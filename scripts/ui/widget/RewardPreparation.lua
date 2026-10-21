-- 大批奖励只读整理：允许私有准备跨帧，完成后一次交给弹窗，不复制装备实例。
local M = {}
local prepared = setmetatable({}, { __mode = "k" })
local CHECKPOINT_STEPS = 256

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
---@return table
function M.prepare(rewards, checkpoint)
    ---@type table<number, table[]>
    local groups = { {}, {}, {}, {} }
    local count = #rewards
    for index, item in ipairs(rewards) do
        local group = item.type == "hero" and 2 or item.type == "equip" and 3
            or item.type == "artifact" and 4 or 1
        local bucket = groups[group]
        bucket[#bucket + 1] = item
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
    prepared[token] = { items = items, rewards = rewards, count = count }
    return token
end

---@param token table|nil
---@param rewards table[]
---@return table[]|nil
function M.take(token, rewards)
    local value = token and prepared[token]
    if not value or value.rewards ~= rewards or value.count ~= #rewards then return nil end
    prepared[token] = nil
    return value.items
end

return M
