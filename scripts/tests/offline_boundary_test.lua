-- 单机在线/离线收益时间边界回归（引擎运行环境中的内存存档替身）。
local function eq(actual, expected, label)
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
    local oldStage, oldResolve, oldCalc = stage.Get, calc.resolveIdleStageAnchors, calc.calcOfflineIdleRewards
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
    stage.Get = function() return {} end
    calc.resolveIdleStageAnchors = function() return 101, 101 end
    calc.calcOfflineIdleRewards = function(seconds)
        calcSeconds = seconds
        return { seconds = seconds, maxSeconds = 43200, kills = 0,
            adventureExp = 0, adventurerExp = calcHeroExp, gold = 7, equipSeeds = {}, scrollDrops = {} }
    end
    fileSystem = { FileExists = function() return disk ~= nil end }
    File = function(_, mode)
        local file = {}
        function file:IsOpen() return not (mode == FILE_WRITE and failOpen) end
        function file:ReadString() return disk end
        function file:WriteString(data)
            if failWrite then return false end
            disk = data
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
    modules.battle = { idleAccumSec = 0, idleHeroCount = 2 }
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

    os.time = realTime
    dispatcher.snapshotAll, dispatcher.get, dispatcher.handleStateUpdate = oldSnapshot, oldGet, oldUpdate
    state.exportSave, state.importSave = oldExport, oldImport
    stage.Get, calc.resolveIdleStageAnchors, calc.calcOfflineIdleRewards = oldStage, oldResolve, oldCalc
    pdm.GetModule, pdm.MarkDirty = oldPdmGet, oldDirty
    heroService.ApplyResonanceSync = oldResonance
    File, fileSystem = oldFile, oldSystem
    print("[offline_boundary_test] ALL PASS: startup freeze, old save, pending, claim, online, crash, short, clock rollback")
    engine:Exit()
end
