---
name: ship
description: Run full test suite, execute L1/L2/L3 simulated code review, commit changes, push feature branch, then open a Merge Request or Pull Request by default (`--no-mr` to skip; `--release[=name]` to also push a release branch; `--target <branch>` to pick the base) — detecting the forge from `origin` and calling its REST API with a scoped token (no forge CLI required). Trigger when user says "ship it", "test and push", "open MR", "open PR", or uses /ship.
---

# Ship Workflow (Test, Review, Commit, Push, and open MR/PR)

## Purpose

Automates the complete release verification and shipping cycle:
1. Verify Git safety (not on `main`/`master`).
2. Run test suites to ensure 100% green pipeline.
3. Perform simulated L1/L2/L3 Code Review against `git diff`.
4. Commit with structured discipline (Why, not just What).
5. Push feature branch to origin.
6. Open a Merge Request / Pull Request **by default**, routed by the detected
   forge — both go through `curl` + `jq` + a scoped token (`$GITHUB_TOKEN` /
   `$GITLAB_TOKEN`). No forge CLI is required; `gh` is used only if it happens
   to be installed.

A release branch is **not** pushed unless asked for. Both defaults can be
flipped per invocation — see *Arguments* below.

---

## Arguments

Everything after `/ship` is parsed as options. Flags and plain language both
count; the trigger phrases ("ship it", "open MR", …) take the same qualifiers.

| Option | Effect | Default |
|---|---|---|
| `--no-mr` / "不開 MR" / "don't open a PR" / "push only" | Skip Step 5: push, print the click-through URL, stop. | MR/PR **is opened** |
| `--release` / "要 release" / "also push a release branch" | Run Step 4.5 with the derived name (`feature/x` → `release/x`). | release branch **skipped** |
| `--release=<name>` / "release branch 叫 `<name>`" | Run Step 4.5 with that exact name. | — |
| `--target <branch>` / "target `<branch>`" / "開到 `<branch>`" | MR/PR base branch. | `origin/HEAD`, else `main` |

Resolve the options **once, before Step 1**, and echo the decision so the user
can see what will happen before anything is pushed:

```
ship: mr=yes target=main release=no
```

**Do not ask.** The defaults are the answer when nothing was said; a question
here turns a one-shot command back into a dialogue. The only prompts left in
this skill are the ones where guessing could post to the wrong place
(Step 5c, unknown forge) or where the body failed a CI pre-check.

---

## When to Use

Trigger this skill when:
- The user says "ship", "ship it", "test and push", "open MR", "open PR", or "/ship"
- A feature implementation and local refinement loop is complete and ready for code review
- The user asks to deliver changes end-to-end to GitHub or GitLab

---

## Execution Steps

### Step 1: Git Safety Check

Verify the current working branch is NOT `main` or `master`:

```bash
git rev-parse --abbrev-ref HEAD
```

- ❌ **If on `main` or `master`**: Stop immediately. Inform the user that `/ship` cannot be executed on primary branches.
- ✅ **If on a feature branch**: Proceed to Step 2.

**One `/ship` ships one repository — the cwd one.** Every step below runs
`git` in cwd. If this session also wrote into a sibling repository (a feature
that spans frontend and backend), that repo gets its own `/ship`, run from
inside it, and `stop-guard` will refuse the stop until it also holds a
`/precommit` PASS. Do not try to describe both repos' changes in one MR.

---

### Step 2: Run Tests

Detect the project test framework (Vitest, Jest, npm test, etc.) and run the test suite:

```bash
npm test 2>&1
```

- ❌ **If any test fails**: Stop immediately. Surface the exact test failure logs to the user. Do NOT commit or push broken code.
- ✅ **If all tests pass**: Proceed to Step 2.5.

---

### Step 2.5: Simulated Code Review (L1 / L2 / L3 Check)

Invoke the **`reviewer-rules`** skill and run its protocol against `git diff`.

That skill is the single source of truth, shared with `/ground` Step 4.5. Do **not**
inline a checklist here — this step and `/ground`'s previously carried separate
copies and they had already drifted apart.

Project-specific rules (table names, lock keys, base classes) are discovered from
the project itself per that protocol. If none are found, say so and review against
the generic L1/L2/L3 levels only — do not apply another project's rules from memory.

- ❌ **If violations found**: Surface the exact violation to the user and auto-fix if obvious before committing.
- ✅ **If LGTM**: Proceed to Step 3.
- ⚠️ **If a level could not be checked** (no project rules for the assets touched):
  say which level and why. Reporting "L1/L2/L3 passed" when a level was never
  actually evaluated is a false pass.

