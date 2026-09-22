-- ============================================================================
-- Server.lua - 服务端主控（常驻服架构 persistent_world）
-- 数据持久化: serverCloud（SaveManager），不是 clientCloud 云存档
-- 职责: Headless Mock、连接管理、守卫链、请求路由、进入游戏流程
-- 运行端: 仅服务端（IsServerMode() == true）
-- ============================================================================

-- ======================== Headless Mock（必须在所有 require 之前） ========================
if GetGraphics() == nil then
    local mockGraphics = {
        SetWindowIcon = function() end,
        GetWidth  = function() return 1920 end,
        GetHeight = function() return 1080 end,
        GetDPR    = function() return 1.0 end,
    }
    function GetGraphics() return mockGraphics end
    graphics = mockGraphics
    console = { background = {} }
    function GetConsole() return console end
    debugHud = {}
    function GetDebugHud() return debugHud end
end

-- ======================== 依赖 ========================

local Protocol         = require("shared.Protocol")
local ModuleRegistry   = require("shared.ModuleRegistry")
local ServerListConfig = require("shared.ServerListConfig")
local ChallengerServerConfig = require("shared.ChallengerServerConfig")
local StageConfig      = require("config.StageConfig")
local StageProvider    = require("shared.StageProvider")
local SaveManager      = require("server.SaveManager")
local ServerDispatcher = require("network.ServerDispatcher")
local PDM              = require("server.character.PlayerDataManager")
local MarketService    = require("server.market.MarketService")
local TavernService    = require("server.gacha.TavernService")
local EquipLevelCompat = require("server.equipment.EquipLevelCompat")
local GameAlgoProxy    = require("server.gamealgo.GameAlgoProxy")
local ServerEnterGame  = require("network.ServerEnterGame")

local Server = {}

-- ======================== 内部状态 ========================

--- 连接映射  connections[uid] = connection
local connections = {}

--- 会话信息  sessions[uid] = { connection, isInGame, disconnectTime, ... }
local sessions = {}

--- 断线保留时长（秒）
local DISCONNECT_KEEP_SECONDS = 300  -- 5 分钟

--- 场景引用
---@type Scene
local scene_ = nil

--- 服务器启动时间戳
local serverStartTime = 0

--- 维护模式标志
local maintenanceMode = false

local function sendServerDiag(uid, message)
    ServerDispatcher.sendEvent(uid, Protocol.RES_ACTION_RESULT, {
        action = "server_diag",
        success = true,
        message = tostring(message),
    })
end

--- 延迟断开队列 { uid → expireTime }
local scheduledDisconnects = {}

--- Phase2 选服读档防重入：phase2Loading[uid] = serverId
local phase2Loading = {}

-- ======================== Handler 路由表 ========================

--- action → handler 映射
--- 每个 handler 签名: function(uid, params) → { success, reason? }
local actionHandlers = {}

--- 玩家清理时的回调列表（handler 模块可通过 __cleanup 键注册）
local playerCleanupHooks = {}

