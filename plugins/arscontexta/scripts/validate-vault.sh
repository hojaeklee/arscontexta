#!/usr/bin/env bash
if command -v ruby >/dev/null 2>&1; then
  exec ruby -x "$0" "$@"
fi
printf 'Ruby is required for structured YAML validation.\n' >&2
exit 1

#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "date"
require "set"
require "json"
require "open3"

def usage
  warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] --file PATH|--changed|--all [--limit N] [--format text|json]"
end

vault = "."
target_file = nil
mode = nil
limit = 25
format = "text"

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--file"
    target_file = args.shift
    mode = :file
  when "--changed"
    mode = :changed
  when "--all"
    mode = :all
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

unless mode
  warn "Choose one of --file, --changed, or --all."
  usage
  exit 2
end

if mode == :file && (target_file.nil? || target_file.empty?)
  warn "--file requires a path."
  usage
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
  full = File.expand_path(path)
  root_prefix = "#{root}/"
  full.start_with?(root_prefix) ? full.delete_prefix(root_prefix) : path
end

def read_frontmatter(path)
  text = File.read(path)
  lines = text.lines
  return [nil, text, "missing opening delimiter", []] unless lines.first&.chomp == "---"

  close_index = lines[1..]&.index { |line| line.chomp == "---" }
  return [nil, text, "missing closing delimiter", []] unless close_index

  close_line = close_index + 1
  yaml_text = lines[1...close_line].join
  body = lines[(close_line + 1)..]&.join || ""
  duplicate_keys = duplicate_top_level_keys(yaml_text)
  begin
    data = YAML.safe_load(yaml_text, permitted_classes: [Date, Time, Symbol], aliases: true)
    data = {} unless data.is_a?(Hash)
    [data, body, nil, duplicate_keys]
  rescue Psych::Exception => e
    [nil, body, e.message, duplicate_keys]
  end
end

def duplicate_top_level_keys(yaml_text)
  seen = Set.new
  dupes = Set.new
  yaml_text.each_line do |line|
    next if line.strip.empty? || line.lstrip.start_with?("#")
    next unless line =~ /\A([A-Za-z0-9_-]+):/

    key = Regexp.last_match(1)
    dupes << key if seen.include?(key)
    seen << key
  end
  dupes.to_a.sort
end

def config_from_yaml(path)
  return {} unless File.file?(path)

  data, = read_frontmatter(path)
  if data.nil? || data.empty?
    begin
      loaded = YAML.safe_load(File.read(path), permitted_classes: [Date, Time, Symbol], aliases: true)
      return loaded.is_a?(Hash) ? loaded : {}
    rescue Psych::Exception
      return {}
    end
  end
  data
end

