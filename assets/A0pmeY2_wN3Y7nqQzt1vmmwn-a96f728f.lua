-- ============================================================================
-- LootHandler - 战利品领取网络入口
-- 职责: 参数提取 → 调 LootService → 返回结果
-- 层级: server/loot  |  薄 Handler
-- ============================================================================

local Protocol    = require("shared.Protocol")
local LootService = require("server.loot.LootService")

local handlers = {}

--- 领取指定组全部战利品
handlers[Protocol.ACTION_TYPES.CLAIM_LOOT] = function(uid, params)
    local index = params and tonumber(params.index)
    local ok, reason, result = LootService.ClaimGroup(uid, index)
    if not ok then
        local resp = { success = false, reason = reason }
        if result and result.bagFull then resp.bagFull = true end
        return resp
    end
    return {
        success      = true,
        claimedCount = result.claimedCount,
        claimed      = result.claimed,
        bagFull      = result.bagFull,
        remaining    = result.remaining,
    }
end

--- 一键领取全部战利品
handlers[Protocol.ACTION_TYPES.CLAIM_LOOT_ALL] = function(uid, params)
    local ok, reason, result = LootService.ClaimAll(uid)
    if not ok then
        local resp = { success = false, reason = reason }
        if result and result.bagFull then resp.bagFull = true end
        return resp
    end
    return {
        success      = true,
        claimedCount = result.claimedCount,
        claimed      = result.claimed,
        bagFull      = result.bagFull,
        remaining    = result.remaining,
    }
end

--- 一键分解全部战利品种子
handlers[Protocol.ACTION_TYPES.DECOMPOSE_LOOT_ALL] = function(uid, params)
    local ok, reason, result = LootService.DecomposeAll(uid)
    if not ok then
        return { success = false, reason = reason }
    end
    return {
        success        = true,
        lootDecomposed = true,
        decomposeCount = result.decomposeCount,
        essenceReward  = result.essenceReward,
    }
end

--- 分解指定组战利品种子
handlers[Protocol.ACTION_TYPES.DECOMPOSE_LOOT] = function(uid, params)
    local index = params and tonumber(params.index)
    local ok, reason, result = LootService.DecomposeOne(uid, index)
    if not ok then
        return { success = false, reason = reason }
    end
    return {
        success        = true,
        lootDecomposed = true,
        decomposeCount = result.decomposeCount,
        essenceReward  = result.essenceReward,
    }
end

return handlers
