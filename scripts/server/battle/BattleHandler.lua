-- ============================================================================
-- BattleHandler - 战斗/关卡事件路由
-- 职责: 网络事件入口、参数提取、调 Service、返回结果
-- 层级: server/battle
-- ============================================================================

local Protocol      = require("shared.Protocol")
local BattleService = require("server.battle.BattleService")

local BattleHandler = {}
local handlers = {}

--- 通关 & 推进关卡
handlers[Protocol.ACTION_TYPES.NEXT_STAGE] = function(uid, params)
    local clearedId = params and params.clearedStageId
    local nextId    = params and params.nextStageId
    local ok, err, result = BattleService.NextStage(uid, clearedId, nextId)
    if not ok then
        return { success = false, reason = err }
    end
    result.success = true
    return result
end

--- 重置关卡进度
handlers[Protocol.ACTION_TYPES.RESET_STAGE] = function(uid, params)
    local ok, err = BattleService.ResetStage(uid)
    if not ok then return { success = false, reason = err } end
    return { success = true }
end

--- 结算战斗奖励
handlers[Protocol.ACTION_TYPES.CLAIM_BATTLE_REWARDS] = function(uid, params)
    local rewards = params and params.rewards
    if not rewards or type(rewards) ~= "table" or #rewards == 0 then
        return { success = false, reason = "无奖励数据" }
    end
    local ok, err, result = BattleService.ClaimBattleRewards(uid, rewards)
    if not ok then return { success = false, reason = err } end
    result.success = true
    return result
end

--- 领取情景对话奖励
handlers[Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD] = function(uid, params)
    local scenarioId = params and params.scenarioId
    if not scenarioId or type(scenarioId) ~= "number" then
        return { success = false, reason = "参数错误" }
    end
    local ok, err, result = BattleService.ClaimScenarioReward(uid, scenarioId)
    if not ok then return { success = false, reason = err } end
    result.success = true
    result.action = Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD
    return result
end

BattleHandler.actionHandlers = handlers
return BattleHandler
