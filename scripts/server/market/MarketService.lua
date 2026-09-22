-- ============================================================================
-- MarketService - 市场商店业务逻辑（单机版）
-- 职责: 商品购买验证、补货/冷却判定、货币扣除与奖励发放（纯逻辑，禁止网络 IO）
-- 层级: server/market  |  通过 PDM 读写数据
-- 说明: 特权点/特权卡/特权广告玩法已随单机化移除，仅保留钻石商品。
-- ============================================================================

local PDM             = require("server.character.PlayerDataManager")
local CurrencyService = require("server.currency.CurrencyService")
local RelicService    = require("server.relic.RelicService")
local StellarQuota    = require("shared.market.StellarDiamondQuota")

local MarketService = {}

-- ======================== 商品配置（服务端权威） ========================

--- currency 配置名 → PDM currency 字段名映射
local CURRENCY_FIELD_MAP = {
    diamond   = "gems",
    gold      = "gold",
}

local COOLDOWN_SECONDS = {
    ["2h"] = 7200,
}

--- 商品配置版本号：每次调整 SHOP_ITEMS 序号时递增，登录时对比此版本号清除旧购买记录
local SHOP_CONFIG_VERSION = 7  -- 去掉每日折扣货，永久商品定价 /2

--- 服务端商品表
--- rewardType 统一使用 CurrencyService.REWARD_TO_CURRENCY 的 key（canonical 名称），特殊奖励在 Buy 内分支处理
local SHOP_ITEMS = {
    -- 钻石商品（永久，不限购；定价已 /2）
    [12] = { name = "冒险招募券",   rewardType = "adventure_ticket",      currency = "diamond", price = 90,  rewardCount = 1,    restockType = "permanent", limitCount = -1 },
    [13] = { name = "洗练石",       rewardType = "enhance_star",          currency = "diamond", price = 90,  rewardCount = 2,    restockType = "permanent", limitCount = -1 },
    [14] = { name = "点金石",       rewardType = "break_protect",         currency = "diamond", price = 250, rewardCount = 1,    restockType = "permanent", limitCount = -1 },
    [22] = { name = "腐化石",       rewardType = "corrupt_stone",         currency = "diamond", price = 250, rewardCount = 1,    restockType = "permanent", limitCount = -1 },
    [15] = { name = "奥术粉尘",     rewardType = "arcane_dust",           currency = "diamond", price = 90,  rewardCount = 288,  restockType = "permanent", limitCount = -1 },
    [16] = { name = "金币",         rewardType = "gold",                  currency = "diamond", price = 94,  rewardCount = 6666, restockType = "permanent", limitCount = -1 },
    [17] = { name = "精粹",         rewardType = "essence",               currency = "diamond", price = 94,  rewardCount = 666,  restockType = "permanent", limitCount = -1 },
    [20] = { name = "黄金钥匙",     rewardType = "golden_key",            currency = "diamond", price = 300, rewardCount = 1,    restockType = "permanent", limitCount = -1 },
}

-- 随机卷轴的具体类型列表
local SCROLL_TYPES = { "weaponScroll", "offhandScroll", "armorScroll", "helmetScroll", "shoesScroll", "accessoryScroll" }
-- camelCase → snake_case 映射（用于 rewardDetail 返回给客户端）
local SCROLL_TO_SNAKE = {
    weaponScroll    = "weapon_scroll",
    offhandScroll   = "offhand_scroll",
    armorScroll     = "armor_scroll",
    accessoryScroll = "accessory_scroll",
    helmetScroll    = "helmet_scroll",
    shoesScroll     = "shoes_scroll",
}

-- ======================== 内部工具 ========================

local function getActualPrice(item)
    return item.price
end

--- 获取当天编号（UTC+8，与 SignInConfig.getDayNumber 保持一致）
local function getDayId()
    return math.floor((os.time() + 28800) / 86400)
end

--- 获取商品的有效购买次数（考虑补货/重置）
---@param record table|nil { count, firstBuyTime, dayId }
---@param item table
---@return number bought 已购买次数（补货后为 0）
---@return boolean needReset
local function getEffectivePurchaseCount(record, item)
    if not record then return 0, false end

    if item.restockType == "daily" then
        local currentDay = getDayId()
        if (record.dayId or 0) ~= currentDay then
            return 0, true
        end
    elseif item.restockType == "cooldown" then
        local firstBuyTime = record.firstBuyTime or 0
        if firstBuyTime > 0 and (record.count or 0) > 0 then
            local cd = COOLDOWN_SECONDS[item.restockPeriod] or 7200
            if (os.time() - firstBuyTime) >= cd then
                return 0, true
            end
        end
    end
    return record.count or 0, false
end

