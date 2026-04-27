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
