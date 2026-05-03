#!/usr/bin/env bash
set -euo pipefail

trap 'status=$?; if [[ "$status" -ne 0 && "$status" -ne 2 ]]; then exit 3; fi' EXIT

usage() {
  cat >&2 <<'EOF'
Usage:
  mcp-vault-tools.sh links.check <vault-path> [--limit N]
  mcp-vault-tools.sh frontmatter.validate <vault-path> [--file PATH|--changed|--all] [--limit N]
EOF
}

die_usage() {
  printf '%s\n' "$1" >&2
  usage
  exit 2
}

json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

require_limit() {
  case "$1" in
    ''|*[!0-9]*)
      die_usage "Limit must be a non-negative integer."
      ;;
  esac
}

resolve_vault() {
  local vault="$1"
  [[ -d "$vault" ]] || die_usage "Vault path is not a directory: $vault"
  cd "$vault" && pwd -P
}

classify_path() {
  case "$1" in
    notes/*|self/*|manual/*|inbox/*|01_thinking/*|00_inbox/*|thinking/*|knowledge/*)
      printf 'primary'
      ;;
    ops/derivation.md|ops/derivation-manifest.md|ops/config.md|ops/config.yaml)
      printf 'primary'
      ;;
    ops/queue/*|ops/health/*|ops/sessions/*|ops/session*|ops/observations/*|ops/tensions/*|ops/logs/*|ops/archive/*)
      printf 'operational'
      ;;
    AGENTS.md|README.md|SKILL.md|templates/*|reference/*|platforms/*|generators/*|plugins/*|presets/*|agents/*)
      printf 'noise'
      ;;
    *)
      printf 'noise'
      ;;
  esac
}

trim_target() {
  local value="$1"
  value="${value%%|*}"
  value="${value%%#*}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

build_target_index() {
  local vault_abs="$1"
  local out="$2"

  find "$vault_abs" \
    -name .git -prune -o \
    -name node_modules -prune -o \
    -name .obsidian -prune -o \
    -type f -name '*.md' -print |
  while IFS= read -r file; do
    rel="${file#"$vault_abs"/}"
    no_ext="${rel%.md}"
    base="${no_ext##*/}"
    printf '%s\n%s\n' "$no_ext" "$base"
  done | sort -u > "$out"
}

print_examples_json() {
  local file="$1"
  local limit="$2"
  awk -F '\t' -v max="$limit" '
    BEGIN { shown = 0 }
    shown < max {
      if (shown > 0) printf ",\n"
      gsub(/\\/,"\\\\",$2); gsub(/"/,"\\\"",$2)
      gsub(/\\/,"\\\\",$3); gsub(/"/,"\\\"",$3)
      gsub(/\\/,"\\\\",$4); gsub(/"/,"\\\"",$4)
      printf "    {\"level\":\"%s\",\"file\":\"%s\",\"target\":\"%s\",\"message\":\"%s\"}", $1, $2, $3, $4
      shown++
    }
    END {
      if (shown > 0) printf "\n"
    }
  ' "$file"
}

