-- ============================================================================
-- TavernService - 酒馆商店业务逻辑层
-- 职责: 酒馆商店购买验证、扣费、发奖、记录
-- ============================================================================

local PDM          = require("server.character.PlayerDataManager")
local TavernConfig = require("config.TavernConfig")

local TavernService = {}

-- ======================== 公开接口 ========================

--- 登录/重连时重置过期的酒馆商店限购（pushFullState 前调用）
---@param uid number
function TavernService.ResetShopLimits(uid)
    local tavern = PDM.GetModule(uid, "tavern")
    if not tavern then return end
    if TavernConfig.applyShopPeriodReset(tavern, os.time()) then
        PDM.MarkDirty(uid, "tavern")
        print("[TavernService] shop limits reset uid=" .. tostring(uid))
    end
end

--- 酒馆商店购买（同步）
---@param uid number
---@param itemId number
---@param quantity number
---@return table result { success, itemId, quantity, purchased, tavernCoin, reason? }
function TavernService.ShopBuy(uid, itemId, quantity)
    quantity = math.max(1, quantity or 1)

    local item = TavernConfig.getShopItem(itemId)
    if not item then
        return { success = false, reason = "商品不存在" }
    end

    local tavern = PDM.GetModule(uid, "tavern")
    if not tavern then
        return { success = false, reason = "数据未加载" }
    end

    local currency = PDM.GetModule(uid, "currency")
    if not currency then
        return { success = false, reason = "数据未加载" }
    end

    -- 周期重置（先重置，再检查购买记录）
    if TavernConfig.applyShopPeriodReset(tavern, os.time()) then
        PDM.MarkDirty(uid, "tavern")
    end

    -- 检查购买次数限制（limitCount < 0 = 不限购；购买记录始终累计）
    local purchased   = tavern.shopPurchased or {}
    local alreadyBought = purchased[itemId] or 0
    if item.limitCount >= 0 then
        local remaining   = item.limitCount - alreadyBought
        if remaining <= 0 then
            return { success = false, reason = "已达购买上限" }
        end
        if quantity > remaining then
            quantity = remaining
        end
    end

    -- 检查酒馆币余额
    local totalPrice = item.price * quantity
    if (currency.tavernCoin or 0) < totalPrice then
        return { success = false, reason = "酒馆币不足" }
    end

    -- 碎片商品必须已拥有对应角色后才能购买
    if item.rewardType == "shard" then
        local heroes = PDM.GetModule(uid, "heroes")
        if not heroes or not heroes.roster then
            return { success = false, reason = "数据未加载" }
        end
        local heroId = item.rewardHeroId
        local heroData = heroes.roster[heroId] or heroes.roster[tostring(heroId)]
        if not heroData or not heroData.level then
            return { success = false, reason = "拥有该角色后可购买碎片" }
        end
    end

    -- 扣除酒馆币
    currency.tavernCoin = (currency.tavernCoin or 0) - totalPrice

    -- 发放奖励
    if item.rewardType == "shard" then
        -- 碎片：加到 heroes.roster[heroId].shards
        local heroes = PDM.GetModule(uid, "heroes")
        if heroes then
            local heroId = item.rewardHeroId
            if not heroes.roster then heroes.roster = {} end
            if not heroes.roster[heroId] then
                heroes.roster[heroId] = { shards = 0, _shardMigrated = true }
            end
            local totalCount = (item.rewardCount or 1) * quantity
            heroes.roster[heroId].shards = (heroes.roster[heroId].shards or 0) + totalCount
            PDM.MarkDirty(uid, "heroes")
            print("[TavernShop] shard → heroId=" .. heroId .. " x" .. totalCount)
        end
    else
        -- 其他奖励（recruiTicket 等）：直接加到 currency 字段
        local field      = item.rewardType
        local totalCount = (item.rewardCount or 1) * quantity
        currency[field]  = (currency[field] or 0) + totalCount
        print("[TavernShop] " .. field .. " x" .. totalCount)
    end
    PDM.MarkDirty(uid, "currency")

    -- 更新购买记录
    if not tavern.shopPurchased then tavern.shopPurchased = {} end
    tavern.shopPurchased[itemId] = alreadyBought + quantity
    PDM.MarkDirty(uid, "tavern")

    print("[TavernShop] buy uid=" .. tostring(uid)
        .. " itemId=" .. tostring(itemId)
        .. " qty=" .. quantity
        .. " price=" .. totalPrice
        .. " tavernCoin=" .. tostring(currency.tavernCoin))

    return {
        success      = true,
        itemId       = itemId,
        quantity     = quantity,
        purchased    = tavern.shopPurchased[itemId],
        tavernCoin   = currency.tavernCoin,
        shopPurchased = tavern.shopPurchased,
    }
end

return TavernService
