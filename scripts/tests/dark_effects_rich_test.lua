-- Rich dark FX regression: actual production/dependency sources in private environments.
-- Controlled native faults are NOT native/GPU proof. Native and PNG render checks run separately
-- in actual NanoVGRender frames; they fail when fallback is used, never count fallback as rich success.
-- No main, player saves, shared global replacement, build, or runtime log writes.
-- Native/PNG: EGL_PLATFORM=surfaceless LIBGL_ALWAYS_SOFTWARE=1 SDL_AUDIODRIVER=dummy
-- UrhoXRuntime tests/dark_effects_rich_test.lua -tapcode_dir=/workspace -tool_mode (no -graphicsheadless)
-- Mock/resources only: append -graphicsheadless -dark-rich-logic-only.
-- Optional -dark-rich-native-only / -dark-rich-png-only report actual backends separately.
-- -dark-rich-failed-load-only injects one missing project resource into real native Load:
-- its expected resource error is separate from healthy native rendering and main startup.
local TAG = "[dark_effects_rich_test]"
local ROOT = "image/暗黑特效/"
local totals = {cases=0,checks=0,failures=0,nativeLoads=0,nativeRenders=0,textureFills=0}
local sources, keep, contexts = {}, {}, {}
local ended, logicOnly, nativeOnly, pngOnly, failedLoadOnly = false,false,false,false,false
local REGIONS = {
    seal_plate={192,192},gate_leaf={96,320},rift_light={80,320},smoke_flame={192,256},
    soul_flame={128,192},seal_shard={64,96},rune_ring={256,256},ember={32,64},
    copper_wing={256,96},nameplate={640,144},impact_glow={256,256},rune_strip={128,256},
    ash_flake={64,64},light_sweep={256,64},
}
local KINDS = {"level","job","revive","success","failure","power"}
local DURATIONS = {level=1.3333,job=1.3333,revive=.9,success=1.6667,failure=1.3333,power=3.2}
local original = {create=nvgCreateImage,delete=nvgDeleteImage,spine=nvgSpineCreate,
    render=nvgSpineRender,random=math.random,seed=math.randomseed,require=require}
local function check(ok,label)
    totals.checks=totals.checks+1
    if not ok then totals.failures=totals.failures+1 end
    print(TAG..(ok and " PASS " or " FAIL ")..label)
end
local function eq(a,b,label) check(a==b,label.." actual="..tostring(a).." expected="..tostring(b)) end
local function near(a,b,label,epsilon)
    check(type(a)=="number" and math.abs(a-b)<=(epsilon or .00001),label.." actual="..tostring(a).." expected="..tostring(b))
end
local function case(label,fn)
    totals.cases=totals.cases+1
    local ok,err=pcall(fn)
    if not ok then check(false,label.." HARNESS "..tostring(err)) end
    print(TAG.." CASE "..label.." failures="..totals.failures)
