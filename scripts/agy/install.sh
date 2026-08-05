#!/usr/bin/env bash
#
# install.sh — install dotai into Antigravity CLI (~/.gemini/)
#
# What this does:
#   1. Syncs global rules from dotai/GLOBAL_RULES.md to ~/.gemini/config/AGENTS.md
#   2. Installs commands AS SKILLS in ~/.gemini/config/skills/<name>/SKILL.md
#      (agy has no commands type — slash commands come from skills)
#   3. Installs skills to ~/.gemini/config/skills/<name>/SKILL.md
#   4. Copies hook scripts to ~/.gemini/hooks/
#   5. Copies rules to ~/.gemini/rules/
#   6. Registers hooks in ~/.gemini/config/hooks.json (NOT settings.json)
#
# agy's global customization root is ~/.gemini/config/. Anything dotai writes
# directly under ~/.gemini/ (except hook scripts, which are only referenced by
# absolute path) is never discovered. See CLAUDE.md §agy Hook Contract.

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

# ── 2. Commands — installed as SKILLS ────────────────────────────────────────
#
# agy has no "commands" customization type; its slash commands are resolved from
# skills (verified: a skill named dotai-probe was invocable as /dotai-probe).
# dotai used to drop these in ~/.gemini/commands/, which agy never reads, so
# /precommit, /plan, /handoff, /prompt and /next-ticket did not exist there.

AGY_SKILLS="$GEMINI_DIR/config/skills"
mkdir -p "$AGY_SKILLS"
rm -rf "$GEMINI_DIR/commands"   # legacy location agy never read

for cmd in precommit plan next-ticket handoff prompt; do
  dest="$AGY_SKILLS/$cmd"
  rm -rf "$dest"
  mkdir -p "$dest"
  # agy requires BOTH name and description in frontmatter; some commands only
  # carry description (they were written for Claude, which infers the name from
  # the filename), so inject `name:` when it is missing.
  if grep -q '^name:' "$DOTAI_DIR/commands/$cmd.md"; then
    cp "$DOTAI_DIR/commands/$cmd.md" "$dest/SKILL.md"
  else
    awk -v n="$cmd" 'NR==1 && $0=="---" { print; print "name: " n; next } { print }' \
      "$DOTAI_DIR/commands/$cmd.md" > "$dest/SKILL.md"
  fi
  echo "✅ /$cmd command   → $dest/SKILL.md"
done

# Helper scripts live beside the skill that calls them; rewrite the documented
# path so it points at the skill dir instead of the Claude commands dir.
cp "$DOTAI_DIR/commands/precommit.sh" "$AGY_SKILLS/precommit/precommit.sh"
chmod +x "$AGY_SKILLS/precommit/precommit.sh"
sed -i '' "s|\.claude/commands/precommit\.sh|.gemini/config/skills/precommit/precommit.sh|g" "$AGY_SKILLS/precommit/SKILL.md" 2>/dev/null || \
sed -i "s|\.claude/commands/precommit\.sh|.gemini/config/skills/precommit/precommit.sh|g" "$AGY_SKILLS/precommit/SKILL.md"
echo "✅ /precommit script  → $AGY_SKILLS/precommit/precommit.sh"

cp "$DOTAI_DIR/commands/prompt-template.sh" "$AGY_SKILLS/prompt/prompt-template.sh"
chmod +x "$AGY_SKILLS/prompt/prompt-template.sh"
echo "✅ /prompt template   → $AGY_SKILLS/prompt/prompt-template.sh"

# ── 3. Skills ────────────────────────────────────────────────────────────────

