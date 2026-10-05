-- B02 专项：真实 Page + Driver.start/tick + EnemySpawn/MonsterConfig/词缀/狂暴。
-- 沿用 battle_cleared_monotonic_test 的源码沙箱脚手架；仅外围UI/保存/攻击叶子替身。
-- 合成英雄、确定性主动死亡；不读取玩家档，不宣称完整数值强度/设备图形验收。
-- Runtime tests/tri_firstclear_rules_test.lua -tapcode_dir=. -tool_mode -graphicsheadless -nosound
local PREFIX = "[tri_firstclear_rules] "
local checks, failures = 0, 0
local function check(value, label)
    checks = checks + 1
    if value then print(PREFIX .. "PASS " .. label)
    else failures = failures + 1; print(PREFIX .. "FAIL " .. label) end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function near(actual, expected, label)
    check(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
        label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

function Start()
    local ok, err = xpcall(function()
        local nativeRequire, nativeCache = require, cache
        local SC = nativeRequire("config.StageConfig")
        local AD = nativeRequire("systems.AttributeDef")
        local HC = nativeRequire("config.HeroConfig")
        local MC = nativeRequire("config.MonsterConfig")
        local GC = nativeRequire("config.GameConfig")
        local sourceCache = {} ---@type table<string, string>
        local function source(name)
            if sourceCache[name] then return sourceCache[name] end
            local path = name:gsub("%.", "/") .. ".lua"
            local file = assert(nativeCache:GetFile(path), "缺少源码 " .. path)
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            file:Dispose()
            sourceCache[name] = table.concat(lines, "\n")
            return sourceCache[name]
        end
        local function noop() end
        local function stub(values)
            return setmetatable(values or {}, { __index = function() return noop end })
        end
        local function newProcess(stageId, cleared)
            local ctx = { drivers = {}, firstCalls = 0, retreats = {}, intervals = {}, attacks = 0,
                kills = 0, drops = 0 } ---@type any
            local deps = {} ---@type table<string, any>
            local env = setmetatable({ time = { elapsedTime = 100 } }, { __index = _G }) ---@type any
            env.File = function() error("B02 禁止玩家文件访问") end
            env.fileSystem = stub({ FileExists = function() error("B02 禁止查询玩家档") end })
            env.cache = stub({ GetResource = function() error("B02 禁止加载图形/音频资源") end })
            env.require = function(name)
                if deps[name] ~= nil then return deps[name] end
                if name:match("^config%.") or name:match("^shared%.") then return nativeRequire(name) end
                deps[name] = stub()
                return deps[name]
            end
            local function compile(name)
                return assert(load(source(name), "@真实B02/" .. name, "t", env))()
            end
            deps["config.MonsterConfig"] = MC -- 真怪物工厂及 UnitAttributes，非手抄敌表。
            deps["systems.UnitAttributes"] = nativeRequire("systems.UnitAttributes")
            deps["systems.AttributeDef"] = AD
            deps["core.NumberUtil"] = nativeRequire("core.NumberUtil")
            deps["core.BattleLayout"] = nativeRequire("core.BattleLayout")
            deps["core.I18n"] = nativeRequire("core.I18n")
            deps["runtime.ClientDispatcher"] = compile("runtime.ClientDispatcher")
            ctx.dispatcher = deps["runtime.ClientDispatcher"]
            deps["boot.StandaloneSave"] = { Flush = function() return true end }
            deps["core.PlayerStore"] = stub({ Get = function(key) return ctx.dispatcher.get(key) end })
            deps["shared.StageProvider"] = { Get = function() return SC end }
            deps["systems.StoryPlayer"] = stub()
            deps["systems.OfflineCalc"] = stub({ resolveIdleStageAnchors = function(data)
                return data.currentStageId, data.currentStageId
            end })
            local mounted = {} ---@type any
            deps["ui.battle.combat.BattleCombat"] = stub({
                newState = function() return { ctx = {} } end,
                mount = function(value) mounted = value or {} end,
                mountedState = function() return mounted end,
                setContext = function(value) mounted.ctx = value end,
                getCardPos = function() return 100, 100 end,
                syncUnitHp = function(unit)
                    unit.hp, unit.maxHp = unit.attrs:get(AD.HP), unit.attrs:get(AD.MAX_HP)
                end,
                advanceAttackProgress = function(unit, dt, interval)
                    ctx.intervals[unit] = interval
                end,
                performAttack = function() ctx.attacks = ctx.attacks + 1 end,
            })
            for _, name in ipairs({ "ui.battle.combat.ProjectileSystem", "systems.ThreatManager",
                "systems.TalentManager", "ui.battle.combat.BattleEffects", "systems.StatusEffectManager",
                "systems.RelicConditionHandler" }) do
                deps[name] = stub({ newState = function() return {} end,
                    newBattleRefs = function() return {} end, newFxState = function() return {} end,
                    newSemState = function() return {} end, isFrozen = function() return false end })
            end
            deps["systems.MapAffixSystem"] = compile("systems.MapAffixSystem")
            deps["systems.BossAffixSystem"] = compile("systems.BossAffixSystem")
            deps["ui.battle.stage.StageBerserk"] = compile("ui.battle.stage.StageBerserk")
            deps["systems.BattleTimeout"] = compile("systems.BattleTimeout")
            deps["ui.battle.stage.BattleEnemySpawn"] = compile("ui.battle.stage.BattleEnemySpawn")
            deps["ui.battle.stage.BattleStageNav"] = { NAV = {} }
            deps["ui.battle.scene.BattleAllyLifecycle"] = compile("ui.battle.scene.BattleAllyLifecycle")
            deps["ui.battle.scene.BattleScene"] = compile("ui.battle.scene.BattleScene")
            ctx.scene = deps["ui.battle.scene.BattleScene"]
            ctx.scene.adoptStageProgress(stageId)
            ctx.scene.setOnFirstClear(function() ctx.firstCalls = ctx.firstCalls + 1 end)
            for key, value in pairs(cleared or {}) do ctx.scene.getClearedStages()[key] = value end
            ctx.dispatcher.set("battle", { currentStageId = stageId, maxStageId = 34505,
                clearedStages = cleared or {}, teamStageIds = { ["1"] = stageId, ["2"] = stageId, ["3"] = stageId } })
            deps["ui.character.panel.CharacterPanel"] = stub({ getTeamSignature = function(team)
                return "B02合成队伍" .. tostring(team)
            end, getDeployedTeam = function(team)
                return { assert(HC.createHero(team, 30, nil, nil, false)) }
            end })
            deps["ui.battle.tri.BattleTriDriver"] = compile("ui.battle.tri.BattleTriDriver")
            local make = deps["ui.battle.tri.BattleTriDriver"].new
            deps["ui.battle.tri.BattleTriDriver"].new = function(team, options)
                local driver = make(team, options)
                ctx.drivers[team] = driver -- 只spy创建，不替换start/tick。
                return driver
            end
            deps["ui.battle.tri.TerminalRaid"] = compile("ui.battle.tri.TerminalRaid")
            deps["ui.battle.tri.BattleTriPage"] = compile("ui.battle.tri.BattleTriPage")
            ctx.page = deps["ui.battle.tri.BattleTriPage"]
            ctx.page.setOnKill(function() ctx.kills = ctx.kills + 1 end)
            ctx.page.setOnDrop(function() ctx.drops = ctx.drops + 1 end)
            ctx.page.open()
            ctx.MAS, ctx.BAS, ctx.Berserk = deps["systems.MapAffixSystem"], deps["systems.BossAffixSystem"],
                deps["ui.battle.stage.StageBerserk"]
            ctx.driverModule = deps["ui.battle.tri.BattleTriDriver"]
            ctx.spawn = deps["ui.battle.stage.BattleEnemySpawn"]
            ctx.timeout = deps["systems.BattleTimeout"]
            ctx.combat = deps["ui.battle.combat.BattleCombat"]
            ctx.raidModule = deps["ui.battle.tri.TerminalRaid"]
            ctx.win = function(team)
                local driver = ctx.drivers[team]
                driver.introTimer = 0
                for _, enemy in ipairs(driver.enemies) do enemy.hp = 0 end
                for _, enemy in ipairs(driver.enemyQueue) do enemy.hp = 0 end
                local turns = 0
                while not driver._clearReported and turns < 100 do
                    turns = turns + 1
                    driver:activate()
                    driver:tick(1.1)
                end
                check(driver._clearReported, "真实死亡/补位/清关到达队" .. team)
            end
            return ctx
        end
        local function allEnemies(driver)
            local result = {}
            for _, unit in ipairs(driver.enemies) do result[#result + 1] = unit end
            for _, unit in ipairs(driver.enemyQueue) do result[#result + 1] = unit end
            return result
        end
        local function find(list, id)
            for _, unit in ipairs(list) do if unit.monsterId == id then return unit end end
        end
        local function bonusCount(entry)
            local ids = entry.firstClearBonusMonsters
            return ids and #ids or (entry.firstClearBonusMonster and 1 or 0)
        end
        -- 正式204从真实Page开启三队；分别让二/三队率先完成，一队本场不删怪。
        for firstTeam = 2, 3 do
            local ctx = newProcess(204)
            local snapshots = {}
            for team = 1, 3 do
                local driver = ctx.drivers[team]
                eq(driver.battleLab, false, "204正式入口非Lab队" .. team)
                eq(driver.firstClear, true, "204共享未通本场首通快照队" .. team)
                eq(driver.stageTotal, 20, "204首通20只队" .. team)
                check(#driver.enemies <= 4, "204首通初始场上不超过4队" .. team)
                check(find(driver.enemies, 1004) ~= nil, "204附加1004开场队" .. team)
                eq(#allEnemies(driver), 20, "204场上加队列20队" .. team)
                snapshots[team] = allEnemies(driver)
            end
            ctx.win(firstTeam)
            eq(ctx.firstCalls, 1, "队" .. firstTeam .. "率先首通只奖励一次")
            local chasing = ctx.drivers[1]
            eq(chasing.firstClear, true, "其他队首通不改一队本场快照")
            eq(#allEnemies(chasing), #snapshots[1], "其他队首通不删除追赶队怪物")
            check(find(chasing.enemies, 1004) == find(snapshots[1], 1004), "追赶队1004对象不变")
            ctx.win(1)
            eq(ctx.firstCalls, 1, "一队追赶不重复首通奖励")
            for team = 1, 3 do
                local driver = ctx.drivers[team]
                driver:start(204)
                eq(driver.firstClear, false, "204已通下一场挂机队" .. team)
                eq(driver.stageTotal, 10, "204已通10只队" .. team)
                eq(find(allEnemies(driver), 1004), nil, "204已通无1004队" .. team)
                eq(driver.firstClearTimeLeft, nil, "204挂机没有失败时限队" .. team)
            end
            ctx.page.close()
        end
        -- 数字/字符串永久真值优先；输入options不能强行改变正式模式。
        for _, ledger in ipairs({ { [204] = true }, { ["204"] = true }, { [204] = false, ["204"] = true } }) do
            local ctx = newProcess(204, ledger)
            eq(ctx.drivers[2].stageTotal, 10, "两种永久已通键使用挂机敌表")
            ctx.page.close()
        end
        for _, stageId in ipairs({ 102, 105, 2405, 2605 }) do
            local ctx = newProcess(stageId)
            local entry = SC.getStage(stageId)
            local driver = ctx.drivers[2]
            eq(driver.stageTotal, entry.firstCount + bonusCount(entry), "真实首通配置数量stage=" .. stageId)
            eq(#allEnemies(driver), driver.stageTotal, "总数与场上队列一致stage=" .. stageId)
            check(#driver.enemies <= 4, "Boss/附加怪开场上限stage=" .. stageId)
            if entry.bossId > 0 then
                local boss = find(allEnemies(driver), entry.bossId)
                check(boss and boss.isBoss, "Boss配置生成isBoss stage=" .. stageId)
            end
            ctx.page.close()
        end
        -- 从正式配置寻找双附加怪，验证开场/末尾规则，不凭手写敌表。
        local ctx = newProcess(204)
        local bonusStage
        for chapter = 1, 345 do
            for index = 1, 5 do
                local entry = SC.getStage(chapter * 100 + index)
                if entry and bonusCount(entry) >= 2 then bonusStage = entry; break end
            end
            if bonusStage then break end
        end
        check(bonusStage ~= nil, "正式配置存在双附加怪用例")
        if bonusStage then
            local driver = ctx.drivers[2]
            driver:start(bonusStage.id)
            local ids = ctx.spawn.getFirstClearBonusMonsterIds(bonusStage)
            local first, last = find(driver.enemies, ids[1]), find(driver.enemyQueue, ids[#ids])
            check(first and first._bonusSpawnPhase == "start", "首附加怪开场占槽")
            check(last and last._bonusSpawnPhase == "end", "末附加怪在末尾队列")
            check(last == driver.enemyQueue[#driver.enemyQueue], "末附加怪排队尾")
            check(#driver.enemies <= 4, "双附加怪仍不超过4")
        end
        -- 三附加middle是共享Spawn API合成边界，正式配置目前最多2，不能宣称可达。
        local first, middle, last = {}, {}, {}
        ctx.spawn.markFirstClearBonusSpawnPhase(first, 1, 3)
        ctx.spawn.markFirstClearBonusSpawnPhase(middle, 2, 3)
        ctx.spawn.markFirstClearBonusSpawnPhase(last, 3, 3)
        local queue = { {}, {}, {}, {} }
        ctx.spawn.insertBonusMonsterIntoQueue(queue, middle)
        ctx.spawn.insertBonusMonsterIntoQueue(queue, last)
        eq(middle._bonusSpawnPhase, "middle", "合成三附加API标记middle")
        check(queue[3] == middle and queue[#queue] == last, "合成middle居中而end队尾")
        -- 正式词缀初始化/动态计时与三队隔离。
        local one, two, three = ctx.drivers[1], ctx.drivers[2], ctx.drivers[3]
        one:start(13901); one:activate()
        check(ctx.MAS.hasAffix("energy_barrier"), "正式首通13901地图护盾激活")
        for _, enemy in ipairs(allEnemies(one)) do
            local base = MC.createMonster(enemy.monsterId, enemy.level)
            check(enemy.attrs:get(AD.ENERGY_SHIELD) > base.attrs:get(AD.ENERGY_SHIELD), "地图静态词缀场上/队列护盾生效")
        end
        two:start(14501); two:activate(); two.introTimer = 0; two:tick(10.1)
        near(ctx.MAS.getDecayDamageBonus(), 0.04, "正式衰败10秒真实tick增伤4%")
        three:start(204); two:activate()
        near(ctx.MAS.getDecayDamageBonus(), 0.04, "第三队重开不清第二队衰败计时")
        one:activate()
        check(ctx.MAS.hasAffix("energy_barrier") and not ctx.MAS.hasAffix("decay_land"), "地图词缀按实例切换")
        one:start(14301); one.introTimer = 0; one:activate(); one:tick(15.1)
        check(ctx.MAS.isFogActive() and one.allies[1]._fogHitDebuff ~= nil, "正式远古之雾按tick施加")
        two:start(14401); two.introTimer = 0; two:activate(); two:tick(22.6)
        check(ctx.MAS.isRiftActive() and two.allies[1]._riftAtkDebuff ~= nil, "正式时空裂隙按tick施加")
        local fogUnit = one.allies[1]
        three:start(204); one:activate()
        check(ctx.MAS.isFogActive() and fogUnit._fogHitDebuff ~= nil, "其他队重开不清本队雾与标记")
        one:start(204)
        eq(fogUnit._fogHitDebuff, nil, "本队重开清旧雾debuff")
        -- Boss再生/暴怒/静态/荆棘，均依赖真实Driver加载当前配置。
        two:start(2405); two:activate()
        check(ctx.BAS.hasAffixes(), "正式Hard Boss词缀激活")
        local boss = find(allEnemies(two), SC.getStage(2405).bossId)
        local atField = find(two.enemies, boss.monsterId)
        if not atField then two.enemies = { boss }; two.enemyQueue = {} end
        boss.attrs.final[AD.HP] = math.floor(boss.maxHp * 0.5); ctx.combat.syncUnitHp(boss)
        local hp = boss.hp
        two.introTimer = 0; two:activate(); two:tick(1.1)
        check(boss.hp > hp, "Hard Boss再生真实tick回血")
        three:start(204); two:activate(); two:tick(1.1)
        check(boss.hp > hp, "其他队开战不清Boss再生配置")
        two:start(2605); two:activate()
        boss = find(allEnemies(two), SC.getStage(2605).bossId)
        two.enemies, two.enemyQueue = { boss }, {}
        boss.attrs.final[AD.HP] = math.floor(boss.maxHp * 0.3); ctx.combat.syncUnitHp(boss)
        local speed = boss.attrs:get(AD.ATK_SPEED)
        two.introTimer = 0; two:tick(0.1)
        check(boss.attrs:get(AD.ATK_SPEED) > speed, "Hard Boss暴怒真实tick加速")
        local enragedSpeed = boss.attrs:get(AD.ATK_SPEED)
        three:start(204); two:activate(); two:tick(0.1)
        near(boss.attrs:get(AD.ATK_SPEED), enragedSpeed, "Boss暴怒一次性状态不串队/不重复")
        two:start(2505); two:activate()
        boss = find(allEnemies(two), SC.getStage(2505).bossId)
        local base = MC.createMonster(boss.monsterId, SC.getStage(2505).monsterLevel)
        check(boss.attrs:get(AD.ENERGY_SHIELD) > base.attrs:get(AD.ENERGY_SHIELD), "Hard Boss静态护盾在队列已生效")
        two:start(2805); two:activate()
        boss = find(allEnemies(two), SC.getStage(2805).bossId)
        local reflected = 0
        ctx.BAS.onBossDamaged(boss, two.allies[1], 100, function(_, amount) reflected = amount end)
        check(reflected > 0, "Hard Boss荆棘按现行规则反弹")
        three:start(204); two:activate()
        local again = 0
        ctx.BAS.onBossDamaged(boss, two.allies[1], 100, function(_, amount) again = amount end)
        eq(again, reflected, "Boss受击钩子按本线配置恢复")
        -- 狂暴既改数值又必须改变Driver实际传给攻击推进的间隔。
        one:start(204); one.introTimer = 0; one:activate()
        local queuedRageEnemy = one.enemyQueue[1]
        one:tick(GC.StageBerserk.RAGE_TIME)
        eq(ctx.Berserk.getRagePhase(), 1, "首通一阶狂暴真实tick")
        near(ctx.intervals[one.allies[1]], one.allies[1].attrs:getActualInterval()
            / (1 + GC.StageBerserk.RAGE_ATK_BONUS), "狂暴攻速进入真实Driver攻击推进")
        local coeff = one.allies[1].attrs.atkCoeff
        local baseCoeff = HC.HEROES[one.allies[1].heroId].atkCoeff
        near(coeff, baseCoeff * (1 + GC.StageBerserk.ALLY_RAGE_DMG_BONUS), "己方首通狂暴准确攻击系数倍率")
        -- 实时attrs改速仍叠狂暴乘区，不能冻结开场攻击间隔。
        one.allies[1].attrs.final[AD.ATK_SPEED] = one.allies[1].attrs.final[AD.ATK_SPEED] + 30
        one:tick(0.1)
        near(ctx.intervals[one.allies[1]], one.allies[1].attrs:getActualInterval()
            / (1 + GC.StageBerserk.RAGE_ATK_BONUS), "狂暴保留本帧实时属性攻速")
        one.enemies[1].hp = 0
        one:tick(1.1)
        check(find(one.enemies, queuedRageEnemy.monsterId) == queuedRageEnemy
            or (function()
                for _, unit in ipairs(one.enemies) do if unit == queuedRageEnemy then return true end end
                return false
            end)(), "狂暴阶段真实死亡补位保留原队列对象")
        near(ctx.intervals[queuedRageEnemy], queuedRageEnemy.attrs:getActualInterval()
            / (1 + GC.StageBerserk.RAGE_ATK_BONUS), "新补位敌人同帧吃本线狂暴攻速")
        two:start(204); one:activate()
        eq(ctx.Berserk.getRagePhase(), 1, "第二队开场不清第一队狂暴")
        near(one.allies[1].attrs.atkCoeff, coeff, "第二队开场不恢复第一队狂暴数值")
        one:tick(GC.StageBerserk.SUPER_RAGE_TIME - GC.StageBerserk.RAGE_TIME)
        eq(ctx.Berserk.getRagePhase(), 2, "首通超级狂暴真实tick")
        local oldAlly = one.allies[1]
        one:start(204)
        near(oldAlly.attrs.atkCoeff, HC.HEROES[oldAlly.heroId].atkCoeff, "重开恢复旧单位狂暴系数")
        -- 首通失败按TIME_LIMIT_SEC；已通不失败，BattleTimeout增伤仍继续。
        one.introTimer = 0; one:activate()
        eq(one.firstClearTimeLeft, GC.Battle.TIME_LIMIT_SEC, "首通失败时限来自现行配置")
        one:tick(GC.Battle.TIME_LIMIT_SEC - 0.1)
        eq(one.stageId, 204, "失败时限到达前不退关")
        one:tick(0.2)
        eq(one.stageId, SC.getPrevStageId(204), "首通失败时限到达走退关")
        check(not ctx.dispatcher.get("battle").clearedStages["204"], "超时失败不登记首通")
        ctx.dispatcher.get("battle").clearedStages["204"] = true
        one:start(204); one.introTimer = 0; one:activate()
        one:tick(GC.Battle.TIME_LIMIT_SEC + 1)
        eq(one.stageId, 204, "挂机超过300秒仍不自动失败")
        eq(one.firstClearTimeLeft, nil, "挂机失败时限始终nil")
        one:activate()
        check(ctx.combat.mountedState().ctx.globalDmgMult > 1, "挂机BattleTimeout只增伤不失败")
        check(not ctx.MAS.hasAffixes() and not ctx.BAS.hasAffixes() and not ctx.Berserk.isActive(),
            "挂机本线清词缀与首通狂暴")
        -- Lab显式模式隔离：不消费正式cleared、不发奖、不推进，不污染其他实例。
        two:start(14501); two.introTimer = 0; two:activate(); two:tick(10.1)
        local lab = ctx.driverModule.new(99, { battleLab = true, firstClear = true, timeLimit = 2,
            allyFactory = function() return { assert(HC.createHero(1, 30, nil, nil, false)) } end })
        lab:start(204)
        eq(lab.stageTotal, 20, "Lab显式首通不受正式已通标记影响")
        check(find(lab.enemies, 1004) ~= nil, "Lab首通1004仍开场")
        two:activate(); near(ctx.MAS.getDecayDamageBonus(), 0.04, "Lab开战不清正式衰败状态")
        lab.introTimer = 0; lab:activate(); lab:tick(2.1)
        check(lab._labTimedOut and not lab.active, "Lab保留专用timeLimit采样截止")
        eq(lab.stageId, 204, "Lab截止不退正式关卡")
        eq(ctx.firstCalls, 0, "Lab不发正式首通奖励")
        -- 终焉保留三编号九Boss共享池与签名守卫。
        local raidDrivers = {}
        for team = 1, 3 do
            local driver = ctx.drivers[team]
            driver:start(999)
            eq(driver.stageTotal, 3, "终焉每线3Boss独立分支队" .. team)
            raidDrivers[team] = driver
        end
        local raid = ctx.raidModule.new(999, raidDrivers)
        for team = 1, 3 do raidDrivers[team].terminalRaid = raid end
        local original = raidDrivers[1].enemies[1]
        raidDrivers[1].teamSignature = "人为改变签名"
        for index = 1, 45 do raidDrivers[1]:update(0) end
        check(raidDrivers[1].enemies[1] == original and raid.lines[1][1] == original,
            "终焉签名变化45帧不重建Boss/不脱共享池")
        raid:release()
        ctx.page.close()

        -- 真Driver/BC.performAttack -> Driver投射物回调 -> 实际伤害 -> BAS荆棘。
        -- 这里只控制公式结果与投射物落地时刻，绝不替换BC/start/BAS钩子。
        local patches = {}
        local function patch(owner, key, value)
            local old = owner[key]
            patches[#patches + 1] = function() owner[key] = old end
            owner[key] = value
        end
        local integrationOk, integrationErr = xpcall(function()
            local Driver = nativeRequire("ui.battle.tri.BattleTriDriver")
            local BC = nativeRequire("ui.battle.combat.BattleCombat")
            local PS = nativeRequire("ui.battle.combat.ProjectileSystem")
            local CP = nativeRequire("ui.character.panel.CharacterPanel")
            local Dispatcher = nativeRequire("runtime.ClientDispatcher")
            local Formula = nativeRequire("systems.CombatFormula")
            local hero = assert(HC.createHero(1, 30, nil, nil, false))
            local ledger = { currentStageId = 2805, maxStageId = 2805, clearedStages = {} }
            patch(Dispatcher, "get", function(key)
                if key == "battle" then return ledger end
                if key == "heroes" then return { roster = {} } end
            end)
            patch(CP, "getTeamSignature", function() return "B02真命中" end)
            patch(CP, "getDeployedTeam", function() return { hero } end)
            patch(CP, "getOwnedHero", function() return nil end)
            patch(nativeRequire("boot.StandaloneSave"), "Flush", function() return true end)
            patch(nativeRequire("systems.GameSFX"), "play", noop)
            local pendingHit
            local realSpawn = PS.spawn
            patch(PS, "hasHeroEffect", function() return true end)
            patch(PS, "spawn", function(_, _, _, _, _, hit) pendingHit = hit end)
            patch(Formula, "calcAttack", function()
                return { category = "physical", isMiss = false, isCrit = false,
                    hits = { { damage = 100, isCrit = false, isBlocked = false } },
                    totalDamage = 100, resistance = 0, comboCount = 0 }
            end)
            local driver = Driver.new(2)
            driver:start(2805) -- 当前Hard第四章荆棘，模式来自真实永久账本。
            local target = find(allEnemies(driver), SC.getStage(2805).bossId)
            driver.enemies, driver.enemyQueue = { target }, {}
            driver:activate()
            nativeRequire("systems.TalentManager").initUnit(target)
            hero.attrs.energyShield, hero.attrs.tempEnergyShield = 0, 0
            target.attrs.energyShield, target.attrs.tempEnergyShield = 0, 0
            local heroHp, bossHp = hero.hp, target.hp
            BC.performAttack(hero, driver.enemies, true)
            check(type(pendingHit) == "function", "真实Driver命中回调进入可控投射物")
            eq(target.hp, bossHp, "飞弹未落地Boss不提前掉血")
            eq(hero.hp, heroHp, "飞弹未落地荆棘不提前反弹")
            if pendingHit then pendingHit() end
            eq(bossHp - target.hp, 100, "真实BC applyHit伤害100实际扣BossHP")
            eq(heroHp - hero.hp, 10, "正式Driver首通真实BC荆棘反弹10HP")
            local other = Driver.new(3)
            other:start(204)
            driver:activate()
            pendingHit = nil
            heroHp = hero.hp
            BC.performAttack(hero, driver.enemies, true)
            if pendingHit then pendingHit() end
            eq(heroHp - hero.hp, 10, "其他队开场后真实命中仍消费本队荆棘配置")

            -- 真实PS.spawn/update与BC applyHit完成限时前最后一击；尸体退场不能变超时。
            PS.spawn = realSpawn
            driver:start(204)
            target = driver.enemies[1]
            driver.enemies, driver.enemyQueue = { target }, {}
            driver.introTimer = 0
            driver:activate()
            target.attrs.final[AD.HP], target.hp = 100, 100
            target.attrs.energyShield, target.attrs.tempEnergyShield = 0, 0
            driver.firstClearTimeLeft = 1
            local clears, lastClearStage = 0, 0
            driver.onStageCleared = function(_, clearedStage)
                clears = clears + 1; lastClearStage = clearedStage
            end
            BC.performAttack(hero, driver.enemies, true)
            check(#driver.psState.projectiles == 1, "限时最后一击进入真实投射物容器")
            local projectile = driver.psState.projectiles[1]
            local flight = projectile.cfg.duration * (projectile.cfg.hitRatio or 1)
            local flightTicks = math.ceil(flight / 0.01) + 1
            for index = 1, flightTicks do driver:update(0.01) end
            eq(target.hp, 0, "真实投射物小dt落地最后敌HP归零")
            check(hero.hp > 0 and driver.stageId == 204 and driver.firstClearTimeLeft > 0,
                "最后一击发生于首通失败时限前且己方存活")
            local timeAtDeath = driver.firstClearTimeLeft
            local stageAtDeath = driver.stageId
            driver:update(0.2)
            check(not driver._clearReported and driver.enemies[1] == target and clears == 0,
                "尸体动画期间不提前clear/奖励/删除对象")
            near(driver.firstClearTimeLeft, timeAtDeath, "已胜尸体收尾冻结首通失败倒计时")
            for index = 1, 110 do driver:update(0.01) end
            eq(driver.stageId, stageAtDeath, "最后敌限时前死亡不因1秒尸体动画退关")
            eq(clears, 1, "尸体自然退场后通关回调恰好一次")
            eq(lastClearStage, 204, "临界最后一击仍回调原关204")
            check(driver._clearReported and #driver.enemies == 0,
                "保留正常尸体退场到通关流程")

            -- 双向已发射末击同帧落地，未用不死鸟先合法复活；额度已用的全灭仍失败。
            local NativeTAL = nativeRequire("systems.TalentManager")
            local NativeSEM = nativeRequire("systems.StatusEffectManager")
            for _, usedPhoenix in ipairs({ false, true }) do
                local label = usedPhoenix and "已用不死鸟" or "未用不死鸟"
                hero.litNodeSet = { [125] = true }
                driver:start(204)
                target = driver.enemies[1]
                target.atkEffect = "EF_ATK_1"
                driver.enemies, driver.enemyQueue = { target }, {}
                driver.introTimer = 0
                driver:activate()
                if usedPhoenix then
                    hero.attrs.final[AD.HP], hero.hp = 0, 0
                    check(NativeTAL.onAllyDeath(hero, driver.allies, BC.syncUnitHp),
                        label .. "先通过真实TAL消费一次复活额度")
                    NativeSEM.removeUnit(hero)
                end
                hero.attrs.final[AD.HP], hero.hp = 100, 100
                target.attrs.final[AD.HP], target.hp = 100, 100
                hero.attrs.energyShield, hero.attrs.tempEnergyShield = 0, 0
                target.attrs.energyShield, target.attrs.tempEnergyShield = 0, 0
                local doubleClears = 0
                driver.onStageCleared = function() doubleClears = doubleClears + 1 end
                BC.performAttack(hero, driver.enemies, true)
                BC.performAttack(target, driver.allies, false)
                eq(#driver.psState.projectiles, 2, label .. "真实BC双向出手进入PS")
                for _, flying in ipairs(driver.psState.projectiles) do
                    local hitTime = flying.cfg.duration * (flying.cfg.hitRatio or 1)
                    flying.timer = hitTime - 0.005 -- 正常飞行即将到达，同帧末击边界。
                end
                driver.firstClearTimeLeft = 0.015
                driver:update(0.01)
                eq(target.hp, 0, label .. "真实敌末击死亡")
                eq(hero.hp, 0, label .. "已发敌弹同帧落地击倒最后友方")
                check(driver.firstClearTimeLeft > 0 and driver.firstClearTimeLeft < 0.01,
                    label .. "双向末击均在时限前")
                driver:update(0.01)
                if usedPhoenix then
                    eq(driver.stageId, 203, label .. "真全灭仍退关")
                    eq(doubleClears, 0, label .. "真全灭不提前发通关奖励")
                else
                    check(hero.hp > 0 and driver.stageId == 204,
                        label .. "先执行合法复活不被首通计时抢先退关")
                    check(not driver._clearReported and doubleClears == 0,
                        label .. "复活后仍等正常尸体退场")
                    for index = 1, 110 do driver:update(0.01) end
                    eq(doubleClears, 1, label .. "复活后正常尸体退场恰好通关一次")
                    eq(driver.stageId, 204, label .. "复活收尾不误退关")
                end
            end
        end, debug.traceback)
        for index = #patches, 1, -1 do patches[index]() end
        check(integrationOk, "真BC命中链无异常 " .. (integrationOk and "" or tostring(integrationErr)))

        -- Lab真实runSingle返回也必须恢复进入前整组状态，而非只恢复统计/布局。
        local RuntimeContext = nativeRequire("ui.battle.scene.BattleRuntimeContext")
        local prior = RuntimeContext.newState("B02Lab前上下文")
        RuntimeContext.mount(prior)
        local NativeMAS = nativeRequire("systems.MapAffixSystem")
        local NativeBAS = nativeRequire("systems.BossAffixSystem")
        local NativeBerserk = nativeRequire("ui.battle.stage.StageBerserk")
        NativeMAS.onStageLoad(145, {}); NativeMAS.tick(10.1, {}, {})
        NativeBAS.onStageLoad(24, "hard")
        local labReport, labErr = nativeRequire("tests.BattleLab").runSingle({
            stageId = 101, mode = "firstClear", runs = 1, seed = 20261004,
            timeLimit = 1, heroes = { { id = 1, level = 30 } },
        })
        check(labReport ~= nil, "真实Lab.runSingle完成 " .. tostring(labErr))
        local afterLab = RuntimeContext.capture()
        check(afterLab.combatState == prior.combatState and afterLab.rchState == prior.rchState,
            "Lab返回恢复进入前战斗/RCH对象")
        check(afterLab.mapAffixState == prior.mapAffixState and afterLab.bossAffixState == prior.bossAffixState
            and afterLab.berserkState == prior.berserkState, "Lab返回恢复进入前3规则对象")
        near(NativeMAS.getDecayDamageBonus(), 0.04, "Lab返回保留原衰败时间/层数")
        check(NativeBAS.hasAffixes(), "Lab返回保留原Boss词缀")
        local NativeLab = nativeRequire("tests.BattleLab")
        for _, case in ipairs({
            { name = "runSingle正常", run = NativeLab.runSingle },
            { name = "run双配装回调切线", run = NativeLab.run, paired = true, callback = "mount" },
            { name = "runSingle异常回调切线", run = NativeLab.runSingle, callback = "error" },
            { name = "run异常回调切线", run = NativeLab.run, callback = "error" },
        }) do
            local sentinel = RuntimeContext.newState("B02Lab恢复" .. case.name)
            RuntimeContext.mount(sentinel)
            NativeMAS.onStageLoad(145, {}); NativeMAS.tick(10.1, {}, {})
            NativeBAS.onStageLoad(24, "hard")
            local sentinelHero = assert(HC.createHero(1, 30, nil, nil, false))
            NativeBerserk.enter({}, { sentinelHero })
            NativeBerserk.update(GC.StageBerserk.RAGE_TIME, {}, { sentinelHero })
            local sentinelCoeff = sentinelHero.attrs.atkCoeff
            local config = { stageId = 101, mode = "firstClear", runs = 1, seed = 20261004,
                timeLimit = 1, heroes = { { id = 1, level = 30 } } }
            if case.paired then config.loadouts = { A = {}, B = {} } end
            local callback = case.callback and function()
                RuntimeContext.mount(sentinel)
                if case.callback == "error" then error("B02预期progress异常") end
            end or nil
            local report, caseErr = case.run(config, callback)
            if case.callback == "error" then
                check(report == nil and tostring(caseErr):find("B02预期progress异常", 1, true) ~= nil,
                    case.name .. "捕获预期异常")
            else
                check(report ~= nil, case.name .. "真实完成 " .. tostring(caseErr))
            end
            local actual = RuntimeContext.capture()
            for key, state in pairs(sentinel) do
                check(actual[key] == state, case.name .. "恢复进入前" .. key)
            end
            near(NativeMAS.getDecayDamageBonus(), 0.04, case.name .. "保留地图计时")
            check(NativeBAS.hasAffixes(), case.name .. "保留Boss配置")
            eq(NativeBerserk.getRagePhase(), 1, case.name .. "不退出正式狂暴")
            near(sentinelHero.attrs.atkCoeff, sentinelCoeff, case.name .. "不恢复正式单位系数")
            RuntimeContext.mount(sentinel)
            NativeBerserk.exit()
        end
        RuntimeContext.mount(prior)
        NativeBerserk.exit()
    end, debug.traceback)
    if not ok then failures = failures + 1; print(PREFIX .. "FAIL exception=" .. tostring(err)) end
    print(PREFIX .. "RESULT " .. (failures == 0 and "ALL PASS" or "FAIL")
        .. " checks=" .. checks .. " failures=" .. failures)
    engine:Exit()
end
