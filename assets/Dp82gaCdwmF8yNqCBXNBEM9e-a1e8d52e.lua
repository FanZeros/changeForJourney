-- ============================================================================
-- loopback_spike_test.lua - 单机回环 Spike 验证（headless，无 UI）
-- 验证链路: LocalBoot → LocalConnect → LocalReady(InitData+ServerList)
--           → select_server → 读档(SaveManager+PDM) → 写档 flush → 落盘 → 重读
-- 运行: .cli/UrhoXRuntime tests/loopback_spike_test.lua -tapcode_dir=<root> -tool_mode
-- ============================================================================

local PASS, FAIL = 0, 0
local function check(name, cond, extra)
    if cond then
        PASS = PASS + 1
        print("[SPIKE][PASS] " .. name)
    else
        FAIL = FAIL + 1
        print("[SPIKE][FAIL] " .. name .. (extra and (" — " .. tostring(extra)) or ""))
    end
end

function Start()
    local ok, err = pcall(function()
        local cjson = cjson

        -- 1. serverCloud 替身（先于 require Server）
        _G.serverCloud = require("network.LocalCloud")
        local LocalCloud = _G.serverCloud

        -- 2. 轻量启动服务端
        local Server = require("network.Server")
        Server.LocalBoot()

        -- 3. MockConnection：记录服务端推送的事件名与载荷
        local Protocol = require("shared.Protocol")
        local pushed = {}          -- { {name, payload} }
        local mockConn = { scene = nil, identity = nil }
        function mockConn:SendRemoteEvent(eventName, _reliable, vm)
            local payload = nil
            if vm and vm["Data"] then
                local okJson, data = pcall(cjson.decode, vm["Data"]:GetString() or "")
                if okJson then payload = data end
            end
            pushed[#pushed + 1] = { name = eventName, payload = payload }
            print("[SPIKE] server push: " .. tostring(eventName))
        end

        Server.LocalConnect(mockConn, 1)

        -- 4. Ready：应推送 RES_INIT_DATA + RES_SERVER_LIST（中间可能夹带 ActionResult 诊断）
        Server.LocalReady(mockConn)
        local names = {}
        local listPayload = nil
        for _, p in ipairs(pushed) do
            names[#names + 1] = p.name
            if p.name == Protocol.RES_SERVER_LIST then
                listPayload = p.payload
            end
        end
        check("LocalReady pushed RES_INIT_DATA", names[1] == Protocol.RES_INIT_DATA, table.concat(names, ","))
        check("LocalReady pushed RES_SERVER_LIST", listPayload ~= nil, table.concat(names, ","))
        check("ServerList has servers", listPayload and listPayload.servers and #listPayload.servers > 0)

        -- 5. 选服 → finishSelectServer → SaveManager 全局读档 + PDM 批量读档
        Server.LocalRequest(mockConn, Protocol.ACTION_TYPES.SELECT_SERVER, { serverId = 11 })

        check("SaveManager.isLoaded(1)", Server and require("server.SaveManager").isLoaded(1))
        local SaveManager = require("server.SaveManager")
        local PDM = require("server.character.PlayerDataManager")
        check("PDM.IsLoaded(1)", PDM.IsLoaded(1))
        check("PDM battle module", type(PDM.GetModule(1, "battle")) == "table")
        check("PDM currency module", type(PDM.GetModule(1, "currency")) == "table")
        check("PDM heroes module", type(PDM.GetModule(1, "heroes")) == "table")

        -- 6. 模拟业务写入：改货币 + MarkDirty
        local currency = PDM.GetModule(1, "currency")
        check("currency.gold is number", type(currency.gold) == "number", tostring(currency.gold))
        print("[SPIKE] gold after load = " .. tostring(currency.gold)
            .. "（第 1 次运行应为 0；再次运行应为 12345，即重启恢复）")
        currency.gold = 12345
        PDM.MarkDirty(1, "currency")

        -- 7. 停服 → PDM.Shutdown flush → LocalCloud 落盘
        Server.Stop()

        -- 8. 直接读取已知落盘文件验证（PDM: s11_mod_currency.json / SaveManager: global_profile.json）
        LocalCloud.ClearCache()
        local function readJson(path)
            local f = File(path, FILE_READ)
            if not f or not f:IsOpen() then return nil end
            local raw = f:ReadString()
            f:Close()
            local okJson, data = pcall(cjson.decode, raw or "")
            if okJson then return data end
            return nil
        end

        local currencyFile = readJson("saves/cloud/1/s11_mod_currency.json")
        check("currency module persisted to disk", currencyFile ~= nil)
        check("persisted currency.gold == 12345",
            type(currencyFile) == "table" and type(currencyFile.currency) == "table"
                and currencyFile.currency.gold == 12345,
            currencyFile and type(currencyFile.currency) == "table" and tostring(currencyFile.currency.gold) or "nil")
        check("persisted _meta.lastSaveTime",
            type(currencyFile) == "table" and type(currencyFile._meta) == "table"
                and currencyFile._meta.lastSaveTime ~= nil)

        local gpFile = readJson("saves/cloud/1/global_profile.json")
        check("global_profile persisted (SaveManager path)",
            type(gpFile) == "table" and type(gpFile.global_profile) == "table"
                and gpFile.global_profile.lastServerId == 11)

        print(string.format("[SPIKE] ===== RESULT: PASS=%d FAIL=%d =====", PASS, FAIL))
    end)
    if not ok then
        print("[SPIKE][ERROR] " .. tostring(err))
        FAIL = FAIL + 1
        print(string.format("[SPIKE] ===== RESULT: PASS=%d FAIL=%d =====", PASS, FAIL))
    end
    engine:Exit()
end
