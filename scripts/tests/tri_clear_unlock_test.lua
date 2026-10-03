-- 三队共享首通链回归：真实 Page/Scene/Boot/Driver/StoryPlayer/SyncBattleState。
-- 页面和奖励出口使用内存替身，不读取或覆盖玩家存档，不运行随机战斗。
local assertions = 0
local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
    print("[tri_clear_unlock] PASS " .. label)
end

function Start()
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
            mocks[name] = stub()
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
        local env = setmetatable({ BattleScene = Scene, ClientDispatcher = Dispatcher, cjson = cjson }, { __index = _G })
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
    for i = #restores, 1, -1 do restores[i]() end
    rawset(_G, "require", nativeRequire)
    rawset(_G, "time", nativeTime)
    if not ok then log:Write(LOG_ERROR, "[tri_clear_unlock_test] " .. tostring(err))
    else print("[tri_clear_unlock_test] ALL PASS: " .. assertions .. " assertions") end
    engine:Exit()
end
