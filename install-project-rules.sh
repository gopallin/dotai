#!/usr/bin/env bash
#
# install-project-rules.sh
# Copies dotai rules into the current project's .claude/rules/ directory.
#
# Run from inside any project repo:
#   bash ~/dotai/install-project-rules.sh
#
# Why this exists:
#   Claude Code's user-level ~/.claude/rules/ has a known bug where
#   globs-based path filtering is sometimes ignored. Project-level
#   .claude/rules/ is the reliable fallback.

set -euo pipefail

DOTAI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"
RULES_DIR="$PROJECT_DIR/.claude/rules"

# Must be run from inside a git repo
if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "Error: not inside a git repository. Run this from your project root."
  exit 1
fi

mkdir -p "$RULES_DIR"
cp "$DOTAI_DIR/rules/laravel.md" "$RULES_DIR/laravel.md"
cp "$DOTAI_DIR/rules/vue.md"     "$RULES_DIR/vue.md"
cp "$DOTAI_DIR/rules/node.md"    "$RULES_DIR/node.md"

echo "✅ Rules installed to $RULES_DIR"
echo ""
echo "Tip: commit .claude/rules/ to share standards with your team."
echo "Tip: add .claude/rules/*.local.md to .gitignore for personal overrides."
