#!/usr/bin/env bash
# review-diff.sh — the review-gate reviewer's diff for a repo other than cwd.
#
# Usage: review-diff.sh <absolute repo dir> cached|head
#
# Why a script and not `Bash(git -C * diff …)`: a `*` in the middle of an allow
# rule matches ANY text, so `git -C . -c core.fsmonitor=<cmd> diff --cached …`
# matched it and ran <cmd> without a prompt — for the main agent too, since the
# rule lives in the global settings. Claude Code 2.1.309 warns about exactly
# this ("allows any option at its *"). Here the `*` is trailing and every
# argument is checked: a path that must start with `/` cannot be a git option.

set -u

usage() { echo "usage: review-diff.sh <absolute repo dir> cached|head — $1" >&2; exit 64; }

[ $# -eq 2 ] || usage "expected 2 arguments, got $#"
dir=$1
case "$dir" in /*) ;; *) usage "repo dir must be an absolute path: $dir" ;; esac
[ -d "$dir" ] || usage "not a directory: $dir"
case "$2" in
  cached) rev=--cached ;;
  head)   rev=HEAD ;;
  *)      usage "mode must be cached or head: $2" ;;
esac

# Same flags as the cwd forms: --no-ext-diff so a repo diff driver cannot run.
exec git -C "$dir" diff "$rev" --no-color --no-ext-diff
