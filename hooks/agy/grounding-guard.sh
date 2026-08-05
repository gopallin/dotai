#!/usr/bin/env bash
#
# grounding-guard.sh (agy CLI adapter — PreToolUse, BLOCKING)
#
# Front-of-work mirror of stop-guard: blocks the FIRST non-doc code edit of a
# session until GROUNDING_STATUS=PASS (or SKIP) appears in the transcript.
#
# agy contract (verified against agy CLI — see CLAUDE.md §agy Hook Contract):
#   event  : PreToolUse, matcher write_to_file|replace_file_content|edit_notebook
#            (agy has no "BeforeTool" event and no write_file/edit_file tools —
#            the previous registration matched nothing at all)
#   stdin  : JSON, camelCase — toolCall.name, toolCall.args, transcriptPath,
#            conversationId, stepIdx. Note args keys are PascalCase.
#   stdout : {"decision":"deny","reason":"..."} blocks; {"decision":"allow"} permits.
#   exit   : NOT the contract — exit 2 fails open, so always print a decision.
#
# Known limits (mirror claude/grounding-guard.sh):
#   #1 Only the FIRST non-.md edit per session is gated; later edits are trusted.
#   #2 A fabricated GROUNDING_STATUS=PASS cannot be fully prevented.
#   #3 Writes made through run_command (echo >, sed -i) bypass this matcher.

allow() { printf '%s' '{"decision":"allow"}'; exit 0; }
deny()  { jq -cn --arg r "$1" '{decision:"deny",reason:$r}'; exit 0; }

command -v jq >/dev/null 2>&1 || { printf '%s' '{"decision":"allow"}'; exit 0; }

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.toolCall.name // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcriptPath // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.conversationId // empty' 2>/dev/null)
# Strip anything that is not [A-Za-z0-9._-]: this value comes from the hook
# payload and is interpolated into a /tmp path below, so a `/` or `..` in it
# would write the marker outside the intended location.
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-')
SESSION_ID="${SESSION_ID:-unknown}"

# agy tool args are PascalCase, and the path key differs per tool — both observed
# from live PreToolUse payloads:
#   write_to_file          → TargetFile (+ CodeContent, Overwrite, Description)
#   replace_file_content   → TargetFile (+ StartLine, EndLine, TargetContent, …)
#   view_file              → AbsolutePath
# TargetFile covers both edit tools this hook matches; AbsolutePath is kept because
# it is the same concept and costs nothing if agy ever unifies them.
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '
  .toolCall.args // {} | (.TargetFile // .AbsolutePath // empty)
' 2>/dev/null)

case "$TOOL_NAME" in
  write_to_file|replace_file_content|edit_notebook) ;;
  *) allow ;;
esac

[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && allow

# ── Skip 1: not in a git repo ─────────────────────────────────────────────────
git rev-parse --git-dir >/dev/null 2>&1 || allow

# ── Skip 2: on master/main (branch-guard owns that case) ─────────────────────
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
case "$CURRENT_BRANCH" in master|main) allow ;; esac

# ── Skip 3: documentation edits ──────────────────────────────────────────────
case "$FILE_PATH" in
  *.md|*/.claudedocs/*) allow ;;
esac

# ── Only gate the FIRST non-doc code edit of the session ─────────────────────
COUNTER_FILE="/tmp/dotai_grounding_agy_${SESSION_ID}"
[[ -f "$COUNTER_FILE" ]] || echo "0" > "$COUNTER_FILE"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0
[[ "$COUNT" -ge 1 ]] && allow

if grep -qE 'GROUNDING_STATUS=(PASS|SKIP)' "$TRANSCRIPT" 2>/dev/null; then
  echo "1" > "$COUNTER_FILE"
  allow
fi

deny "First code edit of this session, but grounding was not done. Run /ground first: restate the task, read 1-2 existing reference files, verify any data/IDs, then emit GROUNDING_STATUS=PASS. For a genuinely trivial edit, emit GROUNDING_STATUS=SKIP reason=<why>."
