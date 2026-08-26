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

# ── Laravel: resolve the toolchain, never assume pint + host php ──────────────
#
# Written after 2026-08-24, when the laravel arm met a repo that lints with phpcs
# and runs entirely in Docker. `./vendor/bin/pint` failed at second zero, the
# receipt went FAIL, and stop-guard then blocked every stop for the rest of the
# session with no reachable fix. These assert the rules that removed that dead
# end — not the shape of the output.

# A laravel fixture: artisan + a fake php on PATH, so the runner resolves to
# "host php" and the tests stay hermetic (no docker, no real PHP).
new_laravel_repo() {
  local d
  d=$(new_repo "$1")
  printf '#!/bin/sh\nexit 0\n' > "$d/artisan"
  mkdir -p "$d/bin" "$d/vendor/bin"
  # Fake php: records its argv so a test can prove `artisan test` was reached.
  printf '#!/bin/sh\necho "php $*" >> "%s/php.log"\nexit 0\n' "$d" > "$d/bin/php"
  chmod +x "$d/bin/php"
  printf '%s' "$d"
}

# $1=dir $2=exit code, $3.. = CSV rows after the header. Records argv so the
# scoping rule can be checked. Rows must not contain single quotes.
fake_phpcs() {
  local d="$1" rc="$2" r
  shift 2
  {
    printf '#!/bin/sh\n'
    printf 'for a in "$@"; do echo "$a" >> "%s/phpcs.argv"; done\n' "$d"
    printf 'echo "File,Line,Column,Type,Message,Source,Severity,Fixable"\n'
    for r in "$@"; do printf "echo '%s'\n" "$r"; done
    printf 'exit %s\n' "$rc"
  } > "$d/vendor/bin/phpcs"
  chmod +x "$d/vendor/bin/phpcs"
}

# Emits something that is not a CSV report at all — a real invocation failure.
fake_phpcs_broken() {
  printf '#!/bin/sh\necho "ERROR: the standard \\"nope\\" is not installed"\nexit 3\n' \
    > "$1/vendor/bin/phpcs"
  chmod +x "$1/vendor/bin/phpcs"
}

ruleset() { printf '<?xml version="1.0"?><ruleset name="p"/>\n' > "$1/phpcs.xml"; }

run_laravel() {
  local d="$1"
  OUT=$(cd "$d" && PATH="$d/bin:$PATH" env -u DOTAI_PRECOMMIT_DISPATCHED \
        -u PRECOMMIT_PHP_RUNNER ENABLE_LSP_TOOL=0 bash "$PRECOMMIT" 2>&1)
  RC=$?
}

# phpcs is used when there is no pint — the case that used to be an instant FAIL.
D=$(new_laravel_repo laravel-phpcs)
ruleset "$D"
fake_phpcs "$D" 2 '"src.php",2,1,warning,"Usage of ELSE IF is discouraged",X,5,1'
printf '<?php\n// touched\n' > "$D/src.php"
run_laravel "$D"
[ "$RC" -eq 0 ] && ok || bad "laravel+phpcs should pass, got rc=$RC: $OUT"
printf '%s' "$OUT" | grep -q 'Linter: phpcs' && ok \
  || bad "should name phpcs as the resolved linter: $OUT"
[ "$(receipt_field "$D" mode)" = "laravel" ] && ok \
  || bad "phpcs repo must stay mode=laravel, not fall back to generic"
grep -q 'artisan test' "$D/php.log" 2>/dev/null && ok \
  || bad "the test step must still run after lint"
printf '%s' "$OUT" | grep -q '1 warning' && ok \
  || bad "warning count must be surfaced on the PASS path: $OUT"

