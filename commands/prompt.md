---
name: prompt
description: Step-by-step prompt wizard — after /prompt, ask the user one question at a time to fill each part, then emit a structured, AI-ready, token-efficient task prompt via prompt-template.sh, and optionally chain into /plan.
---

# /prompt — Step-by-Step Prompt Wizard

After `/prompt` is invoked, you run a **guided wizard**: ask the user **one
question at a time**, wait for each answer, then move to the next step. When
every step is answered, assemble the finished prompt from
`~/.claude/commands/prompt-template.sh` and show it.

## Hard rules (do not violate)

1. **One question per message.** Ask a single question, then STOP and wait for
   the user's reply. Never ask the next question until they answer.
2. **Number every question** as `第 N/{total} 步 — <question>` so the user sees
   the progress. `{total}` = the number of steps that still need an answer; `N`
   counts the questions you actually ask, **sequentially** (第 1/{total}, then
   第 2/{total}, …) — never show a gap like 第 4/5.
3. **Never show the user a blank template or any `<...>` placeholders.** They
   fill the prompt by answering your questions, NOT by editing a skeleton.
4. **Do not run the script until ALL steps are answered.** Run it exactly once,
   at the end.
5. For each question, **offer a recommended example answer**, and **search the
   codebase to self-answer when you can** (especially Related Files) — propose
   what you found and let the user confirm or correct, rather than asking blind.

## Steps to collect

Use this fixed order. `feature`/`refactor` have 5 steps; `bugfix` has 6.

1. **Type** — `feature` | `bugfix` | `refactor`. If the user already passed it in
   the `/prompt` arguments, treat it as answered (don't ask), and exclude it from
   `{total}`.
2. **Goal** — one concrete sentence. (If given in the arguments, skip it.)
3. **(bugfix only) Symptom & key differential** — the reproduction condition AND
   the single most diagnostic fact in one go (e.g. "works on machine A, fails on
   B"). Collect it here so it isn't drip-fed later.
4. **Related files** — paths or `@file`. Offer to grep for them and propose
   candidates if the user is unsure.
5. **Out of scope / must-not-touch** — ask plainly: *"有沒有不要碰的?(特定檔案、
   migration、DB 資料、相鄰模組)"*. This is the highest-value step — it prevents
   mid-task interrupts.
6. **Done when + how to verify** — *"怎樣算完成,用什麼指令驗證?"* — a concrete
   observable result plus a command (e.g. `yarn test:unit` /
   `php artisan test --filter=X`).

If arguments already supplied the type and/or goal, acknowledge them in one line
("類型: feature、目標: …,我們從第 1/N 步開始"), recompute `{total}` for the
remaining steps, and number from there.

## Assemble (only after the last step)

1. Run the template once with the collected goal and files:

   ```
   bash ~/.claude/commands/prompt-template.sh <type> "<goal>" "<files>"
   ```

2. Replace every `<...>` hint in its output with the user's answers; delete any
   checklist line or hint that doesn't apply. Do not add sections the script
   didn't emit, and do not restate the template anywhere else.

3. Present the finished prompt inside a single fenced code block, prefixed with
   `✅ 組好了,這是你的 prompt:` — no other preamble.

## Then offer /plan

After showing the prompt, ask: *"要我把它帶進 `/plan` 設計,還是你直接拿去用?"*
- plan → hand the finished prompt to the `/plan` workflow as its initial input.
- otherwise → stop; the prompt block is the deliverable.
