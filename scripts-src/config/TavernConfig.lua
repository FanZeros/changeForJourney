-- ============================================================================
-- TavernConfig - 酒馆配置（双端共享）
-- ============================================================================

local TavernConfig = {}

-- 周期基准时间（与 ArenaConfig 保持一致）
TavernConfig.WEEK_EPOCH    = 1704038400   -- 2024-01-01 00:00:00 UTC
TavernConfig.WEEK_SECONDS  = 604800       -- 7天

-- 日周期（UTC+8 自然日）
TavernConfig.DAY_SECONDS   = 86400

-- ======================== 商品配置 ========================
-- 与 TavernShopPage.lua 的客户端 SHOP_ITEMS 保持同步
-- 英雄 ID: 1=卡琳 2=麦琪 3=琳达 4=塞西莉亚 5=维多利亚 6=露娜
--          7=星织 8=绫音 9=芙罗拉 10=丽贝卡 11=素华 12=艾丝翠德
--          13=罗莎琳 14=幽夜 15=伊丽莎白 16=洛星绘 20=梅丽莎

TavernConfig.SHOP_ITEMS = {
    -- 每日购买（limitCycle="daily"）
    { id = 1,  name = "冒险招募券",   limitCycle = "daily",  limitCount = 5,  price = 40,  rewardType = "recruitTicket", rewardCount = 1 },
    { id = 102, name = "星辉招募券",   limitCycle = "daily",  limitCount = 5,  price = 160, rewardType = "stellarRecruitTicket", rewardCount = 1 },
    -- 每日购买（limitCycle="daily"）—— N 碎片（品质3）
    { id = 2,  name = "卡琳-碎片",    limitCycle = "daily", limitCount = 50, price = 15,  rewardType = "shard", rewardHeroId = 1,  rewardCount = 1 },
    { id = 3,  name = "麦琪-碎片",    limitCycle = "daily", limitCount = 50, price = 15,  rewardType = "shard", rewardHeroId = 2,  rewardCount = 1 },
    { id = 4,  name = "琳达-碎片",    limitCycle = "daily", limitCount = 50, price = 15,  rewardType = "shard", rewardHeroId = 3,  rewardCount = 1 },
    -- R 碎片（品质4）
    { id = 5,  name = "塞西莉亚-碎片", limitCycle = "daily", limitCount = 50, price = 60,  rewardType = "shard", rewardHeroId = 4,  rewardCount = 1 },
    { id = 6,  name = "维多利亚-碎片", limitCycle = "daily", limitCount = 50, price = 60,  rewardType = "shard", rewardHeroId = 5,  rewardCount = 1 },
    { id = 7,  name = "露娜-碎片",    limitCycle = "daily", limitCount = 50, price = 60,  rewardType = "shard", rewardHeroId = 6,  rewardCount = 1 },
    { id = 8,  name = "星织-碎片",    limitCycle = "daily", limitCount = 50, price = 60,  rewardType = "shard", rewardHeroId = 7,  rewardCount = 1 },
    { id = 9,  name = "绫音-碎片",    limitCycle = "daily", limitCount = 50, price = 60,  rewardType = "shard", rewardHeroId = 8,  rewardCount = 1 },
    { id = 10, name = "芙罗拉-碎片",  limitCycle = "daily", limitCount = 50, price = 60,  rewardType = "shard", rewardHeroId = 9,  rewardCount = 1 },
    -- SR 碎片（品质5）
    { id = 11, name = "丽贝卡-碎片",  limitCycle = "daily", limitCount = 50, price = 250, rewardType = "shard", rewardHeroId = 10, rewardCount = 1 },
    { id = 12, name = "素华-碎片",    limitCycle = "daily", limitCount = 50, price = 250, rewardType = "shard", rewardHeroId = 11, rewardCount = 1 },
    { id = 13, name = "艾丝翠德-碎片", limitCycle = "daily", limitCount = 50, price = 250, rewardType = "shard", rewardHeroId = 12, rewardCount = 1 },
    { id = 14, name = "罗莎琳-碎片",  limitCycle = "daily", limitCount = 50, price = 250, rewardType = "shard", rewardHeroId = 13, rewardCount = 1 },
    { id = 15, name = "幽夜-碎片",    limitCycle = "daily", limitCount = 50, price = 250, rewardType = "shard", rewardHeroId = 14, rewardCount = 1 },
    { id = 16, name = "伊丽莎白-碎片", limitCycle = "daily", limitCount = 50, price = 250, rewardType = "shard", rewardHeroId = 15, rewardCount = 1 },
    { id = 17, name = "亚历克斯-碎片", limitCycle = "daily", limitCount = 50, price = 250, rewardType = "shard", rewardHeroId = 21, rewardCount = 1 },
    { id = 18, name = "赛拉-碎片",    limitCycle = "daily", limitCount = 50, price = 250, rewardType = "shard", rewardHeroId = 22, rewardCount = 1 },
    { id = 19, name = "艾尔温-碎片",  limitCycle = "daily", limitCount = 50, price = 250, rewardType = "shard", rewardHeroId = 23, rewardCount = 1 },
    { id = 101, name = "洛星绘-碎片", limitCycle = "daily", limitCount = 20, price = 1125, rewardType = "shard", rewardHeroId = 16, rewardCount = 1 },
    { id = 103, name = "梅丽莎-碎片", limitCycle = "daily", limitCount = 20, price = 1125, rewardType = "shard", rewardHeroId = 20, rewardCount = 1 },
}

