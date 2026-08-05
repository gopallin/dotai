#!/usr/bin/env bash

# agy speaks a different hook contract from Claude/Codex: camelCase JSON on
# stdin, a JSON decision on stdout, and the exit code is ignored. A guard that
# only writes stderr and exits 2 is a no-op there. These tests pin the contract
# so that regression cannot come back silently.
#
# Fixture payloads use the field names observed from live agy hook invocations
# (PreToolUse: toolCall/args/transcriptPath/conversationId/stepIdx;
#  Stop: terminationReason/executionNum/fullyIdle).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "❌ $1" >&2; }

# Asserts the script emits valid JSON whose .decision matches, given a payload.
expect_decision() {
  local label=$1 script=$2 payload=$3 want=$4 cwd=${5:-$TMP} guard=${6:-}
  local out got
  out=$(cd "$cwd" && printf '%s' "$payload" \
        | bash "$ROOT/$script" ${guard:+"$ROOT/$guard"} 2>/dev/null)
  if ! got=$(printf '%s' "$out" | jq -r '.decision // "«none»"' 2>/dev/null); then
    bad "$label: output was not valid JSON: $out"
    return
  fi
  if [ "$got" != "$want" ]; then
    bad "$label: expected decision=$want, got $got (raw: $out)"
    return
  fi
  ok
}

# ── Fixtures ──────────────────────────────────────────────────────────────────

TRANSCRIPT_CLEAN="$TMP/clean.jsonl"
printf '{"role":"user"}\n' > "$TRANSCRIPT_CLEAN"

TRANSCRIPT_EDITED="$TMP/edited.jsonl"
printf '{"toolCall":{"name":"write_to_file"}}\n' > "$TRANSCRIPT_EDITED"

TRANSCRIPT_EDITED_PASS="$TMP/edited-pass.jsonl"
printf '{"toolCall":{"name":"write_to_file"}}\nPRECOMMIT_STATUS=PASS\n' > "$TRANSCRIPT_EDITED_PASS"

TRANSCRIPT_GROUNDED="$TMP/grounded.jsonl"
printf 'GROUNDING_STATUS=PASS\n' > "$TRANSCRIPT_GROUNDED"

stop_payload() {
  jq -cn --arg t "$1" --arg r "${2:-model_stop}" --argjson n "${3:-1}" \
    '{transcriptPath:$t, terminationReason:$r, executionNum:$n, fullyIdle:true,
      conversationId:"c1", workspacePaths:["/tmp"], modelName:"auto"}'
}

# conversationId keys the per-session marker files the guards write under /tmp,
# so it must be unique per run — a fixed id makes the second run of this suite
# see the first run's "already grounded" state and stop denying.
CID="agytest-$$"
pretool_payload() {  # tool, argsJson, transcript
  jq -cn --arg n "$1" --argjson a "$2" --arg t "$3" --arg c "$CID" \
    '{toolCall:{name:$n,args:$a}, transcriptPath:$t, conversationId:$c,
      stepIdx:1, workspacePaths:["/tmp"], modelName:"auto"}'
}
cleanup_markers() { rm -f "/tmp/dotai_grounding_agy_${CID}" "/tmp/dotai_agy_reads_${CID}"; }
cleanup_markers
trap 'rm -rf "$TMP"; cleanup_markers' EXIT

# A feature branch is required for grounding-guard to engage at all.
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
printf 'x\n' > "$REPO/f.txt"; git -C "$REPO" add -A; git -C "$REPO" commit -qm init
git -C "$REPO" checkout -q -b feature/test

# ── stop-guard (Stop event) ───────────────────────────────────────────────────

expect_decision "stop-guard: no edits → allow" \
  hooks/agy/stop-guard.sh "$(stop_payload "$TRANSCRIPT_CLEAN")" allow

expect_decision "stop-guard: edits without PASS → continue (blocks the stop)" \
  hooks/agy/stop-guard.sh "$(stop_payload "$TRANSCRIPT_EDITED")" continue

expect_decision "stop-guard: edits with PRECOMMIT_STATUS=PASS → allow" \
  hooks/agy/stop-guard.sh "$(stop_payload "$TRANSCRIPT_EDITED_PASS")" allow

expect_decision "stop-guard: error termination → allow (never fight an error)" \
  hooks/agy/stop-guard.sh "$(stop_payload "$TRANSCRIPT_EDITED" error)" allow

expect_decision "stop-guard: loop brake at executionNum 3 → allow" \
  hooks/agy/stop-guard.sh "$(stop_payload "$TRANSCRIPT_EDITED" model_stop 3)" allow

# ── grounding-guard (PreToolUse) ──────────────────────────────────────────────

expect_decision "grounding-guard: first code edit, no grounding → deny" \
  hooks/agy/grounding-guard.sh \
  "$(pretool_payload write_to_file '{"TargetFile":"/x/a.php","CodeContent":"x","Overwrite":false}' "$TRANSCRIPT_CLEAN")" \
  deny "$REPO"

