-- 通关/ETS同步回执热路径：真实Panel/Power/ETS/HeroService/StageProgress及Boot奖励闭包。
-- 私有模块实例、确定性RNG及内存保存叶子；不运行main，不读写玩家档。
-- full oracle仅关闭Power差分，奖励、经验、通知与保存时点仍运行同一正式代码。
local checks, failures = 0, 0
local function check(value, message)
    checks = checks + 1
    if not value then failures = failures + 1; print("[StageHotpaths][FAIL] " .. message) end
end
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, item in pairs(value) do out[key] = copy(item, seen) end
    return out
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function source(path)
    local file = assert(cache:GetFile(path), path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function noop() end

local function fixture(forceFull)
    local f = { modules = {}, data = {}, trace = {}, scores = 0, creates = 0, counts = 0,
        io = 0, rng = 0, seed = 1729, pending = {}, progress = {}, saves = {}, live = {},
        context = {}, values = { Gold = 1000, Gems = 0, Essence = 0, ArcaneDust = 0 },
        phaseScores = {}, phaseCPU = {}, phaseCreates = {}, phaseCounts = {}, observerCPU = 0 }
    local env = setmetatable({}, { __index = _G }) ---@type any
    env._G, env.math = env, copy(math)
    env.print = function(...) -- 订阅者被pcall吞掉的异常必须成为测试失败。
        for i = 1, select("#", ...) do
            local value = tostring(select(i, ...))
            if value:find("subscriber error", 1, true) or value:find("error module=", 1, true) then
                error(value, 0)
            end
        end
    end
    env.File = function() f.io = f.io + 1; error("stage fixture forbids player File") end
    env.fileSystem = setmetatable({}, { __index = function() return env.File end })
    env.IsNetworkMode = function() return false end
    env.math.randomseed = function() error("fixture cannot reseed gameplay RNG") end
    env.math.random = function(lo, hi)
        f.seed = f.seed * 48271 % 2147483647
        f.rng = f.rng + 1
        local value = f.seed / 2147483647
        if lo == nil then return value end
        if hi == nil then hi, lo = lo, 1 end
        return lo + math.floor(value * (hi - lo + 1))
    end
    -- 深值证据冻结是测试观测成本，单独计CPU，不能冒充正式通关耗时。
    local function event(name, data)
        local started = os.clock()
        f.trace[#f.trace + 1] = { name = name, data = copy(data) }
        f.observerCPU = f.observerCPU + os.clock() - started
    end
    local gs = { getLevel = function() return 100 end,
        setPower = function(value) f.gamePower = value; event("gamePower", value) end,
        addExp = function(amount) f.playerExp = (f.playerExp or 0) + amount; event("playerExp", amount) end }
    setmetatable(gs, { __index = function(_, key)
        if key:sub(1, 3) == "get" then return function() return f.values[key:sub(4)] or 0 end end
        if key:sub(1, 3) == "set" then return function(value)
            f.values[key:sub(4)] = value; event(key, value)
        end end
    end })
    local scene = { getClearedStages = function() return f.live end,
        getMaxStageId = function() return f.maxStage or 101 end,
        getStageId = function() return f.currentStage or 101 end,
        adoptStageProgress = function(id) f.currentStage = id end,
        setOnFirstClear = function(fn) f.firstClear = fn end,
        onFirstClear = function(...) return f.firstClear(...) end,
        setOnEnemyKill = function(fn) f.kill = fn end,
        refreshAllyStats = function() event("scenePending") end }
    local draw = { MAX_SLOTS = 4, MAX_PER_ROW = 4, ROW1_CY = 300, ROW_SPACING = 200,
        ROSTER_BOTTOM_DY = 100, SCROLL_BOTTOM = 1800, SCROLL_TOP = 0,
        SCROLL_LEFT = 0, SCROLL_RIGHT = 1080, DESIGN_W = 1080,
        setContext = function(ctx) f.context = ctx end, initImages = noop,
        getSharedImages = function() return {} end, resetPresentation = noop }
    local mocks = {
        ["core.GameState"] = gs,
        ["ui.character.panel.CharacterPanelDraw2"] = draw,
        ["ui.character.detail.CharacterDetail"] = { init = noop, setContext = noop,
            markPowerDirty = function() event("detailDirty") end,
            hasAwakeningUpgrade = function() return false end, hasAnyUpgradeForHero = function() return false end },
        ["ui.hud.BottomNav"] = { setBadge = noop, refreshTownBadge = noop },
        ["ui.church.ChurchPage"] = { hasAdvanceForHero = function() return false end },
        ["ui.hud.popup.OfflineRewardPanel"] = { isOpen = function() return false end },
        ["ui.battle.scene.BattleScene"] = scene,
        ["ui.battle.tri.BattleTriPage"] = { setOnKill = noop, invalidateTeams = function(t) event("invalidateTeams", t) end,
            refreshHeroProgressTeams = function(teams, classes)
                event("progress", { teams = teams, classes = classes })
                f.progress[#f.progress + 1] = copy(teams)
            end },
        ["core.EventBus"] = { emit = function(name, payload)
            if name == "CG_TeamPowerChanged" then
                local p = f.modules["ui.character.panel.CharacterPanel"]
                if p then
                    for team = 1, 3 do check(p.getTotalPower(team) == payload.powers[team], "事件前整队缓存已就绪") end
                end
            end
            event(name, payload)
        end },
        ["ui.fx.SpineCardEffect"] = { playLevelUp = function() event("levelUpVisual") end },
        ["systems.StoryPlayer"] = { onStage = function(id, phase) event("story", { id, phase }) end },
        ["ui.hud.popup.RewardPopup"] = { show = function(title, rewards, options)
            event("popup", { title, rewards, options })
        end },
        ["boot.StandaloneSave"] = { Flush = function()
            local started = os.clock()
            local snapshot = { data = copy(f.data), values = copy(f.values), playerExp = f.playerExp }
            f.saves[#f.saves + 1] = snapshot
            f.observerCPU = f.observerCPU + os.clock() - started
            event("flush", snapshot); return true
        end, RequestSave = function() event("saveRequest") end },
        ["rules.character.PlayerDataManager"] = { GetModule = function(_, name) return f.data[name] end,
            MarkDirty = function(_, name)
                event("markDirty", name)
                f.modules["runtime.ClientDispatcher"].set(name, f.data[name], { normalized = true })
            end },
    }
    env.require = function(name)
        if mocks[name] then return mocks[name] end
        if f.modules[name] then return f.modules[name] end
        local value = assert(load(source(name:gsub("%.", "/") .. ".lua"), "@stage-hotpaths/" .. name, "t", env))()
        f.modules[name] = value
        return value
    end
    f.load, f.event, f.env = env.require, event, env
    local EP, HC = env.require("systems.EquipmentPower"), env.require("config.HeroConfig")
    local build, create = EP.buildWornContext, HC.createHero
    EP.buildWornContext = function(...) f.scores = f.scores + 1; return build(...) end
    HC.createHero = function(...) f.creates = f.creates + 1; return create(...) end
    local Power = env.require("ui.character.panel.CharacterPower")
    local bind = Power.bind
    Power.bind = function(deps)
        local power = bind(deps)
        if forceFull then
            local refresh = power.refreshPowerCache
            power.refreshPowerCache = function(cause) return refresh(cause) end
        end
        return power
    end
    local ETS = env.require("systems.ExtraTalentSystem")
    local panel = env.require("ui.character.panel.CharacterPanel")
    f.panel, f.ets, f.hc = panel, ETS, HC
    panel.init({}) -- 与正式boot一致：Panel先注册heroes，Store.Init随后才注册。
    local dispatcher, store = env.require("runtime.ClientDispatcher"), env.require("core.PlayerStore")
    store.Init()
    f.dispatcher, f.store = dispatcher, store
    local heroes = { roster = {}, deployed = { 1, 3, 4, 5 }, teams = {
        { slots = { 1, 3, 4, 5 } }, { slots = { 9, 20, 12, 23 } }, { slots = { 15, 10, 18, 24 } } } }
    for _, id in ipairs(HC.getAllIds()) do
        heroes.roster[tostring(id)] = { level = 70, exp = 0, maxExp = 100,
            awakening = { [1] = true, [2] = true, [3] = true, _awk3Migrated = true },
            extraTalent = ETS.normalize({ stacks = 10, issuedCards = 2 }), advBranch = {} }
    end
    f.data = { heroes = heroes, equipment = { inventory = {}, equipped = {}, nextSeq = 1 },
        artifacts = { bag = {}, equippedByTeam = {} }, talents = { litNodes = { 113, 124 } },
        battle = { currentStageId = 101, maxStageId = 4905, clearedStages = { ["905"] = true, ["1905"] = true } },
        lootbox = { seeds = {} } }
    local Eq = env.require("systems.EquipmentSystem")
    local inventoryCount = Eq.getInventoryCount
    Eq.getInventoryCount = function(...)
        f.counts = f.counts + 1
        return inventoryCount(...)
    end
    for seq = 1, 1000 do
        local item = assert(Eq.generate("C1", 70, 3)); item.seq = seq
        f.data.equipment.inventory[tostring(seq)] = item
    end
    f.data.equipment.nextSeq = 1001
    f.data.equipment.equipped["12"] = { accessory = 1 }
    f.data.equipment.equipped["23"] = { accessory = 2 }
    for _, name in ipairs({ "equipment", "artifacts", "talents", "battle", "lootbox", "heroes" }) do
        dispatcher.set(name, f.data[name], { normalized = true })
    end
    local service = env.require("rules.hero.HeroService")
    mocks["runtime.GameAction"] = { sendAction = function(action, payload)
        event("send", { action = action, payload = payload })
        local ok, reason, result = service.SyncExtraTalent(1, payload.heroId, payload.extraTalent)
        assert(ok, reason); event("receipt", result)
    end }
    dispatcher.subscribe("heroes", function(data) event("heroesNotify", data) end)
    dispatcher.subscribe("equipment", function(data) event("equipmentNotify", data) end)
    dispatcher.subscribe("lootbox", function(data) event("lootboxNotify", data) end)
    dispatcher.subscribe("battle", function(data) event("battleNotify", data) end)
    -- 整段正式奖励闭包：无人工改写奖励公式或抽走RNG/通知。
    local boot = source("boot/StandaloneBoot.lua")
    local first = assert(boot:find("-- 首通战斗击杀掉落先暂存", 1, true))
    local last = assert(boot:find("---@param rt table", first, true))
    local rewardFirst = assert(boot:find("    BattleScene.setOnFirstClear(function(clearedStageId, teamIdx)", 1, true))
    local rewardLast = assert(boot:find("\n    -- 5.3 初始阵容", rewardFirst, true))
    local killFirst = assert(boot:find("    local handleKillRewards = function(data)", 1, true))
    local killLast = assert(boot:find("\n    -- 5.15", killFirst, true))
    local rewardEnv = setmetatable({ require = env.require, M = {},
        GameState = gs, StageConfig = env.require("config.StageConfig"),
        ExpTable = env.require("config.ExpTable"), DropSystem = env.require("systems.DropSystem"),
        BlacksmithConfig = env.require("config.BlacksmithConfig"), EquipmentSystem = Eq,
        LootBoxSystem = env.require("systems.LootBoxSystem"), ClientDispatcher = dispatcher,
        StandaloneSave = mocks["boot.StandaloneSave"], CharacterPanel = panel,
        BattleScene = scene, BattleTriPage = mocks["ui.battle.tri.BattleTriPage"],
        RewardPopup = mocks["ui.hud.popup.RewardPopup"] }, { __index = env })
    assert(load(boot:sub(first, last - 1) .. "\n" .. boot:sub(killFirst, killLast - 1)
        .. "\n" .. boot:sub(rewardFirst, rewardLast - 1), "@actual-Boot-reward-chain", "t", rewardEnv))()
    f.complete = function(id, team)
        return env.require("ui.battle.tri.BattleTriStageProgress").complete(scene, id, team,
            function(max) f.maxStage = max end)
    end
    f.measure = function(phase, action)
        local scores, creates, counts, observed, started = f.scores, f.creates, f.counts, f.observerCPU, os.clock()
        action()
        f.phaseCPU[phase] = (f.phaseCPU[phase] or 0) + os.clock() - started - (f.observerCPU - observed)
        f.phaseScores[phase] = (f.phaseScores[phase] or 0) + f.scores - scores
        f.phaseCreates[phase] = (f.phaseCreates[phase] or 0) + f.creates - creates
        f.phaseCounts[phase] = (f.phaseCounts[phase] or 0) + f.counts - counts
    end
    f.observation = function()
        local powers = {}
        for team = 1, 3 do powers[team] = panel.getTotalPower(team) end
        local roster = {}
        for _, id in ipairs(HC.getAllIds()) do roster[id] = panel.getRosterPower(id) end
        return { data = copy(f.data), values = copy(f.values), playerExp = f.playerExp,
            trace = copy(f.trace), saves = copy(f.saves), powers = powers, roster = roster,
            rng = f.rng, seed = f.seed, live = copy(f.live), current = f.currentStage, max = f.maxStage }
    end
    f.trace, f.saves, f.progress = {}, {}, {}
    return f
end

function Start()
    local ok, err = xpcall(function()
        local optimized, full = fixture(false), fixture(true)
        local function both(action, label)
            action(optimized); action(full)
            check(same(optimized.observation(), full.observation()), label .. "奖励/经验/RNG/通知/保存快照顺序与全量oracle一致")
        end
        local SC = optimized.load("config.StageConfig")
        local id = 101
        for round = 1, 7 do
            local stage = id
            both(function(f)
                local ETS, panel = f.ets, f.panel
                ETS.mount(ETS.newState())
                local state = ETS.mountedState()
                for _, hid in ipairs({ 1, 3, 12, 23 }) do
                    local own = panel.getOwnedHero(hid)
                    local unit = assert(f.hc.createHero(hid, own.level, own.advBranch, own.awakening, own.extraTalent))
                    state.pendingGrowth[hid], state.growthUnits[hid] = { stacks = 1 }, unit
                end
                f.measure("flush", ETS.flush)
                check(not next(state.pendingGrowth) and not next(state.dirty), "ETS当帧提交完整且消费账本")
                local sends = #f.trace
                ETS.flush()
                check(#f.trace == sends, "空flush不重复发奖/通知")
                f.measure("kill", function() f.kill({ stageId = stage, expReward = 1, goldReward = 7,
                    heroIds = { 1, 3, 4, 5 }, allyCount = 4 }) end)
                f.measure("clear", function() check(f.complete(stage, 1), "首次通关账本返回true") end)
            end, "round" .. round)
            local nextId = SC.getNextStageId(id)
            if nextId and not SC.isTerminalTemple(nextId) then id = nextId else id = id + 100 end
        end
        both(function(f)
            local saveCount = #f.saves
            f.measure("repeatClear", function() check(not f.complete(101, 3), "重复通关不发首通奖励") end)
            check(#f.saves == saveCount, "重复通关仍仅RequestSave不同步flush")
        end, "repeat clear")
        -- 真实等级变化必须当帧更新，不允许把后续装备通知当延迟升级出口。
        both(function(f)
            local own = f.panel.getOwnedHero(12)
            local before = own.level
            local amount = f.load("config.ExpTable").getHeroExpForLevel(before)
            f.measure("level", function() f.panel.addHeroesExp({ 12 }, amount) end)
            check(f.panel.getOwnedHero(12).level > before, "升级在经验入账调用返回前生效")
            check(f.data.heroes.roster["12"].level == f.panel.getOwnedHero(12).level, "同步持久化英雄等级")
        end, "timely level")
        local baseline = rawget(_G, "StageHotpathsBaseline") == true -- 只供固定父版本受控A/B宿主。
        check(optimized.phaseScores.clear == (baseline and 175 or 0), "七次首通不重复构建未变化的全名册")
        check(optimized.phaseScores.flush == 56 and full.phaseScores.flush == 175,
            "ETS仍当帧评分真实八人依赖闭包，不吞成长或延后评分")
        check(optimized.phaseScores.level == 25, "真实升级仍保持即时完整评分")
        for _, phase in ipairs({ "flush", "kill", "clear", "repeatClear", "level" }) do
            print(string.format("[StageHotpaths] phase=%s calls=%d fullCalls=%d creates=%d fullCreates=%d cpu=%.6f fullCPU=%.6f inventoryCounts=%d",
                phase, optimized.phaseScores[phase] or 0, full.phaseScores[phase] or 0,
                optimized.phaseCreates[phase] or 0, full.phaseCreates[phase] or 0,
                optimized.phaseCPU[phase] or 0, full.phaseCPU[phase] or 0, optimized.phaseCounts[phase] or 0))
        end
        check(optimized.io == 0 and full.io == 0, "全链没有玩家File/FS访问")
        local capture = rawget(_G, "StageHotpathsCapture") -- 外部隔离宿主可冻结完整业务证据作跨SHA差分。
        if type(capture) == "function" then capture(optimized.observation()) end
        print(string.format("[StageHotpaths] business rounds=7 rng=%d saves=%d events=%d",
            optimized.rng, #optimized.saves, #optimized.trace))
    end, debug.traceback)
    if not ok then check(false, "exception " .. tostring(err)) end
    print(string.format("[stage_clear_hotpaths_test] %s assertions=%d failures=%d",
        failures == 0 and "ALL PASS" or "FAIL", checks, failures))
    engine:Exit()
end
