-- 离线奖励大批量弹出回归：真实时间轴与弹窗，模拟时钟，不改存档或图形 API。
-- Runtime: tests/offline_reward_cascade_test.lua -tapcode_dir=<隔离frozen> -tool_mode -graphicsheadless
-- 真实Panel/ExpTable/I18n/HeroFrame私有_ENV；Noto字体与NVG测量/绘制原生委托。
-- 只读源码由cache:GetFile读取；File/FS/RNG、玩家动作/存档和外部图片加载封闭。
-- UI动画时间明确按累计dt最近微秒；保留原始dt累计，不更改正式经验/奖励/cascade时序。
local TAG = "[offline_reward_cascade_test]"
local suite = { checks = 0, failed = 0, cases = 0, frames = 0, bounds = 0, io = 0, rng = 0 }
local sourceCache = {}
---@type any
local fontVG = nil
---@type any
local rootFixture = nil
local finished = false
local native = { text = nvgText, bounds = nvgTextBounds, size = nvgFontSize,
    face = nvgFontFace, align = nvgTextAlign, save = nvgSave, restore = nvgRestore,
    rounded = nvgRoundedRect, fill = nvgFill, color = nvgFillColor, rgba = nvgRGBA,
    scissor = nvgScissor, intersect = nvgIntersectScissor, resetClip = nvgResetScissor }

