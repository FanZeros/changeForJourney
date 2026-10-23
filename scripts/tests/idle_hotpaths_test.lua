-- 三个重复开销热点的隔离回归。只读真实源码，依赖全部显式内存桩；未知依赖立即失败。
-- 不启动main、不接真实存档/云端、不替换_G；由主会话统一构建与运行。
local TAG = "[idle_hotpaths_test]"
local checks = 0

local function check(value, label)
    checks = checks + 1
    assert(value, label)
end

local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

local function noop() end

-- 源码来源仍走宿主只读cache；被测模块只能看见显式提供的全局/依赖。
local function readSource(path)
    local file = assert(cache:GetFile(path), "missing test source " .. path)
    assert(file:IsOpen() and file:GetMode() == FILE_READ, "source must be read-only")
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function loadIsolated(path, dependencies, overrides)
    local env = {
        assert = assert, error = error, type = type, tonumber = tonumber, tostring = tostring,
        ipairs = ipairs, pairs = pairs, next = next, pcall = pcall,
        math = math, table = table, string = string, print = noop,
        require = function(name)
            assert(dependencies[name] ~= nil, "unknown isolated dependency " .. tostring(name))
            return dependencies[name]
        end,
    }
    for key, value in pairs(overrides or {}) do env[key] = value end
    return assert(load(readSource(path), "@" .. path, "t", env))()
end

