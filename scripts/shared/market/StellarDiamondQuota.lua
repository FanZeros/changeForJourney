-- ============================================================================
-- StellarDiamondQuota — 市场星辉招募券（商品 id=18）每日限购计数
-- ============================================================================

local M = {}

M.ITEM_ID = 18
M.DAILY_LIMIT = 30  -- 与市场商品 id=18 limitCount 保持一致

function M.getDayId()
    return math.floor((os.time() + 28800) / 86400)
end

---@param purchased table|nil  market.purchased
---@param dailyLimit number
---@return number remaining
function M.getRemaining(purchased, dailyLimit)
    dailyLimit = dailyLimit or M.DAILY_LIMIT
    if dailyLimit <= 0 then return 999999 end
    if not purchased then return dailyLimit end
    local rec = purchased[M.ITEM_ID] or purchased[tostring(M.ITEM_ID)]
    if not rec then return dailyLimit end
    if (rec.dayId or 0) ~= M.getDayId() then
        return dailyLimit
    end
    return math.max(0, dailyLimit - (rec.count or 0))
end

return M
