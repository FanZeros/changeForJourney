-- ============================================================================
-- Talent Suhua helpers extracted from TalentManager
-- Bound via M.bind(deps); original local function names preserved.
-- ============================================================================

local M = {}

function M.bind(deps)
    local hasAwaken = deps.hasAwaken
    local talentLog = deps.talentLog
    local AD = deps.AD
    local CF = deps.CF

--- 熬夜冠军「夜华斩」核心：推进攻击计数，满间隔时斩出多道斩击。
--- 主攻击（onAfterAttack）与连击（onComboAttack）共用同一逻辑。
---@param attacker table
---@param s table
---@param target table
---@param isAlly boolean
---@param targetList table
---@param dealDmgFn function
local function runSuhuaNightSlash(attacker, s, target, isAlly, targetList, dealDmgFn)
    -- 觉醒2: 攻击速度+15%（永久，首次添加）
    if hasAwaken(attacker, 2) and not s.awakSuhuaAtkSpd then
        s.awakSuhuaAtkSpd = true
        attacker.attrs:addModifier("awaken_suhua_atkspd", {
            { key = AD.ATK_SPEED, flat = 15 },
        })
    end
    -- 觉醒5: 物理暴击+10%（永久）
    if hasAwaken(attacker, 5) and not s.awakSuhuaCrit then
        s.awakSuhuaCrit = true
        attacker.attrs:addModifier("awaken_suhua_crit", {
            { key = AD.PHYS_CRIT_RATE, flat = 10 },
        })
    end
    -- 觉醒6: 物理暴击伤害+35%（永久）
    if hasAwaken(attacker, 6) and not s.awakSuhuaCritDmg then
        s.awakSuhuaCritDmg = true
        attacker.attrs:addModifier("awaken_suhua_critdmg", {
            { key = AD.CRIT_DMG, flat = 35 },
        })
    end
    s.atkCount = s.atkCount + 1
    -- 觉醒3: 夜华斩间隔缩短为每3攻
    local slashInterval = 4
    if hasAwaken(attacker, 3) then slashInterval = 3 end
    if s.atkCount % slashInterval ~= 0 then return end

    -- 觉醒1: 伤害系数200%→250%
    local slashMult = 2.0
    if hasAwaken(attacker, 1) then slashMult = 2.5 end
    -- 通宵斩：自身生命越低斩越痛（最多 +50%）
    local selfHpPct = attacker.hp / math.max(1, attacker.maxHp or 1)
    slashMult = slashMult * (1.0 + (1.0 - selfHpPct) * 0.50)

    -- 觉醒4: 斩击数从2提升到3
    local slashCount = 2
    if hasAwaken(attacker, 4) then slashCount = 3 end

    -- 收集存活敌人（排除当前目标优先）
    local otherAlive = {}
    for _, u in ipairs(targetList) do
        if u.hp > 0 and u ~= target then
            otherAlive[#otherAlive + 1] = u
        end
    end

    -- 选择斩击目标：优先不同敌人，不够时命中当前目标
    local slashTargets = {}
    local tempOther = {}
    for i, u in ipairs(otherAlive) do tempOther[i] = u end

    for si = 1, slashCount do
        if #tempOther > 0 then
            local ri = math.random(#tempOther)
            slashTargets[si] = tempOther[ri]
            table.remove(tempOther, ri)
        else
            slashTargets[si] = target
        end
    end

    -- 判断是否所有斩击命中同一目标（用于贝塞尔曲线方向）
    local allSame = true
    for si = 2, slashCount do
        if slashTargets[si] ~= slashTargets[1] then allSame = false; break end
    end

    -- 计算斩击伤害（走完整战斗公式：伤害加成、暴击、类型倍率、护甲抗性）
    -- 基础伤害 = physAtk * atkCoeff * slashMult
    local physAtk = attacker.attrs and attacker.attrs:get(AD.PHYS_ATK) or 0
    local atkCoeff = attacker.atkCoeff or 1.0
    local baseSlashDmg = physAtk * atkCoeff * slashMult

    -- 伤害加成%
    local dmgBonusPct = attacker.attrs:get(AD.DMG_BONUS)
        + attacker.attrs:get(AD.PHYS_DMG_BONUS)

    -- 暴击参数
    local critRate = attacker.attrs:get(AD.CRIT_RATE)
        + attacker.attrs:get(AD.PHYS_CRIT_RATE)
    local critDmg = attacker.attrs:get(AD.CRIT_DMG)
        + attacker.attrs:get(AD.PHYS_CRIT_DMG)

    -- 类型倍率（熬夜冠军 ATK_SLASH）
    local atkType = attacker.atkType or AD.ATK_SLASH

    -- 发射斩击（不检测hp > 0，即使目标被普攻击杀也发射）
    local sides = { 1, -1, 0.5 }  -- 贝塞尔方向：左、右、微偏
    for si = 1, slashCount do
        local st = slashTargets[si]

        -- 针对每个目标独立计算护甲抗性和类型倍率
        local armorType = st.armorType or AD.ARMOR_LEATHER
        local effectiveArmor = math.max(0,
            (st.attrs and st.attrs:get(AD.PHYS_ARMOR) or 0)
            - attacker.attrs:get(AD.PHYS_PEN))
        local resistance = CF.armorToResistance(effectiveArmor)
        local typeMult = AD.getTypeMult(atkType, armorType)

        -- 伤害计算流水线
        local dmg = baseSlashDmg
        dmg = dmg * (1 + dmgBonusPct / 100)

        -- 暴击（每道斩击独立判定）
        local isCrit, critMultiplier = CF.rollCrit(critRate, critDmg)
        if isCrit then
            dmg = dmg * critMultiplier
        end

        dmg = dmg * typeMult
        if attacker.attrs.artifactExtraDamageMult then
            dmg = dmg * attacker.attrs.artifactExtraDamageMult
        end
        dmg = CF.applyFinalDamageBonus(attacker.attrs, dmg)
        dmg = dmg * (1 - resistance)
        dmg = math.max(1, math.floor(dmg + 0.5))

        local opts = {
            isCrit = isCrit,
            statCategory = "physical",
            critEligible = true,
        }
        if allSame then
            opts.bezierSide = sides[si] or (si % 2 == 1 and 1 or -1)
        end
        dealDmgFn(st, dmg, not isAlly, "通宵斩", { 255, 50, 80 }, opts)
        attacker._nightSlashKill = true
    end

    talentLog("[Talent] 熬夜冠军 通宵斩：" .. slashCount .. "道斩击(基础=" .. math.floor(baseSlashDmg) .. ")")
end

    return {
        runSuhuaNightSlash = runSuhuaNightSlash,
    }
end

return M
