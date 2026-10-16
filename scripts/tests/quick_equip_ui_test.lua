-- 独立 Runtime / NanoVGRender 分帧专项；沿 InventoryCurationFixture 的私有源码环境。
-- 真实 CharacterDetail.handleInput/open/close/switchHero + CharacterDetailDraw.draw；
-- 真实 I18n、ButtonFeedback、DarkIcon、DrawUtil、NanoVG/Noto 字体与字墨测量。
-- 显式截断：Bridge pending/Action 为观察 spy；属性数据、配装下半页、图片与其他页面非被测对象。
-- 不启动 main/Boot，不读 .project/玩家档，不使用 File/FS/RNG；不声称 GPU/设备验收。
-- 调度/安装提交及 CMH 完成音效由 quick_equip_async_test 另测，本文件不伪造成功回执。
local TAG = "[quick_equip_ui_test] "
local vg = nil ---@type NVGContextWrapper?
local state = {} ---@type table
local steps = {} ---@type table[]
local checks, frame, ioCalls, rngCalls = 0, 0, 0, 0
local function check(value, why)
    checks = checks + 1
    assert(value, why)
end
local function noop() end
local function denyIO()
    ioCalls = ioCalls + 1
    error("quick-equip UI forbids File/FS/IO")
end
local function prepare()
    local F = require("tests.InventoryCurationFixture")
    local h = F.new()
    state.h = h
    h.env.File, h.env.FileSystem, h.env.GetFileSystem = denyIO, denyIO, denyIO
    h.env.fileSystem = setmetatable({}, { __index = function() return denyIO end })
    h.env.io = setmetatable({}, { __index = function() return denyIO end })
    h.env.os.execute, h.env.os.remove, h.env.os.rename = denyIO, denyIO, denyIO
    h.env.math.random = function() rngCalls = rngCalls + 1; error("RNG forbidden") end
    h.env.math.randomseed = h.env.math.random
    h.env.cache = { GetFile = denyIO, GetResource = denyIO }
    h.env.H_SEAM_BACK = false -- 测原有页面返回键，不启动横屏宿主或改坐标。
    local requireSource = h.require
    local function loadModule(name)
        assert(name ~= "main" and not name:match("^boot[./]"), "Boot/main forbidden")
        return requireSource(name)
    end
    h.env.require, h.require = loadModule, loadModule
    state.pending, state.pendingReads = false, 0
    state.sent, state.sounds, state.uiClicks = {}, {}, {}
    state.warehouse, state.panel = {}, {}
    local owned = { [1] = {level=100,exp=0,maxExp=10,shards=0},
        [2] = {level=100,exp=0,maxExp=10,shards=0} }
    local bag = { inventory={}, equipped={} }
    h.mocks["runtime.LocalActionBridge"] = { isQuickEquipPending = function()
        state.pendingReads = state.pendingReads + 1
        return state.pending
    end }
    local AT = h.require("shared.Protocol").ACTION_TYPES
    state.AT = AT
    h.mocks["runtime.GameAction"] = { sendAction = function(action, params)
        check(action == AT.EQUIP_ALL_BEST or action == AT.UNEQUIP_ALL, "only requested batch action")
        state.sent[#state.sent+1] = {action=action, heroId=params.heroId, frame=frame}
        if action == AT.EQUIP_ALL_BEST then
            check(not state.pending, "spy rejects double submission while pending")
            state.pending = true -- 只观察 UI；不执行 handler/install/CMH，不当成真实调度。
        end
        return true
    end }
    h.mocks["systems.GameSFX"] = {
        play=function(name) state.sounds[#state.sounds+1]=name end,
        playUIClick=function(kind) state.uiClicks[#state.uiClicks+1]=kind end,
    }
    h.mocks["core.PlayerStore"] = { Get=function(name)
        if name == "equipment" then return bag end
        if name == "heroes" then return {roster=owned} end
        error("unexpected PlayerStore module "..tostring(name))
    end }
    h.mocks["core.GameState"] = {}
    h.mocks["runtime.ClientDispatcher"] = {}
    h.mocks["systems.EquipmentPower"] = { getContext=function() error("upgrade scoring outside UI scope") end }
    h.mocks["systems.EquipmentSystem"] = { getHeroSlots=function(data, hero) return data.equipped[tostring(hero)] end }
    h.mocks["ui.character.panel.CharacterPanel"] = {getOwnedHero=function(id) return owned[id] end}
    h.mocks["ui.character.equip.EquipmentBag"] = { init=noop, isOpen=function() return false end, draw=noop }
    h.mocks["ui.character.equip.EquipmentDetail"] = { isOpen=function() return false end, dismissHover=noop }
    h.mocks["ui.widget.ImageCache"] = {init=noop}
    h.mocks["config.HeroAssetUtil"] = {ensureCard=function() return -1 end}
    h.mocks["ui.character.hero.AwakeningPanel"] = {
        initImages=noop, setClassIcons=noop, setOwnedDataGetter=noop, reset=noop, draw=noop,
    }
    h.mocks["ui.character.hero.AwakeningArtwork"] = {close=noop}
    h.mocks["ui.character.hero.HeroScenario"] = {onOpenHero=noop}
    h.mocks["ui.church.ChurchPage"] = {hasAdvanceForHero=function() return false end}
    h.mocks["systems.TutorialManager"] = {isActive=function() return false end}
    h.mocks["ui.character.detail.CharacterDetailAttrs"] = {STAT_LAYOUT={}, collectAttributes=noop}
    local panel = {
        reset=function(hero, slot) state.panel.hero, state.panel.slot=hero,slot end,
        endSideDrag=noop, draw=noop, drawSetCodex=noop,
        isAttributeTogglePoint=function() return false end,
        onSlotChanged=function(slot, hero) state.panel.hero, state.panel.slot=hero,slot end,
        handleInput=function(x,y,hero) state.panel.input={x=x,y=y,hero=hero};return true end,
    }
    h.mocks["ui.character.detail.CharacterDetailEquip"] = panel
    h.mocks["ui.backpack.BackpackPanel"] = {
        acquireForEquipment=function(hero) state.warehouse.owner=hero end,
        releaseForEquipment=function() state.warehouse.owner=nil end,
        setEquipmentSlotFilter=function(slot,hero) state.warehouse.slot,state.warehouse.owner=slot,hero end,
    }
    -- 仅图片装饰不加载；真实 init 设置内部所有 -1 句柄，避免绕过被测绘制分支。
    h.env.nvgCreateImage = function()
        check(not state.animationTrace,"animation never loads a texture")
        return -1
    end
    h.env.nvgCreateFont = function() error("animation/user modules must reuse initialized font") end
    state.Detail = h.require("ui.character.detail.CharacterDetail")
    state.Draw = h.require("ui.character.detail.CharacterDetailDraw")
    state.Lang = h.require("core.I18n")
    state.BF = h.require("systems.ButtonFeedback")
    state.Detail.init(vg)
    state.Detail.setContext({getOwnedData=function(id) return owned[id] end,
        getHeroRoster=function() return {{heroId=1,owned=true},{heroId=2,owned=true}} end})
    local D = state.Draw
    check(D.BTN_EQUIP_CX==869 and D.BTN_EQUIP_CY==105 and D.BTN_BATCH_W==304
        and D.BTN_BATCH_H==100, "keep existing detail button coordinates")
    -- 仅观察并委托原生API，字体/Bounds/文字绘制不以估算或替身替代。
    local style = {size=0,face="",align=0,color={0,0,0,0},alpha=1,
        strokeWidth=1,strokeColor={0,0,0,1},lineCap=NVG_BUTT,clip=false}
    local stack = {}
    local function colorValues(color) return {color.r,color.g,color.b,color.a} end
    local function observe(name,args)
        if state.animationTrace then state.animationTrace[#state.animationTrace+1]={name=name,args=args} end
    end
    -- 全部记录器仍委托真实NanoVG；仅Activity.draw执行窗口收集几何，不抄其算法作替身。
    for _,name in ipairs({"nvgBeginPath","nvgRoundedRect","nvgCircle","nvgArc","nvgMoveTo",
        "nvgLineTo","nvgClosePath","nvgStroke"}) do
        local native=_G[name]
        h.env[name]=function(ctx,...)
            observe(name,{...})
            return native(ctx,...)
        end
    end
    h.env.nvgStrokeWidth=function(ctx,width)
        style.strokeWidth=width;observe("nvgStrokeWidth",{width});return nvgStrokeWidth(ctx,width)
    end
    h.env.nvgStrokeColor=function(ctx,color)
        style.strokeColor=colorValues(color);observe("nvgStrokeColor",style.strokeColor)
        return nvgStrokeColor(ctx,color)
    end
    h.env.nvgLineCap=function(ctx,cap) style.lineCap=cap;return nvgLineCap(ctx,cap) end
    h.env.nvgGlobalAlpha=function(ctx,alpha) style.alpha=alpha;return nvgGlobalAlpha(ctx,alpha) end
    h.env.nvgIntersectScissor=function(ctx,x,y,w,height)
        style.clip={x,y,w,height};observe("nvgIntersectScissor",{x,y,w,height})
        return nvgIntersectScissor(ctx,x,y,w,height)
    end
    h.env.nvgScissor=function(ctx,x,y,w,height) style.clip={x,y,w,height};return nvgScissor(ctx,x,y,w,height) end
    h.env.nvgResetScissor=function(ctx) style.clip=false;return nvgResetScissor(ctx) end
    h.env.nvgFontFace = function(ctx, face) style.face=face;return nvgFontFace(ctx,face) end
    h.env.nvgFontSize = function(ctx, size) style.size=size;return nvgFontSize(ctx,size) end
    h.env.nvgTextAlign = function(ctx, align) style.align=align;return nvgTextAlign(ctx,align) end
    h.env.nvgFillColor = function(ctx, color)
        style.color={color.r,color.g,color.b,color.a}
        observe("nvgFillColor",style.color)
        return nvgFillColor(ctx,color)
    end
    h.env.nvgFill = function(ctx)
        observe("nvgFill",{})
        state.nativeFills=(state.nativeFills or 0)+1
        return nvgFill(ctx)
    end
    h.env.nvgSave = function(ctx) stack[#stack+1]=F.copy(style);return nvgSave(ctx) end
    h.env.nvgRestore = function(ctx)
        style=assert(table.remove(stack),"balanced observed NVG state")
        return nvgRestore(ctx)
    end
    h.env.nvgText = function(ctx,x,y,text,last)
        if y==D.BTN_EQUIP_CY and (x==D.BTN_EQUIP_CX or x==D.BTN_UNEQUIP_CX) then
            local bounds, transform = {}, {}
            local width=nvgTextBounds(ctx,x,y,text,bounds)
            local returned=nvgCurrentTransform(ctx,transform)
            if type(returned)=="table" then transform=returned end
            local record=F.copy(style)
            record.text,record.x,record.y,record.width=text,x,y,width
            record.bounds,record.transform=bounds,transform
            state.texts[#state.texts+1]=record
            for _,code in utf8.codes(text) do
                local glyph={}
                local advance=nvgTextBounds(ctx,0,0,utf8.char(code),glyph)
                if code~=32 then
                    check(advance>0 and #glyph==4 and glyph[3]>glyph[1] and glyph[4]>glyph[2],
                        "actual nonspace glyph ink U+"..string.format("%X",code))
                end
            end
        end
        return nvgText(ctx,x,y,text,last)
    end
    local Activity=h.require("ui.character.detail.QuickEquipActivity")
    local realActivity=Activity.draw
    state.animationCalls={}
    local function matrix(ctx)
        local result={}
        local returned=nvgCurrentTransform(ctx,result)
        return type(returned)=="table" and returned or result
    end
    Activity.draw=function(ctx,cx,cy,width,height,now)
        check(not state.animationTrace,"animation recorder cannot nest")
        local beforeStyle,beforeMatrix,beforeDepth=F.copy(style),matrix(ctx),#stack
        local trace={}
        state.animationTrace=trace
        realActivity(ctx,cx,cy,width,height,now) -- 被测原实现，不替换图形算法。
        state.animationTrace=nil
        F.same(style,beforeStyle,"animation restores font/fill/stroke/alpha/clip")
        F.same(matrix(ctx),beforeMatrix,"animation restores actual native transform")
        check(#stack==beforeDepth,"animation balances NVG save/restore")
        local record={cx=cx,cy=cy,w=width,h=height,now=now,trace=trace,textsBefore=#state.texts}
        state.animationCalls[#state.animationCalls+1]=record
        return record
    end
    local function traceKey(trace)
        local parts={}
        for _,entry in ipairs(trace) do
            parts[#parts+1]=entry.name
            for _,value in ipairs(entry.args) do parts[#parts+1]=tostring(value) end
        end
        return table.concat(parts,"|")
    end
    state.probeAnimation=function()
        -- A→B→A：即使中间换时间，返回A仍逐调用/颜色精确一致；并验证宿主非默认状态。
        local sent,sounds=#state.sent,#state.uiClicks
        h.env.nvgSave(vg)
        h.env.nvgFontSize(vg,23);h.env.nvgFillColor(vg,nvgRGBA(9,19,29,170))
        h.env.nvgStrokeWidth(vg,3.25);h.env.nvgLineCap(vg,NVG_ROUND)
        h.env.nvgStrokeColor(vg,nvgRGBA(61,71,81,190));h.env.nvgGlobalAlpha(vg,0.63)
        h.env.nvgIntersectScissor(vg,720,65,290,80)
        nvgTranslate(vg,7,9);nvgScale(vg,0.9,0.95)
        local a=Activity.draw(vg,D.BTN_EQUIP_CX,D.BTN_EQUIP_CY,D.BTN_BATCH_W,D.BTN_BATCH_H,1200)
        local b=Activity.draw(vg,D.BTN_EQUIP_CX,D.BTN_EQUIP_CY,D.BTN_BATCH_W,D.BTN_BATCH_H,1200.37)
        local repeatA=Activity.draw(vg,D.BTN_EQUIP_CX,D.BTN_EQUIP_CY,D.BTN_BATCH_W,D.BTN_BATCH_H,1200)
        F.same(a.trace,repeatA.trace,"same elapsedTime reproduces exact geometry and opacity after B")
        check(traceKey(a.trace)~=traceKey(b.trace),"different elapsedTime changes real arc/illumination trace")
        local arcsA,arcsB,colorsA,colorsB={},{},{},{}
        for _,pair in ipairs({{a.trace,arcsA,colorsA},{b.trace,arcsB,colorsB}}) do
            for _,entry in ipairs(pair[1]) do
                if entry.name=="nvgArc" then pair[2][#pair[2]+1]=entry.args end
                if entry.name=="nvgStrokeColor" or entry.name=="nvgFillColor" then pair[3][#pair[3]+1]=entry.args end
            end
        end
        check(#arcsA==2 and #arcsB==2 and arcsA[1][4]~=arcsB[1][4],"actual short arcs rotate across time")
        check(cjson.encode(colorsA)~=cjson.encode(colorsB),"pulse/diamonds change actual color opacity")
        h.env.nvgRestore(vg)
        check(#state.sent==sent and #state.uiClicks==sounds and #state.sounds==0,
            "animation neither dispatches nor plays click/business sounds")
    end
    local Dark = h.require("core.DarkIcon")
    local drawNine = Dark.drawNine
    Dark.drawNine = function(ctx,kind,x,y,w,height,options)
        local fills=state.nativeFills or 0
        local result=drawNine(ctx,kind,x,y,w,height,options)
        if w==D.BTN_BATCH_W and height==D.BTN_BATCH_H then
            state.plates[#state.plates+1]={x=x,y=y,w=w,h=height,accent=F.copy(options.accent),
                fills=(state.nativeFills or 0)-fills}
        end
        return result
    end
    local function count(action)
        local n=0;for _,item in ipairs(state.sent) do if item.action==action then n=n+1 end end;return n
    end
    local function click(x,y) check(state.Detail.handleInput(x,y),"real handleInput consumes tested point") end
    local function equip() click(D.BTN_EQUIP_CX,D.BTN_EQUIP_CY) end
    local function add(label,busy,before,after)
        steps[#steps+1]={label=label,busy=busy,before=before,after=after}
    end
    local texts={zh_CN="计算中…",zh_TW="計算中…",en="Calculating…",ja="計算中…",ko="계산 중…"}
    for _,language in ipairs({"zh_CN","zh_TW","en","ja","ko"}) do
        local lang=language
        add(lang.." idle",false,function()
            state.language,state.expectedBusy=lang,texts[lang]
            check(state.Lang.set(lang),"real language selected "..lang)
            state.Detail.forceClose();state.Detail.open(1,"equip")
            h:setTime(h.clock+1)
            check(not state.pending,"fresh idle before request")
        end)
        add(lang.." request",true,function()
            local n,c=count(AT.EQUIP_ALL_BEST),#state.uiClicks
            equip()
            check(count(AT.EQUIP_ALL_BEST)==n+1 and state.sent[#state.sent].heroId==1,"one request for visible hero")
            check(state.pending and #state.sounds==0,"no immediate install or other named success sound")
            check(#state.uiClicks==c+1 and state.uiClicks[#state.uiClicks]==2,"original BF generic click is allowed")
        end)
        add(lang.." held across frames",true,function()
            local n,c=count(AT.EQUIP_ALL_BEST),#state.uiClicks
            for _=1,3 do equip() end
            check(count(AT.EQUIP_ALL_BEST)==n and #state.uiClicks==c,"busy blocks duplicate action and release bounce only")
            local u=count(AT.UNEQUIP_ALL)
            click(D.BTN_UNEQUIP_CX,D.BTN_UNEQUIP_CY)
            check(count(AT.UNEQUIP_ALL)==u+1 and state.sent[#state.sent].heroId==1,
                "busy does not block original unequip-all")
            check(state.pending,"unrelated action does not clear pending spy")
        end)
        add(lang.." recover",false,function()
            state.pending=false -- 显式 pending 观察边界；不是 CMH/服务端完成模拟。
        end)
    end
    -- busy 不成为整页门禁：槽位/子页输入/页签/左右切人/返回/重开仍走原函数。
    add("pending slot and lower-panel input",true,function()
        equip()
        local slot=D.DT_SLOTS[1]
        click(slot.cx,slot.cy)
        check(state.warehouse.slot==slot.slot and state.panel.slot==slot.slot,"busy preserves real slot/filter navigation")
        click(540,1800)
        check(state.panel.input and state.panel.input.hero==1,"busy reaches original equip-panel delegate")
    end)
    add("pending change tab and hero",nil,function()
        click(D.BTN_TAB_ATTR_CX,D.BTN_TAB_ATTR_CY)
        check(not state.Detail.isEquipTab() and state.warehouse.owner==nil,"attr tab releases warehouse while busy")
        click(D.ARROW_BG_RIGHT_CX,D.ARROW_CY)
        check(state.Detail.getHeroId()==2,"busy does not block right hero arrow")
        click(D.ARROW_BG_LEFT_CX,D.ARROW_CY)
        check(state.Detail.getHeroId()==1,"busy does not block left hero arrow")
        click(D.BTN_TAB_EQUIP_CX,D.BTN_TAB_EQUIP_CY)
        check(state.Detail.isEquipTab() and state.warehouse.owner==1,"equip tab restored while busy")
    end)
    add("pending return closes original detail",nil,function()
        click(D.BTN_BACK_CX,D.BTN_BACK_CY)
        check(state.Detail.getHeroId()==nil and not state.Detail.isEquipTab(),"busy return starts real close lifecycle")
        check(state.warehouse.owner==nil and state.pending,"closing releases warehouse not pending")
        h:setTime(h.clock+1)
    end,function() check(not state.Detail.isOpen(),"real draw completes original close animation") end)
    add("pending reopen another hero",true,function()
        state.Detail.open(2,"equip");h:setTime(h.clock+1)
        local n=count(AT.EQUIP_ALL_BEST)
        equip()
        check(state.Detail.getHeroId()==2 and count(AT.EQUIP_ALL_BEST)==n,"busy remains global after reopen/switch hero")
    end)
    add("pending cleared, request enabled again",true,function()
        state.pending=false
        local n=count(AT.EQUIP_ALL_BEST)
        equip()
        check(count(AT.EQUIP_ALL_BEST)==n+1 and state.sent[#state.sent].heroId==2,"cleared pending accepts new current hero")
    end)
    add("busy outside equip page",nil,function()
        state.Detail.open(2,"awaken");h:setTime(h.clock+1)
        check(state.pending and not state.Detail.isEquipTab(),"pending survives navigating away from equip page")
    end,function()
        check(#state.animationCalls==0 and #state.texts==0,"no activity or batch text on unrelated awaken page")
    end)
    add("busy return to equip page",true,function()
        click(D.BTN_TAB_EQUIP_CX,D.BTN_TAB_EQUIP_CY);h:setTime(h.clock+1)
    end)
    add("final recovered visual",false,function() state.pending=false end,function()
        check(#state.sounds==0,"all clicks and draws emit no install/completion business audio")
        check(ioCalls==0 and rngCalls==0 and h.fileCalls==0 and h.fsCalls==0 and h.randomCalls==0,
            "no File/FS/RNG access or native delegation")
        check(h.loaded["runtime.LocalActionBridge"]==nil and h.loaded["runtime.GameAction"]==nil,
            "Bridge/Action explicitly observed spies, no false scheduling claim")
        for name in pairs(h.loaded) do check(not name:match("^boot[./]"),"no Boot module "..name) end
        check(state.pendingReads>=20,"real input/draw both observed pending seam")
    end)
    state.F,state.traceKey=F,traceKey
    state.count=count
end

local function assertAnimation(equip)
    local D=state.Draw
    ---@type table
    local call=state.animationCalls[1]
    assert(call,"real pending draw calls Activity")
    check(#state.animationCalls==1 and call.textsBefore==1,"one real animation between unequip and equip label")
    check(call.cx==D.BTN_EQUIP_CX and call.cy==D.BTN_EQUIP_CY and call.w==D.BTN_BATCH_W
        and call.h==D.BTN_BATCH_H and call.now==state.h.clock,"animation uses original geometry and current elapsedTime")
    local arcs,dots,frames,strokeAlpha={},{},{},{}
    for _,entry in ipairs(call.trace) do
        local a=entry.args
        if entry.name=="nvgArc" then arcs[#arcs+1]=a end
        if entry.name=="nvgMoveTo" then dots[#dots+1]=a end
        if entry.name=="nvgRoundedRect" then frames[#frames+1]=a end
        if entry.name=="nvgStrokeColor" then strokeAlpha[#strokeAlpha+1]=a[4] end
    end
    check(#arcs==2 and #dots==6 and #frames==1,"actual geometry includes two short arcs, six diamonds, inner frame")
    local ringX=D.BTN_EQUIP_CX-D.BTN_BATCH_W/2+26
    for _,arc in ipairs(arcs) do
        check(arc[1]==ringX and arc[2]==D.BTN_EQUIP_CY and arc[3]>0 and arc[3]<=12,
            "both real arc centers at contracted button-left position")
        check(arc[5]-arc[4]>0 and arc[5]-arc[4]<2*math.pi,"arcs are partial not full circles")
        check(arc[1]-arc[3]-2.5>=D.BTN_EQUIP_CX-D.BTN_BATCH_W/2
            and equip.bounds[1]>arc[1]+arc[3]+2.5,"full label ink cannot touch rotating ring including glow")
    end
    for _,dot in ipairs(dots) do
        check(dot[1]>D.BTN_EQUIP_CX-D.BTN_BATCH_W/2 and dot[1]<D.BTN_EQUIP_CX+D.BTN_BATCH_W/2,
            "all diamond centers inside original button width")
        -- moveTo是每枚菱形顶点，实际底部微光以cy+29为中心。
        check(dot[2]==D.BTN_EQUIP_CY+29-2.5 and equip.bounds[4]<dot[2]-2.5,
            "full label ink clears bottom diamond and five-pixel halo")
    end
    check(frames[1][1]>D.BTN_EQUIP_CX-D.BTN_BATCH_W/2 and frames[1][3]<D.BTN_BATCH_W,
        "breathing frame stays inset inside plate")
    check(strokeAlpha[1]>0 and strokeAlpha[1]<0.2,"inner glow is soft nonzero breathing opacity")
    local fingerprint=state.traceKey(call.trace)
    if state.previousAnimation then
        check(call.now~=state.previousAnimation.now and fingerprint~=state.previousAnimation.trace,
            "different real render frames have time-varying geometry/illumination")
    end
    state.previousAnimation={now=call.now,trace=fingerprint}
end

local function assertVisual(busy)
    local D,L=state.Draw,state.Lang
    check(#state.texts==2 and #state.plates==2,"real draw emitted both batch buttons once")
    local unequip,equip=state.texts[1],state.texts[2]
    check(unequip.x==D.BTN_UNEQUIP_CX and equip.x==D.BTN_EQUIP_CX,"actual button centers preserved")
    check(unequip.text==L.t("unequip_all") and unequip.size==38,"busy does not relabel/disable unequip visual")
    local expected=busy and state.expectedBusy or L.t("equip_all")
    check(equip.text==expected and equip.text~="" and equip.text~="equip_calculating","localized complete visible text")
    check(equip.face=="sans" and equip.size==(busy and 30 or 38),"real draw selects expected font and size")
    check(equip.align==NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE,"centered button label")
    check(equip.width>0 and equip.width<=D.BTN_BATCH_W,"real font advance within BTN_BATCH_W "..equip.width)
    local b=equip.bounds
    check(#b==4 and b[3]>b[1] and b[4]>b[2],"actual text has ink, not empty placeholder")
    check(b[1]>=D.BTN_EQUIP_CX-D.BTN_BATCH_W/2 and b[3]<=D.BTN_EQUIP_CX+D.BTN_BATCH_W/2
        and b[2]>=D.BTN_EQUIP_CY-D.BTN_BATCH_H/2 and b[4]<=D.BTN_EQUIP_CY+D.BTN_BATCH_H/2,
        "actual full ink remains inside original button")
    local color=busy and {231,192,135,255} or {244,237,224,255}
    for i=1,4 do check(math.abs(equip.color[i]-color[i]/255)<0.0001,"actual label color channel "..i) end
    local p=state.plates[2]
    check(p.x==D.BTN_EQUIP_CX-D.BTN_BATCH_W/2 and p.y==D.BTN_EQUIP_CY-D.BTN_BATCH_H/2
        and p.w==D.BTN_BATCH_W and p.h==D.BTN_BATCH_H and p.fills>0,"real DarkIcon delegate draws original plate")
    if busy then
        check(type(p.accent)=="table" and p.accent[1]==141 and p.accent[2]==95 and p.accent[3]==65,"busy brown accent recorded")
    else check(p.accent=="green","idle green accent restored") end
    check(state.plates[1].accent=="red","unequip retains original red accent")
    if busy then assertAnimation(equip)
    else check(#state.animationCalls==0,"idle/recovered button has no waiting animation") end
    print(TAG.."VISUAL frame="..frame.." lang="..state.language.." busy="..tostring(busy)
        .." text="..equip.text.." advance="..equip.width.." font="..equip.size)
end

function Start()
    vg=nvgCreate(1)
    assert(vg,"NanoVG context")
    assert(nvgCreateFont(vg,"sans","Fonts/NotoSansCJKkr-Bold.otf")>=0,"real Noto font required")
    local ok,err=pcall(prepare)
    if not ok then print(TAG.."FAIL prepare "..tostring(err));engine:Exit();return end
    SubscribeToEvent(vg,"NanoVGRender","RunQuickEquipUiFrame")
end
function RunQuickEquipUiFrame()
    frame=frame+1
    local step=steps[frame]
    if not step then return end
    local ok,err=pcall(function()
        state.h:setTime(state.h.clock+0.25)
        if step.before then step.before() end
        state.texts,state.plates,state.animationCalls={},{},{}
        -- 与锁定专项一致，在现有 1080x2400 详情设计空间测量，不修改窗口或项目分辨率。
        nvgBeginFrame(vg,1080,2400,1)
        state.Draw.draw(vg)
        if step.busy~=nil then assertVisual(step.busy)
        elseif not state.Detail.isOpen() then check(#state.animationCalls==0,"closed detail has no waiting animation") end
        if frame==1 then state.probeAnimation() end
        nvgEndFrame(vg)
        if step.after then step.after() end
        check(#state.sounds==0,"no named success sound at frame "..frame)
    end)
    if not ok then
        print(TAG.."FAIL frame="..frame.." "..step.label.." "..tostring(err))
        UnsubscribeFromEvent("NanoVGRender");engine:Exit();return
    end
    print(TAG.."PASS "..step.label)
    if frame==#steps then
        print(TAG.."ALL PASS "..checks.." assertions / "..frame.." distinct NanoVGRender frames; FileFS=0 RNG=0")
        UnsubscribeFromEvent("NanoVGRender");engine:Exit()
    end
end
function Stop()
    if state.Detail then state.Detail.forceClose() end
    if vg then nvgDelete(vg);vg=nil end
end
