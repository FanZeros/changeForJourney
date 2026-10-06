-- 关键词显示词典：原业务 key 只用于 KeywordConfig.get / 点击，不写回配置。
-- 注册：mergeLang(dict, require("core.I18nKeywords"))；只有四个语言字段是 table。
-- lookup 只接受完整已登记原文，绝不替换任意句子中的子串。
local KW = require("config.KeywordConfig")
local TalentText = require("core.I18nTalentText")
local Equipment = require("core.I18nEquipment")

---@class I18nKeywords
---@field zh_TW table<string, string>
---@field en table<string, string>
---@field ja table<string, string>
---@field ko table<string, string>
local D = { zh_TW = {}, en = {}, ja = {}, ko = {} }
---@type table<string, table<string, {name:string, title:string, desc:string}>>
local definitions = { zh_TW = {}, en = {}, ja = {}, ko = {} }
local languages = { "zh_TW", "en", "ja", "ko" }

---@param key string
---@param names string[]
---@param titles string[]
---@param descriptions string[]
local function add(key, names, titles, descriptions)
    local source = assert(KW.get(key), "Unknown keyword: " .. key)
    for i, lang in ipairs(languages) do
        local name = assert(names[i], "Missing keyword name")
        local title = assert(titles[i], "Missing keyword title")
        local desc = assert(descriptions[i], "Missing keyword description")
        definitions[lang][key] = { name = name, title = title, desc = desc }
        D[lang][key] = name
        D[lang][source.title] = title
        D[lang][source.desc] = desc
    end
end

-- 六职业名称沿用当前 I18nDictExtra，避免同一业务 key 在不同 UI 使用不同译名。
add("封门人", { "封門人", "Gatewarden", "門を封ずる者", "봉문인" },
    { "封門人（職業）", "Gatewarden (Class)", "門を封ずる者（クラス）", "봉문인 (직업)" }, {
    "坦克型職業，仇恨係數最高。\n職業天賦「門縫」：受到的傷害先儲存於門縫，儲存傷害會增加仇恨。",
    "A tank class with the highest threat multiplier.\nClass talent: Door-gap. Incoming damage is first stored in the Door-gap; stored damage increases threat.",
    "タンク型クラス。ヘイト係数が最も高い。\nクラスタレント「隙間」：受けるダメージをまず隙間に蓄積し、蓄積したダメージに応じてヘイトが増える。",
    "탱커형 직업으로 위협 계수가 가장 높습니다.\n직업 특성 「문틈」: 받는 피해를 먼저 문틈에 저장하며, 저장된 피해는 위협을 증가시킵니다.",
})
add("拾骸者", { "拾骸者", "Bonepicker", "骸拾い", "습해자" },
    { "拾骸者（職業）", "Bonepicker (Class)", "骸拾い（クラス）", "습해자 (직업)" }, {
    "物理輸出職業，靠擊殺滾雪球。\n職業天賦「拾骸」：擊殺敵人獲得骸骨層數，提升攻擊速度。",
    "A physical damage class that grows stronger through kills.\nClass talent: Scavenge. Killing enemies grants Bone stacks that increase attack speed.",
    "敵を倒すほど強くなる物理アタッカー。\nクラスタレント「拾骸」：敵を倒すと骸骨のスタックを獲得し、攻撃速度が上がる。",
    "적 처치로 점점 강해지는 물리 공격 직업입니다.\n직업 특성 「습해」: 적을 처치하면 뼈 중첩을 획득하여 공격 속도가 증가합니다.",
})
add("裂隙使", { "裂隙使", "Riftweaver", "裂け目使い", "열극사" },
    { "裂隙使（職業）", "Riftweaver (Class)", "裂け目使い（クラス）", "열극사 (직업)" }, {
    "魔法輸出職業，幾乎不產生仇恨。\n職業天賦「裂隙」：週期性展開裂隙，強化護甲剋制並施加裂痕。",
    "A magic damage class that generates almost no threat.\nClass talent: Rift. Periodically opens a Rift, improving Armor Matchup and applying Fracture stacks.",
    "ほとんどヘイトを発生させない魔法アタッカー。\nクラスタレント「裂け目」：定期的に裂け目を開き、装甲相性を強化して亀裂を付与する。",
    "위협을 거의 발생시키지 않는 마법 공격 직업입니다.\n직업 특성 「열극」: 주기적으로 열극을 열어 방어구 상성을 강화하고 균열을 부여합니다.",
})
add("回响客", { "回響客", "Echoist", "残響客", "메아리객" },
    { "回響客（職業）", "Echoist (Class)", "残響客（クラス）", "메아리객 (직업)" }, {
    "遠程輸出職業，仇恨極低。\n職業天賦「回響」：普通攻擊留下回響，延遲後追加一次傷害。",
    "A ranged damage class with very low threat.\nClass talent: Echo. Basic attacks leave an Echo that deals one additional hit after a delay.",
    "ヘイトが極めて低い遠距離アタッカー。\nクラスタレント「残響」：通常攻撃が残響を残し、時間差で追加ダメージを1回与える。",
    "위협이 매우 낮은 원거리 공격 직업입니다.\n직업 특성 「메아리」: 기본 공격이 메아리를 남겨 일정 시간 후 추가 피해를 한 번 줍니다.",
})
add("换面人", { "換面人", "Facestealer", "面替え", "환면인" },
    { "換面人（職業）", "Facestealer (Class)", "面替え（クラス）", "환면인 (직업)" }, {
    "刺殺型職業，不產生攻擊仇恨。\n職業天賦「換面」：複製目標的護甲剋制並額外提高，切換目標時無視部分護甲。",
    "An assassin class that generates no attack threat.\nClass talent: Face Swap. Copies and further improves the target's Armor Matchup; switching targets lets an attack ignore part of their armor.",
    "攻撃によるヘイトを発生させない暗殺型クラス。\nクラスタレント「面替えの術」：対象の装甲相性をコピーしてさらに強化し、対象の切り替え時に装甲の一部を無視する。",
    "공격 위협을 발생시키지 않는 암살형 직업입니다.\n직업 특성 「환면」: 대상의 방어구 상성을 복사하고 추가로 높이며, 대상 변경 시 방어력의 일부를 무시합니다.",
})
add("司仪", { "司儀", "Officiant", "司式", "사제" },
    { "司儀（職業）", "Officiant (Class)", "司式（クラス）", "사제 (직업)" }, {
    "治療職業，治療量按90%結算。\n職業天賦「延緩」：過量治療轉為延緩，為隊友抵擋致命傷害。",
    "A healer class whose healing is applied at 90% effectiveness.\nClass talent: Deferral. Converts overhealing into Deferral to protect allies from fatal damage.",
    "回復量が90%で適用されるヒーラー。\nクラスタレント「猶予」：余剰回復を猶予に変換し、味方を致命的なダメージから守る。",
    "치유량이 90%로 적용되는 치유 직업입니다.\n직업 특성 「유예」: 초과 치유를 유예로 전환하여 아군의 치명적인 피해를 막습니다.",
})

