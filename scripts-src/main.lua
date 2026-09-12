-- ============================================================================
-- 2D 卡牌放置类游戏 - 入口路由
-- 用途: 检测运行模式并委托给对应模块，自身不含任何游戏逻辑
-- ============================================================================
--
-- ⚠️ AI 开发注意（架构备忘）:
--
-- 本项目当前为【多人模式 · 常驻服架构】
--   .project/settings.json → multiplayer.enabled = true, persistent_world.enabled = true
-- 运行时实际加载的是 Client.lua（客户端）和 Server.lua（服务端），
-- Standalone.lua 不会被执行！
--
-- 数据持久化走 serverCloud（服务端 SaveManager），不是 clientCloud 云存档。
-- 流程: Handler 修改数据 → SaveManager.markDirty(uid, module) → 推送客户端 + 定时落库
--
-- 因此：所有新增 UI 模块（require / init / draw / 输入处理）必须同时集成到：
--   1. network/Client.lua       — require、init(vg)、draw(vg)、数据设置
--   2. network/ClientInput.lua  — require、输入拦截（drag/tap/scroll）、点击检测
--
-- 不要只改 Standalone.lua，那只在单机模式下生效！
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
        print("[Main] loading Standalone module...")
        Module = require("network.Standalone")
        print("[Main] Standalone module loaded OK")
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
