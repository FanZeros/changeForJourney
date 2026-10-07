-- 右栏展示专项：独立Runtime，不加载main/Boot，不读写玩家存档。
-- 基于scaffold-2d的Start/Stop + NanoVGRender；设计画面1080x2400，逻辑帧+DPR contain。
-- UI/Button/Label/Yoga/字体/Draw2/HeroFrame/HeroConfig均真实；只读源码在私有env编译。
-- 私有env只注入受控时钟、编队数据与Tutorial记录器；所有nvg spy先转发原生，不改_G。
-- 使用独立宿主NanoVG，像正式Boot一样只注册sans；UI私有context仅用于控件测量。
-- autoEvents=false；不能用UI私有context的sans-bold掩盖正式宿主缺字。
-- 图元记录与受控样片不等于设备触控/性能/用户审美验收。
-- 运行由主会话官方build后进行；可加-roster-visual -roster-lang=ko -roster-phase=change。
-- 日志/截图输出路径仅.git/validation/roster-power-20261007，由外层Runtime参数控制。

local TAG = "[character_roster_presentation_test]"
local tally = { assertions = 0, failures = 0, cases = 0 }
---@type table<string, any>
local state = { stage = 0, frames = 0, ended = false, visual = false, language = "zh_CN", phase = "idle" }
---@type NVGContextWrapper?
local vg = nil
---@type table<string, any>
local fixture = {}
local roots, rootSeen, imageHandles = {}, {}, {}
local originals = { require = require, time = time, random = math.random, text = nvgText, image = nvgCreateImage }
local FONT = "Fonts/NotoSansCJKkr-Bold.otf"
local LANGS = { "zh_CN", "zh_TW", "en", "ja", "ko" }
local MODES = { "default", "team", "power", "level", "rarity" }
---@type table<string, string[]>
local EXPECTED = {
    zh_CN = { "默认", "队伍", "战力", "等级", "稀有度", "升序 ↑", "降序 ↓", "固定顺序", "小队 %d", "未解锁" },
    zh_TW = { "預設", "隊伍", "戰力", "等級", "稀有度", "升序 ↑", "降序 ↓", "固定順序", "小隊 %d", "未解鎖" },
    en = { "Default", "Team", "Power", "Level", "Rarity", "Asc ↑", "Desc ↓", "Fixed", "TEAM %d", "LOCKED" },
    ja = { "標準", "部隊", "戦力", "レベル", "レア度", "昇順 ↑", "降順 ↓", "固定順", "部隊 %d", "未解放" },
    ko = { "기본", "팀", "전투력", "레벨", "희귀도", "오름차순 ↑", "내림차순 ↓", "고정", "팀 %d", "잠김" },
}