-- 职业天赋：数值、上限、时间、触发次数逐项保留，不改机制。
add("门缝", { "門縫", "Door-gap", "隙間", "문틈" },
    { "門縫", "Door-gap", "隙間", "문틈" }, {
    "封門人職業天賦。受到的傷害先儲存於門縫（容量為最大生命的12%），每秒釋放20%。\n釋放的傷害有30%轉向目前敵人，其餘由自己承受；儲存傷害會增加仇恨。",
    "Gatewarden class talent. Incoming damage is stored in the Door-gap, up to 12% of max HP. It releases 20% per second.\n30% of released damage is redirected to the current enemy; you take the rest. Stored damage increases threat.",
    "門を封ずる者のクラスタレント。受けるダメージを隙間に蓄積する（容量は最大HPの12%）。毎秒20%を放出。\n放出するダメージの30%は現在の敵に転送し、残りは自身が受ける。蓄積したダメージはヘイトを増やす。",
    "봉문인의 직업 특성. 받는 피해를 문틈에 저장하며 용량은 최대 체력의 12%입니다. 매초 20%를 방출합니다.\n방출 피해의 30%는 현재 적에게 전가하고 나머지는 자신이 받습니다. 저장 피해는 위협을 증가시킵니다.",
})
add("拾骸", { "拾骸", "Scavenge", "拾骸", "습해" },
    { "拾骸", "Scavenge", "拾骸", "습해" }, {
    "拾骸者職業天賦。擊殺敵人獲得1層骸骨（最多12層），每層攻擊速度+1.2%。\n滿12層後，下次攻擊消耗6層骸骨並追加一次40%傷害。",
    "Bonepicker class talent. Each kill grants 1 Bone stack, up to 12. Each stack gives Attack Speed +1.2%.\nAt 12 stacks, the next attack consumes 6 Bone stacks and deals one additional hit for 40% damage.",
    "骸拾いのクラスタレント。敵を倒すと骸骨を1スタック獲得（最大12）。1スタックにつき攻撃速度+1.2%。\n12スタックに達すると、次の攻撃で骸骨を6スタック消費し、40%の追加ダメージを1回与える。",
    "습해자의 직업 특성. 적 처치 시 뼈 1중첩을 획득하며 최대 12중첩입니다. 중첩마다 공격 속도+1.2%.\n12중첩에 도달하면 다음 공격이 뼈 6중첩을 소모하고 40%의 추가 피해를 한 번 줍니다.",
})
add("裂隙", { "裂隙", "Rift", "裂け目", "열극" },
    { "裂隙", "Rift", "裂け目", "열극" }, {
    "裂隙使職業天賦。每8秒展開持續4秒的裂隙：\n自身攻擊的護甲剋制係數向1.25靠近，並給目標施加1層裂痕。",
    "Riftweaver class talent. Every 8 seconds, opens a Rift lasting 4 seconds.\nYour attack's Armor Matchup multiplier moves toward 1.25, and attacks apply 1 Fracture stack to the target.",
    "裂け目使いのクラスタレント。8秒ごとに4秒間持続する裂け目を開く。\n自身の攻撃の装甲相性係数が1.25に近づき、対象に亀裂を1スタック付与する。",
    "열극사의 직업 특성. 8초마다 4초간 지속되는 열극을 엽니다.\n자신의 공격에 적용되는 방어구 상성 계수가 1.25에 가까워지며 대상에게 균열 1중첩을 부여합니다.",
})
add("回响", { "回響", "Echo", "残響", "메아리" },
    { "回響", "Echo", "残響", "메아리" }, {
    "回響客職業天賦。普通攻擊留下回響，1.2秒後造成原傷害45%的額外傷害（僅產生10%仇恨）。\n隊伍中有封門人時，回響傷害+15%。",
    "Echoist class talent. Basic attacks leave an Echo that deals extra damage equal to 45% of the original hit after 1.2 seconds, generating only 10% threat.\nWith a Gatewarden in the team, Echo damage +15%.",
    "残響客のクラスタレント。通常攻撃が残響を残し、1.2秒後に元のダメージの45%の追加ダメージを与える（ヘイトは10%のみ）。\nチームに門を封ずる者がいる場合、残響ダメージ+15%。",
    "메아리객의 직업 특성. 기본 공격이 메아리를 남겨 1.2초 후 원래 피해의 45%만큼 추가 피해를 주며, 위협은 10%만 발생합니다.\n팀에 봉문인이 있으면 메아리 피해+15%.",
})
add("换面", { "換面", "Face Swap", "面替えの術", "환면" },
    { "換面", "Face Swap", "面替えの術", "환면" }, {
    "換面人職業天賦。開戰時複製目前目標的護甲剋制係數，並額外提高0.1。\n目標死亡3秒後切換至下一目標；切換期間的下一次攻擊無視20%護甲。",
    "Facestealer class talent. At battle start, copies the current target's Armor Matchup multiplier and adds 0.1.\nSwitches to the next target 3 seconds after the current target dies. The next attack during the switch ignores 20% armor.",
    "面替えのクラスタレント。戦闘開始時に現在の対象の装甲相性係数をコピーし、さらに0.1を加える。\n対象が倒れて3秒後に次の対象へ切り替える。切り替え中の次の攻撃は装甲の20%を無視する。",
    "환면인의 직업 특성. 전투 시작 시 현재 대상의 방어구 상성 계수를 복사하고 0.1을 추가합니다.\n대상이 죽은 3초 후 다음 대상으로 변경하며, 변경 중 다음 공격은 방어력의 20%를 무시합니다.",
})
add("延缓", { "延緩", "Deferral", "猶予", "유예" },
    { "延緩", "Deferral", "猶予", "유예" }, {
    "司儀職業天賦。治療量按90%結算，過量治療轉為延緩：\n為隊友抵擋一次致命傷害，但抵擋的部分會在4秒內反噬，使其受到的傷害+15%。每人最多承受1層。",
    "Officiant class talent. Healing is applied at 90% effectiveness; overhealing becomes Deferral.\nIt blocks one fatal hit for an ally, but the blocked portion rebounds over 4 seconds, increasing their damage taken by 15%. Maximum: 1 stack per ally.",
    "司式のクラスタレント。回復量を90%で適用し、余剰回復を猶予に変換する。\n味方への致命的なダメージを1回防ぐが、防いだ分は4秒間で反動として返り、被ダメージ+15%。1人につき最大1スタック。",
    "사제의 직업 특성. 치유량을 90%로 적용하고 초과 치유를 유예로 전환합니다.\n아군의 치명적인 피해를 한 번 막지만, 막은 피해는 4초에 걸쳐 반동으로 돌아오며 받는 피해+15%. 아군마다 최대 1중첩입니다.",
})

