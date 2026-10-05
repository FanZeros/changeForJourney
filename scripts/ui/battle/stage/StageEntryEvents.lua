-- StageEntryEvents — 真实入场才触发剧情；预约与存档采集不算进入。
local ClientDispatcher = require("runtime.ClientDispatcher")
local StoryPlayer = require("systems.StoryPlayer")

local Events = {}
---@type table<number, boolean>
local notifiedStages = {}
---@type table<number, number>
local pendingEntries = {}

---@param stageId number
---@param teamIdx number|nil
---@return boolean
function Events.notify(stageId, teamIdx)
    teamIdx = teamIdx or 1
    if notifiedStages[stageId] then
        pendingEntries[teamIdx] = nil
        return false
    end
    local session = ClientDispatcher.get("session")
    if type(session) ~= "table" or session.introCompleted ~= true then
        pendingEntries[teamIdx] = stageId
        return false
    end
    pendingEntries[teamIdx] = nil
    notifiedStages[stageId] = true
    StoryPlayer.onStage(stageId, "enter")
    return true
end

---@param teamIdx number
function Events.retry(teamIdx)
    local stageId = pendingEntries[teamIdx]
    if stageId then Events.notify(stageId, teamIdx) end
end

function Events.reset()
    notifiedStages = {}
    pendingEntries = {}
end

return Events
