-- ============================================================================
-- ArenaHandler - 竞技场网络事件路由层（薄 Handler）
-- 异步 handler 返回 nil，通过 respond() 在回调中发送结果
-- 同步 handler 直接返回 result table
-- ============================================================================

local Protocol         = require("shared.Protocol")
local ServerDispatcher = require("network.ServerDispatcher")
local ArenaService     = require("server.arena.ArenaService")

local ArenaHandler = {}
local handlers = {}

--- 异步响应封装
---@param uid number
---@param result table
local function respond(uid, result)
    ServerDispatcher.sendEvent(uid, Protocol.RES_ACTION_RESULT, result)
end

--- ARENA_ENTER: 进入竞技场（异步）
handlers[Protocol.ACTION_TYPES.ARENA_ENTER] = function(uid, params)
    ArenaService.Enter(uid, params, function(result)
        respond(uid, result)
    end)
    return nil
end

--- ARENA_GET_OPPONENT: 获取对手防守阵容（异步）
handlers[Protocol.ACTION_TYPES.ARENA_GET_OPPONENT] = function(uid, params)
    if not params or not params.targetUid then
        respond(uid, { success = false, reason = "缺少目标玩家" })
        return nil
    end
    ArenaService.GetOpponent(uid, params.targetUid, function(result)
        respond(uid, result)
    end)
    return nil
end

--- ARENA_BATTLE_RESULT: 提交战斗结果（异步）
handlers[Protocol.ACTION_TYPES.ARENA_BATTLE_RESULT] = function(uid, params)
    if not params then
        respond(uid, { success = false, reason = "缺少参数" })
        return nil
    end
    local targetUid = params.targetUid
    local isWin     = params.isWin
    if not targetUid or isWin == nil then
        respond(uid, { success = false, reason = "参数不完整" })
        return nil
    end
    ArenaService.BattleResult(uid, targetUid, isWin, function(result)
        respond(uid, result)
    end)
    return nil
end

--- ARENA_GET_LOG: 获取防守记录（异步）
handlers[Protocol.ACTION_TYPES.ARENA_GET_LOG] = function(uid, params)
    ArenaService.GetLog(uid, function(result)
        respond(uid, result)
    end)
    return nil
end

--- ARENA_SHOP_BUY: 竞技场商店购买（同步，支持批量）
handlers[Protocol.ACTION_TYPES.ARENA_SHOP_BUY] = function(uid, params)
    if not params or not params.itemId then
        return { success = false, reason = "缺少商品ID" }
    end
    local itemId = tonumber(params.itemId)
    local quantity = math.max(1, tonumber(params.quantity) or 1)
    return ArenaService.ShopBuy(uid, itemId, quantity)
end

--- ARENA_CLAIM_TIER: 领取段位首通奖励（异步）
handlers[Protocol.ACTION_TYPES.ARENA_CLAIM_TIER] = function(uid, params)
    if not params or not params.tierId then
        respond(uid, { success = false, reason = "缺少段位ID" })
        return nil
    end
    ArenaService.ClaimTierReward(uid, params.tierId, function(result)
        respond(uid, result)
    end)
    return nil
end

ArenaHandler.actionHandlers = handlers
return ArenaHandler
