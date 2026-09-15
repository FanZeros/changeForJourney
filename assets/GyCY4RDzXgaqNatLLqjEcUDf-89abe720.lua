-- ============================================================================
-- GameAlgoConfigResolve - 服务端 Game Key 多来源解析
-- 优先级（后者覆盖前者）:
--   1. config/GameAlgoConfig.runtime.lua（Maker @runtime 副本，服务端 require）
--   2. 环境变量（Maker 云端密钥注入）
--   3. GameAlgoConfig.local.lua（本地开发覆盖）
--   4. settings.json（仅客户端 Preview，且须 FileExists；服务端禁止 File I/O）
-- ============================================================================

local GameAlgoConfigResolve = {}

local ENV_KEY_NAMES = {
    "GAMEALGO_KEY",
    "GAMEALGO_GAME_KEY",
    "SERVER_GAME_KEY",
    "X_GAMEALGO_KEY",
}

--- 客户端 Preview 可选读取路径（服务端不可用 File API）
local CLIENT_SETTINGS_PATHS = {
    "settings.json",
}

---@return boolean
local function isServerRuntime()
    return type(IsServerMode) == "function" and IsServerMode()
end

---@param value any
---@return string|nil
local function normalizeKey(value)
    if type(value) ~= "string" then return nil end
    local trimmed = value:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then return nil end
    return trimmed
end

---@param name string
---@return string|nil
local function tryGetEnv(name)
    if type(os) == "table" and type(os.getenv) == "function" then
        local ok, val = pcall(os.getenv, name)
        if ok then
            return normalizeKey(val)
        end
    end
    local getEnv = rawget(_G, "GetEnv")
    if type(getEnv) == "function" then
        local ok, val = pcall(getEnv, name)
        if ok then
            return normalizeKey(val)
        end
    end
    return nil
end

---@param block table|nil
---@return string|nil
local function pickKeyFromBlock(block)
    if type(block) ~= "table" then return nil end
    return normalizeKey(block.server_game_key)
        or normalizeKey(block.game_key)
        or normalizeKey(block.SERVER_GAME_KEY)
        or normalizeKey(block.serverGameKey)
end

---@param cfg table|nil
---@return string|nil enabled
---@return string|nil isDebug
local function pickFlagsFromBlock(cfg)
    if type(cfg) ~= "table" then return nil, nil end
    local enabled = cfg.ENABLED
    if enabled == nil then enabled = cfg.enabled end
    local isDebug = cfg.IS_DEBUG
    if isDebug == nil then isDebug = cfg.is_debug end
    if isDebug == nil then isDebug = cfg.isDebug end
    return enabled, isDebug
end

---@param path string
---@return table|nil
local function tryReadJsonFile(path)
    if isServerRuntime() then return nil end
    if not fileSystem or not fileSystem.FileExists or not fileSystem:FileExists(path) then
        return nil
    end

    local okFile, file = pcall(File, path, FILE_READ)
    if not okFile or not file or not file:IsOpen() then
        return nil
    end
    local raw = file:ReadString()
    file:Close()
    local okJson, data = pcall(cjson.decode, raw or "")
    if okJson and type(data) == "table" then
        return data
    end
    return nil
end

---@param moduleName string
---@return table|nil cfg
---@return string|nil source
local function tryRequireConfig(moduleName, sourceLabel)
    local ok, cfg = pcall(require, moduleName)
    if ok and type(cfg) == "table" then
        return cfg, sourceLabel
    end
    return nil, nil
end

---@return string|nil key
---@return string|nil source
local function tryRuntimeModule()
    if not isServerRuntime() then return nil, nil end
    local cfg, source = tryRequireConfig("config.GameAlgoConfig.runtime", "runtime:GameAlgoConfig.runtime")
    if not cfg then return nil, nil end
    local key = normalizeKey(cfg.SERVER_GAME_KEY)
    if key then
        return key, source
    end
    return nil, nil
end

---@return string|nil key
---@return string|nil source
local function tryClientSettingsFile()
    for _, path in ipairs(CLIENT_SETTINGS_PATHS) do
        local data = tryReadJsonFile(path)
        if data then
            local runtime = data["@runtime"] or data.runtime
            local key = pickKeyFromBlock(runtime and runtime.gamealgo)
                or pickKeyFromBlock(data.gamealgo)
            if key then
                return key, "settings:" .. path
            end
        end
    end
    return nil, nil
end

---@return string|nil key
---@return string|nil source
local function tryEnvironment()
    for _, name in ipairs(ENV_KEY_NAMES) do
        local key = tryGetEnv(name)
        if key then
            return key, "env:" .. name
        end
    end
    return nil, nil
end

---@return string|nil key
---@return string|nil source
local function tryLocalFile()
    local cfg = tryRequireConfig("config.GameAlgoConfig.local", "local:GameAlgoConfig.local")
    if not cfg then return nil, nil end
    local key = normalizeKey(cfg.SERVER_GAME_KEY)
    if key then
        return key, "local:GameAlgoConfig.local"
    end
    return nil, nil
end

---@return table { serverGameKey?, source?, enabled?, isDebug? }
function GameAlgoConfigResolve.resolve()
    local result = {
        serverGameKey = nil,
        source = nil,
        enabled = nil,
        isDebug = nil,
    }

    local runtimeKey, runtimeSource = tryRuntimeModule()
    if runtimeKey then
        result.serverGameKey = runtimeKey
        result.source = runtimeSource
    end

    local settingsKey, settingsSource = tryClientSettingsFile()
    if settingsKey then
        result.serverGameKey = settingsKey
        result.source = settingsSource
    end

    local envKey, envSource = tryEnvironment()
    if envKey then
        result.serverGameKey = envKey
        result.source = envSource
    end

    local localKey, localSource = tryLocalFile()
    if localKey then
        result.serverGameKey = localKey
        result.source = localSource
    end

    -- 读取开关：runtime(仅服务端) → client settings → local
    if isServerRuntime() then
        local runtimeCfg = tryRequireConfig("config.GameAlgoConfig.runtime")
        if runtimeCfg then
            local enabled, isDebug = pickFlagsFromBlock(runtimeCfg)
            if enabled ~= nil then result.enabled = enabled end
            if isDebug ~= nil then result.isDebug = isDebug end
        end
    end

    for _, path in ipairs(CLIENT_SETTINGS_PATHS) do
        local data = tryReadJsonFile(path)
        if data then
            local runtime = data["@runtime"] or data.runtime
            local ga = runtime and runtime.gamealgo
            if ga then
                if ga.enabled ~= nil then result.enabled = ga.enabled end
                if ga.is_debug ~= nil then result.isDebug = ga.is_debug end
                if ga.isDebug ~= nil then result.isDebug = ga.isDebug end
            end
        end
    end

    local localCfg = tryRequireConfig("config.GameAlgoConfig.local")
    if localCfg then
        if localCfg.ENABLED ~= nil then result.enabled = localCfg.ENABLED end
        if localCfg.IS_DEBUG ~= nil then result.isDebug = localCfg.IS_DEBUG end
    end

    return result
end

--- 日志用：只展示 key 前缀，避免泄露完整密钥
---@param key string|nil
---@return string
function GameAlgoConfigResolve.maskKey(key)
    if not key or key == "" then return "(empty)" end
    if #key <= 12 then return key:sub(1, 4) .. "..." end
    return key:sub(1, 12) .. "..." .. key:sub(-4)
end

return GameAlgoConfigResolve
