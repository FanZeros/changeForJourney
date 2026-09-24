-- ============================================================================
-- OfflineHandler - 离线收益网络入口（薄路由层）
-- 职责: 接收请求 → 调 OfflineService → 返回结果
-- 层级: server/offline  |  禁止业务逻辑
-- ============================================================================

local Protocol       = require("shared.Protocol")
local OfflineService = require("rules.offline.OfflineService")

local OfflineHandler = {}

local handlers = {}

--- 领取离线收益
handlers[Protocol.ACTION_TYPES.CLAIM_OFFLINE_REWARDS] = function(uid, params)
    local ok, err, result = OfflineService.ClaimRewards(uid)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success   = true,
        gold      = result.gold,
        heroExp   = result.heroExp,
        playerExp = result.playerExp,
    }
end

--- 标记开场剧情已完成
handlers[Protocol.ACTION_TYPES.MARK_INTRO_COMPLETED] = function(uid, params)
    local ok, err, result = OfflineService.MarkIntroCompleted(uid)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success          = true,
        alreadyCompleted = result.alreadyCompleted,
    }
end

--- 清除轮回标志（入场动画播放完毕后调用）
handlers[Protocol.ACTION_TYPES.CLEAR_REINCARNATION] = function(uid, params)
    local ok, err = OfflineService.ClearReincarnation(uid)
    if not ok then
        return { success = false, reason = err }
    end
    return { success = true }
end

--- 断线清理（由 Server.lua 的 __cleanup 机制调用）
handlers["__cleanup"] = function(uid)
    OfflineService.Cleanup(uid)
end

OfflineHandler.actionHandlers = handlers

return OfflineHandler
