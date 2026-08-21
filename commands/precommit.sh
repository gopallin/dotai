#!/usr/bin/env bash
#
# precommit.sh — quality verification pipeline
# Called by the /precommit slash command (commands/precommit.md).
#
# Human-readable output:
#   ✅ step_name (Xs)          — step passed
#   ❌ step_name (Xs) - reason — step failed; script exits immediately
#   ## Overall: ✅ PASS        — all steps passed
#   PRECOMMIT_STATUS=PASS / PRECOMMIT_STATUS=FAIL
#   PRECOMMIT_MODE=<laravel|vue|node|shell|generic|project>
#
# ── Machine contract with stop-guard.sh: the receipt file, NOT the transcript ──
#
# stop-guard used to grep the session transcript for the literal strings
# `/precommit` and `PRECOMMIT_STATUS=PASS`. That made the gate self-satisfying:
# Claude Code injects a blocked hook's own stderr back into the transcript as a
# user message, and stop-guard's messages contain BOTH literals ("Run /precommit
# …", "…ensure it outputs PRECOMMIT_STATUS=PASS"). So the first block made
# Layer 2a pass forever, the second made Layer 2b pass forever — the gate could
# block at most twice per session and then stood permanently open. Prose that
# merely *mentioned* /precommit satisfied it too, as did an agent typing the
# PASS line by hand without running anything.
#
# The fix: this script writes a receipt only it can write, and stop-guard reads
# that. The receipt is keyed to a fingerprint of the working tree, so a PASS
# earned before further edits does not authorise stopping after them.
#
# ── Why there is no "cannot detect stack → FAIL" arm any more ─────────────────
#
# Observed 2026-08-21, in a repo with no artisan, no package.json and no
# tests/*.test.sh: `/precommit` reported `❌ Could not detect tech stack` and
# FAIL. stop-guard then (correctly) refused the stop, and the agent, with no
# passable gate in reach, **wrote its own `.claude/commands/precommit.sh` into
# that repo and graded its own work with it**. An unrunnable gate does not stay
# unrun; it gets replaced by whatever the agent can satisfy.
#
# Two changes close that off:
#   1. An undetectable stack now falls back to `generic` mode — real,
#      stack-independent checks (conflict markers, parse errors, credentials)
#      that can pass honestly, instead of a dead end.
#   2. A project-local override is honoured only when **git tracks it**, so a
#      script invented mid-session cannot be used to grade that same session.
#
# Generic mode reports PASS while running no build and no tests, which is close
# to the line drawn by GLOBAL_RULES §"Skipped is not passed". It stays on the
# right side of it only because it never hides that: the "no build/test
# pipeline" note is printed on the PASS path, and the receipt records
# `mode=generic`. Nothing was skipped — there was nothing there to run. If a
# project does have a pipeline, teach detection about it; do not let generic
# mode stand in for it.

set -uo pipefail

# ── Receipt ───────────────────────────────────────────────────────────────────

# Fingerprint of everything a commit from here would capture: HEAD, the set of
# pending paths, AND their content. Any subsequent edit, stage, or new untracked
# file changes it.
#
# ⚠️ stop-guard.sh recomputes this with an identical block. The two are locked
# together by tests/precommit.test.sh, which runs this script and then the real
# guard against the same tree — if the algorithms drift, that test fails. They
# are duplicated rather than sourced because the two files install into
# different trees (and different trees again on Codex and agy), so there is no
# path both can rely on.
precommit_tree_fingerprint() {
  {
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
  } | shasum -a 256 | cut -d' ' -f1
}

# Written to the git dir (not the worktree): never committed, per-clone, and
# `git rev-parse --git-dir` resolves correctly inside linked worktrees, which a
# hardcoded "$REPO_ROOT/.git" does not.
write_receipt() {
  local status="$1" mode="${2:-${STACK:-unknown}}" gitdir
  gitdir=$(git rev-parse --git-dir 2>/dev/null) || return 0  # not a repo — nothing to gate
  {
    echo "status=${status}"
    echo "mode=${mode}"
    echo "tree=$(precommit_tree_fingerprint)"
    echo "ts=$(date +%s)"
  } > "${gitdir}/dotai-precommit"
}

