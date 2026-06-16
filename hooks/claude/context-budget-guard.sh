#!/usr/bin/env bash
#
# context-budget-guard.sh
# Fires on Claude Code's PreToolUse event (broad matcher).
# Advisory only: when the session transcript grows past size bands, it reminds
# you to /clear or split the task. Long sessions re-send their whole context on
# every turn (cache_read), which usage data showed is ~96% of token cost — 5
# sessions accounted for ~49% of all tokens.
#
# Never blocks (exit 0 always). Warns at most once per size band per session.

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION_ID="${SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"

# Nothing to measure — stay silent (fail open).
[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0

BAND_LINES=1500   # one "getting large" step (~tune to taste)

LINES=$(wc -l < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')
[[ "$LINES" =~ ^[0-9]+$ ]] || exit 0

BAND=$(( LINES / BAND_LINES ))
[[ "$BAND" -lt 1 ]] && exit 0   # still small, nothing to say

# Warn at most once per band per session.
MARKER="/tmp/dotai_ctxband_${SESSION_ID}"
LAST_BAND=$(cat "$MARKER" 2>/dev/null)
[[ "$LAST_BAND" =~ ^[0-9]+$ ]] || LAST_BAND=0
[[ "$BAND" -le "$LAST_BAND" ]] && exit 0

echo "$BAND" > "$MARKER"
echo -e "\033[1;33m[dotai ADVISORY]\033[0m Session transcript is large (~${LINES} lines)." >&2
echo "Long sessions re-send their whole context every turn (cache_read ≈ 96% of token cost)." >&2
echo "If the next task is unrelated, run /clear to reset; for a long marathon, split into a fresh session." >&2
exit 0
