-- 转职确认只消费已穿装备；缓存以独立内容快照复核，不借帧号或 live 引用跳过变更。
local Power = require("systems.EquipmentPower")
local Snapshot = require("ui.character.detail.CharacterDetailSnapshot")
local Store = require("core.PlayerStore")
local M = {}
---@type table|nil
local prepared = nil

local function resultCopy(result)
    if not result then return nil end
    return { currentPower = result.currentPower, previewPower = result.previewPower, gain = result.gain }
end

function M.clear()
    prepared = nil
end

function M.get(heroId, branchId)
    if not heroId then return nil end
    local sources = {
        heroes = Store.Get("heroes"), equipment = Store.Get("equipment"),
        artifacts = Store.Get("artifacts"), talents = Store.Get("talents"),
    }
    local function matches(frozen)
        return Snapshot.matchesDependencies(frozen, sources.heroes, sources.equipment,
            sources.artifacts, sources.talents, heroId)
    end
    if prepared and prepared.heroId == heroId and prepared.branchId == branchId
        and matches(prepared.dependencies) then
        return resultCopy(prepared.result)
    end
    prepared = nil
    local dependencies = Snapshot.freezeDependencies(sources, nil, heroId)
    -- 转职不需要未穿候选；仍保留完整穿戴映射与本队光环，神器沿角色评分默认排除。
    local ctx = Power.buildWornContext(heroId, sources)
    local result = ctx and Power.evaluateAdvancement(ctx, branchId) or nil
    if not matches(dependencies) then return nil end
    prepared = { heroId = heroId, branchId = branchId, dependencies = dependencies, result = result }
    return resultCopy(result)
end

return M
