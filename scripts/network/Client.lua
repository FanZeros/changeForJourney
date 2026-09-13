---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- Client.lua - 客户端主控（多人模式 · 常驻服架构）
-- 架构: persistent_world，数据持久化→serverCloud（非 clientCloud 云存档）
-- 职责: 连接服务端、接收分发数据、渲染输入（复用Standalone 的UI 管线）
-- 运行： 仅客户端（IsNetworkMode() == true && IsClientMode() == true）
-- ============================================================================

local Protocol         = require("shared.Protocol")
local ClientDispatcher = require("network.ClientDispatcher")
local GameConfig       = require("config.GameConfig")
local TopBar           = require("ui.TopBar")
local BottomNav        = require("ui.BottomNav")
local BattleScene      = require("ui.BattleScene")
local CharacterPanel   = require("ui.CharacterPanel")
local DebugPanel       = require("ui.DebugPanel")
local HeroRosterPanel  = require("ui.HeroRosterPanel")
local RewardPopup      = require("ui.RewardPopup")
local TownScene        = require("ui.TownScene")
local BlacksmithPage   = require("ui.BlacksmithPage")
local ChurchPage       = require("ui.ChurchPage")
local TavernPage       = require("ui.TavernPage")
local ArenaPage        = require("ui.ArenaPage")
local MarketPage       = require("ui.MarketPage")
local GuildPage        = require("ui.GuildPage")
local ArenaBattleScene    = require("ui.ArenaBattleScene")
local DungeonBattleScene  = require("ui.DungeonBattleScene")
local TowerBattleScene    = require("ui.TowerBattleScene")
local TowerBuffPick       = require("ui.TowerBuffPick")
local ArenaOpponentDialog = require("ui.ArenaOpponentDialog")
local GameState        = require("core.GameState")
local ExpTable         = require("config.ExpTable")
local HeroConfig       = require("config.HeroConfig")
local LootBoxSystem    = require("systems.LootBoxSystem")
local EquipmentSystem  = require("systems.EquipmentSystem")
local LootBox          = require("ui.LootBox")
local LootBoxPage      = require("ui.LootBoxPage")
local StartScreen      = require("ui.StartScreen")
local LoadingScreen    = require("ui.LoadingScreen")
local DarkTitleScreen  = require("ui.DarkTitleScreenGate")  -- [DarkTitleScreen] 横屏暗黑标题
local LetterIntro      = require("ui.LetterIntro")      -- [LetterIntro] 先祖来信（首登剧情）
local LevelUpPopup     = require("ui.LevelUpPopup")
local OfflineRewardPanel = require("ui.OfflineRewardPanel")
local UpdateNoticePopup    = require("ui.UpdateNoticePopup")
local VersionMismatchPopup = require("ui.VersionMismatchPopup")
local PlayerInfoPanel  = require("ui.PlayerInfoPanel")
local RedeemCodePanel  = require("ui.RedeemCodePanel")
local DiaryPage        = require("ui.DiaryPage")
local SignInPanel      = require("ui.SignInPanel")
local MailPanel        = require("ui.MailPanel")
local AnnouncementPanel = require("ui.AnnouncementPanel")
local BackpackPanel    = require("ui.BackpackPanel")
local TaskPanel        = require("ui.TaskPanel")
local GMConsolePanel   = require("ui.GMConsolePanel")
local RelicReforgePanel = require("ui.RelicReforgePanel")
local EventBus         = require("core.EventBus")
local GameEvents       = require("config.GameEvents")
local ClientInput      = require("network.ClientInput")
local PlayerStore      = require("client.data.PlayerStore")
local GameBGM          = require("systems.GameBGM")
local GameSFX          = require("systems.GameSFX")
local ServerListConfig = require("shared.ServerListConfig")
local SpinePowerUpEffect = require("ui.SpinePowerUpEffect")
local IntroCutscene      = require("ui.IntroCutscene")
local SamsaraCG          = require("ui.SamsaraCG")
local ScenarioDialogue   = require("ui.ScenarioDialogue")
local DungeonPage        = require("ui.DungeonPage")
local ScenarioDialogueConfig = require("config.ScenarioDialogueConfig")
local CharacterSelect  = require("ui.CharacterSelect")
local DrawUtil         = require("core.DrawUtil")
local AdManager        = require("systems.AdManager")
local TutorialManager  = require("systems.TutorialManager")
local TutorialConfig   = require("config.TutorialConfig")
local ClientMsgHandler = require("network.ClientMessageHandler")
local ClientScenario   = require("network.ClientScenarioHelper")
local GameAlgoService  = require("client.GameAlgoService")

local Client = {}

-- ======================== 状态========================

--- 连接状态
local STATE_CONNECTING    = "connecting"
local STATE_CONNECTED     = "connected"
local STATE_LOADING       = "loading"      -- 等待存档加载结果
local STATE_SERVER_SELECT = "server_select" -- 等待玩家选择区服
local STATE_IN_GAME       = "in_game"
local STATE_DISCONNECTED  = "disconnected"
local STATE_RECONNECTING  = "reconnecting"

local currentState = STATE_CONNECTING

--- 战斗页面切换追踪（tab 3 = 战斗）
local BATTLE_TAB = 3
local lastTabIndex = BATTLE_TAB  -- 默认在战斗页

--- 页面切换过渡动画
local pageTrans = {
    active    = false,
    fromIndex = 0,
    toIndex   = 0,
    progress  = 0,   -- 0~1
    duration  = 0.22,
}

local function easeOutBack(t)
    local s = 1.70158
    local f = t - 1
    return f * f * ((s + 1) * f + s) + 1
end


--- NanoVG
local vg = nil
local fontNormal = -1

--- 设计分辨率（Mode A ：1080×2400 竖屏）
local DESIGN_W = GameConfig.Design.WIDTH
local DESIGN_H = GameConfig.Design.HEIGHT

local physW, physH, dpr, logicalW, logicalH
local scale, screenDesignW, screenDesignH, designOffsetX, designOffsetY

--- 场景
---@type Scene
local scene_ = nil

--- 断线遮罩文本
local overlayText = ""
local showOverlay = false

--- 重试机制
local READY_RETRY_INTERVAL = 8.0   -- ClientReady / ServerList 重试间隔（秒）
local SELECT_SERVER_RETRY_INTERVAL = 12.0  -- 选服读档重试间隔，必须大于服务端读档超时
local READY_RETRY_MAX      = 3     -- 最大重试次数
local DATA_LOAD_TIMEOUT    = 15.0  -- 数据加载超时（秒）
local CONNECTION_TIMEOUT   = 15.0  -- STATE_CONNECTING 超时（秒）
local RECONNECT_TIMEOUT    = 90.0  -- STATE_RECONNECTING 超时（秒）平台Lobby重连查询约60-70s，需覆盖

local readyRetryCount   = 0     -- 已重试次数
local readyRetryTimer   = 0     -- 距离上次发送ClientReady 的计时
local serverListRetryTimer = 0  -- 等待区服列表阶段的独立计时
local serverListRetryCount = 0  -- 等待区服列表阶段的重试次数
local readySent         = false -- 是否已发送过 ClientReady（等待SaveResult）
local saveResultReceived = false -- 是否收到 SaveResult

local dataLoadTimer     = 0     -- 进入 STATE_LOADING 后的计时
local dataLoadRetryCount = 0    -- 数据加载重试次数
local pendingSelectServerId_ = nil  -- 选服后记录 serverId，超时重试时重发 SELECT_SERVER 而非 ClientReady
local connectingTimer   = 0     -- STATE_CONNECTING 阶段计时
local connectingTimeoutShown = false -- 连接超时提示是否已显示
local reconnectTimer    = 0     -- STATE_RECONNECTING 阶段计时

--- 心跳定时器（每15 秒向服务端发送心跳包）
local HEARTBEAT_INTERVAL = 15.0
local heartbeatTimer = 0
local focusLostAt_ = 0  -- os.time() when focus was lost, for detecting stale connections

--- 战斗奖励批量累计（每 3 秒上报一次服务端）
local REWARD_FLUSH_INTERVAL = 3.0
local rewardBuffer = {}        -- { {expReward, goldReward, allyCount, heroIds}, ... }
local rewardFlushTimer = 0

--- 离线收益面板自动弹出控制
local loadingScreenWasOpen_ = true   -- LoadingScreen 初始为开启状态
local offlineRewardAutoShown_ = false -- 避免重复弹出
local updateNoticeShown_     = false -- 更新提醒弹窗是否已弹出
local offlineRewardData_     = nil   -- 服务端推送的离线收益数据
local deferredRewardPopupShown_ = false
local serverListReceived_    = false -- 是否已收到区服列表

--- 情景对话奖励相关（lastClearedStageId_ 已移至ClientMessageHandler 模块）

--- 首访/首次事件追踪（仅客户端用于避免重复触发，真正的已领取状态以服务端claimedScenarios 为准）
--- 注意：全体阵亡情景（38/39/40）直接用 ClientScenario.isClaimed() 判断，无需本地标志）
local enter0204ScenarioFired_        = false  -- 已触发首次进入204情景
local townEntranceScenarioFired_     = false  -- 已触发城镇入场情景3/24/25/26（防止切tab重复触发）

--- 一键合成批量收集状态

-- ======================== 布局 ========================

local function RecalcLayout()
    physW  = graphics:GetWidth()
    physH  = graphics:GetHeight()
    dpr    = graphics:GetDPR()
    logicalW = physW / dpr
    logicalH = physH / dpr
    scale = math.min(logicalW / DESIGN_W, logicalH / DESIGN_H)
    screenDesignW = logicalW / scale
    screenDesignH = logicalH / scale
    designOffsetX = (screenDesignW - DESIGN_W) / 2
    designOffsetY = (screenDesignH - DESIGN_H) / 2
end

-- ======================== GM 权限标记（服务端推送） ========================
local gmAuthed_ = false  -- 仅当服务端确认时为true

--- 查询当前玩家是否已通过服务端GM 鉴权
---@return boolean
function Client.isGM()
    return gmAuthed_
end

-- ======================== 网络工具 ========================

--- 向服务端发送操作请求
---@param action string Protocol.ACTION_TYPES 中的值
---@param params table|nil
---@return boolean sent  true if message was sent, false if no connection
function Client.sendAction(action, params)
    local conn = network:GetServerConnection()
    if not conn then
        print("[Client] no server connection, cannot send action")
        return false
    end

    local vm = VariantMap()
    vm["Data"] = Variant(cjson.encode({
        action = action,
        params = params or {},
    }))
    conn:SendRemoteEvent(Protocol.REQ_ACTION, true, vm)
    return true
end

--- 向服务端发送ClientReady（带重试状态管理）
local function sendClientReady()
    local conn = network:GetServerConnection()
    if not conn then return end

    local vm = VariantMap()
    vm["Data"] = Variant("{}")
    conn:SendRemoteEvent(Protocol.REQ_CLIENT_READY, true, vm)
    readySent = true
    readyRetryTimer = 0
    print("[Client] sent ClientReady (attempt " .. (readyRetryCount + 1) .. "/" .. (READY_RETRY_MAX + 1) .. ")")
end

--- 重置所有重试状态（进入游戏或断线时调用）
local function resetRetryState()
    readyRetryCount = 0
    readyRetryTimer = 0
    serverListRetryTimer = 0
    serverListRetryCount = 0
    readySent = false
    saveResultReceived = false
    dataLoadTimer = 0
    dataLoadRetryCount = 0
    pendingSelectServerId_ = nil
    connectingTimer = 0
    connectingTimeoutShown = false
    reconnectTimer = 0
    serverListReceived_ = false
end

-- ======================== 数据桥接收========================
-- UI 模块（TopBar/BattleScene/CharacterPanel 等）原来读取本地 GameState；
-- 现在需要从 ClientDispatcher 读取服务端推送的数据。
-- 这里通过订阅 ClientDispatcher 模块更新来驱动UI 刷新。

-- ======================== 网络事件处理 ========================

--- 确保 serverConnection.scene 已设置（可多次调用，幂等）
local function ensureConnectionScene()
    local conn = network:GetServerConnection()
    if conn and conn.scene ~= scene_ then
        conn.scene = scene_
        print("[Client] serverConnection.scene set")
    end
end

--- 连接成功
local function handleServerConnected(eventType, eventData)
    print("[Client] connected to server, previous state: " .. currentState)
    local wasReconnecting = (currentState == STATE_RECONNECTING)
    local wasDisconnected = (currentState == STATE_DISCONNECTED)
    currentState = STATE_CONNECTED
    connectingTimer = 0
    connectingTimeoutShown = false
    -- 清除加载界面上可能显示的连接超时提示
    if LoadingScreen.isOpen() then
        LoadingScreen.setStatusText("")
        LoadingScreen.clearTapToRetry()
    end
    ensureConnectionScene()

    -- 🔴 重连修复：从 STATE_RECONNECTING 或 STATE_DISCONNECTED 恢复后，必须重新发送ClientReady。
    -- persistent_world 模式下lobby 重连建立新连接后触发此事件，
    -- 而existingConn 检测只在Client.Start() 执行一次不会再触发）
    -- 必须在此处重新走 ClientReady 流程让服务端重建会话并推送数据。
    --
    -- 🔴 竞态修复：平台Lobby重连查询耗时可能超过RECONNECT_TIMEOUT（实测~63s），
    -- 此时currentState已经超时变为STATE_DISCONNECTED。当Lobby最终建立新连接时
    -- 必须同样走重连流程，否则客户端卡在加载界面无法进入游戏。
    if wasReconnecting or wasDisconnected then
        print("[Client] reconnected after " .. (wasReconnecting and "RECONNECTING" or "DISCONNECTED") .. ", re-sending ClientReady")
        currentState = STATE_LOADING
        serverListReceived_ = true  -- 重连不走选服，防止延迟 ServerList 误触发
        resetRetryState()
        -- 清除断线遮罩
        showOverlay = false
        overlayText = ""
        if LoadingScreen.isOpen() then
            LoadingScreen.setStatusText("重连数据中...")
        else
            overlayText = "重连数据中..."
            showOverlay = true
        end
        sendClientReady()
    else
        if readySent then return end
        currentState = STATE_LOADING
        resetRetryState()
        if LoadingScreen.isOpen() then
            LoadingScreen.setStatusText("加载数据中...")
        else
            overlayText = "加载数据中..."
            showOverlay = true
        end
        sendClientReady()
    end
