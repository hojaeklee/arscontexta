#!/usr/bin/env bash
if command -v ruby >/dev/null 2>&1; then
  exec ruby -x "$0" "$@"
fi
printf 'Ruby is required for structured Ralph queue parsing.\n' >&2
exit 1

#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "time"
require "yaml"

def usage
  warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] --dry-run|--advance TASK_ID|--fail TASK_ID --reason TEXT [--limit N] [--batch ID] [--type PHASE] [--format text|json]"
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
  return [{ "phase_order" => default_phase_order, "tasks" => [] }, "hash"] unless path

  raw = File.read(path)
  data =
    if File.extname(path) == ".json"
      JSON.parse(raw)
    else
      YAML.safe_load(raw, aliases: true) || {}
    end
  if data.is_a?(Array)
    [{ "phase_order" => default_phase_order, "tasks" => data }, "array"]
  elsif data.is_a?(Hash)
    data["phase_order"] ||= default_phase_order
    data["tasks"] ||= []
    [data, "hash"]
  else
    raise "queue root must be a mapping or list"
  end
rescue JSON::ParserError, Psych::Exception, StandardError => e
  raise "ERROR: Queue file is malformed: #{e.message}"
end

def write_queue(path, data, shape)
  FileUtils.mkdir_p(File.dirname(path))
  serializable = shape == "array" ? data.fetch("tasks") : data
  if File.extname(path) == ".json"
    File.write(path, "#{JSON.pretty_generate(serializable)}\n")
  else
    File.write(path, serializable.to_yaml)
  end
end

def default_phase_order
  {
    "extract" => ["extract"],
    "claim" => ["create", "reflect", "reweave", "verify"],
    "enrichment" => ["enrich", "reflect", "reweave", "verify"]
  }
end

def phase_for(task)
  task["current_phase"] || task[:current_phase] || (task["type"] == "extract" ? "extract" : nil)
end

def status_for(task)
  (task["status"] || task[:status] || "pending").to_s
end

def id_for(task)
  (task["id"] || task[:id]).to_s
end

def count_statuses(tasks)
  counts = Hash.new(0)
  tasks.each do |task|
    status = status_for(task)
    case status
    when "pending" then counts["pending"] += 1
    when "done", "completed" then counts["done"] += 1
    when "blocked" then counts["blocked"] += 1
    when "active", "in_progress" then counts["active"] += 1
    else counts[status] += 1
    end
  end
  counts
end

def phase_distribution(tasks)
  distribution = Hash.new(0)
  tasks.each do |task|
    next unless status_for(task) == "pending"
    phase = phase_for(task) || "unknown"
    distribution[phase] += 1
  end
  distribution
end

def selected_tasks(tasks, limit, batch, type)
  selected = tasks.select { |task| status_for(task) == "pending" }
  selected = selected.select { |task| (task["batch"] || task[:batch]).to_s == batch } if batch
  selected = selected.select { |task| phase_for(task).to_s == type } if type
  selected.first(limit)
end

def task_target(task)
  task["target"] || task[:target] || task["source"] || task[:source] || id_for(task)
end

def completed_phases(task)
  Array(task["completed_phases"] || task[:completed_phases])
end

def phase_order_for(data, task)
  phase_order = data["phase_order"] || default_phase_order
  type = (task["type"] || task[:type] || "claim").to_s
  Array(phase_order[type] || phase_order[type.to_sym] || default_phase_order[type] || default_phase_order["claim"])
end

def find_task!(tasks, id)
  task = tasks.find { |candidate| id_for(candidate) == id }
  raise "Task not found: #{id}" unless task
  task
end

vault = "."
mode = nil
task_id = nil
reason = nil
limit = 1
batch = nil
type = nil
format = "text"

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--dry-run"
    mode = :dry_run
  when "--advance"
    mode = :advance
    task_id = args.shift
  when "--fail"
    mode = :fail
    task_id = args.shift
  when "--reason"
    reason = args.shift
  when "--limit"
    limit = Integer(args.shift || "")
  when "--batch"
    batch = args.shift
  when "--type"
    type = args.shift
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

mode ||= :dry_run

unless %w[text json].include?(format)
  warn "Unsupported format: #{format}"
  exit 2
end

if limit.negative?
  warn "Limit must be non-negative."
  exit 2
end

