#!/usr/bin/env bash
#
# install.sh — install dotai into ~/.claude/
#
# What this does:
#   1. Syncs global rules from dotai/GLOBAL_RULES.md to ~/.claude/CLAUDE.md
#   2. Copies /precommit command to ~/.claude/commands/
#   3. Copies hook scripts to ~/.claude/hooks/
#   4. Registers Stop and PreToolUse hooks in ~/.claude/settings.json

set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
}

DOTAI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Installing dotai from $DOTAI_DIR → $CLAUDE_DIR"
echo ""

# ── 1. Global Rules Sync ──────────────────────────────────────────────────────

mkdir -p "$CLAUDE_DIR"
if [ -f "$DOTAI_DIR/GLOBAL_RULES.md" ]; then
  cp "$DOTAI_DIR/GLOBAL_RULES.md" "$CLAUDE_DIR/CLAUDE.md"
  echo "✅ Global Rules       → $CLAUDE_DIR/CLAUDE.md"
fi

# ── 2. /precommit command ─────────────────────────────────────────────────────

mkdir -p "$CLAUDE_DIR/commands"
cp "$DOTAI_DIR/commands/precommit.md" "$CLAUDE_DIR/commands/precommit.md"
echo "✅ /precommit command → $CLAUDE_DIR/commands/precommit.md"

# ── 3. hook scripts ───────────────────────────────────────────────────────────

mkdir -p "$CLAUDE_DIR/hooks"

# stop-guard
cp "$DOTAI_DIR/hooks/stop-guard.sh" "$CLAUDE_DIR/hooks/stop-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/stop-guard.sh"
echo "✅ stop-guard.sh     → $CLAUDE_DIR/hooks/stop-guard.sh"

# complexity-guard
cp "$DOTAI_DIR/hooks/complexity-guard.sh" "$CLAUDE_DIR/hooks/complexity-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/complexity-guard.sh"
echo "✅ complexity-guard.sh → $CLAUDE_DIR/hooks/complexity-guard.sh"

# ── 4. Register hooks in settings.json ────────────────────────────────────────

SETTINGS="$CLAUDE_DIR/settings.json"

# Read existing settings (default to empty object if file is missing or empty)
if [[ -f "$SETTINGS" ]] && [[ -s "$SETTINGS" ]]; then
  EXISTING=$(cat "$SETTINGS")
else
  EXISTING="{}"
fi

# Merge hooks — preserves all existing settings
UPDATED=$(echo "$EXISTING" | jq --arg home "$HOME" '
  # Register Stop hook
  .hooks.Stop = ([
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.claude/hooks/stop-guard.sh",
          "timeout": 15
        }
      ]
    }
  ] + (.hooks.Stop // [] | map(select(
    (.hooks[0].command | test("stop-guard\\.sh$")) | not
  )))) |
  # Register PreToolUse hook for complexity-guard
  .hooks.PreToolUse = ([
    {
      "matcher": "Grep|Read|Glob|grep_search|read_file|glob|list_directory",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.claude/hooks/complexity-guard.sh"
        }
      ]
    }
  ] + (.hooks.PreToolUse // [] | map(select(
    (.hooks[0].command | test("complexity-guard\\.sh$")) | not
  ))))
')

echo "$UPDATED" > "$SETTINGS"
echo "✅ Hooks registered   → $SETTINGS"

# ── 5. Install rules (global) ─────────────────────────────────────────────────

mkdir -p "$CLAUDE_DIR/rules"
cp "$DOTAI_DIR/rules/laravel.md" "$CLAUDE_DIR/rules/laravel.md"
cp "$DOTAI_DIR/rules/vue.md"     "$CLAUDE_DIR/rules/vue.md"
cp "$DOTAI_DIR/rules/node.md"    "$CLAUDE_DIR/rules/node.md"
echo "✅ Rules              → $CLAUDE_DIR/rules/"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "dotai installed. Restart Claude Code to activate the hooks."
echo ""
echo "Available after restart:"
echo "  /precommit       run lint + build + test"
echo "  stop-guard       auto-blocks stopping if /precommit was skipped or failed"
echo "  complexity-guard alerts on manual exploration loops"
echo "  rules/           laravel.md · vue.md · node.md (path-filtered)"
echo ""
echo "Note: if path-filtered rules do not activate in a project, run:"
echo "  bash $DOTAI_DIR/install-project-rules.sh"
