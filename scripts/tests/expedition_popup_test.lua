-- 升级组件真实布局/输入回归：不使用玩家 File，NanoVG spy 只观察实际 UI 组件输出。
function Start()
    local assertions = 0
    local function check(value, label)
        assertions = assertions + 1
        assert(value, label)
    end
    local realRequire = _G.require
    local globals = {}
    local function replace(name, fn)
        globals[name] = _G[name]
        _G[name] = fn
    end
    local clock = { elapsedTime = 100 }
    local texts, soundCount, navigations = {}, 0, 0
    local stack, transform = {}, { x=0, y=0, sx=1, sy=1 }
    local originalText = nvgText
    local vg = nvgCreate(1)
    nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf")
    local function noop() end
    local ok, err = pcall(function()
        local Progress = realRequire("config.ExpeditionProgress")
        local UI = realRequire("urhox-libs/UI")
        local Surface = realRequire("ui.widget.DesignWidgetSurface")
        Surface.init()
        _G.require = function(name)
            if name == "systems.GameSFX" then return {play=function() soundCount=soundCount+1 end} end
            if name == "runtime.ClientDispatcher" then return {get=function(key)
                if key=="task" then return {achClaimed={a_plv_5=true}} end
                return {}
            end} end
            if name == "core.GameState" then return {getLevel=function() return 60 end,getExp=function() return 0 end} end
            return realRequire(name)
        end
        local source = cache:GetFile("ui/hud/popup/LevelUpPopup.lua")
        local lines = {}
        while not source:IsEof() do lines[#lines+1] = source:ReadLine() end
        source:Dispose()
        local chunk, compileError = load(table.concat(lines,"\n"),"@LevelUpPopup.lua","t",_G)
        assert(chunk,compileError)
        local popup = chunk()
        replace("nvgSpineCreate",function() error("禁止创建旧升级Spine") end)
        replace("nvgSave",function()
            stack[#stack+1]={x=transform.x,y=transform.y,sx=transform.sx,sy=transform.sy}
        end)
        replace("nvgRestore",function()
            local saved=table.remove(stack);assert(saved,"无匹配save")
            transform=saved
        end)
        replace("nvgTranslate",function(_,x,y)
            transform.x=transform.x+x*transform.sx;transform.y=transform.y+y*transform.sy
        end)
        replace("nvgScale",function(_,x,y) transform.sx=transform.sx*x;transform.sy=transform.sy*y end)
        replace("nvgText",function(_,x,y,text)
            texts[#texts+1]={x=transform.x+x*transform.sx,y=transform.y+y*transform.sy,text=text}
        end)
        for _, name in ipairs({"nvgBeginPath","nvgRect","nvgRoundedRect","nvgCircle","nvgFill",
            "nvgFillColor","nvgFillPaint","nvgStroke","nvgStrokeColor","nvgStrokeWidth",
            "nvgIntersectScissor","nvgGlobalAlpha","nvgRotate","nvgTextScaleMode"}) do replace(name,noop) end
        local function draw(w,h)
            texts={};popup.draw(vg,w,h)
            check(#stack==0,"绘制状态栈平衡")
            check(transform.x==0 and transform.y==0,"绘制恢复宿主变换")
        end
        local function find(text)
            for _, item in ipairs(texts) do if item.text==text then return item end end
            return nil
        end
        popup.init(vg)
        popup.setOnViewRewards(function() navigations=navigations+1 end)
        popup.show(30,nil,1)
        draw(1280,720)
        check(find("Lv.30")~=nil,"冷首次0秒已绘制卡片")
        check(popup.handleInput(10,10,1280,720),"入场输入消费")
        check(popup.isOpen(),"入场不提前关闭")
        popup.update(0.4);draw(1280,720)
        check(find("Lv.1 → Lv.30    远征点上限 +29")~=nil,"跨级点数不是固定+1")
        check(find("每队可出战 4 人")~=nil,"跨级保留Lv2解锁")
        check(find("神器第 1 格")~=nil,"神器Lv30解锁")
        local button=find("查看奖励 · 4 项可领")
        check(button~=nil,"真实按钮字体可见且数量正确")
        check(popup.handleInput(button.x,button.y,1280,720),"真实Yoga按钮坐标命中")
        check(navigations==1 and not popup.isOpen(),"奖励入口仅触发一次并关闭升级层")
        check(not popup.handleInput(button.x,button.y,1280,720),"关闭后不再命中")
        popup.show(2,nil,1);popup.update(0.4);draw(800,450)
        popup.show(60,nil,30);popup.update(0.4);draw(800,450)
        check(find("Lv.1 → Lv.60    远征点上限 +59")~=nil,"连续show合并等级区间")
        check(find("神器第 2 格")~=nil or find("另有 2 项解锁，可前往奖励页查看")~=nil,"合并多格有完整摘要提示")
        check(popup.handleInput(0,0,800,450),"空白关闭输入消费")
        popup.update(0.3);check(not popup.isOpen(),"点击退出结束")
        popup.show(200,nil,199);popup.update(0.4);popup.update(5);popup.update(0.3)
        check(not popup.isOpen(),"自动关闭保留五秒节奏")
        popup.destroy();popup.show(10,nil,9);popup.update(0.4);draw(1280,720)
        check(find("Lv.10")~=nil,"销毁后重建无旧动画资源")
        check(soundCount==5,"每次show保留音效")
        local changes=Progress.getLevelUnlocks(6)
        check(#changes==1,"Lv6没有虚假新增出战槽")
        popup.destroy()
    end)
    _G.require=realRequire
    for name,value in pairs(globals) do _G[name]=value end
    if vg then nvgDelete(vg) end
    if ok then print("[expedition_popup_test] ALL PASS assertions="..assertions)
    else print("[FAIL] expedition_popup_test: "..tostring(err)) end
    engine:Exit()
end
