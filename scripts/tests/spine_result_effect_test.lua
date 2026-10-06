-- 本轮适配：整套 Spine 改为程序化，本文件移除旧原生 Create/Load/监听/Unload/Dispose 57场景1220断言。
-- 新专项：真实程序化 Result controller 生命周期、draw故障隔离、callback重入/抛错、非法输入。
-- 不代表保留原生 Spine GPU 覆盖；不读取玩家档，只读 ResourceCache 源码+独立env。
-- 运行：UrhoXRuntime tests/spine_result_effect_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
local totals={assertions=0,failures=0,cases=0}
local source=""
local cleanups={}
local function check(ok,label)
    totals.assertions=totals.assertions+1
    if ok then print("[PASS] "..label) else totals.failures=totals.failures+1;print("[FAIL] "..label) end
end
local function eq(a,b,label) check(a==b,label.." actual="..tostring(a).." expected="..tostring(b)) end
local function case(label,fn)
    totals.cases=totals.cases+1
    local ok,err=pcall(fn)
    if not ok then check(false,label.." exception="..tostring(err)) end
end
local function fixture()
    local stats={draws=0,callbacks=0,depth=0,forbidden=0,logs={},args={},throw=false,reenter=function() end}
    local clock={elapsedTime=100.0}
    local env={time=clock,math=math,table=table,string=string,assert=assert,error=error,type=type,
        ipairs=ipairs,pairs=pairs,next=next,tostring=tostring,pcall=pcall,
        print=function(line) stats.logs[#stats.logs+1]=line end}
    env.nvgSave=function() stats.depth=stats.depth+1 end
    env.nvgRestore=function() stats.depth=stats.depth-1 end
    env.nvgSpineCreate=function() stats.forbidden=stats.forbidden+1;error("Spine forbidden") end
    env.nvgSpineRender=env.nvgSpineCreate;env.nvgCreateImage=env.nvgSpineCreate
    env.require=function(name)
        assert(name=="ui.fx.DarkEffectPrimitives",name)
        return {drawResult=function(_,success,cx,cy,size,elapsed,duration,alpha)
            stats.draws=stats.draws+1
            stats.args={success,cx,cy,size,elapsed,duration,alpha}
            stats.reenter()
            if stats.throw then error("RESULT_PROCEDURAL_FAULT",0) end
        end}
    end
    local effect=assert(load(source,"@ui/fx/SpineResultEffect.lua","t",env))()
    cleanups[#cleanups+1]=effect.destroy
    return {effect=effect,clock=clock,stats=stats,vg={}}
end
local function run()
    case("success-failure-no-draw",function()
        local f=fixture();f.effect.preload(nil);f.effect.preload(f.vg)
        for _,success in ipairs({true,false}) do
            local start=f.clock.elapsedTime
            f.effect.play(success,function() f.stats.callbacks=f.stats.callbacks+1 end)
            f.effect.update(math.huge)
            check(f.effect.isPlaying(),"dt不推进Result墙钟")
            f.clock.elapsedTime=start+(success and 1.6667 or 1.3333)-.01;f.effect.update(0)
            check(f.effect.isPlaying(),"保留完整duration "..tostring(success))
            f.clock.elapsedTime=start+(success and 1.6667 or 1.3333)+.01;f.effect.update(0)
            check(not f.effect.isPlaying(),"无draw墙钟到期 "..tostring(success))
        end
        eq(f.stats.callbacks,2,"两次callback各一次")
        eq(f.stats.draws,0,"无draw确无原语执行")
        f.effect.update(0);f.effect.isPlaying();eq(f.stats.callbacks,2,"重复query无二次callback")
        eq(f.stats.forbidden,0,"Result完全无Spine/图像")
    end)
    case("draw-arguments-alpha-and-replace",function()
        local f=fixture();local old=0
        f.effect.play(true,function() old=old+1 end);f.clock.elapsedTime=100.4
        f.effect.draw(f.vg,540,600,200,.5)
        eq(f.stats.args[1],true,"真实success身份")
        eq(f.stats.args[2],540,"中心X不乘DPR")
        eq(f.stats.args[3],600,"中心Y不乘fit")
        eq(f.stats.args[4],200,"size不改写")
        check(math.abs(f.stats.args[5]-.4)<.00001,"draw实际墙钟elapsed")
        eq(f.stats.args[7],.5,"alpha传入原语")
        eq(f.stats.depth,0,"draw平衡stack")
        for _,alpha in ipairs({0,-1,0/0,math.huge,-math.huge}) do f.effect.draw(f.vg,540,600,200,alpha) end
        eq(f.stats.draws,1,"invalid/alpha0不绘制")
        f.effect.play(false);f.effect.draw(f.vg,540,600)
        eq(f.stats.args[1],false,"真实failure身份不同")
        eq(f.stats.args[4],160,"默认size160")
        f.clock.elapsedTime=102;f.effect.update(0)
        eq(old,0,"替换取消旧callback")
    end)
    case("callback-error-reentry-and-stop",function()
        local f=fixture();local count=0
        f.effect.play(true,function() count=count+1;error("CALLBACK_FAULT",0) end)
        f.clock.elapsedTime=101.68;check(pcall(f.effect.update,0),"callback抛错被隔离")
        eq(count,1,"throwing callback一次")
        check(not f.effect.isPlaying(),"throwing callback不留下播放状态")
        f.effect.play(true,function()
            count=count+1;f.effect.destroy();f.effect.play(false,function() count=count+1 end)
        end)
        f.clock.elapsedTime=103.36;f.effect.update(0)
        eq(count,2,"重入前callback一次")
        check(f.effect.isPlaying(),"重入新播放不会被旧cleanup删")
        f.clock.elapsedTime=104.70;f.effect.update(0);eq(count,3,"重入独立完成")
        f.effect.play(true,function() count=count+1 end);f.effect.stop();f.effect.stop()
        f.clock.elapsedTime=200;f.effect.update(0);eq(count,3,"stop取消callback")
    end)
    case("fault-safe-disable-and-explicit-reset",function()
        local f=fixture();f.stats.throw=true
        f.effect.play(true,function() f.stats.callbacks=f.stats.callbacks+1 end)
        f.clock.elapsedTime=100.2
        local after=0
        check(pcall(function() f.effect.draw(f.vg,500,600,160);after=after+1 end),"draw故障不外抛")
        eq(after,1,"同帧后续业务继续")
        eq(f.stats.depth,0,"故障后stack0")
        local logs=#f.stats.logs
        for _=1,8 do f.effect.draw(f.vg,500,600,160);f.effect.play(false) end
        eq(f.stats.draws,1,"故障只执行一次不每帧重试")
        eq(#f.stats.logs,logs,"故障不每帧重复日志")
        f.clock.elapsedTime=200;f.effect.update(0)
        eq(f.stats.callbacks,0,"fault取消原callback")
        check(not f.effect.isPlaying(),"disabled不playing")
        f.stats.throw=false;f.effect.destroy();f.effect.play(false);f.effect.draw(f.vg,500,600,160)
        eq(f.stats.draws,2,"显式destroy可恢复")
        check(f.effect.isPlaying(),"修复后重播正常")
        eq(f.stats.forbidden,0,"无原生fallback")
    end)
    case("old-fault-does-not-cancel-reentrant-replacement",function()
        local f=fixture();f.stats.throw=true
        f.stats.reenter=function() f.effect.play(false,function() f.stats.callbacks=f.stats.callbacks+1 end) end
        f.effect.play(true);f.clock.elapsedTime=100.2
        check(pcall(f.effect.draw,f.vg,500,600,160),"旧draw故障隔离")
        check(f.effect.isPlaying(),"新播放不被旧id故障停用")
        eq(f.stats.depth,0,"重入故障stack0")
        f.stats.reenter=function() end;f.stats.throw=false
        f.clock.elapsedTime=101.54;f.effect.update(0)
        eq(f.stats.callbacks,1,"新id正常完成")
    end)
    case("invalid-clock-and-invalid-draw",function()
        local f=fixture()
        for _,value in ipairs({0/0,math.huge,-math.huge,-1}) do
            f.clock.elapsedTime=value;f.effect.play(true)
            check(not f.effect.isPlaying(),"非法clock不能开始 "..tostring(value))
        end
        f.clock.elapsedTime=100;f.effect.play(true)
        for _,value in ipairs({0/0,math.huge,-math.huge}) do
            f.clock.elapsedTime=value;f.effect.update(1000)
            check(f.effect.isPlaying(),"非法clock不提前完成合法播放")
        end
        f.clock.elapsedTime=100.2;f.effect.draw(f.vg,500,600,-1)
        check(not f.effect.isPlaying(),"非法size安全停用表现")
        eq(f.stats.draws,0,"非法参数未入原语")
    end)
end
function Start()
    local ok,err=pcall(function()
        local file=assert(cache:GetFile("ui/fx/SpineResultEffect.lua"))
        local lines={};while not file:IsEof() do lines[#lines+1]=file:ReadLine() end
        file:Dispose();source=table.concat(lines,"\n")
        run()
    end)
    for _,cleanup in ipairs(cleanups) do pcall(cleanup) end
    if not ok then check(false,"suite exception="..tostring(err)) end
    print(string.format("[spine_result_effect_test] %s cases=%d assertions=%d failures=%d",
        totals.failures==0 and "ALL PASS" or "FAIL",totals.cases,totals.assertions,totals.failures))
    engine:Exit()
end
