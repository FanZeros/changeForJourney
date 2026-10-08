-- 资源旧档已通历史迁移专项。只读正式Lua，真实Dispatcher双onLoad与完整三行通关函数。
-- 不运行main/Boot/PDM，不打开玩家档，不写文件，不计算/发放奖励或推进挂机计时。
local TAG = "[resource_dungeon_clear_migration_test]"
local assertions = 0

local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
end

local function eq(actual, expected, label)
    check(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = copy(child) end
    return out
end

local function same(actual, expected, label)
    eq(type(actual), type(expected), label .. "类型")
    if type(expected) ~= "table" then eq(actual, expected, label .. "值"); return end
    for key, child in pairs(expected) do same(actual[key], child, label .. "/" .. tostring(key)) end
    for key in pairs(actual) do check(expected[key] ~= nil, label .. "额外字段 " .. tostring(key)) end
end

local function source(name)
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "缺少正式脚本 " .. name)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function newContext()
    local now = 1720000000
    local h = { flushes = 0, adopted = {}, loaded = {} } ---@type any
    local env = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, next = next,
        tonumber = tonumber, tostring = tostring, type = type, pcall = pcall,
        setmetatable = setmetatable, math = math, string = string, table = table,
        os = { time = function() return now end }, print = print, cjson = cjson,
    } ---@type any
    env._G = env
    -- 与待测副本无关的子Schema仅提供空注册表，不初始化英雄/装备/任务等业务。
    local mocks = {} ---@type table<string, table>
    for _, path in ipairs({ "profile.Profile", "player.Player", "currency.Currency", "heroes.Heroes",
        "equipment.Equipment", "battle.Battle", "lootbox.Lootbox", "talents.Talents",
        "signin.Signin", "redeem.Redeem", "task.Task", "session.Session", "quota.Quota",
        "slotenhance.SlotEnhance", "tavern.Tavern", "artifact.Artifact" }) do
        mocks["shared." .. path .. "Schema"] = { Fields = {} }
    end
    -- Sweep只测已通资格，不计算奖励。资源getStage的券率依赖显式只读替身。
    mocks["systems.DropSystem"] = { getSweepTicketRate = function() return 0 end }
    mocks["boot.StandaloneSave"] = { Flush = function() h.flushes = h.flushes + 1; return true end }
    local allowed = {
        ["config.DungeonConfig"] = true, ["config.StageConfig"] = true,
        ["config.MonsterConfig"] = true, ["config.ExpTable"] = true,
        ["config.TowerConfig"] = true, -- DungeonCompat冻结旧塔首通历史的只读配置依赖。
        ["systems.AttributeDef"] = true, ["systems.UnitAttributes"] = true,
        ["shared.dungeon.DungeonSchema"] = true, ["shared.dungeon.DungeonCompat"] = true,
        ["shared.ModuleRegistry"] = true, ["shared.schemas.CharacterSchema"] = true,
        ["shared.Protocol"] = true, ["runtime.ClientDispatcher"] = true,
        ["shared.sweep.SweepRewards"] = true,
        ["ui.battle.tri.BattleTriStageProgress"] = true, -- Scene通关委托的正式纯逻辑模块。
    }
    env.require = function(name)
        if mocks[name] then return mocks[name] end
        if h.loaded[name] then return h.loaded[name] end
        assert(allowed[name] or name:match("^config%.StageConfig_[A-Za-z0-9]+$"),
            "禁止非专项依赖/存档/奖励入口 " .. tostring(name))
        local value = assert(load(source(name), "@clear-migration/" .. name, "t", env))()
        h.loaded[name] = value
        return value
    end
    h.env, h.require, h.today = env, env.require, math.floor((now + 28800) / 86400)
    h.DC = env.require("config.DungeonConfig")
    h.Schema = env.require("shared.dungeon.DungeonSchema").Fields.dungeon
    h.Compat = env.require("shared.dungeon.DungeonCompat")
    h.Dispatcher = env.require("runtime.ClientDispatcher")
    h.Registry = env.require("shared.ModuleRegistry")
    h.Sweep = env.require("shared.sweep.SweepRewards")
    -- 提取完整正式函数，不复制通关算法；主线奖励出口遇到调用立即失败。
    local text = source("ui.battle.scene.BattleScene")
    local first = assert(text:find("function BattleScene.completeTriStageClear(stageId, teamIdx)", 1, true))
    local last = assert(text:find("\nend", first, true), "缺少完整正式通关委托函数结尾") + #"\nend"
    h.Scene = {
        adoptStageProgress = function(id) h.adopted[#h.adopted + 1] = id end,
        onFirstClear = function() error("资源通关禁止主线首奖") end,
    }
    env.BattleScene = h.Scene
    assert(load("local SC = require('config.StageConfig')\nlocal clearedStages={}\n"
        .. "local maxStageId_=34505\nlocal currentStageId=101\nlocal isFirstClear=false\n"
        .. text:sub(first, last - 1), "@actual-completeTriStageClear", "t", env))()
    h.Dispatcher.set("battle", { maxStageId = 34505, currentStageId = 101,
        clearedStages = { ["101"] = true }, teamStageIds = { ["1"] = 101, ["2"] = 201, ["3"] = 301 } })
    return h
end

local function ledger(sub, through, label)
    for floor = 1, through do eq(sub.cleared[floor], true, label .. "历史层" .. floor) end
    local count = 0
    for key, value in pairs(sub.cleared) do
        check(type(key) == "number" and key >= 1 and key <= through and value == true, label .. "只含可信历史")
        count = count + 1
    end
    eq(count, through, label .. "完整记录数")
    eq(sub.cleared[through + 1], nil, label .. "未通层不预写")
end

local function noSweep(h, data, id, label)
    for floor = 1, h.DC.MAX_FLOOR[id] do
        eq(h.Sweep.isCleared(h.DC.getStageId(id, floor), h.Dispatcher.get("battle"), data), false,
            label .. "禁止凭空账本/floor扫层" .. floor)
    end
end

local function fixture(h, floor, cleared)
    return { floor = floor, cleared = cleared, dailyUsed = 2, dailyDay = h.today,
        idleAccumSec = 12345, custom = { keep = "unchanged" } }
end

local function legacyAndClear()
    local h = newContext()
    local data = { compat = { monsterBuffV1 = true, customCompat = { a = 17 } },
        ancient_ruin = fixture(h, 6, {}), babel_tower = fixture(h, 21, {}), topCustom = "keep" }
    data.babel_tower.buffs = { 2, 5 }
    for _, id in ipairs(h.DC.RESOURCE_IDS) do data[id] = fixture(h, 6, {}) end
    data.equipment_vault.idleConsumedSec = 3600
    local before, compatRef = copy(data), data.compat
    h.Dispatcher.set("dungeon", data) -- 真实Registry先规范化，Schema再次委托；两入口均必须安全。
    eq(data.compat, compatRef, "保留compat原表引用")
    eq(data.compat.resourceClearedV1, true, "一次性迁移标记")
    eq(data.compat.resourceProgressionV2, true, "资源扩展一次性判定标记")
    eq(data.compat.towerSingleWaveV2, true, "单波塔历史冻结标记")
    same(data.compat.customCompat, before.compat.customCompat, "保留其他compat字段")
    eq(data.compat.monsterBuffV1, true, "保留旧难度标记")
    same(data.ancient_ruin, before.ancient_ruin, "古迹旧积累/历史不改")
    local expectedTower = copy(before.babel_tower)
    for floor = 1, 20 do expectedTower.cleared[floor] = true end
    ledger(data.babel_tower, 20, "独立塔冻结历史首通")
    same(data.babel_tower, expectedTower, "独立塔只补历史，其余字段及旧积累不改")
    eq(data.topCustom, before.topCustom, "保留未知顶层字段")
    local battle = h.Dispatcher.get("battle")
    for _, id in ipairs(h.DC.RESOURCE_IDS) do
        ledger(data[id], 5, id .. "第一次读档")
        for key, value in pairs(before[id]) do
            if key ~= "cleared" then same(data[id][key], value, id .. "不改非账本字段/" .. key) end
        end
        for floor = 1, 5 do
            eq(h.Sweep.isCleared(h.DC.getStageId(id, floor), battle, data), true, id .. "历史资格" .. floor)
        end
        eq(h.Sweep.isCleared(h.DC.getStageId(id, 6), battle, data), false, id .. "未通6不能扫")
    end
    local snapshot = copy(data)
    for _ = 1, 3 do h.Registry.applyOnLoad("dungeon", data); h.Schema.onLoad(data); h.Schema.onServerLoad(data) end
    same(data, snapshot, "两入口重复加载值幂等")
    local clearedBefore = copy(battle.clearedStages)
    for team, id in ipairs(h.DC.RESOURCE_IDS) do
        local countBefore = h.flushes
        eq(h.Scene.completeTriStageClear(h.DC.getStageId(id, 6), team), false, id .. "真实资源通关无主线首奖")
        eq(h.flushes, countBefore + 1, id .. "只调用内存Flush一次")
        eq(data[id].floor, 7, id .. "真实正常完成6后floor7")
        eq(data[id].cleared["6"], true, id .. "真实完成新增string层6")
        for floor = 1, 6 do
            eq(h.Sweep.isCleared(h.DC.getStageId(id, floor), battle, data), true, id .. "新增6后仍有历史资格" .. floor)
        end
        eq(h.Sweep.isCleared(h.DC.getStageId(id, 7), battle, data), false, id .. "不授予未通7")
        h.Dispatcher.set("dungeon", cjson.decode(cjson.encode(data))) -- 冷JSON镜像重载，不沿用数字键。
        data = h.Dispatcher.get("dungeon")
        ledger(data[id], 6, id .. "JSON重载")
    end
    eq(battle.maxStageId, 34505, "资源通关不抬主线max")
    same(battle.clearedStages, clearedBefore, "资源通关不动主线首通账本")
    same(data.ancient_ruin, before.ancient_ruin, "新增6/JSON之后古迹保持")
    same(data.babel_tower, expectedTower, "新增6/JSON之后塔只保持冻结历史与原字段")
end

local function sparseAndFresh()
    local h = newContext()
    for _, id in ipairs(h.DC.RESOURCE_IDS) do
        for _, cleared in ipairs({ { [6] = true }, { ["6"] = true }, { ["1"] = true, ["11"] = true } }) do
            local data = { [id] = fixture(h, 12, copy(cleared)), compat = { monsterBuffV1 = true } }
            h.Dispatcher.set("dungeon", data)
            for floor = 1, 12 do
                local recorded = cleared[floor] == true or cleared[tostring(floor)] == true
                eq(data[id].cleared[floor] == true, recorded, id .. "非空跳章不补floor=" .. floor)
                eq(h.Sweep.isCleared(h.DC.getStageId(id, floor), h.Dispatcher.get("battle"), data), recorded,
                    id .. "跳章只真实记录可扫=" .. floor)
            end
            local before = copy(data)
            for _ = 1, 3 do h.Dispatcher.set("dungeon", data) end
            same(data, before, id .. "跳章双onLoad幂等")
        end
    end
    local fresh = h.Schema.getDefault()
    fresh.compat = { monsterBuffV1 = true }
    h.Dispatcher.set("dungeon", fresh)
    for team, id in ipairs(h.DC.RESOURCE_IDS) do
        ledger(fresh[id], 0, id .. "新档不放开首层")
        eq(h.Sweep.isCleared(h.DC.getStageId(id, 1), h.Dispatcher.get("battle"), fresh), false, id .. "新档首层不能扫")
        eq(h.Scene.completeTriStageClear(h.DC.getStageId(id, 1), team), false, id .. "真实首层后仍无主线首奖")
        fresh = h.Dispatcher.get("dungeon")
        eq(fresh[id].cleared["1"], true, id .. "只新增完成首层")
        eq(fresh[id].cleared[2], nil, id .. "不补章节跨越层")
    end
    h.Dispatcher.set("dungeon", fresh)
    for _, id in ipairs(h.DC.RESOURCE_IDS) do ledger(fresh[id], 1, id .. "新档首层重载") end
    -- 已判定的新档后来floor变大且账本为空，不得第二次借floor推断连续历史。
    for _, id in ipairs(h.DC.RESOURCE_IDS) do fresh[id].floor, fresh[id].cleared = 6, {} end
    h.Dispatcher.set("dungeon", fresh)
    for _, id in ipairs(h.DC.RESOURCE_IDS) do
        ledger(fresh[id], 0, id .. "标记后不重迁移")
        noSweep(h, fresh, id, id .. "标记后的空账本无已通资格")
    end
end

local function invalidAndBounds()
    local h = newContext()
    for _, id in ipairs(h.DC.RESOURCE_IDS) do
        for _, cleared in ipairs({ { ["5"] = false }, { bad = true }, { ["2.5"] = true }, { [0] = true }, "bad", false, 42 }) do
            local data = { [id] = fixture(h, 6, copy(cleared)), compat = { monsterBuffV1 = true } }
            h.Dispatcher.set("dungeon", data)
            ledger(data[id], 0, id .. "非法非空不迁移")
            noSweep(h, data, id, id .. "非法非空首次双onLoad")
            for _ = 1, 3 do h.Dispatcher.set("dungeon", data) end
            ledger(data[id], 0, id .. "非法账本规范化后仍不迁移")
            noSweep(h, data, id, id .. "非法非空重复双onLoad")
            eq(data.compat.resourceClearedV1, true, id .. "记住拒绝迁移判定")
        end
        local legacyMax = h.DC.LEGACY_MAX_FLOOR[id]
        for _, floor in ipairs({ "6.5", 6.5, -1, 0, "bad", legacyMax + 2,
            h.DC.MAX_FLOOR[id], h.DC.MAX_FLOOR[id] + 1, h.DC.MAX_FLOOR[id] + 2, math.huge, 0 / 0 }) do
            local data = { [id] = fixture(h, floor, {}), compat = { monsterBuffV1 = true } }
            h.Dispatcher.set("dungeon", data)
            ledger(data[id], 0, id .. "非法原始floor不迁移")
            if tonumber(floor) and tonumber(floor) > legacyMax + 1 then
                eq(data[id].floor, 1, id .. "旧异常大floor不因新max放开")
                eq(h.DC.isStageUnlocked(h.DC.getStageId(id, legacyMax + 2), h.Dispatcher.get("battle"), data),
                    false, id .. "旧异常不能挑战扩展层")
            end
            eq(data.compat.resourceProgressionV2, true, id .. "拒绝异常后记录v2判定")
            noSweep(h, data, id, id .. "非法floor首次双onLoad")
            h.Dispatcher.set("dungeon", data)
            ledger(data[id], 0, id .. "floor规范化后也不反推历史")
            noSweep(h, data, id, id .. "非法floor重复双onLoad")
        end
        for _, floor in ipairs({ 2, "6", legacyMax, legacyMax + 1, tostring(legacyMax + 1) }) do
            local data = { [id] = fixture(h, floor), compat = { monsterBuffV1 = true } }
            h.Dispatcher.set("dungeon", data)
            ledger(data[id], tonumber(floor) - 1, id .. "缺账本可信原始floor=" .. tostring(floor))
            eq(data[id].floor, tonumber(floor), id .. "合法旧终点不重编号")
            if tonumber(floor) == legacyMax + 1 then
                eq(h.Sweep.isCleared(h.DC.getStageId(id, legacyMax), h.Dispatcher.get("battle"), data),
                    true, id .. "合法旧终点保留已通资格")
            end
            local before = copy(data)
            h.Dispatcher.set("dungeon", cjson.decode(cjson.encode(data)))
            same(h.Dispatcher.get("dungeon"), before, id .. "可信边界JSON幂等")
        end
        -- v2有效账本允许新内容；迁移不回退合法扩展层，也不补被章节跳过的层。
        local last = h.DC.MAX_FLOOR[id]
        local progressed = { [id] = fixture(h, last, { [tostring(last)] = true }),
            compat = { monsterBuffV1 = true, resourceClearedV1 = true, resourceProgressionV2 = true,
                towerSingleWaveV2 = true } }
        h.Dispatcher.set("dungeon", progressed)
        eq(progressed[id].floor, last, id .. "v2合法扩展终层保留")
        eq(progressed[id].cleared[last], true, id .. "v2扩展首通保留")
        eq(progressed[id].cleared[last - 1], nil, id .. "v2不推断扩展跳过层")
        eq(h.Sweep.isCleared(h.DC.getStageId(id, last), h.Dispatcher.get("battle"), progressed),
            true, id .. "v2扩展终层可扫")
        local snapshot = copy(progressed)
        for _ = 1, 3 do h.Dispatcher.set("dungeon", progressed) end
        same(progressed, snapshot, id .. "v2合法终层幂等")
    end
    local data = { gold_mine = fixture(h, 6, {}), compat = { monsterBuffV1 = true } }
    h.Compat.onLoad(data, { runMigration = true })
    ledger(data.gold_mine, 5, "Compat直接读档入口")
    local before = copy(data)
    h.Schema.onLoad(data)
    h.Registry.applyOnLoad("dungeon", data)
    same(data, before, "Compat/Schema/Registry入口互换幂等")
    for _, name in ipairs({ "rules.character.PlayerDataManager", "boot.StandaloneBoot", "main", "systems.EquipmentSystem" }) do
        eq(h.loaded[name], nil, "未执行玩家档/初始化/奖励模块 " .. name)
    end
end

local function towerHistoryV2()
    local h = newContext()
    for floor = 2, 113 do
        local bt = fixture(h, floor % 2 == 0 and tostring(floor) or floor,
            floor % 2 == 0 and {} or { [tostring(floor - 1)] = true })
        bt.buffs = { 2, 5 }
        local expected = copy(bt)
        expected.floor, expected.cleared = floor, {}
        for history = 1, floor - 1 do expected.cleared[history] = true end
        local data = { babel_tower = bt, compat = { monsterBuffV1 = true } }
        h.Dispatcher.set("dungeon", data)
        ledger(bt, floor - 1, "旧塔floor=" .. floor)
        same(bt, expected, "旧塔floor=" .. floor .. "仅冻结历史不改旧积累及其他字段")
        eq(data.compat.towerSingleWaveV2, true, "旧塔历史冻结一次标记")
        local snapshot = copy(data)
        h.Schema.onLoad(data)
        h.Schema.onServerLoad(data)
        h.Dispatcher.set("dungeon", cjson.decode(cjson.encode(data)))
        same(h.Dispatcher.get("dungeon"), snapshot, "旧塔floor=" .. floor .. "v2/JSON幂等")
    end
    local data = { babel_tower = fixture(h, 6, {}), compat = { monsterBuffV1 = true,
        towerSingleWaveV2 = true } }
    data.babel_tower.buffs = { 2, 5 }
    local expected = copy(data.babel_tower)
    h.Dispatcher.set("dungeon", data)
    same(data.babel_tower, expected, "v2已判定塔不因floor再次补空账本")
end

function Start()
    local ok, err = pcall(function()
        legacyAndClear()
        sparseAndFresh()
        invalidAndBounds()
        towerHistoryV2()
        print(TAG .. " ALL PASS assertions=" .. assertions .. " playerFile=false main=false rewards=false")
    end)
    if not ok then log:Write(LOG_ERROR, TAG .. " FAIL after " .. assertions .. ": " .. tostring(err)) end
    engine:Exit()
end
