#!/usr/bin/env bash
#
# grounding-guard.sh (agy CLI adapter — BLOCKING)
# Front-of-work mirror of the Claude grounding-guard, ported to agy's tool names.
# Fires on BeforeTool for write_file / edit_file / create_file / replace_in_file.
# Blocks the FIRST non-doc code edit of a session until GROUNDING_STATUS=PASS
# (or SKIP) appears in the transcript.
#
# Exit codes:
#   0 — allow the edit
#   2 — block the edit (stderr message is shown; AI must run /ground first)
#
# Tool names sourced from agy/stop-guard.sh (verified against transcript).
# Known limits (mirrors claude/grounding-guard.sh §Known limits):
#   #1 Only the FIRST non-.md edit per session is gated; later edits are trusted.
#   #2 A fabricated GROUNDING_STATUS=PASS cannot be fully prevented.
#   #3 Bash-level file writes (echo >, sed -i) bypass this — matcher excludes Bash.

# ── Read input ────────────────────────────────────────────────────────────────

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.absolute_path // .tool_input.path // .tool_input.file_path // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION_ID="${SESSION_ID:-${AGY_SESSION_ID:-unknown}}"

# Only act on agy's file-editing tools (mirrors stop-guard.sh tool list).
case "$TOOL_NAME" in
  write_file|edit_file|create_file|replace_in_file) ;;
  *) exit 0 ;;
esac

# No transcript available — allow (fail open, same as claude version).
if [[ -z "$TRANSCRIPT" ]] || [[ ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

# ── Skip 1: not in a git repo ─────────────────────────────────────────────────
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# ── Skip 2: on master/main ────────────────────────────────────────────────────
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "main" ]]; then
  exit 0
fi

# ── Skip 3: documentation edits ───────────────────────────────────────────────
case "$FILE_PATH" in
  *.md|*/.claudedocs/*) exit 0 ;;
esac

# ── Only gate the FIRST non-doc code edit of the session ──────────────────────
COUNTER_FILE="/tmp/dotai_grounding_agy_${SESSION_ID}"
[[ -f "$COUNTER_FILE" ]] || echo "0" > "$COUNTER_FILE"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0

if [[ "$COUNT" -ge 1 ]]; then
  exit 0
fi

# ── First non-doc code edit: require a grounding marker ───────────────────────

if grep -q 'GROUNDING_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
  echo "1" > "$COUNTER_FILE"
  exit 0
fi

if grep -q 'GROUNDING_STATUS=SKIP' "$TRANSCRIPT" 2>/dev/null; then
  echo "1" > "$COUNTER_FILE"
  exit 0
fi

# No marker — block and instruct.
echo "⛔ First code edit of this session, but grounding was not done." >&2
echo "Run /ground to verify before writing: restate the task, read 1-2 existing" >&2
echo "reference files, verify any data/IDs, then emit GROUNDING_STATUS=PASS." >&2
echo "For a genuinely trivial edit, emit: GROUNDING_STATUS=SKIP reason=<why>" >&2
exit 2
