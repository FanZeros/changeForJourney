-- 14/23/24 史诗觉醒Ⅱ专项：独立Runtime、真实TAL/BC/UA、内存拥有数据、存储四接口封闭。
local checks, failures = 0, 0
local function check(value, message)
    checks = checks + 1
    if not value then failures = failures + 1; print("[EpicEcho][FAIL] " .. message) end
end
local function awake(stage)
    local out = { _awk3Migrated = true }
    for n = 1, stage do out[n] = true end
    return out
end

function Start()
    local nativeRequire, nativeFile, nativeFS, nativeFs, nativeGetFS = require, File, FileSystem, fileSystem, GetFileSystem
    local storageCalls, sends = 0, 0
    local function denyStorage()
        storageCalls = storageCalls + 1
        error("EpicEcho禁止玩家存储访问", 0)
    end
    rawset(_G, "File", denyStorage)
    rawset(_G, "FileSystem", denyStorage)
    rawset(_G, "fileSystem", setmetatable({}, { __index = function() return denyStorage end }))
    rawset(_G, "GetFileSystem", denyStorage)
    local owned = {}
    local mocks = {
        ["ui.character.panel.CharacterPanel"] = {
            getOwnedHero = function(id) return owned[id] end,
            patchExtraTalent = function(id, extra) owned[id].extraTalent = extra end,
            finishExtraTalentBatch = function() end,
        },
        ["runtime.ClientDispatcher"] = { get = function(key)
            if key == "heroes" then return { roster = owned } end
        end },
        ["runtime.GameAction"] = { sendAction = function() sends = sends + 1 end },
    }
    rawset(_G, "require", function(name) return mocks[name] or nativeRequire(name) end)
    local ok, err = pcall(function()
        local AD = require("systems.AttributeDef")
        local AC = require("config.AwakeningConfig")
        local UA = require("systems.UnitAttributes")
        local HC = require("config.HeroConfig")
        local TAL = require("systems.TalentManager")
        local ETS = require("systems.ExtraTalentSystem")
        local BC = require("ui.battle.combat.BattleCombat")
        local CF = require("systems.CombatFormula")
        local SEM = require("systems.StatusEffectManager")
        local PS = require("ui.battle.combat.ProjectileSystem")
        local function hero(id, stage, stacks, shields)
            owned[id] = { awakening = awake(stage), extraTalent = ETS.normalize({
                stacks = stacks or 0, shieldStacks = shields or 0,
            }) }
            return assert(HC.createHero(id, 1, nil, awake(stage), nil,
                { litNodes = {}, silent = true }))
        end
        local function enemy(hp, armor, armorType)
            local attrs = UA.create({ [AD.MAX_HP] = hp or 1000000, [AD.ARMOR] = armor or 0 })
            attrs:fillHp(); attrs:recalc()
            local out = attrs:toBattleUnit("史诗专项敌人", 1)
            out.heroId = 0
            out.armorType = armorType or AD.ARMOR_LEATHER
            attrs.armorType = out.armorType
            return out
        end
        local function start(allies, enemies)
            ETS.mount(ETS.newState()); SEM.reset(); PS.reset()
            TAL.mount(TAL.newBattleRefs()); TAL.mountUnitStates(TAL.newUnitStates())
            TAL.onBattleStart(allies, enemies)
            BC.mount(BC.newState("epic-echo"))
            BC.setContext({ getAllies = function() return TAL.mountedState().bAllies end,
                getEnemies = function() return TAL.mountedState().bEnemies end })
        end
        local function state(unit) return TAL.mountedUnitStates()[unit] end
        local function result(crit, damage)
            return { category = "physical", isCrit = crit == true, isMiss = false,
                totalDamage = damage or 1000, atkType = AD.ATK_SLASH }
        end
        local hits = {}
        local function bound(source, after)
            return function(target, damage, targetAlly, prefix, color, meta)
                hits[#hits + 1] = { target = target, damage = damage, source = source, meta = meta, prefix = prefix }
                BC.dealTalentDamage(source, target, damage, targetAlly, prefix, color, meta)
                if after then after(target, damage, prefix, meta) end
            end
        end
        local function copyHits()
            local out = {}
            for _, h in ipairs(hits) do if h.prefix == "满分抄袭 " then out[#out + 1] = h end end
            return out
        end
        local function hit(unit, target, r, fn, list)
            TAL.onAfterAttack(unit, target, r, true, list or TAL.mountedState().bEnemies, fn or bound(unit), TAL.mountedState().bAllies)
        end

        local function readyCopy(unit)
            state(unit).stolenSpeed = 40
            state(unit).copyEchoSpeed = { token = unit._talentBattleToken, speed = 40 }
        end
        -- 14：stage/每50次暴击击杀/封顶；五次偷速、复制不重roll且不重复偷速。
        for stage = 0, 3 do
            for _, stacks in ipairs({ 0, 98, 100, 198, 200, 298, 300, 10000 }) do
                local a, target = hero(14, stage, stacks), enemy()
                start({ a }, { target }); hits = {}
                check(a._talentBattleToken ~= nil, "14开战token由正式TAL接线")
                local oldRandom, randomCalls = math.random, 0
                math.random = function(...) randomCalls = randomCalls + 1; return oldRandom(...) end
                for n = 1, 5 do
                    hit(a, target, result(true))
                    check(state(a).stolenSpeed == math.min(40, n * 8), "14旧偷速每次8最大40")
                    check(#copyHits() == (stage >= 2 and n == 5 and 1 or 0), "14第五暴击刚满40可复制")
                end
                math.random = oldRandom
                check(randomCalls == 0, "14复制不重roll，低暴击率III不触发旧超暴击")
                local copies = copyHits()
                if stage >= 2 then
                    local rate = 0.15 + math.min(0.15, math.floor(stacks / 100) * 0.05)
                    check(copies[1].damage == math.floor(1000 * rate + 0.5), "14已提交stacks/2每50击杀成长封顶30%")
                    check(copies[1].source == a and copies[1].meta.atkType == AD.ATK_SHADOW
                        and copies[1].meta.isCrit and copies[1].meta.critEligible == false
                        and copies[1].meta.instantDamage and copies[1].meta.statCategory == "magical", "14冻结主暴击与暗影meta")
                end
                hit(a, target, result(false)); hit(a, target, { category = "physical", isMiss = true, isCrit = true, totalDamage = 1000 })
                hit(a, target, { category = "healing", isCrit = true, healAmount = 100, appliedHealAmount = 100 })
                check(#copyHits() == #copies and state(a).stolenSpeed == 40, "14非暴击/miss/治疗不复制不偷速")
                check(owned[14].extraTalent.stacks == stacks, "14临时偷速及复制不进成长档")
            end
        end
        do
            local a, target = hero(14, 2, 98), enemy()
            start({ a }, { target }); readyCopy(a); hits = {}
            local dead = enemy(1); dead.hp = 0; dead._killedBy = a; dead._killedByCrit = true
            ETS.onEnemyDeath(dead, { a }, { target })
            check(ETS.mountedState().pendingGrowth[14].stacks == 2 and owned[14].extraTalent.stacks == 98,
                "14真实暴击死亡仅pending不提前入成长")
            hit(a, target, result(true))
            check(copyHits()[1].damage == 150, "14不读取pending临界成长")
            ETS.flush(); ETS.flush(); hits = {}
            check(owned[14].extraTalent.stacks == 100, "14flush幂等保留旧I每击杀2层")
            hit(a, target, result(true))
            check(copyHits()[1].damage == 200, "14flush后达到50击杀复制20%")
            a._etsDisabled = true; hits = {}; hit(a, target, result(true))
            check(#copyHits() == 0 and state(a).stolenSpeed == 40, "14显式ETS禁用仅禁止新复制不改旧偷速")
        end
        do
            local a, target = hero(14, 2, 0), enemy()
            start({ a }, { target }); hits = {}
            for n = 1, 5 do hit(a, target, result(true)) end
            local s, token = state(a), a._talentBattleToken
            check(s.stolenSpeed == 40 and #copyHits() == 1, "14首场真实第五暴击达到门槛")
            TAL.onBattleStart({ a }, { target }); hits = {}
            for n = 1, 5 do
                hit(a, target, result(true))
                check(state(a) == s and s.stolenSpeed == 40 and a._talentBattleToken ~= token,
                    "14同s重开保留旧40及modifier但新token换场")
                check(#copyHits() == (n == 5 and 1 or 0), "14旧40不借新场门槛仍须五次暴击 " .. n)
            end
        end
        -- 实例不开II但owned有II不能借账号觉醒启用复制。
        do
            local a, target = hero(14, 0, 10000), enemy()
            owned[14].awakening = awake(3)
            start({ a }, { target }); readyCopy(a); hits = {}
            hit(a, target, result(true))
            check(#copyHits() == 0, "14新II只查实例AC.hasStage不借owned")
        end
        -- 14 callback递归/同s重开/reset/mount后不再走收工旧轮。
        for _, action in ipairs({ "recursive", "restart", "reset", "mount" }) do
            local a, target = hero(14, 2, 0), enemy()
            start({ a }, { target }); local s = state(a); readyCopy(a); hits = {}
            target.hp = 200; target.attrs.final[AD.HP] = 200; target.attrs._forceFullHpOnRecalc = false
            local fn = bound(a, function(_, _, prefix)
                if prefix ~= "满分抄袭 " then return end
                if action == "recursive" then hit(a, target, result(true))
                elseif action == "restart" then TAL.onBattleStart({ a }, { target })
                elseif action == "reset" then TAL.reset()
                else TAL.mount(TAL.newBattleRefs()) end
            end)
            hit(a, target, result(true), fn, { target })
            check(#copyHits() == 1, "14回调不递归复制 " .. action)
            local finishes = 0
            for _, h in ipairs(hits) do if h.prefix == "收工 " then finishes = finishes + 1 end end
            check(finishes == (action == "recursive" and 1 or 0), "14换场回调停止旧收工，正常主攻击仍保留收工 " .. action)
            if action == "restart" then check(state(a) == s and s.epicEchoDispatch == nil, "14同s重开不擦新token状态") end
        end
        -- 死目标不给复制；复制死亡真实来源和暴击击杀归因。
        do
            local a, target = hero(14, 2, 0), enemy(100)
            start({ a }, { target }); readyCopy(a); hits = {}
            hit(a, target, result(true))
            check(target.hp == 0 and target._killedBy == a and target._killedByCrit,
                "14真实BC复制致死归因仍为主英雄且继承暴击")
            hits = {}; hit(a, target, result(true))
            check(#copyHits() == 0, "14死目标不复制")
        end

        -- 23：II30% + 每40I盾层2.5pp，上限40%；保留旧盾机制及大值max。
        for stage = 0, 3 do
            for _, stacks in ipairs({ 0, 39, 40, 79, 80, 159, 160, 10000 }) do
                local poet, ally, target = hero(23, stage, 0, stacks), hero(10, 0), enemy()
                start({ poet, ally }, { target }); hits = {}
                ally.attrs.energyShield = 100
                hit(poet, ally, { category = "healing", healAmount = 1000, appliedHealAmount = 1000 })
                local expected = stage >= 2 and math.floor(1000 * (0.30 + math.min(0.10, math.floor(stacks / 40) * 0.025)) + 0.5) or 0
                check((ally._rhymeShot or 0) == expected, "23阶段/盾成长40阈值/最高40%")
                if expected > 0 then
                    hit(poet, ally, { category = "healing", healAmount = 100, appliedHealAmount = 100 })
                    check(ally._rhymeShot == expected, "23重复小治疗不叠加不覆盖大值")
                    hit(ally, target, { category = "physical", isMiss = true })
                    hit(ally, poet, { category = "healing", healAmount = 20, appliedHealAmount = 20 })
                    check(ally._rhymeShot == expected, "23miss/治疗不消费待发")
                    hit(ally, target, result(false), bound(ally, function(_, _, prefix)
                        if prefix == "押韵 " then hit(ally, target, result(false)) end
                    end))
                    local rhyme = hits[1]
                    check(#hits == 1 and rhyme.prefix == "押韵 " and rhyme.damage == expected
                        and rhyme.source == ally and rhyme.meta.atkType == AD.ATK_HOLY
                        and rhyme.meta.critEligible == false, "23下次有效攻击仅消费一次圣伤且实际攻击者归因")
                    hit(ally, target, result(false)); check(#hits == 1 and ally._rhymeShot == nil, "23消费后不重复")
                end
                check(owned[23].extraTalent.shieldStacks == stacks, "23无溢出普通治疗不写旧shieldStacks")
            end
        end
        do
            local poet, ally, target = hero(23, 0, 0, 10000), hero(10, 0), enemy()
            owned[23].awakening = awake(2)
            start({ poet, ally }, { target }); ally.attrs.energyShield = 100
            hit(poet, ally, { category = "healing", healAmount = 1000, appliedHealAmount = 1000 })
            check(ally._rhymeShot == 200, "23旧ETS账号II路径仍20%而非借新II30%")
            ally._rhymeShot = nil; ally._rhymeShotContext = nil
            poet._etsDisabled = true
            hit(poet, ally, { category = "healing", healAmount = 1000, appliedHealAmount = 1000 })
            check(ally._rhymeShot == nil, "23显式禁用保留ETS.hasNode拒绝旧附伤")
        end
        do
            local poet, ally, target = hero(23, 2, 0, 39), hero(10, 0), enemy()
            start({ poet, ally }, { target }); ally.attrs.energyShield = 100
            ETS.onOverflowHeal(poet, 100)
            check(owned[23].extraTalent.shieldStacks == 39, "23真实溢出仍pending")
            hit(poet, ally, { category = "healing", healAmount = 1000, appliedHealAmount = 1000 })
            check(ally._rhymeShot == 300, "23待提交40层不提前增幅")
            ETS.flush(); hit(poet, ally, { category = "healing", healAmount = 1000, appliedHealAmount = 1000 })
            check(ally._rhymeShot == 325 and owned[23].extraTalent.shieldStacks == 40, "23flush后成长且max替换")
            hit(poet, ally, { category = "healing", healAmount = 2000, appliedHealAmount = 2000 })
            check(ally._rhymeShot == 650, "23更大治疗只替换不叠加")
            target.hp = 0; hit(ally, target, result(false)); check(ally._rhymeShot == 650, "23死目标不消费")
        end
        for _, action in ipairs({ "restart", "reset", "mount", "disable" }) do
            local poet, ally, target = hero(23, 2), hero(10, 0), enemy()
            start({ poet, ally }, { target }); ally.attrs.energyShield = 100
            hit(poet, ally, { category = "healing", healAmount = 1000, appliedHealAmount = 1000 })
            if action == "restart" then TAL.onBattleStart({ poet, ally }, { target })
            elseif action == "reset" then TAL.reset(); TAL.initUnit(ally)
            elseif action == "mount" then TAL.mount(TAL.newBattleRefs()); TAL.initUnit(ally)
            else poet._etsDisabled = true end
            hits = {}; hit(ally, target, result(false), nil, { target })
            check(#hits == 0 and ally._rhymeShot == nil, "23旧待发跨重开/reset/mount/禁用不发 " .. action)
        end
        do
            local poet, ally, target = hero(23, 2), hero(1, 0), enemy()
            start({ poet, ally }, { target }); ally.attrs.energyShield = 100
            hit(poet, ally, { category = "healing", healAmount = 1000, appliedHealAmount = 1000 })
            local recipientState, refs, token = state(ally), TAL.mountedState(), ally._talentBattleToken
            TAL.onBattleStart({ ally }, { target })
            hits = {}; hit(ally, target, result(false))
            check(state(ally) == recipientState and TAL.mountedState() == refs and ally._talentBattleToken ~= token,
                "23普通hero1受益者同s同refs重开也刷新token")
            check(#hits == 0 and ally._rhymeShot == nil, "23旧healer不在新队普通受益者旧待发不能跨场")
        end
        do
            local poet, ally, target = hero(23, 2), hero(10, 0), enemy()
            start({ poet, ally }, { target }); ally.attrs.energyShield = 100
            hit(poet, ally, { category = "healing", healAmount = 1000, appliedHealAmount = 1000 })
            hits = {}
            hit(ally, target, result(false), bound(ally, function(_, _, prefix)
                if prefix == "押韵 " then
                    TAL.onBattleStart({ poet, ally }, { target })
                    hit(poet, ally, { category = "healing", healAmount = 2000, appliedHealAmount = 2000 })
                end
            end))
            check(#hits == 1 and ally._rhymeShot == 600, "23伤害回调同s重开并新赋值旧消费不擦新待发")
        end

        -- 24：使用真正TAL calcTalentFixedDamage，对两目标独立粉碎/护甲/暴击公式。
        local function loading(id, stage, stacks)
            local out = hero(id, stage, stacks)
            out.attrs:addModifier("epic_test_hp", { { key = AD.MAX_HP, flat = 10000 } })
            out.maxHp = out.attrs:get(AD.MAX_HP); out.attrs:fillHp(); out.hp = out.maxHp
            return out
        end
        local function context(source, onFire, fallback)
            local function talent(attacker, target, damage, targetAlly, prefix, color, meta)
                check(attacker == source and meta.atkType == AD.ATK_CRUSH and meta.statCategory == "physical"
                    and meta.instantDamage and meta.critEligible == false and targetAlly == false, "24source/meta正式出口正确")
                hits[#hits + 1] = { source = attacker, target = target, damage = damage, meta = meta, prefix = prefix }
                BC.dealTalentDamage(attacker, target, damage, targetAlly, prefix, color, meta)
                if onFire then onFire(target, damage, prefix, meta) end
            end
            if fallback then
                return { dealDamage = function(target, damage, targetAlly, prefix, color, attacker, meta)
                    check(attacker == source and type(meta) == "table", "24七参fallback第6来源第7meta不错位")
                    talent(attacker, target, damage, targetAlly, prefix, color, meta)
                end }
            end
            return { dealTalentDamage = talent, dealDamage = function() error("不应选择24低优先级出口") end }
        end
        for stage = 0, 3 do
            for _, stacks in ipairs({ 0, 49, 50, 99, 100, 249, 250, 10000 }) do
                local a = loading(24, stage, stacks)
                local one, two = enemy(nil, 0, AD.ARMOR_LEATHER), enemy(nil, 80, AD.ARMOR_PLATE)
                start({ a }, { one, two }); hits = {}
                local s = state(a)
                local cap = math.floor(a.maxHp * (stage >= 2 and 0.14 or 0.10) + 0.5)
                -- 固定crit=0排除概率噪声，独立oracle显式套粉碎克制/护甲。
                a.attrs:addModifier("epic_no_crit", { { key = AD.CRIT_RATE, flat = -1000 } })
                s.loadingBar = cap
                TAL.update(0, { a }, { one, two }, context(a))
                local count = stage >= 2 and 2 or 1
                check(#hits == count and s.loadingBar == 0 and s.loadingIdle == 0, "24满条发主包+II副包且清零")
                check(hits[1].target == one, "24主目标仍首个活敌")
                if stage >= 2 then
                    local rate = 0.50 + math.min(0.25, math.floor(stacks / 50) * 0.05)
                    local base = math.floor(cap * rate + 0.5)
                    local armor = two.attrs:get(AD.ARMOR)
                    local pen = a.attrs:get(AD.PHYS_PEN)
                    local resistance = CF.armorToResistance(math.max(0, armor - pen))
                    local excess = math.max(0, pen - armor)
                    local penMult = 1 + (excess > 0 and (0.01 * excess) / (0.01 * excess + 1) or 0)
                    local typeMult = AD.getTypeMult(AD.ATK_CRUSH, two.attrs.armorType)
                    local bonus = 1 + (a.attrs:get(AD.DMG_BONUS) + a.attrs:get(AD.PHYS_DMG_BONUS)) / 100
                    local expected = math.floor(base * bonus * CF.getMatchupDamageMult(a.attrs, typeMult)
                        * typeMult * (1 - resistance) * penMult + 0.5)
                    check(hits[2].target == two and hits[2].damage == expected, "24每50I层成长副包独立粉碎护甲公式最高75%")
                end
                check(owned[24].extraTalent.stacks == stacks, "24副包临时量不入成长档")
                hits = {}; s.loadingBar = cap - 1; s.loadingIdle = (stage == 3 and 4 or 6) - 0.1
                TAL.update(0.2, { a }, { one, two }, context(a))
                check(#hits == 1, "24idle非满条仅主包，III旧4秒保留")
            end
        end
        for _, callbackSwap in ipairs({ false, true }) do
            local a = loading(24, 2, 0)
            local oldDead, one, two, replacement = enemy(1), enemy(), enemy(), enemy()
            start({ a }, { oldDead }); oldDead.hp = 0
            hits = {}; state(a).loadingBar = math.floor(a.maxHp * 0.14 + 0.5)
            local incoming = { one, two }
            -- 真实兼容副本形态：refs仍旧全死表，但本轮update实参已经换成新敌人。
            TAL.update(0, { a }, incoming, context(a, function(_, _, prefix)
                if callbackSwap and prefix == "缓冲 " then TAL.mountedState().bEnemies = { replacement } end
            end))
            check(#hits == 2 and hits[1].target == one and hits[2].target == (callbackSwap and replacement or two),
                "24旧refs全死不吞新实参满条释放，回调可再换表 " .. tostring(callbackSwap))
            check(state(a).loadingBar == 0, "24兼容换表满条正常消费")
        end
        for _, fallback in ipairs({ false, true }) do
            local a = loading(24, 2, 0); local target = enemy()
            start({ a }, { target, target, enemy(1) }); TAL.mountedState().bEnemies[3].hp = 0
            hits = {}; state(a).loadingBar = math.floor(a.maxHp * 0.14 + 0.5)
            TAL.update(0, { a }, { target, target }, context(a, nil, fallback))
            check(#hits == 1 and hits[1].source == a, "24无另一不同活人不回打主目标两出口")
        end
        do
            local a = loading(24, 2, 49); local one, two = enemy(), enemy()
            start({ a }, { one, two })
            local dead = enemy(1); dead.hp = 0; dead._killedBy = a
            ETS.onEnemyDeath(dead, { a }, { one, two }); hits = {}
            local cap = math.floor(a.maxHp * 0.14 + 0.5)
            state(a).loadingBar = cap
            TAL.update(0, { a }, { one, two }, context(a))
            local before = hits[2].damage
            ETS.flush(); hits = {}; state(a).loadingBar = cap
            TAL.update(0, { a }, { one, two }, context(a))
            check(owned[24].extraTalent.stacks == 50 and hits[2].damage > before, "24pending49+1只在flush后提升50%到55%")
            a._etsDisabled = true; hits = {}; state(a).loadingBar = cap
            TAL.update(0, { a }, { one, two }, context(a))
            check(#hits == 1, "24显式禁用保留旧主包不发II副包")
        end
        for _, action in ipairs({ "swap", "killOther", "restart", "reset", "mount", "killSelf", "recursive", "disable" }) do
            local a = loading(24, 2, 0); local one, two, replacement = enemy(), enemy(), enemy()
            start({ a }, { one, two }); local s = state(a); hits = {}
            local cap = math.floor(a.maxHp * 0.14 + 0.5); s.loadingBar = cap
            local ctx = context(a, function(_, _, prefix)
                if prefix ~= "缓冲 " then return end
                if action == "swap" then TAL.mountedState().bEnemies = { one, replacement }
                elseif action == "killOther" then two.hp = 0
                elseif action == "restart" then TAL.onBattleStart({ a }, { one, two }); s.loadingBar = 123
                elseif action == "reset" then TAL.reset()
                elseif action == "mount" then TAL.mount(TAL.newBattleRefs())
                elseif action == "killSelf" then a.hp = 0
                elseif action == "disable" then a._etsDisabled = true
                else s.loadingBar = cap; TAL.update(0, { a }, { one, two }, context(a)); s.loadingBar = 123 end
            end)
            TAL.update(0, { a }, { one, two }, ctx)
            local count = (action == "swap" or action == "recursive") and 2 or 1
            check(#hits == count, "24回调换表/死人/reset/同s重开/重入限制 " .. action)
            if action == "swap" then check(hits[2].target == replacement, "24同场换表副包使用新活敌") end
            if action == "restart" or action == "recursive" then check(s.loadingBar == 123, "24不擦回调的新条 " .. action) end
        end
        -- 实例0但ownedII不发新副包；主包/副包实际crit由各目标独立公式返回。
        do
            local a = loading(24, 0, 10000); local one, two = enemy(), enemy()
            owned[24].awakening = awake(3)
            start({ a }, { one, two }); hits = {}; state(a).loadingBar = math.floor(a.maxHp * 0.10 + 0.5)
            TAL.update(0, { a }, { one, two }, context(a))
            check(#hits == 1, "24新II只读实例不借owned觉醒")
        end
        do
            local a = loading(24, 2, 0); local one, two = enemy(), enemy()
            start({ a }, { one, two }); hits = {}; state(a).loadingBar = math.floor(a.maxHp * 0.14 + 0.5)
            local oldRoll, rolls = CF.rollCrit, 0
            CF.rollCrit = function() rolls = rolls + 1; return rolls == 1, rolls == 1 and 2 or 1 end
            TAL.update(0, { a }, { one, two }, context(a))
            CF.rollCrit = oldRoll
            check(rolls == 2 and hits[1].meta.isCrit and not hits[2].meta.isCrit, "24两目标各calc一次保留各自暴击meta")
        end
        -- 真实受伤蓄条与当前cap变化；主/副包各自致死均正确敌侧来源。
        do
            local a = loading(24, 2, 0); local one, two = enemy(1), enemy(1)
            start({ a }, { one, two }); hits = {}
            local cap = math.floor(a.maxHp * 0.14 + 0.5)
            TAL.onDamageTaken(a, one, math.ceil(cap / 0.35), true, result(false))
            check(state(a).loadingBar == cap, "24真实TAL.onDamageTaken I35%蓄条至II14%cap")
            TAL.update(0, { a }, { one, two }, context(a, nil, true))
            check(#hits == 2 and one.hp == 0 and two.hp == 0 and one._killedBy == a and two._killedBy == a,
                "24正式七参主副包都敌侧致死归因")
            check(ETS.mountedState().pendingGrowth[24].stacks == 2, "24两名真实死亡各+1旧I成长，不按包额外入账")
            ETS.flush(); check(owned[24].extraTalent.stacks == 2, "24击杀成长flush保留")
        end
        do
            local a = loading(24, 2, 0); local one, two = enemy(), enemy()
            start({ a }, { one, two }); hits = {}
            state(a).loadingBar = math.floor(a.maxHp * 0.14 + 0.5)
            a.maxHp = a.maxHp * 2
            TAL.update(0, { a }, { one, two }, context(a))
            check(#hits == 0 and state(a).loadingBar > 0, "24旧cap曾满但当前cap变大不发并行")
            TAL.update(6.1, { a }, { one, two }, context(a))
            check(#hits == 1, "24当前cap不足后idle仍仅主包")
        end
        for _, id in ipairs({ 14, 23, 24 }) do
            for _, explicit in ipairs({ 0, 10000 }) do
                local account = explicit == 0 and 10000 or 0
                hero(id, 2, account, account)
                local extra = ETS.normalize({ stacks = explicit, shieldStacks = explicit })
                local a = assert(HC.createHero(id, 1, nil, awake(2), extra, { litNodes = {}, silent = true }))
                local one, two = enemy(), enemy()
                local allies = { a }
                local recipient = hero(1, 0)
                if id == 23 then allies[#allies + 1] = recipient end
                start(allies, { one, two }); hits = {}
                check(ETS.getEpicGrowth(a).stacks == explicit and ETS.getEpicGrowth(a).shieldStacks == explicit,
                    "显式成长实例与owned分离 id=" .. id)
                extra.stacks, extra.shieldStacks = 999999, 999999
                check(ETS.getEpicGrowth(a).stacks == explicit, "显式extra快照不与调用者table共用 id=" .. id)
                if id == 14 then
                    readyCopy(a); hit(a, one, result(true))
                    check(copyHits()[1].damage == (explicit == 0 and 150 or 300), "14显式实例成长而非owned抄袭倍率")
                elseif id == 23 then
                    recipient.attrs.energyShield = 100
                    hit(a, recipient, { category = "healing", healAmount = 1000, appliedHealAmount = 1000 })
                    check(recipient._rhymeShot == (explicit == 0 and 300 or 400), "23显式实例护盾本金而非owned")
                else
                    state(a).loadingBar = math.floor(a.maxHp * 0.14 + 0.5)
                    a.attrs:addModifier("epic_explicit_no_crit", { { key = AD.CRIT_RATE, flat = -1000 } })
                    TAL.update(0, { a }, { one, two }, context(a))
                    local cap = math.floor(a.maxHp * 0.14 + 0.5)
                    local base = math.floor(cap * (explicit == 0 and 0.5 or 0.75) + 0.5)
                    local mult = AD.getTypeMult(AD.ATK_CRUSH, two.attrs.armorType)
                    local excess = math.max(0, a.attrs:get(AD.PHYS_PEN))
                    local pen = 1 + (excess > 0 and (0.01 * excess) / (0.01 * excess + 1) or 0)
                    local damage = math.floor(base * (1 + (a.attrs:get(AD.DMG_BONUS) + a.attrs:get(AD.PHYS_DMG_BONUS)) / 100)
                        * CF.getMatchupDamageMult(a.attrs, mult) * mult * pen + 0.5)
                    check(hits[2].damage == damage, "24显式实例并行倍率而非owned")
                end
                check(owned[id].extraTalent.stacks == account, "显式新联动不写owned成长 id=" .. id)
            end
        end
        check(storageCalls == 0, "四存储接口全程调用0，不读玩家档")
        check(owned[14].extraTalent.stolenSpeed == nil and owned[23].extraTalent.rhymeShot == nil
            and owned[24].extraTalent.loadingBar == nil, "三种临时量未落入owned.extraTalent")
        print("[EpicEcho] assertions=" .. checks .. " failures=" .. failures .. " FileFS=" .. storageCalls .. " actionMock=" .. sends)
    end)
    rawset(_G, "require", nativeRequire)
    rawset(_G, "File", nativeFile); rawset(_G, "FileSystem", nativeFS)
    rawset(_G, "fileSystem", nativeFs); rawset(_G, "GetFileSystem", nativeGetFS)
    if not ok then failures = failures + 1; print("[EpicEcho][HARNESS_FAIL] " .. tostring(err)) end
    if ok and failures == 0 then print("[EpicEcho] ALL PASS") else print("[EpicEcho] FAILED " .. failures) end
    engine:Exit()
end
