-- ============================================================================
-- EquipmentSetConfig - 装备套装静态表（P1：2 件纯属性）
-- 拍板（2026-09-22）：8 套全做、允许跨甲、双手 5 槽可满 6 件、
-- 两套 2 件可同时亮、不要角色专属套。4/6 件战斗被动已落地。
-- 司仪袍 6 件不改死亡（全队护盾+8%）。
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

ESC.SETS = {
    carapace = {
        id = "carapace",
        name = "叠甲虫壳",
        color = { 0xC4, 0x8A, 0x3A, 255 },
        twoHandCountsAsSix = true,
        twoPiece = {
            { key = AD.HP_BONUS, flat = 6 },
            { key = AD.ARMOR_BONUS, flat = 4 },
        },
    },
    faceless = {
        id = "faceless",
        name = "夜行无面",
        color = { 0x7A, 0x8A, 0xA8, 255 },
        twoPiece = {
            { key = AD.CRIT_RATE, flat = 4 },
            { key = AD.DODGE, flat = 5 },
        },
    },
    riftcrystal = {
        id = "riftcrystal",
        name = "裂隙水晶",
        color = { 0x7E, 0xC8, 0xE8, 255 },
        twoPiece = {
            { key = AD.DMG_BONUS, flat = 4 },
            { key = AD.ES_BONUS, flat = 8 },
        },
    },
    last_rite = {
        id = "last_rite",
        name = "终焉司仪袍",
        color = { 0xE8, 0xD0, 0x7A, 255 },
        twoPiece = {
            { key = AD.HEAL_BONUS, flat = 8 },
            { key = AD.ES_BONUS, flat = 6 },
        },
    },
    tidepress = {
        id = "tidepress",
        name = "高压水脉",
        color = { 0x4A, 0xB0, 0xC8, 255 },
        twoPiece = {
            { key = AD.MAG_PEN, flat = 6 },
            { key = AD.ATK_SPEED, flat = 5 },
        },
    },
    nitros = {
        id = "nitros",
        name = "赛道硝烟",
        color = { 0xE0, 0x6A, 0x3A, 255 },
        twoPiece = {
            { key = AD.ATK_SPEED, flat = 8 },
            { key = AD.HIT_VALUE, flat = 6 },
        },
    },
    swordgate = {
        id = "swordgate",
        name = "万剑门扉",
        color = { 0xC8, 0xC4, 0xD8, 255 },
        twoHandCountsAsSix = true,
        twoPiece = {
            { key = AD.PHYS_PEN, flat = 8 },
            { key = AD.PHYS_DMG_BONUS, flat = 5 },
        },
    },
    starless = {
        id = "starless",
        name = "无光星图",
        color = { 0x6A, 0x5A, 0xA0, 255 },
        twoPiece = {
            { key = AD.MAG_DMG_BONUS, flat = 4 },
        },
    },
}

-- 名字子串匹配，先写的规则优先。跨甲水晶放最后，避免把「水晶巨剑」抢走叠甲/万剑。
local NAME_RULES = {
    { setId = "carapace", needles = { "叠甲", "龙鳞", "山岳", "战争之", "金鳞" } },
    { setId = "faceless", needles = { "夜行", "无踪", "刺客", "无声影", "影皮" } },
    { setId = "last_rite", needles = { "光明圣", "主教", "微光者", "圣杯", "权杖", "光之权", "光之圣" } },
    { setId = "tidepress", needles = { "大贤者", "奥术师", "咒法师", "法珠", "水晶法珠" } },
    { setId = "nitros", needles = { "勇士", "勇者", "风行者", "神射手", "监视者" } },
    { setId = "swordgate", needles = { "斩铁", "黑铁大剑", "生铁重剑", "练习用大剑", "水晶大剑", "叠甲战神巨剑" } },
    { setId = "starless", needles = { "大法师魔典", "奥术魔典", "秘法魔典", "咒文魔典" } },
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

return ESC
