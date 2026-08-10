#!/usr/bin/env bash

set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/codex/handoff-reminder.sh"
TMP=$(mktemp -d)
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

run() {
  local name="$1" source="$2" current="$3" cwd="$4" expected="$5"
  local input out
  input=$(jq -nc --arg source "$source" --arg transcript "$current" --arg cwd "$cwd" \
    '{source:$source, transcript_path:$transcript, cwd:$cwd}')
  out=$(printf '%s\n' "$input" | bash "$HOOK")
  if [[ "$out" == *"$expected"* ]]; then
    echo "  ✅ $name"; PASS=$((PASS+1))
  else
    echo "  ❌ $name"; FAIL=$((FAIL+1))
  fi
}

run_empty() {
  local name="$1" source="$2" current="$3" cwd="$4" input out
  input=$(jq -nc --arg source "$source" --arg transcript "$current" --arg cwd "$cwd" \
    '{source:$source, transcript_path:$transcript, cwd:$cwd}')
  out=$(printf '%s\n' "$input" | bash "$HOOK")
  if [[ -z "$out" ]]; then
    echo "  ✅ $name"; PASS=$((PASS+1))
  else
    echo "  ❌ $name"; FAIL=$((FAIL+1))
  fi
}

SESSIONS="$TMP/sessions"; PROJECT="$TMP/project"
mkdir -p "$SESSIONS" "$PROJECT"
PREV="$SESSIONS/previous.jsonl"; CURRENT="$SESSIONS/current.jsonl"
for _ in $(seq 1 50); do echo '{}'; done > "$PREV"
echo '{}' > "$CURRENT"
touch -r "$PREV" "$PROJECT/handoff-feature.md"

echo "codex handoff-reminder tests"
run "fresh handoff is injected" "clear" "$CURRENT" "$PROJECT" "fresh handoff exists"
run_empty "non-clear does nothing" "startup" "$CURRENT" "$PROJECT"
rm "$PROJECT/handoff-feature.md"
run "missing handoff offers options" "clear" "$CURRENT" "$PROJECT" "choose A, B, or C"

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" == 0 ]]
