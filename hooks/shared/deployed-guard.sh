#!/usr/bin/env bash
#
# deployed-guard.sh
# Prevents editing deployed configurations directly in ~/.claude, ~/.gemini, or ~/.codex.
# Directs AI to edit the source files under ~/dotai instead.
#
# Triggered on PreToolUse for Edit/Write/MultiEdit tools.
#

# Resolve tool input to get FILE_PATH
FILE_PATH=""
PATCH_TEXT=""
if command -v jq >/dev/null 2>&1; then
    STDIN_JSON=$(cat 2>/dev/null)
    TOOL_INPUT=""
    if [ -n "$STDIN_JSON" ]; then
        TOOL_INPUT=$(printf '%s' "$STDIN_JSON" | jq -c '.tool_input // .' 2>/dev/null)
    fi
    if [ -z "$TOOL_INPUT" ] || [ "$TOOL_INPUT" = "null" ]; then
        if [ -n "$CLAUDE_TOOL_INPUT" ]; then
            TOOL_INPUT=$(printf '%s' "$CLAUDE_TOOL_INPUT" | jq -c '.tool_input // .' 2>/dev/null)
        fi
    fi
    if [ -n "$TOOL_INPUT" ] && [ "$TOOL_INPUT" != "null" ]; then
        FILE_PATH=$(printf '%s' "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
        PATCH_TEXT=$(printf '%s' "$TOOL_INPUT" | jq -r '.patch // empty' 2>/dev/null)
    fi
fi

# Codex's apply_patch carries paths inside the patch text instead of a
# file_path field. Re-enter this guard once per patch path so a multi-file patch
# cannot hide a deployed configuration edit behind an allowed path. The nested
# invocation receives the normal file_path shape and therefore uses the same
# path normalization and mapping below. Unknown/unparseable input still fails
# open, per the guard contract.
if [ -z "$FILE_PATH" ] && [ -n "$PATCH_TEXT" ]; then
    PATCH_PATHS=$(printf '%s\n' "$PATCH_TEXT" | sed -nE \
        's/^\*\*\* (Update|Add|Delete) File: (.*)$/\2/p; s/^\*\*\* Move to: (.*)$/\1/p')
    while IFS= read -r PATCH_PATH; do
        [ -n "$PATCH_PATH" ] || continue
        PATCH_PAYLOAD=$(jq -cn --arg f "$PATCH_PATH" '{tool_input:{file_path:$f}}')
        printf '%s' "$PATCH_PAYLOAD" | bash "$0"
        PATCH_STATUS=$?
        [ "$PATCH_STATUS" -eq 2 ] && exit 2
        # Any non-standard failure in the nested check is fail-open, matching
        # the normal no-path and malformed-payload behavior.
    done <<EOF
$PATCH_PATHS
EOF
    exit 0
fi

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Resolve file to absolute physical path
FILE_ABS="$FILE_PATH"
case "$FILE_ABS" in /*) ;; *) FILE_ABS="$PWD/$FILE_ABS" ;; esac
SCAN_DIR=$(dirname "$FILE_ABS")
SCAN_REST=$(basename "$FILE_ABS")
while [ ! -d "$SCAN_DIR" ] && [ "$SCAN_DIR" != "/" ] && [ "$SCAN_DIR" != "." ]; do
    SCAN_REST="$(basename "$SCAN_DIR")/$SCAN_REST"
    SCAN_DIR=$(dirname "$SCAN_DIR")
done
SCAN_DIR_P=$(cd "$SCAN_DIR" 2>/dev/null && pwd -P) || SCAN_DIR_P="$SCAN_DIR"
FILE_RESOLVED="$SCAN_DIR_P/$SCAN_REST"

# Check if target is a deployed config file and determine its source path in ~/dotai
IS_DEPLOYED=0
SOURCE_PATH=""

# Helper to check prefix
starts_with() {
    case "$1" in "$2"*) return 0 ;; *) return 1 ;; esac
}

# Resolve HOME path
# On some environments $HOME might contain symlinks, normalize it.
HOME_P=$(cd "$HOME" 2>/dev/null && pwd -P) || HOME_P="$HOME"

# Check mappings
if starts_with "$FILE_RESOLVED" "$HOME_P/.claude/"; then
    REL_PATH="${FILE_RESOLVED#$HOME_P/.claude/}"
    if starts_with "$REL_PATH" "skills/"; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/skills/${REL_PATH#skills/}"
    elif starts_with "$REL_PATH" "commands/"; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/commands/${REL_PATH#commands/}"
    elif starts_with "$REL_PATH" "hooks/"; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/hooks/${REL_PATH#hooks/}"
    elif starts_with "$REL_PATH" "rules/"; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/rules/${REL_PATH#rules/}"
    elif starts_with "$REL_PATH" "dotai-rules/"; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/rules/${REL_PATH#dotai-rules/}"
    elif [ "$REL_PATH" = "CLAUDE.md" ]; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/GLOBAL_RULES.md"
    elif [ "$REL_PATH" = "statusline.sh" ]; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/statusline/claude/statusline.sh"
    fi
elif starts_with "$FILE_RESOLVED" "$HOME_P/.gemini/"; then
    REL_PATH="${FILE_RESOLVED#$HOME_P/.gemini/}"
    # agy stores config under config/ and hooks under hooks/
    if starts_with "$REL_PATH" "config/skills/"; then
        IS_DEPLOYED=1
        SKILL_NAME=$(echo "${REL_PATH#config/skills/}" | cut -d'/' -f1)
        if [ "$SKILL_NAME" = "precommit" ] || [ "$SKILL_NAME" = "plan" ] || [ "$SKILL_NAME" = "map" ] || [ "$SKILL_NAME" = "next-ticket" ] || [ "$SKILL_NAME" = "handoff" ] || [ "$SKILL_NAME" = "prompt" ]; then
            SOURCE_PATH="~/dotai/commands/$SKILL_NAME.md"
        else
            SOURCE_PATH="~/dotai/skills/${REL_PATH#config/skills/}"
        fi
    elif starts_with "$REL_PATH" "config/rules/"; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/rules/${REL_PATH#config/rules/}"
    elif starts_with "$REL_PATH" "rules/"; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/rules/${REL_PATH#rules/}"
    elif starts_with "$REL_PATH" "config/hooks/"; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/hooks/${REL_PATH#config/hooks/}"
    elif starts_with "$REL_PATH" "hooks/"; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/hooks/${REL_PATH#hooks/}"
    elif [ "$REL_PATH" = "config/AGENTS.md" ]; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/GLOBAL_RULES.md"
    elif [ "$REL_PATH" = "statusline.sh" ] || [ "$REL_PATH" = "config/statusline.sh" ]; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/statusline/agy/statusline.sh"
    fi
elif starts_with "$FILE_RESOLVED" "$HOME_P/.codex/"; then
    REL_PATH="${FILE_RESOLVED#$HOME_P/.codex/}"
    if starts_with "$REL_PATH" "prompts/"; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/commands/${REL_PATH#prompts/}"
    elif starts_with "$REL_PATH" "skills/"; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/skills/${REL_PATH#skills/}"
    elif starts_with "$REL_PATH" "hooks/"; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/hooks/${REL_PATH#hooks/}"
    elif [ "$REL_PATH" = "AGENTS.md" ]; then
        IS_DEPLOYED=1
        SOURCE_PATH="~/dotai/GLOBAL_RULES.md"
    fi
fi

if [ "$IS_DEPLOYED" -eq 1 ]; then
    cat >&2 << EOF
❌ dotai Protection: Do not edit deployed config files directly.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
You are trying to edit a deployed file in the CLI configuration directory:
  $FILE_PATH

These files are read-only copies generated from the ~/dotai source repository.

To resolve this:
1. Read [ARCHITECTURE.md](file:///Users/gopal.lin/dotai/ARCHITECTURE.md) to understand the distribution mechanism.
2. Edit the source file under ~/dotai instead:
   ${SOURCE_PATH:-(Locate the corresponding file under ~/dotai/)}
3. Run install.sh in ~/dotai/ to distribute your changes.
EOF
    exit 2
fi

exit 0
