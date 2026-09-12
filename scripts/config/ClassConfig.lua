-- ============================================================================
-- ClassConfig - 职业配置数据表
-- 数据来源: docs/配置文件/职业配置.txt
-- 包含: 6个基础职业的仇恨系数、基础属性加成、天赋、可穿戴护甲
-- ============================================================================

local AD = require("systems.AttributeDef")

local CC = {}

-- ======================== 职业 ID 常量 ========================

CC.KNIGHT  = "knight"   -- 骑士
CC.WARRIOR = "warrior"  -- 战士
CC.MAGE    = "mage"     -- 法师
CC.RANGER  = "ranger"   -- 射手/游侠
CC.ASSASSIN = "assassin" -- 刺客
CC.PRIEST  = "priest"   -- 牧师

-- ======================== 职业配置表 ========================
-- baseAttackThreatMin/Max : 攻击获得基础仇恨范围
-- dmgThreatCoeffMin/Max   : 每点伤害仇恨系数范围
-- healThreatBaseMin/Max   : 治疗基础仇恨点范围
-- healThreatCoeffMin/Max  : 每点治疗仇恨系数范围
-- statBonus               : 职业基础属性加成 { [AD.key] = value }
-- talentName              : 天赋名称
-- talentDesc              : 天赋描述
-- armorTypes              : 可穿戴护甲类型列表

CC.CLASSES = {
    [CC.KNIGHT] = {
        name = "骑士",
        -- 仇恨系数（取范围中值）
        baseAttackThreatMin = 60,  baseAttackThreatMax = 100,
        dmgThreatCoeffMin   = 10.0, dmgThreatCoeffMax   = 15.0,
        healThreatBaseMin   = 20,  healThreatBaseMax   = 30,
        healThreatCoeffMin  = 0.8, healThreatCoeffMax  = 1.2,
        -- 职业属性加成
        statBonus = { [AD.VIT] = 5 },
        -- 天赋
        talentName = "阵前叫嚣",
        talentDesc = "每场战斗开始时，第一次攻击获得20倍仇恨值",
        talentId   = "knight_taunt",
        -- 可穿戴护甲
        armorTypes = { AD.ARMOR_PLATE, AD.ARMOR_HEAVY },
    },

    [CC.WARRIOR] = {
        name = "战士",
        baseAttackThreatMin = 10,  baseAttackThreatMax = 20,
        dmgThreatCoeffMin   = 0.5, dmgThreatCoeffMax   = 0.7,
        healThreatBaseMin   = 20,  healThreatBaseMax   = 30,
        healThreatCoeffMin  = 0.8, healThreatCoeffMax  = 1.2,
        statBonus = { [AD.STR] = 5 },
        talentName = "物理精通",
        talentDesc = "物理伤害加成+10%",
        talentId   = "warrior_phys_mastery",
        armorTypes = { AD.ARMOR_HEAVY, AD.ARMOR_HEAVY },
    },

    [CC.MAGE] = {
        name = "法师",
        baseAttackThreatMin = 0,   baseAttackThreatMax = 5,
        dmgThreatCoeffMin   = 0.5, dmgThreatCoeffMax   = 0.7,
        healThreatBaseMin   = 20,  healThreatBaseMax   = 30,
        healThreatCoeffMin  = 0.8, healThreatCoeffMax  = 1.2,
        statBonus = { [AD.INT] = 5 },
        talentName = "魔法精通",
        talentDesc = "魔法伤害加成+10%",
        talentId   = "mage_mag_mastery",
        armorTypes = { AD.ARMOR_CLOTH, AD.ARMOR_LIGHT },
    },

    [CC.RANGER] = {
        name = "射手",
        baseAttackThreatMin = 1,   baseAttackThreatMax = 2,
        dmgThreatCoeffMin   = 0.8, dmgThreatCoeffMax   = 1.0,
        healThreatBaseMin   = 20,  healThreatBaseMax   = 30,
        healThreatCoeffMin  = 0.8, healThreatCoeffMax  = 1.2,
        statBonus = { [AD.AGI] = 5 },
        talentName = "远程攻击",
        talentDesc = "在有骑士/战士存在时，仇恨获得倍率降低80%",
        talentId   = "ranger_ranged_attack",
        armorTypes = { AD.ARMOR_LIGHT, AD.ARMOR_LEATHER },
    },

    [CC.ASSASSIN] = {
        name = "刺客",
        baseAttackThreatMin = 0,   baseAttackThreatMax = 0,
        dmgThreatCoeffMin   = 0.3, dmgThreatCoeffMax   = 0.5,
        healThreatBaseMin   = 20,  healThreatBaseMax   = 30,
        healThreatCoeffMin  = 0.8, healThreatCoeffMax  = 1.2,
        statBonus = { [AD.LUK] = 5 },
        talentName = "精准",
        talentDesc = "通用暴击率+5%",
        talentId   = "assassin_precision",
        armorTypes = { AD.ARMOR_LEATHER, AD.ARMOR_LEATHER },
    },

    [CC.PRIEST] = {
        name = "牧师",
        baseAttackThreatMin = 0,   baseAttackThreatMax = 5,
        dmgThreatCoeffMin   = 0.5, dmgThreatCoeffMax   = 0.7,
        healThreatBaseMin   = 20,  healThreatBaseMax   = 30,
        healThreatCoeffMin  = 0.8, healThreatCoeffMax  = 1.2,
        statBonus = { [AD.SPI] = 5 },
        talentName = "疗愈",
        talentDesc = "治疗加成+10%",
        talentId   = "priest_heal_mastery",
        armorTypes = { AD.ARMOR_CLOTH, AD.ARMOR_LEATHER },
    },
}

