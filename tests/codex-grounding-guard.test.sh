#!/usr/bin/env bash

set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/codex/grounding-guard.sh"
TMP=$(mktemp -d)
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; rm -f /tmp/dotai_grounding_codex_test-*; }
trap cleanup EXIT

mkrepo() {
  local branch="$1" d="$TMP/repo_$1_$RANDOM"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" commit -q --allow-empty -m init
  git -C "$d" checkout -q -B "$branch"
  echo "$d"
}

mktranscript() {
  local f="$TMP/transcript_$RANDOM.jsonl"
  printf '%s\n' "$1" > "$f"
  echo "$f"
}

run() {
  local name="$1" cwd="$2" tpath="$3" patch="$4" sid="$5" expect="$6"
  local json out code
  json=$(jq -nc --arg transcript "$tpath" --arg patch "$patch" --arg sid "$sid" \
    '{transcript_path:$transcript, tool_input:{command:$patch}, session_id:$sid}')
  out=$(cd "$cwd" && printf '%s\n' "$json" | bash "$HOOK" 2>/dev/null)
  code=$?
  if [[ "$code" == "$expect" ]]; then
    echo "  ✅ $name (exit $code)"; PASS=$((PASS+1))
  else
    echo "  ❌ $name (got exit $code, expected $expect)"; FAIL=$((FAIL+1))
  fi
}

FEAT=$(mkrepo feature/test)
MAIN=$(mkrepo main)
NONREPO="$TMP/notarepo"; mkdir -p "$NONREPO"
PATCH_CODE='*** Begin Patch
*** Update File: src/x.php
*** End Patch'
PATCH_DOC='*** Begin Patch
*** Update File: README.md
*** End Patch'
T_NONE=$(mktranscript 'about to edit')
T_PASS=$(mktranscript 'GROUNDING_STATUS=PASS')
T_SKIP=$(mktranscript 'GROUNDING_STATUS=SKIP reason=typo fix')

echo "codex grounding-guard tests"
run "first code patch blocks" "$FEAT" "$T_NONE" "$PATCH_CODE" "test-a" 2
run "PASS allows" "$FEAT" "$T_PASS" "$PATCH_CODE" "test-b" 0
run "document-only patch allows" "$FEAT" "$T_NONE" "$PATCH_DOC" "test-c" 0
run "SKIP allows" "$FEAT" "$T_SKIP" "$PATCH_CODE" "test-d" 0
echo "1" > /tmp/dotai_grounding_codex_test-e
run "second code patch allows" "$FEAT" "$T_NONE" "$PATCH_CODE" "test-e" 0
run "main allows" "$MAIN" "$T_NONE" "$PATCH_CODE" "test-f" 0
run "missing transcript allows" "$FEAT" "$TMP/nope.jsonl" "$PATCH_CODE" "test-g" 0
run "non-git repo allows" "$NONREPO" "$T_NONE" "$PATCH_CODE" "test-h" 0

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" == 0 ]]
