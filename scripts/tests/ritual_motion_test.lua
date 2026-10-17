-- 独立仪式动效契约：真实源码闭合依赖 + 受控几何 + 实际 NanoVG/Spine 帧。
-- 禁止将受控对象当 GPU 实证；实际 native 的 Load/Render/补层填色另行统计。
-- 不载 main / Boot、不修改全局、不访问玩家档；源读取仅由测试 ResourceCache 只读执行。
-- Runtime ... -graphicssurfaceless -validate -validate-frames=130 -nosound
local TAG="[ritual_motion_test]"
local KINDS={"level","job","revive","success","failure","power"}
local DURATION={level=1.3333,job=1.3333,revive=.9,success=1.6667,failure=1.3333,power=3.2}
local counts={checks=0,failures=0,cases=0,actualLoads=0,actualRenders=0,actualMotionFills=0}
local sources={}
local nativeFixtures={}
local actualStage=0
local finished=false
local logicOnly=false
---@type NVGContextWrapper?
local actualVG=nil
local original={require=require,random=math.random,seed=math.randomseed,create=nvgSpineCreate,render=nvgSpineRender}
local function check(ok,label)
    counts.checks=counts.checks+1
    if not ok then counts.failures=counts.failures+1 end
    print(TAG..(ok and " PASS " or " FAIL ")..label)
end
local function eq(a,b,label) check(a==b,label.." actual="..tostring(a).." expected="..tostring(b)) end
local function near(a,b,label) check(type(a)=="number" and math.abs(a-b)<.00001,label) end
local function case(name,fn)
    counts.cases=counts.cases+1
    local ok,err=pcall(fn)
    if not ok then check(false,name.." HARNESS "..tostring(err)) end
    print(TAG.." CASE "..name)
