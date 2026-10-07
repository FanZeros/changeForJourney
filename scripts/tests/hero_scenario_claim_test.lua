-- ============================================================================
-- hero_scenario_claim_test.lua — 角色详情剧情落档回归（2026-09-30 方案A+C）
-- 背景：闲聊情景 78–81 之前只记内存 idleSeen_（重启必弹，玩家体感
--       "点角色详情一直显示剧情"）。方案A 改为与入队一致 markClaimed 落档；
--       方案C 给 ScenarioDialogue 增加结束广播，HeroScenario 订阅后即时
--       消化 pending_ 积压（不再等下次点击突然补播）。
-- Mock 方式（探针 tests/probe_require.lua 验证）：
--   - 引擎 require 忽略 package.loaded 预注入 → 必须替换全局 require + 自带缓存
--   - 引擎 require 有内部缓存、模块无法重载 → 测试全程共用唯一模块实例，
--     每个角色（18/19/24/25）只走一条完整流程，避免 idleSeen_ 跨用例残留
--   - "重启后不再弹"用 19 号验证：预置存档 claimed={75,79}（模拟重启恢复
--     的落档数据），idleSeen_[19] 本进程从未设置 → 旧代码必弹 79，新代码不弹
-- 跑法: ./.cli/UrhoXRuntime tests/hero_scenario_claim_test.lua \
--         -tapcode_dir=. -tool_mode -graphicsheadless
-- ============================================================================

