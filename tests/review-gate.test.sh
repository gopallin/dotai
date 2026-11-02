#!/usr/bin/env bash

# review-gate replaced /ship's Step 2.5 self-review — the agent that wrote the
# change grading it — with a Claude Code AGENT hook the harness spawns at
# `git commit`. It reads the diff with its own tools, so the author decides
# neither whether it runs nor what it sees.
#
# These tests pin what makes that true, not merely that a file exists:
#   - the installer registers it as an agent hook, scoped by `if` to git commit
#   - the reviewer's diff commands are exactly the allowed ones; it runs in
#     dont-ask mode, so any drift is refused and it fails closed on EVERY commit
#     (observed in a probe: `git -C <dir> diff` was refused, a clean diff blocked)
#   - re-installing over its own entry works (an agent hook has no .command,
#     and `null | test()` once aborted the whole jq merge)
#   - Codex/agy get no copy (no agent hooks there), and /ship keeps the
#     self-review only for them
#
# Live behaviour (deny on a planted bug, `if` skipping `git status`, compound
# `cd . && git commit` matched) was probed by hand on 2.1.308/2.1.309; it needs
# a model call, so it is not re-run here.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_SRC="$ROOT/hooks/claude/review-gate.prompt.md"
SHIP="$ROOT/skills/ship/SKILL.md"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "❌ $1" >&2; }

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# A user's own allow rule and an unrelated PreToolUse hook must survive.
mkdir -p "$TEST_HOME/.claude"
cat > "$TEST_HOME/.claude/settings.json" <<'EOF'
{"permissions":{"allow":["Bash(npm test)"]},
 "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo mine"}]}]}}
EOF

# Twice: the second run merges over a settings.json that already holds the
# agent hook — the case that used to abort jq.
for run in 1 2; do
  HOME="$TEST_HOME" bash "$ROOT/scripts/claude/install.sh" >/dev/null 2>&1 \
    || bad "scripts/claude/install.sh failed (run $run)"
done
S="$TEST_HOME/.claude/settings.json"

jq -e . "$S" >/dev/null 2>&1 && ok || bad "settings.json is not valid JSON after install"

# ── Registration ──────────────────────────────────────────────────────────────

GATES=$(jq '[.hooks.PreToolUse[]?.hooks[]? | select((.prompt // "") | test("DOTAI-REVIEW-GATE"))]' "$S")
[ "$(jq length <<< "$GATES")" = "1" ] && ok \
  || bad "expected exactly one review-gate entry after two installs, got $(jq length <<< "$GATES")"

[ "$(jq -r '.[0].type' <<< "$GATES")" = "agent" ] && ok \
  || bad "review-gate must be an agent hook — a command hook cannot review, and a prompt hook sees only the author's transcript"

[ "$(jq -r '.[0].if' <<< "$GATES")" = "Bash(git commit *)" ] && ok \
  || bad "review-gate must be scoped with if: Bash(git commit *) — without it every Bash call spawns a reviewer"

jq -e '.hooks.PreToolUse[] | select(.hooks[0].prompt? // "" | test("DOTAI-REVIEW-GATE")) | .matcher == "Bash"' "$S" >/dev/null \
  && ok || bad "review-gate matcher must be Bash"

[ -n "$(jq -r '.[0].model // empty' <<< "$GATES")" ] && ok \
  || bad "review-gate has no model — it would fall back to Haiku"

# Not a Stop hook: there, a refusal loops the session (observed 9× in a probe).
if jq -e '.hooks.Stop[]?.hooks[]? | select((.prompt // "") | test("DOTAI-REVIEW-GATE"))' "$S" >/dev/null 2>&1; then
  bad "review-gate registered on Stop — it belongs on PreToolUse(git commit)"
else
  ok
fi

PROMPT=$(jq -r '.[0].prompt' <<< "$GATES")
grep -q '{{HOME}}' <<< "$PROMPT" && bad "{{HOME}} left unsubstituted — the reviewer cannot Read the protocol" || ok
grep -Fq "$TEST_HOME/.claude/skills/reviewer-rules/SKILL.md" <<< "$PROMPT" && ok \
  || bad "prompt does not point at the installed reviewer-rules skill"
grep -Fq '$ARGUMENTS' <<< "$PROMPT" && ok \
  || bad "prompt lacks \$ARGUMENTS — the reviewer would not know which commit or repo"

# ── Independence and fail-closed are in the prompt ────────────────────────────

grep -q 'transcript_path' "$PROMPT_SRC" && grep -qi 'never read' "$PROMPT_SRC" && ok \
  || bad "prompt no longer forbids reading the author's transcript"
grep -qi 'could not obtain the diff' "$PROMPT_SRC" && grep -q 'ok false' "$PROMPT_SRC" && ok \
  || bad "prompt no longer fails closed when the diff cannot be read"

