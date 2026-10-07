-- 三队换关、终焉跳过、入关剧情和存档恢复回归；仅使用内存存档。
local assertions = 0
local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
    print("[tri_progress] PASS " .. label)
end

function Start()
    local nativeRequire = require
    local nativeFile, nativeSystem, nativeTime = File, fileSystem, time
    local ok, err = xpcall(function()
        local SC = nativeRequire("config.StageConfig")
        local ExpTable = nativeRequire("config.ExpTable")
        local Schema = nativeRequire("shared.battle.BattleSchema")
        local ScenarioConfig = nativeRequire("config.ScenarioDialogueConfig")
        local mainStage, maxStage, cleared = 1001, 4905, {}
        local modules = {
            battle = { currentStageId = mainStage, maxStageId = maxStage,
                clearedStages = { ["905"] = true, ["1905"] = true },
                teamStageIds = { ["1"] = 1001, ["2"] = 203, ["3"] = 2504 }, idleAccumSec = 17 },
            session = { introCompleted = true, initialHeroId = 1, claimedScenarios = {} },
            player = {}, heroes = { roster = {} },
        }
        local notices, flushes, firstCalls = 0, 0, 0
        local disk = {}
        local mocks = {}
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
        local dispatcher = {
            get = function(name) return modules[name] end,
            snapshotAll = function() return modules end,
            notifySubscribers = function() notices = notices + 1 end,
            handleStateUpdate = function(json)
                for name, data in pairs(cjson.decode(json).modules) do
                    if name == "battle" then Schema.Fields.battle.onLoad(data) end
                    modules[name] = data
                end
            end,
        }
        local scene = stub({
            getStageId = function() return mainStage end,
            getMaxStageId = function() return maxStage end,
            getClearedStages = function() return cleared end,
            adoptStageProgress = function(id) mainStage = id end,
            gotoStage = function(id) mainStage = id return true end,
            completeTriStageClear = function() firstCalls = firstCalls + 1 return false end,
            setBattleData = function(data)
                mainStage, maxStage = data.currentStageId, data.maxStageId
                cleared = data.clearedStages
            end,
        })
        mocks["runtime.ClientDispatcher"] = dispatcher
        mocks["ui.battle.scene.BattleScene"] = scene
        mocks["config.StageConfig"] = SC
        mocks["shared.battle.BattleSchema"] = Schema
        mocks["core.BattleLayout"] = nativeRequire("core.BattleLayout")
        mocks["systems.AttributeDef"] = nativeRequire("systems.AttributeDef")
        mocks["config.MonsterConfig"] = nativeRequire("config.MonsterConfig")
        mocks["config.ExpTable"] = ExpTable
        mocks["config.ScenarioDialogueConfig"] = ScenarioConfig
        mocks["core.GameState"] = { exportSave = function() return {} end,
            importSave = noop, syncPlayerData = noop }
        mocks["rules.offline.OfflineService"] = stub({ HasPendingRewards = function() return false end })
        mocks["ui.character.panel.CharacterPanel"] = {
            getTeamSignature = function(t) return "team" .. t end,
            getDeployedTeam = function(t) return { { hp = 100, maxHp = 100, heroId = t } } end,
        }
        mocks["ui.battle.combat.BattleCombat"] = stub({ newState = function() return {} end })
        for _, name in ipairs({ "ui.battle.combat.ProjectileSystem", "systems.ThreatManager",
            "systems.TalentManager", "ui.battle.combat.BattleEffects", "systems.StatusEffectManager" }) do
            mocks[name] = stub({ newState = function() return {} end,
                newBattleRefs = function() return {} end, newFxState = function() return {} end,
                newSemState = function() return {} end })
        end
        -- 出怪与首通附加怪阶段使用真实模块，不能遗漏 Driver 新的生产 helper。
        mocks["ui.battle.stage.BattleEnemySpawn"] = compile("ui.battle.stage.BattleEnemySpawn")
        rawset(_G, "require", function(name)
            if mocks[name] then return mocks[name] end
            mocks[name] = stub()
            return mocks[name]
        end)
        rawset(_G, "time", { elapsedTime = 100 })
        rawset(_G, "File", function(path, mode)
            return { IsOpen = function() return true end,
                WriteString = function(_, data) disk[path] = data return true end,
                ReadString = function() return disk[path] end, Close = noop }
        end)
        rawset(_G, "fileSystem", {
            FileExists = function(_, path) return disk[path] ~= nil end,
            Delete = function(_, path) disk[path] = nil end,
            Rename = function(_, from, to) disk[to] = disk[from] disk[from] = nil return true end,
        })
        local Save = compile("boot.StandaloneSave")
        mocks["boot.StandaloneSave"] = { Flush = function()
            flushes = flushes + 1
            return Save.Flush()
        end }
        local Story = compile("systems.StoryPlayer")
        mocks["systems.StoryPlayer"] = Story
        local Entries = compile("ui.battle.stage.StageEntryEvents")
        mocks["ui.battle.stage.StageEntryEvents"] = Entries
        local Driver = compile("ui.battle.tri.BattleTriDriver")
        local drivers = {}
        mocks["ui.battle.tri.BattleTriDriver"] = { new = function(t)
            local drv = Driver.new(t)
            drivers[t] = drv
            return drv
        end }
        mocks["ui.battle.tri.TerminalReincarnation"] = compile("ui.battle.tri.TerminalReincarnation")
        mocks["ui.battle.tri.BattleEntryPreparation"] = compile("ui.battle.tri.BattleEntryPreparation")
        mocks["ui.battle.stage.BattleSpeed"] = compile("ui.battle.stage.BattleSpeed")
        scene.battleSpeed = 1
        local Page = compile("ui.battle.tri.BattleTriPage")
        mocks["ui.battle.tri.BattleTriPage"] = Page
        Page.open()
        check(Page.getTeamStageId(1) == 1001 and Page.getTeamStageId(2) == 203
            and Page.getTeamStageId(3) == 2504, "三队按独立存档关卡启动")
        check(modules.battle.currentStageId == 1001 and modules.battle.idleAccumSec == 17,
            "二三队初始化不覆盖一队关卡和挂机字段")
        for series = 1, 14 do
            local terminalId = series * 1000 - 1
            local previous = SC.getTerminalPrevStageId(terminalId)
            maxStage = terminalId
            for t = 1, 3 do
                check(Page.gotoTeamStage(t, previous),
                    "最高终焉" .. terminalId .. "队" .. t .. "可选已解锁末关" .. previous)
                local before = drivers[t].stageId
                local target = SC.getReincarnationTarget(SC.getDifficulty(terminalId))
                check(not Page.gotoTeamStage(t, target) and drivers[t].stageId == before,
                    "最高终焉" .. terminalId .. "队" .. t .. "不能提前选下一难度")
            end
        end
        maxStage = 4905
        Page.gotoTeamStage(1, 1001)
        Page.gotoTeamStage(2, 203)
        Page.gotoTeamStage(3, 2504)
        while Story.take() do end
        Entries.reset()
        check(Page.gotoTeamStage(2, 204), "二队可手动进入已解锁关卡")
        local story = Story.take()
        check(story and story.scenarioId == 41 and Story.take() == nil, "二队手动换关触发真实入关剧情41一次")
        local beforeFlush = flushes
        drivers[2]:start(204)
        check(Story.take() == nil and flushes == beforeFlush, "同关重开不重复入关事件或写盘")
        check(Page.gotoTeamStage(3, 2505), "三队可手动换关")
        story = Story.take()
        check(story and story.scenarioId == 64, "三队手动进入2505触发剧情64")
        check(modules.battle.teamStageIds["2"] == 204 and modules.battle.teamStageIds["3"] == 2505,
            "手动换关立即记录两个队伍关卡")
        check(not Page.gotoTeamStage(2, 203.5) and not Page.gotoTeamStage(2.5, 204)
            and not Page.gotoTeamStage(3, 5001), "无效或未解锁目标不改变队伍存档")

        local function clearAndAdvance(t, id)
            -- 各个推进场景使用独立入场通知台账；同场景内仍验证只播放一次。
            Entries.reset()
            local drv = drivers[t]
            drv:start(id)
            while Story.take() do end
            drv.enemies, drv.enemyQueue, drv.introTimer = {}, {}, 0
            drv:tick(0.1)
            check(drv.stageId == id and drv.marchTimer > 0, "队" .. t .. "通关先保留两秒行军")
            drv:tick(2)
            return drv
        end
        for t = 1, 3 do
            local drv = clearAndAdvance(t, 203)
            check(drv.stageId == 204 and modules.battle.teamStageIds[tostring(t)] == 204,
                "队" .. t .. "真实tick自动推进并保存204")
            story = Story.take()
            check(story and story.scenarioId == 41 and Story.take() == nil,
                "队" .. t .. "自动推进触发剧情41")
        end
        modules.session.claimedScenarios["41"] = true
        clearAndAdvance(2, 203)
        check(Story.take() == nil, "已领取的入关剧情不重复播放")
        modules.session.claimedScenarios["41"] = nil
        modules.session.introCompleted = false
        drivers[3]:start(2505)
        check(Story.take() == nil, "开场未完成不提前入队后续剧情")
        modules.session.introCompleted = true
        Entries.reset()
        drivers[2]:start(205)
        drivers[2]:retreatStage()
        check(drivers[2].stageId == 204 and modules.battle.teamStageIds["2"] == 204,
            "二队失败退关也保存实际当前关")
        story = Story.take()
        check(story and story.scenarioId == 41, "失败退回剧情关同样走入关通知")

        local function setAccountProgress(id, ledger)
            -- 驱动读取 live 和保存态两份凭据，场景夹具必须同时更新，不能遗留4905。
            maxStage, cleared = id, ledger
            modules.battle.maxStageId, modules.battle.clearedStages = id, ledger
        end
        local terminalCount = 0
        for series = 1, 14 do
            local id = series * 1000 - 1
            if SC.isTerminalTemple(id) then
                terminalCount = terminalCount + 1
                local previous = SC.getTerminalPrevStageId(id)
                local target = SC.getReincarnationTarget(SC.getDifficulty(id))
                for t = 2, 3 do
                    for _, key in ipairs({ id, tostring(id) }) do
                        setAccountProgress(previous, { [key] = true })
                        local drv = drivers[t]
                        drv:start(previous)
                        while Story.take() do end
                        drv.marchTimer = 1
                        local _, _, bgTarget = drv:getMarchBackground()
                        check(bgTarget == target, "队" .. t .. "终焉" .. id .. "已通时背景目标是下一难度")
                        drv:advanceStage()
                        check(drv.active and drv.stageId == target,
                            "队" .. t .. "终焉" .. id .. "数字或字符串已通键都正常推进")
                    end
                    setAccountProgress(target, {})
                    drivers[t]:start(previous)
                    drivers[t]:advanceStage()
                    check(drivers[t].stageId == target and drivers[t].active,
                        "队" .. t .. "终焉" .. id .. "旧档共享最高关跨难度也可推进")
                    setAccountProgress(previous, { [previous] = true })
                    drivers[t]:start(previous)
                    drivers[t]:advanceStage()
                    -- 终焉未确认不能停摆：停在末关并继续在原关刷怪，不伪造轮回。
                    check(drivers[t].stageId == previous and drivers[t].active,
                        "队" .. t .. "终焉" .. id .. "未通仍停末关继续刷本关不伪造轮回")
                    check(#drivers[t].enemies + #drivers[t].enemyQueue > 0,
                        "队" .. t .. "终焉" .. id .. "未通仍重新出怪")
                end
            end
        end
        check(terminalCount == 14, "覆盖全部十四座终焉")
        maxStage, cleared = 34505, {}
        drivers[3]:start(34505)
        drivers[3]:advanceStage()
        check(drivers[3].stageId == 34505 and drivers[3].active, "最高难度末关原地重开，不访问不存在终焉")

        local cases = {
            { currentStageId = 1001, maxStageId = 4905, clearedStages = {},
                teamStageIds = { [1] = 3001, [2] = "204", [3] = 2505 } },
            { currentStageId = 1001, maxStageId = 3999, clearedStages = {},
                teamStageIds = { ["2"] = "999", ["3"] = 3999 } },
            { currentStageId = 1001, maxStageId = 4905, clearedStages = {},
                teamStageIds = { ["2"] = 203.5, ["3"] = "bad" } },
            { currentStageId = 1001, maxStageId = 4905, clearedStages = {} },
            { currentStageId = 1001, maxStageId = 4905, clearedStages = {},
                teamStageIds = { ["2"] = "999", ["3"] = 3999 } },
        }
        for i, data in ipairs(cases) do
            -- onLoad 同时用于运行态推送；真正读档需显式开启回退迁移。
            Schema.Fields.battle.onLoad(data)
            Schema.normalizeTeamStageIds(data, true)
            check(data.teamStageIds["1"] == 1001, "迁移" .. i .. "以一队当前关为准而非最高关")
        end
        check(cases[1].teamStageIds["2"] == 204 and cases[1].teamStageIds["3"] == 2505,
            "Schema接受数字队键和字符串关卡")
        check(cases[2].teamStageIds["2"] == 2305 and cases[2].teamStageIds["3"] == 9205,
            "终焉重登三队统一退对应末关 actual=" .. tostring(cases[2].teamStageIds["2"])
                .. "/" .. tostring(cases[2].teamStageIds["3"]))
        check(cases[3].teamStageIds["2"] == 101 and cases[3].teamStageIds["3"] == 101,
            "无效关卡安全回1-1")
        check(cases[4].teamStageIds["2"] == 101 and cases[4].teamStageIds["3"] == 101,
            "旧档缺字段只迁移默认当前关，不虚构二三队历史")
        check(cases[5].teamStageIds["2"] == 2305 and cases[5].teamStageIds["3"] == 101,
            "终焉回退点超账号上界时回101，不恢复未解锁末关")

        maxStage, cleared = 4905, {}
        Page.gotoTeamStage(1, 1001)
        Page.gotoTeamStage(2, 204)
        Page.gotoTeamStage(3, 2505)
        check(Save.Flush(), "调用真实StandaloneSave完成内存原子写档")
        local saved = cjson.decode(disk["standalone_save.json"])
        check(saved.modules.battle.teamStageIds["2"] == 204
            and saved.modules.battle.teamStageIds["3"] == 2505, "真实存档JSON保留两个队伍当前关")
        Page.close()
        modules = {}
        check(Save.RestoreData(), "真实RestoreData读取刚保存的JSON")
        Save.ApplyBattleProgress()
        drivers = {}
        mocks["ui.battle.tri.TerminalRaid"] = compile("ui.battle.tri.TerminalRaid")
        mocks["config.GameConfig"] = nativeRequire("config.GameConfig")
        Page = compile("ui.battle.tri.BattleTriPage")
        Page.open()
        check(Page.getTeamStageId(1) == 1001 and Page.getTeamStageId(2) == 204
            and Page.getTeamStageId(3) == 2505, "重新创建页面和驱动后仍恢复各队当前关")
        check(modules.battle.idleAccumSec == 17 and notices > 0, "恢复保留其他字段并使用正式通知出口")
        -- 终焉协同仍由页面接管；胜负收尾后的三队位置全部写入同一存档。
        local terminalTarget
        scene.completeTriTerminal = function(id)
            terminalTarget = SC.getReincarnationTarget(SC.getDifficulty(id))
            modules.battle.maxStageId = math.max(modules.battle.maxStageId, terminalTarget)
            cleared[id] = true
            modules.battle.clearedStages[tostring(id)] = true
            Save.Flush()
            return true
        end
        scene.updateTriReincarnation = function() return true end
        maxStage, cleared = 999, { [2305] = 1 }
        modules.battle.teamStageIds["1"] = 2305
        check(not Page.gotoTeamStage(1, 999), "终焉最高节点不接受非true的末关通关标记")
        cleared = { ["2305"] = true }
        check(Page.gotoTeamStage(1, 999), "最高节点999及字符串末关账本仍可通过真实Page进入协同战")
        local enteredSave = cjson.decode(disk["standalone_save.json"])
        check(mainStage == 999 and modules.battle.currentStageId == 2305
            and enteredSave.modules.battle.currentStageId == 2305,
            "终焉运行态保持999而落盘一队立即保存末关回退点")
        for t = 1, 3 do
            check(drivers[t].stageId == 999 and modules.battle.teamStageIds[tostring(t)] == 2305,
                "队" .. t .. "终焉挑战位置保存为末关回退点")
        end
        drivers[1].terminalRaid:finish(false)
        Page.update(0)
        for t = 1, 3 do
            check(drivers[t].stageId == 999 and modules.battle.teamStageIds[tostring(t)] == 2305,
                "队" .. t .. "终焉失败先保留战场，存档仍是末关回退点")
        end
        check(not Page.gotoTeamStage(1, 999), "失败退场期间不能提前重进终焉")
        Page.update(nativeRequire("ui.battle.tri.TerminalRaid").FAILURE_HOLD_SEC)
        for t = 1, 3 do
            check(drivers[t].stageId == 2305 and modules.battle.teamStageIds[tostring(t)] == 2305,
                "队" .. t .. "终焉失败展示结束后回退点已入档")
        end
        check(Page.gotoTeamStage(1, 999), "失败后仍可重新进入终焉")
        local raid = drivers[1].terminalRaid
        check(#raid.pools == 3 and #raid.enemies == 9, "重进终焉仍绑定九实例和三个编号池")
        for _, pool in ipairs(raid.pools) do pool.hp = 0 end
        raid:sync()
        check(raid.hp == 0, "全部编号池归零才汇总为胜利血量")
        Page.update(0)
        Page.update(0)
        for t = 1, 3 do
            check(drivers[t].stageId == 999 and modules.battle.teamStageIds[tostring(t)] == 2305,
                "队" .. t .. "胜利仍停终焉，待轮回保存末关")
        end
        check(terminalTarget == 2401 and Page.completeTerminalReincarnation(terminalTarget), "模拟动画完成统一三队目标进场")
        mainStage = terminalTarget
        modules.battle.currentStageId = terminalTarget
        modules.battle.teamStageIds = { ["1"] = terminalTarget, ["2"] = terminalTarget, ["3"] = terminalTarget }
        Save.Flush()
        for t = 1, 3 do
            check(drivers[t].stageId == 2401 and modules.battle.teamStageIds[tostring(t)] == 2401,
                "队" .. t .. "动画完成后的目标关已入档")
        end
        local terminalSave = cjson.decode(disk["standalone_save.json"])
        check(terminalSave.modules.battle.teamStageIds["2"] == 2401
            and terminalSave.modules.battle.teamStageIds["3"] == 2401,
            "终焉胜利实际Flush包含二三队目标关")
        Page.close()
        local lab = Driver.new(2, { battleLab = true, allyFactory = function() return {} end })
        local labCalls = 0
        lab.onStageChanged = function() labCalls = labCalls + 1 end
        lab:start(204)
        check(labCalls == 0, "战斗实验室不触发玩家关卡或入关剧情")
        check(firstCalls > 0, "自动推进仍走既有共享通关回调")
    end, debug.traceback)
    rawset(_G, "require", nativeRequire)
    rawset(_G, "File", nativeFile)
    rawset(_G, "fileSystem", nativeSystem)
    rawset(_G, "time", nativeTime)
    if ok then print("[tri_progress_test] ALL PASS: " .. assertions .. " assertions")
    else
        print("[tri_progress_test] FAIL " .. tostring(err))
        log:Write(LOG_ERROR, "[tri_progress_test] " .. tostring(err))
    end
    engine:Exit()
end
