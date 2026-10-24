-- ============================================================================
-- TavernService - 酒馆商店业务逻辑层
-- 职责: 酒馆商店购买验证、扣费、发奖、记录
-- ============================================================================

local PDM          = require("rules.character.PlayerDataManager")
local TavernConfig = require("config.TavernConfig")
local HeroShardPolicy = require("shared.heroes.HeroShardPolicy")
local HeroShardService = require("rules.hero.HeroShardService")

local TavernService = {}

-- 购买计划只读校验；周期刷新在入口完成，交付前不扣费或发布通知。
local function planPurchase(uid, item, itemId, quantity, tavern, currency)
    -- 检查购买次数限制（limitCount < 0 = 不限购；购买记录始终累计）
    local purchased   = tavern.shopPurchased or {}
    local alreadyBought = purchased[itemId] or 0
    if item.limitCount >= 0 then
        local remaining   = item.limitCount - alreadyBought
        if remaining <= 0 then
            return nil, "已达购买上限"
        end
        if quantity > remaining then
            quantity = remaining
        end
    end

    -- 碎片商品先按真实需求钳到可买整份，再算价格；不花币购买溢出片。
    local shardPlan = nil ---@type table|nil
    local heroes = PDM.GetModule(uid, "heroes")
    if item.rewardType == "shard" then
        if not heroes or type(heroes.roster) ~= "table" then
            return nil, "数据未加载"
        end
        local entry = heroes.roster[item.rewardHeroId] or heroes.roster[tostring(item.rewardHeroId)]
        if not HeroShardPolicy.isOwned(entry) then
            return nil, "拥有该角色后可购买碎片"
        end
        local need, needErr = HeroShardPolicy.remaining(item.rewardHeroId, entry)
        if need == nil then return nil, needErr end
        local perItem = item.rewardCount or 1
        if not HeroShardPolicy.isSafeInteger(perItem) then
            return nil, "商品数量配置异常"
        end
        quantity = math.min(quantity, math.floor(need / perItem))
        if quantity < 1 then return nil, "该角色碎片已足够，无需购买" end
        local plan, planErr = HeroShardService.PlanFor(heroes, currency, item.rewardHeroId, perItem * quantity)
        if not plan then return nil, planErr end
        shardPlan = plan
    end

    local totalPrice = item.price * quantity
    if not HeroShardPolicy.isSafeInteger(totalPrice)
        or not HeroShardPolicy.isSafeInteger(currency.tavernCoin or 0, true) then
        return nil, "酒馆币数量异常"
    end
    if (currency.tavernCoin or 0) < totalPrice then
        return nil, "酒馆币不足"
    end
    local totalCount = (item.rewardCount or 1) * quantity
    if not HeroShardPolicy.isSafeInteger(totalCount) then
        return nil, "奖励数量异常"
    end
    return { quantity = quantity, totalPrice = totalPrice, alreadyBought = alreadyBought,
        totalCount = totalCount, heroes = heroes, shardPlan = shardPlan }
end

-- 沿用规划时的模块原表；ApplyTo 失败不得先扣币，所有通知由入口在台账更新后发布。
local function deliverPurchase(item, plan, currency)
    if plan.shardPlan then
        local applied, applyErr = HeroShardService.ApplyTo(plan.heroes, currency, plan.shardPlan)
        if not applied then return false, applyErr end
    else
        local balance = currency[item.rewardType] or 0
        if not HeroShardPolicy.isSafeInteger(balance, true)
            or plan.totalCount > HeroShardPolicy.MAX_SAFE_INTEGER - balance then
            return false, "奖励库存超出安全范围"
        end
        currency[item.rewardType] = balance + plan.totalCount
    end
    return true
end

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
    quantity = quantity == nil and 1 or tonumber(quantity)
    if not HeroShardPolicy.isSafeInteger(quantity) then
        return { success = false, reason = "购买数量必须为有限正整数" }
    end

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

    local plan, reason = planPurchase(uid, item, itemId, quantity, tavern, currency)
    if not plan then return { success = false, reason = reason } end
    quantity = plan.quantity
    local totalPrice, alreadyBought = plan.totalPrice, plan.alreadyBought
    local totalCount, shardPlan = plan.totalCount, plan.shardPlan

    local delivered, deliverErr = deliverPurchase(item, plan, currency)
    if not delivered then return { success = false, reason = deliverErr } end
    currency.tavernCoin = currency.tavernCoin - totalPrice

    -- 更新购买记录
    if not tavern.shopPurchased then tavern.shopPurchased = {} end
    tavern.shopPurchased[itemId] = alreadyBought + quantity
    if shardPlan then PDM.MarkDirty(uid, "heroes") end
    PDM.MarkDirty(uid, "currency")
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
        shardGain = shardPlan and shardPlan.shardGain or nil,
        amount = totalCount,
        overflowShards = 0,
        rewards = { { type = item.rewardType, heroId = item.rewardHeroId, amount = totalCount } },
    }
end

return TavernService
