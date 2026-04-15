---
allowed-tools: Bash(yarn *), Bash(npm *), Bash(npx *), Bash(./vendor/bin/pint *), Bash(php artisan test *), Bash(node -e *), Bash(ls *), Bash(test -f *)
description: Run lint, build, and tests before committing
---

## Context

- Working directory: !`pwd`
- Files present: !`ls artisan package.json vite.config.ts vite.config.js 2>/dev/null || echo "(none)"`
- Available npm scripts (if package.json exists): !`node -e "try{const p=require('./package.json');console.log(Object.keys(p.scripts||{}).join(' '))}catch(e){}" 2>/dev/null || echo "(no package.json)"`

## Your task

Detect the tech stack from the files present, then run quality checks in order.

**Tech stack detection (in priority order):**
- `artisan` exists → **Laravel** (takes priority even if package.json also exists)
- `package.json` + `vite.config.*` exists → **Vue**
- `package.json` exists → **Node.js**

**Commands per stack:**

| Stack | Steps (in order) |
|---|---|
| Laravel | `./vendor/bin/pint` → `php artisan test` |
| Vue / Node.js | `yarn lint:fix` → `yarn build` → best matching test script (see below) |

**Choosing the test script (Vue / Node.js only):**
From the available npm scripts listed above, pick the first match in this order:
`test:unit` → `test:jest` → `jest` → `test` → `vitest`
If none match, skip the test step and note it in the output.

**Rules:**
- Run each step sequentially
- After each step, print `✅ step_name (Xs)` on success or `❌ step_name (Xs)` on failure
- If any step fails, stop running further steps
- **Always** print exactly one status line at the very end, even if a step failed:
  - `PRECOMMIT_STATUS=PASS` — all steps passed
  - `PRECOMMIT_STATUS=FAIL` — one or more steps failed or were skipped due to failure
