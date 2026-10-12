-- ============================================================================
-- hero_scenario_claim_test.lua — 角色详情剧情落档回归（2026-09-30 方案A+C）
-- 背景：闲聊情景 78–81 之前只记内存 idleSeen_（重启必弹，玩家体感
--       "点角色详情一直显示剧情"）。方案A 改为与入队一致 markClaimed 落档；
--       方案C 给 ScenarioDialogue 增加结束广播，HeroScenario 订阅后即时
--       消化 pending_ 积压（不再等下次点击突然补播）。
-- 隔离方式：宿主cache只读HeroScenario源码，以独立env执行，所有依赖只用内存桩。
-- 不替换全局require/cjson，不启动main、不读写玩家档、不允许未知依赖回退。
-- 单实例内可由resetAll明确隔离独立用例；已claimed的重启模拟保留。
-- 跑法: /workspace/.cli/UrhoXRuntime tests/hero_scenario_claim_test.lua \
--         -tapcode_dir=/workspace/game2 -tool_mode -graphicsheadless
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

-- ======================== 显式内存依赖与独立环境 ========================

local nativeRequire, nativeEncode, nativeFile, nativeCache = require, cjson.encode, File, cache
local denied = {}
---@type table<string, any>
local loadedCache = {}
---@type table<string, any>
local mocks = {}
local function deny(name)
    denied[#denied + 1] = name
    error("isolated HeroScenario test denies " .. tostring(name))
end
local function isolatedRequire(name)
    if mocks[name] ~= nil then return mocks[name] end
    if loadedCache[name] ~= nil then return loadedCache[name] end
    if name ~= "ui.character.hero.HeroScenario" then return deny("unknown require " .. tostring(name)) end
    local file = assert(nativeCache:GetFile("ui/character/hero/HeroScenario.lua"))
    assert(file:IsOpen() and file:GetMode() == FILE_READ, "source must be read-only")
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local env = setmetatable({ require = isolatedRequire, cjson = cjson,
        File = function() return deny("player File") end,
        fileSystem = setmetatable({}, { __index = function() return function() return deny("fileSystem") end end }),
        clientCloud = setmetatable({}, { __index = function() return function() return deny("cloud") end end }),
    }, { __index = _G })
    local chunk, why = load(table.concat(lines, "\n"), "@ui/character/hero/HeroScenario.lua", "t", env)
    assert(chunk, why)
    local mod = chunk()
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

-- session更新真实经过cjson编解码，仅在内存dispatcher替换，不污染宿主编码函数。

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
    recoveryBlocked = false, battleRewardBlocked = false, storyPending = false,
    recruitBusy = false, place = "battle" }
mocks["systems.TutorialManager"] = { canPlayPendingStory = function() return not playback.tutorialBlocked end }
mocks["ui.hud.popup.RewardPopup"] = {
    isOpen = function() return playback.rewardOpen end,
    hasPendingBattleRewards = function() return playback.rewardPending end,
}
mocks["ui.tutorial.TutorialPageRecovery"] = {
    getStoryPlace = function() return playback.place end,
    isBlocked = function() return playback.recoveryBlocked end,
    isPendingStoryBlocked = function(place)
        assert(place == playback.place, "必须传真实所属上下文")
        return playback.recoveryBlocked
    end,
}
mocks["ui.tavern.TavernPage"] = { isRecruitBusy = function() return playback.recruitBusy end }
mocks["boot.BattleRewardOverlay"] = { isBlocked = function() return playback.battleRewardBlocked end }
mocks["systems.StoryPlayer"] = { hasPending = function(place)
    assert(place == playback.place, "只查询所属场景待播")
    return playback.storyPending
end }

