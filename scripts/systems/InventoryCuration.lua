-- 仓库与遗匣联合优选：纯只读规划，不消费随机、不执行领取/分解。
local Eq = require("systems.EquipmentSystem")
local Power = require("systems.EquipmentPower")
local Query = require("systems.EquipmentQuery")
local EC = require("config.EquipmentConfig")
local Affixes = require("config.AffixConfig")

local M = {}
local SLOTS = {}
for _, slot in ipairs(EC.SLOTS) do SLOTS[slot] = true end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

--- 序号比较统一数字/字符串形式；不把未知字符串当作可分配序号。
---@param value any
---@return string|nil
function M.sequence(value)
    local number = tonumber(value)
    if not finite(number) or number < 1 or number % 1 ~= 0 or number >= 9007199254740991 then return nil end
    return string.format("%.0f", number)
end

local function keyLess(a, b)
    local an, bn = tonumber(a), tonumber(b)
    if an and bn and an ~= bn then return an < bn end
    if tostring(a) ~= tostring(b) then return tostring(a) < tostring(b) end
    return type(a) < type(b)
end

local function groupKey(slot, kind, grip)
    local parts = {}
    for _, value in ipairs({ slot, kind, grip or "" }) do
        parts[#parts + 1] = tostring(#value) .. ":" .. value
    end
    return table.concat(parts, "|")
end

-- 培养底材只计基础主/副属性：沿用属性价值权重，但不带随机词条或任何养成倍率。
-- baseStats 已由只读水合确定性还原，包含模板/等级/品质/固定副抽取，不重骰。
local function baseScore(view, readyScore)
    local stats = view.baseStats
    -- 遗匣里的腐化保护件仍可能参与成品候选；不能借腐化倍率占用底材专额。
    if view.corruptBaseMult ~= nil and view.corruptBaseMult ~= 1 then
        local quality = EC.QUALITY[view.quality]
        stats = Eq.recalcBaseStats(view.templateId, view.level, quality and quality.baseStrength or 1,
            view.secondaryRoll)
    elseif type(view.affixes) == "table" and next(view.affixes) == nil
        and view.ascendLevel == 0 and view.enhanceLevel == 0 and view.level <= 50 then
        -- 无词条/升阶且未进入等级补偿时，两次评分的实际输入等价。
        -- 投影通过template回退slot/grip；历史自带的非模板字段不走复用。
        local tpl = EC.ITEMS[view.templateId]
        if tpl and view.slot == tpl.slot and view.grip == tpl.grip then return readyScore end
    end
    return Power.genericScore({ templateId = view.templateId, baseStats = stats, affixes = {} })
end

local function stableLess(a, b)
    if a.source ~= b.source then return a.source == "inventory" end
    if a.source == "inventory" then return keyLess(a.key, b.key) end
    return a.index < b.index
end

local function baseLess(a, b)
    if a.baseScore ~= b.baseScore then return a.baseScore > b.baseScore end
    if a.quality ~= b.quality then return a.quality > b.quality end
    if a.level ~= b.level then return a.level > b.level end
    -- 底材通道不以随机词条决胜，完全相同的底材先保原仓。
    return stableLess(a, b)
end

local function readyLess(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return baseLess(a, b)
end

-- 双通道只瓜分本组非原位保护名额，不改变部位/type/grip配额。
-- N=1只选成品；N>=2给底材约1/4（向下取整、至少1），保证成品Top仍占多数。
-- 两份Top独立选取，重叠按同一实例去重，空额全部回流成品，不额外扩张底材份额。
local function selectRows(ranked, count)
    table.sort(ranked, readyLess)
    local reserved = count >= 2 and math.max(1, math.floor(count / 4)) or 0
    local selected, channels = {}, {}
    for index = 1, count - reserved do
        local row = ranked[index]
        selected[#selected + 1], channels[row] = row, "ready"
    end
    if reserved > 0 then
        local bases = {}
        for _, row in ipairs(ranked) do bases[#bases + 1] = row end
        table.sort(bases, baseLess)
        for index = 1, reserved do
            local row = bases[index]
            if not channels[row] then
                selected[#selected + 1], channels[row] = row, "base"
            end
        end
    end
    for _, row in ipairs(ranked) do
        if #selected >= count then break end
        if not channels[row] then selected[#selected + 1], channels[row] = row, "ready" end
    end
    -- 搬入/分配新seq仍按成品分稳定排序，不因底材遍历顺序改变同组清单顺序。
    table.sort(selected, readyLess)
    return selected, channels
end

local function changedNumber(value, base)
    if value == nil then return false end
    local number = tonumber(value)
    -- 不合法的历史投入字段也保守保护，不借水合清掉后挪走。
    return not finite(number) or number ~= base
end

local function invested(equip)
    if changedNumber(equip.ascendLevel, 0) or changedNumber(equip.enhanceLevel, 0)
        or changedNumber(equip.refineCount, 0) or changedNumber(equip.ascBonus, 0)
        or changedNumber(equip.affixMult, 1) then return true end
    for _, affix in pairs(type(equip.affixes) == "table" and equip.affixes or {}) do
        if type(affix) == "table" and changedNumber(affix.ascBonus, 0) then return true end
    end
    return false
end

local function corrupted(equip)
    if changedNumber(equip.corruptCount, 0) or changedNumber(equip.corruptBaseMult, 1)
        or equip.corruptRevert ~= nil or equip.corruptOriginalAffixes ~= nil
        or equip.corruptOriginalBaseMult ~= nil then return true end
    for _, affix in pairs(type(equip.affixes) == "table" and equip.affixes or {}) do
        if type(affix) == "table" and Affixes.isCorruptAffix(affix) then return true end
    end
    return false
end

local function sortedKeys(value)
    local keys = {}
    for key in pairs(value) do
        if type(key) ~= "string" and type(key) ~= "number" then return nil end
        keys[#keys + 1] = key
    end
    table.sort(keys, keyLess)
    return keys
end

-- 下限是原位保护的绝对占用，上限是实际供应；固定数组顺序打平。
-- 不均分“扣掉保护后的新增量”：保护多的组等其他组水位追平才继续增加。
local function waterfill(buckets, budget)
    local used = 0
    for _, bucket in ipairs(buckets) do
        bucket.target = bucket.lower
        used = used + bucket.lower
    end
    while used < budget do
        local selected = nil ---@type table|nil
        for _, bucket in ipairs(buckets) do
            if bucket.target < bucket.upper and (not selected or bucket.target < selected.target) then
                selected = bucket
            end
        end
        if not selected then break end
        selected.target = selected.target + 1
        used = used + 1
    end
end

--- options.hasPendingRefine(seq) 是规则层只读闭包，不是客户端参数。
--- moveIn/moveOut 仅携原数据索引；原装备及种子不水合、不重排、不改字段。
---@param equipment table
---@param lootbox table
---@param options table|nil
---@return table|nil, string|nil
function M.plan(equipment, lootbox, options)
    if type(equipment) ~= "table" or type(equipment.inventory) ~= "table"
        or type(lootbox) ~= "table" or type(lootbox.seeds) ~= "table"
        or (equipment.equipped ~= nil and type(equipment.equipped) ~= "table") then
        return nil, "整理数据不可用"
    end
    local keys = sortedKeys(equipment.inventory)
    if not keys then return nil, "仓库序列号异常" end
    local seeds = lootbox.seeds
    -- 遗匣必须是稠密数组，不能通过ipairs丢弃洞后的完整装备。
    local seedCount = 0
    for key in pairs(seeds) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return nil, "遗匣条目异常" end
        seedCount = seedCount + 1
    end
    if seedCount ~= #seeds then return nil, "遗匣条目不连续" end
    local capacity = Eq.MAX_INVENTORY
    if #keys > capacity then return nil, "仓库数量超过容量，未移动任何装备" end
    local plan = {
        capacity = capacity, moveIn = {}, moveOut = {}, groups = {}, reasons = {},
        protected = { inventory = 0, lootbox = 0, reasons = {} },
        counts = { inventoryBefore = #keys, inventoryAfter = #keys,
            lootboxBefore = #seeds, lootboxAfter = #seeds, legacyPending = 0 },
    }
    local occupied, canonical, objects = {}, {}, {}
    for _, slots in pairs(equipment.equipped or {}) do
        if type(slots) ~= "table" then return nil, "英雄装备槽数据异常" end
        for _, seq in pairs(slots) do
            local id = M.sequence(seq)
            if id then occupied[id] = true end
        end
    end
    for _, key in ipairs(keys) do
        local id = M.sequence(key)
        if id then
            if canonical[id] then return nil, "仓库存在重复序列号" end
            canonical[id] = true
        end
    end
    local pools = {}
    local unclassified = 0 -- 无有效分组的保护库存也占仓位，不能拿它的容量再分配。
    local function groupFor(key, view)
        if not pools[key] then
            pools[key] = { key = key, slot = view.slot, type = view.type, grip = view.grip,
                inventory = 0, protected = 0, candidates = {}, removable = {} }
        end
        return pools[key]
    end
    local function protect(row, reason)
        if row.reasons[reason] then return end
        row.reasons[reason] = true
        plan.protected.reasons[reason] = (plan.protected.reasons[reason] or 0) + 1
    end
    local function inspect(equip, source, key, index, seed)
        local row = { key = key, index = index, seq = M.sequence(key), reasons = {}, source = source }
        if type(equip) ~= "table" then
            protect(row, "invalid")
            return row
        end
        if objects[equip] then return nil end
        objects[equip] = true
        if equip.locked then protect(row, "locked") end
        if invested(equip) then protect(row, "investment") end
        if corrupted(equip) then protect(row, "corruption") end
        local equipId, originalId = M.sequence(equip.seq), M.sequence(seed and seed.originalSeq)
        if source == "inventory" and equip.seq ~= nil and equipId ~= row.seq then protect(row, "invalid") end
        -- 槽表、对象seq和整理审计号均查，脏档别名不允许漏掉私有待洗练/悬空穿戴。
        local function protectSequence(id)
            if not id then return end
            if occupied[id] then protect(row, "equipped") end
            if options and options.hasPendingRefine and options.hasPendingRefine(id) then
                protect(row, "pendingRefine")
            end
        end
        protectSequence(row.seq)
        protectSequence(equipId)
        protectSequence(originalId)
        if source == "inventory" and not row.seq then protect(row, "invalid") end
        local tpl = EC.ITEMS[equip.templateId] or EC.ITEMS[tostring(equip.templateId)]
        if not tpl then protect(row, "invalid"); return row end
        local ok, view, score, setId, foundation = pcall(function()
            local hydrated = Query.hydrateCopy(equip)
            local readyScore = Power.genericScore(hydrated)
            return hydrated, readyScore, Query.getSetId(hydrated), baseScore(hydrated, readyScore)
        end)
        if not ok or type(view) ~= "table" or not SLOTS[view.slot]
            or type(view.type) ~= "string" or (view.grip ~= nil and type(view.grip) ~= "string")
            or not finite(score) or not finite(foundation) then
            protect(row, "invalid")
            return row
        end
        if setId and setId ~= "none" then protect(row, "set") end
        if corrupted(view) then protect(row, "corruption") end
        row.group, row.score = groupKey(view.slot, view.type, view.grip), score
        row.baseScore = foundation
        row.quality = finite(tonumber(view.quality)) and tonumber(view.quality) or 1
        row.level = finite(tonumber(view.level)) and tonumber(view.level) or 1
        row.pool = groupFor(row.group, view)
        return row
    end
    local function record(row)
        if next(row.reasons) then
            if row.source == "inventory" then
                plan.protected.inventory = plan.protected.inventory + 1
            else
                plan.protected.lootbox = plan.protected.lootbox + 1
            end
            if row.pool and row.source == "inventory" then row.pool.protected = row.pool.protected + 1 end
        end
    end
    for _, key in ipairs(keys) do
        local row = inspect(equipment.inventory[key], "inventory", key)
        if not row then return nil, "装备对象重复，未移动任何装备" end
        record(row)
        if row.pool then
            row.pool.inventory = row.pool.inventory + 1
            if not next(row.reasons) then row.pool.removable[#row.pool.removable + 1] = row end
        else
            unclassified = unclassified + 1
        end
    end
    for index, seed in ipairs(seeds) do
        if type(seed) ~= "table" then return nil, "遗匣条目异常" end
        if seed.equip == nil then
            plan.counts.legacyPending = plan.counts.legacyPending + 1
        else
            local row = inspect(seed.equip, "lootbox", nil, index, seed)
            if not row then return nil, "装备对象重复，未移动任何装备" end
            if seed.count ~= nil and tonumber(seed.count) ~= 1 then protect(row, "invalid") end
            record(row)
            -- 锁定/投入/套装候选可进入仓库；悬空穿戴/待洗练保持原处避免重挂私有状态。
            if row.pool and not row.reasons.invalid and not row.reasons.pendingRefine and not row.reasons.equipped then
                row.pool.candidates[#row.pool.candidates + 1] = row
            end
        end
    end
    local groups, slotBuckets, bySlot = {}, {}, {}
    for _, slot in ipairs(EC.SLOTS) do
        local bucket = { slot = slot, lower = 0, upper = 0, groups = {} }
        slotBuckets[#slotBuckets + 1], bySlot[slot] = bucket, bucket
    end
    for _, pool in pairs(pools) do groups[#groups + 1] = pool end
    table.sort(groups, function(a, b) return a.key < b.key end)
    for _, pool in ipairs(groups) do
        pool.lower, pool.upper = pool.protected, pool.inventory + #pool.candidates
        local bucket = bySlot[pool.slot]
        bucket.lower = bucket.lower + pool.lower
        bucket.upper = bucket.upper + pool.upper
        bucket.groups[#bucket.groups + 1] = pool
    end
    -- 先平衡六部位，再在部位内平衡slot/type/grip。稀缺组到供应上限后余量回流。
    waterfill(slotBuckets, capacity - unclassified)
    for _, bucket in ipairs(slotBuckets) do waterfill(bucket.groups, bucket.target) end
    for _, pool in ipairs(groups) do
        local ranked = {}
        for _, row in ipairs(pool.removable) do ranked[#ranked + 1] = row end
        for _, row in ipairs(pool.candidates) do ranked[#ranked + 1] = row end
        local count = pool.target - pool.protected
        local chosen, channels = selectRows(ranked, count)
        local keep, selected = {}, 0
        local growth = math.max(0, pool.target - pool.inventory)
        for _, row in ipairs(chosen) do
            if row.source == "inventory" then
                keep[row.key] = true
            else
                selected = selected + 1
                plan.moveIn[#plan.moveIn + 1] = { index = row.index, group = row.group, score = row.score,
                    baseScore = row.baseScore, channel = channels[row],
                    reason = selected <= growth and "fill" or "upgrade" }
            end
        end
        table.sort(pool.removable, function(a, b) return readyLess(b, a) end)
        local shrink = math.max(0, pool.inventory - pool.target)
        local removed = 0
        for _, row in ipairs(pool.removable) do
            if not keep[row.key] then
                removed = removed + 1
                plan.moveOut[#plan.moveOut + 1] = { key = row.key, seq = row.seq, group = row.group,
                    score = row.score, reason = removed <= shrink and "balance" or "upgrade" }
            end
        end
        -- 同组置换可来自成品或底材通道，不再声称每件都严格提高当前成品分。
        plan.groups[#plan.groups + 1] = { key = pool.key, slot = pool.slot, type = pool.type,
            grip = pool.grip, inventory = pool.target, protected = pool.protected,
            remaining = #pool.candidates - selected, target = pool.target }
    end
    plan.moveInCount, plan.moveOutCount = #plan.moveIn, #plan.moveOut
    plan.protectedCount = plan.protected.inventory
    plan.counts.inventoryAfter = #keys + plan.moveInCount - plan.moveOutCount
    plan.counts.lootboxAfter = #seeds - plan.moveInCount + plan.moveOutCount
    plan.counts.moved = plan.moveInCount + plan.moveOutCount
    plan.counts.protected = plan.protectedCount
    plan.reasons = plan.protected.reasons
    plan.changed = plan.counts.moved > 0
    return plan
end

return M
