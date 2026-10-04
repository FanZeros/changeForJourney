-- 真实 ClientMessageHandler 情景领取时机回归；页面/通知出口用 require 拦截。
-- 不加载 Standalone，不写玩家存档，不发送业务动作，不替代 Follow23->24 等专门调度测试。
-- Runtime: tests/tutorial_claim_timing_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
-- 新契约：成功回执通知一次并由真实 TM 持久化入队；奖励窗口关闭后经 TM 安静期才启动。
-- 奖励页替身只模拟 show 保留 onClose、关闭完成时清空并调用一次的接口契约；
-- 不在 show/close 开始时自动通知，不测试 RewardPopup 的渲染或动画实现。

function Start()
    local nativeRequire = require
    local prefix = "[tutorial_claim_timing_test] "
    local checks, failures, sentActions = 0, 0, 0
    local phase = "idle"
    ---@type table[]
    local notifications = {}
    ---@type table[]
    local popups = {}
    ---@type table<string, number>
    local requireHits = {}
    ---@type table<string, table[]>
    local pageResults = {}
    ---@type table<string, any>
    local mocks = {}
    ---@type table<string, any>
    local loaded = {}

    local function check(value, label)
        checks = checks + 1
        if value then print(prefix .. "PASS " .. label)
        else
            failures = failures + 1
            print(prefix .. "FAIL " .. label)
        end
    end
    local function eq(actual, expected, label)
        check(actual == expected, label .. " (actual=" .. tostring(actual) .. ", expected=" .. tostring(expected) .. ")")
    end

    -- Spy 仅记录并转发给真实 TM，绝不自行排队/去重/启动。
    local data = { session = { tutorialProgress = { version = 1, completed = {}, queue = {} } },
        heroes = { roster = { [1] = { level = 1 } } }, equipment = { equipped = {} } }
    local store = { Get = function(key) return data[key] end }
    local persistCount = 0
    mocks["ui.hud.popup.RewardPopup"] = {
        isOpen = function()
            for _, popup in ipairs(popups) do if popup.open then return true end end
            return false
        end,
        show = function(title, rewards, opts)
            popups[#popups + 1] = {
                title = title, rewards = rewards, opts = opts or {}, open = true, closing = false,
            }
        end,
    }
    mocks["ui.story.ScenarioDialogue"] = { isActive = function() return false end }
    mocks["ui.hud.BottomNav"] = { setTabLocked = function() end }
    mocks["ui.tutorial.TutorialPageRecovery"] = {
        isBlocked = function() return false end, prepare = function() return false end,
    }
    local pages = {
        "ui.loot.LootBox", "ui.loot.LootBoxPage", "ui.blacksmith.BlacksmithPage",
        "ui.backpack.BackpackPanel", "ui.church.ChurchPage", "ui.church.talent.TalentPage",
        "ui.tavern.TavernPage", "ui.market.MarketPage", "ui.dungeon.DungeonPage",
        "ui.dungeon.DungeonBattleScene", "ui.dev.GMConsolePanel", "ui.hud.TopBar",
        "ui.battle.scene.BattleScene", "ui.character.panel.CharacterPanel",
        "ui.character.equip.EquipmentDetail", "ui.hud.popup.RedeemCodePanel", "systems.LootBoxSystem",
    }
    for _, path in ipairs(pages) do
        local results = {}
        pageResults[path] = results
        mocks[path] = { onActionResult = function(data) results[#results + 1] = data end }
    end
    -- 这些数据桥接依赖不在 claim 分支使用；禁止意外落入真实页面/存档初始化。
    mocks["runtime.ClientDispatcher"] = {}
    mocks["core.PlayerStore"] = {}
    mocks["core.GameState"] = {}
    mocks["config.HeroConfig"] = {}
    require = function(name)
        if mocks[name] ~= nil then
            requireHits[name] = (requireHits[name] or 0) + 1
            return mocks[name]
        end
        if loaded[name] ~= nil then return loaded[name] end
        local module = nativeRequire(name)
        loaded[name] = module
        return module
    end

    local ok, err = pcall(function()
        -- 实际生产模块唯一实例；不是复制 claim 分支，也不改其任何方法/upvalue。
        local Protocol = require("shared.Protocol")
        local ScenarioConfig = require("config.ScenarioDialogueConfig")
        local TutorialConfig = require("config.TutorialConfig")
        local TM = require("systems.TutorialManager")
        mocks["systems.TutorialManager"] = {
            onScenarioClaimed = function(sid)
                notifications[#notifications + 1] = { sid = sid, phase = phase }
                TM.onScenarioClaimed(sid)
            end,
            notifyEvent = function(name) error("unexpected tutorial business event: " .. tostring(name)) end,
        }
        local CMH = require("runtime.ClientMessageHandler")
        CMH.setup({ sendAction = function() sentActions = sentActions + 1 end, ui = {} })
        check(type(CMH.handleActionResult) == "function" and type(CMH.setPendingTutorialNotify) == "function",
            "loaded real CMH entry points")
        eq(requireHits["systems.TutorialManager"], 1, "real setup obtains notification spy")
        eq(requireHits["ui.hud.popup.RewardPopup"], 1, "real setup obtains reward page mock")
        for _, path in ipairs(pages) do
            eq(requireHits[path], 1, "setup intercepted " .. path)
        end
        local claim = Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD
        check(type(claim) == "string", "claim action comes from real Protocol")

        local function reset()
            CMH.resetSessionBridgeState()
            notifications, popups = {}, {}
            phase, persistCount = "idle", 0
            data.session = { tutorialProgress = { version = 1, completed = {}, queue = {} } }
            TM.init({}, store, function(progress)
                data.session.tutorialProgress = progress
                persistCount = persistCount + 1
            end)
            TM.update(0)
        end
        local function queueOnly(sid, label)
            local group = TutorialConfig.SCENARIO_TO_GROUP[sid]
            assert(group, "fixture must map to real tutorial group")
            eq(TM.getCurrentGroup(), nil, label .. " real TM is not active")
            local progress = TM.getProgress()
            eq(#progress.queue, 1, label .. " real TM queues once")
            eq(progress.queue[1], group, label .. " queues exact configured group")
            eq(data.session.tutorialProgress.queue[1], group, label .. " persisted before reward close")
            check(persistCount > 0, label .. " queue persistence invoked")
        end
        local function staysIdle(label)
            TM.update(1)
            check(not TM.isActive() and #TM.getProgress().queue == 0, label .. " no real TM group scheduled")
        end
        local function response(data)
            phase = "action_result"
            CMH.handleActionResult(data)
            phase = "idle"
        end
        local function result(success, rewardType, reward, sid)
            return { action = claim, success = success, rewardType = rewardType, reward = reward,
                scenarioId = sid, reason = success and nil or "test claim rejected" }
        end
        local function beginClose(popup)
            assert(popup, "expected reward popup")
            popup.closing = true
            phase = "close_started"
            -- 与真实 RewardPopup.close 一样，只标记关闭开始，不调用 onClose。
            phase = "idle"
        end
        local function finishClose(popup)
            assert(popup, "expected reward popup")
            if not popup.open or not popup.closing then return end
            popup.open = false
            local callback = popup.opts.onClose
            popup.opts.savedOnClose = callback
            popup.opts.onClose = nil -- 与真实 RewardPopup.update 的一次性关闭契约一致。
            phase = "onClose"
            if callback then callback() end
            phase = "idle"
        end
        local function notifiedOnce(sid, at, label)
            eq(#notifications, 1, label .. " notification count")
            local notice = notifications[1]
            check(notice and notice.sid == sid and notice.phase == at, label .. " exact sid/phase")
        end

        -- 失败必须清掉这次 pending；不能污染紧随其后的成功响应。
        for _, rewardType in ipairs({ "none", "equip", "currency", "hero" }) do
            reset()
            CMH.setPendingTutorialNotify(5)
            response(result(false, rewardType, { templateId = "W1", heroId = 1, currencyKey = "gold", amount = 50 }, 5))
            eq(#notifications, 0, "failed " .. rewardType .. " does not notify")
            eq(#popups, 0, "failed " .. rewardType .. " does not show rewards")
            eq(CMH.pendingTutorialNotify_, nil, "failed " .. rewardType .. " clears pending")
            eq(CMH.consumePendingTutorialNotify(), nil, "failed pending cannot be consumed later")
            response(result(true, "none", nil, 24))
            eq(#notifications, 0, "failed " .. rewardType .. " cannot bleed into later success")
            staysIdle("failed " .. rewardType)
        end

        reset()
        CMH.setPendingTutorialNotify(24)
        response(result(true, "none", nil, 999))
        notifiedOnce(24, "action_result", "success none")
        eq(#popups, 0, "success none requires no popup")
        eq(CMH.pendingTutorialNotify_, nil, "success none consumes pending")
        response(result(true, "none", nil, 24))
        notifiedOnce(24, "action_result", "duplicate none cannot invent pending")
        queueOnly(24, "none response")
        TM.update(0.24)
        eq(TM.getCurrentGroup(), nil, "none waits for stable-frame quiet period")
        TM.update(0.02)
        eq(TM.getCurrentGroup(), TutorialConfig.SCENARIO_TO_GROUP[24], "none starts via real TM after quiet period")

        local rewardCases = {
            { kind = "equip", sid = 5, reward = { templateId = "W1", quality = 3, level = 7 },
                item = { type = "equip", templateId = "W1", quality = 3, level = 7 } },
            { kind = "currency", sid = 31, reward = { currencyKey = "recruitTicket", amount = 10 },
                item = { type = "adventure_ticket", amount = 10 } },
            { kind = "hero", sid = 20, reward = { heroId = 1, name = "test hero", quality = 1 },
                item = { type = "hero", heroId = 1, name = "test hero", quality = 3 } },
        }
        for _, case in ipairs(rewardCases) do
            reset()
            CMH.setPendingTutorialNotify(case.sid)
            response(result(true, case.kind, case.reward, 999))
            notifiedOnce(case.sid, "action_result", case.kind .. " success enqueues once")
            queueOnly(case.sid, case.kind .. " successful claim")
            TM.update(3)
            queueOnly(case.sid, case.kind .. " open rewards block real TM start")
            eq(CMH.pendingTutorialNotify_, nil, case.kind .. " response transfers and clears pending")
            eq(CMH.consumePendingTutorialNotify(), nil, case.kind .. " cannot be fired by old frame consumer")
            eq(#popups, 1, case.kind .. " creates exactly one popup")
            local popup = popups[1]
            assert(popup, "missing " .. case.kind .. " popup")
            eq(popup.title, "远征奖励", case.kind .. " uses scenario reward popup")
            eq(#popup.rewards, 1, case.kind .. " reward count")
            for key, value in pairs(case.item) do
                eq(popup.rewards[1][key], value, case.kind .. " reward field " .. key)
            end
            check(type(popup.opts.onClose) == "function", case.kind .. " installs real CMH close callback")
            if case.kind == "hero" then
                eq(CMH.pendingFollowUpDialogue_, nil, "hero follow-up waits for reward close")
            end
            beginClose(popup)
            TM.update(1)
            queueOnly(case.sid, case.kind .. " closing animation still blocks real TM start")
            finishClose(popup)
            notifiedOnce(case.sid, "action_result", case.kind .. " onClose does not notify twice")
            queueOnly(case.sid, case.kind .. " onClose itself does not start TM")
            -- 直接重入生产回调也应幂等；此处不能仅依赖页面替身清 callback 的保护。
            local realCloseCallback = popup.opts.savedOnClose
            if realCloseCallback then
                phase = "onClose_replayed"
                realCloseCallback()
                phase = "idle"
            end
            notifiedOnce(case.sid, "action_result", case.kind .. " captured production callback is idempotent")
            if case.kind == "hero" then
                local follow = CMH.consumePendingFollowUpDialogue()
                check(follow and follow.config == ScenarioConfig.SCENARIO_14,
                    "hero close keeps real follow-up config, without running its scheduler")
                eq(CMH.consumePendingFollowUpDialogue(), nil, "hero follow-up consumed once")
            end
            finishClose(popup)
            notifiedOnce(case.sid, "action_result", case.kind .. " repeated page close cannot replay consumed callback")
            -- 再次回执可以重复展示旧业务奖励，但没有 pending 时绝不伪造引导通知。
            response(result(true, case.kind, case.reward, case.sid))
            eq(#popups, 2, case.kind .. " duplicate follows actual reward route")
            beginClose(popups[2]); finishClose(popups[2])
            notifiedOnce(case.sid, "action_result", case.kind .. " duplicate response cannot synthesize notification")
            queueOnly(case.sid, case.kind .. " duplicates preserve one pending group")
            TM.update(0.24)
            eq(TM.getCurrentGroup(), nil, case.kind .. " waits for post-close quiet period")
            TM.update(0.02)
            eq(TM.getCurrentGroup(), TutorialConfig.SCENARIO_TO_GROUP[case.sid],
                case.kind .. " starts through real TM only after windows close and quiet period")
            eq(#TM.getProgress().queue, 0, case.kind .. " started group drained exactly once")
        end

        -- 没有通知令牌时，即使回包携带合法/映射到教程的 scenarioId 也不能凭空启动。
        for _, case in ipairs(rewardCases) do
            reset()
            response(result(true, case.kind, case.reward, case.sid))
            eq(#notifications, 0, "unarmed " .. case.kind .. " does not notify on response")
            eq(#popups, 1, "unarmed " .. case.kind .. " still shows business reward")
            beginClose(popups[1]); finishClose(popups[1])
            eq(#notifications, 0, "unarmed " .. case.kind .. " does not fabricate notification onClose")
            eq(CMH.pendingTutorialNotify_, nil, "unarmed " .. case.kind .. " stays clear")
            staysIdle("unarmed " .. case.kind)
        end
        reset()
        response(result(true, "none", nil, 24))
        eq(#notifications, 0, "unarmed none cannot infer notification from response sid")
        eq(#popups, 0, "unarmed none has no reward popup")
        response(result(true, nil, nil, 24))
        eq(#notifications, 0, "unarmed payload without reward cannot fabricate notification")
        staysIdle("unarmed none/missing reward")

        -- 外部已消费/会话重置的通知不能被后来成功回执重新制造。
        reset()
        CMH.setPendingTutorialNotify(24)
        local consumed = CMH.consumePendingTutorialNotify()
        check(consumed and consumed.scenarioId == 24, "explicit consume returns original token")
        response(result(true, "none", nil, 24))
        eq(#notifications, 0, "explicitly consumed token cannot be recovered from response")
        CMH.setPendingTutorialNotify(31)
        CMH.resetSessionBridgeState()
        response(result(true, "currency", { currencyKey = "gold", amount = 100 }, 31))
        beginClose(popups[1]); finishClose(popups[1])
        eq(#notifications, 0, "reset pending cannot be revived by reward callback")
        staysIdle("consumed/reset pending")

        -- 回调必须捕获领取时的令牌；期间另一剧情发起不应被旧回调消费或篡改。
        reset()
        CMH.setPendingTutorialNotify(5)
        response(result(true, "equip", { templateId = "W1" }, 5))
        CMH.setPendingTutorialNotify(31)
        beginClose(popups[1]); finishClose(popups[1])
        notifiedOnce(5, "action_result", "old popup notification retains original scenario")
        check(CMH.pendingTutorialNotify_ and CMH.pendingTutorialNotify_.scenarioId == 31,
            "old close callback leaves newly armed pending intact")
        response(result(true, "none", nil, 31))
        eq(#notifications, 2, "new pending delivered once by its own response")
        local nextNotice = notifications[2]
        check(nextNotice and nextNotice.sid == 31 and nextNotice.phase == "action_result",
            "new pending has its own scenario and timing")
        eq(CMH.pendingTutorialNotify_, nil, "both independent tokens drained")

        -- 非领取成功/失败回执都不消费 pending，更不能启动情景教学。
        reset()
        CMH.setPendingTutorialNotify(24)
        response({ action = "tutorial_timing_unrelated", success = true, scenarioId = 24 })
        response({ action = "tutorial_timing_unrelated", success = false, reason = "unrelated failure" })
        eq(#notifications, 0, "unrelated responses cannot notify")
        check(CMH.pendingTutorialNotify_ and CMH.pendingTutorialNotify_.scenarioId == 24,
            "unrelated responses preserve pending")
        response(result(true, "none", nil, 24))
        notifiedOnce(24, "action_result", "preserved token delivered by actual claim")

        -- Spy 页面确实被生产分发调用；通知不是独立测试辅助函数主动发出的。
        check(#pageResults["ui.tavern.TavernPage"] > 0 and #pageResults["ui.backpack.BackpackPanel"] > 0,
            "real CMH routes action results into intercepted pages")
        eq(sentActions, 0, "test does not send business actions")
        CMH.resetSessionBridgeState()
    end)
    require = nativeRequire
    if not ok then
        failures = failures + 1
        log:Write(LOG_ERROR, prefix .. "FAIL exception: " .. tostring(err))
    end
    print(prefix .. (failures == 0 and "ALL PASS" or "FAILED")
        .. ": " .. checks .. " assertions, " .. failures .. " failures")
    engine:Exit()
end
