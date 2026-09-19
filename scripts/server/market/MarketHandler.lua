-- ============================================================================
-- MarketHandler - 市场商店网络入口
-- 职责: 参数提取 → 调 MarketService → 返回结果
-- 层级: server/market  |  薄 Handler
-- 说明: 特权里程/特权广告/特权卡转区入口已随单机化移除。
-- ============================================================================

local Protocol      = require("shared.Protocol")
local MarketService = require("server.market.MarketService")

local handlers = {}

--- 购买商品（支持批量 quantity）
handlers[Protocol.ACTION_TYPES.MARKET_BUY] = function(uid, params)
    local itemId = params and tonumber(params.itemId)
    local quantity = math.max(1, math.min(99, tonumber(params and params.quantity) or 1))
    local ok, reason, result = MarketService.Buy(uid, itemId, quantity)
    if not ok then
        return { success = false, reason = reason }
    end
    return {
        success      = true,
        action       = Protocol.ACTION_TYPES.MARKET_BUY,
        itemId       = result.itemId,
        purchased    = result.purchased,
        firstBuyTime = result.firstBuyTime,
        rewardType   = result.rewardType,
        rewardName   = result.rewardName,
        rewardCount  = result.rewardCount,
        rewardDetail = result.rewardDetail,
    }
end

return handlers