# ── Project-local override — tracked only ─────────────────────────────────────
#
# A project may ship its own pipeline at .claude/commands/precommit.sh. It runs
# instead of the stack detection below, but ONLY if git tracks it: an untracked
# script is indistinguishable from one the current session just invented, and a
# gate an agent wrote for itself is not a gate.
#
# This script never creates that file, and neither should anything else. If the
# stack is not detectable, generic mode below is the answer — not a new script
# in someone else's repo.
#
# The override needs no knowledge of the receipt protocol: exit 0 means pass,
# non-zero means fail, and this wrapper records the receipt either way. If it
# does print its own PRECOMMIT_STATUS= line, that line is honoured — but a
# declared PASS with a non-zero exit is treated as FAIL.

if [[ -z "${DOTAI_PRECOMMIT_DISPATCHED:-}" ]]; then
  export DOTAI_PRECOMMIT_DISPATCHED=1   # an override that copies this file cannot loop
  _root=$(git rev-parse --show-toplevel 2>/dev/null) || _root=""
  _override="${_root:-.}/.claude/commands/precommit.sh"
  if [[ -n "$_root" && -f "$_override" ]]; then
    if git -C "$_root" ls-files --error-unmatch ".claude/commands/precommit.sh" >/dev/null 2>&1; then
      echo "Using project-local pipeline: .claude/commands/precommit.sh"
      echo ""
      _log=$(mktemp -t dotai-precommit)
      bash "$_override" 2>&1 | tee "$_log"
      _rc=${PIPESTATUS[0]}
      _declared=$(sed -n 's/^PRECOMMIT_STATUS=//p' "$_log" | tail -1)
      rm -f "$_log"
      if [[ -n "$_declared" ]]; then
        _status="$_declared"
        if [[ "$_status" == "PASS" && "$_rc" -ne 0 ]]; then
          echo ""
          echo "❌ Project pipeline declared PASS but exited ${_rc} — recording FAIL."
          _status=FAIL
        fi
      else
        [[ "$_rc" -eq 0 ]] && _status=PASS || _status=FAIL
        echo ""
        if [[ "$_status" == PASS ]]; then echo "## Overall: ✅ PASS"; else echo "## Overall: ❌ FAIL"; fi
        echo "PRECOMMIT_STATUS=${_status}"
        echo "PRECOMMIT_MODE=project"
      fi
      write_receipt "$_status" project
      [[ "$_status" == PASS ]] || exit 1
      exit 0
    fi
    echo "⚠️  Ignoring UNTRACKED .claude/commands/precommit.sh."
    echo "    A project pipeline has to be committed to count. If this file was"
    echo "    just generated to satisfy the gate, delete it — generic mode below"
    echo "    is the supported fallback."
    echo ""
  fi
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

run_step() {
  local name="$1"; shift
  local start end elapsed output rc
  start=$(date +%s)
  output=$("$@" 2>&1)
  rc=$?
  end=$(date +%s)
  elapsed=$(( end - start ))
  if [[ $rc -eq 0 ]]; then
    echo "✅ ${name} (${elapsed}s)"
  else
    echo "❌ ${name} (${elapsed}s)"
    echo "$output" | head -30
    echo ""
    echo "## Overall: ❌ FAIL"
    echo "PRECOMMIT_STATUS=FAIL"
    echo "PRECOMMIT_MODE=${STACK}"
    write_receipt FAIL
    exit 1
  fi
}

# ── Shell-repo steps ──────────────────────────────────────────────────────────
#
# Both return non-zero on failure so run_step reports ❌ and aborts. Never add
# `|| true` here: a step that cannot fail is not a gate, and a pipeline that
# always prints PASS is worse than no pipeline — it launders "skipped" into
# "passed", which is the one outcome dotai exists to prevent.

