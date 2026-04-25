#!/usr/bin/env bash
#
# stop-guard-codex.sh
# Codex CLI adapter — fires on Stop event.
#
# IMPORTANT: Codex Stop hook requires JSON on stdout (not stderr).
#   {"decision": "allow"}                        → allow stop
#   {"decision": "block", "reason": "..."}       → block, continue agent
#
# Note: if stop-guard does not trigger on code changes, check Codex's
# actual tool names in the transcript and adjust the grep pattern below.

# ── Read input ────────────────────────────────────────────────────────────────

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

if [[ -z "$TRANSCRIPT" ]] || [[ ! -f "$TRANSCRIPT" ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

# ── Layer 1: Were any code files changed? ─────────────────────────────────────
# Covers Codex tool names (str_replace, write_file, create_file)
# and Claude names (Edit, Write, MultiEdit) as fallback.

if ! grep -qiE '"(str_replace|write_file|edit_file|create_file|Edit|Write|MultiEdit)"' "$TRANSCRIPT" 2>/dev/null; then
  echo '{"decision": "allow"}'
  exit 0
fi

# ── Layer 2: Did quality checks pass? ────────────────────────────────────────

if ! grep -q 'PRECOMMIT_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
  echo '{"decision": "block", "reason": "Code changes detected but quality checks did not pass. Run precommit checks and ensure PRECOMMIT_STATUS=PASS appears in the output."}'
  exit 0
fi

echo '{"decision": "allow"}'
exit 0
