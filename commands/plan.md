---
name: plan
description: Single-session design planning on any subject, code or not. One-question-at-a-time grilling loop, then a coverage check (constraints/success, options and tradeoffs, how it fails) → save as plan-{key}.md and optionally decompose into context-window-sized tracer-bullet tickets. Waits for "approved" before asking to save. Routes to /map when too much is still undecided, and collapses a cleared map into a spec with --from-map.
---

# /plan — Design Planning Workflow

You are a structured planning partner. Execute this workflow:

## Step 0: Initialize & Detection

1. Work out the **plan key**. In a git repo on a feature branch it is the branch name
   in snake_case (`feature/smart-replenishment` → `plan-smart-replenishment.md`).
   **Outside a repo, or when the subject has nothing to do with the current one**, it
   is a kebab-case slug of the subject — the workflow does not require a repo, and the
   subject does not have to be code. In that case ask where the file should live and
   default to `~/.claudedocs/`; a personal plan does not belong in a work repository.

   `{plan-key}` and `{map-key}` below mean that value.

2. **Check for a map** (`--from-map` Mode):
   - Look for `map-{map-key}.md` (`.claudedocs/` first, then the current directory)
   - If found, or if the user passed `--from-map`: the grilling already happened inside
     the map, so **skip Steps 1–3 entirely** and go to [Step 3](#step-3-from-map--collapse-a-cleared-map-into-a-plan).
   - If no map exists and `--from-map` was passed: say so and stop. Do not fall back to
     a fresh grilling session — the user asked to collapse a map, not to plan one.

3. **Check for existing plan** (Review Mode):
   - Look for `plan-{plan-key}.md` in the current directory
   - If found: Display the existing plan summary and ask: **"Here's the current plan. Want to make changes, or is this approved?"**
     - If user says `approved` or `no changes` → End with summary
     - If user describes changes → re-open just that topic in the Step 1 loop; leave the rest of the plan alone
     - Return to this question after each revision
   
   **Review Mode Purpose:**
   - Avoid re-planning: If a branch already has a plan, review it instead of starting from scratch.
   - Enable incremental updates: Users can refine one topic without redoing the entire plan.
   - Preserve decisions: Already-decided content is not overthrown.

4. **No existing plan found** (New Design Mode):
   - If the user provided a description in the `/plan` command (e.g., `/plan smart replenishment`), start with that
   - If no description: ask the user: **"What are we designing today?"**
   - Proceed to Step 1 (grilling loop, then the Step 2 coverage check)

---

## The "this is a map, not a plan" rule

Applies throughout the Step 1 grilling loop. Read it once, obey it throughout.

`/plan` assumes the route is describable and the whole thing fits one session. When
the user answers "I don't know yet" / "not decided yet" / "depends", that is a
**result, not a failure**: do not push for a guess, and do not invent a placeholder
to keep the plan moving — a fabricated constraint gets built on. Note it and move to
the next question.

**Once three or more questions have come back undecided, stop planning.** That much
fog means the answers are entangled — the first one settled will reshape the rest —
and a plan written over it is a waterfall. Say so, list what is
undecided, and offer `/map`, which exists for exactly this shape:

> Three things here are still undecided: {list}. That is a map, not a plan — the
> answers depend on each other, so planning around them now will not survive the
> first one. Want to run `/map` instead?

If the user chooses to continue anyway, that is their call: proceed, and record the
undecided items verbatim in the plan summary as open questions.

---

## Step 1: The Grilling Loop

**Mission:** Interview the user until the plan has real decisions in it.

**One question at a time.** Ask, wait, and let the answer decide what to ask next —
follow the user's thread rather than a template's running order. After each answer,
decide whether you need clarification or can move on.

**Provide a recommended answer** with every question — your best guess from the
context, so the user can agree, disagree, or correct rather than compose from
nothing.

**Find facts yourself.** If the working directory can answer a question — what the
code already does, how a table is shaped, what a test currently asserts — go and read
it instead of asking. Ask the user only what is genuinely theirs to decide.

**Avoid scope creep.** When the user raises implementation detail mid-loop, note it
and offer to revisit after approval rather than following it down.

The subject does not have to be code. Where an engineering example appears below it
is an illustration, not a scope.

**Loop exit condition:** you believe the plan is decided. Before you act on that
belief, run Step 2 — the whole point of the check is that "I think we're done" is
exactly when the gaps are invisible.

---

## Step 2: Coverage Check Before You Wrap

A free-running interview has no coverage guarantee: it explores what got mentioned,
and silently skips what did not. Before summarising, confirm all three of these were
actually reached. **This is a checklist, not a running order** — the conversation goes
wherever it goes; this is the gate at the end of it.

The parentheses are what each looks like when the subject is code.

1. **Constraints, and what success looks like** — the core problem, who it affects,
   the success metric, the hard limits, and what happens if nothing is done.
   (Acceptance criteria, deadline, budget, technical limits.)

2. **Options and their tradeoffs** — at least 2–3 viable directions, each with what it
   costs and the assumption it rests on, and which one was chosen.
   (Technical approaches; performance, complexity, dependencies, team skill.)

3. **How it fails, and how you would know** — at least three failure modes, the
   boundary conditions, and what would have to be true for you to believe it worked.
   (Edge cases, concurrency, integration points; unit / integration / performance
   tests.)

**A face that was not reached is a question, not a section to write.** Go back into
the Step 1 loop and ask it. Do not fill the gap yourself, and do not reopen a face
that was covered — re-asking settled ground is how a short plan becomes a long one.

> The three faces are named identically to `/map`'s charting coverage check — one
> concept, one shape, whichever command you are in. What each face *does* differs by
> command (there, an unreached face becomes a ticket or a patch of fog), so only the
> names are shared, and `tests/map-command.test.sh` keeps them in step rather than
> anyone remembering to.

---

## Step 3: `--from-map` — Collapse a Cleared Map Into a Plan

Reached from Step 0 when a `map-{map-key}.md` exists. Steps 1–2 are skipped: the
grilling already happened, one decision per session, inside the map, and the coverage
check ran while it was being charted.

1. **Read the map**, then read the **Answer** section of each closed ticket. This is
   the one time reading every ticket is correct — collapsing them is the whole job.
2. **Check the map is actually clear.** If any ticket is still `open`/`claimed`, or
   **Not Yet Specified** is non-empty, stop and say what is outstanding — a spec
   written over open decisions is the thing the map existed to prevent. Offer to run
   `/map` on the remaining tickets instead.
3. **Collapse, do not concatenate.** Sort the decisions into the Step 4 structure
   below: constraints and success criteria into the first section, the chosen
   direction and the alternatives it beat into the second, failure modes and the test
   strategy into the third. A decision that fits none of the three is usually a domain
   fact — it belongs in `CONTEXT.md` (Step 8), not the plan.
4. Carry **Out Of Scope** across verbatim as its own section. It is the cheapest thing
   in the plan and the first thing a reader asks about.
5. Every claim in the plan must trace to a closed ticket. Cite it inline as
   `(→ {NN} {ticket title})`. **Do not introduce a decision that no ticket made** — if
   collapsing surfaces a gap, that is a ticket the map missed; name it and ask.

Then continue at Step 5 (approval). Steps 6–8 are unchanged: save, decompose into
implementation tickets, update the glossary.

---

## Step 4: Plan Summary

Once the coverage check passes, display the full plan summary in this structure.
The output has three sections because a reader needs the structure — that is not the
order the questions were asked in, and it never was:

```markdown
# Plan: {Feature Name}

## Constraints & Success Criteria
- [What has to be true, and what success looks like]

## Chosen Direction
- **Chosen Approach:** [Brief description]
- **Alternatives considered:**
  - [Alt 1 + tradeoffs]
  - [Alt 2 + tradeoffs]

## How It Fails
- [Failure modes and boundary conditions]
- **Test Plan:**
  - [Unit tests]
  - [Integration tests]
  - [Performance checks]

## Out of Scope
<!-- --from-map only: carried across from the map. Omit the section otherwise. -->
- [What was ruled beyond the destination, and why]
```

---

## Step 5: Wait for Approval

Display:
> **Plan is ready.** Review the summary above and reply with `approved` when ready, or describe any changes needed.

**Loop:** 
- If user says `approved` → Proceed to Step 6 (ask about saving)
- If user says anything else → Treat it as a request to revise a specific section and re-enter the relevant block's loop.

---

## Step 6: Ask About Saving (User-Initiated Output)

Once the plan is approved, ask:

> **Want me to save this plan?**
> - Save to `plan-{plan-key}.md` file
> - Save + decompose into tickets (recommended for multi-session work)
> - Skip for now

**Important behavior:**
- If user says "Skip" or declines: **Do NOT auto-save**. The plan stays in conversation memory and user can request saving later anytime.
- If user chooses file save: Write `plan-{plan-key}.md` in the current directory (use `.claudedocs/` if that directory exists — keep the plan and tickets together)
- If user chooses save + tickets: Save the plan file, then proceed to Step 7

**Plan content persistence:**
- If user declines saving initially, the complete plan remains in memory
- User can later ask "save the plan" or "decompose into tickets" without re-running the entire planning workflow
- Always write the latest plan version if content changed during discussion

---

## Step 7: Ticket Decomposition (only if chosen)

**Code only.** If the subject is not software there is nothing to slice into vertical
slices — do not offer this step, and do not invent an implementation phase to have
somewhere to go. The approved plan is the deliverable; stop after Step 6.

Decompose the approved plan into **tracer-bullet tickets** — each ticket is a narrow but complete vertical slice through all layers the feature touches (e.g., migration → model → service → API → UI → tests), so a completed ticket is demoable or verifiable on its own.

**Sizing rule (the whole point):** each ticket must fit in a **single fresh context window** — one work session, roughly ≤5 files changed, one acceptance scenario. If a slice feels bigger, split it. For wide refactors, use expand–contract sequencing (add new path → migrate callers → remove old path) so tests stay green at every ticket boundary.

**Location:** tickets live next to the plan file:
```
{plan-dir}/tickets/{plan-key}/
├── INDEX.md
├── 01-{slug}.md
├── 02-{slug}.md
└── ...
```

**Numbering = dependency order.** Wire explicit `blocked-by` references; a ticket with no unfinished blockers is on the *frontier* and ready to pick up.

**`INDEX.md` format** (the map — an index, never a restatement of ticket detail):

```markdown
# Tickets: {Feature Name}

**Plan:** ../../plan-{plan-key}.md
**Destination:** {one-paragraph goal + success criteria}

## Tickets

| # | Title | Status | Blocked by |
|---|-------|--------|------------|
| 01 | {title} | todo | — |
| 02 | {title} | todo | 01 |

## Decisions So Far
<!-- one line appended per completed ticket: "01: {decision gist}" -->
```

**Ticket file format:**

```markdown
---
ticket: 02
title: {title}
status: todo        # todo | in-progress | done
blocked-by: [01]
---

## Goal
{One sentence: the end-to-end behavior this slice delivers.}

## Scope
- {Files/layers expected to change}

## Acceptance Criteria
- [ ] {Observable, testable behavior}

## Out of Scope
- {What belongs to other tickets}

## Decision Log
<!-- filled at completion: non-obvious decisions made while implementing -->
```

After writing all files, show the ticket table and finish with:

> **Tickets ready.** Start each work session with `/next-ticket` in a fresh session — it reads only the index and one ticket, keeping context small.

---

## Step 8: Domain Glossary (CONTEXT.md)

Runs after approval, regardless of the save choice in Step 6. **Skip it entirely when
the plan is not about this repo** — a glossary belongs to a codebase, and importing
one into an unrelated project is worse than not having it.

1. **If the project has a `CONTEXT.md` glossary:** append any domain terms this plan introduced or clarified — `**{term}** — {one-line definition}`. Do nothing if no new terms surfaced.
2. **If no `CONTEXT.md` exists** and this plan coined 3+ domain terms: offer to create one, and add an `@CONTEXT.md` import line to the project's `CLAUDE.md`. The import is the enforcement — the glossary then loads deterministically every session instead of relying on AI compliance.

Glossary entries are definitions only — no implementation details, no status. Keep each to one line.

