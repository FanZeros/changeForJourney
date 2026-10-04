-- C批失败回归准备：只观察正式状态产生与普攻／连击消费，不修改生产伤害逻辑。
-- CONFIRMED表示待修契约偏差，HEALTHY表示该项正常；不是普通ALL PASS回归。
local AD = require("systems.AttributeDef")
local HC = require("config.HeroConfig")
local CF = require("systems.CombatFormula")
local SEM = require("systems.StatusEffectManager")
local BC = require("ui.battle.combat.BattleCombat")
local PS = require("ui.battle.combat.ProjectileSystem")
local Driver = require("ui.battle.tri.BattleTriDriver")

local healthy, confirmed, harnessErrors = 0, 0, 0

local function observe(condition, name, details)
    if condition then healthy = healthy + 1 else confirmed = confirmed + 1 end
    print("[状态契约][" .. (condition and "HEALTHY" or "CONFIRMED") .. "] " .. name .. " " .. details)
end

local function awake()
    return { [1] = true, [2] = true, [3] = true, _awk3Migrated = true }
end

local function settle()
    for _ = 1, 90 do PS.update(1 / 60) end
end

local function runCase(producerId, effectType)
    local producer = assert(HC.createHero(producerId, 1, nil, awake(), false))
    local consumer = assert(HC.createHero(1, 1, nil, nil, false))
    local driver = Driver.new(934, { battleLab = true, timeLimit = 60,
        allyFactory = function() return { producer, consumer } end })
    driver:start(101)
    producer.atkTargets, consumer.atkTargets = 1, 1
    producer.attrs:setBase(AD.HIT_VALUE, 100000)
    consumer.attrs:setBases({ [AD.HIT_VALUE] = 100000, [AD.CRIT_RATE] = 0,
        [AD.PHYS_CRIT_RATE] = 0, [AD.COMBO_RATE] = 100 })
    local target = driver.enemies[1]
    target.attrs:setBase(AD.MAX_HP, 1000000)
    target.attrs:fillHp()
    BC.syncUnitHp(target)
    target.attrs.energyShield, target.attrs.tempEnergyShield = 0, 0
    driver.mount()
    driver.bindContext()
    BC.performAttack(producer, { target }, true)
    settle()
    local effect = SEM.get(target, effectType)
    assert(effect and effect.data and effect.data.critVuln == 10, "正式技能必须确实写入10受暴率字段")
    observe(SEM.get(target.attrs, effectType) ~= effect, "状态身份与属性对象不同",
        "hero=" .. producerId .. " 正式状态按unit保存，attrs不是同一key")
    local baseCrit = consumer.attrs:get(AD.CRIT_RATE) + consumer.attrs:get(AD.PHYS_CRIT_RATE)
    local expectedCrit = baseCrit + 10
    local rates = {}
    local oldRoll = CF.rollCrit
    CF.rollCrit = function(rate, damage)
        rates[#rates + 1] = rate
        return oldRoll(rate, damage)
    end
    local ok, err = pcall(function()
        BC.performAttack(consumer, { target }, true)
        settle()
        for _ = 1, 90 do
            BC.updateComboQueue(1 / 60)
            PS.update(1 / 60)
        end
    end)
    CF.rollCrit = oldRoll
    assert(ok, err)
    assert(#rates >= 2, "必须实际执行普通主击与至少一次连击公式")
    observe(math.abs(rates[1] - expectedCrit) < 1e-7, "正式普攻消费受暴率",
        "hero=" .. producerId .. " expected=" .. expectedCrit .. " actual=" .. tostring(rates[1]))
    observe(math.abs(rates[2] - expectedCrit) < 1e-7, "正式连击消费受暴率",
        "hero=" .. producerId .. " expected=" .. expectedCrit .. " actual=" .. tostring(rates[2]))
    SEM.remove(target, effectType)
    rates = {}
    CF.rollCrit = function(rate, damage)
        rates[#rates + 1] = rate
        return oldRoll(rate, damage)
    end
    local controlOk, controlErr = pcall(function()
        consumer.attrs:setBase(AD.COMBO_RATE, 0)
        BC.performAttack(consumer, { target }, true)
        settle()
    end)
    CF.rollCrit = oldRoll
    assert(controlOk, controlErr)
    observe(rates[1] and math.abs(rates[1] - baseCrit) < 1e-7, "无状态对照维持基础暴击率",
        "hero=" .. producerId .. " expected=" .. baseCrit .. " actual=" .. tostring(rates[1]))
end

function Start()
    print("[状态契约] 开始；仅准备C批失败回归，不调整叠加或倍率")
    for _, case in ipairs({ { id = 6, effect = SEM.SHOCKED }, { id = 17, effect = SEM.VULNERABLE } }) do
        local ok, err = pcall(runCase, case.id, case.effect)
        if not ok then
            harnessErrors = harnessErrors + 1
            print("[状态契约][HARNESS_ERROR] hero=" .. case.id .. " " .. tostring(err))
        end
    end
    print(string.format("[damage_status_contract_probe][SUMMARY] confirmed=%d healthy=%d harnessErrors=%d",
        confirmed, healthy, harnessErrors))
    print("[状态契约] 完成；CONFIRMED不是已修复，退出0不代表契约回归通过")
    engine:Exit()
end
