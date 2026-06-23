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

    # --- Bash read-only pass-through ---
    # Whitelist of safe read-only commands.
    SAFE_COMMANDS="^ls|^grep|^cat|^find|^git status|^git log|^git diff|^pwd|^du|^df|^stat|^file|^which|^type"
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

        # Other read-only commands: allow unless they redirect stdout to a FILE
        # (`> file` / `>> file` = a real write masquerading as a safe read).
        # The regex matches a `>`/`>>` whose preceding char is neither a digit
        # nor `&`, so stderr operations (`2>&1`, `2>/dev/null`, `>&2`) pass.
        if echo "$EXECUTING_CMD" | grep -qiE "$SAFE_COMMANDS" \
           && ! echo "$EXECUTING_CMD" | grep -qE '(^|[^0-9&])>>?($|[^&])'; then
            exit 0
        fi
    else
        # Could not determine the command (no stdin payload / parse failure).
        # Fail OPEN rather than trap the agent on master: this hook only matches
        # the Bash tool, so the worst case is one non-git command slipping
        # through, whereas failing closed blocks EVERY bash — including the
        # `git checkout` needed to leave master. The commit/push protection then
        # rests on the agent's own branch-discipline rules.
        echo "⚠️  branch-guard: could not parse tool input; allowing (fail-open)." >&2
        exit 0
    fi

    # --- Edit/Write/MultiEdit doc pass-through ---
    # Documentation edits (*.md, anything under .claudedocs/) are allowed on
    # master/main — mirrors stop-guard, which treats docs as non-code changes.
    if [ -n "$FILE_PATH" ]; then
        case "$FILE_PATH" in
            *.md|*/.claudedocs/*) exit 0 ;;
        esac
    fi
    # --------------------------------------

    cat >&2 << 'EOF'
❌ dotai Branch Protection
━━━━━━━━━━━━━━━━━━━━━━━━━
You are currently on 'master' or 'main' branch.
Cannot edit, commit, or push from protected branches.

To proceed:
1. Create a feature branch: git checkout -b feature/your-feature
2. Make changes there
3. Push and create a PR

If you intentionally need to edit main:
- Use git checkout to switch to main manually
- Make changes
- Use: git push --force-with-lease origin main (NOT RECOMMENDED)
EOF
    exit 2
fi

exit 0
