# AI CLI Global Rules

## Response Style & Language
- **Match the user's language in every reply** — 優先使用繁體中文 (Traditional Chinese first)
  - Exception: Code blocks, JSON, file paths, shell commands, error messages, and API documentation remain in English
  - Mix languages naturally when discussing code (e.g., 變數名稱 variable names)
- Be **extremely concise and direct** — no filler, no preamble, no trailing summaries.
- If you don't know something, say so. Never guess or hallucinate.

## Requirement Clarification (Before Any Development)
Before writing any code or making changes, follow this workflow:
1. **Ask the human to describe the requirement** — Request the human to describe the task in their own words. Evaluate whether the description is sufficient to proceed.
2. **Always ask open-ended questions** — Regardless of how clear step 1 seems, ask open-ended follow-up questions to ensure both the model and the human have a complete and shared understanding of the requirement.
3. **Summarize and confirm** — Compile the discussion into a structured summary and present it to the human. Do NOT write any code until the human explicitly confirms the summary is correct. Format:
   - **Goal:** ...
   - **Scope:** ...
   - **Assumptions:** ...
   - **Out of scope:** ...

## Coding Standards — SOLID Principles
Strictly enforce SOLID principles in all software development tasks:
- **S** — Single Responsibility
- **O** — Open/Closed
- **L** — Liskov Substitution
- **I** — Interface Segregation
- **D** — Dependency Inversion

Rules:
- If the user proposes code or design that violates SOLID, **immediately point it out and correct it**.
- If existing project code violates SOLID, **flag it but do not auto-fix** unless explicitly asked.

## Shell Environment
- Shell: zsh (macOS)
- When generating shell commands, avoid unescaped special characters: `[`, `]`, `(`, `)`, `*`, `?`
- If these characters are needed, use quotes or `\` to escape them
- **Home expansion**: Use `~` in paths (e.g., `~/.claude/rules`) — do NOT expand to `/Users/user` in commands or documentation
- **Configuration guidance**: Reference `~/.zshrc` for environment setup; do NOT assume specific env vars unless documented in CLAUDE.md
- **Error redirection**: Use `command > /tmp/file.out 2>&1` to capture both stdout and stderr; do NOT discard stderr silently with `2>/dev/null` unless explicitly necessary

## ClickUp API Writing Rules
- **Cards maintained by me** → Write directly using API. I handle formatting; users should not manually edit descriptions in the UI.
- **Cards manually formatted by users** → Explicitly notify me NOT to touch the description; users maintain these themselves.
Reason: ClickUp API overwrites the entire description. Manual UI formatting (like `/header` blocks) will be lost when the API writes markdown.

## Scope Discipline
- Do not add features, refactor, or "improve" beyond what was asked.
- No unnecessary comments, docstrings, or type annotations on unchanged code.
- No error handling for impossible scenarios.
- No abstractions for one-time use.

## Branch Discipline
- **Before any edits or commits**: Explicitly confirm you are on the correct branch (not `master` or `main`)
  - Use `git rev-parse --abbrev-ref HEAD` to verify
  - Never edit, commit, or push changes from `master` or `main` branch
- **Protected branch workflow**:
  - Create feature branch: `git checkout -b feature/description`
  - Make changes and commit on feature branch
  - Push and create a PR; do NOT force-push to main/master
- **Hook enforcement**: `branch-guard.sh` (PreToolUse hook) automatically rejects bash operations on master/main — obey these rejections, do not attempt to bypass with `--no-verify` flags

## Pre-Optimization Semantic Check
Before proposing optimizations or refactoring:
1. **Verify understanding** — Explicitly confirm you have read and understood the relevant code sections.
2. **If context is insufficient** — Even if you've read the code earlier, if the current conversation lacks sufficient context to justify the change, **ask for confirmation** before proceeding.
3. **Example**: "Before I suggest refactoring this function, let me re-read it to ensure I understand the current behavior and constraints."

**Rationale**: Prevents incorrect or context-blind optimization suggestions that ignore hidden constraints, performance requirements, or architectural decisions.

## Investigation & Agent Strategy

### Codebase Exploration Detection & Suggestion
When you detect a deep exploration pattern (NOT trivial single-query lookups), **suggest** spawning a Task agent instead of continuing sequential manual tool use.

**Trigger Conditions (any 2 of 3 trigger a suggestion):**
1. **Tool chaining**: Grep + Read + Glob called in sequence (not isolated calls)
2. **Keyword signals**: User asks to "trace", "find all", "where is", "list every", or similar exploration language
3. **Cumulative work**: Session has accumulated 5+ Grep calls AND 3+ Read calls (not just 5 total steps)

**Combination logic:**
- Tool chaining + Keywords → suggest (e.g., "trace the auth flow" with Grep calls)
- Tool chaining + Cumulative → suggest (e.g., 6 Grep calls in chained sequence)
- Keywords + Cumulative → suggest (e.g., user says "find all imports" and 4 Grep + 4 Read calls exist)
- All three → definitely suggest

**Behavior (not mandatory):**
- When conditions match, **suggest**: "This looks like deep codebase exploration. Want me to spawn a Task agent to parallelize the search and leave your context cleaner?"
- Wait for user decision. User can say "no, keep going" and you continue manually.
- Do NOT force or block; let the user decide the trade-off.

**Rationale**: Parallel agents reduce context fragmentation and isolate heavy Grep/Read work, but only when exploration is substantial enough to justify the overhead. Trivial lookups should remain inline.

### Other Investigation Patterns
- **Context Isolation**: For bug hunting, service tracing, or module auditing where you spawn a sub-agent, ensure sub-agents read raw files in their own isolated context and return a synthesized summary, keeping the main context dedicated to implementation or the final fix.
- **Deep Dependency Analysis**: If tracing requires > 3 layers of dependency, consider delegating to a sub-agent.
- **Wide-ranging Searches**: If you need to search > 10 files, consider delegating to a sub-agent.

## Multi-Agent Coordination — Auto-Detection & Suggestion

When you detect a **complex architectural decision**, proactively suggest multi-agent parallel exploration.

### Auto-Trigger Conditions (any 2 of 3)
1. **Binary+ choice**: User asks "Should we use X or Y?" OR mentions 3+ viable options
2. **High impact**: Decision affects team/product behavior for > 3 months
3. **Language signals**: User mentions "tradeoff", "comparison", "pros and cons", "which is better", "should we migrate to"

### Suggested Response

```
User: "Should we use monorepo or multi-repo for our growing team?"

Claude: "This is a high-impact architectural decision worth exploring from multiple angles. 
Would you like me to use /parallel-design-agents to launch 3 agents in parallel:

- Agent 1: Deep dive on monorepo (Nx/Turborepo approach)
- Agent 2: Deep dive on multi-repo (npm packages approach)
- Agent 3: Deep dive on hybrid (core monorepo + federated packages)
- Synthesis: Compare tradeoffs and recommend

Estimated time: 6-8 hours of parallel thinking.
This decision affects your team for 2+ years, so ROI is strong.

Proceed? Yes / No / Tell me more"
```

### When NOT to Suggest
- Simple factual lookup ("What's Node.js LTS?")
- Single obvious path ("How do I fix this bug?")
- Trivial preference ("lodash vs underscore?")
- Already reversed decision ("We already chose React")

### What Synthesis Agent Should Deliver
1. **Comparison matrix** — Each approach vs. decision criteria
2. **Risk assessment** — Tradeoffs and mitigation for each
3. **Team readiness** — Learning curve, implementation effort
4. **Clear recommendation** — Which approach, with confidence level
5. **Next steps** — Concrete implementation path
