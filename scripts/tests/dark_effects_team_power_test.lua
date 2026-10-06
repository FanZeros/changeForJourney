-- 程序化暗黑特效专项（独立 Runtime；不加载 main/Boot，不读取玩家档）。
-- 基于 scaffold-2d 的 Start/Stop 与 NanoVGRender 范式；测试帧采用模式 B：逻辑尺寸 + DPR。
-- 真实源码通过只读 ResourceCache 编译到隔离 env：EventBus 不是替身；UI/Surface/Yoga/Label 不是替身。
-- 图元记录器只用于几何、颜色和故障注入，不代表原生 GPU/手机触控或视觉性能验收。
-- 本轮新生命周期不能冒称保留旧 Spine create/load/GPU 的 57 场景/1220 断言。
-- 运行：UrhoXRuntime tests/dark_effects_team_power_test.lua -tapcode_dir=. -tool_mode -graphicsheadless

local TAG = "[dark_effects_team_power_test]"
local totals = { assertions = 0, failures = 0, cases = 0 }
local sources = {} ---@type table<string, string>
local cleanups = {} ---@type function[]
local fixtureKeepAlive = {} ---@type table[]
local testMode = { uiOnly = false, logicOnly = false }
---@type NVGContextWrapper?
local renderContext = nil
local ended = false
local visual = { enabled = false, sample = .65, language = "zh_CN", teams = 3, context = {}, images = {},
    caption = nil, power = nil, card = nil, success = nil, failure = nil } ---@type table<string, any>

local function check(ok, label)
    totals.assertions = totals.assertions + 1
    if ok then print("[PASS] " .. label)
    else totals.failures = totals.failures + 1; print("[FAIL] " .. label) end
end

local function eq(actual, expected, label)
    local a, e = tostring(actual), tostring(expected)
    if #a > 120 then a = a:sub(1,120) .. "... length=" .. #a end
    if #e > 120 then e = e:sub(1,120) .. "... length=" .. #e end
    check(actual == expected, label .. " actual=" .. a .. " expected=" .. e)
end

