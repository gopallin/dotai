#!/usr/bin/env bash
#
# grounding-guard.test.sh
# Unit tests for hooks/claude/grounding-guard.sh, driven by synthetic
# transcript JSONL + crafted PreToolUse stdin JSON.
# Covers cases (a)-(g) from plan-grounding-guard.md §5.1, plus the (h)
# scope-contract series and cross-CLI parity of the scope helpers.
#
# Run:  bash tests/grounding-guard.test.sh

set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/claude/grounding-guard.sh"
TMP=$(mktemp -d)
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TMP"
  rm -f /tmp/dotai_grounding_test-* /tmp/dotai_scope_test-*
  rm -f /tmp/dotai_grounding_codex_test-* /tmp/dotai_scope_codex_test-*
  rm -f /tmp/dotai_grounding_agy_test-* /tmp/dotai_scope_agy_test-*
}
trap cleanup EXIT

# Build an isolated git repo on a given branch.
mkrepo() { # $1 = branch name
  local d="$TMP/repo_$1_$RANDOM"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" commit -q --allow-empty -m init
  git -C "$d" checkout -q -B "$1"
  echo "$d"
}

mktranscript() { # $1 = content; writes file, echoes path
  local f="$TMP/transcript_$RANDOM.jsonl"
  printf '%s\n' "$1" > "$f"
  echo "$f"
}

# Direct the skip log to a tmp file so tests never touch ~/.claude.
# The real guard reads DOTAI_SKIP_LOG if set, falling back to ~/.claude/...
SKIP_LOG="$TMP/grounding-skip.log"
export DOTAI_SKIP_LOG="$SKIP_LOG"

# run <name> <cwd> <transcript_path> <file_path> <session_id> <expected_exit>
run() {
  local name="$1" cwd="$2" tpath="$3" fpath="$4" sid="$5" expect="$6"
  local json
  json=$(printf '{"transcript_path":"%s","tool_input":{"file_path":"%s"},"session_id":"%s"}' \
    "$tpath" "$fpath" "$sid")
  local out code
  out=$(cd "$cwd" && echo "$json" | bash "$HOOK" 2>/dev/null)
  code=$?
  if [[ "$code" == "$expect" ]]; then
    echo "  ✅ $name (exit $code)"
    PASS=$((PASS+1))
  else
    echo "  ❌ $name (got exit $code, expected $expect)"
    FAIL=$((FAIL+1))
  fi
}

FEAT=$(mkrepo feature/test)
MAIN=$(mkrepo main)
NONREPO="$TMP/notarepo"; mkdir -p "$NONREPO"

