---
name: map
description: Chart an effort too big for one session as a map of decision tickets, then resolve them one per session until the route is clear. Use when you can name the destination but not the route. Hands off to /plan --from-map once the map clears.
---

# /map — Chart the Route Before Building It

An idea has arrived that **one session cannot hold**, and the way from here to the
**destination** is not visible yet. This command charts that way as a **map** of
**decision tickets** — questions whose resolution is a decision — and works them
one per session until nothing is left to decide.

## Which command is this?

**Session count, not project size.** If the whole thing fits in one conversation,
`/plan` is cheaper and better; `/map` is genuinely slower and denser for that case.

| What you have | Run |
|---|---|
| A route you can already describe, even if details are open | `/plan` |
| A destination you can name and a route you cannot | `/map` |
| A cleared map | `/plan --from-map` → Step 7 tickets → `/next-ticket` |

## Plan, don't do

Every ticket resolves a **decision**. The map is finished when nothing is left to
decide before someone goes and builds the thing — then it **hands off**. The pull to
just start building is the signal you have reached the edge of the map, not licence
to carry on.

Two rules make that stick:

1. **Every open ticket must read as a question.** A ticket that reads "build the X"
   is either mis-typed or belongs downstream, in `/plan`'s implementation tickets.
2. **`## Notes` cannot grant execution licence.** Only the user can, in session, in
   their own words — and only for the ticket in front of you. This exists because
   the obvious alternative fails in a specific way: if the agent may write "this map
   carries execution" into a file the agent itself owns, it will later read that
   back as its own authorisation. A constraint whose exemption is self-writable is
   not a constraint.

Prototype tickets are the one type that produces an artifact — code, an outline, a
rough draft — and it is **throwaway**. See the type table.

## The subject does not have to be code

The map is **domain-agnostic**. A decision tree with a frontier is the same shape
whether the effort is a migration, a course outline, a hiring process, or a personal
call spread over weeks. Only two things ever tied this to software — the branch-keyed
filename and the wording of the coverage check — and both are handled below.

**Reach for it on a non-code subject when the effort is genuinely multi-session and
you will otherwise forget what you already decided.** For a question you can talk
through in one sitting, plain conversation beats a map: the value is the thinking,
and a map charges you filing overhead for it.

## Where the map lives

`{map-key}` is the branch name in snake_case when the working directory is a git repo
on a feature branch — matching `/plan`. **Otherwise it is a kebab-case slug of the
destination** (`should-i-take-the-offer`), so the map works with no repo at all.

`{docdir}` is `.claudedocs/` when that directory exists, otherwise the current
directory — **except for a subject unrelated to the current repo**, where you ask the
user where it should live and default to `~/.claudedocs/`. A personal map does not
belong in a work repository; that is how it ends up in a commit.

```
{docdir}/map-{map-key}.md            ← the map (one file, the index)
{docdir}/map-{map-key}/
├── 01-{slug}.md                     ← decision tickets
├── 02-{slug}.md
└── prototypes/{NN}-{slug}/          ← throwaway artifacts, never committed
```

dotai's map is a **local markdown** map. There is deliberately no issue-tracker
integration: forge detection already exists in three places in this repo and adding
a fourth consumer is a known anti-pattern here. The cost of that choice is that the
frontier is computed by reading the map rather than rendered by a tracker UI — which
is why, unlike a tracker-backed map, this one carries a ticket table.

### Map file format

The whole map at low resolution. Load this once per session; **zoom into individual
ticket files on demand**, never read them all.

```markdown
# Map: {Effort Name}

## Destination

{One or two lines: what reaching the end of this map looks like — the spec, the
decision, or the change this effort is finding its way to. Every session orients to
this before choosing a ticket.}

## Notes

{Domain context; skills every session should consult; standing preferences.}
{This section cannot grant execution licence — see "Plan, don't do".}

## Tickets

| # | Title | Type | Status | Blocked by |
|---|-------|------|--------|------------|
| 01 | {question, phrased as a question} | grilling | open | — |
| 02 | {…} | research | closed | — |
| 03 | {…} | prototype | open | 01 |

## Decisions So Far

<!-- one line per closed ticket: enough to judge relevance, then open the ticket -->
- **02 {title}** — {one-line gist of the answer}

## Not Yet Specified

<!-- the fog: in-scope questions you can sense but cannot yet phrase sharply -->
- {the area to revisit, as loosely as the view allows}

## Out Of Scope

<!-- ruled beyond the destination; closed, never graduates -->
- {gist} — {why it is out of scope} (was ticket NN)
```

