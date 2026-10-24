-- 通天塔展示独立回归，沿用 scaffold-2d 生命周期。
-- 实际宿主 sans、Yoga、UI Render、KeywordText 与 PNG/原生绘制。
-- 不启动游戏、不加载玩家存档、不修改全局 nvg/time/RNG、不构建。
-- 默认使用实际 PNG；-tower-choice-native 使用真实原生特效。
-- Runtime: tests/tower_choice_presentation_test.lua -tapcode_dir=/workspace -tool_mode
-- Linux 使用 -graphicssurfaceless -nosound 验证真实绘制回调。
local TAG = "[TowerChoicePresentation]"
local totals = {checks=0, failed=0, cases=0, text=0, glyph=0, descriptions=0, native=0, png=0}
---@type NVGContextWrapper?
local vg = nil
---@type any
local fixture = nil
local sources = {} ---@type table<string,string>
local completed, frame, nativeMode = false, 0, false
local original = {text=nvgText, bounds=nvgTextBounds, random=math.random,
    seed=math.randomseed, save=nvgSave, restore=nvgRestore, spine=nvgSpineCreate}
local langs = {"zh_CN", "zh_TW", "en", "ja", "ko"}
-- 独立期望不可从生产词典/rarity反推，否则配置索引错位仍会自洽通过。
local expectedRarities = {
    zh_CN = {"普通", "优质", "稀有"}, zh_TW = {"普通", "優質", "稀有"},
    en = {"Common", "Uncommon", "Rare"}, ja = {"コモン", "アンコモン", "レア"},
    ko = {"일반", "고급", "레어"},
}
local expectedColors = {{231,231,231,255}, {106,190,115,255}, {100,161,226,255}}
local expectedFooters = {
    zh_CN = {"选择保留，战斗继续；强化从下一波生效", "稍后选择"},
    zh_TW = {"選擇保留，戰鬥繼續；強化從下一波生效", "稍後選擇"},
    en = {"Choices stay available; battle continues. Boons apply next wave.", "Choose Later"},
    ja = {"選択肢は保持され、戦闘は継続。強化は次のウェーブから有効。", "後で選ぶ"},
    ko = {"선택지는 유지되고 전투는 계속됩니다. 강화는 다음 웨이브부터 적용됩니다.", "나중에 선택"},
}
local function check(value, label)
    totals.checks = totals.checks + 1
    if not value then totals.failed = totals.failed + 1; print(TAG .. " FAIL " .. label) end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function near(actual, expected, label)
    check(math.abs(actual-expected) < .01, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function case(name, fn)
    totals.cases = totals.cases + 1
    local before = totals.failed
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then check(false, name .. " exception=" .. tostring(err)) end
    print(TAG .. " CASE " .. name .. " failures=" .. (totals.failed-before))
end
local function source(path)
    local file = assert(cache:GetFile(path), "missing actual source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines+1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function compile(path, env)
    return assert(load(assert(sources[path], path), "@" .. path, "t", env))()
end
local function privateEnvironment(overrides)
    return setmetatable(overrides or {}, {__index=_G})
end
local function upvalue(fn, key)
    for i=1,100 do
        local name, value = debug.getupvalue(fn,i)
        if name == key then return value end
        if not name then break end
    end
    error("actual production upvalue absent " .. key)
end
-- Bytecode clone changes only this instance's _ENV. Non-environment upvalues
-- remain the real library's helpers/UI/Theme. No shared Render/global is patched.
local function observeRender(fn, env)
    local copy = assert(load(string.dump(fn), "@real-widget-render-observer", "b", env))
    for i=1,100 do
        local name = debug.getupvalue(fn,i)
        if not name then break end
        if name == "_ENV" then debug.setupvalue(copy,i,env)
        else debug.upvaluejoin(copy,i,fn,i) end
    end
    return copy
end
local function rectangle(x,y,w,h) return {x=x,y=y,w=w,h=h} end
local function contains(a,b)
    return b.x >= a.x-.01 and b.y >= a.y-.01
        and b.x+b.w <= a.x+a.w+.01 and b.y+b.h <= a.y+a.h+.01
end
local function separate(a,b)
    return a.x+a.w <= b.x+.01 or b.x+b.w <= a.x+.01
        or a.y+a.h <= b.y+.01 or b.y+b.h <= a.y+.01
end
local function normalized(text) return (text:gsub("%s+", "")) end
local function fingerprint(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local entries = {}
    for key, item in pairs(value) do entries[#entries+1] = fingerprint(key) .. "=" .. fingerprint(item) end
    table.sort(entries)
    return "{" .. table.concat(entries,";") .. "}"
end

local function createFixture()
    local f = {draws={}, textRecords={}, popupRects={}, strokeColors={}, active=nil, fontSize=0,
        depth=0, fault=nil, packets={}, picks={}, errors={}, effectResults={},
        clock={elapsedTime=100}, randomCalls=0, tokens={{},{},{}}}
    local mathProxy = setmetatable({random=function()
        f.randomCalls=f.randomCalls+1; error("presentation consumed RNG",0)
    end, randomseed=function()
        f.randomCalls=f.randomCalls+1; error("presentation changed RNG seed",0)
    end}, {__index=math})
    local env = privateEnvironment({math=mathProxy, time=f.clock})
    env.nvgSave = function(ctx) original.save(ctx); f.depth=f.depth+1 end
    env.nvgRestore = function(ctx) original.restore(ctx); f.depth=f.depth-1 end
    env.nvgFontSize = function(ctx,size) f.fontSize=size; nvgFontSize(ctx,size) end
    env.nvgText = function(ctx,x,y,text,...)
        local bounds={}
        local advance=original.bounds(ctx,x,y,text,bounds)
        local record={text=text,x=x,y=y,size=f.fontSize,advance=advance,
            bounds=rectangle(bounds[1] or x,bounds[2] or y,
                (bounds[3] or x)-(bounds[1] or x),(bounds[4] or y)-(bounds[2] or y))}
        f.textRecords[#f.textRecords+1]=record
        if f.active then f.active.records[#f.active.records+1]=record end
        totals.text=totals.text+1
        if record.bounds.w>0 and record.bounds.h>0 then totals.glyph=totals.glyph+1 end
        return original.text(ctx,x,y,text,...)
    end
    env.nvgRGBA=function(r,g,b,a)
        if f.capturePlate then
            local color=nvgRGBA(r,g,b,a)
            f.colorChannels[color]={r,g,b,a}
            return color
        end
        return nvgRGBA(r,g,b,a)
    end
    env.nvgStrokeColor=function(ctx,color)
        if f.capturePlate then f.strokeColors[#f.strokeColors+1]=f.colorChannels[color] end
        return nvgStrokeColor(ctx,color)
    end
    env.nvgRoundedRect = function(ctx,x,y,w,h,r)
        if f.capturePopup then f.popupRects[#f.popupRects+1]=rectangle(x,y,w,h) end
        return nvgRoundedRect(ctx,x,y,w,h,r)
    end
    local realRequire = require
    local modules = {}
    env.require = function(name)
        if modules[name] then return modules[name] end
        if name == "systems.GameSFX" then return {play=function() end} end
        return realRequire(name)
    end
    f.language=compile("core/I18n.lua",env)
    modules["core.I18n"]=f.language
    f.presentation=compile("ui/tower/TowerPresentation.lua",env)
    modules["ui.tower.TowerPresentation"]=f.presentation
    f.keyword=compile("ui/widget/KeywordText.lua",env)
    modules["ui.widget.KeywordText"]=f.keyword
    local effectEnv=privateEnvironment({math=mathProxy})
    if not nativeMode then rawset(effectEnv,"nvgSpineCreate",false); rawset(effectEnv,"nvgSpineRender",false) end
    f.effect=compile("ui/tower/TowerOathEffect.lua",effectEnv)
    local effectProxy=setmetatable({}, {__index=f.effect})
    effectProxy.draw=function(...)
        if f.fault=="effect" then error("injected effect entry failure",0) end
        local backend=f.effect.draw(...)
        f.effectResults[#f.effectResults+1]=backend
        if backend=="native" then totals.native=totals.native+1 end
        if backend=="png" then totals.png=totals.png+1 end
        return backend
    end
    modules["ui.tower.TowerOathEffect"]=effectProxy
    local realUI=require("urhox-libs/UI")
    local uiProxy=setmetatable({}, {__index=realUI}) ---@type any
    for _,kind in ipairs({"Label","Button"}) do
        uiProxy[kind]=function(props)
            local widget=realUI[kind](props)
            local actual=observeRender(widget.Render,env)
            widget.Render=function(self,ctx)
                local previous=f.active
                local observation={widget=self,records={}}
                f.active=observation
                local ok,err=xpcall(function() actual(self,ctx) end,debug.traceback)
                f.active=previous
                self.towerTestObservation=observation
                if not ok then error(err,0) end
            end
            return widget
        end
    end
    modules["urhox-libs/UI"]=uiProxy
    local surface=require("ui.widget.DesignWidgetSurface")
    modules["ui.widget.DesignWidgetSurface"]={init=surface.init,draw=function(root,ctx,w,h)
        if f.fault=="surface" then error("injected surface entry failure",0) end
        surface.draw(root,ctx,w,h)
        f.draws[#f.draws+1]={root=root,width=w,height=h}
    end}
    f.view=compile("ui/tower/TowerChoiceView.lua",env)
    modules["ui.tower.TowerChoiceView"]=f.view
    modules["systems.ButtonFeedback"]={trigger=function() end}
    f.panel=compile("ui/tower/TowerBuffPick.lua",env)
    f.state=upvalue(f.panel.isOpen,"state")
    f.cards=upvalue(f.panel.handleClick,"kwCards")
    f.config=compile("config/TowerConfig.lua",env)
    f.snapshot=fingerprint(f.config.BUFFS)
    f.panel.init(vg)
    f.env=env
    return f
end

local function inspectWidget(widget, expected, label)
    eq(widget.props.text,expected,label .. " full actual UI text")
    local cell=widget:GetAbsoluteLayout()
    check(cell.w>0 and cell.h>0,label .. " actual Yoga dimensions")
    local observation=assert(widget.towerTestObservation,"real widget Render not observed")
    eq(#observation.records,1,label .. " real nvgText called once, no ellipse/textBox")
    local text=observation.records[1]
    eq(text.text,expected,label .. " native nvgText receives complete string")
    check(text.advance>0 and text.bounds.w>0 and text.bounds.h>0,label .. " actual nonempty host glyphs")
    check(contains(cell,text.bounds),label .. " complete native glyph bounds within actual Yoga cell " .. fingerprint(text.bounds))
    return cell
end
local function descriptionBounds(index,landscape)
    local cx,cy,w,h=fixture.view.cardRect(index,landscape)
    local x,y=cx-w*.5,cy-h*.5
    return rectangle(landscape and x+34 or x+205,landscape and y+325 or y+109,
        landscape and w-68 or 755,landscape and 125 or 124)
end
local function drawDescriptionObserved(ctx,index,choice,state,landscape,keyword)
    local f=fixture
    local rawDraw=keyword.draw
    local called=0
    local observed
    keyword.draw=function(self,vg2,text,x,y,w,size,...)
        called=called+1
        observed={text=text,x=x,y=y,w=w,size=size,first=#f.textRecords+1}
        if f.fault=="description" then error("injected description entry failure",0) end
        return rawDraw(self,vg2,text,x,y,w,size,...)
    end
    local ok,err=xpcall(function()
        f.view.drawCard(ctx,index,choice,state,landscape,keyword,1.25,f.tokens[index])
    end,debug.traceback)
    keyword.draw=rawDraw
    if not ok then error(err,0) end
    eq(called,1,"description drawn once")
    return observed
end
local function inspectDescription(ctx,choice,index,landscape,keyword,observation,label)
    local f=fixture
    local rect=descriptionBounds(index,landscape)
    eq(observation.text,f.presentation.description(choice),label .. " exact local dictionary sentence")
    check(observation.size>=16,label .. " minimum actual font16")
    check(keyword:lastHeight()<=rect.h+.01,label .. " full layout height fits, not just clip")
    local layout=keyword:_layout(ctx,observation.text,observation.w,observation.size)
    eq(layout.displayText,observation.text,label .. " KeywordText no second translation")
    local full,rendered={},{}
    for _,line in ipairs(layout.lines) do
        check(line.width<=rect.w+.01,label .. " each real measured line fits")
        for _,piece in ipairs(line.pieces) do full[#full+1]=piece.text end
    end
    eq(normalized(table.concat(full)),normalized(observation.text),label .. " all original UTF8 characters preserved in layout")
    for i=observation.first,#f.textRecords do
        local record=f.textRecords[i]
        rendered[#rendered+1]=record.text
        if normalized(record.text)~="" then
            check(record.advance>0 and record.bounds.w>0 and record.bounds.h>0,label .. " actual native description glyphs")
        end
        check(contains(rect,record.bounds),label .. " unclipped native description glyphs " .. fingerprint(record.bounds))
    end
    eq(normalized(table.concat(rendered)),normalized(observation.text),label .. " complete sentence submitted to actual native drawing")
    for _,spot in ipairs(keyword.hotspots) do
        check(contains(rect,rectangle(spot.x1,spot.y1,spot.x2-spot.x1,spot.y2-spot.y1)),label .. " keyword hit entirely in visible clip")
    end
    totals.descriptions=totals.descriptions+1
    return rect
end

local function layoutCase(ctx,lang,landscape,id)
    local f=fixture
    f.language.set(lang)
    local choice=assert(f.config.BUFFS_BY_ID[id])
    local before=fingerprint(choice)
    local state={floor=112,pending=false}
    f.draws={}; f.textRecords={}
    f.view.drawHeader(ctx,state,landscape)
    local header=f.draws[#f.draws].root
    local hc=header:GetChildren()
    local title=inspectWidget(hc[1],f.presentation.text("塔之暗契"),"title " .. lang)
    local floor=inspectWidget(hc[2],f.presentation.text("第%d层",112),"floor " .. lang)
    local hint=inspectWidget(hc[3],f.presentation.text("三枚契印 · 择一承受"),"hint " .. lang)
    check(separate(title,floor) and separate(floor,hint),"header rows separated")
    for index=1,3 do
        local keyword=f.cards[index]
        local label=lang .. "/" .. tostring(landscape) .. "/" .. id .. "/" .. index
        f.capturePlate=true;f.strokeColors={};f.colorChannels={}
        local observation=drawDescriptionObserved(ctx,index,choice,state,landscape,keyword)
        f.capturePlate=false
        local color=expectedColors[choice.quality]
        eq(fingerprint(f.strokeColors[1]),fingerprint({color[1],color[2],color[3],150}),"Picker实际卡片边框白绿蓝 "..label)
        local card=f.draws[#f.draws].root
        local cc=card:GetChildren()
        local name=inspectWidget(cc[1],f.presentation.name(choice),"name " .. label)
        local quality = inspectWidget(cc[2],expectedRarities[lang][choice.quality],"quality " .. label)
        eq(fingerprint(cc[2].props.fontColor),fingerprint(expectedColors[choice.quality]),"真实稀有度文字配色 " .. label)
        eq(f.presentation.quality(choice.quality),expectedRarities[lang][choice.quality],"品质兼容接口使用真实索引 " .. label)
        eq(f.presentation.rarity(choice.quality),expectedRarities[lang][choice.quality],"通用稀有度使用真实索引 " .. label)
        local action=inspectWidget(cc[3],f.presentation.text("铭刻"),"action " .. label)
        eq(cc[3].props.disabled,false,"normal choice action enabled")
        local box=card:GetLayout()
        local cardLocal=rectangle(0,0,box.w,box.h)
        check(contains(cardLocal,name) and contains(cardLocal,quality) and contains(cardLocal,action),"widget layout fits card " .. label)
        check(separate(name,quality) and separate(quality,action) and separate(name,action),"card UI cells do not overlap " .. label)
        local desc=inspectDescription(ctx,choice,index,landscape,keyword,observation,label)
        local cx,cy,w,h=f.view.cardRect(index,landscape)
        local originX,originY=cx-w*.5,cy-h*.5
        for _,cell in ipairs({name,quality,action}) do
            check(separate(desc,rectangle(originX+cell.x,originY+cell.y,cell.w,cell.h)),"description separate from UI cell " .. label)
        end
        check(hint.y+hint.h <= cy-h*.5+.01,"header does not overlap card " .. label)
        if index>1 then
            local _,previousY,_,previousH=f.view.cardRect(index-1,landscape)
            if not landscape then check(previousY+previousH*.5 <= cy-h*.5,"portrait cards separated") end
        end
    end
    f.view.drawFooter(ctx,state,landscape)
    local footer=f.draws[#f.draws].root:GetChildren()
    local notice=inspectWidget(footer[1],expectedFooters[lang][1],"retention notice " .. lang)
    local cancel=inspectWidget(footer[2],expectedFooters[lang][2],"cancel " .. lang)
    check(separate(notice,cancel),"notice and right-side cancel do not overlap " .. lang)
    local cx,cy,cw,ch=f.view.cancelRect(landscape)
    near(cancel.x,cx-cw*.5,"cancel actual Yoga left agrees with click rect")
    near(cancel.y,cy-ch*.5,"cancel actual Yoga top agrees with click rect")
    local _,lastY,_,lastH=f.view.cardRect(3,landscape)
    check(notice.y >= lastY+lastH*.5-.01,"footer below final card")
    eq(fingerprint(choice),before,"display never changes ID/name/desc/stats/mechanics")
    eq(f.depth,0,"view own state stack balanced")
end

local function click(index,width,height)
    local f=fixture
    local x,y=f.view.cardRect(index,width~=nil)
    if width then local scale,ox,oy=f.view.fit(width,height); x,y=x*scale+ox,y*scale+oy end
    return f.panel.handleClick(x,y,width,height)
end
local function openFixture()
    local f=fixture
    local request={runId=79,selectionId=142,floor=17,wave=4}
    local choices={f.config.BUFFS_BY_ID[20],f.config.BUFFS_BY_ID[28],f.config.BUFFS_BY_ID[30]}
    f.packets={};f.picks={};f.errors={}
    f.panel.open(17,choices,function(id,requestId)
        f.picks[#f.picks+1]={id=id,requestId=requestId}
        eq(f.state.pending,true,"locked before onPick")
    end,request,function(reply) f.errors[#f.errors+1]=reply end)
    return choices,request
end
local function modalCases(ctx)
    local f=fixture
    case("hide-show-signed-selection",function()
        local choices,request=openFixture()
        local key=f.panel.getPresentationKey()
        eq(f.panel.hide(),true,"idle hide")
        eq(f.panel.isOpen(),true,"hide not semantic close")
        eq(f.panel.isVisible(),false,"hidden")
        eq(f.state.choices,choices,"same choices table retained")
        eq(fingerprint(f.state.request),fingerprint(request),"signed identity retained")
        check(f.state.request~=request,"request copied on opening")
        check(f.panel.getPresentationKey()~=key,"hide invalidates visual key")
        eq(f.panel.handleClick(540,744),false,"hidden input not consumed")
        eq(f.panel.show(),true,"resume choice")
        f.panel.draw(ctx,1920,1080)
        eq(f.state.choices,choices,"show/draw not reroll")
        local x,y=f.view.cancelRect(true)
        eq(f.panel.handleClick(x,y,1920,1080),true,"right-side cancel consumed")
        eq(f.panel.isVisible(),false,"right cancel hides")
        eq(fingerprint(f.state.request),fingerprint(request),"right cancel retains signed identity")
        f.panel.show()
        f.panel.setSendAction(function(action,packet)
            f.packets[#f.packets+1]={action=action,packet=packet};return true
        end)
        click(2,2560,1440)
        eq(#f.packets,1,"fitted card sends once")
        local packet=f.packets[1].packet
        for key,value in pairs(request) do eq(packet[key],value,"original authority field " .. key) end
        eq(packet.buffId,28,"original buffID not presentation name")
        eq(f.packets[1].action,require("shared.Protocol").ACTION_TYPES.TOWER_PICK_BUFF,"original protocol")
        eq(f.picks[1].requestId,packet.requestId,"callback and packet request same")
        eq(f.panel.hide(),false,"pending cannot hide")
        f.panel.handleClick(x,y,1920,1080);click(1,1920,1080)
        eq(f.panel.isVisible(),true,"pending cancel does not hide")
        eq(#f.packets,1,"pending cannot double send")
        eq(f.panel.setPending(false,packet.requestId+100),false,"old receipt does not unlock")
        eq(f.state.pending,true,"old receipt leaves pending")
        eq(f.panel.setPending(false,packet.requestId,true),true,"matching uncertain failure")
        click(1,1920,1080);eq(#f.packets,1,"uncertain retry blocks other card")
        click(2,1920,1080);eq(#f.packets,2,"uncertain same-card retry sends")
        check(f.packets[2].packet.requestId~=packet.requestId,"retry new request ID")
        eq(f.panel.setPending(false,packet.requestId),false,"late old cannot consume retry")
        eq(f.panel.setPending(false,f.packets[2].packet.requestId),true,"new matching failure clears pending")
        eq(f.state.retryBuffId,28,"restriction survives retry failure")
    end)
    case("callbacks-synchronous-receipt-and-timeout",function()
        openFixture()
        f.panel.setSendAction(function(_action,packet)
            eq(f.state.pending,true,"locked before synchronous delivery")
            eq(packet.buffId,20,"original card click")
            f.panel.close();return true
        end)
        click(1)
        eq(f.panel.isOpen(),false,"synchronous success callback closes, not presentation")
        eq(#f.picks,1,"onPick once, not reward callback")
        openFixture()
        f.panel.setSendAction(function() return false end)
        click(3)
        eq(#f.errors,1,"explicit unsent reports failure once")
        eq(f.errors[1].retryOnly,false,"explicit unsent not uncertain")
        eq(f.state.pending,false,"unsent unlocks")
        f.panel.setSendAction(function() error("uncertain transport",0) end)
        click(3)
        eq(f.state.retryBuffId,30,"transport exception restricts original ID")
        openFixture()
        f.panel.setSendAction(function() return true end)
        click(1)
        local pending=f.state.pendingRequest
        f.panel.update(4.99);eq(f.state.pending,true,"below five seconds still pending")
        f.panel.update(.01);eq(f.state.pending,false,"timeout failure releases matching request")
        eq(f.state.retryBuffId,20,"timeout cannot choose another card")
        openFixture()
        click(2)
        eq(f.panel.setPending(false,pending.requestId),false,"old run receipt cannot release new request")
        f.panel.close();eq(f.panel.show(),false,"closed cannot resume")
    end)
    for _,language in ipairs(langs) do case("keyword-priority-third-card-popup-" .. language,function()
        f.language.set(language)
        openFixture();f.panel.show();f.panel.draw(ctx,1920,1080)
        local keyword=f.cards[3]
        check(#keyword.hotspots>0,"actual translated third card keyword exists")
        local spot=assert(keyword.hotspots[1])
        local x,y=(spot.x1+spot.x2)*.5,(spot.y1+spot.y2)*.5
        f.panel.handleClick(x,y,1920,1080)
        eq(keyword:isOpen(),true,"keyword click opens real explanation")
        eq(#f.picks,0,"keyword does not pick card")
        local popup=assert(keyword.popup)
        near(popup.cx,(spot.x1+spot.x2)*.5-840,"third card local popup offset")
        f.capturePopup=true;f.popupRects={};f.textRecords={}
        f.view.drawKeywordPopup(ctx,keyword,3,true)
        f.capturePopup=false
        local body=assert(f.popupRects[1],"real rounded popup body")
        check(body.x+840>=0 and body.x+body.w+840<=1920,"actual translated bubble fits host width")
        check(body.y>=0 and body.y+body.h<=1080,"actual translated bubble fits host height")
        check(body.x+840+body.w>1320,"third-card popup not displaced to first card")
        check(#f.textRecords>1,"actual explanation native glyphs")
        for _,record in ipairs(f.textRecords) do
            check(contains(body,record.bounds),"actual explanation glyphs contained in bubble")
        end
        f.panel.handleClick(360,620,1920,1080)
        eq(keyword:isOpen(),false,"next click closes bubble")
        eq(#f.picks,0,"close bubble never picks other card")
        f.panel.hide();eq(#keyword.hotspots,0,"hide clears old keyword hotspots")
        f.panel.show();f.panel.draw(ctx,1920,1080)
        check(#keyword.hotspots>0,"show redraw restores only current hotspots")
        f.panel.close()
    end) end
    case("pending-and-retry-real-widgets",function()
        f.language.set("ko")
        openFixture();f.panel.setSendAction(function() return true end);click(2,1920,1080)
        f.draws={};f.panel.draw(ctx,1920,1080)
        for i=1,3 do
            local cc=f.draws[i+1].root:GetChildren()
            eq(cc[3].props.disabled,true,"pending all real buttons disabled " .. i)
            inspectWidget(cc[3],f.presentation.text(i==2 and "正在铭刻" or "铭刻"),"pending button " .. i)
        end
        eq(f.draws[5].root:GetChildren()[2].props.disabled,true,"pending cancel UI disabled")
        local request=f.state.pendingRequest
        f.panel.setPending(false,request.requestId,true)
        f.draws={};f.panel.draw(ctx,1920,1080)
        for i=1,3 do eq(f.draws[i+1].root:GetChildren()[3].props.disabled,i~=2,"retry actual button disabled selection " .. i) end
        inspectWidget(f.draws[5].root:GetChildren()[1],f.presentation.text("仅可重试原契印"),"retry notice")
        f.panel.close()
    end)
end

local function faultCases(ctx)
    local f=fixture
    for _,kind in ipairs({"effect","surface","description","popup"}) do
        case("own-save-restore-" .. kind,function()
            f.fault=kind
            local keyword=f.keyword.new()
            local oldPopup=keyword.drawPopup
            if kind=="popup" then keyword.drawPopup=function() error("injected popup entry failure",0) end end
            local before={};local returnedBefore=nvgCurrentTransform(ctx,before)
            if type(returnedBefore)=="table" then before=returnedBefore end
            local ok,err=pcall(function()
                if kind=="popup" then f.view.drawKeywordPopup(ctx,keyword,3,true)
                else drawDescriptionObserved(ctx,1,f.config.BUFFS_BY_ID[30],{pending=false},true,keyword) end
            end)
            keyword.drawPopup=oldPopup
            check(not ok and tostring(err):find("injected",1,true),"fault propagated " .. kind)
            eq(f.depth,0,"only View-owned saves restored " .. kind)
            local after={};local returnedAfter=nvgCurrentTransform(ctx,after)
            if type(returnedAfter)=="table" then after=returnedAfter end
            check(#before>=6 and #after>=6,"actual native transform returned six entries")
            for i=1,6 do near(after[i],before[i],"native transform restored " .. kind .. "/" .. i) end
            f.fault=nil
        end)
    end
end
local function summarize()
    completed=true
    check(fixture.randomCalls==0,"isolated production RNG calls zero")
    eq(fingerprint(fixture.config.BUFFS),fixture.snapshot,"all original config unchanged")
    eq(totals.descriptions,1050,"35 IDs x5 languages x2 layouts x3 positions full glyph coverage")
    check(totals.text>0 and totals.glyph>0,"actual host nvgText and nonempty glyph evidence")
    check(nativeMode and totals.native>0 or not nativeMode and totals.png>0,"requested actual backend rendered")
    check(nvgText==original.text and nvgTextBounds==original.bounds and math.random==original.random
        and math.randomseed==original.seed and nvgSave==original.save and nvgRestore==original.restore
        and nvgSpineCreate==original.spine,"shared nvg/RNG functions untouched")
    print(string.format("%s %s cases=%d checks=%d failed=%d descriptions=%d text=%d glyph=%d native=%d png=%d",
        TAG,totals.failed==0 and "ALL PASS" or "FAILED",totals.cases,totals.checks,totals.failed,
        totals.descriptions,totals.text,totals.glyph,totals.native,totals.png))
    engine:Exit()
end
function Start()
    local ok,err=xpcall(function()
        for _,arg in ipairs(GetArguments()) do if arg=="-tower-choice-native" then nativeMode=true end end
        for _,path in ipairs({"core/I18n.lua","ui/tower/TowerPresentation.lua","ui/widget/KeywordText.lua",
            "ui/tower/TowerChoiceView.lua","ui/tower/TowerBuffPick.lua","ui/tower/TowerOathEffect.lua","config/TowerConfig.lua"}) do
            sources[path]=source(path)
        end
        require("ui.widget.DesignWidgetSurface").init()
        vg=assert(nvgCreate(1),"actual host NanoVG unavailable")
        assert(nvgCreateFont(vg,"sans","Fonts/NotoSansCJKkr-Bold.otf")>=0,"real host sans font loaded")
        -- Only sans: production does not supply sans-bold; do not mask missing button glyphs.
        check(true,"real host sans font loaded; no synthetic sans-bold fallback")
        fixture=createFixture()
        SubscribeToEvent(vg,"NanoVGRender","HandleTowerChoicePresentation")
    end,debug.traceback)
    if not ok then check(false,"startup " .. tostring(err));completed=true;engine:Exit() end
end
---@param _eventType string
---@param _eventData NanoVGRenderEventData
function HandleTowerChoicePresentation(_eventType,_eventData)
    if completed or not vg then return end
    local ctx=vg
    local begun=false
    local ok,err=xpcall(function()
        -- Mode B frame (logical dimensions+DPR); formal Panel fits Mode A design.
        -- Direct View assertions use unscaled design space, never graphics:SetMode.
        local dpr=graphics:GetDPR()
        nvgBeginFrame(ctx,graphics:GetWidth()/dpr,graphics:GetHeight()/dpr,dpr);begun=true
        frame=frame+1
        if frame<=350 then
            local id=(frame-1)%35+1
            local group=math.floor((frame-1)/35)
            local landscape=group<5
            local language=langs[group%5+1]
            case(language .. "/" .. tostring(landscape) .. "/buff" .. id,function()
                layoutCase(ctx,language,landscape,id)
            end)
        else modalCases(ctx);faultCases(ctx) end
    end,debug.traceback)
    if begun then local closed,endErr=pcall(nvgEndFrame,ctx);if not closed then check(false,"actual EndFrame " .. tostring(endErr)) end end
    if not ok then check(false,"actual render suite " .. tostring(err));summarize()
    elseif frame>350 then summarize() end
end
function Stop()
    if fixture then
        local ok,err=pcall(function() fixture.panel.destroy() end)
        if not ok then print(TAG .. " STOP FAILED " .. tostring(err)) end
    end
    require("ui.widget.DesignWidgetSurface").shutdown()
    if vg then nvgDelete(vg);vg=nil end
    print(TAG .. " STOP effect/widgets released before host VG delete")
end
