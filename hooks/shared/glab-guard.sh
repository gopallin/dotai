#!/usr/bin/env bash
#
# glab-guard.sh
# Blocks `glab` CLI usage and directs AI to use curl + $GITLAB_TOKEN + jq.
# glab is not installed; this hook prevents wasted round-trips.
#
# Runs on PreToolUse for Bash. Parses tool_input the same way as branch-guard.sh.
#

EXECUTING_CMD=""
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
        EXECUTING_CMD=$(printf '%s' "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null)
    fi
fi

# No command parsed — nothing to block
if [ -z "$EXECUTING_CMD" ]; then
    exit 0
fi

# Strip quoted substrings before matching. The separator alternation below treats
# any `|` as a shell pipe, so a read-only search whose PATTERN contains `\|glab`
# (e.g. grep -rn "gitlab\.com\|glab \|PRIVATE-TOKEN") was blocked even though
# nothing is executed — pure friction on a command that cannot invoke glab.
#
# Accepted trade-off: this also stops matching a glab hidden inside quotes, e.g.
# `bash -c "glab mr list"`. That is deliberate. The failure mode this guard exists
# to prevent is the agent typing `glab ...` directly; losing the contrived
# quoted-invocation case is cheaper than blocking every grep for the string.
SCRUBBED=$(printf '%s' "$EXECUTING_CMD" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")

# Block any command whose command position is `glab`
if echo "$SCRUBBED" | grep -qE '(^|;|\||\&\&|\|\|)\s*glab\b'; then
    cat >&2 << 'EOF'
❌ dotai: glab is not installed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Do NOT use the `glab` CLI. It is not installed on this system.

Use curl + $GITLAB_TOKEN + jq instead:

  curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "https://gitlab.com/api/v4/..." | jq '<filter>'

Rules:
- $GITLAB_TOKEN is already set in the shell (loaded from macOS Keychain).
- Always pipe through jq to filter fields — never dump raw JSON.
- For git push, use the git-push skill (SSH or credential helper).
EOF
    exit 2
fi

exit 0