expect_decision "grounding-guard: GROUNDING_STATUS=PASS present → allow" \
  hooks/agy/grounding-guard.sh \
  "$(pretool_payload write_to_file '{"TargetFile":"/x/b.php","CodeContent":"x"}' "$TRANSCRIPT_GROUNDED")" \
  allow "$REPO"

expect_decision "grounding-guard: markdown edit → allow" \
  hooks/agy/grounding-guard.sh \
  "$(pretool_payload write_to_file '{"TargetFile":"/x/README.md","CodeContent":"x"}' "$TRANSCRIPT_CLEAN")" \
  allow "$REPO"

# The gate only fires on the FIRST non-doc edit per conversation, and the case
# above already consumed it — reset so this asserts the matcher, not the counter.
cleanup_markers
expect_decision "grounding-guard: replace_file_content also gated (TargetFile arg)" \
  hooks/agy/grounding-guard.sh \
  "$(pretool_payload replace_file_content '{"TargetFile":"/x/c.php","StartLine":1,"EndLine":2,"TargetContent":"a","ReplacementContent":"b"}' "$TRANSCRIPT_CLEAN")" \
  deny "$REPO"

expect_decision "grounding-guard: unrelated tool → allow" \
  hooks/agy/grounding-guard.sh \
  "$(pretool_payload run_command '{"CommandLine":"ls"}' "$TRANSCRIPT_CLEAN")" \
  allow "$REPO"

# ── read-dedup-guard (PreToolUse / view_file) ─────────────────────────────────

CONV="dedup-$$"
dedup_payload() {
  jq -cn --arg n "${2:-view_file}" --argjson a "$1" --arg c "$CONV" \
    '{toolCall:{name:$n,args:$a}, conversationId:$c, stepIdx:1}'
}
rm -f "/tmp/dotai_agy_reads_${CONV}"

expect_decision "read-dedup: first full read → allow" \
  hooks/agy/read-dedup-guard.sh "$(dedup_payload '{"AbsolutePath":"/x/dup.php"}')" allow

expect_decision "read-dedup: second full read of same file → deny" \
  hooks/agy/read-dedup-guard.sh "$(dedup_payload '{"AbsolutePath":"/x/dup.php"}')" deny

expect_decision "read-dedup: ranged re-read → allow (escape hatch)" \
  hooks/agy/read-dedup-guard.sh \
  "$(dedup_payload '{"AbsolutePath":"/x/dup.php","StartLine":10,"EndLine":20}')" allow
rm -f "/tmp/dotai_agy_reads_${CONV}"

# ── conversationId sanitisation ───────────────────────────────────────────────
# conversationId comes from the hook payload and is interpolated into a /tmp
# marker path, so path separators must not survive.
TRAVERSAL="../../../$TMP/pwned"
EVIL=$(jq -cn --arg n view_file --arg c "$TRAVERSAL" \
  '{toolCall:{name:$n,args:{AbsolutePath:"/x/e.php"}}, conversationId:$c, stepIdx:1}')
OUT4=$(printf '%s' "$EVIL" | bash "$ROOT/hooks/agy/read-dedup-guard.sh" 2>/dev/null)
if printf '%s' "$OUT4" | jq -e '.decision == "allow"' >/dev/null 2>&1; then ok; else
  bad "read-dedup: traversal conversationId should still return a valid decision, got: $OUT4"
fi
if [ ! -e "$TMP/pwned" ] && [ ! -e "$TMP/dotai_agy_reads_$TMP/pwned" ]; then ok; else
  bad "read-dedup: conversationId traversal escaped the /tmp marker path"
fi
rm -f /tmp/dotai_agy_reads_*TMPpwned* 2>/dev/null

# ── shared-guard-adapter (exit code → JSON decision) ──────────────────────────

MAINREPO="$TMP/repo-main"
mkdir -p "$MAINREPO"
git -C "$MAINREPO" init -q -b main
git -C "$MAINREPO" config user.email t@t; git -C "$MAINREPO" config user.name t
printf 'x\n' > "$MAINREPO/f.txt"; git -C "$MAINREPO" add -A; git -C "$MAINREPO" commit -qm init

expect_decision "adapter: branch-guard denies git commit on main" \
  hooks/agy/shared-guard-adapter.sh \
  "$(pretool_payload run_command '{"CommandLine":"git commit -m x"}' "$TRANSCRIPT_CLEAN")" \
  deny "$MAINREPO" hooks/shared/branch-guard.sh

expect_decision "adapter: git checkout allowed on main (escape hatch)" \
  hooks/agy/shared-guard-adapter.sh \
  "$(pretool_payload run_command '{"CommandLine":"git checkout -b feature/x"}' "$TRANSCRIPT_CLEAN")" \
  allow "$MAINREPO" hooks/shared/branch-guard.sh

expect_decision "adapter: feature branch allows commit" \
  hooks/agy/shared-guard-adapter.sh \
  "$(pretool_payload run_command '{"CommandLine":"git commit -m x"}' "$TRANSCRIPT_CLEAN")" \
  allow "$REPO" hooks/shared/branch-guard.sh

