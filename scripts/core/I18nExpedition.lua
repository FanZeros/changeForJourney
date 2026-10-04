-- 远征成长与奖励显示词典：完整简中原文对应繁中、英文、日文、韩文，printf 格式符及参数顺序保持一致。
-- 仅导出四个语言包；无 I18n / 引擎依赖，不修改业务数据或负责界面接入。
---@type table<string, table<string, string>>
local D = { zh_TW = {}, en = {}, ja = {}, ko = {} }

---@param source string
---@param tw string
---@param en string
---@param ja string
---@param ko string
local function add(source, tw, en, ja, ko)
    D.zh_TW[source], D.en[source], D.ja[source], D.ko[source] = tw, en, ja, ko
end

-- 奖励与升级弹窗。
add("奖励配置不可用", "獎勵設定不可用", "Rewards unavailable", "報酬設定を利用できません", "보상 설정을 사용할 수 없습니다")
add("奖励", "獎勵", "Reward", "報酬", "보상")
add("远征等级提升", "遠征等級提升", "Expedition Level Up", "遠征レベルアップ", "원정 레벨 상승")
add("查看远征奖励", "查看遠征獎勵", "View Expedition Rewards", "遠征報酬を見る", "원정 보상 보기")
add("Lv.%d → Lv.%d    远征点上限 +%d",
    "Lv.%d → Lv.%d    遠征點上限 +%d",
    "Lv.%d → Lv.%d    Expedition Point Cap +%d",
    "Lv.%d → Lv.%d    遠征ポイント上限 +%d",
    "Lv.%d → Lv.%d    원정 포인트 상한 +%d")
add("%s 等 %d 项", "%s 等 %d 項", "%s and more (%d items)", "%sなど全%d項目", "%s 등 총 %d개")
add("到达奖励里程碑 %s", "達成獎勵里程碑 %s", "Reward milestone reached: %s", "報酬の節目 %s に到達", "보상 이정표 %s 달성")
add("每次成长都将记入远征勋记",
    "每次成長都將記入遠征勳記",
    "Every gain is recorded in your Expedition Chronicle",
    "成長の歩みは遠征記録に刻まれます",
    "모든 성장은 원정 기록에 남습니다")
add("查看奖励 · %d 项可领", "查看獎勵 · %d 項可領", "View Rewards · %d to Claim", "報酬を見る · %d件受取可能", "보상 보기 · %d개 수령 가능")
add("另有 %d 项解锁，可前往奖励页查看",
    "另有 %d 項解鎖，可前往獎勵頁查看",
    "%d more unlocked · See the rewards page",
    "さらに%d項目解放 · 報酬ページで確認",
    "%d개 추가 해금 · 보상 페이지에서 확인")
add("%d 秒后自动关闭 · 点击空白继续",
    "%d 秒後自動關閉 · 點擊空白繼續",
    "Closes in %d s · Click empty space to continue",
    "%d秒後に閉じます · 余白を押して続行",
    "%d초 후 닫힘 · 빈 곳을 눌러 계속")

-- 成长解锁与关卡门槛。
add("每队可出战 %d 人", "每隊可出戰 %d 人", "%d heroes per team", "各隊%d人まで出撃可能", "팀당 %d명 출전 가능")
add("装备强化上限 Lv.%d", "裝備強化上限 Lv.%d", "Gear Enhance Cap Lv.%d", "装備強化上限 Lv.%d", "장비 강화 상한 Lv.%d")
add("神器第 %d 格", "神器第 %d 格", "Artifact Slot %d", "神器スロット%d", "유물 슬롯 %d")
add("礼拜堂正式开放（引导门控另计）",
    "禮拜堂正式開放（引導限制另計）",
    "Chapel open (tutorial gates still apply)",
    "教会開放（チュートリアル制限は別途適用）",
    "성당 개방 (튜토리얼 제한 별도 적용)")
add("小队 %d · 通关%d-%d解锁",
    "小隊 %d · 通關%d-%d解鎖",
    "Team %d · Clear %d-%d to unlock",
    "第%d隊 · %d-%dクリアで解放",
    "팀 %d · %d-%d 클리어 시 해금")