-- 战斗机制。
add("骸骨", { "骸骨", "Bone", "骸骨", "뼈" }, { "骸骨", "Bone", "骸骨", "뼈" }, {
    "拾骸者的疊層資源，擊殺敵人獲得，最多12層。\n每層攻擊速度+1.2%；滿層後下次攻擊消耗6層，追加一次40%傷害。",
    "Bonepicker's stacking resource, gained by killing enemies. Maximum: 12 stacks.\nEach stack gives Attack Speed +1.2%. At full stacks, the next attack consumes 6 stacks and deals one additional hit for 40% damage.",
    "骸拾いが敵を倒して獲得するスタック資源。最大12スタック。\n1スタックにつき攻撃速度+1.2%。最大時の次の攻撃は6スタックを消費し、40%の追加ダメージを1回与える。",
    "습해자가 적 처치로 얻는 중첩 자원으로, 최대 12중첩입니다.\n중첩마다 공격 속도+1.2%. 최대 중첩에서 다음 공격이 6중첩을 소모하고 40%의 추가 피해를 한 번 줍니다.",
})
add("裂痕", { "裂痕", "Fracture", "亀裂", "균열" }, { "裂痕", "Fracture", "亀裂", "균열" }, {
    "裂隙展開期間攻擊施加的疊層標記，最多5層。\n部分轉職天賦會消耗裂痕觸發額外效果（如「錯位」）。",
    "A stacking mark applied by attacks while a Rift is open. Maximum: 5 stacks.\nSome advanced class talents consume Fracture stacks to trigger additional effects, such as Dislocation.",
    "裂け目が開いている間、攻撃で付与するスタック印。最大5スタック。\n一部の転職タレントは亀裂を消費し、「位置ずれ」などの追加効果を発動する。",
    "열극이 열린 동안 공격으로 부여하는 중첩 표식으로, 최대 5중첩입니다.\n일부 전직 특성은 균열을 소모하여 「어긋남」 등의 추가 효과를 발동합니다.",
})
add("仇恨", { "仇恨", "Threat", "ヘイト", "위협" }, { "仇恨", "Threat", "ヘイト", "위협" }, {
    "敵人依據仇恨值選擇攻擊目標，造成傷害和治療都會產生仇恨。\n各職業仇恨係數不同：封門人最高，換面人／裂隙使幾乎不產生攻擊仇恨。",
    "Enemies choose attack targets by threat. Dealing damage and healing both generate threat.\nThreat multipliers vary by class: Gatewarden has the highest; Facestealer and Riftweaver generate almost no attack threat.",
    "敵はヘイト値に基づいて攻撃対象を選ぶ。ダメージを与えることも回復もヘイトを発生させる。\n係数はクラスごとに異なり、門を封ずる者が最も高い。面替えと裂け目使いは攻撃ヘイトをほとんど発生させない。",
    "적은 위협 수치에 따라 공격 대상을 선택합니다. 피해를 주거나 치유하면 위협이 발생합니다.\n직업마다 위협 계수가 다릅니다. 봉문인이 가장 높으며, 환면인과 열극사는 공격 위협을 거의 발생시키지 않습니다.",
})
add("护甲克制", { "護甲剋制", "Armor Matchup", "装甲相性", "방어구 상성" },
    { "護甲剋制", "Armor Matchup", "装甲相性", "방어구 상성" }, {
    "攻擊類型與目標護甲類型之間的傷害倍率關係。\n剋制時倍率提高（最高向1.25靠近），被剋制時倍率降低；由角色的攻擊類型與目標護甲類型決定。",
    "The damage multiplier determined by attack type versus the target's armor type.\nA favorable matchup raises it, moving toward 1.25 at most; an unfavorable one lowers it. It depends on the character's attack type and the target's armor type.",
    "攻撃タイプと対象の装甲タイプによって決まるダメージ倍率の関係。\n有利なら倍率が上がる（最大で1.25に近づく）。不利なら下がる。キャラクターの攻撃タイプと対象の装甲タイプで決まる。",
    "공격 유형과 대상의 방어구 유형에 따른 피해 배율 관계입니다.\n유리하면 배율이 높아져 최대 1.25에 가까워지고, 불리하면 낮아집니다. 캐릭터의 공격 유형과 대상의 방어구 유형으로 결정됩니다.",
})
add("连击", { "連擊", "Combo", "連撃", "연격" }, { "連擊", "Combo", "連撃", "연격" }, {
    "有機率在0.1秒後額外攻擊一次，連擊機率超過100%仍有效。\n連擊增傷：每次連擊後增加的額外傷害，逐次遞增。",
    "Has a chance to make one additional attack after 0.1 seconds. Combo chance above 100% remains effective.\nCombo DMG Bonus adds extra damage after each combo hit, increasing with successive hits.",
    "確率で0.1秒後に追加攻撃を1回行う。連撃率は100%を超えても有効。\n連撃ダメージ補正：連撃ごとに追加ダメージが増え、回を重ねるほど上昇する。",
    "확률적으로 0.1초 후 추가 공격을 한 번 합니다. 연격 확률은 100%를 넘어도 유효합니다.\n연격 피해 보너스: 연격마다 추가되는 피해가 차례로 증가합니다.",
})
add("超暴击", { "超暴擊", "Super Crit", "超会心", "초치명타" },
    { "超暴擊", "Super Crit", "超会心", "초치명타" }, {
    "暴擊後額外再判定一次的強化暴擊，觸發後傷害再乘一次暴擊傷害倍率。\n常見來源：暴擊率溢出轉化、通天塔詞條「精準連射」等。",
    "An enhanced critical hit checked once more after a critical hit. On activation, damage is multiplied by the critical damage multiplier again.\nCommon sources include conversion of excess crit rate and the tower affix Precision Volley.",
    "会心後にもう一度判定する強化会心。発動すると、ダメージに会心ダメージ倍率をさらに1回掛ける。\n主な発生源は会心率の超過分の変換や、塔の効果「精密連射」など。",
    "치명타 후 추가로 한 번 더 판정하는 강화 치명타입니다. 발동하면 피해에 치명타 피해 배율을 다시 한 번 곱합니다.\n주요 획득 경로는 초과 치명타율 전환과 탑 옵션 「정밀 연사」 등입니다.",
})
add("能量护盾", { "能量護盾", "Energy Shield", "エネルギーシールド", "에너지 보호막" },
    { "能量護盾", "Energy Shield", "エネルギーシールド", "에너지 보호막" }, {
    "生命之外的護盾值，受傷時優先扣除。\n護盾存在時受到傷害減免（上限80%）；受傷會重置護盾回復冷卻，體質越高冷卻越短。",
    "A shield separate from HP that is depleted first when taking damage.\nWhile the shield is active, damage taken is reduced, up to 80%. Taking damage resets its recovery cooldown; higher VIT shortens that cooldown.",
    "HPとは別のシールド値。ダメージを受けると先に消費される。\nシールドがある間は被ダメージを軽減（上限80%）。被弾すると回復クールタイムがリセットされ、体力が高いほどクールタイムが短い。",
    "체력과 별개인 보호막 수치로, 피해를 받을 때 먼저 소모됩니다.\n보호막이 있는 동안 받는 피해가 최대 80% 감소합니다. 피격 시 보호막 회복 대기시간이 초기화되며, 체질이 높을수록 대기시간이 짧습니다.",
})

