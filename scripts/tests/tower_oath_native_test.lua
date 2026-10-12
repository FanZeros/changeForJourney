-- 实际Spine绑定专项及正式三选一受控样片。默认实际native/PNG测试，-oath-visual仅正式Panel样片。
-- source Runtime不依赖dist；主统一build后再核载荷。所有mock-free代理只计数/改缺失Load参数，不替共享全局。
-- Linux真实像素：-graphicssurfaceless，Mesa环境变量；-oath-time=0.16/0.55/1.6/2.6冻结真实墙钟。
-- 样片配合-validate/-screenshot由Runtime退出；默认native在末帧清理后engine:Exit。
local TAG="[tower_oath_native_test]"
local counts={checks=0,failed=0,loads=0,renders=0,images=0,patterns=0,unloads=0,deletes=0}
local original={create=nvgSpineCreate,render=nvgSpineRender,image=nvgCreateImage,delete=nvgDeleteImage,
    random=math.random,seed=math.randomseed}
local source=""
local fixtures={}
local visual=false
local sampleTime=.55
local visualFrames=0
local elapsedBase=0
local stage=0
local finished=false
---@type NVGContextWrapper?
local vg=nil
---@type NVGContextWrapper?
local secondVG=nil
---@type table
local panel={}
---@type table
local surface={}
---@type table
local tower={}
local qualityNames={"blade","tome","shield"}
local tokens={{},{},{}}
local function check(ok,label)
    counts.checks=counts.checks+1
    if not ok then counts.failed=counts.failed+1 end
    print(TAG..(ok and " PASS " or " FAIL ")..label)
