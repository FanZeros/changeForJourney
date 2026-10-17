-- 暂停灰层专项：真实production源码/Panel/Label/Yoga/Surface/宿主sans；不启动main、不接玩家档。
-- 源码在私有_ENV编译；仅私有UI构造代理捕获真实树、私有NVG观察器透传真实绘制。
-- 基于scaffold-2d的Surface生命周期，raw画面采用模式B；预览真实BattleView而非绘图spy。
-- -pause-overlay-preview [-pause-overlay-state=paused|running|inactive] [-pause-overlay-lang=en]
-- -pause-overlay-layout=tri|dungeon|classic|tower；tri为可复现三战场夹具，不冒称完整宿主启动。
-- -caption-unclipped-reference仅作字墨像素参考，不是正式画面；五语需与不带该flag截图逐像素比较。
-- validate模式不主动Exit，保证运行时正式JSON报告落盘。首轮atlas边界疑点保留日志，不当像素裁剪结论。
local TAG = "[battle_pause_overlay_test]"
local total = { checks = 0, failed = 0, cases = 0, glyphs = 0 }
local sources = {}
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local PointerEvent = require("urhox-libs/UI/Core/PointerEvent")
---@type NVGContextWrapper?
local vg = nil
---@type any
local fixture = nil
local preview, validateMode = false, false
local captionReference = false
local previewState, previewLayout, previewLang = "paused", "tri", "zh_CN"
local frames, finished = 0, false
local expected = { zh_CN = "战斗已暂停", zh_TW = "戰鬥已暫停", en = "Battle paused",
    ja = "戦闘一時停止", ko = "전투 일시 정지" }
local raw = { save = nvgSave, restore = nvgRestore, translate = nvgTranslate,
    intersect = nvgIntersectScissor, text = nvgText, bounds = nvgTextBounds, face = nvgFontFace }
local function check(ok, label)
    total.checks = total.checks + 1
    if not ok then total.failed = total.failed + 1; print(TAG .. " FAIL " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " 实际=" .. tostring(a) .. " 期望=" .. tostring(b)) end
local function near(a, b, label) check(type(a) == "number" and math.abs(a-b) < .05,
    label .. " 实际=" .. tostring(a) .. " 期望=" .. tostring(b)) end
local function run(name, fn)
    total.cases = total.cases + 1
    local before = total.failed
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then check(false, name .. " 异常 " .. tostring(err)) end
    print(TAG .. (before == total.failed and " PASS " or " FAILED ") .. name)
