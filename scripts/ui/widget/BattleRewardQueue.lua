-- 战斗奖励的展示队列；奖励已经结算，此处只复制、合并展示数据，不修改玩家物品。
local BattleRewardQueue = {}
BattleRewardQueue.__index = BattleRewardQueue

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[key] = copy(item, seen) end
    return result
end

-- 只有数量不同才允许叠加；品质、等级、去向和其它元数据必须完全相同。
local function sameStack(a, b)
    for key, value in pairs(a) do
        if key ~= "amount" and b[key] ~= value then return false end
    end
    for key, value in pairs(b) do
        if key ~= "amount" and a[key] ~= value then return false end
    end
    return true
end

function BattleRewardQueue.new(resourceDefs)
    local self = setmetatable({}, BattleRewardQueue)
    self:init(resourceDefs)
    return self
end

function BattleRewardQueue:init(resourceDefs)
    self.entries = {}
    self.resourceDefs = resourceDefs or {}
end

function BattleRewardQueue:hasPending()
    return #self.entries > 0
end

function BattleRewardQueue:clear()
    self.entries = {}
end

function BattleRewardQueue:prepend(entry)
    -- 主动领奖打断的展示快照是独立边界，不与之后的奖励重排或重播。
    table.insert(self.entries, 1, entry)
end

function BattleRewardQueue:pop()
    return table.remove(self.entries, 1)
end

function BattleRewardQueue:appendItems(target, items)
    for _, item in ipairs(items) do
        local stackable = item.type ~= "equip" and item.type ~= "hero" and item.type ~= "artifact"
            and (self.resourceDefs[item.type] ~= nil or item.type == "seed" or item.type == "shard")
            and type(item.amount) == "number" and item.amount > 0
        local merged = false
        if stackable then
            for _, existing in ipairs(target) do
                if type(existing.amount) == "number" and existing.amount > 0 and sameStack(existing, item) then
                    existing.amount = existing.amount + item.amount
                    merged = true
                    break
                end
            end
        end
        if not merged then target[#target + 1] = copy(item) end
    end
end

function BattleRewardQueue:push(title, rewards, opts)
    opts = copy(opts or {})
    local callback = opts.onClose
    local entry = self.entries[#self.entries]
    local compatible = entry and not entry.state and not entry.opts.onItemClick and not opts.onItemClick
        and entry.opts.row == opts.row and entry.opts.panel == opts.panel
        and (entry.opts.subtitle or "") == (opts.subtitle or "")
    if not compatible then
        entry = { title = title, rewards = {}, opts = opts, callbacks = {}, count = 0 }
        self.entries[#self.entries + 1] = entry
        entry.opts.onClose = function()
            -- 每个原始请求的关闭回调恰一次；一个回调失败不能吞掉其它请求的完成通知。
            local callbacks = entry.callbacks
            entry.callbacks = {}
            for _, onClose in ipairs(callbacks) do
                local ok, why = pcall(onClose)
                if not ok then print("[BattleRewardQueue] 关闭回调失败: " .. tostring(why)) end
            end
        end
    end
    if callback then entry.callbacks[#entry.callbacks + 1] = callback end
    entry.count = entry.count + 1
    if entry.title ~= title then entry.title = "战斗掉落" end
    entry.opts.cascade = entry.opts.cascade == true or opts.cascade == true
    if opts.onItemClick then
        for _, item in ipairs(rewards) do entry.rewards[#entry.rewards + 1] = copy(item) end
    else
        self:appendItems(entry.rewards, rewards)
    end
    print("[BattleRewardQueue] 等待批次=" .. #self.entries .. " 合并请求=" .. entry.count
        .. " 展示物品=" .. #entry.rewards)
end

return BattleRewardQueue
