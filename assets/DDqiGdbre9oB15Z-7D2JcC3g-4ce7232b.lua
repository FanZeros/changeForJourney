-- PlayerSchema.lua — player 模块 Schema
-- 玩家基础信息（名称、等级、经验、战力、头像）

local PlayerSchema = {}

PlayerSchema.Fields = {
    player = {
        pdmKey     = "ModPlayer",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_player" },
        getDefault = function()
            return {
                name         = "玩家",
                level        = 1,
                exp          = 0,
                maxExp       = 50,
                power        = 1000,
                avatarHeroId  = 1,
                avatarFrameId = 1,
            }
        end,
        onLoad = function(data)
            local ExpTable = require("config.ExpTable")
            data.level = math.max(1, math.min(
                math.floor(tonumber(data.level) or 1),
                ExpTable.PLAYER_MAX_LEVEL
            ))
            data.exp = math.max(0, math.floor(tonumber(data.exp) or 0))
            data.maxExp = ExpTable.getPlayerExpForLevel(data.level) or 0
            if ExpTable.isPlayerMaxLevel(data.level) then
                data.exp = 0
            end
            data.avatarFrameId = tonumber(data.avatarFrameId) or 1
        end,
        desc = "玩家基础信息",
    },
}

return PlayerSchema
