#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.codex"
printf '[tui]\nanimations = false\nstatus_line = ["model"]\n\n[history]\npersistence = "save-all"\n' > "$TEST_HOME/.codex/config.toml"

HOME="$TEST_HOME" bash "$ROOT/scripts/codex/install.sh" >/dev/null
HOME="$TEST_HOME" bash "$ROOT/scripts/codex/install.sh" >/dev/null

CONFIG="$TEST_HOME/.codex/config.toml"
HOOKS="$TEST_HOME/.codex/hooks.json"

grep -Fqx 'status_line = ["model-with-reasoning", "context-used", "used-tokens", "total-input-tokens", "total-output-tokens", "five-hour-limit", "weekly-limit", "git-branch"]' "$CONFIG"
grep -Fqx 'animations = false' "$CONFIG"
grep -Fqx 'persistence = "save-all"' "$CONFIG"
jq -e '[.hooks.PreToolUse[] | .hooks[]?.command | select(test("grounding-guard\\.sh$"))] | length == 1' "$HOOKS" >/dev/null
jq -e '[.hooks.SessionStart[] | .hooks[]?.command | select(test("handoff-reminder\\.sh$"))] | length == 1' "$HOOKS" >/dev/null
# Registration and the file on disk are separate failure modes: a registered path
# that was never copied is the "looks installed, does nothing" case this repo keeps
# hitting. Assert both. `length == 1` also pins idempotency (installer ran twice).
jq -e '[.hooks.PreToolUse[] | .hooks[]?.command | select(test("secret-guard\\.sh$"))] | length == 1' "$HOOKS" >/dev/null
[ -x "$TEST_HOME/.codex/hooks/shared/secret-guard.sh" ]

echo 'CODEX_INSTALL_TEST_STATUS=PASS'
