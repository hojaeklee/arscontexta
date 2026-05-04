#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [vault-path] [--mode quick] [--limit N] [--format text|json]\n' "$(basename "$0")" >&2
}

vault="."
mode="quick"
limit="25"
format="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      mode="$2"
      shift 2
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
      vault="$1"
      shift
      ;;
  esac
done

if [[ "$mode" != "quick" ]]; then
  printf 'Only --mode quick is supported.\n' >&2
  exit 2
fi

if [[ "$format" != "text" && "$format" != "json" ]]; then
  printf 'Unsupported format: %s\n' "$format" >&2
  exit 2
fi

case "$limit" in
  ''|*[!0-9]*)
    printf 'Limit must be a non-negative integer.\n' >&2
    exit 2
    ;;
esac

if [[ ! -d "$vault" ]]; then
  printf 'Vault path is not a directory: %s\n' "$vault" >&2
  exit 2
fi

vault_abs="$(cd "$vault" && pwd -P)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hippocampusmd-health.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

all_md="$tmp_dir/all-md.tsv"
targets="$tmp_dir/targets.txt"
links="$tmp_dir/links.tsv"
broken="$tmp_dir/broken.tsv"
skipped="$tmp_dir/skipped.tsv"

classify_path() {
  case "$1" in
    notes/*|self/*|manual/*|inbox/*|01_thinking/*|00_inbox/*|thinking/*|knowledge/*)
      printf 'primary'
      ;;
    ops/derivation.md|ops/derivation-manifest.md|ops/config.md)
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

json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

trim_target() {
  local value="$1"
  value="${value%%|*}"
  value="${value%%#*}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

find "$vault_abs" \
  -name .git -prune -o \
  -name node_modules -prune -o \
  -name .obsidian -prune -o \
  -type f -name '*.md' -print |
while IFS= read -r file; do
  rel="${file#"$vault_abs"/}"
  bucket="$(classify_path "$rel")"
  printf '%s\t%s\n' "$bucket" "$rel"
done | sort > "$all_md"

while IFS=$'\t' read -r _bucket rel; do
  no_ext="${rel%.md}"
  base="${no_ext##*/}"
  printf '%s\n' "$no_ext"
  printf '%s\n' "$base"
done < "$all_md" | sort -u > "$targets"