--- 星辉招募券（id=18）市场每日剩余可购次数
---@param uid number
---@return number remaining
function MarketService.GetStellarDiamondBuyRemaining(uid)
    local item = SHOP_ITEMS[StellarQuota.ITEM_ID]
    if not item or item.limitCount <= 0 then return 999999 end
    local market = PDM.GetModule(uid, "market")
    if not market then return 0 end
    return StellarQuota.getRemaining(market.purchased, item.limitCount)
end

--- 消耗星辉券市场购买计数（仅 MarketService.Buy id=18 使用）
---@param uid number
---@param ticketCount number  本次用钻石补足的券数
---@return boolean ok
---@return string|nil reason
function MarketService.ConsumeStellarDiamondBuyQuota(uid, ticketCount)
    ticketCount = tonumber(ticketCount) or 0
    if ticketCount <= 0 then return true end

    local itemId = StellarQuota.ITEM_ID
    local item = SHOP_ITEMS[itemId]
    if not item then return false, "商品配置缺失" end

    local remaining = MarketService.GetStellarDiamondBuyRemaining(uid)
    if ticketCount > remaining then
        return false, "剩余购买次数不足"
    end

    local market = PDM.GetModule(uid, "market")
    if not market then return false, "数据未加载" end
    if not market.purchased then market.purchased = {} end

    local record = market.purchased[itemId]
    local bought, needReset = getEffectivePurchaseCount(record, item)
    if needReset or not record then
        record = { count = 0, firstBuyTime = 0, dayId = getDayId() }
    end
    record.count = bought + ticketCount
    if item.restockType == "daily" then
        record.dayId = getDayId()
    end
    market.purchased[itemId] = record
    PDM.MarkDirty(uid, "market")

    print("[MarketService] stellar diamond quota consume uid=" .. tostring(uid)
        .. " tickets=" .. ticketCount .. " purchased=" .. record.count .. "/" .. item.limitCount)
    return true
end

-- ======================== 登录时每日重置 ========================

--- 重置过期的每日限购记录（登录推送前调用，类似竞技场 resetShopWeekly）
--- 如果发生了重置，内部调用 MarkDirty
---@param uid number
---@return nil
function MarketService.ResetDailyShopItems(uid)
    local market = PDM.GetModule(uid, "market")
    if not market then return nil end

    local dirty = false

    -- 🔴 商品配置版本迁移：序号重排后旧购买记录与新商品不对应，必须清空
    if (market.shopConfigVersion or 0) < SHOP_CONFIG_VERSION then
        market.purchased = {}
        market.shopConfigVersion = SHOP_CONFIG_VERSION
        dirty = true
        print("[MarketService] shop config version migrated to " .. SHOP_CONFIG_VERSION .. " uid=" .. tostring(uid))
    end

    if not market.purchased then
        if dirty then PDM.MarkDirty(uid, "market") end
        return nil
    end

    local currentDay = getDayId()

    for itemId, record in pairs(market.purchased) do
        local item = SHOP_ITEMS[itemId]
        if not item then
            -- 商品已移除，清除残留记录
            market.purchased[itemId] = nil
            dirty = true
        elseif item.restockType == "daily" then
            if (record.dayId or 0) ~= currentDay then
                -- 跨天了，清除该商品的购买记录
                market.purchased[itemId] = nil
                dirty = true
            end
        end
    end

    if dirty then
        PDM.MarkDirty(uid, "market")
    end
    return nil
end

-- ======================== 购买商品 ========================

