#!/usr/bin/env bash

# glab-guard blocks the `glab` CLI (not installed) and redirects to curl + jq.
# The regex matches `glab` after a shell separator, which made it fire on any
# command that merely CONTAINED "|glab" — including a read-only grep whose search
# pattern used `\|` alternation. That false positive is the case pinned below:
# blocking a search for the string is pure friction, since nothing is executed.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$ROOT/hooks/shared/glab-guard.sh"

PASS=0
FAIL=0

# want=block → guard must exit 2; want=allow → guard must exit 0.
check() {
  local want=$1 cmd=$2
  local status
  printf '%s' "$(jq -cn --arg c "$cmd" '{tool_input:{command:$c}}')" \
    | bash "$GUARD" >/dev/null 2>&1
  status=$?
  case "$want" in
    block) [ "$status" -eq 2 ] && { PASS=$((PASS+1)); return; } ;;
    allow) [ "$status" -eq 0 ] && { PASS=$((PASS+1)); return; } ;;
  esac
  FAIL=$((FAIL+1))
  echo "❌ expected $want, got exit $status for: $cmd" >&2
}

# Real invocations — must stay blocked.
check block 'glab mr list'
check block 'glab auth status'
check block 'cd /tmp && glab mr create'
check block 'echo hi; glab repo view'
check block 'true | glab mr list'
check block '  glab mr list'

# Read-only commands that merely mention glab — must NOT be blocked.
# This is the observed false positive: `\|` inside a quoted grep pattern is not a
# shell pipe, but the guard read it as one.
check allow 'grep -rn "gitlab\.com\|glab \|PRIVATE-TOKEN" skills/'
check allow "grep -n 'glab' README.md"
check allow 'rg "glab is not installed" hooks/'
check allow 'echo "do not use glab"'

# Unrelated commands.
check allow 'git status'
check allow 'ls -la'

# A command with no parsable input must fail open, never block everything.
printf '%s' '{}' | bash "$GUARD" >/dev/null 2>&1
[ $? -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "❌ empty payload should fail open" >&2; }

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
