-- ============================================================================
-- MarketHandler - 市场商店网络入口
-- 职责: 参数提取 → 调 MarketService → 返回结果
-- 层级: server/market  |  薄 Handler
-- ============================================================================

local Protocol          = require("shared.Protocol")
local MarketSchema      = require("shared.market.MarketSchema")
local MarketService     = require("server.market.MarketService")
local ServerDispatcher  = require("network.ServerDispatcher")
local TaskService       = require("server.task.TaskService")
local PDM               = require("server.character.PlayerDataManager")

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

--- 领取特权里程奖励
handlers[Protocol.ACTION_TYPES.CLAIM_PRIVILEGE_REWARD] = function(uid, params)
    local threshold = params and tonumber(params.threshold)
    local ok, reason, result = MarketService.ClaimPrivilegeReward(uid, threshold)
    if not ok then
        return { success = false, reason = reason }
    end
    -- 推送最新 privilege 状态（含更新后的 claimed 数组），客户端刷新领取按钮
    if result.privPayload then
        ServerDispatcher.pushModule(uid, "privilege", result.privPayload)
    end
    return {
        success    = true,
        action     = Protocol.ACTION_TYPES.CLAIM_PRIVILEGE_REWARD,
        threshold  = result.threshold,
        rewardType = result.rewardType,
        amount     = result.amount,
        rewardDetail = result.rewardDetail,
    }
end

--- 观看特权广告完成（客户端广告回调成功后发送）
handlers[Protocol.ACTION_TYPES.WATCH_PRIVILEGE_AD] = function(uid, params)
    local ok, reason, payload = MarketService.WatchPrivilegeAd(uid)
    if not ok then
        return { success = false, reason = reason }
    end
    -- 推进广告任务进度
    TaskService.UpdateProgress(uid, "watch_ad", 1)
    -- 把最新 privilege 状态推送到客户端（走 privilege 模块通道）
    if payload then
        ServerDispatcher.pushModule(uid, "privilege", payload)
    end
    return { success = true, action = Protocol.ACTION_TYPES.WATCH_PRIVILEGE_AD,
        rewardType = "privilege_point", rewardCount = MarketSchema.AD_PRIVILEGE_REWARD_PER_WATCH }
end

--- 选服界面处理已结束挑战者区特权卡转出。
--- 该请求发生在区服存档尚未加载时，由 Server.lua 特殊路由调用并接收异步结果。
---@param uid number
---@param params table|nil
---@param onComplete fun(result: table)
handlers[Protocol.ACTION_TYPES.TRANSFER_CLOSED_CHALLENGER_CARD] = function(uid, params, onComplete)
    local gp = PDM.GetModule(uid, "global_profile")
    local sourceServerId = gp and tonumber(gp.lastServerId) or nil
    if not sourceServerId then
        onComplete({ success = false, reason = "最近登录区服信息异常" })
        return
    end

    MarketService.TransferClosedChallengerCard(uid, sourceServerId, function(ok, reason)
        onComplete({
            success = ok,
            action = Protocol.ACTION_TYPES.TRANSFER_CLOSED_CHALLENGER_CARD,
            reason = reason,
            returnToLobby = ok,
        })
    end)
end

--- 特权卡转区（移除当前区服特权卡 → 待转入下一进入的区服 → 返回选服）
handlers[Protocol.ACTION_TYPES.TRANSFER_PRIVILEGE_CARD] = function(uid, params)
    local ok, reason = MarketService.TransferPrivilegeCard(uid)
    if not ok then
        return { success = false, reason = reason }
    end
    return {
        success       = true,
        action        = Protocol.ACTION_TYPES.TRANSFER_PRIVILEGE_CARD,
        returnToLobby = true,
    }
end

return handlers
