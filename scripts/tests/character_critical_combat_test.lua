-- 小雀开战与飞剑伤害生命周期回归，使用正式英雄、三行驱动与投射物回调。
local AD = require("systems.AttributeDef")
local HC = require("config.HeroConfig")
local TAL = require("systems.TalentManager")
local SEM = require("systems.StatusEffectManager")
local BC = require("ui.battle.combat.BattleCombat")
local PS = require("ui.battle.combat.ProjectileSystem")
local Driver = require("ui.battle.tri.BattleTriDriver")

local assertions = 0
local failures = 0
local function check(condition, message)
    assertions = assertions + 1
    if condition then
        print("[关键角色回归][PASS] " .. message)
    else
        failures = failures + 1
        print("[关键角色回归][FAIL] " .. message)
    end
end

local function hero(id, awakening)
    return assert(HC.createHero(id, 1, nil, awakening, false))
end

local function awake(first, second, third)
    return { [1] = first, [2] = second, [3] = third, _awk3Migrated = true }
end

local function setup(attacker, enemies, projectiles)
    BC.reset()
    PS.reset()
    SEM.reset()
    BC.setContext({
        getAllies = function() return { attacker } end,
        getEnemies = function() return enemies end,
        onTalentDealDamage = projectiles and function(a, target, x, y, prefix, applyDamage, opts)
            BC.onTalentDealDamage(a, target, x, y, prefix, applyDamage, opts, { attacker }, enemies)
        end or nil,
    })
end

local function testAyane()
    for _, nodes in ipairs({ awake(false), awake(true, true) }) do
        local ayane = hero(8, nodes)
        local driver = Driver.new(930, {
            battleLab = true,
            timeLimit = 10,
            allyFactory = function() return { ayane } end,
        })
        local ok, err = pcall(driver.start, driver, 101)
        check(ok, "正式三行小雀开战无异常：" .. tostring(err))
        local marked = 0
        for _, enemy in ipairs(driver.enemies) do
            if SEM.has(enemy, SEM.MARKED) then
                marked = marked + 1
                if nodes[2] then
                    check(enemy.attrs.modifiers.awaken_mark_debuff ~= nil, "共鸣标记正确注入护甲/闪避减益")
                end
            end
        end
        check(marked == 1, "开战只标记一个活敌")
    end
end

local function testSwordImmediate()
    local attacker, target, other = hero(16), hero(1), hero(2)
    setup(attacker, { target, other })
    target.attrs.energyShield = 10000
    local before = target.hp
    local otherHp = other.hp
    local actual = BC.dealTalentDamage(attacker, target, 50, false, "灵月飞剑")
    check(actual == 0 and target.hp == before, "全盾飞剑扣血0但命中有效")
    check(target.attrs.energyShield == 9950 and other.hp == otherHp, "全盾仅扣原目标一次，不转火")

    -- 临时盾全吸收同样不是未命中；本轮不改变伤害来源或倍率。
    target.attrs.energyShield = 0
    target.attrs.tempEnergyShield = 100
    BC.dealTalentDamage(attacker, target, 20, false, "飞回")
    check(target.attrs.tempEnergyShield == 80 and other.hp == otherHp, "飞回全额临时盾吸收不转火")

    target.attrs.tempEnergyShield = 0
    local hp = target.hp
    BC.dealTalentDamage(attacker, target, 10, false, "灵月飞剑")
    check(target.hp == hp - 10 and other.hp == otherHp, "无盾正常飞剑保持原目标与伤害")

    target.attrs.final[AD.HP], target.hp = 0, 0
    other.attrs.energyShield = 100
    local otherBefore = other.hp
    BC.dealTalentDamage(attacker, target, 25, false, "灵月飞剑")
    check(other.attrs.energyShield == 75 and other.hp == otherBefore, "原目标死亡后解包活单位，转火全盾只结算一次")
    other.attrs.energyShield = 0
    BC.dealTalentDamage(attacker, target, 10, false, "飞回")
    check(other.hp == otherBefore - 10, "飞回原目标已死可向活单位转火")
    BC.dealTalentDamage(attacker, target, 10, false, "普通天赋")
    check(other.hp == otherBefore - 10, "非飞剑天赋不新增转火行为")
    other.attrs.final[AD.HP], other.hp = 0, 0
    check(BC.dealTalentDamage(attacker, target, 10, false, "灵月飞剑") == 0, "全敌阵亡不结算伤害")
end

local function testSwordProjectile()
    local attacker, target, other = hero(16), hero(1), hero(2)
    setup(attacker, { target, other }, true)
    target.attrs.energyShield = 1000
    local otherBefore = other.hp
    BC.dealTalentDamage(attacker, target, 30, false, "灵月飞剑", nil,
        { target = target, flyingSwordIndex = 1, flyingSwordCount = 1 })
    check(PS.getActiveCount() == 1, "正式天赋回调产生飞剑投射物")
    for _ = 1, 90 do PS.update(1 / 60) end
    check(target.attrs.energyShield == 970 and other.hp == otherBefore, "投射物全盾落地只结算一次")
    check(PS.getActiveCount() == 0, "全盾飞剑完整退场")

    setup(attacker, { target, other }, true)
    other.attrs.energyShield = 1000
    BC.dealTalentDamage(attacker, target, 40, false, "灵月飞剑", nil,
        { target = target, flyingSwordIndex = 1, flyingSwordCount = 1 })
    target.attrs.final[AD.HP], target.hp = 0, 0
    for _ = 1, 90 do PS.update(1 / 60) end
    check(other.attrs.energyShield == 960 and other.hp == otherBefore, "飞行中原目标阵亡，到达回调安全转火")
    check(PS.getActiveCount() == 0, "死目标飞剑回调只触发一次并退场")

    target = hero(1)
    setup(attacker, { target }, true)
    target.attrs.energyShield = 1000
    local opts = {
        target = target, flyingSwordIndex = 1, flyingSwordCount = 1,
        flyingSwordOnHit = { chance = 1, baseDmg = 30, extraMult = 1, isTargetAlly = false },
    }
    BC.dealTalentDamage(attacker, target, 30, false, "灵月飞剑", nil, opts)
    for _ = 1, 180 do PS.update(1 / 60) end
    check(target.attrs.energyShield == 940, "全盾正向命中后飞回各扣盾一次，无重复转火")
    check(PS.getActiveCount() == 0, "飞回生命周期完整结束")
end

function Start()
    print("[关键角色回归] 开始")
    local ok, err = pcall(function()
        testAyane()
        testSwordImmediate()
        testSwordProjectile()
    end)
    if not ok then
        failures = failures + 1
        print("[关键角色回归][FAIL] 执行异常：" .. tostring(err))
    end
    print(string.format("[character_critical_combat_test] assertions=%d failures=%d %s",
        assertions, failures, failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
