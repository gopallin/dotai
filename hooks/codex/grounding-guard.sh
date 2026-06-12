#!/usr/bin/env bash
#
# grounding-guard.sh (Codex CLI adapter — ADVISORY ONLY)
# Front-of-work mirror of the Claude grounding-guard, downgraded to advisory:
# it reminds, it does NOT block. Codex's PreToolUse hook contract and edit-tool
# names are not verified here; this stub keeps the structure cross-CLI compatible
# and is meant to be hardened to a real gate once that contract is confirmed.
# See plan-grounding-guard.md §3.1 / §4 #8.
#
# Codex hooks expect a JSON decision on stdout:
#   {"decision": "allow"}  → proceed
# This adapter always allows; the advisory text is emitted on stderr.
#
# TODO(codex): confirm PreToolUse event + edit tool names (str_replace/write_file/
# create_file), add a per-session "first edit" counter, then switch allow->block
# when GROUNDING_STATUS=PASS/SKIP is absent.

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

if [[ -n "$TRANSCRIPT" ]] && [[ -f "$TRANSCRIPT" ]]; then
  if ! grep -q 'GROUNDING_STATUS=' "$TRANSCRIPT" 2>/dev/null; then
    echo "ℹ️  [advisory] No grounding done yet. Before writing code, restate the task," >&2
    echo "    read 1-2 existing reference files, verify data/IDs, then state" >&2
    echo "    GROUNDING_STATUS=PASS (or SKIP reason=... for trivial edits)." >&2
  fi
fi

echo '{"decision": "allow"}'
exit 0
