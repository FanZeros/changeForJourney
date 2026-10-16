------------------------------------------------------------------------
-- LootBoxSystem — 遗匣保存确定装备，领取不再随机生成。
-- seeds 字段保留旧存档结构；旧分组种子只迁移一次。
------------------------------------------------------------------------
local EquipmentSystem = require("systems.EquipmentSystem")
local BlacksmithConfig = require("config.BlacksmithConfig")
local EquipmentQuery = require("systems.EquipmentQuery")
local EquipmentPower = require("systems.EquipmentPower")

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
                -- 旧存档种子沿用原副属性；新入匣装备仍在生成时抽取并保存。
                local equip = EquipmentSystem.generateRandom(level, entry.quality, { legacySecondary = true })
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

--- 可选品质+套装+部位/类型 AND 过滤；领取优先级固定为通用评分降序。
--- 只水合副本，不因领取顺序改写原遗匣数组或装备；同分保持原条目顺序。
function LootBoxSystem.claimAll(lootboxData, equipData, quality, setFilter, detailFilter)
    local claimed, candidates = {}, {}
    local free = math.max(0, EquipmentSystem.MAX_INVENTORY - EquipmentSystem.getInventoryCount(equipData))
    for index, entry in ipairs(lootboxData.seeds or {}) do
        if EquipmentQuery.matches(entry.equip, quality, setFilter, detailFilter) then
            if free == 0 then return claimed, true end
            local score = EquipmentPower.genericScore(EquipmentQuery.hydrateCopy(entry.equip))
            if score ~= score or score == math.huge or score == -math.huge then score = 0 end
            candidates[#candidates + 1] = { index = index, equip = entry.equip, score = score }
        end
    end
    table.sort(candidates, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.index < b.index
    end)
    local removed = {}
    for rank = 1, math.min(free, #candidates) do
        local candidate = candidates[rank]
        EquipmentSystem.addToInventory(equipData, candidate.equip)
        claimed[#claimed + 1] = candidate.equip
        removed[#removed + 1] = candidate.index
    end
    -- 原索引只在全部取入后倒序删除，防止高分排序与数组移动造成错领/漏领。
    table.sort(removed, function(a, b) return a > b end)
    for _, index in ipairs(removed) do table.remove(lootboxData.seeds, index) end
    return claimed, #candidates > free
end

--- 整理转存不进入遗匣回收；锁定保护同时覆盖单件右键与一键回收。
function LootBoxSystem.canDecompose(entry)
    return entry ~= nil and entry.equip ~= nil
        and not entry.equip.locked and entry.source ~= "curation"
end

local function decomposeValue(entry)
    if not LootBoxSystem.canDecompose(entry) then return 0, 0 end
    local equip = entry.equip
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

function LootBoxSystem.decomposeAll(lootboxData, quality, setFilter, detailFilter)
    local essence, pieces = 0, 0
    for index = #lootboxData.seeds, 1, -1 do
        local entry = lootboxData.seeds[index]
        if EquipmentQuery.matches(entry.equip, quality, setFilter, detailFilter) then
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
