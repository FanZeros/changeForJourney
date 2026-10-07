-- 专项只读验证；基于 scaffold-2d 的 Start/Stop 生命周期，不初始化游戏/main/真实档。
-- cwd MUST be /home/Maker/tutorial-onboarding-validation-20261006.
-- /home/Maker/resource-dungeon-visual-validation-20261006/.cli/UrhoXRuntime tests/tutorial_focused_onboarding_test.lua
-- -tapcode_dir=/workspace -tool_mode -nosound -graphicsheadless
-- -validate -validate-frames=60 -validate-timeout=45 -validate-output=<isolated cwd>/validate.json
-- 真实 TM/Recovery/Letter/Scenario/Story + 完整只读闭包；其他业务为内存替身。
-- 绘图 spy 是语义/几何记录，不是截图，也不代表真实手机或完整存档验收。
local ROOT, REVIEW = "", ""
for _, arg in ipairs(GetArguments()) do
    local mode=arg:match("^%-onboarding%-review=(.+)$")
    if mode then REVIEW=mode end
    local path = arg:match("^%-tapcode_dir=(.+)$")
    if path then ROOT = path:gsub("/+$", "") end
end
local PROJECT = "/workspace"
local CWD = "/home/Maker/tutorial-onboarding-validation-20261006"
local TAG = "[tutorial_focused_onboarding_test] "
local SOURCE_FILES = {
    ["config.TutorialConfig"] = PROJECT .. "/scripts/config/TutorialConfig.lua",
    ["config.GameConfig"] = PROJECT .. "/scripts/config/GameConfig.lua",
    ["config.ScenarioDialogueConfig"] = PROJECT .. "/scripts/config/ScenarioDialogueConfig.lua",
    ["config.StoryBackgroundConfig"] = PROJECT .. "/scripts/config/StoryBackgroundConfig.lua",
    ["config.HeroAssetUtil"] = PROJECT .. "/scripts/config/HeroAssetUtil.lua",
    ["core.DrawUtil"] = PROJECT .. "/scripts/core/DrawUtil.lua",
    ["core.EventBus"] = PROJECT .. "/scripts/core/EventBus.lua",
    ["core.I18nStory"] = PROJECT .. "/scripts/core/I18nStory.lua",
    ["core.Viewport"] = PROJECT .. "/scripts/core/Viewport.lua",
    ["systems.TutorialManager"] = PROJECT .. "/scripts/systems/TutorialManager.lua",
    ["systems.StoryPlayer"] = PROJECT .. "/scripts/systems/StoryPlayer.lua",
    ["ui.tutorial.TutorialOverlay"] = PROJECT .. "/scripts/ui/tutorial/TutorialOverlay.lua",
    ["ui.tutorial.TutorialPageRecovery"] = PROJECT .. "/scripts/ui/tutorial/TutorialPageRecovery.lua",
    ["ui.story.gate.LetterIntro"] = PROJECT .. "/scripts/ui/story/gate/LetterIntro.lua",
    ["ui.story.StoryDisplay"] = PROJECT .. "/scripts/ui/story/StoryDisplay.lua",
    ["ui.story.ScenarioDialogue"] = PROJECT .. "/scripts/ui/story/ScenarioDialogue.lua",
    ["ui.town.TownScene"] = PROJECT .. "/scripts/ui/town/TownScene.lua",
    ["ui.character.hero.HeroScenario"] = PROJECT .. "/scripts/ui/character/hero/HeroScenario.lua",
    ["boot.StandaloneHorizonInput"] = PROJECT .. "/scripts/boot/StandaloneHorizonInput.lua",
    -- 这三个文件只允许读取/抽取明确完整闭包；禁止 require 或执行完整模块。
    ["boot.StandaloneHorizon"] = PROJECT .. "/scripts/boot/StandaloneHorizon.lua",
    ["boot.StandaloneBoot"] = PROJECT .. "/scripts/boot/StandaloneBoot.lua",
    ["boot.Standalone"] = PROJECT .. "/scripts/boot/Standalone.lua",
}
local FRAGMENTS_ONLY = { ["boot.StandaloneHorizon"]=true, ["boot.StandaloneBoot"]=true, ["boot.Standalone"]=true }
local nativeFile, nativeCache = File, cache
local sources, reads, contexts = {}, {}, {} ---@type any
local checks, groups, failures = 0, 0, 0
local loadedBefore, globalsBefore = {}, {} ---@type any
for k,v in pairs(package.loaded) do loadedBefore[k]=v end
for k,v in pairs(_G) do globalsBefore[k]=v end
local function check(ok, label) checks=checks+1; assert(ok,label) end
local function eq(a,b,label) check(a==b,label .. " actual=" .. tostring(a) .. " expected=" .. tostring(b)) end
local function near(a,b,label) check(type(a)=="number" and math.abs(a-b)<0.00001,label) end
local function copy(v)
    if type(v)~="table" then return v end
    local out={}; for k,x in pairs(v) do out[k]=copy(x) end; return out
