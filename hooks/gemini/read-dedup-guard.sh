#!/usr/bin/env bash
#
# read-dedup-guard.sh (Gemini CLI adapter — EXPERIMENTAL, BLOCKS)
# Port of the Claude read-dedup-guard: blocks a full re-read of a file already
# read this session, to stop re-billing the whole file's tokens every later turn.
#
# ⚠️ UNVERIFIED — verify against your installed Gemini CLI before relying on this:
#   1. That the `BeforeTool` event actually FIRES for the built-in `read_file`
#      tool (docs only show write_file/replace examples — github.com/google-gemini/
#      gemini-cli docs/hooks/reference.md). If it does not fire, this hook is inert.
#   2. That exit code 2 + stderr denies the call (the documented deny path).
#
# Design difference vs the Claude version: Gemini's transcript format is not
# documented as stable, so instead of parsing a transcript this hook tracks
# already-read paths in a per-session marker file it maintains itself.
#
# Escape hatch: pass offset/limit to read a range (always allowed). After editing
# a file, re-read it with offset/limit — a plain full re-read stays blocked.
#
# Exit codes: 0 — allow; 2 — block (stderr becomes the deny reason).

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
# Gemini's read_file uses `absolute_path`; accept file_path too for safety.
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.absolute_path // .tool_input.file_path // empty' 2>/dev/null)
OFFSET=$(echo "$INPUT" | jq -r '.tool_input.offset // empty' 2>/dev/null)
LIMIT=$(echo "$INPUT" | jq -r '.tool_input.limit // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION_ID="${SESSION_ID:-${GEMINI_SESSION_ID:-unknown}}"

# Only act on the read tool; never block anything else.
[[ "$TOOL_NAME" != "read_file" ]] && exit 0
[[ -z "$FILE_PATH" ]] && exit 0

# A range read is exactly the desired behavior — and the escape hatch — allow it.
[[ -n "$OFFSET" || -n "$LIMIT" ]] && exit 0

MARKER="/tmp/dotai_gemini_reads_${SESSION_ID}"
touch "$MARKER" 2>/dev/null || exit 0   # cannot track — fail open

# Already read this session → block the redundant full re-read.
if grep -qxF "$FILE_PATH" "$MARKER" 2>/dev/null; then
  echo "⛔ read-dedup-guard: \"$FILE_PATH\" was already read this session — its contents are already in context." >&2
  echo "Reuse what is in context, or read a range with offset/limit instead of re-reading the whole file." >&2
  exit 2
fi

# First read of this file this session — record it and allow.
echo "$FILE_PATH" >> "$MARKER"
exit 0
