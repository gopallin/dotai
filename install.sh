#!/usr/bin/env bash
#
# install.sh — dotai installer (unified entry point)
#
# Usage:
#   bash install.sh              (interactive menu)
#   bash install.sh claude       (Claude Code)
#   bash install.sh codex        (Codex CLI)
#   bash install.sh gemini       (Gemini CLI)
#   bash install.sh all          (All three CLIs)

set -euo pipefail

DOTAI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$DOTAI_DIR/scripts"

# Determine which installer to run
if [ $# -eq 0 ]; then
  # Interactive mode: show menu
  echo ""
  echo "╔════════════════════════════════════════╗"
  echo "║  dotai Installer — Choose CLI Tool    ║"
  echo "╚════════════════════════════════════════╝"
  echo ""
  echo "1) Claude Code"
  echo "2) Codex CLI"
  echo "3) Gemini CLI"
  echo "4) All three CLIs"
  echo ""
  read -p "Select [1-4]: " selection

  case "$selection" in
    1) CHOICE="claude" ;;
    2) CHOICE="codex" ;;
    3) CHOICE="gemini" ;;
    4) CHOICE="all" ;;
    *)
      echo "❌ Invalid selection. Please choose 1-4."
      exit 1
      ;;
  esac
else
  # Command-line mode: use provided argument (strip -- prefix if present)
  CHOICE="${1}"
  CHOICE="${CHOICE#--}"
fi

case "$CHOICE" in
  claude)
    echo "Installing dotai for Claude Code..."
    bash "$SCRIPTS_DIR/claude/install.sh"
    ;;
  codex)
    echo "Installing dotai for Codex CLI..."
    bash "$SCRIPTS_DIR/codex/install.sh"
    ;;
  gemini)
    echo "Installing dotai for Gemini CLI..."
    bash "$SCRIPTS_DIR/gemini/install.sh"
    ;;
  all)
    echo "Installing dotai for all CLIs..."
    bash "$SCRIPTS_DIR/claude/install.sh"
    bash "$SCRIPTS_DIR/codex/install.sh"
    bash "$SCRIPTS_DIR/gemini/install.sh"
    ;;
  *)
    echo "Usage: bash install.sh [claude|codex|gemini|all]"
    echo ""
    echo "  Or run without arguments for interactive menu:"
    echo "  bash install.sh"
    exit 1
    ;;
esac
