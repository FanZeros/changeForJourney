-- 装备显示词典聚合：只存简体原文→繁/英/日/韩，不触碰模板、存档和资源名。
-- 子词典按原配置分区；I18n 只需 merge 本模块返回的四个语言包。
local AD = require("systems.AttributeDef")
---@type table<string, table<string, string>>
local D = { zh_TW = {}, en = {}, ja = {}, ko = {} }

local function merge(pack)
    for lang, entries in pairs(pack) do
        for source, translated in pairs(entries) do
            D[lang][source] = translated
        end
    end
end

merge(require("core.I18nEquipmentArms"))
merge(require("core.I18nEquipmentArmor"))
merge(require("core.I18nEquipmentSpecial"))
merge(require("core.I18nEquipmentSets"))

local function add(zh, tw, en, ja, ko)
    D.zh_TW[zh], D.en[zh], D.ja[zh], D.ko[zh] = tw, en, ja, ko
end

-- 81+套装追加装备：只补充新原文键，沿用虫壳/无面套装的四语用语。
add("虫壳战刃", "蟲殼戰刃", "Carapace Warblade", "虫殻の戦刃", "벌레껍질 전투검")
add("虫壳巨刃", "蟲殼巨刃", "Carapace Greatblade", "虫殻の巨刃", "벌레껍질 거검")
add("虫壳重盾", "蟲殼重盾", "Carapace Heavy Shield", "虫殻の重盾", "벌레껍질 중량 방패")
add("无面影刃", "無面影刃", "Faceless Shadowblade", "無面の影刃", "무면의 그림자 칼날")

-- AffixConfig 的57项：16项译文沿用原词典，新增41项（含13个魔化词缀）。
add("力量", "力量", "STR", "力", "힘")
add("敏捷", "敏捷", "AGI", "敏捷", "민첩")
add("秘识", "秘識", "INT", "知力", "지력")
add("体质", "體質", "VIT", "体力", "체질")
add("命数", "命數", "LUK", "運", "운")
add("幸运值", "幸運值", "Drop Luck", "ドロップ運", "드롭 행운")
add(AD.DROP_LUCK_DESC,
    "本隊出戰成員的幸運值相加，開戰時確定，本場陣亡不扣除。每1點使主線擊殺裝備掉落機率相對提高1%；品質Q1至Q6的原有權重分別乘以1、1+幸運值/500、1+2×幸運值/500、1+3×幸運值/500、1+4×幸運值/500、1+幸運值/100。本隊有效幸運值最多200，掉落機率最多100%，不突破關卡品質上限或開啟原權重為0的品質。不影響離線、掃蕩、副本固定獎勵、卷軸或詞條品級。",
    "Adds the Drop Luck of this team's deployed heroes at battle start; deaths do not reduce it. Each point raises the main-story kill equipment drop chance by 1% relative to its base chance. Original Q1-Q6 rarity weights are multiplied by 1, 1+Luck/500, 1+2*Luck/500, 1+3*Luck/500, 1+4*Luck/500, and 1+Luck/100. Effective team Luck caps at 200 and drop chance at 100%. Stage rarity caps and zero-weight rarities remain unchanged. Offline income, sweeps, fixed dungeon rewards, scrolls, and affix grades are unaffected.",
    "戦闘開始時に、この隊の出撃メンバーのドロップ運を合算します。戦闘中の死亡では減りません。1点につきメインストーリー討伐の装備ドロップ率が元の確率に対して1%上昇。Q1～Q6の元の抽選重みをそれぞれ1、1+運/500、1+2×運/500、1+3×運/500、1+4×運/500、1+運/100倍にします。有効な隊の運は最大200、ドロップ率は最大100%。ステージのレア度上限と重み0のレア度は変わりません。オフライン、掃討、ダンジョン固定報酬、巻物、効果等級には影響しません。",
    "전투 시작 시 이 부대의 출전 영웅 드롭 행운을 합산하며, 전투 중 사망해도 감소하지 않습니다. 1점당 메인 스토리 처치 장비 드롭 확률이 기본 확률 대비 1% 증가합니다. Q1~Q6의 기존 등급 가중치에 각각 1, 1+행운/500, 1+2×행운/500, 1+3×행운/500, 1+4×행운/500, 1+행운/100을 곱합니다. 부대 유효 행운은 최대 200, 드롭 확률은 최대 100%입니다. 스테이지 등급 상한과 가중치 0 등급은 바뀌지 않습니다. 오프라인, 소탕, 던전 고정 보상, 두루마리 및 옵션 등급에는 영향을 주지 않습니다.")
