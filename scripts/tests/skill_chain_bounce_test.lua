-- 技能串行弹射回归：沿用 character_critical_combat_test 的真实战斗脚手架。
-- 只替换账号查询外围，所有英雄、公式、天赋、三行驱动和投射物均使用正式模块。
-- 不读玩家存档，不调用或替换 File/FileSystem；由主线程统一构建和运行。
local assertions, failures = 0, 0
local function check(value, message)
    assertions = assertions + 1
    if not value then
        failures = failures + 1
        print("[技能弹射回归][FAIL] " .. message)
    end
end
local function near(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-7
end
local function samePoint(nextProj, previous)
    return nextProj and previous and near(nextProj.startX, previous.endX)
        and near(nextProj.startY, previous.endY)
end
local function awake(first, second, third)
    return { [1] = first, [2] = second, [3] = third, _awk3Migrated = true }
end

function Start()
    print("[技能弹射回归] 开始")
    local nativeRequire, nativeRandom = require, math.random
    local accountQueries, accountWrites = 0, 0
    local accountBoundary = {
        getOwnedHero = function()
            accountQueries = accountQueries + 1
            return nil
        end,
        patchExtraTalent = function()
            accountWrites = accountWrites + 1
            error("技能弹射回归不允许写账号成长")
        end,
        finishExtraTalentBatch = function() end,
    }
    rawset(_G, "require", function(name)
        if name == "ui.character.panel.CharacterPanel" then return accountBoundary end
        if name == "runtime.GameAction" then
            return { sendAction = function()
                accountWrites = accountWrites + 1
                error("技能弹射回归不允许发送账号操作")
            end }
        end
        return nativeRequire(name)
    end)

    -- 固定随机边界，不替换战斗公式。第三次攻击的必暴仍由正式天赋产生。
    math.random = function(low, high)
        if high then return low end
        if low then return 1 end
        return 0.9
    end
    local formulaRestore = function() end
    local ok, err = pcall(function()
        local AD = require("systems.AttributeDef")
        local HC = require("config.HeroConfig")
        local UA = require("systems.UnitAttributes")
        local CF = require("systems.CombatFormula")
        local TAL = require("systems.TalentManager")
        local SEM = require("systems.StatusEffectManager")
        local BC = require("ui.battle.combat.BattleCombat")
        local PS = require("ui.battle.combat.ProjectileSystem")
        local Stats = require("systems.BattleStats")
        local Driver = require("ui.battle.tri.BattleTriDriver")
        local fixtureId, enemyId = 940, 0

        local function hero(id, nodes)
            return assert(HC.createHero(id, 1, nil, nodes, false, { litNodes = {}, silent = true }))
        end
        local function enemy(armorType)
            enemyId = enemyId + 1
            local attrs = UA.create({
                [AD.MAX_HP] = 1000000, [AD.ARMOR] = 0,
                [AD.PHYS_BLOCK_RATE] = 0, [AD.MAG_BLOCK_RATE] = 0,
                [AD.DODGE] = 0, [AD.ATK_INTERVAL] = 10000,
                armorType = armorType or AD.ARMOR_LEATHER,
            })
            attrs:fillHp()
            local unit = attrs:toBattleUnit("弹射靶" .. enemyId, 1)
            unit.monsterId, unit.instanceId = 1, enemyId
            return unit
        end
        local function enemies(count)
            local list = {}
            for _ = 1, count do list[#list + 1] = enemy() end
            return list
        end
        local function kill(unit)
            unit.hp, unit.attrs.final[AD.HP] = 0, 0
        end
        local function totalHp(list)
            local total = 0
            for _, unit in ipairs(list) do total = total + unit.hp end
            return total
        end
        local function shocked(list)
            local count = 0
            for _, unit in ipairs(list) do
                if SEM.has(unit, SEM.SHOCKED) then count = count + 1 end
            end
            return count
        end
        local function liveProjectiles()
            return PS.mountedState().projectiles
        end
        local function soleProjectile(label)
            local list = liveProjectiles()
            check(#list == 1, label .. "仅一个真实投射物")
            return list[1]
        end

        -- 每个用例使用真实实验室驱动；账号查询固定返回空，不借玩家队伍或成长。
        -- 观察器透明调用原 bindContext 出口，不手工生成弹体或提前执行落地回调。
        local function fixture(attacker, targets, team)
            fixtureId = fixtureId + 1
            local drv = Driver.new(team or fixtureId, {
                battleLab = true, timeLimit = 1000,
                allyFactory = function() return { attacker } end,
            })
            drv:start(101)
            drv.enemies, drv.enemyQueue = targets, {}
            drv.introTimer, drv.reinforceCd = 0, 0
            drv.stageTotal = #targets
            drv:activate()
            for _, unit in ipairs(targets) do TAL.initUnit(unit) end
            TAL.onBattleStart(drv.allies, targets)
            BC.reset(); PS.reset(); SEM.reset(); Stats.resetAccum()
            drv:activate()
            local f = { driver = drv, attacker = attacker, targets = targets,
                attacks = {}, talents = {}, landed = 0, talentHits = 0 }
            local context = BC.mountedState().ctx
            local nativeAttack, nativeTalent = context.onAttackHit, context.onTalentDealDamage
            context.onAttackHit = function(a, target, sx, sy, tx, ty, result, applyHit)
                local rec = { target = target, result = result }
                f.attacks[#f.attacks + 1] = rec
                nativeAttack(a, target, sx, sy, tx, ty, result, function(...)
                    f.landed = f.landed + 1
                    return applyHit(...)
                end)
                rec.proj = liveProjectiles()[#liveProjectiles()]
            end
            context.onTalentDealDamage = function(a, target, tx, ty, prefix, applyDamage, opts)
                local rec = { target = target, prefix = prefix, opts = opts, applications = 0, actual = 0 }
                f.talents[#f.talents + 1] = rec
                nativeTalent(a, target, tx, ty, prefix, function()
                    rec.applications = rec.applications + 1
                    f.talentHits = f.talentHits + 1
                    -- 正式攻击流水线的附伤闭包不返回数值，直接观察真实HP/盾变化。
                    local before = target.hp + (target.attrs.energyShield or 0) + (target.attrs.tempEnergyShield or 0)
                    local returned = applyDamage()
                    local after = target.hp + (target.attrs.energyShield or 0) + (target.attrs.tempEnergyShield or 0)
                    rec.actual = before - after
                    return returned
                end, opts)
                rec.proj = liveProjectiles()[#liveProjectiles()]
            end
            function f:activate() self.driver.mount() end
            function f:attack()
                self:activate()
                BC.performAttack(self.attacker, self.driver.enemies, true)
            end
            function f:step(dt)
                self:activate()
                PS.update(dt or 20)
            end
            return f
        end
        local function drain(f)
            for _ = 1, 16 do
                if #liveProjectiles() == 0 then break end
                f:step()
            end
            check(#liveProjectiles() == 0, "所有真实弹体完整退场")
        end
        local function run(label, fn)
            print("[技能弹射回归] " .. label)
            local caseOK, caseError = pcall(fn)
            formulaRestore()
            formulaRestore = function() end
            if not caseOK then check(false, label .. "执行异常：" .. tostring(caseError)) end
        end
        local function observeFormula(records)
            local original = CF.calcAttack
            CF.calcAttack = function(a, target, ...)
                local result = original(a, target, ...)
                records[#records + 1] = { target = target, result = result }
                return result
            end
            formulaRestore = function() CF.calcAttack = original end
        end

        run("#6 三敌独立结果与串行落地", function()
            local a, list = hero(6), enemies(3)
            list[2].attrs.armorType = AD.ARMOR_PLATE
            local f, computed = fixture(a, list), {}
            local before = totalHp(list)
            observeFormula(computed)
            f:attack()
            check(a.attackChain == true and HC.HEROES[6].attackChain == true, "#6 配置及正式英雄均启用主攻击链")
            check(#computed == 3, "#6 一次出手为三目标各计算一次真实CF结果")
            check(computed[1].result ~= computed[2].result and computed[2].result ~= computed[3].result
                and computed[1].result.hits ~= computed[2].result.hits
                and computed[2].result.hits[1] ~= computed[3].result.hits[1], "#6 三份结果与单段伤害表彼此独立")
            check(#f.attacks == 1 and f.landed == 0 and #f.talents == 0, "#6 首帧不是三弹齐射或新增天赋附伤")
            check(totalHp(list) == before and shocked(list) == 0, "#6 飞行前不扣血、不提前感电")
            local previous = soleProjectile("#6 首帧")
            local accumulated = 0
            for index = 1, 3 do
                f:step(20)
                check(f.landed == index, "#6 大dt每帧只落地一段 index=" .. index)
                check(#computed == 3, "#6 弹射不重算CF或复制首段伤害 index=" .. index)
                local rec = f.attacks[index]
                check(rec.result == computed[index].result, "#6 每段复用原目标独立结果 index=" .. index)
                accumulated = accumulated + (rec.result.actualDamage or 0)
                check(Stats.getTotal("hitCount") == index and Stats.getTotal("critHitCount") == index,
                    "#6 每段仍是原普攻独立统计 index=" .. index)
                check(Stats.getTotal("totalDamage") == accumulated and totalHp(list) == before - accumulated,
                    "#6 扣血与伤害统计无新增链伤 index=" .. index)
                check(shocked(list) == index, "#6 每段落地独立附加感电 index=" .. index)
                if index < 3 then
                    local nextProj = soleProjectile("#6 下一跳")
                    check(nextProj.timer == 0 and not nextProj.arrived, "#6 新弹timer=0，不重消费大dt")
                    check(samePoint(nextProj, previous), "#6 下一起点等于上一真实弹体终点")
                    previous = nextProj
                end
            end
            check(#f.attacks == 3 and #f.talents == 0, "#6 三段完成不新增第四段/天赋附伤")
            drain(f)
        end)

        run("#6 MISS、全盾、单敌及全死", function()
            do
                local a, list = hero(6), enemies(3)
                local f = fixture(a, list)
                a.attrs.final[AD.HIT_VALUE] = -150
                local before = totalHp(list)
                f:attack(); f:step()
                check(#f.attacks == 0 and #liveProjectiles() == 0 and totalHp(list) == before
                    and shocked(list) == 0, "#6 全MISS不发命中链、不扣血、不感电")
            end
            do
                local a, list = hero(6), enemies(3)
                local f = fixture(a, list)
                for _, unit in ipairs(list) do unit.attrs.energyShield = 100000 end
                local hpBefore = totalHp(list)
                f:attack()
                for index = 1, 3 do
                    f:step()
                    check(f.landed == index and shocked(list) == index, "#6 全盾仍命中并继续下一段")
                end
                check(totalHp(list) == hpBefore and Stats.getTotal("hitCount") == 3,
                    "#6 全盾HP不变、三段各记原普攻统计")
                check(list[1].attrs.energyShield < 100000 and list[2].attrs.energyShield < 100000
                    and list[3].attrs.energyShield < 100000, "#6 全盾每个目标仅扣自身护盾")
                drain(f)
            end
            do
                local f = fixture(hero(6), enemies(1))
                f:attack(); f:step()
                check(#f.attacks == 1 and f.landed == 1 and #liveProjectiles() == 0,
                    "#6 单敌只一段且正常完成")
            end
            do
                local list = enemies(3)
                local f = fixture(hero(6), list)
                for _, unit in ipairs(list) do kill(unit) end
                f:attack(); f:step()
                check(#f.attacks == 0 and #liveProjectiles() == 0, "#6 开始时全死无链")
            end
            do
                local list = enemies(3)
                local f = fixture(hero(6), list)
                f:attack()
                for _, unit in ipairs(list) do kill(unit) end
                f:step()
                check(#f.attacks == 1 and #liveProjectiles() == 0 and Stats.getTotal("totalDamage") == 0,
                    "#6 飞行中全死不伤死人、不发下一跳")
            end
        end)

        run("#6 同英雄并发两链与换波失效", function()
            do
                local f = fixture(hero(6), enemies(3))
                f:attack(); f:attack()
                check(#liveProjectiles() == 2 and #f.attacks == 2, "#6 同英雄两次出手各有独立首弹")
                for index = 1, 3 do
                    f:step()
                    check(f.landed == index * 2, "#6 新普攻不截断旧链 index=" .. index)
                    if index < 3 then
                        check(#liveProjectiles() == 2 and liveProjectiles()[1].timer == 0
                            and liveProjectiles()[2].timer == 0, "#6 双链新弹均留至下帧")
                    end
                end
                check(Stats.getTotal("hitCount") == 6 and #f.attacks == 6,
                    "#6 同英雄并发两条完整三段链")
                drain(f)
            end
            for _, unitToken in ipairs({ false, true }) do
                local a, list = hero(6), enemies(3)
                local f = fixture(a, list)
                f:attack()
                local before = totalHp(list)
                if unitToken then
                    TAL.onBattleStart(f.driver.allies, list)
                else
                    -- 刻意保留旧PS弹体，验证token守门而不是仅靠清空列表。
                    BC.reset()
                end
                f:step()
                check(totalHp(list) == before and #f.attacks == 1 and #liveProjectiles() == 0,
                    "#6 " .. (unitToken and "单位开战token" or "换波chainToken") .. "使旧链失效")
            end
        end)

        run("#3 觉醒Ⅲ精确三次普攻后串行两次散射", function()
            local a, list = hero(3, awake(false, false, true)), enemies(4)
            local f, computed = fixture(a, list), {}
            observeFormula(computed)
            for index = 1, 2 do
                f:attack()
                check(#f.attacks == index and #f.talents == 0, "#3 前两次出手不触发精准散射")
                f:step()
                check(#f.talents == 0 and #liveProjectiles() == 0, "#3 前两次真实落地仍无散射")
            end
            f:attack()
            check(#computed == 3 and #f.attacks == 3 and #f.talents == 0,
                "#3 精确三次performAttack，第三弹到达前不并发散射")
            check(computed[3].result.isCrit == true, "#3 第三次攻击由真实天赋保证精准暴击")
            local previous = soleProjectile("#3 第三次主弹")
            f:step()
            check(#f.talents == 1 and f.talentHits == 0, "#3 精准落地后只发第一额外目标")
            local first = soleProjectile("#3 第一散射")
            check(first.timer == 0 and samePoint(first, previous), "#3 首散射从主弹真实终点出发且timer=0")
            f:step()
            check(#f.talents == 2 and f.talentHits == 1, "#3 第一散射落地后才发第二散射")
            local second = soleProjectile("#3 第二散射")
            check(second.timer == 0 and samePoint(second, first), "#3 第二散射从第一真实终点出发")
            f:step()
            check(#f.talents == 2 and f.talentHits == 2 and #liveProjectiles() == 0,
                "#3 四个敌人仍最多两个额外目标，不新增第三散射")
            check(f.talents[1].target ~= f.talents[2].target
                and f.talents[1].target ~= f.attacks[3].target
                and f.talents[2].target ~= f.attacks[3].target, "#3 主目标和两个散射目标互不重复")
            check(#computed == 3 and TAL.mountedUnitStates()[a].atkCount == 3,
                "#3 散射不递归CF、不推进攻击计数")
        end)

        run("#13 基础倍率、觉醒可A↔B重复且并发链不互断", function()
            for _, nodes in ipairs({ awake(false, false, false), awake(false, false, true), awake(false, true, true) }) do
                local a, list = hero(13, nodes), enemies(2)
                local f = fixture(a, list)
                f:attack()
                local previous = soleProjectile("#13 主弹")
                f:step()
                local count = nodes[3] and 3 or 1
                local primary = f.attacks[1]
                check(#f.talents == 1, "#13 主弹落地只生成一条弹射")
                local lastTarget = primary.target
                for index = 1, count do
                    local nextProj = soleProjectile("#13 弹射" .. index)
                    check(nextProj.timer == 0 and samePoint(nextProj, previous), "#13 相邻真实端点相连且大dt不吞下一跳")
                    check(f.talents[index].target ~= lastTarget, "#13 不原地命中同一目标")
                    lastTarget = f.talents[index].target
                    f:step()
                    local mult = 0.5 + (nodes[2] and index * 0.15 or 0)
                    check(f.talents[index].actual == math.floor(primary.result.totalDamage * mult + 0.5),
                        "#13 原有逐段倍率保留 index=" .. index)
                    check(f.talentHits == index, "#13 每帧只落地一段天赋链")
                    previous = nextProj
                end
                check(#f.talents == count and #liveProjectiles() == 0, "#13 完成配置规定的完整链")
                if nodes[3] then
                    check(f.talents[2].target == primary.target
                        and f.talents[3].target == f.talents[1].target,
                        "#13 觉醒Ⅲ两敌可B→A→B，不能被去重提前截断")
                end
                check(Stats.getTotal("hitCount") == count + 1 and Stats.getTotal("critHitCount") == 1,
                    "#13 弹射不增加可暴击普攻统计分母")
            end
            do
                local f = fixture(hero(13, awake(false, false, true)), enemies(2))
                f:attack(); f:attack()
                for _ = 1, 4 do f:step() end
                check(#f.attacks == 2 and #f.talents == 6 and f.talentHits == 6
                    and #liveProjectiles() == 0, "#13 同英雄并发两条三跳链不互相取消")
            end
        end)

        run("#13 死目标移除后仍从上一真实落点出发", function()
            local f = fixture(hero(13, awake(false, false, true)), enemies(3))
            f:attack(); f:step()
            local primaryTarget = f.attacks[1].target
            kill(primaryTarget)
            for index, unit in ipairs(f.driver.enemies) do
                if unit == primaryTarget then table.remove(f.driver.enemies, index); break end
            end
            local previous = soleProjectile("#13 移除上一命中目标后的在飞弹")
            f:step()
            local nextProj = soleProjectile("#13 死目标移除后的下一跳")
            check(samePoint(nextProj, previous) and nextProj.timer == 0,
                "#13 不重新查找已删除卡片位置，下一跳从上一真实落点发射")
            drain(f)
            check(f.talentHits == 3, "#13 死目标移除后剩余两个敌人仍完成三跳")
        end)

        run("真实三行挂载隔离及#13天赋出口", function()
            local rows = {}
            for team = 1, 3 do
                local f = fixture(hero(13, awake(false, false, true)), enemies(2), team)
                rows[#rows + 1] = f
                f:attack()
            end
            for step = 1, 4 do
                for team, f in ipairs(rows) do
                    f:step()
                    check(PS.mountedState() == f.driver.psState
                        and BC.mountedState() == f.driver.combatState, "三行状态挂载只属于当前行 team=" .. team)
                    if step < 4 then
                        local proj = soleProjectile("三行第" .. team .. "行")
                        check(proj.timer == 0, "三行大dt下一跳均留到下一帧")
                    end
                end
            end
            for team, f in ipairs(rows) do
                f:activate()
                check(#f.talents == 3 and f.talentHits == 3 and #f.driver.psState.projectiles == 0,
                    "真实TriDriver.bindContext第" .. team .. "行完成主弹及三跳天赋")
                check(Stats.getTotal("hitCount") == 4 and Stats.getTotal("critHitCount") == 1,
                    "三行伤害统计不串桶 team=" .. team)
            end
        end)

        run("飞行中目标死亡重飞与同场换表", function()
            do
                local f = fixture(hero(6), enemies(4))
                f:attack(); f:step()
                local previous = f.attacks[1].proj
                local inFlight = soleProjectile("#6 待失效第二跳")
                kill(f.attacks[2].target)
                local before = totalHp(f.driver.enemies)
                f:step()
                local retry = soleProjectile("#6 死目标重飞")
                check(totalHp(f.driver.enemies) == before and Stats.getTotal("hitCount") == 1,
                    "#6 飞向死人不隔空扣其他敌人的血、不消费第二段")
                check(retry ~= inFlight and samePoint(retry, previous) and retry.timer == 0,
                    "#6 同段从上一真实命中点重新飞向活敌")
                drain(f)
                check(Stats.getTotal("hitCount") == 3, "#6 死目标重选后仍完成原三段")
            end
            for _, id in ipairs({ 3, 13 }) do
                local a = hero(id, id == 3 and awake(false, false, true) or nil)
                local f = fixture(a, enemies(4))
                if id == 3 then
                    f:attack(); f:step(); f:attack(); f:step()
                end
                f:attack(); f:step()
                local previous = f.attacks[#f.attacks].proj
                local oldTarget = f.talents[1].target
                local oldHp = oldTarget.hp
                f.driver.enemies = enemies(4)
                f.driver.talRefs.bEnemies = f.driver.enemies
                local before = totalHp(f.driver.enemies)
                f:step()
                local retry = soleProjectile("#" .. id .. " 换表重飞")
                check(oldTarget.hp == oldHp and totalHp(f.driver.enemies) == before and f.talentHits == 0,
                    "#" .. id .. " 离场旧对象不扣血、新表敌人不隔空扣血")
                check(samePoint(retry, previous) and retry.timer == 0,
                    "#" .. id .. " 当前新目标表仍从上一真实命中点重飞")
                drain(f)
                check(f.talentHits == (id == 3 and 2 or 1),
                    "#" .. id .. " 跟进新表且保留原额外段数")
            end
        end)

        run("回调清空投射物后不重生旧链", function()
            for _, id in ipairs({ 6, 13 }) do
                local f = fixture(hero(id, id == 13 and awake(false, false, true) or nil), enemies(4))
                if id == 13 then f:attack(); f:step() end
                local target = id == 13 and f.talents[1].target or nil
                if id == 6 then f:attack(); target = f.attacks[1].target end
                local original = target.attrs.takeDamage
                target.attrs.takeDamage = function(self, ...)
                    local actual = original(self, ...)
                    PS.reset()
                    return actual
                end
                f:step()
                target.attrs.takeDamage = original
                check(#liveProjectiles() == 0,
                    "#" .. id .. " 伤害回调PS.reset后不向新队列塞旧下一跳")
            end
            PS.reset()
            local hits = 0
            PS.spawnPierce({ heroId = 2 }, 0, 0, 400, 0, {
                { atT = 0.1, onHit = function() hits = hits + 1; PS.reset() end },
                { atT = 0.2, onHit = function() hits = hits + 1 end },
            })
            PS.update(20)
            check(hits == 1 and #liveProjectiles() == 0,
                "穿透回调reset后不继续旧弹剩余命中事件")
        end)

        run("治疗仍并发及飞剑仍齐射", function()
            do
                local healer = hero(9)
                local f = fixture(healer, enemies(1))
                local other = hero(1)
                f.driver.allies = { healer, other }
                TAL.initUnit(other)
                TAL.onBattleStart(f.driver.allies, f.driver.enemies)
                for _, unit in ipairs(f.driver.allies) do
                    unit.hp = math.floor(unit.maxHp / 2)
                    unit.attrs.final[AD.HP] = unit.hp
                end
                f:attack()
                check(#liveProjectiles() == 2 and #f.attacks == 2,
                    "治疗两目标仍同帧发射，不被主攻击链串行化")
                for _, proj in ipairs(liveProjectiles()) do
                    check(proj.cfg.type == "bezier" and proj.cfg.arc == "heal", "治疗仍保留向上贝塞尔治疗弧")
                end
                f:step()
                check(Stats.getTotal("totalHeal") > 0 and #f.talents == 0, "治疗真实落地仍回血且不新增攻击弹射")
            end
            do
                local a, list = hero(16), enemies(1)
                local f = fixture(a, list)
                local before = list[1].hp
                for index = 1, 3 do
                    BC.dealTalentDamage(a, list[1], 10, false, "灵月飞剑", nil, {
                        target = list[1], flyingSwordIndex = index, flyingSwordCount = 3,
                    })
                end
                check(#liveProjectiles() == 3 and f.talentHits == 0, "飞剑仍三柄同帧齐射，不改为串行")
                for _, proj in ipairs(liveProjectiles()) do
                    check(proj.cfg.type == "flyingSword" and proj.timer == 0,
                        "飞剑保留圆环外扩与齐射弹型")
                end
                f:step()
                check(list[1].hp == before - 30 and f.talentHits == 3, "飞剑齐射仍每柄仅结算一次原伤害")
            end
        end)
        check(accountWrites == 0, "全部回归无账号写入或网络存档操作")
        print("[技能弹射回归] 空账号外围查询次数=" .. accountQueries)
    end)
    formulaRestore()
    math.random = nativeRandom
    rawset(_G, "require", nativeRequire)
    if not ok then
        failures = failures + 1
        print("[技能弹射回归][FAIL] 执行异常：" .. tostring(err))
    end
    print(string.format("[skill_chain_bounce_test] assertions=%d failures=%d %s",
        assertions, failures, failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
