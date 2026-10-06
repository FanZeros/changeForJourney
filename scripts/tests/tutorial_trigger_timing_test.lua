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

        check(persisted > 0, "待触发queue已经持久化")
        print("[tutorial_trigger_timing_test] ALL PASS: " .. count .. " assertions")
    end)
    require = nativeRequire
    if not ok then print("[tutorial_trigger_timing_test] FAIL: " .. tostring(err)) end
    engine:Exit()
end
