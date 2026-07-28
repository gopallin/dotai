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

# ── Tech stack detection ──────────────────────────────────────────────────────

if [[ -f "artisan" ]]; then
  STACK="laravel"
elif [[ -f "package.json" ]] && ls vite.config.* >/dev/null 2>&1; then
  STACK="vue"
elif [[ -f "package.json" ]]; then
  STACK="node"
else
  echo "❌ Could not detect tech stack (no artisan, package.json, or vite.config.*)"
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
