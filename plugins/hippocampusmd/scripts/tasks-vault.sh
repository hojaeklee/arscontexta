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

def task_item_from_current_line(line)
  return nil unless line.match?(/\A-\s+\[\s\]\s+/)

  line.sub(/\A-\s+\[\s\]\s*/, "")
end

def current_item_covers_suggestion?(current_item, suggestion)
  current_item.match?(/\A#{Regexp.escape(suggestion)}(?:\z|[[:space:][:punct:]])/)
end

def current_section_range(lines)
  start_index = lines.index { |line| canonical_heading(line) == :current }
  return nil unless start_index

  end_index = ((start_index + 1)...lines.length).find { |index| lines[index].match?(/\A##\s+/) } || lines.length
  [start_index, end_index]
end

def insert_current_section(lines, added_items)
  return lines if added_items.empty?

  section = ["## Current"] + added_items.map { |item| "- [ ] #{item}" }
  insert_at = lines.index { |line| %i[completed discoveries].include?(canonical_heading(line)) } || lines.length
  prefix_blank = insert_at.positive? && !lines[insert_at - 1].to_s.empty? ? [""] : []
  suffix_blank = insert_at < lines.length && !lines[insert_at].to_s.empty? ? [""] : []
  lines[0...insert_at] + prefix_blank + section + suffix_blank + lines[insert_at..]
end

def refresh_tasks_file(path, stale_items, suggested_items)
  if !File.file?(path)
    return { removed: [], added: [] } if suggested_items.empty?

    stack = {
      title: "# Task Stack",
      preface: [],
      current: suggested_items,
      completed: [],
      discoveries: [],
      trailing: []
    }
    write_tasks(path, stack)
    return { removed: [], added: suggested_items }
  end

  original = File.read(path)
  trailing_newline = original.end_with?("\n")
  lines = original.lines(chomp: true)
  range = current_section_range(lines)

  unless range
    updated = insert_current_section(lines, suggested_items)
    File.write(path, "#{updated.join("\n")}#{trailing_newline ? "\n" : ""}") unless updated == lines
    return { removed: [], added: suggested_items }
  end

  start_index, end_index = range
  before = lines[0...start_index]
  current = lines[start_index...end_index]
  after = lines[end_index..] || []
  removed = []
  kept_current = current.reject do |line|
    item = task_item_from_current_line(line)
    should_remove = item && stale_items.include?(item)
    removed << item if should_remove
    should_remove
  end
  current_items = kept_current.map { |line| task_item_from_current_line(line) }.compact
  added = suggested_items.reject do |item|
    current_items.any? { |current_item| current_item_covers_suggestion?(current_item, item) }
  end

  insert_at = kept_current.length
  insert_at -= 1 while insert_at > 1 && kept_current[insert_at - 1].to_s.empty?
  updated_current = kept_current.dup
  updated_current.insert(insert_at, *added.map { |item| "- [ ] #{item}" })
  updated = before + updated_current + after
  File.write(path, "#{updated.join("\n")}#{trailing_newline ? "\n" : ""}")
  { removed: removed, added: added }
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
  result = refresh_tasks_file(tasks_path, queue[:stale_task_stack_items], queue[:suggested_task_stack_items])
  removed = result.fetch(:removed)
  added = result.fetch(:added)
  stack = parse_tasks(tasks_path)
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
    detail += " / #{task["phase"]}" unless task["phase"].to_s.empty?
    detail += " -- #{task["target"]}" unless task["target"].to_s.empty?
    detail += " (batch: #{task["batch"]})" unless task["batch"].to_s.empty?
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
