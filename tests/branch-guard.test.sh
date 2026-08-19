#!/usr/bin/env bash

# branch-guard used to gate Bash through a 14-prefix read-only WHITELIST, which
# rejected ordinary read-only work whenever it used an unlisted tool or a compound
# command — `wc -l f | tail` and `cd /x && ls` were both blocked in a real session.
# A read-only command cannot modify the repo, so those rejections bought nothing.
#
# It is now a blacklist: writes are blocked, everything else passes. This test
# pins both halves — the writes that MUST stay blocked, and the reads that were
# false positives before and must now pass.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$ROOT/hooks/shared/branch-guard.sh"

PASS=0
FAIL=0

# Two throwaway repos: one on master (guard active), one on a feature branch
# (guard must be a complete no-op).
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for name in protected feature; do
  git init -q -b master "$TMP/$name"
  git -C "$TMP/$name" commit -q --allow-empty -m init
done
git -C "$TMP/feature" checkout -q -b feature/x

# want=block → exit 2; want=allow → exit 0. repo picks the branch context.
check() {
  local want=$1 cmd=$2 repo=${3:-protected}
  local status
  ( cd "$TMP/$repo" && printf '%s' "$(jq -cn --arg c "$cmd" '{tool_input:{command:$c}}')" \
    | bash "$GUARD" >/dev/null 2>&1 )
  status=$?
  case "$want" in
    block) [ "$status" -eq 2 ] && { PASS=$((PASS+1)); return; } ;;
    allow) [ "$status" -eq 0 ] && { PASS=$((PASS+1)); return; } ;;
  esac
  FAIL=$((FAIL+1))
  echo "❌ expected $want, got exit $status for [$repo]: $cmd" >&2
}

# %R% expands to the repo's working-tree root. It MUST be a real path now that the
# guard only blocks files inside the tree — the old fictional `/repo/...` paths
# would all be allowed (correctly) and would silently stop testing anything.
# Note $TMP comes from mktemp -d, i.e. the SYMLINKED form on macOS
# (/var/folders/... → /private/var/folders/...), so every %R% case also exercises
# the guard's physical-path resolution.
check_edit() {
  local want=$1 path=$2 repo=${3:-protected}
  local status
  path=${path//%R%/$TMP/$repo}
  ( cd "$TMP/$repo" && printf '%s' "$(jq -cn --arg p "$path" '{tool_input:{file_path:$p}}')" \
    | bash "$GUARD" >/dev/null 2>&1 )
  status=$?
  case "$want" in
    block) [ "$status" -eq 2 ] && { PASS=$((PASS+1)); return; } ;;
    allow) [ "$status" -eq 0 ] && { PASS=$((PASS+1)); return; } ;;
  esac
  FAIL=$((FAIL+1))
  echo "❌ expected $want, got exit $status for edit [$repo]: $path" >&2
}

# ── Writes on master — must stay blocked ──────────────────────────────────────
check block 'git commit -m "wip"'
check block 'git push origin master'
check block 'git add -A'
check block 'git reset --hard HEAD~1'
check block 'git rebase -i HEAD~3'
check block 'git stash'
check block 'echo hi > notes.txt'
check block 'cat template >> config.yml'
check block 'ls -l | tee listing.txt'
check block 'sed -i "" s/a/b/ file.php'
check block 'rm -rf build/'
check block 'mv a.txt b.txt'

# ── Reads on master — the regressions this rewrite fixes ─────────────────────
# Every line below was blocked by the old whitelist.
check allow 'wc -l CLAUDE.md | tail -40'
check allow 'cd /tmp && ls -l'
check allow 'head -20 README.md'
check allow 'jq -r ".hooks" settings.json'
check allow 'rg "PRIVATE-TOKEN" hooks/'
check allow 'sed -n "1,20p" install.sh'
check allow 'awk "{print \$5}" list.txt'
check allow 'sort names.txt | uniq -c'
check allow 'find . -name "*.sh" | xargs ls -l'
check allow 'bash -n hooks/shared/branch-guard.sh'
check allow 'php artisan route:list'
check allow 'yarn test:unit'

# Still-allowed classics.
check allow 'git status'
check allow 'git log --oneline -5'
check allow 'git diff'
check allow 'ls -la'

# stderr redirection is not a file write.
check allow 'bash -n script.sh 2>&1'
check allow 'command -v jq 2>/dev/null'

