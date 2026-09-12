---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- CrossInstanceService - 跨实例 GM 支持
-- 职责:
--   1. 在线玩家全局注册表（serverCloud 心跳注册 + 查询）
--   2. 离线邮件投递（serverCloud 暂存 + 登录时拉取）
-- 层级: server/gm  |  通过 serverCloud 实现跨实例通信
-- ============================================================================

local PDM = require("server.character.PlayerDataManager")
local ResourceDefs = require("config.ResourceDefs")
local ServerListConfig = require("shared.ServerListConfig")

local CrossInstanceService = {}

-- ======================== 配置常量 ========================

--- 全局在线注册表的 serverCloud key（用公共 UID 存储）
local PUBLIC_UID            = "GM_CROSS_INSTANCE"
local ONLINE_REGISTRY_KEY   = "online_registry"
local PENDING_MAIL_PREFIX   = "pending_gm_mail_"  -- + targetUid

--- 远程修复命令的 serverCloud key 前缀（+ targetUid）
local PENDING_REPAIR_PREFIX  = "pending_gm_repair_"

--- 修复命令轮询间隔（秒）
local REPAIR_POLL_INTERVAL = 10

--- 上次修复命令轮询时间
local lastRepairPollTime_ = 0

--- 在线注册过期时间（秒）：超过此时间未心跳的条目视为过期
local HEARTBEAT_EXPIRE_SEC  = 90

--- 心跳间隔（秒）
local HEARTBEAT_INTERVAL    = 30

-- ======================== 在线注册表（本实例内存 + 定时上报 cloud） ========================

--- 本实例当前在线数据（每次心跳时上报到 cloud）
---@type table<string, { uid: number, name: string, serverId: number, serverName: string, ts: number }>
local localOnlineCache_ = {}

--- 上次心跳上报时间
local lastHeartbeatTime_ = 0

--- 是否已初始化
local initialized_ = false

-- ======================== 初始化 ========================

--- 初始化跨实例服务（服务器启动时调用一次）
function CrossInstanceService.Init()
    if initialized_ then return end
    initialized_ = true
    print("[CrossInstanceService] Initialized")
end

-- ======================== 在线注册：本实例上报 ========================

--- 更新本实例的在线玩家列表到 cloud（由定时器驱动）
--- 每 HEARTBEAT_INTERVAL 秒上报一次
function CrossInstanceService.HeartbeatUpload()
    if not initialized_ then return end

    local now = os.time()
    if now - lastHeartbeatTime_ < HEARTBEAT_INTERVAL then return end
    lastHeartbeatTime_ = now

    -- 收集本实例在线信息
    local Server = require("network.Server")
    local ServerListConfig = require("shared.ServerListConfig")
    local onlineUIDs = Server.GetOnlineUIDs()

    -- 构建本实例的在线条目
    local entries = {}
    for _, uid in ipairs(onlineUIDs) do
        local playerMod = PDM.GetModule(uid, "player")
        local serverId = PDM.GetServerId(uid)
        local serverCfg = serverId and ServerListConfig.find(serverId)
        entries[tostring(uid)] = {
            uid        = uid,
            name       = playerMod and playerMod.name or "未知",
            serverId   = serverId,
            serverName = serverCfg and serverCfg.name or (serverId and ("S" .. tostring(serverId)) or "未选服"),
            ts         = now,
        }
    end

    -- 生成实例唯一标识（使用启动时间 + 进程 hash 确保不同实例 key 不同）
    local instanceId = CrossInstanceService.GetInstanceId()

    -- 将本实例的在线列表写入 cloud（以 instanceId 为子 key）
    local commit = serverCloud:BatchCommit("gm_heartbeat")
    commit:ScoreSet(PUBLIC_UID, ONLINE_REGISTRY_KEY .. "_" .. instanceId, {
        instanceId = instanceId,
        entries    = entries,
        ts         = now,
    })
    commit:Commit({
        ok = function()
            -- 静默成功
        end,
        error = function(code, reason)
            print("[CrossInstanceService][WARN] heartbeat upload failed code="
                .. tostring(code) .. " reason=" .. tostring(reason))
        end,
    })
end

