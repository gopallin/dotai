#!/usr/bin/env bash
#
# context-budget-guard.sh (agy CLI adapter — ADVISORY ONLY)
# Mirror of the Claude context-budget-guard: reminds you to start fresh or split
# the task once the session transcript grows large. Long sessions re-send their
# whole context every turn, which usage analysis showed is ~96% of token cost.
#
# agy contract: advisory on stderr, exit 0 (mirrors agy/grounding-guard.sh).
# Registered on the AfterAgent event (matcher "*"), so it re-checks once per
# agent turn — a natural rate limit, same role as Claude's Stop hook.
#
# CAVEAT: the session transcript format is not documented as stable
# (antigravity.google/docs/hooks). Verify against the installed
# agy version before relying on it.

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION_ID="${SESSION_ID:-${AGY_SESSION_ID:-unknown}}"

BAND_LINES=1500

if [[ -n "$TRANSCRIPT" ]] && [[ -f "$TRANSCRIPT" ]]; then
  LINES=$(wc -l < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')
  if [[ "$LINES" =~ ^[0-9]+$ ]]; then
    BAND=$(( LINES / BAND_LINES ))
    if [[ "$BAND" -ge 1 ]]; then
      MARKER="/tmp/dotai_ctxband_agy_${SESSION_ID}"
      LAST_BAND=$(cat "$MARKER" 2>/dev/null)
      [[ "$LAST_BAND" =~ ^[0-9]+$ ]] || LAST_BAND=0
      if [[ "$BAND" -gt "$LAST_BAND" ]]; then
        echo "$BAND" > "$MARKER"
        echo "ℹ️  [advisory] Session transcript is large (~${LINES} lines)." >&2
        echo "    Long sessions re-send their whole context every turn (~96% of token cost)." >&2
        echo "    If the next task is unrelated, start a fresh session; for a long marathon, split it." >&2
      fi
    fi
  fi
fi

exit 0
