-- 战斗子系统挂载作用域：渲染/输入临时借用战线，结束后恢复调用方。
local Combat = require("ui.battle.combat.BattleCombat")
local Projectiles = require("ui.battle.combat.ProjectileSystem")
local Effects = require("ui.battle.combat.BattleEffects")
local Threat = require("systems.ThreatManager")
local Talents = require("systems.TalentManager")
local Status = require("systems.StatusEffectManager")
local Conditions = require("systems.RelicConditionHandler")
local Stats = require("systems.BattleStats")

local Scope = {}
local modules = { Combat, Projectiles, Effects, Threat, Talents, Status, Conditions }

function Scope.mountDefault()
    Stats.mount(0)
    for _, module in ipairs(modules) do module.mount(nil) end
end

--- 包括异常出口；恢复后重新抛出原错误，不将失败伪装成成功。
function Scope.run(callback, ...)
    local previous = {}
    for i, module in ipairs(modules) do previous[i] = module.mountedState() end
    local statsTeam = Stats.mountedTeam()
    local result = table.pack(pcall(callback, ...))
    for i, module in ipairs(modules) do module.mount(previous[i]) end
    Stats.mount(statsTeam)
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
end

return Scope
