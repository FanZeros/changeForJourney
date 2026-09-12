-- ArenaSchema.lua — arena 模块 Schema
-- 竞技场数据

local ArenaSchema = {}

ArenaSchema.Fields = {
    arena = {
        pdmKey     = "ModArena",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_arena" },
        getDefault = function()
            return {
                rankScore        = 0,
                weekScore        = 1000,
                groupId          = nil,
                weekId           = 0,
                lastSettleWeekId = 0,
                reachedTiers     = {},
                claimedTiers     = {},
                totalWins        = 0,
                totalLosses      = 0,
                ticketsUsedToday = 0,
                ticketResetDay   = 0,
                shopPurchased    = {},
                shopWeekId       = 0,
            }
        end,
        onLoad = function(data)
            data.rankScore        = tonumber(data.rankScore)        or 0
            data.weekScore        = tonumber(data.weekScore)        or 1000
            data.weekId           = tonumber(data.weekId)           or 0
            data.lastSettleWeekId = tonumber(data.lastSettleWeekId) or 0
            data.totalWins        = tonumber(data.totalWins)        or 0
            data.totalLosses      = tonumber(data.totalLosses)      or 0
            data.ticketsUsedToday = tonumber(data.ticketsUsedToday) or 0
            data.ticketResetDay   = tonumber(data.ticketResetDay)   or 0
            data.shopWeekId       = tonumber(data.shopWeekId)       or 0
            if not data.shopPurchased then
                data.shopPurchased = {}
            else
                local fixedShop = {}
                for k, v in pairs(data.shopPurchased) do
                    local numK = tonumber(k)
                    if numK then fixedShop[numK] = tonumber(v) or 0 end
                end
                data.shopPurchased = fixedShop
            end
            if not data.reachedTiers then
                data.reachedTiers = {}
            else
                local fixed = {}
                for k, v in pairs(data.reachedTiers) do
                    local numK = tonumber(k)
                    if numK then fixed[numK] = v else fixed[k] = v end
                end
                data.reachedTiers = fixed
            end
            if not data.claimedTiers then
                data.claimedTiers = {}
            else
                local fixed = {}
                for k, v in pairs(data.claimedTiers) do
                    local numK = tonumber(k)
                    if numK then fixed[numK] = v else fixed[k] = v end
                end
                data.claimedTiers = fixed
            end
            data.groupId = tonumber(data.groupId)
        end,
        desc = "竞技场",
    },
}

return ArenaSchema