--- 获取当前实例唯一 ID（基于服务器启动时间，同一进程生命周期内不变）
---@return string
function CrossInstanceService.GetInstanceId()
    if not CrossInstanceService._instanceId then
        local Server = require("network.Server")
        local startTime = Server.GetStartTime() or os.time()
        -- 使用启动时间作为简单的实例标识
        CrossInstanceService._instanceId = "inst_" .. tostring(startTime)
    end
    return CrossInstanceService._instanceId
end

-- ======================== 在线注册：GM 全局查询 ========================

--- 查询所有实例的在线玩家（异步回调）
--- 合并所有实例的注册数据，过滤掉过期条目
---@param callback fun(players: table[])  回调，参数是合并后的在线玩家列表
function CrossInstanceService.QueryAllOnlinePlayers(callback)
    if not initialized_ then
        -- 未初始化时回退到本实例数据
        callback(CrossInstanceService.GetLocalOnlinePlayers())
        return
    end

    -- 先获取本实例数据作为基准（总是最新的）
    local localPlayers = CrossInstanceService.GetLocalOnlinePlayers()
    local localUidSet = {}
    for _, p in ipairs(localPlayers) do
        localUidSet[tostring(p.uid)] = true
    end

    -- 读取所有实例的注册数据
    -- 由于 serverCloud:Get 只能读单个 key，我们使用 BatchGet 读取多个实例 key
    -- 但我们不知道有多少实例... 使用一个索引 key 存储已知实例列表
    serverCloud:Get(PUBLIC_UID, "instance_list", {
        ok = function(scores)
            local instanceList = scores and scores["instance_list"]
            if not instanceList or type(instanceList) ~= "table" then
                -- 没有索引，只返回本实例数据
                callback(localPlayers)
                return
            end

            -- 过滤掉过期的实例
            local now = os.time()
            local validInstances = {}
            for instId, ts in pairs(instanceList) do
                if now - (ts or 0) < HEARTBEAT_EXPIRE_SEC * 2 then
                    validInstances[#validInstances + 1] = instId
                end
            end

            if #validInstances == 0 then
                callback(localPlayers)
                return
            end

            -- 批量读取所有有效实例的在线数据
            local batch = serverCloud:BatchGet(PUBLIC_UID)
            for _, instId in ipairs(validInstances) do
                batch:Key(ONLINE_REGISTRY_KEY .. "_" .. instId)
            end
            batch:Fetch({
                ok = function(scores2)
                    local allPlayers = {}
                    local seenUids = {}

                    -- 本实例数据优先（最新）
                    for _, p in ipairs(localPlayers) do
                        seenUids[tostring(p.uid)] = true
                        allPlayers[#allPlayers + 1] = p
                    end

                    -- 合并其他实例数据（去重 + 去过期）
                    if scores2 then
                        for _, instId in ipairs(validInstances) do
                            local key = ONLINE_REGISTRY_KEY .. "_" .. instId
                            local instData = scores2[key]
                            if instData and type(instData) == "table" and instData.entries then
                                -- 跳过本实例（已经加过了）
                                if instData.instanceId ~= CrossInstanceService.GetInstanceId() then
                                    for uidStr, entry in pairs(instData.entries) do
                                        if not seenUids[uidStr] then
                                            -- 检查条目是否过期
                                            if entry.ts and (now - entry.ts) < HEARTBEAT_EXPIRE_SEC then
                                                seenUids[uidStr] = true
                                                allPlayers[#allPlayers + 1] = {
                                                    uid        = entry.uid,
                                                    name       = entry.name or "未知",
                                                    serverId   = entry.serverId,
                                                    serverName = entry.serverName or "未知",
                                                    remote     = true,  -- 标记来自其他实例
                                                }
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end

                    callback(allPlayers)
                end,
                error = function(code, reason)
                    print("[CrossInstanceService][WARN] batch read failed code="
                        .. tostring(code) .. " fallback to local")
                    callback(localPlayers)
                end,
            })
        end,
        error = function(code, reason)
            print("[CrossInstanceService][WARN] read instance_list failed, fallback to local")
            callback(localPlayers)
        end,
    })
end

--- 获取本实例在线玩家列表（同步，无网络 IO）
---@return table[]
function CrossInstanceService.GetLocalOnlinePlayers()
    local Server = require("network.Server")
    local ServerListConfig = require("shared.ServerListConfig")
    local onlineUIDs = Server.GetOnlineUIDs()
    local players = {}
    for _, uid in ipairs(onlineUIDs) do
        local playerMod = PDM.GetModule(uid, "player")
        local serverId = PDM.GetServerId(uid)
        local serverCfg = serverId and ServerListConfig.find(serverId)
        players[#players + 1] = {
            uid        = uid,
            name       = playerMod and playerMod.name or "未知",
            serverId   = serverId,
            serverName = serverCfg and serverCfg.name or (serverId and ("S" .. tostring(serverId)) or "未选服"),
            remote     = false,
        }
    end
    return players
end

--- 更新实例索引（记录本实例的存在，供其他实例发现）
function CrossInstanceService.UpdateInstanceIndex()
    if not initialized_ then return end

    local instanceId = CrossInstanceService.GetInstanceId()
    local now = os.time()

    -- 先读取当前索引
    serverCloud:Get(PUBLIC_UID, "instance_list", {
        ok = function(scores)
            local list = (scores and scores["instance_list"]) or {}
            if type(list) ~= "table" then list = {} end

            -- 更新本实例时间戳
            list[instanceId] = now

            -- 清理过期实例
            for instId, ts in pairs(list) do
                if now - (ts or 0) > HEARTBEAT_EXPIRE_SEC * 3 then
                    list[instId] = nil
                end
            end

            -- 写回
            local commit = serverCloud:BatchCommit("gm_inst_index")
            commit:ScoreSet(PUBLIC_UID, "instance_list", list)
            commit:Commit({
                ok = function() end,
                error = function(code, reason)
                    print("[CrossInstanceService][WARN] update instance_list failed code=" .. tostring(code))
                end,
            })
        end,
        error = function()
            -- 首次创建索引
            local list = { [instanceId] = now }
            local commit = serverCloud:BatchCommit("gm_inst_index_init")
            commit:ScoreSet(PUBLIC_UID, "instance_list", list)
            commit:Commit({ ok = function() end, error = function() end })
        end,
    })
end

-- ======================== 离线邮件投递 ========================

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
local function shouldKeepPendingForNonChallengerServer(uid, mail)
    return ServerListConfig.isChallengerServer(PDM.GetServerId(uid)) and isCompensationMail(mail)
end

--- 向目标玩家投递 GM 邮件（跨实例安全）
--- 如果目标在本实例在线 → 直接通过 MailService 写入 inbox
--- 如果目标不在本实例 → 写入 serverCloud 暂存，下次登录时拉取
---@param targetUid number
---@param title string
---@param body string
---@param rewards table[]|nil
---@return boolean ok （对于离线投递，true 仅表示写入 cloud 成功）
---@return string|nil reason
---@return table|nil result
function CrossInstanceService.SendMailCrossInstance(targetUid, title, body, rewards)
    if not targetUid then
        return false, "缺少 targetUid"
    end
    if not title or title == "" then
        return false, "邮件标题不能为空"
    end

    -- 构造标准格式奖励
    local mailRewards = ResourceDefs.normalizeMailRewardList(rewards)
    if ResourceDefs.hasDroppedMailRewards(rewards, mailRewards) then
        print("[CrossInstanceService][WARN] SendMail rewards dropped after normalize"
            .. " targetUid=" .. tostring(targetUid))
        return false, "奖励格式无效（碎片请用 101*数量、shard_16*数量 或 h16*数量）"
    end

    local mailEntry = {
        title   = title,
        body    = body or "",
        rewards = mailRewards,
        source  = "gm_console",
        excludeChallenger = hasCompensationMarker(title) or hasCompensationMarker(body),
        date    = os.date("%Y/%m/%d"),
        sentAt  = os.time(),
    }

    -- 尝试本实例直接投递
    if PDM.IsLoaded(targetUid) and not shouldKeepPendingForNonChallengerServer(targetUid, mailEntry) then
        local MailService = require("server.mail.MailService")
        local dmId = MailService.SendDynamicMail(targetUid, mailEntry)
        if dmId then
            print("[CrossInstanceService] SendMail LOCAL targetUid=" .. tostring(targetUid)
                .. " dmId=" .. dmId)
            return true, nil, { mailId = dmId, delivered = "local" }
        else
            return false, "本地投递失败"
        end
    end

    -- 目标不在本实例或当前在挑战者服且为补偿邮件 → 写入 serverCloud 待领取邮箱

    local cloudKey = PENDING_MAIL_PREFIX .. tostring(targetUid)

    -- 先读取现有待领取邮件列表，追加新邮件
    serverCloud:Get(PUBLIC_UID, cloudKey, {
        ok = function(scores)
            local pending = (scores and scores[cloudKey]) or {}
            if type(pending) ~= "table" then pending = {} end

            -- 追加新邮件
            pending[#pending + 1] = mailEntry

            -- 写回 cloud
            local commit = serverCloud:BatchCommit("gm_mail_" .. tostring(targetUid))
            commit:ScoreSet(PUBLIC_UID, cloudKey, pending)
            commit:Commit({
                ok = function()
                    print("[CrossInstanceService] SendMail CLOUD targetUid=" .. tostring(targetUid)
                        .. " pending count=" .. #pending)
                end,
                error = function(code, reason)
                    print("[CrossInstanceService][ERROR] SendMail cloud write failed targetUid="
                        .. tostring(targetUid) .. " code=" .. tostring(code)
                        .. " reason=" .. tostring(reason))
                end,
            })
        end,
        error = function(code, reason)
            -- 读取失败时尝试直接写入（覆盖，可能丢失旧邮件但不阻塞操作）
            print("[CrossInstanceService][WARN] read pending failed, writing fresh list")
            local pending = { mailEntry }
            local commit = serverCloud:BatchCommit("gm_mail_fresh_" .. tostring(targetUid))
            commit:ScoreSet(PUBLIC_UID, cloudKey, pending)
            commit:Commit({
                ok = function()
                    print("[CrossInstanceService] SendMail CLOUD(fresh) targetUid=" .. tostring(targetUid))
                end,
                error = function(code2, reason2)
                    print("[CrossInstanceService][ERROR] SendMail cloud write(fresh) failed code=" .. tostring(code2))
                end,
            })
        end,
    })

    -- 异步写入，对调用方返回"已排队"
    return true, nil, { delivered = "cloud_queued", targetUid = targetUid }
end

-- ======================== 登录时拉取待领取邮件 ========================

--- 玩家登录后调用：检查 serverCloud 是否有待领取的 GM 邮件
--- 如果有，合并到玩家 inbox 并清空 cloud 暂存
---@param uid number
---@param callback fun(count: number)|nil 拉取完成回调，count 为合并的邮件数
function CrossInstanceService.FetchPendingMails(uid, callback)
    local cloudKey = PENDING_MAIL_PREFIX .. tostring(uid)

    serverCloud:Get(PUBLIC_UID, cloudKey, {
        ok = function(scores)
            local pending = scores and scores[cloudKey]
            if not pending or type(pending) ~= "table" or #pending == 0 then
                if callback then callback(0) end
                return
            end

            -- 合并到玩家 inbox
            local MailService = require("server.mail.MailService")
            local count = 0
            local keptPending = {}
            for _, mail in ipairs(pending) do
                if shouldKeepPendingForNonChallengerServer(uid, mail) then
                    keptPending[#keptPending + 1] = mail
                    print("[CrossInstanceService] FetchPendingMails keep compensation pending for non-challenger uid=" .. tostring(uid)
                        .. " title=" .. tostring(mail.title))
                else
                    local dmId = MailService.SendDynamicMail(uid, {
                        title   = mail.title,
                        body    = mail.body or "",
                        rewards = mail.rewards or {},
                        source  = mail.source or "gm_console",
                        excludeChallenger = mail.excludeChallenger,
                    })
                    if dmId then
                        count = count + 1
                    end
                end
            end

            -- 清空已投递邮件，保留挑战者服不可领取的补偿邮件
            local commit = serverCloud:BatchCommit("gm_mail_clear_" .. tostring(uid))
            commit:ScoreSet(PUBLIC_UID, cloudKey, keptPending)
            commit:Commit({
                ok = function()
                    print("[CrossInstanceService] FetchPendingMails uid=" .. tostring(uid)
                        .. " merged=" .. count .. " kept=" .. #keptPending)
                end,
                error = function(code, reason)
                    print("[CrossInstanceService][WARN] clear pending failed uid=" .. tostring(uid)
                        .. " code=" .. tostring(code))
                end,
            })

            if callback then callback(count) end
        end,
        error = function(code, reason)
            print("[CrossInstanceService][WARN] FetchPendingMails read failed uid=" .. tostring(uid)
                .. " code=" .. tostring(code))
            if callback then callback(0) end
        end,
    })
end

-- ======================== 在线玩家定期轮询待投递邮件 ========================

--- 轮询间隔（秒）：每隔此时间为本实例所有在线玩家检查一次 pending mails
local POLL_PENDING_INTERVAL = 15

--- 上次轮询时间
local lastPollPendingTime_ = 0

--- 当前正在轮询中（防止并发）
local isPollingSinceLock_ = false

--- 为本实例所有在线玩家检查并投递 pending mails（由 Tick 驱动）
--- 拉取成功后直接推送邮件列表给客户端，玩家无需重新登录
function CrossInstanceService.PollPendingForOnlinePlayers()
    if isPollingSinceLock_ then return end

    local Server = require("network.Server")
    local onlineUIDs = Server.GetOnlineUIDs()
    if #onlineUIDs == 0 then return end

    isPollingSinceLock_ = true

    -- 逐个拉取（避免大批量并发请求撑满 serverCloud 配额）
    local idx = 0
    local function pollNext()
        idx = idx + 1
        if idx > #onlineUIDs then
            isPollingSinceLock_ = false
            return
        end

        local uid = onlineUIDs[idx]
        local cloudKey = PENDING_MAIL_PREFIX .. tostring(uid)

        serverCloud:Get(PUBLIC_UID, cloudKey, {
            ok = function(scores)
                local pending = scores and scores[cloudKey]
                if not pending or type(pending) ~= "table" or #pending == 0 then
                    -- 无待投递邮件，继续下一个
                    pollNext()
                    return
                end

                -- 有邮件！合并到 inbox 并推送
                local MailService = require("server.mail.MailService")
                local MailHandler = require("server.mail.MailHandler")
                local ServerDispatcher = require("network.ServerDispatcher")
                local Protocol = require("shared.Protocol")
                local count = 0
                local keptPending = {}
                for _, mail in ipairs(pending) do
                    if shouldKeepPendingForNonChallengerServer(uid, mail) then
                        keptPending[#keptPending + 1] = mail
                        print("[CrossInstanceService] PollPending keep compensation pending for non-challenger uid=" .. tostring(uid)
                            .. " title=" .. tostring(mail.title))
                    else
                        local dmId = MailService.SendDynamicMail(uid, {
                            title   = mail.title,
                            body    = mail.body or "",
                            rewards = mail.rewards or {},
                            source  = mail.source or "gm_console",
                            excludeChallenger = mail.excludeChallenger,
                        })
                        if dmId then
                            count = count + 1
                        end
                    end
                end

                -- 清空已投递邮件，保留挑战者服不可领取的补偿邮件
                local commit = serverCloud:BatchCommit("gm_mail_poll_" .. tostring(uid))
                commit:ScoreSet(PUBLIC_UID, cloudKey, keptPending)
                commit:Commit({
                    ok = function()
                        print("[CrossInstanceService] PollPending uid=" .. tostring(uid)
                            .. " merged=" .. count .. " kept=" .. #keptPending)
                    end,
                    error = function(code, reason)
                        print("[CrossInstanceService][WARN] PollPending clear failed uid="
                            .. tostring(uid) .. " code=" .. tostring(code))
                    end,
                })

                -- 推送更新后的邮件列表给客户端（实时收件）
                if count > 0 and Server.IsPlayerOnline(uid) then
                    local mailList = MailHandler.buildMailList(uid)
                    ServerDispatcher.sendEvent(uid, Protocol.RES_ACTION_RESULT, {
                        success  = true,
                        mailPush = true,
                        mails    = mailList,
                    })
                    print("[CrossInstanceService] Pushed mail update to uid=" .. tostring(uid))
                end

                pollNext()
            end,
            error = function(code, reason)
                -- 单个玩家失败不阻塞其他
                print("[CrossInstanceService][WARN] PollPending read failed uid="
                    .. tostring(uid) .. " code=" .. tostring(code))
                pollNext()
            end,
        })
    end

    pollNext()
end

-- ======================== 定时心跳（由 Update 驱动） ========================

--- 每帧调用（从 Server.lua 的 Update 事件中驱动）
--- 内部控制频率，只在间隔到达时执行上报 + 轮询待投递邮件
function CrossInstanceService.Tick()
    if not initialized_ then return end

    local now = os.time()

    -- 心跳上报
    if now - lastHeartbeatTime_ >= HEARTBEAT_INTERVAL then
        CrossInstanceService.HeartbeatUpload()
        CrossInstanceService.UpdateInstanceIndex()
    end

    -- 轮询在线玩家的待投递邮件（跨实例实时投递）

    -- 轮询远程修复命令（跨实例 GM 存档修复）
    if now - lastRepairPollTime_ >= REPAIR_POLL_INTERVAL then
        lastRepairPollTime_ = now
        CrossInstanceService.PollRemoteRepairs()
    end
    if now - lastPollPendingTime_ >= POLL_PENDING_INTERVAL then
        lastPollPendingTime_ = now
        CrossInstanceService.PollPendingForOnlinePlayers()
    end
end


-- ======================== 远程修复命令队列（跨实例 GM 存档修复） ========================

--- 将 GM 存档修复命令写入 serverCloud 队列，由目标玩家所在实例轮询执行
---@param targetUid number  目标玩家 UID
---@param dryRun boolean   true=仅诊断不修复
---@param operatorUid number  GM 操作者 UID（修复结果将邮件通知此人）
function CrossInstanceService.QueueRemoteRepair(targetUid, dryRun, operatorUid)
    if not targetUid then return false, "缺少 targetUid" end
    local cloudKey = PENDING_REPAIR_PREFIX .. tostring(targetUid)
    local repairEntry = {
        targetUid    = targetUid,
        dryRun       = dryRun and true or false,
        operatorUid  = operatorUid,
        queuedAt     = os.time(),
    }
    local commit = serverCloud:BatchCommit("gm_repair_" .. tostring(targetUid))
    commit:ScoreSet(PUBLIC_UID, cloudKey, repairEntry)
    commit:Commit({
        ok = function()
            print("[CrossInstanceService] QueueRemoteRepair targetUid=" .. tostring(targetUid)
                .. " dryRun=" .. tostring(dryRun) .. " operator=" .. tostring(operatorUid))
        end,
        error = function(code, reason)
            print("[CrossInstanceService][ERROR] QueueRemoteRepair write failed code=" .. tostring(code))
        end,
    })
    return true, nil, { queued = true, targetUid = targetUid }
end

--- 轮询并执行发给本实例在线玩家的远程修复命令
function CrossInstanceService.PollRemoteRepairs()
    local Server = require("network.Server")
    local onlineUIDs = Server.GetOnlineUIDs()
    if #onlineUIDs == 0 then return end
    local idx = 0
    local function pollNext()
        idx = idx + 1
        if idx > #onlineUIDs then return end
        local targetUid = onlineUIDs[idx]
        if not PDM.IsLoaded(targetUid) then pollNext(); return end
        local cloudKey = PENDING_REPAIR_PREFIX .. tostring(targetUid)
        serverCloud:Get(PUBLIC_UID, cloudKey, {
            ok = function(scores)
                local entry = scores and scores[cloudKey]
                if type(entry) ~= "table" or not entry.targetUid then
                    pollNext(); return
                end
                local dryRun = entry.dryRun
                local operatorUid = entry.operatorUid
                print(string.format("[CrossInstanceService] PollRemoteRepairs EXEC targetUid=%s dryRun=%s",
                    tostring(targetUid), tostring(dryRun)))
                local GMService = require("server.gm.GMService")
                local ok, reason, report = GMService.RepairPlayerSave(targetUid, dryRun)
                -- 清除队列
                local commit = serverCloud:BatchCommit("gm_repair_clear_" .. tostring(targetUid))
                commit:ScoreSet(PUBLIC_UID, cloudKey, {})
                commit:Commit({ ok = function() end, error = function() end })
                -- 邮件通知操作 GM
                if operatorUid and operatorUid > 0 then
                    local mailTitle = "存档修复" .. (dryRun and "诊断" or "执行") .. "结果 - UID:" .. tostring(targetUid)
                    local mailBody = (report and report.repairReason or reason or "未知")
                    if report and report.repairExecuted then
                        mailBody = mailBody .. " | 恢复英雄数:" .. tostring(report.repairedRosterCount or "?")
                    end
                    CrossInstanceService.SendMailCrossInstance(operatorUid, mailTitle, mailBody, nil)
                end
                pollNext()
            end,
            error = function(code, reason)
                print("[CrossInstanceService][WARN] PollRemoteRepairs read failed uid="
                    .. tostring(targetUid) .. " code=" .. tostring(code))
                pollNext()
            end,
        })
    end
    pollNext()
end
return CrossInstanceService
