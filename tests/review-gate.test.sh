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

# A user's own allow rule and an unrelated PreToolUse hook must survive. The two
# `git -C *` rules are what an earlier install wrote; they must be pruned.
mkdir -p "$TEST_HOME/.claude"
cat > "$TEST_HOME/.claude/settings.json" <<'EOF'
{"permissions":{"allow":["Bash(npm test)",
   "Bash(git -C * diff --cached --no-color --no-ext-diff)",
   "Bash(git -C * diff HEAD --no-color --no-ext-diff)"]},
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

# A commit into a sibling repo is reviewed there, and `cd <dir> && git diff` was
# refused in the probe — so the prompt names review-diff.sh and a rule allows it.
WRAPPER="$TEST_HOME/.claude/hooks/claude/review-diff.sh"
WRAPPER_RULE="Bash(bash $WRAPPER *)"
jq -e --arg r "$WRAPPER_RULE" '.permissions.allow | index($r)' "$S" >/dev/null && ok \
  || bad "no allow rule for review-diff.sh — sibling-repo commits would fail closed"
[ -x "$WRAPPER" ] && ok || bad "installer did not install an executable review-diff.sh"
grep -Fq "bash $TEST_HOME/.claude/hooks/claude/review-diff.sh <absolute dir> cached" <<< "$PROMPT" && ok \
  || bad "prompt does not tell the reviewer the exact review-diff.sh command its rule allows"

# The reason for the wrapper: a `*` with more command after it matches any
# inserted option (`git -C . -c core.fsmonitor=<cmd> diff …` ran <cmd>
# unprompted), and Claude Code 2.1.309 warns on it. Only a trailing `*` is safe,
# and only in front of a script that validates what lands there.
MID_STAR=$(jq -r '.permissions.allow[] | select(test("^Bash\\(.*\\*.*[^ *].*\\)$") and (test("^Bash\\(.*\\*\\)$") | not))' "$S")
[ -z "$MID_STAR" ] && ok \
  || bad "Bash allow rule with a mid-command * (approves any option inserted there): $MID_STAR"
jq -e '.permissions.allow | map(select(startswith("Bash(git -C"))) | length == 0' "$S" >/dev/null && ok \
  || bad "re-install did not prune the old Bash(git -C * diff …) rules"

# The wrapper is what the trailing `*` trusts, so it must refuse anything that
# is not <absolute dir> cached|head — an option in either slot above all.
REPO="$TEST_HOME/repo"
git init -q "$REPO"; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
printf 'a\n' > "$REPO/f"; git -C "$REPO" add f; git -C "$REPO" commit -qm init
printf 'b\n' > "$REPO/f"; git -C "$REPO" add f; printf 'c\n' > "$REPO/f"
OUT=$(bash "$WRAPPER" "$REPO" cached 2>&1)
grep -q '^+b$' <<< "$OUT" && ! grep -q '^+c$' <<< "$OUT" && ok \
  || bad "review-diff.sh cached did not show exactly the staged change: $OUT"
OUT=$(bash "$WRAPPER" "$REPO" head 2>&1)
grep -q '^+c$' <<< "$OUT" && ok || bad "review-diff.sh head did not include the unstaged change: $OUT"
for args in "-c core.fsmonitor=touch$TEST_HOME/pwned cached" "relative/dir cached" "$REPO --output=$TEST_HOME/pwned" \
            "$REPO cached extra" "$REPO" "$TEST_HOME/no-such-dir cached"; do
  # shellcheck disable=SC2086 # word-splitting into separate arguments is the point
  if bash "$WRAPPER" $args >/dev/null 2>&1; then
    bad "review-diff.sh accepted: $args"
  else
    ok
  fi
done
[ ! -e "$TEST_HOME/pwned" ] && ok || bad "review-diff.sh let an injected option run or write"

jq -e '.permissions.allow | index("Read(~/.claude/skills/reviewer-rules/**)")' "$S" >/dev/null && ok \
  || bad "no Read rule for the reviewer-rules skill — it lives outside every project and the Read is refused"

# …and NOTHING else. These rules land in the user's global settings, so they
# widen the main agent's permissions too. The checks above only look for the
# expected rules, so an extra `Bash(*)` slipped past them. review-gate itself
# caught that in a live dry run on 2026-10-31, and this check pins it.
EXPECTED=$( { while IFS= read -r c; do
                [ -n "$c" ] || continue
                printf 'Bash(%s)\n' "$c"
              done <<< "$PROMPT_CMDS"
              echo "$WRAPPER_RULE"
              echo 'Read(~/.claude/skills/reviewer-rules/**)'; } | sort -u)
ADDED=$(jq -r '.permissions.allow[] | select(. != "Bash(npm test)")' "$S" | sort -u)
EXTRA=$(comm -13 <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$ADDED"))
[ -z "$EXTRA" ] && ok \
  || bad "installer grants allow rules the reviewer does not need (they apply to the main agent too): $(tr '\n' ' ' <<< "$EXTRA")"

for c in $( (jq -r '.permissions.allow[] | select(test("^Bash\\(git diff"))' "$S" | tr ' ' '_') ); do
  grep -q -- '--no-ext-diff' <<< "$c" && ok \
    || bad "allow rule $c lacks --no-ext-diff — a repo diff driver could execute"
done
grep -q -- '--no-ext-diff' "$ROOT/hooks/claude/review-diff.sh" && ok \
  || bad "review-diff.sh lacks --no-ext-diff — a repo diff driver could execute"

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
