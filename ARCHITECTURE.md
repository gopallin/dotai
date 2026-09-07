# dotai Architecture

## Overview

**dotai** is a unified rules and automation distribution system for Claude Code and other AI CLIs (Codex, agy). It provides:

1. **Three enforcement gates** — `grounding-guard` blocks the first un-grounded
   code edit of a session, *and* every later edit that falls outside the
   `scope_files:` contract declared by `/ground`; `stop-guard` blocks the stop
   until `/precommit` has *passed* on the *current* tree. These are the reason the
   repo exists: everything else is distribution plumbing around them.
2. **Credential interception** — `secret-guard` blocks the one command redaction
   cannot cover; `secret-redact` rewrites Bash output before a token reaches the
   transcript.
3. **Branch and deployed-config protection** — `branch-guard` blocks writes on
   master/main; `deployed-guard` redirects edits of installed copies back to the
   `~/dotai` source.
4. **Centralized rules distribution** — one `GLOBAL_RULES.md` fanned out to three
   CLIs, plus per-stack rules emitted conditionally by `stack-rules.sh`.
5. **Commands and skills** — `/precommit`, `/plan`, `/map`, `/next-ticket`,
   `/handoff`, `/prompt` and the `ground` / `ship` / `reviewer-rules` skills.

**Scope of this document.** ARCHITECTURE.md describes *how the pieces work and
what data flows between them*. The authoritative **inventory** (full file tree,
the agy hook contract, `/precommit` detection order, CLI feature gaps) lives in
[CLAUDE.md](CLAUDE.md) — when the two disagree, CLAUDE.md wins and this file is
the bug.

---

## Core Components

### 1. GLOBAL_RULES.md (Source of Truth)

**Location:** `~/dotai/GLOBAL_RULES.md`

**Purpose:** The standing instructions that cannot be derived — this machine's
environment and the owner's non-obvious policies. Nothing else.

