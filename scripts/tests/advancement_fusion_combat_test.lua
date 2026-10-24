-- 六融合真实战斗回归：AVC→HC→TAL→CGR→BC/CF，不加载主入口或读写玩家档。
-- 测试只改独立战斗单位的基础属性；所有被测选择/伤害/死亡/队列使用正式实现。
local AD = require("systems.AttributeDef")
local AVC = require("config.AdvancementConfig")
local HC = require("config.HeroConfig")
local CGR = require("systems.ClassGateRuntime")
local TAL = require("systems.TalentManager")
local BC = require("ui.battle.combat.BattleCombat")
local CF = require("systems.CombatFormula")
local TM = require("systems.ThreatManager")
local SEM = require("systems.StatusEffectManager")
local ETS = require("systems.ExtraTalentSystem")
local ART = require("systems.ArtifactRuntime")
local PS = require("ui.battle.combat.ProjectileSystem")
local RCH = require("systems.RelicConditionHandler")
local FX = require("ui.battle.combat.BattleEffects")
local Stats = require("systems.BattleStats")

local assertions, failures = 0, 0
local function check(ok, message)
    assertions = assertions + 1
    if not ok then failures = failures + 1 end
    print("[Fusion][" .. (ok and "PASS" or "FAIL") .. "] " .. message)
end
local function near(a, b)
    return type(a) == "number" and math.abs(a - b) < 1e-6
end
local function case(name, fn)
    local ok, err = pcall(fn)
    if not ok then check(false, name .. ": " .. tostring(err)) end
end

local serial = 0
local function hero(id, first, second)
    local branch = first and { first = first, second = second } or nil
    local u = assert(HC.createHero(id, 40, branch, {}, false, { litNodes = {}, silent = true }))
    serial = serial + 1
    u.instanceId = 95000 + serial
    local bases = {}
    for key in pairs(AD.META) do bases[key] = AD.getDefault(key) end
    for _, key in ipairs(AD.BASE_STATS) do bases[key] = 0 end
    bases[AD.MAX_HP], bases[AD.PHYS_ATK], bases[AD.MAG_ATK] = 100000, 1000, 1000
    bases[AD.HEAL_AMOUNT], bases[AD.HIT_VALUE] = 1000, 100000
    bases[AD.ARMOR], bases[AD.DODGE], bases[AD.ATK_HEAL] = 0, 0, 0
    bases[AD.CRIT_RATE], bases[AD.PHYS_CRIT_RATE], bases[AD.MAG_CRIT_RATE] = 0, 0, 0
    bases[AD.COMBO_RATE], bases[AD.PHYS_BLOCK_RATE], bases[AD.MAG_BLOCK_RATE] = 0, 0, 0
    bases[AD.HP_REGEN] = 0
    u.attrs:clearModifiers()
    u.attrs:setBases(bases)
    u.attrs.atkCoeff, u.attrs.dmgSpread = 1, 0
    u.attrs:fillHp()
    u.attrs._forceFullHpOnRecalc = nil
    u.attrs.energyShield, u.attrs.tempEnergyShield = 0, 0
    u.atkTargets, u.attackChain = 1, false
    BC.syncUnitHp(u)
    return u
end
local function hp(u, amount)
    u.attrs.final[AD.HP], u.hp = amount, amount
    u.attrs._forceFullHpOnRecalc = nil
end

local function setup(allies, enemies)
    -- 丢测试账本再挂新状态，不 flush 任何永久成长。
    CGR.resetFusionBattle(TAL.mountedState().bAllies, TAL.mountedState().bEnemies)
    ETS.discard()
    TAL.mount(TAL.newBattleRefs())
    TAL.mountUnitStates(TAL.newUnitStates())
    BC.mount(BC.newState("advancement-fusion-test"))
    TM.mount(TM.newState())
    SEM.mount(SEM.newSemState())
    ETS.mount(ETS.newState())
    PS.mount(PS.newState())
    RCH.mount(RCH.newState())
    FX.mount(FX.newFxState())
    ART.reset()
    Stats.mount(953)
    BC.setContext({ getAllies = function() return allies end,
        getEnemies = function() return enemies end })
    for _, list in ipairs({ allies, enemies }) do
        for _, u in ipairs(list) do TAL.initUnit(u) end
    end
    TM.onBattleStart(allies, enemies)
    TAL.onBattleStart(allies, enemies)
