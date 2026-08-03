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

Before emitting PASS, verify that your planned implementation complies with the Reviewer Rules:

1. **L1 (Architecture & Parity):**
   - Use single public method `exec()`, constructor injection, state transitions via `transitionTo()`. No business logic in controllers.
   - **Migration Parity:** If adding/dropping columns on `shipments`, `shipment_items`, `batches`, `batch_items`, `b2b_batches`, or `b2b_batch_items`, ensure matching changes to `backup_*` mirror tables!
2. **L2 (Stack Best Practices):**
   - Laravel: Avoid N+1 queries, keep Eloquent efficient.
   - NestJS / Vue 3: Standard DI and Composition API conventions.
   - Security: Parameterized queries, input sanitization, protect PII.
3. **L3 (Production Readiness & Concurrency):**
   - Concurrency: Protect read-modify-write operations on shared state (`stock.usage`, counters, `picking_priority`) using Redis mutex locks (`getRedisLock`/`releaseRedisLock`, key `check_capacity`).
   - Idempotency & Observability: Ensure jobs/listeners are idempotent and log key operations.

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
