#!/usr/bin/env bash

# /map charts an effort too big for one session as decision tickets, and hands off
# to /plan once the route is clear. The pieces span three files — /map writes the
# map, /plan --from-map reads it, /next-ticket implements what /plan slices — so the
# failure mode is a contract that drifts: /plan looking for a filename /map does not
# write, or decision tickets leaking back into the implementation layer.
#
# The other thing pinned here is the set of constraints that exist BECAUSE of
# documented failures in the skill this is modelled on (mattpocock/skills wayfinder):
# agents writing production code mid-map, self-granting that licence in a file they
# own, mis-typing `task` as an implementation step, and charting 27 tickets of which
# the last 14 rest on assumptions the first 13 invalidate.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP="$ROOT/commands/map.md"
PLAN="$ROOT/commands/plan.md"
NEXT="$ROOT/commands/next-ticket.md"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "❌ $1" >&2; }

# Match against the raw file first (so ^-anchored structural patterns work), then
# against a flattened copy with newlines squashed and bold markers stripped. Prose in
# these files is hard-wrapped at 80 columns, so a phrase that reads as one sentence is
# routinely split across two lines with a `**` in the middle — matching only the raw
# file silently turns those assertions into "no such text", which passes for the wrong
# reason on deny() and fails for the wrong reason on want().
has()  { grep -qi -e "$2" "$1" || tr '\n' ' ' < "$1" | tr -s ' ' | tr -d '*' | grep -qi -e "$2"; }
want() { has "$1" "$2" && ok || bad "$3"; }
deny() { has "$1" "$2" && bad "$3" || ok; }

