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
# Plus one interrupt that is not a gate:
#
#   ENTRY BRIEF — the first edit this session makes inside ANOTHER repository
#      (one that is not the session's cwd repo) is refused ONCE, and the refusal
#      carries that repo's CLAUDE.md and .claude/reviewer-rules.md. The next
#      attempt is not held by it. See "Repo resolution" below for why.
#
# Gate 1 is the front-of-work mirror of stop-guard.sh (see
# plan-grounding-guard.md). Gate 2 exists because the usage report's largest
# remaining friction is scope-shaped, not grounding-shaped: an override
# implemented twice in two layers, a redundant admin page that had to be merged
# back, and a session abandoned outright because the proposed scope had quietly
# grown to include frontend files. "Touch only these files" as prose is a
# request; as a check on every edit it is a contract.
#
# Repo resolution — by the FILE's owner, not by cwd (2026-10-05). Every dotai
# gate used to key off `git rev-parse` in the session cwd, and a write outside
# that tree was waved through as "cannot affect this branch". True for a
# scratch file; false for a file in a SIBLING repo, which enters that repo's
# history with none of its rules in play. nxl-shipping-server MR !891 was
# built from an nxl-shipping-client session: the server's CLAUDE.md (which
# forbids `app(Foo::class)`), its reviewer rules, its memory and its CI
# pre-check were all on the other tree, and the server edits never met
# grounding, scope, or /precommit. Blocking cross-repo edits was rejected —
# one feature routinely spans frontend and backend — so instead every gate
# resolves the repo from the file's path, and the first step into a foreign
# repo hands over that repo's rules. The brief travels on the verified
# channel (exit 2 + stderr) rather than PreToolUse `additionalContext`, which
# is documented but has not been observed delivering text here.
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
#   #4 The entry brief is delivered once; whether it is READ is not verifiable,
#      exactly like a /ground PASS.
#   #5 Transcript lag [probed 2026-10-05]: Claude Code appends a response's
#      blocks to the JSONL only after its tool call has run, so a declaration
#      and an edit in the SAME response meet this hook before the declaration
#      is on disk — that edit is refused once and the retry passes. Observed
#      in the same probe: two assistant text blocks carrying the declaration
#      were never written at all, and the session was unblocked by the USER
#      pasting the declaration — which is why user text counts below. The
#      block message says so. Nothing here can read what the harness has not
#      written.

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

# ── Skip 2: documentation edits ───────────────────────────────────────────────
#
# *.md and anything under .claudedocs/ need no grounding (mirrors stop-guard /
# branch-guard doc pass-through). Do NOT advance the counter for these.

