#!/usr/bin/env bash

# Covers commands/precommit.sh, and the receipt contract it shares with
# hooks/claude/stop-guard.sh.
#
# Written after 2026-08-21, when /precommit hit a repo with no detectable stack,
# returned "❌ Could not detect tech stack / FAIL", and the agent responded by
# writing its own .claude/commands/precommit.sh into that repo and grading its
# own work with it. The two behaviours that close that off — generic mode, and
# honouring a project override only when git tracks it — are asserted here.
#
# Also settles a claim both files used to make about a "tests/stop-guard.test.sh"
# that did not exist: the fingerprint parity between precommit.sh and
# stop-guard.sh is checked at the bottom, by running the real guard.
#
# Every credential below is SYNTHETIC. Never paste a real one into a fixture.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRECOMMIT="$ROOT/commands/precommit.sh"
STOP_GUARD="$ROOT/hooks/claude/stop-guard.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "❌ $1" >&2; }

# -P: mktemp hands back /var/folders/… on macOS while `git rev-parse
# --show-toplevel` reports the physical /private/var/folders/… . stop-guard
# compares the two as strings, so a logical path here makes it fail open and the
# parity checks at the bottom silently pass for the wrong reason.
TMPROOT=$(cd "$(mktemp -d -t dotai-precommit-test)" && pwd -P)
trap 'rm -rf "$TMPROOT"' EXIT

# A repo with no artisan, no package.json and no tests/*.test.sh — i.e. the
# situation that used to be a dead end. On a feature branch, because stop-guard
# skips its whole check on master/main.
new_repo() {
  local d="$TMPROOT/$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name  test
  echo "# fixture" > "$d/README.md"
  git -C "$d" add README.md
  git -C "$d" commit -qm init
  git -C "$d" checkout -q -b feature/work
  printf '%s' "$d"
}

# Runs the pipeline inside a repo, leaving its output in $OUT and its exit
# status in $RC. Not a command substitution: that would put RC in a subshell.
OUT=""
RC=0
run_precommit() {
  local d="$1"
  OUT=$(cd "$d" && env -u DOTAI_PRECOMMIT_DISPATCHED ENABLE_LSP_TOOL=0 bash "$PRECOMMIT" 2>&1)
  RC=$?
}

receipt_field() {
  sed -n "s/^$2=//p" "$1/.git/dotai-precommit" | head -1
}

# ── Generic mode passes, and says exactly what it did not do ──────────────────

D=$(new_repo generic-pass)
printf 'plain text\n' > "$D/notes.txt"
printf '{"a": 1}\n' > "$D/data.json"
printf '#!/bin/bash\necho hi\n' > "$D/tool.sh"
run_precommit "$D"

[ "$RC" -eq 0 ] && ok || bad "generic mode should exit 0, got $RC"
grep -Fq 'PRECOMMIT_STATUS=PASS' <<< "$OUT" && ok || bad "generic mode: no PASS line"
grep -Fq 'PRECOMMIT_MODE=generic' <<< "$OUT" && ok || bad "generic mode: mode line missing"
grep -Fq 'no build ran, no tests ran' <<< "$OUT" && ok \
  || bad "generic PASS must state that nothing was built or tested"
grep -Fq 'Pending files inspected: 3' <<< "$OUT" && ok \
  || bad "generic mode should report how many pending files it looked at"
[ "$(receipt_field "$D" status)" = PASS ] && ok || bad "receipt status should be PASS"
[ "$(receipt_field "$D" mode)" = generic ] && ok || bad "receipt mode should be generic"

# The whole point: it writes nothing into the repo it is checking.
[ -e "$D/.claude" ] && bad "generic mode created .claude/ in the target repo" || ok
[ -z "$(find "$D" -name '__pycache__' -print -quit)" ] && ok \
  || bad "generic mode left __pycache__ behind"
[ "$(cd "$D" && git status --porcelain | wc -l | tr -d ' ')" = 3 ] && ok \
  || bad "generic mode changed the working tree"

