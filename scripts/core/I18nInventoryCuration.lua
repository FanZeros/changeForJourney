-- 局部显示词典，沿用 I18nTower 的 core.I18n.get() 语言路由，不安装全局绘制 hook。
local I18n = require("core.I18n")
local M = {}
local D = { zh_TW = {}, en = {}, ja = {}, ko = {} }
local function add(zh, tw, en, ja, ko)
    D.zh_TW[zh], D.en[zh], D.ja[zh], D.ko[zh] = tw, en, ja, ko
end
add("一键优选", "一鍵優選", "Auto-curate", "一括厳選", "자동 선별")
add("优选预览", "優選預覽", "Curation preview", "厳選プレビュー", "선별 미리보기")
add("正在生成预览…", "正在產生預覽…", "Preparing preview…", "プレビューを作成中…", "미리보기 생성 중…")
add("正在整理…", "正在整理…", "Curating…", "整理中…", "정리 중…")
add("确认优选", "確認優選", "Confirm curation", "厳選を確定", "선별 확정")
add("重新预览", "重新預覽", "Refresh preview", "再プレビュー", "다시 미리보기")
add("取消", "取消", "Cancel", "キャンセル", "취소")
add("关闭", "關閉", "Close", "閉じる", "닫기")
add("移入仓库：%d 件", "移入倉庫：%d 件", "To inventory: %d", "倉庫へ：%d個", "창고로 이동: %d개")
add("转存遗匣：%d 件", "轉存遺匣：%d 件", "To reliquary: %d", "遺匣へ：%d個", "유물함으로 이동: %d개")
add("原位保护：%d 件", "原位保護：%d 件", "Kept protected: %d", "元の場所で保護：%d個", "제자리 보호: %d개")
add("仓库容量：%d 件", "倉庫容量：%d 件", "Inventory capacity: %d", "倉庫容量：%d個", "창고 용량: %d개")
add("按部位平衡仓位。同类优先保留好成品，并预留少量高基础培养底材；不等于英雄最佳配装。", "按部位平衡倉位。同類優先保留好成品，並預留少量高基礎培養底材；不等於英雄最佳配裝。", "Balances slots; keeps strong gear plus some high-base training pieces. Not a hero's best loadout.", "部位ごとに枠を配分。同種の良装備と少量の高基礎育成素材を確保。英雄の最適装備ではありません。", "부위별 균형 배분. 같은 유형의 좋은 완제품과 소량의 고기초 육성 소재를 보존합니다. 영웅 최적 장비는 아닙니다.")
add("整理全仓库与遗匣，忽略筛选与排序。已穿戴、锁定、套装、投入、腐化、待洗练及异常库存原位保护。", "整理全倉庫與遺匣，忽略篩選與排序。已穿戴、鎖定、套裝、投入、腐化、待洗練及異常庫存原位保護。", "Curates all inventory and reliquary gear regardless of filters. Equipped, locked, set, invested, corrupted, pending-refinement and invalid inventory gear stays put.", "絞り込み・並び順に関係なく倉庫と遺匣全体を整理。装備中・ロック・セット・投資済み・腐化・洗練待ち・異常な倉庫装備は元の場所で保護。", "필터·정렬과 무관하게 창고와 유물함 전체를 정리합니다. 착용·잠금·세트·투자·부패·세련 대기·비정상 창고 장비는 제자리 보호됩니다.")
add("只转存不分解，转存遗匣装备受保护，不参与回收。保护占满仓库时无法腾位。", "只轉存不分解，轉存遺匣裝備受保護，不參與回收。保護占滿倉庫時無法騰位。", "Transfers only, never dismantles. Curated reliquary gear cannot be recycled. A fully protected inventory cannot free space.", "移動のみで分解しません。整理で遺匣へ移した装備は回収対象外。倉庫が保護装備で満杯なら枠を空けられません。", "이동만 하며 분해하지 않습니다. 선별로 유물함에 옮긴 장비는 회수 제외됩니다. 보호 장비로 가득 차면 칸을 비울 수 없습니다.")
add("仓库全部受保护，无法腾位", "倉庫全部受保護，無法騰位", "All inventory gear is protected; no space can be freed", "倉庫内は全て保護中のため、枠を空けられません", "창고 전체가 보호되어 칸을 비울 수 없습니다")
add("数据已改变，请重新预览后确认。", "資料已改變，請重新預覽後確認。", "Data changed. Refresh the preview before confirming.", "データが変更されました。再プレビューしてから確定してください。", "데이터가 변경되었습니다. 다시 미리본 뒤 확정하세요.")
add("优选失败，未移动装备，请重新预览。", "優選失敗，未移動裝備，請重新預覽。", "Curation failed; no gear moved. Refresh the preview.", "厳選に失敗しました。装備は移動していません。再プレビューしてください。", "선별 실패: 장비는 이동하지 않았습니다. 다시 미리보세요.")
add("存档失败，未移动装备，请重试。", "存檔失敗，未移動裝備，請重試。", "Save failed; no gear moved. Please retry.", "保存に失敗しました。装備は移動していません。再試行してください。", "저장 실패: 장비는 이동하지 않았습니다. 다시 시도하세요.")
add("没有需要移动的装备", "沒有需要移動的裝備", "No gear needs moving", "移動が必要な装備はありません", "이동할 장비가 없습니다")
add("整理完成：移入 %d 件，转存 %d 件", "整理完成：移入 %d 件，轉存 %d 件", "Curated: %d in, %d transferred", "整理完了：倉庫へ%d個、遺匣へ%d個", "정리 완료: 창고 %d개, 유물함 %d개")
add("一键领取按通用评分优先，与列表排序无关", "一鍵領取按通用評分優先，與列表排序無關", "Claim all prioritizes general score, not list order", "一括受取は一覧順ではなく汎用スコアを優先", "일괄 수령은 목록 순서가 아닌 범용 점수 우선")
add("整理转存 · 受保护", "整理轉存 · 受保護", "Curated transfer · Protected", "整理で転送 · 保護中", "선별 이동 · 보호 중")
add("受保护装备不参与回收", "受保護裝備不參與回收", "Protected gear cannot be recycled", "保護装備は回収対象外です", "보호 장비는 회수되지 않습니다")
add(" · 保护 %d 件", " · 保護 %d 件", " · %d protected", " · 保護%d個", " · 보호 %d개")
add("可回收 %d 件（已排除受保护装备）", "可回收 %d 件（已排除受保護裝備）", "%d recyclable (protected gear excluded)", "回収可能%d個（保護装備を除外）", "회수 가능 %d개 (보호 장비 제외)")
add("回收后无法撤销", "回收後無法撤銷", "Recycling cannot be undone", "回収は取り消せません", "회수는 취소할 수 없습니다")
add("装备已锁定", "裝備已鎖定", "Gear locked", "装備をロックしました", "장비 잠금 완료")
add("装备已解锁", "裝備已解鎖", "Gear unlocked", "装備のロックを解除しました", "장비 잠금 해제 완료")
add("锁定失败，请重试", "鎖定失敗，請重試", "Lock failed. Please retry.", "ロックに失敗しました。再試行してください。", "잠금 실패. 다시 시도하세요.")
add("锁定请求超时，请重试", "鎖定請求逾時，請重試", "Lock request timed out. Please retry.", "ロック要求がタイムアウトしました。再試行してください。", "잠금 요청 시간이 초과되었습니다. 다시 시도하세요.")
add("锁定请求未处理，请重试", "鎖定請求未處理，請重試", "Lock request was not handled. Please retry.", "ロック要求が処理されませんでした。再試行してください。", "잠금 요청이 처리되지 않았습니다. 다시 시도하세요.")
function M.text(source, ...)
    local lang = I18n.get()
    local translated = (D[lang] and D[lang][source]) or source
    if select("#", ...) == 0 then return translated end
    return string.format(translated, ...)
end
return M
