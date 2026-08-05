# Ablation Log — trimming the prompt layer

## Why

Anthropic cut Claude Code's own system prompt by **>80%** when Opus 5 shipped.
Boris Cherny's reasoning: most instructions existed to correct "things the model
should do but didn't", and a newer model already does them. His recommended
practice is to **delete your `CLAUDE.md`, skills and hooks every six months** and
observe what the model actually does, adding a rule back only when it repeatedly
falls into the same pit — and to spend the reclaimed effort on **verification**
rather than prompt engineering.

dotai's own philosophy already says the same thing from the other side: *"Don't
trust AI to do the right thing. Use code to ensure it does."* A hook is
verification; a paragraph in `CLAUDE.md` is a hope. This ablation deletes the
hopes and keeps the verification.

## The three layers, and which one was actually costing anything

| Layer | Passive cost per session | Verdict |
|---|---|---|
| Hooks (`stop-guard`, `grounding-guard`, `branch-guard`, …) | 0 tokens — fire on events | **Keep.** This is the thing to invest in. |
| Skills / commands (`/plan`, `/ship`, `/handoff`, `/precommit`) | 0 tokens — opt-in | **Keep.** Not the problem. |
| `GLOBAL_RULES.md` + `rules/*.md` | **~3,700 tokens, every session, every project** | **Cut.** |

`GLOBAL_RULES.md` was 11,941 bytes and `rules/{laravel,vue,node}.md` were all
installed into `~/.claude/rules/`, which Claude Code auto-loads **unconditionally**
— so a Laravel session paid for the Vue and Node rules too.

## Deleted from `GLOBAL_RULES.md`

### Actively limiting

| Rule | Why it was harmful |
|---|---|
| **Token Budgets Are Not Advisory** (4,000/task, 30,000/session) | The worst offender. It instructed the agent to abandon a task mid-way and "request a fresh session". The harness supplies a 1M context and automatic summarisation, and explicitly tells the model it does *not* need to wrap up early. This rule traded *finishing* for *quitting early* — the exact opposite of the article's advice to let the model run and verify itself. |
| **Before Coding: Clarify & Think** — always ask open-ended follow-ups, then summarise and *wait for explicit confirmation* | Forced a minimum of two round trips onto every task, including unambiguous ones. The harness already instructs the model to make routine judgement calls itself and check in only when readings differ materially. Replaced by: ask only on genuine ambiguity. |
| **Pre-Implementation Grounding Protocol** — 5 steps with a *second* "wait for user confirmation" | Double-billed: `grounding-guard.sh` already blocks the first non-doc code edit until `/ground` emits `GROUNDING_STATUS=PASS`. The prompt copy added round trips without adding enforcement. The hook is the real gate; the prose was decoration. |
| **Investigation & Agent Strategy** — "spawn a sub-agent when >5 Greps AND 3 Reads accumulated" | Encoded a judgement call as a hard counter, and directly contradicted the session-level rule *"Do not call the Agent tool unless the user requested it"*. Its other half ("prefer Grep/Glob over bash grep/find") is already in Claude Code's own system prompt. |
| **Checkpoint After Every Significant Step** — "summarise what was done after every step" | Self-contradictory with the file's own *"no trailing summaries"* directive two sections earlier. Conflicting rules are worse than either rule alone. |
| **Multi-Agent Coordination** — proactively offer N-agent exploration | Loaded in every session to describe something that already exists as an opt-in skill (`parallel-design-agents`), and pushed toward fan-out on decisions that rarely need it. |

### Already model-default (the "should do but didn't" class)

Deleted because a current model does these without being told:

- **Coding Standards — SOLID**
- **Simplicity & Scope Discipline** — the harness has a "Delivering work" section covering scope
- **Match the Codebase's Conventions** — Claude Code's system prompt says verbatim: *"Write code that reads like the surrounding code: match its comment density, naming, and idiom."*
- **Goal-Driven Execution**
- **Pre-Optimization Semantic Check**
- **Performance: Profile Before Optimizing**
- **Documentation Standards** (document why not what)
- **Use the Model Only for Judgment Calls** — a good principle for *designing AI features*, but it is not relevant to most sessions; it lives in `CLAUDE.md`'s design principles where it belongs
- **Logging Standards** — moved to `docs/rules/logging.md`, load per-project if wanted

### Kept, condensed

`Response Style & Language`, `Branch & Git Discipline` (+ commit message format),
`Shell Environment & Credentials`, `Verifying Against Screenshots`,
`Surface Conflicts` / `Skipped is not passed`, `Tests Encode Why`.

These survive one of two tests: the model **cannot** know it (Keychain tokens, no
`glab`, 繁中 preference), or a **specific past burn** justifies the ceremony
(Vision Echo, branch protection).

### Also deleted: ClickUp API Writing Rules