shell_syntax() {
  local f rc=0 list
  list=$(git ls-files '*.sh' 2>/dev/null) || list=""
  [[ -n "$list" ]] || list=$(find . -name '*.sh' -not -path './.git/*' 2>/dev/null)
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    bash -n "$f" || { echo "syntax error: $f"; rc=1; }
  done <<< "$list"
  return $rc
}

shell_tests() {
  local t rc=0 out files
  shopt -s nullglob
  files=(tests/*.test.sh)
  shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "no tests/*.test.sh found — refusing to report PASS on zero tests"
    return 1
  fi
  for t in "${files[@]}"; do
    if out=$(bash "$t" 2>&1); then
      echo "  ✓ ${t}  $(printf '%s' "$out" | tail -1)"
    else
      echo "  ✗ ${t}"
      printf '%s\n' "$out" | tail -15
      rc=1
    fi
  done
  echo "  ${#files[@]} test file(s) executed"
  return $rc
}

# ── Generic steps — no project pipeline, no project config ────────────────────
#
# Scope: only what is pending in the working tree, i.e. exactly what a commit
# from here would capture. Checking the whole repo would make the pipeline's
# runtime a function of repo size and would fail on pre-existing dirt nobody
# touched — the same mistake stop-guard's Layer 1b already corrects for.
#
# Nothing here writes to the repo. That rules out `python -m py_compile`
# (it drops __pycache__/) — the `ast.parse` form leaves no artifact.

GENERIC_FILES=()

generic_collect() {
  local f
  # -uall so files inside a new untracked directory are listed individually;
  # plain porcelain collapses them to "dir/", which the -f test then discards.
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ -f "$f" ]] || continue          # skips deletions and directory entries
    GENERIC_FILES+=("$f")
  done < <(git status --porcelain -uall 2>/dev/null \
             | sed 's/^.\{3\}//' | sed 's/.* -> //' | sed 's/^"//; s/"$//' | sort -u)
}

generic_conflict_markers() {
  local f rc=0
  [[ ${#GENERIC_FILES[@]} -gt 0 ]] || return 0
  for f in "${GENERIC_FILES[@]}"; do
    if grep -IqE '^(<{7}|>{7})( |$)' "$f" 2>/dev/null; then
      echo "unresolved merge conflict markers: $f"
      rc=1
    fi
  done
  return $rc
}

generic_syntax() {
  local f rc=0 checked=0 skipped=0
  if [[ ${#GENERIC_FILES[@]} -eq 0 ]]; then
    echo "  no pending files to parse"
    return 0
  fi
  for f in "${GENERIC_FILES[@]}"; do
    case "$f" in
      *.sh|*.bash)
        bash -n "$f" 2>&1 || { echo "syntax error: $f"; rc=1; }
        checked=$(( checked + 1 )) ;;
      *.json)
        if command -v jq >/dev/null 2>&1; then
          jq empty "$f" >/dev/null 2>&1 || { echo "invalid JSON: $f"; rc=1; }
          checked=$(( checked + 1 ))
        else
          skipped=$(( skipped + 1 ))
        fi ;;
      *.py)
        if command -v python3 >/dev/null 2>&1; then
          python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" >/dev/null 2>&1 \
            || { echo "syntax error: $f"; rc=1; }
          checked=$(( checked + 1 ))
        else
          skipped=$(( skipped + 1 ))
        fi ;;
      *)
        skipped=$(( skipped + 1 )) ;;
    esac
  done
  echo "  ${checked} parsed, ${skipped} skipped (no parser for that file type)"
  return $rc
}

generic_secret_scan() {
  local f rc=0 lines pat
  # Same shapes secret-redact.sh scrubs from tool output. Here the point is to
  # stop them entering a commit, where deleting them later achieves nothing.
  pat='(github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{30,}|glpat-[A-Za-z0-9_-]{16,}|sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
  [[ ${#GENERIC_FILES[@]} -gt 0 ]] || return 0
  for f in "${GENERIC_FILES[@]}"; do
    lines=$(grep -InE "$pat" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ',')
    if [[ -n "$lines" ]]; then
      # File and line only — never the match. Echoing it would put the
      # credential in the transcript, which is the one thing that cannot be
      # undone (see CLAUDE.md §Credential handling).
      echo "possible credential in ${f} at line(s): ${lines%,}"
      rc=1
    fi
  done
  return $rc
}

# ── Tech stack detection ──────────────────────────────────────────────────────

if [[ -f "artisan" ]]; then
  STACK="laravel"
elif [[ -f "package.json" ]] && ls vite.config.* >/dev/null 2>&1; then
  STACK="vue"
elif [[ -f "package.json" ]]; then
  STACK="node"
elif compgen -G "tests/*.test.sh" >/dev/null 2>&1; then
  # A shell-tooling repo (dotai itself is one). Without this branch the pipeline
  # fell through to generic mode, so /precommit could not gate the very project
  # whose purpose is gating — and dotai's own tests/*.test.sh were never run by
  # its own quality gate.
  STACK="shell"
else
  STACK="generic"
fi

if [[ "$STACK" == "generic" ]]; then
  echo "Detected stack: generic (no artisan, package.json, or tests/*.test.sh)"
else
  echo "Detected stack: ${STACK}"
fi
echo ""

# ── Run stack-specific steps ──────────────────────────────────────────────────

case "$STACK" in
  laravel)
    run_step "lint_fix"  ./vendor/bin/pint
    run_step "test"      php artisan test
    ;;
  vue|node)
    run_step "lint_fix"  yarn lint:fix
    run_step "build"     yarn build
    run_step "test_unit" yarn test:unit
    ;;
  shell)
    # Printed before the step, not inside it: run_step swallows a passing step's
    # output, and "tests passed" without a count is the same claim as "no tests
    # ran". The number has to be visible on the success path too.
    shopt -s nullglob; _t=(tests/*.test.sh); shopt -u nullglob
    echo "Test files: ${#_t[@]}"
    run_step "shell_syntax" shell_syntax
    run_step "tests"        shell_tests
    ;;
  generic)
    echo "⚠️  This repo has no build or test pipeline: nothing was built and no"
    echo "    tests were run. Generic checks only — see the note above PASS."
    generic_collect
    echo "Pending files inspected: ${#GENERIC_FILES[@]}"
    echo ""
    run_step "conflict_markers" generic_conflict_markers
    run_step "file_syntax"      generic_syntax
    run_step "secret_scan"      generic_secret_scan
    ;;
esac

# ── Optional: LSP TypeScript typecheck ───────────────────────────────────────
#
# Runs only when ENABLE_LSP_TOOL=1 and a tsconfig.json exists in the current
# directory or any parent. Requires npx / tsc to be on PATH.
# Errors are printed but do NOT fail the pipeline (advisory only) — the full
# TypeScript build already ran in the build step above.

if [[ "${ENABLE_LSP_TOOL:-0}" == "1" ]] && git rev-parse --show-toplevel >/dev/null 2>&1; then
  TS_ROOT=$(git rev-parse --show-toplevel)
  if [[ -f "$TS_ROOT/tsconfig.json" ]] || [[ -f "tsconfig.json" ]]; then
    start=$(date +%s)
    if npx tsc --noEmit 2>&1 | head -20; then
      elapsed=$(( $(date +%s) - start ))
      echo "✅ tsc_typecheck (${elapsed}s)"
    else
      elapsed=$(( $(date +%s) - start ))
      echo "⚠️  tsc_typecheck (${elapsed}s) — type errors found (advisory, see above)"
    fi
  fi
fi

# ── All steps passed ──────────────────────────────────────────────────────────

echo ""
if [[ "$STACK" == "generic" ]]; then
  echo "NOTE: generic mode — no build ran, no tests ran, because this repo has"
  echo "      neither. This PASS covers conflict markers, parse errors and"
  echo "      credential shapes in the pending files, and nothing more."
fi
echo "## Overall: ✅ PASS"
echo "PRECOMMIT_STATUS=PASS"
echo "PRECOMMIT_MODE=${STACK}"
write_receipt PASS