local PREFIX = "[hero_scenario_claim] "
local failures = {}
local function check(cond, msg)
    if cond then print(PREFIX .. "[PASS] " .. msg)
    else print(PREFIX .. "[FAIL] " .. msg); failures[#failures + 1] = msg end
end
local function eq(actual, expected, msg)
    check(actual == expected, msg .. " (实际=" .. tostring(actual) .. " 期望=" .. tostring(expected) .. ")")
end

-- ======================== Mock 依赖（替换全局 require） ========================

local engineRequire = require
---@type table<string, any>
local loadedCache = {}
---@type table<string, any>
local mocks = {}
_G.require = function(name)
    if mocks[name] ~= nil then return mocks[name] end
    if loadedCache[name] ~= nil then return loadedCache[name] end
    local mod = engineRequire(name)
    loadedCache[name] = mod
    return mod
end

-- EventBus 单例 mock（测试与 HeroScenario 共享同一实例；不 clear，订阅全程有效）
local listeners = {}
mocks["core.EventBus"] = {
    on = function(event, cb)
        listeners[event] = listeners[event] or {}
        listeners[event][#listeners[event] + 1] = cb
    end,
    off = function(event, cb)
        local list = listeners[event]
        if not list then return end
        for i = #list, 1, -1 do
            if list[i] == cb then table.remove(list, i) break end
        end
    end,
    emit = function(event, data)
        local list = listeners[event]
        if not list then return end
        for i = 1, #list do list[i](data) end
    end,
}
local EventBus = mocks["core.EventBus"]

-- cjson.encode 挂钩子：markClaimed 走 encode→handleStateUpdate JSON 往返，
-- headless 下不真解析，把 session 表直接递给 MockBridge
local MockBridge = {}
local realEncode = cjson.encode
cjson.encode = function(t)
    if type(t) == "table" and t.modules and t.modules.session then
        MockBridge.lastSession = t.modules.session
    end
    local ok, s = pcall(realEncode, t)
    return ok and s or "{}"
end

-- 假 ScenarioDialogue：记录播放历史
local playedCfgs = {}
local dialogueActive = false
local lastShown = nil
mocks["ui.story.ScenarioDialogue"] = {
    isActive = function() return dialogueActive end,
    show = function(cfg)
        dialogueActive = true
        lastShown = cfg
        playedCfgs[#playedCfgs + 1] = cfg
    end,
}

-- 新剧情调度依赖必须显式使用内存桩，绝不由 require fallback 进入真实教程/奖励/恢复业务。
local playback = { tutorialBlocked = false, rewardOpen = false, rewardPending = false,
    recoveryBlocked = false, battleRewardBlocked = false, storyPending = false }
mocks["systems.TutorialManager"] = { canPlayPendingStory = function() return not playback.tutorialBlocked end }
mocks["ui.hud.popup.RewardPopup"] = {
    isOpen = function() return playback.rewardOpen end,
    hasPendingBattleRewards = function() return playback.rewardPending end,
}
mocks["ui.tutorial.TutorialPageRecovery"] = {
    isBlocked = function() return playback.recoveryBlocked end,
    isPendingStoryBlocked = function() return playback.recoveryBlocked end,
}
mocks["boot.BattleRewardOverlay"] = { isBlocked = function() return playback.battleRewardBlocked end }
mocks["systems.StoryPlayer"] = { hasPending = function() return playback.storyPending end }

-- 假 ClientDispatcher
---@type table<string, table>
local modules = {}
mocks["runtime.ClientDispatcher"] = {
    get = function(name) return modules[name] end,
    handleStateUpdate = function(_)
        if MockBridge.lastSession then
            modules.session = MockBridge.lastSession
            MockBridge.lastSession = nil
        end
    end,
}

-- 假 StandaloneSave（Flush 只计数）
local flushCount = 0
mocks["boot.StandaloneSave"] = {
    Flush = function() flushCount = flushCount + 1 end,
}

-- 假情景配置：74–77 入队 / 78–81 闲聊；steps 文本携带 id 供反查
local ScenarioConfigMock = {}
for _, id in ipairs({ 74, 75, 76, 77, 78, 79, 80, 81 }) do
    ScenarioConfigMock["SCENARIO_" .. id] = {
        mode = "small",
        steps = { { characterId = 1, name = "t", text = "scenario " .. id } },
    }
end
mocks["config.ScenarioDialogueConfig"] = ScenarioConfigMock

-- ======================== 测试辅助 ========================

--- 重置播放记录与数据（session.claimed 由用例各自预置）
---@param claimed table|nil 预置的 claimedScenarios（模拟存档恢复）
local function resetState(claimed)
    playedCfgs = {}
    dialogueActive = false
    lastShown = nil
    MockBridge.lastSession = nil
    for key in pairs(playback) do playback[key] = false end
    modules.session = { claimedScenarios = claimed or {}, introCompleted = true }
    modules.heroes = {
        roster = {
            [18] = { level = 1 },   -- 老六：已拥有
            [19] = { level = 1 },   -- 哈基米：已拥有
            [24] = { level = 1 },   -- 加载中：已拥有（招募用例前会临时移除）
            [25] = { level = 1 },   -- 高ping战士：已拥有
        },
    }
end

--- 结束当前对话（触发 onFinish 链）
local function finishCurrentDialogue()
    dialogueActive = false
    local cfg = lastShown
    lastShown = nil
    if cfg and cfg.onFinish then cfg.onFinish() end
end

--- 播放 cfg 的情景 id 反查（HeroScenario 只传 mode/steps/onFinish）
local function idOfPlayed(cfg)
    local text = cfg and cfg.steps and cfg.steps[1] and cfg.steps[1].text or ""
    return tonumber(tostring(text):match("scenario (%d+)"))
end

local function claimedOf(id)
    return modules.session.claimedScenarios[tostring(id)] == true
end

-- ======================== 用例 ========================

function Start()
    print(PREFIX .. "start")

    -- 模块无法重载 → 全程唯一实例；每个角色只走一条流程（idleSeen_ 无残留干扰）
    local HS = require("ui.character.hero.HeroScenario")

    -- 用例1（方案A核心·模拟重启）：19 号预置存档 claimed={75,79}（重启恢复的
    -- 落档数据），idleSeen_[19] 本进程从未设置 → 旧代码必弹闲聊79，新代码不弹
    resetState({ ["75"] = true, ["79"] = true })
    HS.onOpenHero(19)
    eq(#playedCfgs, 0, "用例1: 重启恢复后（存档已记79）点详情不弹剧情——方案A核心")

    -- 用例2（首播+落档）：18 号空存档 → 入队74补落档（已拥有不播），闲聊78播一次并落档
    resetState()
    flushCount = 0
    HS.onOpenHero(18)
    eq(#playedCfgs, 1, "用例2: 已拥有角色只播1段（闲聊78；入队74仅补落档）")
    eq(idOfPlayed(playedCfgs[1]), 78, "用例2: 播的是闲聊78")
    check(claimedOf(74), "用例2: 入队74补落档 claimedScenarios")
    check(claimedOf(78), "用例2: 闲聊78落档 claimedScenarios")
    check(flushCount >= 1, "用例2: markClaimed 触发 StandaloneSave.Flush")
    finishCurrentDialogue()

    -- 用例3：18 号同进程内再点 → 不播
    playedCfgs = {}
    HS.onOpenHero(18)
    eq(#playedCfgs, 0, "用例3: 已落档，同进程再点不播")

    -- 用例4：未拥有角色（临时移除 roster[24]）→ 不播不落档
    modules.heroes.roster[24] = nil
    playedCfgs = {}
    HS.onOpenHero(24)
    eq(#playedCfgs, 0, "用例4: 未拥有角色不播")
    check(not claimedOf(76), "用例4: 未拥有角色不落档")

    -- 用例5：非玩梗角色1 → 不播
    modules.heroes.roster[1] = { level = 10 }
    playedCfgs = {}
    HS.onOpenHero(1)
    eq(#playedCfgs, 0, "用例5: 非玩梗角色不播")

    -- 用例6（招募流程）：24 号 isNew 且 roster 未同步 → 播入队76接闲聊80，双落档
    resetState()
    modules.heroes.roster[24] = nil   -- 招募瞬间 roster 还没同步该英雄
    HS.onRecruitResults({ { type = "hero", heroId = 24, isNew = true } })
    eq(#playedCfgs, 1, "用例6: 招募新人播入队76")
    eq(idOfPlayed(playedCfgs[1]), 76, "用例6: 第一段是入队76")
    check(claimedOf(76), "用例6: 入队76落档")
    finishCurrentDialogue()   -- 入队播完 → 链播闲聊80
    eq(#playedCfgs, 2, "用例6: 入队结束接闲聊80")
    eq(idOfPlayed(playedCfgs[2]), 80, "用例6: 第二段是闲聊80")
    check(claimedOf(80), "用例6: 闲聊80落档")
    finishCurrentDialogue()

    -- 用例7（方案C核心）：25 号，对话 busy 时点详情 → 进 pending_；广播结束后自动补播
    resetState()
    dialogueActive = true    -- 假装城镇剧情正在播
    HS.onOpenHero(25)
    eq(#playedCfgs, 0, "用例7: 对话忙时不播（请求进 pending_，不提前消费）")
    check(not claimedOf(77), "用例7: busy 时入队77不提前落档")
    dialogueActive = false
    EventBus.emit("scenario_dialogue_finished", { reason = "finished" })
    check(#playedCfgs >= 1, "用例7: 广播结束后立即补播——方案C核心（无需等下次点击）")
    if #playedCfgs >= 1 then
        eq(idOfPlayed(playedCfgs[1]), 81, "用例7: 补播的是闲聊81")
        check(claimedOf(77), "用例7: 释放后已拥有角色才补入队77落档")
        check(claimedOf(81), "用例7: 闲聊81落档")
        finishCurrentDialogue()
    end

    -- 用例8：18 号已全部落档，busy 时再点 → 不重播也不排队（广播后也不播）
    playedCfgs = {}
    dialogueActive = true
    HS.onOpenHero(18)
    dialogueActive = false
    EventBus.emit("scenario_dialogue_finished", { reason = "finished" })
    eq(#playedCfgs, 0, "用例8: 已落档角色 busy 时再点不重播不排队")

    -- 新调度依赖：任何阻挡都只排队，不提前写claimed；没有结束广播也能由update补播。
    for _, gate in ipairs({ "tutorialBlocked", "rewardOpen", "rewardPending", "recoveryBlocked", "storyPending" }) do
        HS.resetAll()
        resetState()
        flushCount = 0
        playback[gate] = true
        HS.onOpenHero(25); HS.onOpenHero(25); HS.update()
        eq(#playedCfgs, 0, "调度 " .. gate .. ": 阻挡期间不展示")
        check(not claimedOf(77) and not claimedOf(81), "调度 " .. gate .. ": 阻挡期间不消费入队或闲聊")
        eq(flushCount, 0, "调度 " .. gate .. ": 阻挡期间不Flush")
        playback[gate] = false
        HS.update()
        eq(#playedCfgs, 1, "调度 " .. gate .. ": update释放后去重补播一次")
        eq(idOfPlayed(playedCfgs[1]), 81, "调度 " .. gate .. ": 已拥有角色补播正确闲聊")
        check(claimedOf(77) and claimedOf(81), "调度 " .. gate .. ": 实际展示后才落档")
        finishCurrentDialogue(); HS.update()
        eq(#playedCfgs, 1, "调度 " .. gate .. ": 重复poll不重播")
    end
    HS.resetAll(); resetState()
    playback.tutorialBlocked = true
    HS.onRecruitResults({ { type = "hero", heroId = 24, isNew = true } })
    HS.resetAll()
    playback.tutorialBlocked = false
    HS.update()
    eq(#playedCfgs, 0, "resetAll丢弃旧待播，不把清档前队列带入新会话")
    check(not claimedOf(76) and not claimedOf(80), "resetAll不伪造旧待播已看或落档")

    if #failures == 0 then
        print(PREFIX .. "RESULT ALL PASS")
    else
        print(PREFIX .. "RESULT " .. #failures .. " FAIL")
    end
    engine:Exit()
end
