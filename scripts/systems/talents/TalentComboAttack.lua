-- ============================================================================
-- TalentComboAttack - TAL.onComboAttack 抽出（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local getState = deps.getState
    local wrapDealDmgForLuoxing = deps.wrapDealDmgForLuoxing
    local getLuoxingAccumAmount = deps.getLuoxingAccumAmount
    local addLuoxingWindowDamage = deps.addLuoxingWindowDamage
    local tryYouyeSuperCrit = deps.tryYouyeSuperCrit
    local runSuhuaNightSlash = deps.runSuhuaNightSlash
    local tickSeraMachineGunCount = deps.tickSeraMachineGunCount

    local function onComboAttack(attacker, target, isAlly, targetList, dealDmgFn, comboMeta)
        if not attacker or not dealDmgFn or not targetList then return end
        local s = getState(attacker)
        if not s then return end
        dealDmgFn = wrapDealDmgForLuoxing(attacker, dealDmgFn)
        if s.heroId == 16 and comboMeta and comboMeta.category ~= "healing" then
            local amt = getLuoxingAccumAmount(comboMeta, comboMeta.totalDamage)
            if amt > 0 then
                addLuoxingWindowDamage(attacker, amt, nil, nil)
            end
        end
        if s.heroId == 14 and comboMeta and comboMeta.isCrit then
            tryYouyeSuperCrit(attacker, target, comboMeta, isAlly, dealDmgFn)
        end
        if s.heroId == 11 then
            runSuhuaNightSlash(attacker, s, target, isAlly, targetList, dealDmgFn)
        elseif s.heroId == 22 and attacker.attrs then
            tickSeraMachineGunCount(attacker, s)
        end
    end

    return { onComboAttack = onComboAttack }
end

return M
