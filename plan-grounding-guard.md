# Plan: Grounding Guard — 動手前的強制紮根閘門

> **這份文件的用途**:本檔是 grounding-guard 功能的完整開發規格與交接文件。
> 它記錄了開發緣起、資料佐證、決策過程、被否決的方案、已知風險,以及一份
> **完成度驗收清單**。未來可將本檔交給另一個 AI,依「§7 完成度驗收清單」
> 逐項檢查實作是否完成、是否符合當初決策。
>
> - Branch: `feature/grounding-guard`
> - 規劃日期: 2026-06-12
> - 規劃方式: `/plan` skill 三段式(business / technical / risks)
> - 狀態: **已 approved,尚未實作**

---

## 1. 開發緣起(Why this exists)

### 1.1 觸發來源
起點是一篇關於 **「迴圈工程 / Loop Engineering」** 的文章
(https://gist.github.com/doggy8088/5cfd0aebe2d3044907f930b7bfd29a2b,
承 Addy Osmani 觀點)。文章主張:AI coding 的槓桿點正從「怎麼下 prompt」
轉移到「怎麼設計一個自動指揮 agent 的迴圈系統」,並提出六個組件:
自動化流程、Worktrees、Skills、Plugins/Connectors、**Subagents(writer/checker 分離)**、Memory。

文章三個關鍵警告:**驗證仍需人類**、**理解力會退化**、**別淪為只按 start 鍵的人**。

### 1.2 為何不直接抄「自動化迴圈」
我們把文章對照了使用者的真實 usage data
(`~/.claude/usage-data/facets/`,76 個 session 分析檔)。結論是:
**使用者的瓶頸不是產出速度,而是品質卡在「動手前的紮根」這一步。**

因此「無人值守的自動化迴圈」會**放大**使用者的 #1 失誤(沒紮根就動手),
把單次錯誤變成規模化、無人攔截的錯誤 —— 正是文章警告的「認知投降」。

真正對症的,是文章的 **writer/checker 分離** 與 **memory** 兩個組件:
用一個獨立的 checker 在動手前強制紮根。這也正是 dotai 的核心哲學:
**「別信 AI 會做對,用 code 逼它做對」**(CLAUDE.md)。

### 1.3 資料佐證(76 個 session 的 facets 聚合)
| 失誤類型 | 總次數 | 影響 session 數 |
|---|---|---|
| **wrong_approach**(沒先讀既有 pattern 就動手) | 24 | 21 |
| **misunderstood_request** | 23 | 16 |
| **buggy_code**(沒驗資料就寫:錯 factory_id、NULL design_id、誤讀截圖) | 19 | 12 |
| user_rejected_action | 7 | 6 |
| excessive_changes | 4 | 4 |
| 謊稱工具做不到(GitLab/WebFetch) | ~3 | 3 |

「大三角」wrong_approach(24)+ misunderstood_request(23)+ buggy_code(19)
佔了全部 friction 事件的絕大多數。滿意/不滿意 ≈ 6.8:1,但**不滿意高度集中在
「沒先驗證資料就下結論」的 debug session**(EAN13 barcode、replenishment SKU)。

代表性 friction 引文(顯示反覆出現的 pattern):
- 「Claude 一開始就動手實作,**沒先研究既有 codebase pattern**,要使用者明講才去參照既有慣例」
- 「Claude 用了 **wrong factory_id(3 而非 4)**、插入 **NULL design_id** 的測試資料」
- 「Claude **反覆誤讀截圖數值**、指向錯誤的 root cause,要使用者多次糾正」

> 這正是使用者 CLAUDE.md 裡「Pre-Implementation Grounding Protocol」與
> 「Screenshot & Data Verification Protocol」想防的行為 —— 但那些規則靠 AI 自覺,
> 會被忽略。本功能的目的就是把它們從 **prompt(可被忽略)** 升級為
> **hook + subagent 的硬關卡(無法繞過)**。

---

## 2. 目標與業務約束(Block 1,已確認)

- **核心問題**:把「動手前沒紮根 / 沒驗資料」這個最大失誤,用動手前的強制閘門擋下。
- **觸發範圍**:**全域** —— 任何非 `.md` 的「每 session 首次」code 編輯前,要求紮根證據。
  - (使用者選項:全域 vs 只擋資料敏感操作 vs 全域分級 → 選**全域**)
