#!/usr/bin/env bash
#
# shared-guard-adapter.sh (agy CLI — PreToolUse protocol translator)
#
# The shared guards (branch-guard, glab-guard, complexity-guard) speak the
# Claude/Codex contract: snake_case {tool_input:{command,file_path}} on stdin,
# exit 2 + stderr to block. agy speaks camelCase {toolCall:{name,args}} on stdin
# and reads a JSON decision from stdout, ignoring the exit code entirely.
#
# Rather than fork those guards (which would leave two copies of the branch rules
# to drift apart), this adapter translates in both directions:
#
#   wrapped exit 2               → {"decision":"deny","reason":<stderr>}
#   wrapped exit 0 with stderr   → {"decision":"allow","reason":<stderr>}  (advisory)
#   wrapped exit 0, no stderr    → {"decision":"allow"}
#
# The advisory case matters because agy never shows a hook's stderr to anyone —
# an exit-0 guard that only writes stderr is invisible, so its text is surfaced
# as the decision `reason` instead.
#
# Usage (from hooks.json):
#   bash ~/.gemini/hooks/agy/shared-guard-adapter.sh ~/.gemini/hooks/shared/branch-guard.sh
#
# ⚠️ DO NOT add `set -e` / `set -euo pipefail` to this script, unlike the rest of
# dotai. Blocking is signalled by the wrapped guard exiting 2, and under `set -e`
# that exit would kill this script BEFORE it prints the deny JSON — agy would then
# read no decision and fail open, silently turning every guard back off. The
# absence of `set -e` here is load-bearing.

allow() { printf '%s' '{"decision":"allow"}'; exit 0; }

GUARD="$1"
[[ -n "$GUARD" && -f "$GUARD" ]] || allow
command -v jq >/dev/null 2>&1 || allow

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.toolCall.name // empty' 2>/dev/null)

# agy tool args are PascalCase — run_command→CommandLine (verified),
# list_dir→DirectoryPath (verified). File-tool path keys are not yet confirmed,
# so try the plausible spellings; an unmatched key just leaves file_path empty,
# which the shared guards treat as "no file involved".
COMMAND=$(printf '%s' "$INPUT" | jq -r '.toolCall.args.CommandLine // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '
  .toolCall.args // {} |
  (.AbsolutePath // .TargetFile // .TargetFilePath // .FilePath // .Path // .File // empty)
' 2>/dev/null)

PAYLOAD=$(jq -cn --arg c "$COMMAND" --arg f "$FILE_PATH" \
  '{tool_input: ({} + (if $c == "" then {} else {command:$c} end)
                    + (if $f == "" then {} else {file_path:$f} end))}')

STDERR_FILE=$(mktemp)
trap 'rm -f "$STDERR_FILE"' EXIT

# CLAUDE_TOOL_NAME for the guards that read it; $1 for complexity-guard, which
# takes the tool name positionally.
printf '%s' "$PAYLOAD" \
  | CLAUDE_TOOL_NAME="$TOOL_NAME" bash "$GUARD" "$TOOL_NAME" >/dev/null 2>"$STDERR_FILE"
STATUS=$?

REASON=$(cat "$STDERR_FILE" 2>/dev/null)

if [[ "$STATUS" -eq 2 ]]; then
  jq -cn --arg r "$REASON" '{decision:"deny",reason:$r}'
  exit 0
fi

if [[ -n "$REASON" ]]; then
  jq -cn --arg r "$REASON" '{decision:"allow",reason:$r}'
  exit 0
fi

allow
