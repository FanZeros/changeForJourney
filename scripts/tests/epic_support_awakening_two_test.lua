-- 史诗支持共鸣专项：真实TAL/ETS/属性/扣血链；仅内存owned，不访问玩家File/FS。
local assertions, failures = 0, 0
local function check(value, message)
    assertions = assertions + 1
    if not value then failures = failures + 1; print("[史诗支持II][FAIL] " .. message) end
end
local function awake(stage)
    local out = { _awk3Migrated = true }
    for i = 1, stage do out[i] = true end
    return out
end

function Start()
    local originalRequire = require
    local oldFile, oldFS, oldFs, oldGetFS = File, FileSystem, fileSystem, GetFileSystem
    local oldRandom = math.random
    local storageCalls, patches, sends = 0, 0, 0
    local function denyStorage()
        storageCalls = storageCalls + 1
        error("史诗支持专项禁止File/FS存储")
    end
    rawset(_G, "File", denyStorage)
    rawset(_G, "FileSystem", denyStorage)
    rawset(_G, "fileSystem", setmetatable({}, { __index = function() return denyStorage end }))
    rawset(_G, "GetFileSystem", denyStorage)
    local owned = {}
    local patchHook = function() end
    local cp = {
        getOwnedHero = function(id) return owned[id] end,
        patchExtraTalent = function(id, extra)
            patches = patches + 1
            owned[id].extraTalent = extra
            patchHook(id)
        end,
        finishExtraTalentBatch = function() end,
    }
    local mocks = {
        ["ui.character.panel.CharacterPanel"] = cp,
        ["runtime.ClientDispatcher"] = { get = function(key) if key == "heroes" then return { roster = owned } end end },
        ["runtime.GameAction"] = { sendAction = function() sends = sends + 1 end },
    }
    rawset(_G, "require", function(name) return mocks[name] or originalRequire(name) end)
    local ok, err = pcall(function()
        local AD = require("systems.AttributeDef")
        local AC = require("config.AwakeningConfig")
        local UA = require("systems.UnitAttributes")
        local HC = require("config.HeroConfig")
        local ETS = require("systems.ExtraTalentSystem")
        local TAL = require("systems.TalentManager")
        local BC = require("ui.battle.combat.BattleCombat")
        local SEM = require("systems.StatusEffectManager")
        local ART = require("systems.ArtifactRuntime")
        local CF = require("systems.CombatFormula")
        local BS = require("systems.BattleStats")
        local function hero(id, stage, extra)
            owned[id] = { awakening = awake(stage), extraTalent = ETS.normalize(extra) }
            return assert(HC.createHero(id, 1, nil, awake(stage), owned[id].extraTalent,
                { litNodes = {}, silent = true }))
        end
        local function enemy(hp, armorType, armor)
            local attrs = UA.create({ [AD.MAX_HP] = hp or 1000000, [AD.ARMOR] = armor or 0 })
            attrs.armorType = armorType or AD.ARMOR_LEATHER
            attrs:fillHp(); attrs:recalc()
            local u = attrs:toBattleUnit("支持专项敌人", 1)
            u.heroId = 0
            return u
        end
        local function setHp(u, hp)
            u.hp, u.attrs.final[AD.HP] = hp, hp
        end
        local function sync(u) if u.attrs then u.hp = u.attrs:get(AD.HP) end end
        local function mount(refs, units, extra, sem)
            TAL.mount(refs); TAL.mountUnitStates(units); ETS.mount(extra); SEM.mount(sem or SEM.newSemState())
        end
        local function fresh(allies, enemies)
            mount(TAL.newBattleRefs(), TAL.newUnitStates(), ETS.newState())
            ART.reset(allies); BC.reset(); BS.reset()
            TAL.onBattleStart(allies, enemies)
            BC.setContext({ getAllies = function() return allies end, getEnemies = function() return enemies end })
            return TAL.mountedUnitStates(), ETS.mountedState()
        end
        local function update(dt, allies, enemies, deal)
            TAL.update(dt, allies, enemies, { dealDamage = deal or BC.dealDamageToUnit })
        end
        local function noArmor(u)
            u.attrs.final[AD.ARMOR] = 0
            u.attrs.final[AD.PHYS_BLOCK_RATE], u.attrs.final[AD.MAG_BLOCK_RATE] = 0, 0
            u.attrs.energyShield, u.attrs.tempEnergyShield = 0, 0
        end
        local function growthCopy(id)
            local x = ETS.getOwned(id)
            return { stacks = x.stacks, shareCount = x.shareCount, issuedCards = x.issuedCards, iceStatues = x.iceStatues }
        end
        local function sameGrowth(id, old, message)
            local x = ETS.getOwned(id)
            check(x.stacks == old.stacks and x.shareCount == old.shareCount and x.issuedCards == old.issuedCards,
                message)
        end

        print("[史诗支持II] 门板：阶段、成长、真实分摊、致死、冷却及独立护盾")
        for stage = 0, 3 do
            for _, count in ipairs({ 0, 1, 15, 16, 10000 }) do
                local tank, protected = hero(10, stage, { shareCount = count }), hero(1, 0)
                local foe = enemy()
                local allies, enemies = { tank, protected }, { foe }
                local states, state = fresh(allies, enemies)
                noArmor(tank); setHp(tank, math.floor(tank.maxHp * 0.7))
                tank.shield = { amount = 77, timer = 20 }
                tank.attrs.energyShield, tank.attrs.tempEnergyShield = 0, 0
                local before = growthCopy(10)
                state.pendingGrowth[10] = { shareCount = 10000 }
                local rem = TAL.modifyDamageForTarget(protected, 20, true, sync, "physical")
                check(rem == (stage >= 2 and 16 or 17), "分摊旧比例保留stage=" .. stage)
                local ward = tank._etsBulwarkWard
                local expected = math.floor(tank.maxHp * math.min(.08, .04 + count * .0025) + .5)
                check((ward ~= nil) == (stage >= 2), "门板余护仅共鸣继承stage=" .. stage)
                if stage >= 2 then
                    check(ward.amount == expected and ward.timer == 3, "门板只读已提交shareCount/封顶8%")
                    local first = ward
                    TAL.modifyDamageForTarget(protected, 20, true, sync, "physical")
                    check(tank._etsBulwarkWard == first and states[tank].bulwarkHealCd == 3,
                        "旧3秒CD内不新建或刷新余护")
                    local left = tank._etsBulwarkWard and tank._etsBulwarkWard.amount or 0
                    ETS.refreshBulwarkWard(tank)
                    check(tank._etsBulwarkWard ~= first and tank._etsBulwarkWard.amount == expected
                        and tank._etsBulwarkWard.amount <= left + expected, "余护刷新不叠加")
                    local hp = tank.hp
                    local take = TAL.modifyDamageForTarget(tank, expected + 9, true, sync, "physical")
                    check(take == 9 and tank._etsBulwarkWard == nil and tank.hp == hp,
                        "自身普通伤害扣血前消费余护无HP回补")
                    tank.attrs:takeDamage(take); sync(tank)
                    check(tank.hp == hp - 9, "自身真实扣血只吃剩余9")
                end
                check(tank.shield.amount == 77 and tank.shield.timer == 20, "余护不覆写/消费复活盾")
                sameGrowth(10, before, "门板余护不修改永久成长")
                state.pendingGrowth = {}
                update(3, allies, enemies)
                check(tank._etsBulwarkWard == nil and tank.shield and tank.shield.timer == 17,
                    "余护独立3秒过期，旧盾仅自己的计时")
            end
        end
        do
            local tank, protected = hero(10, 2, { shareCount = 16 }), hero(1, 0)
            local allies, enemies = { tank, protected }, { enemy() }
            local states = fresh(allies, enemies)
            noArmor(tank); setHp(tank, 1)
            TAL.modifyDamageForTarget(protected, 1000, true, sync, "physical")
            check(tank.hp == 0 and not tank._etsBulwarkWard and states[tank].bulwarkHealCd == 0,
                "分摊致死不能靠新盾复活或起回血CD")
            check(ETS.mountedState().pendingGrowth[10].shareCount == 1, "原分摊致死成长只增一次pending")
            local copy = growthCopy(10)
            check(not ETS.refreshBulwarkWard(tank) and ETS.absorbBulwarkWard(tank, 5) == 5 and tank.hp == 0,
                "死后refresh/consume都不恢复HP")
            sameGrowth(10, copy, "门板增益本身不额外成长")
        end
        do
            local tank, protected = hero(10, 2), hero(1, 0)
            local allies, enemies = { tank, protected }, { enemy() }
            fresh(allies, enemies); noArmor(tank)
            setHp(tank, math.floor(tank.maxHp / 2)); tank.attrs.artifactNoHeal = true
            TAL.modifyDamageForTarget(protected, 20, true, sync, "physical")
            check(not tank._etsBulwarkWard, "原分摊回血被禁疗拒绝不生成余护")
            tank.attrs.artifactNoHeal = nil
            ETS.refreshBulwarkWard(tank)
            local ward, hp = tank._etsBulwarkWard, tank.hp
            check(ETS.absorbBulwarkWard(tank, 0) == 0 and tank._etsBulwarkWard == ward, "零伤不消费/刷新罩")
            check(ETS.absorbBulwarkWard(tank, -4) == -4 and ward.amount > 0, "负伤原值返回不消费")
            tank._etsDisabled = true
            check(ETS.absorbBulwarkWard(tank, 9) == 9 and not ETS.refreshBulwarkWard(tank), "_etsDisabled关闭新增罩")
            tank._etsDisabled = nil
            local amount = ward.amount
            -- 保留真实六契门缝，只将其填满隔离本次独立罩顺序，不能把门缝吸伤算新罩失败。
            tank._gateStored = tank._gateCap
            tank.shield = { amount = 61, timer = 10 }
            tank.attrs.energyShield, tank.attrs.tempEnergyShield = 50, 40
            local actual = BC.dealDamageToUnit(tank, amount + 6, true, "专项", {}, nil, { noCounter = true })
            check(actual == 0 and tank.hp == hp and tank._etsBulwarkWard == nil
                and tank.attrs.tempEnergyShield == 34 and tank.attrs.energyShield == 50 and tank.shield.amount == 61,
                "BC额伤入口罩优先，余伤再耗能量盾，复活盾不变")
            tank.attrs.energyShield, tank.attrs.tempEnergyShield = 0, 0
            ETS.refreshBulwarkWard(tank)
            amount = tank._etsBulwarkWard.amount
            actual = BC.dealDamageToUnit(tank, amount + 7, true, "专项", {}, nil, { noCounter = true })
            check(actual == 7 and tank.hp == hp - 7 and not tank._etsBulwarkWard, "BC直伤真实消费罩且无双扣")
            tank.shield.timer = .5
            ETS.refreshBulwarkWard(tank)
            update(.6, allies, enemies)
            check(not tank.shield and tank._etsBulwarkWard and tank._etsBulwarkWard.timer == 2.4,
                "旧盾先过期不影响余护")
            TAL.onBattleStart(allies, enemies)
            check(not tank._etsBulwarkWard, "同units/同state重开清旧罩")
            ETS.refreshBulwarkWard(tank); tank._talentBattleToken = {}
            check(ETS.absorbBulwarkWard(tank, 10) == 10 and not tank._etsBulwarkWard, "开战单位token变更作废旧罩")
        end

        print("[史诗支持II] 冰雕：真实固定公式/暴击/元素/护甲、三目标及回调取消")
        for stage = 0, 3 do
            for _, count in ipairs({ 0, 49, 50, 99, 100, 199, 200, 10000 }) do
                local snow, protected = hero(12, stage, { stacks = count, iceStatues = 1 }), hero(1, 0)
                local group = { enemy(), enemy(nil, AD.ARMOR_PLATE, 150), enemy(nil, AD.ARMOR_CLOTH, 0), enemy() }
                group[#group + 1] = group[1]
                local dead = enemy(); setHp(dead, 0); table.insert(group, 1, dead)
                local allies = { snow, protected }
                local _, state = fresh(allies, group)
                snow.attrs:addModifier("testCrit", { { key = AD.CRIT_RATE, flat = 100 }, { key = AD.CRIT_DMG, flat = 70 },
                    { key = AD.MAG_DMG_BONUS, flat = 13 }, { key = AD.DMG_BONUS, flat = 7 } })
                snow.attrs.final[AD.MAG_PEN] = 0
                local growth = growthCopy(12)
                state.pendingGrowth[12] = { stacks = 100000 }
                local hits, originals, values = 0, {}, {}
                for _, e in ipairs(group) do originals[e] = e.hp end
                update(0, allies, group, function(target, value, side, prefix, color, source, meta)
                    hits = hits + 1
                    check(source == snow and not side and meta.atkType == AD.ATK_ICE and meta.isCrit
                        and meta.critEligible and meta.category == "magical", "冰雕七参source及暴击元素metadata")
                    check(#state.iceStatues == 0 and owned[12].extraTalent.iceStatues == 0,
                        "伤害回调前先消费雕及已提交库存")
                    local ratio = .8 * (1 + math.min(.4, math.floor(count / 50) * .1))
                    local typeMult = AD.getTypeMult(AD.ATK_ICE, target.attrs.armorType)
                    local armor = target.attrs:get(AD.ARMOR)
                    local expected = snow.attrs:get(AD.MAG_ATK) * snow.attrs.atkCoeff * ratio
                    expected = expected * (1 + (snow.attrs:get(AD.DMG_BONUS) + snow.attrs:get(AD.MAG_DMG_BONUS)) / 100)
                    local matchup = typeMult > 1 and snow.attrs:get(AD.ADVANTAGE_DMG_BONUS)
                        or (typeMult < 1 and snow.attrs:get(AD.DISADVANTAGE_DMG_BONUS) or 0)
                    expected = expected * (1 + matchup / 100) * typeMult * (1 - CF.armorToResistance(armor))
                        * ((snow.attrs:get(AD.CRIT_DMG) + snow.attrs:get(AD.MAG_CRIT_DMG)) / 100)
                    expected = math.max(1, math.floor(expected + .5))
                    check(value == expected, "独立冰伤oracle：80%基础、50层10%乘成长最高112%"
                        .. string.format(" stage=%d count=%d type=%s armor=%.2f value=%.2f expected=%.2f", stage, count,
                            tostring(target.attrs.armorType), armor, value, expected))
                    values[target] = value
                    return BC.dealDamageToUnit(target, value, side, prefix, color, source, meta)
                end)
                local rem = TAL.modifyDamageForTarget(protected, 37, true, sync, "physical")
                check(rem == (stage >= 2 and 0 or 37) and hits == (stage >= 2 and 3 or 0),
                    "阶段0/I无雕/新增，II/III三名不同活敌碎裂")
                for target, value in pairs(values) do
                    check(originals[target] - target.hp == value, "真实BC伤害与公式值一致不重复护甲")
                end
                if stage >= 2 then
                    for i = 2, 5 do check(SEM.has(group[i], SEM.FROZEN), "原全场冻结保留含第四活敌") end
                end
                sameGrowth(12, growth, "碎裂不写成长或pending")
                check(state.pendingGrowth[12].stacks == 100000, "未读取/改写冰雕pending成长")
                state.pendingGrowth = {}
            end
        end
        for _, action in ipairs({ "restart", "mountETS", "mountTAL", "states", "sourceToken", "enemyRefs" }) do
            local snow, protected = hero(12, 2, { iceStatues = 1 }), hero(1, 0)
            local allies, group = { snow, protected }, { enemy(), enemy(), enemy(), enemy() }
            local states, state = fresh(allies, group)
            local hits = 0
            update(0, allies, group, function()
                hits = hits + 1
                if action == "restart" then TAL.onBattleStart(allies, group)
                elseif action == "mountETS" then ETS.mount(ETS.newState())
                elseif action == "mountTAL" then TAL.mount(TAL.newBattleRefs())
                elseif action == "states" then TAL.mountUnitStates(TAL.newUnitStates())
                elseif action == "sourceToken" then snow._talentBattleToken = {}
                else TAL.mountedState().bEnemies = {} end
            end)
            check(TAL.modifyDamageForTarget(protected, 37, true, sync, "physical") == 0 and hits == 1,
                "冰雕首包回调取消旧循环：" .. action)
            check(owned[12].extraTalent.iceStatues == 0, "回调取消不回填已消费雕")
            check(states[snow] ~= nil and state.pendingGrowth[12] == nil, "回调不新增成长或造新state")
        end
        do
            local snow, protected = hero(12, 3, { iceStatues = 1 }), hero(1, 0)
            local allies, group = { snow, protected }, { enemy(), enemy() }
            fresh(allies, group); snow._etsDisabled = true
            local hits = 0
            update(0, allies, group, function() hits = hits + 1 end)
            check(TAL.modifyDamageForTarget(protected, 37, true, sync, "physical") == 37
                and hits == 0 and owned[12].extraTalent.iceStatues == 1, "disabled冰雕不挡伤/消耗/爆裂")
            snow._etsDisabled = nil
            check(TAL.modifyDamageForTarget(protected, 0, true, sync, "physical") == 0
                and owned[12].extraTalent.iceStatues == 1, "零伤不消耗冰雕")
        end

        -- 首个敌击发生在TAL.update前：refs没有缓存出口也必须碎裂并归因真实source。
        do
            local snow = hero(12, 2, { iceStatues = 1, stacks = 50 })
            local foe, spare = enemy(), enemy()
            foe.heroId = 90
            foe.attrs.atkType = AD.ATK_SLASH
            foe.atkType = AD.ATK_SLASH
            foe.attrs.final[AD.PHYS_ATK], foe.attrs.final[AD.HIT_VALUE] = 30, 10000
            foe.attrs.final[AD.CRIT_RATE], foe.attrs.final[AD.COMBO_RATE] = 0, 0
            foe.attrs.dmgSpread = 0
            local allies, group = { snow }, { foe, spare }
            fresh(allies, group)
            check(TAL.mountedState().dealDamage == nil, "冷开场尚无TAL.update缓存出口")
            local hp1, hp2, hpSnow = foe.hp, spare.hp, snow.hp
            BC.performAttack(foe, allies, false)
            check(#ETS.getIceStatues() == 0 and snow.hp == hpSnow and foe.hp < hp1 and spare.hp < hp2,
                "真实BC首个敌擊抵挡并立即碎裂，不依赖先update")
            check(SEM.has(foe, SEM.FROZEN) and SEM.has(spare, SEM.FROZEN), "首击旧全场冻结保留")
            check(TAL.mountedState().dealDamage == nil, "首击可选出口没有写TAL全局缓存")
        end

        print("[史诗支持II] 复活：旧必救援、25%-40%盾、票幂等、成长及III路线")
        for stage = 0, 3 do
            for _, count in ipairs({ 0, 1, 29, 30, 10000 }) do
                local lover, rescued = hero(15, stage, { stacks = count }), hero(1, 0)
                local allies, group = { lover, rescued }, { enemy() }
                local states, state = fresh(allies, group)
                setHp(rescued, 0)
                local old = growthCopy(15)
                state.pendingGrowth[15] = { stacks = 100000 }
                math.random = function() return 0 end
                local syncCalls = 0
                local result = TAL.onAllyDeath(rescued, allies, function(u) syncCalls = syncCalls + 1; sync(u) end)
                math.random = oldRandom
                check(result and rescued.hp == rescued.maxHp and syncCalls == 1, "正常复活真实fill/sync")
                if stage >= 2 then
                    local expected = math.floor(rescued.maxHp * (.25 + math.min(.15, count * .005)) + .5)
                    check(rescued.shield.amount == expected and rescued.shield.timer == 5, "旧20%+5%+I成长最多总40%")
                    check(owned[15].extraTalent.tickets["1"] == true, "正常复活原发票保留")
                else check(not rescued.shield, "0/I不新增复活盾") end
                check(owned[15].extraTalent.stacks == old.stacks and owned[15].extraTalent.issuedCards == old.issuedCards,
                    "正常复活不提前提交永久成长")
                check((state.pendingGrowth[15].stacks or 0) == (stage >= 1 and 100001 or 100000),
                    "正常复活只走原一次成长，不为新盾加成长")
                check(not TAL.onAllyDeath(rescued, allies, sync) and states[lover].reviveUsed[rescued],
                    "活单位重复回调不二次正常复活")
                state.pendingGrowth = {}
                if stage >= 2 then
                    setHp(rescued, 0)
                    local beforePatch, oldGrowth = patches, growthCopy(15)
                    local recursion = true
                    check(TAL.onAllyDeath(rescued, allies, function(u)
                        sync(u); recursion = TAL.onAllyDeath(u, allies, sync)
                    end), "预存票救援成功")
                    check(not recursion and patches == beforePatch + 1 and not owned[15].extraTalent.tickets["1"],
                        "票在sync前消费，重复回调不再消费/发票")
                    check(rescued.shield.amount == math.floor(rescued.maxHp * (.25 + math.min(.15, count * .005)) + .5)
                        and rescued.shield.timer == 5, "票救援共用完整共鸣盾")
                    sameGrowth(15, oldGrowth, "票救援不改成长/issuedCards")
                    check(not state.pendingGrowth[15], "票救援没有pending成长")
                    setHp(rescued, 0)
                    check(not ETS.tryTicketRevive(rescued, allies, sync), "同票只能用一次")
                end
            end
        end
        do
            local lover, rescued = hero(15, 2), hero(1, 0)
            local allies, group = { lover, rescued }, { enemy() }
            fresh(allies, group); setHp(rescued, 0)
            math.random = function() return .99 end
            check(TAL.onAllyDeath(rescued, allies, sync), "保II真实必复活，不因旧正文60%降回概率")
            math.random = oldRandom
            local oldGrowth = growthCopy(15)
            lover._etsDisabled = true
            setHp(rescued, 0)
            check(not ETS.tryTicketRevive(rescued, allies, sync), "disabled不消耗票")
            setHp(rescued, rescued.maxHp); rescued.shield = { amount = 9, timer = 1 }
            check(not ETS.applyLoverReviveShield(lover, rescued) and rescued.shield.amount == 9,
                "disabled helper不刷新旧盾")
            sameGrowth(15, oldGrowth, "disabled不加成长")
        end
        for stage = 2, 3 do
            local lover = hero(15, stage, { stacks = 30, tickets = {}, issuedCards = 0 })
            local ally = hero(1, 0)
            local allies, group = { lover, ally }, { enemy() }
            fresh(allies, group); setHp(lover, 0)
            setHp(ally, math.floor(ally.maxHp / 2))
            local hp = ally.hp
            check(TAL.onAllyDeath(lover, allies, sync) == (stage == 3), "III自复活原路线不向II扩展")
            if stage == 3 then
                check(lover.hp == lover.maxHp and not lover.shield, "III自身复活不获额外共鸣盾")
                check(ally.hp > hp, "III原全队20%治疗保留")
                setHp(lover, 0)
                check(not TAL.onAllyDeath(lover, allies, sync), "III自身首次复活仍单次")
            end
        end
        for _, action in ipairs({ "restart", "mount", "states" }) do
            local lover, rescued = hero(15, 2, { stacks = 30, tickets = { ["1"] = true } }), hero(1, 0)
            local allies, group = { lover, rescued }, { enemy() }
            fresh(allies, group); setHp(rescued, 0)
            local calls = 0
            patchHook = function(id)
                if id == 15 then
                    if action == "restart" then TAL.onBattleStart(allies, group); setHp(rescued, 3)
                    elseif action == "mount" then ETS.mount(ETS.newState())
                    else TAL.mountUnitStates(TAL.newUnitStates()) end
                end
            end
            check(TAL.onAllyDeath(rescued, allies, function() calls = calls + 1 end), "票回调切场终止旧处理")
            patchHook = function() end
            check(calls == 0 and not rescued.shield and not owned[15].extraTalent.tickets["1"],
                "patch回调新场不被旧票填血/发盾/sync：" .. action)
            check(rescued.hp == (action == "restart" and 3 or 0), "旧票不改回调新血量")
        end

        print("[史诗支持II] 显式实例成长与省略owned读取互不串线")
        for _, id in ipairs({ 10, 12, 15 }) do
            for _, reverse in ipairs({ false, true }) do
                local initial = reverse and 200 or 0
                local other = reverse and 0 or 10000
                local unit = hero(id, 2, { stacks = initial, shareCount = initial, iceStatues = 1 })
                check(type(unit._epicAwakeningGrowth) == "table", "HC保留显式史诗实例成长")
                owned[id].extraTalent = ETS.normalize({ stacks = other, shareCount = other, iceStatues = 1 })
                local copy = ETS.getEpicGrowth(unit)
                check(copy.stacks == initial and copy.shareCount == initial, "显式实例不用反向owned值hero=" .. id)
                copy.stacks = 99
                check(ETS.getEpicGrowth(unit).stacks == initial, "成长getter返回独立复制")
                if id == 10 then
                    fresh({ unit }, {}); ETS.refreshBulwarkWard(unit)
                    check(unit._etsBulwarkWard.amount == math.floor(unit.maxHp * math.min(.08, .04 + initial * .0025) + .5),
                        "门板使用显式实例shareCount")
                elseif id == 15 then
                    local rescued = hero(1, 0)
                    fresh({ unit, rescued }, {})
                    check(ETS.applyLoverReviveShield(unit, rescued)
                        and rescued.shield.amount == math.floor(rescued.maxHp * (.25 + math.min(.15, initial * .005)) + .5),
                        "复活盾使用显式实例stacks")
                else
                    local protected, target = hero(1, 0), enemy()
                    local allies, group = { unit, protected }, { target }
                    fresh(allies, group)
                    local values = {}
                    update(0, allies, group, function(_, value) values[#values + 1] = value end)
                    TAL.modifyDamageForTarget(protected, 4, true, sync, "physical")
                    check(#values == 1, "显式冰雕爆裂一次")
                    local scaled = unit.attrs:get(AD.MAG_ATK) * unit.attrs.atkCoeff * .8
                        * (1 + math.min(.4, math.floor(initial / 50) * .1))
                    local oldRate = unit.attrs.final[AD.CRIT_RATE]
                    -- 使用确定性无暴击再次比较，只改专项单位的暴击属性。
                    unit.attrs.final[AD.CRIT_RATE], unit.attrs.final[AD.MAG_CRIT_RATE] = 0, 0
                    owned[12].extraTalent.iceStatues = 1
                    fresh(allies, group); values = {}
                    update(0, allies, group, function(_, value) values[#values + 1] = value end)
                    TAL.modifyDamageForTarget(protected, 4, true, sync, "physical")
                    local typeMult = AD.getTypeMult(AD.ATK_ICE, target.attrs.armorType)
                    local matchup = typeMult > 1 and unit.attrs:get(AD.ADVANTAGE_DMG_BONUS)
                        or (typeMult < 1 and unit.attrs:get(AD.DISADVANTAGE_DMG_BONUS) or 0)
                    local raw = scaled * (1 + (unit.attrs:get(AD.DMG_BONUS) + unit.attrs:get(AD.MAG_DMG_BONUS)) / 100)
                        * typeMult * (1 + matchup / 100)
                    check(values[1] == math.max(1, math.floor(raw + .5)), "冰雕倍率使用显式实例stacks")
                    unit.attrs.final[AD.CRIT_RATE] = oldRate
                end
                unit._epicAwakeningGrowth = nil
                check(ETS.getEpicGrowth(unit).stacks == other, "省略实例时读取最新已提交owned")
                owned[id].extraTalent.stacks = 7
                check(ETS.getEpicGrowth(unit).stacks == 7, "省略实例不持有陈旧owned快照")
                unit._etsDisabled = true
                check(ETS.getEpicGrowth(unit).stacks == 0, "disabled getter空成长")
            end
        end
        check(ETS.getEpicGrowth(nil).stacks == 0 and ETS.getEpicGrowth({ heroId = 0, _epicAwakeningGrowth = { stacks = 100 } }).stacks == 0,
            "无/非法heroId不采信快照")

        print("[史诗支持II] 已提交事件增量同步显式实例，pending不提前加入")
        do
            local first = hero(11, 2, { stacks = 2, slashShadows = 0 })
            local second = hero(11, 2, { stacks = 200, slashShadows = 4 })
            owned[11].extraTalent = ETS.normalize({ stacks = 1000, slashShadows = 0 })
            local dead = enemy(); setHp(dead, 0); dead._killedBy = first
            dead._killedByNightSlash = true
            first._nightSlashKill = true
            fresh({ first, second }, { dead })
            local beforePatches = patches
            ETS.onEnemyDeath(dead, { first, second }, { dead })
            check(ETS.getEpicGrowth(first).slashShadows == 1 and ETS.getEpicGrowth(first).stacks == 2,
                "commit仅同步斩影库存+1，不提前加入永久pending")
            check(ETS.getEpicGrowth(second).slashShadows == 4 and ETS.getEpicGrowth(second).stacks == 200,
                "同hero他实例显式快照不被账号/事件污染")
            check(patches == beforePatches + 1 and owned[11].extraTalent.stacks == 1000,
                "机制commit不提前提交成长")
            check(first._epicCommittedGrowthDelta.slashShadows == 1 and first._epicCommittedGrowthDelta.stacks == nil
                and second._epicCommittedGrowthDelta == nil, "提交台账仅记当前实例实际机制delta，不记pending")
            ETS.flush(); ETS.flush()
            check(ETS.getEpicGrowth(first).stacks == 4 and owned[11].extraTalent.stacks == 1002,
                "flush按原通宵斩击杀已提交增量+2同步显式低快照，不替换账号高值，重复幂等")
            check(ETS.getEpicGrowth(second).stacks == 200, "flush不更新未参与他实例")
            check(first._epicCommittedGrowthDelta.stacks == 2 and first._epicCommittedGrowthDelta.slashShadows == 1,
                "flush台账记真实+2一次且保先前机制+1")
        end
        do
            local unit = hero(13, 2, { stacks = 4, splitKills = 0 })
            owned[13].extraTalent = ETS.normalize({ stacks = 1000, splitKills = 7 })
            local dead = enemy(); setHp(dead, 0)
            dead._killedBy, dead._killedByRicochet = unit, true
            fresh({ unit }, { dead })
            ETS.onEnemyDeath(dead, { unit }, { dead })
            check(ETS.getEpicGrowth(unit).splitKills == 1 and ETS.getEpicGrowth(unit).stacks == 4,
                "13 splitKills事件真实commit按delta，不替换账号7/8")
            ETS.flush()
            check(ETS.getEpicGrowth(unit).stacks == 6 and owned[13].extraTalent.stacks == 1002,
                "13真实flush才按原弹射击杀+2加入永久成长")
        end
        do
            local snow, protected = hero(12, 2, { iceStatues = 3 }), hero(1, 0)
            owned[12].extraTalent.iceStatues = 1
            local allies, group = { snow, protected }, { enemy() }
            fresh(allies, group)
            TAL.modifyDamageForTarget(protected, 1, true, sync, "physical", function() end, { allies = allies, enemies = group })
            check(ETS.getEpicGrowth(snow).iceStatues == 2 and owned[12].extraTalent.iceStatues == 0,
                "冰雕库存消费按负delta同步显式快照，而非用账号0覆盖")
            check(snow._epicCommittedGrowthDelta.iceStatues == -1
                and owned[12].extraTalent._epicCommittedGrowthDelta == nil,
                "提交台账允许实际负库存，玩家归档无新字段")
        end
        -- normalize边界只记实际变化，不将请求的+1/-1写成可凭空恢复的台账。
        for _, count in ipairs({ 0, 3 }) do
            local snow, protected = hero(12, 2, { iceStatues = count }), hero(1, 0)
            local dead, alive = enemy(), enemy()
            local allies, group = { snow, protected }, { dead, alive }
            fresh(allies, group)
            if count == 0 then
                owned[12].extraTalent.iceStatues = 1
                ETS.onBattleStart(allies, group)
                TAL.modifyDamageForTarget(protected, 1, true, sync, "physical", function() end,
                    { allies = allies, enemies = group })
            else
                owned[12].extraTalent.iceStatues = 0
                setHp(dead, 0); dead._killedBy = snow
                SEM.apply(dead, SEM.FROZEN, 1, snow, {})
                ETS.onEnemyDeath(dead, allies, group)
            end
            check(ETS.getEpicGrowth(snow).iceStatues == count and snow._epicCommittedGrowthDelta == nil,
                "冰雕归零/封顶实际变化0，台账不记录请求delta：" .. count)
        end
        do
            local unit = hero(13, 2, { stacks = 4, splitKills = 0 })
            local dead = enemy(); setHp(dead, 0)
            dead._killedBy, dead._killedByRicochet = unit, true
            fresh({ unit }, { dead })
            unit._pendingSnapshot = {}
            unit._hasPendingEpicAwakeningGrowth = true
            unit._pendingEpicCommittedGrowthDelta = { splitKills = -5 }
            local previousPending = unit._pendingSnapshot
            patchHook = function()
                unit._pendingSnapshot = {}
                unit._pendingEpicAwakeningGrowth = ETS.getOwned(13)
                unit._pendingEpicCommittedGrowthDelta = {}
                for key, value in pairs(unit._epicCommittedGrowthDelta or {}) do
                    unit._pendingEpicCommittedGrowthDelta[key] = value
                end
            end
            ETS.onEnemyDeath(dead, { unit }, { dead })
            patchHook = function() end
            check(unit._pendingSnapshot ~= previousPending and unit._pendingEpicAwakeningGrowth.splitKills == 1
                and unit._pendingEpicCommittedGrowthDelta.splitKills == 1,
                "patch同步refresh新pending已含收益，捕获台账仅补本次actualDelta")
            local freshPending = unit._pendingSnapshot
            ETS.flush(); ETS.flush()
            check(unit._pendingSnapshot == freshPending and unit._pendingEpicCommittedGrowthDelta.stacks == nil
                and unit._epicCommittedGrowthDelta.stacks == 2,
                "旧pending未含后续flush成长，captured台账不擅改且重复flush幂等")
        end
        for _, action in ipairs({ "snapshot", "unitToken", "ledger", "reset" }) do
            local unit = hero(13, 2, { stacks = 4, splitKills = 0 })
            local dead = enemy(); setHp(dead, 0)
            dead._killedBy, dead._killedByRicochet = unit, true
            fresh({ unit }, { dead })
            patchHook = function()
                if action == "snapshot" then unit._epicAwakeningGrowth = ETS.normalize({ stacks = 49 })
                elseif action == "unitToken" then unit._talentBattleToken = {}
                elseif action == "ledger" then unit._epicCommittedGrowthDelta = { stacks = 49 }
                else ETS.invalidateSupportBattle() end
            end
            ETS.onEnemyDeath(dead, { unit }, { dead })
            patchHook = function() end
            check(owned[13].extraTalent.splitKills == 1 and ETS.getEpicGrowth(unit).splitKills == 0
                and (not unit._epicCommittedGrowthDelta or not unit._epicCommittedGrowthDelta.splitKills),
                "patch回调身份失效不写旧snapshot/ledger，owned已提交保留：" .. action)
        end
        do
            local tank = hero(10, 2)
            fresh({ tank }, {})
            ETS.refreshBulwarkWard(tank)
            local state = ETS.mountedState()
            state.pendingGrowth[10] = { stacks = 5 }
            local token = state.supportBattleToken
            ETS.invalidateSupportBattle()
            check(not tank._etsBulwarkWard and state.supportBattleToken ~= token and state.pendingGrowth[10].stacks == 5,
                "invalidate只作废瞬时罩/token，pending原样")
            state.pendingGrowth = {}
            -- 人为在invalidate后直接refresh的罩没有合法开战列表注册，token仍须阻止旧罩消费。
            ETS.refreshBulwarkWard(tank)
            local unregisteredWard = tank._etsBulwarkWard
            TAL.reset()
            check(unregisteredWard.token ~= state.supportBattleToken and ETS.absorbBulwarkWard(tank, 3) == 3
                and not tank._etsBulwarkWard, "reset使未注册旧罩token失效，不得吸收新伤害")
            -- 正常生命周期必须先onBattleStart注册当前单位，再测试reset的主动清理。
            TAL.onBattleStart({ tank }, {})
            ETS.refreshBulwarkWard(tank)
            check(tank._etsBulwarkWard ~= nil, "合法重开注册后生成新罩")
            TAL.reset()
            check(not tank._etsBulwarkWard and ETS.absorbBulwarkWard(tank, 3) == 3, "TAL.reset接线清已注册旧罩")
        end

        print("[史诗支持II] 双线及归档：状态独立、永久字段/费用/战力不变")
        do
            local a1, a2 = hero(10, 2, { shareCount = 16 }), hero(10, 2, { shareCount = 16 })
            local refsA, refsB, unitsA, unitsB = TAL.newBattleRefs(), TAL.newBattleRefs(), TAL.newUnitStates(), TAL.newUnitStates()
            local extraA, extraB, semA, semB = ETS.newState(), ETS.newState(), SEM.newSemState(), SEM.newSemState()
            local ea, eb, aa, ab = { enemy() }, { enemy() }, { a1 }, { a2 }
            mount(refsA, unitsA, extraA, semA); TAL.onBattleStart(aa, ea); ETS.refreshBulwarkWard(a1)
            local wa = a1._etsBulwarkWard
            mount(refsB, unitsB, extraB, semB); TAL.onBattleStart(ab, eb); ETS.refreshBulwarkWard(a2)
            local wb = a2._etsBulwarkWard
            mount(refsA, unitsA, extraA, semA); update(1, aa, ea)
            check(wa.timer == 2 and wb.timer == 3, "A线计时不推进B线罩")
            TAL.onBattleStart(aa, ea)
            check(not a1._etsBulwarkWard and a2._etsBulwarkWard == wb, "A线重开不清B线罩")
            mount(refsB, unitsB, extraB, semB)
            check(ETS.absorbBulwarkWard(a2, 1) == 0 and a2._etsBulwarkWard == wb, "B线重新mount仍保有效罩")
            update(3, ab, eb)
            check(not a2._etsBulwarkWard, "B线自己的到期才清罩")
        end
        local normalized = ETS.normalize({ supportBattleToken = {}, supportAllies = {}, _etsBulwarkWard = {}, stacks = 30 })
        check(normalized.supportBattleToken == nil and normalized.supportAllies == nil and normalized._etsBulwarkWard == nil,
            "所有新增临时状态不归档，无新存档字段")
        check(AC.getTotalShardCost() == 90 and AC.COMBAT_POWER[3][2] == 65, "费用/史诗共鸣战力不改")
        check(patches > 0, "真实库存消耗/复活发票经内存owned链")
        print("[史诗支持II] 内存patch=" .. patches .. " syncActions=" .. sends)
    end)
    if not ok then failures = failures + 1; print("[史诗支持II][FAIL] 执行异常 " .. tostring(err)) end
    math.random = oldRandom
    rawset(_G, "require", originalRequire)
    check(storageCalls == 0, "File/FileSystem/fileSystem/GetFileSystem四入口访问0")
    rawset(_G, "File", oldFile); rawset(_G, "FileSystem", oldFS)
    rawset(_G, "fileSystem", oldFs); rawset(_G, "GetFileSystem", oldGetFS)
    print(string.format("[史诗支持II] %d assertions / %d failures / FileFS=%d", assertions, failures, storageCalls))
    print(failures == 0 and "[史诗支持II] ALL PASS" or "[史诗支持II] FAILED")
    engine:Exit()
end
