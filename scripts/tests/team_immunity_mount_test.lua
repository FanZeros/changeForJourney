-- T02 专项：免疫次数随战线挂载，开战/切关/消费不得修改旁队。
-- 真实 Driver.start/activate、TAL 开场/敌死/复活、RCH 与普攻命中链；
-- 编队来源与持久化出口使用内存替身，不读写玩家存档，不发奖励。
-- 跑法：timeout 90s /workspace/.cli/UrhoXRuntime tests/team_immunity_mount_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
local assertions, failures = 0, 0
local function check(ok, label)
    assertions = assertions + 1
    if ok then
        print("[T02][PASS] " .. label)
    else
        failures = failures + 1
        print("[T02][FAIL] " .. label)
    end
end

local function runCase(name, fn)
    print("[T02][CASE] " .. name)
    local ok, err = pcall(fn)
    if not ok then check(false, name .. " 异常：" .. tostring(err)) end
end

function Start()
    local restores = {}
    local function patch(owner, key, value)
        local original = owner[key]
        restores[#restores + 1] = function() owner[key] = original end
        owner[key] = value
    end
    local ok, err = pcall(function()
        local AD = require("systems.AttributeDef")
        local HC = require("config.HeroConfig")
        local AC = require("config.AwakeningConfig")
        local RCH = require("systems.RelicConditionHandler")
        local TAL = require("systems.TalentManager")
        local SEM = require("systems.StatusEffectManager")
        local TM = require("systems.ThreatManager")
        local ART = require("systems.ArtifactRuntime")
        local BC = require("ui.battle.combat.BattleCombat")
        local PS = require("ui.battle.combat.ProjectileSystem")
        local BE = require("ui.battle.combat.BattleEffects")
        local Stats = require("systems.BattleStats")
        local Driver = require("ui.battle.tri.BattleTriDriver")
        local CP = require("ui.character.panel.CharacterPanel")
        local Dispatcher = require("runtime.ClientDispatcher")
        local GameAction = require("runtime.GameAction")
        local ETS = require("systems.ExtraTalentSystem")
        local CF = require("systems.CombatFormula")
        local oldLitNodes = HC._getSavedLitNodes()
        restores[#restores + 1] = function() HC.setDefaultLitNodes(oldLitNodes) end
        HC.setDefaultLitNodes(nil)

        -- 保存/恢复进入测试前的挂载引用，不把测试战线留在业务单例上。
        for _, subsystem in ipairs({ BC, PS, BE, TAL, TM, SEM }) do
            local old = subsystem.mountedState()
            restores[#restores + 1] = function() subsystem.mount(old) end
        end
        local oldStatsTeam = Stats.mountedTeam()
        restores[#restores + 1] = function() Stats.mount(oldStatsTeam) end
        if RCH.mountedState then
            local oldRch = RCH.mountedState()
            restores[#restores + 1] = function() RCH.mount(oldRch) end
            RCH.mount(RCH.newState())
        end

        local teams = {}
        local signatures = {}
        local factories = {}
        local effectsToClean = {}
        patch(CP, "getTeamSignature", function(team) return signatures[team] or ("T02-team-" .. team) end)
        patch(CP, "getDeployedTeam", function(team)
            local make = factories[team]
            local list = make and make() or {}
            teams[team] = list
            effectsToClean[#effectsToClean + 1] = list
            return list
        end)
        patch(CP, "getOwnedHero", function() return nil end)
        patch(Dispatcher, "get", function(key)
            if key == "heroes" then return { roster = {} } end
            return nil
        end)
        patch(GameAction, "sendAction", function() error("T02不能发送持久化或奖励动作") end)
        patch(require("boot.StandaloneSave"), "Flush", function() error("T02不能写玩家存档") end)
        -- 固定普攻公式的输入结果，保留 BC.performAttack→投射物→RCH→真实扣血。
        patch(CF, "calcAttack", function()
            return { category = "physical", isMiss = false, isCrit = false, resistance = 0,
                comboCount = 0, totalDamage = 7,
                hits = { { damage = 7, isCrit = false, isBlocked = false } } }
        end)
        -- 普通免疫专项不依赖随机数；敌死追加1~2次/复活概率取确定成功分支。
        patch(math, "random", function(m, n)
            if n then return m end
            if m then return 1 end
            return 0
        end)

        local awakened = { [2] = true, _awk3Migrated = true }
        local function makeSpy()
            return assert(HC.createHero(14, 10, nil, awakened, ETS.normalize(nil)))
        end
        local function prepare(team)
            factories[team] = function() return { makeSpy() } end
            signatures[team] = "T02-spy-" .. team
            return Driver.new(team)
        end
        local function charge(drv)
            drv:activate()
            return RCH.getImmunityCount(drv.allies[1])
        end
        local function consume(drv, count)
            drv:activate()
            for _ = 1, count do
                check(RCH.onBeforeTakeDamage(drv.allies[1], 7) == 0,
                    "队" .. drv.teamIdx .. " 本线正伤害免疫一次")
            end
        end
        local function hit(drv)
            drv:activate()
            local spy = drv.allies[1]
            local beforeHp, beforeCount = spy.hp, RCH.getImmunityCount(spy)
            BC.performAttack(drv.enemies[1], drv.allies, false)
            PS.update(10)
            check(spy.hp == beforeHp and RCH.getImmunityCount(spy) == beforeCount - 1,
                "队" .. drv.teamIdx .. " 真实普攻命中消费1次且生命不变")
        end

        runCase("正式内鬼共鸣构筑", function()
            local spy = makeSpy()
            check(AC.hasNode(spy.awakeningNodes, 5), "新觉醒2映射开场免疫旧节点5")
            check(not spy.relicConditions or #spy.relicConditions == 0,
                "不依赖已删遗物词条，免疫确由现行天赋追加")
        end)

        for _, order in ipairs({ { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 },
            { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 }, { 1, 2 }, { 2, 1 } }) do
            runCase("启动顺序 " .. table.concat(order, ","), function()
                local drivers, expected = {}, {}
                for step, team in ipairs(order) do
                    local drv = prepare(team)
                    drivers[team] = drv
                    drv:start(101)
                    expected[team] = 10
                    check(charge(drv) == 10, "队" .. team .. " 开战获得10次免疫")
                    for i = 1, step - 1 do
                        local previous = order[i]
                        check(charge(drivers[previous]) == expected[previous],
                            "队" .. team .. " 启动不清队" .. previous .. " 剩余次数")
                    end
                    consume(drv, step)
                    expected[team] = 10 - step
                end
                for _, team in ipairs(order) do
                    check(charge(drivers[team]) == expected[team], "多次activate不消费队" .. team .. " 次数")
                end
            end)
        end

        runCase("旁队切关/空编队/本队重开", function()
            local drivers = { prepare(1), prepare(2), prepare(3) }
            for _, drv in ipairs(drivers) do drv:start(101) end
            for team, drv in ipairs(drivers) do consume(drv, team) end
            local oldSpy = drivers[2].allies[1]
            drivers[2]:start(102)
            check(charge(drivers[1]) == 9 and charge(drivers[3]) == 7,
                "队2换关保留队1/3已经消费过的次数")
            check(charge(drivers[2]) == 10 and drivers[2].allies[1] ~= oldSpy,
                "仅本队新战斗重新获得10次，新单位引用替换")
            drivers[2]:activate()
            check(RCH.getImmunityCount(oldSpy) == 0, "本队旧单位不残留免疫状态")
            factories[2] = function() return {} end
            drivers[2]:start(103)
            check(#drivers[2].allies == 0 and charge(drivers[1]) == 9 and charge(drivers[3]) == 7,
                "空编队重开也不能清旁队次数")
            drivers[1]:activate()
            RCH.reset()
            check(charge(drivers[1]) == 0 and charge(drivers[3]) == 7,
                "显式reset只清当前挂载战线")
        end)

        runCase("真实普攻/耗尽/零伤害边界", function()
            local drivers = { prepare(1), prepare(2), prepare(3) }
            for _, drv in ipairs(drivers) do drv:start(101) end
            for _, drv in ipairs(drivers) do
                hit(drv)
                drv:activate()
                local spy = drv.allies[1]
                check(RCH.onBeforeTakeDamage(spy, 0) == 0
                    and RCH.onBeforeTakeDamage(spy, -7) == -7
                    and RCH.getImmunityCount(spy) == 9,
                    "队" .. drv.teamIdx .. " 零/负伤害不消费免疫")
                consume(drv, 9)
                check(RCH.onBeforeTakeDamage(spy, 7) == 7 and RCH.getImmunityCount(spy) == 0,
                    "队" .. drv.teamIdx .. " 第11次正伤害不再免疫、不产生负次数")
            end
        end)

        runCase("真实敌死追加次数按挂载队消费", function()
            local first, other = prepare(1), prepare(3)
            first:start(101)
            other:start(101)
            consume(first, 3)
            first:activate()
            local enemy = first.enemies[1]
            enemy.hp, enemy.attrs.final[AD.HP] = 0, 0
            TAL.onEnemyDeath(enemy, first.allies, first.enemies)
            check(charge(first) == 8 and charge(other) == 10,
                "真实内鬼敌死追加1次，旁线未改变")
            first:activate()
            TAL.onEnemyDeath(enemy, first.allies, first.enemies)
            check(charge(first) == 8, "同一死亡事件不重复追加免疫")
            first.allies[1].hp = 0
            first.allies[1].attrs.final[AD.HP] = 0
            check(charge(first) == 8, "死亡本身不消费/重授RCH免疫")
        end)

        runCase("真实本线复活保留剩余次数", function()
            local first, other = prepare(1), prepare(2)
            factories[1] = function()
                return { makeSpy(), assert(HC.createHero(15, 10, nil, nil, ETS.normalize(nil))) }
            end
            first:start(101)
            other:start(101)
            consume(first, 4)
            local spy = first.allies[1]
            spy.hp, spy.attrs.final[AD.HP] = 0, 0
            first:activate()
            check(TAL.onAllyDeath(spy, first.allies, BC.syncUnitHp) and spy.hp > 0,
                "生产复活钩子恢复同一单位生命")
            check(charge(first) == 6 and charge(other) == 10,
                "本线复活不重授开战10次、不清旁队次数")
            consume(first, 1)
            check(charge(first) == 5, "复活后继续消费死亡前剩余次数")
        end)

        runCase("与SEM/TM同构的容器及默认挂载协议", function()
            local protocol = type(RCH.newState) == "function" and type(RCH.mount) == "function"
                and type(RCH.mountedState) == "function"
            check(protocol, "RCH提供newState/mount/mountedState挂载协议")
            if not protocol then return end
            local a, b = RCH.newState(), RCH.newState()
            local spy = makeSpy()
            RCH.mount(a)
            RCH.addImmunityCharges(spy, 4)
            RCH.mount(b)
            check(RCH.getImmunityCount(spy) == 0, "同一单位引用在不同容器不共享记录")
            RCH.addImmunityCharges(spy, 2)
            RCH.mount(a)
            check(RCH.getImmunityCount(spy) == 4 and RCH.mountedState() == a,
                "恢复挂载引用同时恢复本容器次数")
            RCH.reset()
            check(RCH.mountedState() == a and RCH.getImmunityCount(spy) == 0,
                "reset替换内部表但不替换外部容器引用")
            RCH.mount(b)
            check(RCH.getImmunityCount(spy) == 2, "reset没有修改另一容器")
            RCH.initBattle({})
            check(RCH.mountedState() == b and RCH.getImmunityCount(spy) == 0,
                "initBattle同样只初始化挂载容器")
            RCH.mount(nil)
            local default = RCH.mountedState()
            RCH.mount(nil)
            check(RCH.mountedState() == default and default ~= a and default ~= b,
                "nil挂载恢复稳定默认容器，与独立战线隔离")
        end)

        runCase("reset清条件修饰符只影响当前战线", function()
            local first, other = prepare(1), prepare(2)
            first:start(101)
            other:start(101)
            local a, b = first.allies[1], other.allies[1]
            local conditions = { { condition = "满血时", adKey = AD.PHYS_ATK, value = 5 } }
            a.relicConditions, b.relicConditions = conditions, conditions
            first:activate()
            RCH.initBattle(first.allies)
            RCH.update(first.allies, 0)
            local beforeA = a.attrs:get(AD.PHYS_ATK)
            other:activate()
            RCH.initBattle(other.allies)
            RCH.update(other.allies, 0)
            local beforeB = b.attrs:get(AD.PHYS_ATK)
            first:activate()
            RCH.reset()
            check(a.attrs:get(AD.PHYS_ATK) == beforeA - 5 and b.attrs:get(AD.PHYS_ATK) == beforeB,
                "清理本队条件modifier，不移除旁队modifier")
            other:activate()
            RCH.reset()
            check(b.attrs:get(AD.PHYS_ATK) == beforeB - 5, "旁队可独立清理自身条件modifier")
        end)
        -- 清测试专属单位临时效果。无奖励、击杀来源为空、复活者无觉醒，不产生永久成长。
        for _, list in ipairs(effectsToClean) do ART.reset(list) end
        ETS.flush()
    end)
    if not ok then check(false, "初始化/收尾异常：" .. tostring(err)) end
    for i = #restores, 1, -1 do restores[i]() end
    print(string.format("[T02][SUMMARY] assertions=%d failures=%d", assertions, failures))
    if failures == 0 then print("[T02] ALL PASS")
    else log:Write(LOG_ERROR, "[T02] failures=" .. failures) end
    engine:Exit()
end
