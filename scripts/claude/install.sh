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

cp "$DOTAI_DIR/commands/precommit.sh" "$CLAUDE_DIR/commands/precommit.sh"
chmod +x "$CLAUDE_DIR/commands/precommit.sh"
echo "✅ /precommit script  → $CLAUDE_DIR/commands/precommit.sh"

cp "$DOTAI_DIR/commands/plan.md" "$CLAUDE_DIR/commands/plan.md"
echo "✅ /plan command      → $CLAUDE_DIR/commands/plan.md"

cp "$DOTAI_DIR/commands/next-ticket.md" "$CLAUDE_DIR/commands/next-ticket.md"
echo "✅ /next-ticket command → $CLAUDE_DIR/commands/next-ticket.md"

cp "$DOTAI_DIR/commands/handoff.md" "$CLAUDE_DIR/commands/handoff.md"
echo "✅ /handoff command   → $CLAUDE_DIR/commands/handoff.md"

cp "$DOTAI_DIR/commands/prompt.md" "$CLAUDE_DIR/commands/prompt.md"
echo "✅ /prompt command    → $CLAUDE_DIR/commands/prompt.md"

cp "$DOTAI_DIR/commands/prompt-template.sh" "$CLAUDE_DIR/commands/prompt-template.sh"
chmod +x "$CLAUDE_DIR/commands/prompt-template.sh"
echo "✅ /prompt template   → $CLAUDE_DIR/commands/prompt-template.sh"

# ── 2b. Skills ────────────────────────────────────────────────────────────────

