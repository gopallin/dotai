#!/usr/bin/env bash
#
# handoff-reminder.sh (Codex CLI)
# Fires on SessionStart with source "clear" and injects handoff guidance.

INPUT=$(cat)
SOURCE=$(echo "$INPUT" | jq -r '.source // empty' 2>/dev/null)
[[ "$SOURCE" == "clear" ]] || exit 0

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CWD="${CWD:-$PWD}"
[[ -n "$TRANSCRIPT" ]] || exit 0

DIR=$(dirname "$TRANSCRIPT")
[[ -d "$DIR" ]] || exit 0
CURRENT=$(basename "$TRANSCRIPT")

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

PREV="" PREV_MTIME=0
for f in "$DIR"/*.jsonl; do
  [[ -f "$f" ]] || continue
  [[ "$(basename "$f")" == "$CURRENT" ]] && continue
  m=$(mtime "$f")
  [[ "$m" =~ ^[0-9]+$ ]] || continue
  if (( m > PREV_MTIME )); then PREV="$f"; PREV_MTIME="$m"; fi
done
[[ -n "$PREV" ]] || exit 0

LINES=$(wc -l < "$PREV" 2>/dev/null | tr -d ' ')
[[ "$LINES" =~ ^[0-9]+$ ]] && (( LINES >= 50 )) || exit 0

PREV_ID=$(basename "$PREV" .jsonl)
HANDOFF="" H_MTIME=0
for f in "$CWD"/.claudedocs/handoff-*.md "$CWD"/handoff-*.md; do
  [[ -f "$f" ]] || continue
  m=$(mtime "$f")
  [[ "$m" =~ ^[0-9]+$ ]] || continue
  if (( m > H_MTIME )); then HANDOFF="$f"; H_MTIME="$m"; fi
done

if [[ -n "$HANDOFF" ]] && (( PREV_MTIME - H_MTIME < 300 )); then
  cat <<EOF
[dotai handoff-reminder] This session started from /clear. A fresh handoff exists: $HANDOFF
On the user's first message, read that file before anything else and continue from its "Next Step".
EOF
  exit 0
fi

cat <<EOF
[dotai handoff-reminder] This session started from /clear and the previous session left no fresh handoff.
Previous session: $PREV_ID (~$LINES transcript lines)
Transcript on disk: $PREV

On the user's first message, briefly offer these options in the user's language before starting their task:
  A. High fidelity — /resume back into session $PREV_ID, run /handoff there, then /clear again.
  B. Cheap — reconstruct a handoff from the TAIL of the transcript above; mark it unverified.
  C. Skip — continue without a handoff.
Do not reconstruct or resume anything until the user chooses.
EOF
