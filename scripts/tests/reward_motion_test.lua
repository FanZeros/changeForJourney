-- 独立奖励纯视觉专项：真实源码在白名单读取一次，然后在零IO/RNG闭包内执行。
-- 不加载main/玩家档；可选 -motion-oracle=/绝对路径/reward-baseline/source 对照冻结旧时间轴。
local ROOT = "/workspace/changeForJourney-effective-power"
local oracle = ""
for _, argument in ipairs(GetArguments()) do
    ROOT = argument:match("^%-tapcode_dir=(.+)$") or ROOT
    oracle = argument:match("^%-motion%-oracle=(.+)$") or oracle
end
local CHECKS = 0
local function check(value, message)
    CHECKS = CHECKS + 1
    assert(value, message)
end
local function near(a, b, message)
    check(type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-9, message)
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
local function readSource(path)
    check(path:sub(1, 1) == "/" and not path:find("..", 1, true), "exact absolute source path")
    local file = File(path, FILE_READ)
    check(file and file:IsOpen(), "whitelisted actual source opened " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function context(text)
    local ctx = { clock = { elapsedTime = 100 }, operations = {}, stack = {}, forbidden = 0 }
    local env = {} ---@type any
    for _, key in ipairs({ "assert", "error", "ipairs", "pairs", "type", "tostring", "setmetatable" }) do
        env[key] = _G[key]
    end
    env.math, env.table, env.string = copy(math), copy(table), copy(string)
    env.time = ctx.clock
    local function denied()
        ctx.forbidden = ctx.forbidden + 1
        error("pure visual code used IO/RNG/unknown global")
    end
    env.math.random, env.math.randomseed = denied, denied
    setmetatable(env, { __index = denied })
    ctx.render = { alpha = 0.63, transform = { 1, 0, 0, 1, 11, 19 },
        fill = { 20, 30, 40, 80 }, stroke = { 70, 60, 50, 120 }, width = 4,
        scissor = { 7, 9, 700, 500 } }
    local function record(name, ...)
        local arguments = { ... }
        check(finite(arguments), "finite NVG " .. name)
        ctx.operations[#ctx.operations + 1] = { name, arguments }
    end
    env.nvgSave = function() ctx.stack[#ctx.stack + 1] = copy(ctx.render); record("save") end
    env.nvgRestore = function()
        ctx.render = assert(table.remove(ctx.stack), "balanced save")
        record("restore")
    end
    env.nvgRGBA = function(r, g, b, a)
        check(finite({ r, g, b, a }) and a >= 0 and a <= 255, "bounded color alpha")
        return { r, g, b, a }
    end
    env.nvgGlobalAlpha = function(_, alpha)
        check(alpha >= 0 and alpha <= 1, "bounded global alpha")
        ctx.render.alpha = alpha; record("alpha", alpha)
    end
    env.nvgFillColor = function(_, color) ctx.render.fill = color; record("fillColor", color) end
    env.nvgStrokeColor = function(_, color) ctx.render.stroke = color; record("strokeColor", color) end
    env.nvgStrokeWidth = function(_, width)
        check(width > 0, "positive thin stroke")
        ctx.render.width = width; record("strokeWidth", width)
    end
    env.nvgTranslate = function(_, x, y)
        local a = ctx.render.transform
        a[5], a[6] = a[5] + a[1] * x + a[3] * y, a[6] + a[2] * x + a[4] * y
        record("translate", x, y)
    end
    env.nvgScale = function(_, x, y)
        check(x > 0 and y > 0, "positive scale")
        local a = ctx.render.transform
        a[1], a[2], a[3], a[4] = a[1] * x, a[2] * x, a[3] * y, a[4] * y
        record("scale", x, y)
    end
    env.nvgRotate = function(_, angle)
        local a = ctx.render.transform
        local c, s = math.cos(angle), math.sin(angle)
        local x1, y1, x2, y2 = a[1], a[2], a[3], a[4]
        a[1], a[2], a[3], a[4] = x1*c+x2*s, y1*c+y2*s, x2*c-x1*s, y2*c-y1*s
        record("rotate", angle)
    end
    env.nvgIntersectScissor = function(_, x, y, w, h)
        check(w > 0 and h > 0, "positive clip")
        ctx.render.scissor = { x, y, w, h }; record("clip", x, y, w, h)
    end
    for _, name in ipairs({ "nvgBeginPath", "nvgCircle", "nvgMoveTo", "nvgLineTo", "nvgRect",
        "nvgRoundedRect", "nvgFill", "nvgStroke", "nvgFillPaint" }) do
        env[name] = function(_, ...) record(name, ...) end
    end
    env.nvgRadialGradient = function(_, ...)
        local args = { ... }; record("radial", ...); return args
    end
    local chunk, why = load(text, "@actual-motion-source", "t", env)
    assert(chunk, why)
    ctx.module = chunk()
    function ctx.sample(method, ...)
        ctx.operations = {}
        local before = copy(ctx.render)
        local moduleBefore = copy(ctx.module)
        ctx.module[method]({}, ...)
        check(same(moduleBefore, ctx.module), "draw does not mutate module")
        check(#ctx.stack == 0, "draw balances save stack")
        check(same(before, ctx.render), "draw restores host fill/stroke/alpha/clip/transform")
        return copy(ctx.operations)
    end
    return ctx
end

function Start()
    local paths = {
        cascade = ROOT .. "/scripts/ui/widget/RewardCascade.lua",
        timeline = ROOT .. "/scripts/ui/tavern/RecruitTimeline.lua",
        motion = ROOT .. "/scripts/ui/tavern/RecruitMotion.lua",
    }
    local cascade = context(readSource(paths.cascade))
    local timeline = context(readSource(paths.timeline))
    local motion = context(readSource(paths.motion))
    local C, T = cascade.module, timeline.module
    near(C.LEAD, 0.10, "lead unchanged")
    near(C.INTERVAL, 0.12, "interval unchanged")
    near(C.INTERVAL_TAIL, 0.10, "tail unchanged")
    near(C.POP_DUR, 0.22, "pop unchanged")
    near(T.INTRO_DURATION, 1.8, "intro unchanged")
    near(T.CARD_DURATION, 0.66, "card unchanged")
    near(T.CARD_DELAY, 0.12, "delay unchanged")
    near(T.FADE_DURATION, 0.35, "fade unchanged")
    local options = { {}, { interval = .14, intervalTail = .06, fastAfter = 10,
        intervalFaster = .02, fasterAfter = 20 }, { interval = 0, intervalTail = 0, fastAfter = 3 } }
    local oldC, oldT
    if oracle ~= "" then
        check(oracle:sub(1, 1) == "/" and not oracle:find("..", 1, true), "absolute frozen oracle directory")
        oldC = context(readSource(oracle .. "/RewardCascade.lua"))
        oldT = context(readSource(oracle .. "/RecruitTimeline.lua"))
    end
    for _, count in ipairs({ 0, 1, 10, 21, 200, 10000 }) do
        for _, opts in ipairs(options) do
            local a = C.new(count, opts)
            local b = oldC and oldC.module.new(count, opts) or C.new(count, opts)
            a:start(100); b:start(100)
            check(same(a, b), "real timeline fields unchanged")
            for i = 1, math.max(1, math.min(count, 200)) do
                near(a:startAt(i), b:startAt(i), "old startAt preserved")
                near(a:gap(i), b:gap(i), "old gap preserved")
            end
            for _, elapsed in ipairs({ -.1, 0, .1, .22, 1, 2, 4, 30 }) do
                cascade.clock.elapsedTime = a.revealStart + elapsed
                if oldC then oldC.clock.elapsedTime = cascade.clock.elapsedTime end
                near(a:shownCount(elapsed), b:shownCount(elapsed), "shownCount preserved")
                check(a:t(1) == b:t(1) and a:finished() == b:finished(), "t/finished preserved")
            end
            a:skipToEnd(); b:skipToEnd()
            near(a.revealStart, b.revealStart, "skip start preserved")
            check(a:finished() == b:finished(), "skip finished preserved")
        end
    end
    for index = 1, 10 do
        for frame = -10, 120 do
            local elapsed = frame / 60
            local pose = T.card(elapsed, index)
            local before = oldT and oldT.module.card(elapsed, index) or pose
            for _, field in ipairs({ "visible", "front", "alpha", "scaleX", "glow", "settled" }) do
                check(pose[field] == before[field], "real old recruit contract " .. field)
            end
            check(finite(pose) and pose.scale >= .94 and pose.scale <= 1, "recruit pose finite/readable")
            check(pose.offsetY >= -3 and pose.offsetY <= 96, "landing travel bounded")
            if pose.settled then near(pose.offsetY, 0, "settled location exact") end
        end
    end
    for _, size in ipairs({ 32, 100, 160, 240 }) do
        for frame = 0, 120 do
            local t = frame / 120
            for _, method in ipairs({ "burst", "glint" }) do
                local first = cascade.sample(method, 540, 420, t, size, 240, 199, 112)
                cascade.sample(method, 10, 20, .3, size, 180, 140, 90)
                check(same(first, cascade.sample(method, 540, 420, t, size, 240, 199, 112)), "A-B-A deterministic " .. method)
                if t == 0 or t == 1 then check(#first == 0, "effect endpoint no residue") end
            end
            local before = copy(cascade.render)
            cascade.operations = {}
            cascade.module.applyPop({}, 540, 420, t, .8)
            check(cascade.render.alpha >= 0 and cascade.render.alpha <= .8, "pop alpha readable/bounded")
            for _, operation in ipairs(cascade.operations) do
                if operation[1] == "scale" then check(operation[2][1] >= .76 and operation[2][1] <= 1.025, "quantity never tiny") end
                if operation[1] == "rotate" then check(math.abs(operation[2][1]) <= .035, "wobble restrained") end
            end
            if t == 1 then check(same(cascade.render.transform, before.transform), "pop final transform exact") end
            cascade.render = before
        end
    end
    for _, lead in ipairs({ -100, -.08, -.04, 0, .2 }) do
        local operations = cascade.sample("anticipate", 100, 200, lead, 100)
        if lead <= -.08 or lead >= 0 then check(#operations == 0, "anticipation endpoint quiet") end
    end
    local nan = 0/0
    for _, invalid in ipairs({ nan, math.huge, -math.huge, "bad", false }) do
        check(#cascade.sample("burst", 100, 200, invalid, 100, 255, 255, 255) == 0, "invalid burst no calls")
        check(#cascade.sample("glint", 100, 200, invalid, 100) == 0, "invalid glint no calls")
        check(#cascade.sample("anticipate", 100, 200, invalid, 100) == 0, "invalid anticipate no calls")
        check(#cascade.sample("applyPop", 100, 200, invalid, .8) == 0, "invalid pop no calls")
        check(#motion.sample("drawBackEdge", 100, 200, 198, 330, invalid, 1) == 0, "invalid edge no calls")
    end
    for frame = 0, 120 do
        local t = frame / 120
        local first = motion.sample("drawBackEdge", 100, 200, 198, 330, t, 1)
        check(same(first, motion.sample("drawBackEdge", 100, 200, 198, 330, t, 1)), "edge deterministic")
        if t == 0 or t >= .58 then check(#first == 0, "edge absent on front/endpoint") end
    end
    check(cascade.forbidden == 0 and timeline.forbidden == 0 and motion.forbidden == 0, "zero IO/RNG/unknown global calls")
    print("[reward_motion_test] ALL PASS checks=" .. CHECKS .. " IO/RNG=0 oldOracle=" .. tostring(oldC ~= nil))
    engine:Exit()
end
