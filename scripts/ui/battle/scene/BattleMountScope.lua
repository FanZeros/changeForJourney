-- 战斗子系统挂载作用域：借用战线或默认场景后恢复调用者，包括异常出口。
local Combat = require("ui.battle.combat.BattleCombat")
local Projectiles = require("ui.battle.combat.ProjectileSystem")
local Effects = require("ui.battle.combat.BattleEffects")
local Threat = require("systems.ThreatManager")
local Talents = require("systems.TalentManager")
local ExtraTalents = require("systems.ExtraTalentSystem")
local Status = require("systems.StatusEffectManager")
local Conditions = require("systems.RelicConditionHandler")
local Stats = require("systems.BattleStats")

local Scope = {}
local modules = { Combat, Projectiles, Effects, Threat, Talents, Status, Conditions }
-- TAL引用与单位表是两个独立mount；ETS也是独立状态，不能借用最近一队。
local defaultScene = { talentUnits = Talents.newUnitStates(), extraTalents = ExtraTalents.newState() }

function Scope.mountDefault()
    Stats.mount(0)
    for _, module in ipairs(modules) do module.mount(nil) end
    Talents.mountUnitStates(defaultScene.talentUnits)
    ExtraTalents.mount(defaultScene.extraTalents)
end

--- 保留多返回值和 nil；恢复后重新抛出原错误，不能把失败伪装成成功。
function Scope.run(callback, ...)
    local previous = {}
    for i, module in ipairs(modules) do previous[i] = module.mountedState() end
    local statsTeam = Stats.mountedTeam()
    local talentUnits, extraTalents = Talents.mountedUnitStates(), ExtraTalents.mountedState()
    local wasDefaultUnits = talentUnits == defaultScene.talentUnits
    local result = table.pack(pcall(callback, ...))
    for i, module in ipairs(modules) do module.mount(previous[i]) end
    Talents.mountUnitStates(wasDefaultUnits and defaultScene.talentUnits or talentUnits)
    ExtraTalents.mount(extraTalents)
    Stats.mount(statsTeam)
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
end

function Scope.runDefault(callback, ...)
    return Scope.run(function(...)
        Scope.mountDefault()
        local result = table.pack(pcall(callback, ...))
        -- TAL.reset会换表；正常/异常出口都记回，下一次挂载不能复用废弃表。
        defaultScene.talentUnits = Talents.mountedUnitStates()
        defaultScene.extraTalents = ExtraTalents.mountedState()
        if not result[1] then error(result[2], 0) end
        return table.unpack(result, 2, result.n)
    end, ...)
end

-- 包装已有公开函数；场景保留原模块抽离与签名，避免复制旧整文件实现。
function Scope.wrap(module, names, useDefault)
    for _, name in ipairs(names) do
        local callback = assert(module[name], "missing battle API: " .. name)
        module[name] = function(...)
            if useDefault then return Scope.runDefault(callback, ...) end
            return Scope.run(callback, ...)
        end
    end
end

return Scope
