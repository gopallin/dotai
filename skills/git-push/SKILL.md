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

### Option A: SSH Keys (Recommended — Already Configured!)

You're using SSH key authentication, which is **more secure than tokens**:

```bash
# Check if SSH keys exist (you already have them)
ls -la ~/.ssh/id_rsa

# SSH keys should already be added to GitHub/GitLab
# When pushing via SSH (git@github.com:...), no additional setup needed!
```

This skill automatically detects SSH and handles it correctly.

### Option B: Token Authentication (Keychain)

If you prefer HTTPS token authentication:

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

### 2. Configure Git (Already Done for SSH!)

If using SSH (your current setup — no action needed):
```bash
# Your remotes already use SSH
git remote -v
# Should show: git@github.com:... (not https://...)
```

If switching to HTTPS tokens:
```bash
# Enable macOS Keychain as credential helper
git config --global credential.helper osxkeychain

# Optional: Add URL-specific remapping
git config --global url."https://oauth2:GITLAB_TOKEN@gitlab.com/".insteadOf "https://gitlab.com/"
git config --global url."https://GITHUB_TOKEN@github.com/".insteadOf "https://github.com/"
```

### 3. Verify Setup

For SSH (current):
```bash
# Check remote URLs
git remote -v

# Verify SSH key works
ssh -T git@github.com
ssh -T git@gitlab.com
```

For Keychain tokens:
```bash
# Check Git config
git config --global --list | grep credential

# Test token retrieval
security find-generic-password -s "gitlab-token" -w
security find-generic-password -s "github-token" -w
```

---

## Workflow: Automatic Detection (SSH or Keychain)

When user initiates a push:

### Step 1: Detect Remote Platform & Auth Method

```bash
# Get remote URL
REMOTE_URL=$(git config --get remote.origin.url)

# Determine platform and auth method
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

# Detect auth method
if [[ "$REMOTE_URL" == git@* ]]; then
  AUTH_METHOD="SSH"
  echo "🔐 Using SSH key authentication"
elif [[ "$REMOTE_URL" == https://* ]]; then
  AUTH_METHOD="HTTPS (Keychain token)"
  echo "🔐 Using HTTPS token from Keychain"
fi
```

### Step 2: Validate Credentials

**If SSH:**
```bash
# SSH keys are automatic — no validation needed
# Git will use ~/.ssh/id_rsa or SSH agent
echo "✅ SSH key ready for $PLATFORM"
```

**If HTTPS:**
```bash
# Retrieve token from Keychain
TOKEN=$(security find-generic-password -s "$TOKEN_KEY" -w 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo "❌ $PLATFORM token not found in Keychain"
  echo "   Please run: security add-generic-password -s '$TOKEN_KEY' ..."
  exit 1
fi

# Set token environment variable
if [ "$PLATFORM" = "GitLab" ]; then
  export GITLAB_TOKEN="$TOKEN"
elif [ "$PLATFORM" = "GitHub" ]; then
  export GITHUB_TOKEN="$TOKEN"
fi

echo "✅ Retrieved $PLATFORM token from Keychain"
```

### Step 3: Execute Push

```bash
# Get current branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Execute push (SSH or HTTPS with token)
git push origin "$BRANCH"
```

### Step 4: Report Result

```
✅ Pushed to $PLATFORM via $AUTH_METHOD
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

### Example 1: Push via SSH (Your Current Setup) ⭐

```
User: "Push dotai changes"

I (reading this skill):
1. Detect remote: git@github.com:gopallin/dotai.git (SSH)
2. Auth method: SSH key (~/.ssh/id_rsa)
3. Get branch: main
4. Execute: git push origin main
5. Report: ✅ Pushed main to GitHub via SSH

(No token needed — SSH key handles authentication!)
```

### Example 2: Push to GitLab via HTTPS Token

```
User: "Push these changes to GitLab"

I (reading this skill):
1. Detect remote: https://gitlab.com/company/project (HTTPS)
2. Auth method: Keychain token
3. Read gitlab-token from Keychain
4. Get branch: feature/api
5. Execute: GITLAB_TOKEN=*** git push origin feature/api
6. Report: ✅ Pushed feature/api to GitLab
```

### Example 3: Mixed Setup (SSH for GitHub, Token for GitLab)

```
Repository 1 (~/dotai on GitHub):
  Remote: git@github.com:gopallin/dotai.git
  Auth: SSH key ✅

Repository 2 (company GitLab):
  Remote: https://gitlab.com/company/project.git
  Auth: Keychain token ✅

Both work automatically!
```

### Example 4: First-Time Token Setup

```
User: "Push to GitLab"

I (reading this skill):
1. Detect remote: gitlab.com/company/project
2. Try to retrieve gitlab-token from Keychain
3. Token not found
4. Report error with setup instructions

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
