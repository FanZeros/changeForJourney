-- ============================================================================
-- ClientUpdate - 多人客户端 HandleUpdate（玩法不变）
-- 每帧 ClientUpdate.bind(deps) 后跑 tick；可变字段写在 D 上并由 Client 写回
-- ============================================================================

local Protocol         = require("shared.Protocol")
local ClientDispatcher = require("network.ClientDispatcher")
local ClientMsgHandler = require("network.ClientMessageHandler")
local GameAlgoService  = require("client.GameAlgoService")
local LoadingScreen    = require("ui.LoadingScreen")
local DarkTitleScreen  = require("ui.DarkTitleScreenGate")
local LetterIntro      = require("ui.LetterIntro")
local CharacterSelect  = require("ui.CharacterSelect")
local StartScreen      = require("ui.StartScreen")
local RewardPopup      = require("ui.RewardPopup")
local ScenarioDialogue = require("ui.ScenarioDialogue")
local TutorialManager  = require("systems.TutorialManager")
local LevelUpPopup     = require("ui.LevelUpPopup")
local OfflineRewardPanel = require("ui.OfflineRewardPanel")
local TavernPage       = require("ui.TavernPage")
local MarketPage       = require("ui.MarketPage")
local PlayerInfoPanel  = require("ui.PlayerInfoPanel")
local GameBGM          = require("systems.GameBGM")
local GameSFX          = require("systems.GameSFX")
local GameState        = require("core.GameState")
local PlayerStore      = require("client.data.PlayerStore")
local EquipmentSystem  = require("systems.EquipmentSystem")
local BottomNav        = require("ui.BottomNav")
local BattleScene      = require("ui.BattleScene")
local CharacterPanel   = require("ui.CharacterPanel")
local TownScene        = require("ui.TownScene")
local BlacksmithPage   = require("ui.BlacksmithPage")
local ChurchPage       = require("ui.ChurchPage")
local GuildPage        = require("ui.GuildPage")
local DungeonBattleScene = require("ui.DungeonBattleScene")
local TowerBattleScene = require("ui.TowerBattleScene")
local DungeonPage      = require("ui.DungeonPage")
local DiaryPage        = require("ui.DiaryPage")
local BackpackPanel    = require("ui.BackpackPanel")
local LootBox          = require("ui.LootBox")
local IntroCutscene    = require("ui.IntroCutscene")
local UpdateNoticePopup = require("ui.UpdateNoticePopup")
local TopBar           = require("ui.TopBar")

local M = {}
local D = {}
M.D = D

function M.bind(deps)
    D = deps
    M.D = D
end

