-- Runtime 闭包回归：只读取声明的生产源码，不启动主入口或玩家存档。
-- NanoVG 语义 spy 不冒充截图，真实像素由 story_motion_preview 提供。
local TAG = "[story_motion_test]"
local nativeCache = cache
local checks, groups, failures = 0, 0, 0
local sourceCache = {} ---@type table<string, string>
local function source(name)
    if sourceCache[name] then return sourceCache[name] end
    local path = name:gsub("%.", "/") .. ".lua"
    local file = assert(nativeCache:GetFile(path), path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    sourceCache[name] = table.concat(lines, "\n")
    return sourceCache[name]
end
local function check(value, label)
    checks = checks + 1
    assert(value, label)
end
local function eq(a, b, label) check(a == b, label .. " actual=" .. tostring(a) .. " expected=" .. tostring(b)) end
local function near(a, b, label) check(math.abs(a - b) < 0.000001, label) end
local function copy(t)
    if type(t) ~= "table" then return t end
    local r = {}; for k, v in pairs(t) do r[k] = copy(v) end; return r
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function up(fn, name)
    for i = 1, 100 do
        local key, value = debug.getupvalue(fn, i)
        if not key then break end
        if key == name then return value end
    end
    error("missing actual upvalue " .. name)
end
local function fixture()
    local f = { calls = {}, loads = {}, handles = {}, modules = {}, events = {}, language = "zh_CN",
        random = 0, io = 0, callbacks = 0, failed = {}, font = 20, stack = {}, tx = 0, ty = 0,
        vg = {}, next = 0 } ---@type any
    local env = setmetatable({}, { __index = _G }) ---@type any
    f.env = env
    local function noop() end
    local function blocked()
        f.io = f.io + 1
        error("player IO forbidden")
    end
    env.File = blocked
    env.cache = { GetFile = blocked, GetResource = blocked }
    env.fileSystem = setmetatable({}, { __index = function() return blocked end })
    env.clientCloud = setmetatable({}, { __index = function() return blocked end })
    env.serverCloud, env.network = env.clientCloud, env.clientCloud
    env.math = setmetatable({}, { __index = math })
    env.math.random = function() f.random = f.random + 1; error("RNG forbidden") end
    env.math.randomseed = env.math.random
    local function record(kind, data)
        data = data or {}; data.kind, data.tx, data.ty = kind, f.tx, f.ty
        f.calls[#f.calls + 1] = data
        return data
    end
    env.nvgCreateImage = function(vg, path)
        f.loads[#f.loads + 1] = { vg = vg, path = path }
        if f.failed[path] then return -1 end
        local handle = f.next; f.next = f.next + 1
        f.handles[handle] = path
        return handle
    end
    env.nvgImageSize = function() return 1920, 1080 end
    env.nvgRGBA = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    env.nvgSave = function()
        f.stack[#f.stack + 1] = { tx = f.tx, ty = f.ty, clip = copy(f.clip), font = f.font }
    end
    env.nvgRestore = function()
        local p = assert(table.remove(f.stack), "VG restore imbalance")
        f.tx, f.ty, f.clip, f.font = p.tx, p.ty, p.clip, p.font
    end
    env.nvgIntersectScissor = function(_, x, y, w, h)
        local clip = { x = x + f.tx, y = y + f.ty, w = w, h = h }
        if f.clip then
            local r, b = math.min(clip.x + w, f.clip.x + f.clip.w), math.min(clip.y + h, f.clip.y + f.clip.h)
            clip.x, clip.y = math.max(clip.x, f.clip.x), math.max(clip.y, f.clip.y)
            clip.w, clip.h = math.max(0, r - clip.x), math.max(0, b - clip.y)
        end
        f.clip = clip
    end
    env.nvgScissor = function(_, x, y, w, h) f.clip = { x = x, y = y, w = w, h = h } end
    env.nvgResetScissor = function() f.clip = nil end
    env.nvgTranslate = function(_, x, y) f.tx, f.ty = f.tx + x, f.ty + y end
    env.nvgBeginPath = function() f.shape, f.paint = nil, nil end
    env.nvgRect = function(_, x, y, w, h) f.shape = { x = x, y = y, w = w, h = h } end
    env.nvgRoundedRect = function(_, x, y, w, h) f.shape = { x = x, y = y, w = w, h = h, rounded = true } end
    env.nvgCircle = function(_, x, y, r) f.shape = { x = x, y = y, r = r } end
    env.nvgFillColor = function(_, color) f.color = color end
    env.nvgFillPaint = function(_, paint) f.paint = paint end
    env.nvgFill = function() record("fill", { shape = copy(f.shape), color = copy(f.color), paint = copy(f.paint) }) end
    env.nvgRadialGradient = function(_, ...) return { kind = "radial", args = { ... } } end
    env.nvgLinearGradient = function(_, ...) return { kind = "linear", args = { ... } } end
    env.nvgImagePattern = function(_, x, y, w, h, _, image, alpha)
        record("image", { image = image, path = f.handles[image], x = x, y = y, w = w, h = h, alpha = alpha })
        return { image = image }
    end
    env.nvgFontSize = function(_, size) f.font = size end
    env.nvgText = function(_, x, y, text) record("text", { x = x, y = y, text = text }); return 0 end
    for _, name in ipairs({ "nvgStroke", "nvgStrokeColor", "nvgStrokeWidth", "nvgFontFace",
        "nvgTextAlign", "nvgTextLineHeight", "nvgMoveTo", "nvgLineTo" }) do env[name] = noop end
    f.modules["core.I18n"] = {
        get = function() return f.language end,
        lookup = function(text) return text end,
        displayBounds = function(_, _, _, text) return (utf8.len(text) or 0) * f.font * 0.5 end,
        displayText = env.nvgText,
    }
    local function image(_, handle, cx, cy, w, h, alpha)
        if handle >= 0 and alpha > 0.01 then
            record("image", { image = handle, path = f.handles[handle], x = cx, y = cy, w = w, h = h, alpha = alpha })
        end
    end
    f.modules["core.DrawUtil"] = { drawImageCover = image, drawImageCentered = image,
        drawTextStroke = function(_, x, y, text) record("name", { x = x, y = y, text = text }) end }
    f.modules["ui.widget.HeroFrame"] = { draw = function(_, opts) record("avatar", copy(opts)) end }
    f.modules["config.HeroConfig"] = { get = function(id) return { name = ({ "大狗嚼", "黄桃龙", "叮咚鸡" })[id] or "测试英雄" } end }
    env.require = function(name)
        if f.modules[name] then return f.modules[name] end
        local permitted = name:match("^config%.") or name == "core.I18nStory" or name == "core.EventBus"
            or name == "ui.story.StoryDisplay" or name == "ui.story.StoryCinematicMotion"
            or name == "ui.story.ScenarioDialogue" or name == "ui.story.gate.LetterIntro"
            or name == "ui.story.gate.IntroCutscene"
        assert(permitted, "unexpected dependency " .. name)
        local module = assert(load(source(name), "@" .. name, "t", env))()
        f.modules[name] = module
        return module
    end
    f.motion = env.require("ui.story.StoryCinematicMotion")
    f.scenario = env.require("ui.story.ScenarioDialogue")
    f.letter = env.require("ui.story.gate.LetterIntro")
    f.intro = env.require("ui.story.gate.IntroCutscene")
    f.config = env.require("config.ScenarioDialogueConfig")
    f.story = env.require("core.I18nStory")
    f.scenario.init(f.vg, nil); f.letter.init(f.vg); f.intro.init(f.vg, nil)
    env.require("core.EventBus").on("scenario_dialogue_finished", function(e) f.events[#f.events + 1] = copy(e) end)
    function f.draw(module)
        f.calls = {}
        local before = copy(f.clip)
        if module == f.scenario then module.draw(1920, 1080)
        elseif module == f.letter then module.draw(f.vg, 1920, 1080)
        else module.draw(f.vg) end
        eq(#f.stack, 0, "VG saves balanced")
        check(same(before, f.clip), "host clip preserved")
        eq(f.tx, 0, "host x preserved"); eq(f.ty, 0, "host y preserved")
        return copy(f.calls)
    end
    function f.image(path)
        for _, c in ipairs(f.calls) do if c.kind == "image" and c.path == path then return c end end
    end
    function f.safe() eq(f.random, 0, "zero RNG"); eq(f.io, 0, "zero save/cloud IO") end
    return f
end
local function stationary(f, module, snapshot)
    f.draw(module)
    local state, draws, loads = snapshot(), copy(f.calls), #f.loads
    for _ = 1, 4 do
        check(same(f.draw(module), draws), "identical elapsed gives identical actual draws")
        check(same(snapshot(), state), "draw does not advance presentation/business state")
        eq(#f.loads, loads, "draw does not load resources")
    end
end
local function sampleState(f)
    return copy(up(f.scenario.update, "presentation_"))
end
local function finishScenario(f)
    local _, count = f.scenario.getProgress()
    for _ = 1, count do f.scenario.update(100); f.scenario.advance() end
    if f.scenario.isActive() then f.scenario.update(0.3) end
end
local function case(name, fn)
    groups = groups + 1
    local ok, why = pcall(fn)
    if not ok then failures = failures + 1; print(TAG .. " FAIL " .. name .. " " .. tostring(why))
    else print(TAG .. " PASS " .. name) end
end

function Start()
    case("pure-motion bounds/identity/two-handles/no-same-line-restart", function()
        local f = fixture(); local m, s = f.motion, f.motion.new()
        for _, size in ipairs({ {1920,1080}, {844,390}, {1080,2400} }) do
            local previousWidth = 0
            for _, t in ipairs({ 0, 0.1, 2, 12, 100, 10000 }) do
                local x, y, w, h = m.cover(t, size[1], size[2])
                check(w >= size[1] and w <= size[1] * 1.03 and h >= size[2] and h <= size[2] * 1.03,
                    "cover overscan <=3 percent")
                check(x - w * 0.5 <= 0 and y - h * 0.5 <= 0 and x + w * 0.5 >= size[1]
                    and y + h * 0.5 >= size[2], "camera never exposes an edge")
                check(w >= previousWidth, "slow monotonic push"); previousWidth = w
            end
        end
        m.present(s, "A", 1); m.update(s, 2); local before = copy(s)
        m.present(s, "A", 1); check(same(s, before), "same displayed identity never resets clock")
        m.present(s, "B", 2); eq(s.previous.image, 1, "old image retained")
        m.update(s, 0.16); near(s.transition, 0.16, "short transition halfway")
        m.present(s, "C", 3); eq(s.previous.image, 2, "rapid transition keeps exactly two images")
        m.update(s, 0.32); eq(s.previous, nil, "old handle dropped after 0.32s")
        m.reset(s); eq(s.current, nil, "reset drops all visual identity")
        eq(m.theme("image/剧情/背景/STORY_BG_01.png"), "warm", "desk warm")
        eq(m.theme("image/剧情/背景/STORY_BG_03.png"), "cool", "forest cool")
        f.safe()
    end)
    case("scenario motion differs/subtitle-and-portrait anchors/typewriter10", function()
        local f = fixture(); local s = f.scenario; local cfg = f.config.OPENING_JOINS[1]
        s.show(cfg); s.update(0.125); f.draw(s)
        local portrait = f.image("image/角色立绘/大狗嚼_透明立绘.png")
        check(portrait ~= nil, "real portrait displayed")
        near(portrait.alpha, 0.875, "original entering easeOutCubic")
        near(portrait.x, 1920 * (0.30 + 0.045 * 0.125), "original enter slide")
        near(portrait.h, 1080 * 0.92, "original large portrait height")
        s.update(0.125); s.advance(); f.draw(s)
        local bg = copy(f.image(cfg.background)); local names = {}
        for _, c in ipairs(f.calls) do if c.kind == "text" or c.kind == "name" then names[#names + 1] = {c.x,c.y,c.text} end end
        s.update(6); f.draw(s)
        check(f.image(cfg.background).w > bg.w and f.image(cfg.background).x ~= bg.x, "real background motion sampled differently")
        local after = {}
        for _, c in ipairs(f.calls) do if c.kind == "text" or c.kind == "name" then after[#after + 1] = {c.x,c.y,c.text} end end
        -- 继续提示只变化明暗，不移动其文本锚点。
        check(same(names, after), "subtitle/name/text anchors remain fixed during push")
        stationary(f, s, function() return {sampleState(f),s.getProgress(),s.isActive(),#f.events,f.callbacks} end)
        s.reset(); s.show({ steps = {{name="旁白",text="abcdefghij"}}, background=cfg.background })
        s.update(0.5); f.draw(s)
        local found = false; for _, c in ipairs(f.calls) do if c.text == "abcde" then found = true end end
        check(found, "10 codepoints per second retained")
        f.safe()
    end)
    case("scenario eye2-plus-hold2/dismiss0.3/exit0.25", function()
        local f = fixture(); local s = f.scenario; local cfg = copy(f.config.SCENARIO_38)
        cfg.mode, cfg.eyeOpen = "small", true
        cfg.onFinish = function() f.callbacks = f.callbacks + 1 end
        s.show(cfg); f.draw(s)
        eq(up(s.update,"eyeOpenActive_"),true,"eye starts closed")
        s.update(1); near(up(s.update,"eyeOpenness_"),0.5,"eye midpoint easing")
        s.update(1); eq(up(s.update,"eyeHoldActive_"),true,"hold starts exactly 2 seconds")
        s.update(1.99); eq(up(s.update,"eyeHoldActive_"),true,"hold still active at 1.99")
        s.update(0.01); eq(up(s.update,"eyeHoldActive_"),false,"hold ends at 2 seconds")
        s.advance(); s.advance(); s.update(0.125); f.draw(s)
        local old = f.image("image/角色立绘/大狗嚼_透明立绘.png")
        near(old.alpha,0.875,"original exit easeInCubic")
        s.update(0.125); eq(up(s.update,"portraitAnimState_"),"entering","exit lasts .25")
        s.update(0.25); eq(up(s.update,"portraitAnimState_"),"idle","entrance lasts .25")
        finishScenario(f); eq(f.callbacks,1,"natural small dismissal callback once")
        eq(f.events[1].reason,"dismissed","original dismissal event")
        s.show({mode="small",background=cfg.background,steps={cfg.steps[1]},onFinish=cfg.onFinish})
        s.update(100); s.advance(); s.update(0.29); eq(f.callbacks,1,"no early callback before .3")
        stationary(f,s,function() return {sampleState(f),s.isActive(),f.callbacks} end)
        s.update(0.01); eq(f.callbacks,2,"dismiss callback at .3")
        f.safe()
    end)
    case("scenario CG transitions/same-image sentence/no duplicate portrait/missing fallback", function()
        local f = fixture(); local s = f.scenario
        s.show({background="room.png",steps={{name="旁白",text="A",cg="cgA.png"},
            {name="旁白",text="B",cg="cgA.png"},{name="旁白",text="C",cg="cgB.png"},
            {name="旁白",text="D",cg="cgC.png"}}})
        s.update(2); s.advance(); s.advance()
        near(sampleState(f).current.elapsed,2,"same cg sentence preserves camera time")
        eq(sampleState(f).previous,nil,"same cg has no dissolve")
        s.advance(); s.advance(); s.update(0.16); f.draw(s)
        local a,b=f.image("cgA.png"),f.image("cgB.png")
        check(a and b,"true cg change renders old/new")
        near(a.alpha,1,"old backdrop opaque"); near(b.alpha,0.5,"new backdrop smoothstep .5")
        local count=0; for _,c in ipairs(f.calls) do if c.kind=="image" then count=count+1 end end
        eq(count,2,"CG transition has two images and no added portrait")
        s.advance(); s.advance(); f.draw(s)
        eq(sampleState(f).previous.identity,"cgB.png","rapid change discards older cg")
        s.update(0.32); f.draw(s); eq(f.image("cgB.png"),nil,"old bg no longer drawn")
        f.failed["missing.png"]=true
        s.reset(); s.show({background="missing.png",steps={{name="旁白",text="A"}}})
        f.draw(s); check(f.image("image/剧情/背景/STORY_BG_03.png")~=nil,"large missing uses original DEFAULT")
        stationary(f,s,function() return sampleState(f) end)
        f.failed["missing.png"]=nil
        s.reset(); s.show({background="missing.png",steps={{name="旁白",text="A"}}})
        f.draw(s); check(f.image("missing.png")~=nil,"missing restored on reopen")
        f.safe()
    end)
    case("scenario natural/skip/reset callback ordering and synchronous chain", function()
        for _, mode in ipairs({"large","small"}) do
            for _, way in ipairs({"natural","skip"}) do
                local f=fixture(); local s=f.scenario
                s.show({mode=mode,background="old.png",steps={{name="旁白",text="A"}},onFinish=function()
                    f.callbacks=f.callbacks+1
                    eq(sampleState(f).current,nil,"old visual reset before callback")
                    s.show({mode="large",background="new.png",steps={{name="旁白",text="B"}}})
                end})
                if way=="skip" then s.skip() else finishScenario(f) end
                eq(f.callbacks,1,"callback once")
                eq(s.isActive(),true,"synchronous next scene stays active")
                eq(sampleState(f).current.identity,"new.png","new visual not wiped after callback")
                eq(#f.events,1,"original finish event emitted once after callback")
                s.reset(); s.skip(); s.update(100); eq(f.callbacks,1,"reset inert")
                f.safe()
            end
        end
    end)
    case("letter true lifecycle/full+compact/draw inert/motion/steady ink/languages", function()
        for _, compact in ipairs({false,true}) do
            local f=fixture(); local l=f.letter
            l.start(function() f.callbacks=f.callbacks+1 end,{compact=compact})
            l.update(0.6); f.draw(l); local first=copy(f.image("image/剧情/背景/STORY_BG_01.png"))
            local unit=up(l.update,"presentation_")
            stationary(f,l,function() return {copy(unit),l.isOpen(),f.callbacks,up(l.update,"state"),up(l.update,"revealT")} end)
            l.update(0.6); f.draw(l)
            check(f.image(first.path).w>first.w,"desk truly pushes forward")
            for _,lang in ipairs({"zh_CN","en","ja","ko","zh_TW"}) do
                local elapsed=unit.current.elapsed; f.language=lang; f.draw(l)
                eq(unit.current.elapsed,elapsed,"language does not restart desk clock")
                eq(f.callbacks,0,"language/draw no callback")
            end
            for _=1,20 do l.handleTap() end
            l.update(0); eq(f.callbacks,1,"skip by existing tap chain once")
            l.handleTap(); l.update(100); eq(f.callbacks,1,"finished letter inert")
            l.start(function() f.callbacks=f.callbacks+1 end,{compact=compact})
            -- 按原阈值取下一可表示采样，避免 0.45*3 与十进制2.85的浮点尾差。
            for _=1,(compact and 1 or 4) do l.update(0.45*3 + 1.5 + 0.000001) end
            if not compact then l.update(0.9 + 0.8 + 0.000001) end
            l.update(0.59); eq(f.callbacks,1,"natural letter fade not early")
            l.update(0.01); eq(f.callbacks,2,"natural letter completes original timeline")
            l.start(function() f.callbacks=f.callbacks+1 end); l.reset(); l.update(100)
            eq(f.callbacks,2,"letter hard reset drops callback")
            f.safe()
        end
    end)
    case("letter synchronous restart retains new visual state and host context", function()
        local f=fixture(); local l=f.letter
        l.start(function()
            f.callbacks=f.callbacks+1
            eq(up(l.update,"presentation_").current,nil,"letter clears old visual before callback")
            l.start(nil,{compact=true})
        end,{compact=true})
        for _=1,4 do l.handleTap() end; l.update(0)
        eq(f.callbacks,1,"first letter finished")
        check(l.isOpen() and up(l.update,"presentation_").current~=nil,"new letter not erased")
        f.clip={x=10,y=20,w=100,h=80}; stationary(f,l,function() return copy(up(l.update,"presentation_")) end)
        f.safe()
    end)
    case("intro original5phase20.5s/alpha cross-contract/draw inert/languages", function()
        local f=fixture(); local i=f.intro
        i.start(function() f.callbacks=f.callbacks+1 end)
        i.update(1.5); i.update(2); f.draw(i)
        local temple=f.image("image/剧情/背景/STORY_TERMINAL_TEMPLE.png")
        near(temple.alpha,0.5,"temple phase2 alpha midpoint")
        stationary(f,i,function() return {up(i.update,"presentationElapsed_"),up(i.update,"phase"),up(i.update,"phaseT"),i.isActive(),f.callbacks} end)
        i.update(2); i.update(3.75); f.draw(i)
        near(f.image("image/剧情/背景/STORY_TERMINAL_TEMPLE.png").alpha,1,"temple opaque throughout road crossfade")
        near(f.image("image/剧情/背景/STORY_TERMINAL_ROAD.png").alpha,0.5,"road phase3 alpha midpoint")
        for _,lang in ipairs({"zh_CN","en","ja","ko","zh_TW"}) do
            local elapsed=up(i.update,"presentationElapsed_"); f.language=lang; f.draw(i)
            eq(up(i.update,"presentationElapsed_"),elapsed,"language does not advance intro time")
            eq(f.callbacks,0,"caption never invokes finish")
        end
        i.update(3.75); i.update(4); i.update(1.75); f.draw(i)
        near(f.image("image/剧情/背景/STORY_TERMINAL_ROAD.png").alpha,0.5,"phase5 fades road")
        near(up(i.update,"presentationElapsed_"),18.75,"timeline elapsed at phase5 middle")
        i.update(1.749); eq(f.callbacks,0,"no finish before20.5")
        i.update(0.001); eq(f.callbacks,1,"original five phases total20.5s")
        check(i.isFinished() and not i.isActive(),"natural finish flags unchanged")
        i.skip(); i.update(100); eq(f.callbacks,1,"duplicate intro finish inert")
        f.safe()
    end)
    case("intro horizontal viewport preserves scene and caption anchors", function()
        local f = fixture(); local i = f.intro
        i.start(nil); i.update(1.5); i.update(3)
        for _, size in ipairs({ {1920,1080}, {1280,800}, {1024,768}, {844,390} }) do
            local w, h = size[1], size[2]
            f.calls = {}
            i.draw(f.vg, w, h)
            local temple = f.image("image/剧情/背景/STORY_TERMINAL_TEMPLE.png")
            check(temple and temple.w >= w and temple.w <= w * 1.03
                and temple.h >= h and temple.h <= h * 1.03, "background uses viewport not portrait canvas")
            near(temple.x, w * (0.5 + 0.0018 * math.sin(3 * 0.065)), "horizontal camera center")
            local captions = 0
            for _, c in ipairs(f.calls) do
                if c.kind == "text" then
                    near(c.x, w * 0.5, "caption stays horizontally centered")
                    check(c.y >= h * 0.35 and c.y <= h * 0.65, "caption stays in middle safe band")
                    captions = captions + 1
                end
            end
            check(captions > 0 and captions <= 2, "caption displayed without portrait crop")
            eq(#f.stack, 0, "horizontal draw balances VG state")
            near(f.tx, 0, "no portrait translation x"); near(f.ty, 0, "no portrait translation y")
        end
        f.safe()
    end)
    case("intro skip/reset and sync-chain visual reset before callback", function()
        local f=fixture(); local i=f.intro
        i.start(function()
            f.callbacks=f.callbacks+1
            eq(up(i.update,"presentationElapsed_"),0,"reset before Intro callback")
            i.start(nil)
        end)
        i.update(1); i.skip()
        check(i.isActive() and not i.isFinished(),"synchronous next Intro survives")
        eq(up(i.update,"presentationElapsed_"),0,"new Intro begins at zero")
        i.reset(); i.skip(); i.update(100); eq(f.callbacks,1,"hard reset no callback")
        f.safe()
    end)
    print(string.format("%s RESULT groups=%d checks=%d failures=%d %s",TAG,groups,checks,failures,
        failures==0 and "ALL PASS" or "FAILED"))
    if failures>0 then log:Write(LOG_ERROR,TAG .. " failures=" .. failures) end
    engine:Exit()
end