end

--- 初始化数据（服务端首次发送）
local function handleInitData(eventType, eventData)
    local dataStr = eventData["Data"]:GetString()
    local ok, data = pcall(cjson.decode, dataStr)
    if not ok then return end

    -- 设置玩家 UID：服务端在initPayload 中附带，客户端直接读取
    -- （clientCloud / lobby 的persistent_world 模式下客户端侧不可用）
    if data.uid then
        PlayerInfoPanel.setUID(data.uid)
        print("[Client] UID set: " .. tostring(data.uid))
    else
        PlayerInfoPanel.setUID("预览模式")
        print("[Client] UID 不可用（编辑器预览模式）")
    end

    -- 🔴 防护：已经进入游戏后忽略 InitData 的其余初始化流程，避免重复处理
    -- 注意：不能在 STATE_LOADING/STATE_CONNECTED 时拦截，因为 persistent_world 重连时
    -- 服务端会在ClientReady 响应中重新发送RES_INIT_DATA（reconnect=true）
    if currentState == STATE_IN_GAME then
        return
    end

    -- 版本一致性检测：服务端携带serverVersion，客户端对比本地版本
    -- 放在 STATE_IN_GAME 守卫之后，避免重连时重复触发
    if data.serverVersion then
        local VersionConfig = require("shared.VersionConfig")
        if data.serverVersion ~= VersionConfig.CURRENT then
            print(string.format("[Client] VERSION MISMATCH: client=%s server=%s", VersionConfig.CURRENT, data.serverVersion))
            VersionMismatchPopup.show(data.serverVersion, VersionConfig.CURRENT)
        end
    end

    -- 接收服务端推送的玩家昵称
    if data.nickname and data.nickname ~= "" then
        TopBar.setPlayerName(data.nickname)
        -- GameState.setName 在多人模式下是no-op，name 由PlayerStore 代理
        PlayerInfoPanel.setPlayerName(data.nickname)
        print("[Client] 玩家昵称: " .. data.nickname)
    end
    -- 保底/更新：客户端从 TapTap 拉取最新昵称
    -- 解决服务端 GetUserNickname 异步竞争导致 nickname 始终为 nil 的问题
    -- 同时也覆盖玩家改了 TapTap 名字但服务端 session 仍缓存旧名的情况
    if data.uid then
        GetUserNickname({
            userIds = { data.uid },
            onSuccess = function(nicknames)
                if nicknames and nicknames[1] and nicknames[1].nickname ~= "" then
                    local tapNick = nicknames[1].nickname
                    TopBar.setPlayerName(tapNick)
                    PlayerInfoPanel.setPlayerName(tapNick)
                    print("[Client] 玩家昵称(TapTap): " .. tapNick)
                end
            end,
        })
    end

    -- 确保 scene 已设置（防止 ServerConnected 未触发的情况）
    ensureConnectionScene()

    if data.reconnect then
        -- 重连场景：跳过StartScreen，直接进入加载流程
        currentState = STATE_LOADING
        serverListReceived_ = true  -- 重连不走选服流程，标记为已收到以忽略延迟到达的 ServerList
        resetRetryState()
        dataLoadTimer = 0

        -- 🔴 重连时恢复GM 权限（重连不会再走RES_SAVE_RESULT，gm 标记在InitData 送达）
        if data.gm == true then
            gmAuthed_ = true
            print("[Client] reconnect: GM auth restored")
        end

        -- 🔴 重连路径不会再发 RES_SAVE_RESULT，需要在此直接标记为已收到，
        -- 否则进入游戏条件 `saveResultReceived and ClientDispatcher.hasData()` 永远不满足，卡死在加载界面。
        saveResultReceived = true
        print("[Client] reconnect: saveResultReceived=true (no separate RES_SAVE_RESULT in reconnect path)")

        -- 🔴 重连时必须关闭StartScreen，否则StartScreen 会一直拦截渲染和输入
        -- StartScreen 等待服务端推送区服列表才能点击关闭，但重连路径不走选服流程。
        -- 导致 serverListData_ 永远为nil →点击被忽略→卡在开始界面
        if StartScreen.isOpen() then
            -- 复用 StartScreen.setOnStart 回调，让 LoadingScreen 打开并继承视频BGM
            -- 直接模拟淡出完成的效果：关闭 StartScreen 并触发回调
            print("[Client] reconnect: closing StartScreen (skip server select)")
            StartScreen.skipForReconnect()
        end

        -- 🔴 重连时恢复区服信息（服务端在 RES_INIT_DATA 中附带serverId）
        if data.serverId then
            local serverCfg = ServerListConfig.find(data.serverId)
            if serverCfg then
                PlayerInfoPanel.setServerId(data.serverId)
                PlayerInfoPanel.setServerName(serverCfg.name)
                SignInPanel.setServerOpenTime(serverCfg.openTime or 0)
                print("[Client] reconnect: restored server name=" .. serverCfg.name)
            else
                print("[Client] reconnect: serverId=" .. tostring(data.serverId) .. " not found in config")
            end
        else
            print("[Client] reconnect: no serverId in init data")
        end

        if LoadingScreen.isOpen() then
            LoadingScreen.setStatusText("重连游戏中...")
        else
            overlayText = "重连游戏中..."
            showOverlay = true
        end
    else
        -- 新连接的 ClientReady 已在 ServerConnected 或 existingConn 检测后发送。
        -- 收到 InitData 仅更新基础信息，后续等待服务端推送区服列表。
        currentState = STATE_LOADING
        if LoadingScreen.isOpen() then
            LoadingScreen.setStatusText("加载数据中...")
        else
            overlayText = "加载数据中..."
            showOverlay = true
        end
    end
end

