-- ============================================================================
-- TalentAllyDeath - TAL.onAllyDeath 抽出（玩法不变）
-- ============================================================================

local AD  = require("systems.AttributeDef")
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

    local function onAllyDeath(dyingUnit, allies, syncHpFn)
        local TAL_BCS = getTAL_BCS()
        if ETS.tryTicketRevive(dyingUnit, allies, syncHpFn) then
            return true
        end

        -- ======== 星图节点125 不死鸟之翼 免疫致命伤害 + 3秒恢复20%HP ========
        if hasStarNode(dyingUnit, 125) then
            local ds = getState(dyingUnit)
            if ds and not ds.phoenixUsed then
                ds.phoenixUsed = true
                -- 免疫致命伤害：将HP恢复到1
                if dyingUnit.attrs then
                    dyingUnit.attrs.final[AD.HP] = 1
                    dyingUnit.hp = 1
                    -- 施加3秒持续治疗(总量=20%最大HP, →HOT dps = maxHp*0.2/3)
                    local maxHp = dyingUnit.maxHp or 1
                    local hotDps = math.floor(maxHp * 0.20 / 3.0 + 0.5)
                    SEM.apply(dyingUnit, SEM.HOT, 3.0, dyingUnit, { hps = hotDps })
                    syncHpFn(dyingUnit)
                    talentLog("[Talent] 不死鸟之翼 " .. (dyingUnit.name or "?") .. " 免疫致命伤害! 3秒恢复20%HP (hps=" .. hotDps .. ")")
                else
                    dyingUnit.hp = 1
                end
                return true
            end
        end

        -- ======== #15 复活吧爱人 觉醒7: 自身首次死亡必定复活 ========
        if dyingUnit.heroId == 15 then
            local selfState = getState(dyingUnit)
            if selfState and hasAwaken(dyingUnit, 7) and not selfState.selfReviveUsed then
                selfState.selfReviveUsed = true
                -- 复活自身 100% HP
                if dyingUnit.attrs then
                    dyingUnit.attrs:fillHp()
                    syncHpFn(dyingUnit)
                else
                    dyingUnit.hp = dyingUnit.maxHp
                end
                -- 全队回复20%最大生命
                for _, a in ipairs(allies) do
                    if a.hp > 0 and a.attrs then
                        local healAmt = math.floor((a.maxHp or 1) * 0.20 + 0.5)
                        if healAmt > 0 then
                            a.attrs:heal(healAmt)
                            a.hp = a.attrs:get(AD.HP)
                            if a.hp > a.maxHp then a.hp = a.maxHp end
                        end
                    end
                end
                talentLog("[Talent] 复活吧爱人 觉醒7 圣光奇迹: 自身复活! 全队回复20%HP")
                return true
            end
        end

        -- ======== #15 复活吧爱人 圣光复活：在场时其他角色死亡复活 + 觉醒 ========
        for _, ally in ipairs(allies) do
            if ally.heroId == 15 and ally.hp > 0 and ally ~= dyingUnit then
                local elizState = getState(ally)
                if elizState and not elizState.reviveUsed[dyingUnit] then
                    -- 计算复活概率: 基础25%, 觉醒1→40%, 觉醒5→60%；追加技永久层叠加上限80%
                    local extraRate = ETS.getReviveRateBonus(ETS.getOwned(15), ally)
                    local reviveRate = 0.25 + extraRate
                    if hasAwaken(ally, 1) then reviveRate = 0.40 + extraRate end
                    if hasAwaken(ally, 5) then reviveRate = 0.60 + extraRate end
                    reviveRate = math.min(0.80, reviveRate)
                    -- 觉醒4: 战斗中首次死亡的角色必定复活
                    if hasAwaken(ally, 4) then
                        reviveRate = 1.0
                    end

                    if math.random() < reviveRate then
                        elizState.reviveUsed[dyingUnit] = true
                        if dyingUnit.attrs then
                            dyingUnit.attrs:fillHp()
                            syncHpFn(dyingUnit)
                        else
                            dyingUnit.hp = dyingUnit.maxHp
                        end

                        -- 觉醒2: 被复活的角色5秒内受治疗效果30%（标记在单位上，任何治疗者都生效果
                        if hasAwaken(ally, 2) then
                            elizState.reviveHealBoostTargets[dyingUnit] = 5.0
                            dyingUnit._reviveHealBoost = true
                            talentLog("[Talent] 复活吧爱人 觉醒2: " .. (dyingUnit.name or "复活者") .. " 治疗效果+30% (5s)")
                        end

                        -- 觉醒6: 复活时施加20%最大HP护盾(5s)
                        if hasAwaken(ally, 6) then
                            local shieldAmt = math.floor((dyingUnit.maxHp or 1) * 0.20 + 0.5)
                            dyingUnit.shield = { amount = shieldAmt, timer = 5.0 }
                            talentLog("[Talent] 复活吧爱人 觉醒6: " .. (dyingUnit.name or "复活者") .. " 获得护盾 " .. shieldAmt)
                        end

                        talentLog("[Talent] 复活吧爱人 圣光复活: " .. (dyingUnit.name or "?") .. " 被复活！(概率=" .. math.floor(reviveRate * 100) .. "%)")
                        ETS.onSuccessfulRevive(ally, dyingUnit)
                        return true
                    else
                        elizState.reviveUsed[dyingUnit] = true
                    end
                end
            end
        end
        if dyingUnit.heroId == 15 then
            ETS.onLoverDeathNuke(dyingUnit, allies, TAL_BCS.bEnemies, TAL_BCS.dealDamage)
        end
        return false
    end

    return { onAllyDeath = onAllyDeath }
end

return M