if mode == :fail && (reason.nil? || reason.empty?)
  warn "--fail requires --reason TEXT"
  exit 2
end

vault = File.expand_path(vault)
queue_path = find_queue(vault)

if queue_path.nil?
  result = {
    "queue_file" => nil,
    "counts" => { "total" => 0, "pending" => 0, "active" => 0, "blocked" => 0, "done" => 0 },
    "selected" => []
  }
  if format == "json"
    puts JSON.pretty_generate(result)
  else
    puts "Queue is empty. Use hippocampusmd-seed or hippocampusmd-pipeline to add sources."
  end
  exit 0
end

begin
  queue_data, queue_shape = load_queue(queue_path)
rescue StandardError => e
  warn e.message
  exit 1
end

tasks = queue_data.fetch("tasks")
counts = count_statuses(tasks)
summary_counts = {
  "total" => tasks.length,
  "pending" => counts["pending"],
  "active" => counts["active"],
  "blocked" => counts["blocked"],
  "done" => counts["done"]
}

case mode
when :dry_run
  selected = selected_tasks(tasks, limit, batch, type)
  result = {
    "queue_file" => rel_path(queue_path, vault),
    "counts" => summary_counts,
    "phase_distribution" => phase_distribution(tasks),
    "selected" => selected.map do |task|
      {
        "id" => id_for(task),
        "phase" => phase_for(task),
        "target" => task_target(task),
        "batch" => task["batch"] || task[:batch],
        "file" => task["file"] || task[:file]
      }
    end,
    "estimated_subagent_spawns" => selected.length
  }
  if format == "json"
    puts JSON.pretty_generate(result)
  else
    puts "--=={ ralph dry-run }==--"
    puts
    puts "Queue file: #{rel_path(queue_path, vault)}"
    puts "Total: #{summary_counts["total"]} | Pending: #{summary_counts["pending"]} | Active: #{summary_counts["active"]} | Blocked: #{summary_counts["blocked"]} | Done: #{summary_counts["done"]}"
    puts
    puts "Phase distribution:"
    if result["phase_distribution"].empty?
      puts "  None"
    else
      result["phase_distribution"].sort.each { |phase_name, count| puts "  #{phase_name}: #{count}" }
    end
    puts
    puts "Next tasks to process:"
    if selected.empty?
      puts "  None"
    else
      selected.each_with_index do |task, index|
        puts "#{index + 1}. #{id_for(task)} -- phase: #{phase_for(task)} -- #{task_target(task)}"
      end
    end
    puts
    puts "Estimated subagent spawns: #{selected.length}"
  end
when :advance
  begin
    task = find_task!(tasks, task_id)
  rescue StandardError => e
    warn e.message
    exit 1
  end
  current = phase_for(task)
  order = phase_order_for(queue_data, task)
  current_index = order.index(current)
  if current.nil? || current_index.nil?
    warn "Task #{task_id} has no recognizable current phase."
    exit 1
  end
  completed = completed_phases(task)
  completed << current unless completed.include?(current)
  task["completed_phases"] = completed
  next_phase = order[current_index + 1]
  if next_phase
    task["current_phase"] = next_phase
    task["status"] = "pending"
  else
    task["current_phase"] = nil
    task["status"] = "done"
    task["completed"] = Time.now.utc.iso8601
  end
  write_queue(queue_path, queue_data, queue_shape)
  result = {
    "id" => task_id,
    "from" => current,
    "to" => next_phase || "done",
    "status" => task["status"],
    "completed_phases" => completed,
    "completed" => task["completed"]
  }
  if format == "json"
    puts JSON.pretty_generate(result.compact)
  else
    puts "Advanced: #{task_id}"
    puts "#{current} -> #{next_phase || "done"}"
  end
when :fail
  begin
    task = find_task!(tasks, task_id)
  rescue StandardError => e
    warn e.message
    exit 1
  end
  task["status"] = "blocked"
  task["blocked_reason"] = reason
  task["blocked_at"] = Time.now.utc.iso8601
  write_queue(queue_path, queue_data, queue_shape)
  result = {
    "id" => task_id,
    "status" => "blocked",
    "reason" => reason
  }
  if format == "json"
    puts JSON.pretty_generate(result)
  else
    puts "Blocked: #{task_id}"
    puts reason
  end
end
