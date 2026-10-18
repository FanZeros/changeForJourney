-- 真实引导管理器+页面恢复器：内存页面与时钟，不读写玩家存档或发送业务动作。
function Start()
    local nativeRequire, nativeTime = require, time
    local clock = { elapsedTime = 100 }
    time = clock
    local mods, views = {}, {}
    local count, prepares, actions, pendingCancelled = 0, 0, 0, 0
    local function check(value, message) count = count + 1; assert(value, message) end
    local function view(name)
        local state = { open = false, tab = "", opens = 0, closes = 0, closeTime = 0 }
        local api = {
            isOpen = function() return state.open end,
            open = function(_, tab)
                state.open, state.closeTime, state.opens = true, 0, state.opens + 1
                state.tab = tab or state.tab
            end,
            forceClose = function() state.open = false; state.closes = state.closes + 1 end,
            getSeamAnim = function() return 100, state.closeTime, 0.3, 0.3 end,
        }
        views[name], mods[name] = state, api
        return api, state
    end
    local paths = {
        "ui.church.ChurchPage", "ui.church.talent.TalentPage", "ui.tavern.TavernPage",
        "ui.market.MarketPage", "ui.loot.LootBoxPage", "ui.story.task.TaskPage",
        "ui.blacksmith.BlacksmithPage", "ui.backpack.BackpackPanel",
        "ui.character.detail.CharacterDetail", "ui.character.equip.EquipmentDetail",
        "ui.hud.popup.PlayerInfoPanel", "ui.hud.popup.RewardPopup", "ui.hud.popup.OfflineRewardPanel",
        "ui.hud.popup.UpdateNoticePopup", "ui.hud.popup.LevelUpPopup",
        "ui.story.gate.DarkTitleScreenGate", "ui.story.gate.LetterIntro",
        "ui.story.gate.IntroCutscene", "ui.dungeon.DungeonBattleScene", "ui.tower.TowerBattleScene",
        "ui.battle.stage.SweepDialog", "ui.battle.popup.DamageStatsPanel",
        "ui.battle.stage.StageSelectDialog", "ui.battle.popup.TerminalConfirmDialog",
        "ui.battle.tri.BattleTriPage",
    }
    for _, path in ipairs(paths) do view(path) end
    mods["ui.story.gate.IntroCutscene"].isActive = mods["ui.story.gate.IntroCutscene"].isOpen
    mods["ui.tower.TowerBattleScene"].isActive = mods["ui.tower.TowerBattleScene"].isOpen
    mods["ui.battle.tri.BattleTriPage"].getTeamStageId = function() return 101 end
    mods["config.DungeonConfig"] = { decodeStageId = function(id)
        assert(id == 101, "本恢复专项仅使用小队1主线101的显式读回")
        return nil
    end }
    local dialog = mods["ui.battle.stage.StageSelectDialog"]
    local dialogState = views["ui.battle.stage.StageSelectDialog"]
    dialog.prepareTutorial = function()
        local changed = not dialogState.open or dialogState.tab ~= "gold_mine"
        if changed then dialog.open(); dialogState.tab = "gold_mine" end
        return changed
    end
    local story, busy, team, nav, hero, filter = false, false, 1, 3, nil, nil
    mods["ui.story.ScenarioDialogue"] = { isActive = function() return story end }
    mods["systems.StoryPlayer"] = { onPlace = function() end }
    mods["ui.hud.BottomNav"] = { setTabLocked = function() end,
        setSelectedIndex = function(index) nav = index end, getSelectedIndex = function() return nav end }
    mods["ui.town.TownScene"] = { cancelPendingPageOpen = function() pendingCancelled = pendingCancelled + 1 end }
    mods["ui.character.panel.CharacterPanel"] = {
        getTeamSlotsData = function() return { { state = "occupied", heroId = 1 } } end,
        getActiveTeamIdx = function() return team end,
        prepareTutorial = function() local changed = team ~= 1; team = 1; prepares = prepares + 1; return changed end,
    }
    local detail = mods["ui.character.detail.CharacterDetail"]
    local detailState = views["ui.character.detail.CharacterDetail"]
    detail.isEquipTab = function() return detailState.tab == "equip" end
    detail.getHeroId = function() return hero end
    detail.open = function(id, tab)
        hero = id; detailState.open, detailState.closeTime, detailState.tab = true, 0, tab
        detailState.opens = detailState.opens + 1
    end
    local bag = mods["ui.backpack.BackpackPanel"]
    local bagState = views["ui.backpack.BackpackPanel"]
    bag.ensureTutorialEquipment = function(id, slot)
        local changed = not bagState.open or bagState.tab ~= "equip" or filter ~= slot
        bagState.open, bagState.tab, filter = true, "equip", slot
        return changed
    end
    local tavern, tavernState = mods["ui.tavern.TavernPage"], views["ui.tavern.TavernPage"]
    local confirmOpen = false
    tavern.isRecruitConfirmOpen = function() return confirmOpen end
    tavern.isRecruitBusy = function() return busy or confirmOpen end
    tavern.prepareTutorial = function()
        local changed = not tavernState.open or tavernState.tab ~= "recruit"
        if changed then tavern.open(); tavernState.tab = "recruit" end
        return changed
    end
    local smith, smithState = mods["ui.blacksmith.BlacksmithPage"], views["ui.blacksmith.BlacksmithPage"]
    smith.prepareTutorial = function()
        local changed = not smithState.open or smithState.tab ~= "qianghua"
        if changed then smith.open(); smithState.tab = "qianghua"; bagState.open = true end
        return changed
    end
    local talent = mods["ui.church.talent.TalentPage"]
    talent.init = function() end
    mods["runtime.GameAction"] = { sendAction = function() actions = actions + 1 end }
    require = function(name) return mods[name] or nativeRequire(name) end
    local Recovery = nativeRequire("ui.tutorial.TutorialPageRecovery")
    local TM = nativeRequire("systems.TutorialManager")
    local data = { session = { claimedScenarios = {} }, heroes = { deployed = { 1 }, roster = { [1] = { level = 100 }, [2] = { level = 100 } } },
        equipment = { inventory = {}, equipped = {} } }
    local store = { Get = function(key) return data[key] end }
    local function tick(dt) clock.elapsedTime = clock.elapsedTime + dt; TM.update(dt) end
    local function hotspot(key)
        TM.clearHotspots()
        TM.registerHotspot(key, 300, 200, 100, 80, "right")
        TM.setOverlayRect(960, 540, { cx = 300, cy = 200, w = 100, h = 80 })
    end
    local function reset(group)
        story, busy, team, nav, filter = false, false, 1, 3, nil
        for _, state in pairs(views) do state.open, state.closeTime, state.tab = false, 0, "" end
        data.session.tutorialProgress = { version = 1, completed = {}, group = group, newHeroId = 1 }
        TM.init({}, store, function(progress) data.session.tutorialProgress = progress end)
        tick(0)
    end
    local ok, err = pcall(function()
        for _, target in ipairs({ "town_overview", "building_church", "talent_toggle", "building_tavern", "building_smith" }) do
            for _, path in ipairs(paths) do views[path].open = false end
            for _, path in ipairs({ "ui.market.MarketPage", "ui.loot.LootBoxPage", "ui.story.task.TaskPage",
                "ui.tavern.TavernPage", "ui.blacksmith.BlacksmithPage", "ui.backpack.BackpackPanel" }) do views[path].open = true end
            check(Recovery.prepare({}, store, target, 1, true), "城镇目标清无关页面: " .. target)
            check(not bagState.open and not tavernState.open and not smithState.open
                and not views["ui.loot.LootBoxPage"].open and not views["ui.story.task.TaskPage"].open,
                "即使城镇热点存在，也移除覆盖层: " .. target)
            check(not Recovery.prepare({}, store, target, 1, false), "稳定城镇不反复重置: " .. target)
        end
        reset(1)
        bagState.open = true; bagState.tab = "item"
        hotspot("battle_hero_detail")
        check(not TM.canPointerStart(300, 200) and not bagState.open, "按下前发现覆盖页先清场，不误推进")
        check(TM.getCurrentHighlight() == "battle_hero_detail" and not detailState.open, "恢复战斗入口不自动打开详情或改变步骤")
        tick(0.5); hotspot("battle_hero_detail")
        check(TM.canPointerStart(300, 200), "清场动画后目标可点击")
        TM.registerCharacterDetailHotspot("battle_hero_detail", 2, 300, 200, 100, 80, "screen")
        TM.handleScreenClick(300, 200)
        check(TM.getCurrentHighlight() == "battle_hero_detail", "点高亮不冒充实际详情已打开")
        detail.open(2, "equip")
        check(TM.notifyCharacterDetailOpened("battle", 2), "实际打开目标详情才进入穿戴")
        tick(0.01)
        check(detailState.open and detailState.tab == "equip" and hero == 2 and bagState.open,
            "后续配装保留实际点击英雄，而不是换成首槽角色")
        hotspot("equip_slot_weapon")
        check(not TM.canPointerStart(300, 200), "页面滑入期间不以稳定热点提前点击")
        tick(0.5); hotspot("equip_slot_weapon")
        local beforeStep = TM.getProgress().step
        check(TM.handleScreenClick(300, 200, true) and TM.getProgress().step == beforeStep,
            "滑入期被阻塞的按下，延迟松手不推进引导")
        check(TM.canPointerStart(300, 200), "配装就绪后放行")
        local opens = detailState.opens
        tick(1); tick(1)
        check(detailState.opens == opens, "持续检查不反复open")
        detailState.open = false
        tick(0.5)
        check(detailState.open and detailState.opens == opens + 1, "Esc关闭配装后自动重开")
        tick(0.5); hotspot("equip_slot_weapon"); TM.handleScreenClick(300, 200); tick(0.01)
        check(filter == "weapon", "仓库武器步骤自动恢复对应部位")
        bagState.open = false; bagState.tab = "item"
        tick(0.5)
        check(bagState.open and bagState.tab == "equip" and filter == "weapon", "关仓库/切道具后恢复装备候选页")
        check(not TM.isGroupCompleted(1), "自动整理页面不伪造穿戴成功")

        reset(6); tick(0.5); hotspot("talent_toggle"); TM.handleScreenClick(300, 200); tick(0.01)
        check(views["ui.church.talent.TalentPage"].open and TM.getCurrentHighlight() == "talent_node_area",
            "点古树换步即开节点页，不依赖延迟回调")
        local cancellations = pendingCancelled
        tick(1)
        check(pendingCancelled == cancellations, "旧建筑回调仅进入步骤时取消，不每帧清理")

        reset(8); tick(0.5)
        check(tavernState.open and tavernState.tab == "recruit", "正常启动十连组保证招募页")
        reset(8); tick(0.5)
        confirmOpen = true
        local confirmOpens = tavernState.opens
        tick(1)
        check(not TM.isInputActive() and tavernState.opens == confirmOpens and confirmOpen,
            "补券确认让位输入且不重置招募页")
        confirmOpen = false
        check(TM.isInputActive(), "补券确认关闭后引导恢复")
        tavernState.tab = "shop"; tick(0.5)
        check(tavernState.tab == "recruit", "商店切页后恢复招募")
        TM.notifyEvent("gacha10_started"); busy = true
        local busyOpens = tavernState.opens
        tick(1)
        check(tavernState.opens == busyOpens and TM.getCurrentHighlight() == nil, "招募请求/隐形等待不中断或重开")
        busy = false; TM.notifyEvent("gacha10_failed"); tick(0.1)
        check(TM.getCurrentHighlight() == "tavern_btn_gacha10", "真实失败仍可重试")

        reset(11); tick(0.5)
        check(smithState.open and smithState.tab == "qianghua", "正常启动升阶组保证升阶页")
        smithState.tab = "xilian"; tick(0.5)
        check(smithState.tab == "qianghua", "洗练切走可恢复升阶")
        reset(15)
        check(nav == 3 and views["ui.battle.tri.BattleTriPage"].open and dialogState.open
            and dialogState.tab == "gold_mine" and TM.getCurrentHighlight() == "dungeon_gold_mine",
            "恢复三队页及黄金矿洞选关列表，而非旧副本页签")

        for _, path in ipairs({ "ui.hud.popup.RewardPopup", "ui.hud.popup.OfflineRewardPanel",
            "ui.hud.popup.UpdateNoticePopup", "ui.hud.popup.LevelUpPopup", "ui.story.gate.DarkTitleScreenGate",
            "ui.story.gate.LetterIntro", "ui.story.gate.IntroCutscene", "ui.dungeon.DungeonBattleScene",
            "ui.tower.TowerBattleScene", "ui.battle.stage.SweepDialog", "ui.battle.popup.DamageStatsPanel",
            "ui.battle.stage.StageSelectDialog", "ui.battle.popup.TerminalConfirmDialog" }) do
            reset(8); views[path].open = true
            local before = tavernState.opens
            tick(1)
            check(not TM.isInputActive() and tavernState.opens == before and views[path].open,
                "高优先级窗口不抢页面或关闭: " .. path)
            views[path].open = false; tick(0.5)
            check(tavernState.open, "窗口结束后自动恢复: " .. path)
        end
        reset(8); tavernState.open = false; story = true; tick(1)
        check(not tavernState.open, "剧情不被页面恢复打断")
        story = false; tick(0.5); check(tavernState.open, "剧情结束恢复")
        local panel = mods["ui.character.panel.CharacterPanel"]
        panel.getOwnedHero = function(id) return data.heroes.roster[id] end
        data.heroes.roster[2] = nil; detailState.open, detailState.tab = false, "attr"
        local beforeOpen = detailState.opens
        Recovery.prepare({}, store, "equip_slot_weapon", 1, false, 2, true)
        check(detailState.opens == beforeOpen and not detailState.open,
            "英雄数据未到不反复打开属性页冒充配装恢复")
        data.heroes.roster[2] = { level = 100 }
        Recovery.prepare({}, store, "equip_slot_weapon", 1, false, 2, true)
        check(detailState.open and detailState.tab == "equip" and hero == 2,
            "数据晚到后强制打开正确英雄配装，不换成首槽英雄")
        local forcedBag = false
        bag.ensureTutorialEquipment = function(id, slot, force)
            forcedBag = id == 2 and slot == "weapon" and force == true
            return false
        end
        Recovery.prepare({}, store, "equip_item_gifted", 1, false, 2, true)
        check(forcedBag, "强恢复传递真实英雄及武器定位请求到仓库")
        detailState.open = false
        local positioned = false
        panel.prepareTutorial = function(id)
            local changed = not positioned and id == 2
            positioned = positioned or id == 2
            return changed
        end
        check(Recovery.prepare({}, store, "character_new_hero", 2, false, nil, true) and positioned,
            "初次准备之后目标丢失仍能重新定位新增英雄")
        check(not Recovery.prepare({}, store, "character_new_hero", 2, false, nil, true),
            "名册强恢复按实际变化返回，稳定后不重置动画")
        reset(8); tavernState.open = false; tick(3)
        check(tavernState.open and not TM.isGroupCompleted(8) and TM.getCurrentHighlight() == "tavern_btn_gacha10",
            "大dt同帧打开页面后保持教程，不按缺失时长完成组")
        for _, key in ipairs({ "equip_slot_weapon", "equip_item_gifted", "character_new_hero", "talent_node_area",
            "tavern_btn_gacha10", "smith_btn_enhance", "dungeon_gold_mine", "building_church" }) do
            check(Recovery.canRestoreTarget(key), "已知目标有明确恢复路由: " .. key)
        end
        check(not Recovery.canRestoreTarget("building_guild"), "已删除页面不伪造恢复能力")
        story = true; tavernState.open = false
        check(not Recovery.prepare({}, store, "tavern_btn_gacha10", nil, false, nil, true) and not tavernState.open,
            "直接强制恢复入口也不打断高优先级剧情")
        story = false
        local seamOpen = clock.elapsedTime
        smithState.open = true
        smith.getSeamAnim = function() return seamOpen + 0.12, 0, 0.45, 0.38 end
        clock.elapsedTime = seamOpen + 0.5
        check(not Recovery.isTargetReady("smith_btn_enhance"), "锻炉错峰滑入未结束不能把静态热点当成可点击按钮")
        clock.elapsedTime = seamOpen + 0.6
        check(Recovery.isTargetReady("smith_btn_enhance"), "锻炉按实际错峰及动画时长就绪")
        smithState.open = false
        check(not Recovery.isTargetReady("smith_btn_enhance"), "页面关闭后旧热点不能冒充就绪")

        -- 读取正式选关恢复完整函数；视图用内存替身，不执行进关动作。
        local file = assert(cache:GetFile("ui/battle/stage/StageSelectDialog.lua"))
        local lines = {}; while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        local source = table.concat(lines, "\n")
        local prepareSource = assert(source:match("(function StageSelectDialog.prepareTutorial.-)\nfunction StageSelectDialog.close"))
        local allowed, opens = true, 0
        local state = { open = true, view = "overview", section = "dungeon", targetTeam = 1,
            selKey = "R:gold_mine", chScroll = 0, rowScroll = {}, chDragMoved = true, cardDragMoved = true }
        local selector = { openDungeon = function() opens = opens + 1; state.open, state.view = true, "selector" end }
        local env = setmetatable({ state = state, StageSelectDialog = selector,
            teamSelectionAllowed = function() return allowed end, resetCardScroll = function() end }, { __index = _G })
        assert(load(prepareSource, "@正式选关恢复", "t", env))()
        check(selector.prepareTutorial() and state.view == "selector" and opens == 1,
            "总览保留gold字段也强制切回真正的黄金矿洞选关页")
        check(state.chDragMoved and state.cardDragMoved and not selector.prepareTutorial() and opens == 1,
            "选关恢复幂等并保留旧拖拽失效标记")
        allowed = false; state.view = "overview"
        check(not selector.prepareTutorial() and state.view == "overview" and opens == 1,
            "终焉或全局锁拒绝强开，不改视图也不假报成功")
        check(actions == 0, "全部恢复路径不发送穿戴招募领奖动作")
        print("[tutorial_page_recovery_test] ALL PASS: " .. count .. " assertions")
    end)
    require, time = nativeRequire, nativeTime
    if not ok then print("[tutorial_page_recovery_test] FAIL: " .. tostring(err)) end
    engine:Exit()
end
