-- 装备生效数值曲线与洗练投入估值；不参与生成、随机副预算或存档写入。
local EC = require("config.EquipmentConfig")
local AD = require("systems.AttributeDef")
local Growth = {}

--- 只读取装备等级；1~50级不补偿，节点间线性插值，200级以上封顶。
---@param equip table|nil
---@param key string
---@return number
function Growth.getMultiplier(equip, key)
    local curve = EC.FLAT_STAT_GROWTH[key]
    if not curve then return 1 end
    local level = tonumber(equip and equip.level) or 1
    if level ~= level or level == math.huge or level == -math.huge then return 1 end
    if level <= 50 then return 1 end
    if level < 100 then return 1 + (curve[1] - 1) * (level - 50) / 50 end
    if level < 200 then return curve[1] + (curve[2] - curve[1]) * (level - 100) / 100 end
    return curve[2]
end

--- 无角色过滤的原静态价值：六围含完整派生，百分比按每个百分点计价。
---@param key string
---@return number
local function staticUnitValue(key)
    local isBaseStat = false
    for _, baseKey in ipairs(AD.BASE_STATS) do
        if key == baseKey then isBaseStat = true break end
    end
    if isBaseStat then
        local derivatives = AD.DERIVATIVES[key]
        if type(derivatives) ~= "table" or #derivatives == 0 then
            error("洗练升阶加成缺少六围派生配置: " .. tostring(key))
        end
        local value = 0
        for _, entry in ipairs(derivatives) do
            local meta = AD.META[entry.attr]
            if not meta or type(meta.valueModel) ~= "number" or meta.valueModel < 0
                or meta.valueModel ~= meta.valueModel or meta.valueModel == math.huge
                or type(entry.perPoint) ~= "number" or entry.perPoint < 0
                or entry.perPoint ~= entry.perPoint or entry.perPoint == math.huge then
                error("洗练升阶加成缺少有效派生价值: " .. tostring(key) .. "/" .. tostring(entry.attr))
            end
            local weight = meta.dataType == AD.TYPE_PCT and meta.valueModel / 100 or meta.valueModel
            value = value + entry.perPoint * weight
        end
        return value
    end
    local meta = AD.META[key]
    if not meta then return 0 end
    -- 探索属性不计战斗战力，但旧升阶投入仍须有正的洗练价值。
    local valueModel = meta.refineValueModel or meta.valueModel
    if not valueModel or valueModel <= 0 then return 0 end
    return meta.dataType == AD.TYPE_PCT and valueModel / 100 or valueModel
end

--- 仅洗练转移使用等级补偿后的线性估值，不改变共享VM或腐化原始预算。
---@param equip table|nil
---@param key string
---@return number
function Growth.refineUnitValue(equip, key)
    return staticUnitValue(key) * Growth.getMultiplier(equip, key)
end

--- 两类来源曲线共用双手预算规则；不写回输入，不让极大输入先乘C溢出。
---@param curves table|nil
---@param equip table|nil
---@param key string
---@param value number
---@return number
local function scaleSourceBonus(curves, equip, key, value)
    local limit = curves and curves[key]
    if not limit or value <= 0 then return value end
    local tpl = equip and EC.ITEMS[equip.templateId]
    local slot = equip and (equip.slot or (tpl and tpl.slot))
    local grip = equip and (equip.grip or (tpl and tpl.grip))
    local budget = limit * ((slot == "weapon" and grip == "twohand") and 2 or 1)
    return budget / (1 + budget / value)
end

--- 直给暴率按来源递减；双手主武器预算翻倍，非目标属性保持原值。
---@param equip table|nil
---@param key string
---@param value number
---@param source string
---@return number
function Growth.scaleCritRate(equip, key, value, source)
    return scaleSourceBonus(EC.CRIT_RATE_CURVE[source], equip, key, value)
end

--- 普通装备优势/劣势伤害按单条来源递减，角色总值和六围派生不在此处理。
---@param equip table|nil
---@param key string
---@param value number
---@param source string
---@return number
function Growth.scaleTypeBonus(equip, key, value, source)
    return scaleSourceBonus(EC.TYPE_BONUS_CURVE[source], equip, key, value)
end

return Growth
