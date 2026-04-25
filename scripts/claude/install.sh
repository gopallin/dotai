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

DOTAI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Installing dotai from $DOTAI_DIR → $CLAUDE_DIR"
echo ""

# ── 1. Global Rules Sync ──────────────────────────────────────────────────────

mkdir -p "$CLAUDE_DIR"
if [ -f "$DOTAI_DIR/GLOBAL_RULES.md" ]; then
  cp "$DOTAI_DIR/GLOBAL_RULES.md" "$CLAUDE_DIR/CLAUDE.md"
  echo "✅ Global Rules       → $CLAUDE_DIR/CLAUDE.md"
fi

# ── 2. Commands ───────────────────────────────────────────────────────────────

mkdir -p "$CLAUDE_DIR/commands"
cp "$DOTAI_DIR/commands/precommit.md" "$CLAUDE_DIR/commands/precommit.md"
echo "✅ /precommit command → $CLAUDE_DIR/commands/precommit.md"

cp "$DOTAI_DIR/commands/plan.md" "$CLAUDE_DIR/commands/plan.md"
echo "✅ /plan command      → $CLAUDE_DIR/commands/plan.md"

# ── 2b. Skills ────────────────────────────────────────────────────────────────

mkdir -p "$CLAUDE_DIR/skills"
if [ -d "$DOTAI_DIR/skills" ]; then
  cp "$DOTAI_DIR/skills"/*.md "$CLAUDE_DIR/skills/" 2>/dev/null || true
  echo "✅ Skills              → $CLAUDE_DIR/skills/"
fi

# ── 3. hook scripts ───────────────────────────────────────────────────────────

mkdir -p "$CLAUDE_DIR/hooks"

# Claude Code hooks
mkdir -p "$CLAUDE_DIR/hooks/claude"
cp "$DOTAI_DIR/hooks/claude/stop-guard.sh" "$CLAUDE_DIR/hooks/claude/stop-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/claude/stop-guard.sh"
echo "✅ claude/stop-guard.sh     → $CLAUDE_DIR/hooks/claude/stop-guard.sh"

# Codex hooks
mkdir -p "$CLAUDE_DIR/hooks/codex"
cp "$DOTAI_DIR/hooks/codex/stop-guard.sh" "$CLAUDE_DIR/hooks/codex/stop-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/codex/stop-guard.sh"
echo "✅ codex/stop-guard.sh      → $CLAUDE_DIR/hooks/codex/stop-guard.sh"

# Gemini hooks
mkdir -p "$CLAUDE_DIR/hooks/gemini"
cp "$DOTAI_DIR/hooks/gemini/stop-guard.sh" "$CLAUDE_DIR/hooks/gemini/stop-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/gemini/stop-guard.sh"
echo "✅ gemini/stop-guard.sh     → $CLAUDE_DIR/hooks/gemini/stop-guard.sh"

# Shared hooks
mkdir -p "$CLAUDE_DIR/hooks/shared"
cp "$DOTAI_DIR/hooks/shared/complexity-guard.sh" "$CLAUDE_DIR/hooks/shared/complexity-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/shared/complexity-guard.sh"
echo "✅ shared/complexity-guard.sh → $CLAUDE_DIR/hooks/shared/complexity-guard.sh"

cp "$DOTAI_DIR/hooks/shared/branch-guard.sh" "$CLAUDE_DIR/hooks/shared/branch-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/shared/branch-guard.sh"
echo "✅ shared/branch-guard.sh     → $CLAUDE_DIR/hooks/shared/branch-guard.sh"

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
  # Register Stop hook (Claude Code)
  .hooks.Stop = ([
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.claude/hooks/claude/stop-guard.sh",
          "timeout": 15
        }
      ]
    }
  ] + (.hooks.Stop // [] | map(select(
    (.hooks[0].command | test("claude/stop-guard\\.sh$")) | not
  )))) |
  # Register PreToolUse hooks (complexity-guard + branch-guard)
  .hooks.PreToolUse = ([
    {
      "matcher": "Grep|Read|Glob|grep_search|read_file|glob|list_directory",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.claude/hooks/shared/complexity-guard.sh"
        }
      ]
    },
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.claude/hooks/shared/branch-guard.sh",
          "timeout": 5
        }
      ]
    }
  ] + (.hooks.PreToolUse // [] | map(select(
    (.hooks[0].command | test("shared/(complexity|branch)-guard\\.sh$")) | not
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
echo "  /plan            structured design planning (user chooses to save to plan.md or ClickUp)"
echo "  /precommit       run lint + build + test"
echo "  stop-guard       auto-blocks stopping if /precommit was skipped or failed"
echo "  complexity-guard alerts on manual exploration loops"
echo "  branch-guard     prevents accidental pushes to master/main"
echo "  rules/           laravel.md · vue.md · node.md (path-filtered)"
echo "  skills/          git-push (auto-detect GitLab/GitHub + Keychain auth)"
