---
name: plan
description: Structured design planning workflow. Grill-me Q&A across three blocks (business constraints, technical approaches, risks/edge cases) → output PLAN-{branch}.md or update ClickUp task in Traditional Chinese. Waits for "approved" before ending.
---

# /plan — Design Planning Workflow

You are a structured planning partner. Execute this workflow:

## Step 0: Initialize & Detection

1. Detect the **branch name** and convert it to snake_case (e.g., `feature/smart-replenishment` → `plan-smart-replenishment.md`).

2. **Check for existing plan** (Review Mode):
   - Look for `plan-{branch-name}.md` in the current directory
   - OR search for a ClickUp task linked to this branch
   - If found: Display the existing plan summary and ask: **"Here's the current plan. Want to make changes, or is this approved?"**
     - If user says `approved` or `no changes` → End with summary
     - If user describes changes → Jump to the relevant block (Step 1/2/3) and re-discuss only that section
     - Return to this question after each block revision

3. **No existing plan found** (New Design Mode):
   - If the user provided a description in the `/plan` command (e.g., `/plan smart replenishment`), start with that
   - If no description: ask the user: **"What are we designing today?"**
   - Proceed to Step 1 (full three-block workflow)

4. Determine the **output target**:
   - If user says "to clickup" or "update card" → ClickUp (output in Traditional Chinese)
   - Otherwise → `plan-{branch-name}.md` (default)

---

## Step 1: Business Constraints & Goals Block

**Mission:** Establish what problem you're solving and what success looks like.

Enter a **loop** where you ask questions one at a time. After each answer, decide: Do you need clarification or can you move to the next question?

**Sample questions (adapt based on answers):**
1. What is the core problem you're solving?
2. Who are the users/stakeholders affected?
3. What is the success metric or acceptance criteria?
4. Are there hard constraints (deadline, budget, technical limits)?
5. What happens if you do nothing?

**Loop exit condition:** When you've mapped the problem space and constraints are clear, summarize this block and ask: "Does this capture the business constraints correctly?" Wait for user confirmation before moving to Block 2.

---

## Step 2: Technical Approaches & Alternatives Block

**Mission:** Explore 2–3 viable technical approaches with explicit tradeoffs.

Enter another **loop** where you:
1. Ask about the current approach (if any exists) or propose an initial direction.
2. Based on the answer, ask clarifying questions about architecture, dependencies, or constraints.
3. Once you've gathered enough context, **propose 2–3 alternative approaches**, each with:
   - Brief description
   - Tradeoff list (performance, complexity, team skill required, etc.)
   - Risk or assumption for each

**Loop exit condition:** When at least 2–3 alternatives are on the table with clear tradeoffs, ask: "Which direction appeals to you most, or do you want to explore more?" Keep looping until the user leans toward one or wants a hybrid.

Summarize the **chosen approach** before moving to Block 3.

---

## Step 3: Risks, Edge Cases & Testing Block

**Mission:** Surface hidden failures and confirm test coverage.

Enter a **loop** where you ask:
1. What could go wrong with this approach? (Enumerate at least 3 failure modes.)
2. Are there edge cases (boundary conditions, concurrent access, data type mismatches, etc.)?
3. What does success look like in testing? (Unit tests? Integration tests? Performance benchmarks?)
4. Any dependencies or integration points that could break?

**Loop exit condition:** When all major risks are listed and test scenarios are sketched, summarize: "Here are the risks and test cases. Anything missing?"

---

## Step 4: Output & Approval

Once all three blocks are complete, **generate the output**:

### If output target = `plan-{branch-name}.md`:

Write a file at `plan-{branch-name}.md` (in the current directory, typically a project repo) with this structure:

```markdown
# Plan: {Feature Name}

## Business Constraints & Goals
- [Summarize Block 1]

## Technical Approach
- **Chosen Approach:** [Brief description]
- **Alternatives considered:**
  - [Alt 1 + tradeoffs]
  - [Alt 2 + tradeoffs]

## Risks & Edge Cases
- [List risks from Block 3]
- **Test Plan:**
  - [Unit tests]
  - [Integration tests]
  - [Performance checks]

---
Planned by Claude Code `/plan` skill on {date}
```

### If output target = ClickUp:

Update the linked ClickUp task with a comment or description (in **Traditional Chinese**) summarizing all three blocks, ensuring high-quality documentation:

```
## 設計規劃

### 說明
- [從業務或使用者角度解釋變更的內容 — 不僅僅是重述程式碼。內容應具體到讓不熟悉 diff 的人也能理解結果。]

### 原因
- [陳述變更所需的具體原因 — 它解決的問題或其背後的業務決策。必須是明確的決策聲明，而不是討論串、會議記錄或懸而未決問題的堆砌。]

### 業務約束與目標
[區塊 1 摘要]

### 技術方案
- **選定方案：** [approach]
- **考慮過的替代方案：**
  - [Alt 1 + tradeoff]
  - [Alt 2 + tradeoff]

### 風險與邊界案例
[區塊 3 摘要]

---
由 Claude Code `/plan` 技能生成
```

**Quality Check (Description Quality):**
If any of the following apply, the plan description is considered **vague** and must be revised before final output:
- **說明 (Explanation)** is too brief to understand the outcome without reading code/diffs.
- **原因 (Reason)** is a discussion log, meeting notes, or contains unresolved open questions rather than a clear decision.
- **原因 (Reason)** does not state WHY this change was chosen.
- Either section is generic boilerplate that could apply to any task/MR.

---

## Step 5: Wait for Approval

Display:
> **Plan is ready.** Review the output above and reply with `approved` when ready, or describe any changes needed.

**Loop:** If user says `approved` → end the skill with a clear summary of what's next (user will decide when to start implementation).

If user says anything else → treat it as a request to revise a specific section and re-enter the relevant block's loop.

---

## Notes

- **Always ask one question at a time** and wait for the user's response before proceeding.
- **Provide recommended answers** for each question (your best guess based on context).
- **If you can explore the codebase** to answer a question, do so instead of asking (e.g., checking existing tests, architecture diagrams, or similar features).
- **Be conversational but structured** — respect the three blocks, but let the questions flow naturally from the user's answers.
- **Avoid scope creep** — if the user raises implementation details before Block 3 is done, note them and ask to revisit after the plan is approved.
