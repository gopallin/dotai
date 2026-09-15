#!/usr/bin/env bash
#
# codex-hook-trust.test.sh — pins the "registered but not trusted" warning.
#
# Codex gates hooks behind a trust prompt that Claude Code and agy do not have.
# Declining it writes `enabled = false` under [hooks.state] in config.toml and the
# hook never runs again — while hooks.json still looks perfectly installed. That
# state was live on this machine for branch-guard, stop-guard, glab-guard and
# context-budget-guard, i.e. the two gates the repo is built around were inert.
#
# What this suite pins:
#   1. The warning names the guard by FILE NAME, resolved through hooks.json, not
#      from a hardcoded list that goes stale the moment a hook is added.
#   2. Only hooks explicitly marked `enabled = false` are named. An entry with a
#      trusted_hash and no `enabled` key must NOT be reported — whether that means
#      "trusted" or "new, awaiting review" is unverified, and guessing either way
#      would make the warning lie.
#   3. The state key is split from the RIGHT. The key embeds an absolute path, and
#      a path containing a colon shifts every field if you split from the left.
#   4. The check never fails the install, and never writes trust state back.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL: $*" >&2; }
check() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$2', got '$1')"; fi; }

# Runs the installer in a throwaway HOME whose config.toml is seeded with the
# given [hooks.state] body, and returns the installer output.
run_with_state() {
  local state_body="$1" home
  home=$(mktemp -d)
  mkdir -p "$home/.codex"
  {
    printf 'model = "gpt-5.6-luna"\n\n[hooks.state]\n'
    printf '%s' "$state_body"
  } > "$home/.codex/config.toml"
  # The key embeds the absolute hooks.json path, which depends on $home.
  sed -i '' "s|__HOME__|$home|g" "$home/.codex/config.toml" 2>/dev/null \
    || sed -i "s|__HOME__|$home|g" "$home/.codex/config.toml"
  HOME="$home" bash "$ROOT/scripts/codex/install.sh" 2>&1
  rm -rf "$home"
}

# ── 1. A disabled hook is named, by file name ────────────────────────────────
#
# PreToolUse group 0 is branch-guard and Stop group 0 is stop-guard — the order
# the installer's own jq block writes, which is what makes the index→name lookup
# trustworthy rather than a guess.

OUT=$(run_with_state '
[hooks.state."__HOME__/.codex/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:aaa"
enabled = false

[hooks.state."__HOME__/.codex/hooks.json:stop:0:0"]
trusted_hash = "sha256:bbb"
enabled = false
')

case "$OUT" in *"NOT RUNNING"*) ok ;; *) bad "no warning emitted for disabled hooks" ;; esac
case "$OUT" in *"branch-guard.sh"*) ok ;; *) bad "branch-guard not named in the warning" ;; esac
case "$OUT" in *"stop-guard.sh"*) ok ;; *) bad "stop-guard not named in the warning" ;; esac
# The event must be translated from config.toml's snake_case to hooks.json's
# PascalCase, or the jq lookup silently finds nothing and the hook goes unnamed.
case "$OUT" in *"(PreToolUse)"*) ok ;; *) bad "event not rendered as PreToolUse" ;; esac
case "$OUT" in *"(Stop)"*) ok ;; *) bad "event not rendered as Stop" ;; esac
case "$OUT" in *"/hooks"*) ok ;; *) bad "warning does not name the /hooks fix" ;; esac
# A guard that is NOT disabled must not be swept into the warning. Scope the
# check to the warning block: every guard also appears in the installer's normal
# "✅ copied" output, so grepping the whole transcript would always match.
WARN_BLOCK=$(printf '%s\n' "$OUT" | awk '/NOT RUNNING/{f=1} f')
case "$WARN_BLOCK" in *"grounding-guard.sh"*) bad "named a hook that was not disabled" ;; *) ok ;; esac
case "$WARN_BLOCK" in *"branch-guard.sh"*) ok ;; *) bad "warning block lost branch-guard" ;; esac

# ── 2. trusted_hash without `enabled` is NOT reported ────────────────────────

OUT=$(run_with_state '
[hooks.state."__HOME__/.codex/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:aaa"
')
case "$OUT" in *"NOT RUNNING"*) bad "warned about a hook that was never disabled" ;; *) ok ;; esac

# ── 3. enabled = true is NOT reported ────────────────────────────────────────

OUT=$(run_with_state '
[hooks.state."__HOME__/.codex/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:aaa"
enabled = true
')
case "$OUT" in *"NOT RUNNING"*) bad "warned about an explicitly enabled hook" ;; *) ok ;; esac

# ── 4. No [hooks.state] at all → silence, not a crash ────────────────────────

FRESH=$(mktemp -d)
mkdir -p "$FRESH/.codex"
printf 'model = "gpt-5.6-luna"\n' > "$FRESH/.codex/config.toml"
set +e
OUT=$(HOME="$FRESH" bash "$ROOT/scripts/codex/install.sh" 2>&1)
RC=$?
set -e
check "$RC" "0" "installer must exit 0 when there is no hook state"
case "$OUT" in *"NOT RUNNING"*) bad "warned with no [hooks.state] present" ;; *) ok ;; esac
rm -rf "$FRESH"

# ── 5. A malformed state key must not fail the install ───────────────────────
#
# Fail-open is the rule for anything advisory: a warning that cannot be computed
# is a missing warning, never a broken install.

set +e
OUT=$(run_with_state '
[hooks.state."garbage-without-indices"]
enabled = false

[hooks.state."__HOME__/.codex/hooks.json:pre_tool_use:99:0"]
enabled = false
')
RC=$?
set -e
check "$RC" "0" "installer must survive unparsable/out-of-range state keys"

# ── 6. The check is read-only — it must never write trust state ──────────────
#
# `enabled = false` is a security answer the user gave Codex. dotai reports it;
# flipping it would be dotai overriding a human decision about which scripts may
# run outside the sandbox.

WRITE_HOME=$(mktemp -d)
mkdir -p "$WRITE_HOME/.codex"
{
  printf 'model = "gpt-5.6-luna"\n\n[hooks.state]\n\n'
  printf '[hooks.state."%s/.codex/hooks.json:stop:0:0"]\n' "$WRITE_HOME"
  printf 'trusted_hash = "sha256:bbb"\nenabled = false\n'
} > "$WRITE_HOME/.codex/config.toml"
HOME="$WRITE_HOME" bash "$ROOT/scripts/codex/install.sh" >/dev/null 2>&1
if grep -Eq '^enabled[[:space:]]*=[[:space:]]*false' "$WRITE_HOME/.codex/config.toml"; then ok
else bad "installer altered the user's hook trust state"; fi
rm -rf "$WRITE_HOME"

# ── 7. Claude and agy installers must NOT grow a copy of this ────────────────
#
# Neither CLI has a hook trust model, so a ported check would be an inert file —
# the failure mode CLAUDE.md §agy Hook Contract already warns about.

grep -q 'report_untrusted_codex_hooks' "$ROOT/scripts/codex/install.sh" || bad "check missing from the codex installer"
ok
for other in claude agy; do
  if grep -q 'report_untrusted_codex_hooks' "$ROOT/scripts/$other/install.sh"; then
    bad "$other installer carries a hook-trust check it has no mechanism for"
  else ok; fi
done

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
