-- 三队共享首通链回归：真实 Page/Scene/Boot/Driver/StoryPlayer/SyncBattleState。
-- 页面和奖励出口使用内存替身，不读取或覆盖玩家存档，不运行随机战斗。
local assertions, failures = 0, 0
local function check(value, label)
    assertions = assertions + 1
    if not value then failures = failures + 1 end
    print("[tri_clear_unlock] " .. (value and "PASS " or "FAIL ") .. label)
end

local function runCase(label, fn)
    local before = assertions
    local ok, err = pcall(fn)
    if not ok then check(false, label .. " 异常: " .. tostring(err)) end
    print(string.format("[tri_clear_unlock] CASE %s assertions=%d", label, assertions - before))
end

-- 每个子例独立编译业务模块：真实结算/奖励/镜像/分发/消息桥/恢复，
-- 只替换战斗资源、UI、钱包及存档出口，不复用生产模块的私有状态。
local function runBattleLedgerCases(nativeRequire)
    local function noop() end
    local function stub(fields)
        return setmetatable(fields or {}, { __index = function() return noop end })
    end
    local function source(name)
        local f = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"))
        local lines = {}
        while not f:IsEof() do lines[#lines + 1] = f:ReadLine() end
        f:Dispose()
        return table.concat(lines, "\n")
    end
    local SC = nativeRequire("config.StageConfig")
    local AD = nativeRequire("systems.AttributeDef")
    local schema = nativeRequire("shared.battle.BattleSchema")
    local real = {
        ["ui.battle.scene.BattleScene"] = true,
        ["ui.battle.scene.BattleDataRestore"] = true,
        ["ui.battle.tri.BattleTriDriver"] = true,
        ["ui.battle.tri.BattleTriPage"] = true,
        ["ui.battle.tri.TerminalRaid"] = true,
        ["ui.battle.tri.TerminalSceneFlow"] = true,
        ["ui.battle.tri.TerminalReincarnation"] = true,
        ["ui.battle.tri.BattleTriStageProgress"] = true,
        ["ui.battle.tri.BattleEntryPreparation"] = true,
        ["ui.battle.stage.BattleSpeed"] = true,
        ["boot.StandaloneSave"] = true,
        ["ui.battle.stage.BattleEnemySpawn"] = true,
        ["boot.StandaloneBoot"] = true,
        ["runtime.ClientDispatcher"] = true,
        ["runtime.ClientMessageHandler"] = true,
    }
    local function fixture(stageId, maxId, cleared, preserveNumericKeys)
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.time = { elapsedTime = 0 }
        local modules = {}
        local wallet = { gold = 0, gems = 0, essence = 0, arcaneDust = 0,
            goldenKey = 0, corruptStone = 0, sacredStone = 0, exp = 0 }
        local firstCalls, updates, restores, saves = 0, 0, 0, 0
        local outgoing = {}
        local lastRestoreData
        local function unit(id, hero)
            return { hp = 1000, maxHp = 1000, monsterId = id, heroId = hero and id or nil,
                attrs = { final = { [AD.HP] = 1000, [AD.MAX_HP] = 1000 }, tickEnergyShield = noop },
                goldReward = 0, expReward = 0 }
        end
        local ally = unit(1, true)
        local gameState = stub({ getName = function() return "账本测试" end,
            addExp = function(amount) wallet.exp = wallet.exp + amount end })
        for _, field in ipairs({ "gold", "gems", "essence", "arcaneDust", "goldenKey", "corruptStone", "sacredStone" }) do
            local suffix = field:sub(1, 1):upper() .. field:sub(2)
            gameState["get" .. suffix] = function() return wallet[field] end
            gameState["set" .. suffix] = function(value) wallet[field] = value end
        end
        modules["config.StageConfig"] = SC
        modules["shared.battle.BattleSchema"] = schema
        modules["systems.AttributeDef"] = AD
        modules["config.ExpTable"] = stub({ TEAM_COUNT = 3, getUnlockedTeamCount = function() return 1 end })
        modules["shared.StageProvider"] = { Get = function() return SC end }
        modules["shared.ModuleRegistry"] = { applyOnLoad = function(name, data)
            if name == "battle" then schema.Fields.battle.onLoad(data) end
        end }
        modules["shared.schemas.CharacterSchema"] = { applyOnLoad = noop }
        modules["core.GameState"] = gameState
        modules["core.I18n"] = { lookup = function(text) return text end }
        -- 布局常量与坐标使用独立编译的真实事实源，缺字段不能回退成 noop 函数。
        modules["core.BattleLayout"] = assert(load(source("core.BattleLayout"),
            "@core.BattleLayout", "t", env))()
        modules["config.MonsterConfig"] = { createMonster = function(id) return unit(id, false) end }
        modules["ui.character.panel.CharacterPanel"] = stub({
            getTeamSignature = function() return "ledger-team-1" end,
            getDeployedTeam = function() return { ally } end })
        modules["ui.battle.stage.BattleStageNav"] = { NAV = {} }
        -- 倍率实现真实执行，仅绘图为叶子替身。
        modules["ui.battle.stage.BattleStageLoad"] = { load = function(ctx, id)
            ctx.currentStageId = id
            ctx.isFirstClear = not ctx.clearedStages[id]
        end }
        modules["ui.battle.stage.BattleStageNavLogic"] = { bind = function() return stub() end }
        modules["ui.battle.scene.BattleAllyLifecycle"] = { bind = function(deps)
            -- 常规战斗叶子仍用替身；显式清档必须走本地真实 resetToDefault，不能手抄清表。
            local lifecycle = assert(load(source("ui.battle.scene.BattleAllyLifecycle"),
                "@真实清档/BattleAllyLifecycle", "t", env))().bind(deps)
            return stub({ resetToDefault = lifecycle.resetToDefault })
        end }
        modules["systems.OfflineCalc"] = { resolveIdleStageAnchors = function() return stageId, stageId end,
            calcOnlineIdleRewards = function() return {} end }
        modules["systems.BattleTimeout"] = { calcMult = function() return 1 end }
        modules["systems.CombatFormula"] = { calcHpRegen = function() return 0 end }
        modules["systems.DropSystem"] = stub({ generateFirstClearEquips = function() return {} end,
            generateFirstClearScrolls = function() return nil end,
            rollKillDrop = function() return nil end, rollScrollDrop = function() return nil end })
        modules["systems.LootBoxSystem"] = stub({ getTotalCount = function() return 0 end })
        modules["ui.story.gate.LetterIntro"] = { isOpen = function() return false end }
        modules["ui.story.gate.IntroCutscene"] = { isActive = function() return false end }
        modules["ui.story.ScenarioDialogue"] = { isActive = function() return false end }
        for _, name in ipairs({ "ui.battle.combat.BattleCombat", "ui.battle.combat.ProjectileSystem",
            "systems.ThreatManager", "systems.TalentManager", "ui.battle.combat.BattleEffects",
            "systems.StatusEffectManager" }) do
            modules[name] = stub({ newState = function() return {} end,
                newBattleRefs = function() return {} end, newFxState = function() return {} end,
                newSemState = function() return {} end })
        end
        modules["ui.battle.combat.BattleCombat"].newState = function() return { ctx = {} } end
        env.require = function(name)
            if modules[name] then return modules[name] end
            local module
            if real[name] then
                module = assert(load(source(name), "@" .. name, "t", env))()
            else
                module = stub()
            end
            modules[name] = module
            return module
        end
        local Scene = env.require("ui.battle.scene.BattleScene")
        local Dispatcher = env.require("runtime.ClientDispatcher")
        local Msg = env.require("runtime.ClientMessageHandler")
        local setData = Scene.setBattleData
        Scene.setBattleData = function(data)
            restores = restores + 1
            lastRestoreData = data
            return setData(data)
        end
        Msg.setup({ sendAction = noop })
        Msg.setupDataSubscriptions()
        local update = Dispatcher.handleStateUpdate
        Dispatcher.handleStateUpdate = function(json)
            local decoded = cjson.decode(json)
            if decoded.modules and decoded.modules.battle then
                updates = updates + 1
                outgoing[#outgoing + 1] = decoded.modules.battle
            end
            return update(json)
        end
        local publish = Dispatcher.publishLive
        Dispatcher.publishLive = function(name, data)
            if name == "battle" then
                updates = updates + 1
                outgoing[#outgoing + 1] = cjson.decode(cjson.encode(data))
            end
            return publish(name, data)
        end
        local Save = env.require("boot.StandaloneSave")
        Save.Flush = function() saves = saves + 1 end
        -- 测试模块仅在独立 Dispatcher 中注入；不经玩家存档 RestoreData。
        Dispatcher.set("equipment", { inventory = {}, equipped = {}, nextSeq = 1 })
        Dispatcher.set("lootbox", { seeds = {} })
        Dispatcher.set("session", { introCompleted = true, claimedScenarios = {} })
        local battle = {
            currentStageId = stageId, maxStageId = maxId, clearedStages = cleared or {},
            teamStageIds = { ["1"] = stageId }, battleMode = "idle", idleAccumSec = 17,
        }
        if preserveNumericKeys then
            -- 真实set保留数字键，仍经真实onAnyUpdate→Msg→Restore；后续Sync走JSON。
            Dispatcher.set("battle", battle)
        else
            Dispatcher.handleStateUpdate(cjson.encode({ modules = { battle = battle } }))
        end
        env.require("boot.StandaloneBoot").run({ vg = {}, localSendAction = noop })
        local forward = Scene.onFirstClear
        Scene.onFirstClear = function(id, team)
            firstCalls = firstCalls + 1
            return forward(id, team)
        end
        local syncSource = assert(source("boot.Standalone"):match("(local battleSync =.-)\nlocal physW"))
        env.BattleScene, env.ClientDispatcher, env.cjson = Scene, Dispatcher, cjson
        env.StandaloneSave, env.StageConfig, env.bootReady_, env.StandaloneRT = Save, SC, true, {}
        local sync = assert(load(syncSource .. "\nreturn SyncBattleState", "@正式SyncBattleState", "t", env))()
        local Driver = env.require("ui.battle.tri.BattleTriDriver")
        local makeDriver = Driver.new
        local drivers = {}
        Driver.new = function(team, options)
            local driver = makeDriver(team, options)
            drivers[team] = driver
            return driver
        end
        local Page = env.require("ui.battle.tri.BattleTriPage")
        Save.SetBattlePage(Page)
        return { scene = Scene, dispatcher = Dispatcher, wallet = wallet, env = env, drivers = drivers,
            page = Page, sync = sync,
            firstCalls = function() return firstCalls end,
            counters = function() return updates, restores, saves end,
            outgoing = outgoing, lastRestoreData = function() return lastRestoreData end }
    end
    local function marked(data, id)
        local cleared = data.clearedStages or {}
        return cleared[id] == true or cleared[tostring(id)] == true
    end
    local function victory(f)
        if not f.page.isOpen() then f.page.open() end
        local driver = assert(f.drivers[1])
        -- 仅设置敌方死亡边界；真实Page回调、Driver补位、胜利及行军均不替换。
        driver.introTimer = 0
        for frame = 1, 40 do
            for _, enemy in ipairs(driver.enemies) do
                enemy.hp = 0
                enemy.attrs.final[AD.HP] = 0
            end
            f.env.time.elapsedTime = f.env.time.elapsedTime + 1
            f.page.update(1)
            if driver._clearReported then return driver end
        end
        error("真实 Driver 未触发胜利")
    end
    runCase("B01 最高关真实胜利→两Sync→再次胜利", function()
        local f = fixture(34505, 34505, {})
        check(SC.getNextStageId(34505) == nil, "最高关确实没有下一节点")
        local firstDriver = victory(f)
        check(f.firstCalls() == 1 and marked(f.dispatcher.get("battle"), 34505)
            and f.scene.getClearedStages()[34505], "第一次真实胜利写入双源且回调一次")
        local gold = SC.getStage(34505).fcGold
        check(f.wallet.gold == gold, "第一次真实Boot金币到账86300")
        local _, beforeRestores = f.counters()
        f.sync(1.1)
        check(f.scene.getClearedStages()[34505] and marked(f.dispatcher.get("battle"), 34505),
            "第一次实时同步保持最高关双源首通")
        f.sync(1.1)
        check(f.scene.getClearedStages()[34505] and marked(f.dispatcher.get("battle"), 34505),
            "第二次实时同步不能把丢标传播到永久账本")
        local updates, restored = f.counters()
        check(updates >= 2 and restored == beforeRestores and f.lastRestoreData() ~= f.dispatcher.get("battle"),
            "真实Dispatcher→publishLive保留账本但不回灌Scene Restore")
        firstDriver:update(1)
        check(firstDriver.stageId == 34505 and not firstDriver._clearReported, "无下一关经真实advanceStage重开")
        victory(f)
        check(f.firstCalls() == 1 and f.wallet.gold == gold, "再次真实胜利首通回调仍一次且金币不重复")
        check(f.wallet.exp == SC.getStage(34505).fcExp and f.wallet.gems == SC.getStage(34505).fcDiamond,
            "再次胜利经验与钻石也只有一份")
        f.page.close()
    end)
    for _, keyKind in ipairs({ "number", "string" }) do
        runCase("B01 最高关已通恢复 " .. keyKind, function()
            local key = keyKind == "number" and 34505 or "34505"
            local f = fixture(34505, 34505, { [key] = true }, keyKind == "number")
            check(f.scene.getClearedStages()[34505] and marked(f.dispatcher.get("battle"), 34505),
                keyKind .. "最高关恢复保留双源标记")
            f.sync(1.1)
            f.sync(1.1)
            check(f.scene.getClearedStages()[34505] and marked(f.dispatcher.get("battle"), 34505),
                keyKind .. "最高关两次同步保持标记")
            victory(f)
            check(f.firstCalls() == 0 and f.wallet.gold == 0, keyKind .. "已通最高关再胜利不发首通")
            check(f.scene.getStageId() == 34505 and f.dispatcher.get("battle").currentStageId == 34505,
                keyKind .. "最高关不伪造下一关")
            f.page.close()
        end)
    end
    for _, keyKind in ipairs({ "number", "string" }) do
        runCase("B01 普通中断推进 " .. keyKind, function()
            local key = keyKind == "number" and 1305 or "1305"
            local f = fixture(1305, 1305, { [key] = true }, keyKind == "number")
            check(f.scene.getStageId() == 1305 and f.scene.getClearedStages()[1305],
                keyKind .. "普通已通当前关恢复不删首通且不自动推进")
            f.sync(1.1)
            f.sync(1.1)
            check(marked(f.dispatcher.get("battle"), 1305) and f.scene.getClearedStages()[1305],
                keyKind .. "普通中断两次同步保留双源首通")
            check(f.scene.getStageId() == 1305 and f.dispatcher.get("battle").currentStageId == 1305
                and f.dispatcher.get("battle").battleMode == "idle", keyKind .. "已通普通关保留合法当前位置与idle")
            victory(f)
            check(f.firstCalls() == 0 and f.wallet.gold == 0, keyKind .. "中断恢复后再胜利不重复首通")
            f.page.close()
        end)
    end
    runCase("B01 终焉入口与一队旧关", function()
        local f = fixture(2305, 2305, { ["2305"] = true })
        f.sync(1.1)
        f.sync(1.1)
        check(f.scene.getStageId() == 2305 and f.scene.getClearedStages()[2305]
            and marked(f.dispatcher.get("battle"), 2305), "终焉前末关双源标记稳定")
        check(not marked(f.dispatcher.get("battle"), SC.TERMINAL_NORMAL)
            and f.scene.getMaxStageId() == 2305, "终焉入口不伪造终焉首通或轮回")
        local old = fixture(1001, 2305, { ["1001"] = true, ["1905"] = true, ["2305"] = true })
        old.sync(1.1)
        old.sync(1.1)
        check(old.scene.getStageId() == 1001 and old.dispatcher.get("battle").currentStageId == 1001,
            "一队旧关恢复不拉到共享最高关")
        check(old.scene.getMaxStageId() == 2305 and marked(old.dispatcher.get("battle"), 1905)
            and marked(old.dispatcher.get("battle"), 2305), "一队旧关不回退其他队共享解锁")
        check(old.dispatcher.get("battle").idleAccumSec == 17, "账本同步保留其他存档字段")
    end)
    runCase("B01 Sync双源合并与同数量换键", function()
        local f = fixture(101, 101, {})
        f.scene.getClearedStages()[102] = true
        f.dispatcher.get("battle").clearedStages["103.0"] = true
        f.dispatcher.get("battle").clearedStages["106"] = false
        f.dispatcher.get("battle").clearedStages["not-a-stage"] = true
        f.sync(1.1)
        local sent = f.outgoing[#f.outgoing]
        check(marked(sent, 102) and marked(sent, 103), "正式Sync合并本地独有与镜像独有首通")
        check(sent.clearedStages["102"] == true and sent.clearedStages["103"] == true,
            "Sync双源数字键统一为字符串永久键")
        check(sent.clearedStages["103.0"] == nil and not marked(sent, 106)
            and sent.clearedStages["not-a-stage"] == nil, "decimal关号规范为唯一整数键且false/非法键不标通")
        local before = #f.outgoing
        -- 固定两份输入都为两条，隔离内容比较和数量比较；不是显式reset入口。
        f.scene.getClearedStages()[102], f.scene.getClearedStages()[103] = nil, nil
        f.scene.getClearedStages()[104], f.scene.getClearedStages()[105] = true, true
        f.dispatcher.get("battle").clearedStages = { ["102"] = true, ["103"] = true }
        f.sync(1.1)
        sent = f.outgoing[#f.outgoing]
        check(#f.outgoing == before + 1 and marked(sent, 104) and marked(sent, 105),
            "同数量换键仍按内容变化触发真实同步")
        check(marked(sent, 102) and marked(sent, 103), "同数量换键不删除已有永久首通事实")
        local after = #f.outgoing
        f.sync(1.1)
        check(#f.outgoing == after, "双源合并稳定后不每秒重复发送")
    end)
    runCase("B01 同数量内容变化与显式空账本", function()
        local f = fixture(101, 101, {})
        f.scene.getClearedStages()[102], f.scene.getClearedStages()[103] = true, true
        f.dispatcher.get("battle").clearedStages = { ["102"] = true, ["103"] = true }
        f.sync(1.1)
        local before = #f.outgoing
        f.scene.getClearedStages()[102], f.scene.getClearedStages()[103] = nil, nil
        f.scene.getClearedStages()[104], f.scene.getClearedStages()[105] = true, true
        f.sync(1.1)
        local sent = f.outgoing[#f.outgoing]
        check(#f.outgoing == before + 1 and marked(sent, 104) and marked(sent, 105),
            "已缓存数量2后换成另外两键不能被数量相等跳过")
        check(marked(sent, 102) and marked(sent, 103), "同数量内容变更保留镜像已通事实")
        -- 普通空快照不是reset：即使max回到第一关，也不能擦掉已确认的账本。
        f.scene.setBattleData({ currentStageId = 101, maxStageId = 101, clearedStages = {} })
        check(f.scene.getClearedStages()[102] and f.scene.getClearedStages()[103]
            and f.scene.getClearedStages()[104] and f.scene.getClearedStages()[105],
            "普通空快照无max后备仍保留四个已通事实")
        -- 沿真实reset入口清两源；Sync不能从内部缓存复活旧通关。
        f.scene.resetToDefault()
        f.dispatcher.reset()
        f.env.require("runtime.ClientMessageHandler").setupDataSubscriptions()
        f.dispatcher.set("battle", { currentStageId = 101, maxStageId = 101, clearedStages = {} })
        f.sync(1.1)
        check(next(f.scene.getClearedStages()) == nil
            and next(f.dispatcher.get("battle").clearedStages) == nil, "双源显式清空后不复活旧标记")
        check(f.firstCalls() == 0 and f.wallet.gold == 0, "同步和reset结果验证本身不发奖励")
        f.scene.setBattleData(nil)
        f.scene.setBattleData({ currentStageId = 101, maxStageId = 101, clearedStages = {} })
        f.dispatcher.get("battle").clearedStages = nil
        local nilOk = pcall(function() f.sync(1.1) end)
        check(nilOk and next(f.scene.getClearedStages()) == nil,
            "nil恢复输入和缺失镜像账本不报错不误标")
    end)
end

function Start()
    assertions, failures = 0, 0
    local nativeRequire = require
    local nativeTime = time
    local restores = {}
    local function replace(owner, key, value)
        local previous = owner[key]
        restores[#restores + 1] = function() owner[key] = previous end
        owner[key] = value
    end
    local ok, err = pcall(function()
        local Scene = nativeRequire("ui.battle.scene.BattleScene")
        local Driver = nativeRequire("ui.battle.tri.BattleTriDriver")
        local Dispatcher = nativeRequire("runtime.ClientDispatcher")
        local Store = nativeRequire("core.PlayerStore")
        local SC = nativeRequire("config.StageConfig")
        local ExpTable = nativeRequire("config.ExpTable")
        local Story = nativeRequire("systems.StoryPlayer")
        local DataRestore = nativeRequire("ui.battle.scene.BattleDataRestore")
        local Dungeon = nativeRequire("rules.dungeon.DungeonService")
        local PDM = nativeRequire("rules.character.PlayerDataManager")
        local modules = {
            battle = { currentStageId = 1001, maxStageId = 1001, battleMode = "firstClear",
                clearedStages = { ["905"] = true }, idleAccumSec = 17 },
            session = { introCompleted = true, initialHeroId = 1, claimedScenarios = {} },
            heroes = { roster = {}, deployed = {}, teams = {} },
            lootbox = { seeds = {} }, equipment = { inventory = {}, equipped = {} }, player = { name = "测试" },
            dungeon = { ancient_ruin = { floor = 1, dailyUsed = 0 } },
        }
        local flushes, notifications, popups, firstCalls = 0, 0, {}, 0
        local wallet = { gold = 0, gems = 0, essence = 0, arcaneDust = 0, goldenKey = 0,
            corruptStone = 0, sacredStone = 0, exp = 0 }
        local function noop() end
        local function stub(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local function source(name)
            local f = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"))
            local lines = {}
            while not f:IsEof() do lines[#lines + 1] = f:ReadLine() end
            f:Dispose()
            return table.concat(lines, "\n")
        end
        local function compile(name)
            return assert(load(source(name), "@" .. name, "t", _G))()
        end
        replace(Dispatcher, "get", function(key) return modules[key] end)
        replace(Store, "Get", function(key) return modules[key] end)
        replace(PDM, "GetModule", function(_, key) return modules[key] end)
        replace(PDM, "MarkDirty", function() error("挑战资格检查不能改档") end)
        replace(Dispatcher, "notifySubscribers", function(key)
            if key == "battle" then notifications = notifications + 1 end
        end)
        replace(Dispatcher, "handleStateUpdate", function(json)
            local update = cjson.decode(json)
            modules.battle = update.modules.battle
            Scene.setBattleData(modules.battle)
        end)
        local gameState = stub({ getName = function() return "测试" end,
            getLevel = function() return 100 end,
            addExp = function(amount) wallet.exp = wallet.exp + amount end })
        for _, field in ipairs({ "gold", "gems", "essence", "arcaneDust", "goldenKey", "corruptStone", "sacredStone" }) do
            local suffix = field:sub(1, 1):upper() .. field:sub(2)
            gameState["get" .. suffix] = function() return wallet[field] end
            gameState["set" .. suffix] = function(value) wallet[field] = value end
        end
        -- 先按真实存档初始化场景，后续同步回灌只更新进度，不启动第二套战斗。
        Scene.setBattleData(modules.battle)
        local mocks = {
            ["shared.StageProvider"] = { Get = function() return SC end },
            ["config.DungeonConfig"] = nativeRequire("config.DungeonConfig"),
            ["ui.battle.scene.BattleScene"] = Scene, ["ui.battle.tri.BattleTriDriver"] = Driver,
            ["runtime.ClientDispatcher"] = Dispatcher, ["core.PlayerStore"] = Store,
            ["config.StageConfig"] = SC, ["config.ExpTable"] = ExpTable,
            ["systems.StoryPlayer"] = Story, ["core.GameState"] = gameState,
            ["boot.StandaloneSave"] = { Flush = function() flushes = flushes + 1 end },
            ["systems.DropSystem"] = stub({ generateFirstClearEquips = function() return {} end,
                generateFirstClearScrolls = function() return nil end }),
            ["systems.LootBoxSystem"] = stub({ getTotalCount = function() return 0 end }),
            ["ui.character.panel.CharacterPanel"] = stub({ getTeamSignature = function(t) return "team" .. t end,
                getDeployedTeam = function() return {} end }),
            ["ui.hud.popup.RewardPopup"] = stub({ show = function(title, rewards, opts)
                popups[#popups + 1] = { title = title, rewards = rewards, opts = opts }
            end }),
            ["core.I18n"] = nativeRequire("core.I18n"),
        }
        replace(_G, "require", function(name)
            if mocks[name] then return mocks[name] end
            if name == "ui.battle.tri.BattleTriStageProgress" or name == "ui.battle.tri.TerminalSceneFlow"
                or name == "ui.battle.tri.TerminalReincarnation" or name == "ui.battle.tri.BattleEntryPreparation"
                or name == "ui.battle.stage.BattleSpeed" then
                mocks[name] = compile(name)
            else
                mocks[name] = stub()
            end
            return mocks[name]
        end)
        replace(_G, "time", { elapsedTime = 100 })
        replace(Scene, "pumpBattleCards", noop)
        Scene.adoptStageProgress(1001)
        Scene.getClearedStages()[905] = true
        local Boot = compile("boot.StandaloneBoot")
        Boot.run({ vg = {}, localSendAction = noop, setLocalBridgeReady = noop })
        local forwardFirst = Scene.onFirstClear
        replace(Scene, "onFirstClear", function(id, team)
            firstCalls = firstCalls + 1
            forwardFirst(id, team)
        end)
        local drivers = {}
        local makeDriver = Driver.new
        replace(Driver, "new", function(team)
            local drv = makeDriver(team)
            drv.start = function(self, id)
                self.stageId, self.active = id, true
                self.allies, self.enemies, self.enemyQueue = { { hp = 100, heroId = team } }, {}, {}
                self.teamSignature = "team" .. team
                self.marchTimer, self.marchNotice, self.introTimer = 0, false, 0
                self._clearReported = false
                self.starts = (self.starts or 0) + 1
            end
            -- 本测试使用真实胜利判定和行军，跳过伤害、绘图及单位资源初始化。
            drv.reportDefeatedEnemies = noop
            drv.reinforceDeadEnemies = noop
            drv.tickRewards = noop
            drivers[team] = drv
            return drv
        end)
        local Page = compile("ui.battle.tri.BattleTriPage")
        mocks["ui.battle.tri.BattleTriPage"] = Page
        local Save = compile("boot.StandaloneSave")
        Save.SetBattlePage(Page)
        mocks["boot.StandaloneSave"].CaptureBattleProgress = Save.CaptureBattleProgress
        Page.open()
        check(drivers[1] and drivers[2] and not drivers[3], "905通关后只有前两队存在")
        local combat = nativeRequire("ui.battle.combat.BattleCombat")
        for _, key in ipairs({ "setCardAnim", "updateCardAnims", "updateFloatingTexts", "updateHitFlashes" }) do
            replace(combat, key, noop)
        end
        local firstStage, firstStarts = drivers[1].stageId, drivers[1].starts
        check(not Dungeon.Challenge(1, "ancient_ruin", 1), "二队首通前上古遗迹仍锁定")
        drivers[2].stageId = 1305
        drivers[2]:tick(0.1)
        check(modules.battle.clearedStages["1305"] and Scene.getClearedStages()[1305], "真实二队tick写入双源通关账本")
        check(modules.battle.maxStageId == 1401 and Scene.getMaxStageId() == 1401, "二队胜利解锁下一章")
        check(Dungeon.Challenge(1, "ancient_ruin", 1), "二队首通后真实上古遗迹挑战门禁开放")
        check(modules.battle.currentStageId == 1001 and modules.battle.battleMode == "firstClear"
            and Scene.getStageId() == 1001, "二队首通不改一队当前关及模式")
        check(wallet.gold == SC.getStage(1305).fcGold and wallet.exp == SC.getStage(1305).fcExp,
            "二队走真实Boot首通奖励且仅到账一份")
        check(firstCalls == 1 and #popups == 1 and popups[1].opts.row == 1, "复用现有行一奖励显示出口")
        local story = Story.take()
        check(story and story.scenarioId == 55 and Story.take() == nil, "二队1305触发真实首通情景55")
        check(drivers[2].marchTimer > 0 and drivers[2].stageId == 1305, "登记首通不截断二秒行军")
        drivers[2]:tick(2)
        check(drivers[2].stageId == 1401 and drivers[1].stageId == firstStage
            and drivers[1].starts == firstStarts, "二队自行前进且一队不重开")
        local gold = wallet.gold
        drivers[1].onStageCleared(1, 1305)
        check(firstCalls == 1 and wallet.gold == gold and #popups == 1, "一队追赶已通节点不重复发首通")
        check(Scene.getStageId() == 1401 and modules.battle.currentStageId == 1401,
            "一队追赶仍同步本队下一关，不被去重早返卡住")
        Scene.adoptStageProgress(1001)
        modules.battle.currentStageId, modules.battle.battleMode = 1001, "firstClear"
        drivers[2].onStageCleared(2, 1905)
        check(ExpTable.getUnlockedTeamCount(modules.battle) == 3, "二队1905首通立即解锁三队")
        check(Scene.getMaxStageId() == 2001 and modules.battle.maxStageId == 2001, "选关与门禁共享最新上限")
        Page.close()
        Page.open()
        check(drivers[3] ~= nil, "新解锁三队驱动正常创建")
        drivers[3].onStageCleared(3, 2001)
        check(modules.battle.clearedStages["2001"] and modules.battle.maxStageId == 2002,
            "三队同样推进全局首通")
        check(Scene.getStageId() == 1001 and modules.battle.currentStageId == 1001,
            "三队推进不拉走一队")
        local beforeDuplicate = firstCalls
        Scene.getClearedStages()[2002] = nil
        modules.battle.clearedStages[2002] = true
        drivers[2].onStageCleared(2, 2002)
        check(firstCalls == beforeDuplicate and Scene.getClearedStages()[2002], "持久化数字键去重并修补本地账本")
        Scene.getClearedStages()[2003] = nil
        modules.battle.clearedStages["2003"] = true
        drivers[3].onStageCleared(3, 2003)
        check(firstCalls == beforeDuplicate and Scene.getClearedStages()[2003], "持久化字符串键同样去重")
        drivers[2].onStageCleared(2, 2305)
        check(Scene.getMaxStageId() == 2305 and modules.battle.maxStageId == 2305
            and not modules.battle.clearedStages["999"], "末关只解锁终焉入口，不伪造轮回")
        check(Scene.getStageId() == 1001, "二队末关通关仍不改变一队")
        local calls = firstCalls
        check(not Scene.completeTriStageClear(999, 2) and not Scene.completeTriStageClear(1305, 0)
            and not Scene.completeTriStageClear(1305.5, 2) and not Scene.completeTriStageClear(1305, 2.5)
            and firstCalls == calls, "普通入口拒绝终焉与无效参数")
        check(notifications > 0 and flushes > 0, "首通实际通知数据镜像并请求持久化")
        -- 执行正式每秒镜像函数，证明不是只验证手抄同步逻辑。
        local syncSource = assert(source("boot.Standalone"):match("(local battleSync =.-)\nlocal physW"))
        local env = setmetatable({ BattleScene = Scene, ClientDispatcher = Dispatcher, cjson = cjson,
            StandaloneSave = mocks["boot.StandaloneSave"], StageConfig = SC,
            bootReady_ = true, StandaloneRT = {} }, { __index = _G })
        local sync = assert(load(syncSource .. "\nreturn SyncBattleState", "@正式SyncBattleState", "t", env))()
        sync(1.1)
        check(modules.battle.clearedStages["1905"] and modules.battle.clearedStages["2305"],
            "每秒整表镜像不擦掉二三队首通")
        check(modules.battle.currentStageId == 1001 and modules.battle.idleAccumSec == 17,
            "整表回灌保留一队关卡与其他存档字段")
        -- 真正的首次恢复分支不得把一队合法旧关强制改为其他队的最高关。
        local values = { currentStageId = 101, initialBattleDataLoaded = false, battleActive = false,
            clearedStages = {}, maxStageId_ = 101 }
        local loadedId = 0
        local restore = DataRestore.bind({ getStageConfig = function() return SC end,
            loadStage = function(id) loadedId = id values.currentStageId = id end,
            resetAllyUnit = noop, startBattleTalents = noop, recalcIdleIncome = noop,
            getAllies = function() return {} end,
            get = function(key) return values[key] end,
            set = function(key, value) values[key] = value end })
        restore.setBattleData(cjson.decode(cjson.encode(modules.battle)))
        check(loadedId == 1001 and values.currentStageId == 1001 and values.maxStageId_ == 2305,
            "JSON读档恢复共享解锁但保留一队选择的旧关")
        check(values.clearedStages[1905] and values.clearedStages[2305], "读档后三队与终焉入口仍解锁")
        Page.close()
    end)
    for i = #restores, 1, -1 do
        local cleaned, cleanupErr = pcall(restores[i])
        if not cleaned then check(false, "退出清理异常: " .. tostring(cleanupErr)) end
    end
    rawset(_G, "require", nativeRequire)
    rawset(_G, "time", nativeTime)
    if not ok then check(false, "原共享首通用例异常: " .. tostring(err)) end
    runCase("B01账本闭环用例组", function() runBattleLedgerCases(nativeRequire) end)
    print(string.format("[tri_clear_unlock_test] SUMMARY: %d assertions, %d failures", assertions, failures))
    if failures > 0 then
        log:Write(LOG_ERROR, "[tri_clear_unlock_test] FAILED: " .. failures .. " failures")
    else
        print("[tri_clear_unlock_test] ALL PASS: " .. assertions .. " assertions")
    end
    engine:Exit()
end