# The rule the real run exposed: an ERROR on a line the change never touched must
# not gate. phpcs lints whole files, so a three-line edit to a legacy file
# reports that file's pre-existing violations too.
D=$(new_laravel_repo laravel-legacy-error)
ruleset "$D"
fake_phpcs "$D" 2 '"legacy.php",9,1,error,"The closing brace must go on the next line",X,5,1'
printf '<?php\n// l2\n// l3\n// l4\n// l5\n// l6\n// l7\n// l8\n// l9\n' > "$D/legacy.php"
git -C "$D" add -A && git -C "$D" commit -qm base
# Touch line 2 only; the reported error is on line 9.
printf '<?php\n// CHANGED\n// l3\n// l4\n// l5\n// l6\n// l7\n// l8\n// l9\n' > "$D/legacy.php"
run_laravel "$D"
[ "$RC" -eq 0 ] && ok || bad "an error on an untouched line must not gate: $OUT"
printf '%s' "$OUT" | grep -q 'change did not touch' && ok \
  || bad "the non-gated error must still be reported: $OUT"

# ...but an error on a line the change DID add gates, and the suite must not run.
D=$(new_laravel_repo laravel-own-error)
ruleset "$D"
fake_phpcs "$D" 2 '"src.php",2,1,error,"Expected 1 space after IF keyword",X,5,1'
printf '<?php\nif(true){}\n' > "$D/src.php"
run_laravel "$D"
[ "$RC" -ne 0 ] && ok || bad "an error on an added line must fail the gate: $OUT"
[ "$(receipt_field "$D" status)" = "FAIL" ] && ok || bad "error run must write status=FAIL"
[ ! -f "$D/php.log" ] && ok || bad "artisan test must not run after lint failed"

# A real invocation failure is never mistaken for "no findings".
D=$(new_laravel_repo laravel-phpcs-broken)
ruleset "$D"
fake_phpcs_broken "$D"
printf '<?php\n// x\n' > "$D/src.php"
run_laravel "$D"
[ "$RC" -ne 0 ] && ok || bad "a phpcs that cannot run must fail the gate: $OUT"
printf '%s' "$OUT" | grep -q 'invocation failed' && ok \
  || bad "should say the invocation failed, not report zero findings: $OUT"

# Only the pending .php files, never the whole repo.
D=$(new_laravel_repo laravel-scope)
ruleset "$D"
fake_phpcs "$D" 0
printf '<?php\n// committed, untouched\n' > "$D/old.php"
git -C "$D" add -A && git -C "$D" commit -qm base
printf '<?php\n// pending\n' > "$D/new.php"
run_laravel "$D"
grep -qx 'new.php' "$D/phpcs.argv" && ok || bad "pending file should be linted"
grep -qx 'old.php' "$D/phpcs.argv" && bad "untouched committed file must not be linted" || ok

# pint wins when both are available — it is the Laravel default.
D=$(new_laravel_repo laravel-pint-first)
ruleset "$D"
fake_phpcs "$D" 2 '"src.php",2,1,error,"would fail",X,5,1'
printf '#!/bin/sh\nexit 0\n' > "$D/vendor/bin/pint"; chmod +x "$D/vendor/bin/pint"
printf '<?php\n// x\n' > "$D/src.php"
run_laravel "$D"
[ "$RC" -eq 0 ] && ok || bad "pint should be preferred over a failing phpcs: $OUT"
printf '%s' "$OUT" | grep -q 'Linter: pint' && ok || bad "should name pint: $OUT"

# No linter at all is a hard FAIL naming both candidates — not a quiet pass, and
# not a fall-through to generic mode.
D=$(new_laravel_repo laravel-no-linter)
printf '<?php\n// x\n' > "$D/src.php"
run_laravel "$D"
[ "$RC" -ne 0 ] && ok || bad "a laravel repo with no linter must not pass"
printf '%s' "$OUT" | grep -q 'pint' && printf '%s' "$OUT" | grep -q 'phpcs' && ok \
  || bad "the failure must name both linter candidates: $OUT"

# PRECOMMIT_PHP_RUNNER overrides everything, including a usable host php.
D=$(new_laravel_repo laravel-runner-override)
ruleset "$D"
fake_phpcs "$D" 0
printf '<?php\n// x\n' > "$D/src.php"
printf '#!/bin/sh\necho "prefix $*" >> "%s/prefix.log"\nexec "$@"\n' "$D" > "$D/bin/wrap"
chmod +x "$D/bin/wrap"
OUT=$(cd "$D" && PATH="$D/bin:$PATH" env -u DOTAI_PRECOMMIT_DISPATCHED \
      ENABLE_LSP_TOOL=0 PRECOMMIT_PHP_RUNNER="wrap" bash "$PRECOMMIT" 2>&1)
