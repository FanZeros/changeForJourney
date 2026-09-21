-- ============================================================================
-- Talent Melissa helpers extracted from TalentManager
-- Bound via M.bind(deps); original local function names preserved.
-- ============================================================================

local M = {}

function M.bind(deps)
    local hasAwaken = deps.hasAwaken
    local getState = deps.getState
    local ensureState = deps.ensureState
    local getAliveEnemies = deps.getAliveEnemies
    local talentLog = deps.talentLog
    local calcTalentFixedDamage = deps.calcTalentFixedDamage
    local AD = deps.AD
    local SEM = deps.SEM
    local CF = deps.CF
    local BattleCombat = deps.BattleCombat

local function getMelissaStarGateInterval(melissa)
    if hasAwaken(melissa, 3) then return 2.2 end
    return 2.6
end

--- 摘星星星人 #20：星门基础伤害比例；觉醒1/5递进
---@param melissa table
---@return number
local function getMelissaStarGateDmgMult(melissa)
    local base = 3.00
    if hasAwaken(melissa, 5) then
        base = 4.00
    elseif hasAwaken(melissa, 1) then
        base = 3.40
    end
    return base + ETS.getStarGateDmgBonus(melissa)
end

--- 摘星星星人 #20：星门数量；基础1个，觉醒6为2个
---@param melissa table
---@return number
local function getMelissaStarGateCount(melissa)
    local n = hasAwaken(melissa, 6) and 2 or 1
    n = n + ETS.extraStarGates(melissa)
    return math.min(3, n)
end

--- 摘星星星人 #20：觉醒6后星门可在本体死亡后继续攻击
---@param melissa table
---@return boolean
local function canMelissaStarGatePersistAfterDeath(melissa)
    return hasAwaken(melissa, 6) or ETS.starGatePersist(melissa)
end

--- 同步星门表现层状态；ProjectileSystem 根据这些标记绘制死亡后仍存在的星门
---@param melissa table
---@param s table
local function syncMelissaStarGateVisualState(melissa, s)
    if not melissa or not s then return end
    melissa._starGateSummoned = s.starGateSummoned == true
    melissa._starGateCount = s.starGateCount or 0
    melissa._starGatePersistsAfterDeath = canMelissaStarGatePersistAfterDeath(melissa)
end

--- 摘星星星人 #20：星门当前是否仍是可攻击来源
---@param melissa table
---@param s table|nil
---@return boolean
local function isMelissaStarGateAttackSourceActive(melissa, s)
    if not melissa then return false end
    if melissa.hp and melissa.hp > 0 then return true end
    s = s or getState(melissa)
    return canMelissaStarGatePersistAfterDeath(melissa)
        and s ~= nil
        and s.starGateSummoned == true
        and (s.starGateCount or 0) > 0
end

--- 摘星星星人 #20：星门攻速/连击转化。
--- 每100%攻速转化为10%星门提速，每100%连击转化为8%星门提速，最多40%。
---@param melissa table
---@param s table
---@return number interval
---@return number speedFactor
local function getMelissaStarGateEffectiveInterval(melissa, s)
    local baseInterval = getMelissaStarGateInterval(melissa)
    local atkSpeed = melissa.attrs and melissa.attrs:get(AD.ATK_SPEED) or 0
    local comboRate = melissa.attrs and melissa.attrs:get(AD.COMBO_RATE) or 0
    local speedFactor = math.max(0, atkSpeed) * 0.001 + math.max(0, comboRate) * 0.0008
    speedFactor = math.min(0.40, speedFactor)
    local interval = baseInterval / (1 + speedFactor)
    s.starGateSpeedFactor = speedFactor
    s.starGateInterval = interval
    return interval, speedFactor
end

--- 摘星星星人 #20：从本次普攻产生的额外连击积累星痕，单次最多2层。
---@param melissa table
---@param comboCount number|nil
local function addMelissaStarMarks(melissa, comboCount)
    if not melissa or melissa.heroId ~= 20 then return end
    local s = getState(melissa)
    if not s or not comboCount or comboCount <= 0 then return end
    local gained = math.min(2, math.floor(comboCount))
    s.starGateStarMarks = math.min(5, (s.starGateStarMarks or 0) + gained)
    s.starGateLastAttackComboCount = comboCount
    talentLog(string.format("[Talent] 摘星星星人 星痕：+%d，当前%d/5", gained, s.starGateStarMarks))