local function near(actual, expected, label, epsilon)
    check(type(actual) == "number" and math.abs(actual - expected) <= (epsilon or 0.00001),
        label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

local function case(label, fn)
    totals.cases = totals.cases + 1
    local ok, err = pcall(fn)
    if not ok then check(false, label .. " exception=" .. tostring(err)) end
    print(TAG .. " CASE " .. label .. " failures=" .. totals.failures)
end

local function readSource(path)
    local file = assert(cache:GetFile(path), "missing real source: " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function compile(path, env)
    return assert(load(assert(sources[path], path .. " not frozen by test"), "@" .. path, "t", env))()
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- 所有注入均在私有 env；不覆写 _G.nvg*/_G.time/math.random/package.loaded。
local function environment(clock, logs)
    local env = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, next = next,
        type = type, tostring = tostring, tonumber = tonumber, select = select,
        pcall = pcall, xpcall = xpcall, setmetatable = setmetatable, getmetatable = getmetatable,
        rawget = rawget, rawset = rawset, math = math, string = string, table = table,
        time = clock, print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
            logs[#logs + 1] = table.concat(parts, " ")
        end,
    } ---@type table<string, any>
    env._G = env
    for key, value in pairs(_G) do
        if type(key) == "string" and key:match("^NVG_") then env[key] = value end
    end
    return env
end

-- 记录真实图元执行路径，颜色独立于几何签名；save/restore模拟宿主状态。
local function recorder(env)
    local r = { calls = {}, colors = {}, depth = 0, saves = 0, restores = 0,
        stack = {}, marker = "host-transform-scissor-alpha", invalid = 0, forbidden = 0,
        throwAt = "", phase = "idle" } ---@type table<string, any>
    local names = { "nvgBeginPath", "nvgClosePath", "nvgMoveTo", "nvgLineTo", "nvgBezierTo",
        "nvgQuadTo", "nvgArc", "nvgArcTo", "nvgCircle", "nvgEllipse", "nvgRect", "nvgRoundedRect",
        "nvgRoundedRectVarying", "nvgFill", "nvgStroke", "nvgStrokeWidth", "nvgLineCap", "nvgLineJoin",
        "nvgMiterLimit", "nvgPathWinding", "nvgTranslate", "nvgScale", "nvgRotate", "nvgTransform",
        "nvgResetTransform", "nvgGlobalAlpha", "nvgGlobalCompositeOperation", "nvgScissor",
        "nvgIntersectScissor", "nvgResetScissor", "nvgFillColor", "nvgStrokeColor", "nvgFillPaint",
        "nvgStrokePaint", "nvgLinearGradient", "nvgRadialGradient", "nvgBoxGradient" }
    local function called(name, ...)
        local args = { ... }
        r.calls[#r.calls + 1] = { name = name, args = args }
        for _, value in ipairs(args) do
            if type(value) == "number" and not finite(value) then r.invalid = r.invalid + 1 end
        end
        if r.throwAt == name then error("INJECTED_DARK_FAULT " .. name, 0) end
        return args
    end
    for _, name in ipairs(names) do
        env[name] = function(_, ...)
            local args = called(name, ...)
            if name == "nvgTranslate" or name == "nvgScale" or name == "nvgGlobalAlpha"
                or name:find("Scissor", 1, true) then r.marker = "mutated-by-primitives" end
            if name:find("Gradient", 1, true) then return { gradient = name, args = args } end
        end
    end
    env.nvgSave = function(_)
        called("nvgSave")
        r.stack[#r.stack + 1] = r.marker
        r.depth, r.saves = r.depth + 1, r.saves + 1
    end
    env.nvgRestore = function(_)
        r.marker = r.stack[#r.stack]
        r.stack[#r.stack] = nil
        r.depth, r.restores = r.depth - 1, r.restores + 1
        called("nvgRestore")
    end
    local function color(red, green, blue, alpha, unit)
        local c = { red, green, blue, alpha }
        r.colors[#r.colors + 1] = { rgba = c, unit = unit }
        for _, value in ipairs(c) do
            if not finite(value) or value < 0 or value > unit then r.invalid = r.invalid + 1 end
        end
        return c
    end
    env.nvgRGBA = function(red, green, blue, alpha) return color(red, green, blue, alpha, 255) end
    env.nvgRGB = function(red, green, blue) return color(red, green, blue, 255, 255) end
    env.nvgRGBAf = function(red, green, blue, alpha) return color(red, green, blue, alpha, 1) end
    env.nvgRGBf = function(red, green, blue) return color(red, green, blue, 1, 1) end
    for _, name in ipairs({ "nvgSpineCreate", "nvgSpineRender", "nvgCreateImage", "nvgCreateImageRGBA",
        "nvgImagePattern", "nvgImagePatternTinted", "nvgText", "nvgTextBox" }) do
        env[name] = function(...)
            r.forbidden = r.forbidden + 1
            error("FORBIDDEN_NON_PROCEDURAL_CALL " .. name, 0)
        end
    end
    return r
end

local function geometrySignature(record)
    local parts = {}
    for _, call in ipairs(record.calls) do
        local name = call.name
        if not name:find("Color", 1, true) and not name:find("Paint", 1, true)
            and not name:find("Gradient", 1, true) and name ~= "nvgGlobalAlpha" then
            local args = {}
            for _, value in ipairs(call.args) do
                if type(value) == "number" then args[#args + 1] = string.format("%.7f", value) end
            end
            parts[#parts + 1] = name .. "(" .. table.concat(args, ",") .. ")"
        end
    end
    return table.concat(parts, "|")
end

local function primitiveFixture()
    local logs, clock = {}, { elapsedTime = 100.0 }
    local env = environment(clock, logs)
    local record = recorder(env)
    env.require = function(name)
        assert(name == "core.DarkIcon", "unexpected primitive dependency: " .. name)
        return require(name)
    end
    local effect = compile("ui/fx/DarkEffectPrimitives.lua", env)
    local fixture = { effect = effect, record = record, env = env, logs = logs, clock = clock }
    fixtureKeepAlive[#fixtureKeepAlive + 1] = fixture
    return fixture
end

local function controllerFixture(path, effects)
    local logs, clock = {}, { elapsedTime = 100.0 }
    local env = environment(clock, logs)
    local record = recorder(env)
    env.require = function(name)
        if name == "ui.fx.DarkEffectPrimitives" then return effects end
        if name == "core.BattleLayout" then return require(name) end
        error("unexpected controller dependency: " .. name, 0)
    end
    local effect = compile(path, env)
    cleanups[#cleanups + 1] = effect.destroy
    local fixture = { effect = effect, record = record, env = env, logs = logs, clock = clock, vg = {} }
    fixtureKeepAlive[#fixtureKeepAlive + 1] = fixture
    return fixture
end

-- 真 EventBus 源码每个case独立实例，spy只转发真实on/off回调。
local function powerFixture(realDrawing)
    local logs, clock = {}, { elapsedTime = 100.0 }
    local env = environment(clock, logs)
    local events = require("config.GameEvents")
    local bus = compile("core/EventBus.lua", environment(clock, logs))
    local subscriptions, invocations = {}, 0
    local on, off = bus.on, bus.off
    bus.on = function(event, callback)
        local wrapped = function(data) invocations = invocations + 1; callback(data) end
        subscriptions[callback] = wrapped
        on(event, wrapped)
    end
    bus.off = function(event, callback)
        local wrapped = subscriptions[callback]
        if wrapped then off(event, wrapped); subscriptions[callback] = nil end
    end
    local surface = require("ui.widget.DesignWidgetSurface")
    local draws = {} ---@type table[]
    local bridge = {
        init = surface.init,
        draw = function(root, vg, width, height)
            -- 必须先真实布局+真实绘制，再采集Label/坐标；不能用stub把布局错误隐藏。
            surface.draw(root, vg, width, height)
            draws[#draws + 1] = { root = root, width = width, height = height }
        end,
    }
    local language = { value = "zh_CN" }
    local effects
    local record = recorder(env)
    if realDrawing then
        -- drawSurface must observe the SAME synchronous global entrypoints as the real UI library.
        env._G = _G
        effects = require("ui.fx.DarkEffectPrimitives")
        for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgTranslate", "nvgScale" }) do env[name] = _G[name] end
    else
        effects = { drawPower = function() error("non-render test unexpectedly drew", 0) end }
    end
    env.require = function(name)
        if name == "core.EventBus" then return bus end
        if name == "config.GameEvents" then return events end
        if name == "urhox-libs/UI" then return require("urhox-libs/UI") end
        if name == "ui.widget.DesignWidgetSurface" then return bridge end
        if name == "core.I18n" then return { get = function() return language.value end } end
        if name == "ui.fx.DarkEffectPrimitives" then return effects end
        error("unexpected Power dependency: " .. name, 0)
    end
    local power = compile("ui/fx/SpinePowerUpEffect.lua", env)
    cleanups[#cleanups + 1] = power.destroy
    local f = { power = power, bus = bus, clock = clock, draws = draws, language = language,
        record = record, events = events, logs = logs, env = env }
    function f:emit(powers, activeTeam)
        self.bus.emit(self.events.TEAM_POWER_CHANGED, { powers = powers, activeTeam = activeTeam })
    end
    function f:baseline(powers)
        self.power.init()
        self:emit(powers or {100, 200, 300})
        self.clock.elapsedTime = self.clock.elapsedTime + 2
        self.power.update(0)
    end
    function f:row(team)
        for _, row in ipairs(self.power.getDisplayRows()) do if row.teamIdx == team then return row end end
        return nil
    end
    function f:calls() return invocations end
    fixtureKeepAlive[#fixtureKeepAlive + 1] = f
    return f
end

local function runPowerEvents()
    case("power-cold-boot-ready-false-never-seeds-zero-baseline", function()
        local f = powerFixture(false)
        for iteration = 1, 2 do
            if iteration == 1 then f.power.init() else f.power.resetSession() end
            f.bus.emit(f.events.TEAM_POWER_CHANGED,{powers={0,0,0},ready=false})
            f.clock.elapsedTime = f.clock.elapsedTime + 10
            f.power.update(0)
            f.bus.emit(f.events.TEAM_POWER_CHANGED,{powers={0,0,0},ready=false})
            f.bus.emit(f.events.TEAM_POWER_CHANGED,{powers={100000,200000,300000},ready=true})
            eq(#f.power.getDisplayRows(),0,"first hydrated save only seeds baseline after long title wait " .. iteration)
            f.bus.emit(f.events.TEAM_POWER_CHANGED,{powers={100000,200123,300456},ready=true})
            eq(#f.power.getDisplayRows(),2,"real teams2/3 gain after hydration " .. iteration)
            eq(assert(f:row(2)).delta,123,"hydrated team2 true delta " .. iteration)
            eq(assert(f:row(3)).delta,456,"hydrated team3 true delta " .. iteration)
        end
    end)
    case("real-bus-initial-wallclock-stabilization", function()
        local f = powerFixture(false)
        check(type(f.events.TEAM_POWER_CHANGED) == "string" and f.events.TEAM_POWER_CHANGED ~= "",
            "uses actual nonempty GameEvents.TEAM_POWER_CHANGED constant")
        f.power.init()
        f:emit({100, 200, 0})
        f.clock.elapsedTime = 101.99
        f:emit({180, 290, 0})
        f.power.update(900)
        eq(#f.power.getDisplayRows(), 0, "large dt cannot end initial two-second quiet period")
        f.clock.elapsedTime = 102
        f.power.update(0)
        f:emit({181, 300, 0})
        eq(#f.power.getDisplayRows(), 2, "wallclock threshold works without any draw")
        eq(assert(f:row(1)).delta, 1, "quiet-period latest value is team1 baseline")
        eq(assert(f:row(2)).delta, 10, "quiet-period latest value is team2 baseline")
        eq(f:row(3), nil, "empty unchanged team produces no row")
        local before = f:calls()
        f.bus.emit("PowerChanged", {powers = {900, 900, 900}})
        eq(f:calls(), before, "legacy total-power event cannot trigger effect")
    end)
    case("three-teams-net-gain-independent-drop-rebound", function()
        local f = powerFixture(false); f:baseline()
        f:emit({150, 230, 320})
        local rows = f.power.getDisplayRows()
        eq(#rows, 3, "three simultaneous team rows")
        for team, delta in ipairs({50, 30, 20}) do
            eq(rows[team].teamIdx, team, "rows retain team order " .. team)
            eq(rows[team].delta, delta, "independent delta " .. team)
        end
        f.clock.elapsedTime = 102.5
        f:emit({130, 190, 320})
        eq(assert(f:row(1)).delta, 30, "drop reduces net gain, does not sum old gain")
        eq(f:row(2), nil, "drop below team2 baseline cancels only team2")
        eq(assert(f:row(3)).delta, 20, "unrelated team3 unchanged")
        f.clock.elapsedTime = 103
        f:emit({160, 210, 320})
        eq(assert(f:row(1)).delta, 60, "same-team restart merges from original baseline")
        eq(assert(f:row(2)).delta, 20, "canceled team rebound starts from lower actual value")
        near(assert(f:row(1)).elapsed, 0, "team1 gain restarts timer")
        near(assert(f:row(3)).elapsed, 1, "team3 timer not restarted by other teams")
        f.clock.elapsedTime = 105.21
        f.power.update(0)
        eq(f:row(3), nil, "old team expires independently without draw")
        check(f:row(1) ~= nil and f:row(2) ~= nil, "newer teams survive old-team expiration")
        f.clock.elapsedTime = 106.21
        f.power.update(-1)
        eq(#f.power.getDisplayRows(), 0, "negative dt cannot freeze wallclock expiry")
    end)
    case("invalid-event-values-active-team-and-copy-isolation", function()
        local f = powerFixture(false); f:baseline({0, 200, 300})
        f:emit({0, 230, 320}, 3)
        for _, value in ipairs({0 / 0, math.huge, -math.huge, -1, "900", false}) do
            f:emit({value, value, value}, 1)
            eq(assert(f:row(2)).delta, 30, "invalid payload leaves team2 baseline: " .. tostring(value))
            eq(assert(f:row(3)).delta, 20, "invalid payload leaves team3 baseline: " .. tostring(value))
        end
        f.bus.emit(f.events.TEAM_POWER_CHANGED, nil)
        f.bus.emit(f.events.TEAM_POWER_CHANGED, false)
        f.bus.emit(f.events.TEAM_POWER_CHANGED, {})
        f.bus.emit(f.events.TEAM_POWER_CHANGED, {powers = "not-array"})
        f:emit({0, 230, 320}, 1)
        eq(#f.power.getDisplayRows(), 2, "switch metadata cannot fabricate gains or lose teams")
        local copy = f.power.getDisplayRows()
        copy[1].delta, copy[1].power, copy[1].teamIdx = 999, 999, 3
        eq(assert(f:row(2)).delta, 30, "display rows are defensive copies")
        f:emit({0, 231, 321}, 2)
        eq(assert(f:row(2)).delta, 31, "invalid input never poisoned subsequent legal baseline")
        eq(assert(f:row(3)).delta, 21, "all legal teams still update independently")
        f:emit({0, 0, 0})
        eq(#f.power.getDisplayRows(), 0, "clearing all teams cancels all visible gains")
    end)
    case("reset-init-destroy-real-subscription-lifecycle", function()
        local f = powerFixture(false); f:baseline()
        f:emit({110, 220, 330})
        f.power.resetSession()
        eq(#f.power.getDisplayRows(), 0, "reset clears visible rows")
        f:emit({1000, 2000, 3000})
        f.clock.elapsedTime = 104
        f.power.update(0); f:emit({1001, 2001, 3001})
        eq(assert(f:row(1)).delta, 1, "reset creates new quiet baseline")
        f.power.init(); f.power.init(); f.power.init()
        local count = f:calls()
        f:emit({1, 2, 3})
        eq(f:calls() - count, 1, "repeated init has exactly one real bus subscription")
        f.power.destroy(); f.power.destroy()
        count = f:calls(); f:emit({999, 999, 999})
        eq(f:calls(), count, "destroy actually unsubscribes, not just ignores handler")
        eq(#f.power.getDisplayRows(), 0, "destroy clears row state")
        f:baseline({20, 40, 60}); f:emit({21, 42, 63})
        eq(#f.power.getDisplayRows(), 3, "init after destroy subscribes and starts fresh")
    end)
end

local function summarize()
    if ended then return end
    ended = true
    for i = #cleanups, 1, -1 do pcall(cleanups[i]) end
    pcall(function() require("ui.widget.DesignWidgetSurface").shutdown() end)
    print(string.format("%s %s mode=%s cases=%d assertions=%d failures=%d", TAG,
        totals.failures == 0 and "ALL PASS" or "FAIL", testMode.logicOnly and "logic" or (testMode.uiOnly and "UI" or "full"),
        totals.cases, totals.assertions, totals.failures))
    engine:Exit()
end

local function paint(f, kind, p, alpha, overrides)
    local o = overrides or {}
    local vg = o.noContext and nil or {}
    local cx, cy = o.cx or 500, o.cy or 600
    local w, h = o.width or 198, o.height or (198 * 955 / 538)
    local duration = o.duration or 2
    local elapsed = o.elapsed or p * duration
    if kind == "power" then f.effect.drawPower(vg, cx, cy, w, h, elapsed, duration, alpha)
    elseif kind == "success" or kind == "failure" then
        f.effect.drawResult(vg, kind == "success", cx, cy, w, elapsed, duration, alpha)
    else f.effect.drawCard(vg, kind, cx, cy, w, h, elapsed, duration, alpha) end
end

local function runPrimitives()
    local kinds = {"power", "level", "job", "revive", "success", "failure"}
    case("real-primitives-geometric-identities-and-phases", function()
        local signatures = {}
        for _, kind in ipairs(kinds) do
            local f = primitiveFixture(); paint(f, kind, .5, 1)
            check(#f.record.calls > 0, kind .. " really executes primitive paths")
            eq(f.record.invalid, 0, kind .. " finite coordinates/colors")
            eq(f.record.forbidden, 0, kind .. " never calls images/Spine/text")
            eq(f.record.depth, 0, kind .. " state stack balanced")
            eq(f.record.saves, 1, kind .. " exactly one primitive save boundary")
            eq(f.record.restores, 1, kind .. " exactly one primitive restore boundary")
            eq(f.record.marker, "host-transform-scissor-alpha", kind .. " host state restored")
            signatures[kind] = geometrySignature(f.record)
            local early, late = primitiveFixture(), primitiveFixture()
            paint(early, kind, .19, 1); paint(late, kind, .73, 1)
            check(geometrySignature(early.record) ~= geometrySignature(late.record),
                kind .. " choreography changes real geometry over time, not just color")
            local a, b = primitiveFixture(), primitiveFixture()
            paint(a, kind, .5, 1, {duration = 2})
            paint(b, kind, .5, 1, {duration = 6})
            eq(geometrySignature(a.record), geometrySignature(b.record),
                kind .. " geometry uses normalized phase, not absolute seconds")
        end
        for i = 1, #kinds do
            for j = i + 1, #kinds do
                check(signatures[kinds[i]] ~= signatures[kinds[j]],
                    "no-color identity differs " .. kinds[i] .. "/" .. kinds[j])
            end
        end
    end)
    case("real-primitives-every-color-alpha-multiplied", function()
        for _, kind in ipairs(kinds) do
            local full, half, zero = primitiveFixture(), primitiveFixture(), primitiveFixture()
            paint(full, kind, .5, 1); paint(half, kind, .5, .5); paint(zero, kind, .5, 0)
            eq(#zero.record.calls, 0, kind .. " alpha zero is total no-op, no state changes")
            eq(#zero.record.colors, 0, kind .. " alpha zero creates no colors")
            eq(geometrySignature(full.record), geometrySignature(half.record),
                kind .. " transparency cannot change geometry")
            eq(#full.record.colors, #half.record.colors, kind .. " half preserves every color call")
            local correct, positive = true, 0
            for i, c in ipairs(full.record.colors) do
                local h = half.record.colors[i]
                if not h then correct = false; break end
                for channel = 1, 3 do if c.rgba[channel] ~= h.rgba[channel] then correct = false end end
                if c.rgba[4] > 0 then positive = positive + 1 end
                if math.abs(h.rgba[4] - c.rgba[4] * .5) > (c.unit == 255 and .5 or .00001) then correct = false end
            end
            check(positive > 0, kind .. " alpha assertion tested visible color data")
            check(correct, kind .. " every fill/stroke/gradient RGBA alpha multiplied")
            local clamped = primitiveFixture(); paint(clamped, kind, .5, 3)
            eq(#full.record.colors, #clamped.record.colors, kind .. " excessive alpha clamped")
            local same = true
            for i, c in ipairs(full.record.colors) do
                local d = clamped.record.colors[i]
                if not d or c.rgba[4] ~= d.rgba[4] then same = false end
            end
            check(same, kind .. " alpha above one equals one")
        end
    end)
    case("real-primitives-invalid-parameters-no-op", function()
        local cases = {
            {width = -1}, {width = 0}, {height = -1}, {height = 0},
            {width = math.huge}, {height = math.huge}, {cx = 0 / 0}, {cy = math.huge},
            {cx = -math.huge}, {duration = -1}, {duration = 0}, {duration = math.huge},
            {elapsed = -1}, {elapsed = 0}, {elapsed = math.huge}, {elapsed = 0 / 0},
            {width = 1e8}, {cx = 1e8},
        }
        for _, kind in ipairs(kinds) do
            for index, args in ipairs(cases) do
                if not ((kind == "success" or kind == "failure") and args.height) then
                    local f = primitiveFixture()
                    local ok = pcall(paint, f, kind, .5, 1, args)
                    check(ok and #f.record.calls == 0 and f.record.invalid == 0,
                        kind .. " invalid argument case " .. index .. " no native calls/no error")
                end
            end
            for _, alpha in ipairs({-1, 0 / 0, math.huge, -math.huge}) do
                local f = primitiveFixture(); paint(f, kind, .5, alpha)
                eq(#f.record.calls, 0, kind .. " invalid/nonpositive alpha no-op " .. tostring(alpha))
            end
            local f = primitiveFixture(); paint(f, kind, 1, 1)
            eq(#f.record.calls, 0, kind .. " deadline frame draws nothing")
        end
        local f = primitiveFixture()
        f.effect.drawCard({}, "unknown", 0, 0, 200, 350, 1, 2, 1)
        f.effect.drawResult({}, "true", 0, 0, 200, 1, 2, 1)
        f.effect.drawPower(nil, 0, 0, 760, 140, 1, 2, 1)
        eq(#f.record.calls, 0, "unknown identities/nonboolean result/nil context all noop")
    end)
    case("real-primitives-fault-restoration-and-random-isolation", function()
        local originalRandom, originalSeed = math.random, math.randomseed
        local trapMath = {} ---@type table<string, any>
        for k, v in pairs(math) do trapMath[k] = v end
        local randomCalls = 0
        trapMath.random = function() randomCalls = randomCalls + 1; error("MATH_RANDOM_TOUCHED", 0) end
        trapMath.randomseed = trapMath.random
        for _, kind in ipairs(kinds) do
            local f = primitiveFixture()
            f.env.math = trapMath
            paint(f, kind, .5, 1)
            eq(randomCalls, 0, kind .. " never consumes or seeds combat RNG")
            for _, name in ipairs({"nvgTranslate", "nvgFill", "nvgStroke", "nvgLinearGradient"}) do
                local fault = primitiveFixture(); fault.record.throwAt = name
                check(not pcall(paint, fault, kind, .5, 1), kind .. " propagates injected " .. name)
                eq(fault.record.depth, 0, kind .. " restores primitive frame after " .. name)
                eq(fault.record.marker, "host-transform-scissor-alpha", kind .. " host unchanged after " .. name)
            end
        end
        eq(math.random, originalRandom, "global math.random never overwritten")
        eq(math.randomseed, originalSeed, "global math.randomseed never overwritten")
    end)
end
local function runCardLifecycle()
    local drawn = {}
    local effects = { drawCard = function(...)
        drawn[#drawn + 1] = { ... }
    end }
    case("card-wallclock-no-draw-and-scopes", function()
        local f = controllerFixture("ui/fx/SpineCardEffect.lua", effects)
        local callbacks = {level = 0, job = 0, revive = 0, dungeon = 0}
        f.effect.preload(nil); f.effect.preload(f.vg)
        eq(f.record.forbidden, 0, "Card preload never touches Spine or images")
        f.effect.playLevelUp(100, 200, function() callbacks.level = callbacks.level + 1 end)
        f.effect.playJobChange(300, 400, function() callbacks.job = callbacks.job + 1 end)
        f.effect.playRevive(500, 600, function() callbacks.revive = callbacks.revive + 1 end)
        f.effect.playRevive(700, 800, function() callbacks.dungeon = callbacks.dungeon + 1 end, "dungeon")
        check(f.effect.isPlaying("battle") and f.effect.isPlaying("church")
            and f.effect.isPlaying("dungeon"), "Card scopes each active")
        check(not f.effect.isPlaying("unknown"), "unknown scope has no card instances")
        f.effect.update(999)
        eq(callbacks.level + callbacks.job + callbacks.revive + callbacks.dungeon, 0,
            "large dt cannot prematurely complete Card")
        f.clock.elapsedTime = 100.91
        f.effect.update(0)
        eq(callbacks.revive, 1, "revive completes without any draw")
        eq(callbacks.dungeon, 1, "hidden dungeon revive completes without draw")
        eq(callbacks.level, 0, "level survives shorter revive duration")
        eq(callbacks.job, 0, "job survives shorter revive duration")
        f.clock.elapsedTime = 101.34
        f.effect.update(-1)
        eq(callbacks.level, 1, "level wallclock completes once")
        eq(callbacks.job, 1, "job wallclock completes once")
        for _ = 1, 5 do f.effect.update(0); f.effect.isPlaying() end
        eq(callbacks.level + callbacks.job + callbacks.revive + callbacks.dungeon, 4,
            "queries and updates cannot duplicate Card callbacks")
        check(not f.effect.isPlaying(), "all Card instances expired")
    end)
    case("card-draw-scope-isolation-and-restart", function()
        local f = controllerFixture("ui/fx/SpineCardEffect.lua", effects)
        local old, fresh = 0, 0
        drawn = {}
        f.effect.playLevelUp(100, 200, function() old = old + 1 end)
        f.effect.playJobChange(300, 400)
        f.effect.playRevive(500, 600, nil, "dungeon")
        f.clock.elapsedTime = 100.2
        f.effect.draw(f.vg, "church")
        eq(#drawn, 1, "church draws exactly its job record")
        f.effect.draw(f.vg, "battle")
        eq(#drawn, 2, "battle cannot draw dungeon or church records")
        f.effect.draw(f.vg, "dungeon")
        eq(#drawn, 3, "dungeon draws only its revive record")
        eq(f.record.depth, 0, "Card draws save/restore balanced")
        eq(f.record.marker, "host-transform-scissor-alpha", "Card preserves host state")
        f.clock.elapsedTime = 101.0
        f.effect.playLevelUp(100, 200, function() fresh = fresh + 1 end)
        drawn = {}; f.effect.draw(f.vg, "battle")
        eq(#drawn, 1, "same-kind same-scope same-position restart merges record")
        f.clock.elapsedTime = 101.34; f.effect.update(0)
        eq(old, 0, "Card replaced callback canceled")
        eq(fresh, 0, "restarted Card not finished by old deadline")
        f.clock.elapsedTime = 102.34; f.effect.update(0)
        eq(fresh, 1, "restarted Card has own deadline")
    end)
    case("card-callback-reentry-throw-and-batch-cancel", function()
        local f = controllerFixture("ui/fx/SpineCardEffect.lua", effects)
        local first, second, errorCalls = 0, 0, 0
        f.effect.playRevive(100, 200, function()
            first = first + 1
            f.effect.playLevelUp(100, 200, function() second = second + 1 end)
        end)
        f.effect.playRevive(300, 400, function() errorCalls = errorCalls + 1; error("CALLBACK_FAULT", 0) end)
        f.clock.elapsedTime = 100.91
        check(pcall(f.effect.update, 0), "throwing Card callback cannot escape update")
        eq(first, 1, "Card first callback once")
        eq(errorCalls, 1, "throwing Card callback attempted once")
        check(f.effect.isPlaying("battle"), "Card callback-created playback survives detached batch")
        f.clock.elapsedTime = 102.25; f.effect.update(0)
        eq(second, 1, "Card reentrant playback completes once")
        local canceled = 0
        f.effect.playRevive(500, 600, function() f.effect.stopAll("battle") end)
        f.effect.playRevive(700, 800, function() canceled = canceled + 1 end)
        f.clock.elapsedTime = 103.16; f.effect.update(0)
        eq(canceled, 0, "stopAll from callback cancels same-batch pending callbacks")
        f.effect.playLevelUp(100, 200, function() canceled = canceled + 1 end)
        f.effect.playJobChange(100, 200, function() canceled = canceled + 1 end)
        f.effect.stopAll("battle")
        check(not f.effect.isPlaying("battle") and f.effect.isPlaying("church"),
            "scope stop cancels only matching records")
        f.effect.destroy(); f.effect.destroy()
        f.clock.elapsedTime = 200; f.effect.update(0)
        eq(canceled, 0, "destroy cancels callbacks rather than completes them")
        eq(f.record.forbidden, 0, "Card lifecycle uses no native Spine/image calls")
    end)
    case("card-procedural-fault-keeps-timed-business-callback", function()
        local calls, complete = 0, 0
        local f = controllerFixture("ui/fx/SpineCardEffect.lua", { drawCard = function()
            calls = calls + 1; error("PROCEDURAL_CARD_FAULT", 0)
        end })
        f.effect.playLevelUp(100, 200, function() complete = complete + 1 end)
        f.clock.elapsedTime = 100.2
        local outer = 0
        local ok = pcall(function() f.effect.draw(f.vg, "battle"); outer = outer + 1 end)
        check(ok and outer == 1, "Card drawing fault cannot cut off outer host draw")
        eq(f.record.depth, 0, "Card fault restores own save boundary")
        for _ = 1, 5 do f.effect.draw(f.vg, "battle") end
        eq(calls, 1, "Card procedural fault visually disables once")
        f.clock.elapsedTime = 101.34; f.effect.update(0)
        eq(complete, 1, "Card visual failure preserves natural completion business callback")
        eq(f.record.forbidden, 0, "Card fault never falls back to Spine/image")
    end)
end

local function runResultLifecycle()
    case("result-wallclock-no-draw-success-failure-and-stop", function()
        local draws, completed = 0, 0
        local f = controllerFixture("ui/fx/SpineResultEffect.lua", {drawResult = function() draws = draws + 1 end})
        f.effect.preload(nil); f.effect.preload(f.vg)
        for _, success in ipairs({true, false}) do
            f.effect.play(success, function() completed = completed + 1 end)
            local start = f.clock.elapsedTime
            f.effect.update(999)
            check(f.effect.isPlaying(), "Result large dt does not advance wallclock")
            f.clock.elapsedTime = start + (success and 1.6667 or 1.3333) - 0.01
            f.effect.update(0)
            check(f.effect.isPlaying(), "Result duration respected " .. tostring(success))
            f.clock.elapsedTime = start + (success and 1.6667 or 1.3333) + 0.01
            f.effect.update(0)
            check(not f.effect.isPlaying(), "Result completes with no draw " .. tostring(success))
        end
        eq(completed, 2, "success and failure each complete once")
        eq(draws, 0, "no-draw Result genuinely performed no primitive calls")
        for _ = 1, 5 do f.effect.update(0); f.effect.isPlaying() end
        eq(completed, 2, "Result repeated query cannot repeat callback")
        f.effect.play(true, function() completed = completed + 1 end)
        f.effect.stop(); f.effect.stop()
        f.clock.elapsedTime = 200; f.effect.update(0)
        eq(completed, 2, "Result stop cancels callback")
        f.effect.destroy(); f.effect.destroy()
        eq(f.record.forbidden, 0, "Result preload/lifecycle has no native create/load/images")
    end)
    case("result-callback-throw-and-reentry", function()
        local count = 0
        local f = controllerFixture("ui/fx/SpineResultEffect.lua", {drawResult = function() end})
        f.effect.play(true, function() count = count + 1; error("RESULT_CALLBACK_FAULT", 0) end)
        f.clock.elapsedTime = 101.68
        check(pcall(f.effect.update, 0), "Result callback error contained")
        eq(count, 1, "Result throwing callback invoked once")
        check(not f.effect.isPlaying(), "throwing Result callback leaves old playback stopped")
        f.effect.play(true, function()
            count = count + 1
            f.effect.destroy()
            f.effect.play(false, function() count = count + 1 end)
        end)
        f.clock.elapsedTime = 103.36; f.effect.update(0)
        eq(count, 2, "Result initial reentrant callback once")
        check(f.effect.isPlaying(), "destroy/replay callback retains new Result")
        f.clock.elapsedTime = 104.70; f.effect.update(0)
        eq(count, 3, "Result reentrant own deadline completes once")
        local canceled = 0
        f.effect.play(true, function() canceled = canceled + 1 end)
        f.effect.play(false)
        f.clock.elapsedTime = 106.1; f.effect.update(0)
        eq(canceled, 0, "Result replacing play cancels old callback")
    end)
    case("result-procedural-error-safely-disables-once", function()
        local complete, draws = 0, 0
        local throw = true
        local f = controllerFixture("ui/fx/SpineResultEffect.lua", {drawResult = function()
            draws = draws + 1
            if throw then error("RESULT_PROCEDURAL_FAULT", 0) end
        end})
        f.effect.play(true, function() complete = complete + 1 end)
        f.clock.elapsedTime = 100.2
        local after = 0
        check(pcall(function() f.effect.draw(f.vg, 500, 600, 160); after = after + 1 end),
            "Result procedural fault does not throw")
        eq(after, 1, "Result fault cannot truncate following host region")
        eq(f.record.depth, 0, "Result fault balances save/restore")
        eq(f.record.marker, "host-transform-scissor-alpha", "Result fault preserves host state")
        local logs = #f.logs
        for _ = 1, 8 do f.effect.draw(f.vg, 500, 600, 160); f.effect.play(false) end
        eq(draws, 1, "Result fault not retried every draw")
        eq(#f.logs, logs, "Result disabled does not repeat failure logs")
        f.clock.elapsedTime = 200; f.effect.update(0)
        eq(complete, 0, "Result drawing failure cancels unsafe current callback")
        check(not f.effect.isPlaying(), "Result disabled remains stopped")
        throw = false; f.effect.destroy(); f.effect.play(false)
        f.effect.draw(f.vg, 500, 600, 160)
        eq(draws, 2, "Result explicit destroy permits repaired procedural replay")
        check(f.effect.isPlaying(), "repaired Result replay valid")
        eq(f.record.forbidden, 0, "Result fault never loads a Spine fallback")
    end)
    case("result-old-draw-fault-cannot-cancel-reentrant-new-play", function()
        local complete = 0
        local f
        local effects = {drawResult = function()
            f.effect.play(false, function() complete = complete + 1 end)
            error("OLD_PLAYBACK_RENDER_FAULT", 0)
        end}
        f = controllerFixture("ui/fx/SpineResultEffect.lua", effects)
        f.effect.play(true)
        f.clock.elapsedTime = 100.2
        check(pcall(f.effect.draw, f.vg, 500, 600, 160), "old draw fault contained after reentry")
        check(f.effect.isPlaying(), "new Result survives old draw failure")
        eq(f.record.depth, 0, "reentrant Result failure restores host boundary")
        effects.drawResult = function() end
        f.clock.elapsedTime = 101.54; f.effect.update(0)
        eq(complete, 1, "new Result callback reaches its own deadline")
    end)
end
local uiState = { fixture = nil, stage = 0 } ---@type table<string, any>
local function realPowerFixture()
    if not uiState.fixture then uiState.fixture = powerFixture(true) end
    return uiState.fixture
end

local function hostTextWidth(vg, label)
    local UI = require("urhox-libs/UI")
    -- Measure on the SAME actual context whose frame is active; UI.MeasureTextWidth uses UI's private context.
    nvgSave(vg); nvgResetTransform(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, UI.Theme.FontSize(label.props.fontSize))
    local width = nvgTextBounds(vg, 0, 0, label:GetText(), nil, nil, false)
    nvgRestore(vg)
    return width
end

local function runPowerUI(vg)
    uiState.stage = uiState.stage + 1
    local currentStage = uiState.stage
    if currentStage <= 6 then case("power-real-ui-yoga-host-" .. currentStage, function()
        local UI = require("urhox-libs/UI")
        local f = realPowerFixture()
        if currentStage == 1 then f:baseline(); f:emit({123456, 234567, 345678}); f.clock.elapsedTime = 102.6 end
        local hosts = { {1920,1080,1}, {3840,2160,2}, {2560,1080,1},
            {1080,2400,3}, {800,600,1}, {360,640,2} }
        for _, host in ipairs({hosts[currentStage]}) do
            -- Hosts supply logical dimensions, exactly as finishFrame; no graphics:SetMode.
            local width, height = host[1] / host[3], host[2] / host[3]
            local left, top, scale, cardHeight = f.power.getGeometry(width, height)
            near(left + 760 * scale * .5, width * .5, "Power center X host " .. table.concat(host,"/"))
            near(top + cardHeight * scale * .5, height * .5, "Power center Y host " .. table.concat(host,"/"))
            check(left >= 0 and top >= 0 and scale > 0 and scale <= 1, "Power host bounded geometry")
            local before = #f.draws
            f.power.draw(vg, width, height)
            eq(#f.draws, before + 1, "Power calls actual Surface.draw for host")
            local capture = assert(f.draws[#f.draws], "real Surface call missing")
            local root = capture.root
            local layout = root:GetLayout()
            near(layout.w, 760, "real Yoga root width")
            near(layout.h, cardHeight, "real Yoga root height matches geometry")
            near(capture.width, layout.w, "Surface width matches actual root")
            near(capture.height, layout.h, "Surface height matches actual root")
            eq(root.props.pointerEvents, "none", "Power UI never captures game input")
            local children = root:GetChildren()
            local header = children[1] ---@type Label
            eq(header:GetText(), "战力提升", "real title Label has correct text")
            near(header:GetAbsoluteLayout().x + header:GetAbsoluteLayout().w*.5, layout.w*.5,
                "real title Label center aligned")
            eq(header.props.textAlign, "center", "title text alignment center")
            local expected = {123456,234567,345678}
            for team = 1, 3 do
                local row = children[team + 1]
                check(row:IsVisible(), "real team row visible " .. team)
                local labels = row:GetChildren()
                local teamLabel, valueLabel = labels[1], labels[2] ---@type Label, Label
                eq(teamLabel:GetText(), "小队 " .. team, "real team Label identity " .. team)
                check(valueLabel:GetText():find(tostring(expected[team]),1,true) ~= nil,
                    "real value Label contains team power " .. team)
                check(valueLabel:GetText():find("+",1,true) ~= nil, "real value Label displays delta")
                local cell = valueLabel:GetAbsoluteLayout()
                near(cell.x + cell.w*.5, layout.w*.5, "real team value Label centered", .50001)
                check(cell.w > 0 and cell.h > 0 and cell.y + cell.h <= layout.h + .001,
                    "real Label width/height inside root")
                eq(valueLabel.props.textAlign, "center", "real numeric text centered")
                local textWidth = hostTextWidth(vg, valueLabel)
                check(textWidth > 0 and textWidth <= cell.w + 1 and cell.w <= 580 + .001,
                    "actual font auto-width inside content area")
            end
        end
    end)
    elseif currentStage <= 11 then case("power-real-ui-language-" .. currentStage, function()
        local UI = require("urhox-libs/UI")
        local f = realPowerFixture()
        if currentStage == 7 then
            f:baseline({0,0,0}); f:emit({1e300, 987654321098765, 123456789})
            f.clock.elapsedTime = f.clock.elapsedTime + .5
        end
        local languages = {{"zh_CN","战力提升"},{"zh_TW","戰力提升"},{"en","POWER INCREASED"},
            {"ja","戦力上昇"},{"ko","전투력 상승"}}
        local entry = languages[currentStage - 6]
        for language, expected in pairs({[entry[1]]=entry[2]}) do
            f.language.value = language
            f.power.draw(vg, 1920, 1080)
            local root = assert(f.draws[#f.draws]).root
            local children = root:GetChildren()
            local header = children[1] ---@type Label
            eq(header:GetText(), expected, "real localized title " .. language)
            for team = 1, 3 do
                local labels = children[team+1]:GetChildren()
                local value = labels[2] ---@type Label
                local layout = value:GetAbsoluteLayout()
                local text = value:GetText()
                check(#text < 100 and text:find("+",1,true) ~= nil,
                    "extreme finite number compact and retains increase " .. language .. "/" .. team)
                local textWidth = hostTextWidth(vg, value)
                check(textWidth > 0 and textWidth <= layout.w + 1 and layout.w <= 580 + .001,
                    "long actual multilingual text auto-width inside content area " .. language .. "/" .. team
                    .. " measured=" .. tostring(textWidth) .. " layout=" .. tostring(layout.w)
                    .. " size=" .. tostring(value.props.fontSize))
            end
        end
    end)
    elseif currentStage <= 16 then case("power-real-ui-font-transition-" .. currentStage, function()
        local f = realPowerFixture()
        local values = {987654321098765, 123456, 987654321098765,
            999999999999999872, 999999999999999872}
        local index = currentStage - 11
        local value = values[index]
        if index < 5 then
            f:baseline({0,0,0}); f:emit({0,value,0})
            f.clock.elapsedTime = f.clock.elapsedTime + .5
        end
        f.power.draw(vg,1920,1080)
        local root = assert(f.draws[#f.draws]).root
        local label = root:GetChildren()[3]:GetChildren()[2] ---@type Label
        local layout = label:GetAbsoluteLayout()
        local text = label:GetText()
        local formatted = string.format("%.0f", value)
        eq(text, formatted .. "   +" .. formatted,
            "long/short/18-digit Power retains exact integer display frame " .. index)
        check(not text:find("e",1,true), "up to 18 digits not replaced by scientific notation")
        local measured = hostTextWidth(vg,label)
        print(TAG .. string.format(" [UI WIDTH] frame=%d bytes=%d font=%s measured=%s layout=%s value=%s",
            index,#text,tostring(label.props.fontSize),tostring(measured),tostring(layout.w),text))
        check(measured > 0 and measured <= layout.w + 1 and layout.w <= 580 + .001,
            "consecutive long/short/integer-max actual width stays inside 580 frame=" .. index
            .. " measured=" .. tostring(measured) .. " layout=" .. tostring(layout.w)
            .. " font=" .. tostring(label.props.fontSize))
        near(layout.x + layout.w*.5,root:GetLayout().w*.5,
            "consecutive font change actual Label centered",.50001)
        if index == 2 then
            eq(label.props.fontSize,27,"long to short restores normal font")
            check(layout.w < uiState.transitionWidth,"long to short recomputes narrower auto width")
        elseif index == 3 then
            check(label.props.fontSize < 27,"short to long reduces font before measurement")
            check(layout.w > uiState.transitionWidth,"short to long recomputes larger auto width")
        elseif index == 5 then
            near(layout.w,uiState.transitionWidth,"unchanged maximum integer width stable next frame")
            eq(text,uiState.transitionText,"unchanged maximum integer text stable next frame")
        end
        if uiState.transitionLabel then
            eq(label,uiState.transitionLabel,"font transitions reuse SAME actual Label instance")
        end
        uiState.transitionLabel,uiState.transitionWidth,uiState.transitionText = label,layout.w,text
    end)
    elseif currentStage == 17 then case("power-real-ui-empty-row-hide-invalid-host-noop", function()
        local f = realPowerFixture(); f:baseline(); f:emit({100, 230, 300})
        f.clock.elapsedTime = f.clock.elapsedTime + .5
        f.power.draw(vg, 1920,1080)
        local root = assert(f.draws[#f.draws]).root
        local children = root:GetChildren()
        check(not children[2]:IsVisible() and children[3]:IsVisible() and not children[4]:IsVisible(),
            "only team2 shown, hidden rows genuinely leave Yoga layout")
        local before = #f.draws
        for _, size in ipairs({{0,1080},{-1,1080},{1920,0},{0/0,1080},
            {math.huge,1080},{1920,-math.huge}}) do
            check(pcall(f.power.draw, vg, size[1],size[2]), "invalid Power host is contained")
        end
        eq(#f.draws, before, "invalid host never reaches real Surface")
        check(f.power.isPlaying(), "invalid host noop does not disable valid Power state")
        f.power.draw(vg,1920,1080)
        eq(#f.draws,before+1,"Power draws again after invalid host")
    end)
    elseif currentStage == 18 then case("power-real-label-render-fault-recovers-outer-state", function()
        local f = realPowerFixture()
        f:baseline(); f:emit({110,220,330}); f.clock.elapsedTime = f.clock.elapsedTime + .5
        f.power.draw(vg,1920,1080)
        local root = assert(f.draws[#f.draws]).root
        local label = root:GetChildren()[1] ---@type Label
        local nativeSave, nativeRestore, nativeText = nvgSave, nvgRestore, nvgText
        local originalRender = label.Render
        local depth, attempts = 0, 0
        -- 注入真实Label实例方法，不替换任何原生全局C绑定；外层env只spy转发真实Save/Restore。
        f.env.nvgSave = function(ctx) nativeSave(ctx); depth = depth + 1 end
        f.env.nvgRestore = function(ctx) nativeRestore(ctx); depth = depth - 1 end
        label.Render = function(self, ctx)
            originalRender(self, ctx) -- 先真实渲染字体，随后在同一实际Label路径制造Lua故障。
            attempts = attempts + 1
            error("REAL_LABEL_RENDER_FAULT",0)
        end
        local ok, err = pcall(function()
            local after = 0
            f.power.draw(vg,1920,1080); after = after + 1
            eq(after,1,"real Label render error does not truncate host caller")
            check(attempts > 0,"fault truly executed real Label Render and glyph drawing")
            eq(depth,0,"actual Power outer save/restore recovered after Label fault")
            eq(nvgSave,nativeSave,"Power never rewrites native global save")
            eq(nvgRestore,nativeRestore,"Power never rewrites native global restore")
            eq(nvgText,nativeText,"Power never rewrites native text binding")
            check(not f.power.isPlaying(),"real UI failure safely disables only Power visual")
            local previous = attempts
            f.power.draw(vg,1920,1080)
            eq(attempts,previous,"disabled Power does not retry real Label error")
        end)
        label.Render = originalRender
        f.env.nvgSave, f.env.nvgRestore = nativeSave, nativeRestore
        if not ok then error(err,0) end
        -- 原生字形C调用自身throw/驱动故障不在此安全Lua注入的覆盖范围。
        f.power.destroy()
    end) end
end

local function configureVisual()
    for _, arg in ipairs(GetArguments()) do
        if arg == "-dark-visual" then visual.enabled = true end
        if arg == "-dark-power-only" then visual.powerOnly = true end
        if arg == "-dark-ui-only" then testMode.uiOnly = true end
        if arg == "-dark-logic-only" then testMode.logicOnly = true end
        local sample = arg:match("^%-dark%-sample=(.+)$")
        if sample then
            local number = tonumber(sample)
            assert(finite(number) and number >= 0 and number <= 4, "dark-sample must be finite 0..4 seconds")
            visual.sample = number
        end
        local language = arg:match("^%-dark%-lang=(.+)$")
        if language then
            assert(({zh_CN=true,zh_TW=true,en=true,ja=true,ko=true})[language], "unsupported dark-lang")
            visual.language = language
        end
        local teams = arg:match("^%-dark%-teams=(.+)$")
        if teams then
            local number = tonumber(teams)
            assert(number and number >= 1 and number <= 3 and number == math.floor(number), "dark-teams must be 1..3")
            visual.teams = number
        end
    end
end

local function setupVisual(vg)
    local primitives = require("ui.fx.DarkEffectPrimitives")
    local function nativeFixture(path)
        local f = controllerFixture(path, primitives)
        for key, value in pairs(_G) do
            if type(key) == "string" and key:match("^nvg") then f.env[key] = value end
        end
        return f
    end
    visual.power = powerFixture(true)
    visual.power.language.value = visual.language
    visual.power:baseline({10000, 20000, 30000})
    local values = {123456, 234567, 345678}
    for team = visual.teams + 1, 3 do values[team] = team * 10000 end
    visual.power:emit(values)
    visual.power.clock.elapsedTime = 102 + visual.sample
    visual.card = nativeFixture("ui/fx/SpineCardEffect.lua")
    visual.success = nativeFixture("ui/fx/SpineResultEffect.lua")
    visual.failure = nativeFixture("ui/fx/SpineResultEffect.lua")
    visual.card.effect.playLevelUp(250, 760, nil, "sample", 198, 198*955/538)
    visual.card.effect.playJobChange(600, 760, nil, "sample", 198, 198*955/538)
    visual.card.effect.playRevive(960, 760, nil, "sample", 198, 198*955/538)
    visual.success.effect.play(true)
    visual.failure.effect.play(false)
    visual.card.clock.elapsedTime = 100 + visual.sample
    visual.success.clock.elapsedTime = 100 + visual.sample
    visual.failure.clock.elapsedTime = 100 + visual.sample
    for index, id in ipairs({1,2,3}) do
        visual.images[index] = nvgCreateImage(vg, "image/角色卡牌/KP_YX_" .. id .. ".png", 0)
        assert(visual.images[index] > 0, "real reference card missing " .. id)
    end
    local UI = require("urhox-libs/UI")
    require("ui.widget.DesignWidgetSurface").init()
    local captions = {
        zh_CN={"升级","转职","复活","成功","失败"}, zh_TW={"升級","轉職","復活","成功","失敗"},
        en={"LEVEL UP","JOB CHANGE","REVIVE","SUCCESS","FAILURE"},
        ja={"レベル上昇","転職","復活","成功","失敗"}, ko={"레벨 상승","전직","부활","성공","실패"},
    }
    local children = {}
    for index, text in ipairs(captions[visual.language]) do
        children[#children+1] = UI.Label {text=text, width=250, height=44, fontSize=22,
            textAlign="center", verticalAlign="middle", fontColor={216,201,163,255}, pointerEvents="none",
            position="absolute", left=({125,475,835,1195,1555})[index], top=520}
    end
    children[#children+1] = UI.Label {text=string.format("sample %.2fs | teams %d | %s | real UI / cards / procedural paths",
        visual.sample, visual.teams, visual.language), width="100%", height=45, fontSize=14,
        textAlign="center", fontColor={150,138,110,255}, pointerEvents="none", position="absolute", top=1010}
    visual.caption = UI.Panel {width=1920,height=1080,pointerEvents="none",children=children}
    print(TAG .. " VISUAL ONLY sample=" .. visual.sample .. " lang=" .. visual.language .. " teams=" .. visual.teams)
    print(TAG .. " LIMIT: real controlled-stage renderer; not live gameplay input/performance validation")
end

local function drawVisual(vg)
    nvgBeginPath(vg); nvgRect(vg,0,0,1920,1080)
    nvgFillColor(vg,nvgRGBA(13,11,9,255)); nvgFill(vg)
    if visual.powerOnly then visual.power.power.draw(vg,1920,1080); return end
    -- Power actual controller is centered in a bounded top host; its UI tree/Surface/labels are real.
    visual.power.power.draw(vg,1920,470)
    for index, center in ipairs({250,600,960}) do
        local w,h=198,198*955/538
        nvgBeginPath(vg); nvgRect(vg,center-w*.5,760-h*.5,w,h)
        local paintValue = nvgImagePattern(vg,center-w*.5,760-h*.5,w,h,0,visual.images[index],1)
        ---@cast paintValue NVGpaint
        nvgFillPaint(vg,paintValue)
        nvgFill(vg)
    end
    visual.card.effect.draw(vg,"sample")
    visual.success.effect.draw(vg,1320,760,250)
    visual.failure.effect.draw(vg,1680,760,250)
    require("ui.widget.DesignWidgetSurface").draw(visual.caption,vg,1920,1080)
end

local function setupTestUI()
    -- Initialize UI's private context BEFORE entering any host NanoVGRender callback.
    require("ui.widget.DesignWidgetSurface").init()
    uiState.fixture = powerFixture(true)
end

function Start()
    local ok, err = pcall(function()
        configureVisual()
        for _, path in ipairs({ "core/EventBus.lua", "ui/fx/SpinePowerUpEffect.lua",
            "ui/fx/SpineCardEffect.lua", "ui/fx/SpineResultEffect.lua", "ui/fx/DarkEffectPrimitives.lua" }) do
            sources[path] = readSource(path)
        end
        if not visual.enabled and not testMode.uiOnly then
            runPowerEvents()
            runPrimitives()
            runCardLifecycle()
            runResultLifecycle()
            if testMode.logicOnly then summarize(); return end
        end
        renderContext = assert(nvgCreate(1), "real NanoVG context unavailable")
        check(nvgCreateFont(renderContext, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0,
            "real multilingual host font loaded")
        if visual.enabled then setupVisual(renderContext) else setupTestUI() end
        SubscribeToEvent(renderContext, "NanoVGRender", "HandleDarkEffectsTestRender")
    end)
    if not ok then check(false, "suite startup: " .. tostring(err)); summarize() end
end

---@param _eventType string
---@param _eventData NanoVGRenderEventData
function HandleDarkEffectsTestRender(_eventType, _eventData)
    if ended or not renderContext then return end
    local vg = renderContext
    local dpr = graphics:GetDPR()
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    local begun = false
    local ok, err = pcall(function()
        nvgBeginFrame(vg, width, height, dpr); begun = true
        if visual.enabled then
            -- 模式 A：明确1920x1080设计画面，逻辑帧DPR+contain；不使用物理像素布局。
            local scale = math.min(width/1920,height/1080)
            nvgSave(vg); nvgTranslate(vg,(width-1920*scale)*.5,(height-1080*scale)*.5)
            nvgScale(vg,scale,scale); drawVisual(vg); nvgRestore(vg)
        else runPowerUI(vg) end
    end)
    if begun then
        local frameOk, frameErr = pcall(nvgEndFrame, vg)
        if not frameOk then check(false, "real NanoVG frame completion: " .. tostring(frameErr)) end
    end
    if not ok then check(false, "real UI suite exception: " .. tostring(err)) end
    if not ok or (not visual.enabled and uiState.stage >= 18) then summarize() end
end

function Stop()
    if renderContext then nvgDelete(renderContext); renderContext = nil end
end
