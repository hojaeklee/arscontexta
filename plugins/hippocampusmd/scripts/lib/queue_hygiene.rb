# frozen_string_literal: true

require "json"
require "pathname"
require "set"
require "time"
require "yaml"

module QueueHygiene
  DEFAULT_STALE_ACTIVE_MINUTES = 120

  QUEUE_CANDIDATES = [
    "ops/queue/queue.json",
    "ops/queue/queue.yaml",
    "ops/queue.yaml"
  ].freeze

  STATUS_ALIASES = {
    "pending" => "pending",
    "todo" => "pending",
    "queued" => "pending",
    "active" => "active",
    "in_progress" => "active",
    "in-progress" => "active",
    "running" => "active",
    "current" => "active",
    "claimed" => "active",
    "done" => "completed",
    "completed" => "completed",
    "complete" => "completed",
    "blocked" => "blocked",
    "waiting" => "blocked"
  }.freeze

  module_function

  def status(root, stale_active_minutes: DEFAULT_STALE_ACTIVE_MINUTES, now: Time.now.utc)
    root = File.expand_path(root)
    queue = load_queue(root)
    tasks = normalize_tasks(queue.fetch(:tasks, []), root)
    counts = counts_for(tasks)
    stale_active_tasks = stale_active_tasks(tasks, stale_active_minutes, now)
    counts[:stale_active] = stale_active_tasks.length
    archivable_batches = archivable_batches(tasks)
    orphan_task_files = orphan_task_files(root, tasks)
    missing_task_files = missing_task_files(tasks)
    completed_left_active = completed_left_active(tasks)
    current_stack_items = current_task_stack_items(root)
    stale_task_stack_items = stale_task_stack_items(current_stack_items, tasks, archivable_batches)
    proposals = proposals_for(
      stale_active_tasks: stale_active_tasks,
      missing_task_files: missing_task_files,
      orphan_task_files: orphan_task_files,
      completed_left_active: completed_left_active,
      stale_task_stack_items: stale_task_stack_items,
      queue_errors: queue.fetch(:errors)
    )

    {
      root: root,
      queue_file: queue[:path],
      queue_file_rel: queue[:rel_path],
      queue_errors: queue.fetch(:errors),
      counts: counts,
      tasks: tasks,
      archivable_batches: archivable_batches,
      stale_active_tasks: stale_active_tasks,
      orphan_task_files: orphan_task_files,
      missing_task_files: missing_task_files,
      completed_left_active: completed_left_active,
      stale_task_stack_items: stale_task_stack_items,
      proposals: proposals
    }
  end

  def discover_queue(root)
    root = File.expand_path(root)
    QUEUE_CANDIDATES.each do |rel_path|
      path = File.join(root, rel_path)
      return { path: path, rel_path: rel_path } if File.file?(path)
    end

    nil
  end

  def load_queue(root)
    queue = discover_queue(root)
    return { path: nil, rel_path: nil, tasks: [], errors: ["Queue file not found."] } unless queue

    raw = File.read(queue.fetch(:path))
    data =
      if File.extname(queue.fetch(:path)) == ".json"
        JSON.parse(raw)
      else
        YAML.safe_load(raw, aliases: true) || {}
      end

    {
      path: queue.fetch(:path),
      rel_path: queue.fetch(:rel_path),
      data: writable_queue_data(data),
      shape: queue_data_shape(data),
      tasks: queue_tasks_from_data(data),
      errors: []
    }
  rescue JSON::ParserError, Psych::Exception, SystemCallError, Encoding::InvalidByteSequenceError => e
    {
      path: queue && queue[:path],
      rel_path: queue && queue[:rel_path],
      data: nil,
      shape: nil,
      tasks: [],
      errors: ["Unable to load queue file: #{e.message}"]
    }
  end

  def queue_data_shape(data)
    data.is_a?(Array) ? "array" : "mapping"
  end

  def writable_queue_data(data)
    data.is_a?(Array) ? { "tasks" => data } : data
  end

  def archive_dir_for_completed_task(root, task)
    File.join(root, "ops", "queue", "archive", archive_segment_for_completed_task(task))
  end

  def archive_segment_for_completed_task(task)
    batch = task[:batch].to_s
    segment = batch.strip.empty? ? task[:id].to_s : batch
    unless safe_archive_segment?(segment)
      raise ArgumentError, "Unsafe archive segment for completed task #{task[:id]}: #{segment}"
    end

    segment
  end

  def safe_archive_segment?(segment)
    value = segment.to_s
    return false if value.strip.empty?
    return false if value != value.strip
    return false if [".", ".."].include?(value)
    return false if value.include?("/") || value.include?("\\")

    !Pathname.new(value).absolute?
  end

  def write_queue(path, data, shape)
    serializable = shape == "array" ? data.fetch("tasks") : data
    if File.extname(path) == ".json"
      File.write(path, "#{JSON.pretty_generate(serializable)}\n")
    else
      File.write(path, serializable.to_yaml)
    end
  end

  def queue_tasks_from_data(data)
    raw_tasks =
      if data.is_a?(Hash) && data["tasks"].is_a?(Array)
        data["tasks"]
      elsif data.is_a?(Array)
        data
      elsif data.is_a?(Hash)
        data.values.find { |value| value.is_a?(Array) } || []
      else
        []
      end

    raw_tasks.select { |entry| entry.is_a?(Hash) }
  end

  def normalize_status(status)
    raw = status.to_s.strip.downcase
    return "unknown" if raw.empty?

    STATUS_ALIASES.fetch(raw, raw)
  end

  def normalize_tasks(raw_tasks, root)
    raw_tasks.map.with_index do |task, index|
      id = string_value(task, "id", "task_id", "queue_id")
      file = string_value(task, "file", "task_file")
      file_path = task_file_path(root, file)
      status = normalize_status(task["status"] || task[:status])

      {
        id: id.empty? ? "task-#{index + 1}" : id,
        type: string_value(task, "type"),
        status: status,
        raw_status: task["status"] || task[:status],
        batch: string_value(task, "batch", "batch_id", "source_batch"),
        phase: string_value(task, "current_phase", "phase", "next_phase"),
        target: string_value(task, "target", "note", "source"),
        file: file,
        file_path: file_path,
        file_rel_path: file_path && rel_path(file_path, root),
        claimed_at: string_value(task, "claimed_at"),
        last_seen_at: string_value(task, "last_seen_at"),
        blocked_reason: string_value(task, "blocked_reason", "reason"),
        raw: task
      }
    end
  end

  def string_value(hash, *keys)
    keys.each do |key|
      value = hash[key] || hash[key.to_sym]
      return value.to_s unless value.nil?
    end
    ""
  end

  def task_file_path(root, file)
    return nil if file.to_s.strip.empty?

    path = file.to_s
    return path if Pathname.new(path).absolute?

    rel = path.start_with?("ops/queue/") ? path : File.join("ops", "queue", path)
    File.expand_path(rel, root)
  end

  def rel_path(path, root)
    Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
  rescue ArgumentError
    path
  end

  def counts_for(tasks)
    counts = {
      total: tasks.length,
      pending: 0,
      active: 0,
      stale_active: 0,
      blocked: 0,
      completed: 0,
      unknown: 0
    }

    tasks.each do |task|
      status = task.fetch(:status)
      if counts.key?(status.to_sym)
        counts[status.to_sym] += 1
      else
        counts[:unknown] += 1
      end
    end

    counts
  end

  def stale_active_tasks(tasks, stale_active_minutes, now)
    threshold_seconds = stale_active_minutes.to_i * 60
    tasks.select { |task| task[:status] == "active" }.map do |task|
      timestamp = parse_task_timestamp(task)
      next unless timestamp && (now - timestamp) > threshold_seconds

      task.merge(stale_since: timestamp.utc.iso8601, stale_minutes: ((now - timestamp) / 60).floor)
    end.compact
  end

  def parse_task_timestamp(task)
    value = task[:last_seen_at].to_s.empty? ? task[:claimed_at] : task[:last_seen_at]
    return nil if value.to_s.empty?

    Time.parse(value).utc
  rescue ArgumentError
    nil
  end

  def archivable_batches(tasks)
    grouped = tasks.reject { |task| task[:batch].empty? }.group_by { |task| task[:batch] }
    grouped.select { |_batch, batch_tasks| batch_tasks.all? { |task| task[:status] == "completed" } }
           .keys
           .sort
  end

  def orphan_task_files(root, tasks)
    queue_dir = File.join(root, "ops", "queue")
    return [] unless Dir.exist?(queue_dir)

    referenced = tasks.map { |task| task[:file_path] && File.expand_path(task[:file_path]) }.compact.to_set
    Dir.glob(File.join(queue_dir, "**", "*.md")).map do |path|
      next if rel_path(path, root).start_with?("ops/queue/archive/")
      next if referenced.include?(File.expand_path(path))

      rel_path(path, root)
    end.compact.sort
  end

  def missing_task_files(tasks)
    tasks.select { |task| task[:file_path] && !File.file?(task[:file_path]) }
         .map { |task| { id: task[:id], file: task[:file_rel_path], task: task } }
  end

  def completed_left_active(tasks)
    tasks.select do |task|
      task[:status] == "completed" &&
        task[:file_path] &&
        File.file?(task[:file_path]) &&
        task[:file_rel_path].start_with?("ops/queue/") &&
        !task[:file_rel_path].start_with?("ops/queue/archive/")
    end
  end

  def current_task_stack_items(root)
    path = File.join(root, "ops", "tasks.md")
    return [] unless File.file?(path)

    section = nil
    File.readlines(path, chomp: true).map do |line|
      heading = canonical_task_heading(line)
      if heading
        section = heading
        next
      elsif line.match?(/\A##\s+/)
        section = nil
      end
      next unless section == :current
      next unless line.match?(/\A-\s+\[\s\]\s+/)

      line.sub(/\A-\s+\[\s\]\s*/, "")
    end.compact
  end

  def canonical_task_heading(line)
    case line.strip.downcase
    when "## current", "## active" then :current
    when "## completed", "## done" then :completed
    when "## discoveries" then :discoveries
    else nil
    end
  end

  def stale_task_stack_items(current_items, tasks, archivable_batches)
    completed_ids = tasks.select { |task| task[:status] == "completed" }.map { |task| task[:id] }
    missing_ids = missing_task_files(tasks).map { |missing| missing[:id] }
    stale_tokens = (archivable_batches + completed_ids + missing_ids).reject(&:empty?).uniq

    current_items.select do |item|
      stale_tokens.any? { |token| text_mentions_token?(item, token) }
    end
  end

  def text_mentions_token?(text, token)
    escaped = Regexp.escape(token)
    text.match?(/(?:\A|[^[:alnum:]_-])#{escaped}(?:\z|[^[:alnum:]_-])/)
  end

  def generated_task_stack_item?(item)
    item.match?(/\A(Process queue batch|Continue queue task)\s+/)
  end

  def suggested_task_stack_items(tasks)
    tasks.select { |task| %w[pending blocked active].include?(task[:status]) }
         .map { |task| "Continue queue task #{task[:id]}" }
  end

  def stale_generated_task_stack_items(current_items, tasks, archivable_batches)
    stale_items = stale_task_stack_items(current_items, tasks, archivable_batches)
    suggested = suggested_task_stack_items(tasks)

    current_items.select do |item|
      generated_task_stack_item?(item) &&
        (stale_items.include?(item) || !suggested.include?(item))
    end
  end

  def proposals_for(
    stale_active_tasks:,
    missing_task_files:,
    orphan_task_files:,
    completed_left_active:,
    stale_task_stack_items:,
    queue_errors:
  )
    proposals = []
    queue_errors.each { |error| proposals << { type: "queue_error", message: error } }
    stale_active_tasks.each do |task|
      proposals << {
        type: "stale_active_task",
        task_id: task[:id],
        message: "Decide whether to continue, requeue, block, or reconcile stale active task #{task[:id]}."
      }
    end
    missing_task_files.each do |missing|
      proposals << {
        type: "missing_task_file",
        task_id: missing[:id],
        file: missing[:file],
        message: "Queue entry #{missing[:id]} points at missing task file #{missing[:file]}."
      }
    end
    orphan_task_files.each do |file|
      proposals << {
        type: "orphan_task_file",
        file: file,
        message: "Review orphan queue task file #{file} before reconciling."
      }
    end
    completed_left_active.each do |task|
      proposals << {
        type: "completed_left_active",
        task_id: task[:id],
        file: task[:file_rel_path],
        message: "Archive completed task file #{task[:file_rel_path]} for queue entry #{task[:id]}."
      }
    end
    stale_task_stack_items.each do |item|
      proposals << {
        type: "stale_task_stack_item",
        item: item,
        message: "Refresh stale task stack item: #{item}"
      }
    end
    proposals
  end
end