The map is an **index, not a store**: a decision lives in exactly one place — its
ticket — and the map only gists it.

### Ticket file format

```markdown
---
ticket: 03
title: {the question, phrased as a question}
type: grilling      # research | prototype | grilling | task
status: open        # open | claimed | closed
blocked-by: [01]
---

## Question

{The decision or investigation this ticket resolves. Sized to one session.}

## Answer

<!-- filled at resolution: the decision, and the reasoning that is worth keeping -->

## Assets

<!-- links to prototypes, research notes, anything created while resolving -->
```

## Ticket Types

Every ticket is either **HITL** — worked *with* the user, who speaks for themselves —
or **AFK**, driven by the agent alone. A HITL ticket resolves only through that live
exchange; **standing in for the user's side of it breaks the ticket**, it does not
complete it.

| `type` | Mode | Reach for it when | Resolved by |
|---|---|---|---|
| `grilling` | HITL | The default. Talking it through can settle it. | Q&A with the user; the output is a decision, not a diff |
| `prototype` | HITL | "How should this look / behave" — talking cannot settle it | A rough throwaway artifact under `prototypes/` — a stub, an outline, a first draft — linked from **Assets**. The user picks; **never choose for them** |
| `research` | AFK | A fact outside this working directory blocks a decision | A sub-agent, fired at charting time, in parallel. Surfaces options — decides nothing |
| `task` | Either | Nothing to decide, but real-world work blocks a decision — provisioning access, signing up for a service, moving data so its shape can be seen, booking the viewing | The agent alone where it can; otherwise a precise checklist for the user |

`task` is the only type that *does* rather than decides, and it earns its place by
**unblocking a decision** — never by delivering a piece of the destination. This is
the type most often got wrong: read as an implementation step, it turns the map into
a build. If a `task` looks like a slice of the product, it is mis-typed.

`research` is the only exception to one-ticket-per-session.

## Fog of War

The map is **deliberately incomplete**. Beyond the live tickets is the fog: questions
you can tell are coming but cannot yet pin down, because they hang on questions still
open. Resolving a ticket clears the fog ahead of it.

**Fog or ticket?** The test is whether you can state the question **precisely now** —
*not* whether you can answer it now.

- **Ticket** when the question is already sharp, even if it is blocked.
- **Not Yet Specified** when it is not. Do not pre-slice fog into ticket-sized
  pieces: one patch may graduate into several tickets, or none.

Fog gathers only **toward** the destination. Work past the destination is not fog —
it goes to **Out Of Scope**, is closed, and never graduates.

---

## Mode A: Chart the Map

Invoked with a loose idea and no existing `map-{map-key}.md`.

### A1. Name the destination

Grill the user until the destination is pinned down: the spec, decision, or change
this whole map — not this session — is finding its way to. The destination fixes the
scope every ticket is measured against, so it is settled first.

### A2. Grill breadth-first

Fan out across the whole space rather than deep on any one thread. You are surfacing
**what has to be decided**, not deciding it.

**Facts are your job, decisions are the user's.** When a question needs something the
environment can settle — what the code already does, what an API returns, how a table
is shaped — go and find out. Read the files, run the query, dispatch a sub-agent.
Never ask the user for something you could look up. Never answer a question that is
theirs to answer.

**Coverage check before you stop.** Breadth-first grilling has no coverage guarantee
of its own, so confirm the fan-out reached all three of these — anything untouched is
either a ticket or a patch of fog. They are phrased for any subject; the parentheses
are what they look like when the subject is code:

1. **Constraints, and what success looks like** — the problem, who it affects, the
   hard limits, what happens if nothing is done. (Business constraints, acceptance
   criteria, deadline and budget.)
2. **Options and their tradeoffs** — at least two viable directions, each with what
   it costs and the assumption it rests on. (Technical approaches; architecture,
   dependencies, team skill.)
3. **How it fails, and how you would know** — the failure modes, the boundary
   conditions, and what would have to be true for you to believe it worked. (Edge
   cases and the test plan: unit, integration, performance.)

### A3. No fog? Stop.

