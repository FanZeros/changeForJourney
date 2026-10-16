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
    local function groupFor(key, view)
        if not pools[key] then
            pools[key] = { key = key, slot = view.slot, type = view.type, grip = view.grip,
                inventory = 0, protected = 0, candidates = {}, removable = {}, cursor = 1 }
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
        local ok, view, score, setId = pcall(function()
            local hydrated = Query.hydrateCopy(equip)
            return hydrated, Power.genericScore(hydrated), Query.getSetId(hydrated)
        end)
        if not ok or type(view) ~= "table" or not SLOTS[view.slot]
            or type(view.type) ~= "string" or (view.grip ~= nil and type(view.grip) ~= "string")
            or not finite(score) then
            protect(row, "invalid")
            return row
        end
        if setId and setId ~= "none" then protect(row, "set") end
        if corrupted(view) then protect(row, "corruption") end
        row.group, row.score = groupKey(view.slot, view.type, view.grip), score
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
    local groups = {}
    for _, pool in pairs(pools) do
        groups[#groups + 1] = pool
        table.sort(pool.candidates, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            return a.index < b.index
        end)
        table.sort(pool.removable, function(a, b)
            if a.score ~= b.score then return a.score < b.score end
            -- 同分优先留较早的仓库序号。
            return keyLess(b.key, a.key)
        end)
    end
    table.sort(groups, function(a, b) return a.key < b.key end)
    local function take(pool, reason)
        local row = pool.candidates[pool.cursor]
        if not row then return nil end
        pool.cursor = pool.cursor + 1
        plan.moveIn[#plan.moveIn + 1] = { index = row.index, group = row.group, score = row.score, reason = reason }
        return row
    end
    -- 先规划空位而非先搬空：低占用组优先，每次取本组最高分；组名稳定打平。
    local free = capacity - #keys
    while free > 0 do
        local selected = nil ---@type table|nil
        for _, pool in ipairs(groups) do
            if pool.candidates[pool.cursor]
                and (not selected or pool.inventory < selected.inventory) then selected = pool end
        end
        if not selected then break end
        take(selected, "fill")
        selected.inventory = selected.inventory + 1
        free = free - 1
    end
    -- 每组保留既有仓位配额；严格高分才能替换未保护原件，跨组不以分数挤占。
    for _, pool in ipairs(groups) do
        for _, old in ipairs(pool.removable) do
            local candidate = pool.candidates[pool.cursor]
            if not candidate or candidate.score <= old.score then break end
            take(pool, "upgrade")
            plan.moveOut[#plan.moveOut + 1] = {
                key = old.key, seq = old.seq, group = old.group, score = old.score, reason = "upgrade",
            }
        end
        plan.groups[#plan.groups + 1] = { key = pool.key, slot = pool.slot, type = pool.type,
            grip = pool.grip, inventory = pool.inventory, protected = pool.protected,
            remaining = #pool.candidates - pool.cursor + 1 }
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
