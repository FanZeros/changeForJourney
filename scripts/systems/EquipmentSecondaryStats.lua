-- 固定副属性只在真实生成时抽取；存档保存未放大的有序基值，重算不使用 RNG。
local AD = require("systems.AttributeDef")
local EC = require("config.EquipmentConfig")
local M = {}

---@class EquipmentSecondaryRoll
---@field version integer
---@field stats table[] 有序 {key, baseValue}，不含等级/品质/腐化/升阶倍率

local PHYSICAL = { "physPen", "physDmgBonus", "atkSpeed", "critRate", "critDmg", "hitValue" }
local MAGICAL = { "magPen", "magDmgBonus", "atkSpeed", "critRate", "critDmg", "hitValue" }
local HEALING = { "healBonus", "healCritRate", "healCritDmg", "spi", "atkSpeed" }
local COMMON_OUTPUT = { "atkSpeed", "critRate", "critDmg", "hitValue" }
local DEFENSE = { "armor", "energyShield", "dodge", "atkSpeed", "hpBonus", "esBonus", "abnormalRes", "vit" }
local WEAPONS = {
    ["单手剑"] = true, ["双手剑"] = true, ["单手斧"] = true, ["双手斧"] = true,
    ["法杖"] = true, ["魔杖"] = true, ["弓箭"] = true, ["单手弩"] = true,
    ["手铳"] = true, ["匕首"] = true, ["细剑"] = true, ["权杖"] = true,
}
local ACCESSORIES = { ["戒指"] = true, ["项链"] = true, ["耳环"] = true }
local PHYSICAL_MAIN = { physAtk = true, physPen = true, physDmgBonus = true, physAtkBonus = true,
    physCritRate = true, physCritDmg = true }
local MAGICAL_MAIN = { magAtk = true, magPen = true, magDmgBonus = true, magAtkBonus = true,
    magCritRate = true, magCritDmg = true }
local HEALING_MAIN = { healAmount = true, healBonus = true, healCritRate = true,
    healCritDmg = true, hpRegen = true, atkHeal = true }
local baseKeys = {}
for _, key in ipairs(AD.BASE_STATS) do baseKeys[key] = true end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

--- 与 EquipmentPower.genericScore 一致：六围递归完整派生，pct按百分点计价。
---@param key string
---@param visiting table|nil
---@return number
function M.unitValue(key, visiting)
    local meta = AD.META[key]
    if not meta or not finite(meta.valueModel) or meta.valueModel <= 0 then return 0 end
    if baseKeys[key] then
        visiting = visiting or {}
        if visiting[key] then return 0 end
        local derivatives = AD.DERIVATIVES[key]
        if type(derivatives) ~= "table" or #derivatives == 0 then return 0 end
        visiting[key] = true
        local total = 0
        for _, row in ipairs(derivatives) do
            if type(row) ~= "table" or not finite(row.perPoint) or row.perPoint < 0 then
                visiting[key] = nil
                return 0
            end
            total = total + row.perPoint * M.unitValue(row.attr, visiting)
        end
        visiting[key] = nil
        return finite(total) and total or 0
    end
    return meta.dataType == AD.TYPE_PCT and meta.valueModel / 100 or meta.valueModel
end

--- 按槽位/类型选池，武器的伤害系由真实主属性定位，不按名称猜伤害系。
---@param tpl table
---@return string[]
local function poolFor(tpl)
    local main = tpl.stats and tpl.stats[1] and tpl.stats[1][1]
    if tpl.slot == "weapon" and WEAPONS[tpl.type] then
        if PHYSICAL_MAIN[main] then return PHYSICAL end
        if MAGICAL_MAIN[main] then return MAGICAL end
        if HEALING_MAIN[main] then return HEALING end
    elseif tpl.slot == "offhand" then
        if tpl.type == "魔典" or tpl.type == "法珠" then return MAGICAL end
        if tpl.type == "圣物" or tpl.type == "轻盾" or tpl.type == "重盾" then return DEFENSE end
    elseif (tpl.slot == "armor" or tpl.slot == "helmet" or tpl.slot == "shoes")
        and AD.ARMOR_TYPE_ENUM[tpl.type] then
        return DEFENSE
    elseif tpl.slot == "accessory" and ACCESSORIES[tpl.type] then
        if main == "str" then return PHYSICAL end
        if main == "int" then return MAGICAL end
        if main == "spi" then return HEALING end
        if main == "agi" or main == "luk" then return COMMON_OUTPUT end
        if main == "vit" then return DEFENSE end
        if PHYSICAL_MAIN[main] then return PHYSICAL end
        if MAGICAL_MAIN[main] then return MAGICAL end
        if HEALING_MAIN[main] then return HEALING end
        for _, key in ipairs(COMMON_OUTPUT) do
            if main == key then return COMMON_OUTPUT end
        end
        if main == "maxHp" then return DEFENSE end
        for _, key in ipairs(DEFENSE) do
            if main == key then return DEFENSE end
        end
    end
    return {}
