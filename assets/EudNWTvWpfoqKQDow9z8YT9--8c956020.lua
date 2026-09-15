-- ============================================================================
-- AwakeningHandler - 觉醒系统网络入口
-- 职责: 参数提取 → 调 Service → 返回结果
-- 层级: server/awakening
-- ============================================================================

local Protocol         = require("shared.Protocol")
local AwakeningService = require("server.awakening.AwakeningService")

local handlers = {}

handlers[Protocol.ACTION_TYPES.ACTIVATE_AWAKENING] = function(uid, params)
    local heroId    = params and tonumber(params.heroId)
    local nodeIndex = params and tonumber(params.nodeIndex)

    local ok, reason, result = AwakeningService.Activate(uid, heroId, nodeIndex)
    if not ok then
        return { success = false, reason = reason }
    end

    return {
        success   = true,
        heroId    = result.heroId,
        nodeIndex = result.nodeIndex,
    }
end

return handlers
