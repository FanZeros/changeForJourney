-- ============================================================================
-- GameAlgoProxy - 服务端 HTTP 代理启动器
-- 职责：把客户端 RemoteEvent 请求转发到 GameAlgo HTTP API
-- ============================================================================

local ProxyServer           = require("sdk.gamealgo.ProxyServer")
local GameAlgoConfig        = require("config.GameAlgoConfig")
local GameAlgoConfigResolve = require("config.GameAlgoConfigResolve")

local GameAlgoProxy = {}

local started_ = false

function GameAlgoProxy.Start()
    if started_ or GameAlgoConfig.ENABLED ~= true then return end

    local gameKey = GameAlgoConfig.SERVER_GAME_KEY
    if not gameKey or gameKey == "" then
        print("[GameAlgoProxy] SERVER_GAME_KEY not configured, proxy disabled"
            .. " (check GameAlgoConfig.runtime.lua, env GAMEALGO_KEY, or GameAlgoConfig.local.lua)")
        return
    end

    print("[GameAlgoProxy] key ready source="
        .. tostring(GameAlgoConfig.SERVER_GAME_KEY_SOURCE or "unknown")
        .. " key=" .. GameAlgoConfigResolve.maskKey(gameKey))

    _G.HandleProxyRequest = function(eventType, eventData)
        ProxyServer.HandleRequest(eventType, eventData)
    end

    ProxyServer.Start({
        allowedHosts = { "game-algo-sdk.dictapis.cn" },
        allowedPathPrefixes = { "/v1/" },
        defaultHeaders = {
            ["X-Proxy-Source"] = "maker-server",
            ["X-GameAlgo-Key"] = gameKey,
        },
        timeout = 10000,
        maxBodySize = 65536,
    })

    started_ = true
    print("[GameAlgoProxy] HTTP proxy ready")
end

return GameAlgoProxy
