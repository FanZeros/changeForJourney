-- ============================================================================
-- 2D 卡牌放置类游戏 - 入口
-- 单机：始终加载 network/Standalone.lua
-- ============================================================================

---@type table
local Module = nil

function Start()
    print("[Main] Start() called")
    print("[Main] loading Standalone module...")
    Module = require("network.Standalone")
    print("[Main] Standalone module loaded OK")
    print("[Main] calling Module.Start()...")
    Module.Start()
    print("[Main] Module.Start() completed OK")
end

function Stop()
    if Module and Module.Stop then
        Module.Stop()
    end
end