links_check() {
  local vault="${1:-}"
  [[ -n "$vault" ]] || die_usage "Missing vault path."
  shift || true

  local limit="25"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit)
        [[ $# -ge 2 ]] || die_usage "Missing value for --limit."
        limit="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die_usage "Unexpected argument: $1"
        ;;
    esac
  done
  require_limit "$limit"

  local vault_abs
  vault_abs="$(resolve_vault "$vault")"
  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/arscontexta-mcp-links.XXXXXX")"

  local targets="$tmp_dir/targets.txt"
  local links="$tmp_dir/links.tsv"
  local broken="$tmp_dir/broken.tsv"
  local examples="$tmp_dir/examples.tsv"
  touch "$links" "$broken" "$examples"
  build_target_index "$vault_abs" "$targets"

  find "$vault_abs" \
    -name .git -prune -o \
    -name node_modules -prune -o \
    -name .obsidian -prune -o \
    -type f -name '*.md' -print |
  while IFS= read -r file; do
    rel="${file#"$vault_abs"/}"
    bucket="$(classify_path "$rel")"
    if command -v rg >/dev/null 2>&1; then
      matches="$(rg -oN '\[\[[^\]]+\]\]' "$file" 2>/dev/null || true)"
    else
      matches="$(grep -Eo '\[\[[^]]+\]\]' "$file" 2>/dev/null || true)"
    fi
    [[ -n "$matches" ]] || continue
    while IFS= read -r match; do
      raw="${match#\[\[}"
      raw="${raw%\]\]}"
      target="$(trim_target "$raw")"
      [[ -n "$target" ]] || continue
      printf '%s\t%s\t%s\n' "$bucket" "$rel" "$target" >> "$links"
    done <<< "$matches"
  done

  awk -F '\t' '
    FNR == NR { targets[$0] = 1; next }
    $3 != "" && !($3 in targets) { print $0 }
  ' "$targets" "$links" > "$broken"

  awk -F '\t' '{ print "WARN\t" $2 "\t" $3 "\tDangling wiki link." }' "$broken" > "$examples"

  local md_count link_count primary operational noise broken_total overall
  md_count="$(find "$vault_abs" -name .git -prune -o -name node_modules -prune -o -name .obsidian -prune -o -type f -name '*.md' -print | wc -l | tr -d ' ')"
  link_count="$(wc -l < "$links" | tr -d ' ')"
  primary="$(awk -F '\t' '$1 == "primary" { count++ } END { print count + 0 }' "$broken")"
  operational="$(awk -F '\t' '$1 == "operational" { count++ } END { print count + 0 }' "$broken")"
  noise="$(awk -F '\t' '$1 == "noise" { count++ } END { print count + 0 }' "$broken")"
  broken_total=$((primary + operational + noise))
  overall="PASS"
  [[ "$operational" -gt 0 ]] && overall="WARN"
  [[ "$primary" -gt 0 ]] && overall="FAIL"

  printf '{\n'
  printf '  "tool": "arscontexta.links.check",\n'
  printf '  "vault": "%s",\n' "$(printf '%s' "$vault_abs" | json_escape)"
  printf '  "overall": "%s",\n' "$overall"
  printf '  "markdown_files": %s,\n' "$md_count"
  printf '  "wiki_links": %s,\n' "$link_count"
  printf '  "broken_total": %s,\n' "$broken_total"
  printf '  "primary_broken": %s,\n' "$primary"
  printf '  "operational_broken": %s,\n' "$operational"
  printf '  "noise_broken": %s,\n' "$noise"
  printf '  "examples": [\n'
  print_examples_json "$examples" "$limit"
  printf '  ]\n'
  printf '}\n'
  rm -rf "$tmp_dir"
}

frontmatter_validate() {
  local vault="${1:-}"
  [[ -n "$vault" ]] || die_usage "Missing vault path."
  shift || true

  local limit="25"
  local target_file=""
  local changed=false
  local all=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)
        [[ $# -ge 2 ]] || die_usage "Missing value for --file."
        target_file="$2"
        shift 2
        ;;
      --changed)
        changed=true
        shift
        ;;
      --all)
        all=true
        shift
        ;;
      --limit)
        [[ $# -ge 2 ]] || die_usage "Missing value for --limit."
        limit="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die_usage "Unexpected argument: $1"
        ;;
    esac
  done
  require_limit "$limit"

  local selected=0
  [[ -n "$target_file" ]] && selected=$((selected + 1))
  [[ "$changed" == true ]] && selected=$((selected + 1))
  [[ "$all" == true ]] && selected=$((selected + 1))
  [[ "$selected" -le 1 ]] || die_usage "Use only one of --file, --changed, or --all."

  local vault_abs
  vault_abs="$(resolve_vault "$vault")"
  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/arscontexta-mcp-frontmatter.XXXXXX")"

  local targets_file="$tmp_dir/targets.txt"
  local notes_index="$tmp_dir/note-targets.txt"
  local findings="$tmp_dir/findings.tsv"
  touch "$targets_file" "$findings"
  build_target_index "$vault_abs" "$notes_index"

  if [[ -n "$target_file" ]]; then
    case "$target_file" in
      /*) abs="$target_file" ;;
      *) abs="$vault_abs/$target_file" ;;
    esac
    [[ -f "$abs" ]] || die_usage "Target file does not exist: $target_file"
    printf '%s\n' "${abs#"$vault_abs"/}" > "$targets_file"
  elif [[ "$changed" == true ]]; then
    git -C "$vault_abs" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die_usage "Cannot use --changed outside a git worktree."
    {
      git -C "$vault_abs" diff --name-only --diff-filter=ACMRT HEAD -- '*.md' 2>/dev/null || true
      git -C "$vault_abs" diff --cached --name-only --diff-filter=ACMRT -- '*.md' 2>/dev/null || true
      git -C "$vault_abs" ls-files --others --exclude-standard -- '*.md' 2>/dev/null || true
    } | sort -u > "$targets_file"
  else
    find "$vault_abs/notes" -type f -name '*.md' -print 2>/dev/null | sort | while IFS= read -r file; do
      printf '%s\n' "${file#"$vault_abs"/}"
    done > "$targets_file"
  fi

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    path="$vault_abs/$rel"
    [[ -f "$path" && "$rel" == *.md ]] || continue
    if ! head -1 "$path" | grep -qx -- '---'; then
      printf 'WARN\t%s\t\tMissing YAML frontmatter opening delimiter.\n' "$rel" >> "$findings"
    fi
    if ! sed -n '1,40p' "$path" | grep -Eq '^description:[[:space:]]*[^[:space:]]'; then
      printf 'WARN\t%s\t\tMissing non-empty description field near the top of the file.\n' "$rel" >> "$findings"
    fi
    if ! sed -n '1,40p' "$path" | grep -Eq '^topics:'; then
      printf 'WARN\t%s\t\tMissing topics field near the top of the file.\n' "$rel" >> "$findings"
    fi
    if command -v rg >/dev/null 2>&1; then
      matches="$(rg -oN '\[\[[^\]]+\]\]' "$path" 2>/dev/null || true)"
    else
      matches="$(grep -Eo '\[\[[^]]+\]\]' "$path" 2>/dev/null || true)"
    fi
    [[ -n "$matches" ]] || continue
    while IFS= read -r match; do
      raw="${match#\[\[}"
      raw="${raw%\]\]}"
      target="$(trim_target "$raw")"
      if [[ -n "$target" ]] && ! grep -Fxq "$target" "$notes_index"; then
        printf 'WARN\t%s\t%s\tPossible unresolved wiki link.\n' "$rel" "$target" >> "$findings"
      fi
    done <<< "$matches"
  done < "$targets_file"

  local files_checked warnings overall
  files_checked="$(awk 'NF { count++ } END { print count + 0 }' "$targets_file")"
  warnings="$(wc -l < "$findings" | tr -d ' ')"
  overall="PASS"
  [[ "$warnings" -gt 0 ]] && overall="WARN"

  printf '{\n'
  printf '  "tool": "arscontexta.frontmatter.validate",\n'
  printf '  "vault": "%s",\n' "$(printf '%s' "$vault_abs" | json_escape)"
  printf '  "overall": "%s",\n' "$overall"
  printf '  "files_checked": %s,\n' "$files_checked"
  printf '  "warnings": %s,\n' "$warnings"
  printf '  "examples": [\n'
  print_examples_json "$findings" "$limit"
  printf '  ]\n'
  printf '}\n'
  rm -rf "$tmp_dir"
}

main() {
  local command="${1:-}"
  [[ -n "$command" ]] || die_usage "Missing command."
  shift || true

  case "$command" in
    links.check)
      links_check "$@"
      ;;
    frontmatter.validate)
      frontmatter_validate "$@"
      ;;
    -h|--help)
      usage
      ;;
    *)
      die_usage "Unknown command: $command"
      ;;
  esac
}

main "$@"
