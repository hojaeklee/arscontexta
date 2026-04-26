#!/usr/bin/env bash
if command -v ruby >/dev/null 2>&1; then
  exec ruby -x "$0" "$@"
fi
printf 'Ruby is required for structured task and queue parsing.\n' >&2
exit 1

#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "json"
require "yaml"

def usage
  warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] --status|--discoveries|--add TEXT|--done N|--drop N|--reorder N POSITION [--limit N] [--format text|json]"
end

vault = "."
mode = nil
mode_arg = nil
reorder_to = nil
limit = 25
format = "text"

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--status"
    mode = :status
  when "--discoveries"
    mode = :discoveries
  when "--add"
    mode = :add
    mode_arg = args.shift
  when "--done"
    mode = :done
    mode_arg = args.shift
  when "--drop"
    mode = :drop
    mode_arg = args.shift
  when "--reorder"
    mode = :reorder
    mode_arg = args.shift
    reorder_to = args.shift
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

mode ||= :status

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
tasks_path = File.join(vault_abs, "ops/tasks.md")

def relpath(path, root)
  path.start_with?("#{root}/") ? path.delete_prefix("#{root}/") : path
end

def canonical_heading(line)
  case line.strip.downcase
  when "## current", "## active" then :current
  when "## completed", "## done" then :completed
  when "## discoveries" then :discoveries
  else nil
  end
end

def parse_tasks(path)
  result = {
    exists: File.file?(path),
    title: "# Task Stack",
    preface: [],
    current: [],
    completed: [],
    discoveries: [],
    trailing: []
  }
  return result unless result[:exists]

  section = :preface
  File.readlines(path, chomp: true).each do |line|
    if line.start_with?("# ") && result[:title] == "# Task Stack"
      result[:title] = line
      next
    end

    heading = canonical_heading(line)
    if heading
      section = heading
      next
    elsif line.start_with?("## ")
      section = :trailing
    end

    case section
    when :current
      result[:current] << line.sub(/\A-\s+\[\s\]\s*/, "") if line.match?(/\A-\s+\[\s\]\s+/)
    when :completed
      result[:completed] << line.sub(/\A-\s+\[[xX]\]\s*/, "") if line.match?(/\A-\s+\[[xX]\]\s+/)
    when :discoveries
      result[:discoveries] << line.sub(/\A-\s+/, "") if line.match?(/\A-\s+/)
    when :preface
      result[:preface] << line unless line.strip.empty?
    else
      result[:trailing] << line
    end
  end
  result
end

def write_tasks(path, stack)
  Dir.mkdir(File.dirname(path)) unless Dir.exist?(File.dirname(path))
  lines = []
  lines << (stack[:title].to_s.empty? ? "# Task Stack" : stack[:title])
  unless stack[:preface].empty?
    lines << ""
    lines.concat(stack[:preface])
  end
  lines << ""
  lines << "## Current"
  stack[:current].each { |item| lines << "- [ ] #{item}" }
  lines << ""
  lines << "## Completed"
  stack[:completed].each { |item| lines << "- [x] #{item}" }
  lines << ""
  lines << "## Discoveries"
  stack[:discoveries].each { |item| lines << "- #{item}" }
  unless stack[:trailing].empty?
    lines << ""
    lines.concat(stack[:trailing])
  end
  File.write(path, "#{lines.join("\n")}\n")
end

def parse_index(value, max, label)
  number = Integer(value || "")
  raise ArgumentError, "#{label} must be between 1 and #{max}." if number < 1 || number > max

  number - 1
rescue ArgumentError
  raise ArgumentError, "#{label} must be between 1 and #{max}."
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

  raw.select { |entry| entry.is_a?(Hash) }.map do |entry|
    status = normalize_status(entry["status"])
    {
      "id" => entry["id"] || entry["task_id"] || entry["queue_id"] || "(no id)",
      "status" => status,
      "raw_status" => entry["status"],
      "phase" => entry["current_phase"] || entry["phase"] || entry["next_phase"],
      "target" => entry["target"] || entry["file"] || entry["note"] || entry["source"],
      "batch" => entry["batch"] || entry["batch_id"] || entry["source_batch"]
    }
  end
end

def parse_queue(root)
  rel = queue_file(root)
  return { exists: false, file: nil, tasks: [], counts: Hash.new(0), archivable_batches: [] } unless rel

  path = File.join(root, rel)
  data =
    if rel.end_with?(".json")
      JSON.parse(File.read(path))
    else
      YAML.safe_load(File.read(path), aliases: true) || {}
    end
  tasks = queue_tasks_from_data(data)
  counts = Hash.new(0)
  tasks.each { |task| counts[task["status"]] += 1 }
  batches = tasks.group_by { |task| task["batch"].to_s }.reject { |batch, _| batch.empty? }
  archivable = batches.select { |_, items| items.all? { |task| task["status"] == "completed" } }.keys.sort
  { exists: true, file: rel, tasks: tasks, counts: counts, archivable_batches: archivable }
rescue JSON::ParserError, Psych::Exception => e
  { exists: true, file: rel, tasks: [], counts: Hash.new(0), archivable_batches: [], error: e.message }
