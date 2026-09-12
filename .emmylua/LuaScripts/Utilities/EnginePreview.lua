-- LuaScripts/Utilities/EnginePreview.lua
-- Entry point for engine preview compatibility layer
-- Supports resource URIs (e.g., uuid://) on old C++ binaries

do
    local rawSendEvent = SendEvent
    if rawSendEvent then
        function SendEvent(eventName, eventData, ...)
            if eventName == "RequestRestartGame" then
                print("[RestartGuard] blocked RequestRestartGame")
                return
            end
            return rawSendEvent(eventName, eventData, ...)
        end
    end
end

-- RuntimeMode fallback (default to client mode if C++ binding not available)
if GetRuntimeMode == nil then
    function GetRuntimeMode()
        return "client"
    end
end

if IsServerMode == nil then
    function IsServerMode()
        return false
    end
end

if IsClientMode == nil then
    function IsClientMode()
        return true
    end
end

-- clientCloud fallback (old binaries only register clientScore)
if clientCloud == nil and clientScore ~= nil then
    clientCloud = clientScore
end

-- iOS calling GetArguments crashes, replace with empty table
if GetPlatform() == "iOS" then
    function GetArguments()
        return {}
    end
end

local cachedNetworkMode = false
do
    if IsServerMode and IsServerMode() then
        cachedNetworkMode = true
    elseif IsClientMode and IsClientMode() then
        -- iOS调用接口GetArguments会crash
        if GetPlatform() == "Windows" then
            local args = GetArguments()
            local hasServerAddress = false
            local hasServerPort = false
            for _, arg in ipairs(args) do
                if arg:find("^-server_address=") then
                    hasServerAddress = true
                elseif arg:find("^-server_port=") then
                    hasServerPort = true
                end
            end
            if hasServerAddress and hasServerPort then
                cachedNetworkMode = true
            end
        end
    end

    if not cachedNetworkMode then
        if cache:Exists("settings.json") then
            local file = cache:GetFile("settings.json")
            if file then
                local content = file:ReadString()
                file:Close()

                local json = JSONFile()
                if json:FromString(content) then
                    local root = json:GetRoot()
                    local multiplayer = root:Get("multiplayer")
                    if not multiplayer:IsNull() then
                        cachedNetworkMode = multiplayer:Get("enabled"):GetBool()
                    end
                end
            end
        end
    end
    print('IsNetworkMode:', cachedNetworkMode)
end

if IsNetworkMode == nil then
    function IsNetworkMode()
        return cachedNetworkMode
    end
end

local function ConfigureNetworkingDefaults()
    if not IsNetworkMode() then return end

    if SetServerOnlyComponent and IsServerMode() then
        local serverOnlyComponents = {
            "RigidBody",
            "CollisionShape",
            "Constraint",
            "RigidBody2D",
            "CollisionShape2D",
            "CollisionBox2D",
            "CollisionChain2D",
            "CollisionCircle2D",
            "CollisionEdge2D",
            "CollisionPolygon2D",
            "Constraint2D",
            "ConstraintDistance2D",
            "ConstraintFriction2D",
            "ConstraintGear2D",
            "ConstraintMotor2D",
            "ConstraintMouse2D",
            "ConstraintPrismatic2D",
            "ConstraintPulley2D",
            "ConstraintRevolute2D",
            "ConstraintRope2D",
            "ConstraintWeld2D",
            "ConstraintWheel2D",
        }

        for _, typeName in ipairs(serverOnlyComponents) do
            SetServerOnlyComponent(StringHash(typeName), true)
        end
    end

    if network and network.SetMinUpdateFps and IsClientMode() then
        network:SetMinUpdateFps(999)
    end
end

ConfigureNetworkingDefaults()

-- GetNativePlatform fallback (use GetPlatform if C++ binding not available)
if GetNativePlatform == nil then
    function GetNativePlatform()
        return GetPlatform()
    end
end

-- Force UI layout update on startup
if ui then
    local root = ui:GetRoot()
    if root then
        root:UpdateLayout()
    end
end

-- Server headless
if GetGraphics() == nil then
    local mockGraphics = {
        SetWindowIcon = function() end,
        SetWindowTitleAndIcon = function() end,
        GetWidth = function() return 1920 end,
        GetHeight = function() return 1080 end,
        GetDPR = function() return 1.0 end,
    }
    ---@diagnostic disable-next-line: lowercase-global
    function GetGraphics() return mockGraphics end
    graphics = mockGraphics

    console = { background = {} }
    function GetConsole() return console end

    debugHud = {}
    function GetDebugHud() return debugHud end

    renderer = {
        SetViewport = function() end,
        SetDynamicInstancing = function() end,
    }
    function GetRenderer() return renderer end
end

local ok, err = pcall(require, 'urhox-libs/Engine')
if not ok then
    print("urhox-libs/Engine not available: " .. tostring(err))
end

require('LuaScripts/Utilities/Previews/InputAdaptor')
require('LuaScripts/Utilities/Previews/Scene')
require('LuaScripts/Utilities/Previews/SceneGuard')
require('LuaScripts/Utilities/Previews/UIGuard')
require('LuaScripts/Utilities/Previews/RewardVideoAd')

if cache:Exists("LuaScripts/Utilities/Previews/UserInfo.lua") then
    require('LuaScripts/Utilities/Previews/UserInfo')
else
    print ('Fallback to run local UserInfo.lua')

    local TAG = "[UserInfo]"
    local pendingRequests = {}

    -- Client-side: subscribe to UserNicknameResponse for async callback dispatch
    if SubscribeToEvent and not (_G.IsServerMode and _G.IsServerMode()) then
        SubscribeToEvent("UserNicknameResponse", function(eventType, eventData)
            local requestId = eventData["RequestId"]:GetInt()
            local callbacks = pendingRequests[requestId]
            if not callbacks then return end
            pendingRequests[requestId] = nil

            if eventData["Success"]:GetBool() then
                local nicknames = {}
                local json = eventData["Nicknames"]:GetString()
                if json and json ~= "" then
                    local ok, parsed = pcall(cjson.decode, json)
                    if ok and parsed and parsed.nicknames then
                        nicknames = parsed.nicknames
                    end
                end
                if callbacks.onSuccess then callbacks.onSuccess(nicknames) end
            else
                if callbacks.onError then callbacks.onError(eventData["ErrorCode"]:GetInt()) end
            end
        end)
    end

    -- Cleanup stale pending requests (timeout = 30s), called lazily before each new request
    local TIMEOUT_SECONDS = 30
    local function cleanupStalePendingRequests()
        local now = os.time()
        for id, req in pairs(pendingRequests) do
            if now - req.timestamp > TIMEOUT_SECONDS then
                print(TAG .. " WARN: request " .. tostring(id) .. " timed out, cleaning up")
                pendingRequests[id] = nil
                if req.onError then
                    pcall(req.onError, -2) -- -2 = timeout
                end
            end
        end
    end

    --- Batch query user nicknames (unified API for server and client)
    --- Server: reads nick_name from connection identity (synchronous)
    --- Client: queries via lobby C++ object (asynchronous)
    --- @param options table
    ---   - userIds: table user ID list (required), e.g. {12345, 67890}
    ---   - onSuccess: function(nicknames) nicknames = { {userId=N, nickname="..."}, ... }
    ---   - onError: function(errorCode)
    _G.GetUserNickname = function(options)
        local rawIds = options.userIds
        if not rawIds or #rawIds == 0 then
            print(TAG .. " ERROR: userIds is required")
            return
        end

        -- Normalize userIds: accept both number and string, convert to number
        local userIds = {}
        for i, id in ipairs(rawIds) do
            userIds[i] = tonumber(id) or 0
        end

        -- Server mode: resolve from SERVER_PLAYER_AUTH_INFOS (set by UrhoXServer C++)
        if _G.IsServerMode and _G.IsServerMode() then
            local authInfos = _G.SERVER_PLAYER_AUTH_INFOS or {}
            local nicknames = {}
            for _, uid in ipairs(userIds) do
                local info = authInfos[uid]
                nicknames[#nicknames + 1] = { userId = uid, nickname = (info and info.nickName) or "" }
            end
            if options.onSuccess then options.onSuccess(nicknames) end
            return
        end

        -- Client mode: query via lobby C++ object
        cleanupStalePendingRequests()

        if not lobby or not lobby.GetUserNickname then
            print(TAG .. " ERROR: lobby object or GetUserNickname not available")
            if options.onError then options.onError(-1) end
            return
        end

        local requestId = lobby:GetUserNickname(userIds)
        if not requestId or requestId < 0 then
            print(TAG .. " ERROR: lobby:GetUserNickname returned invalid requestId: " .. tostring(requestId))
            if options.onError then options.onError(-1) end
            return
        end

        pendingRequests[requestId] = {
            onSuccess = options.onSuccess,
            onError = options.onError,
            timestamp = os.time(),
        }
    end
end

local updateResDir = nil
if not cache:Exists("urhox-libs/UI/Core/Transition.lua") or not cache:Exists("urhox-libs/UI/Widgets/SimpleGrid.lua") then
    local resDirs = cache:GetResourceDirs()
    for _, resDir in ipairs(resDirs) do
        if resDir:match("[/\\]update[/\\]?$") then
            updateResDir = resDir
            break
        end
    end
end

print("Check Transition.lua SimpleGrid.lua")

if updateResDir and not cache:Exists("urhox-libs/UI/Core/Transition.lua") and not cache:Exists("urhox-libs/UI/Core/Transition.luc") then
    local dirPath = updateResDir .. "urhox-libs/UI/Core/"
    fileSystem:CreateDir(dirPath)
    local filePath = dirPath .. "Transition.luc"
    local file = File(filePath, FILE_WRITE)
    if file:IsOpen() then
        file:WriteLine("-- Auto-generated Transition stub for old binary compatibility")
        file:WriteLine("local T = {}")
        file:WriteLine("local function linear(t) return t end")
        file:WriteLine("T.Easing = { linear=linear, easeIn=linear, easeOut=linear, easeInOut=linear, easeInCubic=linear, easeOutCubic=linear, easeInOutCubic=linear, easeInExpo=linear, easeOutExpo=linear, easeInBack=linear, easeOutBack=linear, easeInOutBack=linear, spring=linear }")
        file:WriteLine("T.ResolveEasing = function() return linear end")
        file:WriteLine("T.Lerp = function(a, b, t) return a + (b - a) * t end")
        file:WriteLine("T.LerpColor = function(a, b, t) return { a[1]+(b[1]-a[1])*t, a[2]+(b[2]-a[2])*t, a[3]+(b[3]-a[3])*t, a[4]+(b[4]-a[4])*t } end")
        file:WriteLine("T.GetPropertyType = function() return nil end")
        file:WriteLine("T.Start = function() return {} end")
        file:WriteLine("T.Update = function() return false end")
        file:WriteLine("T.GetValue = function() return nil end")
        file:WriteLine("T.Cancel = function() end")
        file:WriteLine("T.CancelAll = function() end")
        file:WriteLine("T.HasActive = function() return false end")
        file:WriteLine("T.ParseConfig = function() return nil end")
        file:WriteLine("T.ConfigIncludesProperty = function() return false end")
        file:WriteLine("T.GetPropertyConfig = function() return 0, 'linear' end")
        file:WriteLine("T.CreateKeyframeAnimation = function() return {} end")
        file:WriteLine("T.InterpolateKeyframes = function() return {} end")
        file:WriteLine("T.UpdateKeyframeAnimation = function() return nil end")
        file:WriteLine("return T")
    else
        print('Failed to create Transition.lua for old binary version!')
    end
    file:Close()
    print("Created stub Transition.luc at: " .. filePath)
end

if updateResDir and not cache:Exists("urhox-libs/UI/Widgets/SimpleGrid.lua") and not cache:Exists("urhox-libs/UI/Widgets/SimpleGrid.luc") then
    local dirPath = updateResDir .. "urhox-libs/UI/Widgets/"
    fileSystem:CreateDir(dirPath)
    local filePath = dirPath .. "SimpleGrid.luc"
    local file = File(filePath, FILE_WRITE)
    if file:IsOpen() then
        file:WriteLine("-- Auto-generated SimpleGrid stub for old binary compatibility")
        file:WriteLine("local Widget = require('urhox-libs/UI/Core/Widget')")
        file:WriteLine("local SimpleGrid = Widget:Extend('SimpleGrid')")
        file:WriteLine("function SimpleGrid:Init(props)")
        file:WriteLine("    props = props or {}")
        file:WriteLine("    self.columns_ = props.columns or 4")
        file:WriteLine("    self.gap_ = props.gap or 0")
        file:WriteLine("    self.minColumnWidth_ = props.minColumnWidth")
        file:WriteLine("    Widget.Init(self, props)")
        file:WriteLine("    self:SetStyle({ flexDirection = 'row', flexWrap = 'wrap' })")
        file:WriteLine("end")
        file:WriteLine("function SimpleGrid:AddChild(child)")
        file:WriteLine("    Widget.AddChild(self, child)")
        file:WriteLine("    return self")
        file:WriteLine("end")
        file:WriteLine("function SimpleGrid:IsStateful() return false end")
        file:WriteLine("return SimpleGrid")
    else
        print('Failed to create SimpleGrid.lua for old binary version!')
    end
    file:Close()
    print("Created stub SimpleGrid.luc at: " .. filePath)
end

-- ============================================================================
-- File sandbox isolation (must be AFTER stub creation above)
-- ============================================================================

-- LuaEnvironment enum (mirrors C++ LuaScriptContext.h)
local LUA_ENV_RUNTIME = 0

local function isGameVM()
    if not GetLuaEnvironment then return nil end
    return GetLuaEnvironment() == LUA_ENV_RUNTIME
end

local function loadIsolation()
    -- Tool mode (UrhoXRuntime -tool_mode): C++ 在 EnginePreview 加载前设了该 global，
    -- agent / 工具脚本需要写绝对路径产物时由这条路径绕过沙箱。Lua 用户脚本无法在
    -- 这里之前修改 global，所以无法 self-bypass。
    if __tool_mode__ then return end

    if GetPlatform() == "Windows" then
        for _, arg in ipairs(GetArguments()) do
            if arg == "-skip_isolation" then return end
        end
    end
    local vm = isGameVM()
    local server = IsServerMode()
    if server then
        if vm then
            require('LuaScripts/Utilities/Previews/Isolation_Server')
        end
    else
        -- Client: game VM 精准隔离；旧二进制（无 GetLuaEnvironment）保守隔离
        if vm ~= false then
            require('LuaScripts/Utilities/Previews/Isolation_Client')
        end
    end
end

local ok, err = pcall(loadIsolation)
if not ok then
    print("Failed to load file isolation: " .. tostring(err))
end

-- ============================================================================
-- cjson.decode stack overflow protection (hotfix for old binaries)
-- C++ JSONValueToLua() lacks lua_checkstack(), deep JSON triggers abort().
-- Monkey-patch cjson.decode with a pre-scan that rejects overly nested JSON,
-- turning the crash into a catchable Lua error.
-- ============================================================================
-- cjson >= 1.1.0 has C++ side lua_checkstack + depth limit, no hotfix needed
if isGameVM() and cjson and cjson.decode and cjson._VERSION < "1.1.0" then
    print("[EnginePreview] cjson " .. tostring(cjson._VERSION) .. " lacks stack overflow protection, applying Lua hotfix (max depth 9)")
    local raw_decode = cjson.decode
    -- LUA_MINSTACK=20, Object costs 2 slots/level, safe limit ≈ 9
    local CJSON_MAX_DEPTH = 9
    local find = string.find
    local byte = string.byte

    cjson.decode = function(s)
        if #s < CJSON_MAX_DEPTH * 2 then
            return raw_decode(s)
        end

        local depth = 0
        local i = 1

        while true do
            local pos = find(s, '[{%[%]}"]', i)
            if not pos then break end

            local c = byte(s, pos)
            if c == 123 or c == 91 then        -- { [
                depth = depth + 1
                if depth > CJSON_MAX_DEPTH then
                    local msg = string.format(
                        "cjson.decode: JSON nesting too deep (%d > %d), rejecting %d bytes",
                        depth, CJSON_MAX_DEPTH, #s)
                    log:Write(LOG_ERROR, msg)
                    error(msg, 2)
                end
                i = pos + 1
            elseif c == 125 or c == 93 then    -- } ]
                depth = depth - 1
                i = pos + 1
            else                               -- " enter string
                i = pos + 1
                while true do
                    pos = find(s, '["\\]', i)
                    if not pos then break end
                    if byte(s, pos) == 92 then -- \ escape
                        i = pos + 2
                    else                       -- " end string
                        i = pos + 1
                        break
                    end
                end
            end
        end

        return raw_decode(s)
    end
end
