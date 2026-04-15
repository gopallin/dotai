#!/usr/bin/env bash
#
# stop-guard-gemini.sh
# Gemini CLI adapter — fires on AfterAgent event.
# Same logic as stop-guard.sh but uses Gemini's file-editing tool names.
#
# Exit codes:
#   0 — allow stop
#   2 — block stop (stderr message shown to user)
#
# Note: if stop-guard does not trigger on code changes, check Gemini's
# actual tool names in the transcript and adjust the grep pattern below.

# ── Read input ────────────────────────────────────────────────────────────────

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

if [[ -z "$TRANSCRIPT" ]] || [[ ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

# ── Layer 1: Were any code files changed? ─────────────────────────────────────
# Covers Gemini tool names (write_file, edit_file, replace_in_file)
# and Claude names (Edit, Write, MultiEdit) as fallback.

if ! grep -qiE '"(write_file|edit_file|create_file|replace_in_file|Edit|Write|MultiEdit)"' "$TRANSCRIPT" 2>/dev/null; then
  exit 0
fi

# ── Layer 2: Did quality checks pass? ────────────────────────────────────────
# Gemini has no /precommit command — only check for the result marker.

if ! grep -q 'PRECOMMIT_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
  echo "⛔ Code changes detected but quality checks did not pass." >&2
  echo "Run precommit checks and ensure PRECOMMIT_STATUS=PASS appears in the output." >&2
  exit 2
fi

exit 0
