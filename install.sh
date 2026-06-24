#!/usr/bin/env bash
#
# install.sh — dotai installer (unified entry point)
#
# Usage:
#   bash install.sh              (interactive menu)
#   bash install.sh claude       (Claude Code)
#   bash install.sh codex        (Codex CLI)
#   bash install.sh agy          (Antigravity CLI)
#   bash install.sh all          (All CLIs)

set -euo pipefail

DOTAI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$DOTAI_DIR/scripts"

# The command that proves each CLI is installed (same `command -v` check the
# sub-installers use for jq). PATH must expose the CLI — e.g. run from a shell
# where the CLI is on PATH (nvm/global npm bin), not a bare non-login shell.
cli_binary() {
  case "$1" in
    claude) echo "claude" ;;
    codex)  echo "codex" ;;
    agy)    echo "agy" ;;
  esac
}

# Run a CLI's installer only if that CLI is on PATH.
# Returns 0 if it ran, 10 if skipped (CLI not installed).
run_installer() {
  local name="$1" bin
  bin="$(cli_binary "$name")"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "⏭️  Skipping ${name}: '${bin}' CLI not found in PATH — nothing installed for it."
    return 10
  fi
  echo "Installing dotai for ${name}..."
  bash "$SCRIPTS_DIR/${name}/install.sh"
}

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
  echo "3) Antigravity CLI (agy)"
  echo "4) All CLIs"
  echo ""
  read -p "Select [1-4]: " selection

  case "$selection" in
    1) CHOICE="claude" ;;
    2) CHOICE="codex" ;;
    3) CHOICE="agy" ;;
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
  claude|codex|agy)
    rc=0
    run_installer "$CHOICE" || rc=$?
    if [ "$rc" -eq 10 ]; then
      echo "Install the CLI first, then re-run: bash install.sh ${CHOICE}"
      exit 1
    fi
    exit "$rc"   # 0, or the sub-installer's own failure code
    ;;
  all)
    echo "Installing dotai for all installed CLIs..."
    ran=0
    failed=0
    for name in claude codex agy; do
      rc=0
      run_installer "$name" || rc=$?
      if [ "$rc" -eq 0 ]; then
        ran=$((ran + 1))
      elif [ "$rc" -ne 10 ]; then
        failed=$((failed + 1))   # installed but its installer errored
      fi
    done
    if [ "$ran" -eq 0 ] && [ "$failed" -eq 0 ]; then
      echo "❌ No supported CLI (claude/codex/agy) found in PATH. Nothing installed."
      exit 1
    fi
    if [ "$failed" -gt 0 ]; then
      exit 1   # at least one installed CLI's installer errored
    fi
    exit 0
    ;;
  *)
    echo "Usage: bash install.sh [claude|codex|agy|all]"
    echo ""
    echo "  Or run without arguments for interactive menu:"
    echo "  bash install.sh"
    exit 1
    ;;
esac
