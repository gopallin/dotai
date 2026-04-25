#!/usr/bin/env bash
#
# install.sh — dotai installer (unified entry point)
#
# Choose which CLI tool to install dotai for:
#   bash install.sh              (Claude Code - default)
#   bash install.sh --codex      (Codex CLI)
#   bash install.sh --gemini     (Gemini CLI)
#   bash install.sh --all        (All three CLIs)

set -euo pipefail

DOTAI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$DOTAI_DIR/scripts"

# Determine which installer to run
CHOICE="${1:-claude}"

case "$CHOICE" in
  claude|"")
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
    echo "  claude  Install for Claude Code (default)"
    echo "  codex   Install for Codex CLI"
    echo "  gemini  Install for Gemini CLI"
    echo "  all     Install for all three CLIs"
    exit 1
    ;;
esac
