-- 真实普攻／连击套装接线回归：使用正式公式、伤害、仇恨及队列，不写玩家存档。
local AD = require("systems.AttributeDef")
local UA = require("systems.UnitAttributes")
local BC = require("ui.battle.combat.BattleCombat")
local CF = require("systems.CombatFormula")
local ESR = require("systems.EquipmentSetRuntime")
local TM = require("systems.ThreatManager")
local ART = require("systems.ArtifactRuntime")
local ESC = require("config.EquipmentSetConfig")
local HC = require("config.HeroConfig")
local SEM = require("systems.StatusEffectManager")
local Driver = require("ui.battle.tri.BattleTriDriver")

local assertions, failures = 0, 0
local function check(ok, text)
    assertions = assertions + 1
    if not ok then failures = failures + 1 end
    print("[套装接线][" .. (ok and "PASS" or "FAIL") .. "] " .. text)
end
local function near(value, expected)
    return type(value) == "number" and math.abs(value - expected) < 1e-6
end
local function unit(id)
    local attrs = UA.create({ maxHp = 1000000, physAtk = 1000, hitValue = 100000,
        atkType = AD.ATK_SLASH, armorType = AD.ARMOR_LEATHER })
    attrs:setBases({ [AD.CRIT_RATE] = 0, [AD.PHYS_CRIT_RATE] = 0,
        [AD.MAG_CRIT_RATE] = 0, [AD.COMBO_RATE] = 0, [AD.COMBO_DMG_UP] = 0,
        [AD.ARMOR] = 0, [AD.PHYS_BLOCK_RATE] = 0, [AD.MAG_BLOCK_RATE] = 0,
        [AD.ATK_HEAL] = 0 })
    attrs:fillHp()
    attrs.energyShield, attrs.tempEnergyShield = 0, 0
    local result = attrs:toBattleUnit("测试" .. id, 1)
    result.instanceId = id
    result.atkTargets = 1
    result.dmgSpread = 0
    return result
end
local function fixture()
    local ally, enemy = unit(801), unit(802)
    local state = BC.newState("equipment-set-wiring")
    BC.mount(state)
    TM.mount(TM.newState())
    BC.setContext({ getAllies = function() return { ally } end,
        getEnemies = function() return { enemy } end })
    return ally, enemy, state
end
local function attack(attacker, target, isAlly, combo)
    if combo then
        local state = BC.mountedState()
        state.comboQueue[#state.comboQueue + 1] = { attacker = attacker,
            targetRef = target, isAlly = isAlly, targetIsAlly = not isAlly,
            comboHitIndex = 1, timer = 0, delay = 0 }
        BC.updateComboQueue(0.01)
    else
        BC.performAttack(attacker, { target }, isAlly)
    end
end
local function refill(target)
    target.attrs:fillHp()
    BC.syncUnitHp(target)
    target.attrs.energyShield, target.attrs.tempEnergyShield = 0, 0
end

local function damageWiring()
    for _, combo in ipairs({ false, true }) do
        local ally, enemy = fixture()
        math.randomseed(81008)
        attack(ally, enemy, true, combo)
        local baseline = enemy.maxHp - enemy.hp
        check(baseline > 0, "正式攻击造成伤害 combo=" .. tostring(combo))
        for _, effect in ipairs({ "carapace", "ember", "crystal" }) do
            refill(enemy)
            enemy.attrs._setFour = effect == "carapace" and effect or nil
            enemy._setShell = 0
            enemy._setEmber = effect == "ember" and 2 or nil
            enemy._crystal = effect == "crystal" and 5 or 0
            math.randomseed(81008)
            attack(ally, enemy, true, combo)
            local multiplier = effect == "carapace" and 0.97 or (effect == "ember" and 1.16 or 1.15)
            check(near(enemy.maxHp - enemy.hp, math.floor(baseline * multiplier)),
                "真实受伤套装仅应用一次 effect=" .. effect .. " combo=" .. tostring(combo))
            if effect == "carapace" then
                check(enemy._setShell == 1, "真实受击叠甲一层 combo=" .. tostring(combo))
            end
        end
    end
end

local function reflectionWiring()
    for _, combo in ipairs({ false, true }) do
        for _, isAlly in ipairs({ false, true }) do
            local ally, enemy = fixture()
            local attacker, defender = isAlly and ally or enemy, isAlly and enemy or ally
            defender.attrs._setFour, defender.attrs._setSix = "ironwall", "ironwall"
            defender.attrs:setBases({ [AD.PHYS_BLOCK_RATE] = 100, [AD.PHYS_BLOCK_RATIO] = 50,
                [AD.ARMOR] = 10000 })
            defender.attrs.energyShield = 100000
            defender.attrs.final[AD.HP] = 500000
            BC.syncUnitHp(defender)
            math.randomseed(81009)
            local formula = CF.calcAttack(attacker.attrs, defender.attrs, nil, combo and 1 or 0)
            local blocked = assert(formula.hits[1]).blockedDamage
            check(blocked > 0 and near(blocked, formula.hits[1].preBlockDamage * 0.5),
                "公式保留真实格挡量，不含护甲／护盾 combo=" .. tostring(combo))
            math.randomseed(81009)
            attack(attacker, defender, isAlly, combo)
            check(attacker.maxHp - attacker.hp == math.floor(blocked * 0.6),
                "真实铁壁反伤正确阵营，且盾不夸大基数 ally=" .. tostring(isAlly) .. " combo=" .. tostring(combo))
            check(defender.hp == 520000,
                "真实格挡回血为最大生命2%，不被反伤阵营污染 ally=" .. tostring(isAlly) .. " combo=" .. tostring(combo))
        end
    end
end

