-- ============================================================================
-- TalentAfterAttack - TAL.onAfterAttack 抽出（玩法不变）
-- Bound via M.bind(deps); 对外仍走 TAL.onAfterAttack
-- ============================================================================

local AD  = require("systems.AttributeDef")
local SEM = require("systems.StatusEffectManager")
local RCH = require("systems.RelicConditionHandler")
local ETS = require("systems.ExtraTalentSystem")

local M = {}

function M.bind(deps)
    local getState = deps.getState
    local ensureState = deps.ensureState
    local hasAdv = deps.hasAdv
    local hasAwaken = deps.hasAwaken
    local hasStarNode = deps.hasStarNode
    local teamHasStarNode = deps.teamHasStarNode
    local talentLog = deps.talentLog
    local getAliveEnemies = deps.getAliveEnemies
    local applyOverhealToEnergyShield = deps.applyOverhealToEnergyShield
    local calcTalentFixedDamage = deps.calcTalentFixedDamage
    local wrapDealDmgForLuoxing = deps.wrapDealDmgForLuoxing
    local addMelissaStarMarks = deps.addMelissaStarMarks
    local addLuoxingWindowDamage = deps.addLuoxingWindowDamage
    local getLuoxingAccumAmount = deps.getLuoxingAccumAmount
    local applyAyaneMark = deps.applyAyaneMark
    local clearAyaneMarks = deps.clearAyaneMarks
    local applyElwynEnergyBlessing = deps.applyElwynEnergyBlessing
    local runSuhuaNightSlash = deps.runSuhuaNightSlash
    local tryAlexSilverFlash = deps.tryAlexSilverFlash
    local tryYouyeSuperCrit = deps.tryYouyeSuperCrit
    local tryRosaBounce = deps.tryRosaBounce
    local onXinAfterAttack = deps.onXinAfterAttack
    local onFatFishAfterAttack = deps.onFatFishAfterAttack
    local onFourNewAfterAttack = deps.onFourNewAfterAttack
    local getTAL_BCS = deps.getTAL_BCS

    local function onAfterAttack(attacker, target, result, isAlly, targetList, dealDmgFn, attackerAllies)
    local TAL_BCS = getTAL_BCS()
    local s = getState(attacker)
    if not s then return end
    local heroId = s.heroId

    dealDmgFn = wrapDealDmgForLuoxing(attacker, dealDmgFn)

    -- === 原有英雄天赋 ===

    -- #20 摘星星星人 星之守护：星门固定周期发射；连击产生的星痕在星门发射时结算
    if heroId == 20 and result and result.comboCount and result.comboCount > 0 then
        addMelissaStarMarks(attacker, result.comboCount)
    end

    -- 跳过miss的后续效果
    if result and result.isMiss then return end

    -- #23 真布诗人 护盾说唱：有盾的人下次攻击附带神圣伤
    if attacker._rhymeShot and attacker._rhymeShot > 0 and dealDmgFn and target and (target.hp or 0) > 0
        and result and result.category ~= "healing" then
        local rhymeDmg = attacker._rhymeShot
        attacker._rhymeShot = nil
        dealDmgFn(target, rhymeDmg, not isAlly, "押韵 ", { 255, 220, 120 }, {
            instantDamage = true,
            statCategory = "magical",
        })
    end

    -- #1 大狗嚼 衔骨狂
    if heroId == 1 and s.hopeBuff then
        if hasAwaken(attacker, 4) and result and result.totalDamage and result.totalDamage > 0 and attacker.attrs then
            local healAmt = math.floor(result.totalDamage * 0.10 + 0.5)
            if healAmt > 0 then
                attacker.attrs:heal(healAmt)
                attacker.hp = attacker.attrs:get(AD.HP)
                if attacker.hp > attacker.maxHp then attacker.hp = attacker.maxHp end
                talentLog("[Talent] 大狗嚼 觉醒4: 吸血 " .. healAmt .. " HP (伤害=" .. result.totalDamage .. ")")
            end
        end
        -- 残血普攻额外撕咬
        if dealDmgFn and target and (target.hp or 0) > 0
            and result and result.category ~= "healing" and not attacker._etsBiting then
            local physAtk = attacker.attrs and attacker.attrs:get(AD.PHYS_ATK) or 0
            local biteDmg = math.floor(physAtk * 0.40 + 0.5)
            if biteDmg > 0 then
                dealDmgFn(target, biteDmg, not isAlly, "撕咬 ", { 255, 180, 90 }, {
                    instantDamage = true,
                    statCategory = "physical",
                })
            end
        end
    end

    -- #3 叮咚鸡 已读不回：第三刀额外效果后清 modifier
    if heroId == 3 then
        if s.preciseBuff then
        -- 觉醒5: 精准箭矢造成暴击时额外50%伤害
        if hasAwaken(attacker, 5) and result and result.isCrit and dealDmgFn and target.hp > 0 then
            local bonusDmg = math.floor((result.totalDamage or 0) * 0.50 + 0.5)
            if bonusDmg > 0 then
                dealDmgFn(target, bonusDmg, not isAlly, "已读暴击 ", { 255, 200, 50 })
            end
        end
        -- 觉醒3: 精准命中后25%概率下次攻击也是精准
        if hasAwaken(attacker, 3) then
            if math.random() < 0.25 then
                s.preciseChain = true
                talentLog("[Talent] 叮咚鸡 觉醒3：已读连锁触发")
            end
        end
        -- 觉醒7: 精准箭矢散射3个敌人
        if hasAwaken(attacker, 7) and dealDmgFn and targetList then
            local scatterDmg = result and result.totalDamage or 0
            if scatterDmg > 0 then
                local otherAlive = {}
                for _, u in ipairs(targetList) do
                    if u.hp > 0 and u ~= target then
                        otherAlive[#otherAlive + 1] = u
                    end
                end
                -- 散射到最多2个其他目标（加上原目标共3个）
                local scatterCount = math.min(2, #otherAlive)
                for si = 1, scatterCount do
                    local ri = math.random(#otherAlive)
                    local st = otherAlive[ri]
                    if st.hp > 0 then
                        dealDmgFn(st, scatterDmg, not isAlly, "散射 ", { 200, 255, 200 })
                    end
                    table.remove(otherAlive, ri)
                end
                if scatterCount > 0 then
                    talentLog("[Talent] 叮咚鸡 觉醒7：散射命中 " .. scatterCount .. " 个额外目标")
                end
            end
        end
        attacker.attrs:removeModifier("talent_precise")
        s.preciseBuff = false
        end
        attacker.attrs:removeModifier("talent_precise")
    end

    -- #7 信光机兵 闪光协议
    if heroId == 7 then
        onXinAfterAttack(attacker, s, target, isAlly, targetList, dealDmgFn, result)
    end

    -- #5 叠甲怪 战斗征服：叠加征服层数
    if heroId == 5 and attacker.attrs then
        -- 觉醒2: 最大层数5 (15→20)
        local maxConquer = 15
        if hasAwaken(attacker, 2) then maxConquer = 20 end
        if attacker._etsConquerStart then
            s.conquerStacks = math.max(s.conquerStacks, attacker._etsConquerStart)
            attacker._etsConquerStart = nil
        end
        s.conquerStacks = math.min(maxConquer, s.conquerStacks + 1)
        if s.conquerStacks >= maxConquer then
            attacker._conquerFullKill = true
        else
            attacker._conquerFullKill = nil
        end
        attacker.attrs:removeModifier("talent_conquer")
        if s.conquerStacks > 0 then
            local entries = {
                { key = AD.PHYS_ATK, pct = s.conquerStacks * 2 },
            }
            -- 觉醒1: 每层+1%攻速
            if hasAwaken(attacker, 1) then
                entries[#entries+1] = { key = AD.ATK_SPEED, flat = s.conquerStacks * 1 }
            end
            -- 觉醒3: 每层+0.5闪避
            if hasAwaken(attacker, 3) then
                entries[#entries+1] = { key = AD.DODGE, flat = s.conquerStacks * 0.5 }
            end
            -- 觉醒4: 每层+1%连击概率
            if hasAwaken(attacker, 4) then
                entries[#entries+1] = { key = AD.COMBO_RATE, flat = s.conquerStacks * 1 }
            end
            -- 觉醒5: 每层+1%连击增伤
            if hasAwaken(attacker, 5) then
                entries[#entries+1] = { key = AD.COMBO_DMG_UP, flat = s.conquerStacks * 1 }
            end
            -- 觉醒6: 每层+1%物理伤害加成
            if hasAwaken(attacker, 6) then
                entries[#entries+1] = { key = AD.PHYS_DMG_BONUS, flat = s.conquerStacks * 1 }
            end
            -- 觉醒7: 满层时所有效果提速0%
            if hasAwaken(attacker, 7) and s.conquerStacks >= maxConquer then
                if not s.conquerMaxBoostApplied then
                    s.conquerMaxBoostApplied = true
                    -- →.5倍所有flat/pct
                    for _, e in ipairs(entries) do
                        if e.flat then e.flat = math.floor(e.flat * 1.5 + 0.5) end
                        if e.pct then e.pct = math.floor(e.pct * 1.5 + 0.5) end
                    end
                    talentLog("[Talent] 叠甲怪 征服觉醒7：满层效果50%!")
                elseif s.conquerMaxBoostApplied then
                    -- 已满层且已应用50%提升，保留
                    for _, e in ipairs(entries) do
                        if e.flat then e.flat = math.floor(e.flat * 1.5 + 0.5) end
                        if e.pct then e.pct = math.floor(e.pct * 1.5 + 0.5) end
                    end
                end
            end
            attacker.attrs:addModifier("talent_conquer", entries)
        end
        if s.conquerStacks % 5 == 0 or s.conquerStacks == 1 then
            talentLog("[Talent] 叠甲怪 征服×" .. s.conquerStacks .. "/" .. maxConquer .. " (物攻+" .. (s.conquerStacks * 2) .. "%)")
        end
    end

    -- === 转职天赋: 攻击后（伤害类） ===

    if result and result.category ~= "healing" and not result.isMiss then
        -- #8 愤怒的小雀觉醒: 攻击标记目标的战斗效果（需在伤害计算后处理）
        if heroId == 8 and attacker.attrs then
            local isMarked = SEM.has(target, SEM.MARKED)
            -- 觉醒3: 攻击标记目标暴击+15%（攻击后移除临时modifier)
            if hasAwaken(attacker, 3) then
                attacker.attrs:removeModifier("awaken_mark_crit")
            end
            -- 觉醒5: 暴击伤害+30%（攻击后移除临时modifier)
            if hasAwaken(attacker, 5) then
                attacker.attrs:removeModifier("awaken_mark_critdmg")
            end
            -- 觉醒6: 首次攻击标记目标必暴（记录已消费 + 移除modifier)
            if hasAwaken(attacker, 6) and isMarked and not s.markFirstHitCrit[target] then
                s.markFirstHitCrit[target] = true  -- 标记已消费首次必暴）
            end
            attacker.attrs:removeModifier("awaken_mark_first_crit")
            -- 觉醒7: 标记目标HP<15%时直接斩杀
            if hasAwaken(attacker, 7) and isMarked and target.hp > 0 then
                local targetHpPct = target.hp / math.max(1, target.maxHp)
                if targetHpPct < 0.15 then
                    if dealDmgFn then
                        dealDmgFn(target, target.hp, not isAlly, "斩杀 ", { 255, 0, 50 })
                        talentLog("[Talent] 愤怒的小雀 觉醒7：斩杀 " .. target.name .. "!")
                    end
                    -- 斩杀后立即转移标记（不依赖延迟的 onEnemyDeath）
                    if targetList then
                        local aliveEnemies = getAliveEnemies(targetList)
                        if #aliveEnemies > 0 then
                            local newTarget = aliveEnemies[math.random(#aliveEnemies)]
                            applyAyaneMark(attacker, newTarget, targetList)
                            talentLog("[Talent] 愤怒的小雀 觉醒7: 斩杀后标记转移→" .. (newTarget.name or "?"))
                        else
                            clearAyaneMarks(targetList)
                        end
                    end
                end
            end
        end

        -- #14 内鬼 暴击精通觉醒：onAfterAttack效果
        if heroId == 14 and attacker.attrs then
            -- 觉醒4: 首次攻击新目标必暴（消费记录 + 移除modifier)
            if hasAwaken(attacker, 4) then
                if not s.firstHitTargets[target] then
                    s.firstHitTargets[target] = true
                end
                attacker.attrs:removeModifier("awaken_firsthit_crit")
            end
            -- 觉醒7: 超暴击（暴击率溢出→超暴击率，触发后再乘一次暴击伤害）
            if hasAwaken(attacker, 7) and result and result.isCrit then
                tryYouyeSuperCrit(attacker, target, result, isAlly, dealDmgFn)
            end
            -- 抄作业：暴击偷攻速（每次 +8%，最多 +40%）
            if result and result.isCrit and attacker.attrs then
                local stolen = math.min(40, (s.stolenSpeed or 0) + 8)
                s.stolenSpeed = stolen
                local copySpd = stolen
                attacker.attrs:removeModifier("talent_copy_speed")
                attacker.attrs:addModifier("talent_copy_speed", {
                    { key = AD.ATK_SPEED, flat = copySpd },
                })
                attacker.atkInterval = attacker.attrs:getActualInterval()
                talentLog(string.format("[Talent] 内鬼 抄作业 攻速+%.0f%%", copySpd))
                -- 暴击击杀残血：<15% 直接收工
                if target.hp > 0 then
                    local hpPct = target.hp / math.max(1, target.maxHp or 1)
                    if hpPct < 0.15 and dealDmgFn then
                        dealDmgFn(target, target.hp, not isAlly, "收工 ", { 180, 80, 255 }, {
                            instantDamage = true,
                        })
                    end
                end
            end
        end

        -- #2 黄桃龙 火焰精通：附加燃烧
        if heroId == 2 and attacker.attrs and target.hp > 0 then
            local magAtk = attacker.attrs:get(AD.MAG_ATK) or 0
            local burnMult = 0.2
            -- 觉醒1: 燃烧伤害+10%
            if hasAwaken(attacker, 1) then burnMult = burnMult + 0.02 end
            -- 觉醒5: 燃烧伤害+25%
            if hasAwaken(attacker, 5) then burnMult = burnMult + 0.05 end
            local dps = math.floor(magAtk * burnMult + 0.5)
            if dps > 0 then
                local burnData = { dps = dps }
                -- 觉醒3: 燃烧可造成魔法暴击
                if hasAwaken(attacker, 3) then
                    burnData.canCrit = true
                    local baseCritRate = attacker.attrs:get(AD.MAG_CRIT_RATE) or 0
                    local baseCritDmg  = attacker.attrs:get(AD.MAG_CRIT_DMG) or 50
                    -- 觉醒6: 自带+10%魔法暴击率与+50%魔法暴击伤害
                    if hasAwaken(attacker, 6) then
                        baseCritRate = baseCritRate + 10
                        baseCritDmg  = baseCritDmg + 50
                    end
                    burnData.critRate = baseCritRate
                    burnData.critDmg  = baseCritDmg
                end
                -- 觉醒7: 可叠加燃烧，最多5层
                if hasAwaken(attacker, 7) then
                    burnData.stackable = true
                    burnData.maxStacks = 3
                end
                SEM.apply(target, SEM.BURNING, 2.0, attacker, burnData)
            end
            -- 觉醒2: 攻击燃烧中的敌人立即结算一次燃烧伤害
            if hasAwaken(attacker, 2) and SEM.has(target, SEM.BURNING) then
                local burnEffect = SEM.get(target, SEM.BURNING)
                if burnEffect and burnEffect.data.dps and burnEffect.data.dps > 0 and dealDmgFn then
                    local instantDmg = math.floor(burnEffect.data.dps + 0.5)
                    dealDmgFn(target, instantDmg, not isAlly, "燃烧结算 ", { 255, 120, 30 })
                end
            end
            -- 觉醒4: 2+敌人处于燃烧时魔法攻击加成15%
            if hasAwaken(attacker, 4) then
                attacker.attrs:removeModifier("awaken_burn_bonus")
                local burnCount = SEM.countUnitsWithEffect(targetList, SEM.BURNING)
                if burnCount >= 2 then
                    attacker.attrs:addModifier("awaken_burn_bonus", {
                        { key = AD.MAG_ATK_BONUS, flat = 15 },
                    })
                end
            end
        end

        -- #6 阿姨压 闪电精通：附加感电
        if heroId == 6 and target.hp > 0 then
            -- 觉醒1: 魔法伤害加成+10%（永久，首次添加成
            if hasAwaken(attacker, 1) and not s.awakLunaDmgApplied then
                s.awakLunaDmgApplied = true
                attacker.attrs:addModifier("awaken_luna_dmg", {
                    { key = AD.MAG_DMG_BONUS, flat = 10 },
                })
            end
            -- 觉醒2: 感电增伤30%
            local shockMult = 0.20
            if hasAwaken(attacker, 2) then shockMult = 0.30 end
            -- 觉醒3: 感电持续3秒
            local shockDur = 2.0
            if hasAwaken(attacker, 3) then shockDur = 3.0 end
            local shockData = { mult = shockMult }
            -- 觉醒4: 感电额外-105能量护盾
            if hasAwaken(attacker, 4) then shockData.magArmorDebuff = 105 end
            -- 觉醒5: 感电目标攻速10%
            if hasAwaken(attacker, 5) then shockData.atkSpeedDebuff = 10 end
            -- 觉醒7: 感电敌人额外10%受暴击概率
            if hasAwaken(attacker, 7) then shockData.critVuln = 10 end
            SEM.apply(target, SEM.SHOCKED, shockDur, attacker, shockData)
            -- 应用debuff到目标属性
            if target.attrs then
                target.attrs:removeModifier("awaken_shock_debuff_" .. tostring(target))
                local debuffEntries = {}
                if shockData.magArmorDebuff then
                    debuffEntries[#debuffEntries+1] = { key = AD.MAG_ARMOR, flat = -shockData.magArmorDebuff }
                end
                if shockData.atkSpeedDebuff then
                    debuffEntries[#debuffEntries+1] = { key = AD.ATK_SPEED, flat = -shockData.atkSpeedDebuff }
                end
                if #debuffEntries > 0 then
                    target.attrs:addModifier("awaken_shock_debuff_" .. tostring(target), debuffEntries)
                end
            end
            -- 觉醒6: 每有一个敌人处于感电，魔攻加成+5%
            if hasAwaken(attacker, 6) and targetList then
                attacker.attrs:removeModifier("awaken_luna_shock_bonus")
                local shockCount = SEM.countUnitsWithEffect(targetList, SEM.SHOCKED)
                if shockCount > 0 then
                    attacker.attrs:addModifier("awaken_luna_shock_bonus", {
                        { key = AD.MAG_ATK_BONUS, flat = shockCount * 5 },
                    })
                end
            end
        end

        -- #12 雪皇 冰霜精通：25%概率附加冰冻1.5秒 + 觉醒
        if heroId == 12 and target.hp > 0 then
            -- 觉醒1: 概率25%→35%  觉醒3: 概率→50%
            local freezeChance = 0.25 + ETS.getSnowFreezeBonus(ETS.getOwned(12), attacker)
            if hasAwaken(attacker, 1) then freezeChance = 0.35 + ETS.getSnowFreezeBonus(ETS.getOwned(12), attacker) end
            if hasAwaken(attacker, 3) then freezeChance = 0.50 + ETS.getSnowFreezeBonus(ETS.getOwned(12), attacker) end
            freezeChance = math.min(0.80, freezeChance)
            -- 觉醒4: 持续时间+0.5秒
            local freezeDur = 1.5
            if hasAwaken(attacker, 4) then freezeDur = 2.0 end
            -- 内置CD：目标被冰冻后，需待其解冻并再经过 FREEZE_INTERNAL_CD 秒才能被本天赋再次冰冻，避免无限冰冻锁怪
            local FREEZE_INTERNAL_CD = 0.02
            local onFreezeCD = (s.freezeCD[target] or 0) > 0
            if not onFreezeCD and math.random() < freezeChance then
                -- 觉醒5: 首次冰冻额外+2秒
                local actualDur = freezeDur
                if hasAwaken(attacker, 5) and not s.firstFreezeUsed[target] then
                    s.firstFreezeUsed[target] = true
                    actualDur = actualDur + 2.0
                    talentLog("[Talent] 雪皇 觉醒5: 首次冰冻 " .. target.name .. " 额外+2s")
                end
                -- 觉醒2: 冰冻目标额外受到20%伤害
                local frozenData = {}
                if hasAwaken(attacker, 2) then
                    frozenData.extraDmgMult = 0.20
                end
                SEM.apply(target, SEM.FROZEN, actualDur, attacker, frozenData)
                -- 触发内置CD = 本次冰冻时长 + 固定CD（解冻后还需等待 FREEZE_INTERNAL_CD 秒才能再次冰冻）
                s.freezeCD[target] = actualDur + FREEZE_INTERNAL_CD
                -- 觉醒7: 每冰冻一名敌人，魔攻加成+3%，最多10层
                if hasAwaken(attacker, 7) then
                    s.freezeAtkStacks = math.min(20, s.freezeAtkStacks + 1)
                    attacker.attrs:removeModifier("awaken_freeze_matk")
                    attacker.attrs:addModifier("awaken_freeze_matk", {
                        { key = AD.MAG_ATK_BONUS, flat = s.freezeAtkStacks * 3 },
                    })
                    talentLog("[Talent] 雪皇 觉醒7: 冰冻叠层×" .. s.freezeAtkStacks .. " (魔攻+" .. (s.freezeAtkStacks * 3) .. "%)")
                end
            end
        end

        -- #13 弹弹弹弹射箭矢
        if heroId == 13 then
            tryRosaBounce(attacker, s, target, isAlly, targetList, dealDmgFn, result)
        end

        -- #11 熬夜冠军 夜华斩：每攻速次斩出2道斩击
        -- 斩击优先命中不同敌人，没有多余敌人时可命中同一敌人
        -- 造成物理攻击*100%的斩击伤害，投射物使用贝塞尔曲线
        if heroId == 11 and dealDmgFn and targetList then
            runSuhuaNightSlash(attacker, s, target, isAlly, targetList, dealDmgFn)
        end

        -- #17 蓝色大肥鱼 高压水枪：潮湿 + 溅射冰霜
        if heroId == 17 and onFatFishAfterAttack then
            onFatFishAfterAttack(attacker, target, result, isAlly, targetList, dealDmgFn)
        end

        -- #18/#19/#24/#25
        if onFourNewAfterAttack then
            onFourNewAfterAttack(attacker, target, result, isAlly, targetList, dealDmgFn)
        end

        -- #16 万剑归宗 灵月飞剑：累计实际造成伤害（含护盾吸收、暴击与各类增伤）
        if heroId == 16 and result and not result.isMiss and result.category ~= "healing" then
            addLuoxingWindowDamage(attacker, getLuoxingAccumAmount(result, 0), nil, nil)
        end

        -- #20 摘星星星人 星之守护：星门已改为固定间隔自动发射；其他魔法角色不再立即触发星门，避免回到攻速/连击协同

        -- #21 闪电卖鸡 银光（每轮攻击仅判定一次，避免多目标重复触发）
        if heroId == 21 and dealDmgFn and target and not result.isMiss and result.category ~= "healing" then
            if not s.silverFlashChecked then
                s.silverFlashChecked = true
                tryAlexSilverFlash(attacker, s, target, isAlly, dealDmgFn, result)
            end
        end

        -- #22 小黑子 法术机关枪：仅连射弹触发过载叠层 + 觉醒7全体（触发连射的那次普攻不算连射）
        if heroId == 22 and s.lastAttackWasBurst and result and not result.isMiss and result.category ~= "healing" then
            if hasAwaken(attacker, 6) and attacker.attrs then
                s.machineGunOverloadStacks = math.min(10, (s.machineGunOverloadStacks or 0) + 1)
                attacker.attrs:removeModifier("sera_overload")
                attacker.attrs:addModifier("sera_overload", {
                    { key = AD.MAG_ATK_BONUS, flat = s.machineGunOverloadStacks * 2 },
                })
            end
            if hasAwaken(attacker, 7) and dealDmgFn and targetList and math.random() < 0.20 then
                local aoeDmg = result.totalDamage or 0
                if aoeDmg > 0 then
                    for _, u in ipairs(targetList) do
                        if u.hp > 0 and u ~= target then
                            dealDmgFn(u, aoeDmg, not isAlly, "连射 ", { 180, 220, 255 })
                        end
                    end
                    talentLog("[Talent] 小黑子 觉醒7：连射全体")
                end
            end
        end

        -- #4 接化发掌门 化劲：释放格挡反击池
        if heroId == 4 and s.blockAbsorbedDmg > 0 then
            local bonusDmg = s.blockAbsorbedDmg
            s.blockAbsorbedDmg = 0
            if bonusDmg > 0 and target.hp > 0 and dealDmgFn then
                dealDmgFn(target, bonusDmg, not isAlly, "化劲 ", { 200, 200, 255 })
                talentLog("[Talent] 接化发掌门 化劲反击 " .. bonusDmg)
            end
        end

        -- 106 奥术飞弹: 35%概率对随机敌人发射飞弹（魔攻*100%暗影伤害)
        if hasAdv(attacker, "adv_106_arcane_missile") and dealDmgFn and targetList then
            local missileChance = 0.35
            local missileMult = 1.0
            local has211 = hasAdv(attacker, "adv_211_arcane_wisdom")
            local has212 = hasAdv(attacker, "adv_212_arcane_surge")

            -- 211 奥术智慧: 概率→50%
            if has211 then missileChance = 0.50 end
            -- 212 奥能充盈: 伤害→魔攻×200%
            if has212 then missileMult = 2.0 end

            -- 211: 目标<20% HP时必定触发
            local targetHpPct = target.hp / math.max(1, target.maxHp)
            if has211 and targetHpPct < 0.20 then
                missileChance = 1.0
            end

            if math.random() < missileChance then
                -- 211: 优先攻击HP%最低的敌人；默认随机存活敌人
                local missileTarget = target
                if has211 then
                    local lowest, lowestPct = nil, 2.0
                    for _, u in ipairs(targetList) do
                        if u.hp > 0 then
                            local pct = u.hp / math.max(1, u.maxHp)
                            if pct < lowestPct then
                                lowestPct = pct
                                lowest = u
                            end
                        end
                    end
                    if lowest then missileTarget = lowest end
                else
                    local alive = getAliveEnemies(targetList)
                    if #alive > 0 then
                        missileTarget = alive[math.random(#alive)]
                    end
                end

                if missileTarget and missileTarget.hp > 0 and attacker.attrs then
                    local magAtk = attacker.attrs:get(AD.MAG_ATK) or 0
                    local atkCoeff = attacker.atkCoeff or attacker.attrs.atkCoeff or 1.0
                    local baseDmg = magAtk * atkCoeff * missileMult

                    local critRate = attacker.attrs:get(AD.CRIT_RATE) + attacker.attrs:get(AD.MAG_CRIT_RATE)
                    local critDmg  = attacker.attrs:get(AD.CRIT_DMG)  + attacker.attrs:get(AD.MAG_CRIT_DMG)
                    local shockedEffect = SEM.get(missileTarget, SEM.SHOCKED)
                    if shockedEffect and shockedEffect.data and shockedEffect.data.critVuln then
                        critRate = critRate + shockedEffect.data.critVuln
                    end

                    local missileDmg, missileCrit = calcTalentFixedDamage(attacker, missileTarget, baseDmg, {
                        atkType  = AD.ATK_SHADOW,
                        critRate = critRate,
                        critDmg  = critDmg,
                    })

                    -- 遗物/副本等来自触发普攻的增伤（与 BattleCombat._talentDmgMult 一致）
                    if result._talentDmgMult and result._talentDmgMult > 1.0 then
                        missileDmg = math.floor(missileDmg * result._talentDmgMult + 0.5)
                    end

                    -- 211: <40% HP 伤害翻倍
                    if has211 then
                        local mtPct = missileTarget.hp / math.max(1, missileTarget.maxHp)
                        if mtPct < 0.40 then
                            missileDmg = missileDmg * 2
                        end
                    end

                    local semMult = SEM.getDamageTakenMult(missileTarget)
                    if semMult and semMult ~= 1.0 then
                        missileDmg = math.floor(missileDmg * semMult + 0.5)
                    end

                    local missilePrefix = missileCrit and "暴击飞弹 " or "飞弹 "
                    local missileColor  = missileCrit and { 255, 180, 50 } or { 160, 100, 255 }

                    if missileDmg > 0 then
                        dealDmgFn(missileTarget, missileDmg, not isAlly, missilePrefix, missileColor, {
                            talentProjKey = "EF_ZY_106",
                            statCategory = "magical",
                            isCrit = missileCrit,
                            critEligible = true,
                        })

                        -- 212 奥能充盈: 30%概率爆炸AOE
                        if has212 and math.random() < 0.30 then
                            local mtIdx = 0
                            for i, u in ipairs(targetList) do
                                if u == missileTarget then mtIdx = i; break end
                            end
                            local explosionPrefix = missileCrit and "暴击爆炸 " or "飞弹爆炸 "
                            local explosionColor  = missileCrit and { 255, 140, 50 } or { 200, 80, 255 }
                            for offset = -1, 1 do
                                local idx = mtIdx + offset
                                if idx >= 1 and idx <= #targetList then
                                    local u = targetList[idx]
                                    if u ~= missileTarget and u.hp > 0 then
                                        dealDmgFn(u, missileDmg, not isAlly, explosionPrefix, explosionColor, {
                                            talentProjKey = "EF_ZY_224",
                                            statCategory = "magical",
                                            isCrit = missileCrit,
                                            critEligible = false,
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 104 决斗者 锁定目标 + 伤害加成+5%
        if hasAdv(attacker, "adv_104_duelist") then
            if s.duelTarget ~= target then
                -- 切换目标
                s.duelTarget = target
                s.duelCount = 1
            else
                s.duelCount = s.duelCount + 1
            end
        end

        -- 208 幻影剑斩: 攻击同一目标叠加[连击]
        if hasAdv(attacker, "adv_208_phantom_slash") and attacker.attrs then
            attacker.attrs:removeModifier("talent_phantom")
            if s.phantomTarget == target then
                s.phantomStacks = math.min(10, s.phantomStacks + 1)
            else
                -- 切换目标失去2层
                s.phantomStacks = math.max(0, s.phantomStacks - 2)
                s.phantomTarget = target
            end
            if s.phantomStacks > 0 then
                attacker.attrs:addModifier("talent_phantom", {
                    { key = AD.COMBO_RATE, flat = s.phantomStacks * 10 },
                    { key = AD.COMBO_DMG_UP, flat = s.phantomStacks * 2 },
                })
            end
        end

        -- 108 阵前提速 每次攻击消耗1层
        if hasAdv(attacker, "adv_108_battle_haste") and s.hasteStacks > 0 then
            s.hasteStacks = s.hasteStacks - 1
            attacker.attrs:removeModifier("talent_haste")
            if s.hasteStacks > 0 then
                attacker.attrs:addModifier("talent_haste", {
                    { key = AD.ATK_SPEED, flat = s.hasteStacks * 8 },
                })
            end
            -- 215 鹰眼: 更新穿透
            if hasAdv(attacker, "adv_215_eagle_eye") then
                attacker.attrs:removeModifier("talent_eagle_pen")
                if s.hasteStacks > 0 then
                    attacker.attrs:addModifier("talent_eagle_pen", {
                        { key = AD.PHYS_PEN, flat = s.hasteStacks * 6 },
                    })
                end
            end
        end

        -- 110 影袭: 消费影袭buff
        if hasAdv(attacker, "adv_110_shadow_strike") and s.shadowStrikeBuff then
            attacker.attrs:removeModifier("talent_shadow_strike")
            s.shadowStrikeBuff = false
            talentLog("[Talent] 影袭: 伤害加成已消耗")
        end

        -- 219 致命之刃: 暴击时进度条+100%, 暴击伤害+25% (每轮攻击进度只能触发一次）
        if hasAdv(attacker, "adv_219_lethal_blade") and result.isCrit and not s.lethalBladeUsed then
            attacker.atkProgress = math.min(1.0, (attacker.atkProgress or 0) + 1.0)
            s.lethalBladeUsed = true
            s.lethalBladeSkipReset = true  -- 下次免费攻击，onBeforeAttack 不重置
            talentLog("[Talent] 致命之刃: 暴击→进度条+100% (本轮已消费")
        end

        -- 210 蚀骨诅咒 带诅咒的敌人受伤时额外暗影伤害(3秒CD)
        if isAlly and dealDmgFn and target.hp > 0 and SEM.has(target, SEM.VULNERABLE) then
            -- 查找拥有210天赋的己方单位
            for _, ally in ipairs(TAL_BCS.bAllies) do
                if hasAdv(ally, "adv_210_corrosion_curse") and ally.hp > 0 then
                    local as = getState(ally)
                    if as then
                        local cd = as.corrosionCds[target] or 0
                        if cd <= 0 then
                            local magAtk = ally.attrs and ally.attrs:get(AD.MAG_ATK) or 0
                            local corDmg = math.floor(magAtk * 0.8 + 0.5)
                            if corDmg > 0 then
                                dealDmgFn(target, corDmg, not isAlly, "蚀骨", { 180, 50, 220 })
                                as.corrosionCds[target] = 1.0  -- 1秒CD
                            end
                        end
                    end
                    break -- 只触发一次）10
                end
            end
        end

        -- 214 林间之眼: 普通攻击获得[暴击提升]
        if hasAdv(attacker, "adv_214_forest_eye") and attacker.attrs then
            s.critBoostStacks = math.min(20, s.critBoostStacks + 1)
            s.critBoostTimer = 10.0
            attacker.attrs:removeModifier("talent_crit_boost")
            attacker.attrs:addModifier("talent_crit_boost", {
                { key = AD.CRIT_DMG, flat = s.critBoostStacks * 8 },
            })
        end
    end

    -- === 转职天赋: 攻击后（治疗类） ===

    if result and result.category == "healing" then
        -- [DIAG-ADV] 诊断：转职天赋检查（牧师111/112效果不生效排查）
        if heroId == 9 or heroId == 15 then
            local tids = attacker.advTalentIds
            local tidStr = tids and table.concat(tids, ",") or "NIL"
            local abStr = "nil"
            if attacker.advBranch then
                abStr = string.format("{first=%s,second=%s}",
                    tostring(attacker.advBranch.first), tostring(attacker.advBranch.second))
            end
            print(string.format(
                "[DIAG-ADV] HEAL_CHECK healer=%s(id%s) advTalentIds=[%s] advBranch=%s target=%s(hp%.0f)",
                tostring(attacker.name), tostring(heroId), tidStr, abStr,
                tostring(target.name), target.hp or 0))
        end
        -- [通用] 复活吧爱人觉醒2: 被复活者额外回复20%治疗量（任何治疗者都生效果
        if target and target._reviveHealBoost and target.hp > 0 then
            local bonusHeal = math.floor((result.healAmount or 0) * 0.30 + 0.5)
            if bonusHeal > 0 and target.attrs then
                target.attrs:heal(bonusHeal)
                target.hp = target.attrs:get(AD.HP)
                if target.hp > target.maxHp then target.hp = target.maxHp end
            end
        end

        -- #9 卡皮巴拉自然之愈：治疗后给目标HOT + 觉醒
        if heroId == 9 and target.hp > 0 then
            local healAmt = result.healAmount or 0
            -- 觉醒1: HOT恢复比例 10%→15%
            local hotPct = 0.10
            if hasAwaken(attacker, 1) then hotPct = 0.15 end
            -- 觉醒7: HOT恢复比例 15%→25%
            if hasAwaken(attacker, 7) then hotPct = 0.25 end
            -- 觉醒4: 治疗暴击时HOT效果翻倍
            local hotMult = 1.0
            if hasAwaken(attacker, 4) and result.isCrit then
                hotMult = 2.0
            end
            local hps = math.floor(healAmt * hotPct * hotMult + 0.5)
            if hps > 0 then
                local hotData = { hps = hps }
                -- 觉醒2: 有HOT的队友获得+10物甲/魔甲
                if hasAwaken(attacker, 2) then
                    hotData.armorBuff = true
                    -- 添加护甲buff（HOT消失时需移除，由SEM管理或update检查）
                    if target.attrs and not SEM.has(target, SEM.HOT) then
                        target.attrs:addModifier("awaken_hot_armor", {
                            { key = AD.PHYS_ARMOR, flat = 10 },
                        })
                    end
                end
                -- 觉醒5: 有HOT的队友受伤减少5%
                if hasAwaken(attacker, 5) then
                    hotData.dmgReduction = true
                end
                SEM.apply(target, SEM.HOT, 5.0, attacker, hotData)
                if hotMult > 1 then
                    talentLog("[Talent] 卡皮巴拉觉醒4: 暴击HOT翻倍 hps=" .. hps)
                end
                local overflow = result.overhealAmount
                if overflow == nil then
                    overflow = math.max(0, (result.healAmount or 0) - (result.appliedHealAmount or 0))
                end
                ETS.onOverflowHeal(attacker, overflow or 0)
            end
            -- 觉醒3: 治疗暴击+15%（永久加成，首次添加成
            if hasAwaken(attacker, 3) and not s.awakFloraHealCrit then
                s.awakFloraHealCrit = true
                if attacker.attrs then
                    attacker.attrs:addModifier("awaken_flora_healcrit", {
                        { key = AD.HEAL_CRIT_RATE, flat = 5 },
                    })
                end
            end
            -- 觉醒6: 治疗加成+15%（永久加成，首次添加成
            if hasAwaken(attacker, 6) and not s.awakFloraHealBonus then
                s.awakFloraHealBonus = true
                if attacker.attrs then
                    attacker.attrs:addModifier("awaken_flora_healbonus", {
                        { key = AD.HEAL_BONUS, flat = 15 },
                    })
                end
            end
        end

        -- #15 复活吧爱人 觉醒: 治疗加成与治疗暴击（永久首次加成)
        if heroId == 15 and target.hp > 0 and result.category == "healing" then
            -- 觉醒2: 治疗加成+15%
            if hasAwaken(attacker, 2) and not s.awakElizHealBonus then
                s.awakElizHealBonus = true
                if attacker.attrs then
                    attacker.attrs:addModifier("awaken_eliz_healbonus", {
                        { key = AD.HEAL_BONUS, flat = 15 },
                    })
                end
            end
            -- 觉醒3: 治疗暴击+10%
            if hasAwaken(attacker, 3) and not s.awakElizHealCrit then
                s.awakElizHealCrit = true
                if attacker.attrs then
                    attacker.attrs:addModifier("awaken_eliz_healcrit", {
                        { key = AD.HEAL_CRIT_RATE, flat = 10 },
                    })
                end
            end
            -- 觉醒2: 复活治疗加成已移至通用治疗处理（任何治疗者都生效果
        end

        -- #23 真布诗人 护盾说唱：溢出治疗转能量护盾 + 有盾队友下次攻击附带神圣伤
        local healerId = tonumber(attacker.heroId) or heroId
        if healerId == 23 and target.hp > 0 and result.category == "healing" then
            local nGain, tGain = applyElwynEnergyBlessing(attacker, target, result)
            if ((nGain or 0) + (tGain or 0) > 0) or ((target.attrs and ((target.attrs.energyShield or 0) + (target.attrs.tempEnergyShield or 0)) > 0)) then
                if ETS.hasNode(attacker, 4) then
                    target._rhymeShot = math.max(target._rhymeShot or 0, math.floor((result.healAmount or 0) * 0.20 + 0.5))
                end
                local overflow = result.overhealAmount
                if overflow == nil then
                    overflow = math.max(0, (result.healAmount or 0) - (result.appliedHealAmount or 0))
                end
                ETS.onOverflowHeal(attacker, overflow or 0)
            end
        end

        -- 111 激励 治疗时填充目标5%攻击进度 + 3秒治疗加成10%
        if hasAdv(attacker, "adv_111_inspire") and target.hp > 0 then
            local fillPct = 0.25
            local has221 = hasAdv(attacker, "adv_221_war_ritual")
            local has222 = hasAdv(attacker, "adv_222_blood_ritual")

            -- 221 战争之祭: 填充→50%
            if has221 then fillPct = 0.40 end
            -- 222 嗜血祭祀: 填充→100%, →0%概率触发
            if has222 then
                fillPct = 1.0
                if math.random() > 0.40 then
                    -- 未触发
                    goto skip_inspire
                end
            end

            target.atkProgress = math.min(1.0, (target.atkProgress or 0) + fillPct)

            -- 标记目标：下次攻击有特殊效果
            local ts = ensureState(target)
            if has221 then
                ts.inspiredAtkBonus = true  -- 221: 下次攻击+25%伤害
            end
            if has222 then
                ts.inspiredHealBack = true  -- 222: 攻击后回血
            end

            -- 治疗加成+10% (3秒)
            if target.attrs and not has222 then
                target.attrs:addModifier("talent_inspire_heal", {
                    { key = AD.HEAL_BONUS, flat = 10 },
                })
                -- 简单延时：3秒后移除（在update中管理更复杂，这里简化用SEM机制）
            end

            talentLog("[Talent] 激励 " .. target.name .. " 进度+" .. math.floor(fillPct * 100) .. "%")
            ::skip_inspire::
        end

        -- 112 团队治疗: 将治疗量10%分配给全队
        if hasAdv(attacker, "adv_112_group_heal") then
            local healAmt = result.healAmount or 0
            local groupPct = 0.10
            local has223 = hasAdv(attacker, "adv_223_divine_blessing")
            -- 223 神之赐福: 治疗量→三倍(→30%)
            if has223 then groupPct = 0.30 end

            local groupHeal = math.floor(healAmt * groupPct + 0.5)
            if groupHeal > 0 then
                local allyList = isAlly and TAL_BCS.bAllies or TAL_BCS.bEnemies
                for _, ally in ipairs(allyList) do
                    if ally.hp > 0 and ally ~= target then
                        if ally.attrs then
                            -- 223: <20%HP时必定治疗暴击，治疗量×2
                            local actualHeal = groupHeal
                            if has223 then
                                local allyPct = ally.hp / math.max(1, ally.maxHp)
                                if allyPct < 0.20 then
                                    actualHeal = actualHeal * 2
                                end
                            end
                            ally.attrs:heal(actualHeal)
                            -- syncUnitHp 需要通过 ctx 调用，这里直接同步
                            ally.hp = ally.attrs:get(AD.HP)
                            if ally.hp > ally.maxHp then ally.hp = ally.maxHp end
                        end
                    end
                end
            end
        end

        -- 224 神圣惩戒: 40%概率对随机敌人发射惩戒飞弹（治疗量×400%暗影伤害)
        if hasAdv(attacker, "adv_224_divine_punishment") and dealDmgFn then
            if math.random() < 0.40 then
                local healAmt = result.appliedHealAmount or result.healAmount or 0
                if healAmt > 0 then
                    local enemyList = isAlly and TAL_BCS.bEnemies or TAL_BCS.bAllies
                    local alive = getAliveEnemies(enemyList)
                    if #alive > 0 then
                        local randTarget = alive[math.random(#alive)]
                        local baseDmg = healAmt * 4.0
                        local punishDmg, punishCrit = calcTalentFixedDamage(attacker, randTarget, baseDmg, {
                            atkType = AD.ATK_SHADOW,
                        })

                        if result._talentDmgMult and result._talentDmgMult > 1.0 then
                            punishDmg = math.floor(punishDmg * result._talentDmgMult + 0.5)
                        end
                        local rchBonus = RCH.getDamageBonus(attacker, randTarget)
                        if rchBonus > 0 then
                            punishDmg = math.floor(punishDmg * (1 + rchBonus / 100) + 0.5)
                        end
                        local semMult = SEM.getDamageTakenMult(randTarget)
                        if semMult and semMult ~= 1.0 then
                            punishDmg = math.floor(punishDmg * semMult + 0.5)
                        end

                        if punishDmg > 0 and randTarget.hp > 0 then
                            local prefix = punishCrit and "暴击惩戒 " or "惩戒 "
                            dealDmgFn(randTarget, punishDmg, not isAlly, prefix, { 255, 215, 0 }, {
                                talentProjKey = "EF_ZY_224",
                                statCategory = "magical",
                                isCrit = punishCrit,
                                critEligible = true,
                            })
                            talentLog("[Talent] 神圣惩戒 →" .. randTarget.name .. " (" .. punishDmg .. ")")
                        end
                    end
                end
            end
        end
    end

    -- === 激励效果消费（被激励者的攻击后处理） ===
    if result and result.category ~= "healing" and not result.isMiss then
        -- 221 战争之祭: 被激励后攻击伤害+25%（乘法，这里简化为额外伤害)
        if s.inspiredAtkBonus then
            s.inspiredAtkBonus = false
            -- 额外伤害已在攻击中通过modifier处理不太方便,
            -- 这里用dealDmgFn补偿25%
            if dealDmgFn and target.hp > 0 and result.totalDamage then
                local bonusDmg = math.floor(result.totalDamage * 0.25 + 0.5)
                if bonusDmg > 0 then
                    dealDmgFn(target, bonusDmg, not isAlly, "激励", { 255, 200, 50 })
                end
            end
        end
        -- 222 嗜血祭祀: 攻击后回复造成伤害等值HP
        if s.inspiredHealBack then
            s.inspiredHealBack = false
            local totalDmg = result.totalDamage or 0
            if totalDmg > 0 and attacker.attrs then
                attacker.attrs:heal(totalDmg)
                attacker.hp = attacker.attrs:get(AD.HP)
                if attacker.hp > attacker.maxHp then attacker.hp = attacker.maxHp end
                talentLog("[Talent] 嗜血祭祀: " .. attacker.name .. " 回血 " .. totalDmg)
            end
        end
    end

    -- ======== 星图 RUNTIME_ONLY 节点: onAfterAttack 触发 ========

    -- 节点113 秘法印记: 造成魔法伤害时，15%概率使目标受伤+8%，持续5秒）
    if hasStarNode(attacker, 113) then
        if attacker.dmgMainType == "魔法" and target.hp > 0 then
            if math.random() < 0.15 then
                SEM.apply(target, SEM.ARCANE_MARK, 5.0, attacker, { mult = 0.08 })
                talentLog("[Talent] 秘法印记: " .. (attacker.name or "?") .. " →" .. (target.name or "?") .. " 受伤+8% (5s)")
            end
        end
    end

    -- 节点115 斩尽杀绝 暴击时额外伤害= 目标已损失HP% × 30%
    if hasStarNode(attacker, 115) then
        if result and result.isCrit and target.hp > 0 and dealDmgFn then
            local maxHp = target.maxHp or 1
            local lostPct = 1.0 - (target.hp / math.max(1, maxHp))
            local bonusMult = lostPct * 0.30
            local baseDmg = result.totalDamage or 0
            local bonusDmg = math.floor(baseDmg * bonusMult + 0.5)
            if bonusDmg > 0 then
                dealDmgFn(target, bonusDmg, not isAlly, "斩杀 ", { 200, 50, 50 })
                talentLog("[Talent] 斩尽杀绝 " .. (attacker.name or "?") .. " 暴击额外+" .. bonusDmg .. " (已损 " .. math.floor(lostPct * 100) .. "%×30%)")
            end
        end
    end

    -- 节点120 趁胜追击: 连续攻击同一目标，从第2击起每次+2%攻速，最多5层
    if hasStarNode(attacker, 120) and attacker.attrs and target and (not result or result.category ~= "healing") then
        local as = ensureState(attacker)
        if as then
            if as.pursuitTarget == target then
                local stacks = as.pursuitStacks or 0
                if stacks < 5 then
                    as.pursuitStacks = stacks + 1
                end
            else
                as.pursuitTarget = target
                as.pursuitStacks = 0
            end
            attacker.attrs:removeModifier("starmap_pursuit")
            local stacksNow = as.pursuitStacks or 0
            if stacksNow > 0 then
                attacker.attrs:addModifier("starmap_pursuit", {
                    { key = AD.ATK_SPEED, flat = stacksNow * 2 },
                })
            end
            talentLog("[Talent] 趁胜追击: " .. (attacker.name or "?") .. " 层数=" .. tostring(stacksNow))
        end
    end

    -- 节点124 过量治疗: 溢出的治疗量转化为目标能量护盾（转化率30%）
    if teamHasStarNode(124) and result and result.category == "healing" then
        if target and target.hp > 0 and target.attrs then
            local overflow = result.overhealAmount
            if overflow == nil then
                -- 兼容未写入 overhealAmount 的治疗路径
                local healAmt = result.healAmount or 0
                local applied = result.appliedHealAmount or 0
                overflow = math.max(0, healAmt - applied)
            end
            applyOverhealToEnergyShield(target, overflow)
        end
    end

    -- 节点128 共鸣之歌: 攻击/治疗后15%概率全队伤害+5%，持续3秒
    if hasStarNode(attacker, 128) and attackerAllies then
        if math.random() < 0.15 then
            for _, ally in ipairs(attackerAllies) do
                if ally.hp > 0 and ally.attrs then
                    local as = getState(ally)
                    if as then
                        as.resonanceTimer = 3.0
                        ally.attrs:removeModifier("starmap_resonance")
                        ally.attrs:addModifier("starmap_resonance", {
                            { key = AD.DMG_BONUS, flat = 5 },
                        })
                    end
                end
            end
            talentLog("[Talent] 共鸣之歌: " .. (attacker.name or "?") .. " 触发全队伤害+5% (3s)")
        end
    end

    ETS.onAfterAttack(attacker, target, result, isAlly, targetList, dealDmgFn)

    end

    return { onAfterAttack = onAfterAttack }
end

return M
