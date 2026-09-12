-- ============================================================================
-- HeroResonance - 角色共鸣等级
-- 共鸣等级 = 全 roster 中等级最高的 TOP_N 个英雄里的最低值
-- 当共鸣地板提升时，将低于该等级的英雄 level 同步到共鸣等级（只升不降）
-- ============================================================================

local ExpTable = require("config.ExpTable")

local M = {}

M.RESONANCE_TOP_N = 5

--- 从 roster/ownedSet 收集所有已拥有英雄的等级
---@param roster table|nil
---@return number[]
function M.collectOwnedLevels(roster)
    local levels = {}
    if type(roster) ~= "table" then return levels end
    for _, hero in pairs(roster) do
        if type(hero) == "table" and hero.level then
            levels[#levels + 1] = hero.level
        end
    end
    return levels
end

--- 计算共鸣等级（全队前 TOP_N 高等级中的最低值）
---@param roster table|nil
---@return number
function M.computeResonanceLevel(roster)
    local levels = M.collectOwnedLevels(roster)
    if #levels == 0 then return 1 end

    table.sort(levels, function(a, b) return a > b end)
    local count = math.min(M.RESONANCE_TOP_N, #levels)
    return levels[count] or 1
end

--- 将低于共鸣等级的英雄实际 level 同步到共鸣地板（只升不降）
---@param roster table|nil
---@return number resonanceLevel
---@return number boostedCount
function M.syncRosterToResonance(roster)
    if type(roster) ~= "table" then return 1, 0 end

    local resonance = M.computeResonanceLevel(roster)
    local boostedCount = 0

    for _, hero in pairs(roster) do
        if type(hero) == "table" and hero.level and hero.level < resonance then
            hero.level = resonance
            hero.exp = 0
            hero.maxExp = ExpTable.getHeroExpForLevel(resonance) or 0
            boostedCount = boostedCount + 1
        end
    end

    return resonance, boostedCount
end

return M
