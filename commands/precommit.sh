#!/usr/bin/env bash
#
# precommit.sh — quality verification pipeline
# Called by the /precommit slash command (commands/precommit.md).
#
# Human-readable output:
#   ✅ step_name (Xs)          — step passed
#   ❌ step_name (Xs) - reason — step failed; script exits immediately
#   ## Overall: ✅ PASS        — all steps passed
#   PRECOMMIT_STATUS=PASS / PRECOMMIT_STATUS=FAIL
#   PRECOMMIT_MODE=<laravel|vue|node|shell|generic|project>
#
# ── Machine contract with stop-guard.sh: the receipt file, NOT the transcript ──
#
# stop-guard used to grep the session transcript for the literal strings
# `/precommit` and `PRECOMMIT_STATUS=PASS`. That made the gate self-satisfying:
# Claude Code injects a blocked hook's own stderr back into the transcript as a
# user message, and stop-guard's messages contain BOTH literals ("Run /precommit
# …", "…ensure it outputs PRECOMMIT_STATUS=PASS"). So the first block made
# Layer 2a pass forever, the second made Layer 2b pass forever — the gate could
# block at most twice per session and then stood permanently open. Prose that
# merely *mentioned* /precommit satisfied it too, as did an agent typing the
# PASS line by hand without running anything.
#
# The fix: this script writes a receipt only it can write, and stop-guard reads
# that. The receipt is keyed to a fingerprint of the working tree, so a PASS
# earned before further edits does not authorise stopping after them.
#
# ── Why there is no "cannot detect stack → FAIL" arm any more ─────────────────
#
# Observed 2026-08-21, in a repo with no artisan, no package.json and no
# tests/*.test.sh: `/precommit` reported `❌ Could not detect tech stack` and
# FAIL. stop-guard then (correctly) refused the stop, and the agent, with no
# passable gate in reach, **wrote its own `.claude/commands/precommit.sh` into
# that repo and graded its own work with it**. An unrunnable gate does not stay
# unrun; it gets replaced by whatever the agent can satisfy.
#
# Two changes close that off:
#   1. An undetectable stack now falls back to `generic` mode — real,
#      stack-independent checks (conflict markers, parse errors, credentials)
#      that can pass honestly, instead of a dead end.
#   2. A project-local override is honoured only when **git tracks it**, so a
#      script invented mid-session cannot be used to grade that same session.
#
# Generic mode reports PASS while running no build and no tests, which is close
# to the line drawn by GLOBAL_RULES §"Skipped is not passed". It stays on the
# right side of it only because it never hides that: the "no build/test
# pipeline" note is printed on the PASS path, and the receipt records
# `mode=generic`. Nothing was skipped — there was nothing there to run. If a
# project does have a pipeline, teach detection about it; do not let generic
# mode stand in for it.

set -uo pipefail

# ── Receipt ───────────────────────────────────────────────────────────────────

# Fingerprint of everything a commit from here would capture: HEAD, the set of
# pending paths, AND their content. Any subsequent edit, stage, or new untracked
# file changes it.
#
# ⚠️ stop-guard.sh recomputes this with an identical block. The two are locked
# together by tests/precommit.test.sh, which runs this script and then the real
# guard against the same tree — if the algorithms drift, that test fails. They
# are duplicated rather than sourced because the two files install into
# different trees (and different trees again on Codex and agy), so there is no
# path both can rely on.
precommit_tree_fingerprint() {
  {
    git rev-parse HEAD 2>/dev/null
    git status --porcelain -uall 2>/dev/null
    # Status lines alone are not enough: re-editing a file that was ALREADY
    # dirty leaves porcelain byte-identical, so a PASS survived arbitrary
    # further edits — the exact thing the receipt exists to prevent. Caught by
    # tests/precommit.test.sh. --binary so a second edit to a binary file
    # registers too, instead of collapsing to "Binary files differ".
    git diff HEAD --binary 2>/dev/null
    # git diff says nothing about untracked content, so hash it directly.
    git ls-files --others --exclude-standard -z 2>/dev/null \
      | xargs -0 shasum -a 256 2>/dev/null
  } | shasum -a 256 | cut -d' ' -f1
}

# Written to the git dir (not the worktree): never committed, per-clone, and
# `git rev-parse --git-dir` resolves correctly inside linked worktrees, which a
# hardcoded "$REPO_ROOT/.git" does not.
write_receipt() {
  local status="$1" mode="${2:-${STACK:-unknown}}" gitdir
  gitdir=$(git rev-parse --git-dir 2>/dev/null) || return 0  # not a repo — nothing to gate
  {
    echo "status=${status}"
    echo "mode=${mode}"
    echo "tree=$(precommit_tree_fingerprint)"
    echo "ts=$(date +%s)"
  } > "${gitdir}/dotai-precommit"
}

