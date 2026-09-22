-- ============================================================================
-- ClientBoot - 多人客户端启动接线（原 Client.Start 步骤 5.2~5.4）
-- 职责：击杀奖励缓冲、城镇入场情景、轮回/关卡/阵亡/阵容回调
-- ============================================================================

local Protocol               = require("shared.Protocol")
local TopBar                 = require("ui.TopBar")
local BottomNav              = require("ui.BottomNav")
local BattleScene            = require("ui.BattleScene")
local CharacterPanel         = require("ui.CharacterPanel")
local DiaryPage              = require("ui.DiaryPage")
local TaskPanel              = require("ui.TaskPanel")
local DungeonPage            = require("ui.DungeonPage")
local TownScene              = require("ui.TownScene")
local BlacksmithPage         = require("ui.BlacksmithPage")
local ChurchPage             = require("ui.ChurchPage")
local TavernPage             = require("ui.TavernPage")
local MarketPage             = require("ui.MarketPage")
local GuildPage              = require("ui.GuildPage")
local RedeemCodePanel        = require("ui.RedeemCodePanel")
local SignInPanel            = require("ui.SignInPanel")
local MailPanel              = require("ui.MailPanel")
local BackpackPanel          = require("ui.BackpackPanel")
local DebugPanel             = require("ui.DebugPanel")
local HeroRosterPanel        = require("ui.HeroRosterPanel")
local RewardPopup            = require("ui.RewardPopup")
local LevelUpPopup           = require("ui.LevelUpPopup")
local OfflineRewardPanel     = require("ui.OfflineRewardPanel")
local UpdateNoticePopup      = require("ui.UpdateNoticePopup")
local VersionMismatchPopup   = require("ui.VersionMismatchPopup")
local PlayerInfoPanel        = require("ui.PlayerInfoPanel")
local SpinePowerUpEffect     = require("ui.SpinePowerUpEffect")
local IntroCutscene          = require("ui.IntroCutscene")
local ScenarioDialogue       = require("ui.ScenarioDialogue")
local ScenarioDialogueConfig = require("config.ScenarioDialogueConfig")
local TutorialManager        = require("systems.TutorialManager")
local CharacterSelect        = require("ui.CharacterSelect")
local LootBox                = require("ui.LootBox")
local LootBoxPage            = require("ui.LootBoxPage")
local DungeonBattleScene     = require("ui.DungeonBattleScene")
local TowerBuffPick          = require("ui.TowerBuffPick")
local EventBus               = require("core.EventBus")
local GameEvents             = require("config.GameEvents")
local ExpTable               = require("config.ExpTable")
local PlayerStore            = require("client.data.PlayerStore")
local ClientScenario         = require("network.ClientScenarioHelper")
local ClientMsgHandler       = require("network.ClientMessageHandler")
local GameAlgoService        = require("client.GameAlgoService")

local M = {}

