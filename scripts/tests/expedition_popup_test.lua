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
    local blocker = nil
    local blockers = {
        ["ui.hud.popup.OfflineRewardPanel"] = "offline",
        ["ui.hud.popup.UpdateNoticePopup"] = "notice",
        ["ui.story.gate.DarkTitleScreenGate"] = "title",
        ["ui.story.gate.LetterIntro"] = "letter",
        ["ui.story.gate.IntroCutscene"] = "intro",
        ["ui.story.ScenarioDialogue"] = "story",
        ["ui.dev.CEPanel"] = "ce",
    }
    local clock = { elapsedTime = 100 }
    local texts, soundCount, navigations = {}, 0, 0
    local lastButtonClip = nil ---@type table|nil
    local nativeTextBounds = nvgTextBounds
    local I18n = realRequire("core.I18n")
    local originalLanguage = I18n.get()
    I18n.set("zh_CN")
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
            if blockers[name] then
                return { isOpen = function() return blocker == blockers[name] end,
                    isActive = function() return blocker == blockers[name] end }
            end
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
        replace("nvgIntersectScissor", function(_, _, _, width, height)
            if height == 46 then lastButtonClip = { width = width, height = height } end
        end)
        for _, name in ipairs({"nvgBeginPath","nvgRect","nvgRoundedRect","nvgCircle","nvgFill",
            "nvgFillColor","nvgFillPaint","nvgStroke","nvgStrokeColor","nvgStrokeWidth",
            "nvgGlobalAlpha","nvgRotate","nvgTextScaleMode"}) do replace(name,noop) end
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
        local I18n = realRequire("core.I18n")
        popup.show(60, nil, 1)
        for _, language in ipairs({ "zh_TW", "en", "ja", "ko", "zh_CN" }) do
            I18n.set(language)
            draw(1280, 720)
            check(find(I18n.lookup("远征等级提升")), language .. "已打开横卡标题更新")
            check(find(I18n.format("Lv.%d → Lv.%d    远征点上限 +%d", 1, 60, 59)), language .. "跨级动态点数翻译")
            check(find(I18n.format("查看奖励 · %d 项可领", 4)), language .. "可领奖励数量模板翻译")
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 20)
            local buttonWidth = nativeTextBounds(vg, 0, 0, I18n.format("查看奖励 · %d 项可领", 4), nil)
            local emptyWidth = nativeTextBounds(vg, 0, 0, I18n.lookup("查看远征奖励"), nil)
            check(lastButtonClip and math.max(buttonWidth, emptyWidth) + 24 <= lastButtonClip.width,
                language .. "真实字体两种按钮译文均留边且不被裁切")
            check(find(I18n.format("%d 秒后自动关闭 · 点击空白继续", 5)), language .. "倒计时模板翻译")
        end
        for _, name in pairs(blockers) do
            blocker = name
            check(popup.isPresentationBlocked(), name .. "更高层窗口阻塞")
            popup.update(20)
            draw(1280, 720)
            check(#texts == 0 and popup.isOpen(), name .. "隐藏不绘制且不消耗进入或自动关闭计时")
        end
        blocker = nil
        local beforeNoUpdate = popup.getPresentationVersion()
        blocker = "intro"
        draw(1280, 720)
        check(popup.getPresentationVersion() ~= beforeNoUpdate, "开场Update早返时仅draw也作废旧按压")
        blocker = nil
        check(popup.getPresentationVersion() > beforeNoUpdate + 1, "开场结束版本再次更新")
        popup.update(0.4)
        popup.update(4.8)
        draw(1280, 720)
        check(find(I18n.format("%d 秒后自动关闭 · 点击空白继续", 1)), "恢复可见后仍保留真实剩余时间")
        local previousVersion = popup.getPresentationVersion()
        blocker = "story"
        popup.update(20)
        check(popup.getPresentationVersion() ~= previousVersion, "遮挡切换使旧升级按压版本失效")
        check(popup.handleInput(0, 0, 1280, 720) and popup.isOpen(), "遮挡时点击不跳过升级窗")
        blocker = nil
        popup.update(0.21)
        check(popup.isOpen(), "可见倒计时结束只进入退出动画")
        blocker = "offline"
        popup.update(20)
        check(popup.isOpen(), "遮挡期间退出动画也暂停")
        blocker = nil
        popup.update(0.3)
        check(not popup.isOpen(), "可见退出动画完成才关闭")
        check(soundCount == 6, "语言切换或遮挡不重复播放升级音效")
        popup.destroy()
    end)
    _G.require=realRequire
    I18n.set(originalLanguage)
    for name,value in pairs(globals) do _G[name]=value end
    if vg then nvgDelete(vg) end
    if ok then print("[expedition_popup_test] ALL PASS assertions="..assertions)
    else print("[FAIL] expedition_popup_test: "..tostring(err)) end
    engine:Exit()
end
