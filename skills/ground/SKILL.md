---
name: ground
description: Forced pre-implementation grounding check — restate the task, read 1-2 existing reference files, verify data/IDs, then emit GROUNDING_STATUS=PASS. The grounding-guard hook blocks the first code edit of a session until this passes.
---

# Ground — Pre-Implementation Grounding Gate

## Purpose

This skill is the **checker** half of a writer/checker split. It runs **before**
any code is written, forcing the grounding that usage data shows is the #1 source
of failure:

- `wrong_approach` (acting before reading existing patterns)
- `misunderstood_request` (building the wrong thing)
- `buggy_code` (writing against unverified data — wrong `factory_id`, `NULL` `design_id`, misread values)

It mirrors the `/precommit` + `stop-guard` pair, but at the **front** of the work:
`grounding-guard.sh` blocks the first non-doc code edit of a session until this
skill emits `GROUNDING_STATUS=PASS` (or an explicit `SKIP`).

## When to Use

- The `grounding-guard` hook blocked an `Edit`/`Write` with "run /ground first".
- You are about to start implementing a non-trivial code change.
- You are about to touch data-sensitive logic (SQL, migrations, seeders, factories,
  anything keyed on IDs like `factory_id` / `design_id`).

## Workflow

Work through every step. Do **not** skip a step because the task "looks simple" —
the skip path is the explicit `SKIP` marker below, not silence.

### Step 0 — Verify git readiness & ensure correct branch

Cheapest check first: it costs one command and prevents work that has to be
redone or unpicked.

```bash
git rev-parse --abbrev-ref HEAD   # identify current branch
git status --short                # working tree state
```

#### Case A — On `main`/`master`

1. `git pull origin main` (or `master`) — **always pull latest before branching**.
2. Suggest a branch name and base point based on the task:
   - **Default**: branch from `main`/`master` (most common).
   - If the task is continuing work on an existing feature branch → suggest that
     branch instead.
   - If the task is a hotfix → may suggest branching from a release tag or branch.
3. **Ask the user to confirm**: "建議從 main 開分支 `feature/xxx`，確認嗎？還是要
   從其他 branch 開？" — the AI suggests, the user decides.
4. `git checkout -b <branch>` from the confirmed base.

#### Case B — Already on a feature branch

Do **not** assume the current branch is correct — verify it matches the task.

1. Compare the branch name against the task description and make a judgment:
   does this branch look like it belongs to the current task?
2. **Ask the user to confirm**: "目前在 `feature/xxx`，這是你要開發的 branch 嗎？"
3. If **yes** → check working tree:
   - Clean → ✅ proceed.
   - Dirty → ⚠️ surface uncommitted changes, ask whether to continue.
4. If **no** →
   - Dirty working tree → tell the user to handle uncommitted changes first
     (stash / commit / discard). Do not switch branches with a dirty tree.
   - Clean → `git checkout main` (or `master`) → follow **Case A** above
     (pull latest, suggest branch, ask user, create branch).

#### Case C — On another branch (release, staging, etc.)

Same as Case B: confirm whether it is the intended branch. If not, switch to
`main`/`master` and follow Case A.

#### General rules

- **Dirty working tree** → always surface it. Unrelated uncommitted changes get
  swept into the next commit and make the diff unreviewable. Ask before continuing.
- **Reviewing or continuing someone's branch** → `git fetch origin` and check out
  the latest first, so you ground against the real current state instead of a
  stale local copy.

### Step 1 — Restate the task (guards `misunderstood_request`)

In one or two sentences, restate what you are about to build **in your own words**,
including the success criteria. If the restatement reveals ambiguity, stop and ask
the user instead of grounding against a guess.

### Step 2 — Read 1–2 existing reference files (guards `wrong_approach`)

Find and **actually Read** 1–2 existing files that share the architectural pattern
you are about to follow (a Service class, a composable, a hook, a migration, etc.).
Name their full paths. "I'll use the standard approach" is not acceptable — name the
file you are copying.

### Step 3 — State the pattern you are following

Explicitly: "I am following the pattern from `<path>`: <one line on the convention>."

### Step 4 — Verify data and IDs (guards `buggy_code`)

If the change touches data — SQL, migrations, seeders, factories, or any logic keyed
on IDs — **verify the real values before writing code**, do not assume them:

- Query/inspect the actual `factory_id`, `design_id`, foreign keys, and relationships.
- Check for `NULL` in columns you will rely on.
- If you read values from a screenshot, echo each `field | value` and confirm against
  the source of truth (DB / logs), not the image.

If the change touches **no** data, state "No data dependency" and move on.

### Step 4.5 — Reviewer Rules Alignment Check (L1 / L2 / L3)

Invoke the **`reviewer-rules`** skill and run its protocol against the change you
are *about to make*, confirming the plan complies before emitting PASS.

That skill is the single source of truth, shared with `/ship` Step 2.5. Do **not**
inline a checklist here — this step and `/ship`'s previously carried separate copies
and they had already drifted apart.

Project-specific rules (table names, lock keys, base classes) are discovered from
the project itself per that protocol. If none are found, say so and review against
the generic L1/L2/L3 levels only — do not apply another project's rules from
memory.

### Step 5 — State assumptions and confidence

List the assumptions you are making and your confidence. If confidence is below 100%,
name the gaps explicitly (per Confidence-Driven Response Validation).

### Step 6 — Emit the machine-readable marker

End your grounding output with **exactly one** of these lines, on its own line, so
`grounding-guard.sh` can detect it:

**Pass** (you completed Steps 1–5) — include the evidence lines first:

```
reference_file: app/Services/ReplenishmentService.php
reference_file: app/Services/ShippingService.php
verified_data: factory_id=4, design_id=181 (confirmed via DB, design_id NOT NULL)
GROUNDING_STATUS=PASS
```

**Skip** (genuinely trivial: typo fix, comment, one-line config, rename) — a reason is
**required**:

```
GROUNDING_STATUS=SKIP reason=single-line typo fix in error message, no logic/data change
```

> The `reason=` is logged by the hook. Overusing `SKIP` defeats the gate and shows up
> in the skip log as a quality signal — only use it for genuinely trivial edits.

## Marker Contract (read by `hooks/claude/grounding-guard.sh`)

- `GROUNDING_STATUS=PASS` — first non-doc code edit of the session is allowed.
- `GROUNDING_STATUS=SKIP reason=<text>` — allowed, and `<text>` is appended to the skip log.
- Absent — the hook blocks the first code edit with `exit 2`.
- The gate only checks the **first** non-`.md` code edit per session; later edits are
  trusted (a deliberate cost/friction tradeoff — see `plan-grounding-guard.md` §4 #1).

## Honesty Note

This gate cannot fully prevent a fabricated `PASS` (emitting the marker without doing
the work) — exactly like `PRECOMMIT_STATUS=PASS`. The evidence lines (`reference_file:`,
`verified_data:`) exist to make a real pass cheap and a fake pass obvious on review.
Grounding is for your own correctness, not to satisfy the hook.

## Integration with Other Skills

```
/feature-dev (or /plan)
   → /ground            ← you are here (grounding-guard enforces this gate)
   → implement
   → /precommit         (stop-guard enforces this gate)
   → git commit
```

- `plan.md` — design before implementation; `/ground` verifies before writing.
- `precommit.md` — the mirror gate at the end of the work.
- `grounding-guard.sh` — the hook that enforces this skill (runs automatically).