add("魂火", "魂火", "Spirit", "魂火", "혼화")
add("生命值", "生命值", "HP", "HP", "체력")
add("护甲", "護甲", "Armor", "鎧", "갑옷")
add("暴击率", "暴擊率", "Crit Rate", "会心率", "치명타율")
add("暴击伤害", "暴擊傷害", "Crit DMG", "会心ダメージ", "치명 피해")
add("暴击治疗", "暴擊治療", "Critical Healing", "会心回復量", "치명타 치유")
add("当前装备 · 生效数值", "目前裝備 · 生效數值", "Equipped · Effective Stats", "装備中・適用値", "현재 장비 · 적용 수치")
add("治疗暴击时使用的治疗倍率，基础200%。", "治療暴擊時使用的治療倍率，基礎200%。", "Healing multiplier on a critical heal; base 200%.", "会心回復時の回復倍率。基本値は200%。", "치명타 치유 시 적용되는 회복 배율. 기본값은 200%입니다.")
add("物理暴击率", "物理暴擊率", "Phys crit", "物理会心", "물리 치명타")
add("魔法暴击率", "魔法暴擊率", "Magic crit", "魔法会心", "마법 치명타")
add("物理穿透", "物理穿透", "Phys pen", "物理貫通", "물리 관통")
add("魔法穿透", "魔法穿透", "Magic pen", "魔法貫通", "마법 관통")
add("治疗加成", "治療加成", "Heal bonus", "回復強化", "회복 보너스")
add("治疗暴击率", "治療暴擊率", "Heal crit", "回復会心", "회복 치명타")
add("护盾", "護盾", "Shield", "シールド", "보호막")
add("闪避值", "閃避值", "Dodge", "回避値", "회피 수치")
add("每秒回血", "每秒回血", "HP regen/s", "毎秒HP回復", "초당 생명 회복")
add("攻击回血", "攻擊回血", "HP on attack", "攻撃時HP回復", "공격 시 생명 회복")
add("物理格挡概率", "物理格擋機率", "Phys block chance", "物理ガード率", "물리 막기 확률")
add("魔法格挡概率", "魔法格擋機率", "Magic block chance", "魔法ガード率", "마법 막기 확률")
add("异常抗性", "異常抗性", "Status resistance", "状態異常耐性", "상태 이상 저항")
add("物理攻击力", "物理攻擊力", "Phys ATK", "物理攻撃力", "물리 공격력")
add("魔法攻击力", "魔法攻擊力", "Magic ATK", "魔法攻撃力", "마법 공격력")
add("攻击速度", "攻擊速度", "Attack speed", "攻撃速度", "공격 속도")
add("物理暴击伤害", "物理暴擊傷害", "Phys crit DMG", "物理会心ダメージ", "물리 치명타 피해")
add("魔法暴击伤害", "魔法暴擊傷害", "Magic crit DMG", "魔法会心ダメージ", "마법 치명타 피해")
add("伤害加成", "傷害加成", "DMG bonus", "ダメージ補正", "피해 보너스")
add("物理伤害加成", "物理傷害加成", "Phys DMG bonus", "物理ダメージ補正", "물리 피해 보너스")
add("魔法伤害加成", "魔法傷害加成", "Magic DMG bonus", "魔法ダメージ補正", "마법 피해 보너스")
add("连击概率", "連擊機率", "Combo chance", "連撃率", "연격 확률")
add("连击增伤", "連擊增傷", "Combo DMG bonus", "連撃ダメージ補正", "연격 피해 보너스")
-- 旧名称保留兼容；新名称与描述按基础护甲相性判定，百分比加成整体结算。
add("最大伤害加成", "最大傷害加成", "Max DMG bonus", "最大ダメージ補正", "최대 피해 보너스")
add("最小伤害加成", "最小傷害加成", "Min DMG bonus", "最小ダメージ補正", "최소 피해 보너스")
add("优势伤害", "優勢傷害", "Advantage DMG", "有利ダメージ", "상성 우위 피해")
add("劣势伤害", "劣勢傷害", "Disadvantage DMG", "不利ダメージ", "상성 열위 피해")
add(AD.ADVANTAGE_DAMAGE_DESC,
    "攻擊類型對目標護甲的基礎倍率大於1時，額外提高本次傷害，倍率為1+優勢傷害/100。中立、劣勢、治療及無視剋制的混沌傷害不生效。",
    "When the base multiplier for the attack type against the target's armor type is greater than 1, multiply the full damage of this instance by 1+Advantage DMG/100. Does not apply to neutral or unfavorable matchups, healing, or chaos damage that ignores armor matchups.",
    "攻撃タイプと対象の装甲タイプで決まる基本倍率が1より大きい時、今回のダメージ全体に1+有利ダメージ/100を掛けます。中立・不利な相性、回復、相性を無視する混沌ダメージには適用されません。",
    "공격 유형과 대상의 방어구 유형에 따른 기본 배율이 1보다 클 때, 이번 피해 전체에 1+상성 우위 피해/100을 곱합니다. 중립·불리한 상성, 치유 및 상성을 무시하는 혼돈 피해에는 적용되지 않습니다.")
