-- ============================================================================
-- CombatFormula - 战斗公式
-- 包含：命中、伤害、暴击、连击、格挡、穿透、治疗、目标选择
-- 所有公式严格对照 基础属性.txt 设计文档
-- ============================================================================

local AD = require("systems.AttributeDef")
local BattleDiag = require("systems.BattleDiag")
local BattleLayout = require("core.BattleLayout")
local CGR -- 延迟加载
local function getCGR()
    if not CGR then CGR = require("systems.ClassGateRuntime") end
    return CGR
end
local MAS -- 延迟加载避免循环依赖
local function getMAS()
    if not MAS then MAS = require("systems.MapAffixSystem") end
    return MAS
end

local CF = {}

-- ======================== 基础公式 ========================

--- 护甲 → 抗性 (0~1)
--- 公式: resistance = 0.01 * armor / (0.01 * armor + 1)
---@param armor number 护甲值
---@return number 0~1 范围的抗性比例
function CF.armorToResistance(armor)
    if armor <= 0 then return 0 end
    return (0.01 * armor) / (0.01 * armor + 1)
end

--- 命中率
--- 公式: hitRate = (命中值 + 基础命中) / (闪避值 + 基础命中)
--- 基础命中 = 150，等值命中/闪避完全抵消，闪避有渐近上限
---@param hitValue number 攻击方命中值
---@param dodgeValue number 防御方闪避值
---@return number 0~1 范围的命中率
function CF.calcHitRate(hitValue, dodgeValue)
    local BASE_HIT = 150
    local numerator   = hitValue + BASE_HIT
    local denominator = dodgeValue + BASE_HIT
    if denominator <= 0 then return 1.0 end
    return math.max(0, math.min(1, numerator / denominator))
end

--- 魔化「最终伤害」独立乘区（百分点）
---@param attrs table|nil UnitAttributes
---@param dmg number
---@return number
function CF.applyFinalDamageBonus(attrs, dmg)
    if not attrs or not attrs.get then return dmg end
    local bonus = attrs:get(AD.FINAL_DAMAGE_BONUS) or 0
    if bonus == 0 then return dmg end
    return dmg * (1 + bonus / 100)
end

--- 实际攻击间隔
--- 公式: actualInterval = baseInterval / (1 + atkSpeed%)
---@param baseInterval number 基础攻击间隔（秒）
---@param atkSpeedPct number 攻击速度百分比
---@return number 秒
function CF.calcActualInterval(baseInterval, atkSpeedPct)
    return baseInterval / (1 + atkSpeedPct / 100)
end

-- ======================== 暴击判定 ========================

--- 暴击概率最多 100%；仅已解锁专属觉醒的单位可将溢出暴击率转为暴伤。
--- 老六觉醒Ⅲ：150% 暴击率、200% 暴伤 → 必暴、300% 暴伤；未解锁仍为 200%。
--- 治疗暴击不走这里。
---@param critRate number 暴击率（百分比）
---@param critDmg number 暴击伤害（百分比）
---@param attrs table|nil 攻击方属性；critOverflowRatio 缺省为 0，不自带转换
---@return number effectiveRate 封顶 100 的暴击率
---@return number effectiveDmg 转化后的暴击伤害
function CF.applyCritOverflow(critRate, critDmg, attrs)
    if critRate > 100 then
        local ratio = math.max(0, tonumber(attrs and attrs.critOverflowRatio) or 0)
        if ratio > 0 then
            critDmg = critDmg * (1 + (critRate - 100) / 100 * ratio)
        end
        critRate = 100
    end
    return critRate, critDmg
end

--- 判定是否暴击并返回暴击倍率
---@param critRate number 暴击率（百分比，如 25 = 25%）
---@param critDmg number 暴击伤害（百分比，如 200 = 200% 即 2 倍伤害）
---@return boolean isCrit
---@return number critMultiplier 暴击倍率（非暴击时为 1.0）
function CF.rollCrit(critRate, critDmg)
    local roll = math.random() * 100
    if roll < critRate then
        return true, critDmg / 100
    end
    return false, 1.0
end

-- ======================== 连击判定 ========================

--- 计算连击次数
--- 超过 100% 时保底额外攻击，剩余部分概率触发
--- 例: 150% → 必定 1 次 + 50% 概率再 1 次
---@param comboRate number 连击概率（百分比）
---@return number 额外攻击次数（0 = 无连击）
function CF.rollComboCount(comboRate)
    if comboRate <= 0 then return 0 end
    local guaranteed = math.floor(comboRate / 100)
    local remainder  = comboRate - guaranteed * 100
    local extra = 0
    if remainder > 0 and math.random() * 100 < remainder then
        extra = 1
    end
    return guaranteed + extra
