-- TaskCompat.lua — 任务存档兼容（奖励调优后重置领取状态等）

local TaskCompat = {}

--- 一次性：日/周任务钻石奖励加强 → 清空本周期已领取标记，保留进度可立即重领
---@param data table mod_task
---@return boolean migrated
function TaskCompat.migrateRewardBuffV1(data)
    data.compat = data.compat or {}
    if data.compat.taskRewardBuffV1 then
        return false
    end

    local dailyClaimed = 0
    for _ in pairs(data.dailyClaimed or {}) do
        dailyClaimed = dailyClaimed + 1
    end
    local weeklyClaimed = 0
    for _ in pairs(data.weeklyClaimed or {}) do
        weeklyClaimed = weeklyClaimed + 1
    end

    data.dailyClaimed = {}
    data.weeklyClaimed = {}
    data.compat.taskRewardBuffV1 = true
    data._justMigratedTaskRewardBuffV1 = true

    print(string.format(
        "[TaskCompat] taskRewardBuffV1: cleared dailyClaimed=%d weeklyClaimed=%d (progress kept)",
        dailyClaimed, weeklyClaimed))
    return true
end

--- 登录加载：结构补全 + 奖励加强兼容
---@param data table mod_task
function TaskCompat.onLoad(data)
    data.dayId  = tonumber(data.dayId)  or 0
    data.weekId = tonumber(data.weekId) or 0
    if not data.dailyProg     then data.dailyProg     = {} end
    if not data.dailyClaimed  then data.dailyClaimed  = {} end
    if not data.weeklyProg    then data.weeklyProg    = {} end
    if not data.weeklyClaimed then data.weeklyClaimed = {} end
    if not data.achProg       then data.achProg       = {} end
    if not data.achClaimed    then data.achClaimed    = {} end

    TaskCompat.migrateRewardBuffV1(data)
end

return TaskCompat