# Skill discovery requires skills/<name>/SKILL.md — a flat skills/<name>.md is
# silently ignored, which is how ship/ground/git-push went missing for a while.
mkdir -p "$CLAUDE_DIR/skills"
if [ -d "$DOTAI_DIR/skills" ]; then
  rm -f "$CLAUDE_DIR/skills"/*.md   # drop the never-discovered flat layout
  for skill_dir in "$DOTAI_DIR/skills"/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    name=$(basename "$skill_dir")
    rm -rf "$CLAUDE_DIR/skills/$name"
    mkdir -p "$CLAUDE_DIR/skills/$name"
    cp -R "$skill_dir." "$CLAUDE_DIR/skills/$name/"
    INSTALLED_SKILLS="${INSTALLED_SKILLS:+$INSTALLED_SKILLS · }$name"
    echo "✅ /$name skill → $CLAUDE_DIR/skills/$name/SKILL.md"
  done
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

# agy hooks
mkdir -p "$CLAUDE_DIR/hooks/agy"
cp "$DOTAI_DIR/hooks/agy/stop-guard.sh" "$CLAUDE_DIR/hooks/agy/stop-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/agy/stop-guard.sh"
echo "✅ agy/stop-guard.sh     → $CLAUDE_DIR/hooks/agy/stop-guard.sh"

# grounding-guard (front-of-work gate; Claude blocks, codex/gemini advisory)
cp "$DOTAI_DIR/hooks/claude/grounding-guard.sh" "$CLAUDE_DIR/hooks/claude/grounding-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/claude/grounding-guard.sh"
echo "✅ claude/grounding-guard.sh → $CLAUDE_DIR/hooks/claude/grounding-guard.sh"

cp "$DOTAI_DIR/hooks/codex/grounding-guard.sh" "$CLAUDE_DIR/hooks/codex/grounding-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/codex/grounding-guard.sh"
echo "✅ codex/grounding-guard.sh  → $CLAUDE_DIR/hooks/codex/grounding-guard.sh"

cp "$DOTAI_DIR/hooks/agy/grounding-guard.sh" "$CLAUDE_DIR/hooks/agy/grounding-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/agy/grounding-guard.sh"
echo "✅ agy/grounding-guard.sh → $CLAUDE_DIR/hooks/agy/grounding-guard.sh"

# context-budget-guard (advisory: reminds to /clear when the session grows large)
cp "$DOTAI_DIR/hooks/claude/context-budget-guard.sh" "$CLAUDE_DIR/hooks/claude/context-budget-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/claude/context-budget-guard.sh"
echo "✅ claude/context-budget-guard.sh → $CLAUDE_DIR/hooks/claude/context-budget-guard.sh"

# handoff-reminder (SessionStart on /clear: offer resume+handoff or reconstruction)
cp "$DOTAI_DIR/hooks/claude/handoff-reminder.sh" "$CLAUDE_DIR/hooks/claude/handoff-reminder.sh"
chmod +x "$CLAUDE_DIR/hooks/claude/handoff-reminder.sh"
echo "✅ claude/handoff-reminder.sh → $CLAUDE_DIR/hooks/claude/handoff-reminder.sh"

# stack-rules (SessionStart: emits only the detected stack's rules file)
cp "$DOTAI_DIR/hooks/claude/stack-rules.sh" "$CLAUDE_DIR/hooks/claude/stack-rules.sh"
chmod +x "$CLAUDE_DIR/hooks/claude/stack-rules.sh"
echo "✅ claude/stack-rules.sh → $CLAUDE_DIR/hooks/claude/stack-rules.sh"

# Shared hooks
mkdir -p "$CLAUDE_DIR/hooks/shared"
cp "$DOTAI_DIR/hooks/shared/branch-guard.sh" "$CLAUDE_DIR/hooks/shared/branch-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/shared/branch-guard.sh"
echo "✅ shared/branch-guard.sh     → $CLAUDE_DIR/hooks/shared/branch-guard.sh"

cp "$DOTAI_DIR/hooks/shared/glab-guard.sh" "$CLAUDE_DIR/hooks/shared/glab-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/shared/glab-guard.sh"
echo "✅ shared/glab-guard.sh       → $CLAUDE_DIR/hooks/shared/glab-guard.sh"

# Remove hooks retired by the prompt-layer ablation (docs/ABLATION.md). Unregistering
# them in settings.json is not enough — the scripts stay on disk, and a leftover file
# is how a deleted guard quietly comes back (someone re-adds one settings.json line
# and it works again, with none of the reasoning that removed it).
for gone in claude/read-dedup-guard shared/complexity-guard; do
  if [[ -f "$CLAUDE_DIR/hooks/$gone.sh" ]]; then
    rm -f "$CLAUDE_DIR/hooks/$gone.sh"
    echo "🧹 removed retired $CLAUDE_DIR/hooks/$gone.sh"
  fi
done

# ── 3b. Status line (Claude Code only) ────────────────────────────────────────

cp "$DOTAI_DIR/statusline/claude/statusline.sh" "$CLAUDE_DIR/statusline.sh"
chmod +x "$CLAUDE_DIR/statusline.sh"
echo "✅ statusline.sh      → $CLAUDE_DIR/statusline.sh"

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
  # Register PreToolUse hooks
  .hooks.PreToolUse = ([
    {
      # Edit|Write|MultiEdit belong here, not just Bash: branch-guard also gates
      # non-doc file edits on master/main, and with a Bash-only matcher that half
      # of the guard was never reachable.
      "matcher": "Bash|Edit|Write|MultiEdit",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.claude/hooks/shared/branch-guard.sh",
          "timeout": 5
        }
      ]
    },
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.claude/hooks/shared/glab-guard.sh",
          "timeout": 5
        }
      ]
    },
    {
      "matcher": "Edit|Write|MultiEdit",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.claude/hooks/claude/grounding-guard.sh",
          "timeout": 10
        }
      ]
    },
    {
      "matcher": "Bash|Edit|Write|MultiEdit|Read|Grep|Glob",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.claude/hooks/claude/context-budget-guard.sh",
          "timeout": 5
        }
      ]
    }
  ] + (.hooks.PreToolUse // [] | map(select(
    # This regex is a CLEANUP list, not a registration list — it must keep naming
    # `complexity` and `read-dedup` even though neither is installed any more, so
    # that a re-install prunes their stale entries from an older settings.json.
    # Removing a name here orphans its registration forever. See docs/ABLATION.md.
    (.hooks[0].command | test("shared/(complexity|branch|glab)-guard\\.sh$|claude/(grounding|read-dedup|context-budget)-guard\\.sh$")) | not
  )))) |
  # Register SessionStart hook (handoff-reminder fires only after /clear)
  .hooks.SessionStart = ([
    {
      "matcher": "clear",
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.claude/hooks/claude/handoff-reminder.sh",
          "timeout": 10
        }
      ]
    }
    ,
    {
      # No matcher: stack rules apply to every session start, not just /clear.
      "hooks": [
        {
          "type": "command",
          "command": "bash \($home)/.claude/hooks/claude/stack-rules.sh",
          "timeout": 5
        }
      ]
    }
  ] + (.hooks.SessionStart // [] | map(select(
    (.hooks[0].command | test("claude/(handoff-reminder|stack-rules)\\.sh$")) | not
  )))) |
  # Register status line (Claude Code only) — dotai owns this key
  .statusLine = {
    "type": "command",
    "command": "bash \($home)/.claude/statusline.sh",
    "padding": 0
  }
')

echo "$UPDATED" > "$SETTINGS"
echo "✅ Hooks registered   → $SETTINGS"

# ── 5. Install stack rules (conditionally loaded, NOT global) ─────────────────
#
# These go to dotai-rules/, NOT rules/. Claude Code auto-loads every file under
# ~/.claude/rules/ with no path filtering, so the previous layout put all three
# stacks into every session of every project. stack-rules.sh (SessionStart) now
# detects the project and emits only the matching file.

mkdir -p "$CLAUDE_DIR/dotai-rules"
cp "$DOTAI_DIR/rules/laravel.md" "$CLAUDE_DIR/dotai-rules/laravel.md"
cp "$DOTAI_DIR/rules/vue.md"     "$CLAUDE_DIR/dotai-rules/vue.md"
cp "$DOTAI_DIR/rules/node.md"    "$CLAUDE_DIR/dotai-rules/node.md"
echo "✅ Stack rules        → $CLAUDE_DIR/dotai-rules/ (loaded per-project by stack-rules.sh)"

# Clean up the previous always-loaded copies. Without this the old files keep
# being auto-loaded forever and the ablation buys nothing — same reason the skills
# installer removes the legacy flat skills/<name>.md files.
for stale in laravel vue node; do
  if [[ -f "$CLAUDE_DIR/rules/$stale.md" ]]; then
    rm -f "$CLAUDE_DIR/rules/$stale.md"
    echo "🧹 removed always-loaded $CLAUDE_DIR/rules/$stale.md"
  fi
done
rmdir "$CLAUDE_DIR/rules" 2>/dev/null || true

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "dotai installed. Restart Claude Code to activate the hooks."
echo ""
echo "Available after restart:"
echo "  /plan            structured design planning (save to plan.md, optionally decompose into tickets)"
echo "  /next-ticket     pick up the next unblocked ticket (one context-sized slice per session)"
echo "  /handoff         save a compact resume file before /clear (local-only, never committed)"
echo "  /precommit       run lint + build + test"
echo "  /prompt          turn a rough idea into a structured, AI-ready task prompt"
echo "  /ground          pre-implementation grounding check (read patterns + verify data)"
echo "  stop-guard       auto-blocks stopping if /precommit was skipped or failed"
echo "  grounding-guard  auto-blocks the first code edit until /ground passes"
echo "  context-budget-guard reminds you to /clear when the session grows large"
echo "  handoff-reminder after /clear: offers /resume+/handoff or transcript reconstruction"
echo "  branch-guard     blocks WRITE commands and non-doc edits on master/main (reads pass)"
echo "  glab-guard       blocks glab CLI, directs to curl + \$GITLAB_TOKEN + jq"
echo "  stack-rules      loads only the detected stack's rules (laravel|vue|node)"
echo "  statusline       model · context-usage bar · /usage rate-limit bars"
# Derived from what was actually installed — a hardcoded list silently goes
# stale the moment a skill is added (it already had, omitting reviewer-rules).
echo "  skills/          ${INSTALLED_SKILLS:-(none)}"
