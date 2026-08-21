---
description: Run lint, build, and tests before committing
---

# /precommit — Quality Verification Pipeline

Run a full quality check before committing. Detects the project's tech stack
and runs the appropriate lint → build → test sequence.

## What it does

1. If the project ships a **git-tracked** `.claude/commands/precommit.sh`, run
   that instead — the project's own pipeline wins. Untracked copies are ignored
   (see the rule below).

2. Otherwise detect the tech stack from the current directory:
   - `artisan` present → **Laravel**: `./vendor/bin/pint` → `php artisan test`
   - `package.json` + `vite.config.*` → **Vue**: `yarn lint:fix` → `yarn build` → `yarn test:unit`
   - `package.json` only → **Node.js**: `yarn lint:fix` → `yarn build` → `yarn test:unit`
   - `tests/*.test.sh` present → **shell**: `bash -n` on every `*.sh` → run every test file
   - none of the above → **generic** (see below)

3. Run each step and report:
   ```
   ✅ lint_fix (27s)
   ✅ build (8s)
   ✅ test_unit (150s)
   ## Overall: ✅ PASS
   PRECOMMIT_STATUS=PASS
   PRECOMMIT_MODE=vue
   ```
   On any failure, stop immediately:
   ```
   ❌ test_unit (45s) - 3 tests failed
   ## Overall: ❌ FAIL
   PRECOMMIT_STATUS=FAIL
   PRECOMMIT_MODE=vue
   ```

4. **(Claude Code only, if LSP is enabled)** Run `npx tsc --noEmit` after the
   stack-specific checks to catch TypeScript type errors before commit.
   Requires `ENABLE_LSP_TOOL=1` in the environment; skipped otherwise.

## ⛔ Never create a precommit script in the target repo

If no stack is detected, that is **not** an invitation to write
`.claude/commands/precommit.sh`, a `Makefile`, a test runner, or any other file
into the repo so the gate has something to pass. Generic mode exists precisely so
there is always something honest to run. A gate the agent authored for itself in
the same session is not a gate, and the installed pipeline enforces that
mechanically: a project override counts **only if git tracks it**, so a
freshly-invented script is ignored with a warning.

This happened on 2026-08-21 — detection failed, `/precommit` returned FAIL,
stop-guard refused the stop, and the agent wrote its own precommit script into
the repo and graded its own work with it. Hence both the generic fallback and
the tracked-only rule.

## Generic mode — what a stackless repo gets

No build, no tests, because there are none to run. What it does check, over the
files pending in the working tree (`git status`, including untracked):

| Step | Fails when |
|---|---|
| `conflict_markers` | a pending file still contains `<<<<<<<` / `>>>>>>>` |
| `file_syntax` | `*.sh` fails `bash -n`, `*.json` fails `jq empty`, `*.py` fails to parse |
| `secret_scan` | a pending file contains a credential shape (`ghp_`, `glpat-`, `sk-ant-`, `AKIA…`, `xox…`, PEM key header) |

It prints, on the PASS path, that nothing was built and no tests were run, and
records `mode=generic` in the receipt. That honesty is the whole reason a PASS
here does not violate GLOBAL_RULES §"Skipped is not passed" — nothing was
skipped, there was nothing there. **Generic mode is not a substitute for a real
pipeline:** if the project does have one, teach detection about it rather than
letting generic mode stand in.

Generic mode writes nothing to the repo — the Python check uses `ast.parse`
rather than `py_compile` specifically so no `__pycache__/` appears.

## Contract with stop-guard

`stop-guard.sh` reads the receipt this pipeline writes at
`$(git rev-parse --git-dir)/dotai-precommit`:

```
status=PASS|FAIL
mode=laravel|vue|node|shell|generic|project
tree=<sha256 of HEAD + git status --porcelain>
ts=<epoch seconds>
```

It does **not** grep the transcript — that was self-satisfying, because the
guard's own block message names both `/precommit` and `PRECOMMIT_STATUS=PASS`.
The `tree=` fingerprint expires the PASS as soon as anything else is edited.
Consequences: do not hand-write `PRECOMMIT_STATUS=PASS`, it grants nothing; and
run `/precommit` **after** the last edit, not before.

## Execution

!bash -c 'exec bash "$HOME/.claude/commands/precommit.sh"'
