#!/usr/bin/env bash
if command -v ruby >/dev/null 2>&1; then
  exec ruby -x "$0" "$@"
fi
printf 'Ruby is required for structured next-action analysis.\n' >&2
exit 1

#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "json"
require "yaml"
require "set"

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

def relpath(path, root)
  path.start_with?("#{root}/") ? path.delete_prefix("#{root}/") : path
end

def safe_load_yaml(path)
  return {} unless File.file?(path)

  text = File.read(path)
  yaml_text =
    if text =~ /\A(?:#.*\n|\s*\n)*---\n(.*?)\n---/m
      Regexp.last_match(1)
    else
      text
    end
  loaded = YAML.safe_load(yaml_text, aliases: true) || {}
  loaded.is_a?(Hash) ? loaded : {}
rescue Psych::Exception
  {}
end

def vocabulary(root)
  manifest = safe_load_yaml(File.join(root, "ops/derivation-manifest.md"))
  config = safe_load_yaml(File.join(root, "ops/config.yaml"))
  vocab = manifest.fetch("vocabulary", {})
  {
    "notes" => vocab["notes"] || config["notes_dir"] || "notes",
    "inbox" => vocab["inbox"] || config["inbox_dir"] || "inbox",
    "note" => vocab["note"] || "note",
    "reduce" => vocab["cmd_reduce"] || vocab["reduce"] || "reduce",
    "reweave" => vocab["cmd_reweave"] || vocab["reweave"] || "reweave",
    "rethink" => vocab["rethink"] || vocab["cmd_rethink"] || "rethink",
    "ralph" => vocab["ralph"] || "ralph",
    "observation_threshold" => config.dig("self_evolution", "observation_threshold") || 10,
    "tension_threshold" => config.dig("self_evolution", "tension_threshold") || 5
  }
end

def markdown_files(root, rel_dir, depth: nil)
  dir = File.join(root, rel_dir)
  return [] unless Dir.exist?(dir)

  pattern = depth ? File.join(dir, *Array.new(depth, "*"), "*.md") : File.join(dir, "**", "*.md")
  direct = Dir.glob(File.join(dir, "*.md"))
  nested = depth ? Dir.glob(pattern) : Dir.glob(pattern)
  (direct + nested).uniq.sort
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
  result = { exists: File.file?(path), current: [], completed: [], discoveries: [] }
  return result unless result[:exists]

  section = nil
  File.readlines(path, chomp: true).each do |line|
    heading = canonical_heading(line)
    if heading
      section = heading
      next
    elsif line.start_with?("## ")
      section = nil
    end

    case section
    when :current
      result[:current] << line.sub(/\A-\s+\[\s\]\s*/, "") if line.match?(/\A-\s+\[\s\]\s+/)
    when :completed
      result[:completed] << line.sub(/\A-\s+\[[xX]\]\s*/, "") if line.match?(/\A-\s+\[[xX]\]\s+/)
    when :discoveries
      result[:discoveries] << line.sub(/\A-\s+/, "") if line.match?(/\A-\s+/)
    end
  end
  result
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
    {
      "id" => entry["id"] || entry["task_id"] || entry["queue_id"] || "(no id)",
      "status" => normalize_status(entry["status"]),
      "phase" => entry["current_phase"] || entry["phase"] || entry["next_phase"],
      "target" => entry["target"] || entry["file"] || entry["note"] || entry["source"],
      "batch" => entry["batch"] || entry["batch_id"] || entry["source_batch"]
    }
  end
end

def parse_queue(root)
  rel = queue_file(root)
  return { exists: false, file: nil, tasks: [], counts: Hash.new(0) } unless rel

  path = File.join(root, rel)
  data = rel.end_with?(".json") ? JSON.parse(File.read(path)) : YAML.safe_load(File.read(path), aliases: true)
  tasks = queue_tasks_from_data(data || {})
  counts = Hash.new(0)
  tasks.each { |task| counts[task["status"]] += 1 }
  { exists: true, file: rel, tasks: tasks, counts: counts }
rescue JSON::ParserError, Psych::Exception => e
  { exists: true, file: rel, tasks: [], counts: Hash.new(0), error: e.message }
end

def count_pending_frontmatter(root, rel_dir, statuses)
  markdown_files(root, rel_dir).count do |path|
    text = File.read(path)
    statuses.any? { |status| text.match?(/^status:\s*#{Regexp.escape(status)}\s*$/i) }
  end
end

def first_goal_line(root)
  ["self/goals.md", "ops/goals.md"].each do |rel|
    path = File.join(root, rel)
    next unless File.file?(path)

    line = File.readlines(path, chomp: true).find do |candidate|
      stripped = candidate.strip
      stripped.start_with?("- ") || stripped.match?(/\A\d+\.\s+/)
    end
    return { file: rel, excerpt: line&.sub(/\A[-*\d.\s]+/, "") || "Goals file exists." }
  end
  nil
end

def latest_health(root)
  dir = File.join(root, "ops/health")
  return nil unless Dir.exist?(dir)

  files = Dir.glob(File.join(dir, "*.md")).sort
  return nil if files.empty?

  latest = files.last
  severe = File.readlines(latest, chomp: true).find { |line| line.match?(/\b(FAIL|CRITICAL|ERROR)\b/i) }
  { file: relpath(latest, root), severe: severe }
end

def previous_recommendations(root)
  path = File.join(root, "ops/next-log.md")
  return [] unless File.file?(path)

  File.readlines(path, chomp: true).grep(/\*\*Recommended:\*\*/).last(3).map do |line|
    line.sub(/^.*\*\*Recommended:\*\*\s*/, "").strip
  end
end

def file_age_days(path)
  ((Time.now - File.mtime(path)) / 86_400).floor
end

vocab = vocabulary(vault_abs)
notes = markdown_files(vault_abs, vocab["notes"])
inbox = markdown_files(vault_abs, vocab["inbox"], depth: 1)
oldest_inbox = inbox.min_by { |path| File.mtime(path) }
stack = parse_tasks(File.join(vault_abs, "ops/tasks.md"))
queue = parse_queue(vault_abs)
observations = count_pending_frontmatter(vault_abs, "ops/observations", ["pending"])
tensions = count_pending_frontmatter(vault_abs, "ops/tensions", ["pending", "open"])
goals = first_goal_line(vault_abs)
health = latest_health(vault_abs)
recent_recs = previous_recommendations(vault_abs)

blocked_task = queue[:tasks].find { |task| task["status"] == "blocked" }
pending_task = queue[:tasks].find { |task| task["status"] == "pending" }
top_task = stack[:current].first
recommended_inbox = oldest_inbox

signals = []
signals << "Task stack: #{stack[:current].length} current" if stack[:current].length > 0
signals << "Goals: #{goals[:excerpt]}" if goals
signals << "Notes: #{notes.length}" if notes.length < 5
signals << "Inbox: #{inbox.length} item#{inbox.length == 1 ? "" : "s"}" if inbox.any?
signals << "Queue: #{queue[:counts]["pending"]} pending" if queue[:counts]["pending"] > 0
signals << "Blocked: #{queue[:counts]["blocked"]} queue task#{queue[:counts]["blocked"] == 1 ? "" : "s"}" if queue[:counts]["blocked"] > 0
signals << "Observations: #{observations} pending" if observations > 0
signals << "Tensions: #{tensions} pending/open" if tensions > 0
signals << "Health: #{health[:file]}" if health

recommendation = nil
priority = nil
rationale = nil
after_that = nil

if top_task
  recommendation = top_task
  priority = "task-stack"
  rationale = "User-set task stack priorities override automated signals. Deferring this risks losing the explicit thread the user already chose."
elsif goals.nil?
  recommendation = "Create ops/goals.md"
  priority = "session"
  rationale = "Without goals, recommendations can only follow mechanical vault signals. Goals let future next-action choices align with what actually matters."
elsif notes.length < 5
  if recommended_inbox
    recommendation = "#{vocab["reduce"]} #{relpath(recommended_inbox, vault_abs)}"
    rationale = "This is an early-stage vault with #{notes.length} notes, so adding usable content matters more than maintenance. Processing the oldest inbox item prevents capture from going stale."
  else
    recommendation = "Capture a new #{vocab["note"]} in #{vocab["notes"]}/"
    rationale = "This is an early-stage vault with #{notes.length} notes. The graph needs more content before health, reweaving, or queue work will have much leverage."
  end
  priority = "session"
elsif observations >= vocab["observation_threshold"].to_i || tensions >= vocab["tension_threshold"].to_i
  recommendation = vocab["rethink"]
  priority = "session"
  rationale = "#{observations} pending observations and #{tensions} pending/open tensions indicate accumulated operating evidence. Deferring rethink lets methodology drift compound."
elsif inbox.length > 5
  recommendation = "#{vocab["reduce"]} #{relpath(recommended_inbox, vault_abs)}"
  priority = "session"
  rationale = "The inbox has #{inbox.length} items; processing the oldest one prevents captured material from decaying before it enters the graph."
elsif blocked_task
  recommendation = "Resolve blocked queue task #{blocked_task["id"]}"
  priority = "session"
  rationale = "A blocked queue task stops downstream processing. Clearing it restores flow before adding more backlog."
elsif health&.fetch(:severe, nil)
  recommendation = "Review #{health[:file]}"
  priority = "session"
  rationale = "The latest health report contains a severe finding. Structural issues degrade traversal and future recommendations if left unresolved."
elsif queue[:counts]["pending"] > 10
  recommendation = "#{vocab["ralph"]} 5"
  priority = "multi-session"
  rationale = "#{queue[:counts]["pending"]} queue tasks are pending. Processing a bounded batch lets newer #{vocab["note"]}s move toward connection and verification."
elsif oldest_inbox && file_age_days(oldest_inbox) > 7
  recommendation = "#{vocab["reduce"]} #{relpath(oldest_inbox, vault_abs)}"
  priority = "multi-session"
  rationale = "The oldest inbox item is #{file_age_days(oldest_inbox)} days old. Aging capture loses context, so processing it now preserves more of the original signal."
elsif health.nil?
  recommendation = "arscontexta-health"
  priority = "slow"
  rationale = "No health report was found. A bounded health check establishes a structural baseline before small issues compound."
else
  recommendation = "#{vocab["reweave"]} #{vocab["notes"]}"
  priority = "slow"
  rationale = "No urgent signal stands out. Reweaving older #{vocab["note"]}s deepens graph connections and improves future retrieval."
end

if recent_recs.last(2).count(recommendation) >= 2
  after_that = "This was recommended recently; if you intentionally skipped it, choose the next visible signal instead."
end

state = {
  "notes" => notes.length,
  "inbox" => inbox.length,
  "queue_pending" => queue[:counts]["pending"],
  "queue_blocked" => queue[:counts]["blocked"],
  "observations" => observations,
  "tensions" => tensions,
  "goals_file" => goals&.fetch(:file, nil),
  "health_report" => health&.fetch(:file, nil)
}

if format == "json"
  puts JSON.pretty_generate(
    vault: vault_abs,
    priority: priority,
    recommendation: recommendation,
    rationale: rationale,
    after_that: after_that,
    signals: state,
    displayed_signals: signals.first(4)
  )
  exit 0
end

puts "next"
puts
puts "State:"
signals.first(4).each { |signal| puts "  #{signal}" }
puts "  No urgent signals detected" if signals.empty?
puts
puts "Recommended: #{recommendation}"
puts
puts "Rationale: #{rationale}"
puts
puts "After that: #{after_that}" if after_that
