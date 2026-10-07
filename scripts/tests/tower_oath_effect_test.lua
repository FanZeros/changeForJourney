-- 独立生产源mock生命周期专项，不替换共享nvg/math、不加载main或玩家档。
-- CPU mock证明契约，不证明真实native/GPU；native入口由主统一build后再扩展/执行。
local TAG="[tower_oath_effect_test]"
local counts={cases=0,checks=0,failed=0}
local source=""
local fixtures={}
local function check(ok,label)
    counts.checks=counts.checks+1
    if not ok then counts.failed=counts.failed+1 end
    print(TAG..(ok and " PASS " or " FAIL ")..label)
end
local function eq(a,b,label) check(a==b,label.." actual="..tostring(a).." expected="..tostring(b)) end
local function near(a,b,label) check(type(a)=="number" and math.abs(a-b)<.000001,label.." actual="..tostring(a).." expected="..tostring(b)) end
local function case(name,fn)
    counts.cases=counts.cases+1
    local ok,err=pcall(fn)
    if not ok then check(false,name.." HARNESS "..tostring(err)) end
end
local function private(options)
    local opts=options or {}
    local stat={creates=0,loads=0,animations={},updates={},renders=0,unloads=0,dispose=0,
        images=0,deletes={},patterns=0,colors={},depth=0,saves=0,restores=0,world=0,geometry={},logs={},instances={},events={}}
    local mathEnv={} ---@type table<string, any>
    for k,v in pairs(math) do mathEnv[k]=v end
    mathEnv.random=function() error("RNG forbidden",0) end; mathEnv.randomseed=mathEnv.random
    local env={math=mathEnv,string=string,table=table,type=type,assert=assert,error=error,pcall=pcall,
        pairs=pairs,ipairs=ipairs,setmetatable=setmetatable,tostring=tostring,select=select}
    env._G=env
    env.require=function() error("unexpected dependency",0) end
    env.print=function(...) stat.logs[#stat.logs+1]=tostring(select(1,...)) end
    env.nvgSave=function() stat.saves=stat.saves+1; if opts.save then error("SAVE",0) end; stat.depth=stat.depth+1 end
    env.nvgRestore=function() stat.restores=stat.restores+1; if opts.restore then error("RESTORE",0) end; stat.depth=stat.depth-1 end
    env.nvgTranslate=function() end; env.nvgScale=function() end
    env.nvgBeginPath=function() end; env.nvgClosePath=function() end
    local function point(_,x,y) stat.geometry[#stat.geometry+1]={x,y} end
    env.nvgMoveTo=point; env.nvgLineTo=point
    env.nvgFillColor=function() end; env.nvgFill=function() end
    env.nvgRGBA=function(r,g,b,a) stat.colors[#stat.colors+1]={r,g,b,a}; return {r,g,b,a} end
    env.nvgFillPaint=function() end
    env.nvgCreateImage=function(vg,path)
        stat.images=stat.images+1
        if opts.imageFail or (opts.missing and path:find(opts.missing,1,true)) then return 0 end
        return stat.images
    end
    env.nvgDeleteImage=function(vg,id) stat.deletes[#stat.deletes+1]={vg,id} end
    env.nvgImagePatternTinted=function()
        stat.patterns=stat.patterns+1
        if opts.pattern then error("PATTERN",0) end
        return {}
    end
    env.nvgImagePattern=env.nvgImagePatternTinted
    for _,name in ipairs({"nvgGlobalAlpha","nvgScissor","nvgResetScissor","nvgResetTransform","nvgCreate","nvgBeginFrame"}) do
        env[name]=function() error("host state/renderer forbidden: "..name,0) end
    end
    if not opts.noNative then
        env.nvgSpineCreate=function(vg)
            stat.creates=stat.creates+1
            if opts.create then error("CREATE",0) end
            if opts.createNil then return nil end
            local instance={vg=vg,track=0,animation=""}
            function instance:Load(path)
                stat.loads=stat.loads+1; self.path=path
                if opts.loadThrow then error("LOAD",0) end
                return not opts.loadFalse
            end
            function instance:SetAnimation(index,name,loop)
                stat.animations[#stat.animations+1]={index,name,loop}; self.track=0; self.animation=name
                if opts.animation==name then return false end
                return true
            end
            function instance:SetScale(x,y) self.sx,self.sy=x,y;stat.events[#stat.events+1]="scale" end
            function instance:SetPosition(x,y) self.x,self.y=x,y;stat.events[#stat.events+1]="position" end
            function instance:SetColor(_,_,_,a) self.alpha=a;stat.events[#stat.events+1]="color" end
            function instance:Update(dt)
                stat.updates[#stat.updates+1]={dt,self.animation,self.sx,self.sy,self.x,self.y}
                stat.events[#stat.events+1]="update"
                self.track=self.track+dt
                if opts.update then error("UPDATE",0) end
                if opts.onUpdate then opts.onUpdate() end
            end
            function instance:UpdateWorldTransform() stat.world=stat.world+1 end
            function instance:SetDefaultMix(x) self.defaultMix=x end
            function instance:SetMix(a,b,x) self.mix={a,b,x} end
            function instance:SetSpeed(x) self.speed=x end
            function instance:SetTimeScale(x) self.timeScale=x end
            function instance:SetPremultipliedAlpha(x) self.pma=x end
            function instance:Unload() stat.unloads=stat.unloads+1; if opts.onUnload then opts.onUnload() end end
            function instance:Dispose() stat.dispose=stat.dispose+1 end
            if opts.noWorld then instance.UpdateWorldTransform=nil end
            if opts.missingMethod then instance[opts.missingMethod]=nil end
            stat.instances[#stat.instances+1]=instance
            return instance
        end
        env.nvgSpineRender=function()
            stat.renders=stat.renders+1
            if opts.render then error("RENDER",0) end
        end
    end
    local module=assert(load(source,"@private/TowerOathEffect.lua","t",env))()
    local f={effect=module,stat=stat,env=env,vg={},opts=opts}
    fixtures[#fixtures+1]=f
    return f
end
local function draw(f,elapsed,token,quality,size) return f.effect.draw(f.vg,300,250,size or 240,elapsed,token,quality) end
local function tests()
    case("single-instance-time-sampling",function()
        local f=private(); local t={}
        f.effect.preload(f.vg); f.effect.preload(f.vg);eq(f.stat.images,10,"preload exactly10 once")
        eq(draw(f,.25,t),"native","healthy native backend")
        local obj=f.stat.instances[1]
        eq(f.stat.creates,1,"one create");eq(f.stat.loads,1,"one load")
        eq(obj.path,"image/通天塔暗契/tower_oath.json","independent JSON path")
        eq(f.stat.animations[1][1],0,"track0");eq(f.stat.animations[1][2],"awaken","awaken first")
        eq(f.stat.animations[1][3],false,"awaken nonloop");near(obj.track,.25,"actual elapsed not fixed dt")
        eq(obj.pma,false,"straight alpha");eq(obj.speed,1,"speed1");eq(obj.timeScale,1,"real clock1")
        eq(obj.defaultMix,0,"no hidden mix duration")
        draw(f,.25,t);eq(#f.stat.updates,1,"same timestamp not updated twice")
        draw(f,1.4,t);eq(#f.stat.animations,2,"idle selected once")
        eq(f.stat.animations[2][2],"idle","idle name");eq(f.stat.animations[2][3],true,"idle loop")
        near(f.stat.updates[2][1],.55,"awaken consumed to .8");near(f.stat.updates[3][1],.6,"idle consumes remainder")
        near(obj.track,.6,"idle actual track")
        draw(f,1.4,t);eq(#f.stat.updates,3,"idle duplicate no update")
        draw(f,1.2,t);eq(#f.stat.updates,3,"old elapsed no rewind")
        draw(f,4.8,t);near(obj.track,4,"long idle elapsed exact")
        eq(#f.stat.animations,2,"idle no repeated SetAnimation")
        eq(f.stat.patterns,0,"native never silently PNG")
        for i,e in ipairs(f.stat.events) do if e=="update" then
            eq(f.stat.events[i-3],"scale","scale before Update")
            eq(f.stat.events[i-2],"position","position before Update")
            eq(f.stat.events[i-1],"color","color before Update")
        end end
        f.effect.release(t);f.effect.release(t);eq(f.stat.unloads,1,"Unload once");eq(f.stat.dispose,0,"never Dispose chain")
        eq(draw(f,5,t),"released","retired cannot revive")
        f.effect.destroy();f.effect.destroy();eq(#f.stat.deletes,10,"destroy PNG once")
        eq(f.stat.depth,0,"balanced state")
    end)
    case("late-first-frame-and-exact-boundary",function()
        for _,time in ipairs({0,.8,1.9,23.1}) do
            local f=private();local token={};draw(f,time,token)
            local obj=f.stat.instances[1]
            if time==0 then near(obj.track,0,"initial pose Update0");eq(#f.stat.updates,1,"initial zero sample once")
            else
                eq(#f.stat.animations,2,"late first still awaken+idle")
                near(f.stat.updates[1][1],.8,"late first samples awaken end")
                near(obj.track,time-.8,"late first idle real remainder")
            end
        end
    end)
    case("same-time-resize-and-new-token-isolation",function()
        for _,noWorld in ipairs({false,true}) do
            local f=private({noWorld=noWorld});local t={};draw(f,1.5,t)
            local obj=f.stat.instances[1];local n=#f.stat.updates;local old=obj.track
            draw(f,1.5,t,nil,120);near(obj.sx,.5,"resize x");near(obj.sy,-.5,"resize y flip")
            near(obj.track,old,"resize no time advance")
            if noWorld then eq(#f.stat.updates,n+1,"resize Update0 compatibility");eq(f.stat.updates[#f.stat.updates][1],0,"zero delta")
            else eq(f.stat.world,1,"resize world refresh") end
            local updates=#f.stat.updates;draw(f,1.5,t,nil,120);eq(#f.stat.updates,updates,"unchanged no world/update")
            local other={};draw(f,.1,other);eq(f.stat.creates,2,"two cards two instances")
            near(f.stat.instances[2].track,.1,"second card not shared track")
        end
    end)
    case("native-failure-matrix-no-retry",function()
        local faults={{noNative=true},{create=true},{createNil=true},{loadFalse=true},{loadThrow=true},
            {animation="awaken"},{animation="idle"},{update=true},{render=true},{missingMethod="Update"},{missingMethod="Unload"}}
        for i,opts in ipairs(faults) do
            local f=private(opts);local t={};eq(draw(f,1.1,t),"png","fault PNG "..i)
            local creates,loads,animations,unloads,logs=f.stat.creates,f.stat.loads,#f.stat.animations,f.stat.unloads,#f.stat.logs
            for j=1,8 do eq(draw(f,1.1+j*.1,t),"png","fault remains PNG "..i.."/"..j) end
            eq(f.stat.creates,creates,"no create retry "..i);eq(f.stat.loads,loads,"no load retry "..i)
            eq(#f.stat.animations,animations,"no animation retry "..i);eq(f.stat.unloads,unloads,"no unload retry "..i)
            eq(#f.stat.logs,logs,"no log spam "..i);eq(f.stat.dispose,0,"no Dispose "..i)
            eq(f.stat.depth,0,"fault restores state "..i)
        end
    end)
    case("PNG-and-geometry-failure-latching",function()
        for _,opts in ipairs({{noNative=true,imageFail=true},{noNative=true,missing="seal_ring"},{noNative=true,pattern=true}}) do
            local f=private(opts);local t={};eq(draw(f,.6,t),"vector","PNG failed to vector")
            local images,patterns,logs=f.stat.images,f.stat.patterns,#f.stat.logs
            for _=1,8 do draw(f,.7,t) end
            eq(f.stat.images,images,"failed images no reload");eq(f.stat.patterns,patterns,"pattern fault no retry")
            eq(#f.stat.logs,logs,"PNG fault logs once");eq(f.stat.depth,0,"vector restored")
        end
    end)
    case("context-release-and-tokenless",function()
        local f=private({noNative=true});local other={}
        f.effect.preload(f.vg);f.effect.preload(other);eq(f.stat.images,20,"contexts own 10 handles each")
        for _=1,20 do eq(draw(f,2,nil),"png","tokenless PNG") end
        eq(f.stat.creates,0,"tokenless never creates native")
        f.effect.destroy();eq(#f.stat.deletes,20,"deletes two context caches")
        local owned={};for _,e in ipairs(f.stat.deletes) do owned[e[1]]=(owned[e[1]] or 0)+1 end
        eq(owned[f.vg],10,"first ownership");eq(owned[other],10,"second ownership")
        local g=private();local t={};draw(g,.1,t)
        eq(g.effect.draw({},0,0,240,.2,t),"released","cross context retires token")
        eq(g.stat.creates,1,"cross context no reload");eq(g.stat.unloads,1,"cross context Unload")
    end)
    case("icon-seven-corresponding-fallbacks",function()
        local signatures={}
        for _,theme in ipairs({"blade","tome","blood","eye","shield","chain","bell"}) do
            local f=private({missing=theme})
            eq(f.effect.drawIcon(f.vg,theme,100,100,80,.5),"vector","missing icon geometry "..theme)
            eq(f.stat.creates,0,"icon native0");eq(f.stat.depth,0,"icon state balanced")
            local points={};for _,p in ipairs(f.stat.geometry) do points[#points+1]=string.format("%.3f,%.3f",p[1],p[2]) end
            signatures[theme]=table.concat(points,";")
        end
        local names={"blade","tome","blood","eye","shield","chain","bell"}
        for i=1,#names do for j=i+1,#names do check(signatures[names[i]]~=signatures[names[j]],"geometry differs "..names[i].."/"..names[j]) end end
        local f=private();eq(f.effect.drawIcon(f.vg,"blade",0,0,192,.5),"png","healthy icon PNG")
        eq(f.stat.colors[1][4],128,"icon alpha tint")
        local n=f.stat.images;f.effect.drawIcon(f.vg,"tome",0,0,192,1);eq(f.stat.images,n,"icons share cache")
    end)
    case("force-png-toggle-preserves-real-clock",function()
        local f=private();local t={}
        eq(draw(f,.5,t,"png"),"png","force PNG before native")
        eq(draw(f,1.2,t),"native","native after PNG")
        near(f.stat.instances[1].track,.4,"native late start consumes exact idle remainder")
        draw(f,2.7,t,"png");draw(f,2.8,t)
        near(f.stat.instances[1].track,2,"PNG period not removed from actual clock")
        eq(f.stat.creates,1,"quality toggle no recreate")
    end)
    case("reentrant-release-destroy-and-unknown-state",function()
        local opts={};local f=private(opts);local t={}
        opts.onUpdate=function() f.effect.release(t) end
        eq(draw(f,1,t),"released","Update release avoids fallback")
        eq(f.stat.renders,0,"released during update no render");eq(f.stat.unloads,1,"reentrant unload once")
        local g=private();local token={};draw(g,.2,token)
        local nested={};g.opts.onUnload=function() eq(draw(g,.3,nested),"released","destroy reentry prevented") end
        g.effect.destroy();eq(g.stat.creates,1,"destroy cannot create new native")
        for _,opt in ipairs({{save=true},{restore=true},{noNative=true,save=true},{noNative=true,restore=true}}) do
            local bad=private(opt);check(not pcall(draw,bad,.5,{}),"unknown Save/Restore errors propagate")
            if opt.save then eq(bad.stat.restores,0,"failed Save no blind Restore") end
        end
    end)
    case("invalid-input-no-native-or-state",function()
        local f=private();local token={}
        for _,v in ipairs({-1,0/0,math.huge}) do eq(draw(f,v,token),"none","invalid elapsed") end
        eq(draw(f,1,token,nil,0),"none","zero size")
        eq(f.effect.draw(f.vg,0/0,0,240,1,token),"none","nan center")
        eq(f.effect.drawIcon(f.vg,"unknown",0,0,100,1),"none","unknown icon")
        eq(f.effect.drawIcon(f.vg,"blade",0,0,100,0),"none","zero icon alpha")
        eq(f.stat.creates,0,"invalid native0");eq(f.stat.images,0,"invalid PNG0");eq(f.stat.saves,0,"invalid state0")
    end)
end
function Start()
    local ok,err=pcall(function()
        local f=assert(cache:GetFile("ui/tower/TowerOathEffect.lua"),"production resource absent")
        local lines={};while not f:IsEof() do lines[#lines+1]=f:ReadLine() end
        f:Dispose();source=table.concat(lines,"\n")
        tests()
    end)
    if not ok then check(false,"Start "..tostring(err)) end
    for _,f in ipairs(fixtures) do pcall(f.effect.destroy) end
    print(string.format("%s %s cases=%d checks=%d failed=%d MODE=mock-production-source native/GPU=pending",TAG,
        counts.failed==0 and "ALL PASS" or "FAILED",counts.cases,counts.checks,counts.failed))
    engine:Exit()
end
