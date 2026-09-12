-- ============================================================================
-- LocalHost - 本地回环启动器（单机模式）
-- 职责:
--   1. 用 network.LocalCloud 顶替全局 serverCloud（JSON 文件落盘）
--   2. 轻量启动进程内服务端（network/Server.lua 的 LocalBoot seam）
--   3. 提供 MockConnection 与 network 全局 shim，把客户端的远程事件收发
--      变成进程内直通：
--        客户端 → conn:SendRemoteEvent(REQ_*) → LocalHost 路由 → Server.Local*
--        服务端 → conn:SendRemoteEvent(S_*, vm) → SendEvent(name, vm)
--                 → 客户端既有 SubscribeToEvent 处理器原样接收
--   4. 复用完整 multiplayer 客户端管线（network/Client.lua），零改动
-- 运行端: 仅单机模式（main.lua 第三分支）
-- ============================================================================

local LocalHost = {}

--- 本地玩家 uid（服务端各模块以 uid 维度存取数据）
local LOCAL_UID = 1

--- MockConnection 引用（Stop 时用）
local mockConn_ = nil

---@type table|nil  Server 模块引用
local Server_ = nil

function LocalHost.IsActive()
    return mockConn_ ~= nil
end

function LocalHost.GetLocalUID()
    return LOCAL_UID
end

-- ======================== 启动 ========================

function LocalHost.Start()
    print("[LocalHost] ========== Local Loopback Boot ==========")

    -- 1. serverCloud 替身（必须在 require Server/SaveManager 之前）
    _G.serverCloud = require("network.LocalCloud")

    -- 2. 轻量启动服务端（不建 Scene、不注册引擎网络事件、不启动跨实例/GameAlgo）
    Server_ = require("network.Server")
    Server_.LocalBoot()

    -- 3. MockConnection：把服务端发出的远程事件转投到本进程事件系统
    local Protocol = require("shared.Protocol")
    mockConn_ = {
        scene    = nil,
        identity = nil,
    }
    function mockConn_:SendRemoteEvent(eventName, _reliable, vm)
        -- 服务端 → 客户端：直接以本地事件投递，客户端 SubscribeToEvent 原样接收
        SendEvent(eventName, vm)
    end

    Server_.LocalConnect(mockConn_, LOCAL_UID)

    -- 4. network 全局 shim（客户端侧唯一耦合面: GetServerConnection / RegisterRemoteEvent）
    local realNetwork = network
    _G.network = setmetatable({
        GetServerConnection = function()
            return mockConn_
        end,
        RegisterRemoteEvent = function(_eventName)
            -- 回环模式下客户端远程事件直接由 SendEvent 投递，无需向引擎注册
        end,
    }, {
        __index = function(_t, key)
            return realNetwork[key]
        end,
    })

    -- 5. 启动完整 multiplayer 客户端管线
    --    Client.Start() 尾部检测到 existingConn → 发送 C_Ready →
    --    LocalReady → S_InitData + RES_SERVER_LIST → 客户端进入选服/读档流程
    local Client = require("network.Client")
    Client.Start()

    print("[LocalHost] loopback ready (uid=" .. tostring(LOCAL_UID) .. ")")
end

-- ======================== 停止 ========================

function LocalHost.Stop()
    if Server_ and Server_.Stop then
        -- 正常走存档 flush 路径（LocalDisconnect 前先落盘由 PDM 防抖完成）
        Server_.Stop()
    end
    if mockConn_ then
        Server_ = nil
        mockConn_ = nil
    end
    print("[LocalHost] stopped")
end

return LocalHost
