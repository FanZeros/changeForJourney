-- ============================================================================
-- AffixConfig - 装备词缀配置表
-- 包含: 5 档品质定义（D/C/B/A/S）、38 条词缀模板
-- 数据来源: 装备词缀配置.txt
-- ============================================================================

local AffixConfig = {}

-- ======================== 词缀品质定义 ========================
-- minMult/maxMult: 对词缀基础数值的乘数区间
-- weight: 随机权重（越大越容易出）
-- tier: 品质序号（用于 maxAffixQuality 比较）

AffixConfig.QUALITY = {
    [1] = { tier = 1, name = "D", color = "b5b5b5", minMult = 1.0, maxMult = 1.2, weight = 100 },
    [2] = { tier = 2, name = "C", color = "a2ff94", minMult = 1.2, maxMult = 1.5, weight = 80 },
    [3] = { tier = 3, name = "B", color = "72f2f5", minMult = 1.5, maxMult = 1.9, weight = 60 },
    [4] = { tier = 4, name = "A", color = "ef79ff", minMult = 1.9, maxMult = 2.4, weight = 40 },
    [5] = { tier = 5, name = "S", color = "ffed00", minMult = 2.4, maxMult = 3.0, weight = 20 },
}

-- ======================== 词缀模板表 ========================
-- key        : 属性 key（对应 AttributeDef）
-- dataType   : "float"=小数 / "int"=整数 / "pct"=百分比
-- baseValue  : 词缀基础数值（乘以品质倍率后得到实际值）
-- weight     : 随机权重（100=均等）
-- name       : 中文名称