# ── The reviewer's commands == the allow rules ────────────────────────────────
# Drift in either direction breaks it: a prompt command with no rule is refused
# (fail closed on every commit); a rule with no prompt command is dead weight
# granted to the main agent too.

PROMPT_CMDS=$(grep -oE '^- `git diff [^`]+`' "$PROMPT_SRC" | sed -E 's/^- `(.*)`$/\1/' | sort)
RULE_CMDS=$(jq -r '.permissions.allow[] | select(startswith("Bash(git diff")) | sub("^Bash\\(";"") | sub("\\)$";"")' "$S" | sort)
[ -n "$PROMPT_CMDS" ] && [ "$PROMPT_CMDS" = "$RULE_CMDS" ] && ok \
  || bad "prompt diff commands and allow rules differ:
  prompt: $(tr '\n' '|' <<< "$PROMPT_CMDS")
  rules:  $(tr '\n' '|' <<< "$RULE_CMDS")"

# Each form also needs its `git -C <dir>` twin: a commit into a sibling repo is
# reviewed there, and `cd <dir> && git diff` was refused in the probe.
while IFS= read -r c; do
  [ -n "$c" ] || continue
  jq -e --arg r "Bash(git -C * ${c#git })" '.permissions.allow | index($r)' "$S" >/dev/null && ok \
    || bad "no 'git -C *' allow rule for: $c — sibling-repo commits would fail closed"
done <<< "$PROMPT_CMDS"
grep -q 'git -C' "$PROMPT_SRC" && ok || bad "prompt no longer tells the reviewer to use git -C for another repo"

jq -e '.permissions.allow | index("Read(~/.claude/skills/reviewer-rules/**)")' "$S" >/dev/null && ok \
  || bad "no Read rule for the reviewer-rules skill — it lives outside every project and the Read is refused"

# …and NOTHING else. These rules land in the user's global settings, so they
# widen the main agent's permissions too. The checks above only look for the
# expected rules, so an extra `Bash(*)` slipped past them. review-gate itself
# caught that in a live dry run on 2026-10-31, and this check pins it.
EXPECTED=$( { while IFS= read -r c; do
                [ -n "$c" ] || continue
                printf 'Bash(%s)\nBash(git -C * %s)\n' "$c" "${c#git }"
              done <<< "$PROMPT_CMDS"
              echo 'Read(~/.claude/skills/reviewer-rules/**)'; } | sort -u)
ADDED=$(jq -r '.permissions.allow[] | select(. != "Bash(npm test)")' "$S" | sort -u)
EXTRA=$(comm -13 <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$ADDED"))
[ -z "$EXTRA" ] && ok \
  || bad "installer grants allow rules the reviewer does not need (they apply to the main agent too): $(tr '\n' ' ' <<< "$EXTRA")"

for c in $( (jq -r '.permissions.allow[] | select(test("^Bash\\(git (-C \\* )?diff"))' "$S" | tr ' ' '_') ); do
  grep -q -- '--no-ext-diff' <<< "$c" && ok \
    || bad "allow rule $c lacks --no-ext-diff — a repo diff driver could execute"
done

[ "$(jq '[.permissions.allow[]] | length' "$S")" = "$(jq '[.permissions.allow[]] | unique | length' "$S")" ] && ok \
  || bad "permissions.allow has duplicates after two installs"

# ── The user's own config survives ────────────────────────────────────────────

jq -e '.permissions.allow | index("Bash(npm test)")' "$S" >/dev/null && ok \
  || bad "install dropped the user's own allow rule"
jq -e '[.hooks.PreToolUse[].hooks[]? | select(.command? == "echo mine")] | length == 1' "$S" >/dev/null && ok \
  || bad "install dropped or duplicated the user's own PreToolUse hook"

# ── Claude only ───────────────────────────────────────────────────────────────

for f in "$ROOT/scripts/codex/install.sh" "$ROOT/scripts/agy/install.sh" "$ROOT"/hooks/agy/hooks.json; do
  if grep -q 'review-gate\|DOTAI-REVIEW-GATE' "$f"; then
    bad "$(basename "$(dirname "$f")")/$(basename "$f") references review-gate — Codex/agy have no agent hooks, a copy would be inert"
  else
    ok
  fi
done

# ── /ship no longer self-reviews on Claude Code, still does on Codex/agy ──────

grep -q 'Claude Code: skip this step' "$SHIP" && ok \
  || bad "/ship Step 2.5 no longer tells Claude Code to skip the self-review"
grep -q 'Codex / agy: run it here' "$SHIP" && ok \
  || bad "/ship dropped the self-review for Codex/agy — they would have no review at all"
grep -qi 'self-review' "$SHIP" && ok \
  || bad "/ship must label the Codex/agy review a self-review, not an independent one"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
