-- UI显示专项：真实load显示模块，绘图/存档/业务依赖隔离为内存probe。
-- 不证明GPU像素/实机触控；Start始终Exit，错误写LOG_ERROR供validate捕捉。
local TAG = "[ui_damage_polish_test]"
local assertions, failures = 0, 0
local function check(ok, label) assertions = assertions + 1; assert(ok, label) end
local function eq(a, b, label) check(a == b, label .. " actual=" .. tostring(a) .. " expected=" .. tostring(b)) end
local function near(a, b, label) check(math.abs(a - b) < 0.0001, label) end
local function noop() end
local function source(path)
    local file = assert(cache:GetFile(path), "missing source " .. path)
    local rows = {}
    while not file:IsEof() do rows[#rows + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(rows, "\n")
end
---@return any
local function fixture()
    local f = { modules = {}, loaded = {}, calls = {}, font = 40, color = {}, stack = {},
        clock = { elapsedTime = 100 }, imagePaths = {}, nextImage = 1, language = "zh_CN", measurements = 0 }
    local env = setmetatable({ time = f.clock }, { __index = _G })
    f.env = env
    function f.record(kind, data) data.kind = kind; f.calls[#f.calls + 1] = data end
    function f.clear() f.calls = {} end
    function f.load(name)
        if f.modules[name] then return f.modules[name] end
        if f.loaded[name] then return f.loaded[name] end
        local path = name:gsub("%.", "/") .. ".lua"
        local module = assert(load(source(path), "@" .. path, "t", env))()
        f.loaded[name] = module
        return module
    end
    env.require = f.load
    function f.width(text)
        local width = 0
        for _, code in utf8.codes(text) do
            width = width + f.font * (code < 128 and (code == 87 and 0.95 or code == 105 and 0.25 or 0.52) or 1)
        end
        return width
    end
    for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFill", "nvgStroke",
        "nvgStrokeColor", "nvgStrokeWidth", "nvgMoveTo", "nvgLineTo", "nvgClosePath",
        "nvgTranslate", "nvgScale", "nvgGlobalAlpha", "nvgResetScissor", "nvgScissor", "nvgTextBox" }) do env[name] = noop end
    env.nvgRGBA = function(r, g, b, a) return { r, g, b, a } end
    env.nvgFillColor = function(_, color) f.color = color; f.fillPaint = nil end
    env.nvgFillPaint = function(_, paint) f.fillPaint = paint end
    env.nvgImagePattern = function(_, _, _, _, _, _, handle) return { image = handle } end
    env.nvgFontFace = noop
    env.nvgFontSize = function(_, size) f.font = size end
    env.nvgTextAlign = noop
    env.nvgTextBounds = function(_, _, _, text)
        f.measurements = f.measurements + 1
        return f.width(text)
    end
    env.nvgText = function(_, x, y, text)
        f.record("text", { x = x, y = y, text = text, width = f.width(text), color = f.color,
            font = f.font, fillPaint = f.fillPaint })
    end
    env.nvgSave = function()
        f.stack[#f.stack + 1] = { font = f.font, color = f.color, fillPaint = f.fillPaint }
    end
    env.nvgRestore = function()
        local state = assert(table.remove(f.stack), "unbalanced save/restore")
        f.font, f.color, f.fillPaint = state.font, state.color, state.fillPaint
    end
    env.nvgIntersectScissor = function(_, x, y, w, h) f.record("clip", { x = x, y = y, w = w, h = h }) end
    env.nvgCreateImage = function(_, path)
        if f.missingImage and path:find(f.missingImage, 1, true) then return -1 end
        local handle = f.nextImage; f.nextImage = handle + 1; f.imagePaths[handle] = path
        return handle
    end
    -- 图像设置FillPaint并留下白色乘色，仿真真实DrawUtil边界；不能只记录旧FillColor。
    local draw = { drawImageCentered = function(vg, handle, x, y, w, h)
        if handle < 0 then return end
        f.record("image", { handle = handle, path = f.imagePaths[handle], x = x, y = y, w = w, h = h })
        env.nvgFillColor(vg, env.nvgRGBA(255,255,255,255))
        env.nvgFillPaint(vg, env.nvgImagePattern(vg,x,y,w,h,0,handle))
    end,
        drawRoundedRectCentered = noop, drawNineSlice = noop,
        hitTest = function(x, y, cx, cy, w, h) return math.abs(x-cx) <= w*.5 and math.abs(y-cy) <= h*.5 end }
    draw.drawTextStroke = function(vg, x, y, text, font) env.nvgFontSize(vg, font); env.nvgText(vg, x, y, text) end
    f.modules["core.DrawUtil"] = draw
    f.modules["core.I18n"] = { lookup = function(text)
        return f.translations and f.translations[text] or text end, get = function() return f.language end,
        format = string.format, displayText = env.nvgText, displayBounds = env.nvgTextBounds }
    f.modules["core.DarkIcon"] = { drawNine = noop, drawIconDark = noop, drawQualityBg = noop,
        QUALITY_TRIM = { {}, {}, {}, {}, {}, {} } }
    f.modules["systems.ButtonFeedback"] = { begin = function() return false end, finish = noop, trigger = noop }
    f.modules["core.GameState"] = {}
    f.modules["systems.TutorialManager"] = { isActive = function() return false end, isBuildingUnlocked = function() return true end }
    return f
end
local function textJoined(f)
    local texts = {}
    for _, call in ipairs(f.calls) do
        if call.kind == "text" and not (call.color[1] == 48 and call.color[2] == 48) then
            texts[#texts + 1] = call.text
        end
    end
    return table.concat(texts)
end
local function hasColor(f, color)
    for _, call in ipairs(f.calls) do
        if call.kind == "text" and call.color[1] == color[1] and call.color[2] == color[2] then return true end
    end
    return false
end
local function assertWidths(f, x, w, label)
    for _, call in ipairs(f.calls) do
        if call.kind == "text" then
            check(call.x >= x - .001, label .. " left bound")
            check(call.x + call.width <= x + w + .001, label .. " right bound " .. call.text)
        end
    end
    eq(#f.stack, 0, label .. " save/restore balanced")
end
local function tavernFixture()
    local f = fixture()
    local longName = "WiiiiWW中文远征者长英雄名称_abcdefghijklmnopqrstuvwxyz"
    f.modules["config.HeroConfig"] = { HEROES = { [1] = { name = longName }, [2] = { name = "短名" },
        [3] = { name = "普通中文英雄名很长" }, [4] = { name = "末尾队员" } } }
    local group = { items = { {type="hero",heroId=1,weight=99}, {type="hero",heroId=2,weight=12},
        {type="hero",heroId=3,weight=3}, {type="hero",heroId=4,weight=1} } }
    local standard = { Pity = { SSR_THRESHOLD=80 }, Cost = { SINGLE_TICKET=1, TEN_TICKET=10, SINGLE_DIAMOND=180 },
        getPoolGroup = function(q) return q == 3 and group or nil end }
    local stellar = { POOL_ID="stellar", Pity={SR_THRESHOLD=10,SSR_THRESHOLD=60,UR_THRESHOLD=120},
        Probability={[1]=52,[2]=41,[3]=5,[4]=1}, QUALITY_R=1,QUALITY_SR=2,QUALITY_SSR=3,QUALITY_UR=4,
        Cost = { SINGLE_TICKET=1, TEN_TICKET=10, SINGLE_DIAMOND=900 }, UI={ticketIconPath="test.png"},
        getPoolGroup = function(q) return q == 4 and group or nil end }
    f.modules["config.GachaConfig"], f.modules["config.UrGachaConfig"] = standard, stellar
    f.env.fileSystem = { FileExists = function() return false end }
    f.env.File = function() error("UI说明不得打开玩家文件") end
    return f, group, longName
end
local function tavernWrapCase()
    local f, group, longName = tavernFixture()
    local info = f.load("ui.tavern.TavernInfo")
    for _, pool in ipairs({"standard","stellar"}) do
        for _, width in ipairs({790, 360}) do
            f.clear()
            info.draw({}, pool, {x=100,y=200,w=width,h=10000}, 0)
            assertWidths(f, 100, width, pool .. " " .. width)
            local text = textJoined(f)
            check(text:find(longName, 1, true) ~= nil, "long UTF8 hero name retained " .. pool)
            check(text:find("末尾队员",1,true) ~= nil, "last hero retained " .. pool)
            check(text:find(pool == "stellar" and "每120次" or "每80次", 1, true) ~= nil, "pity rule retained")
            check(text:find(pool == "stellar" and "52%" or "55%", 1, true) ~= nil, "base probability retained")
            check(hasColor(f, {230,169}), "highlight survives wrap")
            eq(group.items[1].weight,99,"group weights remain unchanged")
        end
    end
    f.clear()
    local vg = {}
    info.draw(vg,"standard",{x=100,y=200,w=360,h=10000},0)
    local count = f.measurements
    f.clear(); info.draw(vg,"standard",{x=100,y=200,w=360,h=10000},0)
    eq(f.measurements,count,"same context/language/layout uses stable cached widths")
    f.language = "en"
    f.translations = { ["每80次招募必定获得史诗级远征队员"] = "An Epic expedition teammate is guaranteed within every 80 summons.",
        ["史诗"] = "Epic", ["[史诗]" .. longName] = "[Epic]WiiiiWW Legendary Adventurer With A Very Long Hero Name" }
    f.clear(); info.draw(vg,"standard",{x=100,y=200,w=360,h=10000},0)
    check(f.measurements > count,"language change invalidates cached layout")
    check(textJoined(f):find("within every 80 summons",1,true) ~= nil,"full sentence translated before splitting")
    assertWidths(f,100,360,"English sentence")
    info.clearCache()
    f.language, f.translations = "zh_CN", nil
    f.clear()
    local scroll = info.draw(vg,"stellar",{x=100,y=200,w=360,h=200},100000)
    check(scroll>0 and scroll<100000,"scroll clamps to measured content including rules")
    check(textJoined(f):find("末尾队员",1,true) ~= nil,"bottom scroll reaches last reward")
    assertWidths(f,100,360,"bottom scroll")
end
local function tavernPopupCase()
    local f, group = tavernFixture()
    for i = 1, 8 do group.items[#group.items + 1] = {type="hero",heroId=1,weight=1} end
    local pool = "standard"
    local popup = f.load("ui.tavern.TavernPopups")
    popup.setContext({getSelectedPoolId=function() return pool end})
    popup.openInfo(); f.clock.elapsedTime=101
    f.clear(); popup.drawAll({})
    local clip
    for _, call in ipairs(f.calls) do if call.kind == "clip" then clip=call end end
    check(clip~=nil,"popup delegates genuine content clip")
    near(clip.x,145,"combined scroll left")
    near(clip.y,908,"combined scroll top")
    near(clip.w,790,"actual width budget")
    near(clip.h,684,"rules and rewards use full original span")
    local first = textJoined(f)
    popup.handleScroll(-1000); f.clear(); popup.drawAll({})
    check(textJoined(f)~=first,"existing wheel scroll advances combined content")
    popup.handleDragBegin(500,1200); popup.handleDragMove(500,1800); popup.handleDragEnd(500,1800)
    f.clear(); popup.drawAll({}); eq(#f.stack,0,"popup transform restored")
    popup.resetAll(); pool="stellar"; popup.openInfo(); f.clock.elapsedTime=102
    f.clear(); popup.drawAll({})
    check(textJoined(f):find("120",1,true)~=nil,"stellar rule routes to real helper")
    eq(popup.isBlocking(),true,"modal blocking retained")
end
local function equipmentCase(missing)
    local f = fixture()
    if missing then f.missingImage = "套装图标/v3" end
    f.env.nvgRoundedRect = function(_, x, y, w, h)
        f.record("rect", { x = x, y = y, w = w, h = h })
    end
    local setDef = {id="TESTSET",name="测试套装",color={232,208,122,255}}
    local equip = { templateId="TEST",quality=2,name="测试装备",type="主手",level=1 }
    local config = { ITEMS={TEST={setId="TESTSET"}},QUALITY={{name="普通"},{name="稀有"}},SLOT_NAME={} }
    f.modules["config.EquipmentConfig"] = config
    f.modules["config.EquipmentSetConfig"] = {get=function(id) return id=="TESTSET" and setDef or nil end,
        getSetIdForTemplate=function(tpl) return tpl and tpl.setId end }
    f.modules["ui.hud.popup.SettingsPanel"] = {isSetIconsEnabled=function() return false end}
    f.modules["systems.EquipmentSystem"] = {getAscendLevel=function() return 0 end}
    f.modules["config.AffixConfig"], f.modules["config.BlacksmithConfig"], f.modules["core.I18nEquipmentText"] = {}, {}, {}
    local kw = {beginFrame=noop,draw=noop,drawAttribute=noop}
    f.modules["ui.widget.KeywordText"] = {new=function() return kw end}
    local layout = {COMPACT_BG_W=600,COMPACT_AFFIX_TITLE_FONT=26,COMPACT_AFFIX_GAP=8,COMPACT_ICON_CY=168,
        COMPACT_ICON_SIZE=132,COMPACT_NAME_Y=34,COMPACT_PAD_TOP=28,COMPACT_QUALITY_Y=122,COMPACT_STAT_Y0=248,
        COMPACT_TYPE_Y=78,DESC_TOP=980,REF_AFFIX_GAP=8,REF_AFFIX_GAP_TOP=12,REF_AFFIX_ROW_H=44,
        REF_AFFIX_TEXT_X=578,REF_AFFIX_TITLE_FONT=30,REF_AFFIX_TITLE_X=578,REF_AFFIX_TITLE_Y=1206,
        REF_ARROW_GAP=8,REF_ARROW_SIZE=32,REF_BADGE_CX=560,REF_BADGE_H=44,REF_BADGE_W=36,
        REF_BG_CX=807,REF_BTN_CX=807,REF_BTN_FONT=40,REF_BTN_H=100,REF_BTN_W=410,REF_DEC_BTN_FONT=40,
        REF_DEC_BTN_GAP=18,REF_DEC_BTN_H=100,REF_DEC_BTN_W=300,REF_ICON_CX=903,REF_ICON_CY=809,
        REF_ICON_SIZE=290,REF_NAME_FONT=44,REF_NAME_X=578,REF_NAME_Y=630,REF_QUALITY_FONT=30,
        REF_QUALITY_X=578,REF_QUALITY_Y=861,REF_STAT_BG_H=44,REF_STAT_BG_Y0=1000,REF_STAT_FONT=36,
        REF_STAT_GAP=8,REF_STAT_TEXT_X=578,REF_STAT_VAL_X=1000,REF_TYPE_FONT=30,REF_TYPE_X=578,
        REF_TYPE_Y=706,SET_GAP=10,SET_TITLE_H=42}
    local det = {heroId=1,slot=nil,descScrollY=0}
    local panels = f.load("ui.character.equip.EquipmentDetailDraw").create({
        detState=det,setKw={kw,kw,kw},affixKw=kw,layout=layout,qualityColor={{255,255,255},{0,255,0}},affixBadgeKey={},
        getImages=function() return {powerIcon=-1,arrowUp=-1,arrowDown=-1,btnGreen=-1,btnRed=-1,lock=-1,affixBadge={}} end,
        drawImageCentered=f.modules["core.DrawUtil"].drawImageCentered,drawTextStroke=f.modules["core.DrawUtil"].drawTextStroke,
        calcEquipPower=function() return 123 end,getEquipIcon=function() return -1 end,
        getStatName=noop,formatStatValue=noop,layoutButtons=function() return 1461,0 end,clampDescScroll=noop,
        compactViewHeight=function() return 500 end,compactAffixLayout=function() return 200,220,250 end,
        compactSetLines=function()
            if not config.ITEMS.TEST.setId then return nil,{} end
            return setDef,{{text=setDef.name.."  2/6"},{tier=2,desc="套装效果",active=true}}
        end,compactSetRowHeight=function() return 40 end,compactContentBottom=function() return 250 end,
        compactButtonRow=function() return 430,807,410,100 end })
    local function checkIcon(label)
        local icon
        for _, call in ipairs(f.calls) do if call.kind=="image" and call.path=="image/套装图标/v3/SET_TESTSET.png" then icon=call end end
        if missing then
            eq(icon,nil,label.." missing image is not drawn")
            local fallback
            for _, call in ipairs(f.calls) do
                if call.kind=="rect" and call.w==32 and call.h==32 then fallback=call end
            end
            check(fallback~=nil,label.." visible semantic fallback frame remains")
        else
            check(icon~=nil,label.." shows semantic set icon with badge preference disabled")
            near(icon.w,32,label.." icon width")
        end
        eq(#f.stack,0,label.." transforms balanced")
    end
    for _, actions in ipairs({true,false}) do
        f.clear(); panels.drawCompactPanel({},equip,"穿戴",actions); checkIcon("compact "..tostring(actions))
        local title
        for _, call in ipairs(f.calls) do if call.kind=="text" and call.text:find("2/6",1,true) then title=call end end
        check(title~=nil,"compact title retained")
        eq(title.fillPaint,nil,"compact title restored solid text fill instead of stale image paint")
        eq(title.color[1],setDef.color[1],"compact title original set color R retained")
        eq(title.color[2],setDef.color[2],"compact title original set color G retained")
        eq(title.color[3],setDef.color[3],"compact title original set color B retained")
        check(title.x>507+28+8+32,"text moved beyond icon")
        check(title.x+title.width<=507+600-28,"title width fits panel")
    end
    f.clear(); panels.drawEquipPanel({},equip,0,807,1050,600,1000,nil,false,"",false,false,false)
    checkIcon("large")
    for _, call in ipairs(f.calls) do
        if call.kind=="text" and call.text==setDef.name then
            eq(call.fillPaint,nil,"large set title restores solid fill")
            eq(call.color[1],255,"large set title retains caller white R")
            eq(call.color[2],255,"large set title retains caller white G")
            eq(call.color[3],255,"large set title retains caller white B")
        end
    end
    setDef.name=string.rep("很长套装名称",10)
    f.clear(); panels.drawCompactPanel({},equip,"",false)
    for _, call in ipairs(f.calls) do
        if call.kind=="text" and call.text:find("2/6",1,true) then check(call.x+call.width<=1071.001,"long set title measured to available width") end
    end
    config.ITEMS.TEST.setId=nil
    f.clear(); panels.drawCompactPanel({},equip,"",false)
    for _, call in ipairs(f.calls) do check(call.kind~="image" or not (call.path and call.path:find("套装图标",1,true)),"non-set no semantic icon") end
end

local REVIEW, REVIEW_POOL, REVIEW_SCROLL = false, "standard", 0
for _, argument in ipairs(GetArguments()) do
    if argument == "-review" then REVIEW = true end
    local pool = argument:match("^%-pool=(.+)$")
    if pool then REVIEW_POOL = pool end
    local scroll = argument:match("^%-scroll=(.+)$")
    if scroll then REVIEW_SCROLL = tonumber(scroll) or 0 end
end
---@type any
local reviewVg, reviewInfo = nil, nil
function HandleUIDamagePolishReview()
    if not reviewVg then return end
    local width, height = graphics:GetWidth(), graphics:GetHeight()
    local scale = math.min(width / 1080, height / 2400)
    nvgBeginFrame(reviewVg, width, height, 1)
    nvgSave(reviewVg)
    nvgTranslate(reviewVg, (width - 1080 * scale) * .5, (height - 2400 * scale) * .5)
    nvgScale(reviewVg, scale, scale)
    nvgBeginPath(reviewVg); nvgRect(reviewVg,0,0,1080,2400)
    nvgFillColor(reviewVg,nvgRGBA(18,16,14,255)); nvgFill(reviewVg)
    require("core.DarkIcon").drawNine(reviewVg,"panel",65,636.5,950,1051,{titleH=180})
    nvgFontFace(reviewVg,"sans"); nvgFontSize(reviewVg,60)
    nvgTextAlign(reviewVg,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
    nvgFillColor(reviewVg,nvgRGBA(244,237,224,255)); nvgText(reviewVg,540,705,"招募说明")
    nvgFontSize(reviewVg,40); nvgFillColor(reviewVg,nvgRGBA(216,201,180,255))
    nvgText(reviewVg,540,828,REVIEW_POOL=="stellar" and "星辰招募卡池" or "常规招募卡池")
    -- 真实配置/英雄名/字体/绘图；显示层自身不引用GameState或File。
    reviewInfo.draw(reviewVg,REVIEW_POOL,{x=145,y=908,w=790,h=684},REVIEW_SCROLL)
    nvgRestore(reviewVg); nvgEndFrame(reviewVg)
end
function Stop()
    if reviewVg then nvgDelete(reviewVg); reviewVg=nil end
end

function Start()
    if REVIEW then
        reviewVg=assert(nvgCreate(1))
        assert(nvgCreateFont(reviewVg,"sans","Fonts/MiSans-Regular.ttf")>=0,"review font unavailable")
        reviewInfo=require("ui.tavern.TavernInfo")
        SubscribeToEvent(reviewVg,"NanoVGRender","HandleUIDamagePolishReview")
        print(TAG.." REVIEW actual TavernInfo/config/fonts/NanoVG; no Boot/GameState/payments/player saves")
        return
    end
    for _, case in ipairs({{"实际宽度彩色折行/语言缓存",tavernWrapCase},
        {"真实弹窗规则奖励统一滚动",tavernPopupCase},{"大小详情套装语义图标",equipmentCase},
        {"大小详情缺图语义fallback",function() equipmentCase(true) end}}) do
        local ok, err = pcall(case[2])
        if ok then print(TAG.." PASS "..case[1])
        else failures=failures+1; print(TAG.." FAIL "..case[1].." "..tostring(err)); log:Write(LOG_ERROR,tostring(err)) end
    end
    print(TAG..(failures==0 and " ALL PASS" or " FAILED").." assertions="..assertions.." failures="..failures)
    engine:Exit()
end
