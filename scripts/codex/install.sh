#!/usr/bin/env bash
#
# install-codex.sh — install dotai into Codex CLI (~/.codex/)
#
# What this does:
#   1. Syncs global rules from dotai/GLOBAL_RULES.md to ~/.codex/AGENTS.md
#   2. Copies Codex hook scripts to ~/.codex/hooks/
#   3. Registers lifecycle hooks in ~/.codex/hooks.json

set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
}

DOTAI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="$HOME/.codex"

echo "Installing dotai → Codex CLI ($CODEX_DIR)"
echo ""

# ── 1. Global Rules Sync ──────────────────────────────────────────────────────

mkdir -p "$CODEX_DIR"
if [ -f "$DOTAI_DIR/GLOBAL_RULES.md" ]; then
  cp "$DOTAI_DIR/GLOBAL_RULES.md" "$CODEX_DIR/AGENTS.md"
  echo "✅ Global Rules       → $CODEX_DIR/AGENTS.md"
fi

# ── 2. TUI status line ───────────────────────────────────────────────────────

CONFIG_FILE="$CODEX_DIR/config.toml"
STATUS_LINE='status_line = ["model-with-reasoning", "context-used", "used-tokens", "total-input-tokens", "total-output-tokens", "five-hour-limit", "weekly-limit", "git-branch"]'
touch "$CONFIG_FILE"
CONFIG_TMP=$(mktemp "$CODEX_DIR/config.toml.XXXXXX")

