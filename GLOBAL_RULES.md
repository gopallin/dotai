# AI CLI Global Rules

## Response Style
- Match the user's language in every reply.
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

## ClickUp API Writing Rules
- **Cards maintained by me** → Write directly using API. I handle formatting; users should not manually edit descriptions in the UI.
- **Cards manually formatted by users** → Explicitly notify me NOT to touch the description; users maintain these themselves.
Reason: ClickUp API overwrites the entire description. Manual UI formatting (like `/header` blocks) will be lost when the API writes markdown.

## Scope Discipline
- Do not add features, refactor, or "improve" beyond what was asked.
- No unnecessary comments, docstrings, or type annotations on unchanged code.
- No error handling for impossible scenarios.
- No abstractions for one-time use.

## Investigation & Agent Strategy
- **Mandatory Sub-Agent**: For codebase exploration, bug hunting, service tracing, or module auditing, **always** spawn a sub-agent (e.g., `codebase_investigator` or Task Agent) instead of sequential manual tool use.
- **Context Isolation**: Sub-agents must read raw files in their own isolated context and return a synthesized summary, ensuring the main context remains dedicated to implementation or the final fix.
- **Complexity Thresholds**: Transition to a sub-agent immediately if:
  - Deep dependency analysis (> 3 layers) is required.
  - Wide-ranging searches (> 10 files) are needed.
  - Manual exploration (Grep/Read/Glob) exceeds 5 steps in a single session (enforced by `PreToolUse` hook).