-- 假 ClientDispatcher
---@type table<string, table>
local modules = {}
mocks["runtime.ClientDispatcher"] = {
    get = function(name) return modules[name] end,
    handleStateUpdate = function(json)
        local update = cjson.decode(json)
        for name, data in pairs(update.modules) do modules[name] = data end
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
    for key in pairs(playback) do if key ~= "place" then playback[key] = false end end
    playback.place = "battle"
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
    local HS = isolatedRequire("ui.character.hero.HeroScenario")

    -- 用例1（方案A核心·模拟重启）：19 号预置存档 claimed={75,79}（重启恢复的
    -- 落档数据），idleSeen_[19] 本进程从未设置 → 旧代码必弹闲聊79，新代码不弹
    resetState({ ["75"] = true, ["79"] = true })
    HS.onOpenHero(19)
    eq(#playedCfgs, 0, "用例1: 重启恢复后（存档已记79）点详情不弹剧情——方案A核心")

    -- 用例2：已拥有只证明招募成功；未看入队必须先74，再78并各自落档。
    resetState()
    flushCount = 0
    HS.onOpenHero(18)
    eq(#playedCfgs, 1, "用例2: 已拥有未看先播入队74")
    eq(idOfPlayed(playedCfgs[1]), 74, "用例2: 第一段入队74")
    check(claimedOf(74), "用例2: 实际入队起播才落档")
    check(not claimedOf(78), "用例2: 闲聊未播不提前落档")
    eq(flushCount, 1, "用例2: 入队落档恰好一次Flush")
    finishCurrentDialogue()
    eq(#playedCfgs, 2, "用例2: 入队结束接闲聊78")
    eq(idOfPlayed(playedCfgs[2]), 78, "用例2: 第二段闲聊78")
    check(claimedOf(78), "用例2: 实际闲聊才落档")
    eq(flushCount, 2, "用例2: 两段各自Flush一次")
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
        eq(idOfPlayed(playedCfgs[1]), 77, "用例7: 补播已拥有未看的入队77")
        check(claimedOf(77), "用例7: 真正起播才标记入队77")
        check(not claimedOf(81), "用例7: 闲聊未开始不提前标记")
        finishCurrentDialogue()
        eq(idOfPlayed(playedCfgs[2]), 81, "用例7: 入队结束接81")
        check(claimedOf(81), "用例7: 闲聊81落档")
        finishCurrentDialogue()
    end

    -- 用例8：18 号已全部落档，busy 时再点 → 不重播也不排队（广播后也不播）
    -- 已落档旧角色在后续用例resetState的session中也显式保留记录。
    modules.session.claimedScenarios["74"], modules.session.claimedScenarios["78"] = true, true
    playedCfgs = {}
    dialogueActive = true
    HS.onOpenHero(18)
    dialogueActive = false
    EventBus.emit("scenario_dialogue_finished", { reason = "finished" })
    eq(#playedCfgs, 0, "用例8: 已落档角色 busy 时再点不重播不排队")

    -- 新调度依赖：任何阻挡都只排队，不提前写claimed；没有结束广播也能由update补播。
    for _, gate in ipairs({ "tutorialBlocked", "rewardOpen", "rewardPending", "recoveryBlocked", "storyPending", "recruitBusy" }) do
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
        eq(idOfPlayed(playedCfgs[1]), 77, "调度 " .. gate .. ": 已拥有未看先入队")
        check(claimedOf(77) and not claimedOf(81), "调度 " .. gate .. ": 只标记实际入队展示")
        finishCurrentDialogue()
        eq(idOfPlayed(playedCfgs[2]), 81, "调度 " .. gate .. ": 入队结束接闲聊")
        finishCurrentDialogue(); HS.update()
        eq(#playedCfgs, 2, "调度 " .. gate .. ": 重复poll不重播")
    end
    HS.resetAll(); resetState()
    playback.tutorialBlocked = true
    HS.onRecruitResults({ { type = "hero", heroId = 24, isNew = true } })
    HS.resetAll()
    playback.tutorialBlocked = false
    HS.update()
    eq(#playedCfgs, 0, "resetAll丢弃旧待播，不把清档前队列带入新会话")
    check(not claimedOf(76) and not claimedOf(80), "resetAll不伪造旧待播已看或落档")

    -- 正式消息顺序先水合roster再通知招募；拥有标记不能让未看入队被跳过。
    for _, hero in ipairs({ 18,19,24,25 }) do
        HS.resetAll(); resetState(); flushCount = 0
        playback.place = "tavern"
        modules.heroes.roster[tostring(hero)] = { level = 3 }
        modules.heroes.roster[hero] = nil
        local join = ({ [18]=74,[19]=75,[24]=76,[25]=77 })[hero]
        HS.onRecruitResults({ { type="hero", heroId=hero, isNew=true }, { type="hero", heroId=hero, isNew=true } })
        eq(#playedCfgs,1,"roster先水合再回执仍播入队一次 " .. hero)
        eq(idOfPlayed(playedCfgs[1]),join,"正式招募顺序第一段入队 " .. hero)
        finishCurrentDialogue()
        eq(idOfPlayed(playedCfgs[2]),join+4,"正式招募顺序第二段闲聊 " .. hero)
        finishCurrentDialogue(); HS.update(); HS.onOpenHero(hero)
        eq(#playedCfgs,2,"酒馆重复详情/回执不重播 " .. hero)
        eq(flushCount,2,"酒馆两段各落档一次 " .. hero)
    end
    for _, place in ipairs({ "town","smith","church","other" }) do
        HS.resetAll(); resetState(); flushCount=0; playback.place=place
        HS.onOpenHero(25); HS.update(); EventBus.emit("scenario_dialogue_finished",{})
        eq(#playedCfgs,0,"错场不播招募故事 " .. place)
        check(HS.hasPending() and not claimedOf(77) and not claimedOf(81),"错场保留队列不伪标记 " .. place)
        eq(flushCount,0,"错场不落档 " .. place)
        playback.place="tavern"; HS.update()
        eq(idOfPlayed(playedCfgs[1]),77,"回酒馆才播入队")
        finishCurrentDialogue(); finishCurrentDialogue(); HS.update()
        eq(#playedCfgs,2,"回所属场景完整两段一次")
    end
    HS.resetAll(); resetState({["75"]=true,["79"]=true})
    playback.place="tavern"
    HS.onOpenHero(19); HS.onRecruitResults({{type="hero",heroId=19,isNew=true}}); HS.update()
    eq(#playedCfgs,0,"已有两段claimed在酒馆也不重播")
    eq(#denied,0,"真实Hero源码未访问玩家档或云端")
    eq(require,nativeRequire,"宿主require保持原样")
    eq(cjson.encode,nativeEncode,"宿主cjson编码保持原样")
    eq(File,nativeFile,"宿主File保持原样")
    eq(cache,nativeCache,"宿主cache保持原样")

    if #failures == 0 then
        print(PREFIX .. "RESULT ALL PASS")
    else
        print(PREFIX .. "RESULT " .. #failures .. " FAIL")
    end
    engine:Exit()
end
