-- 招募动画专项：实际加载 RecruitTimeline / RecruitAnim，所有依赖只在内存隔离环境中替换。
-- RecruitPresentation 为显式记录桩：检查调用链、卡面/卡背与变换，不是 GPU 或视觉验收。
-- UrhoXRuntime tests/recruit_animation_test.lua -tapcode_dir=/workspace/game3
--   -tool_mode -nosound -graphicsheadless -validate -validate-frames=3
-- 不加载 main，不访问玩家文件，不创建日志、截图、报告、抽奖或发奖请求。

local ROOT = "/workspace/game3"
local arguments = type(GetArguments) == "function" and GetArguments() or {}
for _, argument in ipairs(arguments) do
    local directory = argument:match("^%-tapcode_dir=(.+)$")
    if directory then ROOT = directory:gsub("/+$", "") end
end
local TAG = "[recruit_animation_test] "
local SOURCE_FILES = {
    ["ui.tavern.RecruitTimeline"] = "ui/tavern/RecruitTimeline.lua",
    ["ui.tavern.RecruitAnim"] = "ui/tavern/RecruitAnim.lua",
}
local nativeFile, nativeCache, nativeTime = File, cache, time
local nativeGlobals = {} ---@type table<string, any>
for _, name in ipairs({ "require", "load", "nvgSave", "nvgRestore", "nvgScale", "nvgCreateImage" }) do
    nativeGlobals[name] = rawget(_G, name)
end
local initialLoaded = {} ---@type table<string, any>
for name in pairs(SOURCE_FILES) do initialLoaded[name] = package.loaded[name] end
local sources = {} ---@type table<string, string>
local sourceReads = {} ---@type any[]
local contexts = {} ---@type any[]
local checks, groups = 0, 0
local failures = {} ---@type string[]
local EPS = 0.000001
-- 独立期望值，不从被测模块常量反推完成条件。
local INTRO, CARD, DELAY, FADE = 1.8, 0.66, 0.12, 0.35
local BUTTON_X, BUTTON_Y = 540, 2170

local function check(ok, message)
    checks = checks + 1
    assert(ok, message)
