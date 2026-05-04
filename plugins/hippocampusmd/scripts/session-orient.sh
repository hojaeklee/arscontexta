#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [vault-path] [--limit N] [--format text|json]\n' "$(basename "$0")" >&2
}

vault="."
limit="25"
format="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      limit="$2"
      shift 2
      ;;
    --format)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      format="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
    *)
      if [[ "$vault" == "." ]]; then
        vault="$1"
      else
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage
        exit 2
      fi
      shift
      ;;
  esac
done

case "$limit" in
  ''|*[!0-9]*)
    printf 'Limit must be a non-negative integer.\n' >&2
    exit 2
    ;;
esac

if [[ "$format" != "text" && "$format" != "json" ]]; then
  printf 'Unsupported format: %s\n' "$format" >&2
  exit 2
fi

if [[ ! -d "$vault" ]]; then
  printf 'Vault path is not a directory: %s\n' "$vault" >&2
  exit 2
fi

vault_abs="$(cd "$vault" && pwd -P)"

count_files() {
  local path="$1"
  local pattern="${2:-*}"
  if [[ -d "$path" ]]; then
    find "$path" -maxdepth 1 -type f -name "$pattern" | wc -l | tr -d ' '
  else
    printf '0'
  fi
}

json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

excerpt_file() {
  local rel="$1"
  local path="$vault_abs/$rel"
  if [[ -f "$path" ]]; then
    sed -n "1,${limit}p" "$path"
  fi
}

latest_file() {
  local dir="$1"
  local pattern="${2:-*}"
  if [[ -d "$vault_abs/$dir" ]]; then
    find "$vault_abs/$dir" -maxdepth 1 -type f -name "$pattern" -print | sort | tail -1
  fi
}

marker="absent"
[[ -f "$vault_abs/.hippocampusmd" ]] && marker="present"

md_count="$(find "$vault_abs" -name .git -prune -o -name node_modules -prune -o -type f -name '*.md' -print | wc -l | tr -d ' ')"
notes_count="$(count_files "$vault_abs/notes" '*.md')"
inbox_count="$(count_files "$vault_abs/inbox" '*.md')"
queue_count="$(count_files "$vault_abs/ops/queue" '*.md')"
observations_count="$(count_files "$vault_abs/ops/observations" '*.md')"
tensions_count="$(count_files "$vault_abs/ops/tensions" '*.md')"
session_count="$(count_files "$vault_abs/ops/sessions" '*.md')"
json_session_count="$(count_files "$vault_abs/ops/sessions" '*.json')"
health_count="$(count_files "$vault_abs/ops/health" '*.md')"

next_action="Run hippocampusmd-health to establish a current baseline."
if [[ "$marker" == "absent" ]]; then
  next_action="Run hippocampusmd-setup if this directory should become a HippocampusMD vault."
elif [[ "$inbox_count" -gt 0 ]]; then
  next_action="Review inbox pressure and decide whether to seed or process captured material."
elif [[ "$queue_count" -gt 0 ]]; then
  next_action="Review ops/queue and continue the next queued task."
elif [[ "$observations_count" -ge 10 || "$tensions_count" -ge 5 ]]; then
  next_action="Run a rethink pass on accumulated observations and tensions."
elif [[ "$health_count" -gt 0 ]]; then
  next_action="Review the latest health report and address its highest-severity finding."
fi

latest_health="$(latest_file "ops/health" "*.md")"
latest_session="$vault_abs/ops/sessions/current.md"
[[ -f "$latest_session" ]] || latest_session="$vault_abs/ops/sessions/current.json"

if [[ "$format" == "json" ]]; then
  printf '{\n'
  printf '  "vault": "%s",\n' "$(printf '%s' "$vault_abs" | json_escape)"
  printf '  "hippocampusmd_marker": "%s",\n' "$marker"
  printf '  "markdown_files": %s,\n' "$md_count"
  printf '  "notes": %s,\n' "$notes_count"
  printf '  "inbox": %s,\n' "$inbox_count"
  printf '  "queue": %s,\n' "$queue_count"
  printf '  "observations": %s,\n' "$observations_count"
  printf '  "tensions": %s,\n' "$tensions_count"
  printf '  "sessions": %s,\n' "$((session_count + json_session_count))"
  printf '  "health_reports": %s,\n' "$health_count"
  printf '  "next_action": "%s"\n' "$(printf '%s' "$next_action" | json_escape)"
  printf '}\n'
  exit 0
fi

printf 'HippocampusMD session orientation\n'
printf 'Vault: %s\n' "$vault_abs"
printf 'Marker: %s\n' "$marker"
printf '\n'
printf 'Inventory:\n'
printf '  Markdown files: %s\n' "$md_count"
printf '  notes/: %s\n' "$notes_count"
printf '  inbox/: %s\n' "$inbox_count"
printf '  ops/queue/: %s\n' "$queue_count"
printf '  ops/observations/: %s\n' "$observations_count"
printf '  ops/tensions/: %s\n' "$tensions_count"
printf '  ops/sessions/: %s\n' "$((session_count + json_session_count))"
printf '  ops/health/: %s\n' "$health_count"
printf '\n'

for rel in self/goals.md ops/goals.md; do
  if [[ -f "$vault_abs/$rel" ]]; then
    printf '%s excerpt:\n' "$rel"
    excerpt_file "$rel"
    printf '\n'
    break
  fi
done

if [[ -f "$latest_session" ]]; then
  printf 'Current session handoff:\n'
  sed -n "1,${limit}p" "$latest_session"
  printf '\n'
fi

if [[ -n "$latest_health" ]]; then
  printf 'Latest health report: %s\n' "${latest_health#"$vault_abs"/}"
fi

printf 'Recommended next action: %s\n' "$next_action"