# ── Project-local override — tracked only ─────────────────────────────────────
#
# A project may ship its own pipeline at .claude/commands/precommit.sh. It runs
# instead of the stack detection below, but ONLY if git tracks it: an untracked
# script is indistinguishable from one the current session just invented, and a
# gate an agent wrote for itself is not a gate.
#
# This script never creates that file, and neither should anything else. If the
# stack is not detectable, generic mode below is the answer — not a new script
# in someone else's repo.
#
# The override needs no knowledge of the receipt protocol: exit 0 means pass,
# non-zero means fail, and this wrapper records the receipt either way. If it
# does print its own PRECOMMIT_STATUS= line, that line is honoured — but a
# declared PASS with a non-zero exit is treated as FAIL.

if [[ -z "${DOTAI_PRECOMMIT_DISPATCHED:-}" ]]; then
  export DOTAI_PRECOMMIT_DISPATCHED=1   # an override that copies this file cannot loop
  _root=$(git rev-parse --show-toplevel 2>/dev/null) || _root=""
  _override="${_root:-.}/.claude/commands/precommit.sh"
  if [[ -n "$_root" && -f "$_override" ]]; then
    if git -C "$_root" ls-files --error-unmatch ".claude/commands/precommit.sh" >/dev/null 2>&1; then
      echo "Using project-local pipeline: .claude/commands/precommit.sh"
      echo ""
      _log=$(mktemp -t dotai-precommit)
      bash "$_override" 2>&1 | tee "$_log"
      _rc=${PIPESTATUS[0]}
      _declared=$(sed -n 's/^PRECOMMIT_STATUS=//p' "$_log" | tail -1)
      rm -f "$_log"
      if [[ -n "$_declared" ]]; then
        _status="$_declared"
        if [[ "$_status" == "PASS" && "$_rc" -ne 0 ]]; then
          echo ""
          echo "❌ Project pipeline declared PASS but exited ${_rc} — recording FAIL."
          _status=FAIL
        fi
      else
        [[ "$_rc" -eq 0 ]] && _status=PASS || _status=FAIL
        echo ""
        if [[ "$_status" == PASS ]]; then echo "## Overall: ✅ PASS"; else echo "## Overall: ❌ FAIL"; fi
        echo "PRECOMMIT_STATUS=${_status}"
        echo "PRECOMMIT_MODE=project"
      fi
      write_receipt "$_status" project
      [[ "$_status" == PASS ]] || exit 1
      exit 0
    fi
    echo "⚠️  Ignoring UNTRACKED .claude/commands/precommit.sh."
    echo "    A project pipeline has to be committed to count. If this file was"
    echo "    just generated to satisfy the gate, delete it — generic mode below"
    echo "    is the supported fallback."
    echo ""
  fi
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

run_step() {
  local name="$1"; shift
  local start end elapsed output rc
  start=$(date +%s)
  output=$("$@" 2>&1)
  rc=$?
  end=$(date +%s)
  elapsed=$(( end - start ))
  if [[ $rc -eq 0 ]]; then
    echo "✅ ${name} (${elapsed}s)"
  else
    echo "❌ ${name} (${elapsed}s)"
    echo "$output" | head -30
    echo ""
    echo "## Overall: ❌ FAIL"
    echo "PRECOMMIT_STATUS=FAIL"
    echo "PRECOMMIT_MODE=${STACK}"
    write_receipt FAIL
    exit 1
  fi
}

# Same failure shape as run_step, for a step that cannot run inside run_step's
# command substitution because it has to set globals in this shell (see
# laravel_resolve_runner).
abort_step() {
  echo "❌ $1 (0s)"
  shift
  printf '%s\n' "$@"
  echo ""
  echo "## Overall: ❌ FAIL"
  echo "PRECOMMIT_STATUS=FAIL"
  echo "PRECOMMIT_MODE=${STACK}"
  write_receipt FAIL
  exit 1
}

# ── Shell-repo steps ──────────────────────────────────────────────────────────
#
# Both return non-zero on failure so run_step reports ❌ and aborts. Never add
# `|| true` here: a step that cannot fail is not a gate, and a pipeline that
# always prints PASS is worse than no pipeline — it launders "skipped" into
# "passed", which is the one outcome dotai exists to prevent.

shell_syntax() {
  local f rc=0 list
  list=$(git ls-files '*.sh' 2>/dev/null) || list=""
  [[ -n "$list" ]] || list=$(find . -name '*.sh' -not -path './.git/*' 2>/dev/null)
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    bash -n "$f" || { echo "syntax error: $f"; rc=1; }
  done <<< "$list"
  return $rc
}