---

### Step 3: Git Commit Discipline

Scan working tree status and format commit message adhering to standards:

```bash
git status --short
```

1. Format commit message (<=50 char title, blank line, detailed body explaining **WHY**).
2. Execute commit with explicit authorization or via /ship confirmation.

---

### Step 4: Push to Remote

Push the current branch to `origin`:

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git push origin "$BRANCH" 2>&1
```

### Step 4.5: Release Branch (opt-in, skipped by default)

Run this step **only** when the invocation asked for it (`--release`,
`--release=<name>`, or the equivalent in words — see *Arguments*). Otherwise
skip it silently; do not ask whether the user wants one.

- Default name: replace the leading `feature/` with `release/`
  (e.g. `feature/labelkit-integration` → `release/labelkit-integration`).
  A branch without a `feature/` prefix gets `release/<branch>`.
- `--release=<name>` uses that name verbatim.
- Create the branch locally, push it, and return to the feature branch:

```bash
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
RELEASE_BRANCH="${RELEASE_BRANCH:-release/${CURRENT_BRANCH#feature/}}"
git checkout -b "$RELEASE_BRANCH"
git push origin "$RELEASE_BRANCH" 2>&1
git checkout "$CURRENT_BRANCH"
```

---

### Step 5: Open the Merge Request / Pull Request (default: yes)

The MR/PR is opened **without asking**. The target branch is `$TARGET_BRANCH`
as detected in the forge sub-step below, unless `--target <branch>` (or the
spoken equivalent) was given, in which case that value wins.

**Only when the invocation said `--no-mr`** (or "不開 MR" / "push only"), skip
this step: print a near-exact click-through URL from the raw remote and stop.
No forge detection, no API call.

```bash
REMOTE_URL=$(git remote get-url origin)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
# Strip scheme/user/port/ssh prefix to get a bare host/path — good enough for a
# click-through; no forge API is called when skipping.
clean=${REMOTE_URL#*://}
case "$clean" in *@*) clean=${clean#*@} ;; esac
clean=${clean%.git}
clean=${clean/://}   # scp-style colon → slash
echo "Branch pushed. To open a PR/MR manually:"
echo "  https://$clean/compare/$BRANCH"
```

**Otherwise** detect the forge and proceed to 5a / 5b / 5c:

**Detect the forge from `origin` — do not assume GitLab.** GitHub has no
`PRIVATE-TOKEN` API and GitLab has no `gh`, so guessing wrong wastes a step and
produces a confusing error.

Handles all of `git@host:path.git`, `https://host/path.git`,
`ssh://git@host:2222/path.git`, and GitLab nested subgroups (`group/sub/proj`).
Verified against those forms — do not "simplify" it to a one-line sed, which
truncates subgroup paths to their last two segments.

```bash
REMOTE_URL=$(git remote get-url origin)
BRANCH=$(git rev-parse --abbrev-ref HEAD)

t=${REMOTE_URL#*://}                        # strip scheme if present
case "$t" in *@*) t=${t#*@} ;; esac         # strip user@
FORGE_HOST=${t%%[:/]*}
rest=${t#"$FORGE_HOST"}
rest=${rest#:}                              # scp-style ':' separator, or ':port'
rest=${rest#/}

# If the first path component is ALL digits it was a :port, not part of the
# project path. Do NOT use a [0-9]* glob here — in shell that means "one digit
# then anything", so it would also swallow an org named like 123org/.
port=${rest%%/*}
case "$port" in
  ''|*[!0-9]*) ;;
  *) rest=${rest#*/} ;;
esac
PROJECT_PATH=${rest%.git}

# Default target branch, falling back to main when origin/HEAD is not set.
# A --target given on the /ship line was already put in TARGET_BRANCH by the
# Arguments step and must not be overwritten here.
if [ -z "$TARGET_BRANCH" ]; then
  TARGET_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's@^refs/remotes/origin/@@')
  TARGET_BRANCH="${TARGET_BRANCH:-main}"
fi

echo "forge=$FORGE_HOST project=$PROJECT_PATH branch=$BRANCH → $TARGET_BRANCH"
```

**Build the description from the repo's own template — before routing.** The
forge applies `.gitlab/merge_request_templates/Default.md` (GitLab) or
`.github/pull_request_template.md` (GitHub) **only in its web UI**. An MR/PR
opened through the API gets exactly the body you send. nxl-shipping-server
MR !891 (2026-10-05) failed its CI pre-check on the first pipeline for this
reason: the check requires filled `## 說明` / `## 原因` sections and `/ship` had
sent a `## Summary` body.

```bash
TEMPLATE=""
for t in .gitlab/merge_request_templates/Default.md \
         .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md \
         pull_request_template.md PULL_REQUEST_TEMPLATE.md \
         docs/pull_request_template.md; do
  [ -f "$t" ] && { TEMPLATE="$t"; break; }
done
# A GitLab repo with templates but no Default.md: take the only/first one.
[ -z "$TEMPLATE" ] && [ -d .gitlab/merge_request_templates ] && \
  TEMPLATE=$(ls .gitlab/merge_request_templates/*.md 2>/dev/null | head -1)
BODY_FILE=$(mktemp -t ship-body)
echo "template=${TEMPLATE:-none}  body=$BODY_FILE"
```

Then write `$BODY_FILE`:

- **Template found** → keep every heading **verbatim** and in order. Fill each
  section with real content from the diff and the commit body; delete the
  `<!-- … -->` placeholder comments (a section whose only content is a comment
  reads as *unfilled* to a template gate); tick the checkboxes that apply
  (`- [x]`); a section with nothing to say gets an explicit `None` line, never
  an empty body. Write it in the template's language.
- **No template** → fall back to `## Summary` followed by the commit body.
- Either way, end with `---` and `*Shipped via /ship with L1/L2/L3 verification*`.

Print the body in full before posting it, so a wrong section is visible in
the transcript next to the resulting URL. There is no confirmation pause —
the gate that replaces it is the repo's own check: if `CLAUDE.md` or the
reviewer rules name a CI pre-check that reads the description (for example
one driven by `CI_MERGE_REQUEST_DESCRIPTION`), run it against `$BODY_FILE`
now. A failing pre-check is the one case where Step 5 stops and asks: show
the failure, fix the body, and only then post.

Then route on `$FORGE_HOST`:

```bash
case "$FORGE_HOST" in
  *gitlab*) echo "route=gitlab" ;;
  *github*) echo "route=github" ;;
  *)        echo "route=unknown" ;;
esac
```

Hostname is a heuristic: a self-hosted GitHub Enterprise or GitLab often sits on a
neutral domain like `git.acme.com` and lands in `unknown`. That is deliberate — go
to 5c and **ask** rather than firing a POST at the wrong API with a real token.

#### 5a. `route=github` → REST API; `gh` only if already installed

**Never fall back to the GitLab API** — that would send `$GITLAB_TOKEN` to GitHub.

**5a-i — REST API + a fine-grained PAT. This is the default path.** It is
deliberately the same shape as 5b: `curl` + `jq` + one narrowly scoped token, no
forge CLI to install and no account-wide OAuth token to manage.

> A missing `gh` is **not** a blocker and must never be reported as one. Go
> straight to this block.

```bash
# Prefer the exported var, but read Keychain directly as a fallback: a shell
# started before the token was added to ~/.zshrc has no $GITHUB_TOKEN, and that
# should not block shipping. Never echo this value.
GH_TOKEN_VAL="${GITHUB_TOKEN:-$(security find-generic-password -a "github" -s "ai-agent-github-token" -w 2>/dev/null)}"

# github.com uses api.github.com; GitHub Enterprise uses https://<host>/api/v3.
case "$FORGE_HOST" in
  github.com) API_BASE="https://api.github.com" ;;
  *)          API_BASE="https://$FORGE_HOST/api/v3" ;;
esac

# The body was written to $BODY_FILE above (template-shaped when the repo has
# one). --rawfile keeps it verbatim; a quote or backslash in it cannot break the JSON.
RESP=$(curl -s -w '\n%{http_code}' -X POST \
  -H "Authorization: Bearer $GH_TOKEN_VAL" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -d "$(jq -n --arg t "$(git log -1 --format=%s)" --arg h "$BRANCH" \
            --arg b "$TARGET_BRANCH" --rawfile body "$BODY_FILE" \
        '{title:$t, head:$h, base:$b, body:$body}')" \
  "$API_BASE/repos/$PROJECT_PATH/pulls")

CODE=$(printf '%s' "$RESP" | tail -1)
printf '%s' "$RESP" | sed '$d' | jq '{number, html_url, state}' 2>/dev/null
echo "HTTP $CODE"
```

Build the payload with `jq -n`, never string interpolation — a commit body
containing a quote, backslash, or newline otherwise yields invalid JSON.

**Interpret the status code before reporting.** A bare HTTP number is misleading
here; fine-grained tokens fail in ways that read like the repo is missing:

| Code | Meaning | Fix |
|---|---|---|
| `201` | PR created | use `html_url` |
| `401` | token invalid or **expired** (fine-grained PATs always expire) | regenerate, then `security add-generic-password -a github -s ai-agent-github-token -w` |
| `403` | authenticated but lacks **Pull requests: write** | edit the token's permissions |
| `404` | repo not in the token's **Repository access** list (not "missing repo") | add the repo to the token |
| `422` | PR already exists for this branch, or no commits between branches | check for an open PR first |

**A 401/403/404 here is a token problem, and the table says which one.** Do not
suggest installing `gh` as the fix — swapping to an account-wide OAuth token to
work around a missing scope trades a one-line permission edit for a much larger
blast radius.

**5a-ii — `gh`, only when it is already installed AND authenticated:**

```bash
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh pr create --base "$TARGET_BRANCH" --head "$BRANCH" \
    --title "$(git log -1 --format=%s)" \
    --body-file "$BODY_FILE"
fi
```

Worth reaching for on a GitHub Enterprise host, where it resolves the API base and
auth without extra config. Otherwise 5a-i already covered it.

**5a-iii — no usable token and no `gh`:** report the blocker, do not fail silently.
Print the click-through URL and the PR body so no work is lost:

```bash
echo "https://$FORGE_HOST/$PROJECT_PATH/pull/new/$BRANCH"
echo "Fix: create a fine-grained PAT with these repository permissions —"
echo "       Pull requests: Read and write   (required to open the PR)"
echo "       Contents:      Read-only        (enough while pushes go over SSH)"
echo "     scope it to selected repositories, not All repositories, then store it:"
echo "       security add-generic-password -a github -s ai-agent-github-token -w"
```

Never print the token, and never include it in an error message.

#### 5b. `route=gitlab` → REST API + `$GITLAB_TOKEN`

Use `$FORGE_HOST`, **not** a hardcoded `gitlab.com` — self-hosted GitLab is common
and hardcoding the host silently targets the wrong server. Per global rules, `glab`
is not installed; use `curl` + `jq`.

```bash
[ -n "$GITLAB_TOKEN" ] || echo "GITLAB_TOKEN unset — cannot open MR"
ENCODED_PATH=$(printf '%s' "$PROJECT_PATH" | sed 's#/#%2F#g')

curl -s --request POST \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --header "Content-Type: application/json" \
  --data "$(jq -n \
      --arg s "$BRANCH" --arg t "$TARGET_BRANCH" \
      --arg title "$(git log -1 --format=%s)" \
      --rawfile body "$BODY_FILE" \
      '{source_branch:$s, target_branch:$t, title:$title, description:$body}')" \
  "https://$FORGE_HOST/api/v4/projects/$ENCODED_PATH/merge_requests" \
  | jq '{id, iid, web_url, state}'
```

> Build the JSON with `jq -n` (`--rawfile` for the body), never string
> interpolation — a body containing a quote, backslash, or newline otherwise
> produces invalid JSON and the API returns a 400 that reads like an auth failure.
> The body comes from `$BODY_FILE`, shaped by the repo's MR template when it has
> one — see *Build the description* above.

> **No `draft:` title prefix.** GitLab parses it and returns `draft: true`, which
> blocks the merge button until someone manually clicks "Mark as ready" — a hidden
> extra step on every single MR. It was also an asymmetry: 5a never prefixed the
> GitHub title, so the same `/ship` produced a ready PR and a blocked MR depending
> only on the forge. If a particular MR genuinely is work-in-progress, say so and
> add the prefix for that one.

#### 5c. `route=unknown` → stop and ask

Do not guess an API. Report the detected host, confirm the branch is pushed, and
ask the user which forge it is (or to open the request manually), offering the
remote URL. Firing 5a or 5b speculatively can leak `$GITLAB_TOKEN` to an
unintended host.

---

## Verification

Report final execution status to the user:
- ✅ Tests Passed
- ✅ L1/L2/L3 Review Passed (LGTM)
- ✅ Branch Pushed (`origin/<branch>`)
- ✅ Release Branch Pushed (`origin/<release-branch>`) (only with `--release`)
- ✅ MR/PR Created (provide direct `web_url` link) — the default
- ⏭️ MR/PR Skipped (provide raw click-through URL) (only with `--no-mr`)

If Step 5 could not complete (token missing, token lacks a permission, unknown
host), say so explicitly — steps 1-4 succeeding is **not** "shipped". Report which
step blocked, why, the exact command that fixes it, and the click-through URL plus
the PR body text so no work is lost.

"`gh` is not installed" is never a valid reason for Step 5 to fail. If that is
what you are about to report, you skipped 5a-i.