-- 锻造用词沿用原词典；别名只用于匹配已有译文，不参与全局 lookup。
add("腐化", { "腐化", "Corruption", "腐化", "타락" }, { "腐化", "Corruption", "腐化", "타락" }, {
    "使用腐化石對裝備進行的構築性改造：將一條普通詞綴轉為同類型魔化詞條（數值×1.8），並疊加一層詛咒（基礎屬性-10%／層，最多3層）。\n魔化詞條在洗練／洗練石中保持固定；腐化後仍可洗練但精粹×2；可用神聖石逐層洗除詛咒（魔化詞條保留）。",
    "Corrupt Stone modifies gear for your build: converts one normal affix into a demonic affix of the same type (value ×1.8) and adds one curse stack (base stats -10% per stack, up to 3 stacks).\nDemonic affixes stay fixed during Reforge and Reforge Stone use. Corrupted gear can still be reforged, but essence cost is ×2. Holy Stone removes curses one stack at a time, keeping demonic affixes.",
    "腐化石による装備の構築改造。通常効果1個を同じ種類の魔化効果に変換（数値×1.8）し、呪いを1スタック追加する（基本能力-10%／スタック、最大3）。\n魔化効果は洗練や洗練石の使用時も固定。腐化後も洗練できるが精粋は2倍。神聖石で呪いを1スタックずつ浄化でき、魔化効果は残る。",
    "부화석으로 장비를 개조합니다. 일반 옵션 하나를 같은 유형의 마화 옵션으로 전환하고(수치 ×1.8), 저주 1중첩을 추가합니다(기본 능력치 -10%/중첩, 최대 3중첩).\n마화 옵션은 재련과 재련석 사용 시 고정됩니다. 타락 후에도 재련할 수 있지만 정수 비용은 2배입니다. 성석으로 저주를 한 중첩씩 제거하며 마화 옵션은 유지됩니다.",
})
add("腐化石", { "腐化石", "Corrupt Stone", "腐化石", "부화석" },
    { "腐化石", "Corrupt Stone", "腐化石", "부화석" }, {
    "洗練的附加材料：將一條普通詞綴轉為同類型魔化詞條，並疊加一層腐化詛咒。\n最多腐化3層；腐化後的裝備仍可洗練（精粹×2）。",
    "An extra Reforge material: converts one normal affix into a demonic affix of the same type and adds one Corruption curse stack.\nMaximum: 3 Corruption stacks. Corrupted gear can still be reforged, with essence cost ×2.",
    "洗練の追加素材。通常効果1個を同じ種類の魔化効果に変換し、腐化の呪いを1スタック追加する。\n腐化は最大3スタック。腐化した装備も洗練できる（精粋は2倍）。",
    "재련 추가 재료. 일반 옵션 하나를 같은 유형의 마화 옵션으로 전환하고 타락 저주 1중첩을 추가합니다.\n타락은 최대 3중첩. 타락한 장비도 재련할 수 있으며 정수 비용은 2배입니다.",
})
add("神圣石", { "神聖石", "Holy Stone", "神聖石", "성석" },
    { "神聖石", "Holy Stone", "神聖石", "성석" }, {
    "洗練的附加材料：洗除裝備一層腐化詛咒（基礎屬性恢復），魔化詞條保留。\n洗除不消耗精粹、不增加洗練次數；3層詛咒需3顆神聖石完全洗除。",
    "An extra Reforge material: removes one Corruption curse stack from gear, restoring base stats while keeping demonic affixes.\nCleansing costs no essence and does not increase the reforge count. Fully cleansing 3 curse stacks requires 3 Holy Stones.",
    "洗練の追加素材。装備の腐化の呪いを1スタック浄化して基本能力を戻し、魔化効果は残す。\n浄化は精粋を消費せず、洗練回数も増えない。呪い3スタックの完全浄化には神聖石が3個必要。",
    "재련 추가 재료. 장비의 타락 저주 1중첩을 제거하여 기본 능력치를 복구하며, 마화 옵션은 유지됩니다.\n정화는 정수를 소모하거나 재련 횟수를 늘리지 않습니다. 저주 3중첩을 모두 제거하려면 성석 3개가 필요합니다.",
})
add("洗练石", { "洗練石", "Reforge Stone", "洗練石", "재련석" },
    { "洗練石", "Reforge Stone", "洗練石", "재련석" }, {
    "洗練的附加材料：保留詞綴屬性種類不變，重新隨機品質等級和數值（可跨等級變化）。\n保底只升不降：每條詞綴取新舊數值中的較高者。",
    "An extra Reforge material: keeps affix stat types unchanged while rerolling quality grades and values, including changes across grades.\nGuaranteed no downgrade: each affix keeps the higher of its old and new values.",
    "洗練の追加素材。効果の能力種類を保ったまま品質等級と数値を再抽選する（等級をまたぐ変化も可能）。\n低下しない保証：各効果は新旧の数値のうち高い方を採用する。",
    "재련 추가 재료. 옵션의 능력치 유형을 유지한 채 품질 등급과 수치를 다시 무작위로 정하며, 등급이 달라질 수도 있습니다.\n하락 방지 보장: 각 옵션은 이전과 새 수치 중 높은 값을 유지합니다.",
})
add("点金石", { "點金石", "Gold Stone", "点金石", "점금석" },
    { "點金石", "Gold Stone", "点金石", "점금석" }, {
    "洗練的附加材料：洗練時將裝備提升品質，最高提到目前進度允許的品質。\n品質已達上限後轉為提升一條隨機普通詞綴的品級（最高 S 品）。",
    "An extra Reforge material: raises gear rarity when reforging, up to the rarity allowed by current progress.\nAt the rarity cap, it instead raises the grade of one random normal affix, up to grade S.",
    "洗練の追加素材。洗練時に装備のレア度を上げ、現在の進行で許される上限まで強化する。\nレア度が上限なら、代わりにランダムな通常効果1個の等級を上げる（最高S等級）。",
    "재련 추가 재료. 재련 시 현재 진행도에서 허용되는 상한까지 장비 등급을 높입니다.\n등급이 상한이면 무작위 일반 옵션 하나의 등급을 대신 높이며, 최대 S등급입니다.",
})
add("洗练", { "洗練", "Reforge", "洗練", "재련" }, { "洗練", "Reforge", "洗練", "재련" }, {
    "重新隨機裝備詞綴數值：不選附加或選精粹時消耗固定精粹（費用不隨次數增加）；選擇洗練石／點金石／腐化石／神聖石時不再消耗精粹，只消耗對應石頭。\n可鎖定詞條（鎖定後單次精粹費用提高）。",
    "Rerolls gear affix values. With no extra material or with essence selected, the essence cost is fixed and does not rise with reforge count. Choosing Reforge Stone, Gold Stone, Corrupt Stone, or Holy Stone costs only that stone, not essence.\nAffixes can be locked; locking increases the essence cost per reforge.",
    "装備効果の数値を再抽選する。追加素材なし、または精粋を選ぶ場合は固定量の精粋を消費し、回数で費用は増えない。洗練石・点金石・腐化石・神聖石を選ぶ場合は精粋を消費せず、該当の石だけを消費する。\n効果はロック可能（ロックすると1回あたりの精粋費用が増える）。",
    "장비 옵션 수치를 다시 무작위로 정합니다. 추가 재료를 선택하지 않거나 정수를 선택하면 고정된 정수 비용을 소모하며, 재련 횟수에 따라 늘지 않습니다. 재련석, 점금석, 부화석, 성석을 선택하면 정수 없이 해당 돌만 소모합니다.\n옵션을 잠글 수 있으며, 잠그면 재련 1회당 정수 비용이 증가합니다.",
})

