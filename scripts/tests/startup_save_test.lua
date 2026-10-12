-- 存档分帧检测专项：真实 StandaloneSave 源码/原生 cjson，File/FileSystem 全内存。
-- 不加载 Boot，不读取/修改玩家档。-save-baseline 仅统计旧版序列化热点，不运行新版断言。
local TAG = "[startup_save_test]"
local assertions, failures, cases, harnessErrors = 0, 0, 0, 0
local baseline, firstScanOnly = false, false
for _, arg in ipairs(GetArguments()) do
    if arg == "-save-baseline" then baseline = true end
    if arg == "-save-firstscan-only" then firstScanOnly = true end
end
local function check(value, label)
    assertions = assertions + 1
    if not value then failures = failures + 1; print(TAG .. " FAIL " .. label) end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function run(label, fn)
    cases = cases + 1
    local ok, err = pcall(fn)
    if not ok then harnessErrors = harnessErrors + 1; check(false, label .. ": " .. tostring(err)) end
    print(TAG .. " CASE " .. label)
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, item in pairs(a) do if not same(item, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function source(path)
    local file = assert(cache:GetFile(path), "missing source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function upvalue(fn, name)
    for index = 1, 100 do
        local found, value = debug.getupvalue(fn, index)
        if not found then break end
        if found == name then return value end
    end
end
local saveSource = ""
local Schema
local function fixture(count)
    local f = { now = 200000, pending = false, fault = "", disk = {}, encodes = 0,
        encodeMs = 0, writes = 0, renames = 0, captures = 0, exports = 0, steps = 0,
        clockQueries = 0, slowClock = false, clockValue = 0, captureFault = false,
        maxStage = 2501, ledger = {}, live = nil, onRename = nil, onWrite = nil,
        handles = 0, closes = 0, disposes = 0, activeHandles = 0, onClose = nil,
        onSnapshot = nil, onExport = nil }
    f.modules = { session = { lastOnlineTime = 199000, firstLoginTime = 100 },
        currency = { gold = 20 }, heroes = { roster = { [1] = { level = 100, exp = 1 },
            [25] = { level = 70, exp = 4 } }, deployed = { 1, 0, 25, 0 } },
        battle = { currentStageId = 2501, maxStageId = 2501, clearedStages = { ["1905"] = true },
            teamStageIds = { ["1"] = 2501, ["2"] = 1501, ["3"] = 1901 } },
        equipment = { inventory = {} }, dungeon = { tower = { cleared = { ["1"] = true } } },
        lootbox = { seeds = {} } }
    f.state = { gold = 20, level = 100, exp = 2 }
    -- 数据形状来自真实 EquipmentSystem.generate，不把空/极简表当大库存证据。
    local ES = require("systems.EquipmentSystem")
    local item = assert(ES.generate("W1", 1, 1))
    item.affixes = { { key = "STR", value = 0.123456789, quality = 4 },
        { key = "VIT", value = 10, quality = 2 }, { key = "ATK_SPEED", value = 3.1, quality = 3 } }
    item.ascendLevel, item.affixMult = 12, 1.2
    for i = 1, count or 0 do
        local equipment = copy(item)
        equipment.seq, equipment.locked = tostring(i), i % 3 == 0
        f.modules.equipment.inventory[tostring(i)] = equipment
    end
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.os = { time = function() return f.now end, date = os.date,
        clock = function()
            f.clockQueries = f.clockQueries + 1
            if f.slowClock then f.clockValue = f.clockValue + 0.0006 return f.clockValue end
            return os.clock()
        end }
    env.cjson = { encode = function(value)
        f.encodes = f.encodes + 1
        if f.fault == "encode" then error("expected encode failure") end
        local started = os.clock()
        local json = cjson.encode(value)
        f.encodeMs = f.encodeMs + (os.clock() - started) * 1000
        return json
    end, decode = cjson.decode }
    env.next = function(value, key) f.steps = f.steps + 1; return next(value, key) end
    local function allowed(path)
        assert(path == "standalone_save.json" or path == "standalone_save.pending.json", "unexpected save path")
    end
    env.File = function(path, mode)
        allowed(path)
        if f.fault == "open-throw" and mode == FILE_WRITE then error("expected open throw") end
        f.handles, f.activeHandles = f.handles + 1, f.activeHandles + 1
        local disposed = false
        return { IsOpen = function()
                if f.fault == "isopen-throw" then error("expected IsOpen throw") end
                return not (mode == FILE_WRITE and f.fault == "open")
            end,
            ReadString = function() return f.disk[path] end,
            Close = function()
                f.closes = f.closes + 1
                if f.fault == "close-throw" then error("expected Close throw") end
                if f.onClose then f.onClose() end
                if f.fault == "close-false" then return false end
            end,
            Dispose = function()
                assert(not disposed, "file disposed twice")
                disposed = true
                f.disposes, f.activeHandles = f.disposes + 1, f.activeHandles - 1
                if f.fault == "dispose-throw" then error("expected Dispose throw") end
            end,
            WriteString = function(_, text)
                f.writes = f.writes + 1
                if f.fault == "write-throw" then error("expected write throw") end
                f.disk[path] = f.fault == "write" and text:sub(1, 7) or text
                if f.onWrite then f.onWrite() end
                return f.fault ~= "write"
            end }
    end
    env.fileSystem = { FileExists = function(_, path) allowed(path); return f.disk[path] ~= nil end,
        Delete = function(_, path)
            allowed(path)
            if f.fault == "delete-throw" then error("expected Delete throw") end
            f.disk[path] = nil return true
        end,
        Rename = function(_, from, to)
            allowed(from); allowed(to); f.renames = f.renames + 1
            if f.fault == "rename-throw" then error("expected rename throw") end
            if f.fault == "rename" then return false end
            f.disk[to], f.disk[from] = f.disk[from], nil
            if f.onRename then f.onRename() end
            return true
        end }
    local mocks = {
        ["runtime.ClientDispatcher"] = { get = function(name) return f.modules[name] end,
            snapshotAll = function()
                if f.onSnapshot then f.onSnapshot() end
                return f.modules
            end,
            handleStateUpdate = function(json)
                for name, data in pairs(cjson.decode(json).modules) do f.modules[name] = data end
            end },
        ["core.GameState"] = { exportSave = function()
                f.exports = f.exports + 1
                if f.onExport then f.onExport() end
                return copy(f.state)
            end,
            importSave = function(value) f.state = copy(value or {}) end, syncPlayerData = function() end },
        ["ui.battle.scene.BattleScene"] = { getMaxStageId = function() return f.maxStage end,
            getClearedStages = function() return f.ledger end, setBattleData = function() end },
        ["shared.battle.BattleSchema"] = Schema,
        ["rules.offline.OfflineService"] = { HasPendingRewards = function() return f.pending end,
            MarkOnline = function()
                if not f.pending and f.modules.session and f.now > f.modules.session.lastOnlineTime then
                    f.modules.session.lastOnlineTime = f.now
                end
            end },
    }
    env.require = function(name) return mocks[name] or require(name) end
    f.save = assert(load(saveSource, "@startup-save/StandaloneSave.lua", "t", env))()
    f.page = { getTeamStageIds = function()
        if f.captureFault then error("expected capture failure") end
        return f.live
    end, setTeamStageIds = function(ids) f.live = copy(ids) end }
    f.save.SetBattlePage(f.page)
    f.env = env
    local capture = f.save.CaptureBattleProgress
    f.save.CaptureBattleProgress = function(value) f.captures = f.captures + 1 return capture(value) end
    function f.update(dt)
        local started = os.clock()
        f.save.Update(dt or 1 / 60)
        return (os.clock() - started) * 1000
    end
    function f.saved() return cjson.decode(assert(f.disk["standalone_save.json"])) end
    function f.ready()
        if not upvalue(f.save.Update, "detectorScan") then f.update(1) end
        for i = 1, 20000 do
            if not upvalue(f.save.Update, "detectorScan") then return i end
            f.update()
        end
        error("detector did not finish")
    end
    function f.settle()
        for _ = 1, 20000 do
            f.update()
            if not upvalue(f.save.Update, "detectorScan") and not f.timer() then return end
        end
        error("detector/debounce did not settle")
    end
    function f.untilWrite(limit)
        local before = f.writes
        for i = 1, limit or 3000 do
            f.update()
            if f.writes > before then return i end
        end
        error("change was not persisted")
    end
    function f.timer() return upvalue(f.save.Update, "flushTimer") end
    return f
end

local function firstScanUnvisitedTest()
    for _, mode in ipairs({ "OfflineChecked", "RestoreData" }) do
        run("business first scan previously unvisited locked " .. mode, function()
            local f = fixture(1000)
            local oldJson = cjson.encode({ version = 1, savedAt = 199000,
                gameState = f.state, modules = f.modules })
            f.disk["standalone_save.json"] = oldJson
            if mode == "RestoreData" then eq(f.save.RestoreData(), true, "restore saved business state")
            else f.save.OfflineChecked() end
            f.slowClock = true
            f.update(1)
            check(upvalue(f.save.Update, "detectorScan") ~= nil, "business first scan is suspended")
            local advance = upvalue(f.save.Update, "advanceDetector")
            local snapshot = advance and upvalue(advance, "detectorSnapshot")
            local inventory = snapshot and snapshot.modules and snapshot.modules.equipment
                and snapshot.modules.equipment.inventory
            local key = nil
            for candidate, equipment in pairs(f.modules.equipment.inventory) do
                local prior = inventory and inventory[candidate]
                if not prior or rawget(prior, "locked") == nil then key = candidate break end
            end
            check(key ~= nil, "locked key really not previously observed")
            local before = f.modules.equipment.inventory[key].locked
            f.modules.equipment.inventory[key].locked = not before
            local expected = not before
            f.slowClock = false
            local frames = 0
            for i = 1, 3000 do
                f.update()
                local json = f.disk["standalone_save.json"]
                if json ~= oldJson and cjson.decode(json).modules.equipment.inventory[key].locked == expected then
                    frames = i; break
                end
            end
            check(frames > 0, "unvisited stable locked mutation actually persisted")
            eq(f.saved().modules.equipment.inventory[key].locked, expected,
                "fresh serialized locked value, not detector baseline")
            f.settle()
            local writes, encodes = f.writes, f.encodes
            for _ = 1, 1200 do f.update() end
            eq(f.writes, writes, "business baseline no perpetual writes after settle")
            eq(f.encodes, encodes, "business static twenty seconds no periodic JSON")
            print(TAG .. " FIRST_UNVISITED mode=" .. mode .. " savedAfterFrames=" .. frames
                .. " initialWrites=" .. writes)
        end)
    end
end

function Start()
    Schema = require("shared.battle.BattleSchema")
    saveSource = source(baseline and "tests/StandaloneSave.baseline.lua" or "boot/StandaloneSave.lua")
    if not baseline then firstScanUnvisitedTest() end
    if firstScanOnly then
        print(string.format("%s FIRSTSCAN_SUMMARY cases=%d assertions=%d failures=%d harnessErrors=%d",
            TAG, cases, assertions, failures, harnessErrors))
        if failures > 0 then log:Write(LOG_ERROR, TAG .. " FIRSTSCAN FAILED") end
        engine:Exit()
        return
    end
    if not baseline then
        run("baseline idle / raw in-place mutation", function()
            local f = fixture(20)
            local before = copy(f.modules)
            f.ready()
            for _ = 1, 600 do f.update() end
            eq(f.encodes, 0, "idle polling never encodes")
            eq(f.captures, 0, "idle polling never captures full battle ledger")
            eq(f.writes, 0, "first baseline does not save")
            check(same(f.modules, before), "detector must be source-read-only")
            f.modules.equipment.inventory["20"].affixes[1].value = 9.25
            local frames = f.untilWrite()
            check(frames <= 1865, "small tree mutation <=1s scan wait +30s merge +frames")
            eq(f.saved().modules.equipment.inventory["20"].affixes[1].value, 9.25, "in-place unnotified affix saved")
            eq(f.encodes, 1, "one fresh encode for save")
            eq(f.captures, 1, "full capture only for save")
            for _ = 1, 600 do f.update() end
            eq(f.writes, 1, "stable scan has no recurring write loop")
        end)
        run("RequestSave bounded thirty-second merge and quiet zero writes", function()
            local f = fixture(10); f.ready()
            for _ = 1, 3600 do f.update() end
            eq(f.writes, 0, "quiet sixty seconds no periodic writes")
            eq(f.encodes, 0, "quiet sixty seconds no periodic JSON")
            eq(f.save.RequestSave(), nil, "request is not transaction success")
            eq(f.timer(), 30, "first request establishes thirty-second deadline")
            f.update(1.75)
            eq(f.writes, 0, "two-second update budget still before merge deadline")
            f.update(0.25)
            eq(f.writes, 0, "second two does not retain obsolete debounce save")
            -- 剩余期限只由Update真实dt消耗；负数/非有限dt不能提前或延后。
            local timer = f.timer()
            f.save.Update(-100); f.save.Update(0 / 0); f.save.Update(math.huge)
            eq(f.timer(), timer, "invalid frame time cannot alter merge deadline")
            -- 上面已消耗2秒，继续变更至总30秒。
            for second = 3, 29 do
                f.modules.currency.gold = second
                f.save.RequestSave()
                f.update(1)
                eq(f.writes, 0, "continuous updates do not write early " .. second)
                eq(f.timer(), 30 - second, "continuous requests cannot postpone deadline " .. second)
            end
            f.modules.currency.gold = 30; f.save.RequestSave(); f.update(1)
            eq(f.writes, 1, "continuous changes save at thirty seconds")
            eq(f.saved().modules.currency.gold, 30, "merged save captures latest value")
            eq(f.encodes, 1, "thirty requests have one encode")
            eq(f.activeHandles, 0, "merged write releases native-shaped object")
            f.settle()
            local writes, encodes = f.writes, f.encodes
            for _ = 1, 3600 do f.update() end
            eq(f.writes, writes, "stable after settle has no recurring writes")
            eq(f.encodes, encodes, "stable after settle has no recurring encoding")
        end)
        run("detector-only continuous mutations never extend merge window", function()
            local f = fixture(4); f.ready()
            f.modules.currency.gold = 31
            for _ = 1, 120 do f.update() end
            check(f.timer() ~= nil, "in-place fallback detects ordinary change")
            local deadline = f.timer()
            local seconds = math.floor(deadline)
            for second = 1, seconds do
                f.modules.currency.gold = 100 + second
                f.update(1)
            end
            if f.writes == 0 then f.update(1) end
            eq(f.writes, 1, "detector changes cannot starve maximum deadline")
            eq(f.saved().modules.currency.gold, 100 + seconds, "fallback commits current source")
        end)
        run("Flush remains immediate candidate transaction with pending ordinary request", function()
            local f = fixture(3); f.ready(); f.save.RequestSave(); f.update(5)
            f.state.exp = 7
            local candidate = { level = 100, exp = 88, maxExp = 1000, name = "candidate" }
            eq(f.save.Flush(candidate), true, "immediate Flush does not wait thirty seconds")
            eq(f.writes, 1, "immediate Flush writes once")
            eq(f.saved().gameState.exp, 88, "candidate experience persisted in same transaction")
            eq(f.saved().modules.player.exp, 88, "candidate player mirror persisted")
            eq(f.state.exp, 7, "candidate does not prematurely publish live experience")
            eq(f.timer(), nil, "committed pending request cleared")
            eq(f.activeHandles, 0, "immediate Flush object released")
        end)
        run("adds deletes types strings numeric keys", function()
            local f = fixture(6); f.ready()
            f.modules.equipment.inventory["2"] = nil
            f.modules.equipment.inventory["6"].locked = false
            f.modules.equipment.inventory["new"] = { seq = "new", nested = { value = 8 }, list = { [1] = 3, [5] = 7 } }
            f.modules.dungeon = { floor = 2, flag = false }
            ---@type table
            local extra = { ["0"] = "text", [0] = 5, nested = { false, true } }
            f.modules.extra = extra
            f.modules.currency = nil
            f.state.gold = 41
            f.untilWrite()
            local data = f.saved()
            eq(data.modules.equipment.inventory["2"], nil, "removed inventory saved")
            eq(data.modules.equipment.inventory["6"].locked, false, "false is not missing")
            eq(data.modules.equipment.inventory.new.nested.value, 8, "new nested record")
            eq(data.modules.dungeon.floor, 2, "whole module replacement")
            eq(data.modules.currency, nil, "whole module removal")
            eq(data.gameState.gold, 41, "GameState mutation without dispatcher version")
            eq(data.modules.heroes.roster.h25.exp, 4, "roster h-prefix unchanged")
            eq(data.modules.heroes.deployed[2], 0, "empty party position unchanged")
            rawset(f.modules.extra, "nested", 13)
            f.untilWrite()
            eq(f.saved().modules.extra.nested, 13, "table to scalar")
            rawset(f.modules.extra, "nested", { x = 14 })
            f.untilWrite()
            eq(f.saved().modules.extra.nested.x, 14, "scalar to table")
        end)
        run("first scan already read key mutates and module replacement", function()
            local f = fixture(1500); f.slowClock = true
            local foundKey = nil
            for i = 1, 50000 do
                f.update(i == 1 and 1 or 1 / 60)
                local advance = upvalue(f.save.Update, "advanceDetector")
                local snapshot = advance and upvalue(advance, "detectorSnapshot")
                local inventory = snapshot and snapshot.modules and snapshot.modules.equipment
                    and snapshot.modules.equipment.inventory
                if inventory then
                    for key, equipment in pairs(inventory) do
                        if type(equipment.affixes) == "table" and equipment.affixes[1]
                            and equipment.affixes[1].value ~= nil then foundKey = key break end
                    end
                end
                if foundKey then break end
            end
            check(foundKey ~= nil, "find actually already-read first-scan scalar")
            local scan = upvalue(f.save.Update, "detectorScan")
            check(scan ~= nil, "first scan still active when mutate")
            f.modules.equipment.inventory[foundKey].affixes[1].value = 912.5
            f.modules.dungeon = { firstScanReplacement = 17 }
            f.slowClock = false
            local frames = f.untilWrite(4000)
            eq(f.saved().modules.equipment.inventory[foundKey].affixes[1].value, 912.5,
                "first baseline subsequent stable change not lost")
            eq(f.saved().modules.dungeon.firstScanReplacement, 17, "first scan module replacement current on Flush")
            print(TAG .. " FIRST_SCAN_MUTATION inventory=1500 framesAfterMutation=" .. frames)
        end)
        run("fresh flush during scan; no half snapshot", function()
            local f = fixture(1000); f.ready()
            f.slowClock = true; f.update(1)
            check(upvalue(f.save.Update, "detectorScan") ~= nil, "forced in-flight scan")
            f.modules.equipment.inventory["1000"].affixes[3].value = 777
            f.state.exp = 1234
            eq(f.save.Flush(), true, "immediate transaction flush")
            eq(f.saved().modules.equipment.inventory["1000"].affixes[3].value, 777, "unvisited tail fresh at Flush")
            eq(f.saved().gameState.exp, 1234, "fresh GameState at Flush")
            eq(f.encodes, 1, "Flush exactly one JSON")
            f.slowClock = false
            for _ = 1, 2400 do f.update() end
            check(f.encodes <= 2, "at most conservative resave, no polling JSON")
        end)
        run("deleted live cursor / batch removal / replaced nested table", function()
            local f = fixture(1200)
            f.slowClock = true
            local removed = false
            for i = 1, 50000 do
                f.update(i == 1 and 1 or 1 / 60)
                local scan = upvalue(f.save.Update, "detectorScan")
                if scan then
                    for _, frame in ipairs(scan.stack) do
                        if frame.phase == 2 and frame.source == f.modules.equipment.inventory and frame.key ~= nil then
                            f.modules.equipment.inventory[frame.key] = nil
                            removed = true
                            break
                        end
                    end
                end
                if removed then break end
            end
            check(removed, "delete actual suspended next cursor")
            f.slowClock = false; f.ready()
            for i = 1, 900 do f.modules.equipment.inventory[tostring(i)] = nil end
            f.modules.equipment.inventory["1200"] = { seq = "1200", affixes = { { value = 88 } } }
            f.untilWrite(3000)
            eq(f.saved().modules.equipment.inventory["1200"].affixes[1].value, 88, "tail replacement saved")
            eq(f.saved().modules.equipment.inventory["1"], nil, "batch removal saved")
        end)
        run("online own update does not retrigger; pending existing boundary", function()
            local f = fixture(10)
            f.save.OfflineChecked(); f.ready(); f.settle()
            local beforeWrites = f.writes
            f.modules.currency.gold = 22; f.untilWrite()
            eq(f.saved().savedAt, f.now, "savedAt online boundary")
            eq(f.saved().modules.session.lastOnlineTime, f.now, "lastOnline boundary")
            f.now = f.now + 10
            for _ = 1, 600 do f.update() end
            eq(f.writes, beforeWrites + 1, "own online timestamp does not perpetually dirty")
            local p = fixture(1)
            eq(p.save.Flush(), true, "existing precheck Flush compatibility retained")
            eq(p.saved().savedAt, 0, "precheck savedAt freeze")
            eq(p.saved().modules.session.lastOnlineTime, 199000, "precheck online freeze")
            p.save.OfflineChecked(); p.pending = true; p.modules.currency.gold = 99
            eq(p.save.Flush(), true, "existing pending Flush not newly rejected")
            eq(p.saved().savedAt, 0, "pending savedAt freeze")
            eq(p.saved().modules.session.lastOnlineTime, 199000, "pending online freeze")
            eq(p.saved().modules.currency.gold, 99, "existing pending write is not falsely called full freeze")
        end)
        run("failure atomic boolean rollback retry fresh", function()
            for _, fault in ipairs({ "encode", "open", "open-throw", "isopen-throw", "write", "write-throw",
                "close-throw", "close-false", "dispose-throw", "rename", "rename-throw", "capture" }) do
                local f = fixture(4); f.save.OfflineChecked(); f.ready(); f.save.Flush()
                local disk, online = f.disk["standalone_save.json"], f.modules.session.lastOnlineTime
                f.now = f.now + 30; f.modules.currency.gold = 55
                f.fault, f.captureFault = fault, fault == "capture"
                local ok, result = pcall(f.save.Flush)
                eq(ok, true, "failure contained " .. fault); eq(result, false, "failure boolean " .. fault)
                eq(f.disk["standalone_save.json"], disk, "old file byte identical " .. fault)
                eq(f.modules.session.lastOnlineTime, online, "online rollback " .. fault)
                eq(f.disk["standalone_save.pending.json"], nil, "failed temp cleanup " .. fault)
                eq(f.activeHandles, 0, "all file objects released " .. fault)
                eq(f.timer(), 2, "failed commit retry in two seconds " .. fault)
                f.fault, f.captureFault = "", false
                f.modules.currency.gold = 66
                f.save.RequestSave()
                f.update(1)
                eq(f.disk["standalone_save.json"], disk, "no early retry " .. fault)
                eq(f.timer(), 1, "ordinary requests cannot extend retry " .. fault)
                f.update(1)
                eq(f.saved().modules.currency.gold, 66, "retry current not stale " .. fault)
                eq(f.saved().savedAt, f.now, "retry boundary current " .. fault)
                eq(f.activeHandles, 0, "successful retry releases file " .. fault)
            end
        end)
        run("write cleanup errors contained and lifecycle invalidates old commit", function()
            local f = fixture(3); f.save.OfflineChecked(); eq(f.save.Flush(), true, "establish cleanup baseline")
            local disk, online = f.disk["standalone_save.json"], f.modules.session.lastOnlineTime
            f.now = f.now + 30; f.modules.currency.gold = 45
            f.fault = "delete-throw"
            f.env.fileSystem.Rename = function() return false end
            eq(f.save.Flush(), false, "cleanup throw cannot escape failed commit")
            eq(f.disk["standalone_save.json"], disk, "cleanup failure preserves committed file")
            eq(f.modules.session.lastOnlineTime, online, "cleanup failure restores online boundary")
            eq(f.activeHandles, 0, "cleanup failure still releases file")
            eq(f.timer(), 2, "cleanup failure retains two-second retry")

            for _, phase in ipairs({ "write", "close" }) do
                for _, lifecycle in ipairs({ "Wipe", "RestoreData" }) do
                    local g = fixture(3); g.save.OfflineChecked(); g.save.Flush(); g.settle()
                    local original = g.disk["standalone_save.json"]
                    local baselineWrites = g.writes
                    g.now = g.now + 30; g.modules.currency.gold = 70
                    local invoked = false
                    local function invalidate()
                        if invoked then return end
                        invoked = true
                        g.onWrite, g.onClose = nil, nil
                        if lifecycle == "Wipe" then
                            g.save.Wipe(); g.modules = {}; g.state = {}
                        else
                            eq(g.save.RestoreData(), true, "restore from committed old bytes during " .. phase)
                        end
                    end
                    if phase == "write" then g.onWrite = invalidate else g.onClose = invalidate end
                    eq(g.save.Flush(), false, "old commit rejected after " .. lifecycle .. " at " .. phase)
                    eq(g.activeHandles, 0, "invalidated commit file released " .. lifecycle .. phase)
                    eq(g.timer(), nil, "old retry does not rearm new lifecycle " .. lifecycle .. phase)
                    eq(g.disk["standalone_save.pending.json"], nil, "invalidated pending removed " .. lifecycle .. phase)
                    if lifecycle == "Wipe" then
                        eq(g.disk["standalone_save.json"], nil, "wiped archive not resurrected " .. phase)
                        for _ = 1, 2100 do g.update() end
                        eq(g.writes, baselineWrites + 1, "old wipe task never writes again " .. phase)
                    else
                        eq(g.disk["standalone_save.json"], original, "restore keeps old committed bytes " .. phase)
                        eq(g.modules.currency.gold, 20, "restore keeps old balance " .. phase)
                        eq(g.modules.session.lastOnlineTime, 200000, "old failure cannot overwrite restored online " .. phase)
                    end
                end
            end
        end)
        run("recursive Flush rejected and new request survives commit", function()
            local f = fixture(2); f.ready(); f.save.RequestSave()
            f.onWrite = function()
                f.onWrite = nil
                eq(f.save.Flush(), false, "nested Flush never claims success")
                f.save.Update(100)
                f.modules.currency.gold = 456
                f.save.RequestSave()
            end
            eq(f.save.Flush(), true, "outer synchronous commit succeeds")
            eq(f.writes, 1, "nested writer cannot truncate shared pending file")
            eq(f.saved().modules.currency.gold, 20, "outer commit remains encoded candidate")
            check(f.timer() ~= nil and f.timer() <= 30, "during-write request remains bounded pending")
            f.update(30)
            eq(f.saved().modules.currency.gold, 456, "subsequent request captures fresh data")
            eq(f.activeHandles, 0, "all nested-guard objects released")
        end)
        run("commit scalar receipt stable cursor and callback changes", function()
            -- Flush可先于下一轮检测；提交过的顶层余额/删除不应再安排第二次写盘。
            local stable = fixture(2); stable.ready()
            stable.modules.currency.oldField = 8; stable.ready(); stable.settle()
            stable.slowClock = true; stable.update(1)
            local scan = upvalue(stable.save.Update, "detectorScan")
            local advance = upvalue(stable.save.Update, "advanceDetector")
            local mirror = advance and upvalue(advance, "detectorSnapshot")
            check(scan ~= nil and mirror.modules.currency.oldField == 8, "real mirror and suspended scan exist")
            -- 定点模拟此合法phase1状态，验证提交维护删除键不留下失效next cursor。
            scan.stack = { scan.stack[1], { source = stable.modules.currency, snapshot = mirror.modules.currency,
                phase = 1, key = "oldField" } }
            stable.modules.currency.oldField = nil
            stable.modules.currency.gold = 30; stable.state.gold = 30
            local stableWrites = stable.writes
            eq(stable.save.Flush(), true, "flush before detector observes final scalar/deletion")
            stable.slowClock = false; stable.settle()
            local writes, encodes = stable.writes, stable.encodes
            for _ = 1, 3600 do stable.update() end
            eq(stable.writes, stableWrites + 1, "committed stable scalar/deletion never needs conservative rewrite")
            eq(stable.writes, writes, "committed stable sixty seconds zero extra writes")
            eq(stable.encodes, encodes, "committed stable sixty seconds zero extra encoding")
            eq(stable.saved().modules.currency.oldField, nil, "deleted scalar actually committed")

            for _, mode in ipairs({ "new", "aba", "replace" }) do
                local f = fixture(2); f.ready()
                f.slowClock = true; f.update(1)
                check(upvalue(f.save.Update, "detectorScan") ~= nil, "callback starts with suspended scan " .. mode)
                f.modules.currency.gold = 30; f.state.gold = 30
                f.onRename = function()
                    f.onRename = nil
                    if mode == "replace" then
                        f.modules.currency = { gold = 20 }
                    else
                        f.modules.currency.gold = mode == "aba" and 20 or 123
                    end
                    f.state.gold = mode == "new" and 456 or 20
                end
                eq(f.save.Flush(), true, "callback cannot invalidate completed commit " .. mode)
                eq(f.saved().modules.currency.gold, 30, "disk has pre-callback currency " .. mode)
                eq(f.saved().gameState.gold, 30, "disk has pre-callback GameState " .. mode)
                check(f.timer() ~= nil, "unnotified callback change remains pending including ABA " .. mode)
                f.slowClock = false; f.update(30)
                eq(f.saved().modules.currency.gold, mode == "new" and 123 or 20, "callback currency later fresh " .. mode)
                eq(f.saved().gameState.gold, mode == "new" and 456 or 20, "callback GameState later fresh " .. mode)
                eq(f.activeHandles, 0, "callback receipt objects released " .. mode)
            end
        end)
        run("Rename success is commit point despite later lifecycle reset", function()
            for _, lifecycle in ipairs({ "Wipe", "RestoreData" }) do
                local f = fixture(2); f.save.OfflineChecked(); eq(f.save.Flush(), true, "commit-point initial save")
                local writes = f.writes
                f.now = f.now + 30; f.modules.currency.gold = 44
                local invoked = false
                f.onRename = function()
                    f.onRename = nil; invoked = true
                    -- 内存后端已把候选替换到主档，再执行新生命周期。
                    eq(f.saved().modules.currency.gold, 44, "candidate already durable before " .. lifecycle)
                    if lifecycle == "Wipe" then
                        f.save.Wipe(); f.modules = {}; f.state = {}
                    else
                        eq(f.save.RestoreData(), true, "post-Rename restore succeeds")
                    end
                end
                eq(f.save.Flush(), true, "successful Rename cannot become false after " .. lifecycle)
                check(invoked, "actual post-Rename lifecycle callback executed " .. lifecycle)
                eq(f.writes, writes + 1, "one candidate write despite lifecycle reset " .. lifecycle)
                eq(f.timer(), nil, "committed old writer never rearms retry " .. lifecycle)
                eq(f.activeHandles, 0, "commit-point lifecycle file released " .. lifecycle)
                eq(f.disk["standalone_save.pending.json"], nil, "committed pending consumed " .. lifecycle)
                local laterWrites = f.writes
                if lifecycle == "Wipe" then
                    eq(f.disk["standalone_save.json"], nil, "later wipe stays deleted")
                    for _ = 1, 2100 do f.update() end
                    eq(f.writes, laterWrites, "old successful writer cannot resurrect wiped archive")
                else
                    eq(f.modules.currency.gold, 44, "restore uses committed candidate not pre-write balance")
                    eq(f.modules.session.lastOnlineTime, f.now, "committed boundary not rolled back after restore")
                    eq(f.saved().savedAt, f.now, "savedAt remains actual commit boundary")
                end
            end
        end)
        run("post-commit reconcile lifecycle cannot mutate new detector", function()
            for _, phase in ipairs({ "snapshot", "export" }) do
                for _, lifecycle in ipairs({ "Wipe", "RestoreData" }) do
                    local f = fixture(2); f.ready(); eq(f.save.Flush(), true, "reconcile lifecycle initial commit")
                    f.modules.currency.gold = 44
                    ---@type table|nil
                    local replacementScan = nil
                    ---@type table|nil
                    local replacementSource = nil
                    ---@type number|nil
                    local replacementTimer = nil
                    local invoked = false
                    f.onRename = function()
                        f.onRename = nil
                        local function resetAfterCommit()
                            if invoked then return end
                            invoked = true; f.onSnapshot, f.onExport = nil, nil
                            if lifecycle == "Wipe" then
                                f.save.Wipe(); f.modules = {}; f.state = {}
                            else
                                eq(f.save.RestoreData(), true, "restore committed candidate during reconcile " .. phase)
                            end
                            -- 写者锁只禁止Update重入；直接推进只读检测，且用足够大新树确保预算中止。
                            local probe = {}
                            for key = 1, 64 do probe[tostring(key)] = key end
                            f.modules.reconcileProbe = probe
                            f.slowClock = true
                            local advance = upvalue(f.save.Update, "advanceDetector")
                            advance(f.env.os.clock())
                            replacementScan = upvalue(f.save.Update, "detectorScan")
                            replacementSource = replacementScan and replacementScan.stack[1].source.gameState
                            replacementTimer = f.timer()
                        end
                        if phase == "snapshot" then f.onSnapshot = resetAfterCommit else f.onExport = resetAfterCommit end
                    end
                    eq(f.save.Flush(), true, "post-commit lifecycle is not falsely reported failed " .. lifecycle .. phase)
                    check(invoked and replacementScan ~= nil, "reconcile reset and new scan actually executed " .. lifecycle .. phase)
                    eq(upvalue(f.save.Update, "detectorScan"), replacementScan, "old maintenance retains new scan identity " .. lifecycle .. phase)
                    eq(replacementScan.stack[1].source.gameState, replacementSource, "old maintenance cannot replace new scan source " .. lifecycle .. phase)
                    eq(f.timer(), replacementTimer, "old maintenance preserves new lifecycle request " .. lifecycle .. phase)
                    eq(f.activeHandles, 0, "post-commit lifecycle releases files " .. lifecycle .. phase)
                    if lifecycle == "Wipe" then
                        eq(f.disk["standalone_save.json"], nil, "post-commit wipe remains deleted " .. phase)
                    else
                        eq(f.saved().modules.currency.gold, 44, "post-commit restore reads actual committed value " .. phase)
                    end
                end
            end
        end)
        run("scan exception cyclic data and recovery", function()
            local f = fixture(2); f.ready()
            f.modules.extra = {}; f.modules.extra.self = f.modules.extra
            for _ = 1, 600 do eq(pcall(f.save.Update, 1 / 60), true, "cyclic detector contained") end
            f.modules.extra = { fixed = true }
            f.untilWrite(3000)
            eq(f.saved().modules.extra.fixed, true, "stable valid data recovers after cycle")
            f.captureFault = true
            eq(pcall(f.save.Update, 1), true, "capture exception contained")
            f.captureFault = false
        end)
        run("Wipe/RestoreData reset detector and frame debounce", function()
            local f = fixture(5); f.ready(); f.modules.currency.gold = 77
            for _ = 1, 90 do f.update() end
            check(f.timer() ~= nil, "timer armed before wipe")
            f.save.Wipe(); f.modules = {}; f.state = {}
            for _ = 1, 600 do f.update() end
            eq(f.writes, 0, "wipe cancels old timer and stale scan")
            local g = fixture(5); g.ready(); g.modules.currency.gold = 44
            for _ = 1, 90 do g.update() end
            g.disk["standalone_save.json"] = cjson.encode({ savedAt = 100, gameState = { gold = 5 }, modules = {
                currency = { gold = 5 }, heroes = { roster = {}, deployed = {} }, session = { lastOnlineTime = 100 } } })
            eq(g.save.RestoreData(), true, "restore succeeds with timer pending")
            for _ = 1, 1920 do g.update() end
            eq(g.writes, 1, "restore replaces stale timer with one conservative fresh baseline save")
            eq(g.saved().modules.currency.gold, 5, "restore baseline cannot save old dirty currency")
            g.modules.currency.gold = 6
            g.untilWrite(); eq(g.saved().modules.currency.gold, 6, "restore subsequent in-place detected")
        end)
        run("real live three-team progress and ledger no full poll capture", function()
            local f = fixture(2); f.live = { 2501, 1501, 1901 }; f.ledger = { [1905] = true }; f.ready()
            f.live[1], f.live[3] = 2502, 1902; f.ledger[2001] = true; f.maxStage = 2502
            local old = copy(f.modules.battle)
            f.untilWrite()
            local saved = f.saved().modules.battle
            eq(saved.currentStageId, 2502, "real fresh team1 reservation")
            eq(saved.teamStageIds["3"], 1902, "real fresh team3 reservation")
            eq(saved.clearedStages["2001"], true, "real live ledger mutation")
            check(same(f.modules.battle, old), "no reverse mutation of battle modules")
            eq(f.captures, 1, "CaptureBattleProgress only on actual flush")
        end)
        run("bounded CPU slice and traversal progress with repeated Flush", function()
            local f = fixture(1000); f.ready(); f.slowClock = true; f.clockQueries = 0
            local before = f.steps; f.update(1)
            check(f.steps - before <= 64, "soft CPU budget yields at 32-step checks")
            check(f.clockQueries >= 2, "clock checked for traversal")
            check(upvalue(f.save.Update, "detectorScan") ~= nil, "scan retained on budget yield")
            f.slowClock = false
            local finished = false
            for _ = 1, 300 do
                f.save.Flush(); f.update()
                if not upvalue(f.save.Update, "detectorScan") then finished = true break end
            end
            check(finished, "transaction Flush does not starve large scan tail")
        end)
        run("post-Rename mutation not blessed as committed", function()
            local f = fixture(3); f.ready(); f.save.OfflineChecked(); f.ready()
            f.onRename = function() f.modules.session.lastOnlineTime = f.now + 1; f.modules.currency.gold = 123 end
            eq(f.save.Flush(), true, "rename callback fixture commit")
            eq(f.saved().modules.currency.gold, 20, "encoded value before callback")
            f.onRename = nil; f.untilWrite()
            eq(f.saved().modules.currency.gold, 123, "callback mutation still detected")
            eq(f.saved().modules.session.lastOnlineTime, f.now + 1, "callback online mutation not swallowed")
        end)
    end
    run("large real equipment shape serialization A/B", function()
        for _, count in ipairs({ 1000, 5000, 10000 }) do
            local f = fixture(count)
            local started, maxMs = os.clock(), 0
            local completeFrames = baseline and 1 or f.ready()
            local quietEncodes = f.encodes
            for _ = 1, 1200 do maxMs = math.max(maxMs, f.update()) end
            local idlePeak = maxMs
            local quietTotal = f.encodes - quietEncodes
            if not baseline then
                eq(f.encodes, 0, "large idle zero JSON " .. count)
                eq(f.captures, 0, "large idle zero full capture " .. count)
                eq(f.writes, 0, "large idle baseline no auto write " .. count)
            end
            local measuredSteps = f.steps
            f.modules.equipment.inventory[tostring(count)].affixes[1].value = 654.321
            local latencyFrames, flushPeak = 0, 0
            local writes = f.writes
            for i = 1, 4000 do
                local ms = f.update(); maxMs = math.max(maxMs, ms)
                if f.writes > writes then latencyFrames, flushPeak = i, ms break end
            end
            check(latencyFrames > 0, "large tail mutation eventually saved " .. count)
            eq(f.saved().modules.equipment.inventory[tostring(count)].affixes[1].value, 654.321,
                "large tail final value " .. count)
            local serializedBytes = #(f.disk["standalone_save.json"] or "")
            eq(f.activeHandles, 0, "large commit has no retained file " .. count)
            local directStart = os.clock()
            eq(f.save.Flush(), true, "large synchronous transaction remains immediate " .. count)
            local directFlushMs = (os.clock() - directStart) * 1000
            print(string.format("%s METRIC baseline=%s inventory=%d baselineFrames=%d idle1200Encodes=%d totalEncodes=%d capture=%d traversalNext=%d idlePeakMs=%.4f flushPeakMs=%.4f directFlushMs=%.4f saveBytes=%d mutationFrames=%d elapsedCpuMs=%.3f",
                TAG, tostring(baseline), count, completeFrames, quietTotal, f.encodes, f.captures, measuredSteps,
                idlePeak, flushPeak, directFlushMs, serializedBytes, latencyFrames, (os.clock() - started) * 1000))
        end
    end)
    print(string.format("%s SUMMARY baseline=%s cases=%d assertions=%d failures=%d harnessErrors=%d", TAG,
        tostring(baseline), cases, assertions, failures, harnessErrors))
    if failures > 0 then log:Write(LOG_ERROR, TAG .. " FAILED") end
    engine:Exit()
end
