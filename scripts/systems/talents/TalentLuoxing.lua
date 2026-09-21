-- ============================================================================
-- Talent Luoxing helpers extracted from TalentManager
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

local function isFlyingSwordTalentDmg(prefix, projOpts)
    if prefix == "灵月飞剑" or prefix == "飞回" then return true end
    if projOpts and (projOpts.flyingSwordIndex or projOpts.flyingSwordOnHit) then return true end
    return false
end

--- 灵月飞剑触发间隔（秒）；觉醒2→4秒，觉醒6→3秒
---@param attacker table
---@return number
local function getLuoxingFlyingSwordInterval(attacker)
    local interval = 5.0
    if hasAwaken(attacker, 2) then interval = 4.0 end
    if hasAwaken(attacker, 6) then interval = 3.0 end
    return interval
end

--- 重置万剑归宗飞剑累计窗口（与 interval 对齐）
local function resetLuoxingFlyingSwordWindow(s, interval)
    s.flyingSwordTimer = 0
    s.flyingSwordDamage = 0
    s.flyingSwordWindowSec = interval
end

--- 万剑归宗窗口累计（普攻/连击/附加天赋伤；不含灵月飞剑）
--- 使用 damageDealt（含护盾吸收）而非 actualDamage（仅 HP）
local function getLuoxingAccumAmount(result, fallback)
    if not result then return fallback or 0 end
    local dealt = result.damageDealt
    if dealt and dealt > 0 then return dealt end
    return result.totalDamage or fallback or 0
end

local function addLuoxingWindowDamage(attacker, amount, prefix, projOpts)
    if not attacker or not amount or amount <= 0 then return end
    local s = getState(attacker)
    if not s or s.heroId ~= 16 then return end
    if isFlyingSwordTalentDmg(prefix, projOpts) then return end
    s.flyingSwordDamage = (s.flyingSwordDamage or 0) + amount
end

--- 包装 dealDmgFn：万剑归宗附加天赋伤害计入飞剑窗口
local function wrapDealDmgForLuoxing(attacker, dealDmgFn)
    if not dealDmgFn then return dealDmgFn end
    local s = getState(attacker)
    if not s or s.heroId ~= 16 then return dealDmgFn end
    return function(tgt, dmg, isTgtAlly, pfx, clr, projOpts)
        dealDmgFn(tgt, dmg, isTgtAlly, pfx, clr, projOpts)
        addLuoxingWindowDamage(attacker, dmg, pfx, projOpts)
    end
end

--- 内鬼攻击暴击率/暴击伤害（与 CombatFormula.calcAttack 一致）
local function getYouyeAttackCritStats(attacker, category)
    local critRate = attacker.attrs:get(AD.CRIT_RATE)
    local critDmg  = attacker.attrs:get(AD.CRIT_DMG)
    if category == "physical" then
        critRate = critRate + attacker.attrs:get(AD.PHYS_CRIT_RATE)
        critDmg  = critDmg  + attacker.attrs:get(AD.PHYS_CRIT_DMG)
    else
        critRate = critRate + attacker.attrs:get(AD.MAG_CRIT_RATE)
        critDmg  = critDmg  + attacker.attrs:get(AD.MAG_CRIT_DMG)
    end
    if attacker.attrs.artifactCritRateMult then
        critRate = critRate * attacker.attrs.artifactCritRateMult
    end
    if attacker.attrs.artifactCritDmgMult then
        critDmg = critDmg * attacker.attrs.artifactCritDmgMult
    end
    return critRate, critDmg
end

--- 内鬼觉醒7：暴击率>100%部分每4%→1%超暴击；超暴击再乘一次暴击伤害
local YOUYE_SUPER_CRIT_RATE_CAP = 20  -- 超暴击概率上限（%），避免高暴击率下无限叠强
local YOUYE_SUPER_CRIT_OVERFLOW_RATIO = 4  -- 溢出暴击率每 N% 转化为 1% 超暴击

local function tryYouyeSuperCrit(attacker, target, result, isAlly, dealDmgFn)
    if not attacker or not hasAwaken(attacker, 7) then return end
    if not result or not result.isCrit or not attacker.attrs then return end
    if not target or target.hp <= 0 or not dealDmgFn then return end

    local critRate, critDmg = getYouyeAttackCritStats(attacker, result.category)
    local superCritRate = math.min(YOUYE_SUPER_CRIT_RATE_CAP, math.max(0, critRate - 100) / YOUYE_SUPER_CRIT_OVERFLOW_RATIO)
    if superCritRate <= 0 or math.random() * 100 >= superCritRate then return end

    local critMult = critDmg / 100
    if critMult <= 1 then return end

    local baseDmg = result.totalDamage or 0
    if baseDmg <= 0 then return end

    local extraDmg = math.floor(baseDmg * (critMult - 1) + 0.5)
    if extraDmg <= 0 then return end

    dealDmgFn(target, extraDmg, not isAlly, "超暴击 ", { 255, 120, 255 }, {
        statCategory = result.category or "magical",
        critEligible = false,
    })
    talentLog(string.format("[Talent] 内鬼 觉醒7: 超暴击 (率=%.1f%% 额外=%d)", superCritRate, extraDmg))
