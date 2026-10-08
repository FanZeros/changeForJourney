-- 敌死生命周期回归：真实宿主方法 + 正式 TAL/ETS/属性，不读取或写入真实英雄存档。
-- 仅替换持久化边界、编队数据和剧情阻挡；不替换被测死亡/补位/胜负方法。
-- 跑法：.cli/UrhoXRuntime tests/enemy_death_lifecycle_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
local failures, assertions = 0, 0

local function check(ok, message)
    assertions = assertions + 1
    if ok then
        print("[EnemyDeath][PASS] " .. message)
    else
        failures = failures + 1
        print("[EnemyDeath][FAIL] " .. message)
    end
end

local function case(name, fn)
    local ok, err = pcall(fn)
    if not ok then check(false, name .. "异常: " .. tostring(err)) end
end

function Start()
    local restores = {}
    local function patch(object, key, value)
        local original = object[key]
        restores[#restores + 1] = function() object[key] = original end
        object[key] = value
        return original
    end

    local ok, err = pcall(function()
        local AD = require("systems.AttributeDef")
        local HC = require("config.HeroConfig")
        local MC = require("config.MonsterConfig")
        local SC = require("config.StageConfig")
        local TAL = require("systems.TalentManager")
        local ETS = require("systems.ExtraTalentSystem")
        local SEM = require("systems.StatusEffectManager")
        local BC = require("ui.battle.combat.BattleCombat")
        local Driver = require("ui.battle.tri.BattleTriDriver")
        local Casualty = require("ui.battle.combat.BattleCasualty")
        local DungeonScene = require("ui.dungeon.DungeonBattleScene")
        local DungeonScope = require("ui.dungeon.DungeonBattleScope")
        local DC = require("config.DungeonConfig")
        local Layout = require("core.BattleLayout")
        local DB = require("ui.dungeon.DungeonBattle")
        local Tower = require("ui.tower.TowerTriBattle")
        local CP = require("ui.character.panel.CharacterPanel")
        local GameAction = require("runtime.GameAction")
        local Dispatcher = require("runtime.ClientDispatcher")
        local BattleScene = require("ui.battle.scene.BattleScene")
        local own = {}
        local actions = {}
        local oldGet = Dispatcher.get
        patch(Dispatcher, "get", function(key)
            if key == "heroes" then return { roster = own } end
            return oldGet(key)
        end)
        patch(CP, "getOwnedHero", function(id) return own[tonumber(id)] end)
        patch(CP, "patchExtraTalent", function(id, extra)
            local owned = own[tonumber(id)]
            if owned then owned.extraTalent = ETS.normalize(extra) end
        end)
        patch(GameAction, "sendAction", function(action, data)
            actions[#actions + 1] = { action = action, data = data }
        end)
        patch(BattleScene, "restoreContext", function() end)
        patch(require("boot.StandaloneSave"), "Flush", function() end)

        local events = {}
        local frozenAtDeath = {}
        local oldEnemyHook = ETS.onEnemyDeath
        patch(ETS, "onEnemyDeath", function(dead, allies, enemies)
            events[dead] = (events[dead] or 0) + 1
            frozenAtDeath[dead] = SEM.has(dead, SEM.FROZEN)
            return oldEnemyHook(dead, allies, enemies)
        end)

        local function clear()
            TAL.reset()
            TAL.mount(nil)
            SEM.mount(nil)
            SEM.reset()
            BC.mount(nil)
            BC.reset()
            own = {}
            events = {}
            frozenAtDeath = {}
            actions = {}
        end

        local function hero(id, first, second)
            local awakening = { [1] = first == true, [2] = second == true, _awk3Migrated = true }
            own[id] = { awakening = awakening, extraTalent = ETS.normalize(nil) }
            return assert(HC.createHero(id, 1, nil, awakening, own[id].extraTalent))
        end

        local function enemy()
            local unit = assert(MC.createMonster(1, 1))
            unit.attrs.energyShield = 0
            unit.attrs.tempEnergyShield = 0
            return unit
        end

        local function kill(unit, killer)
            unit.attrs.final[AD.HP] = 0
            unit.hp = 0
            unit._killedBy = killer
        end

        local function driver(allies, enemies)
            local drv = Driver.new(2)
            drv.stageId = 101
            drv.allies, drv.enemies = allies, enemies
            drv.enemyQueue = {}
            drv.active = true
            drv:activate()
            for _, u in ipairs(allies) do TAL.initUnit(u) end
            for _, u in ipairs(enemies) do TAL.initUnit(u) end
            TAL.onBattleStart(allies, enemies)
            return drv
        end

        case("三行扫描/成长/奖励/复活", function()
            clear()
            local dog, e1, e2 = hero(1, true), enemy(), enemy()
            local drv = driver({ dog }, { e1, e2 })
            kill(e1, dog)
            kill(e2, dog)
            drv:reportDefeatedEnemies()
            drv:reportDefeatedEnemies()
            check(events[e1] == 1 and events[e2] == 1, "同帧双死、两次真实扫描，每只事件一次")
            check(own[1].extraTalent.stacks == 2, "生产大狗 ETS 击杀成长准确两层")
            check(drv.kills == 2 and #drv.pendingKills == 2, "三行奖励账本独立，每只奖励一次")
            check(e1._killedBy == dog, "死亡后击杀来源保留到事件/奖励消费")
            e1.attrs:fillHp()
            BC.syncUnitHp(e1)
            drv:reportDefeatedEnemies()
            check(e1._talEnemyDeathReported == nil and e1._killedBy == nil, "复活存活扫描恢复标记并清旧归因")
            kill(e1, dog)
            drv:reportDefeatedEnemies()
            check(events[e1] == 2 and own[1].extraTalent.stacks == 3, "同一敌人复活再死重新分发成长")
            check(drv.kills == 3 and #drv.pendingKills == 3, "复活后的奖励不被永久锁死")
        end)

        case("延迟补位前冻结事件", function()
            clear()
            local snow, e = hero(12, true, true), enemy()
            local drv = driver({ snow }, { e })
            SEM.apply(e, SEM.FROZEN, 10, snow, {})
            kill(e, snow)
            drv:tick(0.01)
            check(events[e] == 1 and frozenAtDeath[e] == true, "三行 tick 首次死即分发，冻结尚未清理")
            check(#ETS.getIceStatues() == 1 and own[12].extraTalent.iceStatues == 1, "正式 ETS 生成一个冰雕")
            check(not SEM.has(e, SEM.FROZEN) and #drv.enemies == 1, "发事件后清状态，但延迟退场单位还在")
            drv:tick(0.01)
            check(events[e] == 1 and #ETS.getIceStatues() == 1, "死亡淡出再次 tick 不重复冰雕")
            drv:tick(1.1)
            check(#drv.enemies == 0, "退场完成才移除最后敌人")
        end)

        case("首通轻量驱动最后敌人", function()
            clear()
            local dog = hero(1, true)
            local drv = Driver.new(2, { battleLab = true, firstClear = true,
                allyFactory = function() return { dog } end })
            drv:start(101)
            local total = #drv.enemies
            local original = {}
            for _, e in ipairs(drv.enemies) do original[#original + 1] = e; kill(e, dog) end
            for _, e in ipairs(drv.enemyQueue) do original[#original + 1] = e end
            -- 保留当前生产首通出怪，直接清空后备只测试最后场上敌人早返。
            drv.enemyQueue = {}
            drv.introTimer = 0
            for _ = 1, 10 do drv:update(0.5) end
            local allOnce = true
            for i = 1, total do if events[original[i]] ~= 1 then allOnce = false end end
            check(allOnce and drv._clearReported == true, "首通实验真实 start/update 最后敌人先分发再清场")
            check(drv.active == false and #drv.pendingKills == 0, "首通实验无正式奖励/推关副作用")
        end)

        case("旧单场兼容", function()
            clear()
            local dog, e = hero(1, true), enemy()
            BC.setContext({ getAllies = function() return { dog } end, getEnemies = function() return { e } end })
            TAL.initUnit(dog)
            TAL.onBattleStart({ dog }, { e })
            kill(e, dog)
            TAL.onEnemyDeath(e, { dog }, { e }) -- 命中端已经即时分发
            local rewards, victories = 0, 0
            local ctx = {
                allies = { dog }, enemies = { e }, enemyQueue = {},
                getCardCX = BC.getCardCX, getAliveUnits = BC.getAliveUnits,
                syncUnitHp = BC.syncUnitHp, RESPAWN_DELAY = 1,
                reinforceCdByList = {}, ENEMY_CARD_CY = 100, ALLY_CARD_CY = 200,
                currentStageId = 101, stageName = "生命周期回归", isFirstClear = true,
                clearedStages = {}, waveKillCount = 0, waveGoldEarned = 0, waveExpEarned = 0,
                onEnemyKillCallback = function() rewards = rewards + 1 end,
                onEnemyDropCallback = function() end,
                settleWaveEfficiency = function() end, resetWaveTimers = function() end,
                getStageConfig = function() return SC end,
                beginVictoryMarch = function() victories = victories + 1 end,
            }
            local consumed = Casualty.process(ctx, 0.01)
            Casualty.process(ctx, 0.01)
            check(consumed and events[e] == 1 and own[1].extraTalent.stacks == 1, "旧单场消费已有死亡事件不重复成长")
            check(rewards == 1 and victories == 1 and ctx.clearedStages[101] == true, "旧单场奖励及首通记账未破坏")
        end)

        case("真实大狗驱动伤害成长", function()
            clear()
            local dog, e = hero(1, true), enemy()
            local drv = driver({ dog }, { e })
            BC.dealDamageToUnit(e, e.maxHp * 100, false, "", nil, dog)
            drv:tick(0)
            check(events[e] == 1 and own[1].extraTalent.stacks == 1 and e._killedBy == dog,
                "生产大狗经真实 drv mounted 伤害/tick 击杀成长一次")
        end)

        case("蓝鱼任意击杀永久魔攻与重复死亡", function()
            clear()
            local fish, e1, e2 = hero(17, true), enemy(), enemy()
            local baseMag = fish.attrs:get(AD.MAG_ATK)
            local drv = driver({ fish }, { e1, e2 })
            -- 非潮湿/非暴击目标，经真实伤害立即分发，宿主扫描只能消费同一生命一次。
            BC.dealDamageToUnit(e1, e1.maxHp * 100, false, "", nil, fish)
            drv:reportDefeatedEnemies()
            drv:reportDefeatedEnemies()
            check(events[e1] == 1 and own[17].extraTalent.stacks == 1
                and math.abs(fish.attrs:get(AD.MAG_ATK) - baseMag - 0.2) < 1e-8,
                "蓝鱼普通击杀经真实伤害/扫描只加1层，永久魔攻+0.2")
            SEM.apply(e2, SEM.VULNERABLE, 3, fish, { fromFatFish = true, mult = 0.30 })
            BC.dealDamageToUnit(e2, e2.maxHp * 100, false, "", nil, fish, { isDot = true })
            drv:reportDefeatedEnemies()
            check(events[e2] == 1 and own[17].extraTalent.stacks == 2
                and math.abs(fish.attrs:get(AD.MAG_ATK) - baseMag - 0.4) < 1e-8,
                "蓝鱼潮湿/DOT击杀同样加1，二次累计永久魔攻+0.4")
            e1.attrs:fillHp(); BC.syncUnitHp(e1)
            drv:reportDefeatedEnemies()
            BC.dealDamageToUnit(e1, e1.maxHp * 100, false, "", nil, fish)
            drv:reportDefeatedEnemies()
            check(events[e1] == 2 and own[17].extraTalent.stacks == 3
                and math.abs(fish.attrs:get(AD.MAG_ATK) - baseMag - 0.6) < 1e-8,
                "蓝鱼复活敌人再死重新成长，扫描不重复，累计+0.6")
            local rebuilt = assert(HC.createHero(17, 1, nil, own[17].awakening, own[17].extraTalent))
            check(math.abs(rebuilt.attrs:get(AD.MAG_ATK) - fish.attrs:get(AD.MAG_ATK)) < 1e-8,
                "蓝鱼既有stacks重建得到同一永久魔攻，无新增档字段")
        end)

        case("蓝鱼未觉醒与敌方禁用", function()
            clear()
            local fish, target = hero(17), enemy()
            local baseMag = fish.attrs:get(AD.MAG_ATK)
            local drv = driver({ fish }, { target })
            BC.dealDamageToUnit(target, target.maxHp * 100, false, "", nil, fish)
            drv:reportDefeatedEnemies()
            check(events[target] == 1 and own[17].extraTalent.stacks == 0
                and fish.attrs:get(AD.MAG_ATK) == baseMag,
                "蓝鱼未觉醒仍分发真实死亡，但不成长/加魔攻")
            clear()
            local enemyFish = assert(HC.createHero(17, 1, nil,
                { [1] = true, _awk3Migrated = true }, false))
            local ally = hero(1, true)
            local enemyDrv = driver({ ally }, { enemyFish })
            own[17] = { awakening = { [1] = true, _awk3Migrated = true }, extraTalent = ETS.normalize(nil) }
            BC.dealDamageToUnit(ally, ally.maxHp * 100, true, "", nil, enemyFish)
            enemyDrv:reportDefeatedEnemies()
            check(enemyFish._etsDisabled == true and own[17].extraTalent.stacks == 0,
                "敌方蓝鱼extraTalent=false真实击杀不写本地成长")
            local fakeTarget = enemy()
            kill(fakeTarget, enemyFish)
            TAL.onEnemyDeath(fakeTarget, { enemyFish }, { fakeTarget })
            check(events[fakeTarget] == 1 and own[17].extraTalent.stacks == 0,
                "敌方禁用标记即使走敌死钩也不叠层")
        end)

        case("蓝鱼潮湿溅射阶段与致死时序", function()
            for stage = 0, 3 do
                clear()
                local fish, target, splash = hero(17, stage >= 1, stage >= 2), enemy(), enemy()
                if stage >= 3 then
                    fish.awakeningNodes[3], own[17].awakening[3] = true, true
                end
                local drv = driver({ fish }, { target, splash })
                local baseMag = fish.attrs:get(AD.MAG_ATK)
                local observedBase, wetBeforeDamage, insideEvents = 0, false, -1
                TAL.onAfterAttack(fish, target, { category = "magical", totalDamage = 1 }, true,
                    { target, splash }, function(tgt, dmg)
                        observedBase = dmg
                        wetBeforeDamage = SEM.has(target, SEM.VULNERABLE) and not SEM.has(tgt, SEM.VULNERABLE)
                    end, { fish })
                local wet = SEM.get(target, SEM.VULNERABLE)
                local splashWet = SEM.get(splash, SEM.VULNERABLE)
                check(wet and splashWet and wetBeforeDamage and wet.data.fromFatFish
                    and math.abs(wet.remaining - (stage >= 1 and 3 or 2)) < 1e-8
                    and wet.data.mult == (stage >= 1 and 0.30 or 0.20)
                    and wet.data.atkSpeedDebuff == (stage >= 2 and 10 or nil)
                    and wet.data.critVuln == (stage >= 3 and 10 or nil),
                    "蓝鱼阶段" .. stage .. "主目标先潮湿/溅射后潮湿，持续增伤减速易暴击原样")
                check(observedBase > 0, "蓝鱼阶段" .. stage .. "仍执行真实溅射计算")
                -- 同一敌人只剩1HP，真实额伤会致死；成长只在本轮后攻击结束分发。
                splash.attrs.final[AD.HP], splash.hp = 1, 1
                TAL.onAfterAttack(fish, target, { category = "magical", totalDamage = 1 }, true,
                    { target, splash }, function(tgt, dmg, isAlly, prefix, color, opts)
                        BC.dealTalentDamage(fish, tgt, dmg, isAlly, prefix, color, opts)
                        insideEvents = events[tgt] or 0
                    end, { fish })
                check(insideEvents == 0 and splash.hp <= 0 and events[splash] == 1
                    and own[17].extraTalent.stacks == (stage >= 1 and 1 or 0),
                    "蓝鱼阶段" .. stage .. "同步溅射死亡仍在整轮后攻击末尾消费，已觉醒才成长")
                check(math.abs(fish.attrs:get(AD.MAG_ATK) - baseMag - (stage >= 1 and 0.2 or 0)) < 1e-8,
                    "蓝鱼阶段" .. stage .. "魔攻增长不回插改本次溅射")
                drv:reportDefeatedEnemies()
                check(events[splash] == 1, "蓝鱼阶段" .. stage .. "溅射后死亡扫描仍幂等")
            end
        end)

        case("真实额伤/DOT与连击", function()
            clear()
            local snow, e = hero(12, true, true), enemy()
            local drv = driver({ snow }, { e })
            SEM.apply(e, SEM.FROZEN, 10, snow, {})
            BC.dealDamageToUnit(e, e.maxHp * 100, false, "", nil, snow, { isDot = true })
            check(events[e] == 1 and frozenAtDeath[e] and #ETS.getIceStatues() == 1, "真实 DOT 伤害入口致死立即生成冰雕，不等扫描")
            drv:reportDefeatedEnemies()
            check(events[e] == 1, "即时伤害分发与宿主扫描去重")
            e.attrs:fillHp()
            BC.syncUnitHp(e)
            local state = BC.mountedState()
            snow.attrs:addModifier("test_combo", { { key = AD.MAG_ATK, flat = 1000000 } })
            state.comboQueue[1] = { attacker = snow, targetRef = e, isAlly = true,
                targetIsAlly = false, timer = 0, delay = 0, comboHitIndex = 1 }
            BC.updateComboQueue(0)
            require("ui.battle.combat.ProjectileSystem").update(2)
            check(e.hp <= 0 and events[e] == 2 and e._killedBy == snow, "真实连击队列复活再击杀，来源与新生命事件可恢复")
        end)

        case("本次攻击后条件早于死亡消费", function()
            clear()
            local conquer, target = hero(5, true, true), enemy()
            local drv = driver({ conquer }, { target })
            -- 先用正常后攻击钩积到19/20，最后一刀必须同时达满层和击杀。
            for _ = 1, 19 do
                TAL.onAfterAttack(conquer, target, { category = "physical", totalDamage = 1 }, true,
                    { target }, function() end, { conquer })
            end
            check(TAL.getConquerStacks(conquer) == 19 and not conquer._conquerFullKill,
                "征服首次满层对照：此前19层不提前产生携带")
            target.attrs.final[AD.HP], target.hp = 1, 1
            BC.performAttack(conquer, { target }, true)
            require("ui.battle.combat.ProjectileSystem").update(2)
            check(target.hp <= 0 and own[5].extraTalent.conquerCarry == 1,
                "首次满20层致死先写本次条件，死亡事件保留征服携带")
            drv:reportDefeatedEnemies()
            check(own[5].extraTalent.conquerCarry == 1 and events[target] == 1,
                "首次满层死亡扫描不重复携带")

            clear()
            local rhymeConquer, rhymeTarget = hero(5, true, true), enemy()
            local rhymeDriver = driver({ rhymeConquer }, { rhymeTarget })
            for _ = 1, 19 do
                TAL.onAfterAttack(rhymeConquer, rhymeTarget, { category = "physical", totalDamage = 1 }, true,
                    { rhymeTarget }, function() end, { rhymeConquer })
            end
            rhymeTarget.attrs.final[AD.HP], rhymeTarget.hp = 1, 1
            rhymeConquer._rhymeShot = 100
            local insideEvents = -1
            TAL.onAfterAttack(rhymeConquer, rhymeTarget, { category = "physical", totalDamage = 1 }, true,
                { rhymeTarget }, function(tgt, dmg, isAlly, prefix, color, opts)
                    BC.dealTalentDamage(rhymeConquer, tgt, dmg, isAlly, prefix, color, opts)
                    insideEvents = events[tgt] or 0
                end, { rhymeConquer })
            check(insideEvents == 0 and events[rhymeTarget] == 1,
                "押韵同步致死在本轮后攻击结束后分发，状态尚未清理")
            check(own[5].extraTalent.conquerCarry == 1 and TAL.getConquerStacks(rhymeConquer) == 20,
                "普攻未杀而押韵杀也先到满层，征服携带不漏")
            rhymeDriver:reportDefeatedEnemies()
            check(own[5].extraTalent.conquerCarry == 1, "押韵延后死亡与宿主扫描仍幂等")

            clear()
            local night, primary, secondary = hero(11, true, true), enemy(), enemy()
            local nightDriver = driver({ night }, { primary, secondary })
            night.attrs:addModifier("test_night_source", { { key = AD.PHYS_ATK, flat = 100000 } })
            primary.attrs.final[AD.HP], primary.hp = 0, 0
            secondary.attrs.final[AD.HP], secondary.hp = 1, 1
            -- 共鸣兼容下每三攻一次斩击；前两次只推进真实计数。
            for _ = 1, 3 do
                TAL.onComboAttack(night, primary, true, { primary, secondary },
                    function(tgt, dmg, isAlly, prefix, color, opts)
                        BC.dealTalentDamage(night, tgt, dmg, isAlly, prefix, color, opts)
                    end, { category = "physical", totalDamage = 1 })
            end
            check(secondary.hp <= 0 and secondary._killedByNightSlash == true
                and own[11].extraTalent.slashShadows == 1,
                "首次同步通宵斩致死已提供本次归因，斩影库存加1")
            nightDriver:reportDefeatedEnemies()
            check(own[11].extraTalent.slashShadows == 1, "通宵斩后宿主扫描不重复库存")

            clear()
            local nitro, nitroTarget = hero(21, true), enemy()
            local nitroDriver = driver({ nitro }, { nitroTarget })
            nitroTarget.attrs.final[AD.HP], nitroTarget.hp = 1, 1
            local oldRandom = math.random
            math.random = function(m, n)
                if n then return m end
                if m then return 1 end
                return 0
            end
            local procOk, procErr = pcall(TAL.onAfterAttack, nitro, nitroTarget,
                { category = "physical", totalDamage = 100 }, true, { nitroTarget },
                function(tgt, dmg, isAlly, prefix, color, opts)
                    BC.dealTalentDamage(nitro, tgt, dmg, isAlly, prefix, color, opts)
                end, { nitro })
            math.random = oldRandom
            check(procOk, "首次氮气执行无异常：" .. tostring(procErr))
            check(nitroTarget.hp <= 0 and own[21].extraTalent.nitroKills == 1,
                "首次同步氮气致死条件已前置，成长不漏记")
            nitroDriver:reportDefeatedEnemies()
            check(own[21].extraTalent.nitroKills == 1 and events[nitroTarget] == 1,
                "氮气即时分发与宿主扫描去重")
        end)

        case("后攻击死亡队列异常与战线隔离", function()
            clear()
            local dog, target = hero(1, true), enemy()
            local drv = driver({ dog }, { target })
            target.attrs.final[AD.HP], target.hp = 1, 1
            dog._rhymeShot = 100
            local okHook = pcall(TAL.onAfterAttack, dog, target,
                { category = "physical", totalDamage = 1 }, true, { target },
                function(tgt, dmg, isAlly, prefix, color, opts)
                    BC.dealTalentDamage(dog, tgt, dmg, isAlly, prefix, color, opts)
                    error("回归用后攻击错误")
                end, { dog })
            local refs = TAL.mountedState()
            check(not okHook and refs.deathHookDepth == 0 and #refs.pendingDeaths == 0,
                "后攻击异常仍恢复深度并清空死亡队列，保留失败反馈")
            check(events[target] == 1 and own[1].extraTalent.stacks == 1,
                "异常前已发生的真实死亡仍只消费一次")
            drv:reportDefeatedEnemies()
            check(events[target] == 1, "异常后的宿主扫描不重复死亡")

            clear()
            local dogA, targetA = hero(1, true), enemy()
            local laneA = driver({ dogA }, { targetA })
            local dogB, targetB = hero(3, true), enemy()
            local laneB = driver({ dogB }, { targetB })
            laneA:activate()
            targetA.attrs.final[AD.HP], targetA.hp = 1, 1
            dogA._rhymeShot = 100
            TAL.onAfterAttack(dogA, targetA, { category = "physical", totalDamage = 1 }, true,
                { targetA }, function(tgt, dmg, isAlly, prefix, color, opts)
                    BC.dealTalentDamage(dogA, tgt, dmg, isAlly, prefix, color, opts)
                    laneB:activate()
                    kill(targetB, dogB)
                    TAL.onEnemyDeath(targetB, { dogB }, { targetB })
                    laneA:activate()
                end, { dogA })
            check(events[targetA] == 1 and events[targetB] == 1,
                "嵌套切换挂载战线，各线死亡队列分别消费")
            check(own[1].extraTalent.stacks == 1 and own[3].extraTalent.stacks == 1,
                "嵌套战线不串击杀来源和成长")
        end)

        case("小雀斩杀保留致死标记", function()
            clear()
            local ayane = hero(8, true, true)
            ayane.awakeningNodes[3] = true
            own[8].awakening[3] = true
            local marked, nextEnemy = enemy(), enemy()
            local drv = driver({ ayane }, { marked, nextEnemy })
            SEM.remove(nextEnemy, SEM.MARKED)
            SEM.apply(marked, SEM.MARKED, 99999, ayane, {})
            marked.hp, marked.attrs.final[AD.HP] = 1, 1
            marked.attrs.energyShield, marked.attrs.tempEnergyShield = 0, 0
            marked.atkType = AD.ATK_SLASH
            TAL.onAfterAttack(ayane, marked, { category = "physical", totalDamage = 1 }, true,
                { marked, nextEnemy }, function(tgt, dmg, isAlly, prefix, color, opts)
                    BC.dealTalentDamage(ayane, tgt, dmg, isAlly, prefix, color, opts)
                end, { ayane })
            check(marked.hp <= 0 and own[8].extraTalent.stacks == 2,
                "小雀同步斩杀死亡消费前仍有原标记，专属击杀成长加2")
            check(own[8].extraTalent.markTypes[tostring(AD.ATK_SLASH)] == true,
                "小雀斩杀记录死亡目标攻击类型")
            check(SEM.has(nextEnemy, SEM.MARKED) and not SEM.has(marked, SEM.MARKED),
                "击杀成长读取后再转标，只留下一个活敌标记")
            drv:reportDefeatedEnemies()
            check(events[marked] == 1 and own[8].extraTalent.stacks == 2,
                "小雀斩杀后扫描不重复成长或转标")
        end)

        local function dungeonOpen(id, allies, count)
            local data = {
                dungeonId = id, floor = 1, teamIdx = 1, wave = 1, monsterLevel = 1,
                monsters = { { id = 1, count = count } }, rageTime = 999, superRageTime = 9999,
            }
            if DC.isResourceDungeon(id) then
                -- 正式工厂返回独立entry副本；只定制夹具数量/怪物，不写全局关卡配置。
                local entry = assert(DC.getCombatEntry(id, 1))
                entry.firstCount, entry.idleCount = count, count
                entry.monsters, entry.monsterLevel, entry.bossId = { 1 }, 1, 0
                data.stageEntry = entry
            end
            DungeonScene.open({ allies = allies, data = data })
            -- 必须在正式Scope.run内调用：Scene.open返回后宿主BC/SEM会还原。
            return BC.mountedState().ctx.getEnemies()
        end

        case("副本真实方法最后敌人", function()
            clear()
            DungeonScope.run(1, function()
                local snow = hero(12, true, true)
                local enemies = dungeonOpen("gold_mine", { snow }, 2)
                local e1, e2 = assert(enemies[1]), assert(enemies[2])
                for _, e in ipairs(enemies) do SEM.apply(e, SEM.FROZEN, 10, snow, {}); kill(e, snow) end
                DungeonScene.update(0)
                local pending = DB.getResultState()
                check(events[e1] == 1 and events[e2] == 1 and not pending,
                    "资源副本同帧全灭立即分发两次死亡，正式退场前不抢跑胜利")
                check(own[12].extraTalent.iceStatues == 2 and #ETS.getIceStatues() == 2,
                    "副本最后敌人冻结仍可生成正式冰雕")
                DungeonScene.update((BC.DEATH_ANIM_DURATION or 0.4) + 0.01)
                local finished, won = DB.getResultState()
                check(finished and won and #enemies == 0, "资源副本最后敌人退场完成才正式 onVictory")
                DungeonScene.update(0)
                check(events[e1] == 1 and events[e2] == 1, "副本结算延迟阶段不重复死亡")
                DungeonScene.forceClose()
            end)
        end)

        case("副本真实方法换批补位", function()
            clear()
            DungeonScope.run(1, function()
                local dog = hero(1, true)
                local field = dungeonOpen("gold_mine", { dog }, 6)
                local first = {}
                for _, e in ipairs(field) do first[#first + 1] = e; kill(e, dog) end
                DungeonScene.update(0)
                local allOnce = true
                for _, e in ipairs(first) do if events[e] ~= 1 then allOnce = false end end
                check(#first == Layout.MAX_PER_SIDE and allOnce and own[1].extraTalent.stacks == #first,
                    "资源副本旧场上数组退场前，全部死亡事件与成长恰好各一次")
                DungeonScene.update((BC.DEATH_ANIM_DURATION or 0.4) + 0.01)
                local current = BC.mountedState().ctx.getEnemies()
                local oldGone = true
                for _, currentEnemy in ipairs(current) do
                    for _, oldEnemy in ipairs(first) do
                        if currentEnemy == oldEnemy then oldGone = false end
                    end
                end
                check(#current == 1 and oldGone, "资源副本正式逐只退场补位，首个新单位不复用旧敌人")
                DungeonScene.update(0.4)
                check(#current == 6 - #first and own[1].extraTalent.stacks == #first,
                    "资源副本补位冷却后补足队列，旧死亡不重复成长")
                DungeonScene.forceClose()
            end)
        end)

        case("副本旧塔模式延迟退场", function()
            clear()
            DungeonScope.run(1, function()
                local snow = hero(12, true, true)
                local enemies = dungeonOpen("babel_tower", { snow }, 6)
                local dead = enemies[1]
                SEM.apply(dead, SEM.FROZEN, 10, snow, {})
                kill(dead, snow)
                DungeonScene.update(0.01)
                DungeonScene.update(0.01)
                check(events[dead] == 1 and dead.reviveTimer < 0 and frozenAtDeath[dead],
                    "旧塔副本动画延迟不延迟事件、重复扫描幂等")
                DungeonScene.update(2.5)
                check(enemies[1] ~= dead and events[dead] == 1, "旧塔实际原位补位不重复旧单位死亡")
                DungeonScene.forceClose()
            end)
        end)

        case("三行塔真实 open/update", function()
            clear()
            local teams, laneEnemies = {}, {}
            for i = 1, 3 do teams[i] = { hero(i, i == 1) } end
            local oldStart = TAL.onBattleStart
            local restoreIndex = #restores
            patch(TAL, "onBattleStart", function(allies, enemies)
                laneEnemies[#laneEnemies + 1] = enemies
                return oldStart(allies, enemies)
            end)
            Tower.open({ teamAllies = teams, data = { dungeonId = "babel_tower", floor = 1,
                wave = 1, monsterLevel = 1, monsters = { 1, 1, 1 }, rageTime = 999, superRageTime = 9999 } })
            -- 正式 splitToLanes：三行各两只，无后备。不是直接调用私有 helper。
            local all = {}
            for i, list in ipairs(laneEnemies) do
                for _, e in ipairs(list) do all[#all + 1] = e; kill(e, teams[i][1]) end
            end
            Tower.update(0)
            local pending, won = DB.getResultState()
            local allOnce = #all == 6
            for _, e in ipairs(all) do if events[e] ~= 1 then allOnce = false end end
            check(allOnce and pending and won, "三行塔真实 clearLane/finishWin 早返前六只敌人各发一次")
            check(own[1].extraTalent.stacks == 2, "塔内大狗击杀两只成长两层，其他线不串成长")
            Tower.update(0)
            check(events[all[1]] == 1, "三行塔结算阶段不重复事件")
            Tower.forceClose()
            for i = #restores, restoreIndex + 1, -1 do restores[i](); table.remove(restores, i) end
        end)

        case("终焉最后战线即时致死收尾", function()
            clear()
            local restoreIndex = #restores
            local terminalOk, terminalErr = pcall(function()
                -- UrhoX require 有引擎缓存；只读编译独立生产 Page，隔离私有 drivers/raid。
                local file = assert(cache:GetFile("ui/battle/tri/BattleTriPage.lua"))
                local readOk, source = pcall(function()
                    local lines = {}
                    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
                    return table.concat(lines, "\n")
                end)
                file:Dispose()
                assert(readOk, source)
                local Page = assert(load(source, "@ui.battle.tri.BattleTriPage", "t", _G))()
                local teams, drivers = {}, {}
                teams[1], teams[2], teams[3] = { hero(2) }, { hero(3) }, { hero(1, true) }
                patch(CP, "getDeployedTeam", function(i) return teams[i] end)
                patch(CP, "getTeamSignature", function(i) return "enemydeath-team" .. i end)
                patch(require("config.ExpTable"), "getUnlockedTeamCount", function() return 3 end)
                local mainStage = SC.TERMINAL_NORMAL
                patch(BattleScene, "getStageId", function() return mainStage end)
                patch(BattleScene, "pumpBattleCards", function() end)
                patch(require("ui.story.gate.LetterIntro"), "isOpen", function() return false end)
                patch(require("ui.story.gate.IntroCutscene"), "isActive", function() return false end)
                patch(require("ui.story.ScenarioDialogue"), "isActive", function() return false end)
                patch(require("ui.battle.popup.TerminalConfirmDialog"), "update", function() end)
                local oldNew = Driver.new
                patch(Driver, "new", function(i, opts)
                    local drv = oldNew(i, opts)
                    drivers[i] = drv
                    return drv
                end)
                restores[#restores + 1] = function()
                    Page.close()
                    for _, drv in ipairs(drivers) do
                        if drv.terminalRaid then drv.terminalRaid:release(); drv.terminalRaid = nil end
                    end
                end
                local finishCalls = 0
                local bossRefs, allBosses = {}, {}
                patch(BattleScene, "updateTriReincarnation", function() return true end)
                patch(BattleScene, "completeTriTerminal", function()
                    finishCalls = finishCalls + 1
                    local allOnce, eventCount = #allBosses == 9, 0
                    for _, e in ipairs(allBosses) do
                        if events[e] ~= 1 then allOnce = false end
                        eventCount = eventCount + (events[e] or 0)
                    end
                    check(allOnce and eventCount == 9,
                        "终焉完成/解绑前，九个 Boss 实例死亡事件恰好各一次")
                    mainStage = SC.getReincarnationTarget(SC.getDifficulty(SC.TERMINAL_NORMAL))
                    return true
                end)
                Page.open()
                local raid = assert(drivers[1].terminalRaid)
                for row = 1, 3 do
                    drivers[row].introTimer = 0
                    bossRefs[row] = {}
                    for index = 1, 3 do
                        local boss = assert(drivers[row].enemies[index])
                        bossRefs[row][index] = boss
                        allBosses[#allBosses + 1] = boss
                    end
                end
                check(#raid.pools == 3 and #allBosses == 9, "真实 Page 终焉为九实例三个同编号池")
                -- 最后一线 update 结束时才打空一个编号池；本帧前两线已完成扫描。
                -- 分三帧打空三池，覆盖单池/双池空不能收尾，最后一池触发兜底扫描。
                local nextPool = 1
                local oldUpdate = drivers[3].update
                patch(drivers[3], "update", function(self, dt)
                    oldUpdate(self, dt)
                    if nextPool > 3 then return end
                    self:activate()
                    local target = bossRefs[3][nextPool]
                    target.attrs.energyShield, target.attrs.tempEnergyShield = 0, 0
                    BC.dealDamageToUnit(target, target.maxHp * 100, false, "", nil, teams[3][1])
                    nextPool = nextPool + 1
                end)
                for index = 1, 2 do
                    Page.update(0)
                    check(raid.pools[index].hp == 0 and raid.hp > 0 and finishCalls == 0 and not raid.finished,
                        "仅打空前" .. index .. "个池，真实 Page 不提前胜利/解绑")
                    check(own[1].extraTalent.stacks == index,
                        "每个编号池只有末击实际命中实例给予大狗一层成长")
                end
                Page.update(0)
                check(finishCalls == 1 and raid.finished and raid.won == true and raid.hp == 0,
                    "所有三池空时真实 Page 同帧胜利收尾一次")
                local noFakeSource, actualSources, allOnce, eventCount = true, true, true, 0
                for row = 1, 3 do
                    for index = 1, 3 do
                        local boss = bossRefs[row][index]
                        if row < 3 and boss._killedBy ~= nil then noFakeSource = false end
                        if row == 3 and boss._killedBy ~= teams[3][1] then actualSources = false end
                        if events[boss] ~= 1 then allOnce = false end
                        eventCount = eventCount + (events[boss] or 0)
                    end
                    check(drivers[row].terminalRaid == raid and drivers[row].stageId == SC.TERMINAL_NORMAL,
                        "胜利真实宿主保留共享池待轮回，队" .. row)
                end
                check(noFakeSource and actualSources, "同步死亡不伪造六个未命中实例杀手，三次实杀保留末击源")
                check(allOnce and eventCount == 9, "九个死亡事件总数恰好9，不因三次跨线扫描重复")
                check(own[1].extraTalent.stacks == 3
                    and own[2].extraTalent.stacks == 0 and own[3].extraTalent.stacks == 0,
                    "三个实际末击只给大狗三层成长，未命中战线不串成长")
                Page.update(0)
                check(finishCalls == 1 and own[1].extraTalent.stacks == 3,
                    "胜利后再次更新不重复完成或实际杀手成长")
            end)
            for i = #restores, restoreIndex + 1, -1 do
                local restoreOk, restoreErr = pcall(restores[i])
                table.remove(restores, i)
                if not restoreOk then check(false, "终焉 restore 异常: " .. tostring(restoreErr)) end
            end
            if not terminalOk then error(terminalErr) end
        end)
        ETS.flush() -- 仍在测试存档/网络边界内，不将 dirty 队列留给还原后的生产边界。
    end)
    if not ok then check(false, "测试初始化/收尾异常: " .. tostring(err)) end
    for i = #restores, 1, -1 do restores[i]() end
    print(string.format("[EnemyDeath][SUMMARY] assertions=%d failures=%d", assertions, failures))
    if failures == 0 then print("[EnemyDeath] ALL PASS") end
    if failures > 0 then log:Write(LOG_ERROR, "[EnemyDeath] failures=" .. failures) end
    engine:Exit()
end