-- 星图40项：既有完整属性名优先复用装备词典，未登记名称使用天赋标签。
-- 这样不会因关键词词典最后合并而改变装备的精确显示；差异标签仅作为匹配别名。
---@param key string
---@param descriptions string[]
---@param names string[]|nil
local function addStat(key, descriptions, names)
    local titles = {}
    for i, lang in ipairs(languages) do
        titles[i] = assert(Equipment[lang][key] or TalentText.label(key, lang), "Missing stat label: " .. key)
    end
    add(key, names or titles, titles, descriptions)
end

addStat("护盾伤害减免", {
    "護盾存在時，先按該比例減免本次傷害，再扣護盾。沒有來源時為 0，上限 80%。",
    "While Shield is active, reduce the incoming damage by this proportion before depleting Shield. With no source, the value is 0; capped at 80%.",
    "シールドがある間、まず今回のダメージをこの割合で軽減してからシールドを消費する。供給源がなければ0、上限80%。",
    "보호막이 있으면 이번 피해를 해당 비율만큼 먼저 감소시킨 뒤 보호막을 차감합니다. 부여하는 효과가 없으면 0이며, 상한은 80%입니다.",
})
addStat("物理格挡概率", {
    "有機率格擋物理傷害，格擋後只受到(1-格擋比例)的傷害，上限100%。",
    "Chance to block physical damage. After blocking, take only (1-block ratio) of the damage. Chance is capped at 100%.",
    "確率で物理ダメージをガードし、ガード後は(1-ガード軽減率)のダメージのみ受ける。確率の上限100%。",
    "확률적으로 물리 피해를 막으며, 막은 뒤에는 (1-막기 비율)만큼의 피해만 받습니다. 확률 상한은 100%입니다.",
})
addStat("魔法格挡概率", {
    "有機率格擋魔法傷害，格擋後只受到(1-格擋比例)的傷害，上限100%。",
    "Chance to block magic damage. After blocking, take only (1-block ratio) of the damage. Chance is capped at 100%.",
    "確率で魔法ダメージをガードし、ガード後は(1-ガード軽減率)のダメージのみ受ける。確率の上限100%。",
    "확률적으로 마법 피해를 막으며, 막은 뒤에는 (1-막기 비율)만큼의 피해만 받습니다. 확률 상한은 100%입니다.",
})
addStat("物理暴击伤害", {
    "基礎0%，與暴擊傷害為加法關係，物理暴擊時額外增加。",
    "Base 0%. Adds to Crit DMG as an extra bonus on physical critical hits.",
    "基本0%。会心ダメージに加算され、物理会心時に追加で適用する。",
    "기본 0%. 치명 피해에 더해지며, 물리 치명타 시 추가로 적용됩니다.",
})
addStat("魔法暴击伤害", {
    "基礎0%，與暴擊傷害為加法關係，魔法暴擊時額外增加。",
    "Base 0%. Adds to Crit DMG as an extra bonus on magic critical hits.",
    "基本0%。会心ダメージに加算され、魔法会心時に追加で適用する。",
    "기본 0%. 치명 피해에 더해지며, 마법 치명타 시 추가로 적용됩니다.",
})
addStat("物理攻击加成", {
    "百分比增加物理攻擊力。", "Increases Phys ATK by a percentage.",
    "物理攻撃力を割合で増加させる。", "물리 공격력을 백분율로 증가시킵니다.",
})
addStat("魔法攻击加成", {
    "百分比增加魔法攻擊力。", "Increases Magic ATK by a percentage.",
    "魔法攻撃力を割合で増加させる。", "마법 공격력을 백분율로 증가시킵니다.",
})
addStat("物理伤害加成", {
    "所有傷害加成為加法關係，造成物理傷害時計入。",
    "All damage bonuses add together. This bonus applies when dealing physical damage.",
    "すべてのダメージ補正は加算される。物理ダメージを与える時に適用する。",
    "모든 피해 보너스는 합산됩니다. 물리 피해를 줄 때 적용됩니다.",
})
addStat("魔法伤害加成", {
    "所有傷害加成為加法關係，造成魔法傷害時計入。",
    "All damage bonuses add together. This bonus applies when dealing magic damage.",
    "すべてのダメージ補正は加算される。魔法ダメージを与える時に適用する。",
    "모든 피해 보너스는 합산됩니다. 마법 피해를 줄 때 적용됩니다.",
})
addStat("物理暴击率", {
    "與暴擊率為加法關係，造成物理傷害時額外增加到暴擊率計算中。",
    "Adds to Crit Rate when calculating the critical chance of physical damage.",
    "会心率に加算され、物理ダメージを与える時の会心率計算に追加する。",
    "치명타율에 더해지며, 물리 피해를 줄 때 치명타율 계산에 추가됩니다.",
})
addStat("魔法暴击率", {
    "與暴擊率為加法關係，造成魔法傷害時額外增加到暴擊率計算中。",
    "Adds to Crit Rate when calculating the critical chance of magic damage.",
    "会心率に加算され、魔法ダメージを与える時の会心率計算に追加する。",
    "치명타율에 더해지며, 마법 피해를 줄 때 치명타율 계산에 추가됩니다.",
})
addStat("治疗暴击率", {
    "治療時有機率觸發暴擊。", "Chance for healing to critically hit.",
    "回復時に確率で会心が発生する。", "치유 시 확률적으로 치명타가 발동합니다.",
})
addStat("物理攻击力", {
    "單位基礎物理攻擊力。", "The unit's base Phys ATK.",
    "ユニットの基本物理攻撃力。", "유닛의 기본 물리 공격력입니다.",
})
addStat("魔法攻击力", {
    "單位基礎魔法攻擊力。", "The unit's base Magic ATK.",
    "ユニットの基本魔法攻撃力。", "유닛의 기본 마법 공격력입니다.",
})
addStat("物理穿透", {
    "造成物理傷害時與護甲對抗，能1:1抵消目標的護甲。",
    "Counters Armor when dealing physical damage, offsetting the target's Armor at a 1:1 ratio.",
    "物理ダメージを与える時に防御と対抗し、対象の防御を1:1で相殺する。",
    "물리 피해를 줄 때 방어력에 대항하며, 대상의 방어력을 1:1로 상쇄합니다.",
})
addStat("魔法穿透", {
    "造成魔法傷害時與護甲對抗，能1:1抵消目標的護甲。",
    "Counters Armor when dealing magic damage, offsetting the target's Armor at a 1:1 ratio.",
    "魔法ダメージを与える時に防御と対抗し、対象の防御を1:1で相殺する。",
    "마법 피해를 줄 때 방어력에 대항하며, 대상의 방어력을 1:1로 상쇄합니다.",
})
addStat("连击概率", {
    "有機率在0.1秒後額外攻擊一次，超過100%仍有效。",
    "Chance to make one additional attack after 0.1 seconds. Chance above 100% remains effective.",
    "確率で0.1秒後に追加攻撃を一回行う。確率は100%を超えても有効。",
    "확률적으로 0.1초 후 추가 공격을 한 번 합니다. 확률은 100%를 넘어도 유효합니다.",
})
addStat("连击增伤", {
    "每次連擊後增加的額外傷害，逐次遞增。",
    "Extra damage added after each combo hit, increasing with successive hits.",
    "連撃ごとに追加するダメージ。回を重ねるほど増加する。",
    "연격마다 추가되는 피해로, 차례로 증가합니다.",
})
addStat("攻击速度", {
    "影響攻擊間隔的百分比加成，實際間隔=基礎間隔/(1+攻擊速度%)。",
    "A percentage bonus affecting attack intervals. Actual interval=base interval/(1+Attack Speed%).",
    "攻撃間隔に影響する割合補正。実際の間隔=基本間隔/(1+攻撃速度%)。",
    "공격 간격에 영향을 주는 백분율 보너스입니다. 실제 간격=기본 간격/(1+공격 속도%).",
})
addStat("暴击伤害", {
    "基礎200%，暴擊時傷害乘以該值，即預設暴擊造成2倍傷害。",
    "Base 200%. Critical damage is multiplied by this value, so critical hits deal 2 times damage by default.",
    "基本200%。会心時にダメージへこの値を掛けるため、初期状態では会心が2倍のダメージを与える。",
    "기본 200%. 치명타 시 피해에 이 값을 곱하므로, 기본 치명타는 2배 피해를 줍니다.",
})
addStat("生命加成", {
    "百分比增加生命值上限。", "Increases max HP by a percentage.",
    "最大HPを割合で増加させる。", "최대 체력을 백분율로 증가시킵니다.",
})
addStat("护甲加成", {
    "百分比增加護甲。", "Increases Armor by a percentage.",
    "防御を割合で増加させる。", "방어력을 백분율로 증가시킵니다.",
})
addStat("护盾加成", {
    "百分比增加護盾上限。", "Increases max Shield by a percentage.",
    "シールド上限を割合で増加させる。", "최대 보호막을 백분율로 증가시킵니다.",
})
addStat("治疗加成", {
    "對治療值進行百分比加成。", "Applies a percentage bonus to healing.",
    "回復量に割合補正を適用する。", "치유량에 백분율 보너스를 적용합니다.",
})
addStat("闪避加成", {
    "百分比增加閃避值。", "Increases Dodge by a percentage.",
    "回避値を割合で増加させる。", "회피 수치를 백분율로 증가시킵니다.",
})
addStat("每秒回血", {
    "每秒恢復的生命值，可被治療屬性增幅。",
    "HP restored per second. Can be increased by healing stats.",
    "毎秒回復するHP。回復能力によって増幅できる。",
    "매초 회복하는 체력으로, 치유 능력치로 증가시킬 수 있습니다.",
})
addStat("命中值", {
    "影響命中機率，命中率=(命中值+150)/(閃避值+150)。",
    "Affects hit chance. Hit chance=(Accuracy+150)/(Dodge+150).",
    "命中率に影響する。命中率=(命中値+150)/(回避値+150)。",
    "명중 확률에 영향을 줍니다. 명중률=(명중 수치+150)/(회피 수치+150).",
})
addStat("闪避值", {
    "影響被命中機率，命中率=(命中值+150)/(閃避值+150)。",
    "Affects the chance of being hit. Hit chance=(Accuracy+150)/(Dodge+150).",
    "攻撃を受ける確率に影響する。命中率=(命中値+150)/(回避値+150)。",
    "피격 확률에 영향을 줍니다. 명중률=(명중 수치+150)/(회피 수치+150).",
})
addStat("暴击率", {
    "通用暴擊率，同時作用於物理傷害與魔法傷害。",
    "General critical chance, applying to both physical and magic damage.",
    "物理ダメージと魔法ダメージの両方に適用される共通会心率。",
    "물리 피해와 마법 피해 모두에 적용되는 공통 치명타율입니다.",
})
addStat("生命值", {
    "生命上限。生命歸零則死亡。", "Maximum HP. Reaching zero HP causes death.",
    "HPの上限。HPがゼロになると死亡する。", "최대 체력입니다. 체력이 모두 소진되면 사망합니다.",
})
-- Threat 已属于「仇恨」；用独立显示匹配名区分怨引值，完整原文标题沿用已有词典。
addStat("怨引值", {
    "影響被敵方隨機攻擊的權重，仇恨值越高越容易被集火。",
    "Affects the weight used when enemies choose a random attack target. Higher threat values make concentrated attacks more likely.",
    "敵のランダム攻撃対象に選ばれる重みに影響する。ヘイト値が高いほど集中攻撃を受けやすい。",
    "적의 무작위 공격 대상이 되는 가중치에 영향을 줍니다. 위협 수치가 높을수록 집중 공격을 받기 쉽습니다.",
}, { "怨引值", "Threat Value", "敵視値", "위협 수치" })
add("怨引", { "怨引", "Threat Weight", "敵視重み", "어그로 가중치" },
    { "怨引", "Threat Weight", "敵視重み", "어그로 가중치" }, {
    "怨引值的簡稱。影響被敵方隨機攻擊的權重，數值越高越容易被集火。",
    "Short for Threat Value. Affects the weight used when enemies choose a random attack target; higher values make concentrated attacks more likely.",
    "敵視値の略称。敵のランダム攻撃対象に選ばれる重みに影響し、値が高いほど集中攻撃を受けやすい。",
    "위협 수치의 줄임말입니다. 적의 무작위 공격 대상이 되는 가중치에 영향을 주며, 수치가 높을수록 집중 공격을 받기 쉽습니다.",
})
addStat("护甲", {
    "將同比轉化為傷害抗性，轉化率 = 護甲/(護甲+100)。",
    "Converts proportionally into damage resistance. Conversion rate = Armor/(Armor+100).",
    "防御を比例してダメージ耐性に変換する。変換率 = 防御/(防御+100)。",
    "비례하여 피해 저항으로 전환됩니다. 전환율 = 방어력/(방어력+100).",
})
addStat("护盾", {
    "受傷時先扣除護盾，護盾扣完後才扣生命。回復速度跟體質：體質越高，受傷後等待越短。",
    "Damage depletes Shield first, then HP once Shield is exhausted. Recovery speed depends on VIT: higher VIT means a shorter wait after taking damage.",
    "被ダメージは先にシールドを消費し、シールドがなくなるとHPを消費する。回復速度は体力に依存し、体力が高いほど被弾後の待ち時間が短い。",
    "피격 시 보호막이 먼저 소모되고, 보호막이 모두 소모된 뒤 체력이 차감됩니다. 회복 속도는 체질에 따라 달라지며, 체질이 높을수록 피격 후 대기시간이 짧습니다.",
})
addStat("力量", {
    "每1點增加1物理攻擊力、0.5%物理傷害加成、1.0護甲、5生命值。",
    "Each 1 point grants 1 Phys ATK, 0.5% Phys DMG bonus, 1.0 Armor, and 5 HP.",
    "1ポイントにつき物理攻撃力1、物理ダメージ補正0.5%、防御1.0、HP5を追加する。",
    "1포인트마다 물리 공격력1, 물리 피해 보너스0.5%, 방어력1.0, 체력5가 증가합니다.",
})
addStat("敏捷", {
    "每1點增加0.5物理攻擊力、0.5魔法攻擊力、0.4%攻擊速度、0.15護甲、0.1%閃避加成、0.4命中值、0.35閃避值。",
    "Each 1 point grants 0.5 Phys ATK, 0.5 Magic ATK, 0.4% Attack speed, 0.15 Armor, 0.1% Dodge bonus, 0.4 Accuracy, and 0.35 Dodge.",
    "1ポイントにつき物理攻撃力0.5、魔法攻撃力0.5、攻撃速度0.4%、防御0.15、回避補正0.1%、命中値0.4、回避値0.35を追加する。",
    "1포인트마다 물리 공격력0.5, 마법 공격력0.5, 공격 속도0.4%, 방어력0.15, 회피 보너스0.1%, 명중 수치0.4, 회피 수치0.35가 증가합니다.",
})
addStat("秘识", {
    "每1點增加1魔法攻擊力、0.5%魔法傷害加成、3.0護盾、0.5%護盾加成、8生命值。",
    "Each 1 point grants 1 Magic ATK, 0.5% Magic DMG bonus, 3.0 Shield, 0.5% Shield bonus, and 8 HP.",
    "1ポイントにつき魔法攻撃力1、魔法ダメージ補正0.5%、シールド3.0、シールド補正0.5%、HP8を追加する。",
    "1포인트마다 마법 공격력1, 마법 피해 보너스0.5%, 보호막3.0, 보호막 보너스0.5%, 체력8이 증가합니다.",
})
addStat("体质", {
    "每1點增加33生命值、0.5%護甲加成、2.0護盾。",
    "Each 1 point grants 33 HP, 0.5% Armor bonus, and 2.0 Shield.",
    "1ポイントにつきHP33、防御補正0.5%、シールド2.0を追加する。",
    "1포인트마다 체력33, 방어 보너스0.5%, 보호막2.0이 증가합니다.",
})
addStat("命数", {
    "每1點增加0.5物理攻擊力、0.5魔法攻擊力、0.5%最大傷害加成、0.3%暴擊機率、1.5%暴擊傷害、0.34閃避值。",
    "Each 1 point grants 0.5 Phys ATK, 0.5 Magic ATK, 0.5% Max DMG bonus, 0.3% Crit Rate, 1.5% Crit DMG, and 0.34 Dodge.",
    "1ポイントにつき物理攻撃力0.5、魔法攻撃力0.5、最大ダメージ補正0.5%、会心率0.3%、会心ダメージ1.5%、回避値0.34を追加する。",
    "1포인트마다 물리 공격력0.5, 마법 공격력0.5, 최대 피해 보너스0.5%, 치명타율0.3%, 치명 피해1.5%, 회피 수치0.34가 증가합니다.",
})
addStat("魂火", {
    "每1點增加2.5護盾、0.5%護盾加成、0.1%異常狀態抗性、1治療量、0.4%治療加成、10生命值。",
    "Each 1 point grants 2.5 Shield, 0.5% Shield bonus, 0.1% status resistance, 1 Healing, 0.4% Heal bonus, and 10 HP.",
    "1ポイントにつきシールド2.5、シールド補正0.5%、状態異常耐性0.1%、回復量1、回復強化0.4%、HP10を追加する。",
    "1포인트마다 보호막2.5, 보호막 보너스0.5%, 상태 이상 저항0.1%, 치유량1, 회복 보너스0.4%, 체력10이 증가합니다.",
})

