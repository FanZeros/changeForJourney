-- 三队普通/资源关共享通关账本；从Scene原样提取，终焉由TerminalSceneFlow负责。
local SC = require("config.StageConfig")
local ClientDispatcher = require("runtime.ClientDispatcher")
local M = {}

function M.complete(scene, stageId, teamIdx, setMaxStage)
    local id = tonumber(stageId)
    if not id or id % 1 ~= 0 or not SC.getStage(id) or SC.isTerminalTemple(id)
        or not teamIdx or teamIdx % 1 ~= 0 or teamIdx < 1 or teamIdx > 3 then
        return false
    end
    local battle = ClientDispatcher.get("battle")
    if SC.isResourceStage(id) then
        local DC = require("config.DungeonConfig")
        local dungeon = ClientDispatcher.get("dungeon")
        if type(dungeon) ~= "table" or type(battle) ~= "table" then return false end
        if not DC.isStageUnlocked(id, battle, dungeon) then return false end
        local dungeonId, floor = DC.decodeStageId(id)
        local sub = dungeon[dungeonId]
        if type(sub) ~= "table" then sub = { floor = 1, cleared = {} }; dungeon[dungeonId] = sub end
        if type(sub.cleared) ~= "table" then sub.cleared = {} end
        local wasCleared = floor <= DC.getHighestClearedFloor(sub, dungeonId)
        sub.cleared[tostring(floor)] = true
        sub.floor = math.min(DC.MAX_FLOOR[dungeonId], math.max(tonumber(sub.floor) or 1, floor + 1))
        local nextId = SC.getNextStageId(id) or id
        if type(battle.teamStageIds) ~= "table" then battle.teamStageIds = {} end
        battle.teamStageIds[tostring(teamIdx)] = nextId
        if teamIdx == 1 then
            scene.adoptStageProgress(nextId)
            battle.currentStageId, battle.battleMode = nextId, "idle"
        end
        if not wasCleared then
            print(string.format("[BattleScene] 队%d 资源通关 %s 层%d，主线进度保持%s", teamIdx, dungeonId, floor, tostring(battle.maxStageId)))
        end
        ClientDispatcher.notifySubscribers("dungeon")
        ClientDispatcher.notifySubscribers("battle")
        require("boot.StandaloneSave").Flush()
        return false -- 资源奖励按击杀发放，不触发主线首次通关回调。
    end
    local clearedStages = scene.getClearedStages()
    local maxStage = scene.getMaxStageId()
    local savedCleared = type(battle) == "table" and battle.clearedStages or {}
    savedCleared = savedCleared or {}
    local wasCleared = clearedStages[id] == true or clearedStages[tostring(id)] == true
        or savedCleared[id] == true or savedCleared[tostring(id)] == true
    clearedStages[id] = true
    -- 末关跳过规则与Driver/存档预约同源，未通终焉仍停在普通末关。
    local nextId = SC.getNextStageId(id)
    local terminalCleared = nextId and (clearedStages[nextId] == true or clearedStages[tostring(nextId)] == true
        or savedCleared[nextId] == true or savedCleared[tostring(nextId)] == true)
    local savedMax = type(battle) == "table" and tonumber(battle.maxStageId) or 0
    local progressId = SC.resolveAutoAdvance(id, math.max(maxStage, savedMax or 0),
        nextId and { [nextId] = terminalCleared } or {})
    local updatedMax = math.max(maxStage, savedMax or 0, progressId)
    setMaxStage(updatedMax)
    if teamIdx == 1 then scene.adoptStageProgress(progressId) end
    local currentStage = scene.getStageId()
    if type(battle) == "table" then
        battle.clearedStages = savedCleared
        savedCleared[tostring(id)] = true
        battle.maxStageId = updatedMax
        if teamIdx == 1 then
            battle.currentStageId = currentStage
            local resource = SC.isResourceStage(currentStage)
            local firstClear = not resource and not (clearedStages[currentStage] or clearedStages[tostring(currentStage)])
            battle.battleMode = firstClear and "firstClear" or "idle"
        end
    end
    print(string.format("[BattleScene] 队%d 通关 stage=%d first=%s current=%s max=%s",
        teamIdx, id, tostring(not wasCleared), tostring(currentStage), tostring(updatedMax)))
    if not wasCleared then scene.onFirstClear(id, teamIdx) end
    if type(battle) == "table" then
        ClientDispatcher.notifySubscribers("battle")
        require("boot.StandaloneSave").Flush()
    end
    return not wasCleared
end

return M
