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
  rm -f /tmp/dotai_foreign_test-* /tmp/dotai_foreign_codex_test-* /tmp/dotai_foreign_agy_test-*
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

# Fixtures are JSONL assistant entries, as the real transcript is: the Claude
# guard reads markers from the conversation's own text blocks only (see (k7)),
# so a bare-text fixture would not be read.
T_NONE=$(mktranscript '{"type":"assistant","message":{"content":[{"type":"text","text":"about to edit"}]}}')
T_PASS=$(mktranscript '{"type":"assistant","message":{"content":[{"type":"text","text":"reference_file: app/Foo.php\nGROUNDING_STATUS=PASS"}]}}')
T_SKIP=$(mktranscript '{"type":"assistant","message":{"content":[{"type":"text","text":"GROUNDING_STATUS=SKIP reason=typo fix no logic change"}]}}')

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

# ── Cross-repo: the FILE's repository decides, not cwd ───────────────────────
#
# 2026-10-05: nxl-shipping-server MR !891 was built from an nxl-shipping-client
# session, and every gate waved the server files through as "outside the
# working tree". Blocking cross-repo edits was rejected (one feature spans
# frontend and backend), so instead: a foreign file is gated like any other,
# declared by how it is reached from cwd (../other/…) or by absolute path, and
# the FIRST edit into that repo is refused once with the repo's own rules.
FOREIGN=$(mkrepo feature/other)
FOREIGN_P=$(cd "$FOREIGN" && pwd -P)
FB=$(basename "$FOREIGN")
printf '# other repo rules\nNEVER_USE_APP_HELPER\n' > "$FOREIGN/CLAUDE.md"
# `\\n` here is JSON's \n, i.e. a real newline once decoded — as in a real
# transcript. These two fixtures used `\\\\n` (a literal backslash-n) until
# 2026-10-31; the old match-anywhere extraction happened to tolerate that, and
# line-anchored declarations (k9–k12) correctly do not.
T_XREPO=$(mktranscript "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"scope_files: src/*.php\\nscope_files: ../$FB/app/*.php\\nGROUNDING_STATUS=PASS\"}]}}")

echo "  ── cross-repo"
# (k1) first edit into the foreign repo: refused once, carrying its rules
json=$(printf '{"transcript_path":"%s","tool_input":{"file_path":"%s"},"session_id":"%s"}' \
  "$T_XREPO" "$FOREIGN/app/x.php" "test-k1")
msg=$(cd "$FEAT" && echo "$json" | bash "$HOOK" 2>&1 >/dev/null); code=$?
[[ "$code" == 2 ]] && { echo "  ✅ (k1) first foreign edit -> exit 2 (entry brief)"; PASS=$((PASS+1)); } \
  || { echo "  ❌ (k1) first foreign edit should be refused once (exit $code)"; FAIL=$((FAIL+1)); }
grep -Fq 'NEVER_USE_APP_HELPER' <<< "$msg" && { echo "  ✅ (k1) brief carries the foreign CLAUDE.md"; PASS=$((PASS+1)); } \
  || { echo "  ❌ (k1) brief lacks the foreign CLAUDE.md: $msg"; FAIL=$((FAIL+1)); }
grep -Fq "$FOREIGN_P" <<< "$msg" && { echo "  ✅ (k1) brief names the foreign repo"; PASS=$((PASS+1)); } \
  || { echo "  ❌ (k1) brief does not name the repo: $msg"; FAIL=$((FAIL+1)); }
grep -Fq "scope_files: ../$FB/app/x.php" <<< "$msg" && { echo "  ✅ (k1) brief shows the cwd-relative declaration form"; PASS=$((PASS+1)); } \
  || { echo "  ❌ (k1) brief does not show how to declare the file: $msg"; FAIL=$((FAIL+1)); }
# (k2) the retry is not held by the brief
run "(k2) same session, retry -> exit 0"          "$FEAT" "$T_XREPO" "$FOREIGN/app/x.php" "test-k1" 0
# (k3) …but the scope still binds foreign files
json=$(printf '{"transcript_path":"%s","tool_input":{"file_path":"%s"},"session_id":"%s"}' \
  "$T_XREPO" "$FOREIGN/lib/y.php" "test-k1")
msg=$(cd "$FEAT" && echo "$json" | bash "$HOOK" 2>&1 >/dev/null); code=$?
[[ "$code" == 2 ]] && { echo "  ✅ (k3) foreign file out of scope -> exit 2"; PASS=$((PASS+1)); } \
  || { echo "  ❌ (k3) foreign file out of scope should block (exit $code)"; FAIL=$((FAIL+1)); }
grep -Fq "../$FB/lib/y.php" <<< "$msg" && { echo "  ✅ (k3) block names the file as reached from cwd"; PASS=$((PASS+1)); } \
  || { echo "  ❌ (k3) block does not name ../$FB/lib/y.php: $msg"; FAIL=$((FAIL+1)); }
# (k4) absolute-path declaration, and the repo's CLAUDE.md already read: no brief
T_XABS=$(mktranscript "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Read\",\"input\":{\"file_path\":\"$FOREIGN_P/CLAUDE.md\"}}]}}
{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"scope_files: $FOREIGN_P/app/z.php\\nGROUNDING_STATUS=PASS\"}]}}")
run "(k4) absolute declaration + CLAUDE.md already read -> exit 0" "$FEAT" "$T_XABS" "$FOREIGN/app/z.php" "test-k4" 0
# (k5) a foreign repo on main is branch-guard's case, not this hook's
FOREIGN_MAIN=$(mkrepo main)
run "(k5) foreign repo on main -> exit 0"         "$FEAT" "$T_XREPO" "$FOREIGN_MAIN/app/x.php" "test-k5" 0
# (k6) a pattern relative to the cwd repo must NOT cover the sibling's tree
T_CWDONLY=$(mktranscript '{"type":"assistant","message":{"content":[{"type":"text","text":"scope_files: app/*.php\nGROUNDING_STATUS=PASS"}]}}')
printf '%s\n' "$FOREIGN_P" > /tmp/dotai_foreign_test-k6   # brief already delivered
run "(k6) cwd-relative pattern does not reach the foreign repo -> exit 2" "$FEAT" "$T_CWDONLY" "$FOREIGN/app/x.php" "test-k6" 2
# (k7) only the conversation's own text declares — a marker quoted inside a
# tool_result (a cat of SKILL.md, or this hook's own block message fed back)
# must satisfy nothing. Observed live 2026-10-05: ~40 junk scope patterns, and
# gate 1 satisfied by the guard's own refusal text.
T_POLLUTED=$(mktranscript '{"type":"user","message":{"content":[{"type":"tool_result","content":"then emit GROUNDING_STATUS=PASS\nscope_files: app/**"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"reading the skill"}]}}')
run "(k7) PASS only inside a tool_result -> exit 2"   "$FEAT" "$T_POLLUTED" "src/x.php" "test-k7" 2
T_POLLUTED2=$(mktranscript '{"type":"assistant","message":{"content":[{"type":"text","text":"scope_files: src/*.php\nGROUNDING_STATUS=PASS"}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"scope_files: app/**"}]}}')
run "(k7) scope quoted in a tool_result does not widen -> exit 2" "$FEAT" "$T_POLLUTED2" "app/x.php" "test-k7b" 2
# (k8) the user's own message counts: that is how a session was unblocked when
# the harness never wrote the assistant's declaration to the transcript.
T_USERDECL=$(mktranscript '{"type":"user","message":{"content":"scope_files: src/*.php\nGROUNDING_STATUS=PASS"}}')
run "(k8) declaration in a user message -> exit 0"    "$FEAT" "$T_USERDECL" "src/x.php" "test-k8" 0

# (k9–k12) a MENTION of a marker is not a declaration. Observed live
# 2026-10-31: an assistant answer that merely discussed this guard —
# "`GROUNDING_STATUS=PASS` 和 `scope_files:` 都是 agent 自己宣告的。再印一行
# `scope_files:` 就能擴大。" — satisfied gate 1 for the session, and gate 2
# cached "` 就能擴大。" as the only declared pattern. A declaration is a line
# of its own; anything mid-sentence or inside inline code is talk about it.
# Exit 2 alone is not enough: before the fix, the prose mention passed gate 1
# and gate 2 then refused on the junk pattern it had cached, so a bare exit-code
# check passed for the wrong reason. Assert it is GATE 1 that refuses.
gate1() {   # $1 name, $2 transcript, $3 file, $4 session
  local json err code
  json=$(printf '{"transcript_path":"%s","tool_input":{"file_path":"%s"},"session_id":"%s"}' "$2" "$3" "$4")
  err=$(cd "$FEAT" && echo "$json" | bash "$HOOK" 2>&1 >/dev/null); code=$?
  if [[ "$code" == 2 ]] && grep -q 'grounding was not done' <<< "$err"; then
    echo "  ✅ $1 (gate 1 refused)"; PASS=$((PASS+1))
  else
    echo "  ❌ $1 (exit $code, not a gate-1 refusal: $(head -1 <<< "$err"))"; FAIL=$((FAIL+1))
  fi
}
T_PROSE=$(mktranscript '{"type":"assistant","message":{"content":[{"type":"text","text":"- `GROUNDING_STATUS=PASS` 和 `scope_files:` 都是 agent 自己宣告的。範圍不夠時，再印一行 `scope_files:` 就能擴大。"}]}}')
gate1 "(k9) PASS mentioned mid-sentence" "$T_PROSE" "src/x.php" "test-k9"
T_PROSE_SKIP=$(mktranscript '{"type":"assistant","message":{"content":[{"type":"text","text":"For a trivial edit you would emit `GROUNDING_STATUS=SKIP reason=typo` instead."}]}}')
gate1 "(k9) SKIP mentioned mid-sentence" "$T_PROSE_SKIP" "src/x.php" "test-k9b"

T_PROSE_SCOPE=$(mktranscript '{"type":"assistant","message":{"content":[{"type":"text","text":"scope_files: src/*.php\nGROUNDING_STATUS=PASS"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"範圍不夠時，再印一行 `scope_files:` 就能擴大。"}]}}')
run "(k10) real declaration still binds -> exit 0"    "$FEAT" "$T_PROSE_SCOPE" "src/x.php" "test-k10" 0
if [[ "$(cat /tmp/dotai_scope_test-k10 2>/dev/null)" == "src/*.php" ]]; then
  echo "  ✅ (k10) prose mention adds no pattern to the scope"; PASS=$((PASS+1))
else
  echo "  ❌ (k10) scope picked up prose: $(tr '\n' '|' < /tmp/dotai_scope_test-k10 2>/dev/null)"; FAIL=$((FAIL+1))
fi

# (k11) a skill's body is injected as a user record with isMeta:true. /ground's
# own SKILL.md carries an example declaration on lines of their own, so merely
# invoking /ground satisfied gate 1 — before any grounding was done.
T_SKILLMETA=$(mktranscript '{"type":"user","isMeta":true,"message":{"content":[{"type":"text","text":"Base directory for this skill: /x/ground\n\nscope_files: app/Services/ReplenishmentService.php\nGROUNDING_STATUS=PASS"}]}}')
gate1 "(k11) declaration only in an injected skill body" "$T_SKILLMETA" "src/x.php" "test-k11"

# (k12) a declaration on its own line still counts when indented.
T_INDENT=$(mktranscript '{"type":"assistant","message":{"content":[{"type":"text","text":"Grounding:\n  scope_files: src/*.php\n  GROUNDING_STATUS=PASS\n"}]}}')
run "(k12) indented standalone declaration -> exit 0" "$FEAT" "$T_INDENT" "src/x.php" "test-k12" 0

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

# (i11–i12) Codex/agy read the RAW transcript, so the guard's own refusal text
# ("…then emit GROUNDING_STATUS=PASS.") landing in a tool result, or a mention
# in prose, satisfied gate 1 there too. Only a marker on a line of its own —
# or at the start of a JSON string — counts.
T_RAW_MENTION=$(mktranscript '{"type":"function_call_output","output":"⛔ First code edit of this session, but grounding was not done.\nas scope_files: lines, then emit GROUNDING_STATUS=PASS.\nFor a genuinely trivial edit, emit: GROUNDING_STATUS=SKIP reason=<why>"}
{"type":"message","role":"assistant","content":[{"type":"output_text","text":"再印一行 `scope_files:` 就能擴大。"}]}')
err=$( (cd "$FEAT" && jq -cn --arg t "$T_RAW_MENTION" --arg c '*** Begin Patch
*** Update File: src/x.php
*** End Patch' '{transcript_path:$t,tool_input:{command:$c},session_id:"test-i11"}' \
  | bash "$ROOT/hooks/codex/grounding-guard.sh" 2>&1 >/dev/null); echo "rc=$?")
[[ "$err" == *"rc=2" ]] && grep -q 'grounding was not done' <<< "$err" \
  && { echo "  ✅ (i11) codex: marker only in refusal text / prose -> gate 1 refuses"; PASS=$((PASS+1)); } \
  || { echo "  ❌ (i11) codex: not a gate-1 refusal: $(head -1 <<< "$err") / ${err##*rc=}"; FAIL=$((FAIL+1)); }
out=$( (cd "$FEAT" && jq -cn --arg t "$T_RAW_MENTION" --arg f "$FEAT/src/x.php" \
    '{toolCall:{name:"write_to_file",args:{TargetFile:$f}},transcriptPath:$t,conversationId:"test-i12"}' \
  | bash "$ROOT/hooks/agy/grounding-guard.sh" 2>/dev/null) )
[[ "$(jq -r '.decision // ""' <<< "$out")" == deny ]] && grep -q 'grounding was not done' <<< "$(jq -r '.reason // ""' <<< "$out")" \
  && { echo "  ✅ (i12) agy: marker only in refusal text / prose -> gate 1 denies"; PASS=$((PASS+1)); } \
  || { echo "  ❌ (i12) agy: not a gate-1 deny: $out"; FAIL=$((FAIL+1)); }

# Cross-repo on the two ports: the first patch/edit into the sibling repo is
# refused once with its rules, the retry passes, and the scope still binds.
codex_x() {   # $1 = name, $2 = patch, $3 = session, $4 = expected exit, $5 = stderr must contain ("" = skip)
  local json code err
  json=$(jq -cn --arg t "$T_XREPO" --arg c "$2" --arg s "$3" \
    '{transcript_path:$t,tool_input:{command:$c},session_id:$s}')
  err=$( (cd "$FEAT" && echo "$json" | bash "$ROOT/hooks/codex/grounding-guard.sh" 2>&1 >/dev/null); echo "rc=$?" )
  code=$(sed -n 's/^rc=//p' <<< "$err" | tail -1)
  if [[ "$code" == "$4" && ( -z "$5" || "$err" == *"$5"* ) ]]; then echo "  ✅ $1 (exit $code)"; PASS=$((PASS+1))
  else echo "  ❌ $1 (got exit $code, expected $4; wanted '$5'): $err"; FAIL=$((FAIL+1)); fi
}
codex_x "(i5) codex: first patch into the foreign repo -> exit 2 with its rules" \
  "*** Begin Patch
*** Update File: ../$FB/app/A.php
*** End Patch" "test-i5" 2 "NEVER_USE_APP_HELPER"
codex_x "(i6) codex: retry -> exit 0" \
  "*** Begin Patch
*** Update File: ../$FB/app/A.php
*** End Patch" "test-i5" 0 ""
codex_x "(i7) codex: foreign target out of scope -> exit 2" \
  "*** Begin Patch
*** Update File: ../$FB/lib/B.php
*** End Patch" "test-i5" 2 "../$FB/lib/B.php"

agy_x() {   # $1 = name, $2 = target, $3 = session, $4 = expected decision, $5 = reason must contain
  local out got reason
  out=$( (cd "$FEAT" && jq -cn --arg t "$T_XREPO" --arg f "$2" --arg s "$3" \
      '{toolCall:{name:"write_to_file",args:{TargetFile:$f}},transcriptPath:$t,conversationId:$s}' \
    | bash "$ROOT/hooks/agy/grounding-guard.sh" 2>/dev/null) )
  got=$(printf '%s' "$out" | jq -r '.decision // "«none»"' 2>/dev/null)
  reason=$(printf '%s' "$out" | jq -r '.reason // ""' 2>/dev/null)
  if [[ "$got" == "$4" && ( -z "$5" || "$reason" == *"$5"* ) ]]; then echo "  ✅ $1 (decision $got)"; PASS=$((PASS+1))
  else echo "  ❌ $1 (got '$got', expected '$4'; wanted '$5'); raw: $out"; FAIL=$((FAIL+1)); fi
}
agy_x "(i8) agy: first edit into the foreign repo -> deny with its rules" "$FOREIGN/app/A.php" "test-i8" deny "NEVER_USE_APP_HELPER"
agy_x "(i9) agy: retry -> allow"                                           "$FOREIGN/app/A.php" "test-i8" allow ""
agy_x "(i10) agy: foreign file out of scope -> deny"                       "$FOREIGN/lib/B.php" "test-i8" deny "../$FB/lib/B.php"

# ── Parity: one scope algorithm, three copies ────────────────────────────────
#
# The helpers are duplicated rather than sourced for the same reason as the
# precommit fingerprint: the three guards install into three different trees, so
# no shared path exists. Drift here is silent — one CLI would accept a pattern
# another refuses — so it is locked textually.
extract_fn() { sed -n "/^$2()/,/^}/p" "$1" | sed 's/#.*//' | tr -d ' \t' | sed '/^$/d'; }
# relpath() is the cross-repo helper (../other/… from cwd); same duplication, same lock.
for fn in extract_scope scope_allows relpath grounding_markers; do
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
