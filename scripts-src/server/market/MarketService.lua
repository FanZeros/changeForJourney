-- ============================================================================
-- MarketService - 市场商店业务逻辑
-- 职责: 商品购买验证、补货/冷却判定、货币扣除与奖励发放（纯逻辑，禁止网络 IO）
-- 层级: server/market  |  通过 PDM 读写数据
-- ============================================================================

local SaveManager     = require("server.SaveManager")
local PDM             = require("server.character.PlayerDataManager")
local CurrencyService = require("server.currency.CurrencyService")
local StageConfig     = require("config.StageConfig")
local MarketSchema    = require("shared.market.MarketSchema")
local RelicService    = require("server.relic.RelicService")
local MileCompLogic   = require("server.market.PrivilegeMileCompLogic")
local PrivCardLogic   = require("server.market.PrivilegeCardLogic")
local StellarQuota    = require("shared.market.StellarDiamondQuota")
local ServerListConfig = require("shared.ServerListConfig")
local cjson             = cjson

local MarketService = {}

-- 选服界面发起的已结束挑战者区特权卡转出请求，防止重复点击并发写档
local closedChallengerTransferPending = {}

-- ======================== 商品配置（服务端权威） ========================

--- currency 配置名 → PDM currency 字段名映射
local CURRENCY_FIELD_MAP = {
    privilege = "privilegePoint",
    diamond   = "gems",
    gold      = "gold",
}

local COOLDOWN_SECONDS = {
    ["2h"] = 7200,
}

--- 商品配置版本号：每次调整 SHOP_ITEMS 序号时递增，登录时对比此版本号清除旧购买记录
local SHOP_CONFIG_VERSION = 4  -- 新增腐化石 id 21/22、神圣石特权商品 id 23

--- 特权里程「特权点」档位奖励版本（仅 10/20/30 三档为 privilege_point）
--- v1: 10→3, 20→5, 30→5  |  v2: 10→5, 20→7, 30→10
local PRIVILEGE_MILE_REWARD_VERSION = MileCompLogic.PRIVILEGE_MILE_REWARD_VERSION

