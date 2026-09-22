-- ============================================================================
-- ServerEnterGame - loadAndPushFullState（从 Server.lua 抽出）
-- Bound via M.bind(deps)
-- ============================================================================

local Protocol         = require("shared.Protocol")
local ServerListConfig = require("shared.ServerListConfig")
local SaveManager      = require("server.SaveManager")
local ServerDispatcher = require("network.ServerDispatcher")
local PDM              = require("server.character.PlayerDataManager")
local MarketService    = require("server.market.MarketService")
local TavernService    = require("server.gacha.TavernService")
local EquipLevelCompat = require("server.equipment.EquipLevelCompat")

local M = {}

function M.bind(deps)
    local connections = deps.connections
    local sessions = deps.sessions
    local phase2Loading = deps.phase2Loading
    local sendServerDiag = deps.sendServerDiag
    local getServerDictValue = deps.getServerDictValue
    local setServerDictValue = deps.setServerDictValue
    local hasRealServerProgress = deps.hasRealServerProgress
    local countHeroesRoster = deps.countHeroesRoster
    local collectRecoverableHeroIds = deps.collectRecoverableHeroIds
    local updateServerProgress = deps.updateServerProgress
    local MailService = deps.MailService
    local SignInService = deps.SignInService
    local ChallengerService = deps.ChallengerService
    local BattleService = deps.BattleService
    local OfflineService = deps.OfflineService
    local DungeonIdleService = deps.DungeonIdleService
    local TaskService = deps.TaskService
    local CrossInstanceService = deps.CrossInstanceService
    local MailHandler = deps.MailHandler
    local AnnouncementConfig = deps.AnnouncementConfig

    local function loadAndPushFullState(uid)
    local TAG = "[Server][DIAG-RESET]"
    local sid = SaveManager.getServerId(uid)
    phase2Loading[uid] = sid
    sendServerDiag(uid, "Phase2 START serverId=" .. tostring(sid))
    print(string.format("%s Phase2 START uid=%s serverId=%s clock=%.4f", TAG, tostring(uid), tostring(sid), os.clock()))

    SaveManager.load(uid, function(success)
        sendServerDiag(uid, "Phase2 SaveManager.load DONE success=" .. tostring(success))
        print(string.format("%s Phase2 SaveManager.load DONE uid=%s success=%s clock=%.4f", TAG, tostring(uid), tostring(success), os.clock()))
        -- 检查玩家是否仍在线
        if not connections[uid] then
            phase2Loading[uid] = nil
            return
        end

        if not success then
            phase2Loading[uid] = nil
            -- 加载失败：通知客户端
            print(string.format("[Server] loadAndPushFullState SM load FAILED uid=%s", tostring(uid)))
            local GMHandler = require("server.gm.GMHandler")
            ServerDispatcher.sendEvent(uid, Protocol.RES_SAVE_RESULT, {
                status = Protocol.SAVE_STATUS_FAILED,
                tips   = "存档加载失败，请重试",
                gm     = GMHandler.IsGM(uid) or nil,
            })
            return
        end

        -- SaveManager 加载成功 → 继续加载 PDM 区服数据
        PDM.LoadPlayer(uid, function(pdmOk)
            sendServerDiag(uid, "Phase2 PDM.LoadPlayer DONE success=" .. tostring(pdmOk))
            print(string.format("%s Phase2 PDM.LoadPlayer DONE uid=%s success=%s clock=%.4f", TAG, tostring(uid), tostring(pdmOk), os.clock()))
            -- 检查玩家是否仍在线
            if not connections[uid] then
                phase2Loading[uid] = nil
                return
            end

            if not pdmOk then
                phase2Loading[uid] = nil
                print(string.format("[Server] loadAndPushFullState PDM load FAILED uid=%s", tostring(uid)))
                local GMHandler = require("server.gm.GMHandler")
                ServerDispatcher.sendEvent(uid, Protocol.RES_SAVE_RESULT, {
                    status = Protocol.SAVE_STATUS_FAILED,
                    tips   = "数据加载失败，请重试",
                    gm     = GMHandler.IsGM(uid) or nil,
                })
                return
            end

            -- 将平台昵称写入 player 表（供竞技场排行榜等模块使用）
            -- 仅通过 PDM 写入，避免双写导致断线时 SaveManager 覆盖 PDM 数据
            local session = sessions[uid]
            if session and session.nickname and session.nickname ~= "" then
                local pdmPlayer = PDM.GetModule(uid, "player")
                if pdmPlayer and pdmPlayer.name ~= session.nickname then
                    pdmPlayer.name = session.nickname
                    PDM.MarkDirty(uid, "player")
                    print("[Server] loadAndPushFullState: name synced from session.nickname=" .. session.nickname)
                end
                -- 同步到 SaveManager 的内存副本（仅更新内存，不标脏，避免 cleanup 时覆盖 PDM）
                local playerData = SaveManager.getTable(uid, "player")
                if playerData then
                    playerData.name = pdmPlayer and pdmPlayer.name or session.nickname
                end
                -- 持久化昵称到 serverCloud（供排行榜离线玩家名字兜底）
                -- 使用独立 key "player_nickname"，不依赖排行榜 score 字段
                serverCloud:Set(uid, "player_nickname", session.nickname)
            else
                -- 🔴 竞态场景：GetUserNickname 回调尚未到达，session.nickname 为 nil
                -- 此时全量推送会携带 cloud 中的旧 player.name，
                -- 但无需阻塞——回调到达后 MarkDirty 会补推正确名字到客户端。
                -- 客户端 onPlayerDataUpdate 已修复为检查 data.name 字段（而非 data.nickname）。
                print("[Server] loadAndPushFullState: nickname not yet available, will be corrected by async callback. uid=" .. tostring(uid))
            end

            local currentServerId = SaveManager.getServerId(uid)
            if ServerListConfig.isChallengerServer(currentServerId) then
                ChallengerService.OnEnterServer(uid, currentServerId)
            end

            -- 合并 SaveManager + PDM 数据，推送全量
            local allData = SaveManager.getAllTables(uid)
            local pushData = {}
            if allData then
                for name, data in pairs(allData) do
                    if name ~= "_meta" then
                        pushData[name] = data
                    end
                end
            end

            -- 登录时装备等级兼容检查（旧版本高等级装备降级到当前关卡怪物等级）
            EquipLevelCompat.Check(uid)

            -- 副本层数回退迁移：首次执行后标脏存盘，避免 compat 未落库导致每次登录重复回退
            local dungeonData = PDM.GetModule(uid, "dungeon")
            if dungeonData and dungeonData._justMigratedMonsterBuffV1 then
                dungeonData._justMigratedMonsterBuffV1 = nil
                PDM.MarkDirty(uid, "dungeon")
                print("[Server] dungeon monsterBuffV1 migrated, marked dirty for persist uid=" .. tostring(uid))
            end

            -- 日/周任务奖励加强：清空本周期已领取标记后标脏存盘（进度保留，可立即重领新数额）
            local taskData = PDM.GetModule(uid, "task")
            if taskData and taskData._justMigratedTaskRewardBuffV1 then
                taskData._justMigratedTaskRewardBuffV1 = nil
                PDM.MarkDirty(uid, "task")
                print("[Server] task taskRewardBuffV1 migrated, marked dirty for persist uid=" .. tostring(uid))
            end

            -- 登录时重置过期的每日限购记录（pushFullState 前执行，确保客户端收到干净数据）
            MarketService.ResetDailyShopItems(uid)
            TavernService.ResetShopLimits(uid)

            -- 老玩家首通黄金钥匙补偿：全量推送前写入动态邮件，确保客户端登录后可见
            MailService.CheckAndSendGoldenKeyRetroCompensation(uid)

            -- 通天塔结算事故一次性补偿：当前层扫荡钻石×3，仅本次事故发放一次
            MailService.CheckAndSendTowerBugCompensation(uid)

            -- 签到奖励版本兼容：全量推送前刷新，旧玩家可重新领取/补签新版奖励
            SignInService.RefreshAndGet(uid)

            -- PDM 管理的模块覆盖到 pushData（PDM 为权威源）
            local pdmModules = PDM.GetAllModules(uid)
            local pdmModuleCount = 0
            if pdmModules then
                for fieldKey, data in pairs(pdmModules) do
                    if fieldKey ~= "_meta" then
                        pushData[fieldKey] = data
                        pdmModuleCount = pdmModuleCount + 1
                        -- 同步 PDM → SaveManager 内存副本（不写盘），避免 SM 滞后
                        if type(data) == "table" then
                            SaveManager.replaceModuleMemory(uid, fieldKey, data)
                        end
                    end
                end
            end
            -- PDM modules overlaid onto SM data

            -- 存档完整性保护：roster 为空时，按幸存证据恢复或阻断
            local serverId = SaveManager.getServerId(uid)
            local gp = PDM.GetModule(uid, "global_profile")
            local heroesData = pushData.heroes
            local rosterCount = countHeroesRoster(heroesData)
            local rosterEmpty = rosterCount <= 0
            local sp = (gp and gp.serverProgress and serverId) and getServerDictValue(gp.serverProgress, serverId) or nil
            local hasServerProgress = hasRealServerProgress(sp)
            local spDebugStr = sp and string.format("level=%s,stage=%s", tostring(sp.level), tostring(sp.stage)) or "nil"
            local playerData = pushData.player
            local equipData = pushData.equipment
            local playerLevel = playerData and (tonumber(playerData.level) or 1) or 1
            local equipNextSeq = equipData and (tonumber(equipData.nextSeq) or 1) or 1
            local hasSurvivorProgress = (playerLevel > 1) or (equipNextSeq > 1)

            print(string.format(
                "%s   SafetyNet INPUT: uid=%s serverId=%s rosterEmpty=%s rosterCount=%d " ..
                "hasServerProgress=%s sp=[%s] player.level=%s equip.nextSeq=%s justClearedSave=%s",
                TAG, tostring(uid), tostring(serverId),
                tostring(rosterEmpty), rosterCount,
                tostring(hasServerProgress), spDebugStr,
                tostring(playerLevel), tostring(equipNextSeq),
                tostring(sessions[uid] and sessions[uid].justClearedSave)))

            if rosterEmpty then
                local session = sessions[uid]
                local justCleared = session and session.justClearedSave

                if justCleared then
                    if gp and gp.serverProgress and serverId then
                        setServerDictValue(gp.serverProgress, serverId, nil)
                        PDM.MarkDirty(uid, "global_profile")
                    end
                    session.justClearedSave = nil
                    print(string.format("%s   SafetyNet BYPASS: justClearedSave consumed, serverProgress cleared", TAG))
                elseif hasSurvivorProgress then
                    local recoveredHeroIds, avatarHeroId = collectRecoverableHeroIds(playerData, equipData)
                    if not next(recoveredHeroIds) then
                        recoveredHeroIds[1] = true
                    end

                    local recoveredRoster = {}
                    local recoveredDeployed = {}
                    local heroLevel = math.max(1, playerLevel)
                    local first = true
                    for heroId, _ in pairs(recoveredHeroIds) do
                        recoveredRoster[heroId] = {
                            level = heroLevel,
                            exp = 0,
                            maxExp = 0,
                            classId = 1,
                            dupeCount = 0,
                            shards = 0,
                            _shardMigrated = true,
                            _recovered = true,
                        }
                        if first then
                            recoveredDeployed[1] = heroId
                            first = false
                        end
                    end

                    if not pushData.heroes then pushData.heroes = {} end
                    pushData.heroes.roster = recoveredRoster
                    pushData.heroes.deployed = recoveredDeployed
                    do
                        -- [三队并行] 恢复路径同样维护 teams 镜像
                        local TeamSlots = require("shared.heroes.TeamSlots")
                        TeamSlots.normalize(pushData.heroes)
                    end
                    heroesData = pushData.heroes
                    rosterCount = countHeroesRoster(heroesData)
                    rosterEmpty = rosterCount <= 0

                    local pdmHeroes = PDM.GetModule(uid, "heroes")
                    if pdmHeroes then
                        pdmHeroes.roster = recoveredRoster
                        pdmHeroes.deployed = recoveredDeployed
                        do
                            local TeamSlots = require("shared.heroes.TeamSlots")
                            TeamSlots.normalize(pdmHeroes)
                        end
                        PDM.MarkDirty(uid, "heroes")
                    end

                    if gp then
                        if not gp.serverProgress then gp.serverProgress = {} end
                        local progress = sp or { level = playerLevel, stage = "" }
                        if (tonumber(progress.level or 0) or 0) < playerLevel then
                            progress.level = playerLevel
                        end
                        setServerDictValue(gp.serverProgress, serverId, progress)
                        if not gp.servers then gp.servers = {} end
                        setServerDictValue(gp.servers, serverId, os.time())
                        PDM.MarkDirty(uid, "global_profile")
                    end

                    local heroIdList = {}
                    for hid, _ in pairs(recoveredHeroIds) do
                        heroIdList[#heroIdList + 1] = tostring(hid)
                    end
                    print(string.format(
                        "[Server][SAVE-RECOVER] uid=%s serverId=%s heroIds=[%s] level=%d " ..
                        "playerLevel=%d equipNextSeq=%d avatarHeroId=%s sp=[%s]",
                        tostring(uid), tostring(serverId), table.concat(heroIdList, ","), heroLevel,
                        playerLevel, equipNextSeq, tostring(avatarHeroId), spDebugStr))

                    PDM.FlushImmediate(uid)
                elseif hasServerProgress then
                    phase2Loading[uid] = nil
                    print(string.format(
                        "[Server][SAVE-BROKEN] BLOCK uid=%s serverId=%s roster=0 playerLevel=%s equipNextSeq=%s sp=[%s]",
                        tostring(uid), tostring(serverId), tostring(playerLevel), tostring(equipNextSeq), spDebugStr))
                    local GMHandler = require("server.gm.GMHandler")
                    ServerDispatcher.sendEvent(uid, Protocol.RES_SAVE_RESULT, {
                        status = Protocol.SAVE_STATUS_FAILED,
                        tips   = "存档数据异常，请联系客服恢复",
                        gm     = GMHandler.IsGM(uid) or nil,
                        _diag  = string.format("brokenSave sid=%s plv=%s eq=%s sp=%s",
                            tostring(serverId), tostring(playerLevel), tostring(equipNextSeq), spDebugStr),
                    })
                    return
                else
                    print(string.format("[Server][SAVE-NEW] uid=%s serverId=%s true new player", tostring(uid), tostring(serverId)))
                end
            end

            -- 监控推送数据大小（SetVar 单帧 64KB 限制）
            local encodeOk, encoded = pcall(cjson.encode, pushData)
            if encodeOk and encoded then
                local dataSize = #encoded
                if dataSize > 50000 then
                    print("[Server] WARNING: pushFullState size=" .. dataSize
                        .. " bytes uid=" .. tostring(uid) .. " (approaching 64KB limit)")
                end
            end

            sendServerDiag(uid, "Phase2 pushFullState START modules=" .. tostring(pdmModuleCount)
                .. " encodedSize=" .. tostring(encodeOk and #encoded or -1))
            ServerDispatcher.pushFullState(uid, pushData)
            sendServerDiag(uid, "Phase2 pushFullState DONE")

            -- 将当前区服进度摘要写入 global_profile（供选服列表展示）
            -- 此时 PDM 刚加载完毕，数据与 SaveManager 一致，updateServerProgress 均可正确读取
            updateServerProgress(uid)

            -- 通知客户端存档加载成功
            -- GM 标记：仅白名单玩家收到 gm=true，客户端据此显示 GM 入口
            -- _diag: 服务端诊断中继，客户端打印到设备日志供反馈系统收集
            local GMHandler = require("server.gm.GMHandler")

            local diagRosterCount = 0
            if pushData.heroes and pushData.heroes.roster then
                for _ in pairs(pushData.heroes.roster) do diagRosterCount = diagRosterCount + 1 end
            end
            local diagSpLevel = 0
            local diagSpStage = ""
            if gp and gp.serverProgress and serverId then
                local sp = getServerDictValue(gp.serverProgress, serverId)
                if sp then
                    diagSpLevel = sp.level or 0
                    diagSpStage = sp.stage or ""
                end
            end
            local gmFlag = GMHandler.IsGM(uid) or nil
            phase2Loading[uid] = nil
            ServerDispatcher.sendEvent(uid, Protocol.RES_SAVE_RESULT, {
                status = Protocol.SAVE_STATUS_SUCCESS,
                tips   = "",
                gm     = gmFlag,
                _diag  = string.format("rc=%d,spLv=%s,spSt=%s,sz=%s,sid=%s,GM=%s,uidT=%s",
                    diagRosterCount,
                    tostring(diagSpLevel),
                    tostring(diagSpStage),
                    encodeOk and tostring(#encoded) or "?",
                    tostring(serverId),
                    tostring(gmFlag),
                    type(uid)),
            })
            print(string.format("%s Phase2 RES_SAVE_RESULT sent uid=%s serverId=%s modules=%d clock=%.4f",
                TAG, tostring(uid), tostring(serverId), pdmModuleCount, os.clock()))
            sendServerDiag(uid, "Phase2 RES_SAVE_RESULT sent")

            -- 标记已进入游戏
            if sessions[uid] then
                sessions[uid].isInGame = true
            end

            -- 断线后 battleMode 可能仍为 offline（持久化），需恢复才能触发在线挂机结算
            BattleService.RestoreBattleModeFromOffline(uid)

            -- 计算离线收益（在全量数据推送之后）
            -- 🔴 防竞态：清档(handleNewGame)后重新进入时，异步提交可能尚未落盘，
            -- 导致 PDM.LoadPlayer 从云端读到旧 session（lastOnlineTime > 0）。
            -- 此处用 roster 为空作为"新玩家/刚清档"的交叉验证——
            -- 没有英雄阵容的玩家不可能产生有意义的离线收益。
            if not rosterEmpty then
                local offlineData = OfflineService.CalcOnEnter(uid)
                if offlineData then
                    ServerDispatcher.sendEvent(uid, Protocol.RES_OFFLINE_REWARD, offlineData)
                end
                DungeonIdleService.SyncOfflineOnEnter(uid)
            else
                -- 新玩家/清档后：确保 session.lastOnlineTime 被正确初始化
                local sessionData = PDM.GetModule(uid, "session")
                if sessionData then
                    local now = os.time()
                    if (sessionData.firstLoginTime or 0) <= 0 then
                        sessionData.firstLoginTime = now
                        PDM.MarkDirty(uid, "session")
                    end
                    if (sessionData.lastOnlineTime or 0) > 0 then
                        -- 竞态残留：session 读到旧值，强制重置
                        print(string.format(
                            "[Server][FIX] rosterEmpty but lastOnlineTime=%d — stale session detected, resetting. uid=%s",
                            sessionData.lastOnlineTime, tostring(uid)))
                        sessionData.lastOnlineTime = now
                        PDM.MarkDirty(uid, "session")
                    else
                        sessionData.lastOnlineTime = now
                        PDM.MarkDirty(uid, "session")
                    end
                end
            end

            TaskService.OnPlayerEnter(uid)
            -- 同步公会排行榜分数（修正 avatarHeroId 编码变更导致的过时 cloud score）
            BattleService.SyncGuildRankOnLogin(uid)

            -- 拉取跨实例待投递邮件（其他实例 GM 发送的离线邮件）
            CrossInstanceService.FetchPendingMails(uid, function()
                ChallengerService.ProcessLoginRewards(uid)
                -- 推送邮件列表（合并配置 + 玩家已领取/已删除状态）
                local mailList = MailHandler.buildMailList(uid)
                print("[Server][DEBUG-MAIL] uid=" .. tostring(uid)
                    .. " mailList count=" .. tostring(mailList and #mailList or "NIL")
                    .. " type=" .. type(mailList))
                ServerDispatcher.sendEvent(uid, Protocol.RES_ACTION_RESULT, {
                    success    = true,
                    mailPush   = true,
                    mails      = mailList,
                })

                -- 推送公告列表（基于开服时间计算日期）
                local serverId = SaveManager.getServerId(uid)
                local srvCfg = ServerListConfig.find(serverId)
                local openTime = (srvCfg and srvCfg.openTime) or 0
                local annList = AnnouncementConfig.buildWithDates(openTime)
                print("[Server][DEBUG-ANN] uid=" .. tostring(uid)
                    .. " serverId=" .. tostring(serverId)
                    .. " openTime=" .. tostring(openTime)
                    .. " announcements count=" .. tostring(annList and #annList or "NIL"))
                ServerDispatcher.sendEvent(uid, Protocol.RES_ACTION_RESULT, {
                    success          = true,
                    announcementPush = true,
                    announcements    = annList,
                })

                print("[Server] player entered game uid=" .. tostring(uid))
            end)  -- CrossInstanceService.FetchPendingMails callback
        end)
    end)
    end


    return { loadAndPushFullState = loadAndPushFullState }
end

return M
