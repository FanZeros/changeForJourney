-- 通天塔真实Sidebar专项：scaffold-2d宿主sans/实际Yoga/真实UI Render，不启动Boot或玩家档。
-- 验证两侧ScrollView内容更新、滚轮/拖动、当前层定位、窗口与五语长描述、独立树释放。
-- 多行TextBoxBounds检查行metrics，不单独等同可见字墨；确认固定行盒的metrics超高仅诊断。
-- 只在实例Render的私有_ENV观察原生文字，不替全局nvg/UI、不改生产/存档/奖励规则。
-- UrhoXRuntime tests/tower_sidebar_native_test.lua -tapcode_dir=/workspace -tool_mode -graphicssurfaceless -nosound
local TAG="[tower_sidebar_native_test]"
local total={checks=0,failed=0,cases=0,text=0,glyph=0}
local langs={"zh_CN","zh_TW","en","ja","ko"}
-- 独立五语文本与真实品质配色，不调用展示适配器生成期望。
local expected={
    zh_CN={rarities={"普通","优质","稀有"},collapse="收起",expand="展开",title="已获强化",pending="待选暗契 ×3"},
    zh_TW={rarities={"普通","優質","稀有"},collapse="收起",expand="展開",title="已獲強化",pending="待選暗契 ×3"},
    en={rarities={"Common","Uncommon","Rare"},collapse="Collapse",expand="Expand",title="Acquired Boons",pending="Pending Pacts ×3"},
    ja={rarities={"コモン","アンコモン","レア"},collapse="折りたたむ",expand="展開",title="獲得済みの強化",pending="未選択の暗契 ×3"},
    ko={rarities={"일반","고급","레어"},collapse="접기",expand="펼치기",title="획득한 강화",pending="미선택 계약 ×3"},
}
local expectedColors={{231,231,231,255},{106,190,115,255},{100,161,226,255}}
local dimensions={{1920,1080},{1280,800}}
---@type NVGContextWrapper?
local vg=nil
local Surface=require("ui.widget.DesignWidgetSurface")
local UI=require("urhox-libs/UI")
local Theme=require("urhox-libs/UI/Core/Theme")
local I18n=require("core.I18n")
local Config=require("config.TowerConfig")
local Layout=require("ui.tower.TowerLayout")
local Presentation=require("ui.tower.TowerPresentation")
local Sidebar={}
local observations={} ---@type table<any, any[]>
local widgets={} ---@type any[]
local finished=false
-- 可选视觉验收：不执行回归变更序列，固定第17层/35增益，供官方Runtime截图。
local preview=false
local previewCollapsed=false
local previewLang="zh_CN"
local index=0
local source=""
local snapshot={floor=17,wave=9,phase="battle",buffIds={},inputModal=false}
local original={text=nvgText,textBox=nvgTextBox,bounds=nvgTextBounds,boxBounds=nvgTextBoxBounds}
local function check(ok,label)
    total.checks=total.checks+1
    if not ok then total.failed=total.failed+1;print(TAG.." FAIL "..label) end
end
local function eq(a,b,label) check(a==b,label.." actual="..tostring(a).." expected="..tostring(b)) end
local function near(a,b,label) check(type(a)=="number" and math.abs(a-b)<.02,label.." actual="..tostring(a).." expected="..tostring(b)) end
local function uv(fn,key)
    for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==key then return v end end
    error("missing real production upvalue "..key)
end
local function copyRender(fn,env)
    local clone=assert(load(string.dump(fn),"@native-widget-observer","b",env))
    for i=1,100 do local n=debug.getupvalue(fn,i);if not n then break end
        if n=="_ENV" then debug.setupvalue(clone,i,env) else debug.upvaluejoin(clone,i,fn,i) end
    end
    return clone
