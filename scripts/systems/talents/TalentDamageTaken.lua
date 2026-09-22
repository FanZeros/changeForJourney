-- ============================================================================
-- TalentDamageTaken - TAL.onDamageTaken 抽出（玩法不变）
-- ============================================================================

local AD  = require("systems.AttributeDef")
local SEM = require("systems.StatusEffectManager")
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
    local getTAL_BCS = deps.getTAL_BCS
    local getPrimaryAyane = deps.getPrimaryAyane
    local applyAyaneMark = deps.applyAyaneMark
    local tryAlexSilverFlash = deps.tryAlexSilverFlash
    local fireLuoxingFlyingSwords = deps.fireLuoxingFlyingSwords
    local addMelissaStarMarks = deps.addMelissaStarMarks
    local addLuoxingWindowDamage = deps.addLuoxingWindowDamage
    local getLuoxingAccumAmount = deps.getLuoxingAccumAmount
    local applyElwynEnergyBlessing = deps.applyElwynEnergyBlessing
    local runSuhuaNightSlash = deps.runSuhuaNightSlash
    local tickSeraMachineGunCount = deps.tickSeraMachineGunCount
    local findLivingElwyn = deps.findLivingElwyn
    local tryElwynInvulnOnEsBreak = deps.tryElwynInvulnOnEsBreak
    local isHighestThreat = deps.isHighestThreat
    local isMelissaStarGateAttackSourceActive = deps.isMelissaStarGateAttackSourceActive
    local updateMelissaStarGate = deps.updateMelissaStarGate

    local function onDamageTaken(unit, attacker, damage, isUnitAlly, performAttackFn, enemyList, result)
        local TAL_BCS = getTAL_BCS()
        local s = getState(unit)
        if not s then
            print("[TAL.onDamageTaken] WARNING: getState nil! heroId=" .. tostring(unit.heroId) .. " name=" .. tostring(unit.name) .. " attacker=" .. tostring(attacker.name))
            return
        end

        -- ======== 护盾消耗（觉醒6等提供的护盾优先吸收伤害）=======
        if unit.shield and unit.shield.amount > 0 and damage > 0 then
            local absorbed = math.min(unit.shield.amount, damage)
            unit.shield.amount = unit.shield.amount - absorbed
            -- 护盾吸收的伤害回补HP（因为伤害已经从HP扣除了）
            -- 注意：直接操作 attrs.final[AD.HP] 而非调用 heal()；
            -- 因为 heal() 有死亡保护（HP<=0 时拒绝恢复），而护盾回补的语义是
            -- "这部分伤害本不该从HP扣除"，必须无条件回补）
            if absorbed > 0 and unit.attrs then
                local hp = unit.attrs.final[AD.HP]
                local maxHp = unit.attrs.final[AD.MAX_HP]
                unit.attrs.final[AD.HP] = math.min(hp + absorbed, maxHp)
                unit.hp = unit.attrs:get(AD.HP)
                if unit.hp > unit.maxHp then unit.hp = unit.maxHp end
            end
            if unit.shield.amount <= 0 then
                unit.shield = nil
                talentLog("[Talent] 护盾已耗尽")
            else
                talentLog("[Talent] 护盾吸收 " .. absorbed .. " 伤害 (剩余=" .. unit.shield.amount .. ")")
            end
        end

        -- #4 接化发掌门 不屈之盾：格挡成功时回复3%最大生命中+ 觉醒
        if s.heroId == 4 and unit.hp > 0 and result and result.isBlocked then
            local maxHp = unit.maxHp or 1
            -- 觉醒2: 格挡回复从3%→5%
            local healPct = 0.03
            if hasAwaken(unit, 2) then healPct = 0.05 end
            local healAmt = math.floor(maxHp * healPct + 0.5)
            if healAmt > 0 and unit.attrs then
                unit.attrs:heal(healAmt)
                unit.hp = unit.attrs:get(AD.HP)
                if unit.hp > unit.maxHp then unit.hp = unit.maxHp end
                talentLog("[Talent] 接化发掌门 不屈之盾：格挡回复" .. healAmt .. " HP (" .. math.floor(healPct * 100) .. "%)")
            end
            -- 觉醒1: 格挡后仇恨+150
            if hasAwaken(unit, 1) then
                local TM = require("systems.ThreatManager")
                TM.addThreat(unit, 50)
                talentLog("[Talent] 接化发掌门 觉醒1: 格挡→仇恨50")
            end
            -- 觉醒3: 格挡成功使攻击者攻速15%持续2秒
            if hasAwaken(unit, 3) and attacker.hp > 0 and attacker.attrs then
                -- 使用SEM模拟2秒debuff（通过VULNERABLE类型携带数据，或直接用modifier+定时）
                -- 简化实现 直接应用modifier并在update中管理2秒倒计时
                attacker.attrs:removeModifier("awaken_cecilia_slow_" .. tostring(unit))
                attacker.attrs:addModifier("awaken_cecilia_slow_" .. tostring(unit), {
                    { key = AD.ATK_SPEED, flat = -15 },
                })
                -- 记录到状态中用于update清理
                if not s.blockSlowTargets then s.blockSlowTargets = {} end
                s.blockSlowTargets[attacker] = 2.0
                talentLog("[Talent] 接化发掌门 觉醒3: " .. (attacker.name or "攻击者") .. " 攻速-15% (2s)")
            end
            -- 觉醒4: 格挡成功后25%概率使攻击者眩晕1秒）
            if hasAwaken(unit, 4) and attacker.hp > 0 then
                if math.random() < 0.25 then
                    SEM.apply(attacker, SEM.FROZEN, 1.0, unit, { isStun = true })
                    talentLog("[Talent] 接化发掌门 觉醒4: " .. (attacker.name or "攻击者") .. " 被眩晕1s!")
                end
            end
            -- 觉醒6: 10%概率使本次格挡比例为100%（全额抵挡）
            -- → 此效果在calcAttack中应先行判断，这里做补偿伤害返还
            if hasAwaken(unit, 6) then
                if math.random() < 0.10 then
                    -- 全额格挡 →回复本次受到的全部伤害
                    if damage > 0 and unit.attrs then
                        unit.attrs:heal(damage)
                        unit.hp = unit.attrs:get(AD.HP)
                        if unit.hp > unit.maxHp then unit.hp = unit.maxHp end
                        talentLog("[Talent] 接化发掌门 觉醒6: 完美格挡! 回复全部伤害 " .. damage)
                    end
                end
            end
            -- 化劲：格挡掉的伤害进反击池（觉醒7额外再记一份）
            do
                local blockedAmt = result.blockedDamage or math.floor(damage * 0.3 + 0.5)
                if hasAwaken(unit, 7) then
                    blockedAmt = math.floor(blockedAmt * 1.5 + 0.5)
                end
                s.blockAbsorbedDmg = (s.blockAbsorbedDmg or 0) + blockedAmt
                ETS.onBlock(unit, blockedAmt)
                talentLog("[Talent] 接化发掌门 化劲蓄力+" .. blockedAmt .. " (累计=" .. s.blockAbsorbedDmg .. ")")
            end
        end

        -- #8 愤怒的小雀 仇册：记下打过自己的人，优先标记
        if isUnitAlly and attacker and (attacker.hp or 0) > 0 then
            for _, ally in ipairs(TAL_BCS.bAllies or {}) do
                if ally.heroId == 8 and (ally.hp or 0) > 0 then
                    local as = getState(ally)
                    if as then
                        as.feudAttackers = as.feudAttackers or {}
                        as.feudAttackers[attacker] = true
                        if not SEM.has(attacker, SEM.MARKED) then
                            applyAyaneMark(ally, attacker, TAL_BCS.bEnemies or {})
                            talentLog("[Talent] 愤怒的小雀 仇册：记下 " .. (attacker.name or "?"))
                        end
                    end
                    break
                end
            end
        end

        -- #10 铁憨憨「帝国铁壁」：伤害吸收已移至 TAL.modifyDamageForTarget（takeDamage前拦截）

        -- （内鬼觉醒5免疫次数由 RelicConditionHandler.onBeforeTakeDamage 统一消费）

        -- === 转职天赋: 受伤害===

        -- 107 巡游射击: 怪物攻击其他角色后，该角色25%概率立即攻击
        -- 这里处理的是：怪物(attacker)攻击了目标unit)，巡游射击者(ally)延迟反击
        if isUnitAlly and attacker.hp > 0 then
            for _, ally in ipairs(TAL_BCS.bAllies) do
                if ally ~= unit and ally.hp > 0 and hasAdv(ally, "adv_107_patrol_shot") then
                    local chance = 0.25
                    if hasAdv(ally, "adv_213_wind_spirit") then chance = 0.35 end
                    if math.random() < chance then
                        local as = getState(ally)
                        if as then
                            -- 加入延迟队列表秒后触发）
                            as.patrolQueue[#as.patrolQueue + 1] = {
                                target = attacker,
                                timer  = 1.0,
                            }
                        end
                    end
                end
            end
        end

        -- 202 传颂祝福: 累计损失HP，每10%一层→全队伤害+7%
        if hasAdv(unit, "adv_202_praise_blessing") and unit.attrs then
            s.praiseTotalLost = s.praiseTotalLost + damage
            local maxHp = unit.maxHp or 1
            local newStacks = math.min(14, math.floor(s.praiseTotalLost / (maxHp * 0.10)))
            if newStacks > s.praiseStacks then
                s.praiseStacks = newStacks
                -- 更新全队伤害加成
                for _, ally in ipairs(TAL_BCS.bAllies) do
                    if ally.hp > 0 and ally.attrs then
                        ally.attrs:removeModifier("talent_praise")
                        ally.attrs:addModifier("talent_praise", {
                            { key = AD.DMG_BONUS, flat = s.praiseStacks * 7 },
                        })
                    end
                end
                talentLog("[Talent] 传颂祝福 ×" .. s.praiseStacks .. " (全队伤害+" .. (s.praiseStacks * 7) .. "%)")
            end
        end

        -- 203 十字盾守: 受伤+2护甲(3秒, max50）
        if hasAdv(unit, "adv_203_cross_shield") and unit.attrs then
            if s.crossShieldStacks < 50 then
                s.crossShieldStacks = s.crossShieldStacks + 1
                unit.attrs:removeModifier("talent_cross_shield")
                unit.attrs:addModifier("talent_cross_shield", {
                    { key = AD.PHYS_ARMOR, flat = s.crossShieldStacks * 2 },
                })
            end
        end

        -- 204 怒龙反击: 受击→进度条+40%
        if hasAdv(unit, "adv_204_dragon_counter") then
            unit.atkProgress = math.min(1.0, (unit.atkProgress or 0) + 0.40)
            talentLog("[Talent] 怒龙反击: 进度+40%")
        end

        -- 217/218 瞬杀/千面: 受击重置计时
        if hasAdv(unit, "adv_217_instant_kill") or hasAdv(unit, "adv_218_thousand_faces") then
            s.timeSinceHit = 0
            if s.noHitBuffApplied then
                unit.attrs:removeModifier("talent_no_hit")
                s.noHitBuffApplied = false
            end
        end
    end

    return { onDamageTaken = onDamageTaken }
end

return M
