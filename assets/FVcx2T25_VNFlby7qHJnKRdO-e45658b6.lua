-- ============================================================================
-- 2D 卡牌放置类游戏 - 入口路由
-- 用途: 检测运行模式并委托给对应模块，自身不含任何游戏逻辑
-- ============================================================================
--
-- ⚠️ AI 开发注意（架构备忘）:
--
-- 本项目当前为【单机模式】
--   .project/settings.json → multiplayer.enabled = false
-- 运行时实际加载的是 network/Standalone.lua；
-- network/Client.lua（客户端）和 network/Server.lua（服务端）只在
-- 多人模式开启时才会被执行。单机下的数据/存档逻辑以 Standalone.lua 内实现为准。
--
-- 若将来切回多人模式（settings.json → multiplayer.enabled = true），
-- 所有新增 UI 模块（require / init / draw / 输入处理）必须同时集成到：
--   1. network/Client.lua       — require、init(vg)、draw(vg)、数据设置
--   2. network/ClientInput.lua  — require、输入拦截（drag/tap/scroll）、点击检测
--
-- 只改 Standalone.lua 的话，在多人模式下不会生效！
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
