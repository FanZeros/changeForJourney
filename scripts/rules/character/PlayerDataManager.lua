-- ============================================================================
-- PlayerDataManager.lua — 单机内存数据管理器
-- 落盘只走 boot/StandaloneSave（save.json）。不再读写云存档。
-- 业务仍通过 GetModule / MarkDirty 读写；MarkDirty 只推本地模块。
-- ============================================================================

local PlayerDataManager = {}

local CharacterSchema = require("shared.schemas.CharacterSchema")
local QuotaConsts     = require("shared.quota.QuotaConsts")

--- playerData_[uid] = { modules, serverId, dirty, sessionVersion, localMode }
local playerData_ = {}

--- 由 Setup 注入，单机下是 LocalActionBridge 的本地推送
local serverDispatcher_ = nil

local function refreshFieldDefs()
    local count = 0
    for _ in pairs(CharacterSchema.Fields) do count = count + 1 end
    print("[PDM] refreshFieldDefs: " .. count .. " fields registered")
end

---@param uid number
---@return table
local function ensurePlayerData(uid)
    if not playerData_[uid] then
        playerData_[uid] = {
            modules        = {},
            serverId       = nil,
            dirty          = {},
            sessionVersion = 0,
            localMode      = true,
        }
    end
    return playerData_[uid]
end

--- 初始化 PDM
---@param opts table|nil
function PlayerDataManager.Setup(opts)
    opts = opts or {}
    serverDispatcher_ = opts.serverDispatcher
    refreshFieldDefs()
    print("[PDM] Setup complete (local only)")
end

---@param uid number
---@param serverId number
function PlayerDataManager.SetServerId(uid, serverId)
    local pd = ensurePlayerData(uid)
    pd.serverId = serverId
    print("[PDM] SetServerId uid=" .. tostring(uid) .. " serverId=" .. tostring(serverId))
end

--- 把 ClientDispatcher 的模块表直接挂到 PDM
---@param uid number
---@param modules table
---@param serverId number|nil
function PlayerDataManager.AttachLocalModules(uid, modules, serverId)
    local pd = ensurePlayerData(uid)
    pd.modules = modules
    pd.serverId = serverId or 1
    pd.localMode = true
    pd.dirty = {}
    pd.sessionVersion = (pd.sessionVersion or 0) + 1
    print("[PDM] AttachLocalModules uid=" .. tostring(uid)
        .. " serverId=" .. tostring(pd.serverId))
end

---@param uid number
---@return number|nil
function PlayerDataManager.GetServerId(uid)
    local pd = playerData_[uid]
    return pd and pd.serverId
end

---@param uid number
---@return boolean
function PlayerDataManager.IsLocalMode(uid)
    local pd = playerData_[uid]
    return pd ~= nil and pd.localMode == true
end

---@param uid number
---@param fieldKey string
---@return table|nil
function PlayerDataManager.GetModule(uid, fieldKey)
    local pd = playerData_[uid]
    if not pd then return nil end
    return pd.modules[fieldKey]
end

---@param uid number
---@param fieldKey string
---@param data table
function PlayerDataManager.SetModule(uid, fieldKey, data)
    local pd = playerData_[uid]
    if not pd then
        print("[PDM] SetModule: no playerData for uid=" .. tostring(uid))
        return
    end
    pd.modules[fieldKey] = data
    PlayerDataManager.MarkDirty(uid, fieldKey)
end

--- 标记变更并推到本地模块表（不写云）
---@param uid number
---@param fieldKey string
function PlayerDataManager.MarkDirty(uid, fieldKey)
    local pd = playerData_[uid]
    if not pd or not pd.modules[fieldKey] then
        print("[PDM] MarkDirty: no data for uid=" .. tostring(uid) .. " field=" .. tostring(fieldKey))
        return
    end
    if serverDispatcher_ and serverDispatcher_.pushModule then
        serverDispatcher_.pushModule(uid, fieldKey, pd.modules[fieldKey])
    end
end

