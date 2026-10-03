-- 无旧轮回过场回归：执行未改写的真实 Phases/宿主源码及 StageLoad/Casualty/NavLogic。
-- 跑法：.cli/UrhoXRuntime tests/samsara_no_cutscene_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- 只隔离模块实例；不复制宿主、不访问 debug/upvalue、不初始化真实玩家/领取奖励。
local PREFIX = "[samsara_no_cutscene] "
local assertions, failures = 0, 0

local function check(ok, message)
    assertions = assertions + 1
    if ok then
        print(PREFIX .. "PASS " .. message)
    else
        failures = failures + 1
        print(PREFIX .. "FAIL " .. message)
        log:Write(LOG_ERROR, PREFIX .. "FAIL " .. message)
    end
end

local function eq(actual, expected, message)
    check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

-- 源码原样 load；私有 require 表仅定向依赖，不修改 package.loaded 或全局 require。
---@param path string
---@param overrides table
---@return table
local function isolated(path, overrides)
    local file = cache:GetFile(path)
    assert(file and file:IsOpen(), "missing real module " .. path)
    -- 当前Runtime的File未绑定ReadText；ReadLine只读原始资源，不替换任何源码。
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    local source = table.concat(lines, "\n")
    file:Dispose()
    local env = setmetatable({
        require = function(name)
            if overrides[name] ~= nil then return overrides[name] end
            return require(name) -- 旧模块缺失直接失败，不提供替代模块绕过。
        end,
    }, { __index = _G })
    return assert(load(source, "@" .. path, "t", env))()
end

