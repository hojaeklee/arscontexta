#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
CODEX_CONFIG_PATH="${CODEX_CONFIG_PATH:-$HOME/.codex/config.toml}"
CODEX_CACHE_ROOT="${CODEX_CACHE_ROOT:-$HOME/.codex/plugins/cache}"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

usage() {
  printf 'Usage: %s\n' "$(basename "$0")" >&2
}

if [[ $# -gt 0 ]]; then
  usage
  exit 2
fi

emit() {
  local level="$1"
  local message="$2"

  printf '%s %s\n' "$level" "$message"
  case "$level" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
  esac
}

json_available() {
  command -v jq >/dev/null 2>&1 || command -v ruby >/dev/null 2>&1
}

json_parse() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq . "$file" >/dev/null
  elif command -v ruby >/dev/null 2>&1; then
    ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "$file" >/dev/null
  else
    return 127
  fi
}

json_get() {
  local file="$1"
  local path="$2"

  if command -v jq >/dev/null 2>&1; then
    jq -r "$path // empty" "$file"
  else
    JSON_PATH="$path" ruby -rjson -e '
      data = JSON.parse(File.read(ARGV.fetch(0)))
      path = ENV.fetch("JSON_PATH")
      value =
        case path
        when ".name" then data["name"]
        when ".version" then data["version"]
        when ".skills" then data["skills"]
        when ".plugins[0].name" then data.dig("plugins", 0, "name")
        when ".plugins[0].source.path" then data.dig("plugins", 0, "source", "path")
        else nil
        end
      puts value if value
    ' "$file"
  fi
}

toml_section_contains() {
  local file="$1"
  local section="$2"
  local pattern="$3"

  awk -v section="$section" -v pattern="$pattern" '
    $0 == section { in_section = 1; next }
    /^\[/ && in_section { exit }
    in_section && index($0, pattern) { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$file"
}

require_json_tools() {
  if json_available; then
    return 0
  fi
  emit FAIL "JSON parsing requires jq or Ruby."
  return 1
}

marketplace="$REPO_ROOT/.agents/plugins/marketplace.json"
manifest="$REPO_ROOT/plugins/arscontexta/.codex-plugin/plugin.json"
health_helper="$REPO_ROOT/plugins/arscontexta/scripts/vault-health.sh"
setup_helper="$REPO_ROOT/plugins/arscontexta/scripts/setup-vault.sh"
session_orient_helper="$REPO_ROOT/plugins/arscontexta/scripts/session-orient.sh"
session_validate_helper="$REPO_ROOT/plugins/arscontexta/scripts/session-validate.sh"
session_capture_helper="$REPO_ROOT/plugins/arscontexta/scripts/session-capture.sh"
mcp_tools_helper="$REPO_ROOT/plugins/arscontexta/scripts/mcp-vault-tools.sh"
validate_helper="$REPO_ROOT/plugins/arscontexta/scripts/validate-vault.sh"
tasks_helper="$REPO_ROOT/plugins/arscontexta/scripts/tasks-vault.sh"
next_helper="$REPO_ROOT/plugins/arscontexta/scripts/next-vault.sh"
stats_helper="$REPO_ROOT/plugins/arscontexta/scripts/stats-vault.sh"
graph_helper="$REPO_ROOT/plugins/arscontexta/scripts/graph-vault.sh"
seed_helper="$REPO_ROOT/plugins/arscontexta/scripts/seed-vault.sh"
ralph_helper="$REPO_ROOT/plugins/arscontexta/scripts/ralph-vault.sh"
pipeline_helper="$REPO_ROOT/plugins/arscontexta/scripts/pipeline-vault.sh"
archive_batch_helper="$REPO_ROOT/plugins/arscontexta/scripts/archive-batch-vault.sh"

if require_json_tools; then
  if [[ -f "$marketplace" ]]; then
    if json_parse "$marketplace"; then
      emit PASS ".agents/plugins/marketplace.json parses."
      marketplace_name="$(json_get "$marketplace" ".name")"
      plugin_name="$(json_get "$marketplace" ".plugins[0].name")"
      plugin_path="$(json_get "$marketplace" ".plugins[0].source.path")"

      [[ "$marketplace_name" == "agenticnotetaking" ]] \
        && emit PASS "Marketplace name is agenticnotetaking." \
        || emit FAIL "Marketplace name is '$marketplace_name', expected agenticnotetaking."

      [[ "$plugin_name" == "arscontexta" ]] \
        && emit PASS "Marketplace contains arscontexta plugin entry." \
        || emit FAIL "Marketplace first plugin is '$plugin_name', expected arscontexta."

      [[ "$plugin_path" == "./plugins/arscontexta" ]] \
        && emit PASS "Marketplace plugin path is ./plugins/arscontexta." \
        || emit FAIL "Marketplace plugin path is '$plugin_path', expected ./plugins/arscontexta."
    else
      emit FAIL ".agents/plugins/marketplace.json does not parse."
    fi
  else
    emit FAIL ".agents/plugins/marketplace.json is missing."
  fi

  if [[ -f "$manifest" ]]; then
    if json_parse "$manifest"; then
      emit PASS "plugins/arscontexta/.codex-plugin/plugin.json parses."
      manifest_name="$(json_get "$manifest" ".name")"
      manifest_version="$(json_get "$manifest" ".version")"
      skills_path="$(json_get "$manifest" ".skills")"

      [[ "$manifest_name" == "arscontexta" ]] \
        && emit PASS "Plugin manifest name is arscontexta." \
        || emit FAIL "Plugin manifest name is '$manifest_name', expected arscontexta."

      [[ -n "$manifest_version" ]] \
        && emit PASS "Plugin manifest version is $manifest_version." \
        || emit FAIL "Plugin manifest version is missing."

      [[ "$skills_path" == "./skills/" ]] \
        && emit PASS "Plugin manifest uses skills path ./skills/." \
        || emit FAIL "Plugin manifest skills path is '$skills_path', expected ./skills/."
    else
      emit FAIL "plugins/arscontexta/.codex-plugin/plugin.json does not parse."
      manifest_version=""
    fi
  else
    emit FAIL "plugins/arscontexta/.codex-plugin/plugin.json is missing."
    manifest_version=""
  fi
fi

for skill_name in arscontexta-help arscontexta-health arscontexta-setup arscontexta-session arscontexta-validate arscontexta-tasks arscontexta-next arscontexta-stats arscontexta-graph arscontexta-ask arscontexta-recommend arscontexta-reduce arscontexta-reflect arscontexta-reweave arscontexta-verify arscontexta-remember arscontexta-rethink arscontexta-architect arscontexta-refactor arscontexta-reseed arscontexta-upgrade arscontexta-add-domain arscontexta-seed arscontexta-ralph arscontexta-pipeline arscontexta-archive-batch arscontexta-tutorial arscontexta-learn; do
  skill_file="$REPO_ROOT/plugins/arscontexta/skills/$skill_name/SKILL.md"
  if [[ -f "$skill_file" ]]; then
    emit PASS "$skill_name skill exists in installable plugin."
    if awk -v expected="name: $skill_name" 'NR == 1 && $0 == "---" { in_fm = 1; next } in_fm && $0 == expected { found = 1 } in_fm && NR > 1 && $0 == "---" { exit } END { exit found ? 0 : 1 }' "$skill_file"; then
      emit PASS "$skill_name skill frontmatter declares name."
    else
      emit FAIL "$skill_name skill frontmatter is missing name: $skill_name."
    fi
  else
    emit FAIL "$skill_name skill is missing from installable plugin."
  fi
done

if [[ -x "$health_helper" ]]; then
  emit PASS "Bundled vault health helper exists and is executable."
elif [[ -f "$health_helper" ]]; then
  emit WARN "Bundled vault health helper exists but is not executable."
else
  emit FAIL "Bundled vault health helper is missing."
fi

if [[ -x "$setup_helper" ]]; then
  emit PASS "Bundled vault setup helper exists and is executable."
elif [[ -f "$setup_helper" ]]; then
  emit WARN "Bundled vault setup helper exists but is not executable."
else
  emit FAIL "Bundled vault setup helper is missing."
fi

for helper in \
  "$session_orient_helper:session orientation" \
  "$session_validate_helper:session validation" \
  "$session_capture_helper:session capture" \
  "$mcp_tools_helper:MCP vault tools prototype" \
  "$validate_helper:vault validation" \
  "$tasks_helper:vault tasks" \
  "$next_helper:vault next action" \
  "$stats_helper:vault stats" \
  "$graph_helper:vault graph" \
  "$seed_helper:vault seed" \
  "$ralph_helper:vault ralph" \
  "$pipeline_helper:vault pipeline" \
  "$archive_batch_helper:vault archive-batch"
do
  helper_path="${helper%%:*}"
  helper_label="${helper#*:}"
  if [[ -x "$helper_path" ]]; then
    emit PASS "Bundled $helper_label helper exists and is executable."
  elif [[ -f "$helper_path" ]]; then
    emit WARN "Bundled $helper_label helper exists but is not executable."
  else
    emit FAIL "Bundled $helper_label helper is missing."
  fi
done

if [[ -f "$CODEX_CONFIG_PATH" ]]; then
  emit PASS "Codex config found at $CODEX_CONFIG_PATH."

  if grep -Fqx '[marketplaces.agenticnotetaking]' "$CODEX_CONFIG_PATH"; then
    emit PASS "Codex config has marketplaces.agenticnotetaking block."
    if toml_section_contains "$CODEX_CONFIG_PATH" '[marketplaces.agenticnotetaking]' "source = \"$REPO_ROOT\""; then
      emit PASS "Codex marketplace source points at this repo."
    else
      emit WARN "Codex marketplace source does not point at this repo: $REPO_ROOT."
    fi
  else
    emit WARN "Codex config is missing marketplaces.agenticnotetaking block."
  fi

  if grep -Fqx '[plugins."arscontexta@agenticnotetaking"]' "$CODEX_CONFIG_PATH"; then
    if toml_section_contains "$CODEX_CONFIG_PATH" '[plugins."arscontexta@agenticnotetaking"]' 'enabled = true'; then
      emit PASS "Codex config enables arscontexta@agenticnotetaking."
    else
      emit WARN "Codex config has arscontexta plugin block but enabled = true was not found."
    fi
  else
    emit WARN "Codex config is missing arscontexta@agenticnotetaking plugin block."
  fi

  if grep -Eq '^[[:space:]]*model[[:space:]]*=[[:space:]]*"gpt-5-codex"' "$CODEX_CONFIG_PATH"; then
    emit FAIL "Codex config uses unsupported ChatGPT-account model gpt-5-codex."
  else
    emit PASS "Codex config does not use denied model gpt-5-codex."
  fi
else
  emit WARN "Codex config not found at $CODEX_CONFIG_PATH; skipping local install checks."
fi

if [[ -n "${manifest_version:-}" ]]; then
  cache_dir="$CODEX_CACHE_ROOT/agenticnotetaking/arscontexta/$manifest_version"
  if [[ -d "$cache_dir" ]]; then
    emit PASS "Codex cache exists for arscontexta $manifest_version."
    [[ -f "$cache_dir/.codex-plugin/plugin.json" ]] \
      && emit PASS "Cached plugin manifest exists." \
      || emit WARN "Cached plugin manifest is missing."
    for skill_name in arscontexta-help arscontexta-health arscontexta-setup arscontexta-session arscontexta-validate arscontexta-tasks arscontexta-next arscontexta-stats arscontexta-graph arscontexta-ask arscontexta-recommend arscontexta-reduce arscontexta-reflect arscontexta-reweave arscontexta-verify arscontexta-remember arscontexta-rethink arscontexta-architect arscontexta-refactor arscontexta-reseed arscontexta-upgrade arscontexta-add-domain arscontexta-seed arscontexta-ralph arscontexta-pipeline arscontexta-archive-batch arscontexta-tutorial arscontexta-learn; do
      [[ -f "$cache_dir/skills/$skill_name/SKILL.md" ]] \
        && emit PASS "Cached $skill_name skill exists." \
        || emit WARN "Cached $skill_name skill is missing; reinstall plugin after adding new Codex skills."
    done
    [[ -f "$cache_dir/scripts/vault-health.sh" ]] \
      && emit PASS "Cached vault health helper exists." \
      || emit WARN "Cached vault health helper is missing; reinstall plugin after #10 changes."
    [[ -f "$cache_dir/scripts/setup-vault.sh" ]] \
      && emit PASS "Cached vault setup helper exists." \
      || emit WARN "Cached vault setup helper is missing; reinstall plugin after adding setup."
    for helper_name in session-orient.sh session-validate.sh session-capture.sh mcp-vault-tools.sh validate-vault.sh tasks-vault.sh next-vault.sh stats-vault.sh graph-vault.sh seed-vault.sh ralph-vault.sh pipeline-vault.sh archive-batch-vault.sh; do
      [[ -f "$cache_dir/scripts/$helper_name" ]] \
        && emit PASS "Cached $helper_name helper exists." \
        || emit WARN "Cached $helper_name helper is missing; reinstall plugin after adding session or MCP workflows."
    done
  else
    emit WARN "No Codex cache found for arscontexta $manifest_version at $cache_dir."
  fi
else
  emit WARN "Skipping cache check because manifest version was not available."
fi

printf 'Summary: %s PASS, %s WARN, %s FAIL\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
