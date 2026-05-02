#!/usr/bin/env bash
if command -v ruby >/dev/null 2>&1; then
  exec ruby -x "$0" "$@"
fi
printf 'Ruby is required for structured graph analysis.\n' >&2
exit 1

#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "json"
require "yaml"
require "set"

def usage
  warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] [--mode health|hubs|sparse|triangles] [--limit N] [--format text|json]"
end

vault = "."
mode = "health"
limit = 25
format = "text"

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--mode"
    mode = args.shift
  when "--limit"
    limit = Integer(args.shift || "")
  when "--format"
    format = args.shift
  when "-h", "--help"
    usage
    exit 0
  when /^--/
    warn "Unknown option: #{arg}"
    usage
    exit 2
  else
    if vault == "."
      vault = arg
    else
      warn "Unexpected argument: #{arg}"
      usage
      exit 2
    end
  end
end

unless %w[health hubs sparse triangles].include?(mode)
  warn "Unsupported mode: #{mode}"
  exit 2
end

unless %w[text json].include?(format)
  warn "Unsupported format: #{format}"
  exit 2
end

unless limit >= 0
  warn "Limit must be a non-negative integer."
  exit 2
end

unless Dir.exist?(vault)
  warn "Vault path is not a directory: #{vault}"
  exit 2
end

vault_abs = File.realpath(vault)

def relpath(path, root)
  path.start_with?("#{root}/") ? path.delete_prefix("#{root}/") : path
end

def safe_load_yaml(path)
  return {} unless File.file?(path)

  text = File.read(path)
  yaml_text =
    if text =~ /\A(?:#.*\n|\s*\n)*---\n(.*?)\n---/m
      Regexp.last_match(1)
    else
      text
    end
  loaded = YAML.safe_load(yaml_text, permitted_classes: [Date, Time, Symbol], aliases: true) || {}
  loaded.is_a?(Hash) ? loaded : {}
rescue Psych::Exception
  {}
end

def vocabulary(root)
  manifest = safe_load_yaml(File.join(root, "ops/derivation-manifest.md"))
  config = safe_load_yaml(File.join(root, "ops/config.yaml"))
  vocab = manifest.fetch("vocabulary", {})
  note = vocab["note"] || "note"
  {
    "notes" => vocab["notes"] || config["notes_dir"] || "notes",
    "note" => note,
    "note_plural" => vocab["note_plural"] || "#{note}s",
    "topic_map" => vocab["topic_map"] || "topic map",
    "topic_map_plural" => vocab["topic_map_plural"] || "topic maps",
    "reflect" => vocab["cmd_reflect"] || vocab["reflect"] || "reflect",
    "reweave" => vocab["cmd_reweave"] || vocab["reweave"] || "reweave"
  }
end

def markdown_files(root, rel_dir)
  dir = File.join(root, rel_dir)
  return [] unless Dir.exist?(dir)

  Dir.glob(File.join(dir, "**", "*.md")).sort
end

def frontmatter(path)
  text = File.read(path)
  if text =~ /\A---\n(.*?)\n---/m
    YAML.safe_load(Regexp.last_match(1), permitted_classes: [Date, Time, Symbol], aliases: true) || {}
  else
    {}
  end
rescue Psych::Exception
  {}
end

def wiki_links(text)
  text.scan(/\[\[([^\]]+)\]\]/).flatten.map do |raw|
    raw.split("|", 2).first.split("#", 2).first.strip
  end.reject(&:empty?).uniq
end

def density(link_count, node_count)
  return nil if node_count < 2

  (link_count.to_f / (node_count * (node_count - 1))).round(4)
end

def pct(numerator, denominator)
  return nil if denominator.to_i <= 0

  ((numerator.to_f * 100) / denominator).round
end

def connected_components(nodes, undirected)
  visited = Set.new
  components = []
  nodes.each do |node|
    next if visited.include?(node)

    stack = [node]
    component = []
    until stack.empty?
      current = stack.pop
      next if visited.include?(current)

      visited << current
      component << current
      (undirected[current] || Set.new).each { |neighbor| stack << neighbor unless visited.include?(neighbor) }
    end
    components << component.sort
  end
  components.sort_by { |component| [-component.length, component.first.to_s] }
end

