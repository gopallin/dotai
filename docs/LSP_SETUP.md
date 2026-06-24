# Claude Code LSP (Language Server Protocol) Setup

**⚠️ Claude Code Only (v2.0.74+)**

This guide is for Claude Code CLI. Antigravity CLI and Codex CLI do not yet have native LSP support. See end of document for future roadmap.

---

## What You Get

Once LSP is enabled, Claude automatically:
- **Jumps to definitions** instead of text-searching (50ms vs 45s)
- **Detects type errors** in real-time as you edit
- **Tracks symbol relationships** (function calls, class inheritance, variable references)
- **Understands code structure** instead of guessing

Example: When you ask "where is `calculateTotal` defined?", Claude uses LSP to pinpoint the exact file:line instead of searching text.

---

## Installation Steps

### 1. Install LSP Binaries
```bash
bash scripts/install-lsp.sh
```

This installs:
- **intelephense** (PHP/Laravel)
- **typescript-language-server** (TypeScript/JavaScript/Vue)
- **@vue/language-server** (Vue 3+ single-file components)

### 2. Enable LSP in Claude Code
```bash
# Temporarily enable
export ENABLE_LSP_TOOL=1

# Make permanent - add to ~/.zshrc
echo 'export ENABLE_LSP_TOOL=1' >> ~/.zshrc
source ~/.zshrc
```

### 3. Verify Configuration
The `.claude/plugins/lsp/.lsp.json` file is already configured for:
- `.php` files → Intelephense
- `.ts/.tsx/.js/.jsx` files → TypeScript LS
- `.vue` files → Vue LS

---

## Behavior After Setup

**Automatic (no manual command needed):**
- Claude reads code and sees real type info
- Errors like `undefined variable` are caught immediately
- Function signatures and return types are accurate

**Manual (you control):**
- Enable/disable via `ENABLE_LSP_TOOL` env var
- Configure language settings in `.lsp.json`

---

## Integration with dotai Workflows

### With `/precommit` Hook
LSP diagnostics are already checked before commit - prevents merging type errors.

### With `stop-guard` Hook
If LSP detects errors, stop-guard blocks completion until fixed.

### With Code Reviews
Claude can now validate Antigravity code review feedback against actual type definitions.

---

## Troubleshooting

**LSP not responding?**
```bash
# Restart Claude Code session
# Check if binary is in PATH
which intelephense
which typescript-language-server
which vue-language-server
```

**Still seeing text-search behavior?**
- Verify `ENABLE_LSP_TOOL=1` is set
- Restart Claude Code session
- Check `.lsp.json` is in `.claude/plugins/lsp/`

**Type checking too strict?**
- Configure `tsconfig.json` (TypeScript) or `phpstan.neon` (PHP) to relax rules
- LSP respects your project's existing configuration

---

## Future: Antigravity CLI & Codex CLI Support

- **Antigravity CLI** — Currently uses MCP and Agent Client Protocol (ACP).
- **Codex CLI** — [PR #1203](https://github.com/openai/codex/pull/1203) pending.

Once Antigravity CLI or Codex CLI get native LSP support:

1. Map the corresponding file extension filters in `rules/`
2. Update `scripts/agy/install.sh` and `scripts/codex/install.sh` with LSP binary installation
3. Cross-CLI LSP feature parity achieved

For now, this dotai LSP integration is **Claude Code exclusive**.