--- 服务端商品表
--- rewardType 统一使用 CurrencyService.REWARD_TO_CURRENCY 的 key（canonical 名称），特殊奖励在 Buy 内分支处理
local SHOP_ITEMS = {
    -- 特权点商品（每日刷新）
    [1]  = { name = "扫荡券",       rewardType = "sweep_ticket",          currency = "privilege", price = 1,  rewardCount = 1,   restockType = "daily", limitCount = 10 },
    [2]  = { name = "冒险招募券",   rewardType = "adventure_ticket",      currency = "privilege", price = 1,  rewardCount = 1,   restockType = "daily", limitCount = 20 },
    [3]  = { name = "钻石",         rewardType = "diamond",               currency = "privilege", price = 1,  rewardCount = 240, restockType = "daily", limitCount = 20 },
    [4]  = { name = "随机卷轴",     rewardType = "random_scroll",         currency = "privilege", price = 1,  rewardCount = 20,  restockType = "daily", limitCount = 6  },
    [5]  = { name = "加速卡",       rewardType = "speed_card",            currency = "privilege", price = 10, rewardCount = 1,   restockType = "daily", limitCount = 1  },
    [6]  = { name = "随机优质遗物", rewardType = "random_quality_relic",  currency = "privilege", price = 1,  rewardCount = 1,   restockType = "daily", limitCount = 5  },
    [7]  = { name = "奥术粉尘",     rewardType = "arcane_dust",           currency = "privilege", price = 1,  rewardCount = 288, restockType = "daily", limitCount = 5  },
    -- 钻石商品（每日刷新，40% 折扣）
    [8]  = { name = "冒险招募券",   rewardType = "adventure_ticket",      currency = "diamond", price = 180, discount = 0.4, rewardCount = 1,  restockType = "daily", limitCount = 2 },
    [9]  = { name = "洗练石",       rewardType = "enhance_star",          currency = "diamond", price = 180, discount = 0.4, rewardCount = 2,  restockType = "daily", limitCount = 5 },
    [10] = { name = "随机卷轴",     rewardType = "random_scroll",         currency = "diamond", price = 180, discount = 0.4, rewardCount = 10, restockType = "daily", limitCount = 5 },
    [11] = { name = "点金石",       rewardType = "break_protect",         currency = "diamond", price = 500, discount = 0.4, rewardCount = 1,  restockType = "daily", limitCount = 3 },
    [21] = { name = "腐化石",       rewardType = "corrupt_stone",         currency = "diamond", price = 500, discount = 0.4, rewardCount = 1,  restockType = "daily", limitCount = 3 },
    -- 钻石商品（永久，不限购）
    [12] = { name = "冒险招募券",   rewardType = "adventure_ticket",      currency = "diamond", price = 180, rewardCount = 1,   restockType = "permanent", limitCount = -1 },
    [13] = { name = "洗练石",       rewardType = "enhance_star",          currency = "diamond", price = 180, rewardCount = 2,   restockType = "permanent", limitCount = -1 },
    [14] = { name = "点金石",       rewardType = "break_protect",         currency = "diamond", price = 500, rewardCount = 1,   restockType = "permanent", limitCount = -1 },
    [22] = { name = "腐化石",       rewardType = "corrupt_stone",         currency = "diamond", price = 500, rewardCount = 1,   restockType = "permanent", limitCount = -1 },
    [15] = { name = "奥术粉尘",     rewardType = "arcane_dust",           currency = "diamond", price = 180, rewardCount = 288, restockType = "permanent", limitCount = -1 },
    [16] = { name = "金币",         rewardType = "gold",                  currency = "diamond", price = 188, rewardCount = 6666, restockType = "permanent", limitCount = -1 },
    [17] = { name = "精粹",         rewardType = "essence",               currency = "diamond", price = 188, rewardCount = 666,  restockType = "permanent", limitCount = -1 },
    -- 星辉招募券（每日刷新）
    [18] = { name = "星辉招募券",   rewardType = "stellar_ticket",      currency = "diamond", price = 900, discount = 0.8, rewardCount = 1,   restockType = "daily", limitCount = 30 },
    [19] = { name = "星辉招募券",   rewardType = "stellar_ticket",      currency = "privilege", price = 4,  rewardCount = 1,   restockType = "daily", limitCount = 10 },
    [23] = { name = "神圣石",       rewardType = "sacred_stone",        currency = "privilege", price = 5,  rewardCount = 1,   restockType = "daily", limitCount = 5  },
    [20] = { name = "黄金钥匙",     rewardType = "golden_key",          currency = "diamond", price = 600, rewardCount = 1,   restockType = "permanent", limitCount = -1 },
}

-- 随机卷轴的具体类型列表
local SCROLL_TYPES = { "weaponScroll", "offhandScroll", "armorScroll", "accessoryScroll" }
-- camelCase → snake_case 映射（用于 rewardDetail 返回给客户端）
local SCROLL_TO_SNAKE = {
    weaponScroll    = "weapon_scroll",
    offhandScroll   = "offhand_scroll",
    armorScroll     = "armor_scroll",
    accessoryScroll = "accessory_scroll",
}

-- ======================== 内部工具 ========================

local function getActualPrice(item)
    if item.discount then
        return math.floor(item.price * item.discount)
    end
    return item.price
end

--- 获取当天编号（UTC+8，与 SignInConfig.getDayNumber 保持一致）
local function getDayId()
    return math.floor((os.time() + 28800) / 86400)
end

--- 检测并执行特权广告每日重置
--- 若 priv.watchDayId 不等于今天，重置 watchCount/claimed/watchDayId
---@param priv table  privilege 子对象（就地修改）
---@return boolean reset  true=发生了重置
local function resetPrivilegeIfNewDay(priv)
    local today = getDayId()
    if (priv.watchDayId or 0) ~= today then
        priv.watchCount  = 0
        priv.claimed     = {}
        priv.watchDayId  = today
        return true
    end
    return false
