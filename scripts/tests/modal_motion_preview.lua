-- scaffold-2d受控视觉验收：真实UI/结算窗/升级窗，不运行main或读写玩家档。
-- -motion-kind=level|result|tower -motion-time=0.14 以确定时间采样，不依赖帧速。
local nativeRequire,nativeCache=require,cache
local UI=nativeRequire("urhox-libs/UI")
local Surface=nativeRequire("ui.widget.DesignWidgetSurface")
local I18n=nativeRequire("core.I18n")
---@type NVGContextWrapper?
local vg=nil
local kind,elapsed,language="level",.2,"zh_CN"
local popup={}
local frames=0
local function noop() end
local function source(path)
    local file=assert(nativeCache:GetFile(path))
    local lines={}
    while not file:IsEof() do lines[#lines+1]=file:ReadLine() end
    file:Dispose()
    return table.concat(lines,"\n")
end
function Start()
    for _,arg in ipairs(GetArguments()) do
        local value=arg:match("^%-motion%-kind=(.+)$");if value then kind=value end
        value=arg:match("^%-motion%-time=(.+)$");if value then elapsed=tonumber(value) or 0 end
        value=arg:match("^%-motion%-lang=(.+)$");if value then language=value end
    end
    assert(elapsed==elapsed and elapsed>=0 and elapsed<=6)
    assert(kind=="level" or kind=="result" or kind=="tower")
    assert(I18n.set(language) or I18n.get()==language)
    vg=assert(nvgCreate(1));assert(nvgCreateFont(vg,"sans","Fonts/NotoSansCJKkr-Bold.otf")>=0)
    Surface.init()
    local blockers={ ["ui.hud.popup.OfflineRewardPanel"]=true,["ui.hud.popup.UpdateNoticePopup"]=true,
        ["ui.story.gate.DarkTitleScreenGate"]=true,["ui.story.gate.LetterIntro"]=true,
        ["ui.story.gate.IntroCutscene"]=true,["ui.story.ScenarioDialogue"]=true,["ui.dev.CEPanel"]=true }
    local env=setmetatable({}, {__index=_G});env._G=env
    env.File=function() error("preview禁止玩家档") end
    env.require=function(name)
        if blockers[name] then return {isOpen=function() return false end,isActive=function() return false end} end
        if name=="systems.GameSFX" then return {play=noop} end
        if name=="runtime.ClientDispatcher" then return {get=function() return {} end} end
        if name=="core.GameState" then return {getLevel=function() return 30 end,getExp=function() return 0 end} end
        return nativeRequire(name)
    end
    local path=kind=="level" and "ui/hud/popup/LevelUpPopup.lua" or "ui/battle/popup/BattleResultPanel.lua"
    popup=assert(load(source(path),"@modal-motion/production","t",env))()
    popup.init(vg)
    if kind=="level" then popup.show(30,nil,29)
    else
        popup.show({layout=kind=="tower" and "tower" or nil,isWin=true,elapsedSecs=51,floor=12,
            heroStats={ {heroId=1,quality=3,totalDamage=12840}, {heroId=2,quality=4,totalDamage=9870},
                {heroId=3,quality=3,totalDamage=7750} },rewards={}})
    end
    popup.update(elapsed)
    assert(popup.isOpen())
    SubscribeToEvent(vg,"NanoVGRender","HandleModalMotionPreview")
end
function HandleModalMotionPreview()
    local ctx=vg;if not ctx then return end
    local dpr=graphics:GetDPR()
    local w,h=graphics:GetWidth()/dpr,graphics:GetHeight()/dpr
    nvgBeginFrame(ctx,w,h,dpr)
    nvgBeginPath(ctx);nvgRect(ctx,0,0,w,h)
    nvgFillPaint(ctx,nvgLinearGradient(ctx,0,0,w,h,nvgRGBA(28,24,20,255),nvgRGBA(8,9,12,255)))
    nvgFill(ctx)
    popup.draw(ctx,w,h)
    nvgEndFrame(ctx)
    frames=frames+1
    if frames==120 then print("[modal-motion-preview] ALL PASS kind="..kind.." time="..elapsed.." language="..language) end
end
function Stop()
    if popup.destroy then popup.destroy() end
    if popup.resetToDefault then popup.resetToDefault() end
    Surface.shutdown()
    if vg then nvgDelete(vg);vg=nil end
end
