-- TaskSchema.lua — task 模块 Schema
-- 任务系统（日任务、周任务、成就）

local TaskCompat = require("shared.task.TaskCompat")

local TaskSchema = {}

TaskSchema.Fields = {
    task = {
        pdmKey     = "ModTask",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_task" },
        getDefault = function()
            return {
                dayId         = 0,
                dailyProg     = {},
                dailyClaimed  = {},
                weekId        = 0,
                weeklyProg    = {},
                weeklyClaimed = {},
                achProg       = {},
                achClaimed    = {},
            }
        end,
        onLoad = function(data)
            TaskCompat.onLoad(data)
        end,
        desc = "任务系统",
    },
}

return TaskSchema