end

--- 玩家是否已激活特权卡
---@param uid number
---@return boolean
local function isPrivilegeCardOwned(uid)
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return false end
    return (currency.privilegeCardOwned or 0) >= 1
end

--- 特权卡福利：每日 100 特权点 + 特权里程进度填满（watchCount→30）
---@param uid number
---@param priv table|nil  market.privilege；nil 时仅尝试发每日点数
---@return table result { grantedPoints=number|nil, watchFilled=boolean, dirtyMarket=boolean, dirtyCurrency=boolean }
function MarketService.ApplyPrivilegeCardDailyBenefits(uid, priv)
    local result = {
        grantedPoints = nil,
        watchFilled   = false,
        dirtyMarket   = false,
        dirtyCurrency = false,
    }
    if not isPrivilegeCardOwned(uid) then
        return result
    end

    local today = getDayId()
    local currency = PDM.GetModule(uid, "currency")
    if currency and (currency.privilegeCardDailyGrantDayId or 0) ~= today then
        local pts = PrivCardLogic.DAILY_PRIVILEGE_POINTS
        if CurrencyService.GrantReward(uid, { type = "privilege_point", amount = pts }) then
            currency.privilegeCardDailyGrantDayId = today
            PDM.MarkDirty(uid, "currency")
            result.grantedPoints = pts
            result.dirtyCurrency = true
            print("[MarketService] privilege card daily points uid=" .. tostring(uid)
                .. " +" .. pts)
        end
    end

    if priv and (priv.watchCount or 0) < PrivCardLogic.FULL_WATCH_COUNT then
        priv.watchCount = PrivCardLogic.FULL_WATCH_COUNT
        result.watchFilled = true
        result.dirtyMarket = true
        print("[MarketService] privilege card watch fill uid=" .. tostring(uid)
            .. " watchCount=" .. PrivCardLogic.FULL_WATCH_COUNT)
    end

    return result
end

--- 确保 privilege 已按日重置，并应用特权卡当日福利
---@param uid number
---@return table|nil priv
---@return boolean dirtyMarket
---@return table cardResult
local function ensurePrivilegeForToday(uid)
    local market = PDM.GetModule(uid, "market")
    if not market then return nil, false end
    if not market.privilege then
        market.privilege = {
            adStored      = MarketSchema.AD_MAX_STORED,
            watchCount    = 0,
            adRechargeEnd = 0,
            claimed       = {},
            watchDayId    = 0,
        }
    end
    local priv = market.privilege
    if not priv.claimed then priv.claimed = {} end

    local dirty = false
    if resetPrivilegeIfNewDay(priv) then
        dirty = true
    end
    local cardResult = MarketService.ApplyPrivilegeCardDailyBenefits(uid, priv)
    if cardResult.dirtyMarket then dirty = true end
    if cardResult.dirtyCurrency then
        -- ApplyPrivilegeCardDailyBenefits 内部已 MarkDirty currency
    end
    if dirty then
        PDM.MarkDirty(uid, "market")
    end
    return priv, dirty, cardResult
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

