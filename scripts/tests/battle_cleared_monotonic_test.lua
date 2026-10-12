-- B01：永久 cleared 单调回归。沿用 tri_clear_unlock/scenario82 的隔离源码脚手架。
-- 真实 Driver.start/tick -> Page -> Scene.completeTriStageClear -> Boot 奖励，
-- 正式 SyncBattleState -> Dispatcher.publishLive（不回灌活战斗）-> 再胜利，
-- 并单独走 ClientMessageHandler -> Scene/Restore 的部分历史快照回灌。
-- 仅加载项目 Lua 源码；存档、随机掉落、战斗数值/绘制叶子为内存替身，不访问玩家档。
-- 本地 Scene 使用既有 getter/setter bind 与 StageLoad/Lifecycle，不引入远端 RuntimeContext。
-- 以 RESULT ALL PASS/FAIL 判定，Runtime exit0 本身不是通过证据。

local PREFIX = "[battle_cleared_monotonic] "
local checks, failures = 0, 0
local function check(value, label)
    checks = checks + 1
    if value then print(PREFIX .. "PASS " .. label)
    else failures = failures + 1; print(PREFIX .. "FAIL " .. label) end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

function Start()
    checks, failures = 0, 0
    local ok, err = xpcall(function()
        local nativeRequire, nativeCache = require, cache
        local SC = nativeRequire("config.StageConfig")
        local sources = {} ---@type table<string, string>
        local function source(name)
            if sources[name] then return sources[name] end
            local path = name:gsub("%.", "/") .. ".lua"
            local file = assert(nativeCache:GetFile(path), "缺少项目源码 " .. path)
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            file:Dispose()
            local text = table.concat(lines, "\n")
            sources[name] = text
            return text
        end
        local syncSource = assert(source("boot.Standalone"):match("(local battleSync =.-)\nlocal physW"),
            "必须提取完整正式 SyncBattleState，不能手抄逻辑")
        local function noop() end
        local function stub(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local function jsonCopy(value) return cjson.decode(cjson.encode(value)) end

        -- 每个用例有新 Dispatcher/MessageHandler/Scene/Restore/Boot/Page/Driver实例，
        -- 不修改引擎 require 单例，不运行 Standalone 全入口/Save 以免读取玩家存档。
        local function newProcess(data, fullEnemyWave)
            local ctx = { firstCalls = 0, restoreCalls = 0, syncCalls = 0, flushes = 0,
                confirmations = {}, popups = {}, drivers = {}, wallet = {} } ---@type any
            local deps = {} ---@type table<string, any>
            local env = setmetatable({ time = { elapsedTime = 100 } }, { __index = _G }) ---@type any
            env._G = env
            env.File = function() error("B01专项禁止访问任何玩家文件") end
            env.fileSystem = stub({ FileExists = function() error("B01专项禁止查玩家档") end })
            env.cache = { GetResource = function() error("B01专项禁止GPU/音频资源加载") end }
            env.require = function(name)
                if deps[name] ~= nil then return deps[name] end
                if name:match("^config%.") or name:match("^shared%.") then return nativeRequire(name) end
                deps[name] = stub()
                return deps[name]
            end
            local function compile(name)
                return assert(load(source(name), "@真实B01/" .. name, "t", env))()
            end
            -- 与现有 tri_clear_unlock 一样，只接真实 battle schema；不初始化其他玩家模块。
            local schema = nativeRequire("shared.battle.BattleSchema")
            deps["shared.ModuleRegistry"] = { applyOnLoad = function(name, battle)
                if name == "battle" then schema.Fields.battle.onLoad(battle) end
            end }
            deps["shared.schemas.CharacterSchema"] = { applyOnLoad = noop }
            deps["runtime.ClientDispatcher"] = compile("runtime.ClientDispatcher")
            ctx.dispatcher = deps["runtime.ClientDispatcher"]
            deps["boot.StandaloneSave"] = { Flush = function() ctx.flushes = ctx.flushes + 1; return true end }
            deps["core.PlayerStore"] = stub({ Get = function(name) return ctx.dispatcher.get(name) end })
            -- 只替换PDM查表出口，不初始化或读写真实玩家档。
            deps["rules.character.PlayerDataManager"] = { GetModule = function(_, name)
                return ctx.dispatcher.get(name)
            end }
            deps["shared.StageProvider"] = { Get = function() return SC end }
            deps["systems.OfflineCalc"] = {
                resolveIdleStageAnchors = function(snapshot) return snapshot.maxStageId, snapshot.maxStageId end,
                calcOnlineIdleRewards = function() return { gold = 0, adventureExp = 0, adventurerExp = 0 } end,
            }
            deps["systems.DropSystem"] = stub({ generateFirstClearEquips = function() return {} end,
                generateFirstClearScrolls = function() return nil end,
                rollKillDrop = function() return nil end, rollScrollDrop = function() return nil end })
            deps["systems.LootBoxSystem"] = stub({ getTotalCount = function() return 0 end })
            deps["systems.StoryPlayer"] = stub()
            deps["core.I18n"] = nativeRequire("core.I18n")
            deps["core.BattleLayout"] = compile("core.BattleLayout")
            deps["systems.AttributeDef"] = nativeRequire("systems.AttributeDef")
            deps["config.MonsterConfig"] = { createMonster = function(id)
                return { hp = 1, monsterId = id, atkProgress = 0, expReward = 0, goldReward = 0 }
            end }
            local mountedCombat = nil ---@type table|nil
            deps["ui.battle.combat.BattleCombat"] = stub({ newState = function() return { ctx = {} } end,
                mount = function(value) mountedCombat = value end,
                mountedState = function() return mountedCombat end,
                setContext = function(value) if mountedCombat then mountedCombat.ctx = value end end,
                DEATH_ANIM_DURATION = 0.3, REVIVE_ANIM_DURATION = 0.3 })
            for _, name in ipairs({ "ui.battle.combat.ProjectileSystem", "systems.ThreatManager",
                "systems.TalentManager", "ui.battle.combat.BattleEffects", "systems.StatusEffectManager",
                "systems.RelicConditionHandler", "systems.MapAffixSystem", "systems.BossAffixSystem" }) do
                deps[name] = stub({ newState = function() return {} end, newBattleRefs = function() return {} end,
                    newFxState = function() return {} end, newSemState = function() return {} end })
            end
            deps["ui.battle.stage.StageBerserk"] = stub({
                isActive = function() return false end, getAttackInterval = function(_, interval) return interval end })
            deps["ui.battle.stage.BattleStageNav"] = { NAV = {} }
            deps["ui.battle.scene.BattleAllyLifecycle"] = compile("ui.battle.scene.BattleAllyLifecycle")
            deps["ui.battle.stage.BattleEnemySpawn"] = {
                generateEnemyList = function()
                    return { { hp = 1, monsterId = 1, atkProgress = 0, expReward = 0, goldReward = 0 } }
                end,
                generateIdleEnemyList = function()
                    return { { hp = 1, monsterId = 1, atkProgress = 0, expReward = 0, goldReward = 0 } }, 1
                end,
                assignEnemiesToField = function(list) return list, {} end,
                getFirstClearBonusMonsterIds = function() return nil end,
            }
            -- 金币专项保留真实总怪数、场上分配和后备补位，只替换怪物数值。
            if fullEnemyWave then
                deps["ui.battle.stage.BattleEnemySpawn"] = compile("ui.battle.stage.BattleEnemySpawn")
            end
            deps["ui.character.panel.CharacterPanel"] = stub({
                getTeamSignature = function(team) return "syntheticTeam" .. team end,
                getDeployedTeam = function(team) return { { hp = 100, maxHp = 100, heroId = team, atkProgress = 0 } } end,
            })
            deps["ui.hud.popup.RewardPopup"] = stub({ show = function(title, rewards)
                ctx.popups[#ctx.popups + 1] = { title = title, rewards = rewards }
            end })
            deps["ui.battle.popup.TerminalConfirmDialog"] = stub({ open = function(id)
                ctx.confirmations[#ctx.confirmations + 1] = id
            end, isOpen = function() return #ctx.confirmations > 0 end })
            local state = stub({ getName = function() return "B01内存测试" end, getLevel = function() return 100 end,
                addExp = function(amount) ctx.wallet.exp = (ctx.wallet.exp or 0) + amount end })
            for _, field in ipairs({ "gold", "gems", "essence", "arcaneDust", "goldenKey", "corruptStone", "sacredStone" }) do
                ctx.wallet[field] = 0
                local suffix = field:sub(1, 1):upper() .. field:sub(2)
                state["get" .. suffix] = function() return ctx.wallet[field] end
                state["set" .. suffix] = function(value) ctx.wallet[field] = value end
            end
            deps["core.GameState"] = state
            deps["ui.battle.scene.BattleDataRestore"] = compile("ui.battle.scene.BattleDataRestore")
            deps["ui.battle.stage.BattleStageNavLogic"] = compile("ui.battle.stage.BattleStageNavLogic")
            deps["ui.battle.stage.BattleStageLoad"] = compile("ui.battle.stage.BattleStageLoad")
            deps["ui.battle.tri.BattleTriStageProgress"] = compile("ui.battle.tri.BattleTriStageProgress")
            deps["ui.battle.tri.TerminalSceneFlow"] = compile("ui.battle.tri.TerminalSceneFlow")
            deps["ui.battle.scene.BattleScene"] = compile("ui.battle.scene.BattleScene")
            ctx.scene = deps["ui.battle.scene.BattleScene"]
            local realRestore = ctx.scene.setBattleData
            ctx.scene.setBattleData = function(battle)
                ctx.restoreCalls = ctx.restoreCalls + 1
                return realRestore(battle)
            end
            deps["runtime.ClientMessageHandler"] = compile("runtime.ClientMessageHandler")
            ctx.handler = deps["runtime.ClientMessageHandler"]
            ctx.handler.setup({ sendAction = noop, ui = {} })
            ctx.handler.setupDataSubscriptions()
            -- 只初始化 battle；避免 heroes/player 全窗业务。Boot只读的模块写入无通知缓存。
            local modules = ctx.dispatcher.snapshotAll()
            modules.session = { introCompleted = true, initialHeroId = 1, claimedScenarios = {} }
            modules.heroes = { roster = {}, teams = {}, deployed = {} }
            modules.lootbox, modules.equipment, modules.player = { seeds = {} }, { inventory = {} }, {}
            ctx.dispatcher.set("battle", data)
            deps["ui.battle.tri.BattleTriDriver"] = compile("ui.battle.tri.BattleTriDriver")
            local makeDriver = deps["ui.battle.tri.BattleTriDriver"].new
            deps["ui.battle.tri.BattleTriDriver"].new = function(team, options)
                local driver = makeDriver(team, options)
                ctx.drivers[team] = driver -- 只spy创建，不替换start/tick/胜利/推进。
                return driver
            end
            deps["ui.battle.tri.BattleTriPage"] = compile("ui.battle.tri.BattleTriPage")
            ctx.page = deps["ui.battle.tri.BattleTriPage"]
            -- 使用真实采集器；只替换落盘出口，不以手抄快照掩盖永久账本回归。
            deps["boot.StandaloneSave"] = compile("boot.StandaloneSave")
            deps["boot.StandaloneSave"].Flush = function()
                ctx.flushes = ctx.flushes + 1
                ctx.lastSavedGold = ctx.wallet.gold
                return true
            end
            deps["boot.StandaloneSave"].SetBattlePage(ctx.page)
            -- 先提供真实 Page 再让 Boot 接线，首通与击杀/掉落出口均使用现有接口。
            deps["boot.StandaloneBoot"] = compile("boot.StandaloneBoot")
            deps["boot.StandaloneBoot"].run({ vg = {}, localSendAction = noop, setLocalBridgeReady = noop })
            local realFirstClear = ctx.scene.onFirstClear
            ctx.scene.onFirstClear = function(id, team)
                ctx.firstCalls = ctx.firstCalls + 1
                return realFirstClear(id, team)
            end
            ctx.page.open()
            env.BattleScene, env.ClientDispatcher, env.cjson = ctx.scene, ctx.dispatcher, cjson
            env.StandaloneSave, env.StageConfig, env.bootReady_ = deps["boot.StandaloneSave"], SC, true
            env.StandaloneRT, env.BattleTriPage = {}, ctx.page
            local sync = assert(load(syncSource .. "\nreturn SyncBattleState", "@正式B01/SyncBattleState", "t", env))()
            local publish = ctx.dispatcher.publishLive
            ctx.dispatcher.publishLive = function(name, snapshot)
                ctx.syncCalls = ctx.syncCalls + 1
                return publish(name, snapshot)
            end
            ctx.sync = sync
            ctx.battle = function() return ctx.dispatcher.get("battle") end
            ctx.enqueueEquipment = function()
                local sequence = {}
                deps["systems.DropSystem"].rollKillDrop = function() sequence[#sequence + 1] = "kill"; return 1 end
                deps["systems.DropSystem"].generateFirstClearEquips = function()
                    sequence[#sequence + 1] = "first"
                    return { { templateId = "W1", quality = 1, level = 1 } }
                end
                deps["systems.EquipmentSystem"].generateRandom = function()
                    sequence[#sequence + 1] = "pending"
                    return { templateId = "O1", quality = 1, level = 1 }
                end
                deps["systems.LootBoxSystem"].deliverEquipment = function(_, _, item)
                    sequence[#sequence + 1] = "deliver:" .. item.templateId
                    return "inventory"
                end
                -- 经真实 Driver 注入回调进入首通暂存，不手抄暂存奖励逻辑。
                local driver = assert(ctx.drivers[1])
                driver.onDrop({ stageId = 34505, teamIdx = 1, dropOnly = true, dropLuck = 0 })
                local notifications = {}
                ctx.dispatcher.subscribe("equipment", function() notifications.equipment = (notifications.equipment or 0) + 1 end)
                ctx.dispatcher.subscribe("lootbox", function() notifications.lootbox = (notifications.lootbox or 0) + 1 end)
                return sequence, notifications
            end
            ctx.win = function(team, id)
                local driver = assert(ctx.drivers[team], "队伍未解锁")
                driver:start(id)
                driver.introTimer = 0 -- 跳过纯视觉入场等待；保留真实生成及死亡报告/补位/胜利路径。
                for _, enemy in ipairs(driver.enemies) do enemy.hp = 0 end
                for _, enemy in ipairs(driver.enemyQueue) do enemy.hp = 0 end
                local limit = 0
                while not driver._clearReported and limit < 20 do
                    limit = limit + 1
                    driver:activate()
                    driver:tick(1.1)
                end
                assert(driver._clearReported, "真实Driver胜利没有到达Page/Scene")
            end
            return ctx
        end
        local function seeded(stageId, maxId)
            return { currentStageId = stageId, maxStageId = maxId, battleMode = "firstClear",
                clearedStages = { ["905"] = true, ["1905"] = true },
                teamStageIds = { ["1"] = stageId, ["2"] = stageId, ["3"] = stageId },
                idleAccumSec = 17, sentinel = { value = "保留非进度字段" } }
        end
        local function dualMark(ctx, id, label)
            check(ctx.scene.getClearedStages()[id] == true, label .. " Scene数字键为true")
            local saved = ctx.battle().clearedStages
            check(saved[tostring(id)] == true or saved[id] == true, label .. " Dispatcher永久键为true")
        end

        -- 合法最高关首通；三个队伍各自首次完成，随后多秒真实回灌再获胜。
        for firstTeam = 1, 3 do
            local label = "34505首通队" .. firstTeam
            local ctx = newProcess(seeded(34505, 34505))
            eq(SC.getNextStageId(34505), nil, label .. " 正式配置没有后继")
            local beforeFirstFlush = ctx.flushes
            ctx.win(firstTeam, 34505)
            eq(ctx.flushes - beforeFirstFlush, 1, label .. " 账本和奖励只同步提交一次")
            eq(ctx.firstCalls, 1, label .. " 首次回调1")
            eq(ctx.wallet.gold, SC.getStage(34505).fcGold, label .. " 首次金币86300")
            dualMark(ctx, 34505, label .. " 首胜")
            local restoreBefore = ctx.restoreCalls
            for second = 1, 6 do ctx.sync(1.1) end
            check(ctx.syncCalls > 0 and ctx.restoreCalls == restoreBefore, label .. " 真Sync/publishLive已执行且不回灌活战斗")
            dualMark(ctx, 34505, label .. " 六秒同步后")
            local gold, exp, gems, calls = ctx.wallet.gold, ctx.wallet.exp, ctx.wallet.gems, ctx.firstCalls
            local beforeRepeatFlush = ctx.flushes
            ctx.win(firstTeam, 34505)
            eq(ctx.flushes, beforeRepeatFlush, label .. " 重复挂机通关不即时全量写盘")
            print(PREFIX .. "EVIDENCE " .. label .. " gold=" .. gold .. "->" .. ctx.wallet.gold
                .. " exp=" .. exp .. "->" .. ctx.wallet.exp .. " gems=" .. gems .. "->" .. ctx.wallet.gems)
            eq(ctx.firstCalls, calls, label .. " 再胜回调增量0")
            eq(ctx.wallet.gold - gold, 0, label .. " 再胜首通金币增量0")
            eq(ctx.wallet.exp - exp, 0, label .. " 再胜首通经验增量0")
            eq(ctx.wallet.gems - gems, 0, label .. " 再胜首通钻石增量0")
            for team = 1, 3 do ctx.win(team, 34505) end
            eq(ctx.firstCalls, 1, label .. " 其他两队追赶仍总回调1")
            eq(ctx.wallet.gold, SC.getStage(34505).fcGold, label .. " 三队追赶金币只一份")
            dualMark(ctx, 34505, label .. " 追赶后")
            eq(ctx.battle().idleAccumSec, 17, label .. " 非进度字段未丢")
            eq(ctx.battle().sentinel.value, "保留非进度字段", label .. " 嵌套非进度字段未丢")
            ctx.page.close()
        end

        local rewards = newProcess(seeded(34505, 34505))
        local sequence, notifications = rewards.enqueueEquipment()
        rewards.win(1, 34505)
        eq(table.concat(sequence, ","), "kill,first,deliver:W1,pending,deliver:O1",
            "固定与暂存装备生成投递顺序保持")
        eq(notifications.equipment, 1, "同次首通两个装备来源只刷新装备一次")
        eq(notifications.lootbox, 1, "同次首通两个装备来源只刷新遗匣一次")
        local equipmentRewards = {}
        for _, item in ipairs(rewards.popups[#rewards.popups].rewards) do
            if item.type == "equip" then equipmentRewards[#equipmentRewards + 1] = item.templateId end
        end
        eq(table.concat(equipmentRewards, ","), "W1,O1", "奖励显示顺序和完整装备来源保持")
        rewards.page.close()

        local single = newProcess(seeded(34505, 34505))
        local beforeSingleFlush = single.flushes
        single.scene.onFirstClear(34505)
        eq(single.flushes - beforeSingleFlush, 1, "默认单队首通保留一次即时提交")
        eq(single.lastSavedGold, SC.getStage(34505).fcGold, "默认单队在奖励到账之后提交")
        single.page.close()

        -- JSON模拟进程重启，不能只复用旧Scene账本或引用复制。
        local first = newProcess(seeded(34505, 34505))
        first.win(3, 34505)
        local json = cjson.encode(first.battle())
        first.page.close()
        local fresh = newProcess(cjson.decode(json))
        check(fresh.scene ~= first.scene and fresh.dispatcher ~= first.dispatcher, "JSON恢复创建新Scene和Dispatcher")
        for second = 1, 6 do fresh.sync(1.1) end
        dualMark(fresh, 34505, "JSON恢复并同步")
        fresh.win(2, 34505)
        eq(fresh.firstCalls, 0, "JSON重启后再胜首通回调0")
        eq(fresh.wallet.gold, 0, "JSON重启后再胜首通资产增量0")
        fresh.page.close()

        -- 双键冲突/互补来源；false不是撤销已经true的永久事实。
        local ctx = newProcess(seeded(34505, 34505))
        ctx.scene.getClearedStages()[34505] = true
        ctx.battle().clearedStages = { [34505] = false, ["34505"] = true, [34504] = true, ["34504"] = false }
        for second = 1, 3 do ctx.sync(1.1) end
        dualMark(ctx, 34505, "数字false/字符串true合并")
        dualMark(ctx, 34504, "持久化数字true/字符串false合并")
        ctx.scene.getClearedStages()[34505] = nil -- 故意模拟局部运行表丢失，不能撤销永久来源。
        ctx.scene.getClearedStages()[34504] = nil
        ctx.sync(1.1)
        dualMark(ctx, 34505, "局部表丢失后账本修补")
        dualMark(ctx, 34504, "局部表丢失后互补数字键保留")
        ctx.scene.getClearedStages()[34505] = true
        ctx.handler.onBattleDataUpdate({ currentStageId = 34505, maxStageId = 34505, clearedStages = {} }, "battle")
        check(ctx.scene.getClearedStages()[34505] == true, "Restore空快照不删除已确认本地事实")
        ctx.handler.onBattleDataUpdate({ currentStageId = 34505, maxStageId = 34505 }, "battle")
        check(ctx.scene.getClearedStages()[34505] == true, "Restore缺省账本不删除事实")
        ctx.page.close()

        -- 无max后备推断的直接Restore边界，证明合并源而非碰巧被max补回。
        local values = { currentStageId = 101, initialBattleDataLoaded = true, battleActive = true,
            clearedStages = { [101] = true, ["102"] = true }, maxStageId_ = 101 }
        local restore = nativeRequire("ui.battle.scene.BattleDataRestore").bind({
            getStageConfig = function() return SC end, loadStage = noop, resetAllyUnit = noop,
            startBattleTalents = noop, recalcIdleIncome = noop, getAllies = function() return {} end,
            get = function(key) return values[key] end, set = function(key, value) values[key] = value end,
        })
        restore.setBattleData({ currentStageId = 101,
            clearedStages = { ["101"] = false, [102] = false, ["103"] = true, [104] = true, ["104"] = false } })
        check(values.clearedStages[101] and values.clearedStages[102], "无max推断Restore保留本地两种已确认键")
        check(values.clearedStages[103] and values.clearedStages[104], "无max推断Restore合并输入两种真值键")
        eq(values.maxStageId_, 101, "无max快照不改变最高关")
        restore.setBattleData({ clearedStages = { ["105.0"] = true, [106] = false,
            ["107"] = 1, ["108"] = "true", [0] = true, [-1] = true,
            ["109.5"] = true, ["not-a-stage"] = true, [true] = true, ["inf"] = true } })
        check(values.clearedStages[105] == true and values.clearedStages["105.0"] == nil,
            "有效正整数decimal键归一为唯一数字键")
        check(not values.clearedStages[106] and not values.clearedStages[107] and not values.clearedStages[108]
            and not values.clearedStages[0] and not values.clearedStages[-1]
            and not values.clearedStages[109.5] and not values.clearedStages["not-a-stage"]
            and not values.clearedStages[true], "false/非布尔true/非法关号不能成为永久事实")
        local input = { ["103"] = false, ["110"] = true }
        restore.setBattleData({ clearedStages = input })
        check(values.clearedStages[101] and values.clearedStages[103] and values.clearedStages[110],
            "部分快照并入新首通但不撤销缺项或false")
        check(input["103"] == false and input["110"] == true and input[101] == nil,
            "恢复不修改incoming账本或与其共享引用")
        for _, snapshot in ipairs({ { clearedStages = {} }, {}, { clearedStages = false } }) do
            restore.setBattleData(snapshot)
            check(values.clearedStages[101] and values.clearedStages[102] and values.clearedStages[103]
                and values.clearedStages[104] and values.clearedStages[105] and values.clearedStages[110],
                "无max空/缺省/非表快照保留全部永久事实")
        end
        local beforeNil = values.clearedStages
        restore.setBattleData(nil)
        check(values.clearedStages == beforeNil and values.isFirstClear == false,
            "nil输入完全无操作，已通当前关保持挂机")
        -- 本地历史键也必须过滤/归一，不能只检查incoming有效性。
        values.clearedStages["111"] = true
        values.clearedStages[112] = 1
        values.clearedStages[113.5] = true
        values.clearedStages[-2] = true
        restore.setBattleData({})
        check(values.clearedStages[111] == true and values.clearedStages["111"] == nil
            and not values.clearedStages[112] and not values.clearedStages[113.5]
            and not values.clearedStages[-2], "本地来源同样仅保留有效正整数true")

        -- 保持2305门禁：只有末关事实，999未通，不能补造轮回/强制加载2401。
        ctx = newProcess(seeded(2305, 2305))
        ctx.win(1, 2305)
        for second = 1, 4 do ctx.sync(1.1) end
        dualMark(ctx, 2305, "2305末关同步")
        check(not ctx.scene.getClearedStages()[999] and not ctx.battle().clearedStages["999"], "2305不伪造999永久事实")
        eq(ctx.scene.getMaxStageId(), 2305, "2305未通终焉共享上限不越过门禁")
        eq(ctx.drivers[1]:getAdvanceStageId(), 999, "2305推进目标仍是待确认终焉")
        ctx.drivers[1]:advanceStage()
        eq(ctx.drivers[1].stageId, 2305, "2305驱动仍停末关")
        -- 未确认终焉时不能停摆：队伍必须继续在原关战斗，只弹出一次确认。
        check(ctx.drivers[1].active, "2305未确认终焉仍继续战斗")
        check(ctx.drivers[1].marchTimer == 0, "2305未确认终焉不残留行军")
        check(not ctx.drivers[1].marchNotice, "2305未确认终焉不显示前进提示")
        check(#ctx.drivers[1].enemies + #ctx.drivers[1].enemyQueue > 0, "2305未确认终焉重新出怪")
        local confirmCount = #ctx.confirmations
        ctx.drivers[1]:start(2305)
        eq(#ctx.confirmations, confirmCount, "2305同关重开不重复弹确认")
        ctx.drivers[1].introTimer = 0
        for _, enemy in ipairs(ctx.drivers[1].enemies) do enemy.hp = 0 end
        for _, enemy in ipairs(ctx.drivers[1].enemyQueue) do enemy.hp = 0 end
        ctx.drivers[1]:tick(1.1)
        eq(ctx.confirmations[1], 999, "2305真实Scene.nextStage弹999确认")
        eq(ctx.scene.getStageId(), 2305, "未确认不进入999或轮回")
        ctx.page.close()

        -- 一队合法选旧关 + 已通旧关挂机原地重开，二三队最高进度不能拉走一队。
        local old = seeded(1001, 34505)
        old.clearedStages["1001"], old.clearedStages["34505"] = true, true
        ctx = newProcess(jsonCopy(old))
        eq(ctx.scene.getStageId(), 1001, "JSON恢复保留一队旧关")
        eq(ctx.scene.getMaxStageId(), 34505, "旧关与共享最高各司其职")
        for second = 1, 4 do ctx.sync(1.1) end
        eq(ctx.scene.getStageId(), 1001, "多秒同步不把旧关跳最高")
        ctx.drivers[1]:start(1001)
        eq(ctx.drivers[1].stageId, 1001, "旧关挂机同关重开不强制推进")
        eq(ctx.battle().currentStageId, 1001, "旧关重开保留一队落盘关卡")
        eq(ctx.battle().battleMode, "idle", "已通旧关重开保持挂机模式")
        eq(ctx.firstCalls, 0, "旧关启动与同步不补发历史首通")
        ctx.page.close()

        -- 资源选关必须清完整波后进入下一层；重打已通层也前进，失败退层不丢首通。
        local DC = nativeRequire("config.DungeonConfig")
        for team = 1, 3 do
            local resource = newProcess(seeded(1001, 4905), true)
            local dungeon = {}
            for _, dungeonId in ipairs(DC.RESOURCE_IDS) do
                dungeon[dungeonId] = { floor = 1, cleared = {} }
            end
            resource.dispatcher.set("dungeon", dungeon)
            local firstId = DC.getStageId("gold_mine", 1)
            -- 资源关按章节锚点推进，不能写死层号；以正式关卡链为准。
            local nextId = SC.getNextStageId(firstId)
            for attempt = 1, 2 do
                local label = "金币首层队" .. team .. (attempt == 1 and "首通" or "重打")
                check(resource.page.gotoTeamStage(team, firstId), label .. "真实选关")
                local driver = resource.drivers[team]
                driver.introTimer = 0
                eq(#driver.enemies + #driver.enemyQueue, SC.getStage(firstId).idleCount, label .. "真实整波怪数")
                check(#driver.enemyQueue > 0, label .. "存在后备怪物")
                for _, enemy in ipairs(driver.enemies) do enemy.hp = 0 end
                resource.page.update(1.1)
                check(not driver._clearReported and driver.marchTimer == 0, label .. "场上怪物倒下不是整波胜利")
                local ticks = 0
                while not driver._clearReported and ticks < 400 do
                    for _, enemy in ipairs(driver.enemies) do enemy.hp = 0 end
                    resource.page.update(0.1)
                    ticks = ticks + 1
                end
                check(driver._clearReported and driver.marchTimer > 0, label .. "整波胜利进入行军")
                eq(#driver.enemies + #driver.enemyQueue, 0, label .. "整波已清空")
                eq(driver.stageId, firstId, label .. "行军结束前仍显示首层")
                local sub = resource.dispatcher.get("dungeon").gold_mine
                check(sub.cleared[1] == true or sub.cleared["1"] == true, label .. "独立已通账本")
                check(DC.isStageUnlocked(nextId, resource.battle(), resource.dispatcher.get("dungeon")),
                    label .. "下一章节锚点已解锁")
                resource.sync(1.1)
                resource.page.update(driver.marchTimer - 0.1)
                eq(driver.stageId, firstId, label .. "未满两秒不提前换层")
                resource.page.update(0.2)
                eq(driver.stageId, nextId, label .. "自动进入下一章节锚点")
                eq(resource.battle().teamStageIds[tostring(team)], nextId, label .. "队伍位置同步")
                eq(resource.scene.getMaxStageId(), 4905, label .. "不改变主线最高关")
                eq(resource.firstCalls, 0, label .. "不触发主线首通奖励")
            end
            local driver = resource.drivers[team]
            driver.introTimer = 0
            for _, ally in ipairs(driver.allies) do ally.hp = 0 end
            resource.page.update(0.1)
            eq(driver.stageId, firstId, "金币第二层全灭会退回首层队" .. team)
            check(DC.isStageUnlocked(nextId, resource.battle(), resource.dispatcher.get("dungeon")),
                "退回首层仍保留下一层解锁队" .. team)
            resource.page.close()
        end

        -- 显式清档沿真实Dispatcher.reset + Scene.resetToDefault，Sync旧键缓存不是事实来源。
        ctx = newProcess(seeded(34505, 34505))
        ctx.win(2, 34505)
        ctx.sync(1.1)
        ctx.page.close()
        ctx.dispatcher.reset()
        ctx.scene.resetToDefault()
        ctx.handler.setupDataSubscriptions()
        ctx.dispatcher.set("battle", { currentStageId = 101, maxStageId = 101, clearedStages = {},
            teamStageIds = { ["1"] = 101, ["2"] = 101, ["3"] = 101 } })
        for second = 1, 3 do ctx.sync(1.1) end
        eq(ctx.scene.getStageId(), 101, "显式重置恢复初始当前关")
        eq(ctx.scene.getMaxStageId(), 101, "显式重置恢复初始最高关")
        eq(next(ctx.scene.getClearedStages()), nil, "显式重置后Scene账本为空")
        eq(next(ctx.battle().clearedStages), nil, "Sync旧缓存不复活已重置永久账本")
    end, debug.traceback)
    if not ok then
        failures = failures + 1
        print(PREFIX .. "FAIL exception=" .. tostring(err))
    end
    print(PREFIX .. "RESULT " .. (failures == 0 and "ALL PASS" or "FAIL")
        .. " checks=" .. checks .. " failures=" .. failures)
    engine:Exit()
end
