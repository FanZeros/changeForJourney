---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- BroadcastMailService - 全服邮件管理（单机本地公告版）
-- 职责: 公告的发送、存储（内存）、过期清理、登录合并
-- 层级: server/mail  |  单机化：不再依赖 serverCloud，公告仅本次运行内存中生效
-- ============================================================================

local PDM = require("rules.character.PlayerDataManager")
local ResourceDefs = require("config.ResourceDefs")
local ServerListConfig = require("shared.ServerListConfig")

local BroadcastMailService = {}

-- ======================== 常量 ========================

--- 最大保留公告数
local MAX_BROADCAST_MAILS = 100

--- 默认过期天数
local DEFAULT_EXPIRE_DAYS = 30

-- ======================== 内部状态 ========================

--- 内存中的公告缓存
---@type table[]
local broadcastMails_ = {}

--- 是否已完成初始化加载
local initialized_ = false

--- 是否已初始化
---@return boolean
function BroadcastMailService.IsInitialized()
    return initialized_
end

-- ======================== 内部工具 ========================

--- 生成唯一邮件 ID
---@return string
local function generateMailId()
    return "bm_" .. os.time() .. "_" .. math.random(1000, 9999)
end

--- 检查邮件是否已过期
---@param mail table
---@return boolean
local function isExpired(mail)
    return mail.expireTime > 0 and os.time() > mail.expireTime
end

---@param value any
---@return boolean
local function hasCompensationMarker(value)
    if type(value) ~= "string" then return false end
    if string.find(value, "补偿", 1, true) then return true end
    return string.find(string.lower(value), "compensat", 1, true) ~= nil
end

---@param mail table|nil
---@return boolean
local function isCompensationMail(mail)
    if type(mail) ~= "table" then return false end
    if mail.excludeChallenger then return true end
    return hasCompensationMarker(mail.id)
        or hasCompensationMarker(mail.title)
        or hasCompensationMarker(mail.body)
        or hasCompensationMarker(mail.content)
        or hasCompensationMarker(mail.source)
end

---@param uid number
---@param mail table|nil
---@return boolean
local function shouldExcludeMailForCurrentServer(uid, mail)
    return ServerListConfig.isChallengerServer(PDM.GetServerId(uid)) and isCompensationMail(mail)
end

--- 清理过期公告（修改内存表，返回清理数量）
---@return number cleanedCount
local function cleanExpired()
    local cleaned = 0
    local i = 1
    while i <= #broadcastMails_ do
        if isExpired(broadcastMails_[i]) then
            table.remove(broadcastMails_, i)
            cleaned = cleaned + 1
        else
            i = i + 1
        end
    end
    return cleaned
end

-- ======================== 初始化 ========================

--- 初始化（单机本地公告：不读云端，公告仅本次运行内存中生效）
---@param callback function|nil  可选回调 callback(ok)
function BroadcastMailService.Init(callback)
    if initialized_ then
        if callback then callback(true) end
        return
    end
    broadcastMails_ = {}
    initialized_ = true
    print("[BroadcastMailService] Init local (no serverCloud)")
    if callback then callback(true) end
end

-- ======================== 核心 API ========================

