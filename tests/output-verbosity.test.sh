#!/usr/bin/env bash
#
# output-verbosity.test.sh — pins the concise-response defaults.
#
# Each of the three CLIs gets the strongest verbosity lever it actually has:
#   Claude Code  outputStyle = "Concise"        (built-in style, replaces defaults)
#   Codex        model_verbosity = "medium"     (native API-layer knob)
#   agy          GLOBAL_RULES.md prose          (no native lever exists)
#
# What this suite exists to catch, in order of how badly each one bit before:
#   1. A top-level TOML key appended at EOF, which lands inside the last [table]
#      and is never read — the "looks installed, does nothing" class.
#   2. A re-install overwriting a preference the user deliberately changed.
#   3. The prose half quietly losing its "explain / errors / warnings stay long"
#      carve-out, which would turn a style rule into a correctness bug.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# ── Claude Code: outputStyle ─────────────────────────────────────────────────

mkdir -p "$TEST_HOME/.claude"
# A pre-existing setting that must survive the merge untouched.
printf '{"theme":"dark"}\n' > "$TEST_HOME/.claude/settings.json"

HOME="$TEST_HOME" bash "$ROOT/scripts/claude/install.sh" >/dev/null
HOME="$TEST_HOME" bash "$ROOT/scripts/claude/install.sh" >/dev/null

SETTINGS="$TEST_HOME/.claude/settings.json"
jq -e '.outputStyle == "Concise"' "$SETTINGS" >/dev/null \
  || fail "outputStyle not seeded as Concise"
jq -e '.theme == "dark"' "$SETTINGS" >/dev/null \
  || fail "installer clobbered an unrelated setting"
# statusLine is dotai-owned and must still be forced, so the //= above cannot be
# copy-pasted onto keys that need overwriting.
jq -e '.statusLine.command | test("statusline\\.sh$")' "$SETTINGS" >/dev/null \
  || fail "statusLine registration regressed"

# A user's own choice must survive a re-install — this is the whole point of //=.
jq '.outputStyle = "Explanatory"' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
HOME="$TEST_HOME" bash "$ROOT/scripts/claude/install.sh" >/dev/null
jq -e '.outputStyle == "Explanatory"' "$SETTINGS" >/dev/null \
  || fail "re-install overwrote a deliberately changed outputStyle"

# Fresh HOME with no settings file at all.
FRESH=$(mktemp -d)
HOME="$FRESH" bash "$ROOT/scripts/claude/install.sh" >/dev/null
jq -e '.outputStyle == "Concise"' "$FRESH/.claude/settings.json" >/dev/null \
  || fail "outputStyle missing on a fresh install"
rm -rf "$FRESH"

# ── Codex: model_verbosity ───────────────────────────────────────────────────

CODEX_HOME=$(mktemp -d)
mkdir -p "$CODEX_HOME/.codex"
# Shaped like the real file: top-level keys, then tables. If the key is appended
# at EOF it ends up inside [projects."…"] and Codex never sees it.
printf 'model = "gpt-5.6-luna"\nmodel_reasoning_effort = "medium"\n\n[projects."/tmp/x"]\ntrust_level = "trusted"\n' \
  > "$CODEX_HOME/.codex/config.toml"

HOME="$CODEX_HOME" bash "$ROOT/scripts/codex/install.sh" >/dev/null
HOME="$CODEX_HOME" bash "$ROOT/scripts/codex/install.sh" >/dev/null

CONFIG="$CODEX_HOME/.codex/config.toml"
grep -Fqx 'model_verbosity = "medium"' "$CONFIG" \
  || fail "model_verbosity not written"
[ "$(grep -c '^model_verbosity' "$CONFIG")" -eq 1 ] \
  || fail "model_verbosity duplicated — installer is not idempotent"
grep -Fqx 'model_reasoning_effort = "medium"' "$CONFIG" \
  || fail "installer clobbered an existing top-level key"

# THE assertion this file exists for: the key must sit above the first [table]
# header, or TOML scopes it into that table and it is silently dead.
VERB_LINE=$(grep -n '^model_verbosity' "$CONFIG" | head -1 | cut -d: -f1)
TABLE_LINE=$(grep -n '^[[:space:]]*\[' "$CONFIG" | head -1 | cut -d: -f1)
[ -n "$TABLE_LINE" ] || fail "test fixture lost its table headers"
[ "$VERB_LINE" -lt "$TABLE_LINE" ] \
  || fail "model_verbosity (line $VERB_LINE) is below the first table header (line $TABLE_LINE) — TOML reads it as a member of that table"

# A tuned value must survive a re-install.
sed -i '' 's/^model_verbosity = "medium"/model_verbosity = "low"/' "$CONFIG" 2>/dev/null \
  || sed -i 's/^model_verbosity = "medium"/model_verbosity = "low"/' "$CONFIG"
HOME="$CODEX_HOME" bash "$ROOT/scripts/codex/install.sh" >/dev/null
grep -Fqx 'model_verbosity = "low"' "$CONFIG" \
  || fail "re-install overwrote a deliberately tuned model_verbosity"
rm -rf "$CODEX_HOME"

# A config.toml with no tables at all must still get a valid top-level key.
BARE=$(mktemp -d)
mkdir -p "$BARE/.codex"
printf 'model = "gpt-5.6-luna"\n' > "$BARE/.codex/config.toml"
HOME="$BARE" bash "$ROOT/scripts/codex/install.sh" >/dev/null
grep -Fqx 'model_verbosity = "medium"' "$BARE/.codex/config.toml" \
  || fail "model_verbosity missing when config.toml has no tables"
rm -rf "$BARE"

# ── agy: the prose half ──────────────────────────────────────────────────────
#
# agy has no native verbosity setting (probed: ~/.gemini/config/config.json holds
# only userSettings), so GLOBAL_RULES.md is the only lever and the one place the
# rule can regress unnoticed.

RULES="$ROOT/GLOBAL_RULES.md"
grep -qi "no preamble" "$RULES" || fail "GLOBAL_RULES lost the no-preamble rule"
# The carve-out is load-bearing: without it "be brief" reads as licence to
# truncate an error report or skip a destructive-action confirmation.
grep -q 'error reports, security warnings' "$RULES" \
  || fail "GLOBAL_RULES lost the full-length carve-out for errors/warnings"
grep -q 'explain' "$RULES" \
  || fail "GLOBAL_RULES lost the carve-out for explicit explanation requests"

# The agy installer must actually ship it — the rule is worthless if it never
# reaches ~/.gemini/config/AGENTS.md.
grep -q 'GLOBAL_RULES.md' "$ROOT/scripts/agy/install.sh" \
  || fail "agy installer no longer distributes GLOBAL_RULES.md"

echo 'OUTPUT_VERBOSITY_TEST_STATUS=PASS'
