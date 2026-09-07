#!/usr/bin/env bash
#
# grounding-guard.sh (Codex CLI)
#
# Two gates, mirroring hooks/claude/grounding-guard.sh:
#   1. GROUNDING — blocks the first non-document apply_patch edit of a session
#      until /ground has emitted GROUNDING_STATUS=PASS or =SKIP.
#   2. SCOPE — blocks every later patch touching a file outside the
#      `scope_files:` list declared with that PASS.
#
# One apply_patch can rewrite several files, so gate 2 checks EVERY target and
# refuses on the first one outside the contract: a patch applies whole, so
# allowing it because most of its targets were declared would apply the
# undeclared one too.

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
PATCH=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION_ID="${SESSION_ID:-${CODEX_SESSION_ID:-unknown}}"
# Strip anything that is not [A-Za-z0-9._-]: this value comes from the hook
# payload and is interpolated into /tmp paths below, so a `/` or `..` in it would
# write the marker outside the intended location. agy's guard already did this;
# the Claude and Codex copies did not, and now that a second marker file (the
# scope cache) keys off the same value, both are fixed rather than one.
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-')
SESSION_ID="${SESSION_ID:-unknown}"
SCOPE_FILE="/tmp/dotai_scope_codex_${SESSION_ID}"

if [[ -z "$TRANSCRIPT" ]] || [[ ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "main" ]]; then
  exit 0
fi

# apply_patch lists each affected path in a *** Add/Update/Delete File header.
# If the patch shape is unknown, treat it as code rather than bypassing the gate.
TARGETS=$(printf '%s\n' "$PATCH" | sed -nE 's/^\*\*\* (Add|Update|Delete) File: //p')
if [[ -n "$TARGETS" ]]; then
  NON_DOC_TARGET=$(printf '%s\n' "$TARGETS" | awk '!/\.md$/ && !/(^|\/)\.claudedocs\// { print; exit }')
  if [[ -z "$NON_DOC_TARGET" ]]; then
    exit 0
  fi
fi

# ── Scope contract helpers (identical across all three CLIs) ─────────────────
#
# Matching rules are documented in skills/ground/SKILL.md, which is what the
# declarer reads:
#   exact path        app/Services/Foo.php
#   glob              app/Services/*.php     (bash pattern: * also crosses /)
#   whole subtree     resources/js/   or   resources/js/**
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

COUNTER_FILE="/tmp/dotai_grounding_codex_${SESSION_ID}"
[[ -f "$COUNTER_FILE" ]] || echo "0" > "$COUNTER_FILE"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0

if [[ "$COUNT" -lt 1 ]]; then
  if grep -q 'GROUNDING_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
    extract_scope > "$SCOPE_FILE" 2>/dev/null
    echo "1" > "$COUNTER_FILE"
    # Fall through to gate 2 — the declared scope binds the first patch too.
  elif grep -q 'GROUNDING_STATUS=SKIP' "$TRANSCRIPT" 2>/dev/null; then
    SKIP_LOG="${HOME}/.codex/usage-data/grounding-skip.log"
    REASON=$(grep -o 'GROUNDING_STATUS=SKIP[^\"]*' "$TRANSCRIPT" 2>/dev/null | tail -n 1)
    mkdir -p "$(dirname "$SKIP_LOG")" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S')	${CURRENT_BRANCH}	${TARGETS:-unknown}	${REASON}" >> "$SKIP_LOG" 2>/dev/null
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

# ── Gate 2: every target of this patch must sit inside the declared scope ────
#
# No declaration => no constraint. Fails OPEN by design: a /ground output
# written before scope_files existed must not deadlock the session.

[[ -n "$TARGETS" ]] || exit 0
[[ -f "$SCOPE_FILE" ]] || extract_scope > "$SCOPE_FILE" 2>/dev/null
[[ -s "$SCOPE_FILE" ]] || exit 0

OUTSIDE=""
while IFS= read -r target; do
  [[ -z "$target" ]] && continue
  case "$target" in
    *.md|*/.claudedocs/*|.claudedocs/*) continue ;;
    */.git/*|.git/*) continue ;;
  esac
  scope_allows "$target" || OUTSIDE+="${target}"$'\n'
done <<< "$TARGETS"

# Cache miss is not proof: the scope may have been amended after it was cached.
# Re-read the transcript only on the way to a block, so the common path stays a
# single small-file read.
if [[ -n "$OUTSIDE" ]]; then
  extract_scope > "$SCOPE_FILE" 2>/dev/null
  OUTSIDE=""
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    case "$target" in
      *.md|*/.claudedocs/*|.claudedocs/*) continue ;;
      */.git/*|.git/*) continue ;;
    esac
    scope_allows "$target" || OUTSIDE+="${target}"$'\n'
  done <<< "$TARGETS"
fi

[[ -z "$OUTSIDE" ]] && exit 0

echo "⛔ This patch touches files outside the scope you declared for this session:" >&2
printf '  %s\n' $OUTSIDE >&2
echo "" >&2
echo "Declared scope_files:" >&2
sed 's/^/  /' "$SCOPE_FILE" >&2
echo "" >&2
echo "If those files genuinely belong to the task, say so out loud and widen the" >&2
echo "contract before retrying — one line per file:  scope_files: <path>" >&2
echo "If they do not, split the patch. Extra pages, a second copy of the same" >&2
echo "override, or a neighbouring layer 'while we are here' is the rework loop" >&2
echo "this gate exists to stop." >&2
exit 2
