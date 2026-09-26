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
    local modules = {}
    local calcSeconds = nil

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
            adventureExp = 0, adventurerExp = 0, gold = 7, equipSeeds = {}, scrollDrops = {} }
    end
    fileSystem = { FileExists = function() return disk ~= nil end }
    File = function(_, mode)
        local file = {}
        function file:IsOpen() return true end
        function file:ReadString() return disk end
        function file:WriteString(data) disk = data end
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

    os.time = realTime
    dispatcher.snapshotAll, dispatcher.get, dispatcher.handleStateUpdate = oldSnapshot, oldGet, oldUpdate
    state.exportSave, state.importSave = oldExport, oldImport
    stage.Get, calc.resolveIdleStageAnchors, calc.calcOfflineIdleRewards = oldStage, oldResolve, oldCalc
    pdm.GetModule, pdm.MarkDirty = oldPdmGet, oldDirty
    heroService.ApplyResonanceSync = oldResonance
    File, fileSystem = oldFile, oldSystem
    print("[offline_boundary_test] PASS: startup freeze, old save, pending, claim, online, crash, short, clock rollback")
end
