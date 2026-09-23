-- ============================================================================
-- TalentFourNew - #18 老六 / #19 哈基米 / #24 加载中 / #25 高ping战士
-- ============================================================================

local AD = require("systems.AttributeDef")
local TM = require("systems.ThreatManager")

local M = {}

function M.bind(deps)
    local hasAwaken = deps.hasAwaken
    local getState = deps.getState
    local talentLog = deps.talentLog
    local getTAL_BCS = deps.getTAL_BCS
    local calcTalentFixedDamage = deps.calcTalentFixedDamage

    local function onBattleStart(unit, s)
        if not unit or not s then return end
        if s.heroId == 18 then
            s.laoliuStealthLeft = hasAwaken(unit, 2) and 6.0 or 4.0
            s.laoliuFirstStrike = true
            unit._laoliuStealthLeft = s.laoliuStealthLeft
            talentLog("[Talent] 老六 蹲人: 隐踪 " .. tostring(s.laoliuStealthLeft) .. "s")
        elseif s.heroId == 19 then
            s.hakimiMerit = 0
        elseif s.heroId == 24 then
            s.loadingBar = 0
            s.loadingIdle = 0
            s.loadingFlushing = false
        elseif s.heroId == 25 then
            s.pingQueue = s.pingQueue or {}
        end
    end

    local function onBeforeAttack(attacker, s)
        if not attacker or not s then return end
        if s.heroId == 18 and s.laoliuFirstStrike and attacker.attrs then
            attacker.attrs:removeModifier("laoliu_first_crit")
            attacker.attrs:addModifier("laoliu_first_crit", {
                { key = AD.CRIT_RATE, flat = 100 },
            })
        end
        if s.heroId == 25 and attacker.attrs then
            local delay = hasAwaken(attacker, 2) and 1.2 or 1.5
            attacker._highPingPending = {
                delay = delay,
                hpPct = (attacker.hp or 0) > 0 and 0 or 0,
            }
        end
    end

    local function onAfterAttack(attacker, target, result, isAlly, targetList, dealDmgFn)
        if not attacker or not result then return end
        local s = getState(attacker)
        if not s then return end

        if s.heroId == 18 then
            if attacker.attrs then
                attacker.attrs:removeModifier("laoliu_first_crit")
            end
            if s.laoliuFirstStrike and not result.isMiss and result.category ~= "healing" then
                s.laoliuFirstStrike = false
                if target and target.attrs then
                    local extra = hasAwaken(attacker, 3) and 0.10 or 0.05
                    target._laoliuStolenArmor = (target._laoliuStolenArmor or 0) + extra
                    talentLog("[Talent] 老六 第一击必暴 + 偷克制 " .. extra)
                end
            end
            return
        end

        if s.heroId == 19 and result.category == "healing" and target and (target.hp or 0) > 0 then
            local need = hasAwaken(attacker, 2) and 4 or 5
            s.hakimiMerit = (s.hakimiMerit or 0) + 1
            if hasAwaken(attacker, 1) and result.isCrit then
                s.hakimiMerit = s.hakimiMerit + 1
            end
            if s.hakimiMerit >= need then
                s.hakimiMerit = 0
                local dur = hasAwaken(attacker, 3) and 4.5 or 3.0
                local red = hasAwaken(attacker, 3) and 0.25 or 0.18
                target._hakimiWard = { t = dur, red = red }
                talentLog("[Talent] 哈基米 清心 →" .. tostring(target.name) .. " -" .. math.floor(red * 100) .. "% " .. dur .. "s")
            end
            return
        end

        if s.heroId == 25 and result.category ~= "healing" and not result.isMiss then
            local dmg = result.totalDamage or 0
            if dmg > 0 and target then
                local delay = hasAwaken(attacker, 2) and 1.2 or 1.5
                local extra = hasAwaken(attacker, 1) and 0.55 or 0.45
                local hpNow = target.hp or 0
                local maxHp = target.maxHp or 1
                s.pingQueue = s.pingQueue or {}
                s.pingQueue[#s.pingQueue + 1] = {
                    t = delay,
                    target = target,
                    dmg = math.floor(dmg * extra + 0.5),
                    hpPctAtFire = hpNow / math.max(1, maxHp),
                    isAlly = isAlly,
                }
                talentLog("[Talent] 高ping战士 延迟入队 " .. tostring(math.floor(dmg * extra + 0.5)) .. " in " .. delay .. "s")
            end
        end
    end

    local function onDamageTaken(unit, attacker, damage, isUnitAlly, result)
        local s = getState(unit)
        if not s then return damage end
        if damage and damage > 0 and unit._hakimiWard and (unit._hakimiWard.t or 0) > 0 then
            damage = math.floor(damage * (1 - (unit._hakimiWard.red or 0.18)) + 0.5)
        end
        if s.heroId == 24 and damage and damage > 0 and (unit.hp or 0) > 0 then
            local rate = hasAwaken(unit, 1) and 0.35 or 0.25
            local capPct = hasAwaken(unit, 2) and 0.14 or 0.10
            local cap = math.floor((unit.maxHp or 1) * capPct + 0.5)
            s.loadingBar = math.min(cap, (s.loadingBar or 0) + math.floor(damage * rate + 0.5))
            s.loadingIdle = 0
        end
        return damage
    end

    local function update(dt, allies, enemies, ctx)
        local dealDamage = ctx and ctx.dealDamage
        for _, ally in ipairs(allies or {}) do
            if (ally.hp or 0) <= 0 then goto continue end
            local s = getState(ally)
            if not s then goto continue end

            if ally._hakimiWard then
                ally._hakimiWard.t = (ally._hakimiWard.t or 0) - dt
                if ally._hakimiWard.t <= 0 then ally._hakimiWard = nil end
            end

            if s.heroId == 18 then
                if (s.laoliuStealthLeft or 0) > 0 then
                    s.laoliuStealthLeft = s.laoliuStealthLeft - dt
                    ally._laoliuStealthLeft = s.laoliuStealthLeft
                    TM.setThreat(ally, 0)
                    if s.laoliuStealthLeft <= 0 then
                        ally._laoliuStealthLeft = nil
                        talentLog("[Talent] 老六 隐踪结束")
                    end
                end
            end

            if s.heroId == 24 then
                s.loadingIdle = (s.loadingIdle or 0) + dt
                local capPct = hasAwaken(ally, 2) and 0.14 or 0.10
                local cap = math.floor((ally.maxHp or 1) * capPct + 0.5)
                local idleLimit = hasAwaken(ally, 3) and 4.0 or 6.0
                if (s.loadingBar or 0) > 0 and ((s.loadingBar >= cap) or s.loadingIdle >= idleLimit) then
                    local bar = s.loadingBar
                    s.loadingBar = 0
                    s.loadingIdle = 0
                    local tgt = nil
                    for _, e in ipairs(enemies or {}) do
                        if (e.hp or 0) > 0 then tgt = e break end
                    end
                    if tgt and dealDamage then
                        local dmg = bar
                        if calcTalentFixedDamage then
                            dmg = select(1, calcTalentFixedDamage(ally, tgt, bar, {
                                atkType = AD.ATK_CRUSH,
                            })) or bar
                        end
                        dealDamage(tgt, dmg, true, "缓冲 ", { 180, 180, 200 }, {
                            instantDamage = true,
                            statCategory = "physical",
                        })
                        TM.addThreat(ally, math.floor(bar * 0.8 + 0.5))
                        talentLog("[Talent] 加载中 缓冲圈吐出 " .. tostring(dmg))
                    end
                end
            end

            if s.heroId == 25 and s.pingQueue and dealDamage then
                local i = 1
                while i <= #s.pingQueue do
                    local entry = s.pingQueue[i]
                    entry.t = entry.t - dt
                    if entry.t <= 0 then
                        local tgt = entry.target
                        if tgt and (tgt.hp or 0) > 0 then
                            local hpPct = (tgt.hp or 0) / math.max(1, tgt.maxHp or 1)
                            local dmg = entry.dmg or 0
                            local bonus = hasAwaken(ally, 1) and 0.50 or 0.35
                            if hpPct < (entry.hpPctAtFire or 1) then
                                dmg = math.floor(dmg * (1 + bonus) + 0.5)
                            end
                            if hasAwaken(ally, 3) and hpPct < 0.30 then
                                dmg = math.floor(dmg * 1.25 + 0.5)
                            end
                            dealDamage(tgt, dmg, not entry.isAlly, "高ping ", { 120, 200, 255 }, {
                                instantDamage = true,
                                statCategory = "physical",
                                threatScale = 0.10,
                            })
                            talentLog("[Talent] 高ping战士 延迟结算 " .. tostring(dmg))
                        end
                        table.remove(s.pingQueue, i)
                    else
                        i = i + 1
                    end
                end
            end
            ::continue::
        end
    end

    return {
        onBattleStart = onBattleStart,
        onBeforeAttack = onBeforeAttack,
        onAfterAttack = onAfterAttack,
        onDamageTaken = onDamageTaken,
        update = update,
    }
end

return M