--- 精确完整原文查询；未知文本和无效语言返回 nil，供 I18n.lookup 原文回退。
---@param text any
---@param lang string
---@return string|nil
function D.lookup(text, lang)
    if type(text) ~= "string" then return nil end
    local pack = D[lang]
    if type(pack) == "table" then return pack[text] end
    if lang == "zh_CN" then
        for key, source in pairs(KW.KEYWORDS) do
            if text == key or text == source.title or text == source.desc then return text end
        end
    end
    return nil
end

--- 获取完整本地化定义的副本；业务 key 始终保持原文，不修改 KeywordConfig。
---@param key string
---@param lang string
---@return {key:string, title:string, desc:string}|nil
function D.get(key, lang)
    local source = KW.get(key)
    if not source then return nil end
    local translated = definitions[lang] and definitions[lang][key]
    return { key = key, title = translated and translated.title or source.title,
        desc = translated and translated.desc or source.desc }
end

---@param key string
---@param lang string
---@return string|nil
function D.name(key, lang)
    local source = KW.get(key)
    if not source then return nil end
    local translated = definitions[lang] and definitions[lang][key]
    return translated and translated.name or key
end

-- 只对已显示的词做高亮匹配。旧/其他分区的确切译词作为显式别名，不用于句子改写。
local function aliases(lang)
    if lang == "zh_CN" then
        return { { "护盾减伤", "护盾伤害减免" } }
    elseif lang == "zh_TW" then
        return { { "護盾減傷", "护盾伤害减免" }, { "護盾傷害減免", "护盾伤害减免" } }
    elseif lang == "en" then
        return { { "Sacred Stone", "神圣石" }, { "Alchemy Stone", "点金石" },
            { "Corruption Stone", "腐化石" }, { "Bones", "骸骨" }, { "Gate-gap", "门缝" },
            { "ASPD", "攻击速度" }, { "Phys Crit Rate", "物理暴击率" },
            { "Phys DMG Bonus", "物理伤害加成" }, { "Hit", "命中值" },
            { "Heal Bonus", "治疗加成" }, { "Threat", "仇恨" }, { "Threat Value", "怨引值" },
            { "Threat Weight", "怨引" } }
    elseif lang == "ja" then
        return { { "敵視", "仇恨" }, { "門の隙間", "门缝" }, { "錬金石", "点金石" },
            { "物理会心", "物理暴击率" }, { "魔法会心", "魔法暴击率" },
            { "回復会心", "治疗暴击率" }, { "回復補正", "治疗加成" } }
    elseif lang == "ko" then
        return { { "신성석", "神圣石" }, { "연금석", "点金石" }, { "타락석", "腐化石" },
            { "치명타 피해", "暴击伤害" }, { "물리 치명타 피해", "物理暴击伤害" },
            { "마법 치명타 피해", "魔法暴击伤害" }, { "초당 체력 회복", "每秒回血" },
            { "초당 생명 회복", "每秒回血" }, { "생명 보너스", "生命加成" },
            { "어그로 수치", "怨引值" } }
    end
    return {}
end

-- 只有四个语言字段是table，terms缓存保持私有，不进入词典合并。
---@type table<string, {text:string, key:string}[]>
local termCache = {}

--- 长词优先的显示词→原业务 key 列表；简体 fallback 只标色，不替换文字。
---@param lang string
---@return {text:string, key:string}[]
function D.terms(lang)
    if termCache[lang] then return termCache[lang] end
    local terms, seen = {}, {}
    local function append(text, key)
        if type(text) == "string" and text ~= "" and not seen[text] then
            terms[#terms + 1] = { text = text, key = key }
            seen[text] = true
        end
    end
    -- 显式指定的别名优先；英文同词Threat固定解释「仇恨」，不由排序/新增属性抢占。
    for _, pair in ipairs(aliases(lang)) do append(pair[1], pair[2]) end
    for _, key in ipairs(KW.sortedKeys()) do
        append(D.name(key, lang), key)
        append(key, key)
        if definitions[lang] and definitions[lang][key] then
            append(TalentText.label(key, lang), key)
            append(Equipment[lang][key], key)
        end
    end
    table.sort(terms, function(a, b)
        if #a.text ~= #b.text then return #a.text > #b.text end
        return a.text < b.text
    end)
    termCache[lang] = terms
    return terms
end

return D
