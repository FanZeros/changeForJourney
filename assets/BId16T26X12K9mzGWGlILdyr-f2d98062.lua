-- ============================================================================
-- loopback_route_test.lua - 验证 LocalHost MockConnection 双向路由（headless）
-- 与 spike 测试的区别：本测试不直调 Server.Local*，而是模拟客户端真实发送路径
--   conn:SendRemoteEvent(REQ_CLIENT_READY) → 路由 → LocalReady → S_InitData/S_ServerList
--   conn:SendRemoteEvent(REQ_ACTION select_server) → 路由 → LocalRequest → 存档加载
-- ============================================================================

local PASS, FAIL = 0, 0
local function check(name, cond, extra)
    if cond then
        PASS = PASS + 1
        print("[ROUTE][PASS] " .. name)
    else
        FAIL = FAIL + 1
        print("[ROUTE][FAIL] " .. name .. (extra and (" — " .. tostring(extra)) or ""))
    end
end

function Start()
    local ok, err = pcall(function()
        local cjson = cjson

        _G.serverCloud = require("network.LocalCloud")
        local Server = require("network.Server")
        Server.LocalBoot()

        -- 捕获服务端推送给客户端的本地事件（mock 路由的下行出口）
        local captured = {}
        local realSendEvent = _G.SendEvent
        _G.SendEvent = function(name, vm)
            local payload = nil
            if vm and vm["Data"] then
                local okJson, data = pcall(cjson.decode, vm["Data"]:GetString() or "")
                if okJson then payload = data end
            end
            captured[#captured + 1] = { name = name, payload = payload }
        end

        local LocalHost = require("network.LocalHost")
        local conn = LocalHost.CreateMockConnection(Server)
        Server.LocalConnect(conn, 1)

        local function makeVM(tbl)
            local vm = VariantMap()
            vm["Data"] = Variant(cjson.encode(tbl))
            return vm
        end

        local function findEvent(name)
            for _, c in ipairs(captured) do
                if c.name == name then return c.payload end
            end
            return nil
        end

        -- 1. 模拟客户端发送 C_Ready（与 Client.sendClientReady 完全同构）
        conn:SendRemoteEvent("C_Ready", true, makeVM({}))

        check("routing: S_InitData pushed", findEvent("S_InitData") ~= nil)
        local list = findEvent("S_ServerList")
        check("routing: S_ServerList pushed", list ~= nil)
        check("routing: server list non-empty", list and list.servers and #list.servers > 0,
            list and list.servers and tostring(#list.servers) or "nil")

        -- 2. 模拟客户端发送选服请求（与 Client.sendAction 完全同构）
        conn:SendRemoteEvent("C_Action", true, makeVM({
            action = "select_server",
            params = { serverId = 11 },
        }))

        local PDM = require("server.character.PlayerDataManager")
        check("routing: PDM loaded after select_server", PDM.IsLoaded(1))
        check("routing: S_SaveResult pushed", findEvent("S_SaveResult") ~= nil)
        check("routing: S_StateUpdate pushed", findEvent("S_StateUpdate") ~= nil)
        local saveResult = findEvent("S_SaveResult")
        check("routing: save status success", saveResult and saveResult.status == "success",
            saveResult and tostring(saveResult.status) or "nil")

        Server.Stop()
        print(string.format("[ROUTE] ===== RESULT: PASS=%d FAIL=%d =====", PASS, FAIL))
    end)
    if not ok then
        print("[ROUTE][ERROR] " .. tostring(err))
        print(string.format("[ROUTE] ===== RESULT: PASS=%d FAIL=%d =====", PASS, FAIL + 1))
    end
    engine:Exit()
end
