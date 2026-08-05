#!/usr/bin/env bash

# /ship routes step 5 by forge, so the remote-URL parser must be right for every
# URL form git accepts. Two failure modes this pins down:
#   - a naive `sed` capturing only the last two path segments truncates GitLab
#     nested subgroups (group/sub/proj → sub/proj), pointing the API at a project
#     that does not exist;
#   - a `[0-9]*/` glob to drop an ssh :port also eats an org whose name starts
#     with a digit, because in shell that pattern means "one digit then anything".
#
# The snippet under test is extracted from skills/ship/SKILL.md itself rather than
# copied, so the doc and the test cannot drift apart.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/skills/ship/SKILL.md"

PASS=0
FAIL=0

# Pull the detection block out of the skill's first bash fence in Step 5.
SNIPPET=$(awk '
  /^### Step 5:/        { in5=1 }
  in5 && /^```bash$/    { if (!seen) { grab=1; seen=1; next } }
  grab && /^```$/       { grab=0 }
  grab                  { print }
' "$SKILL")

[ -n "$SNIPPET" ] || { echo "❌ could not extract the Step 5 detection snippet from $SKILL" >&2; exit 1; }

# Keep only the pure parsing logic: everything from the scheme strip through the
# PROJECT_PATH assignment. Cutting at a boundary beats filtering line-by-line,
# which silently leaves dangling line continuations behind.
SNIPPET=$(printf '%s\n' "$SNIPPET" \
  | sed -n '/^t=\${REMOTE_URL/,/^PROJECT_PATH=/p')

printf '%s' "$SNIPPET" | grep -q '^PROJECT_PATH=' \
  || { echo "❌ extracted snippet does not end at PROJECT_PATH= — Step 5 layout changed" >&2; exit 1; }

detect() {
  REMOTE_URL=$1
  eval "$SNIPPET"
  printf '%s|%s\n' "$FORGE_HOST" "$PROJECT_PATH"
}

route() {
  case "$1" in
    *gitlab*) echo gitlab ;;
    *github*) echo github ;;
    *)        echo unknown ;;
  esac
}

while IFS='|' read -r url want_host want_path want_route; do
  [ -n "$url" ] || continue
  got=$(detect "$url")
  want="$want_host|$want_path"
  if [ "$got" != "$want" ]; then
    FAIL=$((FAIL+1)); echo "❌ $url → got $got, want $want" >&2; continue
  fi
  got_route=$(route "$want_host")
  if [ "$got_route" != "$want_route" ]; then
    FAIL=$((FAIL+1)); echo "❌ $url → route $got_route, want $want_route" >&2; continue
  fi
  PASS=$((PASS+1))
done <<'CASES'
git@github.com:gopallin/dotai.git|github.com|gopallin/dotai|github
https://github.com/gopallin/dotai.git|github.com|gopallin/dotai|github
https://github.com/gopallin/dotai|github.com|gopallin/dotai|github
ssh://git@github.com/gopallin/dotai.git|github.com|gopallin/dotai|github
git@gitlab.com:group/proj.git|gitlab.com|group/proj|gitlab
git@gitlab.com:group/sub/proj.git|gitlab.com|group/sub/proj|gitlab
https://gitlab.example.com/a/b/c/d.git|gitlab.example.com|a/b/c/d|gitlab
ssh://git@gitlab.example.com:2222/group/proj.git|gitlab.example.com|group/proj|gitlab
https://gitlab.com/123org/repo.git|gitlab.com|123org/repo|gitlab
git@github.acme-corp.io:team/repo.git|github.acme-corp.io|team/repo|github
git@git.acme.com:team/repo.git|git.acme.com|team/repo|unknown
CASES

# The skill must not regress to a hardcoded gitlab.com host, which would silently
# POST a self-hosted project's MR to gitlab.com with a real token.
if grep -qE 'https://gitlab\.com/api' "$SKILL"; then
  FAIL=$((FAIL+1)); echo "❌ skill hardcodes https://gitlab.com/api — must use \$FORGE_HOST" >&2
else
  PASS=$((PASS+1))
fi

# GitHub needs BOTH paths: gh when present, REST API when it is not. Having only
# gh is what made step 5 unreachable on a machine without it.
if grep -q 'gh pr create' "$SKILL"; then PASS=$((PASS+1)); else
  FAIL=$((FAIL+1)); echo "❌ skill has no 'gh pr create' path for GitHub" >&2
fi
if grep -q 'repos/\$PROJECT_PATH/pulls' "$SKILL"; then PASS=$((PASS+1)); else
  FAIL=$((FAIL+1)); echo "❌ skill has no REST API fallback for GitHub" >&2
fi

# The API base must be derived: GitHub Enterprise is https://<host>/api/v3, so a
# hardcoded api.github.com silently targets the wrong server — the same class of
# bug as the hardcoded gitlab.com host.
if grep -q 'API_BASE' "$SKILL" && grep -q 'api/v3' "$SKILL"; then PASS=$((PASS+1)); else
  FAIL=$((FAIL+1)); echo "❌ GitHub API base is not derived from \$FORGE_HOST (Enterprise uses /api/v3)" >&2
fi

# The PR body must be built with jq, not interpolated into a JSON string.
if grep -q "jq -n --arg t" "$SKILL"; then PASS=$((PASS+1)); else
  FAIL=$((FAIL+1)); echo "❌ GitHub REST payload is not built with jq -n" >&2
fi

# A fine-grained PAT expires and its 404 means "repo not granted", not "no repo".
# Without that mapping the failure reads as a missing repository.
for code in 401 403 404 422; do
  grep -q "\`$code\`" "$SKILL" && PASS=$((PASS+1)) || {
    FAIL=$((FAIL+1)); echo "❌ skill does not explain HTTP $code for the GitHub API" >&2
  }
done

# The token must never be echoed. Catch an echo/printf that names the token vars.
if grep -nE '(echo|printf)[^|]*\$\{?(GITHUB_TOKEN|GH_TOKEN_VAL)' "$SKILL" >/dev/null; then
  FAIL=$((FAIL+1)); echo "❌ skill echoes the GitHub token" >&2
else
  PASS=$((PASS+1))
fi

# The GitHub path must never SEND a GitLab credential. Match actual use — a
# PRIVATE-TOKEN header or a Bearer of $GITLAB_TOKEN — not a prose warning that
# names the variable, which is worth keeping.
GH_SECTION=$(awk '/^#### 5a\./{f=1} /^#### 5b\./{f=0} f' "$SKILL")
if printf '%s' "$GH_SECTION" | grep -qE 'PRIVATE-TOKEN|Bearer \$\{?GITLAB_TOKEN'; then
  FAIL=$((FAIL+1)); echo "❌ GitHub path sends a GitLab credential" >&2
else
  PASS=$((PASS+1))
fi

# Symmetrically, the GitLab path must not send a GitHub token.
GL_SECTION=$(awk '/^#### 5b\./{f=1} /^#### 5c\./{f=0} f' "$SKILL")
if printf '%s' "$GL_SECTION" | grep -qE 'GITHUB_TOKEN|GH_TOKEN_VAL'; then
  FAIL=$((FAIL+1)); echo "❌ GitLab path references a GitHub token" >&2
else
  PASS=$((PASS+1))
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
