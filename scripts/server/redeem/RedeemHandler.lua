-- ============================================================================
-- RedeemHandler - 兑换码网络入口
-- 职责: 参数提取 → 调 Service → 返回结果（禁止业务逻辑）
-- 层级: server/redeem
-- ============================================================================

local Protocol     = require("shared.Protocol")
local RedeemService = require("server.redeem.RedeemService")
local ServerDispatcher = require("network.ServerDispatcher")

local handlers = {}

handlers[Protocol.ACTION_TYPES.REDEEM_CODE] = function(uid, params)
    local ok, reason, result = RedeemService.Redeem(uid, params and params.code)
    if not ok then
        return { success = false, reason = reason, redeemAction = true }
    end
    if result.privilegePayload then
        ServerDispatcher.pushModule(uid, "privilege", result.privilegePayload)
    end
    return {
        success      = true,
        redeemAction = true,
        action       = Protocol.ACTION_TYPES.REDEEM_CODE,
        code         = result.code,
        rewards      = result.rewards,
    }
end

return handlers
