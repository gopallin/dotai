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
        if echo "$EXECUTING_CMD" | grep -qE '(^|[^0-9&])>>?($|[^&])'; then
            BLOCK_REASON="redirects output to a file"
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
