---
name: next-ticket
description: Pick up the next unblocked ticket produced by /plan ticket decomposition. Reads only INDEX.md plus one ticket file to keep context small; implements that single slice, marks it done, and records the decision in the index.
---

# /next-ticket — Work the Frontier

One ticket per session. This command exists so each work session starts from a fresh, small context: read the index, read one ticket, do the work, record the decision, stop.

## Step 1: Locate Tickets

1. Detect the branch name and convert it to snake_case (same rule as `/plan`).
2. Find `tickets/{branch-name}/INDEX.md` — check `.claudedocs/tickets/{branch-name}/` first, then `tickets/{branch-name}/` in the current directory.
3. If not found: tell the user no ticket decomposition exists for this branch and to run `/plan` first. **Stop.**

## Step 2: Pick the Frontier Ticket

1. Read **INDEX.md only**. Do NOT read the plan file or other ticket files — that defeats the purpose.
2. If any ticket is `in-progress`: ask the user whether to resume it or pick a new one.
3. The **frontier** = tickets with status `todo` whose every `blocked-by` ticket is `done`. Pick the lowest-numbered one.
4. If no frontier ticket exists and all are `done`: announce the feature is complete and suggest deleting the `tickets/{branch-name}/` directory. **Stop.**

## Step 3: Implement

1. Read that **one** ticket file. Only consult the plan file if the ticket genuinely lacks context (and read just the relevant section).
2. Set the ticket's `status: in-progress` (file frontmatter + INDEX table).
3. Announce: **"Working ticket {NN}: {title}"** and list its acceptance criteria as the session's success criteria.
4. Implement the slice. Normal workflow gates apply (grounding, branch discipline).

**Scope discipline:** if implementation reveals new necessary work outside this ticket's scope, do NOT expand the ticket. Create a new ticket file + INDEX row (with `blocked-by` if needed) and keep going on the current slice.

## Step 4: Complete

1. Verify every acceptance criterion — check the boxes in the ticket file.
2. Run `/precommit` (stop-guard enforces this anyway).
3. Set `status: done` in the ticket frontmatter and INDEX table.
4. Fill the ticket's **Decision Log** with any non-obvious decisions made, then append a one-line gist to INDEX.md's **Decisions So Far** (`{NN}: {gist}`).
5. If this ticket introduced or clarified domain terms and the project keeps a `CONTEXT.md` glossary, append them (`**{term}** — {one-line definition}`).
6. Report: tickets remaining, and what the next frontier ticket is.
7. Finish with:

> **Ticket {NN} done.** Commit this slice, then `/clear` and run `/next-ticket` in a fresh session for the next one.

Do not start another ticket in the same session.
