---
name: gitlab-push
description: GitLab push authentication and workflow. Automatically handles token-based authentication for pushing to GitLab repositories.
---

# GitLab Push Workflow

## When to Use

Trigger this skill whenever the user:
- Says "push to gitlab" or "push to gitlab.com"
- Asks to commit and push changes
- Mentions "git push" in the context of GitLab
- Requests publishing code to GitLab

## Setup (One-Time)

**Store your GitLab token securely:**

```bash
# Create the token file
echo "your-gitlab-token-here" > ~/.gitlab-token
chmod 600 ~/.gitlab-token

# Verify it works
cat ~/.gitlab-token
```

**Configure Git credential helper:**

```bash
git config --global credential.helper store
```

## Workflow

When user initiates a push:

1. **Check prerequisites:**
   - Verify `~/.gitlab-token` exists
   - Verify `.git` directory exists (valid repo)

2. **Set environment:**
   ```bash
   export GITLAB_TOKEN=$(cat ~/.gitlab-token)
   ```

3. **Execute push:**
   ```bash
   git push origin $(git rev-parse --abbrev-ref HEAD)
   ```

4. **Handle outcomes:**
   - ✅ Success: Confirm "Pushed to GitLab"
   - ❌ Auth failure: Suggest checking `~/.gitlab-token`
   - ❌ Network failure: Ask user to retry
   - ❌ Merge conflict: Explain pull-then-push workflow

## Token Alternatives

If user doesn't have `~/.gitlab-token`:

**Option A: SSH Key (Recommended for long-term)**
```bash
# Generate SSH key
ssh-keygen -t ed25519 -f ~/.ssh/gitlab -C "your-email@example.com"

# Add to GitLab Settings → SSH Keys

# Configure Git
git config --global core.sshCommand "ssh -i ~/.ssh/gitlab"
```

**Option B: HTTPS with Personal Access Token**
```bash
# Create at GitLab → Settings → Access Tokens
# Store in ~/.gitlab-token
echo "glpat-xxxxxxxxxxxx" > ~/.gitlab-token
chmod 600 ~/.gitlab-token
```

**Option C: HTTPS OAuth**
```bash
git push https://oauth2:$GITLAB_TOKEN@gitlab.com/user/repo.git
```

## Error Handling

| Error | Cause | Solution |
|---|---|---|
| `fatal: could not read Password` | Token not set | Run `cat ~/.gitlab-token` to verify |
| `Permission denied` | Invalid token | Regenerate token in GitLab Settings |
| `fatal: not a git repository` | Not in repo directory | Check working directory is a Git repo |
| `[rejected]` on push | Branch behind remote | `git pull` before pushing |

## Example Interactions

### Interaction 1: Simple Push

```
User: "Push the changes"

You (reading this skill):
1. Check ~/.gitlab-token exists ✓
2. Set GITLAB_TOKEN environment
3. Execute: git push origin main
4. Report: "✅ Pushed to main"
```

### Interaction 2: Push Different Branch

```
User: "Push feature-x to GitLab"

You:
1. Detect current branch is feature-x
2. Execute: git push origin feature-x
3. Report: "✅ Pushed feature-x to GitLab"
```

### Interaction 3: First-Time Setup

```
User: "Push to GitLab"

You (detect ~/.gitlab-token missing):
"I need to set up GitLab authentication first.

Run:
  echo 'your-token' > ~/.gitlab-token
  chmod 600 ~/.gitlab-token

Then I can push for you."
```

## Integration with Other Skills

This skill works with:
- **precommit.md** - Run `/precommit` before pushing
- **gitlab-integration.md** - General GitLab workflow context

Typical flow:
```
1. User makes changes
2. /precommit (lint + test)
3. git commit
4. gitlab-push (this skill) → git push
```

## Notes

- ⚠️ **Never print or log the token value**
- ⚠️ **Always use `chmod 600` on token files**
- ⚠️ **If token is leaked, regenerate immediately in GitLab**
- Token file should be in `.gitignore` (usually automatic via `~` home directory)
- For CI/CD pipelines, use `CI_JOB_TOKEN` instead of personal token
