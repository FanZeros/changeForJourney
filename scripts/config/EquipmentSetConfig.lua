-- ============================================================================
-- EquipmentSetConfig - 装备套装静态表（P1：2 件纯属性）
-- 拍板（2026-09-22）：8 套全做、允许跨甲、双手 5 槽可满 6 件、
-- 两套 2 件可同时亮、不要角色专属套。4/6 件战斗被动已落地。
-- 司仪袍 6 件不改死亡（全队护盾+16%）。
-- ============================================================================

local AD = require("systems.AttributeDef")

local ESC = {}

ESC.THRESHOLDS = { 2, 4, 6 }

---@class EquipSetDef
---@field id string
---@field name string
---@field color number[] rgba 0-255
---@field twoHandCountsAsSix boolean|nil 双手无副手时 5 槽即按 6 件
---@field twoPiece { key: string, flat: number, pct: number|nil }[]

---@field effect4 table 四件效果：概率/层数/阈值/冷却保持，强度统一由本表提供
---@field effect6 table 六件效果：运行、描述和预估共用

ESC.SETS = {
    carapace = {
        id = "carapace",
        name = "叠甲虫壳",
        color = { 0xC4, 0x8A, 0x3A, 255 },
        twoHandCountsAsSix = true,
        twoPiece = {
            { key = AD.HP_BONUS, flat = 12 },
            { key = AD.ARMOR_BONUS, flat = 8 },
        },
        effect4 = { maxStacks = 8, damageReductionPerStack = 0.03 },
        effect6 = { damageRatioPerStack = 0.04, tauntDuration = 2 },
        desc2 = "生命+12%，护甲加成+8%。",
    },
    faceless = {
        id = "faceless",
        name = "夜行无面",
        color = { 0x7A, 0x8A, 0xA8, 255 },
        twoPiece = {
            { key = AD.CRIT_RATE, flat = 8 },
            { key = AD.DODGE, flat = 10 },
        },
        effect4 = { hpThreshold = 0.50, damageRatio = 0.50 },
        effect6 = { duration = 8 },
        desc2 = "暴击率+8%，闪避+10。",
    },
    riftcrystal = {
        id = "riftcrystal",
        name = "裂隙水晶",
        color = { 0x7E, 0xC8, 0xE8, 255 },
        twoPiece = {
            { key = AD.DMG_BONUS, flat = 8 },
            { key = AD.ES_BONUS, flat = 16 },
        },
        effect4 = { procChance = 0.15, maxStacks = 5, damageTakenPerStack = 0.03 },
        effect6 = { magRatio = 1.60, progressLoss = 0.60, bossProgressLoss = 0.20 },
        desc2 = "全伤害+8%，能量护盾加成+16%。",
    },
    last_rite = {
        id = "last_rite",
        name = "终焉司仪袍",
        color = { 0xE8, 0xD0, 0x7A, 255 },
        twoPiece = {
            { key = AD.HEAL_BONUS, flat = 16 },
            { key = AD.ES_BONUS, flat = 12 },
        },
        effect4 = { overhealShieldRatio = 0.40 },
        effect6 = { teamShieldBonus = 16 },
        desc2 = "治疗加成+16%，能量护盾加成+12%。",
    },
    tidepress = {
        id = "tidepress",
        name = "高压水脉",
        color = { 0x4A, 0xB0, 0xC8, 255 },
        twoPiece = {
            { key = AD.MAG_PEN, flat = 12 },
            { key = AD.ATK_SPEED, flat = 10 },
        },
        effect4 = { procChance = 0.30, splashRatio = 0.70, splashTargets = 1 },
        effect6 = { progressLoss = 0.40 },
        desc2 = "魔法穿透+12，攻速+10%。",
    },
    nitros = {
        id = "nitros",
        name = "赛道硝烟",
        color = { 0xE0, 0x6A, 0x3A, 255 },
        twoPiece = {
            { key = AD.ATK_SPEED, flat = 16 },
            { key = AD.HIT_VALUE, flat = 12 },
        },
        effect4 = { hitStep = 80, comboPerStep = 4, comboCap = 20 },
        effect6 = { pierceRatio = 1.00, speedBonus = 24, duration = 2 },
        desc2 = "攻速+16%，命中+12。",
    },
    swordgate = {
        id = "swordgate",
        name = "万剑门扉",
        color = { 0xC8, 0xC4, 0xD8, 255 },
        twoHandCountsAsSix = true,
        twoPiece = {
            { key = AD.PHYS_PEN, flat = 16 },
            { key = AD.PHYS_DMG_BONUS, flat = 10 },
        },
        effect4 = { interval = 6, damageRatio = 0.30, swordCount = 1 },
        effect6 = { extraSwords = 1 },
        desc2 = "物理穿透+16，物伤+10%。",
    },
    starless = {
        id = "starless",
        name = "无光星图",
        color = { 0x6A, 0x5A, 0xA0, 255 },
        twoPiece = {
            { key = AD.MAG_DMG_BONUS, flat = 8 },
        },
        effect4 = { magPen = 16 },
        effect6 = { interval = 8, magRatio = 2.40 },
        desc2 = "魔法伤害+8%。",
    },
    ironwall = {
        id = "ironwall",
        name = "帝国铁壁",
        color = { 0xA8, 0xA0, 0x90, 255 },
        twoPiece = {
            { key = AD.PHYS_BLOCK_RATE, flat = 8 },
            { key = AD.HP_BONUS, flat = 8 },
        },
        effect4 = { healMaxHpRatio = 0.02 },
        effect6 = { reflectRatio = 0.60 },
        desc2 = "物理格挡+8%，生命+8%。",
    },
    emberscout = {
        id = "emberscout",
        name = "巡林余烬",
        color = { 0xC8, 0x78, 0x3A, 255 },
        twoPiece = {
            { key = AD.HIT_VALUE, flat = 10 },
            { key = AD.PHYS_PEN, flat = 8 },
        },
        effect4 = { duration = 2, damageTakenRatio = 0.16 },
        effect6 = { spreadTargets = 2 },
        desc2 = "命中+10，物理穿透+8。",
    },
    gambler = {
        id = "gambler",
        name = "赌徒残响",
        color = { 0xC4, 0x4A, 0x6A, 255 },
        twoPiece = {
            { key = AD.LUK, flat = 8 },
            { key = AD.ADVANTAGE_DMG_BONUS, flat = 16 },
        },
        effect4 = { critPerStack = 12, maxStacks = 3 },
        effect6 = { damageRatio = 0.60, healLostHpRatio = 0.02 },
        desc2 = "命数+8，优势伤害+16%。",
    },
    bonehunger = {
        id = "bonehunger",
        name = "衔骨饥渴",
        color = { 0xB0, 0x78, 0x58, 255 },
        twoPiece = {
            { key = AD.ATK_SPEED, flat = 10 },
            { key = AD.ATK_HEAL, flat = 8 },
        },
        effect4 = { hpThreshold = 0.70, speedBonus = 16 },
        effect6 = { healMaxHpRatio = 0.06 },
        desc2 = "攻速+10%，攻击回血+8。",
    },
}

