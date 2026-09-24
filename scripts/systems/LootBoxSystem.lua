------------------------------------------------------------------------
-- LootBoxSystem — 遗匣存储、领取与分解。
-- seeds 同时容纳合并的挂机种子与独立的溢出装备（equip 字段）。
-- 已生成装备不再骰词条，不参与种子合并或等级回退。
------------------------------------------------------------------------
local EquipmentSystem = require("systems.EquipmentSystem")
local BlacksmithConfig = require("config.BlacksmithConfig")

local LootBoxSystem = {}

-- 只作用于尚未生成的旧版挂机种子。
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

--- 旧档按品质、等级合并；完整装备始终保持独立。
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

--- 挂机种子按组计数，不再因旧版 9999 件上限丢弃奖励。
function LootBoxSystem.addSeed(lootboxData, stageId, quality, level)
    lootboxData.seeds = lootboxData.seeds or {}
    for _, entry in ipairs(lootboxData.seeds) do
        if not entry.equip and entry.quality == quality and entry.level == level then
            entry.count = (entry.count or 1) + 1
            return true
        end
    end
    lootboxData.seeds[#lootboxData.seeds + 1] = {
        quality = quality, level = level, count = 1,
    }
    return true
end

--- 完整保存溢出装备，领取时仍是同一件装备。
function LootBoxSystem.addEquipment(lootboxData, equip)
    lootboxData.seeds = lootboxData.seeds or {}
    lootboxData.seeds[#lootboxData.seeds + 1] = {
        quality = equip.quality, level = equip.level, count = 1, equip = equip,
    }
end

--- 奖励投递只有一个入口：有空位进背包，否则完整暂存遗匣。
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

local function materialize(entry)
    if entry.equip then return entry.equip end
    local level = entry.level
    if LootBoxSystem.levelCap > 0 then
        level = math.min(level, LootBoxSystem.levelCap)
    end
    return EquipmentSystem.generateRandom(level, entry.quality)
end

--- 取出一件，不修改背包；需要容量保护的调用方使用 claimGroup。
function LootBoxSystem.claimOne(lootboxData, index)
    local entry = lootboxData.seeds[index]
    if not entry or (entry.count or 1) <= 0 then return nil end
    local equip = materialize(entry)
    if not equip then return nil end
    entry.count = (entry.count or 1) - 1
    if entry.count <= 0 then table.remove(lootboxData.seeds, index) end
    return equip
end

--- 只消费成功入包的条目；满包和生成失败都保留剩余奖励。
function LootBoxSystem.claimGroup(lootboxData, index, equipData)
    local entry = lootboxData.seeds[index]
    if not entry or (entry.count or 1) <= 0 then return {}, false end
    local claimed = {}
    local remaining = entry.count or 1
    while remaining > 0 do
        if EquipmentSystem.isInventoryFull(equipData) then return claimed, true end
        local equip = materialize(entry)
        if not equip then
            print("[LootBoxSystem] 装备生成失败，保留遗匣条目")
            break
        end
        EquipmentSystem.addToInventory(equipData, equip)
        claimed[#claimed + 1] = equip
        remaining = remaining - 1
        entry.count = remaining
    end
    if remaining <= 0 then table.remove(lootboxData.seeds, index) end
    return claimed, false
end

function LootBoxSystem.claimAll(lootboxData, equipData)
    local claimed = {}
    -- 新近溢出的完整装备通常在末尾，优先领取；反向遍历删除安全。
    for index = #lootboxData.seeds, 1, -1 do
        local group, bagFull = LootBoxSystem.claimGroup(lootboxData, index, equipData)
        for _, equip in ipairs(group) do claimed[#claimed + 1] = equip end
        if bagFull then return claimed, true end
    end
    return claimed, false
end

local function decomposeValue(entry)
    local cost = BlacksmithConfig.QUALITY_COST[entry.quality]
    if not cost then return 0, 0 end
    local count = entry.count or 1
    return math.floor(cost.decBase * (1 + (entry.level or 1) * cost.decScale)) * count, count
end

function LootBoxSystem.decomposeOne(lootboxData, index)
    local entry = lootboxData.seeds and lootboxData.seeds[index]
    if not entry then return 0, 0 end
    local essence, pieces = decomposeValue(entry)
    if pieces > 0 then table.remove(lootboxData.seeds, index) end
    print("[LootBoxSystem] 分解遗匣条目: pieces=" .. pieces .. " essence=" .. essence)
    return essence, pieces
end

function LootBoxSystem.decomposeAll(lootboxData)
    local essence, pieces = 0, 0
    for index = #lootboxData.seeds, 1, -1 do
        local value, count = decomposeValue(lootboxData.seeds[index])
        if count > 0 then
            essence = essence + value
            pieces = pieces + count
            table.remove(lootboxData.seeds, index)
        end
    end
    print("[LootBoxSystem] 全部分解: pieces=" .. pieces .. " essence=" .. essence)
    return essence, pieces
end

--- 摘要顺序与原存储一致，领取/分解使用相同索引。
function LootBoxSystem.getSummary(lootboxData)
    local summary = {}
    for _, entry in ipairs(lootboxData.seeds or {}) do
        summary[#summary + 1] = {
            quality = entry.quality, level = entry.level,
            count = entry.count or 1, equip = entry.equip,
        }
    end
    return summary
end

return LootBoxSystem
