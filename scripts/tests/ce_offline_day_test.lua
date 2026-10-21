-- CE一天离线收益专项；独立Runtime入口，不加载main/正式Boot，不访问玩家档。
-- 借鉴SweepRegressionFixture的私有require/math/os架构，PDM通知和Boot/Save/Bridge显式替身。
-- 正式OfflineCalc/Stage/Exp/Equipment/LootBox/Blacksmith/HeroService均执行真实源码。
-- 不覆盖设备触控/像素、完整Boot、真实存盘/WASM、异常中途交付回滚；异常只验锁释放和CE熔断。
local TAG = "[ce_offline_day_test]"
local assertions, failures, cases = 0, 0, 0
local sourceCache, fixtures = {}, {}
local activeCase = "setup"

local function check(value, label)
    assertions = assertions + 1
    if not value then
        failures = failures + 1
        print(TAG .. " FAIL " .. activeCase .. ": " .. label)
    end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function case(label, fn)
    activeCase = label
    cases = cases + 1
    local before = failures
    local ok, err = pcall(fn)
    if not ok then check(false, "harness exception " .. tostring(err)) end
    print(TAG .. (failures == before and " PASS " or " FAILED ") .. label)
end
local function source(name)
    assert(type(name) == "string" and name:match("^[%w_%.]+$") and not name:find("%.%."), "非法源码名")
    if sourceCache[name] then return sourceCache[name] end
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "缺少真实源码 " .. name)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local text = table.concat(lines, "\n")
    sourceCache[name] = text
    return text
end

