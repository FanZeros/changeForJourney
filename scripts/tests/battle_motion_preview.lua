-- 基于scaffold-2d：UI.Init/组件树/SetRoot管理唯一NanoVG帧。
-- 受控真实战斗样本，不启动main/不读玩家档；借用原卡面和原文本系统。
-- -battle-motion-sample=attack|recoil|heal|critical|death|enter
-- -battle-motion-phase=early|late|charge|recover
local UI = require("urhox-libs/UI")
local sources, mods, samples = {}, {}, {}
local sample, phase = "attack", "early"
local frames = 0
---@type any
local Anim, Fx, Effects, Draw, View, Layout = nil, nil, nil, nil, nil, nil
---@type any
local current = nil
local imagesReady = false

local function source(name)
    local path = name:gsub("%.", "/") .. ".lua"
    if not sources[path] then
        local f = assert(cache:GetFile(path), path)
        local lines = {}; while not f:IsEof() do lines[#lines+1]=f:ReadLine() end
        f:Dispose(); sources[path]=table.concat(lines,"\n")
    end
    return sources[path]
end
local function loadReal(name)
    if mods[name] then return mods[name] end
    local env=setmetatable({}, {__index=_G});env._G=env
    env.require=function(dep) return assert(mods[dep],"预览未声明依赖 " .. dep) end
    env.File=function() error("预览禁止玩家File") end
    env.fileSystem=setmetatable({}, {__index=function() error("预览禁止玩家FileSystem") end})
    env.SendEvent=function() error("预览禁止Action/events") end
    -- 旧setup固定取中值便于比较；新增纯视觉层仍禁止调用随机接口。
    env.math=setmetatable({random=function(a,b) return b and math.floor((a+b)/2) or .5 end,
        randomseed=function() error("预览禁止重置gameplay RNG") end},{__index=math})
    local value=assert(load(source(name),"@真实战斗预览/" .. name,"t",env))()
    mods[name]=value;return value
end

local function makeSample(kind, elapsed)
    local bcs={cardAnims={},hitFlashes={},floatingTexts={},ftPool={}}
    local ally={heroId=1,classId="warrior",name="出手",level=1,hp=100,maxHp=100,atkProgress=0}
    local enemy={monsterId=1,name="受击",level=1,hp=100,maxHp=100,atkProgress=0}
    local fxState=Effects.newFxState();Effects.mount(fxState)
    if kind=="attack" then
        if phase=="charge" then ally.atkProgress=.97
        else
            Anim.playAttack(bcs,ally,true);bcs.cardAnims[ally].timer=elapsed
            if phase=="recover" then bcs.cardAnims[ally].state="return";bcs.cardAnims[ally].timer=.10 end
        end
    elseif kind=="death" then
        enemy.hp=0;Anim.set(bcs,enemy,{state="dying",timer=elapsed,lungeDir=-1})
    elseif kind=="enter" then
        local rear={heroId=1,classId="warrior",name="错峰",level=1,hp=100,maxHp=100,atkProgress=0}
        Anim.playEnter(bcs,{ally,rear},1);Anim.update(bcs,elapsed)
        return {bcs=bcs,fx=fxState,battle={allies={ally,rear},enemies={enemy}}}
    elseif kind=="recoil" then
        Anim.setRecoil(bcs,enemy,-1)
        if elapsed>=.08 then bcs.cardAnims[enemy].state="recoil_return";bcs.cardAnims[enemy].timer=elapsed-.08
        else bcs.cardAnims[enemy].timer=elapsed end
        Fx.setHitFlash(bcs,enemy);bcs.hitFlashes[enemy].timer=elapsed
    elseif kind=="heal" then
        Fx.addCombatNumber(bcs,ally,80,Layout.STRIP_ALLY_X0,180,
            {channel="heal",atkType=8,fontSize=65})
        Fx.updateFloatingTexts(bcs,elapsed)
    else
        Anim.setRecoil(bcs,enemy,-1);bcs.cardAnims[enemy].timer=math.min(.079,elapsed)
        Fx.addCombatNumber(bcs,enemy,240,Layout.STRIP_ENEMY_X0,180,
            {channel="damage",atkType=1,isCrit=true,fontSize=65})
        Fx.updateFloatingTexts(bcs,elapsed)
        Effects.spawn(2,Layout.STRIP_ENEMY_X0,180);Effects.update(elapsed)
    end
    return {bcs=bcs,fx=fxState,battle={allies={ally},enemies={enemy}}}
end

local canvas = UI.Widget:Extend("BattleMotionPreviewCanvas")
function canvas:Render(vg)
    if not imagesReady then
        -- 仅加载授权已有资产，不生成或修改任何媒体。
        local hero=nvgCreateImage(vg,"image/角色卡牌/KP_YX_1.png",0)
        local monster=nvgCreateImage(vg,"image/怪物卡牌/KP_GW_1.png",0)
        assert(hero>=0 and monster>=0,"原样本卡面必须真实可读")
        Draw.setContext({combat=mods["ui.battle.combat.BattleCombat"],imgHeroCards={[1]=hero},
            imgMonsterCards={[1]=monster},imgHpBg=-1,imgHpFill=-1,imgAllyTags={[2]=-1}})
        Effects.init(vg);View.init(vg);imagesReady=true
    end
    local rect=self:GetAbsoluteLayout()
    local scale=math.min(rect.w/948,rect.h/360)
    nvgSave(vg)
    nvgIntersectScissor(vg,rect.x,rect.y,rect.w,rect.h)
    nvgTranslate(vg,rect.x+(rect.w-948*scale)/2,rect.y+(rect.h-360*scale)/2)
    nvgScale(vg,scale,scale)
    for i,s in ipairs(samples) do
        if sample==s.kind then current=s;break end
    end
    Effects.mount(current.fx)
    Effects.setRenderScale(1)
    View.draw(vg,current.battle,nil,true)
    nvgRestore(vg)
    frames=frames+1
    if frames==120 then
        print(string.format("[battle_motion_preview] FRAME120 sample=%s phase=%s draw=%d realAnim/Effects/Draw/View=true playerIO=0 rng=isolated",sample,phase,frames))
    end
end

function Start()
    for _,arg in ipairs(GetArguments()) do
        if arg:find("-battle-motion-sample=",1,true)==1 then sample=arg:sub(23) end
        if arg:find("-battle-motion-phase=",1,true)==1 then phase=arg:sub(22) end
    end
    assert(sample=="attack" or sample=="recoil" or sample=="heal" or sample=="critical"
        or sample=="death" or sample=="enter",sample)
    mods["systems.GameBGM"]={};mods["ui.hud.popup.RedeemCodePanel"]={}
    mods["systems.ButtonFeedback"]={};mods["core.DarkIcon"]={}
    mods["core.I18n"]={LANGS={},t=function(s) return s end}
    Layout=loadReal("core.BattleLayout");loadReal("core.DrawUtil")
    loadReal("ui.hud.popup.SettingsPanel")
    loadReal("ui.battle.combat.BattleMotionPolish")
    mods["ui.battle.combat.ProjectileSystem"]={hasProjectile=function() return false end}
    Anim=loadReal("ui.battle.combat.BattleCombatAnim")
    mods["systems.AttributeDef"]=require("systems.AttributeDef")
    loadReal("core.NumberUtil");loadReal("ui.battle.scene.DamageTypeIcon")
    Fx=loadReal("ui.battle.combat.BattleCombatFx");Effects=loadReal("ui.battle.combat.BattleEffects")
    -- 完整ProjectileSystem用于View绘制；场景没有业务弹包，绝不启动战斗AI。
    mods["systems.GameSFX"]={};mods["systems.BattleStats"]={};mods["systems.BattleDiag"]={}
    mods["ui.battle.combat.ProjectileSystem"]=nil;loadReal("ui.battle.combat.ProjectileSystem")
    mods["systems.StatusEffectManager"]={getVisuals=function() return {} end}
    mods["systems.TalentManager"]={getConquerStacks=function() return 0 end}
    mods["systems.ExtraTalentSystem"]={drawOrbit=function() end,drawIceStatues=function() end}
    mods["config.HeroConfig"]={};loadReal("config.HeroAssetUtil")
    local combat={
        getCardAnimOffsetY=function(u) return Anim.getOffsetY(current.bcs,u) end,
        getChargeOffsetY=function(u,a) return Anim.getChargeOffsetY(current.bcs,u,a) end,
        getCardAnimArcY=function(u,a) return Anim.getArcOffsetY(current.bcs,u,a) end,
        getCardScale=function(u,a) return Anim.getCardScale(current.bcs,u,a) end,
        getAnimState=function(u) return Anim.getState(current.bcs,u) end,
        getTransitionAlpha=function(u) return Anim.getTransitionAlpha(current.bcs,u) end,
        getHitFlashAlpha=function(u) return Fx.getHitFlashAlpha(current.bcs,u) end,
        getHpBuffer=function() return 1 end,
        getFloatingTexts=function() return current.bcs.floatingTexts end,
        getCardCX=function() return 500 end,getCardCY=function() return 180 end,
    }
    mods["ui.battle.combat.BattleCombat"]=combat
    Draw=loadReal("ui.battle.scene.BattleDraw");View=loadReal("ui.battle.scene.BattleView")
    local durations=phase=="late" and {.10,.16,.45,.18,.34,.22} or {.03,.035,.12,.07,.12,.04}
    for i,kind in ipairs({"attack","recoil","heal","critical","death","enter"}) do
        local s=makeSample(kind,durations[i]);s.kind=kind;samples[#samples+1]=s
    end
    UI.Init({theme="default-dark",fonts={{family="sans",weights={normal="Fonts/MiSans-Regular.ttf"}}},
        scale=UI.Scale.DEFAULT})
    UI.SetRoot(UI.Panel{width="100%",height="100%",padding=18,gap=12,pointerEvents="none",
        backgroundColor={22,19,18,255},children={
            UI.Label{text="战斗动效 · " .. sample .. " / " .. phase,fontFamily="sans",fontWeight="normal",
                fontSize=22,fontColor={224,210,181,255}},
            UI.Label{text="原时长 / 纯视觉 / 局部冲击 / 受控时间样本",fontFamily="sans",fontWeight="normal",
                fontSize=13,fontColor={164,116,78,255}},
            canvas{width="100%",flexGrow=1,flexBasis=0,pointerEvents="none"},
        }})
    print("[battle_motion_preview] READY controlled elapsed; real shared modules; no main/player save")
end
function Stop()
    for _,s in ipairs(samples) do Effects.mount(s.fx);Effects.reset() end
    UI.Shutdown()
    print("[battle_motion_preview] STOP frames=" .. frames)
end
