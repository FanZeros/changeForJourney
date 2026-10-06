-- 副本每种一个分类；全部关卡共用选关页的连续列表。
-- 塔ID仅用于界面定位，不进入主线或资源队伍关卡链。
local DC = require("config.DungeonConfig")
local SC = require("config.StageConfig")
local TC = require("config.TowerConfig")
local ClientDispatcher = require("runtime.ClientDispatcher")

local M = {}
local groups = {} ---@type table[]
local TOWER_STAGE_BASE = 400000

function M.isTowerStage(stageId)
    local id = math.tointeger(tonumber(stageId) or 0)
    return id ~= nil and id > TOWER_STAGE_BASE and id <= TOWER_STAGE_BASE + TC.MAX_FLOOR
end

function M.getGroups()
    if #groups > 0 then return groups end
    for resourceIndex, id in ipairs(DC.RESOURCE_IDS) do
        local def = DC.DEFINITIONS[id]
        local ids = {}
        for floor = 1, DC.MAX_FLOOR[id] do
            ids[#ids + 1] = DC.getStageId(id, floor)
        end
        groups[#groups + 1] = {
            key = "R:" .. id, name = def.name, subLabel = "",
            resourceDungeonId = id, hueIndex = resourceIndex,
            background = def.cardImage, ids = ids,
        }
    end
    local ids = {}
    for floor = 1, TC.MAX_FLOOR do ids[#ids + 1] = TOWER_STAGE_BASE + floor end
    groups[#groups + 1] = {
        key = "R:babel_tower", name = "通天塔", subLabel = "",
        isTower = true, hueIndex = 5,
        background = "image/战斗背景/通天塔.png", ids = ids,
    }
    return groups
end

function M.getGroupKey(stageId)
    if M.isTowerStage(stageId) then return "R:babel_tower" end
    local id = DC.decodeStageId(stageId)
    return id and "R:" .. id or nil
end

function M.getStageEntry(stageId)
    if not M.isTowerStage(stageId) then return SC.getStage(stageId) end
    local floor = stageId - TOWER_STAGE_BASE
    local data = TC.getFloor(floor)
    return {
        id = stageId, name = "通天塔 1-" .. floor,
        stage = floor, displayChapter = 1, monsterLevel = data.monsterLevel,
        monsters = {}, bossId = 0, tower = true,
    }
end

-- 当前队伍任务和主线解锁基准各自保存；不要用资源大ID推高主线。
function M.getProgress()
    local battle = ClientDispatcher.get("battle") or {}
    local sceneMax = require("ui.battle.scene.BattleScene").getMaxStageId() or 0
    local maxId = tonumber(battle.maxStageId) or 0
    local function rank(id)
        local previous = SC.getTerminalPrevStageId(id)
        return previous and previous + 0.5 or id
    end
    local progress = { maxStageId = rank(sceneMax) > rank(maxId) and sceneMax or maxId }
    return progress, ClientDispatcher.get("dungeon") or {}
end

function M.getCurrentTowerStageId(dungeonData)
    local dungeon = dungeonData or ClientDispatcher.get("dungeon") or {}
    local tower = dungeon.babel_tower or {}
    local floor = math.max(1, math.min(TC.MAX_FLOOR, math.floor(tonumber(tower.floor) or 1)))
    return TOWER_STAGE_BASE + floor
end

function M.isStageUnlocked(stageId, battleData, dungeonData)
    if not battleData then battleData, dungeonData = M.getProgress() end
    if M.isTowerStage(stageId) then
        if not M.isTowerUnlocked(battleData) then return false end
        return stageId <= M.getCurrentTowerStageId(dungeonData)
    end
    return DC.isStageUnlocked(stageId, battleData, dungeonData)
end

function M.isTowerUnlocked(battleData)
    if not battleData then battleData = M.getProgress() end
    local id = tonumber(battleData.maxStageId) or 0
    local previous = SC.getTerminalPrevStageId(id)
    return (previous and previous + 0.5 or id) >= M.getTowerUnlockStage()
end

function M.getTowerUnlockStage()
    return DC.UNLOCK_CONDITIONS.babel_tower or 0
end

return M
