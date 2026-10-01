#!/usr/bin/env bash
#
# stop-guard-codex.sh
# Codex CLI adapter — fires on Stop event.
#
# IMPORTANT: Codex Stop hook requires JSON on stdout (not stderr).
#   {"decision": "allow"}                        → allow stop
#   {"decision": "block", "reason": "..."}       → block, continue agent
#
# Note: if stop-guard does not trigger on code changes, check Codex's
# actual tool names in the transcript and adjust the grep pattern below.

# ── Read input ────────────────────────────────────────────────────────────────

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

if [[ -z "$TRANSCRIPT" ]] || [[ ! -f "$TRANSCRIPT" ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

# ── Layer 1: Were any code files changed? ─────────────────────────────────────
# We parse the transcript to find exact toolCall entries.
EDITED_FILES=$(jq -r '
  (
    select(.type=="assistant")
    | .message.content[]?
    | select(.type=="tool_use" and (.name=="Edit" or .name=="Write" or .name=="MultiEdit" or .name=="str_replace" or .name=="write_file" or .name=="edit_file" or .name=="create_file"))
    | .input.file_path // empty
  ),
  (
    .tool_calls[]?
    | select(.name=="Edit" or .name=="Write" or .name=="MultiEdit" or .name=="str_replace" or .name=="write_file" or .name=="edit_file" or .name=="create_file")
    | .arguments.file_path // .arguments.TargetFile // .args.TargetFile // "«unknown»"
  )
' "$TRANSCRIPT" 2>/dev/null)

# No file writes at all — allow stop
if [[ -z "$EDITED_FILES" ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

# ── Layer 1b: Intersect with actual dirty files in THIS repo ──────────────────
if [[ -n "$REPO_ROOT" ]]; then
  DIRTY=$(git status --porcelain 2>/dev/null | sed 's/^.\{3\}//' | sed 's/.* -> //')

  RELEVANT=""
  HAS_UNKNOWN=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ "$f" == "«unknown»" ]]; then
      HAS_UNKNOWN=1
      continue
    fi
    # Absolute-ise relative paths against the repo root before comparing.
    [[ "$f" != /* ]] && f="${REPO_ROOT}/${f}"
    case "$f" in
      "$REPO_ROOT"/*) rel="${f#"$REPO_ROOT"/}" ;;
      *) continue ;;  # written outside this repo
    esac
    while IFS= read -r d; do
      [[ -n "$d" && "$d" == "$rel" ]] && { RELEVANT+="${rel}"$'\n'; break; }
    done <<< "$DIRTY"
  done <<< "$EDITED_FILES"

  # If we have "«unknown»" (meaning args wasn't present, e.g. in test fixtures),
  # and the working tree is dirty, we treat it as relevant to maintain test compatibility.
  if [[ "$HAS_UNKNOWN" -eq 1 && -n "$DIRTY" ]]; then
    RELEVANT+='«unknown»'$'\n'
  fi

  if [[ -z "$RELEVANT" ]]; then
    echo '{"decision": "allow"}'
    exit 0
  fi
fi

# ── Skip 1: cwd repo is on master/main ────────────────────────────────────────
if [[ -n "$REPO_ROOT" ]]; then
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "main" ]]; then
    echo '{"decision": "allow"}'
    exit 0
  fi
fi

# ── Skip 2: only documentation files were changed ─────────────────────────────
if [[ -n "$REPO_ROOT" ]]; then
  NEEDS_PRECOMMIT=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ "$f" == "«unknown»" ]]; then
      NEEDS_PRECOMMIT=1
      break
    fi
    if [[ "$f" == *.md || "$f" == .claudedocs/* || "$f" == */.claudedocs/* ]]; then
      continue
    fi
    NEEDS_PRECOMMIT=1
    break
  done <<< "$RELEVANT"

  if [[ "$NEEDS_PRECOMMIT" -eq 0 ]]; then
    echo '{"decision": "allow"}'
    exit 0
  fi
fi

# ── Stale-receipt reporting ───────────────────────────────────────────────────
#
# Both functions below answer "WHAT moved?", never "may I stop?" — the decision
# rests on the fingerprint alone. They are reporting only, so a bug in them
# cannot open the gate.
#
# ⚠️ precommit_file_manifest() must stay identical to the copy in
# commands/precommit.sh, and receipt_delta_report() identical across all three
# stop-guard.sh files. tests/precommit.test.sh compares all four textually.
precommit_file_manifest() {
  git status --porcelain -uall 2>/dev/null \
    | sed 's/^.\{3\}//' | sed 's/.* -> //' \
    | while IFS= read -r p; do
        [ -n "$p" ] || continue
        if [ -f "$p" ]; then
          printf 'file=%s\t%s\n' "$(shasum -a 256 "$p" 2>/dev/null | cut -d' ' -f1)" "$p"
        else
          printf 'file=%s\t%s\n' "deleted" "$p"
        fi
      done
}

receipt_delta_report() {   # $1 = receipt path, $2 = this session's id (may be empty)
  local receipt="$1" this_session="$2"
  local ts session branch age when before after p b a changed added gone

  ts=$(sed -n 's/^ts=//p' "$receipt" | head -1)
  session=$(sed -n 's/^session=//p' "$receipt" | head -1)
  branch=$(sed -n 's/^branch=//p' "$receipt" | head -1)

  if [ -n "$ts" ]; then
    age=$(( $(date +%s) - ts ))
    # BSD date takes -r <epoch>; GNU date reads -r as "mtime of file" and wants
    # -d @<epoch>. Try both, then fall back to the raw epoch rather than
    # printing an empty timestamp.
    when=$(date -r "$ts" '+%H:%M:%S' 2>/dev/null \
        || date -d "@$ts" '+%H:%M:%S' 2>/dev/null \
        || echo "epoch ${ts}")
    echo "That PASS was recorded ${when} (${age}s ago)${branch:+ on ${branch}}."
  fi

  # Provenance only when BOTH ids are known and differ. A receipt written before
  # this field existed, or by a hand-run pipeline, says `unknown` — guessing
  # from that is worse than staying quiet.
  if [ -n "$session" ] && [ "$session" != "unknown" ] \
     && [ -n "$this_session" ] && [ "$session" != "$this_session" ]; then
    echo "⚠️  It was earned by a DIFFERENT session (${session}) — another session is"
    echo "    working in this repo, so the changes below may not be yours."
  fi

  # Receipts written before the manifest existed: say so, rather than reporting
  # an empty delta that would read as "nothing changed" while the gate blocks.
  if ! grep -q '^file=' "$receipt" 2>/dev/null; then
    echo "(This receipt predates the file manifest, so the changed files cannot be named.)"
    return 0
  fi

  before=$(sed -n 's/^file=//p' "$receipt" | sort)
  after=$(precommit_file_manifest | sed -n 's/^file=//p' | sort)

  # Keyed on path, then compared on hash, so a modified file is reported once as
  # "changed" instead of twice as gone-and-reappeared.
  hash_of() { printf '%s\n' "$2" | awk -F'\t' -v p="$1" '$2==p {print $1; exit}'; }

  changed=""; added=""; gone=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    b=$(hash_of "$p" "$before"); a=$(hash_of "$p" "$after")
    if [ -z "$b" ]; then
      added="${added}  + ${p}
"
    elif [ "$a" != "$b" ]; then
      changed="${changed}  M ${p}
"
    fi
  done <<< "$(printf '%s\n' "$after" | cut -f2- | sort -u)"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -z "$(hash_of "$p" "$after")" ]; then
      gone="${gone}  - ${p}
"
    fi
  done <<< "$(printf '%s\n' "$before" | cut -f2- | sort -u)"

  if [ -z "${changed}${added}${gone}" ]; then
    # Every pending path and content matches, yet the fingerprint differs — so
    # what moved is something the manifest does not cover: HEAD (a commit,
    # amend, reset, or checkout) or the staged-vs-worktree split.
    echo "No pending file's content differs — so HEAD or the index moved"
    echo "(a commit, amend, reset, or branch switch since that PASS)."
  else
    echo "Changed since that PASS:"
    printf '%s' "${changed}${added}${gone}"
  fi
}

# ── Refusal breaker ───────────────────────────────────────────────────────────
#
# Observed 2026-10-01 (nxl-shipping-client): /precommit wrote status=FAIL for a
# lint failure in a workspace the change never touched, and this guard then
# refused nine consecutive stops with the identical message. Nothing moved
# between them — the agent had already reported the situation and was waiting
# for the user to choose, blocked on input rather than on work — so each
# refusal cost a turn and produced nothing. The user broke the loop by hand.
#
# A gate that can only be satisfied by sweeping unrelated files into the branch
# is not gating the change; it is holding the session hostage. So: when the
# receipt says FAIL *on this exact tree*, and that same receipt has already
# been refused REFUSAL_LIMIT times, the next stop is allowed with a loud
# warning. The receipt still reads FAIL — nothing here is a pass. The count is
# keyed to the receipt's content hash and reset whenever the tree differs from
# it, so an agent that is actually working (editing, re-running /precommit)
# never reaches the limit; only "same FAIL, same tree, again" does.
#
# Returns 0 = give up; sets REFUSAL_COUNT (this refusal's ordinal, 0 when the
# breaker does not apply) and REFUSAL_LIMIT.
#
# ⚠️ Identical across all three stop-guard.sh files; tests/precommit.test.sh
# compares them textually.
precommit_refusal_breaker() {   # $1 = receipt path, $2 = current tree fingerprint
  local receipt="$1" tree="$2" counter="$1-refusals" key prev n
  REFUSAL_COUNT=0
  REFUSAL_LIMIT=2
  if [ "$(sed -n 's/^status=//p' "$receipt" | head -1)" != "FAIL" ] \
     || [ "$(sed -n 's/^tree=//p' "$receipt" | head -1)" != "$tree" ]; then
    rm -f "$counter"
    return 1
  fi
  key=$(shasum -a 256 "$receipt" 2>/dev/null | cut -d' ' -f1)
  prev=$(sed -n 's/^key=//p' "$counter" 2>/dev/null | head -1)
  n=$(sed -n 's/^count=//p' "$counter" 2>/dev/null | head -1)
  [ "$prev" = "$key" ] || n=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$(( n + 1 ))
  printf 'key=%s\ncount=%s\n' "$key" "$n" > "$counter" 2>/dev/null
  REFUSAL_COUNT=$n
  [ "$n" -gt "$REFUSAL_LIMIT" ]
}

# ── Layer 2: Did /precommit actually run, and pass, on THIS tree? ─────────────
# We check the receipt.
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
RECEIPT=""
CURRENT_TREE=""
REFUSAL_COUNT=0
REFUSAL_LIMIT=2
if [[ -n "$GIT_DIR" ]]; then
  RECEIPT="${GIT_DIR}/dotai-precommit"
  if [[ -f "$RECEIPT" ]]; then
    RECEIPT_STATUS=$(sed -n 's/^status=//p' "$RECEIPT" | head -1)
    RECEIPT_TREE=$(sed -n 's/^tree=//p' "$RECEIPT" | head -1)
    CURRENT_TREE=$({
      git rev-parse HEAD 2>/dev/null
      git status --porcelain -uall 2>/dev/null
      # Content, not just the status lines: re-editing an already-dirty file
      # leaves porcelain byte-identical. See precommit_tree_fingerprint() in
      # commands/precommit.sh — this must stay byte-for-byte equivalent to it,
      # or every PASS mismatches and the gate blocks forever.
      git diff HEAD --binary 2>/dev/null
      git ls-files --others --exclude-standard -z 2>/dev/null \
        | xargs -0 shasum -a 256 2>/dev/null
    } | shasum -a 256 | cut -d' ' -f1)
    
    if [[ "$RECEIPT_STATUS" == "PASS" && "$RECEIPT_TREE" == "$CURRENT_TREE" ]]; then
      rm -f "${RECEIPT}-refusals"   # a PASS on this tree ends any refusal streak
      echo '{"decision": "allow"}'
      exit 0
    fi

    # PASS, but on a different tree. The block still happens below; this
    # only collects WHAT moved, because "run it again" with no delta forces
    # a blind full re-run. This CLI shows the model a `reason` string and
    # never stderr, so the report has to travel in there.
    if [[ "$RECEIPT_STATUS" == "PASS" ]]; then
      THIS_SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // .conversationId // empty' 2>/dev/null)
      THIS_SESSION="${THIS_SESSION:-${CODEX_SESSION_ID:-}}"
      STALE_REPORT=$(receipt_delta_report "$RECEIPT" "$THIS_SESSION")
    fi
  fi
fi

# Fallback: check transcript for PRECOMMIT_STATUS=PASS.
#
# Skipped when the receipt already proved a stale PASS: the transcript of any
# session that ran the pipeline contains that line forever, so honouring it
# here would allow every stale stop and make the report below dead code.
if [[ -z "${STALE_REPORT:-}" ]] && grep -q 'PRECOMMIT_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
  echo '{"decision": "allow"}'
  exit 0
fi

if [[ -n "${STALE_REPORT:-}" ]]; then
  _reason="/precommit passed, but the working tree changed afterwards, so that
PASS does not cover the current tree.

${STALE_REPORT}

Run /precommit again."
  jq -cn --arg r "$_reason" '{decision:"block",reason:$r}'
  exit 0
fi

# Give up only for "same FAIL receipt, same tree, again" — see the breaker's
# comment. Codex has no side channel for a warning on an allow, so the
# countdown in the previous refusals' `reason` is the notice the model gets.
if [[ -n "$RECEIPT" && -f "$RECEIPT" ]] && precommit_refusal_breaker "$RECEIPT" "$CURRENT_TREE"; then
  echo '{"decision": "allow"}'
  exit 0
fi

_reason="Code changes detected but quality checks did not pass. Run precommit checks and ensure PRECOMMIT_STATUS=PASS appears in the output."
if [[ "$REFUSAL_COUNT" -gt 0 ]]; then
  _reason="${_reason}

Refusal ${REFUSAL_COUNT} of ${REFUSAL_LIMIT} on this unchanged tree. If the FAIL sits in files this change never touched and cannot be cleared from here, tell the user so — the next stop on this exact tree is let through. The receipt will still say FAIL; that is not a pass."
fi
jq -cn --arg r "$_reason" '{decision:"block",reason:$r}'
exit 0