--- 补偿旧版特权里程特权点差额（一次性，按玩家持久化版本号去重）
--- 先执行 privilege 每日重置，再读 claimed，避免云端残留昨日 claimed 误补。
---@param uid number
---@return table|nil mileComp { amount = number } 有补差时返回，供登录后弹窗提示
function MarketService.CompensatePrivilegeMileRewardBump(uid)
    local market = PDM.GetModule(uid, "market")
    if not market then return nil end
    local currentMileVersion = market.privilegeMileRewardVersion or 1
    if currentMileVersion >= PRIVILEGE_MILE_REWARD_VERSION then
        return nil
    end

    if not market.privilege then
        market.privilege = {
            adStored      = MarketSchema.AD_MAX_STORED,
            watchCount    = 0,
            adRechargeEnd = 0,
            claimed       = {},
            watchDayId    = 0,
        }
    end
    local priv = market.privilege
    if not priv.claimed then priv.claimed = {} end

    local compResult = nil
    if currentMileVersion < 4 then
        local totalDiff, detailStr = MileCompLogic.calcCompensationAmount(priv.claimed)
        if totalDiff > 0 then
            local currencyBefore = PDM.GetModule(uid, "currency")
            local ptsBefore = currencyBefore and (currencyBefore.privilegePoint or 0) or 0
            local granted = CurrencyService.GrantReward(uid, { type = "privilege_point", amount = totalDiff })
            if not granted then
                print("[MarketService][ERROR] privilege mile bump GrantReward FAILED uid=" .. tostring(uid)
                    .. " amount=" .. tostring(totalDiff))
                return nil
            end
            compResult = { amount = totalDiff }
            local currencyAfter = PDM.GetModule(uid, "currency")
            local ptsAfter = currencyAfter and (currencyAfter.privilegePoint or 0) or 0
            print("[MarketService] privilege mile bump compensate uid=" .. tostring(uid)
                .. " total=+" .. totalDiff .. " detail=[" .. detailStr .. "]"
                .. " privilegePoint " .. tostring(ptsBefore) .. "→" .. tostring(ptsAfter))
        else
            print("[MarketService] privilege mile bump migrate uid=" .. tostring(uid)
                .. " (no same-day old claims, skip compensate)")
        end
    end

    -- v3：25 档改为星辉招募券；v4：30 档改为随主线进度的大量精粹，清空对应领取标记（保留 watchCount）
    if currentMileVersion < 4 then
        MileCompLogic.resetPrivilegeMileProgressForRewardBump(priv)
        print("[MarketService] privilege mile v4 clear threshold 25/30 claimed uid=" .. tostring(uid)
            .. " watchCount=" .. tostring(priv.watchCount or 0))
    end

    -- v5：5/10/15/20/25 档奖励改版，30 档不变；清空新奖励档位领取标记（保留 watchCount）
    if currentMileVersion < 5 then
        MileCompLogic.resetPrivilegeMileProgressForV5(priv)
        print("[MarketService] privilege mile v5 clear threshold 5/10/15/20/25 claimed uid=" .. tostring(uid)
            .. " watchCount=" .. tostring(priv.watchCount or 0))
    end

    market.privilegeMileRewardVersion = PRIVILEGE_MILE_REWARD_VERSION
    PDM.MarkDirty(uid, "market")
    -- 版本号与补差货币必须立即落盘，避免下次登录重复补发
    PDM.FlushImmediate(uid)
    return compResult
end

--- 重置过期的每日限购记录（登录推送前调用，类似竞技场 resetShopWeekly）
--- 如果发生了重置，内部调用 MarkDirty
---@param uid number
---@return table|nil result { mileComp, dailyGrantPoints }
function MarketService.ResetDailyShopItems(uid)
    local market = PDM.GetModule(uid, "market")
    if not market then return nil end

    -- 特权每日重置 + 特权卡每日 100 点（先于里程补差，确保 claimed 已按日清空）
    local _, _, cardResult = ensurePrivilegeForToday(uid)
    local dailyGrantPoints = cardResult and cardResult.grantedPoints or nil

    -- 里程特权点数值上调：一次性补差
    local mileComp = MarketService.CompensatePrivilegeMileRewardBump(uid)

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
        return { mileComp = mileComp, dailyGrantPoints = dailyGrantPoints }
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
    return { mileComp = mileComp, dailyGrantPoints = dailyGrantPoints }
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

-- ======================== 特权广告 ========================

--- 特权广告槽位始终可用（已移除补充冷却，仅归一化存档字段）
---@param priv table  privilege 子对象（会被就地修改）
---@return table priv  同一引用
local function refreshPrivilegeAdStored(priv)
    priv.adStored      = MarketSchema.AD_MAX_STORED
    priv.adRechargeEnd = 0
    return priv
end

