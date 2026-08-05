#!/usr/bin/env bash

# Pins WHERE the agy installer writes hooks, because the wrong location fails
# silently: agy only reads hooks.json from a customization root (globally
# ~/.gemini/config/), and ignores settings.json .hooks entirely.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

SETTINGS="$TEST_HOME/.gemini/antigravity-cli/settings.json"
mkdir -p "$(dirname "$SETTINGS")"

# Seed the state a pre-fix dotai left behind: dead hooks under events agy does
# not have, plus one hand-written hook that must survive the upgrade.
cat > "$SETTINGS" <<'EOF'
{
  "hooks": {
    "AfterAgent": [
      {"hooks": [{"name": "stop-guard", "type": "command", "command": "bash /Users/x/.gemini/hooks/stop-guard.sh"}]},
      {"hooks": [{"name": "user-own", "type": "command", "command": "bash /Users/x/my-own-hook.sh"}]}
    ],
    "BeforeTool": [
      {"hooks": [{"name": "grounding-guard", "type": "command", "command": "bash /Users/x/.gemini/hooks/grounding-guard.sh"}]}
    ]
  },
  "someUnrelatedSetting": true
}
EOF

mkdir -p "$TEST_HOME/.gemini/config"
cat > "$TEST_HOME/.gemini/config/hooks.json" <<'EOF'
{
  "my-own-linter": {"PostToolUse": [{"matcher": "run_command", "hooks": [{"type": "command", "command": "./lint.sh"}]}]},
  "dotai-stale-guard": {"Stop": [{"type": "command", "command": "bash ~/.gemini/hooks/gone.sh"}]}
}
EOF

HOME="$TEST_HOME" bash "$ROOT/scripts/agy/install.sh" >/dev/null
HOME="$TEST_HOME" bash "$ROOT/scripts/agy/install.sh" >/dev/null

HJ="$TEST_HOME/.gemini/config/hooks.json"

fail() { echo "❌ $1" >&2; exit 1; }

[ -f "$HJ" ] || fail "hooks.json was not written to the global customization root"

# Every dotai guard is registered, under an event agy actually supports.
for name in dotai-stop-guard dotai-grounding-guard \
            dotai-branch-guard dotai-glab-guard \
            dotai-context-budget-guard; do
  jq -e --arg n "$name" 'has($n)' "$HJ" >/dev/null || fail "hooks.json missing $name"
done

# Retired by the prompt-layer ablation (docs/ABLATION.md): complexity-guard was
# provably inert, read-dedup-guard duplicated harness-native behaviour. Pinned as
# ABSENT so a stale copy cannot quietly return.
for gone in dotai-read-dedup-guard dotai-complexity-guard; do
  jq -e --arg n "$gone" 'has($n) | not' "$HJ" >/dev/null || fail "hooks.json still registers retired $gone"
done

BADEVENTS=$(jq -r '[.[] | keys[] | select(. != "enabled")]
  | map(select(. as $e | ["PreToolUse","PostToolUse","PreInvocation","PostInvocation","Stop"]
  | index($e) | not)) | unique | join(",")' "$HJ")
[ -z "$BADEVENTS" ] || fail "hooks.json uses events agy does not have: $BADEVENTS"

# Foreign hooks survive; our own stale keys are replaced not duplicated.
jq -e 'has("my-own-linter")' "$HJ" >/dev/null || fail "installer clobbered a hand-written hook"
jq -e 'has("dotai-stale-guard") | not' "$HJ" >/dev/null || fail "stale dotai-* key not pruned"

# Referenced scripts must exist and be executable, or every hook silently no-ops.
# Checks every ~/-rooted token, so the adapter AND the guard it wraps are both
# verified — a missing wrapped guard would make the hook a silent no-op.
while read -r cmd; do
  for token in $cmd; do
    case "$token" in
      '~'/*) script="${token/#\~/$TEST_HOME}"
             [ -x "$script" ] || fail "hook command points at missing/non-executable $script" ;;
    esac
  done
done < <(jq -r 'with_entries(select(.key | startswith("dotai-")))
                | .. | objects | select(has("command")) | .command' "$HJ")

# settings.json: dead dotai entries pruned, foreign hook and settings preserved,
# status line still registered.
jq -e '[.hooks.AfterAgent[]?.hooks[]?.command] | map(select(test("\\.gemini/hooks/"))) | length == 0' \
  "$SETTINGS" >/dev/null || fail "dead dotai AfterAgent entries not removed from settings.json"
jq -e '(.hooks.AfterAgent // []) | map(.hooks[0].name) | index("user-own") != null' \
  "$SETTINGS" >/dev/null || fail "installer removed a hand-written settings.json hook"
jq -e '.someUnrelatedSetting == true' "$SETTINGS" >/dev/null || fail "unrelated setting lost"
jq -e '.statusLine.command | test("statusline\\.sh")' "$SETTINGS" >/dev/null || fail "status line not registered"

echo 'AGY_INSTALL_TEST_STATUS=PASS'
