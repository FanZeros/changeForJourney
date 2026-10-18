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
        TM.update(1.5)
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

        -- 没有恢复路由的旧目标仍可超时退出；已知页面另测强制恢复。
        local recoveryChanged, recoveryBlocked = false, false
        mocks["ui.tutorial.TutorialPageRecovery"].canRestoreTarget = function() return false end
        mocks["ui.tutorial.TutorialPageRecovery"].isBlocked = function() return recoveryBlocked end
        mocks["ui.tutorial.TutorialPageRecovery"].prepare = function(_, _, target)
            calls.target = target
            return recoveryChanged
        end
        local function resetMissing(group)
            story, reward, recoveryChanged, recoveryBlocked = false, false, false, false
            data.session.tutorialProgress = { version = 1, completed = {}, group = group, newHeroId = 1 }
            init()
            TM.setOverlayRect(960, 540, nil)
        end
        resetMissing(10)
        TM.startGroup(11)
        TM.update(1.9)
        check(TM.isActive() and not TM.isGroupCompleted(10), "缺目标两秒前保留准备时间")
        TM.update(0.11)
        check(TM.isGroupCompleted(10) and not TM.isInputActive() and TM.canPointerStart(0, 0),
            "缺目标超时自动跳过并立即释放输入")
        TM.update(0.2)
        check(not TM.isActive() and #TM.getProgress().queue == 1, "超时仅结束当前组，保留后续队列")
        TM.update(0.25)
        check(TM.getCurrentGroup() == 11, "自动跳过后后续引导正常启动")
        TM.skipCurrentGroup(); TM.update(0.3); init()
        check(TM.isGroupCompleted(10) and TM.isGroupCompleted(11) and not TM.isActive(),
            "自动跳过结果持久化，重进不恢复失效引导")
        check(data.session.claimedScenarios["5"] == beforeClaims, "自动跳过不修改已领取剧情奖励")

        resetMissing(10)
        TM.update(1.5); hs("building_smith"); TM.update(0.01)
        check(not TM.isGroupCompleted(10), "准备期内出现目标不会误跳过")
        TM.setOverlayRect(960, 540, nil)
        TM.update(1.5)
        check(not TM.isGroupCompleted(10), "目标短暂消失重新计时，不累计旧缺失时长")
        hs("building_smith"); TM.update(10)
        check(TM.isInputActive() and not TM.isGroupCompleted(10), "可见目标不因停留时间长被跳过")

        resetMissing(10)
        TM.setOverlayRect(960, 540, { cx = -200, cy = -200, w = 40, h = 40 })
        check(not TM.canPointerStart(-200, -200), "屏幕外热点不能放行点击")
        TM.update(2)
        check(TM.isGroupCompleted(10) and not TM.isInputActive(), "完全屏幕外热点视为缺失并自动跳过")
        resetMissing(10)
        TM.setOverlayRect(960, 540, { cx = 0, cy = 200, w = 100, h = 60 })
        TM.update(3)
        check(TM.isInputActive() and not TM.isGroupCompleted(10), "部分可见热点保留正常引导")
        check(TM.canPointerStart(20, 200) and not TM.canPointerStart(-20, 200),
            "部分可见热点只放行屏幕内按钮边界")

        resetMissing(10)
        recoveryChanged = true
        for _ = 1, 4 do TM.update(0.5) end
        check(TM.isGroupCompleted(10) and not TM.isInputActive(),
            "页面持续恢复失败也能超时，不被恢复器无限重置")
        recoveryChanged = false

        for _, blocker in ipairs({ "story", "reward", "page" }) do
            resetMissing(10)
            TM.update(1)
            story, reward, recoveryBlocked = blocker == "story", blocker == "reward", blocker == "page"
            TM.update(10)
            check(not TM.isGroupCompleted(10) and not TM.isInputActive(), "高优先级窗口暂停缺失计时: " .. blocker)
            story, reward, recoveryBlocked = false, false, false
            TM.update(0.9)
            check(not TM.isGroupCompleted(10), "高优先级窗口关闭后保留剩余准备时间: " .. blocker)
            TM.update(0.11)
            check(TM.isGroupCompleted(10), "恢复计时后可自动跳过: " .. blocker)
        end

        resetMissing(1)
        TM.startGroup(2)
        hs("character_slot_1")
        TM.registerCharacterDetailHotspot("character_slot_1", 2, 250, 200, 100, 60, "right")
        TM.update(1.5)
        check(not TM.isGroupCompleted(1), "新步骤拥有独立准备时间")
        TM.handleScreenClick(250, 200)
        TM.update(5)
        check(not TM.isGroupCompleted(1), "可见入口目标等待真实回执，不因操作耗时跳过")
        TM.setOverlayRect(960, 540, nil); TM.update(2)
        check(TM.isGroupCompleted(1), "业务回执步骤缺目标同样自动跳过，不伪造入口成功")

        resetMissing(8)
        TM.notifyEvent("gacha10_started"); TM.update(3)
        check(TM.getCurrentHighlight() == nil and not TM.isGroupCompleted(8),
            "招募隐形等待没有热点也不被两秒超时误跳过")
        TM.update(10)
        check(TM.getCurrentHighlight() == "tavern_btn_gacha10" and not TM.isGroupCompleted(8),
            "招募失联仍沿用原有十二秒重试机制")
        TM.setOverlayRect(960, 540, nil); TM.update(2)
        check(TM.isGroupCompleted(8), "招募入口恢复失败时自动跳过引导")

        local forced, recovered = 0, false
        mocks["ui.tutorial.TutorialPageRecovery"].canRestoreTarget = function() return true end
        mocks["ui.tutorial.TutorialPageRecovery"].prepare = function(_, _, target, _, _, _, force)
            calls.target = target
            if force then forced = forced + 1; return recovered end
            return false
        end
        resetMissing(10); TM.startGroup(11)
        TM.update(1.9)
        check(forced == 0 and not TM.isGroupCompleted(10), "已知目标缺失先正常准备，不提前强制定位")
        TM.update(0.11)
        check(forced == 1 and TM.getCurrentGroup() == 10 and TM.getProgress().step == 1
            and not TM.isGroupCompleted(10) and #TM.getProgress().queue == 1,
            "两秒后强制恢复页面，保留当前步骤和后续队列而非完成组")
        TM.update(2)
        check(forced == 2 and not TM.isGroupCompleted(10), "数据未到允许再次恢复，不永久跳过教学")
        recovered = true; TM.update(2)
        check(TM.isInputActive() and not TM.isGroupCompleted(10), "强制打开成功的同帧不能因旧缺失计时完成")
        TM.update(0.5); hs("building_smith"); TM.update(0.01)
        local beforeForce = forced
        TM.update(10)
        check(forced == beforeForce and not TM.isGroupCompleted(10), "真实热点恢复后不反复强制定位")
        TM.setOverlayRect(960, 540, nil); recovered = false
        TM.update(1); story = true; TM.update(10); story = false; TM.update(0.9)
        check(forced == beforeForce, "剧情期间强制恢复计时暂停")
        TM.update(0.11)
        check(forced == beforeForce + 1 and not TM.isGroupCompleted(10), "让位结束后再恢复，不抢剧情页面")
        TM.skipCurrentGroup(); TM.update(0.3)
        check(TM.isGroupCompleted(10) and #TM.getProgress().queue == 1, "手动跳过仍可释放无法恢复的当前引导")
        check(data.session.claimedScenarios["5"] == beforeClaims, "强制恢复不修改奖励账本")
        resetMissing(8); TM.notifyEvent("gacha10_started"); beforeForce = forced; TM.update(3)
        check(forced == beforeForce and not TM.isGroupCompleted(8), "隐形招募等待不强制打开页面")

        print("[tutorial_manager_flow_test] ALL PASS: " .. count .. " assertions")
    end)
    require = nativeRequire
    if not ok then print("[tutorial_manager_flow_test] FAIL: " .. tostring(err)) end
    engine:Exit()
end
