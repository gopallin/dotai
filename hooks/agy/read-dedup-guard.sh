#!/usr/bin/env bash
#
# read-dedup-guard.sh (agy CLI adapter — PreToolUse, BLOCKING)
#
# Blocks a full re-read of a file already read this session, so the whole file's
# tokens are not re-billed on every later turn.
#
# agy contract (verified against agy CLI — see CLAUDE.md §agy Hook Contract):
#   event  : PreToolUse, matcher view_file  (agy's read tool is `view_file`, not
#            `read_file`; and there is no "BeforeTool" event — the previous
#            registration was inert, which is what §Verification was unsure about)
#   stdout : {"decision":"deny","reason":"..."} blocks; {"decision":"allow"} permits.
#
# Instead of parsing a transcript, this tracks already-read paths in a
# per-conversation marker file.
#
# Escape hatch: a ranged read is always allowed. After editing a file, re-read it
# with a range — a plain full re-read stays blocked.

allow() { printf '%s' '{"decision":"allow"}'; exit 0; }
deny()  { jq -cn --arg r "$1" '{decision:"deny",reason:$r}'; exit 0; }

command -v jq >/dev/null 2>&1 || { printf '%s' '{"decision":"allow"}'; exit 0; }

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.toolCall.name // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.conversationId // empty' 2>/dev/null)
# Sanitised because it is interpolated into a /tmp path below (see grounding-guard).
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-')
SESSION_ID="${SESSION_ID:-unknown}"

[[ "$TOOL_NAME" != "view_file" ]] && allow

# PascalCase args (verified pattern: run_command→CommandLine, list_dir→
# DirectoryPath). The exact view_file key is not yet confirmed — accept the
# plausible spellings; an unmatched key fails open rather than blocking wrongly.
ARGS=$(printf '%s' "$INPUT" | jq -c '.toolCall.args // {}' 2>/dev/null)
FILE_PATH=$(printf '%s' "$ARGS" | jq -r '
  (.AbsolutePath // .TargetFile // .TargetFilePath // .FilePath // .Path // .File // empty)
' 2>/dev/null)
RANGE=$(printf '%s' "$ARGS" | jq -r '
  (.StartLine // .StartLineOneIndexed // .Offset // .EndLine // .EndLineOneIndexed // .Limit // empty)
' 2>/dev/null)

[[ -z "$FILE_PATH" ]] && allow

# A ranged read is the desired behavior — and the escape hatch — so allow it.
[[ -n "$RANGE" ]] && allow

MARKER="/tmp/dotai_agy_reads_${SESSION_ID}"
touch "$MARKER" 2>/dev/null || allow   # cannot track — fail open

if grep -qxF "$FILE_PATH" "$MARKER" 2>/dev/null; then
  deny "\"$FILE_PATH\" was already read this session — its contents are already in context. Reuse what is in context, or read a line range instead of re-reading the whole file."
fi

echo "$FILE_PATH" >> "$MARKER"
allow
