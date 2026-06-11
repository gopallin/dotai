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
#
# Extract the file_path of every Edit/Write/MultiEdit tool call from the
# transcript. Schema: each JSONL line with .type=="assistant" carries
# .message.content[], whose tool_use items expose .name and .input.file_path.

EDITED_FILES=$(jq -r '
  select(.type=="assistant")
  | .message.content[]?
  | select(.type=="tool_use" and (.name=="Edit" or .name=="Write" or .name=="MultiEdit"))
  | .input.file_path // empty
' "$TRANSCRIPT" 2>/dev/null)

# No file changes at all — allow stop
if [[ -z "$EDITED_FILES" ]]; then
  exit 0
fi

# ── Layer 1b: Reconcile transcript edits against the real working tree ─────────
#
# EDITED_FILES is only a proxy: it counts ANY Edit/Write/MultiEdit tool_use,
# regardless of whether the file lives inside the repo or still exists. A
# scratch script written to /tmp (or a temp file created then removed within
# the session) leaves a tool_use in the transcript but no committable change.
# Ground the decision in `git status`: if the working tree is clean, there is
# nothing to precommit — allow stop.

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$REPO_ROOT" ]]; then
  exit 0  # Not inside a git repo — nothing to precommit
fi

if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
  exit 0  # Working tree clean — transcript edits were out-of-repo/scratch
fi

# ── Skip 1: cwd repo is on master/main ────────────────────────────────────────
#
# branch-guard blocks commits on master/main, so /precommit can never lead to a
# commit there — demanding it would only deadlock. Skip the requirement.

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "main" ]]; then
  exit 0
fi

# ── Skip 2: only documentation files were changed ─────────────────────────────
#
# Doc-only edits (*.md or anything under .claudedocs/) need no lint/build/test.
# Require /precommit only if at least one NON-doc file was touched.

NEEDS_PRECOMMIT=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ "$f" == *.md || "$f" == */.claudedocs/* ]]; then
    continue
  fi
  NEEDS_PRECOMMIT=1
  break
done <<< "$EDITED_FILES"

if [[ "$NEEDS_PRECOMMIT" -eq 0 ]]; then
  exit 0  # Documentation-only changes — allow stop
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

# ── Layer 3: Did response validate confidence? ─────────────────────────────────

# Extract last Claude message from transcript
LAST_MESSAGE=$(jq -r '.content[-1].text // empty' "$TRANSCRIPT" 2>/dev/null | tail -c 2000)

if [[ -n "$LAST_MESSAGE" ]]; then
  # Check for confidence-related keywords
  CONFIDENCE_MARKERS=$(echo "$LAST_MESSAGE" | grep -iE '(confident|uncertain|not sure|assume|if .* then|depends on|caveat|edge case|might|could break|unclear)' | wc -l)

  # If changes were made but no explicit confidence markers, warn
  if [[ $CONFIDENCE_MARKERS -eq 0 ]]; then
    echo "⚠️  Code changes made but response lacks explicit confidence assessment." >&2
    echo "Consider stating: confidence level, assumptions, edge cases, or uncertainties." >&2
    echo "See: Confidence-Driven Response Validation in GLOBAL_RULES.md" >&2
    exit 2
  fi
fi

# ── All checks passed ─────────────────────────────────────────────────────────

exit 0
