#!/usr/bin/env bash
#
# grounding-guard.sh (Codex CLI)
#
# Two gates, mirroring hooks/claude/grounding-guard.sh:
#   1. GROUNDING — blocks the first non-document apply_patch edit of a session
#      until /ground has emitted GROUNDING_STATUS=PASS or =SKIP.
#   2. SCOPE — blocks every later patch touching a file outside the
#      `scope_files:` list declared with that PASS.
# Plus the ENTRY BRIEF: the first patch into ANOTHER repository (not the cwd
# repo) is refused once, with that repo's CLAUDE.md / .claude/reviewer-rules.md
# on stderr. See the Claude copy's "Repo resolution" note for why every gate
# resolves the repo from the file's path rather than from cwd.
#
# One apply_patch can rewrite several files, so gate 2 checks EVERY target and
# refuses on the first one outside the contract: a patch applies whole, so
# allowing it because most of its targets were declared would apply the
# undeclared one too.
#
# Codex's transcript shape is not pinned down, so declarations are read from
# the RAW transcript — tool output that quotes a marker counts. The Claude copy
# filters to conversation text; this one cannot yet.

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
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
REPO_ROOT_P=$(cd "$REPO_ROOT" 2>/dev/null && pwd -P) || REPO_ROOT_P="$REPO_ROOT"

# apply_patch lists each affected path in a *** Add/Update/Delete File header.
# If the patch shape is unknown, treat it as code rather than bypassing the gate.
TARGETS=$(printf '%s\n' "$PATCH" | sed -nE 's/^\*\*\* (Add|Update|Delete) File: //p')
if [[ -n "$TARGETS" ]]; then
  NON_DOC_TARGET=$(printf '%s\n' "$TARGETS" | awk '!/\.md$/ && !/(^|\/)\.claudedocs\// { print; exit }')
  if [[ -z "$NON_DOC_TARGET" ]]; then
    exit 0
  fi
fi

# ── Repo resolution per target ────────────────────────────────────────────────
#
# A target is relative to cwd or absolute. Resolved physically (macOS /tmp →
# /private/tmp), walking up to the deepest existing ancestor. Each target is
# classified as: in the cwd repo (REL = repo-relative), in ANOTHER repo
# (FOREIGN root recorded; matched by the ../other/… form or absolute path, never
# by patterns relative to its own root), or outside every repo (ignored).

