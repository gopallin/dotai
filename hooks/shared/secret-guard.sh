#!/usr/bin/env bash
#
# secret-guard.sh
# Blocks commands that dump credentials WHOLESALE, where "wholesale" means the
# output contains an unbounded set of secrets whose format is not known in
# advance.
#
# This is deliberately narrow. Its companion, claude/secret-redact.sh, scrubs
# known token shapes (github_pat_, glpat-, …) out of tool output after the fact,
# and that covers almost everything. The one case redaction CANNOT cover is a
# keychain dump: it emits arbitrary passwords and custom-format secrets that
# match no pattern, so there is nothing for the redactor to recognise.
#
# Why this exists: on 2026-08-06 a `security dump-keychain` in a live session put
# a live GitHub PAT into the transcript in plaintext (the token had been stored,
# by mistake, as an item's service name — an attribute, not the protected
# password blob). The transcript is plaintext JSONL on disk and is sent to the
# model provider, so the token had to be revoked, not merely deleted.
#
# Runs on PreToolUse for Bash. Parses tool_input the same way as glab-guard.sh.
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

# Strip quoted substrings before matching, for the same reason glab-guard does:
# a read-only `grep -rn "dump-keychain"` over this repo must not be blocked by a
# guard that only cares about the command actually being executed.
SCRUBBED=$(printf '%s' "$EXECUTING_CMD" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")

if echo "$SCRUBBED" | grep -qE '(^|;|\||\&\&|\|\|)[[:space:]]*security[[:space:]]+dump-keychain'; then
    cat >&2 << 'EOF'
❌ dotai: `security dump-keychain` is blocked
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
It prints every item's attributes, including any secret that was stored in an
attribute field rather than the password blob. That output lands in the
transcript in plaintext and is sent to the model provider — a leak that can only
be undone by revoking the credential, not by deleting it locally.

Query one item instead, by service name:

  security find-generic-password -s ai-agent-github-token          # attributes
  security find-generic-password -a github -s ai-agent-github-token -w   # value

To check a secret WITHOUT printing it, compare hashes:

  security find-generic-password -a github -s ai-agent-github-token -w \
    | tr -d '\n' | shasum -a 256 | cut -c1-16

To list what exists without values, use Keychain Access.app.
EOF
    exit 2
fi

exit 0