- **強制強度**:**硬擋 `exit 2` + 明確逃生門(SKIP)**,避免誤判 deadlock。
  - (使用者選項:純硬擋 vs 硬擋+逃生門 vs 先 advisory 觀察 → 選**硬擋+逃生門**)
- **觸發單位**:**每 session 首次** code 編輯(非每次)。
- **成功標準**:
  1. 下一季 `facets` 的 wrong_approach / buggy_code 佔比下降。
  2. 閘門誤判率低到不惱人 —— 以 `SKIP` 使用頻率作為代理指標。
- **硬約束**:
  - 落在現有 dotai repo(`skills/` + `hooks/`)。
  - 跨三 CLI(claude / codex / gemini)結構相容。
  - 實作須在 feature branch(`branch-guard.sh` 擋 main)。

---

## 3. 技術方案(Block 2,已確認)

### 3.1 選定方案 — 方案 B:Checker subagent skill + hook 配對

**設計理念**:鏡像現有、已被信任的 `/precommit + stop-guard` 配對。
`stop-guard` 是「**完工前**」的閘門;grounding-guard 是它的鏡像 —— 「**動手前**」的閘門。

兩個產出物:

1. **`skills/ground.md`(`/ground` skill)**
   - 一個**用不同指令的驗證 subagent**(writer/checker 分離中的 checker)。
   - 動手前產出結構化紮根產物:
     - 參照的既有檔案路徑(stated pattern,要 1–2 個)
     - **實際驗證的資料 / IDs**(WMS 場景就跑 SQL 確認 factory_id / design_id / NULL)
     - assumptions 與 confidence
   - 結尾輸出機器可讀 marker:
     - 通過:`GROUNDING_STATUS=PASS`
     - 逃生門:`GROUNDING_STATUS=SKIP reason=<理由>`
   - marker 必須伴隨證據行(參照檔路徑 + 驗證的值),降低造假。

