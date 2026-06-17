#!/usr/bin/env bash
# prompt-template.sh — emit a /plan-shaped task template.
# Keeps the templates OUT of the slash-command markdown so the model does not
# reload all of them into context on every /prompt invocation.
#
# The skeleton bakes in the high-leverage habits from the prompting analysis:
#   - Out of Scope is front-loaded (state boundaries up front, not via interrupts)
#   - "Done when" forces acceptance criteria + a verify command
#   - bugfix leads with the key differential (give it once, not drip-fed)
# Fill the <...> hints inline and delete what doesn't apply — that is all the
# effort needed for an AI-readable, token-efficient, self-verifying prompt.
#
# Usage: prompt-template.sh <feature|bugfix|refactor> "<goal>" "<files>"
set -euo pipefail

type="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
goal="${2:-}"
files="${3:-}"
[ -z "$files" ] && files="(未指定 — 給檔案路徑或 @file,讓 AI 不用猜)"

case "$type" in
  feature)
    cat <<EOF
### Goal
$goal

### Scope
- [ ] 實作功能核心邏輯
- [ ] 撰寫對應測試
- [ ] 更新相關文件

### Related Files
$files

### Done when（完成標準 + 驗證）
- [ ] <可觀察的結果,例:API 回傳含 sku/date/qty,排除已取消訂單>
- 驗證:跑 <command>(例:yarn test:unit),把通過/失敗數貼回

### Out of Scope（先講清楚,省得中途才喊停）
- <不要碰的檔案/資料,例:不要動 migration、不要重置或清空 DB>
- UI/UX 的細節優化

### Assumptions
- 現有架構支援此功能
- 資料庫 schema 無需變更
EOF
    ;;
  bugfix)
    cat <<EOF
### Goal
Fix: $goal

### Symptom & 關鍵差異（一次講完,別擠牙膏）
- 重現步驟 / 條件:<例:同一 build 裝兩台,A 台壞 B 台正常;手動開檔再操作就正常>
- 預期 vs 實際:<預期…,實際…>

### Scope
- [ ] 重現 Bug
- [ ] 修復邏輯
- [ ] 撰寫回歸測試

### Related Files
$files

### Done when（完成標準 + 驗證）
- [ ] <bug 不再發生的可觀察判準>
- 驗證:跑 <command>(例:php artisan test --filter=X),把結果貼回

### Out of Scope（先講清楚）
- <不要碰的部分,例:此功能的全面重構、相鄰模組不要動>

### Assumptions
- Bug 可重現
- 錯誤非第三方套件引起
EOF
    ;;
  refactor)
    cat <<EOF
### Goal
Refactor: $goal

### Scope
- [ ] 優化現有函數/模組
- [ ] 保持現有功能測試通過
- [ ] 移除冗餘代碼

### Related Files
$files

### Done when（完成標準 + 驗證）
- [ ] 行為不變:既有測試全數通過(不新增/修改斷言)
- 驗證:跑 <command>,把通過數貼回

### Out of Scope（先講清楚）
- <不要碰的部分,例:不要改動公開介面、不要順手加新功能>
- 新功能的開發

### Assumptions
- 測試覆蓋率足夠
- 接口定義不變
EOF
    ;;
  *)
    echo "ERROR: unknown type '$type' (expect feature|bugfix|refactor)" >&2
    exit 1
    ;;
esac