⚠️ **This file is deliberately small (~3.4KB, down from 11.9KB).** It loads in every
session of every project, so it is the most expensive and least enforceable channel
available. Before adding anything here, read
[CLAUDE.md §Prompt Minimalism](CLAUDE.md#prompt-minimalism--read-this-before-adding-any-rule)
and [docs/ABLATION.md](docs/ABLATION.md).

**Sections:**
- **Response Style & Language** — Match user's language (優先使用繁體中文)
- **Branch & Git Discipline** — Protected branches, commit authorization, message format
- **Shell Environment & Credentials** — zsh, Keychain tokens, no `glab`, secret rotation
- **Verifying Against Screenshots** — Vision Echo, never assume IDs, DB beats screenshot
- **Two Failure Modes Worth Naming** — don't average conflicting patterns; skipped ≠ passed
- **Tests Encode Why, Not What** — assert the business rule, not the return type

Removed in the 2026-08 ablation because a current model already does them: SOLID,
scope discipline, convention matching, profile-before-optimizing,
document-why-not-what, pre-optimization semantic check. Removed because they
actively cost capability: per-task token budgets, mandatory clarify-and-confirm
round trips, the numeric sub-agent threshold. See `docs/ABLATION.md`.

**Distribution:**
- Copied to `~/.claude/CLAUDE.md` (Claude Code)
- Copied to `~/.codex/AGENTS.md` (Codex CLI)
- Copied to `~/.gemini/config/AGENTS.md` (Antigravity CLI)

---

### 2. branch-guard.sh (PreToolUse Hook)

**Location:** `~/dotai/hooks/shared/branch-guard.sh`

**Purpose:** Prevent accidental edits, commits, and pushes to protected branches (master/main).

**Mechanism:**
- Triggered by **PreToolUse** on `Bash|Edit|Write|MultiEdit` — **not Bash alone.**
  The Edit/Write arm matters: an Edit payload carries `file_path` but no `command`,
  and while the unparsable-payload branch was a plain `else` it swallowed every
  Edit on master, making the hook's headline promise true only for Bash.
- Checks current branch via `git rev-parse --abbrev-ref HEAD`
- If on master/main: applies the pass-through rules below, otherwise exits 2 to block
- On any other branch: allows operation to proceed

**Strategy:** Checks *current git branch* (reliable) rather than parsing bash command (unreliable in hook context).

**Pass-through rules on master/main:**

1. **Escape hatch — `git checkout` / `git switch` are ALWAYS allowed.** Without
   this the agent is trapped: every bash is blocked, including the checkout
   needed to leave master. The subcommand is detected with `awk` so it survives
   redirects (`git checkout -b x 2>&1`) and global flags (`git -C <dir> checkout`)
   — both of which previously slipped past the simple `^git checkout` anchor and
   trapped the agent.
2. **Other read-only commands** (`ls`, `grep`, `cat`, `git status`, `git log`,
   `git diff`, …) are allowed **unless they redirect stdout to a file** — a real
   write masquerading as a safe read. The guard regex `(^|[^0-9&])>>?($|[^&])`
   blocks `> file` / `>> file` but passes stderr operations (`2>&1`,
   `2>/dev/null`, `>&2`), which only move streams and write no data file.
3. **Documentation edits** (`*.md`, `*/.claudedocs/*`) pass through Edit/Write.
4. **Writes inside `.git/`** pass through: git ignores its own directory, so they
   cannot dirty the branch or enter history — the three things this guard exists
   to prevent. `/handoff` writing `.git/info/exclude` was being rejected with
   "edits a non-documentation file", which was true and useless.
5. **Paths outside this repo's working tree** pass through, for the same reason.
   Both sides are resolved to **physical** paths first: on macOS `/tmp` →
   `/private/tmp`, so a textual prefix test would miss real in-repo paths and fail
   *open* — the dangerous direction. Observed 2026-08-19: a write to the session
   scratchpad was blocked merely because cwd happened to sit on main.
6. **Fail-open** when the tool input carries neither a command nor a file path:
   the payload was unparsable, and failing closed would block *every* tool call
   including the `git checkout` needed to escape master. Note the deliberate
   asymmetry inside the command checks — the redirect test runs on the
   quote-scrubbed command (so `echo "a -> b"` is not a write), while the
   write-command test runs on the **raw** command (so `bash -c 'git push'` is
   still caught).

**Testing:**
```bash
# On a feature branch — everything passes
git checkout -b feature/test
git status                      # ✅ Allowed
echo 'x' > file.txt             # ✅ Allowed

# On main — reads pass, writes are blocked
git checkout main
git status                      # ✅ Allowed (read-only, no redirect)
echo 'x' > file.txt             # ❌ Blocked (exit 2) — redirects to a file
git commit -m wip               # ❌ Blocked (exit 2) — write command
git checkout -b feature/x       # ✅ Always allowed (the escape hatch)
```

> ⚠️ The guard is **not** "no bash on main". Earlier revisions of this document
> claimed `git status` was blocked on main, which contradicted the pass-through
> rules above it. Read-only commands pass; only writes, write-redirects, and
> non-doc `Edit`/`Write` are blocked.

**Error Output** (the reason is filled in per blocked case — `redirects output to
a file`, `runs a write/history-modifying command`, or
`edits a non-documentation file (<path>)`):
```
❌ dotai Branch Protection
━━━━━━━━━━━━━━━━━━━━━━━━━
Current branch is 'main', and this command redirects output to a file.

Read-only commands are allowed here — only writes are blocked. To proceed:
1. git checkout -b feature/your-feature   (always permitted, even on master/main)
2. Make changes there
3. Push and open a PR
```

---

### 3. install.sh (Distribution Pipeline)

**Location:** `~/dotai/install.sh`

**Purpose:** Distribute dotai rules, hooks, skills, and commands to one or more AI CLIs.

**Process:**

```
dotai/ (source)                       ↓ install.sh (chosen: Claude Code)   ~/.claude/ (target)
├── GLOBAL_RULES.md ─────────────────────────────────────────────────────→ CLAUDE.md
├── hooks/shared/*.sh ───────────────────────────────────────────────────→ hooks/shared/*.sh
├── hooks/{claude,codex,agy}/*.sh ───────────────────────────────────────→ hooks/{claude,codex,agy}/*.sh
│                                     (registered in) ─────────────────→ settings.json
├── skills/<name>/SKILL.md ─────────────────────────────────────────────→ skills/<name>/SKILL.md
├── commands/*.md + precommit.sh + prompt-template.sh ──────────────────→ commands/
├── rules/{laravel,vue,node}.md ────────────────────────────────────────→ dotai-rules/   ← NOT rules/
└── statusline/claude/statusline.sh ────────────────────────────────────→ statusline.sh
```

> The skill path is always `<name>/SKILL.md`. A flat `skills/<name>.md` is
> **never discovered by any of the three CLIs, with no warning** — the skill
> simply does not exist. Do not draw or create that layout.
>
> Rules land in `dotai-rules/`, not `rules/`, and are emitted one-at-a-time by
> `stack-rules.sh` — see §7 for why.

**Invocation:**
```bash
bash install.sh            # interactive menu (1 Claude / 2 Codex / 3 agy / 4 all)
bash install.sh --claude   # or --codex / --agy / --all  (bare names work too)
```

A CLI whose binary is not on `PATH` is **skipped with a message**, not installed
into — so `--all` on a machine without `agy` is a no-op for agy rather than a
half-written `~/.gemini`. That check requires a shell where the CLI is on PATH
(e.g. nvm/global npm bin), not a bare non-login shell.

**Distribution Steps:**
1. Copy GLOBAL_RULES.md → target `CLAUDE.md` / `AGENTS.md` (in `config/` for agy)
2. Copy `hooks/` → target hooks dir
3. Register hooks in `settings.json` (Claude) / `hooks.json` (Codex, agy)
4. Copy `skills/<name>/` → target `skills/<name>/` (agy: `config/skills/<name>/`)
5. Copy commands → `~/.claude/commands/`, `~/.codex/prompts/`, or agy skill dirs
6. Copy `rules/` → `~/.claude/dotai-rules/` (Claude only; see §7 for Codex/agy)
7. Install the status line (Claude, agy) or write native statusline items (Codex)

Each installer is **idempotent** — re-running it re-syncs and re-merges rather
than duplicating entries — and each removes files retired by past ablations
(`read-dedup-guard.sh`, `complexity-guard.sh`, legacy flat skill files,
`~/.gemini/commands/`) so a stale copy cannot keep firing.

---

### 4. Hooks System

#### PreToolUse Hooks

Triggered **before** any tool (Bash, Read, API) executes.

**Examples:**
- `branch-guard.sh` — Blocks **write** commands and non-doc file edits on master/main; read-only commands pass through
- `grounding-guard.sh` — Two gates in one hook: (1) blocks the first un-grounded
  code edit until `/ground` passes; (2) blocks **every** later edit outside the
  `scope_files:` list declared with that PASS — gate 2 is `[unverified]`
  in the CLAUDE.md sense: tested against real payloads on all three CLIs, not yet
  observed firing in a live session
- `deployed-guard.sh` — Blocks edits to the *installed* copies under `~/.claude`, `~/.codex`, `~/.gemini`, and names the `~/dotai` source file to edit instead
- `glab-guard.sh` — Blocks the `glab` CLI (not installed), redirects to curl + `$GITLAB_TOKEN`
- `secret-guard.sh` — Blocks `security dump-keychain`, the one credential dump redaction cannot cover
- `context-budget-guard.sh` — **Advisory** only: reminds you to `/clear` or split the task once the session transcript grows past size bands (long sessions re-send their whole context every turn).

**Registration:** `~/.claude/settings.json`. Each event holds an array of
**matcher groups**, not an array of script paths — a bare string list is not a
valid Claude Code hook config and is silently ignored:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/hooks/shared/branch-guard.sh", "timeout": 5 }
        ]
      },
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/hooks/shared/deployed-guard.sh", "timeout": 5 },
          { "type": "command", "command": "bash ~/.claude/hooks/claude/grounding-guard.sh", "timeout": 10 }
        ]
      }
    ]
  }
}
```

`scripts/claude/install.sh` writes and idempotently merges the full set. What is
actually registered today, matcher by matcher:

| Event | Matcher | Hook(s) |
|---|---|---|
| `PreToolUse` | `Bash\|Edit\|Write\|MultiEdit` | `shared/branch-guard.sh` |
| `PreToolUse` | `Bash` | `shared/glab-guard.sh` |
| `PreToolUse` | `Bash` | `shared/secret-guard.sh` |
| `PreToolUse` | `Edit\|Write\|MultiEdit` | `shared/deployed-guard.sh`, `claude/grounding-guard.sh` |
| `PreToolUse` | `Bash\|Edit\|Write\|MultiEdit\|Read\|Grep\|Glob` | `claude/context-budget-guard.sh` (advisory) |
| `PostToolUse` | `Bash` | `claude/secret-redact.sh` (**Bash only** — see *PostToolUse Hooks* below) |
| `SessionStart` | `clear` | `claude/handoff-reminder.sh` |
| `SessionStart` | *(none — every source)* | `claude/stack-rules.sh` |
| `Stop` | *(none)* | `claude/stop-guard.sh` |

Codex and agy register the same guards through their own formats
(`~/.codex/hooks.json`, `~/.gemini/config/hooks.json`); agy additionally needs
`shared-guard-adapter.sh`, because it ignores exit codes and reads a JSON
decision from stdout (CLAUDE.md §agy Hook Contract).

**Retired (2026-08 ablation, see `docs/ABLATION.md`):** `complexity-guard.sh` was
provably inert under Claude Code — it read the `CLAUDE_TOOL_NAME` env var, which
Claude Code does not set, so its `case` never matched. `read-dedup-guard.sh`
duplicated file-state tracking the harness now performs natively, and its only
escape hatch ("Edit the file first") was wrong precisely when a file changed on
disk externally — the case that legitimately needs a re-read.

**Remaining token-efficiency work** rests on `context-budget-guard` plus
`/handoff`, on the reasoning that long sessions re-sending their whole context
each turn cost far more than redundant reads do.

> A previous revision quantified this as "~96% of tokens are `cache_read`". That
> number had no source in this repo and is **not** reproducible from the usage
> report, so it has been removed rather than kept as a plausible-looking figure.
> If the split matters for a future decision, measure it and cite the measurement.

#### PostToolUse Hooks

- **claude/secret-redact.sh** — rewrites a tool result via `updatedToolOutput`,
  scrubbing known credential shapes (`github_pat_`, `ghp_`, `glpat-`, `sk-ant-`,
  `AKIA`, `xox*`, PEM headers). Registered for **`Bash` only**: at PostToolUse
  `exit 2` cannot block (the tool already ran), so rewriting the output is the
  only mechanism that withholds a value — and redacting a `Read` would show the
  model `[REDACTED:…]` as a file's real content, which it could then write back
  on the next `Edit`. Claude Code only; `updatedToolOutput` has no Codex or agy
  equivalent (CLAUDE.md §CLI Feature Gaps).

#### SessionStart Hooks (Claude Code only)

- **claude/stack-rules.sh** — detects the repo's stack and emits **only** that
  stack's rules file from `~/.claude/dotai-rules/` (see §7).
- **claude/handoff-reminder.sh** — matcher `clear`: fires on the fresh session
  born from `/clear`, locates the cleared session's transcript on disk, and either
  points at a fresh `/handoff` file or offers `/resume`-then-`/handoff` vs a cheap
  transcript-tail rebuild. Never blocks. Codex has an equivalent; agy has no
  post-clear lifecycle event, so it has none (CLAUDE.md §CLI Feature Gaps).

#### CLI-Specific Stop Hooks

- **claude/stop-guard.sh** — the end-of-work gate, in two layers:
  **(1)** did this session write any code file that is still pending in this repo?
  If not, allow the stop. **(2)** if it did, read the receipt at
  `$GIT_DIR/dotai-precommit` and require `status=PASS` **and** `tree=` equal to a
  freshly recomputed fingerprint of the current tree — so a PASS earned before
  later edits does not count. It is not enough that `/precommit` ran; it must have
  passed, on this tree.
  When it blocks for a stale PASS it also **names what moved** — the changed,
  added and removed paths, how long ago the PASS was earned, and a warning when
  another session earned it. Before that, the message was "the working tree
  changed afterwards. Run /precommit again", which forces a blind full re-run;
  that happened twice in the usage report. The delta is reporting only, computed
  from the receipt's file manifest, so a bug in it cannot open the gate.
- **codex/stop-guard.sh** / **agy/stop-guard.sh** — same contract, different I/O:
  Claude and Codex block with `exit 2`; agy ignores exit codes and needs
  `{"decision":"continue","reason":"…"}` on stdout.

The fingerprint function is duplicated between `commands/precommit.sh` and all
three `stop-guard.sh` files **on purpose**, and `tests/precommit.test.sh` fails if
they drift — drift fails *closed* (every PASS mismatches and the gate blocks
forever) rather than open.

#### Token-Efficiency Hooks: Cross-CLI Portability

> `read-dedup-guard` was retired in the 2026-08 ablation; the row below is kept
> because the **portability analysis** still applies to any future read-gating
> hook, not because the hook exists. See `docs/ABLATION.md`.

The token-efficiency hooks port unevenly because the deciding factor is each
CLI's pre-tool event coverage. Note the data formats are **not** uniform: Claude
Code and Codex pass `session_id` / `transcript_path` / `tool_name` / `tool_input`
and treat `exit 2` as a block, while agy passes camelCase `conversationId` /
`transcriptPath` / `toolCall.name` / `toolCall.args` and reads a JSON decision from
stdout, ignoring the exit code (see CLAUDE.md §agy Hook Contract).

| Hook | Claude Code | Codex CLI | Antigravity CLI (agy) |
|---|---|---|---|
| `context-budget-guard` (advisory) | PreToolUse (broad) | PreToolUse（目前安裝於 `Bash`）¹ | PreInvocation → `injectSteps` ✅ |
| ~~`read-dedup-guard`~~ (retired) | PreToolUse/`Read` ✅ | **內建讀檔工具 coverage 未驗證**² | PreToolUse/`view_file` ✅³ |

1. Codex `PreToolUse` 可攔 Bash、`apply_patch`、MCP 與其他 local function tools；
   本專案的 context-budget guard 目前只註冊於 `Bash`。
2. Codex 是否把其內建讀檔工具交給 hook，必須在目標版本實測；未確認前不安裝
   read-dedup guard，也不宣稱它不可能實作。
3. agy `PreToolUse` **fires** for `view_file` — confirmed by live probe. The deny
   path uses `{"decision":"deny","reason":"…"}` per agy's documented contract but
   has not been exercised end-to-end yet (see CLAUDE.md §agy Hook Contract → Still
   unverified). (The earlier `BeforeTool`/`read_file` note was wrong on both
   names: neither exists.) The agy
   port tracks already-read paths in a per-conversation marker file instead of
   parsing the transcript, whose format agy documents as unstable.

---

### 5. Skills Directory

**Location:** `~/dotai/skills/`

**Purpose:** Reusable automation patterns for common tasks.

**The full set** (each is `skills/<name>/SKILL.md`):

| Skill | Role |
|---|---|
| `ground` | The **checker** half of the front-of-work gate: restate the task, read 1–2 reference files, verify data/IDs, run the reviewer-rules protocol, then emit `GROUNDING_STATUS=PASS`. `grounding-guard.sh` blocks the first non-doc edit until it does. |
| `ship` | Test → L1/L2/L3 review → commit → push → open MR/PR, routing to GitLab or GitHub by inspecting `origin` and calling its REST API with a Keychain token (no forge CLI). |
| `reviewer-rules` | The **single** source for the L1/L2/L3 review protocol, invoked by `/ground` Step 4.5 and `/ship` Step 2.5. It was previously inlined in both and had already drifted; project-specific rules are discovered from the project (`.claude/reviewer-rules.md` or a `## Reviewer Rules` section) rather than shipped globally. `tests/reviewer-rules.test.sh` fails if project-specific content reappears under `skills/` or `rules/`. |
| `git-push` | Auto-detect GitLab/GitHub, apply the Keychain token. |
| `preflight` | Environment audit (branch, git state, env vars, MCP). |
| `parallel-design-agents` | Fan out multiple agents over competing design options, then synthesize. |

