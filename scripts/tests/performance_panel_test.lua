-- 性能面板专项：私有_ENV加载production源码；不require main，不访问玩家档。
-- 默认纯内存UI/Monitor/Surface回归；-performance-preview 使用真实组件+内存Monitor供Runtime截图。
-- 真实截图遵循 run-lua-validate：Linux 三个Mesa环境变量 + -graphicssurfaceless，不能用 graphicsheadless。
-- 宽屏概览：-performance-preview -performance-view=summary -x 1920 -y 1080
-- 窄屏概览：-performance-preview -performance-view=summary -x 390 -y 844
-- 宽屏报告：-performance-preview -performance-view=report -x 1920 -y 1080
-- 各自搭配 -screenshot=/home/Maker/<独立验证目录>/<名称>.png -screenshot-frame=180。
-- 输出目录由调用方先建好，Runtime截图完成后自动退出；请确认PNG非空再读图，日志captured不是成功判据。
local TAG = "[performance_panel_test]"
local checks, failures = 0, 0
local function check(ok, name)
    checks = checks + 1
    if not ok then failures = failures + 1; print(TAG .. " FAIL " .. name) end
end
local function source(name)
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), name)
    local lines = {}
    while not file:IsEof() do lines[#lines+1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function memoryMonitor()
    local m = { enabled = false, starts = 0, stops = 0, marks = 0, snapshots = 0,
        reports = 0, exports = 0, excluded = 0, order = {}, failReport = false, failSave = false }
    function m.start() m.enabled=true; m.starts=m.starts+1; m.order[#m.order+1]="start" end
    function m.stop() m.enabled=false; m.stops=m.stops+1; m.order[#m.order+1]="stop" end
    function m.isEnabled() return m.enabled end
    function m.mark() m.marks=m.marks+1 end
    function m.excludeCurrent(reason) assert(reason=="panel"); m.excluded=m.excluded+1 end
    function m.snapshot()
        m.snapshots=m.snapshots+1
        return { enabled=m.enabled, elapsedSeconds=12.5, frames=720, fps=57.6,
            frameMs={p50=16.7,p95=28,p99=66,max=120}, slowFrames={over33=18,over50=7,over100=2},
            luaMemoryKB=18432, resourceMemoryBytes=67108864, batches=38, primitives=16384,
            sections={{name="Battle.Update",calls=720,totalCpuMs=630,maxCpuMs=18,totalWallMs=820,maxWallMs=30}},
            recentSlow={{frame=695,intervalMs=120,context="battle",top={{name="Save.Flush",cpuMs=11,wallMs=84}}}},
            marks={{frame=690,atSeconds=12}}, excludedGaps=2, excludedPanelFrames=4, limits={} }
    end
    function m.getReport()
        assert(not m.enabled,"report must stop first")
        m.reports=m.reports+1; m.order[#m.order+1]="report"
        if m.failReport then error("fixture report failure") end
        local lines={"性能诊断报告（内存夹具）", "无姓名、钱包或完整存档；不会上传。"}
        for i=1,95 do lines[#lines+1]="区段"..i.." CPU 1.0 ms / 墙钟 2.0 ms" end
        lines[#lines+1]='机器JSON {"frames":720,"fps":57.6,"sections":[]}'
        return table.concat(lines,"\n")
    end
    function m.export()
        assert(not m.enabled,"export must stop first")
        m.exports=m.exports+1
        if m.failSave then return false,"fixture_write_failed" end
        return true,"performance_fixture.txt"
    end
    return m
end
local function newFixture(realUI, realSurface)
    local f={ mods={}, monitor=memoryMonitor(), roots={}, widths={}, buttonDraws={}, codeOpens=0,
        surfaceInits=0, rendering=false, io=0, clipboardCalls=0, clipboard="", gesture=false }
    local env=setmetatable({}, {__index=_G}); env._G=env
    local function forbidden() f.io=f.io+1; error("fixture forbids file/player access",0) end
    env.File,env.fileSystem=forbidden,setmetatable({}, {__index=function() return forbidden end})
    env.time={elapsedTime=100}; env.audio={SetMasterGain=function() end}
    env.cjson={encode=forbidden,decode=forbidden}
    local fontSize=20
    if not realUI then
        env.nvgSave=function() end; env.nvgRestore=function() end
        env.nvgFontFace=function() end; env.nvgFontSize=function(_,size) fontSize=size end
        env.nvgTextBounds=function(_,_,_,text) return #text*fontSize*.4 end
        env.nvgTextAlign=function() end; env.nvgFillColor=function() end
        env.nvgRGBA=function() return {} end; env.nvgText=function() end
        env.nvgBeginPath=function() end; env.nvgRoundedRect=function() end
        env.nvgStrokeColor=function() end; env.nvgStrokeWidth=function() end; env.nvgStroke=function() end
        env.nvgFill=function() end; env.nvgCircle=function() end; env.nvgTranslate=function() end
        env.nvgScale=function() end; env.nvgRect=function() end
    end
    local function widget(props)
        local w={props=props or {},children={},bounds={x=0,y=0,w=0,h=0},disabled=props.disabled==true}
        for _,child in ipairs(props.children or {}) do w.children[#w.children+1]=child end
        function w:SetText(text) self.props.text=text end
        function w:GetText() return self.props.text or "" end
        function w:SetDisabled(value) self.disabled=value end
        function w:IsDisabled() return self.disabled end
        function w:SetStyle(style) for key,value in pairs(style) do self.props[key]=value end end
        function w:GetAbsoluteLayout() return self.bounds end
        function w:AddChild(child) self.children[#self.children+1]=child end
        function w:ClearChildren() self.children={} end
        function w:Destroy() self.destroyed=true end
        function w:GetChildAt(index) return self.children[index] end
        function w:FindById(id)
            if self.props.id==id then return self end
            for _,child in ipairs(self.children) do local found=child:FindById(id); if found then return found end end
        end
        return w
    end
    local function size(value,available)
        if type(value)=="number" then return value end
        if type(value)=="string" and value:sub(-1)=="%" then return available*(tonumber(value:sub(1,-2)) or 100)/100 end
        return available
    end
    local function layout(w,x,y,width,height)
        local p=w.props
        w.bounds={x=x,y=y,w=width,h=height}
        local pad=p.padding or 0; local gap=p.gap or 0
        local innerW,innerH=width-2*pad,height-2*pad
        local row=p.flexDirection=="row"
        local fixed,grow,count=0,0,0
        for _,child in ipairs(w.children) do
            if child.props.position~="absolute" then
                count=count+1
                if (child.props.flexGrow or 0)>0 then grow=grow+child.props.flexGrow
                else fixed=fixed+size(row and child.props.width or child.props.height,row and innerW or innerH) end
            end
        end
        local remaining=math.max(0,(row and innerW or innerH)-fixed-math.max(0,count-1)*gap)
        local cursor=0
        for _,child in ipairs(w.children) do
            local cp=child.props
            if cp.position=="absolute" then
                layout(child,x+(cp.left or 0),y+(cp.top or 0),size(cp.width,width),size(cp.height,height))
            else
                local major=(cp.flexGrow or 0)>0 and remaining*cp.flexGrow/math.max(1,grow)
                    or size(row and cp.width or cp.height,row and innerW or innerH)
                layout(child,x+pad+(row and cursor or 0),y+pad+(row and 0 or cursor),
                    row and major or size(cp.width,innerW),row and size(cp.height,innerH) or major)
                cursor=cursor+major+gap
            end
        end
    end
    f.mods["urhox-libs/UI"]=realUI or {Panel=widget,Label=widget,Button=widget,
        Theme={FontSize=function(pt) return pt*4/3 end}}
    f.mods["core.PerformanceMonitor"]=f.monitor
    f.mods["ui.widget.DesignWidgetSurface"]={
        init=function() assert(not f.rendering,"Surface.init cannot originate in render"); f.surfaceInits=f.surfaceInits+1; if realSurface then realSurface.init() end end,
        draw=function(root,vg,width,height)
            f.roots[#f.roots+1]=root; f.root=root
            if realSurface then realSurface.draw(root,vg,width,height) else layout(root,0,0,width,height) end
        end,
    }
    f.mods["core.DrawUtil"]={hitTest=function(x,y,cx,cy,w,h) return math.abs(x-cx)<=w/2 and math.abs(y-cy)<=h/2 end,
        drawTextStroke=function() end,easeOutBack=function(x) return x end}
    f.mods["ui.hud.popup.RedeemCodePanel"]={init=function() end,isOpen=function() return false end,
        open=function() f.codeOpens=f.codeOpens+1 end,draw=function() end,update=function() end}
    f.mods["systems.GameBGM"]={setMasterGain=function() end}
    f.mods["core.I18n"]={LANGS={{id="zh_CN",label="中文"}},get=function() return "zh_CN" end,
        t=function(key) return key end,set=function() return false end}
    f.mods["systems.ButtonFeedback"]={trigger=function() end,finish=function() end,
        begin=function(_,name,cx,cy,w,h) f.buttonDraws[name]={x=cx,y=cy,w=w,h=h}; return false end}
    f.mods["core.DarkIcon"]={drawNine=function() end}
    env.require=function(name)
        if f.mods[name] then return f.mods[name] end
        assert(name=="ui.dev.PerformancePanel" or name=="ui.hud.popup.SettingsPanel"
            or name=="ui.dev.KeyboardShortcuts" or name=="boot.PerformanceRuntime", "unexpected module "..name)
        local value=assert(load(source(name),"@isolated:"..name,"t",env))()
        f.mods[name]=value; return value
    end
    f.keys = {}
    f.ctrl = false
    f.env = env
    env.input = { GetKeyPress = function(_, key) return f.keys[key] == true end,
        GetQualifierDown = function() return f.ctrl end }
    f.mods["core.UiToast"] = { show = function() end }
    f.mods["ui.story.gate.DarkTitleScreenGate"] = { isOpen = function() return f.title == true end }
    f.mods["ui.dev.GMConsolePanel"] = { isOpen = function() return f.typing == true end }
    f.mods["ui.character.hero.AwakeningArtwork"] = { isOpen = function() return false end }
    f.mods["boot.StandaloneRT"] = { entryRendered = true }
    f.mods["boot.PerformanceHooks"] = { getModule = function() return nil end }
    f.monitor.beginFrame = function() end
    f.monitor.fail = function(stage) error("unexpected diagnostic failure: " .. stage) end
    f.panel=env.require("ui.dev.PerformancePanel")
    function f:draw(width,height,vg)
        self.width,self.height=width or self.width or 1080,height or self.height or 2400
        self.rendering=true; self.panel.draw(vg or {},self.width,self.height); self.rendering=false
    end
    function f:findText(text)
        local function find(w)
            if w.props.text==text then return w end
            for _,child in ipairs(w.children) do local result=find(child); if result then return result end end
        end
        return self.root and find(self.root)
    end
    function f:contains(text)
        local function find(w)
            if type(w.props.text)=="string" and w.props.text:find(text,1,true) then return true end
            for _,child in ipairs(w.children) do if find(child) then return true end end
            return false
        end
        return self.root and find(self.root)
    end
    function f:point(text)
        local b=assert(self:findText(text),"missing button "..text):GetAbsoluteLayout()
        return b.x+b.w/2,b.y+b.h/2
    end
    function f:tap(text,id)
        local x,y=self:point(text); id=id or "mouse"
        self.gesture=true
        check(self.panel.handlePointer("down",x,y,id),"modal down consumed")
        check(self.panel.handlePointer("up",x,y,id),"modal up consumed")
        self.gesture=false
    end
    return f
end
local function runTests()
    local f=newFixture(); local p,m=f.panel,f.monitor
    p.init(); check(not p.isOpen() and m.snapshots==0,"init closed and Monitor untouched")
    p.open(); f:draw(); check(p.isOpen(),"open and draw")
    local x,y=f:point("开始采集")
    p.handlePointer("up",x,y,"mouse"); check(m.starts==0,"up without down ignored")
    p.handlePointer("down",x,y,"mouse"); check(m.starts==0,"down never activates")
    p.handlePointer("up",x,y,0); check(m.starts==0,"touch zero cannot release mouse")
    p.handlePointer("up",x,y,"mouse"); check(m.starts==1,"same mouse activates")
    local before=m.snapshots; p.update(.4);p.update(.59);check(m.snapshots==before,"summary not per-frame")
    p.update(.02);check(m.snapshots==before+1,"summary refresh one second")
    f:tap("标记卡顿",7);check(m.marks==1,"touch same identity mark")
    x,y=f:point("标记卡顿")
    p.handlePointer("down",x,y,1);p.handlePointer("down",x,y,2)
    p.handlePointer("up",x,y,1);p.handlePointer("up",x,y,2);check(m.marks==1,"two touches cancel")
    p.handlePointer("down",x,y,3);p.handlePointer("move",x+13,y,3);p.handlePointer("move",x,y,3)
    p.handlePointer("up",x,y,3);check(m.marks==1,"move over 12 remains canceled after ABA")
    p.handlePointer("down",x,y,3);p.handlePointer("move",x+12,y,3);p.handlePointer("up",x,y,3)
    check(m.marks==2,"exact threshold allowed")
    p.handlePointer("down",x,y,3);f:draw(600,900);p.handlePointer("up",x,y,3)
    check(m.marks==2,"resize cancels old layout press")
    f:tap("停止");check(not m.enabled and m.stops>0,"stop preserves data")
    f:tap("开始采集");check(m.enabled,"restart starts")
    x,y=f:point("标记卡顿");p.handlePointer("down",x,y,"mouse");p.close()
    check(m.enabled,"close never stops")
    check(p.handlePointer("up",x,y,"mouse"),"close tail consumed")
    check(not p.handlePointer("move",x,y,"mouse"),"closed after tail does not block")
    p.open();check(m.excluded==1,"opening during sample excludes current frame");f:draw()
    x,y=f:point("标记卡顿");p.handlePointer("down",x,y,"mouse");p.resetPointer();f:draw()
    p.handlePointer("up",x,y,"mouse");check(m.marks==2,"reset cancels")
    f:tap("生成报告");check(not m.enabled and m.reports==1,"generate stops then reports")
    check(m.order[#m.order-1]=="stop" and m.order[#m.order]=="report","report call order")
    check(f:contains("报告 1 /"),"report pagination caption")
    f:tap("下一页");check(f:contains("报告 2 /"),"next page")
    f:tap("上一页");check(f:contains("报告 1 /"),"previous page")
    f.env.ui={SetClipboardText=function() error("denied") end}
    f:tap("复制报告");check(f:contains("无法确认系统剪贴板写入"),"clipboard thrown failure")
    f.env.ui={SetClipboardText=function() end,GetClipboardText=function() return "different" end}
    f:tap("复制报告");check(f:contains("无法确认系统剪贴板写入"),"clipboard mismatch not success")
    f.env.ui={}
    f:tap("复制报告");check(f:contains("无法确认系统剪贴板写入"),"missing clipboard method not success")
    f.env.ui={SetClipboardText=function(_,text)
        check(f.gesture,"clipboard same user gesture")
        f.clipboardCalls=f.clipboardCalls+1;f.clipboard=text
    end,GetClipboardText=function() return f.clipboard end}
    f:tap("复制报告");check(f.env.ui.useSystemClipboard==true and f.clipboardCalls==1,"system clipboard enabled")
    check(f:contains("已复制报告到系统剪贴板"),"readback verified success")
    f:tap("保存本地");check(m.exports==1 and f:contains("performance_fixture.txt"),"local export path")
    m.failSave=true;f:tap("保存本地");check(f:contains("fixture_write_failed"),"export reason shown")
    m.failReport=true;before=m.exports;f:tap("保存本地");check(m.exports==before,"failed report does not export")
    check(f:contains("报告生成失败"),"report failure retained")
    m.failReport=false;p.close();p.resetPointer()
    -- Settings不调用init，避免原有loadSettings触档；只加载隔离模块，模拟实际draw入口。
    local settings=f.env.require("ui.hud.popup.SettingsPanel")
    settings.open();f.env.time.elapsedTime=101;settings.draw({})
    local code=f.buttonDraws.set_code
    check(code.x==540 and code.w==750 and code.h==100 and not f.buttonDraws.set_performance,
        "独立设置仅保留居中兑换码，不再放诊断入口")
    settings.handleInput(code.x,code.y);check(f.codeOpens==1 and not p.isOpen(),"兑换码不打开性能诊断")
    settings.drawEmbedded({},40);code=f.buttonDraws.set_code
    check(code.x==540 and not f.buttonDraws.set_performance,"角色栏嵌入设置不再放诊断入口")
    settings.handleEmbeddedInput(code.x,code.y,40);check(f.codeOpens==2 and not p.isOpen(),"嵌入兑换码仍正常")

    local keyboard=f.env.require("ui.dev.KeyboardShortcuts")
    local runtime=f.env.require("boot.PerformanceRuntime")
    local rt=f.mods["boot.StandaloneRT"]
    local starts,stops=m.starts,m.stops
    f.keys={[KEY_F8]=true};runtime.updateBefore(.01);keyboard.update()
    check(p.isOpen() and m.starts==starts and m.stops==stops,"F8独立打开，不双切换、不开始或停止采集")
    f.keys={};runtime.updateBefore(.01)
    check(p.isOpen(),"长按没有新Press时不反复切换")
    f.keys={[KEY_F8]=true};runtime.updateBefore(.01);keyboard.update()
    check(not p.isOpen() and m.stops==stops,"再次F8关闭且保留采集状态")
    f.typing=true;runtime.updateBefore(.01);check(not p.isOpen(),"输入期间F8不抢焦点")
    f.typing=false;f.title=true;runtime.updateBefore(.01);check(not p.isOpen(),"标题屏不打开隐形诊断")
    f.title=false;f.ctrl=true;runtime.updateBefore(.01);check(not p.isOpen(),"Ctrl修饰键不误开")
    f.ctrl=false;rt.entryPreparing=true;runtime.updateBefore(.01);check(not p.isOpen(),"入场加载阶段不打开")
    rt.entryPreparing=false;rt.entryRendered=false;runtime.updateBefore(.01);check(not p.isOpen(),"首个游戏画面呈现前不打开")
    rt.entryRendered=true;runtime.updateBefore(.01)
    check(p.isOpen(),"无需正常快捷键Update，业务早退前也可F8打开")
    f.keys={[KEY_ESCAPE]=true};keyboard.update();check(not p.isOpen(),"Esc关闭诊断，不关闭底层页面")
    m.start();f.keys={[KEY_F8]=true};runtime.updateBefore(.01);keyboard.update()
    local activeStops=m.stops
    runtime.updateBefore(.01);keyboard.update()
    check(not p.isOpen() and m.enabled and m.stops==activeStops,"采集中F8关闭不停止采集")
    f.keys={};m.stop()
    check(f.io==0,"no player archive or filesystem accessed")
end
---@type NVGContextWrapper?
local previewVG=nil
---@type table?
local previewFixture=nil
local previewView, previewFrames, previewStarted = "summary", 0, 0
local previewReportReady = false
function Start()
    local preview=false
    local screenshot = ""
    for _,arg in ipairs(GetArguments()) do
        if arg=="-performance-preview" then preview=true end
        previewView=arg:match("^%-performance%-view=(.+)$") or previewView
        screenshot=arg:match("^%-screenshot=(.+)$") or screenshot
    end
    if preview then
        local ok,err=xpcall(function()
            assert(previewView=="summary" or previewView=="report","performance-view must be summary/report")
            -- PNG只交给Runtime截图设施；不使用File/玩家savedata，也不把截图写进项目目录。
            assert(screenshot=="" or screenshot:match("^/home/Maker/[^%z]+%.png$")
                and not screenshot:find("..",1,true),"preview screenshot must use isolated /home/Maker directory")
            local uiLib=require("urhox-libs/UI")
            local surface=require("ui.widget.DesignWidgetSurface")
            previewFixture=newFixture(uiLib,surface)
            previewFixture.panel.init();previewFixture.monitor.start();previewFixture.panel.open()
            previewVG=nvgCreate(1)
            assert(nvgCreateFont(previewVG,"sans","Fonts/NotoSansCJKkr-Bold.otf")>=0,"host font")
            previewStarted=time.elapsedTime
            SubscribeToEvent(previewVG,"NanoVGRender","HandlePerformancePreview")
            print(TAG.." PREVIEW real UI, memory-only Monitor; view="..previewView.."; main not loaded; screenshot="..screenshot)
        end,debug.traceback)
        if not ok then log:Write(LOG_ERROR,TAG.." preview init "..tostring(err));engine:Exit() end
        return
    end
    local ok,err=xpcall(runTests,debug.traceback)
    if not ok then failures=failures+1;print(TAG.." ERROR "..tostring(err)) end
    print(TAG.." checks="..checks.." failures="..failures)
    if failures>0 then log:Write(LOG_ERROR,TAG.." FAILED") end
    engine:Exit()
end
function HandlePerformancePreview()
    if not previewFixture or not previewVG then return end
    local dpr=graphics:GetDPR()
    local w,h=graphics:GetWidth()/dpr,graphics:GetHeight()/dpr
    nvgBeginFrame(previewVG,w,h,dpr)
    nvgBeginPath(previewVG);nvgRect(previewVG,0,0,w,h)
    nvgFillColor(previewVG,nvgRGBA(12,13,17,255));nvgFill(previewVG)
    local ok,err=xpcall(function()
        previewFixture:draw(w,h,previewVG)
        if previewView=="report" and not previewReportReady then
            -- 真实布局命中生产按钮，不通过私有字段直接塞报告。
            previewFixture:tap("生成报告")
            previewReportReady=true
        end
        previewFrames=previewFrames+1
        if previewFrames==3 then
            assert(previewFixture.io==0,"preview must never access player archives")
            assert(previewFixture:contains(previewView=="report" and "报告 1 /" or "采集中"),"preview state shown")
            print(TAG.." PREVIEW_READY "..previewView.." logical="..w.."x"..h.." real UI, playerIO=0")
        end
    end,debug.traceback)
    nvgEndFrame(previewVG)
    if not ok then log:Write(LOG_ERROR,TAG.." preview render "..tostring(err));engine:Exit();return end
    -- 正常由-screenshot-frame自动退出；缺少截图参数或设施异常时只作失败保护，不宣称出图成功。
    if time.elapsedTime-previewStarted>90 then
        log:Write(LOG_ERROR,TAG.." screenshot timeout; verify Runtime -screenshot/-screenshot-frame")
        engine:Exit()
    end
end