vocab = vocabulary(vault_abs)
note_files = markdown_files(vault_abs, vocab["notes"])
metadata = {}
note_files.each { |path| metadata[path] = frontmatter(path) }
moc_files = note_files.select { |path| metadata[path]["type"].to_s.downcase == "moc" }
content_files = note_files - moc_files
large_vault = note_files.length > 200

nodes = {}
note_files.each do |path|
  id = File.basename(path, ".md")
  nodes[id] = {
    id: id,
    path: path,
    rel: relpath(path, vault_abs),
    description: metadata[path]["description"].to_s.strip,
    moc: moc_files.include?(path),
    outgoing: wiki_links(File.read(path))
  }
end

target_ids = nodes.keys.to_set
incoming = Hash.new { |hash, key| hash[key] = Set.new }
dangling = []
nodes.each_value do |node|
  node[:outgoing].each do |target|
    if target_ids.include?(target)
      incoming[target] << node[:id] unless target == node[:id]
    else
      dangling << { target: target, source: node[:id] }
    end
  end
end

content_ids = content_files.map { |path| File.basename(path, ".md") }
moc_ids = moc_files.map { |path| File.basename(path, ".md") }
link_count = nodes.values.sum { |node| node[:outgoing].length }
graph_density = density(link_count, [content_ids.length, 1].max)
orphans = content_ids.select { |id| incoming[id].empty? }.sort
moc_covered = content_ids.count do |id|
  nodes.values.any? { |node| node[:moc] && node[:outgoing].include?(id) }
end
moc_sizes = moc_ids.map { |id| { id: id, size: (nodes[id][:outgoing] & content_ids).length } }.sort_by { |entry| [-entry[:size], entry[:id]] }
coverage = pct(moc_covered, content_ids.length)

undirected = Hash.new { |hash, key| hash[key] = Set.new }
content_ids.each { |id| undirected[id] }
nodes.each_value do |node|
  next if node[:moc]

  node[:outgoing].each do |target|
    next unless content_ids.include?(target)

    undirected[node[:id]] << target
    undirected[target] << node[:id]
  end
end
components = connected_components(content_ids, undirected)
isolated = components.select { |component| component.length == 1 }.flatten

authorities = content_ids.map do |id|
  { id: id, incoming: incoming[id].length, outgoing: (nodes[id][:outgoing] & target_ids.to_a).length, description: nodes[id][:description] }
end.sort_by { |entry| [-entry[:incoming], entry[:id]] }
hubs = authorities.sort_by { |entry| [-entry[:outgoing], entry[:id]] }
synthesizers = authorities.select { |entry| entry[:incoming] > 0 && entry[:outgoing] > 0 }
                          .sort_by { |entry| [-(entry[:incoming] + entry[:outgoing]), entry[:id]] }

low_link = content_ids.map do |id|
  total = incoming[id].length + (nodes[id][:outgoing] & target_ids.to_a).length
  { id: id, links: total, description: nodes[id][:description] }
end.select { |entry| entry[:links] < 2 }.sort_by { |entry| [entry[:links], entry[:id]] }

triangles = []
unless large_vault
  nodes.each_value do |parent|
    next if parent[:moc]

    linked = (parent[:outgoing] & content_ids).sort
    linked.combination(2) do |left, right|
      next if nodes[left][:outgoing].include?(right) || nodes[right][:outgoing].include?(left)

      triangles << {
        parent: parent[:id],
        left: left,
        right: right,
        left_description: nodes[left][:description],
        right_description: nodes[right][:description]
      }
    end
  end
end
triangles = triangles.sort_by { |entry| [entry[:parent], entry[:left], entry[:right]] }

counts = {
  notes: content_ids.length,
  mocs: moc_ids.length,
  links: link_count,
  density: graph_density,
  orphans: orphans.length,
  dangling: dangling.length,
  moc_coverage: coverage,
  components: components.length,
  isolated: isolated.length,
  large_vault_approximate: large_vault
}

findings = {
  orphans: orphans.map { |id| { id: id, description: nodes[id][:description] } },
  dangling: dangling.uniq { |entry| [entry[:target], entry[:source]] },
  moc_sizes: moc_sizes,
  authorities: authorities,
  hubs: hubs,
  synthesizers: synthesizers,
  low_link: low_link,
  isolated: isolated.map { |id| { id: id, description: nodes[id][:description] } },
  components: components.map { |component| { size: component.length, nodes: component } },
  triangles: triangles
}

