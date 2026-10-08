-- A批正式治疗链回归：使用真实三行宿主、英雄、公式、投射物及天赋。
-- 只观察正式入口，不替换被测治疗／套装／功德实现；不写真实玩家存档。
local AD = require("systems.AttributeDef")
local HC = require("config.HeroConfig")
local TAL = require("systems.TalentManager")
local SEM = require("systems.StatusEffectManager")
local BC = require("ui.battle.combat.BattleCombat")
local PS = require("ui.battle.combat.ProjectileSystem")
local Driver = require("ui.battle.tri.BattleTriDriver")
local EC = require("config.EquipmentConfig")
local ESC = require("config.EquipmentSetConfig")
local ES = require("systems.EquipmentSystem")
local Sets = require("systems.EquipmentSetSystem")

local assertions, failures = 0, 0
local afterEvents = {}

local function check(condition, message)
    assertions = assertions + 1
    print("[治疗闭环][" .. (condition and "PASS" or "FAIL") .. "] " .. message)
    if not condition then failures = failures + 1 end
end

local function near(value, expected)
    return type(value) == "number" and math.abs(value - expected) < 1e-7
end

local function awake(stage)
    local nodes = { _awk3Migrated = true }
    for i = 1, stage do nodes[i] = true end
    return nodes
end

local function hero(id, stage)
    return assert(HC.createHero(id, 1, nil, awake(stage or 0), false))
end

local function setHp(unit, hp)
    unit.attrs.final[AD.HP] = hp
    BC.syncUnitHp(unit)
end