-- ======================== 中文名 → classId 映射 ========================

CC.NAME_TO_ID = {}
for id, cls in pairs(CC.CLASSES) do
    CC.NAME_TO_ID[cls.name] = id
end
-- 额外别名
CC.NAME_TO_ID["射手"] = CC.RANGER

-- ======================== 辅助方法 ========================

--- 获取职业配置
---@param classId string 职业 ID（CC.KNIGHT 等）
---@return table|nil
function CC.get(classId)
    return CC.CLASSES[classId]
end

--- 通过中文名获取职业 ID
---@param name string 中文职业名（骑士/战士/法师/游侠/射手/刺客/牧师）
---@return string|nil classId
function CC.getIdByName(name)
    return CC.NAME_TO_ID[name]
end

--- 获取职业的攻击基础仇恨（取范围中值）
---@param classId string
---@return number
function CC.getBaseAttackThreat(classId)
    local cls = CC.CLASSES[classId]
    if not cls then return 5 end
    return (cls.baseAttackThreatMin + cls.baseAttackThreatMax) * 0.5
end

--- 获取职业的伤害仇恨系数（取范围中值）
---@param classId string
---@return number
function CC.getDmgThreatCoeff(classId)
    local cls = CC.CLASSES[classId]
    if not cls then return 1.0 end
    return (cls.dmgThreatCoeffMin + cls.dmgThreatCoeffMax) * 0.5
end

--- 获取职业的治疗基础仇恨（取范围中值）
---@param classId string
---@return number
function CC.getHealThreatBase(classId)
    local cls = CC.CLASSES[classId]
    if not cls then return 25 end
    return (cls.healThreatBaseMin + cls.healThreatBaseMax) * 0.5
end

--- 获取职业的治疗仇恨系数（取范围中值）
---@param classId string
---@return number
function CC.getHealThreatCoeff(classId)
    local cls = CC.CLASSES[classId]
    if not cls then return 1.0 end
    return (cls.healThreatCoeffMin + cls.healThreatCoeffMax) * 0.5
end

--- 应用职业天赋到 UnitAttributes（通过 modifier 系统）
---@param classId string
---@param attrs table UnitAttributes 实例
function CC.applyTalent(classId, attrs)
    local cls = CC.CLASSES[classId]
    if not cls then return end

    local entries = {}

    if classId == CC.WARRIOR then
        -- 物理伤害加成+10%
        entries[#entries + 1] = { key = AD.PHYS_DMG_BONUS, pct = 10 }
    elseif classId == CC.MAGE then
        -- 魔法伤害加成+10%
        entries[#entries + 1] = { key = AD.MAG_DMG_BONUS, pct = 10 }
    elseif classId == CC.RANGER then
        -- 攻击速度+10%
        entries[#entries + 1] = { key = AD.ATK_SPEED, flat = 10 }
    elseif classId == CC.ASSASSIN then
        -- 通用暴击率+5%
        entries[#entries + 1] = { key = AD.CRIT_RATE, flat = 5 }
    elseif classId == CC.PRIEST then
        -- 治疗加成+10%
        entries[#entries + 1] = { key = AD.HEAL_BONUS, flat = 10 }
    elseif classId == CC.KNIGHT then
        -- 骑士天赋"阵前叫嚣"不是属性加成，而是战斗开始时仇恨效果
        -- 由 ThreatManager 在战斗开始时处理
    end

    if #entries > 0 then
        attrs:addModifier("talent_" .. classId, entries)
    end
end

--- 应用职业基础属性加成到 UnitAttributes
---@param classId string
---@param attrs table UnitAttributes 实例
function CC.applyStatBonus(classId, attrs)
    local cls = CC.CLASSES[classId]
    if not cls or not cls.statBonus then return end

    local entries = {}
    for key, val in pairs(cls.statBonus) do
        entries[#entries + 1] = { key = key, flat = val }
    end

    if #entries > 0 then
        attrs:addModifier("class_bonus_" .. classId, entries)
    end
end

return CC
