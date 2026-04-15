#!/usr/bin/env bash
#
# stop-guard.sh
# Fires on Claude Code's Stop event.
# Blocks Claude from stopping if code changes were made but /precommit
# was not run, or ran but did not pass.
#
# Exit codes:
#   0 — allow stop
#   2 — block stop (Claude will see the output and continue working)

# ── Read input ────────────────────────────────────────────────────────────────

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# No transcript available — allow stop
if [[ -z "$TRANSCRIPT" ]] || [[ ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

# ── Layer 1: Were any code files changed? ─────────────────────────────────────

if ! grep -qE '"name"[[:space:]]*:[[:space:]]*"(Edit|Write|MultiEdit)"' "$TRANSCRIPT" 2>/dev/null; then
  exit 0  # No code changes — allow stop
fi

# ── Layer 2a: Was /precommit run? ─────────────────────────────────────────────

if ! grep -q '/precommit' "$TRANSCRIPT" 2>/dev/null; then
  echo "⛔ Code changes detected but /precommit was not run." >&2
  echo "Run /precommit and ensure it passes before finishing." >&2
  exit 2
fi

# ── Layer 2b: Did /precommit pass? ────────────────────────────────────────────

if ! grep -q 'PRECOMMIT_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
  echo "⛔ /precommit was run but did not pass." >&2
  echo "Fix the failures, run /precommit again, and ensure it outputs PRECOMMIT_STATUS=PASS." >&2
  exit 2
fi

# ── All checks passed ─────────────────────────────────────────────────────────

exit 0
