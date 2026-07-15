# dotai

A personal AI workflow toolkit — analogous to dotfiles, but for AI CLI tools. Stores automation configs and quality gates for AI-assisted development.

## Core Philosophy

**Don't trust AI to do the right thing. Use code to ensure it does.**

The common pain point when using AI for development:
- AI says "done", but lint failed, tests weren't run, security wasn't checked
- You have to manually remind AI to run verification steps every time
- "Remember to do X" in CLAUDE.md relies on AI compliance, not enforcement

dotai's solution: replace **CLAUDE.md rules (depends on AI cooperation)** with **Hooks (OS-level forced interception)**.

---

## Key Concepts

Before developing this project, understand the difference between these four components:

| Component | Form | Triggered By | Can AI Bypass? |
|---|---|---|---|
| **Skill** | markdown | Keyword triggers, loaded as context | Yes (just a prompt) |
| **Command** | markdown | User explicitly calls `/xxx` | Yes (just instructions) |
| **Hook** | shell script | Event fires automatically (OS level) | No (enforced) |
| **Plugin** | directory structure | Loaded after installation | — |

**The critical difference between CLAUDE.md and Hook:**
- CLAUDE.md: tells AI "you should do this" — AI reads it, but may forget or get overridden
- Hook: the moment AI tries to stop, the OS intercepts and runs the script — `exit 2` = forced block, AI cannot escape

---

## Existing Official Claude Code Skills (No Need to Reinvent)

After installing claude-code-marketplace, the following skills already cover part of the workflow:

| Official Skill | Equivalent Concept | Notes |
|---|---|---|
| `hookify` | Basic stop-guard | markdown-configured hooks, but can only check "was it run" — cannot do double-layer validation |
| `code-review` | AI code review | Multi-agent parallel review with confidence scoring |
| `feature-dev` | Tech spec + planning | Full 7-phase feature development workflow |
| `commit-commands` | Git operations | `/commit`, `/commit-push-pr`, but **does not run lint/test/build** |

**dotai only fills the genuine gaps. Do not reimplement what already exists.**

---

## Two Core Components to Build

### 1. `/precommit` Command

**Type:** Slash Command (markdown)

**Purpose:** Run a full quality verification pipeline before committing

**Triggered by:** User or AI explicitly calling `/precommit`

**What it does:**
1. Detect the current project's tech stack (Laravel / Vue / Node.js)
2. Run the appropriate commands based on the stack:
   - **Node.js / Vue:** `yarn lint:fix` → `yarn build` → `yarn test:unit`
   - **Laravel:** `./vendor/bin/pint` → `php artisan test`
3. Output `✅ step_name (Xs)` or `❌ step_name` for each step
4. On any failure: stop immediately and report, do not continue

**Output format (used by stop-guard for parsing):**
```
✅ lint_fix (27s)
✅ build (8s)
✅ test_unit (150s)
## Overall: ✅ PASS
```
or:
```
❌ test_unit (45s) - 3 tests failed
## Overall: ❌ FAIL
```

**File location:** `commands/precommit.md`

---

### 2. `stop-guard` Hook

**Type:** Hook (shell script)

**Purpose:** Force double-layer validation whenever Claude is about to stop