function Start()
    local restores = {}
    local function patch(object, key, replacement)
        local original = object[key]
        restores[#restores + 1] = function() object[key] = original end
        object[key] = replacement
        return original
    end

    local ok, err = pcall(function()
        local SC = require("config.StageConfig")
        local StageLoad = require("ui.battle.stage.BattleStageLoad")
        local Flow = require("ui.battle.stage.BattleStageFlow")
        local BC = require("ui.battle.combat.BattleCombat")
        local Dispatcher = require("runtime.ClientDispatcher")
        local Save = require("boot.StandaloneSave")
        local PDM = require("rules.character.PlayerDataManager")
        local Action = require("runtime.GameAction")
        local BGM = require("systems.GameBGM")
        local Nav = require("ui.hud.BottomNav")
        local modules = {
            session = { introCompleted = true, initialHeroId = 1, claimedScenarios = {} },
            heroes = { roster = {} },
            battle = { currentStageId = 101, maxStageId = 101, clearedStages = {} },
            currency = { gold = 123, gems = 456 },
        }
        local currencyBefore = cjson.encode(modules.currency)
        local saveCalls, actionCalls, dirtyCalls = 0, 0, 0
        patch(Dispatcher, "get", function(name) return modules[name] end)
        patch(Dispatcher, "getAll", function() return modules end)
        patch(Dispatcher, "snapshotAll", function() return modules end)
        patch(Save, "Flush", function() saveCalls = saveCalls + 1 end)
        patch(PDM, "GetModule", function(_, name) return modules[name] end)
        patch(PDM, "MarkDirty", function() dirtyCalls = dirtyCalls + 1 end)
        patch(PDM, "FlushImmediate", function() saveCalls = saveCalls + 1 end)
        patch(Action, "sendAction", function() actionCalls = actionCalls + 1 end)
        -- 离线Runtime没有GPU/音频；只替换这些外部边界，不替换战斗流程。
        patch(Flow, "ensureBattleCards", function() return {} end)
        patch(Flow, "pumpBattleCards", function() return nil end)
        patch(BGM, "setScene", function() end)
        local locks = {}
        patch(Nav, "setAllLocked", function(value) locks[#locks + 1] = value end)
        for _, key in ipairs({ "updateCardAnims", "updateFloatingTexts", "updateHitFlashes", "updateComboQueue" }) do
            patch(BC, key, function() end)
        end

        local inPhase = false
        local loads = {}
        local actualLoad = StageLoad.load
        patch(StageLoad, "load", function(ctx, stageId, skip)
            check(not inPhase, "StageLoad 边界未在 Phases 内触发 stage=" .. tostring(stageId))
            loads[#loads + 1] = stageId
            return actualLoad(ctx, stageId, skip)
        end)

        local realPhases = isolated("ui/battle/scene/BattleScenePhases.lua", {})
        local copyKeys = {
            "defeatTimer", "reincarnationTimer", "searchingTimer", "terminalDefeatPending",
            "defeatByTimeout", "battleActive", "pendingReincarnation", "bgTransAnim",
            "regenAccum", "enemies", "enemyQueue", "maxStageId_", "stageName",
            "isFirstClear", "currentStageId",
        }
        local function snapshot(ctx)
            local result = {}
            for _, key in ipairs(copyKeys) do result[key] = ctx[key] end
            return result
        end

        -- 低层契约：真实 Phases 准备四字段pending；所有load/callback边界只spy。
        local function phaseContract(terminal, target)
            local calledLoad, calledCallback = 0, 0
            local visuals = 0
            local function animate() visuals = visuals + 1 end
            ---@type table
            local ctx = {
                currentStageId = terminal, maxStageId_ = terminal, stageName = "phase-fixture",
                allies = {}, enemies = {}, enemyQueue = {}, clearedStages = {},
                battleActive = false, isFirstClear = false, isPaused = false,
                defeatTimer = nil, reincarnationTimer = 0, searchingTimer = nil,
                terminalDefeatPending = false, defeatByTimeout = false,
                pendingReincarnation = nil, bgTransAnim = nil, regenAccum = 0,
                DEFEAT_DELAY = 1.5, REINCARNATION_DELAY = 2,
                SEARCH_ENEMY_DURATION = 3, BG_ZOOM_BACK_TARGET = 1.22, BG_ZOOM_FWD_TARGET = 1.32,
                updateCardAnims = animate, updateFloatingTexts = animate,
                updateHitFlashes = animate, updateComboQueue = animate,
                getStageConfig = function() return SC end,
                loadStage = function() calledLoad = calledLoad + 1 end,
                onReincarnateCallback = function() calledCallback = calledCallback + 1 end,
                onStageChangedCallback = function() calledCallback = calledCallback + 1 end,
                resetAllyUnit = function() end, startBattleTalents = function() end,
                generateIdleEnemyList = function() return {}, 1 end,
                assignEnemiesToField = function(list) return list, {} end,
                BattleScene = { completeReincarnation = function() calledCallback = calledCallback + 1 end },
            }
            eq(realPhases.process(ctx, 1.5), true, "Phases 阈值前消费帧 " .. terminal)
            eq(ctx.reincarnationTimer, 1.5, "Phases 回灌阈值前计时")
            eq(ctx.pendingReincarnation, nil, "Phases 阈值前无pending")
            eq(ctx.reincarnationReady, nil, "Phases 阈值前无ready")
            ctx.isPaused = true
            eq(realPhases.process(ctx, 30), true, "Phases 暂停消费帧")
            eq(ctx.reincarnationTimer, 1.5, "Phases 暂停不推进轮回计时")
            eq(ctx.pendingReincarnation, nil, "Phases 暂停不创建pending")
            eq(ctx.reincarnationReady, nil, "Phases 暂停不置ready")
            ctx.isPaused = false
            eq(realPhases.process(ctx, 0.5), true, "Phases 恰到2秒消费帧")
            eq(ctx.reincarnationTimer, nil, "Phases 阈值清空计时")
            eq(ctx.reincarnationReady, true, "Phases 阈值置ready")
            local pending = ctx.pendingReincarnation --[[@as table?]]
            assert(pending, "Phases pending missing")
            eq(pending.targetStageId, target, "Phases pending目标")
            eq(pending.terminalStageId, terminal, "Phases pending终焉来源")
            eq(pending.fromDifficulty, SC.getDifficulty(terminal), "Phases pending来源难度")
            eq(pending.toDifficulty, SC.getDifficulty(target), "Phases pending目标难度")
            local fields = 0
            for _ in pairs(pending) do fields = fields + 1 end
            eq(fields, 4, "Phases pending仅四个数据字段")
            eq(ctx.currentStageId, terminal, "Phases 不自行切关")
            eq(ctx.maxStageId_, terminal, "Phases 不自行推进max")
            eq(calledLoad, 0, "Phases 内部不调用loadStage")
            eq(calledCallback, 0, "Phases 内部不调用任何callback/complete")
            check(visuals > 0, "Phases 暂停/计时仍推进视觉边界")
        end
        phaseContract(999, 2401)
        phaseContract(1999, 4701)

        -- 每个用例载入一个新的真实宿主与StoryPlayer，避免私有计时/排队状态污染。
        local function hostCase(terminal, target, mode)
            local label = tostring(terminal) .. "→" .. target .. "/" .. mode
            local story = isolated("systems/StoryPlayer.lua", {})
            local records = {}
            local phaseSpy = {
                process = function(ctx, dt)
                    local record = { before = snapshot(ctx), dt = dt }
                    inPhase = true
                    local resultOk, consumed = pcall(realPhases.process, ctx, dt)
                    inPhase = false
                    if not resultOk then error(consumed) end
                    record.after = snapshot(ctx)
                    record.ready = ctx.reincarnationReady
                    records[#records + 1] = record
                    return consumed
                end,
            }
            local scene = isolated("ui/battle/scene/BattleScene.lua", {
                ["ui.battle.scene.BattleScenePhases"] = phaseSpy,
                ["systems.StoryPlayer"] = story,
            })
            local notifications, completions = 0, 0
            local changes, firstClears = {}, {}
            local actualComplete = scene.completeReincarnation
            scene.completeReincarnation = function()
                completions = completions + 1
                return actualComplete()
            end
            scene.setOnFirstClear(function(stage)
                firstClears[#firstClears + 1] = stage
                -- 复用真实首通公开API接线，但不运行Boot奖励或存档逻辑。
                story.onStage(stage, "clear")
            end)
            scene.setOnStageChanged(function(stage) changes[#changes + 1] = stage end)
            if mode ~= "none" then
                scene.setOnReincarnate(function(data)
                    check(not inPhase, label .. " callback在Phases返回后")
                    notifications = notifications + 1
                    eq(data.newStageId, target, label .. " callback目标")
                    eq(data.fromDifficulty, SC.getDifficulty(terminal), label .. " callback来源难度")
                    eq(data.toDifficulty, SC.getDifficulty(target), label .. " callback目标难度")
                    eq(scene.getStageId(), terminal, label .. " callback尚未切关")
                    local expected = records[#records].after --[[@as table]]
                    -- 重入公开update(0)的spy输入即宿主真实状态；不是复制宿主回灌代码。
                    scene.update(0)
                    local observed = records[#records].before
                    for _, key in ipairs(copyKeys) do
                        eq(observed[key], expected[key], label .. " callback前已回灌 " .. key)
                    end
                    local pending = assert(observed.pendingReincarnation, "host pending not written before callback")
                    eq(pending.targetStageId, target, label .. " 真实宿主pending可读")
                    if mode == "sync" then scene.completeReincarnation() end
                end)
            end

            scene.setBattleData({ currentStageId = terminal, maxStageId = terminal, clearedStages = {} })
            eq(scene.getStageId(), terminal, label .. " 真实setBattleData入关")
            check(#scene.getEnemies() > 0, label .. " 真实StageLoad已出怪")
            -- 首通由debugInstantClear直接触发；空己方夹具避免英雄经济/装备成长路径。
            -- 本用例只证轮回消费帧和下一帧进入Phases的真实状态，不证新关常规战斗tick。
            -- setBattleData首次载入寻怪；真实Phases到期恢复battleActive。
            scene.update(3)
            scene.debugInstantClear()
            scene.update(0)
            eq(#firstClears, 1, label .. " 真实Casualty首通一次")
            eq(firstClears[1], terminal, label .. " 首通关卡正确")
            eq(scene.getClearedStages()[terminal], true, label .. " 首通标记")
            eq(scene.getStageId(), terminal, label .. " 胜利帧不提前轮回")
            eq(notifications, 0, label .. " 胜利帧不通知")
            eq(completions, 0, label .. " 胜利帧不complete")
            local initialLoads = #loads
            scene.update(1.5)
            eq(scene.getStageId(), terminal, label .. " 1.5秒不轮回")
            eq(notifications, 0, label .. " 阈值前不通知")
            scene.pause()
            scene.update(20)
            eq(records[#records].after.reincarnationTimer, 1.5, label .. " 真实宿主暂停保留计时")
            eq(notifications, 0, label .. " 暂停不通知")
            eq(#loads, initialLoads, label .. " 暂停不load")
            scene.resume()
            scene.update(0.25)
            eq(scene.getStageId(), terminal, label .. " 1.75秒不轮回")
            eq(notifications, 0, label .. " 1.75秒不通知")
            scene.update(0.25)

            if mode == "async" then
                eq(notifications, 1, label .. " 阈值通知一次")
                eq(completions, 0, label .. " 异步不自动complete")
                eq(#loads, initialLoads, label .. " 异步不自动load")
                eq(scene.getStageId(), terminal, label .. " 异步留在终焉待确认")
                for _ = 1, 5 do scene.update(5) end
                eq(notifications, 1, label .. " 等待25秒不重复通知")
                eq(completions, 0, label .. " 等待不自动complete")
                eq(records[#records].before.reincarnationTimer, nil, label .. " 待确认计时已清空")
                eq(records[#records].before.pendingReincarnation.targetStageId, target, label .. " 等待保留pending")
                scene.completeReincarnation()
            else
                eq(notifications, mode == "sync" and 1 or 0, label .. " 通知次数")
            end
            eq(completions, 1, label .. " 有效完成恰好一次")
            eq(scene.getStageId(), target, label .. " 完成后真实宿主目标关")
            eq(scene.getMaxStageId(), target, label .. " max覆盖新难度首关")
            eq(scene.getClearedStages()[terminal], true, label .. " 完成后终焉首通保留")
            eq(#loads, initialLoads + 1, label .. " 真实StageLoad目标只加载一次")
            eq(loads[#loads], target, label .. " 最后加载目标")
            eq(#changes, 1, label .. " StageChanged恰好一次")
            eq(changes[1], target, label .. " StageChanged目标")
            check(#scene.getEnemies() > 0 and scene.getEnemies()[1].hp > 0, label .. " 新关鲜活敌人未被旧ctx覆盖")
            -- complete无pending幂等；不计入有效完成次数，边界证明不load/不重复通知。
            actualComplete()
            eq(#loads, initialLoads + 1, label .. " 重复complete不load")
            eq(#changes, 1, label .. " 重复complete不切关通知")
            scene.update(0) -- 实测完成后下一帧宿主输入，不能被轮回旧ctx覆盖。
            eq(records[#records].before.currentStageId, target, label .. " 下一帧保留目标关")
            eq(records[#records].before.pendingReincarnation, nil, label .. " 下一帧pending已清空")
            eq(records[#records].before.reincarnationTimer, nil, label .. " 下一帧不重启轮回计时")
            eq(records[#records].before.battleActive, true, label .. " 下一帧新关battleActive为true")
            eq(completions, 1, label .. " 下一帧不重复complete")
            eq(notifications, mode == "none" and 0 or 1, label .. " 下一帧不重复轮回通知")

            local taken = {}
            for _ = 1, 10 do
                local item = story.take()
                if not item then break end
                taken[#taken + 1] = item.scenarioId
            end
            eq(#taken, 3, label .. " 真实StoryPlayer仅终焉enter/clear与新关enter三段")
            eq(taken[1], terminal == 999 and 61 or 68, label .. " 终焉进入仍入队")
            eq(taken[2], terminal == 999 and 62 or 69, label .. " 首通62/69仍入队")
            eq(taken[3], terminal == 999 and 63 or 70, label .. " 进入63/70仍入队")
            eq(#firstClears, 1, label .. " 整个轮回首通不重复")
            scene.setOnReincarnate(nil)
            scene.setOnFirstClear(nil)
            scene.setOnStageChanged(nil)
            scene.completeReincarnation = actualComplete
        end

        hostCase(999, 2401, "none")
        hostCase(1999, 4701, "none")
        hostCase(999, 2401, "sync")
        hostCase(1999, 4701, "async")
        eq(cjson.encode(modules.currency), currencyBefore, "fixture经济数据未变")
        eq(saveCalls, 0, "没有请求玩家存档落盘")
        eq(actionCalls, 0, "没有发送经济/领奖action")
        eq(dirtyCalls, 0, "没有修改真实规则存档")
        check(#locks > 0 and locks[#locks] == false, "轮回到阈值解锁导航")
    end)
    if not ok then
        check(false, "异常: " .. tostring(err))
    end
    -- 所有全局边界逐一恢复；某个恢复失败不会阻断后续恢复或engine退出。
    for i = #restores, 1, -1 do
        local restored, restoreErr = pcall(restores[i])
        if not restored then check(false, "恢复边界异常: " .. tostring(restoreErr)) end
    end
    print(PREFIX .. "RESULT assertions=" .. assertions .. " failures=" .. failures)
    if failures == 0 then print(PREFIX .. "ALL PASS") end
    engine:Exit()
end
