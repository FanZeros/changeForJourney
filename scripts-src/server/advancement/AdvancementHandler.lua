-- ============================================================================
-- AdvancementHandler - 转职系统网络入口
-- 职责: 参数提取 → 调 Service → 返回结果
-- 层级: server/advancement
-- ============================================================================

local Protocol            = require("shared.Protocol")
local AdvancementService  = require("server.advancement.AdvancementService")

local handlers = {}

handlers[Protocol.ACTION_TYPES.ADVANCE_CLASS] = function(uid, params)
    local heroId   = params and tonumber(params.heroId)
    local branchId = params and tonumber(params.branchId)
    local advLevel = params and tonumber(params.advLevel)

    local ok, reason, result = AdvancementService.AdvanceClass(uid, heroId, branchId, advLevel)
    if not ok then
        return { success = false, reason = reason }
    end

    return {
        success    = true,
        heroId     = result.heroId,
        branchId   = result.branchId,
        advLevel   = result.advLevel,
        branchName = result.branchName,
    }
end

handlers[Protocol.ACTION_TYPES.RESET_CLASS] = function(uid, params)
    local heroId = params and tonumber(params.heroId)

    local ok, reason, result = AdvancementService.ResetClass(uid, heroId)
    if not ok then
        return { success = false, reason = reason }
    end

    return {
        success            = true,
        heroId             = result.heroId,
        refundGold         = result.refundGold,
        removedOffhandSeq  = result.removedOffhandSeq,
    }
end

return handlers