---@param rt table
function M.run(rt)
    local vg = rt.vg
    local sendAction = rt.sendAction
    local getRewardBuffer = rt.getRewardBuffer
    local getEnter0204Fired = rt.getEnter0204Fired
    local setEnter0204Fired = rt.setEnter0204Fired
    local ClientMsgHandler = rt.ClientMsgHandler or ClientMsgHandler
    local ClientScenario = rt.ClientScenario or ClientScenario
    local scene_ = rt.scene

    -- 5.2 击杀奖励回调：累计到缓冲区，在update 定时批量上报服务端
    BattleScene.setOnEnemyKill(function(data)
    print("[Client] kill callback: exp=" .. tostring(data.expReward)
        .. " gold=" .. tostring(data.goldReward)
        .. " heroIds=#" .. tostring(data.heroIds and #data.heroIds or 0))
    getRewardBuffer()[#getRewardBuffer() + 1] = {
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
    sendAction(action, params)
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
    sendAction(action, params)
    end)
    -- 注入 sendAction，让 RedeemCodePanel 走服务端兑换流程
    RedeemCodePanel.setSendAction(function(action, params)
    local sent = sendAction(action, params)
    if not sent then
        RedeemCodePanel.onActionResult({ success = false, reason = "网络未连接", redeemAction = true })
    end
    end)
    -- 注入 sendAction，让 SignInPanel 走服务端签到流程
    SignInPanel.setSendAction(function(action, params)
    sendAction(action, params)
    end)
    -- 注入 sendAction，让 MailPanel 走服务端邮件操作流程
    MailPanel.setSendAction(function(action, params)
    sendAction(action, params)
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
    print("[Client][LOAD]   DungeonBattleScene.init...")
    DungeonBattleScene.init(vg)
    print("[Client][LOAD]   TowerBuffPick.init...")
    TowerBuffPick.init(vg)
    print("[Client][LOAD]   MarketPage.init...")
    MarketPage.init(vg)
    -- 注入 sendAction，让 MarketPage 走服务端购买流程
    MarketPage.setSendAction(function(action, params)
    sendAction(action, params)
    end)
    TownScene.setOnMarketClick(function()
    MarketPage.open()
    end)
    -- [仓库入口] 城镇仓库点击 → 打开背包（全窗模态）
    TownScene.setOnWarehouseClick(function()
    BackpackPanel.open(true)
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
    sendAction(Protocol.ACTION_TYPES.CLAIM_LOOT_ALL, {})
    end)

    -- 5.251 战利品单个领取回调：点击种子图标 →发送该组全部领取请求到服务端
    LootBox.setOnClaimOne(function(seedIndex)
    print("[Client] LootBox claimGroup index=" .. tostring(seedIndex)
        .. " →sending CLAIM_LOOT to server")
    sendAction(Protocol.ACTION_TYPES.CLAIM_LOOT, { index = seedIndex })
    -- 服务端返回actionResult 后由 handleActionResult 刷新 LootBox + 弹出 RewardPopup
    end)

    -- 5.252 战利品一键分解回调：发送分解请求到服务端
    LootBox.setOnDecomposeAll(function()
    print("[Client] LootBox decomposeAll →sending DECOMPOSE_LOOT_ALL to server")
    sendAction(Protocol.ACTION_TYPES.DECOMPOSE_LOOT_ALL, {})
    LootBox.refreshPage()
    end)

    LootBox.setOnDecomposeOne(function(seedIndex)
    print("[Client] LootBox decomposeOne index=" .. tostring(seedIndex) .. " →sending DECOMPOSE_LOOT to server")
    sendAction(Protocol.ACTION_TYPES.DECOMPOSE_LOOT, { index = seedIndex })
    LootBox.refreshPage()
    end)

    -- 5.253 自动分解设置回调：直接打开弹窗（无需导航到铁匠铺）
    LootBox.setOnAutoDecompose(function()
    LootBoxPage.hide()
    BlacksmithPage.openAutoDecomposePopupStandalone()
    end)

    -- 5.3 轮回回调：倒计时结束→播放轮回前对话→开场动画→完成关卡加载
    BattleScene.setOnReincarnate(function(data)
    print("[Client] reincarnation triggered, starting intro cutscene (difficulty "
        .. tostring(data.fromDifficulty) .. " →" .. tostring(data.toDifficulty) .. ")")

    -- 轮回前情景对话（普通终点→62，困难终点→69）
    local preReincarnateScenarioId = nil
    if data.fromDifficulty == "normal" then
        preReincarnateScenarioId = 62
    elseif data.fromDifficulty == "hard" then
        preReincarnateScenarioId = 69
    end

    local function proceedWithIntro()
        IntroCutscene.reset()
        IntroCutscene.start(function()
            print("[Client] reincarnation intro finished, completing stage load")
            BattleScene.completeReincarnation()
            -- completeReincarnation 会同步 NEXT_STAGE，服务端可能标记 hasReincarnated；
            -- 入场动画已在本次轮回流程播放完毕，清除标记避免重启后重复播放
            sendAction(Protocol.ACTION_TYPES.CLEAR_REINCARNATION, {})
        end)
    end

    if preReincarnateScenarioId and not ClientScenario.isClaimed(preReincarnateScenarioId) then
        ClientScenario.playFirstVisit(preReincarnateScenarioId, nil, proceedWithIntro)
    else
        proceedWithIntro()
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
    sendAction(Protocol.ACTION_TYPES.NEXT_STAGE, {
        clearedStageId = clearedStageId,
    })
    end)

    BattleScene.setOnStageChanged(function(newStageId)

    sendAction(Protocol.ACTION_TYPES.NEXT_STAGE, {
        nextStageId = newStageId,
    })
    -- 首次进入关卡 0204 →触发情景 41/42/43（昆吾之怒）
    if newStageId == 204 and not getEnter0204Fired() then
        setEnter0204Fired(true)
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
                        sendAction(Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD, {
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
        sendAction(Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD, {
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
    sendAction(Protocol.ACTION_TYPES.SET_TEAM, {
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


end

return M
