-- ============================================================================
-- TalentModifyDamage - TAL.modifyDamageForTarget 抽出（玩法不变）
-- ============================================================================

local AD  = require("systems.AttributeDef")
local CF  = require("systems.CombatFormula")
local SEM = require("systems.StatusEffectManager")
local ETS = require("systems.ExtraTalentSystem")

local M = {}

function M.bind(deps)
    local getState = deps.getState
    local hasAdv = deps.hasAdv
    local hasAwaken = deps.hasAwaken
    local hasStarNode = deps.hasStarNode
    local talentLog = deps.talentLog
    local getTAL_BCS = deps.getTAL_BCS
    local getMAS = deps.getMAS

    local function modifyDamageForTarget(target, damage, isTargetAlly, syncHpFn, dmgCategory)
        local TAL_BCS = getTAL_BCS()
        if damage <= 0 then return damage end

        if not isTargetAlly then return damage end
        if target._hakimiWard and (target._hakimiWard.t or 0) > 0 then
            damage = math.floor(damage * (1 - (target._hakimiWard.red or 0.18)) + 0.5)
        end

        damage = ETS.absorbWithIceStatue(target, damage, TAL_BCS.bEnemies)
        if damage <= 0 then return 0 end

        -- 真布诗人觉醒7：无敌期间免疫伤害
        if target._elwynInvulnTimer and target._elwynInvulnTimer > 0 then
            return 0
        end

        -- 受伤者是铁憨憨自己则不触发吸收（避免循环）
        local targetState = getState(target)
        if targetState and targetState.heroId == 10 then
            -- 觉醒7: 铁憨憨自身受伤防秒杀
            if hasAwaken(target, 7) and targetState.bulwarkDmgCapCd <= 0 and target.attrs then
                local maxHp = target.attrs.final[AD.MAX_HP] or 1
                local cap = math.floor(maxHp * 0.30)
                if damage > cap then
                    damage = cap
                    targetState.bulwarkDmgCapCd = 8.0
                end
            end
            return damage
        end

        -- 查找存活的铁憨憨
        local rebecca = nil
        local rebeccaState = nil
        for _, ally in ipairs(TAL_BCS.bAllies or {}) do
            local as = getState(ally)
            if as and as.heroId == 10 and ally.hp > 0 then
                rebecca = ally
                rebeccaState = as
                break
            end
        end

        -- 觉醒7: 全队防秒杀（铁憨憨在场，队友单次受伤不超过自身最大生命30%，8秒CD）
        if rebecca and rebeccaState and hasAwaken(rebecca, 7)
           and rebeccaState.bulwarkDmgCapCd <= 0 and target.attrs then
            local allyMaxHp = target.attrs.final[AD.MAX_HP] or 1
            local allyCap = math.floor(allyMaxHp * 0.30)
            if damage > allyCap then
                damage = allyCap
                rebeccaState.bulwarkDmgCapCd = 8.0
            end
        end

        if not rebecca or not rebecca.attrs then return damage end

        -- 计算吸收比例: 基础15%, 觉醒4→20%
        local absorbRate = 0.15
        if hasAwaken(rebecca, 4) then absorbRate = 0.20 end

        local absorbedFromAlly = math.floor(damage * absorbRate + 0.5)
        if absorbedFromAlly <= 0 then return damage end

        -- 转移伤害走铁憨憨自身护甲和格挡
        local transferDmg = absorbedFromAlly
        local CF = require("systems.CombatFormula")
        local category = dmgCategory or "physical"

        -- 1. 护甲抗性减免（统一护甲；能量护盾由 takeDamage 单独消耗，不再当作魔抗）
        local effectiveArmor = rebecca.attrs:get(AD.ARMOR)
        local resistance = CF.armorToResistance(effectiveArmor)
        transferDmg = math.floor(transferDmg * (1 - resistance) + 0.5)

        -- 2. 格挡（含地图词缀格挡压制；超 100% 部分可抵消 debuff）
        local blockRate, blockRatio = 0, 0
        if category == "physical" then
            blockRate = getMAS().getEffectiveBlockRate(rebecca.attrs, AD.PHYS_BLOCK_RATE)
            blockRatio = rebecca.attrs:get(AD.PHYS_BLOCK_RATIO)
        else
            blockRate = getMAS().getEffectiveBlockRate(rebecca.attrs, AD.MAG_BLOCK_RATE)
            blockRatio = rebecca.attrs:get(AD.MAG_BLOCK_RATIO)
        end
        local isBlocked, blockMult = CF.rollBlock(blockRate, blockRatio)
        if isBlocked then
            transferDmg = math.floor(transferDmg * blockMult + 0.5)
        end

        -- 3. 觉醒4: 额外减免15%
        if hasAwaken(rebecca, 4) then
            transferDmg = math.floor(transferDmg * 0.85 + 0.5)
        end

        if transferDmg <= 0 then transferDmg = 1 end
        -- 觉醒7: 防秒杀（转移伤害不超过30%最大HP，8秒CD）
        if hasAwaken(rebecca, 7) and rebeccaState.bulwarkDmgCapCd <= 0 then
            local maxHp = rebecca.attrs.final[AD.MAX_HP] or 1
            local cap = math.floor(maxHp * 0.30)
            if transferDmg > cap then
                transferDmg = cap
                rebeccaState.bulwarkDmgCapCd = 8.0
            end
        end

        -- 对铁憨憨造成转移伤害
        local rebHpBefore = rebecca.hp
        rebecca.attrs:takeDamage(transferDmg)
        rebecca.hp = rebecca.attrs:get(AD.HP)
        if rebecca.hp < 0 then rebecca.hp = 0 end
        if syncHpFn then syncHpFn(rebecca) end
        -- 转移伤害致死时设置死亡动画标记
        if rebecca.hp <= 0 and rebHpBefore > 0 then
            local overkill = math.max(0, transferDmg - rebHpBefore)
            rebecca._overkillRatio = math.min(1.0, overkill / (rebecca.maxHp or rebHpBefore))
            ETS.onShareFatal(rebecca)
        end

        -- 觉醒2: 吸收时回复2%最大HP（3秒CD）
        if hasAwaken(rebecca, 2) and rebeccaState.bulwarkHealCd <= 0 and rebecca.hp > 0 then
            local maxHp = rebecca.attrs.final[AD.MAX_HP] or 1
            local heal = math.floor(maxHp * 0.02 + 0.5)
            rebecca.attrs:heal(heal)
            rebecca.hp = rebecca.attrs:get(AD.HP)
            if syncHpFn then syncHpFn(rebecca) end
            rebeccaState.bulwarkHealCd = 3.0
        end

        -- 返回减少后的伤害给目标
        return damage - absorbedFromAlly
    end

    return { modifyDamageForTarget = modifyDamageForTarget }
end

return M
