#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

usage() {
  printf 'Usage: %s <vault-path>\n' "$(basename "$0")" >&2
}

if [[ $# -ne 1 ]]; then
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

json_parse_stdin() {
  if command -v jq >/dev/null 2>&1; then
    jq . >/dev/null
  elif command -v ruby >/dev/null 2>&1; then
    ruby -rjson -e 'JSON.parse(STDIN.read)' >/dev/null
  else
    return 127
  fi
}

vault="$1"

if [[ ! -d "$vault" ]]; then
  emit FAIL "Vault path is not a directory: $vault."
  printf 'Summary: %s PASS, %s WARN, %s FAIL\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
  exit 1
fi

vault_abs="$(cd "$vault" && pwd -P)"
emit PASS "Vault path exists: $vault_abs."

if [[ -e "$vault_abs/.hippocampusmd" ]]; then
  emit PASS ".hippocampusmd marker exists."
else
  emit FAIL ".hippocampusmd marker is missing."
fi

for dir in notes inbox ops self manual; do
  if [[ -d "$vault_abs/$dir" ]]; then
    emit PASS "Expected directory exists: $dir/."
  else
    emit WARN "Expected directory is missing: $dir/."
  fi
done

for file in ops/derivation-manifest.md ops/derivation.md ops/config.yaml; do
  if [[ -f "$vault_abs/$file" ]]; then
    emit PASS "Expected config file exists: $file."
  else
    emit WARN "Expected config file is missing: $file."
  fi
done

helper="$REPO_ROOT/plugins/hippocampusmd/scripts/vault-health.sh"
if [[ -x "$helper" ]]; then
  if output="$("$helper" "$vault_abs" --mode quick --limit 5 --format json 2>&1)"; then
    if printf '%s\n' "$output" | json_parse_stdin; then
      emit PASS "Bounded vault health helper completed with parseable JSON."
    else
      emit FAIL "Bounded vault health helper output was not parseable JSON."
    fi
  else
    emit FAIL "Bounded vault health helper failed: $output"
  fi
else
  emit WARN "Bounded vault health helper is not executable at plugins/hippocampusmd/scripts/vault-health.sh."
fi

printf 'Summary: %s PASS, %s WARN, %s FAIL\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