end
local function eq(a,b,label) check(a==b,label.." actual="..tostring(a).." expected="..tostring(b)) end
local function near(a,b,label,epsilon) check(type(a)=="number" and math.abs(a-b)<=(epsilon or .002),label.." actual="..tostring(a).." expected="..tostring(b)) end
local function read(path)
    local f=assert(cache:GetFile(path),"缺项目资源："..path)
    local rows={};while not f:IsEof() do rows[#rows+1]=f:ReadLine() end
    f:Dispose(); return table.concat(rows,"\n")
end
local function fixture(options)
    local opts=options or {}
    local env={}
    for k,v in pairs(_G) do env[k]=v end
    local mathEnv={} ---@type table<string, any>
    for k,v in pairs(math) do mathEnv[k]=v end
    mathEnv.random=function() error("animation consumed RNG",0) end; mathEnv.randomseed=mathEnv.random
    env.math=mathEnv;env._G=env
    local stat={loads=0,renders=0,images=0,patterns=0,unloads=0,deletes={},objects={},updates={},world=0,animations={},logs={}}
    env.print=function(msg) stat.logs[#stat.logs+1]=tostring(msg) end
    env.nvgCreateImage=function(ctx,path,flags)
        local image=original.image(ctx,path,flags)
        stat.images=stat.images+1;counts.images=counts.images+1
        check(image>0,"actual PNG decode "..path)
        return image
    end
    env.nvgDeleteImage=function(ctx,image)
        stat.deletes[#stat.deletes+1]={ctx,image};counts.deletes=counts.deletes+1
        return original.delete(ctx,image)
    end
    local pattern,tinted=nvgImagePattern,nvgImagePatternTinted
    env.nvgImagePattern=function(...) stat.patterns=stat.patterns+1;counts.patterns=counts.patterns+1;return pattern(...) end
    env.nvgImagePatternTinted=function(...) stat.patterns=stat.patterns+1;counts.patterns=counts.patterns+1;return tinted(...) end
    if opts.png then env.nvgSpineCreate=nil;env.nvgSpineRender=nil
    else
        env.nvgSpineCreate=function(ctx)
            local native=assert(original.create(ctx),"actual Spine create nil")
            local proxy={native=native}
            for _,name in ipairs({"SetScale","SetPosition","SetColor","SetSpeed","SetTimeScale","SetDefaultMix","SetMix","SetPremultipliedAlpha"}) do
                local method=native[name] --[[@as function]]
                if type(method)=="function" then proxy[name]=function(_,...) return method(native,...) end end
            end
            function proxy:Load(path)
                stat.loads=stat.loads+1
                local requested=opts.missing and "image/通天塔暗契/__intentionally_missing__.json" or path
                local result=native:Load(requested)
                if opts.missing then eq(result,false,"actual missing native Load returns false");eq(native:IsLoaded(),false,"failed native unloaded")
                else
                    check(result==true and native:IsLoaded(),"actual native Load/IsLoaded")
                    if result then counts.loads=counts.loads+1 end
                end
                return result
            end
            function proxy:SetAnimation(index,name,loop)
                stat.animations[#stat.animations+1]={index,name,loop}
                local ok=native:SetAnimation(index,name,loop)
                check(ok,"actual SetAnimation "..name);return ok
            end
            function proxy:Update(dt) stat.updates[#stat.updates+1]=dt; native:Update(dt) end
            function proxy:UpdateWorldTransform() stat.world=stat.world+1;native:UpdateWorldTransform() end
            function proxy:Unload() stat.unloads=stat.unloads+1;counts.unloads=counts.unloads+1; native:Unload() end
            stat.objects[#stat.objects+1]=proxy;return proxy
        end
        env.nvgSpineRender=function(ctx,proxy)
            original.render(ctx,proxy.native);stat.renders=stat.renders+1;counts.renders=counts.renders+1
        end
    end
    local effect=assert(load(source,"@actual-native/TowerOathEffect.lua","t",env))()
    local f={effect=effect,stat=stat,tokens={}}
    fixtures[#fixtures+1]=f;return f
end
local function background(ctx,w,h)
    nvgBeginPath(ctx);nvgRect(ctx,0,0,w,h);nvgFillColor(ctx,nvgRGBA(11,12,16,255));nvgFill(ctx)
end
local healthy,pngFixture,failedFixture={},{},{}
local function defaultFrame(ctx)
    stage=stage+1
    if stage==1 then
        healthy=fixture();healthy.effect.preload(ctx)
        for i,t in ipairs({.35,.8,1.9}) do
            local token=tokens[i];healthy.tokens[i]=token
            eq(healthy.effect.draw(ctx,140+i*190,210,180,t,token),"native","healthy production native backend "..i)
            local native=healthy.stat.objects[i].native
            near(native:GetAnimationDuration(0),t<.8 and .8 or 3,"actual animation duration "..i)
            near(native:GetTrackTime(0),t<.8 and t or t-.8,"actual sampled track "..i)
            local bone=assert(native:FindBone("wheel"),"actual wheel bone")
            near(bone:GetWorldX(),140+i*190,"actual world center X")
            near(bone:GetWorldY(),210,"actual world center Y")
            healthy.effect.drawIcon(ctx,qualityNames[i],140+i*190,210,100,1)
        end
        eq(healthy.stat.loads,3,"one native load per card")
        eq(healthy.stat.images,10,"one context ten static images")
        eq(healthy.stat.patterns,3,"healthy draw only icons use PNG")
    elseif stage==2 then
        -- 第二个已完成真实渲染帧后，在同elapsed改变所有参数，检查实际骨骼而非代理数值。
        local before=#healthy.stat.updates
        eq(healthy.effect.draw(ctx,335,225,120,.35,tokens[1]),"native","sameelapsed actual resize backend")
        local native=healthy.stat.objects[1].native
        local bone=assert(native:FindBone("wheel"))
        near(native:GetTrackTime(0),.35,"actual resize track unchanged")
        near(bone:GetWorldX(),335,"actual resize world X");near(bone:GetWorldY(),225,"actual resize world Y")
        near(math.abs(bone:GetWorldScaleX()),.5,"actual world X scale after resize")
        near(math.abs(bone:GetWorldScaleY()),.5,"actual world Y scale after resize")
        eq(#healthy.stat.updates,before,"resize no positive/zero Update when world API exists")
        eq(healthy.stat.world,1,"actual world transform called once")
        healthy.effect.draw(ctx,335,225,120,.35,tokens[1]);eq(healthy.stat.world,1,"stable sameelapsed no repeat world refresh")
        healthy.effect.draw(ctx,330,230,160,1.75,tokens[1])
        near(native:GetTrackTime(0),.95,"actual awaken->idle remainder1.75")
        healthy.effect.draw(ctx,330,230,160,1.75,tokens[1]);near(native:GetTrackTime(0),.95,"duplicate idle track stable")
        healthy.effect.draw(ctx,330,230,160,4.25,tokens[1]);near(native:GetTrackTime(0),3.45,"actual idle beyond one cycle")
    elseif stage==3 then
        for _,token in ipairs(healthy.tokens) do healthy.effect.release(token);healthy.effect.release(token) end
        eq(healthy.stat.unloads,3,"three actual Unload exactly once after completed frame")
        healthy.effect.destroy();eq(#healthy.stat.deletes,10,"actual PNG deletes before vg destroy")
        pngFixture=fixture({png=true});pngFixture.effect.preload(ctx)
        for i=1,3 do
            eq(pngFixture.effect.draw(ctx,140+i*190,210,180,1.5,{}),"png","forced actual PNG backend "..i)
            eq(pngFixture.effect.drawIcon(ctx,qualityNames[i],140+i*190,210,100,.5),"png","actual static icon "..i)
        end
        eq(pngFixture.stat.images,10,"forced PNG decodes ten once")
        check(pngFixture.stat.patterns>3,"fallback ring/ember really used")
    elseif stage==4 then
        failedFixture=fixture({missing=true});failedFixture.tokens[1]={}
        eq(failedFixture.effect.draw(ctx,360,210,180,.55,failedFixture.tokens[1]),"png","actual missing Load fallback PNG")
        eq(failedFixture.stat.loads,1,"missing real Load attempted once")
        eq(failedFixture.stat.unloads,1,"actual failed instance Unload once")
        eq(#failedFixture.stat.animations,0,"failed actual Load no animation")
        for _=1,5 do failedFixture.effect.draw(ctx,360,210,180,.55,failedFixture.tokens[1]) end
        eq(failedFixture.stat.loads,1,"actual failed Load not retried")
        eq(failedFixture.stat.renders,0,"missing path not native success")
    elseif stage==5 then
        pngFixture.effect.destroy();failedFixture.effect.destroy()
        eq(#pngFixture.stat.deletes,10,"PNG fallback handles deleted")
        eq(#failedFixture.stat.deletes,10,"failed Load fallback handles deleted")
        check(counts.loads==3 and counts.renders>5,"actual healthy loads/renders completed")
        finished=true
    end
end
local function choices()
    local ids={1,2,15};local result={}
    for i,id in ipairs(ids) do
        local sourceBuff=tower.BUFFS[id]; assert(sourceBuff,"actual configured buff absent")
        local choice={};for k,v in pairs(sourceBuff) do choice[k]=v end
        choice.quality=i;result[i]=choice
    end
    return result
end
local function visualFrame(ctx,w,h)
    local actualElapsed=time.elapsedTime or 0
    time.elapsedTime=elapsedBase+sampleTime
    local ok,err=pcall(function() panel.draw(ctx,w,h) end)
    time.elapsedTime=actualElapsed
    if not ok then error(err,0) end
    visualFrames=visualFrames+1
    if visualFrames==1 then print(TAG.." VISUAL official TowerBuffPick draw frozenElapsed="..sampleTime.." three actual configured choices") end
end
function Start()
    local ok,err=pcall(function()
        for _,arg in ipairs(GetArguments()) do
            if arg=="-oath-visual" then visual=true end
            local t=arg:match("^-oath%-time=(.+)$");if t then sampleTime=assert(tonumber(t)) end
        end
        source=read("ui/tower/TowerOathEffect.lua")
        vg=assert(nvgCreate(1),"actual NanoVG context")
        if visual then
            panel=require("ui.tower.TowerBuffPick");surface=require("ui.widget.DesignWidgetSurface")
            tower=require("config.TowerConfig")
            surface.init() -- UI/NVG render-order初始化只能在Start，不在第一次Panel.draw事件中懒创建。
            assert(nvgCreateFont(vg,"sans","Fonts/NotoSansCJKkr-Bold.otf")>=0,"实际宿主sans字体加载失败")
            nvgFontFace(vg,"sans")
            panel.init(vg);elapsedBase=time.elapsedTime or 0
            panel.open(17,choices(),nil,{runId=7,selectionId=11,floor=17,wave=4})
        end
        SubscribeToEvent(vg,"NanoVGRender","HandleTowerOathNative")
    end)
    if not ok then check(false,"Start "..tostring(err));engine:Exit() end
end
function HandleTowerOathNative()
    if finished then return end
    local ctx=vg;if not ctx then return end
    local begun=false
    local ok,err=pcall(function()
        -- 模式B系统逻辑分辨率，正式Panel自身按1920x1080设计fit；不重复DPR缩放。
        local dpr=graphics:GetDPR();local w,h=graphics:GetWidth()/dpr,graphics:GetHeight()/dpr
        nvgBeginFrame(ctx,w,h,dpr);begun=true;background(ctx,w,h)
        if visual then visualFrame(ctx,w,h) else defaultFrame(ctx) end
    end)
    if begun then local closed,endErr=pcall(nvgEndFrame,ctx);if not closed then check(false,"EndFrame "..tostring(endErr)) end end
    if not ok then check(false,"native frame "..tostring(err));finished=true end
    if finished then
        print(string.format("%s %s checks=%d failed=%d actualLoads=%d actualRenders=%d actualImages=%d actualTexturePatterns=%d Unload=%d deletes=%d",
            TAG,counts.failed==0 and "ALL PASS" or "FAILED",counts.checks,counts.failed,counts.loads,counts.renders,counts.images,counts.patterns,counts.unloads,counts.deletes))
        engine:Exit()
    end
end
function Stop()
    if visual then
        local ok,err=pcall(function() panel.destroy();surface.shutdown() end)
        if not ok then print(TAG.." STOP FAILED "..tostring(err)) end
        print(TAG.." VISUAL frames="..visualFrames.." frozenElapsed="..sampleTime)
    end
    for _,f in ipairs(fixtures) do pcall(f.effect.destroy) end
    if vg then nvgDelete(vg);vg=nil;print(TAG.." actual nvgDelete after Unload+PNG release") end
    if secondVG then nvgDelete(secondVG);secondVG=nil end
    check(nvgSpineCreate==original.create and nvgSpineRender==original.render and math.random==original.random and math.randomseed==original.seed,"shared native/RNG globals untouched")
end
