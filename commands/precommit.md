---
description: Run lint, build, and tests before committing
---

# /precommit — Quality Verification Pipeline

Run a full quality check before committing. Detects the project's tech stack
and runs the appropriate lint → build → test sequence.

## What it does

1. Detect tech stack from the current directory:
   - `artisan` present → **Laravel**: `./vendor/bin/pint` → `php artisan test`
   - `package.json` + `vite.config.*` → **Vue**: `yarn lint:fix` → `yarn build` → `yarn test:unit`
   - `package.json` only → **Node.js**: `yarn lint:fix` → `yarn build` → `yarn test:unit`

2. Run each step and report:
   ```
   ✅ lint_fix (27s)
   ✅ build (8s)
   ✅ test_unit (150s)
   ## Overall: ✅ PASS
   PRECOMMIT_STATUS=PASS
   ```
   On any failure, stop immediately:
   ```
   ❌ test_unit (45s) - 3 tests failed
   ## Overall: ❌ FAIL
   PRECOMMIT_STATUS=FAIL
   ```

3. **(Claude Code only, if LSP is enabled)** Run `npx tsc --noEmit` after the
   stack-specific checks to catch TypeScript type errors before commit.
   Requires `ENABLE_LSP_TOOL=1` in the environment; skipped otherwise.

## Contract with stop-guard

`stop-guard.sh` checks for two signals in the session transcript:
- `/precommit` was called (Layer 2a)
- `PRECOMMIT_STATUS=PASS` appears in output (Layer 2b)

Both must be present for stop-guard to allow the session to end after code
changes. Do not strip or suppress the `PRECOMMIT_STATUS=` line.

## Execution

!bash .claude/commands/precommit.sh
