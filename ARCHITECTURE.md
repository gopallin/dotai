# dotai Architecture

## Overview

**dotai** is a unified rules and automation distribution system for Claude Code and other AI CLIs (Codex, Gemini). It provides:

1. **Centralized Rules Management** — Single source of truth for AI behavior (`GLOBAL_RULES.md`)
2. **Branch Protection** — Prevents accidental edits/commits/pushes to main branches
3. **CLI Integration** — Distributes rules, hooks, skills, and commands to multiple AI CLI tools
4. **Extensible Hooks** — PreToolUse, PreCommand, and event-based automation

---

## Core Components

### 1. GLOBAL_RULES.md (Source of Truth)

**Location:** `~/dotai/GLOBAL_RULES.md`

**Purpose:** Single authoritative source for all AI CLI behavior rules.

**Sections:**
- **Response Style & Language** — Match user's language (優先使用繁體中文)
- **Requirement Clarification** — SOLID workflow before development
- **Coding Standards** — SOLID principles enforcement
- **Shell Environment** — zsh best practices, ~ expansion, stderr handling
- **ClickUp API Rules** — API-maintained vs. UI-maintained card formatting
- **Scope Discipline** — No unnecessary features or abstractions
- **Branch Discipline** — Branch confirmation, protected branch workflow
- **Pre-Optimization Semantic Check** — Verify context before refactoring
- **Investigation & Agent Strategy** — Codebase exploration patterns

**Distribution:**
- Copied to `~/.claude/CLAUDE.md` (Claude Code)
- Copied to `~/.codex/AGENTS.md` (Codex CLI)
- Copied to `~/.gemini/GEMINI.md` (Gemini CLI)

---

### 2. branch-guard.sh (PreToolUse Hook)

**Location:** `~/dotai/hooks/shared/branch-guard.sh`

**Purpose:** Prevent accidental edits, commits, and pushes to protected branches (master/main).

**Mechanism:**
- Triggered by **PreToolUse** hook when Bash tool is about to execute
- Checks current branch via `git rev-parse --abbrev-ref HEAD`
- If on master/main: exits with code 2, blocks the Bash command
- Otherwise: allows operation to proceed

**Strategy:** Checks *current git branch* (reliable) rather than parsing bash command (unreliable in hook context).

**Testing:**
```bash
# When on feature branch
git checkout -b feature/test
bash -c "git status"  # ✅ Allowed

# When on main
git checkout main
bash -c "git status"  # ❌ Blocked by branch-guard.sh
```

**Error Output:**
```
❌ dotai Branch Protection
━━━━━━━━━━━━━━━━━━━━━━━━━
You are currently on 'master' or 'main' branch.
Cannot edit, commit, or push from protected branches.

To proceed:
1. Create a feature branch: git checkout -b feature/your-feature
2. Make changes there
3. Push and create a PR
```

---

### 3. install.sh (Distribution Pipeline)

**Location:** `~/dotai/install.sh`

**Purpose:** Distribute dotai rules, hooks, skills, and commands to one or more AI CLIs.

**Process:**

```
dotai/ (source)
├── GLOBAL_RULES.md
├── hooks/
│   ├── shared/branch-guard.sh
│   ├── claude/stop-guard.sh
│   ├── codex/stop-guard.sh
│   └── gemini/stop-guard.sh
├── skills/
│   ├── git-push.md
│   ├── preflight.md
│   └── ...
└── commands/
    ├── /plan
    └── /precommit
    
    ↓ install.sh (chosen: Claude Code)
    
~/.claude/ (target)
├── CLAUDE.md (from GLOBAL_RULES.md)
├── hooks/
│   ├── shared/branch-guard.sh
│   ├── claude/stop-guard.sh
│   └── settings.json (hook registration)
├── skills/ (git-push.md, preflight.md, ...)
├── commands/ (/plan, /precommit)
└── rules/ (vue.md, node.md, laravel.md)
```

**Interactive Menu:**
```
1) Claude Code       → ~/.claude
2) Codex CLI        → ~/.codex
3) Gemini CLI       → ~/.gemini
4) All three CLIs
```

**Distribution Steps:**
1. Copy GLOBAL_RULES.md → target CLAUDE.md / AGENTS.md / GEMINI.md
2. Copy hooks/ → target hooks/
3. Register hooks in settings.json / hooks.json
4. Copy skills/ → target skills/
5. Copy commands/ → target commands/
6. Copy rules/ → target rules/

---

### 4. Hooks System

#### PreToolUse Hooks

Triggered **before** any tool (Bash, Read, API) executes.

