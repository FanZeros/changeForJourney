-- ============================================================================
-- GameAlgoConfig.runtime — Maker @runtime.gamealgo 的服务端可读副本
-- 来源: .project/settings.json → @runtime.gamealgo
-- 服务端无法 File() 读取 settings.json，须通过 require 加载此文件。
-- Maker 修改 @runtime.gamealgo 后请同步更新本文件（或与 settings 一并提交）。
-- ============================================================================

local GameAlgoConfigRuntime = {}

GameAlgoConfigRuntime.SERVER_GAME_KEY = "ga_live_8d5e06c0735ad7e54d87dfe99139d983dd1cad0f046ad4bb"
GameAlgoConfigRuntime.ENABLED = true
GameAlgoConfigRuntime.IS_DEBUG = false

return GameAlgoConfigRuntime
