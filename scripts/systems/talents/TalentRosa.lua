-- ============================================================================
-- Talent Rosa helpers extracted from TalentManager
-- Bound via M.bind(deps); original local function names preserved.
-- ============================================================================

local ETS = require("systems.ExtraTalentSystem")

local M = {}

function M.bind(deps)
    local hasAwaken = deps.hasAwaken
    local AD = deps.AD

local function tryRosaBounce(attacker, s, target, isAlly, targetList, dealDmgFn, result)
    if not dealDmgFn or not targetList then return end
    -- 觉醒1: 攻速10%（永久，首次添加）
    if hasAwaken(attacker, 1) and not s.awakRosaAtkSpd then
        s.awakRosaAtkSpd = true
        attacker.attrs:addModifier("awaken_rosa_atkspd", {
            { key = AD.ATK_SPEED, flat = 10 },
        })
    end
    -- 觉醒5: 物理攻击加成+25%（永久）
    if hasAwaken(attacker, 5) and not s.awakRosaPhysAtk then
        s.awakRosaPhysAtk = true
        attacker.attrs:addModifier("awaken_rosa_physatk", {
            { key = AD.PHYS_ATK_BONUS, flat = 25 },
        })
    end
    -- 觉醒6: 攻速25%（永久）
    if hasAwaken(attacker, 6) and not s.awakRosaAtkSpd2 then
        s.awakRosaAtkSpd2 = true
        attacker.attrs:addModifier("awaken_rosa_atkspd2", {
            { key = AD.ATK_SPEED, flat = 25 },
        })
    end

    local bounceCount = 1
    if hasAwaken(attacker, 3) then bounceCount = 2 end
    if hasAwaken(attacker, 7) then bounceCount = 3 end
    bounceCount = bounceCount + ETS.getExtraBounces(ETS.getOwned(13), attacker)

    local baseDmg = result.totalDamage or 0
    local allowRepeatBounce = hasAwaken(attacker, 7)

    local hitTargets = { [target] = true }
    s.rosaBounceGen = (s.rosaBounceGen or 0) + 1
    local bounceGen = s.rosaBounceGen

    local function pickBounceTarget(chainFrom)
        local candidates = {}
        for _, u in ipairs(targetList) do
            if u.hp > 0 and u ~= chainFrom then
                if not allowRepeatBounce and hitTargets[u] then
                    -- skip
                else
                    candidates[#candidates + 1] = u
                end
            end
        end
        if #candidates == 0 then return nil end
        return candidates[math.random(#candidates)]
    end

    local function fireBounce(bi, chainFrom)
        if bounceGen ~= s.rosaBounceGen then return end
        if bi > bounceCount then return end

        local dmgMult = 0.5
        if hasAwaken(attacker, 4) then
            dmgMult = 0.5 + bi * 0.15
        end
        local bounceDmg = math.floor(baseDmg * dmgMult + 0.5)
        if bounceDmg <= 0 then return end

        local bounceTarget = pickBounceTarget(chainFrom)
        if not bounceTarget then return end

        hitTargets[bounceTarget] = true
        dealDmgFn(bounceTarget, bounceDmg, not isAlly, "弹射 ", { 180, 220, 255 }, {
            bounceFromUnit = chainFrom,
            target = bounceTarget,
            isRicochet = true,
            isCrit = result.isCrit,
            statCategory = result.category or "physical",
            critEligible = false,
            onProjectileLand = function()
                if bounceGen ~= s.rosaBounceGen then return end
                fireBounce(bi + 1, bounceTarget)
            end,
        })
    end

    fireBounce(1, target)
end

    return { tryRosaBounce = tryRosaBounce }
end

return M
