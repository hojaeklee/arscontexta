#!/usr/bin/env bash
if command -v ruby >/dev/null 2>&1; then
  exec ruby -x "$0" "$@"
fi
printf 'Ruby is required for queue reconciliation.\n' >&2
exit 1

#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "lib/queue_hygiene"

def usage
  warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] [--apply] [--format text|json]"
end

def rel_path(path, root)
  QueueHygiene.rel_path(path, root)
end

def destination_for_task(root, task)
  File.join(QueueHygiene.archive_dir_for_completed_task(root, task), File.basename(task.fetch(:file_path)))
end

def unsafe_archive_segment_action(task)
  segment = task[:batch].to_s.strip.empty? ? task[:id].to_s : task[:batch].to_s
  {
    type: "skipped_completed_task_file",
    reason: "unsafe_archive_segment",
    task_id: task.fetch(:id),
    source: task.fetch(:file_path),
    source_rel: task.fetch(:file_rel_path),
    archive_segment: segment
  }
end

def deterministic_actions(report)
  root = report.fetch(:root)
  actions = []
  seen_dirs = {}

  report.fetch(:completed_left_active).each do |task|
    source = task.fetch(:file_path)
    begin
      archive_dir = QueueHygiene.archive_dir_for_completed_task(root, task)
      destination = destination_for_task(root, task)
    rescue ArgumentError
      actions << unsafe_archive_segment_action(task)
      next
    end

    if File.file?(source) && File.exist?(destination)
      actions << {
        type: "skipped_completed_task_file",
        reason: "destination_exists",
        task_id: task.fetch(:id),
        source: source,
        source_rel: rel_path(source, root),
        destination: destination,
        destination_rel: rel_path(destination, root),
        archive_dir: archive_dir,
        archive_dir_rel: rel_path(archive_dir, root)
      }
      next
    end

    unless Dir.exist?(archive_dir) || seen_dirs[archive_dir]
      actions << {
        type: "create_archive_directory",
        archive_dir: archive_dir,
        archive_dir_rel: rel_path(archive_dir, root)
      }
      seen_dirs[archive_dir] = true
    end

    next unless File.file?(source) && !File.exist?(destination)

    actions << {
      type: "move_completed_task_file",
      task_id: task.fetch(:id),
      source: source,
      source_rel: rel_path(source, root),
      destination: destination,
      destination_rel: rel_path(destination, root),
      archive_dir: archive_dir,
      archive_dir_rel: rel_path(archive_dir, root)
    }
  end

  actions
end

def proposal_lines(report)
  report.fetch(:proposals).map do |proposal|
    case proposal.fetch(:type)
    when "stale_active_task"
      "Proposal: review stale active task #{proposal.fetch(:task_id)}"
    when "missing_task_file"
      "Proposal: review missing task file #{proposal.fetch(:task_id)} -> #{proposal.fetch(:file)}"
    when "orphan_task_file"
      "Proposal: review orphan task file #{proposal.fetch(:file)}"
    when "stale_task_stack_item"
      "Proposal: refresh stale task-stack item #{proposal.fetch(:item)}"
    when "completed_left_active"
      "Proposal: archive completed task file #{proposal.fetch(:file)}"
    else
      "Proposal: #{proposal.fetch(:message)}"
    end
  end
end

def archive_recommendation_lines(report)
  report.fetch(:archivable_batches).map do |batch|
    "Archive recommendation: hippocampusmd-archive-batch --batch #{batch}"
  end
end

def serializable_actions(actions, applied:)
  actions.map do |action|
    action.merge(applied: applied && action.fetch(:applied, false))
          .reject { |key, _value| %i[source destination archive_dir].include?(key) }
  end
end

def apply_actions(actions)
  actions.each do |action|
    case action.fetch(:type)
    when "create_archive_directory"
      FileUtils.mkdir_p(action.fetch(:archive_dir))
      action[:applied] = true
    when "move_completed_task_file"
      FileUtils.mkdir_p(action.fetch(:archive_dir))
      if File.file?(action.fetch(:source)) && !File.exist?(action.fetch(:destination))
        FileUtils.mv(action.fetch(:source), action.fetch(:destination))
        action[:applied] = true
      else
        action[:applied] = false
      end
    when "skipped_completed_task_file"
      action[:applied] = false
    end
  end
end

vault = "."
apply = false
format = "text"

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--apply"
    apply = true
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

unless Dir.exist?(vault)
  warn "Vault path is not a directory: #{vault}"
  exit 2
end

root = File.realpath(vault)
report = QueueHygiene.status(root)
queue_load_failed = report.fetch(:queue_errors).any? { |error| error.start_with?("Unable to load queue file:") }
actions = deterministic_actions(report)
apply_actions(actions) if apply
mode = apply ? "apply" : "dry run"
proposals = proposal_lines(report)
archive_recommendations = archive_recommendation_lines(report)

if format == "json"
  puts JSON.pretty_generate(
    {
      vault: root,
      mode: mode,
      actions: serializable_actions(actions, applied: apply),
      archive_recommendations: archive_recommendations,
      proposals: report.fetch(:proposals)
    }
  )
else
  puts "Queue reconciliation"
  puts "Vault: #{root}"
  puts "Mode: #{mode}"

  archive_recommendations.each { |line| puts line }

  if actions.empty?
    puts "No deterministic repairs needed"
  else
    actions.each do |action|
      case action.fetch(:type)
      when "create_archive_directory"
        verb = apply ? "Created" : "Would create"
        puts "#{verb} archive directory #{action.fetch(:archive_dir_rel)}"
      when "move_completed_task_file"
        verb = apply && action[:applied] ? "Moved" : "Would move"
        puts "#{verb} completed task file #{action.fetch(:source_rel)} to #{action.fetch(:destination_rel)}"
      when "skipped_completed_task_file"
        case action.fetch(:reason)
        when "destination_exists"
          puts "Skipped completed task file #{action.fetch(:source_rel)} because archive destination already exists #{action.fetch(:destination_rel)}"
        when "unsafe_archive_segment"
          puts "Skipped completed task file #{action.fetch(:source_rel)} because archive segment is unsafe: #{action.fetch(:archive_segment)}"
        end
      end
    end
  end

  if proposals.empty?
    puts "Proposals: none"
  else
    proposals.each { |line| puts line }
  end
end

exit(queue_load_failed ? 1 : 0)