end

-- ======================== 格挡判定 ========================

--- 判定格挡并返回伤害倍率
---@param blockRate number 格挡概率（百分比）
---@param blockRatio number 格挡比例（百分比，如 60 表示格挡 60% 伤害）
---@return boolean isBlocked
---@return number damageMultiplier 格挡后的伤害倍率（非格挡时为 1.0）
function CF.rollBlock(blockRate, blockRatio)
    if blockRate <= 0 then return false, 1.0 end

    -- 格挡概率支持超过 100%：每满 100% 必定触发一次格挡，余量作为额外一次格挡的概率
    -- 例：150% → 必定 1 次 + 50% 概率第 2 次；250% → 必定 2 次 + 50% 概率第 3 次
    local guaranteed  = math.floor(blockRate / 100)
    local extraChance = blockRate - guaranteed * 100   -- 0~100，额外一次格挡的触发概率
    local blockCount  = guaranteed
    if extraChance > 0 and math.random() * 100 < extraChance then
        blockCount = blockCount + 1
    end

    if blockCount <= 0 then return false, 1.0 end

    -- 多次格挡之间为乘法关系：每一次都在“剩余伤害”上再减免 blockRatio
    -- 例：blockRatio=40 时，单次 ×0.6，两次 ×0.36（0.6 × 0.6）
    local survive = 1 - blockRatio / 100
    if survive < 0 then survive = 0 end
    return true, survive ^ blockCount
end

-- ======================== 克制伤害 ========================

--- 独立伤害只应用一次：按基础克制表分类，不受临时倍率改变优势/劣势归属。
--- 英雄与敌人共用；治疗、中立和绕过克制的混沌不吃这两个属性。
---@param attrs table 攻击方 UnitAttributes
---@param baseTypeMult number 攻击类型对目标护甲的基础倍率
---@return number
function CF.getMatchupDamageMult(attrs, baseTypeMult)
    if not attrs or attrs.artifactChaosDamageMult then return 1.0 end
    local bonus = 0
    if baseTypeMult > 1 then
        bonus = attrs:get(AD.ADVANTAGE_DMG_BONUS)
    elseif baseTypeMult > 0 and baseTypeMult < 1 then
        bonus = attrs:get(AD.DISADVANTAGE_DMG_BONUS)
    end
    return math.max(0, 1 + bonus / 100)
end

-- ======================== 伤害浮动 ========================

--- 计算独立的固有伤害波动；端点不读取优势/劣势属性。
---@param baseDmg number 基础伤害
---@param minBonus number 下端点相对偏移百分比
---@param maxBonus number 上端点相对偏移百分比
---@return number 浮动后的伤害
function CF.rollDamageRange(baseDmg, minBonus, maxBonus)
    local minMult = 1 + minBonus / 100
    local maxMult = 1 + maxBonus / 100
    if minMult > maxMult then minMult, maxMult = maxMult, minMult end
    local mult = minMult + math.random() * (maxMult - minMult)
    return baseDmg * mult
end

-- ======================== 目标选择 ========================

