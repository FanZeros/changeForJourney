-- 终焉真实链夹具；默认分支从terminal_raid_test原样抽取，资源来源只由显式options启用。
local SC = require("config.StageConfig")
local HC = require("config.HeroConfig")
local Driver = require("ui.battle.tri.BattleTriDriver")
local M = {}

function M.bind(hooks)
    local compileModule, patch, defer, check, clearShield =
        hooks.compileModule, hooks.patch, hooks.defer, hooks.check, hooks.clearShield
    -- 真正Scene/Nav/三队/Story/Intro与保存快照串联；IO仅采集JSON，不读写玩家档。
    local function terminalFlowFixture(stageId, options)
        local deps, state = {}, { reward = false, pendingReward = false, tutorial = false,
            recovery = false, dialogue = false, starts = 0, snapshots = {}, arrivals = {}, kills = {} }
        local env = setmetatable({}, { __index = _G })
        env.require = function(name) return deps[name] or require(name) end
        local battle = { currentStageId = SC.getTerminalPrevStageId(stageId), maxStageId = SC.getTerminalPrevStageId(stageId),
            clearedStages = { [tostring(SC.getTerminalPrevStageId(stageId))] = true } }
        local session = { introCompleted = true, initialHeroId = 1, claimedScenarios = {} }
        local dungeon = {}
        if options then
            local DC = require("config.DungeonConfig")
            for _, id in ipairs(DC.RESOURCE_IDS) do
                -- 足以恢复任一合法测试锚点的真实资源台账，不改isStageUnlocked。
                dungeon[id] = { floor = DC.MAX_FLOOR[id], cleared = {} }
                for floor = 1, DC.MAX_FLOOR[id] do dungeon[id].cleared[tostring(floor)] = true end
            end
            battle.teamStageIds = {}
            for row = 1, 3 do
                local source = options.sources[row]
                assert(SC.getStage(source) and not SC.isTerminalTemple(source), "来源必须是合法主线/资源关")
                assert(not SC.isResourceStage(source) or DC.isStageUnlocked(source, battle, dungeon), "资源来源必须真实解锁")
                battle.teamStageIds[tostring(row)] = source
            end
            battle.currentStageId = options.sources[1]
            env.time = { elapsedTime = 100 }
        end
        local Dispatcher = require("runtime.ClientDispatcher")
        local oldGet = Dispatcher.get
        patch(Dispatcher, "get", function(name)
            if name == "battle" then return battle end
            if name == "session" then return session end
            if options and name == "dungeon" then return dungeon end
            return oldGet(name)
        end)
        if options then
            -- Nav与Page分别读PDM/Dispatcher；两端必须映射同一合法模块表，不能放宽解锁。
            local PDM = require("rules.character.PlayerDataManager")
            local oldModule = PDM.GetModule
            patch(PDM, "GetModule", function(uid, name)
                if uid == 1 and name == "battle" then return battle end
                if uid == 1 and name == "dungeon" then return dungeon end
                return oldModule(uid, name)
            end)
            -- 真Nav/Scene/Flow使用同一夹具Page，未知require仍走原依赖，不泛化stub。
            deps["ui.battle.popup.TerminalConfirmDialog"] = compileModule("ui.battle.popup.TerminalConfirmDialog", env)
            deps["ui.battle.stage.BattleStageNavLogic"] = compileModule("ui.battle.stage.BattleStageNavLogic", env)
            deps["ui.battle.popup.BattleResultPanel"] = { isOpen = function() return false end }
        end
        deps["ui.hud.popup.RewardPopup"] = { isOpen = function() return state.reward end,
            hasPendingBattleRewards = function() return state.pendingReward end,
            currentRowTag = function() return nil end,
            show = function() state.reward = true end }
        deps["ui.tutorial.TutorialPageRecovery"] = { isPendingStoryBlocked = function() return state.recovery end }
        deps["systems.TutorialManager"] = { canPlayPendingStory = function() return not state.tutorial end }
        deps["ui.story.ScenarioDialogue"] = { isActive = function() return state.dialogue end }
        deps["ui.story.gate.LetterIntro"] = { isOpen = function() return false end }
        deps["systems.StoryPlayer"] = compileModule("systems.StoryPlayer", env)
        local Story = deps["systems.StoryPlayer"]
        local Scene = compileModule("ui.battle.scene.BattleScene", env)
        deps["ui.battle.scene.BattleScene"] = Scene
        deps["ui.battle.tri.TerminalSceneFlow"] = compileModule("ui.battle.tri.TerminalSceneFlow", env)
        deps["ui.battle.tri.BattleTriStageProgress"] = compileModule("ui.battle.tri.BattleTriStageProgress", env)
        local Page = compileModule("ui.battle.tri.BattleTriPage", env)
        deps["ui.battle.tri.BattleTriPage"] = Page
        deps["ui.battle.tri.TerminalReincarnation"] = compileModule("ui.battle.tri.TerminalReincarnation", env)
        local Save = compileModule("boot.StandaloneSave", env)
        deps["boot.StandaloneSave"] = Save
        Save.SetBattlePage(Page)
        Save.Flush = function()
            local snapshot = Save.CaptureBattleProgress(battle)
            state.snapshots[#state.snapshots + 1] = cjson.decode(cjson.encode(snapshot))
            return true
        end
        -- NavLogic/Driver底层模块仍引用真实保存单例，在边界统一替为同一采集函数。
        patch(require("boot.StandaloneSave"), "Flush", Save.Flush)
        patch(require("ui.hud.BottomNav"), "setAllLocked", function(locked) state.locked = locked end)
        patch(require("systems.GameBGM"), "setScene", function() end)
        patch(require("ui.battle.stage.StageEntryEvents"), "notify", function(id, team)
            state.arrivals[#state.arrivals + 1] = { id = id, team = team }
            Story.onStage(id, "enter")
            return true
        end)
        patch(require("ui.battle.stage.StageEntryEvents"), "retry", function() end)
        local introEnv = setmetatable({ require = env.require, cache = { GetResource = function() return nil end } }, { __index = _G })
        local Intro = compileModule("ui.story.gate.IntroCutscene", introEnv)
        deps["ui.story.gate.IntroCutscene"] = Intro
        local sourceFile = assert(cache:GetFile("boot/StandaloneBoot.lua"))
        local lines = {}
        while not sourceFile:IsEof() do lines[#lines + 1] = sourceFile:ReadLine() end
        sourceFile:Dispose()
        local source = table.concat(lines, "\n")
        local first = assert(source:find("    BattleScene.setOnReincarnate(function(data)", 1, true))
        local last = assert(source:find("\n    -- 5.25 首通奖励", first, true))
        local wiringEnv = setmetatable({ BattleScene = Scene, IntroCutscene = Intro }, { __index = _G })
        local oldIntroStart = Intro.start
        Intro.start = function(cb) state.starts = state.starts + 1; oldIntroStart(cb) end
        assert(load(source:sub(first, last - 1), "@真实StandaloneBoot轮回闭包", "t", wiringEnv))()
        -- 首通闭包完整运行，仅奖励生成/页面显示等叶子是替身，真实关卡配置与Story保留。
        first = assert(source:find("    BattleScene.setOnFirstClear(function(clearedStageId, teamIdx)", 1, true))
        last = assert(source:find("\n    -- 5.3 初始阵容", first, true))
        local values = {}
        local GS = setmetatable({}, { __index = function(_, key)
            if key:sub(1, 3) == "get" then return function() return values[key:sub(4)] or 0 end end
            if key:sub(1, 3) == "set" then return function(value) values[key:sub(4)] = value end end
            if key == "addExp" then return function(value) values.Exp = (values.Exp or 0) + value end end
        end })
        local rewardEnv = setmetatable({ require = env.require, StageConfig = SC, BattleScene = Scene,
            ClientDispatcher = Dispatcher, GameState = GS, RewardPopup = deps["ui.hud.popup.RewardPopup"],
            DropSystem = { generateFirstClearEquips = function() return {} end, generateFirstClearScrolls = function() return nil end },
            LootBoxSystem = {}, takePendingFcRewards = function() return {} end, showKeptDrops = function() end }, { __index = _G })
        assert(load(source:sub(first, last - 1), "@真实StandaloneBoot首通闭包", "t", rewardEnv))()
        -- completeTriTerminal调内部callback；以Story队列及经验叶子检查实际首通执行次数。
        state.values = values
        local CP = require("ui.character.panel.CharacterPanel")
        patch(CP, "getDeployedTeam", function(row) return { assert(HC.createHero(row, 1)) } end)
        patch(CP, "getTeamSignature", function(row) return "terminal-flow-" .. row end)
        patch(require("config.ExpTable"), "getUnlockedTeamCount", function() return 3 end)
        local drivers = {}
        local oldNew = Driver.new
        patch(Driver, "new", function(row, opts) local drv = oldNew(row, opts); drivers[row] = drv; return drv end)
        if options then Scene.adoptStageProgress(SC.getTerminalPrevStageId(stageId)) end
        Scene.adoptStageProgress(options and options.sceneSource or battle.currentStageId)
        Scene.getClearedStages()[options and SC.getTerminalPrevStageId(stageId) or battle.currentStageId] = true
        if not options then
            Scene.adoptStageProgress(stageId)
        end
        Page.setOnKill(function(data) state.kills[#state.kills + 1] = data end)
        if not options or (options.entry ~= "coldNav" and options.entry ~= "implicit") then Page.open() end
        if options and options.entry ~= "coldNav" and options.entry ~= "implicit" then
            for row = 1, 3 do
                check(Page.gotoTeamStage(row, options.sources[row]), "真实选关设置终焉前来源队" .. row)
                local pending = options.pendingSources and options.pendingSources[row]
                if pending then
                    assert(SC.isResourceStage(pending)
                        and require("config.DungeonConfig").isStageUnlocked(pending, battle, dungeon), "预约资源必须真实解锁")
                    -- 真Driver清波→Page.onStageCleared→资源记账设置行军预约，不手写生产pending。
                    local drv = drivers[row]
                    drv.enemies, drv.enemyQueue, drv.introTimer = {}, {}, 0
                    drv:tick(0.1)
                    check(drv.pendingStageId == pending and drv.marchTimer > 0,
                        "真实清波形成资源预约队" .. row)
                    assert(drv.pendingStageId == pending, "资源预约与独立期望不符")
                end
            end
        end
        local function enter(mode)
            mode = mode or (options and options.entry) or "page"
            if mode == "page" then
                check(Page.gotoTeamStage(1, stageId), "通过真实Page.gotoTeamStage进入终焉")
            elseif mode == "confirm" then
                local dialog = deps["ui.battle.popup.TerminalConfirmDialog"]
                dialog.open(stageId)
                if options and options.beforeConfirm then options.beforeConfirm(Page, drivers) end
                env.time.elapsedTime = env.time.elapsedTime + 1
                check(Scene.handleInput(340, 1310), "真实Scene确认输入进入终焉")
                Page.open()
                Page.update(0)
            elseif mode == "implicit" then
                Page.open()
            else
                check(Scene.gotoStage(stageId, { deferEnter = true }), "通过真实Nav.gotoStage进入终焉 " .. mode)
                Page.open()
                Page.update(0)
            end
            assert(drivers[1] and drivers[1].terminalRaid, "真实入口必须创建共享raid")
            for _, drv in ipairs(drivers) do drv.introTimer = 0 end
            state.snapshots, state.arrivals = {}, {}
            return drivers[1].terminalRaid
        end
        if options and not options.deferTerminal then enter() end
        for _, drv in ipairs(drivers) do drv.introTimer = 0 end
        state.snapshots, state.arrivals = {}, {} -- 入终焉的真实通知已排61/68，不算目标通知。
        local raid = not options and assert(drivers[1].terminalRaid) or nil
        local function finishRaid()
            local currentRaid = options and assert(drivers[1].terminalRaid) or raid
            for index = 1, 3 do
                local enemy = currentRaid.lines[1][index]
                clearShield(enemy)
                enemy.attrs:takeDamage(currentRaid.pools[index].maxHp * 100)
            end
            Page.update(0)
        end
        -- 只读编译正式SyncBattleState和正式live发布/路由，验证末关快照不回灌运行态终焉。
        local standaloneFile = assert(cache:GetFile("boot/Standalone.lua"))
        local standaloneLines = {}
        while not standaloneFile:IsEof() do standaloneLines[#standaloneLines + 1] = standaloneFile:ReadLine() end
        standaloneFile:Dispose()
        local standaloneSource = table.concat(standaloneLines, "\n")
        local syncFirst = assert(standaloneSource:find("local battleSync =", 1, true))
        local syncLast = assert(standaloneSource:find("\nlocal physW, physH", syncFirst, true))
        local liveDispatcher = compileModule("runtime.ClientDispatcher", env)
        liveDispatcher.set("battle", battle, { normalized = true })
        local routes = { restored = 0 }
        local router = { onBattleDataUpdate = function(data) routes.restored = routes.restored + 1; Scene.setBattleData(data) end }
        local handlerFile = assert(cache:GetFile("runtime/ClientMessageHandler.lua"))
        local handlerLines = {}
        while not handlerFile:IsEof() do handlerLines[#handlerLines + 1] = handlerFile:ReadLine() end
        handlerFile:Dispose()
        local handlerSource = table.concat(handlerLines, "\n")
        local routerFirst = assert(handlerSource:find(" function M.setupDataSubscriptions()", 1, true))
        local routerLast = assert(handlerSource:find("\n --= 网络事件处理", routerFirst, true))
        local routerEnv = setmetatable({ M = router, ClientDispatcher = liveDispatcher }, { __index = _G })
        assert(load(handlerSource:sub(routerFirst, routerLast - 1), "@真实live回灌路由", "t", routerEnv))()
        router.setupDataSubscriptions()
        local syncEnv = setmetatable({ bootReady_ = true, StandaloneRT = {}, StageConfig = SC,
            BattleScene = Scene, BattleTriPage = Page, StandaloneSave = Save, ClientDispatcher = liveDispatcher }, { __index = _G })
        local sync = assert(load(standaloneSource:sub(syncFirst, syncLast - 1) .. "\nreturn SyncBattleState",
            "@真实SyncBattleState", "t", syncEnv))()
        local function syncBattle()
            sync(1.1)
            battle = liveDispatcher.get("battle")
            check(routes.restored == 0, "正式publishLive及ClientMessageHandler不走末关回灌")
            check(Scene.getStageId() == stageId and drivers[1].stageId == stageId,
                "周期SyncBattleState保留运行态队1终焉，不被末关快照拉走")
            local expectedFirst = SC.getTerminalPrevStageId(stageId)
            if options then
                local origin = options.pendingSources and options.pendingSources[1] or options.sources[1]
                if SC.isResourceStage(origin) then expectedFirst = origin end
            end
            check(battle.currentStageId == expectedFirst
                and battle.maxStageId >= SC.getReincarnationTarget(SC.getDifficulty(stageId)), "周期同步保留来源策略及目标解锁")
        end
        defer(function() Intro.reset(); Page.resetToDefault() end)
        return { scene = Scene, page = Page, story = Story, intro = Intro, save = Save, battle = battle,
            session = session, drivers = drivers, raid = raid, state = state, finishRaid = finishRaid,
            syncBattle = syncBattle, enter = enter, dungeon = dungeon }
    end
    return terminalFlowFixture
end

return M
