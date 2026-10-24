-- 战斗动效独立验收：完整加载真实Anim/Fx/Effects/Draw/View；外围API显式spy。
-- 不启动main、不读玩家档、不发Action；旧Effects随机调用单独计数，新层严禁额外消费。
local TAG = "[battle_motion_test]"
local checks, failures = 0, 0
local sources = {}
local function check(ok, text)
    checks = checks + 1
    if not ok then failures = failures + 1; print(TAG .. " FAIL " .. text) end
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.000001 end
local function noop() end
local function source(name)
    local path = name:gsub("%.", "/") .. ".lua"
    if not sources[path] then
        local f = assert(cache:GetFile(path), path)
        local lines = {}; while not f:IsEof() do lines[#lines + 1] = f:ReadLine() end
        f:Dispose(); sources[path] = table.concat(lines, "\n")
    end
    return sources[path]
end
local function compile(name, mods, fields)
    local env = setmetatable({}, { __index = _G }); env._G = env
    for key, value in pairs(fields or {}) do env[key] = value end
    env.require = function(dep) return assert(mods[dep], "未声明依赖 " .. dep) end
    env.File = function() error("禁止玩家File") end
    env.fileSystem = setmetatable({}, { __index = function() error("禁止玩家FileSystem") end })
    env.SendEvent = function() error("视觉不能发事件") end
    env.time = setmetatable({}, { __index = function() error("视觉不能读wall clock") end })
    env.os = setmetatable({}, { __index = function() error("视觉不能读CPU/IO") end })
    env.math = setmetatable({ random = function() error("新增视觉消费RNG") end,
        randomseed = function() error("禁止重置RNG") end }, { __index = math })
    return assert(load(source(name), "@真实战斗动效/" .. name, "t", env))(), env
end

function Start()
    local ok, err = xpcall(function()
        local mods = {}
        local function real(name, fields)
            local module, env = compile(name, mods, fields); mods[name] = module; return module, env
        end
        -- Settings是真实模块，只有外围声明不执行；直接改变私有状态不调用保存接口。
        mods["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 } }
        mods["core.I18n"] = { LANGS = {}, t = function(s) return s end }
        mods["ui.hud.popup.RedeemCodePanel"] = {}
        mods["systems.GameBGM"] = {}
        mods["systems.ButtonFeedback"] = {}
        mods["core.DarkIcon"] = {}
        mods["cjson"] = require("cjson")
        local Layout = real("core.BattleLayout")
        local Util = real("core.DrawUtil")
        local Settings = real("ui.hud.popup.SettingsPanel")
        local settingsState
        for i = 1, 50 do
            local name, value = debug.getupvalue(Settings.isEffectsEnabled, i)
            if not name then break end
            if name == "state" then settingsState = value end
        end
        assert(settingsState, "真实设置状态未找到")
        settingsState.showEffects, settingsState.showDamageNumbers = true, true
        mods["ui.battle.combat.ProjectileSystem"] = { hasProjectile = function(id) return id == 2 end }
        local Motion = real("ui.battle.combat.BattleMotionPolish")
        local Anim = real("ui.battle.combat.BattleCombatAnim")
        mods["systems.AttributeDef"] = require("systems.AttributeDef")
        real("core.NumberUtil")
        local Icon, iconEnv = real("ui.battle.scene.DamageTypeIcon")
        local Fx = real("ui.battle.combat.BattleCombatFx")
        local countRandom = 0
        local Effect, effectEnv = real("ui.battle.combat.BattleEffects")
        effectEnv.math.random = function(a, b)
            countRandom = countRandom + 1
            if b then return math.floor((a + b) / 2) end
            if a then return math.max(1, math.floor(a / 2)) end
            return 0.5
        end
        local state = { cardAnims = {}, hitFlashes = {}, floatingTexts = {}, ftPool = {} }
        local unit = { hp = 100, maxHp = 100, atkProgress = 0.7, x = 123, y = 456,
            target = {}, hitbox = { x = 2 }, heroId = 1 }
        local target, hitbox = unit.target, unit.hitbox
        check(Anim.LUNGE_DURATION == .12 and Anim.RETURN_DURATION == .15
            and near(Anim.DEATH_ANIM_DURATION, .40) and Anim.REVIVE_ANIM_DURATION == .35,
            "所有导出旧时长精确保持")
        for _, entry in ipairs({ { "lunge", .12, 0, -60 }, { "return", .15, -60, 0 },
            { "recoil", .08, 0, -30 }, { "recoil_return", .12, -30, 0 },
            { "entering", .30, -100, 0 }, { "dying", .40, 0, -80 },
            { "reviving", .35, -80, 0 }, { "advance", .28, -100, 0 } }) do
            Anim.set(state, unit, { state = entry[1], timer = 0, lungeDir = -1, advanceDist = 100 })
            check(near(Anim.getOffsetY(state, unit), entry[3]), entry[1] .. "旧起点")
            state.cardAnims[unit].timer = entry[2]
            check(near(Anim.getOffsetY(state, unit), entry[4]), entry[1] .. "旧终点")
        end
        Anim.clear(state, unit)
        check(near(Anim.getChargeOffsetY(state, unit, true), 0), "蓄力起点0.7")
        unit.atkProgress = 1
        check(near(Anim.getChargeOffsetY(state, unit, true), 25), "蓄力终点25")
        Anim.playAttack(state, unit, true)
        state.cardAnims[unit].timer = .012
        local prepare = Anim.getOffsetY(state, unit)
        state.cardAnims[unit].timer = .07
        local strike = Anim.getOffsetY(state, unit)
        check(prepare > 0 and strike < -40, "已有0.12秒内收势→发力真实采样不同")
        state.cardAnims[unit].timer = 0
        Anim.update(state, .119)
        check(Anim.getState(state, unit) == "lunge", "0.119仍原lunge阶段")
        Anim.update(state, .0011)
        check(Anim.getState(state, unit) == "return" and state.cardAnims[unit].timer == 0,
            "旧阶段切换与原超额dt处理不改")
        state.cardAnims[unit].timer = .105
        check(Anim.getOffsetY(state, unit) > 0 and Anim.getOffsetY(state, unit) < 4,
            "迅速回位末段≤6%回弹")
        Anim.update(state, .046)
        check(Anim.getState(state, unit) == nil, "原0.15秒回位完成移除")
        Anim.setRecoil(state, unit, -1)
        Anim.update(state, .08)
        check(Anim.getState(state, unit) == "recoil_return", "受击仍0.08切换")
        Anim.update(state, .12)
        check(Anim.getState(state, unit) == nil, "受击回弹仍0.12移除")
        local dead = { hp = 0 }
        Anim.set(state, dead, { state = "dying", timer = 0, lungeDir = 1 })
        Anim.setRecoil(state, dead, -1)
        Anim.update(state, .059)
        check(Anim.getState(state, dead) == "dying" and Anim.getOffsetY(state, dead) == 0,
            "旧死亡0.06局部阶段保留，不是战斗hitstop")
        state.cardAnims[dead].timer = .28
        check(near(Anim.getOffsetY(state, dead), 92), "死亡0.22段原超调终点92")
        state.cardAnims[dead].timer = .34
        check(Anim.getArcOffsetY(state, dead) > 0, "死亡中段轻沉降")
        state.cardAnims[dead].timer = .399
        Anim.update(state, .002)
        check(Anim.getState(state, dead) == "gone", "原0.40 gone，不延长等待")
        local enters = { {}, {}, {}, {} }
        Anim.playEnter(state, enters, 1)
        for i, u in ipairs(enters) do check(near(state.cardAnims[u].delay, (i-1)*.06), "原错峰" .. i) end
        Anim.update(state, .09)
        check(near(state.cardAnims[enters[2]].timer, .03) and state.cardAnims[enters[3]].delay > 0,
            "错峰结束只吸收超出dt")
        local ranged = { hp = 100, heroId = 2, atkProgress = 1 }
        check(near(Anim.getCardScale(state, ranged), .85), "远程蓄力旧缩放端点")
        Anim.playAttack(state, ranged, true); state.cardAnims[ranged].timer = .12
        check(near(Anim.getCardScale(state, ranged), 1.15) and Anim.getOffsetY(state, ranged) == 0,
            "远程发力缩放旧端点且权威无平移")
        state.cardAnims[ranged].state = "return"; state.cardAnims[ranged].timer = .15
        check(near(Anim.getCardScale(state, ranged), 1), "远程回位端点1")

        -- 旧随机消费精确计数；新的setupImpact/drawImpact从不接触全局RNG。
        local expected = {49,48,42,54,54}
        for armor = 1, 5 do
            Effect.reset(); local before = countRandom
            Effect.spawn(armor, 500, 180)
            check(countRandom - before == expected[armor], "护甲" .. armor .. "旧RNG次数=" .. expected[armor])
            check(Effect.getPoolStats().motionLayers == 1, "低频落点一层增强" .. armor)
            local fx = Effect.mountedState().effects[1]
            local duration = ({.45,.35,.35,.40,.50})[armor]
            check(fx.duration == duration and fx.timer == 0, "旧效果寿命" .. armor)
        end
        Effect.reset(); local before = countRandom
        Effect.spawnSilverFlash(500, 180)
        check(countRandom - before == 1 and Effect.getPoolStats().motionLayers == 0,
            "银光旧一次RNG，不附第二增强层")
        Effect.reset()
        for i = 1, 20 do Effect.spawn(2, 500, 180) end
        check(Effect.getPoolStats().motionLayers == 1, "同帧多hit仅首层，不叠满增强")
        for _ = 1, 20 do Effect.update(.01); Effect.spawn(2, 500, 180) end
        check(Effect.getPoolStats().motionLayers == 1, "连续DOT/HOT式频率严格抑制新增层")
        Effect.reset()
        for i = 1, 40 do Effect.spawn(2, i*35, 180) end
        check(Effect.getPoolStats().motionLayers == 12, "全mounted场景增强层硬上限12")
        for i = 1, 4000 do
            Effect.spawn((i%5)+1, (i%100)*35, 180)
            if i%50 == 0 then
                local stats = Effect.getPoolStats()
                check(Effect.getActiveCount() <= 48 and stats.motionLayers <= 12
                    and stats.effects <= 48 and stats.particleArrays <= 192, "高hit压力池有界" .. i)
            end
        end
        Effect.reset()
        local stats = Effect.getPoolStats()
        check(Effect.getActiveCount() == 0 and stats.motionLayers == 0 and stats.effects > 0,
            "reset真实回收不是丢弃活动对象")
        Effect.spawnSilverFlash(500, 180)
        check(Effect.getPoolStats().motionLayers == 0, "池复用无残留增强标记")

        -- 私有NanoVG观察器捕获真实Draw/View/Effects路径，不修改全局绑定。
        local calls, pathLog, depth, scissor = {}, {}, 0, {0,0,948,360}
        local stack = {}
        local graphicsFields = {}
        for _, key in ipairs({ "nvgBeginPath", "nvgFill", "nvgStroke", "nvgCircle", "nvgRect",
            "nvgRoundedRect", "nvgEllipse", "nvgMoveTo", "nvgLineTo", "nvgQuadTo", "nvgClosePath",
            "nvgTranslate", "nvgRotate", "nvgScale", "nvgLineCap", "nvgStrokeWidth", "nvgStrokeColor",
            "nvgFillColor", "nvgFillPaint", "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgGlobalAlpha" }) do
            graphicsFields[key] = function(...)
                calls[key] = (calls[key] or 0) + 1
                if key == "nvgMoveTo" or key == "nvgQuadTo" then pathLog[#pathLog+1] = {key,...} end
            end
        end
        graphicsFields.nvgText = function() calls.text = (calls.text or 0) + 1 end
        graphicsFields.nvgTextBounds = function() return 20 end
        graphicsFields.nvgImagePattern = function() return {} end
        graphicsFields.nvgRadialGradient = function() return {} end
        graphicsFields.nvgRGBA = function(...) return {...} end
        graphicsFields.nvgSave = function() depth=depth+1; stack[depth]=scissor end
        graphicsFields.nvgRestore = function() scissor=assert(stack[depth]); stack[depth]=nil; depth=depth-1 end
        graphicsFields.nvgScissor = function(_,x,y,w,h) scissor={x,y,w,h} end
        graphicsFields.nvgIntersectScissor = function(_,x,y,w,h)
            calls.intersect=(calls.intersect or 0)+1; scissor={x,y,w,h}
        end
        graphicsFields.nvgCreateImage = function() return -1 end
        graphicsFields.nvgBeginFrame = function() error("共享模块不能BeginFrame") end
        for key,value in pairs(graphicsFields) do effectEnv[key]=value; iconEnv[key]=value end
        local _, motionEnv = compile("ui.battle.combat.BattleMotionPolish", mods, graphicsFields)
        -- Effect持有的Motion也使用私有观察器，但数学曲线仍是真实实现。
        local observedMotion = assert(load(source("ui.battle.combat.BattleMotionPolish"), "@真实motion图形", "t", motionEnv))()
        mods["ui.battle.combat.BattleMotionPolish"] = observedMotion
        Effect, effectEnv = real("ui.battle.combat.BattleEffects", graphicsFields)
        effectEnv.math.random = function(a,b) countRandom=countRandom+1; return b and math.floor((a+b)/2) or .5 end
        mods["systems.StatusEffectManager"] = { getVisuals = function() return {} end }
        mods["systems.TalentManager"] = { getConquerStacks = function() return 0 end }
        mods["systems.ExtraTalentSystem"] = { drawOrbit = noop, drawIceStatues = noop }
        mods["config.HeroAssetUtil"] = { getCardPath = function() return "unused" end }
        local Draw = real("ui.battle.scene.BattleDraw", graphicsFields)
        local mounted = state
        local combat = {
            getCardAnimOffsetY = function(u) return Anim.getOffsetY(mounted,u) end,
            getChargeOffsetY = function(u,a) return Anim.getChargeOffsetY(mounted,u,a) end,
            getCardAnimArcY = function(u,a) return Anim.getArcOffsetY(mounted,u,a) end,
            getCardScale = function(u,a) return Anim.getCardScale(mounted,u,a) end,
            getAnimState = function(u) return Anim.getState(mounted,u) end,
            getTransitionAlpha = function(u) return Anim.getTransitionAlpha(mounted,u) end,
            getHitFlashAlpha = function(u) return Fx.getHitFlashAlpha(mounted,u) end,
            getHpBuffer = function() return 1 end,
            getFloatingTexts = function() return mounted.floatingTexts end,
            getCardCX = function() return 500 end, getCardCY = function() return 180 end,
        }
        mods["ui.battle.combat.BattleCombat"] = combat
        mods["ui.battle.combat.ProjectileSystem"] = {
            draw = function() calls.projectile=(calls.projectile or 0)+1 end,
            drawStarGates = function() calls.gates=(calls.gates or 0)+1 end,
        }
        Draw.setContext({ combat=combat, imgHeroCards={}, imgMonsterCards={}, imgHpBg=-1,
            imgHpFill=-1, imgAllyTags={} })
        -- 完整DrawUtil观察器透过真实常量，文字仍沿原文本系统。
        local utilEnv=setmetatable({require=function() return Layout end},{__index=_G})
        for k,v in pairs(graphicsFields) do utilEnv[k]=v end
        local UtilSpy=assert(load(source("core.DrawUtil"),"@真实DrawUtil观察","t",utilEnv))()
        mods["core.DrawUtil"]=UtilSpy
        Draw=real("ui.battle.scene.BattleDraw",graphicsFields)
        Draw.setContext({combat=combat,imgHeroCards={},imgMonsterCards={},imgHpBg=-1,imgHpFill=-1,imgAllyTags={}})
        local View=real("ui.battle.scene.BattleView",graphicsFields)
        Fx.resetFloatingTexts(state)
        Fx.addFloatingText(state,"+80",500,180,{170,190,160},false,80,false,"heal")
        unit.name,unit.level,unit.heroId,unit.classId="样本",1,nil,"warrior"
        Draw.setContext({combat=combat,imgHeroCards={},imgMonsterCards={},imgHpBg=-1,
            imgHpFill=-1,imgAllyTags={[2]=-1}})
        local battle={allies={unit},enemies={}}
        for _, host in ipairs({"tri","tower"}) do
            settingsState.showEffects,settingsState.showDamageNumbers=false,false
            calls={}; View.draw({},battle,nil,true)
            check(not calls.projectile and not calls.gates and calls.text,
                host .. "关闭效果保留卡牌名称/生命/等级文本")
            -- 卡片名称原文本是必要内容，上项只对空战场验证数字出口。
            calls={}; View.draw({},{allies={},enemies={}},nil,true)
            check(not calls.projectile and not calls.gates and not calls.text,host .. "空场off精确draw skip")
            settingsState.showDamageNumbers=true; calls={}; View.draw({},{},nil,true)
            check(calls.text and not calls.projectile and not calls.gates,host .. "数字开/效果关独立")
            settingsState.showDamageNumbers=false;settingsState.showEffects=true
            calls={}; View.draw({},{},nil,true)
            check(not calls.text and calls.projectile==1 and calls.gates==2,host .. "数字关/效果开独立")
        end
        settingsState.showEffects=true
        Effect.mount(Effect.newFxState());Effect.spawn(2,500,180);Effect.update(.07)
        pathLog={};before=countRandom; Effect.draw({}); local firstPath=pathLog[1]
        check(firstPath and countRandom==before and depth==0,"真实效果draw不消费RNG且save/restore平衡")
        local timer=Effect.mountedState().effects[1].timer
        for _=1,10 do Effect.draw({}) end
        check(Effect.mountedState().effects[1].timer==timer,"同帧重复draw不推进timer")
        Effect.update(.10);pathLog={};Effect.draw({})
        check(pathLog[1] and (pathLog[1][3]~=firstPath[3] or pathLog[1][4]~=firstPath[4]),"不同elapsed实际轨迹变化")
        Effect.reset();Effect.spawnSilverFlash(500,180);Effect.update(.10)
        local originalScissor=scissor;calls={};Effect.draw({})
        check(calls.intersect==1 and scissor==originalScissor and depth==0,"银光既有卡片scissor保留并还原宿主裁剪")
        local laneA=Effect.mountedState();local laneB=Effect.newFxState();Effect.mount(laneB)
        check(Effect.getActiveCount()==0,"换挂载不串场")
        Effect.spawn(2,800,180);Effect.update(.1);Effect.mount(laneA)
        check(near(laneA.effects[1].timer,.1) and near(laneB.effects[1].timer,.1),"只更新mounted寿命")
        settingsState.showEffects=false;calls={};Effect.draw({})
        check(next(calls)==nil,"classic/dungeon共享出口也立即停止新视觉")
        Effect.update(1);check(Effect.getActiveCount()==0,"效果关闭update仍回收")
        Anim.playAttack(state,unit,true);Anim.setRecoil(state,unit,1)
        check(Anim.getOffsetY(state,unit)==0 and Anim.getChargeOffsetY(state,unit,true)==0,
            "关闭效果屏蔽攻击/蓄力/受击")
        Anim.playEnter(state,{unit},1);Anim.update(state,.15)
        check(Anim.getState(state,unit)=="entering" and Anim.getTransitionAlpha(state,unit)>0,
            "关闭效果必要入场继续")
        settingsState.showEffects=true
        Fx.setHitFlash(state,unit);check(Fx.getHitFlashAlpha(state,unit)==72,"局部闪光峰值72不频闪")
        Fx.updateHitFlashes(state,.15);check(Fx.getHitFlashAlpha(state,unit)<20,"低亮回声快速衰减")
        Fx.updateHitFlashes(state,.15);check(state.hitFlashes[unit]==nil,"仍0.3秒回收")

        -- 真实双时钟扣暂停区间；宿主按照既有pause策略跳update，重复draw仍无增量。
        local wall={elapsedTime=100};local cpu=10
        local clockEnv=setmetatable({time=wall,os={clock=function() return cpu end}},{__index=_G})
        local Clock=assert(load(source("ui.battle.combat.BattleClock"),"@真实BattleClock","t",clockEnv))()
        Anim.playAttack(state,unit,true);Effect.mount(laneB)
        local animTime=state.cardAnims[unit].timer;local fxTime=laneB.effects[1].timer
        Clock.setPaused(true);wall.elapsedTime=140;cpu=30
        for _=1,5 do
            if not Clock.isPaused() then Anim.update(state,5);Effect.update(5) end
            Anim.getOffsetY(state,unit);Effect.draw({})
        end
        check(Clock.now()==100 and Clock.cpuNow()==10 and state.cardAnims[unit].timer==animTime
            and laneB.effects[1].timer==fxTime,"pausetime真正freeze动画/效果与双时钟")
        Clock.setPaused(false);wall.elapsedTime=141;cpu=31
        check(Clock.now()==101 and Clock.cpuNow()==11,"恢复扣除区间但保留活动时间")
        check(unit.hp==100 and unit.x==123 and unit.y==456 and unit.target==target
            and unit.hitbox==hitbox,"全部视觉测试不写权威位置/hitbox/target/伤害")
        for _,name in ipairs({"ui.battle.combat.BattleCombatAnim","ui.battle.combat.BattleCombatFx",
            "ui.battle.combat.BattleMotionPolish","ui.battle.combat.BattleEffects","ui.battle.scene.BattleView"}) do
            local s=source(name)
            check(not s:find("nvgBeginFrame",1,true) and not s:find("SendEvent(",1,true)
                and not s:find("randomseed",1,true) and not s:find("File(",1,true),name .. "事件/IO/BeginFrame保留")
        end
        check(near(Motion.launch(0),0) and near(Motion.launch(1),1) and near(Motion.recover(0),1)
            and near(Motion.recover(1),0),"pure easing精确端点")
        check(Icon~=nil and Util~=nil,"原文本/图标/坐标系统完整加载")
    end,debug.traceback)
    if not ok then failures=failures+1;print(TAG .. " HARNESS_ERROR " .. tostring(err)) end
    print(string.format("%s RESULT checks=%d failures=%d %s",TAG,checks,failures,failures==0 and "ALL PASS" or "FAILED"))
    if failures>0 then error(TAG .. " FAILED") end
    engine:Exit()
end
