#!/usr/bin/env bash
#
# context-budget-guard.sh (Codex CLI adapter — ADVISORY ONLY)
# Mirror of the Claude context-budget-guard: reminds you to /clear or split the
# task once the session transcript grows large. Long sessions re-send their whole
# context every turn, which usage analysis showed is ~96% of token cost.
#
# Codex contract: emit {"decision":"allow"} on stdout (mirrors codex/grounding-
# guard.sh) and the advisory on stderr; never blocks.
#
# COVERAGE CAVEAT: this guard is registered on "Bash", so it only re-checks size
# on shell-tool turns. Sessions with few Bash calls get fewer reminders. The
# transcript/rollout format is documented as unstable — verify against the
# installed Codex version before relying on it.

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION_ID="${SESSION_ID:-${CODEX_SESSION_ID:-unknown}}"

BAND_LINES=1500

if [[ -n "$TRANSCRIPT" ]] && [[ -f "$TRANSCRIPT" ]]; then
  LINES=$(wc -l < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')
  if [[ "$LINES" =~ ^[0-9]+$ ]]; then
    BAND=$(( LINES / BAND_LINES ))
    if [[ "$BAND" -ge 1 ]]; then
      MARKER="/tmp/dotai_ctxband_codex_${SESSION_ID}"
      LAST_BAND=$(cat "$MARKER" 2>/dev/null)
      [[ "$LAST_BAND" =~ ^[0-9]+$ ]] || LAST_BAND=0
      if [[ "$BAND" -gt "$LAST_BAND" ]]; then
        echo "$BAND" > "$MARKER"
        echo "ℹ️  [advisory] Session transcript is large (~${LINES} lines)." >&2
        echo "    Long sessions re-send their whole context every turn (~96% of token cost)." >&2
        echo "    Run /handoff to save a resume file, then start a fresh session from the handoff." >&2
      fi
    fi
  fi
fi

echo '{"decision": "allow"}'
exit 0
