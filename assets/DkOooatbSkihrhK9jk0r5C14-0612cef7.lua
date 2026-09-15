-- ============================================================================
-- OfflineHandler - 离线收益网络入口（薄路由层）
-- 职责: 接收请求 → 调 OfflineService → 返回结果
-- 层级: server/offline  |  禁止业务逻辑
-- ============================================================================

local Protocol       = require("shared.Protocol")
local OfflineService = require("server.offline.OfflineService")
local TaskService    = require("server.task.TaskService")

local OfflineHandler = {}

local handlers = {}

--- 将网络参数规范为真正的 boolean（避免 "false"/其它真值误判）
---@param v any
---@return boolean
local function toBool(v)
    return v == true or v == 1 or v == "1" or v == "true"
end

--- 领取离线收益
handlers[Protocol.ACTION_TYPES.CLAIM_OFFLINE_REWARDS] = function(uid, params)
    local claimBonus   = toBool(params and params.claimBonus)
    local usePrivilege = toBool(params and params.usePrivilege)
    -- 看广告路径绝不能带上 usePrivilege；特权点路径固定只扣 1 点（服务端再校验）
    if claimBonus and usePrivilege then
        print("[OfflineHandler] CLAIM_OFFLINE bonus+privilege uid=" .. tostring(uid))
    elseif claimBonus then
        print("[OfflineHandler] CLAIM_OFFLINE bonus+ad uid=" .. tostring(uid))
    else
        print("[OfflineHandler] CLAIM_OFFLINE base-only uid=" .. tostring(uid))
    end
    local ok, err, result = OfflineService.ClaimRewards(uid, claimBonus, usePrivilege)
    if not ok then
        return { success = false, reason = err }
    end
    -- 看广告获得额外收益时，推进广告任务进度（特权点不算广告）
    if result.bonusApplied and not usePrivilege then
        TaskService.UpdateProgress(uid, "watch_ad", 1)
    end
    return {
        success       = true,
        bonusApplied  = result.bonusApplied,
        gold          = result.gold,
        heroExp       = result.heroExp,
        playerExp     = result.playerExp,
        privilegeCost = result.privilegeCost,
        privilegeLeft = result.privilegeLeft,
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
