-- ============================================================================
-- MailService - 邮件系统业务逻辑
-- 职责: 邮件领取、一键领取、删除已读、构建邮件列表（纯逻辑，禁止网络 IO）
-- 层级: server/mail  |  通过 PDM 读写数据
-- ============================================================================

local PDM              = require("server.character.PlayerDataManager")
local SaveManager      = require("server.SaveManager")
local MailConfig       = require("shared.mail.MailConfig")
local CurrencyService  = require("server.currency.CurrencyService")
local StageConfig      = require("config.StageConfig")
local TowerConfig      = require("config.TowerConfig")
local ServerListConfig = require("shared.ServerListConfig")

local MailService = {}

--- 动态邮件收件箱容量上限（铁律 #3: 集合类数据必须有增长预警）
--- 单封邮件含 rewards[] 约 200-500 字节
--- 100 封 × 300 字节(均值) ≈ 30KB，极端 100 × 500 = 50KB，不超 MSG_SAFE_SIZE(50KB)
local MAX_INBOX = 100

--- claimedBroadcasts 清理阈值（超过此数量时触发清理）
local CLAIMED_BROADCASTS_PRUNE_THRESHOLD = 200

--- 动态邮件 ID 前缀
local DM_PREFIX = "dm_"
--- 全服邮件 ID 前缀
local BM_PREFIX = "bm_"

