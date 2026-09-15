-- ============================================================================
-- ChallengerService - 挑战者区服全局权益与懒投递
-- 层级: server/challenger | 通过 PDM 读写，网络推送由 PDM/MailHandler 间接完成
--
-- 奖励发放两条线：
-- 1. 挑战者服达成档位后，立即投递到当前挑战者服邮件
-- 2. 永久服懒投递：进入任意永久服时补发未投递档位（含后续新开服）
--    同一服待投递 >= MERGE_MAIL_THRESHOLD 档时，合并为一封邮件
-- ============================================================================

local PDM                    = require("server.character.PlayerDataManager")
local ServerListConfig       = require("shared.ServerListConfig")
local ChallengerServerConfig = require("shared.ChallengerServerConfig")
local ChallengerConsts       = require("shared.challenger.ChallengerConsts")
local ResourceDefs           = require("config.ResourceDefs")
local StageProvider          = require("shared.StageProvider")

local ChallengerService = {}

local MERGE_THRESHOLD = ChallengerConsts.MERGE_MAIL_THRESHOLD or 8

local function pushMailListToClient(uid)
    local okHandler, MailHandler = pcall(require, "server.mail.MailHandler")
    local okDispatcher, ServerDispatcher = pcall(require, "network.ServerDispatcher")
    local okProtocol, Protocol = pcall(require, "shared.Protocol")
    if not okHandler or not okDispatcher or not okProtocol then
        return
    end
    if not MailHandler.buildMailList or not ServerDispatcher.sendEvent then
        return
    end
    local mailList = MailHandler.buildMailList(uid)
    ServerDispatcher.sendEvent(uid, Protocol.RES_ACTION_RESULT, {
        success = true,
        mailPush = true,
        mails = mailList,
    })
end

local function ensureRoot(uid)
    local data = PDM.GetModule(uid, "challenger")
    if not data then return nil end
    if not data.activities then data.activities = {} end
    return data
end

local function ensureActivity(data, cfg)
    local activityId = cfg.activityId or ChallengerConsts.ACTIVITY_ID
    local activity = data.activities[activityId]
    if type(activity) ~= "table" then
        activity = {
            serverId = cfg.id,
            bestStageId = 0,
            settled = false,
            settledAt = 0,
            rewardTier = 0,
            tierName = "",
            rewards = {},
            claimScope = cfg.claimScope or ChallengerConsts.CLAIM_SCOPE_PER_NON_CHALLENGER_SERVER,
            deliveredServers = {},
            deliveredTiersByServer = {},
        }
        data.activities[activityId] = activity
    end
    activity.serverId = cfg.id
    if not activity.claimScope then
        activity.claimScope = cfg.claimScope or ChallengerConsts.CLAIM_SCOPE_PER_NON_CHALLENGER_SERVER
    end
    if type(activity.deliveredServers) ~= "table" then activity.deliveredServers = {} end
    if type(activity.deliveredTiersByServer) ~= "table" then activity.deliveredTiersByServer = {} end
    if type(activity.rewards) ~= "table" then activity.rewards = {} end
    activity.bestStageId = tonumber(activity.bestStageId) or 0
    activity.rewardTier = tonumber(activity.rewardTier) or 0
    activity.tierName = activity.tierName or ""
    return activity, activityId
end

local function getActivity(data, cfg)
    local activityId = cfg.activityId or ChallengerConsts.ACTIVITY_ID
    local activity = data.activities and data.activities[activityId]
    if type(activity) ~= "table" then return nil, activityId end
    if type(activity.deliveredServers) ~= "table" then activity.deliveredServers = {} end
    if type(activity.deliveredTiersByServer) ~= "table" then activity.deliveredTiersByServer = {} end
    if type(activity.rewards) ~= "table" then activity.rewards = {} end
    activity.bestStageId = tonumber(activity.bestStageId) or 0
    activity.rewardTier = tonumber(activity.rewardTier) or 0
    activity.tierName = activity.tierName or ""
    return activity, activityId
end

local function tierKey(tier)
    return tostring(tier.rewardTier or tier.minStageId)
end

local function ensureDeliveredTierMap(activity, serverKey)
    if type(activity.deliveredTiersByServer) ~= "table" then
        activity.deliveredTiersByServer = {}
    end
    if type(activity.deliveredTiersByServer[serverKey]) ~= "table" then
        activity.deliveredTiersByServer[serverKey] = {}
    end
    return activity.deliveredTiersByServer[serverKey]
