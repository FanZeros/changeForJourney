-- TavernSchema.lua — tavern 模块 Schema
-- 酒馆数据（商店购买记录）

local TavernConfig = require("config.TavernConfig")

local TavernSchema = {}

TavernSchema.Fields = {
    tavern = {
        pdmKey     = "ModTavern",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_tavern" },
        getDefault = function()
            return {
                shopPurchased = {},   -- { [itemId] = count }
                shopWeekId    = 0,    -- 周购买记录重置标记
                shopDayId     = 0,    -- 日购买记录重置标记
            }
        end,
        onLoad = function(data)
            data.shopWeekId = tonumber(data.shopWeekId) or 0
            data.shopDayId  = tonumber(data.shopDayId)  or 0
            if not data.shopPurchased then
                data.shopPurchased = {}
            else
                -- cjson 将数字 key 反序列化为字符串，需修正
                local fixed = {}
                for k, v in pairs(data.shopPurchased) do
                    local numK = tonumber(k)
                    if numK then fixed[numK] = tonumber(v) or 0 end
                end
                data.shopPurchased = fixed
            end
            -- 加载时跨日/跨周重置（客户端推送与服务端 PDM 加载均会执行）
            TavernConfig.applyShopPeriodReset(data, os.time())
        end,
        desc = "酒馆",
    },
}

return TavernSchema
