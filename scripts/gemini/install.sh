#!/usr/bin/env bash
#
# install-gemini.sh — install dotai into Gemini CLI (~/.gemini/)
#
# What this does:
#   1. Syncs global rules from dotai/GLOBAL_RULES.md to ~/.gemini/GEMINI.md
#   2. Copies hook scripts to ~/.gemini/hooks/
#   3. Registers AfterAgent hooks in ~/.gemini/settings.json

set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
}

DOTAI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GEMINI_DIR="$HOME/.gemini"

echo "Installing dotai → Gemini CLI ($GEMINI_DIR)"
echo ""

# ── 1. Global Rules Sync ──────────────────────────────────────────────────────

mkdir -p "$GEMINI_DIR"
if [ -f "$DOTAI_DIR/GLOBAL_RULES.md" ]; then
  cp "$DOTAI_DIR/GLOBAL_RULES.md" "$GEMINI_DIR/GEMINI.md"
  echo "✅ Global Rules       → $GEMINI_DIR/GEMINI.md"
fi

# ── 2. Install hook scripts ───────────────────────────────────────────────────

mkdir -p "$GEMINI_DIR/hooks/shared"

# stop-guard
cp "$DOTAI_DIR/hooks/gemini/stop-guard.sh" "$GEMINI_DIR/hooks/stop-guard.sh"
chmod +x "$GEMINI_DIR/hooks/stop-guard.sh"
echo "✅ stop-guard.sh     → $GEMINI_DIR/hooks/stop-guard.sh"

# complexity-guard
cp "$DOTAI_DIR/hooks/shared/complexity-guard.sh" "$GEMINI_DIR/hooks/complexity-guard.sh"
chmod +x "$GEMINI_DIR/hooks/complexity-guard.sh"
echo "✅ complexity-guard.sh → $GEMINI_DIR/hooks/complexity-guard.sh"

# branch-guard (stored but not auto-triggered; Gemini CLI lacks PreCommand hook)
mkdir -p "$GEMINI_DIR/hooks/shared"
cp "$DOTAI_DIR/hooks/shared/branch-guard.sh" "$GEMINI_DIR/hooks/shared/branch-guard.sh"
chmod +x "$GEMINI_DIR/hooks/shared/branch-guard.sh"
echo "✅ shared/branch-guard.sh → $GEMINI_DIR/hooks/shared/branch-guard.sh (manual invoke)"

# ── 3. Register hooks in settings.json ────────────────────────────────────────

SETTINGS="$GEMINI_DIR/settings.json"

if [[ -f "$SETTINGS" ]] && [[ -s "$SETTINGS" ]]; then
  EXISTING=$(cat "$SETTINGS")
else
  EXISTING="{}"
fi

# timeout is milliseconds in Gemini CLI
UPDATED=$(echo "$EXISTING" | jq --arg home "$HOME" '
  # Define the new hooks
  def new_hooks: [
    {
      "matcher": "*",
      "hooks": [
        {
          "name": "stop-guard",
          "type": "command",
          "command": "bash \($home)/.gemini/hooks/stop-guard.sh",
          "timeout": 15000,
          "description": "Enforce precommit quality checks before finishing"
        }
      ]
    },
    {
      "matcher": "grep_search|read_file|glob|list_directory",
      "hooks": [
        {
          "name": "complexity-guard",
          "type": "command",
          "command": "bash \($home)/.gemini/hooks/complexity-guard.sh $TOOL_NAME",
          "timeout": 5000,
          "description": "Alerts on manual exploration loops"
        }
      ]
    }
  ];

  # Filter out old versions of these hooks
  def filter_hooks: map(select((.hooks[0].name // "") != "stop-guard" and (.hooks[0].name // "") != "complexity-guard"));

  .hooks.AfterAgent = (new_hooks + (.hooks.AfterAgent // [] | filter_hooks))
')

echo "$UPDATED" > "$SETTINGS"
echo "✅ Hooks registered   → $SETTINGS"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "dotai → Gemini CLI installed."
echo ""
echo "Available:"
echo "  stop-guard       auto-blocks stopping if quality checks were skipped"
echo "  complexity-guard alerts on manual exploration loops"
echo "  branch-guard     (available for manual invoke; auto-trigger requires PreCommand hook support)"
echo "  rules/           GEMINI.md with global AI CLI rules"
echo ""
echo "Note: /plan command is Claude Code-only. Gemini CLI uses structured prompts instead."
echo ""