function M.tick(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    local connectingTimeoutShown = D.connectingTimeoutShown
    local connectingTimer = D.connectingTimer
    local currentState = D.currentState
    local overlayText = D.overlayText
    local showOverlay = D.showOverlay
    local reconnectTimer = D.reconnectTimer
    local serverListRetryTimer = D.serverListRetryTimer
    local serverListRetryCount = D.serverListRetryCount
    local readyRetryTimer = D.readyRetryTimer
    local readyRetryCount = D.readyRetryCount
    local dataLoadTimer = D.dataLoadTimer
    local dataLoadRetryCount = D.dataLoadRetryCount
    local heartbeatTimer = D.heartbeatTimer
    local lastTabIndex = D.lastTabIndex
    local rewardBuffer = D.rewardBuffer
    local rewardFlushTimer = D.rewardFlushTimer
    local pageTrans = D.pageTrans
    local saveResultReceived = D.saveResultReceived
    local readySent = D.readySent
    local serverListReceived_ = D.serverListReceived_
    local pendingSelectServerId_ = D.pendingSelectServerId_
    local deferredRewardPopupShown_ = D.deferredRewardPopupShown_
    local loadingScreenWasOpen_ = D.loadingScreenWasOpen_
    local offlineRewardAutoShown_ = D.offlineRewardAutoShown_
    local offlineRewardData_ = D.offlineRewardData_
    local pendingIntroAfterTitle_ = D.pendingIntroAfterTitle_
    local townEntranceScenarioFired_ = D.townEntranceScenarioFired_
    local updateNoticeShown_ = D.updateNoticeShown_
    local _diag_errorCount = D._diag_errorCount
    local _diag_lastError = D._diag_lastError

    local Client = D.Client
    local sendClientReady = D.sendClientReady
    local resetRetryState = D.resetRetryState
    local ClientScenario = D.ClientScenario
    local STATE_CONNECTING = D.STATE_CONNECTING
    local STATE_CONNECTED = D.STATE_CONNECTED
    local STATE_LOADING = D.STATE_LOADING
    local STATE_SERVER_SELECT = D.STATE_SERVER_SELECT
    local STATE_IN_GAME = D.STATE_IN_GAME
    local STATE_DISCONNECTED = D.STATE_DISCONNECTED
    local STATE_RECONNECTING = D.STATE_RECONNECTING
    local CONNECTION_TIMEOUT = D.CONNECTION_TIMEOUT
    local RECONNECT_TIMEOUT = D.RECONNECT_TIMEOUT
    local READY_RETRY_INTERVAL = D.READY_RETRY_INTERVAL
    local READY_RETRY_MAX = D.READY_RETRY_MAX
    local DATA_LOAD_TIMEOUT = D.DATA_LOAD_TIMEOUT
    local HEARTBEAT_INTERVAL = D.HEARTBEAT_INTERVAL
    local REWARD_FLUSH_INTERVAL = D.REWARD_FLUSH_INTERVAL
    local SELECT_SERVER_RETRY_INTERVAL = D.SELECT_SERVER_RETRY_INTERVAL
    local BATTLE_TAB = D.BATTLE_TAB

    -- ClientDispatcher tick（检查批次超时）→始终运行，不受StartScreen 阻断
    ClientDispatcher.update(dt)

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
        end
    end

    -- 开始界面更新（视频+动画）→网络连接/重试已在上方运行，此处仅跳过游戏 UI 更新
    if StartScreen.isOpen() then
        StartScreen.update(dt)
        return
    end

    -- [DarkTitleScreen] 横屏标题动画（游戏/加载在标题下方继续进行）
    -- LoadingScreen 未完成时锁点击，避免点进无背景界面
    if DarkTitleScreen.isOpen() then
        DarkTitleScreen.setReady(not LoadingScreen.isOpen())
        DarkTitleScreen.update(dt)
    elseif pendingIntroAfterTitle_ and not LoadingScreen.isOpen() then
        -- 标题已关闭（或不存在）且加载完成 → 启动先祖来信开场链
        pendingIntroAfterTitle_ = false
        print("[Client] title closed, starting letter then character select (skip cutscene/scenario)")
        GameBGM.setScene("letter", { fromStart = true })
        LetterIntro.start(function()
            GameBGM.setScene("battle", { fromStart = true })
            print("[Client] letter finished, opening character select")
            -- 跳过情景1仍领取标记，避免后续系统再拉起开场对话
            Client.sendAction(Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD, { scenarioId = 1 })
            CharacterSelect.show({
                background = "image/关卡地图/MAP_1.png",
                onFinish = function(heroId)
                    print("[Client] character selected: heroId=" .. heroId)
                    Client.sendAction(Protocol.ACTION_TYPES.SELECT_INITIAL_HERO, {
                        heroId = heroId,
                    })
                end,
            })
        end)
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
                -- roster 为空 = 新玩家。横屏标题打开时先挂起，关闭后再播信
                print("[Client] roster is empty (new player), queue intro after title")
                pendingIntroAfterTitle_ = true
                GameBGM.start()
                GameSFX.start()
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
            rewardData.onClaim = function()
                print("[OfflineRewardPanel] claimed")
                Client.sendAction(Protocol.ACTION_TYPES.CLAIM_OFFLINE_REWARDS, {})
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
            [2] = "enter_panel_diary",
            [3] = "enter_panel_battle",
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

        if TowerBattleScene.isActive() then
            TowerBattleScene.update(dt)
        elseif DungeonBattleScene.isOpen() then
            DungeonBattleScene.update(dt)
        else
            BattleScene.update(dt)
        end
        LootBox.update(dt)   -- 战利品箱全局更新（飞入动画/领取检测），独立于战斗场景
        if tabIndex == 1 then
            CharacterPanel.update(dt)
        elseif tabIndex == 2 then
            DiaryPage.update(dt)
        elseif tabIndex == 5 then
            DungeonPage.update(dt)
        end
        -- [仓库入口] 背包全窗模态动画由宿主驱动（DiaryPage 已让位）
        if BackpackPanel.isOpen() and BackpackPanel.isWindowMode() then
            BackpackPanel.update(dt)
        end

        -- 角标刷新（始终执行，不受当前 tab 限制）
        BottomNav.setBadge(2, DiaryPage.hasAnyClaimable(), "redDot")

        -- 铁匠铺分解红点（背包满时提示）
        local equipData_ = ClientDispatcher.get("equipment")
        local bagFull_ = equipData_ and EquipmentSystem.isInventoryFull(equipData_) or false
        TownScene.setSmithRedDot(bagFull_)
        BlacksmithPage.setDecomposeRedDot(bagFull_)


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
        MarketPage.update(dt)
        PlayerInfoPanel.update(dt)
    end


    D.connectingTimeoutShown = connectingTimeoutShown
    D.connectingTimer = connectingTimer
    D.currentState = currentState
    D.overlayText = overlayText
    D.showOverlay = showOverlay
    D.reconnectTimer = reconnectTimer
    D.serverListRetryTimer = serverListRetryTimer
    D.serverListRetryCount = serverListRetryCount
    D.readyRetryTimer = readyRetryTimer
    D.readyRetryCount = readyRetryCount
    D.dataLoadTimer = dataLoadTimer
    D.dataLoadRetryCount = dataLoadRetryCount
    D.heartbeatTimer = heartbeatTimer
    D.lastTabIndex = lastTabIndex
    D.rewardBuffer = rewardBuffer
    D.rewardFlushTimer = rewardFlushTimer
    D.pageTrans = pageTrans
    D.saveResultReceived = saveResultReceived
    D.readySent = readySent
    D.serverListReceived_ = serverListReceived_
    D.pendingSelectServerId_ = pendingSelectServerId_
    D.deferredRewardPopupShown_ = deferredRewardPopupShown_
    D.loadingScreenWasOpen_ = loadingScreenWasOpen_
    D.offlineRewardAutoShown_ = offlineRewardAutoShown_
    D.offlineRewardData_ = offlineRewardData_
    D.pendingIntroAfterTitle_ = pendingIntroAfterTitle_
    D.townEntranceScenarioFired_ = townEntranceScenarioFired_
    D.updateNoticeShown_ = updateNoticeShown_
    D._diag_errorCount = _diag_errorCount
    D._diag_lastError = _diag_lastError
end

return M
