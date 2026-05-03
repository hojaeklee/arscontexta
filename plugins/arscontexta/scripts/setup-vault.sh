#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s <vault-path> --preset research|personal|experimental --domain <name> [--dry-run]\n' "$(basename "$0")" >&2
}

vault=""
preset=""
domain=""
dry_run=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PRESETS_DIR="$PLUGIN_ROOT/presets"
GENERATORS_DIR="$PLUGIN_ROOT/generators"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preset)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      preset="$2"
      shift 2
      ;;
    --domain)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      domain="$2"
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
      if [[ -z "$vault" ]]; then
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

if [[ -z "$vault" || -z "$preset" || -z "$domain" ]]; then
  usage
  exit 2
fi

preset_dir="$PRESETS_DIR/$preset"
preset_file="$preset_dir/preset.yaml"
vocabulary_file="$preset_dir/vocabulary.yaml"
categories_file="$preset_dir/categories.yaml"
agents_template="$GENERATORS_DIR/agents-md.md"

if [[ ! -d "$preset_dir" ]]; then
  printf 'Unsupported preset: %s\n' "$preset" >&2
  exit 2
fi

for required_file in "$preset_file" "$vocabulary_file" "$categories_file" "$agents_template"; do
  if [[ ! -f "$required_file" ]]; then
    printf 'Missing setup source: %s\n' "$required_file" >&2
    exit 2
  fi
done

if [[ "$vault" == "." ]]; then
  vault_abs="$(pwd -P)"
else
  mkdir_parent="$(dirname "$vault")"
  if [[ ! -d "$mkdir_parent" ]]; then
    printf 'Parent directory does not exist: %s\n' "$mkdir_parent" >&2
    exit 2
  fi
  if [[ -d "$vault" ]]; then
    vault_abs="$(cd "$vault" && pwd -P)"
  elif [[ "$dry_run" == true ]]; then
    parent_abs="$(cd "$mkdir_parent" && pwd -P)"
    vault_abs="$parent_abs/$(basename "$vault")"
  else
    mkdir -p "$vault"
    vault_abs="$(cd "$vault" && pwd -P)"
  fi
fi

today="$(date +%Y-%m-%d)"

yaml_scalar() {
  local file="$1"
  local key="$2"
  local default="${3:-}"
  local value

  value="$(awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
      line = $0
      sub(/^[^:]+:[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*/, "", line)
      gsub(/^"|"$/, "", line)
      if (line != "" && line != "null") {
        print line
        exit
      }
    }
  ' "$file")"

  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default"
  fi
}

yaml_list_values() {
  local file="$1"
  local key="$2"

  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key ":[[:space:]]*\\[\\][[:space:]]*($|#)" { exit }
    $0 ~ "^[[:space:]]*" key ":[[:space:]]*$" { in_list = 1; next }
    in_list && /^[[:space:]]*-/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*/, "", line)
      gsub(/^"|"$/, "", line)
      if (line != "" && line != "null") print line
      next
    }
    in_list && $0 !~ /^[[:space:]]*$/ { exit }
  ' "$file"
}

render_template_file() {
  local source="$1"
  local path="$2"
  local content

  content="$(<"$source")"
  content="${content//\{\{DOMAIN\}\}/$domain}"
  content="${content//\{\{PRESET\}\}/$preset}"
  content="${content//\{\{NOTE_TYPE\}\}/$note_type}"
  content="${content//\{\{TOPIC_MAP\}\}/$topic_map}"
  content="${content//\{\{FOCUS_TERM\}\}/$focus_term}"
  printf '%s\n' "$content" > "$path"
}

note_type="$(yaml_scalar "$preset_file" "note_type" "note")"
topic_map="$(yaml_scalar "$preset_file" "topic_map" "topic map")"
focus_term="$(yaml_scalar "$preset_file" "focus_term" "knowledge")"
starter_files="$(yaml_list_values "$preset_file" "starter_notes" | tr '\n' ' ')"
if [[ -z "${starter_files// }" ]]; then
  starter_files="index"
fi

category_items="$(yaml_list_values "$categories_file" "extraction_categories" | sed 's/^/  - /')"
vocabulary_note="$(yaml_scalar "$vocabulary_file" "note" "$note_type")"
vocabulary_moc="$(yaml_scalar "$vocabulary_file" "moc" "$topic_map")"
vocabulary_reduce="$(yaml_scalar "$vocabulary_file" "reduce" "reduce")"
vocabulary_reflect="$(yaml_scalar "$vocabulary_file" "reflect" "reflect")"
vocabulary_verify="$(yaml_scalar "$vocabulary_file" "verify" "verify")"
vocabulary_reweave="$(yaml_scalar "$vocabulary_file" "reweave" "reweave")"

announce() {
  printf '%s %s\n' "$1" "$2"
}

