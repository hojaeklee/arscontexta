#!/usr/bin/env bash
if command -v ruby >/dev/null 2>&1; then
  exec ruby -x "$0" "$@"
fi
printf 'Ruby is required for structured archive-batch queue updates.\n' >&2
exit 1

#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "time"
require "yaml"

def usage
  warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] --batch ID [--format text|json]"
end

def rel_path(path, root)
  Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
rescue ArgumentError
  path
end

def queue_candidates(vault)
  [
    File.join(vault, "ops", "queue", "queue.json"),
    File.join(vault, "ops", "queue", "queue.yaml"),
    File.join(vault, "ops", "queue.yaml")
  ]
end

def find_queue(vault)
  queue_candidates(vault).find { |path| File.file?(path) }
end

def load_queue(path)
  raw = File.read(path)
  data =
    if File.extname(path) == ".json"
      JSON.parse(raw)
    else
      YAML.safe_load(raw, aliases: true) || {}
    end

  if data.is_a?(Array)
    [{ "tasks" => data }, "array"]
  elsif data.is_a?(Hash)
    data["tasks"] ||= []
    [data, "hash"]
  else
    raise "queue root must be a mapping or list"
  end
rescue JSON::ParserError, Psych::Exception, StandardError => e
  raise "ERROR: Queue file is malformed: #{e.message}"
end

def write_queue(path, data, shape)
  serializable = shape == "array" ? data.fetch("tasks") : data
  if File.extname(path) == ".json"
    File.write(path, "#{JSON.pretty_generate(serializable)}\n")
  else
    File.write(path, serializable.to_yaml)
  end
end

def id_for(task)
  (task["id"] || task[:id]).to_s
end

def status_for(task)
  (task["status"] || task[:status] || "pending").to_s
end

def batch_for(task)
  task["batch"] || task[:batch]
end

def type_for(task)
  (task["type"] || task[:type]).to_s
end

def task_file_for(task)
  task["file"] || task[:file]
end

def task_batch_match?(task, batch)
  id_for(task) == batch || batch_for(task).to_s == batch
end

def completed?(task)
  %w[done completed].include?(status_for(task))
end

def archive_folder_for(tasks, batch, vault)
  extract = tasks.find { |task| id_for(task) == batch && type_for(task) == "extract" } ||
            tasks.find { |task| id_for(task) == batch }
  folder = extract && (extract["archive_folder"] || extract[:archive_folder])
  folder = File.join("ops", "queue", "archive", "#{Time.now.utc.strftime("%Y-%m-%d")}-#{batch}") if folder.to_s.empty?
  Pathname.new(folder).absolute? ? folder : File.join(vault, folder)
end

def unique_summary_path(archive_dir, batch)
  base = File.join(archive_dir, "#{batch}-summary.md")
  return base unless File.exist?(base)

  suffix = 2
  loop do
    candidate = File.join(archive_dir, "#{batch}-summary-#{suffix}.md")
    return candidate unless File.exist?(candidate)
    suffix += 1
  end
end

def task_target(task)
  task["target"] || task[:target] || task["source"] || task[:source] || id_for(task)
end

def summary_body(batch, tasks, archive_dir, vault)
  created = Time.now.utc.iso8601
  source = tasks.find { |task| type_for(task) == "extract" }&.fetch("source", nil)
  lines = []
  lines << "# Batch Summary: #{batch}"
  lines << ""
  lines << "Archived: #{created}"
  lines << "Archive folder: #{rel_path(archive_dir, vault)}"
  lines << "Source: #{source || "unknown"}"
  lines << ""
  lines << "## Counts"
  type_counts = tasks.group_by { |task| type_for(task).empty? ? "unknown" : type_for(task) }
  type_counts.sort.each { |type, grouped| lines << "- #{type}: #{grouped.length}" }
  lines << ""
  lines << "## Archived Tasks"
  tasks.each do |task|
    lines << "- #{id_for(task)} (#{type_for(task).empty? ? "unknown" : type_for(task)}): #{task_target(task)}"
  end
  lines << ""
  "#{lines.join("\n")}\n"
end

vault = "."
batch = nil
format = "text"

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--batch"
    batch = args.shift
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

unless batch && !batch.empty?
  usage
  exit 2
end

unless %w[text json].include?(format)
  warn "Unsupported format: #{format}"
  exit 2
end

vault = File.expand_path(vault)
queue_path = find_queue(vault)
unless queue_path
  warn "ERROR: Queue file not found"
  exit 1
end

begin
  queue_data, queue_shape = load_queue(queue_path)
rescue StandardError => e
  warn e.message
  exit 1
end

tasks = queue_data.fetch("tasks")
batch_tasks = tasks.select { |task| task_batch_match?(task, batch) }
if batch_tasks.empty?
  warn "ERROR: No tasks found for batch #{batch}"
  exit 1
end

incomplete = batch_tasks.reject { |task| completed?(task) }
if incomplete.any?
  warn "ERROR: Batch #{batch} is not complete"
  incomplete.each { |task| warn "- #{id_for(task)} status=#{status_for(task)}" }
  exit 1
end

archive_dir = archive_folder_for(batch_tasks, batch, vault)
FileUtils.mkdir_p(archive_dir)

moves = []
batch_tasks.each do |task|
  file = task_file_for(task)
  next if file.to_s.empty?

  source = Pathname.new(file).absolute? ? file : File.join(vault, "ops", "queue", file)
  next unless File.file?(source)

  destination = File.join(archive_dir, File.basename(file))
  if File.exist?(destination)
    warn "ERROR: Archive destination already exists: #{rel_path(destination, vault)}"
    exit 1
  end
  moves << [source, destination]
end

summary_path = unique_summary_path(archive_dir, batch)
moves.each { |source, destination| FileUtils.mv(source, destination) }
File.write(summary_path, summary_body(batch, batch_tasks, archive_dir, vault))

queue_data["tasks"] = tasks.reject { |task| task_batch_match?(task, batch) }
write_queue(queue_path, queue_data, queue_shape)

result = {
  "batch" => batch,
  "tasks_archived" => batch_tasks.length,
  "files_moved" => moves.length,
  "archive_folder" => rel_path(archive_dir, vault),
  "summary" => rel_path(summary_path, vault),
  "queue_file" => rel_path(queue_path, vault)
}

if format == "json"
  puts JSON.pretty_generate(result)
else
  puts "--=={ archive-batch }==--"
  puts
  puts "Archived batch: #{batch}"
  puts "Tasks archived: #{batch_tasks.length}"
  puts "Task files moved: #{moves.length}"
  puts "Archive folder: #{rel_path(archive_dir, vault)}"
  puts "Summary: #{rel_path(summary_path, vault)}"
  puts "Queue: #{rel_path(queue_path, vault)} updated"
end