AffixConfig.AFFIXES = {
    -- 基础属性（六围）
    { id = 1,  key = "str",           dataType = "float", baseValue = 0.67,  weight = 100, name = "力量" },
    { id = 2,  key = "agi",           dataType = "float", baseValue = 0.67,  weight = 100, name = "敏捷" },
    { id = 3,  key = "int",           dataType = "float", baseValue = 0.67,  weight = 100, name = "智慧" },
    { id = 4,  key = "vit",           dataType = "float", baseValue = 0.67,  weight = 100, name = "体质" },
    { id = 5,  key = "luk",           dataType = "float", baseValue = 0.67,  weight = 100, name = "运气" },
    { id = 6,  key = "spi",           dataType = "float", baseValue = 0.67,  weight = 100, name = "精神" },

    -- 防御属性
    { id = 7,  key = "maxHp",         dataType = "int",   baseValue = 33,    weight = 100, name = "生命值" },
    { id = 8,  key = "armor",         dataType = "float", baseValue = 1.43,  weight = 100, name = "护甲" },
    { id = 9,  key = "energyShield",  dataType = "float", baseValue = 10.00, weight = 100, name = "能量护盾" },
    { id = 10, key = "dodge",         dataType = "float", baseValue = 1.00,  weight = 100, name = "闪避值" },
    { id = 11, key = "hpRegen",       dataType = "float", baseValue = 3.33,  weight = 100, name = "每秒回血" },
    { id = 12, key = "atkHeal",       dataType = "float", baseValue = 2.22,  weight = 100, name = "攻击回血" },
    { id = 13, key = "physBlockRate", dataType = "pct",   baseValue = 2.0,   weight = 100, name = "物理格挡概率" },
    { id = 14, key = "magBlockRate",  dataType = "pct",   baseValue = 2.0,   weight = 100, name = "魔法格挡概率" },
    { id = 15, key = "abnormalRes",   dataType = "pct",   baseValue = 2.0,   weight = 100, name = "异常抗性" },

    -- 攻击属性
    { id = 16, key = "physAtk",       dataType = "float", baseValue = 2.00,  weight = 100, name = "物理攻击力" },
    { id = 17, key = "magAtk",        dataType = "float", baseValue = 2.00,  weight = 100, name = "魔法攻击力" },
    { id = 18, key = "atkSpeed",      dataType = "pct",   baseValue = 2.5,   weight = 100, name = "攻击速度" },
    { id = 19, key = "critRate",      dataType = "pct",   baseValue = 1.0,   weight = 100, name = "暴击率" },
    { id = 20, key = "critDmg",       dataType = "pct",   baseValue = 5.0,   weight = 100, name = "暴击伤害" },
    { id = 21, key = "physCritRate",  dataType = "pct",   baseValue = 1.3,   weight = 100, name = "物理暴击率" },
    { id = 22, key = "physCritDmg",   dataType = "pct",   baseValue = 6.7,   weight = 100, name = "物理暴击伤害" },
    { id = 23, key = "magCritRate",   dataType = "pct",   baseValue = 1.3,   weight = 100, name = "魔法暴击率" },
    { id = 24, key = "magCritDmg",    dataType = "pct",   baseValue = 6.7,   weight = 100, name = "魔法暴击伤害" },
    { id = 25, key = "physPen",       dataType = "float", baseValue = 2.00,  weight = 100, name = "物理穿透" },
    { id = 26, key = "magPen",        dataType = "float", baseValue = 2.00,  weight = 100, name = "魔法穿透" },
    { id = 27, key = "dmgBonus",      dataType = "pct",   baseValue = 2.5,   weight = 100, name = "伤害加成" },
    { id = 28, key = "physDmgBonus",  dataType = "pct",   baseValue = 3.3,   weight = 100, name = "物理伤害加成" },
    { id = 29, key = "magDmgBonus",   dataType = "pct",   baseValue = 3.3,   weight = 100, name = "魔法伤害加成" },
    { id = 30, key = "comboRate",     dataType = "pct",   baseValue = 3.3,   weight = 100, name = "连击概率" },
    { id = 31, key = "comboDmgUp",    dataType = "pct",   baseValue = 1.7,   weight = 100, name = "连击增伤" },
    { id = 32, key = "maxDmgBonus",   dataType = "pct",   baseValue = 8.3,   weight = 100, name = "最大伤害加成" },
    { id = 33, key = "minDmgBonus",   dataType = "pct",   baseValue = 10.0,  weight = 100, name = "最小伤害加成" },
    { id = 34, key = "hitValue",      dataType = "float", baseValue = 1.25,  weight = 100, name = "命中值" },

   -- 治疗属性
   { id = 35, key = "healAmount",    dataType = "float", baseValue = 2.00,  weight = 100, name = "治疗量" },
   { id = 36, key = "healBonus",     dataType = "pct",   baseValue = 4.0,   weight = 100, name = "治疗加成" },
   { id = 37, key = "healCritRate",  dataType = "pct",   baseValue = 1.3,   weight = 100, name = "治疗暴击率" },
   { id = 38, key = "healCritDmg",   dataType = "pct",   baseValue = 6.7,   weight = 100, name = "治疗暴击加成" },

    -- ==== 新增词缀 39-42（百分比加成类）====
    { id = 39, key = "physAtkBonus", dataType = "pct",   baseValue = 1.7,   weight = 100, name = "物理攻击加成" },
    { id = 40, key = "magAtkBonus",  dataType = "pct",   baseValue = 1.7,   weight = 100, name = "魔法攻击加成" },
    { id = 41, key = "hpBonus",      dataType = "pct",   baseValue = 1.7,   weight = 100, name = "生命加成" },
    { id = 42, key = "dodgeBonus",   dataType = "pct",   baseValue = 1.7,   weight = 100, name = "闪避加成" },
    { id = 43, key = "esBonus",      dataType = "pct",   baseValue = 1.7,   weight = 100, name = "能量护盾加成" },
    { id = 44, key = "armorBonus",   dataType = "pct",   baseValue = 1.7,   weight = 100, name = "护甲加成" },
}

