-- 神器抽卡动画隔离回归，基于 recruit_animation_test 的严格 private-env/source 白名单脚手架。
-- 实际 Anim / RecruitTimeline / Presentation + 真实 ArtifactDefs 纯配置；UI/VG/图像/SFX 均内存叶替身。
-- 不加载 main/完整boot，不联网，不抽取/发奖/扣费，不访问玩家IO，不创建截图/日志/报告文件。
-- 源码ROOT取 -tapcode_dir；真实cache只读取下列固定Lua源码。由主会话统一LSP/build后再运行。
-- 记录控件/绘图调用仅证明时序与接线，不代表GPU或实机视觉验收。
local ROOT = "/workspace/changeForJourney"
for _, argument in ipairs(type(GetArguments) == "function" and GetArguments() or {}) do
    local directory = argument:match("^%-tapcode_dir=(.+)$")
    if directory then ROOT = directory:gsub("/+$", "") end
end
local TAG = "[artifact_draw_animation_test] "
local SOURCE_FILES = {
    ["ui.church.ArtifactDrawAnim"] = "ui/church/ArtifactDrawAnim.lua",
    ["ui.church.ArtifactDrawPresentation"] = "ui/church/ArtifactDrawPresentation.lua",
    ["ui.tavern.RecruitTimeline"] = "ui/tavern/RecruitTimeline.lua",
    ["ui.tavern.RecruitMotion"] = "ui/tavern/RecruitMotion.lua",
    ["shared.artifact.ArtifactDefs"] = "shared/artifact/ArtifactDefs.lua",
    ["host.ChurchPage"] = "ui/church/ChurchPage.lua",
    ["host.ChurchInput"] = "ui/church/ChurchInput.lua",
    ["host.ChurchDraw"] = "ui/church/ChurchDraw.lua",
    ["host.ChurchResults"] = "ui/church/ChurchResults.lua",
    ["host.ChurchArtifactDrawPanel"] = "ui/church/ChurchArtifactDrawPanel.lua",
    ["host.SeamBackGesture"] = "boot/SeamBackGesture.lua",
    ["host.Standalone"] = "boot/Standalone.lua",
}
local nativeCache, nativeFile, nativeTime = cache, File, time
local nativeGlobals, initialLoaded = {}, {} ---@type table<string, any>, table<string, any>
for _, name in ipairs({ "require", "load", "math", "nvgCreate", "nvgSave", "nvgRestore", "nvgScale", "nvgCreateImage" }) do
    nativeGlobals[name] = rawget(_G, name)
end
for name in pairs(SOURCE_FILES) do initialLoaded[name] = package.loaded[name] end
local sources = {} ---@type table<string, string>
local sourceReads, contexts = {}, {} ---@type any[], any[]
local failures = {} ---@type string[]
local checks, groups = 0, 0
local EPS = 0.000001
local INTRO, CARD, DELAY, FADE = 1.8, 0.66, 0.12, 0.35
local BUTTON_X, BUTTON_Y = 540, 2170
local CUES = { "artifact_draw_charge", "artifact_draw_reveal", "artifact_draw_legendary", "artifact_draw_settle" }
local function noop() end
local function check(ok, message) checks = checks + 1; assert(ok, message) end
local function eq(actual, expected, message)
    check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function near(actual, expected, message)
    check(type(actual) == "number" and math.abs(actual - expected) < EPS,
        message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) == "number" and a ~= a then return b ~= b end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function finite(value)
    if type(value) == "number" then return value == value and math.abs(value) < math.huge end
    if type(value) == "table" then for _, child in pairs(value) do if not finite(child) then return false end end end
    return true
