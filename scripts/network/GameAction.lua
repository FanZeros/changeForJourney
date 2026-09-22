-- ============================================================================
-- GameAction - 玩法操作门面
-- 单机：直接走 LocalActionBridge，不加载 network.Client
-- 联网：转发 Client.sendAction / isGM / 会话重置
-- ============================================================================

local M = {}

local function isOnline()
    return IsNetworkMode() and not IsServerMode()
end

---@param action string
---@param params table|nil
---@return boolean
function M.sendAction(action, params)
    if isOnline() then
        return require("network.Client").sendAction(action, params)
    end
    return require("network.LocalActionBridge").dispatch(action, params)
end

---@return boolean
function M.isGM()
    if isOnline() then
        return require("network.Client").isGM() == true
    end
    -- 单机不加载 Client，保持原 gmAuthed_ 默认 false（调试面板不因此解锁）
    return false
end

function M.resetForNewSession()
    if isOnline() then
        require("network.Client").resetForNewSession()
    end
end

function M.requestReturnToLobby()
    if isOnline() then
        require("network.Client").requestReturnToLobby()
    end
end

return M
