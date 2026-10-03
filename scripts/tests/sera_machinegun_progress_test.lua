-- 塞拉连射计数回归：小数门槛保留余量，攻击口径和连射刷新行为不变。
-- 使用正式 helper、攻击钩子及 TAL.update；不修改 ETS 成长或技能倍率。
local AD = require("systems.AttributeDef")
local HC = require("config.HeroConfig")
local ETS = require("systems.ExtraTalentSystem")
local TAL = require("systems.TalentManager")
local Sera = require("systems.talents.TalentSera")
local Before = require("systems.talents.TalentBeforeAttack")
local Combo = require("systems.talents.TalentComboAttack")

local assertions, failures = 0, 0
local function check(condition, message)
    assertions = assertions + 1
    if condition then
        print("[塞拉回归][PASS] " .. message)
    else
        failures = failures + 1
        print("[塞拉回归][FAIL] " .. message)
    end
end

local function near(a, b)
    return math.abs((a or 0) - b) < 1e-8
end

local function hero(id)
    return assert(HC.createHero(id, 1, nil, nil, false))
end

local function fixture(nodes, cut)
    local attacker = hero(22)
    local s = { heroId = 22 }
    local logs = {}
    local helper = Sera.bind({
        hasAwaken = function(_, node) return nodes[node] == true end,
        talentLog = function(msg) logs[#logs + 1] = msg end,
        AD = AD,
    })
    ETS.getGatlingCut = function() return cut end
    return attacker, s, helper, logs
end

local function tick(attacker, s, helper, n)
    for _ = 1, n do helper.tickSeraMachineGunCount(attacker, s) end
end

local function testThresholds()
    for _, case in ipairs({
        { nodes = {}, interval = 20 },
        { nodes = { [1] = true }, interval = 18 },
        { nodes = { [1] = true, [5] = true }, interval = 15 },
    }) do
        local a, s, helper, logs = fixture(case.nodes, 0)
        tick(a, s, helper, case.interval - 1)
        check(#logs == 0 and s.machineGunShotsLeft == nil, "整数门槛前不触发：" .. case.interval)
        tick(a, s, helper, 1)
        check(#logs == 1 and s.machineGunShotsLeft == 10 and near(s.machineGunProgress, 0),
            "整数门槛准时触发并扣进度：" .. case.interval)
        tick(a, s, helper, case.interval)
        check(#logs == 2 and s.machineGunNormalCount == case.interval * 2,
            "整数总计数连续增长、不被触发清零：" .. case.interval)
    end

    local a, s, helper, logs = fixture({}, 0.05)
    tick(a, s, helper, 19)
    check(#logs == 0, "0.05 减免不会立即少需一次攻击")
    tick(a, s, helper, 1)
    check(#logs == 1 and near(s.machineGunProgress, 0.05), "20次攻击启动第一轮并保留0.05余量")
    tick(a, s, helper, 378)
    check(#logs == 19, "398次攻击尚未到第20轮")
    tick(a, s, helper, 1)
    check(#logs == 20 and near(s.machineGunProgress, 0) and s.machineGunNormalCount == 399,
        "399次累计节省一次攻击，浮点边界不晚触发")

    a, s, helper, logs = fixture({}, 0.5)
    tick(a, s, helper, 39)
    check(#logs == 2 and near(s.machineGunProgress, 0), "19.5门槛两轮合计39次攻击")
    tick(a, s, helper, 1)
    check(s.machineGunNormalCount == 40 and near(s.machineGunProgress, 1), "总计数与剩余进度独立")

    a, s, helper, logs = fixture({}, 0)
    tick(a, s, helper, 19)
    ETS.getGatlingCut = function() return 12 end
    tick(a, s, helper, 1)
    check(#logs == 1 and near(s.machineGunProgress, 4) and s.machineGunShotsLeft == 10,
        "门槛20降到8：消耗跨过的两轮，只刷新一轮连射并留下4进度")
    tick(a, s, helper, 4)
    check(#logs == 2 and near(s.machineGunProgress, 0), "门槛变化后继续使用余量、不依赖总计数取模")
    s.machineGunShotsLeft, s.machineGunShotTimer = 3, 0.07
    tick(a, s, helper, 8)
    check(s.machineGunShotsLeft == 10 and s.machineGunShotTimer == 0 and s.machineGunInBurst,
        "连射期间再次达门槛：刷新10发而非追加到13发")

    a, s, helper, logs = fixture({ [3] = true, [4] = true, [6] = true }, 100)
    tick(a, s, helper, 7)
    check(#logs == 0, "极高减免仍保持最低8次门槛")
    tick(a, s, helper, 1)
    check(s.machineGunShotsLeft == 12 and a.attrs.modifiers.sera_burst_pen ~= nil
        and a.attrs.modifiers.sera_burst_speed ~= nil, "最低门槛与12发、穿透、攻速增益保持原行为")
    local empty = {}
    helper.tickSeraMachineGunCount({}, empty)
    check(empty.machineGunNormalCount == nil and empty.machineGunProgress == nil, "无属性单位不推进计数")
end

local function testReference()
    -- 用百分之一攻击为整数单位作独立判据，覆盖全部0.05成长档位。
    local consistent = true
    local detail = ""
    for _, case in ipairs({ { nodes = {}, base = 2000 },
        { nodes = { [1] = true }, base = 1800 },
        { nodes = { [5] = true }, base = 1500 } }) do
        for kills = 0, 240 do
            local a, s, helper, logs = fixture(case.nodes, kills * 0.05)
            local threshold = math.max(800, case.base - kills * 5)
            for count = 1, 400 do
                helper.tickSeraMachineGunCount(a, s)
                local expected = math.floor(count * 100 / threshold)
                local remainder = (count * 100 % threshold) / 100
                if #logs ~= expected or not near(s.machineGunProgress, remainder)
                    or s.machineGunNormalCount ~= count then
                    consistent = false
                    detail = string.format("base=%d kills=%d count=%d", case.base, kills, count)
                    break
                end
            end
            if not consistent then break end
        end
        if not consistent then break end
    end
    check(consistent, "三档基础门槛×241成长档×400攻击与整数判据一致：" .. detail)
end

local function testAttackHooks()
    local a, s, helper = fixture({}, 0.05)
    local getState = function() return s end
    local before = Before.bind({
        getState = getState,
        hasAdv = function() return false end,
        hasAwaken = function() return false end,
        getTAL_BCS = function() return { bAllies = { a }, bEnemies = {} } end,
        tickSeraMachineGunCount = helper.tickSeraMachineGunCount,
    })
    local combo = Combo.bind({
        getState = getState,
        wrapDealDmgForLuoxing = function(_, fn) return fn end,
        tickSeraMachineGunCount = helper.tickSeraMachineGunCount,
    })
    before.onBeforeAttack(a)
    check(s.machineGunNormalCount == 1 and near(s.machineGunProgress, 1), "正式攻击前钩子推进一次")
    s.machineGunBurstShot = true
    before.onBeforeAttack(a)
    check(s.machineGunNormalCount == 1 and near(s.machineGunProgress, 1)
        and s.lastAttackWasBurst and not s.machineGunBurstShot, "正式连射弹消费标记、不计入进度")
    combo.onComboAttack(a, nil, true, {}, function() end, { category = "magic", totalDamage = 1 })
    check(s.machineGunNormalCount == 2 and near(s.machineGunProgress, 2), "连射产生的有效连击仍沿用原计数口径")
    before.onBeforeAttack(a)
    check(s.machineGunNormalCount == 3 and not s.lastAttackWasBurst, "下一次普攻恢复计数")
    combo.onComboAttack(a, nil, true, {}, nil)
    check(s.machineGunNormalCount == 3, "缺少有效伤害回调的连击不推进")
    tick(a, s, helper, 17)
    check(s.machineGunShotsLeft == 10 and near(s.machineGunProgress, 0.05), "普攻与连击共用同一小数余量池")
end

local function testRuntime()
    ETS.getGatlingCut = function() return 0.05 end
    TAL.reset()
    local a, enemy = hero(22), hero(2)
    TAL.onBattleStart({ a }, { enemy })
    for _ = 1, 10 do
        TAL.onBeforeAttack(a)
        TAL.onComboAttack(a, enemy, true, { enemy }, function() end, { category = "magic", totalDamage = 1 })
    end
    local shots = 0
    local ctx = { performAttack = function(unit)
        shots = shots + 1
        TAL.onBeforeAttack(unit)
    end }
    for _ = 1, 12 do TAL.update(0.13, { a }, { enemy }, ctx) end
    check(shots == 10, "正式TAL路径：10普攻+10连击触发10发，连射弹不会自充能")
    for _ = 1, 19 do TAL.onBeforeAttack(a) end
    TAL.update(0.13, { a }, { enemy }, ctx)
    check(shots == 10, "正式TAL路径：下一轮未达门槛不出弹")
    TAL.onBeforeAttack(a)
    for _ = 1, 12 do TAL.update(0.13, { a }, { enemy }, ctx) end
    check(shots == 20, "正式TAL路径：第二轮正常触发10发")
    TAL.reset()
    TAL.initUnit(a)
    TAL.update(0.13, { a }, { enemy }, ctx)
    check(shots == 20, "TAL.reset/initUnit重新开局不继承旧连射或余量")
    ETS.getGatlingCut = function() return 0.5 end
    for _ = 1, 20 do TAL.onBeforeAttack(a) end
    for _ = 1, 12 do TAL.update(0.13, { a }, { enemy }, ctx) end
    check(shots == 30, "正式TAL路径：19.5门槛首轮保留0.5余量")
    TAL.reset()
    TAL.initUnit(a)
    for _ = 1, 19 do TAL.onBeforeAttack(a) end
    TAL.update(0.13, { a }, { enemy }, ctx)
    check(shots == 30, "重新初始化清除0.5余量，19次攻击不得提前触发")
    TAL.onBeforeAttack(a)
    for _ = 1, 12 do TAL.update(0.13, { a }, { enemy }, ctx) end
    check(shots == 40, "重新初始化后第20次攻击正常启动一轮连射")
end

local function testAwakenedRuntime(oldCut)
    -- 这里使用真实三阶映射及真实减免计算；仅替换持久化英雄查询的输入数据。
    ETS.getGatlingCut = oldCut
    local oldOwned = ETS.getOwned
    ETS.getOwned = function() return ETS.normalize({ gatlingKills = 1 }) end
    local ok, err = pcall(function()
        for _, case in ipairs({
            { nodes = { _awk3Migrated = true }, interval = 20, shots = 10, buffs = false },
            { nodes = { [1] = true, _awk3Migrated = true }, interval = 18, shots = 12, buffs = false },
            { nodes = { [1] = true, [2] = true, _awk3Migrated = true }, interval = 15, shots = 12, buffs = true },
        }) do
            TAL.reset()
            local a = assert(HC.createHero(22, 1, nil, case.nodes, ETS.normalize({ gatlingKills = 1 })))
            local enemy = hero(2)
            TAL.onBattleStart({ a }, { enemy })
            check(near(ETS.getGatlingCut(a), case.interval == 20 and 0 or 0.05),
                "真实觉醒与击杀成长计算减免：" .. case.interval)
            local shots = 0
            local ctx = { performAttack = function(unit)
                shots = shots + 1
                TAL.onBeforeAttack(unit)
            end }
            for _ = 1, case.interval - 1 do TAL.onBeforeAttack(a) end
            TAL.update(0.13, { a }, { enemy }, ctx)
            check(shots == 0, "真实觉醒门槛前不出弹：" .. case.interval)
            TAL.onBeforeAttack(a)
            check((a.attrs.modifiers.sera_burst_pen ~= nil) == case.buffs
                and (a.attrs.modifiers.sera_burst_speed ~= nil) == case.buffs,
                "真实觉醒按现有映射添加连射增益：" .. case.interval)
            for _ = 1, 14 do TAL.update(0.13, { a }, { enemy }, ctx) end
            check(shots == case.shots, "真实觉醒连射发数：" .. case.shots)
            check(a.attrs.modifiers.sera_burst_pen == nil and a.attrs.modifiers.sera_burst_speed == nil,
                "连射结束移除临时穿透和攻速增益：" .. case.interval)
        end
    end)
    ETS.getOwned = oldOwned
    assert(ok, err)
end

local function testPendingReset()
    ETS.getGatlingCut = function() return 0.5 end
    TAL.reset()
    local a, enemy = hero(22), hero(2)
    TAL.onBattleStart({ a }, { enemy })
    for _ = 1, 20 do TAL.onBeforeAttack(a) end
    local shots = 0
    local ctx = { performAttack = function(unit)
        shots = shots + 1
        TAL.onBeforeAttack(unit)
    end }
    TAL.update(0.13, { a }, { enemy }, ctx)
    check(shots == 1, "重置夹具：连射仅发1弹，仍有9弹及0.5进度")
    TAL.reset()
    TAL.initUnit(a)
    for _ = 1, 12 do TAL.update(0.13, { a }, { enemy }, ctx) end
    check(shots == 1, "重置后未发完的9弹和计时器不会继续出弹")
    for _ = 1, 19 do TAL.onBeforeAttack(a) end
    TAL.update(0.13, { a }, { enemy }, ctx)
    check(shots == 1, "重置后19次攻击不继承旧0.5余量或总计数")
    TAL.onBeforeAttack(a)
    for _ = 1, 12 do TAL.update(0.13, { a }, { enemy }, ctx) end
    check(shots == 11, "重置后第20次攻击触发完整新一轮10发")
end

function Start()
    print("[塞拉回归] 开始；小数余量、动态门槛、攻击口径及正式运行时")
    local oldCut = ETS.getGatlingCut
    local ok, err = pcall(function()
        testThresholds()
        testReference()
        testAttackHooks()
        testRuntime()
        testAwakenedRuntime(oldCut)
        testPendingReset()
    end)
    ETS.getGatlingCut = oldCut
    if not ok then
        failures = failures + 1
        print("[塞拉回归][FAIL] 执行异常：" .. tostring(err))
    end
    print(string.format("[sera_machinegun_progress_test] assertions=%d failures=%d %s",
        assertions, failures, failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
