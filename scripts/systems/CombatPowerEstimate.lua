-- ============================================================================
-- CombatPowerEstimate — 「实战预估」分项计价原型（仅 battle-lab 校准使用）
--
-- 背景：官方战力（CharacterPower.calcHeroPower / BattleLab.powerOf）对所有
-- 属性用统一 valueModel 权重，且不区分英雄伤害类别——物理英雄戴力量戒与
-- 智力戒显示战力完全相同（实测 112/112、160/160），无法反映职业适配。
--
-- 原型思路（最小可解释差异）：
--   1. 与官方同一价值底座：沿用 AD.META.valueModel 与 pct/100 换算；
--   2. 属性按用途分组：phys（物理攻击系）/ mag（魔法攻击系）/ heal（治疗系）
--      / generic（通用攻防，不乘系数）；
--   3. 按英雄攻击大类（AD.getAtkCategory(hero.atkType)）给本系属性 1.0、
--      异系输出属性打折（OFF_FACTOR）。异系不完全归零：六围派生里力量也带
--      护甲/生命、秘识也带护盾/生命，防御部分价值仍保留在 generic/防御组；
--   4. 输出 = 官方同底座的加权和，只多一个类别系数表，便于后续按实测回归。
--
-- ⚠️ 原型状态：仅在 tests/BattleLab.lua 报告中使用（estimatePower 字段），
--    不接线角色页/队伍展示，不修改正式战力公式。系数未经跨阵容/层级验证，
--    只能用于「同战力不同适配」的方向性判断，不能作为绝对强度承诺。
-- ============================================================================

local AD = require("systems.AttributeDef")

local M = {}

-- 异系输出属性折扣。
-- 拟合依据（_proc/fit_power_estimate.py，31 组败局样本、DPS 口径岭回归）：
--   physical 类 off[mag] 与 magical 类 off[phys] 的非负约束解均为 0
--   （异系攻击属性对 DPS 无可测贡献，其派生生存价值已计入 generic 组）。
-- 工程上保留小正值而非 0：避免显示战力对异系装备完全归零（异系属性的
-- 六围派生生存价值仍然存在），并保持 A/B 方向区分度。
local OFF_FACTOR = 0.10

-- 治疗系英雄对输出属性的系数。
-- 拟合依据（_proc/fit_power_estimate.py --mode healing，22 组牧师样本剔除
-- heal/taken≥0.65 的需求截断饱和后取 8 组非饱和，HPS 口径岭回归 R²=0.32）：
--   heal 组归一化基准 1.0，phys/mag 输出组系数 ≈0.48。据此确认初值 0.5 与
--   数据一致，保留 0.5。⚠️ R² 偏低（n=8、仅 303 关超时带非饱和），属方向性
--   验证而非精确标定；带2/3（304/305 阵亡带）治疗全被需求截断，无法拟合。
local HEALER_ATK_FACTOR = 0.5

-- 属性分组：phys / mag / heal（未列出的非跳过属性都按 generic 全额计）
local GROUP = {
    -- 物理攻击系
    [AD.PHYS_ATK]               = "phys",
    [AD.PHYS_ATK_BONUS]         = "phys",
    [AD.FINAL_PHYS_ATK_BONUS]   = "phys",
    [AD.PHYS_PEN]               = "phys",
    [AD.PHYS_CRIT_RATE]         = "phys",
    [AD.PHYS_CRIT_DMG]          = "phys",
    [AD.PHYS_DMG_BONUS]         = "phys",
    [AD.PHYS_BLOCK_RATE]        = "phys",
    [AD.PHYS_BLOCK_RATIO]       = "phys",
    -- 魔法攻击系
    [AD.MAG_ATK]                = "mag",
    [AD.MAG_ATK_BONUS]          = "mag",
    [AD.FINAL_MAG_ATK_BONUS]    = "mag",
    [AD.MAG_PEN]                = "mag",
    [AD.MAG_CRIT_RATE]          = "mag",
    [AD.MAG_CRIT_DMG]           = "mag",
    [AD.MAG_DMG_BONUS]          = "mag",
    [AD.MAG_BLOCK_RATE]         = "mag",
    [AD.MAG_BLOCK_RATIO]        = "mag",
    -- 治疗系
    [AD.HEAL_AMOUNT]            = "heal",
    [AD.HEAL_BONUS]             = "heal",
    [AD.HEAL_CRIT_RATE]         = "heal",
    [AD.HEAL_CRIT_DMG]          = "heal",
}

-- 与官方 powerOf 相同的跳过表：六围已派生进战斗属性，HP 当前值与攻击间隔
-- 不重复计价；物理/魔法抗性由护甲转化，不双计。
local SKIP = {
    [AD.STR] = true, [AD.AGI] = true, [AD.INT] = true,
    [AD.VIT] = true, [AD.LUK] = true, [AD.SPI] = true,
    [AD.HP] = true, [AD.ATK_INTERVAL] = true,
    [AD.PHYS_RES] = true, [AD.MAG_RES] = true,
}

--- 类别 → 分组系数
---@param category string "physical"|"magical"|"healing"
---@return table<string, number>
local function factorsFor(category)
    if category == "magical" then
        return { phys = OFF_FACTOR, mag = 1.0, heal = OFF_FACTOR }
    elseif category == "healing" then
        return { phys = HEALER_ATK_FACTOR, mag = HEALER_ATK_FACTOR, heal = 1.0 }
    end
    return { phys = 1.0, mag = OFF_FACTOR, heal = OFF_FACTOR }
end

M.factorsFor = factorsFor

--- 按官方价值底座把属性分解到 phys/mag/heal/generic 四组（未乘类别系数）。
--- 供拟合工具（tests/battle_lab_fit.lua + _proc/fit_power_estimate.py）做回归，
--- 也供报告展示各组构成。
---@param attrs table UnitAttributes
---@param atkType number|nil AD.ATK_*（nil 时类别回落 physical，仅影响第二返回值）
---@return table<string, number> sums { phys, mag, heal, generic }
---@return string category
function M.breakdown(attrs, atkType)
    local category = AD.getAtkCategory(atkType)
    local sums = { phys = 0, mag = 0, heal = 0, generic = 0 }
    for key, meta in pairs(AD.META) do
        if not SKIP[key] and meta.valueModel and meta.valueModel > 0 then
            local value = attrs:get(key)
            local unit = meta.dataType == AD.TYPE_PCT and meta.valueModel / 100 or meta.valueModel
            local group = GROUP[key] or "generic"
            sums[group] = sums[group] + value * unit
        end
    end
    return sums, category
end

--- 计算单位的分项计价预估战力
---@param attrs table UnitAttributes（含 final 表与 get 方法）
---@param atkType number AD.ATK_* 攻击类型
---@return integer estimate 预估战力（向下取整到 0.5 精度以内）
---@return string category 伤害大类
function M.estimate(attrs, atkType)
    local sums, category = M.breakdown(attrs, atkType)
    local factors = factorsFor(category)
    local total = sums.generic
        + sums.phys * factors.phys
        + sums.mag * factors.mag
        + sums.heal * factors.heal
    return math.floor(total + 0.5), category
end

--- 便捷入口：直接对 HC.createHero 产物估值
--- 战斗单位本体可能没有 atkType 字段（仅 ClassGateRuntime 战中动态设置），
--- 类型以 attrs.atkType 为准（UnitAttributes.create 从英雄配置写入，恒有值）。
---@param hero table createHero 返回的单位（含 attrs）
---@return integer estimate
---@return string category
function M.estimateUnit(hero)
    return M.estimate(hero.attrs, hero.attrs and hero.attrs.atkType or nil)
end

return M
