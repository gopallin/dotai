---
name: git-push
description: Automatic authentication for Git push to GitLab and GitHub. Detects remote URL and applies correct Keychain-stored token.
---

# Git Push Workflow (GitLab + GitHub)

## When to Use

Trigger this skill whenever the user:
- Says "push to gitlab" or "push to github"
- Asks to commit and push changes
- Mentions "git push" for either platform
- Requests publishing code

## One-Time Setup

### 1. Store Tokens in macOS Keychain (Secure)

```bash
# Store GitLab token (company account)
security add-generic-password -s "gitlab-token" \
  -a "$(whoami)" -w "glpat-xxxxxxxxxxxx"

# Store GitHub token (personal account)
security add-generic-password -s "github-token" \
  -a "$(whoami)" -w "ghp_xxxxxxxxxxxx"

# Verify both are stored
security find-generic-password -s "gitlab-token" -w
security find-generic-password -s "github-token" -w
```

### 2. Configure Git for Auto-Authentication

```bash
# Enable macOS Keychain as credential helper
git config --global credential.helper osxkeychain

# Optional: Add URL-specific remapping (if using HTTPS)
git config --global url."https://oauth2:GITLAB_TOKEN@gitlab.com/".insteadOf "https://gitlab.com/"
git config --global url."https://GITHUB_TOKEN@github.com/".insteadOf "https://github.com/"
```

### 3. Verify Setup

```bash
# Check Git config
git config --global --list | grep credential

# Test token retrieval
security find-generic-password -s "gitlab-token" -w
security find-generic-password -s "github-token" -w
```

---

## Workflow: Automatic URL Detection + Token Selection

When user initiates a push:

### Step 1: Detect Remote Platform

```bash
# Get remote URL
REMOTE_URL=$(git config --get remote.origin.url)

# Determine platform
if [[ "$REMOTE_URL" == *"gitlab.com"* ]] || [[ "$REMOTE_URL" == *"gitlab"* ]]; then
  PLATFORM="GitLab"
  TOKEN_KEY="gitlab-token"
elif [[ "$REMOTE_URL" == *"github.com"* ]] || [[ "$REMOTE_URL" == *"github"* ]]; then
  PLATFORM="GitHub"
  TOKEN_KEY="github-token"
else
  echo "❓ Unknown Git platform. Remote: $REMOTE_URL"
  exit 1
fi
```

### Step 2: Retrieve Token from Keychain

```bash
# Retrieve token securely from Keychain
TOKEN=$(security find-generic-password -s "$TOKEN_KEY" -w 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo "❌ $PLATFORM token not found in Keychain"
  echo "   Please run setup: security add-generic-password -s '$TOKEN_KEY' ..."
  exit 1
fi

echo "✅ Retrieved $PLATFORM token from Keychain"
```

### Step 3: Set Environment & Push

```bash
# Set token environment variable
if [ "$PLATFORM" = "GitLab" ]; then
  export GITLAB_TOKEN="$TOKEN"
elif [ "$PLATFORM" = "GitHub" ]; then
  export GITHUB_TOKEN="$TOKEN"
fi

# Get current branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Execute push
git push origin "$BRANCH"
```

### Step 4: Report Result

```
✅ Pushed to $PLATFORM
   Branch: $BRANCH
   Remote: $REMOTE_URL
```

---

## Platform-Specific Details

### GitLab (Company Account)

**Token Type:** Personal Access Token (PAT)
- Create at: GitLab → Settings → Access Tokens
- Scopes needed: `api`, `read_repository`, `write_repository`
- Stored as: `gitlab-token`

**Example Push:**
```
Remote: https://gitlab.com/company/project.git
Branch: feature/implement-api
Action: git push origin feature/implement-api
Auth: Uses GITLAB_TOKEN from Keychain
```

### GitHub (Personal Account)

**Token Type:** Personal Access Token (Fine-grained)
- Create at: GitHub → Settings → Developer settings → Personal access tokens
- Permissions needed: `contents:read/write`, `pull_requests:read/write`
- Stored as: `github-token`

**Example Push:**
```
Remote: https://github.com/username/dotai.git
Branch: main
Action: git push origin main
Auth: Uses GITHUB_TOKEN from Keychain
```

