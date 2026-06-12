#!/usr/bin/env bash
#
# grounding-guard.test.sh
# Unit tests for hooks/claude/grounding-guard.sh, driven by synthetic
# transcript JSONL + crafted PreToolUse stdin JSON.
# Covers cases (a)-(g) from plan-grounding-guard.md §5.1.
#
# Run:  bash tests/grounding-guard.test.sh

set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/claude/grounding-guard.sh"
TMP=$(mktemp -d)
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; rm -f /tmp/dotai_grounding_test-*; }
trap cleanup EXIT

# Build an isolated git repo on a given branch.
mkrepo() { # $1 = branch name
  local d="$TMP/repo_$1_$RANDOM"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" commit -q --allow-empty -m init
  git -C "$d" checkout -q -B "$1"
  echo "$d"
}

mktranscript() { # $1 = content; writes file, echoes path
  local f="$TMP/transcript_$RANDOM.jsonl"
  printf '%s\n' "$1" > "$f"
  echo "$f"
}

# run <name> <cwd> <transcript_path> <file_path> <session_id> <expected_exit>
run() {
  local name="$1" cwd="$2" tpath="$3" fpath="$4" sid="$5" expect="$6"
  local json
  json=$(printf '{"transcript_path":"%s","tool_input":{"file_path":"%s"},"session_id":"%s"}' \
    "$tpath" "$fpath" "$sid")
  local out code
  out=$(cd "$cwd" && echo "$json" | bash "$HOOK" 2>/dev/null)
  code=$?
  if [[ "$code" == "$expect" ]]; then
    echo "  ✅ $name (exit $code)"
    PASS=$((PASS+1))
  else
    echo "  ❌ $name (got exit $code, expected $expect)"
    FAIL=$((FAIL+1))
  fi
}

FEAT=$(mkrepo feature/test)
MAIN=$(mkrepo main)
NONREPO="$TMP/notarepo"; mkdir -p "$NONREPO"

T_NONE=$(mktranscript '{"type":"assistant","text":"about to edit"}')
T_PASS=$(mktranscript 'reference_file: app/Foo.php
GROUNDING_STATUS=PASS')
T_SKIP=$(mktranscript 'GROUNDING_STATUS=SKIP reason=typo fix no logic change')

echo "grounding-guard.sh tests"

# (a) first non-doc edit, no marker -> block
run "(a) first edit, no marker -> exit 2" "$FEAT" "$T_NONE" "src/x.php" "test-a" 2

# (b) first non-doc edit, PASS marker -> allow
run "(b) first edit, PASS -> exit 0" "$FEAT" "$T_PASS" "src/x.php" "test-b" 0

# (c) first edit is .md -> allow (doc exempt)
run "(c) .md edit -> exit 0" "$FEAT" "$T_NONE" "README.md" "test-c" 0

# (d) SKIP marker -> allow + log
run "(d) SKIP -> exit 0" "$FEAT" "$T_SKIP" "src/x.php" "test-d" 0
SKIP_LOG="${HOME}/.claude/usage-data/grounding-skip.log"
if grep -q 'typo fix no logic change' "$SKIP_LOG" 2>/dev/null; then
  echo "  ✅ (d) skip reason logged"; PASS=$((PASS+1))
else
  echo "  ❌ (d) skip reason NOT logged to $SKIP_LOG"; FAIL=$((FAIL+1))
fi

# (e) second code edit (counter preset to 1) -> allow without marker
echo "1" > "/tmp/dotai_grounding_test-e"
run "(e) second edit (counter=1) -> exit 0" "$FEAT" "$T_NONE" "src/y.php" "test-e" 0

# (f) on main -> allow (avoid deadlock with branch-guard)
run "(f) main branch -> exit 0" "$MAIN" "$T_NONE" "src/x.php" "test-f" 0

# (g1) transcript path missing -> allow (fail open)
run "(g1) no transcript -> exit 0" "$FEAT" "$TMP/nope.jsonl" "src/x.php" "test-g1" 0

# (g2) not a git repo -> allow
run "(g2) non-repo -> exit 0" "$NONREPO" "$T_NONE" "src/x.php" "test-g2" 0

echo "─────────────────────────────"
echo "PASS=$PASS  FAIL=$FAIL"
[[ "$FAIL" == 0 ]] && echo "GROUNDING_TEST_STATUS=PASS" || echo "GROUNDING_TEST_STATUS=FAIL"
exit $([[ "$FAIL" == 0 ]] && echo 0 || echo 1)
