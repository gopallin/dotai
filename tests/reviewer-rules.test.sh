#!/usr/bin/env bash

# The L1/L2/L3 checklist used to be inlined in BOTH ground and ship, and the two
# copies had already drifted. It also named one specific project's tables and lock
# keys, while dotai skills install globally — so those rules loaded in unrelated
# repos. These tests pin the fix: one stack-agnostic source, referenced by both,
# with project specifics kept out of anything that gets installed.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GROUND="$ROOT/skills/ground/SKILL.md"
SHIP="$ROOT/skills/ship/SKILL.md"
PROTOCOL="$ROOT/skills/reviewer-rules/SKILL.md"
EXAMPLE="$ROOT/docs/reviewer-rules.example.md"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "❌ $1" >&2; }

# Assets that belong to exactly one project and must not ship globally.
PROJECT_SPECIFIC='shipments|b2b_batch_items|check_capacity|transitionTo|getRedisLock|picking_priority|stock\.usage'

# ── Single source exists and is stack-agnostic ────────────────────────────────

[ -f "$PROTOCOL" ] && ok || bad "missing skills/reviewer-rules/SKILL.md (the single source)"

if grep -qE "$PROJECT_SPECIFIC" "$PROTOCOL" 2>/dev/null; then
  bad "the reviewer-rules skill names project-specific assets — it must stay stack-agnostic"
else
  ok
fi

for level in L1 L2 L3; do
  grep -q "$level" "$PROTOCOL" 2>/dev/null && ok || bad "protocol does not define $level"
done

# Discovery must be documented, or the skills have no way to find project rules.
grep -q 'reviewer-rules.md' "$PROTOCOL" 2>/dev/null \
  && grep -qi 'CLAUDE.md' "$PROTOCOL" 2>/dev/null && ok \
  || bad "protocol does not document where project rules are discovered from"

# Frontmatter is what makes it discoverable as a skill on all three CLIs.
grep -Fqx 'name: reviewer-rules' "$PROTOCOL" && ok \
  || bad "reviewer-rules SKILL.md has no 'name: reviewer-rules' frontmatter"

# ── Both skills reference it, neither inlines a copy ─────────────────────────

for f in "$GROUND" "$SHIP"; do
  name=$(basename "$(dirname "$f")")
  grep -q 'reviewer-rules' "$f" && ok \
    || bad "$name does not reference the reviewer-rules skill"

  # A hardcoded ~/.claude path would be wrong on Codex (no rules/ mechanism) and agy.
  if grep -q 'claude/rules/' "$f"; then
    bad "$name hardcodes a ~/.claude/rules path — wrong on Codex and agy"
  else
    ok
  fi

  if grep -qE "$PROJECT_SPECIFIC" "$f"; then
    bad "$name still inlines project-specific reviewer rules"
  else
    ok
  fi
done

# ── Nothing installed globally carries project specifics ─────────────────────
# Everything under skills/ and rules/ is copied to ~/.claude, ~/.codex and
# ~/.gemini/config, so a project's table names there load in every other project.

while read -r f; do
  if grep -qE "$PROJECT_SPECIFIC" "$f"; then
    bad "globally-installed $f carries project-specific rules"
  fi
done < <(find "$ROOT/skills" "$ROOT/rules" -name '*.md')
ok   # reaching here means the sweep found nothing

# The example template must exist (so the rules were preserved, not deleted) and
# must NOT be installed — docs/ is not copied by any installer.
[ -f "$EXAMPLE" ] && ok || bad "docs/reviewer-rules.example.md missing — project rules were dropped, not relocated"
grep -qE "$PROJECT_SPECIFIC" "$EXAMPLE" 2>/dev/null && ok \
  || bad "example template does not actually contain the preserved project rules"
if grep -rn 'docs/' "$ROOT/scripts"/*/install.sh 2>/dev/null | grep -qv '^\s*#'; then
  bad "an installer copies docs/ — the example template would become global again"
else
  ok
fi

# ── ground has a git-readiness step ──────────────────────────────────────────

grep -q 'git rev-parse --abbrev-ref HEAD' "$GROUND" && ok \
  || bad "ground has no branch check (global protocol step 3)"
grep -q 'git status --short' "$GROUND" && ok \
  || bad "ground has no working-tree cleanliness check"
grep -q 'git fetch origin' "$GROUND" && ok \
  || bad "ground does not tell you to fetch before grounding on someone's branch"

# It must come before the reference-reading step, or it is not the cheapest-first
# gate it claims to be.
STEP0=$(grep -n '^### Step 0' "$GROUND" | head -1 | cut -d: -f1)
STEP1=$(grep -n '^### Step 1' "$GROUND" | head -1 | cut -d: -f1)
if [ -n "$STEP0" ] && [ -n "$STEP1" ] && [ "$STEP0" -lt "$STEP1" ]; then ok; else
  bad "ground's git-readiness step does not precede Step 1"
fi

# ── The installers must ship the protocol ────────────────────────────────────

# No installer change is needed: skills/ is copied wholesale as <name>/SKILL.md, so
# the protocol ships with every CLI automatically. Assert that end state rather than
# a grep for a filename, and assert the stale "path-filtered" claim is gone — nothing
# ever filtered rules by path, and believing otherwise is what let project-specific
# rules sit in a globally-loaded file.
for cli in claude codex agy; do
  if grep -q 'path-filtered' "$ROOT/scripts/$cli/install.sh" 2>/dev/null; then
    bad "$cli installer still claims rules are path-filtered — no such mechanism exists"
  else
    ok
  fi
done

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
