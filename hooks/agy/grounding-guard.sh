#!/usr/bin/env bash
#
# grounding-guard.sh (agy CLI adapter — PreToolUse, BLOCKING)
#
# Front-of-work mirror of stop-guard, with the same two gates as
# hooks/claude/grounding-guard.sh:
#   1. GROUNDING — blocks the FIRST non-doc code edit of a session until
#      GROUNDING_STATUS=PASS (or SKIP) appears in the transcript.
#   2. SCOPE — blocks every later edit whose path falls outside the
#      `scope_files:` list declared with that PASS.
#
# agy contract (verified against agy CLI — see CLAUDE.md §agy Hook Contract):
#   event  : PreToolUse, matcher write_to_file|replace_file_content|edit_notebook
#            (agy has no "BeforeTool" event and no write_file/edit_file tools —
#            the previous registration matched nothing at all)
#   stdin  : JSON, camelCase — toolCall.name, toolCall.args, transcriptPath,
#            conversationId, stepIdx. Note args keys are PascalCase.
#   stdout : {"decision":"deny","reason":"..."} blocks; {"decision":"allow"} permits.
#   exit   : NOT the contract — exit 2 fails open, so always print a decision.
#
# Known limits (mirror claude/grounding-guard.sh):
#   #1 Only the FIRST non-.md edit per session is gated BY GATE 1; every later
#      edit is still checked against the declared scope by gate 2.
#   #2 Neither a fabricated GROUNDING_STATUS=PASS nor a self-widened scope can
#      be fully prevented — the agent may print another `scope_files:` line and
#      retry. That is the intended escape: it makes scope growth explicit in the
#      transcript instead of silent.
#   #3 Writes made through run_command (echo >, sed -i) bypass this matcher.

allow() { printf '%s' '{"decision":"allow"}'; exit 0; }
deny()  { jq -cn --arg r "$1" '{decision:"deny",reason:$r}'; exit 0; }

command -v jq >/dev/null 2>&1 || { printf '%s' '{"decision":"allow"}'; exit 0; }

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.toolCall.name // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcriptPath // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.conversationId // empty' 2>/dev/null)
# Strip anything that is not [A-Za-z0-9._-]: this value comes from the hook
# payload and is interpolated into a /tmp path below, so a `/` or `..` in it
# would write the marker outside the intended location.
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-')
SESSION_ID="${SESSION_ID:-unknown}"

# agy tool args are PascalCase, and the path key differs per tool — both observed
# from live PreToolUse payloads:
#   write_to_file          → TargetFile (+ CodeContent, Overwrite, Description)
#   replace_file_content   → TargetFile (+ StartLine, EndLine, TargetContent, …)
#   view_file              → AbsolutePath
# TargetFile covers both edit tools this hook matches; AbsolutePath is kept because
# it is the same concept and costs nothing if agy ever unifies them.
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '
  .toolCall.args // {} | (.TargetFile // .AbsolutePath // empty)
' 2>/dev/null)

case "$TOOL_NAME" in
  write_to_file|replace_file_content|edit_notebook) ;;
  *) allow ;;
esac

[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && allow

# ── Skip 1: not in a git repo ─────────────────────────────────────────────────
git rev-parse --git-dir >/dev/null 2>&1 || allow

# ── Skip 2: on master/main (branch-guard owns that case) ─────────────────────
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
case "$CURRENT_BRANCH" in master|main) allow ;; esac

# ── Skip 3: documentation edits ──────────────────────────────────────────────
case "$FILE_PATH" in
  *.md|*/.claudedocs/*) allow ;;
esac

# ── Skip 4: writes that cannot reach this branch's diff ──────────────────────
#
# A write inside .git/, or outside the working tree, cannot be committed and
# cannot enter history — so neither gate has anything to protect (the argument
# branch-guard already accepts). Paths are compared PHYSICALLY: on macOS /tmp is
# a symlink to /private/tmp and a textual prefix test would misfile real in-repo
# paths. REL is also what gate 2 matches against, so it is computed once here.
case "$FILE_PATH" in
  */.git/*|*/.git|.git/*|.git) allow ;;
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
    *) allow ;;   # outside the working tree — cannot affect this branch
  esac
fi

# ── Scope contract helpers (identical across all three CLIs) ─────────────────
#
# Matching rules are documented in skills/ground/SKILL.md, which is what the
# declarer reads:
#   exact path        app/Services/Foo.php
#   glob              app/Services/*.php     (bash pattern: * also crosses /)
#   whole subtree     resources/js/   or   resources/js/**
SCOPE_FILE="/tmp/dotai_scope_agy_${SESSION_ID}"

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

# ── Gate 1: the FIRST non-doc code edit of the session ───────────────────────
COUNTER_FILE="/tmp/dotai_grounding_agy_${SESSION_ID}"
[[ -f "$COUNTER_FILE" ]] || echo "0" > "$COUNTER_FILE"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0

if [[ "$COUNT" -lt 1 ]]; then
  if grep -q 'GROUNDING_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
    extract_scope > "$SCOPE_FILE" 2>/dev/null
    echo "1" > "$COUNTER_FILE"
    # Fall through to gate 2 — the declared scope binds the first edit too.
  elif grep -q 'GROUNDING_STATUS=SKIP' "$TRANSCRIPT" 2>/dev/null; then
    echo "1" > "$COUNTER_FILE"
    allow   # An explicit SKIP declares no scope; nothing to enforce.
  else
    deny "First code edit of this session, but grounding was not done. Run /ground first: restate the task, read 1-2 existing reference files, verify any data/IDs, declare the files you intend to touch as scope_files: lines, then emit GROUNDING_STATUS=PASS. For a genuinely trivial edit, emit GROUNDING_STATUS=SKIP reason=<why>."
  fi
fi

# ── Gate 2: is this file inside the declared scope? ──────────────────────────
#
# No declaration => no constraint. Fails OPEN by design: a /ground output written
# before scope_files existed must not deadlock the session.

[[ -n "$REL" ]] || allow
[[ -f "$SCOPE_FILE" ]] || extract_scope > "$SCOPE_FILE" 2>/dev/null
[[ -s "$SCOPE_FILE" ]] || allow

scope_allows "$REL" && allow

# Cache miss is not proof: the scope may have been amended after it was cached.
# Re-read the transcript only on the way to a deny, so the common path stays a
# single small-file read.
extract_scope > "$SCOPE_FILE" 2>/dev/null
[[ -s "$SCOPE_FILE" ]] || allow
scope_allows "$REL" && allow

deny "Outside the scope you declared for this session: ${REL}
Declared scope_files:
$(sed 's/^/  /' "$SCOPE_FILE")
If this file genuinely belongs to the task, say so out loud and widen the contract before retrying — emit one line: scope_files: ${REL} (with a one-line reason why it is needed). If it does not, do not edit it. Extra pages, a second copy of the same override, or a neighbouring layer 'while we are here' is the rework loop this gate exists to stop."
