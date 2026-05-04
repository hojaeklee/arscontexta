#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [vault-path] --summary-file PATH [--next-file PATH] [--dry-run]\n' "$(basename "$0")" >&2
}

vault="."
summary_file=""
next_file=""
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary-file)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      summary_file="$2"
      shift 2
      ;;
    --next-file)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      next_file="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
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

if [[ -z "$summary_file" ]]; then
  usage
  exit 2
fi

if [[ ! -d "$vault" ]]; then
  printf 'Vault path is not a directory: %s\n' "$vault" >&2
  exit 2
fi

if [[ ! -f "$summary_file" ]]; then
  printf 'Summary file does not exist: %s\n' "$summary_file" >&2
  exit 2
fi

if [[ -n "$next_file" && ! -f "$next_file" ]]; then
  printf 'Next-action file does not exist: %s\n' "$next_file" >&2
  exit 2
fi

vault_abs="$(cd "$vault" && pwd -P)"
summary_abs="$(cd "$(dirname "$summary_file")" && pwd -P)/$(basename "$summary_file")"
timestamp="$(date -u +"%Y%m%d-%H%M%S")"
today="$(date -u +"%Y-%m-%d")"
session_dir="$vault_abs/ops/sessions"
session_file="$session_dir/${timestamp}.md"
current_file="$session_dir/current.md"

printf 'HippocampusMD session capture\n'
printf 'Vault: %s\n' "$vault_abs"
printf 'Session file: %s\n' "${session_file#"$vault_abs"/}"
if [[ "$dry_run" == true ]]; then
  printf 'Mode: dry run\n'
  exit 0
fi

mkdir -p "$session_dir"

{
  printf '%s\n' '---'
  printf 'description: Session handoff captured for Codex continuity\n'
  printf 'type: session-handoff\n'
  printf 'created: %s\n' "$today"
  printf 'timestamp: %s\n' "$timestamp"
  printf 'platform: codex\n'
  printf '%s\n' '---'
  printf '\n'
  printf '# Session handoff %s\n' "$timestamp"
  printf '\n'
  printf 'Codex cannot automatically save a full transcript without a stable session hook or transcript API. This handoff records the summary provided for capture.\n'
  printf '\n'
  printf '## Summary\n'
  printf '\n'
  cat "$summary_abs"
  printf '\n'
  if [[ -n "$next_file" ]]; then
    next_abs="$(cd "$(dirname "$next_file")" && pwd -P)/$(basename "$next_file")"
    printf '\n'
    printf '## Next\n'
    printf '\n'
    cat "$next_abs"
    printf '\n'
  fi
} > "$session_file"

cp "$session_file" "$current_file"

printf 'Wrote: %s\n' "${session_file#"$vault_abs"/}"
printf 'Updated: %s\n' "${current_file#"$vault_abs"/}"
