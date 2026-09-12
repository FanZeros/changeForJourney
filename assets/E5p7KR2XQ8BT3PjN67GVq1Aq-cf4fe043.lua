-- ============================================================================
-- 2D 卡牌放置类游戏 - 入口路由
-- 用途: 检测运行模式并委托给对应模块，自身不含任何游戏逻辑
-- ============================================================================
--
-- ⚠️ 架构备忘（本地回环改造 2026-09）:
--
-- 单机模式（multiplayer.enabled = false）→ network/LocalHost.lua
--   在同一进程内轻量启动 Server + LocalCloud（JSON 落盘），并复用完整的
--   multiplayer 客户端管线（Client.lua）。「联网改本地」方案 B，详见
--   docs/local-conversion-plan.md。
--
-- 多人模式（multiplayer.enabled = true）→ Server.lua / Client.lua（原样不变）
--   数据持久化走 serverCloud（服务端 SaveManager）。
--
-- ============================================================================

---@type table
local Module = nil

function Start()
    print("[Main] Start() called")
    if IsServerMode() then
        print("[Main] loading Server module...")
        Module = require("network.Server")
        print("[Main] Server module loaded OK")
    elseif IsNetworkMode() then
        print("[Main] loading Client module...")
        Module = require("network.Client")
        print("[Main] Client module loaded OK")
    else
        print("[Main] loading LocalHost module (single-player loopback)...")
        Module = require("network.LocalHost")
        print("[Main] LocalHost module loaded OK")
    end
    print("[Main] calling Module.Start()...")
    Module.Start()
    print("[Main] Module.Start() completed OK")
end

function Stop()
    if Module and Module.Stop then
        Module.Stop()
    end
end
