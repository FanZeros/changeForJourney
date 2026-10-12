-- 装备只读查询：遗匣显示与批量动作共用规则，不依赖英雄或界面模块。
local EquipmentConfig = require("config.EquipmentConfig")
local EquipmentSetConfig = require("config.EquipmentSetConfig")
local EquipmentSystem = require("systems.EquipmentSystem")
local M = {}

local function template(equip)
    return EquipmentConfig.ITEMS[equip.templateId] or EquipmentConfig.ITEMS[tostring(equip.templateId)]
end

--- 与穿戴预检 getFields 同口径；冷装备只投影模板字段，不原地水合。
function M.getFields(equip)
    if not equip.type or not equip.slot then
        local tpl = template(equip)
        if tpl then
            return tpl.slot, tpl.type, tpl.grip,
                math.max(1, math.min(9999, math.floor(tonumber(equip.level) or 1)))
        end
    end
    return equip.slot, equip.type, equip.grip, equip.level or 1
end

function M.getQuality(equip)
    local tpl = template(equip)
    return equip.quality or (tpl and tpl.quality) or 1
end

function M.getSetId(equip)
    return EquipmentSetConfig.getSetIdForTemplate(template(equip)) or "none"
end

--- 空集合=不限；保留旧数字品质签名（0=全部）。
function M.matches(equip, quality, setFilter, detailFilter)
    if not equip then return false end
    local q = M.getQuality(equip)
    if type(quality) == "table" then
        if next(quality) and quality[q] ~= true then return false end
    elseif quality and quality ~= 0 and quality ~= q then return false end
    if type(setFilter) == "table" and next(setFilter) and setFilter[M.getSetId(equip)] ~= true then
        return false
    end
    if detailFilter then
        local slot, equipType = M.getFields(equip)
        if detailFilter.slotFilter and slot ~= detailFilter.slotFilter then return false end
        if detailFilter.typeFilter and equipType ~= detailFilter.typeFilter then return false end
    end
    return true
end

function M.isFiltered(quality, setFilter, detailFilter)
    local q = type(quality) == "table" and next(quality) ~= nil
        or type(quality) == "number" and quality ~= 0
    return q or (type(setFilter) == "table" and next(setFilter) ~= nil)
        or (detailFilter ~= nil and (detailFilter.slotFilter ~= nil or detailFilter.typeFilter ~= nil))
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

--- 腐化恢复快照也会被水合规范化，必须深拷贝；绝不回写 seeds[].equip。
function M.hydrateCopy(equip)
    local result = copy(equip)
    result.quality = M.getQuality(equip)
    EquipmentSystem.hydrate(result)
    -- 已有展示名不因模板水合被覆盖。
    if equip.name then result.name = equip.name end
    return result
end

--- 输入是已水合副本；固定主/副词条、随机与魔化词条全部按实际生效值合计。
function M.attributeValue(equip, key)
    local total, present = 0, false
    for index, stat in ipairs(equip.baseStats or {}) do
        if stat[1] == key then
            total, present = total + EquipmentSystem.effectiveBaseStatValue(equip, index), true
        end
    end
    for _, affix in ipairs(equip.affixes or {}) do
        if affix.key == key then
            total, present = total + EquipmentSystem.effectiveAffixValue(equip, affix), true
        end
    end
    return total, present
end

return M
