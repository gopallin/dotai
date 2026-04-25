#!/usr/bin/env bash
#
# branch-guard.sh
# Prevents accidental pushes to master/main branches.
# Triggered on PreToolUse when Bash tool is about to execute.
#

# Hook receives Bash tool parameters via stdin (JSON) or environment
# Attempt to parse command from available sources
BASH_COMMAND=""

# Method 1: Read from stdin if available (Claude Code hook input)
if [ -s /dev/stdin ]; then
    BASH_COMMAND=$(cat | grep -oE '"command":\s*"[^"]*"' | head -1 | cut -d'"' -f4)
fi

# Method 2: Fallback to positional arguments
if [ -z "$BASH_COMMAND" ]; then
    BASH_COMMAND="$@"
fi

# Check if command is attempting to push to protected branches
if echo "$BASH_COMMAND" | grep -qE "git\s+push.*\b(master|main)\b"; then
    cat >&2 << 'EOF'
❌ dotai Branch Protection
━━━━━━━━━━━━━━━━━━━━━━━━━
Cannot push to master/main directly. Use a feature branch + PR instead.

If you intentionally want to push to master, use:
  git push --force-with-lease origin master

(Not recommended for shared repos.)
EOF
    exit 2
fi

exit 0