**Examples:**
- `branch-guard.sh` — Blocks bash on master/main
- `grounding-guard.sh` — Blocks the first un-grounded code edit until `/ground` passes
- `complexity-guard.sh` — Alerts on manual exploration loops
- `read-dedup-guard.sh` — **Blocks** a full re-read of a file already in context this session and unchanged since (escape hatch: pass `offset`/`limit`, or Edit the file first). Cuts redundant `cache_read` tokens.
- `context-budget-guard.sh` — **Advisory** only: reminds you to `/clear` or split the task once the session transcript grows past size bands (long sessions re-send their whole context every turn).

**Registration:** `~/.claude/settings.json`
```json
{
  "hooks": {
    "PreToolUse": [
      "~/.claude/hooks/shared/branch-guard.sh",
      "~/.claude/hooks/shared/complexity-guard.sh",
      "~/.claude/hooks/claude/grounding-guard.sh",
      "~/.claude/hooks/claude/read-dedup-guard.sh",
      "~/.claude/hooks/claude/context-budget-guard.sh"
    ]
  }
}
```

**Token-efficiency hooks (`read-dedup-guard`, `context-budget-guard`):** added to attack the dominant token cost surfaced by usage analysis — ~96% of tokens are `cache_read` (context re-sent every turn), driven by monster sessions and redundant full-file reads (1,236 across 40% of sessions). They are the runtime enforcement counterpart to trimming `GLOBAL_RULES.md`.

#### CLI-Specific Hooks

- **claude/stop-guard.sh** — Blocks Claude Code stop if /precommit was skipped
- **codex/stop-guard.sh** — Similar for Codex CLI
- **gemini/stop-guard.sh** — Similar for Gemini CLI

#### Token-Efficiency Hooks: Cross-CLI Portability

The two token-efficiency hooks port unevenly because the deciding factor is each
CLI's pre-tool event coverage, not its data format (all three pass the same stdin
JSON: `session_id`, `transcript_path`, `tool_name`, `tool_input`).

| Hook | Claude Code | Codex CLI | Gemini CLI |
|---|---|---|---|
| `context-budget-guard` (advisory) | PreToolUse (broad) | PreToolUse/`Bash` only¹ | AfterAgent (`*`) |
| `read-dedup-guard` (blocks reads) | PreToolUse/`Read` ✅ | **Not possible**² | BeforeTool/`read_file` ⚠️ experimental³ |

1. Codex `PreToolUse` fires only for Bash / apply_patch / MCP, so the advisory
   only re-checks on shell-tool turns.
2. Codex `PreToolUse` does not intercept built-in file reads at all — there is no
   event to deny and no file path delivered, so `read-dedup-guard` cannot exist on
   Codex in any form (source: developers.openai.com/codex/hooks).
3. Gemini `BeforeTool` can deny (exit 2 / `decision:"deny"`) and matches tool
   names by regex, but it is **unverified** that it fires for the built-in
   `read_file` tool — confirm empirically before relying on the block. The Gemini
   port also tracks already-read paths in a per-session marker file instead of
   parsing the transcript, whose format Gemini documents as unstable.

---

### 5. Skills Directory

**Location:** `~/dotai/skills/`

**Purpose:** Reusable automation patterns for common tasks.

**Examples:**
- **git-push.md** — Auto-detect GitLab/GitHub, apply Keychain token
- **preflight.md** — Environment audit (branch, git state, env vars, MCP)

**Format:** Markdown with YAML frontmatter
```yaml
---
name: skill-name
description: What the skill does
---
```

**Distribution:** Copied to `~/.claude/skills/`, `~/.codex/skills/`, etc.

---

### 6. Commands Directory

**Location:** `~/dotai/commands/`

**Purpose:** Slash commands available across all CLIs.

**Examples:**
- **/plan** — Structured design planning workflow (Claude Code only)
- **/precommit** — Lint + build + test pipeline

---

### 7. Rules Directory

**Location:** `~/dotai/rules/`

**Purpose:** Language/framework-specific coding standards (path-filtered).

**Examples:**
- **vue.md** — Vue 3 Composition API, TypeScript, Pinia rules
- **node.md** — async/await, error handling, ES modules
- **laravel.md** — Service classes, Form Requests, Eloquent relationships

**Distribution:** Copied to `~/.claude/rules/` (auto-loaded by Claude Code)

---

### 8. Status Line (Claude Code only)

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

**CLI parity:** Claude Code only for now. Codex / Gemini status lines use different formats and stdin schemas; their adapters would live under `statusline/codex/` and `statusline/gemini/` when added.

