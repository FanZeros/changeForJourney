-- DungeonBattleScene独立挂载既有公共战斗状态；每次调用后还原宿主三队作用域。
local BC = require("ui.battle.combat.BattleCombat")
local PS = require("ui.battle.combat.ProjectileSystem")
local TM = require("systems.ThreatManager")
local TAL = require("systems.TalentManager")
local FX = require("ui.battle.combat.BattleEffects")
local SEM = require("systems.StatusEffectManager")
local Stats = require("systems.BattleStats")
local ETS = require("systems.ExtraTalentSystem")
local Layout = require("core.BattleLayout")
local M = {}
local scope = {
    combat = BC.newState("dungeon"), projectiles = PS.newState(), threat = TM.newState(),
    talents = TAL.newBattleRefs(), effects = FX.newFxState(), status = SEM.newSemState(),
    unitStates = TAL.newUnitStates(), extraTalents = ETS.newState(),
}
local running = false

function M.run(teamIdx, fn, ...)
    -- forceClose/输入回调可能嵌套close，沿用当前副本状态，由最外层统一还原。
    if running then return fn(...) end
    local scopedModules = require("ui.dungeon.DungeonCombatRuntime").getScopedModules()
    local previous = {
        combat = BC.mountedState(), projectiles = PS.mountedState(), threat = TM.mountedState(),
        talents = TAL.mountedState(), effects = FX.mountedState(), status = SEM.mountedState(),
        team = Stats.mountedTeam(), layout = Layout.MODE,
        unitStates = TAL.mountedUnitStates(), extraTalents = ETS.mountedState(),
    }
    BC.mount(scope.combat)
    PS.mount(scope.projectiles)
    TM.mount(scope.threat)
    TAL.mount(scope.talents)
    FX.mount(scope.effects)
    SEM.mount(scope.status)
    TAL.mountUnitStates(scope.unitStates)
    ETS.mount(scope.extraTalents)
    Layout.setMode("strip") -- 副本与主线共用左右对阵坐标，作用域退出后还原宿主。
    Stats.mount(100 + (teamIdx or 1)) -- 独立数字桶，不覆盖主线0或三队1/2/3
    -- 无mount API的公共模块复用独立实例，临时桥接函数，返回后原样还原。
    -- 内部跨模块require仍取得同一导出表，故BattleCombat也消费当前副本实例。
    local bridges = {}
    for _, item in ipairs(scopedModules) do
        local original = {}
        for key, value in pairs(item.instance) do
            if type(value) == "function" then
                original[key] = item.target[key]
                item.target[key] = value
            end
        end
        bridges[#bridges + 1] = { target = item.target, original = original }
    end
    running = true
    local result = table.pack(pcall(fn, ...))
    running = false
    -- TAL.reset会替换单位表，保留最新副本表供下一帧挂载。
    scope.unitStates = TAL.mountedUnitStates()
    for index = #bridges, 1, -1 do
        for key, value in pairs(bridges[index].original) do bridges[index].target[key] = value end
    end
    BC.mount(previous.combat)
    PS.mount(previous.projectiles)
    TM.mount(previous.threat)
    TAL.mount(previous.talents)
    FX.mount(previous.effects)
    SEM.mount(previous.status)
    TAL.mountUnitStates(previous.unitStates)
    ETS.mount(previous.extraTalents)
    Layout.setMode(previous.layout)
    Stats.mount(previous.team)
    if not result[1] then error(result[2]) end
    return table.unpack(result, 2, result.n)
end

return M
