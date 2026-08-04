---
name: ship
description: Run full test suite, execute L1/L2/L3 simulated code review, commit changes, push feature branch, then open a Merge Request or Pull Request — detecting the forge from `origin` (GitHub via `gh`, GitLab via REST API). Trigger when user says "ship it", "test and push", "open MR", "open PR", or uses /ship.
---

# Ship Workflow (Test, Review, Commit, Push, and open MR/PR)

## Purpose

Automates the complete release verification and shipping cycle:
1. Verify Git safety (not on `main`/`master`).
2. Run test suites to ensure 100% green pipeline.
3. Perform simulated L1/L2/L3 Code Review against `git diff`.
4. Commit with structured discipline (Why, not just What).
5. Push feature branch to origin.
6. Open a Merge Request / Pull Request, routed by the detected forge
   (GitHub → `gh`, GitLab → REST API + `$GITLAB_TOKEN`).

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

Review the current `git diff` against the project's Reviewer Agent rules:

1. **L1 (Project Rules & CLAUDE.md):**
   - Single public method `exec()`, constructor injection, state transitions via `transitionTo`.
   - Anti-patterns: no manual status column updates, no `app()` usage, no business logic in controllers.
   - **Data & Migrations:** If adding/dropping columns on `shipments`, `shipment_items`, `batches`, `batch_items`, `b2b_batches`, or `b2b_batch_items`, verify matching changes to `backup_*` mirror tables!
2. **L2 (Stack Best Practices):**
   - Laravel: No N+1 queries, Eloquent efficiency, PSR-2 styling.
   - NestJS: Proper dependency injection and TypeScript typing safety.
   - Vue 3: Composition API best practices, no unnecessary reactivity overhead.
   - Security: Parameterized queries, input sanitization, PII protection.
3. **L3 (Production & Concurrency):**
   - Concurrency: Check for read-modify-write on shared state (`stock.usage`, counters, `picking_priority`). Ensure Redis locks (`getRedisLock`/`releaseRedisLock`, key `check_capacity`) are used.
   - Idempotency & Observability: Ensure jobs/listeners are idempotent and important events are logged.

- ❌ **If violations found**: Surface the exact violation to the user and auto-fix if obvious before committing.
- ✅ **If LGTM**: Proceed to Step 3.

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

---

### Step 5: Open the Merge Request / Pull Request

**Detect the forge from `origin` first — do not assume GitLab.** GitHub has no
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
TARGET_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
  | sed 's@^refs/remotes/origin/@@')
TARGET_BRANCH="${TARGET_BRANCH:-main}"

echo "forge=$FORGE_HOST project=$PROJECT_PATH branch=$BRANCH → $TARGET_BRANCH"
```

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

#### 5a. `route=github` → `gh`

```bash
command -v gh >/dev/null 2>&1 || { echo "gh not installed"; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated"; }

TITLE=$(git log -1 --format=%s)
gh pr create --base "$TARGET_BRANCH" --head "$BRANCH" \
  --title "$TITLE" --body "$(printf '## Summary\n\n%s\n\n---\n*Shipped via /ship with L1/L2/L3 verification*' "$(git log -1 --format=%b)")"
```

**If `gh` is missing or unauthenticated, do NOT fail silently and do NOT fall back
to the GitLab API.** Report the blocker, print the ready-to-click compare URL, and
give the user the PR body so nothing is lost:

```bash
echo "https://$FORGE_HOST/$PROJECT_PATH/pull/new/$BRANCH"
echo "Fix with: brew install gh && gh auth login"
```

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
      --arg title "draft: $(git log -1 --format=%s)" \
      --arg body "## Summary

$(git log -1 --format=%b)

---
*Shipped via /ship with L1/L2/L3 verification*" \
      '{source_branch:$s, target_branch:$t, title:$title, description:$body}')" \
  "https://$FORGE_HOST/api/v4/projects/$ENCODED_PATH/merge_requests" \
  | jq '{id, iid, web_url, state}'
```

> Build the JSON with `jq -n`, never string interpolation — a commit body
> containing a quote, backslash, or newline otherwise produces invalid JSON and the
> API returns a 400 that reads like an auth failure.

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
- ✅ MR/PR Created (provide direct `web_url` link)

If Step 5 could not complete (no `gh`, no `$GITLAB_TOKEN`, unknown host), say so
explicitly — steps 1-4 succeeding is **not** "shipped". Report which step blocked,
why, the exact command that fixes it, and the click-through URL plus the PR body
text so no work is lost.