shell_tests() {
  local t rc=0 out files
  shopt -s nullglob
  files=(tests/*.test.sh)
  shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "no tests/*.test.sh found — refusing to report PASS on zero tests"
    return 1
  fi
  for t in "${files[@]}"; do
    if out=$(bash "$t" 2>&1); then
      echo "  ✓ ${t}  $(printf '%s' "$out" | tail -1)"
    else
      echo "  ✗ ${t}"
      printf '%s\n' "$out" | tail -15
      rc=1
    fi
  done
  echo "  ${#files[@]} test file(s) executed"
  return $rc
}

# ── Generic steps — no project pipeline, no project config ────────────────────
#
# Scope: only what is pending in the working tree, i.e. exactly what a commit
# from here would capture. Checking the whole repo would make the pipeline's
# runtime a function of repo size and would fail on pre-existing dirt nobody
# touched — the same mistake stop-guard's Layer 1b already corrects for.
#
# Nothing here writes to the repo. That rules out `python -m py_compile`
# (it drops __pycache__/) — the `ast.parse` form leaves no artifact.

GENERIC_FILES=()

generic_collect() {
  local f
  # -uall so files inside a new untracked directory are listed individually;
  # plain porcelain collapses them to "dir/", which the -f test then discards.
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ -f "$f" ]] || continue          # skips deletions and directory entries
    GENERIC_FILES+=("$f")
  done < <(git status --porcelain -uall 2>/dev/null \
             | sed 's/^.\{3\}//' | sed 's/.* -> //' | sed 's/^"//; s/"$//' | sort -u)
}

generic_conflict_markers() {
  local f rc=0
  [[ ${#GENERIC_FILES[@]} -gt 0 ]] || return 0
  for f in "${GENERIC_FILES[@]}"; do
    if grep -IqE '^(<{7}|>{7})( |$)' "$f" 2>/dev/null; then
      echo "unresolved merge conflict markers: $f"
      rc=1
    fi
  done
  return $rc
}

generic_syntax() {
  local f rc=0 checked=0 skipped=0
  if [[ ${#GENERIC_FILES[@]} -eq 0 ]]; then
    echo "  no pending files to parse"
    return 0
  fi
  for f in "${GENERIC_FILES[@]}"; do
    case "$f" in
      *.sh|*.bash)
        bash -n "$f" 2>&1 || { echo "syntax error: $f"; rc=1; }
        checked=$(( checked + 1 )) ;;
      *.json)
        if command -v jq >/dev/null 2>&1; then
          jq empty "$f" >/dev/null 2>&1 || { echo "invalid JSON: $f"; rc=1; }
          checked=$(( checked + 1 ))
        else
          skipped=$(( skipped + 1 ))
        fi ;;
      *.py)
        if command -v python3 >/dev/null 2>&1; then
          python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" >/dev/null 2>&1 \
            || { echo "syntax error: $f"; rc=1; }
          checked=$(( checked + 1 ))
        else
          skipped=$(( skipped + 1 ))
        fi ;;
      *)
        skipped=$(( skipped + 1 )) ;;
    esac
  done
  echo "  ${checked} parsed, ${skipped} skipped (no parser for that file type)"
  return $rc
}

generic_secret_scan() {
  local f rc=0 lines pat
  # Same shapes secret-redact.sh scrubs from tool output. Here the point is to
  # stop them entering a commit, where deleting them later achieves nothing.
  pat='(github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{30,}|glpat-[A-Za-z0-9_-]{16,}|sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
  [[ ${#GENERIC_FILES[@]} -gt 0 ]] || return 0
  for f in "${GENERIC_FILES[@]}"; do
    lines=$(grep -InE "$pat" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ',')
    if [[ -n "$lines" ]]; then
      # File and line only — never the match. Echoing it would put the
      # credential in the transcript, which is the one thing that cannot be
      # undone (see CLAUDE.md §Credential handling).
      echo "possible credential in ${f} at line(s): ${lines%,}"
      rc=1
    fi
  done
  return $rc
}

# The three generic steps as one callable unit. Two callers reach it: the
# `generic)` arm, and the node/vue arm when the repo declares no build and no
# test script. Inlining the trio in both places is how the L1/L2/L3 checklist
# came to exist twice in `ground` and `ship` and then drift — one concern, one
# source.
generic_steps() {
  generic_collect
  echo "Pending files inspected: ${#GENERIC_FILES[@]}"
  echo ""
  run_step "conflict_markers" generic_conflict_markers
  run_step "file_syntax"      generic_syntax
  run_step "secret_scan"      generic_secret_scan
}

# ── Laravel steps — resolve the toolchain instead of assuming it ──────────────
#
# The laravel arm used to be two hard-coded lines, `./vendor/bin/pint` then
# `php artisan test`, and both assumptions break on a real Laravel repo:
#
#   * The linter may be phpcs (squizlabs/php_codesniffer + phpcs.xml) rather than
#     pint. Observed 2026-08-24 in nxl-shipping-server: composer requires
#     php_codesniffer, the repo ships phpcs.xml, and there is no pint.json and no
#     vendor/bin/pint.
#   * `php` may not be on the host at all, because the whole toolchain lives in
#     Docker. Same repo: `command -v php` finds nothing.
#
# The consequence was worse than a wrong result. lint_fix failed at second zero,
# wrote a FAIL receipt, and stop-guard then refused every stop for the rest of
# the session with no reachable fix — the same dead end that generic mode was
# added to remove, reappearing inside a *detected* stack. An unpassable gate does
# not stay unrun; it gets worked around.
#
# So: resolve pint-or-phpcs and host-or-container, print what was resolved so a
# wrong pick is visible rather than silent, and when the choice is genuinely
# ambiguous, fail with the candidates named instead of guessing.
#
# bash 3.2 throughout (macOS /bin/bash): no mapfile, no associative arrays.

# Command prefix for php / vendor binaries. Empty array = run on the host.
LARAVEL_RUN=()
LARAVEL_RUN_WHERE=""
LARAVEL_LINTER=""
LARAVEL_LINTER_DESC=""
LARAVEL_PHP_FILES=()
LARAVEL_WARN_FILE=""

# Running containers with this repo's root bind-mounted. Matched by mount source,
# not by container name: a name convention is a guess, a mount is a fact.
laravel_docker_candidates() {
  local root name
  command -v docker >/dev/null 2>&1 || return 0
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [[ -n "$root" ]] || return 0
  for name in $(docker ps --format '{{.Names}}' 2>/dev/null); do
    if docker inspect -f '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' "$name" 2>/dev/null \
         | grep -qxF "$root"; then
      echo "$name"
    fi
  done
}

# Where this repo's root is mounted inside $1, so the container's working
# directory matches the repo-relative paths we pass to phpcs and artisan.
laravel_mount_dest() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  docker inspect \
    -f "{{range .Mounts}}{{if eq .Source \"${root}\"}}{{.Destination}}{{end}}{{\"\n\"}}{{end}}" \
    "$1" 2>/dev/null | grep -v '^$' | head -1
}

# A project may pin its runner in .claude/precommit.env as
#   PRECOMMIT_PHP_RUNNER=docker exec -w /var/www/app app
#
# Unlike .claude/commands/precommit.sh, this file is honoured whether or not git
# tracks it, and the difference is not an inconsistency. A project *pipeline* can
# declare PASS, so an untracked one is indistinguishable from a gate the current
# session invented for itself. A runner is only *where* the real linter and the
# real suite execute — it cannot manufacture a pass, and a wrong value makes the
# steps fail rather than succeed. Requiring a commit for it would just push
# people back to exporting a variable every session, which is how the gate
# became unpassable in the first place.
laravel_runner_from_project_env() {
  local root f
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  f="${root:-.}/.claude/precommit.env"
  [[ -f "$f" ]] || return 0
  # Only this one key, and no shell evaluation of the file: it is config, not code.
  sed -n 's/^[[:space:]]*PRECOMMIT_PHP_RUNNER[[:space:]]*=[[:space:]]*//p' "$f" \
    | sed 's/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//' | tail -1
}

laravel_resolve_runner() {
  local cands n name dest from_env

  # 1. Explicit override always wins. Deliberately word-split: the value is a
  #    command prefix, e.g. PRECOMMIT_PHP_RUNNER='docker exec -w /app api'.
  if [[ -n "${PRECOMMIT_PHP_RUNNER:-}" ]]; then
    LARAVEL_RUN=(${PRECOMMIT_PHP_RUNNER})
    LARAVEL_RUN_WHERE="PRECOMMIT_PHP_RUNNER (${PRECOMMIT_PHP_RUNNER})"
    return 0
  fi

  # 1b. Then the project's pinned runner.
  from_env=$(laravel_runner_from_project_env)
  if [[ -n "$from_env" ]]; then
    LARAVEL_RUN=(${from_env})
    LARAVEL_RUN_WHERE=".claude/precommit.env (${from_env})"
    return 0
  fi

  # 2. A host php is the simple case and stays the default.
  if command -v php >/dev/null 2>&1; then
    LARAVEL_RUN=()
    LARAVEL_RUN_WHERE="host php ($(command -v php))"
    return 0
  fi

  # 3. No host php: the toolchain is containerised.
  cands=$(laravel_docker_candidates)
  n=$(printf '%s' "$cands" | grep -c . )

  if [[ "$n" -eq 0 ]]; then
    LARAVEL_RESOLVE_ERR="no php on the host, and no running container has this repo bind-mounted.
    Start the project's containers, or pin a runner in .claude/precommit.env:
      PRECOMMIT_PHP_RUNNER=docker exec -w /var/www/app app"
    return 1
  fi

  if [[ "$n" -gt 1 ]]; then
    # Several containers mount the same host directory. Any pick would be a
    # guess about which one owns the app, and running the suite in the wrong
    # container is a false PASS — the one outcome this pipeline must not produce.
    LARAVEL_RESOLVE_ERR="no php on the host, and ${n} running containers mount this repo:
$(printf '%s' "$cands" | sed 's/^/      - /')
    Which of them owns this app cannot be inferred from a mount, and running the
    suite in the wrong container is a false PASS. Pin it in .claude/precommit.env:
      PRECOMMIT_PHP_RUNNER=docker exec -w $(laravel_mount_dest "$(printf '%s' "$cands" | head -1)") $(printf '%s' "$cands" | head -1)"
    return 1
  fi

  name=$(printf '%s' "$cands" | head -1)
  dest=$(laravel_mount_dest "$name")
  if [[ -z "$dest" ]]; then
    LARAVEL_RESOLVE_ERR="container ${name} mounts this repo but its mount destination could not be read"
    return 1
  fi

  if ! docker exec -w "$dest" "$name" php -v >/dev/null 2>&1; then
    LARAVEL_RESOLVE_ERR="container ${name} mounts this repo at ${dest} but has no working php"
    return 1
  fi

  LARAVEL_RUN=(docker exec -w "$dest" "$name")
  LARAVEL_RUN_WHERE="docker exec ${name} (repo at ${dest})"
  return 0
}

laravel_resolve_linter() {
  local f
  if [[ -f "./vendor/bin/pint" ]]; then
    LARAVEL_LINTER="pint"
    LARAVEL_LINTER_DESC="pint (vendor/bin/pint)"
    return 0
  fi
  if [[ -f "./vendor/bin/phpcs" ]]; then
    for f in phpcs.xml phpcs.xml.dist; do
      if [[ -f "$f" ]]; then
        LARAVEL_LINTER="phpcs"
        LARAVEL_LINTER_DESC="phpcs (${f}, pending .php files only)"
        return 0
      fi
    done
  fi
  LARAVEL_RESOLVE_ERR="no linter found: neither vendor/bin/pint nor vendor/bin/phpcs+phpcs.xml.
    Run composer install, or add one of them. A Laravel repo with no linter is not
    something this pipeline will paper over."
  return 1
}

# Only the .php files a commit from here would capture. Whole-repo phpcs would
# make runtime a function of repo size and fail on pre-existing dirt nobody
# touched — the same scoping the generic steps already use.
laravel_collect_php() {
  local f
  LARAVEL_PHP_FILES=()
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    case "$f" in *.php) [[ -f "$f" ]] && LARAVEL_PHP_FILES[${#LARAVEL_PHP_FILES[@]}]="$f" ;; esac
  done < <(git status --porcelain -uall 2>/dev/null | sed 's/^...//' | sed 's/.* -> //')
}

# Run a command through the resolved prefix. A function rather than
# "${LARAVEL_RUN[@]}" at each call site because bash 3.2 (macOS /bin/bash) treats
# an empty array's [@] expansion as an unbound variable under `set -u`, so the
# host-php case — the common one — aborted with "LARAVEL_RUN[@]: unbound
# variable". Caught by tests/precommit.test.sh.
laravel_run() {
  if [[ ${#LARAVEL_RUN[@]} -eq 0 ]]; then
    "$@"
  else
    "${LARAVEL_RUN[@]}" "$@"
  fi
}

# Added/changed line numbers for one pending file, one per line. A file that HEAD
# does not know (new or untracked) counts in full.
laravel_added_lines() {
  local f="$1"
  if git rev-parse --verify -q HEAD >/dev/null 2>&1 \
     && git cat-file -e "HEAD:$f" 2>/dev/null; then
    git diff -U0 HEAD -- "$f" 2>/dev/null | awk '
      /^@@/ {
        if (match($0, /\+[0-9]+(,[0-9]+)?/)) {
          spec  = substr($0, RSTART + 1, RLENGTH - 1)
          n     = split(spec, p, ",")
          start = p[1] + 0
          count = (n > 1 ? p[2] + 0 : 1)
          for (i = 0; i < count; i++) print start + i
        }
      }'
  else
    awk '{ print NR }' "$f" 2>/dev/null
  fi
}

# phpcs lints whole files, so pointing it at the pending files reports every
# legacy violation in them too. Observed 2026-08-24 in nxl-shipping-server: a
# change to three lines of BixolonService.php surfaced a PSR2 error on line 28,
# which the change never touched — and gating on that is the "fail on
# pre-existing dirt nobody touched" mistake the generic steps already avoid by
# scoping to pending files. Scoping to pending *files* is not enough here.
#
# So findings are attributed to added/changed lines: an error on a line this
# change introduced fails the step, anything else is reported and not gated.
# That keeps the step a real gate — it can still fail, on your own lines — which
# is the line `|| true` would have crossed.
laravel_lint() {
  local csv keys f line type own=0 legacy=0 warn=0 rest
  if [[ "$LARAVEL_LINTER" == "pint" ]]; then
    laravel_run ./vendor/bin/pint
    return $?
  fi

  if [[ ${#LARAVEL_PHP_FILES[@]} -eq 0 ]]; then
    echo "no pending .php files to lint"
    return 0
  fi

  # --basepath=. so the report's paths are repo-relative and comparable to the
  # git-derived ones, even when phpcs runs inside a container.
  csv=$(laravel_run ./vendor/bin/phpcs --report=csv --basepath=. \
          "${LARAVEL_PHP_FILES[@]}" 2>&1)

  # phpcs exits non-zero merely for *having* findings, so its status cannot be
  # used. A genuine invocation failure (bad standard, PHP fatal) is caught by the
  # header being absent instead — never swallowed.
  if ! printf '%s' "$csv" | head -1 | grep -q '^File,Line,Column,Type,'; then
    echo "phpcs did not produce a CSV report — invocation failed:"
    printf '%s\n' "$csv" | head -20
    return 1
  fi

  keys=$(mktemp -t dotai-phpcs-keys)
  for f in "${LARAVEL_PHP_FILES[@]}"; do
    laravel_added_lines "$f" | sed "s|^|${f}:|"
  done > "$keys"

  while IFS='|' read -r f line type rest; do
    [[ -n "$f" ]] || continue
    if [[ "$type" == "error" ]]; then
      if grep -qxF "${f}:${line}" "$keys"; then
        own=$((own + 1))
        echo "  ✗ ${f}:${line} ${rest}"
      else
        legacy=$((legacy + 1))
      fi
    else
      warn=$((warn + 1))
    fi
  done < <(printf '%s\n' "$csv" \
            | sed -nE 's/^"([^"]*)",([0-9]+),[0-9]+,(error|warning),"?(.*)$/\1|\2|\3|\4/p')

  rm -f "$keys"

  # run_step swallows a passing step's output, so counts reached on the PASS path
  # would otherwise be invisible. Hand them back through a file.
  [[ -n "$LARAVEL_WARN_FILE" ]] \
    && printf 'warn=%s legacy=%s' "$warn" "$legacy" > "$LARAVEL_WARN_FILE"

  if [[ "$own" -gt 0 ]]; then
    echo ""
    echo "${own} phpcs error(s) on lines this change added or modified."
    return 1
  fi
  return 0
}

laravel_test() {
  laravel_run php artisan test
}

# ── Node/Vue steps — resolve the runner and the script names, don't assume ────
#
# This branch used to be three hardcoded lines: `yarn lint:fix`, `yarn build`,
# `yarn test:unit`. Two ways that reported a quality failure when nothing had
# actually been checked:
#   - an npm-only repo died at second zero with "yarn: command not found"
#   - a repo whose scripts are named `test` (not `test:unit`) died on a missing
#     script — the runner exits non-zero for those, so it looked like a real bug
# Both are the pipeline being wrong about the project rather than the project
# being broken, and in the receipt they are indistinguishable from a genuine FAIL.
#
# So: take the runner from the lockfile, and run only scripts the project
# actually declares. This never silently narrows the gate — if the repo declares
# neither a build- nor a test-shaped script that is a FAIL, and whatever did run
# is printed by name, so a PASS can never be read as "everything was checked".

# Sets NODE_PM and NODE_PM_SRC. Two outputs, so it assigns rather than echoes:
# building the "(from …)" half as a nested command substitution inside the echo
# swallowed the closing paren — the header printed "Runner: yarn (from yarn.lock"
# and the test asserting the full string was the only thing that noticed.
NODE_PM=""
NODE_PM_SRC=""
node_resolve_pm() {
  if   [[ -f pnpm-lock.yaml    ]]; then NODE_PM=pnpm; NODE_PM_SRC="pnpm-lock.yaml"
  elif [[ -f yarn.lock         ]]; then NODE_PM=yarn; NODE_PM_SRC="yarn.lock"
  elif [[ -f package-lock.json ]]; then NODE_PM=npm;  NODE_PM_SRC="package-lock.json"
  elif [[ -f bun.lockb         ]]; then NODE_PM=bun;  NODE_PM_SRC="bun.lockb"
  elif command -v npm >/dev/null 2>&1; then NODE_PM=npm; NODE_PM_SRC="no lockfile — defaulted"
  else NODE_PM=""; NODE_PM_SRC="none available"
  fi
}

# Does package.json declare this script? Uses node so a `scripts` key that is
# absent, null, or malformed answers "no" instead of crashing the pipeline.
node_has_script() {
  node -e 'try{const s=(require("./package.json").scripts)||{};process.exit(s[process.argv[1]]?0:1)}catch(e){process.exit(1)}' "$1" 2>/dev/null
}

# First declared script from a preference-ordered candidate list; empty if none.
node_pick_script() {
  local c
  for c in "$@"; do
    if node_has_script "$c"; then printf '%s' "$c"; return 0; fi
  done
  printf ''
}

# ── Tech stack detection ──────────────────────────────────────────────────────

if [[ -f "artisan" ]]; then
  STACK="laravel"
elif [[ -f "package.json" ]] && ls vite.config.* >/dev/null 2>&1; then
  STACK="vue"
elif [[ -f "package.json" ]]; then
  STACK="node"
elif compgen -G "tests/*.test.sh" >/dev/null 2>&1; then
  # A shell-tooling repo (dotai itself is one). Without this branch the pipeline
  # fell through to generic mode, so /precommit could not gate the very project
  # whose purpose is gating — and dotai's own tests/*.test.sh were never run by
  # its own quality gate.
  STACK="shell"
else
  STACK="generic"
fi

if [[ "$STACK" == "generic" ]]; then
  echo "Detected stack: generic (no artisan, package.json, or tests/*.test.sh)"
else
  echo "Detected stack: ${STACK}"
fi
echo ""

# ── Run stack-specific steps ──────────────────────────────────────────────────

case "$STACK" in
  laravel)
    LARAVEL_RESOLVE_ERR=""
    laravel_resolve_runner || abort_step "php_runner" "$LARAVEL_RESOLVE_ERR"
    laravel_resolve_linter || abort_step "lint"       "$LARAVEL_RESOLVE_ERR"
    laravel_collect_php

    # Printed before the steps, not inside them: run_step swallows a passing
    # step's output, and "lint passed" without saying *which* linter ran where is
    # the same claim as "something ran somewhere".
    echo "Runner: ${LARAVEL_RUN_WHERE}"
    echo "Linter: ${LARAVEL_LINTER_DESC}"
    echo "Pending .php files: ${#LARAVEL_PHP_FILES[@]}"
    echo ""

    LARAVEL_WARN_FILE=$(mktemp -t dotai-precommit-warn)
    run_step "lint" laravel_lint
    if [[ -s "$LARAVEL_WARN_FILE" ]]; then
      _w=$(sed -n 's/.*warn=\([0-9]*\).*/\1/p' "$LARAVEL_WARN_FILE")
      _l=$(sed -n 's/.*legacy=\([0-9]*\).*/\1/p' "$LARAVEL_WARN_FILE")
      if [[ "${_w:-0}" != "0" || "${_l:-0}" != "0" ]]; then
        echo "   ↳ not gated: ${_w:-0} warning(s), ${_l:-0} error(s) on lines this"
        echo "     change did not touch. phpcs lints whole files; only your own"
        echo "     added/modified lines gate here."
      fi
    fi
    rm -f "$LARAVEL_WARN_FILE"

    run_step "test" laravel_test
    ;;
  vue|node)
    node_resolve_pm
    if [[ -z "$NODE_PM" ]]; then
      echo "❌ runner (0s)"
      echo "No package manager available: no pnpm/yarn/npm/bun lockfile and npm is not on PATH."
      echo ""
      echo "## Overall: ❌ FAIL"
      echo "PRECOMMIT_STATUS=FAIL"
      echo "PRECOMMIT_MODE=${STACK}"
      write_receipt FAIL
      exit 1
    fi

    NODE_LINT=$(node_pick_script lint:fix lint typecheck type-check)
    NODE_BUILD=$(node_pick_script build)
    NODE_TEST=$(node_pick_script test:unit test)

    # Printed before the steps, not inside them: run_step swallows a passing
    # step's output, and "build passed" without naming the script that ran is
    # the same claim as "something ran somewhere".
    echo "Runner: ${NODE_PM} (from ${NODE_PM_SRC})"
    echo "Scripts: lint=${NODE_LINT:-(none declared)} build=${NODE_BUILD:-(none declared)} test=${NODE_TEST:-(none declared)}"
    echo ""

    # Neither build nor test declared → degrade to generic mode, do NOT FAIL.
    #
    # A FAIL here would be permanent: nothing the agent can do to a repo whose
    # package.json simply has no test script clears it, so stop-guard would
    # refuse every stop forever. That is the exact pressure behind the
    # 2026-08-21 incident — /precommit returned FAIL, the stop was refused, and
    # the agent wrote its own precommit script into the repo to get past the
    # gate. Generic mode is the honest floor: it states out loud that nothing
    # was built and nothing was tested, so the PASS cannot be misread.
    if [[ -z "$NODE_BUILD" && -z "$NODE_TEST" ]]; then
      echo "⚠️  package.json declares neither a build nor a test script, so this"
      echo "    mode has nothing to run. Generic checks only — see the note above"
      echo "    PASS. If the project does have a pipeline under other script"
      echo "    names, give it a tracked .claude/commands/precommit.sh."
      echo ""
      # Receipt mode follows what actually ran, not what was detected: recording
      # mode=node for a run that built and tested nothing would be the same lie
      # as a hardcoded install summary.
      STACK="generic"
      generic_steps
    else
      # `if` blocks rather than `[[ … ]] && run_step …`: the && form leaves a
      # non-zero status behind when the guard is false, which under `set -o
      # pipefail` is a trap waiting for the next person who adds `set -e`.
      if [[ -n "$NODE_LINT" ]];  then run_step "lint (${NODE_LINT})"   "$NODE_PM" run "$NODE_LINT";  fi
      if [[ -n "$NODE_BUILD" ]]; then run_step "build (${NODE_BUILD})" "$NODE_PM" run "$NODE_BUILD"; fi
      if [[ -n "$NODE_TEST" ]];  then run_step "test (${NODE_TEST})"   "$NODE_PM" run "$NODE_TEST";  fi
    fi
    ;;
  shell)
    # Printed before the step, not inside it: run_step swallows a passing step's
    # output, and "tests passed" without a count is the same claim as "no tests
    # ran". The number has to be visible on the success path too.
    shopt -s nullglob; _t=(tests/*.test.sh); shopt -u nullglob
    echo "Test files: ${#_t[@]}"
    run_step "shell_syntax" shell_syntax
    run_step "tests"        shell_tests
    ;;
  generic)
    echo "⚠️  This repo has no build or test pipeline: nothing was built and no"
    echo "    tests were run. Generic checks only — see the note above PASS."
    generic_steps
    ;;
esac

# ── Optional: LSP TypeScript typecheck ───────────────────────────────────────
#
# Runs only when ENABLE_LSP_TOOL=1 and a tsconfig.json exists in the current
# directory or any parent. Requires npx / tsc to be on PATH.
# Errors are printed but do NOT fail the pipeline (advisory only) — the full
# TypeScript build already ran in the build step above.

if [[ "${ENABLE_LSP_TOOL:-0}" == "1" ]] && git rev-parse --show-toplevel >/dev/null 2>&1; then
  TS_ROOT=$(git rev-parse --show-toplevel)
  if [[ -f "$TS_ROOT/tsconfig.json" ]] || [[ -f "tsconfig.json" ]]; then
    start=$(date +%s)
    if npx tsc --noEmit 2>&1 | head -20; then
      elapsed=$(( $(date +%s) - start ))
      echo "✅ tsc_typecheck (${elapsed}s)"
    else
      elapsed=$(( $(date +%s) - start ))
      echo "⚠️  tsc_typecheck (${elapsed}s) — type errors found (advisory, see above)"
    fi
  fi
fi

# ── All steps passed ──────────────────────────────────────────────────────────

echo ""
if [[ "$STACK" == "generic" ]]; then
  echo "NOTE: generic mode — no build ran, no tests ran, because this repo has"
  echo "      neither. This PASS covers conflict markers, parse errors and"
  echo "      credential shapes in the pending files, and nothing more."
fi
echo "## Overall: ✅ PASS"
echo "PRECOMMIT_STATUS=PASS"
echo "PRECOMMIT_MODE=${STACK}"
write_receipt PASS
