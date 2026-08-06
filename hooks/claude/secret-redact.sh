#!/usr/bin/env bash
#
# secret-redact.sh
# PostToolUse hook: scrubs known credential shapes out of a tool's result BEFORE
# the result reaches the model or the transcript.
#
# Why: a credential that reaches the transcript has left the machine. Transcripts
# are plaintext JSONL under ~/.claude/projects/ and are sent to the model
# provider, so the only real remedy afterwards is revoking the credential.
# Deleting the local copy does nothing. This hook removes the value before that
# happens, which is the whole point — it is a control, not a reminder.
#
# Claude Code only. It depends on PostToolUse `updatedToolOutput`, which replaces
# the tool result; Codex and agy have no documented equivalent, so porting it
# would produce an inert file. See §CLI Feature Gaps in CLAUDE.md.
#
# Registered for `Bash` ONLY — deliberately not for Read/Grep. A redacted Read is
# actively dangerous: the model would see `[REDACTED:…]` as the file's real
# content and could write that placeholder back on the next Edit, destroying the
# value it was protecting. Bash output is consumed as a report, not copied back
# into files, so rewriting it is safe. Do not widen this matcher.
#
# Contract (verified against code.claude.com/docs/en/hooks):
#   stdin : {tool_name, tool_input, tool_response, …}
#   stdout: {"hookSpecificOutput":{"hookEventName":"PostToolUse",
#            "updatedToolOutput": <replacement>}, "systemMessage": "…"}
#   Exit 2 does NOT block at PostToolUse — the tool already ran. Rewriting the
#   output is the only mechanism that actually withholds the value, which is why
#   this hook writes JSON to stdout rather than a warning to stderr.
#

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

STDIN_JSON=$(cat 2>/dev/null)
[ -n "$STDIN_JSON" ] || exit 0

RESPONSE=$(printf '%s' "$STDIN_JSON" | jq -c '.tool_response' 2>/dev/null)
[ -n "$RESPONSE" ] && [ "$RESPONSE" != "null" ] || exit 0

# Redaction runs over the COMPACT JSON serialisation, not the parsed strings, so
# one pass covers every field at any depth. This is safe only because each
# pattern below matches a character class that excludes `"` and `\` — a match can
# therefore never span a JSON string boundary or eat an escape, and the
# replacement introduces neither. Keep that property when adding a pattern.
#
# BSD sed (macOS) has no \b, so anchoring relies on the fixed prefixes.
REDACTED=$(printf '%s' "$RESPONSE" | sed -E '
  s/github_pat_[A-Za-z0-9_]{20,}/[REDACTED:github-fine-grained-pat]/g
  s/gh[pousr]_[A-Za-z0-9]{20,}/[REDACTED:github-token]/g
  s/glpat-[A-Za-z0-9_-]{16,}/[REDACTED:gitlab-pat]/g
  s/glptt-[A-Za-z0-9_-]{16,}/[REDACTED:gitlab-trigger-token]/g
  s/sk-ant-[A-Za-z0-9_-]{20,}/[REDACTED:anthropic-key]/g
  s/AKIA[0-9A-Z]{16}/[REDACTED:aws-access-key-id]/g
  s/xox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED:slack-token]/g
  s/-----BEGIN [A-Z ]*PRIVATE KEY-----/[REDACTED:private-key]/g
')

# Nothing matched — leave the tool result untouched. Emitting updatedToolOutput
# unconditionally would rewrite every single tool result in the session for no
# reason, and any bug here would then corrupt all of them instead of none.
[ "$REDACTED" != "$RESPONSE" ] || exit 0

MSG='🔒 dotai secret-redact: a credential was scrubbed from this tool result before the model saw it. If it was a real, live secret, ROTATE it — assume it is already exposed wherever that command has been run before this hook existed.'

if OUT=$(jq -cn --argjson r "$REDACTED" --arg m "$MSG" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse",updatedToolOutput:$r},systemMessage:$m}' 2>/dev/null); then
    printf '%s' "$OUT"
else
    # Redaction broke the JSON, so the shape cannot be preserved. Withhold the
    # whole result rather than failing open — failing open here means shipping
    # the credential, which is the exact outcome this hook exists to prevent.
    jq -cn --arg m "$MSG" \
      '{hookSpecificOutput:{hookEventName:"PostToolUse",
        updatedToolOutput:"[dotai secret-redact: output withheld — it contained a credential and could not be safely redacted. Re-run the command with a filter that does not print secrets.]"},
        systemMessage:$m}'
fi

exit 0