ensure_dir() {
  local path="$1"
  if [[ -d "$path" ]]; then
    announce "EXISTS" "${path#"$vault_abs"/}/"
  elif [[ "$dry_run" == true ]]; then
    announce "CREATE" "${path#"$vault_abs"/}/"
  else
    mkdir -p "$path"
    announce "CREATE" "${path#"$vault_abs"/}/"
  fi
}

write_starter_note() {
  local name="$1"
  local path="$vault_abs/notes/$name.md"
  local rel="${path#"$vault_abs"/}"
  local source="$preset_dir/starter/$name.md"

  if [[ -e "$path" ]]; then
    announce "EXISTS" "$rel"
    return
  fi

  if [[ "$dry_run" == true ]]; then
    announce "CREATE" "$rel"
    return
  fi

  mkdir -p "$(dirname "$path")"
  if [[ -f "$source" ]]; then
    render_template_file "$source" "$path"
    announce "CREATE" "$rel"
  else
    write_file "$path"
  fi
}

write_file() {
  local path="$1"
  local rel="${path#"$vault_abs"/}"
  if [[ -e "$path" ]]; then
    announce "EXISTS" "$rel"
    return
  fi

  if [[ "$dry_run" == true ]]; then
    announce "CREATE" "$rel"
    return
  fi

  mkdir -p "$(dirname "$path")"
  case "$rel" in
    .arscontexta)
      printf '%s\n' \
        '# Ars Contexta vault marker' \
        '# Generated by Codex setup.' \
        '# Do not delete unless this directory should stop being treated as an Ars Contexta vault.' \
        "created: $today" \
        'platform: codex' \
        > "$path"
      ;;
    AGENTS.md)
      render_template_file "$agents_template" "$path"
      ;;
    ops/derivation.md)
      printf '%s\n' \
        "---" \
        "description: How this Codex vault was initialized" \
        "created: $today" \
        "engine_version: codex-minimal-setup-0.1" \
        "---" \
        "" \
        "# System Derivation" \
        "" \
        "## Summary" \
        "" \
        "This vault was initialized by the minimal Codex setup flow from bundled plugin preset and generator assets." \
        "" \
        "- Domain: $domain" \
        "- Preset: $preset" \
        "- Platform: Codex" \
        "- Context file: AGENTS.md" \
        "- Session workflow: arscontexta-session" \
        "" \
        "## Migration Notes" \
        "" \
        "Existing markdown files, if any, were left in place. This setup adds Ars Contexta scaffolding around the workspace without moving user content." \
        "" \
        "## Operating Model" \
        "" \
        "Codex works through explicit user intent, local file reads, and approved writes. Background automation is not required. The plugin-side generators and presets remain bundled source assets; this vault receives only their derived outputs." \
        > "$path"
      ;;
    ops/derivation-manifest.md)
      printf '%s\n' \
        "# ops/derivation-manifest.md -- Runtime configuration for Ars Contexta skills" \
        "# Generated by Codex minimal setup." \
        "---" \
        "domain:" \
        "  name: \"$domain\"" \
        "  preset: \"$preset\"" \
        "platform:" \
        "  primary: codex" \
        "  context_file: AGENTS.md" \
        "vocabulary:" \
        "  notes: notes" \
        "  inbox: inbox" \
        "  archive: archive" \
        "  note: $vocabulary_note" \
        "  topic_map: $vocabulary_moc" \
        "  reduce: $vocabulary_reduce" \
        "  reflect: $vocabulary_reflect" \
        "  reweave: $vocabulary_reweave" \
        "  verify: $vocabulary_verify" \
        "---" \
        > "$path"
      ;;
    ops/config.yaml)
      {
        printf '%s\n' \
          "# ops/config.yaml -- Minimal Codex setup configuration" \
          "domain: \"$domain\"" \
          "preset: \"$preset\"" \
          "platform: codex" \
          "context_file: AGENTS.md" \
          "notes_dir: notes" \
          "inbox_dir: inbox" \
          "archive_dir: archive" \
          "vocabulary:" \
          "  note: $vocabulary_note" \
          "  topic_map: $vocabulary_moc" \
          "  reduce: $vocabulary_reduce" \
          "  reflect: $vocabulary_reflect" \
          "  reweave: $vocabulary_reweave" \
          "  verify: $vocabulary_verify"
        if [[ -n "$category_items" ]]; then
          printf 'extraction_categories:\n%s\n' "$category_items"
        else
          printf 'extraction_categories: []\n'
        fi
        printf '%s\n' \
          "scan:" \
          "  include:" \
          "    - notes/**" \
          "    - self/**" \
          "    - manual/**" \
          "    - inbox/**" \
          "    - ops/derivation.md" \
          "    - ops/derivation-manifest.md" \
          "  exclude:" \
          "    - archive/**" \
          "    - imported/**" \
          "    - attachments/**" \
          "    - ops/cache/**" \
          "    - ops/health/**" \
          "    - ops/sessions/**" \
          "    - ops/queue/archive/**" \
          "automation:" \
          "  session_workflow: arscontexta-session" \
          "  explicit_user_confirmation: true" \
          "processing:" \
          "  mode: explicit" \
          "  pipeline_skill: arscontexta-pipeline" \
          "maintenance:" \
          "  health_skill: arscontexta-health"
      } > "$path"
      ;;
    templates/base-note.md)
      printf '%s\n' \
        "---" \
        "description: One sentence adding context beyond the title" \
        "type: insight" \
        "created: YYYY-MM-DD" \
        "---" \
        "" \
        "# prose-as-title expressing one $focus_term insight" \
        "" \
        "Develop the idea in plain language. Use wiki links where they clarify relationships." \
        "" \
        "---" \
        "" \
        "Topics:" \
        "- [[index]]" \
        > "$path"
      ;;
    templates/moc.md)
      printf '%s\n' \
        "---" \
        "description: Brief description of what this $topic_map covers and why it matters" \
        "type: moc" \
        "created: YYYY-MM-DD" \
        "---" \
        "" \
        "# topic-name" \
        "" \
        "Brief orientation for this topic." \
        "" \
        "## Core Ideas" \
        "" \
        "- [[related note]] -- why it belongs here" \
        "" \
        "---" \
        "" \
        "Topics:" \
        "- [[index]]" \
        > "$path"
      ;;
    self/identity.md)
      printf '%s\n' \
        "---" \
        "description: How the agent should approach this vault" \
        "type: identity" \
        "created: $today" \
        "---" \
        "" \
        "# identity" \
        "" \
        "I help maintain this $domain knowledge graph with care, restraint, and concrete file-aware guidance." \
        "" \
        "## Working Style" \
        "" \
        "- Read before changing files." \
        "- Preserve user notes and existing structure." \
        "- Prefer bounded diagnostics over noisy scans." \
        > "$path"
      ;;
    self/methodology.md)
      printf '%s\n' \
        "---" \
        "description: How this vault organizes and maintains knowledge" \
        "type: methodology" \
        "created: $today" \
        "---" \
        "" \
        "# methodology" \
        "" \
        "This vault uses markdown, YAML frontmatter, and wiki links to make local knowledge navigable by humans and agents." \
        "" \
        "Durable notes live in \`notes/\`. Capture lives in \`inbox/\`. Operational state lives in \`ops/\`." \
        > "$path"
      ;;
    manual/manual.md)
      printf '%s\n' \
        "---" \
        "description: User manual for this Ars Contexta vault" \
        "type: manual" \
        "created: $today" \
        "---" \
        "" \
        "# Manual" \
        "" \
        "Welcome to your $domain knowledge system." \
        "" \
        "## Pages" \
        "" \
        "- [[getting-started]] -- first steps" \
        "- [[skills]] -- available Codex skills" \
        > "$path"
      ;;
    manual/getting-started.md)
      printf '%s\n' \
        "---" \
        "description: First steps for using this Ars Contexta vault with Codex" \
        "type: manual" \
        "created: $today" \
        "---" \
        "" \
        "# Getting Started" \
        "" \
        "Start by adding raw thoughts or source material to \`inbox/\`. At session start, ask Codex to run \`arscontexta-session orient\`. When you want a checkup, ask Codex to run \`arscontexta-health\`." \
        "" \
        "Use \`notes/\` for durable $note_type files and \`manual/\` for human-facing guidance." \
        > "$path"
      ;;
    manual/skills.md)
      printf '%s\n' \
        "---" \
        "description: Codex skills currently available for this vault" \
        "type: manual" \
        "created: $today" \
        "---" \
        "" \
        "# Skills" \
        "" \
        "Available now:" \
        "" \
        "- \`arscontexta-help\` -- orient to the vault and choose the next action." \
        "- \`arscontexta-health\` -- run bounded read-only diagnostics." \
        "- \`arscontexta-setup\` -- create or complete minimal vault scaffolding." \
        "- \`arscontexta-session\` -- run explicit orient, validate, and capture workflows." \
        "" \
        "Use the installed Ars Contexta plugin for query, processing, maintenance, and evolution workflows." \
        > "$path"
      ;;
    ops/methodology/methodology.md)
      printf '%s\n' \
        "---" \
        "description: MOC for vault self-knowledge and operational rationale" \
        "type: moc" \
        "created: $today" \
        "---" \
        "" \
        "# methodology" \
        "" \
        "This folder records how the vault understands its own operation." \
        "" \
        "## Core Ideas" \
        "" \
        "- [[derivation-rationale]] -- why this minimal Codex setup was chosen" \
        > "$path"
      ;;
    ops/methodology/derivation-rationale.md)
      printf '%s\n' \
        "---" \
        "description: Why this initial Codex configuration was chosen" \
        "category: derivation-rationale" \
        "status: active" \
        "created: $today" \
        "---" \
        "" \
        "# derivation rationale for $domain" \
        "" \
        "The vault starts with a minimal Codex-native configuration so it can be inspected and maintained immediately without background hooks." \
        "" \
        "Preset \`$preset\` supplies initial vocabulary and starter maps. Full derivation parity remains future migration work." \
        > "$path"
      ;;
    notes/index.md)
      printf '%s\n' \
        "---" \
        "description: Entry point for the $domain knowledge graph" \
        "type: moc" \
        "created: $today" \
        "---" \
        "" \
        "# index" \
        "" \
        "Start here to orient to the main areas of this vault." \
        "" \
        "## Core Ideas" \
        "" \
        "Add links to important $topic_map files as the graph grows." \
        "" \
        "---" \
        "" \
        "Topics: []" \
        > "$path"
      ;;
    notes/methods.md)
      printf '%s\n' \
        "---" \
        "description: Tracks methods, workflows, and research process decisions" \
        "type: moc" \
        "created: $today" \
        "---" \
        "" \
        "# methods" \
        "" \
        "Use this map for methodology, process patterns, and workflow decisions." \
        "" \
        "---" \
        "" \
        "Topics:" \
        "- [[index]]" \
        > "$path"
      ;;
    notes/open-questions.md)
      printf '%s\n' \
        "---" \
        "description: Tracks unresolved questions and knowledge gaps" \
        "type: moc" \
        "created: $today" \
        "---" \
        "" \
        "# open questions" \
        "" \
        "Capture questions that deserve future exploration." \
        "" \
        "---" \
        "" \
        "Topics:" \
        "- [[index]]" \
        > "$path"
      ;;
    notes/life-areas.md)
      printf '%s\n' \
        "---" \
        "description: Maps areas of life or attention represented in this vault" \
        "type: moc" \
        "created: $today" \
        "---" \
        "" \
        "# life areas" \
        "" \
        "Use this map to organize reflections by life area." \
        "" \
        "---" \
        "" \
        "Topics:" \
        "- [[index]]" \
        > "$path"
      ;;
    notes/people.md)
      printf '%s\n' \
        "---" \
        "description: Tracks people, relationships, and social patterns" \
        "type: moc" \
        "created: $today" \
        "---" \
        "" \
        "# people" \
        "" \
        "Use this map for relationship-centered reflections." \
        "" \
        "---" \
        "" \
        "Topics:" \
        "- [[index]]" \
        > "$path"
      ;;
    notes/goals.md)
      printf '%s\n' \
        "---" \
        "description: Tracks current goals and directions of growth" \
        "type: moc" \
        "created: $today" \
        "---" \
        "" \
        "# goals" \
        "" \
        "Use this map for current goals and why they matter." \
        "" \
        "---" \
        "" \
        "Topics:" \
        "- [[index]]" \
        > "$path"
      ;;
    *)
      printf 'Internal error: no template for %s\n' "$rel" >&2
      exit 1
      ;;
  esac
  announce "CREATE" "$rel"
}

