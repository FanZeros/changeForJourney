-- ============================================================================
-- TalentEnemyDeath - TAL.onEnemyDeath / TAL.checkMarkTarget 抽出（玩法不变）
-- ============================================================================

local ETS = require("systems.ExtraTalentSystem")
local RCH = require("systems.RelicConditionHandler")
local SEM = require("systems.StatusEffectManager")
local AD  = require("systems.AttributeDef")

local M = {}

function M.bind(deps)
    local getState = deps.getState
    local hasAdv = deps.hasAdv
    local hasAwaken = deps.hasAwaken
    local hasStarNode = deps.hasStarNode
    local talentLog = deps.talentLog
    local getAliveEnemies = deps.getAliveEnemies
    local getPrimaryAyane = deps.getPrimaryAyane
    local applyAyaneMark = deps.applyAyaneMark
    local clearAyaneMarks = deps.clearAyaneMarks
    local getAyaneMarkMult = deps.getAyaneMarkMult
    local hasAnyAyaneMark = deps.hasAnyAyaneMark

    local function checkMarkTarget(allies, enemies)
        local ayane = getPrimaryAyane(allies, false)
        if not ayane then return end
        if hasAnyAyaneMark(enemies) then return end
        local aliveEnemies = getAliveEnemies(enemies)
        if #aliveEnemies == 0 then return end
        local as = getState(ayane)
        local target = nil
        if as and as.feudAttackers then
            for foe, _ in pairs(as.feudAttackers) do
                if foe and (foe.hp or 0) > 0 then
                    target = foe
                    break
                end
            end
        end
        if not target then
            target = aliveEnemies[math.random(#aliveEnemies)]
        end
        applyAyaneMark(ayane, target, enemies)
        talentLog("[Talent] 愤怒的小雀 仇册补标 " .. (target.name or "?")
            .. " (增伤=" .. math.floor(getAyaneMarkMult(ayane) * 100) .. "%)")
    end

    local function onEnemyDeath(deadEnemy, allies, enemies)
        ETS.onEnemyDeath(deadEnemy, allies, enemies)
        for _, ally in ipairs(allies) do
            if ally.hp > 0 then
                local s = getState(ally)

                -- 110 影袭: 敌人死亡→攻击进度+100% + 下次伤害+30%
                if hasAdv(ally, "adv_110_shadow_strike") then
                    ally.atkProgress = 1.0
                    if s then
                        s.shadowStrikeBuff = true
                    end
                    talentLog("[Talent] 影袭: " .. ally.name .. " 进度条已满+ 伤害+30%")
                end

                -- ======== 觉醒: 敌人死亡触发 ========

                -- #11 熬夜冠军 觉醒7: 夜华斩击杀敌人时立即刷新攻击计时
                if s and s.heroId == 11 and hasAwaken(ally, 7) then
                    -- 将攻击计数重置到下次能立即触发夜华斩
                    local slashInterval = 4
                    if hasAwaken(ally, 3) then slashInterval = 3 end
                    -- 设置为 slashInterval-1，这样下次攻击就会触发
                    s.atkCount = slashInterval - 1
                    talentLog("[Talent] 熬夜冠军 觉醒7: 击杀刷新→下次攻击触发夜华斩 (atkCount=" .. s.atkCount .. ")")
                end

                -- #14 内鬼 觉醒5: 击杀随机获得1~2次免疫（共用 RCH.immunityCount）
                if s and s.heroId == 14 and hasAwaken(ally, 5) then
                    local killImmunity = math.random(1, 2)
                    RCH.addImmunityCharges(ally, killImmunity)
                    talentLog("[Talent] 内鬼 觉醒5: 击杀+" .. killImmunity .. "免疫 (剩余" .. RCH.getImmunityCount(ally) .. "次)")
                end

                -- #14 内鬼 觉醒6: 击杀敌人后暴击伤害10%，最多500%
                if s and s.heroId == 14 and hasAwaken(ally, 6) and ally.attrs then
                    s.killCritDmgStacks = math.min(100, s.killCritDmgStacks + 10)
                    ally.attrs:removeModifier("awaken_kill_critdmg")
                    ally.attrs:addModifier("awaken_kill_critdmg", {
                        { key = AD.CRIT_DMG, flat = s.killCritDmgStacks },
                    })
                    talentLog("[Talent] 内鬼 觉醒6: 击杀→暴击伤害" .. s.killCritDmgStacks .. "%/100%")
                end

                -- ======== 星图节点126 杀戮盛宴 击杀敌人后攻速30%，持续5秒）========
                if hasStarNode(ally, 126) and s and ally.attrs then
                    s.slaughterTimer = 5.0
                    ally.attrs:removeModifier("starmap_slaughter")
                    ally.attrs:addModifier("starmap_slaughter", {
                        { key = AD.ATK_SPEED, flat = 30 },
                    })
                    talentLog("[Talent] 杀戮盛宴 " .. (ally.name or "?") .. " 攻速30% (5s)")
                end
            end
        end

        -- #8 愤怒的小雀 仇册：被标记敌人死亡 → 优先传给仇人，否则随机
        local ayane = getPrimaryAyane(allies, false)
        if ayane and SEM.has(deadEnemy, SEM.MARKED) then
            local as = getState(ayane)
            local aliveEnemies = getAliveEnemies(enemies)
            local newTarget = nil
            if as and as.feudAttackers then
                as.feudAttackers[deadEnemy] = nil
                for foe, _ in pairs(as.feudAttackers) do
                    if foe and (foe.hp or 0) > 0 then
                        newTarget = foe
                        break
                    end
                end
            end
            if not newTarget and #aliveEnemies > 0 then
                newTarget = aliveEnemies[math.random(#aliveEnemies)]
            end
            if newTarget then
                applyAyaneMark(ayane, newTarget, enemies)
                talentLog("[Talent] 愤怒的小雀 仇册转移→" .. (newTarget.name or "?")
                    .. " (增伤=" .. math.floor(getAyaneMarkMult(ayane) * 100) .. "%)")
            else
                clearAyaneMarks(enemies)
            end
        end
        checkMarkTarget(allies, enemies)
    end

    return {
        onEnemyDeath = onEnemyDeath,
        checkMarkTarget = checkMarkTarget,
    }
end

return M
