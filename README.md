# dotai — AI CLI Automation Toolkit

A personal AI workflow toolkit with automation configs, quality gates, and language-server integration for Claude Code, Gemini CLI, and Codex.

## Features

### ✅ Universal (All CLIs)
- **Precommit checks** — Automated lint, build, test before commits
- **Stop-guard hooks** — Force quality verification before Claude stops
- **Branch protection** — Safe checkout/commit/push workflow
- **Tech stack detection** — Auto-detect Laravel/Vue/Node.js projects
- **Reusable skills** — `/precommit`, `/plan`, `/git-push` commands

### 🚀 Claude Code Exclusive (v2.0.74+)
- **Language Server Protocol (LSP)** — Real-time type checking & symbol navigation
  - Supports: PHP (Intelephense), TypeScript/JavaScript, Vue
  - 50ms symbol lookup vs 45s text search
  - See `docs/LSP_SETUP.md` for setup

### 📋 Gemini CLI & Codex
- Full hooks/skills/scripts support
- LSP support planned when native LSP becomes available (see `docs/LSP_SETUP.md`)

---

## Quick Start

### Claude Code + LSP
```bash
# Install LSP servers
bash scripts/install-lsp.sh

# Enable LSP
export ENABLE_LSP_TOOL=1
echo 'export ENABLE_LSP_TOOL=1' >> ~/.zprofile
```

### All CLIs (hooks + skills)
```bash
# Install to ~/.claude, ~/.gemini, or ~/.codex
bash install.sh                 # Claude Code (default)
bash install.sh --gemini        # Gemini CLI
bash install.sh --codex         # Codex CLI
bash install.sh --all           # All three
```

---

## Project Structure

```
dotai/
├── CLAUDE.md                    ← Main project config
├── README.md                    ← This file
├── .claude/
│   ├── commands/
│   │   ├── precommit.md        ← Quality gate skill
│   │   └── precommit.sh        ← Actual implementation
│   ├── plugins/lsp/
│   │   └── .lsp.json           ← LSP config (Claude Code only)
│   └── skills/
│       ├── git-push.md         ← Auto-push to remote
│       └── parallel-design-agents.md
├── scripts/
│   └── install-lsp.sh          ← Install LSP binaries
├── hooks/
│   ├── shared/
│   │   └── branch-guard.sh    ← Safe branch workflow
│   └── claude/
│       └── stop-guard.sh       ← Force precommit before stop
├── docs/
│   ├── LSP_SETUP.md            ← LSP detailed guide
│   └── MULTI_AGENT_COORDINATION.md
└── rules/
    ├── laravel.md              ← Laravel-specific rules
    ├── vue.md                  ← Vue.js rules
    └── node.md                 ← Node.js rules
```

---

## Tech Stack Support

| Stack | Precommit | LSP | Tests |
|-------|-----------|-----|-------|
| **Laravel** | ✅ pint + php artisan test | ✅ Intelephense | ✅ |
| **Vue 3+** | ✅ yarn lint/build/test | ✅ Vue LS | ✅ |
| **Node.js** | ✅ yarn lint/test | ✅ TypeScript LS | ✅ |
| **Shell/dotai** | ✅ shellcheck | ❌ Not applicable | ✅ |

---

## Key Workflows

### 1. Safe Feature Branch Development
```bash
git checkout -b feature/my-feature  # branch-guard allows checkout
# Make changes...
/precommit                          # Verify quality
git commit                          # Only works on feature branch
git push                           # Only works on feature branch
```

### 2. Automatic Pre-Stop Validation
- Modify code → Claude tries to stop
- `stop-guard` blocks: "Run /precommit first!"
- You run `/precommit` → PASS → Claude can stop

### 3. Claude Code + LSP Code Navigation
```
You: "Where is calculateTotal defined?"
Claude: Jumps to exact file:line via LSP (not text search)
```

---

## Environment Setup

**Required:**
- Node.js 18+ (for LSP binaries)
- Git

**Optional:**
- `~/.zshrc` and `~/.zprofile` configured (for env vars)

**Claude Code:**
```bash
export ENABLE_LSP_TOOL=1  # Required for LSP
```

---

## Roadmap

- [ ] LSP support for Gemini CLI (awaiting native LSP)
- [ ] LSP support for Codex CLI (awaiting native LSP or MCP LSP Bridge)
- [ ] Automated /precommit hook integration (currently manual)
- [ ] Python/Go language support

---

## FAQ

**Q: Can I use this with Gemini CLI / Codex right now?**
A: Yes, but only hooks/skills/precommit (no LSP yet). LSP is Claude Code exclusive until Gemini/Codex add native support.

**Q: Why is LSP only for Claude Code?**
A: Claude Code got native LSP in v2.0.74 (Dec 2025). Gemini and Codex don't have it yet — [feature requests are open](docs/LSP_SETUP.md#future-gemini-cli--codex-cli-support).

**Q: Do I need to run `bash install.sh`?**
A: Only if you want to copy dotai to global `~/.claude/`. For local development, you don't need it.

**Q: How do I know LSP is working?**
A: Ask Claude "Where is [function_name] defined?" — it should give line:column instantly instead of searching.

---

## Contributing

This is a personal toolkit, but if you use it and find issues, feel free to report them in your own fork or adapt it for your workflow.

---

**Last updated:** May 2026
