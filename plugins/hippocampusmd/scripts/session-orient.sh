#!/usr/bin/env bash
if command -v ruby >/dev/null 2>&1; then
  exec ruby -x "$0" "$@"
fi
printf 'Ruby is required for structured session orientation.\n' >&2
exit 1

#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"

require_relative "lib/queue_hygiene"

def usage
  warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] [--limit N] [--format text|json]"
end

vault = "."
limit = 25
format = "text"

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--limit"
    limit_arg = args.shift
    unless limit_arg&.match?(/\A\d+\z/)
      warn "Limit must be a non-negative integer."
      exit 2
    end
    limit = limit_arg.to_i
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

def count_files(path, pattern = "*")
  return 0 unless Dir.exist?(path)

  Dir.glob(File.join(path, pattern)).count { |candidate| File.file?(candidate) }
end

def markdown_count(root)
  Dir.glob(File.join(root, "**", "*.md"), File::FNM_DOTMATCH).count do |path|
    next false unless File.file?(path)

    parts = Pathname.new(path).relative_path_from(Pathname.new(root)).each_filename.to_a
    !parts.include?(".git") && !parts.include?("node_modules")
  end
end

def excerpt_file(root, rel, limit)
  path = File.join(root, rel)
  return nil unless File.file?(path)

  File.readlines(path, chomp: true).first(limit)
end

def latest_file(root, rel_dir, pattern = "*")
  dir = File.join(root, rel_dir)
  return nil unless Dir.exist?(dir)

  Dir.glob(File.join(dir, pattern)).select { |path| File.file?(path) }.sort.last
end

def relpath(path, root)
  path.start_with?("#{root}/") ? path.delete_prefix("#{root}/") : path
end

marker = File.file?(File.join(vault_abs, ".hippocampusmd")) ? "present" : "absent"

md_count = markdown_count(vault_abs)
notes_count = count_files(File.join(vault_abs, "notes"), "*.md")
inbox_count = count_files(File.join(vault_abs, "inbox"), "*.md")
queue_count = count_files(File.join(vault_abs, "ops/queue"), "*.md")
observations_count = count_files(File.join(vault_abs, "ops/observations"), "*.md")
tensions_count = count_files(File.join(vault_abs, "ops/tensions"), "*.md")
session_count = count_files(File.join(vault_abs, "ops/sessions"), "*.md")
json_session_count = count_files(File.join(vault_abs, "ops/sessions"), "*.json")
health_count = count_files(File.join(vault_abs, "ops/health"), "*.md")

queue_hygiene = QueueHygiene.status(vault_abs)
archivable_batches = queue_hygiene.fetch(:archivable_batches)
stale_active_tasks = queue_hygiene.fetch(:stale_active_tasks)

next_action = "Run hippocampusmd-health to establish a current baseline."
if marker == "absent"
  next_action = "Run hippocampusmd-setup if this directory should become a HippocampusMD vault."
elsif archivable_batches.any?
  next_action = "Archive completed queue batch #{archivable_batches.first}."
elsif stale_active_tasks.any?
  next_action = "Review stale active queue task #{stale_active_tasks.first[:id]}."
elsif inbox_count.positive?
  next_action = "Review inbox pressure and decide whether to seed or process captured material."
elsif queue_hygiene.dig(:counts, :pending).to_i.positive? || queue_count.positive?
  next_action = "Review ops/queue and continue the next queued task."
elsif observations_count >= 10 || tensions_count >= 5
  next_action = "Run a rethink pass on accumulated observations and tensions."
elsif health_count.positive?
  next_action = "Review the latest health report and address its highest-severity finding."
end

latest_health = latest_file(vault_abs, "ops/health", "*.md")
latest_session = File.join(vault_abs, "ops/sessions/current.md")
latest_session = File.join(vault_abs, "ops/sessions/current.json") unless File.file?(latest_session)

if format == "json"
  puts JSON.pretty_generate(
    vault: vault_abs,
    hippocampusmd_marker: marker,
    markdown_files: md_count,
    notes: notes_count,
    inbox: inbox_count,
    queue: queue_count,
    observations: observations_count,
    tensions: tensions_count,
    sessions: session_count + json_session_count,
    health_reports: health_count,
    queue_hygiene: {
      queue_file: queue_hygiene[:queue_file_rel],
      counts: queue_hygiene[:counts],
      archivable_batches: archivable_batches,
      stale_active_tasks: stale_active_tasks.map { |task| task[:id] },
      orphan_task_files: queue_hygiene[:orphan_task_files],
      missing_task_files: queue_hygiene[:missing_task_files].map { |missing| missing[:file] },
      stale_task_stack_items: queue_hygiene[:stale_task_stack_items],
      proposals: queue_hygiene[:proposals]
    },
    archivable_batches: archivable_batches,
    stale_active_tasks: stale_active_tasks.map { |task| task[:id] },
    next_action: next_action
  )
  exit 0
end

puts "HippocampusMD session orientation"
puts "Vault: #{vault_abs}"
puts "Marker: #{marker}"
puts
puts "Inventory:"
puts "  Markdown files: #{md_count}"
puts "  notes/: #{notes_count}"
puts "  inbox/: #{inbox_count}"
puts "  ops/queue/: #{queue_count}"
puts "  ops/observations/: #{observations_count}"
puts "  ops/tensions/: #{tensions_count}"
puts "  ops/sessions/: #{session_count + json_session_count}"
puts "  ops/health/: #{health_count}"
puts

puts "Queue hygiene:"
counts = queue_hygiene.fetch(:counts)
puts "  Queue file: #{queue_hygiene[:queue_file_rel] || "not found"}"
puts "  Counts: #{counts[:pending]} pending, #{counts[:active]} active, #{counts[:completed]} completed, #{counts[:blocked]} blocked, #{counts[:stale_active]} stale active"
puts "  Archivable batches: #{archivable_batches.any? ? archivable_batches.join(", ") : "none"}"
puts "  Stale active tasks: #{stale_active_tasks.any? ? stale_active_tasks.map { |task| task[:id] }.join(", ") : "none"}"
puts "  Orphan task files: #{queue_hygiene[:orphan_task_files].any? ? queue_hygiene[:orphan_task_files].join(", ") : "none"}"
puts

["self/goals.md", "ops/goals.md"].each do |rel|
  lines = excerpt_file(vault_abs, rel, limit)
  next unless lines

  puts "#{rel} excerpt:"
  puts lines
  puts
  break
end

if File.file?(latest_session)
  puts "Current session handoff:"
  puts File.readlines(latest_session, chomp: true).first(limit)
  puts
end

puts "Latest health report: #{relpath(latest_health, vault_abs)}" if latest_health
puts "Recommended next action: #{next_action}"