# Same root as the commands above: skills must be <root>/skills/<name>/SKILL.md.
# Earlier dotai versions wrote flat .md into ~/.gemini/skills/ — wrong on both
# counts, so nothing was ever discovered.
if [ -d "$DOTAI_DIR/skills" ]; then
  rm -rf "$GEMINI_DIR/skills"        # legacy location
  rm -f "$AGY_SKILLS"/*.md           # legacy flat layout
  for skill_dir in "$DOTAI_DIR/skills"/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    name=$(basename "$skill_dir")
    rm -rf "$AGY_SKILLS/$name"
    mkdir -p "$AGY_SKILLS/$name"
    cp -R "$skill_dir." "$AGY_SKILLS/$name/"
    INSTALLED_SKILLS="${INSTALLED_SKILLS:+$INSTALLED_SKILLS · }$name"
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

# complexity-guard (invoked through shared-guard-adapter.sh, see hooks.json)
cp "$DOTAI_DIR/hooks/shared/complexity-guard.sh" "$GEMINI_DIR/hooks/shared/complexity-guard.sh"
chmod +x "$GEMINI_DIR/hooks/shared/complexity-guard.sh"
echo "✅ shared/complexity-guard.sh → $GEMINI_DIR/hooks/shared/complexity-guard.sh"

# shared-guard-adapter — translates agy's JSON hook contract to the exit-code
# contract the shared guards use, so branch/glab/complexity guards can auto-fire
# on PreToolUse instead of being "manual invoke only".
cp "$DOTAI_DIR/hooks/agy/shared-guard-adapter.sh" "$GEMINI_DIR/hooks/shared-guard-adapter.sh"
chmod +x "$GEMINI_DIR/hooks/shared-guard-adapter.sh"
echo "✅ shared-guard-adapter.sh → $GEMINI_DIR/hooks/shared-guard-adapter.sh"

cp "$DOTAI_DIR/hooks/shared/branch-guard.sh" "$GEMINI_DIR/hooks/shared/branch-guard.sh"
chmod +x "$GEMINI_DIR/hooks/shared/branch-guard.sh"
echo "✅ shared/branch-guard.sh → $GEMINI_DIR/hooks/shared/branch-guard.sh"

cp "$DOTAI_DIR/hooks/shared/glab-guard.sh" "$GEMINI_DIR/hooks/shared/glab-guard.sh"
chmod +x "$GEMINI_DIR/hooks/shared/glab-guard.sh"
echo "✅ shared/glab-guard.sh   → $GEMINI_DIR/hooks/shared/glab-guard.sh"

# context-budget-guard (advisory: reminds to start fresh when session grows large)
cp "$DOTAI_DIR/hooks/agy/context-budget-guard.sh" "$GEMINI_DIR/hooks/context-budget-guard.sh"
chmod +x "$GEMINI_DIR/hooks/context-budget-guard.sh"
echo "✅ context-budget-guard.sh → $GEMINI_DIR/hooks/context-budget-guard.sh"

# read-dedup-guard (PreToolUse on view_file — agy's read tool)
cp "$DOTAI_DIR/hooks/agy/read-dedup-guard.sh" "$GEMINI_DIR/hooks/read-dedup-guard.sh"
chmod +x "$GEMINI_DIR/hooks/read-dedup-guard.sh"
echo "✅ read-dedup-guard.sh → $GEMINI_DIR/hooks/read-dedup-guard.sh"

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

# ── 3. Register hooks in ~/.gemini/config/hooks.json ─────────────────────────
#
# agy reads lifecycle hooks from a hooks.json in a customization root — globally
# that is ~/.gemini/config/, NOT ~/.gemini/ and NOT antigravity-cli/settings.json.
# dotai previously registered them under settings.json .hooks.{AfterAgent,
# BeforeTool}; neither event exists in agy, so every guard was silently inert.
# Verified by probe: a Stop hook in config/hooks.json fires, an AfterAgent hook in
# settings.json does not. See CLAUDE.md §agy Hook Contract.

AGY_HOOKS="$GEMINI_DIR/config/hooks.json"

if [[ -f "$AGY_HOOKS" ]] && [[ -s "$AGY_HOOKS" ]]; then
  EXISTING_HOOKS=$(cat "$AGY_HOOKS")
else
  EXISTING_HOOKS="{}"
fi

# Drop our own previous keys, then re-add — keeps foreign/hand-written hooks and
# makes re-runs idempotent. Named hooks are top-level keys, so a shallow
# right-biased merge is the whole story.
MERGED_HOOKS=$(jq -s '
  (.[0] | with_entries(select(.key | startswith("dotai-") | not))) + .[1]
' <(printf '%s' "$EXISTING_HOOKS") "$DOTAI_DIR/hooks/agy/hooks.json")

printf '%s\n' "$MERGED_HOOKS" > "$AGY_HOOKS"
echo "✅ Hooks registered   → $AGY_HOOKS"

# ── 3b. Status line + cleanup of the dead settings.json registration ─────────

SETTINGS="$GEMINI_DIR/antigravity-cli/settings.json"
mkdir -p "$(dirname "$SETTINGS")"

if [[ -f "$SETTINGS" ]] && [[ -s "$SETTINGS" ]]; then
  EXISTING=$(cat "$SETTINGS")
else
  EXISTING="{}"
fi

UPDATED=$(printf '%s' "$EXISTING" | jq --arg home "$HOME" '
  # Remove the dead AfterAgent/BeforeTool entries dotai used to write here, so an
  # upgrade does not leave inert config behind. Only our own entries are touched
  # (matched by the ~/.gemini/hooks/ command path); anything hand-added survives.
  def strip_dotai:
    map(select(([.hooks[]?.command] | join(" ")) | test("\\.gemini/hooks/") | not));

  (if (.hooks | type) == "object" then
     .hooks |= (
       (if has("AfterAgent")  then .AfterAgent  |= strip_dotai else . end)
       | (if has("BeforeTool") then .BeforeTool |= strip_dotai else . end)
       | with_entries(select((.value | type) != "array" or (.value | length) > 0))
     )
     | (if (.hooks | length) == 0 then del(.hooks) else . end)
   else . end)
  |
  # Register status line — dotai owns this key
  .statusLine = {
    "type": "command",
    "command": "bash \($home)/.gemini/statusline.sh",
    "padding": 0
  }
')

echo "$UPDATED" > "$SETTINGS"
echo "✅ Status line        → $SETTINGS"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "dotai → Antigravity CLI (agy) installed."
echo ""
echo "Available:"
echo "  /plan            structured design planning"
echo "  /next-ticket     pick up the next unblocked ticket"
echo "  /handoff         save a compact resume file before starting fresh"
echo "  /precommit       run lint + build + test"
echo "  /prompt          turn a rough idea into a structured, AI-ready task prompt"
echo "  stop-guard       auto-blocks stopping if quality checks were skipped"
echo "  grounding-guard  auto-blocks the first code edit until /ground passes"
echo "  complexity-guard alerts on manual exploration loops"
echo "  context-budget-guard advisory: reminds to start fresh when the session grows large"
echo "  read-dedup-guard blocks full re-reads of files already in context (view_file)"
echo "  branch-guard     prevents edits/commands on master/main (PreToolUse)"
echo "  glab-guard       blocks glab CLI, directs to curl + \$GITLAB_TOKEN + jq"
echo "  statusline       model · context-usage bar · /usage rate-limit bars"
echo "  rules/           AGENTS.md · laravel.md · vue.md · node.md (loaded globally, all projects)"
# Derived from what was actually installed — a hardcoded list silently goes
# stale the moment a skill is added (it already had, omitting reviewer-rules).
echo "  skills/          ${INSTALLED_SKILLS:-(none)}"
echo ""