---@return table driver
---@return table healer
---@return table target
---@return table[] allies
local function fixture(healerId, stage, count)
    local healer = hero(healerId, stage)
    local allies = { healer } ---@type table[]
    for i = 1, count or 1 do
        local target = hero(i == 1 and 1 or 2)
        target.attrs:setBase(AD.MAX_HP, 100000)
        target.attrs:fillHp()
        BC.syncUnitHp(target)
        allies[#allies + 1] = target
    end
    local driver = Driver.new(931, {
        battleLab = true, timeLimit = 10,
        allyFactory = function() return allies end,
    })
    driver:start(101)
    healer.atkTargets = count or 1
    healer.attrs:setBase(AD.HEAL_CRIT_RATE, 0)
    healer.attrs:setBase(AD.HEAL_AMOUNT, 1000)
    healer.attrs:fillHp()
    BC.syncUnitHp(healer)
    for i = 2, #allies do setHp(allies[i], 10000 + i * 1000) end
    afterEvents = {}
    return driver, healer, assert(allies[2]), allies
end

local function attack(driver, attacker, targets, isAlly)
    driver.mount()
    driver.bindContext()
    BC.performAttack(attacker, targets, isAlly)
    for _ = 1, 90 do PS.update(1 / 60) end
end

local function heal(driver, healer)
    attack(driver, healer, driver.enemies, true)
end

local function testHakimiStages()
    for stage = 0, 3 do
        local driver, healer, target = fixture(19, stage)
        local need = stage >= 2 and 4 or 5
        for i = 1, need - 1 do
            local oldHp = target.hp
            heal(driver, healer)
            check(target.hp > oldHp, "实际治疗落地 stage=" .. stage .. " hit=" .. i)
            check(target._hakimiWard == nil, "功德未达门槛不提前清心 stage=" .. stage .. " hit=" .. i)
        end
        heal(driver, healer)
        local ward = target._hakimiWard
        check(ward ~= nil, "正式治疗达到门槛触发清心 stage=" .. stage)
        check(ward and near(ward.red, stage == 3 and 0.25 or 0.18), "清心减伤参数不变 stage=" .. stage)
        check(ward and near(ward.t, stage == 3 and 4.5 or 3), "清心时长参数不变 stage=" .. stage)
        check(#afterEvents == need, "每个正式治疗目标仅分发一次 stage=" .. stage)
        check(afterEvents[need] and afterEvents[need].target == target
            and afterEvents[need].result.category == "healing", "正式后处理携带真实治疗目标 stage=" .. stage)
        local duration = stage == 3 and 4.5 or 3
        TAL.update(duration - 0.01, driver.allies, driver.enemies, {})
        check(target._hakimiWard and near(target._hakimiWard.t, 0.01), "到期前仍保留清心 stage=" .. stage)
        TAL.update(0.02, driver.allies, driver.enemies, {})
        check(target._hakimiWard == nil, "超过时限清心移除 stage=" .. stage)
        heal(driver, healer)
        check(target._hakimiWard == nil, "触发后功德已消费，不在下一治疗重复触发 stage=" .. stage)
    end
end

local function testCritAndMultipleTargets()
    for stage = 0, 3 do
        local driver, healer, target = fixture(19, stage)
        healer.attrs:setBase(AD.HEAL_CRIT_RATE, 100)
        local need = stage >= 2 and 4 or 5
        local perHit = stage >= 1 and 2 or 1
        local hits = math.ceil(need / perHit)
        for i = 1, hits - 1 do
            heal(driver, healer)
            check(target._hakimiWard == nil, "暴击治疗门槛前无清心 stage=" .. stage .. " hit=" .. i)
        end
        heal(driver, healer)
        check(target._hakimiWard ~= nil, "Ⅰ起暴击多一层功德且不改门槛 stage=" .. stage)
        check(#afterEvents == hits and afterEvents[hits] and afterEvents[hits].result.isCrit,
            "正式公式确实产生暴击治疗 stage=" .. stage)
    end
    local driver, healer, _, allies = fixture(19, 0, 2)
    heal(driver, healer)
    check(#afterEvents == 2 and afterEvents[1].target ~= afterEvents[2].target,
        "两目标治疗按实际落地各一次后处理")
    heal(driver, healer)
    check(allies[2]._hakimiWard == nil and allies[3]._hakimiWard == nil,
        "两次双目标共四层，未提前达到五层")
    heal(driver, healer)
    local wards = (allies[2]._hakimiWard and 1 or 0) + (allies[3]._hakimiWard and 1 or 0)
    check(wards == 1 and #afterEvents == 6, "第三次双目标仅达门槛的目标获得清心，无重复分发")
end

local function testWardDamage()
    local driver, healer, target = fixture(19, 3)
    for _ = 1, 4 do heal(driver, healer) end
    local ward = target._hakimiWard
    check(ward and near(ward.red, 0.25), "正式治疗产生25%清心后准备实际受击")
    local attacker = driver.enemies[1]
    attacker.atkTargets = 1
    attacker.attrs:setBases({ [AD.HIT_VALUE] = 100000, [AD.PHYS_ATK] = 1000,
        [AD.CRIT_RATE] = 0, [AD.PHYS_CRIT_RATE] = 0, [AD.COMBO_RATE] = 0 })
    target.attrs:setBases({ [AD.PHYS_BLOCK_RATE] = 0, [AD.MAG_BLOCK_RATE] = 0 })
    target.attrs.energyShield, target.attrs.tempEnergyShield = 0, 0
    target._hakimiWard = nil
    setHp(target, 50000)
    math.randomseed(1004)
    attack(driver, attacker, { target }, false)
    local baselineDamage = 50000 - target.hp
    target._hakimiWard = ward
    setHp(target, 50000)
    math.randomseed(1004)
    attack(driver, attacker, { target }, false)
    local wardDamage = 50000 - target.hp
    check(baselineDamage > 0 and wardDamage == math.floor(baselineDamage * 0.75 + 0.5),
        "真实敌方普攻只应用一次25%清心减伤")
    setHp(target, 50000)
    math.randomseed(1004)
    attack(driver, attacker, { target }, false)
    check(50000 - target.hp == wardDamage and target._hakimiWard == ward,
        "清心连续受击仍减伤，不被一次命中消费")
    TAL.update(4.51, driver.allies, driver.enemies, {})
    setHp(target, 50000)
    math.randomseed(1004)
    attack(driver, attacker, { target }, false)
    check(target._hakimiWard == nil and 50000 - target.hp == baselineDamage,
        "清心实际到期后恢复同种子普通伤害")
end

local function testHealingSets()
    for _, setId in ipairs({ "emberscout", "gambler", "riftcrystal", "carapace", "faceless", "nitros", "tidepress", "bonehunger", "swordgate" }) do
        local driver, healer, target = fixture(19, 0)
        healer.attrs._setFour, healer.attrs._setSix = setId, setId
        healer._setShell = 8
        healer._setFacelessT = 4
        healer._setSwordDmgWin = 321
        local crystalBefore = target._crystal
        local extraDamage = 0
        local oldDamage = BC.dealDamageToUnit
        -- 套装正式回调使用宿主闭包；通过攻击后包装观察回调，不替换被测套装实现。
        local oldAfter = TAL.onAfterAttack
        TAL.onAfterAttack = function(a, t, result, isAlly, targetList, callback, attackerAllies)
            return oldAfter(a, t, result, isAlly, targetList, function(...)
                extraDamage = extraDamage + 1
                return callback(...)
            end, attackerAllies)
        end
        heal(driver, healer)
        TAL.onAfterAttack = oldAfter
        check(target._setEmber == nil and target._setEmberSrc == nil, "治疗不写余烬／来源 set=" .. setId)
        check(target._crystal == crystalBefore, "治疗不积晶蚀 set=" .. setId)
        check(extraDamage == 0, "治疗不触发攻击套装额伤 set=" .. setId)
        check(healer._setGamble == 0 and healer.attrs.modifiers.set4_gamble == nil,
            "治疗不改变赌徒攻击计数 set=" .. setId)
        check(healer._setShell == 8 and healer._setFacelessT == 4,
            "治疗不消费虫壳／无面攻击资源 set=" .. setId)
        check(healer.attrs.modifiers.set4_bonehunger == nil, "治疗不触发低血攻击加速 set=" .. setId)
        check(healer._setSwordDmgWin == 321, "治疗不写门剑伤害池 set=" .. setId)
        check(BC.dealDamageToUnit == oldDamage, "未替换正式伤害结算 set=" .. setId)
    end
end

local function testHealingAbilitiesRetained()
    local driver, healer, target = fixture(9, 0)
    heal(driver, healer)
    check(SEM.has(target, SEM.HOT), "卡皮巴拉正式治疗后温泉HOT仍生效")

    local shieldDriver, shieldHealer, shieldTarget = fixture(19, 0)
    shieldHealer.attrs._setFour = "last_rite"
    shieldHealer.attrs:setBase(AD.HEAL_AMOUNT, 1000000)
    shieldTarget.attrs.energyShield = 0
    heal(shieldDriver, shieldHealer)
    local result = afterEvents[#afterEvents] and afterEvents[#afterEvents].result
    check(result and result.overhealAmount > 0
        and (shieldTarget.attrs.energyShield or 0) + (shieldTarget.attrs.tempEnergyShield or 0) > 0,
        "正式过量治疗仍调用司仪袍转盾")
end

local function testMissOverhealAndRetarget()
    local driver, healer, target = fixture(19, 0)
    TAL.onAfterAttack(healer, target, { category = "healing", isMiss = true, isCrit = true },
        true, driver.enemies, function() end, driver.allies)
    afterEvents = {}
    for _ = 1, 4 do heal(driver, healer) end
    check(target._hakimiWard == nil, "miss治疗不积功德、不提前到门槛")
    heal(driver, healer)
    check(target._hakimiWard ~= nil, "miss后仍需五次真实治疗")

    local fullDriver, fullHealer, _, fullAllies = fixture(19, 0)
    for _, ally in ipairs(fullAllies) do setHp(ally, ally.maxHp) end
    for _ = 1, 5 do heal(fullDriver, fullHealer) end
    local wards = (fullAllies[1]._hakimiWard and 1 or 0) + (fullAllies[2]._hakimiWard and 1 or 0)
    local event = afterEvents[#afterEvents]
    check(wards == 1 and event and event.result.appliedHealAmount == 0
        and event.result.overhealAmount > 0, "满血过量治疗保留现有功德口径，不新增有效治疗门槛")

    local retryDriver, retryHealer, original, retryAllies = fixture(19, 0, 2)
    retryHealer.atkTargets = 1
    retryDriver.mount()
    retryDriver.bindContext()
    BC.performAttack(retryHealer, retryDriver.enemies, true)
    check(PS.getActiveCount() == 1 and #afterEvents == 0, "治疗投射物未落地不分发功德")
    setHp(original, 0)
    for _ = 1, 90 do PS.update(1 / 60) end
    check(#afterEvents == 1 and afterEvents[1].target == retryAllies[3]
        and original._hakimiWard == nil, "飞行中原目标死亡，按落地实际重选目标只分发一次")
end

local function testNormalAttackSets()
    for _, setId in ipairs({ "emberscout", "gambler", "swordgate" }) do
        local driver, attacker = fixture(18, 0)
        local target = driver.enemies[1]
        attacker.attrs._setFour = setId
        attacker.attrs._setSix = nil
        attacker.attrs:setBase(AD.HIT_VALUE, 100000)
        target.attrs:setBase(AD.MAX_HP, 1000000)
        target.attrs:fillHp()
        BC.syncUnitHp(target)
        if setId == "gambler" then
            attacker.attrs:setBase(AD.CRIT_RATE, 0)
            -- 消费老六基础首次必暴，再验证普通未暴攻击计数。
            attack(driver, attacker, { target }, true)
            attacker.attrs:setBases({ [AD.CRIT_RATE] = 0, [AD.MAG_CRIT_RATE] = 0,
                [AD.PHYS_CRIT_RATE] = 0 })
        end
        attack(driver, attacker, { target }, true)
        if setId == "emberscout" then
            check(target._setEmber == 2 and target._setEmberSrc == attacker,
                "普通伤害仍可挂余烬，未整体禁用套装")
        elseif setId == "gambler" then
            check(attacker._setGamble == 1 and attacker.attrs.modifiers.set4_gamble ~= nil,
                "普通未暴伤害仍可叠赌徒攻击层")
        else
            check((attacker._setSwordDmgWin or 0) > 0, "普通伤害仍累积门剑池")
        end
    end
end

local function testLegalHealerLoadout()
    for _, setId in ipairs({ "emberscout", "last_rite" }) do
        local driver, healer, target = fixture(19, 0)
        local equipment = { inventory = {}, equipped = {} }
        local owned = { roster = { [19] = { level = 345 } } }
        local templateIds = {}
        for id in pairs(EC.ITEMS) do templateIds[#templateIds + 1] = id end
        table.sort(templateIds)
        local worn = 0
        for _, slot in ipairs(EC.SLOTS) do
            local wearable = ES.getWearableTypeSet(19, slot)
            for _, templateId in ipairs(templateIds) do
                local template = EC.ITEMS[templateId]
                if template.slot == slot and ESC.getSetIdForTemplate(template) == setId
                    and (not wearable or wearable[template.type]) then
                    local seq = worn + 1
                    local equip = assert(ES.hydrate({ templateId = templateId, quality = 1,
                        level = 345, affixes = {} }))
                    equipment.inventory[tostring(seq)] = equip
                    local ok, err = ES.applyEquip(equipment, seq, 19, slot, owned)
                    check(ok, "正式职业／等级穿戴通过 set=" .. setId .. " slot=" .. slot .. " " .. tostring(err))
                    if ok then
                        ES.applyToUnit(healer.attrs, equip, seq)
                        worn = worn + 1
                    end
                    break
                end
            end
            if worn >= 4 then break end
        end
        local rows = Sets.applyToUnit(healer.attrs, equipment, 19, ES.getFromInventory, ES.getHeroSlots)
        check(worn == 4 and rows[1] and rows[1].count == 4 and healer.attrs._setFour == setId,
            "真实四件计数／属性注入生成高阶标记 set=" .. setId)
        healer.attrs:fillHp()
        BC.syncUnitHp(healer)
        for _ = 1, 5 do heal(driver, healer) end
        local wards = (target._hakimiWard and 1 or 0) + (healer._hakimiWard and 1 or 0)
        check(wards == 1, "合法四件穿装后正式治疗仍触发清心 set=" .. setId)
        check(target._setEmber == nil and target._setEmberSrc == nil,
            "合法穿装治疗不污染队友余烬 set=" .. setId)
    end
end

local function testDamageHeroesOnce()
    for _, id in ipairs({ 18, 24, 25 }) do
        local driver, attacker = fixture(id, 3)
        attacker.atkTargets = 1
        local target = driver.enemies[1]
        target.attrs:setBase(AD.MAX_HP, 1000000)
        target.attrs:fillHp()
        BC.syncUnitHp(target)
        attacker.attrs:setBase(AD.HIT_VALUE, 100000)
        afterEvents = {}
        attack(driver, attacker, { target }, true)
        check(#afterEvents == 1, "伤害英雄后处理仍仅一次 id=" .. id)
        if id == 18 then
            check(attacker.attrs.modifiers.laoliu_first_crit == nil and near(target._laoliuStolenArmor, 0.10),
                "老六首击效果未重复消费")
        elseif id == 25 then
            local hits = 0
            TAL.update(1.21, driver.allies, driver.enemies, { dealDamage = function(_, _, _, prefix)
                if prefix == "高ping " then hits = hits + 1 end
            end })
            check(hits == 1, "高ping一次主击只生成一份延迟包")
        end
    end
end

function Start()
    print("[治疗闭环] 开始；正式宿主／公式／投射物，保留阶段参数")
    local oldAfter = TAL.onAfterAttack
    TAL.onAfterAttack = function(attacker, target, result, ...)
        afterEvents[#afterEvents + 1] = { target = target, result = result }
        return oldAfter(attacker, target, result, ...)
    end
    local ok, err = pcall(function()
        testHakimiStages()
        testCritAndMultipleTargets()
        testWardDamage()
        testHealingSets()
        testHealingAbilitiesRetained()
        testMissOverhealAndRetarget()
        testNormalAttackSets()
        testLegalHealerLoadout()
        testDamageHeroesOnce()
    end)
    TAL.onAfterAttack = oldAfter
    if not ok then
        failures = failures + 1
        print("[治疗闭环][FAIL] 执行异常：" .. tostring(err))
    end
    print(string.format("[healing_awaken_pipeline_test] assertions=%d failures=%d %s",
        assertions, failures, failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
