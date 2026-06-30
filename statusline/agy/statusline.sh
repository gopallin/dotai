#!/usr/bin/env bash
#
# statusline.sh — Antigravity CLI (agy) status line (bar-graph display)
# Shows: model · context usage bar · plan rate-limit bars
#
# Data source: the JSON agy pipes to the statusLine command on stdin.
#   .context_window.*  — always present after the first API call
#   .rate_limits.*     — the data behind /usage; Google One / Pro accounts,
#                        absent for API / managed accounts (degrades silently)
#

input=$(cat)

jqr() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

fmt_duration() {
  local s="$1"
  [ -z "$s" ] || [ "$s" = "null" ] && return
  local h=$((s / 3600))
  local m=$(((s % 3600) / 60))
  echo "${h}h ${m}m"
}

# Render a colored bar: bar <pct> [width] -> "████░░░░"
# Purple normally; red when this bar is >80% used.
# Render a colored bar: bar <pct> [width] [is_remaining]
# Purple normally; red when high usage (>80% used) or low remaining (<=20% remaining).
bar() {
  awk -v p="${1:-0}" -v w="${2:-8}" -v rem="${3:-0}" 'BEGIN{
    esc = sprintf("%c", 27);
    is_red = rem ? (p <= 20) : (p > 80);
    col = is_red ? esc "[38;5;203m" : esc "[38;5;141m";   # red / purple
    rst = esc "[0m";
    f = int(p*w/100 + 0.5); if(f>w)f=w; if(f<0)f=0;
    s=""; for(i=0;i<f;i++)s=s"█"; for(i=f;i<w;i++)s=s"░";
    printf "%s%s%s", col, s, rst;
  }'
}

intpct() { [ -n "$1" ] && printf '%.0f' "$1"; }            # "23.5" -> "24"
fmtk()   { awk -v n="${1:-0}" 'BEGIN{ if(n>=1000) printf "%.0fk", n/1000; else printf "%d", n }'; }

# Format a reset time from a Unix epoch in local time (= /usage's timezone).
#   fmt_reset <epoch> time  -> "2pm"        (5h window: time only)
#   fmt_reset <epoch> date  -> "Jun 14 1pm" (7d window: date + time)
# Minutes are shown only when not on the hour. Empty/null -> nothing.
fmt_reset() {
  local e="$1" kind="$2" min tfmt
  [ -z "$e" ] || [ "$e" = "null" ] && return
  # %M differs across date(1) flavors only in the flag, not the field
  min=$(date -r "$e" '+%M' 2>/dev/null || date -d "@$e" '+%M' 2>/dev/null) || return
  tfmt='%-I%p'; [ "$min" != "00" ] && tfmt='%-I:%M%p'
  [ "$kind" = "date" ] && tfmt="%b %-d $tfmt"
  { date -r "$e" "+$tfmt" 2>/dev/null || date -d "@$e" "+$tfmt" 2>/dev/null; } | sed 's/AM/am/;s/PM/pm/'
}

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
gem_rem_frac=$(jqr '.quota["gemini-weekly"].remaining_fraction // empty')
tp_rem_frac=$(jqr '.quota["3p-weekly"].remaining_fraction // empty')

if [ -n "$gem_rem_frac" ]; then
  gem_rem=$(awk -v f="$gem_rem_frac" 'BEGIN { printf "%.0f", f * 100 }')
  gem_sec=$(jqr '.quota["gemini-weekly"].reset_in_seconds // empty')
  gem_reset=$(fmt_duration "$gem_sec")
  out="$out · gemini [$(bar "$gem_rem" 8 1)] ${gem_rem}%${gem_reset:+ ↺$gem_reset}"
fi

if [ -n "$tp_rem_frac" ]; then
  tp_rem=$(awk -v f="$tp_rem_frac" 'BEGIN { printf "%.0f", f * 100 }')
  tp_sec=$(jqr '.quota["3p-weekly"].reset_in_seconds // empty')
  tp_reset=$(fmt_duration "$tp_sec")
  out="$out · claude-gpt [$(bar "$tp_rem" 8 1)] ${tp_rem}%${tp_reset:+ ↺$tp_reset}"
fi

printf '%s' "$out"
