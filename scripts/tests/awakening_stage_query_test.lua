-- 三阶查询回归：新I/II/III与旧七节点查询分离，仅验证解锁门槛、不调整倍率。
-- 本入口的哈基米阶段用例只验证helper；正式治疗链见healing_awaken_pipeline_test.lua。
local AC = require("config.AwakeningConfig")
local AD = require("systems.AttributeDef")
local UA = require("systems.UnitAttributes")
local HC = require("config.HeroConfig")
local TAL = require("systems.TalentManager")
local SEM = require("systems.StatusEffectManager")
local Fish = require("systems.talents.TalentFatFish")
local Four = require("systems.talents.TalentFourNew")
local CF = require("systems.CombatFormula")
local Attrs = require("ui.character.detail.CharacterDetailAttrs")
local Reset = require("ui.battle.scene.BattleAllyReset")

local assertions, failures = 0, 0
local function check(condition, message)
    assertions = assertions + 1
    if condition then
        print("[三阶回归][PASS] " .. message)
    else
        failures = failures + 1
        print("[三阶回归][FAIL] " .. message)
    end
end

local function near(a, b)
    return type(a) == "number" and math.abs(a - b) < 1e-8
end

local function awake(stage)
    local nodes = { _awk3Migrated = true }
    for i = 1, stage do nodes[i] = true end
    return nodes
end

local function unit(id, stage)
    local attrs = UA.create({ [AD.MAX_HP] = 1000, [AD.MAG_ATK] = 100 })
    attrs:fillHp()
    attrs:recalc()
    local u = attrs:toBattleUnit("三阶夹具", 1)
    u.heroId = id
    u.awakeningNodes = awake(stage)
    return u
end

local function stageQuery(u, index)
    return AC.hasStage(u.awakeningNodes, index)
end

local function testQueries()
    for mask = 0, 7 do
        local nodes = { _awk3Migrated = true }
        for i = 1, 3 do nodes[i] = (mask & (1 << (i - 1))) ~= 0 end
        for i = 1, 3 do
            check(AC.hasStage(nodes, i) == nodes[i], "原生三阶独立查询 mask=" .. mask .. " stage=" .. i)
        end
        for i = 1, 7 do
            local mapped = i <= 3 and 1 or (i <= 6 and 2 or 3)
            check(AC.hasNode(nodes, i) == nodes[mapped], "旧七节点兼容保持不变 mask=" .. mask .. " node=" .. i)
        end
    end
    for mask = 0, 127 do
        local legacy = {}
        for i = 1, 7 do legacy[tostring(i)] = (mask & (1 << (i - 1))) ~= 0 end
        local expected = { (mask & 7) ~= 0, (mask & 56) ~= 0, (mask & 64) ~= 0 }
        for i = 1, 3 do
            check(AC.hasStage(legacy, i) == expected[i], "旧七节点迁移后新阶段查询 mask=" .. mask .. " stage=" .. i)
        end
    end
    check(not AC.hasStage(nil, 1) and not AC.hasStage({}, 2), "空觉醒不激活任何阶段")
    for _, index in ipairs({ -1, 0, 1.5, 4, 7 }) do
        check(not AC.hasStage(awake(3), index), "新阶段拒绝非法编号：" .. index)
    end
    check(not AC.hasStage(awake(3), nil), "新阶段拒绝nil编号")
    local marked = { ["1"] = true, ["2"] = true, ["3"] = true }
    check(AC.hasStage(marked, 2, true) and AC.hasStage(marked, 3, true), "英雄级标记保留原生字符串键II/III")
    check(not AC.hasStage(marked, 2) and not AC.hasStage(marked, 3), "无标记三键仍按旧七节点迁移")
    local native = { ["1"] = true, ["3"] = true, _awk3Migrated = true }
    check(AC.hasStage(native, 1) and not AC.hasStage(native, 2) and AC.hasStage(native, 3), "非连续原生阶段不擅自补齐前阶")
    check(native["1"] == true and native["3"] == true and native["2"] == nil, "查询不修改输入表")