Removed on the owner's instruction — ClickUp is no longer in use. Worth recording as
the cheapest category of all: a rule that was perfectly correct and genuinely
non-derivable, but described a tool that left the workflow. **Nothing signals when
that happens.** Standing instructions have no expiry, so a tool-specific rule
outlives its tool silently, which is a second reason to re-read this file at every
model release rather than only when something feels wrong.

Result: **11,941 → ~3,100 bytes.**

## Hook changes

| Hook | Change | Reason |
|---|---|---|
| `branch-guard.sh` | whitelist → **blacklist** | The 14-prefix read-only whitelist (`^ls\|^grep\|^cat\|^find\|^git status\|…`) blocked ordinary read-only work: `wc -l file \| tail` failed (`wc` absent) and `cd /x && ls` failed (starts with `cd`). Any pipeline or compound command using `wc`/`head`/`jq`/`rg`/`sed -n` was rejected. A read-only command cannot mutate the repo, so this was pure capability loss for zero safety gain. Now: block commands that **write** (`git commit/push/add/reset/rebase`, redirections, `tee`, `sed -i`, `rm`, …) and allow the rest. |
| `read-dedup-guard.sh` | **deleted** (Claude + agy) | Fixed a behaviour the harness now handles itself — Claude Code tracks file state and its system prompt already says *"Do NOT re-read a file you just edited to verify … the harness tracks file state for you."* Worse, its only escape hatch was "Edit the file first", which is wrong precisely when the file changed on disk for an external reason (`git checkout`, a build step, another agent) — the case where a genuine re-read is required. Its supporting data (1,236 redundant reads) was measured on an older model. |
| `complexity-guard.sh` | **deleted** | **Provably inert under Claude Code.** It read `TOOL_NAME` from the `CLAUDE_TOOL_NAME` env var, but Claude Code passes the PreToolUse payload as JSON on stdin and sets no such variable (`branch-guard.sh`'s own comments call the sibling `CLAUDE_TOOL_INPUT` "legacy"). `TOOL_NAME` was always empty, so its `case` never matched. Verified: 6 consecutive invocations past its threshold of 5 produced no output. It also advised delegating to a `codebase_investigator` agent that does not exist in this setup. |

Kept unchanged: `stop-guard`, `grounding-guard`, `context-budget-guard`,
`glab-guard`, `handoff-reminder`. These verify rather than advise.

## `rules/*.md` — conditional instead of global

`~/.claude/rules/*.md` is auto-loaded by Claude Code with no path filtering, so
all three stacks loaded everywhere. They now install to
**`~/.claude/dotai-rules/`** (not auto-loaded) and a `SessionStart` hook,
`stack-rules.sh`, detects the project and emits **only** the matching file:

- `artisan` present → `laravel.md`
- `package.json` + `vite.config.*` → `vue.md`
- `package.json` → `node.md`

Cost drops from three files always to one file when relevant. This is the same
move the repo already made for reviewer rules: stop shipping project-specific
content globally, discover it from the project instead.

Claude Code only — Codex has no `rules/` mechanism, and agy uses
`~/.gemini/config/AGENTS.md`. See `CLAUDE.md` §CLI Feature Gaps.

**Evidence labels for this change**, per the repo's own L3 rule that a `[doc]`-only
claim must not be written as fact:

| Claim | Status |
|---|---|
| `complexity-guard` never fired under Claude Code | **[probed]** — 6 invocations past its threshold, no output |
| `branch-guard` blocked read-only commands | **[probed]** — `wc -l \| tail` and `cd && ls` both rejected in a live session |
| `branch-guard`'s Edit/Write path was unreachable | **[probed]** — `tests/branch-guard.test.sh` failed on it before the fix |
| `stack-rules.sh` emits the right file per stack | **[probed]** — 15 assertions + a live run against a real `~/.claude/dotai-rules/` |
| `~/.claude/rules/*.md` loads unfiltered in every project | **[probed]** — all three files were present in this session's context |
| The `SessionStart` hook actually fires in a live session | **[unverified]** — registered and unit-tested, but not yet observed firing; a matcher-less entry is *assumed* to match every source |

The last row is the one to close first. Verification steps are in `CLAUDE.md`
§CLI Feature Gaps → `stack-rules.sh`.

## How to re-add a rule

1. **Wait for the same mistake twice.** Once is noise.
2. **Prefer a hook.** Can a script detect and block it? Then it is not a prompt rule.
3. **If it must be prose, put it in the project's own `CLAUDE.md`,** not the global file.
4. **Global is the last resort,** reserved for things true of this machine or this owner regardless of project.

## Next review

Re-run this ablation at the next major model release, or 2027-02 at the latest.
Method: delete a section, use the toolkit normally for two weeks, and restore only
what the model demonstrably got wrong without it.