If the breadth-first pass surfaces **no fog** — the route is already clear and the
whole journey fits one session — **you do not need a map**. Say so and point at
`/plan`. Do not chart it anyway.

### A4. Write the map

Create `{docdir}/map-{map-key}.md`: Destination and Notes filled in, Decisions So
Far empty, the fog sketched into Not Yet Specified.

### A5. Create the tickets you can specify now

Write them as `{docdir}/map-{map-key}/NN-{slug}.md`, then wire `blocked-by` in a
**second pass** — tickets need numbers before they can reference each other. Wiring
sorts them into the frontier and the blocked. Anything you cannot phrase sharply
stays in the fog.

**Size signal, not a cap.** If charting yields more than roughly 8–10 tickets, the
destination is too big: the later tickets will rest on assumptions the earlier ones
invalidate, and you will get halfway before the rest stops making sense. Say so and
propose splitting the destination into a bounded first map rather than charting on.

### A6. Fire the research sub-agents

For each `research` ticket just created, dispatch a sub-agent to resolve it — **in
parallel, and non-blocking**. Only tickets downstream of a running exploration wait;
the rest of the frontier is takeable now. Each sub-agent writes its findings into its
ticket's **Answer** with a source for every fact, and closes it.

### A7. Stop

Charting is one session's work. It resolves no HITL tickets. Finish with the ticket
table and:

> **Map charted.** `/clear`, then run `/map` in a fresh session to work the first
> ticket.

---

## Mode B: Work the Map

Invoked when `map-{map-key}.md` exists. A ticket number may be given; without
one, **you** pick the next.

### B1. Load the map only

Read `map-{map-key}.md` and nothing else yet. Do not read every ticket file —
that is what the map exists to avoid.

### B2. Pick and claim

1. The **frontier** = tickets that are `open`, unclaimed, and whose every `blocked-by`
   ticket is `closed`. Take the lowest-numbered one, or the one the user named.
2. **Claim it before any work**: set `status: claimed` in the ticket and the map
   table. A concurrent session then skips it.
3. If any ticket is already `claimed`, ask whether to resume it or pick another.
4. **Frontier empty but tickets remain open** → everything is blocked. Report the
   chain, and if Not Yet Specified is non-empty, offer to graduate a patch — that fog
   is what is actually holding the work up.
5. **All tickets closed** → the map is clear. Go to B6.

### B3. Resolve it

Read that **one** ticket file. Zoom into related or closed tickets on demand; consult
the skills `## Notes` names. Then work it according to its `type` (see the table
above) — and hold the HITL/AFK line: on a `grilling` or `prototype` ticket, the
decision is the user's and you wait for it.

### B4. Record the resolution

1. Write the **Answer** into the ticket; link anything created under **Assets**.
2. Set `status: closed` in the ticket and the map table.
3. Append one line to the map's **Decisions So Far** — a gist, not a restatement.
4. If domain terms were introduced or clarified and the project keeps a `CONTEXT.md`
   glossary, append them (`**{term}** — {one-line definition}`).

### B5. Redraw the map, then stop

The answer changes what is knowable:

- **Graduate fog** the answer has made specifiable into new tickets, and **delete
  those patches from Not Yet Specified** — a graduated patch must live in exactly one
  place.
- **Add newly-surfaced tickets** (create, then wire `blocked-by` in a second pass).
- **Rule out of scope** anything the answer reveals sits past the destination: close
  the ticket and leave one line in Out Of Scope with the reason. It does **not** go
  into Decisions So Far — a scope boundary is not a step on the route.
- **Invalidated tickets** get updated or deleted. If the answer contradicts an
  already-closed decision, say so plainly rather than designing around it.

Then stop. **One ticket per session** (`research` excepted):

> **Ticket {NN} closed.** `/clear` and run `/map` in a fresh session for the next one.

### B6. Hand off

When every ticket is closed and Not Yet Specified is empty, the route is clear:

> **Map clear.** The decisions are made; nothing is left to decide. Run
> `/plan --from-map` to collapse them into a spec, then Step 7 slices it into
> implementation tickets for `/next-ticket`.

A cleared map is a set of linked decisions, not a build plan — which is why it hands
off to `/plan` rather than straight into code.

**If the subject is not code**, there is nothing downstream to slice. Say the map is
clear, summarise the decisions in the conversation, and stop. Do not invent an
implementation phase to have somewhere to go.