--- 根据 id 查找商品配置
---@param itemId number
---@return table|nil
function TavernConfig.getShopItem(itemId)
    for _, item in ipairs(TavernConfig.SHOP_ITEMS) do
        if item.id == itemId then return item end
    end
    return nil
end

--- 计算当前 weekId
---@param timestamp number|nil 时间戳（默认 os.time()）
---@return number weekId
function TavernConfig.calcWeekId(timestamp)
    local t = timestamp or os.time()
    return math.floor((t - TavernConfig.WEEK_EPOCH) / TavernConfig.WEEK_SECONDS)
end

--- 计算当前 dayId（UTC+8 自然日）
---@param timestamp number|nil 时间戳（默认 os.time()）
---@return number dayId
function TavernConfig.calcDayId(timestamp)
    local t = timestamp or os.time()
    return math.floor((t + 28800) / TavernConfig.DAY_SECONDS)
end

--- 跨日/跨周时重置酒馆商店限购记录（双端共享，不写 PDM）
---@param tavern table
---@param timestamp number|nil
---@return boolean dirty 是否发生了重置
function TavernConfig.applyShopPeriodReset(tavern, timestamp)
    if not tavern then return false end
    local t = timestamp or os.time()
    local dayId  = TavernConfig.calcDayId(t)
    local weekId = TavernConfig.calcWeekId(t)
    local dirty  = false
    local purchased = tavern.shopPurchased or {}

    if (tavern.shopDayId or 0) ~= dayId then
        local kept = {}
        for id, count in pairs(purchased) do
            local numId = tonumber(id) or id
            local cfg = TavernConfig.getShopItem(numId)
            if cfg and cfg.limitCycle ~= "daily" then
                kept[numId] = count
            end
        end
        purchased = kept
        tavern.shopPurchased = purchased
        tavern.shopDayId = dayId
        dirty = true
    end

    if (tavern.shopWeekId or 0) ~= weekId then
        local kept = {}
        for id, count in pairs(purchased) do
            local numId = tonumber(id) or id
            local cfg = TavernConfig.getShopItem(numId)
            if cfg and cfg.limitCycle ~= "weekly" then
                kept[numId] = count
            end
        end
        tavern.shopPurchased = kept
        tavern.shopWeekId = weekId
        dirty = true
    end

    return dirty
end

return TavernConfig
