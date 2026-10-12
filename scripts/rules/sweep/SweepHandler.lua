-- ============================================================================
-- SweepHandler - 扫荡本地入口（薄路由层）
-- 职责: 接收本地 SWEEP 请求 → 调 SweepService → 返回结果
-- 层级: rules/sweep  |  单机，不连服务器
-- ============================================================================

local Protocol     = require("shared.Protocol")
local SweepService = require("rules.sweep.SweepService")

local SweepHandler = {}

local handlers = {}

handlers[Protocol.ACTION_TYPES.SWEEP] = function(uid, params)
    params = params or {}
    local count = params.count
    if count == nil then count = params.times end
    local teamIdx = params.teamIdx
    local ok, err, result = SweepService.Sweep(uid, count, teamIdx, params.stageId)
    if not ok then
        return { success = false, reason = err, teamIdx = teamIdx, stageId = params and params.stageId }
    end
    result.success = true
    return result
end

SweepHandler.actionHandlers = handlers

return SweepHandler
