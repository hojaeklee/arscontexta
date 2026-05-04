# Queue Lifecycle Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dependable HippocampusMD queue lifecycle hygiene layer that detects, surfaces, and safely reconciles completed batches, stale active work, orphan queue files, missing task files, and stale `ops/tasks.md` state.

**Architecture:** Extract shared queue parsing and hygiene analysis into one Ruby helper module, then keep public CLIs small and bounded: `queue-status` reads only, `queue-reconcile` performs deterministic repairs only, and existing session/next/Ralph/pipeline/archive/task helpers call the shared analyzer. The safety boundary is explicit: completed work can be archived or mechanically repaired, pending/stale active work is surfaced with proposals, and no helper silently drops pending work.

**Tech Stack:** Bash wrapper scripts, embedded Ruby CLIs, JSON/YAML queue formats, shell test scripts under `scripts/tests/`, Codex plugin manifest SemVer, local plugin cache refresh.

---

## Issue Context

Source issue: [hojaeklee/hippocampusmd#35](https://github.com/hojaeklee/hippocampusmd/issues/35)

Rename note: the repository and plugin-facing language should use `HippocampusMD` / `hippocampusmd`. Avoid introducing new `arscontexta` names. Existing historical references should only remain where they are part of old prose that is outside this change.

Sub-issue dependency order:

1. #46 defines the queue lifecycle contract.
2. #47 adds read-only queue hygiene status.
3. #48 surfaces queue hygiene in session orientation and next-action workflows.
4. #49 makes Ralph and pipeline interruption-recoverable.
5. #50 adds deterministic queue reconciliation.
6. #51 detects and refreshes `ops/tasks.md` drift from queue state.
7. #52 integrates `archive-batch` into lifecycle hygiene.

## File Structure

- Create `plugins/hippocampusmd/scripts/lib/queue_hygiene.rb`
  - Shared Ruby module for queue file discovery, JSON/YAML parsing, status normalization, batch grouping, task-file relationship checks, stale active detection, and machine-readable hygiene reports.
- Create `plugins/hippocampusmd/scripts/queue-status-vault.sh`
  - Read-only CLI for queue hygiene summaries in text and JSON.
- Create `plugins/hippocampusmd/scripts/queue-reconcile-vault.sh`
  - Deterministic repair CLI with `--dry-run` default, `--apply` for safe mechanical changes, and no pending-task deletion.
- Modify `plugins/hippocampusmd/scripts/session-orient.sh`
  - Replace queue file counting with shared queue hygiene status.
- Modify `plugins/hippocampusmd/scripts/next-vault.sh`
  - Prioritize archivable batches and interrupted/stale active work before generic backlog recommendations.
- Modify `plugins/hippocampusmd/scripts/ralph-vault.sh`
  - Add explicit claim/start/release semantics and stale active metadata while preserving `--dry-run`, `--advance`, and `--fail`.
- Modify `plugins/hippocampusmd/scripts/pipeline-vault.sh`
  - Reuse lifecycle status for `--status` and `--ready-to-archive`; surface recovery recommendations after interruption.
- Modify `plugins/hippocampusmd/scripts/tasks-vault.sh`
  - Detect stale `ops/tasks.md` entries against queue/goals state and add deterministic refresh actions.
- Modify `plugins/hippocampusmd/scripts/archive-batch-vault.sh`
  - Make archive cleanup idempotent and repairable after partial moves.
- Modify `plugins/hippocampusmd/skills/hippocampusmd-session/SKILL.md`
  - Session start and close must run or consult queue hygiene.
- Modify `plugins/hippocampusmd/skills/hippocampusmd-next/SKILL.md`
  - Next-action workflow must treat queue hygiene as a first-class signal.
- Modify `plugins/hippocampusmd/skills/hippocampusmd-ralph/SKILL.md`
  - Ralph workflow must claim/release work and recover from interrupted phases.
- Modify `plugins/hippocampusmd/skills/hippocampusmd-pipeline/SKILL.md`
  - Pipeline workflow must surface archive and recovery states.
- Modify `plugins/hippocampusmd/skills/hippocampusmd-archive-batch/SKILL.md`
  - Archive workflow must describe idempotent retry and lifecycle integration.
- Modify `plugins/hippocampusmd/reference/session-lifecycle.md`
  - Add session start briefing, persist/close hygiene, and repair boundary rules.
- Modify `plugins/hippocampusmd/reference/components.md`
  - Define queue lifecycle components and their boundaries.
- Modify `plugins/hippocampusmd/reference/methodology.md`
  - Tie queue hygiene to prospective memory and operational memory.
- Modify `plugins/hippocampusmd/generators/features/session-rhythm.md`
  - Generated instructions include session start/persist hygiene.
- Modify `plugins/hippocampusmd/generators/features/processing-pipeline.md`
  - Generated instructions include archival and interruption recovery.
- Modify `plugins/hippocampusmd/generators/features/maintenance.md`
  - Generated maintenance guidance includes queue hygiene checks.
- Modify `scripts/tests/test-queue-status-vault.sh`
  - New coverage for read-only hygiene reports.
- Modify `scripts/tests/test-queue-reconcile-vault.sh`
  - New coverage for deterministic repair and dry-run safety.
- Modify existing tests:
  - `scripts/tests/test-session-workflows.sh`
  - `scripts/tests/test-next-vault.sh`
  - `scripts/tests/test-ralph-vault.sh`
  - `scripts/tests/test-pipeline-vault.sh`
  - `scripts/tests/test-tasks-vault.sh`
  - `scripts/tests/test-archive-batch-vault.sh`
  - relevant skill tests for the updated skill docs.
- Modify `plugins/hippocampusmd/.codex-plugin/plugin.json`
  - Minor version bump, because this adds new helper CLIs and workflow behavior.

## Queue Contract

Canonical queue locations, in priority order:

1. `ops/queue/queue.json`
2. `ops/queue/queue.yaml`
3. `ops/queue.yaml`

Normalized statuses:

```ruby
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
```

Task metadata added by this plan:

```yaml
status: active
claimed_at: "2026-05-04T12:00:00Z"
claimed_by: "codex"
claim_token: "claim-001-20260504T120000Z"
claim_note: "Selected by ralph --claim"
last_seen_at: "2026-05-04T12:03:00Z"
```

Stale active threshold:

```ruby
DEFAULT_STALE_ACTIVE_MINUTES = 120
```

Read-only hygiene categories:

- `counts`: total, pending, active, stale_active, blocked, completed, unknown.
- `archivable_batches`: every task in the batch is completed.
- `stale_active_tasks`: active/claimed tasks whose `claimed_at` or `last_seen_at` is older than the threshold.
- `orphan_task_files`: markdown files in `ops/queue/` not referenced by any queue entry and not inside `ops/queue/archive/`.
- `missing_task_files`: queue entries with a `file` field whose active task file is missing.
- `completed_left_active`: completed queue entries whose task files still sit in active `ops/queue/`.
- `stale_task_stack_items`: `ops/tasks.md` current entries that point at already-completed, archived, or missing queue work.
- `proposals`: judgment-requiring decisions such as stale active work that might need continue, requeue, block, or reconcile from outputs.

Safety rules:

- Read-only helpers never mutate files.
- Reconciliation defaults to dry-run.
- `--apply` may create missing directories, normalize mechanically completed statuses, move completed active task files when queue state proves they are complete, and refresh generated task-stack lines.
- `--apply` must not delete pending queue entries or auto-advance stale active tasks.
- Stale active work becomes a proposal unless there is deterministic evidence that the task is completed.

---

### Task 1: Define Lifecycle Contract Docs (#46)

**Files:**
- Modify: `plugins/hippocampusmd/reference/session-lifecycle.md`
- Modify: `plugins/hippocampusmd/reference/components.md`
- Modify: `plugins/hippocampusmd/reference/methodology.md`
- Modify: `plugins/hippocampusmd/generators/features/session-rhythm.md`
- Modify: `plugins/hippocampusmd/generators/features/processing-pipeline.md`
- Modify: `plugins/hippocampusmd/generators/features/maintenance.md`
- Modify tests as needed: skill/reference smoke tests that assert lifecycle wording

- [ ] **Step 1: Add failing documentation assertions**

Add assertions to the relevant existing shell tests, or create a narrow new test if no reference-doc test exists:

```bash
assert_contains "$PROJECT_ROOT/plugins/hippocampusmd/reference/session-lifecycle.md" "Session Start Queue Briefing"
assert_contains "$PROJECT_ROOT/plugins/hippocampusmd/reference/session-lifecycle.md" "Persist Queue Hygiene"
assert_contains "$PROJECT_ROOT/plugins/hippocampusmd/reference/session-lifecycle.md" "Repair Boundary"
assert_contains "$PROJECT_ROOT/plugins/hippocampusmd/reference/components.md" "queue-status"
assert_contains "$PROJECT_ROOT/plugins/hippocampusmd/reference/components.md" "queue-reconcile"
assert_contains "$PROJECT_ROOT/plugins/hippocampusmd/generators/features/processing-pipeline.md" "interrupted or stale-active work"
```

- [ ] **Step 2: Run the doc assertions and verify they fail**

Run:

```bash
scripts/tests/test-session-workflows.sh
```

Expected: FAIL on missing queue lifecycle contract text.

- [ ] **Step 3: Update lifecycle documentation**

Add this section to `plugins/hippocampusmd/reference/session-lifecycle.md`:

```markdown
## Queue Lifecycle Hygiene

### Session Start Queue Briefing

Every session orientation reports queue state from structured queue files, not only file counts. The briefing includes pending, active, stale-active, blocked, completed, unknown, archivable batches, orphan queue files, queue entries with missing task files, and stale `ops/tasks.md` entries.

### Persist Queue Hygiene

Every processing persist or session close checks for completed-but-unarchived batches, interrupted Ralph or pipeline work, stale active claims, orphan queue files, and task-stack drift. The close path records judgment-requiring work as proposals rather than silently mutating pending state.

### Repair Boundary

Health and status helpers detect. Deterministic cleaners repair only reversible mechanical issues: missing directories, completed task files left in the active queue folder, generated task-stack drift, and idempotent archive retries. Pending stale tasks and stale active claims require a continue, requeue, block, or reconcile decision.
```

Add this component table to `plugins/hippocampusmd/reference/components.md`:

```markdown
| Component | Boundary | Repairs? | Purpose |
| --- | --- | --- | --- |
| `queue-status` | Read-only | No | Summarize queue counts, archivable batches, stale active work, orphan task files, missing task files, and task-stack drift. |
| `archive-batch` | Completed batches only | Yes | Move completed batch task files into `ops/queue/archive/`, write a summary, and remove archived entries from active queue state. |
| `queue-reconcile` | Deterministic inconsistencies | Dry-run by default | Repair mechanical drift without dropping pending work or judging task outcomes. |
| `task-refresh` | `ops/tasks.md` generated lines | Yes with explicit command | Refresh task-stack entries from queue and goals state while preserving human-authored priorities. |
```

Add a short note to `plugins/hippocampusmd/reference/methodology.md`:

```markdown
Queue lifecycle hygiene externalizes prospective memory. The queue is operational memory, so the system must make completed work, interrupted work, and stale coordination traces visible at session boundaries instead of relying on an agent or human to remember cleanup.
```

- [ ] **Step 4: Update generated feature guidance**

In `session-rhythm.md`, add:

```markdown
Session start runs a queue briefing before choosing work. Session close runs queue hygiene before writing the handoff.
```

In `processing-pipeline.md`, add:

```markdown
Pipeline work must leave recoverable state. Interrupted or stale-active work is surfaced by queue hygiene as a decision, while completed batches are surfaced for archive.
```

In `maintenance.md`, add:

```markdown
Maintenance includes queue hygiene: read-only detection first, deterministic repair second, judgment repairs as proposals.
```

- [ ] **Step 5: Run focused doc tests**

Run:

```bash
scripts/tests/test-session-workflows.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add plugins/hippocampusmd/reference/session-lifecycle.md plugins/hippocampusmd/reference/components.md plugins/hippocampusmd/reference/methodology.md plugins/hippocampusmd/generators/features/session-rhythm.md plugins/hippocampusmd/generators/features/processing-pipeline.md plugins/hippocampusmd/generators/features/maintenance.md scripts/tests
git commit -m "docs: define queue lifecycle hygiene contract"
```

### Task 2: Add Shared Queue Hygiene Analyzer (#47 foundation)

**Files:**
- Create: `plugins/hippocampusmd/scripts/lib/queue_hygiene.rb`
- Create: `scripts/tests/test-queue-status-vault.sh` first half, targeting the library through the future CLI

- [ ] **Step 1: Write failing queue status test fixture**

Create `scripts/tests/test-queue-status-vault.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
STATUS="$PROJECT_ROOT/plugins/hippocampusmd/scripts/queue-status-vault.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -Fq -- "$needle" || fail "expected output to contain: $needle"
}
assert_not_exists() { [[ ! -e "$1" ]] || fail "expected file not to exist: $1"; }

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hippocampusmd-queue-status-test.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

vault="$tmp_dir/vault"
mkdir -p "$vault/ops/queue/archive" "$vault/ops/tasks.md.d"
cat > "$vault/ops/queue/queue.json" <<'JSON'
{
  "tasks": [
    {"id":"alpha","type":"extract","status":"done","batch":"alpha","file":"alpha.md"},
    {"id":"alpha-001","type":"claim","status":"completed","batch":"alpha","file":"alpha-001.md"},
    {"id":"beta-001","type":"claim","status":"pending","batch":"beta","file":"beta-001.md"},
    {"id":"gamma-001","type":"claim","status":"active","batch":"gamma","file":"gamma-001.md","claimed_at":"2020-01-01T00:00:00Z"},
    {"id":"delta-001","type":"claim","status":"blocked","batch":"delta","file":"delta-001.md","blocked_reason":"Missing source"},
    {"id":"epsilon-001","type":"claim","status":"pending","batch":"epsilon","file":"missing.md"}
  ]
}
JSON
printf '# Alpha\n' > "$vault/ops/queue/alpha.md"
printf '# Alpha 001\n' > "$vault/ops/queue/alpha-001.md"
printf '# Beta 001\n' > "$vault/ops/queue/beta-001.md"
printf '# Gamma 001\n' > "$vault/ops/queue/gamma-001.md"
printf '# Delta 001\n' > "$vault/ops/queue/delta-001.md"
printf '# Orphan\n' > "$vault/ops/queue/orphan.md"
cat > "$vault/ops/tasks.md" <<'EOF'
# Task Stack

## Current
- [ ] Process queue batch alpha
- [ ] Review unrelated human task

## Completed

## Discoveries
EOF

output="$("$STATUS" "$vault")"
assert_contains "$output" "Queue hygiene status"
assert_contains "$output" "Pending: 2 | Active: 1 | Stale active: 1 | Blocked: 1 | Completed: 2"
assert_contains "$output" "Archivable batches: alpha"
assert_contains "$output" "Stale active tasks: gamma-001"
assert_contains "$output" "Orphan task files: ops/queue/orphan.md"
assert_contains "$output" "Missing task files: epsilon-001 -> ops/queue/missing.md"
assert_contains "$output" "Stale task stack: Process queue batch alpha"

json_output="$("$STATUS" "$vault" --format json)"
assert_contains "$json_output" '"archivable_batches"'
assert_contains "$json_output" '"alpha"'
assert_contains "$json_output" '"stale_active_tasks"'
assert_not_exists "$vault/ops/queue/archive/alpha.md"

printf 'PASS: queue-status-vault checks\n'
```

- [ ] **Step 2: Run test and verify it fails because CLI does not exist**

Run:

```bash
scripts/tests/test-queue-status-vault.sh
```

Expected: FAIL with `queue-status-vault.sh` missing.

- [ ] **Step 3: Implement shared analyzer**

Create `plugins/hippocampusmd/scripts/lib/queue_hygiene.rb`:

```ruby
# frozen_string_literal: true

require "json"
require "pathname"
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
    "pending" => "pending", "todo" => "pending", "queued" => "pending",
    "active" => "active", "in_progress" => "active", "in-progress" => "active",
    "running" => "active", "current" => "active", "claimed" => "active",
    "done" => "completed", "completed" => "completed", "complete" => "completed",
    "blocked" => "blocked", "waiting" => "blocked"
  }.freeze

  module_function

  def rel_path(path, root)
    Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
  rescue ArgumentError
    path
  end

  def queue_file(root)
    QUEUE_CANDIDATES.find { |rel| File.file?(File.join(root, rel)) }
  end

  def normalize_status(value)
    STATUS_ALIASES.fetch(value.to_s.downcase, value.to_s.empty? ? "unknown" : value.to_s.downcase)
  end

  def load_queue(root)
    rel = queue_file(root)
    return { exists: false, file: nil, shape: "hash", data: { "tasks" => [] }, tasks: [] } unless rel

    path = File.join(root, rel)
    raw = File.read(path)
    parsed = rel.end_with?(".json") ? JSON.parse(raw) : YAML.safe_load(raw, aliases: true)
    data, shape = parsed.is_a?(Array) ? [{ "tasks" => parsed }, "array"] : [parsed || {}, "hash"]
    data["tasks"] ||= []
    tasks = data["tasks"].select { |entry| entry.is_a?(Hash) }
    { exists: true, file: rel, path: path, shape: shape, data: data, tasks: normalize_tasks(tasks) }
  rescue JSON::ParserError, Psych::Exception, StandardError => e
    { exists: true, file: rel, path: path, shape: "hash", data: { "tasks" => [] }, tasks: [], error: e.message }
  end

  def normalize_tasks(tasks)
    tasks.map do |task|
      id = (task["id"] || task[:id] || task["task_id"] || task[:task_id]).to_s
      file = task["file"] || task[:file]
      status = normalize_status(task["status"] || task[:status])
      {
        "id" => id.empty? ? "(no id)" : id,
        "status" => status,
        "raw_status" => task["status"] || task[:status],
        "phase" => task["current_phase"] || task[:current_phase] || task["phase"] || task[:phase],
        "target" => task["target"] || task[:target] || task["source"] || task[:source] || id,
        "batch" => task["batch"] || task[:batch] || task["batch_id"] || task[:batch_id],
        "file" => file,
        "claimed_at" => task["claimed_at"] || task[:claimed_at],
        "last_seen_at" => task["last_seen_at"] || task[:last_seen_at],
        "raw" => task
      }
    end
  end

  def task_file_path(root, file)
    return nil if file.to_s.empty?
    path = Pathname.new(file.to_s)
    path.absolute? ? path.to_s : File.join(root, "ops", "queue", file.to_s)
  end

  def stale_active?(task, now, threshold_minutes)
    return false unless task["status"] == "active"

    stamp = task["last_seen_at"] || task["claimed_at"]
    return false if stamp.to_s.empty?

    parsed = Time.parse(stamp).utc
    parsed <= now - (threshold_minutes * 60)
  rescue ArgumentError
    true
  end

  def parse_task_stack(root)
    path = File.join(root, "ops/tasks.md")
    return [] unless File.file?(path)

    current = []
    in_current = false
    File.readlines(path, chomp: true).each do |line|
      stripped = line.strip.downcase
      if ["## current", "## active"].include?(stripped)
        in_current = true
        next
      elsif line.start_with?("## ")
        in_current = false
      end
      current << line.sub(/\A-\s+\[\s\]\s*/, "") if in_current && line.match?(/\A-\s+\[\s\]\s+/)
    end
    current
  end

  def status(root, now: Time.now.utc, stale_active_minutes: DEFAULT_STALE_ACTIVE_MINUTES)
    queue = load_queue(root)
    tasks = queue[:tasks]
    counts = Hash.new(0)
    tasks.each { |task| counts[task["status"]] += 1 }
    stale_active = tasks.select { |task| stale_active?(task, now, stale_active_minutes) }
    batches = tasks.group_by { |task| task["batch"].to_s }.reject { |batch, _| batch.empty? }
    archivable = batches.select { |_, items| items.all? { |task| task["status"] == "completed" } }.keys.sort
    referenced_files = tasks.filter_map { |task| task_file_path(root, task["file"]) }.map { |path| File.expand_path(path) }.to_set
    active_files = Dir.glob(File.join(root, "ops/queue", "*.md")).sort
    orphan_files = active_files.reject { |path| referenced_files.include?(File.expand_path(path)) }
    missing_files = tasks.select { |task| !task["file"].to_s.empty? && !File.file?(task_file_path(root, task["file"])) }
    completed_left_active = tasks.select do |task|
      task["status"] == "completed" && !task["file"].to_s.empty? && File.file?(task_file_path(root, task["file"]))
    end
    current_stack = parse_task_stack(root)
    stale_stack = current_stack.select do |item|
      archivable.any? { |batch| item.downcase.include?(batch.downcase) } ||
        tasks.any? { |task| task["status"] == "completed" && item.downcase.include?(task["id"].downcase) }
    end

    {
      queue: queue,
      counts: {
        total: tasks.length,
        pending: counts["pending"],
        active: counts["active"],
        stale_active: stale_active.length,
        blocked: counts["blocked"],
        completed: counts["completed"],
        unknown: counts["unknown"]
      },
      archivable_batches: archivable,
      stale_active_tasks: stale_active,
      orphan_task_files: orphan_files.map { |path| rel_path(path, root) },
      missing_task_files: missing_files,
      completed_left_active: completed_left_active,
      stale_task_stack_items: stale_stack,
      proposals: stale_active.map { |task| "Review stale active task #{task["id"]}: continue, requeue, block, or reconcile from outputs." }
    }
  end
end
```

- [ ] **Step 4: Commit shared analyzer with failing CLI test**

```bash
git add plugins/hippocampusmd/scripts/lib/queue_hygiene.rb scripts/tests/test-queue-status-vault.sh
git commit -m "test: define queue hygiene status expectations"
```

### Task 3: Add Read-Only Queue Status CLI (#47)

**Files:**
- Create: `plugins/hippocampusmd/scripts/queue-status-vault.sh`
- Modify: `scripts/tests/test-queue-status-vault.sh`

- [ ] **Step 1: Implement CLI wrapper**

Create `plugins/hippocampusmd/scripts/queue-status-vault.sh`:

```bash
#!/usr/bin/env bash
if command -v ruby >/dev/null 2>&1; then
  exec ruby -x "$0" "$@"
fi
printf 'Ruby is required for queue hygiene status.\n' >&2
exit 1

#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "lib/queue_hygiene"

def usage
  warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] [--format text|json] [--stale-active-minutes N]"
end

vault = "."
format = "text"
stale_minutes = QueueHygiene::DEFAULT_STALE_ACTIVE_MINUTES

args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "--format"
    format = args.shift
  when "--stale-active-minutes"
    stale_minutes = Integer(args.shift || "")
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
report = QueueHygiene.status(root, stale_active_minutes: stale_minutes)

if format == "json"
  puts JSON.pretty_generate(
    vault: root,
    queue_file: report[:queue][:file],
    counts: report[:counts],
    archivable_batches: report[:archivable_batches],
    stale_active_tasks: report[:stale_active_tasks].map { |task| task.slice("id", "phase", "target", "batch", "claimed_at", "last_seen_at") },
    orphan_task_files: report[:orphan_task_files],
    missing_task_files: report[:missing_task_files].map { |task| { id: task["id"], file: QueueHygiene.rel_path(QueueHygiene.task_file_path(root, task["file"]), root) } },
    completed_left_active: report[:completed_left_active].map { |task| task["id"] },
    stale_task_stack_items: report[:stale_task_stack_items],
    proposals: report[:proposals]
  )
  exit 0
end

puts "Queue hygiene status"
puts "Vault: #{root}"
puts "Queue file: #{report[:queue][:file] || "missing"}"
if report[:queue][:error]
  puts "Queue parse error: #{report[:queue][:error]}"
  exit 1
end
counts = report[:counts]
puts "Pending: #{counts[:pending]} | Active: #{counts[:active]} | Stale active: #{counts[:stale_active]} | Blocked: #{counts[:blocked]} | Completed: #{counts[:completed]}"
puts "Archivable batches: #{report[:archivable_batches].empty? ? "none" : report[:archivable_batches].join(", ")}"
puts "Stale active tasks: #{report[:stale_active_tasks].empty? ? "none" : report[:stale_active_tasks].map { |task| task["id"] }.join(", ")}"
puts "Orphan task files: #{report[:orphan_task_files].empty? ? "none" : report[:orphan_task_files].join(", ")}"
missing = report[:missing_task_files].map { |task| "#{task["id"]} -> #{QueueHygiene.rel_path(QueueHygiene.task_file_path(root, task["file"]), root)}" }
puts "Missing task files: #{missing.empty? ? "none" : missing.join(", ")}"
puts "Stale task stack: #{report[:stale_task_stack_items].empty? ? "none" : report[:stale_task_stack_items].join(" | ")}"
unless report[:proposals].empty?
  puts "Proposals:"
  report[:proposals].each { |proposal| puts "  - #{proposal}" }
end
```

- [ ] **Step 2: Make executable and run focused test**

Run:

```bash
chmod +x plugins/hippocampusmd/scripts/queue-status-vault.sh
scripts/tests/test-queue-status-vault.sh
```

Expected: PASS.

- [ ] **Step 3: Run existing queue-adjacent tests**

Run:

```bash
scripts/tests/test-ralph-vault.sh
scripts/tests/test-pipeline-vault.sh
scripts/tests/test-tasks-vault.sh
scripts/tests/test-archive-batch-vault.sh
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add plugins/hippocampusmd/scripts/queue-status-vault.sh plugins/hippocampusmd/scripts/lib/queue_hygiene.rb scripts/tests/test-queue-status-vault.sh
git commit -m "feat: add read-only queue hygiene status"
```

### Task 4: Surface Hygiene in Session Orientation and Next (#48)

**Files:**
- Modify: `plugins/hippocampusmd/scripts/session-orient.sh`
- Modify: `plugins/hippocampusmd/scripts/next-vault.sh`
- Modify: `scripts/tests/test-session-workflows.sh`
- Modify: `scripts/tests/test-next-vault.sh`
- Modify: `plugins/hippocampusmd/skills/hippocampusmd-session/SKILL.md`
- Modify: `plugins/hippocampusmd/skills/hippocampusmd-next/SKILL.md`

- [ ] **Step 1: Add failing session orientation assertions**

Extend `scripts/tests/test-session-workflows.sh` by replacing the one-file queue fixture with a structured queue fixture:

```bash
cat > "$vault/ops/queue/queue.json" <<'EOF'
{"tasks":[
  {"id":"alpha","status":"done","batch":"alpha","file":"alpha.md"},
  {"id":"alpha-001","status":"completed","batch":"alpha","file":"alpha-001.md"},
  {"id":"gamma-001","status":"active","batch":"gamma","file":"gamma-001.md","claimed_at":"2020-01-01T00:00:00Z"}
]}
EOF
printf '# Alpha\n' > "$vault/ops/queue/alpha.md"
printf '# Alpha 001\n' > "$vault/ops/queue/alpha-001.md"
printf '# Gamma 001\n' > "$vault/ops/queue/gamma-001.md"
```

Add assertions:

```bash
assert_contains "$orient_output" "Queue hygiene:"
assert_contains "$orient_output" "Archivable batches: alpha"
assert_contains "$orient_output" "Stale active tasks: gamma-001"
assert_contains "$orient_output" "Recommended next action: Archive completed queue batch alpha"
assert_contains "$orient_json" '"archivable_batches"'
```

- [ ] **Step 2: Add failing next-action assertions**

Add two fixtures to `scripts/tests/test-next-vault.sh` before the generic pending queue backlog fixture:

```bash
archive_vault="$tmp_dir/archive-vault"
make_vault "$archive_vault"
add_notes "$archive_vault" 8
cat > "$archive_vault/self/goals.md" <<'EOF'
# Goals
- Keep pipeline clean
EOF
cat > "$archive_vault/ops/queue/queue.json" <<'EOF'
{"tasks":[
  {"id":"alpha","status":"done","batch":"alpha","file":"alpha.md"},
  {"id":"alpha-001","status":"completed","batch":"alpha","file":"alpha-001.md"}
]}
EOF
archive_output="$("$NEXT" "$archive_vault")"
assert_contains "$archive_output" "Recommended: hippocampusmd-archive-batch --batch alpha"
assert_contains "$archive_output" "completed queue batch is ready to archive"

stale_active_vault="$tmp_dir/stale-active-vault"
make_vault "$stale_active_vault"
add_notes "$stale_active_vault" 8
cat > "$stale_active_vault/self/goals.md" <<'EOF'
# Goals
- Recover interrupted work
EOF
cat > "$stale_active_vault/ops/queue/queue.json" <<'EOF'
{"tasks":[{"id":"gamma-001","status":"active","batch":"gamma","file":"gamma-001.md","claimed_at":"2020-01-01T00:00:00Z"}]}
EOF
stale_output="$("$NEXT" "$stale_active_vault")"
assert_contains "$stale_output" "Recommended: Review stale active queue task gamma-001"
assert_contains "$stale_output" "continue, requeue, block, or reconcile"
```

- [ ] **Step 3: Run tests and verify failures**

Run:

```bash
scripts/tests/test-session-workflows.sh
scripts/tests/test-next-vault.sh
```

Expected: FAIL because orientation and next do not consume `QueueHygiene`.

- [ ] **Step 4: Update `session-orient.sh`**

Port the Bash script to the existing embedded Ruby pattern or shell out to the Ruby helper. The simplest implementation is a Ruby-backed script that requires `lib/queue_hygiene` and emits existing inventory plus:

```text
Queue hygiene:
  Pending: 0 | Active: 1 | Stale active: 1 | Blocked: 0 | Completed: 2
  Archivable batches: alpha
  Stale active tasks: gamma-001
  Orphan task files: none
  Missing task files: none
```

Update next-action precedence in orientation:

```ruby
if report[:archivable_batches].any?
  next_action = "Archive completed queue batch #{report[:archivable_batches].first}."
elsif report[:stale_active_tasks].any?
  next_action = "Review stale active queue task #{report[:stale_active_tasks].first["id"]}."
elsif inbox_count.positive?
  next_action = "Review inbox pressure and decide whether to seed or process captured material."
end
```

- [ ] **Step 5: Update `next-vault.sh`**

Require `lib/queue_hygiene` and calculate `hygiene = QueueHygiene.status(vault_abs)` after parsing the vault. Insert these precedence branches after explicit task-stack and goals checks, before observations/inbox/blocked/generic queue backlog:

```ruby
if hygiene[:archivable_batches].any?
  batch = hygiene[:archivable_batches].first
  recommendation = "hippocampusmd-archive-batch --batch #{batch}"
  priority = "session"
  rationale = "A completed queue batch is ready to archive. Archiving it removes active queue state and prevents future sessions from carrying completed operational memory."
elsif hygiene[:stale_active_tasks].any?
  task = hygiene[:stale_active_tasks].first
  recommendation = "Review stale active queue task #{task["id"]}"
  priority = "session"
  rationale = "This task appears interrupted or stale-active. Decide whether to continue, requeue, block, or reconcile from observed outputs before selecting fresh work."
end
```

Include `archivable_batches` and `stale_active` in JSON `signals`.

- [ ] **Step 6: Update skill docs**

In `hippocampusmd-session/SKILL.md`, add:

```markdown
At session start, consult `plugins/hippocampusmd/scripts/session-orient.sh` or `queue-status-vault.sh` before choosing work. At session close, check completed batches, stale active claims, orphan task files, and task-stack drift.
```

In `hippocampusmd-next/SKILL.md`, add:

```markdown
Treat queue hygiene as a first-class next-action signal. Completed batches ready to archive and stale-active work outrank generic pending queue backlog.
```

- [ ] **Step 7: Run focused tests**

Run:

```bash
scripts/tests/test-session-workflows.sh
scripts/tests/test-next-vault.sh
scripts/tests/test-session-skill.sh
scripts/tests/test-next-vault.sh
```

Expected: PASS. If `test-session-skill.sh` does not exist, run the relevant skill test that checks `hippocampusmd-session/SKILL.md`.

- [ ] **Step 8: Commit**

```bash
git add plugins/hippocampusmd/scripts/session-orient.sh plugins/hippocampusmd/scripts/next-vault.sh plugins/hippocampusmd/skills/hippocampusmd-session/SKILL.md plugins/hippocampusmd/skills/hippocampusmd-next/SKILL.md scripts/tests/test-session-workflows.sh scripts/tests/test-next-vault.sh
git commit -m "feat: surface queue hygiene in session workflows"
```

### Task 5: Make Ralph and Pipeline Interruption-Recoverable (#49)

**Files:**
- Modify: `plugins/hippocampusmd/scripts/ralph-vault.sh`
- Modify: `plugins/hippocampusmd/scripts/pipeline-vault.sh`
- Modify: `scripts/tests/test-ralph-vault.sh`
- Modify: `scripts/tests/test-pipeline-vault.sh`
- Modify: `plugins/hippocampusmd/skills/hippocampusmd-ralph/SKILL.md`
- Modify: `plugins/hippocampusmd/skills/hippocampusmd-pipeline/SKILL.md`

- [ ] **Step 1: Add failing Ralph claim/release tests**

Extend `scripts/tests/test-ralph-vault.sh`:

```bash
claim_output="$("$RALPH" "$yaml_vault" --claim claim-002 --format json)"
assert_contains "$claim_output" '"status": "active"'
assert_contains "$claim_output" '"claim_token"'
assert_contains "$(cat "$yaml_vault/ops/queue/queue.yaml")" "claimed_at:"
assert_contains "$(cat "$yaml_vault/ops/queue/queue.yaml")" "claim_token:"

release_output="$("$RALPH" "$yaml_vault" --release claim-002 --reason "Session interrupted before review")"
assert_contains "$release_output" "Released: claim-002"
assert_contains "$(cat "$yaml_vault/ops/queue/queue.yaml")" "status: pending"
assert_contains "$(cat "$yaml_vault/ops/queue/queue.yaml")" "release_reason: Session interrupted before review"
```

Add a stale active dry-run fixture:

```bash
stale_vault="$tmp_dir/stale"
mkdir -p "$stale_vault/ops/queue"
cat > "$stale_vault/ops/queue/queue.json" <<'EOF'
{"tasks":[{"id":"stale-001","status":"active","current_phase":"reflect","target":"Stale Claim","claimed_at":"2020-01-01T00:00:00Z"}]}
EOF
stale_output="$("$RALPH" "$stale_vault" --dry-run)"
assert_contains "$stale_output" "Stale active tasks:"
assert_contains "$stale_output" "stale-001"
assert_contains "$stale_output" "use --release, --fail, or --advance after review"
```

- [ ] **Step 2: Add failing pipeline recovery tests**

Extend `scripts/tests/test-pipeline-vault.sh`:

```bash
recovery_vault="$tmp_dir/recovery"
mkdir -p "$recovery_vault/ops/queue"
cat > "$recovery_vault/ops/queue/queue.json" <<'EOF'
{"tasks":[{"id":"recover-001","status":"active","batch":"recover","file":"recover-001.md","current_phase":"verify","claimed_at":"2020-01-01T00:00:00Z"}]}
EOF
recovery_output="$("$PIPELINE" "$recovery_vault" --status --batch recover)"
assert_contains "$recovery_output" "Stale active tasks:"
assert_contains "$recovery_output" "recover-001"
assert_contains "$recovery_output" "Next action: review stale active work before continuing batch recover"
```

- [ ] **Step 3: Run tests and verify failures**

Run:

```bash
scripts/tests/test-ralph-vault.sh
scripts/tests/test-pipeline-vault.sh
```

Expected: FAIL on missing `--claim`, `--release`, and stale active reporting.

- [ ] **Step 4: Implement Ralph claim and release**

Update `usage` in `ralph-vault.sh`:

```ruby
warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] --dry-run|--claim TASK_ID|--release TASK_ID|--advance TASK_ID|--fail TASK_ID --reason TEXT [--limit N] [--batch ID] [--type PHASE] [--format text|json]"
```

Parse:

```ruby
when "--claim"
  mode = :claim
  task_id = args.shift
when "--release"
  mode = :release
  task_id = args.shift
```

Add helper:

```ruby
def claim_token_for(task_id)
  "#{task_id}-#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}"
end
```

In `:claim` mode:

```ruby
task = find_task!(tasks, task_id)
if status_for(task) != "pending"
  warn "Task #{task_id} is not pending; current status=#{status_for(task)}"
  exit 1
end
now = Time.now.utc.iso8601
task["status"] = "active"
task["claimed_at"] = now
task["last_seen_at"] = now
task["claimed_by"] = ENV.fetch("USER", "codex")
task["claim_token"] = claim_token_for(task_id)
write_queue(queue_path, queue_data, queue_shape)
```

In `:release` mode:

```ruby
task = find_task!(tasks, task_id)
task["status"] = "pending"
task["released_at"] = Time.now.utc.iso8601
task["release_reason"] = reason || "Released for recovery"
task.delete("last_seen_at")
write_queue(queue_path, queue_data, queue_shape)
```

In `--dry-run`, require `lib/queue_hygiene` and print stale active tasks after pending selection:

```ruby
hygiene = QueueHygiene.status(vault)
if hygiene[:stale_active_tasks].any?
  puts "Stale active tasks:"
  hygiene[:stale_active_tasks].each { |task| puts "  #{task["id"]} -- use --release, --fail, or --advance after review" }
end
```

- [ ] **Step 5: Implement pipeline recovery surfacing**

In `pipeline-vault.sh --status`, calculate hygiene and filter stale active tasks to the requested batch:

```ruby
hygiene = QueueHygiene.status(vault)
stale_for_batch = hygiene[:stale_active_tasks].select { |task| task["batch"].to_s == batch || task["id"] == batch }
```

Update `next_action`:

```ruby
return "review stale active work before continuing batch #{batch}" if stale_for_batch.any?
```

Print:

```ruby
if stale_for_batch.any?
  puts
  puts "Stale active tasks:"
  stale_for_batch.each { |task| puts "  #{task["id"]} -- #{task["phase"] || "unknown phase"}" }
end
```

- [ ] **Step 6: Update skill docs**

In Ralph skill:

```markdown
Before handing a task to a worker, claim it with `ralph-vault.sh --claim TASK_ID`. If the session is interrupted or worker output cannot be reviewed, release it with `--release TASK_ID --reason TEXT` rather than leaving it indistinguishable from never-started pending work.
```

In pipeline skill:

```markdown
Pipeline status must surface stale active work before selecting more tasks. Recovery choices are continue, release to pending, block with reason, or advance only after evidence review.
```

- [ ] **Step 7: Run focused tests**

Run:

```bash
scripts/tests/test-ralph-vault.sh
scripts/tests/test-pipeline-vault.sh
scripts/tests/test-ralph-skill.sh
scripts/tests/test-pipeline-skill.sh
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add plugins/hippocampusmd/scripts/ralph-vault.sh plugins/hippocampusmd/scripts/pipeline-vault.sh plugins/hippocampusmd/skills/hippocampusmd-ralph/SKILL.md plugins/hippocampusmd/skills/hippocampusmd-pipeline/SKILL.md scripts/tests/test-ralph-vault.sh scripts/tests/test-pipeline-vault.sh
git commit -m "feat: make queue work interruption recoverable"
```

### Task 6: Add Deterministic Queue Reconciliation (#50)

**Files:**
- Create: `plugins/hippocampusmd/scripts/queue-reconcile-vault.sh`
- Create: `scripts/tests/test-queue-reconcile-vault.sh`
- Modify: `plugins/hippocampusmd/scripts/lib/queue_hygiene.rb`

- [ ] **Step 1: Write failing reconciliation tests**

Create `scripts/tests/test-queue-reconcile-vault.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
RECONCILE="$PROJECT_ROOT/plugins/hippocampusmd/scripts/queue-reconcile-vault.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -Fq -- "$needle" || fail "expected output to contain: $needle"
}
assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    fail "did not expect output to contain: $needle"
  fi
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hippocampusmd-queue-reconcile-test.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

vault="$tmp_dir/vault"
mkdir -p "$vault/ops/queue"
cat > "$vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: alpha
    status: done
    batch: alpha
    file: alpha.md
  - id: alpha-001
    status: completed
    batch: alpha
    file: alpha-001.md
  - id: beta-001
    status: pending
    batch: beta
    file: missing.md
  - id: gamma-001
    status: active
    batch: gamma
    file: gamma-001.md
    claimed_at: "2020-01-01T00:00:00Z"
EOF
printf '# Alpha\n' > "$vault/ops/queue/alpha.md"
printf '# Alpha 001\n' > "$vault/ops/queue/alpha-001.md"
printf '# Gamma 001\n' > "$vault/ops/queue/gamma-001.md"

dry_output="$("$RECONCILE" "$vault")"
assert_contains "$dry_output" "Mode: dry run"
assert_contains "$dry_output" "Would create archive directory"
assert_contains "$dry_output" "Would move completed task file ops/queue/alpha.md"
assert_contains "$dry_output" "Proposal: review stale active task gamma-001"
[[ -f "$vault/ops/queue/alpha.md" ]] || fail "dry-run must not move alpha.md"

apply_output="$("$RECONCILE" "$vault" --apply)"
assert_contains "$apply_output" "Mode: apply"
assert_contains "$apply_output" "Moved completed task file ops/queue/alpha.md"
assert_contains "$apply_output" "Moved completed task file ops/queue/alpha-001.md"
assert_contains "$apply_output" "Proposal: review stale active task gamma-001"
[[ -f "$vault/ops/queue/archive/alpha/alpha.md" ]] || fail "alpha.md should move to deterministic archive"
[[ -f "$vault/ops/queue/archive/alpha/alpha-001.md" ]] || fail "alpha-001.md should move to deterministic archive"
[[ -f "$vault/ops/queue/gamma-001.md" ]] || fail "active task file must remain active"
assert_contains "$(cat "$vault/ops/queue/queue.yaml")" "beta-001"
assert_not_contains "$(cat "$vault/ops/queue/queue.yaml")" "status: dropped"

second_apply="$("$RECONCILE" "$vault" --apply)"
assert_contains "$second_apply" "No deterministic repairs needed"

printf 'PASS: queue-reconcile-vault checks\n'
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
scripts/tests/test-queue-reconcile-vault.sh
```

Expected: FAIL because `queue-reconcile-vault.sh` does not exist.

- [ ] **Step 3: Implement deterministic repair helpers**

Add to `queue_hygiene.rb`:

```ruby
def archive_dir_for_completed_task(root, task)
  batch = task["batch"].to_s.empty? ? task["id"] : task["batch"].to_s
  File.join(root, "ops", "queue", "archive", batch)
end

def write_queue(path, data, shape)
  serializable = shape == "array" ? data.fetch("tasks") : data
  if File.extname(path) == ".json"
    File.write(path, "#{JSON.pretty_generate(serializable)}\n")
  else
    File.write(path, serializable.to_yaml)
  end
end
```

- [ ] **Step 4: Implement `queue-reconcile-vault.sh`**

Create `plugins/hippocampusmd/scripts/queue-reconcile-vault.sh`:

```bash
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
    vault = arg if vault == "."
  end
end

root = File.realpath(vault)
report = QueueHygiene.status(root)
actions = []

report[:completed_left_active].each do |task|
  source = QueueHygiene.task_file_path(root, task["file"])
  archive_dir = QueueHygiene.archive_dir_for_completed_task(root, task)
  destination = File.join(archive_dir, File.basename(source))
  if apply
    FileUtils.mkdir_p(archive_dir)
    FileUtils.mv(source, destination) if File.file?(source) && !File.exist?(destination)
    actions << "Moved completed task file #{QueueHygiene.rel_path(source, root)}"
  else
    actions << "Would create archive directory #{QueueHygiene.rel_path(archive_dir, root)}"
    actions << "Would move completed task file #{QueueHygiene.rel_path(source, root)}"
  end
end

proposals = report[:proposals].map { |proposal| "Proposal: #{proposal.sub(/\AReview /, "review ")}" }
if format == "json"
  puts JSON.pretty_generate(mode: apply ? "apply" : "dry-run", actions: actions, proposals: proposals)
  exit 0
end

puts "Queue reconcile"
puts "Mode: #{apply ? "apply" : "dry run"}"
if actions.empty?
  puts "No deterministic repairs needed"
else
  actions.each { |action| puts action }
end
proposals.each { |proposal| puts proposal }
```

- [ ] **Step 5: Make executable and run tests**

Run:

```bash
chmod +x plugins/hippocampusmd/scripts/queue-reconcile-vault.sh
scripts/tests/test-queue-reconcile-vault.sh
scripts/tests/test-queue-status-vault.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add plugins/hippocampusmd/scripts/queue-reconcile-vault.sh plugins/hippocampusmd/scripts/lib/queue_hygiene.rb scripts/tests/test-queue-reconcile-vault.sh
git commit -m "feat: add deterministic queue reconciliation"
```

### Task 7: Detect and Refresh `ops/tasks.md` Drift (#51)

**Files:**
- Modify: `plugins/hippocampusmd/scripts/tasks-vault.sh`
- Modify: `scripts/tests/test-tasks-vault.sh`
- Modify: `plugins/hippocampusmd/scripts/lib/queue_hygiene.rb`
- Optionally Modify: `plugins/hippocampusmd/skills/hippocampusmd-tasks/SKILL.md`

- [ ] **Step 1: Add failing drift detection and refresh tests**

Extend `scripts/tests/test-tasks-vault.sh`:

```bash
drift_vault="$tmp_dir/drift-vault"
mkdir -p "$drift_vault/ops/queue"
cat > "$drift_vault/ops/tasks.md" <<'EOF'
# Task Stack

## Current
- [ ] Process queue batch alpha
- [ ] Preserve human priority

## Completed

## Discoveries
EOF
cat > "$drift_vault/ops/queue/queue.json" <<'EOF'
{"tasks":[
  {"id":"alpha","status":"done","batch":"alpha","file":"alpha.md"},
  {"id":"alpha-001","status":"completed","batch":"alpha","file":"alpha-001.md"},
  {"id":"beta-001","status":"pending","batch":"beta","target":"Beta Claim","current_phase":"reflect"}
]}
EOF
drift_output="$("$TASKS" "$drift_vault" --status)"
assert_contains "$drift_output" "Stale task stack entries:"
assert_contains "$drift_output" "Process queue batch alpha"
assert_contains "$drift_output" "Suggested queue task entries:"
assert_contains "$drift_output" "Continue queue task beta-001"

refresh_output="$("$TASKS" "$drift_vault" --refresh-queue)"
assert_contains "$refresh_output" "Removed stale generated task: Process queue batch alpha"
assert_contains "$refresh_output" "Added queue task: Continue queue task beta-001"
assert_contains "$(cat "$drift_vault/ops/tasks.md")" "Preserve human priority"
assert_contains "$(cat "$drift_vault/ops/tasks.md")" "Continue queue task beta-001"
assert_not_contains "$(cat "$drift_vault/ops/tasks.md")" "Process queue batch alpha"
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
scripts/tests/test-tasks-vault.sh
```

Expected: FAIL because `--refresh-queue` and drift sections do not exist.

- [ ] **Step 3: Add generated task convention**

Use stable generated task text so refresh can safely own only its own lines:

```text
Continue queue task TASK_ID
```

Only remove stale generated lines that match:

```ruby
\A(Process queue batch|Continue queue task)\s+
```

Do not remove arbitrary human tasks unless they match the generated convention and queue state proves they are stale.

- [ ] **Step 4: Implement `--refresh-queue`**

In `tasks-vault.sh` usage:

```ruby
warn "Usage: #{File.basename($PROGRAM_NAME)} [vault-path] --status|--discoveries|--add TEXT|--done N|--drop N|--reorder N POSITION|--refresh-queue [--limit N] [--format text|json]"
```

Parse:

```ruby
when "--refresh-queue"
  mode = :refresh_queue
```

Build suggested queue tasks:

```ruby
suggested = queue[:tasks]
  .select { |task| %w[pending blocked active].include?(task["status"]) }
  .map { |task| "Continue queue task #{task["id"]}" }
```

In refresh mode:

```ruby
generated_pattern = /\A(Process queue batch|Continue queue task)\s+/
removed = stack[:current].select { |item| queue[:archivable_batches].any? { |batch| item.include?(batch) } || item.match?(generated_pattern) && !suggested.include?(item) }
stack[:current] = stack[:current].reject { |item| removed.include?(item) }
added = suggested.reject { |item| stack[:current].include?(item) }
stack[:current].concat(added)
write_tasks(tasks_path, stack)
message = (removed.map { |item| "Removed stale generated task: #{item}" } + added.map { |item| "Added queue task: #{item}" }).join("\n")
```

In status output, print:

```ruby
unless queue[:archivable_batches].empty?
  stale = stack[:current].select { |item| queue[:archivable_batches].any? { |batch| item.include?(batch) } }
  puts "Stale task stack entries:"
  stale.each { |item| puts "  - #{item}" }
end
puts "Suggested queue task entries:"
suggested.first(limit).each { |item| puts "  - #{item}" }
```

- [ ] **Step 5: Run tests**

Run:

```bash
scripts/tests/test-tasks-vault.sh
scripts/tests/test-queue-status-vault.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add plugins/hippocampusmd/scripts/tasks-vault.sh plugins/hippocampusmd/scripts/lib/queue_hygiene.rb scripts/tests/test-tasks-vault.sh plugins/hippocampusmd/skills/hippocampusmd-tasks/SKILL.md
git commit -m "feat: refresh task stack from queue state"
```

### Task 8: Integrate Archive Batch Into Lifecycle Hygiene (#52)

**Files:**
- Modify: `plugins/hippocampusmd/scripts/archive-batch-vault.sh`
- Modify: `plugins/hippocampusmd/scripts/queue-reconcile-vault.sh`
- Modify: `plugins/hippocampusmd/scripts/lib/queue_hygiene.rb`
- Modify: `scripts/tests/test-archive-batch-vault.sh`
- Modify: `scripts/tests/test-queue-reconcile-vault.sh`
- Modify: `plugins/hippocampusmd/skills/hippocampusmd-archive-batch/SKILL.md`

- [ ] **Step 1: Add failing idempotent archive retry test**

Extend `scripts/tests/test-archive-batch-vault.sh` with a partial-interruption fixture:

```bash
partial_vault="$tmp_dir/partial"
mkdir -p "$partial_vault/ops/queue/archive/2026-05-03-theta"
cat > "$partial_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: theta
    type: extract
    status: done
    file: theta.md
    archive_folder: ops/queue/archive/2026-05-03-theta
  - id: theta-001
    type: claim
    status: completed
    batch: theta
    file: theta-001.md
    archive_folder: ops/queue/archive/2026-05-03-theta
EOF
cat > "$partial_vault/ops/queue/archive/2026-05-03-theta/theta.md" <<'EOF'
# Already moved theta
EOF
cat > "$partial_vault/ops/queue/theta-001.md" <<'EOF'
# Theta claim
EOF
partial_output="$("$ARCHIVE" "$partial_vault" --batch theta)"
assert_contains "$partial_output" "Already archived task file: ops/queue/archive/2026-05-03-theta/theta.md"
assert_contains "$partial_output" "Task files moved: 1"
assert_not_contains "$(cat "$partial_vault/ops/queue/queue.yaml")" "theta-001"
```

- [ ] **Step 2: Run archive test and verify failure**

Run:

```bash
scripts/tests/test-archive-batch-vault.sh
```

Expected: FAIL because current archive code treats destination collision as fatal even when it is an idempotent retry of an already moved source.

- [ ] **Step 3: Make archive retry idempotent**

Change move planning in `archive-batch-vault.sh`:

```ruby
if File.file?(source)
  if File.exist?(destination)
    warn "ERROR: Archive destination already exists: #{rel_path(destination, vault)}"
    exit 1
  end
  moves << [source, destination]
elsif File.file?(destination)
  already_archived << destination
else
  missing << [id_for(task), source, destination]
end
```

Fail on missing both source and destination:

```ruby
if missing.any?
  warn "ERROR: Task file missing from active queue and archive"
  missing.each { |id, source, destination| warn "- #{id}: #{rel_path(source, vault)} or #{rel_path(destination, vault)}" }
  exit 1
end
```

Print already-archived lines:

```ruby
already_archived.each { |path| puts "Already archived task file: #{rel_path(path, vault)}" }
```

- [ ] **Step 4: Teach reconcile to recommend archive command**

When `queue-reconcile-vault.sh` sees `archivable_batches`, print:

```text
Archive recommendation: hippocampusmd-archive-batch --batch alpha
```

Do not call archive automatically from reconcile unless a future issue adds explicit `--archive-completed`.

- [ ] **Step 5: Update archive skill docs**

Add:

```markdown
Archive is part of queue lifecycle hygiene. If a previous archive run was interrupted, rerun `archive-batch-vault.sh --batch ID`; already moved files are treated as idempotent progress, missing files are reported for repair, and pending work is never removed.
```

- [ ] **Step 6: Run focused tests**

Run:

```bash
scripts/tests/test-archive-batch-vault.sh
scripts/tests/test-queue-reconcile-vault.sh
scripts/tests/test-archive-batch-skill.sh
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add plugins/hippocampusmd/scripts/archive-batch-vault.sh plugins/hippocampusmd/scripts/queue-reconcile-vault.sh plugins/hippocampusmd/scripts/lib/queue_hygiene.rb plugins/hippocampusmd/skills/hippocampusmd-archive-batch/SKILL.md scripts/tests/test-archive-batch-vault.sh scripts/tests/test-queue-reconcile-vault.sh
git commit -m "feat: integrate archive batch with queue hygiene"
```

### Task 9: Plugin Version, Checks, Cache Refresh, and Issue Closure Prep

**Files:**
- Modify: `plugins/hippocampusmd/.codex-plugin/plugin.json`
- Maybe Modify: `scripts/check-codex-plugin.sh` only if it does not discover new helper scripts correctly

- [ ] **Step 1: Bump plugin version**

Change `plugins/hippocampusmd/.codex-plugin/plugin.json` from:

```json
"version": "1.0.0"
```

to:

```json
"version": "1.1.0"
```

Rationale: this is a backwards-compatible workflow addition with new helper CLIs, so use a minor version bump.

- [ ] **Step 2: Run all focused tests**

Run:

```bash
scripts/tests/test-queue-status-vault.sh
scripts/tests/test-queue-reconcile-vault.sh
scripts/tests/test-session-workflows.sh
scripts/tests/test-next-vault.sh
scripts/tests/test-ralph-vault.sh
scripts/tests/test-pipeline-vault.sh
scripts/tests/test-tasks-vault.sh
scripts/tests/test-archive-batch-vault.sh
scripts/tests/test-ralph-skill.sh
scripts/tests/test-pipeline-skill.sh
scripts/tests/test-archive-batch-skill.sh
```

Expected: all PASS.

- [ ] **Step 3: Run plugin check**

Run:

```bash
scripts/check-codex-plugin.sh
```

Expected: PASS.

- [ ] **Step 4: Refresh local plugin cache**

Run:

```bash
mkdir -p /Users/hlee/.codex/plugins/cache/hippocampusmd/hippocampusmd/1.1.0
/bin/cp -R plugins/hippocampusmd/. /Users/hlee/.codex/plugins/cache/hippocampusmd/hippocampusmd/1.1.0/
```

Expected: the local cache contains version `1.1.0` with the new helper scripts.

- [ ] **Step 5: Run final repository smoke checks**

Run:

```bash
scripts/check-codex-plugin.sh
scripts/tests/test-codex-smoke.sh
scripts/tests/test-codex-only-cleanup.sh
```

Expected: all PASS.

- [ ] **Step 6: Commit final integration**

```bash
git add plugins/hippocampusmd/.codex-plugin/plugin.json scripts/check-codex-plugin.sh
git commit -m "chore: bump hippocampusmd plugin for queue hygiene"
```

- [ ] **Step 7: Confirm acceptance criteria before closing #35**

Check:

```bash
gh issue view 35 --repo hojaeklee/hippocampusmd --json state,title,url
```

Close only after all acceptance criteria are satisfied and all implementation commits are present:

```bash
gh issue close 35 --repo hojaeklee/hippocampusmd --comment "Implemented queue lifecycle hygiene: read-only status, lifecycle surfacing, interruption recovery, deterministic reconciliation, task-stack refresh, archive integration, plugin checks, and local cache refresh."
```

## Acceptance Criteria Mapping

- Reference/methodology docs describe queue lifecycle hygiene at session start and persist/close.
  - Task 1.
- Helper behavior distinguishes read-only status, deterministic repair, and judgment-requiring proposals.
  - Tasks 2, 3, and 6.
- Completed batch archival can be surfaced by session orientation or next-action workflows.
  - Tasks 4 and 8.
- Stale `ops/tasks.md` state is detected or reconciled from queue/goals state.
  - Task 7.
- Auto-compaction/session restart recovery is covered by queue status/orientation behavior.
  - Tasks 3, 4, and 5.
- Ctrl+C/interrupted Ralph or pipeline runs leave recoverable state or are detectable by queue hygiene helpers.
  - Task 5.
- Stale active/claimed tasks, orphan queue files, and queue entries missing task files are detected.
  - Tasks 2 and 3.
- Existing plugin checks pass and the local plugin cache is refreshed after version bump.
  - Task 9.

## Self-Review Notes

- Scope is intentionally split by issue dependency: contract, read-only status, surfacing, interruption recovery, deterministic reconcile, task-stack refresh, archive integration.
- The plan uses `hippocampusmd` names for new files, CLIs, tests, and prose.
- The safety boundary is repeated in docs, helpers, tests, and task behavior: no pending work is dropped automatically.
- Existing helper behavior remains compatible: `--dry-run`, `--advance`, `--fail`, `--status`, `--ready-to-archive`, and archive commands keep their current entry points.