---@param uid number
---@param itemId number
---@param quantity number|nil 购买数量，默认 1，上限 99
---@return boolean ok
---@return string|nil reason
---@return table|nil result { itemId, purchased, firstBuyTime, rewardType, rewardName, rewardCount, rewardDetail }
function MarketService.Buy(uid, itemId, quantity)
    if not itemId then
        return false, "缺少商品ID"
    end
    quantity = math.max(1, math.min(99, quantity or 1))

    local item = SHOP_ITEMS[itemId]
    if not item then
        return false, "商品不存在"
    end

    local market = PDM.GetModule(uid, "market")
    if not market then
        return false, "数据未加载"
    end

    if not market.purchased then market.purchased = {} end
    local record = market.purchased[itemId]

    -- 检查购买次数限制（考虑批量数量）
    local bought = 0
    if item.limitCount > 0 then
        local needReset
        bought, needReset = getEffectivePurchaseCount(record, item)
        if needReset then
            record = { count = 0, firstBuyTime = 0, dayId = getDayId() }
            market.purchased[itemId] = record
            bought = 0
        end
        if bought >= item.limitCount then
            return false, "已达购买上限"
        end
        -- 限购时，实际购买量不得超过剩余可购量
        local remaining = item.limitCount - bought
        if quantity > remaining then
            quantity = remaining
        end
    end

    -- 检查货币余额 + 扣除（通过 CurrencyService，不直接操作 currency 表）
    local currField = CURRENCY_FIELD_MAP[item.currency]
    if not currField then
        return false, "未知货币类型"
    end

    local actualCost = getActualPrice(item) * quantity

    local deducted, newBalance = CurrencyService.Deduct(uid, currField, actualCost)
    if not deducted then
        return false, "余额不足"
    end

    -- 发放奖励（总数 = 单次数量 × 购买次数）
    local singleRewardCount = item.rewardCount or 1
    local totalRewardCount = singleRewardCount * quantity
    local rewardDetail = nil  -- 额外奖励信息（随机卷轴时返回实际卷轴类型）

    if item.rewardType == "random_scroll" then
        -- 随机卷轴：每个独立随机类型，按类型聚合后加到 currency
        local currency_mod = PDM.GetModule(uid, "currency")
        if currency_mod then
            local scrolls = {}
            for i = 1, totalRewardCount do
                local st = SCROLL_TYPES[math.random(1, #SCROLL_TYPES)]
                scrolls[st] = (scrolls[st] or 0) + 1
            end
            for st, n in pairs(scrolls) do
                currency_mod[st] = (currency_mod[st] or 0) + n
            end
            PDM.MarkDirty(uid, "currency")
            rewardDetail = { scrolls = scrolls }
            local parts = {}
            for st, n in pairs(scrolls) do parts[#parts + 1] = st .. "x" .. n end
            print("[MarketService] random_scroll -> " .. table.concat(parts, ", "))
        end
    elseif item.rewardType == "speed_card" then
        local currency_mod = PDM.GetModule(uid, "currency")
        if not currency_mod then
            CurrencyService.Add(uid, currField, actualCost)
            return false, "货币数据未加载"
        end
        local now = os.time()
        local baseExpire = math.max(now, tonumber(currency_mod.speedCardExpireAt) or 0)
        currency_mod.speedCardExpireAt = baseExpire + 86400 * totalRewardCount
        PDM.MarkDirty(uid, "currency")
        rewardDetail = { speedCardExpireAt = currency_mod.speedCardExpireAt }
        print("[MarketService] speed_card activated uid=" .. tostring(uid)
            .. " expireAt=" .. tostring(currency_mod.speedCardExpireAt))
    elseif item.rewardType == "random_quality_relic" then
        local relicData = PDM.GetModule(uid, "mod_relics")
        if not relicData then
            CurrencyService.Add(uid, currField, actualCost)
            return false, "遗物数据未加载"
        end
        if #relicData.bag + totalRewardCount > RelicService.MAX_BAG then
            CurrencyService.Add(uid, currField, actualCost)
            return false, "遗物背包已满"
        end
        local relics = {}
        for _ = 1, totalRewardCount do
            local okRelic, errRelic, resultRelic = RelicService.GmGiveRelic(uid, math.random(1, 5), 2)
            if not okRelic then
                CurrencyService.Add(uid, currField, actualCost)
                return false, errRelic or "遗物生成失败"
            end
            if resultRelic and resultRelic.relic then
                relics[#relics + 1] = resultRelic.relic
            end
        end
        rewardDetail = { relics = relics }
    else
        local granted = CurrencyService.GrantReward(uid, { type = item.rewardType, amount = totalRewardCount })
        if not granted then
            -- 回滚扣除
            CurrencyService.Add(uid, currField, actualCost)
            return false, "奖励配置错误: " .. tostring(item.rewardType)
        end
    end

    -- 更新购买记录
    if not record then
        record = { count = 0, firstBuyTime = 0 }
    end
    local prevCount = record.count or 0
    record.count = prevCount + quantity
    if item.restockType == "cooldown" then
        if prevCount == 0 then
            record.firstBuyTime = os.time()
        end
    elseif item.restockType == "daily" then
        record.dayId = getDayId()
    end
    market.purchased[itemId] = record
    PDM.MarkDirty(uid, "market")

    print("[MarketService] Buy uid=" .. tostring(uid)
        .. " itemId=" .. tostring(itemId) .. " (" .. item.name .. ")"
        .. " qty=" .. quantity
        .. " cost=" .. actualCost .. " " .. currField
        .. " reward=+" .. totalRewardCount .. " " .. item.rewardType
        .. " purchased=" .. record.count .. "/" .. tostring(item.limitCount))

    -- 高价值购买（含加速卡 expireAt）立即刷盘，避免防抖窗口内重启丢档
    PDM.FlushImmediate(uid)

    return true, nil, {
        itemId       = itemId,
        purchased    = record.count,
        firstBuyTime = record.firstBuyTime or 0,
        rewardType   = item.rewardType,
        rewardName   = item.name,
        rewardCount  = totalRewardCount,
        rewardDetail = rewardDetail,
    }
end

return MarketService
