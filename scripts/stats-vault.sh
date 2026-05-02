#!/usr/bin/env bash
if command -v ruby >/dev/null 2>&1; then
  exec ruby -x "$0" "$@"
fi
printf 'Ruby is required for structured vault statistics.\n' >&2
exit 1

#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "json"
require "yaml"
require "set"

def usage
  warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] [--share] [--limit N] [--format text|json]"
end

vault = "."
share = false
limit = 25
format = "text"

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--share"
    share = true
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
    "inbox" => vocab["inbox"] || config["inbox_dir"] || "inbox",
    "note" => note,
    "note_plural" => vocab["note_plural"] || "#{note}s",
    "topic_map" => vocab["topic_map"] || "topic map",
    "topic_map_plural" => vocab["topic_map_plural"] || "topic maps",
    "reflect" => vocab["cmd_reflect"] || vocab["reflect"] || "reflect",
    "rethink" => vocab["rethink"] || vocab["cmd_rethink"] || "rethink"
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
  end.reject(&:empty?)
end

def note_title(path)
  File.basename(path, ".md")
end

def queue_file(root)
  ["ops/queue/queue.json", "ops/queue/queue.yaml", "ops/queue.yaml"].find do |rel|
    File.file?(File.join(root, rel))
  end
end

def normalize_status(status)
  case status.to_s.downcase
  when "pending", "todo", "queued" then "pending"
  when "active", "in_progress", "in-progress", "running", "current" then "active"
  when "done", "completed", "complete" then "completed"
  when "blocked", "waiting" then "blocked"
  else
    status.to_s.empty? ? "unknown" : status.to_s.downcase
  end
end

def queue_tasks_from_data(data)
  raw =
    if data.is_a?(Hash) && data["tasks"].is_a?(Array)
      data["tasks"]
    elsif data.is_a?(Array)
      data
    elsif data.is_a?(Hash)
      data.values.find { |value| value.is_a?(Array) } || []
    else
      []
    end

  raw.select { |entry| entry.is_a?(Hash) }.map { |entry| normalize_status(entry["status"]) }
end

def parse_queue(root)
  rel = queue_file(root)
  return { exists: false, file: nil, counts: Hash.new(0) } unless rel

  path = File.join(root, rel)
  data = rel.end_with?(".json") ? JSON.parse(File.read(path)) : YAML.safe_load(File.read(path), permitted_classes: [Date, Time, Symbol], aliases: true)
  counts = Hash.new(0)
  queue_tasks_from_data(data || {}).each { |status| counts[status] += 1 }
  { exists: true, file: rel, counts: counts }
rescue JSON::ParserError, Psych::Exception => e
  { exists: true, file: rel, counts: Hash.new(0), error: e.message }
end