end

--- 排序/筛选等消费者可查询完整候选key；返回独立有序副本。
---@return string[]
function M.getAttributeKeys()
    local result, seen = {}, {}
    for _, pool in ipairs({ PHYSICAL, MAGICAL, HEALING, COMMON_OUTPUT, DEFENSE }) do
        for _, key in ipairs(pool) do
            if not seen[key] and M.unitValue(key) > 0 then
                seen[key] = true
                result[#result + 1] = key
            end
        end
    end
    return result
end

local function weightFor(tpl, key)
    if poolFor(tpl) ~= DEFENSE then return 1 end
    if tpl.type == "布甲" then
        if key == "energyShield" then return 6 end
        if key == "esBonus" then return 4 end
        if key == "dodge" then return 2 end
        return 1
    end
    return (key == "armor" or key == "energyShield" or key == "dodge") and 3 or 1
end

local function budgetFor(tpl, index)
    local row = tpl.stats[index + 1]
    if type(row) ~= "table" or not finite(row[2]) or row[2] <= 0 then return 0 end
    local value = row[2] * M.unitValue(row[1])
    return finite(value) and value or 0
end

-- 仅生成失败/非法存档记录一次；不在重算/每帧属性读取中输出日志。
local warned = {}
local function warn(tpl, reason)
    local id = tostring(tpl and tpl.id or "unknown")
    local key = id .. ":" .. reason
    if not warned[key] then
        warned[key] = true
        print("[EquipmentSecondaryStats] " .. id .. "：" .. reason .. "；确定性回退原模板副属性，不补抽")
    end
end

---@param tpl table
---@return EquipmentSecondaryRoll|nil
function M.roll(tpl)
    local count = math.max(0, #tpl.stats - 1)
    local result = { version = 1, stats = {} }
    if count == 0 then return result end
    local main = tpl.stats[1][1]
    local candidates = {}
    for _, key in ipairs(poolFor(tpl)) do
        local meta = AD.META[key]
        -- 池仅用float/pct，避免整数四舍五入改变原槽预算或强加1。
        if key ~= main and meta and meta.dataType ~= AD.TYPE_INT and M.unitValue(key) > 0 then
            candidates[#candidates + 1] = key
        end
    end
    if #candidates < count then
        warn(tpl, "候选池不足")
        return nil
    end
    -- 先验证全部槽，失败不能消耗一部分RNG再半途回退。
    for index = 1, count do
        if budgetFor(tpl, index) <= 0 then
            warn(tpl, "副槽预算非法")
            return nil
        end
    end
    for index = 1, count do
        local total = 0
        for _, key in ipairs(candidates) do total = total + weightFor(tpl, key) end
        local roll = math.random() * total
        local accumulated, selected = 0, #candidates
        for i, key in ipairs(candidates) do
            accumulated = accumulated + weightFor(tpl, key)
            if roll < accumulated then selected = i break end
        end
        local key = table.remove(candidates, selected)
        result.stats[index] = { key, budgetFor(tpl, index) / M.unitValue(key) }
    end
    return result
end

-- 严格有序数组；兼容JSON对象的数字字符串键，但拒绝洞/别名重复/多余元素。
local function orderedArray(value, count)
    if type(value) ~= "table" then return false end
    local size = 0
    for key in pairs(value) do
        local index = tonumber(key)
        if not index or index % 1 ~= 0 or index < 1 or index > count then return false end
        size = size + 1
    end
    if size ~= count then return false end
    for index = 1, count do
        if value[index] == nil and value[tostring(index)] == nil then return false end
    end
    return true
end

local function arrayItem(value, index)
    return value[index] or value[tostring(index)]
end

--- 只拷贝白名单字段，无RNG。非法数据保留惰性version=0标记，绝不补抽。
--- 未知合法版本原样深拷贝保留，但本实现不解释它，重算回退原模板。
---@param tpl table|nil
---@param data any
---@param silent boolean|nil 重算时不输出日志
---@return EquipmentSecondaryRoll
function M.copyValidated(tpl, data, silent)
    local function invalid(reason)
        if not silent then warn(tpl, reason) end
        return { version = 0, stats = {} }
    end
    if type(data) ~= "table" or not finite(data.version) or data.version % 1 ~= 0
        or data.version < 0 then return invalid("版本字段非法") end
    if data.version == 0 then return { version = 0, stats = {} } end
    local count = tpl and math.max(0, #tpl.stats - 1) or 0
    if not orderedArray(data.stats, count) then return invalid("副属性条数非法") end
    local result = { version = data.version, stats = {} }
    local seen = {}
    if tpl and tpl.stats[1] then seen[tpl.stats[1][1]] = true end
    -- 保存的基值是真源，不能因未来模板预算调整而抹掉抽取结果。
    local allowed = {}
    for _, key in ipairs(M.getAttributeKeys()) do allowed[key] = true end
    for index = 1, count do
        local row = arrayItem(data.stats, index)
        if not orderedArray(row, 2) then return invalid("副属性行结构非法") end
        local key, value = arrayItem(row, 1), arrayItem(row, 2)
        if type(key) ~= "string" or seen[key] or M.unitValue(key) <= 0
            or not finite(value) or value < 0 then return invalid("属性基值或key非法") end
        if data.version == 1 then
            if not allowed[key] or AD.META[key].dataType == AD.TYPE_INT then
                return invalid("属性不在合法候选集合")
            end
        end
        seen[key] = true
        result.stats[index] = { key, value }
    end
    return result
end

--- 验证后返回v1有序副属性；其他版本只确定性回退，不在此刷日志。
---@param tpl table
---@param data any
---@return table[]|nil
function M.resolve(tpl, data)
    if type(data) ~= "table" or data.version ~= 1 then return nil end
    -- copyValidated日志只用于生成/水合/脱水；重算传入非法值也不能刷屏。
    local result = M.copyValidated(tpl, data, true)
    return result.version == 1 and result.stats or nil
end

--- 主属性只读原模板，副属性只读保存基值；倍率只在此应用一次。
---@param tpl table|nil
---@param level number
---@param baseStrength number
---@param data EquipmentSecondaryRoll|nil
---@return table[]
function M.buildBaseStats(tpl, level, baseStrength, data)
    if not tpl then return {} end
    local lv = tonumber(level) or 1
    if not finite(lv) then lv = 1 end
    local safeLevel = math.max(1, math.min(9999, math.floor(lv)))
    local strength = tonumber(baseStrength) or 1.0
    if not finite(strength) or strength <= 0 then strength = 1.0 end
    local secondaries = data ~= nil and M.resolve(tpl, data) or nil
    local stats = {}
    for index, original in ipairs(tpl.stats) do
        local row = index > 1 and secondaries and secondaries[index - 1] or original
        local value = row[2] * (1 + (safeLevel - 1) * EC.LEVEL_SCALE) * strength
        if not finite(value) then value = original[2] * (1 + (safeLevel - 1) * EC.LEVEL_SCALE) end
        local meta = AD.META[row[1]]
        if meta and meta.dataType == AD.TYPE_INT then value = math.floor(value + 0.5) end
        stats[index] = { row[1], value }
    end
    return stats
end

--- 水合仅校验/拷贝已有字段；绝不为无字段旧装备补抽。
---@param tpl table|nil
---@param equip table
function M.restore(tpl, equip)
    if equip.secondaryRoll ~= nil then equip.secondaryRoll = M.copyValidated(tpl, equip.secondaryRoll) end
    if not tpl then return end
    equip.name, equip.type, equip.slot, equip.grip = tpl.name, tpl.type, tpl.slot, tpl.grip
    if not equip.baseStats or equip.secondaryRoll ~= nil then
        local quality = EC.QUALITY[equip.quality]
        local strength = (quality and quality.baseStrength or 1.0) * (equip.corruptBaseMult or 1)
        equip.baseStats = M.buildBaseStats(tpl, equip.level, strength, equip.secondaryRoll)
    end
end

return M
