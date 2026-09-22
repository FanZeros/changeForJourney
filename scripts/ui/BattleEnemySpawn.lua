-- ============================================================================
-- BattleEnemySpawn - 首通/挂机敌人列表生成与上场分配
-- 从 BattleScene 抽出，生成规则与原实现保持一致
-- ============================================================================

local MC = require("config.MonsterConfig")

local M = {}

--- 解析首通附加特殊怪 ID 列表（兼容 firstClearBonusMonster 单值）
---@param stageEntry table
---@return number[]|nil
function M.getFirstClearBonusMonsterIds(stageEntry)
    local ids = stageEntry.firstClearBonusMonsters
    if ids and #ids > 0 then
        return ids
    end
    if stageEntry.firstClearBonusMonster then
        return { stageEntry.firstClearBonusMonster }
    end
    return nil
end

--- 标记首通附加特殊怪出场阶段：
--- 1 个：开场；2 个：开场 + 最后；3 个及以上：开场 + 中间若干 + 最后。
---@param bonusUnit table
---@param index number
---@param count number
function M.markFirstClearBonusSpawnPhase(bonusUnit, index, count)
    bonusUnit._isBonusMonster = true
    if index == 1 then
        bonusUnit._bonusSpawnPhase = "start"
    elseif index == count then
        bonusUnit._bonusSpawnPhase = "end"
    else
        bonusUnit._bonusSpawnPhase = "middle"
    end
end

---@param queue table[]
---@param unit table
function M.insertBonusMonsterIntoQueue(queue, unit)
    if unit._bonusSpawnPhase == "middle" then
        local insertPos = math.floor(#queue / 2) + 1
        table.insert(queue, insertPos, unit)
    else
        queue[#queue + 1] = unit
    end
end

---@param stageEntry table
---@param isFirstClear boolean
---@return table[] allEnemies
function M.generateEnemyList(stageEntry, isFirstClear)
    local totalCount = isFirstClear and stageEntry.firstCount or stageEntry.idleCount
    local monsterTypes = stageEntry.monsters
    local level = stageEntry.monsterLevel
    local list = {}

    local normalCount = totalCount
    if stageEntry.bossId > 0 then
        normalCount = totalCount - 1
    end

    for i = 1, normalCount do
        local typeIdx = ((i - 1) % #monsterTypes) + 1
        local monsterId = monsterTypes[typeIdx]
        local unit = MC.createMonster(monsterId, level)
        if unit then
            list[#list + 1] = unit
        end
    end

    if stageEntry.bossId > 0 then
        local bossUnit = MC.createMonster(stageEntry.bossId, level)
        if bossUnit then
            bossUnit.isBoss = true
            local insertPos = math.ceil(#list / 2) + 1
            table.insert(list, insertPos, bossUnit)
        end
    end

    if isFirstClear then
        local bonusIds = M.getFirstClearBonusMonsterIds(stageEntry)
        if bonusIds then
            local bonusAtStart = require("shared.ServerListConfig").isFirstClearBonusAtStart(require("ui.PlayerInfoPanel").getServerId())
            local bonusCount = #bonusIds
            for i, monsterId in ipairs(bonusIds) do
                local bonusUnit = MC.createMonster(monsterId, level)
                if bonusUnit then
                    if bonusAtStart then
                        M.markFirstClearBonusSpawnPhase(bonusUnit, i, bonusCount)
                    end
                    list[#list + 1] = bonusUnit
                end
            end
        end
    end

    return list
end

--- 分配敌人到场上与队列；首通特殊怪按阶段出场（开场/中间/最后）
---@param allEnemies table[]
---@param maxField number
---@return table[] fieldEnemies, table[] queueEnemies
function M.assignEnemiesToField(allEnemies, maxField)
    local field = {}
    local queue = {}
    local fieldCount = 0
    for _, u in ipairs(allEnemies) do
        if not u._isBonusMonster then
            if fieldCount < maxField then
                field[#field + 1] = u
                fieldCount = fieldCount + 1
            else
                queue[#queue + 1] = u
            end
        end
    end
    for _, u in ipairs(allEnemies) do
        if u._isBonusMonster then
            if u._bonusSpawnPhase == "start" then
                if fieldCount >= maxField and #field > 0 then
                    local bumped = table.remove(field, #field)
                    table.insert(queue, 1, bumped)
                else
                    fieldCount = fieldCount + 1
                end
                field[#field + 1] = u
            else
                M.insertBonusMonsterIntoQueue(queue, u)
            end
        end
    end
    return field, queue
end

--- 挂机模式：从 maxStageId 前 5 关混合生成怪物
---@param stageConfig table
---@param maxStageId number
---@param currentStageId number
---@return table[] allEnemies, number maxField
function M.generateIdleEnemyList(stageConfig, maxStageId, currentStageId)
    local IDLE_STAGE_COUNT = 5
    local stages = require("shared.StageUtils").collectPrevStages(maxStageId, IDLE_STAGE_COUNT, stageConfig)
    if #stages == 0 then
        local entry = stageConfig.getStage(currentStageId)
        if entry then
            return M.generateEnemyList(entry, false), entry.maxFieldEnemies or 5
        end
        return {}, 5
    end

    local allEnemies = {}
    local maxField = 0
    local perStage = 2

    for _, entry in ipairs(stages) do
        local monsterTypes = entry.monsters
        local level = entry.monsterLevel
        if (entry.maxFieldEnemies or 5) > maxField then
            maxField = entry.maxFieldEnemies or 5
        end

        local hasBoss = entry.bossId and entry.bossId > 0

        if hasBoss then
            local monsterId = monsterTypes[1]
            local unit = MC.createMonster(monsterId, level)
            if unit then
                unit._idleStageId = entry.id
                allEnemies[#allEnemies + 1] = unit
            end
            local bossUnit = MC.createMonster(entry.bossId, level)
            if bossUnit then
                bossUnit._idleStageId = entry.id
                allEnemies[#allEnemies + 1] = bossUnit
            end
        else
            for i = 1, perStage do
                local typeIdx = ((i - 1) % #monsterTypes) + 1
                local monsterId = monsterTypes[typeIdx]
                local unit = MC.createMonster(monsterId, level)
                if unit then
                    unit._idleStageId = entry.id
                    allEnemies[#allEnemies + 1] = unit
                end
            end
        end
    end

    if maxField < 5 then maxField = 5 end

    print(string.format("[BattleEnemySpawn] 挂机混合出怪: %d只来自%d关 (maxField=%d)",
        #allEnemies, #stages, maxField))
    return allEnemies, maxField
end

return M
