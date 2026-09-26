-- ============================================================================
-- BattleCombatCombo - 连击额外攻击 / 连击队列更新
-- 从 BattleCombat 抽出；通过 bind(deps) 注入内部 helper，保持原函数名
-- ============================================================================

local CF  = require("systems.CombatFormula")
local TM  = require("systems.ThreatManager")
local SEM = require("systems.StatusEffectManager")
local TAL = require("systems.TalentManager")
local ART = require("systems.ArtifactRuntime")
local NumberUtil = require("core.NumberUtil")
local BattleStats = require("systems.BattleStats")
local GameSFX = require("systems.GameSFX")

local M = {}

function M.bind(deps)
    local BCS = deps.BCS
    local getBCS = deps.getBCS
    local resolveUnitInList = deps.resolveUnitInList
    local resolveDamageTarget = deps.resolveDamageTarget
    local getCardPos = deps.getCardPos
    local playAttackCardAnim = deps.playAttackCardAnim
    local addFloatingText = deps.addFloatingText
    local setRecoil = deps.setRecoil
    local setHitFlash = deps.setHitFlash
    local applyGlobalDmgMult = deps.applyGlobalDmgMult
    local syncUnitHp = deps.syncUnitHp
    local statMetaFromProjOpts = deps.statMetaFromProjOpts
    local dealDamageToUnit = deps.dealDamageToUnit

    -- ======================== 连击额外攻击 ========================

    --- 执行一次连击额外攻击（完整动画+投射�?伤害�?
    ---@param entry table 连击队列条目
    local function performComboAttack(entry)
    local isAlly        = entry.isAlly
    local comboHitIndex = entry.comboHitIndex

    -- ══�?从当前上下文重新获取列表 ══�?
    local allies  = getBCS().ctx.getAllies()
    local enemies = getBCS().ctx.getEnemies()
    local allyList = isAlly and allies or enemies

    -- 使用 targetIsAlly 确定目标列表（支持治疗扩展）
    local tgtIsAlly  = entry.targetIsAlly
    if tgtIsAlly == nil then tgtIsAlly = not isAlly end  -- 兼容旧格式队列条�?
    local targetList = tgtIsAlly and allies or enemies

    -- ══�?重新解析攻击�?══�?
    local attacker, atkIdx = resolveUnitInList(
        allyList, entry.attacker, entry.atkStableId
    )
    if not attacker or attacker.hp <= 0 then
        return  -- 攻击者已死或已不在场，取消连�?
    end

    -- ══�?重新解析目标 ══�?
    local curTarget, tgtIdx = resolveDamageTarget(
        targetList, entry.targetRef, entry.tgtStableId, attacker, isAlly
    )
    if not curTarget then
        return  -- 没有可命中的目标，取消连击
    end

    -- ══�?校验 attrs（连击必须走公式路径�?══�?
    if not attacker.attrs or not curTarget.attrs then
        return
    end

    -- ══�?计算位置（使用实际索引，resolveUnitInList 成功时保证非 nil�?══�?
    local atkCX, atkCY = getCardPos(allyList, atkIdx)    local tgtCX, tgtCY = getCardPos(targetList, tgtIdx)

    -- 播放攻击动画（lunge + return�?
    playAttackCardAnim(attacker, isAlly)

    -- 计算伤害（带连击增伤�?
    local result = CF.calcAttack(attacker.attrs, curTarget.attrs, nil, comboHitIndex)

    if result.isMiss then
        addFloatingText("MISS", tgtCX, tgtCY, { 255, 122, 122 }, false)
        setRecoil(curTarget, isAlly and -1 or 1)
        ART.onDodge(curTarget)
        return
    end

    -- ══�?applyComboHit 闭包变量映射 ══�?
    -- curTgt     = curTarget  (解析后的最新引用，�?getBCS().cardAnims key 一�?
    -- curTgtCX   = tgtCX      (当前帧位�?
    -- curTgtCY   = tgtCY
    -- attacker   = attacker   (解析后的最新引�?
    -- allyList   = allyList   (当前帧列表，用于吸血位置计算)
    -- atkIdx     = atkIdx     (解析返回的索引，用于吸血浮字位置)
    -- result     = result     (本次攻击计算结果)
    local curTgt = curTarget
    local curTgtCX, curTgtCY = tgtCX, tgtCY

    local function applyComboHit()
        local liveTargetList
        if tgtIsAlly then
            liveTargetList = getBCS().ctx.getAllies and getBCS().ctx.getAllies() or targetList
        else
            liveTargetList = getBCS().ctx.getEnemies and getBCS().ctx.getEnemies() or targetList
        end
        targetList = liveTargetList
        local resolved, resolvedIdx = resolveDamageTarget(liveTargetList, curTgt, entry.tgtStableId, attacker, isAlly)
        if not resolved then return end
        curTgt = resolved
        curTgtCX, curTgtCY = getCardPos(liveTargetList, resolvedIdx)
        if not result.hits or not result.hits[1] then return end
        local semMult = SEM.getDamageTakenMult(curTgt)
        local hpBefore = curTgt.hp
        local hit = result.hits[1]
        local finalDmg = (semMult ~= 1.0) and math.floor(hit.damage * semMult) or hit.damage
        finalDmg = applyGlobalDmgMult(finalDmg)
        -- 铁憨憨帝国铁壁：拦截队友伤害（连击目标与主攻击一致）
        local comboTgtIsAlly = not isAlly
        finalDmg = TAL.modifyDamageForTarget(curTgt, finalDmg, comboTgtIsAlly, syncUnitHp, result.category)
        result.damageDealt = finalDmg
        local shieldBefore = (curTgt.attrs.energyShield or 0) + (curTgt.attrs.tempEnergyShield or 0)
        local actual = curTgt.attrs:takeDamage(finalDmg, result.resistance)
        local shieldAfter = (curTgt.attrs.energyShield or 0) + (curTgt.attrs.tempEnergyShield or 0)
        local takenForStats = actual + math.max(0, shieldBefore - shieldAfter)
        ART.checkShieldBreak(curTgt, shieldBefore)
        syncUnitHp(curTgt)

        local baseColor = (result.category == "magical")
            and { 113, 253, 255 } or { 255, 238, 96 }
        local prefix = ""
        local color  = baseColor
        if hit.isCrit then
            prefix = "暴击 "
        end
        if hit.isBlocked then
            prefix = prefix .. "格挡 "
            color  = { 180, 180, 180 }
        end

        -- 护盾吸收灰色飘字（完全吸收时不显示 -0）
        local shieldAbsorb = math.max(0, (takenForStats or 0) - (actual or 0))
        if actual > 0 then
            addFloatingText(prefix .. "-" .. NumberUtil.format(actual), curTgtCX, curTgtCY, color, hit.isCrit, nil, true)
            if shieldAbsorb > 0 then
                addFloatingText("-" .. NumberUtil.format(shieldAbsorb), curTgtCX, curTgtCY,
                    { 168, 168, 168 }, false, nil, true)
            end
        elseif shieldAbsorb > 0 then
            addFloatingText(prefix .. "-" .. NumberUtil.format(shieldAbsorb), curTgtCX, curTgtCY,
                { 168, 168, 168 }, false, nil, true)
        end

        if curTgt.hp <= 0 and hpBefore > 0 then
            local overkill = math.max(0, finalDmg - hpBefore)
            curTgt._overkillRatio = math.min(1.0, overkill / (curTgt.maxHp or hpBefore))
        end

        setRecoil(curTgt, isAlly and -1 or 1)
        setHitFlash(curTgt)
        if actual > 0 then GameSFX.play("hit", BattleStats.mountedTeam()) end
        -- 累计伤害统计（结算面板用�?
        getBCS().unitDamageAccum[attacker] = (getBCS().unitDamageAccum[attacker] or 0) + takenForStats

        -- 战斗统计面板：己方输出 / 己方承伤
        if isAlly then
            BattleStats.recordDamage(attacker, takenForStats, result.category, hit.isCrit)
        else
            BattleStats.recordTaken(curTgt, takenForStats)
        end

        if isAlly then
            TM.onDamageDealt(attacker, result.totalDamage)
        end

        -- 攻击吸血
        if actual > 0 and attacker.hp > 0 and attacker.attrs and ART.canHeal(attacker) then
            local atkHeal = CF.calcAtkHeal(attacker.attrs)
            if atkHeal > 0 then
                local healActual = attacker.attrs:heal(atkHeal)
                syncUnitHp(attacker)
                if healActual > 0 then
                    local aCX, aCY = getCardPos(allyList, atkIdx)
                    addFloatingText("+" .. NumberUtil.format(math.floor(healActual)), aCX, aCY, { 0, 255, 82 }, false)
                end
            end
        end

        -- 连击命中后：让按攻击计数触发的天赋（如熬夜冠军夜华斩）也能被连击推进/触发（仅对应英雄生效）
        TAL.onComboAttack(attacker, curTgt, isAlly, targetList, function(tgt, dmg, isTgtAlly, pfx, clr, projOpts)
            local meta = statMetaFromProjOpts(projOpts)
            local function doTalentDamage()
                local sourceAttacker = (projOpts and projOpts.sourceAttacker) or attacker
                dealDamageToUnit(tgt, dmg, isTgtAlly, pfx or "", clr or { 255, 238, 96 }, sourceAttacker, meta)
            end
            if getBCS().ctx.onTalentDealDamage then
                local lookupList = (isAlly == isTgtAlly) and allyList or targetList
                for li, lu in ipairs(lookupList) do
                    if lu == tgt then
                        local tdCX, tdCY = getCardPos(lookupList, li)
                        local sourceAttacker = (projOpts and projOpts.sourceAttacker) or attacker
                        getBCS().ctx.onTalentDealDamage(sourceAttacker, tgt, tdCX, tdCY, pfx, doTalentDamage, projOpts)
                        break
                    end
                end
            else
                doTalentDamage()
            end
        end, {
            damageDealt = finalDmg,
            totalDamage = actual,
            category = result.category,
            isCrit = hit.isCrit,
        })
    end

    -- 通知 BattleScene（投射物/受击特效�?
    if getBCS().ctx.onAttackHit then
        getBCS().ctx.onAttackHit(attacker, curTgt, atkCX, atkCY, curTgtCX, curTgtCY, result, applyComboHit)
    else
        applyComboHit()
    end
    end

    --- 更新连击队列（每帧调用）
    local function updateComboQueue(dt)
    local i = 1
    while i <= #getBCS().comboQueue do
        local entry = getBCS().comboQueue[i]
        entry.timer = entry.timer + dt
        if entry.timer >= entry.delay then
            performComboAttack(entry)
            table.remove(getBCS().comboQueue, i)
        else
            i = i + 1
        end
    end
    end


    return {
        performComboAttack = performComboAttack,
        updateComboQueue = updateComboQueue,
    }
end

return M