add(AD.DISADVANTAGE_DAMAGE_DESC,
    "攻擊類型對目標護甲的基礎倍率大於0且小於1時，額外提高本次傷害，倍率為1+劣勢傷害/100。中立、優勢、治療及無視剋制的混沌傷害不生效。",
    "When the base multiplier for the attack type against the target's armor type is greater than 0 and less than 1, multiply the full damage of this instance by 1+Disadvantage DMG/100. Does not apply to neutral or favorable matchups, healing, or chaos damage that ignores armor matchups.",
    "攻撃タイプと対象の装甲タイプで決まる基本倍率が0より大きく1より小さい時、今回のダメージ全体に1+不利ダメージ/100を掛けます。中立・有利な相性、回復、相性を無視する混沌ダメージには適用されません。",
    "공격 유형과 대상의 방어구 유형에 따른 기본 배율이 0보다 크고 1보다 작을 때, 이번 피해 전체에 1+상성 열위 피해/100을 곱합니다. 중립·유리한 상성, 치유 및 상성을 무시하는 혼돈 피해에는 적용되지 않습니다.")
add("命中值", "命中值", "Accuracy", "命中値", "명중 수치")
add("治疗量", "治療量", "Healing", "回復量", "회복량")
add("治疗暴击加成", "治療暴擊加成", "Heal crit bonus", "回復会心補正", "회복 치명타 보너스")
add("物理攻击加成", "物理攻擊加成", "Phys ATK bonus", "物理攻撃補正", "물리 공격 보너스")
add("魔法攻击加成", "魔法攻擊加成", "Magic ATK bonus", "魔法攻撃補正", "마법 공격 보너스")
add("生命加成", "生命加成", "HP bonus", "HP補正", "생명 보너스")
add("闪避加成", "閃避加成", "Dodge bonus", "回避補正", "회피 보너스")
add("护盾加成", "護盾加成", "Shield bonus", "シールド補正", "보호막 보너스")
add("护甲加成", "護甲加成", "Armor bonus", "防御補正", "방어 보너스")
add("最终物攻", "最終物攻", "Final phys ATK", "最終物理攻撃", "최종 물리 공격")
add("最终魔攻", "最終魔攻", "Final magic ATK", "最終魔法攻撃", "최종 마법 공격")
add("最终生命", "最終生命", "Final HP", "最終HP", "최종 생명")
add("最终伤害", "最終傷害", "Final DMG", "最終ダメージ", "최종 피해")
add("最终力量", "最終力量", "Final STR", "最終筋力", "최종 힘")
add("最终敏捷", "最終敏捷", "Final AGI", "最終敏捷", "최종 민첩")
add("最终智慧", "最終智慧", "Final WIT", "最終知力", "최종 지혜")
add("最终体质", "最終體質", "Final VIT", "最終体力", "최종 체질")
add("最终运气", "最終運氣", "Final LUK", "最終運", "최종 운")
add("最终精神", "最終精神", "Final SPI", "最終精神", "최종 정신")
add("最终护甲", "最終護甲", "Final armor", "最終防御", "최종 방어")
add("最终护盾", "最終護盾", "Final shield", "最終シールド", "최종 보호막")
add("最终闪避", "最終閃避", "Final dodge", "最終回避", "최종 회피")

