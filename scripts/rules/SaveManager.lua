-- ============================================================================
-- SaveManager - 单机区服 ID
-- 云存档已删除。玩家数据落盘只走 boot/StandaloneSave（save.json）。
-- 仍保留 load/flush 等旧入口，全部改为本地空操作，避免残留调用再走云。
-- ============================================================================

local SaveManager = {}

--- uid -> serverId
local serverId_ = {}

--- 设置玩家当前的区服 ID
---@param uid number
---@param serverId number
function SaveManager.setServerId(uid, serverId)
    serverId_[uid] = serverId
    print("[SaveManager] setServerId uid=" .. tostring(uid) .. " serverId=" .. tostring(serverId))
end

--- 获取玩家当前的区服 ID
---@param uid number
---@return number|nil
function SaveManager.getServerId(uid)
    return serverId_[uid]
end

function SaveManager.register(_moduleName, _config) end

function SaveManager.registerFromRegistry() end

function SaveManager.setLoadDiagHook(_fn) end

---@param uid number
---@param callback function|nil
function SaveManager.loadGlobalProfile(uid, callback)
    print("[SaveManager] loadGlobalProfile skipped (local) uid=" .. tostring(uid))
    if callback then callback(true) end
end

---@param uid number
---@param callback function|nil
function SaveManager.load(uid, callback)
    print("[SaveManager] load skipped (local) uid=" .. tostring(uid))
    if callback then callback(true) end
end

function SaveManager.getTable(_uid, _moduleName)
    return nil
end

function SaveManager.getAllTables(_uid)
    return nil
end

function SaveManager.replaceModuleMemory(_uid, _moduleName, _data) end

function SaveManager.markDirty(_uid, _moduleName) end

function SaveManager.savePlayerNow(_uid) end

function SaveManager.isLoaded(uid)
    return serverId_[uid] ~= nil
end

function SaveManager.checkRateLimit(_uid)
    return true
end

function SaveManager.update(_dt) end

function SaveManager.cleanup(_uid) end

function SaveManager.shutdown()
    print("[SaveManager] shutdown local (no cloud flush)")
end

function SaveManager.getLoadState(_uid)
    return "local"
end

return SaveManager