end

local function migrateLegacyDelivered(activity, cfg)
    if activity._legacyDeliveredMigrated then return end
    if type(activity.deliveredServers) ~= "table" then
        activity._legacyDeliveredMigrated = true
        return
    end

    local bestStageId = tonumber(activity.bestStageId) or 0
    for serverKey, delivered in pairs(activity.deliveredServers) do
        if delivered then
            local tierMap = ensureDeliveredTierMap(activity, tostring(serverKey))
            for _, tier in ipairs(cfg.rewardTable or {}) do
                if bestStageId >= (tonumber(tier.minStageId) or 0) then
                    tierMap[tierKey(tier)] = true
                end
            end
        end
    end
    activity._legacyDeliveredMigrated = true
end

local function selectRewardTier(cfg, bestStageId)
    local selected = nil
    for _, tier in ipairs(cfg.rewardTable or {}) do
        if bestStageId >= (tonumber(tier.minStageId) or 0) then
            if not selected or (tonumber(tier.minStageId) or 0) >= (tonumber(selected.minStageId) or 0) then
                selected = tier
            end
        end
    end
    return selected
end

local function mergeUnlockedAvatarFrames(root, cfg, bestStageId)
    if not root then return false end
    if type(root.unlockedAvatarFrames) ~= "table" then
        root.unlockedAvatarFrames = {}
    end
    if type(root.avatarFrameGrants) ~= "table" then
        root.avatarFrameGrants = {}
    end

    local changed = false
    local activityId = tostring(cfg.activityId or ChallengerConsts.ACTIVITY_ID)
    if type(root.avatarFrameGrants[activityId]) ~= "table" then
        root.avatarFrameGrants[activityId] = {}
        changed = true
    end
    local granted = root.avatarFrameGrants[activityId]

    for _, tier in ipairs(cfg.rewardTable or {}) do
        if bestStageId >= (tonumber(tier.minStageId) or 0) then
            local frameId = tonumber(tier.avatarFrameId)
            if frameId then
                local frameKey = tostring(frameId)
                local grantKey = tierKey(tier)
                if not granted[grantKey] then
                    local currentLevel = tonumber(root.unlockedAvatarFrames[frameKey]) or 0
                    local incrementValue = tier.avatarFrameIncrement
                    if type(incrementValue) == "number" then
                        root.unlockedAvatarFrames[frameKey] = math.min(
                            2,
                            currentLevel + math.max(1, incrementValue)
                        )
                    else
                        root.unlockedAvatarFrames[frameKey] = math.max(1, currentLevel)
                    end
                    granted[grantKey] = true
                    changed = true
                    print("[ChallengerService] avatar frame grant activity=" .. activityId
                        .. " tier=" .. grantKey
                        .. " frame=" .. frameKey
                        .. " level=" .. tostring(root.unlockedAvatarFrames[frameKey]))
                end
            end
        end
    end
    return changed
end

local function syncActivitySummary(activity, cfg, bestStageId)
    local selectedTier = selectRewardTier(cfg, bestStageId)
    activity.rewardTier = selectedTier and (tonumber(selectedTier.rewardTier) or tonumber(selectedTier.minStageId) or 0) or 0
    activity.tierName = selectedTier and selectedTier.tierName or ""
    if selectedTier then
        activity.rewards = ResourceDefs.normalizeMailRewardList(selectedTier.rewards or selectedTier.reward or {})
    else
        activity.rewards = {}
    end
end

local function hasMailSource(mailData, source)
    if not mailData or type(mailData.inbox) ~= "table" then return false end
    for _, mail in pairs(mailData.inbox) do
        if type(mail) == "table" and mail.source == source then
            return true
        end
    end
    return false
end

local function isRewardAlreadySent(mailData, source)
    if not mailData then return false end
    if mailData.compensationFlags and mailData.compensationFlags[source] then
        return true
    end
    return hasMailSource(mailData, source)
end

local function isMailSourceFlagged(mailData, source)
    return mailData
        and type(mailData.compensationFlags) == "table"
        and mailData.compensationFlags[source] == true
end

local function ensureMailSourceFlag(mailData, source)
    if not mailData or type(source) ~= "string" or source == "" then return false end
    if isMailSourceFlagged(mailData, source) then return false end
    if not hasMailSource(mailData, source) then return false end
    if type(mailData.compensationFlags) ~= "table" then mailData.compensationFlags = {} end
    mailData.compensationFlags[source] = true
    return true
