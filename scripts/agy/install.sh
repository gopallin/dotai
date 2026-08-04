#!/usr/bin/env bash
#
# install.sh — install dotai into Antigravity CLI (~/.gemini/)
#
# What this does:
#   1. Syncs global rules from dotai/GLOBAL_RULES.md to ~/.gemini/config/AGENTS.md
#   2. Copies commands to ~/.gemini/commands/
#   3. Copies skills to ~/.gemini/skills/
#   4. Copies hook scripts to ~/.gemini/hooks/
#   5. Copies rules to ~/.gemini/rules/
#   6. Registers AfterAgent hooks in ~/.gemini/settings.json

set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
}

DOTAI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GEMINI_DIR="$HOME/.gemini"

echo "Installing dotai → Antigravity CLI ($GEMINI_DIR)"
echo ""

# ── 1. Global Rules Sync ──────────────────────────────────────────────────────

mkdir -p "$GEMINI_DIR/config"
if [ -f "$DOTAI_DIR/GLOBAL_RULES.md" ]; then
  cp "$DOTAI_DIR/GLOBAL_RULES.md" "$GEMINI_DIR/config/AGENTS.md"
  echo "✅ Global Rules       → $GEMINI_DIR/config/AGENTS.md"
fi

# ── 2. Commands ───────────────────────────────────────────────────────────────

mkdir -p "$GEMINI_DIR/commands"
cp "$DOTAI_DIR/commands/precommit.md" "$GEMINI_DIR/commands/precommit.md"
# Replace hardcoded .claude path with .gemini for Antigravity CLI
sed -i '' 's|\.claude/commands/precommit\.sh|\.gemini/commands/precommit\.sh|g' "$GEMINI_DIR/commands/precommit.md" 2>/dev/null || \
sed -i 's|\.claude/commands/precommit\.sh|\.gemini/commands/precommit\.sh|g' "$GEMINI_DIR/commands/precommit.md"
echo "✅ /precommit command → $GEMINI_DIR/commands/precommit.md"

cp "$DOTAI_DIR/commands/precommit.sh" "$GEMINI_DIR/commands/precommit.sh"
chmod +x "$GEMINI_DIR/commands/precommit.sh"
echo "✅ /precommit script  → $GEMINI_DIR/commands/precommit.sh"

cp "$DOTAI_DIR/commands/plan.md" "$GEMINI_DIR/commands/plan.md"
echo "✅ /plan command      → $GEMINI_DIR/commands/plan.md"

cp "$DOTAI_DIR/commands/next-ticket.md" "$GEMINI_DIR/commands/next-ticket.md"
echo "✅ /next-ticket command → $GEMINI_DIR/commands/next-ticket.md"

cp "$DOTAI_DIR/commands/handoff.md" "$GEMINI_DIR/commands/handoff.md"
echo "✅ /handoff command   → $GEMINI_DIR/commands/handoff.md"

cp "$DOTAI_DIR/commands/prompt.md" "$GEMINI_DIR/commands/prompt.md"
echo "✅ /prompt command    → $GEMINI_DIR/commands/prompt.md"

cp "$DOTAI_DIR/commands/prompt-template.sh" "$GEMINI_DIR/commands/prompt-template.sh"
chmod +x "$GEMINI_DIR/commands/prompt-template.sh"
echo "✅ /prompt template   → $GEMINI_DIR/commands/prompt-template.sh"

# ── 3. Skills ────────────────────────────────────────────────────────────────

