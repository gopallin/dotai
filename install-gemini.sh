#!/usr/bin/env bash
#
# install-gemini.sh — install dotai into Gemini CLI (~/.gemini/)
#
# What this does:
#   1. Copies stop-guard-gemini.sh to ~/.gemini/hooks/
#   2. Registers AfterAgent hook in ~/.gemini/settings.json

set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
}

DOTAI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEMINI_DIR="$HOME/.gemini"

echo "Installing dotai → Gemini CLI ($GEMINI_DIR)"
echo ""

# ── 1. Install hook script ────────────────────────────────────────────────────

mkdir -p "$GEMINI_DIR/hooks"
cp "$DOTAI_DIR/hooks/stop-guard-gemini.sh" "$GEMINI_DIR/hooks/stop-guard.sh"
chmod +x "$GEMINI_DIR/hooks/stop-guard.sh"
echo "✅ stop-guard.sh     → $GEMINI_DIR/hooks/stop-guard.sh"

# ── 2. Register AfterAgent hook in settings.json ──────────────────────────────

SETTINGS="$GEMINI_DIR/settings.json"

if [[ -f "$SETTINGS" ]] && [[ -s "$SETTINGS" ]]; then
  EXISTING=$(cat "$SETTINGS")
else
  EXISTING="{}"
fi

# timeout is milliseconds in Gemini CLI
UPDATED=$(echo "$EXISTING" | jq --arg home "$HOME" '
  .hooks.AfterAgent = ([
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
    }
  ] + (.hooks.AfterAgent // [] | map(select(
    (.hooks[0].name // "") != "stop-guard"
  )))
)')

echo "$UPDATED" > "$SETTINGS"
echo "✅ AfterAgent hook   → $SETTINGS"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "dotai → Gemini CLI installed."
echo ""
echo "Note: Gemini uses different file-editing tool names."
echo "If the guard does not trigger on code changes, check tool names in:"
echo "  $DOTAI_DIR/hooks/stop-guard-gemini.sh"
