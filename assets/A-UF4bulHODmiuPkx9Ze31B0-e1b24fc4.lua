-- ============================================================================
-- StageProvider - 按区服选择关卡配置（双端共享，无副作用）
-- ============================================================================

local BaseStageConfig = require("config.StageConfig")
local ChallengerServerConfig = require("shared.ChallengerServerConfig")

local M = {}
local cache_ = {}
local errors_ = {}

local UnavailableStageConfig = {
    __stageProviderUnavailable = true,
}

function UnavailableStageConfig.getStage(id)
    return nil
end

function UnavailableStageConfig.getPrevStageId(id)
    return nil
end

function UnavailableStageConfig.getLastStageOfPrevDifficulty(id)
    return nil
end

function UnavailableStageConfig.getTerminalPrevStageId(id)
    return nil
end

function UnavailableStageConfig.getNextStageId(id)
    return nil
end

function UnavailableStageConfig.isTerminalTemple(id)
    return false
end

function UnavailableStageConfig.getDifficulty(id)
    return BaseStageConfig.getDifficulty(id)
end

function UnavailableStageConfig.getDifficultyDisplayName(difficulty)
    return BaseStageConfig.getDifficultyDisplayName(difficulty)
end

function UnavailableStageConfig.formatProgressDisplay(stageId)
    return tostring(stageId or 0)
end

local function loadStageConfig(moduleName)
    if not cache_[moduleName] then
        local ok, mod = pcall(require, moduleName)
        if ok and mod then
            cache_[moduleName] = mod
            errors_[moduleName] = nil
        else
            local err = tostring(mod)
            print("[StageProvider][ERROR] failed to load " .. tostring(moduleName) .. ": " .. err)
            cache_[moduleName] = UnavailableStageConfig
            errors_[moduleName] = err
        end
    end
    return cache_[moduleName]
end

function M.GetForServer(serverId)
    local cfg = ChallengerServerConfig.GetByServerId(serverId)
    if cfg and cfg.stageConfigModule then
        return loadStageConfig(cfg.stageConfigModule)
    end
    return BaseStageConfig
end

function M.IsAvailableForServer(serverId)
    local cfg = ChallengerServerConfig.GetByServerId(serverId)
    if not cfg or not cfg.stageConfigModule then return true end
    local stageConfig = loadStageConfig(cfg.stageConfigModule)
    return stageConfig ~= UnavailableStageConfig
end

function M.GetLoadError(serverId)
    local cfg = ChallengerServerConfig.GetByServerId(serverId)
    if not cfg or not cfg.stageConfigModule then return nil end
    loadStageConfig(cfg.stageConfigModule)
    return errors_[cfg.stageConfigModule]
end

return M
