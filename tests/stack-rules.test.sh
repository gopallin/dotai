#!/usr/bin/env bash

# stack-rules.sh replaces the always-loaded ~/.claude/rules/*.md with a
# SessionStart hook that emits ONLY the detected stack's rules. The bug it exists
# to prevent is silent over-inclusion: three stacks loading in every project, which
# is invisible because nothing errors — it just costs tokens forever.
#
# So the assertions are two-sided: the right file loads, AND the other two do not.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/hooks/claude/stack-rules.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "❌ $1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fake ~/.claude/dotai-rules with recognisable markers per stack.
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/dotai-rules"
for s in laravel vue node; do
  echo "MARKER-${s}" > "$FAKE_HOME/.claude/dotai-rules/$s.md"
done

# run <dir> → hook stdout, with HOME pointed at the fake tree.
run() {
  printf '%s' "$(jq -cn --arg d "$1" '{cwd:$d, source:"startup"}')" \
    | HOME="$FAKE_HOME" bash "$HOOK" 2>/dev/null
}

# expect_stack <label> <dir> <stack|none>
expect_stack() {
  local label=$1 dir=$2 want=$3 out
  out=$(run "$dir")
  if [ "$want" = "none" ]; then
    [ -z "$out" ] && ok || bad "$label: expected no output, got: $(printf '%s' "$out" | head -2)"
    return
  fi
  if ! printf '%s' "$out" | grep -q "MARKER-${want}"; then
    bad "$label: expected MARKER-${want}, got: $(printf '%s' "$out" | head -3)"
    return
  fi
  # The whole point: the other stacks must be absent.
  local other
  for other in laravel vue node; do
    [ "$other" = "$want" ] && continue
    if printf '%s' "$out" | grep -q "MARKER-${other}"; then
      bad "$label: leaked MARKER-${other} into a ${want} project"
      return
    fi
  done
  ok
}

# ── Laravel: artisan wins even when package.json is also present ──────────────
L="$TMP/laravel"; mkdir -p "$L"
touch "$L/artisan" "$L/package.json"
expect_stack "laravel via artisan" "$L" laravel

# ── Vue: package.json + vite.config.* ────────────────────────────────────────
V="$TMP/vue"; mkdir -p "$V"
touch "$V/package.json" "$V/vite.config.ts"
expect_stack "vue via vite.config.ts" "$V" vue

V2="$TMP/vue-js"; mkdir -p "$V2"
touch "$V2/package.json" "$V2/vite.config.js"
expect_stack "vue via vite.config.js" "$V2" vue

# ── Node: package.json alone ─────────────────────────────────────────────────
N="$TMP/node"; mkdir -p "$N"
touch "$N/package.json"
expect_stack "node via package.json" "$N" node

# ── No recognisable stack → silent ───────────────────────────────────────────
P="$TMP/plain"; mkdir -p "$P"
expect_stack "unknown stack stays silent" "$P" none

# ── A session opened in a SUBDIRECTORY must still detect the stack ────────────
# Without the repo-root walk this returns nothing, which is the silent-failure mode.
G="$TMP/gitrepo"; mkdir -p "$G/app/Services"
touch "$G/artisan"
git init -q "$G"
expect_stack "laravel detected from a subdirectory" "$G/app/Services" laravel

# A subdirectory of a NON-git project cannot be resolved to a root — staying
# silent is correct, and must not crash.
NG="$TMP/nogit/src"; mkdir -p "$NG"
touch "$TMP/nogit/package.json"
expect_stack "non-git subdirectory stays silent" "$NG" none

# ── No rules installed at all → exit 0, no output ────────────────────────────
# Feed stdin from a FILE, not a pipe: if the hook ever exits before draining stdin
# the writer takes SIGPIPE and `pipefail` reports 141, masking the hook's real
# status. (That is exactly what this assertion caught.)
EMPTY_HOME="$TMP/empty"; mkdir -p "$EMPTY_HOME/.claude"
jq -cn --arg d "$L" '{cwd:$d}' > "$TMP/payload.json"
OUT=$(HOME="$EMPTY_HOME" bash "$HOOK" < "$TMP/payload.json" 2>/dev/null)
STATUS=$?
[ "$STATUS" -eq 0 ] && [ -z "$OUT" ] && ok \
  || bad "missing dotai-rules/ should exit 0 silently (status=$STATUS, out=$OUT)"

# ── A hook that cannot parse its payload must never break the session ─────────
for payload in '{}' 'not json at all' ''; do
  printf '%s' "$payload" > "$TMP/bad.json"
  HOME="$FAKE_HOME" bash "$HOOK" < "$TMP/bad.json" >/dev/null 2>&1
  [ $? -eq 0 ] && ok || bad "payload '$payload' should still exit 0"
done

# ── The retired layout must not come back ────────────────────────────────────
# Installing to ~/.claude/rules/ is what made all three stacks global; assert the
# installer writes dotai-rules/ and cleans the old path up.
if grep -q 'dotai-rules' "$ROOT/scripts/claude/install.sh"; then ok; else
  bad "claude installer no longer targets dotai-rules/"
fi
if grep -qE 'cp .*rules/(laravel|vue|node)\.md" "\$CLAUDE_DIR/rules/' "$ROOT/scripts/claude/install.sh"; then
  bad "claude installer still copies stack rules into the auto-loaded ~/.claude/rules/"
else
  ok
fi

# Both installers must DELETE the retired guards, not merely stop registering them:
# a leftover script on disk is one settings.json line away from coming back.
for inst in claude agy; do
  if grep -q 'retired' "$ROOT/scripts/$inst/install.sh"; then ok; else
    bad "scripts/$inst/install.sh does not clean up the retired guard files"
  fi
done

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
