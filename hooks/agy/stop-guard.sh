#!/usr/bin/env bash
#
# stop-guard.sh (agy CLI adapter — Stop event)
#
# agy's hook contract is NOT the Claude/Codex one. Verified against agy CLI:
#   event  : Stop  (there is no "AfterAgent" event — the old registration was
#            silently inert, see CLAUDE.md §agy Hook Contract)
#   stdin  : JSON with camelCase keys — transcriptPath, conversationId,
#            executionNum, terminationReason, error, fullyIdle, workspacePaths
#   stdout : JSON. {"decision":"continue","reason":"..."} blocks the stop and
#            re-enters the loop; ANY other decision lets the agent stop.
#   exit   : NOT the contract. `exit 2` fails open here, which is why every
#            path below must print a decision before exiting.

allow() { printf '%s' '{"decision":"allow"}'; exit 0; }
block() { jq -cn --arg r "$1" '{decision:"continue",reason:$r}'; exit 0; }

command -v jq >/dev/null 2>&1 || { printf '%s' '{"decision":"allow"}'; exit 0; }

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcriptPath // empty' 2>/dev/null)
TERMINATION=$(printf '%s' "$INPUT" | jq -r '.terminationReason // empty' 2>/dev/null)
EXECUTION_NUM=$(printf '%s' "$INPUT" | jq -r '.executionNum // 0' 2>/dev/null)

# Never fight an error or a step-limit stop — forcing "continue" there just
# burns turns on a loop that cannot make progress.
case "$TERMINATION" in
  error|max_steps_exceeded) allow ;;
esac

# Loop brake. Unlike Claude's Stop event there is no `stop_hook_active` flag, so
# an unconditional "continue" would spin forever. Give up after 2 blocks and let
# the user see the unfinished state rather than trapping the session.
[[ "$EXECUTION_NUM" =~ ^[0-9]+$ ]] || EXECUTION_NUM=0
[[ "$EXECUTION_NUM" -ge 3 ]] && allow

[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && allow

# ── Layer 1: Were any code files changed? ─────────────────────────────────────
# We parse the transcript to find exact toolCall entries.
# Format: {"toolCall":{"name":"write_to_file","args":{"TargetFile":"..."}}}
# We extract TargetFile values.
EDITED_FILES=$(jq -r '
  .toolCall? 
  | select(.name=="write_to_file" or .name=="replace_file_content" or .name=="edit_notebook")
  | .args.TargetFile // "«unknown»"
' "$TRANSCRIPT" 2>/dev/null)

# No file writes at all — allow stop
if [[ -z "$EDITED_FILES" ]]; then
  allow
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
    allow  # Nothing this session wrote is pending in this repo
  fi
fi

# ── Skip 1: cwd repo is on master/main ────────────────────────────────────────
if [[ -n "$REPO_ROOT" ]]; then
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "main" ]]; then
    allow
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
    allow  # Documentation-only changes — allow stop
  fi
fi

# ── Layer 2: Did /precommit actually run, and pass, on THIS tree? ─────────────
# We check the receipt.
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
if [[ -n "$GIT_DIR" ]]; then
  RECEIPT="${GIT_DIR}/dotai-precommit"
  if [[ -f "$RECEIPT" ]]; then
    RECEIPT_STATUS=$(sed -n 's/^status=//p' "$RECEIPT" | head -1)
    RECEIPT_TREE=$(sed -n 's/^tree=//p' "$RECEIPT" | head -1)
    CURRENT_TREE=$({ git rev-parse HEAD 2>/dev/null; git status --porcelain 2>/dev/null; } \
      | shasum -a 256 | cut -d' ' -f1)
    
    if [[ "$RECEIPT_STATUS" == "PASS" && "$RECEIPT_TREE" == "$CURRENT_TREE" ]]; then
      allow
    fi
  fi
fi

# Fallback: check transcript for PRECOMMIT_STATUS=PASS
if grep -q 'PRECOMMIT_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
  allow
fi

block "Code was changed but quality checks did not pass. Run /precommit and confirm PRECOMMIT_STATUS=PASS appears in the output before stopping."
