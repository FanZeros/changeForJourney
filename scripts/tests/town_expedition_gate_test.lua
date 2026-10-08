-- 城镇远征门专项：复用2D脚手架生命周期，只读白名单源码，真实load(env)。
-- cwd=/home/Maker/town-expedition-gate-validation-20261006，禁止在项目根cwd运行。
-- .cli/UrhoXRuntime tests/town_expedition_gate_test.lua -tapcode_dir=<项目根>
--   -tool_mode -nosound -graphicsheadless -validate -validate-frames=60
--   -validate-timeout=45 -validate-output=<隔离目录>/validate.json
-- 可选 -review：真实TownScene/DrawUtil/DarkIcon/NanoVG与全部建筑PNG；背景关闭。
-- review: -graphicssurfaceless -screenshot=<绝对PNG> -screenshot-frame=120 -x1080 -y2400。
-- 业务依赖均为内存fixture；不启动main/Boot.run，不读写玩家档，不提供save/cloud。
-- Boot只执行精确源注入块，不能等同完整启动/移动端触控验收。

local ROOT = "/workspace/changeForJourney-workspace1005"
local REVIEW = false
for _, arg in ipairs(GetArguments()) do
    local root = arg:match("^%-tapcode_dir=(.+)$")
    if root then ROOT = root:gsub("/+$", "") end
    if arg == "-review" or arg == "-town-expedition-review" then REVIEW = true end
