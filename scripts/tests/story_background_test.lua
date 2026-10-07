-- 专项回归：仅只读生产源码/图片，通过 cache.GetFile + load(env) 创建独立真实模块。
-- /home/Maker/game04-runtime/UrhoXRuntime tests/story_background_test.lua
--   -tapcode_dir=/workspace/game04 -tool_mode -graphicsheadless -validate -validateframes=90
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

-- 绘制记录包含最终调用次序、alpha、平移、覆盖区域；不安装全局require/package.loaded桩。
local function newContext()
    local ctx = { deps = {}, calls = {}, loads = {}, responses = {}, handles = {}, nextHandle = 0,
        modules = {}, events = {}, shown = {}, actions = {}, notices = {}, flushes = 0,
        fileAttempts = 0, cloudAttempts = 0, vg = {}, font = 20, stack = {}, tx = 0, ty = 0 } ---@type any
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
    ctx.deps["ui.tutorial.TutorialPageRecovery"] = { isBlocked = function() return ctx.recoveryBlocked == true end }
    ctx.deps["boot.BattleRewardOverlay"] = { isBlocked = function() return ctx.battleRewardBlocked == true end }
    env.require = function(name)
        if ctx.deps[name] ~= nil then return ctx.deps[name] end
        local permitted = name:match("^config%.") or name == "core.EventBus" or name == "core.I18nStory"
            or name == "ui.story.StoryDisplay" or name == "ui.story.ScenarioDialogue"
            or name == "ui.story.gate.LetterIntro" or name == "ui.story.gate.DarkTitleScreenGate"
            or name == "systems.StoryPlayer" or name == "ui.character.hero.HeroScenario"
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
    ctx.env.ClientDispatcher = ctx.deps["runtime.ClientDispatcher"]
    ctx.env.ScenarioDialogue = ctx.dialogue
    ctx.env.TutorialManager = ctx.deps["systems.TutorialManager"]
    ctx.env.LetterIntro = { isOpen = function() return ctx.letterOpen end }
    ctx.env.IntroCutscene = { isActive = function() return ctx.introActive end }
    ctx.env.RewardPopup = { isOpen = function() return ctx.rewardOpen end,
        hasPendingBattleRewards = function() return ctx.rewardPending end }
    ctx.env.OfflineRewardPanel = { isOpen = function() return ctx.offlineOpen end }
    ctx.env.ClientMsgHandler = {
        consumePendingScenarioDialogue = function() return table.remove(ctx.pending or {}, 1) end,
        consumePendingFollowUpDialogue = function() return nil end,
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
    eq(ctx.shown[2].background, bg(17), "drained idle retains background17")
    ctx.dialogue.skip(); hs.onOpenHero(25)
    eq(#ctx.shown, 2, "drained claim prevents replay")
    ctx.assertSafe()
end
local function bootChainCases()
    local ctx = newContext()
    local letter = ctx.env.require("ui.story.gate.LetterIntro")
    letter.init(ctx.vg)
    ctx.modules.session.introCompleted = false
    ctx.modules.session.keep = "unchanged-session-field"
    ctx.env.ClientDispatcher = ctx.deps["runtime.ClientDispatcher"]
    ctx.env.ScenarioDialogue, ctx.env.ScenarioDialogueConfig = ctx.dialogue, ctx.config
    local completed, scenes = 0, {}
    ctx.env.GameBGM = { setScene = function(name) scenes[#scenes + 1] = name end }
    ctx.env.showOfflineRewardPanel_ = function() completed = completed + 1; return true end
    ctx.env.postStartFlowDone_ = false
    ctx.env.StandaloneRT = {}
    ctx.env.LetterIntro = letter
    ctx.env.localSendAction = function(action, params)
        ctx.actions[#ctx.actions + 1] = { action = action, params = params }; return true
    end
    local finishText = section("boot.Standalone", "local function markIntroCompleted_(deferOpening)",
        "\n--- 首通/入场排队")
    local mark, finishIntro = ctx.compile(finishText .. "\nreturn markIntroCompleted_, finishIntro_",
        "production-short-intro-finish")
    ctx.env.markIntroCompleted_, ctx.env.finishIntro_ = mark, finishIntro
    local introText = section("boot.Standalone", "local function startIntroChain_()", "\n--- 清除存档后")
    local start = ctx.compile(introText .. "\nreturn startIntroChain_", "production-intro-chain")
    start()
    eq(ctx.modules.session.introCompleted, true, "Boot still marks original intro completion at start")
    eq(ctx.modules.session.deferredOpening, true, "only new intro reserves original introduction for later")
    eq(ctx.modules.session.deferredOpeningIndex, 1, "deferred opening begins at original first segment")
    eq(ctx.modules.session.keep, "unchanged-session-field", "intro mark preserves unrelated session fields")
    eq(ctx.actions[1].action, "grant_starter_trio", "Boot preserves starter grant action")
    eq(#ctx.shown, 0, "Boot waits for letter before gameplay, no immediate opening")
    letter.handleTap(); ctx.calls = {}; letter.draw(ctx.vg, 1920, 1080)
    local shortBody = ""
    for _, call in ipairs(ctx.calls) do if call.kind == "text" then shortBody = shortBody .. call.text end end
    check(shortBody:find("帽子、印鉴、名册都在桌上，三位伙伴已在门外等你。", 1, true)
        and shortBody:find("先带队出门，路上的故事，我们稍后再说。", 1, true),
        "real Boot opts into the single three-line compact letter")
    letter.handleTap(); letter.update(0.3)
    eq(completed, 0, "compact letter keeps original fade completion guard")
    letter.update(0.31)
    eq(completed, 1, "short letter completion goes directly to gameplay once")
    eq(ctx.env.postStartFlowDone_, true, "finishIntro preserves offline post-start flow result")
    eq(scenes[#scenes], "battle", "short intro hands music back to battle")
    eq(#ctx.shown, 0, "compact callback no longer starts OPENING or three joins immediately")
    letter.handleTap(); letter.update(1)
    eq(completed, 1, "whole compact intro finishes once despite duplicate interactions")
    eq(#ctx.actions, 1, "background change adds no extra reward dispatch")

    -- 原84配置196句仍可完整展示，但先等基础操作完成，并把四段错开而非即时串播。
    local story = ctx.env.require("systems.StoryPlayer")
    eq(story.takeDeferredOpening(), nil, "new intro cannot play while foundation tutorials incomplete")
    ctx.foundation = { [1] = true, [2] = true, [4] = true, [8] = true, [9] = true }
    local play = pendingBoot(ctx)
    play()
    eq(#ctx.shown, 1, "foundation completion permits original opening briefing")
    eq(ctx.shown[1].backgroundIsCg, true, "Boot explicitly forwards backgroundIsCg")
    eq(ctx.shown[1].steps, ctx.config.OPENING.steps, "deferred Boot preserves exact original step table")
    ctx.dialogue.update(0.3); ctx.draw()
    eq(#images(ctx), 1, "Boot opening draws CG once, no portrait")
    local before = ctx.flushes
    finish(ctx)
    eq(ctx.modules.session.deferredOpeningIndex, 2, "only real opening finish advances deferred progress")
    eq(ctx.flushes, before + 1, "deferred finish Flushes memory save exactly once")
    eq(#ctx.shown, 1, "opening completion does not immediately chain first join")
    play(); eq(#ctx.shown, 1, "next deferred segment waits during 30-second gap")
    ctx.clock.elapsedTime = ctx.clock.elapsedTime + 29.99
    play(); eq(#ctx.shown, 1, "29.99 seconds does not consume next join")
    ctx.clock.elapsedTime = ctx.clock.elapsedTime + 0.01
    play()
    eq(#ctx.shown, 2, "first join becomes available at 30 seconds")
    eq(ctx.shown[2].background, bg(2), "Boot first join HALL")
    eq(ctx.shown[2].steps, ctx.config.OPENING_JOINS[1].steps, "first join preserves original dialogue")
    finish(ctx)
    eq(ctx.modules.session.deferredOpeningIndex, 3, "first join completion advances to second join")
    eq(#ctx.shown, 2, "first join completion cannot immediately chain second join")
    ctx.clock.elapsedTime = ctx.clock.elapsedTime + 30; play()
    eq(#ctx.shown, 3, "second original join plays after its own gap")
    eq(ctx.shown[3].steps, ctx.config.OPENING_JOINS[2].steps, "second join retains exact original steps")
    finish(ctx)
    eq(ctx.modules.session.deferredOpeningIndex, 4, "second join completion advances to third join")
    eq(#ctx.shown, 3, "second join does not immediately chain third join")
    ctx.clock.elapsedTime = ctx.clock.elapsedTime + 30; play()
    eq(#ctx.shown, 4, "third original join plays after its own gap")
    eq(ctx.shown[4].steps, ctx.config.OPENING_JOINS[3].steps, "third join retains exact original steps")
    finish(ctx)
    eq(ctx.modules.session.deferredOpening, false, "all four real segment finishes clear pending flag")
    eq(ctx.modules.session.deferredOpeningCompletedVersion, 1, "completion version written only at final finish")
    eq(completed, 1, "deferred segments do not repeat intro completion or offline startup")
    eq(#ctx.actions, 1, "deferred visual introductions add no scenario rewards or repeat starter grants")
    eq(#ctx.notices, 0, "deferred introductions do not manufacture tutorial claim notices")
    ctx.assertSafe()
end

function Start()
    local cases = {
        { "config-80-and-real-StageConfig", configCases }, { "17-backgrounds-and-title-resources", assetCases },
        { "frame-semantics-layering-and-original-entrance", frameCases }, { "all80-frame-backgrounds-and-original-contract", allScenarioFrames },
        { "dismiss-fade-and-failure-callback", dismissalCases },
        { "legacy-eyeOpen-contract", eyeCases }, { "cache-handle0-retry-and-context", cacheCases },
        { "direct-CG-flag-and-fallback", cgCases }, { "wipe-capture-and-reward-gates", wipeCases },
        { "Boot-all-dead-time-of-capture", wipeBootCases }, { "Boot-reward-gates-and-failed-local-callback", rewardGateCases },
        { "letter-study-and-same-path-title", letterTitleCases }, { "HeroScenario-background-and-claim-dedup", heroCases },
        { "real-Boot-compact-intro-and-deferred-original-segments", bootChainCases },
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
