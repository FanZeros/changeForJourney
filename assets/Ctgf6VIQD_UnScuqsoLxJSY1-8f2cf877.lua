-- ============================================================================
-- SignInHandler - 签到系统网络入口
-- 职责: 参数提取 → 调 Service → 返回结果（禁止业务逻辑）
-- 层级: server/signin
-- ============================================================================

local Protocol      = require("shared.Protocol")
local SignInService = require("server.signin.SignInService")

local handlers = {}

handlers[Protocol.ACTION_TYPES.WEEKLY_SIGN] = function(uid, params)
    local ok, reason, result = SignInService.WeeklySign(uid)
    if not ok then
        return { success = false, reason = reason }
    end
    return {
        success = true,
        action  = Protocol.ACTION_TYPES.WEEKLY_SIGN,
        day     = result.day,
        reward  = result.reward,
    }
end

handlers[Protocol.ACTION_TYPES.DAILY_SIGN] = function(uid, params)
    local ok, reason, result = SignInService.DailySign(uid)
    if not ok then
        return { success = false, reason = reason }
    end
    return {
        success = true,
        action  = Protocol.ACTION_TYPES.DAILY_SIGN,
        day     = result.day,
        reward  = result.reward,
    }
end

handlers[Protocol.ACTION_TYPES.RETRO_SIGN] = function(uid, params)
    local source = params and params.source
    local day    = params and tonumber(params.day)
    local ok, reason, result = SignInService.RetroSign(uid, source, day)
    if not ok then
        return { success = false, reason = reason }
    end
    return {
        success = true,
        action  = Protocol.ACTION_TYPES.RETRO_SIGN,
        source  = result.source,
        day     = result.day,
        reward  = result.reward,
        cost    = result.cost,
    }
end

handlers[Protocol.ACTION_TYPES.GET_SIGNIN_STATE] = function(uid, params)
    local ok, reason = SignInService.RefreshAndGet(uid)
    if not ok then
        return { success = false, reason = reason }
    end
    -- MarkDirty 会触发服务端 pushModule，客户端将收到最新 signin 数据
    return { success = true, action = Protocol.ACTION_TYPES.GET_SIGNIN_STATE }
end

return handlers