end
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function noop() end
local function source(name)
    local path=assert(SOURCE_FILES[name],"source denied " .. tostring(name))
    if sources[name] then return sources[name] end
    assert(ROOT==PROJECT,"unexpected project root")
    assert(path:sub(1,#PROJECT+9)==PROJECT .. "/scripts/" and path:sub(-4)==".lua"
        and not path:find("..",1,true),"fixed absolute Lua source only")
    -- 绝对白名单仅作源码身份；宿主cache只读scripts资源根下的相对键，不开放给生产env。
    local resource=path:sub(#PROJECT+10)
    local f=assert(nativeCache:GetFile(resource),"source cache File unavailable " .. resource)
    local ok,text=pcall(function()
        assert(f:IsOpen(),"source open failed " .. resource)
        assert(f:GetMode()==FILE_READ,"source must be read-only " .. resource)
        local lines={}; while not f:IsEof() do lines[#lines+1]=f:ReadLine() end
        return table.concat(lines,"\n")
    end)
    f:Dispose(); assert(ok,text)
    sources[name]=text; reads[#reads+1]=resource; return text
end
local function section(name,first,last)
    local text=source(name)
    local a=assert(text:find(first,1,true),"source boundary missing " .. name .. " " .. first)
    local b=assert(text:find(last,a+#first,true),"source end missing " .. name .. " " .. last)
    return text:sub(a,b-1)
end
local function compile(text,name,env)
    local chunk,why=load(text,"@" .. name,"t",env); assert(chunk,why); return chunk()
end
local PAGE_PATHS = {
    "ui.hud.TopBar", "ui.hud.BottomNav", "ui.battle.scene.BattleScene", "ui.character.panel.CharacterPanel",
    "ui.dev.CEPanel", "ui.character.hero.HeroRosterPanel", "ui.hud.popup.RewardPopup",
    "ui.blacksmith.BlacksmithPage", "ui.church.ChurchPage", "ui.church.talent.TalentPage", "ui.tavern.TavernPage",
    "ui.market.MarketPage", "ui.dungeon.DungeonBattleScene", "ui.tower.TowerBattleScene", "ui.dungeon.DungeonPage",
    "ui.backpack.BackpackPanel", "ui.loot.LootBox", "ui.loot.LootBoxPage", "ui.story.task.TaskPage",
    "ui.hud.popup.LevelUpPopup", "ui.hud.popup.OfflineRewardPanel", "ui.hud.popup.UpdateNoticePopup",
    "ui.hud.popup.PlayerInfoPanel", "ui.story.gate.StartScreen", "ui.story.gate.DarkTitleScreenGate",
    "ui.battle.tri.BattleTriPage", "ui.battle.stage.SweepDialog", "ui.battle.popup.DamageStatsPanel",
    "ui.battle.stage.StageSelectDialog", "ui.battle.popup.TerminalConfirmDialog", "ui.story.gate.IntroCutscene",
    "ui.character.detail.CharacterDetail", "ui.character.equip.EquipmentBag", "ui.character.EquipCrossDrag",
    "ui.character.equip.EquipmentDetail", "ui.tavern.TargetRecruitPanel", "ui.tavern.TavernPopups",
}
local NVG_NOOPS = {
    "nvgStrokeColor","nvgStrokeWidth","nvgStroke","nvgFontFace","nvgTextLineHeight","nvgMoveTo","nvgLineTo",
    "nvgClosePath","nvgLineCap","nvgLineJoin","nvgShapeAntiAlias","nvgGlobalCompositeOperation",
    "nvgGlobalCompositeBlendFuncSeparate","nvgSkewX","nvgResetScissor","nvgScissor","nvgIntersectScissor",
}
local HANDLERS = {
    HandleMouseButtonDownHorizon=true, HandleMouseButtonUpHorizon=true, HandleMouseMoveHorizon=true,
    HandleEquipmentHoverTickHorizon=true, HandleTouchBeginHorizon=true, HandleTouchEndHorizon=true,
    HandleTouchMoveHorizon=true, HandleMouseWheelHorizon=true,
}
---@return any
local function newContext()
    local c={ env={}, modules={}, loading={}, denied={}, calls={}, draws={}, texts={}, loads={}, views={},
        handles={}, nextHandle=0, clock={elapsedTime=100}, cursor={x=0,y=0}, font=20, align=0,
        transform={tx=0,ty=0,sx=1,sy=1}, stack={}, saved={}, flushes=0, persists=0, grants=0,
        stateUpdates=0, notices={}, actions={}, shown={}, pending={}, follow={}, nav=3, team=1, heroId=1,
        memory={session={introCompleted=true,initialHeroId=1,claimedScenarios={},
            tutorialProgress={version=1,completed={},queue={}}}, heroes={roster={[1]={level=1}},deployed={1}},
            equipment={equipped={},inventory={}},battle={maxStageId=106,clearedStages={}}},
        rt={logicalW=1920,logicalH=1080,windowW=1920,windowH=1080,DESIGN_W=1080,DESIGN_H=2400,
            dpr=1,frameScale=1,frameOx=0,frameOy=0,bootReady_=true},
    } ---@type any
    contexts[#contexts+1]=c
    local e=c.env
    local function deny(name) c.denied[#c.denied+1]=name; error("isolated test denies " .. tostring(name)) end
    c.deny=deny
    local function blocked(name)
        return setmetatable({}, {__index=function(_,key) return deny(name .. "." .. tostring(key)) end,
            __newindex=function(_,key) return deny(name .. "." .. tostring(key)) end})
    end
    local function mock(name,fields)
        c.modules[name]=setmetatable(fields,{__index=function(_,key) return deny("unknown method " .. name .. "." .. tostring(key)) end})
        return c.modules[name]
    end
    c.mock=mock
    c.record=function(name,x,y)
        c.calls[name]=(c.calls[name] or 0)+1; c.draws[#c.draws+1]={kind=name,x=x,y=y}
    end
    for _,key in ipairs({"assert","error","ipairs","pairs","next","pcall","xpcall","select","tonumber",
        "tostring","type","setmetatable","getmetatable","rawget","rawset","rawequal"}) do e[key]=_G[key] end
    e.math,e.string,e.table,e.utf8=copy(math),copy(string),copy(table),copy(utf8)
    e.math.randomseed=function() return deny("global RNG seed") end
    e.math.random=function() return 0.5 end
    e._G,e.time=e,c.clock; e.print=function(...) print(TAG .. "production " .. table.concat({...}," ")) end
    for k,v in pairs(_G) do if type(k)=="string" and (k:match("^NVG_") or k:match("^MOUSEB_")) then e[k]=v end end
    e.FILE_READ,e.FILE_WRITE=FILE_READ,FILE_WRITE
    e.File=function() return deny("File any path/mode") end
    for _,key in ipairs({"io","os","package","debug","cache","fileSystem","engine","network","clientCloud","serverCloud"}) do e[key]=blocked(key) end
    for _,key in ipairs({"load","loadfile","dofile","GetFileSystem","GetEngine","SubscribeToEvent","SendEvent"}) do e[key]=function() return deny(key) end end
    e.cjson={encode=cjson.encode,decode=cjson.decode}
    e.input={GetMousePosition=function() return c.cursor end}
    e.H_ox,e.H_oy,e.H_s,e.H_skipDone,e.H_SKIP_START,e.H_SEAM_BACK,e.H_TRI_L0=0,0,1,false,false,false,false
    e.H_focusPanel,e.H_lastPanel="center","center"
    e.nvgCreateImage=function(_,path)
        assert(type(path)=="string" and path:sub(1,6)=="image/" and not path:find("..",1,true),"image spy path invalid")
        local h=c.nextHandle; c.nextHandle=h+1; c.handles[h]=path; c.loads[#c.loads+1]=path; return h
    end
    e.nvgImageSize=function() return 1920,1080 end
    e.nvgRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end
    e.nvgFontSize=function(_,font) c.font=font end
    e.nvgTextAlign=function(_,align) c.align=align end
    e.nvgTextBounds=function(_,_,_,text)
        local width=0; for _,cp in utf8.codes(text) do width=width+(cp<128 and c.font*0.55 or c.font) end
        return width
    end
    e.nvgText=function(_,x,y,text)
        local t=c.transform
        c.texts[#c.texts+1]={x=x,y=y,text=text,font=c.font,align=c.align,width=e.nvgTextBounds(nil,0,0,text),
            px=t.tx+x*t.sx,py=t.ty+y*t.sy,sx=t.sx,sy=t.sy}
        return 0
    end
    e.nvgSave=function() c.stack[#c.stack+1]={transform=copy(c.transform),font=c.font,align=c.align} end
    e.nvgRestore=function()
        local s=assert(table.remove(c.stack),"unbalanced nvgRestore")
        c.transform,c.font,c.align=s.transform,s.font,s.align
    end
    e.nvgTranslate=function(_,x,y) local t=c.transform; t.tx,t.ty=t.tx+x*t.sx,t.ty+y*t.sy end
    e.nvgScale=function(_,x,y) local t=c.transform; t.sx,t.sy=t.sx*x,t.sy*y end
    e.nvgResetTransform=function() c.transform={tx=0,ty=0,sx=1,sy=1} end
    e.nvgBeginPath=function() c.shape=nil end
    local function rect(kind,_,x,y,w,h)
        c.shape={kind=kind,x=x,y=y,w=w,h=h}; c.draws[#c.draws+1]=copy(c.shape)
    end
    e.nvgRect=function(...) rect("rect",...) end
    e.nvgRoundedRect=function(...) rect("rounded",...) end
    e.nvgFillColor=function(_,color) c.color=color end
    e.nvgFillPaint=function(_,paint) c.paint=paint end
    e.nvgFill=function() c.draws[#c.draws+1]={kind="fill",shape=copy(c.shape),color=copy(c.color)} end
    e.nvgImagePattern=function(_,x,y,w,h,_,handle,alpha)
        c.draws[#c.draws+1]={kind="image",path=c.handles[handle],x=x,y=y,w=w,h=h,alpha=alpha}; return {}
    end
    e.nvgImagePatternTinted=function(_,x,y,w,h,angle,handle,color)
        return e.nvgImagePattern(nil,x,y,w,h,angle,handle,color.a/255)
    end
    e.nvgPathWinding=function(_,direction)
        assert(c.shape and c.shape.kind=="rounded","hole must follow rounded target")
        assert(direction==NVG_HOLE,"expected NVG_HOLE")
        c.draws[#c.draws+1]={kind="hole",shape=copy(c.shape)}
    end
    for _,key in ipairs(NVG_NOOPS) do e[key]=noop end
    mock("core.BattleLayout",{})
    mock("core.GameState",{getLevel=function() return 50 end})
    mock("core.DarkIcon",{draw=noop,drawNine=noop})
    mock("core.HorizonBg",{draw=noop})
    mock("config.ExpTable",{CHURCH_UNLOCK_LEVEL=30,isBuildingUnlocked=function() return true end,getBuildingUnlockLevel=function() return 30 end})
    mock("config.StageConfig",{isTerminalTemple=function(id) return id%1000==999 end,
        getStage=function(id) return {chapter=math.floor(id/100),id=id} end})
    mock("config.HeroConfig",{get=function(id)
        return {name=({[1]="大狗嚼",[2]="黄桃龙",[3]="叮咚鸡"})[id] or ("hero" .. id)} end})
    mock("core.I18n",{get=function() return c.lang or "zh_CN" end,lookup=function(s)
        if c.lang then return c.require("core.I18nStory").lookup(s,c.lang) or s end
        return s
    end,
        displayBounds=e.nvgTextBounds,displayText=e.nvgText})
    mock("systems.ButtonFeedback",{begin=function() return false end,finish=noop,trigger=function(k) c.record(k) end})
    mock("ui.widget.HeroFrame",{draw=noop})
    mock("runtime.ClientDispatcher",{get=function(key) return c.memory[key] end,
        handleStateUpdate=function(json)
            local data=e.cjson.decode(json); c.stateUpdates=c.stateUpdates+1
            for k,v in pairs(data.modules) do c.memory[k]=copy(v) end
        end})
    -- 仅内存Flush替身；真实StandaloneSave文件绝不在源码白名单中。
    mock("boot.StandaloneSave",{Flush=function()
        c.flushes=c.flushes+1; c.saved[#c.saved+1]=copy(c.memory); return true end})
    for _,name in ipairs(PAGE_PATHS) do
        local state={open=false,opens=0,closes=0,tab="",closeTime=0,busy=false,confirm=false}
        c.views[name]=state
        local methods={
            isOpen=function() return state.open end,isActive=function() return state.open end,
            isVisible=function() return state.open end,isPresentationBlocked=function() return false end,
            open=function(_,tab) state.open,state.tab,state.closeTime=true,tab or state.tab,0; state.opens=state.opens+1 end,
            init=noop,close=function() state.open=false; state.closes=state.closes+1 end,
            forceClose=function() state.open=false; state.closes=state.closes+1 end,
            getSeamAnim=function() return 100,state.closeTime,0.45,0.38 end,
            isLeftMode=function() return true end,isRecruitBusy=function() return state.busy or state.confirm end,
            isRecruitConfirmOpen=function() return state.confirm end,isEquipTab=function() return state.tab=="equip" end,
            getHeroId=function() return c.heroId end,getHorizonWidthScale=function() return 1 end,
            hasAnyChurchBadge=function() return false end,hasAnyUnusedTalent=function() return false end,
            canEnhanceAny=function() return false end,isDraggingCard=function() return false end,
            isDetailOpen=function() return false end,isArmed=function() return false end,
            isPinned=function() return false end,isCompactCorner=function() return false end,
            containsPoint=function() return false end,peekEquipAt=function() return nil end,
            currentPanel=function() return "left" end,currentRowTag=function() return nil end,
            hasPendingBattleRewards=function() return state.pending==true end,
            getSelectedIndex=function() return c.nav end,setSelectedIndex=function(i) c.nav=i end,setTabLocked=noop,
            getTeamSlotsData=function() return {{state="occupied",heroId=1},
                {state="empty"},{state="empty"},{state="empty"}} end,
            getTeamSlotLayout=function() return {1,0,0,0} end,getActiveTeamIdx=function() return c.team end,
            isHeroesDataApplied=function() return true end,
            isOwned=function(id) local hero=c.memory.heroes.roster[id] or c.memory.heroes.roster[tostring(id)]
                return hero~=nil and hero.level~=nil end,
            prepareTutorial=function() local changed=not state.open; state.open=true; state.tab="recruit"; return changed end,
            ensureTutorialEquipment=function(_,slot)
                local changed=not state.open or state.tab~=slot; state.open,state.tab=true,slot; return changed end,
            hitTestAvatar=function() return false end,getCount=function() return 0 end,drawRates=noop,
            hasClaimable=function() return false end,cancel=noop,
        }
        for _,key in ipairs({"handleInput","handleDown","handleUp","handleWheel","handleDragBegin","handleDragMove",
            "handleDragEnd","handleHover","handleScroll","handleRightClick","handleNavigationTap","handleEquipmentSlotTap"}) do
            methods[key]=function(x,y) c.record(name .. "." .. key,x,y); return false end
        end
        mock(name,methods)
    end
    c.modules["ui.battle.tri.BattleTriPage"].getTeamStageId=function(team)
        assert(team==1,"onboarding fixture only reads team1 stage")
        return 101
    end
    mock("config.DungeonConfig",{decodeStageId=function(id)
        assert(id==101,"onboarding fixture only decodes main stage101")
        return nil
    end})
    c.modules["ui.character.panel.CharacterPanel"].prepareTutorial=function() c.team=1; c.record("roster.prepare") end
    c.modules["ui.character.detail.CharacterDetail"].open=function(id,tab)
        c.heroId=id; local s=c.views["ui.character.detail.CharacterDetail"]
        s.open,s.tab,s.closeTime=true,tab,0; s.opens=s.opens+1
    end
    c.modules["ui.hud.TopBar"].handleInput=function() return false end
    local gesture={bind=function() return nil end,down=function() return false end,up=function() return false end,
        move=function() return false end,hover=noop,cancel=noop}
    mock("boot.ArtifactGesture",gesture)
    mock("boot.BattleRewardOverlay",{isBlocked=function() return c.rewardBlocked==true end})
    e.require=function(name)
        if FRAGMENTS_ONLY[name] then return deny("whole Boot/module " .. name) end
        if c.modules[name]~=nil then return c.modules[name] end
        if not SOURCE_FILES[name] then return deny("unknown require " .. tostring(name)) end
        if c.loading[name] then return deny("circular require " .. name) end
        c.loading[name]=true
        local ok,value=pcall(compile,source(name),SOURCE_FILES[name],e)
        c.loading[name]=nil; if not ok then error(value) end
        c.modules[name]=value; return value
    end
    setmetatable(e,{__index=function(_,k) return deny("unknown global " .. tostring(k)) end,
        __newindex=function(t,k,v)
            if not HANDLERS[k] then return deny("unknown global assignment " .. tostring(k)) end
            rawset(t,k,v)
        end})
    c.require=e.require
    c.store={Get=function(key) return c.memory[key] end}
    c.persist=function(progress)
        c.persists=c.persists+1; c.memory.session.tutorialProgress=copy(progress)
        c.saved[#c.saved+1]=copy(c.memory)
    end
    c.vg={}; c.rt.vg=c.vg
    c.tm=c.require("systems.TutorialManager")
    c.tm.init(c.vg,c.store,c.persist); c.tm.update(0)
    c.letter=c.require("ui.story.gate.LetterIntro"); c.letter.init(c.vg)
    c.scenario=c.require("ui.story.ScenarioDialogue"); c.scenario.init(c.vg,nil)
    c.config=c.require("config.ScenarioDialogueConfig")
    c.configBefore=copy(c.config)
    local realShow=c.scenario.show
    c.scenario.show=function(cfg) c.shown[#c.shown+1]=cfg; realShow(cfg) end
    c.tick=function(dt)
        c.clock.elapsedTime=c.clock.elapsedTime+dt; c.tm.update(dt)
    end
    c.clearDraw=function() c.draws,c.texts={},{}; e.nvgResetTransform() end
    c.beginGroup=function(id)
        c.memory.session.tutorialProgress={version=1,completed={},group=id,step=1,newHeroId=1}
        c.tm.init(c.vg,c.store,c.persist); c.tick(0); c.tick(0.6)
    end
    return c
end
local function countCalls(c,key) return c.calls[key] or 0 end
local function inScreen(r,w,h,label)
    check(r.w>0 and r.h>0,label .. " positive")
    check(r.cx-r.w/2>=-0.001 and r.cx+r.w/2<=w+0.001,label .. " X bounds")
    check(r.cy-r.h/2>=-0.001 and r.cy+r.h/2<=h+0.001,label .. " Y bounds")
end
local function overlaps(a,b)
    return b and math.abs(a.cx-b.cx)<(a.w+b.w)/2 and math.abs(a.cy-b.cy)<(a.h+b.h)/2
end
local function auditContext(c)
    eq(#c.denied,0,"production made no forbidden access")
    check(same(c.config,c.configBefore),"source dialogue config unchanged")
    eq(#c.stack,0,"drawing save/restore balanced")
end
local function runCase(label,fn)
    groups=groups+1
    local ok,why=pcall(fn)
    if ok then print(TAG .. "[PASS] " .. label)
    else failures=failures+1; local text=TAG .. "[FAIL] " .. label .. " " .. tostring(why)
        print(text); log:Write(LOG_ERROR,text)
    end
end
local function safetyCases()
    local c=newContext()
    local probes={
        function() c.require("main") end,function() c.require("boot.Standalone") end,
        function() c.require("boot.StandaloneBoot") end,function() c.require("boot.StandaloneHorizon") end,
        function() c.require("core.PlayerStore") end,function() c.require("runtime.GameAction") end,
        function() c.require("runtime.LocalActionBridge") end,function() c.require("unknown.Module") end,
        function() c.env.File("player_save.json",FILE_READ) end,function() c.env.File("player_save.json",FILE_WRITE) end,
        function() c.env.dofile("main.lua") end,function() c.env.loadfile("main.lua") end,
        function() c.env.load("return _G") end,function() c.env.clientCloud:Set("x",1) end,
        function() c.env.serverCloud:Set("x",1) end,function() c.env.network:Connect() end,
        function() c.env.fileSystem:CreateDir("saves") end,function() c.env.cache:GetFile("save.json") end,
        function() c.env.require("boot.StandaloneSave").Load() end,
        function() return c.env.unknownGlobal end,function() c.env.package.loaded["main"]=true end,
    }
    for i,probe in ipairs(probes) do local before=#c.denied; local ok=pcall(probe)
        check(not ok,"danger probe rejects " .. i); eq(#c.denied,before+1,"probe visible audit " .. i)
    end
    c.denied={}
    local other=newContext()
    check(other.tm~=c.tm and other.config~=c.config and other.env~=c.env,"module cache/context isolated")
    local progress=c.tm.getProgress(); progress.completed["4"]=true; progress.queue[1]=8
    check(not c.tm.isGroupCompleted(4) and #c.tm.getProgress().queue==0,"snapshot deepcopy owns progress")
    c.beginGroup(4); local saved=copy(c.saved[#c.saved]); c.tm.notifyEvent("enter_tavern")
    check(same(c.saved[#c.saved-1],saved),"persist history detached from later mutation")
    auditContext(c); auditContext(other)
end
local function targetCases()
    for _,sid in ipairs({20,21,22}) do
        local c=newContext(); local tm=c.tm
        tm.onScenarioClaimed(sid); tm.onScenarioClaimed(sid)
        eq(#tm.getProgress().queue,1,"claim queues once " .. sid)
        check(not tm.canPlayPendingStory(),"queued tutorial beats pending story")
        c.tick(0.15); check(not tm.isActive(),"does not steal quiet0.25 window")
        c.tick(0.11); eq(tm.getCurrentGroup(),4,"all branches activate group4")
        c.tick(0.6)
        eq(tm.getCurrentHighlight(),"building_tavern","explicit building target replaces blank band")
        local cfg=c.require("config.TutorialConfig")[4].steps[1]
        eq(cfg.advanceOn,"enter_tavern","business success, not click")
        eq(cfg.pointerTarget,true,"event step still gates pointer")
        tm.registerHotspot("building_tavern",832,1400,397,387,"left")
        local hs={cx=300,cy=300,w=120,h=90}; tm.setOverlayRect(960,540,hs)
        for _,point in ipairs({{300,30},{600,300},{363,300},{0,0}}) do
            local before=c.persists
            check(not tm.canPointerStart(point[1],point[2]),"blank/non-target/halo down blocked")
            check(tm.handleScreenClick(point[1],point[2]),"non-target up consumed")
            eq(c.persists,before,"wrong click never persisted progress")
            check(not tm.isGroupCompleted(4),"wrong click never success")
        end
        check(tm.handleClick(832,1400,"right"),"same design coords wrong panel blocked")
        check(not tm.handleClick(832,1400,"left"),"actual left building forwards, not advance")
        check(tm.canPointerStart(300,300),"actual screen target allowed")
        local before=c.persists
        check(not tm.handleScreenClick(300,300),"target click forwards to business")
        eq(c.persists,before,"click is not successful open")
        eq(tm.getProgress().step,1,"target click stays event step")
        tm.notifyEvent("enter_tavern_failed"); check(not tm.isGroupCompleted(4),"failed open never finishes")
        tm.notifyEvent("enter_tavern"); check(tm.isGroupCompleted(4),"success completes")
        eq(c.persists,before+1,"success persisted once")
        tm.notifyEvent("enter_tavern"); tm.skipCurrentGroup(); eq(c.persists,before+1,"repeat finish/skip inert")
        check(not tm.canPlayPendingStory(),"out fade still blocks ordinary story")
        c.tick(0.19); check(not tm.canPlayPendingStory(),"0.19 fade blocks")
        c.tick(0.02); check(tm.canPlayPendingStory(),"finished fade releases story")
        auditContext(c)
    end
end
local function queueRecoveryCases()
    local c=newContext(); local tm=c.tm
    c.views["ui.hud.popup.RewardPopup"].open=true
    tm.onScenarioClaimed(20); tm.onScenarioClaimed(31); tm.onScenarioClaimed(31)
    c.tick(20); check(not tm.isActive() and #tm.getProgress().queue==2,"reward has queue priority")
    check(not tm.canPlayPendingStory(),"reward-hidden tutorial queue cannot deadlock by story steal")
    c.views["ui.hud.popup.RewardPopup"].open=false
    c.tick(0.15); check(not tm.isActive(),"post reward quiet window")
    c.views["ui.hud.popup.OfflineRewardPanel"].open=true; c.tick(1)
    c.views["ui.hud.popup.OfflineRewardPanel"].open=false; c.tick(0.15)
    check(not tm.isActive(),"priority interruption resets quiet window")
    c.tick(0.11); eq(tm.getCurrentGroup(),4,"queue order4 before8")
    tm.skipCurrentGroup(); c.tick(0.3)
    check(not tm.canPlayPendingStory(),"queue8 still beats ordinary story after fade")
    tm.init(c.vg,c.store,c.persist); c.tick(0.15)
    check(not tm.isActive() and #tm.getProgress().queue==1,"readback keeps queue and quiet window")
    c.tick(0.11); eq(tm.getCurrentGroup(),8,"restored queue starts once")
    c.tick(0.6); local opens=c.views["ui.tavern.TavernPage"].opens
    c.tick(1); c.tick(1); eq(c.views["ui.tavern.TavernPage"].opens,opens,"recovery stable no repeated open")
    tm.notifyEvent("gacha10_complete"); check(not tm.isGroupCompleted(8),"completion before actual started is not current invisible event")
    tm.notifyEvent("gacha10_started"); tm.notifyEvent("gacha10_failed")
    eq(tm.getCurrentHighlight(),"tavern_btn_gacha10","failed retry restored")
    tm.notifyEvent("gacha10_complete"); check(not tm.isGroupCompleted(8),"failed then stale complete not success")
    tm.notifyEvent("gacha10_started"); tm.notifyEvent("gacha10_complete"); c.tick(0.3)
    check(tm.isGroupCompleted(8) and not tm.isActive(),"real started/completed finishes once")
    auditContext(c)
    local r=newContext(); r.beginGroup(4)
    local recovery=r.require("ui.tutorial.TutorialPageRecovery")
    local before=copy(r.memory)
    for _,path in ipairs({"ui.market.MarketPage","ui.tavern.TavernPage","ui.character.detail.CharacterDetail"}) do r.views[path].open=true end
    check(recovery.prepare(r.vg,r.store,"building_tavern",1,true),"recovery closes covering pages")
    check(not recovery.prepare(r.vg,r.store,"building_tavern",1,false),"stable recovery idempotent")
    check(not r.tm.isGroupCompleted(4) and same(r.memory,before),"recovery only view, no success/ledger mutation")
    eq(#r.actions,0,"recovery sends no recruit/equip/claim action")
    for _,path in ipairs({"ui.hud.popup.OfflineRewardPanel","ui.hud.popup.LevelUpPopup","ui.hud.popup.UpdateNoticePopup",
        "ui.story.gate.DarkTitleScreenGate","ui.story.gate.IntroCutscene","ui.dungeon.DungeonBattleScene","ui.tower.TowerBattleScene"}) do
        r.views[path].open=true; r.tick(2); check(not r.tm.isInputActive(),"high priority unblocked " .. path)
        check(r.tm.canPointerStart(0,0) and not r.tm.handleScreenClick(0,0),"hidden tutorial input yields")
        r.views[path].open=false
    end
    r.letter.start(nil,{compact=true}); r.tick(1)
    check(not r.tm.isInputActive(),"real Letter active blocks tutorial"); r.letter.reset()
    auditContext(r)
end
local function finishDialogue(c)
    local _,total=c.scenario.getProgress()
    for _=1,total do c.scenario.update(100); c.scenario.advance() end
    if c.scenario.isActive() then c.scenario.update(0.31) end
end
local function letterCases()
    local FULL={
        "致第三十七任远征长：","拆开这封信时，我已经荣休了。","公会管这叫交接。我管这叫甩锅。",
        "帽子、印鉴、名册，都在桌上。","塔底下的山海怪不讲道理，但它们会排队上门。",
        "门外有三条吵闹的命。","狗会咬，龙会烧，鸡会敲铃。","先听他们把话说完，再出门。",
        "公会不需要英雄。","需要一个肯签字的傻子。","——第三十六任，你的外祖父",
    }
    local BRIEF={"致第三十七任远征长：","帽子、印鉴、名册都在桌上，三位伙伴已在门外等你。",
        "先带队出门，路上的故事，我们稍后再说。"}
    for _,compact in ipairs({false,true}) do
        local c=newContext(); local letter=c.letter; local done=0
        letter.start(function() done=done+1 end,compact and {compact=true} or nil)
        letter.start(function() done=done+100 end,{compact=not compact})
        for _=1,(compact and 1 or 7) do letter.handleTap() end
        for _,size in ipairs({{1920,1080},{1280,720},{960,540},{844,390}}) do
            c.clearDraw(); letter.draw(c.vg,size[1],size[2])
            local body={}; for _,t in ipairs(c.texts) do if not t.text:find("·",1,true) then body[#body+1]=t.text end end
            local text=table.concat(body,"")
            for _,want in ipairs(compact and BRIEF or FULL) do check(text:find(want,1,true)~=nil,"complete letter unit visible " .. want) end
            check(not text:find(compact and "先听他们把话说完，再出门。" or "先带队出门，路上的故事",1,true),"mode separation no content carryover")
            for _,t in ipairs(c.texts) do
                local x0=t.x; if t.align & NVG_ALIGN_RIGHT~=0 then x0=x0-t.width
                elseif t.align & NVG_ALIGN_CENTER~=0 then x0=x0-t.width/2 end
                check(x0>=-0.001 and x0+t.width<=size[1]+0.001,"letter text horizontal bounds")
                check(t.y>=0 and t.y+t.font<=size[2]+0.001,"letter text vertical bounds")
            end
        end
        for _=1,12 do letter.handleTap() end
        eq(done,0,"rapid clicks finish only in update")
        letter.update(0); eq(done,1,"fast finish callback once")
        letter.update(10); letter.handleTap(); eq(done,1,"after finished callback inert")
        letter.start(function() done=done+1 end,compact and {compact=true} or nil)
        letter.reset(); letter.handleTap(); letter.update(100); eq(done,1,"reset cancels callback")
        letter.start(function() done=done+1 end,compact and {compact=true} or nil)
        local elapsed=0
        while letter.isOpen() and elapsed<30 do letter.update(0.05); elapsed=elapsed+0.05 end
        check(not letter.isOpen() and done==2,"natural completion exactly once")
        check(compact and elapsed<4 or not compact and elapsed>12,"BRIEF natural shorter; FULL default unchanged")
        eq(#c.loads,1,"desk image cache once across modes and resets")
        auditContext(c)
    end
    local c=newContext(); local finished=0
    for _,cfg in ipairs({c.config.OPENING,c.config.OPENING_JOINS[1],c.config.SCENARIO_31}) do
        local snapshot=copy(cfg)
        c.scenario.show({mode=cfg.mode,steps=cfg.steps,background=cfg.background,backgroundIsCg=cfg.backgroundIsCg,
            onFinish=function() finished=finished+1 end})
        finishDialogue(c); local count=finished; c.scenario.skip(); c.scenario.advance(); c.scenario.update(10)
        eq(finished,count,"Scenario natural/duplicate finish once")
        c.scenario.show({mode=cfg.mode,steps=cfg.steps,onFinish=function() finished=finished+1 end})
        c.scenario.skip(); c.scenario.skip(); eq(finished,count+1,"Scenario repeated skip once")
        c.scenario.show({mode=cfg.mode,steps=cfg.steps,onFinish=function() finished=finished+1 end})
        c.scenario.reset(); c.scenario.skip(); c.scenario.update(100); eq(finished,count+1,"Scenario reset no completion")
        check(same(cfg,snapshot),"natural/skip/reset keep config")
    end
    eq(#c.config.OPENING.steps,4,"original OPENING4 lines")
    eq(#c.config.OPENING_JOINS,3,"original joins3 configs")
    local steps=0; for _,cfg in ipairs(c.config.OPENING_JOINS) do steps=steps+#cfg.steps end
    eq(steps,6,"original joins6 lines, not cut")
    auditContext(c)
end
local function projectFunction(c)
    local e=c.env
    for name,value in pairs({TutorialManager=c.tm,Viewport=c.require("core.Viewport"),ScenarioDialogue=c.scenario,
        LetterIntro=c.letter,IntroCutscene=c.modules["ui.story.gate.IntroCutscene"],
        DarkTitleScreen=c.modules["ui.story.gate.DarkTitleScreenGate"],DungeonBattleScene=c.modules["ui.dungeon.DungeonBattleScene"],
        TowerBattleScene=c.modules["ui.tower.TowerBattleScene"],BottomNav=c.modules["ui.hud.BottomNav"],
        logicalW=function() return c.rt.logicalW end,logicalH=function() return c.rt.logicalH end,
        DESIGN_W=function() return 1080 end,DESIGN_H=function() return 2400 end,vg=function() return c.vg end,
        applyFrame=function() e.nvgTranslate(c.vg,c.rt.frameOx,c.rt.frameOy); e.nvgScale(c.vg,c.rt.frameScale,c.rt.frameScale) end,
    }) do rawset(e,name,value) end
    return compile(section("boot.StandaloneHorizon","local function HorizonDrawTutorialOverlay()","\n--- [弹窗聚焦]")
        .. "\nreturn HorizonDrawTutorialOverlay",SOURCE_FILES["boot.StandaloneHorizon"],e)
end
local function bindInput(c)
    local vp=c.require("core.Viewport"); local rt=c.rt
    local gesture={hasPress=function() return false end,reset=noop,cancel=noop,cancelIfBlocked=noop}
    local offline={hasPress=function() return false end,cancel=noop,handleWheel=function() return false end,
        toDesign=function(x,y) return x,y end}
    local ctx={RT=rt,Viewport=vp,OfflineRewardOverlay=offline,vg=function() return c.vg end,
        logicalW=function() return rt.logicalW end,logicalH=function() return rt.logicalH end,
        windowW=function() return rt.windowW end,windowH=function() return rt.windowH end,
        dpr=function() return rt.dpr end,DESIGN_W=function() return 1080 end,DESIGN_H=function() return 2400 end,
        bootReady_=function() return true end,toDesign=function(x,y) return (x-rt.frameOx)/rt.frameScale,(y-rt.frameOy)/rt.frameScale end,
        talentPageUsesWideLayout=function() return false end,syncTalentPageLayout=noop,
        talentPageRightEdge=function() return 0 end,equipOverlayDesign=function() return nil end,
        seamHitAt=function() return nil end,seamInputBlocked=function() return true end,seamGesture=gesture,
    }
    c.require("boot.StandaloneHorizonInput").bind(ctx)
    c.pointer=function(x,y)
        c.cursor.x=(rt.frameOx+x*rt.frameScale)*rt.dpr; c.cursor.y=(rt.frameOy+y*rt.frameScale)*rt.dpr
    end
    c.invoke=function(name,event) c.env[name](name,event or {Button={GetInt=function() return MOUSEB_LEFT end}}) end
    c.click=function(x,y)
        c.pointer(x,y); c.invoke("HandleMouseButtonDownHorizon"); c.clock.elapsedTime=c.clock.elapsedTime+0.2
        c.invoke("HandleMouseButtonUpHorizon")
    end
    c.touch=function(id,x,y)
        local px=math.floor((rt.frameOx+x*rt.frameScale)*rt.dpr+0.5)
        local py=math.floor((rt.frameOy+y*rt.frameScale)*rt.dpr+0.5)
        return {TouchID={GetInt=function() return id end},X={GetInt=function() return px end},Y={GetInt=function() return py end}}
    end
end
local function geometryInputCases()
    for _,tri in ipairs({false,true}) do
        for _,size in ipairs({{1920,1080},{1280,720},{844,390}}) do
            for _,ratio in ipairs({1,2,3}) do
                local c=newContext(); c.beginGroup(4); c.tick(0.5)
                local rt,vp=c.rt,c.require("core.Viewport")
                rt.logicalW,rt.logicalH=size[1],size[2]; rt.windowW,rt.windowH=size[1],size[2]
                rt.dpr,rt.frameOx,rt.frameOy,rt.frameScale=ratio,37,23,0.8
                c.views["ui.battle.tri.BattleTriPage"].open=tri
                local ox,oy,s=vp.layout(size[1],size[2])
                if tri then ox,oy,s=0,0,size[2]/1080 end
                c.env.H_ox,c.env.H_oy,c.env.H_s=ox,oy,s
                vp.note("left",ox,oy,s)
                local town=c.require("ui.town.TownScene"); town.init(c.vg)
                c.tm.clearHotspots(); c.clearDraw(); town.draw(c.vg)
                local hs=assert(c.tm.getCurrentHotspot(),"real TownScene register tavern")
                eq(hs.cx,832,"real tavernX oracle"); eq(hs.cy,1400,"real tavernY oracle")
                eq(hs.w,397,"real tavernW oracle"); eq(hs.h,387,"real tavernH oracle")
                check(hs.spotlight==nil and hs.panel=="left","building not legacy full-left spotlight")
                local project=projectFunction(c)
                c.clearDraw(); project()
                local hole; for _,draw in ipairs(c.draws) do if draw.kind=="hole" then hole=draw.shape end end
                local cs=s*0.45; local x,y=ox+832*cs,oy+1400*cs
                local layout=c.require("ui.tutorial.TutorialOverlay").layout(size[1],size[2],{cx=x,cy=y,w=397*cs,h=387*cs})
                check(hole~=nil,"actual overlay draw hole spy")
                near(hole.x,layout.hole.cx-layout.hole.w/2,"real project final holeX")
                near(hole.w,layout.hole.w,"actual drawn hole not whole left panel")
                inScreen(layout.bubble,size[1],size[2],"bubble"); inScreen(layout.skip,size[1],size[2],"skip")
                check(not overlaps(layout.bubble,layout.hole) and not overlaps(layout.skip,layout.hole),"geometry doesn't hide target")
                bindInput(c)
                local before=c.persists
                c.click(ox+540*cs,oy+150*cs)
                eq(countCalls(c,"town_tavern"),0,"old blank band doesn't reach real TownScene")
                check(not c.tm.isGroupCompleted(4) and c.persists==before,"old blank doesn't progress")
                c.click(x+397*cs/2+3,y)
                eq(countCalls(c,"town_tavern"),0,"visual halo does not reach business")
                c.click(x,y)
                eq(countCalls(c,"town_tavern"),1,"target routed to real town once")
                check(not c.tm.isGroupCompleted(4),"real TownScene target click still not success")
                c.invoke("HandleMouseButtonUpHorizon"); eq(countCalls(c,"town_tavern"),1,"duplicate up inert")
                c.cursor.x,c.cursor.y=0,0
                local event=c.touch(41,x,y); c.invoke("HandleTouchBeginHorizon",event)
                c.invoke("HandleTouchBeginHorizon",c.touch(42,x,y)); c.invoke("HandleTouchEndHorizon",c.touch(42,x,y))
                eq(countCalls(c,"town_tavern"),1,"secondary touch cannot release primary")
                c.clock.elapsedTime=c.clock.elapsedTime+0.2; c.invoke("HandleTouchEndHorizon",event)
                eq(countCalls(c,"town_tavern"),2,"physical touch transformed DPR/frame to real building")
                c.invoke("HandleTouchEndHorizon",event); eq(countCalls(c,"town_tavern"),2,"duplicate touch up inert")
                check(not c.tm.isGroupCompleted(4),"touch click no business receipt remains active")
                c.tm.notifyEvent("enter_tavern"); c.tick(0.3)
                auditContext(c)
            end
        end
    end
end
local function bootTavernCases()
    for _,success in ipairs({false,true}) do
        local c=newContext(); c.beginGroup(4); c.tick(0.5)
        local town=c.require("ui.town.TownScene"); town.init(c.vg)
        local tavern=c.modules["ui.tavern.TavernPage"]; local view=c.views["ui.tavern.TavernPage"]
        tavern.open=function() view.opens=view.opens+1; view.open=success end
        for key,value in pairs({TownScene=town,TavernPage=tavern,vg=c.vg}) do rawset(c.env,key,value) end
        compile(section("boot.StandaloneBoot","    TownScene.setOnTavernClick(function()","\n    -- 5.18 城镇市场"),
            SOURCE_FILES["boot.StandaloneBoot"],c.env)
        bindInput(c); local project=projectFunction(c)
        local vp=c.require("core.Viewport"); vp.note("left",0,0,1)
        c.env.H_ox,c.env.H_oy,c.env.H_s=0,0,1
        town.draw(c.vg); project()
        c.click(832*0.45,1400*0.45)
        eq(view.opens,0,"real Town click schedules delayed callback, not immediate open")
        check(not c.tm.isGroupCompleted(4),"before0.15 success not fabricated")
        c.clock.elapsedTime=c.clock.elapsedTime+0.149; town.draw(c.vg)
        eq(view.opens,0,"0.149 draw not successful open")
        c.clock.elapsedTime=c.clock.elapsedTime+0.002; town.draw(c.vg)
        eq(view.opens,1,"0.151 real draw fires original Boot callback")
        eq(c.tm.isGroupCompleted(4),success,"actual isOpen gate controls success")
        local story=c.require("systems.StoryPlayer"); local pending=story.take()
        if success then
            eq(pending.scenarioId,31,"real opened tavern queues entry story once")
            eq(story.take(),nil,"success story deduplicated")
            c.tick(0.6); check(view.open,"out fade does not recovery-close just opened tavern")
        else eq(pending,nil,"failed open cannot queue entry story") end
        eq(#c.actions,0,"Boot entry itself emits no claim/recruit action")
        auditContext(c)
    end
    local c=newContext(); c.beginGroup(4); c.tick(0.5)
    local town=c.require("ui.town.TownScene"); local calls=0
    town.setOnTavernClick(function() calls=calls+1; c.tm.notifyEvent("enter_tavern") end)
    town.handleInput(832,1400); town.cancelPendingPageOpen(); c.clock.elapsedTime=c.clock.elapsedTime+1
    town.draw(c.vg); eq(calls,0,"Recovery cancellation invalidates pending Town open")
    check(not c.tm.isGroupCompleted(4),"cancelled delayed callback cannot fabricate success")
    auditContext(c)
end
local function foundation(c)
    c.memory.heroes.roster[18]={level=1}; c.tm.setNewHeroId(18)
    for _,id in ipairs({1,2,4,8,9}) do
        c.tm.startGroup(id); c.tm.skipCurrentGroup(); c.tick(0.3)
        check(c.tm.isGroupCompleted(id),"real finish/skip foundation " .. id)
    end
end
local function standaloneClosures(c)
    local e=c.env
    rawset(e,"postStartFlowDone_",false)
    for key,value in pairs({ClientDispatcher=c.modules["runtime.ClientDispatcher"],TutorialManager=c.tm,
        ScenarioDialogue=c.scenario,ScenarioDialogueConfig=c.config,LetterIntro=c.letter,
        IntroCutscene=c.modules["ui.story.gate.IntroCutscene"],RewardPopup=c.modules["ui.hud.popup.RewardPopup"],
        OfflineRewardPanel=c.modules["ui.hud.popup.OfflineRewardPanel"],DarkTitleScreen=c.modules["ui.story.gate.DarkTitleScreenGate"],
        GameBGM={setScene=function(scene) c.record("bgm." .. scene) end,start=noop},GameSFX={start=noop},
        showOfflineRewardPanel_=function() c.record("offline.check"); return c.offlineReady~=false end,
        localSendAction=function(action,params)
            if action~="grant_starter_trio" and action~="claim_scenario_reward" then return c.deny("unexpected action " .. action) end
            c.actions[#c.actions+1]={action=action,params=copy(params)}
            if action=="grant_starter_trio" then
                c.grants=c.grants+1
                c.memory.heroes.roster={["1"]={level=1},["2"]={level=1},["3"]={level=1}}
                c.memory.heroes.deployed={1,2,3}; c.memory.session.starterTrioReady=true
            end
            return true
        end,
        ClientMsgHandler={consumePendingScenarioDialogue=function() return table.remove(c.pending,1) end,
            consumePendingFollowUpDialogue=function() return table.remove(c.follow,1) end,
            setPendingTutorialNotify=function(id) c.notices[#c.notices+1]=id end},
    }) do rawset(e,key,value) end
    local body=section("boot.Standalone","local function markIntroCompleted_(deferOpening)","\n--- 清除存档后")
    return compile(body .. "\nreturn {mark=markIntroCompleted_,finish=finishIntro_,start=startIntroChain_,play=tryPlayPendingStory_}",
        SOURCE_FILES["boot.Standalone"],e)
end
local function postTitle(c,closures)
    rawset(c.env,"markIntroCompleted_",closures.mark); rawset(c.env,"startIntroChain_",closures.start)
    local text=section("boot.Standalone","    if not postStartFlowDone_ and not DarkTitleScreen.isOpen() then","\n    BottomNav.update(dt)")
    return compile("local startFlowBegun_,startScreenWasOpen_=false,false\nreturn function()\n"
        .. text .. "\nreturn postStartFlowDone_\nend",SOURCE_FILES["boot.Standalone"],c.env)
end
local function openingCases()
    local c=newContext(); c.memory.session={introCompleted=false,customLedger={x=9},claimedScenarios={}}
    local closures=standaloneClosures(c); local post=postTitle(c,closures)
    check(post(),"real new-save title branch completes once")
    check(c.letter.isOpen() and not c.scenario.isActive(),"new opening only real brief letter")
    eq(c.grants,1,"original starter action exactly once")
    eq(c.memory.session.deferredOpening,true,"new save alone deferred marked")
    eq(c.memory.session.deferredOpeningIndex,1,"new save deferred starts1")
    eq(c.memory.session.introCompleted,true,"original introCompleted preserved")
    check(same(c.memory.session.customLedger,{x=9}),"mark copies full unrelated session")
    for _,id in ipairs({1,2,3,4,11,12,13}) do check(c.memory.session.claimedScenarios[tostring(id)],"legacy hero grant claims preserved " .. id) end
    eq(countCalls(c,"offline.check"),0,"no offline computation before letter completion")
    c.env.postStartFlowDone_=false -- 模拟pre-cover先设intro=true、post-title仍未完成的真实路径。
    post(); eq(countCalls(c,"offline.check"),0,"intro=true during letter cannot show offline early")
    for _=1,10 do c.letter.handleTap() end
    c.letter.update(0); eq(#c.shown,0,"brief finish never immediately plays10 long opening lines")
    eq(countCalls(c,"offline.check"),1,"brief finish returns actual finish closure offline check")
    c.letter.update(1); post(); eq(c.grants,1,"repeat postTitle/finish does not grant again")
    eq(countCalls(c,"offline.check"),1,"successful finish/post-title offline computed once")
    local retry=newContext(); retry.memory.session.introCompleted=false; retry.offlineReady=false
    local rf=standaloneClosures(retry); local rp=postTitle(retry,rf); rp()
    for _=1,10 do retry.letter.handleTap() end
    retry.letter.update(0); check(not retry.env.postStartFlowDone_,"failed offline finish remains retryable")
    eq(countCalls(retry,"offline.check"),1,"failed offline once at finish")
    rp(); eq(countCalls(retry,"offline.check"),2,"next post-title frame retries readiness")
    retry.offlineReady=true; rp(); rp(); eq(countCalls(retry,"offline.check"),3,"successful retry finalizes exactly once")
    eq(retry.grants,1,"offline retry never regrants heroes or replays letter")
    auditContext(retry)
    local story=c.require("systems.StoryPlayer"); story.onStage(103,"clear")
    eq(story.take(),nil,"starter ready no old random hero reward scenario11-13")
    eq(story.takeDeferredOpening(),nil,"opening waits actual basic operation progress")
    auditContext(c)
    for _,intro in ipairs({false,true}) do
        local old=newContext(); old.memory.session.introCompleted=intro
        old.memory.heroes.roster={[1]={level=5},[2]={level=3}}
        old.memory.session.customLedger={old=true}
        local f=standaloneClosures(old); local once=postTitle(old,f)
        check(once() and once(),"real old-save branch settles")
        check(not old.letter.isOpen() and #old.shown==0,"old save never replays opening")
        eq(old.grants,0,"old multiple-hero save no repeated starter action")
        eq(old.memory.session.deferredOpening,nil,"old save no retroactive deferred marker")
        eq(old.memory.session.deferredOpeningIndex,nil,"old save no new index")
        eq(old.memory.session.introCompleted,true,"legacy hero migration still intro complete")
        check(old.require("systems.StoryPlayer").takeDeferredOpening()==nil,"old save no deferred take")
        check(old.memory.session.customLedger.old,"old arbitrary ledger retained")
        auditContext(old)
    end
end
local function deferredCases()
    for _,missing in ipairs({1,2,4,8,9}) do
        local c=newContext(); foundation(c)
        c.memory.session.deferredOpening,c.memory.session.deferredOpeningIndex=true,1
        c.memory.session.tutorialProgress.completed[tostring(missing)]=nil
        c.tm.init(c.vg,c.store,c.persist); c.tick(0)
        eq(c.require("systems.StoryPlayer").takeDeferredOpening(),nil,"each missing foundation blocks " .. missing)
        eq(c.flushes,0,"blocked take never saves")
        auditContext(c)
    end
    local c=newContext(); foundation(c)
    c.memory.session.deferredOpening,c.memory.session.deferredOpeningIndex=true,1
    local story=c.require("systems.StoryPlayer"); local f=standaloneClosures(c)
    story.enqueue(35); eq(story.takeDeferredOpening(),nil,"ordinary queue wins before deferred")
    f.play(); eq(c.shown[1].steps,c.config.SCENARIO_35.steps,"ordinary story plays before opening")
    eq(c.memory.session.deferredOpeningIndex,1,"ordinary play doesn't advance deferred")
    finishDialogue(c)
    eq(c.actions[#c.actions].action,"claim_scenario_reward","normal claim still real closure action boundary")
    local expected={c.config.OPENING,c.config.OPENING_JOINS[1],c.config.OPENING_JOINS[2],c.config.OPENING_JOINS[3]}
    local totalSteps=0
    for index,cfg in ipairs(expected) do
        local before=copy(c.memory); local flush=c.flushes; local actions=#c.actions
        f.play(); local shown=c.shown[#c.shown]
        eq(shown.steps,cfg.steps,"deferred keeps original config/steps identity " .. index)
        eq(shown.background,cfg.background,"deferred correct original background")
        eq(shown.backgroundIsCg,cfg.backgroundIsCg,"deferred CG flag preserved")
        eq(shown.title,cfg.title,"deferred title forwarded")
        check(same(c.memory,before),"take/show not mark complete nor session update")
        eq(c.flushes,flush,"take/show no Flush")
        eq(#c.actions,actions,"deferred no claim or hero action")
        local stale=shown.onFinish
        if index==1 then
            c.scenario.reset(); eq(c.memory.session.deferredOpeningIndex,1,"hard reset no progress")
            f.play(); stale(); eq(c.memory.session.deferredOpeningIndex,1,"old token cannot complete new playback")
            eq(c.flushes,flush,"old token no Flush")
        end
        if index%2==0 then c.scenario.skip(); c.scenario.skip() else finishDialogue(c) end
        totalSteps=totalSteps+#cfg.steps
        eq(c.flushes,flush+1,"only natural/skip onFinish Flush once")
        if index<4 then eq(c.memory.session.deferredOpeningIndex,index+1,"only finish advances index")
        else
            eq(c.memory.session.deferredOpening,false,"all4 clears marker")
            eq(c.memory.session.deferredOpeningCompletedVersion,1,"all4 records completion version")
        end
        c.scenario.skip(); stale(); eq(c.flushes,flush+1,"duplicate callback cannot progress/save")
        if index<4 then
            local shownCount=#c.shown
            f.play(); eq(#c.shown,shownCount,"no immediate next deferred segment")
            c.clock.elapsedTime=c.clock.elapsedTime+29.999
            f.play(); eq(#c.shown,shownCount,"29.999s still leaves game time")
            if index==1 then
                story.enqueue(47); f.play()
                eq(c.shown[#c.shown].steps,c.config.SCENARIO_47.steps,"ordinary story never waits for deferred gap")
                finishDialogue(c)
            end
            c.clock.elapsedTime=c.clock.elapsedTime+0.0011
            check(story.takeDeferredOpening()~=nil,"30s exact boundary now permits next segment")
        end
    end
    eq(totalSteps,10,"all original deferred ten lines retain accessibility")
    f.play(); eq(#c.shown,7,"no fifth/repeated deferred opening, ordinary2 + deferred5 including cancelled replay")
    auditContext(c)
    local reset=newContext(); foundation(reset)
    reset.memory.session.deferredOpening,reset.memory.session.deferredOpeningIndex=true,1
    local s=reset.require("systems.StoryPlayer"); local item=s.takeDeferredOpening()
    s.resetAll(); eq(s.finishDeferredOpening(item.deferredToken),false,"reset invalidates token")
    eq(reset.memory.session.deferredOpeningIndex,1,"reset old callback cannot write session")
    eq(reset.flushes,0,"reset old callback no Flush")
    auditContext(reset)
end
local function priorityCases()
    for _,gate in ipairs({"ui.hud.popup.RewardPopup","ui.hud.popup.OfflineRewardPanel","ui.hud.popup.LevelUpPopup",
        "ui.hud.popup.UpdateNoticePopup","ui.story.gate.DarkTitleScreenGate","ui.story.gate.IntroCutscene",
        "ui.dungeon.DungeonBattleScene","ui.tower.TowerBattleScene","ui.battle.stage.SweepDialog",
        "ui.battle.popup.DamageStatsPanel","ui.battle.stage.StageSelectDialog","ui.battle.popup.TerminalConfirmDialog"}) do
        local c=newContext(); foundation(c)
        c.memory.session.deferredOpening,c.memory.session.deferredOpeningIndex=true,1
        c.views[gate].open=true; local f=standaloneClosures(c); local before=copy(c.memory)
        f.play(); eq(#c.shown,0,"pending opening doesn't steal " .. gate)
        check(same(c.memory,before) and c.flushes==0,"blocked pending doesn't mark/save")
        c.views[gate].open=false; f.play(); eq(c.shown[1].steps,c.config.OPENING.steps,"blocked opening not dropped")
        c.scenario.skip(); auditContext(c)
    end
    local c=newContext(); foundation(c)
    local story=c.require("systems.StoryPlayer"); local f=standaloneClosures(c)
    c.memory.session.deferredOpening,c.memory.session.deferredOpeningIndex=true,1
    c.views["ui.hud.popup.RewardPopup"].pending=true
    f.play(); eq(#c.shown,0,"pending visible battle rewards precede deferred")
    c.rewardBlocked=true; f.play(); eq(#c.shown,0,"high priority blocked battle keeps deferred waiting")
    story.enqueue(47); f.play()
    eq(c.shown[1].steps,c.config.SCENARIO_47.steps,"hidden battle reward doesn't deadlock ordinary story")
    finishDialogue(c); c.rewardBlocked=false; c.views["ui.hud.popup.RewardPopup"].pending=false
    f.play(); eq(c.shown[2].steps,c.config.OPENING.steps,"hidden reward resolving releases deferred")
    c.scenario.skip(); auditContext(c)
    local queued=newContext(); local play=standaloneClosures(queued).play
    queued.require("systems.StoryPlayer").enqueue(35); queued.tm.onScenarioClaimed(20)
    play(); eq(#queued.shown,0,"queue tutorial protects original0.25 quiet window from ordinary")
    queued.tick(0.25); play(); eq(#queued.shown,0,"active tutorial blocks ordinary")
    queued.tm.skipCurrentGroup(); play(); eq(#queued.shown,0,"fading tutorial blocks ordinary")
    queued.tick(0.3); play(); eq(queued.shown[1].steps,queued.config.SCENARIO_35.steps,"ordinary story not starved after tutorial")
    finishDialogue(queued); auditContext(queued)
end
local function heroScenarioCases()
    for _,gate in ipairs({"queue","active","reward","offline","pending","story"}) do
        local c=newContext(); local hero=c.require("ui.character.hero.HeroScenario")
        c.memory.heroes.roster[18]={level=1}
        if gate=="queue" then c.tm.onScenarioClaimed(20)
        elseif gate=="active" then c.tm.startGroup(4)
        elseif gate=="reward" then c.views["ui.hud.popup.RewardPopup"].open=true
        elseif gate=="offline" then c.views["ui.hud.popup.OfflineRewardPanel"].open=true
        elseif gate=="story" then c.require("systems.StoryPlayer").enqueue(35)
        else c.views["ui.hud.popup.RewardPopup"].pending=true end
        local before=copy(c.memory)
        hero.onOpenHero(18); hero.onOpenHero(18); hero.update()
        eq(#c.shown,0,"direct hero idle arbitration blocks " .. gate)
        check(same(c.memory,before) and c.flushes==0,"blocked hero no early claim/save")
        c.views["ui.hud.popup.RewardPopup"].open=false; c.views["ui.hud.popup.RewardPopup"].pending=false
        c.views["ui.hud.popup.OfflineRewardPanel"].open=false
        if gate=="queue" then c.tick(0.25) end
        if gate=="queue" or gate=="active" then c.tm.skipCurrentGroup(); c.tick(0.3) end
        if gate=="story" then
            eq(c.require("systems.StoryPlayer").take().scenarioId,35,"queued ordinary consumed before hero")
        end
        hero.update(); eq(#c.shown,1,"hero poll recovers once without new clicks/end event " .. gate)
        eq(c.shown[1].steps,c.config.SCENARIO_78.steps,"owned hero emits original idle not repeated join")
        check(c.memory.session.claimedScenarios["74"] and c.memory.session.claimedScenarios["78"],"only played idle original ledger set")
        finishDialogue(c); hero.update(); hero.onOpenHero(18); eq(#c.shown,1,"hero queue/claim dedup no replay")
        auditContext(c)
    end
    local c=newContext(); local hero=c.require("ui.character.hero.HeroScenario")
    c.tm.startGroup(4)
    hero.onRecruitResults({{type="hero",isNew=true,heroId=18},{type="hero",isNew=true,heroId=19},
        {type="hero",isNew=true,heroId=18}})
    eq(#c.shown,0,"all multi recruit results queued while tutorial active")
    c.tm.skipCurrentGroup(); c.tick(0.3); hero.update()
    local expected={74,78,75,79}
    for i,id in ipairs(expected) do
        eq(c.shown[i].steps,c.config["SCENARIO_" .. id].steps,"real event chain drains distinct hero " .. id)
        c.scenario.skip()
    end
    eq(#c.shown,4,"two heroes four stories, duplicate result dedup")
    hero.update(); eq(#c.shown,4,"poll never duplicates hero chain")
    auditContext(c)
    local reset=newContext(); local h=reset.require("ui.character.hero.HeroScenario")
    reset.tm.startGroup(4); h.onRecruitResults({{type="hero",isNew=true,heroId=25}})
    h.resetAll(); reset.tm.skipCurrentGroup(); reset.tick(0.3); h.update()
    eq(#reset.shown,0,"reset cancels old hero queue")
    eq(reset.memory.session.claimedScenarios["77"],nil,"reset no false mark")
    -- 确认生产宿主确实有 poll/reset 接线，而非仅手工调用模块API。
    check(source("boot.Standalone"):find('require("ui.character.hero.HeroScenario").update()',1,true)~=nil,"real Standalone poll present")
    check(source("boot.Standalone"):find('require("ui.character.hero.HeroScenario").resetAll()',1,true)~=nil,"real Standalone reset present")
    auditContext(reset)
    local precedence=newContext(); local h2=precedence.require("ui.character.hero.HeroScenario")
    precedence.memory.heroes.roster[18]={level=1}; precedence.tm.startGroup(4)
    h2.onOpenHero(18); precedence.tm.skipCurrentGroup(); precedence.tick(0.3); foundation(precedence)
    precedence.memory.session.deferredOpening,precedence.memory.session.deferredOpeningIndex=true,1
    local ps=precedence.require("systems.StoryPlayer"); local play=standaloneClosures(precedence).play
    play(); eq(#precedence.shown,0,"pending hero priority over deferred, without mutual deadlock")
    h2.update(); eq(precedence.shown[1].steps,precedence.config.SCENARIO_78.steps,"hero poll consumes ahead of deferred")
    ps.enqueue(35); h2.onRecruitResults({{type="hero",heroId=19,isNew=true}})
    precedence.scenario.skip(); eq(#precedence.shown,1,"finish broadcast cannot jump ahead of ordinary queue")
    play(); eq(precedence.shown[2].steps,precedence.config.SCENARIO_35.steps,"ordinary queue priority during event drain")
    precedence.scenario.skip(); eq(precedence.shown[3].steps,precedence.config.SCENARIO_75.steps,"after ordinary finish drains next hero")
    precedence.scenario.skip(); precedence.scenario.skip(); play()
    eq(precedence.shown[5].steps,precedence.config.OPENING.steps,"hero+ordinary finished then deferred released")
    precedence.scenario.skip(); auditContext(precedence)
end
local function localizedCases()
    local c=newContext(); local dictionary=c.require("core.I18nStory")
    local inputs={"致第三十七任远征长：","帽子、印鉴、名册都在桌上，三位伙伴已在门外等你。",
        "先带队出门，路上的故事，我们稍后再说。","· 轻触出发 ·"}
    eq(#dictionary.LETTER,12,"FULL translation source12 unchanged")
    local sentences=0
    for key,cfg in pairs(c.config) do
        if type(cfg)=="table" and type(cfg.steps)=="table" then sentences=sentences+#cfg.steps
        elseif key=="OPENING_JOINS" then for _,join in ipairs(cfg) do sentences=sentences+#join.steps end end
    end
    eq(sentences,196,"all original196 sentences including Opening+Joins remain")
    for _,lang in ipairs({"zh_TW","en","ja","ko"}) do
        c.lang=lang
        for _,input in ipairs(inputs) do
            local translated=dictionary.lookup(input,lang)
            check(type(translated)=="string" and translated~="" and translated~=input,"real source lookup complete " .. lang)
        end
        local target=c.require("config.TutorialConfig")[4].steps[1].text
        check(dictionary.lookup(target,lang)~=nil,"real target prompt translation " .. lang)
        c.letter.start(nil,{compact=true}); c.letter.handleTap()
        for _,size in ipairs({{1920,1080},{1280,720},{844,390}}) do
            c.clearDraw(); c.letter.draw(c.vg,size[1],size[2])
            local texts={}
            for _,t in ipairs(c.texts) do
                texts[#texts+1]=t.text
                local x=t.x
                if t.align & NVG_ALIGN_RIGHT~=0 then x=x-t.width
                elseif t.align & NVG_ALIGN_CENTER~=0 then x=x-t.width/2 end
                check(x>=-0.001 and x+t.width<=size[1]+0.001,"translated letter X bounds " .. lang)
                check(t.y>=0 and t.y+t.font<=size[2]+0.001,"translated letter Y bounds " .. lang)
            end
            local text=table.concat(texts,"")
            for _,input in ipairs(inputs) do
                check(text:find(dictionary.lookup(input,lang),1,true)~=nil,"translated full text/footer retained " .. lang)
            end
            local layout=c.require("ui.tutorial.TutorialOverlay").draw(c.vg,size[1],size[2],
                {cx=832*0.45*size[2]/1080,cy=1400*0.45*size[2]/1080,w=397*0.45*size[2]/1080,h=387*0.45*size[2]/1080},
                target,1,2,1)
            eq(table.concat(layout.lines,""),dictionary.lookup(target,lang),"actual Overlay translates before wrap, retains full prompt")
            inScreen(layout.bubble,size[1],size[2],"translated tutorial bubble " .. lang)
        end
        c.letter.reset()
    end
    auditContext(c)
end
local REVIEW_IMAGES={
    ["image/剧情/背景/STORY_BG_01.png"]="image/剧情/背景/STORY_BG_01.png",
    ["fixed-town-backdrop"]="/workspace/screenshots/town-expedition-landscape-inspect-20261006.png",
}
local NATIVE_DRAW_NAMES={
    "nvgBeginPath","nvgCircle","nvgClosePath","nvgFill","nvgFillColor","nvgFillPaint","nvgFontFace","nvgFontSize",
    "nvgImagePattern","nvgImagePatternTinted","nvgImageSize","nvgIntersectScissor","nvgLineCap","nvgLineJoin",
    "nvgLineTo","nvgLinearGradient","nvgMoveTo","nvgPathWinding","nvgRGBA","nvgRect","nvgResetScissor",
    "nvgRestore","nvgRoundedRect","nvgSave","nvgScale","nvgScissor","nvgShapeAntiAlias","nvgSkewX",
    "nvgStroke","nvgStrokeColor","nvgStrokeWidth","nvgText","nvgTextAlign","nvgTextBounds","nvgTextLineHeight","nvgTranslate",
}
---@type any
local reviewContext,reviewVG,reviewProject=nil,nil,nil
local reviewBackdrop=-1
local function startReview()
    check(REVIEW=="letter" or REVIEW=="tavern","explicit review mode")
    reviewContext=newContext(); local c=reviewContext
    reviewVG=assert(nvgCreate(1)); check(nvgCreateFont(reviewVG,"sans","Fonts/MiSans-Regular.ttf")>=0,"native font once")
    c.vg=reviewVG; c.rt.vg=reviewVG
    c.tm.init(reviewVG,c.store,c.persist)
    if REVIEW=="tavern" then
        c.beginGroup(4); c.tick(1.2)
        c.require("ui.town.TownScene").draw(reviewVG) -- 只读Town spy用于实际热点注册；底图是固定旧截图。
        c.require("core.Viewport").note("left",0,0,1)
        reviewProject=projectFunction(c)
    end
    -- 仅明确列举的绘图能力；env未知全局、require、文件/业务拒绝规则完全不变。
    for _,name in ipairs(NATIVE_DRAW_NAMES) do rawset(c.env,name,assert(_G[name],"native draw missing " .. name)) end
    c.env.nvgCreateImage=function(vg,path,flags)
        local image=REVIEW_IMAGES[path]
        if not image then return c.deny("native image not whitelisted " .. tostring(path)) end
        local handle=nvgCreateImage(vg,image,flags or 0)
        check(handle>=0,"native whitelisted image load " .. path)
        c.loads[#c.loads+1]=image; return handle
    end
    local i18n=c.modules["core.I18n"]
    i18n.displayBounds=nvgTextBounds; i18n.displayText=nvgText
    c.letter.init(reviewVG); c.scenario.init(reviewVG,nil)
    if REVIEW=="letter" then c.letter.start(nil,{compact=true}); c.letter.handleTap()
    else reviewBackdrop=c.env.nvgCreateImage(reviewVG,"fixed-town-backdrop",0) end
    SubscribeToEvent(reviewVG,"NanoVGRender","HandleFocusedOnboardingReview")
    print(TAG .. "REVIEW " .. REVIEW .. ": actual native NanoVG/font/Letter/Overlay; tavern background fixed read-only prior screenshot; no main/save.")
end
function HandleFocusedOnboardingReview()
    local c=assert(reviewContext); local ratio=graphics:GetDPR()
    local w,h=graphics:GetWidth()/ratio,graphics:GetHeight()/ratio
    check(graphics:GetWidth()==1920 and graphics:GetHeight()==1080,"review real1920x1080")
    -- 模式A：指定1920×1080；DPR只BeginFrame，设计contain绝不修改SetMode。
    local scale=math.min(w/1920,h/1080)
    nvgBeginFrame(reviewVG,w,h,ratio); nvgSave(reviewVG)
    nvgTranslate(reviewVG,(w-1920*scale)*0.5,(h-1080*scale)*0.5); nvgScale(reviewVG,scale,scale)
    if REVIEW=="letter" then c.letter.draw(reviewVG,1920,1080)
    else
        nvgBeginPath(reviewVG); nvgRect(reviewVG,0,0,1920,1080)
        local backdropPaint=nvgImagePattern(reviewVG,0,0,1920,1080,0,reviewBackdrop,1)
        ---@cast backdropPaint NVGpaint
        nvgFillPaint(reviewVG,backdropPaint); nvgFill(reviewVG)
        reviewProject()
    end
    nvgRestore(reviewVG); nvgEndFrame(reviewVG)
end
function Start()
    -- 宿主 entry 注册 Start/Stop 后再冻结；NaN 枚举用显式 NaN 等价审计。
    loadedBefore,globalsBefore={},{}
    for k,v in pairs(package.loaded) do loadedBefore[k]=v end
    for k,v in pairs(_G) do globalsBefore[k]=v end
    eq(ROOT,PROJECT,"explicit intended test root")
    check(fileSystem:GetCurrentDir():gsub("/+$","")==CWD,"must run only in isolated validation cwd")
    if REVIEW~="" then startReview(); return end
    runCase("strict-loader-danger-probes-and-deepcopy",safetyCases)
    runCase("target-business-separation-all-three-branches",targetCases)
    runCase("queue-quiet-recovery-priority-and-no-action",queueRecoveryCases)
    runCase("FULL-BRIEF-letter-geometry-natural-fast-reset-and-original-config",letterCases)
    runCase("real-Town-register-Horizon-project-input-mouse-touch-DPR",geometryInputCases)
    runCase("real-Boot-tavern-delayed-open-success-failure-cancellation",bootTavernCases)
    runCase("real-Standalone-new-legacy-opening-and-offline-once-retry",openingCases)
    runCase("real-deferred-token-only-finish-reset-and-original-four-configs",deferredCases)
    runCase("ordinary-deferred-quiet-priority-hidden-reward-no-deadlock",priorityCases)
    runCase("real-HeroScenario-blocked-queue-dedup-poll-event-reset",heroScenarioCases)
    runCase("real-I18nStory-FULL196-and-short-four-language-layout",localizedCases)
    runCase("package-loaded-global-and-source-audit",function()
        for k,v in pairs(loadedBefore) do eq(package.loaded[k],v,"package loaded original " .. k) end
        for k,v in pairs(package.loaded) do eq(loadedBefore[k],v,"no package loaded added " .. k) end
        for k,v in pairs(globalsBefore) do
            local a=_G[k]; check(a==v or type(a)=="number" and type(v)=="number" and a~=a and v~=v,
                "host global original " .. tostring(k))
        end
        for k,v in pairs(_G) do
            local a=globalsBefore[k]; check(a==v or type(a)=="number" and type(v)=="number" and a~=a and v~=v,
                "no global added " .. tostring(k))
        end
        for _,resource in ipairs(reads) do
            local allowed=false; for _,candidate in pairs(SOURCE_FILES) do
                if candidate==PROJECT .. "/scripts/" .. resource then allowed=true end
            end
            check(allowed,"every cache read exact allowlisted script resource")
        end
        eq(File,nativeFile,"host File never overwritten")
        eq(cache,nativeCache,"host cache never overwritten")
        check(#contexts>0 and #reads>0,"audit covered actual isolated production modules")
    end)
    print(TAG .. "RESULT " .. (failures==0 and "ALL PASS" or "FAIL") .. " groups=" .. groups .. " checks=" .. checks .. " failures=" .. failures)
    if failures>0 then log:Write(LOG_ERROR,TAG .. "validation assertions failed=" .. failures) end
    -- 官方 validate 帧预算负责退出和报告；不得用进程退出码替代断言结果。
end
function Stop()
    if reviewVG then nvgDelete(reviewVG); reviewVG=nil end
end