# ── A `>` inside a string literal is data, not a redirect ────────────────────
# Regression, observed 2026-08-19: this exact read-only command was blocked with
# "redirects output to a file" because `-` is neither a digit nor `&`, so `->`
# satisfied the bare-string redirect pattern.
check allow 'echo "s3.ap-northeast-1.amazonaws.com -> "'
check allow 'echo "[10.0.50.176] -> internal"'
check allow "grep -oE '>' hooks/shared/branch-guard.sh"
check allow 'echo "use > to redirect and >> to append"'
check allow "awk '{print \$1 \" -> \" \$2}' routes.txt"
# ...but an UNQUOTED `->` genuinely redirects into a file named `b`, so this one
# must still block. This is why the fix is quote awareness, not skipping `->`.
check block 'echo a->b'
check block 'echo "hi" > notes.txt'
check block "echo 'hi' >> notes.txt"

# A write COMMAND inside quotes is normally a real invocation, so unlike the
# redirect check this one deliberately still scans the raw string.
check block "bash -c 'git commit -m x'"
check block "ssh host 'git push origin master'"

# ── The escape hatch must survive unconditionally ────────────────────────────
check allow 'git checkout -b feature/new'
check allow 'git switch -c feature/new'
check allow 'git -C /some/dir checkout main'
check allow 'git checkout -b feature/x 2>&1'

# ── Edit/Write pass-through ──────────────────────────────────────────────────
check_edit allow '%R%/README.md'
check_edit allow '%R%/.claudedocs/note.txt'
check_edit block '%R%/app/Services/Foo.php'
# Neither app/ nor Services/ exists — resolution must walk up to the deepest
# existing ancestor (the repo root) instead of giving up and failing open.
check_edit block '%R%/does/not/exist/yet/Foo.php'
# Relative path, resolved against cwd (= the repo root in this harness).
check_edit block 'app/Services/Foo.php'

# git internals: git cannot track anything inside .git, so a write there can never
# dirty the branch or enter history. Blocking it only broke /handoff, which writes
# its ignore patterns to .git/info/exclude.
check_edit allow '%R%/.git/info/exclude'
check_edit allow '%R%/.git/config'
check_edit allow '%R%/vendor/pkg/.git/info/exclude'
# Relative path: Claude Code sends absolute, but the contract does not promise it
# for every CLI, and a `*/.git/*`-only pattern would block this.
check_edit allow '.git/info/exclude'
# Submodules and worktrees make `.git` a FILE holding a `gitdir:` pointer.
check_edit allow '%R%/sub/.git'

# ...but `.github/` is NOT `.git/` — workflow files are tracked repo content and
# must stay blocked. A sloppy glob would let these through.
check_edit block '%R%/.github/workflows/ci.yml'
check_edit block '%R%/.gitignore'
check_edit block '%R%/src/.gitkeep'

# ── Files OUTSIDE the working tree cannot affect the branch ──────────────────
# Regression, observed 2026-08-19: a write to the session scratchpad under
# /private/tmp/... was blocked purely because cwd was a repo sitting on main.
# The branch has no relationship to those files, so blocking protected nothing.
check_edit allow '/private/tmp/claude-501/session/scratchpad/report.html'
check_edit allow '/tmp/scratch/notes.json'
check_edit allow "$TMP/outside-any-repo/thing.php"
check_edit allow '/Users/nobody/elsewhere/app.ts'
# A sibling temp repo is still "outside" relative to the one we are standing in.
check_edit allow "$TMP/feature/app/Services/Foo.php"

# ── Off master, the guard is inert ───────────────────────────────────────────
check allow 'git commit -m "wip"' feature
check allow 'rm -rf build/' feature
check_edit allow '%R%/app/Services/Foo.php' feature

# ── Unparsable payload must fail OPEN, never trap the agent on master ────────
( cd "$TMP/protected" && printf '%s' '{}' | bash "$GUARD" >/dev/null 2>&1 )
[ $? -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "❌ empty payload should fail open" >&2; }

# ── Outside a git repo, exit 0 ───────────────────────────────────────────────
( cd "$TMP" && printf '%s' '{"tool_input":{"command":"git commit -m x"}}' | bash "$GUARD" >/dev/null 2>&1 )
[ $? -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "❌ non-repo should exit 0" >&2; }

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
