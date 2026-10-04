-- 真实关卡入场通知：Scene备用加载与三队Driver共用账户级去重。
-- 通关预约(adoptStageProgress/pendingStageId)不得调用此模块。
local ClientDispatcher = require("runtime.ClientDispatcher")
local StoryPlayer = require("systems.StoryPlayer")

local Events = {}
---@type table<number, boolean>
local notifiedStages = {}
---@type table<number, number>
local pendingEntries = {}

--- 初始恢复早于开场完成时保留真实入场，完成后重试，不永久吞掉剧情。
--- 本进程已通知关卡不再次入队，包括Story.take后、领取回执到达前的窗口。
--- 新进程重新通知当前关，是否已领取仍由StoryPlayer全局账本判断。
---@param stageId number
---@param teamIdx number|nil
---@return boolean notified
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

--- 仅清档/重置账户时清除；重开、编队刷新、普通回灌不得重置。
function Events.reset()
    notifiedStages = {}
    pendingEntries = {}
end

return Events
