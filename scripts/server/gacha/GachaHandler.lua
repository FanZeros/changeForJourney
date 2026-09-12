-- ============================================================================
-- GachaHandler - 抽卡/招募网络入口（薄路由层）
-- 职责: 接收请求 → 提取参数 → 调 GachaService → 返回结果
-- 层级: server/gacha  |  禁止业务逻辑
-- ============================================================================

local Protocol       = require("shared.Protocol")
local GachaService   = require("server.gacha.GachaService")
local TavernService  = require("server.gacha.TavernService")

local GachaHandler = {}

local handlers = {}

--- 招募英雄（旧接口，转发到 GACHA_PULL，保持兼容）
handlers[Protocol.ACTION_TYPES.DRAW_CARD] = function(uid, params)
    local ok, err, result = GachaService.GachaPull(uid, params and params.count or 1, "ticket")
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success      = true,
        gachaResults = result.gachaResults,
        totalCost    = result.totalCost,
        payType      = result.payType,
        pity         = result.pity,
    }
end

--- 扭蛋/抽卡
handlers[Protocol.ACTION_TYPES.GACHA_PULL] = function(uid, params)
    local ok, err, result = GachaService.GachaPull(
        uid,
        params and params.count,
        params and params.payType,
        params and params.poolId
    )
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success      = true,
        gachaResults = result.gachaResults,
        totalCost    = result.totalCost,
        payType      = result.payType,
        poolId       = result.poolId,
        pity         = result.pity,
    }
end

--- 指定招募：设置保底目标英雄
handlers[Protocol.ACTION_TYPES.TARGET_RECRUIT] = function(uid, params)
    if not params or not params.heroId then
        return { success = false, reason = "缺少英雄ID" }
    end
    local ok, err = GachaService.SetTargetRecruit(uid, tonumber(params.heroId))
    if not ok then
        return { success = false, reason = err }
    end
    return { success = true }
end

--- 星辉指定UP角色：设置UR命中时50%概率转为的目标角色
handlers[Protocol.ACTION_TYPES.STELLAR_TARGET_UP] = function(uid, params)
    if not params or not params.heroId then
        return { success = false, reason = "缺少角色ID" }
    end
    local ok, err = GachaService.SetStellarTargetUp(uid, tonumber(params.heroId))
    if not ok then
        return { success = false, reason = err }
    end
    return { success = true }
end

--- TAVERN_SHOP_BUY: 酒馆商店购买（同步）
handlers[Protocol.ACTION_TYPES.TAVERN_SHOP_BUY] = function(uid, params)
    if not params or not params.itemId then
        return { success = false, reason = "缺少商品ID" }
    end
    local itemId   = tonumber(params.itemId)
    local quantity = math.max(1, tonumber(params.quantity) or 1)
    return TavernService.ShopBuy(uid, itemId, quantity)
end

GachaHandler.actionHandlers = handlers

return GachaHandler
