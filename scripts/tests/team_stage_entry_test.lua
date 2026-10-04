-- T04/T05：真实 Driver.start/tick → Page预约 → Scene/Nav/Load → Story 入场链。
-- 仅单位、渲染、声音和落盘出口替身；不读取玩家档，不改生产函数或推进预期。
-- Runtime: tests/team_stage_entry_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless -nosound
function Start()
    local nativeRequire = require
    local checks, failed, passedCases, failedCases = 0, 0, 0, 0
    local function check(value, label)
        checks = checks + 1
        if not value then failed = failed + 1 end
        print("[team_stage_entry] " .. (value and "PASS " or "FAIL ") .. label)
    end
    local function eq(actual, expected, label)
        check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
    end
    local function runCase(label, fn)
        local before = failed
        local ok, err = pcall(fn)
        if not ok then
            failed = failed + 1
            print("[team_stage_entry] FAIL harness " .. label .. " " .. tostring(err))
        end
        if failed == before then passedCases = passedCases + 1 else failedCases = failedCases + 1 end
    end
    local function source(name)
        local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "source " .. name)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        return table.concat(lines, "\n")
    end
    local SC = nativeRequire("config.StageConfig")
    local ExpTable = nativeRequire("config.ExpTable")
    local Schema = nativeRequire("shared.battle.BattleSchema")
    local ScenarioConfig = nativeRequire("config.ScenarioDialogueConfig")
    local function noop() end
    local function stub(fields)
        return setmetatable(fields or {}, { __index = function() return noop end })
    end
    local function newUnit(heroId)
        return { heroId = heroId, monsterId = heroId and nil or 1, hp = 100,
            attrs = { final = {}, getActualInterval = function() return 1 end,
                tickEnergyShield = noop, takeDamage = function(_, amount) return amount end,
                heal = function(_, amount) return amount end } }
    end
    -- 每例重新加载生产模块：隔离队列/当前关/去重状态，不靠修改生产局部变量。
    local function fixture(startIds, maxId, cleared, intro)
        local modules = {
            battle = { currentStageId = startIds[1], maxStageId = maxId,
                teamCurrentStageIds = { startIds[1], startIds[2], startIds[3] },
                clearedStages = cleared or {}, battleMode = "firstClear" },
            session = { introCompleted = intro ~= false, initialHeroId = 1, claimedScenarios = {} },
            heroes = { roster = {}, teams = {}, deployed = {} },
        }
        local loaded, mocks, drivers, snapshots, events = {}, {}, {}, {}, {}
        local signatures = { "team1", "team2", "team3" }
        local env = setmetatable({}, { __index = _G })
        local function stateModule(newName)
            local current = {}
            local result = stub({ mount = function(state) current = state or {} end,
                mountedState = function() return current end,
                reset = noop })
            result[newName] = function() return {} end
            return result
        end
        mocks["ui.battle.combat.BattleCombat"] = stateModule("newState")
        mocks["ui.battle.combat.ProjectileSystem"] = stateModule("newState")
        mocks["ui.battle.combat.BattleEffects"] = stateModule("newFxState")
        mocks["systems.ThreatManager"] = stateModule("newState")
        mocks["systems.TalentManager"] = stateModule("newBattleRefs")
        mocks["systems.StatusEffectManager"] = stateModule("newSemState")
        mocks["systems.RelicConditionHandler"] = stateModule("newState")
        mocks["systems.ArtifactRuntime"] = stub()
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
            getTeamSignature = function(team) return signatures[team] end,
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
        mocks["shared.battle.BattleSchema"] = Schema
        mocks["config.ScenarioDialogueConfig"] = ScenarioConfig
        mocks["core.BattleLayout"] = nativeRequire("core.BattleLayout")
        mocks["core.NumberUtil"] = nativeRequire("core.NumberUtil")
        mocks["shared.StageUtils"] = nativeRequire("shared.StageUtils")
        mocks["runtime.ClientDispatcher"] = stub({ get = function(key) return modules[key] end })
        mocks["core.GameState"] = stub()
        mocks["core.I18n"] = stub({ lookup = function(text) return text end })
        local terminalOpen = false
        local terminalId = 0
        mocks["ui.battle.popup.TerminalConfirmDialog"] = stub({
            isOpen = function() return terminalOpen end,
            open = function(id) terminalOpen, terminalId = true, id end,
        })
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
            ["ui.battle.scene.BattleDataRestore"] = true,
            ["ui.battle.scene.BattleMountScope"] = true,
            ["ui.battle.stage.StageEntryEvents"] = true,
            ["systems.StoryPlayer"] = true,
            ["boot.StandaloneSave"] = true,
        }
        local function isolatedRequire(name)
            if mocks[name] then return mocks[name] end
            if loaded[name] then return loaded[name] end
            if targets[name] then
                local chunk = assert(load(source(name), "@" .. name, "t", env))
                loaded[name] = chunk()
                return loaded[name]
            end
            mocks[name] = stub()
            return mocks[name]
        end
        env.require = isolatedRequire
        env.time = { elapsedTime = 100 }
        local Scene = isolatedRequire("ui.battle.scene.BattleScene")
        local Story = isolatedRequire("systems.StoryPlayer")
        local realOnStage = Story.onStage
        Story.onStage = function(id, phase)
            events[#events + 1] = { id = id, phase = phase, driverStage = drivers[1] and drivers[1].stageId }
            return realOnStage(id, phase)
        end
        local Driver = isolatedRequire("ui.battle.tri.BattleTriDriver")
        local newDriver = Driver.new
        Driver.new = function(team, options)
            local drv = newDriver(team, options)
            drivers[team] = drv
            return drv
        end
        local Save = isolatedRequire("boot.StandaloneSave")
        Save.Flush = function()
            snapshots[#snapshots + 1] = Save.CaptureBattleProgress(modules.battle)
            return true
        end
        -- Scene首通奖励出口与宿主Boot无关，不影响入场剧情或真实Scene预约逻辑。
        Scene.onFirstClear = noop
        Scene.setBattleData(modules.battle)
        local Page = isolatedRequire("ui.battle.tri.BattleTriPage")
        Save.SetBattlePage(Page)
        Page.setTeamStageIds(startIds)
        Page.open()
        local ctx = { Scene = Scene, Story = Story, Page = Page, Driver = Driver, Save = Save,
            drivers = drivers, modules = modules, snapshots = snapshots, events = events, signatures = signatures }
        function ctx.enterCount(id)
            local count = 0
            for _, event in ipairs(events) do
                if event.phase == "enter" and event.id == id then count = count + 1 end
            end
            return count
        end
        function ctx.clearEvents()
            for i = #events, 1, -1 do events[i] = nil end
            while Story.take() do end
        end
        function ctx.claimNext(expected)
            local nextStory = Story.take()
            eq(nextStory and nextStory.scenarioId, expected, "真实Story队列情景")
            if nextStory then modules.session.claimedScenarios[tostring(nextStory.scenarioId)] = true end
            eq(Story.take(), nil, "账户入场只入队一次")
        end
        function ctx.clear(team)
            local drv = drivers[team]
            drv.enemies, drv.enemyQueue = {}, {}
            drv.introTimer = 0
            drv:tick(0.1)
        end
        function ctx.isTerminalOpen() return terminalOpen, terminalId end
        return ctx
    end
    local storyStages = { { 2505, 64 }, { 2705, 65 }, { 2905, 67 }, { 4705, 71 } }
    for team = 1, 3 do
        for _, pair in ipairs(storyStages) do
            local id, scenarioId = pair[1], pair[2]
            runCase("队" .. team .. "手选" .. id, function()
                local ctx = fixture({ 2402, 2402, 2402 }, 5001)
                ctx.clearEvents()
                check(ctx.Page.gotoTeamStage(team, id), "手选合法关队" .. team)
                eq(ctx.drivers[team].stageId, id, "手选实际Driver入场")
                eq(ctx.enterCount(id), 1, "Scene+Driver统一单次enter")
                if team == 1 then
                    eq(ctx.events[#ctx.events].driverStage, id, "队一通知发生在Driver实际start之后而非备用Scene load")
                end
                ctx.claimNext(scenarioId)
                ctx.drivers[team]:start(id)
                eq(ctx.enterCount(id), 1, "重开本关不重复enter")
                ctx.signatures[team] = "changed"
                for _ = 1, 15 do ctx.drivers[team]:update(0) end
                eq(ctx.enterCount(id), 1, "编队刷新不重复enter")
                eq(ctx.Story.take(), nil, "领取账本阻止重复情景")
            end)
            runCase("队" .. team .. "自动" .. id, function()
                local previous = id - 1
                local ids = { 2402, 2402, 2402 }
                ids[team] = previous
                local ctx = fixture(ids, 5001)
                ctx.clearEvents()
                ctx.clear(team)
                eq(ctx.enterCount(id), 0, "complete/adopt预约阶段不得enter")
                eq(ctx.drivers[team].stageId, previous, "行军仍在已通关")
                check(ctx.drivers[team].marchTimer > 0, "真实tick启动行军")
                eq(ctx.Page.getTeamStageIds()[team], id, "首通即时快照预约下一关")
                eq(ctx.snapshots[#ctx.snapshots].teamCurrentStageIds[team], id, "真实Save采集预约")
                ctx.drivers[team]:tick(2)
                eq(ctx.drivers[team].stageId, id, "行军完成实际进入下一关")
                eq(ctx.enterCount(id), 1, "自动推进单次enter")
                ctx.claimNext(scenarioId)
                ctx.Page.update(0)
                eq(ctx.drivers[team].stageId, id, "Scene兼容镜像不拉回旧关")
            end)
        end
    end
    runCase("初始恢复三队+同关重开账户去重", function()
        local ctx = fixture({ 2505, 2705, 2905 }, 5001)
        eq(ctx.enterCount(2505), 1, "初始队一Scene+Driver仅通知一次")
        eq(ctx.enterCount(2705), 1, "恢复队二真实进入通知")
        eq(ctx.enterCount(2905), 1, "恢复队三真实进入通知")
        for _, id in ipairs({ 64, 65, 67 }) do
            local item = ctx.Story.take()
            check(item and item.scenarioId == id, "三队初始情景入队" .. id)
            if item then ctx.modules.session.claimedScenarios[tostring(item.scenarioId)] = true end
        end
        eq(ctx.Story.take(), nil, "初始无重复队列")
        ctx.Page.setTeamStageIds({ 2505, 2705, 2905 })
        eq(ctx.Story.take(), nil, "重复恢复不重复剧情")
        check(ctx.Page.gotoTeamStage(2, 2505), "另一队进入账户已播关")
        eq(ctx.Story.take(), nil, "账户claimed跨队去重")
    end)
    runCase("take后领取前跨队入场不重复补排", function()
        local ctx = fixture({ 2402, 2402, 2402 }, 5001)
        ctx.clearEvents()
        check(ctx.Page.gotoTeamStage(1, 2505), "第一队真实手选2505")
        local active = ctx.Story.take()
        eq(active and active.scenarioId, 64, "情景已被take进入播放")
        eq(ctx.modules.session.claimedScenarios["64"], nil, "领取尚未到达")
        check(ctx.Page.gotoTeamStage(2, 2505), "第二队同时到达2505")
        check(ctx.Page.gotoTeamStage(3, 2505), "第三队同时到达2505")
        eq(ctx.enterCount(2505), 1, "同一进程账户通知一次")
        eq(ctx.Story.take(), nil, "active窗口不重复补排")
        local fresh = fixture({ 2505, 2402, 2402 }, 5001)
        fresh.claimNext(64)
    end)
    runCase("开场暂存随真实切关覆盖，清档重置通知", function()
        local ctx = fixture({ 2402, 2505, 2402 }, 5001, {}, false)
        check(ctx.Page.gotoTeamStage(2, 2705), "开场时真实改选2705")
        ctx.modules.session.introCompleted = true
        ctx.Page.update(0)
        ctx.claimNext(65)
        eq(ctx.enterCount(2505), 0, "未实际继续驻留旧关不补旧情景")
        ctx.Scene.resetToDefault()
        ctx.Scene.setBattleData(ctx.modules.battle)
        ctx.clearEvents()
        check(ctx.Page.gotoTeamStage(2, 2705), "清档后可再次真实入场")
        eq(ctx.enterCount(2705), 1, "清档重置运行期通知")
        eq(ctx.Story.take(), nil, "若领取账本保留仍不重复播")
    end)
    runCase("intro未完成恢复不能永久吞入场", function()
        local ctx = fixture({ 2505, 2705, 2905 }, 5001, {}, false)
        eq(ctx.Story.take(), nil, "开场未结束不得播后续")
        ctx.modules.session.introCompleted = true
        ctx.Page.update(0)
        for _, id in ipairs({ 64, 65, 67 }) do
            local item = ctx.Story.take()
            check(item and item.scenarioId == id, "开场完成后真实update补入场" .. id)
            if item then ctx.modules.session.claimedScenarios[tostring(item.scenarioId)] = true end
        end
        eq(ctx.Story.take(), nil, "intro重试仍去重")
    end)
    for team = 1, 3 do
        runCase("退关真实入场队" .. team, function()
            local ids = { 2402, 2402, 2402 }
            ids[team] = 2601
            local ctx = fixture(ids, 5001)
            ctx.clearEvents()
            ctx.drivers[team]:retreatStage()
            eq(ctx.drivers[team].stageId, 2505, "退到上一章末关")
            eq(ctx.enterCount(2505), 1, "退关也通知真实enter")
            ctx.claimNext(64)
            eq(ctx.snapshots[#ctx.snapshots].teamCurrentStageIds[team], 2505, "退关快照实际关")
        end)
    end
    runCase("battleLab不播入场且不保存正常进度", function()
        local ctx = fixture({ 2402, 2402, 2402 }, 5001)
        ctx.clearEvents()
        local lab = ctx.Driver.new(2, { battleLab = true, allyFactory = function() return { newUnit(2) } end })
        lab:start(2505)
        lab:start(2705)
        lab:update(0)
        eq(ctx.enterCount(2505), 0, "实验室不通知2505")
        eq(ctx.enterCount(2705), 0, "实验室不通知2705")
        eq(ctx.Story.take(), nil, "实验室不入账户剧情队列")
        eq(ctx.modules.battle.teamCurrentStageIds[2], 2402, "实验室不写队二正常关")
    end)
    runCase("旧Scene备用load与Nav仍工作且重开去重", function()
        local ctx = fixture({ 2402, 2402, 2402 }, 5001)
        ctx.Page.close()
        ctx.clearEvents()
        check(ctx.Scene.gotoStage(2505), "备用Scene手选")
        eq(ctx.enterCount(2505), 1, "备用load通知enter")
        ctx.claimNext(64)
        ctx.Scene.reloadStage()
        eq(ctx.enterCount(2505), 1, "备用reload同关去重")
        ctx.Scene.adoptStageProgress(2704)
        ctx.Scene.nextStage()
        eq(ctx.Scene.getStageId(), 2705, "备用Nav自动前进")
        eq(ctx.enterCount(2705), 1, "备用Nav/load入场")
        ctx.claimNext(65)
    end)
    runCase("终焉协同真实胜利仅Driver实际进轮回时入场", function()
        local ctx = fixture({ 2305, 2305, 2305 }, 2305, { ["2305"] = true })
        ctx.clearEvents()
        check(ctx.Page.gotoTeamStage(2, 999), "队二选终焉接管三队协同")
        eq(ctx.enterCount(999), 1, "三队终焉入場账户单次")
        ctx.claimNext(61)
        for team = 1, 3 do
            eq(ctx.drivers[team].stageId, 999, "终焉三队正式开战" .. team)
        end
        local raid = ctx.drivers[2].terminalRaid
        check(raid and raid.maxHp > 0, "真实TerminalRaid共享池")
        raid.hp = 0
        ctx.Page.update(0)
        eq(ctx.enterCount(2401), 1, "胜利轮回入场只通知一次")
        ctx.claimNext(63)
        eq(ctx.events[#ctx.events].driverStage, 999, "Scene提前load不通知，首个实际Driver回调时一队仍待同步")
        for team = 2, 3 do eq(ctx.drivers[team].stageId, 2401, "副队真实进入轮回首关" .. team) end
        ctx.Page.update(0)
        eq(ctx.drivers[1].stageId, 2401, "下一帧一队同步实际开战")
        eq(ctx.enterCount(2401), 1, "Scene+三队入场不双通知")
    end)
    -- 已跨难度max和终焉首通账本是两种独立凭据；不使用upper推断终焉已通。
    local terminalStates = {
        { label = "未通", max = 2305, cleared = { ["2305"] = true }, destination = 2305, wait = true },
        { label = "数字键", max = 2305, cleared = { [999] = true }, destination = 2401 },
        { label = "字符串键", max = 2305, cleared = { ["999"] = true }, destination = 2401 },
        { label = "已跨难度", max = 2401, cleared = {}, destination = 2401 },
        { label = "末难度", max = 34505, cleared = {}, current = 34505, destination = 34505 },
    }
    for team = 1, 3 do
        for _, state in ipairs(terminalStates) do
            runCase("队" .. team .. "终焉" .. state.label, function()
                local current = state.current or 2305
                local ctx = fixture({ current, current, current }, state.max, state.cleared)
                ctx.clearEvents()
                ctx.clear(team)
                eq(ctx.drivers[team].stageId, current, "终焉边界行军未提前入场")
                eq(ctx.Page.getTeamStageIds()[team], state.destination, "Page终焉预约同解析")
                eq(ctx.snapshots[#ctx.snapshots].teamCurrentStageIds[team], state.destination, "Save终焉预约同解析")
                local _, _, background = ctx.drivers[team]:getMarchBackground()
                eq(background, state.destination, "终焉行军视觉同解析")
                eq(ctx.enterCount(state.destination), 0, "预约阶段零enter")
                ctx.drivers[team]:tick(2)
                eq(ctx.drivers[team].stageId, state.destination, "三队终焉边界实际目标")
                if state.wait then
                    eq(ctx.drivers[team].active, false, "未通终焉停止等待确认")
                    eq(ctx.modules.battle.clearedStages[999], nil, "不伪造终焉数字账本")
                    eq(ctx.modules.battle.clearedStages["999"], nil, "不伪造终焉字符串账本")
                    eq(ctx.enterCount(999), 0, "不自动挑战终焉")
                else
                    eq(ctx.drivers[team].active, true, "已通或末关正常开战")
                    if current ~= state.destination then
                        eq(ctx.enterCount(state.destination), 1, "跨难度真实入场一次")
                        ctx.claimNext(63)
                    else
                        eq(ctx.enterCount(current), 0, "最高难度原地重开无重复enter")
                    end
                end
                ctx.Page.update(0)
                eq(ctx.drivers[team].stageId, state.destination, "下一帧兼容镜像不拉回")
            end)
        end
    end
    runCase("14座终焉纯解析双键与未通一致", function()
        check(type(SC.resolveAutoAdvance) == "function", "提供共享纯推进解析器")
        if type(SC.resolveAutoAdvance) ~= "function" then return end
        for _, entry in ipairs(SC.STAGES) do
            if SC.isTerminalTemple(entry.id) then
                local previous = SC.getTerminalPrevStageId(entry.id)
                local target = SC.getReincarnationTarget(SC.getDifficulty(entry.id))
                local destination, waiting = SC.resolveAutoAdvance(previous, previous, { [previous] = true })
                eq(destination, previous, "14终焉未通留本关" .. entry.id)
                eq(waiting, entry.id, "14终焉未通确认目标" .. entry.id)
                for _, ledger in ipairs({ { [entry.id] = true }, { [tostring(entry.id)] = true } }) do
                    destination, waiting = SC.resolveAutoAdvance(previous, previous, ledger)
                    eq(destination, target, "14终焉双键跳过" .. entry.id)
                    eq(waiting, nil, "已通不等待" .. entry.id)
                end
                destination, waiting = SC.resolveAutoAdvance(previous, target, {})
                eq(destination, target, "14终焉已跨max" .. entry.id)
                eq(waiting, nil, "跨max不等待" .. entry.id)
            end
        end
    end)
    print(string.format("[team_stage_entry] RESULT casesPassed=%d casesFailed=%d checks=%d failures=%d (real Driver/Page/Scene; unit/render/save outlet doubles)",
        passedCases, failedCases, checks, failed))
    if failed == 0 then
        print("[team_stage_entry] ALL PASS")
    else
        log:Write(LOG_ERROR, "[team_stage_entry] FAIL " .. failed .. " checks")
    end
    engine:Exit()
end