--- 发送一封全服邮件（支持区服范围限制）
---@param title string
---@param content string
---@param rewards table[]|nil  奖励列表 [{key, amount}, ...]
---@param expireDays number|nil  过期天数（默认 30）
---@param serverIds number[]|nil  目标区服ID列表，nil 表示全服
---@param suppressNotify boolean|nil  true=仅写入云端，不立即通知在线玩家（用于服务启动批量补偿）
---@return boolean ok
---@return string|nil reason
---@return table|nil result { mailId }
function BroadcastMailService.SendBroadcastMail(title, content, rewards, expireDays, serverIds, suppressNotify)
    if not initialized_ then
        return false, "全服邮件系统未初始化（等待云端加载完成）"
    end

    if not title or title == "" then
        return false, "缺少邮件标题"
    end
    if not content then
        return false, "缺少邮件内容"
    end

    -- 检查数量上限
    if #broadcastMails_ >= MAX_BROADCAST_MAILS then
        -- 尝试清理过期邮件腾出空间
        local cleaned = cleanExpired()
        if cleaned > 0 then
            print("[BroadcastMailService] auto-cleaned " .. cleaned .. " expired before send")
        end
        if #broadcastMails_ >= MAX_BROADCAST_MAILS then
            return false, "全服邮件已达上限(" .. MAX_BROADCAST_MAILS .. "封)，请先清理过期邮件"
        end
    end

    local days = tonumber(expireDays) or DEFAULT_EXPIRE_DAYS
    local now = os.time()

    local rawRewards = rewards or {}
    local mailRewards = ResourceDefs.normalizeMailRewardList(rawRewards)
    if ResourceDefs.hasDroppedMailRewards(rawRewards, mailRewards) then
        return false, "奖励格式无效（碎片请用 101*数量、shard_16*数量 或 h16*数量）"
    end

    local mail = {
        id         = generateMailId(),
        title      = title,
        content    = content,
        rewards    = mailRewards,
        createTime = now,
        expireTime = now + days * 86400,
        date       = os.date("%Y/%m/%d", now),
        serverIds  = serverIds,  -- nil=全服; {1,2,3}=仅指定区服
    }

    -- 追加到内存表
    broadcastMails_[#broadcastMails_ + 1] = mail

    print("[BroadcastMailService] SendBroadcastMail id=" .. mail.id
        .. " title=" .. title .. " expireDays=" .. days
        .. " total=" .. #broadcastMails_)

    -- 通知在线玩家有新邮件（通过推送邮件列表更新）
    if not suppressNotify then
        BroadcastMailService.NotifyOnlinePlayers()
    end

    return true, nil, { mailId = mail.id }
end

--- 获取当前有效的全服邮件列表（供 BuildMailList 合并使用）
--- 自动跳过已过期邮件
---@return table[] 未过期的全服邮件列表
function BroadcastMailService.GetActiveMails()
    if not initialized_ then
        return {}
    end

    local result = {}
    for _, mail in ipairs(broadcastMails_) do
        if not isExpired(mail) then
            result[#result + 1] = mail
        end
    end
    return result
end

--- 获取所有全服邮件（包括过期的，用于 GM 管理查询）
---@return table[]
function BroadcastMailService.GetAllMails()
    if not initialized_ then
        return {}
    end
    return broadcastMails_
end

--- 删除指定全服邮件
---@param mailId string
---@return boolean ok
---@return string|nil reason
function BroadcastMailService.RemoveMail(mailId)
    if not initialized_ then
        return false, "系统未初始化"
    end
    if not mailId then
        return false, "缺少 mailId"
    end

    for i, mail in ipairs(broadcastMails_) do
        if mail.id == mailId then
            table.remove(broadcastMails_, i)
            print("[BroadcastMailService] RemoveMail id=" .. mailId)
            return true
        end
    end

    return false, "未找到邮件: " .. mailId
end

--- 手动触发过期清理
---@return number cleanedCount
function BroadcastMailService.CleanExpired()
    if not initialized_ then
        return 0
    end

    local cleaned = cleanExpired()
    if cleaned > 0 then
        print("[BroadcastMailService] CleanExpired: removed " .. cleaned .. " mails")
    end
    return cleaned
end

--- 是否已初始化完成
---@return boolean
function BroadcastMailService.IsReady()
    return initialized_
end

-- ======================== 登录合并 ========================

--- 为指定玩家构建全服邮件列表（过滤已领取/已过期/不在目标区服）
--- 在 MailService.BuildMailList 中调用
---@param uid number
---@return table[] 该玩家可见的全服邮件（客户端格式）
function BroadcastMailService.GetMailsForPlayer(uid)
    if not initialized_ then
        return {}
    end

    local mailData = PDM.GetModule(uid, "mail")
    if not mailData then
        return {}
    end

    -- 确保 claimedBroadcasts 表存在
    if not mailData.claimedBroadcasts then
        mailData.claimedBroadcasts = {}
    end

    -- 获取玩家所在区服用于过滤
    local playerServerId = PDM.GetServerId(uid)

    local result = {}
    for _, mail in ipairs(broadcastMails_) do
        -- 跳过已过期
        if not isExpired(mail) and not shouldExcludeMailForCurrentServer(uid, mail) then
            -- 区服范围过滤：mail.serverIds 为 nil 表示全服，否则玩家必须在目标区服列表中
            local serverMatch = true
            if mail.serverIds and playerServerId then
                serverMatch = false
                for _, sid in ipairs(mail.serverIds) do
                    if sid == playerServerId then
                        serverMatch = true
                        break
                    end
                end
            end

            if serverMatch then
                local bmId = mail.id
                local claimed = mailData.claimedBroadcasts[bmId]
                -- 未领取的全服邮件显示给玩家
                if not claimed then
                    result[#result + 1] = {
                        id      = bmId,
                        title   = mail.title,
                        body    = mail.content,
                        rewards = mail.rewards,
                        read    = false,
                        date    = mail.date or os.date("%Y/%m/%d", mail.createTime),
                        source  = "broadcast",
                    }
                end
            end
        end
    end

    return result
end

--- 领取一封全服邮件的奖励
---@param uid number
---@param mailId string  全服邮件 ID（"bm_" 前缀）
---@return boolean ok
---@return string|nil reason
---@return table|nil result { mailId, rewards }
function BroadcastMailService.ClaimBroadcastMail(uid, mailId)
    if not initialized_ then
        return false, "系统未初始化"
    end

    local mailData = PDM.GetModule(uid, "mail")
    if not mailData then
        return false, "数据异常"
    end
    if not mailData.claimedBroadcasts then
        mailData.claimedBroadcasts = {}
    end

    -- 检查是否已领取
    if mailData.claimedBroadcasts[mailId] then
        return false, "已领取"
    end

    -- 查找全服邮件
    local targetMail = nil
    for _, mail in ipairs(broadcastMails_) do
        if mail.id == mailId then
            targetMail = mail
            break
        end
    end

    if not targetMail then
        return false, "邮件不存在或已过期"
    end
    if isExpired(targetMail) then
        return false, "邮件已过期"
    end
    if shouldExcludeMailForCurrentServer(uid, targetMail) then
        return false, "挑战者服不发放补偿邮件"
    end

    local playerServerId = PDM.GetServerId(uid)
    if targetMail.serverIds and playerServerId then
        local serverMatch = false
        for _, sid in ipairs(targetMail.serverIds) do
            if sid == playerServerId then
                serverMatch = true
                break
            end
        end
        if not serverMatch then
            return false, "邮件不属于当前区服"
        end
    end

    -- 发放奖励
    local CurrencyService = require("rules.currency.CurrencyService")
    local failedRewards = {}
    for _, reward in ipairs(targetMail.rewards or {}) do
        if not CurrencyService.GrantReward(uid, reward) then
            failedRewards[#failedRewards + 1] = reward.type or reward.key
            print("[BroadcastMailService] WARN grant failed uid=" .. tostring(uid)
                .. " bmId=" .. mailId .. " type=" .. tostring(reward.type or reward.key))
        end
    end

    -- 标记已领取
    mailData.claimedBroadcasts[mailId] = true
    PDM.MarkDirty(uid, "mail")

    print("[BroadcastMailService] ClaimBroadcastMail uid=" .. tostring(uid)
        .. " bmId=" .. mailId
        .. (#failedRewards > 0 and (" failedRewards=" .. table.concat(failedRewards, ",")) or ""))
    return true, nil, { mailId = mailId, rewards = targetMail.rewards }
end

-- ======================== 在线通知 ========================

--- 通知在线玩家刷新邮件列表（仅推送给目标区服内的玩家）
---@param serverIds number[]|nil  目标区服ID列表，nil 表示全部在线玩家
function BroadcastMailService.NotifyOnlinePlayers(serverIds)
    local uid = 1
    if not PDM.IsLoaded(uid) then
        print("[BroadcastMailService] NotifyOnlinePlayers: local save not loaded")
        return
    end
    if serverIds then
        local playerSid = PDM.GetServerId(uid)
        local shouldPush = false
        for _, sid in ipairs(serverIds) do
            if sid == playerSid then
                shouldPush = true
                break
            end
        end
        if not shouldPush then
            return
        end
    end

    local ServerDispatcher = require("app.LocalDispatcher")
    local MailService = require("rules.mail.MailService")
    local Protocol = require("shared.Protocol")
    local mailList = MailService.BuildMailList(uid)
    if mailList then
        ServerDispatcher.sendEvent(uid, Protocol.RES_ACTION_RESULT, {
            success  = true,
            mailPush = true,
            mails    = mailList,
        })
    end
    print("[BroadcastMailService] NotifyOnlinePlayers: pushed to local player")
end

return BroadcastMailService
