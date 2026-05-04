#!/usr/bin/env bash
if command -v ruby >/dev/null 2>&1; then
  exec ruby -x "$0" "$@"
fi
printf 'Ruby is required for queue hygiene status checks.\n' >&2
exit 1

#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "lib/queue_hygiene"

def usage
  warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] [--format text|json] [--stale-active-minutes N]"
end

def parse_non_negative_integer(value, label)
  integer = Integer(value || "")
  raise ArgumentError if integer.negative?

  integer
rescue ArgumentError
  warn "#{label} must be a non-negative integer."
  exit 2
end

def list_value(items, &block)
  values = block ? items.map(&block) : items
  values.empty? ? "none" : values.join(", ")
end

def task_label(task)
  id = task.fetch(:id)
  file = task[:file_rel_path]
  file.to_s.empty? ? id : "#{id} (#{file})"
end

def serializable_report(report)
  {
    vault: report.fetch(:root),
    queue_file: report[:queue_file_rel],
    queue_errors: report.fetch(:queue_errors),
    counts: report.fetch(:counts),
    archivable_batches: report.fetch(:archivable_batches),
    stale_active_tasks: report.fetch(:stale_active_tasks).map do |task|
      {
        id: task[:id],
        file: task[:file_rel_path],
        batch: task[:batch],
        stale_since: task[:stale_since],
        stale_minutes: task[:stale_minutes]
      }
    end,
    orphan_task_files: report.fetch(:orphan_task_files),
    missing_task_files: report.fetch(:missing_task_files).map do |missing|
      { id: missing[:id], file: missing[:file] }
    end,
    completed_left_active: report.fetch(:completed_left_active).map do |task|
      { id: task[:id], file: task[:file_rel_path], batch: task[:batch] }
    end,
    stale_task_stack_items: report.fetch(:stale_task_stack_items),
    proposals: report.fetch(:proposals)
  }
end

vault = "."
format = "text"
stale_active_minutes = QueueHygiene::DEFAULT_STALE_ACTIVE_MINUTES

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--format"
    format = args.shift
  when "--stale-active-minutes"
    stale_active_minutes = parse_non_negative_integer(args.shift, "Stale active threshold")
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

unless Dir.exist?(vault)
  warn "Vault path is not a directory: #{vault}"
  exit 2
end

root = File.realpath(vault)
report = QueueHygiene.status(root, stale_active_minutes: stale_active_minutes)
queue_load_failed = report.fetch(:queue_errors).any? { |error| error.start_with?("Unable to load queue file:") }

if format == "json"
  puts JSON.pretty_generate(serializable_report(report))
else
  counts = report.fetch(:counts)

  puts "Queue hygiene status"
  puts "Vault: #{report.fetch(:root)}"
  puts "Queue file: #{report[:queue_file_rel] || "missing"}"
  report.fetch(:queue_errors).each { |error| puts "Queue error: #{error}" }
  puts "Pending: #{counts.fetch(:pending)} | Active: #{counts.fetch(:active)} | Stale active: #{counts.fetch(:stale_active)} | Blocked: #{counts.fetch(:blocked)} | Completed: #{counts.fetch(:completed)}"
  puts "Archivable batches: #{list_value(report.fetch(:archivable_batches))}"
  puts "Stale active tasks: #{list_value(report.fetch(:stale_active_tasks)) { |task| task_label(task) }}"
  puts "Orphan task files: #{list_value(report.fetch(:orphan_task_files))}"
  puts "Missing task files: #{list_value(report.fetch(:missing_task_files)) { |missing| "#{missing[:id]} -> #{missing[:file]}" }}"
  puts "Stale task stack: #{list_value(report.fetch(:stale_task_stack_items))}"
  puts "Completed left active: #{list_value(report.fetch(:completed_left_active)) { |task| task_label(task) }}"
  if report.fetch(:proposals).empty?
    puts "Proposals: none"
  else
    puts "Proposals:"
    report.fetch(:proposals).each { |proposal| puts "- #{proposal.fetch(:message)}" }
  end
end

exit(queue_load_failed ? 1 : 0)
