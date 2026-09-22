-- ============================================================================
-- Talent Alex helpers extracted from TalentManager
-- Bound via M.bind(deps); original local function names preserved.
-- ============================================================================

local ETS = require("systems.ExtraTalentSystem")

local M = {}

function M.bind(deps)
    local hasAwaken = deps.hasAwaken
    local talentLog = deps.talentLog
    local AD = deps.AD
    local SEM = deps.SEM
    local getBattleRefs = deps.getBattleRefs

local function tryAlexSilverFlash(attacker, s, target, isAlly, dealDmgFn, result)
    if not dealDmgFn or not target or target.hp <= 0 or not attacker.attrs or not result then return end

    local hitVal = attacker.attrs:get(AD.HIT_VALUE)
    local extraProc = math.min(20, math.floor(hitVal / 80) * 2)
    local baseProc = hasAwaken(attacker, 1) and 30 or 25
    local procChance = (baseProc + extraProc) / 100 + ETS.getNitroProcBonus(attacker)

    if math.random() >= procChance then return end

    -- 设计：额外造成「本次物理伤害 ×150%/180%」的闪电伤害（已含护甲/暴击，不再二次结算护甲）
    local dmgMult = hasAwaken(attacker, 3) and 1.8 or 1.5
    local physDmg = result.totalDamage or 0
    if physDmg <= 0 then return end

    local bonusDmg = math.floor(physDmg * dmgMult + 0.5)
    -- 觉醒7：额外享受魔法伤害加成（MAG_DMG_BONUS）
    if hasAwaken(attacker, 7) then
        local magDmgBonus = attacker.attrs:get(AD.MAG_DMG_BONUS)
        if magDmgBonus ~= 0 then
            bonusDmg = math.floor(bonusDmg * (1 + magDmgBonus / 100) + 0.5)
        end
    end

    if bonusDmg > 0 then
        dealDmgFn(target, bonusDmg, not isAlly, "氮气", { 200, 230, 255 }, {
            silverFlashVfx = true,
            instantDamage = true,
        })
        -- 氮气贯穿：额外打一名其他存活敌人（对侧）
        local bcs = getBattleRefs and getBattleRefs() or nil
        local pierceList = bcs and (isAlly and bcs.bEnemies or bcs.bAllies) or nil
        if pierceList then
            local others = {}
            for _, u in ipairs(pierceList) do
                if u ~= target and (u.hp or 0) > 0 then
                    others[#others + 1] = u
                end
            end
            if #others > 0 then
                local pierceTgt = others[math.random(#others)]
                local pierceDmg = math.floor(bonusDmg * 0.60 + 0.5)
                if pierceDmg > 0 then
                    dealDmgFn(pierceTgt, pierceDmg, not isAlly, "超车 ", { 180, 220, 255 }, {
                        instantDamage = true,
                    })
                end
            end
        end
    end

    local paralyzeDur = hasAwaken(attacker, 4) and 0.5 or 0.3
    SEM.apply(target, SEM.FROZEN, paralyzeDur, attacker, {})

    if hasAwaken(attacker, 5) then
        s.silverLightProgressBoost = true
    end

    -- 氮气叠加速：每触发 +8% 攻速，最多 5 层
    if attacker.attrs then
        local stacks = math.min(5, (s.nitroStacks or 0) + 1)
        s.nitroStacks = stacks
        local nitroSpd = stacks * 8
        attacker.attrs:removeModifier("talent_nitro_speed")
        attacker.attrs:addModifier("talent_nitro_speed", {
            { key = AD.ATK_SPEED, flat = nitroSpd },
        })
        attacker.atkInterval = attacker.attrs:getActualInterval()
        talentLog(string.format("[Talent] 闪电卖鸡 氮气叠速 ×%d (+%d%%)", stacks, nitroSpd))
        attacker._nitroKill = true
    end

    talentLog(string.format("[Talent] 闪电卖鸡 氮气 → %s (%.0f伤害, 麻痹%.1fs)",
        target.name or "?", bonusDmg, paralyzeDur))
end

    return {
        tryAlexSilverFlash = tryAlexSilverFlash,
    }
end

return M