--- 判断是否为全服邮件 ID
---@param mailId string
---@return boolean
local function isBroadcastMail(mailId)
    return type(mailId) == "string" and mailId:sub(1, #BM_PREFIX) == BM_PREFIX
end

-- ======================== 内部工具 ========================

--- 查找邮件配置
---@param mailId string
---@return table|nil
local function findMailDef(mailId)
    for _, mail in ipairs(MailConfig.MAILS) do
        if mail.id == mailId then return mail end
    end
    return nil
end

--- 判断是否为动态邮件 ID
---@param mailId string
---@return boolean
local function isDynamicMail(mailId)
    return type(mailId) == "string" and mailId:sub(1, #DM_PREFIX) == DM_PREFIX
end

---@param value any
---@return boolean
local function hasCompensationMarker(value)
    if type(value) ~= "string" then return false end
    if string.find(value, "补偿", 1, true) then return true end
    return string.find(string.lower(value), "compensat", 1, true) ~= nil
end

---@param uid number
---@return number
local function getCurrentServerId(uid)
    return tonumber(SaveManager.getServerId(uid) or PDM.GetServerId(uid) or 0) or 0
end

---@param uid number
---@return boolean
local function isCurrentServerChallenger(uid)
    return ServerListConfig.isChallengerServer(getCurrentServerId(uid))
end

---@param mail table|nil
---@return boolean
local function isCompensationMailExcludedFromChallenger(mail)
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
    return isCurrentServerChallenger(uid) and isCompensationMailExcludedFromChallenger(mail)
end

---@param uid number
---@param mail table|nil
---@return boolean
function MailService.ShouldExcludeMailForCurrentServer(uid, mail)
    return shouldExcludeMailForCurrentServer(uid, mail)
end

-- ======================== 内部容量保护 ========================

--- 判断是否为不可自动淘汰的挑战者奖励邮件
---@param mail table|nil
---@return boolean
local function isProtectedChallengerRewardMail(mail)
    return type(mail) == "table"
        and type(mail.source) == "string"
        and mail.source:sub(1, 11) == "challenger:"
end

--- 获取 inbox 中按日期最旧且允许淘汰的邮件 ID
---@param inbox table
---@return string|nil oldestId
local function findOldestEvictableInboxId(inbox)
    local oldestId = nil
    local oldestDate = nil
    for dmId, dm in pairs(inbox) do
        if not isProtectedChallengerRewardMail(dm) then
            local d = dm.date or "0000/00/00"
            if not oldestDate or d < oldestDate then
                oldestDate = d
                oldestId = dmId
            end
        end
    end
    return oldestId
end

--- 获取 inbox 当前数量
---@param inbox table
---@return number
local function getInboxCount(inbox)
    local count = 0
    for _ in pairs(inbox) do
        count = count + 1
    end
    return count
end

--- inbox 容量保护：超限时淘汰最旧邮件直到腾出空间
--- 被淘汰的邮件奖励视为放弃（玩家长期不领取的代价）
---@param mailData table
---@return number evictedCount
local function evictOldestIfOverLimit(mailData)
    if not mailData.inbox then return 0 end
    local count = getInboxCount(mailData.inbox)
    local evicted = 0
    while count >= MAX_INBOX do
        local oldestId = findOldestEvictableInboxId(mailData.inbox)
        if not oldestId then
            print("[MailService][WARN] inbox full with protected challenger rewards; keeping all mails")
            break
        end
        print("[MailService] EVICT inbox full (" .. count .. ">=" .. MAX_INBOX
            .. ") removing oldest dmId=" .. oldestId)
        mailData.inbox[oldestId] = nil
        count = count - 1
        evicted = evicted + 1
    end
    return evicted
end

--- 清理 claimedBroadcasts 中已过期的广播邮件 ID
--- 只保留仍在 BroadcastMailService 活跃列表中的 ID
---@param mailData table
---@return number prunedCount
local function pruneExpiredBroadcastClaims(mailData)
    if not mailData.claimedBroadcasts then return 0 end

    -- 计算当前 claimedBroadcasts 大小
    local totalCount = 0
    for _ in pairs(mailData.claimedBroadcasts) do
        totalCount = totalCount + 1
    end

    -- 未超阈值，不需要清理
    if totalCount < CLAIMED_BROADCASTS_PRUNE_THRESHOLD then
        return 0
    end

    -- 获取当前活跃的广播邮件 ID 集合
    local okBm, BroadcastMailService = pcall(require, "server.mail.BroadcastMailService")
    if not okBm or not BroadcastMailService or not BroadcastMailService.IsReady() then
        return 0
    end

    local activeMails = BroadcastMailService.GetActiveMails()
    local activeIds = {}
    for _, mail in ipairs(activeMails) do
        activeIds[mail.id] = true
    end

    -- 清理不在活跃列表中的 claimed ID（已过期的广播邮件）
    local pruned = 0
    local toRemove = {}
    for bmId in pairs(mailData.claimedBroadcasts) do
        if not activeIds[bmId] then
            toRemove[#toRemove + 1] = bmId
        end
    end
    for _, bmId in ipairs(toRemove) do
        mailData.claimedBroadcasts[bmId] = nil
        pruned = pruned + 1
    end

    if pruned > 0 then
        print("[MailService] pruneExpiredBroadcastClaims: removed " .. pruned
            .. " stale IDs (was " .. totalCount .. ", now " .. (totalCount - pruned) .. ")")
    end
    return pruned
end

-- ======================== 发送动态邮件 ========================

--- 向玩家发送一封动态邮件（服务端内部调用）
--- 每封邮件使用 nextId 自增分配唯一 ID，不会覆盖已有邮件
---@param uid number
---@param mail table { title: string, body: string, rewards: table[], source?: string }
---@return string|nil dmId 分配的动态邮件 ID，失败返回 nil
function MailService.SendDynamicMail(uid, mail)
    if not mail or not mail.title then
        print("[MailService] SendDynamicMail: invalid mail param uid=" .. tostring(uid))
        return nil
    end

    if shouldExcludeMailForCurrentServer(uid, mail) then
        print("[MailService] SendDynamicMail blocked compensation mail on challenger uid=" .. tostring(uid)
            .. " serverId=" .. tostring(getCurrentServerId(uid))
            .. " title=" .. tostring(mail.title)
            .. " source=" .. tostring(mail.source))
        return nil
    end

    local mailData = PDM.GetModule(uid, "mail")
    if not mailData then
        print("[MailService] SendDynamicMail: no mailData uid=" .. tostring(uid))
        return nil
    end

    if not mailData.inbox  then mailData.inbox  = {} end
    if not mailData.nextId then mailData.nextId  = 1  end

    -- 容量保护：inbox 满时淘汰最旧邮件（铁律 #3）
    local evicted = evictOldestIfOverLimit(mailData)
    if evicted > 0 then
        print("[MailService] SendDynamicMail: evicted " .. evicted .. " old mails to make room, uid=" .. tostring(uid))
    end

    local dmId = DM_PREFIX .. tostring(mailData.nextId)
    mailData.nextId = mailData.nextId + 1

    mailData.inbox[dmId] = {
        id      = dmId,
        title   = mail.title,
        body    = mail.body or "",
        rewards = mail.rewards or {},
        date    = os.date("%Y/%m/%d"),
        source  = mail.source,   -- 来源标识（如 "arena_weekly"），可选
    }

    PDM.MarkDirty(uid, "mail")

    print("[MailService] SendDynamicMail uid=" .. tostring(uid)
        .. " dmId=" .. dmId .. " title=" .. mail.title
        .. " rewards=" .. #(mail.rewards or {}))
    return dmId
end

-- ======================== 通天塔结算事故一次性补偿 ========================

local TOWER_BUG_COMP_FLAG = "towerBugCompV1"
local TOWER_BUG_COMP_CUTOFF_TS = 1782489600  -- 2026-06-27 00:00:00 UTC+8

---@param bt table|nil
---@return boolean
local function hasTowerProgress(bt)
    if type(bt) ~= "table" then return false end
    if (tonumber(bt.floor) or 0) > 1 then return true end
    if (tonumber(bt.dailyUsed) or 0) > 0 then return true end
    if type(bt.cleared) == "table" then
        for _, v in pairs(bt.cleared) do
            if v then return true end
        end
    end
    return false
end

---@param uid number
---@return boolean checked
---@return table|nil result
function MailService.CheckAndSendTowerBugCompensation(uid)
    local mailData = PDM.GetModule(uid, "mail")
    local dungeonData = PDM.GetModule(uid, "dungeon")
    local sessionData = PDM.GetModule(uid, "session")
    if not mailData or not dungeonData then
        print("[MailService] towerBugComp skip: missing data uid=" .. tostring(uid)
            .. " mail=" .. tostring(mailData ~= nil) .. " dungeon=" .. tostring(dungeonData ~= nil))
        return false, nil
    end

    if not mailData.compensationFlags then mailData.compensationFlags = {} end
    if mailData.compensationFlags[TOWER_BUG_COMP_FLAG] then
        return true, { alreadyChecked = true }
    end

    local sid = getCurrentServerId(uid)
    if ServerListConfig.isChallengerServer(sid) then
        mailData.compensationFlags[TOWER_BUG_COMP_FLAG] = true
        PDM.MarkDirty(uid, "mail")
        print("[MailService] towerBugComp blocked challenger uid=" .. tostring(uid)
            .. " serverId=" .. tostring(sid))
        return true, { ineligible = true, reason = "challenger_server", serverId = sid }
    end

    local bt = dungeonData.babel_tower
    local firstLoginTime = sessionData and tonumber(sessionData.firstLoginTime or 0) or 0
    local eligible = (firstLoginTime > 0 and firstLoginTime < TOWER_BUG_COMP_CUTOFF_TS) or hasTowerProgress(bt)
    if not eligible then
        mailData.compensationFlags[TOWER_BUG_COMP_FLAG] = true
        PDM.MarkDirty(uid, "mail")
        print("[MailService] towerBugComp skipped future player uid=" .. tostring(uid)
            .. " firstLoginTime=" .. tostring(firstLoginTime))
        return true, { ineligible = true, firstLoginTime = firstLoginTime }
    end

    local currentFloor = bt and math.floor(tonumber(bt.floor) or 0) or 0
    local rewardFloor = math.max(1, math.min(currentFloor, TowerConfig.MAX_FLOOR))
    local floorCfg = currentFloor > 0 and TowerConfig.getFloor(rewardFloor) or nil
    local compensation = floorCfg and math.max(0, math.floor((floorCfg.sweepDiamond or 0) * 3)) or 0

    if compensation > 0 then
        local dmId = MailService.SendDynamicMail(uid, {
            title = "通天塔结算补偿",
            body = "亲爱的冒险者：通天塔结算奖励显示与发放异常已修复。现按你当前通天塔层数对应扫荡钻石的3倍发放本次事故补偿，请在邮件中领取。该补偿仅本次事故发放一次。",
            rewards = {
                { type = "diamond", amount = compensation },
            },
            source = TOWER_BUG_COMP_FLAG,
        })
        if not dmId then
            print("[MailService] towerBugComp send failed uid=" .. tostring(uid)
                .. " currentFloor=" .. tostring(currentFloor)
                .. " rewardFloor=" .. tostring(rewardFloor)
                .. " compensation=" .. tostring(compensation))
            return false, nil
        end
        print("[MailService] towerBugComp sent uid=" .. tostring(uid)
            .. " currentFloor=" .. tostring(currentFloor)
            .. " rewardFloor=" .. tostring(rewardFloor)
            .. " compensation=" .. tostring(compensation)
            .. " dmId=" .. tostring(dmId))
    else
        print("[MailService] towerBugComp no compensation uid=" .. tostring(uid)
            .. " currentFloor=" .. tostring(currentFloor)
            .. " rewardFloor=" .. tostring(rewardFloor)
            .. " compensation=" .. tostring(compensation))
    end

    mailData.compensationFlags[TOWER_BUG_COMP_FLAG] = true
    PDM.MarkDirty(uid, "mail")
    return true, {
        currentFloor = currentFloor,
        rewardFloor = rewardFloor,
        compensation = compensation,
    }
end

-- ======================== 老玩家首通黄金钥匙补偿 ========================

local GOLDEN_KEY_RETRO_FLAG = "goldenKeyRetroV1"
local GOLDEN_KEY_RETRO_CUTOFF_TS = 1782489600  -- 2026-06-27 00:00:00 UTC+8

local function isGoldenKeyRetroEligible(uid)
    local sid = getCurrentServerId(uid)
    if ServerListConfig.isChallengerServer(sid) then
        return false, "challenger_server", sid
    end
    local serverCfg = ServerListConfig.find(sid)
    if serverCfg and serverCfg.openTime and serverCfg.openTime > 0 and serverCfg.openTime >= GOLDEN_KEY_RETRO_CUTOFF_TS then
        return false, "new_server", sid
    end

    return true, nil, sid
end

---@param clearedStages table|nil
---@param stageId number
---@return boolean
local function hasClearedStage(clearedStages, stageId)
    if type(clearedStages) ~= "table" then return false end
    return not not (clearedStages[stageId] or clearedStages[tostring(stageId)])
end

---@param battleData table
---@return number missingGoldenKey
---@return number rewardStageCount
local function calculateMissingFirstClearGoldenKeys(battleData)
    local clearedStages = battleData.clearedStages or {}
    local missing = 0
    local stageCount = 0

    for _, stageEntry in ipairs(StageConfig.STAGES or {}) do
        local stageId = tonumber(stageEntry.id) or 0
        local goldenKey = StageConfig.getFirstClearGoldenKey(stageId, stageEntry)
        if goldenKey > 0 and hasClearedStage(clearedStages, stageId) then
            missing = missing + goldenKey
            stageCount = stageCount + 1
        end
    end

    return missing, stageCount
end

---@param uid number
---@return boolean checked
---@return table|nil result
function MailService.CheckAndSendGoldenKeyRetroCompensation(uid)
    local mailData = PDM.GetModule(uid, "mail")
    local battleData = PDM.GetModule(uid, "battle")
    if not mailData or not battleData then
        print("[MailService] goldenKeyRetro skip: missing data uid=" .. tostring(uid)
            .. " mail=" .. tostring(mailData ~= nil) .. " battle=" .. tostring(battleData ~= nil))
        return false, nil
    end

    if not mailData.compensationFlags then mailData.compensationFlags = {} end
    if mailData.compensationFlags[GOLDEN_KEY_RETRO_FLAG] then
        return true, { alreadyChecked = true }
    end

    local eligible, ineligibleReason, sid = isGoldenKeyRetroEligible(uid)
    if not eligible then
        mailData.compensationFlags[GOLDEN_KEY_RETRO_FLAG] = true
        PDM.MarkDirty(uid, "mail")
        print("[MailService] goldenKeyRetro blocked uid=" .. tostring(uid)
            .. " serverId=" .. tostring(sid)
            .. " reason=" .. tostring(ineligibleReason))
        return true, { ineligible = true, reason = ineligibleReason, serverId = sid }
    end

    local missingGoldenKey, rewardStageCount = calculateMissingFirstClearGoldenKeys(battleData)
    local compensation = math.floor(missingGoldenKey / 2)

    if compensation > 0 then
        local dmId = MailService.SendDynamicMail(uid, {
            title = "首通黄金钥匙补偿",
            body = "新版已为噩梦及以后各章首通追加黄金钥匙奖励，但新玩家对应关卡的首通钻石奖励也有所下调。综合两边资源投放差异，系统根据你的历史通关记录，按缺失黄金钥匙数量的一半进行补发，请在邮件中领取。",
            rewards = {
                { type = "golden_key", amount = compensation },
            },
            source = GOLDEN_KEY_RETRO_FLAG,
        })
        if not dmId then
            print("[MailService] goldenKeyRetro send failed uid=" .. tostring(uid)
                .. " missing=" .. tostring(missingGoldenKey)
                .. " compensation=" .. tostring(compensation))
            return false, nil
        end
        print("[MailService] goldenKeyRetro sent uid=" .. tostring(uid)
            .. " stages=" .. tostring(rewardStageCount)
            .. " missing=" .. tostring(missingGoldenKey)
            .. " compensation=" .. tostring(compensation)
            .. " dmId=" .. tostring(dmId))
    else
        print("[MailService] goldenKeyRetro no compensation uid=" .. tostring(uid)
            .. " stages=" .. tostring(rewardStageCount)
            .. " missing=" .. tostring(missingGoldenKey))
    end

    mailData.compensationFlags[GOLDEN_KEY_RETRO_FLAG] = true
    PDM.MarkDirty(uid, "mail")
    return true, {
        missingGoldenKey = missingGoldenKey,
        compensation = compensation,
        rewardStageCount = rewardStageCount,
    }
end

-- ======================== 领取单封邮件 ========================

---@param uid number
---@param mailId string
---@return boolean ok
---@return string|nil reason
---@return table|nil result { mailId, rewards }
function MailService.ClaimMail(uid, mailId)
    if not mailId or type(mailId) ~= "string" then
        return false, "参数错误"
    end

    local mailData = PDM.GetModule(uid, "mail")
    if not mailData then
        return false, "数据异常"
    end

    -- ---- 全服邮件分支 ----
    if isBroadcastMail(mailId) then
        local BroadcastMailService = require("server.mail.BroadcastMailService")
        local bmOk, bmErr, bmResult = BroadcastMailService.ClaimBroadcastMail(uid, mailId)
        return bmOk, bmErr, bmResult
    end

    -- ---- 动态邮件分支 ----
    if isDynamicMail(mailId) then
        if not mailData.inbox then mailData.inbox = {} end
        local dm = mailData.inbox[mailId]
        if not dm then
            return false, "邮件不存在"
        end

        if shouldExcludeMailForCurrentServer(uid, dm) then
            mailData.inbox[mailId] = nil
            PDM.MarkDirty(uid, "mail")
            print("[MailService] ClaimMail removed challenger compensation dynamic mail uid=" .. tostring(uid)
                .. " dmId=" .. tostring(mailId)
                .. " title=" .. tostring(dm.title))
            return false, "挑战者服不发放补偿邮件"
        end

        -- 发放奖励
        local failedRewards = {}
        for _, reward in ipairs(dm.rewards or {}) do
            if not CurrencyService.GrantReward(uid, reward) then
                failedRewards[#failedRewards + 1] = reward.type
                print("[MailService] WARN grant failed uid=" .. tostring(uid)
                    .. " dmId=" .. mailId .. " type=" .. tostring(reward.type))
            end
        end

        local rewards = dm.rewards
        -- 领取后从 inbox 移除（动态邮件领取即删除，不需要二次删除操作）
        mailData.inbox[mailId] = nil
        PDM.MarkDirty(uid, "mail")

        print("[MailService] ClaimMail(dynamic) uid=" .. tostring(uid) .. " dmId=" .. mailId
            .. (#failedRewards > 0 and (" failedRewards=" .. table.concat(failedRewards, ",")) or ""))
        return true, nil, { mailId = mailId, rewards = rewards }
    end

    -- ---- 静态邮件分支（原逻辑） ----
    local mailDef = findMailDef(mailId)
    if not mailDef then
        return false, "邮件不存在"
    end

    if shouldExcludeMailForCurrentServer(uid, mailDef) then
        return false, "挑战者服不发放补偿邮件"
    end

    if mailData.deleted and mailData.deleted[mailId] then
        return false, "邮件已删除"
    end
    if mailData.claimed and mailData.claimed[mailId] then
        return false, "已领取"
    end

    -- 发放奖励（检查返回值，记录失败的奖励）
    local failedRewards = {}
    for _, reward in ipairs(mailDef.rewards or {}) do
        if not CurrencyService.GrantReward(uid, reward) then
            failedRewards[#failedRewards + 1] = reward.type
            print("[MailService] WARN grant failed uid=" .. tostring(uid)
                .. " mailId=" .. mailId .. " type=" .. tostring(reward.type))
        end
    end

    -- 标记已领取（即使部分奖励失败也标记，防止重复领取）
    if not mailData.claimed then mailData.claimed = {} end
    mailData.claimed[mailId] = true
    PDM.MarkDirty(uid, "mail")

    print("[MailService] ClaimMail uid=" .. tostring(uid) .. " mailId=" .. mailId
        .. (#failedRewards > 0 and (" failedRewards=" .. table.concat(failedRewards, ",")) or ""))
    return true, nil, { mailId = mailId, rewards = mailDef.rewards }
end

-- ======================== 一键领取所有未领取邮件 ========================

---@param uid number
---@return boolean ok
---@return string|nil reason
---@return table|nil result { claimedIds, rewards }
function MailService.ClaimAll(uid)
    local mailData = PDM.GetModule(uid, "mail")
    if not mailData then
        return false, "数据异常"
    end

    if not mailData.claimed then mailData.claimed = {} end
    if not mailData.deleted then mailData.deleted = {} end

    local claimedIds = {}
    local allRewards = {}
    local removedBlockedCount = 0

    -- 静态邮件
    local now = os.time()
    for _, mailDef in ipairs(MailConfig.MAILS) do
        local mid = mailDef.id
        -- 定时邮件：未到发送日期则跳过
        if mailDef.sendDate and now < mailDef.sendDate then
            goto continue_claim
        end
        if shouldExcludeMailForCurrentServer(uid, mailDef) then
            goto continue_claim
        end
        if not mailData.claimed[mid] and not mailData.deleted[mid] then
            for _, reward in ipairs(mailDef.rewards or {}) do
                if CurrencyService.GrantReward(uid, reward) then
                    local entry = { type = reward.type, amount = reward.amount }
                    if reward.heroId then entry.heroId = reward.heroId end
                    allRewards[#allRewards + 1] = entry
                else
                    print("[MailService] WARN ClaimAll grant failed uid=" .. tostring(uid)
                        .. " mailId=" .. mid .. " type=" .. tostring(reward.type))
                end
            end
            mailData.claimed[mid] = true
            claimedIds[#claimedIds + 1] = mid
        end
        ::continue_claim::
    end

    -- 动态邮件
    if not mailData.inbox then mailData.inbox = {} end
    local dmToRemove = {}
    for dmId, dm in pairs(mailData.inbox) do
        if shouldExcludeMailForCurrentServer(uid, dm) then
            dmToRemove[#dmToRemove + 1] = dmId
            print("[MailService] ClaimAll removing challenger compensation dynamic mail uid=" .. tostring(uid)
                .. " dmId=" .. tostring(dmId)
                .. " title=" .. tostring(dm.title))
            goto continue_dm_claim
        end
        for _, reward in ipairs(dm.rewards or {}) do
            if CurrencyService.GrantReward(uid, reward) then
                local entry = { type = reward.type, amount = reward.amount }
                if reward.heroId then entry.heroId = reward.heroId end
                allRewards[#allRewards + 1] = entry
            else
                print("[MailService] WARN ClaimAll grant failed uid=" .. tostring(uid)
                    .. " dmId=" .. dmId .. " type=" .. tostring(reward.type))
            end
        end
        claimedIds[#claimedIds + 1] = dmId
        dmToRemove[#dmToRemove + 1] = dmId
        ::continue_dm_claim::
    end
    for _, dmId in ipairs(dmToRemove) do
        mailData.inbox[dmId] = nil
        removedBlockedCount = removedBlockedCount + 1
    end

    -- 全服广播邮件
    local BroadcastMailService = require("server.mail.BroadcastMailService")
    local bmMails = BroadcastMailService.GetMailsForPlayer(uid)
    for _, bm in ipairs(bmMails) do
        for _, reward in ipairs(bm.rewards or {}) do
            if CurrencyService.GrantReward(uid, reward) then
                local entry = { type = reward.type, amount = reward.amount }
                if reward.heroId then entry.heroId = reward.heroId end
                allRewards[#allRewards + 1] = entry
            else
                print("[MailService] WARN ClaimAll broadcast grant failed uid=" .. tostring(uid)
                    .. " bmId=" .. bm.id .. " type=" .. tostring(reward.type))
            end
        end
        -- 标记已领取
        if not mailData.claimedBroadcasts then mailData.claimedBroadcasts = {} end
        mailData.claimedBroadcasts[bm.id] = true
        claimedIds[#claimedIds + 1] = bm.id
    end

    if #claimedIds > 0 or removedBlockedCount > 0 then
        PDM.MarkDirty(uid, "mail")
    end

    print("[MailService] ClaimAll uid=" .. tostring(uid) .. " claimed=" .. #claimedIds)
    return true, nil, { claimedIds = claimedIds, rewards = allRewards }
end

-- ======================== 删除已读（已领取）邮件 ========================

---@param uid number
---@return boolean ok
---@return string|nil reason
---@return table|nil result { deletedIds }
function MailService.DeleteRead(uid)
    local mailData = PDM.GetModule(uid, "mail")
    if not mailData then
        return false, "数据异常"
    end

    if not mailData.claimed then mailData.claimed = {} end
    if not mailData.deleted then mailData.deleted = {} end

    local deletedIds = {}

    print("[MailService][DIAG] DeleteRead uid=" .. tostring(uid) .. " configMails=" .. #MailConfig.MAILS)
    for _, mailDef in ipairs(MailConfig.MAILS) do
        local mid = mailDef.id
        local isClaimed = mailData.claimed[mid]
        local isDeleted = mailData.deleted[mid]
        print("[MailService][DIAG]   DeleteRead check mail[" .. mid .. "] claimed=" .. tostring(isClaimed) .. " deleted=" .. tostring(isDeleted))
        if isClaimed and not isDeleted then
            mailData.deleted[mid] = true
            deletedIds[#deletedIds + 1] = mid
            print("[MailService][DIAG]   → DELETING mail[" .. mid .. "]")
        end
    end

    if #deletedIds > 0 then
        PDM.MarkDirty(uid, "mail")
    end

    print("[MailService] DeleteRead uid=" .. tostring(uid) .. " deleted=" .. #deletedIds .. " ids=[" .. table.concat(deletedIds, ",") .. "]")
    return true, nil, { deletedIds = deletedIds }
end

-- ======================== 构建客户端邮件列表 ========================

--- 根据配置和玩家状态，生成推送给客户端的邮件列表
--- 被 Server.lua 调用（登录时推送邮件列表）
---@param uid number
---@return table[] 邮件列表（客户端格式）
function MailService.BuildMailList(uid)
    local mailData = PDM.GetModule(uid, "mail")
    if not mailData then
        print("[MailService][DEBUG] BuildMailList uid=" .. tostring(uid) .. " mailData=NIL (PDM module not loaded)")
        return {}
    end

    -- 登录时清理过期的 claimedBroadcasts（防止无限增长）
    local pruned = pruneExpiredBroadcastClaims(mailData)
    if pruned > 0 then
        PDM.MarkDirty(uid, "mail")
    end

    -- ======== 详细诊断日志 START ========
    -- 打印 mailData 完整结构概要
    local deletedKeys = {}
    if mailData.deleted then
        for k, v in pairs(mailData.deleted) do
            deletedKeys[#deletedKeys + 1] = tostring(k) .. "=" .. tostring(v)
        end
    end
    local claimedKeys = {}
    if mailData.claimed then
        for k, v in pairs(mailData.claimed) do
            claimedKeys[#claimedKeys + 1] = tostring(k) .. "=" .. tostring(v)
        end
    end
    local sentKeys = {}
    if mailData.sentDates then
        for k, v in pairs(mailData.sentDates) do
            sentKeys[#sentKeys + 1] = tostring(k) .. "=" .. tostring(v)
        end
    end
    local inboxKeys = {}
    if mailData.inbox then
        for k, _ in pairs(mailData.inbox) do
            inboxKeys[#inboxKeys + 1] = tostring(k)
        end
    end

    print("[MailService][DIAG] BuildMailList uid=" .. tostring(uid))
    print("[MailService][DIAG]   configMails count=" .. tostring(#MailConfig.MAILS))
    print("[MailService][DIAG]   deleted keys: [" .. table.concat(deletedKeys, ", ") .. "]")
    print("[MailService][DIAG]   claimed keys: [" .. table.concat(claimedKeys, ", ") .. "]")
    print("[MailService][DIAG]   sentDates keys: [" .. table.concat(sentKeys, ", ") .. "]")
    print("[MailService][DIAG]   inbox keys: [" .. table.concat(inboxKeys, ", ") .. "]")
    -- ======== 详细诊断日志 END ========

    local result = {}

    -- 静态邮件
    if not mailData.sentDates then mailData.sentDates = {} end
    local sentDatesModified = false
    local now = os.time()
    for _, mailDef in ipairs(MailConfig.MAILS) do
        local mid = mailDef.id
        -- 定时邮件：未到发送日期则跳过
        if mailDef.sendDate and now < mailDef.sendDate then
            goto continue_mail
        end
        if shouldExcludeMailForCurrentServer(uid, mailDef) then
            goto continue_mail
        end
        local isDeleted = mailData.deleted and mailData.deleted[mid]
        print("[MailService][DIAG]   mail[" .. mid .. "] deleted=" .. tostring(isDeleted))
        if not isDeleted then
            -- 首次看到此邮件时记录时间戳（只记录一次，之后永远用这个时间）
            if not mailData.sentDates[mid] then
                mailData.sentDates[mid] = os.time()
                sentDatesModified = true
            end
            local sentAt     = mailData.sentDates[mid]
            local daysPassed = math.floor((os.time() - sentAt) / 86400)
            local remainDays = math.max(0, mailDef.remainDays - daysPassed)
            result[#result + 1] = {
                id         = mid,
                title      = mailDef.title,
                body       = mailDef.body,
                remainDays = remainDays,
                rewards    = mailDef.rewards,
                read       = mailData.claimed and mailData.claimed[mid] == true,
                date       = os.date("%Y/%m/%d", sentAt),
            }
        end
        ::continue_mail::
    end
    if sentDatesModified then
        PDM.MarkDirty(uid, "mail")
    end

    -- 动态邮件（inbox 中存在即未领取）
    if mailData.inbox then
        local removedIds = {}
        for dmId, dm in pairs(mailData.inbox) do
            if shouldExcludeMailForCurrentServer(uid, dm) then
                removedIds[#removedIds + 1] = dmId
                print("[MailService] BuildMailList removing challenger compensation dynamic mail uid=" .. tostring(uid)
                    .. " dmId=" .. tostring(dmId)
                    .. " title=" .. tostring(dm.title))
            else
                result[#result + 1] = {
                    id      = dmId,
                    title   = dm.title,
                    body    = dm.body or "",
                    rewards = dm.rewards,
                    read    = false,   -- inbox 中的邮件一定未领取
                    date    = dm.date or os.date("%Y/%m/%d"),
                    source  = dm.source,
                }
            end
        end
        if #removedIds > 0 then
            for _, dmId in ipairs(removedIds) do
                mailData.inbox[dmId] = nil
            end
            PDM.MarkDirty(uid, "mail")
        end
    end

    -- 全服广播邮件（未领取、未过期的）
    local okBm, BroadcastMailService = pcall(require, "server.mail.BroadcastMailService")
    if okBm and BroadcastMailService and BroadcastMailService.GetMailsForPlayer then
        local bmMails = BroadcastMailService.GetMailsForPlayer(uid)
        for _, bm in ipairs(bmMails) do
            result[#result + 1] = {
                id      = bm.id,
                title   = bm.title,
                body    = bm.body or "",
                rewards = bm.rewards,
                read    = false,
                date    = bm.date or os.date("%Y/%m/%d"),
                source  = "broadcast",
            }
        end
    end

    print("[MailService][DIAG] BuildMailList uid=" .. tostring(uid) .. " FINAL result count=" .. #result)
    for i, m in ipairs(result) do
        print("[MailService][DIAG]   result[" .. i .. "] id=" .. tostring(m.id) .. " read=" .. tostring(m.read) .. " title=" .. tostring(m.title))
    end
    return result
end

return MailService
