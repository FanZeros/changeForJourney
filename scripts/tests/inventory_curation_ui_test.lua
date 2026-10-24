-- 隔离UI/Yoga/字体、完整HorizonInput及真实Bridge→Service→Flush→CMH。
-- 不加载main/Standalone；Fixture的File/FS完全虚拟，cache只读脚本资源。
local vg = nil ---@type NVGContextWrapper?
local h = nil ---@type table?
local checks = 0
local function check(value, why)
    checks = checks + 1
    assert(value, why)
end
local function noop() return false end
local function stub(values)
    return setmetatable(values or {}, { __index = function() return noop end })
end
local function event(fields)
    local result = {}
    for key, value in pairs(fields) do result[key] = { GetInt = function() return value end } end
    return result
end
function Start()
    vg = nvgCreate(1)
    assert(vg, "NanoVG context")
    check(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0, "real font available")
    h = require("tests.InventoryCurationFixture").new()
    h.allowBootFixture = true
    h.require("ui.widget.DesignWidgetSurface").init()
    SubscribeToEvent(vg, "NanoVGRender", "RunCurationUiTest")
end
function RunCurationUiTest()
    UnsubscribeFromEvent("NanoVGRender")
    local ok, err = pcall(function()
        local F = require("tests.InventoryCurationFixture")
        local cursor, ratio = {x=0,y=0}, 1
        h.env.input = { GetMousePosition = function() return cursor end }
        local overlays, calls = {}, {underlying=0, detail=0, candidate=0}
        local paths = {
            "ui.hud.TopBar", "ui.hud.BottomNav", "ui.battle.scene.BattleScene",
            "ui.character.panel.CharacterPanel", "ui.dev.CEPanel", "ui.character.hero.HeroRosterPanel",
            "ui.hud.popup.RewardPopup", "ui.town.TownScene", "ui.blacksmith.BlacksmithPage",
            "ui.church.ChurchPage", "ui.church.talent.TalentPage", "ui.tavern.TavernPage",
            "ui.market.MarketPage", "ui.dungeon.DungeonBattleScene", "ui.tower.TowerBattleScene",
            "ui.dungeon.DungeonPage", "ui.backpack.BackpackPanel", "ui.loot.LootBox", "ui.loot.LootBoxPage",
            "ui.story.task.TaskPage", "ui.hud.popup.LevelUpPopup", "ui.hud.popup.OfflineRewardPanel",
            "ui.hud.popup.UpdateNoticePopup", "ui.hud.popup.PlayerInfoPanel", "ui.story.gate.StartScreen",
            "ui.story.gate.DarkTitleScreenGate", "ui.battle.tri.BattleTriPage", "ui.battle.stage.SweepDialog",
            "ui.battle.popup.DamageStatsPanel", "ui.battle.stage.StageSelectDialog",
            "ui.battle.popup.TerminalConfirmDialog", "ui.story.gate.IntroCutscene", "ui.story.gate.LetterIntro",
            "ui.character.detail.CharacterDetail", "ui.character.hero.AwakeningArtwork",
            "ui.character.equip.EquipmentBag", "ui.character.EquipCrossDrag", "ui.story.ScenarioDialogue",
            "systems.TutorialManager", "ui.character.equip.EquipmentDetail", "ui.dev.GMConsolePanel",
            "ui.hud.popup.RedeemCodePanel", "ui.church.ChurchArtifactPanel", "ui.character.hero.ArtifactDetailPanel",
        }
        for _, name in ipairs(paths) do
            local key = name
            h.mocks[name] = stub({
                isOpen=function() return overlays[key] == true end,
                isActive=function() return overlays[key] == true end,
                handleInput=function() calls.underlying=calls.underlying+1; return true end,
                handleScroll=function() calls.underlying=calls.underlying+1; return true end,
            })
        end
        h.mocks["ui.battle.scene.BattleScene"].getStageId = function() return 101 end
        h.mocks["ui.battle.scene.BattleScene"].getMaxStageId = function() return 101 end
        h.mocks["ui.battle.scene.BattleScene"].getClearedStages = function() return {} end
        h.mocks["ui.hud.BottomNav"].getSelectedIndex = function() return 3 end
        h.mocks["ui.battle.tri.BattleTriPage"].isOpen = function() return true end
        h.mocks["ui.backpack.BackpackPanel"].isCurationSourceReady = function() return true end
        h.mocks["ui.loot.LootBoxPage"].isCurationSourceReady = function() return true end
        h.mocks["ui.character.hero.AwakeningArtwork"].bindInput = function() return noop end
        h.mocks["ui.character.equip.EquipmentDetail"].close = function() calls.detail=calls.detail+1 end
        h.mocks["ui.backpack.BackpackPanel"].onCurationCommitted = function() calls.candidate=calls.candidate+1 end
        -- 仅裁剪无关动作pack；被测三个action注册/dispatch/持久化hooks均是真实Bridge。
        for _, name in ipairs({"battle.Battle", "hero.Hero", "gacha.Gacha", "equipment.Equipment",
            "blacksmith.Blacksmith", "task.Task", "redeem.Redeem", "awakening.Awakening",
            "advancement.Advancement", "talent.Talent", "signin.SignIn", "gm.GM", "market.Market",
            "loot.Loot", "sweep.Sweep", "artifact.Artifact", "dungeon.Dungeon", "offline.Offline", "tower.Tower"}) do
            h.mocks["rules."..name.."Handler"] = {actionHandlers={}}
        end
        h.mocks["rules.task.TaskService"] = {SetPersistCallback=function() end}
        h.mocks["rules.dungeon.DungeonService"] = {SetPersistCallback=function() end}
        h.mocks["rules.redeem.RedeemService"] = {Init=function() end}
        local modules = F.modules(h, 500)
        modules.lootbox = F.box({F.item(h,"W1",1,6)})
        for _, name in ipairs({"talents","artifacts","slotEnhance","task","redeem","signin","market","tavern","dungeon","global_profile","quotas"}) do modules[name]={} end
        h:attach(modules)
        local Store = h.require("core.PlayerStore")
        local Dispatch = h.require("runtime.ClientDispatcher")
        local GameState = h.require("core.GameState")
        GameState.syncPlayerData(modules.player)
        GameState.syncFromCurrency(modules.currency)
        local UI = require("urhox-libs/UI")
        local Theme = require("urhox-libs/UI/Core/Theme")
        local Surface = h.require("ui.widget.DesignWidgetSurface")
        local captured = nil
        h.mocks["ui.widget.DesignWidgetSurface"] = {
            init=Surface.init,
            draw=function(root, context, width, height)
                captured=root
                Surface.draw(root,context,width,height)
            end,
        }
        local Dialog = h.require("ui.loot.InventoryCurationDialog")
        local Text, Lang = h.require("core.I18nInventoryCuration"), h.require("core.I18n")
        local Msg = h.require("runtime.ClientMessageHandler")
        Msg.setup({sendAction=noop,ui={}})
        local results, sent = {}, {}
        local receive = Msg.handleActionResult
        Msg.handleActionResult = function(data)
            results[#results+1]=F.copy(data)
            receive(data)
        end
        local Bridge = h.require("runtime.LocalActionBridge")
        Bridge.init()
        local Action = h.require("runtime.GameAction")
        local realSend = Action.sendAction
        Action.sendAction = function(action,params)
            sent[#sent+1]={action=action,params=F.copy(params)}
            return realSend(action,params)
        end
        local notified, flushes, failFlush = {}, 0, false
        Store.Subscribe("equipment",function() notified[#notified+1]="equipment" end)
        Store.Subscribe("lootbox",function() notified[#notified+1]="lootbox" end)
        local Save = h.require("boot.StandaloneSave")
        local realFlush = Save.Flush
        Save.Flush = function(...)
            flushes=flushes+1
            check(#notified==0,"no notification before Flush")
            if failFlush then return false end
            return realFlush(...)
        end
        local RT={frameScale=1,frameOx=0,frameOy=0}
        local width,height=1920,1080
        local Viewport=h.require("core.Viewport")
        local ctx={RT=RT,Viewport=Viewport,vg=function() return vg end,
            logicalW=function() return width end,logicalH=function() return height end,
            windowW=function() return width end,windowH=function() return height end,
            dpr=function() return ratio end,DESIGN_W=1920,DESIGN_H=1080,bootReady_=function() return true end,
            toDesign=function(x,y) return (x-RT.frameOx)/RT.frameScale,(y-RT.frameOy)/RT.frameScale end,
            talentPageUsesWideLayout=noop,syncTalentPageLayout=noop,talentPageRightEdge=function() return 486 end,
            equipOverlayDesign=function() return 0,0 end,seamHitAt=noop,seamInputBlocked=noop,
            OfflineRewardOverlay=stub({toDesign=function(x,y) return x,y end}),
        }
        h.require("boot.StandaloneHorizonInput").bind(ctx)
        local function draw()
            nvgBeginFrame(vg,width,height,1)
            Dialog.drawEntry(vg,840,608,340,68)
            Dialog.draw(vg,width,height)
            nvgEndFrame(vg)
        end
        local function buttonPoint(which)
            local footer=captured.children[5]
            local b=footer.children[which=="cancel" and 1 or 2]:GetAbsoluteLayout()
            local s=math.min(1,(width-32)/900,(height-32)/800)
            return (width-900*s)/2+(b.x+b.w/2)*s,(height-800*s)/2+(b.y+b.h/2)*s
        end
        local function mouse(kind,which,x,y)
            if x then cursor.x,cursor.y=(x*RT.frameScale+RT.frameOx)*ratio,(y*RT.frameScale+RT.frameOy)*ratio end
            local fn=kind=="down" and h.env.HandleMouseButtonDownHorizon or kind=="up" and h.env.HandleMouseButtonUpHorizon or h.env.HandleMouseMoveHorizon
            fn("test",event({Button=which or MOUSEB_LEFT}))
        end
        local function tap(which)
            local x,y=buttonPoint(which)
            mouse("down",MOUSEB_LEFT,x,y); mouse("up",MOUSEB_LEFT,x,y)
        end
        local function applyCount()
            local n=0; for _,record in ipairs(sent) do if record.action=="ApplyInventoryCuration" then n=n+1 end end; return n
        end
        local function open()
            check(Dialog.open("backpack"),"open preview")
            check(results[#results].action=="PreviewInventoryCuration" and results[#results].success,"real preview wrapper+CMH")
            draw()
        end
        open()
        check(captured and captured.node,"real Yoga root")
        -- 实际Yoga布局与字体测量，不以预计按钮位置替代真实bounds。
        local function assertTree(widget,parent)
            local b=widget:GetAbsoluteLayout()
            check(b.w>=0 and b.h>=0,"finite Yoga sizes")
            if parent then
                check(b.x>=parent.x-1 and b.x+b.w<=parent.x+parent.w+1 and b.y>=parent.y-1 and b.y+b.h<=parent.y+parent.h+1,"child inside parent")
            end
            if widget.GetText and widget.props.fontSize then
                local fit=UI.MeasureTextFit(widget:GetText(),{fontSize=Theme.FontSize(widget.props.fontSize),
                    fontFace=Theme.FontFace("sans"),width=b.w-4,multiline=true,lineHeight=widget.props.lineHeight or 1,minFontSize=Theme.FontSize(widget.props.fontSize)})
                check(fit.height<=b.h+1,"real font content height "..fit.height.."/"..b.h.." "..widget:GetText())
            end
            for _,child in ipairs(widget.children) do assertTree(child,b) end
        end
        for _,lang in ipairs({"zh_CN","zh_TW","en","ja","ko"}) do
            Lang.set(lang); draw(); assertTree(captured)
            local footer=captured.children[5]
            for _,button in ipairs(footer.children) do
                local face=Theme.FontFace(button.props.fontFamily,button.props.fontWeight)
                check(button.props.text~="","localized button text "..lang)
                check(nvgFindFont(vg,face)>=0,"button font registered in host vg: "..face)
                nvgFontFace(vg,face);nvgFontSize(vg,Theme.FontSize(button.props.fontSize))
                local measured=nvgTextBounds(vg,0,0,button.props.text)
                local b=button:GetAbsoluteLayout()
                check(measured>0 and measured<b.w-32,"actual button font measures caption "..lang)
            end
            check(footer.children[1].props.text==Text.text("取消"),"localized cancel "..lang)
            check(footer.children[2].props.text==Text.text("确认优选"),"localized confirm "..lang)
            check(captured.children[1]:GetText()==Text.text("优选预览"),"localized title "..lang)
        end
        Lang.set("zh_CN");draw()
        local x,y=buttonPoint("confirm")
        local before=applyCount()
        mouse("up",MOUSEB_LEFT,x,y); check(applyCount()==before,"release only rejected")
        mouse("down",MOUSEB_LEFT,x,y); mouse("move",MOUSEB_LEFT,x+50,y); mouse("move",MOUSEB_LEFT,x,y); mouse("up",MOUSEB_LEFT,x,y)
        check(applyCount()==before,"movement ABA rejected")
        mouse("down",MOUSEB_LEFT,x,y);mouse("down",MOUSEB_RIGHT,x,y);mouse("up",MOUSEB_RIGHT,x,y);mouse("up",MOUSEB_LEFT,x,y)
        check(applyCount()==before+1,"secondary button preserves primary")
        check(flushes==1 and #notified==2 and notified[1]=="equipment" and notified[2]=="lootbox","real commit publish exactly once")
        check(calls.detail==1 and calls.candidate==1,"real CMH clears stale refs")
        check(h.disk["standalone_save.json"]~=nil and h.fileCalls>0 and h.fsCalls>0,"real Flush virtual disk")
        local last=sent[#sent]
        check(last.action=="ApplyInventoryCuration" and type(last.params.token)=="string" and last.params.requestId~=nil,"token action")
        for k in pairs(last.params) do check(k=="token" or k=="requestId","no client list") end
        for _,lang in ipairs({"zh_CN","zh_TW","en","ja","ko"}) do
            Lang.set(lang);draw()
            local r=results[#results]
            check(captured.children[4]:GetText()==Text.text("整理完成：移入 %d 件，转存 %d 件",r.moveInCount,r.moveOutCount),"done live language "..lang)
        end
        tap("confirm");check(applyCount()==before+1,"done cannot resubmit")
        Dialog.close();Lang.set("zh_CN")
        -- 恢复新确定性夹具，避免复用已优选状态造成无变更。
        local function replenish()
            modules.equipment=F.bag(h,500)
            modules.lootbox=F.box({F.item(h,"W1",1,6)})
            Dispatch.set("equipment",modules.equipment,{normalized=true})
            Dispatch.set("lootbox",modules.lootbox,{normalized=true})
            notified={}
        end
        replenish();open();before=applyCount()
        mouse("down",MOUSEB_LEFT,x,y)
        overlays["ui.hud.popup.RewardPopup"]=true;Dialog.observe();overlays["ui.hud.popup.RewardPopup"]=false
        mouse("up",MOUSEB_LEFT,x,y)
        check(not Dialog.isOpen() and not Dialog.hasPress() and applyCount()==before,"overlay ABA cancels whole gesture")
        open();mouse("down",MOUSEB_LEFT,x,y)
        ratio=2;Dialog.observe();ratio=1;mouse("up",MOUSEB_LEFT,x,y)
        check(applyCount()==before,"DPR ABA permanent cancellation")
        mouse("down",MOUSEB_LEFT,x,y);h.env.HandleMouseWheelHorizon("wheel",event({Wheel=-1}));mouse("up",MOUSEB_LEFT,x,y)
        check(applyCount()==before,"wheel cancels and consumes")
        mouse("down",MOUSEB_LEFT,x,y);Dispatch.set("equipment",modules.equipment,{normalized=true});Dialog.observe();mouse("up",MOUSEB_LEFT,x,y)
        check(applyCount()==before,"data update stale down rejected")
        draw();tap("confirm");draw() -- invalid -> actual new preview
        local function touch(kind,id,tx,ty)
            local fn=kind=="down" and h.env.HandleTouchBeginHorizon or kind=="up" and h.env.HandleTouchEndHorizon or h.env.HandleTouchMoveHorizon
            fn("touch",event({TouchID=id,X=tx,Y=ty}))
        end
        x,y=buttonPoint("confirm")
        touch("down",1,math.floor(x),math.floor(y));touch("down",2,math.floor(x),math.floor(y));touch("up",2,math.floor(x),math.floor(y))
        mouse("up",MOUSEB_LEFT,x,y);check(applyCount()==before,"different pointer source rejected")
        touch("move",1,math.floor(x+40),math.floor(y));touch("move",1,math.floor(x),math.floor(y));touch("up",1,math.floor(x),math.floor(y))
        check(applyCount()==before,"real touch move ABA rejected")
        -- Flush=false必须由真实Bridge持久化callback进入真实Service回滚，再由真实CMH显示。
        failFlush=true;notified={};local frozen=F.copy({modules.equipment,modules.lootbox});local aliases=F.aliases({modules.equipment,modules.lootbox})
        tap("confirm");check(applyCount()==before+1,"apply reaches actual wrapper")
        check(results[#results].success==false and results[#results].reason=="整理存档失败，可重试","real failure result")
        F.same({modules.equipment,modules.lootbox},frozen);F.assertAliases(aliases)
        check(#notified==0 and calls.detail==1 and calls.candidate==1,"rollback no notify or stale-ref success hooks")
        draw();check(captured.children[4]:GetText()==Text.text("存档失败，未移动装备，请重试。"),"localized save failure")
        local old=captured
        mouse("down",MOUSEB_LEFT,x,y);Dialog.reset()
        check(old.node==nil and #old.children==0 and not Dialog.isOpen() and Dialog.hasPress(),"reset destroys own Yoga tree retains canceled press")
        mouse("up",MOUSEB_LEFT,x,y);check(not Dialog.hasPress() and applyCount()==before+1,"reset consumes matching old release")
        check(calls.underlying==0,"modal input never leaks to panels")
        check(h.randomCalls==0,"no random consumption")
        -- 共享Surface仍可重开；新预览未Render前不可命中旧树。
        Dialog.bindHost({sourceValid=function() return true end})
        check(Dialog.open("lootbox"),"reopen after reset")
        Dialog.pointer("down",MOUSEB_LEFT,x,y,"mouse",width,height,"new")
        Dialog.pointer("up",MOUSEB_LEFT,x,y,"mouse",width,height,"new")
        check(applyCount()==before+1,"no first draw fails closed")
        draw();check(captured~=old and captured.node~=nil,"fresh root after reset")
        Dialog.close()
        -- 延迟回执只验证UI身份门禁；上面的成功/失败始终走真实Bridge/Service/Flush。
        local queued={}
        Action.sendAction=function(action,params) queued[#queued+1]={action=action,params=F.copy(params)};return true end
        check(Dialog.open("lootbox"),"async preview open");draw()
        local pending=queued[#queued]
        local function queuedApplies()
            local n=0;for _,r in ipairs(queued) do if r.action=="ApplyInventoryCuration" then n=n+1 end end;return n
        end
        tap("confirm");check(queuedApplies()==0,"loading cannot apply")
        Dialog.close()
        Dialog.onActionResult({action="PreviewInventoryCuration",requestId=pending.params.requestId,success=true,token="late"})
        check(queued[#queued].action=="CancelInventoryCuration" and queued[#queued].params.token=="late","late preview token canceled")
        check(Dialog.open("backpack"),"stress metrics preview")
        pending=queued[#queued]
        Dialog.onActionResult({action="PreviewInventoryCuration",requestId=pending.params.requestId,success=true,token="stress",moveInCount=500,moveOutCount=500,protectedCount=500})
        for _,lang in ipairs({"zh_CN","zh_TW","en","ja","ko"}) do Lang.set(lang);draw();assertTree(captured) end
        Lang.set("zh_CN");draw();tap("confirm");draw();tap("confirm")
        check(queuedApplies()==1,"applying cannot submit twice")
        Dialog.reset()
        Action.sendAction=realSend
        Surface.shutdown()
    end)
    if not ok then print("[inventory_curation_ui_test] [FAIL] "..tostring(err))
    else print("[inventory_curation_ui_test] ALL PASS "..checks.." assertions") end
    engine:Exit()
end
function Stop()
    if vg then nvgDelete(vg);vg=nil end
end
