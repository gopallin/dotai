---
name: preflight
description: Automated environment check before starting work — verifies branch, git state, env vars, and MCP status
---

# Preflight Environment Check

## When to Use

Trigger this skill whenever:
- User starts a new work session and wants to verify their environment
- User wants to quickly audit system readiness before running complex tasks
- User needs to confirm all integrations (MCP, Git, environment) are properly configured

## What It Checks

### 1. Git Branch Status
- Current branch name
- Whether branch is protected (master/main)
- Warning if on main/master

### 2. Git Working Tree State
- Uncommitted changes
- Untracked files
- Unpushed commits
- Overall cleanliness for starting new work

### 3. Environment Variables
- Required vars for project (from `.env` or CLAUDE.md config section)
- PATH configuration
- Node.js and Python versions (if relevant)

### 4. MCP Servers Status
- List configured MCP servers
- Check authentication status for each
- Identify any disabled or misconfigured servers

### 5. Claude Code Environment
- Claude Code version
- Settings.json status
- Hooks directory status
- Rules directory status

## Output Format

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Preflight Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Git Branch: feature/your-feature
✅ Git Status: Clean (no uncommitted changes)
⚠️  Environment: 1 missing var (SLACK_TOKEN)
✅ MCP Servers: 3 active, 1 auth pending
✅ Claude Code: v1.x.x

Recommendations:
- Set SLACK_TOKEN before running automation

Ready to start work.
```

## Implementation Notes

The skill should:
1. Run non-blocking checks (no installation/setup)
2. Provide actionable warnings (not just pass/fail)
3. Use color-coded output (✅ green, ⚠️ yellow, ❌ red)
4. Exit 0 on success, 1 on critical failures
5. Take < 2 seconds to complete

## One-Time Setup

No setup required — this is a read-only audit tool.

## Example Usage

```bash
# Run preflight check
/preflight

# Or with options
/preflight --verbose   # Show full MCP details
/preflight --check=git # Check only git status
```

## Related Skills

- `/plan` — Design planning before starting work
- `branch-guard.sh` — Prevents accidental pushes to main (runs automatically)
