-- 套装约x2独立回归：期望值不从配置反推，避免配置与运行同时漂移仍假通过。
local AD = require("systems.AttributeDef")
local UA = require("systems.UnitAttributes")
local ESC = require("config.EquipmentSetConfig")
local Sets = require("systems.EquipmentSetSystem")
local ESR = require("systems.EquipmentSetRuntime")
local CP = require("systems.CombatPower")
local TM = require("systems.ThreatManager")

local assertions, failures = 0, 0
local function check(condition, message)
    assertions = assertions + 1
    if not condition then
        failures = failures + 1
        print("[套装增强][FAIL] " .. message)
    end
end
local function near(actual, expected, message)
    check(type(actual) == "number" and math.abs(actual - expected) < 1e-7,
        message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function runCase(name, fn)
    local ok, err = pcall(fn)
    if not ok then check(false, name .. "执行异常：" .. tostring(err)) end
end
local function withRandom(value, fn)
    local original = math.random
    math.random = function(n)
        if n then return 1 end
        return value
    end
    local ok, err = pcall(fn)
    math.random = original
    if not ok then error(err) end
end
local function unit(setId, six)
    local attrs = UA.create({ [AD.MAX_HP] = 10000, [AD.PHYS_ATK] = 100,
        [AD.MAG_ATK] = 100, [AD.HIT_VALUE] = 0, [AD.COMBO_RATE] = 0 })
    attrs._setFour = setId
    attrs._setSix = setId
    if six == false then attrs._setSix = nil end
    attrs:fillHp()
    attrs:recalc() -- 消费正式满血初始化标志，然后测试战斗中的血量与修改器。
    return { attrs = attrs, hp = attrs:get(AD.HP), maxHp = attrs:get(AD.MAX_HP), atkProgress = 1 }
end
local function hp(target, value)
    target.attrs.final[AD.HP] = value
    target.hp = value
end
local function result(overrides)
    local r = { totalDamage = 1000, isMiss = false, isCrit = false, category = "physical" }
    for key, value in pairs(overrides or {}) do r[key] = value end
    return r
end
local function collector()
    local calls = {}
    return calls, function(target, damage, targetIsAlly, prefix, color, source, meta)
        calls[#calls + 1] = { target = target, damage = damage, targetIsAlly = targetIsAlly,
            prefix = prefix, color = color, source = source, meta = meta }
    end
end
local function afterAttack(owner, target, r, isAlly, targets)
    local calls, direct = collector()
    ESR.onAfterAttack(owner, target, r, isAlly, function(t, damage, ally, prefix, color, opts)
        direct(t, damage, ally, prefix, color, owner, opts)
    end, targets or { target })
    return calls
end
local function callback(call, target, owner, isAlly, setId, noThreat)
    check(call ~= nil, setId .. "产生预期回调")
    if not call then return end
    check(call.target == target and call.source == owner and call.targetIsAlly == isAlly,
        setId .. "回调真实owner与目标阵营正确")
    check(call.meta and call.meta.noCounter == true and call.meta.setId == setId
        and call.meta.critEligible == false, setId .. "无反击递归且额伤统计归因明确")
    if noThreat then check(call.meta.noThreat == true, setId .. "明确无仇恨") end
end

local EXPECTED = {
    carapace = { two = { 12, 8 }, effect4 = { maxStacks = 8, damageReductionPerStack = 0.03 },
        effect6 = { damageRatioPerStack = 0.04, tauntDuration = 2 } },
    faceless = { two = { 8, 10 }, effect4 = { hpThreshold = 0.5, damageRatio = 0.5 }, effect6 = { duration = 8 } },
    riftcrystal = { two = { 8, 16 }, effect4 = { procChance = 0.15, maxStacks = 5, damageTakenPerStack = 0.03 },
        effect6 = { magRatio = 1.6, progressLoss = 0.6, bossProgressLoss = 0.2 } },
    last_rite = { two = { 16, 12 }, effect4 = { overhealShieldRatio = 0.4 }, effect6 = { teamShieldBonus = 16 } },
    tidepress = { two = { 12, 10 }, effect4 = { procChance = 0.3, splashRatio = 0.7, splashTargets = 1 },
        effect6 = { progressLoss = 0.4 } },
    nitros = { two = { 16, 12 }, effect4 = { hitStep = 80, comboPerStep = 4, comboCap = 20 },
        effect6 = { pierceRatio = 1, speedBonus = 24, duration = 2 } },
    swordgate = { two = { 16, 10 }, effect4 = { interval = 6, damageRatio = 0.3, swordCount = 1 },
        effect6 = { extraSwords = 1 } },
    starless = { two = { 8 }, effect4 = { magPen = 16 }, effect6 = { interval = 8, magRatio = 2.4 } },
    ironwall = { two = { 8, 8 }, effect4 = { healMaxHpRatio = 0.02 }, effect6 = { reflectRatio = 0.6 } },
    emberscout = { two = { 10, 8 }, effect4 = { duration = 2, damageTakenRatio = 0.16 },
        effect6 = { spreadTargets = 2 } },
    gambler = { two = { 8, 16 }, effect4 = { critPerStack = 12, maxStacks = 3 },
        effect6 = { damageRatio = 0.6, healLostHpRatio = 0.02 } },
    bonehunger = { two = { 10, 8 }, effect4 = { hpThreshold = 0.7, speedBonus = 16 },
        effect6 = { healMaxHpRatio = 0.06 } },
}
local EXPECTED_DESCRIPTIONS = {
    carapace = { "生命+12%，护甲加成+8%。", "每次受击获得1层甲片（最多8）。每层受伤-3%。",
        "甲片满层时，下次攻击消耗全部层数，按层数×4%追加伤害并嘲讽2秒。" },
    faceless = { "暴击率+8%，闪避+10。", "攻击生命低于50%的敌人时，追加50%本次伤害。",
        "敌人死亡后8秒进入无面：清空仇恨，期间不产生仇恨。" },
    riftcrystal = { "全伤害+8%，能量护盾加成+16%。",
        "攻击命中15%给目标1层晶蚀（最多5）。每层使目标受到的全伤害+3%。",
        "晶蚀满5层碎裂：160%魔攻暗影伤害，并打断攻击进度。" },
    last_rite = { "治疗加成+16%，能量护盾加成+12%。", "过量治疗的40%转为能量护盾。",
        "全队能量护盾加成+16%（不改写死亡）。" },
    tidepress = { "魔法穿透+12，攻速+10%。", "攻击主目标时30%溅射邻近1人，伤害70%。",
        "被溅射目标立即扣除40%攻击进度。" },
    nitros = { "攻速+16%，命中+12。", "每80点命中，连击率+4%（最多+20%）。",
        "连击时贯穿仇恨第二的目标（100%伤害）；仅1名敌人时自身攻速+24%持续2秒。" },
    swordgate = { "物理穿透+16，物伤+10%。", "每6秒召唤1柄门缝飞剑，伤害=这6秒自身伤害的30%。",
        "飞剑+1柄。穿套本人不额外飞一轮。" },
    starless = { "魔法伤害+8%。", "魔法穿透+16。", "每8秒对生命百分比最低的敌人打240%魔攻，不产生仇恨。" },
    ironwall = { "物理格挡+8%，生命+8%。", "格挡成功时回复2%最大生命。",
        "格挡成功时把挡掉伤害的60%反给攻击者（暗影，无仇恨）。" },
    emberscout = { "命中+10，物理穿透+8。", "攻击施加余烬2秒：目标受伤+16%。",
        "余烬目标死亡时，余烬弹射到另外2名敌人。" },
    gambler = { "命数+8，优势伤害+16%。", "未暴击时下次暴击率+12%（最多叠3层，暴击清空）。",
        "暴击时额外一段60%伤害；若未暴击则回复2%已损失生命。" },
    bonehunger = { "攻速+10%，攻击回血+8。", "生命低于70%时攻速再+16%。", "敌人死亡后回复6%最大生命。" },
}

local function testConfig()
    local count = 0
    for setId, expected in pairs(EXPECTED) do
        count = count + 1
        local cfg = ESC.SETS[setId]
        check(cfg ~= nil and #cfg.twoPiece == #expected.two, "两件条目数量保持 set=" .. setId)
        for index, value in ipairs(expected.two) do
            near(cfg.twoPiece[index].flat, value, "两件flat精确x2 " .. setId .. ":" .. index)
        end
        for _, tier in ipairs({ "effect4", "effect6" }) do
            for key, value in pairs(expected[tier]) do
                near(cfg[tier][key], value, "增强强度/保留触发边界 " .. setId .. ":" .. tier .. ":" .. key)
            end
        end
        for index, desc in ipairs(EXPECTED_DESCRIPTIONS[setId]) do
            check(cfg["desc" .. (index * 2)] == desc, "36句实际运行文案一致 " .. setId .. ":" .. index)
        end
        local attrs = unit().attrs
        local counts = { [setId] = 2 }
        Sets.applyTwoPieceToUnit(attrs, counts)
        Sets.applyTwoPieceToUnit(attrs, counts)
        for index, value in ipairs(expected.two) do
            near(attrs.modifiers["set2_" .. setId][index].flat, value, "两件实际注入且不叠倍 " .. setId)
        end
    end
    near(count, 12, "十二套完整验证")
end

local function testStatic()
    local owner = unit("nitros")
    for _, pair in ipairs({ { 79, 0 }, { 80, 4 }, { 159, 4 }, { 160, 8 }, { 400, 20 }, { 10000, 20 } }) do
        owner.attrs:setBase(AD.HIT_VALUE, pair[1])
        ESR.applyStaticBonuses(owner.attrs)
        ESR.applyStaticBonuses(owner.attrs)
        near(owner.attrs:get(AD.COMBO_RATE), pair[2], "硝烟命中分档/上限/幂等 " .. pair[1])
    end
    owner.attrs._setFour = "starless"
    local before = owner.attrs:get(AD.MAG_PEN)
    ESR.applyStaticBonuses(owner.attrs)
    ESR.applyStaticBonuses(owner.attrs)
    near(owner.attrs:get(AD.MAG_PEN) - before, 16, "无光四件魔穿只加16")
    check(owner.attrs.modifiers.set4_nitros == nil, "硝烟换无光清旧连击")
    owner.attrs._setFour = "bonehunger"
    ESR.applyStaticBonuses(owner.attrs)
    check(owner.attrs.modifiers.set4_starless == nil and owner.attrs.modifiers.set4_bonehunger == nil,
        "静态清旧无光且不激活低血条件攻速")
    for setId in pairs(EXPECTED) do
        if setId ~= "nitros" and setId ~= "starless" then
            local other = unit(setId)
            hp(other, 1000)
            ESR.applyStaticBonuses(other.attrs)
            check(next(other.attrs.modifiers) == nil, "非确定性四件不进静态属性 " .. setId)
        end
    end
    check(ESR.applyStaticBonuses(nil) == nil, "空属性helper安全")
end

local function testAura()
    local owner, friend, otherTeam, noTeam = unit("last_rite"), unit(), unit(), unit()
    owner.teamIdx, friend.teamIdx, otherTeam.teamIdx = 1, "1", 2
    local original = friend.attrs
    local baseBonus = original:get(AD.ES_BONUS)
    local units = { owner, friend, otherTeam, noTeam }
    ESR.applyTeamAura(units)
    near(friend.attrs:get(AD.ES_BONUS) - baseBonus, 16, "真实同队司仪光环16")
    check(friend.attrs ~= original and original.modifiers.set6_last_rite == nil,
        "光环clone不污染之前复用attrs")
    check(otherTeam.attrs.modifiers.set6_last_rite == nil and noTeam.attrs.modifiers.set6_last_rite == nil,
        "显式旁队/未标队不被串队光环污染")
    local current = friend.attrs
    ESR.applyTeamAura(units)
    check(friend.attrs == current, "光环幂等不重复clone/叠加")
    local secondOwner = unit("last_rite")
    secondOwner.teamIdx = 1
    units[#units + 1] = secondOwner
    ESR.applyTeamAura(units)
    near(friend.attrs:get(AD.ES_BONUS) - baseBonus, 16, "两名司仪仍不叠光环")
    owner.attrs._setSix, secondOwner.attrs._setSix = nil, nil
    ESR.applyTeamAura(units)
    check(friend.attrs.modifiers.set6_last_rite == nil and current.modifiers.set6_last_rite ~= nil,
        "移除队内最后司仪仅变新attrs不污染旧快照")
    local unmarkedOwner, unmarkedFriend = unit("last_rite"), unit()
    ESR.applyTeamAura({ unmarkedOwner, unmarkedFriend })
    near(unmarkedFriend.attrs.modifiers.set6_last_rite[1].flat, 16, "旧同场无teamIdx调用保持兼容")
end

local function testShellAndVulnerability()
    local shell, target, source = unit("carapace"), unit(), unit("emberscout")
    near(ESR.onIncoming(shell, 0, source), 0, "零伤不增长虫壳")
    near(shell._setShell or 0, 0, "零伤层数仍0")
    near(ESR.onIncoming(shell, 100, source), 97, "每层3%虫壳减伤")
    for _ = 1, 20 do ESR.onIncoming(shell, 100, source) end
    near(shell._setShell, 8, "虫壳层数上限仍8")
    near(ESR.onIncoming(shell, 100, source), 76, "虫壳8层24%而非层数再翻倍")
    local calls = afterAttack(shell, target, result(), true)
    near(calls[1].damage, 320, "虫壳每层4%八层额伤32%")
    callback(calls[1], target, shell, false, "carapace")
    near(shell._setShell, 0, "虫壳攻击消费8层")
    afterAttack(source, target, result(), true)
    near(ESR.onIncoming(target, 100, source), 116, "余烬所有伤害易伤16%")
    target._crystal = 5
    near(ESR.onIncoming(target, 100, source), 116 * 1.15, "晶蚀每层3%全伤易伤乘区")
    ESR.update(2, {}, { target }, {})
    check(target._setEmber == nil and target._setEmberSrc == nil, "余烬仍2秒到期")
    near(ESR.onIncoming(target, 100, source), 115, "晶蚀5层保留15%全伤易伤")
end

local function testFaceless()
    local owner, target = unit("faceless"), unit()
    hp(target, 5000)
    check(#afterAttack(owner, target, result(), true) == 0, "无面50%严格低血门槛不变")
    hp(target, 4999)
    local calls = afterAttack(owner, target, result(), true)
    near(calls[1].damage, 500, "无面低血额伤50%")
    callback(calls[1], target, owner, false, "faceless")
    hp(target, 0)
    target._killedBy = owner
    ESR.onEnemyDeath(target, { owner }, { target })
    hp(target, 4999)
    near(owner._setFacelessT, 8, "无面击杀窗口8秒")
    check(ESR.shouldSkipThreat(owner), "无面窗口免仇恨API开启")
    calls = afterAttack(owner, target, result(), true)
    near(owner._setFacelessT, 8, "下一攻击不归零8秒窗口")
    check(calls[1].meta.noThreat == true, "无面额伤窗口明确免仇恨")
    ESR.update(7.99, { owner }, { target }, {})
    check(ESR.shouldSkipThreat(owner), "8秒前免仇恨保留")
    ESR.update(0.02, { owner }, { target }, {})
    check(not ESR.shouldSkipThreat(owner), "8秒后免仇恨关闭")
end

local function testCrystalAndSplash()
    local owner, target = unit("riftcrystal"), unit()
    withRandom(0.15, function() afterAttack(owner, target, result(), true) end)
    near(target._crystal or 0, 0, "晶蚀15%边界不触发，概率未翻倍")
    withRandom(0.149, function()
        for _ = 1, 4 do afterAttack(owner, target, result(), true) end
        near(target._crystal, 4, "晶蚀原5层触发阈值保留")
        near(ESR.onIncoming(target, 100, owner), 112, "晶蚀四层实战全伤易伤12%")
        local calls = afterAttack(owner, target, result(), true)
        near(calls[1].damage, 160, "晶蚀碎裂160%裸魔攻")
        callback(calls[1], target, owner, false, "riftcrystal")
        near(target._crystal, 0, "晶蚀碎裂清5层")
        near(target.atkProgress, 0.4, "晶蚀普通目标进度扣60%未翻倍")
        target.isBoss, target.atkProgress, target._crystal = true, 1, 4
        afterAttack(owner, target, result(), true)
        near(target.atkProgress, 0.8, "晶蚀Boss进度扣20%未翻倍")
    end)
    local water, first, second, third = unit("tidepress"), unit(), unit(), unit()
    withRandom(0.30, function()
        check(#afterAttack(water, first, result(), true, { first, second, third }) == 0,
            "水脉30%概率边界保持")
    end)
    withRandom(0.299, function()
        local calls = afterAttack(water, first, result(), false, { first, second, third })
        near(#calls, 1, "水脉溅射仍1目标")
        near(calls[1].damage, 700, "水脉溅伤70%而非概率伤害同翻倍")
        callback(calls[1], second, water, true, "tidepress")
        near(second.atkProgress, 0.6, "水脉即时扣40%攻击进度")
        near(third.atkProgress, 1, "水脉未命中第三人")
    end)
end

local function testNitrosAndPeriodic()
    local owner, first, second = unit("nitros"), unit(), unit()
    local calls = afterAttack(owner, first, result({ comboCount = 1 }), true, { first, second })
    near(calls[1].damage, 1000, "硝烟贯穿100%")
    callback(calls[1], second, owner, false, "nitros")
    afterAttack(owner, first, result({ comboCount = 1 }), true, { first })
    near(owner.attrs.modifiers.set6_nitros_spd[1].flat, 24, "独敌硝烟攻速24%")
    near(owner._setNitroT, 2, "独敌硝烟时长仍2秒")
    ESR.update(2, { owner }, { first }, {})
    check(owner.attrs.modifiers.set6_nitros_spd == nil, "独敌硝烟2秒及时清理")
    for _, six in ipairs({ false, true }) do
        local sword = unit("swordgate", six)
        ESR.addSwordWindowDamage(sword, 1000)
        local directCalls, direct = collector()
        ESR.update(5.99, { sword }, { first }, { dealDamage = direct })
        near(#directCalls, 0, "门剑6秒前不出剑")
        withRandom(0, function() ESR.update(0.02, { sword }, { first }, { dealDamage = direct }) end)
        near(#directCalls, six and 2 or 1, "门剑四件1柄六件总2柄不额外翻倍")
        for _, call in ipairs(directCalls) do
            near(call.damage, 300, "门剑窗口伤害30%")
            callback(call, first, sword, false, "swordgate", true)
        end
    end
    local star = unit("starless")
    hp(second, 1000)
    local starCalls, direct = collector()
    ESR.update(7.99, { star }, { first, second }, { dealDamage = direct })
    near(#starCalls, 0, "无光8秒前不输出")
    ESR.update(0.02, { star }, { first, second }, { dealDamage = direct })
    near(#starCalls, 1, "无光8秒一次不翻触发次数")
    near(starCalls[1].damage, 240, "无光240%裸魔攻")
    callback(starCalls[1], second, star, false, "starless", true)
end

local function testHealingAndReflection()
    local healer, target = unit("last_rite"), unit()
    target.attrs.energyShield, target.attrs.tempEnergyShield = 0, 0
    ESR.onOverheal(healer, target, 1000)
    near(target.attrs.tempEnergyShield, 400, "司仪过疗40%转临时盾")
    local wall, enemy = unit("ironwall"), unit()
    hp(wall, 5000)
    local calls, direct = collector()
    ESR.onBlocked(wall, enemy, 1000, direct, false)
    near(wall.hp, 5200, "铁壁格挡回复2%最大生命")
    near(calls[1].damage, 600, "铁壁反射挡掉伤害60%")
    callback(calls[1], enemy, wall, false, "ironwall", true)
    ESR.onBlocked(wall, enemy, 1000, direct, true)
    callback(calls[2], enemy, wall, true, "ironwall", true)
    hp(wall, 0)
    local previous = #calls
    ESR.onBlocked(wall, enemy, 1000, direct, false)
    near(wall.hp, 0, "死人格挡不回血复活")
    near(#calls, previous, "死人格挡不反射")
end

local function testSpreadAndGamblerAndBone()
    local ember, dead, a, b, c = unit("emberscout"), unit(), unit(), unit(), unit()
    afterAttack(ember, dead, result(), true)
    hp(dead, 0)
    ESR.onEnemyDeath(dead, { ember }, { dead, a, b, c })
    check(a._setEmber == 2 and b._setEmber == 2 and c._setEmber == nil,
        "余烬至少三活敌测试：传播2目标而非全体")
    check(a._setEmberSrc == ember and b._setEmberSrc == ember
        and dead._setEmber == nil and dead._setEmberSrc == nil, "传播真实来源且清死者残留")
    local gamble, target = unit("gambler"), unit()
    for _ = 1, 5 do afterAttack(gamble, target, result(), true) end
    near(gamble._setGamble, 3, "赌徒上限仍3层")
    near(gamble.attrs.modifiers.set4_gamble[1].flat, 36, "赌徒每层12%总36%")
    hp(gamble, 5000)
    afterAttack(gamble, target, result(), true)
    near(gamble.hp, 5100, "赌徒未暴击回2%已损生命")
    local calls = afterAttack(gamble, target, result({ isCrit = true }), true)
    near(calls[1].damage, 600, "赌徒暴击60%额伤")
    callback(calls[1], target, gamble, false, "gambler")
    check(gamble._setGamble == 0 and gamble.attrs.modifiers.set4_gamble == nil, "赌徒暴击清层")
    local bone = unit("bonehunger")
    hp(bone, 7000)
    afterAttack(bone, target, result(), true)
    check(bone.attrs.modifiers.set4_bonehunger == nil, "饥渴70%严格门槛保持")
    hp(bone, 6999)
    afterAttack(bone, target, result(), true)
    near(bone.attrs.modifiers.set4_bonehunger[1].flat, 16, "饥渴低血攻速16%")
    hp(target, 0)
    target._killedBy = bone
    ESR.onEnemyDeath(target, { bone }, { target })
    hp(target, 10000)
    near(bone.hp, 7599, "饥渴击杀回6%最大生命")
    afterAttack(bone, target, result(), true)
    check(bone.attrs.modifiers.set4_bonehunger == nil, "回血后低血条件移除")
end

local function testTemporaryShield()
    local healer = unit("last_rite")
    for _, shieldBase in ipairs({ 0, 100 }) do
        local target = unit()
        target.attrs:setBase(AD.ENERGY_SHIELD, shieldBase)
        target.attrs.energyShield, target.attrs.tempEnergyShield = 0, 0
        ESR.onOverheal(healer, target, 1000)
        near(target.attrs.tempEnergyShield, 400, "过疗临时盾400 baseES=" .. shieldBase)
        target.attrs:addModifier("shield_recalc_test", { { key = AD.ATK_SPEED, flat = 1 } })
        near(target.attrs.tempEnergyShield, 400, "无上限/有上限属性重算不抹过疗临时盾 baseES=" .. shieldBase)
        local oldHp = target.attrs:get(AD.HP)
        near(target.attrs:takeDamage(100), 0, "过疗盾优先承受100伤 baseES=" .. shieldBase)
        near(target.attrs.tempEnergyShield, 300, "临时盾消耗后剩300 baseES=" .. shieldBase)
        near(target.attrs:get(AD.HP), oldHp, "临时盾未破不掉血 baseES=" .. shieldBase)
        target.attrs:removeModifier("shield_recalc_test")
        near(target.attrs.tempEnergyShield, 300, "移除属性仍不恢复/抹掉已消耗临时盾 baseES=" .. shieldBase)
        ESR.resetBattleState(target)
        near(target.attrs.tempEnergyShield, 0, "新场边界显式清过疗临时盾 baseES=" .. shieldBase)
        target.attrs.tempEnergyShield = 700
        ESR.onBattleStart(target, { target })
        near(target.attrs.tempEnergyShield, 700, "套装后初始化不抹刚施加的开战天赋盾 baseES=" .. shieldBase)
    end
end

local function testDeathScope()
    local dead, faceless, secondFaceless, bone, deadBone, deadFaceless = unit(), unit("faceless"),
        unit("faceless"), unit("bonehunger"), unit("bonehunger"), unit("faceless")
    hp(bone, 5000)
    hp(deadBone, 0)
    hp(deadFaceless, 0)
    ESR.onEnemyDeath(dead, { faceless, secondFaceless, bone, deadBone, deadFaceless }, { dead })
    check(not ESR.shouldSkipThreat(faceless) and bone.hp == 5000, "存活敌人不分发敌死收益")
    hp(dead, 0)
    dead._killedBy = unit()
    ESR.onEnemyDeath(dead, { faceless, secondFaceless, bone, deadBone, deadFaceless }, { dead })
    check(faceless._setFacelessT == 8 and secondFaceless._setFacelessT == 8,
        "原队内敌死范围保留，无面不缩窄成末击独占")
    near(bone.hp, 5600, "他人末击仍给予队内饥渴6%敌死回血")
    check(deadBone.hp == 0 and not ESR.shouldSkipThreat(deadFaceless),
        "死持有者不被敌死回血复活或开启无面")
end

local function testPowerCoefficients()
    for _, setId in ipairs({ "starless", "riftcrystal" }) do
        local owner = unit(setId)
        owner.heroId = 1
        owner.attrs:setBase(AD.MAG_ATK, 100)
        local before = CP.calculate(owner, { teamUnits = { owner } })
        owner.attrs:setBase(AD.MAG_ATK, 200)
        local after = CP.calculate(owner, { teamUnits = { owner } })
        local coefficient = setId == "starless" and 2.4 / 8 or 1.6 * 0.15 / 5
        near(after - before, 100 * AD.META[AD.MAG_ATK].valueModel * coefficient,
            "原裸魔攻期望通道保留且增强系数一致 " .. setId)
    end
end

function Start()
    local oldThreatState = TM.mountedState()
    TM.mount(TM.newState())
    runCase("配置与36句", testConfig)
    runCase("确定性静态", testStatic)
    runCase("同队不污染光环", testAura)
    runCase("虫壳与全伤易伤", testShellAndVulnerability)
    runCase("无面窗口", testFaceless)
    runCase("水晶与水脉概率边界", testCrystalAndSplash)
    runCase("硝烟门剑无光", testNitrosAndPeriodic)
    runCase("过疗格挡反射", testHealingAndReflection)
    runCase("余烬赌徒饥渴", testSpreadAndGamblerAndBone)
    runCase("过疗临时盾与重算", testTemporaryShield)
    runCase("原队内敌死范围", testDeathScope)
    runCase("原静态预估通道", testPowerCoefficients)
    TM.mount(oldThreatState)
    print(string.format("[equipment_set_balance_test] assertions=%d failures=%d %s",
        assertions, failures, failures == 0 and "ALL PASS" or "FAILED"))
    if failures > 0 then log:Write(LOG_ERROR, "[equipment_set_balance_test] failed=" .. failures) end
    engine:Exit()
end
