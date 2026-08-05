#!/usr/bin/env bash
#
# stack-rules.sh
# Fires on Claude Code's SessionStart event. Detects the project's tech stack and
# prints ONLY the matching rules file, which Claude Code adds to the session
# context.
#
# Why this exists: `~/.claude/rules/*.md` is auto-loaded by Claude Code with no
# path filtering, so installing laravel.md + vue.md + node.md there meant every
# Laravel session also paid for the Vue and Node rules (~3.4KB of always-wrong
# context). dotai's own CLAUDE.md flagged this: "⚠️ loaded GLOBALLY in every
# project, not path-filtered".
#
# The rules therefore install to ~/.claude/dotai-rules/ — deliberately NOT the
# auto-loaded `rules/` directory — and this hook emits the one that applies.
#
# Detection order matters (matches /precommit's own tech-stack detection):
#   artisan                        → Laravel
#   package.json + vite.config.*   → Vue
#   package.json                   → Node.js
#
# Always exit 0: a rules file is a convenience, never a gate. If detection fails
# the session simply starts with no stack rules, which is the pre-dotai baseline.

# Drain stdin FIRST, before any early exit. Exiting while the caller is still
# writing the payload hands it SIGPIPE, which surfaces as exit 141 under
# `set -o pipefail` — a confusing failure for something that did nothing wrong.
INPUT=$(cat 2>/dev/null)

RULES_DIR="${HOME}/.claude/dotai-rules"
[[ -d "$RULES_DIR" ]] || exit 0

CWD=""
if command -v jq >/dev/null 2>&1 && [[ -n "$INPUT" ]]; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
fi
CWD="${CWD:-$PWD}"

# Prefer the repo root over the shell's cwd — a session opened in a subdirectory
# (app/Services, src/components) would otherwise detect nothing.
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
ROOT="${ROOT:-$CWD}"

if [[ -f "$ROOT/artisan" ]]; then
  STACK="laravel"
elif [[ -f "$ROOT/package.json" ]] && compgen -G "$ROOT/vite.config.*" >/dev/null 2>&1; then
  STACK="vue"
elif [[ -f "$ROOT/package.json" ]]; then
  STACK="node"
else
  exit 0
fi

RULES_FILE="$RULES_DIR/${STACK}.md"
[[ -f "$RULES_FILE" ]] || exit 0

echo "# Stack rules: ${STACK} (auto-loaded by dotai stack-rules.sh — only this stack's rules are in context)"
cat "$RULES_FILE"
exit 0