expect_decision "adapter: glab-guard denies glab" \
  hooks/agy/shared-guard-adapter.sh \
  "$(pretool_payload run_command '{"CommandLine":"glab mr list"}' "$TRANSCRIPT_CLEAN")" \
  deny "$REPO" hooks/shared/glab-guard.sh

# branch-guard fails OPEN (with a warning on stderr) when there is no shell
# command to inspect — see hooks/shared/branch-guard.sh lines 79-88. Registering
# it on agy's file-edit tools would therefore turn every edit into a noisy
# {"decision":"allow","reason":"…fail-open…"} instead of a block, so it must stay
# scoped to run_command until that shared guard handles the file-edit case.
BG_MATCHERS=$(jq -r '.["dotai-branch-guard"].PreToolUse[].matcher' "$ROOT/hooks/agy/hooks.json")
if [ "$BG_MATCHERS" = "run_command" ]; then ok; else
  bad "hooks.json: dotai-branch-guard matcher should be run_command only, got: $BG_MATCHERS"
fi

OUT3=$(cd "$MAINREPO" && printf '%s' \
  "$(pretool_payload write_to_file '{"TargetFile":"/x/a.php","CodeContent":"x","Overwrite":false}' "$TRANSCRIPT_CLEAN")" \
  | bash "$ROOT/hooks/agy/shared-guard-adapter.sh" "$ROOT/hooks/shared/branch-guard.sh" 2>/dev/null)
if printf '%s' "$OUT3" | jq -e '.reason // "" | test("fail-open")' >/dev/null 2>&1; then
  ok   # documents the known fail-open, which is why the matcher above excludes edits
else
  bad "adapter: expected branch-guard's fail-open warning to surface as a reason, got: $OUT3"
fi

# ── context-budget-guard (PreInvocation → injectSteps, not stderr) ────────────

BIG="$TMP/big.jsonl"
awk 'BEGIN { for (i=0;i<3200;i++) print "{\"x\":1}" }' > "$BIG"
CONV2="ctx-$$"
rm -f "/tmp/dotai_ctxband_agy_${CONV2}"
CTX_PAYLOAD=$(jq -cn --arg t "$BIG" --arg c "$CONV2" \
  '{transcriptPath:$t, conversationId:$c, invocationNum:3}')

OUT=$(printf '%s' "$CTX_PAYLOAD" | bash "$ROOT/hooks/agy/context-budget-guard.sh" 2>/dev/null)
if printf '%s' "$OUT" | jq -e '.injectSteps[0].ephemeralMessage | test("advisory")' >/dev/null 2>&1; then
  ok
else
  bad "context-budget-guard: large transcript should inject an ephemeralMessage, got: $OUT"
fi

# Second call in the same band must stay silent, or the advice repeats every turn.
OUT2=$(printf '%s' "$CTX_PAYLOAD" | bash "$ROOT/hooks/agy/context-budget-guard.sh" 2>/dev/null)
if [ "$(printf '%s' "$OUT2" | jq -c '.' 2>/dev/null)" = '{}' ]; then
  ok
else
  bad "context-budget-guard: same band should stay quiet, got: $OUT2"
fi
rm -f "/tmp/dotai_ctxband_agy_${CONV2}"

# ── hooks.json shape ──────────────────────────────────────────────────────────

HJ="$ROOT/hooks/agy/hooks.json"

# Named hooks are top-level keys; a {"hooks":{...}} wrapper is the Claude shape
# and would make every entry inert.
if jq -e 'has("hooks") | not' "$HJ" >/dev/null 2>&1; then ok; else
  bad "hooks.json: must use agy's named-hook shape, not a {\"hooks\":...} wrapper"
fi

# Only events agy actually supports.
BADEVENTS=$(jq -r '[.[] | keys[] | select(. != "enabled")]
  | map(select(. as $e | ["PreToolUse","PostToolUse","PreInvocation","PostInvocation","Stop"]
  | index($e) | not)) | join(",")' "$HJ")
if [ -z "$BADEVENTS" ]; then ok; else
  bad "hooks.json: unsupported event(s): $BADEVENTS (AfterAgent/BeforeTool do not exist in agy)"
fi

# Matchers must reference agy's real tool names.
if jq -e '[.[] | .PreToolUse[]?.matcher] | join("|") |
          (test("write_to_file") and test("view_file") and test("run_command"))' "$HJ" >/dev/null 2>&1; then
  ok
else
  bad "hooks.json: PreToolUse matchers must use agy tool names (write_to_file/view_file/run_command)"
fi

if jq -e '[.[] | .PreToolUse[]?.matcher] | join("|") |
          (test("write_file\\b") or test("edit_file") or test("create_file") or test("read_file")) | not' "$HJ" >/dev/null 2>&1; then
  ok
else
  bad "hooks.json: matchers still reference tool names agy does not have"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