end

local function testFish()
    local helper = Fish.bind({
        hasAwakenStage = stageQuery,
        talentLog = function() end,
        getAliveEnemies = function(list)
            local out = {}
            for _, u in ipairs(list) do if u.hp > 0 then out[#out + 1] = u end end
            return out
        end,
        calcTalentFixedDamage = function(_, _, base) return base end,
    })
    for stage = 0, 3 do
        SEM.reset()
        local a = unit(17, stage)
        local targets = { unit(0, 0), unit(0, 0), unit(0, 0) }
        local calls, damage = 0, 0
        helper.onAfterAttack(a, targets[1], { category = "magical", totalDamage = 10 }, true, targets,
            function(_, value) calls = calls + 1; damage = value end)
        local effect = assert(SEM.get(targets[1], SEM.VULNERABLE))
        check(near(effect.data.mult, stage >= 1 and 0.30 or 0.20), "大肥鱼I控制潮湿增伤 stage=" .. stage)
        check(near(effect.remaining, stage >= 1 and 3 or 2), "大肥鱼I控制潮湿时长 stage=" .. stage)
        check((effect.data.atkSpeedDebuff == 10) == (stage >= 2), "大肥鱼减速只在II及以上 stage=" .. stage)
        check((effect.data.critVuln == 10) == (stage >= 3), "大肥鱼暴击易伤字段只在III stage=" .. stage)
        check(calls == 1 and damage == (stage >= 2 and 55 or 40), "大肥鱼溅射系数只在II提升 stage=" .. stage)
        for _, target in ipairs(targets) do
            SEM.apply(target, SEM.VULNERABLE, 10, a, { fromFatFish = true })
        end
        calls = 0
        helper.onAfterAttack(a, targets[1], { category = "magical", totalDamage = 10 }, true, targets,
            function() calls = calls + 1 end)
        check(calls == (stage == 3 and 3 or 1), "三潮湿群体溅射只在III stage=" .. stage)
    end
end

local function fourFixture(id, stage)
    local a, s = unit(id, stage), { heroId = id }
    local helper = Four.bind({
        hasAwakenStage = stageQuery,
        getState = function() return s end,
        talentLog = function() end,
        calcTalentFixedDamage = function(_, _, base) return base end,
    })
    helper.onBattleStart(a, s)
    return a, s, helper
end

local function testFour()
    for stage = 0, 3 do
        local a, s, helper = fourFixture(18, stage)
        check(near(s.laoliuStealthLeft, stage >= 2 and 6 or 4), "老六隐踪只在II延长 stage=" .. stage)
        local target = unit(0, 0)
        helper.onBeforeAttack(a, s)
        helper.onAfterAttack(a, target, { category = "physical", totalDamage = 10 }, true, { target }, function() end)
        check(near(target._laoliuStolenArmor, stage == 3 and 0.10 or 0.05),
            "老六偷克制字段只在III提升（不验证未接入的实际属性消费）stage=" .. stage)

        a, s, helper = fourFixture(19, stage)
        target = unit(0, 0)
        local need = stage >= 2 and 4 or 5
        for _ = 1, need - 1 do helper.onAfterAttack(a, target, { category = "healing", isCrit = false }) end
        check(target._hakimiWard == nil and s.hakimiMerit == need - 1, "哈基米helper未达本阶段门槛不清心 stage=" .. stage)
        helper.onAfterAttack(a, target, { category = "healing", isCrit = false })
        check(target._hakimiWard and near(target._hakimiWard.t, stage == 3 and 4.5 or 3)
            and near(target._hakimiWard.red, stage == 3 and 0.25 or 0.18), "哈基米helper III控制时长减伤 stage=" .. stage)
        helper.onAfterAttack(a, target, { category = "healing", isCrit = true })
        check(s.hakimiMerit == (stage >= 1 and 2 or 1), "哈基米helper I保留治疗暴击功德 stage=" .. stage)

        a, s, helper = fourFixture(24, stage)
        helper.onDamageTaken(a, nil, 1000, true)
        check(s.loadingBar == (stage >= 2 and 140 or 100), "加载中II控制缓冲容量 stage=" .. stage)
        helper.onBattleStart(a, s)
        helper.onDamageTaken(a, nil, 100, true)
        check(s.loadingBar == (stage >= 1 and 35 or 25), "加载中I保留入条比例 stage=" .. stage)
        local releases = 0
        helper.update(4, { a }, { unit(0, 0) }, { dealDamage = function() releases = releases + 1 end })
        check(releases == (stage == 3 and 1 or 0), "加载中仅III在4秒闲置释放 stage=" .. stage)
        helper.update(2, { a }, { unit(0, 0) }, { dealDamage = function() releases = releases + 1 end })
        check(releases == 1, "加载中未达III仍在6秒释放 stage=" .. stage)

        a, s, helper = fourFixture(25, stage)
        target = unit(0, 0)
        target.hp, target.maxHp = 250, 1000
        helper.onBeforeAttack(a, s)
        check(near(a._highPingPending.delay, stage >= 2 and 1.2 or 1.5), "高ping攻击前延迟字段只在II缩短 stage=" .. stage)
        helper.onAfterAttack(a, target, { category = "physical", totalDamage = 100 }, true, { target }, function() end)
        check(near(s.pingQueue[1].t, stage >= 2 and 1.2 or 1.5), "高ping实际队列只在II缩短延迟 stage=" .. stage)
        local dealt = 0
        helper.update(1.2, { a }, { target }, { dealDamage = function(_, value) dealt = value end })
        check(dealt == (stage >= 2 and (stage == 3 and 69 or 55) or 0), "高ping低血25%追加只在III stage=" .. stage)
        helper.update(0.31, { a }, { target }, { dealDamage = function(_, value) dealt = value end })
        check(dealt == (stage == 3 and 69 or (stage >= 1 and 55 or 45)), "高ping保持已有伤害系数不调平衡 stage=" .. stage)
        target.hp = 500
        helper.onAfterAttack(a, target, { category = "physical", totalDamage = 100 }, true, { target }, function() end)
        target.hp = 250
        dealt = 0
        helper.update(1.51, { a }, { target }, { dealDamage = function(_, value) dealt = value end })
        check(dealt == (stage == 3 and 104 or (stage >= 1 and 83 or 61)),
            "高ping生命比例下降分支保持本批前系数及I阶段归属 stage=" .. stage)
    end
end

local function testRealBindings()
    for stage = 0, 3 do
        TAL.reset()
        SEM.reset()
        local a = assert(HC.createHero(18, 1, nil, awake(stage), false))
        local enemy = assert(HC.createHero(2, 1, nil, nil, false))
        TAL.onBattleStart({ a }, { enemy })
        check(near(a._laoliuStealthLeft, stage >= 2 and 6 or 4), "正式TAL老六绑定使用新阶段 stage=" .. stage)

        TAL.reset()
        SEM.reset()
        a = assert(HC.createHero(17, 1, nil, awake(stage), false))
        local other = assert(HC.createHero(1, 1, nil, nil, false))
        TAL.onBattleStart({ a }, { enemy, other })
        TAL.onAfterAttack(a, enemy, { category = "magical", totalDamage = 10, isMiss = false }, true,
            { enemy, other }, function() end, { a })
        local effect = assert(SEM.get(enemy, SEM.VULNERABLE))
        check((effect.data.atkSpeedDebuff == 10) == (stage >= 2)
            and (effect.data.critVuln == 10) == (stage >= 3), "正式TAL大肥鱼绑定使用新阶段 stage=" .. stage)

        TAL.reset()
        SEM.reset()
        a = assert(HC.createHero(24, 1, nil, awake(stage), false))
        TAL.onBattleStart({ a }, { enemy })
        TAL.onDamageTaken(a, enemy, 100, true, nil, { enemy }, nil)
        local releases = 0
        local loadingCtx = { dealDamage = function(_, _, _, prefix)
            if prefix == "缓冲 " then releases = releases + 1 end
        end }
        TAL.update(4, { a }, { enemy }, loadingCtx)
        check(releases == (stage == 3 and 1 or 0), "正式TAL加载中只有III在4秒吐条 stage=" .. stage)
        TAL.update(2, { a }, { enemy }, loadingCtx)
        check(releases == 1, "正式TAL加载中各阶段到6秒均已吐条 stage=" .. stage)

        TAL.reset()
        SEM.reset()
        a = assert(HC.createHero(25, 1, nil, awake(stage), false))
        enemy = unit(0, 0)
        enemy.hp, enemy.maxHp = 250, 1000
        TAL.onBattleStart({ a }, { enemy })
        TAL.onBeforeAttack(a)
        TAL.onAfterAttack(a, enemy, { category = "physical", totalDamage = 100, isMiss = false }, true,
            { enemy }, function() end, { a })
        local delayed = 0
        local pingCtx = { dealDamage = function(_, value, _, prefix)
            if prefix == "高ping " then delayed = value end
        end }
        TAL.update(1.2, { a }, { enemy }, pingCtx)
        check(delayed == (stage >= 2 and (stage == 3 and 69 or 55) or 0),
            "正式TAL高ping II延迟及III低血分支 stage=" .. stage)
        TAL.update(0.31, { a }, { enemy }, pingCtx)
        check(delayed == (stage == 3 and 69 or (stage >= 1 and 55 or 45)),
            "正式TAL高ping延迟队列完整结算 stage=" .. stage)
    end
end

local function testCritOverflow()
    -- 两参数旧调用默认关闭；只有显式传入已解锁的属性才能转换。
    for _, rate in ipairs({ 0, 25, 100, 150, 1000 }) do
        local effective, damage = CF.applyCritOverflow(rate, 200)
        check(near(effective, math.min(100, rate)) and near(damage, 200),
            "默认暴击溢出不增加暴伤 rate=" .. rate)
    end
    local target = UA.create({ [AD.MAX_HP] = 100000, [AD.DODGE] = 0 })
    target:fillHp()
    for _, id in ipairs(HC.getAllIds()) do
        for stage = 0, 3 do
            local nodes = awake(stage)
            local a = assert(HC.createHero(id, 70, nil, nodes, {}))
            local enabled = id == 18 and stage == 3
            check(a.attrs.critOverflowRatio == (enabled and 1 or 0),
                "专属转换仅老六Ⅲ开启 id=" .. id .. " stage=" .. stage)
            local effective, damage = CF.applyCritOverflow(150, 200, a.attrs)
            check(near(effective, 100) and near(damage, enabled and 300 or 200),
                "角色阶段门控实际转换 id=" .. id .. " stage=" .. stage)
        end
    end
    for _, entry in ipairs({
        { nodes = { [1] = true, [2] = true, [3] = true }, enabled = false },
        { nodes = { [7] = true }, enabled = true },
        { nodes = { ["1"] = true, ["2"] = true, ["3"] = true, _awk3Migrated = true }, enabled = true },
    }) do
        local a = assert(HC.createHero(18, 70, nil, entry.nodes, false))
        check(a.attrs.critOverflowRatio == (entry.enabled and 1 or 0), "转换兼容旧七阶与原生字符串三阶")
    end

    -- 正式普攻/连击读取属性：神器先调整暴击参数，再消费觉醒能力。
    for _, id in ipairs({ 1, 18 }) do
        for stage = 0, 3 do
            local a = assert(HC.createHero(id, 70, nil, awake(stage), {}))
            a.attrs:setBases({ [AD.CRIT_RATE] = 300, [AD.LUK] = 0,
                [AD.CRIT_DMG] = 200, [AD.PHYS_CRIT_RATE] = 0, [AD.MAG_CRIT_RATE] = 0,
                [AD.PHYS_CRIT_DMG] = 0, [AD.MAG_CRIT_DMG] = 0, [AD.HIT_VALUE] = 100000 })
            a.attrs.artifactCritRateMult, a.attrs.artifactCritDmgMult = 0.5, 2
            for _, comboIndex in ipairs({ 0, 1 }) do
                local result = CF.calcAttack(a.attrs, target, nil, comboIndex)
                check(result.isCrit and near(result.hits[1].critMult, id == 18 and stage == 3 and 6 or 4),
                    "实战先计神器倍率后按觉醒转换 id=" .. id .. " stage=" .. stage .. " combo=" .. comboIndex)
            end
            check(a.attrs:clone():clone().critOverflowRatio == a.attrs.critOverflowRatio,
                "连续克隆保留专属觉醒能力")
        end
    end

    -- 战中解锁只在新波提交 pending 快照，不能提前借即时觉醒数据生效。
    local locked = assert(HC.createHero(18, 70, nil, awake(2), {}))
    local unlocked = assert(HC.createHero(18, 70, nil, awake(3), {}))
    Reset.createSnapshot(locked)
    locked._pendingSnapshot = unlocked.attrs
    check(locked.attrs.critOverflowRatio == 0, "pending觉醒不提前影响当前波")
    check(Reset.restoreFromSnapshot(locked) and locked.attrs.critOverflowRatio == 1,
        "下波恢复新快照后转换生效")
    locked._pendingSnapshot = assert(HC.createHero(18, 70, nil, awake(2), {})).attrs
    check(Reset.restoreFromSnapshot(locked) and locked.attrs.critOverflowRatio == 0,
        "新快照撤销能力不残留转换")

    local function panelRow(data, key)
        for _, r in ipairs(data.right) do if r.key == key then return r end end
        error("缺少属性行：" .. key)
    end
    for stage = 0, 3 do
        local nodes = awake(stage)
        local options = { heroes = { roster = { ["18"] = { level = 70,
            awakening = nodes, extraTalent = { stacks = 10000 } } } },
            equipment = { inventory = {}, equipped = {} }, artifacts = { bag = {} } }
        local data = Attrs.collectAttributes(18, assert(HC.get(18)), 70, options)
        local rawRate = data.attrs:get(AD.CRIT_RATE) + data.attrs:get(AD.MAG_CRIT_RATE)
        local rawDmg = data.attrs:get(AD.CRIT_DMG) + data.attrs:get(AD.MAG_CRIT_DMG)
        local _, converted = CF.applyCritOverflow(rawRate, rawDmg, data.attrs)
        check(near(panelRow(data, "_effCritRate").numericValue, rawRate), "面板保留原始暴击率 stage=" .. stage)
        check(near(panelRow(data, "_effCritDmg").numericValue, converted), "面板暴伤与实战转换一致 stage=" .. stage)
        if stage == 1 or stage == 2 then
            check(rawRate > 1000 and near(converted, rawDmg), "历史万层成长保留，但未到Ⅲ不转暴伤")
        elseif stage == 3 then
            check(converted > 2000, "老六Ⅲ解锁后历史成长正常转暴伤")
        end
    end
end

function Start()
    print("[三阶回归] 开始；旧接口兼容、新阶段查询及五角色门槛")
    local ok, err = pcall(function()
        testQueries()
        testFish()
        testFour()
        testRealBindings()
        testCritOverflow()
    end)
    if not ok then
        failures = failures + 1
        print("[三阶回归][FAIL] 执行异常：" .. tostring(err))
    end
    print(string.format("[awakening_stage_query_test] assertions=%d failures=%d %s",
        assertions, failures, failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
