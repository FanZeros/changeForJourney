-- 大批奖励只读整理：允许私有准备跨帧，完成后一次交给弹窗，不复制装备实例。
local M = {}
local ResourceDefs = require("config.ResourceDefs")
local prepared = setmetatable({}, { __mode = "k" })
local CHECKPOINT_STEPS = 256
local MAX_EXACT_AMOUNT = 9007199254740991

-- 按协议类型和完整标量元数据合并；同名不等于同物品，嵌套实例不参与叠加。
local function stackKey(item)
    local amount = item.amount
    if not (ResourceDefs.DEFS[item.type] or item.type == "shard")
        or item.type == "equip" or item.type == "hero" or item.type == "artifact"
        or type(amount) ~= "number" or amount ~= amount or amount <= 0
        or amount > MAX_EXACT_AMOUNT or amount ~= math.floor(amount) or getmetatable(item) ~= nil then return nil end
    if item.type == "shard" then
        local heroId = tonumber(item.heroId)
        if not heroId or heroId <= 0 or heroId == math.huge or heroId ~= math.floor(heroId) then return nil end
    end
    local keys = {}
    for key, value in pairs(item) do
        if key ~= "amount" then
            local kind = type(value)
            if type(key) ~= "string" or (kind ~= "string" and kind ~= "number" and kind ~= "boolean")
                or (kind == "number" and (value ~= value or math.abs(value) == math.huge)) then return nil end
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local value = item[key]
        local text = type(value) == "number" and math.type(value) ~= "integer"
            and string.format("%.17g", value) or tostring(value)
        parts[#parts + 1] = #key .. ":" .. key .. type(value) .. #text .. ":" .. text
    end
    return table.concat(parts, "|")
end

local function byQuality(a, b)
    return (a.quality or 1) > (b.quality or 1)
end

local function byEquipment(a, b)
    local qa, qb = a.quality or 1, b.quality or 1
    if qa ~= qb then return qa > qb end
    return (a.level or 1) > (b.level or 1)
end

-- 稳定归并不改变相同品质/等级的原序；每段只有有限比较/复制再让出。
local function sort(items, less, checkpoint, progress)
    local n = #items
    local source, target, width = items, {}, 1
    local steps = 0
    local function tick()
        steps = steps + 1
        if steps >= CHECKPOINT_STEPS then
            steps = 0
            checkpoint("presentation", progress, progress)
        end
    end
    while width < n do
        for first = 1, n, width * 2 do
            local middle, last = math.min(first + width - 1, n), math.min(first + width * 2 - 1, n)
            local left, right = first, middle + 1
            for index = first, last do
                if left <= middle and (right > last or not less(source[right], source[left])) then
                    target[index] = source[left]
                    left = left + 1
                else
                    target[index] = source[right]
                    right = right + 1
                end
                tick()
            end
        end
        source, target = target, source
        width = width * 2
    end
    return source
end

---@param rewards table[]
---@param checkpoint fun(phase: string, completed: number, total: number)
---@param mergeResources boolean|nil false用于有逐项点击身份的列表
---@return table
function M.prepare(rewards, checkpoint, mergeResources)
    ---@type table<number, table[]>
    local groups = { {}, {}, {}, {} }
    ---@type table<string, table>
    local stacks = {}
    local count = #rewards
    for index, item in ipairs(rewards) do
        local group = item.type == "hero" and 2 or item.type == "equip" and 3
            or item.type == "artifact" and 4 or 1
        local bucket = groups[group]
        local key = group == 1 and mergeResources ~= false and stackKey(item) or nil
        local existing = key and stacks[key]
        if existing and existing.amount <= MAX_EXACT_AMOUNT - item.amount then
            existing.amount = existing.amount + item.amount
        elseif key then
            -- 配置奖励/回执可能共享同一个table，绝不能在原对象上累加数量。
            local display = {}
            for field, value in pairs(item) do display[field] = value end
            bucket[#bucket + 1] = display
            stacks[key] = display
        else
            bucket[#bucket + 1] = item
        end
        if index % CHECKPOINT_STEPS == 0 then checkpoint("presentation", index, count) end
    end
    groups[2] = sort(groups[2], byQuality, checkpoint, count)
    groups[3] = sort(groups[3], byEquipment, checkpoint, count)
    groups[4] = sort(groups[4], byQuality, checkpoint, count)
    local items = {}
    for groupIndex = 1, 4 do
        local group = groups[groupIndex]
        for _, item in ipairs(group) do
            items[#items + 1] = item
            if #items % CHECKPOINT_STEPS == 0 then checkpoint("presentation", #items, count) end
        end
    end
    checkpoint("presentation", count, count)
    local token = {}
    prepared[token] = { items = items, rewards = rewards, count = count, mergeResources = mergeResources ~= false }
    return token
end

---@param token table|nil
---@param rewards table[]
---@param mergeResources boolean|nil
---@return table[]|nil
function M.take(token, rewards, mergeResources)
    local value = token and prepared[token]
    if not value or value.rewards ~= rewards or value.count ~= #rewards
        or value.mergeResources ~= (mergeResources ~= false) then return nil end
    prepared[token] = nil
    return value.items
end

return M
