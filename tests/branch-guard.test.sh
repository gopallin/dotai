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

check_edit() {
  local want=$1 path=$2 repo=${3:-protected}
  local status
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

# ── The escape hatch must survive unconditionally ────────────────────────────
check allow 'git checkout -b feature/new'
check allow 'git switch -c feature/new'
check allow 'git -C /some/dir checkout main'
check allow 'git checkout -b feature/x 2>&1'

# ── Edit/Write pass-through ──────────────────────────────────────────────────
check_edit allow '/repo/README.md'
check_edit allow '/repo/.claudedocs/note.txt'
check_edit block '/repo/app/Services/Foo.php'

# git internals: git cannot track anything inside .git, so a write there can never
# dirty the branch or enter history. Blocking it only broke /handoff, which writes
# its ignore patterns to .git/info/exclude.
check_edit allow '/repo/.git/info/exclude'
check_edit allow '/repo/.git/config'
check_edit allow '/repo/vendor/pkg/.git/info/exclude'
# Relative path: Claude Code sends absolute, but the contract does not promise it
# for every CLI, and a `*/.git/*`-only pattern would block this.
check_edit allow '.git/info/exclude'
# Submodules and worktrees make `.git` a FILE holding a `gitdir:` pointer.
check_edit allow '/repo/sub/.git'

# ...but `.github/` is NOT `.git/` — workflow files are tracked repo content and
# must stay blocked. A sloppy glob would let these through.
check_edit block '/repo/.github/workflows/ci.yml'
check_edit block '/repo/.gitignore'
check_edit block '/repo/src/.gitkeep'

# ── Off master, the guard is inert ───────────────────────────────────────────
check allow 'git commit -m "wip"' feature
check allow 'rm -rf build/' feature
check_edit allow '/repo/app/Services/Foo.php' feature

# ── Unparsable payload must fail OPEN, never trap the agent on master ────────
( cd "$TMP/protected" && printf '%s' '{}' | bash "$GUARD" >/dev/null 2>&1 )
[ $? -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "❌ empty payload should fail open" >&2; }

# ── Outside a git repo, exit 0 ───────────────────────────────────────────────
( cd "$TMP" && printf '%s' '{"tool_input":{"command":"git commit -m x"}}' | bash "$GUARD" >/dev/null 2>&1 )
[ $? -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "❌ non-repo should exit 0" >&2; }

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
