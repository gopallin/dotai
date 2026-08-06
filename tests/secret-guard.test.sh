#!/usr/bin/env bash

# Covers the two halves of the credential control added after the 2026-08-06
# incident, where a `security dump-keychain` put a live GitHub PAT into the
# transcript in plaintext and the token had to be revoked.
#
#   shared/secret-guard.sh   PreToolUse  — blocks the wholesale keychain dump
#   claude/secret-redact.sh  PostToolUse — scrubs known token shapes from output
#
# Every credential below is SYNTHETIC. Never paste a real one into a test file:
# the repo is pushed, and a test fixture is as permanent as git history.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$ROOT/hooks/shared/secret-guard.sh"
REDACT="$ROOT/hooks/claude/secret-redact.sh"

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "❌ $1" >&2; }

# ── secret-guard: block / allow ──────────────────────────────────────────────

# want=block → exit 2; want=allow → exit 0.
check() {
  local want=$1 cmd=$2 status
  printf '%s' "$(jq -cn --arg c "$cmd" '{tool_input:{command:$c}}')" \
    | bash "$GUARD" >/dev/null 2>&1
  status=$?
  case "$want" in
    block) [ "$status" -eq 2 ] && { ok; return; } ;;
    allow) [ "$status" -eq 0 ] && { ok; return; } ;;
  esac
  bad "expected $want, got exit $status for: $cmd"
}

check block 'security dump-keychain'
check block 'security dump-keychain | grep svce'
check block 'cd /tmp && security dump-keychain'
check block 'echo hi; security dump-keychain'
check block 'true | security dump-keychain'
check block '  security   dump-keychain'

# Targeted lookups stay allowed — /ship's GitHub fallback reads exactly this, and
# blocking it would break shipping to fix nothing (the value is a single known
# item, not an unbounded dump).
check allow 'security find-generic-password -a github -s ai-agent-github-token -w'
check allow 'security find-generic-password -s ai-agent-gitlab-token'
check allow 'security add-generic-password -a github -s ai-agent-github-token -w'
check allow 'security delete-generic-password -s ai-agent-github-token'

# Merely naming the command in a quoted string is not executing it.
check allow 'grep -rn "dump-keychain" hooks/'
check allow "grep -rn 'security dump-keychain' ."

# Non-Bash payloads / empty input must fail open, not crash the tool loop.
check allow ''
printf '%s' '{}' | bash "$GUARD" >/dev/null 2>&1
[ $? -eq 0 ] && ok || bad "empty tool_input should exit 0"

# ── secret-redact: rewrite / passthrough ─────────────────────────────────────

# Feeds a tool_response through the hook and returns its stdout.
redact() {
  jq -cn --arg s "$1" '{tool_name:"Bash",tool_response:{stdout:$s,stderr:""}}' \
    | bash "$REDACT" 2>/dev/null
}

# want_gone must NOT survive into the hook's stdout; want_tag must appear.
scrub() {
  local label=$1 secret=$2 tag=$3 out
  out=$(redact "leaked value: $secret")
  if printf '%s' "$out" | grep -q "$secret"; then
    bad "$label: secret survived redaction"
  elif ! printf '%s' "$out" | grep -q "$tag"; then
    bad "$label: expected marker $tag missing from output"
  else
    ok
  fi
}

scrub github-pat  'github_pat_11ABCDEFG0aaaaaaaaaaa_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' 'REDACTED:github-fine-grained-pat'
scrub github-ghp  'ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' 'REDACTED:github-token'
scrub gitlab-pat  'glpat-AAAAAAAAAAAAAAAAAAAA'               'REDACTED:gitlab-pat'
scrub anthropic   'sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAA'    'REDACTED:anthropic-key'
scrub aws-key     'AKIAIOSFODNN7EXAMPLE'                     'REDACTED:aws-access-key-id'
scrub slack       'xoxb-1111111111-AAAAAAAAAAAA'             'REDACTED:slack-token'

# The emitted envelope must match the documented PostToolUse contract, or the
# hook is inert in exactly the way that is impossible to notice at runtime.
ENV_OUT=$(redact 'token glpat-AAAAAAAAAAAAAAAAAAAA here')
[ "$(printf '%s' "$ENV_OUT" | jq -r '.hookSpecificOutput.hookEventName')" = "PostToolUse" ] \
  && ok || bad "hookEventName must be PostToolUse"
[ "$(printf '%s' "$ENV_OUT" | jq -r '.hookSpecificOutput.updatedToolOutput | type')" = "object" ] \
  && ok || bad "updatedToolOutput must preserve the tool_response shape (object)"
[ -n "$(printf '%s' "$ENV_OUT" | jq -r '.systemMessage // empty')" ] \
  && ok || bad "a redaction must surface a systemMessage to the user"

# Clean output must pass through untouched. Emitting updatedToolOutput on every
# result would put a rewrite in the path of every tool call in the session.
CLEAN=$(redact 'PASS=23 FAIL=0')
[ -z "$CLEAN" ] && ok || bad "clean output must produce no rewrite, got: $CLEAN"

# A token split across nested fields still gets caught, because redaction runs
# over the serialised JSON rather than one field.
NESTED=$(jq -cn '{tool_name:"Bash",tool_response:{stdout:"ok",stderr:"glpat-BBBBBBBBBBBBBBBBBBBB"}}' \
  | bash "$REDACT" 2>/dev/null)
printf '%s' "$NESTED" | grep -q 'glpat-BBBB' && bad "nested stderr secret survived" || ok

# Malformed / empty stdin must not emit a rewrite.
printf '%s' '' | bash "$REDACT" >/dev/null 2>&1 && ok || bad "empty stdin should exit 0"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
