#!/usr/bin/env bash
#
# stop-guard.sh (agy CLI adapter — Stop event)
#
# agy's hook contract is NOT the Claude/Codex one. Verified against agy CLI:
#   event  : Stop  (there is no "AfterAgent" event — the old registration was
#            silently inert, see CLAUDE.md §agy Hook Contract)
#   stdin  : JSON with camelCase keys — transcriptPath, conversationId,
#            executionNum, terminationReason, error, fullyIdle, workspacePaths
#   stdout : JSON. {"decision":"continue","reason":"..."} blocks the stop and
#            re-enters the loop; ANY other decision lets the agent stop.
#   exit   : NOT the contract. `exit 2` fails open here, which is why every
#            path below must print a decision before exiting.

allow() { printf '%s' '{"decision":"allow"}'; exit 0; }
block() { jq -cn --arg r "$1" '{decision:"continue",reason:$r}'; exit 0; }

command -v jq >/dev/null 2>&1 || { printf '%s' '{"decision":"allow"}'; exit 0; }

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcriptPath // empty' 2>/dev/null)
TERMINATION=$(printf '%s' "$INPUT" | jq -r '.terminationReason // empty' 2>/dev/null)
EXECUTION_NUM=$(printf '%s' "$INPUT" | jq -r '.executionNum // 0' 2>/dev/null)

# Never fight an error or a step-limit stop — forcing "continue" there just
# burns turns on a loop that cannot make progress.
case "$TERMINATION" in
  error|max_steps_exceeded) allow ;;
esac

# Loop brake. Unlike Claude's Stop event there is no `stop_hook_active` flag, so
# an unconditional "continue" would spin forever. Give up after 2 blocks and let
# the user see the unfinished state rather than trapping the session.
[[ "$EXECUTION_NUM" =~ ^[0-9]+$ ]] || EXECUTION_NUM=0
[[ "$EXECUTION_NUM" -ge 3 ]] && allow

[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && allow

# ── Layer 1: were any code files changed? ─────────────────────────────────────
# agy's real edit tool names, observed from PreToolUse payloads.
if ! grep -qE '"(write_to_file|replace_file_content|edit_notebook)"' "$TRANSCRIPT" 2>/dev/null; then
  allow
fi

# ── Layer 2: did quality checks pass? ─────────────────────────────────────────
if grep -q 'PRECOMMIT_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
  allow
fi

block "Code was changed but quality checks did not pass. Run /precommit and confirm PRECOMMIT_STATUS=PASS appears in the output before stopping."
