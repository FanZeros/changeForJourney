-- 配装仓库的只读穿戴预检。规则逐条件对齐 EquipmentSystem.applyEquip；
-- 不调用其写入口（会 hydrate / 整理槽位 / 打日志），也不修改装备或名册。
local EquipmentSystem = require("systems.EquipmentSystem")
local EquipmentConfig = require("config.EquipmentConfig")
local HeroConfig = require("config.HeroConfig")
local AdvancementConfig = require("config.AdvancementConfig")
local M = {}

--- 与 getFromInventory 的水合触发条件一致，只投影穿戴所需字段。
--- hydrate 会覆写 type/slot/grip 并钳制等级；此处不触碰词缀、腐化快照等源数据。
---@param equip table
---@return string|nil slot
---@return string|nil equipType
---@return string|nil grip
---@return number level
function M.getFields(equip)
    if not equip.type or not equip.slot then
        local tpl = EquipmentConfig.ITEMS[equip.templateId]
            or EquipmentConfig.ITEMS[tostring(equip.templateId)]
        if tpl then
            return tpl.slot, tpl.type, tpl.grip,
                math.max(1, math.min(9999, math.floor(tonumber(equip.level) or 1)))
        end
    end
    return equip.slot, equip.type, equip.grip, equip.level or 1
end

---@param equipData table|nil
---@param seq number|string|nil
---@return table|nil
local function readInventory(equipData, seq)
    if not equipData or not equipData.inventory or seq == nil then return nil end
    return equipData.inventory[tostring(seq)] or equipData.inventory[seq]
end

--- 一次列表查询共用角色等级、职业集合及当前主副手；不复制整个 inventory。
--- nil slot 预检装备的自然槽位（单手武器自然为主手，不误用副手规则）。
---@param equipData table|nil
---@param heroId number|string
---@param heroesData table|nil
---@return function checker (seq, slot?) -> ok, err
function M.createChecker(equipData, heroId, heroesData)
    local heroN = tonumber(heroId)
    local heroCfg = heroN and HeroConfig.get(heroN)
    local heroLevel = EquipmentSystem.getHeroLevel(heroesData, heroId)
    local hd = heroesData and heroesData.roster and heroN
        and (heroesData.roster[heroN] or heroesData.roster[tostring(heroN)])
    local dualMode = AdvancementConfig.getDualWieldMode(hd and hd.advBranch)
    local slots = EquipmentSystem.getHeroSlots(equipData, heroN or heroId) or {}
    local mainEquip = readInventory(equipData, slots.weapon)
    local offEquip = readInventory(equipData, slots.offhand)
    local mainType = mainEquip and select(2, M.getFields(mainEquip))
    local offSlot, offType = nil, nil
    if offEquip then offSlot, offType = M.getFields(offEquip) end
    local wearableBySlot = {}
    for _, slot in ipairs(EquipmentConfig.SLOTS) do
        wearableBySlot[slot] = EquipmentSystem.getWearableTypeSet(heroId, slot)
    end

    return function(seq, slot)
        local seqN = tonumber(seq)
        if not equipData or not seqN or not heroN then return false, "参数缺失" end
        local equip = readInventory(equipData, seqN)
        if not equip then return false, "装备不存在" end
        local naturalSlot, equipType, grip, level = M.getFields(equip)
        slot = slot or naturalSlot
        if not slot then return false, "参数缺失" end
        if heroesData then
            local ok, required = EquipmentSystem.checkLevelGate(heroLevel, level)
            if not ok then return false, "角色等级不足，需要等级 " .. tostring(required) end
        end
        if not heroCfg then return false, "英雄不存在" end

        local wearable = wearableBySlot[slot]
        local isOffhandWeapon = slot == "offhand" and naturalSlot == "weapon" and grip == "onehand"
        if isOffhandWeapon then
            if not dualMode then return false, "槽位不匹配" end
            wearable = wearableBySlot.weapon
            if dualMode == "same" and (not mainEquip or mainType ~= equipType) then
                return false, "双刃精通：副手必须装备与主手相同类型的武器"
            elseif dualMode == "different" and mainEquip and mainType == equipType then
                return false, "武器精通：副手必须装备不同类型的武器"
            end
        elseif naturalSlot ~= slot then
            return false, "槽位不匹配"
        elseif slot == "offhand" and dualMode then
            return false, "双持天赋无法装备常规副手"
        end
        if wearable and not wearable[equipType] then
            return false, "该英雄无法穿戴此类型装备"
        end
        if slot == "weapon" and grip == "onehand" and dualMode and offSlot == "weapon" then
            if dualMode == "same" and offType ~= equipType then
                return false, "双刃精通：主手必须与副手武器同类型"
            elseif dualMode == "different" and offType == equipType then
                return false, "武器精通：主手必须与副手武器不同类型"
            end
        end
        -- 双手替换副手、副手替换双手是 applyEquip 的自动卸槽，不是拒绝条件。
        return true, nil
    end
end

---@param equipData table|nil
---@param seq number|string
---@param heroId number|string
---@param slot string|nil
---@param heroesData table|nil
---@return boolean ok
---@return string|nil err
function M.canEquip(equipData, seq, heroId, slot, heroesData)
    return M.createChecker(equipData, heroId, heroesData)(seq, slot)
end

return M