end

--- 摘星星星人 #20：星痕对本次星门伤害的倍率。
---@param melissa table
---@param s table
---@return number
local function getMelissaStarMarkDamageScale(melissa, s)
    local marks = math.min(5, math.max(0, s and s.starGateStarMarks or 0))
    return 1 + marks * 0.12
end

--- 摘星星星人 #20：计算星门元素类型
---@param melissa table
---@return number
local function getMelissaStarGateResonanceScale(melissa)
    return hasAwaken(melissa, 7) and 1.50 or 1.0
end

--- 摘星星星人 #20：计算星门元素类型
---@param melissa table
---@return number atkType
local function rollMelissaStarGateAtkType(melissa)
    if not hasAwaken(melissa, 2) then return AD.ATK_SHADOW end
    local types = { AD.ATK_ICE, AD.ATK_LIGHTNING, AD.ATK_FIRE }
    return types[math.random(1, #types)] or AD.ATK_SHADOW
end

--- 摘星星星人 #20：星门命中异常状态目标时的伤害倍率
---@param melissa table
---@param target table
---@return number
local function getMelissaStarGateStatusMult(melissa, target)
    if not hasAwaken(melissa, 4) then return 1.0 end
    if SEM.has(target, SEM.FROZEN) or SEM.has(target, SEM.SHOCKED) or SEM.has(target, SEM.BURNING) then
        return 1.5
    end
    return 1.0
end

--- 摘星星星人 #20：单个角色提供的星象共鸣属性。
--- 基础形态读取摘星星星人自身与其他魔法伤害角色；觉醒7读取全队魔法词条。
--- 设计重点：直接继承对应属性；主继承魔法穿透/魔法伤害加成，少量继承魔法攻击加成折算为伤害加成。
---@param unit table
---@param melissa table
---@return table|nil resonance { name=string, magDmgBonus=number, magPen=number, score=number }
local function calcMelissaUnitResonance(unit, melissa)
    if not unit or not unit.attrs then return nil end
    if unit.hp <= 0 and unit ~= melissa then return nil end
    local isAwaken7 = hasAwaken(melissa, 7)
    if not isAwaken7 and unit.dmgMainType ~= "魔法" then return nil end

    local magPen = unit.attrs:get(AD.MAG_PEN) or 0
    local magDmgBonus = unit.attrs:get(AD.MAG_DMG_BONUS) or 0
    local magAtkBonus = unit.attrs:get(AD.MAG_ATK_BONUS) or 0
    local inheritedDmgBonus = math.max(0, magDmgBonus + magAtkBonus * 0.25)
    local inheritedPen = math.max(0, magPen)
    local score = inheritedDmgBonus + inheritedPen * 0.6
    if score <= 0 then return nil end
    return {
        name = unit.name or (unit == melissa and "摘星星星人" or "?"),
        magDmgBonus = inheritedDmgBonus,
        magPen = inheritedPen,
        score = score,
    }
end

--- 摘星星星人 #20：星象共鸣读取人数上限；基础最多3名魔法角色，觉醒7提升至4名
---@param melissa table
---@return number
local function getMelissaStarGateResonanceLimit(melissa)
    return hasAwaken(melissa, 7) and 4 or 3
end

--- 摘星星星人 #20：计算星象共鸣；基础读取摘星星星人自身与魔法角色，觉醒7读取全队。
---@param melissa table
---@param teamUnits table[]|nil
---@return table resonance { magDmgBonus=number, magPen=number, sourceText=string, independentMult=number }
---@return number count
local function calcMelissaTeamResonance(melissa, teamUnits)
    local contributions = {}
    local includeSelf = true
    for _, unit in ipairs(teamUnits or {}) do
        if includeSelf or unit ~= melissa then
            local value = calcMelissaUnitResonance(unit, melissa)
            if value then
                contributions[#contributions + 1] = value
            end
        end
    end
    if #contributions == 0 then return { magDmgBonus = 0, magPen = 0, sourceText = "无", independentMult = 1.0 }, 0 end

    table.sort(contributions, function(a, b) return (a.score or 0) > (b.score or 0) end)
    local resonanceWeight = 1.50
    local totalDmgBonus = 0
    local totalPen = 0
    local sourceParts = {}
    local count = math.min(getMelissaStarGateResonanceLimit(melissa), #contributions)
    for i = 1, count do
        local c = contributions[i]
        local dmgPart = (c.magDmgBonus or 0) * resonanceWeight
        local penPart = (c.magPen or 0) * resonanceWeight
        totalDmgBonus = totalDmgBonus + dmgPart
        totalPen = totalPen + penPart
        sourceParts[#sourceParts + 1] = string.format("%s:魔伤%.1f%%/魔穿%.1f", c.name or "?", dmgPart, penPart)
    end
    local scale = getMelissaStarGateResonanceScale(melissa)
    local finalDmgBonus = totalDmgBonus * scale
    local finalPen = totalPen * scale
    return {
        magDmgBonus = finalDmgBonus,
        magPen = finalPen,
        sourceText = table.concat(sourceParts, "; "),
        independentMult = 1 + finalDmgBonus / 100,
    }, count
end

--- 摘星星星人 #20：召唤战斗中永久存在的星门
---@param melissa table
---@param s table
local function summonMelissaStarGate(melissa, s)
    if not melissa or not s or s.heroId ~= 20 then return end
    s.starGateSummoned = melissa.hp > 0 or canMelissaStarGatePersistAfterDeath(melissa)
    s.starGateCount = getMelissaStarGateCount(melissa)
    s.starGateTimer = 0
    s.starGateStarMarks = 0
    s.starGateLastAttackComboCount = 0
    s.starGateResonanceDamage = 0
    s.starGateResonanceDmgBonus = 0
    s.starGateResonancePen = 0
    s.starGateResonanceUnits = 0
    s.starGateBaseDamage = 0
    s.starGateResonanceSourceText = "无"
    s.starGateResonanceMult = 1.0
    s.starGateTargetTakenMult = 1.0
    s.starGateArtifactExtraMult = 1.0
    s.starGateFinalDamage = 0
    syncMelissaStarGateVisualState(melissa, s)
    talentLog(string.format("[Talent] 摘星星星人 星门召唤：%d个星门永久存在", s.starGateCount))
end

--- 摘星星星人 #20：计算单个星门本次发射伤害
---@param melissa table
---@param target table
---@param teamUnits table[]|nil
---@param dmgScale number|nil
---@return number damage
---@return boolean isCrit
---@return number atkType
local function calcMelissaStarGateDamage(melissa, target, teamUnits, dmgScale)
    if not melissa or not melissa.attrs or not target or target.hp <= 0 then return 0, false, AD.ATK_SHADOW end
    local atkType = rollMelissaStarGateAtkType(melissa)
    local magAtk = melissa.attrs:get(AD.MAG_ATK) or 0
    local atkCoeff = melissa.atkCoeff or melissa.attrs.atkCoeff or 1.0
    local baseDmg = magAtk * atkCoeff * getMelissaStarGateDmgMult(melissa) * (dmgScale or 1.0)
    local resonanceAttrs, resonanceUnits = calcMelissaTeamResonance(melissa, teamUnits)
    local statusMult = getMelissaStarGateStatusMult(melissa, target)
    local rawDmg = baseDmg * statusMult
    if rawDmg <= 0 then return 0, false, atkType end

    local s = getState(melissa)
    if s then
        s.starGateBaseDamage = baseDmg
        s.starGateResonanceDamage = 0
        s.starGateResonanceDmgBonus = resonanceAttrs.magDmgBonus or 0
        s.starGateResonancePen = resonanceAttrs.magPen or 0
        s.starGateResonanceUnits = resonanceUnits
        s.starGateResonanceSourceText = resonanceAttrs.sourceText or "无"
        s.starGateResonanceMult = resonanceAttrs.independentMult or 1.0
    end

    local dmg, isCrit = calcTalentFixedDamage(melissa, target, rawDmg, {
        atkType = atkType,
        extraPen = resonanceAttrs.magPen,
    })
    local resonanceMult = resonanceAttrs.independentMult or 1.0
    if resonanceMult ~= 1.0 then
        dmg = math.max(1, math.floor(dmg * resonanceMult + 0.5))
    end
    local targetTakenMult = SEM.getDamageTakenMult(target)
    if targetTakenMult and targetTakenMult ~= 1.0 then
        dmg = math.max(1, math.floor(dmg * targetTakenMult + 0.5))
    end
    if s then
        s.starGateTargetTakenMult = targetTakenMult or 1.0
        s.starGateArtifactExtraMult = melissa.attrs.artifactExtraDamageMult or 1.0
        s.starGateFinalDamage = dmg
    end
    return dmg, isCrit, atkType
end

--- 摘星星星人 #20：常驻星门发射攻击投射物
---@param melissa table
---@param isAlly boolean
---@param targetList table[]
---@param dealDmgFn function
---@param teamUnits table[]|nil
---@param gateIndex number
---@param gateCount number
---@param preferredTarget table|nil
---@param dmgScale number|nil
---@return boolean fired
local function fireMelissaStarGate(melissa, isAlly, targetList, dealDmgFn, teamUnits, gateIndex, gateCount, preferredTarget, dmgScale)
    if not melissa or not isMelissaStarGateAttackSourceActive(melissa) or not melissa.attrs or not dealDmgFn or not targetList then return false end
    local alive = getAliveEnemies(targetList)
    if #alive == 0 then return false end
    local target = preferredTarget
    if not target or target.hp <= 0 then
        target = alive[math.random(#alive)]
    end
    if not target or target.hp <= 0 then return false end

    local dmg, isCrit, atkType = calcMelissaStarGateDamage(melissa, target, teamUnits, dmgScale)
    if dmg <= 0 then return false end

    dealDmgFn(target, dmg, not isAlly, "星门", { 220, 160, 255 }, {
        sourceAttacker = melissa,
        starGateIndex = gateIndex or 1,
        starGateCount = gateCount or 1,
        starGateRadius = 118,
        statCategory = AD.getAtkCategory(atkType),
        isCrit = isCrit,
        critEligible = true,
        useBasicProjectile = true,
    })
    return true
end

--- 摘星星星人 #20：触发当前所有星门固定周期发射
---@param melissa table
---@param isAlly boolean
---@param targetList table[]
---@param dealDmgFn function
---@param teamUnits table[]|nil
---@param preferredTarget table|nil
---@param dmgScale number|nil
---@return boolean fired
local function triggerMelissaStarGates(melissa, isAlly, targetList, dealDmgFn, teamUnits, preferredTarget, dmgScale)
    if not melissa or not isMelissaStarGateAttackSourceActive(melissa) or not dealDmgFn or not targetList then return false end
    local s = ensureState(melissa)
    if not s.starGateSummoned then
        summonMelissaStarGate(melissa, s)
    end
    s.starGateCount = getMelissaStarGateCount(melissa)
    syncMelissaStarGateVisualState(melissa, s)

    local firedAny = false
    local markScale = dmgScale or getMelissaStarMarkDamageScale(melissa, s)
    for gateIndex = 1, s.starGateCount do
        local okFire, firedOrErr = pcall(function()
            return fireMelissaStarGate(melissa, isAlly, targetList, dealDmgFn, teamUnits, gateIndex, s.starGateCount, preferredTarget, markScale)
        end)
        if okFire then
            firedAny = firedAny or firedOrErr == true
        else
            talentLog("[Talent] 摘星星星人 星门发射失败: " .. tostring(firedOrErr))
        end
    end
    if firedAny then
        s.starGateStarMarks = 0
        s.starGateLastAttackComboCount = 0
        local selfMagDmg = (melissa.attrs and melissa.attrs:get(AD.MAG_DMG_BONUS)) or 0
        talentLog(string.format("[Talent] 摘星星星人 星门：基础%.0f 自身魔伤+%.1f%% 共鸣独立×%.2f 受伤×%.2f 神器额外×%.2f 最终%.0f(魔伤+%.1f%% 魔穿+%.1f %d人) 来源=%s",
            s.starGateBaseDamage or 0,
            selfMagDmg,
            s.starGateResonanceMult or 1.0,
            s.starGateTargetTakenMult or 1.0,
            s.starGateArtifactExtraMult or 1.0,
            s.starGateFinalDamage or 0,
            s.starGateResonanceDmgBonus or 0,
            s.starGateResonancePen or 0,
            s.starGateResonanceUnits or 0,
            s.starGateResonanceSourceText or "无"))
    end
    return firedAny
end

--- 摘星星星人 #20：推进常驻星门召唤物状态；星门按固定间隔自动发射
---@param dt number
---@param melissa table
---@param s table
---@param isAlly boolean
---@param targetList table[]
---@param ctx table
---@param teamUnits table[]|nil
local function updateMelissaStarGate(dt, melissa, s, isAlly, targetList, ctx, teamUnits)
    if not melissa or not s or s.heroId ~= 20 then return end
    if melissa.hp <= 0 and not canMelissaStarGatePersistAfterDeath(melissa) then
        s.starGateSummoned = false
        s.starGateCount = 0
        syncMelissaStarGateVisualState(melissa, s)
        return
    end
    if not s.starGateSummoned then
        summonMelissaStarGate(melissa, s)
    else
        s.starGateCount = getMelissaStarGateCount(melissa)
        syncMelissaStarGateVisualState(melissa, s)
    end

    local interval = getMelissaStarGateEffectiveInterval(melissa, s)
    if interval <= 0 then interval = 1.0 end
    s.starGateTimer = (s.starGateTimer or 0) + dt
    local pendingTicks = math.floor(s.starGateTimer / interval)
    local maxTicks = math.min(3, pendingTicks)
    while s.starGateTimer >= interval and maxTicks > 0 do
        maxTicks = maxTicks - 1
        local dealFn = nil
        if ctx and ctx.dealTalentDamage then
            dealFn = function(tgt, dmg, isTgtAlly, pfx, clr, projOpts)
                ctx.dealTalentDamage(melissa, tgt, dmg, isTgtAlly, pfx, clr, projOpts)
            end
        elseif ctx and ctx.dealDamage then
            dealFn = function(tgt, dmg, isTgtAlly, pfx, clr)
                ctx.dealDamage(tgt, dmg, isTgtAlly, pfx, clr, melissa)
            end
        end
        if not dealFn then
            s.starGateTimer = s.starGateTimer - interval
            break
        end
        local okFire, firedOrErr = pcall(function()
            return triggerMelissaStarGates(melissa, isAlly, targetList, dealFn, teamUnits, nil, nil)
        end)
        if not okFire then
            talentLog("[Talent] 摘星星星人 星门 tick failed: " .. tostring(firedOrErr))
            s.starGateTimer = 0
            break
        end
        s.starGateTimer = s.starGateTimer - interval
    end
end

--- 闪电卖鸡 #21：银光触发
---@param attacker table
---@param s table
---@param target table
---@param isAlly boolean
---@param dealDmgFn function
---@param result table|nil 当次攻击公式结果（银光伤害基于本次物理伤害）

    return {
        getMelissaStarGateInterval = getMelissaStarGateInterval,
        getMelissaStarGateDmgMult = getMelissaStarGateDmgMult,
        getMelissaStarGateCount = getMelissaStarGateCount,
        canMelissaStarGatePersistAfterDeath = canMelissaStarGatePersistAfterDeath,
        syncMelissaStarGateVisualState = syncMelissaStarGateVisualState,
        isMelissaStarGateAttackSourceActive = isMelissaStarGateAttackSourceActive,
        getMelissaStarGateEffectiveInterval = getMelissaStarGateEffectiveInterval,
        addMelissaStarMarks = addMelissaStarMarks,
        getMelissaStarMarkDamageScale = getMelissaStarMarkDamageScale,
        getMelissaStarGateResonanceScale = getMelissaStarGateResonanceScale,
        rollMelissaStarGateAtkType = rollMelissaStarGateAtkType,
        getMelissaStarGateStatusMult = getMelissaStarGateStatusMult,
        calcMelissaUnitResonance = calcMelissaUnitResonance,
        getMelissaStarGateResonanceLimit = getMelissaStarGateResonanceLimit,
        calcMelissaTeamResonance = calcMelissaTeamResonance,
        summonMelissaStarGate = summonMelissaStarGate,
        calcMelissaStarGateDamage = calcMelissaStarGateDamage,
        fireMelissaStarGate = fireMelissaStarGate,
        triggerMelissaStarGates = triggerMelissaStarGates,
        updateMelissaStarGate = updateMelissaStarGate,
    }
end

return M