case "$FILE_PATH" in
  *.md|*/.claudedocs/*) exit 0 ;;
esac

# ── Skip 3: writes that cannot reach any branch's diff ────────────────────────
#
# A write inside .git/ cannot be committed and cannot enter history — so
# neither grounding nor scope has anything to protect (the argument
# branch-guard already accepts).

case "$FILE_PATH" in
  */.git/*|*/.git|.git/*|.git) exit 0 ;;
esac

# ── Repo resolution: which repository owns this file? ─────────────────────────
#
# Paths are compared PHYSICALLY because on macOS /tmp is a symlink to
# /private/tmp and a textual prefix test would misfile real in-repo paths. The
# target usually does not exist yet (Write creates it), so resolution walks up
# to the deepest existing ancestor and re-appends the remainder.
#
# Outcomes:
#   REL           path relative to the OWNING repo's root (used in messages)
#   FOREIGN_ROOT  set when the owner is NOT the cwd repo; "" otherwise
#   REL_CWD       the file as seen from the cwd repo root (../other/…) — this,
#                 or the absolute path, is what a scope_files: line must name
#                 for a foreign file. A foreign file is deliberately NOT matched
#                 against patterns relative to its own root: `app/*.php`
#                 declared for the cwd repo must not silently cover a sibling
#                 repo's app/ as well.

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
      # Not this repo. A scratch file, or another repository's working tree?
      OTHER=$(git -C "$SCAN_DIR_P" rev-parse --show-toplevel 2>/dev/null) || OTHER=""
      [[ -n "$OTHER" ]] && OTHER=$(cd "$OTHER" 2>/dev/null && pwd -P)
      # Outside every working tree — cannot enter any history.
      [[ -n "$OTHER" ]] || exit 0
      # Mirrors Skip 4 for the cwd repo: branch-guard owns that case (it, too,
      # resolves the branch from the file's owner), and gating here as well
      # would only deadlock.
      case "$(git -C "$OTHER" rev-parse --abbrev-ref HEAD 2>/dev/null)" in
        master|main) exit 0 ;;
      esac
      FOREIGN_ROOT="$OTHER"
      REL="${ABS_P#"$FOREIGN_ROOT"/}"
      REL_CWD=$(relpath "$REPO_ROOT_P" "$ABS_P")
      ;;
  esac
fi

# ── Skip 4: cwd repo on master/main, and the file is in it ────────────────────
#
# branch-guard already blocks code edits on master/main; requiring grounding
# there too would only deadlock. Mirrors stop-guard Skip 1. A FOREIGN file is
# judged by ITS repo's branch (above), not by cwd's.

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ -z "$FOREIGN_ROOT" && ( "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "main" ) ]]; then
  exit 0
fi

# ── Scope contract helpers ────────────────────────────────────────────────────
#
# The declaration lives in the transcript, written by /ground as one
# `scope_files: <path-or-glob>` line per entry.
#
# Matching (documented in skills/ground/SKILL.md so the declarer knows):
#   exact path        app/Services/Foo.php
#   glob              app/Services/*.php     (bash pattern: * also crosses /)
#   whole subtree     resources/js/   or   resources/js/**
#   another repo      ../other-repo/app/Foo.php   or the absolute path

SCOPE_FILE="/tmp/dotai_scope_${SESSION_ID}"

# Only the conversation's OWN text may declare: the assistant's text blocks and
# the user's messages. Claude Code's JSONL interleaves those with tool results
# and @file attachments, and a `cat` of skills/ground/SKILL.md — or of this
# very hook — puts "scope_files:" and "GROUNDING_STATUS=PASS" into a
# tool_result. Worse, this hook's own block message names both, and a blocked
# hook's stderr is fed back as a tool_result: the first refusal satisfied
# gate 1 for the rest of the session. Observed live 2026-10-05 — a block
# printed a "declared scope" of ~40 junk patterns lifted from tool output.
# Same lesson stop-guard learned about grepping for PRECOMMIT_STATUS=PASS.
#
# Per-CLI: the Codex and agy copies read the raw transcript, because their
# JSONL shapes are not pinned down well enough to filter. extract_scope() below
# is identical across the three (tests/grounding-guard.test.sh locks it).
scope_source() {
  jq -r '
    select(.type=="assistant" or .type=="user")
    | .message.content
    | if type=="string" then .
      else .[]? | select(.type=="text") | .text // empty
      end
  ' "$TRANSCRIPT" 2>/dev/null
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

# A cwd-repo file matches by its repo-relative path. A foreign file matches by
# how it is reached from here (../other/…) or by its absolute path — see the
# repo-resolution note for why not by its own root.
in_scope() {
  if [[ -n "$FOREIGN_ROOT" ]]; then
    scope_allows "$REL_CWD" || scope_allows "$ABS_P"
  else
    scope_allows "$REL"
  fi
}

# How the declarer should name this file in a scope_files: line.
SCOPE_NAME="${REL_CWD:-$REL}"

# Gate-1 markers are read from the same source, for the same reason.
MARKERS=$(scope_source | grep -o 'GROUNDING_STATUS=\(PASS\|SKIP[^"]*\)' 2>/dev/null)

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

SKIPPED=0
if [[ "$COUNT" -lt 1 ]]; then
  if grep -q 'GROUNDING_STATUS=PASS' <<< "$MARKERS"; then
    extract_scope > "$SCOPE_FILE" 2>/dev/null
    echo "1" > "$COUNTER_FILE"   # advance: first edit grounded
    # Fall through to Gate 2 — the declared scope binds the first edit too.
  elif grep -q 'GROUNDING_STATUS=SKIP' <<< "$MARKERS"; then
    # Log the skip reason as a quality signal (overuse => the gate isn't working).
    # session_id is included so each skip can be traced back to its transcript.
    REASON=$(grep 'GROUNDING_STATUS=SKIP' <<< "$MARKERS" | tail -n 1)
    mkdir -p "$(dirname "$SKIP_LOG")" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S')	${SESSION_ID}	${CURRENT_BRANCH}	${FILE_PATH}	${REASON}" >> "$SKIP_LOG" 2>/dev/null
    echo "1" > "$COUNTER_FILE"
    # An explicit SKIP declares no scope; nothing to enforce — but a foreign
    # repo's rules still have to be handed over, so fall through to the brief.
    SKIPPED=1
    [[ -n "$FOREIGN_ROOT" ]] || exit 0
  else
    echo "⛔ First code edit of this session, but grounding was not done." >&2
    echo "Run /ground to verify before writing: restate the task, read 1-2 existing" >&2
    echo "reference files, verify any data/IDs, declare the files you intend to touch" >&2
    echo "as scope_files: lines, then emit GROUNDING_STATUS=PASS." >&2
    echo "For a genuinely trivial edit, emit: GROUNDING_STATUS=SKIP reason=<why>" >&2
    echo "(Only your own message text counts — not file contents you printed.)" >&2
    echo "If you emitted the marker in THIS message, the transcript has not caught up" >&2
    echo "yet: restate it in a short message of its own, then retry the edit." >&2
    if [[ -n "$FOREIGN_ROOT" ]]; then
      echo "" >&2
      echo "Note: this file belongs to another repository (${FOREIGN_ROOT})." >&2
      echo "Declare it as  scope_files: ${SCOPE_NAME}  — as reached from this cwd, or absolute." >&2
    fi
    exit 2
  fi
fi

# ── Entry brief: first step into another repository this session ──────────────
#
# Once per (session, foreign repo). The refusal carries the repo's own rules,
# because nothing else in this session will: the harness loads CLAUDE.md from
# cwd only (and /add-dir does not load one without an env var), the
# reviewer-rules discovery walks up from cwd, memory is keyed to the cwd
# project, and /precommit grades the cwd tree. Skipped when the transcript
# already shows the repo's CLAUDE.md being read — the point is that the rules
# reach the model, not that this hook is the one delivering them.

if [[ -n "$FOREIGN_ROOT" ]]; then
  BRIEF_FILE="/tmp/dotai_foreign_${SESSION_ID}"
  if ! grep -Fqx -- "$FOREIGN_ROOT" "$BRIEF_FILE" 2>/dev/null; then
    printf '%s\n' "$FOREIGN_ROOT" >> "$BRIEF_FILE" 2>/dev/null
    if ! grep -Fq -- "${FOREIGN_ROOT}/CLAUDE.md" "$TRANSCRIPT" 2>/dev/null; then
      FOREIGN_BRANCH=$(git -C "$FOREIGN_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
      {
        echo "⛔ First edit into another repository this session:"
        echo "     ${FOREIGN_ROOT}    (branch: ${FOREIGN_BRANCH:-unknown})"
        echo "   This session's cwd repo is ${REPO_ROOT_P}. That repo's CLAUDE.md, reviewer"
        echo "   rules, memory and /precommit receipt do NOT cover files over there."
        echo ""
        echo "   Before retrying this edit:"
        echo "   • Read the rules below — they are the repo's own, not the cwd repo's."
        echo "   • Its files are declared as   scope_files: ${SCOPE_NAME}   (as reached"
        echo "     from this cwd, or absolute). Patterns relative to ITS root do not count."
        echo "   • /precommit and /ship run INSIDE it:"
        echo "       cd ${FOREIGN_ROOT} && bash ~/.claude/commands/precommit.sh"
        echo "     stop-guard checks that repo's own receipt, separately from this one's."
        echo "   This brief is shown once per repository per session; the retry is not"
        echo "   held by it."
        for rules in "CLAUDE.md" ".claude/reviewer-rules.md"; do
          f="${FOREIGN_ROOT}/${rules}"
          [[ -f "$f" ]] || continue
          echo ""
          echo "──── ${f} ────"
          # Cap each file so one oversized rules file cannot flood the turn.
          if [[ "$(wc -c < "$f" 2>/dev/null)" -gt 65536 ]]; then
            head -c 65536 "$f"
            echo ""
            echo "[… truncated at 64 KiB — read ${f} directly for the rest]"
          else
            cat "$f"
          fi
        done
        if [[ ! -f "${FOREIGN_ROOT}/CLAUDE.md" && ! -f "${FOREIGN_ROOT}/.claude/reviewer-rules.md" ]]; then
          echo ""
          echo "   (That repo has no CLAUDE.md and no .claude/reviewer-rules.md; review"
          echo "    against the generic L1/L2/L3 levels and say so.)"
        fi
      } >&2
      exit 2
    fi
  fi
  # A SKIP session has no scope to enforce; the brief was the only reason to
  # come this far.
  [[ "$SKIPPED" -eq 1 ]] && exit 0
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

in_scope && exit 0

# Cache miss is not proof: the scope may have been amended after it was cached.
# Re-read the transcript (only on the way to a block, so the common path stays a
# single small-file read) and re-check before refusing.
extract_scope > "$SCOPE_FILE" 2>/dev/null
[[ -s "$SCOPE_FILE" ]] || exit 0
in_scope && exit 0

echo "⛔ Outside the scope you declared for this session: ${SCOPE_NAME}" >&2
if [[ -n "$FOREIGN_ROOT" ]]; then
  echo "   (a file in another repository: ${FOREIGN_ROOT})" >&2
fi
echo "" >&2
echo "Declared scope_files:" >&2
sed 's/^/  /' "$SCOPE_FILE" >&2
echo "" >&2
echo "If this file genuinely belongs to the task, say so out loud and widen the" >&2
echo "contract before retrying — emit one line:" >&2
echo "  scope_files: ${SCOPE_NAME}    (with a one-line reason why it is needed)" >&2
echo "If it does not, do not edit it. Extra pages, a second copy of the same" >&2
echo "override, or a neighbouring layer 'while we are here' is the rework loop" >&2
echo "this gate exists to stop." >&2
echo "(If you widened it in THIS message, the transcript has not caught up yet —" >&2
echo " restate it in a short message of its own, then retry.)" >&2
exit 2
