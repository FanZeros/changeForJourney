-- 战斗宿主共享挂载契约：RCH/TAL与战斗/词缀状态始终一起切换。
-- capture保存容器引用（非复制/重开）；塔与副本退出恢复进入前的整组上下文。
local BC = require("ui.battle.combat.BattleCombat")
local PS = require("ui.battle.combat.ProjectileSystem")
local TM = require("systems.ThreatManager")
local TAL = require("systems.TalentManager")
local BE = require("ui.battle.combat.BattleEffects")
local SEM = require("systems.StatusEffectManager")
local RCH = require("systems.RelicConditionHandler")
local MAS = require("systems.MapAffixSystem")
local BAS = require("systems.BossAffixSystem")
local Berserk = require("ui.battle.stage.StageBerserk")

local M = {}

---@class BattleRuntimeState
---@field combatState table
---@field psState table
---@field tmState table
---@field talRefs table
---@field beState table
---@field semState table
---@field rchState RelicBattleState
---@field mapAffixState table
---@field bossAffixState table
---@field berserkState table

---@param name string
---@return BattleRuntimeState
function M.newState(name)
    return {
        combatState = BC.newState(name), psState = PS.newState(), tmState = TM.newState(),
        talRefs = TAL.newBattleRefs(), beState = BE.newFxState(), semState = SEM.newSemState(),
        rchState = RCH.newState(), mapAffixState = MAS.newState(),
        bossAffixState = BAS.newState(), berserkState = Berserk.newState(),
    }
end

---@return BattleRuntimeState
function M.capture()
    return {
        combatState = BC.mountedState(), psState = PS.mountedState(), tmState = TM.mountedState(),
        talRefs = TAL.mountedState(), beState = BE.mountedState(), semState = SEM.mountedState(),
        rchState = RCH.mountedState(), mapAffixState = MAS.getState(),
        bossAffixState = BAS.getState(), berserkState = Berserk.getState(),
    }
end

---@param state BattleRuntimeState|nil nil只恢复默认容器，不清状态或重发开场
function M.mount(state)
    local s = state or {}
    BC.mount(s.combatState)
    PS.mount(s.psState)
    TM.mount(s.tmState)
    TAL.mount(s.talRefs)
    BE.mount(s.beState)
    SEM.mount(s.semState)
    RCH.mount(s.rchState)
    MAS.mount(s.mapAffixState)
    BAS.mount(s.bossAffixState)
    Berserk.mount(s.berserkState)
end

return M
