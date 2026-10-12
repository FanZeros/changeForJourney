-- 专项回归：仅只读生产源码/图片，通过 cache.GetFile + load(env) 创建独立真实模块。
-- /workspace/.cli/UrhoXRuntime tests/story_background_test.lua
--   -tapcode_dir=/workspace/game2 -tool_mode -graphicsheadless
-- 不启动完整Boot、不读取玩家档、不dispatch cloud；绘制出口是语义spy，不冒充截图。
local PREFIX = "[story_background] "
local checks, groups = 0, 0
local failures = {} ---@type string[]
local sources = {} ---@type table<string, string>
local nativeCache = cache
local function check(ok, message)
    checks = checks + 1
    assert(ok, message)
end
local function eq(actual, expected, message)
    check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function near(actual, expected, message)
    check(type(actual) == "number" and math.abs(actual - expected) < 0.00001, message)
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function fileText(path)
    local file = assert(nativeCache:GetFile(path), "missing project file " .. path)
    assert(file:IsOpen(), "cannot open " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function source(name)
    if not sources[name] then sources[name] = fileText(name:gsub("%.", "/") .. ".lua") end
    return sources[name]
end
local function section(name, firstMarker, nextMarker)
    local text = source(name)
    local first = assert(text:find(firstMarker, 1, true), "missing source marker " .. firstMarker)
    local last = assert(text:find(nextMarker, first + #firstMarker, true), "missing boundary " .. nextMarker)
    return text:sub(first, last - 1)
end
local function noop() end
local function bg(index) return string.format("image/剧情/背景/STORY_BG_%02d.png", index) end
local TITLE = "image/界面底板/标题与加载/UI_TITLE_BG_GATE.png"
local LOGO = "image/界面底板/标题与加载/UI_LOGO_TM.png"
-- 独立枚举作为门控 oracle，不从恢复器读取名单，避免漏页时测试同步漏测。
local LEFT_PAGE_CASES = {
    { "教堂", "ui.church.ChurchPage" }, { "古树", "ui.church.talent.TalentPage" },
    { "酒馆", "ui.tavern.TavernPage" }, { "市场", "ui.market.MarketPage" },
    { "遗匣", "ui.loot.LootBoxPage" }, { "任务", "ui.story.task.TaskPage" },
    { "锻炉", "ui.blacksmith.BlacksmithPage" }, { "仓库", "ui.backpack.BackpackPanel" },
}
local HIGH_PRIORITY_CASES = {
    { "ui.hud.popup.OfflineRewardPanel", "isOpen" }, { "ui.hud.popup.UpdateNoticePopup", "isOpen" },
    { "ui.hud.popup.LevelUpPopup", "isOpen" }, { "ui.story.gate.DarkTitleScreenGate", "isOpen" },
    { "ui.story.gate.LetterIntro", "isOpen" }, { "ui.story.gate.IntroCutscene", "isActive" },
    { "ui.dungeon.DungeonBattleScene", "isOpen" }, { "ui.tower.TowerBattleScene", "isActive" },
    { "ui.tavern.TavernPage", "isRecruitConfirmOpen" }, { "ui.battle.stage.SweepDialog", "isOpen" },
    { "ui.battle.popup.DamageStatsPanel", "isOpen" }, { "ui.battle.stage.StageSelectDialog", "isOpen" },
    { "ui.battle.popup.TerminalConfirmDialog", "isOpen" },
}

-- 绘制记录包含最终调用次序、alpha、平移、覆盖区域；不安装全局require/package.loaded桩。
local function newContext()
    local ctx = { deps = {}, calls = {}, loads = {}, responses = {}, handles = {}, nextHandle = 0,
        modules = {}, events = {}, shown = {}, actions = {}, notices = {}, flushes = 0,
        fileAttempts = 0, cloudAttempts = 0, stateUpdates = 0, unexpectedDependencies = {},
        vg = {}, font = 20, stack = {}, tx = 0, ty = 0 } ---@type any
    local env = setmetatable({}, { __index = _G }) ---@type any
    ctx.env = env
    local function record(kind, data)
        data = data or {}
        data.kind, data.tx, data.ty = kind, ctx.tx, ctx.ty
        ctx.calls[#ctx.calls + 1] = data
        return data
    end
    local function blockedFile()
        ctx.fileAttempts = ctx.fileAttempts + 1
        error("isolated test forbids player File/fileSystem IO")
    end
    local function blockedCloud()
        ctx.cloudAttempts = ctx.cloudAttempts + 1
        error("isolated test forbids cloud/network dispatch")
    end
    env.File = blockedFile
    env.fileSystem = setmetatable({}, { __index = function() return blockedFile end })
    env.clientCloud = setmetatable({}, { __index = function() return blockedCloud end })
    env.serverCloud, env.network = env.clientCloud, env.clientCloud
    env.cache = { GetResource = function() error("no audio/GPU resources in semantic test") end,
        GetFile = blockedFile }
    env.nvgCreateImage = function(vg, path)
        local entry = { vg = vg, path = path }
        ctx.loads[#ctx.loads + 1] = entry
        local response = ctx.responses[path]
        if type(response) == "function" then response = response(vg, path) end
        if response == false then return nil end
        if response ~= nil then
            if response >= 0 then ctx.handles[response] = path end
            entry.handle = response
            return response
        end
        local handle = ctx.nextHandle
        ctx.nextHandle = ctx.nextHandle + 1
        ctx.handles[handle], entry.handle = path, handle
        return handle
    end
    env.nvgImageSize = function() return 1920, 1080 end
    env.nvgRGBA = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    env.nvgBeginPath = function() ctx.shape, ctx.paint = nil, nil end
    env.nvgRect = function(_, x, y, w, h) ctx.shape = { x = x, y = y, w = w, h = h } end
    env.nvgRoundedRect = function(_, x, y, w, h) ctx.shape = { x = x, y = y, w = w, h = h, rounded = true } end
    env.nvgFillColor = function(_, color) ctx.color = color end
    env.nvgFillPaint = function(_, paint) ctx.paint = paint end
    env.nvgFill = function() record("fill", { rect = ctx.shape, color = ctx.color, paint = ctx.paint }) end
    env.nvgImagePattern = function(_, x, y, w, h, _, image, alpha)
        record("image", { path = ctx.handles[image], image = image, x = x, y = y, w = w, h = h, alpha = alpha })
        return { image = image }
    end
    env.nvgSave = function()
        ctx.stack[#ctx.stack + 1] = { ctx.tx, ctx.ty }
        record("save")
    end
    env.nvgRestore = function()
        local previous = assert(table.remove(ctx.stack), "unbalanced nvgRestore")
        ctx.tx, ctx.ty = previous[1], previous[2]
        record("restore")
    end
    env.nvgScissor = function(_, x, y, w, h) record("scissor", { x = x, y = y, w = w, h = h }) end
    env.nvgResetScissor = function() record("resetScissor") end
    env.nvgTranslate = function(_, x, y)
        ctx.tx, ctx.ty = ctx.tx + x, ctx.ty + y
        record("translate", { x = x, y = y })
    end
    env.nvgFontSize = function(_, size) ctx.font = size end
    env.nvgText = function(_, x, y, text) record("text", { x = x, y = y, text = text }); return 0 end
    for _, name in ipairs({ "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgFontFace",
        "nvgTextAlign", "nvgTextLineHeight", "nvgMoveTo", "nvgLineTo" }) do env[name] = noop end
    ctx.deps["core.I18n"] = {
        get = function() return "zh_CN" end, lookup = function(text) return text end,
        t = function(text) return text end, displayName = function(id) return id end,
        displayText = env.nvgText,
        displayBounds = function(_, _, _, text) return (utf8.len(text) or 0) * ctx.font end,
    }
    ctx.deps["core.DrawUtil"] = {
        drawImageCover = function(_, image, x, y, w, h, alpha)
            record("image", { path = ctx.handles[image], image = image, x = x, y = y, w = w, h = h, alpha = alpha })
        end,
        drawImageCentered = function(_, image, x, y, w, h, alpha)
            record("image", { path = ctx.handles[image], image = image, x = x, y = y, w = w, h = h, alpha = alpha })
        end,
        drawTextStroke = function(_, x, y, text, _, _, _, _, _, _, opts)
            record("name", { x = x, y = y, text = text, alpha = opts.alpha })
        end,
    }
    ctx.deps["ui.widget.HeroFrame"] = { draw = function(_, opts)
        record("avatar", { path = ctx.handles[opts.iconHandle], alpha = opts.alpha, heroId = opts.heroId })
    end }
    -- HeroConfig仅作为纯美术查询叶子；真实HeroAssetUtil/ScenarioConfig解析路径。
    ctx.deps["config.HeroConfig"] = { get = function(id)
        local names = { [1] = "大狗嚼", [2] = "黄桃龙", [3] = "叮咚鸡", [15] = "复活吧爱人" }
        return { name = names[id] or ("test-hero-" .. id) }
    end }
    ctx.deps["runtime.ClientDispatcher"] = {
        get = function(name) return ctx.modules[name] end,
        handleStateUpdate = function(json)
            ctx.stateUpdates = ctx.stateUpdates + 1
            local data = cjson.decode(json)
            for name, value in pairs(data.modules) do ctx.modules[name] = value end
        end,
    }
    ctx.deps["boot.StandaloneSave"] = { Flush = function() ctx.flushes = ctx.flushes + 1; return true end }
    ctx.clock = { elapsedTime = 100 }
    env.time = ctx.clock
    ctx.deps["systems.TutorialManager"] = {
        canPlayPendingStory = function() return not ctx.tutorialBlocked end,
        isGroupCompleted = function(id) return ctx.foundation and ctx.foundation[id] == true or false end,
    }
    ctx.deps["ui.hud.popup.RewardPopup"] = {
        isOpen = function() return ctx.rewardOpen == true end,
        hasPendingBattleRewards = function() return ctx.rewardPending == true end,
    }
    -- 恢复器加载真实源码；仅显式隔离它查询的高优先级页面和八类建筑叶子。
    -- 关闭请求不清 open，只有页面生命周期真正收尾才变 false，符合生产 isOpen 契约。
    ctx.pageStates, ctx.highPriority = {}, {}
    for _, entry in ipairs(LEFT_PAGE_CASES) do
        local path = entry[2]
        local state = { open = false, closing = false, openTime = 0, closeTime = 0 }
        ctx.pageStates[path] = state
        ctx.deps[path] = {
            isOpen = function() return state.open end,
            open = function()
                state.open, state.closing, state.closeTime = true, false, 0
                state.openTime = ctx.clock.elapsedTime
            end,
            close = function()
                if not state.open or state.closing then return end
                state.closing, state.closeTime = true, ctx.clock.elapsedTime
            end,
            finishClose = function() state.open, state.closing = false, false end,
            getSeamAnim = function() return state.openTime, state.closeTime, 0.3, 0.3 end,
        }
    end
    for _, entry in ipairs(HIGH_PRIORITY_CASES) do
        local path, method = entry[1], entry[2]
        if path ~= "ui.story.gate.LetterIntro" and path ~= "ui.story.gate.DarkTitleScreenGate" then
            ctx.deps[path] = ctx.deps[path] or {}
            ctx.deps[path][method] = function()
                if path == "ui.hud.popup.UpdateNoticePopup" and ctx.recoveryBlocked then return true end
                if path == "ui.hud.popup.OfflineRewardPanel" and ctx.offlineOpen then return true end
                if path == "ui.story.gate.IntroCutscene" and ctx.introActive then return true end
                return ctx.highPriority[path .. ":" .. method] == true
            end
        end
    end
    ctx.deps["ui.tavern.TavernPage"].isRecruitBusy = function() return ctx.recruitBusy == true end
    ctx.deps["boot.BattleRewardOverlay"] = { isBlocked = function() return ctx.battleRewardBlocked == true end }
    ctx.nav = 3
    ctx.deps["ui.hud.BottomNav"] = { getSelectedIndex = function() return ctx.nav end }
    ctx.deps["ui.battle.tri.BattleTriPage"] = { isOpen = function() return ctx.triOpen == true end }
    env.require = function(name)
        if ctx.deps[name] ~= nil then return ctx.deps[name] end
        local permitted = name:match("^config%.") or name == "core.EventBus" or name == "core.I18nStory"
            or name == "ui.story.StoryDisplay" or name == "ui.story.ScenarioDialogue"
            or name == "ui.story.gate.LetterIntro" or name == "ui.story.gate.DarkTitleScreenGate"
            or name == "systems.StoryPlayer" or name == "ui.character.hero.HeroScenario"
            or name == "ui.tutorial.TutorialPageRecovery"
        if not permitted then ctx.unexpectedDependencies[#ctx.unexpectedDependencies + 1] = name end
        assert(permitted, "unexpected dependency blocked: " .. tostring(name))
        local chunk, why = load(source(name), "@" .. name:gsub("%.", "/") .. ".lua", "t", env)
        assert(chunk, why)
        local module = chunk()
        ctx.deps[name] = module
        return module
    end
    function ctx.compile(text, name)
        local chunk, why = load(text, "@" .. name, "t", env)
        assert(chunk, why)
        return chunk()
    end
    ctx.bg = env.require("config.StoryBackgroundConfig")
    ctx.config = env.require("config.ScenarioDialogueConfig")
    ctx.bus = env.require("core.EventBus")
    ctx.dialogue = env.require("ui.story.ScenarioDialogue")
    ctx.dialogue.init(ctx.vg, nil)
    ctx.bus.on("scenario_dialogue_finished", function(event) ctx.events[#ctx.events + 1] = event end)
    local originalShow = ctx.dialogue.show
    ctx.dialogue.show = function(cfg)
        ctx.shown[#ctx.shown + 1] = cfg
        originalShow(cfg)
    end
    ctx.modules.session = { introCompleted = true, initialHeroId = 1, claimedScenarios = {} }
    ctx.modules.battle = { currentStageId = 201, clearedStages = {} }
    ctx.modules.heroes = { roster = {} }
    function ctx.draw(w, h)
        ctx.calls, ctx.stack, ctx.tx, ctx.ty = {}, {}, 0, 0
        ctx.dialogue.draw(w or 1920, h or 1080)
        eq(#ctx.stack, 0, "frame balances save/restore")
        return ctx.calls
    end
    function ctx.loadCount(path)
        local count = 0
        for _, entry in ipairs(ctx.loads) do if entry.path == path then count = count + 1 end end
        return count
    end
    function ctx.assertSafe()
        eq(ctx.fileAttempts, 0, "no player save File/fileSystem access")
        eq(ctx.cloudAttempts, 0, "no cloud/network dispatch")
        eq(#ctx.unexpectedDependencies, 0, "未知依赖即使被生产 pcall 捕获也不能绕过隔离")
    end
    return ctx
end
local function find(ctx, kind, path)
    for index, call in ipairs(ctx.calls) do
        if call.kind == kind and (path == nil or call.path == path) then return call, index end
    end
    return nil, nil
end
local function images(ctx, path)
    local result = {}
    for _, call in ipairs(ctx.calls) do
        if call.kind == "image" and (not path or call.path == path) then result[#result + 1] = call end
    end
    return result
end
local function firstMask(ctx)
    for _, call in ipairs(ctx.calls) do
        if call.kind == "fill" and call.rect and not call.rect.rounded then return call end
    end
    return nil
end
local function bar(ctx)
    for index, call in ipairs(ctx.calls) do
        if call.kind == "fill" and call.rect and call.rect.rounded
            and call.color.r == 10 and call.color.g == 8 then return call, index end
    end
    return nil, nil
end
local function portraitPath(ctx, step)
    local appearance = ctx.config.getAppearance(step)
    return appearance.portraitPath or ctx.env.require("config.HeroAssetUtil").getPortraitPath(appearance.heroId)
end
local function sample(ctx, mode, background, onFinish, extras)
    local cfg = { mode = mode, background = background, steps = ctx.config.SCENARIO_38.steps,
        onFinish = onFinish }
    for key, value in pairs(extras or {}) do cfg[key] = value end
    ctx.dialogue.reset()
    ctx.dialogue.show(cfg)
    return cfg
end
local function finish(ctx)
    local _, total = ctx.dialogue.getProgress()
    for _ = 1, total do ctx.dialogue.update(100); ctx.dialogue.advance() end
    if ctx.dialogue.isActive() then ctx.dialogue.update(0.31) end
end

local function configCases()
    local ctx = newContext()
    ---@type (number|boolean)[]
    local expected = { 2,2,2,2,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,4,4,4,5,5,5,5,6,5,5,5,
        7,5,5,5,9,9,9,3,3,3,9,9,9,9,9,9,8,5,5,5,10,10,10,false,13,13,13,12,12,12,
        14,14,3,10,15,false,16,14,14,3,3,10,11,17,17,17,17,17,17,17,17,10 }
    eq(#expected, 82, "explicit ID oracle includes both holes")
    local count, steps = 0, #ctx.config.OPENING.steps
    for _, cfg in ipairs(ctx.config.OPENING_JOINS) do
        eq(cfg.background, ctx.bg.HALL, "opening joins use HALL")
        eq(cfg.mode, "large", "opening joins retain large")
        steps = steps + #cfg.steps
    end
    for id = 1, 82 do
        local path = expected[id] and bg(expected[id]) or nil
        eq(ctx.bg.forScenario(id), path, "scenario mapping " .. id)
        local cfg = ctx.config["SCENARIO_" .. id]
        if path then
            count, steps = count + 1, steps + #cfg.steps
            eq(cfg.background, path, "config background " .. id)
            check(cfg.mode == "small" or cfg.mode == "large", "original mode present " .. id)
        else eq(cfg, nil, "removed scenario remains absent " .. id) end
    end
    eq(count, 80, "80 numbered scenarios, no 54/66 resurrection")
    eq(steps, 196, "84 configs retain 196 original lines")
    eq(ctx.bg.STUDY, bg(1), "STUDY")
    eq(ctx.bg.HALL, bg(2), "HALL")
    eq(ctx.bg.DEFAULT, bg(3), "DEFAULT")
    eq(ctx.bg.forScenario(0), nil, "unknown zero ID")
    eq(ctx.bg.forScenario(83), nil, "unknown new ID")
    eq(ctx.config.OPENING.background, "image/剧情/开场三人CG.png", "opening keeps existing CG path")
    eq(ctx.config.OPENING.backgroundIsCg, true, "opening explicit CG flag")
    eq(ctx.config.SCENARIO_1.eyeOpen, true, "legacy eyeOpen retained")
    eq(ctx.config.SCENARIO_82.rewards[1].amount, 10, "82 shard reward unchanged")
    local stage = ctx.env.require("config.StageConfig")
    local overrides = { [1] = 3, [2] = 10, [3] = 11, [4] = 15, [6] = 16, [13] = 13 }
    for chapter = 1, stage.TOTAL_CHAPTERS do
        for _, position in ipairs({ 1, 5 }) do
            local entry = assert(stage.getStageByChapter(chapter, position), "real StageConfig entry")
            local relative = ((entry.chapter - 1) % 23) + 1
            local want = overrides[relative] and bg(overrides[relative]) or stage.getBattleBackground(entry.id)
            eq(ctx.bg.forStage(entry.id), want, "forStage real relative chapter " .. chapter .. "/" .. position)
            eq(ctx.bg.forStage(tostring(entry.id)), want, "forStage string ID " .. entry.id)
        end
    end
    for tier = 1, 14 do eq(ctx.bg.forStage(tier * 1000 - 1), bg(14), "terminal tier " .. tier) end
    eq(ctx.bg.forStage(nil), bg(3), "nil stage defaults safely")
    eq(ctx.bg.forStage("invalid"), bg(3), "invalid stage defaults safely")
    ctx.assertSafe()
end
local function assetCases()
    local uuids = {}
    for index = 1, 18 do
        local path = index <= 17 and bg(index) or TITLE
        local image = assert(nativeCache:GetResource("Image", path), "resource image missing " .. path)
        eq(image.width, 1920, "PNG width " .. path)
        eq(image.height, 1080, "PNG height " .. path)
        local meta = cjson.decode(fileText(path .. ".meta"))
        check(type(meta.uuid) == "string" and meta.uuid ~= "" and not uuids[meta.uuid], "unique meta " .. path)
        uuids[meta.uuid] = true
        if index == 18 then eq(meta.uuid, "BQ8tKQY6Tzcboc1rDEFdRu5F", "title same path preserves original meta UUID") end
    end
end
local function frameCases()
    local ctx = newContext()
    local called = 0
    local cfg = sample(ctx, "small", bg(13), function() called = called + 1 end)
    local original = copy(cfg.steps)
    local path = portraitPath(ctx, cfg.steps[1])
    ctx.draw()
    eq(#images(ctx, bg(13)), 1, "small explicit bg from very first frame")
    eq(#images(ctx, path), 0, "small first entrance starts at alpha0, not cancelled")
    eq(firstMask(ctx).color.a, 255, "explicit background opaque foundation")
    eq(ctx.dialogue.isFullscreen(), false, "small background does not change mode")
    ctx.dialogue.update(0.125); ctx.draw()
    local portrait, pi = find(ctx, "image", path)
    check(portrait ~= nil, "small entering portrait visible halfway")
    near(portrait.alpha, 0.875, "legacy easeOutCubic entrance alpha")
    near(portrait.x, 1920 * (0.30 + 0.045 * 0.125), "legacy entrance slide preserved")
    local backdrop, bi = find(ctx, "image", bg(13))
    local _, bari = bar(ctx)
    local avatar, ai = find(ctx, "avatar")
    check(bi < pi and pi < bari and bari < ai, "layer order bg < entering portrait < dialogue bar < avatar")
    near(backdrop.w, 1920, "bg covers frame width")
    near(backdrop.h, 1080, "bg covers frame height")
    near(portrait.h, 1080 * 0.72, "small portrait original size")
    near(avatar.alpha, 1, "avatar original visibility")
    eq(called, 0, "loading/drawing never finishes or awards")
    ctx.dialogue.update(0.125); ctx.draw()
    near(find(ctx, "image", path).alpha, 1, "entrance completes at 0.25s")
    ctx.dialogue.advance(); ctx.draw()
    local firstText = cfg.steps[1].text
    local concatenated = ""
    for _, call in ipairs(ctx.calls) do if call.kind == "text" then concatenated = concatenated .. call.text end end
    check(concatenated:find(firstText, 1, true), "original first line fully accessible")
    ctx.dialogue.advance(); ctx.dialogue.update(0.125); ctx.draw()
    near(find(ctx, "image", path).alpha, 0.875, "old speaker retains exit animation")
    eq(#images(ctx, bg(13)), 1, "background stable across speaker change")
    ctx.dialogue.update(0.125); ctx.dialogue.update(0.125); ctx.draw()
    check(find(ctx, "image", portraitPath(ctx, cfg.steps[2])) ~= nil, "next speaker enters normally")
    finish(ctx)
    eq(called, 1, "small natural dismissal completes once")
    eq(ctx.events[1].reason, "dismissed", "small keeps dismissed event")
    check(same(cfg.steps, original), "drawing/advance never changes original steps")
    ctx.dialogue.skip(); ctx.dialogue.advance(); ctx.dialogue.update(10)
    eq(called, 1, "after finish duplicate interactions are inert")
    ctx.draw(); eq(#ctx.calls, 0, "closed scene draws nothing")

    sample(ctx, "small", nil)
    local defaultBefore = ctx.loadCount(ctx.bg.DEFAULT)
    ctx.dialogue.update(0.3); ctx.draw()
    eq(firstMask(ctx).color.a, 150, "small without bg retains original black mask")
    eq(ctx.loadCount(ctx.bg.DEFAULT), defaultBefore, "small without bg does not request DEFAULT")
    eq(#images(ctx), 1, "no residual previous explicit background")
    sample(ctx, "large", nil)
    ctx.dialogue.update(0.3); ctx.draw()
    eq(#images(ctx, ctx.bg.DEFAULT), 1, "large nil bg loads/draws DEFAULT")
    near(find(ctx, "image", path).h, 1080 * 0.92, "large keeps original portrait size")
    check(ctx.dialogue.isFullscreen(), "large remains fullscreen")
    ctx.assertSafe()
end
local function allScenarioFrames()
    local ctx = newContext()
    local count = 0
    for id = 1, 82 do
        local cfg = ctx.config["SCENARIO_" .. id]
        if cfg then
            local snapshot = copy(cfg)
            ctx.dialogue.reset(); ctx.dialogue.show(cfg)
            ctx.dialogue.update(0.3)
            for _, size in ipairs({ { 844, 390 }, { 1920, 1080 } }) do
                ctx.draw(size[1], size[2])
                local backdrop, bi = find(ctx, "image", cfg.background)
                local _, bari = bar(ctx)
                check(backdrop ~= nil, "all80 first visible frame has configured environment " .. id)
                near(backdrop.w, size[1], "all80 background uses supplied logical width " .. id)
                near(backdrop.h, size[2], "all80 background uses supplied logical height " .. id)
                if bari then check(bi < bari, "all80 environment below dialogue " .. id) end
                eq(ctx.dialogue.isFullscreen(), cfg.mode == "large", "all80 keeps mode " .. id)
                eq(ctx.dialogue.getProgress(), 1, "all80 first frame not step advance " .. id)
            end
            ctx.dialogue.skip()
            check(same(cfg, snapshot), "all80 rendering never mutates lines/mode/rewards " .. id)
            count = count + 1
        end
    end
    eq(count, 80, "all80 production configs exercised at two logical sizes")
    ctx.assertSafe()
end
local function dismissalCases()
    for _, background in ipairs({ bg(5), false, "missing-small.png" }) do
        local ctx = newContext()
        ctx.responses["missing-small.png"] = -1
        local finishes = 0
        sample(ctx, "small", background or nil, function() finishes = finishes + 1 end,
            { steps = { ctx.config.SCENARIO_38.steps[1] } })
        ctx.dialogue.update(100); ctx.dialogue.advance(); ctx.draw()
        eq(finishes, 0, "small completion still waits for 0.3s dismissal")
        ctx.dialogue.update(0.15); ctx.draw()
        local alpha = 1 - 0.5 ^ 3
        near(firstMask(ctx).color.a, math.floor((background == bg(5) and 255 or 150) * alpha), "foundation fades")
        local portrait = find(ctx, "image", portraitPath(ctx, ctx.config.SCENARIO_38.steps[1]))
        near(portrait.alpha, alpha, "portrait same dismiss alpha")
        near(portrait.ty, 1080 * 0.06 * 0.5 ^ 3, "legacy dismiss slide retained")
        near(bar(ctx).color.a, math.floor(214 * alpha), "bar fades with background")
        near(find(ctx, "avatar").alpha, alpha, "avatar fades with background")
        if background == bg(5) then near(find(ctx, "image", bg(5)).alpha, alpha, "explicit background fades") end
        ctx.dialogue.advance(); ctx.dialogue.update(0.14)
        eq(finishes, 0, "dismiss 0.29s plus repeated tap cannot award")
        ctx.dialogue.update(0.02)
        eq(finishes, 1, "dismiss complete even if background missing")
        ctx.dialogue.skip(); ctx.dialogue.update(1)
        eq(finishes, 1, "missing/present background never duplicates callback")
        eq(#ctx.events, 1, "dismiss event once")
        sample(ctx, "small", background or nil, function() finishes = finishes + 1 end)
        ctx.dialogue.skip(); ctx.dialogue.skip()
        eq(finishes, 2, "active skip callback once regardless background load")
        sample(ctx, "small", background or nil, function() finishes = finishes + 1 end)
        ctx.dialogue.reset(); ctx.dialogue.update(1); ctx.dialogue.skip()
        eq(finishes, 2, "hard reset never invokes finish/reward")
        ctx.assertSafe()
    end
end
local function eyeCases()
    local ctx = newContext()
    sample(ctx, "small", bg(2), nil, { eyeOpen = true })
    ctx.draw()
    eq(#images(ctx, bg(2)), 1, "eyeOpen still renders environment behind lids")
    eq(#images(ctx, portraitPath(ctx, ctx.config.SCENARIO_38.steps[1])), 1, "eyeOpen uses static portrait, not removed")
    eq(bar(ctx), nil, "eyeOpen hides dialogue")
    local fills = {}
    for _, call in ipairs(ctx.calls) do if call.kind == "fill" then fills[#fills + 1] = call end end
    eq(#fills, 3, "eyeOpen foundation plus two lids")
    eq(fills[2].rect.h, 540, "first frame upper eyelid half height")
    eq(fills[3].rect.y, 540, "first frame lower eyelid half height")
    ctx.dialogue.update(1); ctx.draw()
    eq(bar(ctx), nil, "1s eyeOpen still no dialogue")
    ctx.dialogue.update(1); ctx.dialogue.update(1.99); ctx.draw()
    eq(bar(ctx), nil, "eyeHold retains 2s pre-dialogue wait")
    ctx.dialogue.update(0.02); ctx.dialogue.update(0.1); ctx.draw()
    check(bar(ctx) ~= nil, "eyeOpen plus hold naturally reveals dialogue")
    eq(ctx.dialogue.getProgress(), 1, "eyeOpen does not advance source step")
    sample(ctx, "small", bg(2), nil, { eyeOpen = true })
    ctx.dialogue.advance(); ctx.draw()
    check(bar(ctx) ~= nil, "tap skips eyeOpen without removing legacy animation option")
    eq(ctx.dialogue.getProgress(), 1, "skip eyeOpen not a dialogue step skip")
    ctx.assertSafe()
end
local function cacheCases()
    local ctx = newContext()
    sample(ctx, "small", bg(4)); ctx.dialogue.update(0.3); ctx.draw()
    eq(find(ctx, "image", bg(4)).image, 0, "successful image handle0 is rendered")
    local loads = ctx.loadCount(bg(4))
    for _ = 1, 3 do ctx.draw(); ctx.dialogue.reset(); ctx.dialogue.show(ctx.config.SCENARIO_20) end
    eq(ctx.loadCount(bg(4)), loads, "success cached across frames/reset/reopen")
    ctx.dialogue.init(ctx.vg, nil); ctx.dialogue.show(ctx.config.SCENARIO_20)
    eq(ctx.loadCount(bg(4)), loads, "same vg preserves background cache")
    local changed = {}
    ctx.dialogue.init(changed, nil); ctx.dialogue.show(ctx.config.SCENARIO_20)
    eq(ctx.loadCount(bg(4)), loads + 1, "changed vg clears background handle cache")
    eq(ctx.loads[#ctx.loads].vg, changed, "background rebuilt in new context")
    for _, missingValue in ipairs({ -1, false }) do
        local other = newContext()
        other.responses["missing.png"] = missingValue
        sample(other, "small", "missing.png")
        eq(other.loadCount("missing.png"), 1, "missing small image attempted")
        other.draw()
        eq(firstMask(other).color.a, 150, "missing small fallback black mask")
        eq(other.loadCount(bg(3)), 0, "missing small not forced to large default")
        for _ = 1, 3 do other.draw() end
        eq(other.loadCount("missing.png"), 1, "frames do not continually retry missing image")
        sample(other, "small", "missing.png")
        eq(other.loadCount("missing.png"), 2, "missing is not negatively cached, reopen retries")
        other.responses["missing.png"] = nil
        sample(other, "small", "missing.png"); other.draw()
        eq(#images(other, "missing.png"), 1, "restored small background succeeds on reopen")
        sample(other, "small", "missing.png")
        eq(other.loadCount("missing.png"), 3, "recovered image now cached")
        other.assertSafe()
    end
    local other = newContext()
    other.responses["broken-large.png"] = -1
    sample(other, "large", "broken-large.png"); other.dialogue.update(0.3); other.draw()
    eq(#images(other, bg(3)), 1, "missing large explicitly falls back DEFAULT")
    eq(other.loadCount("broken-large.png"), 1, "large original attempted")
    sample(other, "large", "broken-large.png")
    eq(other.loadCount("broken-large.png"), 2, "large failed path retries on reopen")
    eq(other.loadCount(bg(3)), 1, "large successful fallback cached")
    other.responses["broken-large.png"] = nil
    sample(other, "large", "broken-large.png"); other.draw()
    eq(#images(other, "broken-large.png"), 1, "restored explicit large replaces fallback")
    ctx.assertSafe(); other.assertSafe()
end
local function cgCases()
    local ctx = newContext()
    local cfg = ctx.config.OPENING
    ctx.dialogue.show(cfg); ctx.dialogue.update(0.3); ctx.draw()
    eq(#images(ctx, cfg.background), 1, "direct OPENING CG draws exactly once")
    eq(#images(ctx), 1, "direct OPENING flag suppresses portrait only, no name guessing")
    check(find(ctx, "avatar") ~= nil and bar(ctx) ~= nil, "CG retains original avatar/dialogue")
    eq(ctx.shown[1].steps, cfg.steps, "direct cfg steps retain identity")
    for index = 1, #cfg.steps do
        ctx.dialogue.update(100); ctx.draw()
        eq(#images(ctx), 1, "CG remains single image every dialogue frame " .. index)
        ctx.dialogue.advance()
    end
    eq(ctx.events[1].reason, "finished", "large CG finishes normally")
    sample(ctx, "small", "environment-CG-in-name.png")
    ctx.dialogue.update(0.3); ctx.draw()
    eq(#images(ctx), 2, "background name containing CG without flag does not suppress portrait")
    sample(ctx, "small", "neutral-environment.png", nil, { backgroundIsCg = true })
    ctx.dialogue.update(0.3); ctx.draw()
    eq(#images(ctx), 1, "explicit flag independent of CG filename")
    ctx.responses[cfg.background] = -1
    local fresh = {}; ctx.dialogue.init(fresh, nil)
    ctx.dialogue.show(cfg); ctx.dialogue.update(0.3); ctx.draw()
    eq(#images(ctx, bg(3)), 1, "missing opening CG falls back environment DEFAULT")
    eq(#images(ctx), 2, "missing CG fallback restores ordinary portrait")
    sample(ctx, "small", bg(3), nil, { steps = { { characterId = 1, name = "大狗嚼", text = "legacy", cg = "legacy-cg.png" } } })
    ctx.dialogue.update(0.3); ctx.draw()
    eq(#images(ctx, "legacy-cg.png"), 1, "legacy step.cg contract remains supported")
    eq(#images(ctx, portraitPath(ctx, ctx.config.SCENARIO_38.steps[1])), 0, "legacy step.cg suppresses portrait")
    ctx.assertSafe()
end

local function wipeCases()
    for hero = 1, 3 do
        local ctx = newContext()
        ctx.modules.session.initialHeroId = hero
        local story = ctx.env.require("systems.StoryPlayer")
        local calls, realForStage = {}, ctx.bg.forStage
        ctx.bg.forStage = function(id) calls[#calls + 1] = id; return realForStage(id) end
        local original = ctx.config["SCENARIO_" .. (37 + hero)]
        local snapshot = copy(original)
        story.onWipe("1305")
        ctx.modules.battle.currentStageId = 4805
        story.onWipe(4805)
        eq(#calls, 1, "duplicate wipe never overrides first captured background hero " .. hero)
        eq(calls[1], "1305", "forStage receives exact failure-time stage argument")
        local item = assert(story.take(), "successful wipe queue item")
        eq(item.scenarioId, 37 + hero, "wipe hero branch unchanged")
        eq(item.config.background, bg(13), "delayed take not drifted to current player stage")
        check(item.config ~= original, "dynamic wipe shallow-copies config")
        eq(item.config.steps, original.steps, "dynamic take keeps exact steps table")
        eq(item.config.rewards, original.rewards, "dynamic take keeps exact rewards table")
        for key, value in pairs(original) do if key ~= "background" then eq(item.config[key], value, "only background overrides " .. key) end end
        check(same(original, snapshot), "production source config not mutated")
        eq(story.take(), nil, "wipe queue deduplicated")
        story.enqueue(37 + hero)
        eq(story.take().config, original, "taken capture cleared, normal requeue has original config")
        story.enqueue(37 + hero); story.onWipe(201)
        eq(story.take().config, original, "failed duplicate enqueue cannot set capture")
        eq(#calls, 1, "forStage only called when enqueue succeeds")
        ctx.modules.session.introCompleted = false
        story.onWipe(201)
        eq(#calls, 1, "intro gate blocks capture")
        eq(story.take(), nil, "intro gate still prevents dialogue")
        ctx.modules.session.introCompleted = true
        ctx.modules.session.claimedScenarios[tostring(37 + hero)] = true
        story.onWipe(201)
        eq(#calls, 1, "claimed gate blocks capture")
        eq(story.take(), nil, "claimed wipe never requeues")
        ctx.assertSafe()
    end
    local ctx = newContext()
    local story = ctx.env.require("systems.StoryPlayer")
    story.onWipe(999)
    eq(story.take().config.background, bg(14), "terminal wipe gets terminal background")
    eq(story.onWipe(nil), false, "同会话首次团灭已take但未领取时仍阻止重复排队")
    eq(story.take(), nil, "重复团灭不覆盖首次失败地点")
    story.resetWipe()
    story.onWipe(nil)
    eq(story.take().config.background, bg(3), "unknown wipe does not consult saved battle stage")
    ctx.modules.session.scenarioRewardsGranted = { [82] = true }
    eq(story.enqueue(82), false, "reward-granted ledger still blocks82")
    ctx.modules.session.scenarioRewardsGranted = {}
    ctx.modules.session.claimedScenarios[82] = true
    check(story.enqueue(82), "82 preclaimed with empty granted remains retryable")
    eq(story.take().config, ctx.config.SCENARIO_82, "82 ordinary reward config remains original")
    ctx.assertSafe()
end
local function wipeBootCases()
    local ctx = newContext()
    local story = ctx.env.require("systems.StoryPlayer")
    ctx.env.StageConfig = ctx.env.require("config.StageConfig")
    local callback
    ctx.env.BattleScene = {
        getCurrentStageId = function() return ctx.modules.battle.currentStageId end,
        setOnAllDead = function(fn) callback = fn end,
    }
    ctx.env.showKeptDrops = function()
        -- 模拟奖励弹窗/状态刷新同步切关，Boot必须在此前捕获失败关。
        ctx.modules.battle.currentStageId = 4805
    end
    local block = section("boot.StandaloneBoot", "    BattleScene.setOnAllDead(function()", "\n    BattleScene.setOnStageLoaded")
    ctx.compile(block, "production-all-dead")
    check(type(callback) == "function", "real Boot setOnAllDead callback registered")
    ctx.modules.battle.currentStageId = 1305
    callback()
    eq(ctx.modules.battle.currentStageId, 4805, "kept-drops leaf really changes stage during callback")
    eq(story.take().config.background, bg(13), "Boot captures stage before showKeptDrops, not afterward")
    ctx.assertSafe()
end
local function pendingBoot(ctx)
    -- 三类队列出口记录读取次数；后续剧情泵永远不读取旧延播开场。
    ctx.pendingReads = { scenario = 0, follow = 0, story = 0, deferred = 0 }
    local story = ctx.env.require("systems.StoryPlayer")
    local take, takeDeferred = story.take, story.takeDeferredOpening
    story.take = function(place)
        ctx.pendingReads.story = ctx.pendingReads.story + 1
        return take(place)
    end
    story.takeDeferredOpening = function()
        ctx.pendingReads.deferred = ctx.pendingReads.deferred + 1
        return takeDeferred()
    end
    ctx.env.ClientDispatcher = ctx.deps["runtime.ClientDispatcher"]
    ctx.env.ScenarioDialogue = ctx.dialogue
    ctx.env.TutorialManager = ctx.deps["systems.TutorialManager"]
    ctx.env.LetterIntro = { isOpen = function() return ctx.letterOpen end }
    ctx.env.IntroCutscene = { isActive = function() return ctx.introActive end }
    ctx.env.RewardPopup = { isOpen = function() return ctx.rewardOpen end,
        hasPendingBattleRewards = function() return ctx.rewardPending end }
    ctx.env.OfflineRewardPanel = { isOpen = function() return ctx.offlineOpen end }
    ctx.env.ClientMsgHandler = {
        consumePendingScenarioDialogue = function()
            ctx.pendingReads.scenario = ctx.pendingReads.scenario + 1
            return table.remove(ctx.pending or {}, 1)
        end,
        consumePendingFollowUpDialogue = function()
            ctx.pendingReads.follow = ctx.pendingReads.follow + 1
            return table.remove(ctx.followPending or {}, 1)
        end,
        setPendingTutorialNotify = function(id) ctx.notices[#ctx.notices + 1] = id end,
    }
    ctx.env.localSendAction = function(action, params)
        ctx.actions[#ctx.actions + 1] = { action = action, params = params }
        return false -- 失败的本地领奖出口也不能修改剧情背景/提前发奖；绝不转发真实cloud。
    end
    local text = section("boot.Standalone", "local function tryPlayPendingStory_()", "\n--- [LetterIntro]")
    return ctx.compile(text .. "\nreturn tryPlayPendingStory_", "production-pending-story")
end
local function rewardGateCases()
    for _, gate in ipairs({ "tutorialBlocked", "letterOpen", "introActive", "rewardOpen", "rewardPending", "offlineOpen", "recoveryBlocked" }) do
        local ctx = newContext()
        local story = ctx.env.require("systems.StoryPlayer")
        story.onWipe(1305)
        ctx[gate] = true
        local play = pendingBoot(ctx)
        play()
        eq(#ctx.shown, 0, "unchanged reward/intro/tutorial gate " .. gate)
        eq(#ctx.actions, 0, "blocked background does not dispatch reward " .. gate)
        ctx.modules.battle.currentStageId = 4805
        ctx[gate] = false
        play()
        eq(ctx.shown[1].background, bg(13), "gate delay retains captured failure scene " .. gate)
        eq(ctx.shown[1].steps, ctx.config.SCENARIO_38.steps, "Boot retains original steps")
        eq(ctx.shown[1].mode, ctx.config.SCENARIO_38.mode, "Boot preserves mode")
        eq(#ctx.actions, 0, "show alone never claims")
        finish(ctx)
        eq(#ctx.actions, 1, "only finish invokes local claim")
        eq(ctx.actions[1].action, "claim_scenario_reward", "original claim action")
        eq(ctx.actions[1].params.scenarioId, 38, "original scenario reward ID")
        eq(ctx.actions[1].params.preClaimed, true, "original preClaimed flag")
        ctx.dialogue.skip(); ctx.dialogue.update(1)
        eq(#ctx.actions, 1, "failed claim callback still invoked at most once")
        eq(#ctx.notices, 1, "original tutorial notify still once")
        ctx.assertSafe()
    end
    local ctx = newContext()
    local play = pendingBoot(ctx)
    ctx.pending = { { scenarioId = 1, config = ctx.config.SCENARIO_1 } }
    play(); ctx.draw()
    eq(ctx.shown[1].eyeOpen, true, "pending Boot forwards legacy eyeOpen")
    eq(bar(ctx), nil, "forwarded eyeOpen really hides dialogue during entry")
    ctx.assertSafe()
end
local function assertPendingPaused(ctx, sessionBefore, message, storyProbes)
    eq(#ctx.shown, 0, message .. "：不展示")
    for name, count in pairs(ctx.pendingReads) do
        eq(count, name == "story" and (storyProbes or 0) or 0, message .. "：所属查询不消费队列 " .. name)
    end
    eq(ctx.stateUpdates, 0, message .. "：不发布预标记或82台账")
    eq(ctx.flushes, 0, message .. "：不落档")
    eq(#ctx.actions, 0, message .. "：不发奖")
    eq(#ctx.notices, 0, message .. "：不伪造教程领奖通知")
    check(same(ctx.modules.session, sessionBefore), message .. "：完整session保持原样")
end
local function buildingGateCases()
    local ctx = newContext()
    local recovery = ctx.env.require("ui.tutorial.TutorialPageRecovery")
    local owners = { ["ui.church.ChurchPage"] = "church", ["ui.tavern.TavernPage"] = "tavern",
        ["ui.blacksmith.BlacksmithPage"] = "smith" }
    eq(#LEFT_PAGE_CASES, 8, "八类建筑页独立枚举完整")
    eq(recovery.isBlocked(), false, "无高优先级页面时原恢复器不阻挡")
    eq(recovery.getStoryPlace(), "battle", "三行未开时主线页归战场")
    ctx.triOpen = true
    eq(recovery.getStoryPlace(), "battle_town", "默认nav3真实三行同时归城镇和战场")
    eq(recovery.isPendingStoryBlocked("battle_town"), false, "三行布局本身不阻挡普通剧情")
    ctx.nav = 5
    eq(recovery.getStoryPlace(), "battle", "其他页签不因三行旧状态误归双上下文")
    ctx.triOpen = false
    ctx.nav = 4
    eq(recovery.getStoryPlace(), "town", "城镇页归城镇")
    eq(recovery.isPendingStoryBlocked("town"), false, "全部关闭时允许城镇待播")
    for _, entry in ipairs(LEFT_PAGE_CASES) do
        local label, path = entry[1], entry[2]
        local p, owner = ctx.deps[path], owners[path]
        p.open()
        eq(recovery.isBlocked(), false, label .. "：原教程门控仍放行，不抢教程建筑页")
        eq(recovery.isPendingStoryBlocked(), true, label .. "：无所属上下文不豁免")
        eq(recovery.getStoryPlace(), owner or "other", label .. "：按实际菜单定位")
        for _, place in ipairs({ "battle", "town", "church", "tavern", "smith", "battle_town" }) do
            eq(recovery.isPendingStoryBlocked(place), place ~= owner, label .. "：只豁免所属菜单 " .. place)
        end
        p.close()
        eq(p.isOpen(), true, label .. "：close启动动画不等于真正关闭")
        eq(recovery.getStoryPlace(), "other", label .. "：关闭动画不算所属菜单")
        ctx.clock.elapsedTime = ctx.clock.elapsedTime + 10
        eq(recovery.isPendingStoryBlocked(owner or "battle"), true, label .. "：超时也等真实生命周期收尾")
        p.finishClose()
        eq(recovery.isPendingStoryBlocked("town"), false, label .. "：真实关闭后放行")
    end
    local smith, bag, tavern = ctx.deps["ui.blacksmith.BlacksmithPage"],
        ctx.deps["ui.backpack.BackpackPanel"], ctx.deps["ui.tavern.TavernPage"]
    smith.open(); bag.open()
    eq(recovery.getStoryPlace(), "smith", "锻炉联动仓库仍归锻炉")
    eq(recovery.isPendingStoryBlocked("smith"), false, "锻炉只豁免本页和联动仓库")
    eq(recovery.isPendingStoryBlocked("tavern"), true, "仓库不因错误所属获得豁免")
    bag.close()
    eq(recovery.isPendingStoryBlocked("smith"), true, "联动仓库关闭动画继续挡")
    bag.finishClose(); tavern.open()
    eq(recovery.isPendingStoryBlocked("smith"), true, "锻炉所属不能豁免另一个酒馆")
    eq(recovery.isPendingStoryBlocked("tavern"), true, "酒馆所属不能豁免另一个锻炉")
    smith.finishClose(); tavern.finishClose()
    -- 锻炉错峰滑入将开放时间推后0.12秒；早关必须优先读真实closing，不能放宽门禁。
    local smithState = ctx.pageStates["ui.blacksmith.BlacksmithPage"]
    local originalSeam = smith.getSeamAnim
    smith.isClosing = function() return smithState.closing end
    smith.getSeamAnim = function()
        return smithState.openTime + 0.12, smithState.closeTime, 0.3, 0.3
    end
    smith.open(); bag.open()
    eq(smith.isClosing(), false, "锻炉显式getter开放时不是关闭中")
    eq(recovery.getStoryPlace(), "smith", "锻炉未来开放时间不误挡正常所属")
    eq(recovery.isPendingStoryBlocked("smith"), false, "正常锻炉仍精确豁免联动仓库")
    ctx.clock.elapsedTime = ctx.clock.elapsedTime + 0.04
    smith.close()
    local opened, closed = smith.getSeamAnim()
    check(opened > ctx.clock.elapsedTime, "早关时错峰开放时间确实仍在未来")
    check(closed > 0 and closed < opened, "早关时间小于开放时间，时间戳回退无法识别")
    eq(smith.isOpen(), true, "锻炉早关动画尚未收尾")
    eq(smith.isClosing(), true, "锻炉显式getter保留真实关闭状态")
    eq(recovery.getStoryPlace(), "other", "锻炉未来开放时间早关必须归other")
    eq(recovery.isPendingStoryBlocked("smith"), true, "锻炉早关不能豁免自身或联动仓库")
    bag.finishClose()
    eq(recovery.getStoryPlace(), "other", "仓库收尾后锻炉早关仍归other")
    eq(recovery.isPendingStoryBlocked("smith"), true, "独立锻炉早关仍阻挡所属剧情")
    smith.finishClose(); smith.open()
    -- 显式false也优先于旧时间戳，证明getter不是只在true时附加检查。
    smithState.closeTime = smithState.openTime + 0.2
    eq(recovery.getStoryPlace(), "smith", "显式开放状态优先于残留关闭时间戳")
    eq(recovery.isPendingStoryBlocked("smith"), false, "真实重新开放后精确放行锻炉")
    smith.finishClose()
    smith.isClosing, smith.getSeamAnim = nil, originalSeam
    for _, entry in ipairs(HIGH_PRIORITY_CASES) do
        local path, method = entry[1], entry[2]
        local original = ctx.env.require(path)[method]
        ctx.deps[path][method] = function() return true end
        eq(recovery.isBlocked(), true, "原高优先级门控保持 " .. path)
        for _, place in ipairs({ "battle", "town", "church", "tavern", "smith", "battle_town" }) do
            eq(recovery.isPendingStoryBlocked(place), true, "所属菜单不能绕过高优先级 " .. path .. "/" .. place)
        end
        if path == "ui.battle.stage.StageSelectDialog" then
            eq(recovery.isBlocked("tab_dungeon"), false, "原副本教程选关豁免保留")
            eq(recovery.isBlocked("dungeon_gold_mine"), false, "原金矿教程选关豁免保留")
            eq(recovery.isPendingStoryBlocked("battle"), true, "故事不借用教程选关豁免")
        end
        ctx.deps[path][method] = original
    end
    ctx.assertSafe()
end
local function buildingBootCases()
    for _, entry in ipairs(LEFT_PAGE_CASES) do
        for _, queueKind in ipairs({ "scenario", "follow", "story" }) do
            local ctx = newContext()
            local story = ctx.env.require("systems.StoryPlayer")
            local label = entry[1] .. "/" .. queueKind
            local cfg = ctx.config.SCENARIO_38
            local item = { scenarioId = 38, config = cfg }
            if queueKind == "scenario" then ctx.pending = { item }
            elseif queueKind == "follow" then ctx.followPending = { item }
            else check(story.enqueue(38), label .. "：真实队列入队") end
            local play = pendingBoot(ctx)
            local p = ctx.deps[entry[2]]
            p.open()
            local sessionBefore = copy(ctx.modules.session)
            for _ = 1, 3 do play() end
            local ownedMenu = entry[2] == "ui.church.ChurchPage" or entry[2] == "ui.tavern.TavernPage"
                or entry[2] == "ui.blacksmith.BlacksmithPage"
            assertPendingPaused(ctx, sessionBefore, label .. "打开时", ownedMenu and 3 or 0)
            if queueKind == "scenario" then eq(ctx.pending[1], item, label .. "：桥接队首身份仍在")
            elseif queueKind == "follow" then eq(ctx.followPending[1], item, label .. "：后续队首身份仍在")
            elseif queueKind == "story" then check(story.hasPending(), label .. "：真实StoryPlayer仍待播") end
            p.close(); play()
            ctx.clock.elapsedTime = ctx.clock.elapsedTime + 10; play()
            assertPendingPaused(ctx, sessionBefore, label .. "关闭动画中", ownedMenu and 3 or 0)
            p.finishClose(); play()
            eq(#ctx.shown, 1, label .. "：全部真实关闭后下次泵自动恢复一次")
            eq(ctx.shown[1].steps, cfg.steps, label .. "：恢复原队首/原段")
            eq(ctx.shown[1].background, cfg.background, label .. "：背景原样")
            eq(ctx.shown[1].mode, cfg.mode, label .. "：模式原样")
            play(); play()
            eq(#ctx.shown, 1, label .. "：重复泵不重播")
            eq(#ctx.actions, 0, label .. "：起播仍不发奖")
            check(ctx.modules.session.claimedScenarios["38"] == true, label .. "：仅起播时沿原时机预标记")
            finish(ctx)
            eq(#ctx.actions, 1, label .. "：仅结束沿原领奖出口调用一次")
            eq(ctx.actions[1].params.scenarioId, 38, label .. "：原领奖ID")
            eq(#ctx.notices, 1, label .. "：真实结束通知教程一次")
            play(); ctx.dialogue.skip(); play()
            eq(#ctx.shown, 1, label .. "：消费/完成后不重复展示")
            ctx.assertSafe()
        end
    end
    -- 锻炉真正关闭不是释放条件：仓库手动持有或仍在close动画，都继续暂停。
    local ctx = newContext()
    local story = ctx.env.require("systems.StoryPlayer")
    check(story.enqueue(82), "82奖励故事成功排队")
    local play = pendingBoot(ctx)
    local smith, bag = ctx.deps["ui.blacksmith.BlacksmithPage"], ctx.deps["ui.backpack.BackpackPanel"]
    smith.open(); bag.open()
    ctx.rewardPending, ctx.battleRewardBlocked = true, true
    local snapshot = copy(ctx.modules.session)
    play(); smith.close(); play(); smith.finishClose(); play()
    eq(bag.isOpen(), true, "锻炉已关闭但仓库仍开")
    assertPendingPaused(ctx, snapshot, "锻炉关闭仓库仍开，奖励覆盖门控不能绕过建筑", 1)
    bag.close(); ctx.clock.elapsedTime = ctx.clock.elapsedTime + 10; play()
    assertPendingPaused(ctx, snapshot, "库存关闭动画未收尾", 1)
    bag.finishClose(); play()
    eq(#ctx.shown, 1, "双页真正关闭后82恢复一次")
    eq(ctx.shown[1].steps, ctx.config.SCENARIO_82.steps, "82恢复原奖励故事")
    eq(ctx.modules.session.claimedScenarios["82"], nil, "82仍不在起播时预标记claimed")
    check(type(ctx.modules.session.scenarioRewardsGranted) == "table", "82原台账仅起播时创建")
    eq(next(ctx.modules.session.scenarioRewardsGranted), nil, "起播不伪造82发奖记录")
    eq(#ctx.actions, 0, "82起播仍不发奖")
    finish(ctx); play(); play()
    eq(#ctx.actions, 1, "82真实结束调用原领奖一次")
    eq(ctx.actions[1].params.scenarioId, 82, "82奖励ID未改")
    eq(ctx.actions[1].params.preClaimed, true, "82原领奖preClaimed参数保持")
    eq(#ctx.shown, 1, "82单队列消费后不重播")
    ctx.assertSafe()
end
local function buildingHeroCases()
    for _, entry in ipairs(LEFT_PAGE_CASES) do
        for _, route in ipairs({ "直接详情", "真实结束广播" }) do
            local ctx = newContext()
            local hs = ctx.env.require("ui.character.hero.HeroScenario")
            local p = ctx.deps[entry[2]]
            local label = entry[1] .. "/HeroScenario/" .. route
            ctx.modules.heroes.roster[25] = { level = 1 }
            if route == "真实结束广播" then sample(ctx, "small", bg(5)) end
            p.open()
            -- 酒馆菜单允许招募对白，仍必须等真实招募动画收尾。
            local inTavern = entry[2] == "ui.tavern.TavernPage"
            ctx.recruitBusy = inTavern
            local sessionBefore = copy(ctx.modules.session)
            local shownBefore = #ctx.shown
            hs.onOpenHero(25); hs.onOpenHero(25)
            hs.onRecruitResults({ { type = "hero", heroId = 24, isNew = true },
                { type = "hero", heroId = 24, isNew = true } })
            if route == "真实结束广播" then ctx.dialogue.skip() end
            local function paused(message)
                eq(#ctx.shown, shownBefore, label .. message .. "：不展示")
                check(hs.hasPending(), label .. message .. "：真实Hero队列保留")
                check(same(ctx.modules.session, sessionBefore), label .. message .. "：不提前标记角色")
                eq(ctx.stateUpdates, 0, label .. message .. "：不发布状态")
                eq(ctx.flushes, 0, label .. message .. "：不落档")
                eq(#ctx.actions, 0, label .. message .. "：不发奖")
            end
            hs.update(); ctx.bus.emit("scenario_dialogue_finished", { reason = "finished" })
            paused(inTavern and "招募忙时" or "打开时")
            p.close(); ctx.recruitBusy = false
            hs.onOpenHero(25); hs.update()
            ctx.bus.emit("scenario_dialogue_finished", { reason = "dismissed" })
            ctx.clock.elapsedTime = ctx.clock.elapsedTime + 10; hs.update()
            paused("关闭动画中重入")
            if inTavern then p.open() else p.finishClose() end
            hs.update(); hs.update()
            eq(#ctx.shown, shownBefore + 1, label .. "：所属/关闭后入队剧情恢复一次")
            eq(ctx.shown[#ctx.shown].steps, ctx.config.SCENARIO_77.steps, label .. "：已拥有未看仍先播入队")
            check(ctx.modules.session.claimedScenarios["77"], label .. "：仅起播才标记入队")
            eq(ctx.modules.session.claimedScenarios["81"], nil, label .. "：未看闲聊不提前标记")
            eq(ctx.modules.session.claimedScenarios["76"], nil, label .. "：下一角色还没消费")
            eq(ctx.flushes, 1, label .. "：已播入队标记落档一次")
            finish(ctx)
            eq(#ctx.shown, shownBefore + 2, label .. "：入队结束立即接本角色闲聊")
            eq(ctx.shown[#ctx.shown].steps, ctx.config.SCENARIO_81.steps, label .. "：本角色闲聊原文")
            eq(ctx.flushes, 2, label .. "：入队与闲聊各标记一次")
            -- 本角色闲聊结束前覆盖页面，回调及广播不得抽走第二队首。
            if inTavern then ctx.recruitBusy = true else p.open() end
            finish(ctx); hs.update()
            ctx.bus.emit("scenario_dialogue_finished", { reason = "finished" })
            eq(#ctx.shown, shownBefore + 2, label .. "：重入仍挡第二个角色")
            check(hs.hasPending(), label .. "：第二队首未丢失")
            eq(ctx.modules.session.claimedScenarios["76"], nil, label .. "：重入不预标记新人")
            eq(ctx.flushes, 2, label .. "：重入不额外Flush")
            p.close(); ctx.recruitBusy = false; hs.update()
            eq(#ctx.shown, shownBefore + 2, label .. "：再次close中仍暂停")
            if inTavern then p.open() else p.finishClose() end
            hs.update()
            eq(#ctx.shown, shownBefore + 3, label .. "：第二请求自动恢复一次")
            eq(ctx.shown[#ctx.shown].steps, ctx.config.SCENARIO_76.steps, label .. "：FIFO新人入队保持")
            finish(ctx)
            eq(#ctx.shown, shownBefore + 4, label .. "：新人入队结束接闲聊一次")
            eq(ctx.shown[#ctx.shown].steps, ctx.config.SCENARIO_80.steps, label .. "：新人闲聊原文")
            finish(ctx); hs.update(); hs.onOpenHero(25)
            ctx.bus.emit("scenario_dialogue_finished", { reason = "finished" }); hs.update()
            eq(#ctx.shown, shownBefore + 4, label .. "：重复调用/广播不重播")
            eq(hs.hasPending(), false, label .. "：两次请求均完成无积压")
            eq(ctx.flushes, 4, label .. "：四个真实标记各落档一次")
            eq(#ctx.actions, 0, label .. "：Hero流程没有新增发奖出口")
            ctx.assertSafe()
        end
    end
end
local function letterTitleCases()
    local ctx = newContext()
    local letter = ctx.env.require("ui.story.gate.LetterIntro")
    letter.init(ctx.vg)
    local done = 0
    letter.start(function() done = done + 1 end)
    eq(ctx.loadCount(bg(1)), 1, "LetterIntro explicitly loads STUDY")
    for _ = 1, 7 do letter.handleTap() end
    ctx.calls = {}; letter.draw(ctx.vg, 1920, 1080)
    eq(#images(ctx, bg(1)), 1, "letter keeps desk scene throughout four reveal blocks")
    local _, bi = find(ctx, "image", bg(1))
    local _, ti = find(ctx, "text")
    check(bi < ti, "letter desk below original text")
    letter.handleTap(); ctx.calls = {}; letter.draw(ctx.vg, 1920, 1080)
    eq(#images(ctx, bg(1)), 1, "sealed letter keeps STUDY, no seal cutaway")
    letter.handleTap(); letter.update(0.3)
    ctx.calls = {}; letter.draw(ctx.vg, 1920, 1080)
    check(find(ctx, "image", bg(1)).alpha < 0.51, "letter desk follows original fading")
    eq(done, 0, "letter 0.3s fade not completed")
    letter.update(0.31); letter.update(1)
    eq(done, 1, "letter original 0.6s finish once")
    letter.start(); eq(ctx.loadCount(bg(1)), 1, "letter reuses successful desk image")
    letter.reset()
    local title = ctx.env.require("ui.story.gate.DarkTitleScreenGate")
    title.init(ctx.vg); title.open(); title.setReady(false)
    ctx.calls = {}; title.draw(ctx.vg, 1920, 1080)
    local gate, gi = find(ctx, "image", TITLE)
    local logo, li = find(ctx, "image", LOGO)
    check(gi < li, "same-path title replacement stays behind existing logo")
    near(gate.w, 1920, "title background original cover geometry")
    near(logo.w, 960, "title existing logo scale unchanged")
    title.handleTap(); eq(title.isFading(), false, "title resource-readiness gate remains")
    title.setReady(true); title.handleTap(); title.update(0.275)
    ctx.calls = {}; title.draw(ctx.vg, 1920, 1080)
    near(find(ctx, "image", TITLE).alpha, 0.5, "title background retains 0.55s fade")
    title.update(0.3); eq(title.isOpen(), false, "title closes on original timing")
    ctx.assertSafe()
end
local function heroCases()
    for _, hero in ipairs({ 18, 19, 24, 25 }) do
        local ctx = newContext()
        local hs = ctx.env.require("ui.character.hero.HeroScenario")
        local join = ({ [18] = 74, [19] = 75, [24] = 76, [25] = 77 })[hero]
        local idle = join + 4
        hs.onRecruitResults({ { type = "hero", heroId = hero, isNew = true }, { type = "hero", heroId = hero, isNew = true } })
        eq(#ctx.shown, 1, "new hero join once despite duplicate recruit result " .. hero)
        eq(ctx.shown[1].background, bg(17), "HeroScenario forwards cfg.background join " .. hero)
        eq(ctx.shown[1].steps, ctx.config["SCENARIO_" .. join].steps, "hero join original steps")
        eq(ctx.shown[1].mode, "small", "hero join original small mode")
        check(ctx.modules.session.claimedScenarios[tostring(join)], "join claimed through memory state update")
        ctx.dialogue.skip()
        eq(#ctx.shown, 2, "join onFinish chains idle once")
        eq(ctx.shown[2].background, bg(17), "HeroScenario forwards cfg.background idle " .. hero)
        eq(ctx.shown[2].steps, ctx.config["SCENARIO_" .. idle].steps, "hero idle original steps")
        check(ctx.modules.session.claimedScenarios[tostring(idle)], "idle claimed through memory state update")
        ctx.dialogue.skip(); ctx.modules.heroes.roster[hero] = { level = 1 }
        hs.onOpenHero(hero); hs.onRecruitResults({ { type = "hero", heroId = hero, isNew = true } })
        eq(#ctx.shown, 2, "claimed join/idle never replay")
        eq(ctx.flushes, 2, "two claim writes call mock Flush only once each")
        eq(#ctx.actions, 0, "hero display does not dispatch cloud rewards")
        ctx.assertSafe()
    end
    local ctx = newContext()
    ctx.modules.heroes.roster[25] = { level = 1 }
    local hs = ctx.env.require("ui.character.hero.HeroScenario")
    sample(ctx, "small", bg(5))
    hs.onOpenHero(25); hs.onOpenHero(25)
    eq(#ctx.shown, 1, "busy hero requests wait and deduplicate")
    ctx.dialogue.skip()
    eq(#ctx.shown, 2, "real finished EventBus drains pending hero")
    eq(ctx.shown[2].background, bg(17), "drained join retains background17")
    eq(ctx.shown[2].steps, ctx.config.SCENARIO_77.steps, "已拥有未看入队仍先77")
    ctx.dialogue.skip()
    eq(#ctx.shown, 3, "真实入队结束接81一次")
    eq(ctx.shown[3].steps, ctx.config.SCENARIO_81.steps, "闲聊81原文保持")
    ctx.dialogue.skip(); hs.onOpenHero(25)
    eq(#ctx.shown, 3, "drained claim prevents replay")
    ctx.assertSafe()
end
local function placeQueueCases()
    local ctx = newContext()
    local story = ctx.env.require("systems.StoryPlayer")
    local expected = { [27] = "church", [31] = "tavern", [47] = "smith" }
    for _, id in ipairs({ 23,24,25,26,28,29,30,32,33,34,48,49,50 }) do expected[id] = "town" end
    for id = 1, 82 do
        if ctx.config["SCENARIO_" .. id] then
            for _, place in ipairs({ "town", "battle", "church", "tavern", "smith", "other", "battle_town" }) do
                local owner = expected[id] or "battle"
                local matches = place == owner or place == "battle_town" and (owner == "town" or owner == "battle")
                eq(story.matchesPlace(id, place), matches, "80剧情精确归属 " .. id .. "/" .. place)
            end
        end
    end
    for _, id in ipairs({ 35, 31, 47, 27, 23, 36 }) do check(story.enqueue(id), "混合队列入队 " .. id) end
    for _, pair in ipairs({ { "tavern",31 }, { "church",27 }, { "smith",47 }, { "town",23 },
        { "battle",35 }, { "battle",36 } }) do
        check(story.hasPending(pair[1]), "所属队列待播 " .. pair[1])
        eq(story.take(pair[1]).scenarioId, pair[2], "跨场跳过但同场FIFO " .. pair[1])
    end
    eq(story.hasPending(), false, "跨场取完无积压")
    eq(story.take("other"), nil, "其他页不能消费任何剧情")
    -- 两栏同时可见时沿用全队列FIFO，不人为给城镇或主线另设永久优先级。
    for _, ids in ipairs({ { 23,24,5 }, { 5,23,24 }, { 23,5,24 } }) do
        for _, id in ipairs({ 31,27,47 }) do check(story.enqueue(id), "双上下文保留菜单队首 " .. id) end
        for _, id in ipairs(ids) do check(story.enqueue(id), "双上下文混合FIFO入队 " .. id) end
        for _, id in ipairs(ids) do
            check(story.hasPending("battle_town"), "双上下文有可播城镇或主线 " .. id)
            eq(story.take("battle_town").scenarioId, id, "双上下文按原全队列顺序消费 " .. id)
        end
        eq(story.hasPending("battle_town"), false, "仅剩菜单时双上下文不虚报待播")
        eq(story.take("battle_town"), nil, "双上下文不消费三个菜单介绍")
        for _, pair in ipairs({ { "tavern",31 }, { "church",27 }, { "smith",47 } }) do
            eq(story.take(pair[1]).scenarioId, pair[2], "跳过菜单后菜单原队首仍在 " .. pair[1])
        end
    end
    for hero = 1, 3 do
        local branch = newContext()
        branch.modules.session.initialHeroId = hero
        local s = branch.env.require("systems.StoryPlayer")
        for _, place in ipairs({ "church", "tavern", "smith" }) do
            s.onPlace(place, "leave")
            eq(s.hasPending("town"), false, "没看入场不排告别 " .. place)
            s.onPlace(place, "enter")
            eq(s.take("battle"), nil, "菜单介绍不归战场 " .. place)
            local item = assert(s.take(place))
            branch.modules.session.claimedScenarios[tostring(item.scenarioId)] = true
            s.onPlace(place, "leave")
            eq(s.take(place), nil, "告别不留所属菜单 " .. place)
            local want = ({ church = 27, tavern = 31, smith = 47 })[place] + hero
            eq(s.take("town").scenarioId, want, "告别回城镇英雄分支 " .. place)
        end
        s.onStage(205, "clear")
        eq(s.take("town"), nil, "205不能跑到城镇")
        eq(s.take("battle").scenarioId, 50 + hero, "205先角色收尾分支")
        eq(s.take("battle").scenarioId, 82, "205后潜能引导82")
        eq(s.take("battle"), nil, "205仅两段")
        branch.assertSafe()
    end
    ctx.assertSafe()
end
local function menuBootCases()
    for _, entry in ipairs({ { "tavern", "ui.tavern.TavernPage",31 },
        { "church", "ui.church.ChurchPage",27 }, { "smith", "ui.blacksmith.BlacksmithPage",47 } }) do
        local ctx = newContext()
        local story = ctx.env.require("systems.StoryPlayer")
        local play = pendingBoot(ctx)
        local p = ctx.deps[entry[2]]
        local bridge = { scenarioId = 38, config = ctx.config.SCENARIO_38 }
        ctx.pending, ctx.followPending = { bridge }, { bridge }
        check(story.enqueue(35), "菜单前有战场旧队首")
        p.open()
        if entry[1] == "smith" then ctx.deps["ui.backpack.BackpackPanel"].open() end
        -- 与生产Update同一段闭包，直接菜单/教程恢复入口无需点击城镇才触发。
        ctx.env.postStartFlowDone_ = true
        local auto = section("boot.Standalone", "    -- 按实际打开的菜单自动触发，", "\n    -- [横屏接线 0928]")
        ctx.compile(auto, "production-auto-place")
        play(); play()
        eq(#ctx.shown, 1, "所属菜单自动起播一次 " .. entry[1])
        eq(ctx.shown[1].steps, ctx.config["SCENARIO_" .. entry[3]].steps, "所属菜单原文 " .. entry[1])
        eq(ctx.shown[1].background, ctx.config["SCENARIO_" .. entry[3]].background, "所属菜单背景保持")
        eq(ctx.pendingReads.scenario, 0, "菜单不读旧主线回执")
        eq(ctx.pendingReads.follow, 0, "菜单不读主线后续回执")
        eq(ctx.pending[1], bridge, "菜单保留主线桥接队首")
        check(story.hasPending("battle"), "菜单保留主线队首")
        eq(#ctx.actions, 0, "菜单起播仍不发奖")
        finish(ctx)
        eq(#ctx.actions, 1, "所属菜单真实结束领奖一次")
        ctx.compile(auto, "production-auto-place-again"); play()
        eq(#ctx.shown, 1, "所属菜单已看不重播")
        story.onPlace(entry[1], "leave")
        play(); eq(#ctx.shown, 1, "告别不在菜单播")
        p.close(); play(); eq(#ctx.shown, 1, "所属页关闭动画挡告别")
        p.finishClose()
        if entry[1] == "smith" then ctx.deps["ui.backpack.BackpackPanel"].finishClose() end
        ctx.nav = 4; play()
        eq(ctx.shown[2].steps, ctx.config["SCENARIO_" .. (entry[3] + 1)].steps, "回城镇才播告别")
        eq(ctx.pendingReads.scenario, 0, "城镇仍不消费主线桥接")
        finish(ctx); ctx.nav = 3; play()
        eq(ctx.shown[3].steps, ctx.config.SCENARIO_38.steps, "回主线恢复原桥接队首")
        ctx.assertSafe()
    end
    -- 正式nav3三行无需切旧nav4：菜单介绍结束、真正关闭后直接播告别，再恢复主线。
    local autoPlace = section("boot.Standalone", "    -- 按实际打开的菜单自动触发，", "\n    -- [横屏接线 0928]")
    for _, entry in ipairs({ { "tavern", "ui.tavern.TavernPage",31 },
        { "church", "ui.church.ChurchPage",27 }, { "smith", "ui.blacksmith.BlacksmithPage",47 } }) do
        local ctx = newContext()
        ctx.triOpen = true
        ctx.modules.battle.clearedStages = { [105] = true }
        ctx.modules.session.claimedScenarios = { ["23"] = true, ["24"] = true }
        ctx.env.postStartFlowDone_ = true
        local recovery = ctx.env.require("ui.tutorial.TutorialPageRecovery")
        local story, play = ctx.env.require("systems.StoryPlayer"), pendingBoot(ctx)
        local p = ctx.deps[entry[2]]
        p.open()
        if entry[1] == "smith" then ctx.deps["ui.backpack.BackpackPanel"].open() end
        ctx.compile(autoPlace, "production-tri-menu-enter"); play()
        eq(ctx.nav, 3, "菜单直达不伪切旧城镇页签 " .. entry[1])
        eq(recovery.getStoryPlace(), entry[1], "双上下文仍优先真实所属菜单 " .. entry[1])
        eq(#ctx.shown, 1, "三行菜单自动起播一次 " .. entry[1])
        eq(ctx.shown[1].steps, ctx.config["SCENARIO_" .. entry[3]].steps, "三行菜单保留原介绍 " .. entry[1])
        eq(ctx.pendingReads.scenario, 0, "三行菜单不消费主线回执 " .. entry[1])
        finish(ctx)
        story.onPlace(entry[1], "leave")
        check(story.enqueue(5), "菜单告别后还有主线5待播 " .. entry[1])
        p.close(); ctx.compile(autoPlace, "production-tri-menu-closing"); play()
        eq(recovery.getStoryPlace(), "other", "三行菜单关闭动画不能回退双上下文 " .. entry[1])
        eq(recovery.isPendingStoryBlocked("battle_town"), true, "三行菜单关闭动画仍挡双上下文 " .. entry[1])
        eq(#ctx.shown, 1, "三行关闭动画不抢播告别 " .. entry[1])
        p.finishClose()
        if entry[1] == "smith" then ctx.deps["ui.backpack.BackpackPanel"].finishClose() end
        eq(recovery.getStoryPlace(), "battle_town", "菜单真实关闭后恢复三行双上下文 " .. entry[1])
        ctx.compile(autoPlace, "production-tri-menu-closed"); play()
        eq(#ctx.shown, 2, "nav3原地播菜单告别一次 " .. entry[1])
        eq(ctx.shown[2].steps, ctx.config["SCENARIO_" .. (entry[3] + 1)].steps, "三行31到32/27到28/47到48原文 " .. entry[1])
        finish(ctx); ctx.compile(autoPlace, "production-tri-menu-follow"); play()
        eq(#ctx.shown, 3, "三行告别后主线不饥饿 " .. entry[1])
        eq(ctx.shown[3].steps, ctx.config.SCENARIO_5.steps, "三行告别后恢复主线5 " .. entry[1])
        finish(ctx)
        ctx.pending = { { scenarioId = 38, config = ctx.config.SCENARIO_38 } }
        play()
        eq(#ctx.shown, 4, "三行双上下文继续消费真实普通回执 " .. entry[1])
        eq(ctx.shown[4].steps, ctx.config.SCENARIO_38.steps, "三行普通回执保留原38 " .. entry[1])
        eq(#ctx.pending, 0, "三行普通回执恰好消费一次 " .. entry[1])
        eq(ctx.nav, 3, "告别和主线全程保持正式nav3 " .. entry[1])
        ctx.assertSafe()
    end
    -- 城镇绘图存在不等于剧情已经抵达；新开场/第一章期间不得自动抢播23。
    for _, fixture in ipairs({
        { label = "新入三行", cleared = {}, max = 101, current = 101, town = false },
        { label = "仅当前关201", cleared = {}, max = 104, current = 201, town = false },
        { label = "max尚未201", cleared = {}, max = 200, current = 104, town = false },
        { label = "数字105已通", cleared = { [105] = true }, max = 105, current = 105, town = true },
        { label = "字符串105已通", cleared = { ["105"] = true }, max = 105, current = 105, town = true },
        { label = "旧档max201", cleared = {}, max = 201, current = 101, town = true },
        { label = "字符串max201", cleared = {}, max = "201", current = 101, town = true },
    }) do
        local ctx = newContext()
        ctx.triOpen = true
        ctx.modules.battle.clearedStages, ctx.modules.battle.maxStageId = fixture.cleared, fixture.max
        ctx.modules.battle.currentStageId = fixture.current
        local story, play = ctx.env.require("systems.StoryPlayer"), pendingBoot(ctx)
        local recovery = ctx.env.require("ui.tutorial.TutorialPageRecovery")
        eq(recovery.getStoryPlace(), "battle_town", fixture.label .. "：始终是真实三行双上下文")
        ctx.env.postStartFlowDone_ = false
        ctx.compile(autoPlace, "production-tri-before-gameplay")
        eq(story.hasPending(), false, fixture.label .. "：开场未完成不自动入城")
        ctx.env.postStartFlowDone_ = true
        ctx.compile(autoPlace, "production-tri-town-entry"); play()
        eq(#ctx.shown, fixture.town and 1 or 0, fixture.label .. "：按真实第一章进度入城")
        if fixture.town then
            eq(ctx.shown[1].steps, ctx.config.SCENARIO_23.steps, fixture.label .. "：先23抵达城门")
            finish(ctx)
            ctx.compile(autoPlace, "production-tri-town-repeat"); play()
            eq(#ctx.shown, 2, fixture.label .. "：23结束后原分支24自动可取")
            eq(ctx.shown[2].steps, ctx.config.SCENARIO_24.steps, fixture.label .. "：24保留原文")
            story.onStage(101, "clear")
            finish(ctx); ctx.compile(autoPlace, "production-tri-town-to-battle"); play()
            eq(#ctx.shown, 3, fixture.label .. "：23和24后主线仍可取")
            eq(ctx.shown[3].steps, ctx.config.SCENARIO_5.steps, fixture.label .. "：取原主线5而非永久城镇筛选")
            eq(ctx.modules.session.claimedScenarios["23"], true, fixture.label .. "：23真实起播防重")
            eq(ctx.modules.session.claimedScenarios["24"], true, fixture.label .. "：24真实起播防重")
        else
            eq(story.hasPending("town"), false, fixture.label .. "：尚未抵达不积压城镇剧情")
            eq(ctx.stateUpdates, 0, fixture.label .. "：自动绘城不预标记剧情")
            eq(ctx.flushes, 0, fixture.label .. "：自动绘城不落档")
            story.onStage(101, "clear"); ctx.compile(autoPlace, "production-tri-first-clear"); play()
            eq(#ctx.shown, 1, fixture.label .. "：第一章首通主线正常播放")
            eq(ctx.shown[1].steps, ctx.config.SCENARIO_5.steps, fixture.label .. "：首通5不被23抢播")
            eq(story.hasPending("town"), false, fixture.label .. "：首通后仍无提前城门剧情")
        end
        check(ctx.pendingReads.scenario > 0 and ctx.pendingReads.follow > 0, fixture.label .. "：双上下文保留普通回执读取")
        eq(ctx.nav, 3, fixture.label .. "：城镇与主线不需旧页签切换")
        ctx.assertSafe()
    end
    for _, entry in ipairs(LEFT_PAGE_CASES) do
        local ctx = newContext()
        ctx.modules.session.deferredOpening, ctx.modules.session.deferredOpeningIndex = true, 3
        local play = pendingBoot(ctx)
        ctx.deps[entry[2]].open(); play()
        ctx.deps[entry[2]].finishClose(); play()
        eq(#ctx.shown, 0, "后续泵永不消费旧开场 " .. entry[1])
        eq(ctx.pendingReads.deferred, 0, "后续泵不读取旧开场 " .. entry[1])
        eq(ctx.modules.session.deferredOpeningIndex, 3, "后续泵保留旧进度")
        eq(ctx.flushes, 0, "后续泵不落开场档")
        ctx.assertSafe()
    end
end
local function bootOpening(ctx)
    ctx.env.ClientDispatcher = ctx.deps["runtime.ClientDispatcher"]
    ctx.env.ScenarioDialogue, ctx.env.ScenarioDialogueConfig = ctx.dialogue, ctx.config
    local letter = ctx.env.require("ui.story.gate.LetterIntro")
    letter.init(ctx.vg)
    ctx.env.LetterIntro = letter
    ctx.env.Standalone, ctx.env.StandaloneRT = {}, {}
    ctx.env.postStartFlowDone_, ctx.env.entryPrepared_ = false, false
    ctx.completed, ctx.scenes = 0, {}
    ctx.env.GameBGM = { setScene = function(name) ctx.scenes[#ctx.scenes + 1] = name end }
    ctx.env.showOfflineRewardPanel_ = function() ctx.completed = ctx.completed + 1; return true end
    ctx.env.localSendAction = function(action, params)
        ctx.actions[#ctx.actions + 1] = { action = action, params = params }; return true
    end
    local text = section("boot.Standalone", "local function markIntroCompleted_(deferOpening)", "\n--- 清除存档后")
    return ctx.compile(text .. "\nreturn { start=startIntroChain_, resume=resumeOpening_, cancel=cancelOpening_ }", "production-opening-chain"), letter
end
local function bootChainCases()
    local ctx = newContext()
    ctx.modules.session.introCompleted = false
    ctx.modules.session.keep = "unchanged-session-field"
    local chain, letter = bootOpening(ctx)
    chain.start()
    eq(ctx.modules.session.introCompleted, true, "新档仍预标记原开场完成字段")
    eq(ctx.modules.session.deferredOpening, true, "开场链保存可恢复进度")
    eq(ctx.modules.session.deferredOpeningIndex, 1, "新档开场从第一段")
    eq(ctx.modules.session.keep, "unchanged-session-field", "保留无关session字段")
    eq(ctx.actions[1].action, "grant_starter_trio", "原starter动作保持")
    eq(#ctx.actions, 1, "初始三人只发一次")
    eq(#ctx.shown, 0, "必须完整信件后才开始门厅")
    eq(ctx.completed, 0, "信件前不进入游戏/离线结算")
    for _ = 1, 7 do letter.handleTap() end
    ctx.calls = {}; letter.draw(ctx.vg, 1920, 1080)
    local text = ""
    for _, call in ipairs(ctx.calls) do if call.kind == "text" then text = text .. call.text end end
    check(text:find("公会管这叫交接。我管这叫甩锅。", 1, true)
        and text:find("先听他们把话说完，再出门。", 1, true), "真实Boot使用完整来信，不再compact")
    check(not text:find("先带队出门，路上的故事，我们稍后再说。", 1, true), "开场不混短信旧策略")
    letter.handleTap(); letter.handleTap(); letter.update(0.3)
    eq(#ctx.shown, 0, "完整信件仍等待淡出收尾")
    letter.update(0.31)
    local expected = { ctx.config.OPENING, table.unpack(ctx.config.OPENING_JOINS) }
    for index, cfg in ipairs(expected) do
        eq(#ctx.shown, index, "信件后连续即时段落 " .. index)
        local shown = ctx.shown[index]
        eq(shown.steps, cfg.steps, "原步骤表身份 " .. index)
        eq(shown.background, cfg.background, "原背景 " .. index)
        eq(shown.backgroundIsCg, cfg.backgroundIsCg, "原CG标记 " .. index)
        eq(shown.mode, cfg.mode, "原模式 " .. index)
        eq(ctx.modules.session.deferredOpeningIndex, index, "只已结束段落推进保存index")
        eq(ctx.completed, 0, "最后一段结束前不离线结算/进入游戏")
        local stale, flushes = shown.onFinish, ctx.flushes
        if index == 1 then
            ctx.dialogue.update(0.3); ctx.draw()
            eq(#images(ctx), 1, "真实Boot门厅CG只绘制一次无立绘")
        end
        finish(ctx)
        eq(ctx.flushes, flushes + (index == 4 and 2 or 1), "结束推进一次，最终另存原intro标记")
        local after = ctx.flushes
        stale(); eq(ctx.flushes, after, "重复回调不推进/落档")
    end
    eq(#ctx.shown, 4, "门厅加三人入队完整四段")
    eq(ctx.modules.session.deferredOpening, false, "四段结束清待播")
    eq(ctx.modules.session.deferredOpeningCompletedVersion, 1, "最终完成版本")
    eq(ctx.completed, 1, "最后一段结束才离线结算一次")
    eq(ctx.env.postStartFlowDone_, true, "原离线启动结果保持")
    eq(ctx.scenes[#ctx.scenes], "battle", "开场结束音乐交还战场")
    eq(#ctx.actions, 1, "四段纯展示不发场景奖励/重复初始角色")
    eq(#ctx.notices, 0, "四段不制造教程领取通知")
    local play = pendingBoot(ctx); play()
    eq(ctx.pendingReads.deferred, 0, "后续剧情泵不读取已完成开场")
    ctx.assertSafe()
    for index = 1, 4 do
        local old = newContext()
        old.modules.session.deferredOpening, old.modules.session.deferredOpeningIndex = true, index
        old.modules.session.keep = "旧进度保留"
        local flow, oldLetter = bootOpening(old)
        flow.resume()
        eq(oldLetter.isOpen(), false, "旧延播档不重播已读来信")
        for current = index, 4 do
            local cfg = current == 1 and old.config.OPENING or old.config.OPENING_JOINS[current - 1]
            eq(old.shown[#old.shown].steps, cfg.steps, "旧档从保存index连续接续")
            eq(old.completed, 0, "旧档剩余段落结束前不进游戏")
            finish(old)
        end
        eq(#old.shown, 5 - index, "旧档只播剩余段落")
        eq(old.modules.session.keep, "旧进度保留", "旧任意字段保留")
        eq(old.completed, 1, "旧档最后结束进游戏一次")
        eq(#old.actions, 0, "旧档不补发starter")
        old.assertSafe()
    end
    local reset = newContext()
    reset.modules.session.deferredOpening, reset.modules.session.deferredOpeningIndex = true, 2
    local flow = bootOpening(reset)
    flow.resume()
    local stale = reset.shown[1].onFinish
    flow.cancel(); reset.env.require("systems.StoryPlayer").resetAll(); reset.dialogue.reset()
    reset.modules.session = { introCompleted = true, deferredOpening = true, deferredOpeningIndex = 2, newSave = true }
    flow.resume()
    local before, count, flushes = copy(reset.modules.session), #reset.shown, reset.flushes
    stale()
    check(same(reset.modules.session, before), "旧flow/token不写同index新档")
    eq(#reset.shown, count, "旧回调不替新档连播")
    eq(reset.flushes, flushes, "旧回调不落新档")
    reset.assertSafe()
end

function Start()
    local cases = {
        { "config-80-and-real-StageConfig", configCases }, { "17-backgrounds-and-title-resources", assetCases },
        { "frame-semantics-layering-and-original-entrance", frameCases }, { "all80-frame-backgrounds-and-original-contract", allScenarioFrames },
        { "dismiss-fade-and-failure-callback", dismissalCases },
        { "legacy-eyeOpen-contract", eyeCases }, { "cache-handle0-retry-and-context", cacheCases },
        { "direct-CG-flag-and-fallback", cgCases }, { "wipe-capture-and-reward-gates", wipeCases },
        { "Boot-all-dead-time-of-capture", wipeBootCases }, { "Boot-reward-gates-and-failed-local-callback", rewardGateCases },
        { "building-story-gate-keeps-original-tutorial-priority", buildingGateCases },
        { "eight-building-pages-pause-battle-Boot-queues", buildingBootCases },
        { "eight-building-pages-Hero-owned-or-blocked-reentry", buildingHeroCases },
        { "letter-study-and-same-path-title", letterTitleCases }, { "HeroScenario-background-and-claim-dedup", heroCases },
        { "all80-place-FIFO-and-205-branch-before82", placeQueueCases },
        { "real-menu-auto-story-and-deferred-never-consumed-by-pump", menuBootCases },
        { "real-Boot-full-intro-continuous-original-segments-and-reset", bootChainCases },
    }
    for _, case in ipairs(cases) do
        local ok, why = pcall(case[2])
        groups = groups + 1
        if ok then print(PREFIX .. "[PASS] " .. case[1])
        else
            local message = case[1] .. " " .. tostring(why)
            failures[#failures + 1] = message
            print(PREFIX .. "[FAIL] " .. message)
            log:Write(LOG_ERROR, PREFIX .. message)
        end
    end
    if #failures == 0 then print(PREFIX .. "RESULT ALL PASS groups=" .. groups .. " checks=" .. checks)
    else print(PREFIX .. "RESULT FAIL groups=" .. groups .. " checks=" .. checks .. " failures=" .. #failures) end
    engine:Exit()
end
