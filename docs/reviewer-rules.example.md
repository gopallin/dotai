# Reviewer Rules — project template

**This file is NOT installed by `install.sh`.** It is a template to copy into a
single project, because everything in it names assets that exist in exactly one
codebase.

## Why it lives here instead of in a dotai skill

These rules previously sat inline in both `skills/ground/SKILL.md` and
`skills/ship/SKILL.md`. Two problems:

1. **Duplicated and already drifting.** The `ship` copy had grown
   `no manual status column updates`, `no app()` and PSR-2; the `ground` copy had
   not. Two copies of a checklist reliably become two different checklists.
2. **Globally installed, project-specific content.** dotai skills install to
   `~/.claude/skills/`, so a rule about the `shipments` table was loaded while
   working on unrelated repos — where it is noise at best and misleading at worst.
   (The installers claimed rules were "path-filtered"; they were not. Nothing
   filtered them, and every rules file loaded in every project.)

`/ground` and `/ship` now invoke the stack-agnostic **`reviewer-rules` skill**,
which discovers project rules from the project itself. It is a skill rather than a
`rules/*.md` file because Codex has no `rules/` mechanism, so one shared file works
across all three CLIs without a per-CLI path.

## How to use this

Copy the section below into the target project as either:

- `.claude/reviewer-rules.md` in the repo root, or
- a `## Reviewer Rules` section in that project's `CLAUDE.md`

Both are discovered automatically — see Discovery in the `reviewer-rules` skill.
Trim anything that does not apply, and keep it in the repo it describes so it
travels with the code and gets reviewed alongside it.

---

## Reviewer Rules

### L1 — Architecture & Parity

- Services expose a single public method `exec()`; use constructor injection.
- State transitions go through `transitionTo()` — never write the status column
  directly.
- No business logic in controllers.
- Do not use the `app()` service locator; inject dependencies.
- **Migration parity:** when adding or dropping columns on `shipments`,
  `shipment_items`, `batches`, `batch_items`, `b2b_batches`, or
  `b2b_batch_items`, make the matching change to the `backup_*` mirror tables.

### L2 — Stack Best Practices

- **Laravel:** avoid N+1 queries; keep Eloquent access efficient; PSR-2 style.
- **NestJS:** proper dependency injection and TypeScript type safety.
- **Vue 3:** Composition API conventions; no unnecessary reactivity overhead.
- **Security:** parameterised queries, input sanitisation, protect PII.

### L3 — Production Readiness & Concurrency

- **Concurrency:** protect read-modify-write on shared state — `stock.usage`,
  counters, `picking_priority` — with a Redis mutex
  (`getRedisLock` / `releaseRedisLock`, key `check_capacity`).
- **Idempotency & observability:** jobs and listeners must be idempotent; log key
  operations with structured context.