[ -f "$MAP" ] && ok || { bad "commands/map.md missing"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

# ── Discoverable on all three CLIs ───────────────────────────────────────────
# agy injects `name:` only when absent; both keys present is what every CLI needs.

grep -Fqx 'name: map' "$MAP" && ok || bad "map.md frontmatter has no 'name: map'"
grep -q '^description: ' "$MAP" && ok || bad "map.md frontmatter has no description"

# ── Both invocation modes ────────────────────────────────────────────────────

want "$MAP" '^## Mode A: Chart the Map' "map.md has no charting mode"
want "$MAP" '^## Mode B: Work the Map' "map.md has no work-the-map mode"

# ── Plan, don't do ───────────────────────────────────────────────────────────
# The most-reported wayfinder failure is an agent writing production code mid-map.

want "$MAP" 'plan, don.t do' "map.md does not state the plan-don't-do default"
want "$MAP" 'must read as a question' \
  "map.md does not require open tickets to read as questions — 'build the X' tickets slip in"

# Matt's own documented hole: the Notes section can override plan-don't-do, and the
# agent writes the Notes. A constraint whose exemption is self-writable is not one.
want "$MAP" 'cannot grant execution licence' \
  "map.md lets ## Notes grant execution licence — the agent can then authorise itself"
want "$MAP" 'only the user can' \
  "map.md does not reserve execution licence to the user"

# ── The four types, and the HITL/AFK line ────────────────────────────────────

for t in grilling prototype research task; do
  grep -q "^| \`$t\` |" "$MAP" && ok || bad "map.md's ticket-type table does not define '$t'"
done

want "$MAP" 'HITL' "map.md does not distinguish human-in-the-loop tickets"
want "$MAP" 'AFK' "map.md does not distinguish agent-driven tickets"
want "$MAP" 'standing in for the user' \
  "map.md does not forbid the agent answering a HITL ticket for the user"

# `task` is the type that goes wrong most often: read as an implementation step.
want "$MAP" 'unblocking a decision' \
  "map.md does not scope the task type to unblocking a decision"
want "$MAP" 'mis-typed' "map.md gives no tell for a mis-typed task ticket"

# Prototype selection is the user's; an agent choosing for them is a reported bug.
want "$MAP" 'never choose for them' \
  "map.md does not reserve the prototype choice to the user"
want "$MAP" 'throwaway' "map.md does not mark prototype output as throwaway"

# research is the documented exception to one-per-session; both halves must be stated.
want "$MAP" 'one ticket per session' "map.md does not cap a session at one ticket"
want "$MAP" 'exception to one-ticket-per-session' \
  "map.md does not exempt research from the one-ticket-per-session rule"
want "$MAP" 'in parallel, and non-blocking' \
  "map.md does not fire research sub-agents in parallel without blocking the frontier"

# ── Fog of war ───────────────────────────────────────────────────────────────

want "$MAP" '^## Fog of War' "map.md has no fog-of-war section"
want "$MAP" 'Not Yet Specified' "map.md's map format has no Not Yet Specified section"
# The test for fog-vs-ticket is stateable-now, not answerable-now. Getting this
# backwards turns every blocked question into fog and empties the frontier.
want "$MAP" 'state the question \*\*precisely now\*\*' \
  "map.md does not give the fog-vs-ticket test (stateable now, not answerable now)"
want "$MAP" 'do not pre-slice fog' "map.md does not forbid pre-slicing fog into tickets"
# A graduated patch living in both places is how the fog stops shrinking.
want "$MAP" 'delete those patches from Not Yet Specified' \
  "map.md does not clear graduated fog — Not Yet Specified would never shrink"

# ── Out of scope is not fog ──────────────────────────────────────────────────

want "$MAP" '^## Out of Scope\|Out Of Scope' "map.md has no out-of-scope section"
want "$MAP" 'never graduates' "map.md does not state that out-of-scope work never graduates"
want "$MAP" 'not go into Decisions So Far' \
  "map.md lets a scope boundary land in Decisions So Far — that records the route walked"

# ── Index, not store ─────────────────────────────────────────────────────────

want "$MAP" 'index, not a store' "map.md does not state the map is an index"
want "$MAP" 'Do not read every ticket file' \
  "map.md does not stop Mode B reading every ticket — the map exists to avoid that"

# ── The escape hatches in both directions ────────────────────────────────────

want "$MAP" 'you do not need a map' \
  "map.md does not stop when charting surfaces no fog"
want "$MAP" 'session count, not project size' \
  "map.md does not give the /plan-vs-/map discriminator"
# The anti-waterfall signal. A cap would be arbitrary; a signal is the honest form.
want "$MAP" 'destination is too big' \
  "map.md has no size signal — a 27-ticket map's tail rests on invalidated assumptions"

# ── Coverage: /plan's three blocks survive as a checklist ────────────────────
# Breadth-first grilling has no coverage guarantee of its own. This is the one thing
# dotai's /plan had that the skill being modelled does not.

want "$MAP" 'Coverage check before you stop' \
  "map.md's charting grill has no coverage check — breadth-first guarantees nothing"
want "$MAP" 'Business constraints' "map.md coverage check omits business constraints"
want "$MAP" 'Technical approaches' "map.md coverage check omits technical approaches"
want "$MAP" 'How it fails, and how you would know' \
  "map.md coverage check omits failure modes and how you would know"

# ── Facts vs decisions ───────────────────────────────────────────────────────

want "$MAP" 'never ask the user for something you could look up' \
  "map.md does not make fact-finding the agent's job"

# ── Deliberately no issue tracker ────────────────────────────────────────────
# Forge detection already lives in three places in this repo (git-push, ship,
# glab-guard) and is a known outstanding cleanup. A fourth consumer is not a fix.

for forge in 'glab' 'api\.github\.com' 'gh issue' 'PRIVATE-TOKEN'; do
  deny "$MAP" "$forge" "map.md couples to a forge ($forge) — dotai's map is local markdown"
done
want "$MAP" 'local markdown' "map.md does not state that the map is local markdown"

# ── Portable to non-code subjects ────────────────────────────────────────────
# Two things ever tied these commands to software: the branch-keyed filename and the
# wording of the three blocks. Both must stay unbound, or "grill me about a decision
# that isn't code" needs a repo and a feature branch to work at all.

want "$MAP" 'domain-agnostic' "map.md does not state the map works on non-code subjects"
want "$MAP" 'kebab-case slug' "map.md still requires a git branch to name its artifact"
deny "$MAP" 'map-{branch-name}' "map.md is still branch-keyed — it cannot run outside a repo"
want "$MAP" 'default to .~/\.claudedocs/' \
  "map.md does not keep a personal map out of the current repo"
want "$MAP" 'nothing downstream to slice' \
  "map.md invents an implementation phase for a non-code subject"
# Overhead honesty: a one-sitting question does not deserve a filing system.
want "$MAP" 'plain conversation beats a map' \
  "map.md does not say when a map is overkill for a non-code question"

want "$PLAN" 'plan key' "plan.md has no plan key — it is still branch-only"
deny "$PLAN" 'plan-{branch-name}' "plan.md is still branch-keyed"
want "$PLAN" 'does not have to be code' "plan.md still assumes the subject is software"
want "$PLAN" '^\*\*Code only\.\*\*' \
  "plan.md's ticket decomposition is not gated to code subjects"
want "$PLAN" 'Skip it entirely when' \
  "plan.md writes a CONTEXT.md glossary for a plan that is not about this repo"

# ── One interview shape, checked once at the end ─────────────────────────────
# /plan used to gate three fixed blocks in a fixed order, each with its own confirm
# step. Real design questions cross those boundaries — "cache it" is simultaneously an
# option, a constraint and a failure mode — so the sequence made you say one thought
# three times, and Block 1's questions got asked even when Block 2's answer would have
# made them moot. The topics were worth keeping; the running order was not.

grep -q '^## Step 1: The Grilling Loop' "$PLAN" && ok \
  || bad "plan.md has no single grilling loop — the gated blocks are back"
grep -q '^## Step 2: Coverage Check Before You Wrap' "$PLAN" && ok \
  || bad "plan.md has no coverage check — a free-running interview guarantees nothing"
want "$PLAN" 'This is a checklist, not a running order' \
  "plan.md does not say the coverage check is a checklist rather than a sequence"
want "$PLAN" 'one question at a time' \
  "plan.md dropped one-question-at-a-time — the user chose to keep that rhythm"
want "$PLAN" 'Provide a recommended answer' \
  "plan.md no longer attaches a recommended answer to each question"
want "$PLAN" 'Find facts yourself' \
  "plan.md does not make fact-finding the agent's job"
# The check exists precisely for the moment the agent believes it is finished.
want "$PLAN" 'is exactly when the gaps are invisible' \
  "plan.md lets the loop exit without running the coverage check"
# An unreached face is a question to ask, not a heading to fill in.
want "$PLAN" 'is a question, not a section to write' \
  "plan.md lets the agent fill an unreached coverage face itself"
want "$PLAN" 'do not reopen a face that was covered' \
  "plan.md does not stop the coverage check re-asking settled ground"

# Structure of the OUTPUT is still three sections — that is a reader's need, not an
# interview order. Losing the distinction is how the gated blocks come back.
want "$PLAN" 'that is not\s*the order the questions were asked in' \
  "plan.md no longer separates output structure from interview order"

# The three faces must be named identically in both commands. Bodies differ by design
# (in /map an unreached face becomes a ticket or fog); the names are the shared unit,
# and this is the assertion that keeps them from drifting apart.
for face in \
  'Constraints, and what success looks like' \
  'Options and their tradeoffs' \
  'How it fails, and how you would know'
do
  has "$PLAN" "$face" && has "$MAP" "$face" && ok \
    || bad "coverage face '$face' is not named identically in plan.md and map.md"
done

# Nothing may still refer to the retired blocks.
for stale in 'Block 1' 'Block 2' 'Block 3' 'three-block' 'three blocks'; do
  deny "$PLAN" "$stale" "plan.md still references '$stale' — a leftover from the gated blocks"
done

# ── Cross-file contract: /plan must look for what /map writes ────────────────
# This is the real drift risk: two files agreeing on a filename by coincidence.

grep -q 'map-{map-key}\.md' "$MAP" && ok \
  || bad "map.md does not name its own artifact as map-{map-key}.md"
grep -q 'map-{map-key}\.md' "$PLAN" && ok \
  || bad "plan.md looks for a different map filename than map.md writes"

want "$MAP" '/plan --from-map' "map.md does not hand a cleared map off to /plan"
want "$PLAN" '\-\-from-map' "plan.md has no --from-map mode to receive a cleared map"
want "$PLAN" '^## Step 3: .--from-map.' "plan.md has no --from-map collapse step"
want "$PLAN" 'skip Steps 1–3' \
  "plan.md re-grills a collapsed map — the grilling already happened inside it"

# A spec written over open decisions defeats the map.
want "$PLAN" 'still .open.\/.claimed., or' \
  "plan.md does not refuse to collapse a map that still has open tickets"
# Every claim traceable, and no new decisions invented during the collapse.
want "$PLAN" 'Do not introduce a decision that no ticket made' \
  "plan.md's collapse may invent decisions the map never made"
want "$PLAN" 'Collapse, do not concatenate' \
  "plan.md's --from-map does not distinguish collapsing from concatenating"

# --from-map with no map must stop, not silently become a fresh planning session.
want "$PLAN" 'Do not fall back to' \
  "plan.md silently falls back to a fresh session when --from-map finds no map"

# ── /plan routes to /map when there is too much fog ──────────────────────────

want "$PLAN" 'this is a map, not a plan' \
  "plan.md has no rule routing an over-foggy session to /map"
want "$PLAN" 'three or more questions have come back undecided' \
  "plan.md gives no threshold for bailing out to /map"
want "$PLAN" 'do not invent a placeholder' \
  "plan.md still lets an undecided answer be filled with a guess"
# The user overriding the recommendation is their call, not a reason to stall.
want "$PLAN" 'that is their call' \
  "plan.md turns the /map recommendation into a block"

# ── Layer separation: decision tickets stay out of the implementation layer ──
# Mixing them is what makes a `task` ticket read as a build step.

for t in grilling prototype 'Not Yet Specified' 'HITL'; do
  deny "$NEXT" "$t" "next-ticket.md carries decision-ticket concept '$t' — that belongs to /map"
done
want "$NEXT" 'tracer-bullet\|Implement the slice' \
  "next-ticket.md is no longer about implementing slices"

# ── Installer parity (L1): a command must ship on all three CLIs ─────────────

for cli in claude codex agy; do
  grep -q 'map' "$ROOT/scripts/$cli/install.sh" && ok \
    || bad "$cli installer does not install /map"
done
# agy has no commands type — it ships them as skills, so map must be in that loop.
grep -q 'for cmd in .*\bmap\b' "$ROOT/scripts/agy/install.sh" && ok \
  || bad "agy installer does not ship /map as a skill (agy has no commands type)"
grep -q 'for cmd in .*\bmap\b' "$ROOT/scripts/codex/install.sh" && ok \
  || bad "codex installer does not ship /map as a prompt"
grep -q 'commands/map\.md' "$ROOT/scripts/claude/install.sh" && ok \
  || bad "claude installer does not copy commands/map.md"

# ── Documented in the structure tree ─────────────────────────────────────────

grep -q 'map\.md' "$ROOT/GLOBAL_RULES.md" || echo "warning: map.md not found in GLOBAL_RULES.md" >&2

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
