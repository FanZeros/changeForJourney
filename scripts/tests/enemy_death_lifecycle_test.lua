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
            DungeonScene.open({ allies = allies, data = {
                dungeonId = id, floor = 1, wave = 1, monsterLevel = 1,
                monsters = { { id = 1, count = count } }, rageTime = 999, superRageTime = 9999,
            } })
            return BC.mountedState().ctx.getEnemies()
        end

        case("副本真实方法最后敌人", function()
            clear()
            local snow = hero(12, true, true)
            local enemies = dungeonOpen("gold_mine", { snow }, 2)
            for _, e in ipairs(enemies) do SEM.apply(e, SEM.FROZEN, 10, snow, {}); kill(e, snow) end
            DungeonScene.update(0)
            local pending, won = DB.getResultState()
            check(events[enemies[1]] == 1 and events[enemies[2]] == 1 and pending and won,
                "普通副本 open/update 同帧全灭先发两次事件再 onVictory")
            check(own[12].extraTalent.iceStatues == 2 and #ETS.getIceStatues() == 2, "副本最后敌人冻结仍可生成正式冰雕")
            DungeonScene.update(0)
            check(events[enemies[1]] == 1, "副本结算延迟阶段不重复死亡")
            DungeonScene.forceClose()
        end)

        case("副本真实方法换批补位", function()
            clear()
            local dog = hero(1, true)
            local first = dungeonOpen("gold_mine", { dog }, 6)
            for _, e in ipairs(first) do kill(e, dog) end
            DungeonScene.update(0)
            local current = BC.mountedState().ctx.getEnemies()
            check(#first == 5 and #current == 1 and current ~= first, "普通副本真实全灭换批、补位新单位")
            local allOnce = true
            for _, e in ipairs(first) do if events[e] ~= 1 then allOnce = false end end
            check(allOnce and own[1].extraTalent.stacks == 5, "丢弃旧敌人数组前五个死亡事件全到达")
            DungeonScene.forceClose()
        end)

        case("副本旧塔模式延迟退场", function()
            clear()
            local snow = hero(12, true, true)
            local enemies = dungeonOpen("babel_tower", { snow }, 6)
            local dead = enemies[1]
            SEM.apply(dead, SEM.FROZEN, 10, snow, {})
            kill(dead, snow)
            DungeonScene.update(0.01)
            DungeonScene.update(0.01)
            check(events[dead] == 1 and dead.reviveTimer < 0 and frozenAtDeath[dead], "旧塔副本动画延迟不延迟事件、重复扫描幂等")
            DungeonScene.update(2.5)
            check(enemies[1] ~= dead and events[dead] == 1, "旧塔实际原位补位不重复旧单位死亡")
            DungeonScene.forceClose()
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
            local Page = require("ui.battle.tri.BattleTriPage")
            local teams, drivers = {}, {}
            teams[1], teams[2], teams[3] = { hero(2) }, { hero(3) }, { hero(1, true) }
            local restoreIndex = #restores
            patch(CP, "getDeployedTeam", function(i) return teams[i] end)
            patch(CP, "getTeamSignature", function(i) return "enemydeath-team" .. i end)
            patch(require("config.ExpTable"), "getUnlockedTeamCount", function() return 3 end)
            patch(BattleScene, "getStageId", function() return SC.TERMINAL_NORMAL end)
            patch(BattleScene, "pumpBattleCards", function() end)
            patch(require("ui.story.gate.LetterIntro"), "isOpen", function() return false end)
            patch(require("ui.story.gate.IntroCutscene"), "isActive", function() return false end)
            patch(require("ui.story.ScenarioDialogue"), "isActive", function() return false end)
            local oldNew = Driver.new
            patch(Driver, "new", function(i, opts)
                local drv = oldNew(i, opts)
                drivers[i] = drv
                return drv
            end)
            local finished = false
            local bossRefs = {}
            patch(BattleScene, "completeTriTerminal", function()
                finished = true
                local allOnce = true
                for _, e in ipairs(bossRefs) do if events[e] ~= 1 then allOnce = false end end
                check(allOnce, "终焉完成/解绑前，三路 Boss 同步死亡各事件一次")
                return true
            end)
            Page.open()
            for i = 1, 3 do bossRefs[i] = drivers[i].enemies[1]; drivers[i].introTimer = 0 end
            -- 最后一线 update 结束时才击穿共享池，前两线本帧已经完成扫描。
            local oldUpdate = drivers[3].update
            drivers[3].update = function(self, dt)
                oldUpdate(self, dt)
                self:activate()
                bossRefs[3].attrs.energyShield = 0
                bossRefs[3].attrs.tempEnergyShield = 0
                BC.dealDamageToUnit(bossRefs[3], bossRefs[3].maxHp * 100, false, "", nil, teams[3][1])
            end
            Page.update(0)
            check(finished and bossRefs[1]._killedBy == nil and bossRefs[2]._killedBy == nil,
                "终焉真实 Page 收尾可达，未命中两线不伪造杀手")
            check(own[1].extraTalent.stacks == 1, "终焉三路同步仅实际末击源的大狗成长一次")
            Page.close()
            for i = #restores, restoreIndex + 1, -1 do restores[i](); table.remove(restores, i) end
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
