-- ============================================================================
-- GameAlgoConfig - GameAlgo 平台接入配置
-- 服务端 key 仅用于 ProxyServer，不要放进客户端包。
-- 解析顺序见 GameAlgoConfigResolve.lua（runtime require → env → local → client settings）
-- ============================================================================

local Resolve = require("config.GameAlgoConfigResolve")

local GameAlgoConfig = {}

--- 总开关
GameAlgoConfig.ENABLED = true

--- GameAlgo SDK API 地址
GameAlgoConfig.BASE_URL = "https://game-algo-sdk.dictapis.cn"

--- 服务端鉴权 key（由 Resolve 多来源注入）
GameAlgoConfig.SERVER_GAME_KEY = ""

--- key 来源（调试用，如 runtime:GameAlgoConfig.runtime / env:GAMEALGO_KEY）
GameAlgoConfig.SERVER_GAME_KEY_SOURCE = "none"

--- QA 包设为 true，生产包设为 false
GameAlgoConfig.IS_DEBUG = false

local resolved = Resolve.resolve()
if resolved.serverGameKey then
    GameAlgoConfig.SERVER_GAME_KEY = resolved.serverGameKey
    GameAlgoConfig.SERVER_GAME_KEY_SOURCE = resolved.source or "unknown"
end
if resolved.enabled ~= nil then
    GameAlgoConfig.ENABLED = resolved.enabled
end
if resolved.isDebug ~= nil then
    GameAlgoConfig.IS_DEBUG = resolved.isDebug == true
end

return GameAlgoConfig
