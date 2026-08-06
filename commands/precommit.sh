#!/usr/bin/env bash
#
# precommit.sh — quality verification pipeline
# Called by the /precommit slash command (commands/precommit.md).
#
# Output contract (stop-guard.sh reads this from the session transcript):
#   ✅ step_name (Xs)          — step passed
#   ❌ step_name (Xs) - reason — step failed; script exits immediately
#   ## Overall: ✅ PASS        — all steps passed
#   PRECOMMIT_STATUS=PASS      — machine-readable marker for stop-guard Layer 2b
#   ## Overall: ❌ FAIL
#   PRECOMMIT_STATUS=FAIL

set -uo pipefail

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

# ── Tech stack detection ──────────────────────────────────────────────────────

if [[ -f "artisan" ]]; then
  STACK="laravel"
elif [[ -f "package.json" ]] && ls vite.config.* >/dev/null 2>&1; then
  STACK="vue"
elif [[ -f "package.json" ]]; then
  STACK="node"
elif compgen -G "tests/*.test.sh" >/dev/null 2>&1; then
  # A shell-tooling repo (dotai itself is one). Without this branch the pipeline
  # fell through to the FAIL arm below, so /precommit could not gate the very
  # project whose purpose is gating — and dotai's own tests/*.test.sh were never
  # run by its own quality gate.
  STACK="shell"
else
  echo "❌ Could not detect tech stack (no artisan, package.json, vite.config.*, or tests/*.test.sh)"
  echo "## Overall: ❌ FAIL"
  echo "PRECOMMIT_STATUS=FAIL"
  exit 1
fi

echo "Detected stack: ${STACK}"
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
echo "## Overall: ✅ PASS"
echo "PRECOMMIT_STATUS=PASS"
