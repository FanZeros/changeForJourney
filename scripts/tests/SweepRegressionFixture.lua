-- 扫荡隔离夹具：真实源码在私有require/math环境执行，不触碰package.loaded或玩家文件。
-- 参考 team_drop_luck_test 与 ResourceDungeonPersistenceFixture；只mock数据/保存/通知边界。
local M = {}

function M.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[key] = M.copy(child, seen) end
    return result
end

function M.equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not M.equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function source(name)
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "缺少真实源码 " .. name)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

function M.new()
    local h = { data = {}, modules = {}, dirty = {}, notifications = 0, events = 0,
        persists = 0, finishes = {}, rngCalls = 0, seed = 17, failure = "", wallet = {}, disk = {} }
    local env = setmetatable({}, { __index = _G })
    env._G, env.math, env.os = env, M.copy(math), M.copy(os)
    env.os.time = function() return 1791200000 end
    env.time = { elapsedTime = 100 }
    env.print = function() end
    env.File = function() error("扫荡专项禁止读写玩家文件") end
    env.fileSystem = { FileExists = function() error("扫荡专项禁止读取玩家存档") end }
    env.package = { loaded = h.modules, preload = {}, path = "" }
    env.math.random = function(a, b)
        h.rngCalls = h.rngCalls + 1
        if h.forbidRNG then error("Preview/拒绝请求消费了RNG") end
        h.seed = (h.seed * 48271) % 2147483647
        local r = h.forceRandom or h.seed / 2147483647
        if a == nil then return r end
        local lo, hi = b == nil and 1 or a, b == nil and a or b
        return lo + math.floor(r * (hi - lo + 1))
    end
    env.math.randomseed = function(seed) h.seed, h.rngCalls = seed, 0 end
    h.modules["rules.character.PlayerDataManager"] = {
        GetModule = function(_, name) return h.data[name] end,
        MarkDirty = function(_, name)
            assert(h.committed, "保存成功前泄露候选通知 " .. name)
            h.dirty[name] = (h.dirty[name] or 0) + 1
            h.notifications = h.notifications + 1
        end,
        FlushImmediate = function() error("禁止绕过事务保存边界") end,
    }
    h.modules["core.PlayerStore"] = { Get = function(name) return h.data[name] end }
    h.modules["runtime.ClientDispatcher"] = { get = function(name) return h.data[name] end }
    h.modules["core.GameState"] = {
        exportSave = function() return M.copy(h.wallet) end,
        syncFromCurrency = function(value, opts)
            h.wallet = M.copy(value)
            if not (opts and opts.silent) then h.events = h.events + 1 end
        end,
    }
    h.modules["shared.ModuleRegistry"] = { find = function(name)
        return h.onLoad and { onLoad = function(data) h.onLoad(name, data) end } or nil
    end }
    h.modules["shared.schemas.CharacterSchema"] = { Fields = {} }
    env.require = function(name)
        if h.modules[name] ~= nil then return h.modules[name] end
        assert(not name:match("^boot%."), "禁止加载正式Boot " .. name)
        if name == "cjson" then return cjson end
        local value = assert(load(source(name), "@sweep-regression/" .. name, "t", env))()
        assert(value ~= nil, "真实模块缺少返回值 " .. name)
        h.modules[name] = value
        return value
    end
    h.env, h.require = env, env.require
    h.Sweep = h.require("rules.sweep.SweepService")
    h.Transaction = h.require("rules.dungeon.DungeonService")
    h.ES = h.require("systems.EquipmentSystem")
    h.LS = h.require("systems.LootBoxSystem")
    h.DC = h.require("config.DungeonConfig")
    h.SC = h.require("config.StageConfig")
    h.ET = h.require("config.ExpTable")
    h.Rewards = h.require("shared.sweep.SweepRewards")
    h.Drop = h.require("systems.DropSystem")
    h.Spawn = h.require("ui.battle.stage.BattleEnemySpawn")
    h.Transaction.SetPersistCallback(function()
        h.persists = h.persists + 1
        assert(h.notifications == h.beforeNotifications and h.events == h.beforeEvents,
            "持久化前通知/货币事件必须保持静默")
        if h.beforePersist then h.beforePersist() end
        if h.failure == "false" then return false end
        if h.failure == "nil" then return nil end
        if h.failure == "throw" then error("expected persist failure") end
        h.disk, h.committed = M.copy(h.data), true
        return true
    end, {
        begin = function()
            h.committed = false
            h.beforeNotifications, h.beforeEvents = h.notifications, h.events
        end,
        finish = function(_, success) h.finishes[#h.finishes + 1] = success end,
    })
    return h
end

function M.install(h, count)
    local bag = { inventory = {}, equipped = {}, nextSeq = 1, settings = {} }
    local filler = assert(h.ES.generate("W1", 1, 1))
    for _ = 1, count or 0 do h.ES.addToInventory(bag, M.copy(filler)) end
    local dungeon = { ancient_ruin = { floor = 57, cleared = { [56] = true }, dailyUsed = 1 },
        babel_tower = { floor = 21, cleared = {}, buffs = { 2, 5 } } }
    for _, id in ipairs(h.DC.RESOURCE_IDS) do
        dungeon[id] = { floor = 2, cleared = { [1] = true }, dailyUsed = 2,
            dailyDay = 20732, idleAccumSec = 86437 }
    end
    local heroes = { roster = {}, deployed = { 1, 0, 0, 0 }, teams = {
        { slots = { 1, 0, 0, 0 } }, { slots = { 2, 0, 3, 0 } }, { slots = { 4, 5, 0, 6 } } } }
    for id = 1, 6 do heroes.roster[id] = { level = 100, exp = 0 } end
    heroes.roster[25] = { level = 100, exp = 0 }
    h.data = { equipment = bag, lootbox = { seeds = {} }, dungeon = dungeon,
        currency = { gold = 40, gems = 20, arcaneDust = 30, sweepTicket = 30 },
        heroes = heroes, player = { level = 200, exp = 0 }, artifacts = {}, talents = {},
        battle = { currentStageId = 1905, maxStageId = 2501,
            clearedStages = { [905] = true, ["1905"] = true, [6705] = true },
            teamStageIds = { 1905, 1905, 1905 }, idleAccumSec = 43217, dropLuck = 0 },
        session = { lastOnlineTime = 1791199700, claimedScenarios = { [82] = true } } }
    h.wallet, h.disk = M.copy(h.data.currency), M.copy(h.data)
    h.dirty, h.notifications, h.events, h.persists, h.finishes = {}, 0, 0, 0, {}
    h.seed, h.rngCalls, h.failure, h.committed = 17, 0, "", false
    h.forbidRNG, h.forceRandom, h.onLoad, h.beforePersist = false, nil, nil, nil
    return h.data
end

return M