local function check(value, label)
    tally.assertions = tally.assertions + 1
    if value then print("[PASS] " .. label)
    else tally.failures = tally.failures + 1; print("[FAIL] " .. label) end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function near(actual, expected, label, epsilon)
    check(type(actual) == "number" and math.abs(actual - expected) <= (epsilon or .001),
        label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function case(label, fn)
    tally.cases = tally.cases + 1
    local ok, err = pcall(fn)
    if not ok then check(false, label .. " exception=" .. tostring(err)) end
    print(TAG .. " CASE " .. label .. " failures=" .. tally.failures)
end
local function readSource(path)
    local file = assert(cache:GetFile(path), "missing actual resource " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, entry in pairs(value) do out[key] = copy(entry) end
    return out
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function colorEqual(a, b)
    return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end
---@return table<number, any>
local function feedback(team, slot)
    local values = { fixture.presentation.getFeedback(team, slot) }
    return values
end
local function quiet(team, slot, label)
    local f = feedback(team, slot)
    near(f[3], 0, label .. " slot/selection pulse silent")
    near(f[4], 0, label .. " power pulse silent")
end
local function rememberRoot(root)
    if rootSeen[root] then return end
    rootSeen[root] = {calls=0,children={}}
    -- 记录原实例Destroy调用，再真实递归销毁；不替换成stub或在测试reset代销毁。
    local destroy=root.Destroy
    local savedChildren={}
    for _,child in ipairs(root:GetChildren()) do savedChildren[#savedChildren+1]=child end
    rootSeen[root].children=savedChildren
    root.Destroy=function(self)
        rootSeen[root].calls=rootSeen[root].calls+1
        return destroy(self)
    end
    roots[#roots+1]=root
end

local function setupFixture()
    local UI = require("urhox-libs/UI")
    local surface = require("ui.widget.DesignWidgetSurface")
    surface.init()
    vg = assert(nvgCreate(1), "actual host NanoVG context missing")
    check(vg ~= UI.GetNVGContext(), "real host context differs from UI private font context")
    check(nvgCreateFont(vg, "sans", FONT) >= 0, "real host registers only multilingual sans")
    check(nvgFindFont(vg, "sans-bold") < 0, "real host has no implicit sans-bold alias")
    fixture.UI, fixture.surface = UI, surface
    fixture.i18n = require("core.I18n")
    fixture.originalLanguage = fixture.i18n.get()
    fixture.clock = { elapsedTime = 100 }
    fixture.captures, fixture.frameCalls, fixture.textCalls, fixture.strokes, fixture.targets = {}, {}, {}, {}, {}
    fixture.imagePaths, fixture.imageFailures, fixture.imageCreates = {}, 0, 0
    fixture.active, fixture.unlocked, fixture.ready, fixture.mode, fixture.ascending = 1, 3, true, "default", false
    fixture.drag = { active = false }
    fixture.HC = require("config.HeroConfig")
    fixture.roster, fixture.powers = {}, {}
    for index, heroId in ipairs(fixture.HC.getAllIds()) do
        fixture.roster[index] = { heroId = heroId, owned = true, level = 20 + index, shards = 0 }
        fixture.powers[index] = 10000 + index * 345
    end
    fixture.teams = {
        { slots = { {state="occupied",heroId=1}, {state="occupied",heroId=2}, {state="occupied",heroId=3}, {state="empty"} } },
        { slots = { {state="occupied",heroId=4}, {state="occupied",heroId=5}, {state="empty"}, {state="empty"} } },
        { slots = { {state="occupied",heroId=6}, {state="empty"}, {state="empty"}, {state="empty"} } },
    }
    fixture.teamPowers = { { 10345, 10690, 11035, 0 }, { 11380, 11725, 0, 0 }, { 12070, 0, 0, 0 } }
    -- 故意不等于槽位sum：证明header使用宿主权威总值，不重新计算正式战力公式。
    fixture.totals = { 35001, 25002, 13003 }
    local env = setmetatable({ time = fixture.clock, H_TRI_L0 = true }, { __index = _G })
    env._G = env
    fixture.env, fixture.modules = env, {}
    local paths = {
        ["ui.character.panel.CharacterRosterPresentation"] = "ui/character/panel/CharacterRosterPresentation.lua",
        ["ui.character.panel.CharacterPanelDraw2"] = "ui/character/panel/CharacterPanelDraw2.lua",
        ["ui.widget.HeroFrame"] = "ui/widget/HeroFrame.lua",
        ["config.HeroAssetUtil"] = "config/HeroAssetUtil.lua",
        ["core.DrawUtil"] = "core/DrawUtil.lua",
    }
    local bridge = {
        init = surface.init,
        draw = function(root, ctx, width, height)
            surface.draw(root, ctx, width, height) -- actual Yoga + actual native glyph rendering first
            rememberRoot(root)
            fixture.captures[#fixture.captures + 1] = { root=root, width=width, height=height }
        end,
    }
    local tutorial = {
        isActive=function() return true end, getCurrentHighlight=function() return "character_slot_1" end,
        getNewHeroId=function() return 25 end,
        registerCharacterDetailHotspot=function(key, id, cx, cy, w, h, panel)
            fixture.targets[key] = {heroId=id,cx=cx,cy=cy,w=w,h=h,panel=panel}
        end,
        registerHotspot=function(key,cx,cy,w,h,panel)
            fixture.targets[key] = {cx=cx,cy=cy,w=w,h=h,panel=panel}
        end,
    }
    env.nvgCreateImage = function(ctx, path, flags)
        local handle = nvgCreateImage(ctx, path, flags)
        fixture.imageCreates = fixture.imageCreates + 1
        if not handle or handle <= 0 then fixture.imageFailures = fixture.imageFailures + 1 end
        if handle and handle > 0 then
            fixture.imagePaths[handle] = path
            imageHandles[handle] = true
        end
        return handle
    end
    local lastPath, lastWidth
    env.nvgRoundedRect = function(ctx, x, y, w, h, r)
        nvgRoundedRect(ctx, x, y, w, h, r)
        lastPath = { x=x,y=y,w=w,h=h,r=r }
    end
    env.nvgStrokeWidth = function(ctx, width) nvgStrokeWidth(ctx, width); lastWidth = width end
    env.nvgStroke = function(ctx)
        nvgStroke(ctx)
        if lastPath then
            fixture.strokes[#fixture.strokes + 1] = {path=copy(lastPath),width=lastWidth}
        end
    end
    env.require = function(name)
        if name == "ui.widget.DesignWidgetSurface" then return bridge end
        if name == "systems.TutorialManager" then return tutorial end
        if name == "ui.character.panel.CharacterPanel" then
            return {getEffectiveLevel=function(id)
                for _, entry in ipairs(fixture.roster) do if entry.heroId == id then return entry.level end end
                return 1
            end}
        end
        if fixture.modules[name] then return fixture.modules[name] end
        local path = paths[name]
        if not path then return originals.require(name) end
        local mod = assert(load(readSource(path), "@actual-roster/" .. path, "t", env))()
        fixture.modules[name] = mod
        if name == "ui.widget.HeroFrame" then
            local draw = mod.draw
            mod.draw = function(ctx, opts)
                draw(ctx, opts) -- actual HeroFrame draw; options only recorded AFTER real rendering
                fixture.frameCalls[#fixture.frameCalls + 1] = copy(opts)
            end
        elseif name == "core.DrawUtil" then
            local draw = mod.drawTextStroke
            mod.drawTextStroke = function(ctx,x,y,text,size,...)
                draw(ctx,x,y,text,size,...)
                fixture.textCalls[#fixture.textCalls + 1] = {x=x,y=y,text=text,size=size}
            end
        end
        return mod
    end
    fixture.presentation = env.require("ui.character.panel.CharacterRosterPresentation")
    fixture.draw = env.require("ui.character.panel.CharacterPanelDraw2")
    local D = fixture.draw
    D.setContext({
        getTeamSlots=function() return fixture.teams[fixture.active].slots end,
        getHeroRoster=function() return fixture.roster end,
        getSlotPowerCache=function() return fixture.teamPowers[fixture.active] end,
        getRosterPowerCache=function() return fixture.powers end,
        getDragState=function() return fixture.drag end, getSelectSlotState=function() return {} end,
        getHeroDeployTeams=function(id)
            local teams = {}
            for t,row in ipairs(fixture.teams) do
                for _,slot in ipairs(row.slots) do if slot.heroId == id then teams[#teams+1]=t;break end end
            end
            return teams
        end,
        getUpgradeBadgeCache=function() return {[1]=true,[4]=true} end,
        getActiveTeamIdx=function() return fixture.active end,
        getUnlockedTeamCount=function() return fixture.unlocked end,
        getTeamOccupiedCounts=function() return {3,2,1} end,
        getTeams=function() return fixture.teams end,
        getTeamPowerCaches=function() return fixture.teamPowers end,
        getTeamTotalPower=function(t) return fixture.totals[t] end,
        getRosterSort=function() return fixture.mode, fixture.ascending end,
        isHeroesDataApplied=function() return fixture.ready end,
    })
    D.initImages(vg) -- actual paths and actual image decoding, no resource substitution
    fixture.base = {teams=copy(fixture.teams),roster=copy(fixture.roster),totals=copy(fixture.totals),
        teamPowers=copy(fixture.teamPowers),powers=copy(fixture.powers)}
    print(TAG .. " actual UI context=" .. tostring(vg) .. " heroes=" .. #fixture.roster)
end

local function captureStart()
    fixture.captures, fixture.frameCalls, fixture.textCalls, fixture.strokes, fixture.targets = {}, {}, {}, {}, {}
end
local function actualDraw(detailOpen)
    captureStart()
    local before = {teams=copy(fixture.teams),roster=copy(fixture.roster),totals=copy(fixture.totals),
        teamPowers=copy(fixture.teamPowers),powers=copy(fixture.powers)}
    fixture.draw.draw(vg, 0, detailOpen or false)
    check(same(fixture.teams,before.teams) and same(fixture.roster,before.roster),
        "every actual Draw is read-only for slots/ownership/levels")
    check(same(fixture.totals,before.totals) and same(fixture.teamPowers,before.teamPowers)
        and same(fixture.powers,before.powers),"every actual Draw preserves host authoritative power caches")
end
local function toolbar()
    for _, c in ipairs(fixture.captures) do if c.height == 40 then return c.root end end
    error("actual toolbar Surface capture absent", 0)
end
local function header(team)
    local index = 0
    for _, c in ipairs(fixture.captures) do
        if c.height == 44 then index = index + 1; if index == team then return c.root end end
    end
    error("actual header Surface capture absent team=" .. team, 0)
end
local function measure(widget)
    local UI = fixture.UI
    local fit = widget.autoFitCache_
    local size = fit and fit.fontSize or UI.Theme.FontSize(widget.props.fontSize)
    nvgSave(vg); nvgResetTransform(vg)
    local face = UI.Theme.FontFace(widget.props.fontFamily, widget.props.fontWeight)
    check(nvgFindFont(vg, face) >= 0, "actual render host registered widget font " .. face)
    nvgFontFace(vg, face)
    nvgFontSize(vg, size)
    nvgTextLetterSpacing(vg, widget.props.letterSpacing or 0)
    local width = nvgTextBounds(vg, 0, 0, widget.props.text, nil, nil, false)
    nvgRestore(vg)
    return width, size
end
local function assertTextFits(widget, label)
    local width, font = measure(widget)
    local l = widget:GetAbsoluteLayout()
    local p = widget.props
    local content = l.w - (p.paddingLeft or 0) - (p.paddingRight or 0)
    check(type(width)=="number" and width>0 and width<=content+1,
        label .. " actual font width=" .. tostring(width) .. " content=" .. content .. " font=" .. font)
    print(TAG .. " TEXT " .. label .. " text=" .. p.text .. " font=" .. font .. " width=" .. width
        .. " layout=" .. l.x .. "," .. l.y .. "," .. l.w .. "," .. l.h)
end
local function assertUnchanged(label)
    check(same(fixture.teams,fixture.base.teams), label .. " slots untouched")
    check(same(fixture.roster,fixture.base.roster), label .. " roster ownership/level untouched")
    check(same(fixture.teamPowers,fixture.base.teamPowers) and same(fixture.totals,fixture.base.totals)
        and same(fixture.powers,fixture.base.powers), label .. " authority power untouched")
end

local function runToolbarLanguage(language)
    case("actual-toolbar-language-" .. language, function()
        fixture.i18n.set(language)
        local P,D = fixture.presentation,fixture.draw
        local x,y,w,h,keys,widths,gap = P.getSortGeometry()
        near(x,112,"sort left unchanged");near(y,1000,"sort top unchanged")
        near(w,856,"sort actual design width");near(h,40,"sort actual design height")
        eq(#keys,6,"five modes plus direction only")
        local previousRoot
        for _, mode in ipairs(MODES) do
            for _, ascending in ipairs({false,true}) do
                fixture.mode, fixture.ascending = mode,ascending
                actualDraw()
                local root = toolbar()
                if previousRoot then eq(root,previousRoot,"mode/language update reuses SAME UI tree") end
                previousRoot = root
                local rootLayout = root:GetLayout()
                near(rootLayout.w,w,"actual Yoga toolbar width");near(rootLayout.h,h,"actual Yoga toolbar height")
                local children = root:GetChildren()
                eq(#children,6,"actual UI.Button child count")
                local left = 0
                for index,button in ipairs(children) do
                    local l = button:GetAbsoluteLayout()
                    near(l.x,left,"actual Button x equals shared geometry " .. index)
                    near(l.y,0,"actual Button top equals hit top " .. index)
                    near(l.w,widths[index],"actual Button width equals hit width " .. index)
                    near(l.h,h,"actual Button height equals hit height " .. index)
                    local sx,sy = x+l.x+D.CONTENT_SHIFT_X,y+l.y+D.CONTENT_SHIFT_Y
                    for _,point in ipairs({{sx+l.w*.5,sy+l.h*.5},{sx+.01,sy+.01},{sx+l.w-.01,sy+l.h-.01}}) do
                        eq(D.hitTestRosterSort(point[1],point[2]),keys[index],"actual Button interior hits same key " .. index)
                    end
                    eq(D.hitTestRosterSort(sx+l.w,sy+l.h*.5),nil,"actual Button exclusive right edge/gap " .. index)
                    eq(D.hitTestRosterSort(sx+l.w*.5,sy+l.h),nil,"actual Button exclusive bottom edge " .. index)
                    local fixed = mode == "default" or mode == "team"
                    local text = index<6 and EXPECTED[language][index] or EXPECTED[language][fixed and 8 or ascending and 6 or 7]
                    eq(button.props.text,text,"five-language actual Button text " .. index)
                    eq(button:IsDisabled(),index==6 and fixed,"only fixed direction disabled " .. index)
                    eq(button.props.pointerEvents,"none","presentation cannot steal ordinary game input " .. index)
                    if index<6 then
                        check(colorEqual(button.props.borderColor,keys[index]==mode and {212,175,90,255} or {104,88,64,200}),
                            "actual selected mode border " .. index)
                    end
                    assertTextFits(button,language .. "/" .. mode .. "/" .. tostring(ascending) .. "/" .. keys[index])
                    left = left + widths[index] + gap
                end
                near(left-gap,w,"actual buttons consume exact toolbar width")
            end
        end
        local last = toolbar()
        actualDraw();eq(toolbar(),last,"unchanged draw reuses toolbar")
        assertUnchanged("toolbar language " .. language)
    end)
end

local function runHeadersLanguage(language)
    case("actual-header-language-" .. language,function()
        fixture.i18n.set(language)
        fixture.mode,fixture.unlocked = "default",3
        actualDraw()
        for team=1,3 do
            local root = header(team)
            local labels = root:GetChildren()
            eq(#labels,3,"actual team header three Labels " .. team)
            eq(labels[1].props.text,string.format(EXPECTED[language][9],team),"actual displayed squad identity " .. team)
            eq(labels[2].props.text,tostring(({3,2,1})[team]) .. "/4","actual occupied count " .. team)
            eq(labels[3].props.text,require("core.NumberUtil").format(fixture.totals[team]),"host authoritative total not slot sum " .. team)
            near(root:GetLayout().w,752,"actual header Yoga width")
            near(root:GetLayout().h,44,"actual header Yoga height")
            local left = 0
            for i,label in ipairs(labels) do
                local l = label:GetAbsoluteLayout()
                near(l.x,left,"actual header nonoverlap x " .. i)
                near(l.w,({268,72,360})[i],"actual header width " .. i)
                if i>1 then check(l.x>=labels[i-1]:GetAbsoluteLayout().x+labels[i-1]:GetAbsoluteLayout().w+25.99,
                    "actual team title/count/power separated " .. i) end
                assertTextFits(label,language .. "/header" .. team .. "/label" .. i)
                left=left+l.w+26
            end
        end
        fixture.unlocked=1;actualDraw()
        for team=2,3 do
            local labels=header(team):GetChildren()
            eq(labels[1].props.text,string.format(EXPECTED[language][9],team) .. " · " .. EXPECTED[language][10],
                "actual locked squad title " .. team)
            eq(labels[2].props.text,"","locked squad no false occupancy")
            eq(labels[3].props.text,"—","locked squad no fabricated zero power")
            check(labels[1].props.fontColor[4]<255 and labels[3].props.fontColor[4]<255,"locked header actual alpha reduced")
            assertTextFits(labels[1],language .. "/locked-title" .. team)
            local cx,cy=fixture.draw.avatarCenter(team,1)
            eq(fixture.draw.hitTestAvatarSlot(cx+fixture.draw.CONTENT_SHIFT_X,cy+fixture.draw.CONTENT_SHIFT_Y,false),nil,
                "locked actual avatar does not accept hit")
        end
        local locked=0
        for _,frame in ipairs(fixture.frameCalls) do if frame.state=="locked" then locked=locked+1 end end
        eq(locked,8,"eight actual HeroFrames locked, not just Labels")
        fixture.unlocked=3;actualDraw()
        for team=1,3 do quiet(team,1,"first unlocked snapshot " .. team) end
        assertUnchanged("header language " .. language)
    end)
end

local function runInteractions()
    case("actual-hover-press-cancel-and-disabled",function()
        local P,D=fixture.presentation,fixture.draw
        fixture.mode,fixture.ascending="power",false
        actualDraw()
        local x,y,_,h= P.getSortGeometry()
        local button=toolbar():GetChildren()[3]
        local l=button:GetAbsoluteLayout()
        local px,py=x+l.x+l.w*.5+D.CONTENT_SHIFT_X,y+h*.5+D.CONTENT_SHIFT_Y
        local normal=copy(button:ResolveStateBgColor())
        D.setSortInteraction(px,py,false);actualDraw()
        button=toolbar():GetChildren()[3]
        check(button.state.hovered and not button.state.pressed,"actual Button hover state")
        check(not colorEqual(button:ResolveStateBgColor(),normal),"actual Button hover background changes")
        D.setSortInteraction(px,py,true);actualDraw()
        check(button.state.hovered and button.state.pressed,"actual Button press state")
        check(colorEqual(button:ResolveStateBgColor(),button.props.pressedBackgroundColor),"actual Button pressed color priority")
        D.clearSortInteraction();actualDraw()
        check(not button.state.hovered and not button.state.pressed,"cancel clears actual Button states")
        check(colorEqual(button:ResolveStateBgColor(),normal),"cancel restores actual Button background")
        local direction=toolbar():GetChildren()[6]
        local dl=direction:GetAbsoluteLayout()
        local dx=x+dl.x+dl.w*.5+D.CONTENT_SHIFT_X
        for _,mode in ipairs({"default","team"}) do
            fixture.mode=mode
            D.setSortInteraction(dx,py,true);actualDraw()
            direction=toolbar():GetChildren()[6]
            check(direction:IsDisabled() and not direction.state.hovered and not direction.state.pressed,
                "disabled direction ignores hover/pressed " .. mode)
            check(colorEqual(direction:ResolveStateBgColor(),direction.props.disabledBackgroundColor),"disabled actual color wins")
        end
        fixture.mode="level"
        D.setSortInteraction(dx,py,true);actualDraw()
        check(direction.state.pressed and not direction:IsDisabled(),"numeric direction becomes enabled and pressable")
        D.draw(vg,0,true)
        for _,b in ipairs(toolbar():GetChildren()) do check(not b.state.hovered and not b.state.pressed,"detail-open cancels sorting press") end
        local cx,cy=D.avatarCenter(1,1);cx,cy=cx+D.CONTENT_SHIFT_X,cy+D.CONTENT_SHIFT_Y
        D.setTeamInteraction(cx,cy,false);actualDraw()
        local f=feedback(1,1)
        check(f[1] and not f[2],"actual avatar hover observed")
        local hoverStroke
        for _,s in ipairs(fixture.strokes) do if s.path.w==182 and s.path.h==182 and s.path.r==18 then hoverStroke=s end end
        check(hoverStroke and hoverStroke.width>=2,"hover draws real avatar outside edge, no scaling")
        D.setTeamInteraction(cx,cy,true);actualDraw();f=feedback(1,1)
        check(f[1] and f[2],"actual avatar press observed")
        local pressStroke
        for _,s in ipairs(fixture.strokes) do if s.path.w==172 and s.path.h==172 and s.path.r==18 then pressStroke=s end end
        check(pressStroke and pressStroke.width==4,"press draws actual inset edge, no moved geometry")
        D.clearTeamInteraction();actualDraw();f=feedback(1,1)
        check(not f[1] and not f[2],"team cancel clears hover/pressed")
        D.setTeamInteraction(cx,cy,true);D.draw(vg,0,true);f=feedback(1,1)
        check(not f[1] and not f[2],"detail-open cancels actual avatar press")
        local titleLayout=header(1):GetChildren()[1]:GetAbsoluteLayout()
        local ax,ay=D.avatarCenter(1,4)
        -- Header Surface位置由真实头像左缘和既有行top推导，不沿用旧固定159空隙。
        local headerX=ax-D.AV_SIZE*.5+D.CONTENT_SHIFT_X
        local headerY=ay-D.AV_SIZE*.5-30-56-4+D.CONTENT_SHIFT_Y
        local hx,hy=headerX+titleLayout.x+titleLayout.w*.5,headerY+titleLayout.y+titleLayout.h*.5
        eq(D.hitTestTeamHeader(hx,hy),1,"actual title Label center hits header")
        eq(D.hitTestTeamHeader(headerX+.01,headerY+.01),1,"actual header top-left interior hits")
        eq(D.hitTestTeamHeader(headerX+752-.01,headerY+44-.01),1,"actual header bottom-right interior hits")
        eq(D.hitTestTeamHeader(headerX-.01,hy),nil,"actual header left gap excluded")
        eq(D.hitTestTeamHeader(headerX+752,hy),nil,"actual header exclusive right edge excluded")
        eq(D.hitTestTeamHeader(hx,headerY+44),nil,"actual header exclusive bottom edge excluded")
        D.setTeamInteraction(hx,hy,true);actualDraw();f=feedback(1,nil)
        check(f[1] and f[2],"header press feedback distinct from avatar")
        eq(feedback(1,1)[2],false,"header press does not press any avatar")
        D.clearTeamInteraction();actualDraw();assertUnchanged("all interactions")
    end)
end

local function observeAll()
    for team=1,3 do
        fixture.presentation.observe(team,fixture.teams[team].slots,fixture.totals[team],fixture.active,function(id)
            for _,entry in ipairs(fixture.roster) do if entry.heroId==id then return entry.level end end
            return 0
        end,fixture.ready,team>fixture.unlocked)
    end
    fixture.presentation.finishObservation(fixture.active)
end
local function restoreBase()
    fixture.teams,fixture.roster=copy(fixture.base.teams),copy(fixture.base.roster)
    fixture.totals,fixture.teamPowers,fixture.powers=copy(fixture.base.totals),copy(fixture.base.teamPowers),copy(fixture.base.powers)
    fixture.active,fixture.unlocked,fixture.ready=1,3,true
end
local function runObservation()
    case("real-snapshot-wallclock-change-level-power-expire-reset",function()
        local P=fixture.presentation
        restoreBase();P.reset();fixture.clock.elapsedTime=100
        observeAll();actualDraw()
        for t=1,3 do for s=1,4 do quiet(t,s,"first snapshot "..t.."/"..s) end end
        fixture.clock.elapsedTime=100.1
        fixture.teams[1].slots[1]={state="occupied",heroId=7}
        observeAll()
        quiet(1,1,"change trigger exact time")
        fixture.clock.elapsedTime=100.25;actualDraw()
        local change=feedback(1,1)
        check(change[3]>0 and change[3]<1,"real hero replacement produces short positive pulse")
        near(change[4],0,"hero replacement alone does not fabricate power increase")
        quiet(1,2,"neighbor slot unchanged");quiet(2,1,"other team unchanged")
        local before=copy(fixture.teams)
        actualDraw();local twice=feedback(1,1)
        near(twice[3],change[3],"same time second actual Draw cannot accelerate/restart pulse")
        near(twice[4],change[4],"same time second actual Draw power sample stable")
        check(same(before,fixture.teams),"two Draws do not rewrite slots")
        fixture.clock.elapsedTime=100.7;actualDraw();quiet(1,1,"replacement expired")
        local oldLevel=fixture.roster[2].level
        fixture.clock.elapsedTime=101;fixture.roster[2].level=oldLevel+1;observeAll()
        fixture.clock.elapsedTime=101.2;actualDraw()
        check(feedback(1,2)[3]>0,"real existing hero level growth produces short pulse")
        near(feedback(1,1)[3],0,"upgrade does not animate unrelated replacement slot")
        fixture.clock.elapsedTime=101.7;actualDraw();quiet(1,2,"upgrade expired")
        fixture.clock.elapsedTime=102;fixture.totals[2]=fixture.totals[2]+700;observeAll()
        fixture.clock.elapsedTime=102.2;actualDraw()
        local gain=feedback(2,nil)
        check(gain[4]>0 and gain[4]<1,"real host team total gain produces positive header pulse")
        eq(header(2):GetChildren()[3].props.text,require("core.NumberUtil").format(fixture.totals[2]),
            "actual glowing header still shows authority final value")
        check(header(2):GetChildren()[3].props.fontColor[2]>219,"actual header power color contains pulse")
        near(feedback(2,1)[3],0,"total-only growth does not pulse unchanged hero")
        actualDraw();near(feedback(2,nil)[4],gain[4],"same clock multiple header Draws stable")
        fixture.clock.elapsedTime=102.7;actualDraw();quiet(2,1,"power expired")
        fixture.clock.elapsedTime=103;fixture.totals[2]=fixture.totals[2]-100;fixture.roster[2].level=oldLevel;observeAll()
        fixture.clock.elapsedTime=103.2;actualDraw();quiet(1,2,"level decrease not growth");quiet(2,1,"power decrease not growth")
        fixture.clock.elapsedTime=104;fixture.active=3;observeAll()
        fixture.clock.elapsedTime=104.2;actualDraw()
        check(feedback(3,nil)[3]>0,"active team selection pulse")
        near(feedback(1,nil)[3],0,"old active team no selection pulse")
        fixture.clock.elapsedTime=104.8;actualDraw();quiet(3,nil,"selection expires")
        fixture.ready=false;fixture.clock.elapsedTime=105;fixture.totals[1]=999999;observeAll()
        fixture.ready=true;fixture.clock.elapsedTime=105.2;observeAll();actualDraw()
        quiet(1,1,"ready false clears cold snapshot, hydration first silent")
        fixture.unlocked=1;fixture.clock.elapsedTime=106;observeAll()
        fixture.totals[2]=999999;fixture.unlocked=3;fixture.clock.elapsedTime=106.2;observeAll();actualDraw()
        quiet(2,1,"locked snapshot cleared, unlocking first silent")
        P.setTeamInteraction(1,1,true);P.setSortInteraction(120,1020,true)
        P.reset();fixture.clock.elapsedTime=107;observeAll();actualDraw()
        for t=1,3 do
            local f=feedback(t,1)
            check(not f[1] and not f[2],"reset clears interaction "..t)
            quiet(t,1,"reset fresh baseline "..t)
        end
        restoreBase();P.reset();observeAll();actualDraw();assertUnchanged("observation restored fixture")
        -- 全未ready时切active，后续首次真实快照不能被误当成队选择变化。
        restoreBase();P.reset();fixture.ready=false;fixture.active=1;actualDraw()
        fixture.active=2;fixture.ready=true;fixture.clock.elapsedTime=108;actualDraw()
        fixture.clock.elapsedTime=108.2;actualDraw()
        for t=1,3 do
            quiet(t,nil,"cold active switch first header snapshot "..t)
            for s=1,4 do quiet(t,s,"cold active switch first slot snapshot "..t.."/"..s) end
        end
        -- 已有一队快照而目标队一直锁定，unlock+active首次同样只能静默建基线。
        restoreBase();P.reset();fixture.unlocked=1;fixture.active=1;fixture.clock.elapsedTime=109;actualDraw()
        fixture.unlocked=3;fixture.active=3;fixture.clock.elapsedTime=109.1;actualDraw()
        fixture.clock.elapsedTime=109.3;actualDraw()
        quiet(3,nil,"unlock active first header snapshot")
        for s=1,4 do quiet(3,s,"unlock active first slot snapshot "..s) end
        restoreBase();P.reset();observeAll();actualDraw();assertUnchanged("cold-active fixture restored")
    end)
end

local function runActualGeometry()
    case("actual-draw-25-real-heroes-176-148-five-by-five-tutorial",function()
        restoreBase();fixture.presentation.reset();fixture.i18n.set("zh_CN");actualDraw()
        local D=fixture.draw
        eq(#fixture.roster,25,"actual HeroConfig exactly25 roster heroes")
        local rosterFrames,avatars={},{}
        for _,frame in ipairs(fixture.frameCalls) do
            if frame.nameLabel then rosterFrames[#rosterFrames+1]=frame else avatars[#avatars+1]=frame end
        end
        eq(#rosterFrames,25,"actual HeroFrame draws all25 names/icons")
        eq(#avatars,12,"actual HeroFrame draws three teams four slots")
        near(D.AV_SIZE,176,"actual team avatar176 unchanged")
        near(D.ROSTER_ICON,148,"actual roster avatar148 unchanged")
        eq(D.MAX_PER_ROW,5,"actual five columns unchanged")
        near(D.CONTENT_SHIFT_X,0,"actual horizontal offset unchanged")
        near(D.CONTENT_SHIFT_Y,144,"actual vertical offset unchanged")
        near(D.SCROLL_BOTTOM+D.CONTENT_SHIFT_Y,2400,"actual scroll clip bottom visible")
        for i,frame in ipairs(rosterFrames) do
            eq(frame.heroId,fixture.roster[i].heroId,"actual roster id "..i)
            eq(frame.nameLabel,fixture.HC.get(frame.heroId).name,"actual HeroConfig name "..i)
            near(frame.size,148,"actual roster icon size "..i)
            local row=math.ceil(i/5)
            near(frame.cy,D.ROW1_CY+(row-1)*D.ROW_SPACING,"actual five-row y "..i)
            check(frame.cy-frame.size*.5>=D.SCROLL_TOP and frame.cy+D.ROSTER_BOTTOM_DY<=D.SCROLL_BOTTOM,
                "actual icon/name/power fits unclipped row "..i)
        end
        for t=1,3 do for s=1,4 do
            local cx,cy=D.avatarCenter(t,s)
            local ht,hs=D.hitTestAvatarSlot(cx+D.CONTENT_SHIFT_X,cy+D.CONTENT_SHIFT_Y,false)
            eq(ht,t,"actual avatar hit team "..t.."/"..s);eq(hs,s,"actual avatar hit slot "..t.."/"..s)
        end end
        local target=assert(fixture.targets.character_slot_1)
        local cx,cy=D.avatarCenter(1,1)
        eq(target.heroId,1,"actual old tutorial entry retains hero identity")
        near(target.cx,cx+D.CONTENT_SHIFT_X,"actual tutorial x not moved")
        near(target.cy,cy+D.CONTENT_SHIFT_Y,"actual tutorial y not moved")
        near(target.w,176,"actual tutorial width retained");near(target.h,176,"actual tutorial height retained")
        eq(target.panel,"right","actual tutorial source right")
        check(fixture.targets.character_new_hero~=nil,"actual old new-hero roster hotspot retained")
        eq(fixture.imageFailures,0,"all actual initImages/HeroFrame/25 icons decoded")
        local iconCount=0
        for _,path in pairs(fixture.imagePaths) do if path:find("UI_icon_hero_",1,true) then iconCount=iconCount+1 end end
        eq(iconCount,25,"25 actual HeroAssetUtil icons loaded")
        local creates=fixture.imageCreates
        actualDraw();eq(fixture.imageCreates,creates,"unchanged actual Draw does not recreate image handles")
        assertUnchanged("actual geometry")
        eq(require,originals.require,"native require unchanged")
        eq(time,originals.time,"native time unchanged")
        eq(math.random,originals.random,"native gameplay random unchanged")
        eq(nvgText,originals.text,"native glyph binding unchanged")
        eq(nvgCreateImage,originals.image,"native image binding unchanged")
    end)
end

local function verifyReleased(label)
    for index,root in ipairs(roots) do
        local record=rootSeen[root]
        eq(record.calls,1,label .. " production Destroy exactly once root " .. index)
        eq(root.node,nil,label .. " production frees actual Yoga root " .. index)
        eq(#root:GetChildren(),0,label .. " production empties actual children " .. index)
        for childIndex,child in ipairs(record.children) do
            eq(child.node,nil,label .. " production frees actual child Yoga node " .. index .. "/" .. childIndex)
        end
    end
end
local function runLifecycle()
    case("production-reset-real-destroy-and-rebuild-no-double-free",function()
        local P=fixture.presentation
        actualDraw()
        local old=toolbar()
        check(old.node~=nil,"actual toolbar Yoga node alive before production reset")
        P.reset();verifyReleased("first reset")
        P.reset();verifyReleased("second idempotent reset")
        actualDraw()
        local new=toolbar()
        check(new~=old and new.node~=nil,"reset then actual Draw builds fresh live toolbar")
        eq(rootSeen[new].calls,0,"fresh toolbar not prematurely Destroyed")
        fixture.draw.resetPresentation();verifyReleased("Draw2 explicit reset relay")
        actualDraw()
        check(toolbar().node~=nil,"Draw after Draw2 reset remains usable")
        P.reset();verifyReleased("final production reset")
        assertUnchanged("production lifecycle")
    end)
end

local function summarize()
    if state.ended then return end
    state.ended=true
    print(TAG .. (tally.failures==0 and " ALL PASS" or " FAIL") .. " cases=" .. tally.cases
        .. " assertions=" .. tally.assertions .. " failures=" .. tally.failures .. " frames=" .. state.frames)
    engine:Exit()
end
local function runStage()
    state.stage=state.stage+1
    local stage=state.stage
    if stage<=5 then runToolbarLanguage(LANGS[stage])
    elseif stage<=10 then runHeadersLanguage(LANGS[stage-5])
    elseif stage==11 then runInteractions()
    elseif stage==12 then runObservation()
    elseif stage==13 then runActualGeometry()
    elseif stage==14 then runLifecycle() end
end
local function setupVisual()
    fixture.i18n.set(state.language);fixture.mode,fixture.ascending="power",false
    fixture.clock.elapsedTime=100;observeAll()
    if state.phase~="idle" then
        fixture.clock.elapsedTime=100.1
        fixture.teams[1].slots[1]={state="occupied",heroId=7}
        fixture.roster[2].level=fixture.roster[2].level+1
        fixture.totals[1]=fixture.totals[1]+888
        observeAll()
        fixture.clock.elapsedTime=state.phase=="change" and 100.3 or 101
    end
    print(TAG .. " VISUAL phase="..state.phase.." language="..state.language.." design=1080x2400")
end

function Start()
    local ok,err=pcall(function()
        for _,arg in ipairs(GetArguments()) do
            if arg=="-roster-visual" then state.visual=true end
            local language=arg:match("^%-roster%-lang=(.+)$")
            if language then assert(EXPECTED[language],"unsupported roster language");state.language=language end
            local phase=arg:match("^%-roster%-phase=(.+)$")
            if phase then assert(({idle=true,change=true,["end"]=true})[phase],"unsupported roster phase");state.phase=phase end
        end
        setupFixture()
        check(nvgFindFont(vg,"sans")>=0,"actual multilingual UI font registered once")
        assert(cache:Exists(FONT),"real multilingual font resource absent")
        if state.visual then setupVisual() end
        SubscribeToEvent(vg,"NanoVGRender","HandleRosterPresentationRender")
    end)
    if not ok then check(false,"suite Start "..tostring(err));summarize() end
end

---@param _eventType string
---@param _eventData NanoVGRenderEventData
function HandleRosterPresentationRender(_eventType,_eventData)
    if state.ended or not vg then return end
    state.frames=state.frames+1
    local dpr=graphics:GetDPR()
    local width,height=graphics:GetWidth()/dpr,graphics:GetHeight()/dpr
    local begun=false
    local ok,err=pcall(function()
        -- 宿主frame独立于UI私有测量context，覆盖正式绘制时的字体别名条件。
        nvgBeginFrame(vg,width,height,dpr);begun=true
        if state.visual then
            local scale=math.min(width/1080,height/2400)
            nvgSave(vg);nvgTranslate(vg,(width-1080*scale)*.5,(height-2400*scale)*.5)
            nvgScale(vg,scale,scale)
            nvgBeginPath(vg);nvgRect(vg,0,0,1080,2400);nvgFillColor(vg,nvgRGBA(13,11,9,255));nvgFill(vg)
            actualDraw()
            if state.frames==1 then
                case("actual-visual-captures-"..state.language.."-"..state.phase,function()
                    local root=toolbar();eq(#root:GetChildren(),6,"visual actual buttons")
                    for _,b in ipairs(root:GetChildren()) do assertTextFits(b,"visual toolbar") end
                    for t=1,3 do
                        local labels=header(t):GetChildren()
                        eq(labels[3].props.text,require("core.NumberUtil").format(fixture.totals[t]),"visual authority team "..t)
                        for _,label in ipairs(labels) do assertTextFits(label,"visual team "..t) end
                    end
                    local f=feedback(1,1)
                    if state.phase=="change" then check(f[3]>0 and f[4]>0,"visual actual change slot/power pulse")
                    else near(f[3],0,"visual idle/end slot pulse zero");near(f[4],0,"visual idle/end power pulse zero") end
                    eq(fixture.imageFailures,0,"visual real resources decoded")
                end)
            end
            nvgRestore(vg)
        else runStage() end
    end)
    if begun then
        local ended,frameErr=pcall(nvgEndFrame,vg)
        if not ended then check(false,"actual EndFrame "..tostring(frameErr)) end
    end
    if not ok then check(false,"actual frame "..tostring(err)) end
    if not ok or (state.visual and state.frames>=150) or (not state.visual and state.stage>=14) then summarize() end
end

function Stop()
    if fixture.presentation then fixture.presentation.reset() end
    -- 先断言生产reset真正释放；测试不得代Destroy后声称生产无泄漏。
    local cleanupFailures=tally.failures
    verifyReleased("Stop production reset")
    if tally.failures>cleanupFailures then
        print(TAG .. " STOP FAIL production UI cleanup; prior ALL PASS does not override this failure")
    end
    -- 仅在已明确失败后清残留测试私有根，避免污染进程退出；已释放对象不重复Destroy。
    for _,root in ipairs(roots) do
        if root.node then
            print(TAG .. " STOP residual fixture root cleanup (NOT production success)")
            pcall(function() root:Destroy() end)
        end
    end
    roots,rootSeen={},{}
    if vg then for handle in pairs(imageHandles) do nvgDeleteImage(vg,handle) end end
    imageHandles={}
    if fixture.i18n and fixture.originalLanguage then fixture.i18n.set(fixture.originalLanguage) end
    if fixture.surface then fixture.surface.shutdown() end -- owns UI private context only
    if vg then nvgDelete(vg) end -- separate host context, released exactly once
    vg=nil
    print(TAG .. " STOP native time/require/random unchanged=" .. tostring(time==originals.time and require==originals.require and math.random==originals.random))
end