end

--- 万剑归宗 #16：发射灵月飞剑
---@param attacker table
---@param s table
---@param targetList table
---@param isAlly boolean
---@param dealDmgFn function
---@return boolean fired 是否成功发射
---@return boolean consumeWindow 是否消耗本轮间隔（无伤害的空窗仍消耗）
local function fireLuoxingFlyingSwords(attacker, s, targetList, isAlly, dealDmgFn)
    if not attacker or attacker.hp <= 0 or not dealDmgFn or not targetList then return false, false end

    -- 每柄飞剑 = 窗口累计伤害 × 比例（默认50%；觉醒3：60%）
    local swordDmgPct = 0.50 + ETS.getSwordCoeffBonus(attacker)
    if hasAwaken(attacker, 3) then swordDmgPct = swordDmgPct + 0.10 end

    local accumulated = math.floor((s.flyingSwordDamage or 0) + (s.flyingSwordCarryover or 0) + 0.5)
    if accumulated <= 0 then
        return false, true
    end

    local perSwordDmg = math.floor(accumulated * swordDmgPct + 0.5)
    if perSwordDmg <= 0 then
        return false, true
    end

    local alive = getAliveEnemies(targetList)
    if #alive == 0 then
        return false, false
    end

    s.flyingSwordDamage = 0
    s.flyingSwordCarryover = 0

    local minSwords, maxSwords = 3, 6
    if hasAwaken(attacker, 1) then minSwords = 4 end
    if hasAwaken(attacker, 6) then maxSwords = 7 end
    if minSwords > maxSwords then minSwords, maxSwords = maxSwords, minSwords end

    local swordCount = math.random(minSwords, maxSwords)
    swordCount = math.floor(swordCount + 0.5)
    perSwordDmg = math.floor(perSwordDmg + 0.5)
    local flybackChance = hasAwaken(attacker, 7) and 0.50 or (hasAwaken(attacker, 4) and 0.25 or 0)
    local flybackExtraMult = hasAwaken(attacker, 7) and 1.5 or 1.0
    local recordChance = hasAwaken(attacker, 5) and 0.10 or 0

    local function addCarryover(amt)
        s.flyingSwordCarryover = (s.flyingSwordCarryover or 0) + amt
    end

    for i = 1, swordCount do
        local st = alive[math.random(#alive)]
        if st and st.hp > 0 then
            local dmg = perSwordDmg
            local projOpts = {
                flyingSwordIndex = i,
                flyingSwordCount = swordCount,
                threatScale = 0.1, -- 灵月飞剑伤害仅产生 10% 仇恨
            }
            if recordChance > 0 then
                projOpts.recordOnHit = { chance = recordChance, baseDmg = dmg, addCarryover = addCarryover }
            end
            if flybackChance > 0 then
                projOpts.flyingSwordOnHit = {
                    chance       = flybackChance,
                    extraMult    = flybackExtraMult,
                    baseDmg      = dmg,
                    isTargetAlly = not isAlly,
                    recordChance = recordChance,
                    addCarryover = addCarryover,
                }
            end
            local okDmg, dmgErr = pcall(dealDmgFn, st, dmg, not isAlly, "灵月飞剑", { 180, 220, 255 }, projOpts)
            if not okDmg then
                talentLog("[Talent] 万剑归宗 灵月飞剑 dealDmgFn failed: " .. tostring(dmgErr))
            end
        end
    end

    -- Lua 5.4：%d 仅接受整数；属性伤害可能为浮点
    talentLog(string.format("[Talent] 万剑归宗 灵月飞剑：%.0f柄，单柄=%.0f (窗口%.0fs×%.0f%%)",
        swordCount, perSwordDmg, getLuoxingFlyingSwordInterval(attacker), swordDmgPct * 100))
    return true, true
end

--- 摘星星星人 #20：星门固定触发间隔；基础2.6秒，觉醒3缩短为2.2秒
---@param melissa table
---@return number

    return {
        isFlyingSwordTalentDmg = isFlyingSwordTalentDmg,
        getLuoxingFlyingSwordInterval = getLuoxingFlyingSwordInterval,
        resetLuoxingFlyingSwordWindow = resetLuoxingFlyingSwordWindow,
        getLuoxingAccumAmount = getLuoxingAccumAmount,
        addLuoxingWindowDamage = addLuoxingWindowDamage,
        wrapDealDmgForLuoxing = wrapDealDmgForLuoxing,
        getYouyeAttackCritStats = getYouyeAttackCritStats,
        tryYouyeSuperCrit = tryYouyeSuperCrit,
        fireLuoxingFlyingSwords = fireLuoxingFlyingSwords,
    }
end

return M