RC=$?
[ "$RC" -eq 0 ] && ok || bad "runner override should pass: $OUT"
printf '%s' "$OUT" | grep -q 'PRECOMMIT_PHP_RUNNER' && ok \
  || bad "should report that the runner came from the override: $OUT"
grep -q 'prefix' "$D/prefix.log" 2>/dev/null && ok \
  || bad "the override prefix must actually wrap the commands"

# A project pins its runner in .claude/precommit.env, and — unlike a project
# *pipeline* — it counts even untracked, because a runner cannot declare PASS.
D=$(new_laravel_repo laravel-project-env)
ruleset "$D"
fake_phpcs "$D" 0
printf '<?php\n// x\n' > "$D/src.php"
printf '#!/bin/sh\necho "wrapped $*" >> "%s/prefix.log"\nexec "$@"\n' "$D" > "$D/bin/wrap"
chmod +x "$D/bin/wrap"
mkdir -p "$D/.claude"
printf 'PRECOMMIT_PHP_RUNNER=wrap\n' > "$D/.claude/precommit.env"
run_laravel "$D"
[ "$RC" -eq 0 ] && ok || bad "project precommit.env runner should pass: $OUT"
printf '%s' "$OUT" | grep -q 'precommit.env' && ok \
  || bad "should report the runner came from .claude/precommit.env: $OUT"
grep -q 'wrapped' "$D/prefix.log" 2>/dev/null && ok \
  || bad "the pinned prefix must actually wrap the commands"

# The env var still wins over the file, so a one-off override stays possible.
printf '#!/bin/sh\necho "env-wins $*" >> "%s/envwins.log"\nexec "$@"\n' "$D" > "$D/bin/wrap2"
chmod +x "$D/bin/wrap2"
OUT=$(cd "$D" && PATH="$D/bin:$PATH" env -u DOTAI_PRECOMMIT_DISPATCHED \
      ENABLE_LSP_TOOL=0 PRECOMMIT_PHP_RUNNER="wrap2" bash "$PRECOMMIT" 2>&1)
[ -f "$D/envwins.log" ] && ok || bad "PRECOMMIT_PHP_RUNNER must take precedence over the file"

# The file is config, not code: it must not be sourced.
D=$(new_laravel_repo laravel-env-not-sourced)
ruleset "$D"
fake_phpcs "$D" 0
printf '<?php\n// x\n' > "$D/src.php"
mkdir -p "$D/.claude"
printf 'touch %s/PWNED\nPRECOMMIT_PHP_RUNNER=\n' "$D" > "$D/.claude/precommit.env"
run_laravel "$D"
[ ! -f "$D/PWNED" ] && ok || bad ".claude/precommit.env must never be executed"

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

# ── Node mode: the runner and the script names come from the repo ─────────────
#
# Added 2026-08-26. The node/vue branch had NO coverage, which is how three
# hardcoded `yarn …` lines survived: on an npm-only repo /precommit died at
# second zero with "yarn: command not found", and on a repo whose script is
# named `test` (not `test:unit`) it died on a missing script. Both wrote FAIL to
# the receipt, so stop-guard refused the stop — for a tree nothing had examined.
# These assert the rule, not the current spelling: the runner is *detected*, and
# only *declared* scripts run.

node_repo() {          # $1 = fixture name, $2 = lockfile, $3 = scripts JSON body
  local d; d=$(new_repo "$1")
  printf '{"name":"fixture","scripts":{%s}}\n' "$3" > "$d/package.json"
  [ -n "$2" ] && printf '{}\n' > "$d/$2"
  printf '%s' "$d"
}

# npm-only repo, scripts named `build`/`test` — the exact shape that used to die.
D=$(node_repo node-npm package-lock.json '"build":"true","test":"true"')
run_precommit "$D"
[ "$RC" -eq 0 ] && ok || bad "npm repo should pass, got $RC: $OUT"
grep -Fq 'PRECOMMIT_MODE=node' <<< "$OUT" && ok || bad "npm repo: mode should be node"
grep -Fq 'Runner: npm (from package-lock.json)' <<< "$OUT" && ok \
  || bad "npm repo must name the runner and where it was detected: $OUT"
