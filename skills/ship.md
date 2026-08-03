---
name: ship
description: Run full test suite, execute L1/L2/L3 simulated code review, commit changes, push feature branch, and create a GitLab Merge Request via API. Trigger when user says "ship it", "test and push", "open MR", or uses /ship.
---

# Ship Workflow (Test, Review, Commit, Push, and Merge Request)

## Purpose

Automates the complete release verification and shipping cycle:
1. Verify Git safety (not on `main`/`master`).
2. Run test suites to ensure 100% green pipeline.
3. Perform simulated L1/L2/L3 Code Review against `git diff`.
4. Commit with structured discipline (Why, not just What).
5. Push feature branch to origin.
6. Create a GitLab Merge Request via GitLab REST API.

---

## When to Use

Trigger this skill when:
- The user says "ship", "ship it", "test and push", "open MR", or "/ship"
- A feature implementation and local refinement loop is complete and ready for code review
- The user asks to deliver changes end-to-end to GitLab

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

### Step 5: Open GitLab Merge Request via API

Detect GitLab project path or ID from `git remote -v`, then invoke GitLab API with `$GITLAB_TOKEN`:

```bash
# Get remote URL and extract project path
REMOTE_URL=$(git remote get-url origin)
PROJECT_PATH=$(echo "$REMOTE_URL" | sed -E 's#.*[:/]([^/]+/[^/]+)\.git#\1#')
ENCODED_PATH=$(echo "$PROJECT_PATH" | sed 's#/#%2F#g')
BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Detect default target branch
TARGET_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

# Create MR via Curl
curl -s --request POST \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{
    \"source_branch\": \"$BRANCH\",
    \"target_branch\": \"$TARGET_BRANCH\",
    \"title\": \"draft: $(git log -1 --format=%s)\",
    \"description\": \"## Summary\n\n$(git log -1 --format=%b)\n\n---\n*Shipped via /ship skill with L1/L2/L3 verification*\"
  }" \
  "https://gitlab.com/api/v4/projects/$ENCODED_PATH/merge_requests" | jq '{id, iid, web_url, state}'
```

---

## Verification

Report final execution status to the user:
- ✅ Tests Passed
- ✅ L1/L2/L3 Review Passed (LGTM)
- ✅ Branch Pushed (`origin/<branch>`)
- ✅ MR Created (provide direct `web_url` link)
