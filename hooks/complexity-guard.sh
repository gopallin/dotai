#!/usr/bin/env bash
#
# complexity-guard.sh
# Generic hook for dotai to detect manual exploration patterns across CLIs.
#

# 1. Identify Session (cross-CLI adaptation)
# Claude uses CLAUDE_SESSION_ID
# Gemini uses GEMINI_SESSION_ID (or we default to "unknown")
SESSION_ID="${CLAUDE_SESSION_ID:-${GEMINI_SESSION_ID:-unknown}}"
COUNTER_FILE="/tmp/dotai_complexity_${SESSION_ID}"
THRESHOLD=5

# 2. Identify Tool Name
# Claude: CLAUDE_TOOL_NAME
# Gemini: often passed as $1 (positional parameter)
TOOL_NAME="${CLAUDE_TOOL_NAME:-$1}"

# Initialize and increment counter
[ ! -f "$COUNTER_FILE" ] && echo "0" > "$COUNTER_FILE"
COUNT=$(($(cat "$COUNTER_FILE") + 1))
echo "$COUNT" > "$COUNTER_FILE"

# 3. Trigger Detection
# Matches both Claude (Grep, Read) and Gemini (grep_search, read_file) tool names
case "$TOOL_NAME" in
    "Grep"|"grep_search"|"Read"|"read_file"|"Glob"|"glob"|"list_directory")
        if [ "$COUNT" -ge "$THRESHOLD" ]; then
            echo -e "\033[1;33m[dotai ADVISORY]\033[0m Continuous manual exploration detected (Step $COUNT)." >&2
            echo -e "To maintain clean context, consider delegating to \033[1;36mcodebase_investigator\033[0m or a Task Agent." >&2
        fi
        ;;
esac
