-- ============================================================================
-- Talent Ayane helpers extracted from TalentManager
-- Bound via M.bind(deps); original local function names preserved.
-- ============================================================================

local M = {}

function M.bind(deps)
    local hasAwaken = deps.hasAwaken
    local getState = deps.getState
    local ensureState = deps.ensureState
    local getAliveEnemies = deps.getAliveEnemies
    local talentLog = deps.talentLog
    local calcTalentFixedDamage = deps.calcTalentFixedDamage
    local AD = deps.AD
    local SEM = deps.SEM
    local CF = deps.CF
    local BattleCombat = deps.BattleCombat

local function getAyaneMarkMult(ayane)
    return hasAwaken(ayane, 1) and 0.35 or 0.25
end

--- 清除敌方列表上所有愤怒的小雀标记（全局唯一标记，施加前先清场）
---@param opponents table[]
local function clearAyaneMarks(opponents)
    for _, u in ipairs(opponents or {}) do
        if u and SEM.has(u, SEM.MARKED) then
            SEM.remove(u, SEM.MARKED)
            if u.attrs then
                u.attrs:removeModifier("awaken_mark_debuff")
            end
        end
    end
end

--- 施加愤怒的小雀标记（先清场，保证全场仅一个标记目标）
---@param ayane table 愤怒的小雀单位
---@param target table 标记目标
---@param opponents table[] 对方单位列表
local function applyAyaneMark(ayane, target, opponents)
    if not ayane or not target or target.hp <= 0 then return end
    clearAyaneMarks(opponents)
    local markMult = getAyaneMarkMult(ayane)
    SEM.apply(target, SEM.MARKED, 99999, ayane, { mult = markMult })
    if hasAwaken(ayane, 4) and target.attrs then
        target.attrs:addModifier("awaken_mark_debuff", {
            { key = AD.DODGE, flat = -30 },
            { key = AD.PHYS_ARMOR, flat = -15 },
        })
    end
    if hasAwaken(ayane, 6) then
        local s = getState(ayane)
        if s then s.markFirstHitCrit[target] = nil end
    end
end

--- 战斗开始：队伍内多个愤怒的小雀也只标记一个随机敌人
---@param units table[] 己方/对方单位列表
---@param opposingUnits table[] 被标记的一方
local function applyAyaneBattleStartMark(units, opposingUnits)
    local ayane = nil
    for _, unit in ipairs(units) do
        if unit.heroId == 8 and unit.hp > 0 then
            ayane = unit
            break
        end
    end
    if not ayane then return end
    local aliveOpponents = getAliveEnemies(opposingUnits)
    if #aliveOpponents == 0 then return end
    local target = aliveOpponents[math.random(#aliveOpponents)]
    applyAyaneMark(ayane, target, opposingUnits)
    talentLog("[Talent] 愤怒的小雀 仇册：标记" .. (target.name or "?")
        .. " (受伤+" .. math.floor(getAyaneMarkMult(ayane) * 100) .. "%)")
end

--- 获取队伍中第一个存活愤怒的小雀（标记/补标来源）
---@param allies table[]
---@param requireAw2 boolean|nil 是否要求觉醒2
---@return table|nil
local function getPrimaryAyane(allies, requireAw2)
    for _, ally in ipairs(allies) do
        if ally.hp > 0 and ally.heroId == 8 then
            if not requireAw2 or hasAwaken(ally, 2) then
                return ally
            end
        end
    end
    return nil
end

--- 敌方是否已有愤怒的小雀标记
---@param enemies table[]
---@return boolean
local function hasAnyAyaneMark(enemies)
    for _, e in ipairs(getAliveEnemies(enemies)) do
        if SEM.has(e, SEM.MARKED) then return true end
    end
    return false
end


    return {
        getAyaneMarkMult = getAyaneMarkMult,
        clearAyaneMarks = clearAyaneMarks,
        applyAyaneMark = applyAyaneMark,
        applyAyaneBattleStartMark = applyAyaneBattleStartMark,
        getPrimaryAyane = getPrimaryAyane,
        hasAnyAyaneMark = hasAnyAyaneMark,
    }
end

return M
