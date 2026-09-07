#!/usr/bin/env bash
#
# grounding-guard.sh
# Fires on Claude Code's PreToolUse event for Edit/Write/MultiEdit.
#
# Two gates, both fed by what /ground emits into the transcript:
#
#   1. GROUNDING — blocks the FIRST non-doc code edit of a session until
#      GROUNDING_STATUS=PASS (or an explicit SKIP) appears.
#   2. SCOPE — blocks EVERY later edit whose path falls outside the
#      `scope_files:` list declared alongside that PASS.
#
# Gate 1 is the front-of-work mirror of stop-guard.sh (see
# plan-grounding-guard.md). Gate 2 exists because the usage report's largest
# remaining friction is scope-shaped, not grounding-shaped: an override
# implemented twice in two layers, a redundant admin page that had to be merged
# back, and a session abandoned outright because the proposed scope had quietly
# grown to include frontend files. "Touch only these files" as prose is a
# request; as a check on every edit it is a contract.
#
# Exit codes:
#   0 — allow the edit
#   2 — block the edit (Claude sees the output and must act on it)
#
# Known, deliberate limits:
#   #1 Gate 1 only sees the FIRST non-.md edit per session (plan §4 #1).
#   #2 A fabricated PASS or a self-widened scope cannot be fully prevented —
#      the agent can print another `scope_files:` line and retry. That is the
#      intended escape: it makes scope growth EXPLICIT and reviewable in the
#      transcript instead of silent. Same honesty note as PRECOMMIT_STATUS.
#   #3 Bash file writes (echo >, sed -i) bypass both gates — matcher excludes Bash.

# ── Read input ────────────────────────────────────────────────────────────────

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
# CLAUDE_CODE_SESSION_ID is the name Claude Code actually exports (verified
# 2026-09-07); CLAUDE_SESSION_ID is NOT set and was a dead fallback here — the
# same class of bug as the retired complexity-guard's CLAUDE_TOOL_NAME.
SESSION_ID="${SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}}"
# Strip anything that is not [A-Za-z0-9._-]: this value comes from the hook
# payload and is interpolated into /tmp paths below, so a `/` or `..` in it would
# write the marker outside the intended location. agy's guard already did this;
# the Claude and Codex copies did not, and now that a second marker file (the
# scope cache) keys off the same value, both are fixed rather than one.
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-')
SESSION_ID="${SESSION_ID:-unknown}"

# No transcript available — allow (cannot verify, fail open like stop-guard).
if [[ -z "$TRANSCRIPT" ]] || [[ ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

# ── Skip 1: not in a git repo ─────────────────────────────────────────────────
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# ── Skip 2: on master/main ────────────────────────────────────────────────────
#
# branch-guard already blocks code edits on master/main; requiring grounding
# there too would only deadlock. Mirrors stop-guard Skip 1.

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "main" ]]; then
  exit 0
fi

# ── Skip 3: documentation edits ───────────────────────────────────────────────
#
# *.md and anything under .claudedocs/ need no grounding (mirrors stop-guard /
# branch-guard doc pass-through). Do NOT advance the counter for these.

case "$FILE_PATH" in
  *.md|*/.claudedocs/*) exit 0 ;;
esac

# ── Skip 4: writes that cannot reach this branch's diff ───────────────────────
#
# Same argument branch-guard already accepts for these two cases: a write inside
# .git/, or outside the working tree entirely, cannot be committed and cannot
# enter history — so neither grounding nor scope has anything to protect. Paths
# are compared PHYSICALLY because on macOS /tmp is a symlink to /private/tmp and
# a textual prefix test would misfile real in-repo paths.
#
# REL is also what the scope check matches against, so it is computed once here.

case "$FILE_PATH" in
  */.git/*|*/.git|.git/*|.git) exit 0 ;;
esac

REL=""
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -n "$REPO_ROOT" ]] && REPO_ROOT_P=$(cd "$REPO_ROOT" 2>/dev/null && pwd -P); then
  FILE_ABS="$FILE_PATH"
  case "$FILE_ABS" in /*) ;; *) FILE_ABS="$PWD/$FILE_ABS" ;; esac
  SCAN_DIR=$(dirname "$FILE_ABS")
  SCAN_REST=$(basename "$FILE_ABS")
  while [[ ! -d "$SCAN_DIR" && "$SCAN_DIR" != "/" && "$SCAN_DIR" != "." ]]; do
    SCAN_REST="$(basename "$SCAN_DIR")/$SCAN_REST"
    SCAN_DIR=$(dirname "$SCAN_DIR")
  done
  SCAN_DIR_P=$(cd "$SCAN_DIR" 2>/dev/null && pwd -P) || SCAN_DIR_P="$SCAN_DIR"
  ABS_P="$SCAN_DIR_P/$SCAN_REST"
  case "$ABS_P" in
    "$REPO_ROOT_P"/*) REL="${ABS_P#"$REPO_ROOT_P"/}" ;;
    *) exit 0 ;;   # outside the working tree — cannot affect this branch
  esac
fi

# ── Scope contract helpers ────────────────────────────────────────────────────
#
# The declaration lives in the transcript, written by /ground as one
# `scope_files: <path-or-glob>` line per entry. Transcript lines are JSON, so
# embedded newlines arrive as the two characters \n and have to be split before
# the lines are readable.
#
# Matching (documented in skills/ground/SKILL.md so the declarer knows):
#   exact path        app/Services/Foo.php
#   glob              app/Services/*.php     (bash pattern: * also crosses /)
#   whole subtree     resources/js/   or   resources/js/**

SCOPE_FILE="/tmp/dotai_scope_${SESSION_ID}"

extract_scope() {
  sed 's/\\n/\
/g' "$TRANSCRIPT" 2>/dev/null \
    | awk '/scope_files:/ {
        sub(/.*scope_files:[[:space:]]*/, "")
        sub(/[",\\].*$/, "")
        sub(/[[:space:]]+$/, "")
        if (length($0)) print
      }' \
    | sort -u
}

