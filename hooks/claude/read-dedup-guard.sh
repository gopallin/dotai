#!/usr/bin/env bash
#
# read-dedup-guard.sh
# Fires on Claude Code's PreToolUse event for Read.
# Blocks a full re-read of a file that is already in context this session and
# has NOT been modified since it was last read — the content is already loaded,
# so re-reading it just re-bills the whole file's tokens on every later turn.
#
# Escape hatches (both exit 0):
#   - Pass offset/limit to Read only the range you need.
#   - Edit/Write/MultiEdit the file first; a modify after the last read re-allows it.
#
# Rationale: usage data showed 1,236 redundant full-file reads across 40% of
# sessions (one file re-read 122× in a single session), and cache_read of
# re-sent context is ~96% of token cost. See the token-waste report.
#
# Exit codes:
#   0 — allow the read
#   2 — block the read (Claude sees the output and must reuse the content already
#       in context, or pass offset/limit)

# ── Read input ────────────────────────────────────────────────────────────────

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
OFFSET=$(echo "$INPUT" | jq -r '.tool_input.offset // empty' 2>/dev/null)
LIMIT=$(echo "$INPUT" | jq -r '.tool_input.limit // empty' 2>/dev/null)

# Cannot verify without a transcript, or non-file read — allow (fail open).
[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0
[[ -z "$FILE_PATH" ]] && exit 0

# A range read is exactly the desired behavior — never block it.
[[ -n "$OFFSET" || -n "$LIMIT" ]] && exit 0

# ── Decide from the file's last event in the transcript ───────────────────────
#
# Walk the transcript IN ORDER, collecting every Read/Edit/Write/MultiEdit that
# targets this exact file. The LAST such event tells us the file's current state:
#   last == Read           → in context, unmodified since → block re-read
#   last == Edit/Write/...  → modified after last read     → allow (changed)
#   (none)                  → never touched                → allow (first read)

LAST=$(jq -rc --arg f "$FILE_PATH" '
  (.message.content // []) | .[]? |
  select(.type? == "tool_use") |
  select(.name? == "Read" or .name? == "Edit" or .name? == "Write" or .name? == "MultiEdit") |
  select((.input.file_path // "") == $f) |
  .name
' "$TRANSCRIPT" 2>/dev/null | tail -n 1)

[[ "$LAST" != "Read" ]] && exit 0

# ── Block: file already in context, unchanged since ───────────────────────────

echo "⛔ read-dedup-guard: \"$FILE_PATH\" was already read this session and not modified since — its full contents are already in context." >&2
echo "Re-reading the whole file re-bills every token on each later turn. Instead:" >&2
echo "  • reuse the content already in context, or" >&2
echo "  • Read with offset/limit to fetch only the range you need." >&2
echo "If the file genuinely changed on disk, Edit/Write it first, or read a range." >&2
exit 2
