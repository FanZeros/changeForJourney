-- ============================================================================
-- TalentBeforeAttack - TAL.onBeforeAttack 抽出（玩法不变）
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
    local onFourNewBeforeAttack = deps.onFourNewBeforeAttack

    local function onBeforeAttack(attacker)
        local TAL_BCS = getTAL_BCS()
        local s = getState(attacker)
        if not s then
            print("[TAL.onBeforeAttack] WARNING: getState nil! heroId=" .. tostring(attacker.heroId) .. " name=" .. tostring(attacker.name))
            return
        end
        local heroId = s.heroId

        if onFourNewBeforeAttack then
            onFourNewBeforeAttack(attacker, s)
        end

        -- === 原有英雄天赋 ===

        -- #1 大狗嚼 衔骨狂：HP<70%时攻速+20%，普攻额外撕咬
        if heroId == 1 and attacker.attrs then
            local hpPct = attacker.hp / math.max(1, attacker.maxHp)
            if hpPct < 0.7 and not s.hopeBuff then
                local entries = {
                    { key = AD.ATK_SPEED, flat = 20 },
                }
                -- 觉醒1: 再加攻速10%（合计30%）
                if hasAwaken(attacker, 1) then entries[#entries+1] = { key = AD.ATK_SPEED, flat = 10 } end
                -- 觉醒2: 物穿+10
                if hasAwaken(attacker, 2) then entries[#entries+1] = { key = AD.PHYS_PEN, flat = 10 } end
                -- 觉醒3: 伤害加成+10%
                if hasAwaken(attacker, 3) then entries[#entries+1] = { key = AD.DMG_BONUS, flat = 10 } end
                -- 觉醒5: 护甲+10
                if hasAwaken(attacker, 5) then
                    entries[#entries+1] = { key = AD.PHYS_ARMOR, flat = 10 }
                end
                -- 觉醒6: 攻速25%（额外）
                if hasAwaken(attacker, 6) then entries[#entries+1] = { key = AD.ATK_SPEED, flat = 25 } end
                -- 觉醒7: HP<35%时所有效果翻倍
                if hasAwaken(attacker, 7) and hpPct < 0.35 then
                    -- 翻倍所有flat/pct →
                    for _, e in ipairs(entries) do
                        if e.flat then e.flat = e.flat * 2 end
                        if e.pct then e.pct = e.pct * 2 end
                    end
                end
                attacker.attrs:addModifier("talent_hope", entries)
                s.hopeBuff = true
                talentLog("[Talent] 大狗嚼 衔骨狂：激励(HP=" .. math.floor(hpPct * 100) .. "%)")
            elseif hpPct >= 0.7 and s.hopeBuff then
                attacker.attrs:removeModifier("talent_hope")
                s.hopeBuff = false
            elseif s.hopeBuff and hasAwaken(attacker, 7) then
                -- 觉醒7: 需要重新检测5%阈值切换
                local below35 = hpPct < 0.35
                local wasBelowKey = s.hopeBelowThreshold or false
                if below35 ~= wasBelowKey then
                    s.hopeBelowThreshold = below35
                    -- 重建 modifier
                    attacker.attrs:removeModifier("talent_hope")
                    s.hopeBuff = false
                    -- 下次循环会重新添加
                end
            end
        end

        -- #3 叮咚鸡 已读不回：前两刀 70% 伤害，第三刀 1.8 倍且必暴
        if heroId == 3 and attacker.attrs then
            s.atkCount = s.atkCount + 1
            local forcePrec = s.preciseChain or false
            attacker.attrs:removeModifier("talent_precise")
            s.preciseBuff = false
            if s.atkCount % 3 == 0 or forcePrec then
                -- 觉醒1: 第三刀 1.8→2.2 倍
                local precBonus = hasAwaken(attacker, 1) and 120 or 80
                local entries = {
                    { key = AD.DMG_BONUS, flat = precBonus },
                    { key = AD.PHYS_CRIT_RATE, flat = 100 },
                }
                -- 觉醒4: 无视护甲（穿透9999)
                if hasAwaken(attacker, 4) then
                    entries[#entries+1] = { key = AD.PHYS_PEN, flat = 9999 }
                end
                attacker.attrs:addModifier("talent_precise", entries)
                s.preciseBuff = true
                s.preciseChain = false
                attacker._preciseKill = true
                talentLog("[Talent] 叮咚鸡 已读不回：第" .. s.atkCount .. "次通知到了 ×" .. (1 + precBonus / 100))
            else
                attacker.attrs:addModifier("talent_precise", {
                    { key = AD.DMG_BONUS, flat = -30 },
                })
                s.preciseBuff = false
                attacker._preciseKill = nil
            end
        end

        -- #3 叮咚鸡觉醒2: 物理暴击+5%（永久加成，首次激活时添加成
        if heroId == 3 and hasAwaken(attacker, 2) and not s.awakPrecCritApplied then
            s.awakPrecCritApplied = true
            attacker.attrs:addModifier("awaken_linda_crit", {
                { key = AD.PHYS_CRIT_RATE, flat = 5 },
            })
            -- 觉醒6: 暴击伤害+25%
            if hasAwaken(attacker, 6) then
                attacker.attrs:addModifier("awaken_linda_critdmg", {
                    { key = AD.CRIT_DMG, flat = 25 },
                })
            end
        end

        -- #7 信光机兵 必杀蓄力：蓄满时打贯穿光线；觉醒7才给连击
        if heroId == 7 and attacker.attrs and s.flashReady then
            if hasAwaken(attacker, 7) then
                attacker.attrs:addModifier("talent_flash", {
                    { key = AD.COMBO_RATE, flat = 200 },
                })
                talentLog("[Talent] 信光机兵 必杀蓄力：光线+连击")
            else
                talentLog("[Talent] 信光机兵 必杀蓄力：光线就绪")
            end
        end

        -- #7 信光机兵觉醒效果（非闪光时也生效的永久加成）
        if heroId == 7 and attacker.attrs then
            -- 觉醒1: 连击增伤+5% (永久加成，首次添加
            -- 觉醒4: 连击增伤+10%
            -- 觉醒5: 连击概率+20%
            -- 觉醒6: 连击无法被闪避（通过临时命中值加成实现）
            if not s.awakFlashApplied then
                s.awakFlashApplied = true
                local entries = {}
                local comboDmgBonus = 0
                if hasAwaken(attacker, 1) then comboDmgBonus = comboDmgBonus + 5 end
                if hasAwaken(attacker, 4) then comboDmgBonus = comboDmgBonus + 10 end
                if comboDmgBonus > 0 then
                    entries[#entries+1] = { key = AD.COMBO_DMG_UP, flat = comboDmgBonus }
                end
                if hasAwaken(attacker, 5) then
                    entries[#entries+1] = { key = AD.COMBO_RATE, flat = 20 }
                end
                if #entries > 0 then
                    attacker.attrs:addModifier("awaken_flash_passive", entries)
                end
            end
            -- 觉醒6: 连击无法被闪避，临时命中+9999
            if hasAwaken(attacker, 6) then
                attacker.attrs:addModifier("awaken_flash_hit", {
                    { key = AD.HIT_VALUE, flat = 9999 },
                })
            end
            -- 觉醒7: 连击+100%、连击增伤30%，但只能由闪光协议触发
            -- 非闪光时连击概率清零（在onAfterAttack中处理）
        end

        -- #8 愤怒的小雀觉醒: 攻击标记目标时的临时增益（onAfterAttack中移除）
        if heroId == 8 and attacker.attrs then
            -- 清除上次的临时modifier
            attacker.attrs:removeModifier("awaken_mark_crit")
            attacker.attrs:removeModifier("awaken_mark_first_crit")
            attacker.attrs:removeModifier("awaken_mark_critdmg")
            -- 觉醒3/5: 仅当存在标记目标时才应用暴击加成
            local anyMarked = false
            for _, enemy in ipairs(TAL_BCS.bEnemies) do
                if enemy.hp > 0 and SEM.has(enemy, SEM.MARKED) then
                    anyMarked = true
                    break
                end
            end
            -- 觉醒3: 攻击标记目标暴击+15%（先应用，onAfterAttack中移除）
            if hasAwaken(attacker, 3) and anyMarked then
                attacker.attrs:addModifier("awaken_mark_crit", {
                    { key = AD.PHYS_CRIT_RATE, flat = 15 },
                })
            end
            -- 觉醒5: 对标记目标暴击伤害30%
            if hasAwaken(attacker, 5) and anyMarked then
                attacker.attrs:addModifier("awaken_mark_critdmg", {
                    { key = AD.CRIT_DMG, flat = 30 },
                })
            end
            -- 觉醒6: 首次攻击标记目标必暴
            if hasAwaken(attacker, 6) then
                -- 使用 markFirstHitCrit 跟踪，需在onAfterAttack 中根据目标判断
                -- 先应用必暴buff，onAfterAttack中会根据是否已使用来移除
                -- 需要遍历检查是否有未消费的标记目标
                local hasUnusedTarget = false
                for _, enemy in ipairs(TAL_BCS.bEnemies) do
                    if enemy.hp > 0 and SEM.has(enemy, SEM.MARKED) and not s.markFirstHitCrit[enemy] then
                        hasUnusedTarget = true
                        break
                    end
                end
                if hasUnusedTarget then
                    attacker.attrs:addModifier("awaken_mark_first_crit", {
                        { key = AD.PHYS_CRIT_RATE, flat = 100 },
                    })
                end
            end
        end

        -- #14 内鬼觉醒4: 对新敌人首次攻击必定暴击
        if heroId == 14 and attacker.attrs and hasAwaken(attacker, 4) then
            attacker.attrs:removeModifier("awaken_firsthit_crit")
            -- 先应用，onAfterAttack中根据目标判断是否保留
            local hasNewTarget = false
            for _, enemy in ipairs(TAL_BCS.bEnemies) do
                if enemy.hp > 0 and not s.firstHitTargets[enemy] then
                    hasNewTarget = true
                    break
                end
            end
            if hasNewTarget then
                attacker.attrs:addModifier("awaken_firsthit_crit", {
                    { key = AD.PHYS_CRIT_RATE, flat = 100 },
                })
            end
        end

        -- === 转职天赋: 攻击前 ===

        -- 103 狂暴之血: HP每损失5%, 物攻+2.5%
        if hasAdv(attacker, "adv_103_berserker_blood") and attacker.attrs then
            attacker.attrs:removeModifier("talent_berserker")
            local hpPct = attacker.hp / math.max(1, attacker.maxHp)
            local lostPct = math.floor((1.0 - hpPct) * 100 / 5) -- 5%一阶
            local bonus = lostPct * 2.5
            if bonus > 0 then
                attacker.attrs:addModifier("talent_berserker", {
                    { key = AD.PHYS_ATK_BONUS, flat = bonus },
                })
            end
            -- 205 狂风骤雨: 额外每5%损失→攻速3%, 物暴击1.5%
            if hasAdv(attacker, "adv_205_storm_fury") then
                attacker.attrs:removeModifier("talent_storm")
                if lostPct > 0 then
                    attacker.attrs:addModifier("talent_storm", {
                        { key = AD.ATK_SPEED, flat = lostPct * 3 },
                        { key = AD.PHYS_CRIT_RATE, flat = lostPct * 1.5 },
                    })
                end
            end
        end

        -- 206 嗜血狂怒 HP>50%时每次攻击减3%当前HP
        if hasAdv(attacker, "adv_206_bloodthirst") and attacker.attrs then
            local hpPct = attacker.hp / math.max(1, attacker.maxHp)
            if hpPct > 0.5 then
                local selfDmg = math.floor(attacker.hp * 0.03)
                if selfDmg > 0 then
                    -- FIX: 通过 attrs:takeDamage 同步扣血，避免 unit.hp →attrs.final[HP] 脱节
                    local actualSelfDmg = attacker.attrs:takeDamage(selfDmg)
                    attacker.hp = attacker.attrs:get(AD.HP)
                    if attacker.hp > attacker.maxHp then attacker.hp = attacker.maxHp end
                    if attacker.hp <= 0 then attacker.hp = 1; attacker.attrs.final[AD.HP] = 1 end
                end
            end
        end

        -- 110 影袭: 消费影袭buff →+30%伤害
        if hasAdv(attacker, "adv_110_shadow_strike") and s.shadowStrikeBuff then
            attacker.attrs:addModifier("talent_shadow_strike", {
                { key = AD.DMG_BONUS, flat = 30 },
            })
        end

        -- 219 致命之刃: 重置每轮限制（免费攻击不重置，只有自然充能的攻击才重置）
        if s.lethalBladeUsed then
            if s.lethalBladeSkipReset then
                s.lethalBladeSkipReset = false  -- 这是免费攻击，跳过本次重置
            else
                s.lethalBladeUsed = false  -- 自然充能攻击，解除限制
            end
        end

        -- 109 隐匿暗影状态 暴击+15%, 暴击伤害+30%（由update管理添加/移除)

        -- 217 瞬杀: 5秒未受击→暴击25%（由update管理)
        -- 218 千面: 5秒未受击→攻速50%,伤害+10%（由update管理)

        -- #21 闪电卖鸡 银光：觉醒5 上次触发后填充15%攻击进度；每轮攻击只判定一次银光
        if heroId == 21 then
            s.silverFlashChecked = false
            if s.silverLightProgressBoost then
                attacker.atkProgress = math.min(1.0, (attacker.atkProgress or 0) + 0.15)
                s.silverLightProgressBoost = false
                talentLog("[Talent] 闪电卖鸡 觉醒5：攻击进度+15%")
            end
            -- 觉醒6：每80命中+5护甲（战斗内动态，与命中值挂钩）
            if hasAwaken(attacker, 6) and attacker.attrs then
                local hitVal = attacker.attrs:get(AD.HIT_VALUE)
                local armorBonus = math.floor(hitVal / 80) * 5
                attacker.attrs:removeModifier("awaken_alex_hit_armor")
                if armorBonus > 0 then
                    attacker.attrs:addModifier("awaken_alex_hit_armor", {
                        { key = AD.ARMOR, flat = armorBonus },
                    })
                end
            end
        end

        -- #22 小黑子 法术机关枪：
        -- 普攻与连击计入 machineGunNormalCount；连射弹标记 machineGunBurstShot 不计入，但仍走完整 performAttack
        if heroId == 22 and attacker.attrs then
            s.lastAttackWasBurst = false
            if s.machineGunBurstShot then
                s.machineGunBurstShot = false
                s.lastAttackWasBurst = true
            else
                tickSeraMachineGunCount(attacker, s)
            end
        end
    end

    return { onBeforeAttack = onBeforeAttack }
end

return M
