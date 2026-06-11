#!/usr/bin/env bash
#
# statusline.sh — Claude Code status line (bar-graph display)
# Shows: model · context usage bar · plan rate-limit bars
#
# Data source: the JSON Claude Code pipes to the statusLine command on stdin.
#   .context_window.*  — always present after the first API call
#   .rate_limits.*     — the data behind /usage; Claude.ai Pro/Max only,
#                        absent for API / managed accounts (degrades silently)
#

input=$(cat)

jqr() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

# Render a colored bar: bar <pct> [width] -> "████░░░░"
# Purple normally; red when this bar is >80% used.
bar() {
  awk -v p="${1:-0}" -v w="${2:-8}" 'BEGIN{
    esc = sprintf("%c", 27);
    col = (p > 80) ? esc "[38;5;203m" : esc "[38;5;141m";   # red / purple
    rst = esc "[0m";
    f = int(p*w/100 + 0.5); if(f>w)f=w; if(f<0)f=0;
    s=""; for(i=0;i<f;i++)s=s"█"; for(i=f;i<w;i++)s=s"░";
    printf "%s%s%s", col, s, rst;
  }'
}

intpct() { [ -n "$1" ] && printf '%.0f' "$1"; }            # "23.5" -> "24"
fmtk()   { awk -v n="${1:-0}" 'BEGIN{ if(n>=1000) printf "%.0fk", n/1000; else printf "%d", n }'; }

model=$(jqr '.model.display_name // "?"')

used_pct=$(jqr '.context_window.used_percentage // empty')
in_tok=$(jqr '.context_window.total_input_tokens // 0')
win=$(jqr '.context_window.context_window_size // 0')

# --- context segment ---
if [ -n "$used_pct" ]; then
  up=$(intpct "$used_pct")
  ctx="ctx [$(bar "$up")] $(fmtk "$in_tok")/$(fmtk "$win") ${up}%"
else
  # null before first API call / right after /compact
  ctx="ctx [$(bar 0)] —"
fi

out="$model · $ctx"

# --- plan rate limits (= /usage); only if the account exposes them ---
five=$(jqr '.rate_limits.five_hour.used_percentage // empty')
seven=$(jqr '.rate_limits.seven_day.used_percentage // empty')
if [ -n "$five" ]; then
  fi5=$(intpct "$five"); fi7=$(intpct "$seven")
  out="$out · 5h [$(bar "$fi5")] ${fi5}% · 7d [$(bar "$fi7")] ${fi7}%"
fi

printf '%s' "$out"