def manifest_config(path)
  return {} unless File.file?(path)

  text = File.read(path)
  match = text.match(/\A(?:#.*\n|\s*\n)*---\n(.*?)\n---/m)
  yaml_text = match ? match[1] : text
  loaded = YAML.safe_load(yaml_text, permitted_classes: [Date, Time, Symbol], aliases: true)
  loaded.is_a?(Hash) ? loaded : {}
rescue Psych::Exception
  {}
end

manifest = manifest_config(File.join(vault_abs, "ops/derivation-manifest.md"))
ops_config = config_from_yaml(File.join(vault_abs, "ops/config.yaml"))
vocabulary = manifest.fetch("vocabulary", {})
notes_dir = vocabulary["notes"] || ops_config["notes_dir"] || "notes"
templates_dir = vocabulary["templates"] || ops_config["templates_dir"] || "templates"
template_dirs = [templates_dir, "templates", "ops/templates"].compact.uniq

def markdown_files(root)
  Dir.glob(File.join(root, "**", "*.md"), File::FNM_DOTMATCH).reject do |path|
    path.split(File::SEPARATOR).any? { |part| %w[.git node_modules .obsidian].include?(part) }
  end.sort
end

note_targets = Set.new
markdown_files(vault_abs).each do |path|
  rel = relpath(path, vault_abs)
  no_ext = rel.delete_suffix(".md")
  note_targets << no_ext
  note_targets << File.basename(no_ext)
end

def schema_from_template(path)
  data, = read_frontmatter(path)
  return nil unless data.is_a?(Hash)

  schema = data["_schema"]
  schema.is_a?(Hash) ? schema : nil
end

templates = {}
template_dirs.each do |dir|
  abs = File.join(vault_abs, dir)
  next unless Dir.exist?(abs)

  markdown_files(abs).each do |path|
    schema = schema_from_template(path)
    next unless schema

    name = File.basename(path, ".md")
    templates[name] = { path: path, schema: schema }
  end
end

def template_for(frontmatter, templates)
  type = frontmatter.is_a?(Hash) ? frontmatter["type"].to_s : ""
  candidates = []
  candidates << type unless type.empty?
  candidates << "#{type}-note" unless type.empty?
  candidates << "moc" if type == "moc"
  candidates << "base-note"
  candidates << "note"
  candidates.each do |name|
    return templates[name] if templates.key?(name)
  end
  templates.values.first
end

def changed_targets(root)
  unless system("git", "-C", root, "rev-parse", "--is-inside-work-tree", out: File::NULL, err: File::NULL)
    warn "Cannot use --changed outside a git worktree."
    exit 2
  end

  commands = [
    %w[diff --name-only --diff-filter=ACMRT HEAD -- *.md],
    %w[diff --cached --name-only --diff-filter=ACMRT -- *.md],
    %w[ls-files --others --exclude-standard -- *.md]
  ]
  commands.flat_map do |cmd|
    out, = Open3.capture2("git", "-C", root, *cmd)
    out.lines.map(&:chomp)
  end.uniq.select { |rel| File.file?(File.join(root, rel)) }.sort
end

targets =
  case mode
  when :file
    path = target_file.start_with?("/") ? target_file : File.join(vault_abs, target_file)
    unless File.file?(path)
      warn "Target file does not exist: #{target_file}"
      exit 2
    end
    [relpath(path, vault_abs)]
  when :changed
    changed_targets(vault_abs)
  when :all
    dir = File.join(vault_abs, notes_dir)
    Dir.exist?(dir) ? markdown_files(dir).map { |path| relpath(path, vault_abs) } : []
  end

findings = []

def add_finding(findings, level, file, check, detail, fix = nil)
  findings << {
    level: level,
    file: file,
    check: check,
    detail: detail,
    fix: fix
  }.compact
end

def strip_code_for_links(text)
  stripped = text.gsub(/```.*?```/m, "")
  stripped.gsub(/`[^`\n]*`/, "")
end

def wiki_links(text)
  strip_code_for_links(text).scan(/\[\[([^\]]+)\]\]/).flatten.map do |raw|
    raw.split("|", 2).first.split("#", 2).first.strip
  end.reject(&:empty?)
end

def value_present?(value)
  case value
  when nil then false
  when String then !value.strip.empty?
  when Array, Hash then !value.empty?
  else true
  end
end

def normalize_text(value)
  value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
end

targets.each do |rel|
  path = File.join(vault_abs, rel)
  next unless File.file?(path) && rel.end_with?(".md")

  frontmatter, body, yaml_error, duplicate_keys = read_frontmatter(path)
  title = File.basename(rel, ".md")

  if yaml_error
    add_finding(findings, "FAIL", rel, "yaml", "Frontmatter is invalid: #{yaml_error}.", "Repair YAML delimiters and syntax before validating fields.")
    frontmatter = {}
  end

  duplicate_keys.each do |key|
    add_finding(findings, "FAIL", rel, "yaml", "Duplicate top-level frontmatter key: #{key}.", "Keep one #{key} field and merge any intended values.")
  end

  template = template_for(frontmatter, templates)
  schema = template&.fetch(:schema, nil) || {}
  required = Array(schema["required"])
  required = %w[description topics] if required.empty?
  optional = Array(schema["optional"])
  enum_map = schema["enums"].is_a?(Hash) ? schema["enums"] : {}
  known_fields = (required + optional + enum_map.keys + ["_schema"]).to_set

  frontmatter.each_key do |key|
    next unless template
    next if known_fields.include?(key)

    add_finding(findings, "WARN", rel, "schema", "Unknown frontmatter field: #{key}.", "Remove #{key} or add it to the template _schema optional fields.")
  end

  required.each do |field|
    next if value_present?(frontmatter[field])

    add_finding(findings, "FAIL", rel, field, "Required field is missing or empty: #{field}.", "Add a non-empty #{field} value.")
  end

  enum_map.each do |field, valid_values|
    next unless frontmatter.key?(field)

    values = frontmatter[field].is_a?(Array) ? frontmatter[field] : [frontmatter[field]]
    valid = Array(valid_values).map(&:to_s)
    values.each do |value|
      next if valid.include?(value.to_s)

      add_finding(findings, "WARN", rel, field, "#{field} value #{value.inspect} is not in template enum: #{valid.join(", ")}.", "Use one of: #{valid.join(", ")}.")
    end
  end

  if frontmatter.key?("description")
    desc = frontmatter["description"].to_s.strip
    if desc.empty?
      add_finding(findings, "FAIL", rel, "description", "Description is empty.", "Add one sentence that gives mechanism, scope, implication, or context beyond the title.")
    else
      add_finding(findings, "WARN", rel, "description", "Description is #{desc.length} chars; expected roughly 50-200 chars.", "Expand or tighten the description.") unless (50..200).cover?(desc.length)
      desc_norm = normalize_text(desc)
      title_norm = normalize_text(title)
      if desc_norm == title_norm || (!title_norm.empty? && (desc_norm.include?(title_norm) || title_norm.include?(desc_norm)))
        add_finding(findings, "WARN", rel, "description", "Description appears to restate the title.", "Add mechanism, scope, implication, or context beyond the title.")
      end
      if desc.end_with?(".")
        add_finding(findings, "WARN", rel, "description", "Description ends with a period.", "Remove the trailing period to match Ars Contexta convention.")
      end
      if desc[0...-1].to_s.match?(/[.!?]/)
        add_finding(findings, "WARN", rel, "description", "Description appears to contain multiple sentences.", "Keep the description to one coherent sentence.")
      end
    end
  end

  topics_value = frontmatter["topics"]
  topic_links = wiki_links(topics_value.is_a?(String) ? topics_value : topics_value.to_s)
  if frontmatter.key?("topics") && topic_links.empty?
    add_finding(findings, "FAIL", rel, "topics", "Topics field does not contain a wiki link.", "Add at least one topic map wiki link, such as [[index]].")
  end

  links = wiki_links(File.read(path))
  links.each do |target|
    next if note_targets.include?(target)

    add_finding(findings, "WARN", rel, "links", "Unresolved wiki link: [[#{target}]].", "Create the target note or update the link text to an existing filename.")
  end

  if frontmatter.key?("relevant_notes")
    entries = frontmatter["relevant_notes"].is_a?(Array) ? frontmatter["relevant_notes"] : [frontmatter["relevant_notes"]]
    entries.each do |entry|
      text = entry.to_s
      next if text.strip.empty?

      if wiki_links(text).empty?
        add_finding(findings, "WARN", rel, "relevant_notes", "Relevant note entry has no wiki link: #{text.inspect}.", "Use the format [[note]] -- relationship context.")
      elsif !text.include?("--") && !text.include?("—")
        add_finding(findings, "WARN", rel, "relevant_notes", "Relevant note entry lacks relationship context: #{text.inspect}.", "Add -- followed by a short relationship phrase.")
      end
    end
  end
end

counts = Hash.new(0)
findings.each { |finding| counts[finding[:level]] += 1 }
overall = counts["FAIL"].positive? ? "FAIL" : counts["WARN"].positive? ? "WARN" : "PASS"

if format == "json"
  puts JSON.pretty_generate(
    overall: overall,
    vault: vault_abs,
    mode: mode.to_s,
    files_checked: targets.length,
    pass: overall == "PASS" ? targets.length : 0,
    warn: counts["WARN"],
    fail: counts["FAIL"],
    findings: findings
  )
  exit 0
end

puts "Ars Contexta validation"
puts "Overall: #{overall}"
puts "Vault: #{vault_abs}"
puts "Mode: #{mode}"
puts "Files checked: #{targets.length}"
puts "Findings: #{findings.length}"
puts

if findings.empty?
  puts "PASS:"
  puts "- All checked files passed validation."
  puts
  puts "WARN:"
  puts "- none"
  puts
  puts "FAIL:"
  puts "- none"
else
  %w[FAIL WARN].each do |level|
    level_findings = findings.select { |finding| finding[:level] == level }
    puts "#{level}:"
    if level_findings.empty?
      puts "- none"
    else
      level_findings.first(limit).each do |finding|
        puts "- #{finding[:file]}: #{finding[:check]}: #{finding[:detail]}"
      end
      omitted = level_findings.length - limit
      puts "- ... #{omitted} more omitted by --limit #{limit}" if omitted.positive?
    end
    puts
  end

  fixes = findings.map { |finding| [finding[:file], finding[:check], finding[:fix]] if finding[:fix] }.compact.uniq
  unless fixes.empty?
    puts "Suggested Fixes:"
    fixes.first(limit).each do |file, check, fix|
      puts "- #{file}: #{check}: #{fix}"
    end
  end
end