def pending_status_count(root, rel_dir, statuses)
  markdown_files(root, rel_dir).count do |path|
    text = File.read(path)
    statuses.any? { |status| text.match?(/^status:\s*#{Regexp.escape(status)}\s*$/i) }
  end
end

def count_files(root, rel_dir)
  dir = File.join(root, rel_dir)
  return 0 unless Dir.exist?(dir)

  Dir.glob(File.join(dir, "*.md")).length
end

def oldest_age_days(files)
  return nil if files.empty?

  oldest = files.min_by { |path| File.mtime(path) }
  ((Time.now - File.mtime(oldest)) / 86_400).floor
end

def created_this_week?(metadata)
  value = metadata["created"]
  return false unless value

  date = value.is_a?(Date) ? value : Date.parse(value.to_s)
  date >= Date.today - 7
rescue ArgumentError
  false
end

def pct(numerator, denominator)
  return nil if denominator.to_i <= 0

  ((numerator.to_f * 100) / denominator).round
end

def decimal(numerator, denominator, places = 2)
  return nil if denominator.to_i <= 0

  (numerator.to_f / denominator).round(places)
end

vocab = vocabulary(vault_abs)
notes_dir = vocab["notes"]
inbox_dir = vocab["inbox"]
note_files = markdown_files(vault_abs, notes_dir)
inbox_files = markdown_files(vault_abs, inbox_dir)
metadata = {}
note_files.each { |path| metadata[path] = frontmatter(path) }
moc_files = note_files.select { |path| metadata[path]["type"].to_s.downcase == "moc" }
content_files = note_files - moc_files

links_by_file = {}
all_links = []
note_files.each do |path|
  links = wiki_links(File.read(path))
  links_by_file[path] = links
  all_links.concat(links)
end

targets = Set.new
note_files.each do |path|
  rel = relpath(path, vault_abs).delete_suffix(".md")
  targets << rel
  targets << File.basename(rel)
end

incoming = Hash.new(0)
links_by_file.each do |source, links|
  links.each do |target|
    next unless targets.include?(target)

    incoming[target] += 1
  end
end

large_vault = note_files.length > 200
orphans =
  if large_vault
    content_files.count { |path| !all_links.include?(note_title(path)) }
  else
    content_files.count { |path| incoming[note_title(path)].zero? }
  end
dangling = all_links.uniq.count { |target| !targets.include?(target) }
missing_desc = note_files.count { |path| metadata[path]["description"].to_s.strip.empty? }
missing_topics = note_files.count { |path| !metadata[path].key?("topics") || metadata[path]["topics"].to_s.strip.empty? || metadata[path]["topics"] == [] }
schema_compliance = pct(note_files.length - [missing_desc, missing_topics].max, note_files.length)
topic_links = metadata.values.flat_map { |data| wiki_links(data["topics"].to_s) }.uniq
moc_coverage = pct(content_files.count { |path| !metadata[path]["topics"].to_s.strip.empty? && metadata[path]["topics"] != [] }, content_files.length)
queue = parse_queue(vault_abs)
processed_pct = pct(content_files.length, content_files.length + inbox_files.length)
this_week_files = content_files.select { |path| created_this_week?(metadata[path]) }
this_week_links = this_week_files.sum { |path| links_by_file[path].length }
self_files = count_files(vault_abs, "self")
methodology_count = count_files(vault_abs, "ops/methodology")
observations_pending = pending_status_count(vault_abs, "ops/observations", ["pending"])
tensions_pending = pending_status_count(vault_abs, "ops/tensions", ["pending", "open"])
session_count = count_files(vault_abs, "ops/sessions")
health_reports = count_files(vault_abs, "ops/health")
latest_health = Dir.glob(File.join(vault_abs, "ops/health", "*.md")).sort.last

metrics = {
  "total_files" => note_files.length,
  "notes" => content_files.length,
  "mocs" => moc_files.length,
  "connections" => all_links.length,
  "avg_links" => decimal(all_links.length, [content_files.length, 1].max, 1) || 0,
  "density" => decimal(all_links.length, content_files.length * [content_files.length - 1, 1].max, 4),
  "topics" => topic_links.length,
  "moc_coverage" => moc_coverage,
  "orphans" => orphans,
  "dangling" => dangling,
  "schema_compliance" => schema_compliance,
  "missing_description" => missing_desc,
  "missing_topics" => missing_topics,
  "inbox" => inbox_files.length,
  "oldest_inbox_age_days" => oldest_age_days(inbox_files),
  "queue_pending" => queue[:counts]["pending"],
  "queue_done" => queue[:counts]["completed"],
  "queue_blocked" => queue[:counts]["blocked"],
  "processed_pct" => processed_pct,
  "this_week_notes" => this_week_files.length,
  "this_week_links" => this_week_links,
  "self_space" => self_files > 0 ? "enabled (#{self_files} files)" : "disabled",
  "methodology" => methodology_count,
  "observations_pending" => observations_pending,
  "tensions_pending" => tensions_pending,
  "sessions" => session_count,
  "health_reports" => health_reports,
  "latest_health" => latest_health ? relpath(latest_health, vault_abs) : nil,
  "large_vault_approximate" => large_vault
}

notes = []
notes << "#{orphans} orphan #{vocab["note_plural"]} -- run arscontexta-graph for details" if orphans > 0
notes << "#{dangling} dangling links -- run arscontexta-graph to identify broken links" if dangling > 0
notes << "Schema compliance below 90% -- some #{vocab["note_plural"]} are missing required fields" if schema_compliance && schema_compliance < 90
notes << "#{observations_pending} pending observations -- consider #{vocab["rethink"]}" if observations_pending >= 10
notes << "#{tensions_pending} open tensions -- consider #{vocab["rethink"]}" if tensions_pending >= 5
notes << "Graph density is low -- run #{vocab["reflect"]} to strengthen the network" if metrics["density"] && metrics["density"] < 0.02 && content_files.length > 5
notes << "More content in inbox than in #{vocab["notes"]}/ -- consider processing backlog" if processed_pct && processed_pct < 50
notes << "No new #{vocab["note_plural"]} this week" if note_files.any? && this_week_files.empty?
notes << "Metrics approximate for large vault. Run arscontexta-graph for precise graph analysis." if large_vault

if format == "json"
  puts JSON.pretty_generate(vault: vault_abs, vocabulary: vocab, queue_file: queue[:file], metrics: metrics, notes: notes)
  exit 0
end

if share
  puts "## My Knowledge Graph"
  puts
  puts "- **#{metrics["notes"]}** #{vocab["note_plural"]} with **#{metrics["connections"]}** connections (avg #{metrics["avg_links"]} per #{vocab["note"]})"
  puts "- **#{metrics["mocs"]}** #{vocab["topic_map_plural"]} covering #{metrics["moc_coverage"] || "N/A"}% of #{vocab["note_plural"]}"
  puts "- Schema compliance: #{metrics["schema_compliance"] || "N/A"}%"
  puts "- This week: +#{metrics["this_week_notes"]} #{vocab["note_plural"]}, +#{metrics["this_week_links"]} connections"
  puts "- Graph density: #{metrics["density"] || "N/A"}"
  puts
  puts "*Built with Ars Contexta*"
  exit 0
end

if note_files.empty?
  puts "--=={ stats }==--"
  puts
  puts "Your knowledge graph is new. Start capturing to see it grow."
  puts
  puts "Knowledge Graph"
  puts "==============="
  puts "#{vocab["note_plural"]}: 0"
  puts "Connections: 0"
  puts "#{vocab["topic_map_plural"]}: 0"
  puts "Topics: 0"
  puts
  puts "Generated by Ars Contexta"
  exit 0
end

bar_pct = processed_pct || 0
filled = [[bar_pct / 5, 20].min, 0].max
bar = "[#{"=" * filled}#{" " * (20 - filled)}] #{bar_pct}%"

puts "--=={ stats }==--"
puts
puts "Knowledge Graph"
puts "==============="
puts "#{vocab["note_plural"]}: #{metrics["notes"]}"
puts "Connections: #{metrics["connections"]} (avg #{metrics["avg_links"]} per #{vocab["note"]})"
puts "#{vocab["topic_map_plural"]}: #{metrics["mocs"]} (covering #{metrics["moc_coverage"] || "N/A"}% of #{vocab["note_plural"]})"
puts "Topics: #{metrics["topics"]}"
puts
puts "Health"
puts "======"
puts "Orphans: #{metrics["orphans"]}"
puts "Dangling: #{metrics["dangling"]}"
puts "Schema: #{metrics["schema_compliance"] || "N/A"}% compliant"
puts
if queue[:exists] || inbox_files.any?
  puts "Pipeline"
  puts "========"
  puts "Processed: #{bar}"
  oldest = metrics["oldest_inbox_age_days"] ? " (oldest #{metrics["oldest_inbox_age_days"]}d)" : ""
  puts "Inbox: #{metrics["inbox"]} items#{oldest}"
  if queue[:exists]
    puts "Queue: #{metrics["queue_pending"]} pending, #{metrics["queue_blocked"]} blocked, #{metrics["queue_done"]} done"
  end
  puts
end
puts "Growth"
puts "======"
puts "This week: +#{metrics["this_week_notes"]} #{vocab["note_plural"]}, +#{metrics["this_week_links"]} connections"
puts "Graph density: #{metrics["density"] || "N/A"}"
puts
puts "System"
puts "======"
puts "Self space: #{metrics["self_space"]}"
puts "Methodology: #{metrics["methodology"]} learned patterns"
puts "Observations: #{metrics["observations_pending"]} pending"
puts "Tensions: #{metrics["tensions_pending"]} open"
puts "Sessions: #{metrics["sessions"]} captured"
puts "Health reports: #{metrics["health_reports"]}#{metrics["latest_health"] ? " (latest #{metrics["latest_health"]})" : ""}"
puts
unless notes.empty?
  puts "Notes"
  puts "====="
  notes.first(limit).each { |note| puts "- #{note}" }
end
