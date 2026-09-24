------------------------------------------------------------------------
-- LootBoxSystem — 遗匣保存确定装备，领取不再随机生成。
-- seeds 字段保留旧存档结构；旧分组种子只迁移一次。
------------------------------------------------------------------------
local EquipmentSystem = require("systems.EquipmentSystem")
local BlacksmithConfig = require("config.BlacksmithConfig")

local LootBoxSystem = {}
-- 只用于旧版种子迁移，不影响已经确定的装备。
--- 领取时若种子 level 超过此值则钳制，0=不限制
LootBoxSystem.levelCap = 0

function LootBoxSystem.getTotalCount(lootboxData)
    local total = 0
    for _, entry in ipairs(lootboxData.seeds or {}) do
        total = total + (entry.count or 1)
    end
    return total
end

function LootBoxSystem.getEntryCount(lootboxData)
    return #(lootboxData.seeds or {})
end

--- 兼容旧档分组；完整装备始终独立，不重骰。
function LootBoxSystem.consolidateSeeds(lootboxData)
    if not lootboxData or not lootboxData.seeds then return end
    local merged, byKey = {}, {}
    for _, entry in ipairs(lootboxData.seeds) do
        if entry.equip then
            merged[#merged + 1] = entry
        else
            local key = tostring(entry.quality) .. ":" .. tostring(entry.level)
            local target = byKey[key]
            if target then
                target.count = target.count + (entry.count or 1)
            else
                entry.count = entry.count or 1
                entry.stageId = nil
                byKey[key] = entry
                merged[#merged + 1] = entry
            end
        end
    end
    lootboxData.seeds = merged
end

function LootBoxSystem.addEquipment(lootboxData, equip, source)
    lootboxData.seeds = lootboxData.seeds or {}
    lootboxData.seeds[#lootboxData.seeds + 1] = {
        quality = equip.quality, level = equip.level, count = 1,
        equip = equip, source = source or "overflow",
    }
end

--- 保留掉落接口；内容在入匣时确定，而不是领取时生成。
function LootBoxSystem.addSeed(lootboxData, stageId, quality, level)
    local equip = EquipmentSystem.generateRandom(level, quality)
    if not equip then
        print("[LootBoxSystem] 装备生成失败，保留待整理掉落")
        lootboxData.seeds = lootboxData.seeds or {}
        lootboxData.seeds[#lootboxData.seeds + 1] = { quality = quality, level = level, count = 1 }
        return false
    end
    LootBoxSystem.addEquipment(lootboxData, equip, "idle")
    return true
end

--- 旧种子转换为确定装备；失败保留剩余数量，不丢奖励。
function LootBoxSystem.revealLegacy(lootboxData)
    local revealed, converted = {}, 0
    for _, entry in ipairs(lootboxData.seeds or {}) do
        if entry.equip then
            revealed[#revealed + 1] = entry
        else
            local remaining = entry.count or 1
            local level = entry.level
            if LootBoxSystem.levelCap > 0 then level = math.min(level, LootBoxSystem.levelCap) end
            while remaining > 0 do
                local equip = EquipmentSystem.generateRandom(level, entry.quality)
                if not equip then break end
                revealed[#revealed + 1] = {
                    quality = equip.quality, level = equip.level, count = 1,
                    equip = equip, source = "idle",
                }
                converted = converted + 1
                remaining = remaining - 1
            end
            if remaining > 0 then
                entry.count = remaining
                revealed[#revealed + 1] = entry
            end
        end
    end
    if converted > 0 then
        lootboxData.seeds = revealed
        print("[LootBoxSystem] 旧遗匣内容已确定: " .. converted .. " 件")
    end
    return converted
end

---@return string destination
function LootBoxSystem.deliverEquipment(lootboxData, equipData, equip)
    if not EquipmentSystem.isInventoryFull(equipData) then
        EquipmentSystem.addToInventory(equipData, equip)
        return "inventory"
    end
    LootBoxSystem.addEquipment(lootboxData, equip)
    print("[LootBoxSystem] 背包溢出已入遗匣: " .. tostring(equip.templateId)
        .. " q=" .. tostring(equip.quality) .. " lv=" .. tostring(equip.level))
    return "lootbox"
end

--- 只取出已有内容；未迁移条目不能在领取时偷偷随机。
function LootBoxSystem.claimOne(lootboxData, index)
    local entry = lootboxData.seeds[index]
    if not entry or not entry.equip then return nil end
    table.remove(lootboxData.seeds, index)
    return entry.equip
end

function LootBoxSystem.claimGroup(lootboxData, index, equipData)
    local entry = lootboxData.seeds[index]
    if not entry or not entry.equip then return {}, false end
    if EquipmentSystem.isInventoryFull(equipData) then return {}, true end
    EquipmentSystem.addToInventory(equipData, entry.equip)
    table.remove(lootboxData.seeds, index)
    return { entry.equip }, false
end

local function matchesQuality(entry, quality)
    return entry.equip and (not quality or quality == 0 or entry.equip.quality == quality)
end

--- 可选品质只处理筛选范围，未显示品质不会被领取。
function LootBoxSystem.claimAll(lootboxData, equipData, quality)
    local claimed = {}
    for index = #lootboxData.seeds, 1, -1 do
        if matchesQuality(lootboxData.seeds[index], quality) then
            local group, bagFull = LootBoxSystem.claimGroup(lootboxData, index, equipData)
            for _, equip in ipairs(group) do claimed[#claimed + 1] = equip end
            if bagFull then return claimed, true end
        end
    end
    return claimed, false
end

local function decomposeValue(entry)
    local equip = entry.equip
    if not equip then return 0, 0 end
    local cost = BlacksmithConfig.QUALITY_COST[equip.quality]
    if not cost then return 0, 0 end
    return math.floor(cost.decBase * (1 + (equip.level or 1) * cost.decScale)), 1
end

function LootBoxSystem.decomposeOne(lootboxData, index)
    local entry = lootboxData.seeds and lootboxData.seeds[index]
    if not entry then return 0, 0 end
    local essence, pieces = decomposeValue(entry)
    if pieces > 0 then table.remove(lootboxData.seeds, index) end
    print("[LootBoxSystem] 回收遗匣条目: pieces=" .. pieces .. " essence=" .. essence)
    return essence, pieces
end

function LootBoxSystem.decomposeAll(lootboxData, quality)
    local essence, pieces = 0, 0
    for index = #lootboxData.seeds, 1, -1 do
        local entry = lootboxData.seeds[index]
        if matchesQuality(entry, quality) then
            local value, count = decomposeValue(entry)
            if count > 0 then
                essence = essence + value
                pieces = pieces + count
                table.remove(lootboxData.seeds, index)
            end
        end
    end
    print("[LootBoxSystem] 一键回收: pieces=" .. pieces .. " essence=" .. essence)
    return essence, pieces
end

function LootBoxSystem.getSummary(lootboxData)
    local summary = {}
    for index, entry in ipairs(lootboxData.seeds or {}) do
        summary[#summary + 1] = {
            quality = entry.quality, level = entry.level,
            count = entry.count or 1, equip = entry.equip,
            source = entry.source, sourceIndex = index,
        }
    end
    return summary
end

return LootBoxSystem