local function newFixture(count, settings)
    ---@type table<string, any>
    local h = { data = {}, modules = {}, dirty = {}, generated = {}, toasts = {},
        rngCalls = 0, seed = 17, now = 1791200000, fileCalls = 0, bootLoads = 0,
        bridgeCalls = 0, captures = 0, saves = 0, ready = true, panelOpen = false,
        order = {}, reads = {} }
    local guard = { fileCalls = 0, bootLoads = 0 }
    fixtures[#fixtures + 1] = guard
    local env = setmetatable({}, { __index = _G })
    local F = assert(load(source("tests.SweepRegressionFixture"), "@ce-day/fixture", "t", env))()
    h.copy, h.equal = F.copy, F.equal
    env._G, env.math, env.os = env, F.copy(math), F.copy(os)
    env.os.time = function() return h.now end
    env.print = function() end
    local function deny()
        guard.fileCalls = guard.fileCalls + 1
        error("CE专项禁止File/FileSystem/真实存档访问")
    end
    env.File, env.GetFileSystem, env.dofile, env.loadfile = deny, deny, deny, deny
    env.fileSystem = setmetatable({}, { __index = function() return deny end })
    env.io = setmetatable({}, { __index = function() return deny end })
    env.os.execute, env.os.remove, env.os.rename, env.os.getenv = deny, deny, deny, deny
    env.cache = { GetFile = function(_, path)
        assert(type(path) == "string" and path:match("^[%w_/]+%.lua$")
            and not path:match("^boot/"), "只允许读规则Lua资源")
        return cache:GetFile(path)
    end }
    env.package = { loaded = h.modules, preload = {}, path = "" }
    env.math.randomseed = function(seed) h.seed, h.rngCalls = seed, 0 end
    env.math.random = function(a, b)
        h.rngCalls = h.rngCalls + 1
        assert(not h.forbidRNG, "拒绝/重推/领取路径消费RNG")
        h.seed = h.seed * 48271 % 2147483647
        local r = h.seed / 2147483647
        if a == nil then return r end
        local lo, hi = b == nil and 1 or a, b == nil and a or b
        return lo + math.floor(r * (hi - lo + 1))
    end
    -- 不复用F.new默认事务PDM：本功能MarkDirty就是同步通知边界，不伪造已持久化。
    h.modules["rules.character.PlayerDataManager"] = {
        GetModule = function(uid, key)
            eq(uid, 1, "PDM UID")
            h.reads[key] = (h.reads[key] or 0) + 1
            return h.data[key]
        end,
        MarkDirty = function(uid, key)
            eq(uid, 1, "dirty UID")
            h.dirty[key] = (h.dirty[key] or 0) + 1
            h.order[#h.order + 1] = "dirty:" .. key
            if h.onDirty then h.onDirty(key) end
        end,
        FlushImmediate = deny,
    }
    h.modules["core.PlayerStore"] = { Get = function(key) return h.data[key] end }
    h.modules["runtime.ClientDispatcher"] = { get = function(key) return h.data[key] end }
    h.modules["ui.character.panel.CharacterPanel"] = {
        isHeroesDataApplied = function() return false end,
        getTeamSlotIds = function() error("未应用面板不应借实时队伍") end,
    }
    h.modules["boot.Standalone"] = { isRewardReady = function() return h.ready end }
    h.modules["boot.StandaloneSave"] = {
        CaptureBattleProgress = function(battle)
            eq(battle, h.data.battle, "Capture收到PDM当前battle引用")
            h.captures = h.captures + 1
            h.order[#h.order + 1] = "capture"
            if h.captureError then error("expected capture failure") end
            h.lastCapture = F.copy(h.liveSnapshot or battle)
            return h.lastCapture
        end,
        RequestSave = function()
            h.saves = h.saves + 1
            h.order[#h.order + 1] = "request-save"
            if h.onSave then h.onSave() end
        end,
        Flush = deny, Wipe = deny, RestoreData = deny,
    }
    h.modules["runtime.LocalActionBridge"] = { init = function()
        h.bridgeCalls = h.bridgeCalls + 1
        h.order[#h.order + 1] = "bridge"
        if h.bridgeError then error("expected bridge failure") end
    end }
    h.modules["ui.hud.popup.OfflineRewardPanel"] = { isOpen = function() return h.panelOpen end }
    h.modules["core.UiToast"] = { show = function(text) h.toasts[#h.toasts + 1] = text end }
    h.modules["ui.dev.CERuntime"] = { isGodMode = function() return false end }
    local loading = {}
    env.require = function(name)
        if h.modules[name] ~= nil then return h.modules[name] end
        if name:match("^boot%.") then guard.bootLoads = guard.bootLoads + 1; error("禁止正式Boot " .. name) end
        assert(name ~= "main" and (name:match("^config%.") or name:match("^shared%.")
            or name:match("^systems%.") or name:match("^rules%.") or name == "core.BattleLayout"
            or name == "ui.dev.CEPanel"),
            "未声明的依赖边界 " .. tostring(name))
        assert(not loading[name], "循环依赖 " .. name)
        loading[name] = true
        local value = assert(load(source(name), "@ce-day/" .. name, "t", env))()
        loading[name] = nil
        assert(value ~= nil, "模块缺少返回值 " .. name)
        h.modules[name] = value
        return value
    end
    h.env, h.require = env, env.require
    h.ES = h.require("systems.EquipmentSystem")
    count = count or h.ES.MAX_INVENTORY
    h.capacity = h.ES.MAX_INVENTORY
    h.LS = h.require("systems.LootBoxSystem")
    h.ET = h.require("config.ExpTable")
    h.SC = h.require("config.StageConfig")
    h.DC = h.require("config.DungeonConfig")
    h.BS = h.require("config.BlacksmithConfig")
    h.Calc = h.require("systems.OfflineCalc")
    h.Offline = h.require("rules.offline.OfflineService")
    h.CE = h.require("rules.gm.CEService")
    h.Panel = h.require("ui.dev.CEPanel")
    local inventory = { inventory = {}, equipped = {}, nextSeq = 1, settings = F.copy(settings or {}) }
    local filler = assert(h.ES.generate("W1", 1, 1))
    filler.locked, filler.marker = true, { old = "inventory" }
    for _ = 1, count or 0 do h.ES.addToInventory(inventory, F.copy(filler)) end
    local lootbox = { seeds = { { quality = 1, level = 1, count = 7, legacy = true } } }
    h.LS.addEquipment(lootbox, F.copy(filler), "curation")
    local roster = {}
    for id = 1, 12 do roster[id] = { level = 1, exp = id % 3, maxExp = h.ET.getHeroExpForLevel(1) } end
    -- 混用字符串名册键，覆盖冷档JSON常见表示；未出战角色只允许正式共鸣改变。
    roster["6"], roster[6] = roster[6], nil
    local dungeon = { babel_tower = { floor = 1, cleared = {}, buffs = {} } }
    for _, id in ipairs(h.DC.RESOURCE_IDS) do dungeon[id] = { floor = 1, cleared = {}, dailyUsed = 2 } end
    h.data = { equipment = inventory, lootbox = lootbox, dungeon = dungeon,
        heroes = { roster = roster, deployed = { 1, 0, 0, 0 }, teams = {
            { slots = { 1, 0, 0, 0 } }, { slots = { 2, 0, 3, 0 } }, { slots = { 4, 5, 0, 6 } } } },
        battle = { currentStageId = 101, maxStageId = 2501, teamStageIds = { 101, 105, 201 },
            clearedStages = { [905] = true, ["1905"] = true }, idleAccumSec = 43217, idleHeroCount = 99 },
        session = { lastOnlineTime = h.now - 86400, firstLoginTime = h.now - 3 * 86400,
            playDays = 3, introCompleted = true, marker = { keep = true } },
        player = { level = 1, exp = 7, maxExp = h.ET.getPlayerExpForLevel(1) },
        currency = { gold = 40, gems = 20, essence = 17, sweepTicket = 31 }, artifacts = {}, talents = {} }
    local original = h.ES.generateRandom
    h.ES.generateRandom = function(level, quality, options)
        local equip = original(level, quality, options)
        if equip then
            if h.lockGenerated then equip.locked = true end
            h.generated[#h.generated + 1] = { equip = equip, value = F.copy(equip) }
        end
        return equip
    end
    h.seed, h.rngCalls = 1021, 0
    return h
end
local function same(h, a, b, label) check(h.equal(a, b), label) end
local function pendingOf(h)
    for index = 1, 50 do
        local name, value = debug.getupvalue(h.Offline.HasPendingRewards, index)
        if name == "pendingRewards" then return value end
        if not name then break end
    end
    error("缺少真实pendingRewards")
end
local function graph(value, out)
    out = out or {}
    if type(value) ~= "table" or out[value] then return out end
    local edges = {}; out[value] = edges
    for key, child in pairs(value) do edges[key] = child; graph(child, out) end
    return out
end
local function graphUnchanged(snapshot, label)
    for node, edges in pairs(snapshot) do
        for key, child in pairs(edges) do eq(node[key], child, label .. " 原引用/标量") end
        for key in pairs(node) do check(edges[key] ~= nil, label .. " 不新增字段") end
    end
end
local function requireSuccess(ok, err, label)
    eq(ok, true, label .. " " .. tostring(err))
    assert(ok, label .. "未成功，停止本场景后续断言")
end
local function rewardsOnly(h, before)
    for _, key in ipairs({ "session", "battle", "dungeon", "artifacts", "talents" }) do
        same(h, h.data[key], before[key], "CE不得修改 " .. key)
    end
    eq(h.Offline.HasPendingRewards(1), false, "CE不创建正式pending")
    eq(h.dirty.session, nil, "CE无session通知")
    eq(h.dirty.battle, nil, "CE无battle通知")
end

local MAIN = { { teamIdx = 1, stageId = 101, heroCount = 1 },
    { teamIdx = 2, stageId = 105, heroCount = 2 }, { teamIdx = 3, stageId = 201, heroCount = 3 } }
local function pair(label, options)
    case(label, function()
        options = options or {}
        local a, b = newFixture(), newFixture()
        local free = options.free == nil and 3 or options.free
        for _, h in ipairs({ a, b }) do
            eq(h.capacity, 500, "正式背包容量为500")
            for i = 1, free do h.ES.removeFromInventory(h.data.equipment, h.capacity - i + 1) end
            h.data.equipment.settings = h.copy(options.settings or {})
            if options.configure then options.configure(h) end
        end
        local specs = options.specs or MAIN
        local before = b.copy(b.data)
        local oracle = assert(a.Calc.calcTeamOfflineRewards(86400, specs, a.SC))
        a.seed, a.rngCalls = 1021, 0
        local panel = assert(a.Offline.CalcOnEnter(1), "正式24h面板必须存在")
        eq(panel.offlineSeconds, 86400, "24小时不乘队数或速度卡")
        eq(panel.totalKills, oracle.kills, "显式来源oracle总击杀")
        eq(panel.adventureExp, oracle.adventureExp, "显式来源oracle玩家经验")
        eq(#panel.teamSources, #specs, "真实来源数量")
        for i, spec in ipairs(specs) do
            local row, expected = panel.teamSources[i], oracle.teamRewards[i]
            eq(row.teamIdx, spec.teamIdx, "来源队号")
            eq(row.stageId, spec.stageId, "不偷最高主线或已存旧任务")
            eq(row.heroCount, spec.heroCount, "人数只含非空真实英雄")
            eq(row.paused, spec.paused == true, "暂停语义")
            eq(row.gold, expected.gold, "来源金币")
            eq(row.diamond, expected.diamond, "来源黑钻")
            eq(row.adventureExp, expected.adventureExp, "来源玩家经验")
            eq(row.adventurerExp, expected.adventurerExp, "来源英雄经验")
        end
        for _, key in ipairs({ "currency", "heroes", "player", "equipment", "lootbox" }) do
            same(a, a.data[key], before[key], "正式预览不提前发奖 " .. key)
        end
        local formalRng = a.rngCalls
        a.forbidRNG = true
        local ok, err, expected = a.Offline.ClaimRewards(1)
        requireSuccess(ok, err, "正式领取")
        eq(a.rngCalls, formalRng, "正式领取不重骰")
        local granted, why, actual = b.Offline.GrantDebugDayRewards(1)
        requireSuccess(granted, why, "CE额外一天")
        same(b, actual, expected, "完整业务回执与正式24h严格一致")
        eq(b.seed, a.seed, "同种子随机终态完全相同")
        eq(b.rngCalls, a.rngCalls, "同种子随机消费完全相同")
        local seedCount = 0
        for _, seed in ipairs(oracle.equipSeeds) do seedCount = seedCount + math.max(1, math.floor(seed.count or 1)) end
        eq(#b.generated, seedCount, "显式来源真实种子全部确定化，无漏件")
        eq(actual.gold, math.floor(oracle.gold), "独立Calc金币对照")
        eq(actual.diamond, math.floor(oracle.diamond), "独立Calc黑钻对照")
        eq(b.data.currency.gold, before.currency.gold + math.floor(oracle.gold), "金币准确入账一次")
        eq(b.data.currency.gems, before.currency.gems + math.floor(oracle.diamond), "黑钻写gems一次")
        for key, amount in pairs(oracle.scrollDrops) do
            eq(b.data.currency[key], (before.currency[key] or 0) + math.floor(amount), "卷轴/券完整入账 " .. key)
        end
        eq(#b.generated, #a.generated, "实际确定装备数一致")
        check(#b.generated > 0 or options.noEquip == true, "必须真实产生装备，禁止空oracle通过")
        for _, key in ipairs({ "currency", "heroes", "player", "equipment", "lootbox", "dungeon" }) do
            same(b, b.data[key], a.data[key], "实际最终模块严格一致 " .. key)
        end
        local kept, decomposed, essence = {}, 0, 0
        for i, entry in ipairs(b.generated) do
            same(b, entry.value, a.generated[i].value, "新装备全部字段/顺序一致 " .. i)
            local item = entry.equip
            if not item.locked and b.BS.shouldAutoDecompose(before.equipment.settings, item.quality, item.level) then
                decomposed = decomposed + 1
                essence = essence + b.BS.calcAutoDecomposeEssence(item.quality, item.level)
            else kept[#kept + 1] = item end
        end
        local stored = math.min(free, #kept)
        eq(b.ES.getInventoryCount(b.data.equipment), b.capacity - free + stored, "真实500容量上限/余量")
        eq(#b.data.lootbox.seeds, #before.lootbox.seeds + #kept - stored, "溢出逐件入遗匣不丢弃")
        for i, item in ipairs(kept) do
            if i <= free then
                eq(b.data.equipment.inventory[tostring(item.seq)], item, "入库保留生成实例")
            else
                local entry = b.data.lootbox.seeds[#before.lootbox.seeds + i - stored]
                eq(entry.equip, item, "入匣保留生成实例")
                eq(entry.source, "overflow", "沿用正式满包来源标记")
            end
        end
        for key, old in pairs(before.equipment.inventory) do
            same(b, b.data.equipment.inventory[key], old, "旧库存不追溯分解/改写")
        end
        for i, old in ipairs(before.lootbox.seeds) do same(b, b.data.lootbox.seeds[i], old, "旧遗匣及未确定旧种子不变") end
        eq(actual.autoDecomposeCount or 0, decomposed, "分解数按真实新实例计算")
        eq(actual.autoDecomposeEssence or 0, essence, "精粹按真实规则计算")
        eq(b.data.currency.essence, before.currency.essence + essence, "精粹仅本次加一次")
        if essence > 0 then
            eq(b.data.lootbox.autoDecomposeNotice.count, decomposed, "分解通知准确累计")
            eq(b.data.lootbox.autoDecomposeNotice.essence, essence, "分解通知金额")
        end
        -- 独立构造每队经验份额，真实Exp升级后再走正式共鸣，不借被测交付结果作期望。
        local heroes = b.copy(before.heroes.roster)
        local expectedGrants = {}
        for _, reward in ipairs(oracle.teamRewards) do
            for _, id in ipairs(before.heroes.teams[reward.teamIdx].slots) do
                if tonumber(id) > 0 and reward.adventurerExp > 0 then
                    local gain = math.floor(reward.adventurerExp / reward.heroCount + 0.5)
                    expectedGrants[tonumber(id)] = gain
                    local hero = heroes[id] or heroes[tostring(id)]
                    hero.exp = hero.exp + gain; b.ET.autoLevelUpHero(hero)
                end
            end
        end
        if next(expectedGrants) then b.require("shared.heroes.HeroResonance").syncRosterToResonance(heroes) end
        same(b, b.data.heroes.roster, heroes, "英雄经验/连续升级/正式共鸣精确一致")
        local seen = {}
        for _, grant in ipairs(actual.heroExpGrants) do
            eq(grant.expGain, expectedGrants[grant.heroId], "英雄只领取本队经验")
            check(not seen[grant.heroId], "英雄不得跨队重复领取"); seen[grant.heroId] = true
        end
        for id in pairs(expectedGrants) do eq(seen[id], true, "不漏合法英雄经验") end
        local player = b.copy(before.player)
        player.exp = player.exp + oracle.adventureExp; b.ET.autoLevelUpPlayer(player)
        same(b, b.data.player, player, "玩家经验沿真实Exp曲线")
        rewardsOnly(b, before)
        eq(a.data.session.lastOnlineTime, a.now, "正式领取推进真实在线时间")
        eq(a.data.battle.idleAccumSec, 0, "正式初算清旧在线积累")
        if before.battle.offlineChallengeSources then
            eq(a.data.battle.offlineChallengeSources, nil, "正式初算消费覆盖来源，CE严格保留")
        end
    end)
end

local function rejectionCases()
    for _, name in ipairs({ "session", "currency", "heroes", "player", "equipment", "lootbox", "battle" }) do
        case("缺模块 " .. name .. " 拒绝且修复后可调用", function()
            local h = newFixture()
            local removed = h.data[name]; h.data[name] = nil
            local before, rng = h.copy(h.data), h.rngCalls
            h.forbidRNG = true
            local ok, reason = h.Offline.GrantDebugDayRewards(1)
            eq(ok, false, "未加载拒绝"); check(type(reason) == "string", "明确原因")
            same(h, h.data, before, "缺数据无金币/经验/装备/会话提前变动")
            eq(h.rngCalls, rng, "缺数据零RNG"); eq(next(h.dirty), nil, "缺数据零通知")
            h.data[name], h.forbidRNG = removed, false
            requireSuccess(h.Offline.GrantDebugDayRewards(1), nil, "普通false不锁死")
        end)
    end
    for _, target in ipairs({ "roster", "inventory" }) do
        case("缺结构 " .. target, function()
            local h = newFixture()
            local owner = target == "roster" and h.data.heroes or h.data.equipment
            owner[target] = nil
            local before = h.copy(h.data); h.forbidRNG = true
            eq(h.Offline.GrantDebugDayRewards(1), false, "无结构拒绝")
            same(h, h.data, before, "无结构不提前改动")
            eq(h.rngCalls, 0, "无结构零RNG")
        end)
    end
    case("已有pending完整值和所有引用保持/零RNG", function()
        local h = newFixture()
        local panel = assert(h.Offline.CalcOnEnter(1))
        local pending = pendingOf(h)[1]
        local values, refs, before = h.copy(pending), graph(pending), h.copy(h.data)
        local rng = h.rngCalls; h.forbidRNG = true
        eq(h.Offline.GrantDebugDayRewards(1), false, "有pending拒绝直接CE")
        check(h.CE.giveOfflineDayRewards():find("请先领取", 1, true) ~= nil, "真实CEService拒绝pending")
        eq(h.Offline.CalcOnEnter(1), panel, "重推同一panel")
        eq(pendingOf(h)[1], pending, "正式pending对象不替换")
        same(h, pending, values, "完整待领值不变"); graphUnchanged(refs, "pending拒绝")
        same(h, h.data, before, "拒绝期间完整玩家模块不变")
        eq(h.rngCalls, rng, "拒绝/重推零RNG")
        eq(h.saves, 0, "拒绝不请求保存"); eq(h.bridgeCalls, 0, "拒绝不初始化桥")
        requireSuccess(h.Offline.ClaimRewards(1), nil, "原pending仍可正常领取")
        h.forbidRNG = false
        requireSuccess(h.Offline.GrantDebugDayRewards(1), nil, "领取后新的主动调用可加一天")
    end)
    for _, mode in ipairs({ "tower", "empty", "dirty" }) do
        case("全队无产出 " .. mode, function()
            local h = newFixture()
            if mode == "tower" then
                h.data.battle.offlineChallengeSources = {}
                for i = 1, 3 do h.data.battle.offlineChallengeSources[tostring(i)] = {
                    sourceKind = "tower", stageId = 400001, paused = true } end
            elseif mode == "empty" then
                for i = 1, 3 do h.data.heroes.teams[i].slots = { 0, 0, 0, 0 } end
            else
                h.data.heroes.teams = { { slots = { 1, 1 } }, { slots = { [2] = 2 } }, { slots = { 99999 } } }
            end
            local before = h.copy(h.data); h.forbidRNG = true
            eq(h.Offline.GrantDebugDayRewards(1), false, "无收益不能发奖")
            same(h, h.data, before, "无收益不清来源/不借deployed/不变动数据")
            eq(h.rngCalls, 0, "无收益零RNG"); eq(next(h.dirty), nil, "无收益无通知")
        end)
    end
end

local function integrationCases()
    for _, blocked in ipairs({ "boot", "panel" }) do
        case("CEService前置门禁 " .. blocked, function()
            local h = newFixture()
            h.ready, h.panelOpen = blocked ~= "boot", blocked == "panel"
            local before = h.copy(h.data); h.forbidRNG = true
            local text = h.CE.giveOfflineDayRewards()
            check(text:find(blocked == "boot" and "完成游戏入场" or "关闭离线奖励面板", 1, true), "明确门禁提示")
            same(h, h.data, before, "未就绪不发奖")
            eq(h.bridgeCalls, 0, "门禁先于Bridge")
            eq(h.captures, 0, "门禁先于Capture")
            eq(h.saves, 0, "门禁不保存"); eq(h.rngCalls, 0, "门禁零RNG")
        end)
    end
    case("真实CE接线/即时Capture/同步重入/每次主动再给一天", function()
        local h, raw = newFixture(), newFixture()
        local snapshot = h.copy(h.data.battle)
        snapshot.teamStageIds = { 100001, 200001, 300001 }
        snapshot.offlineChallengeSources = { ["1"] = { sourceKind = "dungeon", stageId = 100001 } }
        h.liveSnapshot = snapshot
        local saved, snapshotBefore = h.copy(h.data.battle), h.copy(snapshot)
        local reentries = 0
        h.onDirty = function(key)
            if key ~= "currency" or reentries > 0 then return end
            reentries = reentries + 1
            local before, rng = h.copy(h.data), h.rngCalls
            check(h.CE.giveOfflineDayRewards():find("正在发放", 1, true), "同步CE重入busy")
            local ok, why = h.Offline.GrantDebugDayRewards(1)
            eq(ok, false, "同步Service重入拒绝"); check(why:find("正在发放", 1, true), "共享交付锁")
            eq(h.Offline.ClaimRewards(1), false, "同步Claim拒绝")
            eq(h.Offline.CalcOnEnter(1), nil, "同步初算不能创建pending")
            same(h, h.data, before, "重入不变动任何数据"); eq(h.rngCalls, rng, "重入零额外RNG")
        end
        h.onSave = function()
            check((h.dirty.player or 0) > 0 and (h.dirty.lootbox or 0) > 0, "保存请求在完整交付之后")
        end
        local spec = { { teamIdx = 1, stageId = 100001, heroCount = 1 },
            { teamIdx = 2, stageId = 200001, heroCount = 2 }, { teamIdx = 3, stageId = 300001, heroCount = 3 } }
        local dayGold = raw.Calc.previewTeamOfflineRewards(86400, spec, raw.SC).gold
        check(dayGold > 0, "重复调用对照日金币非零")
        for iteration = 1, 2 do
            local priorGold = h.data.currency.gold
            local text = h.CE.giveOfflineDayRewards()
            check(text:find("已获得一天", 1, true), "真实CE调用成功")
            eq(h.data.currency.gold, priorGold + dayGold, "每次新的主动调用确实再增加整日金币")
            requireSuccess(raw.Offline.GrantDebugDayRewards(1, raw.copy(snapshot)), nil, "显式即时快照对照")
            for _, key in ipairs({ "currency", "equipment", "lootbox", "player", "heroes" }) do
                same(h, h.data[key], raw.data[key], "第" .. iteration .. "次CE接线与直接真实Service一致 " .. key)
            end
            eq(h.saves, iteration, "每次主动调用只RequestSave一次")
            eq(h.captures, iteration, "每次主动调用重新Capture")
            eq(h.bridgeCalls, iteration, "每次只初始化一次Bridge")
        end
        eq(reentries, 1, "确实触发同步MarkDirty重入")
        same(h, h.data.battle, saved, "Capture不反写保存battle")
        same(h, snapshot, snapshotBefore, "即时快照本身保持只读")
        eq(h.Offline.HasPendingRewards(1), false, "同步初算没有留下幽灵pending")
        eq(h.order[1], "bridge", "先Bridge")
        eq(h.order[2], "capture", "后Capture")
        eq(h.order[#h.order], "request-save", "最后请求保存")
    end)
    case("正式Claim的currency/session通知重入均拒绝", function()
        local h = newFixture()
        assert(h.Offline.CalcOnEnter(1))
        local seen = {}
        h.onDirty = function(key)
            if (key ~= "currency" and key ~= "session") or seen[key] then return end
            seen[key] = true
            local before, rng = h.copy(h.data), h.rngCalls
            local ok, why = h.Offline.ClaimRewards(1)
            eq(ok, false, "Claim重入拒绝"); check(why:find("正在发放", 1, true), "Claim直到session通知仍持锁")
            eq(h.Offline.GrantDebugDayRewards(1), false, "Claim期间CE拒绝")
            eq(h.Offline.CalcOnEnter(1), nil, "Claim期间初算不建新pending")
            h.CE.giveOfflineDayRewards()
            same(h, h.data, before, "Claim同步通知重入数据不变")
            eq(h.rngCalls, rng, "Claim重入零RNG")
        end
        h.forbidRNG = true
        requireSuccess(h.Offline.ClaimRewards(1), nil, "正式Claim成功")
        eq(seen.currency, true, "覆盖真实currency通知")
        eq(seen.session, true, "覆盖pending清除之后session通知")
        eq(h.Offline.HasPendingRewards(1), false, "没有新pending")
    end)
    for _, point in ipairs({ "bridge", "capture" }) do
        case("CE外围异常释放busy " .. point, function()
            local h = newFixture()
            local before = h.copy(h.data)
            h.bridgeError, h.captureError = point == "bridge", point == "capture"
            check(h.CE.giveOfflineDayRewards():find("发放异常", 1, true), "外围异常明确报告")
            same(h, h.data, before, "发奖前异常没有部分到账")
            eq(h.saves, 0, "外围异常不保存"); eq(h.rngCalls, 0, "外围异常零RNG")
            h.bridgeError, h.captureError = false, false
            check(h.CE.giveOfflineDayRewards():find("已获得一天", 1, true), "外围busy解锁可新调用")
        end)
    end
    for _, point in ipairs({ "calc", "currency" }) do
        case("Service异常锁释放/本会话熔断 " .. point, function()
            local h = newFixture()
            local provider = h.require("shared.StageProvider")
            local get, before = provider.Get, h.copy(h.data)
            if point == "calc" then provider.Get = function() error("expected calc failure") end
            else h.onDirty = function(key) if key == "currency" then error("expected notification failure") end end end
            local text = h.CE.giveOfflineDayRewards()
            check(text:find("发放异常", 1, true), "CEService捕获真实Service异常")
            eq(h.saves, 0, "Service失败不请求保存")
            if point == "calc" then same(h, h.data, before, "计算前异常数据不变")
            else check(h.data.currency.gold > before.currency.gold, "异常可能部分入账，不伪造回滚通过") end
            provider.Get, h.onDirty = get, nil
            local after, rng = h.copy(h.data), h.rngCalls; h.forbidRNG = true
            local ok, why = h.Offline.GrantDebugDayRewards(1)
            eq(ok, false, "本会话拒绝重复发奖")
            check(why:find("上次发放异常", 1, true), "明确熔断而非残留busy锁")
            check(h.CE.giveOfflineDayRewards():find("上次发放异常", 1, true), "CEbusy也已释放，转交Service熔断")
            local claim, reason = h.Offline.ClaimRewards(1)
            eq(claim, false, "无正式pending"); check(reason:find("无待领取", 1, true), "Claim没有残留交付锁")
            same(h, h.data, after, "熔断拒绝保持部分结果不重复到账")
            eq(h.rngCalls, rng, "熔断零RNG")
        end)
    end
    case("正式Claim的session异常仍释放锁", function()
        local h = newFixture()
        assert(h.Offline.CalcOnEnter(1))
        h.onDirty = function(key) if key == "session" then error("expected session notification failure") end end
        local called, err = pcall(h.Offline.ClaimRewards, 1)
        eq(called, false, "session异常外传"); check(tostring(err):find("expected session", 1, true), "命中session通知")
        h.onDirty = nil
        local ok, why = h.Offline.ClaimRewards(1)
        eq(ok, false, "pending已消费不重发")
        check(why:find("无待领取", 1, true), "异常后不是永久busy")
        requireSuccess(h.Offline.GrantDebugDayRewards(1), nil, "正式Claim异常不误设CE熔断")
    end)
end

local function panelCase()
    case("真实CEPanel绘制按钮/按下抬起只一次", function()
        local h = newFixture()
        ---@type table<string, { x: number, y: number }>
        local textCalls = {}
        local noop = function() end
        for _, key in ipairs({ "nvgBeginPath", "nvgRoundedRect", "nvgFillColor", "nvgFill", "nvgStrokeColor",
            "nvgStrokeWidth", "nvgStroke", "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgSave",
            "nvgRestore", "nvgIntersectScissor" }) do h.env[key] = noop end
        h.env.nvgRGBA = function() return {} end
        h.env.nvgText = function(_, x, y, text) textCalls[text] = { x = x, y = y } end
        local p = h.Panel
        eq(p.isOpen(), false, "默认关闭")
        eq(p.handleDown(100, 464, 1080), false, "关闭无捕获")
        p.toggle(); p.draw({}, 1920, 1080)
        local button = assert(textCalls["获得一天离线奖励"], "新按钮实际draw存在")
        local other = assert(textCalls["重置存档"], "相邻不同按钮存在")
        local before = h.copy(h.data)
        eq(p.handleDown(button.x, button.y, 1080), true, "真实按下捕获")
        same(h, h.data, before, "按下不立即发奖"); eq(h.saves, 0, "按下零保存")
        eq(p.handleUp(other.x, other.y, 1080), true, "异按钮抬起只吞手势")
        same(h, h.data, before, "异按钮抬起不发奖也不清档")
        eq(p.handleUp(button.x, button.y, 1080), false, "旧手势已释放")
        eq(p.handleDown(button.x, button.y, 1080), true, "新按下")
        eq(p.handleUp(button.x, button.y, 1080), true, "同按钮抬起触发")
        eq(h.saves, 1, "真实Panel到CE到Service只交付一次")
        local after = h.copy(h.data)
        eq(p.handleUp(button.x, button.y, 1080), false, "重复Up不重复触发")
        same(h, h.data, after, "重复Up数据不变")
        p.handleDown(button.x, button.y, 1080); p.toggle()
        eq(p.handleUp(button.x, button.y, 1080), true, "关闭期间Up吞掉旧手势")
        same(h, h.data, after, "关闭取消不触发")
        p.toggle(); p.handleDown(button.x, button.y, 1080); p.handleUp(button.x, button.y, 1080)
        eq(h.saves, 2, "新的完整主动点击允许再加一天")
        p.toggle()
    end)
end

function Start()
    local originalRandom, originalSeed, originalTime = math.random, math.randomseed, os.time
    local originalBoot, originalSave = package.loaded["boot.Standalone"], package.loaded["boot.StandaloneSave"]
    local ok, err = pcall(function()
        pair("三队当前主线/497余量")
        pair("500满包全部溢出", { free = 0 })
        pair("三资源金币装备黑钻", { free = 0, specs = {
            { teamIdx = 1, stageId = 100001, heroCount = 1 }, { teamIdx = 2, stageId = 200001, heroCount = 2 },
            { teamIdx = 3, stageId = 300001, heroCount = 3 } }, configure = function(h)
                h.data.battle.teamStageIds = { 100001, 200001, 300001 }
            end })
        pair("即时挑战来源/塔暂停不借主线", { specs = {
            MAIN[1], { teamIdx = 2, stageId = 100001, heroCount = 2, sourceKind = "dungeon" },
            { teamIdx = 3, stageId = 400001, heroCount = 3, sourceKind = "tower", paused = true } },
            configure = function(h) h.data.battle.offlineChallengeSources = {
                ["2"] = { sourceKind = "dungeon", stageId = 100001 },
                ["3"] = { sourceKind = "tower", stageId = 400001, paused = true } } end })
        pair("明确空队不借deployed", { specs = { MAIN[1], MAIN[3] }, configure = function(h)
            h.data.heroes.teams[2].slots = { 0, 0, 0, 0 }
        end })
        pair("未通905锁住二三队", { specs = { MAIN[1] }, configure = function(h)
            h.data.battle.maxStageId, h.data.battle.clearedStages = 905, {}
        end })
        pair("全品质自动分解不追溯旧装备", { free = 0, settings = { autoQuality = 6, autoLevel = 0 } })
        pair("双条件自动分解保留其他件", { settings = { autoQuality = 3, autoLevel = 1 } })
        pair("锁定新装备分解豁免", { settings = { autoQuality = 6, autoLevel = 0 },
            configure = function(h) h.lockGenerated = true end })
        rejectionCases()
        integrationCases()
        panelCase()
    end)
    if not ok then check(false, "setup exception " .. tostring(err)) end
    case("隔离边界最终审计", function()
        for _, h in ipairs(fixtures) do
            eq(h.fileCalls, 0, "实际FileFS调用0")
            eq(h.bootLoads, 0, "实际正式Boot加载0")
        end
        eq(math.random, originalRandom, "宿主RNG函数不变")
        eq(math.randomseed, originalSeed, "宿主seed函数不变")
        eq(os.time, originalTime, "宿主时钟函数不变")
        eq(package.loaded["boot.Standalone"], originalBoot, "宿主Boot模块缓存不变")
        eq(package.loaded["boot.StandaloneSave"], originalSave, "宿主Save模块缓存不变")
    end)
    print(TAG .. " SUMMARY cases=" .. cases .. " assertions=" .. assertions .. " failures=" .. failures)
    engine:Exit()
    if failures > 0 then error(TAG .. " FAILED", 0) end
    print(TAG .. " ALL PASS")
end
