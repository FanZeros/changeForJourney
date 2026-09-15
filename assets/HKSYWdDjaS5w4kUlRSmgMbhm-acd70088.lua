-- ============================================================================
-- TalentHandler - 天赋系统网络入口
-- 职责: 参数提取 → 调 Service → 返回结果（禁止业务逻辑）
-- 层级: server/talent
-- ============================================================================

local Protocol      = require("shared.Protocol")
local TalentService = require("server.talent.TalentService")

local handlers = {}

handlers[Protocol.ACTION_TYPES.ACTIVATE_TALENT] = function(uid, params)
    local nodeId = params and tonumber(params.nodeId)
    local ok, reason, result = TalentService.Activate(uid, nodeId)
    if not ok then
        return { success = false, reason = reason }
    end
    return { success = true, nodeId = result.nodeId }
end

handlers[Protocol.ACTION_TYPES.RESET_TALENTS] = function(uid, params)
    local ok, reason = TalentService.ResetAll(uid)
    if not ok then
        return { success = false, reason = reason }
    end
    return { success = true }
end

handlers[Protocol.ACTION_TYPES.RESET_SINGLE_TALENT] = function(uid, params)
    local nodeId = params and tonumber(params.nodeId)
    local ok, reason = TalentService.DeactivateSingle(uid, nodeId)
    if not ok then
        return { success = false, reason = reason }
    end
    return { success = true, nodeId = nodeId }
end

return handlers