---

## Error Handling

| Error | Cause | Solution |
|---|---|---|
| `Keychain not found` | Token not stored | Run: `security add-generic-password -s "gitlab-token" ...` |
| `Permission denied (publickey)` | Wrong token for platform | Check token permissions in GitLab/GitHub settings |
| `fatal: not a git repository` | Not in repo | `cd` to repository directory |
| `[rejected]` on push | Branch behind remote | `git pull` before pushing |
| `Unknown Git platform` | Unrecognized remote URL | Check remote: `git remote -v` |

---

## Interaction Examples

### Example 1: Push to GitLab (Company)

```
User: "Push these changes to GitLab"

I (reading this skill):
1. Detect remote: gitlab.com/company/project
2. Read gitlab-token from Keychain
3. Get branch: feature/api
4. Execute: GITLAB_TOKEN=*** git push origin feature/api
5. Report: ✅ Pushed feature/api to GitLab
```

### Example 2: Push to GitHub (Personal)

```
User: "Push dotai changes"

I (reading this skill):
1. Detect remote: github.com/username/dotai
2. Read github-token from Keychain
3. Get branch: main
4. Execute: GITHUB_TOKEN=*** git push origin main
5. Report: ✅ Pushed main to GitHub
```

### Example 3: First-Time User (Missing Token)

```
User: "Push to GitLab"

I (reading this skill):
1. Try to retrieve gitlab-token from Keychain
2. Token not found
3. Report error with setup instructions

Setup:
security add-generic-password -s "gitlab-token" \
  -a "$(whoami)" -w "glpat-xxxxxxxxxxxx"
```

---

## Security Best Practices

### ✅ DO:
- Store tokens in macOS Keychain (encrypted at rest)
- Use fine-grained PATs with minimal permissions
- Rotate tokens periodically (every 90 days recommended)
- Never commit tokens to version control
- Use SSH keys as alternative to HTTPS tokens

### ❌ DON'T:
- Store tokens in plain text files
- Share tokens across devices
- Use tokens with excessive permissions
- Keep expired tokens in Keychain
- Print token values in logs

### Keychain-Specific Tips:
```bash
# Update token if expired
security delete-generic-password -s "gitlab-token"
security add-generic-password -s "gitlab-token" \
  -a "$(whoami)" -w "new-token-value"

# List all stored tokens
security find-generic-password -l | grep "token"

# Delete a token
security delete-generic-password -s "gitlab-token"
```

---

## Integration with Other Skills

Works with:
- **precommit.md** - Run `/precommit` before pushing
- **plan.md** - Design before implementation
- **stop-guard.sh** - Prevents stopping without push confirmation

Typical flow:
```
1. Make code changes
2. /precommit (lint + test)
3. git commit
4. git-push skill (auto-detect + auth + push)
```

---

## Troubleshooting

**Q: How do I know which token is being used?**
A: I will report the platform detected and which token is being retrieved:
```
Detected: GitLab (gitlab.com)
Using: gitlab-token from Keychain
```

**Q: Can I use SSH instead of HTTPS tokens?**
A: Yes! Configure SSH keys in your Git config:
```bash
git config --global core.sshCommand "ssh -i ~/.ssh/gitlab -o IdentitiesOnly=yes"
```

**Q: What if Keychain asks for password every time?**
A: macOS is asking to access Keychain. Click "Always Allow" to cache credentials for 15 minutes. This is normal security behavior.

**Q: How do I rotate tokens?**
A:
```bash
# 1. Generate new token in GitLab/GitHub
# 2. Update in Keychain
security delete-generic-password -s "gitlab-token"
security add-generic-password -s "gitlab-token" -a "$(whoami)" -w "new-token"
# 3. Test: git push
```

---

## Notes

- 🔐 Tokens are encrypted in macOS Keychain, not stored as plain text
- 🤖 This skill automatically detects which platform (GitLab or GitHub) and uses the correct token
- 📱 Works with multi-account setup: different repos can push to different platforms
- 🔄 Compatible with all Claude, Gemini, and Codex CLI tools (once installed)