**Format:** one directory per skill, containing `SKILL.md` with YAML frontmatter
```yaml
---
name: skill-name
description: What the skill does
---
```

**Distribution:** copied as `<name>/SKILL.md` into `~/.claude/skills/`,
`~/.codex/skills/`, and `~/.gemini/config/skills/` (agy's global root is
`config/`, not `~/.gemini/`). A flat `<name>.md` is silently ignored by every
CLI — see `tests/skills-install.test.sh`.

---

### 6. Commands Directory

**Location:** `~/dotai/commands/`

**Purpose:** Slash commands available across all CLIs.

| Command | Role |
|---|---|
| `/precommit` | The quality pipeline. `precommit.md` documents the output format and the stop-guard contract; **`precommit.sh` is the executor** — tracked project override → tech-stack detection → lint/build/test, or generic mode. It prints `PRECOMMIT_STATUS=` / `PRECOMMIT_MODE=` and writes the receipt that `stop-guard.sh` reads: `status=`, `mode=`, `tree=` (the gate), plus `ts=`, `session=`, `branch=` and one `file=<sha256>\t<path>` line per pending file (the report — see §4). |
| `/plan` | Single-session design planning: one-question-at-a-time grilling, coverage check, save as `plan-{key}.md`, optionally decompose into context-window-sized tickets（Codex 以 `/prompts:plan` 呼叫，不與內建 `/plan` mode 衝突）。 |
| `/map` | For work too big for one session: destination, fog of war, decision tickets — hands off to `/plan --from-map` once the map clears. |
| `/next-ticket` | Pick up the next unblocked ticket, reading only `INDEX.md` plus one ticket file to keep context small. |
| `/handoff` | Write a compact resume file before `/clear`. Local-only, never committed (ignored via `.git/info/exclude`). |
| `/prompt` | Guided wizard collecting type/goal/files/scope/done-when, emitting an AI-ready task prompt via `prompt-template.sh` (kept as a shell template so all skeletons do not load into context). |
| `/incident` | Evidence-first root-cause protocol for production incidents: declare every source's timezone and convert to UTC **before** building a timeline, rank ≥3 hypotheses each with the query that would disprove it, check whether the suspected fix is even deployed, then reproduce with a failing test before repairing. |

