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
    local count = params and (params.count or params.times) or 1
    local ok, err, result = SweepService.Sweep(uid, count)
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
        equips          = result.equips,
        equipByQuality  = result.equipByQuality,
        scrollDrops     = result.scrollDrops,
        ticketLeft      = result.ticketLeft,
        count           = result.count,
    }
end

SweepHandler.actionHandlers = handlers

return SweepHandler