--- 按仇恨值加权随机选择目标
---@param units table 存活单位列表，每个元素需要有 attrs:get(AD.THREAT)
---@return number 被选中单位在列表中的索引（1-based），0 = 无有效目标
function CF.selectTarget(units)
    local totalThreat = 0
    local alive = {}

    for i, u in ipairs(units) do
        if u.attrs and u.attrs:isAlive() and not u.artifactUntargetable then
            local t = u.attrs:get(AD.THREAT)
            if t < 1 then t = 1 end
            -- [前后排] 乘以位置受击权重: 前排(靠中心)被攻击概率显著更高
            t = t * BattleLayout.hitWeight(i)
            totalThreat = totalThreat + t
            alive[#alive + 1] = { index = i, threat = t }
        end
    end

    if #alive == 0 then return 0 end
    if #alive == 1 then return alive[1].index end

    local roll = math.random() * totalThreat
    local cumulative = 0
    for _, a in ipairs(alive) do
        cumulative = cumulative + a.threat
        if roll <= cumulative then
            return a.index
        end
    end
    return alive[#alive].index
end

-- ======================== 完整伤害计算 ========================

--- 计算一次攻击的完整伤害（单次命中）
--- comboHitIndex 用于连击增伤：0=普通攻击，1=第1次连击，2=第2次连击...
---@param attacker table UnitAttributes 实例
---@param defender table UnitAttributes 实例
---@param atkType number|nil 攻击类型（nil 则用 attacker.atkType）
---@param comboHitIndex number|nil 连击序号（0=普通，>=1=连击额外攻击），默认0
---@return table result { damage, isCrit, isBlocked, isHit, isMiss, category, comboCount, hits[] }
function CF.calcAttack(attacker, defender, atkType, comboHitIndex)
    comboHitIndex = comboHitIndex or 0
    atkType = atkType or attacker.atkType or AD.ATK_SLASH
    local category = AD.getAtkCategory(atkType)
    local armorType = defender.armorType or AD.ARMOR_LEATHER
    local chaosMult = attacker.artifactChaosDamageMult

    local result = {
        category   = category,
        atkType    = atkType,
        isHit      = false,
        isMiss     = false,
        totalDamage = 0,
        comboCount = 0,
        hits       = {},   -- 每次命中的详细信息
    }

    -- 神圣（治疗）走治疗逻辑
    if category == "healing" then
        return CF.calcHealAttack(attacker, defender, atkType)
    end

    -- ---- 1. 命中判定 ----
    local hitRate = CF.calcHitRate(
        attacker:get(AD.HIT_VALUE),
        defender:get(AD.DODGE)
    )
    if math.random() > hitRate then
        result.isMiss = true
        return result
    end
    result.isHit = true

    -- ---- 2. 基础攻击力 ----
    local baseAtk
    if category == "physical" then
        baseAtk = attacker:get(AD.PHYS_ATK)
    else
        baseAtk = attacker:get(AD.MAG_ATK)
    end

    -- ---- 2b. 攻击伤害系数（角色配置表） ----
    local atkCoeff = attacker.atkCoeff or 1.0
    baseAtk = baseAtk * atkCoeff

    -- ---- 3. 伤害加成（加法叠加） ----
    local dmgBonusPct = attacker:get(AD.DMG_BONUS)
    if chaosMult then
        dmgBonusPct = dmgBonusPct + attacker:get(AD.PHYS_DMG_BONUS) + attacker:get(AD.MAG_DMG_BONUS)
    elseif category == "physical" then
        dmgBonusPct = dmgBonusPct + attacker:get(AD.PHYS_DMG_BONUS)
    else
        dmgBonusPct = dmgBonusPct + attacker:get(AD.MAG_DMG_BONUS)
    end

    -- ---- 4. 暴击判定 ----
    local critRate = attacker:get(AD.CRIT_RATE)
    local critDmg  = attacker:get(AD.CRIT_DMG)
    if category == "physical" then
        critRate = critRate + attacker:get(AD.PHYS_CRIT_RATE)
        critDmg  = critDmg  + attacker:get(AD.PHYS_CRIT_DMG)
    else
        critRate = critRate + attacker:get(AD.MAG_CRIT_RATE)
        critDmg  = critDmg  + attacker:get(AD.MAG_CRIT_DMG)
    end
    if attacker.artifactCritRateMult then
        critRate = critRate * attacker.artifactCritRateMult
    end
    if attacker.artifactCritDmgMult then
        critDmg = critDmg * attacker.artifactCritDmgMult
    end
    -- 觉醒: 感电目标额外受暴击概率（Luna觉醒7 critVuln）
    local SEM = require("systems.StatusEffectManager")
    local shockedEffect = SEM.get(defender, SEM.SHOCKED)
    if shockedEffect and shockedEffect.data and shockedEffect.data.critVuln then
        critRate = critRate + shockedEffect.data.critVuln
    end
    -- 全部修正之后封顶判定概率；暴伤转换需专属觉醒解锁。
    critRate, critDmg = CF.applyCritOverflow(critRate, critDmg, attacker)

    -- ---- 5. 穿透 → 有效护甲（抗性）+ 溢出穿透（独立乘区增伤）----
    -- 溢出穿透 = 穿透超出护甲的部分，按对称公式计算独立增伤倍率
    -- penBonus 有渐近上限：+100% 伤害（穿透→∞时），正常范围 +20%~+50%
    local effectiveArmor, excessPen
    local rawArmor = defender:get(AD.ARMOR)
    -- 地图词缀：蚀甲之触 — 降低目标护甲
    local corrodePct = getMAS().getCorrodeArmorPct(defender)
    if corrodePct > 0 then
        rawArmor = rawArmor * (1 - corrodePct)
    end
    local rawPen
    if chaosMult then
        rawPen = attacker:get(AD.PHYS_PEN) + attacker:get(AD.MAG_PEN)
    else
        rawPen = category == "physical" and attacker:get(AD.PHYS_PEN) or attacker:get(AD.MAG_PEN)
    end
    if attacker.artifactIgnoreArmor then
        rawArmor = 0
    end
    rawArmor = getCGR().adjustArmor(attacker, rawArmor)
    effectiveArmor = math.max(0, rawArmor - rawPen)
    excessPen      = math.max(0, rawPen - rawArmor)
    local resistance = CF.armorToResistance(effectiveArmor)
    if attacker.artifactJudgmentStacks then
        local judgment = attacker.artifactJudgmentStacks[defender]
        if judgment and judgment.category == category then
            resistance = resistance - (tonumber(judgment.value) or 0) / 100
        end
    end
    local penBonus = excessPen > 0 and (1 + (0.01 * excessPen) / (0.01 * excessPen + 1)) or 1.0

    -- ---- 6. 格挡 ----
    local blockRate, blockRatio
    if category == "physical" then
        blockRate  = getMAS().getEffectiveBlockRate(defender, AD.PHYS_BLOCK_RATE)
        blockRatio = defender:get(AD.PHYS_BLOCK_RATIO)
    else
        blockRate  = getMAS().getEffectiveBlockRate(defender, AD.MAG_BLOCK_RATE)
        blockRatio = defender:get(AD.MAG_BLOCK_RATIO)
    end
    local artifactBlockCap = defender.artifactBlockCap
    if artifactBlockCap and blockRate > 100 then
        blockRate = math.min(blockRate, artifactBlockCap)
    end

    -- ---- 7. 类型倍率 ----
    local baseTypeMult = AD.getTypeMult(atkType, armorType)
    local typeMult = getCGR().adjustTypeMult(attacker, defender, baseTypeMult)
    local matchupMult = CF.getMatchupDamageMult(attacker, baseTypeMult)
    result.matchup = baseTypeMult > 1 and "advantage" or (baseTypeMult < 1 and "disadvantage" or "neutral")
    result.matchupDamageMult = matchupMult

    -- ---- 8. 连击次数（仅普通攻击时 roll，连击额外攻击不再触发连击） ----
    local comboCount = 0
    if comboHitIndex == 0 then
        comboCount = CF.rollComboCount(attacker:get(AD.COMBO_RATE))
    end
    result.comboCount = comboCount

    -- ---- 9. 计算单次伤害 ----
    local comboDmgUp = attacker:get(AD.COMBO_DMG_UP)
    local hit = {}

    -- 固有波动与克制属性独立；两项加成不再成为随机区间端点。
    local spread = (attacker.dmgSpread or 0) * 100
    local dmg = CF.rollDamageRange(baseAtk, -spread, spread) * matchupMult

    -- 伤害加成
    dmg = dmg * (1 + dmgBonusPct / 100)

    -- 连击增伤（连击额外攻击根据序号叠加增伤）
    if comboHitIndex > 0 then
        dmg = dmg * (1 + comboDmgUp / 100 * comboHitIndex)
    end

    -- 暴击
    local isCrit, critMult = CF.rollCrit(critRate, critDmg)
    hit.isCrit = isCrit
    hit.critMult = critMult  -- 保留倍率供外部暴击压制还原用
    if isCrit then
        dmg = dmg * critMult
    end

    -- 类型倍率
    if chaosMult then
        dmg = dmg * chaosMult
    else
        dmg = dmg * typeMult
    end

    -- 穿透增伤仍在这里。护甲抗性不在这里减：
    -- 护盾按这份原伤吸收，打到生命的部分由 takeDamage 按同一抗性再减。
    dmg = dmg * penBonus

    -- 神器额外伤害（独立乘区，如狂怒沙漏）
    if attacker.artifactExtraDamageMult then
        dmg = dmg * attacker.artifactExtraDamageMult
    end

    -- 魔化最终伤害（独立乘区）
    dmg = CF.applyFinalDamageBonus(attacker, dmg)

    -- 格挡
    -- 保留格挡真正挡掉的原伤，不把护盾吸收或护甲减伤当成反伤基数。
    hit.preBlockDamage = dmg
    local isBlocked, blockMult = CF.rollBlock(blockRate, blockRatio)
    hit.isBlocked = isBlocked
    hit.blockedDamage = isBlocked and math.max(0, dmg * (1 - blockMult)) or 0
    if isBlocked then
        dmg = dmg * blockMult
    end

    -- 最终伤害取整（至少 1）
    dmg = math.max(1, math.floor(dmg + 0.5))
    hit.damage = dmg
    hit.hitIndex = 1

    result.hits[1] = hit
    result.totalDamage = dmg
    result.resistance = resistance

    -- 顶层暴击/格挡状态
    result.isCrit    = hit.isCrit
    result.isBlocked = hit.isBlocked

    return result
end

-- ======================== 治疗计算 ========================

--- 神圣攻击（治疗）计算
---@param healer table UnitAttributes
---@param target table UnitAttributes
---@param atkType number
---@return table result
function CF.calcHealAttack(healer, target, atkType)
    local armorType = target.armorType or AD.ARMOR_LEATHER
    local typeMult = math.abs(AD.getTypeMult(atkType, armorType))  -- 取绝对值

    local baseHeal = healer:get(AD.HEAL_AMOUNT)
    local atkCoeff = healer.atkCoeff or 1.0
    local rawBaseHeal = baseHeal  -- [HealDiag2] 记录原始值
    baseHeal = baseHeal * atkCoeff
    local healBonus = healer:get(AD.HEAL_BONUS)

    -- 治疗量 = 基础治疗量 × 攻击系数 × (1 + 治疗加成%) × 类型倍率
    local heal = baseHeal * (1 + healBonus / 100) * typeMult

    -- 治疗暴击
    local isCrit, critMult = CF.rollCrit(
        healer:get(AD.HEAL_CRIT_RATE),
        healer:get(AD.HEAL_CRIT_DMG)
    )
    if isCrit then
        heal = heal * critMult
    end

    heal = math.max(1, math.floor(heal + 0.5))

    -- [HealDiag2] 记录治疗计算过程
    if BattleDiag.logEnabled and rawBaseHeal <= 0 then
        print(string.format(
            "[HealDiag2] CALC_HEAL rawBase=%.1f atkCoeff=%.2f healBonus=%.1f typeMult=%.2f final=%d"
            .. " healer_base_healAmt=%.1f healer_final_healAmt=%.1f",
            rawBaseHeal, atkCoeff, healBonus, typeMult, heal,
            healer:getBase(AD.HEAL_AMOUNT),
            healer:get(AD.HEAL_AMOUNT)
        ))
    end

    return {
        category    = "healing",
        atkType     = atkType,
        isHit       = true,
        isMiss      = false,
        isCrit      = isCrit,
        isBlocked   = false,
        totalDamage = -heal,   -- 负数表示治疗
        healAmount  = heal,
        comboCount  = 0,
        hits        = { { damage = -heal, isCrit = isCrit, isBlocked = false, hitIndex = 1 } },
    }
end

-- ======================== 独立治疗公式 ========================

--- 通用治疗计算（非攻击型治疗，如技能治疗）
---@param healer table UnitAttributes
---@param baseHeal number|nil 基础治疗量覆盖（nil 则用属性中的 healAmount）
---@return number healAmount 最终治疗量
---@return boolean isCrit
function CF.calcHeal(healer, baseHeal)
    baseHeal = baseHeal or healer:get(AD.HEAL_AMOUNT)
    local healBonus = healer:get(AD.HEAL_BONUS)

    local heal = baseHeal * (1 + healBonus / 100)

    local isCrit, critMult = CF.rollCrit(
        healer:get(AD.HEAL_CRIT_RATE),
        healer:get(AD.HEAL_CRIT_DMG)
    )
    if isCrit then
        heal = heal * critMult
    end

    return math.max(1, math.floor(heal + 0.5)), isCrit
end

-- ======================== 每秒回血 / 攻击回血 ========================

--- 计算每秒回血量（受治疗属性增幅）
---@param unit table UnitAttributes
---@return number
function CF.calcHpRegen(unit)
    local base = unit:get(AD.HP_REGEN)
    if base <= 0 then return 0 end
    local healBonus = unit:get(AD.HEAL_BONUS)
    return base * (1 + healBonus / 100)
end

--- 计算攻击回血量（受治疗属性增幅）
---@param unit table UnitAttributes
---@return number
function CF.calcAtkHeal(unit)
    local base = unit:get(AD.ATK_HEAL)
    if base <= 0 then return 0 end
    local healBonus = unit:get(AD.HEAL_BONUS)
    return base * (1 + healBonus / 100)
end

-- ======================== 异常状态持续时间 ========================

--- 计算异常状态实际持续时间
---@param baseDuration number 基础持续时间（秒）
---@param abnormalRes number 异常抗性（百分比）
---@return number 实际持续时间
function CF.calcAbnormalDuration(baseDuration, abnormalRes)
    local reduction = math.min(abnormalRes, 80) / 100  -- 上限 80%
    return baseDuration * (1 - reduction)
end

return CF