**Detection order used by `/precommit`** — authoritative copy in CLAUDE.md
§Owner's Tech Stack: git-tracked `.claude/commands/precommit.sh` → `artisan`
(Laravel) → `package.json` + `vite.config.*` (Vue) → `package.json` (Node) →
`tests/*.test.sh` (shell) → **generic**. Within an arm it resolves the *actual*
toolchain rather than assuming one: pint vs phpcs (+ host vs container), and
pnpm/yarn/npm/bun from the lockfile.

⛔ Never author a precommit script into a repo to give the gate something to
pass — the override is honoured **only when git tracks it**, precisely because
that happened once (CLAUDE.md §Owner's Tech Stack).

**Distribution note:** Codex has no `commands/` directory — these install to
`~/.codex/prompts/` and are invoked as `/prompts:<name>`. agy has no commands
concept at all; they install as skills under `~/.gemini/config/skills/<name>/SKILL.md`
with `name:` injected into the frontmatter (CLAUDE.md §Commands — agy has no such
concept).

---

### 7. Rules Directory

**Location:** `~/dotai/rules/`

**Purpose:** Language/framework-specific coding standards.

**Examples:**
- **vue.md** — Vue 3 Composition API, TypeScript, Pinia rules
- **node.md** — async/await, error handling, ES modules
- **laravel.md** — Service classes, Form Requests, Eloquent relationships

**Distribution: `~/.claude/dotai-rules/`, deliberately NOT `~/.claude/rules/`.**

Claude Code auto-loads **every** file under `~/.claude/rules/` with no path
filtering, so the earlier layout loaded Laravel *and* Vue *and* Node rules into
every session of every project — three stacks' standing instructions, at most one
of them relevant. The fix is a directory the CLI does not auto-load plus a
`SessionStart` hook that emits only the match:

```
rules/{laravel,vue,node}.md
   → scripts/claude/install.sh  →  ~/.claude/dotai-rules/
   → claude/stack-rules.sh (SessionStart) detects the repo's stack
   → emits exactly ONE file into the session's context
```

Pinned by `tests/stack-rules.test.sh` (15 assertions). Status **`[unverified]`**:
the hook has been run against real payloads but not yet *observed* firing in a
live session — a matcher-less `SessionStart` entry is *assumed* to match every
source.

**Sibling CLIs deliberately differ** (CLAUDE.md §CLI Feature Gaps):

- **Codex** has no `rules/` mechanism at all, so nothing loads unconditionally and
  there is nothing to filter. `scripts/codex/install.sh` installs no rules.
- **agy** reads global rules from a single `~/.gemini/config/AGENTS.md` and has no
  `SessionStart` event. `scripts/agy/install.sh` still copies the three files to
  `~/.gemini/rules/`, which agy is **not** known to read — treat that copy as
  vestigial until someone probes it, not as a working per-stack mechanism.

> ⚠️ Nothing path-filters rules *by content*: a rule naming one project's tables
> would apply to every project on the same stack. That is why project-specific
> reviewer rules live in the project repo instead (see the `reviewer-rules` skill).

---

### 8. Custom Status Line (Claude Code only)

**Location:** `~/dotai/statusline/claude/statusline.sh`

**Purpose:** Always-on display of token usage so you can see "how much is left" at a glance.

**Mechanism:**
- Registered under the `statusLine` key in `~/.claude/settings.json` (NOT a hook — `statusLine` is a settings-only feature, so it cannot be declared in `plugin.json` / `hooks.json`).
- Claude Code pipes a JSON blob to the command on stdin; the script parses it and prints one line.
- Renders colored bar graphs (`█` used / `░` remaining): **purple normally, red when a bar exceeds 80%**.

**Data source (stdin JSON):**
- `.context_window.*` — context token usage; always present after the first API call.
- `.rate_limits.*` — the data behind `/usage` (5-hour / 7-day plan limits, plus each window's `resets_at` epoch); **Claude.ai Pro/Max only**, absent for API / managed accounts. The script degrades silently when absent.

Reset times (`↺`) are rendered in local time (= `/usage`'s timezone): the 5-hour window shows time only, the 7-day window shows date + time; minutes appear only when not on the hour.

**Example output:**
```
Opus · ctx [███░░░░░] 86k/200k 43% · 5h [██░░░░░░] 24% ↺2pm · 7d [███░░░░░] 41% ↺Jun 14 1pm
```

**CLI parity:** Claude Code and Antigravity CLI (agy) support this custom command
statusline. Codex provides a native configurable `/statusline`（model、context、token
usage、rate limits、git 等）；`scripts/codex/install.sh` writes its selected items to
`~/.codex/config.toml`，但不能直接沿用本腳本的 stdin schema。

**Distribution:** Copied to `~/.claude/statusline.sh` by `scripts/claude/install.sh`, which also registers the `statusLine` command in `settings.json` (idempotent).

---

### 9. Tests (`~/dotai/tests/`)

**Not installed.** They run from the repo, and they are the layer that makes the
philosophy — *don't trust AI to do the right thing, use code to ensure it* — apply
to dotai itself. Every guard here is a claim about behaviour under a payload
format nobody controls; the suites are what keep those claims honest.

```bash
for t in tests/*.test.sh; do bash "$t" || echo "FAILED: $t"; done
```

| Suite | What it pins |
|---|---|
| `precommit.test.sh` | generic mode, the tracked-only project override, the receipt fingerprint — recomputed inline by all three `stop-guard.sh` files, so drift fails **closed** — plus the file manifest, its parity across all four copies, and that a blocked stop names the files that changed |
| `branch-guard.test.sh` | the pass-through rules: reads allowed, write-redirects blocked, `git checkout` always allowed even behind global flags |
| `grounding-guard.test.sh`, `codex-grounding-guard.test.sh` | the `GROUNDING_STATUS` marker contract, the doc-edit exemption, the `scope_files:` contract (in/out of scope, globs, subtrees, loud amendment, stale-cache re-read, fail-open when nothing was declared), and that the Codex and agy ports actually fire under their own payload shapes |
| `secret-guard.test.sh` | 26 assertions over real payload shapes — **synthetic credentials only**; never put a live one in a fixture, the repo is pushed and git history is permanent |
| `deployed-guard.test.sh`, `glab-guard.test.sh` | the deployed-path → source-path redirect, and the `glab` block |
| `agy-hook-contract.test.sh` | agy's event names, tool names, PascalCase arg keys, JSON-decision contract, **and that the three retired hook files stay absent** |
| `agy-install.test.sh`, `codex-install.test.sh`, `skills-install.test.sh` | where each installer writes; the skill layout for all three CLIs, including cleanup of legacy flat files |
| `stack-rules.test.sh` | stack detection and that exactly one rules file is emitted |
| `reviewer-rules.test.sh` | fails if project-specific rules reappear under `skills/` or `rules/` |
| `ship-forge-detect.test.sh`, `map-command.test.sh`, `codex-handoff-reminder.test.sh` | forge routing from `origin`, the map command contract, the post-`/clear` reminder |

A passing suite is **not** proof a hook fires: the CLI still has to invoke it.
That is the gap `[unverified]` marks throughout CLAUDE.md.

---

## Workflow: Adding a New Rule

### Step 0: Run the gate — most new rules should not be written at all

⚠️ **This is the step this document used to omit, and omitting it is how
`GLOBAL_RULES.md` reached 11,941 bytes before the 2026-08 ablation cut it back to
~3.4KB.** Global prose loads in every session of every project and is the *weakest*
enforcement available. Answer all four questions in
[CLAUDE.md §Prompt Minimalism](CLAUDE.md#gate-for-any-new-rule) first — has the
model actually got this wrong **twice**, can a script detect it instead, does it
need every project, does it contradict or merely restate something already there.
Any "no" means don't add it.

Then place it as low in this order as it will go:

> **hook → skill/command (opt-in) → project `CLAUDE.md` → global prose**

So: prefer writing `hooks/shared/<thing>-guard.sh` plus `tests/<thing>.test.sh`.
Reach for `GLOBAL_RULES.md` only for what the model cannot derive — this machine's
environment, credentials, the owner's non-obvious policies.

### Step 1: Branch first

`GLOBAL_RULES.md` §Branch & Git Discipline forbids editing or committing from
`master`/`main`, and `branch-guard.sh` enforces it (a `.md` edit would slip
through the doc pass-through, but the commit would not):

```bash
cd ~/dotai
git checkout -b feature/rule-description
```

### Step 2: Edit and commit

```bash
# edit GLOBAL_RULES.md (or, preferably, add the hook + its test)
bash tests/branch-guard.test.sh     # run the suites your change touches
git add GLOBAL_RULES.md
git commit                          # message says WHY, per GLOBAL_RULES
```

Then push and open a PR — never commit to `main` directly.

### Step 3: Run install.sh

```bash
cd ~/dotai
bash install.sh --all      # or: echo "4" | bash install.sh
```

### Result

The new rules appear in:
- `~/.claude/CLAUDE.md` (Claude Code)
- `~/.codex/AGENTS.md` (Codex CLI)
- `~/.gemini/config/AGENTS.md` (Antigravity CLI)

Re-run the ablation at every major model release (next due **2027-02** at the
latest) and delete what the current model no longer needs.

---

## Workflow: Creating a Feature Branch

### Step 1: Create Feature Branch

```bash
cd ~/dotai
git checkout -b feature/description
```

### Step 2: Make Changes

- Edit `GLOBAL_RULES.md` for rules
- Add skill files to `skills/`
- Add hooks to `hooks/shared/`
- Commit each logical chunk

### Step 3: Test Protection

If you accidentally switch to main, branch-guard.sh blocks the **writes** — reads
still pass, so you are never trapped:

```bash
git checkout main
git status                      # ✅ Allowed (read-only)
echo 'x' >> CLAUDE.md           # ❌ Blocked — write-redirect on main
```

### Step 4: Switch Back to Feature Branch

```bash
git checkout feature/description   # always allowed, even from main
echo 'x' >> CLAUDE.md              # ✅ Allowed again
```

---

## Testing branch-guard.sh

### Verify Hook Installation

```bash
# Check the hook is registered, with its matcher (a bare grep for the path
# cannot tell you whether the surrounding matcher-group shape is valid)
jq -r '.hooks | to_entries[] | .key as $e | .value[]
       | "\($e)\t\(.matcher // "(none)")\t\([.hooks[].command] | join(", "))"' \
  ~/.claude/settings.json

# Check hook file exists
ls -la ~/.claude/hooks/shared/branch-guard.sh
```

### Manual Test: Allow Feature Branch

```bash
git checkout -b feature/test
bash -c "echo 'This should work'"  # ✅ Allowed
```

### Manual Test: Block Main Branch

```bash
git checkout main
bash -c "echo 'x' > file.txt"   # ❌ Blocked (exit 2) — writes to a file
git commit -m wip               # ❌ Blocked (exit 2) — write command
wc -l CLAUDE.md | tail -5       # ✅ Allowed — read-only
git checkout -b feature/x       # ✅ Always allowed (the escape hatch)
```

Or run the suite: `bash tests/branch-guard.test.sh`

---

## Integration with Claude Code

### Automatic Hook Loading

When Claude Code restarts, it reads `~/.claude/settings.json` and activates hooks:

1. **PreToolUse hooks** execute before Bash/Edit/Write/MultiEdit (and, for the
   advisory context-budget guard, Read/Grep/Glob too)
2. **branch-guard.sh** blocks write operations on protected branches
3. **deployed-guard.sh** blocks edits to installed copies, naming the `~/dotai` source
4. **grounding-guard.sh** blocks the first non-doc code edit until `/ground` passes
5. **glab-guard.sh / secret-guard.sh** block the `glab` CLI and `security dump-keychain`
6. **PostToolUse** runs `secret-redact.sh` over Bash output before it reaches the transcript
7. **SessionStart hooks** run `stack-rules.sh` (emits the detected stack's rules) and, after `/clear`, `handoff-reminder.sh`
8. **Stop** runs `stop-guard.sh`, which requires a `/precommit` PASS on the current tree

### Available Commands

`/precommit`, `/plan`, `/map`, `/next-ticket`, `/handoff`, `/prompt` — see §6.

### Available Skills

`ground`, `ship`, `reviewer-rules`, `git-push`, `preflight`,
`parallel-design-agents` — see §5.

### Available Rules

One of `laravel.md` / `vue.md` / `node.md`, chosen per session by
`stack-rules.sh` — see §7. All three are on disk; exactly one loads.

### The Enforced Loop

```
/plan (or /feature-dev)          design before code
   → /ground                     grounding-guard blocks the first edit until PASS
                                 …and holds later edits to scope_files:
   → implement
   → /precommit                  stop-guard blocks the stop until PASS on THIS tree
   → /ship                       test → L1/L2/L3 review → commit → push → MR/PR
```

For production incidents the loop starts one step earlier, at `/incident`:
diagnose evidence-first, reproduce with a failing test, and only then enter
`/ground`. It carries no marker and no hook — a hook can verify that a pipeline
ran, but not that a hypothesis was honestly falsified, and a check that rewards
typing the line is what got the old stop-guard "Layer 3" deleted.

---

## Maintenance

### Update GLOBAL_RULES.md

Edit `~/dotai/GLOBAL_RULES.md` directly (source of truth).

Distribute via `install.sh` after committing.

### Add New Hook

1. Create the hook in `~/dotai/hooks/shared/` (all three CLIs) or a CLI-specific
   directory. A shared hook needs agy's `shared-guard-adapter.sh` to be routed
   through, because agy ignores exit codes.
2. Add execution logic (bash script). Decide **fail-open vs fail-closed
   deliberately** and say which in the header comment — `branch-guard.sh`
   fails *open* on unparseable input so the `git checkout` escape hatch survives,
   while the precommit fingerprint fails *closed*.
3. Register it in the relevant `scripts/*/install.sh`, then run `install.sh`.
4. **Write `tests/<hook>.test.sh` and drive the hook with a real payload on
   stdin.** Two retired hooks were *provably inert in production* —
   `complexity-guard.sh` read an env var Claude Code never sets, and the old
   stop-guard "Layer 3" read `.content[-1].text` when the transcript stores text
   at `.message.content[]` — and both went unnoticed for months because nothing
   exercised them. A hook with no test is an assumption, not a control.
5. Confirm it fires **in a live session**, not just under the test. Hooks pending
   that confirmation are marked `[unverified]` in CLAUDE.md; do not upgrade the
   wording until you have seen it fire.

### Add New Skill

1. Create `~/dotai/skills/new-skill/SKILL.md` (the directory name must match `name:`)
2. Follow git-push/SKILL.md format (YAML frontmatter + Markdown docs)
3. Run `install.sh` to distribute to `~/.claude/skills/new-skill/SKILL.md`
4. Run `bash tests/skills-install.test.sh` — it derives the expected skill list
   from `skills/`, so it covers the new one with no edits

### Add New Rule

1. Run the §Prompt Minimalism gate first (see *Workflow: Adding a New Rule* → Step 0)
2. Create or edit `~/dotai/rules/{language}.md`
3. Teach `hooks/claude/stack-rules.sh` how to detect that stack, and add the copy
   line to `scripts/claude/install.sh`
4. Run `install.sh` (lands in `~/.claude/dotai-rules/`) and
   `bash tests/stack-rules.test.sh`

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────┐
│                dotai (Source Repository)                 │
├──────────────────────────────────────────────────────────┤
│ GLOBAL_RULES.md                                          │
│ hooks/shared/{branch,glab,secret,deployed}-guard.sh       │
│ hooks/claude/{stop,grounding,context-budget}-guard.sh     │
│ hooks/claude/{handoff-reminder,stack-rules,secret-redact}.sh │
│ hooks/{codex,agy}/…            (agy: + shared-guard-adapter) │
│ skills/<name>/SKILL.md         ← always <name>/SKILL.md      │
│ commands/*.md + precommit.sh + prompt-template.sh         │
│ rules/{laravel,vue,node}.md                              │
│ statusline/{claude,agy}/statusline.sh                    │
│ tests/*.test.sh                ← NOT installed            │
│ docs/*.md                      ← NOT installed            │
└──────────────────────────────────────────────────────────┘
          │
          │ install.sh   (skips any CLI not on PATH)
          ├────────────────────────────┬─────────────────────────┐
          ▼                            ▼                         ▼
  ┌────────────────────┐   ┌──────────────────────┐   ┌────────────────────────┐
  │ ~/.claude          │   │ ~/.codex             │   │ ~/.gemini              │
  ├────────────────────┤   ├──────────────────────┤   ├────────────────────────┤
  │ CLAUDE.md          │   │ AGENTS.md            │   │ config/AGENTS.md       │
  │ hooks/{shared,     │   │ hooks/ + hooks.json  │   │ config/hooks.json      │
  │   claude,codex,agy}│   │ skills/<n>/SKILL.md  │   │ hooks/ (+ adapter)     │
  │ skills/<n>/SKILL.md│   │ prompts/  ← commands │   │ config/skills/<n>/     │
  │ commands/          │   │   (/prompts:plan)    │   │   SKILL.md ← commands  │
  │ dotai-rules/       │   │ config.toml          │   │   too (no cmd concept) │
  │   ← NOT rules/     │   │   ← native statusline│   │ statusline.sh          │
  │ settings.json      │   │ (no rules mechanism) │   │ rules/ ← vestigial,    │
  │ statusline.sh      │   │                      │   │   agy reads AGENTS.md  │
  └────────────────────┘   └──────────────────────┘   └────────────────────────┘
```

Three asymmetries in that picture are **deliberate**, not gaps to be "fixed"
(CLAUDE.md §CLI Feature Gaps):

- **Codex has no `rules/` mechanism**, so there is nothing loading
  unconditionally and nothing for a `stack-rules` port to filter. Its commands
  live in `prompts/` and are invoked `/prompts:<name>`.
- **agy has no commands concept and no `SessionStart`**, so commands install as
  skills and `handoff-reminder` / `stack-rules` have no agy port at all. Its
  `rules/` copy is not known to be read — `AGENTS.md` is the documented path.
- **`secret-redact.sh` is Claude-only**, because `updatedToolOutput` has no
  equivalent elsewhere; a port would be an inert file.

---

## Key Principles

1. **Enforce with code, not prompts** — a hook that checks the outcome beats a
   paragraph asking for it. Prefer, in order:
   **hook → skill/command → project `CLAUDE.md` → global prose.**
2. **Single Source of Truth** — Edit `GLOBAL_RULES.md` once, distribute to all CLIs
3. **Non-Destructive Hooks** — the guards block or advise; only `secret-redact`
   rewrites, and only because PostToolUse cannot block
4. **Reversible, idempotent Distribution** — re-run `install.sh` to sync; it also
   deletes files retired by past ablations
5. **CLI Parity where the CLIs allow it** — parity is the default, but four
   documented asymmetries are deliberate; an inert file is worse than an absence
6. **Feature Branch Workflow** — All edits on feature branches, protected main via hooks
7. **Fewer rules, verified harder** — delete first, measure, restore only after
   the same mistake happens **twice** (`docs/ABLATION.md`)
