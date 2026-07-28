#!/usr/bin/env bash
#
# grounding-guard.sh (Codex CLI)
# Blocks the first non-document apply_patch edit of a session until /ground
# has emitted GROUNDING_STATUS=PASS or GROUNDING_STATUS=SKIP.

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
PATCH=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION_ID="${SESSION_ID:-${CODEX_SESSION_ID:-unknown}}"

if [[ -z "$TRANSCRIPT" ]] || [[ ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "main" ]]; then
  exit 0
fi

# apply_patch lists each affected path in a *** Add/Update/Delete File header.
# If the patch shape is unknown, treat it as code rather than bypassing the gate.
TARGETS=$(printf '%s\n' "$PATCH" | sed -nE 's/^\*\*\* (Add|Update|Delete) File: //p')
if [[ -n "$TARGETS" ]]; then
  NON_DOC_TARGET=$(printf '%s\n' "$TARGETS" | awk '!/\.md$/ && !/(^|\/)\.claudedocs\// { print; exit }')
  if [[ -z "$NON_DOC_TARGET" ]]; then
    exit 0
  fi
fi

COUNTER_FILE="/tmp/dotai_grounding_codex_${SESSION_ID}"
[[ -f "$COUNTER_FILE" ]] || echo "0" > "$COUNTER_FILE"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0

if [[ "$COUNT" -ge 1 ]]; then
  exit 0
fi

if grep -q 'GROUNDING_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
  echo "1" > "$COUNTER_FILE"
  exit 0
fi

if grep -q 'GROUNDING_STATUS=SKIP' "$TRANSCRIPT" 2>/dev/null; then
  SKIP_LOG="${HOME}/.codex/usage-data/grounding-skip.log"
  REASON=$(grep -o 'GROUNDING_STATUS=SKIP[^\"]*' "$TRANSCRIPT" 2>/dev/null | tail -n 1)
  mkdir -p "$(dirname "$SKIP_LOG")" 2>/dev/null
  echo "$(date '+%Y-%m-%d %H:%M:%S')	${CURRENT_BRANCH}	${TARGETS:-unknown}	${REASON}" >> "$SKIP_LOG" 2>/dev/null
  echo "1" > "$COUNTER_FILE"
  exit 0
fi

echo "⛔ First code edit of this session, but grounding was not done." >&2
echo "Run /ground to verify before writing: restate the task, read 1-2 existing" >&2
echo "reference files, verify any data/IDs, then emit GROUNDING_STATUS=PASS." >&2
echo "For a genuinely trivial edit, emit: GROUNDING_STATUS=SKIP reason=<why>" >&2
exit 2