--- 区服列表推送
local function handleServerList(eventType, eventData)
    local dataStr = eventData["Data"]:GetString()
    local ok, data = pcall(cjson.decode, dataStr)
    if not ok then
        print("[Client] failed to decode server list data")
        return
    end

    print("[Client] received ServerList: servers=" .. tostring(data.servers and #data.servers or 0)
        .. " created=" .. tostring(data.createdServers and #data.createdServers or 0)
        .. " lastServerId=" .. tostring(data.lastServerId)
        .. " currentState=" .. tostring(currentState))

    -- 状态守卫：仅在等待区服列表的阶段才处理。
    -- STATE_LOADING 有两种语义：
    --   Phase 1: sendClientReady 后等待区服列表（saveResultReceived=false）
    --   Phase 2: 玩家选服后等待存档数据（saveResultReceived=false 但由选服触发）
    -- 区分方式：Phase 2 时serverListReceived_=true（已收到过列表），
    -- 此时收到的是延迟/重复的列表，应忽略。
    if currentState == STATE_IN_GAME
        or currentState == STATE_DISCONNECTED
        or currentState == STATE_RECONNECTING then
        print("[Client] ignoring stale ServerList in state=" .. tostring(currentState))
        return
    end
    -- Phase 2 LOADING（玩家已选服，正在等存档）→ 忽略重复区服列表
    if currentState == STATE_LOADING and serverListReceived_ then
        print("[Client] ignoring duplicate ServerList during save loading")
        return
    end


    -- 注：重连场景的 stale ServerList 已通过上方 serverListReceived_ 检查拦截
    -- （重连路径在 handleInitData 中设置 serverListReceived_=true）
    serverListReceived_ = true
    currentState = STATE_SERVER_SELECT

    -- 将真实数据传递给 StartScreen / ServerSelectPanel
    StartScreen.setServerListData(data)

    -- 更新 LoadingScreen 状态
    if LoadingScreen.isOpen() then
        LoadingScreen.setStatusText("")
        LoadingScreen.clearTapToRetry()
    end
    showOverlay = false
end

--- 存档加载结果
local function handleSaveResult(eventType, eventData)
    local dataStr = eventData["Data"]:GetString()
    local ok, data = pcall(cjson.decode, dataStr)
    if not ok then return end

    if data.status == Protocol.SAVE_STATUS_SUCCESS then
        saveResultReceived = true
        -- 服务端推送的 GM 鉴权标记（仅白名单玩家会收到 gm=true）
        gmAuthed_ = (data.gm == true)
        -- 服务端诊断中继：打印到设备日志供反馈系统收集
        if data._diag then
            print("[Client][SDIAG] " .. tostring(data._diag))
        end
        -- 等待全量数据推送（在 onAnyUpdate 判断数据收齐后进入游戏）
        if data.tips and data.tips ~= "" then
            print("[Client] tips: " .. data.tips)
        end
    elseif data.status == Protocol.SAVE_STATUS_FAILED then
        saveResultReceived = false
        currentState = STATE_DISCONNECTED
        -- GM 权限即使在存档异常时也应保留，方便调试修复
        if data.gm == true then
            gmAuthed_ = true
        end
        local msg = "存档加载失败\n" .. (data.tips or "请重试")
        if LoadingScreen.isOpen() then
            LoadingScreen.setStatusText(msg)
        else
            overlayText = msg
            showOverlay = true
        end
    elseif data.status == Protocol.SAVE_STATUS_TIMEOUT then
        if LoadingScreen.isOpen() then
            LoadingScreen.setStatusText("连接超时")
        else
            overlayText = "连接超时\n请重试"
            showOverlay = true
        end
    end
end

--- 操作结果
--- 重连数据
local function handleReconnectData(eventType, eventData)
    local dataStr = eventData["Data"]:GetString()
    local ok, data = pcall(cjson.decode, dataStr)
    if not ok then return end

    -- 🔴 仅在数据尚未全部到达时才切换到STATE_LOADING
    -- 重连时resendFromCache 的数据可能在 RES_RECONNECT_DATA 之前到达。
    -- 此时 onAnyUpdate 已将 currentState 推进入STATE_IN_GAME。
    -- 若无条件覆写会导致LoadingScreen 永远无法关闭。
    if currentState ~= STATE_IN_GAME then
        currentState = STATE_LOADING
        print("[Client][DEBUG-RECONNECT] state →STATE_LOADING (waiting for data)")
    else
        print("[Client][DEBUG-RECONNECT] already in game, skipping state change"
            .. " (mail/announcement push should arrive as ActionResult events)")
    end
end

local function handleServerDisconnected(eventType, eventData)
    print("[Client] disconnected from server")
    resetRetryState()

    -- 通知各页面释放等待锁，避免断线后 pendingXxx 永久卡死
    -- （WiFi 场景：Android Doze/WiFi sleep 断开，S_ActionResult 不补发）
    if TavernPage and TavernPage.onServerDisconnect then
        TavernPage.onServerDisconnect()
    end
    local okMP, MarketPageMod = pcall(require, "ui.MarketPage")
    if okMP and MarketPageMod and MarketPageMod.onServerDisconnect then
        MarketPageMod.onServerDisconnect()
    end
    local AdManager = require("systems.AdManager")
    if AdManager.OnServerDisconnect then
        AdManager.OnServerDisconnect()
    end

    if currentState == STATE_IN_GAME or currentState == STATE_SERVER_SELECT then
        -- 游戏/选服中断线：显示遮罩，等待平台自动重连
        currentState = STATE_RECONNECTING
        reconnectTimer = 0
        overlayText = "正在连接服务器..."
        showOverlay = true

        -- 🔴 修复：重连时关闭离线收益面板，防止在不稳定窗口期操作导致奖励丢失
        -- 重连成功后服务端会补发RES_OFFLINE_REWARD（如果仍有待领取），客户端会重新展示
        if OfflineRewardPanel.isOpen() then
            OfflineRewardPanel.close()
            offlineRewardAutoShown_ = false  -- 允许重连后重新展示
            deferredRewardPopupShown_ = false
            print("[Client] closed OfflineRewardPanel on disconnect, will re-show after reconnect")
        end
    else
        -- 非游戏中断线
        currentState = STATE_DISCONNECTED
        if LoadingScreen.isOpen() then
            LoadingScreen.setStatusText("连接已断开，请重新进入游戏")
        else
            overlayText = "连接已断开"
            showOverlay = true
        end
    end
end

--- 连接失败
local function handleConnectFailed(eventType, eventData)
    print("[Client] connect failed")
    resetRetryState()
    currentState = STATE_DISCONNECTED
    if LoadingScreen.isOpen() then
        LoadingScreen.setStatusText("连接失败，请重新进入游戏")
    else
        overlayText = "连接失败\n请重试"
        showOverlay = true
    end
end

-- ======================== 生命周期 ========================

function Client.Start()

    -- 初始化拆分模块
    ClientMsgHandler.setup({ sendAction = Client.sendAction })
    ClientScenario.setup({
        sendAction = Client.sendAction,
        onPendingNotify = function(id) ClientMsgHandler.setPendingTutorialNotify(id) end,
    })
    print("[Client] ========== Starting Client ==========")

    GameAlgoService.Init()

    -- 1. 创建场景
    print("[Client][LOAD] step 1: creating scene...")
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    GameBGM.init(scene_)
    GameSFX.init(scene_)
    local camNode = scene_:CreateChild("Camera", LOCAL)
    local camera = camNode:CreateComponent("Camera")
    renderer:SetViewport(0, Viewport:new(scene_, camera))
    print("[Client][LOAD] step 1: scene OK")

    -- 2. NanoVG
    print("[Client][LOAD] step 2: nvgCreate...")
    vg = nvgCreate(1)
    if not vg then
        print("[Client] ERROR: nvgCreate failed")
        return
    end
    print("[Client][LOAD] step 2: nvgCreate OK")

    -- 3. 字体
    print("[Client][LOAD] step 3: loading font...")
    fontNormal = nvgCreateFont(vg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
    if fontNormal < 0 then
        print("[Client] ERROR: font load failed")
    end
    print("[Client][LOAD] step 3: font OK (id=" .. tostring(fontNormal) .. ")")

    -- 4. 布局
    print("[Client][LOAD] step 4: RecalcLayout...")
    RecalcLayout()
    print("[Client][LOAD] step 4: layout OK (" .. tostring(physW) .. "x" .. tostring(physH) .. " dpr=" .. tostring(dpr) .. ")")

    -- 4.5 碎片图标资源初始化
    DrawUtil.initShardAssets(vg)

    -- 5. UI 子模块初始化
    print("[Client][LOAD] step 5: UI modules init...")
    print("[Client][LOAD]   StartScreen.init...")
    StartScreen.init(vg, scene_)
    print("[Client][LOAD]   LoadingScreen.init...")
    LoadingScreen.init(vg)
    DarkTitleScreen.init(vg)  -- [DarkTitleScreen] 横屏标题资源
    -- StartScreen 关闭后→打开 LoadingScreen（复用视频播放器，避免黑屏闪烁）
    StartScreen.setOnStart(function(vp, vh, bs, bn)
        LoadingScreen.open({ videoPlayer = vp, videoHandle = vh, bgmSource = bs, bgmNode = bn })
        -- 页面可能被浏览器后台回收后重载：此时连接可能已失效超时，
        -- 但StartScreen 还在显示（用户尚未点击），导致LoadingScreen
        -- 打开时currentState 已经是DISCONNECTED，无重试路径 →卡死。
        -- 立即检查并显示错误提示。
        if currentState == STATE_DISCONNECTED or connectingTimeoutShown then
            print("[Client] LoadingScreen opened but connection already failed/timed out")
            LoadingScreen.setStatusText("连接失败，请重新进入游戏")
        end
    end)

    -- 选服回调：用户在 StartScreen/ServerSelectPanel 选中区服后，发送SELECT_SERVER
    StartScreen.setOnServerSelect(function(serverId)
        print("[Client] user selected server id=" .. tostring(serverId))
        -- 设置当前区服名称到玩家信息面板
        local serverCfg = ServerListConfig.find(serverId)
        if serverCfg then
            PlayerInfoPanel.setServerId(serverId)
            PlayerInfoPanel.setServerName(serverCfg.name)
            SignInPanel.setServerOpenTime(serverCfg.openTime or 0)
        end
        currentState = STATE_LOADING
        -- 🔴 修复：选服后必须设置 readySent=true，否则超时重试逻辑不会触发。
        -- 之前 readySent=false 导致客户端在服务端加载超时时永远卡死。
        -- 超时后通过 pendingSelectServerId_ 重发 SELECT_SERVER（而非 ClientReady），
        -- 避免弹回选服界面，同时保证不会永远卡死。
        readySent = true
        saveResultReceived = false
        readyRetryCount = 0
        readyRetryTimer = 0
        dataLoadTimer = 0
        dataLoadRetryCount = 0
        pendingSelectServerId_ = serverId  -- 记录选服 ID，超时时重发
        if LoadingScreen.isOpen() then
            LoadingScreen.setStatusText("加载数据中..")
        else
            overlayText = "加载数据中.."
            showOverlay = true
        end
        Client.sendAction(Protocol.ACTION_TYPES.SELECT_SERVER, { serverId = serverId })
    end)

    StartScreen.setOnClosedTransfer(function(serverId)
        print("[Client] request closed challenger privilege card transfer serverId=" .. tostring(serverId))
        local sent = Client.sendAction(Protocol.ACTION_TYPES.TRANSFER_CLOSED_CHALLENGER_CARD, {})
        if not sent then
            local ServerSelectPanel = require("ui.ServerSelectPanel")
            ServerSelectPanel.setClosedTransferPending(false)
            local LootBoxPage = require("ui.LootBoxPage")
            LootBoxPage.showToast("网络未连接")
        end
    end)

    print("[Client][LOAD]   TopBar.init...")
    TopBar.init(vg)
    print("[Client][LOAD]   BottomNav.init...")
    BottomNav.init(vg)
    print("[Client][LOAD]   BattleScene.init...")
    BattleScene.init(vg)

    -- 5.2 击杀奖励回调：累计到缓冲区，在update 定时批量上报服务端
    BattleScene.setOnEnemyKill(function(data)
        print("[Client] kill callback: exp=" .. tostring(data.expReward)
            .. " gold=" .. tostring(data.goldReward)
            .. " heroIds=#" .. tostring(data.heroIds and #data.heroIds or 0))
        rewardBuffer[#rewardBuffer + 1] = {
            expReward  = data.expReward  or 0,
            goldReward = data.goldReward or 0,
            allyCount  = data.allyCount  or 1,
            heroIds    = data.heroIds    or {},
            stageId    = data.stageId    or 0,
        }
    end)

    print("[Client][LOAD]   CharacterPanel.init...")
    CharacterPanel.init(vg)
    print("[Client][LOAD]   DiaryPage.init...")
    DiaryPage.init(vg)
    -- 注入 sendAction，让 TaskPanel 走服务端领取流程
    TaskPanel.setSendAction(function(action, params)
        Client.sendAction(action, params)
    end)
    print("[Client][LOAD]   DungeonPage.init...")
    DungeonPage.init(vg)
    print("[Client][LOAD]   TownScene.init...")
    TownScene.init(vg)
    print("[Client][LOAD]   BlacksmithPage.init...")
    BlacksmithPage.init(vg)
    print("[Client][LOAD]   ChurchPage.init...")
    ChurchPage.init(vg)
    print("[Client][LOAD]   TavernPage.init...")
    TavernPage.init(vg)
    -- 注入 sendAction，让 TavernPage 走服务端招募流程
    TavernPage.setSendAction(function(action, params)
        Client.sendAction(action, params)
    end)
    -- 注入 sendAction，让 RedeemCodePanel 走服务端兑换流程
    RedeemCodePanel.setSendAction(function(action, params)
        local sent = Client.sendAction(action, params)
        if not sent then
            RedeemCodePanel.onActionResult({ success = false, reason = "网络未连接", redeemAction = true })
        end
    end)
    -- 注入 sendAction，让 SignInPanel 走服务端签到流程
    SignInPanel.setSendAction(function(action, params)
        Client.sendAction(action, params)
    end)
    -- 注入 sendAction，让 MailPanel 走服务端邮件操作流程
    MailPanel.setSendAction(function(action, params)
        Client.sendAction(action, params)
    end)
    -- 铁匠铺：点击直接开页面；打开动画结束后播入场情景47；首次离开时播离场分支48/49/50
    TownScene.setOnSmithClick(function()
        BlacksmithPage.setOnOpenCallback(function()
            ClientScenario.playFirstVisit(47, nil, nil)
        end)
        BlacksmithPage.setOnCloseCallback(function()
            ClientScenario.playFirstVisit(nil, { [1]=48, [2]=49, [3]=50 }, nil)
        end)
        BlacksmithPage.open()
    end)
    -- 教堂：点击直接开页面；打开动画结束后播入场情景27；首次离开时播离场分支28/29/30
    TownScene.setOnChurchClick(function()
        ChurchPage.setOnOpenCallback(function()
            ClientScenario.playFirstVisit(27, nil, nil)
        end)
        ChurchPage.setOnCloseCallback(function()
            ClientScenario.playFirstVisit(nil, { [1]=28, [2]=29, [3]=30 }, nil)
        end)
        ChurchPage.open()
    end)
    -- 酒馆：点击直接开页面；打开动画结束后播入场情景31；首次离开时播离场分支32/33/34
    TownScene.setOnTavernClick(function()
        TavernPage.setOnOpenCallback(function()
            ClientScenario.playFirstVisit(31, nil, nil)
        end)
        TavernPage.setOnCloseCallback(function()
            ClientScenario.playFirstVisit(nil, { [1]=32, [2]=33, [3]=34 }, nil)
        end)
        TavernPage.open()
    end)
    print("[Client][LOAD]   ArenaPage.init...")
    ArenaPage.init(vg)
    print("[Client][LOAD]   ArenaBattleScene.init...")
    ArenaBattleScene.init(vg)
    print("[Client][LOAD]   DungeonBattleScene.init...")
    DungeonBattleScene.init(vg)
    print("[Client][LOAD]   TowerBuffPick.init...")
    TowerBuffPick.init(vg)
    -- 竞技场：点击直接开页面；打开动画结束后播入场情景54（无离场分支）
    TownScene.setOnArenaClick(function()
        ArenaPage.setOnOpenCallback(function()
            ClientScenario.playFirstVisit(54, nil, nil)
        end)
        ArenaPage.open()
    end)
    print("[Client][LOAD]   MarketPage.init...")
    MarketPage.init(vg)
    -- 注入 sendAction，让 MarketPage 走服务端购买流程
    MarketPage.setSendAction(function(action, params)
        Client.sendAction(action, params)
    end)
    TownScene.setOnMarketClick(function()
        MarketPage.open()
    end)
    print("[Client][LOAD]   GuildPage.init...")
    GuildPage.init(vg)
    TownScene.setOnGuildClick(function()
        GuildPage.open()
    end)
    print("[Client][LOAD]   DebugPanel.init...")
    DebugPanel.init(vg)
    print("[Client][LOAD]   HeroRosterPanel.init...")
    HeroRosterPanel.init(vg)
    print("[Client][LOAD]   RewardPopup.init...")
    RewardPopup.init(vg)
    print("[Client][LOAD]   LevelUpPopup.init...")
    LevelUpPopup.init(vg)
    print("[Client][LOAD]   OfflineRewardPanel.init...")
    OfflineRewardPanel.init(vg)
    print("[Client][LOAD]   UpdateNoticePopup.init...")
    UpdateNoticePopup.init(vg)
    print("[Client][LOAD]   VersionMismatchPopup.init...")
    VersionMismatchPopup.init(vg)
    print("[Client][LOAD]   PlayerInfoPanel.init...")
    PlayerInfoPanel.init(vg)
    print("[Client][LOAD]   SpinePowerUpEffect.init...")
    SpinePowerUpEffect.init()
    print("[Client][LOAD]   IntroCutscene.init...")
    IntroCutscene.init(vg, scene_)
    print("[Client][LOAD]   ScenarioDialogue.init...")
    ScenarioDialogue.init(vg, scene_)
    print("[Client][LOAD]   TutorialManager.init...")
    TutorialManager.init(vg, PlayerStore)
    print("[Client][LOAD]   CharacterSelect.init...")
    CharacterSelect.init(vg)
    print("[Client][LOAD] step 5: all UI modules init OK")

    -- 5.05 冒险等级提升弹窗：监听PLAYER_LEVEL_UP 事件，并刷新解锁状态
    EventBus.on(GameEvents.PLAYER_LEVEL_UP, function(data)
        local newLevel = data.level
        local unlocks = ExpTable.getLevelUnlocks(newLevel)
        LevelUpPopup.show(newLevel, unlocks)
        -- 刷新各模块解锁状态
        CharacterPanel.refreshSlotUnlocks()
        BottomNav.refreshUnlockState(vg)
    end)


    -- 5.25 战利品领取回调：弹窗关闭 →发送一键领取请求到服务端
    LootBox.setOnClaimAll(function()
        print("[Client] LootBox claimAll →sending CLAIM_LOOT_ALL to server")
        Client.sendAction(Protocol.ACTION_TYPES.CLAIM_LOOT_ALL, {})
    end)

    -- 5.251 战利品单个领取回调：点击种子图标 →发送该组全部领取请求到服务端
    LootBox.setOnClaimOne(function(seedIndex)
        print("[Client] LootBox claimGroup index=" .. tostring(seedIndex)
            .. " →sending CLAIM_LOOT to server")
        Client.sendAction(Protocol.ACTION_TYPES.CLAIM_LOOT, { index = seedIndex })
        -- 服务端返回actionResult 后由 handleActionResult 刷新 LootBox + 弹出 RewardPopup
    end)

    -- 5.252 战利品一键分解回调：发送分解请求到服务端
    LootBox.setOnDecomposeAll(function()
        print("[Client] LootBox decomposeAll →sending DECOMPOSE_LOOT_ALL to server")
        Client.sendAction(Protocol.ACTION_TYPES.DECOMPOSE_LOOT_ALL, {})
        LootBox.refreshPage()
    end)

    LootBox.setOnDecomposeOne(function(seedIndex)
        print("[Client] LootBox decomposeOne index=" .. tostring(seedIndex) .. " →sending DECOMPOSE_LOOT to server")
        Client.sendAction(Protocol.ACTION_TYPES.DECOMPOSE_LOOT, { index = seedIndex })
        LootBox.refreshPage()
    end)

    -- 5.253 自动分解设置回调：直接打开弹窗（无需导航到铁匠铺）
    LootBox.setOnAutoDecompose(function()
        LootBoxPage.hide()
        BlacksmithPage.openAutoDecomposePopupStandalone()
    end)

    -- 5.3 轮回回调：倒计时结束→播放轮回前对话→CG 视频 →开场动画→完成关卡加载
    BattleScene.setOnReincarnate(function(data)
        print("[Client] reincarnation triggered, playing CG video then intro cutscene (difficulty "
            .. tostring(data.fromDifficulty) .. " →" .. tostring(data.toDifficulty) .. ")")

        -- 轮回前情景对话（普通终点→62，困难终点→69）
        local preReincarnateScenarioId = nil
        if data.fromDifficulty == "normal" then
            preReincarnateScenarioId = 62
        elseif data.fromDifficulty == "hard" then
            preReincarnateScenarioId = 69
        end

        local function proceedWithCG()
            -- 先播放轮回CG 视频（BGM 在视频模块内部静音恢复）
            SamsaraCG.start(function()
                -- CG 视频结束后，播放开场动画
                print("[Client] CG video finished, starting intro cutscene")
                IntroCutscene.reset()
                IntroCutscene.start(function()
                    print("[Client] reincarnation intro finished, completing stage load")
                    BattleScene.completeReincarnation()
                    -- completeReincarnation 会同步 NEXT_STAGE，服务端可能标记 hasReincarnated；
                    -- 入场动画已在本次轮回流程播放完毕，清除标记避免重启后重复播放
                    Client.sendAction(Protocol.ACTION_TYPES.CLEAR_REINCARNATION, {})
                end)
            end)
        end

        if preReincarnateScenarioId and not ClientScenario.isClaimed(preReincarnateScenarioId) then
            ClientScenario.playFirstVisit(preReincarnateScenarioId, nil, proceedWithCG)
        else
            proceedWithCG()
        end
    end)

    BattleScene.setOnStageLoaded(function(stageId, isFirstClear)
        GameAlgoService.TrackLevelStart(stageId, { first_clear = isFirstClear == true })
    end)

    -- 5.4 关卡进度回调：首通前进 →同步服务端持久化
    BattleScene.setOnFirstClear(function(clearedStageId)
        GameAlgoService.TrackLevelEnd(clearedStageId, "win", { first_clear = true })

        -- 记录最近首通的关卡ID，用于后续触发情景对话
        ClientMsgHandler.lastClearedStageId_ = clearedStageId

        -- 仅记录通关，不推进关卡；玩家手动点"前进"才切换
        Client.sendAction(Protocol.ACTION_TYPES.NEXT_STAGE, {
            clearedStageId = clearedStageId,
        })
    end)

    BattleScene.setOnStageChanged(function(newStageId)

        Client.sendAction(Protocol.ACTION_TYPES.NEXT_STAGE, {
            nextStageId = newStageId,
        })
        -- 首次进入关卡 0204 →触发情景 41/42/43（昆吾之怒）
        if newStageId == 204 and not enter0204ScenarioFired_ then
            enter0204ScenarioFired_ = true
            if not ClientScenario.isClaimed(41) then
                local sessionData = PlayerStore.Get("session")
                local heroId = sessionData and sessionData.initialHeroId
                local followIds = { [1]=41, [2]=42, [3]=43 }
                local scenarioId = heroId and followIds[heroId] or 41
                local config = ScenarioDialogueConfig["SCENARIO_" .. scenarioId]
                if config then
                    ScenarioDialogue.show({
                        mode       = config.mode,
                        background = config.background,
                        steps      = config.steps,
                        onFinish = function()
                            Client.sendAction(Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD, {
                                scenarioId = scenarioId,
                            })
                            ClientMsgHandler.setPendingTutorialNotify(scenarioId)
                        end,
                    })
                end
            end
        end

        -- ========== 情景对话 61-73：关卡进入触发==========
        -- 进入普通终点站 999 →情景 61（终章·普通篇）
        if newStageId == 999 then
            ClientScenario.playFirstVisit(61)
        end
        -- 进入困难 1 →2401 →情景 63（困难开篇）
        if newStageId == 2401 then
            ClientScenario.playFirstVisit(63)
        end
        -- 进入困难 2 →2505 →情景 64
        if newStageId == 2505 then
            ClientScenario.playFirstVisit(64)
        end
        -- 进入困难 4 →2705 →情景 65
        if newStageId == 2705 then
            ClientScenario.playFirstVisit(65)
        end
        -- 进入困难 6 →2905 →情景 67
        if newStageId == 2905 then
            ClientScenario.playFirstVisit(67)
        end
        -- 进入困难终点站1999 →情景 68（终章·困难篇）
        if newStageId == 1999 then
            ClientScenario.playFirstVisit(68)
        end
        -- 进入噩梦 1 →4701 →情景 70（噩梦开篇）
        if newStageId == 4701 then
            ClientScenario.playFirstVisit(70)
        end
        -- 进入噩梦 1 →4705 →情景 71
        if newStageId == 4705 then
            ClientScenario.playFirstVisit(71)
        end
        -- 进入噩梦 2 →4805 →情景 72
        if newStageId == 4805 then
            ClientScenario.playFirstVisit(72)
        end
        -- 进入噩梦 3 →4905 →情景 73
        if newStageId == 4905 then
            ClientScenario.playFirstVisit(73)
        end
    end)

    -- 全体阵亡 →触发情景 38/39/40（神秘少女）
    BattleScene.setOnAllDead(function()
        GameAlgoService.TrackLevelEnd(BattleScene.getCurrentStageId(), "lose")

        local sessionData = PlayerStore.Get("session")
        local heroId = sessionData and sessionData.initialHeroId
        local followIds = { [1]=38, [2]=39, [3]=40 }
        local scenarioId = heroId and followIds[heroId] or 38
        if ClientScenario.isClaimed(scenarioId) then return end
        -- 本地立即标记 pending，防止连续死亡时异步 claim 未回来导致重复触发
        ClientScenario.markPending(scenarioId)
        local config = ScenarioDialogueConfig["SCENARIO_" .. scenarioId]
        if config then
            -- 死亡情景无实际奖励（type=none），在展示对话【前】发送claim。
            -- 若在 onFinish 中发送，用户对话途中刷新游戏，onFinish 不触发，
            -- 服务端不记录已领取，导致重进游戏后死亡情景反复重播。
            Client.sendAction(Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD, {
                scenarioId = scenarioId,
            })
            ClientMsgHandler.setPendingTutorialNotify(scenarioId)
            ScenarioDialogue.show({
                mode       = config.mode,
                background = config.background,
                steps      = config.steps,
            })
        end
    end)

    -- 5.4 阵容变更回调：角色面板出战变更→同步服务端+ 本地即时刷新
    -- [三队并行] 回调携带 teamIdx：队1 同步战斗画面；队2/3 仅提交编队（三栏并行战斗 Phase 3 接入）
    CharacterPanel.setOnTeamChanged(function(teamIdx)
        teamIdx = tonumber(teamIdx) or 1
        -- 收集该队出战 heroId 列表
        local team = CharacterPanel.getDeployedTeam(teamIdx)
        local deployedIds = {}
        for _, unit in ipairs(team) do
            if unit.heroId then
                deployedIds[#deployedIds + 1] = unit.heroId
            end
        end

        -- 发送指定队伍的完整阵容到服务端（服务端校验解锁/唯一性后 markDirty 推送回来）
        Client.sendAction(Protocol.ACTION_TYPES.SET_TEAM, {
            teamIdx = teamIdx,
            heroIds = deployedIds,
        })

        if teamIdx == 1 then
            -- 本地即时更新战斗画面（不等服务端推送）
            -- 同时更新快照，防止服务端推送回来时触发重复 reloadStage
            ClientMsgHandler.setLastDeployedSnapshot(ClientMsgHandler.deployedToString(deployedIds))
            TopBar.setTotalPower(CharacterPanel.getTotalPower())
            if #team > 0 then
                BattleScene.setAllies(team)
                BattleScene.reloadStage()
            end
        else
            print("[Client] 队伍" .. teamIdx .. " 编队提交: " .. #deployedIds .. " 人（等待服务端校验推送）")
        end
    end)

    -- 6. 数据订阅
    print("[Client][LOAD] step 6: setupDataSubscriptions...")
    ClientMsgHandler.setupDataSubscriptions()
    PlayerStore.Init()
    -- 注册全局超时提示钩子：WaitForChange 超时且无自定义onTimeout 时触发
    PlayerStore.SetWaitTimeoutHook(function(key, elapsed)
        print(string.format("[Client][WARN] 操作超时 key=%s elapsed=%.1fs, 网络可能不稳定", key, elapsed))
        -- TODO: 接入全局 Toast/飘字提示玩家"操作超时，请检查网络
        -- 当前仅日志记录；后续可通过 UI 框架展示轻提示
    end)
    -- session 订阅必须在PlayerStore.Init() 之后注册。
    -- PlayerStore.Subscribe 的回调触发时，PlayerStore 内部缓存已更新，
    -- BottomNav.refreshUnlockState() 调用 PlayerStore.Get("session") 才能拿到最新值。
    PlayerStore.Subscribe("session", function(data, fieldKey)
        BottomNav.refreshUnlockState()
        -- 🔴 修复签到天数: 当openTime=0 时，用firstLoginTime 作为签到周期起始。
        -- SignInPanel.getServerOpenTime() 返回当前缓存的openTime，为 0 说明配置无固定开服日
        if data and (data.firstLoginTime or 0) > 0 then
            if (SignInPanel.getServerOpenTime and SignInPanel.getServerOpenTime() or 0) <= 0 then
                SignInPanel.setServerOpenTime(data.firstLoginTime)
            end
        end
    end)
    -- battle 数据变化时也刷新解锁状态：
    -- isPanelUnlocked / isBuildingUnlocked 依赖 battle.maxStageId，但battle 可能在
    -- session 晚到达，若只在session 变化时刷新，battle 到达后城镇角色面tab 仍然锁定。
    PlayerStore.Subscribe("battle", function(data, fieldKey)
        BottomNav.refreshUnlockState()
        -- 副本解锁依赖 maxStageId，关卡推进后也需刷新副本红点
        if BottomNav.refreshDungeonBadge then
            BottomNav.refreshDungeonBadge()
        end
    end)
    -- 遗物模块变化 →初始化seenSet（首次） + 刷新公会角标）
    local relicSeenInited = false
    PlayerStore.Subscribe("mod_relics", function(data, fieldKey)
        local okRS, RS = pcall(require, "systems.RelicSystem")
        if not okRS or not RS then return end
        -- 首次到达时初始化"已见"集合（后续新增才产生红点）
        if not relicSeenInited then
            relicSeenInited = true
            if RS.initSeenSet then RS.initSeenSet() end
        end
        -- 刷新公会遗物角标 →TownScene 建筑 →BottomNav Tab4
        if RS.getRelicBadgeInfo then
            local show, style = RS.getRelicBadgeInfo()
            local okTS, TS = pcall(require, "ui.TownScene")
            if okTS and TS and TS.setGuildRelicBadge then
                TS.setGuildRelicBadge(show, style)
            end
            local okBN, BN = pcall(require, "ui.BottomNav")
            if okBN and BN and BN.refreshTownBadge then
                BN.refreshTownBadge()
            end
        end
    end)
    -- 神器模块变化 →刷新教堂入口/底部导航可提升角标
    PlayerStore.Subscribe("artifacts", function(data, fieldKey)
        local okBN, BN = pcall(require, "ui.BottomNav")
        if okBN and BN and BN.refreshTownBadge then
            BN.refreshTownBadge()
        end
    end)
    -- 副本数据变化 →刷新副本 Tab5 红点（可扫荡次数）
    PlayerStore.Subscribe("dungeon", function(data, fieldKey)
        local okBN, BN = pcall(require, "ui.BottomNav")
        if okBN and BN and BN.refreshDungeonBadge then
            BN.refreshDungeonBadge()
        end
    end)
    -- 签到模块数据变化 →推送给 SignInPanel 刷新按钮状态
    PlayerStore.Subscribe("signin", function(data, fieldKey)
        if data then
            SignInPanel.setSignInData(data)
        end
    end)
    -- 任务模块数据变化 →推送给 TaskPanel 刷新任务列表/按钮状态
    PlayerStore.Subscribe("task", function(data, fieldKey)
        if data then
            TaskPanel.setTaskData(data)
        end
    end)
    -- 集市模块数据变化 →推送给 MarketPage 刷新购买记录/限购状态
    PlayerStore.Subscribe("market", function(data, fieldKey)
        if data then
            MarketPage.setMarketData(data)
        end
    end)
    -- 战利品箱子数据变化→刷新 LootBox UI（种子计时+ 摘要）
    PlayerStore.Subscribe("lootbox", function(data, fieldKey)
        if data then
            LootBoxSystem.consolidateSeeds(data)
            LootBox.updateSeedData(data)
        end
    end)
    GameState.bindToPlayerStore()
    print("[Client][LOAD] step 6: OK")

    -- 6.5 广告管理器初始化（注入sendAction 依赖，订阅adPending 模块）
    AdManager.Init(Client.sendAction)

    -- 7. 注册远程事件
    print("[Client][LOAD] step 7-10: register events & subscribe...")
    network:RegisterRemoteEvent(Protocol.REQ_CLIENT_READY)
    network:RegisterRemoteEvent(Protocol.REQ_ACTION)
    network:RegisterRemoteEvent(Protocol.REQ_NEW_GAME)
    network:RegisterRemoteEvent(Protocol.REQ_RETURN_SERVER_SELECT)
    network:RegisterRemoteEvent(Protocol.REQ_HEARTBEAT)
    network:RegisterRemoteEvent("C_ResendRequest")

    network:RegisterRemoteEvent(Protocol.RES_SERVER_LIST)
    network:RegisterRemoteEvent(Protocol.RES_INIT_DATA)
    network:RegisterRemoteEvent(Protocol.RES_SAVE_RESULT)
    network:RegisterRemoteEvent(Protocol.RES_ACTION_RESULT)
    network:RegisterRemoteEvent(Protocol.RES_STATE_UPDATE)
    network:RegisterRemoteEvent(Protocol.RES_STATE_BATCH)
    network:RegisterRemoteEvent(Protocol.RES_KICKED)
    network:RegisterRemoteEvent(Protocol.RES_RECONNECT_DATA)
    network:RegisterRemoteEvent(Protocol.RES_OFFLINE_REWARD)

    -- 8. 订阅网络事件
    SubscribeToEvent("ServerConnected", handleServerConnected)
    SubscribeToEvent("ServerDisconnected", handleServerDisconnected)
    SubscribeToEvent("ConnectFailed", handleConnectFailed)

    -- 9. 订阅远程事件
    SubscribeToEvent(Protocol.RES_SERVER_LIST, handleServerList)
    SubscribeToEvent(Protocol.RES_INIT_DATA, handleInitData)
    SubscribeToEvent(Protocol.RES_SAVE_RESULT, handleSaveResult)
    SubscribeToEvent(Protocol.RES_ACTION_RESULT, ClientMsgHandler.handleActionResult)
    SubscribeToEvent(Protocol.RES_STATE_UPDATE, function(et, ed)
        if currentState ~= STATE_LOADING and currentState ~= STATE_IN_GAME then
            print("[Client] ignoring StateUpdate in state=" .. tostring(currentState))
            return
        end
        ClientMsgHandler.handleStateUpdate(et, ed)
    end)
    SubscribeToEvent(Protocol.RES_STATE_BATCH, function(et, ed)
        if currentState ~= STATE_LOADING and currentState ~= STATE_IN_GAME then
            print("[Client] ignoring StateBatch in state=" .. tostring(currentState))
            return
        end
        ClientMsgHandler.handleStateUpdate(et, ed)
    end)
    SubscribeToEvent(Protocol.RES_KICKED, function(et, ed)
        local reason = ClientMsgHandler.handleKicked(et, ed)
        if reason then
            currentState = STATE_DISCONNECTED
            overlayText = reason
            showOverlay = true
        end
    end)
    SubscribeToEvent(Protocol.RES_RECONNECT_DATA, handleReconnectData)
    SubscribeToEvent(Protocol.RES_OFFLINE_REWARD, function(et, ed)
        local data = ClientMsgHandler.handleOfflineReward(et, ed)
        if data then
            offlineRewardData_ = data
        end
    end)

    -- 10. 渲染和输入事件
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender_Client")
    SubscribeToEvent("Update", "HandleUpdate_Client")
    SubscribeToEvent("ScreenMode", "HandleScreenMode_Client")
    SubscribeToEvent("InputFocus", "HandleInputFocus_Client")

    -- 10.1 输入事件 →ClientInput 子模块
    ClientInput.setContext({
        dpr            = dpr,
        scale          = scale,
        designOffsetX  = designOffsetX,
        designOffsetY  = designOffsetY,
        currentStateFn = function() return currentState end,
        STATE_IN_GAME  = STATE_IN_GAME,
    })

    -- [DIAG] 所有输入事件处理器用pcall 保护，防止崩溃影响引擎事件系统
    local function safeInput(name, handler)
        return function(et, ed)
            local ok, err = pcall(handler, et, ed)
            if not ok then
                print("[Client] input error (" .. name .. "): " .. tostring(err))
            end
        end
    end
    SubscribeToEvent("MouseButtonDown", safeInput("MouseDown", function(et, ed) ClientInput.handleMouseButtonDown(et, ed) end))
    SubscribeToEvent("MouseButtonUp",   safeInput("MouseUp",   function(et, ed) ClientInput.handleMouseButtonUp(et, ed) end))
    SubscribeToEvent("MouseMove",       safeInput("MouseMove", function(et, ed) ClientInput.handleMouseMove(et, ed) end))
    SubscribeToEvent("TouchBegin",      safeInput("TouchBegin",function(et, ed) ClientInput.handleTouchBegin(et, ed) end))
    SubscribeToEvent("TouchEnd",        safeInput("TouchEnd",  function(et, ed) ClientInput.handleTouchEnd(et, ed) end))
    SubscribeToEvent("TouchMove",       safeInput("TouchMove", function(et, ed) ClientInput.handleTouchMove(et, ed) end))
    SubscribeToEvent("MouseWheel",      safeInput("MouseWheel",function(et, ed) ClientInput.handleMouseWheel(et, ed) end))

    -- 初始状态
    currentState = STATE_CONNECTING
    overlayText = "连接服务器中..."
    showOverlay = true

    -- persistent_world 模式下连接可能已建立，提前设置scene
    ensureConnectionScene()

    -- 🔴 persistent_world 修复：引擎可能在 Start() 之前已建立连接，
    -- 导致 RES_INIT_DATA 在事件订阅前到达而被丢弃。
    -- 直接推进入STATE_LOADING 复用其完善的重试机制（即ClientReady 重发 + tap-to-retry）。
    -- 服务端handleClientReady 对新 session 会调用loadGlobalAndPushServerList →推送RES_SERVER_LIST。
    local existingConn = network:GetServerConnection()
    if existingConn and not readySent then
        currentState = STATE_LOADING
        resetRetryState()
        if LoadingScreen.isOpen() then
            LoadingScreen.setStatusText("加载数据中..")
        else
            overlayText = "加载数据中.."
            showOverlay = true
        end
        sendClientReady()
    end

    print("[Client] Started →design " .. DESIGN_W .. "x" .. DESIGN_H)
end

--- 清除存档后重置客户端一次性标志，让开场动画等可以重新触发
function Client.resetForNewSession()
    local TAG = "[Client][DIAG-RESET]"
    print(string.format("%s resetForNewSession START clock=%.4f", TAG, os.clock()))
    loadingScreenWasOpen_ = true
    offlineRewardAutoShown_ = false
    deferredRewardPopupShown_ = false
    updateNoticeShown_ = false
    gmAuthed_ = false
    if ClientMsgHandler and ClientMsgHandler.clearPendingDeferredRewardPopup then
        ClientMsgHandler.clearPendingDeferredRewardPopup()
    end
    if ClientMsgHandler and ClientMsgHandler.resetSessionBridgeState then
        ClientMsgHandler.resetSessionBridgeState()
    end
    if ClientDispatcher and ClientDispatcher.clearModuleData then
        ClientDispatcher.clearModuleData()
    end
    if PlayerStore and PlayerStore.ClearCache then
        PlayerStore.ClearCache()
    end
    if MarketPage and MarketPage.resetSessionData then
        MarketPage.resetSessionData()
    end
    if CharacterPanel and CharacterPanel.resetSessionData then
        CharacterPanel.resetSessionData()
    end
    if TopBar and TopBar.resetSessionData then
        TopBar.resetSessionData()
    end
    enter0204ScenarioFired_    = false   -- 重置铁匠铺204触发标志，清档后可重新触发情景1/42/43
    townEntranceScenarioFired_ = false   -- 重置城镇入场触发标志，清档后可重新触发情景3/24/25/26
    IntroCutscene.reset()
    print(string.format("%s resetForNewSession DONE clock=%.4f →all flags reset, IntroCutscene ready", TAG, os.clock()))
end

--- 清除存档后请求返回大厅：重置客户端状态使其能接收区服列表，并通知服务端重推
function Client.requestReturnToLobby()
    local TAG = "[Client][DIAG-RESET]"
    print(string.format("%s requestReturnToLobby START clock=%.4f currentState=%s",
        TAG, os.clock(), tostring(currentState)))
    -- 重置客户端状态，使handleServerList 不会被STATE_IN_GAME 守卫拒绝消息
    currentState = STATE_CONNECTED
    serverListReceived_ = false
    saveResultReceived = false
    readySent = false
    print(string.format("%s requestReturnToLobby state→CONNECTED, flags cleared clock=%.4f", TAG, os.clock()))

    -- 通知服务端执行"返回大厅"流程（cleanupPlayer + 重推 RES_SERVER_LIST）
    local conn = network:GetServerConnection()
    if not conn then
        print(string.format("%s requestReturnToLobby ABORT →no server connection clock=%.4f", TAG, os.clock()))
        return
    end
    local vm = VariantMap()
    vm["Data"] = Variant("{}")
    conn:SendRemoteEvent(Protocol.REQ_NEW_GAME, true, vm)
    print(string.format("%s requestReturnToLobby DONE →sent REQ_NEW_GAME clock=%.4f", TAG, os.clock()))
end

--- 转区前预置网络状态，避免 RES_SERVER_LIST 在 STATE_IN_GAME 下被丢弃
function Client.prepareForServerSelectReturn()
    currentState = STATE_CONNECTED
    serverListReceived_ = false
    saveResultReceived = false
    readySent = false
    pendingSelectServerId_ = nil
end

--- 请求服务端返回选服并推送区服列表（不清档；调用方需先 prepareForServerSelectReturn）
function Client.requestReturnToServerSelect()
    print("[Client] requestReturnToServerSelect")
    local conn = network:GetServerConnection()
    if not conn then
        print("[Client] requestReturnToServerSelect ABORT →no server connection")
        return false
    end
    local vm = VariantMap()
    vm["Data"] = Variant("{}")
    conn:SendRemoteEvent(Protocol.REQ_RETURN_SERVER_SELECT, true, vm)
    return true
end

--- 特权卡转区成功后返回选服界面
function Client.transitionToServerSelectAfterTransfer()
    print("[Client] transitionToServerSelectAfterTransfer")

    GameBGM.stop()
    GameSFX.stop()

    if ArenaBattleScene.isOpen()       then ArenaBattleScene.close()       end
    if ArenaPage.isOpen()              then ArenaPage.close()              end
    if MarketPage.isOpen()             then MarketPage.close()             end
    if TavernPage.isOpen()             then TavernPage.close()             end
    if BlacksmithPage.isOpen()         then BlacksmithPage.close()         end
    if ChurchPage.isOpen()             then ChurchPage.close()             end
    if GuildPage.isOpen()              then GuildPage.close()              end
    if SignInPanel.isOpen()            then SignInPanel.close()            end
    if MailPanel.isOpen()              then MailPanel.close()              end
    if BackpackPanel.isOpen()          then BackpackPanel.close()          end
    if TaskPanel.isOpen()              then TaskPanel.close()              end
    if HeroRosterPanel.isVisible()     then HeroRosterPanel.hide()         end
    if RewardPopup.isOpen()            then RewardPopup.close()            end
    if OfflineRewardPanel.isOpen()     then OfflineRewardPanel.close()     end
    if LevelUpPopup.isOpen()           then LevelUpPopup.destroy()         end
    if PlayerInfoPanel.isOpen()        then PlayerInfoPanel.close()        end
    if LootBoxPage.isVisible()         then LootBoxPage.hide()             end
    if RedeemCodePanel.isOpen()        then RedeemCodePanel.close()        end
    if AnnouncementPanel.isOpen()      then AnnouncementPanel.close()      end
    if GMConsolePanel.isOpen()         then GMConsolePanel.close()         end
    if RelicReforgePanel.isVisible()   then RelicReforgePanel.hide()       end
    if DungeonBattleScene.isOpen()     then DungeonBattleScene.close()     end
    if TowerBattleScene.isActive()     then TowerBattleScene.close()       end
    if ArenaOpponentDialog.isOpen()    then ArenaOpponentDialog.close()    end

    showOverlay = false
    Client.prepareForServerSelectReturn()
    Client.resetForNewSession()
    StartScreen.reopen(scene_)
    print("[Client] waiting for server-pushed ServerList after privilege transfer")
end

function Client.Stop()
    GameAlgoService.OnSessionEnd()
    SpinePowerUpEffect.destroy()
    GameState.unbindFromPlayerStore()
    PlayerStore.Cleanup()
    ClientDispatcher.reset()
    if vg then
        nvgDelete(vg)
        vg = nil
    end
end

-- Update 安全防护变量（自动重新订阅机制+ pcall 错误追踪）
local _diag_errorCount = 0
local _diag_lastError = nil
local _diag_updateFrameNum = 0        -- update 总帧计数（pcall 外递增，零开销）
local _diag_renderLastSeenFrame = 0   -- 渲染侧上次看到的 update 帧号
local _diag_renderStallCount = 0      -- 连续检测到 update 帧号未变化的渲染帧数

-- ======================== 渲染 ========================

--- 绘制遮罩层（加载/断线/错误等状态）
local function drawOverlay()
    if not showOverlay then return end

    -- 半透明黑色背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenDesignW, screenDesignH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    -- 状态文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, screenDesignW / 2, screenDesignH / 2, overlayText)
end

function HandleNanoVGRender_Client(eventType, eventData)
    if not vg then return end

    -- 横屏 PC 多面板（changeForJourney）：状态感知 letterbox
    if HORIZON_MODE then
        if not H_skipDone and StartScreen.isOpen() then
            H_skipDone = true
            StartScreen.skipForReconnect()
            DarkTitleScreen.open()  -- [DarkTitleScreen] 竖屏标题被跳过，改以横屏暗黑标题呈现
        end
        if StartScreen.isOpen() or LoadingScreen.isOpen() or LetterIntro.isOpen() then
            local ss = math.min(logicalW / 1080, logicalH / 2400)
            scale = ss
            -- 外层 nvgScale(scale) 会缩放 translate 值：偏移需除以 scale（缩放空间语义）
            designOffsetX = (logicalW - 1080 * ss) / (2 * ss)
            designOffsetY = (logicalH - 2400 * ss) / (2 * ss)
        else
            local vox, voy, vs = ViewportH.layout(logicalW, logicalH)
            H_ox, H_oy, H_s = vox, voy, vs
            scale = vs
            designOffsetX = (vox + ViewportH.PANELS.center.bx * vs) / vs
            designOffsetY = voy / vs
        end
    end

    nvgBeginFrame(vg, logicalW, logicalH, dpr)

    if HORIZON_MODE then
        -- 全窗口底色
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, logicalW, logicalH)
        nvgFillColor(vg, nvgRGBA(14, 14, 22, 255))
        nvgFill(vg)
        -- 左右面板（独立变换，主渲染缩进中面板）
        if currentState == STATE_IN_GAME and not StartScreen.isOpen() and not LoadingScreen.isOpen() and not LetterIntro.isOpen() then
            nvgSave(vg)
            nvgResetTransform(vg)
            ViewportH.begin(vg, ViewportH.PANELS.left, H_ox, H_oy, H_s)
            TownScene.draw(vg)
            BlacksmithPage.draw(vg)
            ChurchPage.draw(vg)
            TavernPage.draw(vg)
            ArenaPage.draw(vg)
            MarketPage.draw(vg)
            GuildPage.draw(vg)
            ViewportH.finish(vg)
            ViewportH.begin(vg, ViewportH.PANELS.right, H_ox, H_oy, H_s)
            CharacterPanel.draw(vg)
            ViewportH.finish(vg)
            nvgRestore(vg)
        end
    end

    nvgScale(vg, scale, scale)

    if not HORIZON_MODE then
    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenDesignW, screenDesignH)
    nvgFillColor(vg, nvgRGBA(25, 25, 35, 255))
    nvgFill(vg)
    end

    -- 开始界面（最高优先级，覆盖所有内容）
    if StartScreen.isOpen() then
        nvgSave(vg)
        nvgTranslate(vg, designOffsetX, designOffsetY)
        StartScreen.draw(vg)
        VersionMismatchPopup.draw(vg)
        nvgRestore(vg)
        nvgEndFrame(vg)
        return
    end

    -- 加载界面（第二优先级）
    if LoadingScreen.isOpen() then
        nvgSave(vg)
        nvgTranslate(vg, designOffsetX, designOffsetY)
        LoadingScreen.draw(vg)
        nvgRestore(vg)
        nvgEndFrame(vg)
        return
    end

    if currentState == STATE_IN_GAME then
      local _rok, _rerr = pcall(function()
        -- 调试面板
        DebugPanel.draw(vg, designOffsetX, screenDesignW)

        -- 进入设计空间
        nvgSave(vg)
        nvgTranslate(vg, designOffsetX, designOffsetY)

        -- 竞技场副本对战全屏优先（覆盖所有其他界面）
        local arenaBattleOpen = ArenaBattleScene.isOpen()
        local dungeonBattleOpen = DungeonBattleScene.isOpen()
        local towerBattleOpen = TowerBattleScene.isActive()
        if arenaBattleOpen then
            ArenaBattleScene.draw(vg)
            -- 不绘制TopBar/BottomNav
        elseif towerBattleOpen then
            TowerBattleScene.draw(vg)
            -- 不绘制TopBar/BottomNav
        elseif dungeonBattleOpen then
            DungeonBattleScene.draw(vg)
            -- 不绘制TopBar/BottomNav
        else
            local tabIndex = BottomNav.getSelectedIndex()

            --- 绘制指定 tab 的页面内容
            local function drawTabPage(idx)
                if idx == 1 then
                    CharacterPanel.draw(vg)
                elseif idx == 2 then
                    DiaryPage.draw(vg)
                elseif idx == 3 then
                    BattleScene.draw(vg)
                elseif idx == 4 then
                    TownScene.draw(vg)
                    BlacksmithPage.draw(vg)
                    ChurchPage.draw(vg)
                    TavernPage.draw(vg)
                    ArenaPage.draw(vg)
                    MarketPage.draw(vg)
                    GuildPage.draw(vg)
                elseif idx == 5 then
                    DungeonPage.draw(vg)
                end
            end

            if pageTrans.active then
                -- 过渡动画：旧页面淡出，新页面从下方弹起淡入
                local t = easeOutBack(pageTrans.progress)   -- easeOutBack 回弹，呼应标签弹起感
                local RISE_DIST = 80  -- 新页面起始偏移量（设计像素）
                local cx = screenDesignW * 0.5
                local cy = screenDesignH * 0.5

                -- 旧页面：快速淡出（前半段结束）
                local oldAlpha = math.max(0, 1 - pageTrans.progress * 2)
                nvgSave(vg)
                nvgGlobalAlpha(vg, oldAlpha)
                drawTabPage(pageTrans.fromIndex)
                nvgRestore(vg)

                -- 新页面：从下方RISE_DIST px 处上升+ 从0.96 缩放到1.0 + 淡入
                local newAlpha  = math.min(1, pageTrans.progress * 1.5)
                local offsetY   = RISE_DIST * (1 - t)                 -- 从下方升起
                local pageScale = 0.96 + 0.04 * t                     -- 0.96 →1.0

                nvgSave(vg)
                nvgGlobalAlpha(vg, newAlpha)
                nvgTranslate(vg, cx, cy + offsetY)
                nvgScale(vg, pageScale, pageScale)
                nvgTranslate(vg, -cx, -cy)
                drawTabPage(pageTrans.toIndex)
                nvgRestore(vg)
            else
                drawTabPage(tabIndex)
            end

            local detailOpen = CharacterPanel.isDetailOpen()
            local smithOpen  = BlacksmithPage.isOpen()
            local churchOpen = ChurchPage.isOpen()
            local tavernOpen = TavernPage.isOpen()
            local arenaOpen  = ArenaPage.isOpen()
            local marketOpen = MarketPage.isOpen()
            local guildOpen  = GuildPage.isOpen()
            local signInOpen = SignInPanel.isOpen()
            local backpackOpen = BackpackPanel.isOpen()
            local taskOpen   = TaskPanel.isOpen()
            if not detailOpen and not smithOpen and not churchOpen and not tavernOpen and not arenaOpen and not marketOpen and not guildOpen and not signInOpen and not backpackOpen and not taskOpen then
                if tabIndex ~= 5 then
                    TopBar.setTrainingDummyVisible(true)
                    TopBar.draw(vg)
                end
                BottomNav.draw(vg)
            elseif taskOpen and not detailOpen and not smithOpen and not churchOpen and not tavernOpen and not arenaOpen and not guildOpen and not signInOpen and not backpackOpen then
                local animP = TaskPanel.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(vg)
                    nvgGlobalAlpha(vg, fadeAlpha)
                    TopBar.setTrainingDummyVisible(true)
                    TopBar.draw(vg)
                    BottomNav.draw(vg)
                    nvgRestore(vg)
                end
            elseif backpackOpen and not detailOpen and not smithOpen and not churchOpen and not tavernOpen and not arenaOpen and not guildOpen and not signInOpen then
                local animP = BackpackPanel.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(vg)
                    nvgGlobalAlpha(vg, fadeAlpha)
                    TopBar.setTrainingDummyVisible(true)
                    TopBar.draw(vg)
                    BottomNav.draw(vg)
                    nvgRestore(vg)
                end
            elseif signInOpen and not detailOpen and not smithOpen and not churchOpen and not tavernOpen and not arenaOpen and not guildOpen then
                local animP = SignInPanel.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(vg)
                    nvgGlobalAlpha(vg, fadeAlpha)
                    TopBar.setTrainingDummyVisible(true)
                    TopBar.draw(vg)
                    BottomNav.draw(vg)
                    nvgRestore(vg)
                end
            elseif arenaOpen and not detailOpen and not smithOpen and not churchOpen and not tavernOpen then
                local animP = ArenaPage.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(vg)
                    nvgGlobalAlpha(vg, fadeAlpha)
                    TopBar.setTrainingDummyVisible(true)
                    TopBar.draw(vg)
                    BottomNav.draw(vg)
                    nvgRestore(vg)
                end
            elseif marketOpen and not detailOpen and not smithOpen and not churchOpen and not tavernOpen and not arenaOpen and not guildOpen then
                local animP = MarketPage.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(vg)
                    nvgGlobalAlpha(vg, fadeAlpha)
                    TopBar.setTrainingDummyVisible(true)
                    TopBar.draw(vg)
                    BottomNav.draw(vg)
                    nvgRestore(vg)
                end
            elseif guildOpen and not detailOpen and not smithOpen and not churchOpen and not tavernOpen and not arenaOpen and not marketOpen then
                local animP = GuildPage.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(vg)
                    nvgGlobalAlpha(vg, fadeAlpha)
                    TopBar.setTrainingDummyVisible(true)
                    TopBar.draw(vg)
                    BottomNav.draw(vg)
                    nvgRestore(vg)
                end
            elseif tavernOpen and not detailOpen and not smithOpen and not churchOpen then
                local animP = TavernPage.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(vg)
                    nvgGlobalAlpha(vg, fadeAlpha)
                    TopBar.setTrainingDummyVisible(true)
                    TopBar.draw(vg)
                    BottomNav.draw(vg)
                    nvgRestore(vg)
                end
            elseif churchOpen and not detailOpen and not smithOpen then
                local animP = ChurchPage.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(vg)
                    nvgGlobalAlpha(vg, fadeAlpha)
                    TopBar.setTrainingDummyVisible(true)
                    TopBar.draw(vg)
                    BottomNav.draw(vg)
                    nvgRestore(vg)
                end
            end
        end

        HeroRosterPanel.draw(vg)

        -- 玩家信息弹窗（头像点击打开）
        PlayerInfoPanel.draw(vg)

        -- 战利品全屏页面（在RewardPopup 之前，覆盖游戏画面）
        LootBox.drawPage(vg)
        -- 自动分解设置弹窗（standalone 模式：从战利品面板直接调起，不打开铁匠铺）
        BlacksmithPage.drawAutoDecomposePopupStandalone(vg)
        -- 奖励弹窗（最顶层）
        RewardPopup.draw(vg)
        -- 冒险等级提升弹窗（最顶层）
        LevelUpPopup.draw(vg)
        -- 离线收益面板（最顶层弹窗）
        OfflineRewardPanel.draw(vg)
        -- 战斗力提升特效（叠加在弹窗之上）
        SpinePowerUpEffect.draw(vg)
        -- 更新提醒弹窗（最最顶层）
        UpdateNoticePopup.draw(vg)

        -- 轮回 CG 视频（覆盖所有游戏UI）
        if SamsaraCG.isActive() then
            SamsaraCG.draw(vg)
        end

        -- 新手过场动画（覆盖所有游戏UI）
        if IntroCutscene.isActive() then
            IntroCutscene.draw(vg)
        end

        -- 情景对话（覆盖所有游戏UI，紧接在过场动画之后）
        if ScenarioDialogue.isActive() then
            ScenarioDialogue.draw()
        end

        -- 选择初始角色界面（情景对话结束后显示）
        if CharacterSelect.isActive() then
            CharacterSelect.draw()
        end

        -- 新手引导蒙层（覆盖在所有游戏UI 之上，情景对话之后）
        if TutorialManager.isActive() then
            TutorialManager.draw()
        end

        nvgRestore(vg)
      end) -- pcall end (render)
      if not _rok then
        print("[Client] render error: " .. tostring(_rerr))
      end
    end

    -- 遮罩层（最顶层）
    drawOverlay()

    -- Update 安全网：检测update handler 是否存活，停滞时自动重新订阅
    do
        if _diag_updateFrameNum == _diag_renderLastSeenFrame then
            _diag_renderStallCount = _diag_renderStallCount + 1
        else
            _diag_renderStallCount = 0
            _diag_renderLastSeenFrame = _diag_updateFrameNum
        end
        -- 连续 ~2秒未更新→重新订阅 Update 事件
        if _diag_renderStallCount == 120 then
            print("[Client] Update handler stalled, re-subscribing...")
            SubscribeToEvent("Update", "HandleUpdate_Client")
        end
    end

    -- 广告加载指示器（绝对顶层，覆盖所有UI）
    if AdManager.IsLoading() then
        local t   = os.clock()
        local bh  = 68
        local bw  = 300
        local px  = designOffsetX + (DESIGN_W - bw) / 2
        local py  = designOffsetY + (DESIGN_H - bh) / 2
        local br  = bh / 2  -- pill 形圆角

        -- 半透明深色背景气泡
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px, py, bw, bh, br)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 185))
        nvgFill(vg)

        -- 转圈动画（旋转弧线）
        local spx = px + bh / 2
        local spy = py + bh / 2
        local sr  = 16.0
        local a0  = t * 3.5                         -- 转速：3.5 rad/s
        local a1  = a0 + math.pi * 1.4              -- 弧长≈252°
        nvgBeginPath(vg)
        nvgArc(vg, spx, spy, sr, a0, a1, NVG_CW)
        nvgStrokeColor(vg, nvgRGBA(255, 215, 100, 240))
        nvgStrokeWidth(vg, 3.5)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)

        -- 文字 "广告加载中 + 动态省略号（每 0.5s 增一个点，~3 循环）
        local dotCount = math.floor(t * 2) % 4
        local label    = "广告加载中" .. string.rep(".", dotCount)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 28)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(vg, spx + sr + 18, spy, label, nil)
    end

    -- [DarkTitleScreen] 横屏标题（全窗口逻辑坐标，覆盖一切直至点击淡出）
    if HORIZON_MODE and DarkTitleScreen.isOpen() then
        nvgResetTransform(vg)
        DarkTitleScreen.draw(vg, logicalW, logicalH)
    end

    -- [LetterIntro] 先祖来信（设计空间 1080×2400，letterbox 同 StartScreen）
    if LetterIntro.isOpen() then
        nvgResetTransform(vg)
        local ssL = math.min(logicalW / 1080, logicalH / 2400)
        nvgTranslate(vg, (logicalW - 1080 * ssL) * 0.5, (logicalH - 2400 * ssL) * 0.5)
        nvgScale(vg, ssL, ssL)
        LetterIntro.draw(vg)
    end

    nvgEndFrame(vg)
