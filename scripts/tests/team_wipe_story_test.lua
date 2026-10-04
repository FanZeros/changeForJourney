-- 首次普通全灭剧情：真实 Driver.tick/retreatStage → Page → Boot → Story.onWipe/take。
-- 基于 team_stage_entry_test、hero_scenario_claim_test、scenario82_firstclear_test。
-- 每例隔离加载生产模块；只替身单位资源/战斗执行/养成/Flush/渲染出口。
-- 不读取玩家档，不改生产或经济；缺少新接口计业务失败，不终止后续用例。
-- Runtime tests/team_wipe_story_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
function Start()
    local nativeRequire = require
    local PREFIX = "[team_wipe_story] "
    local checks, failures, casesPassed, casesFailed, harnessErrors = 0, 0, 0, 0, 0
    local function check(value, label)
        checks = checks + 1
        if not value then failures = failures + 1 end
        print(PREFIX .. (value and "PASS " or "FAIL ") .. label)
    end
    local function eq(actual, expected, label)
        check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
    end
    local function runCase(label, fn)
        local before = failures
        local ok, err = pcall(fn)
        if not ok then
            failures, harnessErrors = failures + 1, harnessErrors + 1
            print(PREFIX .. "FAIL harness " .. label .. " " .. tostring(err))
        end
        if failures == before then casesPassed = casesPassed + 1 else casesFailed = casesFailed + 1 end
    end
    local function source(name)
        local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "source " .. name)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        return table.concat(lines, "\n")
    end
    local function noop() end
    local function stub(fields)
        return setmetatable(fields or {}, { __index = function() return noop end })
    end
    local SC = nativeRequire("config.StageConfig")
    local ExpTable = nativeRequire("config.ExpTable")
    local ScenarioConfig = nativeRequire("config.ScenarioDialogueConfig")
    local function newUnit(heroId)
        return { heroId = heroId, monsterId = heroId and nil or 1, hp = 100, maxHp = 100,
            attrs = { final = {}, getActualInterval = function() return 1 end,
                tickEnergyShield = noop, takeDamage = function(_, amount) return amount end,
                heal = function(_, amount) return amount end } }
    end
    local function fixture(opts)
        opts = opts or {}
        -- 两次普通失败2404→2403→2402均无入场剧情，避免把轮回入场63误当全灭。
        local ids = opts.ids or { 2404, 2404, 2404 }
        local modules = {
            battle = { currentStageId = ids[1], maxStageId = 5001,
                teamCurrentStageIds = { ids[1], ids[2], ids[3] },
                clearedStages = { ["2305"] = true }, battleMode = "firstClear" },
            session = { introCompleted = opts.intro ~= false, initialHeroId = opts.hero or 1,
                claimedScenarios = opts.claimed or {} },
            heroes = { roster = {}, teams = {}, deployed = {} },
            equipment = { inventory = {}, equipped = {} }, lootbox = { seeds = {} },
            player = { name = "test" },
        }
        local loaded, mocks, drivers, wipeCalls, flushes = {}, {}, {}, {}, {}
        local revive = { artifact = false, talent = false }
        local env = setmetatable({}, { __index = _G })
        local function stateModule(newName)
            local current = {}
            local result = stub({ mount = function(state) current = state or {} end,
                mountedState = function() return current end, reset = noop })
            result[newName] = function() return {} end
            return result
        end
        mocks["ui.battle.combat.BattleCombat"] = stateModule("newState")
        mocks["ui.battle.combat.BattleCombat"].getCardPos = function() return 0, 0 end
        mocks["ui.battle.combat.ProjectileSystem"] = stateModule("newState")
        mocks["ui.battle.combat.BattleEffects"] = stateModule("newFxState")
        mocks["systems.ThreatManager"] = stateModule("newState")
        mocks["systems.TalentManager"] = stateModule("newBattleRefs")
        mocks["systems.TalentManager"].onAllyDeath = function(u)
            if revive.talent then u.hp = 100; return true end
            return false
        end
        mocks["systems.StatusEffectManager"] = stateModule("newSemState")
        mocks["systems.RelicConditionHandler"] = stateModule("newState")
        mocks["systems.ArtifactRuntime"] = stub({ onAllyDeath = function(u)
            if revive.artifact then u.hp = 100; return true end
            return false
        end })
        mocks["systems.AttributeDef"] = nativeRequire("systems.AttributeDef")
        mocks["systems.BattleStats"] = stub({ mountedTeam = function() return nil end })
        mocks["ui.battle.scene.BattleAllyReset"] = stub()
        mocks["ui.battle.stage.BattleStageFlow"] = stub({ ensureBattleCards = function() return {} end })
        mocks["ui.battle.stage.BattleStageNav"] = stub({ NAV = {} })
        mocks["ui.battle.stage.StageBerserk"] = stub({ isActive = function() return false end })
        mocks["systems.MapAffixSystem"] = stub({ hasAffixes = function() return false end })
        mocks["systems.BossAffixSystem"] = stub({ hasAffixes = function() return false end })
        mocks["ui.battle.stage.BattleEnemySpawn"] = stub({
            generateEnemyList = function() return { newUnit() } end,
            generateIdleEnemyList = function() return { newUnit() }, 1 end,
            assignEnemiesToField = function(units) return units, {} end,
        })
        mocks["config.MonsterConfig"] = { createMonster = function() return newUnit() end }
        mocks["ui.character.panel.CharacterPanel"] = stub({
            getTeamSignature = function(team) return "team" .. team end,
            getDeployedTeam = function(team) return { newUnit(team) } end,
        })
        mocks["systems.OfflineCalc"] = {
            resolveIdleStageAnchors = function() return 101, 101 end,
            calcOnlineIdleRewards = function() return {} end,
        }
        mocks["config.StageConfig"] = SC
        mocks["shared.StageProvider"] = { Get = function() return SC end }
        mocks["config.ExpTable"] = ExpTable
        mocks["config.GameConfig"] = nativeRequire("config.GameConfig")
        mocks["shared.battle.BattleSchema"] = nativeRequire("shared.battle.BattleSchema")
        mocks["config.ScenarioDialogueConfig"] = ScenarioConfig
        mocks["core.BattleLayout"] = nativeRequire("core.BattleLayout")
        mocks["core.NumberUtil"] = nativeRequire("core.NumberUtil")
        mocks["shared.StageUtils"] = nativeRequire("shared.StageUtils")
        mocks["runtime.ClientDispatcher"] = stub({ get = function(key) return modules[key] end })
        mocks["runtime.LocalActionBridge"] = stub()
        mocks["core.PlayerStore"] = stub({ Get = function(key) return modules[key] end })
        mocks["core.GameState"] = stub()
        mocks["core.I18n"] = stub({ lookup = function(text) return text end })
        mocks["boot.StandaloneSave"] = stub({ Flush = function()
            flushes[#flushes + 1] = { modules.battle.teamCurrentStageIds[1],
                modules.battle.teamCurrentStageIds[2], modules.battle.teamCurrentStageIds[3] }
            return true
        end })
        mocks["ui.battle.popup.TerminalConfirmDialog"] = stub({ isOpen = function() return false end })
        for _, name in ipairs({ "ui.story.gate.LetterIntro", "ui.story.gate.IntroCutscene",
            "ui.story.ScenarioDialogue", "ui.battle.stage.SweepDialog", "ui.battle.popup.DamageStatsPanel",
            "ui.battle.stage.StageSelectDialog" }) do
            mocks[name] = stub({ isOpen = function() return false end, isActive = function() return false end })
        end
        mocks["ui.character.equip.EquipmentBag"] = stub({ shouldBattleOverlay = function() return false end })
        mocks["systems.BattleTimeout"] = { calcMult = function() return 1 end }
        local targets = {
            ["ui.battle.scene.BattleScene"] = true,
            ["ui.battle.tri.BattleTriDriver"] = true,
            ["ui.battle.tri.BattleTriPage"] = true,
            ["ui.battle.tri.TerminalRaid"] = true,
            ["ui.battle.stage.BattleStageNavLogic"] = true,
            ["ui.battle.stage.BattleStageLoad"] = true,
            ["ui.battle.stage.BattleSpeed"] = true, -- 真实dt纯逻辑；draw出口依旧替身
            ["ui.battle.scene.BattleDataRestore"] = true,
            ["ui.battle.scene.BattleMountScope"] = true,
            ["ui.battle.stage.StageEntryEvents"] = true,
            ["systems.StoryPlayer"] = true,
            ["boot.StandaloneBoot"] = true,
        }
        local function isolatedRequire(name)
            if mocks[name] then return mocks[name] end
            if loaded[name] then return loaded[name] end
            if targets[name] then
                loaded[name] = assert(load(source(name), "@" .. name, "t", env))()
                return loaded[name]
            end
            -- 仅未列入 targets 的资源/UI/养成出口替身；通知目标均真实加载。
            mocks[name] = stub()
            return mocks[name]
        end
        env.require = isolatedRequire
        env.time = { elapsedTime = 100 }
        local Scene = isolatedRequire("ui.battle.scene.BattleScene")
        local Story = isolatedRequire("systems.StoryPlayer")
        local realWipe = Story.onWipe
        Story.onWipe = function(...)
            wipeCalls[#wipeCalls + 1] = table.pack(...)
            return realWipe(...)
        end
        local Driver = isolatedRequire("ui.battle.tri.BattleTriDriver")
        local realNew = Driver.new
        Driver.new = function(team, options)
            local drv = realNew(team, options)
            drivers[team] = drv
            return drv
        end
        Scene.setBattleData(modules.battle)
        local Page = isolatedRequire("ui.battle.tri.BattleTriPage")
        -- 运行完整真实 Boot.run，UI/养成注册与落盘出口为 inert doubles。
        -- 不伪造 setOnAllDead，更不在 fixture 中手工接 Driver → Story。
        isolatedRequire("boot.StandaloneBoot").run({ localSendAction = noop, setLocalBridgeReady = noop })
        Page.setTeamStageIds(ids)
        Page.open()
        -- 入场剧情属于另一专项；只清当前入场队列，不干预 wipe 运行期锁。
        while Story.take() do end
        local ctx = { Scene = Scene, Story = Story, Page = Page, Driver = Driver,
            drivers = drivers, modules = modules, wipeCalls = wipeCalls, flushes = flushes, revive = revive }
        function ctx.kill(team)
            local drv = drivers[team]
            for _, u in ipairs(drv.allies) do u.hp = 0 end
            drv.introTimer = 0
        end
        function ctx.wipe(team)
            ctx.kill(team)
            drivers[team]:activate()
            drivers[team]:tick(0.1)
        end
        function ctx.take(expected, label)
            local item = Story.take()
            eq(item and item.scenarioId, expected, label)
            if item then
                eq(item.config, ScenarioConfig["SCENARIO_" .. tostring(expected)], label .. "真实配置对象")
                check(item.config.steps and #item.config.steps > 0, label .. "真实剧情有台词")
            end
            return item
        end
        function ctx.startRaid()
            check(Page.gotoTeamStage(2, 999), "真实Page接管终焉三队")
            while Story.take() do end
            local raid = drivers[2].terminalRaid
            check(raid and raid.maxHp > 0, "真实共享生命池有效")
            return raid
        end
        return ctx
    end

    -- 第一批必须先复现普通业务断链，不被尚未新增的 Page API 抢断全部测试。
    for team = 1, 3 do
        for hero = 1, 3 do
            runCase("普通全灭队" .. team .. "初始hero" .. hero, function()
                local ctx = fixture({ hero = hero })
                local old = ctx.drivers[team].stageId
                ctx.wipe(team)
                eq(ctx.drivers[team].stageId, SC.getPrevStageId(old), "真实全灭退上一关队" .. team)
                eq(#ctx.wipeCalls, 1, "Boot真实通知到Story队" .. team)
                ctx.take(37 + hero, "首次全灭对应初始hero" .. hero)
                eq(ctx.Story.take(), nil, "首次普通全灭只排一个场景")
                eq(ctx.modules.session.claimedScenarios[tostring(37 + hero)], nil, "播放前不预写领奖账本")
            end)
        end
    end
    for team = 1, 3 do
        runCase("真实Driver直接callback队" .. team, function()
            local ctx = fixture({ ids = { 2601, 2601, 2601 } })
            local drv = ctx.drivers[team]
            local events = {}
            -- 这里仅观测 Driver 的公开出口，独立于 Page/Boot 缺失接线。
            drv.onAllDead = function(idx, stageId)
                events[#events + 1] = { team = idx, stage = stageId, liveStage = drv.stageId }
            end
            ctx.wipe(team)
            eq(#events, 1, "真正失败tick调用公开callback一次")
            local e = events[1] or {}
            eq(e.team, team, "callback携带真实队伍")
            eq(e.stage, 2601, "通知原失败关而不是退关后2505")
            eq(e.liveStage, 2601, "callback发生在retreatStage之前")
            eq(drv.stageId, 2505, "保留真实retreatStage与start")
            check(#ctx.flushes > 0, "真实退关仍调用Flush出口")
        end)
    end
    runCase("Page公开转发接口不崩溃检查", function()
        local ctx = fixture()
        local setter = ctx.Page.setOnAllDead
        check(type(setter) == "function", "Page提供setOnAllDead")
        local events = {}
        if type(setter) == "function" then
            setter(function(team, stage) events[#events + 1] = { team, stage } end)
        end
        for team = 1, 3 do ctx.wipe(team) end
        eq(#events, 3, "真实Page转发三队Driver出口")
        for team = 1, 3 do
            local e = events[team] or {}
            eq(e[1], team, "Page保留teamIdx队" .. team)
            eq(e[2], 2404, "Page保留原stageId队" .. team)
        end
    end)
    runCase("Story取出后领取前同进程不重复", function()
        local ctx = fixture()
        ctx.Story.onWipe()
        ctx.take(38, "真实onWipe首排")
        eq(ctx.modules.session.claimedScenarios["38"], nil, "take后尚未领取")
        ctx.Story.onWipe()
        ctx.Story.onWipe()
        eq(ctx.Story.take(), nil, "active窗口不可重复补排")
        ctx.Page.close()
        ctx.Page.open()
        ctx.Story.onWipe()
        eq(ctx.Story.take(), nil, "关闭重开不清账户全灭锁")
    end)
    runCase("三队同帧全灭账户只播一个", function()
        local ctx = fixture({ hero = 2 })
        for team = 1, 3 do ctx.kill(team) end
        ctx.Page.update(0.1)
        eq(#ctx.wipeCalls, 3, "三队普通失败均通过真实Boot通知")
        ctx.take(39, "账户初始hero而非失败队伍决定分支")
        eq(ctx.Story.take(), nil, "三队同时只排一段")
        for team = 1, 3 do ctx.wipe(team) end
        eq(ctx.Story.take(), nil, "take后其他关的全灭也不重复")
    end)
    -- 全灭组跨分支去重：旧档任何38/39/40真值都代表首次全灭已消费。
    for hero = 1, 3 do
        for claimedId = 38, 40 do
            for _, keyKind in ipairs({ "number", "string" }) do
                runCase("claimed组hero" .. hero .. "/" .. claimedId .. "/" .. keyKind, function()
                    local key = keyKind == "number" and claimedId or tostring(claimedId)
                    local ctx = fixture({ hero = hero, claimed = { [key] = true } })
                    ctx.Story.onWipe()
                    eq(ctx.Story.take(), nil, "claimed双键任一分支阻止重播")
                    ctx.wipe(2)
                    eq(ctx.Story.take(), nil, "真实队二全灭同样遵守组账本")
                end)
            end
        end
    end
    runCase("intro未完成保留pending直到take重试", function()
        local ctx = fixture({ intro = false, hero = 3 })
        ctx.Story.onWipe()
        ctx.Story.onWipe()
        eq(ctx.Story.take(), nil, "开场未完成不播放")
        eq(ctx.modules.session.claimedScenarios["40"], nil, "未成功入队不消耗领取账本")
        ctx.modules.session.introCompleted = true
        ctx.take(40, "开场完成take补回原全灭通知")
        eq(ctx.Story.take(), nil, "多个开场pending只排一次")
        ctx.Story.onWipe()
        eq(ctx.Story.take(), nil, "补排take后仍锁同进程")
    end)
    runCase("真实失败intro延迟不能吞通知", function()
        local ctx = fixture({ intro = false })
        ctx.wipe(2)
        eq(ctx.Story.take(), nil, "失败发生时intro不排后续")
        ctx.modules.session.introCompleted = true
        ctx.take(38, "真实失败在intro完成后可取出")
        eq(ctx.Story.take(), nil, "真实失败延迟仅一次")
    end)
    runCase("清档Scene重置允许首次全灭再通知", function()
        local ctx = fixture()
        ctx.Story.onWipe()
        ctx.take(38, "清档前首次")
        ctx.Story.onWipe()
        eq(ctx.Story.take(), nil, "清档前已保留运行期锁")
        ctx.Scene.resetToDefault()
        ctx.modules.session.claimedScenarios = {}
        ctx.Story.onWipe()
        ctx.take(38, "真实Scene清档重置wipe锁")
        ctx.modules.session.claimedScenarios[38] = true
        ctx.Scene.resetToDefault()
        ctx.Story.onWipe()
        eq(ctx.Story.take(), nil, "重置内存不覆盖保留的claimed账本")
    end)
    for team = 1, 3 do
        runCase("空队不算全灭队" .. team, function()
            local ctx = fixture()
            local drv = ctx.drivers[team]
            drv.allies, drv.introTimer = {}, 0
            drv:tick(0.1)
            eq(drv.stageId, 2404, "空队不退关")
            eq(#ctx.wipeCalls, 0, "空队不通知")
            eq(ctx.Story.take(), nil, "空队不入剧情")
        end)
        for _, kind in ipairs({ "artifact", "talent" }) do
            runCase("瞬时复活" .. kind .. "队" .. team, function()
                local ctx = fixture()
                ctx.revive[kind] = true
                ctx.wipe(team)
                check(ctx.drivers[team].allies[1].hp > 0, "真实Driver先尝试瞬时拦截")
                eq(ctx.drivers[team].stageId, 2404, "成功复活不退关")
                eq(#ctx.wipeCalls, 0, "成功复活不通知全灭")
                eq(ctx.Story.take(), nil, "成功复活不消费首灭剧情")
            end)
        end
        runCase("战斗实验室不误触发队" .. team, function()
            local ctx = fixture()
            local lab = ctx.Driver.new(team, { battleLab = true, allyFactory = function() return { newUnit(team) } end })
            local callbacks = 0
            lab.onAllDead = function() callbacks = callbacks + 1 end
            lab:start(2404)
            lab.allies[1].hp, lab.introTimer = 0, 0
            lab:tick(0.1)
            check(lab._labDefeated and not lab.active, "真实lab失败出口")
            eq(callbacks, 0, "实验室不走普通全灭callback")
            eq(#ctx.wipeCalls, 0, "实验室不通知账户剧情")
            eq(ctx.Story.take(), nil, "实验室不排首次全灭")
        end)
        runCase("终焉单队失守不误触发队" .. team, function()
            local ctx = fixture()
            local raid = ctx.startRaid()
            ctx.wipe(team)
            check(raid.defeated[team], "真实TerminalRaid单队失守")
            check(not raid.finished, "其余队存活共享战继续")
            eq(ctx.drivers[team].stageId, 999, "失守队留终焉")
            eq(#ctx.wipeCalls, 0, "终焉单队不通知首次普通全灭")
            eq(ctx.Story.take(), nil, "终焉单队失守不排剧情")
        end)
    end
    runCase("终焉共享失败退关也不误触发", function()
        local ctx = fixture()
        local raid = ctx.startRaid()
        for team = 1, 3 do ctx.wipe(team) end
        check(raid.finished and raid.won == false, "真实共享池全队失守失败")
        ctx.Page.update(0)
        for team = 1, 3 do eq(ctx.drivers[team].stageId, 2305, "共享失败退关队" .. team) end
        eq(#ctx.wipeCalls, 0, "共享失败不转普通首次全灭")
        eq(ctx.Story.take(), nil, "共享失败不排普通剧情")
    end)
    runCase("终焉超时共享失败也不误触发", function()
        local ctx = fixture()
        local raid = ctx.startRaid()
        raid.elapsed = nativeRequire("config.GameConfig").Battle.TIME_LIMIT_SEC
        ctx.Page.update(0)
        check(raid.finished and raid.won == false, "真实Page判定超时失败")
        eq(#ctx.wipeCalls, 0, "终焉超时不通知普通首次全灭")
        eq(ctx.Story.take(), nil, "终焉超时不排剧情")
    end)
    print(string.format(PREFIX .. "RESULT casesPassed=%d casesFailed=%d checks=%d failures=%d harnessErrors=%d",
        casesPassed, casesFailed, checks, failures, harnessErrors))
    print(PREFIX .. "BOUNDARY real Driver.tick/retreatStage, Page callbacks, Boot.run, Scene reset, Story.onWipe/take, ScenarioConfig; unit/combat/growth/Flush/render doubles; no reward claims or player saves")
    if failures == 0 then print(PREFIX .. "ALL PASS")
    else log:Write(LOG_ERROR, PREFIX .. "FAIL " .. failures .. " checks; harnessErrors=" .. harnessErrors) end
    engine:Exit()
end
