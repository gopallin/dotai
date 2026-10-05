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
# Plus the ENTRY BRIEF: the first edit into ANOTHER repository (not the cwd
# repo) is denied once, with that repo's CLAUDE.md / .claude/reviewer-rules.md
# in the reason. See the Claude copy's "Repo resolution" note for why every
# gate now resolves the repo from the file's path rather than from cwd.
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
#   #4 agy's transcript shape is documented as unstable, so declarations are
#      read from the RAW transcript — tool output that quotes a marker counts.
#      The Claude copy filters to conversation text; this one cannot yet.

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

# ── Skip 2: documentation edits ──────────────────────────────────────────────
case "$FILE_PATH" in
  *.md|*/.claudedocs/*) allow ;;
esac

# ── Skip 3: writes inside .git/ cannot reach any branch's diff ───────────────
case "$FILE_PATH" in
  */.git/*|*/.git|.git/*|.git) allow ;;
esac

# ── Repo resolution: which repository owns this file? ────────────────────────
#
# Physical paths (macOS /tmp → /private/tmp). A file outside the cwd repo is
# either scratch (allow) or another repo's (FOREIGN_ROOT set; its own branch is
# what the master/main skip looks at). A foreign file is matched against the
# scope by how it is reached from here (REL_CWD, ../other/…) or by absolute
# path — never by patterns relative to its own root, which would let `app/*.php`
# declared for one repo cover a sibling's app/ silently.

relpath() {   # $1 = from directory (absolute), $2 = to path (absolute)
  local from="$1" to="$2" up=""
  while :; do
    if [[ "$from" == "/" ]]; then printf '%s%s' "$up" "${to#/}"; return; fi
    if [[ "$to" == "$from"/* ]]; then printf '%s%s' "$up" "${to#"$from"/}"; return; fi
    from=$(dirname "$from"); up="../$up"
  done
}

REL=""
REL_CWD=""
FOREIGN_ROOT=""
ABS_P=""
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
    *)
      OTHER=$(git -C "$SCAN_DIR_P" rev-parse --show-toplevel 2>/dev/null) || OTHER=""
      [[ -n "$OTHER" ]] && OTHER=$(cd "$OTHER" 2>/dev/null && pwd -P)
      [[ -n "$OTHER" ]] || allow   # outside every working tree
      case "$(git -C "$OTHER" rev-parse --abbrev-ref HEAD 2>/dev/null)" in
        master|main) allow ;;      # branch-guard owns that case
      esac
      FOREIGN_ROOT="$OTHER"
      REL="${ABS_P#"$FOREIGN_ROOT"/}"
      REL_CWD=$(relpath "$REPO_ROOT_P" "$ABS_P")
      ;;
  esac
fi

# ── Skip 4: cwd repo on master/main, and the file is in it ───────────────────
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ -z "$FOREIGN_ROOT" ]]; then
  case "$CURRENT_BRANCH" in master|main) allow ;; esac
fi

# ── Scope contract helpers (extract_scope / scope_allows identical across CLIs) ─
#
# Matching rules are documented in skills/ground/SKILL.md, which is what the
# declarer reads:
#   exact path        app/Services/Foo.php
#   glob              app/Services/*.php     (bash pattern: * also crosses /)
#   whole subtree     resources/js/   or   resources/js/**
#   another repo      ../other-repo/app/Foo.php   or the absolute path
SCOPE_FILE="/tmp/dotai_scope_agy_${SESSION_ID}"

# Raw transcript, with JSON-escaped newlines split (limit #4 above).
scope_source() {
  sed 's/\\n/\
/g' "$TRANSCRIPT" 2>/dev/null
}

extract_scope() {
  scope_source \
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

in_scope() {
  if [[ -n "$FOREIGN_ROOT" ]]; then
    scope_allows "$REL_CWD" || scope_allows "$ABS_P"
  else
    scope_allows "$REL"
  fi
}

SCOPE_NAME="${REL_CWD:-$REL}"

# ── Gate 1: the FIRST non-doc code edit of the session ───────────────────────
COUNTER_FILE="/tmp/dotai_grounding_agy_${SESSION_ID}"
[[ -f "$COUNTER_FILE" ]] || echo "0" > "$COUNTER_FILE"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0

SKIPPED=0
if [[ "$COUNT" -lt 1 ]]; then
  if grep -q 'GROUNDING_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
    extract_scope > "$SCOPE_FILE" 2>/dev/null
    echo "1" > "$COUNTER_FILE"
    # Fall through to gate 2 — the declared scope binds the first edit too.
  elif grep -q 'GROUNDING_STATUS=SKIP' "$TRANSCRIPT" 2>/dev/null; then
    echo "1" > "$COUNTER_FILE"
    SKIPPED=1
    # An explicit SKIP declares no scope — but a foreign repo's rules still
    # have to be handed over, so only a cwd-repo file is allowed right here.
    [[ -n "$FOREIGN_ROOT" ]] || allow
  else
    _r="First code edit of this session, but grounding was not done. Run /ground first: restate the task, read 1-2 existing reference files, verify any data/IDs, declare the files you intend to touch as scope_files: lines, then emit GROUNDING_STATUS=PASS. For a genuinely trivial edit, emit GROUNDING_STATUS=SKIP reason=<why>."
    [[ -n "$FOREIGN_ROOT" ]] && _r="${_r} Note: this file belongs to another repository (${FOREIGN_ROOT}); declare it as  scope_files: ${SCOPE_NAME}  — as reached from this cwd, or absolute."
    deny "$_r"
  fi
fi

# ── Entry brief: first step into another repository this session ─────────────
#
# Once per (session, foreign repo); skipped when the transcript already shows
# that repo's CLAUDE.md being read. Nothing else in this session carries those
# rules: agy reads AGENTS.md from the cwd, and /precommit grades the cwd tree.
if [[ -n "$FOREIGN_ROOT" ]]; then
  BRIEF_FILE="/tmp/dotai_foreign_agy_${SESSION_ID}"
  if ! grep -Fqx -- "$FOREIGN_ROOT" "$BRIEF_FILE" 2>/dev/null; then
    printf '%s\n' "$FOREIGN_ROOT" >> "$BRIEF_FILE" 2>/dev/null
    if ! grep -Fq -- "${FOREIGN_ROOT}/CLAUDE.md" "$TRANSCRIPT" 2>/dev/null; then
      FOREIGN_BRANCH=$(git -C "$FOREIGN_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
      _brief="First edit into another repository this session: ${FOREIGN_ROOT} (branch: ${FOREIGN_BRANCH:-unknown}). This session's cwd repo is ${REPO_ROOT_P}; that repo's rules, memory and /precommit receipt do NOT cover files over there.
Before retrying this edit: read the rules below (they are that repo's own); declare its files as  scope_files: ${SCOPE_NAME}  (as reached from this cwd, or absolute — patterns relative to ITS root do not count); run /precommit and /ship INSIDE it (cd ${FOREIGN_ROOT} && bash ~/.gemini/config/skills/precommit/precommit.sh), since stop-guard checks that repo's own receipt. This brief is shown once per repository per session; the retry is not held by it."
      _found=0
      for rules in "CLAUDE.md" ".claude/reviewer-rules.md"; do
        f="${FOREIGN_ROOT}/${rules}"
        [[ -f "$f" ]] || continue
        _found=1
        _brief="${_brief}

──── ${f} ────
$(head -c 65536 "$f")"
        [[ "$(wc -c < "$f" 2>/dev/null)" -gt 65536 ]] && _brief="${_brief}
[… truncated at 64 KiB — read ${f} directly for the rest]"
      done
      [[ "$_found" -eq 0 ]] && _brief="${_brief}
(That repo has no CLAUDE.md and no .claude/reviewer-rules.md; review against the generic L1/L2/L3 levels and say so.)"
      deny "$_brief"
    fi
  fi
  [[ "$SKIPPED" -eq 1 ]] && allow
fi

# ── Gate 2: is this file inside the declared scope? ──────────────────────────
#
# No declaration => no constraint. Fails OPEN by design: a /ground output written
# before scope_files existed must not deadlock the session.

[[ -n "$REL" ]] || allow
[[ -f "$SCOPE_FILE" ]] || extract_scope > "$SCOPE_FILE" 2>/dev/null
[[ -s "$SCOPE_FILE" ]] || allow

in_scope && allow

# Cache miss is not proof: the scope may have been amended after it was cached.
# Re-read the transcript only on the way to a deny, so the common path stays a
# single small-file read.
extract_scope > "$SCOPE_FILE" 2>/dev/null
[[ -s "$SCOPE_FILE" ]] || allow
in_scope && allow

deny "Outside the scope you declared for this session: ${SCOPE_NAME}${FOREIGN_ROOT:+ (a file in another repository: ${FOREIGN_ROOT})}
Declared scope_files:
$(sed 's/^/  /' "$SCOPE_FILE")
If this file genuinely belongs to the task, say so out loud and widen the contract before retrying — emit one line: scope_files: ${SCOPE_NAME} (with a one-line reason why it is needed). If it does not, do not edit it. Extra pages, a second copy of the same override, or a neighbouring layer 'while we are here' is the rework loop this gate exists to stop."
