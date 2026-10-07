-- Card controller契约：保留页面隔离、显式尺寸、墙钟生命周期与取消语义。
-- Sprites后端在本入口受控注入；native Spine/纹理/释放另由rich入口实测，不禁止正式资源。
-- 只读生产源码→独立env；不改全局time/nvg、package.loaded，不加载玩家档。
local totals = {assertions=0,failures=0}
local function check(ok,label)
    totals.assertions=totals.assertions+1
    if ok then print("[PASS] "..label) else totals.failures=totals.failures+1;print("[FAIL] "..label) end
end
local function eq(a,b,label) check(a==b,label.." actual="..tostring(a).." expected="..tostring(b)) end
local function readSource()
    local file=assert(cache:GetFile("ui/fx/SpineCardEffect.lua"))
    local lines={}
    while not file:IsEof() do lines[#lines+1]=file:ReadLine() end
    file:Dispose()
    return table.concat(lines,"\n")
end
function Start()
    local cleanup = function() end
    local ok,err=pcall(function()
        local clock={elapsedTime=100.0}
        local calls, forbidden, depth={},0,0
        local env={time=clock,print=function() end,math=math,table=table,string=string,
            assert=assert,error=error,type=type,ipairs=ipairs,pairs=pairs,next=next,tostring=tostring,pcall=pcall}
        env.nvgSave=function() depth=depth+1 end
        env.nvgRestore=function() depth=depth-1 end
        env.nvgSpineCreate=function() forbidden=forbidden+1;error("Spine is forbidden") end
        env.nvgSpineRender=env.nvgSpineCreate
        env.nvgCreateImage=env.nvgSpineCreate
        env.require=function(name)
            if name=="core.BattleLayout" then return require(name) end
            assert(name=="ui.fx.DarkEffectSprites",name)
            return {preload=function() end,release=function() end,destroy=function() end,
                drawCard=function(_,kind,cx,cy,w,h,elapsed,duration,alpha)
                calls[#calls+1]={kind=kind,cx=cx,cy=cy,w=w,h=h,elapsed=elapsed,duration=duration,alpha=alpha}
            end}
        end
        local effect=assert(load(readSource(),"@ui/fx/SpineCardEffect.lua","t",env))()
        cleanup=effect.destroy
        local done=0
        effect.preload(nil);effect.preload({})
        effect.playLevelUp(100,200)
        effect.playJobChange(300,400,function() done=done+1 end)
        effect.playRevive(500,600)
        effect.playRevive(700,800,nil,"dungeon",120,210)
        clock.elapsedTime=100.2
        effect.draw({},"church")
        eq(#calls,1,"church只绘制转职")
        eq(calls[1].kind,"job","转职真实程序化kind")
        effect.draw({},"battle")
        eq(#calls,3,"battle只绘制升级及battle复活")
        effect.draw({},"dungeon")
        eq(#calls,4,"dungeon只绘制副本复活")
        eq(calls[4].w,120,"显式宽度不乘宿主DPR/fit")
        eq(calls[4].h,210,"显式高度不乘宿主DPR/fit")
        eq(calls[4].cx,700,"显式中心不改写")
        eq(calls[4].cy,800,"显式Y中心不改写")
        eq(depth,0,"程序化draw保护宿主stack")
        effect.draw({},"church",0)
        eq(#calls,4,"alpha0不绘制任何图元")
        clock.elapsedTime=101.0;effect.update(0)
        eq(done,0,"较短复活到期不提前完成转职")
        check(not effect.isPlaying("dungeon"),"没draw副本也按墙钟到期")
        clock.elapsedTime=101.34;effect.update(0)
        eq(done,1,"转职无draw墙钟完成一次")
        check(not effect.isPlaying(),"全部作用域到期")
        effect.update(100);effect.draw({},"church")
        eq(done,1,"重复update/draw不重复callback")
        effect.playLevelUp(100,200,function() done=done+1 end)
        effect.stopAll("battle");clock.elapsedTime=200;effect.update(0)
        eq(done,1,"stop取消而非完成callback")
        effect.destroy();effect.destroy()
        eq(forbidden,0,"受控Sprites注入后controller不旁路后端原生入口")
    end)
    pcall(cleanup)
    if not ok then check(false,"suite exception: "..tostring(err)) end
    print(string.format("[spine_card_effect_test] %s assertions=%d failures=%d",
        totals.failures==0 and "ALL PASS" or "FAIL",totals.assertions,totals.failures))
    engine:Exit()
end