local function threatWiring()
    local ally, enemy = fixture()
    ally.heroId = 999
    ally.attrs._setFour, ally.attrs._setSix = "faceless", "faceless"
    ally._setFacelessT = 8
    for _, combo in ipairs({ false, true }) do
        attack(ally, enemy, true, combo)
        check(TM.getThreat(ally) == 0 and ally._setFacelessT == 8,
            "无面窗口正式攻击不产生仇恨且不被消费 combo=" .. tostring(combo))
    end
    BC.dealTalentDamage(ally, enemy, 100, false, "测试", nil,
        { noCounter = true, threatScale = 1, category = "magical" })
    check(TM.getThreat(ally) == 0, "无面窗口真实额伤不产生仇恨")
    ESR.update(8.01, { ally }, { enemy }, {})
    attack(ally, enemy, true, false)
    check(TM.getThreat(ally) > 0 and ally._setFacelessT == 0, "八秒到期后普通仇恨恢复")
    TM.clearThreat(ally)
    BC.dealTalentDamage(ally, enemy, 100, false, "测试", nil,
        { noCounter = true, noThreat = true, threatScale = 1 })
    check(TM.getThreat(ally) == 0, "投射物noThreat正确透传")
end

local function counterMetadata()
    local ally, enemy = fixture()
    local original = ART.onBeforeTakeDamage
    local calls = 0
    ART.onBeforeTakeDamage = function(...)
        calls = calls + 1
        return original(...)
    end
    local ok, err = pcall(function()
        BC.dealTalentDamage(ally, enemy, 100, false, "测试", nil, { noCounter = true })
        check(calls == 0, "只有noCounter也能透传，不递归触发反击")
        BC.dealTalentDamage(ally, enemy, 100, false, "测试", nil, {})
        check(calls == 1, "普通额伤保留原反击处理")
    end)
    ART.onBeforeTakeDamage = original
    if not ok then error(err, 0) end
end

-- 只观察 ART 入口；TAL.update → ESR.update → Driver 七参宿主 → BC 均保持正式实现。
local function periodicCounterMetadata()
    for _, setId in ipairs({ "swordgate", "starless" }) do
        local original = ART.onBeforeTakeDamage
        local ok, err = pcall(function()
            local wearer, friend = assert(HC.createHero(24, 1)), assert(HC.createHero(1, 1))
            wearer.attrs._setFour, wearer.attrs._setSix = setId, setId
            local drv = Driver.new(934, { battleLab = true, timeLimit = 60,
                allyFactory = function() return { wearer, friend } end })
            drv:start(101)
            drv.introTimer = 0
            for _, list in ipairs({ drv.allies, drv.enemies }) do
                for _, u in ipairs(list) do
                    u.attrs:setBases({ [AD.MAX_HP] = 1000000, [AD.ARMOR] = 0,
                        [AD.HP_REGEN] = 0 })
                    u.attrs:fillHp()
                    u.attrs.energyShield, u.attrs.tempEnergyShield = 0, 0
                    BC.syncUnitHp(u)
                    -- 用真实冻结状态隔离普攻，不替换攻击、天赋或套装实现。
                    SEM.apply(u, SEM.FROZEN, 100, nil, {})
                end
            end
            wearer.attrs:setBase(AD.MAG_ATK, 1000)
            wearer._setSwordWin = ESC.SETS.swordgate.effect4.interval
            wearer._setSwordDmgWin = 1000
            wearer._setStarCd = 0
            local before = 0
            for _, enemy in ipairs(drv.enemies) do before = before + enemy.hp end
            local observations = {}
            ART.onBeforeTakeDamage = function(target, source, damage, isTargetAlly)
                observations[#observations + 1] = { target = target, source = source,
                    isTargetAlly = isTargetAlly }
                return original(target, source, damage, isTargetAlly)
            end
            drv.mount()
            drv.bindContext()
            drv:tick(0.1)
            local after = 0
            for _, enemy in ipairs(drv.enemies) do after = after + enemy.hp end
            local dealt = before - after
            check(dealt > 0, "真实Driver tick周期伤害确实执行 set=" .. setId)
            local cycleConsumed = setId == "swordgate"
                and wearer._setSwordWin == 0 and wearer._setSwordDmgWin == 0
                or setId == "starless" and wearer._setStarCd == ESC.SETS.starless.effect6.interval
            check(cycleConsumed, "真实周期消费门剑池／重置无光计时 set=" .. setId)
            check(#observations == 0, "真实宿主透传noCounter，周期门剑／无光不进入ART反击 set=" .. setId)

            -- 同一场、同一来源的无第七参对照，排除 source 丢失或观察钩子未生效的假通过。
            local target = assert(drv.enemies[1])
            local callsBefore = #observations
            local control = BC.dealDamageToUnit(target, 100, false, "无meta对照 ",
                { 255, 255, 255 }, wearer)
            check(control > 0 and #observations == callsBefore + 1,
                "无meta对照实际受伤且进入真实ART反击处理 set=" .. setId)
            local observed = observations[#observations]
            check(observed ~= nil and observed.target == target and observed.source == wearer
                and observed.isTargetAlly == false,
                "无meta对照ART观察保留真实来源与敌方阵营 set=" .. setId)
        end)
        ART.onBeforeTakeDamage = original
        if not ok then check(false, "周期meta回归执行异常 set=" .. setId .. "：" .. tostring(err)) end
    end
end

function Start()
    print("[套装接线] 开始真实普攻／连击／格挡／无面窗口／Driver周期meta回归")
    for _, test in ipairs({ damageWiring, reflectionWiring, threatWiring, counterMetadata, periodicCounterMetadata }) do
        local ok, err = pcall(test)
        if not ok then check(false, tostring(err)) end
    end
    print(string.format("[equipment_set_combat_wiring_test] assertions=%d failures=%d %s",
        assertions, failures, failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