end
local function source(name)
    local path = name:gsub("%.", "/") .. ".lua"
    if not sources[path] then
        local file = assert(cache:GetFile(path), "缺少真实源码 " .. path)
        local lines = {}
        while not file:IsEof() do lines[#lines+1] = file:ReadLine() end
        file:Dispose(); sources[path] = table.concat(lines, "\n")
    end
    return sources[path]
end
local function clone(fn, env)
    local copy = assert(load(string.dump(fn), "@暂停专项私有原生观察器", "b", env))
    for i = 1, 100 do
        local key = debug.getupvalue(fn, i)
        if not key then break end
        if key == "_ENV" then debug.setupvalue(copy, i, env) else debug.upvaluejoin(copy, i, fn, i) end
    end
    return copy
end
local function xform(ctx)
    local values = {0,0,0,0,0,0}; local result = nvgCurrentTransform(ctx, values)
    return type(result) == "table" and result or values
end
local function sameTransform(before, after, label)
    eq(#after, 6, label .. " 原生矩阵六项")
    for i = 1, 6 do near(after[i], before[i], label .. " 矩阵" .. i) end
end
local function newFixture()
    local f = { mods = {}, constructed = {}, labels = {}, texts = {}, calls = {}, depth = 0,
        saves = 0, restores = 0, io = 0, blocked = 0, clockReads = 0, clockWrites = 0,
        wall = { elapsedTime = 100 }, cpu = 10, root = false, caption = false }
    local env = setmetatable({}, { __index = _G }); env._G = env
    env.time = f.wall; env.os = setmetatable({ clock = function() return f.cpu end }, { __index = os })
    env.File = function() f.io = f.io + 1; error("专项禁止File/玩家档", 0) end
    env.fileSystem = setmetatable({}, { __index = function() f.io=f.io+1; error("专项禁止FileSystem", 0) end })
    local forbidden = { ["core.PlayerStore"] = true, ["core.GameState"] = true,
        ["runtime.LocalActionBridge"] = true, ["boot.StandaloneSave"] = true,
        ["boot.Standalone"] = true, ["main"] = true }
    local function loadPrivate(name)
        if f.mods[name] ~= nil then return f.mods[name] end
        if name == "cjson" or name:find("^urhox%-libs") then return require(name) end
        if forbidden[name] then
            local trap = setmetatable({}, { __index = function(_, key)
                f.blocked = f.blocked + 1; error("专项禁止玩家/动作边界 " .. name .. "." .. tostring(key), 0)
            end })
            f.mods[name] = trap; return trap
        end
        local placeholder = {}; f.mods[name] = placeholder
        local value = assert(load(source(name), "@resource:" .. name, "t", env))()
        if type(value) == "table" then
            for key, item in pairs(value) do placeholder[key] = item end
            setmetatable(placeholder, getmetatable(value)); return placeholder
        end
        f.mods[name] = value; return value
    end
    env.require = loadPrivate
    f.load = loadPrivate; f.env = env
    f.mods["ui.widget.DesignWidgetSurface"] = Surface
    local proxy = setmetatable({}, { __index = UI })
    local labelEnv = setmetatable({}, { __index = _G })
    -- 像素参考模式只取消该Label自己的scissor；仍调用真实Label/NVG、保留父战场裁剪。
    labelEnv.nvgIntersectScissor = function(ctx,x,y,w,h)
        if captionReference then return end
        return raw.intersect(ctx,x,y,w,h)
    end
    labelEnv.nvgFontFace = function(ctx, face)
        f.face = face; return raw.face(ctx, face)
    end
    labelEnv.nvgText = function(ctx, x, y, text, ...)
        local bounds = {}; local endp, fit = ...
        if select("#", ...) >= 2 then raw.bounds(ctx, x, y, text, endp, bounds, fit)
        else raw.bounds(ctx, x, y, text, endp, bounds) end
        f.texts[#f.texts+1] = { text=text, b=bounds, face=f.face, widget=f.drawingLabel }
        return raw.text(ctx, x, y, text, ...)
    end
    proxy.Label = function(props)
        local widget = UI.Label(props)
        f.constructed[#f.constructed+1] = widget; f.labels[#f.labels+1] = widget; f.caption=widget
        local actual = clone(widget.Render, labelEnv)
        widget.Render = function(self, ctx)
            f.drawingLabel = self; actual(self, ctx); f.drawingLabel = nil
        end
        return widget
    end
    proxy.Panel = function(props)
        local widget = UI.Panel(props); f.constructed[#f.constructed+1] = widget
        if props.pointerEvents == "none" and props.overflow == "hidden" then f.root = widget end
        return widget
    end
    f.mods["urhox-libs/UI"] = proxy
    -- 真时钟的写入口只有测试控制器；覆盖层拿只读代理，任何误写立即失败。
    local clock = loadPrivate("ui.battle.combat.BattleClock"); f.clock = clock
    f.mods["ui.battle.combat.BattleClock"] = setmetatable({ isPaused = function()
        f.clockReads=f.clockReads+1; return clock.isPaused()
    end }, { __index = function(_, key)
        f.clockWrites=f.clockWrites+1; error("覆盖层不是时钟owner: " .. tostring(key), 0)
    end })
    env.nvgSave = function(ctx)
        f.depth=f.depth+1; f.saves=f.saves+1; f.calls[#f.calls+1]={kind="save"}; return raw.save(ctx)
    end
    env.nvgRestore = function(ctx)
        f.depth=f.depth-1; f.restores=f.restores+1; f.calls[#f.calls+1]={kind="restore"}; return raw.restore(ctx)
    end
    env.nvgIntersectScissor = function(ctx,x,y,w,h)
        f.calls[#f.calls+1]={kind="clip",x=x,y=y,w=w,h=h}; return raw.intersect(ctx,x,y,w,h)
    end
    env.nvgTranslate = function(ctx,x,y)
        f.calls[#f.calls+1]={kind="translate",x=x,y=y}; return raw.translate(ctx,x,y)
    end
    f.overlay=loadPrivate("ui.battle.scene.BattlePauseOverlay")
    f.i18n=loadPrivate("core.I18n")
    return f
end
local function draw(f,x,y,w,h,active,uiScale)
    local before=xform(vg); local calls=#f.calls; local texts=#f.texts
    f.overlay.draw(vg,x,y,w,h,active,uiScale)
    sameTransform(before,xform(vg),"draw不改变宿主变换")
    eq(f.depth,0,"draw外层save/restore平衡")
    return #f.calls-calls, #f.texts-texts
end
local function glyphCheck(f,label)
    local caption=assert(f.caption); local rect=caption:GetAbsoluteLayout()
    local record=assert(f.texts[#f.texts],"必须有真实Label文字")
    eq(record.widget,caption,label.." 当前真实Label")
    eq(record.face,"sans",label.." 仅使用宿主sans字体")
    eq(record.text,expected[f.i18n.get()],label.." 独立五语完整文案")
    local b=record.b
    check(b[1] and b[3]>b[1] and b[4]>b[2],label.." 实际字墨非空")
    if b[1] then
        total.glyphs=total.glyphs+1
        -- Bounds包含atlas padding，不把1～3px metrics外溢冒称字墨被裁；另跑真实参考图逐像素比对。
        local overhang=math.max(rect.x-b[1],b[3]-rect.x-rect.w,0)
        check(overhang<=3,label.." 字形atlas padding边界≤3px 实际="..overhang)
        if overhang>1 then print(TAG.." ATLAS_METRICS_DIAG "..label.." overhang="..overhang.." 像素裁剪待配对图验证") end
        check(b[2]>=rect.y-1 and b[4]<=rect.y+rect.h+1,label.." 真实Yoga高度容纳字墨")
    end
end
local function tests()
    local f=fixture
    run("加载隔离与幂等初始化",function()
        eq(#f.constructed,0,"require不提前创建UI树")
        eq(package.loaded["ui.battle.scene.BattlePauseOverlay"],nil,"新require不污染全局module缓存")
        eq(package.loaded["ui.battle.combat.BattleClock"],nil,"私有时钟不污染全局缓存")
        f.overlay.init(); local root=f.root; local caption=f.caption
        eq(#f.constructed,6,"真实五Panel与一Label")
        check(root.node~=nil and caption.node~=nil,"真实Yoga节点")
        for _=1,40 do f.overlay.init() end
        eq(#f.constructed,6,"重复init不建树")
        eq(f.root,root,"重复init根引用相同")
        eq(f.caption,caption,"重复init标签引用相同")
        eq(root.props.pointerEvents,"none","灰层整树输入穿透")
        eq(caption.props.fontFamily,"sans","显式宿主fontFamily")
        eq(caption.props.fontWeight,"normal","不请求宿主缺失sans-bold")
    end)
    run("暂停恢复inactive与零尺寸不绘制/不写时钟",function()
        local calls,texts=draw(f,40,60,948,360,true)
        eq(calls,0,"未暂停不调用绘图"); eq(texts,0,"未暂停无Label draw")
        f.wall.elapsedTime=100.25; f.cpu=10.25; f.clock.setPaused(true)
        local frozen, cpu=f.clock.now(),f.clock.cpuNow()
        f.wall.elapsedTime=160.25; f.cpu=30.25
        for _,args in ipairs({{948,360,false},{0,360,true},{948,0,true},{-1,360,true},{948,-1,true}}) do
            calls,texts=draw(f,40,60,args[1],args[2],args[3])
            eq(calls,0,"inactive/无效尺寸无绘图");eq(texts,0,"inactive/无效尺寸无字墨")
        end
        near(f.clock.now(),frozen,"暂停长间隔wall冻结")
        near(f.clock.cpuNow(),cpu,"暂停长间隔CPU冻结")
        calls,texts=draw(f,40,60,948,360,true)
        eq(calls,4,"实际save/clip/translate/restore四调用");eq(texts,1,"实际Label一次绘制")
        glyphCheck(f,"暂停首帧")
        f.clock.setPaused(true);f.clock.setPaused(false)
        near(f.clock.now(),frozen,"恢复无暂停时间catch-up")
        f.wall.elapsedTime=160.35;f.cpu=30.35
        near(f.clock.now(),frozen+.1,"恢复只增加新wall帧")
        near(f.clock.cpuNow(),cpu+.1,"恢复只增加新CPU帧")
        calls,texts=draw(f,40,60,948,360,true)
        eq(calls,0,"恢复立即不绘图");eq(texts,0,"恢复无旧文字")
        eq(f.clockWrites,0,"覆盖层仅访问isPaused只读接口")
    end)
    run("五语多战场尺寸/继承裁剪/状态平衡",function()
        f.clock.setPaused(true);local root=f.root;local constructed=#f.constructed
        local rects={{0,0,1080,2400},{0,260,1920,680},{486,110,948,250},
            {486,424,948,360},{42,58,474,180},{9,13,320,120}}
        for _,lang in ipairs({"zh_CN","zh_TW","en","ja","ko"}) do
            f.i18n.set(lang)
            for _,r in ipairs(rects) do
                nvgSave(vg);nvgTranslate(vg,17,23);nvgScale(vg,.75,.8)
                nvgScissor(vg,0,0,1800,1000)
                local matrix=xform(vg)
                near(matrix[1],.75,"矩阵观察器读取真实X缩放而非初始table")
                near(matrix[4],.8,"矩阵观察器读取真实Y缩放")
                near(matrix[5],17,"矩阵观察器读取真实X平移")
                near(matrix[6],23,"矩阵观察器读取真实Y平移")
                local callStart=#f.calls
                draw(f,r[1],r[2],r[3],r[4],true)
                local clip=f.calls[callStart+2];eq(clip.kind,"clip","使用Intersect不清宿主Scissor")
                near(clip.x,r[1],"精确clip x");near(clip.y,r[2],"精确clip y")
                near(clip.w,r[3],"精确clip width");near(clip.h,r[4],"精确clip height")
                local actual=root:GetAbsoluteLayout()
                near(actual.w,r[3],"真实Yoga战场width");near(actual.h,r[4],"真实Yoga战场height")
                local badge=root:GetChildAt(1):GetAbsoluteLayout()
                near(badge.x+badge.w/2,r[3]/2,"真实暂停标牌水平居中")
                near(badge.y+badge.h/2,r[4]/2,"真实暂停标牌垂直居中")
                check(badge.x>=-1 and badge.x+badge.w<=r[3]+1,"标牌不越战场左右边")
                glyphCheck(f,lang.."/"..r[3].."x"..r[4]);nvgRestore(vg)
            end
        end
        eq(f.root,root,"多战场共用同一真实子树")
        eq(#f.constructed,constructed,"多尺寸切换不重复创建")
        eq(f.saves,f.restores,"所有draw状态对称")
        f.i18n.set("zh_CN")
    end)
    run("classic显式UI缩放保持原clip/中心/宿主状态",function()
        f.clock.setPaused(true);local root=f.root;local count=#f.constructed
        local scales={2400/1080,1}
        for _,scale in ipairs(scales) do
            local before=#f.calls;nvgSave(vg);nvgScale(vg,.45,.45)
            draw(f,0,0,1080,2400,true,scale)
            local actual=root:GetAbsoluteLayout();near(actual.w,1080/scale,"缩放后真实布局width")
            near(actual.h,2400/scale,"缩放后真实布局height")
            local badge=root:GetChildAt(1):GetAbsoluteLayout()
            near((badge.x+badge.w*.5)*scale,540,"缩放后仍在原战场中心X")
            near((badge.y+badge.h*.5)*scale,1200,"缩放后仍在原战场中心Y")
            local clip=f.calls[before+2];near(clip.w,1080,"clip保持原战场width")
            near(clip.h,2400,"clip保持原战场height")
            -- 仅真实宿主使用的补偿值验证字墨；默认1已经在五语/六矩形矩阵验证。
            if scale~=1 then glyphCheck(f,"classic scale="..scale) end
            nvgRestore(vg)
        end
        eq(f.root,root,"缩放复用同一真实根")
        eq(#f.constructed,count,"缩放不创建第二棵树")
    end)
    run("真实UI命中/鼠标触摸按压连续性/无模态栈",function()
        local previous=UI.GetRoot();local clicks=0
        local button=UI.Button{width=300,height=120,text="底层可操作按钮",onClick=function() clicks=clicks+1 end}
        local host=UI.Panel{width=400,height=200,pointerEvents="box-none",children={button}}
        UI.SetRoot(host);Surface.draw(host,vg,400,200)
        local scale=UI.GetScale();local function event(kind,id,pt)
            return PointerEvent.new(kind,{pointerId=id,pointerType=pt,x=140*scale,y=55*scale,
                button=PointerEvent.Button.Left,buttons=PointerEvent.Buttons.Primary})
        end
        for _,pointer in ipairs({{0,PointerEvent.PointerTypes.Mouse},{7,PointerEvent.PointerTypes.Touch}}) do
            UI.HandlePointerEvent(event(PointerEvent.Types.PointerDown,pointer[1],pointer[2]))
            eq(UI.GetPressedWidgetForPointer(pointer[1]),button,"真实指针按压命中底层")
            local oldRoot=UI.GetRoot();local oldFocus=UI.GetFocus();local overlays=#UI.GetOverlayStack()
            local activeOverlay=UI.GetActiveOverlay()
            f.overlay.draw(vg,0,0,400,200,true)
            eq(UI.GetRoot(),oldRoot,"独立灰层不替换宿主UI根")
            eq(UI.GetFocus(),oldFocus,"独立灰层不抢真实焦点")
            eq(#UI.GetOverlayStack(),overlays,"独立灰层不注册真实模态栈")
            eq(UI.GetActiveOverlay(),activeOverlay,"独立灰层不成为真实activeOverlay")
            eq(UI.GetPressedWidgetForPointer(pointer[1]),button,"灰层draw保留pressed引用")
            -- 强化反例：即使显式把真实灰层挂进宿主树，顶层none仍跳过全部子控件。
            f.root:SetStyle{position="absolute",left=0,top=0};host:AddChild(f.root)
            YGNodeCalculateLayout(host.node,400,200,YGDirectionLTR)
            eq(UI.FindWidgetAt(140,55),button,"真实FindWidgetAt穿透整个灰层")
            UI.HandlePointerEvent(event(PointerEvent.Types.PointerMove,pointer[1],pointer[2]))
            UI.HandlePointerEvent(event(PointerEvent.Types.PointerUp,pointer[1],pointer[2]))
            f.root:Remove()
        end
        eq(clicks,2,"真实鼠标和touch完整按压各一次点击")
        eq(f.clock.isPaused(),true,"点击底层不由覆盖层擅自恢复时钟")
        UI.SetRoot(previous);host:Destroy()
        f.root:SetStyle{position="relative",left=0,top=0}
        eq(f.overlay.handleInput,nil,"覆盖层无抢输入入口")
    end)
    run("destroy幂等/释放真实Yoga/重新init/不重置暂停坐标",function()
        local oldRoot=f.root;local oldNodes={};for _,widget in ipairs(f.constructed) do oldNodes[#oldNodes+1]=widget end
        local wall,cpu=f.clock.now(),f.clock.cpuNow();local host=UI.GetRoot()
        f.overlay.destroy();f.overlay.destroy()
        for _,widget in ipairs(oldNodes) do eq(widget.node,nil,"destroy释放真实Yoga节点") end
        eq(oldRoot:GetNumChildren(),0,"destroy清理整棵子树")
        eq(UI.GetRoot(),host,"destroy不销毁Surface/其他宿主根")
        near(f.clock.now(),wall,"destroy不改变wall坐标");near(f.clock.cpuNow(),cpu,"destroy不改变CPU坐标")
        eq(f.clock.isPaused(),true,"destroy不擅自取消暂停")
        f.overlay.init();check(f.root~=oldRoot,"重新init获得新树")
        eq(#f.constructed,12,"重新init仅新增一个六节点树")
        draw(f,30,45,948,360,true);glyphCheck(f,"destroy后重开")
        f.clock.setPaused(false);local calls=draw(f,30,45,948,360,true);eq(calls,0,"重开后恢复正常不画")
        eq(f.io,0,"私有环境File/FS访问零");eq(f.blocked,0,"玩家/动作边界访问零")
    end)
    run("真实源码Tri灰层loop空队/失守/寻怪/结算/解锁门禁",function()
        local tri=source("ui.battle.tri.BattleTriPage")
        local start=assert(tri:find("    -- 灰层只覆盖已解锁战场",1,true))
        local ending=assert(tri:find("    -- ===== UI 层（窗口坐标）",start,true))
        local env={COL_COUNT=3,unlocked=3,logicalW=1920,logicalH=1080,battleReady=true,
            drivers={{active=true,allies={{}}},{active=true,allies={{}}},{active=true,allies={{}}}},
            terminalRaid=false,math=math,
            interiorRect=function(row) return 100,80+(row-1)*300,948,260 end,
            BattlePauseOverlay=f.overlay,vg=vg}
        local actual=assert(load(tri:sub(start,ending-1),"@真实Tri灰层loop","t",env))
        f.clock.setPaused(true)
        local function verify(count,label)
            local before=#f.texts;local beforeClock=f.clock.now();actual()
            eq(#f.texts-before,count,label.." 实际真实Label绘制数")
            near(f.clock.now(),beforeClock,label.." 不修改时钟")
            eq(f.depth,0,label.." 真实灰层状态平衡")
        end
        verify(3,"三队有英雄active")
        env.drivers[2].allies={};verify(2,"空编队不叠暂停文案")
        env.drivers[2].allies={{}};env.drivers[2].active=false;verify(2,"寻怪inactive不灰")
        env.drivers[2].active=true;env.drivers[3]=nil;verify(2,"尚无driver不灰")
        env.drivers[3]={active=true,allies={{}}};env.battleReady=false;verify(0,"宿主未ready不灰")
        env.battleReady=true;env.terminalRaid={finished=false,defeated={[2]=true}};verify(2,"终焉已失守行不灰")
        env.terminalRaid.finished=true;verify(0,"终焉结算不灰")
        env.terminalRaid=false;env.unlocked=1;verify(1,"未解锁行不灰")
        eq(f.io,0,"宿主loop不接存档");eq(f.clockWrites,0,"宿主loop只读灰层时钟")
    end)
    run("四宿主inactive生产门禁源码契约",function()
        local scene=source("ui.battle.scene.BattleScene")
        check(scene:find("MAP_H, battleActive, MAP_H / 1080)",1,true)~=nil,"普通inactive门禁与显式设计缩放")
        local function callLine(text)
            return assert(text:match("BattlePauseOverlay%.draw%s*(%b())"),"宿主真实调用未找到")
        end
        local function hostCase(line,values,expect,label)
            local env=setmetatable(values,{__index=_G});env.BattlePauseOverlay=f.overlay;env.vg=vg
            local actual=assert(load("BattlePauseOverlay.draw"..line,"@真实宿主灰层调用","t",env))
            f.clock.setPaused(true);local before=#f.texts;actual()
            eq(#f.texts-before,expect,label.." 真实Label绘制数")
            eq(f.depth,0,label.." 状态平衡")
        end
        hostCase(callLine(scene),{MAP_W=1080,MAP_H=2400,battleActive=false},0,"普通inactive")
        hostCase(callLine(scene),{MAP_W=1080,MAP_H=2400,battleActive=true},1,"普通active")
        local dungeon=source("ui.dungeon.DungeonBattleScene")
        hostCase(callLine(dungeon),{state={battleState="win"},BATTLE_ACTIVE="active"},0,"副本结算")
        hostCase(callLine(dungeon),{state={battleState="active"},BATTLE_ACTIVE="active"},1,"副本active")
        local tower=source("ui.tower.TowerTriBattle")
        hostCase(callLine(tower),{ix=30,iy=60,iw=948,ih=260,state={phase="lose"},lane={cleared=false,wiped=false},BATTLE_ACTIVE="active"},0,"通天塔全灭/结算")
        hostCase(callLine(tower),{ix=30,iy=60,iw=948,ih=260,state={phase="active"},lane={cleared=false,wiped=false},BATTLE_ACTIVE="active"},1,"通天塔active")
        hostCase(callLine(tower),{ix=30,iy=60,iw=948,ih=260,state={phase="active"},lane={cleared=true,wiped=false},BATTLE_ACTIVE="active"},0,"通天塔已清队待会合")
        hostCase(callLine(tower),{ix=30,iy=60,iw=948,ih=260,state={phase="active"},lane={cleared=false,wiped=true},BATTLE_ACTIVE="active"},0,"通天塔全灭队")
        local tri=source("ui.battle.tri.BattleTriPage")
        check(tri:find("drv.active == true",1,true)~=nil and tri:find("not terminalRaid.finished",1,true)~=nil,
            "Tri真实drv.active/终焉finished逐行门禁")
        check(source("ui.dungeon.DungeonBattleScene"):find("680, state.battleState == BATTLE_ACTIVE)",1,true)~=nil,"副本active门禁")
        check(tower:find("state.phase == BATTLE_ACTIVE and not lane.cleared and not lane.wiped",1,true)~=nil,"塔active/cleared/wiped门禁")
        print(TAG.." 宿主门禁为源码契约断言，不冒称四宿主完整集成启动")
    end)
end
local function previewInit(f)
    -- BattleView/BattleDraw/战斗状态及英雄怪物工厂均为私有真实production代码。
    f.mods["ui.battle.combat.BattleClock"]=f.clock
    f.combat=f.load("ui.battle.combat.BattleCombat")
    f.view=f.load("ui.battle.scene.BattleView")
    f.draw=f.load("ui.battle.scene.BattleDraw")
    f.layout=f.load("core.BattleLayout");f.layout.setMode("strip")
    f.view.init(vg)
    local function image(path)
        local handle=nvgCreateImage(vg,path,0);check(handle>=0,"真实图片 "..path);return handle
    end
    local tags={};for i=1,6 do tags[i]=image("image/通用图标/ICON_ZY_"..i..".png") end
    f.draw.setContext{combat=f.combat,imgHeroCards={},imgMonsterCards={},imgAllyTags=tags,
        imgHpBg=image("image/界面底板/战斗/UI_ZD_HP1.png")}
    f.backdrop=image("image/关卡地图/MAP_1.png")
    local heroes=f.load("config.HeroConfig");local monsters=f.load("config.MonsterConfig")
    f.lanes={}
    for row=1,3 do
        local allies,enemies={},{}
        for i=1,4 do
            allies[i]=assert(heroes.createHero(i,60,nil,{},false,{litNodes={},silent=true}))
            enemies[i]=assert(monsters.createMonster(i,60,{}))
        end
        f.lanes[row]={allies=allies,enemies=enemies,state=f.combat.newState("pause-preview-"..row)}
        f.draw.preloadCards(vg,allies);f.draw.preloadCards(vg,enemies)
    end
    f.clock.setPaused(previewState~="running");f.i18n.set(previewLang)
    f.hud=UI.Panel{width=1,height=1,pointerEvents="none",paddingHorizontal=16,
        flexDirection="row",alignItems="center",justifyContent="space-between",
        backgroundColor={33,39,49,255},children={
            UI.Label{text="暂停专项 · 真实BattleView战场",fontFamily="sans",fontWeight="normal",fontSize=20,fontColor={238,202,125,255}},
            UI.Label{text="HUD 保持原色 · 可操作",fontFamily="sans",fontWeight="normal",fontSize=18,fontColor={110,222,181,255}},
        }}
    print(TAG.." 预览夹具=真实BattleView/BattleDraw/工厂/状态/NVG；仅静态三队与HUD为测试组合，不运行玩家战斗/存档")
end
local function rectangle(x,y,w,h,r,g,b)
    nvgBeginPath(vg);nvgRect(vg,x,y,w,h);nvgFillColor(vg,nvgRGBA(r,g,b,255));nvgFill(vg)
end
local function previewDraw(f,w,h)
    rectangle(0,0,w,h,14,18,25)
    if previewLayout=="classic" then
        -- 精确模拟普通BattleScene的1080×2400设计空间经宿主contain到窗口；并非全Scene启动。
        local fit=math.min(w/1080,h/2400);local lane=f.lanes[1]
        nvgSave(vg);nvgTranslate(vg,(w-1080*fit)/2,(h-2400*fit)/2);nvgScale(vg,fit,fit)
        nvgBeginPath(vg);nvgRect(vg,0,0,1080,2400)
        nvgFillPaint(vg,nvgImagePattern(vg,0,0,1080,2400,0,f.backdrop,1));nvgFill(vg)
        f.layout.setMode("classic");f.combat.mount(lane.state)
        local half=f.layout.CARD_H*.5
        f.draw.drawCardGroup(vg,lane.enemies,804,-half+4,half-117,half-54,half-72,181,half-4,-1,false)
        f.draw.drawCardGroup(vg,lane.allies,1760,-half+4,half-134,half-66,half-84,181,half-4,-1,true)
        f.overlay.draw(vg,0,0,1080,2400,previewState~="inactive",2400/1080)
        nvgRestore(vg)
    else
    local left=w*.08;local width=w*.84;local top=100;local rows=previewLayout=="tri" or previewLayout=="tower"
    local count=rows and 3 or 1;local gap=24;local rowHeight=(h-top-80-gap*(count-1))/count
    for row=1,count do
        local x,y,rw,rh=left,top+(row-1)*(rowHeight+gap),width,rowHeight
        if previewLayout=="tower" then x=w*.26;rw=w*.48 end
        local lane=f.lanes[row];local s=math.min(rw/948,rh/360)
        nvgSave(vg);nvgScissor(vg,x,y,rw,rh)
        nvgTranslate(vg,x+(rw-948*s)/2,y+(rh-360*s)/2);nvgScale(vg,s,s)
        f.combat.mount(lane.state)
        f.view.draw(vg,lane,f.backdrop,false)
        nvgRestore(vg)
        -- 灰层按宿主窗口矩形绘制，标牌不随卡牌contentScale二次缩小。
        f.overlay.draw(vg,x,y,rw,rh,previewState~="inactive")
        nvgFontFace(vg,"sans");nvgFontSize(vg,20);nvgTextAlign(vg,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
        nvgFillColor(vg,nvgRGBA(241,198,104,255));nvgText(vg,x+20,y+24,"【小队"..row.."】真实战场 · Lv.60",nil)
        rectangle(x+rw-130,y+10,112,30,48,115,89)
        nvgFillColor(vg,nvgRGBA(243,244,237,255));nvgText(vg,x+rw-118,y+25,"HUD / 撤退",nil)
    end
    end
    f.hud:SetWidth(w);f.hud:SetHeight(70);Surface.draw(f.hud,vg,w,70)
    if frames==100 then
        eq(f.io,0,"预览File/FS访问零");eq(f.blocked,0,"预览玩家/动作访问零")
        eq(f.clock.isPaused(),previewState~="running","预览时钟状态确定")
        check(frames>=100,"真实帧已经稳定")
        print(TAG.." PREVIEW COMPLETE layout="..previewLayout.." state="..previewState.." lang="..previewLang.." frames="..frames)
        finished=true
    end
end
function Start()
    for _,arg in ipairs(GetArguments()) do
        if arg=="-pause-overlay-preview" then preview=true end
        if arg=="-validate" then validateMode=true end
        if arg=="-caption-unclipped-reference" then captionReference=true end
        previewState=arg:match("^%-pause%-overlay%-state=(.+)$") or previewState
        previewLayout=arg:match("^%-pause%-overlay%-layout=(.+)$") or previewLayout
        previewLang=arg:match("^%-pause%-overlay%-lang=(.+)$") or previewLang
    end
    assert(expected[previewLang],"不支持预览语言")
    Surface.init();vg=assert(nvgCreate(1))
    check(nvgCreateFont(vg,"sans","Fonts/NotoSansCJKkr-Bold.otf")>=0,"真实宿主仅注册sans字体")
    fixture=newFixture()
    if preview then previewInit(fixture) end
    SubscribeToEvent(vg,"NanoVGRender","HandlePauseOverlayRender")
end
function HandlePauseOverlayRender()
    if not vg then return end
    if finished and not preview then return end
    frames=frames+1
    local dpr=graphics:GetDPR();local w,h=graphics:GetWidth()/dpr,graphics:GetHeight()/dpr
    nvgBeginFrame(vg,w,h,dpr)
    local ok,err=xpcall(function()
        if preview then previewDraw(fixture,w,h)
        elseif frames==1 then tests();finished=true end
    end,debug.traceback)
    nvgEndFrame(vg)
    if not ok then check(false,"真实渲染异常 "..tostring(err));finished=true;engine:Exit() end
    if finished and not preview and not validateMode then engine:Exit() end
end
function Stop()
    local ok,err=xpcall(function()
        if fixture then
            fixture.overlay.destroy()
            if fixture.hud then fixture.hud:Destroy() end
            fixture.clock.setPaused(false)
        end
        Surface.shutdown();if vg then nvgDelete(vg);vg=nil end
    end,debug.traceback)
    if not ok then check(false,"销毁异常 "..tostring(err)) end
    check(_G.nvgText==raw.text and _G.nvgSave==raw.save and _G.nvgRestore==raw.restore,"没有替全局NVG")
    print(TAG.." FINAL "..(finished and total.failed==0 and "ALL PASS" or "FAILED")..
        " cases="..total.cases.." checks="..total.checks.." failed="..total.failed.." glyphs="..total.glyphs)
end
