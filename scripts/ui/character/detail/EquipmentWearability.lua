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

-- 职业筛选只看自然槽位/类型，按该职业全部英雄的配置取并集。
-- 不借当前角色等级、拥有状态或转职；具体是否能穿仍由原预检灰显。
---@param classId string|nil
---@return function checker (equip) -> boolean
function M.createClassChecker(classId)
    if classId == nil then return function() return true end end
    local CC = require("config.ClassConfig")
    local normalized = CC.normalize(classId)
    if not CC.get(normalized) then return function() return false end end
    local typesBySlot, unrestricted = {}, {}
    for _, heroId in ipairs(HeroConfig.getIdsByClass(normalized)) do
        for _, slot in ipairs(EquipmentConfig.SLOTS) do
            local types = EquipmentSystem.getWearableTypeSet(heroId, slot)
            if types == nil then
                unrestricted[slot] = true
            else
                typesBySlot[slot] = typesBySlot[slot] or {}
                for equipType, allowed in pairs(types) do
                    if allowed then typesBySlot[slot][equipType] = true end
                end
            end
        end
    end
    return function(equip)
        local slot, equipType = M.getFields(equip)
        return unrestricted[slot] == true or (typesBySlot[slot] ~= nil and typesBySlot[slot][equipType] == true)
    end
end

-- 类型黄色提示忽略装备等级，但保留当前角色类型限制与实际主副手搭配。
-- 仅添加内存候选，与 createChecker 共用完整只读规则，不调用 applyEquip。
---@param equipData table|nil
---@param heroId number|string|nil
---@param heroesData table|nil
---@return function checker (template, targetSlot?) -> boolean
function M.createTypeChecker(equipData, heroId, heroesData)
    local heroN = tonumber(heroId)
    if not heroN or not HeroConfig.get(heroN) then return function() return false end end
    local source = equipData or {}
    local mainSlots = EquipmentSystem.getHeroSlots(source, heroN) or {}
    local inventory = {}
    for _, slot in ipairs({ "weapon", "offhand" }) do
        local seq = mainSlots[slot]
        local equip = readInventory(source, seq)
        if equip then inventory[tostring(seq)] = equip end
    end
    local candidateSeq = -1
    while inventory[tostring(candidateSeq)] ~= nil do candidateSeq = candidateSeq - 1 end
    local candidate = { level = 1 }
    inventory[tostring(candidateSeq)] = candidate
    local checker = M.createChecker({ inventory = inventory, equipped = source.equipped }, heroN, nil)
    -- createChecker 的 nil heroes 不检查等级，但双持仍必须读当前转职。
    local hd = heroesData and heroesData.roster
        and (heroesData.roster[heroN] or heroesData.roster[tostring(heroN)])
    if hd then
        checker = M.createChecker({ inventory = inventory, equipped = source.equipped }, heroN,
            { roster = { [heroN] = { level = 9999, advBranch = hd.advBranch } } })
    end
    return function(tpl, slot)
        candidate.slot, candidate.type, candidate.grip = tpl.slot, tpl.type, tpl.grip
        return checker(candidateSeq, slot or tpl.slot)
    end
end

return M
