-- ============================================================================
-- Talent Rosa helpers extracted from TalentManager
-- Bound via M.bind(deps); original local function names preserved.
-- ============================================================================

local ETS = require("systems.ExtraTalentSystem")
local AC = require("config.AwakeningConfig")

local M = {}

function M.bind(deps)
    local hasAwaken = deps.hasAwaken
    local hasAwakenStage = deps.hasAwakenStage or function(u, stage)
        return AC.hasStage(u.awakeningNodes, stage)
    end
    local getState = deps.getState
    local getBattleRefs = deps.getBattleRefs
    local AD = deps.AD

local function tryRosaBounce(attacker, s, target, isAlly, targetList, dealDmgFn, result)
    if not attacker or not attacker.attrs or not s or not target or not result or not dealDmgFn or not targetList then return end
    local battleRefs = getBattleRefs and getBattleRefs()
    local battleToken = s.epicAttackBattleToken
    local unitBattleToken = attacker._talentBattleToken
    local function currentBattle()
        return (not getState or getState(attacker) == s)
            and (not getBattleRefs or getBattleRefs() == battleRefs)
            and s.epicAttackBattleToken == battleToken
            and attacker._talentBattleToken == unitBattleToken
    end
    local function currentChain()
        return currentBattle() and (attacker.hp or 0) > 0
    end
    if not currentBattle() then return end
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
    local extra = ETS.getOwned(13)
    bounceCount = bounceCount + ETS.getExtraBounces(extra, attacker)
    -- 新Ⅱ成长读取显式实例快照，旧每8击杀增加弹射次数仍沿原ETS读取。
    local resonanceBonus = 0
    local resonating = not attacker._etsDisabled and hasAwakenStage(attacker, 2) and tonumber(attacker.heroId) == 13
    if resonating then
        local growth = ETS.getEpicGrowth(attacker)
        resonanceBonus = 0.10 + math.min(0.20, math.floor(growth.splitKills / 50) * 0.05)
    end

    local baseDmg = result.totalDamage or 0
    local isCrit, category, atkType = result.isCrit, result.category or "physical", result.atkType
    local increasingBounce = hasAwaken(attacker, 4)
    local allowRepeatBounce = hasAwaken(attacker, 7)

    -- 每次主命中独立持有一条链；新普攻不取消已在飞行的旧链。
    local hitTargets = { [target] = true }
    local failedTargets = {}

    local initialRefTargets = battleRefs and (isAlly and battleRefs.bEnemies or battleRefs.bAllies)
    local function pickBounceTarget(chainFrom)
        local candidates = {}
        local currentRefTargets = battleRefs and (isAlly and battleRefs.bEnemies or battleRefs.bAllies)
        -- 入口实参可能比兼容副本refs更新；只在本轮开始后refs真正换表时跟进。
        local liveTargets = currentRefTargets ~= initialRefTargets and currentRefTargets or targetList
        for _, u in ipairs(liveTargets or {}) do
            if u.hp > 0 and u ~= chainFrom and not failedTargets[u] then
                if not allowRepeatBounce and hitTargets[u] then
                    -- skip
                else
                    candidates[#candidates + 1] = u
                end
            end
        end
        if #candidates == 0 then return nil end
        return candidates[math.random(#candidates)], liveTargets
    end

    local function fireBounce(bi, chainFrom, fromX, fromY)
        if not currentChain() then return end
        if bi > bounceCount then return end

        local dmgMult = 0.5 + resonanceBonus
        if increasingBounce then
            dmgMult = dmgMult + bi * 0.15
        end
        local bounceDmg = math.floor(baseDmg * dmgMult + 0.5)
        if bounceDmg <= 0 then return end

        local bounceTarget, liveTargets = pickBounceTarget(chainFrom)
        if not bounceTarget then return end

        local landed = false
        dealDmgFn(bounceTarget, bounceDmg, not isAlly, "弹射 ", { 180, 220, 255 }, {
            sourceAttacker = attacker,
            bounceFromUnit = chainFrom,
            bounceFromX = fromX,
            bounceFromY = fromY,
            target = bounceTarget,
            isRicochet = true,
            chainProjectile = true,
            isCurrentChain = currentChain,
            epicBounceTargetList = resonating and liveTargets or nil,
            isCrit = isCrit,
            statCategory = category,
            atkType = atkType,
            critEligible = false,
            onProjectileLand = function(hx, hy, landedTarget, didHit)
                if landed then return end
                landed = true
                if not currentChain() then return end
                if didHit == false then
                    -- 飞行中死/移除不算命中，不推进段数/倍率，也不把死目标位置当新起点。
                    failedTargets[bounceTarget] = true
                    fireBounce(bi, chainFrom, fromX, fromY)
                    return
                end
                -- 兼容无参落地测试桩；正式回调以实际命中对象和坐标为准。
                local hitTarget = landedTarget or bounceTarget
                hitTargets[hitTarget] = true
                fireBounce(bi + 1, hitTarget, hx, hy)
            end,
        })
    end

    fireBounce(1, target, result.projectileHitX, result.projectileHitY)
end

    return { tryRosaBounce = tryRosaBounce }
end

return M
