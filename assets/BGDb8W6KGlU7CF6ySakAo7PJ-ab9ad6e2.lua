-- ============================================================================
-- MailHandler - 邮件系统网络入口
-- 职责: 参数提取 → 调 MailService → 返回结果
-- 层级: server/mail  |  薄 Handler
-- ============================================================================

local Protocol    = require("shared.Protocol")
local MailService = require("server.mail.MailService")

local handlers = {}

--- 领取单封邮件
handlers[Protocol.ACTION_TYPES.CLAIM_MAIL] = function(uid, params)
    local mailId = params and params.mailId
    local ok, reason, result = MailService.ClaimMail(uid, mailId)
    if not ok then
        return { success = false, reason = reason, mailAction = true }
    end
    return {
        success    = true,
        mailAction = true,
        action     = Protocol.ACTION_TYPES.CLAIM_MAIL,
        mailId     = result.mailId,
        rewards    = result.rewards,
    }
end

--- 一键领取所有未领取邮件
handlers[Protocol.ACTION_TYPES.CLAIM_ALL_MAIL] = function(uid, params)
    local ok, reason, result = MailService.ClaimAll(uid)
    if not ok then
        return { success = false, reason = reason, mailAction = true }
    end
    return {
        success    = true,
        mailAction = true,
        action     = Protocol.ACTION_TYPES.CLAIM_ALL_MAIL,
        claimedIds = result.claimedIds,
        rewards    = result.rewards,
    }
end

--- 删除已读（已领取）邮件
handlers[Protocol.ACTION_TYPES.DELETE_READ] = function(uid, params)
    local ok, reason, result = MailService.DeleteRead(uid)
    if not ok then
        return { success = false, reason = reason, mailAction = true }
    end
    return {
        success    = true,
        mailAction = true,
        action     = Protocol.ACTION_TYPES.DELETE_READ,
        deletedIds = result.deletedIds,
    }
end

-- ============================================================================
-- 模块导出
-- ============================================================================

local MailHandler = {}

--- 网络事件路由表（供 registerHandlers 使用）
MailHandler.actionHandlers = handlers

--- 构建客户端邮件列表（供 Server.lua 登录推送使用）
function MailHandler.buildMailList(uid)
    return MailService.BuildMailList(uid)
end

return MailHandler
