-- 资源副本逐名阵亡退场/队列补位，不等同屏全灭，不重置整场天赋/仇恨。
local BC = require("ui.battle.combat.BattleCombat")
local TM = require("systems.ThreatManager")
local SEM = require("systems.StatusEffectManager")
local Layout = require("core.BattleLayout")
local M = {}
local REINFORCE_INTERVAL = 0.4

function M.tick(state, dt)
    state.reinforceCd = math.max(0, (state.reinforceCd or 0) - dt)
    for index = #state.enemies, 1, -1 do
        local unit = state.enemies[index]
        if unit.hp <= 0 then
            if not unit._dungeonDying then
                unit._dungeonDying = true
                unit._dungeonDeathTime = 0
                unit.atkProgress = 0
                TM.removeUnit(unit)
                SEM.removeUnit(unit)
                BC.setCardAnim(unit, { state = "dying", timer = 0, lungeDir = -1,
                    noTombstone = true, knockbackMult = 1 + (unit._overkillRatio or 0) * 2 })
            end
            unit._dungeonDeathTime = unit._dungeonDeathTime + dt
            if unit._dungeonDeathTime >= (BC.DEATH_ANIM_DURATION or 0.4) then
                BC.clearCardAnim(unit)
                BC.clearHitFlash(unit)
                table.remove(state.enemies, index)
            end
        end
    end
    if #state.enemies < Layout.MAX_PER_SIDE and #state.enemyQueue > 0 and state.reinforceCd <= 0 then
        local unit = table.remove(state.enemyQueue, 1)
        unit.atkProgress = 0
        state.enemies[#state.enemies + 1] = unit
        -- 全队列已在开场初始化，不能RCH.initBattle({unit})清掉己方免疫。
        BC.playEnterAnims({ unit }, -1)
        state.reinforceCd = REINFORCE_INTERVAL
    end
    return #state.enemies == 0 and #state.enemyQueue == 0
end

return M