end
local function span(count) return CARD + math.max(0, count - 1) * DELAY end
local function source(name)
    local relative = assert(SOURCE_FILES[name], "source not whitelisted " .. tostring(name))
    assert(ROOT:sub(1, 1) == "/" and not ROOT:find("..", 1, true), "unsafe -tapcode_dir root")
    if sources[name] then return sources[name] end
    local path = ROOT .. "/scripts/" .. relative
    local file = assert(nativeCache:GetFile(relative), "missing actual source " .. path)
    local ok, text = pcall(function()
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        return table.concat(lines, "\n")
    end)
    file:Dispose()
    assert(ok and type(text) == "string" and #text > 100, tostring(text))
    sources[name] = text
    sourceReads[#sourceReads + 1] = { path = path, relative = relative, bytes = #text }
    return text
end
-- 手工已完成权威回执：实例id不等于artifactId；品质故意乱序，包含真实双属性X/Y且不roll。
local function receipt(count)
    local ids = { 2, 1, 14, 7, 12, 9, 3, 8, 5, 4 }
    local quality = { 5, 1, 6, 2, 4, 3, 1, 5, 2, 4 }
    local values = { 73.8, 127.4, 10.3, 16.7, 272.6, 136.8, 83.2, 52.4, 49.3, 47.5 }
    local list = {}
    for i = 1, count do
        list[i] = { type = "artifact", id = "artifact_receipt_" .. (900 + i), artifactId = ids[i], quality = quality[i],
            value = values[i], valueRatio = 7319 - i * 137, isNew = i % 2 == 1 }
        if ids[i] == 2 then list[i].threatClearValue, list[i].threatClearRatio = 63.4, 8933 end
    end
    return list
end

---@param options any
---@return any
local function newContext(options)
    options = options or {}
    local ctx = { deps = {}, executions = {}, required = {}, forbidden = {}, fixtures = {},
        calls = {}, plays = {}, stops = {}, activeCues = {}, loads = {}, handles = {}, deleted = {},
        widgets = {}, surfaces = {}, stack = {}, clock = { elapsedTime = options.startTime or 0 }, vg = {},
        transform = { tx = 0, ty = 0, sx = 1, sy = 1, alpha = 1 }, font = 24, nextHandle = 0,
        memory = { keys = 50, gems = 12345, bag = { { id = "untouched_owned_artifact" } } },
        rngCalls = 0, transactionCalls = 0, costCalls = 0,
        presentationCalls = {}, language = options.language or "zh_CN", imageMode = options.imageMode or "ok",
    } ---@type any
    ctx.initialMemory = copy(ctx.memory)
    contexts[#contexts + 1] = ctx
    local env = {} ---@type any
    ctx.env = env
    for _, key in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "tonumber",
        "tostring", "type", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal" }) do env[key] = _G[key] end
    env.math, env.string, env.table, env.utf8 = copy(math), copy(string), copy(table), copy(utf8)
    env._G, env.time, env.print = env, ctx.clock, noop
    local function denied(label)
        return function()
            ctx.forbidden[#ctx.forbidden + 1] = label
            error("isolated artifact animation forbids " .. label)
        end
    end
    local function denyObject(label)
        return setmetatable({}, { __index = function(_, key) return denied(label .. "." .. tostring(key)) end })
    end
    env.math.random = function() ctx.rngCalls = ctx.rngCalls + 1; error("animation consumes RNG") end
    env.math.randomseed = env.math.random
    env.File, env.loadfile, env.dofile = denied("File"), denied("loadfile"), denied("dofile")
    env.SubscribeToEvent, env.SendEvent = denied("SubscribeToEvent"), denied("SendEvent")
    for _, key in ipairs({ "cache", "fileSystem", "io", "os", "package", "debug", "engine", "network",
        "sdk", "clientCloud", "serverCloud", "audio" }) do env[key] = denyObject(key) end
    for _, key in ipairs({ "NVG_ALIGN_LEFT", "NVG_ALIGN_RIGHT", "NVG_ALIGN_CENTER", "NVG_ALIGN_TOP",
        "NVG_ALIGN_MIDDLE", "NVG_ALIGN_BOTTOM", "NVG_ALIGN_BASELINE", "NVG_ROUND", "NVG_IMAGE_NEAREST",
        "NVG_SOLID", "NVG_HOLE" }) do env[key] = _G[key] end
    setmetatable(env, { __index = function(_, key) return denied("global " .. tostring(key))() end })
    local function record(kind, fields)
        local call = fields or {}; call.kind = kind
        ctx.calls[#ctx.calls + 1] = call
        return call
    end
    local function geometry(kind, x, y, w, h, fields)
        local entry = fields or {}; entry.x, entry.y, entry.w, entry.h = x, y, w, h
        entry.screenX, entry.screenY = x * ctx.transform.sx + ctx.transform.tx, y * ctx.transform.sy + ctx.transform.ty
        entry.sx, entry.sy, entry.alpha = ctx.transform.sx, ctx.transform.sy, ctx.transform.alpha
        check(finite({ x, y, w, h, entry.screenX, entry.screenY, entry.sx, entry.sy, entry.alpha }), "finite isolated geometry")
        return record(kind, entry)
    end
    -- 所有VG底层均明确私有替身，不把假VG交给native，也不创建真实帧/context/font/image。
    env.nvgCreate, env.nvgDelete = denied("nvgCreate"), denied("nvgDelete")
    env.nvgBeginFrame, env.nvgEndFrame, env.nvgCreateFont = denied("nvgBeginFrame"), denied("nvgEndFrame"), denied("nvgCreateFont")
    env.nvgSave = function() ctx.stack[#ctx.stack + 1] = copy(ctx.transform) end
    env.nvgRestore = function() ctx.transform = assert(table.remove(ctx.stack), "VG restore without save") end
    env.nvgTranslate = function(_, x, y)
        check(finite({x,y}), "finite translate")
        ctx.transform.tx, ctx.transform.ty = ctx.transform.tx + x * ctx.transform.sx, ctx.transform.ty + y * ctx.transform.sy
    end
    env.nvgScale = function(_, x, y)
        check(finite({x,y}) and x > 0 and y > 0, "positive finite flip scale")
        ctx.transform.sx, ctx.transform.sy = ctx.transform.sx * x, ctx.transform.sy * y
        record("scale", { x = x, y = y })
    end
    env.nvgGlobalAlpha = function(_, value) check(finite(value) and value >= 0 and value <= 1, "bounded VG alpha"); ctx.transform.alpha = value end
    for _, name in ipairs({ "nvgBeginPath", "nvgClosePath", "nvgFill", "nvgStroke", "nvgStrokeColor", "nvgFillColor", "nvgFillPaint",
        "nvgStrokeWidth", "nvgFontBlur", "nvgTextAlign", "nvgFontFace", "nvgScissor", "nvgIntersectScissor", "nvgResetScissor",
        "nvgLineCap", "nvgLineJoin", "nvgPathWinding" }) do
        env[name] = function(...) record(name, {}); check(select(1, ...) == ctx.vg, "all VG calls use isolated context " .. name) end
    end
    for _, name in ipairs({ "nvgRect", "nvgRoundedRect", "nvgRoundedRectVarying", "nvgCircle", "nvgEllipse", "nvgMoveTo", "nvgLineTo", "nvgBezierTo", "nvgRotate" }) do
        env[name] = function(vg, ...)
            eq(vg, ctx.vg, "shape uses isolated VG " .. name)
            local args = { ... }; check(finite(args), "finite shape args " .. name)
            record(name, { args = args })
        end
    end
    env.nvgRGBA, env.nvgRGBAf = function(...) return { ... } end, function(...) return { ... } end
    for _, name in ipairs({ "nvgLinearGradient", "nvgRadialGradient", "nvgBoxGradient" }) do env[name] = function() return {} end end
    env.nvgFontSize = function(_, value) check(finite(value) and value > 0, "positive font"); ctx.font = value end
    env.nvgTextBounds = function(_, _, _, text) return (utf8.len(text) or #text) * ctx.font * 0.56 end
    env.nvgTextLineHeight = function(_, value) ctx.lineHeight = value end
    env.nvgTextBoxBounds = function(_, x, y, width, text)
        local glyphs = utf8.len(text) or #text
        local lines = math.max(1, math.ceil(glyphs * ctx.font * 0.56 / math.max(1, width)))
        return { x, y, x + width, y + lines * ctx.font * (ctx.lineHeight or 1.18) }
    end
    env.nvgText = function(_, x, y, text) geometry("text", x, y, 0, 0, { text = text, font = ctx.font }) end
    env.nvgCreateImage = function(_, path)
        check(type(path) == "string" and path:sub(1, 6) == "image/", "only explicit image resource leaf")
        ctx.loads[#ctx.loads + 1] = path
        if ctx.imageMode == "throw" then error("isolated missing image") end
        if ctx.imageMode == "missing" then return -1 end
        ctx.nextHandle = ctx.nextHandle + 1; ctx.handles[ctx.nextHandle] = path; return ctx.nextHandle
    end
    env.nvgDeleteImage = function(_, handle) ctx.deleted[#ctx.deleted + 1] = handle end
    env.nvgImageSize = function() return 512, 512 end
    env.nvgImagePattern = function(_, x, y, w, h, angle, handle, alpha)
        check(type(handle) == "number" and handle >= 0, "missing image never reaches image pattern")
        geometry("image", x, y, w, h, { path = ctx.handles[handle], imageAlpha = alpha }); return {}
    end
    env.nvgImagePatternTinted = env.nvgImagePattern
    local function stub(name, values)
        ctx.deps[name] = setmetatable(values, { __index = function(_, key)
            ctx.transactionCalls = ctx.transactionCalls + 1
            return denied("dependency " .. name .. "." .. tostring(key))()
        end })
        return ctx.deps[name]
    end
    local function widget(kind, props)
        local w = { kind = kind, props = copy(props or {}), children = (props or {}).children or {}, destroyed = false } ---@type any
        function w:SetText(text) self.props.text = text end
        function w:SetStyle(values) for key, value in pairs(values) do self.props[key] = value end end
        function w:SetVisible(value) self.props.visible = value end
        function w:SetDisabled(value) self.props.disabled = value end
        function w:SetWidth(value) self.props.width = value end
        function w:SetHeight(value) self.props.height = value end
        function w:Destroy() self.destroyed = true; for _, child in ipairs(self.children) do child:Destroy() end end
        ctx.widgets[#ctx.widgets + 1] = w
        return w
    end
    local function renderTree(w)
        if w.props.visible == false then return end
        if w.Render then w:Render(ctx.vg) end
        for _, child in ipairs(w.children) do renderTree(child) end
    end
    stub("urhox-libs/UI", { Panel = function(props) return widget("Panel", props) end,
        Button = function(props) return widget("Button", props) end,
        Label = function(props) return widget("Label", props) end,
        Theme = { FontFace = function(value) return value or "sans" end, FontSize = function(value) return value end } })
    stub("ui.widget.DesignWidgetSurface", { init = noop,
        draw = function(root, vg, width, height)
            eq(vg, ctx.vg, "Surface only isolated VG")
            ctx.surfaces[#ctx.surfaces + 1] = { root = root, width = width, height = height,
                x = ctx.transform.tx, y = ctx.transform.ty, alpha = ctx.transform.alpha }
            record("surface", { w = width, h = height, x = ctx.transform.tx, y = ctx.transform.ty, alpha = ctx.transform.alpha })
            renderTree(root)
        end })
    stub("config.ArtifactAssetUtil", { drawIcon = function(_, item, cx, cy, size, opts)
        geometry("artifact", cx, cy, size, size, { artifactId = item.artifactId, id = item.id,
            quality = item.quality, value = item.value, threatClearValue = item.threatClearValue, opts = copy(opts) })
    end })
    stub("ui.widget.ImageCache", { getArtifactIcon = function(id)
        record("artifactIcon", { artifactId = id })
        if ctx.imageMode ~= "ok" then return -1 end
        return env.nvgCreateImage(ctx.vg, "image/test/artifact_" .. tostring(id) .. ".png", 0)
    end })
    stub("core.I18n", { get = function() return ctx.language end, lookup = function(value) return value end,
        t = function(value) return value end, format = string.format,
        displayText = env.nvgText, displayBounds = env.nvgTextBounds, displayTextBoxBounds = env.nvgTextBoxBounds })
    stub("core.DarkIcon", { Palette = { BONE = { 240, 230, 210 }, BONE_DIM = { 170, 160, 150 },
            GOLD = { 194, 154, 96 }, BG_DEEP = { 10, 9, 12 } },
        drawQualityBg = function(_, q, cx, cy, w, h, alpha) geometry("qualityBg", cx, cy, w, h, { quality = q, faceAlpha = alpha }) end,
        drawNine = function(_, image, cx, cy, w, h, alpha) geometry("nine", cx, cy, w, h, { image = image, faceAlpha = alpha }) end })
    stub("ui.widget.RepeatDrawButton", {
        draw = function(_, cx, cy, w, h, text, parts, enough)
            geometry("button", cx, cy, w, h, { text = text, parts = copy(parts), enough = enough })
        end,
        hit = function(x, y, cx, cy, w, h) return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5 end,
    })
    stub("systems.GameSFX", { preload = function(key) check(key:sub(1, 14) == "artifact_draw_", "only artifact cue prewarm") end,
        play = function(key)
            local allowed = false; for _, cue in ipairs(CUES) do if key == cue then allowed = true end end
            check(allowed, "only four deterministic artifact cues")
            ctx.plays[#ctx.plays + 1] = { key = key, at = ctx.clock.elapsedTime }
            ctx.activeCues[key] = true
        end,
        stopCue = function(key) ctx.stops[#ctx.stops + 1] = key; ctx.activeCues[key] = nil end })
    -- 任何事务访问立即报错；纯ArtifactDefs完整真实源码，但绝不roll/normalize。
    for _, name in ipairs({ "core.GameState", "runtime.ClientDispatcher", "runtime.GameClient", "core.PlayerStore",
        "rules.artifact.ArtifactService", "rules.character.PlayerDataManager", "systems.ArtifactSystem" }) do stub(name, {}) end
    env.require = function(name)
        ctx.required[#ctx.required + 1] = name
        if ctx.deps[name] then return ctx.deps[name] end
        if name:sub(1, 5) == "host." then return denied("host source is read-only, never executable " .. name)() end
        local relative = SOURCE_FILES[name]
        if not relative then return denied("require " .. tostring(name))() end
        local chunk = assert(load(source(name), "@" .. ROOT .. "/scripts/" .. relative, "t", env))
        local result = chunk()
        assert(type(result) == "table", "actual module must return table " .. name)
        ctx.deps[name] = result; ctx.executions[name] = (ctx.executions[name] or 0) + 1
        return result
    end
    ctx.defs = env.require("shared.artifact.ArtifactDefs")
    ctx.timeline = env.require("ui.tavern.RecruitTimeline")
    ctx.presentation = env.require("ui.church.ArtifactDrawPresentation")
    -- 包装仅记录后透传真正Presentation函数，不能用spy替代本专项真实调用链。
    for _, name in ipairs({ "init", "prepare", "setStatus", "setCost", "drawBackground", "drawIntro", "drawBack",
        "drawCardGlow", "drawFront", "drawCardText", "drawLabels", "destroy" }) do
        local fn = assert(ctx.presentation[name], "missing actual Presentation API " .. name)
        ctx.presentation[name] = function(...)
            local args = { ... }
            ctx.presentationCalls[#ctx.presentationCalls + 1] = { name = name, args = copy(args) }
            return fn(...)
        end
    end
    ctx.anim = env.require("ui.church.ArtifactDrawAnim")
    if options.init ~= false then ctx.anim.init(ctx.vg) end
    function ctx.quote(count, chest)
        ctx.costCalls = ctx.costCalls + 1
        return { parts = { { type = "golden_key", amount = count * (chest == "advanced" and 5 or 1) } }, enough = true }
    end
    function ctx.start(list, onClose, count, chest, opts)
        if type(list) == "table" then ctx.fixtures[#ctx.fixtures + 1] = { original = list, snapshot = copy(list) } end
        return ctx.anim.start(list, onClose, count, chest or "normal", opts or { getCost = ctx.quote })
    end
    function ctx.at(value, dt) ctx.clock.elapsedTime = value; ctx.anim.update(dt or 0) end
    function ctx.draw(value, update)
        if value ~= nil then ctx.clock.elapsedTime = value end
        if update ~= false then ctx.anim.update(0) end
        ctx.calls, ctx.surfaces = {}, {}
        local before = copy(ctx.transform)
        local plays, costs, loads = #ctx.plays, ctx.costCalls, #ctx.loads
        ctx.anim.draw(ctx.vg)
        eq(#ctx.stack, 0, "real Anim/Presentation balance VG save/restore")
        check(same(ctx.transform, before), "real draw restores transform/alpha")
        eq(#ctx.plays, plays, "draw makes zero SFX calls")
        eq(ctx.costCalls, costs, "draw makes zero getCost reads")
        eq(#ctx.loads, loads, "draw does not create/load new images")
        check(finite(ctx.calls), "all draw samples finite")
        return ctx.calls
    end
    return ctx
end
local function calls(ctx, kind)
    local list = {}; for _, call in ipairs(ctx.calls) do if call.kind == kind then list[#list + 1] = call end end; return list
end
local function presented(ctx, name)
    local list = {}; for _, call in ipairs(ctx.presentationCalls) do if call.name == name then list[#list + 1] = call end end; return list
end
local function status(ctx)
    local list = presented(ctx, "setStatus"); return assert(list[#list], "actual Presentation status not supplied").args
end
local function cueCount(ctx, key)
    local count = 0; for _, play in ipairs(ctx.plays) do if play.key == key then count = count + 1 end end; return count
end
local function safe(ctx)
    eq(#ctx.forbidden, 0, "strict private env denies no unknown/native/player path")
    eq(ctx.rngCalls, 0, "no gameplay random/randomseed consumption")
    eq(ctx.transactionCalls, 0, "no transaction/save/player-store calls")
    check(same(ctx.memory, ctx.initialMemory), "currency/artifact bag memory unchanged")
    for _, fixture in ipairs(ctx.fixtures) do check(same(fixture.original, fixture.snapshot), "real receipt scalars/order unchanged") end
end

local function isolationAndTimelineCases()
    local a, b = newContext(), newContext()
    check(a.anim ~= b.anim and a.timeline ~= b.timeline and a.presentation ~= b.presentation, "real modules private per env")
    eq(a.env._G, a.env, "private _G has no native fallback")
    for name in pairs(SOURCE_FILES) do
        if name:sub(1, 5) ~= "host." then eq(a.executions[name], 1, "actual source executes once per env " .. name) end
    end
    near(a.timeline.INTRO_DURATION, INTRO, "independent intro oracle")
    near(a.timeline.CARD_DURATION, CARD, "independent card oracle")
    near(a.timeline.CARD_DELAY, DELAY, "independent stagger oracle")
    near(a.timeline.FADE_DURATION, FADE, "independent fade oracle")
    for _, count in ipairs({ 1, 10 }) do near(a.timeline.cardSpan(count), span(count), "real timeline span " .. count) end
    for i = 1, 10 do
        local delay = (i - 1) * DELAY
        eq(a.timeline.card(delay, i).visible, false, "exact card local-time zero remains hidden " .. i)
        eq(a.timeline.card(delay + EPS, i).visible, true, "first positive local time visible " .. i)
        eq(a.timeline.card(delay + CARD - EPS, i).settled, false, "not ready early " .. i)
        eq(a.timeline.card(delay + CARD + EPS, i).settled, true, "ready past exact span " .. i)
        for step = 0, 20 do
            local pose = a.timeline.card(delay + CARD * step / 20, i)
            check(finite(pose) and pose.scaleX >= 0.045 and pose.scale > 0 and pose.alpha >= 0 and pose.alpha <= 1,
                "real flip never makes degenerate transform " .. i .. "/" .. step)
        end
    end
    eq(a.anim.isPlaying(), false, "fresh actual animation idle")
    eq(a.anim.handleInput(BUTTON_X, BUTTON_Y), false, "idle input not consumed")
    eq(a.anim.dismiss(), false, "idle seam dismiss not consumed")
    a.draw(); b.draw()
    eq(#a.calls + #b.calls, 0, "unstarted draw inert")
    check(a.start(receipt(1), nil, 1), "shared result background fixture starts")
    a.draw(0.5)
    local backgrounds = 0
    for _, image in ipairs(calls(a, "image")) do
        if image.path == "image/界面底板/酒馆抽卡/UI_XKJM.png" then
            backgrounds = backgrounds + 1
            eq(image.w, 1080, "same recruit background covers design width")
            eq(image.h, 2400, "same recruit background covers design height")
            near(image.imageAlpha, 0.72, "same recruit background opacity")
        end
    end
    eq(backgrounds, 1, "artifact uses exactly one actual recruit result background")
    local loads = #a.loads
    a.anim.init(a.vg)
    eq(#a.loads, loads, "shared asset still keeps its own idempotent image cache")
    a.anim.close()
    safe(a); safe(b)
end

local function invalidAndUnavailableCases()
    local absent = newContext({ init = false })
    eq(absent.start(receipt(1), noop, 1), false, "not initialized actual animation returns false for host fallback")
    eq(absent.anim.isPlaying(), false, "uninitialized start does not create hidden playing state")
    eq(#absent.plays, 0, "uninitialized start does not emit cue")
    safe(absent)
    local invalid = { { label = "nil", value = nil }, { label = "false", value = false },
        { label = "number", value = 12 }, { label = "string", value = "receipt" },
        { label = "empty", value = {} }, { label = "empty row", value = { {} } },
        { label = "two draws", value = receipt(2) }, { label = "eleven draws", value = {} } }
    for i = 1, 11 do invalid[8].value[i] = copy(receipt(1)[1]); invalid[8].value[i].id = "invalid_count_" .. i end
    for _, change in ipairs({ { key = "id", value = "" }, { key = "id", value = 0 },
        { key = "artifactId", value = 999 }, { key = "artifactId", value = "bad" },
        { key = "quality", value = 0 }, { key = "quality", value = 7 }, { key = "quality", value = 1.5 },
        { key = "value", value = math.huge }, { key = "value", value = 0/0 },
        { key = "valueRatio", value = math.huge }, { key = "threatClearValue", value = 0/0 },
        { key = "threatClearRatio", value = -math.huge } }) do
        local item = receipt(1); item[1][change.key] = change.value
        invalid[#invalid + 1] = { label = change.key .. "=" .. tostring(change.value), value = item }
    end
    local missingX, missingY = receipt(1), receipt(1)
    missingX[1].value, missingY[1].threatClearValue = nil, nil
    invalid[#invalid + 1] = { label = "missing actual X", value = missingX }
    invalid[#invalid + 1] = { label = "missing actual Y never midpoint", value = missingY }
    for _, entry in ipairs(invalid) do
        local ctx = newContext()
        eq(ctx.start(entry.value, noop, nil), false, "invalid receipt rejected " .. entry.label)
        eq(ctx.anim.isPlaying(), false, "invalid receipt cannot start " .. entry.label)
        eq(#ctx.plays, 0, "invalid receipt cannot consume cue " .. entry.label)
        ctx.draw(); eq(#ctx.calls, 0, "invalid receipt cannot draw " .. entry.label)
        safe(ctx)
    end
    local ctx = newContext()
    eq(ctx.start(receipt(1), nil, 10), false, "explicit count mismatch cannot turn one receipt into ten")
    eq(ctx.start(receipt(10), nil, 1), false, "explicit count mismatch cannot truncate ten to one")
    eq(ctx.start(receipt(1), nil, 1, "missing_chest"), false, "invalid chest never normal-fallback anim")
    eq(ctx.anim.isPlaying(), false, "all count/chest failures atomic")
    check(ctx.start(receipt(1), nil, 1), "valid receipt starts after invalid attempts")
    local playingBefore = #ctx.plays
    eq(ctx.start({}, noop, 1), false, "invalid replacement refuses new batch")
    eq(ctx.anim.isPlaying(), true, "invalid replacement cannot discard existing actual receipt")
    eq(#ctx.plays, playingBefore, "invalid replacement emits no next charge")
    ctx.draw(8); ctx.anim.close(); safe(ctx)
end

local function realIdentityAndOrderCases(count)
    local ctx = newContext()
    local list = receipt(count)
    local closed = 0
    check(ctx.start(list, function() closed = closed + 1 end, count, "advanced"), "valid actual artifact receipt starts")
    local prepared = presented(ctx, "prepare")
    eq(#prepared, 1, "real Presentation prepares one batch")
    for i, expected in ipairs(list) do
        local actual = prepared[1].args[1][i]
        for _, key in ipairs({ "id", "artifactId", "quality", "value", "valueRatio", "threatClearValue", "threatClearRatio" }) do
            eq(actual[key], expected[key], "prepare scalar snapshot preserved " .. i .. "/" .. key)
        end
    end
    ctx.draw(8)
    local fronts = presented(ctx, "drawFront")
    eq(#fronts, count, "exactly one real Presentation front per receipt, no grouped quality reorder")
    local background = calls(ctx, "artifact")
    eq(#background, count, "actual icon leaf receives one true artifact identity per card")
    for i, front in ipairs(fronts) do
        local item = front.args[2]
        eq(item.id, list[i].id, "front keeps original receipt order " .. i)
        eq(item.artifactId, list[i].artifactId, "front keeps actual artifact type " .. i)
        eq(item.quality, list[i].quality, "front never upgrades/reorders rarity " .. i)
        eq(item.value, list[i].value, "front retains actual X " .. i)
        eq(item.valueRatio, list[i].valueRatio, "front retains ratio not recomputed from X " .. i)
        eq(item.threatClearValue, list[i].threatClearValue, "front retains actual Y " .. i)
        eq(background[i].quality, list[i].quality, "background derives actual q1..6 " .. i)
        near(front.args[3], count == 1 and 540 or 128 + ((i - 1) % 5) * 206, "settled design center X " .. i)
        near(front.args[4], count == 1 and 1110 or (i <= 5 and 760 or 1400), "settled design center Y " .. i)
        eq(front.args[5], count == 1 and 740 or 188, "card width matches actual single/5x2 layout")
        eq(front.args[6], count == 1 and 1260 or 520, "card height preserves complete effect room")
    end
    eq(closed, 0, "all ready never auto-claims/closes")
    ctx.anim.close(); eq(closed, 1, "whole batch close callback once, not once per artifact")
    safe(ctx)
end

local function naturalCueCases(count, highQuality)
    local ctx = newContext()
    local list = receipt(count)
    -- 第一张/后续低品质先播reveal；第3张史诗触发legendary。品质不改变业务结果或原序。
    for i, item in ipairs(list) do
        item.artifactId = 1; item.quality = highQuality and ((count == 1 or i == 3) and 4 or 1) or 1
        item.value = 127.4
        item.threatClearValue, item.threatClearRatio = nil, nil
    end
    local closed, continued = 0, 0
    check(ctx.start(list, function() closed = closed + 1 end, count, "normal",
        { getCost = ctx.quote, onContinue = function() continued = continued + 1 end }), "natural batch starts")
    eq(cueCount(ctx, CUES[1]), 1, "charge emitted once at successful start")
    ctx.draw(0); ctx.at(0); ctx.at(INTRO - EPS)
    eq(#ctx.plays, 1, "no front/settle cue before intro finishes")
    ctx.draw(INTRO); eq(status(ctx)[1], "cards", "intro transitions at planned boundary")
    eq(cueCount(ctx, CUES[1]), 1, "intro does not replay charge")
    local expectedReveal, expectedLegendary = 0, 0
    for i = 1, count do
        local at = INTRO + (i - 1) * DELAY + CARD * 0.58
        ctx.at(at - EPS)
        local before = #ctx.plays
        ctx.at(at + EPS)
        local q = list[i].quality
        if q >= 4 then
            if expectedLegendary == 0 then expectedLegendary = 1 end
        else expectedReveal = expectedReveal + 1 end
        eq(cueCount(ctx, CUES[2]), expectedReveal, "one reveal per newly crossed low-q front " .. i)
        eq(cueCount(ctx, CUES[3]), expectedLegendary, "first real epic+ only one legendary per batch " .. i)
        check(#ctx.plays - before <= 1, "one new-front frame emits at most one reveal/legendary " .. i)
        local plays = #ctx.plays
        for _ = 1, 10 do ctx.anim.update(99999) end
        eq(#ctx.plays, plays, "same timestamp repeated update never replays consumed front " .. i)
        ctx.draw(nil, false); eq(#ctx.plays, plays, "real draw cannot emit front cue " .. i)
    end
    ctx.at(INTRO + span(count) - EPS)
    eq(cueCount(ctx, CUES[4]), 0, "settle not before actual last card span")
    ctx.at(INTRO + span(count) + EPS)
    eq(status(ctx)[2], true, "ready after complete real staggered batch")
    eq(cueCount(ctx, CUES[4]), 1, "settle exactly once after all actual cards")
    for _ = 1, 10 do ctx.anim.update(0); ctx.draw(nil, false) end
    eq(cueCount(ctx, CUES[4]), 1, "ready sampling never repeats settle")
    eq(cueCount(ctx, CUES[1]), 1, "full natural flow charge once")
    eq(cueCount(ctx, CUES[3]), highQuality and 1 or 0, "legendary based on actual epic+ only")
    eq(closed + continued, 0, "natural cues cannot claim/close/request next batch")
    ctx.anim.close(); eq(closed, 1, "one batch close after natural sequence")
    safe(ctx)
end

local function catchUpCueCases()
    for _, count in ipairs({ 1, 10 }) do
        for _, high in ipairs({ false, true }) do
            local ctx = newContext()
            local list = receipt(count)
            for _, item in ipairs(list) do
                item.artifactId, item.quality, item.value = 1, high and 5 or 1, 127.4
                item.threatClearValue, item.threatClearRatio = nil, nil
            end
            check(ctx.start(list, nil, count), "catch-up valid receipt")
            ctx.at(100)
            eq(status(ctx)[2], true, "late update uses planned timestamp, no extra animation delay")
            eq(cueCount(ctx, CUES[1]), 1, "catch-up charge once")
            eq(cueCount(ctx, CUES[2]), 0, "late all-ready frame does not flood ten reveal cues")
            eq(cueCount(ctx, CUES[3]), high and 1 or 0, "catch-up only actual necessary legendary")
            eq(cueCount(ctx, CUES[4]), 1, "catch-up settle once")
            for _ = 1, 30 do ctx.at(101); ctx.draw(nil, false) end
            eq(cueCount(ctx, CUES[2]), 0, "all consumed catch-up fronts cannot backfill later")
            eq(cueCount(ctx, CUES[4]), 1, "later catch-up update no repeat settle")
            safe(ctx)
        end
    end
end

local function skipAndSameFrameCases(count, viaDismiss, inCards)
    local ctx = newContext()
    local closed, continued = 0, 0
    check(ctx.start(receipt(count), function() closed = closed + 1 end, count, "advanced",
        { getCost = ctx.quote, onContinue = function() continued = continued + 1 end }), "skip batch starts")
    ctx.draw(inCards and INTRO + 0.1 or 0)
    local before = #ctx.plays
    if viaDismiss then eq(ctx.anim.dismiss(), true, "first seam dismiss reveals only")
    else eq(ctx.anim.handleInput(BUTTON_X, BUTTON_Y), true, "first continue-coordinate click reveals only") end
    ctx.draw(nil, false)
    eq(status(ctx)[1], "cards", "skip moves to full results not fade")
    eq(status(ctx)[2], true, "skip reveals all actual cards immediately")
    local latest = presented(ctx, "drawFront")
    check(#latest >= count, "skip truly calls real Presentation for all cards")
    eq(cueCount(ctx, CUES[2]), 0, "skip before any front never emits pending ten reveal cues")
    eq(cueCount(ctx, CUES[3]), 1, "skip emits necessary highest actual legendary once")
    eq(cueCount(ctx, CUES[4]), 1, "skip emits settle once")
    check(#ctx.plays - before <= 2, "skip merges remaining batch cues into at most legendary+settle")
    eq(closed + continued, 0, "first skip cannot close/call business continue")
    eq(ctx.anim.dismiss(), false, "same-frame repeat seam does not close newly revealed batch")
    ctx.anim.handleInput(BUTTON_X, BUTTON_Y); ctx.anim.handleInput(10, 10)
    eq(closed + continued, 0, "same-frame second click cannot continue or fade")
    ctx.at(ctx.clock.elapsedTime + 0.1)
    local after = #ctx.plays
    for _ = 1, 20 do ctx.anim.update(0); ctx.draw(nil, false) end
    eq(#ctx.plays, after, "consumed skipped fronts never backfill next-frame ten sounds")
    eq(cueCount(ctx, CUES[2]), 0, "after skip all remaining reveal cues are consumed")
    ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
    eq(continued, 1, "fresh ready frame allows exactly one continue")
    ctx.anim.handleInput(BUTTON_X, BUTTON_Y); ctx.anim.update(999)
    eq(continued, 1, "same frame and waiting update never duplicate continue")
    eq(ctx.anim.dismiss(), false, "same-frame after continue cannot dismiss")
    ctx.clock.elapsedTime = ctx.clock.elapsedTime + 0.1
    eq(ctx.anim.dismiss(), true, "next-frame ready results can close even awaiting receipt")
    ctx.at(ctx.clock.elapsedTime + FADE + EPS)
    eq(closed, 1, "skip/repeat whole-batch close callback once after fade")
    eq(ctx.anim.isPlaying(), false, "skip/continue/fade ends idle")
    safe(ctx)
end

local function continueReentryCases()
    for _, count in ipairs({ 1, 10 }) do
        local ctx = newContext()
        local oldClosed, newClosed, continued = 0, 0, 0
        local nextCount = count == 1 and 10 or 1
        local opts = { getCost = ctx.quote }
        opts.onContinue = function(actualCount)
            continued = continued + 1
            eq(actualCount, count, "continue receives frozen actual count")
            check(ctx.start(receipt(nextCount), function() newClosed = newClosed + 1 end, nextCount, "normal",
                { getCost = ctx.quote, onContinue = noop }), "synchronous next batch starts")
            return true
        end
        check(ctx.start(receipt(count), function() oldClosed = oldClosed + 1 end, count, "advanced", opts), "old actual batch starts")
        ctx.draw(INTRO + span(count) + EPS)
        local beforeCharges = cueCount(ctx, CUES[1])
        ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
        eq(continued, 1, "one ready continue callback before synchronous start")
        ctx.draw(nil, false)
        eq(status(ctx)[1], "intro", "synchronous start not overwritten by old handleInput state")
        eq(status(ctx)[4], "normal", "next batch chest preserved through old stack return")
        ctx.anim.update(1000); ctx.draw(nil, false)
        eq(status(ctx)[1], "intro", "old update cannot settle synchronous new start at same timestamp")
        eq(cueCount(ctx, CUES[1]), beforeCharges + 1, "new receipt starts exactly one new charge")
        ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
        eq(ctx.anim.dismiss(), false, "same-frame dismiss barrier survives synchronous start")
        eq(continued, 1, "same-frame extra click cannot send second request")
        eq(oldClosed + newClosed, 0, "repeat start queues whole-batch callbacks rather than early claiming")
        ctx.anim.close(); ctx.anim.close()
        eq(oldClosed, 1, "old batch close callback once after replacement")
        eq(newClosed, 1, "new batch callback once on its own final close")
        safe(ctx)
    end
    local ctx = newContext()
    local continued = 0
    check(ctx.start(receipt(1), nil, 1, "normal", { getCost = ctx.quote,
        onContinue = function() continued = continued + 1; return false end }), "declined-send fixture starts")
    ctx.draw(8); ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
    eq(continued, 1, "declined continue invoked once")
    ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
    eq(continued, 1, "declined same-frame send still guarded")
    ctx.at(8.1); ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
    eq(continued, 2, "explicit false declines may retry on later frame")
    safe(ctx)
end

local function closeDestroyReentryCases()
    local ctx = newContext()
    local order, counts = {}, {0,0,0}
    ctx.start(receipt(1), function() counts[1] = counts[1] + 1; order[#order + 1] = "old"; ctx.anim.close() end, 1)
    ctx.start(receipt(10), function()
        counts[2] = counts[2] + 1; order[#order + 1] = "current"
        ctx.start(receipt(1), function() counts[3] = counts[3] + 1 end, 1)
    end, 10)
    ctx.anim.close()
    check(same(counts, {1,1,0}) and same(order, {"old","current"}), "close drains detached whole batch once in stable order")
    check(ctx.anim.isPlaying(), "callback-started new batch survives reentrant outer close")
    ctx.draw(nil, false); eq(status(ctx)[1], "intro", "reentrant callback state remains fresh intro")
    ctx.anim.close(); ctx.anim.close(); check(same(counts, {1,1,1}), "reentrant new callback only own close once")
    local suppressed = 0
    ctx.start(receipt(1), function() suppressed = suppressed + 1 end, 1)
    ctx.start(receipt(10), function() suppressed = suppressed + 1 end, 10)
    ctx.activeCues.foreign_combat = true
    ctx.anim.destroy()
    eq(suppressed, 0, "destroy cancels all queued/active callbacks without claiming")
    eq(ctx.anim.isPlaying(), false, "destroy cancels immediately")
    for _, cue in ipairs(CUES) do eq(ctx.activeCues[cue], nil, "destroy stops own cue " .. cue) end
    eq(ctx.activeCues.foreign_combat, true, "destroy never calls global audio stop or foreign cue")
    local played = #ctx.plays
    ctx.anim.update(999); ctx.anim.close(); ctx.draw(nil, false)
    eq(#ctx.plays, played, "destroyed update/draw never restarts cue")
    eq(suppressed, 0, "post-destroy close cannot resurrect callbacks")
    eq(ctx.start(receipt(1), noop, 1), false, "destroyed context refuses start until explicit init")
    ctx.anim.init(ctx.vg)
    check(ctx.start(receipt(1), nil, 1), "fresh explicit init may restore context")
    ctx.anim.close(); safe(ctx)
end

local function inputHotspotAndNoCallbackCases()
    -- 与用户约定的独立设计空间热区，含端点；边外不能继续，不从production.hit反推oracle。
    for _, point in ipairs({ {220,2120}, {860,2120}, {540,2170}, {220,2220}, {860,2220},
        {219.999,2170}, {860.001,2170}, {540,2119.999}, {540,2220.001} }) do
        local ctx = newContext()
        local continued = 0
        ctx.start(receipt(1), nil, 1, "advanced", { getCost = ctx.quote,
            onContinue = function() continued = continued + 1 end })
        ctx.draw(INTRO + span(1))
        eq(status(ctx)[2], true, "exact finish boundary becomes ready")
        local buttons = calls(ctx, "button")
        eq(#buttons, 1, "ready actual Presentation draws one continue button")
        eq(buttons[1].x, BUTTON_X, "button centerX")
        eq(buttons[1].y, BUTTON_Y, "button centerY")
        eq(buttons[1].w, 640, "button width")
        eq(buttons[1].h, 100, "button height")
        ctx.anim.handleInput(point[1], point[2])
        local inside = point[1] >= 220 and point[1] <= 860 and point[2] >= 2120 and point[2] <= 2220
        eq(continued, inside and 1 or 0, "inclusive independent hotspot no out-of-area continue")
        safe(ctx)
    end
    local absent = newContext()
    absent.start(receipt(1), nil, 1)
    absent.draw(8)
    eq(#calls(absent, "button"), 0, "no onContinue callback means no usable repeat button")
    absent.anim.handleInput(BUTTON_X, BUTTON_Y)
    absent.draw(nil, false); eq(status(absent)[1], "fadeOut", "unavailable button hotspot is normal dismiss, never fake business")
    safe(absent)
end

local function drawPurityAndMissingImageCases()
    for _, mode in ipairs({ "ok", "missing", "throw" }) do
        local ctx = newContext({ imageMode = mode })
        check(ctx.start(receipt(10), nil, 10), "missing-image tolerant actual batch " .. mode)
        local at = INTRO + 0.08
        ctx.at(INTRO)
        local first = copy(ctx.draw(at, false))
        ctx.draw(INTRO + 0.2, false)
        check(same(first, ctx.draw(at, false)), "actual Anim+Timeline+Motion A-B-A deterministic draw " .. mode)
        for _ = 1, 8 do check(same(first, ctx.draw(at, false)), "repeated pure draw same calls " .. mode) end
        ctx.draw(8)
        eq(status(ctx)[2], true, "missing images never block full result reveal " .. mode)
        if mode ~= "ok" then eq(#calls(ctx, "image"), 0, "no invalid handle reaches native-shaped sample " .. mode) end
        ctx.clock.elapsedTime = 0/0
        local invalidPlays, invalidCosts = #ctx.plays, ctx.costCalls
        local invalidCalls = #ctx.calls
        ctx.anim.draw(ctx.vg)
        check(#ctx.calls > invalidCalls and finite(ctx.calls), "invalid engine clock samples last finite host-owned time safely")
        eq(#ctx.plays, invalidPlays, "invalid-clock draw no audio")
        eq(ctx.costCalls, invalidCosts, "invalid-clock draw no getCost")
        ctx.clock.elapsedTime = 8
        local played, costs = #ctx.plays, ctx.costCalls
        ctx.anim.dismiss(); ctx.clock.elapsedTime = 8 + FADE + EPS
        ctx.draw(nil, false)
        eq(#ctx.plays, played, "draw-only expired fade never emits cues")
        eq(ctx.costCalls, costs, "draw-only expired fade never reads cost")
        eq(ctx.anim.isPlaying(), true, "draw cannot complete fade or close receipt")
        ctx.anim.update(0)
        eq(ctx.anim.isPlaying(), false, "host update owns fade completion")
        safe(ctx)
    end
end

local function fiveLanguageCompleteTextCases()
    local longNames = {
        zh_CN = "星辉护符·守望永夜与黎明的远征队长传承之至臻神器完整名称",
        zh_TW = "星輝護符·守望永夜與黎明的遠征隊長傳承之至臻神器完整名稱",
        en = "Starlight Amulet of the Unbroken Expedition Covenant Beyond the Eternal Dawn",
        ja = "星輝の護符・永遠の夜明けを守り続ける遠征隊長の至高なる継承神器の完全な名前",
        ko = "별빛 부적 · 영원한 새벽을 지키는 원정대장의 최고의 계승 신기 전체 이름",
    }
    local expectedEffects = {
        zh_TW = "護盾加成額外增加73.8%，護盾破碎後，清除當前63.4%的仇恨值",
        en = "Gain an extra 73.8% shield bonus. When the shield breaks, clear 63.4% of current threat.",
        ja = "シールドボーナスを追加で73.8%。シールド破壊時、現在のヘイトを63.4%除去。",
        ko = "보호막 보너스 추가 73.8%. 보호막 파괴 시 현재 위협 수치의 63.4% 제거.",
    }
    for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
        for _, count in ipairs({ 1, 10 }) do
            local ctx = newContext({ language = lang })
            local list = receipt(count)
            list[1].name = longNames[lang]
            check(ctx.start(list, nil, count), "real language display starts " .. lang .. "/" .. count)
            ctx.draw(8)
            local surface = assert(ctx.surfaces[1], "actual card text Surface exists")
            local leaves = surface.root.children
            eq(#leaves, 3, "card has only quality/name/effect labels, no formula value rows")
            eq(leaves[2].props.text, longNames[lang], "five-language long name complete, no elision/truncation " .. lang)
            for _, leaf in ipairs(leaves) do
                check(not leaf.props.text:find("X", 1, true) and not leaf.props.text:find("Y", 1, true),
                    "player card never displays formula placeholders " .. lang)
            end
            local realEffect = ctx.defs.getEffectText(list[1])
            check(realEffect:find("73.8%", 1, true) ~= nil and realEffect:find("63.4%", 1, true) ~= nil,
                "real ArtifactDefs.getEffectText uses exact completed receipt X/Y")
            check(not realEffect:find("57.5%", 1, true), "real Y never missing-field range midpoint")
            if count == 1 then
                eq(leaves[3].props.text, lang == "zh_CN" and realEffect or expectedEffects[lang],
                    "complete player-readable effect includes both actual properties " .. lang)
                eq(leaves[3].props.visible, true, "single full effect is visible")
            else
                eq(leaves[3].props.visible, false, "ten-card compact layout shows name and quality only")
                eq(leaves[3].props.text, "", "ten-card layout has no standalone attribute numbers")
            end
            for _, index in ipairs({ 1, 2, 3 }) do
                local props = leaves[index].props
                if props.visible ~= false then
                    check(props.left >= 0 and props.top >= 0 and props.left + props.width <= surface.width
                        and props.top + props.height <= surface.height, "five-language visible label remains within real card " .. lang .. "/" .. index)
                    check(props.fontSize > 0 and props.flexShrink == 1, "explicit finite size and shrink avoid overflowing text")
                    if props.whiteSpace == "normal" then
                        local glyphs = utf8.len(props.text) or #props.text
                        local lines = math.max(1, math.ceil(glyphs * props.fontSize * 0.56 / (props.width - 8)))
                        check(lines * props.fontSize * 1.18 <= props.height - 8 + EPS,
                            "complete multiline text fits explicit measured leaf bounds " .. lang .. "/" .. index)
                    end
                end
            end
            local snapshot = copy(list)
            ctx.language = lang == "en" and "ja" or "en"
            ctx.at(8.1); ctx.draw(nil, false)
            check(same(list, snapshot), "live language update does not mutate receipt fields")
            safe(ctx)
        end
    end
end

local function includes(text, fragment, label)
    check(text:find(fragment, 1, true) ~= nil, "actual host source fragment " .. label)
end
local function ordered(text, first, second, label)
    local a, b = text:find(first, 1, true), text:find(second, 1, true)
    check(a ~= nil and b ~= nil and a < b, "actual host source order " .. label)
end
local function hostSourceCases()
    -- 宿主只固定源码片段读取，不执行boot，不把全局/玩家依赖带入env。
    local input = source("host.ChurchInput")
    ordered(input, "return ArtifactDrawPanel.handleAnimationInput(dx, dy)", 'if state.tab == "shenqi" then',
        "draw animation consumes clicks before artifact/card/tab/back")
    for _, name in ipairs({ "handleDragBegin", "handleDragMove", "handleDragEnd", "handleScroll" }) do
        local start = assert(input:find("local function " .. name, 1, true))
        local ending = input:find("local function ", start + 15, true)
        local body = input:sub(start, ending and ending - 1 or #input)
        local afterGate = (name == "handleDragEnd" or name == "handleDragMove")
            and "if state.rosterDragging" or "isRosterVisible()"
        ordered(body, "ArtifactDrawPanel.isAnimationPlaying", afterGate,
            "animation drag/scroll modal gate " .. name)
    end
    local seam = source("host.SeamBackGesture")
    ordered(seam, '== "church" and ArtifactDrawAnim.isPlaying()', "local now = time.elapsedTime",
        "church seam dismiss before ordinary close/tap timestamp")
    includes(seam, "ArtifactDrawAnim.dismiss()", "seam forwards first reveal/dismiss, not page close")
    local page = source("host.ChurchPage")
    includes(page, "ArtifactDrawPanel.updateAnimation(dt)", "ChurchPage owns animation updates")
    includes(page, "ArtifactDrawPanel.closeAnimation()", "ChurchPage close invalidates repeat generation")
    local draw = source("host.ChurchDraw")
    ordered(draw, "ArtifactDrawPanel.drawKeyConfirmDialog(vg)", "ArtifactDrawPanel.drawAnimation(vg)",
        "reveal animation is last overlay above key confirmation")
    local results = source("host.ChurchResults")
    ordered(results, "ArtifactDrawPanel.onArtifactDrawResult()", "if state.closing then return end",
        "late closing receipt releases pending before refusing invisible animation")
    ordered(results, "if state.closing then return end", "ArtifactDrawPanel.onArtifactDrawSuccess(data)",
        "late closing receipt cannot restart canceled reveal")
    includes(results, "if not ArtifactDrawPanel.isAnimationPlaying() then", "legacy reward toast not layered over active animation")
    local panel = source("host.ChurchArtifactDrawPanel")
    includes(panel, "pcall(ArtifactDrawAnim.start, rewards, nil", "success start protected with actual rewards")
    includes(panel, "if not ok or not playing then", "failed/not initialized animation gets RewardPopup fallback only")
    includes(panel, "RewardPopup.show", "legacy fallback remains")
    includes(panel, "return checkKeyAndDraw(count, chestType)", "continue stays on original frozen chest payment path")
    local continueStart = assert(panel:find("local function continueArtifactDraw", 1, true))
    local continueEnd = assert(panel:find("-- ======================== 绘制", continueStart, true))
    local continueBody = panel:sub(continueStart, continueEnd - 1)
    ordered(continueBody, "generation ~= state.resultGeneration", "ArtifactDrawAnim.close()", "generation guard precedes closing result")
    ordered(continueBody, "ArtifactDrawAnim.close()", "checkKeyAndDraw(count, chestType)", "old result does not cover payment modal")
    local standalone = source("host.Standalone")
    includes(standalone, "ChurchPage.update(dt)", "existing host Update calls ChurchPage animation update")
    ordered(standalone, 'require("ui.church.ArtifactDrawAnim").destroy()', "nvgDelete(vg)",
        "destroy releases only animation cues/UI before VG teardown")
end

function Start()
    local tests = {
        { "strict-real-module-isolation-and-timeline", isolationAndTimelineCases },
        { "empty-illegal-no-init-atomic-refusal", invalidAndUnavailableCases },
        { "single-real-instance-quality-X-Y-order", function() realIdentityAndOrderCases(1) end },
        { "ten-real-instance-quality-X-Y-order", function() realIdentityAndOrderCases(10) end },
        { "single-natural-low-quality-cue", function() naturalCueCases(1, false) end },
        { "single-natural-epic-cue", function() naturalCueCases(1, true) end },
        { "ten-natural-low-front-cue-once-each", function() naturalCueCases(10, false) end },
        { "ten-natural-mixed-front-cue-once-each", function() naturalCueCases(10, true) end },
        { "late-update-no-ten-cue-flood", catchUpCueCases },
        { "single-click-skip-and-same-frame-barrier", function() skipAndSameFrameCases(1, false, false) end },
        { "ten-click-skip-and-same-frame-barrier", function() skipAndSameFrameCases(10, false, false) end },
        { "single-seam-skip-and-same-frame-barrier", function() skipAndSameFrameCases(1, true, false) end },
        { "ten-seam-skip-and-same-frame-barrier", function() skipAndSameFrameCases(10, true, false) end },
        { "ten-cards-skip-consumes-unplayed-cues", function() skipAndSameFrameCases(10, false, true) end },
        { "continue-ready-synchronous-start-survives-old-update", continueReentryCases },
        { "whole-batch-close-reentry-destroy-suppresses-and-stops-own-cues", closeDestroyReentryCases },
        { "real-button-ready-inclusive-hit-no-callback", inputHotspotAndNoCallbackCases },
        { "draw-zero-audio-RNG-IO-and-missing-images", drawPurityAndMissingImageCases },
        { "five-language-player-text-no-formula-labels-real-effect", fiveLanguageCompleteTextCases },
        { "host-fixed-source-animation-input-seam-update-draw-and-late-receipt", hostSourceCases },
    }
    for _, test in ipairs(tests) do
        groups = groups + 1
        local ok, why = pcall(test[2])
        if ok then print(TAG .. "PASS " .. test[1])
        else
            failures[#failures + 1] = test[1] .. " " .. tostring(why)
            print(TAG .. "FAIL " .. failures[#failures])
        end
    end
    local safeOk, safeWhy = pcall(function()
        for _, ctx in ipairs(contexts) do safe(ctx) end
        eq(cache, nativeCache, "runtime cache unchanged")
        eq(File, nativeFile, "runtime File unchanged")
        eq(time, nativeTime, "runtime clock unchanged")
        for name, value in pairs(nativeGlobals) do eq(rawget(_G, name), value, "runtime global unchanged " .. name) end
        for name in pairs(SOURCE_FILES) do eq(package.loaded[name], initialLoaded[name], "native package.loaded never injected " .. name) end
        eq(#sourceReads, 12, "five actual presentation sources plus seven host text files read once")
        for _, read in ipairs(sourceReads) do
            local allowed = false
            for _, relative in pairs(SOURCE_FILES) do if read.relative == relative then allowed = true end end
            check(allowed and read.bytes > 100 and read.path == ROOT .. "/scripts/" .. read.relative,
                "cache only fixed Lua source, never player file")
        end
    end)
    if not safeOk then failures[#failures + 1] = "final-safety " .. tostring(safeWhy); print(TAG .. "FAIL " .. failures[#failures]) end
    ArtifactDrawAnimationTestResult = { groups = groups, checks = checks, failures = copy(failures),
        sourceReads = copy(sourceReads), root = ROOT, gpuAcceptance = false }
    print(TAG .. "RESULT " .. (#failures == 0 and "ALL PASS" or "FAIL") .. " groups=" .. groups
        .. " checks=" .. checks .. " failures=" .. #failures .. " (real Presentation; UI/VG/audio leaves only; not GPU acceptance)")
    engine:Exit()
    if #failures > 0 then error(TAG .. "isolated regression failures=" .. #failures, 0) end
    return ArtifactDrawAnimationTestResult
end
