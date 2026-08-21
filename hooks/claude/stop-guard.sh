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

# ── Layer 1: Were any files written this session? ─────────────────────────────
#
# Extract the file_path of every Edit/Write/MultiEdit tool call from the
# transcript. Schema: each JSONL line with .type=="assistant" carries
# .message.content[], whose tool_use items expose .name and .input.file_path.
#
# This is only a *candidate* list — it counts writes to anywhere on disk. It is
# reconciled against the repo in Layer 1b; never gate on it directly.

EDITED_FILES=$(jq -r '
  select(.type=="assistant")
  | .message.content[]?
  | select(.type=="tool_use" and (.name=="Edit" or .name=="Write" or .name=="MultiEdit"))
  | .input.file_path // empty
' "$TRANSCRIPT" 2>/dev/null)

# No file writes at all — allow stop
if [[ -z "$EDITED_FILES" ]]; then
  exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$REPO_ROOT" ]]; then
  exit 0  # Not inside a git repo — nothing to precommit
fi

# ── Layer 1b: Intersect the writes with what is actually dirty in THIS repo ────
#
# The previous version asked only "is the working tree dirty?" and treated any
# dirt as proof that the session's writes needed gating. Those are different
# questions. A session that wrote one scratch script to /tmp, in a repo carrying
# an unrelated pre-existing untracked file, was blocked and told to run
# /precommit on changes it had not made — with no way to comply, since there was
# nothing to fix.
#
# Gate on the intersection instead: a written file counts only if it lives
# inside this repo AND appears in `git status --porcelain`. That drops
# out-of-repo scratch files, files written and then reverted, and pre-existing
# dirt nobody touched this session.

DIRTY=$(git status --porcelain 2>/dev/null | sed 's/^.\{3\}//' | sed 's/.* -> //')

RELEVANT=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  # Absolute-ise relative paths against the repo root before comparing.
  [[ "$f" != /* ]] && f="${REPO_ROOT}/${f}"
  case "$f" in
    "$REPO_ROOT"/*) rel="${f#"$REPO_ROOT"/}" ;;
    *) continue ;;  # written outside this repo (scratchpad, $HOME, another repo)
  esac
  while IFS= read -r d; do
    [[ -n "$d" && "$d" == "$rel" ]] && { RELEVANT+="${rel}"$'\n'; break; }
  done <<< "$DIRTY"
done <<< "$EDITED_FILES"

if [[ -z "$RELEVANT" ]]; then
  exit 0  # Nothing this session wrote is pending in this repo
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
# Require /precommit only if at least one NON-doc file is pending. Applied to
# RELEVANT, not EDITED_FILES: the old version tested the unreconciled list, so a
# non-doc scratch file outside the repo defeated the doc-only skip.

NEEDS_PRECOMMIT=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ "$f" == *.md || "$f" == .claudedocs/* || "$f" == */.claudedocs/* ]]; then
    continue
  fi
  NEEDS_PRECOMMIT=1
  break
done <<< "$RELEVANT"

if [[ "$NEEDS_PRECOMMIT" -eq 0 ]]; then
  exit 0  # Documentation-only changes — allow stop
fi

# ── Layer 2: Did /precommit actually run, and pass, on THIS tree? ─────────────
#
# Read the receipt precommit.sh writes. Do NOT grep the transcript.
#
# The transcript cannot be the state store, because a blocked hook's own stderr
# is fed back into it as a user message — and this script's messages name both
# `/precommit` and `PRECOMMIT_STATUS=PASS`. Grepping for those literals meant
# the guard's first block satisfied its own Layer 2a and the second satisfied
# Layer 2b, after which it stood open for the rest of the session. Merely
# discussing /precommit in prose passed it too, and so did an agent typing the
# PASS line by hand without running the pipeline. Verified in the wild: a
# session whose only PRECOMMIT_STATUS=PASS was hand-written prose stopped clean.
#
# The receipt is keyed to the tree it was earned on, so it expires the moment
# anything else is edited — "passed, then changed three files" is not a pass.

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
RECEIPT="${GIT_DIR}/dotai-precommit"

if [[ ! -f "$RECEIPT" ]]; then
  echo "⛔ Code changes are pending but /precommit has not run in this repo." >&2
  echo "Pending files this session wrote:" >&2
  printf '  %s\n' $RELEVANT >&2
  echo "Run /precommit; it must reach PRECOMMIT_STATUS=PASS." >&2
  exit 2
fi

RECEIPT_STATUS=$(sed -n 's/^status=//p' "$RECEIPT" | head -1)
RECEIPT_TREE=$(sed -n 's/^tree=//p' "$RECEIPT" | head -1)

# ⚠️ Must stay identical to precommit_tree_fingerprint() in commands/precommit.sh.
# tests/precommit.test.sh runs the pipeline and then this guard against one
# tree, and fails if they diverge.
CURRENT_TREE=$({
    git rev-parse HEAD 2>/dev/null
    git status --porcelain -uall 2>/dev/null
    # Status lines alone are not enough: re-editing a file that was ALREADY
    # dirty leaves porcelain byte-identical, so a PASS survived arbitrary
    # further edits — the exact thing the receipt exists to prevent. Caught by
    # tests/precommit.test.sh. --binary so a second edit to a binary file
    # registers too, instead of collapsing to "Binary files differ".
    git diff HEAD --binary 2>/dev/null
    # git diff says nothing about untracked content, so hash it directly.
    git ls-files --others --exclude-standard -z 2>/dev/null \
      | xargs -0 shasum -a 256 2>/dev/null
} | shasum -a 256 | cut -d' ' -f1)

if [[ "$RECEIPT_STATUS" != "PASS" ]]; then
  echo "⛔ /precommit ran but did not pass (receipt: status=${RECEIPT_STATUS:-unknown})." >&2
  echo "Fix the failures and run /precommit again until it reports PRECOMMIT_STATUS=PASS." >&2
  exit 2
fi

if [[ "$RECEIPT_TREE" != "$CURRENT_TREE" ]]; then
  echo "⛔ /precommit passed, but the working tree changed afterwards." >&2
  echo "That PASS was earned on a different tree and does not cover the current one." >&2
  echo "Run /precommit again." >&2
  exit 2
fi

# ── All checks passed ─────────────────────────────────────────────────────────
#
# The former "Layer 3" confidence check lived here: it grepped the last message
# for hedging words ("might", "assume", "unclear") and blocked when none were
# found. It never ran even once. It read `jq -r '.content[-1].text'`, but the
# transcript is JSONL with text at `.message.content[]` — so LAST_MESSAGE was
# always empty and the `-n` guard always skipped. Removed rather than repaired:
# a check that blocks until hedging language appears rewards hedging, which is
# the opposite of GLOBAL_RULES §"Skipped is not passed" (name the specific gap,
# don't sprinkle "should"). See docs/ABLATION.md for the same call on
# complexity-guard.sh.

exit 0