awk -v status_line="$STATUS_LINE" '
  /^\[tui\][[:space:]]*$/ {
    tui_seen = 1
    in_tui = 1
    print
    next
  }
  in_tui && /^\[/ {
    if (!status_line_written) print status_line
    status_line_written = 1
    in_tui = 0
    print
    next
  }
  in_tui && /^[[:space:]]*status_line[[:space:]]*=/ {
    if (!status_line_written) print status_line
    status_line_written = 1
    next
  }
  { print }
  END {
    if (in_tui && !status_line_written) print status_line
    if (!tui_seen && !in_tui) {
      print ""
      print "[tui]"
      print status_line
    }
  }
' "$CONFIG_FILE" > "$CONFIG_TMP"
mv "$CONFIG_TMP" "$CONFIG_FILE"
echo "✅ TUI status line    → $CONFIG_FILE"

# ── 3. Commands (Codex custom prompts: ~/.codex/prompts/*.md → /name) ─────────

mkdir -p "$CODEX_DIR/prompts"
for cmd in precommit plan next-ticket handoff prompt; do
  cp "$DOTAI_DIR/commands/$cmd.md" "$CODEX_DIR/prompts/$cmd.md"
done

# Replace hardcoded .claude path with .codex for Codex CLI
sed -i '' 's|\.claude/commands/precommit\.sh|\.codex/prompts/precommit\.sh|g' "$CODEX_DIR/prompts/precommit.md" 2>/dev/null || \
sed -i 's|\.claude/commands/precommit\.sh|\.codex/prompts/precommit\.sh|g' "$CODEX_DIR/prompts/precommit.md"

# Copy helper scripts
cp "$DOTAI_DIR/commands/precommit.sh" "$CODEX_DIR/prompts/precommit.sh"
chmod +x "$CODEX_DIR/prompts/precommit.sh"
cp "$DOTAI_DIR/commands/prompt-template.sh" "$CODEX_DIR/prompts/prompt-template.sh"
chmod +x "$CODEX_DIR/prompts/prompt-template.sh"

for cmd in precommit plan next-ticket handoff prompt; do
  echo "✅ /$cmd prompt → $CODEX_DIR/prompts/$cmd.md"
done
echo "✅ /precommit script  → $CODEX_DIR/prompts/precommit.sh"
echo "✅ /prompt template   → $CODEX_DIR/prompts/prompt-template.sh"

# ── 3b. Skills (Codex discovers ~/.codex/skills/<name>/SKILL.md) ──────────────

# Codex keeps its own skills under skills/.system/ and reads user skills from the
# same root, so dotai skills install alongside without touching .system.
CODEX_SKILLS="$CODEX_DIR/skills"
mkdir -p "$CODEX_SKILLS"
if [ -d "$DOTAI_DIR/skills" ]; then
  rm -f "$CODEX_SKILLS"/*.md
  for skill_dir in "$DOTAI_DIR/skills"/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    name=$(basename "$skill_dir")
    rm -rf "$CODEX_SKILLS/$name"
    mkdir -p "$CODEX_SKILLS/$name"
    cp -R "$skill_dir." "$CODEX_SKILLS/$name/"
    INSTALLED_SKILLS="${INSTALLED_SKILLS:+$INSTALLED_SKILLS · }$name"
    echo "✅ /$name skill → $CODEX_SKILLS/$name/SKILL.md"
  done
fi

# ── 4. Install hook scripts ───────────────────────────────────────────────────

mkdir -p "$CODEX_DIR/hooks/shared"
cp "$DOTAI_DIR/hooks/codex/stop-guard.sh" "$CODEX_DIR/hooks/stop-guard.sh"
chmod +x "$CODEX_DIR/hooks/stop-guard.sh"
echo "✅ codex/stop-guard.sh     → $CODEX_DIR/hooks/stop-guard.sh"

cp "$DOTAI_DIR/hooks/shared/branch-guard.sh" "$CODEX_DIR/hooks/shared/branch-guard.sh"
chmod +x "$CODEX_DIR/hooks/shared/branch-guard.sh"
echo "✅ shared/branch-guard.sh  → $CODEX_DIR/hooks/shared/branch-guard.sh"

cp "$DOTAI_DIR/hooks/shared/glab-guard.sh" "$CODEX_DIR/hooks/shared/glab-guard.sh"
chmod +x "$CODEX_DIR/hooks/shared/glab-guard.sh"
echo "✅ shared/glab-guard.sh    → $CODEX_DIR/hooks/shared/glab-guard.sh"

cp "$DOTAI_DIR/hooks/shared/secret-guard.sh" "$CODEX_DIR/hooks/shared/secret-guard.sh"
chmod +x "$CODEX_DIR/hooks/shared/secret-guard.sh"
echo "✅ shared/secret-guard.sh  → $CODEX_DIR/hooks/shared/secret-guard.sh"

# grounding-guard (blocks the first code edit until /ground passes)
cp "$DOTAI_DIR/hooks/codex/grounding-guard.sh" "$CODEX_DIR/hooks/grounding-guard.sh"
chmod +x "$CODEX_DIR/hooks/grounding-guard.sh"
echo "✅ grounding-guard.sh      → $CODEX_DIR/hooks/grounding-guard.sh"

# context-budget-guard (advisory: reminds to start fresh when session grows large)
cp "$DOTAI_DIR/hooks/codex/context-budget-guard.sh" "$CODEX_DIR/hooks/context-budget-guard.sh"
chmod +x "$CODEX_DIR/hooks/context-budget-guard.sh"
echo "✅ context-budget-guard.sh → $CODEX_DIR/hooks/context-budget-guard.sh"

# handoff-reminder (SessionStart on /clear)
cp "$DOTAI_DIR/hooks/codex/handoff-reminder.sh" "$CODEX_DIR/hooks/handoff-reminder.sh"
chmod +x "$CODEX_DIR/hooks/handoff-reminder.sh"
echo "✅ handoff-reminder.sh     → $CODEX_DIR/hooks/handoff-reminder.sh"

# ── 5. Register hooks in hooks.json ──────────────────────────────────────────

HOOKS_FILE="$CODEX_DIR/hooks.json"

if [[ -f "$HOOKS_FILE" ]] && [[ -s "$HOOKS_FILE" ]]; then
  EXISTING=$(cat "$HOOKS_FILE")
else
  EXISTING="{}"
fi

# timeout is seconds in Codex CLI
UPDATED=$(echo "$EXISTING" | jq --arg home "$HOME" '
  # Register Stop hook
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
  )))) |
  # Register PreToolUse hook for branch-guard
  .hooks.PreToolUse = ([
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.codex/hooks/shared/branch-guard.sh",
          "timeout": 5
        }
      ]
    },
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.codex/hooks/context-budget-guard.sh",
          "timeout": 5
        }
      ]
    },
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.codex/hooks/shared/glab-guard.sh",
          "timeout": 5
        }
      ]
    },
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.codex/hooks/shared/secret-guard.sh",
          "timeout": 5
        }
      ]
    },
    {
      "matcher": "apply_patch",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.codex/hooks/grounding-guard.sh",
          "timeout": 10
        }
      ]
    }
  ] + (.hooks.PreToolUse // [] | map(select(
    (.hooks[0].command | test("branch-guard\\.sh$|context-budget-guard\\.sh$|glab-guard\\.sh$|secret-guard\\.sh$|grounding-guard\\.sh$")) | not
  )))) |
  # Register SessionStart hook for handoff reminders after /clear
  .hooks.SessionStart = ([
    {
      "matcher": "clear",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.codex/hooks/handoff-reminder.sh",
          "timeout": 10
        }
      ]
    }
  ] + (.hooks.SessionStart // [] | map(select(
    (.hooks[0].command | test("handoff-reminder\\.sh$")) | not
  ))))
')

echo "$UPDATED" > "$HOOKS_FILE"
echo "✅ Hooks registered  → $HOOKS_FILE"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "dotai → Codex CLI installed."
echo ""
echo "Available after restart:"
echo "  /plan            structured design planning (save to plan.md, optionally decompose into tickets)"
echo "  /next-ticket     pick up the next unblocked ticket (one context-sized slice per session)"
echo "  /handoff         save a compact resume file before starting fresh (local-only, never committed)"
echo "  /precommit       run lint + build + test"
echo "  /prompt          turn a rough idea into a structured, AI-ready task prompt"
# Derived from what was actually installed — a hardcoded list silently goes
# stale the moment a skill is added (it already had, omitting reviewer-rules).
echo "  skills/          ${INSTALLED_SKILLS:-(none)}"
echo "  statusline       model · context · token usage · rate limits · git branch"
echo "  stop-guard       auto-blocks stopping if verifications incomplete"
echo "  branch-guard     prevents accidental pushes to master/main"
echo "  glab-guard       blocks glab CLI, directs to curl + \$GITLAB_TOKEN + jq"
echo "  secret-guard     blocks 'security dump-keychain' (unbounded secret dump)"
echo "  grounding-guard  auto-blocks the first code edit until /ground passes"
echo "  context-budget-guard advisory: reminds to start fresh when the session grows large"
echo "  handoff-reminder after /clear: offers /resume + /handoff or transcript reconstruction"