-- AttributeDef 采用当前世界观名，与存档中旧词缀名并存，不能改源字段。
add("最终秘识", "最終秘識", "Final Lore", "最終秘知", "최종 비지")
add("最终命数", "最終命數", "Final Fate", "最終運命", "최종 운명")
add("最终魂火", "最終魂火", "Final Soulfire", "最終魂火", "최종 혼불")
add("伤害抗性", "傷害抗性", "DMG resistance", "ダメージ耐性", "피해 저항")
add("怨引值", "怨引值", "Threat", "敵視値", "위협 수치")
add("物理格挡比例", "物理格擋比例", "Phys block ratio", "物理ガード軽減率", "물리 막기 비율")
add("魔法格挡比例", "魔法格擋比例", "Magic block ratio", "魔法ガード軽減率", "마법 막기 비율")
add("护盾伤害减免", "護盾減傷", "Shield DMG reduction", "シールド被ダメージ軽減", "보호막 피해 감소")
add("护盾减伤", "護盾減傷", "Shield DMG reduction", "シールド被ダメージ軽減", "보호막 피해 감소")

-- 真实显示调用点的完整模板：printf占位符类型、次序和数字精度必须保持。
add("升阶", "升階", "Ascend", "昇格", "승급")
add("一键升阶", "一鍵升階", "Ascend all", "一括昇格", "일괄 승급")
add("升阶需求", "升階需求", "Ascension cost", "昇格コスト", "승급 비용")
add("已达到最高升阶等级", "已達到最高升階等級", "Maximum ascension reached", "昇格上限に到達", "최대 승급 단계 도달")
add("选择目标升阶等级", "選擇目標升階等級", "Choose ascension level", "昇格先の段階を選択", "목표 승급 단계 선택")
add("%s 升阶", "%s 升階", "%s · Ascension", "%sの昇格", "%s 승급")
add("%d 条随机词条", "%d 條隨機詞條", "%d random affixes", "ランダム効果%d個", "무작위 옵션 %d개")
add("词条倍率 ×%.2f → ×%.2f", "詞條倍率 ×%.2f → ×%.2f", "Affix multiplier ×%.2f → ×%.2f", "効果倍率 ×%.2f → ×%.2f", "옵션 배율 ×%.2f → ×%.2f")
add("词条倍率 ×%.2f", "詞條倍率 ×%.2f", "Affix multiplier ×%.2f", "効果倍率 ×%.2f", "옵션 배율 ×%.2f")
add("副属性轮转强化 %d 次", "副屬性輪轉強化 %d 次", "%d rotating substat boosts", "副能力を順に%d回強化", "보조 능력 순환 강화 %d회")
add("将新增 %s", "將新增 %s", "Gains: %s", "獲得予定：%s", "획득 예정: %s")
add("升阶获得：%s", "升階獲得：%s", "Ascension gains: %s", "昇格で獲得：%s", "승급 획득: %s")
add("随机词条", "隨機詞條", "Random affix", "ランダム効果", "무작위 옵션")
add("腐化状态：诅咒 %d/%d 层", "腐化狀態：詛咒 %d/%d 層", "Corruption: curse %d/%d stacks", "腐化状態：呪い%d/%d層", "타락 상태: 저주 %d/%d중첩")
add("腐化状态：诅咒 %d/%d 层（需神圣石洗除）", "腐化狀態：詛咒 %d/%d 層（需神聖石洗除）", "Corruption: curse %d/%d stacks (Sacred Stone required)", "腐化状態：呪い%d/%d層（神聖石で浄化）", "타락 상태: 저주 %d/%d중첩 (신성석으로 정화)")
add("词缀「%s」品级 %s → %s", "詞綴「%s」品級 %s → %s", "Affix [%s] grade %s → %s", "効果「%s」等級 %s → %s", "옵션 [%s] 등급 %s → %s")
add("已洗除 1 层诅咒，剩余 %d 层", "已洗除 1 層詛咒，剩餘 %d 層", "1 curse stack cleansed; %d remain", "呪いを1層浄化、残り%d層", "저주 1중첩 정화, %d중첩 남음")
add("腐化诅咒已全部洗除", "腐化詛咒已全部洗除", "All curse stacks cleansed", "腐化の呪いをすべて浄化", "타락 저주 모두 정화")
add("洗除诅咒", "洗除詛咒", "Cleanse curse", "呪いを浄化", "저주 정화")
add("魔化词条保留，可继续洗除剩余层数", "魔化詞條保留，可繼續洗除剩餘層數", "Corrupted affixes remain. Cleanse the remaining stacks.", "魔化効果は保持。残りの呪いも浄化可能", "타락 옵션은 유지됩니다. 남은 중첩도 정화할 수 있습니다")
add("魔化词条保留，装备已无诅咒减益", "魔化詞條保留，裝備已無詛咒減益", "Corrupted affixes remain. No curse penalties.", "魔化効果は保持。呪いの弱体効果は解除", "타락 옵션은 유지됩니다. 저주 약화 효과가 사라졌습니다")
add("魔化转换", "魔化轉換", "Corrupted conversion", "魔化変換", "타락 변환")
add("魔化完成", "魔化完成", "Corruption complete", "魔化完了", "타락 완료")
add("装备品质已达进度上限，点金石转为提升词缀品级", "裝備品質已達進度上限，點金石轉為提升詞綴品級", "Rarity capped by progress. Alchemy Stone raises affix grade instead.", "装備レア度は進行上限。錬金石で効果等級を強化", "진행도에 따른 장비 등급 상한 도달. 연금석은 옵션 등급을 높입니다")
add("至少保留1条词缀未锁定", "至少保留1條詞綴未鎖定", "Leave at least 1 affix unlocked", "効果を最低1個はロック解除", "옵션을 최소 1개 잠금 해제하세요")
add("请点击提品，提升装备品质", "請點擊提品，提升裝備品質", "Tap Raise Rarity to improve gear", "レア度強化で装備を強化", "등급 향상을 눌러 장비 등급을 높이세요")
add("词缀已自动生成", "詞綴已自動生成", "Affixes generated automatically", "効果を自動生成", "옵션 자동 생성 완료")
add("拖入装备", "拖入裝備", "Drag gear here", "装備をドラッグ", "장비를 끌어오세요")
add("请先从左侧仓库拖入装备", "請先從左側倉庫拖入裝備", "Drag gear from the vault on the left", "左の倉庫から装備をドラッグ", "왼쪽 창고에서 장비를 끌어오세요")
add("勾选装备预览分解所得", "勾選裝備預覽分解所得", "Select gear to preview salvage rewards", "装備を選択して分解報酬を確認", "장비를 선택하여 분해 보상을 확인하세요")
add("当前分解可获得", "目前分解可獲得", "Salvage rewards", "今回の分解報酬", "현재 분해 보상")
add("精粹 +%s", "精粹 +%s", "Essence +%s", "精粋 +%s", "정수 +%s")
add("%s级及以下", "%s級及以下", "Lv.%s and below", "Lv.%s以下", "Lv.%s 이하")
add("%s品质及以下", "%s品質及以下", "%s rarity and below", "%sレア度以下", "%s 등급 이하")
add("且", "且", " and ", "かつ", " 및 ")
add("未设置条件，掉落装备不会自动分解", "未設定條件，掉落裝備不會自動分解", "No filters set. Drops will not auto-salvage.", "条件未設定。ドロップ装備は自動分解されません", "조건 미설정. 획득 장비는 자동 분해되지 않습니다")
add("的装备会在掉落时自动分解", "的裝備會在掉落時自動分解", " gear auto-salvages on drop", "の装備はドロップ時に自動分解", " 장비는 획득 시 자동 분해됩니다")
add("返还卷轴 %s", "返還卷軸 %s", "Scroll refund: %s", "巻物返還：%s", "두루마리 반환: %s")
add("%s · %s", "%s · %s", "%s · %s", "%s・%s", "%s · %s")
add("%s  %d/6", "%s  %d/6", "%s  %d/6", "%s  %d/6", "%s  %d/6")
add("%d件  ", "%d件  ", "%d pcs  ", "%d点  ", "%d개  ")
add("属性预览暂不可用，当前装备未改变", "屬性預覽暫不可用，目前裝備未改變", "Stat preview unavailable. Gear unchanged.", "能力プレビューを表示できません。装備は未変更", "능력 미리 보기를 표시할 수 없습니다. 장비는 변경되지 않았습니다")
add("该属性为当前角色的最终面板数值。", "該屬性為目前角色的最終面板數值。", "This is the hero's final displayed stat.", "現在のキャラの最終能力値です。", "현재 영웅의 최종 표시 능력치입니다")

return D
