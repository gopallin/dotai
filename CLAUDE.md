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
├── .claude/
│   └── reviewer-rules.md       ← dotai's OWN L1/L2/L3 rules (discovery slot 1; not installed)
├── install.sh                  ← unified installer entry point
├── scripts/
│   ├── claude/
│   │   └── install.sh          ← Claude Code installer
│   ├── codex/
│   │   └── install.sh          ← Codex CLI installer
│   └── agy/
│       └── install.sh          ← Antigravity CLI installer
├── commands/
│   ├── precommit.md            ← /precommit slash command (documents output format + stop-guard contract)
│   ├── precommit.sh            ← /precommit execution script (tech-stack detection → lint/build/test; outputs PRECOMMIT_STATUS=)
│   ├── plan.md                 ← /plan design planning command (+ ticket decomposition, CONTEXT.md glossary)
│   ├── next-ticket.md          ← /next-ticket pick up next unblocked ticket (one slice per session)
│   ├── handoff.md              ← /handoff compact resume file before /clear (local-only, git-ignored)
│   ├── prompt.md               ← /prompt guided wizard: collects type/goal/files/scope/done-when, builds AI-ready task prompt via prompt-template.sh
│   └── prompt-template.sh      ← shell template emitter for /prompt (feature|bugfix|refactor skeletons; kept out of .md to avoid loading all templates into context)
├── skills/                     ← one dir per skill; all three CLIs require <name>/SKILL.md
│   ├── git-push/SKILL.md       ← automatic GitLab/GitHub push
│   ├── ground/SKILL.md         ← /ground pre-implementation grounding check
│   ├── parallel-design-agents/SKILL.md ← multi-agent workflow to explore different design options
│   ├── preflight/SKILL.md      ← environment verification checklist before starting work
│   ├── reviewer-rules/SKILL.md ← single source for the L1/L2/L3 review protocol (used by /ground + /ship)
│   └── ship/SKILL.md           ← /ship test → L1/L2/L3 review → commit → push → open MR/PR (forge-routed)
├── hooks/
│   ├── hooks.json              ← hook event declarations
│   ├── claude/
│   │   ├── stop-guard.sh       ← Claude Code Stop event hook
│   │   ├── grounding-guard.sh  ← Claude PreToolUse hook (blocks first un-grounded edit)
│   │   ├── read-dedup-guard.sh ← Claude PreToolUse hook (blocks full re-reads of files already in context)
│   │   ├── context-budget-guard.sh ← Claude PreToolUse hook (advisory: reminds to /clear when session grows large)
│   │   └── handoff-reminder.sh ← Claude SessionStart hook (after /clear: offer /resume+/handoff or transcript rebuild)
│   ├── codex/
│   │   ├── stop-guard.sh       ← Codex CLI Stop event hook
│   │   ├── grounding-guard.sh  ← Codex PreToolUse hook (blocks first un-grounded apply_patch)
│   │   ├── context-budget-guard.sh ← Codex advisory (reminds to start fresh; PreToolUse/Bash only)
│   │   └── handoff-reminder.sh ← Codex SessionStart hook after /clear
│   ├── agy/
│   │   ├── hooks.json          ← agy named-hook registration, installed to ~/.gemini/config/hooks.json
│   │   ├── stop-guard.sh       ← agy Stop hook (blocks the stop if PRECOMMIT_STATUS=PASS absent)
│   │   ├── grounding-guard.sh  ← agy PreToolUse (write_to_file|replace_file_content|edit_notebook)
│   │   ├── context-budget-guard.sh ← agy PreInvocation advisory (injects an ephemeralMessage)
│   │   ├── read-dedup-guard.sh ← agy PreToolUse/view_file dedup block
│   │   └── shared-guard-adapter.sh ← translates agy's JSON contract ↔ the shared guards' exit codes
│   └── shared/
│       ├── complexity-guard.sh ← shared PreToolUse hook (all CLIs)
│       └── branch-guard.sh     ← blocks edits/commits on master/main
├── rules/                      ← ⚠️ loaded GLOBALLY in every project, not path-filtered
│   ├── laravel.md              ← Laravel-specific guidelines
│   ├── vue.md                  ← Vue.js-specific guidelines
│   └── node.md                 ← Node.js-specific guidelines
└── docs/                       ← NOT installed; reference material and templates
    └── reviewer-rules.example.md ← project-specific reviewer rules to copy into a project repo
