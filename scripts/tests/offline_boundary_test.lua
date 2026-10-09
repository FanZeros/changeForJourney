-- 单机在线/离线收益时间边界回归（引擎运行环境中的内存存档替身）。
local assertions = 0
local function eq(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

function Start()
    local now = 10000
    local realTime = os.time
    os.time = function() return now end

    local dispatcher = require("runtime.ClientDispatcher")
    local state = require("core.GameState")
    local offline = require("rules.offline.OfflineService")
    local calc = require("systems.OfflineCalc")
    local stage = require("shared.StageProvider")
    local pdm = require("rules.character.PlayerDataManager")
    local oldSnapshot, oldGet, oldUpdate, oldExport, oldImport =
        dispatcher.snapshotAll, dispatcher.get, dispatcher.handleStateUpdate,
        state.exportSave, state.importSave
    local oldStage, oldResolve, oldCalc = stage.Get, calc.resolveIdleStageAnchors, calc.calcTeamOfflineRewards
    local SC = require("config.StageConfig")
    local oldPdmGet, oldDirty = pdm.GetModule, pdm.MarkDirty
    local heroService = require("rules.hero.HeroService")
    local oldResonance = heroService.ApplyResonanceSync
    local oldFile, oldSystem = File, fileSystem
    local disk = nil
    local failWrite = false
    local failOpen = false
    local modules = {}
    local calcSeconds = nil
    local calcHeroExp = 0

    dispatcher.snapshotAll = function() return modules end
    dispatcher.get = function(name) return modules[name] end
    dispatcher.handleStateUpdate = function(json)
        local patch = cjson.decode(json).modules
        for name, data in pairs(patch) do modules[name] = data end
    end
    state.exportSave = function() return {} end
    state.importSave = function() end
    pdm.GetModule = function(_, name) return modules[name] end
    pdm.MarkDirty = function() end
    heroService.ApplyResonanceSync = function() end
    stage.Get = function() return SC end
    calc.resolveIdleStageAnchors = function() return 101, 101 end
    calc.calcTeamOfflineRewards = function(seconds, teams)
        calcSeconds = seconds
        return { seconds = seconds, effectiveSeconds = seconds, maxSeconds = 43200, kills = 0,
            adventureExp = 0, adventurerExp = calcHeroExp, gold = 7, diamond = 0, equipSeeds = {}, scrollDrops = {},
            teamRewards = { { teamIdx = 1, stageId = 101, heroCount = teams[1] and teams[1].heroCount or 0,
                gold = 7, diamond = 0, adventureExp = 0, adventurerExp = calcHeroExp,
                kills = 0, equipSeeds = {}, scrollDrops = {} } } }
    end
    local temporaryFiles = {}
    fileSystem = {
        FileExists = function(_, path)
            return path == "standalone_save.json" and disk ~= nil or temporaryFiles[path] ~= nil
        end,
        Rename = function(_, source, destination)
            if destination ~= "standalone_save.json" or type(temporaryFiles[source]) ~= "string" then return false end
            disk = temporaryFiles[source]
            temporaryFiles[source] = nil
            return true
        end,
    }
    File = function(path, mode)
        local file = {}
        function file:IsOpen() return not (mode == FILE_WRITE and failOpen) end
        function file:ReadString() return path == "standalone_save.json" and disk or temporaryFiles[path] end
        function file:WriteString(data)
            if failWrite then return false end
            if path == "standalone_save.json" then disk = data else temporaryFiles[path] = data end
            return true
        end
        function file:Close() end
        return file
    end
    local save = require("boot.StandaloneSave")

    local function saved()
        assert(type(disk) == "string", "存档必须已写入")
        return cjson.decode(disk)
    end
    local function restore(lastOnline, savedAt, accum)
        offline.Cleanup(1)
        modules = {
            session = { lastOnlineTime = lastOnline, firstLoginTime = 100 },
            battle = { idleAccumSec = accum, idleHeroCount = 1 },
            heroes = { deployed = {}, roster = {} }, player = { level = 1, exp = 0 },
            currency = { gold = 40 }, equipment = { inventory = {} },
        }
        disk = cjson.encode({ savedAt = savedAt, gameState = {}, modules = modules })
        eq(save.RestoreData(), true, "读入旧存档")
        calcSeconds = nil
    end
    local function enter()
        save.ReconcileOfflineBoundary()
        local panel = offline.CalcOnEnter(1)
        save.OfflineChecked()
        return panel
    end

    restore(7000, 9000, 18)
    save.Update(120)
    save.Flush()
    eq(saved().savedAt, 9000, "开场未结算时不能写档")
    local panel = enter()
    eq(calcSeconds, 1000, "旧档仅补上次落盘后真实离线的1000秒")
    eq(modules.battle.idleAccumSec, 0, "旧在线累积秒数不重复补算")
    save.Update(120)
    save.Flush()
    eq(saved().savedAt, 9000, "待领取奖励时继续冻结存档")
    eq(modules.session.lastOnlineTime, 9000, "待领取奖励不前推在线边界")
    local rewardPanel = require("ui.hud.popup.OfflineRewardPanel")
    local attempts = 0
    rewardPanel.show({ offlineSeconds = panel.offlineSeconds, rewards = panel.rewards,
        onClaim = function()
            attempts = attempts + 1
            if attempts == 1 then return false end
            local ok = offline.ClaimRewards(1)
            if ok then save.Flush() end
            return ok
        end,
    })
    eq(rewardPanel.claim(), true, "失败领取事件由弹窗消费")
    eq(rewardPanel.isOpen(), true, "领取失败时弹窗不关闭")
    eq(offline.HasPendingRewards(1), true, "领取失败仍保留待领数据")
    eq(saved().savedAt, 9000, "领取失败时旧存档仍保留")
    eq(rewardPanel.claim(), true, "第二次领取成功")
    eq(attempts, 2, "领取回调只执行两次")
    eq(offline.HasPendingRewards(1), false, "成功领取后清除待领数据")
    eq(modules.currency.gold, 47, "真实领取发放一次7金币")
    eq(saved().modules.currency.gold, 47, "领取金币随在线边界一起落盘")
    eq(saved().modules.session.lastOnlineTime, now, "领取后落盘真实在线边界")
    now = 10400
    save.Update(3)
    save.Update(3)
    save.Flush()
    eq(saved().modules.session.lastOnlineTime, now, "在线战斗运行期间推进边界")
    -- 模拟异常结束：落盘后不调用 Flush，下一次进程只从最后成功存档继续。
    restore(10000, 10000, 0)
    now = 10300
    enter()
    eq(calcSeconds, 300, "异常结束只补最后一次落盘后的离线区间")
    restore(10400, 10400, 0)
    now = 10420
    enter()
    eq(calcSeconds, nil, "短离线不发奖励")
    save.Flush()
    eq(saved().modules.session.lastOnlineTime, now, "短离线退出仍保存本轮在线时刻")
    restore(15000, 15000, 0)
    now = 14000
    enter()
    eq(calcSeconds, nil, "系统时钟回拨不产生负收益")
    save.Flush()
    eq(saved().modules.session.lastOnlineTime, 15000, "时钟回拨不倒退在线边界")

    -- 存档往返：未编队英雄也必须留在 roster，不能按 deployed 数组位置还原。
    local heroes = { roster = {
        [1] = { level = 2, exp = 4 },
        [2] = { level = 3, exp = 6 },
        [25] = { level = 7, exp = 8 },
    }, deployed = { 1, 0, 2, 0 }, teams = { { slots = { 1, 0, 2, 0 } } } }
    modules.heroes = heroes
    save.Flush()
    local restoredHeroes = saved().modules.heroes
    require("shared.ModuleRegistry").applyOnLoad("heroes", restoredHeroes)
    require("shared.schemas.CharacterSchema").applyOnLoad("heroes", restoredHeroes)
    eq(restoredHeroes.roster[1].level, 2, "队1英雄存档等级保留")
    eq(restoredHeroes.roster[2].level, 3, "非连续英雄编号不与编队位置混淆")
    eq(restoredHeroes.roster[25].level, 7, "未编队英雄存档等级保留")
    eq(restoredHeroes.roster[25].exp, 8, "未编队英雄经验保留")
    eq(restoredHeroes.deployed[3], 2, "编队空槽位置保留")
    eq(restoredHeroes.teams[1].slots[3], 2, "三队编队槽位保留")

    -- 带 0 空槽的读档：奖励只能平分给真实英雄，预览与领取保持一致。
    offline.Cleanup(1)
    now = 20000
    calcHeroExp = 100
    modules.heroes = restoredHeroes
    modules.session = { lastOnlineTime = 19000, firstLoginTime = 100 }
    modules.battle = { currentStageId = 101, maxStageId = 101, idleAccumSec = 0, idleHeroCount = 2 }
    local sparsePanel = offline.CalcOnEnter(1)
    eq(#sparsePanel.heroExpPreview, 2, "空槽不能生成经验预览")
    eq(sparsePanel.heroExpPreview[1].expGain, 50, "经验只按真实队员平分")
    eq(sparsePanel.heroExpPreview[2].expGain, 50, "第二位队员预览经验正确")
    eq(sparsePanel.heroExpPreview[2].heroId, 2, "空槽后面的队员仍能领取经验")
    local claimOk, _, claimResult = offline.ClaimRewards(1)
    eq(claimOk, true, "有空槽时可以领取离线经验")
    eq(claimResult.heroExp, 50, "实际领取的每人经验与预览一致")
    eq(restoredHeroes.roster[1].level, sparsePanel.heroExpPreview[1].level, "队员1实际等级与预览一致")
    eq(restoredHeroes.roster[1].exp, sparsePanel.heroExpPreview[1].exp, "队员1实际经验与预览一致")
    eq(restoredHeroes.roster[2].level, sparsePanel.heroExpPreview[2].level, "队员2实际等级与预览一致")
    eq(restoredHeroes.roster[2].exp, sparsePanel.heroExpPreview[2].exp, "队员2实际经验与预览一致")
    eq(restoredHeroes.roster[25].exp, 8, "未上阵队员经验不变")
    offline.Cleanup(1)

    -- 写档失败不能当成成功快照，下一轮 Update 应自动重试。
    save.Flush()
    local previousDisk = disk
    modules.currency.gold = 99
    failWrite = true
    save.Flush()
    eq(disk, previousDisk, "写盘失败不能改动已经存在的存档")
    failWrite = false
    save.Update(1)
    save.Update(1)
    save.Update(2)
    eq(saved().modules.currency.gold, 99, "写盘恢复后自动重试未落盘变更")

    local previousOpenDisk = disk
    modules.currency.gold = 123
    failOpen = true
    save.Flush()
    eq(disk, previousOpenDisk, "无法打开文件时旧存档保持不变")
    failOpen = false
    save.Update(2)
    eq(saved().modules.currency.gold, 123, "文件可再次打开时自动重试存档")

    -- 真实规则只用内存PDM；独立挑战覆盖指定队伍，冷恢复来源不借最高主线或首通奖。
    calc.calcTeamOfflineRewards = oldCalc
    local DC = require("config.DungeonConfig")
    local Income = require("config.IdleIncomeConfig")
    local Dungeon = require("rules.dungeon.DungeonService")
    local Tower = require("rules.tower.TowerService")
    local function resetSources()
        offline.Cleanup(1)
        Dungeon.Cleanup(1)
        Tower.ResetToDefault(1)
        modules = {
            battle = { currentStageId = 101, maxStageId = 2305, clearedStages = {},
                teamStageIds = { ["1"] = 101, ["2"] = 200001, ["3"] = 300001 } },
            heroes = { roster = { [1] = { level = 1, exp = 0 }, [2] = { level = 1, exp = 0 },
                [3] = { level = 1, exp = 0 } }, deployed = { 1 },
                teams = { { slots = { 1 } }, { slots = { 2 } }, { slots = { 3 } } } },
            dungeon = { gold_mine = { floor = 1, cleared = {} }, equipment_vault = { floor = 1, cleared = {} },
                black_diamond = { floor = 1, cleared = {} }, babel_tower = { floor = 1, cleared = {}, buffs = {} } },
            player = { level = 1, exp = 0 }, equipment = { inventory = {} }, lootbox = {},
            currency = { gold = 0, gems = 0 }, session = { lastOnlineTime = now - 3600, firstLoginTime = 100 },
        }
    end
    resetSources()
    local ready, _, challenge = Dungeon.Challenge(1, "gold_mine", 1, 2)
    eq(ready, true, "进行中独立金币副本挑战")
    eq(challenge.teamIdx, 2, "独立挑战仅覆盖队2")
    eq(modules.battle.teamStageIds["2"], 200001, "独立挑战不改队2原任务")
    eq(modules.battle.maxStageId, 2305, "独立挑战不推主线最高")
    save.Flush()
    local persistedBattle = saved().modules.battle
    eq(persistedBattle.offlineChallengeSources["2"].stageId, 100001, "覆盖来源进入唯一真实存档")
    Dungeon.Cleanup(1)
    eq(next(modules.battle.offlineChallengeSources), nil, "退出活跃副本清覆盖来源")
    modules.battle = persistedBattle
    modules.session.lastOnlineTime = now - 3600
    Dungeon.Cleanup(1)
    eq(modules.battle.offlineChallengeSources["2"].stageId, 100001, "冷启动Cleanup保留离线来源")
    local panelSources = offline.CalcOnEnter(1)
    eq(#panelSources.teamSources, 3, "三队独立来源")
    eq(panelSources.teamSources[1].stageId, 101, "队1仍刷保存低主线")
    eq(panelSources.teamSources[2].stageId, 100001, "队2按离线时独立挑战副本")
    eq(panelSources.teamSources[2].sourceKind, "dungeon", "独立副本来源明确")
    eq(panelSources.teamSources[2].sourceStageId, 305, "金币首层源主线305")
    eq(panelSources.teamSources[3].stageId, 300001, "队3保留资源黑钻任务")
    local goldPerMin, expPerMin = Income.get(101)
    eq(panelSources.teamSources[1].gold, goldPerMin * 60, "低主线不偷最高主线收入")
    eq(panelSources.teamSources[1].adventureExp, expPerMin * 60, "低主线经验使用本关")
    eq(panelSources.teamSources[2].adventureExp, DC.getStageExpAmount(100001, 1200), "挑战队经验只用自身副本")
    eq(panelSources.teamSources[3].adventureExp, DC.getStageExpAmount(300001, 1200), "独立黑钻队经验")
    eq(modules.battle.offlineChallengeSources, nil, "计算捕获后消费覆盖来源")
    eq(next(modules.dungeon.gold_mine.cleared), nil, "重登不补副本首通账本")
    eq(modules.dungeon.gold_mine.floor, 1, "重登不推进进行中副本")
    eq(offline.CalcOnEnter(1), panelSources, "重复进场复用奖励和来源")
    local originalSources = panelSources.teamSources[2].stageId
    modules.battle.teamStageIds["2"] = 2305
    eq(panelSources.teamSources[2].stageId, originalSources, "来源不随live任务变化")
    eq(offline.ClaimRewards(1), true, "来源奖励真实领取")
    eq(modules.session.lastOnlineTime, now, "领取推进离线边界")
    eq(next(modules.dungeon.gold_mine.cleared), nil, "领取也不补首通")

    resetSources()
    eq(Tower.Challenge(1, 1), true, "三队进入独立塔")
    eq(modules.battle.offlineChallengeSources["1"].paused, true, "塔队1无离线产出标记")
    save.Flush()
    persistedBattle = saved().modules.battle
    Tower.Cleanup(1)
    eq(next(modules.battle.offlineChallengeSources), nil, "塔退出清暂停标记")
    modules.battle = persistedBattle
    modules.session.lastOnlineTime = now - 3600
    Tower.ResetToDefault(1)
    eq(modules.battle.offlineChallengeSources["1"].paused, true, "冷启动塔重置不先删快照")
    panelSources = offline.CalcOnEnter(1)
    eq(#panelSources.teamSources, 3, "塔三队来源仍可解释")
    eq(panelSources.totalKills, 0, "塔离线无击杀")
    eq(panelSources.adventureExp, 0, "塔离线不偷原主线经验")
    eq(#panelSources.rewards, 0, "塔离线不发黑钻神器首通或原主线奖励")
    for _, source in ipairs(panelSources.teamSources) do
        eq(source.sourceKind, "tower", "塔各队来源")
        eq(source.paused, true, "塔各队零产出")
    end
    resetSources()
    modules.heroes.teams[1].slots = { 0 }
    modules.battle.offlineChallengeSources = { ["1"] = { sourceKind = "tower", stageId = 400001, paused = true },
        ["2"] = { sourceKind = "dungeon", stageId = 999999 } }
    local eligible = offline.PreviewTeamIncome(modules.heroes, modules.battle, modules.dungeon, 3600)
    eq(#eligible.teamRewards, 1, "空队与无效挑战不借旧主线")
    eq(eligible.teamRewards[1].teamIdx, 3, "仅合法资源队产生收益")
    resetSources()
    local Drop = require("systems.DropSystem")
    local MC = require("config.MonsterConfig")
    local testedDifficulties = {}
    local originalRandom = math.random
    for floor = 1, DC.MAX_FLOOR.equipment_vault do
        local combat = DC.getStage(DC.getStageId("equipment_vault", floor))
        local source = SC.getStage(combat.sourceStageId)
        local difficulty = SC.getDifficulty(source.id)
        if not testedDifficulties[difficulty] or source.id == 2305 or source.id == 4605
            or source.id == 6905 or source.id == 9205 or source.id == 34505 then
            testedDifficulties[difficulty] = true
            local probabilities = DC.getEquipQualityProbabilities(floor)
            local oracle = { 0, 0, 0, 0, 0, 0 }
            local monsterIds = {}
            for _, id in ipairs(source.monsters) do monsterIds[#monsterIds + 1] = id end
            if source.bossId > 0 then monsterIds[#monsterIds + 1] = source.bossId end
            local high = source.id >= SC.HELL_FIRST_STAGE
            local cap = SC.getMaxDropQuality(source)
            for _, monsterId in ipairs(monsterIds) do
                local weights = MC.QUALITY[MC.MONSTERS[monsterId].quality].dropWeights
                local sum = 0
                for q = 1, 6 do sum = sum + weights[q] * (high and q >= 5 and 3 or 1) end
                for q = 1, 6 do
                    local quality = math.min(q, cap)
                    oracle[quality] = oracle[quality] + weights[q] * (high and q >= 5 and 3 or 1) / sum / #monsterIds
                end
            end
            local sum = 0
            for q = 1, 6 do
                eq(math.abs(probabilities[q] - oracle[q]) < 1e-12, true, "副本品质与源主线同口径")
                sum = sum + probabilities[q]
            end
            eq(math.abs(sum - 1) < 1e-12, true, "品质概率和为1")
            print(string.format("[offline_boundary_test] QUALITY floor=%d source=%d Q4=%.6f%% Q5=%.6f%% Q6=%.6f%%",
                floor, source.id, probabilities[4] * 100, probabilities[5] * 100, probabilities[6] * 100))
            local cumulative = 0
            for q = 1, 6 do
                if probabilities[q] > 0 then
                    local point = cumulative + probabilities[q] / 2
                    math.random = function(lower) return lower or point end
                    eq(DC.rollEquipQuality(floor), q, "统一CDF抽样区间")
                    local stageId = DC.getStageId("equipment_vault", floor)
                    local perMinute = require("config.DungeonIdleConfig").getIdlePerMin("equipment_vault", floor)
                    local dropped = DC.getStageRewards(stageId, 20 / perMinute, 1)
                    eq(dropped.equipSeeds[1].quality, q, "在线资源奖励使用同源品质")
                end
                cumulative = cumulative + probabilities[q]
            end
            math.random = originalRandom
        end
    end
    local highWeights, weightTotal = Drop.getQualityWeights(5, SC.DIFFICULTY_HELL, 0)
    eq(highWeights[5], 300, "高难度传说权重三倍")
    eq(highWeights[6], 60, "高难度至臻权重三倍")
    eq(weightTotal, 1210, "高难度总权重")
    math.random = function() return 1210 end
    eq(calc._rollQualityByMonster(5, SC.DIFFICULTY_HELL), 6, "离线品质复用高难度权重")
    math.random = originalRandom
    local preview = calc.previewTeamOfflineRewards(86400,
        { { teamIdx = 1, stageId = 200001, heroCount = 1 } })
    local probability = DC.getEquipQualityProbabilities(1)
    local fullCount = DC.getEquipSweepCount(1) * 2
    for _, seed in ipairs(preview.teamRewards[1].equipSeeds) do
        eq(math.abs(seed.count - fullCount * probability[seed.quality]) < 1e-9, true,
            "离线资源装备预览按权重而非均匀稀有度")
    end

    os.time = realTime
    dispatcher.snapshotAll, dispatcher.get, dispatcher.handleStateUpdate = oldSnapshot, oldGet, oldUpdate
    state.exportSave, state.importSave = oldExport, oldImport
    stage.Get, calc.resolveIdleStageAnchors, calc.calcTeamOfflineRewards = oldStage, oldResolve, oldCalc
    pdm.GetModule, pdm.MarkDirty = oldPdmGet, oldDirty
    heroService.ApplyResonanceSync = oldResonance
    File, fileSystem = oldFile, oldSystem
    print("[offline_boundary_test] ALL PASS assertions=" .. assertions
        .. ": startup freeze, pending, claim, source isolation, tower pause, rarity, time boundaries")
    engine:Exit()
end