T_NONE=$(mktranscript '{"type":"assistant","text":"about to edit"}')
T_PASS=$(mktranscript 'reference_file: app/Foo.php
GROUNDING_STATUS=PASS')
T_SKIP=$(mktranscript 'GROUNDING_STATUS=SKIP reason=typo fix no logic change')

echo "grounding-guard.sh tests"

# (a) first non-doc edit, no marker -> block
run "(a) first edit, no marker -> exit 2" "$FEAT" "$T_NONE" "src/x.php" "test-a" 2

# (b) first non-doc edit, PASS marker -> allow
run "(b) first edit, PASS -> exit 0" "$FEAT" "$T_PASS" "src/x.php" "test-b" 0

# (c) first edit is .md -> allow (doc exempt)
run "(c) .md edit -> exit 0" "$FEAT" "$T_NONE" "README.md" "test-c" 0

# (d) SKIP marker -> allow + log
run "(d) SKIP -> exit 0" "$FEAT" "$T_SKIP" "src/x.php" "test-d" 0
if grep -q 'typo fix no logic change' "$SKIP_LOG" 2>/dev/null; then
  echo "  ✅ (d) skip reason logged to tmp log"; PASS=$((PASS+1))
else
  echo "  ❌ (d) skip reason NOT logged to $SKIP_LOG"; FAIL=$((FAIL+1))
fi
if grep -q 'test-d' "$SKIP_LOG" 2>/dev/null; then
  echo "  ✅ (d) session_id present in log entry"; PASS=$((PASS+1))
else
  echo "  ❌ (d) session_id missing from log entry"; FAIL=$((FAIL+1))
fi

# (e) second code edit (counter preset to 1) -> allow without marker
echo "1" > "/tmp/dotai_grounding_test-e"
run "(e) second edit (counter=1) -> exit 0" "$FEAT" "$T_NONE" "src/y.php" "test-e" 0

# (f) on main -> allow (avoid deadlock with branch-guard)
run "(f) main branch -> exit 0" "$MAIN" "$T_NONE" "src/x.php" "test-f" 0

# (g1) transcript path missing -> allow (fail open)
run "(g1) no transcript -> exit 0" "$FEAT" "$TMP/nope.jsonl" "src/x.php" "test-g1" 0

# (g2) not a git repo -> allow
run "(g2) non-repo -> exit 0" "$NONREPO" "$T_NONE" "src/x.php" "test-g2" 0

# ── Scope contract (gate 2) ──────────────────────────────────────────────────
#
# The declaration is `scope_files:` lines emitted with the PASS. These assert
# the RULE — an edit inside the declared blast radius proceeds, one outside is
# refused until the contract is widened out loud — not the current wording.
#
# Transcript lines are JSON in real life, so the fixture keeps the two-character
# \n escape the guard has to split on; a fixture with real newlines would pass
# while the guard failed in production.
T_SCOPE=$(mktranscript '{"type":"assistant","message":{"content":[{"type":"text","text":"reference_file: app/S.php\nscope_files: app/Services/*.php\nscope_files: resources/js/\nscope_files: src/exact.php\nGROUNDING_STATUS=PASS"}]}}')

echo "  ── scope contract"
run "(h1) in scope, exact path -> exit 0"   "$FEAT" "$T_SCOPE" "src/exact.php"            "test-h1" 0
run "(h2) in scope, glob -> exit 0"         "$FEAT" "$T_SCOPE" "app/Services/Label.php"   "test-h2" 0
run "(h3) in scope, subtree -> exit 0"      "$FEAT" "$T_SCOPE" "resources/js/pages/a.vue" "test-h3" 0
run "(h4) OUT of scope -> exit 2"           "$FEAT" "$T_SCOPE" "app/Http/Controllers/C.php" "test-h4" 2

# The block must name the file and print the contract, or the reader cannot tell
# whether to widen the scope or drop the edit.
json=$(printf '{"transcript_path":"%s","tool_input":{"file_path":"%s"},"session_id":"%s"}' \
  "$T_SCOPE" "app/Http/Controllers/C.php" "test-h5")
msg=$(cd "$FEAT" && echo "$json" | bash "$HOOK" 2>&1 >/dev/null)
grep -Fq 'app/Http/Controllers/C.php' <<< "$msg" && { echo "  ✅ (h5) block names the file"; PASS=$((PASS+1)); } \
  || { echo "  ❌ (h5) block does not name the file: $msg"; FAIL=$((FAIL+1)); }
grep -Fq 'app/Services/*.php' <<< "$msg" && { echo "  ✅ (h5) block prints the declared scope"; PASS=$((PASS+1)); } \
  || { echo "  ❌ (h5) block omits the declared scope: $msg"; FAIL=$((FAIL+1)); }

# Amendment: a later scope_files line widens the contract. This is the intended
# escape — scope growth becomes explicit in the transcript instead of silent.
T_WIDENED=$(mktranscript '{"type":"assistant","message":{"content":[{"type":"text","text":"scope_files: app/Services/*.php\nGROUNDING_STATUS=PASS"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"widening: the controller must pass the new flag through\nscope_files: app/Http/Controllers/C.php"}]}}')
run "(h6) amended scope -> exit 0"          "$FEAT" "$T_WIDENED" "app/Http/Controllers/C.php" "test-h6" 0

# A stale cache must not outlive the amendment: prime the cache with the narrow
# scope, then check the widened path against the same session.
echo "app/Services/*.php" > /tmp/dotai_scope_test-h7
echo "1" > /tmp/dotai_grounding_test-h7
run "(h7) stale cache re-read -> exit 0"    "$FEAT" "$T_WIDENED" "app/Http/Controllers/C.php" "test-h7" 0

# PASS with no scope_files at all: no constraint. Every /ground output written
# before this field existed must keep working, so this fails OPEN by design.
run "(h8) PASS without scope -> exit 0"         "$FEAT" "$T_PASS"  "anything/at/all.php"       "test-h8" 0

# Docs and out-of-tree writes are exempt even when a scope is declared — they
# cannot enter this branch's diff (same argument branch-guard accepts).
run "(h9) .md ignores scope -> exit 0"      "$FEAT" "$T_SCOPE" "out/of/scope.md"           "test-h9" 0
run "(h10) outside repo -> exit 0"          "$FEAT" "$T_SCOPE" "$TMP/elsewhere/x.php"      "test-h10" 0
run "(h11) .git write -> exit 0"            "$FEAT" "$T_SCOPE" "$FEAT/.git/info/exclude"   "test-h11" 0

# An explicit SKIP declares no scope, so it cannot be used to smuggle one in.
run "(h12) SKIP ignores scope -> exit 0"    "$FEAT" "$T_SKIP"  "app/Http/Controllers/C.php" "test-h12" 0

# ── Cross-CLI: the ports must actually fire ──────────────────────────────────
#
# dotai has shipped inert ports before (complexity-guard read an env var Claude
# Code never sets; the agy guards matched tool names that do not exist), so a
# port is not done until it has been driven with that CLI's own payload shape.
# The scope ALGORITHM is shared verbatim and locked by the parity check below;
# these cases cover the per-CLI plumbing around it.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "  ── cross-CLI ports"

# Codex: apply_patch names its targets in *** Update File: headers, and applies
# whole — so one undeclared target must refuse the entire patch.
codex_run() {   # $1 = name, $2 = patch body, $3 = session, $4 = expected exit
  local json code
  json=$(jq -cn --arg t "$T_SCOPE" --arg c "$2" --arg s "$3" \
    '{transcript_path:$t,tool_input:{command:$c},session_id:$s}')
  (cd "$FEAT" && echo "$json" | bash "$ROOT/hooks/codex/grounding-guard.sh" >/dev/null 2>&1)
  code=$?
  if [[ "$code" == "$4" ]]; then echo "  ✅ $1 (exit $code)"; PASS=$((PASS+1))
  else echo "  ❌ $1 (got exit $code, expected $4)"; FAIL=$((FAIL+1)); fi
}
codex_run "(i1) codex: all targets in scope -> exit 0" \
  '*** Begin Patch
*** Update File: app/Services/A.php
*** End Patch' "test-i1" 0
codex_run "(i2) codex: one target outside -> exit 2" \
  '*** Begin Patch
*** Update File: app/Services/A.php
*** Update File: app/Http/Controllers/C.php
*** End Patch' "test-i2" 2

# agy: exit codes are ignored, so a deny that only sets $? fails OPEN. The
# decision must be in the JSON on stdout.
agy_run() {   # $1 = name, $2 = target file, $3 = session, $4 = expected decision
  local out got
  out=$( (cd "$FEAT" && jq -cn --arg t "$T_SCOPE" --arg f "$2" --arg s "$3" \
      '{toolCall:{name:"write_to_file",args:{TargetFile:$f}},transcriptPath:$t,conversationId:$s}' \
    | bash "$ROOT/hooks/agy/grounding-guard.sh" 2>/dev/null) )
  got=$(printf '%s' "$out" | jq -r '.decision // "«none»"' 2>/dev/null)
  if [[ "$got" == "$4" ]]; then echo "  ✅ $1 (decision $got)"; PASS=$((PASS+1))
  else echo "  ❌ $1 (got '$got', expected '$4'); raw: $out"; FAIL=$((FAIL+1)); fi
}
agy_run "(i3) agy: in scope -> allow"  "$FEAT/app/Services/A.php"      "test-i3" allow
agy_run "(i4) agy: out of scope -> deny" "$FEAT/app/Http/Controllers/C.php" "test-i4" deny

# ── Parity: one scope algorithm, three copies ────────────────────────────────
#
# The helpers are duplicated rather than sourced for the same reason as the
# precommit fingerprint: the three guards install into three different trees, so
# no shared path exists. Drift here is silent — one CLI would accept a pattern
# another refuses — so it is locked textually.
extract_fn() { sed -n "/^$2()/,/^}/p" "$1" | sed 's/#.*//' | tr -d ' \t' | sed '/^$/d'; }
for fn in extract_scope scope_allows; do
  ref=$(extract_fn "$ROOT/hooks/claude/grounding-guard.sh" "$fn")
  if [[ -z "$ref" ]]; then
    echo "  ❌ (j) could not extract $fn() from claude/grounding-guard.sh"; FAIL=$((FAIL+1))
    continue
  fi
  for cli in codex agy; do
    if [[ "$(extract_fn "$ROOT/hooks/$cli/grounding-guard.sh" "$fn")" == "$ref" ]]; then
      echo "  ✅ (j) $cli $fn() matches claude's"; PASS=$((PASS+1))
    else
      echo "  ❌ (j) $cli $fn() drifted from claude's"; FAIL=$((FAIL+1))
    fi
  done
done

echo "─────────────────────────────"
echo "PASS=$PASS  FAIL=$FAIL"
[[ "$FAIL" == 0 ]] && echo "GROUNDING_TEST_STATUS=PASS" || echo "GROUNDING_TEST_STATUS=FAIL"
exit $([[ "$FAIL" == 0 ]] && echo 0 || echo 1)
