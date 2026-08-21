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

# ── Layer 2: Did /precommit actually run, and pass, on THIS tree? ─────────────
# We check the receipt.
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
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
      echo '{"decision": "allow"}'
      exit 0
    fi
  fi
fi

# Fallback: check transcript for PRECOMMIT_STATUS=PASS
if grep -q 'PRECOMMIT_STATUS=PASS' "$TRANSCRIPT" 2>/dev/null; then
  echo '{"decision": "allow"}'
  exit 0
fi

echo '{"decision": "block", "reason": "Code changes detected but quality checks did not pass. Run precommit checks and ensure PRECOMMIT_STATUS=PASS appears in the output."}'
exit 0
