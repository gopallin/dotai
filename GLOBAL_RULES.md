# AI CLI Global Rules

> **This file is deliberately short.** It loads into *every* session of *every*
> project, so it costs tokens whether or not it is relevant. It therefore holds
> only what the model **cannot** derive: this machine's environment, the owner's
> non-obvious policies, and workflows that a specific past failure justifies.
>
> Everything a current model already does by default was removed — see
> `docs/ABLATION.md` for the deleted list, the reasoning, and the re-add rule
> (**a rule earns its way back only after the same mistake happens twice, and it
> comes back as a hook first, prompt text last**).

## Response Style & Language

- **Match the user's language** — 優先使用繁體中文. Code, JSON, paths, shell
  commands, error messages and API docs stay in English.
- Concise and direct: no preamble, no trailing summary of what was just read.
- If you don't know, say so. Never guess.

## Branch & Git Discipline

⚠️ **NON-NEGOTIABLE — also enforced by `branch-guard.sh`.**

- **Never edit, commit, or push from `master`/`main`.** Work on
  `feature/<description>`, push, open a PR. Never force-push to master/main.
- **Never run `git add` / `commit` / `push` / `rebase` / `reset` without explicit
  authorization** — the user saying "commit this" / "push this", or running
  `/precommit` or `/ship`. Writing files is not authorization to commit them.
- Never bypass a failing gate with `--no-verify`.
- **Exception:** a project's own CLAUDE.md may document a different workflow.
- Commit messages tell the **why**: ≤50-char summary, blank line, body wrapped at
  72 explaining why it was needed and any gotchas.

## Shell Environment & Credentials

- zsh on macOS. Capture both streams: `cmd > /tmp/out 2>&1` — don't discard
  stderr with `2>/dev/null` unless you mean it.
- `$GITLAB_TOKEN` / `$GITLAB_NPM_TOKEN` are loaded from the macOS Keychain by
  `.zshrc` and are always present in a shell session.
- **`glab` CLI is NOT installed.** Use
  `curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN"` + `jq` for every GitLab API
  call, and always filter with `jq` rather than dumping raw JSON.
- For git push auth, read the `git-push` skill.
- Never commit secrets. If one was committed, **rotate it** — a "remove secret"
  commit does not help, git history is permanent.

## Verifying Against Screenshots

Screenshots are the least reliable source in the room.

1. **Vision Echo** — before drawing any conclusion from an image, list each field
   you read as `field_name | value_read` and let the user confirm.
2. **Never assume IDs or relationships** — confirm them with a query.
3. If a screenshot conflicts with the DB or the logs, **the DB wins.**

## Two Failure Modes Worth Naming

- **Don't average conflicting patterns.** When two existing patterns contradict,
  pick one (more recent / better tested / explicitly preferred), say why, and flag
  the other for cleanup. A blended line follows no coherent rule.
- **Skipped is not passed.** "Done" is wrong if any step was skipped; "tests pass"
  is wrong if any test was skipped. When confidence is below certain, name the
  specific gap rather than hedging with "should" or "generally".

## Tests Encode Why, Not What

A test that cannot fail when the business rule changes is not a test. Assert that
`calculateDiscount()` honours the regional rule — not that it returns a number.
