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

handlers[Protocol.ACTION_TYPES.DUNGEON_CHALLENGE] = function(uid, params)
    if not params or params.floor == nil then return { success = false, reason = "缺少floor参数" } end
    return response(DungeonService.Challenge(uid, params.dungeonId or "gold_mine", params.floor, params.teamIdx))
end

handlers[Protocol.ACTION_TYPES.DUNGEON_WIN] = function(uid, params)
    if not params or params.floor == nil then return { success = false, reason = "缺少floor参数" } end
    return response(DungeonService.Win(uid, params.dungeonId or "gold_mine", params.floor, params.teamIdx))
end

handlers[Protocol.ACTION_TYPES.DUNGEON_IDLE_CLAIM] = function(uid, params)
    if not params or not params.dungeonId then return { success = false, reason = "缺少dungeonId参数" } end
    return response(DungeonIdleService.Claim(uid, params.dungeonId))
end

handlers["__cleanup"] = function(uid)
    DungeonIdleService.Cleanup(uid)
end

DungeonHandler.actionHandlers = handlers
return DungeonHandler
