-- DungeonSchema.lua — dungeon 模块 Schema
-- 副本进度（黄金矿洞楼层、通关记录、每日使用次数）

local DungeonSchema = {}

DungeonSchema.Fields = {
    dungeon = {
        pdmKey     = "ModDungeon",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_dungeon" },
        getDefault = function()
            return {
                gold_mine = {
                    floor         = 1,       -- 当前可挑战楼层
                    cleared       = {},      -- [floor]=true 已首通的层
                    dailyUsed     = 0,       -- 今日已扫荡次数
                    dailyDay      = 0,       -- 上次重置日序号 (UTC+8)
                    idleAccumSec  = 0,       -- 副本挂机累积秒数（上限 12h）
                },
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
