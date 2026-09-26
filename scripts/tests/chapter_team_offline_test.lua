-- 选关确认、章节滚动与编队拖拽回归；外部服务均用内存替身。
local function eq(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

function Start()
    local oldTime = time
    time = { elapsedTime = 20 }
    local stageId, maxStageId, jumps = 101, 305, 0
    local battleScene = require("ui.battle.scene.BattleScene")
    local oldGetStageId, oldGetMaxStageId, oldGotoStage =
        battleScene.getStageId, battleScene.getMaxStageId, battleScene.gotoStage
    battleScene.getStageId = function() return stageId end
    battleScene.getMaxStageId = function() return maxStageId end
    battleScene.gotoStage = function(id)
        jumps = jumps + 1
        stageId = id
        return true
    end
    package.loaded["systems.ButtonFeedback"] = { trigger = function() end }
    local Stage = require("ui.battle.stage.StageSelectDialog")
    Stage.open()
    eq(Stage.isOpen(), true, "选关弹窗打开")
    Stage.handleInput(370, 1060) -- 1-1：当前关无需切换
    eq(jumps, 0, "当前关不切换")
    Stage.handleInput(480, 1060) -- 1-2：首次点击仅展开确认
    eq(jumps, 0, "选关首次点击不切换")
    Stage.handleInput(395, 1508)
    eq(jumps, 0, "取消确认不切换")
    Stage.handleInput(480, 1060)
    Stage.handleInput(686, 1508)
    eq(stageId, 102, "确认后切换目标关")
    eq(jumps, 1, "确认只触发一次切换")
    eq(Stage.isOpen(), false, "切换后关闭弹窗")

    Stage.open()
    Stage.handleInput(595, 1060) -- 1-3
    maxStageId = 101
    Stage.handleInput(686, 1508)
    eq(jumps, 1, "进度变化时确认再次检查解锁")
    Stage.handleInput(370, 1060)
    eq(jumps, 1, "未解锁关卡不打开切换")
    Stage.close()
    maxStageId = 305
    Stage.open()
    Stage.handleScroll(-3, 175, 850)
    Stage.handleInput(175, 830) -- 滚动后选中第 4 章
    Stage.handleInput(370, 1060)
    eq(jumps, 1, "不可选章节中未解锁关卡")
    Stage.close()
    Stage.open()
    Stage.handleDragBegin(175, 1000)
    Stage.handleDragMove(175, 740)
    Stage.handleDragEnd()
    Stage.handleInput(175, 740) -- 松手后的点击应被消费
    Stage.handleInput(370, 1060) -- 仍是原章节的 1-1
    eq(jumps, 1, "拖动结束不会误选其他章节")
    Stage.close()

    local Input = require("ui.character.panel.CharacterInput")
    local slots = {
        { state = "occupied", heroId = 1 },
        { state = "occupied", heroId = 2 },
        { state = "empty" },
    }
    local power = { 10, 20, 0 }
    local drag = { active = false }
    local updates = 0
    local api = Input.bind({
        CharacterDetail = { isOpen = function() return false end },
        Draw = {
            hitTestAvatarSlot = function(x, y)
                if y == 500 and x >= 1 and x <= 3 then return 1, x end
            end,
            hitTestTeamTabs = function() end,
        },
        CharacterPanel = { setActiveTeam = function() end },
        hitTestRosterCard = function() end,
        getTeamSlots = function() return slots end,
        getSlotPowerCache = function() return power end,
        getDragState = function() return drag end,
        getSelectSlotState = function() return { active = false } end,
        getTeams = function() return { { slots = slots } } end,
        getTeamPowerCaches = function() return { power } end,
        getHeroRoster = function() return {} end,
        getShardMap = function() return {} end,
        getActiveTeamIdx = function() return 1 end,
        getOnTeamChanged = function() return function() updates = updates + 1 end end,
        deployHeroToSlot = function() end,
        rebuildRoster = function() end,
        refreshPowerCache = function() end,
        refreshNavBadge = function() end,
        isHeroDeployed = function() return false end,
        isInScrollArea = function() return false end,
        clampScroll = function() end,
        getScroll = function() return 0 end,
        setScroll = function() end,
        getIsDragging = function() return false end,
        setIsDragging = function() end,
        getDragLastY = function() return 0 end,
        setDragLastY = function() end,
        getDragDeltaY = function() return 0 end,
        setDragDeltaY = function() end,
        setScrollVelocity = function() end,
        SCROLL_WHEEL_STEP = 60,
        HC = {},
    })
    drag.active, drag.fromSlot, drag.fromTeam, drag.heroId = true, 1, 1, 1
    api.handleInput(0, 258)
    eq(slots[1].heroId, 1, "拖出头像到队伍页签不能卸下")
    eq(updates, 0, "取消拖放不触发阵容更新")
    drag.active, drag.fromSlot, drag.fromTeam, drag.heroId = true, 1, 1, 1
    api.handleInput(2, 500)
    eq(slots[1].heroId, 2, "交换后第一个槽位")
    eq(slots[2].heroId, 1, "交换后第二个槽位")
    eq(power[1], 20, "交换后第一个战力缓存")
    eq(power[2], 10, "交换后第二个战力缓存")
    eq(updates, 1, "交换通知一次")

    local defs = require("config.ResourceDefs").DEFS
    eq(type(defs.sweep_ticket.iconPath), "string", "扫荡券注册了图标")
    local PDM = require("rules.character.PlayerDataManager")
    local OfflineCalc = require("systems.OfflineCalc")
    local StageProvider = require("shared.StageProvider")
    local oldGetModule, oldMarkDirty = PDM.GetModule, PDM.MarkDirty
    local oldGetStageConfig = StageProvider.Get
    local oldResolve = OfflineCalc.resolveIdleStageAnchors
    local oldCalc = OfflineCalc.calcOfflineIdleRewards
    local session = { lastOnlineTime = os.time() - 7200, firstLoginTime = os.time() - 86400 }
    local battle = { lastIdleClaimTime = session.lastOnlineTime }
    local heroData = { deployed = {} }
    local playerData = {}
    PDM.GetModule = function(_, name)
        return ({ session = session, battle = battle, heroes = heroData, player = playerData })[name]
    end
    PDM.MarkDirty = function() end
    StageProvider.Get = function() return {} end
    OfflineCalc.resolveIdleStageAnchors = function() return 101, 101 end
    OfflineCalc.calcOfflineIdleRewards = function()
        return {
            seconds = 7200, kills = 10, adventureExp = 0, adventurerExp = 0,
            gold = 0, scrollDrops = { sweepTicket = 2 }, equipSeeds = {},
        }
    end
    local reward = require("rules.offline.OfflineService").CalcOnEnter(99901)
    eq(reward.rewards[1].type, "sweep_ticket", "离线扫荡券使用资源注册类型")
    eq(reward.rewards[1].amount, 2, "离线扫荡券数量保留")
    eq(type(defs[reward.rewards[1].type].iconPath), "string", "离线奖励图标能够按类型解析")
    PDM.GetModule, PDM.MarkDirty = oldGetModule, oldMarkDirty
    StageProvider.Get = oldGetStageConfig
    OfflineCalc.resolveIdleStageAnchors = oldResolve
    OfflineCalc.calcOfflineIdleRewards = oldCalc
    battleScene.getStageId, battleScene.getMaxStageId, battleScene.gotoStage =
        oldGetStageId, oldGetMaxStageId, oldGotoStage
    time = oldTime
    print("[chapter_team_offline_test] 选关、编队与图标回归通过")
end