# ── Generic mode still fails on things that matter ────────────────────────────

D=$(new_repo generic-conflict)
{ printf 'a\n'; printf '<<<<<<< HEAD\n'; printf 'b\n'; printf '>>>>>>> other\n'; } > "$D/merged.txt"
run_precommit "$D"
[ "$RC" -ne 0 ] && ok || bad "conflict markers should fail"
grep -Fq 'PRECOMMIT_STATUS=FAIL' <<< "$OUT" && ok || bad "conflict markers: no FAIL line"
grep -Fq 'merged.txt' <<< "$OUT" && ok || bad "conflict markers: file not named"
[ "$(receipt_field "$D" status)" = FAIL ] && ok || bad "conflict markers: receipt not FAIL"

D=$(new_repo generic-json)
printf '{"a": }\n' > "$D/broken.json"
run_precommit "$D"
[ "$RC" -ne 0 ] && grep -Fq 'invalid JSON' <<< "$OUT" && ok || bad "broken JSON should fail"

D=$(new_repo generic-shell)
printf '#!/bin/bash\nif [ 1 -eq 1 ]; then\n' > "$D/broken.sh"
run_precommit "$D"
[ "$RC" -ne 0 ] && grep -Fq 'syntax error' <<< "$OUT" && ok || bad "broken shell should fail"

D=$(new_repo generic-python)
printf 'def f(:\n' > "$D/broken.py"
run_precommit "$D"
if command -v python3 >/dev/null 2>&1; then
  [ "$RC" -ne 0 ] && ok || bad "broken python should fail"
  [ -z "$(find "$D" -name '__pycache__' -print -quit)" ] && ok \
    || bad "python check must not compile to disk"
else
  [ "$RC" -eq 0 ] && ok || bad "no python3: unparseable .py should be skipped, not failed"
  ok
fi

# A credential shape fails the pipeline, and the report names the file and line
# WITHOUT echoing the value — printing it is what put a token in a transcript on
# 2026-08-06 (CLAUDE.md §Credential handling).
D=$(new_repo generic-secret)
SYNTH="ghp_$(printf 'A%.0s' $(seq 1 36))"
printf 'token = %s\n' "$SYNTH" > "$D/config.txt"
run_precommit "$D"
[ "$RC" -ne 0 ] && ok || bad "credential shape should fail"
grep -Fq 'possible credential in config.txt at line(s): 1' <<< "$OUT" && ok \
  || bad "secret_scan should name file and line"
grep -Fq "$SYNTH" <<< "$OUT" && bad "secret_scan echoed the credential" || ok

# ── Project override: tracked wins, untracked is refused ─────────────────────

# An untracked override is exactly what an agent writes to satisfy the gate, so
# it is ignored and generic mode runs instead.
D=$(new_repo override-untracked)
mkdir -p "$D/.claude/commands"
printf '#!/bin/bash\necho "SELF-GRADED"\necho "PRECOMMIT_STATUS=PASS"\n' > "$D/.claude/commands/precommit.sh"
run_precommit "$D"
grep -Fq 'Ignoring UNTRACKED' <<< "$OUT" && ok || bad "untracked override should be refused"
grep -Fq 'SELF-GRADED' <<< "$OUT" && bad "untracked override was executed" || ok
grep -Fq 'PRECOMMIT_MODE=generic' <<< "$OUT" && ok \
  || bad "untracked override should fall through to generic mode"

# Committed, it is the project's own pipeline and runs instead of detection.
D=$(new_repo override-tracked)
mkdir -p "$D/.claude/commands"
printf '#!/bin/bash\necho "PROJECT PIPELINE RAN"\nexit 0\n' > "$D/.claude/commands/precommit.sh"
git -C "$D" add .claude/commands/precommit.sh
git -C "$D" commit -qm "add project pipeline"
run_precommit "$D"
[ "$RC" -eq 0 ] && ok || bad "tracked override exiting 0 should pass"
grep -Fq 'PROJECT PIPELINE RAN' <<< "$OUT" && ok || bad "tracked override did not run"
grep -Fq 'PRECOMMIT_MODE=project' <<< "$OUT" && ok || bad "override should report mode=project"
[ "$(receipt_field "$D" mode)" = project ] && ok || bad "receipt mode should be project"