--- 将 privilege 内部状态转换为客户端推送格式
---@param priv table
---@return table  { adStored, watchCount, adRechargeMin, adRemainSecs, claimed }
local function privToClientPayload(priv)
    local remainSecs = 0
    if priv.adRechargeEnd > 0 then
        remainSecs = math.max(0, priv.adRechargeEnd - os.time())
    end
    -- claimed: map {[threshold]=true} → 数组 [threshold, ...]（客户端 ipairs 遍历用）
    local claimedArr = {}
    if priv.claimed then
        for th, _ in pairs(priv.claimed) do
            claimedArr[#claimedArr + 1] = tonumber(th)
        end
    end
    return {
        adStored      = priv.adStored,
        watchCount    = priv.watchCount,
        adRechargeMin = math.ceil(remainSecs / 60),  -- 保留兼容字段
        adRemainSecs  = remainSecs,                   -- 精确秒数，客户端用于实时倒计时
        claimed       = claimedArr,
    }
end

--- 处理玩家观看特权广告
--- 成功后：watchCount+1、发放特权点、返回新状态供推送
---@param uid number
---@param force boolean|nil  保留参数（AD_CONFIRM 路径兼容，安全性由 pending 标记保证）
---@return boolean ok
---@return string|nil reason
---@return table|nil payload  供客户端 setPrivilegeData 使用
function MarketService.WatchPrivilegeAd(uid, force)
    local market = PDM.GetModule(uid, "market")
    if not market then
        return false, "数据未加载"
    end

    local priv = ensurePrivilegeForToday(uid)
    if not priv then
        return false, "数据未加载"
    end

    refreshPrivilegeAdStored(priv)

    priv.watchCount = priv.watchCount + 1

    -- 发放特权点（特权商店看广告）
    local adReward = MarketSchema.AD_PRIVILEGE_REWARD_PER_WATCH
    local granted = CurrencyService.GrantReward(uid, { type = "privilege_point", amount = adReward })
    if not granted then
        priv.watchCount = priv.watchCount - 1
        return false, "特权点发放失败"
    end

    PDM.MarkDirty(uid, "market")

    local payload = privToClientPayload(priv)
    print("[MarketService] WatchPrivilegeAd uid=" .. tostring(uid)
        .. " adStored=" .. priv.adStored
        .. " watchCount=" .. priv.watchCount
        .. " adRechargeEnd=" .. priv.adRechargeEnd
        .. " rechargeMin=" .. payload.adRechargeMin)

    return true, nil, payload
end

-- 里程碑奖励配置（与客户端 MarketPage.PRIVILEGE_REWARDS 保持一致）
local PRIVILEGE_MILE_REWARDS = {
    { threshold = 5,  rewardType = "adventure_ticket", amount = 5 },
    { threshold = 10, rewardType = "diamond",          amount = 1000 },
    { threshold = 15, rewardType = "diamond",          amount = 2000 },
    { threshold = 20, rewardType = "golden_key",       amount = 10 },
    { threshold = 25, rewardType = "stellar_ticket",   amount = 10 },
    { threshold = 30, rewardType = "essence_by_stage" },
}
-- threshold → reward 快查表
local MILE_REWARD_BY_THRESHOLD = {}
for _, r in ipairs(PRIVILEGE_MILE_REWARDS) do
    MILE_REWARD_BY_THRESHOLD[r.threshold] = r
end

local function calcPrivilegeEssenceReward(uid)
    local battle = PDM.GetModule(uid, "battle")
    local stageId = battle and (tonumber(battle.maxStageId) or tonumber(battle.currentStageId)) or 0
    local stageEntry = stageId > 0 and StageConfig.getStage(stageId) or nil
    local baseEssence = tonumber(stageEntry and stageEntry.fcEssence) or 38
    return math.max(20000, baseEssence * 300), stageId
end

--- 领取特权里程奖励
---@param uid number
---@param threshold number  要领取的里程阈值
---@return boolean ok
---@return string|nil reason
---@return table|nil result  { threshold, rewardType, amount }
function MarketService.ClaimPrivilegeReward(uid, threshold)
    threshold = tonumber(threshold)
    if not threshold then
        return false, "参数错误"
    end

    local rewardCfg = MILE_REWARD_BY_THRESHOLD[threshold]
    if not rewardCfg then
        return false, "无效的里程阈值"
    end

    local market = PDM.GetModule(uid, "market")
    if not market then
        return false, "数据未加载"
    end

    local priv = ensurePrivilegeForToday(uid)
    if not priv then
        return false, "数据未加载"
    end
    if not priv.claimed then priv.claimed = {} end

    -- 检查是否已领取
    if priv.claimed[threshold] then
        return false, "该奖励已领取"
    end

    -- 检查观看次数是否达标
    if (priv.watchCount or 0) < threshold then
        return false, "累计观看次数不足"
    end

    -- 发放奖励
    local rewardType = rewardCfg.rewardType
    local rewardAmount = rewardCfg.amount
    local rewardDetail = nil
    if rewardType == "essence_by_stage" then
        rewardType = "essence"
        rewardAmount, rewardDetail = calcPrivilegeEssenceReward(uid)
        rewardDetail = { stageId = rewardDetail }
    end
    local granted = CurrencyService.GrantReward(uid, { type = rewardType, amount = rewardAmount })
    if not granted then
        return false, "奖励发放失败: " .. tostring(rewardType)
    end

    -- 标记已领取
    priv.claimed[threshold] = true
    PDM.MarkDirty(uid, "market")

    print("[MarketService] ClaimPrivilegeReward uid=" .. tostring(uid)
        .. " threshold=" .. threshold
        .. " reward=" .. rewardType .. "x" .. rewardAmount)

    return true, nil, {
        threshold   = threshold,
        rewardType  = rewardType,
        amount      = rewardAmount,
        rewardDetail = rewardDetail,
        privPayload = privToClientPayload(priv),  -- 供 handler 推送最新 privilege 状态
    }
end

--- 获取特权广告当前状态（登录时推送用）
---@param uid number
---@return table|nil  { adStored, watchCount, adRechargeMin }
function MarketService.GetPrivilegeAdPayload(uid)
    local priv = ensurePrivilegeForToday(uid)
    if not priv then return nil end
    refreshPrivilegeAdStored(priv)
    return privToClientPayload(priv)
end

--- 兑换/GM 激活特权卡后立即发放当日福利
---@param uid number
---@return table|nil result { privPayload, grantedPoints }
function MarketService.OnPrivilegeCardActivated(uid)
    local priv, _, cardResult = ensurePrivilegeForToday(uid)
    if not priv then return nil end
    refreshPrivilegeAdStored(priv)
    return {
        privPayload    = privToClientPayload(priv),
        grantedPoints  = cardResult.grantedPoints,
    }
end

--- 特权卡转区：移除当前区服特权卡，写入 global_profile 待转入标记，并返回选服界面
---@param uid number
---@return boolean ok
---@return string|nil reason
function MarketService.TransferPrivilegeCard(uid)
    if not isPrivilegeCardOwned(uid) then
        return false, "未拥有特权卡"
    end

    local gp = PDM.GetModule(uid, "global_profile")
    if not gp then
        return false, "数据未加载"
    end
    if (gp.pendingPrivilegeCardTransfer or 0) >= 1 then
        return false, "已有待转区的特权卡"
    end

    local serverId = PDM.GetServerId(uid) or SaveManager.getServerId(uid)
    if not serverId then
        return false, "区服信息异常"
    end

    local currency = PDM.GetModule(uid, "currency")
    if not currency then
        return false, "数据未加载"
    end

    currency.privilegeCardOwned = 0
    PDM.MarkDirty(uid, "currency")

    gp.pendingPrivilegeCardTransfer = 1
    gp.pendingPrivilegeCardTransferFrom = serverId
    PDM.MarkDirty(uid, "global_profile")

    local smGp = SaveManager.getTable(uid, "global_profile")
    if smGp then
        smGp.pendingPrivilegeCardTransfer = 1
        smGp.pendingPrivilegeCardTransferFrom = serverId
    end
    local smCur = SaveManager.getTable(uid, "currency")
    if smCur then
        smCur.privilegeCardOwned = 0
    end

    PDM.FlushImmediate(uid)

    print("[MarketService] privilege card transfer initiated uid=" .. tostring(uid)
        .. " fromServerId=" .. tostring(serverId))

    return true, nil
end

--- 挑战者活动结束后，从选服界面直接转出该区服的特权卡。
--- 此时区服模块尚未加载，直接读写挑战者区 currency 的独立 cloud key；
--- global_profile 仍由 PDM 作为权威内存源，并在 cloud 写成功后立即刷盘。
---@param uid number
---@param sourceServerId number
---@param callback fun(ok: boolean, reason: string|nil)
function MarketService.TransferClosedChallengerCard(uid, sourceServerId, callback)
    callback = callback or function() end
    sourceServerId = tonumber(sourceServerId)

    local ServerListConfig = require("shared.ServerListConfig")
    if not sourceServerId or not ServerListConfig.isChallengerServer(sourceServerId) then
        callback(false, "挑战者区信息异常")
        return
    end
    if not ServerListConfig.isServerClosed(sourceServerId) then
        callback(false, "挑战者活动尚未结束")
        return
    end
    if closedChallengerTransferPending[uid] then
        callback(false, "特权卡正在转出，请稍候")
        return
    end

    local gp = PDM.GetModule(uid, "global_profile")
    if not gp then
        callback(false, "全局数据未加载")
        return
    end
    if (gp.pendingPrivilegeCardTransfer or 0) >= 1 then
        callback(false, "已有待转区的特权卡")
        return
    end
    local played = type(gp.servers) == "table"
        and (gp.servers[tostring(sourceServerId)] or gp.servers[sourceServerId])
    if not played then
        callback(false, "该挑战者区没有角色记录")
        return
    end

    closedChallengerTransferPending[uid] = true
    local cloudKey = ServerListConfig.getKeyPrefix(sourceServerId) .. "mod_currency"
    serverCloud:Get(uid, cloudKey, {
        ok = function(scores)
            local cloudRoot = scores and scores[cloudKey]
            local currency = type(cloudRoot) == "table" and cloudRoot.currency or nil
            if type(currency) ~= "table" or (tonumber(currency.privilegeCardOwned) or 0) < 1 then
                closedChallengerTransferPending[uid] = nil
                callback(false, "该挑战者区没有可转出的特权卡")
                return
            end

            local updatedRoot = cjson.decode(cjson.encode(cloudRoot))
            updatedRoot.currency.privilegeCardOwned = 0
            updatedRoot._meta = type(updatedRoot._meta) == "table" and updatedRoot._meta or {}
            updatedRoot._meta.lastSaveTime = os.time()
            updatedRoot._meta.closedChallengerTransferAt = os.time()

            local commit = serverCloud:BatchCommit("closed_challenger_card_transfer_" .. tostring(uid))
            commit:ScoreSet(uid, cloudKey, updatedRoot)
            commit:Commit({
                ok = function()
                    -- 只有源区特权卡确定扣除后才创建待转入标记，防止复制卡。
                    gp.pendingPrivilegeCardTransfer = 1
                    gp.pendingPrivilegeCardTransferFrom = sourceServerId
                    PDM.MarkDirty(uid, "global_profile")

                    local smGp = SaveManager.getTable(uid, "global_profile")
                    if smGp then
                        smGp.pendingPrivilegeCardTransfer = 1
                        smGp.pendingPrivilegeCardTransferFrom = sourceServerId
                    end

                    PDM.FlushImmediate(uid)
                    closedChallengerTransferPending[uid] = nil
                    print("[MarketService] closed challenger privilege card transferred uid="
                        .. tostring(uid) .. " fromServerId=" .. tostring(sourceServerId))
                    callback(true, nil)
                end,
                error = function(code, reason)
                    closedChallengerTransferPending[uid] = nil
                    print("[MarketService][ERROR] closed challenger privilege card transfer failed uid="
                        .. tostring(uid) .. " serverId=" .. tostring(sourceServerId)
                        .. " code=" .. tostring(code) .. " reason=" .. tostring(reason))
                    callback(false, "特权卡转出失败，请稍后重试")
                end,
            })
        end,
        error = function(code, reason)
            closedChallengerTransferPending[uid] = nil
            print("[MarketService][ERROR] closed challenger currency load failed uid="
                .. tostring(uid) .. " serverId=" .. tostring(sourceServerId)
                .. " code=" .. tostring(code) .. " reason=" .. tostring(reason))
            callback(false, "特权卡数据读取失败，请稍后重试")
        end,
    })
end

--- 进入区服时应用待转入的特权卡（仅在不同区服生效）
---@param uid number
---@return table result { applied: boolean, sameServer?: boolean, alreadyOwned?: boolean, cardResult?: table }
function MarketService.ApplyPendingPrivilegeCardTransfer(uid)
    local result = { applied = false }
    local gp = PDM.GetModule(uid, "global_profile")
    if not gp or (gp.pendingPrivilegeCardTransfer or 0) < 1 then
        return result
    end

    local serverId = tonumber(PDM.GetServerId(uid) or SaveManager.getServerId(uid)) or 0
    local fromServer = tonumber(gp.pendingPrivilegeCardTransferFrom) or 0
    local currency = PDM.GetModule(uid, "currency")
    if not currency then
        return result
    end

    local ServerListConfig = require("shared.ServerListConfig")

    -- 活动已结束的挑战者区不能通过重新进入来撤销转出；必须转入普通区服。
    if fromServer > 0 and serverId == fromServer
        and not ServerListConfig.isServerClosed(fromServer) then
        currency.privilegeCardOwned = 1
        PDM.MarkDirty(uid, "currency")
        gp.pendingPrivilegeCardTransfer = 0
        gp.pendingPrivilegeCardTransferFrom = 0
        PDM.MarkDirty(uid, "global_profile")
        local smGp = SaveManager.getTable(uid, "global_profile")
        if smGp then
            smGp.pendingPrivilegeCardTransfer = 0
            smGp.pendingPrivilegeCardTransferFrom = 0
        end
        local smCur = SaveManager.getTable(uid, "currency")
        if smCur then
            smCur.privilegeCardOwned = 1
        end
        result.sameServer = true
        result.restored = true
        print("[MarketService] privilege card transfer cancelled (re-entered source server) uid="
            .. tostring(uid) .. " serverId=" .. tostring(serverId))
        return result
    end

    if (currency.privilegeCardOwned or 0) >= 1 then
        gp.pendingPrivilegeCardTransfer = 0
        gp.pendingPrivilegeCardTransferFrom = 0
        PDM.MarkDirty(uid, "global_profile")
        result.alreadyOwned = true
        return result
    end

    currency.privilegeCardOwned = 1
    PDM.MarkDirty(uid, "currency")

    gp.pendingPrivilegeCardTransfer = 0
    gp.pendingPrivilegeCardTransferFrom = 0
    PDM.MarkDirty(uid, "global_profile")

    local smGp = SaveManager.getTable(uid, "global_profile")
    if smGp then
        smGp.pendingPrivilegeCardTransfer = 0
        smGp.pendingPrivilegeCardTransferFrom = 0
    end
    local smCur = SaveManager.getTable(uid, "currency")
    if smCur then
        smCur.privilegeCardOwned = 1
    end

    result.applied = true
    result.cardResult = MarketService.OnPrivilegeCardActivated(uid)

    print("[MarketService] privilege card transfer applied uid=" .. tostring(uid)
        .. " toServerId=" .. tostring(serverId)
        .. " fromServerId=" .. tostring(fromServer))

    return result
end

return MarketService
