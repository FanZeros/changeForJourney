-- ============================================================================
-- StageUtils - 关卡遍历共享工具
-- 职责: 提供跨难度的关卡前向遍历能力，供扫荡、挂机等模块共用
-- 层级: shared  |  纯计算，无副作用
-- ============================================================================

local SC = require("config.StageConfig")

local StageUtils = {}

--- 收集当前关卡往前的 N 个已通过关卡（不含当前关卡本身）
--- 支持跨难度边界：当前关卡是某难度第一关时，自动回退到上一难度末关
---@param currentStageId number 玩家当前卡住的关卡 ID
---@param count number 需要收集的关卡数
---@param stageConfig table|nil 关卡配置模块，默认 config.StageConfig
---@return table stages  StageEntry 数组（从高到低排列）
function StageUtils.collectPrevStages(currentStageId, count, stageConfig)
    local cfg = stageConfig or SC
    local stages = {}
    local prevId = cfg.getPrevStageId(currentStageId)
    -- fallback: 当前关卡是某难度第一关（如 2401），取上一个难度的最后一关
    if not prevId then
        prevId = cfg.getLastStageOfPrevDifficulty(currentStageId)
    end
    while prevId and #stages < count do
        local entry = cfg.getStage(prevId)
        if entry then
            stages[#stages + 1] = entry
        end
        local nextPrev = cfg.getPrevStageId(prevId)
        if not nextPrev then
            nextPrev = cfg.getLastStageOfPrevDifficulty(prevId)
        end
        prevId = nextPrev
    end
    return stages
end

return StageUtils
