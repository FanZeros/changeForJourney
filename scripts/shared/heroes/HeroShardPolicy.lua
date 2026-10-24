-- HeroShardPolicy.lua — 英雄碎片容量与溢出转币的纯规划（不改库存、不访问 PDM）
local HeroConfig = require("config.HeroConfig")
local AwakeningConfig = require("config.AwakeningConfig")
local UrGachaConfig = require("config.UrGachaConfig")

local Policy = {}
Policy.MAX_SAFE_INTEGER = 9007199254740991

function Policy.isSafeInteger(value, allowZero)
    return type(value) == "number" and value == value
        and value <= Policy.MAX_SAFE_INTEGER
        and value >= (allowZero and 0 or 1) and value % 1 == 0
end

function Policy.isOwned(entry)
    local level = type(entry) == "table" and tonumber(entry.level) or nil
    return level ~= nil and level > 0 and level < math.huge
end

--- 总库存上限 = 未拥有时的合成费用 + 所有尚未激活的觉醒节点费用。
---@param heroId number
---@param entry table|nil
---@return number|nil capacity
---@return string|nil err
function Policy.capacity(heroId, entry)
    heroId = tonumber(heroId)
    if not Policy.isSafeInteger(heroId) or not HeroConfig.get(heroId) then
        return nil, "无效的英雄 ID"
    end
    if entry ~= nil and type(entry) ~= "table" then return nil, "英雄数据异常" end
    local owned = Policy.isOwned(entry)
    local capacity = owned and 0 or HeroConfig.SHARD_SYNTHESIZE_COST
    local awakening = AwakeningConfig.migrateAwakening(owned and entry.awakening or nil,
        owned and entry._awk3Migrated == true)
    for node = 1, AwakeningConfig.NODE_COUNT do
        if not awakening[node] then capacity = capacity + AwakeningConfig.getShardCost(node) end
    end
    if not Policy.isSafeInteger(capacity, true) then return nil, "碎片容量配置异常" end
    return capacity
end

local function inventory(entry)
    local shards = entry and entry.shards
    if shards == nil then return 0 end
    if not Policy.isSafeInteger(shards, true) then return nil, "碎片库存异常" end
    return shards
end

--- 仍可保留的实际片数；异常数据返回 nil，调用方不得继续扣费。
function Policy.remaining(heroId, entry)
    local capacity, err = Policy.capacity(heroId, entry)
    if capacity == nil then return nil, err end
    local shards, shardErr = inventory(entry)
    if shards == nil then return nil, shardErr end
    return math.max(0, capacity - shards)
end

--- amount 必须是有限正安全整数；内部归并可通过 allowZero=true 规划零新增。
--- overflowShards 包含历史超额，shardGain/amount 仅计本次真正保留的新片。
function Policy.planGrant(heroId, entry, amount, opts)
    opts = opts or {}
    if not Policy.isSafeInteger(amount, opts.allowZero == true) then
        return nil, "碎片数量必须为有限正整数"
    end
    local capacity, err = Policy.capacity(heroId, entry)
    if capacity == nil then return nil, err end
    local before, shardErr = inventory(entry)
    if before == nil then return nil, shardErr end
    if amount > Policy.MAX_SAFE_INTEGER - before then return nil, "碎片数量超出安全范围" end
    local retained = math.min(before, capacity)
    local gain = math.min(amount, capacity - retained)
    local overflow = before - retained + amount - gain
    local rate = UrGachaConfig.getShardStardustValue(tonumber(heroId))
    if not Policy.isSafeInteger(rate) then return nil, "未配置碎片转币比例" end
    if overflow > math.floor(Policy.MAX_SAFE_INTEGER / rate) then
        return nil, "碎片转币超出安全范围"
    end
    return {
        heroId = tonumber(heroId), capacity = capacity,
        beforeShards = before, afterShards = retained + gain,
        shardGain = gain, amount = gain,
        overflowShards = overflow, tavernCoin = overflow * rate,
    }
end

return Policy