-- 高阶描述直接由效果常量生成，避免文案、实战与静态预估各维护一套数值。
do
    local s = ESC.SETS
    local fmt = string.format
    s.carapace.desc4 = fmt("每次受击获得1层甲片（最多%d）。每层受伤-%g%%。",
        s.carapace.effect4.maxStacks, s.carapace.effect4.damageReductionPerStack * 100)
    s.carapace.desc6 = fmt("甲片满层时，下次攻击消耗全部层数，按层数×%g%%追加伤害并嘲讽%g秒。",
        s.carapace.effect6.damageRatioPerStack * 100, s.carapace.effect6.tauntDuration)
    s.faceless.desc4 = fmt("攻击生命低于%g%%的敌人时，追加%g%%本次伤害。",
        s.faceless.effect4.hpThreshold * 100, s.faceless.effect4.damageRatio * 100)
    s.faceless.desc6 = fmt("敌人死亡后%g秒进入无面：清空仇恨，期间不产生仇恨。", s.faceless.effect6.duration)
    s.riftcrystal.desc4 = fmt("攻击命中%g%%给目标1层晶蚀（最多%d）。每层使目标受到的全伤害+%g%%。",
        s.riftcrystal.effect4.procChance * 100, s.riftcrystal.effect4.maxStacks,
        s.riftcrystal.effect4.damageTakenPerStack * 100)
    s.riftcrystal.desc6 = fmt("晶蚀满%d层碎裂：%g%%魔攻暗影伤害，并打断攻击进度。",
        s.riftcrystal.effect4.maxStacks, s.riftcrystal.effect6.magRatio * 100)
    s.last_rite.desc4 = fmt("过量治疗的%g%%转为能量护盾。", s.last_rite.effect4.overhealShieldRatio * 100)
    s.last_rite.desc6 = fmt("全队能量护盾加成+%g%%（不改写死亡）。", s.last_rite.effect6.teamShieldBonus)
    s.tidepress.desc4 = fmt("攻击主目标时%g%%溅射邻近%d人，伤害%g%%。",
        s.tidepress.effect4.procChance * 100, s.tidepress.effect4.splashTargets,
        s.tidepress.effect4.splashRatio * 100)
    s.tidepress.desc6 = fmt("被溅射目标立即扣除%g%%攻击进度。", s.tidepress.effect6.progressLoss * 100)
    s.nitros.desc4 = fmt("每%g点命中，连击率+%g%%（最多+%g%%）。",
        s.nitros.effect4.hitStep, s.nitros.effect4.comboPerStep, s.nitros.effect4.comboCap)
    s.nitros.desc6 = fmt("连击时贯穿仇恨第二的目标（%g%%伤害）；仅1名敌人时自身攻速+%g%%持续%g秒。",
        s.nitros.effect6.pierceRatio * 100, s.nitros.effect6.speedBonus, s.nitros.effect6.duration)
    s.swordgate.desc4 = fmt("每%g秒召唤%d柄门缝飞剑，伤害=这%g秒自身伤害的%g%%。",
        s.swordgate.effect4.interval, s.swordgate.effect4.swordCount,
        s.swordgate.effect4.interval, s.swordgate.effect4.damageRatio * 100)
    s.swordgate.desc6 = fmt("飞剑+%d柄。穿套本人不额外飞一轮。", s.swordgate.effect6.extraSwords)
    s.starless.desc4 = fmt("魔法穿透+%g。", s.starless.effect4.magPen)
    s.starless.desc6 = fmt("每%g秒对生命百分比最低的敌人打%g%%魔攻，不产生仇恨。",
        s.starless.effect6.interval, s.starless.effect6.magRatio * 100)
    s.ironwall.desc4 = fmt("格挡成功时回复%g%%最大生命。", s.ironwall.effect4.healMaxHpRatio * 100)
    s.ironwall.desc6 = fmt("格挡成功时把挡掉伤害的%g%%反给攻击者（暗影，无仇恨）。",
        s.ironwall.effect6.reflectRatio * 100)
    s.emberscout.desc4 = fmt("攻击施加余烬%g秒：目标受伤+%g%%。",
        s.emberscout.effect4.duration, s.emberscout.effect4.damageTakenRatio * 100)
    s.emberscout.desc6 = fmt("余烬目标死亡时，余烬弹射到另外%d名敌人。", s.emberscout.effect6.spreadTargets)
    s.gambler.desc4 = fmt("未暴击时下次暴击率+%g%%（最多叠%d层，暴击清空）。",
        s.gambler.effect4.critPerStack, s.gambler.effect4.maxStacks)
    s.gambler.desc6 = fmt("暴击时额外一段%g%%伤害；若未暴击则回复%g%%已损失生命。",
        s.gambler.effect6.damageRatio * 100, s.gambler.effect6.healLostHpRatio * 100)
    s.bonehunger.desc4 = fmt("生命低于%g%%时攻速再+%g%%。",
        s.bonehunger.effect4.hpThreshold * 100, s.bonehunger.effect4.speedBonus)
    s.bonehunger.desc6 = fmt("敌人死亡后回复%g%%最大生命。", s.bonehunger.effect6.healMaxHpRatio * 100)
