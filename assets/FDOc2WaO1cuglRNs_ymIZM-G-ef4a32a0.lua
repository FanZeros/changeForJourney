-- LootboxSchema.lua — lootbox 模块 Schema
-- 战利品种子缓冲

local LootBoxSystem = require("systems.LootBoxSystem")

local LootboxSchema = {}

LootboxSchema.Fields = {
    lootbox = {
        pdmKey     = "ModLootbox",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_lootbox" },
        getDefault = function()
            return {
                seeds = {},
            }
        end,
        onLoad = function(data)
            if not data.seeds then data.seeds = {} end
            -- cjson 反序列化类型修正
            for _, seed in ipairs(data.seeds) do
                seed.quality = math.floor(tonumber(seed.quality) or 1)
                seed.level   = math.floor(tonumber(seed.level) or 1)
                seed.count   = math.floor(tonumber(seed.count) or 1)
            end
            -- 合并旧存档中按 stageId 分开的同类种子（quality+level 相同的合并为一条）
            LootBoxSystem.consolidateSeeds(data)
        end,
        desc = "战利品种子缓冲",
    },
}

return LootboxSchema
