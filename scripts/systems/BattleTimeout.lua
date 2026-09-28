-- ============================================================================
-- BattleTimeout - 战斗超时增伤（纯函数模块，无状态）
-- 职责: 按"单场战斗已持续时间"计算敌我双方的全局伤害倍率
-- 语义: 超过宽限期后，每过 STEP_SEC 秒伤害 +STEP_BONUS，封顶 MAX_MULT
-- 注入: 各战斗入口每帧把 calcMult(elapsed) 写入 BattleCombat ctx.globalDmgMult
--       （applyGlobalDmgMult 覆盖普攻/连击/DOT/AOE/弹射/反击，不影响治疗）
-- 计时归属: 每个战斗实例自持 elapsed（主线=BattleScene、挂机=每队 TriDriver、
--           副本/通天塔=DungeonBattle.getElapsed），本模块不存任何状态
-- ============================================================================

local GameConfig = require("config.GameConfig")

local BattleTimeout = {}

--- 按战斗已持续时间计算全局伤害倍率
---@param elapsed number 本场战斗已持续时间（秒，战斗逻辑时间）
---@return number mult 伤害倍率（>=1.0；未启用/未超宽限期时恒为 1.0）
function BattleTimeout.calcMult(elapsed)
    local cfg = GameConfig.BattleTimeout
    if not cfg or not cfg.ENABLED then return 1.0 end
    local grace = cfg.GRACE_SEC or 60
    if not elapsed or elapsed < grace then return 1.0 end
    local step = cfg.STEP_SEC or 10
    local bonus = cfg.STEP_BONUS or 0.05
    if step <= 0 then return 1.0 end
    -- 超过宽限期立即进入第 1 阶（+1 步），此后每 STEP_SEC 再加一阶
    local steps = math.floor((elapsed - grace) / step) + 1
    local mult = 1.0 + steps * bonus
    local cap = cfg.MAX_MULT or 3.0
    if mult > cap then mult = cap end
    return mult
end

return BattleTimeout
