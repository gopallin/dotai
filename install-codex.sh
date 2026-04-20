#!/usr/bin/env bash
#
# install-codex.sh — install dotai into Codex CLI (~/.codex/)
#
# What this does:
#   1. Syncs global rules from dotai/GLOBAL_RULES.md to ~/.codex/AGENTS.md
#   2. Copies stop-guard-codex.sh to ~/.codex/hooks/
#   3. Registers Stop hook in ~/.codex/hooks.json

set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
}

DOTAI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="$HOME/.codex"

echo "Installing dotai → Codex CLI ($CODEX_DIR)"
echo ""

# ── 1. Global Rules Sync ──────────────────────────────────────────────────────

mkdir -p "$CODEX_DIR"
if [ -f "$DOTAI_DIR/GLOBAL_RULES.md" ]; then
  cp "$DOTAI_DIR/GLOBAL_RULES.md" "$CODEX_DIR/AGENTS.md"
  echo "✅ Global Rules       → $CODEX_DIR/AGENTS.md"
fi

# ── 2. Install hook script ────────────────────────────────────────────────────

mkdir -p "$CODEX_DIR/hooks"
cp "$DOTAI_DIR/hooks/stop-guard-codex.sh" "$CODEX_DIR/hooks/stop-guard.sh"
chmod +x "$CODEX_DIR/hooks/stop-guard.sh"
echo "✅ stop-guard.sh     → $CODEX_DIR/hooks/stop-guard.sh"

# ── 3. Register Stop hook in hooks.json ──────────────────────────────────────

HOOKS_FILE="$CODEX_DIR/hooks.json"

if [[ -f "$HOOKS_FILE" ]] && [[ -s "$HOOKS_FILE" ]]; then
  EXISTING=$(cat "$HOOKS_FILE")
else
  EXISTING="{}"
fi

# timeout is seconds in Codex CLI
UPDATED=$(echo "$EXISTING" | jq --arg home "$HOME" '
  .hooks.Stop = ([
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.codex/hooks/stop-guard.sh",
          "timeout": 15
        }
      ]
    }
  ] + (.hooks.Stop // [] | map(select(
    (.hooks[0].command | test("stop-guard\\.sh$")) | not
  )))
)')

echo "$UPDATED" > "$HOOKS_FILE"
echo "✅ Stop hook         → $HOOKS_FILE"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "dotai → Codex CLI installed."