end
local function read(path)
    local f=assert(cache:GetFile(path),"missing resource "..path)
    local lines={};while not f:IsEof() do lines[#lines+1]=f:ReadLine() end
    f:Dispose()
    return table.concat(lines,"\n")
end
local function privateEnv(logs)
    local mathEnv={} ---@type table<string, any>
    for k,v in pairs(math) do mathEnv[k]=v end
    local env={assert=assert,error=error,ipairs=ipairs,pairs=pairs,next=next,type=type,
        tostring=tostring,tonumber=tonumber,select=select,pcall=pcall,xpcall=xpcall,
        setmetatable=setmetatable,getmetatable=getmetatable,rawget=rawget,rawset=rawset,
        string=string,table=table,math=mathEnv,time={elapsedTime=100}}
    env.math.random=function() error("rich FX consumed combat RNG",0) end
    env.math.randomseed=env.math.random
    env.print=function(...) local p={};for i=1,select("#",...) do p[i]=tostring(select(i,...)) end
        logs[#logs+1]=table.concat(p," ") end
    env._G=env
    for k,v in pairs(_G) do if type(k)=="string" and k:match("^NVG_") then env[k]=v end end
    return env
end
-- Palette dependency is actual DarkIcon, and its actual DrawUtil/BattleLayout dependency chain.
-- Lazy unrelated DarkIcon image helpers are not executed. Unexpected imports are errors.
local function loadRich(env,stats)
    local modules={}
    local allowed={ ["ui.fx.DarkEffectSprites"]=true,["ui.fx.DarkEffectPrimitives"]=true,
        ["core.DarkIcon"]=true,["core.DrawUtil"]=true,["core.BattleLayout"]=true }
    env.require=function(name)
        assert(allowed[name],"unexpected rich dependency "..name)
        if modules[name] then return modules[name] end
        local path=name:gsub("%.","/")..".lua"
        sources[path]=sources[path] or read(path)
        local mod=assert(load(sources[path],"@rich-real/"..path,"t",env))()
        if name=="ui.fx.DarkEffectPrimitives" then
            local actualPrimitives=mod
            local facade={}
            for _,key in ipairs({"drawCard","drawResult","drawPower"}) do
                facade[key]=function(...) stats.fallback=stats.fallback+1;return actualPrimitives[key](...) end
            end
            mod=facade
        end
        modules[name]=mod
        return mod
    end
    return env.require("ui.fx.DarkEffectSprites")
end
local function draw(f,kind,p,alpha,token,vg)
    local ctx=vg or f.vg
    local elapsed=(p or .5)*DURATIONS[kind]
    if kind=="power" then return f.rich.drawPower(ctx,380,180,760,360,elapsed,DURATIONS[kind],alpha or 1,token)
    elseif kind=="success" or kind=="failure" then
        return f.rich.drawResult(ctx,kind=="success",300,240,200,elapsed,DURATIONS[kind],alpha or 1,token)
    else return f.rich.drawCard(ctx,kind,300,240,200,350,elapsed,DURATIONS[kind],alpha or 1,token) end
end
local function controlled(options)
    local opts=options or {}
    local stats={fallback=0,creates=0,loads=0,animations=0,renders=0,updates={},unloads=0,disposes=0,
        images=0,deletes={},patterns=0,fills=0,depth=0,stack={},geometry={},invalid=0,instances={},
        transforms={},colors={},logs={},saveCalls=0,restoreCalls=0,imageNames={},platePaths={},worldRefreshes=0,
        patternIds={},slotLookups={},slotColors={},slotResets=0,renderSlots={}}
    local env=privateEnv(stats.logs)
    local matrix={a=1,b=0,c=0,d=1,x=0,y=0}
    local function snapshot() return {a=matrix.a,b=matrix.b,c=matrix.c,d=matrix.d,x=matrix.x,y=matrix.y} end
    env.nvgSave=function()
        stats.saveCalls=stats.saveCalls+1
        if opts.saveThrow then error("CONTROLLED_SAVE",0) end
        stats.stack[#stats.stack+1]=snapshot();stats.depth=stats.depth+1
    end
    env.nvgRestore=function()
        stats.restoreCalls=stats.restoreCalls+1
        if opts.restoreThrow then error("CONTROLLED_RESTORE",0) end
        matrix=assert(table.remove(stats.stack),"stack underflow");stats.depth=stats.depth-1
    end
    env.nvgTranslate=function(_,x,y) matrix.x=matrix.x+matrix.a*x+matrix.c*y;matrix.y=matrix.y+matrix.b*x+matrix.d*y end
    env.nvgScale=function(_,x,y) matrix.a=matrix.a*x;matrix.b=matrix.b*x;matrix.c=matrix.c*y;matrix.d=matrix.d*y end
    local function point(_,x,y)
        if x~=x or y~=y or math.abs(x)==math.huge or math.abs(y)==math.huge then stats.invalid=stats.invalid+1 end
        stats.geometry[#stats.geometry+1]={matrix.a*x+matrix.c*y+matrix.x,matrix.b*x+matrix.d*y+matrix.y}
    end
    env.nvgMoveTo=point;env.nvgLineTo=point
    for _,name in ipairs({"nvgBeginPath","nvgClosePath","nvgBezierTo","nvgQuadTo","nvgArc","nvgArcTo",
        "nvgCircle","nvgEllipse","nvgRect","nvgRoundedRect","nvgStroke","nvgStrokeWidth","nvgLineCap",
        "nvgLineJoin","nvgMiterLimit","nvgPathWinding","nvgFillColor","nvgStrokeColor","nvgStrokePaint"}) do env[name]=function() end end
    for _,name in ipairs({"nvgGlobalAlpha","nvgScissor","nvgIntersectScissor","nvgResetScissor","nvgResetTransform"}) do
        env[name]=function() error("rich code altered host state "..name,0) end
    end
    env.nvgFill=function() stats.fills=stats.fills+1 end
    env.nvgRGBA=function(r,g,b,a) stats.colors[#stats.colors+1]={r,g,b,a};return {r,g,b,a} end
    env.nvgRGB=function(r,g,b) return env.nvgRGBA(r,g,b,255) end
    env.nvgRGBAf=function(r,g,b,a) return {r,g,b,a} end
    for _,name in ipairs({"nvgLinearGradient","nvgRadialGradient","nvgBoxGradient"}) do env[name]=function() return {} end end
    env.nvgFillPaint=function(_,paint)
        if type(paint)=="table" and stats.imageNames[paint.image]==ROOT.."nameplate.png" then
            local vertices={}
            for index=#stats.geometry-3,#stats.geometry do vertices[#vertices+1]=stats.geometry[index] end
            stats.platePaths[#stats.platePaths+1]=vertices
        end
    end
    env.nvgCreateImage=function(ctx,path,flags)
        stats.images=stats.images+1
        if opts.imageThrow then error("CONTROLLED_IMAGE_CREATE",0) end
        if opts.imageMissing and path:find(opts.imageMissing,1,true) then return 0 end
        stats.imageNames[stats.images]=path
        return stats.images
    end
    env.nvgDeleteImage=function(ctx,id) stats.deletes[#stats.deletes+1]={ctx,id} end
    env.nvgImagePatternTinted=function(_,x,y,w,h,angle,id,color)
        stats.patterns=stats.patterns+1
        stats.patternIds[#stats.patternIds+1]=id
        if opts.patternThrow then error("CONTROLLED_PATTERN",0) end
        return {image=id,color=color}
    end
    env.nvgImagePattern=env.nvgImagePatternTinted
    if opts.noImageAPI then env.nvgCreateImage=nil end
    if not opts.noNative then
        env.nvgSpineCreate=function(vg)
            stats.creates=stats.creates+1
            if opts.createThrow then error("CONTROLLED_NATIVE_CREATE",0) end
            if opts.createNil then return nil end
            local obj={vg=vg,time=0}
            -- 真实API的槽句柄可缓存；动画Update每次覆盖alpha，测试必须验证渲染前再次屏蔽。
            local slot={name="sweep",color={1,1,1,1}}
            function slot:IsValid() return not opts.slotInvalid end
            function slot:GetName() return self.name end
            function slot:GetColor() return table.unpack(self.color) end
            function slot:SetColor(r,g,b,a)
                stats.slotColors[#stats.slotColors+1]={r,g,b,a}
                if opts.slotColorThrow then error("CONTROLLED_SLOT_COLOR",0) end
                self.color={r,g,b,a}
            end
            obj.sweepSlot=slot
            function obj:FindSlot(name)
                stats.slotLookups[#stats.slotLookups+1]=name
                if opts.findSlotThrow then error("CONTROLLED_FIND_SLOT",0) end
                if name~="sweep" or opts.slotMissing then return nil end
                return self.sweepSlot
            end
            function obj:Load(path) stats.loads=stats.loads+1;self.path=path
                if opts.loadThrow then error("CONTROLLED_LOAD",0) end
                return not opts.loadFalse end
            function obj:SetAnimation(track,name,loop) stats.animations=stats.animations+1;self.animation=name
                eq(track,0,"controlled native track uses public zero-based track API")
                eq(loop,false,"controlled native animation nonlooping")
                if opts.animationThrow then error("CONTROLLED_ANIMATION",0) end
                return not opts.animationFalse end
            function obj:GetAnimationDuration() if opts.durationThrow then error("CONTROLLED_DURATION",0) end
                return opts.duration or DURATIONS[self.animation] end
            function obj:Update(dt) stats.updates[#stats.updates+1]=dt;self.time=self.time+dt
                self.sweepSlot.color={1,1,1,1};stats.slotResets=stats.slotResets+1
                if opts.updateThrow then error("CONTROLLED_UPDATE",0) end
                if opts.onUpdate then opts.onUpdate() end end
            function obj:UpdateWorldTransform() stats.worldRefreshes=stats.worldRefreshes+1 end
            function obj:SetPosition(x,y) self.x,self.y=x,y end
            function obj:SetScale(x,y) self.sx,self.sy=x,y end
            function obj:SetColor(r,g,b,a) self.color={r,g,b,a} end
            function obj:SetSpeed(v) self.speed=v end
            function obj:SetTimeScale(v) self.timeScale=v end
            function obj:SetPremultipliedAlpha(v) self.pma=v end
            function obj:Unload() stats.unloads=stats.unloads+1;if opts.onUnload then opts.onUnload() end end
            function obj:Dispose() stats.disposes=stats.disposes+1 end
            if opts.missingMethod then obj[opts.missingMethod]=nil end
            stats.instances[#stats.instances+1]=obj
            return obj
        end
        env.nvgSpineRender=function(_,obj) stats.renders=stats.renders+1
            stats.renderSlots[#stats.renderSlots+1]={table.unpack(obj.sweepSlot.color)}
            if opts.renderThrow then error("CONTROLLED_RENDER",0) end end
    end
    local f={env=env,stats=stats,vg={},opts=opts}
    f.rich=loadRich(env,stats);keep[#keep+1]=f
    f.matrix=function() return snapshot() end
    return f
end
local function logic()
    case("native-contract-elapsed-and-single-token",function()
        local f=controlled();local token={}
        f.rich.preload(f.vg);f.rich.preload(f.vg)
        eq(f.stats.images,14,"preload 14 PNGs once")
        draw(f,"job",.75,1,token);local instance=f.stats.instances[1]
        eq(f.stats.creates,1,"one native instance per token")
        eq(f.stats.loads,1,"one native JSON Load")
        eq(instance.path,ROOT.."card_fx.json","family path actual public contract")
        eq(instance.animation,"job","animation identity")
        near(instance.time,DURATIONS.job*.75,"first late draw advances full elapsed rather than .016 clamp")
        near(instance.sx,1,"native width uses supplied design box")
        near(instance.sy,-1,"native Y-up flip only no DPR")
        eq(instance.pma,false,"straight alpha Spine mode")
        eq(instance.speed,1,"native speed independent of combat speed")
        eq(instance.timeScale,1,"native clock scale independent of combat scale")
        draw(f,"job",.75,1,token);eq(#f.stats.updates,1,"same-time repeated draw never advances twice")
        draw(f,"job",.8,.5,token);near(instance.time,DURATIONS.job*.8,"next draw consumes only elapsed delta")
        eq(f.stats.fallback,0,"healthy native avoids fallback")
        eq(f.stats.patterns,0,"healthy native does not silently substitute PNG")
        eq(f.stats.depth,0,"native own state restored")
        f.rich.release(token);f.rich.release(token)
        eq(f.stats.unloads,1,"native unload once")
        eq(f.stats.disposes,0,"available Unload must not be followed by unsafe Dispose")
        draw(f,"job",.85,1,token);eq(f.stats.creates,1,"retired token cannot resurrect")
        f.rich.destroy();eq(#f.stats.deletes,14,"destroy releases shared images")
        f.rich.destroy();eq(#f.stats.deletes,14,"destroy idempotent")
    end)
    -- 槽颜色在每次动画更新后都被重置；实际提交时必须只把战力sweep的alpha置零。
    case("power-native-sweep-cached-and-hidden-before-every-render",function()
        local f=controlled();local token={}
        for index,p in ipairs({.2,.3,.45,.65,.9}) do
            draw(f,"power",p,1,token)
            local obj=assert(f.stats.instances[1])
            eq(f.stats.renders,index,"power still uses native each frame "..index)
            eq(f.stats.slotResets,index,"controlled animation really resets slot alpha each Update "..index)
            eq(#f.stats.slotColors,index,"sweep suppression repeated after each reset "..index)
            local color=assert(f.stats.renderSlots[index])
            eq(color[1],1,"sweep keeps red multiplier "..index)
            eq(color[2],1,"sweep keeps green multiplier "..index)
            eq(color[3],1,"sweep keeps blue multiplier "..index)
            eq(color[4],0,"sweep alpha zero at actual native render "..index)
            near(obj.time,p*DURATIONS.power,"sweep suppression cannot change native elapsed "..index)
        end
        eq(#f.stats.slotLookups,1,"FindSlot cached once for independent power playback")
        eq(f.stats.slotLookups[1],"sweep","public named sweep slot used")
        eq(f.stats.creates,1,"sweep suppression reuses same native instance")
        eq(f.stats.patterns,0,"healthy sweep suppression cannot hide PNG substitution")
        eq(f.stats.fallback,0,"healthy sweep suppression cannot hide vector substitution")
        eq(f.stats.depth,0,"sweep suppression restores host state")
        f.rich.release(token)
        eq(f.stats.unloads,1,"cached sweep released with native owner once")
        eq(f.stats.disposes,0,"cached sweep owner still uses single unload API")
    end)
    case("power-native-sweep-same-time-repeat-never-advances",function()
        local f=controlled();local token={};draw(f,"power",.4,1,token)
        local obj=assert(f.stats.instances[1]);local updates=#f.stats.updates
        local elapsed=obj.time
        for index=1,4 do
            -- 同时间外部也可能恢复槽颜色，不能依赖上一帧已透明而省略屏蔽。
            obj.sweepSlot:SetColor(1,1,1,1)
            local colors=#f.stats.slotColors
            draw(f,"power",.4,.5,token)
            eq(#f.stats.slotColors,colors+1,"same-time render reapplies suppression "..index)
            eq(f.stats.renderSlots[#f.stats.renderSlots][4],0,"same-time native submission has invisible sweep "..index)
            eq(#f.stats.updates,updates,"same-time suppression never advances Update "..index)
            near(obj.time,elapsed,"same-time suppression keeps track time "..index)
        end
        eq(#f.stats.slotLookups,1,"same-time render never repeats FindSlot")
        eq(f.stats.renders,5,"same-time duplicate still submits all requested native renders")
        eq(f.stats.patterns,0,"same-time duplicate remains native")
        eq(f.stats.fallback,0,"same-time duplicate never vector substitute")
    end)
    case("power-missing-invalid-slot-single-fallback-other-cards-unchanged",function()
        for index,opts in ipairs({{slotMissing=true},{slotInvalid=true},{missingMethod="FindSlot"},
            {findSlotThrow=true},{slotColorThrow=true}}) do
            local f=controlled(opts);local token={};draw(f,"power",.3,1,token)
            eq(f.stats.renders,0,"unsafe power slot never renders native "..index)
            check(f.stats.patterns>0,"unsafe power slot falls to actual PNG "..index)
            eq(f.stats.fallback,0,"unsafe slot PNG not vector substitute "..index)
            eq(f.stats.unloads,1,"unsafe power slot unloads once "..index)
            eq(f.stats.disposes,0,"unsafe power slot never Dispose after Unload "..index)
            local creates,loads,lookups,colors,logs=f.stats.creates,f.stats.loads,#f.stats.slotLookups,#f.stats.slotColors,#f.stats.logs
            for _=1,4 do draw(f,"power",.4,1,token) end
            eq(f.stats.creates,creates,"unsafe power slot creation failure latched "..index)
            eq(f.stats.loads,loads,"unsafe power slot Load failure latched "..index)
            eq(#f.stats.slotLookups,lookups,"unsafe power slot lookup failure latched "..index)
            eq(#f.stats.slotColors,colors,"unsafe power slot color failure latched "..index)
            eq(#f.stats.logs,logs,"unsafe power slot logs once "..index)
            eq(f.stats.unloads,1,"unsafe power slot repeats do not unload again "..index)
            eq(f.stats.depth,0,"unsafe slot fallback restores host state "..index)
        end
        for _,kind in ipairs({"level","job","revive","success","failure"}) do
            local f=controlled({missingMethod="FindSlot"});local token={}
            draw(f,kind,.3,1,token);draw(f,kind,.6,1,token)
            eq(f.stats.renders,2,"other animation needs no FindSlot "..kind)
            eq(#f.stats.slotLookups,0,"other animation never queries sweep "..kind)
            eq(#f.stats.slotColors,0,"other animation never suppresses sweep "..kind)
            for _,color in ipairs(f.stats.renderSlots) do eq(color[4],1,"other animation retains reset sweep alpha "..kind) end
            eq(f.stats.patterns,0,"other animation native not replaced "..kind)
            eq(f.stats.fallback,0,"other animation never vector substitute "..kind)
        end
    end)
    case("power-PNG-never-samples-light-sweep-and-other-kinds-retain-it",function()
        for _,missing in ipairs({false,"light_sweep"}) do
            for _,plain in ipairs({false,true}) do
                local f=controlled({noNative=true,imageMissing=missing})
                -- 同时覆盖tint和旧ImagePattern入口，预热可包含共享图，战力采样不能用它。
                if plain then f.env.nvgImagePatternTinted=nil end
                local token={}
                for _,p in ipairs({.05,.2,.3,.5,.75,.9}) do draw(f,"power",p,1,token) end
                check(f.stats.patterns>0,"power truly samples PNG layers missing="..tostring(missing).." plain="..tostring(plain))
                local sweepSamples=0
                for _,id in ipairs(f.stats.patternIds) do
                    if f.stats.imageNames[id]==ROOT.."light_sweep.png" then sweepSamples=sweepSamples+1 end
                end
                eq(sweepSamples,0,"power never samples shared light_sweep PNG")
                eq(f.stats.fallback,0,"missing unrelated light_sweep never blocks power PNG readiness")
                eq(f.stats.images,14,"shared fourteen-image preload contract unchanged")
                eq(f.stats.depth,0,"power PNG sweep removal leaves state balanced")
            end
        end
        for _,entry in ipairs({{"level",.3},{"job",.4},{"success",.45},{"failure",.25}}) do
            local f=controlled({noNative=true});draw(f,entry[1],entry[2],1,{})
            local sweepSamples=0
            for _,id in ipairs(f.stats.patternIds) do
                if f.stats.imageNames[id]==ROOT.."light_sweep.png" then sweepSamples=sweepSamples+1 end
            end
            check(sweepSamples>0,"other PNG animation retains original light_sweep "..entry[1])
            eq(f.stats.fallback,0,"other PNG sweep still truly rendered "..entry[1])
        end
    end)
    case("power-program-accents-stay-outside-central-text-other-card-retains-shard",function()
        local f=controlled();draw(f,"power",.3,1,{})
        check(#f.stats.geometry>0,"native power really draws side accent particles")
        for index,point in ipairs(f.stats.geometry) do
            check(math.abs(point[1]-380)>280,"power accent never crosses central number area point "..index)
        end
        eq(f.stats.patterns,0,"power accent geometry is native overlay not PNG")
        eq(f.stats.fallback,0,"power accent geometry is not vector substitute")
        local card=controlled();draw(card,"level",.3,1,{})
        local centerPoints=0
        for _,point in ipairs(card.stats.geometry) do
            if math.abs(point[1]-300)>50 and math.abs(point[1]-300)<90 then centerPoints=centerPoints+1 end
        end
        check(centerPoints>0,"other card retains original middle impact light shard")
        eq(card.stats.patterns,0,"other card shard remains native overlay not PNG")
    end)
    case("power-native-and-PNG-actual-attachment-envelope-three-rows",function()
        local data=require("cjson").decode(read(ROOT.."power_fx.json"))
        local plate=data.skins[1].attachments.plate.nameplate
        eq(plate.width,740,"actual Power nameplate attachment width")
        eq(plate.height,340,"actual Power nameplate attachment height")
        eq(plate.y or 0,0,"actual Power nameplate centered attachment Y")
        for _,height in ipairs({174,270,366,254,350,446,314,410,506}) do
            local native=controlled();local token={}
            native.rich.drawPower(native.vg,960,235,760,height,1.1,3.2,1,token)
            local instance=assert(native.stats.instances[1])
            near(instance.sx,1,"Power native x scale target/760 rows height "..height)
            near(instance.sy,-height/340,"Power native Y scale target/actual 340 attachment "..height)
            near(plate.height*math.abs(instance.sy),height,"actual native plate height exactly target "..height)
            for _,host in ipairs({{1920,470},{1920,1080},{800,600},{180,320}}) do
                local scale=math.max(.01,math.min(1,(host[1]-40)/760,(host[2]-40)/height))
                local left=(host[1]-760*scale)*.5
                local top=(host[2]-height*scale)*.5
                local png=controlled({noNative=true})
                png.env.nvgTranslate(png.vg,left,top);png.env.nvgScale(png.vg,scale,scale)
                png.rich.drawPower(png.vg,380,height*.5,760,height,1.1,3.2,1,{})
                local vertices=assert(png.stats.platePaths[1],"real production PNG nameplate path absent") --[[@as number[][] ]]
                local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
                for _,v in ipairs(vertices) do minX=math.min(minX,v[1]);maxX=math.max(maxX,v[1]);minY=math.min(minY,v[2]);maxY=math.max(maxY,v[2]) end
                near(maxY-minY,height*scale,"actual transformed PNG plate target height "..height.."/"..host[2])
                near(maxX-minX,740*scale,"actual transformed PNG plate target width "..height.."/"..host[2])
                near((minY+maxY)*.5,host[2]*.5,"actual PNG plate host vertical center "..height.."/"..host[2])
                check(minY>=-.001 and maxY<=host[2]+.001 and minX>=-.001 and maxX<=host[1]+.001,
                    "stable plate envelope fits real host "..height.."/"..host[1].."x"..host[2])
                local nTop=host[2]*.5-plate.height*math.abs(instance.sy)*scale*.5
                local nBottom=host[2]*.5+plate.height*math.abs(instance.sy)*scale*.5
                near(nTop,minY,"native actual attachment and PNG share top "..height.."/"..host[2])
                near(nBottom,maxY,"native actual attachment and PNG share bottom "..height.."/"..host[2])
            end
        end
        -- Envelope contract concerns the steady plaque; deliberate intro/exit bone transforms
        -- are animation, not fabricated UI dimensions. Intro root reaches scale1.04 at .3s.
    end)
    case("same-time-transform-change-refreshes-without-track-advance",function()
        for _,missing in ipairs({false,"UpdateWorldTransform"}) do
            local f=controlled({missingMethod=missing});local token={}
            draw(f,"power",.65,1,token)
            local obj=assert(f.stats.instances[1]);local elapsed=obj.time
            local updates=#f.stats.updates
            f.rich.drawPower(f.vg,960,235,760,506,2.08,3.2,1,token)
            near(obj.time,elapsed,"same-time transform never advances native clock "..tostring(missing))
            near(obj.sy,-506/340,"same-time transform has fresh target scale "..tostring(missing))
            if missing then
                eq(#f.stats.updates,updates+1,"missing world API uses one Update(0)")
                eq(f.stats.updates[#f.stats.updates],0,"fallback update refresh is zero delta")
            else eq(f.stats.worldRefreshes,1,"world API refresh called once on changed transform") end
            local count=#f.stats.updates;local worlds=f.stats.worldRefreshes
            f.rich.drawPower(f.vg,960,235,760,506,2.08,3.2,1,token)
            eq(#f.stats.updates,count,"same-time unchanged transform no extra Update")
            eq(f.stats.worldRefreshes,worlds,"same-time unchanged transform no world refresh")
            f.rich.drawPower(f.vg,960,235,760,506,2.24,3.2,1,token)
            near(obj.time,2.24,"positive elapsed advances native exactly once")
            eq(f.stats.worldRefreshes,worlds,"positive delta Update does not also refresh world twice")
        end
    end)
    case("native-release-selects-one-api-Unload-or-Dispose-fallback",function()
        for _,missing in ipairs({"Unload","Dispose"}) do
            local f=controlled({missingMethod=missing});local token={}
            draw(f,"job",.5,1,token);f.rich.release(token);f.rich.release(token)
            eq(f.stats.unloads,missing=="Unload" and 0 or 1,"single selected Unload API when missing "..missing)
            eq(f.stats.disposes,missing=="Unload" and 1 or 0,"Dispose fallback only if Unload absent "..missing)
        end
    end)
    case("native-fault-matrix-single-attempt-PNG-fallback",function()
        local faults={{noNative=true},{createThrow=true},{createNil=true},{loadFalse=true},{loadThrow=true},
            {animationFalse=true},{animationThrow=true},{duration=0},{duration=-1},{duration=0/0},
            {duration=math.huge},{durationThrow=true},{updateThrow=true},{renderThrow=true},
            {missingMethod="Update"},{missingMethod="Load"},{missingMethod="GetAnimationDuration"}}
        for index,opts in ipairs(faults) do
            local f=controlled(opts);local token={};draw(f,"level",.5,1,token)
            check(f.stats.patterns>0,"fault "..index.." executes actual production PNG layers")
            eq(f.stats.fallback,0,"fault "..index.." PNG success not vector substitute")
            local creates,loads,animations,unloads,disposes,logs=f.stats.creates,f.stats.loads,f.stats.animations,f.stats.unloads,f.stats.disposes,#f.stats.logs
            for _=1,8 do draw(f,"level",.5,1,token) end
            eq(f.stats.creates,creates,"fault "..index.." does not retry create every frame")
            eq(f.stats.loads,loads,"fault "..index.." does not retry Load")
            eq(f.stats.animations,animations,"fault "..index.." animation attempted once")
            eq(f.stats.unloads,unloads,"fault "..index.." no repeated unload")
            eq(f.stats.disposes,disposes,"fault "..index.." no repeated Dispose")
            eq(#f.stats.logs,logs,"fault "..index.." log not spammed")
            eq(f.stats.depth,0,"fault "..index.." successful restore before fallback")
        end
    end)
    case("PNG-failure-vector-and-explicit-recovery",function()
        for index,opts in ipairs({{noNative=true,imageMissing="seal_plate"},{noNative=true,imageThrow=true},
            {noNative=true,noImageAPI=true},{noNative=true,patternThrow=true}}) do
            local f=controlled(opts);local token={};draw(f,"success",.5,1,token)
            eq(f.stats.fallback,1,"PNG failure "..index.." executes actual private vector source")
            local images,patterns,logs=f.stats.images,f.stats.patterns,#f.stats.logs
            for _=1,8 do draw(f,"success",.5,1,token) end
            eq(f.stats.images,images,"PNG failure "..index.." no image-create retry")
            eq(f.stats.patterns,patterns,"PNG failure "..index.." layer failure latched")
            eq(#f.stats.logs,logs,"PNG failure "..index.." logs latched")
            eq(f.stats.depth,0,"PNG/vector failure path restores caller matrix")
        end
        local opts={noNative=true,imageMissing="seal_plate"};local f=controlled(opts)
        draw(f,"success",.5,1,{});local before=f.stats.images
        opts.imageMissing=nil;draw(f,"success",.5,1,{})
        eq(f.stats.images,before,"missing-image zero remains cached until destroy")
        f.rich.destroy();local fallback=f.stats.fallback
        draw(f,"success",.5,1,{})
        eq(f.stats.images,before+14,"explicit destroy reloads repaired context once")
        eq(f.stats.fallback,fallback,"repaired images genuinely draw, not fallback")
    end)
    case("PNG-context-ownership-transform-alpha-identities",function()
        local f=controlled({noNative=true});local other={}
        f.rich.preload(f.vg);f.rich.preload(other);eq(f.stats.images,28,"distinct context has distinct image cache")
        local signatures={}
        for _,kind in ipairs(KINDS) do
            local full=controlled({noNative=true});local half=controlled({noNative=true})
            full.env.nvgTranslate(full.vg,17,23);full.env.nvgScale(full.vg,.5,.75)
            local old=full.matrix();draw(full,kind,.5,1,{})
            local after=full.matrix()
            for key,value in pairs(old) do near(after[key],value,"host transform restored "..kind.."/"..key) end
            eq(full.stats.invalid,0,"finite transformed vertices "..kind)
            check(#full.stats.geometry>0,"PNG produces real rotated quadrilateral geometry "..kind)
            local signature={};for _,point in ipairs(full.stats.geometry) do
                signature[#signature+1]=string.format("%.6f,%.6f",point[1],point[2]) end
            signatures[kind]=table.concat(signature,"|")
            draw(half,kind,.5,.5,{})
            eq(#full.stats.colors,#half.stats.colors,"all texture tint calls retained "..kind)
            local multiplied=true
            for i,c in ipairs(full.stats.colors) do local h=half.stats.colors[i]
                if not h or math.abs(c[4]*.5-h[4])>.501 then multiplied=false end end
            check(multiplied,"all texture tint alpha individually multiplied "..kind)
            local creates=full.stats.creates;local imageCount=full.stats.images
            for _=1,30 do draw(full,kind,.6,1) end
            eq(full.stats.creates,creates,"tokenless draw never creates native per-frame "..kind)
            eq(full.stats.images,imageCount,"PNGs never recreated per-frame "..kind)
        end
        for i=1,#KINDS do for j=i+1,#KINDS do
            check(signatures[KINDS[i]]~=signatures[KINDS[j]],"geometry identity "..KINDS[i].."/"..KINDS[j]) end end
        f.rich.destroy();eq(#f.stats.deletes,28,"destroy deletes both owning-context caches")
        local byContext={};for _,item in ipairs(f.stats.deletes) do byContext[item[1]]=(byContext[item[1]] or 0)+1 end
        eq(byContext[f.vg],14,"first context ownership preserved on delete")
        eq(byContext[other],14,"second context ownership preserved on delete")
    end)
    case("invalid-input-zero-alpha-Save-Restore-failures",function()
        local f=controlled();local token={}
        for _,alpha in ipairs({0,-1,0/0,math.huge,-math.huge}) do draw(f,"job",.5,alpha,token) end
        for _,p in ipairs({0,-1,1,10,0/0,math.huge}) do draw(f,"job",p,1,token) end
        f.rich.drawCard(f.vg,"unknown",0,0,200,350,.5,1,1,token)
        f.rich.drawPower(f.vg,0/0,0,760,200,.5,1,1,token)
        f.rich.drawPower(f.vg,0,0,0,200,.5,1,1,token)
        eq(f.stats.creates,0,"invalid/zero alpha never creates native")
        eq(f.stats.images,0,"invalid/deadline never creates images")
        eq(f.stats.saveCalls,0,"invalid/deadline never mutates state")
        for _,opts in ipairs({{saveThrow=true},{restoreThrow=true},{noNative=true,saveThrow=true},{noNative=true,restoreThrow=true}}) do
            local fault=controlled(opts)
            check(not pcall(draw,fault,"job",.5,1,{}),"unknown stack Save/Restore failure propagates rather than guesses")
            eq(fault.stats.fallback,0,"unknown stack forbids trying another backend")
            if opts.saveThrow then eq(fault.stats.restoreCalls,0,"failed Save never blind Restores") end
        end
    end)
    case("release-reentry-and-context-reuse-protection",function()
        local opts={};local f=controlled(opts);local token={}
        opts.onUpdate=function() f.rich.release(token) end
        draw(f,"level",.5,1,token)
        eq(f.stats.renders,0,"release during Update does not render detached instance")
        eq(f.stats.unloads,1,"reentrant update release unload once")
        eq(f.stats.disposes,0,"reentrant update release uses Unload only")
        opts.onUpdate=nil;draw(f,"level",.6,1,token)
        eq(f.stats.creates,1,"retired reentrant token stays retired")
        local token2={};draw(f,"job",.5,1,token2)
        draw(f,"job",.6,1,token2,{})
        eq(f.stats.creates,2,"same token in second context never reloads native")
        eq(f.stats.unloads,2,"cross-context stale native disposed")
        check(f.stats.fallback>0,"cross-context misuse falls to actual vector safely")
        local old={};draw(f,"revive",.5,1,old)
        local nested={};opts.onUnload=function() opts.onUnload=nil;draw(f,"power",.5,1,nested) end
        f.rich.destroy()
        local before=f.stats.renders;draw(f,"power",.6,1,nested)
        eq(f.stats.renders,before+1,"destroy detached batch preserves reentrant new playback")
    end)
end
local function resources()
    case("independent-Spine-4.2-atlas-attachment-structure",function()
        local json=require("cjson")
        for _,family in ipairs({"card","result","power"}) do
            local data=json.decode(read(ROOT..family.."_fx.json"))
            eq(data.skeleton.spine,"4.2.43","declared Spine version "..family)
            check(type(data.skins)=="table" and data.skins[1] and data.skins[1].name=="default","array-form default skin "..family)
            local bones={};for _,b in ipairs(data.bones) do
                check(not bones[b.name],"unique bone "..family.."/"..b.name)
                if b.parent then check(bones[b.parent],"parent defined before child "..b.name) end
                bones[b.name]=true end
            local slots={};for _,s in ipairs(data.slots) do
                check(bones[s.bone],"slot references existing bone "..family.."/"..s.name)
                slots[s.name]=s end
            local atlas=read(ROOT..family.."_fx.atlas")
            check(not atlas:find("bounds:",1,true) and not atlas:find("offsets:",1,true) and not atlas:find("pma:",1,true),"atlas avoids newer 4.2-only fields "..family)
            local lines={};for line in atlas:gmatch("[^\r\n]+") do lines[#lines+1]=line end
            eq(lines[1],"atlas.png","actual shared atlas page path "..family)
            check(lines[2]:match("^size:") and lines[3]:match("^format:") and lines[4]:match("^filter:") and lines[5]:match("^repeat:"),"fixed old page order "..family)
            local count=0;local names={}
            for i,line in ipairs(lines) do if REGIONS[line] then
                count=count+1;names[line]=true
                local w,h=lines[i+3]:match("size:%s*(%d+),%s*(%d+)")
                local x,y=lines[i+2]:match("xy:%s*(%d+),%s*(%d+)")
                eq(tonumber(w),REGIONS[line][1],"atlas width "..family.."/"..line)
                eq(tonumber(h),REGIONS[line][2],"atlas height "..family.."/"..line)
                check(x and tonumber(x)+tonumber(w)<=1024 and y and tonumber(y)+tonumber(h)<=1024,"atlas region bounds "..family.."/"..line)
                check(lines[i+1]:match("rotate:") and lines[i+4]:match("orig:") and lines[i+5]:match("offset:") and lines[i+6]:match("index:"),"old region order "..family.."/"..line)
            end end
            eq(count,14,"all 14 atlas regions present "..family)
            for slot,attachments in pairs(data.skins[1].attachments) do
                check(slots[slot],"skin attachment slot exists "..family.."/"..slot)
                for name,a in pairs(attachments) do check(names[a.path or name],"attachment region exists "..family.."/"..name) end
            end
            for name,animation in pairs(data.animations) do
                check(DURATIONS[name] and ((family=="card" and (name=="level" or name=="job" or name=="revive"))
                    or (family=="result" and (name=="success" or name=="failure")) or (family=="power" and name=="power")),"family animation allowed "..family.."/"..name)
                local maximum=0
                local function walk(t)
                    for key,v in pairs(t) do if type(v)=="table" then walk(v)
                        elseif key=="time" then check(type(v)=="number" and v>=0,"timeline valid time "..family.."/"..name);maximum=math.max(maximum,v) end end
                end
                walk(animation);near(maximum,DURATIONS[name],"strict declared timeline duration "..family.."/"..name)
                if animation.bones then for bone,timeline in pairs(animation.bones) do
                    check(bones[bone],"animated bone exists "..bone)
                    if timeline.rotate then for _,key in ipairs(timeline.rotate) do
                        check(key.value~=nil and key.angle==nil,"4.2 rotate uses value "..bone) end end end end
                if animation.slots then for slot,timeline in pairs(animation.slots) do
                    check(slots[slot],"animated slot exists "..slot)
                    check(timeline.color==nil and timeline.rgba~=nil,"4.2 slot color uses rgba "..slot) end end
            end
        end
    end)
end
-- Actual native C bindings forwarded without replacing ANY shared global.
local function realFixture(vg,noNative,options)
    local opts=options or {}
    local stats={fallback=0,creates=0,loads=0,animations=0,renders=0,images=0,patterns=0,fills=0,
        unloads=0,disposes=0,depth=0,logs={},objects={},deletes={},failedLoadCalls=0}
    local env=privateEnv(stats.logs)
    for name,value in pairs(_G) do if type(name)=="string" and name:match("^nvg") then env[name]=value end end
    local nativeSave,nativeRestore,nativeImage,nativeDelete,nativePattern,nativeTint,nativeFill=
        nvgSave,nvgRestore,nvgCreateImage,nvgDeleteImage,nvgImagePattern,nvgImagePatternTinted,nvgFill
    env.nvgSave=function(ctx) nativeSave(ctx);stats.depth=stats.depth+1 end
    env.nvgRestore=function(ctx) nativeRestore(ctx);stats.depth=stats.depth-1 end
    env.nvgCreateImage=function(ctx,path,flags)
        stats.images=stats.images+1
        local image=nativeImage(ctx,path,flags)
        check(type(image)=="number" and image>0,"actual PNG decodes "..path)
        local name=path:match("([^/]+)%.png$")
        if image>0 and REGIONS[name] then
            local width,height=nvgImageSize(ctx,image)
            eq(width,REGIONS[name][1],"actual decoded PNG width "..name)
            eq(height,REGIONS[name][2],"actual decoded PNG height "..name)
        end
        return image
    end
    env.nvgDeleteImage=function(ctx,id) stats.deletes[#stats.deletes+1]={ctx,id};return nativeDelete(ctx,id) end
    env.nvgImagePattern=function(...)
        local paint=nativePattern(...);stats.patterns=stats.patterns+1;stats.pendingTexture=true;return paint
    end
    if type(nativeTint)=="function" then env.nvgImagePatternTinted=function(...)
        local paint=nativeTint(...);stats.patterns=stats.patterns+1;stats.pendingTexture=true;return paint
    end end
    env.nvgFill=function(ctx)
        nativeFill(ctx);stats.fills=stats.fills+1
        if stats.pendingTexture then totals.textureFills=totals.textureFills+1;stats.pendingTexture=false end
    end
    if noNative then env.nvgSpineCreate=nil;env.nvgSpineRender=nil
    else
        assert(type(original.spine)=="function" and type(original.render)=="function","actual native Spine APIs unavailable")
        env.nvgSpineCreate=function(ctx)
            stats.creates=stats.creates+1
            local obj=assert(original.spine(ctx),"real Spine create returned nil")
            local proxy={native=obj,track=0}
            for _,name in ipairs({"SetPosition","SetScale","SetColor","SetSpeed","SetTimeScale","SetPremultipliedAlpha","FindSlot"}) do
                local method=obj[name] --[[@as function]]
                if type(method)=="function" then proxy[name]=function(_,...) return method(obj,...) end end
            end
            function proxy:Load(path)
                if opts.failedLoad then
                    eq(path,ROOT.."card_fx.json","production requests unchanged real card family path")
                    stats.failedLoadCalls=stats.failedLoadCalls+1
                    -- Native call is real, only its resource argument is privately redirected.
                    -- pcall diagnoses Lua binding errors; it cannot catch a C crash.
                    local ok,result=pcall(function() return obj:Load(ROOT.."__dark_rich_intentionally_missing__.json") end)
                    self.failedLoadOk,self.failedLoadResult=ok,result
                    check(ok and result==false,"actual missing-resource native Load returns false")
                    eq(obj:IsLoaded(),false,"actual failed native instance remains unloaded")
                    if not ok then error(result,0) end
                    return result
                end
                local result=obj:Load(path)
                if result==true then stats.loads=stats.loads+1;totals.nativeLoads=totals.nativeLoads+1 end
                check(result==true and obj:IsLoaded(),"actual Spine native Load/IsLoaded "..path)
                return result
            end
            function proxy:SetAnimation(track,name,loop)
                local result=obj:SetAnimation(track,name,loop)
                if result then stats.animations=stats.animations+1 end
                check(result==true,"actual native animation exists "..name)
                return result
            end
            function proxy:GetAnimationDuration(track) return obj:GetAnimationDuration(track) end
            function proxy:Update(dt) obj:Update(dt);self.track=obj:GetTrackTime(0) end
            function proxy:Unload() stats.unloads=stats.unloads+1;return obj:Unload() end
            function proxy:Dispose() stats.disposes=stats.disposes+1;return obj:Dispose() end
            stats.objects[#stats.objects+1]=proxy
            return proxy
        end
        env.nvgSpineRender=function(ctx,proxy)
            original.render(ctx,proxy.native);stats.renders=stats.renders+1;totals.nativeRenders=totals.nativeRenders+1
        end
    end
    local f={vg=vg,env=env,stats=stats};f.rich=loadRich(env,stats);keep[#keep+1]=f
    return f
end
local frameCleanup={} ---@type function[]
local function nativeRender(vg)
    case("actual-native-six-animations-frame-loading-render-release",function()
        local f=realFixture(vg,false)
        local nativeTokens={}
        for _,kind in ipairs(KINDS) do
            local token={};nativeTokens[#nativeTokens+1]=token;local before=f.stats.loads
            draw(f,kind,.65,1,token)
            eq(f.stats.loads,before+1,"native family truly loaded "..kind)
            local proxy=assert(f.stats.objects[#f.stats.objects])
            near(proxy.track,DURATIONS[kind]*.65,"native track actual first late sample "..kind,.001)
            near(proxy.native:GetAnimationDuration(0),DURATIONS[kind],"native duration actual "..kind,.001)
            eq(proxy.native:IsPremultipliedAlpha(),false,"actual native straight alpha "..kind)
            local old=proxy.track;draw(f,kind,.65,1,token)
            near(proxy.native:GetTrackTime(0),old,"same-time actual native not advanced twice "..kind,.001)
            if kind=="power" then
                -- 原生帧额外读取真实槽颜色，不能把受控对象的alpha记录当作GPU/API实证。
                local sweep=assert(proxy.native:FindSlot("sweep"),"actual native sweep slot absent")
                check(sweep:IsValid(),"actual native cached sweep slot valid")
                local getSlotColor=sweep.GetColor --[[@as function]]
                local _,_,_,sweepAlpha=getSlotColor(sweep)
                eq(sweepAlpha,0,"actual native power sweep hidden after animation Update")
                local plate=require("cjson").decode(read(ROOT.."power_fx.json")).skins[1].attachments.plate.nameplate
                for _,height in ipairs({174,270,366,254,350,446,314,410,506}) do
                    local fit=math.min(1,430/height)
                    f.rich.drawPower(vg,960,235,760*fit,height*fit,2.08,3.2,1,token)
                    local bone=assert(proxy.native:FindBone("plate"),"actual native plate bone absent")
                    near(math.abs(bone:GetWorldScaleY()),height/340*fit,"actual native plate bone scale target/340 height "..height,.001)
                    near(plate.height*math.abs(bone:GetWorldScaleY()),height*fit,"actual native bone attachment envelope height "..height,.01)
                    local center=bone:GetWorldY()
                    near(center,235,"actual native plaque center host470 height "..height,.01)
                    check(center-height*fit*.5>=-.01 and center+height*fit*.5<=470.01,"actual native stable plaque fits host470 height "..height)
                end
            end
        end
        eq(f.stats.loads,6,"six real native loads not fake/fallback")
        eq(f.stats.renders,21,"twenty-one actual nvgSpineRender submissions including old/new Power heights")
        eq(f.stats.patterns,0,"native test not passed through PNG fallback")
        eq(f.stats.fallback,0,"native test not passed through vector fallback")
        eq(f.stats.depth,0,"actual native stack balanced")
        -- Render enqueues native draws. Do not dispose its data while this frame is pending.
        frameCleanup[#frameCleanup+1]=function()
            for _,token in ipairs(nativeTokens) do f.rich.release(token) end
            eq(f.stats.unloads,6,"six actual native Unload after completed native frame")
            eq(f.stats.disposes,0,"actual native Unload never followed by unsafe Dispose")
            f.rich.destroy()
        end
    end)
end
local function texturesRender(vg)
    case("actual-14-PNG-texture-draw-and-reuse",function()
        local f=realFixture(vg,true);f.rich.preload(vg)
        eq(f.stats.images,14,"actual PNG preload exactly fourteen")
        for _,kind in ipairs(KINDS) do
            local before=f.stats.patterns
            draw(f,kind,.5,1,{})
            check(f.stats.patterns>before,"actual ImagePattern texture used "..kind)
            eq(f.stats.fallback,0,"texture success must not use vector "..kind)
        end
        for _=1,20 do for _,kind in ipairs(KINDS) do draw(f,kind,.65,.5) end end
        eq(f.stats.images,14,"real actual images not recreated per frame")
        eq(f.stats.creates,0,"forced-PNG fixture never invokes native creator")
        check(f.stats.fills>0,"actual PNG polygon fills submitted")
        eq(f.stats.depth,0,"actual PNG state stack balanced")
        f.rich.destroy();eq(#f.stats.deletes,14,"actual PNG owner releases every handle")
    end)
end
local failedLoadDone=false
local function failedLoadRender(vg)
    case("actual-native-failed-Load-Unload-once-private-fresh-context",function()
        local f=realFixture(vg,false,{failedLoad=true});local token={}
        draw(f,"job",.5,1,token)
        eq(f.stats.creates,1,"failed-load path creates one real native instance")
        eq(f.stats.failedLoadCalls,1,"failed-load path calls real Load once")
        eq(f.stats.loads,0,"failed-load injection is not counted as native success")
        eq(f.stats.unloads,1,"production immediately Unloads failed native object once")
        eq(f.stats.disposes,0,"production never Disposes after failed native Unload")
        eq(f.stats.animations,0,"failed Load never starts animation")
        eq(f.stats.renders,0,"failed Load never submits native render")
        check(f.stats.patterns>0,"failed native Load genuinely falls back to actual PNG")
        eq(f.stats.fallback,0,"failed native Load actual PNG does not silently use vector")
        local images=f.stats.images;local logs=#f.stats.logs
        for _=1,8 do draw(f,"job",.6,1,token) end
        eq(f.stats.creates,1,"failed native instance not recreated each frame")
        eq(f.stats.failedLoadCalls,1,"failed actual Load never retried")
        eq(f.stats.images,images,"failed native fallback reuses actual PNG handles")
        eq(#f.stats.logs,logs,"failed Load diagnostic is latched")
        eq(f.stats.depth,0,"failed Load fallback restores actual NanoVG stack")
        f.rich.release(token);f.rich.release(token);f.rich.destroy();f.rich.destroy()
        eq(f.stats.unloads,1,"release/destroy cannot retry failed native Unload")
        eq(f.stats.disposes,0,"failed path release/destroy never calls Dispose")
        eq(#f.stats.deletes,14,"fresh failed-load context releases its fourteen PNGs")
    end)
    failedLoadDone=true
end
local frameStage=0
local sharedTexture=nil
local function contextRender(vg)
    case("actual-two-context-PNG-isolation",function()
        if not sharedTexture then sharedTexture=realFixture(vg,true) end
        sharedTexture.rich.preload(vg)
        draw(sharedTexture,"power",.5,1,{},vg)
        eq(sharedTexture.stats.images,frameStage==3 and 14 or 28,"actual context has own fourteen native image loads")
        eq(sharedTexture.stats.fallback,0,"both actual contexts draw PNG not vector")
        if frameStage==4 then
            sharedTexture.rich.destroy()
            local owners={};for _,item in ipairs(sharedTexture.stats.deletes) do owners[item[1]]=(owners[item[1]] or 0)+1 end
            eq(owners[contexts[1]],14,"actual first context deletes its own images")
            eq(owners[contexts[2]],14,"actual second context deletes its own images")
        end
    end)
end
local function finish()
    if ended then return end;ended=true
    for _,f in ipairs(keep) do pcall(f.rich.destroy) end
    eq(nvgCreateImage,original.create,"shared nvgCreateImage unchanged")
    eq(nvgDeleteImage,original.delete,"shared nvgDeleteImage unchanged")
    eq(nvgSpineCreate,original.spine,"shared nvgSpineCreate unchanged")
    eq(nvgSpineRender,original.render,"shared nvgSpineRender unchanged")
    eq(math.random,original.random,"shared random unchanged")
    eq(math.randomseed,original.seed,"shared seed unchanged")
    eq(require,original.require,"shared require unchanged")
    print(string.format("%s %s mode=%s cases=%d checks=%d failures=%d actualNativeLoads=%d actualNativeRenders=%d actualTextureFills=%d",
        TAG,totals.failures==0 and "ALL PASS" or "FAILED",failedLoadOnly and "native-failed-load-injection" or (logicOnly and "logic+resources" or (nativeOnly and "native" or (pngOnly and "PNG+contexts" or "full"))),
        totals.cases,totals.checks,totals.failures,totals.nativeLoads,totals.nativeRenders,totals.textureFills))
    engine:Exit()
end
function Start()
    local ok,err=pcall(function()
        for _,arg in ipairs(GetArguments()) do
            if arg=="-dark-rich-logic-only" then logicOnly=true end
            if arg=="-dark-rich-native-only" then nativeOnly=true end
            if arg=="-dark-rich-png-only" then pngOnly=true end
            if arg=="-dark-rich-failed-load-only" then failedLoadOnly=true end
        end
        if not nativeOnly and not pngOnly and not failedLoadOnly then logic();resources() end
        if logicOnly then finish();return end
        if pngOnly then frameStage=1 end
        contexts[1]=assert(nvgCreate(1),"actual context A unavailable")
        contexts[2]=assert(nvgCreate(1),"actual context B unavailable")
        if not nativeOnly and not pngOnly then
            contexts[3]=assert(nvgCreate(1),"actual fresh failed-load context unavailable")
            SubscribeToEvent(contexts[3],"NanoVGRender","HandleDarkRichFailedLoad")
        end
        SubscribeToEvent(contexts[1],"NanoVGRender","HandleDarkRichRenderA")
        SubscribeToEvent(contexts[2],"NanoVGRender","HandleDarkRichRenderB")
    end)
    if not ok then check(false,"startup "..tostring(err));finish() end
end
local function render(vg,second)
    if ended or failedLoadOnly then return end
    if second and frameStage~=3 then return end
    if not second and frameStage>=3 then return end
    -- A previously submitted native frame is fully done before this event begins.
    local cleanups=frameCleanup;frameCleanup={}
    for _,cleanup in ipairs(cleanups) do
        local cleaned,cleanupErr=pcall(cleanup)
        if not cleaned then check(false,"native next-frame release "..tostring(cleanupErr)) end
    end
    if nativeOnly and frameStage==1 then finish();return end
    local begun=false
    local ok,err=pcall(function()
        local dpr=graphics:GetDPR()
        nvgBeginFrame(vg,graphics:GetWidth()/dpr,graphics:GetHeight()/dpr,dpr);begun=true
        frameStage=frameStage+1
        if frameStage==1 then nativeRender(vg)
        elseif frameStage==2 then texturesRender(vg)
        else contextRender(vg) end
    end)
    if begun then local endedFrame,frameErr=pcall(nvgEndFrame,vg);if not endedFrame then check(false,"native end-frame "..tostring(frameErr)) end end
    if not ok then check(false,"native frame "..tostring(err));finish()
    elseif frameStage==4 and (failedLoadDone or pngOnly) then finish() end
end
function HandleDarkRichRenderA() render(contexts[1],false) end
function HandleDarkRichRenderB() render(contexts[2],true) end
function HandleDarkRichFailedLoad()
    if ended or failedLoadDone then return end
    local vg=contexts[3];local begun=false
    local ok,err=pcall(function()
        local dpr=graphics:GetDPR()
        nvgBeginFrame(vg,graphics:GetWidth()/dpr,graphics:GetHeight()/dpr,dpr);begun=true
        failedLoadRender(vg)
    end)
    if begun then
        local closed,frameErr=pcall(nvgEndFrame,vg)
        if not closed then check(false,"failed-load context end-frame "..tostring(frameErr)) end
    end
    if not ok then check(false,"failed-load native frame "..tostring(err));finish()
    elseif failedLoadOnly or frameStage==4 then finish() end
end
function Stop()
    for _,f in ipairs(keep) do pcall(f.rich.destroy) end
    for _,vg in ipairs(contexts) do nvgDelete(vg) end
    contexts={}
end