end
local function tick(dt, allies, enemies)
    TAL.update(dt, allies, enemies, {
        dealDamage = BC.dealDamageToUnit,
        dealTalentDamage = function(source, target, damage, isTargetAlly, prefix, color, opts)
            return BC.dealTalentDamage(source, target, damage, isTargetAlly, prefix, color, opts, allies, enemies)
        end,
        syncHp = BC.syncUnitHp,
        healUnit = function(u, amount) return u.attrs:heal(amount) end,
    })
end
local function attack(attacker, targets, isAlly, seed)
    math.randomseed(seed or 95200)
    BC.performAttack(attacker, targets, isAlly)
end
local function hit(source, target, damage, targetAlly)
    return BC.dealTalentDamage(source, target, damage, targetAlly, "融合探针", nil,
        { instantDamage = true, noCounter = true })
end

-- 观察器仅记录正式钩子入参，再原样执行；不替换被测实现。
local function observeAttack(fn)
    local original = CGR.onAfterAttack
    local seen = {}
    CGR.onAfterAttack = function(a, t, r, ...)
        seen[#seen + 1] = { attacker = a, target = t, result = r }
        return original(a, t, r, ...)
    end
    local ok, err = pcall(fn, seen)
    CGR.onAfterAttack = original
    if not ok then error(err, 0) end
end

local SPECS = {
    { id = 225, hero = 24, parents = { 101, 102 } },
    { id = 226, hero = 1, parents = { 103, 104 } },
    { id = 227, hero = 2, parents = { 105, 106 } },
    { id = 228, hero = 3, parents = { 107, 108 } },
    { id = 229, hero = 18, parents = { 109, 110 } },
    { id = 230, hero = 19, parents = { 111, 112 } },
}

local function configPipeline()
    for _, spec in ipairs(SPECS) do
        for _, first in ipairs(spec.parents) do
            local u = hero(spec.hero, first, spec.id)
            local expected = AVC.getTalentIds(u.advBranch)
            local seen = {}
            for _, id in ipairs(u.advTalentIds) do seen[id] = (seen[id] or 0) + 1 end
            check(#expected == 3 and #u.advTalentIds == 3
                and seen[assert(AVC.get(spec.parents[1])).talentId] == 1
                and seen[assert(AVC.get(spec.parents[2])).talentId] == 1
                and seen["gate_" .. spec.id .. "_fusion"] == 1,
                "AVC→HC 两父天赋+marker去重 id=" .. spec.id .. " first=" .. first)
        end
    end
end

local function sealCombat()
    for _, first in ipairs({ 101, 102 }) do
        local seal, friend, enemy = hero(24, first, 225), hero(2), hero(1)
        local allies, enemies = { seal, friend }, { enemy }
        setup(allies, enemies)
        check(near(seal._gateCap, seal.maxHp * 0.18) and seal._gateEnemyRatio == 0.5,
            "225 同时有门闩容量+转敌比例 first=" .. first)
        observeAttack(function(seen)
            local before = seal.hp
            attack(enemy, { seal }, false)
            local raw = seen[#seen].result.damageDealt
            -- damageDealt 是桥接后的剩余值；全部吸收时为0。
            check(seal.hp == before and raw == 0 and seal._gateStored > 0,
                "225 真实敌普攻先吸收且不扣血 first=" .. first)
        end)
        local stored = seal._gateStored
        hit(enemy, seal, 77, true)
        check(near(seal._gateStored, stored + 77), "225 附伤单次吸收77，不重复入池")
        hit(enemy, seal, seal._gateCap, true)
        check(near(seal._gateStored, seal._gateCap), "225 容量满后多余真实附伤落HP")
        local beforeEnemy, beforeSeal = enemy.hp, seal.hp
        tick(0.1, allies, enemies)
        check(TM.mountedState().forcedTarget == seal and TM.mountedState().forcedTargetTimer == 2,
            "225 满池闸门实际强制嘲讽2秒")
        check(TM.selectTarget({ friend, seal }) == 2, "225 嘲讽真实影响ThreatManager选敌")
        check(near(seal._gateStored, seal._gateCap * 0.7 * 0.98)
            and enemy.hp < beforeEnemy and seal.hp < beforeSeal,
            "225 清30%后按50/50正常释放，自身伤害不被免除")
        TAL.reset()
        check(seal._gateStored == nil and seal._fusionToken == nil, "225 reset清门缝与融合绑定")
    end
    local old, enemy = hero(24, 101, 201), hero(1)
    setup({ old }, { enemy })
    local before = old.hp
    attack(enemy, { old }, false)
    check(old.hp < before and old._gateStored == 0, "旧201普通承伤不被本次新门缝桥接改变")
end

local function sealShareCombat()
    for _, first in ipairs({ 101, 102 }) do
        local seal, friend, enemy = hero(10, first, 225), hero(2), hero(1)
        local allies, enemies = { seal, friend }, { enemy }
        setup(allies, enemies)
        local beforeSeal, beforeFriend, transfer = seal.hp, friend.hp, 0
        observeAttack(function(seen)
            attack(enemy, { friend }, false)
            local result = seen[#seen].result
            transfer = math.floor(result.totalDamage * 0.15 + 0.5)
            check(transfer > 50 and seal.hp == beforeSeal and near(seal._gateStored, transfer),
                "225 铁憨憨真实队友分摊全入门缝一次 first=" .. first)
            check(friend.hp == beforeFriend - result.totalDamage + transfer,
                "225 分摊仍只减队友原伤15%，不重入TAL")
        end)
        -- 真实附伤填到差50，再让同一真实普攻分摊跨容量边界。
        hit(enemy, seal, seal._gateCap - seal._gateStored - 50, true)
        beforeSeal = seal.hp
        attack(enemy, { friend }, false)
        check(near(seal._gateStored, seal._gateCap) and seal.hp == beforeSeal - transfer + 50,
            "225 分摊仅吸最后50容量，溢出量真实扣铁憨憨HP")
        beforeSeal = seal.hp
        attack(enemy, { friend }, false)
        check(near(seal._gateStored, seal._gateCap) and seal.hp == beforeSeal - transfer,
            "225 满池后分摊不凭空消失或双吸收")
        tick(0, allies, enemies)
        check(TM.mountedState().forcedTarget == seal and TM.mountedState().forcedTargetTimer == 2
            and near(seal._gateStored, seal._gateCap * 0.7) and TM.selectTarget({ friend, seal }) == 2,
            "225 分摊填满真实触发闸门嘲讽+清30%（dt0边界）")
        local stored = seal._gateStored
        beforeSeal = seal.hp
        observeAttack(function(seen)
            attack(enemy, { seal }, false)
            local raw = seen[#seen].result.totalDamage
            check(seal.hp == beforeSeal and near(seal._gateStored, stored + raw),
                "225 改打本人只走普通吸收一次，不再次队友分摊")
        end)
    end
    for _, spec in ipairs({ {}, { first = 101 }, { first = 101, second = 201 } }) do
        local old, friend, enemy = hero(10, spec.first, spec.second), hero(2), hero(1)
        setup({ old, friend }, { enemy })
        local beforeOld, beforeFriend = old.hp, friend.hp
        observeAttack(function(seen)
            attack(enemy, { friend }, false)
            local raw = seen[#seen].result.totalDamage
            local transfer = math.floor(raw * 0.15 + 0.5)
            check(old.hp == beforeOld - transfer and friend.hp == beforeFriend - raw + transfer
                and (old._gateStored or 0) == 0,
                "旧铁憨憨无转职/101/201分摊直接扣HP不改 first=" .. tostring(spec.first)
                    .. " second=" .. tostring(spec.second))
        end)
    end
end

local function spoilCombat()
    for _, first in ipairs({ 103, 104 }) do
        local spoil, original, advantage, excluded = hero(1, first, 226), hero(2), hero(2), hero(2)
        spoil.attrs.atkType, spoil.atkType = AD.ATK_SLASH, AD.ATK_SLASH
        original.attrs.armorType, original.armorType = AD.ARMOR_PLATE, AD.ARMOR_PLATE
        advantage.attrs.armorType, advantage.armorType = AD.ARMOR_CLOTH, AD.ARMOR_CLOTH
        excluded.attrs.armorType, excluded.armorType = AD.ARMOR_CLOTH, AD.ARMOR_CLOTH
        excluded.artifactUntargetable = true
        local allies, enemies = { spoil }, { original, advantage, excluded }
        setup(allies, enemies)
        check(spoil._spoilCap == 18, "226 骨市18容量 first=" .. first)
        for _ = 1, 5 do
            local dead = hero(2)
            dead.isElite = true
            enemies[#enemies + 1] = dead
            hit(spoil, dead, dead.hp + 1, false)
        end
        check(spoil._spoilBones == 18 and spoil._spoilReady, "226 精英+3与普通1同时入骨，封顶18")
        hp(spoil, 80000)
        local beforeOriginal, beforeAdvantage, beforeExcluded = original.hp, advantage.hp, excluded.hp
        observeAttack(function(seen)
            attack(spoil, { original }, true)
            check(seen[#seen].target == original and original.hp < beforeOriginal,
                "226 普攻原目标未改 first=" .. first)
        end)
        -- 传给 BC 的本次 targetList 是原目标单元素；追加全战线列表才能检测优选。
        check(spoil._spoilBones == 12 and not spoil._spoilReady and spoil.hp == 80800,
            "226 消耗6骨且实际恢复4%已损失生命")
        check(advantage.hp == beforeAdvantage and excluded.hp == beforeExcluded,
            "226 不擅自扫描本次targetList外目标")
        -- 正式后攻击入口传完整敌阵，但普攻选择仍用正式CF固定种子。
        spoil._spoilBones, spoil._spoilReady = 18, true
        local originalHp, advantageHp = original.hp, advantage.hp
        local choiceSeed = 95315
        for seed = 95315, 95415 do
            math.randomseed(seed)
            if CF.selectTarget(enemies) == 1 then choiceSeed = seed; break end
        end
        observeAttack(function(seen)
            attack(spoil, enemies, true, choiceSeed)
            local r = seen[#seen]
            check(r.result.actualDamage > 0 and r.target == original,
                "226 正式CF普攻选不利原目标，额击才另选优势目标")
            check(original.hp == originalHp - r.result.actualDamage and advantage.hp == advantageHp - 400,
                "226 原目标仅承普攻，优势目标真实只承400额击")
        end)
        check(advantage.hp < advantageHp and excluded.hp == beforeExcluded,
            "226 实际额击优选克制优势活目标、跳过不可选目标")
        check(original.hp <= originalHp, "226 未给原目标额外恢复或改写死亡")
        TAL.reset()
        check(spoil.attrs.modifiers.gate_spoil_spd == nil and spoil._spoilBones == nil,
            "226 骸骨modifier与状态reset清理")
    end
    for _, second in ipairs({ 207, 208 }) do
        local old, original, other = hero(1, 104, second), hero(2), hero(2)
        original.attrs.armorType, other.attrs.armorType = AD.ARMOR_PLATE, AD.ARMOR_CLOTH
        setup({ old }, { original, other })
        old._spoilBones, old._spoilReady = 12, true
        local before = other.hp
        attack(old, { original }, true)
        check(other.hp == before, "旧104系二转不新增优势转火 id=" .. second)
    end
end

local function riftCombat()
    for _, first in ipairs({ 105, 106 }) do
        local rift, enemy = hero(2, first, 227), hero(1)
        local allies, enemies = { rift }, { enemy }
        setup(allies, enemies)
        local originalType = rift.attrs.atkType
        tick(6.01, allies, enemies)
        check(rift._riftLeft == 4, "227 错位6秒进入裂隙 first=" .. first)
        local baseMult = AD.getTypeMult(rift.attrs.atkType, enemy.attrs.armorType)
        check(near(CGR.adjustTypeMult(rift.attrs, enemy.attrs, baseMult), baseMult + (1.25 - baseMult) * 0.5),
            "227 attrs真实公式绑定裂隙克制拉近")
        for _, kind in ipairs({ AD.ATK_FIRE, AD.ATK_ICE, AD.ATK_LIGHTNING, AD.ATK_SHADOW }) do
            enemy.attrs:fillHp(); enemy.attrs._forceFullHpOnRecalc = nil; BC.syncUnitHp(enemy)
            local before = enemy.hp
            observeAttack(function(seen)
                attack(rift, enemies, true)
                check(rift.attrs.atkType == kind and rift.atkType == kind,
                    "227 实际后攻击切换元素 " .. kind)
                if kind == AD.ATK_LIGHTNING then
                    local normal = seen[#seen].result.actualDamage
                    check(before - enemy.hp == normal + 600 and enemy._riftStacks == 0,
                        "227 同一击错位600附伤+深缝元素都触发，不互斥")
                end
            end)
        end
        tick(4.01, allies, enemies)
        check(rift.attrs.atkType == originalType, "227 裂隙到期还原属性攻击类型")
        attack(rift, enemies, true)
        TAL.reset()
        check(enemy._riftStacks == nil and rift._fusionToken == nil, "227 reset清敌裂痕与owner")
    end
    local old, target = hero(2, 106, 211), hero(1)
    setup({ old }, { target })
    old._riftLeft = 4
    attack(old, { target }, true)
    tick(4.1, { old }, { target })
    check(old.attrs.atkType == AD.ATK_SHADOW, "旧211元素持久行为不被融合到期还原改变")
end

local function echoCombat()
    for _, first in ipairs({ 107, 108 }) do
        local echo, enemy = hero(3, first, 228), hero(2)
        local allies, enemies = { echo }, { enemy }
        setup(allies, enemies)
        echo.attrs:setBases({ [AD.CRIT_RATE] = 250, [AD.CRIT_DMG] = 100 })
        attack(echo, enemies, true)
        local firstJob = echo._echoQueue[1]
        attack(echo, enemies, true)
        local secondJob = echo._echoQueue[2]
        check(firstJob and secondJob and firstJob.t == 0.8 and secondJob.t == 0.8
            and firstJob.crit and secondJob.crit,
            "228 第二回响仍0.8秒且有暴击 first=" .. first)
        check(secondJob.dmg > firstJob.dmg, "228 第二回响实际70%伤害")
        attack(echo, enemies, true)
        check(#echo._echoQueue == 2, "228 同目标最大2回响")
        local before, threatBefore = enemy.hp, TM.getThreat(echo)
        tick(0.79, allies, enemies)
        check(enemy.hp == before and #echo._echoQueue == 2, "228 尚未到期不会提前结算")
        local total = math.floor(firstJob.dmg * 2) + math.floor(secondJob.dmg * 2)
        tick(0.02, allies, enemies)
        check(enemy.hp == before - total and #echo._echoQueue == 0,
            "228 两次暴击回响真实BC扣血且出队")
        local expectedThreat = total * require("config.ClassConfig").getDmgThreatCoeff(echo.classId) * 0.1
        check(near(TM.getThreat(echo) - threatBefore, expectedThreat), "228 回响meta真实来源/10%仇恨仅一次")
        attack(echo, enemies, true)
        TAL.onBattleStart(allies, enemies)
        local reopenedHp = enemy.hp
        tick(1, allies, enemies)
        check(enemy.hp == reopenedHp and #echo._echoQueue == 0, "228 同对象重开清旧回响不跨场伤害")
    end
    local old, target = hero(3, 108, 215), hero(2)
    setup({ old }, { target })
    attack(old, { target }, true)
    check(old._echoQueue[1].t == 1.2 and not old._echoQueue[1].crit,
        "旧215未继承107短延迟/暴击")
end

local function maskCombat()
    for _, first in ipairs({ 109, 110 }) do
        local mask, left, target, right, far = hero(18, first, 229), hero(2), hero(19), hero(2), hero(2)
        -- 死亡前列表中的复制目标位于2；首个空血槽不参与首次复制。
        hp(left, 0)
        local allies, enemies = { mask }, { left, target, right, far }
        setup(allies, enemies)
        hp(mask, 80000)
        check(mask._maskTarget == target and mask._fusionBorrowLeech and mask._fusionBorrowT == nil,
            "229 首次复制治疗目标获得无时限下一击吸血 first=" .. first)
        tick(3.9, allies, enemies)
        check(mask._fusionBorrowLeech and mask._fusionBorrowT == nil,
            "229 治疗借面3.9秒仍待下一实际普攻")
        mask.attrs:setBase(AD.ATK_HEAL, 0)
        target.attrs.energyShield = 100000
        attack(mask, { target }, true)
        check(mask.hp == 80000 and mask._fusionBorrowLeech, "229 全盾不触发或消费8%吸血")
        tick(0.2, allies, enemies)
        check(mask._fusionBorrowLeech and mask._fusionBorrowT == nil and mask.hp == 80000,
            "229 全盾后跨4.1秒不自动丢下一击吸血")
        attack(mask, { target }, true)
        check(mask.hp == 80000 and mask._fusionBorrowLeech, "229 4.1秒后全盾仍不消费吸血")
        target.attrs.energyShield = 0
        target.attrs:setBase(AD.DODGE, 1000000000)
        observeAttack(function(seen)
            attack(mask, { target }, true)
            check(#seen == 0 and mask._fusionBorrowLeech and mask.hp == 80000,
                "229 正式命中公式miss不消费吸血")
        end)
        target.attrs:setBase(AD.DODGE, 0)
        observeAttack(function(seen)
            attack(mask, { target }, true)
            local actual = seen[#seen].result.actualDamage
            check(mask.hp == 80000 + math.floor(actual * 0.08) and not mask._fusionBorrowLeech,
                "229 普攻真实actualDamage×8%单次回血")
        end)
        local once = mask.hp
        attack(mask, { target }, true)
        check(mask.hp == once, "229 下一击吸血消费后不重复")
        local unrelated = hero(2)
        enemies[#enemies + 1] = unrelated
        hit(mask, unrelated, unrelated.hp + 1, false)
        check(mask._maskTarget == target and (mask._maskWindow or 0) == 0,
            "229 不相关敌死不剥面、不改变原first复制目标")
        hp(left, left.maxHp)
        for _, u in ipairs({ left, right, far }) do u.attrs:setBase(AD.ARMOR, 100) end
        local oldShield = right.attrs:get(AD.ENERGY_SHIELD)
        hit(mask, target, target.hp + 1, false)
        check(near(left.attrs:get(AD.ARMOR), 80) and near(right.attrs:get(AD.ARMOR), 80)
            and near(far.attrs:get(AD.ARMOR), 100), "229 被复制目标死亡只邻左右2秒削甲20%")
        check(right.attrs:get(AD.ENERGY_SHIELD) == oldShield, "229 削甲不把MAG_ARMOR护盾误减")
        observeAttack(function(seen)
            attack(mask, { right }, true)
            check(near(seen[#seen].result.resistance, CF.armorToResistance(80 * 0.8)),
                "229 剥面真实普攻抗性读80护甲，并保留换面下一击20%忽甲")
        end)
        tick(0.01, allies, enemies)
        check(mask._maskTarget == left and mask.attrs.modifiers.gate_fusion_borrow ~= nil,
            "229 死后重新复制非治疗目标真实攻速+8")
        local beforeSpeed = mask.attrs:get(AD.ATK_SPEED)
        local ordinary = hero(18, 109)
        check(near(beforeSpeed, ordinary.attrs:get(AD.ATK_SPEED) + 8), "229 +8是攻速百分点，不是pct乘基数")
        local sameMask = hero(18, first, 229)
        TAL.initUnit(sameMask)
        allies[#allies + 1] = sameMask
        CGR.onBattleStart({ sameMask }, enemies)
        -- 第二融合复制left，死亡触发同一right之外的相邻槽；不把多来源减益累计。
        sameMask._maskTarget = target
        mask._maskTarget = target
        target.attrs:fillHp(); target.attrs._forceFullHpOnRecalc = nil; BC.syncUnitHp(target)
        TAL.resetEnemyDeath(target)
        hit(mask, target, target.hp + 1, false)
        check(near(right.attrs:get(AD.ARMOR), 80), "229 多融合来源刷新同一20%modifier不叠加")
        tick(2.01, allies, enemies)
        check(near(right.attrs:get(AD.ARMOR), 100) and right.attrs.modifiers.gate_fusion_strip == nil,
            "229 2秒到期实际护甲modifier清除")
        tick(2.01, allies, enemies)
        -- 第二次复制在上一tick发生，四秒应从该次复制起算，不提前过期。
        tick(2.0, allies, enemies)
        check(mask.attrs.modifiers.gate_fusion_borrow == nil, "229 4秒攻速buff到期清除")
        TAL.reset()
        check(mask._maskTarget == nil and mask._fusionToken == nil, "229 reset清目标/借面/绑定")
    end
    for _, first in ipairs({ 109, 110 }) do
        local old, target, neighbor = hero(18, first, first == 109 and 217 or 219), hero(19), hero(2)
        neighbor.attrs:setBase(AD.ARMOR, 100)
        setup({ old }, { target, neighbor })
        check(old._fusionBorrowT == nil and old.attrs.modifiers.gate_fusion_borrow == nil,
            "旧借面无消费者行为保留 first=" .. first)
        hit(old, target, target.hp + 1, false)
        tick(0.1, { old }, { target, neighbor })
        check(neighbor.attrs:get(AD.ARMOR) == 100, "旧剥面不新增真实削甲 first=" .. first)
    end
end

local function maskBorrowLifecycle()
    for _, first in ipairs({ 109, 110 }) do
        local mask, healerTarget, nextTarget = hero(18, first, 229), hero(19), hero(2)
        local allies, enemies = { mask }, { healerTarget, nextTarget }
        setup(allies, enemies)
        hp(mask, 80000)
        tick(3.9, allies, enemies)
        observeAttack(function(seen)
            attack(mask, { healerTarget }, true)
            check(mask.hp == 80000 + math.floor(seen[#seen].result.actualDamage * 0.08)
                and not mask._fusionBorrowLeech, "229 3.9秒真实扣HP吸血消费一次 first=" .. first)
        end)
        TAL.onBattleStart(allies, enemies)
        tick(4.1, allies, enemies)
        check(mask._fusionBorrowLeech, "229 同对象重开治疗借面4.1秒保留待消费")
        hp(mask, 0)
        tick(0, allies, enemies)
        hp(mask, mask.maxHp)
        check(not mask._fusionBorrowLeech and mask._fusionBorrowT == nil,
            "229 本体死亡立即清待消费，复活不带旧借面")
        TAL.onBattleStart(allies, enemies)
        hit(mask, healerTarget, healerTarget.hp + 1, false)
        tick(0, allies, enemies)
        check(mask._maskTarget == nextTarget and not mask._fusionBorrowLeech
            and mask._fusionBorrowT == 4, "229 新复制非治疗目标替换旧待消费吸血")
        tick(3.9, allies, enemies)
        check(mask.attrs.modifiers.gate_fusion_borrow ~= nil and mask._fusionBorrowT > 0,
            "229 非治疗+8攻速3.9秒仍存在")
        tick(0.2, allies, enemies)
        check(mask.attrs.modifiers.gate_fusion_borrow == nil and mask._fusionBorrowT == nil,
            "229 非治疗+8攻速4.1秒确实过期")
        hp(healerTarget, healerTarget.maxHp)
        TAL.onBattleStart(allies, enemies)
        check(mask._fusionBorrowLeech, "229 reset前确有治疗待消费")
        TAL.reset()
        check(mask._fusionBorrowLeech == nil and mask._fusionBorrowT == nil,
            "229 reset清无时限吸血，不能跨战线复用")
    end
end

local function debtCombat()
    for _, first in ipairs({ 111, 112 }) do
        local debt, one, two, three, enemy = hero(19, first, 230), hero(2), hero(3), hero(1), hero(2)
        local allies, enemies = { debt, one, two, three }, { enemy }
        setup(allies, enemies)
        debt.atkTargets = 2
        hp(one, 99900); hp(two, 99910)
        attack(debt, enemies, true)
        check(one._gateDefer and two._gateDefer and debt._deferCount == 2,
            "230 真实BC过量治疗同时保护2名队友 first=" .. first)
        CGR.onOverheal(debt, three, 100)
        check(not three._gateDefer, "230 第三人不超过双延缓容量")
        attack(enemy, { one }, false)
        -- 真实普攻致死随后由宿主使用同一TAL.onAllyDeath分发，不能改原BC死亡结算。
        hp(one, 1)
        attack(enemy, { one }, false)
        check(one.hp == 0 and TAL.onAllyDeath(one, allies, BC.syncUnitHp) and one.hp == 1
            and one._gateDebtT == 4, "230 普攻致死经正式宿主TAL拦截留1血4秒债")
        hit(enemy, two, two.hp + 1, true)
        check(two.hp == 1 and two._gateDebtT == 4, "230 附伤BC致死同样只触发一次延缓")
        hp(one, 50000); hp(two, 50000); hp(debt, 50000); hp(three, 50000)
        observeAttack(function(seen)
            attack(enemy, { one }, false)
            local after = seen[#seen].result.damageDealt
            math.randomseed(95200)
            local baseline = assert(CF.calcAttack(enemy.attrs, one.attrs).totalDamage)
            check(near(after, baseline * 1.15) and near(one._gateDebtTaken, after),
                "230 正式普攻债期确切1.15倍率与记账只一次")
        end)
        local oldTaken, oldHp = one._gateDebtTaken, one.hp
        hit(enemy, one, 1000, true)
        check(near(one._gateDebtTaken, oldTaken + 1150) and one.hp == oldHp - 1150,
            "230 附伤债期1.15倍率仅一次")
        hp(two, 50000)
        hit(enemy, two, 500, true)
        local healTotal = math.floor(one._gateDebtTaken * 0.1 + two._gateDebtTaken * 0.1)
        local before = three.hp
        tick(4.01, allies, enemies)
        check(three.hp == before + healTotal and one._gateDebtT == nil and two._gateDebtT == nil
            and debt._deferCount == 0, "230 双债结束领忏真实全队回血且释放两容量")
        CGR.onOverheal(debt, one, 100)
        TAL.onBattleStart(allies, enemies)
        check(not one._gateDefer and one._gateDeferHealer == nil and not one._fusionDeferToken
            and debt._deferCount == nil, "230 同对象重开清旧延缓/来源/容量")
    end
    local old, friend, enemy = hero(19, 112, 223), hero(2), hero(2)
    setup({ old, friend }, { enemy })
    CGR.onOverheal(old, friend, 100)
    hp(friend, 1)
    attack(enemy, { friend }, false)
    check(friend.hp == 0 and not TAL.onAllyDeath(friend, { old, friend }, BC.syncUnitHp),
        "旧223普通致死不被新增230桥接改变")
end

local function lifecycle()
    local rift, mask, echo, debt = hero(2, 105, 227), hero(18, 109, 229), hero(3, 107, 228), hero(19, 111, 230)
    local target = hero(2)
    local allies, enemies = { rift, mask, echo, debt }, { target }
    setup(allies, enemies)
    rift._riftLeft = 4
    attack(rift, enemies, true)
    local snapshot = rift.attrs:clone()
    local mult = AD.getTypeMult(snapshot.atkType, target.attrs.armorType)
    check(near(CGR.adjustTypeMult(snapshot, target.attrs, mult), mult),
        "属性clone不拷贝融合owner引用，快照不会误借原战线")
    local oldAttrs = rift.attrs
    rift.attrs = snapshot
    check(near(CGR.adjustTypeMult(oldAttrs, target.attrs, mult), mult), "旧attrs绑定在刷新换对象后自动失效")
    TAL.onBattleStart(allies, enemies)
    rift._riftLeft = 4
    local rebound = CGR.adjustTypeMult(rift.attrs, target.attrs, mult)
    check(near(rebound, mult + (1.25 - mult) * 0.5), "刷新快照后重新start绑定当前attrs")
    attack(echo, enemies, true)
    CGR.onOverheal(debt, mask, 100)
    local before = target.hp
    TAL.reset()
    tick(10, {}, enemies)
    check(target.hp == before and not mask._gateDefer and echo._echoQueue == nil,
        "reset后旧回响/延缓/目标属性均不跨场")

    setup({ echo }, { target })
    attack(echo, { target }, true)
    local removedHp = target.hp
    tick(1, { echo }, {})
    check(target.hp == removedHp and #echo._echoQueue == 0, "228 已离场但还活着的目标不能被旧队列打伤")
    attack(echo, { target }, true)
    local beforeDeathHp = target.hp
    hp(echo, 0)
    tick(0.01, { echo }, { target })
    hp(echo, echo.maxHp)
    tick(1, { echo }, { target })
    check(target.hp == beforeDeathHp and #echo._echoQueue == 0,
        "228 回响者死亡清队列，再入场不复用旧回响")

    local lane1, laneTarget1, lane2, laneTarget2 = hero(18, 109, 229), hero(2), hero(18, 110, 229), hero(2)
    setup({ lane1 }, { laneTarget1 })
    local refs1, units1 = TAL.mountedState(), TAL.mountedUnitStates()
    local states = { BC = BC.mountedState(), TM = TM.mountedState(), SEM = SEM.mountedState(),
        ETS = ETS.mountedState(), PS = PS.mountedState(), RCH = RCH.mountedState(), FX = FX.mountedState() }
    TAL.mount(TAL.newBattleRefs()); TAL.mountUnitStates(TAL.newUnitStates())
    TAL.initUnit(lane2); TAL.initUnit(laneTarget2)
    TAL.onBattleStart({ lane2 }, { laneTarget2 })
    local secondToken = lane2._fusionToken
    TAL.mount(refs1); TAL.mountUnitStates(units1)
    for name, module in pairs({ BC = BC, TM = TM, SEM = SEM, ETS = ETS, PS = PS, RCH = RCH, FX = FX }) do
        module.mount(states[name])
    end
    TAL.reset()
    check(lane1._fusionToken == nil and lane2._fusionToken == secondToken
        and lane2.attrs.modifiers.gate_fusion_borrow ~= nil, "并行mount重置队1不清队2融合token/buff")
    CGR.resetFusionBattle({ lane2 }, { laneTarget2 })
end

function Start()
    print("[Fusion] 开始6融合真实能力、旧ID对照与复位回归")
    for _, test in ipairs({ configPipeline, sealCombat, sealShareCombat, spoilCombat, riftCombat, echoCombat,
        maskCombat, maskBorrowLifecycle, debtCombat, lifecycle }) do case("融合回归", test) end
    ETS.discard()
    print(string.format("[advancement_fusion_combat_test] assertions=%d failures=%d %s",
        assertions, failures, failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
