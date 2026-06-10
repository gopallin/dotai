#!/usr/bin/env bash
#
# branch-guard.sh
# Prevents accidental edits/commits/pushes to master/main branches.
# Triggered on PreToolUse for Bash and Edit/Write/MultiEdit tools.
#
# Strategy: Check current git branch (reliable) rather than parsing the command
# (which may not be available in every hook context).
#
# Tool input is read from stdin (Claude Code's PreToolUse JSON: {tool_input:{...}})
# with the legacy CLAUDE_TOOL_INPUT env var as a fallback.
#

# Only check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi

# Get current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

# Allow all branches except master/main
if [ "$CURRENT_BRANCH" = "master" ] || [ "$CURRENT_BRANCH" = "main" ]; then
    # --- Resolve the tool input (Bash command and/or Edit/Write file_path) ---
    EXECUTING_CMD=""
    FILE_PATH=""
    if command -v jq >/dev/null 2>&1; then
        RAW_INPUT="$CLAUDE_TOOL_INPUT"
        if [ -z "$RAW_INPUT" ]; then
            STDIN_JSON=$(cat 2>/dev/null)
            RAW_INPUT=$(echo "$STDIN_JSON" | jq -c '.tool_input // empty' 2>/dev/null)
        fi
        if [ -n "$RAW_INPUT" ]; then
            EXECUTING_CMD=$(echo "$RAW_INPUT" | jq -r '.command // empty' 2>/dev/null)
            FILE_PATH=$(echo "$RAW_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
        fi
    fi

    # --- Bash read-only pass-through ---
    # Whitelist of safe read-only commands.
    # git checkout / git switch are allowed so the agent can escape master/main
    # by creating a feature branch (otherwise it would be trapped: every bash,
    # including the checkout needed to leave, gets blocked).
    SAFE_COMMANDS="^ls|^grep|^cat|^find|^git status|^git log|^git diff|^git checkout|^git switch|^pwd|^du|^df|^stat|^file|^which|^type"
    if [ -n "$EXECUTING_CMD" ]; then
        if echo "$EXECUTING_CMD" | grep -qiE "$SAFE_COMMANDS" && ! echo "$EXECUTING_CMD" | grep -qE ">|>>"; then
            exit 0
        fi
    fi

    # --- Edit/Write/MultiEdit doc pass-through ---
    # Documentation edits (*.md, anything under .claudedocs/) are allowed on
    # master/main — mirrors stop-guard, which treats docs as non-code changes.
    if [ -n "$FILE_PATH" ]; then
        case "$FILE_PATH" in
            *.md|*/.claudedocs/*) exit 0 ;;
        esac
    fi
    # --------------------------------------

    cat >&2 << 'EOF'
❌ dotai Branch Protection
━━━━━━━━━━━━━━━━━━━━━━━━━
You are currently on 'master' or 'main' branch.
Cannot edit, commit, or push from protected branches.

To proceed:
1. Create a feature branch: git checkout -b feature/your-feature
2. Make changes there
3. Push and create a PR

If you intentionally need to edit main:
- Use git checkout to switch to main manually
- Make changes
- Use: git push --force-with-lease origin main (NOT RECOMMENDED)
EOF
    exit 2
fi

exit 0
