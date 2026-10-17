-- 结算窗纯表现专项：真实BattleResultPanel/UI树，隔离资源/时间/数据，不启动main。
local TAG = "[result_motion_test]"
local nativeRequire, nativeCache = require, cache
local function source()
    local file = assert(nativeCache:GetFile("ui/battle/popup/BattleResultPanel.lua"))
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
function Start()
    local checks, closes, denied = 0, 0, 0
    local function check(value, why) checks = checks + 1; assert(value, why) end
    local function deny() denied = denied + 1; error("禁止玩家数据、文件及随机访问") end
    local function noop() end
    local stack, current, alphas = {}, {x=0,y=0,sx=1,sy=1,alpha=1}, {}
    local outputs, towerTrees = {}, {}
    local env = setmetatable({ File=deny, FileSystem=deny,
        math=setmetatable({random=deny,randomseed=deny},{__index=math}) }, {__index=_G})
    env._G = env
    local UI = nativeRequire("urhox-libs/UI")
    local surface = nativeRequire("ui.widget.DesignWidgetSurface")
    surface.init()
    env.require = function(name)
        if name == "core.NumberUtil" then return {format=tostring} end
        if name == "ui.widget.ImageCache" then return {init=noop} end
        if name == "core.DrawUtil" then return {drawImageCentered=noop,drawTextStroke=noop} end
        if name == "core.DarkIcon" then return {drawQualityBg=noop} end
        if name == "ui.widget.HeroFrame" then return {draw=noop} end
        if name == "config.ResourceDefs" then return {DEFS={}} end
        if name == "config.HeroConfig" then return {HEROES={}} end
        if name == "core.I18n" or name == "urhox-libs/UI" then return nativeRequire(name) end
        if name == "ui.widget.DesignWidgetSurface" then return {init=surface.init,
            draw=function(root, _, width, height)
                YGNodeCalculateLayout(root.node,width,height,YGDirectionLTR)
                towerTrees[#towerTrees+1]={root=root,x=current.x,y=current.y,sx=current.sx,sy=current.sy,alpha=current.alpha}
            end} end
        error("未声明被测依赖 " .. name)
    end
    env.nvgSave=function() stack[#stack+1]={x=current.x,y=current.y,sx=current.sx,sy=current.sy,alpha=current.alpha} end
    env.nvgRestore=function() current=assert(table.remove(stack),"无对应save") end
    env.nvgTranslate=function(_,x,y) current.x,current.y=current.x+x*current.sx,current.y+y*current.sy end
    env.nvgScale=function(_,x,y) current.sx,current.sy=current.sx*x,current.sy*y end
    env.nvgGlobalAlpha=function(_,value) current.alpha=current.alpha*value; alphas[#alphas+1]=current.alpha end
    env.nvgText=function(_,x,y,text) outputs[#outputs+1]={x=current.x+x*current.sx,y=current.y+y*current.sy,text=text} end
    env.nvgRGBA=function(...) return {...} end
    for _,name in ipairs({"nvgBeginPath","nvgRect","nvgRoundedRect","nvgFillColor","nvgFill","nvgFontFace",
        "nvgFontSize","nvgTextAlign","nvgStroke","nvgStrokeColor","nvgStrokeWidth"}) do env[name]=noop end
    local popup=assert(load(source(),"@result-motion/production","t",env))()
    local function draw(width,height)
        outputs,alphas,towerTrees={},{},{}
        popup.draw({},width,height)
        check(#stack==0 and current.alpha==1 and current.x==0 and current.y==0,"完整恢复宿主状态")
        return alphas[#alphas], outputs[1]
    end
    local ok,caught=xpcall(function()
        popup.init({})
        popup.show({isWin=true,elapsedSecs=51,onClose=function() closes=closes+1 end})
        local first,pos=draw(1280,720)
        check(math.abs(first-.82)<.000001,"首次结算已有可读内容非黑屏")
        local repeatAlpha,repeatPos=draw(1280,720)
        check(repeatAlpha==first and repeatPos.x==pos.x and repeatPos.y==pos.y,"draw不推进渐显或改变锚点")
        popup.update(.14)
        local middle,middlePos=draw(1280,720)
        check(middle>first and middle<1,"真实半程渐显")
        check(middlePos.x==pos.x and middlePos.y==pos.y,"统计和点击位置不随动画移动")
        popup.update(.14)
        local settled=draw(1280,720)
        check(settled==1 and popup.isOpen(),"0.28秒完全落位不自动关闭")
        popup.update(-2);popup.update(0/0);popup.update(math.huge)
        check(draw(1280,720)==1,"非法dt不污染表现")
        check(popup.handleInput(0,0) and closes==1 and not popup.isOpen(),"任意点击仍立即关闭并一次回调")
        popup.close();check(closes==1,"重复关闭不重回调")
        popup.show({layout="tower",isWin=false,floor=7,elapsedSecs=91,onClose=function() closes=closes+1 end})
        local towerFirst=draw(1600,1000)
        check(math.abs(towerFirst-.82)<.000001 and #towerTrees==1,"塔真实UI树首次渐显")
        local tree=towerTrees[1]
        local layout=tree.root:GetAbsoluteLayout()
        check(layout.w==1440 and layout.h==760,"塔专用1440x760画布不变")
        popup.update(.28);check(draw(1600,1000)==1,"塔结束渐显")
        local final=towerTrees[1]
        check(final.x==tree.x and final.y==tree.y and final.sx==tree.sx,"塔fit与内容锚点稳定")
        popup.resetToDefault();popup.update(5)
        check(not popup.isOpen() and closes==1,"硬reset不调用旧业务回调")
        popup.show({onClose=function()
            closes=closes+1;popup.show({layout="tower",floor=9})
        end})
        popup.close();check(popup.isOpen() and closes==2,"同步链播新结算保留")
        check(math.abs(draw(1600,1000)-.82)<.000001,"新段重新入场而非旧时钟")
        -- 按引擎/UI约定模拟乘性alpha，确认模态叠层不覆盖宿主透明度。
        for _,layoutKind in ipairs({"normal","tower"}) do
            popup.show({layout=layoutKind=="tower" and "tower" or nil})
            current.alpha=.5;alphas={}
            popup.draw({},1600,1000)
            check(math.abs(alphas[#alphas]-.41)<.000001 and current.alpha==.5 and #stack==0,
                "渐显乘宿主alpha且完整恢复 "..layoutKind)
            current.alpha=1
        end
        popup.resetToDefault()
        check(denied==0,"无玩家文件或随机访问")
    end,debug.traceback)
    popup.resetToDefault();surface.shutdown()
    print(TAG .. (ok and " ALL PASS" or " FAIL " .. tostring(caught)) .. " assertions=" .. checks)
    engine:Exit()
end
