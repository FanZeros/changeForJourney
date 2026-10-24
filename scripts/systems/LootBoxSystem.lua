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

-- ======================== 大批聚合条目 ========================
-- 扫荡/挂机的大批量掉落不再逐件生成并落盘实体装备，改为按品质×等级聚合成
-- {batch=true, quality, level, count, source, stageId}；领取或分解时才按原规则
-- 逐件生成。保存体积与准备成本不再随总件数线性膨胀。

--- 聚合条目最多保留的实体件数；超过后不再逐件预生成给展示层。
LootBoxSystem.BATCH_PREVIEW_LIMIT = 50

---@param entry table
---@return boolean
function LootBoxSystem.isBatch(entry)
    return type(entry) == "table" and entry.batch == true and entry.equip == nil
end

--- 写入或累加一个聚合条目；返回该条目。
---@param lootboxData table
---@param quality number
---@param level number
---@param count number
---@param source string|nil
---@return table
function LootBoxSystem.addBatch(lootboxData, quality, level, count, source)
    lootboxData.seeds = lootboxData.seeds or {}
    local q = math.max(1, math.floor(tonumber(quality) or 1))
    local lv = math.max(1, math.floor(tonumber(level) or 1))
    local amount = math.max(0, math.floor(tonumber(count) or 0))
    local seeds = lootboxData.seeds
    for index = #seeds, 1, -1 do
        local entry = seeds[index]
        if LootBoxSystem.isBatch(entry) and entry.quality == q and entry.level == lv
            and (entry.source or "idle") == (source or "idle") then
            entry.count = (entry.count or 0) + amount
            return entry
        end
    end
    local entry = { batch = true, quality = q, level = lv, count = amount, source = source or "idle" }
    seeds[#seeds + 1] = entry
    return entry
end

--- 兼容旧档分组；完整装备与聚合条目始终独立，不重骰、不展开。
function LootBoxSystem.consolidateSeeds(lootboxData)
    if not lootboxData or not lootboxData.seeds then return end
    local merged, byKey = {}, {}
    for _, entry in ipairs(lootboxData.seeds) do
        if entry.equip or LootBoxSystem.isBatch(entry) then
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

--- 从聚合条目按需生成下一件确定装备；不修改条目本身。
--- 领取/分解是玩家明确操作，仍按原所属来源抽取完整随机装备。
---@param entry table 聚合条目
---@param legacySecondary boolean|nil
---@return table|nil
function LootBoxSystem.materialize(entry, legacySecondary)
    if not LootBoxSystem.isBatch(entry) then return nil end
    local level = entry.level
    if LootBoxSystem.levelCap > 0 then level = math.min(level, LootBoxSystem.levelCap) end
    local options = legacySecondary and { legacySecondary = true } or nil
    return EquipmentSystem.generateRandom(level, entry.quality, options)
end

--- 释放聚合条目中的一件（只减数量，不重排数组）。
---@param lootboxData table
---@param index number
---@return boolean ok
function LootBoxSystem.takeBatchOne(lootboxData, index)
    local entry = lootboxData.seeds and lootboxData.seeds[index]
    if not LootBoxSystem.isBatch(entry) or (entry.count or 0) <= 0 then return false end
    entry.count = entry.count - 1
    if entry.count <= 0 then table.remove(lootboxData.seeds, index) end
    return true
end

--- 旧种子转换为确定装备；失败保留剩余数量，不丢奖励。
--- 聚合条目是新的保存形态，原样保留到领取/分解时再逐件生成。
function LootBoxSystem.revealLegacy(lootboxData)
    local revealed, converted = {}, 0
    for _, entry in ipairs(lootboxData.seeds or {}) do
        if entry.equip or LootBoxSystem.isBatch(entry) then
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

--- 单个无yield交付批次的局部计数器；默认调用仍逐次扫描/记录日志。
--- 不跨请求缓存、不承担并发锁；库存引用或nextSeq异常变化时安全回退重扫。
function LootBoxSystem.createDeliveryContext(equipData, options)
    return { owner = equipData, inventory = equipData.inventory,
        count = EquipmentSystem.getInventoryCount(equipData), nextSeq = equipData.nextSeq,
        summaryLogs = options and options.summaryLogs == true, overflow = 0 }
end

---@return string destination
function LootBoxSystem.deliverEquipment(lootboxData, equipData, equip, context)
    local batch = context and context.owner == equipData and context or nil
    if batch and (batch.inventory ~= equipData.inventory or batch.nextSeq ~= equipData.nextSeq) then
        batch.inventory, batch.nextSeq = equipData.inventory, equipData.nextSeq
        batch.count = EquipmentSystem.getInventoryCount(equipData)
    end
    local full = batch and batch.count >= EquipmentSystem.MAX_INVENTORY
        or not batch and EquipmentSystem.isInventoryFull(equipData)
    if not full then
        -- 脏nextSeq可能覆盖已有键；与原addToInventory保持一致，不虚增计数。
        local existed = equipData.inventory[tostring(equipData.nextSeq or 1)] ~= nil
        EquipmentSystem.addToInventory(equipData, equip)
        if batch then
            if not existed then batch.count = batch.count + 1 end
            batch.nextSeq = equipData.nextSeq
        end
        return "inventory"
    end
    LootBoxSystem.addEquipment(lootboxData, equip)
    if batch then batch.overflow = batch.overflow + 1 end
    if not (batch and batch.summaryLogs) then
        print("[LootBoxSystem] 背包溢出已入遗匣: " .. tostring(equip.templateId)
            .. " q=" .. tostring(equip.quality) .. " lv=" .. tostring(equip.level))
    end
    return "lootbox"
end

--- 只取出已有内容；未迁移条目不能在领取时偷偷随机。
--- 聚合条目在玩家领取时生成一件，与逐件入匣同口径。
function LootBoxSystem.claimOne(lootboxData, index)
    local entry = lootboxData.seeds[index]
    if not entry then return nil end
    if LootBoxSystem.isBatch(entry) then
        local equip = LootBoxSystem.materialize(entry)
        if not equip then return nil end
        if (entry.count or 0) <= 1 then table.remove(lootboxData.seeds, index)
        else entry.count = entry.count - 1 end
        return equip
    end
    if not entry.equip then return nil end
    table.remove(lootboxData.seeds, index)
    return entry.equip
end

function LootBoxSystem.claimGroup(lootboxData, index, equipData)
    local entry = lootboxData.seeds[index]
    if not entry then return {}, false end
    if EquipmentSystem.isInventoryFull(equipData) then return {}, true end
    if LootBoxSystem.isBatch(entry) then
        local equip = LootBoxSystem.materialize(entry)
        if not equip then return {}, false end
        EquipmentSystem.addToInventory(equipData, equip)
        if (entry.count or 0) <= 1 then table.remove(lootboxData.seeds, index)
        else entry.count = entry.count - 1 end
        return { equip }, false
    end
    if not entry.equip then return {}, false end
    EquipmentSystem.addToInventory(equipData, entry.equip)
    table.remove(lootboxData.seeds, index)
    return { entry.equip }, false
end

--- 可选品质+套装/部位类型 AND 过滤；领取优先级固定为通用评分降序。
--- 只水合副本，不因领取顺序改写原遗匣数组或装备；同分保持原条目顺序。
--- 聚合条目按品质从高到低物化，且最多物化到空位数，避免一键领取再生成整批装备。
function LootBoxSystem.claimAll(lootboxData, equipData, quality, setFilter, detailFilter)
    local claimed, candidates = {}, {}
    local free = math.max(0, EquipmentSystem.MAX_INVENTORY - EquipmentSystem.getInventoryCount(equipData))
    local batches = {}
    for index, entry in ipairs(lootboxData.seeds or {}) do
        if LootBoxSystem.isBatch(entry) then
            -- 聚合条目不含部位/类型/套装，带这些筛选时不参与匹配。
            local passQuality
            if type(quality) == "table" then
                passQuality = next(quality) == nil or quality[entry.quality] == true
            else
                passQuality = not quality or quality == 0 or quality == entry.quality
            end
            local noDetail = not detailFilter
                or (detailFilter.slotFilter == nil and detailFilter.typeFilter == nil)
            local noSet = setFilter == nil or (type(setFilter) == "table" and next(setFilter) == nil)
            if passQuality and noDetail and noSet then
                batches[#batches + 1] = { index = index, entry = entry }
            end
        elseif EquipmentQuery.matches(entry.equip, quality, setFilter, detailFilter) then
            local score = EquipmentPower.genericScore(EquipmentQuery.hydrateCopy(entry.equip))
            if score ~= score or score == math.huge or score == -math.huge then score = 0 end
            candidates[#candidates + 1] = { index = index, equip = entry.equip, score = score }
        end
    end
    -- 品质降序、同品质按原索引稳定；只在仍需补足空位时物化。
    table.sort(batches, function(a, b)
        local qa, qb = a.entry.quality or 1, b.entry.quality or 1
        if qa ~= qb then return qa > qb end
        return a.index < b.index
    end)
    local budget = free
    local truncatedBatch = false
    for _, batch in ipairs(batches) do
        if budget <= 0 then
            if (batch.entry.count or 0) > 0 then truncatedBatch = true end
        else
            local entry = batch.entry
            local remaining = math.min(entry.count or 0, budget)
            if (entry.count or 0) > remaining then truncatedBatch = true end
            for _ = 1, remaining do
                local equip = LootBoxSystem.materialize(entry)
                if not equip then break end
                candidates[#candidates + 1] = { index = batch.index, equip = equip,
                    score = EquipmentPower.genericScore(equip) }
                budget = budget - 1
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.index < b.index
    end)
    local removed = {}
    local taken = {}
    for rank = 1, math.min(free, #candidates) do
        local candidate = candidates[rank]
        EquipmentSystem.addToInventory(equipData, candidate.equip)
        claimed[#claimed + 1] = candidate.equip
        if not taken[candidate.index] then
            taken[candidate.index] = 0
            removed[#removed + 1] = candidate.index
        end
        taken[candidate.index] = taken[candidate.index] + 1
    end
    -- 原索引只在全部取入后倒序删除，防止高分排序与数组移动造成错领/漏领。
    table.sort(removed, function(a, b) return a > b end)
    for _, index in ipairs(removed) do
        local entry = lootboxData.seeds[index]
        if LootBoxSystem.isBatch(entry) then
            entry.count = (entry.count or 0) - taken[index]
            if entry.count <= 0 then table.remove(lootboxData.seeds, index) end
        else
            table.remove(lootboxData.seeds, index)
        end
    end
    return claimed, #candidates > free or truncatedBatch
end

--- 整理转存不进入遗匣回收；锁定保护同时覆盖单件右键与一键回收。
function LootBoxSystem.canDecompose(entry)
    if LootBoxSystem.isBatch(entry) then return entry.source ~= "curation" end
    return entry ~= nil and entry.equip ~= nil
        and not entry.equip.locked and entry.source ~= "curation"
end

local function decomposeValue(entry)
    if not LootBoxSystem.canDecompose(entry) then return 0, 0 end
    -- 聚合条目没有锁定/整理保护，可直接按品质与等级计算，无需物化。
    if LootBoxSystem.isBatch(entry) then
        local cost = BlacksmithConfig.QUALITY_COST[entry.quality]
        if not cost then return 0, 0 end
        local pieces = math.max(0, entry.count or 0)
        if pieces == 0 then return 0, 0 end
        local each = math.floor(cost.decBase * (1 + (entry.level or 1) * cost.decScale))
        return each * pieces, pieces
    end
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
        local matches
        if LootBoxSystem.isBatch(entry) then
            -- 聚合条目没有部位/类型/套装信息；带这些筛选时保守跳过。
            local passQuality
            if type(quality) == "table" then
                passQuality = next(quality) == nil or quality[entry.quality] == true
            else
                passQuality = not quality or quality == 0 or quality == entry.quality
            end
            local noDetail = not detailFilter
                or (detailFilter.slotFilter == nil and detailFilter.typeFilter == nil)
            local noSet = setFilter == nil or (type(setFilter) == "table" and next(setFilter) == nil)
            matches = passQuality and noDetail and noSet
        else
            matches = EquipmentQuery.matches(entry.equip, quality, setFilter, detailFilter)
        end
        if matches then
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
            count = entry.count or 1, equip = entry.equip, batch = entry.batch,
            source = entry.source, sourceIndex = index,
        }
    end
    return summary
end

return LootBoxSystem
