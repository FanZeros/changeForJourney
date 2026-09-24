-- ============================================================================
-- TaskHandler - 任务系统网络入口（薄路由层）
-- 职责: 接收 CLAIM_TASK 请求 → 调用 TaskService → 返回结果
-- 层级: server/task  |  禁止业务逻辑，逻辑全在 TaskService
-- ============================================================================

local Protocol    = require("shared.Protocol")
local TaskService = require("rules.task.TaskService")

local TaskHandler = {}

-- ======================== Action Handlers ========================

local handlers = {}

handlers[Protocol.ACTION_TYPES.CLAIM_TASK] = function(uid, params)
    local taskId = params and params.taskId

    local ok, err, result = TaskService.ClaimTask(uid, taskId)
    if not ok then
        return { success = false, reason = err }
    end

    return {
        success = true,
        action  = Protocol.ACTION_TYPES.CLAIM_TASK,
        taskId  = result.taskId,
        reward  = result.reward,
    }
end

handlers[Protocol.ACTION_TYPES.CLAIM_ALL_TASKS] = function(uid, params)
    local scope = params and params.scope
    local ok, err, result = TaskService.ClaimAll(uid, scope)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success = true,
        action  = Protocol.ACTION_TYPES.CLAIM_ALL_TASKS,
        scope   = result.scope,
        claimed = result.claimed,
        rewards = result.rewards,
    }
end

TaskHandler.actionHandlers = handlers

return TaskHandler
