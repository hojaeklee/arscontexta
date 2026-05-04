#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [vault-path] [--file PATH|--changed] [--limit N] [--format text|json]\n' "$(basename "$0")" >&2
}

vault="."
target_file=""
changed=false
limit="25"
format="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      target_file="$2"
      shift 2
      ;;
    --changed)
      changed=true
      shift
      ;;
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

if [[ -n "$target_file" && "$changed" == true ]]; then
  printf 'Use only one of --file or --changed.\n' >&2
  exit 2
fi

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
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hippocampusmd-session-validate.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

targets_file="$tmp_dir/targets.txt"
notes_index="$tmp_dir/note-targets.txt"
findings_file="$tmp_dir/findings.tsv"
touch "$targets_file" "$findings_file"

json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

relpath() {
  local path="$1"
  case "$path" in
    "$vault_abs"/*) printf '%s' "${path#"$vault_abs"/}" ;;
    *) printf '%s' "$path" ;;
  esac
}

if [[ -n "$target_file" ]]; then
  case "$target_file" in
    /*) abs="$target_file" ;;
    *) abs="$vault_abs/$target_file" ;;
  esac
  if [[ ! -f "$abs" ]]; then
    printf 'Target file does not exist: %s\n' "$target_file" >&2
    exit 2
  fi
  printf '%s\n' "$(relpath "$abs")" > "$targets_file"
elif [[ "$changed" == true ]]; then
  if git -C "$vault_abs" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    {
      git -C "$vault_abs" diff --name-only --diff-filter=ACMRT HEAD -- '*.md' 2>/dev/null || true
      git -C "$vault_abs" diff --cached --name-only --diff-filter=ACMRT -- '*.md' 2>/dev/null || true
      git -C "$vault_abs" ls-files --others --exclude-standard -- '*.md' 2>/dev/null || true
    } | sort -u > "$targets_file"
  else
    printf 'Cannot use --changed outside a git worktree.\n' >&2
    exit 2
  fi
else
  if [[ -d "$vault_abs/notes" ]]; then
    find "$vault_abs/notes" -type f -name '*.md' -print | sort | while IFS= read -r file; do
      relpath "$file"
      printf '\n'
    done > "$targets_file"
  fi
fi

find "$vault_abs" \
  -name .git -prune -o \
  -name node_modules -prune -o \
  -type f -name '*.md' -print |
while IFS= read -r file; do
  rel="${file#"$vault_abs"/}"
  no_ext="${rel%.md}"
  base="${no_ext##*/}"
  printf '%s\n%s\n' "$no_ext" "$base"
done | sort -u > "$notes_index"

add_finding() {
  local rel="$1"
  local level="$2"
  local message="$3"
  printf '%s\t%s\t%s\n' "$level" "$rel" "$message" >> "$findings_file"
}

trim_target() {
  local value="$1"
  value="${value%%|*}"
  value="${value%%#*}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

validate_file() {
  local rel="$1"
  local path="$vault_abs/$rel"
  [[ -f "$path" ]] || return
  [[ "$rel" == *.md ]] || return

  if ! head -1 "$path" | grep -qx -- '---'; then
    add_finding "$rel" "WARN" "Missing YAML frontmatter opening delimiter."
  fi
  if ! sed -n '1,40p' "$path" | grep -Eq '^description:[[:space:]]*[^[:space:]]'; then
    add_finding "$rel" "WARN" "Missing non-empty description field near the top of the file."
  fi
  if ! sed -n '1,40p' "$path" | grep -Eq '^topics:'; then
    add_finding "$rel" "WARN" "Missing topics field near the top of the file."
  fi

  if command -v rg >/dev/null 2>&1; then
    rg -oN '\[\[[^\]]+\]\]' "$path" 2>/dev/null || true
  else
    grep -Eo '\[\[[^]]+\]\]' "$path" 2>/dev/null || true
  fi | while IFS= read -r match; do
    raw="${match#\[\[}"
    raw="${raw%\]\]}"
    target="$(trim_target "$raw")"
    if [[ -n "$target" ]] && ! grep -Fxq "$target" "$notes_index"; then
      add_finding "$rel" "WARN" "Possible unresolved wiki link: [[$target]]."
    fi
  done
}

while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  validate_file "$rel"
done < "$targets_file"

target_count="$(awk 'NF { count++ } END { print count + 0 }' "$targets_file")"
warn_count="$(awk -F '\t' '$1 == "WARN" { count++ } END { print count + 0 }' "$findings_file")"
overall="PASS"
[[ "$warn_count" -gt 0 ]] && overall="WARN"

if [[ "$format" == "json" ]]; then
  printf '{\n'
  printf '  "overall": "%s",\n' "$overall"
  printf '  "vault": "%s",\n' "$(printf '%s' "$vault_abs" | json_escape)"
  printf '  "files_checked": %s,\n' "$target_count"
  printf '  "warnings": %s\n' "$warn_count"
  printf '}\n'
  exit 0
fi

printf 'HippocampusMD session validation\n'
printf 'Vault: %s\n' "$vault_abs"
printf 'Files checked: %s\n' "$target_count"
printf 'Overall: %s\n' "$overall"
printf '\n'

if [[ "$warn_count" -eq 0 ]]; then
  printf 'Findings: none\n'
else
  printf 'Findings (%s):\n' "$warn_count"
  awk -F '\t' -v max="$limit" '
    shown < max {
      print "  - " $1 ": " $2 ": " $3
      shown++
    }
  ' "$findings_file"
  if [[ "$warn_count" -gt "$limit" ]]; then
    printf '  ... %s more omitted by --limit %s\n' "$((warn_count - limit))" "$limit"
  fi
fi