# agy's global customization root is ~/.gemini/config/ (see the built-in
# agy-customizations skill), and skills must be <root>/skills/<name>/SKILL.md.
# Earlier dotai versions wrote flat .md into ~/.gemini/skills/ — wrong on both
# counts, so nothing was ever discovered.
AGY_SKILLS="$GEMINI_DIR/config/skills"
mkdir -p "$AGY_SKILLS"
if [ -d "$DOTAI_DIR/skills" ]; then
  rm -rf "$GEMINI_DIR/skills"        # legacy location
  rm -f "$AGY_SKILLS"/*.md           # legacy flat layout
  for skill_dir in "$DOTAI_DIR/skills"/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    name=$(basename "$skill_dir")
    rm -rf "$AGY_SKILLS/$name"
    mkdir -p "$AGY_SKILLS/$name"
    cp -R "$skill_dir." "$AGY_SKILLS/$name/"
    echo "✅ /$name skill → $AGY_SKILLS/$name/SKILL.md"
  done
fi

# ── 2. Install hook scripts ───────────────────────────────────────────────────

mkdir -p "$GEMINI_DIR/hooks/shared"

# stop-guard
cp "$DOTAI_DIR/hooks/agy/stop-guard.sh" "$GEMINI_DIR/hooks/stop-guard.sh"
chmod +x "$GEMINI_DIR/hooks/stop-guard.sh"
echo "✅ stop-guard.sh     → $GEMINI_DIR/hooks/stop-guard.sh"

# grounding-guard (front-of-work gate)
cp "$DOTAI_DIR/hooks/agy/grounding-guard.sh" "$GEMINI_DIR/hooks/grounding-guard.sh"
chmod +x "$GEMINI_DIR/hooks/grounding-guard.sh"
echo "✅ grounding-guard.sh → $GEMINI_DIR/hooks/grounding-guard.sh"

# complexity-guard
cp "$DOTAI_DIR/hooks/shared/complexity-guard.sh" "$GEMINI_DIR/hooks/complexity-guard.sh"
chmod +x "$GEMINI_DIR/hooks/complexity-guard.sh"
echo "✅ complexity-guard.sh → $GEMINI_DIR/hooks/complexity-guard.sh"

# branch-guard (stored but not auto-triggered; agy CLI lacks PreCommand hook)
mkdir -p "$GEMINI_DIR/hooks/shared"
cp "$DOTAI_DIR/hooks/shared/branch-guard.sh" "$GEMINI_DIR/hooks/shared/branch-guard.sh"
chmod +x "$GEMINI_DIR/hooks/shared/branch-guard.sh"
echo "✅ shared/branch-guard.sh → $GEMINI_DIR/hooks/shared/branch-guard.sh (manual invoke)"

cp "$DOTAI_DIR/hooks/shared/glab-guard.sh" "$GEMINI_DIR/hooks/shared/glab-guard.sh"
chmod +x "$GEMINI_DIR/hooks/shared/glab-guard.sh"
echo "✅ shared/glab-guard.sh   → $GEMINI_DIR/hooks/shared/glab-guard.sh (manual invoke)"

# context-budget-guard (advisory: reminds to start fresh when session grows large)
cp "$DOTAI_DIR/hooks/agy/context-budget-guard.sh" "$GEMINI_DIR/hooks/context-budget-guard.sh"
chmod +x "$GEMINI_DIR/hooks/context-budget-guard.sh"
echo "✅ context-budget-guard.sh → $GEMINI_DIR/hooks/context-budget-guard.sh"

# read-dedup-guard (needs BeforeTool/read_file verification)
cp "$DOTAI_DIR/hooks/agy/read-dedup-guard.sh" "$GEMINI_DIR/hooks/read-dedup-guard.sh"
chmod +x "$GEMINI_DIR/hooks/read-dedup-guard.sh"
echo "✅ read-dedup-guard.sh → $GEMINI_DIR/hooks/read-dedup-guard.sh (needs verification)"

# ── 5. Install rules (framework-specific) ────────────────────────────────────

mkdir -p "$GEMINI_DIR/rules"
cp "$DOTAI_DIR/rules/laravel.md" "$GEMINI_DIR/rules/laravel.md"
cp "$DOTAI_DIR/rules/vue.md"     "$GEMINI_DIR/rules/vue.md"
cp "$DOTAI_DIR/rules/node.md"    "$GEMINI_DIR/rules/node.md"
echo "✅ Rules              → $GEMINI_DIR/rules/"

# ── 6. Status line ──────────────────────────────────────────────────────────

cp "$DOTAI_DIR/statusline/agy/statusline.sh" "$GEMINI_DIR/statusline.sh"
chmod +x "$GEMINI_DIR/statusline.sh"
echo "✅ statusline.sh      → $GEMINI_DIR/statusline.sh"

# ── 3. Register hooks in settings.json ────────────────────────────────────────

SETTINGS="$GEMINI_DIR/antigravity-cli/settings.json"

if [[ -f "$SETTINGS" ]] && [[ -s "$SETTINGS" ]]; then
  EXISTING=$(cat "$SETTINGS")
else
  EXISTING="{}"
fi

# timeout is milliseconds in agy CLI
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

  # BeforeTool hooks (fire before a tool runs; can deny).
  def before_hooks: [
    {
      "matcher": "write_to_file|replace_file_content|multi_replace_file_content|generate_image",
      "hooks": [
        {
          "name": "grounding-guard",
          "type": "command",
          "command": "bash \($home)/.gemini/hooks/grounding-guard.sh",
          "timeout": 10000,
          "description": "Auto-blocks the first code edit until /ground passes"
        }
      ]
    },
    {
      "matcher": "read_file",
      "hooks": [
        {
          "name": "read-dedup-guard",
          "type": "command",
          "command": "bash \($home)/.gemini/hooks/read-dedup-guard.sh",
          "timeout": 5000,
          "description": "Blocks full re-reads of files already in context"
        }
      ]
    },
    {
      "matcher": "run_command",
      "hooks": [
        {
          "name": "glab-guard",
          "type": "command",
          "command": "bash \($home)/.gemini/hooks/shared/glab-guard.sh",
          "timeout": 5000,
          "description": "Blocks glab CLI usage; directs to curl + $GITLAB_TOKEN"
        }
      ]
    }
  ];

  # Filter out old versions of these hooks before re-adding (idempotent re-runs)
  def filter_after: map(select((.hooks[0].name // "") as $n | $n != "stop-guard" and $n != "complexity-guard" and $n != "context-budget-guard"));
  def filter_before: map(select((.hooks[0].name // "") as $n | $n != "grounding-guard" and $n != "read-dedup-guard" and $n != "glab-guard"));

  .hooks.AfterAgent = (after_hooks + (.hooks.AfterAgent // [] | filter_after)) |
  .hooks.BeforeTool = (before_hooks + (.hooks.BeforeTool // [] | filter_before)) |
  # Register status line — dotai owns this key
  .statusLine = {
    "type": "command",
    "command": "bash \($home)/.gemini/statusline.sh",
    "padding": 0
  }
')

echo "$UPDATED" > "$SETTINGS"
echo "✅ Hooks registered   → $SETTINGS"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "dotai → Antigravity CLI (agy) installed."
echo ""
echo "Available:"
echo "  /plan            structured design planning"
echo "  /precommit       run lint + build + test"
echo "  /prompt          turn a rough idea into a structured, AI-ready task prompt"
echo "  stop-guard       auto-blocks stopping if quality checks were skipped"
echo "  grounding-guard  auto-blocks the first code edit until /ground passes"
echo "  complexity-guard alerts on manual exploration loops"
echo "  context-budget-guard advisory: reminds to start fresh when the session grows large"
echo "  read-dedup-guard blocks full re-reads (needs BeforeTool/read_file verification)"
echo "  branch-guard     (available for manual invoke; auto-trigger requires PreCommand hook support)"
echo "  glab-guard       (available for manual invoke; auto-trigger requires BeforeTool support for run_command)"
echo "  statusline       model · context-usage bar · /usage rate-limit bars"
echo "  rules/           AGENTS.md (global) and laravel.md · vue.md · node.md (path-filtered)"
echo "  skills/          ship · ground · git-push · preflight · parallel-design-agents"
echo ""
