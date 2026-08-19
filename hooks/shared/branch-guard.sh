#!/usr/bin/env bash
#
# branch-guard.sh
# Prevents accidental edits/commits/pushes to master/main branches.
# Triggered on PreToolUse for Bash and Edit/Write/MultiEdit tools.
#
# Strategy: Check current git branch (reliable) rather than parsing the command
# (which may not be available in every hook context).
#
# Tool input is read from stdin (Claude Code's PreToolUse JSON: {tool_input:{...}})
# with the legacy CLAUDE_TOOL_INPUT env var as a fallback.
#

# Only check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi

# Get current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

# Allow all branches except master/main
if [ "$CURRENT_BRANCH" = "master" ] || [ "$CURRENT_BRANCH" = "main" ]; then
    # --- Resolve the tool input (Bash command and/or Edit/Write file_path) ---
    #
    # Claude Code delivers the PreToolUse payload as JSON on stdin; older/other
    # CLIs may set the legacy CLAUDE_TOOL_INPUT env var instead. Read stdin FIRST
    # (the authoritative source) and fall back to the env var only when stdin is
    # empty. Parse `.tool_input // .` so we tolerate both the full event shape
    # ({tool_input:{...}}) and a bare tool_input object. This parse MUST succeed
    # or the safe-command whitelist below cannot fire — which previously trapped
    # the agent on master (even `git checkout`, the documented escape, blocked)
    # because the old code read $CLAUDE_TOOL_INPUT (often the full event) and ran
    # `jq '.command'` against it, always yielding empty.
    EXECUTING_CMD=""
    FILE_PATH=""
    if command -v jq >/dev/null 2>&1; then
        STDIN_JSON=$(cat 2>/dev/null)
        TOOL_INPUT=""
        if [ -n "$STDIN_JSON" ]; then
            TOOL_INPUT=$(printf '%s' "$STDIN_JSON" | jq -c '.tool_input // .' 2>/dev/null)
        fi
        if [ -z "$TOOL_INPUT" ] || [ "$TOOL_INPUT" = "null" ]; then
            if [ -n "$CLAUDE_TOOL_INPUT" ]; then
                TOOL_INPUT=$(printf '%s' "$CLAUDE_TOOL_INPUT" | jq -c '.tool_input // .' 2>/dev/null)
            fi
        fi
        if [ -n "$TOOL_INPUT" ] && [ "$TOOL_INPUT" != "null" ]; then
            EXECUTING_CMD=$(printf '%s' "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null)
            FILE_PATH=$(printf '%s' "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
        fi
    fi

    # --- Bash write-command block (blacklist, NOT whitelist) ---
    #
    # This used to be a 14-prefix read-only WHITELIST
    # (^ls|^grep|^cat|^find|^git status|^git log|^git diff|^pwd|^du|^df|^stat|
    #  ^file|^which|^type) and it was strictly worse than useless:
    #
    #   • `wc -l f | tail -40`  → blocked (`wc` simply wasn't on the list)
    #   • `cd /x && ls -l`      → blocked (the command starts with `cd`)
    #   • anything using head/jq/rg/sed -n/awk/sort/comm → blocked
    #
    # A read-only command cannot modify the repository, so every one of those
    # rejections was capability loss for zero safety gain. What this hook actually
    # exists to prevent is *changing* master/main, so it now enumerates the ways a
    # shell command can write and allows everything else.
    #
    # Deliberately NOT blocked: package managers (`npm install`, `composer
    # install`). They mostly touch gitignored trees, and blocking them re-creates
    # the over-blocking this rewrite removed. Lockfile churn on master/main is
    # caught at commit time by the git-write patterns below.
    #
    # KNOWN LIMIT — a blacklist is not exhaustive, and this one is not claimed to be.
    # A write routed through an interpreter (`python -c "open('f','w')"`, a script
    # that writes internally, an editor invocation) is NOT detected. The whitelist it
    # replaced did not catch those either, and it additionally blocked dozens of
    # harmless reads. What this guard actually buys is stopping the *accidental*
    # `git commit` / `echo >` on the wrong branch; it is not a sandbox and must not
    # be described as one.
    WRITE_CMDS="git[[:space:]]+(commit|push|add|reset|rebase|merge|cherry-pick|revert|stash|am|apply|restore|rm|mv|clean|tag|update-ref|filter-branch)"
    WRITE_CMDS="$WRITE_CMDS|(^|[[:space:];&|])(tee|rm|mv|truncate|dd|ln|shred)[[:space:]]"
    WRITE_CMDS="$WRITE_CMDS|(sed|perl|ruby)[[:space:]]+[^|;]*-i|awk[[:space:]]+[^|;]*-i[[:space:]]*inplace"
    if [ -n "$EXECUTING_CMD" ]; then
        # Escape hatch: `git checkout` / `git switch` must ALWAYS be allowed on
        # master/main so the agent can leave (otherwise every bash is blocked,
        # including the checkout needed to escape). Allow them UNCONDITIONALLY —
        # ignoring redirects (`2>&1`) and global flags (`git -C <dir> checkout`),
        # both of which previously trapped the agent. awk finds the real git
        # subcommand by skipping global options and their arguments.
        GIT_SUBCMD=$(printf '%s\n' "$EXECUTING_CMD" | awk '
          { for(i=1;i<=NF;i++) if($i=="git"){ i++;
              while(i<=NF){ t=$i;
                if(t ~ /^-/){ if(t=="-C"||t=="-c"||t=="--git-dir"||t=="--work-tree"||t=="--namespace"||t=="--exec-path") i++; i++; continue }
                print t; exit } } }')
        case "$GIT_SUBCMD" in checkout|switch) exit 0 ;; esac

        # Redirection to a FILE is a write masquerading as anything else.
        # The regex matches a `>`/`>>` whose preceding char is neither a digit nor
        # `&`, so stderr operations (`2>&1`, `2>/dev/null`, `>&2`) still pass.
        #
        # It runs against a QUOTE-STRIPPED copy, because a `>` inside a string
        # literal is data, not an operator. Observed false positive 2026-08-19: the
        # read-only  echo "s3.ap-northeast-1.amazonaws.com -> "  was blocked, since
        # `-` is neither a digit nor `&` and so `->` matched. Note the fix has to be
        # quote awareness rather than special-casing `->`: unquoted, `echo a->b`
        # really does redirect into a file named `b`.
        #
        # SCRUBBED is deliberately byte-identical to the line in glab-guard.sh and
        # secret-guard.sh — same name, same sed — because this is the third copy of
        # one idea and reviewer-rules L1 ("one concern, one source") flags exactly
        # that. Keeping the copies identical is the cheap half of the fix; hoisting
        # them into a sourced helper is a separate change, since a new installed file
        # carries the parity obligation across all three CLI installers plus a test.
        #
        # KNOWN LIMIT — two sed substitutions are not a shell parser. An escaped
        # quote inside a quoted span (`"a\" > f"`) mis-pairs and leaves the `>`
        # exposed, so that case still blocks. That is the safe direction to fail.
        SCRUBBED=$(printf '%s' "$EXECUTING_CMD" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
        if echo "$SCRUBBED" | grep -qE '(^|[^0-9&])>>?($|[^&])'; then
            BLOCK_REASON="redirects output to a file"
        # DELIBERATELY the RAW command, not $SCRUBBED. The asymmetry with the
        # redirect check above is intentional: a write *command* inside quotes is
        # normally a real invocation (`bash -c 'git push'`, `ssh host 'git commit'`),
        # so stripping quotes here would silently drop detection that works today.
        # The cost is that `echo "run git commit"` still blocks — rarer, and safe.
        elif echo "$EXECUTING_CMD" | grep -qiE "$WRITE_CMDS"; then
            BLOCK_REASON="runs a write/history-modifying command"
        else
            # Not a write — allow. This is the common case now.
            exit 0
        fi
    elif [ -z "$FILE_PATH" ]; then
        # Neither a command NOR a file path — the payload was unparsable.
        # Fail OPEN rather than trap the agent on master: failing closed would
        # block EVERY tool call, including the `git checkout` needed to leave
        # master. The commit/push protection then rests on the agent's own
        # branch-discipline rules.
        #
        # This branch MUST NOT swallow the Edit/Write case. It used to be a plain
        # `else`, and since an Edit payload carries `file_path` but no `command`,
        # every Edit/Write/MultiEdit on master/main hit this fail-open `exit 0`
        # and the file-path check below was unreachable. The hook's headline
        # promise — "prevents accidental edits to master/main" — was therefore
        # only ever true for Bash.
        echo "⚠️  branch-guard: could not parse tool input; allowing (fail-open)." >&2
        exit 0
    fi

    # --- Edit/Write/MultiEdit pass-through ---
    # Documentation edits (*.md, anything under .claudedocs/) are allowed on
    # master/main — mirrors stop-guard, which treats docs as non-code changes.
    #
    # `.git/` internals are allowed for a different reason: git refuses to track
    # anything inside a `.git` directory, so writing there cannot dirty the branch,
    # cannot be committed, and cannot enter history — the three things this guard
    # exists to prevent. Blocking it only breaks local-state workflows: /handoff
    # writes its ignore patterns to `.git/info/exclude`, and on main that write was
    # rejected with "edits a non-documentation file", which is both true and useless.
    # The `.git/*` and `.git` arms (no leading `*/`) are not redundant: Claude Code
    # sends an absolute file_path, but nothing in the contract guarantees that for
    # every CLI, and a relative `.git/info/exclude` would miss a `*/.git/*`-only
    # pattern and be blocked. `*/.git` (and `.git`) covers the submodule/worktree
    # case where `.git` is a FILE containing a `gitdir:` pointer, not a directory.
    if [ -n "$FILE_PATH" ]; then
        case "$FILE_PATH" in
            *.md|*/.claudedocs/*) exit 0 ;;
            */.git/*|*/.git|.git/*|.git) exit 0 ;;
        esac

        # A path OUTSIDE this repo's working tree cannot dirty the branch, cannot be
        # committed, and cannot enter history — exactly the argument already accepted
        # for `.git/` above. Observed false positive 2026-08-19: a write to the
        # session scratchpad under /private/tmp/... was blocked merely because cwd
        # happened to be a repo sitting on main. Blocking that protects nothing; the
        # branch has no relationship to the file.
        #
        # Both sides are resolved to PHYSICAL paths before comparing. On macOS the
        # same directory is reachable through symlinks (/tmp → /private/tmp,
        # /var → /private/var, and mktemp -d hands back the symlinked form), so a
        # textual prefix test would miss real in-repo paths and fail OPEN — the
        # dangerous direction. The target usually does not exist yet (Write creates
        # it), so resolution walks up to the deepest existing ancestor directory and
        # re-appends the remainder.
        #
        # If the working tree cannot be located (bare repo, or cwd inside .git), fall
        # through to the block below. Refusing to guess is safer than allowing.
        REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -n "$REPO_ROOT" ] && REPO_ROOT_P=$(cd "$REPO_ROOT" 2>/dev/null && pwd -P); then
            FILE_ABS="$FILE_PATH"
            case "$FILE_ABS" in /*) ;; *) FILE_ABS="$PWD/$FILE_ABS" ;; esac
            SCAN_DIR=$(dirname "$FILE_ABS")
            SCAN_REST=$(basename "$FILE_ABS")
            while [ ! -d "$SCAN_DIR" ] && [ "$SCAN_DIR" != "/" ] && [ "$SCAN_DIR" != "." ]; do
                SCAN_REST="$(basename "$SCAN_DIR")/$SCAN_REST"
                SCAN_DIR=$(dirname "$SCAN_DIR")
            done
            SCAN_DIR_P=$(cd "$SCAN_DIR" 2>/dev/null && pwd -P) || SCAN_DIR_P="$SCAN_DIR"
            case "$SCAN_DIR_P/$SCAN_REST" in
                "$REPO_ROOT_P"/*) ;;   # inside the working tree — keep blocking
                *) exit 0 ;;           # outside — cannot affect this branch
            esac
        fi

        BLOCK_REASON="edits a non-documentation file ($FILE_PATH)"
    fi
    # --------------------------------------

    cat >&2 << EOF
❌ dotai Branch Protection
━━━━━━━━━━━━━━━━━━━━━━━━━
Current branch is '$CURRENT_BRANCH', and this command ${BLOCK_REASON:-modifies the repository}.

Read-only commands are allowed here — only writes are blocked. To proceed:
1. git checkout -b feature/your-feature   (always permitted, even on master/main)
2. Make changes there
3. Push and open a PR

If you genuinely must change master/main, switch to it yourself outside the agent.
EOF
    exit 2
fi

exit 0
