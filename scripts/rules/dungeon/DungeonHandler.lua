-- ============================================================================
-- DungeonHandler - 副本动作薄路由，保留规则层完整战斗与奖励回执。
-- ============================================================================
local Protocol = require("shared.Protocol")
local DungeonService = require("rules.dungeon.DungeonService")
local DungeonIdleService = require("rules.dungeon.DungeonIdleService")

local DungeonHandler = {}
local handlers = {}

local function response(ok, err, result)
    if not ok then return { success = false, reason = err } end
    result.success = true
    return result
end

handlers[Protocol.ACTION_TYPES.DUNGEON_SWEEP] = function(uid, params)
    local id = params and params.dungeonId or "gold_mine"
    return response(DungeonService.Sweep(uid, id))
end

local function battleResponse(params, ok, err, result)
    local reply = response(ok, err, result)
    -- 失败也带回请求身份，UI才能释放本次pending而不是等超时。
    if not ok and params then
        reply.dungeonId = params.dungeonId or "gold_mine"
        reply.floor = tonumber(params.floor)
        reply.teamIdx = tonumber(params.teamIdx) or 1
        reply.challengeId = params.challengeId
    end
    return reply
end

local function callBattle(params, operation, ...)
    local called, ok, err, result = pcall(operation, ...)
    if not called then
        print("[DungeonHandler] 战斗动作异常: " .. tostring(ok))
        return battleResponse(params, false, "本地处理失败")
    end
    return battleResponse(params, ok, err, result)
end

handlers[Protocol.ACTION_TYPES.DUNGEON_CHALLENGE] = function(uid, params)
    if not params or params.floor == nil then return battleResponse(params, false, "缺少floor参数") end
    return callBattle(params, DungeonService.Challenge, uid, params.dungeonId or "gold_mine", params.floor, params.teamIdx)
end

handlers[Protocol.ACTION_TYPES.DUNGEON_WIN] = function(uid, params)
    if not params or params.floor == nil then return battleResponse(params, false, "缺少floor参数") end
    return callBattle(params, DungeonService.Win, uid, params.dungeonId or "gold_mine", params.floor, params.teamIdx, params.challengeId)
end

handlers[Protocol.ACTION_TYPES.DUNGEON_IDLE_CLAIM] = function(uid, params)
    if not params or not params.dungeonId then return { success = false, reason = "缺少dungeonId参数" } end
    return response(DungeonIdleService.Claim(uid, params.dungeonId))
end

handlers["__cleanup"] = function(uid)
    DungeonService.Cleanup(uid)
    DungeonIdleService.Cleanup(uid)
end

DungeonHandler.actionHandlers = handlers
return DungeonHandler
