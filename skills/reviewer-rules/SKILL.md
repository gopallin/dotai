---
name: reviewer-rules
description: The L1/L2/L3 code review protocol shared by /ground and /ship. Defines the three review levels and how to discover a project's own reviewer rules. Invoked by /ground Step 4.5 and /ship Step 2.5; also usable directly when reviewing a diff.
---

# Reviewer Rules Protocol

Single source of truth for the L1/L2/L3 review gate. `/ground` (before writing)
and `/ship` (before committing) both run this protocol instead of carrying their
own copies — those copies had already drifted apart.

It lives as a skill, not as a `rules/*.md` file, so that one copy works on all
three CLIs: skills install to a known root on each (`~/.claude/skills/`,
`~/.codex/skills/`, `~/.gemini/config/skills/`), whereas Codex has no `rules/`
mechanism at all and any hardcoded `~/.claude/rules/...` path would be wrong there.

**This file is deliberately stack-agnostic.** It says *how* to review, never *what*
a specific project's tables, locks, or base classes are called. Project-specific
assets belong in that project's own repo (see Discovery below), because dotai's
rules are installed globally and apply to every project on the machine.

## Discovery — where the project's rules come from

Check in this order and use the first hit:

1. `.claude/reviewer-rules.md` in the repo (walk up to the repo root)
2. A `## Reviewer Rules` section in the project's `CLAUDE.md` / `AGENTS.md`
3. Nothing found → **say so explicitly** and review against the generic levels
   below only

Never invent project-specific rules, and never apply another project's rules from
memory. If the review touches assets you cannot see rules for, say which level you
could not check rather than implying full coverage.

## The three levels

**L1 — Architecture & project conventions.** Does the change follow the structure
this repo already uses? Read a sibling file and match it rather than importing a
convention from elsewhere. Watch for parity obligations: mirrored tables, paired
config, generated files that must be regenerated, fixtures that must match a
schema. Parity is the most commonly missed L1 item because the second half of the
pair is usually in a file the change never touched.

**L2 — Stack best practices & security.** Whatever the stack: no N+1 or unbounded
queries, no unparameterised SQL, no unsanitised input crossing a trust boundary,
no secrets or PII in code or logs. Match the project's error-handling and logging
conventions rather than introducing a second style.

**L3 — Production readiness & concurrency.** Is any read-modify-write on shared
state unprotected? Are retried operations (jobs, listeners, webhooks, hooks)
idempotent? Are the operations that will need debugging at 3am actually logged,
with structured context and no secrets?

## Applicability

State plainly when a level does not apply. A shell-and-markdown change has no L3
concurrency surface, and saying "L3: not applicable, no shared mutable state"
is a real review result. Silently skipping a level, or asserting compliance with
rules that were never loaded, is not.

## Outcome

- Violations found → report the exact file and line, and fix the obvious ones
  before proceeding.
- Clean → say which levels were checked and which were not applicable.
