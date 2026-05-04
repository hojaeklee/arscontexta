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
require_relative "lib/queue_hygiene"

def usage
  warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] --status|--discoveries|--add TEXT|--done N|--drop N|--reorder N POSITION|--refresh-queue [--limit N] [--format text|json]"
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
  when "--refresh-queue"
    mode = :refresh_queue
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

def parse_queue(root)
  report = QueueHygiene.status(root)
  counts = Hash.new(0)
  report.fetch(:counts).each { |key, value| counts[key.to_s] = value }
  tasks = report.fetch(:tasks).map do |task|
    {
      "id" => task[:id],
      "status" => task[:status],
      "raw_status" => task[:raw_status],
      "phase" => task[:phase],
      "target" => task[:target].to_s.empty? ? task[:file] : task[:target],
      "batch" => task[:batch]
    }
  end
  errors = report.fetch(:queue_errors)
  stale_items =
    if report[:queue_file_rel]
      QueueHygiene.stale_generated_task_stack_items(stack_current_items(root), report.fetch(:tasks), report.fetch(:archivable_batches))
    else
      []
    end
  {
    exists: !report[:queue_file_rel].nil?,
    file: report[:queue_file_rel],
    tasks: tasks,
    counts: counts,
    archivable_batches: report.fetch(:archivable_batches),
    stale_task_stack_items: stale_items,
    suggested_task_stack_items: QueueHygiene.suggested_task_stack_items(report.fetch(:tasks)),
    error: errors.empty? || report[:queue_file_rel].nil? ? nil : errors.join("; ")
  }
end

def stack_current_items(root)
  QueueHygiene.current_task_stack_items(root)
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
when :refresh_queue
  removed = queue[:stale_task_stack_items]
  stack[:current] = stack[:current].reject { |item| removed.include?(item) }
  added = queue[:suggested_task_stack_items].reject { |item| stack[:current].include?(item) }
  stack[:current].concat(added)
  write_tasks(tasks_path, stack)
  stack[:exists] = true
  message = (removed.map { |item| "Removed stale generated task: #{item}" } +
             added.map { |item| "Added queue task: #{item}" }).join("\n")
  message = "Task stack already matches queue state." if message.empty?
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
      stale_task_stack_items: queue[:stale_task_stack_items],
      suggested_task_stack_items: queue[:suggested_task_stack_items],
      tasks: queue[:tasks]
    }
  )
  exit 0
end

puts "HippocampusMD tasks"
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
  unless queue[:stale_task_stack_items].empty?
    puts "Stale task stack entries:"
    queue[:stale_task_stack_items].first(limit).each { |item| puts "  - #{item}" }
    puts "  ... #{queue[:stale_task_stack_items].length - limit} more omitted by --limit #{limit}" if queue[:stale_task_stack_items].length > limit
  end
  puts "Suggested queue task entries:"
  if queue[:suggested_task_stack_items].empty?
    puts "  (empty)"
  else
    queue[:suggested_task_stack_items].first(limit).each { |item| puts "  - #{item}" }
    puts "  ... #{queue[:suggested_task_stack_items].length - limit} more omitted by --limit #{limit}" if queue[:suggested_task_stack_items].length > limit
  end
end
puts
puts "Summary: #{stack[:current].length} current tasks, #{queue[:counts]["pending"]} pending queue tasks, #{queue[:counts]["blocked"]} blocked queue tasks."
