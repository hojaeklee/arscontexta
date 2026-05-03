#!/usr/bin/env bash
if command -v ruby >/dev/null 2>&1; then
  exec ruby -x "$0" "$@"
fi
printf 'Ruby is required for structured pipeline planning.\n' >&2
exit 1

#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"
require "yaml"

def usage
  warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] --plan --file PATH|--status --batch ID|--ready-to-archive --batch ID [--format text|json]"
end

def rel_path(path, root)
  Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
rescue ArgumentError
  path
end

def slugify(value)
  File.basename(value, File.extname(value)).downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
end

def read_inbox_paths(vault)
  config = File.join(vault, "ops", "config.yaml")
  return ["inbox"] unless File.file?(config)

  data = YAML.safe_load(File.read(config), aliases: true) || {}
  paths = data["paths"] || data[:paths] || {}
  inbox_value = paths["inbox"] || paths[:inbox] || data["inbox"] || data[:inbox]
  inbox = Array(inbox_value).compact
  inbox.empty? ? ["inbox"] : inbox
rescue Psych::Exception
  ["inbox"]
end

def resolve_source(vault, requested, inbox_paths)
  return nil if requested.nil? || requested.empty?

  candidates = []
  candidates << requested
  candidates << File.join(vault, requested) unless Pathname.new(requested).absolute?
  inbox_paths.each { |dir| candidates << File.join(vault, dir, requested) }
  inbox_paths.each do |dir|
    candidates.concat(Dir.glob(File.join(vault, dir, "**", File.basename(requested))))
  end
  candidates.find { |path| File.file?(path) }
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
  return [{ "tasks" => [] }, nil] unless path

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

def id_for(task)
  (task["id"] || task[:id]).to_s
end

def status_for(task)
  (task["status"] || task[:status] || "pending").to_s
end

def phase_for(task)
  task["current_phase"] || task[:current_phase] || (task["type"] == "extract" ? "extract" : nil)
end

def batch_for(task)
  task["batch"] || task[:batch]
end

def target_for(task)
  task["target"] || task[:target] || task["source"] || task[:source] || id_for(task)
end

def task_batch_match?(task, batch)
  id_for(task) == batch || batch_for(task).to_s == batch
end

def tasks_for_batch(tasks, batch)
  tasks.select { |task| task_batch_match?(task, batch) }
end

def count_statuses(tasks)
  counts = Hash.new(0)
  tasks.each do |task|
    case status_for(task)
    when "pending" then counts["pending"] += 1
    when "done", "completed" then counts["done"] += 1
    when "blocked" then counts["blocked"] += 1
    when "active", "in_progress" then counts["active"] += 1
    else counts[status_for(task)] += 1
    end
  end
  {
    "total" => tasks.length,
    "pending" => counts["pending"],
    "active" => counts["active"],
    "blocked" => counts["blocked"],
    "done" => counts["done"]
  }
end

def phase_distribution(tasks)
  distribution = Hash.new(0)
  tasks.each do |task|
    phase = phase_for(task)
    next unless phase
    distribution[phase] += 1
  end
  distribution
end

def ready_to_archive?(tasks)
  !tasks.empty? && tasks.all? { |task| %w[done completed].include?(status_for(task)) }
end

def next_action(batch, counts, ready)
  return "run arscontexta-archive-batch --batch #{batch}" if ready
  return "resolve blocked tasks, then run arscontexta-ralph --batch #{batch}" if counts["blocked"].positive?
  return "wait for active tasks or inspect with arscontexta-ralph --batch #{batch}" if counts["active"].positive?
  return "run arscontexta-ralph --batch #{batch}" if counts["pending"].positive?

  "no tasks found for batch #{batch}"
end

vault = "."
mode = nil
source_arg = nil
batch = nil
format = "text"

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--plan"
    mode = :plan
  when "--status"
    mode = :status
  when "--ready-to-archive"
    mode = :ready
  when "--file"
    source_arg = args.shift
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

unless mode
  usage
  exit 2
end

unless %w[text json].include?(format)
  warn "Unsupported format: #{format}"
  exit 2
end

vault = File.expand_path(vault)
queue_path = find_queue(vault)

begin
  queue_data, = load_queue(queue_path)
rescue StandardError => e
  warn e.message
  exit 1
end
tasks = queue_data.fetch("tasks")

case mode
when :plan
  unless source_arg
    usage
    exit 2
  end
  source = resolve_source(vault, source_arg, read_inbox_paths(vault))
  unless source
    warn "ERROR: Source file not found: #{source_arg}"
    exit 1
  end
  source = File.expand_path(source)
  batch_id = slugify(source)
  matching_tasks = tasks_for_batch(tasks, batch_id)
  queue_status = matching_tasks.empty? ? "unseeded" : "already queued"
  action = if matching_tasks.empty?
             "run arscontexta-seed --file #{rel_path(source, vault)}"
           else
             "run arscontexta-ralph --batch #{batch_id}"
           end
  result = {
    "source" => rel_path(source, vault),
    "batch" => batch_id,
    "queue_status" => queue_status,
    "queue_file" => queue_path ? rel_path(queue_path, vault) : nil,
    "next_action" => action,
    "ready_to_archive" => ready_to_archive?(matching_tasks)
  }
  if format == "json"
    puts JSON.pretty_generate(result)
  else
    puts "Pipeline plan"
    puts "Source: #{result["source"]}"
    puts "Batch: #{batch_id}"
    puts "Queue status: #{queue_status}"
    puts "Next action: #{action}"
    puts "Then: run arscontexta-ralph --batch #{batch_id}"
  end
when :status, :ready
  unless batch
    usage
    exit 2
  end
  batch_tasks = tasks_for_batch(tasks, batch)
  counts = count_statuses(batch_tasks)
  distribution = phase_distribution(batch_tasks)
  blocked = batch_tasks.select { |task| status_for(task) == "blocked" }
  ready = ready_to_archive?(batch_tasks)
  action = next_action(batch, counts, ready)
  result = {
    "batch" => batch,
    "queue_file" => queue_path ? rel_path(queue_path, vault) : nil,
    "counts" => counts,
    "phase_distribution" => distribution,
    "ready_to_archive" => ready,
    "next_action" => action,
    "tasks" => batch_tasks.map do |task|
      {
        "id" => id_for(task),
        "status" => status_for(task),
        "phase" => phase_for(task),
        "target" => target_for(task),
        "blocked_reason" => task["blocked_reason"] || task[:blocked_reason]
      }
    end
  }
  if format == "json"
    puts JSON.pretty_generate(result)
  elsif mode == :ready
    puts "Batch: #{batch}"
    puts "Ready to archive: #{ready ? "yes" : "no"}"
    puts "Next action: #{action}"
  else
    puts "Pipeline status"
    puts "Batch: #{batch}"
    puts "Queue file: #{queue_path ? rel_path(queue_path, vault) : "missing"}"
    puts "Total: #{counts["total"]} | Pending: #{counts["pending"]} | Active: #{counts["active"]} | Blocked: #{counts["blocked"]} | Done: #{counts["done"]}"
    puts
    puts "Phase distribution:"
    if distribution.empty?
      puts "  None"
    else
      distribution.sort.each { |phase, count| puts "  #{phase}: #{count}" }
    end
    if blocked.any?
      puts
      puts "Blocked tasks:"
      blocked.each do |task|
        puts "  #{id_for(task)} -- #{phase_for(task)} -- #{task["blocked_reason"] || task[:blocked_reason] || "no reason"}"
      end
    end
    puts
    puts "Ready to archive: #{ready ? "yes" : "no"}"
    puts "Next action: #{action}"
  end
end
