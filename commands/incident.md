---
description: Root-cause a production incident evidence-first — normalize every timestamp to UTC, rank competing hypotheses, disprove them before proposing a fix, then write the failing test that reproduces it
---

# /incident — Evidence-First Root Cause

## Why this exists

Debugging is the second-largest category of work in this setup (~22 of 95
sessions in the 2026-09-07 usage report), and it produced the single most
expensive documented failure: during a duplicate-B2B-batch-claim investigation
the timeline mixed **UTC** database and log timestamps with **+0800** git
timestamps, which yielded three separate confident "you didn't break anything"
conclusions. The user's timezone correction forced a full retraction — and the
real cause turned out to be a Redis lock TTL lost on retry, plus a fix that had
never been deployed to production.

Same shape elsewhere: the S-station create-batch path, the WARP/Tailscale
mechanism, the "data-only USB cable", the `numprocs=2` correlation. In each case
the *final* answer was good and the *first* hypothesis was wrong, and each wrong
turn cost a round trip where the human had to supply DB rows or logs to force a
retraction.

This is a command rather than a rule in `GLOBAL_RULES.md` deliberately
(CLAUDE.md §Prompt Minimalism): it applies to a quarter of sessions, so it is
opt-in and costs nothing in the other three quarters.

## When to use

Invoke `/incident` before any diagnosis where the answer will drive a code change
or a production action:

- a symptom plus logs / a `failed_jobs` dump / DB rows
- "why did X happen in production"
- anything whose evidence spans more than one clock (DB, app logs, git, CI, a
  device)

For a local failure with a stack trace in front of you, don't — just read it.

## Protocol

### Step 1 — Timezones FIRST, before any analysis

List **every** data source and the timezone it reports in, then convert
everything to UTC. Do this before building any timeline, not while explaining
one.

```
source                      | native tz | note
--------------------------- | --------- | ----------------------------------
MySQL/Postgres rows         | ?         | check the column type + server tz
application logs            | ?         | framework config, not the host
git commit timestamps       | ?         | committer's local zone, per commit
shell / `date` output       | ?         | this machine
CI / pipeline logs          | ?         | usually UTC, verify
```

Fill in `?` by **checking**, not assuming. On this machine the shell is +0800
while DB rows and most application logs are UTC — an eight-hour offset silently
invalidates any reconstruction that mixes them.

State the timezone explicitly in every timeline row and in the conclusion.

> If you are ever about to write "you didn't break anything" or any similar
> reassurance, stop and re-verify the timeline first. That sentence has been
> wrong three times in a row in this codebase.

### Step 2 — Establish the observable facts

Only what is *observed*, each with its source. No inference yet.

```
fact                                   | source
-------------------------------------- | -------------------------------------
batch 4471 claimed twice, 12s apart    | b2b_batches rows 4471 (UTC)
worker restarted at 03:14:22Z          | supervisord log
```

If a "fact" comes from a screenshot, echo each `field | value` and confirm it
against the DB or the logs — the DB wins (GLOBAL_RULES §Verifying Against
Screenshots).

### Step 3 — At least three competing hypotheses, each with a kill test

Rank by likelihood, and for **each** name the single command or query that would
**disprove** it:

```
H1 (likely)   lock TTL lost on retry     → kill test: SELECT … FROM cache WHERE key='lock:…'
H2 (possible) duplicate consumer         → kill test: ps aux | grep queue:work | wc -l
H3 (unlikely) client double-submit       → kill test: request log for POST /claim, same idempotency key
```

Then **run the kill tests** and report which hypotheses survived, with the
evidence pasted. Do not propose a fix while more than one survives — go find the
distinguishing evidence instead.

A correlation is not a kill test. "numprocs happens to be 2 and we saw 2
duplicates" survives nothing.

### Step 4 — Check whether the fix is even deployed

Before concluding that a known fix "should have prevented this", verify the fix
is actually running in the affected environment:

```bash
git log --oneline -5 -- <path>          # when was it fixed
git branch -r --contains <sha>          # did it reach the release branch
# then: what does the deployed host actually have checked out?
```

A fix that exists in `master` and not in production explains a great many
"impossible" incidents.

### Step 5 — Reproduce before repairing

Write the **failing test** that reproduces the bug, and show it failing. A fix
without a regression test cannot be distinguished from a coincidence, and this
is where `/precommit`'s test step earns its keep.

### Step 6 — Then, and only then, fix

Hand off to the normal flow: `/ground` (declare the blast radius — the fix
belongs in one layer, and incident fixes are exactly where "while we are here"
creeps in) → implement → `/precommit` → `/ship`.

## Output shape

Lead with the answer in one sentence, then the evidence. Terse and
copy-pasteable; no essay:

```
ROOT CAUSE: <one sentence>

TIMELINE (all UTC)
  03:14:10Z  …
FACTS
  … | source
RULED OUT
  H2 — <the evidence that killed it>
  H3 — <the evidence that killed it>
REGRESSION TEST
  tests/Feature/…::test_… (failing before the fix)
NOT YET VERIFIED
  <anything you could not check, named explicitly>
```

`NOT YET VERIFIED` is not optional. "Skipped is not passed" (GLOBAL_RULES): if
you could not reach a log or a row, name that gap rather than smoothing it over
with "should".

## Parallelism

When the evidence spans repos or systems, gather it concurrently — one agent per
repo/source, each reporting `file:line` or rows and nothing else — then
synthesize one timeline yourself. Serial `grep` chains across four repos burn
the context you need for the actual fix.

## Not enforced by a hook — and why

There is no `INCIDENT_STATUS=PASS` marker. A hook can verify that a *pipeline
ran* (`/precommit`) or that a *declaration exists* (`/ground`), but it cannot
verify that a hypothesis was honestly falsified. Adding a marker here would
create exactly the kind of check that rewards typing the line — the failure mode
that got the old stop-guard "Layer 3" deleted (`docs/ABLATION.md`). The
enforcement for incident work is the regression test in Step 5, which
`/precommit` does run.
