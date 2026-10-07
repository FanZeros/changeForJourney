-- 真实持久化专项共享夹具。只读正式Lua资源，原生File/FileSystem只路由测试专用目录。
-- 不加载游戏Boot，不打开/覆盖/删除玩家正式档；GPU和主线页面出口隔离。
local M = {}
M.ROOT = "resource_dungeon_transaction_test_data"
M.SAVE = M.ROOT .. "/save.json"
M.PENDING = M.ROOT .. "/pending.json"
M.EXPECTED = M.ROOT .. "/expected.json"

local function source(name)
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "缺少脚本 " .. name)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

function M.copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = M.copy(child) end
    return out
end

function M.same(actual, expected, label)
    assert(type(actual) == type(expected), label .. "类型")
    if type(expected) ~= "table" then assert(actual == expected, label .. "值") return end
    for key, child in pairs(expected) do M.same(actual[key], child, label .. "/" .. tostring(key)) end
    for key in pairs(actual) do assert(expected[key] ~= nil, label .. "新增 " .. tostring(key)) end
end

function M.read(path)
    assert(path == M.SAVE or path == M.EXPECTED or path == M.PENDING, "禁止读取非测试档")
    local file = File(path, FILE_READ)
    assert(file and file:IsOpen(), "测试文件读取失败 " .. path)
    local text = file:ReadString()
    file:Dispose()
    return text
end

function M.writeExpected(value)
    local file = File(M.EXPECTED, FILE_WRITE)
    assert(file and file:IsOpen(), "测试期望文件打开失败")
    local complete = file:WriteString(cjson.encode(value))
    file:Dispose()
    assert(complete == true, "测试期望文件写入失败")
end

