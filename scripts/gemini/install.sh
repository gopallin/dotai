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

# context-budget-guard (advisory: reminds to start fresh when session grows large)
cp "$DOTAI_DIR/hooks/gemini/context-budget-guard.sh" "$GEMINI_DIR/hooks/context-budget-guard.sh"
chmod +x "$GEMINI_DIR/hooks/context-budget-guard.sh"
echo "✅ context-budget-guard.sh → $GEMINI_DIR/hooks/context-budget-guard.sh"

# read-dedup-guard (EXPERIMENTAL: blocks full re-reads via BeforeTool/read_file —
# verify that BeforeTool fires for read_file on your installed Gemini version)
cp "$DOTAI_DIR/hooks/gemini/read-dedup-guard.sh" "$GEMINI_DIR/hooks/read-dedup-guard.sh"
chmod +x "$GEMINI_DIR/hooks/read-dedup-guard.sh"
echo "✅ read-dedup-guard.sh → $GEMINI_DIR/hooks/read-dedup-guard.sh (experimental)"

# ── 3. Register hooks in settings.json ────────────────────────────────────────

SETTINGS="$GEMINI_DIR/settings.json"

if [[ -f "$SETTINGS" ]] && [[ -s "$SETTINGS" ]]; then
  EXISTING=$(cat "$SETTINGS")
else
  EXISTING="{}"
fi

# timeout is milliseconds in Gemini CLI
UPDATED=$(echo "$EXISTING" | jq --arg home "$HOME" '
  # AfterAgent hooks (fire after each agent turn)
  def after_hooks: [
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
    },
    {
      "matcher": "*",
      "hooks": [
        {
          "name": "context-budget-guard",
          "type": "command",
          "command": "bash \($home)/.gemini/hooks/context-budget-guard.sh",
          "timeout": 5000,
          "description": "Advisory: reminds to start fresh when the session grows large"
        }
      ]
    }
  ];

  # BeforeTool hooks (fire before a tool runs; can deny). EXPERIMENTAL: verify
  # that BeforeTool fires for read_file on the installed Gemini version.
  def before_hooks: [
    {
      "matcher": "read_file",
      "hooks": [
        {
          "name": "read-dedup-guard",
          "type": "command",
          "command": "bash \($home)/.gemini/hooks/read-dedup-guard.sh",
          "timeout": 5000,
          "description": "EXPERIMENTAL: blocks full re-reads of files already in context"
        }
      ]
    }
  ];

  # Filter out old versions of these hooks before re-adding (idempotent re-runs)
  def filter_after: map(select((.hooks[0].name // "") as $n | $n != "stop-guard" and $n != "complexity-guard" and $n != "context-budget-guard"));
  def filter_before: map(select((.hooks[0].name // "") != "read-dedup-guard"));

  .hooks.AfterAgent = (after_hooks + (.hooks.AfterAgent // [] | filter_after)) |
  .hooks.BeforeTool = (before_hooks + (.hooks.BeforeTool // [] | filter_before))
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
echo "  context-budget-guard advisory: reminds to start fresh when the session grows large"
echo "  read-dedup-guard EXPERIMENTAL: blocks full re-reads (verify BeforeTool fires for read_file)"
echo "  branch-guard     (available for manual invoke; auto-trigger requires PreCommand hook support)"
echo "  rules/           GEMINI.md with global AI CLI rules"
echo ""
echo "Note: /plan command is Claude Code-only. Gemini CLI uses structured prompts instead."
echo ""
