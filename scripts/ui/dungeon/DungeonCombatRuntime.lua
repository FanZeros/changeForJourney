-- 资源副本复用同一 StageBerserk 实现，但实例计时不覆盖暂停中的主线。
local M = {}
---@type table|nil
local berserk = nil

local function instantiate(path)
    local file = assert(cache:GetFile(path), "缺少公共战斗脚本 " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return assert(load(table.concat(lines, "\n"), "@dungeon/" .. path, "t", _G))()
end

function M.getBerserk()
    if not berserk then berserk = instantiate("ui/battle/stage/StageBerserk.lua") end
    return berserk
end

---@type table|nil
local scopedModules = nil
function M.getScopedModules()
    if not scopedModules then
        scopedModules = {
            { target = require("systems.RelicConditionHandler"), instance = instantiate("systems/RelicConditionHandler.lua") },
            { target = require("systems.MapAffixSystem"), instance = instantiate("systems/MapAffixSystem.lua") },
            { target = require("systems.BossAffixSystem"), instance = instantiate("systems/BossAffixSystem.lua") },
        }
    end
    return scopedModules
end

--- 仅单机规则层清除未完成资源挑战；胜利等待回执时调用方禁止调用。
function M.cancelChallenge()
    local service = require("rules.dungeon.DungeonService")
    service.Cleanup(1)
end

return M
