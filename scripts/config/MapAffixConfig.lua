-- ============================================================================
-- MapAffixConfig.lua — 地图词缀配置（双端共享）
-- 折磨II 起每个大章节（地图区域）累加词缀，增加战斗难度
-- ============================================================================

local MapAffixConfig = {}

--- 治疗荒漠：己方治疗加成最多削减 90%（至少保留 10% 治疗）
MapAffixConfig.HEAL_REDUCE_MAX = 0.90

---@param value number|nil
---@return number
function MapAffixConfig.clampHealReduce(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    return math.min(value, MapAffixConfig.HEAL_REDUCE_MAX)
end

MapAffixConfig.ANNIHILATION4_AFFIX_OVERRIDES = {
    energy_barrier = { shieldPct = 0.20 },
    berserk_low_hp = { threshold = 0.38, atkSpeedBonus = 0.65, dmgBonus = 0.32 },
    iron_wall = { armorAdd = 280 },
    ancient_fog = { interval = 11, hitReduce = 130, duration = 10 },
    time_rift = { interval = 11, atkSpeedReduce = 0.32, duration = 10 },
    block_suppress = { blockReduce = 0.48 },
    corrode_armor = { perHitPct = 0.13, maxPct = 0.72, layerDuration = 5 },
    thick_scales = { chance = 0.32 },
    haste_realm = { atkReduce = 0.32, atkSpeedBonus = 1.25 },
    decay_land = { perTick = 0.07, maxBonus = 0.62, tickInterval = 10 },
    life_hunter = { hpDmgBonus = 0.20 },
    heal_desert = { healReduce = 0.58 },
    tenacious_will = { abnormalResAdd = 55 },
    frost_lotus = { interval = 5, freezeDuration = 3.2 },
}

MapAffixConfig.ANNIHILATION5_AFFIX_OVERRIDES = {
    energy_barrier = { shieldPct = 0.22 },
    berserk_low_hp = { threshold = 0.36, atkSpeedBonus = 0.70, dmgBonus = 0.35 },
    iron_wall = { armorAdd = 310 },
    ancient_fog = { interval = 10, hitReduce = 140, duration = 11 },
    time_rift = { interval = 10, atkSpeedReduce = 0.35, duration = 11 },
    block_suppress = { blockReduce = 0.50 },
    corrode_armor = { perHitPct = 0.14, maxPct = 0.75, layerDuration = 5 },
    thick_scales = { chance = 0.35 },
    haste_realm = { atkReduce = 0.35, atkSpeedBonus = 1.30 },
    decay_land = { perTick = 0.08, maxBonus = 0.65, tickInterval = 9 },
    life_hunter = { hpDmgBonus = 0.22 },
    heal_desert = { healReduce = 0.60 },
    tenacious_will = { abnormalResAdd = 60 },
    frost_lotus = { interval = 5, freezeDuration = 3.5 },
}

MapAffixConfig.ANNIHILATION3_AFFIX_OVERRIDES = {
    energy_barrier = { shieldPct = 0.18 },
    berserk_low_hp = { threshold = 0.40, atkSpeedBonus = 0.60, dmgBonus = 0.30 },
    iron_wall = { armorAdd = 250 },
    ancient_fog = { interval = 12, hitReduce = 120, duration = 10 },
    time_rift = { interval = 12, atkSpeedReduce = 0.30, duration = 10 },
    block_suppress = { blockReduce = 0.45 },
    corrode_armor = { perHitPct = 0.12, maxPct = 0.70, layerDuration = 5 },
    thick_scales = { chance = 0.30 },
    haste_realm = { atkReduce = 0.30, atkSpeedBonus = 1.20 },
    decay_land = { perTick = 0.06, maxBonus = 0.60, tickInterval = 10 },
    life_hunter = { hpDmgBonus = 0.18 },
    heal_desert = { healReduce = 0.55 },
    tenacious_will = { abnormalResAdd = 50 },
    frost_lotus = { interval = 6, freezeDuration = 3.0 },
}

local function pct(value)
    return math.floor((tonumber(value) or 0) * 100 + 0.5)
end

function MapAffixConfig.formatAffixText(id, params, def)
    local p = params or {}
    if id == "energy_barrier" then
        return "怪物获得" .. pct(p.shieldPct) .. "%最大生命的护盾",
            "所有怪物获得最大生命值×" .. pct(p.shieldPct) .. "%的能量护盾"
    elseif id == "berserk_low_hp" then
        return "怪物低于" .. pct(p.threshold) .. "%血时暴走",
            "怪物生命低于" .. pct(p.threshold) .. "%时，攻击速度+" .. pct(p.atkSpeedBonus) .. "%，伤害+" .. pct(p.dmgBonus) .. "%"
    elseif id == "iron_wall" then
        return "怪物护甲+" .. tostring(math.floor((p.armorAdd or 0) + 0.5)),
            "所有怪物护甲+" .. tostring(math.floor((p.armorAdd or 0) + 0.5))
    elseif id == "vengeance_oath" then
        return def.shortDesc, def.desc
    elseif id == "ancient_fog" then
        return "每" .. tostring(p.interval) .. "秒降低己方" .. tostring(p.hitReduce) .. "命中" .. tostring(p.duration) .. "秒",
            "每隔" .. tostring(p.interval) .. "秒，己方全体命中值-" .. tostring(p.hitReduce) .. "，持续" .. tostring(p.duration) .. "秒"
    elseif id == "time_rift" then
        return "每" .. tostring(p.interval) .. "秒降低己方" .. pct(p.atkSpeedReduce) .. "%攻速" .. tostring(p.duration) .. "秒",
            "每隔" .. tostring(p.interval) .. "秒，己方全体攻击速度-" .. pct(p.atkSpeedReduce) .. "% ，持续" .. tostring(p.duration) .. "秒"
    elseif id == "block_suppress" then
        return "己方格挡率-" .. pct(p.blockReduce) .. "%",
            "己方角色物理/魔法格挡率-" .. pct(p.blockReduce) .. "%（超出100%的部分可抵消此效果）"
    elseif id == "corrode_armor" then
        return "命中护甲-" .. pct(p.perHitPct) .. "%最多" .. pct(p.maxPct) .. "%",
            "怪物攻击命中时使目标护甲降低" .. pct(p.perHitPct) .. "% ，最多" .. pct(p.maxPct) .. "% ，每层持续" .. tostring(p.layerDuration) .. "秒"
    elseif id == "thick_scales" then
        return "怪物" .. pct(p.chance) .. "%概率免疫暴击",
            "怪物有" .. pct(p.chance) .. "%概率使受到的暴击判定为普通伤害"
    elseif id == "haste_realm" then
        return "怪物攻速+" .. pct(p.atkSpeedBonus) .. "%且攻击力-" .. pct(p.atkReduce) .. "%",
            "所有怪物攻击力-" .. pct(p.atkReduce) .. "% ，攻击速度+" .. pct(p.atkSpeedBonus) .. "%"
    elseif id == "decay_land" then
        return "每" .. tostring(p.tickInterval) .. "秒怪物伤害+" .. pct(p.perTick) .. "%上限" .. pct(p.maxBonus) .. "%",
            "战斗每持续" .. tostring(p.tickInterval) .. "秒，怪物伤害+" .. pct(p.perTick) .. "%（上限+" .. pct(p.maxBonus) .. "%）"
    elseif id == "life_hunter" then
        return "怪物对生命值增伤" .. pct(p.hpDmgBonus) .. "%",
            "怪物对生命值（非护盾）造成的伤害+" .. pct(p.hpDmgBonus) .. "%"
    elseif id == "heal_desert" then
        return "己方治疗效果-" .. pct(p.healReduce) .. "%",
            "己方治疗单位的治疗加成-" .. pct(p.healReduce) .. "%"
    elseif id == "tenacious_will" then
        return "怪物异常抗性+" .. tostring(math.floor((p.abnormalResAdd or 0) + 0.5)) .. "%",
            "所有怪物异常抗性+" .. tostring(math.floor((p.abnormalResAdd or 0) + 0.5)) .. "%"
    elseif id == "frost_lotus" then
        return "每" .. tostring(p.interval) .. "秒冰冻一个己方角色" .. tostring(p.freezeDuration) .. "秒",
            "每隔" .. tostring(p.interval) .. "秒，随机冰冻一个己方角色" .. tostring(p.freezeDuration) .. "秒"
    end
    return def.shortDesc or def.name, def.desc
end

--- 词缀定义
--- type: 词缀类型标识（系统用）
--- name: 显示名称
--- desc: 效果描述（UI 展示用）
--- params: 数值参数表
MapAffixConfig.AFFIXES = {
    -- 1. 能量壁障：怪物获得基于最大HP的能量护盾
    energy_barrier = {
        name = "能量壁障",
        shortDesc = "怪物获得12%最大生命的护盾",
        desc = "所有怪物获得最大生命值×%d%%的能量护盾",
        params = { shieldPct = 0.12 },
    },
    -- 2. 濒死狂怒：低血暴走
    berserk_low_hp = {
        name = "濒死狂怒",
        shortDesc = "怪物低于30%血时暴走",
        desc = "怪物生命低于30%%时，攻击速度+%d%%，伤害+%d%%",
        params = { threshold = 0.30, atkSpeedBonus = 0.40, dmgBonus = 0.20 },
    },
    -- 3. 铁壁强化：护甲增加
    iron_wall = {
        name = "铁壁强化",
        shortDesc = "怪物护甲+150",
        desc = "所有怪物护甲+%d",
        params = { armorAdd = 150 },
    },
    -- 4. 复仇之誓：击杀触发额外攻击
    vengeance_oath = {
        name = "复仇之誓",
        shortDesc = "击杀怪物时剩余怪物反击",
        desc = "每当有怪物被击杀，剩余怪物立即进行一次额外攻击",
        params = {},
    },
    -- 5. 远古之雾：周期性降低命中
    ancient_fog = {
        name = "远古之雾",
        shortDesc = "周期性降低己方命中",
        desc = "每隔%d秒，己方全体命中值-%d，持续%d秒",
        params = { interval = 15, hitReduce = 80, duration = 8 },
    },
    -- 6. 时空裂隙：周期性降低攻速
    time_rift = {
        name = "时空裂隙",
        shortDesc = "周期性降低己方攻速",
        desc = "每隔%d秒，己方全体攻击速度-%d%%，持续%d秒",
        params = { interval = 15, atkSpeedReduce = 0.20, duration = 8 },
    },
    -- 7. 格挡压制：格挡率降低（从未截断值扣减，超 100% 部分可抵消）
    block_suppress = {
        name = "格挡压制",
        shortDesc = "己方格挡率-30%",
        desc = "己方角色物理/魔法格挡率-%d%%（超出100%%的部分可抵消此效果）",
        params = { blockReduce = 0.30 },
    },
    -- 8. 蚀甲之触：攻击削弱护甲
    corrode_armor = {
        name = "蚀甲之触",
        shortDesc = "怪物攻击削弱你的护甲",
        desc = "怪物攻击命中时使目标护甲降低%d%%，最多%d%%，每层持续%d秒",
        params = { perHitPct = 0.08, maxPct = 0.50, layerDuration = 4 },
    },
    -- 9. 厚重鳞甲：概率免疫暴击
    thick_scales = {
        name = "厚重鳞甲",
        shortDesc = "怪物20%概率免疫暴击",
        desc = "怪物有%d%%概率使受到的暴击判定为普通伤害",
        params = { chance = 0.20 },
    },
    -- 10. 加速时空：攻击力降低但攻速大增
    haste_realm = {
        name = "加速时空",
        shortDesc = "怪物攻速翻倍但攻击力降低",
        desc = "所有怪物攻击力-%d%%，攻击速度+%d%%",
        params = { atkReduce = 0.40, atkSpeedBonus = 0.80 },
    },
    -- 11. 衰败之地：战斗时间越久伤害越高
    decay_land = {
        name = "衰败之地",
        shortDesc = "战斗越久怪物伤害越高",
        desc = "战斗每持续10秒，怪物伤害+%d%%（上限+%d%%）",
        params = { perTick = 0.04, maxBonus = 0.40, tickInterval = 10 },
    },
    -- 12. 生命猎手：对HP部分增伤
    life_hunter = {
        name = "生命猎手",
        shortDesc = "怪物对生命值增伤12%",
        desc = "怪物对生命值（非护盾）造成的伤害+%d%%",
        params = { hpDmgBonus = 0.12 },
    },
    -- 13. 治疗荒漠：削弱治疗
    heal_desert = {
        name = "治疗荒漠",
        shortDesc = "己方治疗效果-40%",
        desc = "己方治疗单位的治疗加成-%d%%",
        params = { healReduce = 0.40 },
    },
    -- 14. 坚韧意志：怪物异常抗性增加
    tenacious_will = {
        name = "坚韧意志",
        shortDesc = "怪物异常抗性+30%",
        desc = "所有怪物异常抗性+%d%%",
        params = { abnormalResAdd = 30 },
    },
    -- 15. 冰冻之莲：周期性冰冻一个己方角色
    frost_lotus = {
        name = "冰冻之莲",
        shortDesc = "每7秒冰冻一个己方角色2秒",
        desc = "每隔%d秒，随机冰冻一个己方角色%d秒",
        params = { interval = 7, freezeDuration = 2.0 },
    },
}

--- 章节词缀分配规则：
--- 折磨II（chapter 139~161，共23章）：每章仅1个词缀，同章内所有关卡相同
--- 折磨III（chapter 162~184，共23章）：每章2个词缀（本章新词缀 + 继承一个旧词缀）
---
--- 折磨II 每章1个词缀（23章循环13种词缀）：
MapAffixConfig.TORMENT2_AFFIXES_BY_CHAPTER = {
    [139] = { "energy_barrier" },       -- 森林小径: 能量壁障
    [140] = { "berserk_low_hp" },       -- 幽光林地: 濒死狂怒
    [141] = { "iron_wall" },            -- 迷雾沼泽: 铁壁强化
    [142] = { "vengeance_oath" },       -- 巨木之根: 复仇之誓
    [143] = { "ancient_fog" },          -- 狂风沙丘: 远古之雾
    [144] = { "time_rift" },            -- 蚀骨荒漠: 时空裂隙
    [145] = { "decay_land" },           -- 焦土平原: 衰败之地
    [146] = { "corrode_armor" },        -- 碎石裂谷: 蚀甲之触
    [147] = { "thick_scales" },         -- 回声山洞: 厚重鳞甲
    [148] = { "haste_realm" },          -- 永恒瀑布: 加速时空
    [149] = { "life_hunter" },          -- 凛冽雪山: 生命猎手
    [150] = { "heal_desert" },          -- 失落冰原: 治疗荒漠
    [151] = { "block_suppress" },       -- 霜寂冻土: 格挡压制
    [152] = { "tenacious_will" },     -- 坚韧意志
    [153] = { "frost_lotus" },        -- 冰冻之莲
    -- 第16章起循环复用
    [154] = { "energy_barrier" },
    [155] = { "berserk_low_hp" },
    [156] = { "iron_wall" },
    [157] = { "vengeance_oath" },
    [158] = { "ancient_fog" },
    [159] = { "time_rift" },
    [160] = { "decay_land" },
    [161] = { "corrode_armor" },
}

--- 折磨III 每章2个词缀（新词缀 + 一个搭配词缀）
MapAffixConfig.TORMENT3_AFFIXES_BY_CHAPTER = {
    [162] = { "energy_barrier", "decay_land" },
    [163] = { "berserk_low_hp", "life_hunter" },
    [164] = { "iron_wall", "corrode_armor" },
    [165] = { "vengeance_oath", "haste_realm" },
    [166] = { "ancient_fog", "heal_desert" },
    [167] = { "time_rift", "thick_scales" },
    [168] = { "decay_land", "berserk_low_hp" },
    [169] = { "corrode_armor", "block_suppress" },
    [170] = { "thick_scales", "energy_barrier" },
    [171] = { "haste_realm", "iron_wall" },
    [172] = { "life_hunter", "vengeance_oath" },
    [173] = { "heal_desert", "ancient_fog" },
    [174] = { "block_suppress", "time_rift" },
    [175] = { "energy_barrier", "life_hunter" },
    [176] = { "berserk_low_hp", "corrode_armor" },
    [177] = { "iron_wall", "heal_desert" },
    [178] = { "vengeance_oath", "decay_land" },
    [179] = { "ancient_fog", "thick_scales" },
    [180] = { "time_rift", "block_suppress" },
    [181] = { "decay_land", "haste_realm" },
    [182] = { "tenacious_will", "corrode_armor" },
    [183] = { "frost_lotus", "life_hunter" },
    [184] = { "heal_desert", "frost_lotus" },
}

--- 折磨IV 每章3个词缀
MapAffixConfig.TORMENT4_AFFIXES_BY_CHAPTER = {
    [185] = { "energy_barrier", "berserk_low_hp", "iron_wall" },
    [186] = { "berserk_low_hp", "iron_wall", "vengeance_oath" },
    [187] = { "iron_wall", "vengeance_oath", "ancient_fog" },
    [188] = { "vengeance_oath", "ancient_fog", "time_rift" },
    [189] = { "ancient_fog", "time_rift", "block_suppress" },
    [190] = { "time_rift", "block_suppress", "corrode_armor" },
    [191] = { "block_suppress", "corrode_armor", "thick_scales" },
    [192] = { "corrode_armor", "thick_scales", "haste_realm" },
    [193] = { "thick_scales", "haste_realm", "decay_land" },
    [194] = { "haste_realm", "decay_land", "life_hunter" },
    [195] = { "decay_land", "life_hunter", "heal_desert" },
    [196] = { "life_hunter", "heal_desert", "tenacious_will" },
    [197] = { "heal_desert", "tenacious_will", "frost_lotus" },
    [198] = { "tenacious_will", "frost_lotus", "energy_barrier" },
    [199] = { "frost_lotus", "energy_barrier", "berserk_low_hp" },
    [200] = { "energy_barrier", "berserk_low_hp", "iron_wall" },
    [201] = { "berserk_low_hp", "iron_wall", "vengeance_oath" },
    [202] = { "iron_wall", "vengeance_oath", "ancient_fog" },
    [203] = { "vengeance_oath", "ancient_fog", "time_rift" },
    [204] = { "ancient_fog", "time_rift", "block_suppress" },
    [205] = { "time_rift", "block_suppress", "corrode_armor" },
    [206] = { "block_suppress", "corrode_armor", "thick_scales" },
    [207] = { "corrode_armor", "thick_scales", "haste_realm" },
}

--- 折磨V 每章4个词缀
MapAffixConfig.TORMENT5_AFFIXES_BY_CHAPTER = {
    [208] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath" },
    [209] = { "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [210] = { "iron_wall", "vengeance_oath", "ancient_fog", "time_rift" },
    [211] = { "vengeance_oath", "ancient_fog", "time_rift", "block_suppress" },
    [212] = { "ancient_fog", "time_rift", "block_suppress", "corrode_armor" },
    [213] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales" },
    [214] = { "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [215] = { "corrode_armor", "thick_scales", "haste_realm", "decay_land" },
    [216] = { "thick_scales", "haste_realm", "decay_land", "life_hunter" },
    [217] = { "haste_realm", "decay_land", "life_hunter", "heal_desert" },
    [218] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will" },
    [219] = { "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [220] = { "heal_desert", "tenacious_will", "frost_lotus", "energy_barrier" },
    [221] = { "tenacious_will", "frost_lotus", "energy_barrier", "berserk_low_hp" },
    [222] = { "frost_lotus", "energy_barrier", "berserk_low_hp", "iron_wall" },
    [223] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath" },
    [224] = { "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [225] = { "iron_wall", "vengeance_oath", "ancient_fog", "time_rift" },
    [226] = { "vengeance_oath", "ancient_fog", "time_rift", "block_suppress" },
    [227] = { "ancient_fog", "time_rift", "block_suppress", "corrode_armor" },
    [228] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales" },
    [229] = { "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [230] = { "corrode_armor", "thick_scales", "haste_realm", "decay_land" },
}

--- 湮灭 每章5个词缀

MapAffixConfig.ANNIHILATION_AFFIXES_BY_CHAPTER = {
    [231] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [232] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [233] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [234] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [235] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [236] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [237] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [238] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [239] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [240] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [241] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [242] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [243] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [244] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [245] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [246] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [247] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [248] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [249] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [250] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [251] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [252] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [253] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
}

--- 湮灭II 每章5个词缀

MapAffixConfig.ANNIHILATION2_AFFIXES_BY_CHAPTER = {
    [254] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [255] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [256] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [257] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [258] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [259] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [260] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [261] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [262] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [263] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [264] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [265] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [266] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [267] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [268] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [269] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [270] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [271] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [272] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [273] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [274] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [275] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [276] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
}

--- 湮灭III 每章5个词缀

MapAffixConfig.ANNIHILATION3_AFFIXES_BY_CHAPTER = {
    [277] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [278] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [279] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [280] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [281] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [282] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [283] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [284] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [285] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [286] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [287] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [288] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [289] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [290] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [291] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [292] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [293] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [294] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [295] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [296] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [297] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [298] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [299] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
}


MapAffixConfig.ANNIHILATION4_AFFIXES_BY_CHAPTER = {
    [300] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [301] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [302] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [303] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [304] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [305] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [306] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [307] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [308] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [309] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [310] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [311] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [312] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [313] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [314] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [315] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [316] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [317] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [318] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [319] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [320] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [321] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [322] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
}

MapAffixConfig.ANNIHILATION5_AFFIXES_BY_CHAPTER = {
    [323] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [324] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [325] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [326] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [327] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [328] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [329] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [330] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [331] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [332] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [333] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [334] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [335] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [336] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [337] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [338] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [339] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [340] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [341] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [342] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
    [343] = { "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus" },
    [344] = { "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog" },
    [345] = { "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm" },
}

-- S1 按地图难度启用词缀：普通1、困难2、噩梦3、地狱4、炼狱5。
MapAffixConfig.CHALLENGER_S1_AFFIXES_BY_CHAPTER = {}
MapAffixConfig.CHALLENGER_S1_AFFIX_SNAPSHOT_VERSION = "challenger_2026s1_v1"
MapAffixConfig.CHALLENGER_S1_AFFIX_SNAPSHOT_HASH = 627147698

local s1AffixPool = {
    "energy_barrier", "berserk_low_hp", "iron_wall", "vengeance_oath", "ancient_fog",
    "time_rift", "block_suppress", "corrode_armor", "thick_scales", "haste_realm",
    "decay_land", "life_hunter", "heal_desert", "tenacious_will", "frost_lotus",
}
for chapter = 1, 115 do
    local difficultyIndex = math.floor((chapter - 1) / 23) + 1
    local count = math.min(difficultyIndex, #s1AffixPool)
    local list = {}
    local offset = (chapter - 1) % #s1AffixPool
    for i = 1, count do
        list[i] = s1AffixPool[((offset + i - 1) % #s1AffixPool) + 1]
    end
    MapAffixConfig.CHALLENGER_S1_AFFIXES_BY_CHAPTER[chapter] = list
end

local function validateChallengerS1AffixSnapshot()
    local hash = 5381
    local function hashText(text)
        for i = 1, #text do
            hash = (hash * 33 + string.byte(text, i)) % 2147483647
        end
    end

    for chapter = 1, 115 do
        local ids = MapAffixConfig.CHALLENGER_S1_AFFIXES_BY_CHAPTER[chapter]
        local expectedCount = math.floor((chapter - 1) / 23) + 1
        assert(type(ids) == "table", "S1词缀缺少章节 " .. tostring(chapter))
        assert(#ids == expectedCount,
            "S1词缀数量错误 chapter=" .. tostring(chapter)
                .. " expected=" .. tostring(expectedCount)
                .. " actual=" .. tostring(#ids))

        local seen = {}
        for _, id in ipairs(ids) do
            assert(MapAffixConfig.AFFIXES[id],
                "S1词缀定义不存在 chapter=" .. tostring(chapter) .. " id=" .. tostring(id))
            assert(not seen[id],
                "S1同章词缀重复 chapter=" .. tostring(chapter) .. " id=" .. tostring(id))
            seen[id] = true
        end
        hashText(tostring(chapter) .. "=" .. table.concat(ids, ",") .. ";")
    end

    assert(hash == MapAffixConfig.CHALLENGER_S1_AFFIX_SNAPSHOT_HASH,
        "S1词缀快照发生未版本化变更 version="
            .. MapAffixConfig.CHALLENGER_S1_AFFIX_SNAPSHOT_VERSION
            .. " expected=" .. tostring(MapAffixConfig.CHALLENGER_S1_AFFIX_SNAPSHOT_HASH)
            .. " actual=" .. tostring(hash))
end

validateChallengerS1AffixSnapshot()

function MapAffixConfig.getAffixesForChallengerS1(chapter)
    local affixIds = MapAffixConfig.CHALLENGER_S1_AFFIXES_BY_CHAPTER[tonumber(chapter)]
    if not affixIds then return nil end

    local result = {}
    for _, id in ipairs(affixIds) do
        local def = MapAffixConfig.AFFIXES[id]
        if def then
            local params = {}
            for key, value in pairs(def.params) do
                params[key] = value
            end
            result[#result + 1] = {
                id = id,
                name = def.name,
                desc = def.desc,
                shortDesc = def.shortDesc or def.name,
                params = params,
            }
        end
    end
    return #result > 0 and result or nil
end

--- 根据 chapter 获取当前生效的普通地图词缀列表。
---@param chapter number
---@return table[]|nil
function MapAffixConfig.getAffixesForChapter(chapter)
    local StageConfig = require("config.StageConfig")
    local scale = 1.0
    local affixIds
    local affixOverrides

    -- 折磨II: chapter 139~161
    if chapter >= StageConfig.TORMENT2_CHAPTERS.first and chapter <= StageConfig.TORMENT2_CHAPTERS.last then
        affixIds = MapAffixConfig.TORMENT2_AFFIXES_BY_CHAPTER[chapter]
        scale = 1.0
    -- 折磨III: chapter 162~184
    elseif chapter >= StageConfig.TORMENT3_CHAPTERS.first and chapter <= StageConfig.TORMENT3_CHAPTERS.last then
        affixIds = MapAffixConfig.TORMENT3_AFFIXES_BY_CHAPTER[chapter]
        scale = 1.0
    -- 折磨IV: chapter 185~207
    elseif chapter >= StageConfig.TORMENT4_CHAPTERS.first and chapter <= StageConfig.TORMENT4_CHAPTERS.last then
        affixIds = MapAffixConfig.TORMENT4_AFFIXES_BY_CHAPTER[chapter]
        scale = 1.0
    -- 折磨V: chapter 208~230
    elseif chapter >= StageConfig.TORMENT5_CHAPTERS.first and chapter <= StageConfig.TORMENT5_CHAPTERS.last then
        affixIds = MapAffixConfig.TORMENT5_AFFIXES_BY_CHAPTER[chapter]
        scale = 1.0
    -- 湮灭: chapter 231~253
    elseif chapter >= StageConfig.ANNIHILATION_CHAPTERS.first and chapter <= StageConfig.ANNIHILATION_CHAPTERS.last then
        affixIds = MapAffixConfig.ANNIHILATION_AFFIXES_BY_CHAPTER[chapter]
        scale = 1.0
    -- 湮灭II: chapter 254~276
    elseif chapter >= StageConfig.ANNIHILATION2_CHAPTERS.first and chapter <= StageConfig.ANNIHILATION2_CHAPTERS.last then
        affixIds = MapAffixConfig.ANNIHILATION2_AFFIXES_BY_CHAPTER[chapter]
        scale = 1.0
    -- 湮灭V: chapter 323~345
    elseif chapter >= StageConfig.ANNIHILATION5_CHAPTERS.first and chapter <= StageConfig.ANNIHILATION5_CHAPTERS.last then
        affixIds = MapAffixConfig.ANNIHILATION5_AFFIXES_BY_CHAPTER[chapter]
        affixOverrides = MapAffixConfig.ANNIHILATION5_AFFIX_OVERRIDES
        scale = 1.0
    -- 湮灭IV: chapter 300~322
    elseif chapter >= StageConfig.ANNIHILATION4_CHAPTERS.first and chapter <= StageConfig.ANNIHILATION4_CHAPTERS.last then
        affixIds = MapAffixConfig.ANNIHILATION4_AFFIXES_BY_CHAPTER[chapter]
        affixOverrides = MapAffixConfig.ANNIHILATION4_AFFIX_OVERRIDES
        scale = 1.0
    -- 湮灭III: chapter 277~299
    elseif chapter >= StageConfig.ANNIHILATION3_CHAPTERS.first and chapter <= StageConfig.ANNIHILATION3_CHAPTERS.last then
        affixIds = MapAffixConfig.ANNIHILATION3_AFFIXES_BY_CHAPTER[chapter]
        affixOverrides = MapAffixConfig.ANNIHILATION3_AFFIX_OVERRIDES
        scale = 1.0
    else
        return nil  -- 折磨II之前无词缀
    end

    if not affixIds then return nil end

    local result = {}
    for _, id in ipairs(affixIds) do
        local def = MapAffixConfig.AFFIXES[id]
        if def then
            -- 复制 params；湮灭III 使用专属增强参数，并由实际参数生成显示文本
            local scaledParams = {}
            for k, v in pairs(def.params) do
                if type(v) == "number" then
                    scaledParams[k] = v * scale
                else
                    scaledParams[k] = v
                end
            end
            local override = affixOverrides and affixOverrides[id]
            if override then
                for k, v in pairs(override) do
                    scaledParams[k] = v
                end
            end
            if id == "heal_desert" then
                scaledParams.healReduce = MapAffixConfig.clampHealReduce(scaledParams.healReduce)
            end
            local shortDesc = def.shortDesc or def.name
            local desc = def.desc
            if override or id == "heal_desert" then
                shortDesc, desc = MapAffixConfig.formatAffixText(id, scaledParams, def)
            end
            result[#result + 1] = {
                id = id,
                name = def.name,
                desc = desc,
                shortDesc = shortDesc,
                params = scaledParams,
            }
        end
    end
    return #result > 0 and result or nil
end

return MapAffixConfig