end

-- ======================== 更新 ========================

function HandleUpdate_Client(eventType, eventData)
    _diag_updateFrameNum = _diag_updateFrameNum + 1  -- 帧计数（供渲染安全网检测）

  -- pcall 保护整个函数体，防止引擎取消订阅 Update 事件
  local _ok, _err = pcall(function()
    local dt = eventData["TimeStep"]:GetFloat()

    -- ClientDispatcher tick（检查批次超时）→始终运行，不受StartScreen 阻断
    ClientDispatcher.update(dt)

    -- 广告管理器每帧更新（三重超时计时）
    AdManager.Update(dt)

    GameAlgoService.Update(dt)

    -- ===== 重试机制（始终运行，不受 StartScreen 阻断）====

    -- 0) STATE_CONNECTING 超时检测：连接阶段无限等待保护
    if currentState == STATE_CONNECTING and not connectingTimeoutShown then
        connectingTimer = connectingTimer + dt
        if connectingTimer >= CONNECTION_TIMEOUT then
            connectingTimeoutShown = true
            currentState = STATE_DISCONNECTED
            print("[Client] connection timeout after " .. CONNECTION_TIMEOUT .. "s, state -> DISCONNECTED")
            if LoadingScreen.isOpen() then
                LoadingScreen.setStatusText("连接超时")
                LoadingScreen.setTapToRetry(function()
                    print("[Client] user tap-to-retry from connection timeout")
                    connectingTimeoutShown = false
                    connectingTimer = 0
                    currentState = STATE_CONNECTING
                    LoadingScreen.clearTapToRetry()
                    LoadingScreen.setStatusText("")
                end)
            else
                overlayText = "连接超时\n请重新进入游戏"
                showOverlay = true
            end
        end
    end

    -- 0.5) STATE_RECONNECTING 超时检测：游戏中断线后等待重连，超时则提示重新进入
    if currentState == STATE_RECONNECTING then
        reconnectTimer = reconnectTimer + dt
        if reconnectTimer >= RECONNECT_TIMEOUT then
            currentState = STATE_DISCONNECTED
            print("[Client] reconnect timeout after " .. RECONNECT_TIMEOUT .. "s, state -> DISCONNECTED")
            overlayText = "连接已断开\n请重新进入游戏"
            showOverlay = true
        end
    end

    -- 点击重试回调（用于ClientReady / 数据加载重试用尽后的手动重试）
    local function resetAndRetry()
        print("[Client] user tap-to-retry, resetting retry state")
        resetRetryState()
        if LoadingScreen.isOpen() then
            LoadingScreen.clearTapToRetry()
            LoadingScreen.setStatusText("")
        end
        sendClientReady()
    end

    if currentState == STATE_LOADING then
        -- 0.8) 区服列表等待超时：新连接发出 ClientReady 后，若服务端全局档案加载/PDM 回调异常
        -- 没有推送 RES_SERVER_LIST，StartScreen 会一直显示“选择服务器”加载态。该阶段不能依赖
        -- saveResultReceived，因为 Phase 1 本来就不会发送 RES_SAVE_RESULT。
        if readySent and not serverListReceived_ and not pendingSelectServerId_ then
            serverListRetryTimer = serverListRetryTimer + dt
            if serverListRetryTimer >= READY_RETRY_INTERVAL then
                serverListRetryTimer = 0
                if serverListRetryCount < READY_RETRY_MAX then
                    serverListRetryCount = serverListRetryCount + 1
                    print("[Client] ServerList timeout, retrying ClientReady (" .. serverListRetryCount .. "/" .. READY_RETRY_MAX .. ")")
                    sendClientReady()
                else
                    print("[Client] ServerList max retries exceeded, waiting for tap-to-retry")
                    if LoadingScreen.isOpen() then
                        LoadingScreen.setStatusText("区服列表加载失败")
                        LoadingScreen.setTapToRetry(resetAndRetry)
                    else
                        overlayText = "区服列表加载失败\n请重新进入游戏"
                        showOverlay = true
                    end
                end
            end
        end

        -- 1) ClientReady / SELECT_SERVER 重试：发送后未收到SaveResult →重发
        if readySent and not saveResultReceived and serverListReceived_ then
            readyRetryTimer = readyRetryTimer + dt
            local retryInterval = pendingSelectServerId_ and SELECT_SERVER_RETRY_INTERVAL or READY_RETRY_INTERVAL
            if readyRetryTimer >= retryInterval then
                readyRetryTimer = 0
                if readyRetryCount < READY_RETRY_MAX then
                    readyRetryCount = readyRetryCount + 1
                    -- 🔴 修复：选服超时时重发 SELECT_SERVER（而非 ClientReady），
                    -- 避免弹回选服界面。只有非选服场景才重发 ClientReady。
                    if pendingSelectServerId_ then
                        print("[Client] SELECT_SERVER timeout, retrying (" .. readyRetryCount .. "/" .. READY_RETRY_MAX .. ")")
                        if LoadingScreen.isOpen() then
                            LoadingScreen.setStatusText("加载数据中..(重试 " .. readyRetryCount .. "/" .. READY_RETRY_MAX .. ")")
                        end
                        Client.sendAction(Protocol.ACTION_TYPES.SELECT_SERVER, { serverId = pendingSelectServerId_ })
                    else
                        print("[Client] ClientReady timeout, retrying (" .. readyRetryCount .. "/" .. READY_RETRY_MAX .. ")")
                        if LoadingScreen.isOpen() then
                            LoadingScreen.setStatusText("等待服务器响应..(重试 " .. readyRetryCount .. "/" .. READY_RETRY_MAX .. ")")
                        end
                        sendClientReady()
                    end
                else
                    -- 超过最大重试次数→允许点击重试
                    print("[Client] ClientReady max retries exceeded, waiting for tap-to-retry")
                    if LoadingScreen.isOpen() then
                        LoadingScreen.setStatusText("服务器无响应")
                        LoadingScreen.setTapToRetry(resetAndRetry)
                    else
                        overlayText = "服务器无响应\n请重新进入游戏"
                        showOverlay = true
                    end
                end
            end
        end

        -- 2) 数据加载超时：收到SaveResult 后15s 后数据仍未收齐→重发 ClientReady
        if saveResultReceived and not ClientDispatcher.hasData() then
            dataLoadTimer = dataLoadTimer + dt
            if dataLoadTimer >= DATA_LOAD_TIMEOUT then
                local missingModules = ""
                if ClientDispatcher.getMissingRequiredModules then
                    missingModules = ClientDispatcher.getMissingRequiredModules()
                end
                print("[Client] data load timeout, missing modules=[" .. tostring(missingModules) .. "]")
                if dataLoadRetryCount < READY_RETRY_MAX then
                    dataLoadRetryCount = dataLoadRetryCount + 1
                    dataLoadTimer = 0
                    print("[Client] data load timeout, re-requesting (" .. dataLoadRetryCount .. "/" .. READY_RETRY_MAX .. ")")
                    -- 重置 saveResult 状态，重新走ClientReady 流程
                    saveResultReceived = false
                    readyRetryCount = 0
                    sendClientReady()
                    if LoadingScreen.isOpen() then
                        LoadingScreen.setStatusText("加载数据中..(重试 " .. dataLoadRetryCount .. "/" .. READY_RETRY_MAX .. ")")
                    else
                        overlayText = "加载数据中..\n(重试 " .. dataLoadRetryCount .. "/" .. READY_RETRY_MAX .. ")"
                    end
                else
                    -- 超过最大重试次数，允许点击重试
                    print("[Client] data load max retries exceeded, waiting for tap-to-retry")
                    if LoadingScreen.isOpen() then
                        LoadingScreen.setStatusText("数据加载失败")
                        LoadingScreen.setTapToRetry(resetAndRetry)
                    else
                        overlayText = "数据加载失败\n请重新进入游戏"
                        showOverlay = true
                    end
                end
            end
        end

        -- 3) 数据收齐：SaveResult 已收到+ Dispatcher 已有模块数据 →进入游戏
        if saveResultReceived and ClientDispatcher.hasData() then
            print("[Client] all data received, refreshing power cache before STATE_IN_GAME")
            if CharacterPanel.refreshPower then
                CharacterPanel.refreshPower()
                TopBar.setTotalPower(CharacterPanel.getTotalPower())
            end
            currentState = STATE_IN_GAME
            dataLoadTimer = 0
            pendingSelectServerId_ = nil  -- 加载成功，清除选服重试标记
            showOverlay = false
            if LoadingScreen.isOpen() then
                LoadingScreen.setStatusText("")
                LoadingScreen.clearTapToRetry()
            end
            -- 数据加载完成后，重试未完成的 AD_CONFIRM（重连场景：之前发到死连接上的）
            local AdManager = require("systems.AdManager")
            if AdManager.RetryNow then AdManager.RetryNow() end
        end
    end

    -- 开始界面更新（视频+动画）→网络连接/重试已在上方运行，此处仅跳过游戏 UI 更新
    if StartScreen.isOpen() then
        StartScreen.update(dt)
        return
    end

    -- [DarkTitleScreen] 横屏标题动画（游戏/加载在标题下方继续进行）
    if DarkTitleScreen.isOpen() then
        DarkTitleScreen.update(dt)
    end

    -- [LetterIntro] 先祖来信动画（逐行显墨/封印/淡出）
    if LetterIntro.isOpen() then
        LetterIntro.update(dt)
    end

    -- 加载界面更新 →网络进度 + 资源下载进度（由 LoadingScreen 内部组合）
    if LoadingScreen.isOpen() then
        if currentState == STATE_IN_GAME then
            LoadingScreen.setNetworkProgress(1.0)
        elseif currentState == STATE_SERVER_SELECT then
            -- 选服阶段：StartScreen 仍在显示，进度条保持低位
            LoadingScreen.setNetworkProgress(0.4)
        elseif currentState == STATE_LOADING then
            if saveResultReceived then
                LoadingScreen.setNetworkProgress(0.7)
            elseif readySent then
                LoadingScreen.setNetworkProgress(0.5)
            else
                LoadingScreen.setNetworkProgress(0.3)
            end
        elseif currentState == STATE_CONNECTED then
            LoadingScreen.setNetworkProgress(0.2)
        elseif currentState == STATE_DISCONNECTED then
            LoadingScreen.setNetworkProgress(0)
        else -- STATE_CONNECTING
            LoadingScreen.setNetworkProgress(0.1)
        end
        LoadingScreen.update(dt)
        return
    end

    if currentState == STATE_IN_GAME then
        -- LoadingScreen 刚关闭
        if loadingScreenWasOpen_ and not LoadingScreen.isOpen() then
            loadingScreenWasOpen_ = false
            if CharacterPanel.refreshPower then
                CharacterPanel.refreshPower()
                TopBar.setTotalPower(CharacterPanel.getTotalPower())
                print("[Client] power cache refreshed after loading screen closed")
            end

            -- 判断是否需要播放开场剧情：roster 为空 = 新玩家尚未选择初始英雄
            local heroesData = PlayerStore.Get("heroes")
            local rosterEmpty = true
            if heroesData and heroesData.roster then
                for _ in pairs(heroesData.roster) do
                    rosterEmpty = false
                    break
                end
            end
            print("[Client] intro check: rosterEmpty=" .. tostring(rosterEmpty)
                .. " IntroCutscene.isFinished=" .. tostring(IntroCutscene.isFinished()))

            -- 获取 session 数据判断轮回状态
            local sessionData = PlayerStore.Get("session")
            local hasReincarnated = sessionData and sessionData.hasReincarnated or false

            if rosterEmpty and not IntroCutscene.isFinished() then
                -- roster 为空 = 新玩家，启动过场动画 + 开场剧情
                print("[Client] roster is empty (new player), starting intro cutscene")
                GameBGM.start()
                GameSFX.start()
                GameBGM.setScene("letter", { fromStart = true })  -- [LetterIntro] 暗黑烛光读信氛围
                -- [LetterIntro] 先祖来信 → 睁眼过场 → 情景对话 → 选角
                LetterIntro.start(function()
                IntroCutscene.start(function()
                    GameBGM.setScene("battle", { fromStart = true })  -- [LetterIntro] 情景1"出发"切回主曲
                    -- 过场动画结束 →衔接情景对话 1（introCompleted 由服务端在选择英雄时标记）
                    print("[Client] intro cutscene finished")
                    print("[Client] starting scenario dialogue 1")
                    local scenarioConfig = ScenarioDialogueConfig.SCENARIO_1
                    scenarioConfig.onFinish = function()
                        -- 情景对话1结束 →选择初始角色
                        print("[Client] scenario dialogue 1 finished, opening character select")
                        CharacterSelect.show({
                            background = scenarioConfig.background,
                            onFinish = function(heroId)
                                print("[Client] character selected: heroId=" .. heroId)
                                Client.sendAction(Protocol.ACTION_TYPES.SELECT_INITIAL_HERO, {
                                    heroId = heroId,
                                })
                            end,
                        })
                    end
                    ScenarioDialogue.show(scenarioConfig)
                end)
                end)  -- [LetterIntro] 回调闭合
            elseif hasReincarnated then
                if rosterEmpty then
                    -- 极端情况：尚无角色但标记轮回（补播入场动画）
                    print("[Client] reincarnated new player, replaying intro cutscene (no story)")
                    GameBGM.start()
                    GameSFX.start()
                    IntroCutscene.reset()
                    IntroCutscene.start(function()
                        print("[Client] reincarnation intro finished, clearing flag")
                        Client.sendAction(Protocol.ACTION_TYPES.CLEAR_REINCARNATION, {})
                    end)
                else
                    -- 已有角色：正常轮回流程内应已播放过动画，清除旧存档残留标记
                    print("[Client] clearing stale hasReincarnated flag (skip replay on relogin)")
                    Client.sendAction(Protocol.ACTION_TYPES.CLEAR_REINCARNATION, {})
                    GameBGM.start()
                    GameSFX.start()
                end
            else
                -- roster 不为空= 已选择过英雄，跳过开场剧情
                print("[Client] roster not empty, skipping cutscene")
                GameBGM.start()
                GameSFX.start()
            end

            -- 检测Spine 不可用→弹出更新提醒
            if not updateNoticeShown_ and LoadingScreen.isSpineNotSupported() then
                updateNoticeShown_ = true
                UpdateNoticePopup.show()
            end
        end

        -- 轮回 CG 视频更新（播放期间阻止其他UI 更新和BGM 切换）
        if SamsaraCG.isActive() then
            SamsaraCG.update(dt)
            return  -- CG 视频期间不处理游戏UI / BGM
        end

        -- 新手过场动画更新（播放期间阻止其他UI 更新）BGM 切换）
        if IntroCutscene.isActive() then
            IntroCutscene.update(dt)
            return  -- 过场期间不处理游戏UI / BGM
        end

        -- 情景对话更新
        if ScenarioDialogue.isActive() then
            ScenarioDialogue.update(dt)
            if ScenarioDialogue.isFullscreen() then
                return  -- 大情景：阻止其他 UI 更新
            end
            -- 小情景：继续更新游戏画面
        end

        -- 新手引导更新（每帧清空热点缓存，让UI 模块重新注册）
        TutorialManager.clearHotspots()
        TutorialManager.update(dt)

        -- 选择初始角色界面（播放期间阻止其他UI 更新）
        if CharacterSelect.isActive() then
            CharacterSelect.update(dt)
            return
        end

        -- 自动弹出离线收益面板（使用服务端推送的数据，独立于 LoadingScreen 检查）
        if not offlineRewardAutoShown_ and not LoadingScreen.isOpen() and offlineRewardData_ then
            offlineRewardAutoShown_ = true
            local rewardData = offlineRewardData_
            offlineRewardData_ = nil  -- 消费后清除
            rewardData.privilegePoint = GameState.getPrivilegePoint()
            rewardData.onClaim = function(bonusClaimed, usePrivilege)
                print("[OfflineRewardPanel] claimed, bonusClaimed=" .. tostring(bonusClaimed)
                    .. " usePrivilege=" .. tostring(usePrivilege))
                Client.sendAction(Protocol.ACTION_TYPES.CLAIM_OFFLINE_REWARDS, {
                    claimBonus   = bonusClaimed or false,
                    usePrivilege = usePrivilege or false,
                })
            end
            OfflineRewardPanel.show(rewardData)
            print("[Client] auto-showed OfflineRewardPanel after LoadingScreen closed")
        end

        -- 登录补发奖励弹窗（离线收益面板关闭后再展示，避免叠层）
        if not deferredRewardPopupShown_
                and not LoadingScreen.isOpen()
                and not OfflineRewardPanel.isOpen()
                and ClientMsgHandler.hasPendingDeferredRewardPopup() then
            local pending = ClientMsgHandler.takePendingDeferredRewardPopup()
            if pending then
                deferredRewardPopupShown_ = true
                RewardPopup.show(pending.title, pending.rewards, { subtitle = pending.subtitle })
                print("[Client] auto-showed deferred reward popup: " .. tostring(pending.title))
            end
        end

        BottomNav.update(dt)
        local tabIndex = BottomNav.getSelectedIndex()

        -- 检测tab 切换：离开/进入战斗页面 + BGM 氛围切换
        if tabIndex ~= lastTabIndex then
            print("[TAB_SWITCH] " .. tostring(lastTabIndex) .. " →" .. tostring(tabIndex)
                .. " | smith=" .. tostring(BlacksmithPage.isOpen())
                .. " church=" .. tostring(ChurchPage.isOpen())
                .. " tavern=" .. tostring(TavernPage.isOpen())
                .. " arena=" .. tostring(ArenaPage.isOpen())
                .. " market=" .. tostring(MarketPage.isOpen())
                .. " guild=" .. tostring(GuildPage.isOpen()))
            if lastTabIndex == BATTLE_TAB and tabIndex ~= BATTLE_TAB then
                BattleScene.pause()
            elseif tabIndex == BATTLE_TAB and lastTabIndex ~= BATTLE_TAB then
                BattleScene.resume()
            end
            -- 首次切换到城镇Tab（tab 4）→ 触发情景 23（卫兵拦截）+ 英雄分支 24/25/26
            -- 旧存档兼容：冒险等级 >= 5 的玩家跳过，视为已经历过此段剧情
            -- townEntranceScenarioFired_ 防止本局内多次切 tab 时在 claim 回包到达前重复触发
            if tabIndex == 4 and GameState.getLevel() < 5
                    and not ScenarioDialogue.isActive()
                    and not townEntranceScenarioFired_ then
                local heroFollows = { [1]=24, [2]=25, [3]=26 }
                if not ClientScenario.isClaimed(23) then
                    -- 正常流程：从卫兵拦截情景开始
                    townEntranceScenarioFired_ = true
                    ClientScenario.playChain(23, heroFollows, nil)
                else
                    -- 旧存档补丁：23已领取但英雄分支未播→直接播英雄分支
                    -- 注意：只检查本玩家对应英雄的分支情景是否已领取。
                    -- 不能用anyHeroUnclaimed 遍历全部分支：heroFollows 三条分支，
                    -- 玩家只会 claim 自己英雄对应的那条，其余两条永远不会被claimed。
                    -- 导致每次重进游戏都重复触发）
                    local sessionData = PlayerStore.Get("session")
                    local heroId      = sessionData and sessionData.initialHeroId
                    local myFollowId  = heroId and heroFollows[heroId]
                    if myFollowId and not ClientScenario.isClaimed(myFollowId) then
                        townEntranceScenarioFired_ = true
                        ClientScenario.playChain(nil, heroFollows, nil)
                    else
                        -- 本玩家英雄分支已领取（或 session 未就绪）：标记本局不再检查
                        townEntranceScenarioFired_ = true
                    end
                end
            end
            -- 启动页面切换过渡动画
        end

        -- 通知引导系统当前所在的面板（enter_panel_* 类步骤推进）
        -- 放在 tab 切换块之外，确保玩家已在该tab 上时引导也能推进
        local TAB_PANEL_EVENTS = {
            [1] = "enter_panel_character",
            [2] = "enter_panel_diary",
            [3] = "enter_panel_battle",
            [4] = "enter_panel_town",
            [5] = "enter_panel_dungeon",
        }
        if TAB_PANEL_EVENTS[tabIndex] then
            TutorialManager.notifyEvent(TAB_PANEL_EVENTS[tabIndex])
        end

        if tabIndex ~= lastTabIndex then
            pageTrans.active    = true
            pageTrans.fromIndex = lastTabIndex
            pageTrans.toIndex   = tabIndex
            pageTrans.progress  = 0
            lastTabIndex = tabIndex
        end

        -- 推进过渡动画进度
        if pageTrans.active then
            pageTrans.progress = pageTrans.progress + dt / pageTrans.duration
            if pageTrans.progress >= 1 then
                pageTrans.progress = 1
                pageTrans.active   = false
            end
        end

        -- 安全保护：离开 tab4 时，强制关闭仍处理open 状态的城镇建筑页面
        -- 这些页面的state.open=false 仅在 draw() 中设置，而draw() 仅在 tab==4 时调用
        -- 如果 tab 在关闭动画期间切走，state.open 会永久卡住为 true，导致输入卡住
        if tabIndex ~= 4 then
            if BlacksmithPage.isOpen() then
                BlacksmithPage.forceClose()
            end
            if ChurchPage.isOpen() then
                ChurchPage.forceClose()
            end
            if TavernPage.isOpen() then
                TavernPage.forceClose()
            end
            if ArenaPage.isOpen() then
                ArenaPage.forceClose()
            end
            if MarketPage.isOpen() then
                MarketPage.forceClose()
            end
            if GuildPage.isOpen() then
                GuildPage.forceClose()
            end
        end

        -- ── BGM 轨道切换（优先级：城镇建筑> 标签页）──
        -- [LetterIntro] 开场链（信/过场/情景1）期间不自动切轨，轨道由开场链自控
        if not (LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive()) then
        do
            local bgmScene
            -- 城镇建筑
            if tabIndex == 4 and (BlacksmithPage.isOpen()
                or ChurchPage.isOpen()
                or TavernPage.isOpen()
                or ArenaPage.isOpen()
                or MarketPage.isOpen()
                or GuildPage.isOpen()) then
                bgmScene = "town_building"
            -- 标签页
            elseif tabIndex == 2 then bgmScene = "popup"
            elseif tabIndex == 3 then bgmScene = BattleScene.isInTerminalTemple() and "samsara" or "battle"
            elseif tabIndex == 4 then bgmScene = "town"
            else bgmScene = "other"
            end
            GameBGM.setScene(bgmScene)
        end
        end -- [LetterIntro] 守卫闭合
        GameBGM.update(dt)

        -- 竞技场副本对战更新（打开时独占）
        if ArenaBattleScene.isOpen() then
            ArenaBattleScene.update(dt)
        elseif TowerBattleScene.isActive() then
            TowerBattleScene.update(dt)
        elseif DungeonBattleScene.isOpen() then
            DungeonBattleScene.update(dt)
        else
            BattleScene.update(dt)
        end
        if tabIndex == 1 then
            CharacterPanel.update(dt)
        elseif tabIndex == 2 then
            DiaryPage.update(dt)
        elseif tabIndex == 5 then
            DungeonPage.update(dt)
        end

        -- 角标刷新（始终执行，不受当前 tab 限制）
        BottomNav.setBadge(2, DiaryPage.hasAnyClaimable(), "redDot")

        -- 铁匠铺分解红点（背包满时提示）
        local equipData_ = ClientDispatcher.get("equipment")
        local bagFull_ = equipData_ and EquipmentSystem.isInventoryFull(equipData_) or false
        TownScene.setSmithRedDot(bagFull_)
        BlacksmithPage.setDecomposeRedDot(bagFull_)

        -- 市场/竞技场建筑红点（与BottomNav 查询条件保持一致）
        TownScene.setMarketRedDot(MarketPage.hasPrivilegeRedDot())
        TownScene.setArenaRedDot(ArenaPage.hasTicketRedDot())

        -- 心跳发送（每15 秒发送一次，仅发事件名，不携带数据）
        heartbeatTimer = heartbeatTimer + dt
        if heartbeatTimer >= HEARTBEAT_INTERVAL then
            heartbeatTimer = heartbeatTimer - HEARTBEAT_INTERVAL
            local conn = network:GetServerConnection()
            if conn then
                conn:SendRemoteEvent(Protocol.REQ_HEARTBEAT, true)
            end
        end

        -- 战斗奖励批量上报（每 3 秒flush 一次）
        if #rewardBuffer > 0 then
            rewardFlushTimer = rewardFlushTimer + dt
            if rewardFlushTimer >= REWARD_FLUSH_INTERVAL then
                -- 取出缓冲区数据并清空
                local batch = rewardBuffer
                rewardBuffer = {}
                rewardFlushTimer = 0
                -- 上报服务端：服务端单次最多接受 30 条，2x 首通可能让 3 秒内击杀更多，按 30 条分包但仍保持真实 3 秒 flush 节奏
                print("[Client] flushing " .. #batch .. " kill rewards to server")
                local start = 1
                while start <= #batch do
                    local chunk = {}
                    local finish = math.min(start + 29, #batch)
                    for i = start, finish do
                        chunk[#chunk + 1] = batch[i]
                    end
                    Client.sendAction(Protocol.ACTION_TYPES.CLAIM_BATTLE_REWARDS, {
                        rewards = chunk,
                    })
                    start = finish + 1
                end
            end
        else
            rewardFlushTimer = 0
        end

        -- 一键合成批量超时保护：防止部分请求失败导致永不弹窗
        ClientMsgHandler.updateBatchMergeTimeout(dt)

        RewardPopup.update(dt)

        -- 首通奖励弹窗关闭后，播放排队中的情景对话
        -- 注意：必须先检查弹窗是否关闭，再消费pending，否则对话数据会丢失
        if not RewardPopup.isOpen() and not ScenarioDialogue.isActive() then
            local pend = ClientMsgHandler.consumePendingScenarioDialogue()
            if pend then
                print("[Client] 播放情景对话: scenarioId=" .. pend.scenarioId)
                ScenarioDialogue.show({
                    mode       = pend.config.mode,
                    background = pend.config.background,
                    steps      = pend.config.steps,
                    onFinish = function()
                        print("[Client] 情景对话结束，请求领取奖励 scenarioId=" .. pend.scenarioId)
                        Client.sendAction(Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD, {
                            scenarioId = pend.scenarioId,
                        })
                        TutorialManager.onScenarioClaimed(pend.scenarioId)
                    end,
                })
            end
        end

        -- 角色奖励弹窗关闭后，播放后续对话（4-16，无需领取奖励）
        if not RewardPopup.isOpen() and not ScenarioDialogue.isActive() then
            local pend = ClientMsgHandler.consumePendingFollowUpDialogue()
            if pend then
                print("[Client] 播放后续对话(角色跟上)")
                ScenarioDialogue.show({
                    mode       = pend.config.mode,
                    background = pend.config.background,
                    steps      = pend.config.steps,
                })
            end
        end

        LevelUpPopup.update(dt)
        OfflineRewardPanel.update(dt)
        TavernPage.update(dt)
        ArenaPage.update(dt)
        MarketPage.update(dt)
        PlayerInfoPanel.update(dt)
    end

  end) -- pcall end (整个函数）
  if not _ok then
    _diag_errorCount = _diag_errorCount + 1
    if _err ~= _diag_lastError or _diag_errorCount % 300 == 0 then
        _diag_lastError = _err
        print("[Client] update error (#" .. _diag_errorCount .. "): " .. tostring(_err))
    end
  end
end

function HandleScreenMode_Client(eventType, eventData)
    local ok, err = pcall(function()
        RecalcLayout()
        ClientInput.updateLayoutFull(dpr, scale, designOffsetX, designOffsetY)
        print("[Client] ScreenMode →" .. physW .. "x" .. physH .. " dpr=" .. dpr)
    end)
    if not ok then
        print("[Client] ScreenMode error: " .. tostring(err))
    end
end

--- 焦点恢复处理：切换/切微信/接电话/下拉通知栏回来后，重置计时器防止误判超时
function HandleInputFocus_Client(eventType, eventData)
    local ok, err = pcall(function()
        local hasFocus = eventData["Focus"]:GetBool()
        local minimized = eventData["Minimized"]:GetBool()
        print("[Client] InputFocus: focus=" .. tostring(hasFocus) .. " minimized=" .. tostring(minimized)
            .. " state=" .. tostring(currentState))

        -- 广告焦点变化通知必须在early return 之前，失焦也需要通知（暂停加载超时计时器）
        AdManager.OnFocusChange(hasFocus and not minimized)

        if not hasFocus or minimized then
            focusLostAt_ = os.time()
            return
        end

        -- 计算后台时长
        local bgDuration = 0
        if focusLostAt_ > 0 then
            bgDuration = os.time() - focusLostAt_
            focusLostAt_ = 0
        end

        if currentState == STATE_RECONNECTING then
            reconnectTimer = 0
            print("[Client] focus restored during RECONNECTING, timer reset")
        end
        if currentState == STATE_CONNECTING and not connectingTimeoutShown then
            connectingTimer = 0
            print("[Client] focus restored during CONNECTING, timer reset")
        end
        if currentState == STATE_DISCONNECTED and showOverlay then
            local conn = network:GetServerConnection()
            if conn then
                currentState = STATE_RECONNECTING
                reconnectTimer = 0
                overlayText = "正在连接服务端.."
                print("[Client] focus restored: connection exists, recovering from DISCONNECTED →RECONNECTING")
            end
        end

        -- 🔴 长时间后台（>30s）恢复后立即触发心跳，强制检测死连接
        -- 移动端NAT 超时通常 60-120s，49s 后台几乎必定导致连接死亡
        -- 设置 heartbeatTimer >= HEARTBEAT_INTERVAL 使下一帧立即发送心跳
        if bgDuration > 30 then
            heartbeatTimer = HEARTBEAT_INTERVAL
            print("[Client] focus restored after " .. bgDuration .. "s background, forcing immediate heartbeat")
        else
            heartbeatTimer = 0
        end
    end)
    if not ok then
        print("[Client] InputFocus error: " .. tostring(err))
    end
end


-- ============================================================================
-- 横屏 PC 多面板（changeForJourney）：Client 侧状态
-- 左面板：城镇功能页组；中面板：BottomNav 主视图 + 全屏战斗 + 弹窗层；右面板：角色
-- ============================================================================
ViewportH = require("core.Viewport")
HORIZON_MODE = true
H_SKIP_START = true
H_skipDone = false
H_ox, H_oy, H_s = 0, 0, 1

return Client