function M.new()
    local h = { failure = "", pushes = 0, events = 0, writeAttempts = 0, renameAttempts = 0,
        committed = false, queue = false, sends = {}, replies = {}, displayed = {} }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.time = { elapsedTime = 20 }
    local nativeFile, nativeFS = File, fileSystem
    local function mapped(path)
        if path == "standalone_save.json" then return M.SAVE end
        if path == "standalone_save.pending.json" then return M.PENDING end
        error("Save试图访问未授权路径 " .. tostring(path))
    end
    env.File = function(path, mode)
        local target = mapped(path)
        if mode == FILE_WRITE then
            h.writeAttempts = h.writeAttempts + 1
            assert(target == M.PENDING, "禁止直接截断旧测试档")
            if h.failure == "open" then
                return nativeFile(M.ROOT .. "/missing-parent/pending.json", mode)
            elseif h.failure == "write" then
                -- 真正只读File句柄，WriteString实际返回失败；不伪造写入结果。
                return nativeFile(M.SAVE, FILE_READ)
            end
        end
        return nativeFile(target, mode)
    end
    env.fileSystem = {
        FileExists = function(_, path) return nativeFS:FileExists(mapped(path)) end,
        Rename = function(_, from, to)
            h.renameAttempts = h.renameAttempts + 1
            local destination = mapped(to)
            if h.failure == "rename" then destination = M.ROOT .. "/missing-parent/save.json" end
            local ok = nativeFS:Rename(mapped(from), destination)
            if ok then h.committed = true end
            return ok
        end,
        Delete = function(_, path) return nativeFS:Delete(mapped(path)) end,
    }
    local function noop() end
    local loaded = {}
    local mocks = {
        ["core.PlayerStore"] = { Get = function(key) return h.Dispatcher.get(key) end },
        ["ui.battle.scene.BattleScene"] = {
            restoreContext = noop, getStageId = function() return 2501 end,
            getMaxStageId = function() return 2501 end, getClearedStages = function() return {} end,
        },
        ["ui.battle.tri.BattleTriPage"] = { getTeamStageId = function() return 2501 end,
            isTerminalRaidActive = function() return false end },
        ["ui.hud.popup.SettingsPanel"] = { isEffectsEnabled = function() return false end },
        ["ui.fx.SpineCardEffect"] = { playRevive = noop },
        ["systems.ButtonFeedback"] = { trigger = noop },
        ["systems.GameSFX"] = setmetatable({}, { __index = function() return noop end }),
        ["ui.loot.LootBoxPage"] = { showToast = noop },
        ["ui.hud.BottomNav"] = { getSelectedIndex = function() return 3 end, setSelectedIndex = noop,
            isAllLocked = function() return false end, isTabLocked = function() return false end },
        ["ui.tower.TowerBattleScene"] = { isActive = function() return false end },
        ["ui.hud.popup.RewardPopup"] = { show = function(_, rewards) h.displayed[#h.displayed + 1] = rewards end },
        ["ui.battle.popup.BattleResultPanel"] = {
            init = noop, update = noop, draw = noop, isOpen = function() return false end,
            show = function(opts) h.displayed[#h.displayed + 1] = opts.rewards end,
        },
    }
    mocks["ui.character.panel.CharacterPanel"] = {
        getActiveTeamIdx = function() return 1 end,
        getOwnedHero = function() return nil end,
        getDeployedTeam = function(team)
            local hero = assert(env.require("config.HeroConfig").createHero(team, 100, nil, {}, {}))
            hero.atkInterval = 100000
            return { hero }
        end,
    }
    mocks["runtime.GameAction"] = { sendAction = function(action, params)
        h.sends[#h.sends + 1] = { action = action, params = params }
        local handler = assert(h.Handler.actionHandlers[action], "未知测试动作")
        local reply = handler(1, params)
        reply.action = action
        h.replies[#h.replies + 1] = reply
        h.Page.onActionResult(reply)
    end }
    env.require = function(name)
        if mocks[name] then return mocks[name] end
        if loaded[name] then return loaded[name] end
        assert(not name:match("^boot%.") or name == "boot.StandaloneSave", "禁止加载游戏Boot")
        assert(name ~= "runtime.LocalActionBridge", "禁止启动正式本地桥")
        if name == "cjson" then return cjson end
        local value = assert(load(source(name), "@transaction/" .. name, "t", env))()
        loaded[name] = value
        return value
    end
    h.env, h.require = env, env.require
    h.Dispatcher = env.require("runtime.ClientDispatcher")
    h.PDM = env.require("rules.character.PlayerDataManager")
    h.GS = env.require("core.GameState")
    h.GS.setLocalPlayerSync(noop)
    h.Service = env.require("rules.dungeon.DungeonService")
    h.Idle = env.require("rules.dungeon.DungeonIdleService")
    h.Handler = env.require("rules.dungeon.DungeonHandler")
    h.Save = env.require("boot.StandaloneSave")
    h.Registry = env.require("shared.ModuleRegistry")
    h.Schema = env.require("shared.schemas.CharacterSchema")
    h.DC = env.require("config.DungeonConfig")
    h.IC = env.require("config.DungeonIdleConfig")
    h.ES = env.require("systems.EquipmentSystem")
    h.Protocol = env.require("shared.Protocol")
    h.PDM.Setup({ serverDispatcher = { pushModule = function(_, name, data)
        if h.queue then h.queue[name] = data return end
        h.pushes = h.pushes + 1
        assert(h.committed, "持久化之前泄露模块通知 " .. name)
        h.Dispatcher.set(name, data)
        if name == "currency" then h.GS.syncFromCurrency(data) end
    end } })
    h.Service.SetPersistCallback(function()
        assert(h.pushes == h.beforePushes and h.events == h.beforeEvents, "真实Flush前不允许通知")
        if h.failure == "false" then return false end
        if h.failure == "nil" then return nil end
        if h.failure == "throw" then error("expected persist exception") end
        return h.Save.Flush()
    end, {
        begin = function() h.queue = {}; h.beforePushes = h.pushes; h.beforeEvents = h.events end,
        finish = function(_, success)
            local pushes = h.queue
            h.queue = false
            if not success then return end
            if type(pushes) ~= "table" then error("提交成功但通知缓存不存在") end
            for name, data in pairs(pushes) do
                h.pushes = h.pushes + 1
                assert(h.committed, "真实Rename之前不能通知 " .. name)
                h.Dispatcher.set(name, data)
                if name == "currency" then h.GS.syncFromCurrency(data) end
            end
        end,
    })
    env.require("core.EventBus").on(env.require("config.GameEvents").CURRENCY_CHANGED,
        function() h.events = h.events + 1 end)
    return h
end

function M.install(h, count)
    local modules = h.Dispatcher.getAll()
    for key in pairs(modules) do modules[key] = nil end
    for _, name in ipairs({ "currency", "heroes", "dungeon", "equipment", "lootbox", "session", "player" }) do
        modules[name] = h.Schema.Fields[name].getDefault()
    end
    modules.currency.gold, modules.currency.gems, modules.currency.arcaneDust = 10, 20, 30
    modules.currency.sweepTicket = 30 -- 一券一场资源扫荡；不靠首通/挂机返券补齐夹具。
    modules.artifacts, modules.talents = {}, {} -- 幸运上下文完整快照，不回读玩家Store。
    modules.heroes.roster = { [1] = { level = 100 }, [2] = { level = 100 }, [3] = { level = 100 } }
    modules.heroes.deployed = { 1, 0, 0, 0 }
    modules.heroes.teams = { { slots = { 1, 0, 0, 0 } }, { slots = { 2, 0, 0, 0 } }, { slots = { 3, 0, 0, 0 } } }
    modules.battle = { currentStageId = 2501, maxStageId = 2501, clearedStages = { ["2305"] = true },
        teamStageIds = { 2501, 1305, 605 } }
    modules.session.lastOnlineTime = os.time() - 300
    modules.dungeon.compat = { monsterBuffV1 = true }
    modules.dungeon.ancient_ruin.floor = 57
    modules.dungeon.ancient_ruin.cleared[56] = true
    modules.dungeon.ancient_ruin.idleAccumSec = 88000
    modules.dungeon.babel_tower.floor = 21
    modules.dungeon.babel_tower.buffs = { 2, 5 }
    for name, data in pairs(modules) do
        h.Registry.applyOnLoad(name, data)
        h.Schema.applyOnLoad(name, data)
    end
    local filler = assert(h.ES.generate("W1", 1, 1))
    for _ = 1, count or 0 do h.ES.addToInventory(modules.equipment, M.copy(filler)) end
    h.GS.syncFromCurrency(modules.currency, { silent = true })
    h.PDM.AttachLocalModules(1, modules)
    h.Service.Cleanup(1)
    h.Idle.Cleanup(1)
    h.Save.OfflineChecked()
    h.failure, h.committed = "", false
    h.queue = {} -- 初始基线写档也先缓存MarkOnline通知，不把它当待测奖励通知。
    assert(h.Save.Flush() == true, "建立真实测试旧档失败")
    h.queue, h.committed = false, false
    return modules
end


return M
