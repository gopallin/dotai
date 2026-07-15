---
name: handoff
description: Write a compact session-handoff file before /clear, so the next fresh session resumes in seconds instead of re-deriving state. Local-only — never committed (ignored via .git/info/exclude).
---

# /handoff — Compact Session Handoff

Produce a small resume file capturing where this session left off. The next session reads this one file instead of replaying the conversation via /resume or /compact.

## Step 1: Determine the File Path

1. Detect the branch name and convert it to snake_case (same rule as `/plan`).
2. Target: `.claudedocs/handoff-{branch-name}.md` if `.claudedocs/` exists, otherwise `handoff-{branch-name}.md` in the current directory.

## Step 2: Ensure It Is Never Committed

Handoff files are local session state — they must not enter git history. Append these patterns to `.git/info/exclude` (local-only ignore, does not touch the project's `.gitignore`) if not already present:

```
.claudedocs/handoff-*.md
handoff-*.md
```

## Step 3: Write the Handoff (Overwrite, Keep It Small)

Overwrite the file every time — it is a snapshot, not a journal. Target **≤30 lines**. Point to file paths instead of pasting code. Do not dump conversation history.

```markdown
# Handoff: {branch-name} — {date}

## Goal
{One sentence: what this work is trying to achieve.}

## Done (verified)
- {Only things actually verified — tests run, behavior observed. Not "should work".}

## Next Step
- {The single concrete action the next session should start with.}

## Key Decisions
- {Decision + one-line why. Only non-obvious ones.}

## Pointers
- {file:line paths that matter — changed files, the failing test, the relevant plan/ticket}

## Gotchas
- {Anything that would trip up a fresh session: env quirks, half-applied changes, misleading errors.}
```

**Honesty rule (fail loud):** if something was skipped or is unverified, say so in the handoff. A handoff that claims more than was verified poisons the next session.

## Step 4: Hand Off

Confirm with:

> **Handoff saved → `{path}`.** Run `/clear`, then start the next session with `@{path}` (or `/next-ticket` if this branch uses tickets — INDEX.md already tracks ticket state).

## Reconstruction Mode (rebuilding from a cleared session's transcript)

When the handoff-reminder hook (or the user) asks you to rebuild a handoff from a previous session's transcript instead of live memory:

1. **Read only the tail** of the transcript (roughly the last 200 lines), skipping large tool-result blobs. Reading the whole transcript re-pays the context the user just cleared — that defeats `/clear`.
2. Write the same format as Step 3, but title it `# Handoff (reconstructed): ...` and add a first line: `> Reconstructed from transcript tail — unverified; mid-session decisions may be missing.`
3. **Done (verified)** may only contain claims with visible evidence in the transcript (e.g. test output). Everything else goes under **Gotchas** as unverified.
4. Ignore rules and overwrite behavior are identical to a normal handoff.

## Notes

- If working inside the `/plan` ticket flow and a ticket was **completed**, INDEX.md is the handoff — this command is for mid-ticket interruptions and non-ticketed work.
- Stale handoff files are harmless: git-ignored, overwritten on next use.
- The handoff-reminder hook (SessionStart on `/clear`, Claude Code only) is the safety net for forgotten handoffs: it offers `/resume` + `/handoff` (high fidelity) or reconstruction (cheap). Proactive `/handoff` before `/clear` still beats both.
