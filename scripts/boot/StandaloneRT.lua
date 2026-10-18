-- ============================================================================
-- StandaloneRT - 单机入口共享运行时（Boot / Horizon 跨模块读写）
-- ============================================================================
---@class StandaloneRuntime
---@field bootError string|nil
---@field bootRendered boolean|nil
---@field entryError string|nil
---@field entryPreparing boolean|nil
---@field entryStep string|nil
---@field entryPercent number|nil
---@field retryStartup function|nil
---@type StandaloneRuntime
local RT = {}
return RT
