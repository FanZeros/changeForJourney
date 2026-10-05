-- DungeonSchema.lua — dungeon 模块 Schema
-- 副本进度（三资源副本、独立通天塔与隐藏旧遗迹存量）

local DungeonSchema = {}

DungeonSchema.Fields = {
    dungeon = {
        pdmKey     = "ModDungeon",
        type       = "json",
        scope      = "server",
        persist    = { via = "local", cloudKey = "mod_dungeon" },
        getDefault = function()
            return {
                gold_mine = {
                    floor         = 1,       -- 当前可挑战楼层
                    cleared       = {},      -- [floor]=true 已首通的层
                    dailyUsed     = 0,       -- 今日已扫荡次数
                    dailyDay      = 0,       -- 上次重置日序号 (UTC+8)
                    idleAccumSec  = 0,       -- 副本挂机累积秒数
                },
                equipment_vault = {
                    floor         = 1,       -- 新副本独立进度，不继承旧遗迹
                    cleared       = {},
                    dailyUsed     = 0,
                    dailyDay      = 0,
                    idleAccumSec  = 0,
                    idleConsumedSec = 0,     -- 本轮已消费秒数，保留尾段费率位置
                },
                black_diamond = {
                    floor         = 1,
                    cleared       = {},
                    dailyUsed     = 0,
                    dailyDay      = 0,
                    idleAccumSec  = 0,
                },
                -- 隐藏旧遗迹：只结清原粉尘挂机存量，不转移或重发。
                ancient_ruin = {
                    floor         = 1,
                    cleared       = {},
                    dailyUsed     = 0,
                    dailyDay      = 0,
                    idleAccumSec  = 0,
                },
                babel_tower = {
                    floor         = 1,
                    cleared       = {},
                    dailyUsed     = 0,
                    dailyDay      = 0,
                    buffs         = {},
                    idleAccumSec  = 0,
                },
            }
        end,
        onLoad = function(data)
            local DungeonCompat = require("shared.dungeon.DungeonCompat")
            DungeonCompat.onLoad(data)
        end,
        onServerLoad = function(data)
            local DungeonCompat = require("shared.dungeon.DungeonCompat")
            DungeonCompat.migrateMonsterBuffV1(data)
        end,
        desc = "副本进度",
    },
}

return DungeonSchema