# A non-zero exit is a FAIL even with no protocol line…
D=$(new_repo override-fails)
mkdir -p "$D/.claude/commands"
printf '#!/bin/bash\necho "boom"\nexit 3\n' > "$D/.claude/commands/precommit.sh"
git -C "$D" add .claude/commands/precommit.sh
git -C "$D" commit -qm "add failing pipeline"
run_precommit "$D"
[ "$RC" -ne 0 ] && grep -Fq 'PRECOMMIT_STATUS=FAIL' <<< "$OUT" && ok \
  || bad "override exiting non-zero should fail"

# …and a declared PASS cannot override a non-zero exit.
D=$(new_repo override-lies)
mkdir -p "$D/.claude/commands"
printf '#!/bin/bash\necho "PRECOMMIT_STATUS=PASS"\nexit 1\n' > "$D/.claude/commands/precommit.sh"
git -C "$D" add .claude/commands/precommit.sh
git -C "$D" commit -qm "add lying pipeline"
run_precommit "$D"
[ "$RC" -ne 0 ] && ok || bad "declared PASS with non-zero exit must not pass"
[ "$(receipt_field "$D" status)" = FAIL ] && ok || bad "lying override: receipt should be FAIL"

# ── Receipt parity with stop-guard ───────────────────────────────────────────
#
# Runs the real guard rather than re-deriving the fingerprint, so this fails if
# either side's algorithm drifts — the claim both files' comments make.

guard() {
  local d="$1" transcript="$1/.transcript.jsonl"
  jq -cn --arg p "$d/app.sh" \
    '{type:"assistant",message:{content:[{type:"tool_use",name:"Write",input:{file_path:$p}}]}}' \
    > "$transcript"
  (cd "$d" && jq -cn --arg t "$transcript" '{transcript_path:$t,stop_hook_active:true}' \
    | bash "$STOP_GUARD" >/dev/null 2>&1)
  return $?
}

D=$(new_repo guard-parity)
printf '#!/bin/bash\necho v1\n' > "$D/app.sh"

guard "$D"; [ $? -eq 2 ] && ok || bad "stop-guard should block with no receipt"

run_precommit "$D"
[ "$RC" -eq 0 ] && ok || bad "parity fixture: precommit should pass"
guard "$D"; [ $? -eq 0 ] && ok || bad "stop-guard should allow after a generic PASS"

printf '#!/bin/bash\necho v2\n' > "$D/app.sh"
guard "$D"; [ $? -eq 2 ] && ok \
  || bad "stop-guard should block once the tree changed after the PASS"

# All three stop-guards recompute the fingerprint inline. A drift in any of them
# does not fail open — it fails CLOSED, every PASS mismatching forever — so the
# recipe is compared textually here for the two CLIs whose guards cannot be run
# from bash directly (they speak JSON decisions, not exit codes).
fingerprint_recipe() {
  sed -n '/rev-parse HEAD/,/xargs -0 shasum/p' "$1" \
    | sed 's/#.*//' | tr -d ' \t' | sed '/^$/d'
}
REF=$(fingerprint_recipe "$PRECOMMIT")
[ -n "$REF" ] && ok || bad "could not extract the fingerprint recipe from precommit.sh"
for g in claude codex agy; do
  if [ "$(fingerprint_recipe "$ROOT/hooks/$g/stop-guard.sh")" = "$REF" ]; then
    ok
  else
    bad "$g/stop-guard.sh fingerprint drifted from precommit.sh"
  fi
done

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