end
local TAG = "[town_expedition_gate_test] "
local GATE = "image/城镇建筑/UI_CZ_EXPEDITION_GATE.png"
local SOURCE_FILES = {
    ["ui.town.TownScene"] = "ui/town/TownScene.lua",
    ["ui.town.TownExpeditionIcon"] = "ui/town/TownExpeditionIcon.lua",
    ["core.DrawUtil"] = "core/DrawUtil.lua",
    ["core.DarkIcon"] = "core/DarkIcon.lua",
    ["boot.StandaloneBoot"] = "boot/StandaloneBoot.lua",
    ["boot.BattleRewardOverlay"] = "boot/BattleRewardOverlay.lua",
    ["boot.StandaloneHorizonInput"] = "boot/StandaloneHorizonInput.lua",
    ["ui.battle.tri.BattleTriPage"] = "ui/battle/tri/BattleTriPage.lua",
}
local nativeFile, nativeCreateImage = File, nvgCreateImage
local sources, reads, contexts, initialLoaded = {}, {}, {}, {} ---@type any
local checks, groups, failures = 0, 0, 0
for name in pairs(SOURCE_FILES) do initialLoaded[name] = package.loaded[name] end
local function check(ok, message) checks = checks + 1; assert(ok, message) end
local function eq(a, b, message) check(a == b, message .. " actual=" .. tostring(a) .. " expected=" .. tostring(b)) end
local function near(a, b, message) check(type(a) == "number" and math.abs(a - b) < 0.000001, message) end
local function noop() end
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
local function source(name)
    local rel = assert(SOURCE_FILES[name], "source denied: " .. tostring(name))
    if sources[name] then return sources[name] end
    local path = ROOT .. "/scripts/" .. rel
    assert(path:sub(1, 1) == "/" and not path:find("..", 1, true) and path:sub(-4) == ".lua")
    -- 原生File唯一出口：固定绝对路径白名单 + FILE_READ + Dispose，无玩家文件参数。
    local file = assert(nativeFile(path, FILE_READ), "source File unavailable: " .. path)
    assert(file:IsOpen(), "source open failed: " .. path)
    local ok, text = pcall(function()
        local lines = {}; while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        return table.concat(lines, "\n")
    end)
    file:Dispose(); assert(ok, text)
    sources[name], reads[#reads + 1] = text, path
    return text
end
local function compile(text, label, env)
    local chunk, why = load(text, "@" .. label, "t", env); assert(chunk, why); return chunk()
end
-- 热区独立oracle，含端点：
-- TREE名牌底1291.5       上gap18.5       GATE hit上1310
-- 教堂右383 | gap27 | x410 +------220------+ x630 | gap3.5 | 酒馆左633.5
--                              图(520,1440)192x240
--                              牌(520,1610)220x80
--                              hit(520,1480)220x340，下1650
-- 门图/牌皆命中；边外0.001/gap不触发；旧建筑区域与解锁逻辑不扩大。
local function rect(cx, cy, w, h) return { x = cx - w / 2, y = cy - h / 2, w = w, h = h } end
local function within(a, b, p)
    p = p or 0
    return a.x - p >= b.x and a.y - p >= b.y and a.x + a.w + p <= b.x + b.w and a.y + a.h + p <= b.y + b.h
end
local function overlaps(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
local HIT, IMAGE, PLATE = rect(520, 1480, 220, 340), rect(520, 1440, 192, 240), rect(520, 1610, 220, 80)
local NVG = {
    "nvgArc", "nvgBeginPath", "nvgBezierTo", "nvgCircle", "nvgClosePath", "nvgCreateImage",
    "nvgEllipse", "nvgFill", "nvgFillColor", "nvgFillPaint", "nvgFontFace", "nvgFontSize",
    "nvgGlobalCompositeBlendFuncSeparate", "nvgGlobalCompositeOperation", "nvgImagePattern",
    "nvgImagePatternTinted", "nvgImageSize", "nvgIntersectScissor", "nvgLineCap", "nvgLineJoin",
    "nvgLineTo", "nvgLinearGradient", "nvgMoveTo", "nvgQuadTo", "nvgRGBA", "nvgRadialGradient",
    "nvgRect", "nvgRestore", "nvgRotate", "nvgRoundedRect", "nvgRoundedRectVarying", "nvgSave",
    "nvgScale", "nvgShapeAntiAlias", "nvgSkewX", "nvgStroke", "nvgStrokeColor", "nvgStrokeWidth",
    "nvgText", "nvgTextAlign", "nvgTranslate", "nvgTextBounds",
}
local function newContext(review, vg)
    local c = { env = {}, deps = {}, calls = {}, loads = {}, handles = {}, forbidden = {}, feedback = {},
        events = {}, clock = { elapsedTime = 100 }, tutorial = false, unlocked = {}, level = 50,
        memory = { currency = { gold = 1234, diamond = 567, ticket = 8 }, battle = {
            teamStageIds = { 105, 203, 302 }, activeTeam = 2, clearedStages = { [101] = true } } },
        vg = vg or {}, nextHandle = 0, fontSize = 38, align = NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        review = review == true, modal = {}, nav = 3, navLocked = false, triOpen = true,
        terminal = nil, openSuccess = true, raidOnOpen = false, selections = 0, deniedExpected = 0,
    } ---@type any
    contexts[#contexts + 1] = c
    c.before = copy(c.memory)
    local e = c.env
    for _, k in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select",
        "tonumber", "tostring", "type", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal" }) do e[k] = _G[k] end
    e.math, e.string, e.table, e.utf8 = copy(math), copy(string), copy(table), copy(utf8)
    e._G, e.time, e.H_TRI_L0 = e, c.clock, true
    c.messages = {}
    e.print = function(message) c.messages[#c.messages + 1] = tostring(message) end
    for k, v in pairs(_G) do if k:match("^NVG_") then e[k] = v end end
    local function deny(label)
        return function() c.forbidden[#c.forbidden + 1] = label; error("isolated gate test denies " .. label) end
    end
    local function deniedObject(label)
        return setmetatable({}, { __index = function(_, k) return deny(label .. "." .. tostring(k)) end })
    end
    e.File = deny("File all paths/modes")
    for _, k in ipairs({ "cache", "fileSystem", "io", "os", "package", "debug", "engine",
        "clientCloud", "serverCloud", "network" }) do e[k] = deniedObject(k) end
    for _, k in ipairs({ "loadfile", "dofile", "GetFileSystem", "SubscribeToEvent", "SendEvent" }) do e[k] = deny(k) end
    local function mock(name, fields)
        c.deps[name] = setmetatable(fields, { __index = function(_, k) return deny(name .. "." .. tostring(k)) end })
        return c.deps[name]
    end
    c.mock = mock
    mock("core.GameState", { getLevel = function() return c.level end })
    mock("config.ExpTable", { CHURCH_UNLOCK_LEVEL = 30,
        isBuildingUnlocked = function() return c.unlocked.market ~= false end, getBuildingUnlockLevel = function() return 30 end })
    mock("systems.TutorialManager", { isActive = function() return c.tutorial end,
        isInputActive = function() return c.tutorial end,
        isBuildingUnlocked = function(k) return c.unlocked[k] ~= false end,
        getBuildingUnlockStageId = function() return nil end, registerHotspot = noop })
    mock("core.HorizonBg", { draw = function() error("fixture background must be disabled") end })
    mock("core.BattleLayout", {})
    mock("systems.ButtonFeedback", {
        begin = function(_, k, cx, cy, w, h) c.feedback[k] = rect(cx, cy, w, h); return false end,
        finish = noop, trigger = function(k) c.events[#c.events + 1] = k end,
    })
    mock("ui.loot.LootBox", { getCount = function() return 0 end, drawRates = noop, openPage = noop })
    mock("ui.blacksmith.BlacksmithPage", { canEnhanceAny = function() return false end, isOpen = function() return c.modal.smith == true end })
    mock("ui.church.ChurchPage", { hasAnyChurchBadge = function() return false end, isOpen = function() return c.modal.church == true end })
    mock("ui.church.talent.TalentPage", { hasAnyUnusedTalent = function() return false end,
        isOpen = function() return c.modal.talent == true end, getHorizonWidthScale = function() return 1 end })
    mock("ui.story.task.TaskPage", { hasClaimable = function() return false end, isOpen = function() return c.modal.task == true end })
    local function record(kind, fields) fields.kind = kind; c.calls[#c.calls + 1] = fields end
    for _, k in ipairs(NVG) do e[k] = noop end
    e.nvgRGBA = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    e.nvgFontSize = function(_, size) c.fontSize = size end
    e.nvgTextAlign = function(_, align) c.align = align end
    e.nvgTextBounds = function(_, _, _, text) return (utf8.len(text) or #text) * c.fontSize end
    e.nvgText = function(_, x, y, text)
        local w = e.nvgTextBounds(c.vg, 0, 0, text)
        record("text", { text = text, x = x, y = y, size = c.fontSize,
            rect = rect(x, y, w, c.fontSize), align = c.align }); return x + w
    end
    e.nvgCreateImage = function(_, path)
        assert(type(path) == "string" and path:match("^image/") and not path:find("..", 1, true))
        c.loads[#c.loads + 1] = path
        if path == GATE and c.gateNil then return nil end
        if path == GATE and c.gateHandle ~= nil then c.handles[c.gateHandle] = path; return c.gateHandle end
        local h = c.nextHandle
        while c.handles[h] ~= nil do h = h + 1 end
        c.nextHandle = h + 1; c.handles[h] = path; return h
    end
    e.nvgImagePattern = function(_, x, y, w, h, _, hnd, alpha)
        record("image", { path = c.handles[hnd], handle = hnd, rect = { x = x, y = y, w = w, h = h }, alpha = alpha })
        return {}
    end
    e.nvgImagePatternTinted = function(_, x, y, w, h, a, hnd, tint)
        return e.nvgImagePattern(c.vg, x, y, w, h, a, hnd, tint.a / 255)
    end
    e.nvgImageSize = function() return 1080, 2400 end
    e.nvgLinearGradient, e.nvgRadialGradient = function() return {} end, function() return {} end
    if c.review then
        for _, k in ipairs(NVG) do e[k] = assert(_G[k], "missing real NanoVG " .. k) end
        e.nvgCreateImage = function(ctx, path, flags)
            assert(type(path) == "string" and path:match("^image/") and not path:find("..", 1, true))
            c.loads[#c.loads + 1] = path
            local h = nativeCreateImage(ctx, path, flags)
            assert(h and h >= 0, "review actual image missing " .. path); return h
        end
    end
    e.require = function(name)
        if c.deps[name] then return c.deps[name] end
        if name == "ui.town.TownScene" or name == "ui.town.TownExpeditionIcon"
            or name == "core.DrawUtil" or name == "core.DarkIcon"
            or name == "boot.BattleRewardOverlay" then
            local m = compile(source(name), ROOT .. "/scripts/" .. SOURCE_FILES[name], e)
            c.deps[name] = m; return m
        end
        return deny("unknown require " .. tostring(name))()
    end
    c.page = e.require("ui.town.TownScene"); c.page.init(c.vg)
    if not c.review then
        local compass = c.deps["ui.town.TownExpeditionIcon"]
        local drawCompass = compass.draw
        compass.draw = function(ctx,cx,cy,size)
            record("compass", {rect=rect(cx,cy,size,size)})
            drawCompass(ctx,cx,cy,size)
        end
        local dark = c.deps["core.DarkIcon"]; local drawNine = dark.drawNine
        dark.drawNine = function(ctx, style, x, y, w, h, opts)
            record("plate", { style = style, rect = { x = x, y = y, w = w, h = h } })
            return drawNine(ctx, style, x, y, w, h, opts)
        end
    end
    c.draw = function(at) if at then c.clock.elapsedTime = at end; c.page.draw(c.vg) end
    return c
end
local function idle(c) check(same(c.memory, c.before), "fixture所有货币/三队关卡/activeTeam/首通账本不变") end
local function pointCase(c, x, y, expected, consumed)
    c.page.cancelPendingPageOpen(); c.clock.elapsedTime = c.clock.elapsedTime + 1
    local opened = 0; c.page.setOnExpeditionClick(function() opened = opened + 1 end)
    if consumed == nil then consumed = expected end
    eq(c.page.handleInput(x, y), consumed, "命中返回 " .. x .. "," .. y)
    eq(opened, 0, "点击不立即执行")
    c.draw(c.clock.elapsedTime + 0.149); eq(opened, 0, "0.149秒尚未回调")
    c.draw(c.clock.elapsedTime + 0.0011); eq(opened, expected and 1 or 0, "0.15秒后恰好一次或不触发")
    c.draw(c.clock.elapsedTime + 1); eq(opened, expected and 1 or 0, "后续draw不得重复")
    idle(c)
end
local function layoutCases()
    local c = newContext(); c.draw()
    check(type(c.page.setOnExpeditionClick) == "function", "真实TownScene导出门回调API")
    local image, title, plate, icon = {}, {}, {}, {} ---@type any
    for _, call in ipairs(c.calls) do
        if call.kind == "image" and call.path == GATE then image = call end
        if call.kind == "compass" then icon = call end
        if call.kind == "plate" and same(call.rect, PLATE) then plate = call end
        if call.kind == "text" and call.text == "远征" and call.x == 550 and call.y == 1610 then title = call end
    end
    check(plate.kind == "plate" and plate.style == "plain", "真实名牌center5201610绘制220x80")
    check(image and same(image.rect, IMAGE), "真实门图center5201440绘制192x240")
    check(title and title.align == NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "远征标题5501610给左侧白图标留位")
    check(icon.kind == "compass" and same(icon.rect, rect(460, 1610, 48, 48)), "白色矢量罗盘4601610绘制48x48")
    check(within(icon.rect, PLATE), "完整白图标在原220x80牌内")
    check(icon.rect.x + icon.rect.w + 8 <= title.rect.x - 4, "图标与文字描边不重叠且有间隔")
    check(same(c.feedback.town_expedition, HIT), "BF热区center5201480尺寸220x340")
    check(within(IMAGE, HIT) and within(PLATE, HIT), "完整门图与名牌均在统一热区")
    check(title and within(title.rect, PLATE, 4), "保守全宽字形加描边不越220x80名牌")
    for _, call in ipairs(c.calls) do
        if call.kind == "text" and call.text ~= "远征" then
            check(not overlaps(call.rect, PLATE), "新名牌不碰旧标题 " .. call.text)
        end
    end
    local count = #c.loads; c.draw(); eq(#c.loads, count, "图片仅初始化一次")
    idle(c)
end
local function resourceCases()
    for _, response in ipairs({ 0, -1, "nil" }) do
        local c=newContext(); c.gateNil=response=="nil"
        if not c.gateNil then c.gateHandle=response; c.handles[response]="reserved gate handle" end
        local n=0; c.page.setOnExpeditionClick(function() n=n+1 end); c.draw()
        local imageCount, loadCount, success=0,0,false
        for _, call in ipairs(c.calls) do if call.kind=="image" and call.path==GATE then imageCount=imageCount+1 end end
        for _, path in ipairs(c.loads) do if path==GATE then loadCount=loadCount+1 end end
        for _, message in ipairs(c.messages) do if message:find("远征门加载并缓存",1,true) then success=true end end
        eq(loadCount,1,"门图只请求一次 "..tostring(response)); eq(success,response==0,"合法句柄0记成功，缺图不假报成功")
        eq(imageCount,response==0 and 1 or 0,"句柄0真正绘制192x240，缺图仅名牌")
        c.calls={}; c.page.handleInput(520,1440); c.draw(100.075)
        local normal, flash=0,0
        for _, call in ipairs(c.calls) do
            if call.kind=="image" and call.path==GATE then
                check(same(call.rect,IMAGE),"句柄0普通/闪白均保持门绘制矩形")
                if call.alpha==1 then normal=normal+1 else flash=flash+1 end
            end
        end
        eq(normal,response==0 and 1 or 0,"句柄0普通绘制"); eq(flash,response==0 and 1 or 0,"句柄0闪白绘制")
        c.draw(100.151); eq(n,1,"图0或缺图时门回调可执行"); c.page.handleInput(520,1610); c.draw(100.302)
        eq(n,2,"缺图名牌仍可点"); c.draw(101)
        local requests=0; for _, path in ipairs(c.loads) do if path==GATE then requests=requests+1 end end
        eq(requests,1,"图0/缺图后续帧不重试加载"); idle(c)
    end
end
local function boundaryCases()
    local c = newContext()
    for _, r in ipairs({ HIT, IMAGE, PLATE }) do
        for _, d in ipairs({ 0, 0.001 }) do
            for _, x in ipairs({ r.x + d, r.x + r.w / 2, r.x + r.w - d }) do
                for _, y in ipairs({ r.y + d, r.y + r.h / 2, r.y + r.h - d }) do pointCase(c, x, y, true) end
            end
        end
    end
    for _, p in ipairs({ {409.999,1480}, {630.001,1480}, {520,1309.999}, {520,1650.001},
        {409.999,1309.999}, {630.001,1650.001}, {409.999,1650.001}, {630.001,1309.999},
        {410,1309.999}, {630,1650.001}, {409.999,1310}, {630.001,1650}, {396,1440}, {631.75,1440},
        {520,1300}, {520,1660}, {520,1720}, {520,1789.999}, {1080,2400}, {0,0} }) do
        pointCase(c, p[1], p[2], false)
    end
end
local function oldBuildingCases()
    local c = newContext()
    for _, p in ipairs({ {"Smith",525,390}, {"Smith",534,560}, {"Tree",540,1040}, {"Tree",540,1235},
        {"Church",211,1400}, {"Church",238,1720}, {"Market",211,720}, {"Market",225,846},
        {"Warehouse",832,720}, {"Warehouse",837,870}, {"Tavern",832,1400}, {"Tavern",837,1524},
        {"LootBox",610,1940}, {"LootBox",610,2090}, {"Task",230,2050}, {"Task",230,2240} }) do
        local old, gate = 0, 0
        c.page["setOn" .. p[1] .. "Click"](function() old = old + 1 end)
        c.page.setOnExpeditionClick(function() gate = gate + 1 end)
        c.page.cancelPendingPageOpen(); eq(c.page.handleInput(p[2],p[3]),true,"旧入口仍消费点击 " .. p[1])
        c.draw(c.clock.elapsedTime + 0.151); eq(old,1,"旧图/牌回调仍正确 " .. p[1]); eq(gate,0,"旧入口不误开门")
    end
    for _, p in ipairs({ {"Smith","smith",525,390}, {"Tree","church",540,1040},
        {"Church","church",211,1400}, {"Tavern","tavern",832,1400}, {"Market","market",211,720} }) do
        local n = 0; c.page["setOn" .. p[1] .. "Click"](function() n = n + 1 end)
        c.unlocked[p[2]] = false; c.page.cancelPendingPageOpen()
        eq(c.page.handleInput(p[3],p[4]),true,"旧锁建筑仍吞点击"); c.draw(c.clock.elapsedTime + 1); eq(n,0,"旧锁不回调")
        c.unlocked[p[2]] = true
    end
    c.level = 1; c.tutorial = false; local n = 0; c.page.setOnChurchClick(function() n = n + 1 end)
    c.page.handleInput(211,1400); c.draw(c.clock.elapsedTime + 1); eq(n,0,"教堂等级30门控保留")
    c.tutorial = true; c.page.handleInput(211,1400); c.draw(c.clock.elapsedTime + 1); eq(n,1,"教堂教程豁免保留")
    idle(c)
end
local function compassWhiteCases()
    local c = newContext()
    local fills, strokes = {}, {}
    c.env.nvgFillColor = function(_, color) fills[#fills+1]=color end
    c.env.nvgStrokeColor = function(_, color) strokes[#strokes+1]=color end
    c.deps["ui.town.TownExpeditionIcon"].draw(c.vg,460,1610,48)
    eq(#fills,1,"罗盘只填充一个白色针形")
    eq(fills[1].r,255,"罗盘填充R纯白"); eq(fills[1].g,255,"罗盘填充G纯白"); eq(fills[1].b,255,"罗盘填充B纯白")
    local white, black=0,0
    for _, color in ipairs(strokes) do
        check(color.r==color.g and color.g==color.b,"罗盘轮廓不能出现金色/彩色")
        if color.r==255 then white=white+1 elseif color.r==0 then black=black+1 end
    end
    check(white>0 and black>0,"罗盘有纯白语义轮廓与黑色外描边")
    idle(c)
end

local function churchPolishCases()
    local c = newContext(); c.draw()
    local art = rect(211, 1451.6, 292.4, 584.8)
    local churchPath = "image/界面底板/城镇世界/UI_CZ_JT.png"
    local artCount = 0
    for _, call in ipairs(c.calls) do
        if call.kind == "image" and call.path == churchPath then
            check(same(call.rect, art), "礼拜堂立绘等比缩15%并保留底1744")
            artCount = artCount + 1
        end
    end
    eq(artCount, 1, "未锁礼拜堂只画一个普通层")
    check(same(c.feedback.town_church, rect(211, 1400, 344, 688)), "礼拜堂原BF/输入范围不缩错")
    check(not overlaps(art, HIT), "缩小教堂不与远征门热区重叠")
    local opened = 0; c.page.setOnChurchClick(function() opened = opened + 1 end)
    c.calls = {}; c.page.handleInput(211,1451.6); c.draw(100.075)
    local flashCount = 0
    for _, call in ipairs(c.calls) do
        if call.kind == "image" and call.path == churchPath then
            check(same(call.rect,art), "教堂普通与闪白同缩图矩形")
            flashCount = flashCount + 1
        end
    end
    eq(flashCount,2,"教堂闪白仅加相同立绘层")
    c.page.cancelPendingPageOpen()
    c.unlocked.church = false; c.calls = {}
    local silhouetteRects = 0
    c.env.nvgRect = function(_, x, y, w, h)
        if same({x=x,y=y,w=w,h=h},art) then silhouetteRects = silhouetteRects + 1 end
    end
    c.draw(101)
    local silhouette = 0
    for _, call in ipairs(c.calls) do
        if call.kind == "image" and call.path == churchPath then
            check(same(call.rect,art), "教堂锁定剪影同底锚缩图")
            silhouette = silhouette + 1
        end
    end
    eq(silhouette,1,"教堂锁定只复用一份剪影paint")
    eq(silhouetteRects,6,"教堂锁定六层剪影绘制保留")
    c.env.nvgRect = noop
    c.unlocked.church=true; c.level=30
    local label = rect(238,1720,361,113)
    for _, point in ipairs({{label.x,label.y},{label.x+label.w,label.y+label.h},
        {label.x+label.w,1720},{238,label.y+label.h}}) do
        c.page.cancelPendingPageOpen(); c.clock.elapsedTime=c.clock.elapsedTime+1
        local before=opened
        eq(c.page.handleInput(point[1],point[2]),true,"完整标签角/底沿消费点击")
        c.draw(c.clock.elapsedTime+.151); eq(opened,before+1,"标签仍回调原礼拜堂入口")
    end
    c.level=29
    c.page.handleInput(418.5,1776.5); c.draw(c.clock.elapsedTime+1)
    eq(opened,4,"新补齐标签边沿仍尊重Lv30门控")
    idle(c)
end

local function deferredCases()
    local c = newContext(); local n, replaced = 0, 0
    c.page.setOnExpeditionClick(function() n = n + 1 end)
    for i=1,20 do c.page.handleInput(520, i % 2 == 0 and 1610 or 1440) end
    c.draw(100.149); eq(n,0,"重复点延迟前不开"); c.draw(100.15); eq(n,1,"20次重复点只有一项门pending")
    c.draw(101); eq(n,1,"重复draw不重入"); c.page.handleInput(520,1440); c.draw(101.15); eq(n,2,"下一轮点击仍一次")
    c.page.handleInput(520,1440); c.page.cancelPendingPageOpen(); c.draw(102); eq(n,2,"教程接管cancel取消门pending")
    c.page.handleInput(520,1440); c.page.setOnExpeditionClick(function() replaced = replaced + 1 end)
    c.draw(103); eq(n,2,"setter替换不得执行旧回调"); eq(replaced,0,"旧排队也不偷跑新回调")
    c.page.handleInput(520,1610); c.draw(103.15); eq(replaced,1,"替换后新点击可回调")
    c.page.handleInput(520,1440); c.page.setOnExpeditionClick(nil); c.draw(104); eq(replaced,1,"setter nil取消pending")
    eq(c.page.handleInput(520,1610),true,"无回调仍有热区"); c.draw(105); idle(c)
end
local function bootFixture(c)
    -- 保留Tree之后/Tavern之前完整真实文本（包括helper），不复制/重写回调逻辑。
    local text = source("boot.StandaloneBoot")
    local tree = assert(text:find("TownScene.setOnTreeClick(function()",1,true))
    local first = assert(text:find("\n    end)", tree, true)) + #"\n    end)"
    local last = assert(text:find("    TownScene.setOnTavernClick(function()",first,true))
    local block = text:sub(first,last-1)
    check(block:find("TownScene.setOnExpeditionClick",1,true),"精确Boot源块含真实门注入")
    local guardText = source("ui.battle.tri.BattleTriPage")
    local guard = assert(guardText:match("(function BattleTriPage%.isTerminalRaidActive%(%).-end)"), "missing actual terminal guard")
    local page = {}
    local guardFactory = compile("return function(terminalRaid)\n" .. guard .. "\nreturn BattleTriPage.isTerminalRaidActive\nend",
        "actual-BattleTriPage-terminal-guard", { BattleTriPage = page })
    local tri = c.mock("ui.battle.tri.BattleTriPage", {
        isTerminalRaidActive = function() return guardFactory(c.terminal)() end,
        isOpen = function() return c.triOpen end,
        open = function() c.triOpen = c.openSuccess; if c.raidOnOpen then c.terminal = { failed = true } end end,
    })
    local nav = c.mock("ui.hud.BottomNav", { getSelectedIndex = function() return c.nav end,
        setSelectedIndex = function(i) if not c.refuseNav then c.nav = i end end,
        isAllLocked = function() return c.navLocked end,
        isTabLocked = function(i) eq(i,3,"仅查询原战斗页签锁"); return c.tabLocked == true end })
    local select = c.mock("ui.battle.stage.StageSelectDialog", { isOpen = function() return c.modal.stage == true end,
        openOverview = function() c.selections = c.selections + 1; c.modal.stage = true end })
    local topBar = c.mock("ui.hud.TopBar", { setOnExpeditionClick = function(callback) c.topBarExpedition = callback end })
    local map = {
        ["ui.tavern.TavernPage"]={"tavern","isOpen"}, ["ui.market.MarketPage"]={"market","isOpen"},
        ["ui.backpack.BackpackPanel"]={"backpack","isOpen"}, ["ui.loot.LootBoxPage"]={"loot","isOpen"},
        ["ui.hud.popup.PlayerInfoPanel"]={"info","isOpen"}, ["ui.hud.popup.RewardPopup"]={"reward","isOpen"},
        ["ui.battle.stage.SweepDialog"]={"sweep","isOpen"}, ["ui.battle.popup.DamageStatsPanel"]={"stats","isOpen"},
        ["ui.battle.popup.TerminalConfirmDialog"]={"confirm","isOpen"},
        ["ui.character.equip.EquipmentBag"]={"equip","shouldBattleOverlay"},
        ["ui.dungeon.DungeonBattleScene"]={"dungeon","isOpen"}, ["ui.tower.TowerBattleScene"]={"tower","isActive"},
        ["ui.hud.popup.OfflineRewardPanel"]={"offline","isOpen"}, ["ui.hud.popup.LevelUpPopup"]={"level","isOpen"},
        ["ui.hud.popup.UpdateNoticePopup"]={"update","isOpen"}, ["ui.story.gate.StartScreen"]={"start","isOpen"},
        ["ui.story.gate.DarkTitleScreenGate"]={"title","isOpen"}, ["ui.story.gate.LetterIntro"]={"letter","isOpen"},
        ["ui.story.gate.IntroCutscene"]={"intro","isActive"}, ["ui.story.ScenarioDialogue"]={"scenario","isActive"},
        ["ui.character.equip.EquipmentDetail"]={"detail","isOpen"},
        ["ui.character.hero.HeroRosterPanel"]={"roster","isVisible"}, ["ui.dev.CEPanel"]={"ce","isOpen"},
    }
    for name, cfg in pairs(map) do local key = cfg[1]; local fields = {}; fields[cfg[2]] = function() return c.modal[key] == true end; c.mock(name,fields) end
    c.deps["ui.backpack.BackpackPanel"].isLeftMode = function() return true end
    local e = c.env
    e.TownScene, e.BattleTriPage, e.BottomNav, e.StageSelectDialog, e.vg = c.page, tri, nav, select, c.vg
    e.TopBar = topBar
    for _, name in ipairs({ "BlacksmithPage","ChurchPage","TavernPage","MarketPage","BackpackPanel",
        "LootBoxPage","TaskPage","PlayerInfoPanel","RewardPopup" }) do
        for path, dep in pairs(c.deps) do if path:match("%." .. name .. "$") then e[name] = dep end end
    end
    compile(block,"actual-StandaloneBoot-expedition-injection",e)
    return tri
end
local function bootCases()
    local c = newContext(); local tri = bootFixture(c)
    eq(tri.isTerminalRaidActive(),false,"真实Tri nil raid不活跃")
    for _, raid in ipairs({ {}, { failed=true }, { retreatTimer=0.8 }, false }) do
        c.terminal=raid; eq(tri.isTerminalRaidActive(),true,"真实Tri非nil含失败退场均活跃")
        c.page.handleInput(520,1440); c.draw(c.clock.elapsedTime+0.151); eq(c.selections,0,"真实Boot终焉guard不放行")
    end
    c.terminal=nil
    for _, key in ipairs({"smith","church","talent","tavern","market","backpack","loot","task","info","reward",
        "sweep","stats","stage","confirm","equip","dungeon","tower","offline","level","update","start","title","letter","intro","scenario","detail","roster","ce"}) do
        c.modal[key]=true; c.page.handleInput(520,1610); c.draw(c.clock.elapsedTime+0.151)
        eq(c.selections,0,"真实Boot模态/标题阻塞 "..key); c.modal[key]=nil
    end
    c.tutorial=true; c.page.handleInput(520,1440); c.draw(c.clock.elapsedTime+0.151); eq(c.selections,0,"真实Boot教程阻塞")
    c.tutorial=false; c.navLocked=true; c.page.handleInput(520,1440); c.draw(c.clock.elapsedTime+0.151); eq(c.selections,0,"真实Boot全局导航锁")
    c.navLocked=false; c.tabLocked=true; c.page.handleInput(520,1440); c.draw(c.clock.elapsedTime+0.151)
    eq(c.selections,0,"真实Boot战斗页签锁保留"); c.tabLocked=false
    -- 点击后、0.15回调前新出现模态/终焉，执行真实Boot guard而非点击时缓存。
    c.page.handleInput(520,1440); c.terminal={failed=true}; c.draw(c.clock.elapsedTime+0.151)
    eq(c.selections,0,"defer期间出现失败退场仍阻塞"); c.terminal=nil
    c.page.handleInput(520,1610); c.modal.title=true; c.draw(c.clock.elapsedTime+0.151)
    eq(c.selections,0,"defer期间标题出现仍阻塞"); c.modal.title=nil
    c.triOpen=false; c.openSuccess=false; c.nav=4
    c.page.handleInput(520,1440); c.draw(c.clock.elapsedTime+0.151); eq(c.selections,0,"tri.open失败不得弹选关")
    eq(c.nav,4,"tri.open失败不切页签")
    c.openSuccess=true; c.raidOnOpen=true; c.page.handleInput(520,1440); c.draw(c.clock.elapsedTime+0.151)
    eq(c.selections,0,"打开tri期间进入终焉二次guard阻塞"); eq(c.nav,4,"二次guard失败不切页签")
    c.terminal=nil; c.raidOnOpen=false; c.triOpen=false; c.refuseNav=true
    c.page.handleInput(520,1440); c.draw(c.clock.elapsedTime+0.151); eq(c.selections,0,"切页签未生效不得弹选关")
    eq(c.nav,4,"导航拒绝保持原页签"); c.refuseNav=false; c.triOpen=false; c.nav=4
    for i=1,20 do c.page.handleInput(520,i%2==0 and 1610 or 1440) end
    c.draw(c.clock.elapsedTime+0.149); eq(c.selections,0,"Boot链也遵守0.15defer")
    c.draw(c.clock.elapsedTime+0.002); eq(c.selections,1,"真实Boot最终StageSelectDialog.openOverview()一次")
    check(type(c.topBarExpedition)=="function", "TopBar与城镇绑定同一收益总览回调")
    eq(c.nav,3,"非战斗页签切回3"); check(c.triOpen,"开启tri成功后才打开选关")
    c.page.handleInput(520,1610); c.draw(c.clock.elapsedTime+0.151); eq(c.selections,1,"已开选关重复点不重开")
    idle(c)
end
local function safetyCases()
    for _, c in ipairs(contexts) do eq(#c.forbidden,0,"生产执行没有未知require/save/cloud/IO尝试"); idle(c) end
    local c = newContext()
    for _, probe in ipairs({ function() c.env.require("main") end, function() c.env.require("core.PlayerStore") end,
        function() c.env.require("boot.StandaloneSave") end, function() c.env.File("player.json",FILE_READ) end,
        function() c.env.File("player.json",FILE_WRITE) end, function() c.env.clientCloud:Get("x") end,
        function() c.env.serverCloud:Set("x",1) end, function() c.env.cache:GetFile("main.lua") end,
        function() c.env.fileSystem:Rename("a","b") end }) do
        local n=#c.forbidden; check(not pcall(probe),"显式危险探针拒绝"); eq(#c.forbidden,n+1,"拒绝有审计")
    end
    for name in pairs(SOURCE_FILES) do eq(package.loaded[name],initialLoaded[name],"全局module cache未被更改 "..name) end
    eq(File,nativeFile,"全局File不覆写"); eq(nvgCreateImage,nativeCreateImage,"全局绘图API不覆写")
    local inputSource=source("boot.StandaloneHorizonInput")
    check(inputSource:find("if DarkTitleScreen.isOpen() then",1,true),"真实宿主保留标题分流静态证据")
    check(inputSource:find("TutorialManager.handleScreenClick",1,true),"真实宿主保留教程分流静态证据")
    local town=assert(inputSource:find("if isTap then TownScene.handleInput(dx, dy) end",1,true))
    for _, name in ipairs({"LootBoxPage","TaskPage","BackpackPanel","TalentPage","ChurchPage","TavernPage","MarketPage"}) do
        local start=assert(inputSource:find("if "..name..".isOpen()",1,true)); check(start<town,"二级页优先Town静态证据 "..name)
    end
    eq(#reads,8,"原生File只读取8份白名单源码（含白色罗盘小模块）")
    print(TAG.."LIMIT: 宿主教程/标题分流仅静态源证据；未load完整Horizon/Boot.run/main。")
end
---@type any
local reviewContext, reviewVG = nil, nil
function HandleTownExpeditionGateReview()
    local w,h,dpr=graphics:GetWidth(),graphics:GetHeight(),graphics:GetDPR()
    local lw,lh=w/dpr,h/dpr
    -- 横屏与真实宿主一样把城镇放左栏；1920x1080 => 486x1080，竖屏完整居中。
    local rw = lw > lh and lw * (486 / 1920) or lw
    local scale=math.min(rw/1080,lh/2400)
    nvgBeginFrame(reviewVG,lw,lh,dpr); nvgSave(reviewVG); nvgScale(reviewVG,scale,scale)
    nvgTranslate(reviewVG,(rw/scale-1080)*0.5,(lh/scale-2400)*0.5)
    reviewContext.page.draw(reviewVG); nvgRestore(reviewVG); nvgEndFrame(reviewVG)
end
function Start()
    if REVIEW then
        reviewVG=assert(nvgCreate(1)); check(nvgCreateFont(reviewVG,"sans","Fonts/MiSans-Regular.ttf")>=0,"真实字体加载")
        reviewContext=newContext(true,reviewVG)
        SubscribeToEvent(reviewVG,"NanoVGRender","HandleTownExpeditionGateReview")
        print(TAG.."REVIEW: actual TownScene/DrawUtil/DarkIcon/building PNG; background=false, BF/tutorial/business/save mocked")
        return
    end
    for _, test in ipairs({ {"real-source-layout-title",layoutCases}, {"handle-zero-and-missing-image-fallback",resourceCases},
        {"full-image-label-edges-outside-gap",boundaryCases}, {"compass-pure-white-not-gold",compassWhiteCases},
        {"old-buildings-level-tutorial-preserved",oldBuildingCases}, {"church-bottom-anchor-label-hit",churchPolishCases},
        {"defer-dedupe-cancel-replace",deferredCases},
        {"actual-Boot-callback-terminal-and-modal-guards",bootCases}, {"read-only-allowlist-final-safety",safetyCases} }) do
        groups=groups+1; local ok,why=pcall(test[2])
        if ok then print(TAG.."PASS "..test[1]) else failures=failures+1; log:Write(LOG_ERROR,TAG.."FAIL "..test[1].." "..tostring(why)) end
    end
    print(TAG.."RESULT "..(failures==0 and "ALL PASS" or "FAIL").." groups="..groups.." checks="..checks.." failures="..failures)
    -- 不立即Exit，让官方validate完成预算并输出JSON。
end
function Stop() if reviewVG then nvgDelete(reviewVG); reviewVG=nil end end