```

**Where reviewer rules live.** The L1/L2/L3 checklist was inlined in both
`ground` and `ship` and had already drifted between them, while naming one
project's tables and lock keys — which then loaded in every unrelated repo,
because `rules/` and `skills/` are global and nothing filters them by path.

Now: the stack-agnostic protocol is the `reviewer-rules` **skill** (one copy, and a
skill rather than a `rules/*.md` file because Codex has no `rules/` mechanism, so
any hardcoded `~/.claude/rules/...` path would be wrong there). Project-specific
rules are discovered from the project itself — `.claude/reviewer-rules.md` or a
`## Reviewer Rules` section in its `CLAUDE.md`. `docs/reviewer-rules.example.md`
holds the previous Laravel/NestJS content as a template to copy into that project.
`tests/reviewer-rules.test.sh` fails if project-specific assets reappear anywhere
under `skills/` or `rules/`.

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

**Skill layout — all three CLIs agree, and a wrong layout fails silently:**

| CLI | Skills root | Verified by |
|---|---|---|
| Claude Code | `~/.claude/skills/<name>/SKILL.md` | skill list reload |
| Codex | `~/.codex/skills/<name>/SKILL.md` | `codex exec` skill list |
| Antigravity | `~/.gemini/config/skills/<name>/SKILL.md` | `agy -p` skill list |

A flat `skills/<name>.md` is **never discovered** — no warning, the skill just
does not exist. agy's global root is `~/.gemini/config/`, **not** `~/.gemini/`
(the `agy` binary carries the template `{appDataDir}/skills/{skill_name}/SKILL.md`).
`tests/skills-install.test.sh` locks all three layouts down, including cleanup of
the legacy flat files.

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

---

## §agy Hook Contract

agy's hook system is **not** the Claude/Codex one. An earlier dotai relied on the
Claude-shaped assumptions and every agy guard was silently inert as a result.

Each claim below is marked with how it is known: **[probed]** = observed in a live
`agy -p` session, **[binary]** = string extracted from the `agy` executable,
**[doc]** = agy's built-in `agy-customizations` guide only. Treat `[doc]`-only rows
as unverified.

**Where config lives.** agy's global customization root is `~/.gemini/config/`.

| What | Path | Verified by |
|---|---|---|
| Lifecycle hooks | `~/.gemini/config/hooks.json` | **[probed]** a `Stop` hook there fires |
| Skills (= slash commands) | `~/.gemini/config/skills/<name>/SKILL.md` | **[probed]** `/dotai-probe` skill was invocable; **[binary]** `{appDataDir}/skills/{skill_name}/SKILL.md` |
| Global rules | `~/.gemini/config/AGENTS.md` | **[doc]** |

`antigravity-cli/settings.json` `.hooks.*` is **not** read: an `AfterAgent` probe
registered there did not fire in the same run where the `config/hooks.json` `Stop`
probe did. `settings.json` is still used for `.statusLine`.

**Event names** — only `PreToolUse`, `PostToolUse`, `PreInvocation`,
`PostInvocation`, `Stop` exist **[doc]**; `PreToolUse` and `Stop` **[probed]** to
fire. `AfterAgent` and `BeforeTool` **do not exist** — that is what the old
`read-dedup-guard` "needs BeforeTool verification" note was really asking about,
and the answer is that the event was never real.

**Config shape.** Top-level keys are hook *names*, not events:

```json
{ "dotai-stop-guard": { "Stop": [ { "type": "command", "command": "…" } ] } }
```

`PreToolUse`/`PostToolUse` wrap handlers in `{matcher, hooks:[…]}`; the other
three take a flat handler list.

**I/O contract — this is the part that bites.** agy passes JSON on stdin and reads
a JSON decision from **stdout**. The **exit code is ignored**, so a guard that
writes stderr and `exit 2` fails *open*.

| Event | Block with | Allow with |
|---|---|---|
| `PreToolUse` | `{"decision":"deny","reason":"…"}` **[probed]** — blocks, and `reason` reaches the model | `{"decision":"allow"}` **[probed]** |
| `Stop` | `{"decision":"continue","reason":"…"}` **[doc]** | any other decision **[probed]** |

Only `Stop`'s `continue` remains doc-only; `PreToolUse` `deny` is confirmed.
| `PreInvocation` | n/a — advise via `{"injectSteps":[{"ephemeralMessage":"…"}]}` **[doc]** | `{}` |

stderr is never shown to the user or the model, so advisory guards must return
their text as a `reason` or an `ephemeralMessage`.

**Payload keys are camelCase; tool arg keys are PascalCase.**

- Common: `conversationId`, `transcriptPath`, `workspacePaths`,
  `artifactDirectoryPath`, `modelName`
- `PreToolUse`: `toolCall.name`, `toolCall.args`, `stepIdx`
- `Stop`: `terminationReason`, `executionNum`, `fullyIdle`, `error`

**Tool names** **[probed]** (also **[binary]**: lowercased step type with the
`CORTEX_STEP_TYPE_` prefix stripped). Arg keys per tool are tabulated below:

| Purpose | agy tool |
|---|---|
| create file | `write_to_file` |
| edit in place | `replace_file_content` |
| read file | `view_file`, `view_file_outline` |
| shell | `run_command` |
| list dir | `list_dir` |
| search | `grep_search`, `code_search` |

There is no `write_file`, `edit_file`, `create_file`, `replace_in_file`, or
`read_file` — dotai matched those for a while and therefore matched nothing.

`tests/agy-hook-contract.test.sh` pins all of the above; `tests/agy-install.test.sh`
pins where the installer writes it.

### Tool arg keys — all observed from live PreToolUse payloads

Args are PascalCase, and **the path key differs per tool** — this is the detail that
silently breaks a guard, because a missed key yields an empty path and the hook
fails open.

| Tool | Arg keys |
|---|---|
| `view_file` | `AbsolutePath` |
| `write_to_file` | `TargetFile`, `CodeContent`, `Overwrite`, `Description` |
| `replace_file_content` | `TargetFile`, `StartLine`, `EndLine`, `TargetContent`, `ReplacementContent`, `Instruction`, `AllowMultiple`, `Description` |
| `run_command` | `CommandLine`, `Cwd`, `WaitMsBeforeAsync`, `BypassSandbox` |
| `list_dir` | `DirectoryPath` |
| `ask_permission` | `Action`, `Reason`, `Target` |

So a path is `TargetFile` for the edit tools and `AbsolutePath` for reads — the
guards check exactly those two.

**The `deny` path is confirmed to block.** With a `PreToolUse` deny registered on
the edit tools, agy left the target file untouched and reported back verbatim:

> "I attempted to use the file writing tool to create `created.txt` as requested,
> but the tool is currently being blocked by the system
> (**"DOTAI-PROBE-DENY: blocked on purpose"**)."

That also confirms `reason` reaches the model, which is why advisory guards put
their text there instead of stderr.

**Hook ordering note.** When two named hooks match the same tool, a `deny` from one
can short-circuit the other — a logging hook registered alongside a denying hook
did not always run. Do not rely on two hooks both executing for one tool call.

### Still unverified

A **ranged** `view_file` payload. Asked for specific lines, agy reaches for
`run_command` instead, so the range keys were never captured. `read-dedup-guard`
assumes `StartLine`/`EndLine` because its sibling `replace_file_content` uses
exactly those names. If that is wrong the guard fails **open** on ranged reads — it
can never wrongly block one.

To capture a payload for any tool, log one live invocation:

```bash
cat > ~/.gemini/config/hooks.json <<'EOF'
{"probe":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command",
  "command":"cat >> /tmp/agy-args.jsonl; printf '\n' >> /tmp/agy-args.jsonl; printf '%s' '{\"decision\":\"allow\"}'"}]}]}}
EOF
cd /tmp && printf 'a\nb\n' > p.txt
agy -p "Read p.txt then change 'b' to 'B' in place." --dangerously-skip-permissions --print-timeout 300s
jq -c '{tool:.toolCall.name, argKeys:(.toolCall.args|keys)}' /tmp/agy-args.jsonl | sort -u
# then restore: cp <backup> ~/.gemini/config/hooks.json   (or: bash install.sh --agy)
```

> `agy -p` can take well over 90s per call. A timeout is not a quota error — raise
> `--print-timeout` (300s worked) before concluding anything is broken.

---

## §CLI Feature Gaps

### `handoff-reminder.sh` — agy and Codex

**agy** does not have a `SessionStart` event equivalent to Claude Code's
`source=clear` signal. This means there is no reliable way to detect that a new
session was started from `/clear` vs a fresh start. `handoff-reminder.sh` is
therefore **not implemented for agy** — the feature is inherently
Claude Code-specific.

If agy adds a post-clear session lifecycle event in the future, port
`hooks/claude/handoff-reminder.sh` using the same pattern.

### Commands — agy has no such concept

agy's customization types are Rules, Skills, Plugins, Hooks, and MCP servers.
There is no "commands" type; slash commands are resolved from **skills**. dotai's
`/precommit`, `/plan`, `/next-ticket`, `/handoff`, and `/prompt` are therefore
installed for agy as `~/.gemini/config/skills/<name>/SKILL.md`, with `name:`
injected into the frontmatter when the source `.md` only carries `description:`.
`~/.gemini/commands/` is removed on install — agy never read it.