end

stack = parse_tasks(tasks_path)
queue = parse_queue(vault_abs)

def stack_payload(stack)
  {
    exists: stack[:exists],
    current: stack[:current],
    completed: stack[:completed],
    discoveries: stack[:discoveries]
  }
end

case mode
when :add
  if mode_arg.to_s.strip.empty?
    warn "--add requires a task description."
    exit 2
  end
  stack[:title] = "# Task Stack" unless stack[:exists]
  stack[:current] << mode_arg.strip
  write_tasks(tasks_path, stack)
  stack[:exists] = true
  message = "Added to task stack: #{mode_arg.strip}"
when :done
  begin
    index = parse_index(mode_arg, stack[:current].length, "Task number")
  rescue ArgumentError => e
    warn e.message
    exit 2
  end
  item = stack[:current].delete_at(index)
  stack[:completed].unshift("#{item} (#{Date.today.iso8601})")
  write_tasks(tasks_path, stack)
  stack[:exists] = true
  message = "Completed: #{item}"
when :drop
  begin
    index = parse_index(mode_arg, stack[:current].length, "Task number")
  rescue ArgumentError => e
    warn e.message
    exit 2
  end
  item = stack[:current].delete_at(index)
  write_tasks(tasks_path, stack)
  stack[:exists] = true
  message = "Dropped: #{item}"
when :reorder
  begin
    from = parse_index(mode_arg, stack[:current].length, "Task number")
    to = parse_index(reorder_to, stack[:current].length, "Position")
  rescue ArgumentError => e
    warn e.message
    exit 2
  end
  item = stack[:current].delete_at(from)
  stack[:current].insert(to, item)
  write_tasks(tasks_path, stack)
  stack[:exists] = true
  message = "Moved: #{item}"
end

if format == "json"
  puts JSON.pretty_generate(
    vault: vault_abs,
    mode: mode.to_s,
    message: message,
    task_stack: stack_payload(stack),
    queue: {
      exists: queue[:exists],
      file: queue[:file],
      counts: {
        pending: queue[:counts]["pending"],
        active: queue[:counts]["active"],
        completed: queue[:counts]["completed"],
        blocked: queue[:counts]["blocked"],
        unknown: queue[:counts]["unknown"]
      },
      archivable_batches: queue[:archivable_batches],
      tasks: queue[:tasks]
    }
  )
  exit 0
end

puts "Ars Contexta tasks"
puts "Vault: #{vault_abs}"
puts "Task stack: #{stack[:exists] ? "ops/tasks.md" : "missing"}"
puts message if message
puts

if mode == :discoveries
  puts "Discoveries:"
  if stack[:discoveries].empty?
    puts "  (empty)"
  else
    stack[:discoveries].first(limit).each { |item| puts "  - #{item}" }
  end
  exit 0
end

unless stack[:exists]
  puts "No task stack found. Use --add \"description\" to create ops/tasks.md."
  puts
end

puts "Task Stack"
puts "=========="
puts "Current:"
if stack[:current].empty?
  puts "  (empty)"
else
  stack[:current].first(limit).each.with_index(1) { |item, index| puts "  #{index}. [ ] #{item}" }
  puts "  ... #{stack[:current].length - limit} more omitted by --limit #{limit}" if stack[:current].length > limit
end
puts
puts "Completed:"
if stack[:completed].empty?
  puts "  (empty)"
else
  stack[:completed].first(limit).each { |item| puts "  - [x] #{item}" }
  puts "  ... #{stack[:completed].length - limit} more omitted by --limit #{limit}" if stack[:completed].length > limit
end
puts
puts "Discoveries:"
if stack[:discoveries].empty?
  puts "  (empty)"
else
  stack[:discoveries].first(limit).each { |item| puts "  - #{item}" }
  puts "  ... #{stack[:discoveries].length - limit} more omitted by --limit #{limit}" if stack[:discoveries].length > limit
end
puts

puts "Pipeline Queue"
puts "=============="
if queue[:error]
  puts "Queue file: #{queue[:file]}"
  puts "Could not parse queue: #{queue[:error]}"
elsif !queue[:exists]
  puts "No queue file found."
else
  counts = queue[:counts]
  puts "Queue file: #{queue[:file]}"
  puts "Pending: #{counts["pending"]} | Active: #{counts["active"]} | Blocked: #{counts["blocked"]} | Completed: #{counts["completed"]}"
  queue[:tasks].select { |task| %w[pending active blocked].include?(task["status"]) }.first(limit).each do |task|
    detail = "#{task["id"]}: #{task["status"]}"
    detail += " / #{task["phase"]}" if task["phase"]
    detail += " -- #{task["target"]}" if task["target"]
    detail += " (batch: #{task["batch"]})" if task["batch"]
    puts "  - #{detail}"
  end
  if queue[:archivable_batches].empty?
    puts "Archivable batches: none"
  else
    puts "Archivable batches: #{queue[:archivable_batches].join(", ")}"
  end
end
puts
puts "Summary: #{stack[:current].length} current tasks, #{queue[:counts]["pending"]} pending queue tasks, #{queue[:counts]["blocked"]} blocked queue tasks."
