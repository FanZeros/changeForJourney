-- ============================================================================
-- Talent Elwyn helpers extracted from TalentManager
-- Bound via M.bind(deps); original local function names preserved.
-- ============================================================================

local M = {}

function M.bind(deps)
    local hasAwaken = deps.hasAwaken
    local getState = deps.getState
    local talentLog = deps.talentLog
    local AD = deps.AD

--- 真布诗人 #23：溢出治疗转能量护盾 + 临时护盾
---@param attacker table
---@param target table
---@param result table
---@return number normalGain, number tempGain
local function applyElwynEnergyBlessing(attacker, target, result)
    if not target or not target.attrs or not result then return 0, 0 end

    local overflow = result.overhealAmount
    if overflow == nil then
        overflow = math.max(0, (result.healAmount or 0) - (result.appliedHealAmount or 0))
    end
    overflow = math.floor(overflow + 0.0001)
    if overflow <= 0 then return 0, 0 end

    local convertRate = 1.0
    if hasAwaken(attacker, 2) then convertRate = 1.2 end
    if hasAwaken(attacker, 6) and result.isCrit then
        convertRate = convertRate + 0.5
    end

    local esGain = math.floor(overflow * convertRate + 0.5)
    if esGain <= 0 then return 0, 0 end

    -- final[ENERGY_SHIELD] 可能为浮点；Lua 5.4 的 string.format %d 不接受非整数
    local maxES = math.floor((target.attrs.final[AD.ENERGY_SHIELD] or 0) + 0.0001)
    if maxES <= 0 then return 0, 0 end

    local curES = math.floor(math.min(maxES, target.attrs.energyShield or 0) + 0.0001)
    local room = math.max(0, maxES - curES)
    local toNormal = math.min(room, esGain)
    if toNormal > 0 then
        target.attrs.energyShield = curES + toNormal
    end

    local tempGain = 0
    local remaining = esGain - toNormal
    if remaining > 0 then
        local tempCapPct = 0.50
        if hasAwaken(attacker, 1) then tempCapPct = tempCapPct + 0.10 end
        if hasAwaken(attacker, 5) then tempCapPct = tempCapPct + 0.20 end
        local tempCap = math.floor(maxES * tempCapPct + 0.5)
        local curTemp = math.floor(target.attrs.tempEnergyShield or 0)
        tempGain = math.min(math.max(0, tempCap - curTemp), remaining)
        if tempGain > 0 then
            target.attrs.tempEnergyShield = curTemp + tempGain
            talentLog(string.format("[Talent] 真布诗人 能量祝福：%s 临时护盾+%.0f (上限%.0f)",
                target.name or "?", tempGain, tempCap))
        end
    end

    if toNormal > 0 then
        talentLog(string.format("[Talent] 真布诗人 能量祝福：%s 护盾+%.0f", target.name or "?", toNormal))
    end
    return toNormal, tempGain
end

--- 查找场上存活的真布诗人（觉醒7用）
---@param units table[]
---@return table|nil unit
---@return table|nil state
local function findLivingElwyn(units)
    for _, u in ipairs(units or {}) do
        if u.heroId == 23 and u.hp > 0 then
            return u, getState(u)
        end
    end
    return nil, nil
end

--- 真布诗人觉醒7：护盾清零时触发无敌
---@param ally table
---@param elwyn table
---@param elwynState table
local function tryElwynInvulnOnEsBreak(ally, elwyn, elwynState)
    if not hasAwaken(elwyn, 7) or not ally or ally.hp <= 0 then return end
    if ally._elwynInvulnTimer and ally._elwynInvulnTimer > 0 then return end

    local chance = elwynState.elwynInvulnProcChance or 1.0
    if math.random() >= chance then return end

    ally._elwynInvulnTimer = 2.0
    elwynState.elwynInvulnProcChance = chance * 0.5
    talentLog(string.format("[Talent] 真布诗人 觉醒7：%s 无敌2秒 (下次概率%.0f%%)",
        ally.name or "?", elwynState.elwynInvulnProcChance * 100))
end

    return {
        applyElwynEnergyBlessing = applyElwynEnergyBlessing,
        findLivingElwyn = findLivingElwyn,
        tryElwynInvulnOnEsBreak = tryElwynInvulnOnEsBreak,
    }
end

return M