end
local function fingerprint(v)
    if type(v)~="table" then return type(v)..":"..tostring(v) end
    local parts={};for k,value in pairs(v) do parts[#parts+1]=fingerprint(k).."="..fingerprint(value) end
    table.sort(parts);return "{"..table.concat(parts,",").."}"
end
local configBefore=fingerprint(Config.BUFFS)
local currentWidget=nil
local function record(ctx,text,bounds,multiline)
    total.text=total.text+1
    if bounds[1] and bounds[3] and bounds[3]>bounds[1] and bounds[4]>bounds[2] then total.glyph=total.glyph+1 end
    if currentWidget then observations[currentWidget][#observations[currentWidget]+1]={text=text,b=bounds,multiline=multiline==true} end
end
local function createSidebar()
    widgets={};observations={}
    local env=setmetatable({},{__index=_G})
    env.nvgText=function(ctx,x,y,text,...)
        local b={};local rawBounds=original.bounds ---@type any
        local endp,fit=...
        if select("#",...)>=2 then rawBounds(ctx,x,y,text,endp,b,fit)
        else rawBounds(ctx,x,y,text,endp,b) end
        record(ctx,text,b)
        return original.text(ctx,x,y,text,...)
    end
    env.nvgTextBox=function(ctx,x,y,w,text,...)
        local rawBoxBounds=original.boxBounds ---@type any
        local endp,fit=...
        local b={}
        if select("#",...)>=2 then b=rawBoxBounds(ctx,x,y,w,text,endp,b,fit)
        else b=rawBoxBounds(ctx,x,y,w,text,endp,b) end
        record(ctx,text,b,true)
        return original.textBox(ctx,x,y,w,text,...)
    end
    local proxy=setmetatable({},{__index=UI}) ---@type any
    for _,kind in ipairs({"Label","Button"}) do
        local constructor=kind=="Label" and UI.Label or UI.Button
        proxy[kind]=function(props)
            local widget=constructor(props)
            local actual=copyRender(widget.Render,env)
            widgets[#widgets+1]=widget
            widget.Render=function(self,ctx)
                local before=currentWidget;currentWidget=self;observations[self]={}
                local ok,err=xpcall(function() actual(self,ctx) end,debug.traceback)
                currentWidget=before;if not ok then error(err,0) end
            end
            return widget
        end
    end
    env.require=function(name)
        if name=="urhox-libs/UI" then return proxy end
        return require(name)
    end
    Sidebar=assert(load(source,"@resource:ui/tower/TowerBuffSidebar.lua","t",env))()
end
local function settle(w,h)
    for i=1,4 do Sidebar.draw(vg,w,h,snapshot) end
end
local function point(scroll,side,w,h)
    local l=Layout.compute(w,h);local r=scroll:GetAbsoluteLayout()
    local p=side=="right" and l.right or l.left
    return p.x+(r.x+r.w/2)*l.sideScale,(r.y+r.h/2)*l.sideScale
end
local function revealExpected(scroll,floor)
    local r=scroll:GetLayout();local _,ch=scroll:GetContentSize()
    return math.max(0,math.min(math.max(0,ch-r.h),(floor-1)*88-r.h/2+36))
end
local function inspectText(widget,label)
    local props=widget.GetProps and widget:GetProps() or widget.props;local expected=props.text or ""
    if expected=="" then return end
    local r=widget:GetAbsoluteLayout();local records=observations[widget] or {}
    eq(#records,1,label.." actual native draw receives full text once")
    if #records~=1 then return end
    local item=assert(records[1],"native text record missing");local b=item.b ---@type number[]
    eq(item.text,expected,label.." no truncated sentence or ellipsis")
    check(b[1]~=nil and b[3]>b[1] and b[4]>b[2],label.." actual host glyph bounds nonempty")
    if b[1] then
        check(b[1]>=r.x-1 and b[3]<=r.x+r.w+1,label.." text="..expected.." full glyph width inside actual Yoga cell left="..b[1].." right="..b[3].." cell="..r.x.."/"..r.w)
        local fixedConfirmMetrics=item.multiline and (label:find("confirm-title/",1,true) or label:find("confirm-note/",1,true))
        if fixedConfirmMetrics then
            print(TAG.." LINE_METRICS_DIAG "..label.." bounds="..b[2].."/"..b[4].." actualYoga="..r.y.."/"..r.h.." inkClippingUnconfirmed=true")
            check(r.h>0 and b[4]>b[2],label.." actual confirmation allocation and native multiline metrics nonempty")
        else
            check(b[2]>=r.y-1 and b[4]<=r.y+r.h+1,label..(item.multiline and " complete native line metrics height" or " full glyph height").." inside actual Yoga cell top="..b[2].." bottom="..b[4].." cell="..r.y.."/"..r.h)
        end
    end
end
local function assertTree(root,label)
    local r=root:GetAbsoluteLayout()
    for _,child in ipairs(root:GetChildren()) do
        local cr=child:GetAbsoluteLayout()
        check(cr.x>=r.x-.01 and cr.x+cr.w<=r.x+r.w+.01,label.." child within parent width")
        if child.GetText then inspectText(child,label) end
        if child.GetChildren then assertTree(child,label) end
    end
end
local function scrollCase(w,h,lang)
    total.cases=total.cases+1
    I18n.set(lang)
    createSidebar();snapshot.floor=17;snapshot.wave=9;snapshot.phase="battle";snapshot.inputModal=false;snapshot.pendingChoices=0
    snapshot.buffIds={1,2,3,4,5,6,7,8}
    settle(w,h)
    local route=uv(Sidebar.destroy,"routeScroll");local buffs=uv(Sidebar.destroy,"buffScroll")
    local left=uv(Sidebar.destroy,"leftRoot");local right=uv(Sidebar.destroy,"rightRoot")
    local nodes=uv(Sidebar.destroy,"nodes");local rows=uv(Sidebar.destroy,"buffContent")
    local rr=route:GetLayout();local br=buffs:GetLayout()
    local rw,rh=route:GetContentSize();local bw,bh=buffs:GetContentSize()
    eq(#nodes,112,"real route112 nodes "..lang)
    eq(#rows:GetChildren(),8,"real acquired buff8 rows "..lang)
    check(rw>0 and rh>rr.h,"left actual content exceeds viewport "..lang)
    check(bw>0 and bh>br.h,"right actual content exceeds viewport "..lang)
    local _,sy=route:GetScroll();near(sy,revealExpected(route,17),"initial floor17 reveal settled "..lang)
    local rx,ry=point(route,"left",w,h);local bx,by=point(buffs,"right",w,h)
    Sidebar.handleScroll(-1,rx,ry,w,h)
    local _,wheel=route:GetScroll();near(wheel,sy+110,"left actual wheel +110 "..lang)
    Sidebar.draw(vg,w,h,snapshot);local _,stable=route:GetScroll();near(stable,wheel,"stable draw preserves manual route scroll "..lang)
    Sidebar.handleScroll(-1,bx,by,w,h)
    local _,bsy=buffs:GetScroll();near(bsy,math.min(110,bh-br.h),"right actual wheel +110 "..lang)
    Sidebar.draw(vg,w,h,snapshot);local _,bStable=buffs:GetScroll();near(bStable,bsy,"stable draw preserves buff scroll "..lang)
    Sidebar.dragBegin(rx,ry,w,h);Sidebar.dragMove(rx,ry-50*Layout.compute(w,h).sideScale,w,h);Sidebar.dragEnd()
    local _,drag=route:GetScroll();near(drag,wheel+50,"left actual touch drag+50 "..lang)
    Sidebar.dragBegin(bx,by,w,h);Sidebar.dragMove(bx,by-50*Layout.compute(w,h).sideScale,w,h);Sidebar.dragEnd()
    local _,bd=buffs:GetScroll();near(bd,math.min(bsy+50,bh-br.h),"right actual touch drag+50 "..lang)
    local toggle=uv(Sidebar.destroy,"toggleButton");local title=uv(Sidebar.destroy,"buffTitle")
    local rule=uv(Sidebar.destroy,"ruleNote");local pending=uv(Sidebar.destroy,"pendingButton")
    local retreat=uv(Sidebar.destroy,"actionButton");local actual=expected[lang]
    near(title.props.fontSize,25.6,"右标题尺寸80% "..lang)
    near(rule.props.fontSize,14.4,"右说明尺寸80% "..lang)
    near(left.props.paddingLeft,24,"左栏间距保持 "..lang)
    near(right.props.paddingLeft,19.2,"右栏留白缩至80% "..lang)
    eq(toggle.props.text,actual.collapse,"独立五语收起文案 "..lang)
    inspectText(toggle,"collapse/"..lang)
    local firstRow=rows:GetChildAt(1);local firstHeader=firstRow:GetChildAt(1)
    near(firstHeader:GetChildAt(1).props.width,51.2,"图标配置尺寸80% "..lang)
    near(firstHeader:GetChildAt(1):GetLayout().w,51,"真实Yoga按像素舍入图标80% "..lang)
    near(firstHeader:GetChildAt(2):GetChildAt(1).props.fontSize,20.8,"名字尺寸80% "..lang)
    near(firstRow:GetChildAt(2).props.fontSize,18.4,"描述尺寸80% "..lang)
    snapshot.pendingChoices=3;settle(w,h)
    local ax,ay=point(retreat,"right",w,h);local px,py=point(pending,"right",w,h)
    local tx,ty=point(toggle,"right",w,h);local beforeSy=select(2,buffs:GetScroll())
    local beforeKey=Sidebar.getPresentationKey();local beforeRows=rows:GetChildAt(1)
    local beforeLeft=fingerprint(left:GetAbsoluteLayout());local beforeRight=fingerprint(right:GetAbsoluteLayout())
    eq(Sidebar.handleClick(tx,ty,w,h),"toggle_buffs","真实收起按钮命中 "..lang)
    Sidebar.dragBegin(bx,by,w,h);eq(Sidebar.toggleCollapsed(),true,"一键收起 "..lang)
    check(Sidebar.getPresentationKey()~=beforeKey,"收起使旧按压版本失效 "..lang)
    settle(w,h);Sidebar.dragMove(bx,by-80*Layout.compute(w,h).sideScale,w,h)
    near(select(2,buffs:GetScroll()),beforeSy,"收起停止旧drag且真实布局不清零sy "..lang)
    Sidebar.handleScroll(-1,bx,by,w,h);Sidebar.dragBegin(bx,by,w,h)
    Sidebar.dragMove(bx,by-80*Layout.compute(w,h).sideScale,w,h);Sidebar.dragEnd()
    near(select(2,buffs:GetScroll()),beforeSy,"隐藏区域不滚轮不拖动 "..lang)
    eq(buffs:IsVisible(),false,"隐藏真实ScrollView "..lang);eq(rule:IsVisible(),false,"隐藏规则说明 "..lang)
    eq(rows:GetChildAt(1),beforeRows,"收起不销毁现有卡片 "..lang)
    eq(title:GetText(),actual.title.."  8","数量收起后保留 "..lang)
    eq(pending.props.text,actual.pending,"待选数量收起后保留 "..lang)
    eq(Sidebar.handleClick(px,py,w,h),"resume_pick","收起保留待选恢复入口 "..lang)
    eq(Sidebar.handleClick(ax,ay,w,h),"retreat","收起保留撤退入口和位置 "..lang)
    eq(toggle.props.text,actual.expand,"独立五语展开文案 "..lang);inspectText(toggle,"expand/"..lang)
    eq(fingerprint(left:GetAbsoluteLayout()),beforeLeft,"收起不改左栏几何 "..lang)
    eq(fingerprint(right:GetAbsoluteLayout()),beforeRight,"收起不改右栏几何 "..lang)
    snapshot.inputModal=true;settle(w,h)
    eq(Sidebar.handleClick(tx,ty,w,h),nil,"模态阻止收起展开按钮 "..lang)
    snapshot.inputModal=false;settle(w,h)
    eq(Sidebar.toggleCollapsed(),false,"一键展开 "..lang);settle(w,h)
    near(select(2,buffs:GetScroll()),beforeSy,"展开恢复原sy "..lang)
    check(Sidebar.getPresentationKey()~=beforeKey,"收起展开ABA版本仍失效 "..lang)
    eq(rows:GetChildAt(1),beforeRows,"展开复用原卡片 "..lang)
    Sidebar.toggleCollapsed();Sidebar.reset();settle(w,h)
    eq(Sidebar.isCollapsed(),false,"reset默认展开 "..lang)
    eq(buffs:IsVisible(),true,"reset恢复内容可见 "..lang)
    near(select(2,buffs:GetScroll()),0,"reset清理旧会话scroll "..lang)
    snapshot.pendingChoices=0;settle(w,h)
    snapshot.floor=112;settle(w,h);local _,endY=route:GetScroll();near(endY,revealExpected(route,112),"floor112 bottom-clamped reveal "..lang)
    snapshot.floor=1;settle(w,h);local _,first=route:GetScroll();near(first,0,"floor1 top-clamped reveal "..lang)
    snapshot.floor=17;snapshot.buffIds={1,2,3,4,5,6,7,8};settle(w,h)
    local alternateW,alternateH=w==1920 and 1280 or 1920,w==1920 and 800 or 1080
    settle(alternateW,alternateH)
    local _,resized=route:GetScroll();near(resized,revealExpected(route,17),"same root resize re-centers current route "..lang)
    eq(uv(Sidebar.destroy,"leftRoot"),left,"resize reuses same left root "..lang)
    eq(uv(Sidebar.destroy,"rightRoot"),right,"resize reuses same right root "..lang)
    settle(w,h)
    local _,returned=route:GetScroll();near(returned,revealExpected(route,17),"same root return size re-centers current route "..lang)
    snapshot.buffIds={};for id=1,30 do snapshot.buffIds[#snapshot.buffIds+1]=id end
    snapshot.pendingChoices=3
    settle(w,h)
    eq(#rows:GetChildren(),30,"all30 actual buff descriptions available "..lang)
    assertTree(left,"left/"..lang);assertTree(right,"right/"..lang)
    local seen={}
    for rowIndex,row in ipairs(rows:GetChildren()) do
        local header=row:GetChildAt(1);local desc=row:GetChildAt(2);local name=header:GetChildAt(2):GetChildAt(1)
        local quality=header:GetChildAt(2):GetChildAt(2);local def=Config.BUFFS_BY_ID[rowIndex]
        eq(quality:GetText(),actual.rarities[def.quality].."  ×1","独立真实稀有度文字 "..lang.."/"..rowIndex)
        eq(fingerprint(quality.props.fontColor),fingerprint(expectedColors[def.quality]),"品质文字白绿蓝 "..lang.."/"..rowIndex)
        eq(fingerprint(row.props.borderColor),fingerprint(expectedColors[def.quality]),"卡片边框白绿蓝 "..lang.."/"..rowIndex)
        eq(quality.props.textStroke,nil,"不额外增加文字描边次数 "..lang.."/"..rowIndex)
        seen[name:GetText()]=true;seen[desc:GetText()]=true
        local dl=desc:GetAbsoluteLayout();local rowRect=row:GetAbsoluteLayout()
        check(dl.h>0 and dl.y+dl.h<=rowRect.y+rowRect.h+.01,"full long description fits own actual Yoga row "..lang)
    end
    for id=1,30 do
        local def=Config.BUFFS_BY_ID[id]
        check(seen[Presentation.name(def)]==true,"exact complete translated name "..lang.."/"..id)
        check(seen[Presentation.description(def)]==true,"exact complete translated description "..lang.."/"..id)
    end
    buffs:ScrollToBottom();local _,fullBottom=buffs:GetScroll()
    check(fullBottom>0,"long real acquired list can reach lower rows "..lang)
    Sidebar.toggleCollapsed()
    local alternateLang=lang=="en" and "ko" or "en"
    I18n.set(alternateLang);settle(w,h)
    near(select(2,buffs:GetScroll()),fullBottom,"收起时切换语言不钳制旧sy "..lang)
    Sidebar.toggleCollapsed();settle(w,h)
    local _,translatedHeight=buffs:GetContentSize();local translatedViewport=buffs:GetLayout()
    near(select(2,buffs:GetScroll()),math.min(fullBottom,math.max(0,translatedHeight-translatedViewport.h)),"展开后按真实译文高度钳制sy "..lang)
    I18n.set(lang);settle(w,h);buffs:ScrollToBottom()
    Sidebar.toggleCollapsed();local beforeShrink=select(2,buffs:GetScroll())
    snapshot.buffIds={1};settle(w,h)
    near(select(2,buffs:GetScroll()),beforeShrink,"收起时增益变化不提前清零旧sy "..lang)
    Sidebar.toggleCollapsed();settle(w,h)
    local _,shrunken=buffs:GetScroll();near(shrunken,0,"shortened actual list clamps old bottom scroll "..lang)
    eq(#rows:GetChildren(),1,"old acquired row instances replaced after list change "..lang)
    snapshot.buffIds={};for id=1,30 do snapshot.buffIds[#snapshot.buffIds+1]=id end
    snapshot.phase="buff_pick";settle(w,h)
    local action=uv(Sidebar.destroy,"actionButton");local ar=action:GetAbsoluteLayout();local l=Layout.compute(w,h)
    local ax=l.right.x+(ar.x+ar.w/2)*l.sideScale;local ay=(ar.y+ar.h/2)*l.sideScale
    eq(Sidebar.handleClick(ax,ay,w,h),"resume_pick","actual translated continue button action "..lang)
    inspectText(action,"continue/"..lang)
    snapshot.inputModal=true;settle(w,h);eq(Sidebar.handleClick(ax,ay,w,h),nil,"modal blocks right-side action "..lang)
    snapshot.inputModal=false;Sidebar.drawConfirmation(vg,w,h)
    inspectText(uv(Sidebar.destroy,"confirmTitle"),"confirm-title/"..lang)
    inspectText(uv(Sidebar.destroy,"confirmNote"),"confirm-note/"..lang)
    inspectText(uv(Sidebar.destroy,"confirmCancel"),"confirm-cancel/"..lang)
    inspectText(uv(Sidebar.destroy,"confirmRetreat"),"confirm-retreat/"..lang)
    local beforeRoot=left
    Sidebar.destroy()
    eq(uv(Sidebar.destroy,"leftRoot"),nil,"own left root cleared after destroy "..lang)
    eq(uv(Sidebar.destroy,"rightRoot"),nil,"own right root cleared after destroy "..lang)
    eq(#uv(Sidebar.destroy,"nodes"),0,"own route references cleared after destroy "..lang)
    Sidebar.draw(vg,w,h,snapshot)
    check(uv(Sidebar.destroy,"leftRoot")~=beforeRoot,"new actual root after reopen "..lang)
    Sidebar.destroy()
    eq(fingerprint(Config.BUFFS),configBefore,"no formal buff rule/config mutation "..lang)
    print(TAG.." CASE COMPLETE "..lang.." "..w.."x"..h.." checks="..total.checks.." failed="..total.failed.." route="..rw.."/"..rh.." buffs="..bw.."/"..bh)
end
function Start()
    for _,arg in ipairs(GetArguments()) do
        if arg=="-tower-sidebar-preview" then preview=true end
        if arg=="-tower-sidebar-collapsed" then previewCollapsed=true end
        local lang=arg:match("^%-tower%-sidebar%-lang=(.+)$")
        if lang and expected[lang] then previewLang=lang end
    end
    local f=assert(cache:GetFile("ui/tower/TowerBuffSidebar.lua"));local lines={}
    while not f:IsEof() do lines[#lines+1]=f:ReadLine() end;f:Dispose();source=table.concat(lines,"\n")
    Surface.init();vg=assert(nvgCreate(1));check(nvgCreateFont(vg,"sans","Fonts/NotoSansCJKkr-Bold.otf")>=0,"only actual host sans font")
    SubscribeToEvent(vg,"NanoVGRender","HandleSidebarNative")
end
function HandleSidebarNative()
    if finished then return end
    local d=graphics:GetDPR();local w,h=graphics:GetWidth()/d,graphics:GetHeight()/d
    local ctx=vg;if not ctx then return end
    nvgBeginFrame(ctx,w,h,d)
    local ok,err=xpcall(function()
        index=index+1
        if preview then
            if index==1 then
                I18n.set(previewLang);createSidebar()
                snapshot.buffIds={};for id=1,35 do snapshot.buffIds[#snapshot.buffIds+1]=id end
                snapshot.pendingChoices=3
                if previewCollapsed then Sidebar.toggleCollapsed() end
            end
            settle(w,h)
            if index==120 then
                check(Sidebar.isCollapsed()==previewCollapsed,"视觉验收目标状态保持120帧")
                check(fingerprint(Config.BUFFS)==configBefore,"视觉验收不修改配置")
                print(TAG.." PREVIEW COMPLETE lang="..previewLang.." collapsed="..tostring(previewCollapsed).." frames="..index)
                finished=true
            end
            return
        end
        local dimensionsIndex=math.floor((index-1)/#langs)+1
        local lang=langs[(index-1)%#langs+1]
        local dims=assert(dimensions[dimensionsIndex],"invalid dimensions case")
        scrollCase(dims[1],dims[2],lang)
        if index==#langs*#dimensions then finished=true end
    end,debug.traceback)
    nvgEndFrame(ctx)
    if not ok then check(false,"unexpected real UI exception "..tostring(err));finished=true end
    if finished then engine:Exit() end
end
function Stop()
    local ok,err=xpcall(function()
        if Sidebar.destroy then Sidebar.destroy() end
        require("ui.tower.TowerOathEffect").destroy();Surface.shutdown();if vg then nvgDelete(vg);vg=nil end
    end,debug.traceback)
    if not ok then check(false,"Stop actual UI/VG exception "..tostring(err)) end
    print(TAG.." FINAL "..(total.failed==0 and finished and "ALL PASS" or "FAILED").." cases="..total.cases.." checks="..total.checks.." failed="..total.failed.." nativeText="..total.text.." glyph="..total.glyph)
end