relpath() {   # $1 = from directory (absolute), $2 = to path (absolute)
  local from="$1" to="$2" up=""
  while :; do
    if [[ "$from" == "/" ]]; then printf '%s%s' "$up" "${to#/}"; return; fi
    if [[ "$to" == "$from"/* ]]; then printf '%s%s' "$up" "${to#"$from"/}"; return; fi
    from=$(dirname "$from"); up="../$up"
  done
}

# classify <target> → sets T_KIND (cwd|foreign|none), T_REL, T_ABS, T_ROOT, T_CWDREL
classify() {
  local t="$1" abs dir rest dir_p other
  T_KIND=none; T_REL=""; T_ABS=""; T_ROOT=""; T_CWDREL=""
  abs="$t"; case "$abs" in /*) ;; *) abs="$PWD/$abs" ;; esac
  dir=$(dirname "$abs"); rest=$(basename "$abs")
  while [[ ! -d "$dir" && "$dir" != "/" && "$dir" != "." ]]; do
    rest="$(basename "$dir")/$rest"; dir=$(dirname "$dir")
  done
  dir_p=$(cd "$dir" 2>/dev/null && pwd -P) || dir_p="$dir"
  T_ABS="$dir_p/$rest"
  case "$T_ABS" in
    */.git/*|*/.git) return ;;
    "$REPO_ROOT_P"/*) T_KIND=cwd; T_REL="${T_ABS#"$REPO_ROOT_P"/}"; return ;;
  esac
  other=$(git -C "$dir_p" rev-parse --show-toplevel 2>/dev/null) || other=""
  [[ -n "$other" ]] && other=$(cd "$other" 2>/dev/null && pwd -P)
  [[ -n "$other" ]] || return
  case "$(git -C "$other" rev-parse --abbrev-ref HEAD 2>/dev/null)" in
    master|main) return ;;   # branch-guard owns that case
  esac
  T_KIND=foreign; T_ROOT="$other"; T_REL="${T_ABS#"$other"/}"
  T_CWDREL=$(relpath "$REPO_ROOT_P" "$T_ABS")
}

# Which targets are actually gated here, and which foreign roots they enter.
GATED=""; FOREIGN_ROOTS=""
while IFS= read -r target; do
  [[ -z "$target" ]] && continue
  case "$target" in *.md|*/.claudedocs/*|.claudedocs/*) continue ;; esac
  classify "$target"
  case "$T_KIND" in
    cwd)     [[ "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "main" ]] && continue
             GATED+="${target}"$'\n' ;;
    foreign) GATED+="${target}"$'\n'
             grep -Fqx -- "$T_ROOT" <<< "$FOREIGN_ROOTS" || FOREIGN_ROOTS+="${T_ROOT}"$'\n' ;;
  esac
done <<< "$TARGETS"
# Unknown patch shape: gate it as code in the cwd repo, like before.
if [[ -z "$TARGETS" ]]; then
  [[ "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "main" ]] && exit 0
  GATED="«unknown»"
fi
[[ -n "$GATED" ]] || exit 0

# ── Scope contract helpers (extract_scope / scope_allows identical across CLIs) ─
#
# Matching rules are documented in skills/ground/SKILL.md, which is what the
# declarer reads:
#   exact path        app/Services/Foo.php
#   glob              app/Services/*.php     (bash pattern: * also crosses /)
#   whole subtree     resources/js/   or   resources/js/**
#   another repo      ../other-repo/app/Foo.php   or the absolute path

# Raw transcript, with JSON-escaped newlines split (see header).
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

# target_in_scope <target>: cwd files by repo-relative path; foreign files by
# the ../other/… form, the patch's own spelling, or the absolute path.
target_in_scope() {
  classify "$1"
  case "$T_KIND" in
    cwd)     scope_allows "$T_REL" ;;
    foreign) scope_allows "$T_CWDREL" || scope_allows "$1" || scope_allows "$T_ABS" ;;
    *)       return 0 ;;
  esac
}

COUNTER_FILE="/tmp/dotai_grounding_codex_${SESSION_ID}"
[[ -f "$COUNTER_FILE" ]] || echo "0" > "$COUNTER_FILE"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0

SKIPPED=0
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
    SKIPPED=1
    # An explicit SKIP declares no scope — but a foreign repo's rules still
    # have to be handed over, so only a cwd-only patch is allowed right here.
    [[ -n "$FOREIGN_ROOTS" ]] || exit 0
  else
    echo "⛔ First code edit of this session, but grounding was not done." >&2
    echo "Run /ground to verify before writing: restate the task, read 1-2 existing" >&2
    echo "reference files, verify any data/IDs, declare the files you intend to touch" >&2
    echo "as scope_files: lines, then emit GROUNDING_STATUS=PASS." >&2
    echo "For a genuinely trivial edit, emit: GROUNDING_STATUS=SKIP reason=<why>" >&2
    if [[ -n "$FOREIGN_ROOTS" ]]; then
      echo "" >&2
      echo "Note: this patch touches another repository:" >&2
      printf '  %s\n' $FOREIGN_ROOTS >&2
      echo "Declare its files as reached from this cwd (../other/…) or by absolute path." >&2
    fi
    exit 2
  fi
fi

# ── Entry brief: first patch into another repository this session ─────────────
#
# Once per (session, foreign repo); skipped when the transcript already shows
# that repo's CLAUDE.md being read. Nothing else in this session carries those
# rules: Codex reads AGENTS.md from the cwd, and /precommit grades the cwd tree.
BRIEF_FILE="/tmp/dotai_foreign_codex_${SESSION_ID}"
while IFS= read -r root; do
  [[ -z "$root" ]] && continue
  grep -Fqx -- "$root" "$BRIEF_FILE" 2>/dev/null && continue
  printf '%s\n' "$root" >> "$BRIEF_FILE" 2>/dev/null
  grep -Fq -- "${root}/CLAUDE.md" "$TRANSCRIPT" 2>/dev/null && continue
  FOREIGN_BRANCH=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)
  {
    echo "⛔ First patch into another repository this session:"
    echo "     ${root}    (branch: ${FOREIGN_BRANCH:-unknown})"
    echo "   This session's cwd repo is ${REPO_ROOT_P}. That repo's rules, memory and"
    echo "   /precommit receipt do NOT cover files over there."
    echo ""
    echo "   Before retrying this patch:"
    echo "   • Read the rules below — they are the repo's own, not the cwd repo's."
    echo "   • Its files are declared as   scope_files: $(relpath "$REPO_ROOT_P" "$root")/<path>"
    echo "     (as reached from this cwd, or absolute). Patterns relative to ITS root do not count."
    echo "   • /precommit and /ship run INSIDE it:"
    echo "       cd ${root} && bash ~/.codex/prompts/precommit.sh"
    echo "     stop-guard checks that repo's own receipt, separately from this one's."
    echo "   This brief is shown once per repository per session; the retry is not"
    echo "   held by it."
    found=0
    for rules in "CLAUDE.md" ".claude/reviewer-rules.md"; do
      f="${root}/${rules}"
      [[ -f "$f" ]] || continue
      found=1
      echo ""
      echo "──── ${f} ────"
      if [[ "$(wc -c < "$f" 2>/dev/null)" -gt 65536 ]]; then
        head -c 65536 "$f"; echo ""
        echo "[… truncated at 64 KiB — read ${f} directly for the rest]"
      else
        cat "$f"
      fi
    done
    if [[ "$found" -eq 0 ]]; then
      echo ""
      echo "   (That repo has no CLAUDE.md and no .claude/reviewer-rules.md; review"
      echo "    against the generic L1/L2/L3 levels and say so.)"
    fi
  } >&2
  exit 2
done <<< "$FOREIGN_ROOTS"
[[ "$SKIPPED" -eq 1 ]] && exit 0

# ── Gate 2: every target of this patch must sit inside the declared scope ────
#
# No declaration => no constraint. Fails OPEN by design: a /ground output
# written before scope_files existed must not deadlock the session.

[[ -n "$TARGETS" ]] || exit 0
[[ -f "$SCOPE_FILE" ]] || extract_scope > "$SCOPE_FILE" 2>/dev/null
[[ -s "$SCOPE_FILE" ]] || exit 0

outside_targets() {
  local target
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    case "$target" in
      *.md|*/.claudedocs/*|.claudedocs/*) continue ;;
      */.git/*|.git/*) continue ;;
    esac
    target_in_scope "$target" || printf '%s\n' "$target"
  done <<< "$TARGETS"
}

OUTSIDE=$(outside_targets)

# Cache miss is not proof: the scope may have been amended after it was cached.
# Re-read the transcript only on the way to a block, so the common path stays a
# single small-file read.
if [[ -n "$OUTSIDE" ]]; then
  extract_scope > "$SCOPE_FILE" 2>/dev/null
  OUTSIDE=$(outside_targets)
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
echo "(a file in another repository: as reached from this cwd, ../other/…, or absolute)" >&2
echo "If they do not, split the patch. Extra pages, a second copy of the same" >&2
echo "override, or a neighbouring layer 'while we are here' is the rework loop" >&2
echo "this gate exists to stop." >&2
exit 2
