#!/usr/bin/env bash
#
# branch-guard.sh
# Prevents accidental pushes to master/main branches.
# Triggered on PreToolUse when Bash tool is about to execute.
#
# Strategy: Check current git branch (reliable) rather than parsing bash command
# (which may not be available in PreToolUse hook context).
#

# Only check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi

# Get current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

# Allow all branches except master/main
if [ "$CURRENT_BRANCH" = "master" ] || [ "$CURRENT_BRANCH" = "main" ]; then
    # --- Read-Only Command Pass-through ---
    # In Claude Code, the command being executed is available in $CLAUDE_TOOL_INPUT (JSON)
    # or sometimes as positional arguments depending on hook configuration.
    
    # Try to extract command from CLAUDE_TOOL_INPUT if jq is available
    EXECUTING_CMD=""
    if command -v jq >/dev/null 2>&1 && [ -n "$CLAUDE_TOOL_INPUT" ]; then
        EXECUTING_CMD=$(echo "$CLAUDE_TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null)
    fi

    # Whitelist of safe read-only commands
    SAFE_COMMANDS="^ls|^grep|^cat|^find|^git status|^git log|^git diff|^pwd|^du|^df|^stat|^file|^which|^type"
    
    # If it's a safe command AND doesn't contain redirection (which implies writing)
    if [ -n "$EXECUTING_CMD" ]; then
        if echo "$EXECUTING_CMD" | grep -qiE "$SAFE_COMMANDS" && ! echo "$EXECUTING_CMD" | grep -qE ">|>>"; then
            exit 0
        fi
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