if command -v rg >/dev/null 2>&1; then
  raw_matches="$tmp_dir/raw-rg-matches.txt"
  rg --hidden -oN --no-heading --with-filename \
    -g '*.md' \
    -g '!.git/**' \
    -g '!node_modules/**' \
    -g '!.obsidian/**' \
    '\[\[[^\]]+\]\]' "$vault_abs" > "$raw_matches" 2>/dev/null || true

  awk -v root="$vault_abs/" -v links_file="$links" -v skipped_file="$skipped" '
    function classify(rel) {
      if (rel ~ /^(notes|self|manual|inbox|01_thinking|00_inbox|thinking|knowledge)\//) return "primary"
      if (rel ~ /^ops\/(derivation\.md|derivation-manifest\.md|config\.md)$/) return "primary"
      if (rel ~ /^ops\/(queue|health|sessions|observations|tensions|logs|archive)\//) return "operational"
      if (rel ~ /^ops\/session/) return "operational"
      if (rel ~ /^(AGENTS\.md|README\.md|SKILL\.md)$/) return "noise"
      if (rel ~ /^(templates|reference|platforms|generators|plugins|presets|agents)\//) return "noise"
      return "noise"
    }
    {
      split_at = index($0, ":[[")
      if (split_at == 0) next
      file = substr($0, 1, split_at - 1)
      wiki_match = substr($0, split_at + 1)
      rel = file
      if (index(file, root) == 1) rel = substr(file, length(root) + 1)
      bucket = classify(rel)
      raw = wiki_match
      sub(/^\[\[/, "", raw)
      sub(/\]\]$/, "", raw)
      target = raw
      sub(/\|.*/, "", target)
      sub(/#.*/, "", target)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", target)
      if (target == "") {
        print bucket "\t" rel "\t" raw >> skipped_file
      } else {
        print bucket "\t" rel "\t" target >> links_file
      }
    }
  ' "$raw_matches"
else
  while IFS=$'\t' read -r bucket rel; do
    file="$vault_abs/$rel"
    matches="$(grep -Eo '\[\[[^]]+\]\]' "$file" 2>/dev/null || true)"

    if [[ -z "$matches" ]]; then
      continue
    fi

    while IFS= read -r match; do
      raw="${match#\[\[}"
      raw="${raw%\]\]}"
      target="$(trim_target "$raw")"
      if [[ -z "$target" ]]; then
        printf '%s\t%s\t%s\n' "$bucket" "$rel" "$raw" >> "$skipped"
        continue
      fi
      printf '%s\t%s\t%s\n' "$bucket" "$rel" "$target" >> "$links"
    done <<< "$matches"
  done < "$all_md"
fi

touch "$links" "$skipped"

awk -F '\t' '
  FNR == NR {
    targets[$0] = 1
    next
  }
  $3 != "" && !($3 in targets) {
    print $0
  }
' "$targets" "$links" > "$broken"

md_count="$(wc -l < "$all_md" | tr -d ' ')"
link_count="$(wc -l < "$links" | tr -d ' ')"
skipped_count="$(wc -l < "$skipped" | tr -d ' ')"
primary_broken="$(awk -F '\t' '$1 == "primary" { count++ } END { print count + 0 }' "$broken")"
operational_broken="$(awk -F '\t' '$1 == "operational" { count++ } END { print count + 0 }' "$broken")"
noise_broken="$(awk -F '\t' '$1 == "noise" { count++ } END { print count + 0 }' "$broken")"
broken_total=$((primary_broken + operational_broken + noise_broken))

marker_status="absent"
if [[ -e "$vault_abs/.hippocampusmd" ]]; then
  marker_status="present"
fi

if [[ "$primary_broken" -gt 0 ]]; then
  overall="FAIL"
  link_status="FAIL"
elif [[ "$operational_broken" -gt 0 ]]; then
  overall="WARN"
  link_status="WARN"
else
  overall="PASS"
  link_status="PASS"
fi

print_text_examples() {
  local bucket="$1"
  local heading="$2"
  local count="$3"

  printf '%s (%s):\n' "$heading" "$count"
  if [[ "$count" -eq 0 ]]; then
    printf '  none\n'
    return
  fi

  awk -F '\t' -v bucket="$bucket" -v max="$limit" '
    $1 == bucket && shown < max {
      print "  - [[" $3 "]] in " $2
      shown++
    }
  ' "$broken"
  if [[ "$count" -gt "$limit" ]]; then
    printf '  ... %s more omitted by --limit %s\n' "$((count - limit))" "$limit"
  fi
}

if [[ "$format" == "json" ]]; then
  printf '{\n'
  printf '  "overall": "%s",\n' "$overall"
  printf '  "mode": "%s",\n' "$mode"
  printf '  "vault": "%s",\n' "$(printf '%s' "$vault_abs" | json_escape)"
  printf '  "hippocampusmd_marker": "%s",\n' "$marker_status"
  printf '  "markdown_files": %s,\n' "$md_count"
  printf '  "wiki_links": %s,\n' "$link_count"
  printf '  "skipped_links": %s,\n' "$skipped_count"
  printf '  "link_health": {\n'
  printf '    "status": "%s",\n' "$link_status"
  printf '    "broken_total": %s,\n' "$broken_total"
  printf '    "primary": %s,\n' "$primary_broken"
  printf '    "operational": %s,\n' "$operational_broken"
  printf '    "noise": %s\n' "$noise_broken"
  printf '  },\n'
  printf '  "examples_limit": %s\n' "$limit"
  printf '}\n'
  exit 0
fi

printf 'HippocampusMD Quick Health\n'
printf 'Overall: %s\n' "$overall"
printf 'Vault: %s\n' "$vault_abs"
printf 'HippocampusMD marker: %s\n' "$marker_status"
if [[ "$marker_status" == "absent" ]]; then
  printf 'Note: .hippocampusmd was not detected; treating this as a generic markdown vault.\n'
fi
printf '\n'
printf 'Inventory:\n'
printf '  Markdown files: %s\n' "$md_count"
printf '  Wiki links checked: %s\n' "$link_count"
printf '  Skipped malformed/empty links: %s\n' "$skipped_count"
printf '\n'
printf 'Link health: %s\n' "$link_status"
printf '  Broken links total: %s\n' "$broken_total"
printf '  Primary: %s\n' "$primary_broken"
printf '  Operational: %s\n' "$operational_broken"
printf '  Noise/docs/templates: %s\n' "$noise_broken"
printf '\n'
print_text_examples "primary" "Primary broken links" "$primary_broken"
printf '\n'
print_text_examples "operational" "Operational broken links" "$operational_broken"
printf '\n'
print_text_examples "noise" "Noise/docs/template broken links" "$noise_broken"
printf '\n'
printf 'Recommended next action: '
if [[ "$primary_broken" -gt 0 ]]; then
  printf 'fix primary broken links first by creating target notes or removing stale links.\n'
elif [[ "$operational_broken" -gt 0 ]]; then
  printf 'review operational broken links when maintaining queues, sessions, or health history.\n'
elif [[ "$noise_broken" -gt 0 ]]; then
  printf 'primary link health is clean; review noisy docs/templates only if they affect user-facing guidance.\n'
else
  printf 'no broken wiki links found in scanned markdown.\n'
fi
