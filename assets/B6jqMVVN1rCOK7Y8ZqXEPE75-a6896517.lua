-- MarketSchema.lua — market 模块 Schema
-- 市场商店购买记录

local MarketSchema = {}

-- 广告存储上限（存档兼容字段，补充冷却已移除，始终视为可用）
MarketSchema.AD_MAX_STORED    = 10
--- 特权商店：每次观看广告立即获得的特权点
MarketSchema.AD_PRIVILEGE_REWARD_PER_WATCH = 3
--- 特权广告：单次观看完成后，按钮再次可点击的冷却（秒，防 SDK 未清理重复点）
MarketSchema.AD_PRIVILEGE_CLICK_COOLDOWN_SECS = 5
-- 以下常量已废弃（补充冷却已移除），保留仅供旧存档/文档引用
MarketSchema.AD_RECHARGE_SECS = 0
MarketSchema.AD_RECHARGE_SECS_SLOW = 0
MarketSchema.AD_SLOW_THRESHOLD = 30

MarketSchema.Fields = {
    market = {
        pdmKey     = "ModMarket",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_market" },
        getDefault = function()
            return {
                purchased  = {},
                shopConfigVersion = 0,
                privilegeMileRewardVersion = 5, -- 特权里程奖励版本（见 MarketService）
                -- 特权广告存储
                privilege  = {
                    adStored        = MarketSchema.AD_MAX_STORED, -- 当前可观看广告数（0~10）
                    watchCount      = 0,                          -- 当日累计观看次数（每日重置）
                    adRechargeEnd   = 0,                          -- 下次补满时的服务器时间戳（0=已满）
                    claimed         = {},                         -- 当日已领取里程奖励：{ [threshold] = true }
                    watchDayId      = 0,                          -- 最近重置的日期编号（UTC+8），用于每日重置
                },
            }
        end,
        onLoad = function(data)
            if data.shopConfigVersion == nil then data.shopConfigVersion = 0 end
            data.shopConfigVersion = tonumber(data.shopConfigVersion) or 0
            if data.privilegeMileRewardVersion == nil then data.privilegeMileRewardVersion = 1 end
            data.privilegeMileRewardVersion = tonumber(data.privilegeMileRewardVersion) or 1
            if not data.purchased then
                data.purchased = {}
            else
                local fixed = {}
                for k, v in pairs(data.purchased) do
                    local numK = tonumber(k)
                    if numK then
                        fixed[numK] = v
                        fixed[numK].count = tonumber(v.count) or 0
                        fixed[numK].firstBuyTime = tonumber(v.firstBuyTime) or 0
                        fixed[numK].dayId = tonumber(v.dayId) or 0
                    end
                end
                data.purchased = fixed
            end
            -- 确保 privilege 子对象存在（旧存档兼容）
            if not data.privilege then
                data.privilege = {
                    adStored      = MarketSchema.AD_MAX_STORED,
                    watchCount    = 0,
                    adRechargeEnd = 0,
                }
            else
                local p = data.privilege
                if p.adStored      == nil then p.adStored      = MarketSchema.AD_MAX_STORED end
                if p.watchCount    == nil then p.watchCount    = 0 end
                if p.adRechargeEnd == nil then p.adRechargeEnd = 0 end
                if p.claimed       == nil then p.claimed       = {} end
                if p.watchDayId    == nil then p.watchDayId    = 0 end
                p.adStored      = tonumber(p.adStored)      or MarketSchema.AD_MAX_STORED
                p.watchCount    = tonumber(p.watchCount)    or 0
                p.adRechargeEnd = tonumber(p.adRechargeEnd) or 0
                p.watchDayId    = tonumber(p.watchDayId)    or 0
            end
        end,
        desc = "市场商店",
    },
}

return MarketSchema
