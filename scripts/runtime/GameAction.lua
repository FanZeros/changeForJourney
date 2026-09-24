-- ============================================================================
-- GameAction - 玩法操作门面（单机）
-- 全部走 LocalActionBridge，不加载联机 Client
-- ============================================================================

local M = {}

---@param action string
---@param params table|nil
---@return boolean
function M.sendAction(action, params)
    return require("runtime.LocalActionBridge").dispatch(action, params)
end

---@return boolean
function M.isGM()
    return false
end

function M.resetForNewSession()
end

function M.requestReturnToLobby()
end

return M
