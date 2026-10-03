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
    }
    for _, path in ipairs(paths) do view(path) end
    mods["ui.story.gate.IntroCutscene"].isActive = mods["ui.story.gate.IntroCutscene"].isOpen
    mods["ui.tower.TowerBattleScene"].isActive = mods["ui.tower.TowerBattleScene"].isOpen
    local story, busy, team, nav, hero, filter = false, false, 1, 3, nil, nil
    mods["ui.story.ScenarioDialogue"] = { isActive = function() return story end }
    mods["ui.hud.BottomNav"] = { setTabLocked = function() end,
        setSelectedIndex = function(index) nav = index end, getSelectedIndex = function() return nav end }
    mods["ui.town.TownScene"] = { cancelPendingPageOpen = function() pendingCancelled = pendingCancelled + 1 end }
    mods["ui.character.panel.CharacterPanel"] = {
        getTeamSlotsData = function() return { { state = "occupied", heroId = 1 } } end,
        getActiveTeamIdx = function() return team end,
        prepareTutorial = function() team = 1; prepares = prepares + 1 end,
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
    local data = { session = { claimedScenarios = {} }, heroes = { deployed = { 1 }, roster = { [1] = { level = 100 } } },
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
        hotspot("character_slot_1")
        check(not TM.canPointerStart(300, 200) and not bagState.open, "按下前发现覆盖页先清场，不误推进")
        check(TM.getCurrentHighlight() == "character_slot_1", "恢复页面不改变步骤")
        tick(0.5); hotspot("character_slot_1")
        check(TM.canPointerStart(300, 200), "清场动画后目标可点击")
        TM.handleScreenClick(300, 200)
        tick(0.01)
        check(detailState.open and detailState.tab == "equip" and hero == 1 and bagState.open,
            "换步自动打开首槽角色配装及仓库")
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
        check(nav == 5 and TM.getCurrentHighlight() == "dungeon_gold_mine", "恢复黄金矿洞列表而非隐藏旧页签")

        for _, path in ipairs({ "ui.hud.popup.RewardPopup", "ui.hud.popup.OfflineRewardPanel",
            "ui.hud.popup.UpdateNoticePopup", "ui.hud.popup.LevelUpPopup", "ui.story.gate.DarkTitleScreenGate",
            "ui.story.gate.LetterIntro", "ui.story.gate.IntroCutscene", "ui.dungeon.DungeonBattleScene",
            "ui.tower.TowerBattleScene" }) do
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
        check(actions == 0, "全部恢复路径不发送穿戴招募领奖动作")
        print("[tutorial_page_recovery_test] ALL PASS: " .. count .. " assertions")
    end)
    require, time = nativeRequire, nativeTime
    if not ok then print("[tutorial_page_recovery_test] FAIL: " .. tostring(err)) end
    engine:Exit()
end
