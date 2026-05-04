#!/usr/bin/env bash
if command -v ruby >/dev/null 2>&1; then
  exec ruby -x "$0" "$@"
fi
printf 'Ruby is required for structured seed queue updates.\n' >&2
exit 1

#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "pathname"
require "time"
require "yaml"

def usage
  warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] --file PATH [--format text|json] [--queue-format yaml|json] [--scope TEXT]"
end

def rel_path(path, root)
  Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
rescue ArgumentError
  path
end

def slugify(value)
  File.basename(value, File.extname(value)).downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
end

def unique_dir(path)
  return path unless Dir.exist?(path)

  base = path
  suffix = 2
  loop do
    candidate = "#{base}-#{suffix}"
    return candidate unless Dir.exist?(candidate)
    suffix += 1
  end
end

def read_config_paths(vault)
  config = File.join(vault, "ops", "config.yaml")
  inbox = ["inbox"]
  notes = ["notes"]
  return [inbox, notes] unless File.file?(config)

  data = YAML.safe_load(File.read(config), aliases: true) || {}
  paths = data["paths"] || data[:paths] || {}
  inbox_value = paths["inbox"] || paths[:inbox] || data["inbox"] || data[:inbox]
  notes_value = paths["notes"] || paths[:notes] || data["notes"] || data[:notes]
  inbox = Array(inbox_value).compact unless inbox_value.nil?
  notes = Array(notes_value).compact unless notes_value.nil?
  [inbox.empty? ? ["inbox"] : inbox, notes.empty? ? ["notes"] : notes]
rescue Psych::Exception
  [["inbox"], ["notes"]]
end