local function tutorialFixture(progress)
    local f = { blocked = false, story = false, reward = false, busy = false,
        guards = 0, prepared = 0, persisted = 0, draw = {}, sessionReads = 0 }
    local config = { SCENARIO_TO_GROUP = { [5] = 1, [8] = 2, [31] = 8 } }
    for _, id in ipairs({1, 2, 8}) do
        config[id] = { steps = { { highlight = "target", advanceOn = "done", text = "test" } } }
    end
    local session = { tutorialProgress = progress or { version = 1, completed = {}, queue = {} } }
    local deps = {
        ["config.TutorialConfig"] = config,
        ["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 } },
        ["core.DrawUtil"] = {},
        ["ui.story.ScenarioDialogue"] = { isActive = function() return f.story end },
        ["ui.hud.popup.RewardPopup"] = { isOpen = function() return f.reward end },
        ["ui.tavern.TavernPage"] = { isRecruitBusy = function() return f.busy end },
        ["ui.tutorial.TutorialPageRecovery"] = {
            isBlocked = function() f.guards = f.guards + 1; return f.blocked end,
            prepare = function() f.prepared = f.prepared + 1; return false end,
            canRestoreTarget = function() return true end,
        },
        ["ui.tutorial.TutorialOverlay"] = { draw = function(_, _, _, _, _, elapsed, groupElapsed)
            f.draw = { elapsed = elapsed, groupElapsed = groupElapsed }; return {}
        end },
    }
    f.module = loadIsolated("systems/TutorialManager.lua", deps)
    f.module.init({}, { Get = function(key)
        assert(key == "session", "fixture must not query live data")
        f.sessionReads = f.sessionReads + 1
        return session
    end }, function(state)
        f.persisted = f.persisted + 1
        session.tutorialProgress = state
        if f.onPersist then f.onPersist(state) end
    end)
    return f
end

local function testTutorial()
    local f = tutorialFixture()
    local tm = f.module
    for _ = 1, 128 do tm.update(0.125) end
    eq(f.guards, 0, "empty tutorial queue never queries recovery guard")
    eq(f.prepared, 0, "empty tutorial queue does not prepare pages")
    eq(f.persisted, 0, "idle polling adds no persistence")
    eq(f.sessionReads, 1, "session hydration remains one-shot")
    tm.onScenarioClaimed(5)
    f.blocked = true
    tm.update(3)
    check(not tm.isActive() and #tm.getProgress().queue == 1, "blocked task stays queued")
    check(f.guards > 0, "nonempty queue still queries guard")
    f.blocked = false
    tm.update(0.125)
    check(not tm.isActive(), "release does not bypass quiet window")
    f.blocked = true; tm.update(1); f.blocked = false
    tm.update(0.125)
    check(not tm.isActive(), "new blocker resets partial quiet time")
    tm.update(0.125)
    eq(tm.getCurrentGroup(), 1, "continuous quiet window starts task")
    tm.update(0.125)
    tm.draw()
    eq(f.draw.elapsed, 20.5, "idle/blocked time still advances real overlay clock")
    eq(f.draw.groupElapsed, 0.125, "group time starts only with active input")
    f.blocked = true; tm.update(5); f.blocked = false
    tm.draw()
    eq(f.draw.groupElapsed, 0.125, "active group input clock pauses while blocked")
    tm.skipCurrentGroup(); tm.update(0.125)
    check(tm.isActive(), "active out-animation keeps original duration")
    tm.update(0.125)
    check(not tm.isActive(), "out-animation eventually releases active group")
    local before = f.guards
    tm.update(2)
    eq(f.guards, before, "completed empty tutorial returns before recovery")

    -- 内存会话水合不是玩家读档：快路径必须位于restore之后。
    f = tutorialFixture({ version = 1, completed = {}, queue = {2} })
    f.module.update(0.125)
    check(not f.module.isActive() and #f.module.getProgress().queue == 1,
        "hydrated queue is not skipped by idle fast path")
    f.module.update(0.125)
    eq(f.module.getCurrentGroup(), 2, "hydrated queue keeps quiet-window timing")
    f = tutorialFixture({ version = 1, completed = {}, group = 1 })
    f.module.update(0.125)
    eq(f.module.getCurrentGroup(), 1, "hydrated active group is not treated as idle")
    eq(f.prepared, 1, "hydrated active group still prepares its target")

    -- save回调同步入队属于原有重入契约，不允许快路径丢失后续任务。
    -- 普通事件发生在会话水合后；否则原有restore会再次追加persist写回的queue。
    f = tutorialFixture()
    f.module.update(0)
    local queued = false
    f.onPersist = function(state)
        if state.group == 1 and not queued then
            queued = true
            f.module.onScenarioClaimed(8)
        end
    end
    f.module.onScenarioClaimed(5); f.module.update(0.25)
    eq(f.module.getProgress().queue[1], 2, "reentrant persistence preserves follow-up queue")
    f.module.skipCurrentGroup(); f.module.update(0.25); f.module.update(0.25)
    eq(f.module.getCurrentGroup(), 2, "reentrant queued task starts after prior fade-out")

    for _, gate in ipairs({"story", "reward", "busy"}) do
        f = tutorialFixture(); f.module.update(0)
        f.module.onScenarioClaimed(5); f[gate] = true
        f.module.update(10)
        check(not f.module.isActive(), "tutorial waits for " .. gate)
        f[gate] = false; f.module.update(0.125)
        check(not f.module.isActive(), "tutorial retains quiet window after " .. gate)
        f.module.update(0.125)
        eq(f.module.getCurrentGroup(), 1, "tutorial resumes after " .. gate)
    end
end

local function heroFixture()
    local f = { guards = 0, blocked = false, active = false, played = {}, listeners = {},
        saves = 0, writes = 0, modules = { session = { claimedScenarios = {} } } }
    local function guard(value) f.guards = f.guards + 1; return value end
    local deps = {
        ["config.ScenarioDialogueConfig"] = {
            SCENARIO_74 = { steps = { { id = 74 } } }, SCENARIO_78 = { steps = { { id = 78 } } },
            SCENARIO_75 = { steps = { { id = 75 } } }, SCENARIO_79 = { steps = { { id = 79 } } },
        },
        ["ui.story.ScenarioDialogue"] = {
            isActive = function() return guard(f.active) end,
            show = function(cfg)
                f.active = true; f.played[#f.played + 1] = cfg
                -- 展示过程中同步广播，队列非空时仍必须守卫，不能抢播。
                f.listeners[1]()
            end,
        },
        ["systems.TutorialManager"] = { canPlayPendingStory = function() return not guard(f.blocked) end },
        ["ui.tutorial.TutorialPageRecovery"] = {
            getStoryPlace = function() guard(false); return "battle" end,
            isPendingStoryBlocked = function() return guard(false) end,
        },
        ["ui.hud.popup.RewardPopup"] = {
            isOpen = function() return guard(false) end,
            hasPendingBattleRewards = function() return guard(false) end,
        },
        ["ui.tavern.TavernPage"] = { isRecruitBusy = function() return guard(false) end },
        ["systems.StoryPlayer"] = { hasPending = function() return guard(false) end },
        ["runtime.ClientDispatcher"] = {
            get = function(key) return f.modules[key] end,
            handleStateUpdate = function(data)
                f.writes = f.writes + 1
                f.modules.session = data.modules.session
                f.module.update() -- 与真实状态刷新相同的同步重入边界。
            end,
        },
        ["boot.StandaloneSave"] = { Flush = function() f.saves = f.saves + 1 end },
        ["core.EventBus"] = { on = function(event, callback)
            eq(event, "scenario_dialogue_finished", "original dialogue subscription retained")
            f.listeners[#f.listeners + 1] = callback
        end },
    }
    f.module = loadIsolated("ui/character/hero/HeroScenario.lua", deps,
        { cjson = { encode = function(value) return value end } })
    f.finish = function()
        local cfg = f.played[#f.played]
        f.active = false
        if cfg.onFinish then cfg.onFinish() end
        f.listeners[1]()
    end
    return f
end

local function testHero()
    local f = heroFixture()
    eq(#f.listeners, 1, "HeroScenario subscribes once")
    for _ = 1, 128 do f.module.update(); f.listeners[1]() end
    f.module.onRecruitResults({})
    eq(f.guards, 0, "empty hero queue skips every playback guard, including event polls")
    eq(f.saves, 0, "empty hero queue does not save")
    f.blocked = true
    local results = { { type = "hero", heroId = 18, isNew = true },
        { type = "hero", heroId = 18, isNew = true }, { type = "hero", heroId = 19, isNew = true } }
    f.module.onRecruitResults(results); f.module.update(); f.listeners[1]()
    check(f.guards > 0 and f.module.hasPending(), "nonempty hero queue still checks blocking")
    eq(#f.played, 0, "blocked heroes do not show")
    eq(f.writes, 0, "blocked heroes are not marked claimed")
    eq(f.saves, 0, "blocked heroes are not saved")
    f.blocked = false; f.module.update()
    eq(#f.played, 1, "unblocking polls play one hero despite synchronous reentry")
    eq(f.played[1].steps[1].id, 74, "FIFO first join")
    f.finish()
    eq(f.played[2].steps[1].id, 78, "first join chains to idle")
    f.finish()
    eq(f.played[3].steps[1].id, 75, "finish subscription drains next distinct hero")
    f.finish()
    eq(f.played[4].steps[1].id, 79, "second join chains to idle")
    f.finish()
    eq(f.writes, 4, "only actually shown scenarios are claimed once")
    eq(f.saves, 4, "only actually shown scenarios save once")
    check(not f.module.hasPending(), "all pending heroes drained")
    local before = f.guards
    f.module.update(); f.listeners[1]()
    eq(f.guards, before, "drained queue stops guard queries again")
    eq(#f.played, 4, "duplicate requests and finish reentry never replay")
    f.blocked = true; f.module.onRecruitResults(results); f.module.resetAll()
    f.blocked = false; before = f.guards; f.module.update(); f.listeners[1]()
    eq(f.guards, before, "reset empty queue does not query guards")
    eq(#f.listeners, 1, "reset retains existing subscription without duplicating it")
end

local function testRoster()
    local f = { roster = {}, teams = {}, reads = 0, scans = 0, visits = 0, ready = true,
        unlocked = 3, observed = {}, observedCalls = 0, callbacks = {} }
    for t = 1, 3 do f.teams[t] = { slots = {} } end
    local function countedIpairs(value)
        if value == f.roster then
            f.scans = f.scans + 1
            local index = 0
            return function()
                index = index + 1
                local entry = value[index]
                if entry ~= nil then f.visits = f.visits + 1; return index, entry end
            end
        end
        return ipairs(value)
    end
    local presentation = {
        reset = noop, finishObservation = noop,
        getFeedback = function() return false, false, 0, 0 end,
        drawHeader = function() return 0, 0 end,
        observe = function(team, slots, _, _, levelFn, ready, locked)
            f.observedCalls = f.observedCalls + 1
            f.callbacks[team] = levelFn
            if ready == false or locked then return end
            for slot = 1, 4 do
                local entry = slots and slots[slot]
                local id = entry and entry.state == "occupied" and entry.heroId or 0
                f.observed[#f.observed + 1] = { id = id, level = id ~= 0 and levelFn(id) or 0 }
            end
        end,
    }
    local draw = loadIsolated("ui/character/panel/CharacterPanelDraw2.lua", {
        ["config.HeroConfig"] = {}, ["config.HeroAssetUtil"] = { ensureIcon = function() return 1 end },
        ["core.DrawUtil"] = { drawTextStroke = noop, drawImageCentered = noop },
        ["core.DarkIcon"] = {}, ["config.ExpTable"] = {},
        ["systems.TutorialManager"] = { getCurrentHighlight = noop },
        ["ui.widget.HeroFrame"] = { draw = noop },
        ["ui.character.panel.CharacterRosterPresentation"] = presentation,
        ["ui.character.panel.CharacterPanel"] = { getEffectiveLevel = function() return 1 end },
        ["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 } },
        ["core.NumberUtil"] = { format = tostring },
    }, { ipairs = countedIpairs, nvgBeginPath = noop, nvgRoundedRect = noop,
        nvgFillColor = noop, nvgFill = noop, nvgStrokeColor = noop, nvgStrokeWidth = noop,
        nvgStroke = noop, nvgRGBA = noop, nvgFontFace = noop, nvgFontSize = noop,
        nvgTextBounds = function() return 0 end, NVG_ALIGN_LEFT = 1, NVG_ALIGN_MIDDLE = 2 })
    draw.setContext({
        getTeams = function() return f.teams end,
        getHeroRoster = function() f.reads = f.reads + 1; return f.roster end,
        getUnlockedTeamCount = function() return f.unlocked end,
        getActiveTeamIdx = function() return 1 end,
        isHeroesDataApplied = function() return f.ready end,
    })
    local function referenceLevel(id)
        for _, entry in ipairs(f.roster) do
            if entry.heroId == id then return entry.level or 1 end
        end
        return 1
    end
    local function render(label, expectedScans)
        f.reads, f.scans, f.visits, f.observedCalls, f.observed = 0, 0, 0, 0, {}
        draw.drawTeamAvatars({})
        eq(f.observedCalls, 3, label .. ": real draw observes all three teams")
        for _, item in ipairs(f.observed) do
            eq(item.level, item.id ~= 0 and referenceLevel(item.id) or 0, label .. ": old lookup oracle")
        end
        eq(f.reads, expectedScans, label .. ": getter once, not once per slot")
        eq(f.scans, expectedScans, label .. ": roster scan once, not twelve times")
        eq(f.visits, expectedScans * #f.roster, label .. ": roster visits linear in roster size")
    end
    f.roster = { { heroId = 1, level = 0, owned = false }, { heroId = 1, level = 90, owned = true },
        { heroId = 2, owned = false }, { heroId = 2, level = 99, owned = true },
        { heroId = 3, level = false }, { heroId = 4, level = 8, owned = false },
        { heroId = "1", level = 17 }, { level = 73 } }
    local ids = {1, 2, 3, 4, "1", 99, 1, 2, 3, 4, "1", 99}
    for t = 1, 3 do
        for s = 1, 4 do f.teams[t].slots[s] = { state = "occupied", heroId = ids[(t - 1) * 4 + s] } end
    end
    render("duplicate/missing/false/zero/string ID/unowned", 1)
    eq(f.observed[1].level, 0, "zero level is not replaced by default")
    eq(f.observed[2].level, 1, "first duplicate without level wins over later level")
    eq(f.observed[4].level, 8, "owned=false is not a filter in original observation")
    check(f.callbacks[1] == f.callbacks[2] and f.callbacks[2] == f.callbacks[3],
        "actual draw shares one callback/index across all teams")
    local oldCallback = f.callbacks[1]
    f.roster[1].level = 23
    f.roster[1], f.roster[2] = f.roster[2], f.roster[1]
    render("next frame in-place update and reorder", 1)
    eq(f.observed[1].level, 90, "next frame sees new first duplicate")
    check(f.callbacks[1] ~= oldCallback, "index does not survive across draw calls")
    f.roster = { { heroId = 1, level = 41 } }
    render("replacement roster and removed IDs", 1)
    for i = 2, 1024 do f.roster[i] = { heroId = i, level = i + 10 } end
    for t = 1, 3 do
        for s = 1, 4 do f.teams[t].slots[s].heroId = 1024 end
    end
    render("twelve deployed slots at end of large roster", 1)
    eq(f.visits, 1024, "1024 entries visited once instead of 12288 visits")
    f.ready = false; render("not ready", 0)
    f.ready, f.unlocked = true, 0; render("all teams locked", 0)
    f.unlocked = 3
    for t = 1, 3 do f.teams[t].slots = {} end
    render("empty teams", 0)
end

function Start()
    local ok, why = pcall(function()
        testTutorial()
        testHero()
        testRoster()
    end)
    if ok then print(TAG .. " ALL PASS: " .. checks .. " assertions")
    else print(TAG .. " FAIL: " .. tostring(why)) end
    engine:Exit()
end
