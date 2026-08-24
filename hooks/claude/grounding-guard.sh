#!/usr/bin/env bash
#
# grounding-guard.sh
# Fires on Claude Code's PreToolUse event for Edit/Write/MultiEdit.
# Blocks the FIRST non-doc code edit of a session until the /ground skill
# has emitted GROUNDING_STATUS=PASS (or an explicit SKIP) in the transcript.
#
# This is the front-of-work mirror of stop-guard.sh: stop-guard gates the END
# of work (/precommit must pass), grounding-guard gates the START (grounding
# must happen before the first code edit). See plan-grounding-guard.md.
#
# Exit codes:
#   0 — allow the edit
#   2 — block the edit (Claude sees the output and must run /ground first)
#
# Known, deliberate limits (plan-grounding-guard.md §4):
#   #1 Only the FIRST non-.md edit per session is gated; later edits are trusted.
#   #2 A fabricated PASS cannot be fully prevented (same as PRECOMMIT_STATUS=PASS).
#   #3 Bash file writes (echo >, sed -i) bypass this — matcher excludes Bash.

# ── Read input ────────────────────────────────────────────────────────────────

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION_ID="${SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"

# No transcript available — allow (cannot verify, fail open like stop-guard).
if [[ -z "$TRANSCRIPT" ]] || [[ ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

# ── Skip 1: not in a git repo ─────────────────────────────────────────────────
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# ── Skip 2: on master/main ────────────────────────────────────────────────────
#
# branch-guard already blocks code edits on master/main; requiring grounding
# there too would only deadlock. Mirrors stop-guard Skip 1.

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "main" ]]; then
  exit 0
fi

# ── Skip 3: documentation edits ───────────────────────────────────────────────
#
# *.md and anything under .claudedocs/ need no grounding (mirrors stop-guard /
# branch-guard doc pass-through). Do NOT advance the counter for these.

case "$FILE_PATH" in
  *.md|*/.claudedocs/*) exit 0 ;;
esac

# ── Only gate the FIRST non-doc code edit of the session ──────────────────────
#
# COUNTER holds the number of non-doc code edits already allowed past the gate
# this session. It is advanced ONLY when an edit is allowed — a blocked edit
# must not burn the "first edit" slot, so the next attempt is re-checked.

COUNTER_FILE="/tmp/dotai_grounding_${SESSION_ID}"
[[ -f "$COUNTER_FILE" ]] || echo "0" > "$COUNTER_FILE"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0

# Not the first non-doc code edit — already grounded earlier this session, trust it.
if [[ "$COUNT" -ge 1 ]]; then
  exit 0
fi

# ── First non-doc code edit: require a grounding marker ───────────────────────

# DOTAI_SKIP_LOG lets tests redirect to /tmp so they never touch the real log.
SKIP_LOG="${DOTAI_SKIP_LOG:-${HOME}/.claude/usage-data/grounding-skip.log}"

if grep -q 'GROUNDING_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
  echo "1" > "$COUNTER_FILE"   # advance: first edit grounded, trust the rest
  exit 0
fi

if grep -q 'GROUNDING_STATUS=SKIP' "$TRANSCRIPT" 2>/dev/null; then
  # Log the skip reason as a quality signal (overuse => the gate isn't working).
  # session_id is included so each skip can be traced back to its transcript.
  REASON=$(grep -o 'GROUNDING_STATUS=SKIP[^"]*' "$TRANSCRIPT" 2>/dev/null | tail -n 1)
  mkdir -p "$(dirname "$SKIP_LOG")" 2>/dev/null
  echo "$(date '+%Y-%m-%d %H:%M:%S')	${SESSION_ID}	${CURRENT_BRANCH}	${FILE_PATH}	${REASON}" >> "$SKIP_LOG" 2>/dev/null
  echo "1" > "$COUNTER_FILE"
  exit 0
fi

# No marker — block and instruct.
echo "⛔ First code edit of this session, but grounding was not done." >&2
echo "Run /ground to verify before writing: restate the task, read 1-2 existing" >&2
echo "reference files, verify any data/IDs, then emit GROUNDING_STATUS=PASS." >&2
echo "For a genuinely trivial edit, emit: GROUNDING_STATUS=SKIP reason=<why>" >&2
exit 2