printf 'Ars Contexta minimal Codex setup\n'
printf 'Vault: %s\n' "$vault_abs"
printf 'Preset: %s\n' "$preset"
printf 'Domain: %s\n' "$domain"
if [[ "$dry_run" == true ]]; then
  printf 'Mode: dry run\n'
else
  printf 'Mode: write missing files only\n'
fi
printf '\n'

if [[ -f "$vault_abs/.agents/plugins/marketplace.json" || -f "$vault_abs/plugins/arscontexta/.codex-plugin/plugin.json" ]]; then
  printf 'ERROR: This looks like the Ars Contexta plugin repo, not a target vault. Choose another directory.\n' >&2
  exit 1
fi

for dir in \
  notes inbox archive self manual templates ops \
  ops/queue ops/queue/archive ops/health ops/observations ops/tensions ops/sessions ops/methodology
do
  ensure_dir "$vault_abs/$dir"
done

for file in \
  .arscontexta \
  AGENTS.md \
  ops/derivation.md \
  ops/derivation-manifest.md \
  ops/config.yaml \
  templates/base-note.md \
  templates/moc.md \
  self/identity.md \
  self/methodology.md \
  manual/manual.md \
  manual/getting-started.md \
  manual/skills.md \
  ops/methodology/methodology.md \
  ops/methodology/derivation-rationale.md
do
  write_file "$vault_abs/$file"
done

for starter in $starter_files; do
  write_starter_note "$starter"
done

printf '\n'
printf 'Next: run scripts/check-vault.sh "%s" from the Ars Contexta repo, then run arscontexta-health in Codex.\n' "$vault_abs"