--- 单机落盘由 StandaloneSave 快照，这里不写云
---@param uid number
function PlayerDataManager.FlushImmediate(uid)
    print("[PDM] FlushImmediate local uid=" .. tostring(uid))
end

---@param _fn function|nil
function PlayerDataManager.SetDataLossAlertHook(_fn)
end

---@param uid number
---@return table|nil
function PlayerDataManager.GetAllModules(uid)
    local pd = playerData_[uid]
    return pd and pd.modules
end

---@param uid number
---@return boolean
function PlayerDataManager.IsLoaded(uid)
    local pd = playerData_[uid]
    return pd ~= nil and next(pd.modules) ~= nil
end

---@param uid number
function PlayerDataManager.PushFullState(uid)
    local pd = playerData_[uid]
    if not pd or not serverDispatcher_ or not serverDispatcher_.pushFullState then return end
    serverDispatcher_.pushFullState(uid, pd.modules)
end

---@param uid number
---@param callback function|nil
function PlayerDataManager.LoadGlobalProfile(uid, callback)
    ensurePlayerData(uid)
    print("[PDM] LoadGlobalProfile local uid=" .. tostring(uid))
    if callback then callback(true) end
end

---@param uid number
---@param callback function|nil
function PlayerDataManager.LoadPlayer(uid, callback)
    local pd = ensurePlayerData(uid)
    pd.modules.quotas = pd.modules.quotas or {}
    print("[PDM] LoadPlayer local uid=" .. tostring(uid))
    if callback then callback(true) end
end

---@param uid number
function PlayerDataManager.SavePlayer(uid)
    print("[PDM] SavePlayer skipped (local file) uid=" .. tostring(uid))
end

---@param _uid number
function PlayerDataManager.ClearCleanupRetries(_uid)
end

---@param uid number
---@param skipSave boolean|nil
function PlayerDataManager.RemovePlayer(uid, skipSave)
    playerData_[uid] = nil
    print("[PDM] RemovePlayer uid=" .. tostring(uid) .. " skipSave=" .. tostring(skipSave))
end

---@param _dt number
function PlayerDataManager.Update(_dt)
end

---@param uid number
---@param quotaKey string
---@return table|nil
function PlayerDataManager.GetQuotaState(uid, quotaKey)
    local pd = playerData_[uid]
    if not pd or not pd.modules.quotas then return nil end
    return pd.modules.quotas[quotaKey]
end

--- 本地限额。不写云变量。
---@param uid number
---@param quotaKey string
---@param amount number|nil
---@return boolean ok
---@return string|nil errMsg
function PlayerDataManager.UseQuota(uid, quotaKey, amount)
    amount = amount or 1
    local pd = playerData_[uid]
    if not pd or not pd.modules.quotas then
        return false, "not_loaded"
    end
    local keyDef = QuotaConsts.FindByKey(quotaKey)
    if not keyDef then
        print("[PDM] UseQuota: unknown key=" .. tostring(quotaKey))
        return false, "unknown_key"
    end
    local state = pd.modules.quotas[quotaKey]
    if not state then
        state = { value = 0, limit = keyDef.limit }
        pd.modules.quotas[quotaKey] = state
    end
    if state.value + amount > state.limit then
        return false, "quota_exceeded"
    end
    state.value = state.value + amount
    PlayerDataManager.MarkDirty(uid, "quotas")
    return true, nil
end

--- 单机限额已在内存中，刷新直接成功
---@param uid number
---@param quotaKey string
---@param callback function|nil
function PlayerDataManager.RefreshQuota(uid, quotaKey, callback)
    local pd = playerData_[uid]
    if not pd then
        if callback then callback(false) end
        return
    end
    print("[PDM] RefreshQuota local uid=" .. tostring(uid) .. " key=" .. tostring(quotaKey))
    if callback then callback(true) end
end

function PlayerDataManager.Shutdown()
    print("[PDM] Shutdown local (no cloud flush)")
end

return PlayerDataManager