add("该等级无新增功能解锁", "此等級無新增功能解鎖", "No new unlocks at this level", "このレベルでの新規解放なし", "이 레벨의 신규 해금 없음")
add("等级成长 · %s", "等級成長 · %s", "Level Growth · %s", "レベル成長 · %s", "레벨 성장 · %s")
add("已开放 · %s", "已開放 · %s", "Unlocked · %s", "解放済 · %s", "개방됨 · %s")
add("通关开放 · %s", "通關開放 · %s", "Clear to Unlock · %s", "クリアで解放 · %s", "클리어 시 개방 · %s")

-- 远征勋记标题、进度与领取状态。
add("远征等级 · 加载中", "遠征等級 · 載入中", "Expedition Lv · Loading", "遠征レベル · 読込中", "원정 레벨 · 로딩 중")
add("远征等级 Lv.%d", "遠征等級 Lv.%d", "Expedition Lv.%d", "遠征レベル Lv.%d", "원정 레벨 Lv.%d")
add("可领 —", "可領 —", "To Claim —", "受取可能 —", "수령 가능 —")
add("可领 %d 项", "可領 %d 項", "%d to Claim", "%d件受取可能", "%d개 수령 가능")
add("经验进度加载中", "經驗進度載入中", "Loading EXP progress", "経験値の進捗を読込中", "경험치 진행도 로딩 중")
add("经验 %s / %s", "經驗 %s / %s", "EXP %s / %s", "経験値 %s / %s", "경험치 %s / %s")
add("经验进度 · 已达等级上限", "經驗進度 · 已達等級上限", "EXP · Level Cap Reached", "経験値 · レベル上限到達", "경험치 · 레벨 상한 도달")
add("下一里程碑 · 加载中", "下一里程碑 · 載入中", "Next Milestone · Loading", "次の節目 · 読込中", "다음 이정표 · 로딩 중")
add("下一里程碑 · Lv.%d", "下一里程碑 · Lv.%d", "Next Milestone · Lv.%d", "次の節目 · Lv.%d", "다음 이정표 · Lv.%d")
add("全部里程碑已达成", "全部里程碑已達成", "All Milestones Reached", "すべての節目を達成", "모든 이정표 달성")
add("当前成长 · 加载中", "目前成長 · 載入中", "Current Growth · Loading", "現在の成長 · 読込中", "현재 성장 · 로딩 중")
add("每队 %s 人 · 强化上限 Lv.%s · 神器 %s 格",
    "每隊 %s 人 · 強化上限 Lv.%s · 神器 %s 格",
    "%s per team · Enhance Cap Lv.%s · %s Artifact Slots",
    "各隊%s人 · 強化上限 Lv.%s · 神器%s枠",
    "팀당 %s명 · 강화 상한 Lv.%s · 유물 %s칸")
add("永久勋记 · 等级顺序固定，已领取奖励保留记录",
    "永久勳記 · 等級順序固定，已領取獎勵保留記錄",
    "Permanent Chronicle · Fixed level order; claimed rewards stay recorded",
    "永久記録 · レベル順は固定、受取済みの報酬も記録",
    "영구 기록 · 레벨 순서 고정, 수령한 보상도 기록 유지")
add("远征勋记", "遠征勳記", "Expedition Chronicle", "遠征記録", "원정 기록")
add("加载中", "載入中", "Loading", "読込中", "로딩 중")
add("已领取", "已領取", "Claimed", "受取済", "수령됨")
add("领取", "領取", "Claim", "受取", "수령")
add("未达成", "未達成", "Not Reached", "未達成", "미달성")

add("当前等级", "目前等級", "Current Level", "現在のレベル", "현재 레벨")
add("等级奖励", "等級獎勵", "Level Rewards", "レベル報酬", "레벨 보상")
add("每级额外奖励", "每級額外獎勵", "Bonus per Level", "各レベルの追加報酬", "레벨별 추가 보상")

return D