end
local function eq(actual, expected, message)
    check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function near(actual, expected, message)
    check(type(actual) == "number" and math.abs(actual - expected) < 0.0000001,
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
    if type(a) ~= "table" then return a == b end
    for key, child in pairs(a) do if not same(child, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function finite(value)
    if type(value) == "number" then return value == value and math.abs(value) < math.huge end
    if type(value) == "table" then
        for _, child in pairs(value) do if not finite(child) then return false end end
    end
    return true
end
local function noop() end
local function span(count) return CARD + math.max(0, count - 1) * DELAY end

-- 只允许两份真实源码。先尝试固定绝对 File，再尝试脚本资源根下的 cache:GetFile。
-- 缓存的是源码字符串，不修改 package.loaded；每个 env 独立执行同一份真实字节。
local function source(name)
    local relative = assert(SOURCE_FILES[name], "source denied: " .. tostring(name))
    if sources[name] then return sources[name] end
    local path = ROOT .. "/scripts/" .. relative
    assert(ROOT:sub(1, 1) == "/" and not path:find("..", 1, true), "unsafe source root")
    local file = nil ---@type any
    local route = "File"
    if nativeFile then
        local ok, opened = pcall(function() return nativeFile(path, FILE_READ) end)
        if ok and opened then
            if opened:IsOpen() then file = opened else opened:Dispose() end
        end
    end
    if not file and nativeCache then
        route = "cache:GetFile"
        local ok, opened = pcall(function() return nativeCache:GetFile(relative) end)
        if ok and opened then
            if opened:IsOpen() then file = opened else opened:Dispose() end
        end
    end
    assert(file, "cannot read actual source: " .. path)
    local ok, text = pcall(function()
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        return table.concat(lines, "\n")
    end)
    file:Dispose()
    assert(ok, text)
    assert(type(text) == "string" and #text > 100, "empty actual source: " .. path)
    sources[name] = text
    sourceReads[#sourceReads + 1] = { path = path, route = route, bytes = #text }
    return text
end

local function heroes(count)
    local list = {}
    for i = 1, count do list[i] = { id = i, type = "hero", heroId = 100 + i, quality = i % 5 } end
    return list
end
local function mixed()
    return {
        { id = 1, type = "resource", resType = "gold", amount = 101, quality = 0 },
        { id = 2, type = "shard", heroId = 21, amount = 102, quality = 1 },
        { id = 3, type = "hero", heroId = 11, quality = 1 },
        { id = 4, type = "resource", resType = "ticket", amount = 104, quality = 4 },
        { id = 5, type = "dupe_to_shard", heroId = 12, shardGain = 105, quality = 0 },
        { id = 6, type = "shard", heroId = 22, amount = 106, quality = 3 },
        { id = 7, type = "decompose", heroId = 13, tavernCoin = 107, quality = 2 },
        { id = 8, type = "hero", heroId = 14, quality = 4 },
        { id = 9, type = "resource", resType = "exp", amount = 109, quality = 2 },
        { id = 10, type = "shard", heroId = 23, amount = 110, quality = 1 },
    }
end

---@param options any
---@return any
local function newContext(options)
    options = options or {}
    local ctx = {
        deps = {}, executions = {}, required = {}, forbidden = {}, fixtures = {},
        calls = {}, loads = {}, deleted = {}, handles = {}, warming = {}, stack = {},
        clock = { elapsedTime = options.startTime or 0 }, vg = {},
        transform = { sx = 1, sy = 1, tx = 0, ty = 0, alpha = 1 },
        memory = { ticket = 20, stellarTicket = 15, gems = 10000, heroes = { [11] = { level = 4 } } },
        readCounts = { ticket = 0, stellarTicket = 0, gems = 0 },
        presentationInit = 0, presentationDestroy = 0, rngCalls = 0, transactionCalls = 0,
        nextHandle = 0,
    } ---@type any
    ctx.initialMemory = copy(ctx.memory)
    contexts[#contexts + 1] = ctx
    local env = {} ---@type any
    ctx.env = env
    -- 不继承真实 _G。遗漏的函数或 require 必须报错，绝不能退回玩家数据/业务系统。
    for _, key in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "select",
        "tonumber", "tostring", "type", "setmetatable", "getmetatable", "rawget", "rawset" }) do
        env[key] = _G[key]
    end
    env.math, env.string, env.table = copy(math), copy(string), copy(table)
    env._G, env.time, env.print = env, ctx.clock, noop
    env.NVG_ALIGN_CENTER, env.NVG_ALIGN_MIDDLE = NVG_ALIGN_CENTER, NVG_ALIGN_MIDDLE
    local function denied(label)
        return function()
            ctx.forbidden[#ctx.forbidden + 1] = label
            error("isolated animation forbids " .. label)
        end
    end
    local function denyObject(label)
        return setmetatable({}, { __index = function(_, key) return denied(label .. "." .. tostring(key)) end })
    end
    env.math.random = function()
        ctx.rngCalls = ctx.rngCalls + 1
        error("animation must not consume RNG")
    end
    env.math.randomseed = env.math.random
    env.File, env.loadfile, env.dofile = denied("File"), denied("loadfile"), denied("dofile")
    for _, key in ipairs({ "cache", "fileSystem", "clientCloud", "serverCloud", "network",
        "io", "os", "package", "debug", "engine" }) do env[key] = denyObject(key) end
    env.SubscribeToEvent, env.SendEvent = denied("SubscribeToEvent"), denied("SendEvent")
    setmetatable(env, { __index = function(_, key)
        ctx.forbidden[#ctx.forbidden + 1] = "global " .. tostring(key)
        error("missing explicit global stub: " .. tostring(key))
    end })

    local function record(kind, fields)
        local entry = fields or {}
        entry.kind = kind
        ctx.calls[#ctx.calls + 1] = entry
        return entry
    end
    local function geometry(kind, cx, cy, w, h, alpha, extra)
        local transform = ctx.transform
        local entry = extra or {}
        entry.cx, entry.cy, entry.w, entry.h = cx, cy, w, h
        entry.screenX = cx * transform.sx + transform.tx
        entry.screenY = cy * transform.sy + transform.ty
        entry.sx, entry.sy = transform.sx, transform.sy
        entry.alpha = (alpha or 1) * transform.alpha
        return record(kind, entry)
    end
    env.nvgSave = function()
        ctx.stack[#ctx.stack + 1] = copy(ctx.transform)
    end
    env.nvgRestore = function()
        ctx.transform = assert(table.remove(ctx.stack), "NanoVG restore underflow")
    end
    env.nvgTranslate = function(_, x, y)
        assert(finite(x) and finite(y), "non-finite translate")
        local previous = ctx.transform
        previous.tx, previous.ty = previous.tx + x * previous.sx, previous.ty + y * previous.sy
    end
    env.nvgScale = function(_, x, y)
        assert(finite(x) and finite(y) and x > 0 and y > 0, "card scale must be finite and positive")
        record("scale", { x = x, y = y })
        ctx.transform.sx, ctx.transform.sy = ctx.transform.sx * x, ctx.transform.sy * y
    end
    env.nvgGlobalAlpha = function(_, alpha)
        assert(finite(alpha) and alpha >= 0 and alpha <= 1, "invalid global alpha")
        ctx.transform.alpha = alpha
    end
    env.nvgRGBA = function(r, g, b, a) return { r, g, b, a } end
    env.nvgBeginPath = function() ctx.shape, ctx.paint = {}, nil end
    env.nvgRect = function(_, x, y, w, h)
        assert(finite({ x, y, w, h }) and w > 0 and h > 0, "invalid rectangle")
        ctx.shape = { cx = x + w / 2, cy = y + h / 2, w = w, h = h }
    end
    env.nvgRoundedRect = function(vg, x, y, w, h, radius)
        assert(finite(radius) and radius >= 0, "invalid radius")
        env.nvgRect(vg, x, y, w, h)
    end
    env.nvgImagePattern = function(_, x, y, w, h, angle, handle, alpha)
        assert(finite({ x, y, w, h, angle, handle, alpha }), "non-finite image sample")
        return { path = ctx.handles[handle], handle = handle, alpha = alpha }
    end
    env.nvgFillPaint = function(_, paint) ctx.paint = paint end
    env.nvgFillColor = function(_, color) ctx.paint = nil; record("color", { color = color }) end
    env.nvgFill = function()
        local shape = ctx.shape
        if ctx.paint then
            geometry("image", shape.cx, shape.cy, shape.w, shape.h, ctx.paint.alpha,
                { path = ctx.paint.path, handle = ctx.paint.handle })
        else record("fill", copy(shape)) end
    end
    env.nvgFontFace = function(_, font) record("font", { name = font }) end
    env.nvgFontSize = function(_, size) assert(finite(size) and size > 0, "invalid font size") end
    env.nvgTextAlign = noop
    env.nvgCreateImage = function(_, path)
        assert(type(path) == "string" and path:sub(1, 6) == "image/", "unexpected image resource")
        ctx.loads[#ctx.loads + 1] = path
        local handle = ctx.nextHandle
        ctx.nextHandle = handle + 1
        ctx.handles[handle] = path
        return handle
    end
    env.nvgDeleteImage = function(_, handle) ctx.deleted[#ctx.deleted + 1] = handle end
    local function stub(name, values)
        ctx.deps[name] = setmetatable(values, { __index = function(_, field)
            ctx.forbidden[#ctx.forbidden + 1] = name .. "." .. tostring(field)
            ctx.transactionCalls = ctx.transactionCalls + 1
            error("unmocked dependency/transaction: " .. name .. "." .. tostring(field))
        end })
        return ctx.deps[name]
    end
    stub("config.GameConfig", { Design = { WIDTH = 1080, HEIGHT = 2400 } })
    stub("config.ClassConfig", { KNIGHT = "knight", WARRIOR = "warrior", MAGE = "mage",
        RANGER = "ranger", ASSASSIN = "assassin", PRIEST = "priest" })
    stub("config.HeroConfig", { get = function(id) return { name = "测试英雄" .. id, classId = "knight" } end })
    stub("core.BattleLayout", { cardHeightForWidth = function(width) return width * 5 / 3 end })
    stub("config.ResourceDefs", { DEFS = {
        gold = { iconPath = "image/test/gold.png", quality = 1, name = "测试金币" },
        ticket = { iconPath = "image/test/ticket.png", quality = 3, name = "测试券" },
        exp = { iconPath = "image/test/exp.png", quality = 2, name = "测试经验" },
    } })
    stub("config.GachaConfig", { Cost = { SINGLE_TICKET = 1, TEN_TICKET = 10, SINGLE_DIAMOND = 180, TEN_DIAMOND = 1800 } })
    stub("config.UrGachaConfig", { Cost = { SINGLE_TICKET = 1, TEN_TICKET = 10, SINGLE_DIAMOND = 300, TEN_DIAMOND = 3000 } })
    stub("core.GameState", {
        getRecruitTicket = function() ctx.readCounts.ticket = ctx.readCounts.ticket + 1; return ctx.memory.ticket end,
        getStellarRecruitTicket = function() ctx.readCounts.stellarTicket = ctx.readCounts.stellarTicket + 1; return ctx.memory.stellarTicket end,
        getGems = function() ctx.readCounts.gems = ctx.readCounts.gems + 1; return ctx.memory.gems end,
    })
    stub("config.HeroAssetUtil", { ensureCard = function(vg, images, heroId)
        ctx.warming[#ctx.warming + 1] = heroId
        if images[heroId] == nil then images[heroId] = env.nvgCreateImage(vg, "image/test/hero_" .. heroId .. ".png", 0) end
        return images[heroId]
    end })
    stub("core.DrawUtil", {
        drawTextStroke = function(_, x, y, text, size)
            record("text", { x = x, y = y, text = text, size = size })
        end,
        drawImageCentered = function(_, image, cx, cy, w, h, alpha)
            geometry("image", cx, cy, w, h, alpha, { path = ctx.handles[image] })
        end,
        drawCardImage = function(_, image, cx, cy, w, h, alpha)
            geometry("hero", cx, cy, w, h, alpha, { path = ctx.handles[image] })
        end,
        drawShardIcon = function(_, heroId, cx, cy, width, alpha)
            geometry("shard", cx, cy, width, width, alpha, { heroId = heroId })
        end,
    })
    stub("core.DarkIcon", { drawQualityBg = function(_, quality, cx, cy, w, h, alpha)
        geometry("qualityBg", cx, cy, w, h, alpha, { quality = quality })
    end })
    stub("ui.widget.RepeatDrawButton", { draw = function(_, cx, cy, w, h, text, parts, enough)
        geometry("button", cx, cy, w, h, 1, { text = text, parts = copy(parts), enough = enough })
    end })
    -- 字幕/UI/资源/样式均不会接触真实引擎；本专项不宣称 Presentation 的美术或 GPU 已通过。
    stub("urhox-libs/UI", {})
    stub("ui.widget.DesignWidgetSurface", { init = noop, draw = noop })
    stub("ui.tavern.RecruitPresentation", {
        init = function() ctx.presentationInit = ctx.presentationInit + 1 end,
        destroy = function() ctx.presentationDestroy = ctx.presentationDestroy + 1 end,
        drawIntro = function(_, elapsed, quality)
            record("intro", { elapsed = elapsed, quality = quality, pose = ctx.timeline.intro(elapsed) })
        end,
        drawBack = function(_, cx, cy, w, h, alpha) geometry("back", cx, cy, w, h, alpha) end,
        drawCardGlow = function(_, cx, cy, w, h, quality, glow)
            geometry("glow", cx, cy, w, h, glow, { quality = quality, glow = glow })
        end,
        drawLabels = function(_, phase, ready, pool, alpha)
            record("labels", { phase = phase, ready = ready, pool = pool, alpha = alpha })
        end,
    })
    env.require = function(name)
        ctx.required[#ctx.required + 1] = name
        if ctx.deps[name] then return ctx.deps[name] end
        if not SOURCE_FILES[name] then return denied("require " .. tostring(name))() end
        local chunk, why = load(source(name), "@" .. ROOT .. "/scripts/" .. SOURCE_FILES[name], "t", env)
        assert(chunk, why)
        local module = chunk()
        assert(type(module) == "table", "real module did not return a table: " .. name)
        ctx.executions[name] = (ctx.executions[name] or 0) + 1
        ctx.deps[name] = module
        return module
    end
    ctx.timeline = env.require("ui.tavern.RecruitTimeline")
    ctx.anim = env.require("ui.tavern.RecruitAnim")
    if options.init ~= false then ctx.anim.init(ctx.vg) end
    function ctx.start(list, callback, count, pool)
        ctx.fixtures[#ctx.fixtures + 1] = { original = list, snapshot = copy(list) }
        ctx.anim.start(list, callback, count, pool or "standard")
    end
    function ctx.draw(at, update)
        if at ~= nil then ctx.clock.elapsedTime = at end
        if update ~= false then ctx.anim.update(0) end
        ctx.calls = {}
        local before = copy(ctx.transform)
        eq(#ctx.stack, 0, "frame starts with empty save stack")
        ctx.anim.draw(ctx.vg)
        eq(#ctx.stack, 0, "real RecruitAnim balances nvgSave/nvgRestore")
        check(same(ctx.transform, before), "draw restores transform and alpha")
        check(finite(ctx.calls), "all recorded coordinates/scales/alpha/time are finite")
        return ctx.calls
    end
    return ctx
end

---@param ctx any
local function calls(ctx, kind)
    local selected = {}
    for _, call in ipairs(ctx.calls) do if call.kind == kind then selected[#selected + 1] = call end end
    return selected
end
---@param ctx any
local function labels(ctx)
    local list = calls(ctx, "labels")
    eq(#list, 1, "one Presentation label sampling per active draw")
    return list[1]
end
---@param ctx any
local function fronts(ctx)
    local selected = {}
    for _, call in ipairs(ctx.calls) do
        if call.kind == "hero" or call.kind == "shard"
            or (call.kind == "image" and call.path and call.path:find("image/test/", 1, true)) then
            selected[#selected + 1] = call
        end
    end
    return selected
end
---@param ctx any
local function safe(ctx)
    eq(#ctx.forbidden, 0, "no player IO, cloud, events or unknown dependency")
    eq(ctx.rngCalls, 0, "actual modules never call RNG/randomseed")
    eq(ctx.transactionCalls, 0, "no reward/cost/claim/gacha/save calls")
    check(same(ctx.memory, ctx.initialMemory), "currency and roster memory unchanged")
    for _, fixture in ipairs(ctx.fixtures) do
        check(same(fixture.original, fixture.snapshot), "receipt fields and original order unchanged")
    end
end

local function isolationCases()
    local first, second = newContext(), newContext()
    check(first.anim ~= second.anim and first.timeline ~= second.timeline, "real modules isolated per env")
    eq(first.env._G, first.env, "sandbox _G has no runtime fallback")
    first.start(heroes(1), nil, 1)
    check(first.anim.isPlaying(), "first instance active")
    eq(second.anim.isPlaying(), false, "second instance remains idle")
    eq(first.env.require("ui.tavern.RecruitAnim"), first.anim, "per-env real module cached")
    for name in pairs(SOURCE_FILES) do eq(first.executions[name], 1, "real source executed once " .. name) end
    first.anim.close()
    first.draw(); second.draw()
    eq(#first.calls, 0, "closed draw is inert")
    eq(#second.calls, 0, "unstarted draw is inert")
    eq(second.anim.handleInput(BUTTON_X, BUTTON_Y), false, "idle input not consumed")
    eq(second.anim.dismiss(), false, "idle dismiss not consumed")
    safe(first); safe(second)
end

local function timelineCases()
    local ctx = newContext({ init = false })
    local timeline = ctx.timeline
    near(timeline.INTRO_DURATION, INTRO, "intro duration")
    near(timeline.CARD_DURATION, CARD, "card duration")
    near(timeline.CARD_DELAY, DELAY, "stagger delay")
    near(timeline.FADE_DURATION, FADE, "fade duration")
    for _, count in ipairs({ 0, 1, 2, 5, 10 }) do near(timeline.cardSpan(count), span(count), "span " .. count) end
    local initial = timeline.intro(0)
    near(initial.charge, 0, "time zero uncharged")
    near(initial.opening, 0, "time zero gate closed")
    near(initial.alpha, 1, "time zero intro visible")
    near(initial.sealScale, 0.84, "time zero seal scale")
    check(same(timeline.intro(-1), initial), "negative intro time clamps to zero")
    local finished = timeline.intro(INTRO)
    near(finished.opening, 1, "gate fully opened")
    near(finished.alpha, 0, "intro fades at duration boundary")
    near(finished.sealAlpha, 0, "seal disappears")
    for _, at in ipairs({ -1, 0, EPS, 0.4, 0.72, 0.8, 1.35, 1.44, INTRO, 100 }) do
        local pose = timeline.intro(at)
        check(finite(pose) and pose.alpha >= 0 and pose.alpha <= 1 and pose.opening >= 0
            and pose.opening <= 1 and pose.sealScale > 0, "finite bounded intro sample " .. at)
    end
    for i = 1, 10 do
        local delay = (i - 1) * DELAY
        eq(timeline.card(delay, i).visible, false, "card not visible at exact zero local time " .. i)
        eq(timeline.card(delay + EPS, i).visible, true, "card visible immediately after delay " .. i)
        eq(timeline.card(delay + CARD - EPS, i).settled, false, "card not settled early " .. i)
        eq(timeline.card(delay + CARD + EPS, i).settled, true, "card settled after full duration " .. i)
        local middle = delay + CARD * (0.28 + 0.60 * 0.5)
        eq(timeline.card(middle - EPS, i).front, false, "back before half flip " .. i)
        eq(timeline.card(middle + EPS, i).front, true, "front after half flip " .. i)
        near(timeline.card(middle, i).scaleX, 0.045, "nonzero minimum flip scale " .. i)
        for step = 0, 100 do
            local pose = timeline.card(delay + CARD * step / 100, i)
            check(finite(pose) and pose.scaleX >= 0.045 and pose.scale > 0 and pose.alpha >= 0
                and pose.alpha <= 1 and pose.glow >= -EPS and pose.glow <= 1 + EPS,
                "finite positive card sample " .. i .. "/" .. step)
        end
    end
    eq(timeline.card(0, 1).settled, false, "time zero card not settled")
    eq(timeline.card(CARD, 1).settled, true, "first card settled at exact boundary")
    for quality = 0, 4 do check(finite(timeline.color(quality)), "actual quality color " .. quality) end
    check(same(timeline.color(999), timeline.color(0)), "unknown quality has neutral fallback")
    safe(ctx)
end

local function naturalTimingCases(count)
    local ctx = newContext()
    local closed, again = 0, 0
    ctx.anim.setOnAgain(function(value) again = again + 1; eq(value, count, "repeat count") end)
    ctx.start(heroes(count), function() closed = closed + 1 end, count)
    ctx.draw(0)
    eq(labels(ctx).phase, "intro", "starts intro at clock zero")
    near(calls(ctx, "intro")[1].elapsed, 0, "actual start timestamp zero")
    eq(#calls(ctx, "button"), 0, "no repeat button during intro")
    ctx.draw(INTRO - EPS)
    eq(labels(ctx).phase, "intro", "intro lasts until planned boundary")
    ctx.draw(INTRO)
    eq(labels(ctx).phase, "cards", "intro completes exactly on schedule")
    eq(#calls(ctx, "back"), 0, "first card local time zero is not yet visible")
    for i = 1, count do
        ctx.draw(INTRO + (i - 1) * DELAY + EPS)
        eq(#calls(ctx, "scale"), i, "one newly visible staggered card " .. i)
        eq(#calls(ctx, "button"), 0, "all-card span still incomplete " .. i)
    end
    ctx.draw(INTRO + span(count) - EPS)
    eq(labels(ctx).ready, false, "not ready before final span")
    eq(#calls(ctx, "button"), 0, "not shown before final span")
    ctx.draw(INTRO + span(count) + EPS)
    eq(labels(ctx).ready, true, "ready after final span")
    eq(#fronts(ctx), count, "all actual front-card branches drawn")
    eq(#calls(ctx, "back"), 0, "no card backs after reveal")
    eq(#calls(ctx, "button"), 1, "repeat button visible after reveal")
    eq(closed, 0, "natural completion does not close")
    eq(again, 0, "natural completion does not reroll")
    local now = ctx.clock.elapsedTime
    ctx.anim.update(99999); ctx.draw(now, false)
    eq(labels(ctx).phase, "cards", "dt alone does not advance host-owned time")
    local paused = newContext()
    paused.start(heroes(count), nil, count)
    paused.draw(100)
    eq(labels(paused).ready, true, "late update uses planned start, no extra animation delay")
    eq(#fronts(paused), count, "paused catch-up reveals complete receipt")
    safe(ctx); safe(paused)
end

-- 精确边界必须严格通过；浮点差值若导致尚未 ready，保留失败，不写 expected-failure 掩盖。
local function exactReadyCases(count)
    local ctx = newContext()
    local again = 0
    ctx.anim.setOnAgain(function() again = again + 1 end)
    ctx.start(heroes(count), nil, count)
    ctx.draw(INTRO + span(count))
    eq(labels(ctx).ready, true, "exact natural finish is ready count=" .. count)
    eq(#calls(ctx, "button"), 1, "exact finish repeat button visible")
    ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
    eq(again, 1, "exact finish repeat button clickable, not a second skip")
    safe(ctx)
end

local function stableOrderCases()
    local ctx = newContext()
    local receipt = mixed()
    ctx.start(receipt, nil, 10, "stellar")
    eq(#ctx.warming, 4, "only hero/dupe/decompose cards warmed at start")
    for i, id in ipairs({ 11, 12, 13, 14 }) do eq(ctx.warming[i], id, "warming stable hero group " .. i) end
    ctx.draw(0)
    eq(calls(ctx, "intro")[1].quality, 4, "intro uses real highest receipt quality")
    eq(labels(ctx).pool, "stellar", "pool passed unchanged to Presentation")
    ctx.draw(8)
    local visible = fronts(ctx)
    local expected = { "hero_11", "hero_12", "hero_13", "hero_14", "shard21", "shard22", "shard23", "gold", "ticket", "exp" }
    eq(#visible, 10, "mixed receipt draws exactly ten fronts")
    for i, key in ipairs(expected) do
        local entry = visible[i]
        local identity = entry.heroId and ("shard" .. entry.heroId)
            or entry.path:match("image/test/(.-)%.png$")
        eq(identity, key, "stable hero/fragment/resource grouping " .. i)
    end
    local text = {}
    for _, entry in ipairs(calls(ctx, "text")) do text[entry.text] = true end
    for _, expectedText in ipairs({ "→碎片×105", "→酒馆币×107", "X102", "X106", "X110", "X101", "X104", "X109" }) do
        check(text[expectedText], "actual branch retains real amount " .. expectedText)
    end
    eq(receipt[1].id, 1, "sort never reorders original receipt")
    eq(receipt[4].quality, 4, "resource quality is not rewritten into a fake hero")
    safe(ctx)
end

local function skipCases(count, at, phase)
    local ctx = newContext({ startTime = at })
    local closed, again = 0, 0
    ctx.anim.setOnAgain(function() again = again + 1 end)
    ctx.start(heroes(count), function() closed = closed + 1 end, count)
    if phase == "cards" then ctx.draw(at + INTRO + 0.1) else ctx.draw(at) end
    eq(labels(ctx).phase, phase, "pre-skip phase")
    eq(ctx.anim.handleInput(BUTTON_X, BUTTON_Y), true, "first input consumed only as skip")
    ctx.draw(nil, false)
    eq(labels(ctx).phase, "cards", "one skip moves to cards")
    eq(labels(ctx).ready, true, "one skip reveals all immediately count=" .. count .. " time=" .. ctx.clock.elapsedTime)
    eq(#fronts(ctx), count, "one skip draws every front")
    eq(again, 0, "first click at repeat coordinate never rerolls")
    eq(closed, 0, "skip never consumes close callbacks")
    eq(ctx.anim.dismiss(), false, "same-frame dismiss cannot close skipped results")
    ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
    eq(again, 0, "same-frame second input cannot reroll just-revealed cards")
    ctx.anim.handleInput(10, 10)
    eq(closed, 0, "same-frame second blank input cannot close just-revealed cards")
    ctx.draw(nil, false)
    eq(labels(ctx).phase, "cards", "same-frame routing leaves results open")
    local now = ctx.clock.elapsedTime
    ctx.clock.elapsedTime = now + 0.1
    eq(ctx.anim.dismiss(), true, "fresh-frame dismiss begins fade, not another reveal")
    ctx.draw(nil, false)
    eq(labels(ctx).phase, "fadeOut", "dismiss starts fadeOut")
    eq(closed, 0, "close callback waits for fade")
    ctx.draw(now + 0.1 + FADE - EPS)
    eq(closed, 0, "callback not early")
    ctx.draw(now + 0.1 + FADE + EPS)
    eq(closed, 1, "callback fires once after fade")
    eq(ctx.anim.isPlaying(), false, "fade returns to idle")
    ctx.anim.close(); ctx.anim.update(100)
    eq(closed, 1, "no duplicate callback after repeated close/update")
    safe(ctx)
end

local function directDismissSkipCases()
    for _, count in ipairs({ 1, 10 }) do
        for _, at in ipairs({ 0, 8 }) do
            local ctx = newContext({ startTime = at })
            local closed, again = 0, 0
            ctx.anim.setOnAgain(function() again = again + 1 end)
            ctx.start(heroes(count), function() closed = closed + 1 end, count)
            eq(ctx.anim.dismiss(), true, "first seam dismiss only reveals")
            ctx.draw(nil, false)
            eq(labels(ctx).phase, "cards", "direct dismiss reveals cards, not fade")
            eq(labels(ctx).ready, true, "direct dismiss reveals all at zero/nonzero clock")
            eq(#fronts(ctx), count, "direct dismiss draws complete receipt")
            eq(closed + again, 0, "direct dismiss cannot close or reroll")
            eq(ctx.anim.dismiss(), false, "same-frame repeated seam dismiss inert")
            ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
            eq(again, 0, "same-frame input after direct dismiss cannot reroll")
            ctx.anim.close(); eq(closed, 1, "later explicit close notifies once")
            safe(ctx)
        end
    end
end

local function repeatHotspotCases()
    -- 设计坐标热区：x300..780、y2126..2214，含边；边外 0.001 不再招募。
    for _, count in ipairs({ 1, 10 }) do
        for _, pool in ipairs({ "standard", "stellar" }) do
            for _, point in ipairs({ { 300, 2126 }, { 540, 2126 }, { 780, 2126 },
                { 300, 2170 }, { 540, 2170 }, { 780, 2170 },
                { 300, 2214 }, { 540, 2214 }, { 780, 2214 },
                { 299.999, 2170 }, { 780.001, 2170 }, { 540, 2125.999 }, { 540, 2214.001 } }) do
                local ctx = newContext()
                local again, closed = 0, 0
                ctx.anim.setOnAgain(function(value) again = again + 1; eq(value, count, "repeat forwards correct pull count") end)
                ctx.start(heroes(count), function() closed = closed + 1 end, count, pool)
                ctx.draw(8)
                local button = calls(ctx, "button")[1]
                eq(button.text, count == 10 and "继续十连" or "继续单抽", "repeat text matches count")
                eq(button.cx, BUTTON_X, "button center X matches hit area")
                eq(button.cy, BUTTON_Y, "button center Y matches hit area")
                eq(button.w, 480, "button width matches hit area")
                eq(button.h, 88, "button height matches hit area")
                check(button.enough and #button.parts == 1, "read-only cost display uses owned tickets")
                eq(button.parts[1].type, pool == "stellar" and "stellar_ticket" or "adventure_ticket", "pool cost icon type")
                eq(button.parts[1].amount, count, "cost display count")
                local inside = math.abs(point[1] - BUTTON_X) <= 240 and math.abs(point[2] - BUTTON_Y) <= 44
                ctx.anim.handleInput(point[1], point[2])
                eq(again, inside and 1 or 0, "inclusive hotspot, no off-button reroll")
                eq(closed, 0, "repeat/off-button input does not immediately close")
                if inside then
                    eq(ctx.anim.dismiss(), false, "same-frame repeat dismiss blocked")
                    ctx.draw(nil, false)
                    eq(labels(ctx).phase, "cards", "repeat routing does not fade results")
                else
                    ctx.draw(nil, false)
                    eq(labels(ctx).phase, "fadeOut", "outside hotspot starts dismiss")
                end
                safe(ctx)
            end
        end
    end
end

local function beforeReadyInputCases(count)
    local ctx = newContext()
    local again, closed = 0, 0
    ctx.anim.setOnAgain(function() again = again + 1 end)
    ctx.start(heroes(count), function() closed = closed + 1 end, count)
    ctx.draw(INTRO + span(count) - EPS)
    eq(#calls(ctx, "button"), 0, "repeat button hidden before cardsReady")
    ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
    eq(again, 0, "hidden repeat hotspot only skips")
    eq(closed, 0, "hidden repeat hotspot never closes")
    eq(ctx.anim.dismiss(), false, "same-frame hidden hotspot dismiss guarded")
    safe(ctx)
end

local function unavailableButtonCases(mode)
    local ctx = newContext()
    local again = 0
    if mode == "fadeOut" then ctx.anim.setOnAgain(function() again = again + 1 end) end
    ctx.start(heroes(1), nil, 1)
    ctx.draw(8)
    if mode == "fadeOut" then
        ctx.anim.handleInput(10, 10)
        ctx.draw(8.1, false)
        eq(labels(ctx).phase, "fadeOut", "button consistency checked during fade")
    end
    -- cards 阶段的可见性与可点性必须一致；fadeOut 允许保留淡出绘制，但不能再触发动作。
    if mode == "fadeOut" then
        eq(#calls(ctx, "button"), 1, "fade transition retains already-visible button")
        check(calls(ctx, "button")[1].alpha > 0 and calls(ctx, "button")[1].alpha < 1,
            "transition button fades with its parent")
    else
        eq(#calls(ctx, "button"), 0, "no callback means no usable repeat button")
    end
    ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
    eq(again, 0, "unavailable repeat button cannot invoke again")
    safe(ctx)
end

local function repeatedStartCases()
    local ctx = newContext()
    local invoked = { 0, 0, 0 }
    for i = 1, 3 do
        local index = i
        ctx.start(heroes(i), function() invoked[index] = invoked[index] + 1 end, i == 1 and 1 or 10)
    end
    check(same(invoked, { 0, 0, 0 }), "replacement does not prematurely deliver close callbacks")
    ctx.draw(8)
    eq(#fronts(ctx), 3, "only latest results rendered")
    ctx.anim.handleInput(10, 10)
    ctx.draw(8 + FADE + EPS)
    check(same(invoked, { 1, 1, 1 }), "each replaced start callback consumed once on close")
    ctx.anim.close(); ctx.anim.close()
    check(same(invoked, { 1, 1, 1 }), "repeated close cannot consume old callbacks twice")
    local sameFunctionCalls = 0
    local callback = function() sameFunctionCalls = sameFunctionCalls + 1 end
    for _ = 1, 3 do ctx.start(heroes(1), callback, 1) end
    ctx.anim.close()
    eq(sameFunctionCalls, 3, "same callback identity invoked once per start, not deduplicated")
    safe(ctx)
end

local function callbackReentryCases()
    local ctx = newContext()
    local order = {}
    local invoked = { 0, 0, 0 }
    ctx.start(heroes(1), function()
        invoked[1] = invoked[1] + 1; order[#order + 1] = "old"
        ctx.anim.close()
    end, 1)
    ctx.start(heroes(10), function()
        invoked[2] = invoked[2] + 1; order[#order + 1] = "current"
        ctx.start(heroes(1), function() invoked[3] = invoked[3] + 1 end, 1)
    end, 10)
    ctx.anim.close()
    check(same(invoked, { 1, 1, 0 }), "close reentry drains old batch only once")
    check(same(order, { "old", "current" }), "old/current callback order stable")
    check(ctx.anim.isPlaying(), "callback-started animation survives outer close")
    ctx.draw(nil, false)
    eq(labels(ctx).phase, "intro", "reentrant start phase retained")
    ctx.anim.close(); ctx.anim.close()
    check(same(invoked, { 1, 1, 1 }), "reentrant new callback runs only on its own close")
    local fade = newContext()
    local fromFade = 0
    fade.start(heroes(1), function()
        fromFade = fromFade + 1
        fade.start(heroes(10), nil, 10)
    end, 1)
    fade.draw(8); fade.anim.handleInput(10, 10); fade.draw(8 + FADE + EPS)
    eq(fromFade, 1, "fade close callback once")
    eq(labels(fade).phase, "intro", "callback reentry survives update's fade completion")
    safe(ctx); safe(fade)
end

local function againReentryCases()
    local ctx = newContext()
    local oldClosed, newClosed, again = 0, 0, 0
    ctx.start(heroes(10), function() oldClosed = oldClosed + 1 end, 10)
    ctx.anim.setOnAgain(function(value)
        again = again + 1
        eq(value, 10, "repeat callback receives old count before reentry")
        ctx.start(heroes(1), function() newClosed = newClosed + 1 end, 1, "stellar")
    end)
    ctx.draw(8); ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
    eq(again, 1, "one repeat input invokes callback exactly once")
    ctx.draw(nil, false)
    eq(labels(ctx).phase, "intro", "repeat callback can start next receipt")
    eq(labels(ctx).pool, "stellar", "reentry keeps next pool")
    eq(oldClosed + newClosed, 0, "repeat callback does not close/settle old or new receipt")
    eq(ctx.anim.dismiss(), false, "same-frame seam dismiss cannot reveal or close newly started receipt")
    ctx.draw(nil, false)
    eq(labels(ctx).phase, "intro", "repeat route preserves new intro, not just prevents fadeOut")
    ctx.anim.close(); ctx.anim.close()
    eq(oldClosed, 1, "old callback preserved through repeat reentry")
    eq(newClosed, 1, "new callback consumed once")
    safe(ctx)
end

local function repeatFrozenPoolAndFreshIntroCases()
    for _, count in ipairs({ 1, 10 }) do
        for _, pool in ipairs({ "standard", "stellar" }) do
            local ctx = newContext()
            local selectedPool = pool
            local receiptPool = pool
            local nextPool = pool == "standard" and "stellar" or "standard"
            local nextCount = count == 1 and 10 or 1
            local again, oldClosed, nextClosed = 0, 0, 0
            ctx.start(heroes(count), function() oldClosed = oldClosed + 1 end, count, receiptPool)
            -- 宿主随后切换选择，不得篡改当前回执冻结的再次招募池。
            selectedPool = nextPool
            ctx.anim.setOnAgain(function(receiptCount, frozenPool)
                again = again + 1
                eq(receiptCount, count, "repeat callback receives frozen receipt count")
                eq(frozenPool, receiptPool, "repeat callback receives frozen receipt poolId")
                check(frozenPool ~= selectedPool, "repeat pool does not follow mutable host selection")
                ctx.start(heroes(nextCount), function() nextClosed = nextClosed + 1 end, nextCount, nextPool)
                eq(frozenPool, receiptPool, "synchronous start cannot change captured callback poolId")
                eq(receiptCount, count, "synchronous start cannot change captured callback count")
            end)
            ctx.draw(8)
            ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
            eq(again, 1, "one repeat call before synchronous new start")
            ctx.draw(nil, false)
            eq(labels(ctx).phase, "intro", "repeat callback opens fresh intro")
            eq(labels(ctx).pool, nextPool, "fresh intro uses new receipt pool only")
            eq(ctx.anim.dismiss(), false, "same-frame dismiss cannot consume fresh intro")
            ctx.draw(nil, false)
            eq(labels(ctx).phase, "intro", "same-frame repeat barrier preserves fresh intro")
            ctx.clock.elapsedTime = 8.1
            eq(ctx.anim.dismiss(), true, "next-frame intro dismiss can reveal after repeat barrier expires")
            ctx.draw(nil, false)
            eq(labels(ctx).phase, "cards", "next-frame dismiss reveals, never closes intro")
            eq(labels(ctx).ready, true, "fresh receipt fully revealed on next-frame dismiss")
            eq(#fronts(ctx), nextCount, "next-frame reveal draws all new receipt fronts")
            eq(ctx.anim.dismiss(), false, "new reveal barrier still blocks same-frame repeated dismiss")
            eq(oldClosed + nextClosed, 0, "repeat and reveal do not consume either close callback")
            ctx.clock.elapsedTime = 8.2
            eq(ctx.anim.dismiss(), true, "next-frame settled dismiss starts close after reveal barrier expires")
            ctx.draw(nil, false)
            eq(labels(ctx).phase, "fadeOut", "fresh settled receipt can fade after repeat and reveal")
            eq(oldClosed + nextClosed, 0, "fade start waits for close callbacks")
            ctx.draw(8.2 + FADE + EPS)
            eq(ctx.anim.isPlaying(), false, "next-frame settled dismiss eventually closes")
            eq(oldClosed, 1, "replaced receipt callback delivered once after fade")
            eq(nextClosed, 1, "fresh receipt callback delivered once after fade")
            eq(again, 1, "dismiss sequence cannot reroll again")
            ctx.anim.close()
            eq(oldClosed + nextClosed, 2, "post-fade close cannot repeat callbacks")
            safe(ctx)
        end
    end
end

local function repeatFreshSettledDismissCases()
    for _, count in ipairs({ 1, 10 }) do
        local ctx = newContext()
        local again, closed = 0, 0
        local pool = count == 1 and "stellar" or "standard"
        ctx.anim.setOnAgain(function(receiptCount, receiptPool)
            again = again + 1
            eq(receiptCount, count, "settled repeat count preserved")
            eq(receiptPool, pool, "settled repeat poolId preserved")
            -- 无同步回执时保留当前已揭晓结果，不能留下永久返回屏障。
        end)
        ctx.start(heroes(count), function() closed = closed + 1 end, count, pool)
        ctx.draw(8)
        ctx.anim.handleInput(BUTTON_X, BUTTON_Y)
        eq(again, 1, "settled repeat callback once without reentry")
        eq(ctx.anim.dismiss(), false, "same-frame settled dismiss blocked after repeat")
        ctx.draw(nil, false)
        eq(labels(ctx).phase, "cards", "same-frame settled result stays open")
        ctx.clock.elapsedTime = 8.1
        eq(ctx.anim.dismiss(), true, "next-frame settled dismiss not blocked by old repeat")
        ctx.draw(nil, false)
        eq(labels(ctx).phase, "fadeOut", "next-frame settled dismiss begins closing")
        eq(closed, 0, "next-frame close respects fade duration")
        ctx.draw(8.1 + FADE + EPS)
        eq(closed, 1, "settled close callback once after next-frame dismiss")
        eq(ctx.anim.isPlaying(), false, "settled result idle after fade")
        eq(again, 1, "next-frame dismiss never repeats recruit")
        ctx.anim.close(); eq(closed, 1, "settled callback not repeated by close")
        safe(ctx)
    end
end

local function closeDestroyCases()
    local ctx = newContext()
    local closed, suppressed = 0, 0
    ctx.start(heroes(1), function() closed = closed + 1 end, 1)
    ctx.anim.close()
    eq(closed, 1, "close notifies host immediately")
    eq(ctx.presentationDestroy, 0, "ordinary close retains Presentation resources")
    eq(#ctx.deleted, 0, "ordinary close never deletes shared card images")
    local loaded = #ctx.loads
    ctx.start(heroes(1), function() closed = closed + 1 end, 1)
    eq(#ctx.loads, loaded, "ordinary close retains hero card cache")
    ctx.start(heroes(10), function() suppressed = suppressed + 1 end, 10)
    ctx.anim.destroy()
    eq(ctx.anim.isPlaying(), false, "destroy cancels immediately")
    eq(closed, 1, "destroy suppresses queued replaced callback")
    eq(suppressed, 0, "destroy suppresses active callback")
    eq(ctx.presentationDestroy, 1, "destroy forwards Presentation teardown")
    ctx.draw(); eq(#ctx.calls, 0, "destroyed draw inert")
    ctx.anim.close(); ctx.anim.update(1000)
    eq(closed + suppressed, 1, "close/update after destroy cannot revive discarded callbacks")
    local warming = #ctx.warming
    ctx.start(heroes(1), nil, 1)
    eq(#ctx.warming, warming, "destroy clears cached VG, no resource preheat with dead context")
    ctx.anim.close()
    ctx.anim.init(ctx.vg)
    eq(ctx.presentationInit, 2, "explicit init can restore Presentation after destroy")
    ctx.start(heroes(1), function() closed = closed + 1 end, 1); ctx.anim.close()
    eq(closed, 2, "fresh post-destroy callback works without old callbacks")
    safe(ctx)
end

local function renderCases()
    for _, count in ipairs({ 1, 10 }) do
        local ctx = newContext()
        ctx.anim.setOnAgain(noop)
        ctx.start(count == 1 and heroes(1) or mixed(), nil, count)
        for _, at in ipairs({ 0, EPS, 0.72, 1.35, INTRO, INTRO + EPS, INTRO + 0.05,
            INTRO + CARD * 0.58, INTRO + CARD * 0.58 + DELAY, INTRO + span(count) + EPS, 8 }) do
            ctx.draw(at)
            if at == INTRO + 0.05 then
                eq(#calls(ctx, "back"), 1, "early flip actually draws a card back")
                eq(#fronts(ctx), 0, "early flip does not expose front card yet")
            end
            for _, scale in ipairs(calls(ctx, "scale")) do
                check(scale.x > 0 and scale.y > 0, "card-front/back transform strictly positive")
            end
        end
        local visible = fronts(ctx)
        eq(#visible, count, "every final card visible")
        for i, entry in ipairs(visible) do
            local expectedX = count == 1 and 540 or 124 + ((i - 1) % 5) * 208
            local expectedY = count == 1 and 1050 or (i <= 5 and 714 or 1383)
            if entry.kind == "shard" or entry.kind == "image" then expectedY = expectedY - 89 end
            near(entry.screenX, expectedX, "final card horizontal center " .. i)
            near(entry.screenY, expectedY, "final card vertical center " .. i)
            near(entry.sx, 1, "settled front scale X")
            near(entry.sy, 1, "settled front scale Y")
        end
        ctx.anim.handleInput(10, 10)
        ctx.draw(8 + FADE / 2, false)
        check(ctx.anim.isPlaying(), "fade draw itself never closes")
        ctx.draw(8 + FADE + EPS, false)
        eq(#ctx.calls, 0, "fully transparent fade draw performs no graphics work")
        check(ctx.anim.isPlaying(), "only update, not draw, completes fade")
        ctx.anim.update(0)
        eq(ctx.anim.isPlaying(), false, "update completes expired fade")
        safe(ctx)
    end
end

local function finalSafetyCases()
    for _, ctx in ipairs(contexts) do safe(ctx) end
    eq(File, nativeFile, "runtime File unchanged")
    eq(cache, nativeCache, "runtime cache unchanged")
    eq(time, nativeTime, "runtime clock unchanged")
    for name, value in pairs(nativeGlobals) do eq(rawget(_G, name), value, "runtime global unchanged " .. name) end
    for name in pairs(SOURCE_FILES) do eq(package.loaded[name], initialLoaded[name], "runtime package.loaded unchanged " .. name) end
    eq(#sourceReads, 2, "exactly two actual source files cached once")
    for _, read in ipairs(sourceReads) do
        local allowed = false
        for _, relative in pairs(SOURCE_FILES) do if read.path == ROOT .. "/scripts/" .. relative then allowed = true end end
        check(allowed and read.bytes > 100, "native source read is exact whitelist, not player file")
        print(TAG .. "SOURCE " .. read.route .. " " .. read.path .. " bytes=" .. read.bytes)
    end
end

function Start()
    local tests = {
        { "real-source-per-env-isolation", isolationCases },
        { "real-timeline-zero-stagger-finite-and-positive-scale", timelineCases },
        { "single-natural-sequence", function() naturalTimingCases(1) end },
        { "ten-natural-sequence", function() naturalTimingCases(10) end },
        { "single-exact-ready-boundary", function() exactReadyCases(1) end },
        { "ten-exact-ready-boundary", function() exactReadyCases(10) end },
        { "stable-real-receipt-groups-and-amounts", stableOrderCases },
        { "single-intro-skip-at-zero", function() skipCases(1, 0, "intro") end },
        { "ten-intro-skip-at-zero", function() skipCases(10, 0, "intro") end },
        { "single-intro-skip-nonzero", function() skipCases(1, 8, "intro") end },
        { "ten-intro-skip-nonzero", function() skipCases(10, 8, "intro") end },
        { "single-card-skip", function() skipCases(1, 8, "cards") end },
        { "ten-card-skip", function() skipCases(10, 8, "cards") end },
        { "direct-seam-dismiss-reveals-once-at-zero-and-nonzero", directDismissSkipCases },
        { "single-hidden-button-input-only-reveals", function() beforeReadyInputCases(1) end },
        { "ten-hidden-button-input-only-reveals", function() beforeReadyInputCases(10) end },
        { "inclusive-repeat-hotspot-and-same-frame-dismiss", repeatHotspotCases },
        { "button-hidden-without-repeat-callback", function() unavailableButtonCases("noCallback") end },
        { "button-hidden-during-nonclickable-fade", function() unavailableButtonCases("fadeOut") end },
        { "repeated-start-callback-each-once", repeatedStartCases },
        { "close-and-fade-callback-reentry", callbackReentryCases },
        { "repeat-callback-start-reentry", againReentryCases },
        { "repeat-frozen-pool-and-next-frame-intro-dismiss", repeatFrozenPoolAndFreshIntroCases },
        { "repeat-next-frame-settled-dismiss-closes", repeatFreshSettledDismissCases },
        { "close-notifies-destroy-cancels", closeDestroyCases },
        { "recorded-front-back-finite-stack-and-no-draw-time-advance", renderCases },
        { "final-no-RNG-transactions-player-IO-or-global-mutation", finalSafetyCases },
    }
    for _, test in ipairs(tests) do
        local passed, why = pcall(test[2])
        groups = groups + 1
        if passed then print(TAG .. "[PASS] " .. test[1])
        else
            local message = test[1] .. " " .. tostring(why)
            failures[#failures + 1] = message
            print(TAG .. "[FAIL] " .. message)
        end
    end
    RecruitAnimationTestResult = { groups = groups, checks = checks, failures = copy(failures),
        sourceReads = copy(sourceReads), gpuAcceptance = false, root = ROOT }
    local outcome = #failures == 0 and "ALL PASS" or "FAIL"
    print(TAG .. "RESULT " .. outcome .. " groups=" .. groups .. " checks=" .. checks .. " failures=" .. #failures
        .. " (Presentation/UI/resources/styles mocked; not GPU acceptance)")
    -- 严格失败保留给主代理汇报；异常使 headless 验证明确失败，不写生产或日志文件。
    if #failures > 0 then error(TAG .. "production boundary assertions failed=" .. #failures, 0) end
    return RecruitAnimationTestResult
end
