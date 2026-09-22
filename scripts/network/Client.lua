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
local MarketPage       = require("ui.MarketPage")
local GuildPage        = require("ui.GuildPage")
local DungeonBattleScene  = require("ui.DungeonBattleScene")
local TowerBattleScene    = require("ui.TowerBattleScene")
local TowerBuffPick       = require("ui.TowerBuffPick")
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
local ScenarioDialogue   = require("ui.ScenarioDialogue")
local DungeonPage        = require("ui.DungeonPage")
local ScenarioDialogueConfig = require("config.ScenarioDialogueConfig")
local CharacterSelect  = require("ui.CharacterSelect")
local DrawUtil         = require("core.DrawUtil")
local TutorialManager  = require("systems.TutorialManager")
local TutorialConfig   = require("config.TutorialConfig")
local ClientMsgHandler = require("network.ClientMessageHandler")
local ClientScenario   = require("network.ClientScenarioHelper")
local ClientBoot       = require("network.ClientBoot")
local ClientRender     = require("network.ClientRender")
local ClientUpdate     = require("network.ClientUpdate")
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
local pendingIntroAfterTitle_ = false -- [LetterIntro] 等横屏标题关闭后再走开场链
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
    local conn = nil
    local okConn, got = pcall(function()
        return network:GetServerConnection()
    end)
    if okConn then
        conn = got
    end
    if not conn then
        local okLocal, handled = pcall(function()
            return require("network.Standalone").tryLocalAction(action, params)
        end)
        if okLocal and handled then
            return true
        end
        print("[Client] no server connection, cannot send action action=" .. tostring(action))
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
    LetterIntro.init(vg)      -- [LetterIntro] 书斋/火漆全窗口素材
    -- StartScreen 关闭后→打开 LoadingScreen（静态背景，接管 BGM）
    StartScreen.setOnStart(function(bs, bn)
        LoadingScreen.open({ bgmSource = bs, bgmNode = bn })
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

    -- 5.2~5.4 击杀/城镇/轮回/关卡/阵亡/阵容接线（抽出到 ClientBoot）
    ClientBoot.run({
        vg = vg,
        scene = scene_,
        sendAction = Client.sendAction,
        getRewardBuffer = function() return rewardBuffer end,
        getEnter0204Fired = function() return enter0204ScenarioFired_ end,
        setEnter0204Fired = function(v) enter0204ScenarioFired_ = v end,
        ClientMsgHandler = ClientMsgHandler,
        ClientScenario = ClientScenario,
    })

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
    pendingIntroAfterTitle_ = false
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
    LetterIntro.reset()
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
    ClientRender.bind({
        vg = vg,
        logicalW = logicalW,
        logicalH = logicalH,
        dpr = dpr,
        scale = scale,
        designOffsetX = designOffsetX,
        designOffsetY = designOffsetY,
        screenDesignW = screenDesignW,
        screenDesignH = screenDesignH,
        H_skipDone = H_skipDone,
        H_ox = H_ox, H_oy = H_oy, H_s = H_s,
        currentState = currentState,
        STATE_IN_GAME = STATE_IN_GAME,
        pageTrans = pageTrans,
        drawOverlay = drawOverlay,
        easeOutBack = easeOutBack,
        _diag_updateFrameNum = _diag_updateFrameNum,
        _diag_renderLastSeenFrame = _diag_renderLastSeenFrame,
        _diag_renderStallCount = _diag_renderStallCount,
        setHSkipDone = function(v) H_skipDone = v end,
        setScale = function(v) scale = v end,
        setDesignOffset = function(x, y) designOffsetX, designOffsetY = x, y end,
        setHLayout = function(ox, oy, s) H_ox, H_oy, H_s = ox, oy, s end,
    })
    ClientRender.HandleNanoVGRender(eventType, eventData)
    if ClientRender.D then
        H_skipDone = ClientRender.D.H_skipDone
        scale = ClientRender.D.scale
        designOffsetX = ClientRender.D.designOffsetX
        designOffsetY = ClientRender.D.designOffsetY
        H_ox = ClientRender.D.H_ox
        H_oy = ClientRender.D.H_oy
        H_s = ClientRender.D.H_s
        _diag_renderLastSeenFrame = ClientRender.D._diag_renderLastSeenFrame
        _diag_renderStallCount = ClientRender.D._diag_renderStallCount
    end
end

-- ======================== 更新 ========================

function HandleUpdate_Client(eventType, eventData)
    _diag_updateFrameNum = _diag_updateFrameNum + 1

  local _ok, _err = pcall(function()
    ClientUpdate.bind({
        Client = Client,
        sendClientReady = sendClientReady,
        resetRetryState = resetRetryState,
        ClientScenario = ClientScenario,
        STATE_CONNECTING = STATE_CONNECTING,
        STATE_CONNECTED = STATE_CONNECTED,
        STATE_LOADING = STATE_LOADING,
        STATE_SERVER_SELECT = STATE_SERVER_SELECT,
        STATE_IN_GAME = STATE_IN_GAME,
        STATE_DISCONNECTED = STATE_DISCONNECTED,
        STATE_RECONNECTING = STATE_RECONNECTING,
        CONNECTION_TIMEOUT = CONNECTION_TIMEOUT,
        RECONNECT_TIMEOUT = RECONNECT_TIMEOUT,
        READY_RETRY_INTERVAL = READY_RETRY_INTERVAL,
        READY_RETRY_MAX = READY_RETRY_MAX,
        DATA_LOAD_TIMEOUT = DATA_LOAD_TIMEOUT,
        HEARTBEAT_INTERVAL = HEARTBEAT_INTERVAL,
        REWARD_FLUSH_INTERVAL = REWARD_FLUSH_INTERVAL,
        SELECT_SERVER_RETRY_INTERVAL = SELECT_SERVER_RETRY_INTERVAL,
        BATTLE_TAB = BATTLE_TAB,
        connectingTimeoutShown = connectingTimeoutShown,
        connectingTimer = connectingTimer,
        currentState = currentState,
        overlayText = overlayText,
        showOverlay = showOverlay,
        reconnectTimer = reconnectTimer,
        serverListRetryTimer = serverListRetryTimer,
        serverListRetryCount = serverListRetryCount,
        readyRetryTimer = readyRetryTimer,
        readyRetryCount = readyRetryCount,
        dataLoadTimer = dataLoadTimer,
        dataLoadRetryCount = dataLoadRetryCount,
        heartbeatTimer = heartbeatTimer,
        lastTabIndex = lastTabIndex,
        rewardBuffer = rewardBuffer,
        rewardFlushTimer = rewardFlushTimer,
        pageTrans = pageTrans,
        saveResultReceived = saveResultReceived,
        readySent = readySent,
        serverListReceived_ = serverListReceived_,
        pendingSelectServerId_ = pendingSelectServerId_,
        deferredRewardPopupShown_ = deferredRewardPopupShown_,
        loadingScreenWasOpen_ = loadingScreenWasOpen_,
        offlineRewardAutoShown_ = offlineRewardAutoShown_,
        offlineRewardData_ = offlineRewardData_,
        pendingIntroAfterTitle_ = pendingIntroAfterTitle_,
        townEntranceScenarioFired_ = townEntranceScenarioFired_,
        updateNoticeShown_ = updateNoticeShown_,
        _diag_errorCount = _diag_errorCount,
        _diag_lastError = _diag_lastError,
        _diag_updateFrameNum = _diag_updateFrameNum,
    })
    ClientUpdate.tick(eventType, eventData)
    local U = ClientUpdate.D
    if U then
        connectingTimeoutShown = U.connectingTimeoutShown
        connectingTimer = U.connectingTimer
        currentState = U.currentState
        overlayText = U.overlayText
        showOverlay = U.showOverlay
        reconnectTimer = U.reconnectTimer
        serverListRetryTimer = U.serverListRetryTimer
        serverListRetryCount = U.serverListRetryCount
        readyRetryTimer = U.readyRetryTimer
        readyRetryCount = U.readyRetryCount
        dataLoadTimer = U.dataLoadTimer
        dataLoadRetryCount = U.dataLoadRetryCount
        heartbeatTimer = U.heartbeatTimer
        lastTabIndex = U.lastTabIndex
        rewardBuffer = U.rewardBuffer
        rewardFlushTimer = U.rewardFlushTimer
        pageTrans = U.pageTrans
        saveResultReceived = U.saveResultReceived
        readySent = U.readySent
        serverListReceived_ = U.serverListReceived_
        pendingSelectServerId_ = U.pendingSelectServerId_
        deferredRewardPopupShown_ = U.deferredRewardPopupShown_
        loadingScreenWasOpen_ = U.loadingScreenWasOpen_
        offlineRewardAutoShown_ = U.offlineRewardAutoShown_
        offlineRewardData_ = U.offlineRewardData_
        pendingIntroAfterTitle_ = U.pendingIntroAfterTitle_
        townEntranceScenarioFired_ = U.townEntranceScenarioFired_
        updateNoticeShown_ = U.updateNoticeShown_
        _diag_errorCount = U._diag_errorCount
        _diag_lastError = U._diag_lastError
    end
  end)
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
H_SKIP_START = true
H_skipDone = false
H_ox, H_oy, H_s = 0, 0, 1

return Client