local function sourceText(name)
    local path = name:gsub("%.", "/") .. ".lua"
    if sourceCache[path] then return sourceCache[path] end
    local file = assert(cache:GetFile(path), "专项缺少真实源码 " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    sourceCache[path] = table.concat(lines, "\n")
    return sourceCache[path]
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function upvalue(fn, wanted)
    for index = 1, 100 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
    error("真实Panel缺少私有状态 " .. wanted)
end

local function newFixture()
    local f = { mods = {}, clock = { elapsedTime = 100 }, player = false, gets = 0,
        writes = 0, io = 0, rng = 0, images = 0, sounds = {}, sims = {}, playerSims = {},
        texts = {}, strokeTexts = {}, heroes = {}, fills = {}, rows = {}, drawErrors = {},
        colorArgs = {}, clips = {}, font = 22, align = NVG_ALIGN_LEFT, color = {}, stack = {}, depth = 0 }
    local env = setmetatable({}, { __index = _G })
    env._G, env.time = env, f.clock
    local function deniedIO()
        f.io = f.io + 1; suite.io = suite.io + 1
        error("离线专项禁止File/FS/玩家档", 0)
    end
    local function deniedRNG()
        f.rng = f.rng + 1; suite.rng = suite.rng + 1
        error("离线专项禁止RNG", 0)
    end
    env.File, env.FileSystem, env.GetFileSystem = deniedIO, deniedIO, deniedIO
    env.fileSystem = setmetatable({}, { __index = function() return deniedIO end })
    env.io = setmetatable({}, { __index = function() return deniedIO end })
    env.dofile, env.loadfile = deniedIO, deniedIO
    env.cache = setmetatable({}, { __index = function() return deniedIO end })
    env.os = setmetatable({ clock = os.clock }, { __index = function() return deniedIO end })
    env.math = setmetatable({ random = deniedRNG, randomseed = deniedRNG }, { __index = math })
    env.Random, env.RandomInt, env.SetRandomSeed = deniedRNG, deniedRNG, deniedRNG
    env.print = function(...)
        local text = tostring(select(1, ...))
        if text:find("DRAW ERROR", 1, true) or text:find("词典加载失败", 1, true) then
            f.drawErrors[#f.drawErrors + 1] = text
            print(TAG .. " PRIVATE ERROR " .. text)
        end
    end
    local function loadPrivate(name)
        if f.mods[name] ~= nil then return f.mods[name] end
        local allowed = name:find("^config%.") or name:find("^core%.I18n") or name:find("^core%.i18n%.")
            or name == "core.NumberUtil" or name == "core.DrawUtil" or name == "core.BattleLayout"
            or name == "core.DarkIcon" or name == "systems.AttributeDef" or name == "ui.widget.RewardCascade"
            or name == "ui.widget.HeroFrame" or name == "ui.hud.popup.OfflineRewardPanel"
        assert(allowed, "专项未授权依赖 " .. tostring(name))
        local value = assert(load(sourceText(name), "@private/" .. name, "t", env))()
        f.mods[name] = value
        return value
    end
    env.require = loadPrivate
    local noop = function() end
    f.mods["systems.GameSFX"] = { play = function(key) f.sounds[#f.sounds + 1] = key end }
    f.mods["systems.ButtonFeedback"] = { begin = function() return false end,
        finish = noop, trigger = function() f.triggered = (f.triggered or 0) + 1 end }
    f.mods["ui.widget.ImageCache"] = { init = noop, getQualityBg = function() return -1 end,
        getEquipIcon = function() return -1 end }
    -- HeroFrame本体真实执行；只替身不参与本专项的配置属性/外部头像资源边界。
    f.mods["config.HeroConfig"] = { getQualityColorRGB = function() return 214, 181, 93 end,
        get = function() return { quality = 2 } end }
    f.mods["config.HeroAssetUtil"] = { ensureIcon = function() return -1 end }
    f.mods["ui.character.equip.EquipmentDetail"] = {
        readOnlySize = function() return 760, 480 end,
        drawReadOnly = function(_, item) f.detailDrawn = item end,
    }
    f.mods["runtime.ClientDispatcher"] = {
        get = function(key)
            assert(key == "player", "经验展示只允许读player，实际=" .. tostring(key))
            f.gets = f.gets + 1
            return f.player or nil
        end,
        set = function() f.writes = f.writes + 1; error("Panel禁止写dispatcher", 0) end,
        patch = function() f.writes = f.writes + 1; error("Panel禁止patch dispatcher", 0) end,
    }
    env.nvgCreateImage = function() f.images = f.images + 1; return -1 end
    env.nvgSave = function(vg)
        f.depth = f.depth + 1
        f.stack[f.depth] = { font = f.font, align = f.align, color = f.color, clip = f.clip }
        return native.save(vg)
    end
    env.nvgRestore = function(vg)
        local saved = assert(f.stack[f.depth], "NVG restore必须配对save") --[[@as any]]
        f.font, f.align, f.color, f.clip = saved.font, saved.align, saved.color, saved.clip
        f.stack[f.depth] = nil; f.depth = f.depth - 1
        return native.restore(vg)
    end
    env.nvgScissor = function(vg, x, y, w, h)
        f.clip = { x, y, x + w, y + h }
        f.clips[#f.clips + 1] = copy(f.clip)
        return native.scissor(vg, x, y, w, h)
    end
    env.nvgIntersectScissor = function(vg, x, y, w, h)
        local prior = f.clip or { x, y, x + w, y + h }
        f.clip = { math.max(x, prior[1]), math.max(y, prior[2]),
            math.min(x + w, prior[3]), math.min(y + h, prior[4]) }
        return native.intersect(vg, x, y, w, h)
    end
    env.nvgResetScissor = function(vg) f.clip = nil; return native.resetClip(vg) end
    env.nvgFontFace = function(vg, face) return native.face(vg, face) end
    env.nvgFontSize = function(vg, size) f.font = size; return native.size(vg, size) end
    env.nvgTextAlign = function(vg, align) f.align = align; return native.align(vg, align) end
    env.nvgRGBA = function(r, g, b, a)
        local color = native.rgba(r, g, b, a)
        f.colorArgs[color] = { r, g, b, a }
        return color
    end
    env.nvgFillColor = function(vg, color)
        f.color = f.colorArgs[color] or {}; return native.color(vg, color)
    end
    env.nvgTextBounds = function(vg, x, y, text, ...)
        suite.bounds = suite.bounds + 1
        return native.bounds(vg, x, y, text, ...)
    end
    env.nvgText = function(vg, x, y, text, endp)
        local bounds = {}
        local width = native.bounds(vg, x, y, text, endp, bounds)
        suite.bounds = suite.bounds + 1
        f.texts[#f.texts + 1] = { x = x, y = y, text = text, font = f.font,
            align = f.align, width = width, b = bounds, color = copy(f.color), clip = copy(f.clip) }
        return native.text(vg, x, y, text, endp)
    end
    local rawBeginPath = nvgBeginPath
    env.nvgBeginPath = function(vg) f.lastRect = nil; return rawBeginPath(vg) end
    env.nvgRoundedRect = function(vg, x, y, w, h, r)
        f.lastRect = { x = x, y = y, w = w, h = h, r = r, hero = f.drawingHero }
        return native.rounded(vg, x, y, w, h, r)
    end
    env.nvgFill = function(vg)
        if f.lastRect then
            f.fills[#f.fills + 1] = { rect = copy(f.lastRect), color = copy(f.color) }
        end
        return native.fill(vg)
    end
    f.env, f.load = env, loadPrivate
    f.exp = loadPrivate("config.ExpTable")
    local expProxy = setmetatable({}, { __index = f.exp })
    expProxy.simulateHeroExp = function(level, exp, gain)
        f.sims[#f.sims + 1] = { level = level, exp = exp, gain = gain }
        return f.exp.simulateHeroExp(level, exp, gain)
    end
    expProxy.autoLevelUpPlayer = function(player)
        f.playerSims[#f.playerSims + 1] = { object = player, before = copy(player) }
        return f.exp.autoLevelUpPlayer(player)
    end
    f.mods["config.ExpTable"] = expProxy
    f.i18n = loadPrivate("core.I18n")
    f.i18n.installDrawHook() -- 只修改私有ENV；原生观察器捕获最终译文，不换全局NVG。
    local draw = loadPrivate("core.DrawUtil")
    local actualText, actualRect = draw.drawTextStroke, draw.drawRoundedRectCentered
    draw.drawTextStroke = function(vg, x, y, text, font, align, ...)
        local rendered = f.i18n.lookup(text)
        native.save(vg); native.face(vg, "sans"); native.size(vg, font); native.align(vg, align)
        local bounds = {}; local width = native.bounds(vg, x, y, rendered, nil, bounds)
        native.restore(vg)
        f.strokeTexts[#f.strokeTexts + 1] = { text = rendered, x = x, y = y,
            font = font, align = align, width = width, b = bounds }
        return actualText(vg, x, y, text, font, align, ...)
    end
    draw.drawRoundedRectCentered = function(vg, cx, cy, w, h, ...)
        f.rows[#f.rows + 1] = { cx = cx, cy = cy, w = w, h = h }
        return actualRect(vg, cx, cy, w, h, ...)
    end
    local frame = loadPrivate("ui.widget.HeroFrame")
    local actualHero = frame.draw
    frame.draw = function(vg, opts)
        local call = copy(opts); call.rects = {}; f.heroes[#f.heroes + 1] = call
        f.drawingHero = opts.heroId
        local before = #f.fills
        actualHero(vg, opts)
        for index = before + 1, #f.fills do call.rects[#call.rects + 1] = f.fills[index] end
        f.drawingHero = nil
    end
    f.cascade = loadPrivate("ui.widget.RewardCascade")
    f.panel = loadPrivate("ui.hud.popup.OfflineRewardPanel")
    f.state = upvalue(f.panel.show, "state")
    assert(fontVG, "fixture必须先创建真实字体VG")
    f.panel.init(fontVG) -- 首次show/输入即使用与draw相同VG，图片仍为私有-1边界。
    return f
end

local function verify(ok, label)
    suite.checks = suite.checks + 1
    if not ok then suite.failed = suite.failed + 1; print(TAG .. " FAIL " .. label) end
end
local function equal(a, b, label)
    verify(a == b, label .. " 实际=" .. tostring(a) .. " 期望=" .. tostring(b))
end
local function scenario(name, fn)
    suite.cases = suite.cases + 1
    local before = suite.failed
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then verify(false, name .. " 异常 " .. tostring(err)) end
    print(TAG .. (before == suite.failed and " PASS " or " FAILED ") .. name)
end

local function show(f, data)
    f.clock.elapsedTime = 100
    f.panel.show(data)
end
local function advance(f, dt)
    f.clock.elapsedTime = f.clock.elapsedTime + dt
    f.panel.update(dt)
end
local function advanceTo(f, target, fps)
    local elapsed = 0
    local count = math.floor(target * fps)
    for _ = 1, count do advance(f, 1 / fps); elapsed = elapsed + 1 / fps end
    if target > elapsed then advance(f, target - elapsed) end
end
local function drawFrame(f)
    f.texts, f.strokeTexts, f.heroes, f.fills, f.rows, f.drawErrors = {}, {}, {}, {}, {}, {}
    f.lastRect, f.clips = nil, {}
    native.save(fontVG)
    f.panel.draw(fontVG)
    native.restore(fontVG)
    suite.frames = suite.frames + 1
    equal(#f.drawErrors, 0, "真实Panel.draw不吞绘制异常/词典失败")
    equal(f.depth, 0, "真实Panel/HeroFrame NVG save/restore配对")
    return { texts = f.texts, strokes = f.strokeTexts, heroes = f.heroes,
        fills = f.fills, rows = f.rows }
end
local function textsAt(frame, y, predicate)
    local found = {}
    for _, text in ipairs(frame.texts) do
        if math.abs(text.y - y) < .000001 and (not predicate or predicate(text)) then
            found[#found + 1] = text
        end
    end
    return found
end
local function heroBars(frame)
    local bars = {}
    for _, fill in ipairs(frame.fills) do
        if fill.rect.h == 12 and fill.rect.hero == nil then bars[#bars + 1] = fill end
    end
    return bars
end
local function heroPreview(exp, id, team, lv, rest, gain, finalCapped)
    local result = exp.simulateHeroExp(lv, rest, gain)
    return { heroId = id, teamIdx = team, quality = 2, startLevel = lv, startExp = rest,
        expGain = gain, level = result.level, exp = result.exp, maxExp = result.maxExp,
        capped = finalCapped == nil and result.capped or finalCapped }
end
-- 明确UI时间契约：只把累计dt的动画观察时间映射到最近微秒，不舍入每帧dt或实发经验。
-- 独立oracle的分子先浮点化，避免大经验×微秒溢出Lua signed integer。
local function issuedAtMicroseconds(total, elapsed, index)
    local clockTicks = math.floor(elapsed * 1000000 + .5)
    local activeTicks = math.max(0, math.min(5000000, clockTicks - 550000 - (index - 1) * 100000))
    return math.floor((total + 0.0) * activeTicks / 5000000.0)
end
local function assertHeroOracle(f, preview, elapsed, label)
    equal(#f.state.heroAnim, #preview, label .. "动画数量")
    for index, item in ipairs(preview) do
        local total = math.max(0, math.floor(item.expGain or 0))
        local issued = issuedAtMicroseconds(total, elapsed, index)
        local expected = f.exp.simulateHeroExp(item.startLevel or item.level or 1,
            item.startExp or 0, issued)
        local actual = f.state.heroAnim[index]
        equal(actual.level, expected.level, label .. "英雄" .. index .. "等级")
        equal(actual.exp, expected.exp, label .. "英雄" .. index .. "经验")
        equal(actual.capped == true, expected.capped, label .. "英雄" .. index .. "当前cap")
        equal(actual.remain, expected.capped and 0 or total - issued,
            label .. "英雄" .. index .. "剩余经验仅扣累计增量/cap清零")
    end
end
local function checkNoIO(f, label)
    equal(f.io, 0, label .. "File/FS原生委托零")
    equal(f.rng, 0, label .. "RNG零")
    equal(f.writes, 0, label .. "dispatcher写零")
end

local function animationTests()
    scenario("30/60/120fps同时间累计整数经验/多级严格等价", function()
        local snapshots = {}
        for _, target in ipairs({ .25, .75, 1.25, 2.25, 3.25, 5.95 }) do
            for _, fps in ipairs({ 30, 60, 120 }) do
                local f = newFixture()
                local preview = {
                    heroPreview(f.exp, 1, 1, 1, 3, 997),
                    heroPreview(f.exp, 2, 1, 2, 100, 1597),
                    heroPreview(f.exp, 3, 2, 3, 999, 2397),
                }
                show(f, { heroExpPreview = preview, rewards = { { type = "gold", amount = 10 } } })
                equal(#f.sims, #preview, "reset逐英雄调用真实simulateHeroExp")
                for _, call in ipairs(f.sims) do equal(call.gain, 0, "reset不给经验") end
                advanceTo(f, target, fps)
                assertHeroOracle(f, preview, target, fps .. "fps@" .. target)
                local snap = copy(f.state.heroAnim)
                -- issued是生产内置累计量，另校验重复dt=0完全不变且不再调用模拟器。
                local calls = #f.sims
                for _ = 1, 12 do f.panel.update(0) end
                verify(same(snap, f.state.heroAnim), "dt0不重复消费且所有动画字段不变")
                equal(#f.sims, calls, "dt0不重算经验")
                local key = tostring(target)
                if snapshots[key] then
                    verify(same(snap, snapshots[key]), "30/60/120fps同时间所有动画字段一致")
                else snapshots[key] = snap end
                if target == 5.95 then
                    verify(f.state.cascade:finished(), "经验5秒不延迟4.65秒原奖励完成")
                end
                checkNoIO(f, "fps")
            end
        end
    end)
    scenario("精确整数发放边界30/60/120fps无epsilon同时间等价", function()
        for _, target in ipairs({ .55, .65, .85, 1.05, 1.15, 1.55, 2.55, 5.55, 5.75 }) do
            local expected
            for _, fps in ipairs({ 30, 60, 120 }) do
                local f = newFixture()
                local preview = { heroPreview(f.exp, 1, 1, 1, 0, 100),
                    heroPreview(f.exp, 2, 1, 1, 0, 100), heroPreview(f.exp, 3, 1, 1, 0, 100) }
                show(f, { heroExpPreview = preview }); advanceTo(f, target, fps)
                local snap = copy(f.state.heroAnim)
                print(TAG .. " INTEGER BOUNDARY time=" .. target .. " fps=" .. fps
                    .. " heroTime=" .. string.format("%.17g", f.state.heroTime)
                    .. " issued=" .. snap[1].issued .. "/" .. snap[2].issued .. "/" .. snap[3].issued)
                assertHeroOracle(f, preview, target, fps .. "fps整数边界@" .. target)
                local exactFirst = { [.55] = 0, [.65] = 2, [.85] = 6, [1.05] = 10,
                    [1.15] = 12, [1.55] = 20, [2.55] = 40, [5.55] = 100, [5.75] = 100 }
                equal(snap[1].issued, exactFirst[target], "微秒契约精确整数边界硬期望@" .. target)
                if expected then verify(same(snap, expected), "精确边界同时间整数动画严格一致@" .. target)
                else expected = snap end
                checkNoIO(f, "精确边界")
            end
        end
    end)
    scenario("微秒边界前后2us与末帧精确补dt同输入等价", function()
        local boundaryFirst = { [.65] = 2, [.85] = 6, [1.15] = 12, [5.55] = 100 }
        for _, boundary in ipairs({ .65, .85, 1.15, 5.55 }) do
            for _, delta in ipairs({ -.000002, 0, .000002 }) do
                local target = boundary + delta
                local reference
                for _, fps in ipairs({ 30, 60, 120 }) do
                    local f = newFixture()
                    local preview = { heroPreview(f.exp, 1, 1, 1, 0, 100) }
                    show(f, { heroExpPreview = preview })
                    -- 最后dt从实际已累计值计算；相同binary64总时间并非数学求和假定。
                    local steps = math.max(0, math.ceil(target * fps) - 1)
                    for _ = 1, steps do advance(f, 1 / fps) end
                    local finalDt = target - f.state.heroTime
                    verify(finalDt > 0, "最后补dt保持正值，不用负dt纠正历史消费")
                    advance(f, finalDt)
                    equal(f.state.heroTime, target, "最后补dt后累计时间精确等于输入目标")
                    assertHeroOracle(f, preview, target, fps .. "fps/末dt/" .. target)
                    local first = boundaryFirst[boundary]
                    equal(f.state.heroAnim[1].issued, delta < 0 and first - 1 or first,
                        "微秒边界前2us不提前/后2us不额外多发")
                    local snap, calls = copy(f.state.heroAnim), #f.sims
                    for _ = 1, 5 do f.panel.update(0) end
                    verify(same(snap, f.state.heroAnim), "微秒边界dt0不改变已发量")
                    equal(#f.sims, calls, "微秒边界dt0不调用经验模拟")
                    if reference then verify(same(snap, reference), "同输入总时间三fps全部动画字段一致")
                    else reference = snap end
                    checkNoIO(f, "微秒边界")
                end
                local direct = newFixture()
                local preview = { heroPreview(direct.exp, 1, 1, 1, 0, 100) }
                show(direct, { heroExpPreview = preview }); advance(direct, target)
                assertHeroOracle(direct, preview, target, "单大dt/微秒边界")
                verify(same(direct.state.heroAnim, reference), "单大dt与三fps同时间全部动画字段一致")
            end
        end
    end)
    scenario("1整数经验第五秒边界与单大dt", function()
        local f = newFixture()
        local preview = { heroPreview(f.exp, 1, 1, 1, 0, 1) }
        show(f, { heroExpPreview = preview })
        advance(f, .55); assertHeroOracle(f, preview, .55, "delay边界")
        advance(f, 4.99)
        equal(f.state.heroAnim[1].exp, 0, "不足5秒不能提前发1点")
        equal(f.state.heroAnim[1].remain, 1, "不足5秒保留1点")
        advance(f, .02)
        equal(f.state.heroAnim[1].exp, 1, "超过5秒恰好发1点")
        equal(f.state.heroAnim[1].remain, 0, "1整数经验最终结束")
        local snapshot = copy(f.state.heroAnim); advance(f, 100)
        verify(same(snapshot, f.state.heroAnim), "结束后大dt不再发经验")
        show(f, { heroExpPreview = preview }); advance(f, 100)
        assertHeroOracle(f, preview, 100, "单大dt直达完整终值")
        checkNoIO(f, "整数/大dt")
    end)
    scenario("多级cap/current cap不借最终item.capped提前填满", function()
        local f = newFixture()
        local needed = f.exp.getHeroExpForLevel(199)
        local multi = f.exp.getHeroExpForLevel(198) + needed + 999
        local preview = {
            heroPreview(f.exp, 1, 1, 199, needed - 10, 100, true),
            heroPreview(f.exp, 2, 1, 198, 0, multi, true),
            heroPreview(f.exp, 3, 2, 200, 999, 100),
        }
        show(f, { heroExpPreview = preview })
        assertHeroOracle(f, preview, 0, "cap reset")
        equal(f.state.heroAnim[3].exp, 0, "已cap旧剩余由正式simulate清零")
        equal(f.state.heroAnim[3].remain, 0, "已cap立即清未发量")
        f.clock.elapsedTime = 101; f.panel.update(0)
        local frame = drawFrame(f)
        local bars = heroBars(frame)
        equal(#bars, 5, "199/198非cap各底条＋仅199有填充，200底条＋满条")
        local notFull = false
        for _, bar in ipairs(bars) do
            if bar.color[1] ~= 0 and bar.rect.y < 944 and bar.rect.w < 118 then notFull = true end
        end
        verify(notFull, "最终capped=true的199当前经验条仍非满")
        advance(f, 1.25); assertHeroOracle(f, preview, 1.25, "达到首英雄cap")
        equal(f.state.heroAnim[1].remain, 0, "当前达cap不残留90待发经验")
        advance(f, 100); assertHeroOracle(f, preview, 101.25, "多级大dt cap")
        local stable = copy(f.state.heroAnim); f.panel.update(0)
        verify(same(stable, f.state.heroAnim), "cap后dt0不动")
        checkNoIO(f, "多级cap")
    end)
    scenario("刷新重置/关闭重开/关闭期间不消费", function()
        local f = newFixture()
        local old = { heroPreview(f.exp, 1, 1, 1, 0, 997) }
        show(f, { heroExpPreview = old, rewards = { { type = "gold", amount = 10 } } })
        advance(f, 2.25); assertHeroOracle(f, old, 2.25, "刷新前")
        local rewardRef, reveal = f.state.rewards, f.state.cascade.revealStart
        local fresh = { heroPreview(f.exp, 2, 2, 2, 300, 1497) }
        local simCount = #f.sims
        f.panel.refreshHeroPreview(fresh)
        equal(#f.sims, simCount + 1, "刷新也用真实simulate reset")
        assertHeroOracle(f, fresh, 0, "刷新后清已发/时间/过级起点归一")
        equal(f.state.heroTime, 0, "刷新重置独立英雄时钟")
        verify(f.state.rewards == rewardRef and f.state.cascade.revealStart == reveal,
            "刷新不重置奖励或cascade100.55")
        advance(f, 1.25); assertHeroOracle(f, fresh, 1.25, "刷新后重发")
        f.panel.close(); local stable = copy(f.state.heroAnim)
        advance(f, .1); verify(same(stable, f.state.heroAnim), "关闭动画不继续发经验")
        advance(f, .2); verify(not f.panel.isOpen(), "关闭完成")
        advance(f, 100); verify(same(stable, f.state.heroAnim), "已关闭不发经验")
        show(f, { heroExpPreview = fresh }); assertHeroOracle(f, fresh, 0, "关闭重开重置")
        advance(f, 100); assertHeroOracle(f, fresh, 100, "重开终值")
        checkNoIO(f, "刷新/重开")
    end)
end

-- 独立真实字体oracle：不调用生产wrap/layout，也不从生产行高反推期望。
-- 常量来自设计契约；Unicode累计advance宽度贪心分段（不是UTF-8字节计数）。
local function sourceLabel(f, source)
    if source.sourceKind == "tower" then
        return f.i18n.format("通天塔 第%d层", (source.stageId or 400001) - 400000)
    end
    local entry = f.load("config.StageConfig").getStage(source.stageId)
    return f.i18n.lookup(source.sourceName or (entry and entry.name) or tostring(source.stageId))
end
local function fontLines(text)
    native.save(fontVG); native.face(fontVG, "sans"); native.size(fontVG, 56)
    native.align(fontVG, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local lines, paragraphs = {}, {}
    local start = 1
    for at in text:gmatch("()\n") do
        paragraphs[#paragraphs + 1] = text:sub(start, at - 1); start = at + 1
    end
    if start <= #text then paragraphs[#paragraphs + 1] = text:sub(start) end
    for _, paragraph in ipairs(paragraphs) do
        local chars, prefix = {}, { 0 }
        for _, point in utf8.codes(paragraph) do
            local char = utf8.char(point)
            chars[#chars + 1] = char
            local width = native.bounds(fontVG, 0, 0, char, nil)
            suite.bounds = suite.bounds + 1
            prefix[#chars + 1] = prefix[#chars] + width
        end
        if #chars == 0 then lines[#lines + 1] = "" end
        local first = 1
        while first <= #chars do
            local last = first
            while last < #chars and prefix[last + 2] - prefix[first] <= 416 do last = last + 1 end
            lines[#lines + 1] = table.concat(chars, "", first, last)
            first = last + 1
        end
    end
    native.restore(fontVG)
    return lines
end
local function layoutOracle(f, data)
    local preview, sources = data.heroExpPreview or {}, data.teamSources or {}
    local groups, src = { {}, {}, {} }, {}
    local explicit = false
    for _, item in ipairs(preview) do if item.teamIdx then explicit = true break end end
    for index, item in ipairs(preview) do
        local team = explicit and math.max(1, math.min(3, item.teamIdx or 1)) or math.ceil(index / 4)
        if team <= 3 and #groups[team] < 4 then groups[team][#groups[team] + 1] = item end
    end
    for index, source in ipairs(sources) do
        local team = source.teamIdx or index
        if not src[team] then src[team] = source end
    end
    local rows, blockH = {}, 0
    for team = 1, 3 do
        local members, source = groups[team], src[team]
        if #members > 0 or source then
            local name = source and sourceLabel(f, source) or ""
            local status = source and source.paused and f.i18n.lookup("暂停离线收益") or ""
            local lines, statuses = fontLines(name), fontLines(status)
            local h = math.min(420, math.max(#members > 0 and 220 or 100,
                100 + (#lines + #statuses) * 92))
            local sourceH = math.max(0, h - 100 - #statuses * 92)
            rows[#rows + 1] = { team = team, members = members, source = source, name = name,
                lines = lines, status = statuses, top = 710 + blockH, h = h, sourceH = sourceH,
                maxScroll = math.max(0, #lines * 92 - sourceH) }
            blockH = blockH + h + 14
        end
    end
    if #rows > 0 then blockH = blockH - 14 end
    local rewardTop = 710 + blockH + 24
    local rewardH = math.min(552, 2400 - 40 - rewardTop - 180)
    local gridRows = math.ceil(math.max(#(data.rewards or {}), 1) / 10)
    return { rows = rows, height = blockH, rewardTop = rewardTop, rewardH = rewardH,
        clipTop = rewardTop + 12, clipH = rewardH - 24, claimCY = rewardTop + rewardH + 80,
        scrollMax = math.max(0, gridRows * 120 + (gridRows - 1) * 12 - (rewardH - 24)) }
end
-- 仅用于核对缓存/scroll；任何期望均来自上方native字体oracle。
local function cachedLayout(f)
    return upvalue(upvalue(f.env.self_drawHeroExpList, "teamRows"), "teamLayout")
end
local function checkInk(text, left, top, right, bottom, label)
    verify(type(text.b[1]) == "number" and type(text.b[4]) == "number", label .. "真实字墨有效")
    verify(text.b[1] >= left and text.b[3] <= right, label .. "左右不越界 b="
        .. table.concat(text.b, ","))
    -- 不以scissor交集冒充字墨完整：TOP字体可能negative bearing，必须报告而非加epsilon。
    verify(text.b[2] >= top and text.b[4] <= bottom, label .. "上下字墨完整 b="
        .. table.concat(text.b, ",") .. " area=" .. top .. "," .. bottom)
end
local function verifySourceFrame(f, frame, expected, offset, label, seen)
    local x, textTop = -236, expected.top + 88
    local header = textsAt(frame, expected.top, function(t)
        return t.text == f.i18n.format("小队%d", expected.team)
    end)
    equal(#header, 1, label .. "独立队名")
    if header[1] then
        equal(header[1].font, 60, label .. "队名60号")
        checkInk(header[1], -260, expected.top, 220, expected.top + 88, label .. "队名字墨")
    end
    local visible = 0
    for index, line in ipairs(expected.lines) do
        local y = textTop + (index - 1) * 92 - offset
        if y + 92 > textTop and y < textTop + expected.sourceH then
            visible = visible + 1
            local found = textsAt(frame, y, function(t) return t.x == x and t.text == line end)
            equal(#found, 1, label .. "完整来源行" .. index)
            if found[1] then
                local text = found[1] --[[@as any]]
                equal(text.font, 56, label .. "来源56号不缩字")
                verify(math.abs(text.font * .45 * 1280 / 1920 - 16.8) < 1e-12,
                    label .. "1280稳定字号16.8px")
                verify(text.b[1] >= -240 and text.b[3] <= 192, label .. "来源左区宽度/不侵右头像")
                verify(text.clip and text.clip[1] == -240 and text.clip[2] == textTop
                    and text.clip[3] == 192 and text.clip[4] == textTop + expected.sourceH,
                    label .. "独立来源clip不含状态")
                if y >= textTop and y + 92 <= textTop + expected.sourceH then
                    checkInk(text, -240, textTop, 204, textTop + expected.sourceH, label .. "可整读来源行" .. index)
                end
                if seen and text.b[2] >= textTop and text.b[4] <= textTop + expected.sourceH then
                    seen[index] = line
                end
            end
        end
    end
    local drawn = 0
    for _, text in ipairs(frame.texts) do
        if text.font == 56 and text.color[1] == 232 and text.y >= textTop - 92
            and text.y < textTop + expected.sourceH then drawn = drawn + 1 end
    end
    equal(drawn, visible, label .. "可见来源无多画/漏画")
    for index, line in ipairs(expected.status) do
        local y = textTop + expected.sourceH + (index - 1) * 92
        local found = textsAt(frame, y, function(t) return t.x == x and t.text == line end)
        equal(#found, 1, label .. "暂停状态固定底部" .. index)
        if found[1] then
            equal(found[1].font, 56, label .. "状态56号")
            checkInk(found[1], -240, y, 204, expected.top + expected.h, label .. "状态字墨")
        end
    end
end
local function verifyLayout(f, data, label)
    local expected = layoutOracle(f, data)
    show(f, data)
    -- 首次draw前先让真实输入建缓存，不能使用无VG的56等宽退化布局。
    verify(f.panel.handleInput(-250, 700), label .. "首次输入消费且不领取")
    local cacheBefore = cachedLayout(f)
    verify(cacheBefore.context == fontVG, label .. "开前输入采用已init真实VG")
    f.clock.elapsedTime = 101; f.panel.update(0)
    local frame = drawFrame(f)
    verify(cachedLayout(f) == cacheBefore, label .. "input/draw复用同缓存")
    equal(cacheBefore.height, expected.height, label .. "独立字体并集高度")
    equal(#cacheBefore.rows, #expected.rows, label .. "队伍并集行数")
    local heroCount = 0
    for index, row in ipairs(expected.rows) do
        local cached = cacheBefore.rows[index]
        equal(cached.h, row.h, label .. "队" .. row.team .. "动态高度")
        verify(same(cached.lines, row.lines) and same(cached.status, row.status), label .. "独立Unicode换行")
        equal(cached.maxScroll, row.maxScroll, label .. "来源独立滚动上限")
        local matched = false
        for _, rect in ipairs(frame.rows) do
            if rect.w == 1600 and rect.h == row.h and rect.cy == row.top + row.h / 2 then matched = true end
        end
        verify(matched, label .. "真实行底跟随高度")
        verifySourceFrame(f, frame, row, 0, label .. "/队" .. row.team)
        for slot, item in ipairs(row.members) do
            heroCount = heroCount + 1
            local hero
            for _, call in ipairs(frame.heroes) do if call.heroId == item.heroId then hero = call break end end
            verify(hero ~= nil, label .. "真实HeroFrame英雄" .. item.heroId)
            if hero then
                equal(hero.size, 118, label .. "HeroFrame实际118")
                equal(hero.cx, 780 + (slot - (#row.members + 1) / 2) * 268, label .. "右栏center780/cell268")
                equal(hero.cy, row.top + (row.h - 220) / 2 + 80, label .. "头像随动态行居中")
                verify(hero.cx - 59 >= 220 and hero.cx + 59 <= 1340, label .. "右头像不侵左区")
                local rect = hero.rects[1] and hero.rects[1].rect
                verify(rect and rect.w == 118 and rect.h == 118, label .. "真实头像路径118×118")
                local base
                for _, bar in ipairs(heroBars(frame)) do
                    if bar.color[1] == 0 and bar.rect.x == hero.cx - 59 and bar.rect.y == hero.cy + 65 then base = bar end
                end
                verify(base ~= nil, label .. "真实NVG经验底条存在")
                if base then equal(base.rect.w, 118, label .. "经验条宽等于118头像") end
            end
        end
    end
    equal(#frame.heroes, heroCount, label .. "不伪造source-only英雄")
    local claim = textsAt(frame, expected.claimCY, function(text) return text.text == f.i18n.lookup("领取") end)
    equal(#claim, 1, label .. "动态奖励/领取共布局")
    verify(expected.claimCY + 100 <= 2360, label .. "面板底保留40设计单位")
    local reward = false
    for _, rect in ipairs(frame.rows) do
        if rect.w == 1600 and rect.h == expected.rewardH
            and rect.cy == expected.rewardTop + expected.rewardH / 2 then reward = true end
    end
    verify(reward, label .. "奖励H=min552,设计剩余空间")
    equal(f.state.scrollMax, expected.scrollMax, label .. "动态奖励scrollMax")
    local attempts = 0
    f.state.onClaim = function() attempts = attempts + 1; return attempts > 1 end
    verify(f.panel.handleInput(540, expected.claimCY - 70), label .. "按钮外消费")
    equal(attempts, 0, label .. "按钮外不领取")
    verify(f.panel.handleInput(540, expected.claimCY), label .. "动态领取热区")
    equal(attempts, 1, label .. "失败回执保留")
    verify(f.panel.isOpen(), label .. "失败不关闭")
    verify(f.panel.handleInput(540, expected.claimCY), label .. "真实失败后重试")
    equal(attempts, 2, label .. "第二次成功")
    advance(f, .25); verify(not f.panel.isOpen(), label .. "领取关闭")
    checkNoIO(f, label)
    return frame
end
local function layoutTests()
    scenario("新版左栏五语1至4人/12人/来源并集和名称回退", function()
        local f = newFixture()
        local dataCases = {
            { label = "三队乱序", heroExpPreview = {
                heroPreview(f.exp, 3, 3, 3, 1, 100), heroPreview(f.exp, 1, 1, 1, 1, 100),
                heroPreview(f.exp, 2, 2, 2, 1, 100) }, teamSources = {
                { teamIdx = 3, stageId = 701 }, { teamIdx = 1, stageId = 101 },
                { teamIdx = 2, stageId = 400077, sourceKind = "tower", paused = true } } },
            { label = "team2-only", heroExpPreview = { heroPreview(f.exp, 2, 2, 2, 1, 100) },
                teamSources = { { teamIdx = 2, stageId = 2305 } } },
            { label = "塔零preview", teamSources = { { teamIdx = 3, stageId = 400120,
                sourceKind = "tower", sourceName = "不能覆盖塔层", paused = true } } },
            { label = "来源队1＋英雄队2", heroExpPreview = { heroPreview(f.exp, 2, 2, 2, 1, 100) },
                teamSources = { { teamIdx = 1, stageId = 400055, sourceKind = "tower", paused = true } } },
            { label = "三source-only", teamSources = { { teamIdx = 3, stageId = 2305 },
                { teamIdx = 1, stageId = 101 }, { teamIdx = 2, stageId = 400001, sourceKind = "tower", paused = true } } },
            { label = "旧无team无来源", heroExpPreview = {
                heroPreview(f.exp, 1, nil, 1, 1, 100), heroPreview(f.exp, 2, nil, 2, 1, 100),
                heroPreview(f.exp, 3, nil, 3, 1, 100), heroPreview(f.exp, 4, nil, 4, 1, 100),
                heroPreview(f.exp, 5, nil, 5, 1, 100) } },
            { label = "旧来源数组队号", teamSources = { { stageId = 101 }, { stageId = 301 } } },
            { label = "完全空旧预览" },
            { label = "未知kind保名称", teamSources = { { stageId = -999, sourceKind = "future", sourceName = "自定来源" } } },
            { label = "未知关回退ID", teamSources = { { stageId = -999 } } },
            { label = "缺关回退nil", teamSources = { {} } },
            { label = "空名称source-only最小100", teamSources = { { stageId = 101, sourceName = "" } } },
            { label = "三长来源奖励区压缩", teamSources = {
                { stageId = 101, sourceName = string.rep("长来源 Long Source ", 6), paused = true },
                { stageId = 301, sourceName = string.rep("悬魂瀑布 Écho ", 6), paused = true },
                { stageId = 701, sourceName = string.rep("終焉への道 한글 ", 6), paused = true } } },
            { label = "换行Unicode", teamSources = { { stageId = 101,
                sourceName = "悬魂瀑布\nÁg Écho 한글\n終焉への道", paused = true } } },
        }
        for count = 1, 4 do
            local data = { label = count .. "人", heroExpPreview = {}, teamSources = { { stageId = 101 } } }
            for id = 1, count do data.heroExpPreview[id] = heroPreview(f.exp, id, 1, id, 1, 100) end
            dataCases[#dataCases + 1] = data
        end
        for _, legacy in ipairs({ false, true }) do
            local data = { label = legacy and "旧12人" or "12人", heroExpPreview = {}, teamSources = {
                { stageId = 101 }, { stageId = 2305 }, { stageId = 400120, sourceKind = "tower", paused = true } } }
            for id = 1, 12 do data.heroExpPreview[id] = heroPreview(f.exp, id,
                legacy and nil or math.ceil(id / 4), 1, 1, 100) end
            -- Lua and/or不能生成nil，显式清理旧格式，防测试悄悄仍走新格式。
            if legacy then for _, item in ipairs(data.heroExpPreview) do item.teamIdx = nil end end
            dataCases[#dataCases + 1] = data
        end
        for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            verify(f.i18n.set(lang), "真实I18n切语言")
            for _, data in ipairs(dataCases) do verifyLayout(f, data, lang .. "/" .. data.label) end
        end
    end)
    scenario("长来源五语完整可滚动拼接/状态固定/奖励滚动隔离", function()
        for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            local f = newFixture(); f.i18n.set(lang)
            local data = { heroExpPreview = { heroPreview(f.exp, 1, 1, 1, 1, 100) },
                teamSources = { { stageId = 101, sourceName = string.rep("悬魂瀑布 Long Écho 한글 ", 8), paused = true } },
                rewards = { { type = "gold", amount = 10 } } }
            local expected = layoutOracle(f, data); local row = expected.rows[1]
            show(f, data); f.clock.elapsedTime = 101; f.panel.update(0)
            equal(row.h, 420, "长来源上限420")
            verify(row.maxScroll > 0 and row.sourceH >= 92, "长名称有整行可读滚动区")
            local seen, offset = {}, 0
            -- 1/4行步长也覆盖中途可整读位置，不能只在行顶对齐时采样误判其余行不可读。
            for step = 0, math.ceil(row.maxScroll / 23) do
                if step > 0 then f.panel.handleScroll(-.25, -100, row.top + 89); offset = math.min(row.maxScroll, step * 23) end
                local frame = drawFrame(f)
                verifySourceFrame(f, frame, row, offset, lang .. "/长来源/" .. step, seen)
                equal(cachedLayout(f).rows[1].scroll, offset, "来源滚轮独立92步进/clamp")
                equal(f.state.scrollY, 0, "来源滚轮不移动奖励")
            end
            for index, line in ipairs(row.lines) do equal(seen[index], line, lang .. "每行真实字墨曾完整可读" .. index) end
            local joined = {}; for index = 1, #row.lines do joined[index] = seen[index] or "<未完整显示>" end
            equal(table.concat(joined), row.name, lang .. "滚动拼接全文无省略/截字")
            f.panel.handleDragBegin(-100, row.top + 90)
            f.panel.handleDragMove(-100, row.top + 90 + row.maxScroll + 100)
            f.panel.handleDragEnd(-100, row.top + 90)
            equal(cachedLayout(f).rows[1].scroll, 0, "来源拖动到顶clamp")
            f.panel.handleDragBegin(-100, row.top + 90)
            f.panel.handleDragMove(-100, row.top + 90 - 35)
            f.panel.handleDragEnd(-100, row.top + 55)
            equal(cachedLayout(f).rows[1].scroll, math.min(35, row.maxScroll), "来源拖动真实35")
            equal(f.state.scrollY, 0, "来源拖动奖励不动")
            checkNoIO(f, "长来源")
        end
    end)
    scenario("短来源整个左信息行吞滚轮拖动不落奖励", function()
        local f = newFixture()
        local data = { teamSources = { { stageId = 101, sourceName = "A" } }, rewards = {} }
        for id = 1, 80 do data.rewards[id] = { type = "gold", amount = id } end
        local expected = layoutOracle(f, data); local row = expected.rows[1]
        show(f, data); f.clock.elapsedTime = 110; f.panel.update(0)
        f.panel.handleInput(-250, 700)
        equal(row.maxScroll, 0, "短来源确实无需来源滚动")
        for _, y in ipairs({ row.top, row.top + 40, row.top + 89, row.top + row.h - 1 }) do
            local scroll, follow = f.state.scrollY, f.state.followScroll
            f.panel.handleScroll(-1, -100, y)
            equal(f.state.scrollY, scroll, "左短行滚轮不能落奖励 y=" .. y)
            equal(f.state.followScroll, follow, "左短行滚轮不取消奖励自动跟随")
            f.panel.handleDragBegin(-100, y)
            f.panel.handleDragMove(-100, y - 50)
            f.panel.handleDragEnd(-100, y - 50)
            equal(f.state.scrollY, scroll, "左短行拖动不能落奖励 y=" .. y)
            equal(f.state.followScroll, follow, "左短行拖动不取消奖励自动跟随")
            equal(cachedLayout(f).rows[1].scroll, 0, "短来源滚动保持0")
        end
        checkNoIO(f, "短来源输入隔离")
    end)
    scenario("切语言/refresh首draw前动态奖励命中拖动滚轮及领取重试", function()
        local f = newFixture()
        local data = { heroExpPreview = { heroPreview(f.exp, 1, 1, 1, 1, 100) },
            teamSources = { { stageId = 400120, sourceKind = "tower", paused = true } }, rewards = {} }
        for id = 1, 80 do data.rewards[id] = { type = "gold", amount = id } end
        local attempts = 0
        data.onClaim = function() attempts = attempts + 1; return attempts > 1 end
        show(f, data); advance(f, 10)
        local prior = false
        for _, lang in ipairs({ "zh_CN", "en", "ja", "ko", "zh_TW" }) do
            local oldCache = prior
            f.i18n.set(lang)
            local languageLayout = layoutOracle(f, data)
            f.panel.handleInput(-250, 700) -- 只切语言，不借refresh清缓存掩盖失效问题。
            local languageCache = cachedLayout(f)
            equal(languageCache.language, lang, "仅切语言首次输入重建布局")
            equal(languageCache.height, languageLayout.height, "仅切语言独立字体高度")
            if oldCache then verify(languageCache ~= oldCache, "仅语言变化使旧缓存失效") end
            local fresh = { heroPreview(f.exp, 1, 1, 1, 1, 100) }
            if lang ~= "zh_CN" then fresh[2] = heroPreview(f.exp, 2, 2, 1, 1, 100) end
            local rewards, reveal = f.state.rewards, f.state.cascade.revealStart
            f.panel.refreshHeroPreview(fresh); data.heroExpPreview = fresh
            verify(f.state.rewards == rewards and f.state.cascade.revealStart == reveal, "refresh保奖励/cascade身份")
            local expected = layoutOracle(f, data)
            f.panel.handleScroll(10000, 500, expected.clipTop + 1)
            equal(f.state.scrollY, 0, "切语言/refresh开前滚轮新clip归顶")
            equal(f.state.scrollMax, expected.scrollMax, "动态新奖励scrollMax")
            local cache = cachedLayout(f)
            verify(cache.context == fontVG and cache.language == lang, "切语言首次输入缓存真实字体")
            if prior then verify(cache ~= prior, "切语言/refresh废弃旧缓存") end
            prior = cache
            -- 十列中心独立计算：总宽1344居中540，首列-72，步长136。
            verify(f.panel.handleInput(-72, expected.clipTop - 1), "clip外消费")
            equal(f.state.detailIdx, 0, "动态clip上方不能开详情")
            verify(f.panel.handleInput(-72, expected.clipTop + 60), "首次draw前新奖励中心命中")
            equal(f.state.detailIdx, 1, "独立网格第一项")
            verify(f.state.detailItem == rewards[1], "详情为真实奖励对象")
            f.panel.handleInput(540, expected.claimCY)
            equal(attempts, 0, "有详情先关闭不穿透领取")
            equal(f.state.detailIdx, 0, "详情关闭")
            f.panel.handleScroll(-1, 500, expected.clipTop + 60)
            equal(f.state.scrollY, math.min(60, expected.scrollMax), "奖励滚轮60独立步进")
            f.panel.handleDragBegin(500, expected.clipTop + 60)
            f.panel.handleDragMove(500, expected.clipTop + 10)
            f.panel.handleDragEnd(500, expected.clipTop + 10)
            equal(f.state.scrollY, math.min(110, expected.scrollMax), "动态clip奖励拖动50")
            local frame = drawFrame(f)
            verify(cachedLayout(f) == cache, "动态input/draw共缓存")
            local clipFound = false
            for _, clip in ipairs(f.clips) do
                if same(clip, { -248, expected.clipTop, 1328, expected.clipTop + expected.clipH }) then clipFound = true end
            end
            verify(clipFound, "真实NVG奖励clip跟随动态高度")
            equal(#textsAt(frame, expected.claimCY, function(t) return t.text == f.i18n.lookup("领取") end), 1,
                "动态领取文字和热区同坐标")
        end
        local expected = layoutOracle(f, data)
        f.panel.handleInput(540, expected.claimCY); equal(attempts, 1, "动态领取失败")
        verify(f.panel.isOpen(), "失败保留")
        f.panel.handleInput(540, expected.claimCY); equal(attempts, 2, "动态领取重试成功")
        advance(f, .25); verify(not f.panel.isOpen(), "成功关闭")
        verify(not f.panel.handleInput(540, expected.claimCY), "关闭不消费")
        checkNoIO(f, "动态输入")
    end)
    -- 原不收敛目的保留：新固定56号逐码点换行也必须有界，不能只删除旧缩号case。
    scenario("来源测量退化/异常有界终止不进入缩号死循环", function()
        for _, mode in ipairs({ "constant", "zero", "nan", "throw" }) do
            local f, calls = newFixture(), 0
            local text = string.rep("悬魂瀑布 Long ", 8)
            local original = f.i18n.displayBounds
            f.i18n.displayBounds = function(vg, x, y, value, _endp, out)
                -- 只注入逐码点来源测量，不能把NaN传到无关经验行的字号/原生绘制。
                if utf8.len(value) ~= 1 then return original(vg, x, y, value, _endp, out) end
                calls = calls + 1
                if calls > utf8.len(text) + 100 then error("测量调用无界", 0) end
                if mode == "throw" then error("private native measurement failure", 0) end
                if type(out) == "table" then out[1], out[2], out[3], out[4] = x - 600, y - 400, x + 600, y + 400 end
                if mode == "zero" then return 0 elseif mode == "nan" then return 0 / 0 end
                return 1200
            end
            local done, err = pcall(function()
                show(f, { heroExpPreview = { heroPreview(f.exp, 1, 1, 1, 1, 100) },
                    teamSources = { { stageId = 101, sourceName = text } } })
                f.clock.elapsedTime = 101; f.panel.update(0)
                -- draw以生产pcall日志明确异常，不将其误称正常绘制成功。
                if mode == "throw" then f.panel.handleInput(0, 0) else drawFrame(f) end
            end)
            f.i18n.displayBounds = original
            verify(calls > 0 and calls <= utf8.len(text) + 100, mode .. "测量有限调用")
            if mode == "throw" then
                verify(not done and tostring(err):find("private native measurement failure", 1, true) ~= nil,
                    "测量抛异常有限返回且不伪造成功")
            else verify(done, mode .. "失真测量有界终止") end
            checkNoIO(f, "测量异常")
        end
    end)
end

local function playerTests()
    scenario("远征正式经验不升级/阈值/跨级/199cap/200/no player冻结与副作用零", function()
        local f = newFixture()
        local cases = {
            { player = { level = 1, exp = 5, maxExp = 100 }, gain = 1.99 },
            { player = { level = 1, exp = 98, maxExp = 100 }, gain = 1.99 },
            { player = { level = 1, exp = 99, maxExp = 100 }, gain = 1.99 },
            { player = { level = 1, exp = 0, maxExp = 100 }, gain = 100 + 1131 + 4676 + 21.99 },
            { player = { level = 199, exp = f.exp.getPlayerExpForLevel(199) - 1 }, gain = 50.99 },
            { player = { level = 200, exp = 999, maxExp = 100 }, gain = 999999.99 },
            { player = false, gain = 125 },
        }
        for index, case in ipairs(cases) do
            f.player = copy(case.player)
            local original = copy(f.player)
            local expected = ""
            if f.player then
                local simulation = { level = f.player.level, exp = f.player.exp + math.floor(case.gain) }
                f.exp.autoLevelUpPlayer(simulation)
                expected = "Lv." .. f.player.level .. " → Lv." .. simulation.level
            end
            local beforeCalls = #f.playerSims
            show(f, { adventureExp = case.gain })
            verify(same(f.player, original), "show玩家原表不改 case" .. index)
            equal(#f.playerSims - beforeCalls, f.player and 1 or 0, "show仅一次正式autoLevelUpPlayer/no player不假造")
            if f.player then
                local call = f.playerSims[#f.playerSims] --[[@as any]]
                verify(call.object ~= f.player, "autoLevelUpPlayer只收到临时copy")
                equal(call.before.level, original.level, "临时level来自dispatcher")
                equal(call.before.exp, original.exp + math.floor(case.gain), "临时exp加floor收益")
            end
            f.clock.elapsedTime = 101; f.panel.update(0)
            local savedCalls, savedGets = #f.playerSims, f.gets
            local heroTime = f.state.heroTime
            -- 原对象值修改＋完全替换dispatcher，打开后的级数仍冻结。
            if f.player then f.player.level, f.player.exp = 88, 765 end
            f.player = { level = 199, exp = f.exp.getPlayerExpForLevel(199) - 1 }
            local changed = copy(f.player)
            local observedLabel
            for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
                verify(f.i18n.set(lang), "打开后仅切真实显示语言")
                for repeatDraw = 1, 2 do
                    local frame = drawFrame(f)
                    local rowTexts = textsAt(frame, 468)
                    local levelText
                    for _, text in ipairs(rowTexts) do
                        if text.text:find("^Lv%.") then levelText = text end
                    end
                    if expected == "" then verify(levelText == nil, "no player不能假造等级")
                    else
                        verify(levelText ~= nil, "远征经验行有冻结完整区间")
                        if levelText then equal(levelText.text, expected, "切语言/draw后dispatcher变化级数冻结") end
                    end
                    local labelText = f.i18n.lookup("远征等级经验")
                    local label
                    for _, text in ipairs(rowTexts) do if text.text == labelText then label = text break end end
                    verify(label ~= nil, "最终五语远征标签全文")
                    if observedLabel and lang ~= "zh_CN" then verify(labelText ~= "远征等级经验", "非简体采用正式译文") end
                    observedLabel = labelText
                    local reward
                    for _, text in ipairs(frame.strokes) do
                        if text.y == 468 then reward = text break end
                    end
                    verify(reward ~= nil, "经验奖励值真实DrawUtil出口")
                    if label and reward then
                        if levelText then
                            verify(label.b[3] + 1 <= levelText.b[1] and levelText.b[3] + 1 <= reward.b[1],
                                "最终译文标签/等级区间/奖励值真实字墨无重叠 " .. lang)
                        else verify(label.b[3] + 1 <= reward.b[1], "no player标签/奖励不重叠") end
                        verify(label.b[1] >= -200 - .05 and reward.b[3] <= 1280 + .05,
                            "经验行最终Noto字墨在内边距")
                    end
                end
            end
            equal(#f.playerSims, savedCalls, "每帧draw不重新模拟远征等级")
            equal(f.gets, savedGets, "每帧draw不重新读dispatcher估等级")
            equal(f.state.heroTime, heroTime, "draw不推进英雄经验动画")
            verify(same(f.player, changed), "draw/切语言不写替换后的dispatcher")
            checkNoIO(f, "远征case" .. index)
        end
    end)
end

local function cascadeTests()
    rootFixture = newFixture()
    local Cascade = rootFixture.cascade
    local Panel = rootFixture.panel
    local SFX = rootFixture.mods["systems.GameSFX"]
    local originalNew, originalPlay = Cascade.new, SFX.play
    local clock = rootFixture.clock
    local assertions = 0
    local sounds = {}
    ---@type any
    local captured = {}

    local function check(condition, label)
        assertions = assertions + 1
        assert(condition, label)
    end
    local function near(actual, expected, label)
        check(math.abs(actual - expected) < 0.0000001,
            label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
    end
    local function referenceStart(timeline, idx)
        local result = 0
        for i = 2, idx do result = result + timeline:gap(i) end
        return result
    end
    local function referenceShown(timeline, elapsed)
        if elapsed < 0 then return 0 end
        local shown = 0
        for i = 1, timeline.count do
            if elapsed + 0.0001 < referenceStart(timeline, i) then break end
            shown = i
        end
        return shown
    end

    local ok, err = pcall(function()
        -- 默认首通、离线三段、缺省最快间隔、零间隔与反向阈值均保持原来 gap 语义。
        local options = {
            {},
            { interval = 0.14, intervalTail = 0.10, fastAfter = 10,
                intervalFaster = 0.05, fasterAfter = 20 },
            { interval = 0.14, intervalTail = 0.06, fastAfter = 10,
                intervalFaster = 0.002, fasterAfter = 20 },
            { interval = 0, intervalTail = 0, fastAfter = 3 },
            { fastAfter = 8, fasterAfter = 3, intervalFaster = 0.03 },
            { fastAfter = 0, fasterAfter = 0, intervalFaster = 0.01 },
            { fastAfter = 10.5, fasterAfter = 20.5 },
        }
        for _, opts in ipairs(options) do
            local timeline = originalNew(100, opts)
            for i = 1, 100 do
                near(timeline:startAt(i), referenceStart(timeline, i), "区段求和与逐项累计一致")
            end
            for _, elapsed in ipairs({ -0.01, 0, 0.1198, 0.12, 0.84, 1.26, 1.86, 3, 30 }) do
                check(timeline:shownCount(elapsed) == referenceShown(timeline, elapsed),
                    "二分已显示数量与旧算法一致")
            end
            for _, i in ipairs({ 2, 8, 9, 10, 11, 20, 21, 99, 100 }) do
                local at = referenceStart(timeline, i)
                for _, delta in ipairs({ -0.0002, -0.00005, 0, 0.00005 }) do
                    check(timeline:shownCount(at + delta) == referenceShown(timeline, at + delta),
                        "区段边界与浮点容差不变")
                end
            end
        end
        local default = originalNew(200)
        near(default:startAt(200) + default.popDur + default.lead, 20.36, "普通首通200项节奏不变")
        local empty = originalNew(0)
        check(empty:finished() and empty:shownCount(100) == 0, "空奖励直接完成")
        local single = originalNew(1)
        single:start(clock.elapsedTime)
        check(single:t(1) == nil, "首件保留停顿")
        clock.elapsedTime = single.revealStart
        near(single:t(1), 0, "出场边界进度为0")
        clock.elapsedTime = single.revealStart + single.popDur + 0.000001
        check(single:finished(), "最后动画落地才完成")
        single:start(clock.elapsedTime, true)
        near(single:elapsed(), 0, "跳过首件停顿")
        single:skipToEnd()
        near(single:t(1), 1, "跳过动画推进到落地边界")
        check(single:shownCount() == 1, "跳过动画不漏显示首件")
        clock.elapsedTime = clock.elapsedTime + 0.000001
        check(single:finished(), "跳过后的浮点边界正常完成")

        -- 捕获真实 Panel.show 创建的时间轴，避免只验证手抄参数。
        Cascade.new = function(count, opts)
            captured = originalNew(count, opts)
            return captured
        end
        SFX.play = function(key) sounds[#sounds + 1] = key end
        local source = {}
        local function showCount(count, withHeroes)
            clock.elapsedTime = 100
            sounds = {}
            source = {}
            if count > 0 then source[1] = { type = "gold", amount = 100 } end
            for i = 2, count do
                source[i] = { type = "equip", templateId = "W1", quality = 1, level = i }
            end
            Panel.show({
                offlineSeconds = 86400,
                rewards = source,
                heroExpPreview = withHeroes and {
                    { heroId = 1, startLevel = 1, startExp = 0, expGain = 100 },
                } or {},
            })
            check(captured.count == count and #source == count, "奖励条目数量未改变")
            if count > 0 then near(captured.revealStart, 100.55, "首件与队员动画同起点") end
            return captured
        end
        for _, count in ipairs({ 0, 1, 10, 11, 20, 21, 100, 120, 121, 200, 1000, 10000 }) do
            local timeline = showCount(count, false)
            local lastStart = timeline:startAt(count)
            if count > 0 then
                check(lastStart + timeline.lead + timeline.popDur <= 4.6500001,
                    "任意大队列约4.65秒全部落地")
                for i = 2, math.min(count, 10) do near(timeline:gap(i), 0.14, "前10项节奏不变") end
                if count > 10 then near(timeline:gap(11), 0.06, "第11项开始加速") end
                if count > 20 then
                    check(timeline:gap(21) <= 0.02, "第21项起间隔不超过20毫秒")
                    check(lastStart - timeline:startAt(20) <= 2.0000001, "尾段排队不超过2秒")
                end
            end
        end
        local hundred = showCount(100, false)
        near(hundred:startAt(100) + hundred.lead + hundred.popDur, 4.25, "100项由7.05秒降至4.25秒")
        local large = showCount(200, false)
        near(large:startAt(200) + large.lead + large.popDur, 4.65, "200项由12.05秒降至4.65秒")
        local withHeroes = showCount(200, true)
        near(withHeroes:startAt(200), large:startAt(200), "队员经验预览不阻塞装备动画")

        -- 大帧跳跃到尾部：一帧最多一个入场音；未新增奖励时不能重播。
        local soundTimeline = showCount(200, false)
        Panel.update(1 / 60)
        check(#sounds == 0, "停顿期间不播放入场音")
        clock.elapsedTime = soundTimeline.revealStart + 0.001
        Panel.update(1 / 60)
        check(#sounds == 1 and sounds[1] == "ui_click_3", "资源首件播放资源音")
        clock.elapsedTime = soundTimeline.revealStart + soundTimeline:startAt(2) + 0.001
        Panel.update(1 / 60)
        check(#sounds == 2 and sounds[2] == "install", "装备入场播放安装音")
        clock.elapsedTime = soundTimeline.revealStart + soundTimeline:startAt(200) + 0.3
        Panel.update(1 / 60)
        check(#sounds == 3, "同帧批量出场只补一次音效")
        Panel.update(1 / 60)
        check(#sounds == 3, "同一批奖励不会重复播放音效")
        check(soundTimeline:shownCount() == 200 and soundTimeline:finished(), "音效合并不漏显示奖励")
        check(source[1].type == "gold" and source[2].level == 2 and source[200].level == 200,
            "奖励源数组顺序与内容不变")

        -- 不等待动画即可领取；失败保留、再次成功后关闭动画正常结束。
        clock.elapsedTime = 200
        local attempts = 0
        Panel.show({ rewards = source, onClaim = function()
            attempts = attempts + 1
            return attempts > 1
        end })
        check(captured:t(200) == nil, "提前领取时末件尚未出场")
        check(Panel.claim() and Panel.isOpen() and attempts == 1, "领取失败保留弹窗")
        check(Panel.claim() and attempts == 2, "提前领取可重试成功")
        clock.elapsedTime = 201
        Panel.update(1 / 60)
        check(not Panel.isOpen(), "领取后的关闭动画正常结束")
        check(not Panel.claim() and attempts == 2, "关闭后不能再次领取")
    end)

    Cascade.new, SFX.play = originalNew, originalPlay
    if not ok then error("[offline_reward_cascade_test] " .. tostring(err)) end
    suite.checks = suite.checks + assertions
    print("[offline_reward_cascade_test] 原cascade全部保留: " .. assertions .. " assertions")
    checkNoIO(rootFixture, "原cascade")
    SubscribeToEvent(fontVG, "NanoVGRender", "HandleOfflineCascadeRender")
end

function Start()
    fontVG = assert(nvgCreate(1), "真实字体专项VG创建失败")
    verify(nvgCreateFont(fontVG, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0,
        "仅注册一次真实宿主sans Noto字体")
    local ok, err = xpcall(cascadeTests, debug.traceback)
    if not ok then
        verify(false, "Start专项异常 " .. tostring(err))
        finished = true
        print(TAG .. " FAILED Start")
        engine:Exit()
    end
end

function HandleOfflineCascadeRender()
    if finished or not fontVG then return end
    nvgBeginFrame(fontVG, 2200, 2400, 1)
    local ok, err = xpcall(function()
        animationTests()
        layoutTests()
        playerTests()
        equal(suite.io, 0, "全部测试File/FS访问零")
        equal(suite.rng, 0, "全部测试RNG零")
        verify(_G.nvgText == native.text and _G.nvgTextBounds == native.bounds
            and _G.nvgRGBA == native.rgba, "私有观察器未污染全局NVG")
    end, debug.traceback)
    nvgEndFrame(fontVG)
    if not ok then verify(false, "Render专项异常 " .. tostring(err)) end
    finished = true
    print(TAG .. (suite.failed == 0 and " ALL PASS" or " FAILED") .. ": " .. suite.checks
        .. " assertions, cases=" .. suite.cases .. ", draws=" .. suite.frames .. ", nativeBounds="
        .. suite.bounds .. ", FileFS=" .. suite.io .. ", RNG=" .. suite.rng .. ", failures=" .. suite.failed)
    engine:Exit()
end

function Stop()
    if fontVG then nvgDelete(fontVG); fontVG = nil end
end