grep -Fq 'yarn' <<< "$OUT" && bad "npm repo must not mention yarn: $OUT" || ok
# The step labels carry the script name: a PASS that does not say what ran is
# the same claim as "something ran somewhere".
grep -Eq '✅ build \(build\)' <<< "$OUT" && ok || bad "build step should name its script: $OUT"
grep -Eq '✅ test \(test\)'   <<< "$OUT" && ok || bad "test step should name its script: $OUT"

# `lint:fix` absent, `typecheck` present → the fallback ladder is used, not skipped.
D=$(node_repo node-typecheck package-lock.json '"typecheck":"true","build":"true","test":"true"')
run_precommit "$D"
[ "$RC" -eq 0 ] && ok || bad "typecheck fallback should pass, got $RC: $OUT"
grep -Eq '✅ lint \(typecheck\)' <<< "$OUT" && ok \
  || bad "with no lint:fix/lint, typecheck should serve as the lint step: $OUT"

# No lint-shaped script at all → the other two still gate, and the header says so.
D=$(node_repo node-nolint package-lock.json '"build":"true","test":"true"')
run_precommit "$D"
[ "$RC" -eq 0 ] && ok || bad "missing lint script should not fail the run: $OUT"
grep -Fq 'lint=(none declared)' <<< "$OUT" && ok \
  || bad "a script that does not exist must be reported, not silently dropped: $OUT"

# Neither build nor test → degrade to generic, NOT a FAIL. A FAIL here is
# unclearable (no edit to the repo makes a missing test script appear), so
# stop-guard would refuse every stop forever — the 2026-08-21 trap. What the run
# must NOT do is claim a node-mode PASS for a tree it never built or tested.
D=$(node_repo node-nogate package-lock.json '"lint":"true"')
run_precommit "$D"
[ "$RC" -eq 0 ] && ok || bad "no-gate repo must not be an unclearable FAIL: $OUT"
grep -Fq 'PRECOMMIT_MODE=generic' <<< "$OUT" && ok \
  || bad "a run that built and tested nothing must record mode=generic, not node: $OUT"
grep -Fq 'no build ran, no tests ran' <<< "$OUT" && ok \
  || bad "no-gate PASS must state that nothing was built or tested: $OUT"
grep -Fq 'declares neither a build nor a test script' <<< "$OUT" && ok \
  || bad "no-gate repo must say why it fell back: $OUT"
[ "$(receipt_field "$D" mode)" = generic ] && ok \
  || bad "no-gate repo: receipt mode should be generic, got $(receipt_field "$D" mode)"
# The lint script it *does* declare must not be silently promoted into a PASS
# that looks like a real gate.
grep -Eq '✅ lint' <<< "$OUT" && bad "no-gate repo should not run lint as if it gated: $OUT" || ok
grep -Fq '✅ secret_scan' <<< "$OUT" && ok || bad "no-gate repo should run the generic checks: $OUT"

# Lockfile drives the choice — asserted on the header, which is printed before
# any step, so this holds whether or not yarn is installed on this machine.
D=$(node_repo node-yarn yarn.lock '"build":"true","test":"true"')
run_precommit "$D"
grep -Fq 'Runner: yarn (from yarn.lock)' <<< "$OUT" && ok \
  || bad "yarn.lock should select yarn: $OUT"

# vite.config.* → stack is vue, but the same resolution applies.
D=$(node_repo node-vite package-lock.json '"build":"true","test:unit":"true"')
printf 'export default {}\n' > "$D/vite.config.ts"
run_precommit "$D"
[ "$RC" -eq 0 ] && ok || bad "vue repo should pass, got $RC: $OUT"
grep -Fq 'PRECOMMIT_MODE=vue' <<< "$OUT" && ok || bad "vite.config.ts should detect vue"
grep -Eq '✅ test \(test:unit\)' <<< "$OUT" && ok \
  || bad "test:unit should win over test when both could apply: $OUT"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
