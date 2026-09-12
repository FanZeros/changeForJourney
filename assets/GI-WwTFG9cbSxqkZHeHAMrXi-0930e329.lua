-- ============================================================================
-- SweepHandler - 扫荡网络入口（薄路由层）
-- 职责: 接收 SWEEP 请求 → 调 SweepService → 返回结果
-- 层级: server/sweep  |  禁止业务逻辑
-- ============================================================================

local Protocol     = require("shared.Protocol")
local SweepService = require("server.sweep.SweepService")

local SweepHandler = {}

local handlers = {}

handlers[Protocol.ACTION_TYPES.SWEEP] = function(uid, params)
    local ok, err, result = SweepService.Sweep(uid)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success         = true,
        gold            = result.gold,
        heroExp         = result.heroExp,
        heroExpTotal    = result.heroExpTotal,
        playerExp       = result.playerExp,
        equipCount      = result.equipCount,
        equipByQuality  = result.equipByQuality,
        scrollDrops     = result.scrollDrops,
        ticketLeft      = result.ticketLeft,
    }
end

SweepHandler.actionHandlers = handlers

return SweepHandler