def resolve_source(vault, requested, inbox_paths)
  return nil if requested.nil? || requested.empty?
  return :url if requested.match?(%r{\A[a-z][a-z0-9+.-]*://}i)

  candidates = []
  candidates << requested
  candidates << File.join(vault, requested) unless Pathname.new(requested).absolute?
  inbox_paths.each { |dir| candidates << File.join(vault, dir, requested) }
  inbox_paths.each do |dir|
    base = File.basename(requested)
    candidates.concat(Dir.glob(File.join(vault, dir, "**", base)))
  end

  candidates.find { |path| File.file?(path) }
end

def content_type(path)
  ext = File.extname(path).downcase
  return "markdown" if ext == ".md"
  return "plain text" if [".txt", ".text"].include?(ext)
  return "structured data" if [".json", ".yaml", ".yml", ".csv", ".tsv"].include?(ext)
  return "source file" if [".rb", ".py", ".js", ".ts", ".go", ".rs"].include?(ext)

  "document"
end

def queue_candidates(vault)
  [
    File.join(vault, "ops", "queue", "queue.json"),
    File.join(vault, "ops", "queue", "queue.yaml"),
    File.join(vault, "ops", "queue.yaml")
  ]
end

def queue_file(vault, requested_format)
  existing = queue_candidates(vault).find { |path| File.file?(path) }
  return existing if existing

  ext = requested_format == "json" ? "json" : "yaml"
  File.join(vault, "ops", "queue", "queue.#{ext}")
end

def load_queue(path)
  return [[], "hash"] unless File.file?(path)

  data =
    if File.extname(path) == ".json"
      JSON.parse(File.read(path))
    else
      YAML.safe_load(File.read(path), aliases: true) || {}
    end
  return [data, "array"] if data.is_a?(Array)
  return [data["tasks"] || [], "hash"] if data.is_a?(Hash)

  [[], "hash"]
rescue JSON::ParserError, Psych::Exception
  [[], "hash"]
end

def write_queue(path, tasks, shape)
  FileUtils.mkdir_p(File.dirname(path))
  if File.extname(path) == ".json"
    data = shape == "array" ? tasks : { "tasks" => tasks }
    File.write(path, "#{JSON.pretty_generate(data)}\n")
  else
    data = shape == "array" ? tasks : { "tasks" => tasks }
    File.write(path, data.to_yaml)
  end
end

def duplicate_matches(vault, id, source_name, source_path, queue_tasks)
  needles = [id, source_name, rel_path(source_path, vault)].map(&:to_s)
  matches = []
  queue_tasks.each do |task|
    text = task.to_s
    matches << "queue: #{task["id"] || task[:id] || text[0, 40]}" if needles.any? { |needle| text.include?(needle) }
  end
  task_file = File.join(vault, "ops", "queue", "#{id}.md")
  matches << "task file: ops/queue/#{id}.md" if File.exist?(task_file)
  Dir.glob(File.join(vault, "ops", "queue", "archive", "*#{id}*")).each do |path|
    next if File.directory?(path) && Dir.empty?(path)
    matches << "archive: #{rel_path(path, vault)}"
  end
  matches.uniq
end

def next_claim_start(vault, queue_tasks)
  max_seen = 0
  Dir.glob(File.join(vault, "ops", "queue", "**", "*.md")).each do |path|
    File.basename(path).scan(/-(\d{3})\.md\z/) { |match| max_seen = [max_seen, match.first.to_i].max }
  end
  queue_tasks.each do |task|
    value = task["next_claim_start"] || task[:next_claim_start]
    max_seen = [max_seen, value.to_i].max if value
  end
  max_seen + 1
end

vault = "."
source_arg = nil
format = "text"
queue_format = nil
scope = "Full document"

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--file"
    source_arg = args.shift
  when "--format"
    format = args.shift
  when "--queue-format"
    queue_format = args.shift
  when "--scope"
    scope = args.shift || ""
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

unless source_arg
  usage
  exit 2
end

unless %w[text json].include?(format)
  warn "Unsupported format: #{format}"
  exit 2
end

if queue_format && !%w[yaml json].include?(queue_format)
  warn "Unsupported queue format: #{queue_format}"
  exit 2
end

vault = File.expand_path(vault)
inbox_paths, = read_config_paths(vault)
source = resolve_source(vault, source_arg, inbox_paths)

if source == :url
  warn "ERROR: seed requires a file path, not a URL or remote resource."
  exit 2
end

unless source
  warn "ERROR: Source file not found: #{source_arg}"
  warn "Checked: explicit path, vault-relative path, and configured inbox paths"
  exit 1
end

source = File.expand_path(source)
id = slugify(source)
queue_path = queue_file(vault, queue_format)
queue_tasks, queue_shape = load_queue(queue_path)
duplicates = duplicate_matches(vault, id, File.basename(source), source, queue_tasks)

if duplicates.any?
  result = {
    "status" => "duplicate",
    "id" => id,
    "source" => rel_path(source, vault),
    "duplicates" => duplicates,
    "mutated" => false
  }
  if format == "json"
    puts JSON.pretty_generate(result)
  else
    puts "Duplicate source detected: #{id}"
    duplicates.each { |match| puts "- #{match}" }
    puts "No queue changes made."
  end
  exit 0
end

ops_queue = File.join(vault, "ops", "queue")
archive_root = File.join(ops_queue, "archive")
FileUtils.mkdir_p(archive_root)

today = Time.now.utc.strftime("%Y-%m-%d")
archive_dir = unique_dir(File.join(archive_root, "#{today}-#{id}"))
FileUtils.mkdir_p(archive_dir)

inbox_abs = inbox_paths.map { |dir| File.expand_path(File.join(vault, dir)) }
source_moved = inbox_abs.any? { |dir| source.start_with?("#{dir}/") || source == dir }
original_source = source
final_source = source

if source_moved
  destination = File.join(archive_dir, File.basename(source))
  if File.exist?(destination)
    warn "ERROR: Archive destination already exists: #{rel_path(destination, vault)}"
    exit 1
  end
  FileUtils.mv(source, destination)
  final_source = destination
end

line_count = File.readlines(final_source, chomp: true).length
claim_start = next_claim_start(vault, queue_tasks)
created = Time.now.utc.iso8601
task_file = File.join(ops_queue, "#{id}.md")

if File.exist?(task_file)
  warn "ERROR: Task file already exists: #{rel_path(task_file, vault)}"
  exit 1
end

FileUtils.mkdir_p(ops_queue)
task_body = <<~TASK
  ---
  id: #{id}
  type: extract
  source: #{rel_path(final_source, vault)}
  original_path: #{rel_path(original_source, vault)}
  archive_folder: #{rel_path(archive_dir, vault)}
  created: #{created}
  next_claim_start: #{claim_start}
  ---

  # Extract notes from #{File.basename(final_source)}

  ## Source
  Original: #{rel_path(original_source, vault)}
  Archived: #{rel_path(final_source, vault)}
  Size: #{line_count} lines
  Content type: #{content_type(final_source)}

  ## Scope
  #{scope.empty? ? "Full document" : scope}

  ## Acceptance Criteria
  - Extract claims, implementation ideas, tensions, and testable hypotheses.
  - Check duplicates against notes during extraction.
  - Preserve source references in created notes.

  ## Execution Notes
  (filled by hippocampusmd-reduce)

  ## Outputs
  (filled by hippocampusmd-reduce)
TASK
File.write(task_file, task_body)

entry = {
  "id" => id,
  "type" => "extract",
  "status" => "pending",
  "source" => rel_path(final_source, vault),
  "file" => "#{id}.md",
  "created" => created,
  "next_claim_start" => claim_start
}
queue_tasks << entry
write_queue(queue_path, queue_tasks, queue_shape)

result = {
  "status" => "seeded",
  "id" => id,
  "source" => rel_path(original_source, vault),
  "final_source" => rel_path(final_source, vault),
  "source_moved" => source_moved,
  "archive_folder" => rel_path(archive_dir, vault),
  "task_file" => rel_path(task_file, vault),
  "queue_file" => rel_path(queue_path, vault),
  "line_count" => line_count,
  "content_type" => content_type(final_source),
  "next_claim_start" => claim_start
}

if format == "json"
  puts JSON.pretty_generate(result)
else
  puts "--=={ seed }==--"
  puts
  puts "Seeded: #{id}"
  puts "Source: #{rel_path(original_source, vault)} -> #{rel_path(final_source, vault)}"
  puts "Source moved: #{source_moved ? "yes" : "no"}"
  puts "Archive folder: #{rel_path(archive_dir, vault)}"
  puts "Size: #{line_count} lines"
  puts "Content type: #{content_type(final_source)}"
  puts
  puts "Task file: #{rel_path(task_file, vault)}"
  puts "Claims will start at: #{claim_start}"
  puts "Queue: #{rel_path(queue_path, vault)} updated with extract task"
  puts
  puts "Next steps:"
  puts "  hippocampusmd-ralph --batch #{id}"
  puts "  hippocampusmd-pipeline can process this queue when ported."
end