end

-- 名字子串匹配，先写的规则优先。跨甲水晶放最后，避免把「水晶巨剑」抢走叠甲/万剑。
local NAME_RULES = {
    { setId = "carapace", needles = { "叠甲", "龙鳞", "山岳", "战争之", "金鳞" } },
    { setId = "faceless", needles = { "夜行", "无踪", "刺客", "无声影", "影皮" } },
    { setId = "last_rite", needles = { "光明圣", "主教", "微光者", "圣杯", "权杖", "光之权", "光之圣" } },
    { setId = "tidepress", needles = { "大贤者", "奥术师", "咒法师", "法珠", "水晶法珠" } },
    { setId = "nitros", needles = { "勇士", "勇者", "风行者", "神射手", "监视者" } },
    { setId = "swordgate", needles = { "斩铁", "黑铁大剑", "生铁重剑", "练习用大剑", "水晶大剑", "叠甲战神巨剑" } },
    { setId = "starless", needles = { "大法师魔典", "奥术魔典", "秘法魔典", "咒文魔典" } },
    { setId = "ironwall", needles = { "帝国", "圣骑士", "审判官", "元帅", "守卫巨盾", "水晶巨盾" } },
    { setId = "emberscout", needles = { "巡林客", "追猎者", "狩猎弓", "游侠弓", "镶钉皮" } },
    { setId = "gambler", needles = { "赌徒", "碎玉", "珊瑚之戒", "海灵吊饰" } },
    { setId = "bonehunger", needles = { "蛮族", "掠夺者", "伐木斧", "铁手斧" } },
    { setId = "riftcrystal", needles = { "水晶" } },
}

