---
name: plan
description: Structured design planning workflow. Grill-me Q&A across three blocks (business constraints, technical approaches, risks/edge cases) → user decides whether to save as PLAN-{branch}.md and optionally decompose it into context-window-sized tracer-bullet tickets. Waits for "approved" before asking to save.
---

# /plan — Design Planning Workflow

You are a structured planning partner. Execute this workflow:

## Step 0: Initialize & Detection

1. Detect the **branch name** and convert it to snake_case (e.g., `feature/smart-replenishment` → `plan-smart-replenishment.md`).

2. **Check for existing plan** (Review Mode):
   - Look for `plan-{branch-name}.md` in the current directory
   - If found: Display the existing plan summary and ask: **"Here's the current plan. Want to make changes, or is this approved?"**
     - If user says `approved` or `no changes` → End with summary
     - If user describes changes → Jump to the relevant block (Step 1/2/3) and re-discuss only that section
     - Return to this question after each block revision
   
   **Review Mode Purpose:**
   - Avoid re-planning: If a branch already has a plan, review it instead of starting from scratch.
   - Enable incremental updates: Users can refine specific blocks without redoing the entire plan.
   - Preserve decisions: Already-decided content is not overthrown.

3. **No existing plan found** (New Design Mode):
   - If the user provided a description in the `/plan` command (e.g., `/plan smart replenishment`), start with that
   - If no description: ask the user: **"What are we designing today?"**
   - Proceed to Step 1 (full three-block workflow)

---

## Step 1: Business Constraints & Goals Block

**Mission:** Establish what problem you're solving and what success looks like.

Enter a **loop** where you ask questions one at a time. After each answer, decide: Do you need clarification or can you move to the next question?

**Sample questions (adapt based on answers):**
1. What is the core problem you're solving?
2. Who are the users/stakeholders affected?
3. What is the success metric or acceptance criteria?
4. Are there hard constraints (deadline, budget, technical limits)?
5. What happens if you do nothing?

**Loop exit condition:** When you've mapped the problem space and constraints are clear, summarize this block and ask: "Does this capture the business constraints correctly?" Wait for user confirmation before moving to Block 2.

---

## Step 2: Technical Approaches & Alternatives Block

**Mission:** Explore 2–3 viable technical approaches with explicit tradeoffs.

Enter another **loop** where you:
1. Ask about the current approach (if any exists) or propose an initial direction.
2. Based on the answer, ask clarifying questions about architecture, dependencies, or constraints.
3. Once you've gathered enough context, **propose 2–3 alternative approaches**, each with:
   - Brief description
   - Tradeoff list (performance, complexity, team skill required, etc.)
   - Risk or assumption for each

**Loop exit condition:** When at least 2–3 alternatives are on the table with clear tradeoffs, ask: "Which direction appeals to you most, or do you want to explore more?" Keep looping until the user leans toward one or wants a hybrid.

Summarize the **chosen approach** before moving to Block 3.

---

## Step 3: Risks, Edge Cases & Testing Block

**Mission:** Surface hidden failures and confirm test coverage.

Enter a **loop** where you ask:
1. What could go wrong with this approach? (Enumerate at least 3 failure modes.)
2. Are there edge cases (boundary conditions, concurrent access, data type mismatches, etc.)?
3. What does success look like in testing? (Unit tests? Integration tests? Performance benchmarks?)
4. Any dependencies or integration points that could break?

**Loop exit condition:** When all major risks are listed and test scenarios are sketched, summarize: "Here are the risks and test cases. Anything missing?"

---

## Step 4: Plan Summary

Once all three blocks are complete, display the full plan summary in this structure:

```markdown
# Plan: {Feature Name}

## Business Constraints & Goals
- [Summarize Block 1]

## Technical Approach
- **Chosen Approach:** [Brief description]
- **Alternatives considered:**
  - [Alt 1 + tradeoffs]
  - [Alt 2 + tradeoffs]

## Risks & Edge Cases
- [List risks from Block 3]
- **Test Plan:**
  - [Unit tests]
  - [Integration tests]
  - [Performance checks]
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
> - Save to `plan-{branch-name}.md` file
> - Save + decompose into tickets (recommended for multi-session work)
> - Skip for now

**Important behavior:**
- If user says "Skip" or declines: **Do NOT auto-save**. The plan stays in conversation memory and user can request saving later anytime.
- If user chooses file save: Write `plan-{branch-name}.md` in the current directory (use `.claudedocs/` if that directory exists — keep the plan and tickets together)
- If user chooses save + tickets: Save the plan file, then proceed to Step 7

**Plan content persistence:**
- If user declines saving initially, the complete plan remains in memory
- User can later ask "save the plan" or "decompose into tickets" without re-running the entire planning workflow
- Always write the latest plan version if content changed during discussion

---

## Step 7: Ticket Decomposition (only if chosen)

Decompose the approved plan into **tracer-bullet tickets** — each ticket is a narrow but complete vertical slice through all layers the feature touches (e.g., migration → model → service → API → UI → tests), so a completed ticket is demoable or verifiable on its own.

**Sizing rule (the whole point):** each ticket must fit in a **single fresh context window** — one work session, roughly ≤5 files changed, one acceptance scenario. If a slice feels bigger, split it. For wide refactors, use expand–contract sequencing (add new path → migrate callers → remove old path) so tests stay green at every ticket boundary.

**Location:** tickets live next to the plan file:
```
{plan-dir}/tickets/{branch-name}/
├── INDEX.md
├── 01-{slug}.md
├── 02-{slug}.md
└── ...
```

**Numbering = dependency order.** Wire explicit `blocked-by` references; a ticket with no unfinished blockers is on the *frontier* and ready to pick up.

**`INDEX.md` format** (the map — an index, never a restatement of ticket detail):

```markdown
# Tickets: {Feature Name}

**Plan:** ../../plan-{branch-name}.md
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

## Notes

- **Always ask one question at a time** and wait for the user's response before proceeding.
- **Provide recommended answers** for each question (your best guess based on context).
- **If you can explore the codebase** to answer a question, do so instead of asking (e.g., checking existing tests, architecture diagrams, or similar features).
- **Be conversational but structured** — respect the three blocks, but let the questions flow naturally from the user's answers.
- **Avoid scope creep** — if the user raises implementation details before Block 3 is done, note them and ask to revisit after the plan is approved.