**Triggered by:** `Stop` event fires automatically (when Claude says it's done and is about to end its response)

**Double-layer validation logic:**

```
Layer 1: Were any code files changed?
  → Scan transcript for Edit/Write tool calls
  → Changes found → proceed to Layer 2
  → No changes → allow stop

Layer 2 (only if changes were found):
  → Check whether /precommit was executed
  → Check whether /precommit output "Overall: ✅ PASS"
  → Both satisfied → allow stop
  → Either unsatisfied → exit 2, block stop, output instructions
```

**Key principle: Not just "was it run" — also "did it pass".**

Ran but FAIL? Still cannot stop.

**Technical details:**
- Read JSON from stdin: `{"transcript_path": "/path/to/transcript.jsonl", "stop_hook_active": true}`
- Transcript is JSONL format, one record per line
- Requires `jq` for parsing (pre-installed on macOS)
- exit 0 = allow stop, exit 2 = block stop

**File locations:** 
- `hooks/claude/stop-guard.sh` (Claude Code)
- `hooks/codex/stop-guard.sh` (Codex CLI)
- `hooks/agy/stop-guard.sh` (Antigravity CLI)

---

## Project Structure

```
~/dotai/                        ← git repo (GitHub: gopallin/dotai)
├── CLAUDE.md                   ← this file
├── install.sh                  ← unified installer entry point
├── scripts/
│   ├── claude/
│   │   └── install.sh          ← Claude Code installer
│   ├── codex/
│   │   └── install.sh          ← Codex CLI installer
│   └── agy/
│       └── install.sh          ← Antigravity CLI installer
├── commands/
│   ├── precommit.md            ← /precommit slash command
│   ├── plan.md                 ← /plan design planning command (+ ticket decomposition, CONTEXT.md glossary)
│   ├── next-ticket.md          ← /next-ticket pick up next unblocked ticket (one slice per session)
│   └── handoff.md              ← /handoff compact resume file before /clear (local-only, git-ignored)
├── skills/
│   ├── git-push.md             ← automatic GitLab/GitHub push
│   └── ground.md               ← /ground pre-implementation grounding check
├── hooks/
│   ├── hooks.json              ← hook event declarations
│   ├── claude/
│   │   ├── stop-guard.sh       ← Claude Code Stop event hook
│   │   ├── grounding-guard.sh  ← Claude PreToolUse hook (blocks first un-grounded edit)
│   │   ├── read-dedup-guard.sh ← Claude PreToolUse hook (blocks full re-reads of files already in context)
│   │   └── context-budget-guard.sh ← Claude PreToolUse hook (advisory: reminds to /clear when session grows large)
│   ├── codex/
│   │   ├── stop-guard.sh       ← Codex CLI Stop event hook
│   │   ├── grounding-guard.sh  ← Codex grounding hook (advisory)
│   │   └── context-budget-guard.sh ← Codex advisory (reminds to start fresh; PreToolUse/Bash only)
│   ├── agy/
│   │   ├── stop-guard.sh       ← Antigravity CLI Stop event hook
│   │   ├── grounding-guard.sh  ← Antigravity grounding hook (advisory)
│   │   ├── context-budget-guard.sh ← Antigravity advisory (reminds to start fresh; AfterAgent)
│   │   └── read-dedup-guard.sh ← Antigravity block via BeforeTool/read_file (EXPERIMENTAL — needs verification)
│   └── shared/
│       ├── complexity-guard.sh ← shared PreToolUse hook (all CLIs)
│       └── branch-guard.sh     ← blocks edits/commits on master/main
└── rules/
    ├── laravel.md              ← Laravel-specific guidelines
    ├── vue.md                  ← Vue.js-specific guidelines
    └── node.md                 ← Node.js-specific guidelines
```

**Installation:**

```bash
# Claude Code (default)
bash install.sh

# Codex CLI
bash install.sh --codex

# Antigravity CLI
bash install.sh --agy

# All CLIs
bash install.sh --all
```

**What each installer does:**
- Copies files to recognized locations (`~/.claude/`, `~/.codex/`, `~/.gemini/`)
- Installs commands, skills, hooks, and rules for the selected CLI
- Merges hook configurations into settings files

---

## Owner's Tech Stack

- **Backend:** Laravel (PHP)
- **Frontend:** Vue.js (JS + TS)
- **Services:** Node.js
- **Rule:** one repo = one tech stack (no monorepo)

Tech stack detection logic for `/precommit`:
- Has `artisan` → Laravel
- Has `package.json` + `vite.config.*` → Vue
- Has `package.json` → Node.js

---

## Design Principles

1. **Fill gaps, don't reinvent** — do not rewrite functionality already covered by official skills
2. **Enforce with code, not prompts** — quality gates use hooks, not CLAUDE.md rules
3. **Complement official skills** — dotai's role is to fill gaps; the complete workflow is:
   ```
   /feature-dev → /ground → (grounding-guard auto-enforces) → implement
                → /precommit → (stop-guard auto-enforces) → git commit
   ```
   `grounding-guard` is the front-of-work mirror of `stop-guard`: it blocks the
   first non-doc code edit of a session until `/ground` emits `GROUNDING_STATUS=PASS`
   (verifies existing patterns + data/IDs before writing). See `plan-grounding-guard.md`.
4. **Extensible** — adapters for Antigravity CLI (agy) and other tools can be added later, sharing the same core `commands/` and `hooks/` logic

---

## Recommended Development Order

1. Create `plugin.json` (Claude Code plugin manifest)
2. Implement `commands/precommit.md` (do this first — stop-guard depends on its output format)
3. Implement `hooks/hooks.json` + `hooks/stop-guard.sh`
4. Implement `install.sh`
5. Write `README.md`
6. Test in a real project

---

## LSP (Language Server Protocol) Integration

**⚠️ Claude Code Only (v2.0.74+)**

Claude Code now supports LSP for real-time code intelligence. This allows Claude to understand code structure, type definitions, and symbol relationships instead of relying on text search.

*Note: Antigravity CLI and Codex CLI do not yet have native LSP support. Future roadmap includes MCP-based LSP Bridge for those CLIs.*

**Supported Languages:**
- PHP/Laravel (via Intelephense)
- TypeScript/JavaScript (via TypeScript LS)
- Vue 3+ (via Vue LS)

**Setup (Claude Code only):**
```bash
# 1. Install all LSP servers
bash scripts/install-lsp.sh

# 2. Enable LSP in your shell
export ENABLE_LSP_TOOL=1

# 3. Make permanent - add to ~/.zprofile
echo 'export ENABLE_LSP_TOOL=1' >> ~/.zprofile
```

**Benefits:**
- Symbol lookup: 50ms instead of 45 seconds (text search)
- Real-time type error detection during edits
- Accurate function signatures and return types
- Fewer "wrong approach" reversals in code reviews

**Configuration:**
- All LSP settings are in `.claude/plugins/lsp/.lsp.json`
- Each language server is pre-configured for this project
- See `docs/LSP_SETUP.md` for detailed troubleshooting

**Integration with dotai Workflows:**
- `/precommit` can now validate type errors from LSP before commit
- `stop-guard` hook checks LSP diagnostics to prevent merging broken code
- Code review sessions benefit from accurate type context

**Future: Antigravity CLI & Codex CLI Support**
- Waiting for native LSP or official MCP LSP Bridge support
- Will implement via [Codex LSP Bridge](https://glama.ai/mcp/servers/CesarPetrescu/lsp-mcp) when ready

---

## Future Scope (Out of Scope for Now)

- Adapters for Antigravity CLI and other AI CLIs
- `/analyze-log` command (production issue diagnosis)
- Support for additional tech stacks (Go, Python, etc.)
