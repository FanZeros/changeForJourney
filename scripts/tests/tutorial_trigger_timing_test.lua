-- 真实教程触发调度回归：剧情/领奖/招募与安静窗口、队列去重、古树后续对话。
function Start()
    local nativeRequire = require
    local story, reward, blocked, busy = false, false, false, false
    local leaves, prepared, persisted, talentCloses = 0, 0, 0, 0
    local talentOpen = false
    local data = { session = { claimedScenarios = {}, tutorialProgress = { version = 1, completed = {} } },
        heroes = { roster = { [1] = { level = 10 } } } }
    local mocks = {
        ["ui.story.ScenarioDialogue"] = { isActive = function() return story end },
        ["ui.hud.popup.RewardPopup"] = { isOpen = function() return reward end },
        ["ui.tavern.TavernPage"] = { isRecruitBusy = function() return busy end },
        ["ui.church.talent.TalentPage"] = { isOpen = function() return talentOpen end,
            close = function() talentOpen = false; talentCloses = talentCloses + 1 end },
        ["ui.hud.BottomNav"] = { setTabLocked = function() end },
        ["ui.tutorial.TutorialPageRecovery"] = { isBlocked = function() return blocked end,
            prepare = function() prepared = prepared + 1; return false end },
        ["systems.StoryPlayer"] = { followOf = function(id) return id == 23 and 24 or nil end,
            onPlace = function(place, phase)
                if place == "church" and phase == "leave" then
                    assert(not talentOpen, "古树目标页必须先关闭再排离场剧情")
                    leaves = leaves + 1
                end
            end },
    }
    require = function(name) return mocks[name] or nativeRequire(name) end
    local TM = nativeRequire("systems.TutorialManager")
    local store = { Get = function(key) return data[key] end }
    local count = 0
    local function check(value, label) count = count + 1; assert(value, label) end
    local function reset()
        story, reward, blocked, busy, talentOpen = false, false, false, false, false
        data.session = { claimedScenarios = {}, tutorialProgress = { version = 1, completed = {} } }
        TM.init({}, store, function(progress) data.session.tutorialProgress = progress; persisted = persisted + 1 end)
        TM.update(0)
    end
    local function stop() TM.skipCurrentGroup(); TM.update(0.3) end
    local ok, err = pcall(function()
        reset(); story = true
        TM.onScenarioClaimed(5)
        check(not TM.isActive() and #TM.getProgress().queue == 1, "剧情领取只登记待触发教程")
        TM.update(10)
        check(not TM.isActive() and prepared == 0, "剧情活跃不启动或清页面")
        story = false; reward = true; TM.update(10)
        check(not TM.isActive(), "奖励窗口未关闭不触发")
        reward = false; blocked = true; TM.update(10)
        check(not TM.isActive(), "离线标题更新战斗等高优先级窗口不触发")
        blocked = false; busy = true; TM.update(10)
        check(not TM.isActive(), "招募确认请求动画未结束不触发")
        busy = false; TM.update(0.15)
        check(not TM.isActive(), "等待0.25秒安静窗口，不立刻抢输入")
        blocked = true; TM.update(1); blocked = false
        TM.update(0.15)
        check(not TM.isActive(), "等待期间新窗口重新计时")
        TM.update(0.11)
        check(TM.getCurrentGroup() == 1, "连续安静后启动原待触发教程")
        check(not TM.canPlayPendingStory(), "活动操作教学不让新普通剧情插队")
        TM.onScenarioClaimed(8); TM.onScenarioClaimed(8)
        check(#TM.getProgress().queue == 1 and TM.getProgress().queue[1] == 2,
            "后续教程排队去重，不覆盖当前")
        TM.skipCurrentGroup()
        check(not TM.canPlayPendingStory() and TM.isActive(), "淡出期间不让剧情插队")
        TM.update(0.2)
        check(not TM.canPlayPendingStory() and not TM.isActive(), "已释放当前组但queue未空仍不允许剧情")
        reward = true; TM.update(1)
        check(not TM.isActive() and #TM.getProgress().queue == 1, "queued教程仍等奖励结束")
        reward = false; TM.update(0.25)
        check(TM.getCurrentGroup() == 2, "queue仍按顺序触发")

        reset(); TM.onScenarioClaimed(23); TM.update(1)
        check(not TM.isActive() and #TM.getProgress().queue == 0,
            "城镇23有未播放分支24时不提前教堂引导")
        data.session.claimedScenarios["24"] = true
        TM.onScenarioClaimed(24); TM.update(0.25)
        check(TM.getCurrentGroup() == 5, "本角色教堂分支完成后触发组5")
        reset(); data.session.claimedScenarios[24] = true
        TM.onScenarioClaimed(23); TM.update(0.25)
        check(TM.getCurrentGroup() == 5, "旧档分支已播放保留23兼容触发")

        data.session.tutorialProgress = { version = 1, completed = { ["6"] = true }, queue = {} }
        local restoredLeaves = leaves
        TM.init({}, store, function(progress) data.session.tutorialProgress = progress end)
        TM.update(0)
        check(leaves == restoredLeaves + 1 and not TM.isActive(),
            "完成古树后立即退出重启，补回尚未播放的教堂离场剧情")
        TM.update(1)
        check(leaves == restoredLeaves + 1, "离场恢复只初始化补一次，不每帧排队")
        reset(); TM.startGroup(6); talentOpen = true
        TM.notifyEvent("click_highlight"); TM.update(0.6)
        check(TM.getCurrentHighlight() == "talent_node_area", "古树打开后进入学习节点步骤")
        TM.registerHotspot("talent_node_area", 100, 100, 80, 80, "left")
        check(not TM.handleClick(100, 100, "left"), "节点点击仍放行真实天赋页面处理")
        TM.notifyEvent("click_highlight")
        check(TM.getCurrentHighlight() == "talent_node_area" and not TM.isGroupCompleted(6),
            "节点点击或通用高亮事件不冒充天赋学习成功")
        local learnedLeaves, learnedCloses = leaves, talentCloses
        TM.notifyEvent("talent_learned"); TM.notifyEvent("talent_learned")
        check(TM.isGroupCompleted(6) and not talentOpen and talentCloses == learnedCloses + 1,
            "真实talent_learned才完成古树组并关闭一次目标页")
        check(leaves == learnedLeaves + 1, "重复学习成功通知不重复排离场剧情")
        reset(); TM.startGroup(6); talentOpen = true
        local before, beforeCloses = leaves, talentCloses
        TM.skipCurrentGroup(); TM.skipCurrentGroup()
        check(leaves == before + 1 and TM.isGroupCompleted(6), "古树完成或跳过只补一次教堂离场剧情")
        check(not talentOpen and talentCloses == beforeCloses + 1, "古树目标页只关闭一次")
        check(not TM.canPlayPendingStory(), "古树淡出期间仍不允许离场剧情抢输入")
        TM.update(0.19)
        check(TM.isActive() and not TM.canPlayPendingStory(), "0.2秒淡出未满仍持有教程")
        TM.update(0.01)
        check(not TM.isActive(), "古树结束释放引导，不自动伪造酒馆完成")
        check(TM.canPlayPendingStory() and #TM.getProgress().queue == 0,
            "淡出完成且queue为空才允许离场剧情")
        TM.onScenarioClaimed(28); TM.update(0.25)
        check(TM.getCurrentGroup() == 7, "真实离场对话领取后才触发去酒馆组")

        reset(); reward = true; TM.onScenarioClaimed(31)
        local queued = data.session.tutorialProgress
        TM.init({}, store, function(progress) data.session.tutorialProgress = progress end)
        TM.update(1)
        check(not TM.isActive() and #TM.getProgress().queue == 1,
            "排队触发进度读档仍等待领奖")
        reward = false; TM.update(0.25)
        check(TM.getCurrentGroup() == 8 and queued.queue[1] == 8, "恢复queue不丢触发且不重复领取")
        reset(); TM.onScenarioClaimed(31)
        TM.notifyEvent("gacha10_complete")
        check(not TM.isGroupCompleted(8) and #TM.getProgress().queue == 1,
            "孤立完成事件不冒充真实十连")
        TM.notifyEvent("gacha10_started"); TM.notifyEvent("gacha10_failed")
        TM.notifyEvent("gacha10_complete")
        check(not TM.isGroupCompleted(8), "失败后的完成事件不误消费教学")
        TM.notifyEvent("gacha10_started"); TM.setNewHeroId(1)
        TM.notifyEvent("gacha10_complete")
        check(TM.isGroupCompleted(8) and #TM.getProgress().queue == 0 and not TM.isActive(),
            "等待触发期间真实十连完成不要求再次消费招募券")
        TM.update(1)
        check(not TM.isActive(), "已完成queued十连不再启动")
        mocks["ui.character.panel.CharacterPanel"] = {
            getTeamSlotLayout = function(teamIdx) return teamIdx == 1 and { 0, 0, 0, 1 } or {} end,
            getTeamSlotsData = function() return { {}, {}, {}, { state = "occupied", heroId = 1 } } end,
            isOwned = function() return true end,
            isHeroesDataApplied = function() return true end,
        }
        TM.onScenarioClaimed(32); TM.update(0.25)
        check(TM.isGroupCompleted(9) and not TM.isActive(), "新角色已在队一第四槽时免重复拖放")
        mocks["ui.character.panel.CharacterPanel"].getTeamSlotLayout = function() return { 0, 0, 0, 0 } end
        mocks["ui.character.panel.CharacterPanel"].getTeamSlotsData = function()
            return { { state = "empty" }, { state = "empty" }, { state = "empty" }, { state = "empty" } }
        end
        reset(); TM.setNewHeroId(1); TM.onScenarioClaimed(32); TM.update(0.25)
        check(TM.getCurrentGroup() == 9, "角色存在但未在目标槽时仍正常上阵教学")

        -- 只读取CMH两个相邻完整helper；不加载整CMH/主入口，不接真实PlayerStore或存档。
        local file = assert(cache:GetFile("runtime/ClientMessageHandler.lua"), "CMH source unavailable")
        local lines = {}; while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        local source = table.concat(lines, "\n")
        local first = assert(source:find(" local function isTalentNodeLit(", 1, true))
        local last = assert(source:find("\n --- 操作结果", first, true))
        for _, mode in ipairs({"immediate", "delayed", "timeout", "reset_all", "deactivate"}) do
            reset(); TM.startGroup(6); TM.notifyEvent("click_highlight"); talentOpen = true
            local talents = { litNodes = mode == "immediate" and {0, 12} or {0} }
            local wait = {} ---@type any
            local refreshes, learned = 0, 0
            local env = { tonumber = tonumber, ipairs = ipairs, pairs = pairs, pcall = pcall,
                print = function() end, tostring = tostring, ChurchPage = false,
                TalentPage = { syncTalentFromStore = function() refreshes = refreshes + 1 end },
                PlayerStore = { Get = function(key) assert(key == "talents"); return talents end,
                    WaitForChange = function(key, opts) assert(key == "talents"); wait = opts end },
                TutorialManager = { notifyEvent = function(name)
                    assert(name == "talent_learned"); learned = learned + 1; TM.notifyEvent(name)
                end } }
            local chunk = assert(load(source:sub(first, last - 1) .. "\nreturn finishTalentActionWhenSynced",
                "@runtime/ClientMessageHandler.lua", "t", env))
            local finishAction = chunk()
            finishAction({mode = (mode == "reset_all" or mode == "deactivate") and mode or "activate", nodeId = 12})
            if mode == "delayed" or mode == "timeout" then
                check(wait.timeout == 5 and refreshes == 0 and learned == 0,
                    "未同步激活只等待，不刷新或完成 " .. mode)
                check(not wait.compare(talents, talents) and not wait.compare(talents, {litNodes = {0, 13}}),
                    "等待拒绝原引用或非目标节点")
                local synced = {litNodes = {0, 12}}
                check(wait.compare(talents, synced), "等待识别目标节点已同步")
                talents = synced
                if mode == "delayed" then wait.onChange() else wait.onTimeout() end
            else check(next(wait) == nil, "已同步操作不注册等待 " .. mode) end
            local success = mode == "immediate" or mode == "delayed"
            check(refreshes == 1 and learned == (success and 1 or 0),
                "CMH仅成功同步激活通知学习，超时/重置只刷新 " .. mode)
            check(TM.isGroupCompleted(6) == success,
                "CMH真实helper完成状态符合操作结果 " .. mode)
        end

        check(persisted > 0, "待触发queue已经持久化")
        print("[tutorial_trigger_timing_test] ALL PASS: " .. count .. " assertions")
    end)
    require = nativeRequire
    if not ok then print("[tutorial_trigger_timing_test] FAIL: " .. tostring(err)) end
    engine:Exit()
end
