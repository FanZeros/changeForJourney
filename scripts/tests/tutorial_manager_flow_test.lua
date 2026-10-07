-- 真实TutorialManager状态回归，存档/页面使用内存替身，不写玩家存档。
function Start()
    ---@type fun(name: string): any
    local nativeRequire = require
    local data = { session = { claimedScenarios = {} }, heroes = { roster = { [1] = { level = 1 } } },
        equipment = { equipped = {} }, battle = { maxStageId = 102 } }
    local story, reward = false, false
    local calls = {}
    local mocks = {
        ["ui.story.ScenarioDialogue"] = { isActive = function() return story end },
        ["systems.StoryPlayer"] = { onPlace = function(place, phase) calls.place = place .. ":" .. phase end },
        ["ui.hud.popup.RewardPopup"] = { isOpen = function() return reward end },
        ["ui.hud.BottomNav"] = {
            setTabLocked = function() end,
            setSelectedIndex = function(index) calls.tab = index end,
        },
        ["ui.church.ChurchPage"] = { forceClose = function() calls.church = true end },
        ["ui.church.talent.TalentPage"] = { forceClose = function() end },
        ["ui.character.detail.CharacterDetail"] = { forceClose = function() calls.hero = nil end,
            open = function(id) calls.hero = id end, isOpen = function() return calls.hero ~= nil end,
            getHeroId = function() return calls.hero end, isEquipTab = function() return true end },
        ["ui.character.panel.CharacterPanel"] = { prepareTutorial = function() end,
            getTeamSlotsData = function() return { {}, {}, {}, { state = "empty" } } end,
            getTeamSlotLayout = function() return { 0, 0, 0, 0 } end },
        ["ui.tavern.TavernPage"] = { open = function() calls.tavern = true end },
        ["ui.blacksmith.BlacksmithPage"] = { open = function() calls.smith = true end },
        ["ui.battle.tri.BattleTriPage"] = { getTeamStageId = function() return 101 end },
        ["config.DungeonConfig"] = { decodeStageId = function(id)
            assert(id == 101, "本管理专项仅使用小队1主线101的显式读回")
            return nil
        end },
        ["ui.tutorial.TutorialPageRecovery"] = { isBlocked = function() return false end,
            prepare = function(_, _, target)
                calls.target = target
                if target == "tavern_btn_gacha10" then calls.tavern = true end
                if target == "smith_btn_enhance" then calls.smith = true end
                if target == "dungeon_gold_mine" then calls.tab = 3 end
                return false
            end },
    }
    require = function(name) return mocks[name] or nativeRequire(name) end
    local TM = nativeRequire("systems.TutorialManager")
    local Store = { Get = function(key) return data[key] end }
    local count = 0
    local function check(value, label) count = count + 1; assert(value, label) end
    local function init()
        TM.init({}, Store, function(progress) data.session.tutorialProgress = progress end)
        TM.update(0)
    end
    local function hs(key)
        TM.registerHotspot(key, 250, 200, 100, 60, "right")
        TM.setOverlayRect(960, 540, { cx = 250, cy = 200, w = 100, h = 60 })
    end
    local ok, err = pcall(function()
        init()
        data.session.claimedScenarios["5"] = true
        TM.onScenarioClaimed(5)
        check(not TM.isActive() and #TM.getProgress().queue == 1, "剧情领取只排队，不在回调当帧弹引导")
        TM.update(0.25)
        check(TM.isActive() and not TM.isGroupCompleted(1), "剧情领取不是操作完成")
        check(TM.getPreferredCharacterTab() == "equip", "教程打开详情优先配装")
        hs("battle_hero_detail")
        TM.registerCharacterDetailHotspot("battle_hero_detail", 1, 250, 200, 100, 60, "screen")
        check(TM.canPointerStart(250, 200), "真实目标按下放行")
        check(not TM.canPointerStart(312, 200), "外扩光环不冒充按钮边界")
        check(TM.handleScreenClick(312, 200) == true and TM.getCurrentHighlight() == "battle_hero_detail",
            "点光环但未命中按钮不能提前推进")
        check(TM.handleScreenClick(250, 200) == false and TM.getCurrentHighlight() == "battle_hero_detail",
            "点角色热点只放行，不提前推进")
        TM.notifyEvent("character_detail_opened")
        check(TM.getCurrentHighlight() == "battle_hero_detail", "无来源和英雄的通用事件不冒充入口成功")
        check(not TM.notifyCharacterDetailOpened("battle", 1), "详情未打开不推进")
        mocks["ui.character.detail.CharacterDetail"].open(1)
        check(not TM.notifyCharacterDetailOpened("avatar", 1) and not TM.notifyCharacterDetailOpened("battle", 2),
            "错来源或错英雄不推进")
        check(TM.notifyCharacterDetailOpened("battle", 1) and TM.getCurrentHighlight() == "equip_slot_weapon"
            and TM.getEquipmentHeroId() == 1, "真实战斗卡打开对应详情才进入武器槽")
        check(not TM.notifyCharacterDetailOpened("battle", 1), "重复入口回执不再推进")
        hs("equip_slot_weapon")
        TM.handleScreenClick(250, 200)
        check(TM.getCurrentHighlight() == "equip_item_gifted", "武器槽下一步为合法仓库装备")
        hs("equip_item_gifted")
        TM.handleScreenClick(250, 200)
        check(not TM.isGroupCompleted(1), "点击候选不会假装穿戴成功")
        TM.notifyEvent("equipment_equipped")
        TM.update(0.3)
        check(TM.isGroupCompleted(1) and not TM.isActive(), "成功穿戴回执完成教程")
        init()
        check(TM.isGroupCompleted(1) and not TM.isActive(), "重启保留完成状态，不重复发奖励")
        TM.startGroup(2)
        hs("character_slot_1")
        TM.registerCharacterDetailHotspot("character_slot_1", 2, 250, 200, 100, 60, "right")
        TM.handleScreenClick(250, 200)
        check(TM.getCurrentHighlight() == "character_slot_1" and TM.getEquipmentHeroId() == nil,
            "第二段头像入口独立等待，旧组英雄不串入")
        mocks["ui.character.detail.CharacterDetail"].open(2)
        check(TM.notifyCharacterDetailOpened("avatar", 2) and TM.getCurrentHighlight() == "equip_btn_auto",
            "真实队伍头像打开详情才开始一键装备")
        TM.notifyEvent("equipment_equipped"); TM.update(0.3)
        check(TM.isGroupCompleted(2), "第二段仍以穿戴成功回执完成")

        TM.startGroup(8)
        check(TM.getCurrentHighlight() == "tavern_btn_gacha10", "招募初始目标")
        TM.handleScreenClick(250, 200)
        check(TM.getCurrentHighlight() == "tavern_btn_gacha10", "未实际发出请求不进入等待")
        TM.notifyEvent("gacha10_started")
        check(TM.getCurrentHighlight() == nil, "实际请求开始后进入隐形等待")
        TM.notifyEvent("gacha10_failed")
        check(TM.getCurrentHighlight() == "tavern_btn_gacha10", "失败可重试")
        TM.notifyEvent("gacha10_started")
        TM.update(13)
        check(TM.getCurrentHighlight() == "tavern_btn_gacha10", "失联兜底恢复招募目标")
        init()
        TM.update(0.1)
        check(TM.getCurrentGroup() == 8 and calls.tavern, "中断重进恢复招募入口")
        TM.notifyEvent("gacha10_started")
        TM.setNewHeroId(nil)
        TM.notifyEvent("gacha10_complete")
        TM.onScenarioClaimed(32)
        TM.update(0.3)
        TM.update(0.25)
        check(TM.isGroupCompleted(9) and not TM.isActive(), "全重复招募无新角色不死等拖拽")

        TM.startGroup(10)
        TM.update(2)
        TM.clearHotspots()
        TM.setOverlayRect(960, 540, nil)
        local layout = nativeRequire("ui.tutorial.TutorialOverlay").layout(960, 540, nil)
        check(TM.handleScreenClick(layout.skip.cx, layout.skip.cy), "缺热点时跳过仍可点")
        TM.update(0.3)
        check(not TM.isActive(), "跳过后释放引导")
        TM.startGroup(11)
        hs("smith_btn_enhance")
        story = true
        check(not TM.isInputActive() and TM.canPointerStart(0, 0), "剧情期间绘制/输入共同让位")
        story, reward = false, true
        check(TM.handleScreenClick(0, 0) == false, "领奖窗口不被隐藏教程拦住")
        reward = false
        check(TM.handleScreenClick(0, 0) == true, "领奖关闭后恢复目标限制")
        check(TM.isBuildingUnlocked("church") and not TM.isBuildingUnlocked("smith"), "原建筑解锁保持")
        data.battle.clearedStages = { [204] = true }
        check(TM.isBuildingUnlocked("smith"), "兼容数字键首通解锁")
        TM.skipCurrentGroup()
        TM.update(0.3)
        TM.startGroup(15)
        TM.update(0.1)
        check(calls.tab == 3 and TM.getCurrentHighlight() == "dungeon_gold_mine",
            "横屏恢复三队页的黄金矿洞选关入口，不返回旧副本页签")
        TM.skipCurrentGroup()
        TM.update(0.3)

        -- 对每个未完成组恢复到合法入口，队列不会覆盖正在进行的引导。
        for _, id in ipairs({ 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 15 }) do
            data.session.tutorialProgress = { version = 1, completed = {}, group = id, step = 2, newHeroId = 1 }
            init()
            check(TM.getCurrentGroup() == id, "恢复引导组: " .. id)
            TM.update(0.1)
            check(TM.getProgress().step == (id == 15 and 2 or 1), "恢复入口而非失效中途界面: " .. id)
        end
        TM.startGroup(7)
        TM.startGroup(7)
        check(#TM.getProgress().queue == 1, "后续引导排队去重，不覆盖当前组")
        local beforeClaims = data.session.claimedScenarios["5"]
        init()
        check(#TM.getProgress().queue == 1 and data.session.claimedScenarios["5"] == beforeClaims,
            "队列恢复不改剧情领取账本")
        print("[tutorial_manager_flow_test] ALL PASS: " .. count .. " assertions")
    end)
    require = nativeRequire
    if not ok then print("[tutorial_manager_flow_test] FAIL: " .. tostring(err)) end
    engine:Exit()
end