--- 注册一组 handler 到路由表
--- 特殊键 "__cleanup" 会被注册为玩家清理回调，不进入 actionHandlers
---@param handlers table<string, function>  action → handler 映射表
local function registerHandlers(handlers)
    for action, fn in pairs(handlers) do
        if action == "__cleanup" then
            playerCleanupHooks[#playerCleanupHooks + 1] = fn
        elseif action == Protocol.ACTION_TYPES.TRANSFER_CLOSED_CHALLENGER_CARD then
            -- 结束挑战者区转出由选服阶段全局路由处理，不能进入普通区服 action 路由。
        else
            if actionHandlers[action] then
                print("[Server] WARNING: overriding handler for action=" .. tostring(action))
            end
            actionHandlers[action] = fn
        end
    end
end

-- 注册所有业务 handler 模块（均已迁移为三层 Handler+Service）
-- ── 导出 .actionHandlers 的模块 ──
registerHandlers(require("server.battle.BattleHandler").actionHandlers)
registerHandlers(require("server.hero.HeroHandler").actionHandlers)
registerHandlers(require("server.gacha.GachaHandler").actionHandlers)
registerHandlers(require("server.equipment.EquipmentHandler").actionHandlers)
registerHandlers(require("server.blacksmith.BlacksmithHandler").actionHandlers)
registerHandlers(require("server.task.TaskHandler").actionHandlers)
registerHandlers(require("server.mail.MailHandler").actionHandlers)
-- ── 直接导出 handlers table 的模块 ──
registerHandlers(require("server.redeem.RedeemHandler"))
registerHandlers(require("server.awakening.AwakeningHandler"))
registerHandlers(require("server.advancement.AdvancementHandler"))
registerHandlers(require("server.talent.TalentHandler"))
registerHandlers(require("server.signin.SignInHandler"))
registerHandlers(require("server.gm.GMHandler").actionHandlers)
---@type table<string, function>
local MarketHandlers = require("server.market.MarketHandler")
registerHandlers(MarketHandlers)
registerHandlers(require("server.loot.LootHandler"))
registerHandlers(require("server.guild.GuildHandler").actionHandlers)
registerHandlers(require("server.sweep.SweepHandler").actionHandlers)
registerHandlers(require("server.relic.RelicHandler").actionHandlers)
registerHandlers(require("server.artifact.ArtifactHandler").actionHandlers)
registerHandlers(require("server.dungeon.DungeonHandler").actionHandlers)
do
    local ok, TowerHandler = pcall(require, "server.tower.TowerHandler")
    if ok and TowerHandler and TowerHandler.actionHandlers then
        registerHandlers(TowerHandler.actionHandlers)
    else
        print("[Server][ERROR] TowerHandler load failed: " .. tostring(TowerHandler))
    end
end

local TaskService            = require("server.task.TaskService")
local BattleService          = require("server.battle.BattleService")
local MailHandler            = require("server.mail.MailHandler")
local MailService            = require("server.mail.MailService")
local SignInService          = require("server.signin.SignInService")
local AnnouncementConfig     = require("shared.AnnouncementConfig")
local OfflineService         = require("server.offline.OfflineService")
local IdleSettleService      = require("server.offline.IdleSettleService")
local DungeonIdleService     = require("server.dungeon.DungeonIdleService")
local CrossInstanceService   = require("server.gm.CrossInstanceService")
local ChallengerService      = require("server.challenger.ChallengerService")
registerHandlers(require("server.offline.OfflineHandler").actionHandlers)

-- ======================== 区服进度摘要更新 ========================

local function getServerDictValue(t, serverId)
    if type(t) ~= "table" then return nil end
    return t[tostring(serverId)] or t[serverId]
end

local function setServerDictValue(t, serverId, value)
    if type(t) ~= "table" then return end
    t[tostring(serverId)] = value
    t[serverId] = nil
end

local function hasRealServerProgress(progress)
    if type(progress) ~= "table" then return false end
    local level = tonumber(progress.level or 0) or 0
    local stage = progress.stage or ""
    return level > 1 or stage ~= ""
end

local function attachServerListMeta(entry, cfg)
    entry.kind = ServerListConfig.getServerKind(cfg.id)
    local closeTime = cfg.closeTime
    if ServerListConfig.isChallengerServer(cfg.id) then
        local challengerCfg = ChallengerServerConfig.GetByServerId(cfg.id)
        if challengerCfg then
            closeTime = challengerCfg.closeTime
        end
    end
    entry.closeTime = closeTime
    entry.status = ServerListConfig.getStatus(cfg.id)
    entry.closed = ServerListConfig.isServerClosed(cfg.id)
    if ServerListConfig.isChallengerServer(cfg.id) then
        entry.stageConfigReady = StageProvider.IsAvailableForServer(cfg.id)
    end
    return entry
end

local function countHeroesRoster(heroesData)
    local count = 0
    if heroesData and type(heroesData.roster) == "table" then
        for _ in pairs(heroesData.roster) do
            count = count + 1
        end
    end
    return count
end

local function collectRecoverableHeroIds(playerData, equipData)
    local recovered = {}
    local avatarHeroId = playerData and tonumber(playerData.avatarHeroId)
    if avatarHeroId and avatarHeroId > 0 then
        recovered[avatarHeroId] = true
    end
    if equipData and type(equipData.equipped) == "table" then
        for heroIdKey, _ in pairs(equipData.equipped) do
            local hid = tonumber(heroIdKey)
            if hid and hid > 0 then
                recovered[hid] = true
            end
        end
    end
    return recovered, avatarHeroId
end

--- 构建关卡展示名（含难度前缀）
---@param stageId number
---@return string
local function buildStageDisplayName(stageId, serverId)
    if ServerListConfig.isChallengerServer(serverId) then
        local StageProvider = require("shared.StageProvider")
        local stageConfig = StageProvider.GetForServer(serverId)
        local entry = stageConfig.getStage(stageId)
        return (entry and entry.name) or ""
    end
    local entry = StageConfig.getStage(stageId)
    if not entry then return "" end
    return entry.name
end

--- 将当前游戏进度写入 global_profile.serverProgress（供选服列表展示）
--- 优先读取 PDM（权威源），回退到 SaveManager（进服时加载的副本）
---@param uid number
local function updateServerProgress(uid)
    local serverId = SaveManager.getServerId(uid)
    if not serverId then return end

    -- 🔴 必须写入 PDM 的副本！SaveManager 的 global_profile 不会被持久化
    -- （isPdmManagedKey 防护会跳过 SaveManager 对 global_profile 的写入）
    local gp = PDM.GetModule(uid, "global_profile")
    if not gp then return end
    if not gp.serverProgress then gp.serverProgress = {} end

    -- 优先从 PDM 读取（游戏中 PDM 是权威源），回退到 SaveManager
    local playerData = PDM.GetModule(uid, "player") or SaveManager.getTable(uid, "player")
    local battleData = PDM.GetModule(uid, "battle") or SaveManager.getTable(uid, "battle")
    local heroesData = PDM.GetModule(uid, "heroes") or SaveManager.getTable(uid, "heroes")

    -- 🔴 铁律 #18 修复：roster 为空时说明是重置后的默认数据，
    -- 此时 battle.currentStageId 是初始默认值（"s101"），不代表真实游戏进度。
    -- 写入非空 stage 会导致 HeroService PRIMARY 安全网误判为"有进度但无英雄"并阻止选角。
    local rosterCount = 0
    if heroesData and heroesData.roster then
        for _ in pairs(heroesData.roster) do
            rosterCount = rosterCount + 1
            break  -- 只需知道是否 > 0
        end
    end

    local lvl = playerData and playerData.level or 1
    local stageName = ""
    if rosterCount > 0 and battleData and battleData.currentStageId then
        -- 只有在玩家确实有英雄时才写入 stage（此时 stage 代表真实进度）
        stageName = buildStageDisplayName(battleData.currentStageId, serverId)
    end

    -- 🔴 铁律 #18 修复：serverProgress 只允许升级不允许降级
    -- 如果当前 level 比已记录的低，说明当前内存数据可能因丢档而不可信，
    -- 禁止覆盖以保护安全网（防止 updateServerProgress 自毁防丢档检查）
    local serverKey = tostring(serverId)
    local existing = getServerDictValue(gp.serverProgress, serverId)

    if existing and existing.level and existing.level > lvl then
        print(string.format(
            "[Server][WARN] updateServerProgress BLOCKED downgrade uid=%s serverId=%s " ..
            "existing.level=%d > current.level=%d — refusing to overwrite (possible data loss state)",
            tostring(uid), tostring(serverId), existing.level, lvl))
        return
    end

    setServerDictValue(gp.serverProgress, serverId, {
        level = lvl,
        stage = stageName,
    })
    PDM.MarkDirty(uid, "global_profile")

    -- 同步到 SaveManager 的内存副本（供当前会话的 loadGlobalAndPushServerList 读取）
    local smGp = SaveManager.getTable(uid, "global_profile")
    if smGp then
        if not smGp.serverProgress then smGp.serverProgress = {} end
        setServerDictValue(smGp.serverProgress, serverId, {
            level = lvl,
            stage = stageName,
        })
    end
end

local _enterGame
local function bindEnterGame()
    _enterGame = ServerEnterGame.bind({
        connections = connections,
        sessions = sessions,
        phase2Loading = phase2Loading,
        sendServerDiag = sendServerDiag,
        getServerDictValue = getServerDictValue,
        setServerDictValue = setServerDictValue,
        hasRealServerProgress = hasRealServerProgress,
        countHeroesRoster = countHeroesRoster,
        collectRecoverableHeroIds = collectRecoverableHeroIds,
        updateServerProgress = updateServerProgress,
        MailService = MailService,
        SignInService = SignInService,
        ChallengerService = ChallengerService,
        BattleService = BattleService,
        OfflineService = OfflineService,
        DungeonIdleService = DungeonIdleService,
        TaskService = TaskService,
        CrossInstanceService = CrossInstanceService,
        MailHandler = MailHandler,
        AnnouncementConfig = AnnouncementConfig,
    })
end
bindEnterGame()
local function loadAndPushFullState(uid)
    return _enterGame.loadAndPushFullState(uid)
end

-- ======================== 玩家清理（统一入口） ========================

--- 清理玩家数据：先执行 handler 注册的清理回调，再清理 PDM + SaveManager
--- 铁律：先存后清（SaveAll → Dispose，反了 = 回档）
---@param uid number
local function cleanupPlayer(uid)
    phase2Loading[uid] = nil

    for i, hook in ipairs(playerCleanupHooks) do
        local ok, err = pcall(hook, uid)
        if not ok then
            print(string.format("[Server] cleanupPlayer hook[%d] ERROR uid=%s err=%s", i, tostring(uid), tostring(err)))
        end
    end

    PDM.RemovePlayer(uid)       -- PDM: 先存后清（内部已实现 save-then-clear）
    SaveManager.cleanup(uid)
end

-- ======================== 守卫链 ========================

--- 连接 → UID 映射（在 ClientIdentity 事件中填充）
local connToUID = {}

--- 从 connection 获取 UID（通过本地映射表，不依赖 identity）
---@param connection userdata
---@return number|nil
local function getUID(connection)
    if not connection then return nil end
    return connToUID[connection]
end

--- 向客户端发送操作结果
---@param uid number
---@param result table
local function sendActionResult(uid, result)
    ServerDispatcher.sendEvent(uid, Protocol.RES_ACTION_RESULT, result)
end

-- 前向声明（定义在"选服流程"区域）
local handleSelectServer
local returnPlayerToServerSelect

--- 选服阶段允许处理的全局业务请求（当前没有区服模块时使用）
local function handleGlobalAction(uid, action, params)
    if action ~= Protocol.ACTION_TYPES.TRANSFER_CLOSED_CHALLENGER_CARD then
        return false
    end

    local handler = require("server.market.MarketHandler")[Protocol.ACTION_TYPES.TRANSFER_CLOSED_CHALLENGER_CARD]
    handler(uid, params, function(result)
        sendActionResult(uid, result)
        if result.success and returnPlayerToServerSelect then
            -- 转出完成后刷新全局区服列表，玩家可以选择普通区服接收特权卡。
            returnPlayerToServerSelect(uid)
        end
    end)
    return true
end

-- 🔧 关键战斗消息豁免限频：这些是连续通关的正常流量，
-- 限频会导致 firstClear 消息被丢弃 → 服务端状态脱节 → 后续全部请求连锁失败（P0 级 bug）。
local RATE_LIMIT_EXEMPT = {
    [Protocol.ACTION_TYPES.NEXT_STAGE] = true,
    [Protocol.ACTION_TYPES.CLAIM_BATTLE_REWARDS] = true,
    [Protocol.ACTION_TYPES.TOWER_WAVE_WIN] = true,
    [Protocol.ACTION_TYPES.TOWER_FLOOR_WIN] = true,
    [Protocol.ACTION_TYPES.TOWER_PICK_BUFF] = true,
}

--- 三层守卫 + 路由
---@param connection userdata
---@param action string
---@param params table|nil
local function handleRequest(connection, action, params)
    -- 守卫 1：认证检查
    local uid = getUID(connection)
    if not uid then
        print("[Server] guard: no uid, dropping request")
        return
    end

    -- 选服阶段的结束挑战者区转出只依赖全局存档，必须早于区服数据加载守卫处理。
    if handleGlobalAction(uid, action, params or {}) then
        return
    end

    -- 特殊路由：选服操作不需要完整数据加载
    if action == Protocol.ACTION_TYPES.SELECT_SERVER then
        handleSelectServer(uid, params or {})
        return
    end

    -- 守卫 2：数据加载状态（SaveManager + PDM 都必须就绪）
    if not SaveManager.isLoaded(uid) or not PDM.IsLoaded(uid) then
        sendActionResult(uid, {
            success = false,
            action  = action,
            reason  = "数据加载中，请稍候",
        })
        return
    end

    -- 守卫 2.5：所有 gm_* 协议统一走 UID 白名单（防止个别 Handler 漏鉴权）
    if type(action) == "string" and action:sub(1, 3) == "gm_" then
        local GMHandler = require("server.gm.GMHandler")
        if not GMHandler.IsGM(uid) then
            print("[Server][WARN] rejected non-GM action=" .. tostring(action)
                .. " uid=" .. tostring(uid))
            sendActionResult(uid, {
                success = false,
                action  = action,
                reason  = "权限不足",
            })
            return
        end
    end

    -- 守卫 3：频率限制（关键战斗消息豁免，见 RATE_LIMIT_EXEMPT）
    if not RATE_LIMIT_EXEMPT[action] and not SaveManager.checkRateLimit(uid) then
        sendActionResult(uid, {
            success = false,
            action  = action,
            reason  = "操作过于频繁，请稍候",
        })
        return
    end

    -- 路由到 Handler
    local handler = actionHandlers[action]
    if handler then
        local ok, result = pcall(handler, uid, params)
        if ok then
            -- 异步 handler 返回 nil 表示"稍后自行响应"，不自动发送结果
            if result ~= nil then
                result.action = action   -- 客户端依赖 action 字段做分支路由
                sendActionResult(uid, result)
            end
        else
            print("[Server] handler error action=" .. tostring(action)
                .. " uid=" .. tostring(uid) .. ": " .. tostring(result))
            sendActionResult(uid, {
                success = false,
                action  = action,
                reason  = "服务器内部错误",
            })
        end
    else
        sendActionResult(uid, {
            success = false,
            action  = action,
            reason  = "未知操作: " .. tostring(action),
        })
    end
end

-- ======================== 进入游戏流程 ========================

--- Phase 1: 加载全局存档并推送区服列表
---@param uid number
local function loadGlobalAndPushServerList(uid)
    print("[Server] Phase 1: loading global profile uid=" .. tostring(uid))

    -- 双异步门控：任一全局源成功即可推区服列表；都失败才返回失败。
    local gate = { pdmDone = false, saveDone = false, pdmOk = false, saveOk = false, finished = false }

    local function tryFinishGlobalLoad()
        if gate.finished then return end
        if not gate.pdmOk and not gate.saveOk then
            if not gate.pdmDone or not gate.saveDone then return end
        end
        gate.finished = true

        -- 检查玩家是否仍在线
        if not connections[uid] then
            print("[Server] player disconnected during global load uid=" .. tostring(uid))
            return
        end

        if not gate.saveOk and not gate.pdmOk then
            local GMHandler = require("server.gm.GMHandler")
            ServerDispatcher.sendEvent(uid, Protocol.RES_SAVE_RESULT, {
                status = Protocol.SAVE_STATUS_FAILED,
                tips   = "全局数据加载失败，请重试",
                gm     = GMHandler.IsGM(uid) or nil,
            })
            return
        end

        -- 🔴 封禁检查（首次登录 - PDM 刚加载完成）
        if gate.pdmOk then
            local BanService = require("server.gm.BanService")
            local isBanned, banInfo = BanService.CheckBan(uid)
            if isBanned then
                ServerDispatcher.sendEvent(uid, Protocol.RES_KICKED, {
                    reason      = "账号已封禁: " .. (banInfo.banReason or "违规操作"),
                    showPopup   = true,
                    banExpireTime = banInfo.banExpireTime,
                })
                print("[Server] ban check (post-load): rejecting uid=" .. tostring(uid)
                    .. " reason=" .. tostring(banInfo.banReason))
                return
            end
        end

        -- 🔴 合并 PDM 和 SaveManager 的 global_profile，PDM 为权威源
        -- PDM 是 global_profile 的权威持久化者（SaveManager 的 isPdmManagedKey 防护会跳过写入），
        -- 因此 servers / lastServerId / serverProgress 以 PDM 版本为准。
        -- SaveManager 的版本作为 fallback（PDM 加载失败时兜底）。
        local pdmGp = PDM.GetModule(uid, "global_profile")
        local smGp  = SaveManager.getTable(uid, "global_profile")
        if pdmGp and not smGp then
            SaveManager.replaceModuleMemory(uid, "global_profile", pdmGp)
            smGp = SaveManager.getTable(uid, "global_profile")
        end

        -- 取权威数据源：PDM 优先，SaveManager 兜底
        local gp = pdmGp or smGp or {}

        -- 构造区服列表数据
        local openServers = ServerListConfig.getOpenServers()
        local createdServers = {}
        local lastServerId = gp.lastServerId
        local serverProgress = gp.serverProgress  -- { ["1"]={level,stage}, ... }

        if type(gp.servers) == "table" then
            for sid, ts in pairs(gp.servers) do
                createdServers[#createdServers + 1] = {
                    id = tonumber(sid) or sid,
                    ts = (type(ts) == "number") and ts or 0,  -- 兼容旧数据(true)视为最旧
                }
            end
            -- 按最近游玩时间降序排列（最近玩的排最前）
            table.sort(createdServers, function(a, b) return a.ts > b.ts end)
            -- 展平为纯 ID 数组
            for i, entry in ipairs(createdServers) do
                createdServers[i] = entry.id
            end
        end

        -- 将玩家在各区服的进度附加到区服条目上
        -- 🔴 修复: 除了已开放区服，还需包含玩家已创建角色但未开放的区服
        local enrichedServers = {}
        local includedIds = {}  -- 避免重复添加

        -- 先添加所有已开放的区服
        for _, s in ipairs(openServers) do
            local entry = attachServerListMeta({ id = s.id, name = s.name, openTime = s.openTime }, s)
            if serverProgress then
                local prog = getServerDictValue(serverProgress, s.id)
                if prog then
                    entry.level = prog.level
                    local st = prog.stage or ""
                    st = st:gsub("^%[困难%]", ""):gsub("^%[噩梦%]", ""):gsub("^%[地狱%]", "")
                    entry.stage = st
                end
            end
            enrichedServers[#enrichedServers + 1] = entry
            includedIds[s.id] = true
        end

        -- 挑战者服即使未开放/已结束也下发给客户端，用于展示活动状态，但服务端会禁止进入
        for _, cfg in ipairs(ServerListConfig.SERVERS) do
            if ServerListConfig.isChallengerServer(cfg.id) and not includedIds[cfg.id] then
                local entry = attachServerListMeta({ id = cfg.id, name = cfg.name, openTime = cfg.openTime }, cfg)
                if serverProgress then
                    local prog = getServerDictValue(serverProgress, cfg.id)
                    if prog then
                        entry.level = prog.level
                        entry.stage = prog.stage or ""
                    end
                end
                enrichedServers[#enrichedServers + 1] = entry
                includedIds[cfg.id] = true
            end
        end

        -- 再添加玩家已创建角色但未开放的区服（已游玩的老玩家可进入）
        if type(gp.servers) == "table" then
            for sid, _ in pairs(gp.servers) do
                local numId = tonumber(sid) or sid
                if not includedIds[numId] then
                    local cfg = ServerListConfig.find(numId)
                    if cfg and not ServerListConfig.isServerClosed(cfg.id) then
                        local entry = attachServerListMeta({ id = cfg.id, name = cfg.name, openTime = cfg.openTime }, cfg)
                        if serverProgress then
                            local prog = getServerDictValue(serverProgress, cfg.id)
                            if prog then
                                entry.level = prog.level
                                local st = prog.stage or ""
                                st = st:gsub("^%[困难%]", ""):gsub("^%[噩梦%]", ""):gsub("^%[地狱%]", "")
                                entry.stage = st
                            end
                        end
                        enrichedServers[#enrichedServers + 1] = entry
                        includedIds[numId] = true
                    end
                end
            end
        end

        ServerDispatcher.sendEvent(uid, Protocol.RES_SERVER_LIST, {
            servers        = enrichedServers,
            createdServers = createdServers,
            lastServerId   = lastServerId,
        })

        -- 同步 PDM 数据到 SaveManager 内存副本（后续选服等操作可能读 SaveManager）
        if pdmGp and smGp then
            smGp.servers = pdmGp.servers
            smGp.lastServerId = pdmGp.lastServerId
            smGp.serverProgress = pdmGp.serverProgress
        end

        print("[Server] Phase 1 done: pushed server list uid=" .. tostring(uid))
    end

    -- 并行加载 PDM 全局字段（scope="global"）
    PDM.LoadGlobalProfile(uid, function(pdmOk)
        gate.pdmDone = true
        gate.pdmOk = pdmOk
        if not pdmOk then
            print("[Server] PDM global profile load failed uid=" .. tostring(uid))
        end
        tryFinishGlobalLoad()
    end)

    local loadStartTime = os.clock()
    SaveManager.loadGlobalProfile(uid, function(success, globalProfile)
        gate.saveDone = true
        gate.saveOk = success
        local elapsed = os.clock() - loadStartTime
        if elapsed > 5.0 then
            print("[Server][WARN] SaveManager.loadGlobalProfile slow callback: "
                .. string.format("%.1fs", elapsed) .. " uid=" .. tostring(uid)
                .. " success=" .. tostring(success))
        end
        tryFinishGlobalLoad()
    end)
end

--- Phase 2: 加载玩家区服存档并推送全量数据（serverId 必须已设置）
---@param uid number
--- 重连后补推 PDM 权威模块（resendFromCache 批次可能晚于增量 push 到达，旧包覆盖最新操作）
---@param uid number
local function pushReconnectAuthoritativeModules(uid)
    local pdmModules = PDM.GetAllModules(uid)
    if not pdmModules then return end
    for fieldKey, data in pairs(pdmModules) do
        if fieldKey ~= "_meta" and data ~= nil then
            ServerDispatcher.pushModule(uid, fieldKey, data)
        end
    end
end

--- 处理重连：从缓存重发
---@param uid number
local function handleReconnect(uid)
    BattleService.RestoreBattleModeFromOffline(uid)

    local cached = ServerDispatcher.resendFromCache(uid)
    if cached then
        -- 缓存有效，直接重发
        print("[Server][DEBUG-RECONNECT] via cache uid=" .. tostring(uid)
            .. " cached=true (resendFromCache replays all prior events)")
        ServerDispatcher.sendEvent(uid, Protocol.RES_RECONNECT_DATA, {
            status = "reconnect",
        })
        -- 重连时重置过期的每日限购记录（配置可能从cooldown改为daily，旧记录需清除）
        MarketService.ResetDailyShopItems(uid)
        TavernService.ResetShopLimits(uid)
        -- resendFromCache 批次可能晚于增量 push 到达；补推 PDM 权威模块
        pushReconnectAuthoritativeModules(uid)
        -- 邮件列表不走缓存：MailConfig 可能在热更后变化，必须重新构建推送
        ChallengerService.ProcessLoginRewards(uid)
        local mailListC = MailHandler.buildMailList(uid)
        print("[Server][DEBUG-MAIL] reconnect(cached) mailPush uid=" .. tostring(uid)
            .. " count=" .. tostring(mailListC and #mailListC or "NIL"))
        ServerDispatcher.sendEvent(uid, Protocol.RES_ACTION_RESULT, {
            success  = true,
            mailPush = true,
            mails    = mailListC,
        })
        -- 🔴 修复：重连时补推离线收益数据（如果仍有待领取）
        -- CalcOnEnter 幂等：pendingRewards 存在时直接返回缓存的 panelData
        if OfflineService.HasPendingRewards(uid) then
            local offlineDataC = OfflineService.CalcOnEnter(uid)
            if offlineDataC then
                ServerDispatcher.sendEvent(uid, Protocol.RES_OFFLINE_REWARD, offlineDataC)
                print("[Server] reconnect(cached) re-pushed RES_OFFLINE_REWARD uid=" .. tostring(uid))
            end
        end
    else
        -- 缓存无效 → 优先从内存重建，避免从云端加载覆盖最新数据（回档防护）
        -- 重连场景（同一进程）下 PDM + SaveManager 内存一定有最新数据
        local pdmLoaded = PDM.IsLoaded(uid)
        local saveLoaded = SaveManager.isLoaded(uid)

        if pdmLoaded and saveLoaded then
            -- 从内存重建推送数据（与 loadAndPushFullState 的合并逻辑一致）
            local allData = SaveManager.getAllTables(uid)
            local pushData = {}
            if allData then
                for name, data in pairs(allData) do
                    if name ~= "_meta" then
                        pushData[name] = data
                    end
                end
            end
            -- 重连时重置过期的每日限购记录（配置可能从cooldown改为daily，旧记录需清除）
            MarketService.ResetDailyShopItems(uid)
            TavernService.ResetShopLimits(uid)
            -- PDM 管理的模块覆盖（PDM 为权威源）
            local pdmModules = PDM.GetAllModules(uid)
            if pdmModules then
                for fieldKey, data in pairs(pdmModules) do
                    if fieldKey ~= "_meta" then
                        pushData[fieldKey] = data
                    end
                end
            end

            ServerDispatcher.pushFullState(uid, pushData)
            pushReconnectAuthoritativeModules(uid)

            -- 重连时补推邮件列表（与首次登录一致）
            ChallengerService.ProcessLoginRewards(uid)
            local mailListR = MailHandler.buildMailList(uid)
            print("[Server][DEBUG-MAIL] reconnect mailPush uid=" .. tostring(uid)
                .. " count=" .. tostring(mailListR and #mailListR or "NIL"))
            ServerDispatcher.sendEvent(uid, Protocol.RES_ACTION_RESULT, {
                success  = true,
                mailPush = true,
                mails    = mailListR,
            })

            -- 重连时补推公告列表
            local serverIdR = SaveManager.getServerId(uid)
            local srvCfgR = ServerListConfig.find(serverIdR)
            local openTimeR = (srvCfgR and srvCfgR.openTime) or 0
            local annListR = AnnouncementConfig.buildWithDates(openTimeR)
            print("[Server][DEBUG-ANN] reconnect announcementPush uid=" .. tostring(uid)
                .. " count=" .. tostring(annListR and #annListR or "NIL"))
            ServerDispatcher.sendEvent(uid, Protocol.RES_ACTION_RESULT, {
                success          = true,
                announcementPush = true,
                announcements    = annListR,
            })

            -- 🔴 修复：重连时补推离线收益数据（如果仍有待领取）
            if OfflineService.HasPendingRewards(uid) then
                local offlineDataR = OfflineService.CalcOnEnter(uid)
                if offlineDataR then
                    ServerDispatcher.sendEvent(uid, Protocol.RES_OFFLINE_REWARD, offlineDataR)
                    print("[Server] reconnect(memory) re-pushed RES_OFFLINE_REWARD uid=" .. tostring(uid))
                end
            end

            ServerDispatcher.sendEvent(uid, Protocol.RES_RECONNECT_DATA, {
                status = "reconnect",
            })
            print("[Server] reconnect rebuilt from MEMORY uid=" .. tostring(uid))
        else
            -- 内存也没有数据（不应该发生在重连场景），回退到云端加载
            print("[Server] WARNING: reconnect but no memory data uid=" .. tostring(uid)
                .. " → falling back to loadAndPushFullState")
            loadAndPushFullState(uid)
        end
    end
end

-- ======================== 选服流程 ========================

--- 保存进度并返回选服界面（不清档，用于特权卡转区等）
---@param uid number
returnPlayerToServerSelect = function(uid)
    updateServerProgress(uid)
    cleanupPlayer(uid)
    ServerDispatcher.clearCache(uid)
    if sessions[uid] then
        sessions[uid].isInGame = false
    end
    loadGlobalAndPushServerList(uid)
    print("[Server] returnPlayerToServerSelect uid=" .. tostring(uid))
end

--- 完成选服：设置 serverId、更新 global_profile、加载区服数据
---@param uid number
---@param serverId number
local function finishSelectServer(uid, serverId)
    SaveManager.setServerId(uid, serverId)
    PDM.SetServerId(uid, serverId)

    -- 🔴 更新 global_profile — 必须写入 PDM 的副本（权威持久化源）
    local gp = PDM.GetModule(uid, "global_profile")
    if gp then
        gp.lastServerId = serverId
        if not gp.servers then gp.servers = {} end
        setServerDictValue(gp.servers, serverId, os.time())  -- 记录最后进入时间戳，用于"已游玩"排序
        PDM.MarkDirty(uid, "global_profile")
    end

    -- 同步到 SaveManager 的内存副本（供当前会话读取）
    local smGp = SaveManager.getTable(uid, "global_profile")
    if smGp then
        smGp.lastServerId = serverId
        if not smGp.servers then smGp.servers = {} end
        setServerDictValue(smGp.servers, serverId, os.time())
    end

    print("[Server] Phase 2: entering server " .. tostring(serverId)
        .. " uid=" .. tostring(uid))

    -- 加载区服数据并推送全量状态
    loadAndPushFullState(uid)
end

--- 处理选服请求（Phase 2 入口）
---@param uid number
---@param params table { serverId: number }
handleSelectServer = function(uid, params)
    local serverId = tonumber(params.serverId)
    sendServerDiag(uid, "SELECT_SERVER received serverId=" .. tostring(serverId))
    if not serverId then
        ServerDispatcher.sendEvent(uid, Protocol.RES_SAVE_RESULT, {
            status = Protocol.SAVE_STATUS_FAILED,
            tips   = "缺少 serverId",
        })
        return
    end

    if ServerListConfig.isChallengerServer(serverId) then
        local status = ServerListConfig.getStatus(serverId)
        if status == "closed" then
            ServerDispatcher.sendEvent(uid, Protocol.RES_SAVE_RESULT, {
                status = Protocol.SAVE_STATUS_FAILED,
                tips   = "挑战者活动已结束",
            })
            return
        elseif status == "not_open" then
            ServerDispatcher.sendEvent(uid, Protocol.RES_SAVE_RESULT, {
                status = Protocol.SAVE_STATUS_FAILED,
                tips   = "挑战者活动尚未开放",
            })
            return
        end
        if not StageProvider.IsAvailableForServer(serverId) then
            print("[Server][ERROR] challenger stage config unavailable serverId=" .. tostring(serverId)
                .. " err=" .. tostring(StageProvider.GetLoadError(serverId)))
            ServerDispatcher.sendEvent(uid, Protocol.RES_SAVE_RESULT, {
                status = Protocol.SAVE_STATUS_FAILED,
                tips   = "挑战者配置异常，请稍后再试",
            })
            return
        end
    end

    -- 🔴 修复: 使用 isAccessible 替代 isValid，允许已游玩的玩家进入未开放区服
    local gp = PDM.GetModule(uid, "global_profile") or SaveManager.getTable(uid, "global_profile") or {}
    if not ServerListConfig.isAccessible(serverId, gp.servers) then
        ServerDispatcher.sendEvent(uid, Protocol.RES_SAVE_RESULT, {
            status = Protocol.SAVE_STATUS_FAILED,
            tips   = "无效的区服",
        })
        return
    end

    local oldServerId = SaveManager.getServerId(uid)
    local loadingServerId = phase2Loading[uid]
    if loadingServerId then
        sendServerDiag(uid, "SELECT_SERVER ignored while Phase2 loading loadingServerId="
            .. tostring(loadingServerId) .. " requestedServerId=" .. tostring(serverId))
        print("[Server] SELECT_SERVER ignored while Phase2 loading uid="
            .. tostring(uid) .. " loadingServerId=" .. tostring(loadingServerId)
            .. " requestedServerId=" .. tostring(serverId))
        return
    end

    -- 切服：先清理旧区服数据，再加载新区服
    if oldServerId and oldServerId ~= serverId then
        print("[Server] server switch uid=" .. tostring(uid)
            .. " old=" .. tostring(oldServerId) .. " new=" .. tostring(serverId))

        -- 🔴 切服前先保存旧区服的最新进度到 global_profile.serverProgress
        updateServerProgress(uid)

        -- 清理旧数据（flush dirty + 清内存）
        cleanupPlayer(uid)
        ServerDispatcher.clearCache(uid)

        -- 重新加载全局数据（cleanup 已清除，PDM + SaveManager 都需要重加载）
        -- 任一全局源成功即可继续；都失败才返回失败，避免其中一个云读无回调卡死切服。
        local loadState = { pdmDone = false, saveDone = false, pdmOk = false, saveOk = false, finished = false }
        local function tryFinish()
            if loadState.finished then return end
            if not loadState.pdmOk and not loadState.saveOk then
                if not loadState.pdmDone or not loadState.saveDone then return end
            end
            loadState.finished = true
            if not connections[uid] then return end
            if not loadState.saveOk and not loadState.pdmOk then
                sendActionResult(uid, { success = false, reason = "数据加载失败" })
                return
            end
            if not loadState.pdmOk then
                print("[Server] PDM global reload failed on switch uid=" .. tostring(uid) .. ", continuing with SaveManager data")
            end
            if not loadState.saveOk then
                print("[Server] SaveManager global reload failed on switch uid=" .. tostring(uid) .. ", continuing with PDM data")
            end
            finishSelectServer(uid, serverId)
        end

        PDM.LoadGlobalProfile(uid, function(pdmOk)
            loadState.pdmDone = true
            loadState.pdmOk = pdmOk
            tryFinish()
        end)
        SaveManager.loadGlobalProfile(uid, function(ok, _)
            loadState.saveDone = true
            loadState.saveOk = ok
            tryFinish()
        end)
        return
    end

    -- 首次选服或重新进入同一服
    finishSelectServer(uid, serverId)
end

-- ======================== 网络事件处理 ========================

--- 处理客户端连接（TCP 握手完成，但 identity 尚未建立）
local function handleClientConnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end
    print("[Server] TCP connected, waiting for identity...")
end

--- 处理客户端身份认证（user_id 在此事件中可用）
local function handleClientIdentity(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end

    local identity = connection.identity
    if not identity then
        print("[Server] ClientIdentity but no identity table")
        return
    end

    local uid = identity["user_id"]:GetInt64()
    if not uid or uid == 0 then
        print("[Server] ClientIdentity but no valid user_id")
        return
    end

    print("[Server] client identity confirmed uid=" .. tostring(uid))

    -- 维护模式拦截（GM 白名单豁免）
    if maintenanceMode then
        local GMHandler = require("server.gm.GMHandler")
        if not GMHandler.IsGM(uid) then
            -- 连接映射尚未建立，直接用 connection 底层发送
            local vm = VariantMap()
            local payload = cjson.encode({
                reason    = "服务器维护中，请稍后再试",
                showPopup = true,
            })
            vm["Data"] = Variant(payload)
            connection:SendRemoteEvent(Protocol.RES_KICKED, true, vm)
            print("[Server] maintenance mode: rejecting uid=" .. tostring(uid))
            return
        end
    end

    -- 封禁检查（global_profile 可能尚未加载，需先尝试加载）
    -- 注意: 此处 PDM 数据可能未加载（首次登录），封禁检查在后续 loadPlayerData 完成后再做二次拦截
    -- 对于重连场景（PDM 已加载），可在此处直接拦截
    if PDM.IsLoaded(uid) then
        local BanService = require("server.gm.BanService")
        local isBanned, banInfo = BanService.CheckBan(uid)
        if isBanned then
            local vm = VariantMap()
            local payload = cjson.encode({
                reason      = "账号已封禁: " .. (banInfo.banReason or "违规操作"),
                showPopup   = true,
                banExpireTime = banInfo.banExpireTime,
            })
            vm["Data"] = Variant(payload)
            connection:SendRemoteEvent(Protocol.RES_KICKED, true, vm)
            print("[Server] ban check: rejecting uid=" .. tostring(uid)
                .. " reason=" .. tostring(banInfo.banReason))
            return
        end
    end

    -- 查询玩家昵称（服务端同步，从 SERVER_PLAYER_AUTH_INFOS 读取）
    local nickname = nil
    GetUserNickname({
        userIds = { uid },
        onSuccess = function(nicknames)
            if nicknames and nicknames[1] then
                nickname = nicknames[1].nickname
                print("[Server] player nickname: " .. nickname)
                -- 异步回调到达后，立即同步 session + PDM + cloud
                if sessions[uid] then
                    sessions[uid].nickname = nickname
                end
                if nickname and nickname ~= "" then
                    local pdmPlayer = PDM.GetModule(uid, "player")
                    if pdmPlayer and pdmPlayer.name ~= nickname then
                        pdmPlayer.name = nickname
                        PDM.MarkDirty(uid, "player")
                        print("[Server] nickname MarkDirty pushed to client: " .. nickname)
                    end
                    local playerData = SaveManager.getTable(uid, "player")
                    if playerData then
                        playerData.name = nickname
                    end
                    serverCloud:Set(uid, "player_nickname", nickname)
                    -- 补偿：如果 loadAndPushFullState 已经跑过但当时 nickname 还没到，
                    -- PDM 已加载意味着全量推送已发出（带旧名），MarkDirty 已补推修正。
                    -- 如果 PDM 还没加载（pdmPlayer=nil），loadAndPushFullState 还没跑，
                    -- 等它跑时 session.nickname 已有值，会自动同步——无需额外处理。
                    print("[Server] nickname synced to PDM+cloud: " .. nickname)
                end
            else
                print("[Server] GetUserNickname returned empty for uid=" .. tostring(uid))
            end
        end,
        onFail = function(err)
            -- API 失败时用 cloud 中缓存的旧昵称兜底，避免 nickname 永远为 nil
            print("[Server] GetUserNickname FAILED uid=" .. tostring(uid) .. " err=" .. tostring(err))
            serverCloud:Get(uid, "player_nickname", {
                ok = function(scores)
                    local val = scores and scores["player_nickname"]
                    if val and type(val) == "string" and val ~= "" then
                        nickname = val
                        if sessions[uid] then
                            sessions[uid].nickname = val
                        end
                        local pdmPlayer = PDM.GetModule(uid, "player")
                        if pdmPlayer and pdmPlayer.name ~= val then
                            pdmPlayer.name = val
                            PDM.MarkDirty(uid, "player")
                        end
                        print("[Server] nickname fallback from cloud: " .. val)
                    end
                end,
            })
        end,
    })

    -- 存入连接映射表
    connToUID[connection] = uid

    -- 检查顶号
    local oldSession = sessions[uid]
    if oldSession and oldSession.connection then
        local oldConn = oldSession.connection
        if oldConn ~= connection then
            -- 通知旧客户端被顶号
            ServerDispatcher.sendEvent(uid, Protocol.RES_KICKED, {
                reason = "账号在其他设备登录",
            })
            -- 清除旧连接映射
            connToUID[oldConn] = nil
            print("[Server] kicking old connection for uid=" .. tostring(uid))
        end
    end

    -- 建立/更新连接映射
    connections[uid] = connection

    -- 注意：不在这里设置 connection.scene，在 ClientReady 中设置

    -- 建立/更新会话
    local isReconnect = false
    if oldSession and oldSession.isInGame and SaveManager.isLoaded(uid) then
        -- 重连场景
        isReconnect = true
        -- 🔴 防丢档: 清除断线存档重试队列，防止旧快照覆盖重连后的新数据
        PDM.ClearCleanupRetries(uid)
        sessions[uid] = {
            connection     = connection,
            isInGame       = true,
            disconnectTime = nil,
            nickname       = nickname,
        }
    else
        -- 新会话
        sessions[uid] = {
            connection     = connection,
            isInGame       = false,
            disconnectTime = nil,
            nickname       = nickname,
        }
    end

    -- 不在 ClientIdentity 阶段发送远程事件。
    -- 客户端此时可能尚未完成 RegisterRemoteEvent，过早推送 S_InitData 会被引擎丢弃。
    -- 等客户端显式发送 C_Ready 后，在 handleClientReady 中统一推送初始化/重连数据。
    print("[Server] identity ready uid=" .. tostring(uid)
        .. " reconnect=" .. tostring(isReconnect) .. ", waiting for ClientReady")
end

--- 处理客户端断开
local function handleClientDisconnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end

    local uid = getUID(connection)
    -- 清理连接映射
    connToUID[connection] = nil

    if not uid then return end

    print("[Server] client disconnected uid=" .. tostring(uid))

    local session = sessions[uid]
    if not session then
        connections[uid] = nil
        return
    end

    if session.isInGame then
        -- 进入游戏后断开：保留会话，等待重连
        session.connection = nil
        session.disconnectTime = os.time()
        connections[uid] = nil

        -- 🔴 先更新 lastOnlineTime，再刷盘！
        -- 顺序至关重要：OnPlayerDisconnect 会 MarkDirty("session")，
        -- 必须在 SavePlayer/savePlayerNow 之前调用，否则 lastOnlineTime 永远不会持久化，
        -- 导致下次登录时 OfflineService.CalcOnEnter 用旧的 lastOnlineTime 重复计算离线奖励。
        if SaveManager.isLoaded(uid) then
            OfflineService.OnPlayerDisconnect(uid)
            DungeonIdleService.Cleanup(uid)
        end
        BattleService.ClearRateLimitBucket(uid)

        -- 🔴 断线前更新 serverProgress，确保最新游戏进度写入 global_profile
        updateServerProgress(uid)

        -- 立即刷脏数据到云端（包括刚更新的 lastOnlineTime 和 serverProgress）
        -- 🔴 只调用 PDM.SavePlayer，不调用 SaveManager.savePlayerNow
        -- SaveManager 的区服模块副本是过时的，写入会覆盖 PDM 的最新数据导致丢档

        PDM.SavePlayer(uid)
        print("[Server] keeping session for uid=" .. tostring(uid)
            .. " timeout=" .. DISCONNECT_KEEP_SECONDS .. "s")
    else
        -- 进入游戏前断开：清理
        connections[uid] = nil
        sessions[uid] = nil
        cleanupPlayer(uid)
    end
end

--- 处理 ClientReady 事件
local function handleClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end

    local uid = getUID(connection)

    -- 🔴 persistent_world 修复：引擎可能在脚本订阅前就建立了连接，
    -- 导致 ClientConnected/ClientIdentity 事件未被脚本捕获，connToUID 为空。
    -- 此时从 connection.identity 恢复 UID 映射。
    if not uid then
        local identity = connection.identity
        if identity then
            uid = identity["user_id"]:GetInt64()
        end
        if not uid or uid == 0 then
            print("[Server] ClientReady but cannot resolve uid (no identity)")
            return
        end
        print("[Server] ClientReady: late identity recovery uid=" .. tostring(uid))

        -- 补建映射（相当于补做 handleClientIdentity 的核心逻辑）
        connToUID[connection] = uid
        connections[uid] = connection

        -- 查询昵称（异步）
        local nickname = nil
        GetUserNickname({
            userIds = { uid },
            onSuccess = function(nicknames)
                if nicknames and nicknames[1] then
                    nickname = nicknames[1].nickname
                    -- 异步到达后补写 session + PDM
                    if sessions[uid] then
                        sessions[uid].nickname = nickname
                    end
                    if nickname and nickname ~= "" then
                        local pdmPlayer = PDM.GetModule(uid, "player")
                        if pdmPlayer and pdmPlayer.name ~= nickname then
                            pdmPlayer.name = nickname
                            PDM.MarkDirty(uid, "player")
                        end
                        serverCloud:Set(uid, "player_nickname", nickname)
                    end
                    print("[Server] ClientReady late recovery: nickname=" .. tostring(nickname))
                end
            end,
            onFail = function(err)
                print("[Server] ClientReady GetUserNickname FAILED uid=" .. tostring(uid) .. " err=" .. tostring(err))
            end,
        })

        -- 建立会话（不覆盖已有的活跃会话）
        if not sessions[uid] then
            sessions[uid] = {
                connection     = connection,
                isInGame       = false,
                disconnectTime = nil,
                nickname       = nickname,
            }
        else
            -- 更新连接引用
            sessions[uid].connection = connection
            sessions[uid].disconnectTime = nil
        end
    end

    print("[Server] ClientReady from uid=" .. tostring(uid))

    -- 在 ClientReady 时设置 scene（不要在 ClientConnected/ClientIdentity 中设置）
    connection.scene = scene_

    local session = sessions[uid]
    if session and session.isInGame then
        -- 🔴 重连场景：persistent_world 模式下，handleClientIdentity 中的
        -- RES_INIT_DATA 和 resendFromCache 可能在客户端事件订阅前到达而被丢弃。
        -- 客户端 Start() 完成订阅后会重新发送 ClientReady，此时需要重新推送。
        print("[Server] ClientReady from reconnecting uid=" .. tostring(uid) .. ", re-pushing data")
        local GMHandler = require("server.gm.GMHandler")
        local VersionConfig = require("shared.VersionConfig")
        local initPayload = {
            serverTime = os.time(),
            reconnect  = true,
            uid        = uid,
            nickname   = session.nickname,
            serverId   = SaveManager.getServerId(uid),
            gm         = GMHandler.IsGM(uid) or nil,
            serverVersion = VersionConfig.CURRENT,
        }
        ServerDispatcher.sendEvent(uid, Protocol.RES_INIT_DATA, initPayload)
        handleReconnect(uid)
        return
    end

    local VersionConfig = require("shared.VersionConfig")
    ServerDispatcher.sendEvent(uid, Protocol.RES_INIT_DATA, {
        serverTime    = os.time(),
        reconnect     = false,
        nickname      = session and session.nickname or nil,
        uid           = uid,
        serverVersion = VersionConfig.CURRENT,
    })

    -- Phase 1: 加载全局存档 → 推送区服列表
    loadGlobalAndPushServerList(uid)
end

--- 处理 Action 请求
local function handleAction(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end

    local dataStr = eventData["Data"]:GetString()
    if not dataStr or dataStr == "" then return end

    local ok, data = pcall(cjson.decode, dataStr)
    if not ok or not data then return end

    local action = data.action
    local params = data.params

    handleRequest(connection, action, params)
end

--- 处理 NewGame 请求（重连后选择新游戏 / 返回选服）
local function handleNewGame(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end

    local uid = getUID(connection)
    if not uid then return end

    -- 记录清档前的 serverId（cleanupPlayer 后 PDM 内存被清空，拿不到了）
    local clearServerId = PDM.GetServerId(uid)

    -- 🔴 清档操作：先清除该区服的 serverProgress（在 cleanupPlayer 之前，PDM 还在内存中）
    -- 否则安全网会误判"有进度但 roster 为空 = 数据丢失"。
    if clearServerId then
        local gp = PDM.GetModule(uid, "global_profile")
        if gp and gp.serverProgress and getServerDictValue(gp.serverProgress, clearServerId) then
            setServerDictValue(gp.serverProgress, clearServerId, nil)
            PDM.MarkDirty(uid, "global_profile")
        end
        -- 同步清除 SaveManager 的内存副本
        local smGp = SaveManager.getTable(uid, "global_profile")
        if smGp and smGp.serverProgress and getServerDictValue(smGp.serverProgress, clearServerId) then
            setServerDictValue(smGp.serverProgress, clearServerId, nil)
        end
    end

    -- 🔴 清档操作：重置所有区服模块到默认值
    -- cleanupPlayer → PDM.RemovePlayer 会 flush 所有脏数据到云端，
    -- 如果不重置，旧值会被 flush 到云端，重登后加载的就是旧数据。
    local resetCount = 0
    for _, moduleDef in ipairs(ModuleRegistry.modules) do
        local moduleData = PDM.GetModule(uid, moduleDef.name)
        if moduleData and moduleDef.getDefault then
            local defaults = moduleDef.getDefault()
            for k in pairs(moduleData) do
                moduleData[k] = nil
            end
            for k, v in pairs(defaults) do
                moduleData[k] = v
            end
            PDM.MarkDirty(uid, moduleDef.name)
            resetCount = resetCount + 1
        end
    end

    -- 清理旧数据（PDM.RemovePlayer 内部会 flush 所有脏数据到云端，包括刚重置的模块）
    cleanupPlayer(uid)
    ServerDispatcher.clearCache(uid)

    -- 标记为未进入游戏 + 设置清档标记（用于跳过 Phase 2 完整性检查）
    if sessions[uid] then
        sessions[uid].isInGame = false
        sessions[uid].justClearedSave = true
    else
        print(string.format("[Server][WARN] handleNewGame: sessions[uid] is nil! Cannot set justClearedSave! uid=%s", tostring(uid)))
    end

    -- 重新走 Phase 1（返回选服界面）
    loadGlobalAndPushServerList(uid)
    print(string.format("[Server] handleNewGame completed uid=%s serverId=%s resetModules=%d",
        tostring(uid), tostring(clearServerId), resetCount))
end

--- 在线状态存储用的系统 UID（未来扩展用，记录哪些玩家在线）
local ONLINE_STATUS_UID = 1

--- 处理客户端心跳（每 15 秒一次）
--- 职责：更新 lastOnlineTime → MarkDirty → 立即存盘 → 写入在线状态
local function handleHeartbeat(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end

    local uid = getUID(connection)
    if not uid then return end

    local session = sessions[uid]
    if not session or not session.isInGame then return end

    local now = os.time()

    -- 1. 更新 lastOnlineTime
    -- 🔴 如果有未领取的离线奖励，不更新 lastOnlineTime！
    -- 否则玩家刷新/闪退后重连，CalcOnEnter 会用被心跳刷新的时间戳重新计算，
    -- 导致数小时的离线收益变成几分钟。等玩家领取后 ClaimRewards 会更新。
    if not OfflineService.HasPendingRewards(uid) then
        local sessionData = PDM.GetModule(uid, "session")
        if sessionData then
            sessionData.lastOnlineTime = now
            PDM.MarkDirty(uid, "session")
        end
    end

    -- 2. 触发 PDM 持久化（区服模块由 PDM 独占管理）
    -- 🔴 不要调用 SaveManager.savePlayerNow！
    -- SaveManager 的 tables[uid] 是登录时加载的静态副本，业务逻辑只修改 PDM 的数据。
    -- 调用 SaveManager.savePlayerNow 会用过时数据覆盖 PDM 刚写入的最新数据，导致丢档。

    PDM.SavePlayer(uid)

    -- 3. 写入在线状态到系统 UID（供未来查询用）
    local commit = serverCloud:BatchCommit("online_status")
    if commit then
        commit:ScoreSet(ONLINE_STATUS_UID, "online_" .. tostring(uid), { t = now })
        commit:Commit({
            ok = function() end,
            err = function()
                print("[Server] online status write failed uid=" .. tostring(uid))
            end,
        })
    end
end

--- 处理补齐请求
local function handleResendRequest(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end

    local uid = getUID(connection)
    if not uid then return end

    local dataStr = eventData["Data"]:GetString()
    local ok, data = pcall(cjson.decode, dataStr)
    if not ok then return end

    local missing = data.missing or {}
    local success = ServerDispatcher.handleResendRequest(uid, missing)
    if not success then
        -- 缓存为空，触发全量重建
        loadAndPushFullState(uid)
    end
end

-- ======================== 断线超时清理 ========================

--- 检查断线超时的会话
---@param dt number
local function checkDisconnectTimeouts(dt)
    local now = os.time()
    local toClean = {}

    for uid, session in pairs(sessions) do
        if session.disconnectTime then
            local elapsed = now - session.disconnectTime
            if elapsed >= DISCONNECT_KEEP_SECONDS then
                toClean[#toClean + 1] = uid
            end
        end
    end

    for _, uid in ipairs(toClean) do
        print("[Server] disconnect timeout uid=" .. tostring(uid) .. ", cleaning up")
        -- 🔴 安全网：再次更新 serverProgress（防止断线时的更新未持久化）
        updateServerProgress(uid)
        sessions[uid] = nil
        connections[uid] = nil
        BattleService.ClearRateLimitBucket(uid)
        cleanupPlayer(uid)
    end
end

-- ======================== GM 公开接口 ========================

--- 获取当前在线玩家数量
---@return number
function Server.GetOnlineCount()
    local count = 0
    for _, sess in pairs(sessions) do
        if sess.isInGame and sess.connection then
            count = count + 1
        end
    end
    return count
end

--- 获取服务器启动时间戳
---@return number
function Server.GetStartTime()
    return serverStartTime
end

--- 获取当前所有在线 UID 列表
---@return number[]
function Server.GetOnlineUIDs()
    local uids = {}
    for uid, sess in pairs(sessions) do
        if sess.isInGame and sess.connection then
            uids[#uids + 1] = uid
        end
    end
    return uids
end

--- 判断指定玩家是否在线
---@param uid number
---@return boolean
function Server.IsPlayerOnline(uid)
    local sess = sessions[uid]
    return sess ~= nil and sess.isInGame and sess.connection ~= nil
end

--- 踢出玩家（推送弹窗 → 延迟 3 秒强制断开）
---@param targetUid number  目标 UID
---@param reason string     踢出原因
---@return boolean ok
---@return string|nil errMsg
function Server.KickPlayer(targetUid, reason)
    local sess = sessions[targetUid]
    if not sess or not sess.connection then
        return false, "玩家不在线"
    end

    -- 推送弹窗通知
    ServerDispatcher.sendEvent(targetUid, Protocol.RES_KICKED, {
        reason    = reason or "被管理员踢出",
        showPopup = true,
    })

    -- 延迟 3 秒强制断开
    scheduledDisconnects[targetUid] = os.time() + 3

    print("[Server][GM] KickPlayer uid=" .. tostring(targetUid) .. " reason=" .. tostring(reason))
    return true
end

--- 设置维护模式
---@param enabled boolean
function Server.SetMaintenanceMode(enabled)
    maintenanceMode = enabled
    print("[Server][GM] MaintenanceMode=" .. tostring(enabled))
end

--- 获取维护模式状态
---@return boolean
function Server.GetMaintenanceMode()
    return maintenanceMode
end

--- 处理延迟断开（在 Update 循环中调用）
local function processScheduledDisconnects()
    local now = os.time()
    local toProcess = {}
    for uid, expireTime in pairs(scheduledDisconnects) do
        if now >= expireTime then
            toProcess[#toProcess + 1] = uid
        end
    end
    for _, uid in ipairs(toProcess) do
        scheduledDisconnects[uid] = nil
        local conn = connections[uid]
        if conn then
            conn:Disconnect()
            print("[Server][GM] Force disconnect uid=" .. tostring(uid))
        end
    end
end

-- ======================== 网络事件注册 ========================

local networkEventsRegistered_ = false

local function registerNetworkEvents()
    if networkEventsRegistered_ then return end
    networkEventsRegistered_ = true

    -- 远程事件必须尽早注册。常驻服下客户端可能在服务端完成其它启动任务前
    -- 就已经发送 C_Ready；若注册过晚，C_Ready 会被引擎丢弃，客户端卡在区服列表阶段。
    network:RegisterRemoteEvent(Protocol.REQ_CLIENT_READY)
    network:RegisterRemoteEvent(Protocol.REQ_LOAD_SAVE)
    network:RegisterRemoteEvent(Protocol.REQ_ACTION)
    network:RegisterRemoteEvent(Protocol.REQ_NEW_GAME)
    network:RegisterRemoteEvent(Protocol.REQ_HEARTBEAT)
    network:RegisterRemoteEvent("C_ResendRequest")

    network:RegisterRemoteEvent(Protocol.RES_INIT_DATA)
    network:RegisterRemoteEvent(Protocol.RES_SAVE_RESULT)
    network:RegisterRemoteEvent(Protocol.RES_ACTION_RESULT)
    network:RegisterRemoteEvent(Protocol.RES_STATE_UPDATE)
    network:RegisterRemoteEvent(Protocol.RES_STATE_BATCH)
    network:RegisterRemoteEvent(Protocol.RES_KICKED)
    network:RegisterRemoteEvent(Protocol.RES_RECONNECT_DATA)
    network:RegisterRemoteEvent(Protocol.RES_OFFLINE_REWARD)
    network:RegisterRemoteEvent(Protocol.RES_SERVER_LIST)

    SubscribeToEvent("ClientConnected", handleClientConnected)
    SubscribeToEvent("ClientIdentity", handleClientIdentity)
    SubscribeToEvent("ClientDisconnected", handleClientDisconnected)

    SubscribeToEvent(Protocol.REQ_CLIENT_READY, handleClientReady)
    SubscribeToEvent(Protocol.REQ_ACTION, handleAction)
    SubscribeToEvent(Protocol.REQ_NEW_GAME, handleNewGame)
    SubscribeToEvent(Protocol.REQ_HEARTBEAT, handleHeartbeat)
    SubscribeToEvent("C_ResendRequest", handleResendRequest)

    print("[Server] network events registered")
end

-- ======================== 生命周期 ========================

function Server.Start()
    print("[Server] ========== Starting Server ==========")

    -- 记录启动时间
    serverStartTime = os.time()

    -- 创建场景（常驻服务端，轻量级）
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 注册所有业务模块到 SaveManager
    SaveManager.registerFromRegistry()
    SaveManager.setLoadDiagHook(sendServerDiag)

    -- 初始化 ServerDispatcher
    ServerDispatcher.init(connections)

    -- 初始化 PDM（注入 ServerDispatcher 用于数据推送）
    PDM.Setup({ serverDispatcher = ServerDispatcher, loadDiagHook = sendServerDiag })

    -- 常驻服允许玩家随时加入，网络事件必须在其它异步启动任务前注册。
    registerNetworkEvents()

    -- 初始化跨实例服务（心跳注册 + 离线邮件）
    CrossInstanceService.Init()

    GameAlgoProxy.Start()

    -- 初始化全服公告服务（单机本地公告，不依赖云端存储）
    local okBms, BroadcastMailService = pcall(require, "server.mail.BroadcastMailService")
    if okBms and BroadcastMailService then
        BroadcastMailService.Init(nil)
    end

    -- 初始化兑换码服务（固定兑换码，无需云端记录）
    local okRedeem, RedeemService = pcall(require, "server.redeem.RedeemService")
    if okRedeem and RedeemService and RedeemService.Init then
        RedeemService.Init(nil)
    end

    -- 网络事件已在启动前半段注册；这里保留幂等兜底，避免后续调整启动顺序时漏注册。
    registerNetworkEvents()

    -- 订阅 Update 事件
    local onlineTickAcc = 0
    SubscribeToEvent("Update", function(eventType, eventData)
        local dt = eventData["TimeStep"]:GetFloat()
        SaveManager.update(dt)
        PDM.Update(dt)
        CrossInstanceService.Tick(dt)
        checkDisconnectTimeouts(dt)
        processScheduledDisconnects()
        -- 在线挂机结算（每帧累加，满 60s 自动结算）
        for uid, sess in pairs(sessions) do
            if sess.isInGame and sess.connection then
                IdleSettleService.HandleIdleAccum(uid, dt)
                DungeonIdleService.HandleIdleAccum(uid, dt)
            end
        end

        -- 每60秒累计在线时长
        onlineTickAcc = onlineTickAcc + dt
        if onlineTickAcc >= 60 then
            onlineTickAcc = onlineTickAcc - 60
            for uid, sess in pairs(sessions) do
                if sess.isInGame then
                    TaskService.TickOnlineTime(uid)
                end
            end
        end
        -- 定期存盘已由客户端心跳（每 15s）驱动，见 handleHeartbeat()
    end)

    print("[Server] ready, waiting for connections...")
end

function Server.Stop()
    print("[Server] ========== Stopping Server ==========")
    PDM.Shutdown()          -- PDM 先 flush（铁律：先存后清）
    SaveManager.shutdown()
    print("[Server] shutdown complete")
end

return Server