-- ======================== 魔化词缀模板表 ========================
-- 腐化石专用：仅在魔化结果「出现魔化词条」时从此池随机，不进入普通装备/普通洗练词缀池
AffixConfig.CORRUPT_AFFIXES = {
    { id = 1001, key = "finalPhysAtkBonus",      dataType = "pct", baseValue = 1.7, weight = 100, name = "最终物攻" },
    { id = 1002, key = "finalMagAtkBonus",       dataType = "pct", baseValue = 1.7, weight = 100, name = "最终魔攻" },
    { id = 1003, key = "finalHpBonus",           dataType = "pct", baseValue = 1.7, weight = 100, name = "最终生命" },
    { id = 1004, key = "finalDamageBonus",       dataType = "pct", baseValue = 1.7, weight = 100, name = "最终伤害" },
    { id = 1005, key = "finalStrBonus",          dataType = "pct", baseValue = 1.7, weight = 100, name = "最终力量" },
    { id = 1006, key = "finalAgiBonus",          dataType = "pct", baseValue = 1.7, weight = 100, name = "最终敏捷" },
    { id = 1007, key = "finalIntBonus",          dataType = "pct", baseValue = 1.7, weight = 100, name = "最终智慧" },
    { id = 1008, key = "finalVitBonus",          dataType = "pct", baseValue = 1.7, weight = 100, name = "最终体质" },
    { id = 1009, key = "finalLukBonus",          dataType = "pct", baseValue = 1.7, weight = 100, name = "最终运气" },
    { id = 1010, key = "finalSpiBonus",          dataType = "pct", baseValue = 1.7, weight = 100, name = "最终精神" },
    { id = 1011, key = "finalArmorBonus",        dataType = "pct", baseValue = 1.7, weight = 100, name = "最终护甲" },
    { id = 1012, key = "finalEnergyShieldBonus", dataType = "pct", baseValue = 1.7, weight = 100, name = "最终能量护盾" },
    { id = 1013, key = "finalDodgeBonus",        dataType = "pct", baseValue = 1.7, weight = 100, name = "最终闪避" },
}

AffixConfig.CORRUPT_TOTAL_WEIGHT = 0
for _, affix in ipairs(AffixConfig.CORRUPT_AFFIXES) do
    AffixConfig.CORRUPT_TOTAL_WEIGHT = AffixConfig.CORRUPT_TOTAL_WEIGHT + affix.weight
end

--- 按 id 查找词缀  BY_ID[affixId] = affix
AffixConfig.BY_ID = {}
for _, affix in ipairs(AffixConfig.AFFIXES) do
    AffixConfig.BY_ID[affix.id] = affix
end
for _, affix in ipairs(AffixConfig.CORRUPT_AFFIXES) do
    AffixConfig.BY_ID[affix.id] = affix
end

--- 按 key 查找词缀  BY_KEY[key] = affix
AffixConfig.BY_KEY = {}
for _, affix in ipairs(AffixConfig.AFFIXES) do
    AffixConfig.BY_KEY[affix.key] = affix
end
for _, affix in ipairs(AffixConfig.CORRUPT_AFFIXES) do
    AffixConfig.BY_KEY[affix.key] = affix
end

--- 魔化词缀 id 集合（不吃 D~S 词缀品质增幅）
AffixConfig.CORRUPT_ID_SET = {}
for _, affix in ipairs(AffixConfig.CORRUPT_AFFIXES) do
    AffixConfig.CORRUPT_ID_SET[affix.id] = true
    AffixConfig.CORRUPT_ID_SET[tostring(affix.id)] = true
end

--- 是否为魔化词条（id 1001+ 或 word 模板）
---@param affixOrId table|number|string|nil
---@return boolean
function AffixConfig.isCorruptAffix(affixOrId)
    if affixOrId == nil then return false end
    local id
    if type(affixOrId) == "table" then
        id = tonumber(affixOrId.affixId) or affixOrId.affixId
        if not id and affixOrId.key then
            for _, tpl in ipairs(AffixConfig.CORRUPT_AFFIXES) do
                if tpl.key == affixOrId.key then
                    return true
                end
            end
            return false
        end
    else
        id = tonumber(affixOrId) or affixOrId
    end
    return id ~= nil and AffixConfig.CORRUPT_ID_SET[id] == true
end

--- 词缀总权重（用于加权随机）
AffixConfig.TOTAL_WEIGHT = 0
for _, affix in ipairs(AffixConfig.AFFIXES) do
    AffixConfig.TOTAL_WEIGHT = AffixConfig.TOTAL_WEIGHT + affix.weight
end

--- 品质总权重
AffixConfig.QUALITY_TOTAL_WEIGHT = 0
for _, q in pairs(AffixConfig.QUALITY) do
    AffixConfig.QUALITY_TOTAL_WEIGHT = AffixConfig.QUALITY_TOTAL_WEIGHT + q.weight
end

return AffixConfig
