#!/usr/bin/env bash
#
# context-budget-guard.sh (agy CLI adapter — PreInvocation, ADVISORY)
#
# Reminds you to start fresh once the session transcript grows large. Long
# sessions re-send their whole context every turn, which usage analysis showed is
# ~96% of token cost.
#
# agy contract (verified against agy CLI — see CLAUDE.md §agy Hook Contract):
#   event  : PreInvocation (flat handler list, no matcher). The old AfterAgent
#            registration did not exist as an event, so this never ran.
#   stdin  : JSON, camelCase — transcriptPath, conversationId, invocationNum.
#   stdout : {"injectSteps":[{"ephemeralMessage":"..."}]} surfaces the advice to
#            the model as a transient system message; {} says nothing.
#            stderr is NOT read by agy, which is why the advice must go here.

quiet() { printf '%s' '{}'; exit 0; }

command -v jq >/dev/null 2>&1 || quiet

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcriptPath // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.conversationId // empty' 2>/dev/null)
# Sanitised because it is interpolated into a /tmp path below (see grounding-guard).
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-')
SESSION_ID="${SESSION_ID:-unknown}"

BAND_LINES=1500

[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && quiet

LINES=$(wc -l < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')
[[ "$LINES" =~ ^[0-9]+$ ]] || quiet

BAND=$(( LINES / BAND_LINES ))
[[ "$BAND" -ge 1 ]] || quiet

# One nudge per band crossing — PreInvocation fires on every model call, so
# without this the advice would repeat on every single turn.
MARKER="/tmp/dotai_ctxband_agy_${SESSION_ID}"
LAST_BAND=$(cat "$MARKER" 2>/dev/null)
[[ "$LAST_BAND" =~ ^[0-9]+$ ]] || LAST_BAND=0
[[ "$BAND" -gt "$LAST_BAND" ]] || quiet
echo "$BAND" > "$MARKER"

jq -cn --arg m "ℹ️ [advisory] Session transcript is large (~${LINES} lines). Long sessions re-send their whole context every turn (~96% of token cost). Run /handoff to save a resume file, then start a fresh session from it." \
  '{injectSteps:[{ephemeralMessage:$m}]}'
