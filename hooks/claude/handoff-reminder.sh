#!/usr/bin/env bash
#
# handoff-reminder.sh (Claude Code adapter)
# Fires on SessionStart with source "clear": the moment a fresh session is born
# after /clear. Detection is code, not AI: this script finds the cleared
# session's transcript on disk and checks whether a fresh handoff file exists.
#
# - Fresh handoff found  → inject "read it and continue".
# - No fresh handoff     → inject an offer the AI relays on the user's first
#   message: /resume the old session and write /handoff there (high fidelity),
#   or reconstruct from the transcript tail (cheap, unverified), or skip.
#
# stdout is added to the new session's context. Never blocks (exit 0 always).

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

# Newest transcript in this project other than the current session = the
# session that was just cleared.
PREV="" PREV_MTIME=0
for f in "$DIR"/*.jsonl; do
  [[ -f "$f" ]] || continue
  [[ "$(basename "$f")" == "$CURRENT" ]] && continue
  m=$(mtime "$f")
  [[ "$m" =~ ^[0-9]+$ ]] || continue
  if (( m > PREV_MTIME )); then PREV="$f"; PREV_MTIME="$m"; fi
done
[[ -n "$PREV" ]] || exit 0

# Too small to be worth handing off.
LINES=$(wc -l < "$PREV" 2>/dev/null | tr -d ' ')
[[ "$LINES" =~ ^[0-9]+$ ]] && (( LINES >= 50 )) || exit 0

PREV_ID=$(basename "$PREV" .jsonl)

# Newest handoff file in the project (any branch — name matching is fragile).
HANDOFF="" H_MTIME=0
for f in "$CWD"/.claudedocs/handoff-*.md "$CWD"/handoff-*.md; do
  [[ -f "$f" ]] || continue
  m=$(mtime "$f")
  [[ "$m" =~ ^[0-9]+$ ]] || continue
  if (( m > H_MTIME )); then HANDOFF="$f"; H_MTIME="$m"; fi
done

# Fresh = written within 5 minutes of the cleared session's last activity
# (the /handoff turn itself bumps the transcript mtime after the file write).
if [[ -n "$HANDOFF" ]] && (( PREV_MTIME - H_MTIME < 300 )); then
  cat <<EOF
[dotai handoff-reminder] This session started from /clear. A fresh handoff exists: $HANDOFF
On the user's first message, read that file before anything else and continue from its "Next Step".
EOF
  exit 0
fi

cat >&2 <<EOF

[dotai handoff-reminder] 上一個 session 未留下最新的 handoff 檔案。
請選擇接下來的動作 (在輸入框直接告訴 AI 即可)：
  A. 高保真 — /resume 回 $PREV_ID，在那邊跑 /handoff，再 /clear
  B. 便宜 — 從 transcript 的尾段重建 handoff (會標記未驗證，可能漏掉中途的決策)
  C. 跳過 — 不要 handoff，直接處理這題

EOF

cat <<EOF
[dotai handoff-reminder] This session started from /clear and the previous session left no fresh handoff.
Previous session: $PREV_ID (~$LINES transcript lines)
Transcript on disk: $PREV

The user has been prompted directly in the terminal to choose A, B, or C.
If they choose A, they will run the resume command themselves.
If they choose B, reconstruct a handoff from the TAIL of the transcript above (per /handoff Reconstruction Mode: mark unverified, may miss mid-session decisions).
If they choose C, continue without a handoff.
Do not reconstruct or resume anything until the user chooses.
EOF
exit 0
