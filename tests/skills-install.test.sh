#!/usr/bin/env bash

# Verifies all three installers lay skills out as <root>/<name>/SKILL.md.
# All three CLIs share that convention; a flat <root>/<name>.md is never discovered.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Derived from the repo so a newly added skill is covered without editing this test.
SKILLS=()
for d in "$ROOT/skills"/*/; do
  [ -f "$d/SKILL.md" ] || continue
  SKILLS+=("$(basename "$d")")
done
[ "${#SKILLS[@]}" -gt 0 ] || { echo "❌ no skills found in $ROOT/skills" >&2; exit 1; }

# Pre-seed the stale flat layout a previous dotai version installed, so the
# cleanup path is exercised rather than assumed.
mkdir -p "$TEST_HOME/.claude/skills" "$TEST_HOME/.gemini/skills"
touch "$TEST_HOME/.claude/skills/ship.md" "$TEST_HOME/.gemini/skills/ship.md"

mkdir -p "$TEST_HOME/.codex"
printf '[tui]\nanimations = false\n' > "$TEST_HOME/.codex/config.toml"

# Both installers merge into a settings file the CLI itself normally creates.
mkdir -p "$TEST_HOME/.gemini/antigravity-cli"
echo '{}' > "$TEST_HOME/.gemini/antigravity-cli/settings.json"

# Run each installer twice — idempotency.
for cli in claude codex agy; do
  HOME="$TEST_HOME" bash "$ROOT/scripts/$cli/install.sh" >/dev/null
  HOME="$TEST_HOME" bash "$ROOT/scripts/$cli/install.sh" >/dev/null
done

# agy has no "commands" customization type — dotai's slash commands ship there as
# skills, so its skills root legitimately holds more entries than the other CLIs.
AGY_COMMANDS=(precommit plan next-ticket handoff prompt)

assert_skills_root() {
  local label=$1 root=$2; shift 2
  local expected=("$@")
  for s in "${expected[@]}"; do
    [ -f "$root/$s/SKILL.md" ] || {
      echo "❌ $label: missing $root/$s/SKILL.md" >&2
      exit 1
    }
    grep -Fqx "name: $s" "$root/$s/SKILL.md" || {
      echo "❌ $label: $s/SKILL.md frontmatter has no 'name: $s'" >&2
      exit 1
    }
  done

  local count
  count=$(find "$root" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
  [ "$count" = "${#expected[@]}" ] || {
    echo "❌ $label: expected ${#expected[@]} skills in $root, found $count" >&2
    exit 1
  }

  # A leftover flat .md shadows nothing but rots — installer must clean it.
  local stale
  stale=$(find "$root" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
  [ "$stale" = 0 ] || {
    echo "❌ $label: $stale stale flat .md file(s) left in $root" >&2
    exit 1
  }
}

assert_skills_root claude "$TEST_HOME/.claude/skills" "${SKILLS[@]}"
assert_skills_root codex  "$TEST_HOME/.codex/skills"  "${SKILLS[@]}"
# agy's global customization root is ~/.gemini/config/, not ~/.gemini/.
assert_skills_root agy    "$TEST_HOME/.gemini/config/skills" "${SKILLS[@]}" "${AGY_COMMANDS[@]}"

for legacy in "$TEST_HOME/.gemini/skills" "$TEST_HOME/.gemini/commands"; do
  [ ! -e "$legacy" ] || {
    echo "❌ agy: legacy $legacy still present (agy never reads it)" >&2
    exit 1
  }
done

# The commands-as-skills need a name in frontmatter; precommit.md only carries a
# description, so the installer must inject one or agy will not register it.
grep -Fqx 'name: precommit' "$TEST_HOME/.gemini/config/skills/precommit/SKILL.md" || {
  echo "❌ agy: precommit SKILL.md is missing the injected 'name: precommit'" >&2
  exit 1
}
[ -x "$TEST_HOME/.gemini/config/skills/precommit/precommit.sh" ] || {
  echo "❌ agy: precommit.sh helper not installed beside its skill" >&2
  exit 1
}

# The installers print a summary of what they installed. It used to be a hardcoded
# list and had already gone stale (it omitted reviewer-rules), so assert the summary
# names every skill actually shipped — a doc that lies about coverage is worse than
# no doc, because it reads as verification.
for cli in claude codex agy; do
  summary=$(HOME="$TEST_HOME" bash "$ROOT/scripts/$cli/install.sh" 2>/dev/null \
            | grep -E '^  skills/ ')
  for s in "${SKILLS[@]}"; do
    printf '%s' "$summary" | grep -Fq "$s" || {
      echo "❌ $cli install summary does not mention skill '$s': $summary" >&2
      exit 1
    }
  done
done

echo 'SKILLS_INSTALL_TEST_STATUS=PASS'