scope_allows() {   # $1 = repo-relative path; scope patterns on stdin file
  local rel="$1" pat
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    case "$pat" in
      */)     [[ "$rel" == "${pat}"* ]] && return 0 ;;
      */'**') [[ "$rel" == "${pat%/**}/"* ]] && return 0 ;;
      *)      [[ "$rel" == $pat ]] && return 0 ;;   # unquoted RHS: glob match
    esac
  done < "$SCOPE_FILE"
  return 1
}

# ── Gate 1: the FIRST non-doc code edit of the session ────────────────────────
#
# COUNTER holds the number of non-doc code edits already allowed past the gate
# this session. It is advanced ONLY when an edit is allowed — a blocked edit
# must not burn the "first edit" slot, so the next attempt is re-checked.

COUNTER_FILE="/tmp/dotai_grounding_${SESSION_ID}"
[[ -f "$COUNTER_FILE" ]] || echo "0" > "$COUNTER_FILE"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0

# DOTAI_SKIP_LOG lets tests redirect to /tmp so they never touch the real log.
SKIP_LOG="${DOTAI_SKIP_LOG:-${HOME}/.claude/usage-data/grounding-skip.log}"

if [[ "$COUNT" -lt 1 ]]; then
  if grep -q 'GROUNDING_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
    extract_scope > "$SCOPE_FILE" 2>/dev/null
    echo "1" > "$COUNTER_FILE"   # advance: first edit grounded
    # Fall through to Gate 2 — the declared scope binds the first edit too.
  elif grep -q 'GROUNDING_STATUS=SKIP' "$TRANSCRIPT" 2>/dev/null; then
    # Log the skip reason as a quality signal (overuse => the gate isn't working).
    # session_id is included so each skip can be traced back to its transcript.
    REASON=$(grep -o 'GROUNDING_STATUS=SKIP[^"]*' "$TRANSCRIPT" 2>/dev/null | tail -n 1)
    mkdir -p "$(dirname "$SKIP_LOG")" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S')	${SESSION_ID}	${CURRENT_BRANCH}	${FILE_PATH}	${REASON}" >> "$SKIP_LOG" 2>/dev/null
    echo "1" > "$COUNTER_FILE"
    exit 0   # An explicit SKIP declares no scope; nothing to enforce.
  else
    echo "⛔ First code edit of this session, but grounding was not done." >&2
    echo "Run /ground to verify before writing: restate the task, read 1-2 existing" >&2
    echo "reference files, verify any data/IDs, declare the files you intend to touch" >&2
    echo "as scope_files: lines, then emit GROUNDING_STATUS=PASS." >&2
    echo "For a genuinely trivial edit, emit: GROUNDING_STATUS=SKIP reason=<why>" >&2
    exit 2
  fi
fi

# ── Gate 2: is this file inside the declared scope? ───────────────────────────
#
# No declaration at all => no constraint. Failing open here is deliberate: every
# /ground output written before scope_files existed would otherwise deadlock,
# and a gate that blocks work it was never told about teaches people to disable
# it. A PASS with no scope_files is instead a visible protocol violation in the
# transcript.

[[ -n "$REL" ]] || exit 0
[[ -f "$SCOPE_FILE" ]] || extract_scope > "$SCOPE_FILE" 2>/dev/null
[[ -s "$SCOPE_FILE" ]] || exit 0

scope_allows "$REL" && exit 0

# Cache miss is not proof: the scope may have been amended after it was cached.
# Re-read the transcript (only on the way to a block, so the common path stays a
# single small-file read) and re-check before refusing.
extract_scope > "$SCOPE_FILE" 2>/dev/null
[[ -s "$SCOPE_FILE" ]] || exit 0
scope_allows "$REL" && exit 0

echo "⛔ Outside the scope you declared for this session: ${REL}" >&2
echo "" >&2
echo "Declared scope_files:" >&2
sed 's/^/  /' "$SCOPE_FILE" >&2
echo "" >&2
echo "If this file genuinely belongs to the task, say so out loud and widen the" >&2
echo "contract before retrying — emit one line:" >&2
echo "  scope_files: ${REL}    (with a one-line reason why it is needed)" >&2
echo "If it does not, do not edit it. Extra pages, a second copy of the same" >&2
echo "override, or a neighbouring layer 'while we are here' is the rework loop" >&2
echo "this gate exists to stop." >&2
exit 2