local TYPE_FALLBACK = {
    ["重盾"] = "carapace",
    ["轻盾"] = "faceless",
    ["魔典"] = "starless",
    ["法珠"] = "tidepress",
    ["圣物"] = "last_rite",
}

local ACCESSORY_BY_NAME = {
    ["红宝石戒"] = "carapace",
    ["黄宝石戒"] = "carapace",
    ["海灵之戒"] = "carapace",
    ["月光之戒"] = "faceless",
    ["晶钻之戒"] = "faceless",
    ["翠玉挂坠"] = "faceless",
    ["水晶之戒"] = "riftcrystal",
    ["水晶挂坠"] = "riftcrystal",
    ["水晶耳环"] = "riftcrystal",
    ["珊瑚耳环"] = "last_rite",
    ["海玉耳环"] = "last_rite",
    ["紫宝石戒"] = "last_rite",
    ["蛋白石戒"] = "tidepress",
    ["金光挂坠"] = "tidepress",
    ["羽制耳环"] = "tidepress",
    ["玛瑙挂坠"] = "nitros",
    ["白玉挂坠"] = "nitros",
    ["红玉挂坠"] = "swordgate",
    ["金光之戒"] = "swordgate",
    ["碎玉之环"] = "starless",
    ["紫晶耳环"] = "starless",
    ["蓝玉挂坠"] = "starless",
    ["红宝石耳环"] = "ironwall",
    ["珍珠耳环"] = "ironwall",
    ["琥珀挂坠"] = "gambler",
    ["赌徒之环"] = "gambler",
    ["珊瑚吊饰"] = "bonehunger",
    ["黄玉挂坠"] = "bonehunger",
    ["青玉挂坠"] = "emberscout",
}

--- 模板 → setId（名字规则 + 饰品表 + 副手类型兜底）
---@param tpl table|nil EquipmentConfig.ITEMS 条目
---@return string|nil
function ESC.getSetIdForTemplate(tpl)
    if not tpl then return nil end
    if tpl.setId then return tpl.setId end
    local name = tpl.name or ""
    if tpl.slot == "accessory" then
        local acc = ACCESSORY_BY_NAME[name]
        if acc then return acc end
    end
    for i = 1, #NAME_RULES do
        local rule = NAME_RULES[i]
        for j = 1, #rule.needles do
            if string.find(name, rule.needles[j], 1, true) then
                return rule.setId
            end
        end
    end
    if tpl.slot == "offhand" then
        return TYPE_FALLBACK[tpl.type]
    end
    return nil
end

---@param setId string
---@return table|nil
function ESC.get(setId)
    return ESC.SETS[setId]
end

-- 固定展示顺序（SETS 是 hash 表无序；筛选列表等 UI 按此顺序渲染）。
-- 新增套装时同步追加到本表末尾。
ESC.SET_ORDER = {
    "carapace", "faceless", "riftcrystal", "last_rite",
    "tidepress", "nitros", "swordgate", "starless",
    "ironwall", "emberscout", "gambler", "bonehunger",
}

--- 按固定顺序返回全部套装 id
---@return string[]
function ESC.orderedSetIds()
    return ESC.SET_ORDER
end

return ESC