2. **`hooks/claude/grounding-guard.sh`(PreToolUse hook)**
   - matcher:`Edit|Write|MultiEdit`(**不含 Bash**,見 §6 #3)。
   - 邏輯:
     1. 讀 stdin JSON 取 `transcript_path` 與 `tool_input.file_path`。
     2. 非 git repo / 無 transcript → `exit 0`。
     3. 在 `main`/`master` → `exit 0`(避免與 branch-guard deadlock,比照 stop-guard Skip 1)。
     4. 本次編輯檔為 `*.md` 或 `*/.claudedocs/*` → `exit 0`(文件豁免)。
     5. 用 `/tmp/dotai_grounding_${SESSION_ID}` counter 判斷是否為本 session
        **首次非 .md code 編輯**;非首次 → `exit 0`(只擋首次)。
     6. 首次:掃 transcript 找新鮮的 `GROUNDING_STATUS=PASS` 或 `SKIP`:
        - 有 → `exit 0`(SKIP 須額外把 `reason` 寫進 log)。
        - 無 → `exit 2`,輸出「先跑 `/ground` 並確保輸出 `GROUNDING_STATUS=PASS`」。

3. **`hooks/hooks.json`**:把 grounding-guard 增掛到既有 PreToolUse(與 branch-guard 並存)。

4. **跨 CLI**:`hooks/codex/`、`hooks/gemini/` 先放 **advisory 降級版**(只警告,不擋),
   結構相容,日後補齊。

### 3.2 被否決的方案(保留理由,供日後重評)

- **方案 A — 純啟發式 hook**:每 session 首次編輯時 grep transcript 找「讀了別的檔 + 講了 pattern」。
  - 否決理由:① 靠 grep 關鍵字偵測「有沒有 stated pattern」太**模糊** → 全域硬擋下 false positive 高;
    ② **只能驗「有沒有讀檔」,驗不了資料對錯** → 抓不到 buggy_code 的根因(錯 factory_id)。

- **方案 C — inline 結構化 marker**:不另開 skill,要求 AI 在回覆內輸出固定格式
  ```GROUNDING:``` 區塊,hook 檢查存在。
  - 否決理由:**自我宣告可被「演」**(AI 把區塊寫出來但沒真做),沒有獨立 checker,
    拿不到文章 writer/checker 的價值,也擋不住最痛的「沒真驗資料」。

> 取捨總結:A 最輕但驗不到根因;C 中等但可被演;**B 最重但唯一能「實際驗資料」+
> 與既有架構一致 + marker 用 `=PASS` 硬比對(非模糊 grep)**。代價(每任務多一步)
> 用「只擋首次編輯 + SKIP 逃生門」壓住。

---

## 4. 風險與已知缺口(Block 3,已確認)

| # | 風險 / 邊界 | 處置 | 能否用 code 完全封死? |
|---|---|---|---|
| 1 | **Stale PASS / 多任務 session**:同 session 內任務 B 沿用任務 A 的舊 PASS | **刻意接受**(使用者選「只擋首次」)。hook 註解寫明,log 記錄編輯序號供日後評估是否升級為 per-task | 設計上不封 |
| 2 | **Marker 被「演」**:AI 不跑 `/ground` 就自打 `GROUNDING_STATUS=PASS` | 與既有 `PRECOMMIT_STATUS=PASS` 同級風險,已接受。緩解:marker 要求伴隨證據行 | **否 —— 明講無法 code 全封** |
| 3 | **Bash 寫檔繞過**:`echo >`、`sed -i` 不經 Edit/Write | 已知缺口。matcher **不含 Bash**(誤判太多),改在 `/ground` skill 文件警示;日後可加 Bash 寫檔偵測 | **否 —— 已知缺口** |
| 4 | **雙 PreToolUse hook 順序**:branch-guard + grounding-guard 同掛 Edit/Write/MultiEdit | 確認兩者並存、任一 `exit 2` 即擋;main 上 grounding-guard 直接放行 | 是 |
| 5 | **首次編輯是 .md** | 豁免;counter 只計非 .md 編輯 | 是 |
| 6 | **SKIP 濫用**:逃生門被狂用失去意義 | `SKIP` 必帶 `reason=`,每次記 log,當成功指標(誤判率) | 是(可觀測) |
| 7 | **Counter 狀態殘留**:/tmp 跨 session 累積 | 以 `SESSION_ID` 隔離(比照 complexity-guard);無 transcript / 非 repo → exit 0 | 是 |
| 8 | **跨 CLI 差異**:codex/gemini 無相同 skill+transcript 模型 | claude 為主;codex/gemini 先 advisory 降級 | 部分 |

> **明確聲明**:風險 #2(marker 被演)與 #3(Bash 繞過)**無法用 code 完全封死**。
> 本功能不宣稱 100% 防護,而是把「動手前紮根」從靠自覺升級為預設強制 + 高摩擦繞過。

---

## 5. 測試計畫

### 5.1 單元測試(合成 transcript JSONL 驅動 `grounding-guard.sh`,比照 stop-guard 可測性)
| 案例 | 輸入 | 期望 |
|---|---|---|
| (a) | 首次 code 編輯、transcript 無 PASS | **exit 2** |
| (b) | 首次 code 編輯、transcript 有 fresh `GROUNDING_STATUS=PASS` | exit 0 |
| (c) | 首次編輯是 `.md` | exit 0(豁免) |
| (d) | transcript 有 `GROUNDING_STATUS=SKIP reason=...` | exit 0 + 寫 log |
| (e) | 第二次 code 編輯(counter > 1) | exit 0(只擋首次) |
| (f) | 當前 branch 為 main/master | exit 0(避免 deadlock) |
| (g) | 無 transcript / 非 git repo | exit 0 |

### 5.2 整合測試(真實流程)
1. 在 `feature/grounding-guard`(或任意 feature branch)冷啟動。
2. 直接編輯一個 `.php` → **預期被擋(exit 2)**。
3. 跑 `/ground` → 輸出 `GROUNDING_STATUS=PASS`。
4. 再編輯同檔 → **預期放行**。

---

## 6. 建置順序(Build Order)

1. ✅ `git checkout -b feature/grounding-guard`(已完成)
2. ⬜ `skills/ground.md` —— **先做**,定義 `GROUNDING_STATUS` marker 格式與證據行要求
3. ⬜ `hooks/claude/grounding-guard.sh`
4. ⬜ `hooks/hooks.json` 增掛 grounding-guard(與 branch-guard 並存)
5. ⬜ 合成 transcript 測試 (a)–(g)
6. ⬜ `hooks/codex/`、`hooks/gemini/` advisory 降級版
7. ⬜ 更新 `README.md` / `CLAUDE.md`(專案結構表 + 工作流程圖)

---

## 7. 完成度驗收清單(交給其他 AI 檢查時使用)

> 逐項核對。每項標 ✅/❌ 並附證據(檔案路徑 + 行號 / 測試輸出)。

### 7.1 檔案存在性
- [ ] `skills/ground.md` 存在,且 frontmatter 有 `name: ground` 與 `description`
- [ ] `hooks/claude/grounding-guard.sh` 存在且 `chmod +x`
- [ ] `hooks/hooks.json` 內 PreToolUse 同時含 branch-guard 與 grounding-guard
- [ ] `hooks/codex/grounding-guard.sh`、`hooks/gemini/grounding-guard.sh` 存在(advisory 版)

### 7.2 `/ground` skill 行為
- [ ] 要求輸出 1–2 個既有參照檔路徑(stated pattern)
- [ ] 要求實際驗證資料 / IDs(WMS 場景含 SQL 確認)
- [ ] 結尾輸出 `GROUNDING_STATUS=PASS` 或 `GROUNDING_STATUS=SKIP reason=<理由>`
- [ ] marker 伴隨證據行(參照檔 + 驗證的值)

### 7.3 `grounding-guard.sh` 邏輯(對照 §3.1 與 §5.1)
- [ ] 讀 stdin JSON 的 `transcript_path` 與 `tool_input.file_path`
- [ ] 非 git repo / 無 transcript → exit 0(案例 g)
- [ ] main/master → exit 0(案例 f)
- [ ] 本次編輯為 `.md` / `.claudedocs/` → exit 0(案例 c)
- [ ] 用 `/tmp/dotai_grounding_${SESSION_ID}` counter 只擋首次非 .md 編輯(案例 e)
- [ ] 首次且無 PASS/SKIP → exit 2 並輸出指引(案例 a)
- [ ] 首次且有 fresh PASS → exit 0(案例 b)
- [ ] SKIP → exit 0 且把 reason 寫 log(案例 d)
- [ ] counter 只計非 .md 編輯

### 7.4 測試
- [ ] §5.1 (a)–(g) 七個單元案例皆有對應測試且通過
- [ ] §5.2 整合測試實際走過一遍(冷啟動被擋 → /ground → 放行)

### 7.5 風險處置對照(§4)
- [ ] #1 stale PASS:hook 註解說明「刻意只擋首次」,且 log 記錄編輯序號
- [ ] #2 marker 被演:程式碼註解 / 文件明確聲明此風險無法 code 全封
- [ ] #3 Bash 繞過:matcher 不含 Bash,且 `/ground` 文件有警示
- [ ] #4 雙 hook:確認 branch-guard + grounding-guard 並存、任一 exit 2 即擋
- [ ] #6 SKIP log:每次 SKIP 帶 reason 並寫入 log

### 7.6 文件
- [ ] `README.md` / `CLAUDE.md` 更新專案結構與工作流程
  (`/feature-dev → /ground →(grounding-guard 強制)→ implement → /precommit →(stop-guard 強制)→ commit`)

---

## 8. 決策記錄摘要(Decision Log)

| 決策點 | 選擇 | 否決的選項 | 理由 |
|---|---|---|---|
| 是否採用文章的自動化迴圈 | 否 | 無人值守 cron 迴圈 | 會放大使用者 #1 失誤(沒紮根),違反「驗證需人類」警告 |
| 採用哪個 loop-engineering 組件 | writer/checker 分離 + memory | worktrees / 自動化流程 | 對症 usage data 的 wrong_approach + buggy_code |
| 觸發範圍 | 全域 | 只擋資料敏感 / 全域分級 | 使用者選擇 |
| 強制強度 | 硬擋 + SKIP 逃生門 | 純硬擋 / 先 advisory | 避免 deadlock 又保留強制力 |
| 偵測機制 | 方案 B(skill + PASS marker) | A 啟發式 / C inline | 唯一能實際驗資料 + 與既有架構一致 + marker 非模糊 |
| 觸發單位 | 每 session 首次編輯 | 每次編輯 / per-task | 壓低成本與摩擦;接受 stale PASS 取捨 |