end

local function isMergedSourceForTier(source, cfg, serverKey, targetTierKey)
    if type(source) ~= "string" then return false end
    local prefix = "challenger:" .. tostring(cfg.activityId) .. ":merged:s" .. serverKey .. ":t"
    if source:sub(1, #prefix) ~= prefix then return false end
    local suffix = source:sub(#prefix + 1)
    for key in string.gmatch(suffix, "[^_]+") do
        if key == targetTierKey then
            return true
        end
    end
    return false
end

local function findSentSourceForTier(mailData, cfg, tier, serverKey)
    if not mailData then return nil end
    local targetTierKey = tierKey(tier)
    local singleSource = "challenger:" .. tostring(cfg.activityId) .. ":t" .. targetTierKey .. ":s" .. serverKey
    if isRewardAlreadySent(mailData, singleSource) then
        return singleSource
    end

    if type(mailData.compensationFlags) == "table" then
        for source, sent in pairs(mailData.compensationFlags) do
            if sent and isMergedSourceForTier(source, cfg, serverKey, targetTierKey) then
                return source
            end
        end
    end
    if type(mailData.inbox) == "table" then
        for _, mail in pairs(mailData.inbox) do
            local source = type(mail) == "table" and mail.source or nil
            if isMergedSourceForTier(source, cfg, serverKey, targetTierKey) then
                return source
            end
        end
    end
    return nil
end

local function hasAnyDeliveredTier(delivered)
    if type(delivered) ~= "table" then return false end
    for _, deliveredValue in pairs(delivered) do
        if deliveredValue then return true end
    end
    return false
end

local function reconcileLoginDeliveryState(uid, cfg, activity, bestStageId, serverKey)
    local mailData = PDM.GetModule(uid, "mail")
    if not mailData then return false, false end

    local delivered = ensureDeliveredTierMap(activity, serverKey)
    local challengerChanged = false
    local mailChanged = false
    local repairedKeys = {}
    local syncedKeys = {}

    for _, tier in ipairs(cfg.rewardTable or {}) do
        if bestStageId >= (tonumber(tier.minStageId) or 0) then
            local key = tierKey(tier)
            local sentSource = findSentSourceForTier(mailData, cfg, tier, serverKey)
            if sentSource then
                if ensureMailSourceFlag(mailData, sentSource) then
                    mailChanged = true
                end
                if not delivered[key] then
                    delivered[key] = true
                    challengerChanged = true
                    syncedKeys[#syncedKeys + 1] = key
                end
            elseif delivered[key] then
                delivered[key] = nil
                challengerChanged = true
                repairedKeys[#repairedKeys + 1] = key
            end
        end
    end

    activity.deliveredServers[serverKey] = hasAnyDeliveredTier(delivered) or nil

    if #syncedKeys > 0 then
        print("[ChallengerService] login sync delivered tiers from mail evidence uid=" .. tostring(uid)
            .. " activity=" .. tostring(cfg.activityId)
            .. " server=" .. serverKey
            .. " tiers=" .. table.concat(syncedKeys, ","))
    end
    if #repairedKeys > 0 then
        print("[ChallengerService] login repair missing challenger mails uid=" .. tostring(uid)
            .. " activity=" .. tostring(cfg.activityId)
            .. " server=" .. serverKey
            .. " tiers=" .. table.concat(repairedKeys, ","))
    end

    return challengerChanged, mailChanged
end

local function formatProgress(cfg, stageId)
    local stageConfig = StageProvider.GetForServer(cfg.id)
    if stageConfig and stageConfig.formatProgressDisplay then
        return stageConfig.formatProgressDisplay(stageId)
    end
    local entry = stageConfig and stageConfig.getStage and stageConfig.getStage(stageId)
    return (entry and entry.name) or tostring(stageId)
end

local function collectUndeliveredTiers(cfg, activity, bestStageId, serverKey)
    local delivered = ensureDeliveredTierMap(activity, serverKey)
    local undelivered = {}
    for _, tier in ipairs(cfg.rewardTable or {}) do
        if bestStageId >= (tonumber(tier.minStageId) or 0) then
            local key = tierKey(tier)
            if not delivered[key] then
                undelivered[#undelivered + 1] = tier
            end
        end
    end
    table.sort(undelivered, function(a, b)
        return (tonumber(a.rewardTier) or 0) < (tonumber(b.rewardTier) or 0)
    end)
    return undelivered
end

local function markTiersDelivered(activity, serverKey, tiers)
    local delivered = ensureDeliveredTierMap(activity, serverKey)
    for _, tier in ipairs(tiers) do
        delivered[tierKey(tier)] = true
    end
    activity.deliveredServers[serverKey] = true
end

local function buildTierMailBody(cfg, tier, bestStageId, isChallengerServer)
    local progressName = formatProgress(cfg, bestStageId)
    local tierLabel = tier.tierName or ("第" .. tierKey(tier) .. "档")
    local scopeHint = isChallengerServer
        and "奖励已发放至当前挑战者区服邮箱。"
        or "该奖励会在每个非挑战区服各投递一次。"
    return "恭喜达成【" .. tostring(tierLabel) .. "】！你在挑战者区服中最高达到 "
        .. tostring(progressName) .. "，根据活动规则获得以下奖励。" .. scopeHint
end

local function buildMergedMailBody(cfg, tiers, bestStageId)
    local progressName = formatProgress(cfg, bestStageId)
    local names = {}
    for _, tier in ipairs(tiers) do
        names[#names + 1] = tier.tierName or ("第" .. tierKey(tier) .. "档")
    end
    return "恭喜达成多项挑战者成就（共 " .. tostring(#tiers) .. " 档："
        .. table.concat(names, "、")
        .. "）！你在挑战者区服中最高达到 "
        .. tostring(progressName)
        .. "。为避免邮箱过多，以下奖励已合并为一封邮件发放。"
end

local function markMailSent(mailData, source)
    if not mailData.compensationFlags then mailData.compensationFlags = {} end
    mailData.compensationFlags[source] = true
end

local function sendSingleTierMail(uid, cfg, activity, tier, serverKey, bestStageId, isChallengerServer)
    local mailData = PDM.GetModule(uid, "mail")
    if not mailData then return false end

    local source = "challenger:" .. tostring(cfg.activityId) .. ":t" .. tierKey(tier) .. ":s" .. serverKey
    if isRewardAlreadySent(mailData, source) then
        markTiersDelivered(activity, serverKey, { tier })
        return true
    end

    local rawRewards = tier.rewards or tier.reward or {}
    local normalized = ResourceDefs.normalizeMailRewardList(rawRewards)
    if ResourceDefs.hasDroppedMailRewards(rawRewards, normalized) then
        print("[ChallengerService][ERROR] dropped invalid tier rewards uid=" .. tostring(uid)
            .. " activity=" .. tostring(cfg.activityId)
            .. " tier=" .. tierKey(tier))
        return false
    end
    if #normalized <= 0 then
        markTiersDelivered(activity, serverKey, { tier })
        return true
    end

    local MailService = require("server.mail.MailService")
    local dmId = MailService.SendDynamicMail(uid, {
        title = "挑战者成就奖励",
        body = buildTierMailBody(cfg, tier, bestStageId, isChallengerServer),
        rewards = normalized,
        source = source,
    })
    if not dmId then
        print("[ChallengerService][WARN] tier deliver failed uid=" .. tostring(uid)
            .. " activity=" .. tostring(cfg.activityId)
            .. " tier=" .. tierKey(tier)
            .. " server=" .. serverKey)
        return false
    end

    markMailSent(mailData, source)
    markTiersDelivered(activity, serverKey, { tier })
    print("[ChallengerService] tier delivered uid=" .. tostring(uid)
        .. " activity=" .. tostring(cfg.activityId)
        .. " tier=" .. tierKey(tier)
        .. " server=" .. serverKey
        .. " dmId=" .. tostring(dmId))
    return true
end

local function sendMergedTierMail(uid, cfg, activity, tiers, serverKey, bestStageId)
    local mailData = PDM.GetModule(uid, "mail")
    if not mailData then return false end

    local tierKeys = {}
    for _, tier in ipairs(tiers) do
        tierKeys[#tierKeys + 1] = tierKey(tier)
    end
    table.sort(tierKeys, function(a, b) return tonumber(a) < tonumber(b) end)
    local source = "challenger:" .. tostring(cfg.activityId) .. ":merged:s" .. serverKey .. ":t" .. table.concat(tierKeys, "_")
    if isRewardAlreadySent(mailData, source) then
        markTiersDelivered(activity, serverKey, tiers)
        return true
    end

    local rewardLists = {}
    for _, tier in ipairs(tiers) do
        local rawRewards = tier.rewards or tier.reward or {}
        local normalized = ResourceDefs.normalizeMailRewardList(rawRewards)
        if ResourceDefs.hasDroppedMailRewards(rawRewards, normalized) then
            print("[ChallengerService][ERROR] dropped invalid merged tier rewards uid=" .. tostring(uid)
                .. " activity=" .. tostring(cfg.activityId)
                .. " tier=" .. tierKey(tier))
            return false
        end
        if #normalized > 0 then
            rewardLists[#rewardLists + 1] = normalized
        end
    end

    local mergedRewards = ResourceDefs.mergeMailRewardLists(rewardLists)
    if #mergedRewards <= 0 then
        markTiersDelivered(activity, serverKey, tiers)
        return true
    end

    local MailService = require("server.mail.MailService")
    local dmId = MailService.SendDynamicMail(uid, {
        title = "挑战者成就奖励（合并）",
        body = buildMergedMailBody(cfg, tiers, bestStageId),
        rewards = mergedRewards,
        source = source,
    })
    if not dmId then
        print("[ChallengerService][WARN] merged deliver failed uid=" .. tostring(uid)
            .. " activity=" .. tostring(cfg.activityId)
            .. " server=" .. serverKey
            .. " tiers=" .. tostring(#tiers))
        return false
    end

    markMailSent(mailData, source)
    markTiersDelivered(activity, serverKey, tiers)
    print("[ChallengerService] merged delivered uid=" .. tostring(uid)
        .. " activity=" .. tostring(cfg.activityId)
        .. " server=" .. serverKey
        .. " tiers=" .. tostring(#tiers)
        .. " dmId=" .. tostring(dmId))
    return true
end

local function deliverPendingRewards(uid, root, cfg, activity, currentServerId)
    if not currentServerId then return false end

    local bestStageId = tonumber(activity.bestStageId) or 0
    if bestStageId <= 0 then return false end

    migrateLegacyDelivered(activity, cfg)
    syncActivitySummary(activity, cfg, bestStageId)
    local avatarFramesChanged = mergeUnlockedAvatarFrames(root, cfg, bestStageId)

    local serverKey = tostring(currentServerId)
    local isChallengerServer = ServerListConfig.isChallengerServer(currentServerId)
    if not isChallengerServer
        and activity.claimScope ~= ChallengerConsts.CLAIM_SCOPE_PER_NON_CHALLENGER_SERVER then
        return false
    end

    local undelivered = collectUndeliveredTiers(cfg, activity, bestStageId, serverKey)
    if #undelivered <= 0 then
        if avatarFramesChanged then
            PDM.MarkDirty(uid, "challenger")
        end
        return avatarFramesChanged
    end

    local changed = avatarFramesChanged
    if #undelivered >= MERGE_THRESHOLD then
        if sendMergedTierMail(uid, cfg, activity, undelivered, serverKey, bestStageId) then
            changed = true
        end
    else
        for _, tier in ipairs(undelivered) do
            if sendSingleTierMail(uid, cfg, activity, tier, serverKey, bestStageId, isChallengerServer) then
                changed = true
            end
        end
    end

    if changed then
        PDM.MarkDirty(uid, "challenger")
        PDM.MarkDirty(uid, "mail")
    end
    return changed
end

local function resolveBestClearedStageId(battleData, stageConfig)
    if not battleData then return 0 end
    stageConfig = stageConfig or StageProvider.GetForServer(nil)

    local best = 0
    if type(battleData.clearedStages) == "table" then
        for k, cleared in pairs(battleData.clearedStages) do
            if cleared then
                local sid = tonumber(k)
                if sid and sid > best then
                    best = sid
                end
            end
        end
    end
    if best > 0 then return best end

    local maxStageId = tonumber(battleData.maxStageId or battleData.currentStageId) or 0
    if maxStageId <= 0 then return 0 end
    if type(battleData.clearedStages) == "table" and battleData.clearedStages[tostring(maxStageId)] then
        return maxStageId
    end
    if stageConfig and stageConfig.getPrevStageId then
        local prev = stageConfig.getPrevStageId(maxStageId)
        if prev then return prev end
    end
    if stageConfig and stageConfig.getTerminalPrevStageId then
        local prev = stageConfig.getTerminalPrevStageId(maxStageId)
        if prev then return prev end
    end
    return 0
end

function ChallengerService.CanPlay(uid)
    local serverId = PDM.GetServerId(uid)
    if not ServerListConfig.isChallengerServer(serverId) then
        return true
    end
    if ServerListConfig.isServerClosed(serverId) then
        return false, "挑战者活动已结束"
    end
    if not ChallengerServerConfig.IsOpen(serverId) then
        return false, "挑战者活动尚未开放"
    end
    if not StageProvider.IsAvailableForServer(serverId) then
        print("[ChallengerService][ERROR] stage config unavailable serverId=" .. tostring(serverId)
            .. " err=" .. tostring(StageProvider.GetLoadError(serverId)))
        return false, "挑战者配置异常，请稍后再试"
    end
    return true
end

function ChallengerService.OnEnterServer(uid, serverId)
    local cfg = ChallengerServerConfig.GetByServerId(serverId)
    if not cfg then return false end
    local root = ensureRoot(uid)
    if not root then return false end
    local activity = ensureActivity(root, cfg)

    local battleData = PDM.GetModule(uid, "battle")
    local stageConfig = StageProvider.GetForServer(serverId)
    local bestClearedStageId = resolveBestClearedStageId(battleData, stageConfig)
    if bestClearedStageId > (tonumber(activity.bestStageId) or 0) then
        activity.bestStageId = bestClearedStageId
        activity.updatedAt = os.time()
        print("[ChallengerService] backfill progress uid=" .. tostring(uid)
            .. " serverId=" .. tostring(serverId)
            .. " bestClearedStageId=" .. tostring(bestClearedStageId))
    end

    deliverPendingRewards(uid, root, cfg, activity, serverId)

    PDM.MarkDirty(uid, "challenger")
    print("[ChallengerService] enter challenger uid=" .. tostring(uid)
        .. " serverId=" .. tostring(serverId)
        .. " activity=" .. tostring(cfg.activityId))
    return true
end

function ChallengerService.RecordProgress(uid, bestStageId)
    local serverId = PDM.GetServerId(uid)
    local cfg = ChallengerServerConfig.GetByServerId(serverId)
    if not cfg then return false end

    bestStageId = tonumber(bestStageId) or 0
    if bestStageId <= 0 then return false end

    local root = ensureRoot(uid)
    if not root then return false end
    local activity = ensureActivity(root, cfg)

    if bestStageId > (activity.bestStageId or 0) then
        activity.bestStageId = bestStageId
        activity.updatedAt = os.time()
        local delivered = deliverPendingRewards(uid, root, cfg, activity, serverId)
        PDM.MarkDirty(uid, "challenger")
        if delivered then
            pushMailListToClient(uid)
        end
        print("[ChallengerService] progress uid=" .. tostring(uid)
            .. " serverId=" .. tostring(serverId)
            .. " bestStageId=" .. tostring(bestStageId))
        return true
    end
    return false
end

function ChallengerService.ProcessLoginRewards(uid)
    local currentServerId = PDM.GetServerId(uid)
    if not currentServerId or ServerListConfig.isChallengerServer(currentServerId) then
        return false
    end

    local root = ensureRoot(uid)
    if not root then
        print("[ChallengerService][WARN] login rewards skipped: challenger root missing uid=" .. tostring(uid)
            .. " serverId=" .. tostring(currentServerId))
        return false
    end

    local changed = false
    local mailChanged = false
    local serverKey = tostring(currentServerId)
    for _, cfg in pairs(ChallengerServerConfig.CHALLENGER_SERVERS) do
        local activity = ensureActivity(root, cfg)
        local bestStageId = tonumber(activity.bestStageId) or 0
        if bestStageId > 0 then
            local cChanged, mChanged = reconcileLoginDeliveryState(uid, cfg, activity, bestStageId, serverKey)
            changed = changed or cChanged
            mailChanged = mailChanged or mChanged
            if deliverPendingRewards(uid, root, cfg, activity, currentServerId) then
                changed = true
            end
        end
    end
    if changed then
        PDM.MarkDirty(uid, "challenger")
    end
    if mailChanged then
        PDM.MarkDirty(uid, "mail")
    end
    return changed or mailChanged
end

return ChallengerService
