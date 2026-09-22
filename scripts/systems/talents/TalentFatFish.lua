-- ============================================================================
-- TalentFatFish - #17 蓝色大肥鱼 高压水枪
-- ============================================================================

local AD  = require("systems.AttributeDef")
local SEM = require("systems.StatusEffectManager")

local M = {}

function M.bind(deps)
    local hasAwaken = deps.hasAwaken
    local getState = deps.getState
    local talentLog = deps.talentLog
    local getAliveEnemies = deps.getAliveEnemies
    local calcTalentFixedDamage = deps.calcTalentFixedDamage

    local function getWetMult(unit)
        if hasAwaken(unit, 1) then return 0.30 end
        return 0.20
    end

    local function getWetDuration(unit)
        if hasAwaken(unit, 1) then return 3.0 end
        return 2.0
    end

    local function getSplashMult(unit)
        if hasAwaken(unit, 2) then return 0.55 end
        return 0.40
    end

    local function applyWet(attacker, target)
        if not target or (target.hp or 0) <= 0 then return end
        local data = {
            mult = getWetMult(attacker),
            fromFatFish = true,
        }
        if hasAwaken(attacker, 2) then
            data.atkSpeedDebuff = 10
        end
        if hasAwaken(attacker, 3) then
            data.critVuln = 10
        end
        SEM.apply(target, SEM.VULNERABLE, getWetDuration(attacker), attacker, data)
        if target.attrs and data.atkSpeedDebuff then
            target.attrs:removeModifier("fatfish_wet_as")
            target.attrs:addModifier("fatfish_wet_as", {
                { key = AD.ATK_SPEED, flat = -data.atkSpeedDebuff },
            })
        end
    end

    local function onAfterAttack(attacker, target, result, isAlly, targetList, dealDmgFn)
        if not attacker or not target or not dealDmgFn then return end
        if result and result.isMiss then return end
        if result and result.category == "healing" then return end
        if (target.hp or 0) <= 0 then return end

        applyWet(attacker, target)

        local magAtk = attacker.attrs and (attacker.attrs:get(AD.MAG_ATK) or 0) or 0
        local splashBase = math.floor(magAtk * getSplashMult(attacker) + 0.5)
        if splashBase <= 0 then return end

        local alive = getAliveEnemies(targetList or {})
        local splashTargets = {}
        if hasAwaken(attacker, 3) then
            local wetCount = 0
            for _, u in ipairs(alive) do
                local eff = SEM.get(u, SEM.VULNERABLE)
                if eff and eff.data and eff.data.fromFatFish then
                    wetCount = wetCount + 1
                end
            end
            if wetCount >= 3 then
                for _, u in ipairs(alive) do
                    local eff = SEM.get(u, SEM.VULNERABLE)
                    if eff and eff.data and eff.data.fromFatFish then
                        splashTargets[#splashTargets + 1] = u
                    end
                end
            end
        end
        if #splashTargets == 0 then
            local others = {}
            for _, u in ipairs(alive) do
                if u ~= target then others[#others + 1] = u end
            end
            if #others > 0 then
                splashTargets[1] = others[math.random(#others)]
            end
        end

        for _, splashTarget in ipairs(splashTargets) do
            local dmg = splashBase
            if calcTalentFixedDamage then
                dmg = select(1, calcTalentFixedDamage(attacker, splashTarget, splashBase, {
                    atkType = AD.ATK_ICE,
                }))
            end
            if dmg and dmg > 0 then
                dealDmgFn(splashTarget, dmg, not isAlly, "喷水 ", { 80, 180, 255 }, {
                    instantDamage = true,
                    statCategory = "magical",
                })
                applyWet(attacker, splashTarget)
            end
        end

        talentLog("[Talent] 蓝色大肥鱼 高压水枪 溅射=" .. tostring(#splashTargets))
    end

    return { onAfterAttack = onAfterAttack }
end

return M
