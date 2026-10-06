-- 资源副本仅提供章节数据与独立解锁检查；绘制/滚动复用 StageSelectDialog。
-- 不把资源 ID 写入主线关卡链；通天塔不生成 StageEntry。
local DC = require("config.DungeonConfig")
local ClientDispatcher = require("runtime.ClientDispatcher")

local M = {}
local groups = {} ---@type table[]

local function chapterKey(id, chapter)
    return "R:" .. id .. ":" .. tostring(chapter)
end

function M.getGroups()
    if #groups > 0 then return groups end
    for resourceIndex, id in ipairs(DC.RESOURCE_IDS) do
        local def = DC.DEFINITIONS[id]
        local maxFloor = DC.MAX_FLOOR[id] or def.maxFloor
        for chapter = 1, math.ceil(maxFloor / 5) do
            local ids = {}
            for floor = (chapter - 1) * 5 + 1, math.min(chapter * 5, maxFloor) do
                local stageId = DC.getStageId(id, floor)
                if stageId then ids[#ids + 1] = stageId end
            end
            groups[#groups + 1] = {
                key = chapterKey(id, chapter), name = def.name,
                subLabel = "第 " .. chapter .. " 章", chapter = chapter,
                resourceDungeonId = id, hueIndex = resourceIndex,
                background = def.cardImage, ids = ids,
            }
        end
    end
    return groups
end

function M.getGroupKey(stageId)
    local id, floor = DC.decodeStageId(stageId)
    if not id then return nil end
    return chapterKey(id, math.ceil(floor / 5))
end

-- Scene 的主线最高进度可能比每秒同步的快照新；只合并解锁基准，不修改存档表。
function M.getProgress()
    local battle = ClientDispatcher.get("battle") or {}
    local sceneMax = require("ui.battle.scene.BattleScene").getMaxStageId() or 0
    local progress = { maxStageId = math.max(tonumber(battle.maxStageId) or 0, sceneMax) }
    return progress, ClientDispatcher.get("dungeon") or {}
end

function M.isStageUnlocked(stageId, battleData, dungeonData)
    if not battleData then battleData, dungeonData = M.getProgress() end
    return DC.isStageUnlocked(stageId, battleData, dungeonData)
end

-- 通天塔沿用现有独立详情回调及主线解锁条件，绝不调用 SC.getStage("babel_tower")。
function M.isTowerUnlocked(battleData)
    if not battleData then battleData = M.getProgress() end
    return (tonumber(battleData.maxStageId) or 0) >= (DC.UNLOCK_CONDITIONS.babel_tower or 0)
end

function M.getTowerUnlockStage()
    return DC.UNLOCK_CONDITIONS.babel_tower or 0
end

return M