end
local function read(path)
    if sources[path] then return sources[path] end
    local file=assert(cache:GetFile(path),"缺真实源码 "..path)
    local lines={};while not file:IsEof() do lines[#lines+1]=file:ReadLine() end
    file:Dispose();sources[path]=table.concat(lines,"\n")
    return sources[path]
end
local function closedEnv(logs)
    local mathEnv={};for k,v in pairs(math) do mathEnv[k]=v end
    mathEnv.random=function() error("禁止消费业务 RNG",0) end;mathEnv.randomseed=mathEnv.random
    local env={assert=assert,error=error,ipairs=ipairs,pairs=pairs,next=next,type=type,tostring=tostring,
        tonumber=tonumber,select=select,pcall=pcall,xpcall=xpcall,setmetatable=setmetatable,getmetatable=getmetatable,
        rawget=rawget,rawset=rawset,string=string,table=table,math=mathEnv}
    env.print=function(...) local t={};for i=1,select("#",...) do t[i]=tostring(select(i,...)) end
        logs[#logs+1]=table.concat(t," ") end
    env._G=env
    for k,v in pairs(_G) do if type(k)=="string" and k:match("^NVG_") then env[k]=v end end
    local forbidden=function() error("程序层访问文件/时钟/事件",0) end
    env.File=forbidden;env.cache=setmetatable({},{__index=forbidden});env.fileSystem=env.cache
    env.io=env.cache;env.time=env.cache;env.SubscribeToEvent=forbidden;env.SendEvent=forbidden
    return env
end
local function loadModules(env,stats,disableMotion)
    local allowed={ ["ui.fx.DarkRitualMotion"]=true,["ui.fx.DarkEffectSprites"]=true,["ui.fx.DarkEffectPrimitives"]=true,
        ["core.DarkIcon"]=true,["core.DrawUtil"]=true,["core.BattleLayout"]=true }
    local modules={}
    env.require=function(name)
        assert(allowed[name],"未允许依赖 "..name)
        if modules[name] then return modules[name] end
        local path=name:gsub("%.","/")..".lua"
        local mod=assert(load(read(path),"@ritual-closed-real/"..path,"t",env))()
        if name=="ui.fx.DarkRitualMotion" then
            local draw=mod.draw
            mod.draw=function(...)
                stats.motionCalls=stats.motionCalls+1
                if disableMotion then return true end
                stats.inMotion=true
                local ok,result=pcall(draw,...)
                stats.inMotion=false
                if not ok then error(result,0) end
                return result
            end
        elseif name=="ui.fx.DarkEffectPrimitives" then
            for _,key in ipairs({"drawCard","drawResult","drawPower"}) do
                local method=mod[key]
                mod[key]=function(...) stats.fallback=stats.fallback+1;return method(...) end
            end
        end
        modules[name]=mod
        return mod
    end
    return env.require("ui.fx.DarkEffectSprites"),env.require("ui.fx.DarkRitualMotion")
end
local function fixture(opts)
    opts=opts or {}
    local stats={logs={},depth=0,stack={},vertices={},colors={},draws={},saves=0,fills=0,motionFills=0,motionCalls=0,
        inMotion=false,loads=0,renders=0,updates=0,unloads=0,disposes=0,images=0,patterns=0,fallback=0,gradient=0}
    local env=closedEnv(stats.logs)
    local host={a=.7,b=.11,c=-.05,d=.9,x=71,y=33,alpha=.37,scissor="host-clip",fill="host-fill"}
    local function clone(t) local c={};for k,v in pairs(t) do c[k]=v end;return c end
    local before=clone(host)
    env.nvgSave=function()
        if opts.saveThrow then error("SAVE_TEST",0) end
        stats.saves=stats.saves+1;stats.stack[#stats.stack+1]=clone(host);stats.depth=stats.depth+1
    end
    env.nvgRestore=function()
        if opts.restoreThrow then error("RESTORE_TEST",0) end
        host=assert(table.remove(stats.stack));stats.depth=stats.depth-1
    end
    env.nvgTranslate=function(_,x,y) host.x=host.x+host.a*x+host.c*y;host.y=host.y+host.b*x+host.d*y end
    env.nvgScale=function(_,x,y) host.a=host.a*x;host.b=host.b*x;host.c=host.c*y;host.d=host.d*y end
    local function point(_,x,y)
        assert(type(x)=="number" and type(y)=="number" and x==x and y==y and math.abs(x)<math.huge and math.abs(y)<math.huge,"非法几何")
        stats.vertices[#stats.vertices+1]={x,y,host.a*x+host.c*y+host.x,host.b*x+host.d*y+host.y,stats.inMotion}
    end
    env.nvgMoveTo=point;env.nvgLineTo=point
    env.nvgBeginPath=function() end;env.nvgClosePath=function() end
    env.nvgRGBA=function(r,g,b,a)
        local c={r,g,b,a};stats.colors[#stats.colors+1]=c;return c
    end
    env.nvgFillColor=function(_,color) host.fill=color end
    env.nvgFillPaint=function(_,paint) host.fill=paint end
    env.nvgFill=function()
        if opts.fillThrow then error("FILL_TEST",0) end
        stats.fills=stats.fills+1
        stats.draws[#stats.draws+1]={host.alpha,host.scissor,stats.inMotion}
        if stats.inMotion then stats.motionFills=stats.motionFills+1 end
    end
    env.nvgLinearGradient=function(...) stats.gradient=stats.gradient+1;return {} end
    for _,name in ipairs({"nvgBezierTo","nvgStroke","nvgStrokeColor","nvgStrokeWidth","nvgLineCap","nvgLineJoin"}) do env[name]=function() end end
    for _,name in ipairs({"nvgGlobalAlpha","nvgScissor","nvgResetScissor","nvgIntersectScissor","nvgResetTransform","nvgText","nvgTextBox"}) do
        env[name]=function() error("改变宿主状态/重写文字 "..name,0) end
    end
    if not opts.noImages then
        env.nvgCreateImage=function() stats.images=stats.images+1;return stats.images end
        env.nvgDeleteImage=function() end
        env.nvgImagePattern=function() stats.patterns=stats.patterns+1;return {} end
    end
    if not opts.noNative then
        env.nvgSpineCreate=function()
            local instance={time=0,color={},slot={}}
            function instance:Load() stats.loads=stats.loads+1;return true end
            function instance:SetAnimation(_,name) self.animation=name;return true end
            function instance:GetAnimationDuration() return DURATION[self.animation] end
            function instance:Update(dt) self.time=self.time+dt;stats.updates=stats.updates+1 end
            function instance:UpdateWorldTransform() end
            function instance:SetPosition() end;function instance:SetScale() end;function instance:SetColor() end
            function instance:Unload() stats.unloads=stats.unloads+1 end
            function instance:Dispose() stats.disposes=stats.disposes+1 end
            function instance.slot:IsValid() return true end
            function instance.slot:SetColor(_,_,_,a) self.alpha=a end
            function instance:FindSlot() return self.slot end
            stats.instance=instance;return instance
        end
        env.nvgSpineRender=function(_,instance)
            stats.renders=stats.renders+1
            if instance.animation=="power" then assert(instance.slot.alpha==0,"power白线未屏蔽") end
        end
    end
    if opts.noGradient then env.nvgLinearGradient=nil end
    if opts.empty then for k in pairs(env) do if k:match("^nvg") then env[k]=nil end end end
    local rich,motion=loadModules(env,stats,opts.disableMotion)
    return {env=env,rich=rich,motion=motion,stats=stats,vg={},before=before,host=function() return host end}
end
local function draw(f,kind,p,alpha,token)
    local d=DURATION[kind]
    if kind=="power" then f.rich.drawPower(f.vg,0,0,760,340,p*d,d,alpha,token)
    elseif kind=="success" or kind=="failure" then f.rich.drawResult(f.vg,kind=="success",0,0,200,p*d,d,alpha,token)
    else f.rich.drawCard(f.vg,kind,0,0,200,350,p*d,d,alpha,token) end
end
local function signature(f)
    local t={}
    for _,v in ipairs(f.stats.vertices) do
        t[#t+1]=string.format("%.12g %.12g %.12g %.12g",v[1],v[2],v[3],v[4])
    end
    for _,c in ipairs(f.stats.colors) do t[#t+1]=table.concat(c,",") end
    return table.concat(t,"|")
end
local function clear(f)
    f.stats.vertices={};f.stats.colors={};f.stats.draws={}
end
local function runLogic()
    case("纯采样闭合无 IO / RNG / 事件 / 列表",function()
        local f=fixture()
        local s=read("ui/fx/DarkRitualMotion.lua")
        check(not s:find("require%s*%(") and not s:find("math%.random") and not s:find("SubscribeToEvent")
            and not s:find("cache:") and not s:find("File%(") and not s:find("time%."),"程序helper无外部依赖与副作用调用")
        local sample=s:match("function M%.sample.-\nend")
        check(sample and not sample:find("{",1,true),"sample仅多返回值，无每帧采样表")
        for _,kind in ipairs(KINDS) do
            for _,p in ipairs({-.2,0,.001,.12,.30,.43,.66,.84,.999,1,1.2}) do
                local a={f.motion.sample(kind,p*DURATION[kind],DURATION[kind],1)}
                local b={f.motion.sample(kind,p*DURATION[kind],DURATION[kind],1)}
                for i=1,#a do eq(a[i],b[i],"重复纯采样 "..kind.."/"..p.."/"..i) end
                if p<=0 or p>=1 then eq(a[2],0,"零/结束alpha零 "..kind.."/"..p) end
            end
        end
    end)
    case("native新增可见程序绘制，不是 PNG 时间线",function()
        for _,kind in ipairs(KINDS) do
            local f=fixture();local baseline=fixture({disableMotion=true});local token={}
            for _,p in ipairs({.12,.40,.84}) do
                local before=f.stats.motionFills
                draw(f,kind,p,1,token);draw(baseline,kind,p,1,{})
                check(f.stats.motionFills>before,"native新增draw前奏/峰值/余烬 "..kind.."/"..p)
            end
            eq(f.stats.loads,1,"每token一次nativeLoad "..kind)
            eq(f.stats.renders,3,"实际走native分支 "..kind)
            eq(f.stats.images,0,"native没PNG预热代替 "..kind)
            eq(f.stats.patterns,0,"native无PNG采样 "..kind)
            eq(f.stats.fallback,0,"native无vector替身 "..kind)
            eq(baseline.stats.motionFills,0,"禁helper基线无新增draw "..kind)
            local time=f.stats.instance.time;local updates=f.stats.updates
            draw(f,kind,.84,1,token);near(f.stats.instance.time,time,"同elapsed不推进native "..kind)
            eq(f.stats.updates,updates,"LastElapsed去重 "..kind)
            f.rich.release(token);f.rich.release(token);eq(f.stats.unloads,1,"单Unload "..kind)
            eq(f.stats.disposes,0,"Unload后绝不Dispose "..kind)
            local renders=f.stats.renders;draw(f,kind,.90,1,token);eq(f.stats.renders,renders,"墓碑不复活 "..kind)
        end
    end)
    case("PNG / vector 后端只共享一套程序补层",function()
        for _,kind in ipairs(KINDS) do
            for _,opts in ipairs({{noNative=true},{noNative=true,noImages=true}}) do
                local f=fixture(opts);draw(f,kind,.40,1,{})
                eq(f.stats.motionCalls,1,"fallback只一次helper "..kind.."/"..tostring(opts.noImages))
                check(f.stats.motionFills>0,"fallback新增可见纹章 "..kind)
                if opts.noImages then eq(f.stats.fallback,1,"真正矢量路径 "..kind)
                else eq(f.stats.images,14,"仍共享14图 "..kind);check(f.stats.patterns>0,"真正PNG路径 "..kind) end
                eq(f.stats.depth,0,"fallback栈恢复 "..kind)
            end
        end
    end)
    case("重复绘制 A-B-A 等像、宿主状态与 alpha 乘法",function()
        local signatures={}
        for _,kind in ipairs(KINDS) do
            local f=fixture();f.motion.draw(f.vg,kind,0,0,760,340,.4*DURATION[kind],DURATION[kind],1)
            local first=signature(f)
            clear(f);f.motion.draw(f.vg,kind,0,0,760,340,.7*DURATION[kind],DURATION[kind],1)
            check(signature(f)~=first,"异时有运动 "..kind)
            clear(f);f.motion.draw(f.vg,kind,0,0,760,340,.4*DURATION[kind],DURATION[kind],1)
            eq(signature(f),first,"A-B-A严格等像 "..kind);signatures[kind]=first
            for key,value in pairs(f.before) do eq(f.host()[key],value,"保宿主 "..kind.."/"..key) end
            for _,state in ipairs(f.stats.draws) do eq(state[1],.37,"内部draw不覆盖hostAlpha "..kind);eq(state[2],"host-clip","内部draw沿用scissor "..kind) end
            local full={};for i,c in ipairs(f.stats.colors) do full[i]=c[4] end
            clear(f);f.motion.draw(f.vg,kind,0,0,760,340,.4*DURATION[kind],DURATION[kind],.5)
            eq(#f.stats.colors,#full,"alpha不改几何阶段 "..kind)
            for i,c in ipairs(f.stats.colors) do check(math.abs(full[i]*.5-c[4])<=.501,"逐色alpha乘法 "..kind.."/"..i) end
            eq(f.stats.depth,0,"保宿主栈 "..kind)
        end
        for i=1,#KINDS do for j=i+1,#KINDS do check(signatures[KINDS[i]]~=signatures[KINDS[j]],"主题明显不同 "..KINDS[i].."/"..KINDS[j]) end end
    end)
    case("所有帧有限包络 / 战力中央580无白线",function()
        for _,kind in ipairs(KINDS) do
            local f=fixture();local power=kind=="power";local card=kind=="level" or kind=="job" or kind=="revive"
            local w,h=power and 760 or 200,card and 350 or (power and 340 or 200)
            for step=1,99 do
                clear(f);f.motion.draw(f.vg,kind,0,0,w,h,step/100*DURATION[kind],DURATION[kind],1)
                local safe=true
                for _,v in ipairs(f.stats.vertices) do
                    if math.abs(v[1])>(power and 380 or 100) or math.abs(v[2])>(card and 175 or (power and 170 or 100)) then safe=false end
                    if power and math.abs(v[1])<290 then safe=false end
                end
                check(safe,"有限尺寸与中央文字避让 "..kind.."/"..step)
            end
        end
    end)
    case("空 API / 单次降级 / 失败仍恢复状态",function()
        local empty=fixture({empty=true})
        for _,kind in ipairs(KINDS) do
            check(pcall(draw,empty,kind,.4,1,{}),"全后端空API不崩 "..kind)
            eq(empty.stats.fills,0,"全空不画 "..kind)
        end
        local noGradient=fixture({noGradient=true})
        noGradient.motion.draw(noGradient.vg,"level",0,0,200,350,.4,1,1)
        local logs=#noGradient.stats.logs
        check(noGradient.stats.motionFills>0,"缺渐变仍有薄线纹章")
        noGradient.env.nvgLinearGradient=function() error("不应重新探测渐变",0) end
        for _=1,5 do noGradient.motion.draw(noGradient.vg,"level",0,0,200,350,.5,1,1) end
        eq(#noGradient.stats.logs,logs,"API单次降级日志锁存")
        local bad=fixture({fillThrow=true})
        eq(bad.motion.draw(bad.vg,"level",0,0,200,350,.4,1,1),false,"绘制故障返回失败")
        eq(bad.stats.depth,0,"故障恢复自己Save")
        local saves=bad.stats.saves;local errors=#bad.stats.logs
        for _=1,5 do bad.motion.draw(bad.vg,"level",0,0,200,350,.5,1,1) end
        eq(bad.stats.saves,saves,"绘图故障不逐帧重试")
        eq(#bad.stats.logs,errors,"故障不重复日志")
        for _,opts in ipairs({{saveThrow=true},{restoreThrow=true}}) do
            local f=fixture(opts)
            check(not pcall(f.motion.draw,f.vg,"job",0,0,200,350,.4,1,1),"未知Save/Restore异常传播")
        end
        local f=fixture()
        for _,p in ipairs({0,1,-1,2,0/0,math.huge}) do f.motion.draw(f.vg,"job",0,0,200,350,p,1,1) end
        for _,a in ipairs({0,-1,0/0,math.huge}) do f.motion.draw(f.vg,"job",0,0,200,350,.4,1,a) end
        eq(f.stats.saves,0,"零alpha/结束/非法输入不接触NVG")
    end)
end
local function actualFixture()
    local stats={logs={},motionCalls=0,inMotion=false,fallback=0}
    local env=closedEnv(stats.logs)
    for k,v in pairs(_G) do if type(k)=="string" and k:match("^nvg") then env[k]=v end end
    local fill=nvgFill
    env.nvgFill=function(vg)
        fill(vg)
        if stats.inMotion then counts.actualMotionFills=counts.actualMotionFills+1 end
    end
    env.nvgSpineCreate=function(vg)
        local obj=assert(original.create(vg));local proxy={native=obj}
        for _,key in ipairs({"SetAnimation","GetAnimationDuration","Update","UpdateWorldTransform","SetPosition","SetScale","SetColor","SetSpeed","SetTimeScale","SetPremultipliedAlpha","FindSlot","Unload","Dispose"}) do
            local method=obj[key]
            if type(method)=="function" then proxy[key]=function(_,...) return method(obj,...) end end
        end
        function proxy:Load(path)
            local ok=obj:Load(path)
            check(ok and obj:IsLoaded(),"真实nativeLoad "..path)
            if ok then counts.actualLoads=counts.actualLoads+1 end
            return ok
        end
        return proxy
    end
    env.nvgSpineRender=function(vg,proxy) original.render(vg,proxy.native);counts.actualRenders=counts.actualRenders+1 end
    local rich=loadModules(env,stats,false)
    return {rich=rich,stats=stats,vg=actualVG}
end
local function finish()
    if finished then return end;finished=true
    eq(require,original.require,"未替换全局require");eq(math.random,original.random,"未替换全局RNG")
    eq(math.randomseed,original.seed,"未替换全局seed");eq(nvgSpineCreate,original.create,"未替换全局SpineCreate")
    eq(nvgSpineRender,original.render,"未替换全局SpineRender")
    print(string.format("%s %s cases=%d assertions=%d failures=%d actualNativeLoads=%d actualNativeRenders=%d actualMotionFills=%d",
        TAG,counts.failures==0 and "ALL PASS" or "FAILED",counts.cases,counts.checks,counts.failures,counts.actualLoads,counts.actualRenders,counts.actualMotionFills))
    if counts.failures>0 then error("ritual_motion_test assertion failures="..counts.failures,0) end
end
function Start()
    for _,arg in ipairs(GetArguments()) do if arg=="-ritual-logic-only" then logicOnly=true end end
    runLogic()
    if logicOnly then finish();return end
    actualVG=assert(nvgCreate(1))
    SubscribeToEvent(actualVG,"NanoVGRender","HandleRitualMotionTestRender")
end
function HandleRitualMotionTestRender()
    if finished then return end
    if actualStage==1 then
        for _,f in ipairs(nativeFixtures) do f.rich.destroy() end
        finish();return
    end
    actualStage=1
    local dpr=graphics:GetDPR()
    nvgBeginFrame(actualVG,graphics:GetWidth()/dpr,graphics:GetHeight()/dpr,dpr)
    case("真实Runtime native与程序补层共同提交",function()
        for _,kind in ipairs(KINDS) do
            local f=actualFixture();nativeFixtures[#nativeFixtures+1]=f
            local before=counts.actualMotionFills
            draw(f,kind,.4,1,{})
            check(counts.actualMotionFills>before,"真实native额外nvgFill "..kind)
            eq(f.stats.fallback,0,"真实native不以矢量fallback充当成功 "..kind)
        end
        eq(counts.actualLoads,6,"真实六次Load")
        eq(counts.actualRenders,6,"真实六次SpineRender")
        check(counts.actualMotionFills>200,"真实程序补层可见绘制非PNG-only")
    end)
    nvgEndFrame(actualVG)
end
function Stop()
    for _,f in ipairs(nativeFixtures) do f.rich.destroy() end
    if actualVG then nvgDelete(actualVG);actualVG=nil end
end
