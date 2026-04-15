#!/usr/bin/env bash
#
# install.sh — install dotai into ~/.claude/
#
# What this does:
#   1. Copies /precommit command to ~/.claude/commands/
#   2. Copies stop-guard.sh to ~/.claude/hooks/
#   3. Registers the Stop hook in ~/.claude/settings.json

set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
}

DOTAI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Installing dotai from $DOTAI_DIR → $CLAUDE_DIR"
echo ""

# ── 1. /precommit command ─────────────────────────────────────────────────────

mkdir -p "$CLAUDE_DIR/commands"
cp "$DOTAI_DIR/commands/precommit.md" "$CLAUDE_DIR/commands/precommit.md"
echo "✅ /precommit command → $CLAUDE_DIR/commands/precommit.md"

# ── 2. stop-guard.sh hook script ─────────────────────────────────────────────

mkdir -p "$CLAUDE_DIR/hooks"
cp "$DOTAI_DIR/hooks/stop-guard.sh" "$CLAUDE_DIR/hooks/stop-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/stop-guard.sh"
echo "✅ stop-guard.sh     → $CLAUDE_DIR/hooks/stop-guard.sh"

# ── 3. Register Stop hook in settings.json ────────────────────────────────────

SETTINGS="$CLAUDE_DIR/settings.json"

# Read existing settings (default to empty object if file is missing or empty)
if [[ -f "$SETTINGS" ]] && [[ -s "$SETTINGS" ]]; then
  EXISTING=$(cat "$SETTINGS")
else
  EXISTING="{}"
fi

# Merge the Stop hook — preserves all existing settings
UPDATED=$(echo "$EXISTING" | jq '
  .hooks.Stop = ([
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash ~/.claude/hooks/stop-guard.sh",
          "timeout": 15
        }
      ]
    }
  ] + (.hooks.Stop // [] | map(select(
    .hooks[0].command != "bash ~/.claude/hooks/stop-guard.sh"
  )))
)')

echo "$UPDATED" > "$SETTINGS"
echo "✅ Stop hook          → $SETTINGS"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "dotai installed. Restart Claude Code to activate the Stop hook."
echo ""
echo "Available after restart:"
echo "  /precommit   run lint + build + test"
echo "  stop-guard   auto-blocks stopping if /precommit was skipped or failed"