suggestions = []
suggestions << "Run #{vocab["reflect"]} on orphan #{vocab["note_plural"]} to find first connections." if orphans.any?
suggestions << "Create missing #{vocab["note_plural"]} or update stale wiki links." if dangling.any?
suggestions << "Run #{vocab["reweave"]} on low-link #{vocab["note_plural"]} to strengthen traversal." if low_link.any?
suggestions << "Evaluate top triangle pairs as synthesis candidates." if triangles.any?
suggestions << "Metrics approximate for large vault; run narrower graph modes for detailed review." if large_vault

if format == "json"
  puts JSON.pretty_generate(vault: vault_abs, mode: mode, vocabulary: vocab, counts: counts, findings: findings, suggestions: suggestions)
  exit 0
end

def print_limited(items, limit)
  shown = items.first(limit)
  shown.each { |line| puts line }
  omitted = items.length - shown.length
  puts "  ... #{omitted} more omitted by --limit #{limit}" if omitted > 0
end

case mode
when "health"
  puts "--=={ graph health }==--"
  puts
  puts "#{vocab["note_plural"]}: #{counts[:notes]} (plus #{counts[:mocs]} #{vocab["topic_map_plural"]})"
  puts "Connections: #{counts[:links]}"
  puts "Graph density: #{counts[:density] || "N/A"}"
  puts "#{vocab["topic_map"]} coverage: #{counts[:moc_coverage] || "N/A"}%"
  puts
  puts "Orphans (#{counts[:orphans]}):"
  print_limited(findings[:orphans].map { |entry| "  - [[#{entry[:id]}]]#{entry[:description].empty? ? "" : " -- #{entry[:description]}"}" }, limit)
  puts "  none" if findings[:orphans].empty?
  puts
  puts "Dangling Links (#{counts[:dangling]}):"
  print_limited(findings[:dangling].map { |entry| "  - [[#{entry[:target]}]] from [[#{entry[:source]}]]" }, limit)
  puts "  none" if findings[:dangling].empty?
  puts
  puts "#{vocab["topic_map"]} Sizes:"
  print_limited(findings[:moc_sizes].map { |entry| "  - [[#{entry[:id]}]]: #{entry[:size]} #{vocab["note_plural"]}" }, limit)
  puts "  none" if findings[:moc_sizes].empty?
when "hubs"
  puts "--=={ graph hubs }==--"
  puts
  puts "Authorities (incoming links):"
  print_limited(findings[:authorities].map { |entry| "  - [[#{entry[:id]}]]: #{entry[:incoming]} incoming" }, limit)
  puts
  puts "Hubs (outgoing links):"
  print_limited(findings[:hubs].map { |entry| "  - [[#{entry[:id]}]]: #{entry[:outgoing]} outgoing" }, limit)
  puts
  puts "Synthesizers:"
  print_limited(findings[:synthesizers].map { |entry| "  - [[#{entry[:id]}]]: #{entry[:incoming]} in / #{entry[:outgoing]} out" }, limit)
  puts "  none" if findings[:synthesizers].empty?
when "sparse"
  puts "--=={ graph sparse }==--"
  puts
  puts "Low-link #{vocab["note_plural"]} (#{findings[:low_link].length}):"
  print_limited(findings[:low_link].map { |entry| "  - [[#{entry[:id]}]]: #{entry[:links]} total links" }, limit)
  puts "  none" if findings[:low_link].empty?
  puts
  puts "Isolated components (#{findings[:isolated].length}):"
  print_limited(findings[:isolated].map { |entry| "  - [[#{entry[:id]}]]#{entry[:description].empty? ? "" : " -- #{entry[:description]}"}" }, limit)
  puts "  none" if findings[:isolated].empty?
  puts
  puts "Action: #{suggestions.find { |item| item.include?(vocab["reweave"]) } || "No sparse-area action needed."}"
when "triangles"
  puts "--=={ graph triangles }==--"
  puts
  if large_vault
    puts "Triangle search skipped for large vault; run a narrower target analysis."
  else
    puts "Synthesis opportunities (#{findings[:triangles].length}):"
    print_limited(findings[:triangles].map do |entry|
      "  - [[#{entry[:left]}]] + [[#{entry[:right]}]] via [[#{entry[:parent]}]]"
    end, limit)
    puts "  none" if findings[:triangles].empty?
    puts
    puts "Action: #{suggestions.find { |item| item.include?("triangle") } || "No open triangle action needed."}"
  end
end
