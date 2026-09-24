-- ============================================================================
-- StageProvider - 单机关卡配置
-- 不再按区服切换。挑战者关卡已删除。
-- ============================================================================

local BaseStageConfig = require("config.StageConfig")

local M = {}

function M.Get()
    return BaseStageConfig
end

function M.GetForServer(_serverId)
    return BaseStageConfig
end

function M.IsAvailableForServer(_serverId)
    return true
end

function M.GetLoadError(_serverId)
    return nil
end

return M
