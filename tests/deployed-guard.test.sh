#!/usr/bin/env bash

# deployed-guard blocks editing configuration files directly under ~/.claude, ~/.gemini, and ~/.codex.
# It directs the AI/user to read ARCHITECTURE.md and edit the source files under ~/dotai instead.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$ROOT/hooks/shared/deployed-guard.sh"

PASS=0
FAIL=0

# Resolve actual HOME directory
HOME_P=$(cd "$HOME" 2>/dev/null && pwd -P) || HOME_P="$HOME"

# want=block → guard must exit 2; want=allow → guard must exit 0.
check() {
  local want=$1 file=$2
  local status
  # Expand ~ to actual home path in the input path
  local expanded_file="${file/#\~/$HOME_P}"

  printf '%s' "$(jq -cn --arg f "$expanded_file" '{tool_input:{file_path:$f}}')" \
    | bash "$GUARD" >/dev/null 2>&1
  status=$?
  case "$want" in
    block) [ "$status" -eq 2 ] && { PASS=$((PASS+1)); return; } ;;
    allow) [ "$status" -eq 0 ] && { PASS=$((PASS+1)); return; } ;;
  esac
  FAIL=$((FAIL+1))
  echo "❌ expected $want, got exit $status for: $file (expanded: $expanded_file)" >&2
}

# Real deployed paths — must stay blocked.
check block '~/.claude/skills/git-push/SKILL.md'
check block '~/.claude/commands/plan.md'
check block '~/.claude/hooks/shared/branch-guard.sh'
check block '~/.claude/rules/vue.md'
check block '~/.claude/dotai-rules/vue.md'
check block '~/.claude/CLAUDE.md'
check block '~/.claude/statusline.sh'

check block '~/.gemini/config/skills/precommit/SKILL.md'
check block '~/.gemini/config/skills/git-push/SKILL.md'
check block '~/.gemini/config/rules/vue.md'
check block '~/.gemini/rules/vue.md'
check block '~/.gemini/config/hooks/stop-guard.sh'
check block '~/.gemini/hooks/stop-guard.sh'
check block '~/.gemini/config/AGENTS.md'
check block '~/.gemini/statusline.sh'
check block '~/.gemini/config/statusline.sh'

check block '~/.codex/prompts/plan.md'
check block '~/.codex/skills/git-push/SKILL.md'
check block '~/.codex/hooks/stop-guard.sh'
check block '~/.codex/AGENTS.md'

# Codex apply_patch carries paths inside the patch field, not file_path. The
# guard must inspect every file path in a patch, including a mixed patch where
# an allowed file appears before the deployed one.
check_patch() {
  local want=$1 patch=$2 status
  printf '%s' "$(jq -cn --arg p "$patch" '{tool_input:{patch:$p}}')" \
    | bash "$GUARD" >/dev/null 2>&1
  status=$?
  case "$want" in
    block) [ "$status" -eq 2 ] && { PASS=$((PASS+1)); return; } ;;
    allow) [ "$status" -eq 0 ] && { PASS=$((PASS+1)); return; } ;;
  esac
  FAIL=$((FAIL+1))
  echo "❌ expected $want, got exit $status for patch: $patch" >&2
}

check_patch block "*** Begin Patch
*** Update File: /tmp/allowed.md
@@
-a
+b
*** Update File: $HOME_P/.codex/skills/git-push/SKILL.md
@@
-a
+b
*** End Patch"
check_patch allow "*** Begin Patch
*** Update File: /tmp/allowed.md
@@
-a
+b
*** End Patch"

# Files that are under CLI dirs but allowed (not managed config files)
check allow '~/.claude/settings.json'
check allow '~/.claude/settings.local.json'
check allow '~/.claude/usage-data/report.html'
check allow '~/.gemini/antigravity-cli/settings.json'

# Allowed source paths in dotai
check allow "$ROOT/skills/git-push/SKILL.md"
check allow "$ROOT/commands/plan.md"
check allow "$ROOT/hooks/shared/branch-guard.sh"
check allow "$ROOT/rules/vue.md"
check allow "$ROOT/GLOBAL_RULES.md"
check allow "$ROOT/statusline/claude/statusline.sh"

# Allowed arbitrary temp files
check allow '/tmp/scratch.md'
check allow '/tmp/some_random_code.ts'

# The plugin manifest must register the same deployed guard as the installers.
grep -Fq 'hooks/shared/deployed-guard.sh' "$ROOT/hooks/hooks.json" \
  && PASS=$((PASS+1)) \
  || { FAIL=$((FAIL+1)); echo "❌ plugin manifest does not register deployed-guard" >&2; }

# A command with no parsable input must fail open, never block everything.
printf '%s' '{}' | bash "$GUARD" >/dev/null 2>&1
[ $? -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "❌ empty payload should fail open" >&2; }

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