**Distribution:** Copied to `~/.claude/statusline.sh` by `scripts/claude/install.sh`, which also registers the `statusLine` command in `settings.json` (idempotent).

---

## Workflow: Adding a New Rule

### Step 1: Add to GLOBAL_RULES.md

Edit `~/dotai/GLOBAL_RULES.md`:
```markdown
## New Rule Section
- Guideline 1
- Guideline 2
```

### Step 2: Commit

```bash
git add GLOBAL_RULES.md
git commit -m "Add new rule section"
```

### Step 3: Run install.sh

```bash
cd ~/dotai
echo "4" | bash install.sh  # Install to all CLIs
```

### Result

The new rules appear in:
- `~/.claude/CLAUDE.md` (Claude Code)
- `~/.codex/AGENTS.md` (Codex CLI)
- `~/.gemini/GEMINI.md` (Gemini CLI)

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

branch-guard.sh will **block** any bash operations if you accidentally switch to main:

```bash
git checkout main
bash -c "git status"  # ❌ Blocked
```

### Step 4: Switch Back to Feature Branch

```bash
git checkout feature/description
bash -c "git status"  # ✅ Allowed
```

---

## Testing branch-guard.sh

### Verify Hook Installation

```bash
# Check hook is registered
cat ~/.claude/settings.json | grep branch-guard

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
bash -c "echo 'This should fail'"  # ❌ Blocked with exit code 2
```

---

## Integration with Claude Code

### Automatic Hook Loading

When Claude Code restarts, it reads `~/.claude/settings.json` and activates hooks:

1. **PreToolUse hooks** execute before Bash/Read/API tools
2. **branch-guard.sh** blocks operations on protected branches
3. **complexity-guard.sh** alerts on deep exploration patterns

### Available Commands

- `/plan` — Structured design planning
- `/precommit` — Lint + build + test

### Available Skills

- `git-push` — Auto-auth for GitLab/GitHub
- `preflight` — Environment audit

### Available Rules

- `vue.md` — Vue 3 + TypeScript standards
- `node.md` — Node.js async/await + error handling
- `laravel.md` — Laravel architecture + testing

---

## Maintenance

### Update GLOBAL_RULES.md

Edit `~/dotai/GLOBAL_RULES.md` directly (source of truth).

Distribute via `install.sh` after committing.

### Add New Hook

1. Create hook file in `~/dotai/hooks/shared/` or CLI-specific directory
2. Add execution logic (bash script)
3. Run `install.sh` to register in settings.json
4. Test via manual tool execution

### Add New Skill

1. Create `~/dotai/skills/new-skill.md`
2. Follow git-push.md format (YAML frontmatter + Markdown docs)
3. Run `install.sh` to distribute to `~/.claude/skills/`

### Add New Rule

1. Create or edit `~/dotai/rules/{language}.md`
2. Run `install.sh` to distribute to `~/.claude/rules/`

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────┐
│         dotai (Source Repository)               │
├─────────────────────────────────────────────────┤
│ GLOBAL_RULES.md                                 │
│ hooks/shared/branch-guard.sh                    │
│ hooks/claude/stop-guard.sh                      │
│ skills/git-push.md, preflight.md                │
│ commands/plan.md, precommit.md                  │
│ rules/vue.md, node.md, laravel.md               │
│ statusline/claude/statusline.sh                 │
└─────────────────────────────────────────────────┘
          │
          │ install.sh
          ├─────────────────────────────────────┬────────────────┐
          ▼                                      ▼                ▼
  ┌──────────────────┐           ┌──────────────────┐   ┌─────────────┐
  │ ~/.claude        │           │ ~/.codex         │   │ ~/.gemini   │
  ├──────────────────┤           ├──────────────────┤   ├─────────────┤
  │ CLAUDE.md        │           │ AGENTS.md        │   │ GEMINI.md   │
  │ hooks/           │           │ hooks/           │   │ hooks/      │
  │ skills/          │           │ skills/          │   │ skills/     │
  │ commands/        │           │ (limited)        │   │ (limited)   │
  │ rules/           │           │                  │   │             │
  │ statusline.sh    │           │                  │   │             │
  └──────────────────┘           └──────────────────┘   └─────────────┘
```

---

## Key Principles

1. **Single Source of Truth** — Edit `GLOBAL_RULES.md` once, distribute to all CLIs
2. **Non-Destructive Hooks** — branch-guard.sh blocks, doesn't modify
3. **Reversible Distribution** — Can always re-run `install.sh` to sync
4. **CLI Parity** — Same rules across Claude Code, Codex, Gemini
5. **Feature Branch Workflow** — All edits on feature branches, protected main via hooks
