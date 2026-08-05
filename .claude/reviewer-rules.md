# Reviewer Rules — dotai

Discovered by the `reviewer-rules` skill (discovery slot 1), so `/ground` and
`/ship` load these automatically in this repo.

Every rule below is here because it was **actually violated in this repo**, and the
parenthetical says what it would have caught. Nothing speculative — a checklist of
hypotheticals gets skimmed, and then the real items get skimmed with it.

The stack is bash + jq + markdown, distributed to three AI CLIs (Claude Code,
Codex, Antigravity/agy). The recurring failure mode is not broken logic: it is
**config that is silently ignored**, which looks installed and does nothing.

---

## L1 — Architecture & Parity

**Never port a guard between CLIs by copying it.** Each CLI has its own hook
contract — event names, payload key casing, tool names, and how a block is
signalled. Read the target CLI's contract in `CLAUDE.md` §agy Hook Contract before
touching `hooks/<cli>/`. (All six agy guards were silently inert: they used events
`AfterAgent`/`BeforeTool` that do not exist, tool names `write_file`/`read_file`
that do not exist, and `exit 2` where agy reads a JSON decision from stdout.)

**Skills are directories, never flat files.** `skills/<name>/SKILL.md` with both
`name:` and `description:` in frontmatter. A flat `skills/<name>.md` is discovered
by no CLI, with no warning. (All five skills were invisible; `/ship` "did not
exist" despite being installed with valid frontmatter.)

**Parity list — adding a skill, command, or hook means touching all of these:**

| Add a… | Also update |
|---|---|
| skill | `skills/<name>/SKILL.md`, `CLAUDE.md` structure tree |
| command | all three `scripts/*/install.sh` (agy installs commands **as skills**) |
| hook | `hooks/<cli>/`, the CLI's registration (`hooks/hooks.json` or `hooks/agy/hooks.json`), all three installers, `tests/` |
| anything installed | a test that asserts it landed where the CLI actually reads it |

Install summaries must be **derived from what was installed**, never hardcoded — a
hardcoded list goes stale the moment something is added, and reads as verification
while lying. (Three installers claimed 5 skills after a 6th was added.)

**Per-CLI install roots — these are not interchangeable:**

| | Claude Code | Codex | agy |
|---|---|---|---|
| skills | `~/.claude/skills/` | `~/.codex/skills/` | `~/.gemini/config/skills/` |
| commands | `~/.claude/commands/` | `~/.codex/prompts/` | **none** — ship as skills |
| hooks cfg | `settings.json` | `hooks.json` | `~/.gemini/config/hooks.json` |
| rules | `~/.claude/dotai-rules/` + `stack-rules.sh` | **no mechanism** | `~/.gemini/rules/` |

**Stack rules deliberately avoid `~/.claude/rules/`.** Claude Code auto-loads every
file in that directory with no path filtering, so anything placed there loads in
every project forever. dotai installs to `dotai-rules/` — *not* auto-loaded — and a
`SessionStart` hook emits only the detected stack's file. Putting a stack rules file
back under `rules/` silently restores the always-on behaviour.

agy's global root is `~/.gemini/config/`, **not** `~/.gemini/`. Codex has no
`rules/` mechanism, so shared content referenced by a skill must not live in
`rules/` or carry a `~/.claude/...` path. (Both mistakes were made: skills at the
wrong agy root, and `ground`/`ship` pointing at `~/.claude/rules/reviewer-rules.md`,
dead on two of three CLIs.)

**One concern, one source.** Before adding logic to a skill or hook, grep for it —
if it already exists, reference it. (The L1/L2/L3 checklist was inlined in both
`ground` and `ship` and had already drifted. Forge/remote detection currently
exists in **three** places — `skills/git-push`, `skills/ship`, `hooks/shared/glab-guard.sh`
— and is a known outstanding cleanup, not a pattern to copy.)

---

## L2 — Bash / jq Practices & Security

**Guards fail OPEN.** A guard that cannot classify its input must allow the action.
Trapping the agent is worse than missing one bad call, because the escape usually
requires the very tool being blocked. Every deny path needs an escape hatch
(`git checkout` on a protected branch; a ranged re-read after an edit).

**Shell globs are not regex.** `[0-9]*` means "one digit then anything", not "digits".
Use an explicit `case "$x" in ''|*[!0-9]*)` test for "all digits". (`[0-9]*/` meant
to strip an ssh `:port` also ate an org named `123org/`.)

**Sanitise any payload value interpolated into a path.** IDs from hook stdin go
through `tr -cd 'A-Za-z0-9._-'` before landing in a `/tmp/...` marker name.
(`conversationId` containing `../` would have written outside `/tmp`.)

**Build JSON with `jq -n --arg`, never string interpolation.** A commit body with a
quote, backslash, or newline otherwise yields invalid JSON, and the API returns a
400 that reads like an auth failure.

**Do not add `set -e` to a script whose signal is a wrapped command's exit code.**
It kills the script before it can emit its decision, silently turning the guard
off. Where its absence is load-bearing, say so in the file.
(`hooks/agy/shared-guard-adapter.sh`.)

**Do not treat quoted substrings as shell syntax.** Strip quoted spans before
matching separators, or a read-only `grep "a\|foo"` is read as a pipe into `foo`.
(`glab-guard` blocked every grep whose pattern mentioned glab.)

**Never `rm` an untracked file to test that something detects its absence.** git
cannot restore it. Move it aside and move it back. (Cost one rewrite of this file.)

**Secrets:** never in files. Tokens come from the shell env, loaded from Keychain.
Never log a token or echo it into an error message.

---

## L3 — Production Readiness

**Verify against the real CLI, and label the evidence.** Mark claims `[probed]`
(observed live), `[binary]` (string in the executable), or `[doc]`. Never write a
`[doc]`-only claim as established fact. (Three docs claimed `rules/` was
"path-filtered". Nothing filters it — every rules file loads in every project.
That false belief is what made it look fine to put one project's table names in a
globally-installed file. Fixed by `hooks/claude/stack-rules.sh`, which does the
filtering the docs had merely assumed.)

**A newly registered hook has not fired until you have seen it fire.** Registration
landing in `settings.json` is not evidence — that is the same "looks installed, does
nothing" class as an inert matcher. State a new hook's status as `[unverified]` until
a live session confirms it, and say what would confirm it.

**Installers must be idempotent and must clean up the previous layout.** Run twice
in a temp `HOME` in tests. An upgrade that leaves the old files behind produces a
tree that looks installed two different ways. (Flat `skills/*.md` and
`~/.gemini/skills/` both had to be removed explicitly.)

**A blocking hook on a stop/continue event needs a loop brake.** Unconditional
"keep going" spins forever. Cap it and fail open. (`hooks/agy/stop-guard.sh` gives
up after 2 blocks; agy has no `stop_hook_active` flag.)

**Advisory output must go where that CLI actually reads it.** agy never surfaces a
hook's stderr — advice belongs in `reason` or an `ephemeralMessage`. An advisory
written to the wrong stream is not a soft warning, it is nothing.

**A slow CLI is not a broken one.** `agy -p` regularly exceeds 90s; raise
`--print-timeout` (300s works) before concluding quota or config is at fault.

**Never report coverage you did not achieve.** "Tests pass" is false if any were
skipped; "L1/L2/L3 passed" is false if a level was never evaluated. If a check
could not run, name the check and why. This is the whole premise of the repo —
`stop-guard` exists because "done" was being claimed without verification.

---

## How to check these

`tests/*.test.sh` — run all of them, they are the enforcement:

```bash
for t in tests/*.test.sh; do printf '%-34s ' "$(basename "$t")"; bash "$t" 2>&1 | tail -1; done
```

`skills-install.test.sh` and `agy-install.test.sh` cover the L1 parity items;
`glab-guard.test.sh`, `ship-forge-detect.test.sh` and `agy-hook-contract.test.sh`
cover the L2 items above. A new rule here should arrive with the test that enforces
it — otherwise it is back to relying on the agent remembering, which is the thing
this repo exists to avoid.
