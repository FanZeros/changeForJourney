---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- Standalone - 单机模式入口（⚠️ 当前项目为多人模式，本文件不会被执行！）
-- 职责: 创建场景/NanoVG/字体、设计分辨率缩放、事件订阅、渲染调度
--
-- AI 注意: 多人模式下请改 Client.lua + ClientInput.lua，不要改这里！
-- ============================================================================

local GameConfig        = require("config.GameConfig")
local GameState         = require("core.GameState")
local ExpTable          = require("config.ExpTable")
local StageConfig       = require("config.StageConfig")
local DropSystem        = require("systems.DropSystem")
local EquipmentSystem   = require("systems.EquipmentSystem")
local LootBoxSystem     = require("systems.LootBoxSystem")
local ClientDispatcher  = require("network.ClientDispatcher")
local TopBar            = require("ui.TopBar")
local BottomNav         = require("ui.BottomNav")
local BattleScene       = require("ui.BattleScene")
local CharacterPanel    = require("ui.CharacterPanel")
local DebugPanel        = require("ui.DebugPanel")
local HeroRosterPanel   = require("ui.HeroRosterPanel")
local RewardPopup       = require("ui.RewardPopup")
local TownScene         = require("ui.TownScene")
local BlacksmithPage    = require("ui.BlacksmithPage")
local TavernPage        = require("ui.TavernPage")
local ArenaPage         = require("ui.ArenaPage")
local MarketPage        = require("ui.MarketPage")
local ArenaBattleScene  = require("ui.ArenaBattleScene")
local DungeonBattleScene = require("ui.DungeonBattleScene")
local LootBox           = require("ui.LootBox")
local LootBoxPage       = require("ui.LootBoxPage")
local LevelUpPopup      = require("ui.LevelUpPopup")
        local BattleCombat     = require("ui.BattleCombat")
local OfflineRewardPanel = require("ui.OfflineRewardPanel")
local PlayerInfoPanel   = require("ui.PlayerInfoPanel")
local RedeemCodePanel   = require("ui.RedeemCodePanel")
local MailPanel         = require("ui.MailPanel")
local AnnouncementPanel = require("ui.AnnouncementPanel")
local MailConfig        = require("shared.mail.MailConfig")
local AnnouncementConfig = require("shared.AnnouncementConfig")
local RedeemConfig      = require("shared.redeem.RedeemConfig")
local Protocol          = require("shared.Protocol")
local DiaryPage         = require("ui.DiaryPage")
local StartScreen       = require("ui.StartScreen")
local EventBus          = require("core.EventBus")
local GameEvents        = require("config.GameEvents")
local GameBGM           = require("systems.GameBGM")
local GameSFX           = require("systems.GameSFX")
local SpinePowerUpEffect = require("ui.SpinePowerUpEffect")
local IntroCutscene      = require("ui.IntroCutscene")
local SamsaraCG          = require("ui.SamsaraCG")
local DrawUtil           = require("core.DrawUtil")

local Standalone = {}

-- NanoVG context & font
local vg = nil
local sceneRef_ = nil  -- 保存 scene 引用，供 requestResetToStartScreen 使用
local startScreenWasOpen_ = false
local fontNormal = -1


-- Design resolution (Mode A — 1080x2400 竖屏)
local DESIGN_W = GameConfig.Design.WIDTH
local DESIGN_H = GameConfig.Design.HEIGHT

local physW, physH, dpr, logicalW, logicalH
local scale, screenDesignW, screenDesignH, designOffsetX, designOffsetY

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

-- ============================================================================
-- Module API
-- ============================================================================

function Standalone.Start()
    -- 1. Minimal scene (renderer needs a viewport)
    local scene = Scene()
    sceneRef_ = scene  -- 保存引用
    scene:CreateComponent("Octree")
    local camNode = scene:CreateChild("Camera")
    local camera = camNode:CreateComponent("Camera")
    renderer:SetViewport(0, Viewport:new(scene, camera))

    -- 1.5 BGM & SFX
    GameBGM.init(scene)
    GameSFX.init(scene)

    -- 2. NanoVG context
    vg = nvgCreate(1)
    if not vg then
        print("[Standalone] ERROR: nvgCreate failed")
        return
    end

    -- 3. Font
    fontNormal = nvgCreateFont(vg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
    if fontNormal < 0 then
        print("[Standalone] ERROR: font load failed")
    end

    -- 4. Layout
    RecalcLayout()

    -- 4.5 碎片图标资源初始化
    DrawUtil.initShardAssets(vg)

    -- 5. Sub-modules
    StartScreen.init(vg, scene)
    TopBar.init(vg)
    BottomNav.init(vg)
    BattleScene.init(vg)
    IntroCutscene.init(vg, scene)
    CharacterPanel.init(vg)
    DiaryPage.init(vg)
    TopBar.markAvatarViewed()  -- 初始化头像红点基准
    TownScene.init(vg)
    BlacksmithPage.init(vg)
    TavernPage.init(vg)
    DebugPanel.init(vg)
    HeroRosterPanel.init(vg)
    RewardPopup.init(vg)
    OfflineRewardPanel.init(vg)
    LevelUpPopup.init(vg)
    PlayerInfoPanel.init(vg)
    SpinePowerUpEffect.init()

    -- 兑换码回调（单机模式本地校验）
    -- 注意：一次性批量码(FATE-XXXX)仅服务端加载，单机模式只能验证公开不限量码
    local usedCodes = {}
    RedeemCodePanel.setSendAction(function(action, params)
        local code = params and params.code or ""
        print("[Standalone] redeem code request: " .. code)
        local upper = string.upper(code)
        local cfg = RedeemConfig.CODE_MAP[upper]
        if not cfg then
            RedeemCodePanel.onActionResult({ success = false, reason = "无效的兑换码", redeemAction = true })
        elseif usedCodes[upper] then
            RedeemCodePanel.onActionResult({ success = false, reason = "该兑换码已使用过", redeemAction = true })
        else
            usedCodes[upper] = true
            RedeemCodePanel.onActionResult({ success = true, redeemAction = true, rewards = cfg.rewards })
        end
    end)

    -- 邮件回调（单机模式本地处理）
    local mailClaimed = {}
    local mailDeleted = {}
    local function buildLocalMailList()
        local list = {}
        for _, cfg in ipairs(MailConfig.MAILS) do
            if not mailDeleted[cfg.id] then
                list[#list + 1] = {
                    id         = cfg.id,
                    title      = cfg.title,
                    date       = cfg.date,
                    remainDays = cfg.remainDays,
                    body       = cfg.body,
                    rewards    = cfg.rewards,
                    read       = mailClaimed[cfg.id] or false,
                }
            end
        end
        return list
    end
    -- 注入初始邮件数据
    MailPanel.setMailData(buildLocalMailList())
    -- 注入公告数据（基于开服时间计算日期，单机模式 openTime=0 取当前日期）
    AnnouncementPanel.setAnnouncementData(AnnouncementConfig.buildWithDates(0))

    MailPanel.setSendAction(function(action, params)
        print("[Standalone] mail action: " .. tostring(action))
        if action == Protocol.ACTION_TYPES.CLAIM_MAIL then
            local mailId = params and params.mailId
            if mailId and not mailClaimed[mailId] then
                mailClaimed[mailId] = true
                -- 查找邮件奖励
                local rewards = {}
                for _, cfg in ipairs(MailConfig.MAILS) do
                    if cfg.id == mailId then rewards = cfg.rewards or {}; break end
                end
                MailPanel.onActionResult({
                    success    = true,
                    mailAction = true,
                    action     = Protocol.ACTION_TYPES.CLAIM_MAIL,
                    mailId     = mailId,
                    rewards    = rewards,
                })
            end
        elseif action == Protocol.ACTION_TYPES.CLAIM_ALL_MAIL then
            local allRewards = {}
            for _, cfg in ipairs(MailConfig.MAILS) do
                if not mailClaimed[cfg.id] and not mailDeleted[cfg.id] then
                    mailClaimed[cfg.id] = true
                    for _, r in ipairs(cfg.rewards or {}) do
                        allRewards[#allRewards + 1] = r
                    end
                end
            end
            MailPanel.onActionResult({
                success    = true,
                mailAction = true,
                action     = Protocol.ACTION_TYPES.CLAIM_ALL_MAIL,
                rewards    = allRewards,
            })
        elseif action == Protocol.ACTION_TYPES.DELETE_READ then
            local deletedIds = {}
            for _, cfg in ipairs(MailConfig.MAILS) do
                if mailClaimed[cfg.id] and not mailDeleted[cfg.id] then
                    mailDeleted[cfg.id] = true
                    deletedIds[#deletedIds + 1] = cfg.id
                end
            end
            MailPanel.onActionResult({
                success    = true,
                mailAction = true,
                action     = Protocol.ACTION_TYPES.DELETE_READ,
                deletedIds = deletedIds,
            })
        end
    end)

    -- 5.05 冒险等级提升弹窗：监听 PLAYER_LEVEL_UP 事件，并刷新解锁状态
    EventBus.on(GameEvents.PLAYER_LEVEL_UP, function(data)
        local newLevel = data.level
        local unlocks = ExpTable.getLevelUnlocks(newLevel)
        LevelUpPopup.show(newLevel, unlocks)
        -- 刷新各模块解锁状态
        CharacterPanel.refreshSlotUnlocks()
        BottomNav.refreshUnlockState(vg)
    end)

    -- 5.1 阵容变更回调：角色面板出战变动 → 同步战斗画面 → 重载关卡 → 更新 TopBar 战力
    CharacterPanel.setOnTeamChanged(function()
        local team = CharacterPanel.getDeployedTeam()
        TopBar.setTotalPower(CharacterPanel.getTotalPower())
        if #team > 0 then
            BattleScene.setAllies(team)
            BattleScene.reloadStage()
            print("[Standalone] 阵容变更，同步 " .. #team .. " 个英雄到战斗，重载关卡")
        else
            print("[Standalone] 阵容变更，当前无出战英雄")
        end
    end)

    -- 5.2 击杀奖励回调：经验平分给每个上场冒险家，金币/冒险等级经验照常
    BattleScene.setOnEnemyKill(function(data)
        local baseExp  = data.expReward  or 0
        local baseGold = data.goldReward or 0
        local heroIds  = data.heroIds    or {}
        local allyCount = data.allyCount or 1

        -- 金币直接加
        if baseGold > 0 then
            GameState.setGold(GameState.getGold() + baseGold)
        end

        -- 玩家（冒险等级）经验 = 怪物基础经验（不乘倍率）
        if baseExp > 0 then
            GameState.addExp(baseExp)
        end

        -- 冒险家经验：总池 = 基础经验 × 倍率，平分给每个上场英雄
        if baseExp > 0 and #heroIds > 0 then
            local expMult = ExpTable.getHeroCountExpMult(allyCount)
            local totalExp = baseExp * expMult
            local perHeroExp = math.floor(totalExp / #heroIds + 0.5)
            if perHeroExp > 0 then
                for _, hid in ipairs(heroIds) do
                    CharacterPanel.addHeroExp(hid, perHeroExp)
                end
                -- 升级后刷新战斗单位属性（同步 _pendingLevel + _pendingSnapshot）
                if BattleScene.refreshAllyStats then
                    BattleScene.refreshAllyStats()
                end
            end
        end
    end)

    -- 5.15 城镇铁匠铺点击 → 打开铁匠铺界面
    TownScene.setOnSmithClick(function()
        BlacksmithPage.open()
    end)
    -- 5.16 城镇酒馆点击 → 打开酒馆界面
    TownScene.setOnTavernClick(function()
        TavernPage.open()
    end)
    -- 5.17 城镇竞技场点击 → 打开竞技场界面
    ArenaPage.init(vg)
    ArenaBattleScene.init(vg)
    DungeonBattleScene.init(vg)
    TopBar.setTrainingDummyVisible(true)
    TownScene.setOnArenaClick(function()
        ArenaPage.open()
    end)
    -- 5.18 城镇市场点击 → 打开市场界面
    MarketPage.init(vg)
    TownScene.setOnMarketClick(function()
        MarketPage.open()
    end)

    -- 5.24 装备数据初始化（Standalone 模式下 ClientDispatcher 不会收到 Server 推送）
    if not ClientDispatcher.get("equipment") then
        local initEquipData = { inventory = {}, equipped = {}, nextSeq = 1 }
        -- 通过 handleStateUpdate 注入，触发订阅者通知
        local cjson = cjson
        ClientDispatcher.handleStateUpdate(cjson.encode({
            modules = { equipment = initEquipData }
        }))
        print("[Standalone] 初始化 equipment 数据")
    end

    -- 5.241 战利品缓冲区初始化
    if not ClientDispatcher.get("lootbox") then
        local initLootboxData = { seeds = {} }
        local cjson = cjson
        ClientDispatcher.handleStateUpdate(cjson.encode({
            modules = { lootbox = initLootboxData }
        }))
        print("[Standalone] 初始化 lootbox 数据")
    end
    -- 订阅 lootbox 数据变化 → 刷新 LootBox UI
    ClientDispatcher.subscribe("lootbox", function(data, moduleName)
        LootBoxSystem.consolidateSeeds(data) -- 合并旧存档中按 stageId 分开的同类种子
        -- 版本兼容：clamp 旧版高等级种子到当前关卡怪物等级
        local capStageId = BattleScene.getCurrentStageId()
        local capEntry = capStageId and StageConfig.getStage(capStageId)
        if capEntry and capEntry.monsterLevel and capEntry.monsterLevel > 0 then
            local cap = capEntry.monsterLevel
            LootBoxSystem.levelCap = cap
            local fixed = false
            for _, seed in ipairs(data.seeds or {}) do
                if seed.level and seed.level > cap then
                    seed.level = cap
                    fixed = true
                end
            end
            if fixed then
                LootBoxSystem.consolidateSeeds(data) -- 降级后再合并重复项
                print("[Standalone] lootbox seeds clamped to Lv." .. cap)
            end
        end
        LootBox.updateSeedData(data)
        print("[Standalone] lootbox data updated, seedCount=" .. LootBoxSystem.getTotalCount(data))
    end)

    -- 5.245 击杀掉落回调：掷骰 → 种子存入 lootbox 缓冲区 → UI 提示 + 卷轴掉落
    BattleScene.setOnEnemyDrop(function(data)
        local stageEntry = StageConfig.getStage(data.stageId)
        if not stageEntry then return end
        -- 装备掉落
        local quality = DropSystem.rollKillDrop(stageEntry)
        if quality then
            local level = stageEntry.monsterLevel or 1
            local lootboxData = ClientDispatcher.get("lootbox")
            if lootboxData then
                LootBoxSystem.addSeed(lootboxData, data.stageId, quality, level)
                LootBox.addSeedHint(quality, level)
                LootBox.updateSeedData(lootboxData)
                print("[Standalone] seed added: q=" .. quality .. " lv=" .. level
                    .. " total=" .. LootBoxSystem.getTotalCount(lootboxData))
            end
        end
        -- 卷轴掉落（直接加入货币）
        local scrollType = DropSystem.rollScrollDrop(stageEntry)
        if scrollType then
            local getter = GameState["get" .. scrollType:sub(1,1):upper() .. scrollType:sub(2)]
            local setter = GameState["set" .. scrollType:sub(1,1):upper() .. scrollType:sub(2)]
            if getter and setter then
                setter(getter() + 1)
                print("[Standalone] scroll drop: type=" .. scrollType)
            end
        end
    end)

    -- 5.246 战利品领取回调：一键领取全部种子 → 生成装备加入背包
    LootBox.setOnClaimAll(function()
        local lootboxData = ClientDispatcher.get("lootbox")
        local equipData   = ClientDispatcher.get("equipment")
        if not lootboxData or not equipData then return end
        local claimed, bagFull = LootBoxSystem.claimAll(lootboxData, equipData)
        -- 刷新 LootBox UI + LootBoxPage
        LootBox.updateSeedData(lootboxData)
        LootBox.refreshPage()
        -- 通知 equipment 订阅者刷新（Standalone 直接修改数据，需手动触发）
        ClientDispatcher.notifySubscribers("equipment")
        -- 刷新战力显示
        if CharacterPanel.getTotalPower then
            TopBar.setTotalPower(CharacterPanel.getTotalPower())
        end
        -- 刷新战斗单位属性
        if BattleScene.refreshAllyStats then
            BattleScene.refreshAllyStats()
        end
        -- 领取完毕后，用 RewardPopup 展示领取到的装备（作为奖励展示页面）
        if #claimed > 0 then
            local rewards = {}
            for _, equip in ipairs(claimed) do
                rewards[#rewards + 1] = {
                    type       = "equip",
                    templateId = equip.templateId,
                    quality    = equip.quality,
                    level      = equip.level,
                }
            end
            RewardPopup.show("领取了 " .. #claimed .. " 件装备", rewards)
        end
        if bagFull then
            print("[Standalone] 领取 " .. #claimed .. " 件装备（背包已满，剩余种子保留）")
            LootBoxPage.showToast("背包已满，请先分解多余装备")
            local cx, cy = LootBoxPage.getLastClickPos()
            BattleCombat.addFloatingText("背包已满", cx, cy, { 235, 80, 80 }, false, nil)
        else
            print("[Standalone] 领取 " .. #claimed .. " 件装备（全部领取完毕）")
        end
    end)

    -- 5.247 战利品单个领取回调：点击种子图标 → 领取该组全部装备加入背包
    LootBox.setOnClaimOne(function(seedIndex)
        local lootboxData = ClientDispatcher.get("lootbox")
        local equipData   = ClientDispatcher.get("equipment")
        if not lootboxData or not equipData then return end

        -- 背包满检查
        if EquipmentSystem.isInventoryFull(equipData) then
            print("[Standalone] claimGroup: bag full, cannot claim")
            LootBoxPage.showToast("背包已满，请先分解多余装备")
            local cx, cy = LootBoxPage.getLastClickPos()
            BattleCombat.addFloatingText("背包已满", cx, cy, { 235, 80, 80 }, false, nil)
            return
        end
        -- 领取该组全部（背包不足则领到上限）
        local claimed, bagFull = LootBoxSystem.claimGroup(lootboxData, seedIndex, equipData)
        if #claimed == 0 then
            print("[Standalone] claimGroup: nothing claimed (invalid index)")
            return
        end
        -- 刷新 LootBox UI + LootBoxPage
        LootBox.updateSeedData(lootboxData)
        LootBox.refreshPage()
        -- 通知 equipment 订阅者刷新
        ClientDispatcher.notifySubscribers("equipment")
        -- 刷新战力显示
        if CharacterPanel.getTotalPower then
            TopBar.setTotalPower(CharacterPanel.getTotalPower())
        end
        -- 刷新战斗单位属性
        if BattleScene.refreshAllyStats then
            BattleScene.refreshAllyStats()
        end
        -- 弹出奖励面板展示领取到的装备
        local rewards = {}
        for _, equip in ipairs(claimed) do
            rewards[#rewards + 1] = {
                type       = "equip",
                templateId = equip.templateId,
                quality    = equip.quality,
                level      = equip.level,
            }
        end
        RewardPopup.show("领取了 " .. #claimed .. " 件装备", rewards)
        if bagFull then
            LootBoxPage.showToast("背包已满，请先分解多余装备")
            local cx, cy = LootBoxPage.getLastClickPos()
            BattleCombat.addFloatingText("背包已满", cx, cy, { 235, 80, 80 }, false, nil)
        end
        local newTotal = LootBoxSystem.getTotalCount(lootboxData)
        print("[Standalone] claimGroup: claimed " .. #claimed .. " equips, bagFull="
            .. tostring(bagFull) .. ", remaining=" .. newTotal)
    end)

    -- 5.248 战利品一键分解回调：所有种子 → 精粹
    LootBox.setOnDecomposeAll(function()
        local lootboxData = ClientDispatcher.get("lootbox")
        if not lootboxData then return end
        local totalEssence, totalPieces = LootBoxSystem.decomposeAll(lootboxData)
        if totalPieces > 0 then
            -- 增加精粹
            GameState.setEssence(GameState.getEssence() + totalEssence)
            -- 刷新 LootBox UI（种子已清空）
            LootBox.updateSeedData(lootboxData)
            LootBox.refreshPage()
            -- 弹出奖励面板展示精粹
            local rewards = {}
            if totalEssence > 0 then
                rewards[#rewards + 1] = { type = "essence", amount = totalEssence }
            end
            if #rewards > 0 then
                RewardPopup.show("分解奖励", rewards)
            end
            print("[Standalone] decomposeAll: " .. totalPieces .. " pieces → "
                .. totalEssence .. " essence")
        else
            print("[Standalone] decomposeAll: nothing to decompose")
        end
    end)

    LootBox.setOnDecomposeOne(function(seedIndex)
        local lootboxData = ClientDispatcher.get("lootbox")
        if not lootboxData then return end
        local totalEssence, totalPieces = LootBoxSystem.decomposeOne(lootboxData, seedIndex)
        if totalPieces > 0 then
            GameState.setEssence(GameState.getEssence() + totalEssence)
            LootBox.updateSeedData(lootboxData)
            LootBox.refreshPage()
            local rewards = {}
            if totalEssence > 0 then
                rewards[#rewards + 1] = { type = "essence", amount = totalEssence }
            end
            if #rewards > 0 then
                RewardPopup.show("分解奖励", rewards)
            end
            print("[Standalone] decomposeOne index=" .. seedIndex .. ": "
                .. totalPieces .. " pieces → " .. totalEssence .. " essence")
        else
            print("[Standalone] decomposeOne: invalid index=" .. tostring(seedIndex))
        end
    end)

    -- 5.249 自动分解设置回调：打开铁匠铺分解弹窗
    LootBox.setOnAutoDecompose(function()
        LootBoxPage.hide()
        BottomNav.setSelectedIndex(4)
        BlacksmithPage.openToAutoDecompose()
    end)

    -- 5.24 轮回回调：倒计时结束 → 播放 CG 视频 → 播放开场动画 → 完成关卡加载
    BattleScene.setOnReincarnate(function(data)
        print("[Standalone] reincarnation triggered, playing CG video then intro cutscene (difficulty "
            .. tostring(data.fromDifficulty) .. " → " .. tostring(data.toDifficulty) .. ")")
        -- 先播放轮回 CG 视频（BGM 在视频模块内部静音/恢复）
        SamsaraCG.start(function()
            -- CG 视频结束后，播放开场动画
            print("[Standalone] CG video finished, starting intro cutscene")
            IntroCutscene.reset()
            IntroCutscene.start(function()
                print("[Standalone] reincarnation intro finished, completing stage load")
                BattleScene.completeReincarnation()
            end)
        end)
    end)

    -- 5.25 首通奖励回调：本地计算首通金币+装备，弹出 RewardPopup
    BattleScene.setOnFirstClear(function(clearedStageId)
        local stageEntry = StageConfig.getStage(clearedStageId)
        if not stageEntry then return end

        local rewards = {}
        -- 首通金币
        local fcGold = stageEntry.fcGold or 0
        if fcGold > 0 then
            GameState.setGold(GameState.getGold() + fcGold)
            rewards[#rewards + 1] = { type = "gold", amount = fcGold }
        end
        -- 首通经验
        local fcExp = stageEntry.fcExp or 0
        if fcExp > 0 then
            GameState.addExp(fcExp)
        end
        -- 首通钻石
        local fcDiamond = stageEntry.fcDiamond or 0
        if fcDiamond > 0 then
            GameState.setGems(GameState.getGems() + fcDiamond)
            rewards[#rewards + 1] = { type = "diamond", amount = fcDiamond }
        end
        -- 首通精粹
        local fcEssence = stageEntry.fcEssence or 0
        if fcEssence > 0 then
            GameState.setEssence(GameState.getEssence() + fcEssence)
            rewards[#rewards + 1] = { type = "essence", amount = fcEssence }
        end
        -- 首通奥术粉尘
        local fcArcaneDust = stageEntry.fcArcaneDust or 0
        if fcArcaneDust > 0 then
            GameState.setArcaneDust(GameState.getArcaneDust() + fcArcaneDust)
            rewards[#rewards + 1] = { type = "arcane_dust", amount = fcArcaneDust }
        end
        -- 首通装备（单机模式直接生成并加入背包）
        local fcEquips = DropSystem.generateFirstClearEquips(stageEntry)
        local equipData = ClientDispatcher.get("equipment")
        for _, equip in ipairs(fcEquips) do
            if equipData and not EquipmentSystem.isInventoryFull(equipData) then
                EquipmentSystem.addToInventory(equipData, equip)
            end
            rewards[#rewards + 1] = {
                type       = "equip",
                templateId = equip.templateId,
                quality    = equip.quality,
                level      = equip.level,
            }
        end
        -- 首通卷轴（每个独立随机，按类型聚合）
        local scrollReward = DropSystem.generateFirstClearScrolls(stageEntry)
        if scrollReward and scrollReward.scrolls then
            local SCROLL_TO_REWARD = {
                weaponScroll    = "weapon_scroll",
                offhandScroll   = "offhand_scroll",
                armorScroll     = "armor_scroll",
                accessoryScroll = "accessory_scroll",
            }
            for field, amount in pairs(scrollReward.scrolls) do
                local getter = GameState["get" .. field:sub(1,1):upper() .. field:sub(2)]
                local setter = GameState["set" .. field:sub(1,1):upper() .. field:sub(2)]
                if getter and setter then
                    setter(getter() + amount)
                    local rewardKey = SCROLL_TO_REWARD[field]
                    if rewardKey then
                        rewards[#rewards + 1] = {
                            type   = rewardKey,
                            amount = amount,
                        }
                    end
                    print("[Standalone] 首通卷轴: type=" .. field .. " amount=" .. tostring(amount))
                end
            end
        end
        -- 噩梦及以后各章 X-5 首通：黄金钥匙 ×2
        local fcGoldenKey = StageConfig.getFirstClearGoldenKey(clearedStageId, stageEntry)
        if fcGoldenKey > 0 then
            GameState.setGoldenKey(GameState.getGoldenKey() + fcGoldenKey)
            rewards[#rewards + 1] = { type = "golden_key", amount = fcGoldenKey }
        end
        -- 单机预览：与挑战者首通规则一致（X-5 腐化石；相对 4/8/12/16/20 章 X-5 神圣石）
        local fcCorruptStone = StageConfig.getFirstClearCorruptStone
            and StageConfig.getFirstClearCorruptStone(clearedStageId, stageEntry) or 0
        if fcCorruptStone > 0 then
            GameState.setCorruptStone(GameState.getCorruptStone() + fcCorruptStone)
            rewards[#rewards + 1] = { type = "corrupt_stone", amount = fcCorruptStone }
        end
        local fcSacredStone = StageConfig.getFirstClearSacredStone
            and StageConfig.getFirstClearSacredStone(clearedStageId, stageEntry) or 0
        if fcSacredStone > 0 then
            GameState.setSacredStone(GameState.getSacredStone() + fcSacredStone)
            rewards[#rewards + 1] = { type = "sacred_stone", amount = fcSacredStone }
        end
        if #rewards > 0 then
            print("[Standalone] 首通奖励: gold=" .. tostring(fcGold)
                .. " diamond=" .. tostring(fcDiamond)
                .. " equips=" .. tostring(#fcEquips))
            RewardPopup.show("首通奖励", rewards)
        end
    end)

    -- 5.3 初始阵容同步到战斗画面 + TopBar 战力
    local initialTeam = CharacterPanel.getDeployedTeam()
    TopBar.setTotalPower(CharacterPanel.getTotalPower())
    if #initialTeam > 0 then
        BattleScene.setAllies(initialTeam)
        -- 首次进入以"寻怪中"模式启动，等待服务端数据（装备/天赋/职业）同步完毕后再开战
        BattleScene.reloadStage({ startSearching = true })
        print("[Standalone] 初始阵容同步: " .. #initialTeam .. " 个英雄（寻怪模式）")
    end

    -- 5.3 获取玩家昵称（TapTap 账号系统）
    ---@diagnostic disable-next-line: undefined-global
    local myUid = clientCloud and clientCloud.userId or nil
    ---@diagnostic disable-next-line: undefined-global
    if not myUid then myUid = lobby and lobby:GetMyUserId() or nil end
    if myUid then
        PlayerInfoPanel.setUID(myUid)
        GetUserNickname({
            userIds = { myUid },
            onSuccess = function(nicknames)
                if nicknames and nicknames[1] then
                    TopBar.setPlayerName(nicknames[1].nickname)
                    PlayerInfoPanel.setPlayerName(nicknames[1].nickname)
                    print("[Standalone] 玩家昵称: " .. nicknames[1].nickname)
                end
            end,
        })
    else
        PlayerInfoPanel.setUID("预览模式")
        print("[Standalone] lobby 不可用，UID 设置为预览模式")
    end

    -- 6. Events
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseButtonUp")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("MouseWheel", "HandleMouseWheel")

    print("[Standalone] Started — design " .. DESIGN_W .. "x" .. DESIGN_H)
end

function Standalone.Stop()
    SpinePowerUpEffect.destroy()
    if vg then
        nvgDelete(vg)
        vg = nil
    end
end

--- 清除存档后重置客户端状态并回到开始界面
--- 由 DebugPanel 的 reset_save 处理器调用
function Standalone.requestResetToStartScreen()
    local TAG = "[Standalone][DIAG-RESET]"
    local t0 = os.clock()
    print(string.format("%s requestResetToStartScreen START clock=%.4f", TAG, t0))

    -- 1. 停止 BGM & SFX
    GameBGM.stop()
    GameSFX.stop()
    print(string.format("%s step1: BGM/SFX stopped clock=%.4f", TAG, os.clock()))

    -- 2. 关闭所有打开的面板/弹窗
    if ArenaBattleScene.isOpen()    then ArenaBattleScene.close()    end
    if ArenaPage.isOpen()           then ArenaPage.close()           end
    if MarketPage.isOpen()          then MarketPage.close()          end
    if TavernPage.isOpen()          then TavernPage.close()          end
    if BlacksmithPage.isOpen()      then BlacksmithPage.close()      end
    if HeroRosterPanel.isVisible()  then HeroRosterPanel.hide()      end
    if RewardPopup.isOpen()         then RewardPopup.close()         end
    if OfflineRewardPanel.isOpen()  then OfflineRewardPanel.close()  end
    if LevelUpPopup.isOpen()        then LevelUpPopup.destroy()      end
    if PlayerInfoPanel.isOpen()     then PlayerInfoPanel.close()      end
    -- LootBoxPage 直接使用顶部引用
    if LootBoxPage.isVisible()      then LootBoxPage.hide()          end
    print(string.format("%s step2: panels closed clock=%.4f", TAG, os.clock()))

    -- 3. 重置 GameState（货币、经验等缓存）
    GameState.reset()
    print(string.format("%s step3: GameState.reset done clock=%.4f", TAG, os.clock()))

    -- 4. 重置角色面板到初始状态（只有英雄 1，等级 1）
    CharacterPanel.setInitialHeroes({1}, 1)
    print(string.format("%s step4: CharacterPanel.setInitialHeroes done clock=%.4f", TAG, os.clock()))

    -- 5. 重置战斗场景
    BattleScene.resetToDefault()
    print(string.format("%s step5: BattleScene.resetToDefault done clock=%.4f", TAG, os.clock()))

    -- 6. 重置 ClientDispatcher 中的 equipment / lootbox 为初始数据
    --    不能调用 ClientDispatcher.reset() 因为会销毁所有订阅者
    local cjson = cjson
    ClientDispatcher.handleStateUpdate(cjson.encode({
        modules = {
            equipment = { inventory = {}, equipped = {}, nextSeq = 1 },
            lootbox   = { seeds = {} },
        }
    }))
    print(string.format("%s step6: ClientDispatcher.handleStateUpdate (equip/lootbox reset) done clock=%.4f", TAG, os.clock()))

    -- 7. 重置 BottomNav 回到战斗标签（第 3 个）
    BottomNav.setSelectedIndex(3)
    print(string.format("%s step7: BottomNav.setSelectedIndex(3) done clock=%.4f", TAG, os.clock()))

    -- 8. 重置 TopBar 战力显示
    TopBar.setTotalPower(CharacterPanel.getTotalPower())
    print(string.format("%s step8: TopBar.setTotalPower done clock=%.4f", TAG, os.clock()))

    -- 9. 重新同步初始阵容到战斗画面
    local initialTeam = CharacterPanel.getDeployedTeam()
    if #initialTeam > 0 then
        BattleScene.setAllies(initialTeam)
        BattleScene.reloadStage()
    end
    print(string.format("%s step9: BattleScene.setAllies/reloadStage done teamSize=%d clock=%.4f",
        TAG, #initialTeam, os.clock()))

    -- 10. 重置开场动画状态（让清档后可以重新播放）
    IntroCutscene.reset()
    print(string.format("%s step10: IntroCutscene.reset done clock=%.4f", TAG, os.clock()))

    -- 11. 设置标志：重新进入开始界面流程
    startScreenWasOpen_ = true
    print(string.format("%s step11: startScreenWasOpen_=true clock=%.4f", TAG, os.clock()))

    -- 12. 重新打开 StartScreen
    StartScreen.reopen(sceneRef_)

    print(string.format("%s requestResetToStartScreen DONE elapsed=%.4fs clock=%.4f", TAG, os.clock() - t0, os.clock()))
end

-- ============================================================================
-- Global event handlers (SubscribeToEvent requires global function names)
-- ============================================================================

function HandleNanoVGRender(eventType, eventData)
    if not vg then return end

    nvgBeginFrame(vg, logicalW, logicalH, dpr)
    nvgScale(vg, scale, scale)

    -- 背景（screen space，填满可见区域）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenDesignW, screenDesignH)
    nvgFillColor(vg, nvgRGBA(25, 25, 35, 255))
    nvgFill(vg)

    -- 调试面板（screen space，设计区域右侧）
    DebugPanel.draw(vg, designOffsetX, screenDesignW)

    -- 进入设计空间 (1080x2400)
    nvgTranslate(vg, designOffsetX, designOffsetY)

    -- 开始界面（最高优先级，覆盖一切）
    if StartScreen.isOpen() then
        StartScreen.draw(vg)
        nvgEndFrame(vg)
        return
    end

    -- 竞技场对战全屏优先（覆盖所有其他界面）
    local arenaBattleOpen = ArenaBattleScene.isOpen()
    local dungeonBattleOpen = DungeonBattleScene.isOpen()
    if arenaBattleOpen then
        ArenaBattleScene.draw(vg)
        -- 不绘制 TopBar/BottomNav
    elseif dungeonBattleOpen then
        DungeonBattleScene.draw(vg)
        -- 不绘制 TopBar/BottomNav
    else
        -- 根据当前标签绘制对应场景内容
        local tabIndex = BottomNav.getSelectedIndex()
        if tabIndex == 1 then
            -- "角色"标签 → 角色界面
            CharacterPanel.draw(vg)
        elseif tabIndex == 2 then
            -- "日志"标签 → 日志页面
            DiaryPage.draw(vg)
        elseif tabIndex == 3 then
            -- "战斗"标签 → 战斗场景
            BattleScene.draw(vg)
        elseif tabIndex == 4 then
            -- "城镇"标签 → 城镇场景
            TownScene.draw(vg)
            -- 铁匠铺二级界面（覆盖在城镇之上）
            BlacksmithPage.draw(vg)
            -- 酒馆二级界面（覆盖在城镇之上）
            TavernPage.draw(vg)
            -- 竞技场二级界面（覆盖在城镇之上）
            ArenaPage.draw(vg)
            -- 市场二级界面（覆盖在城镇之上）
            MarketPage.draw(vg)
        end

        -- 绘制顶部信息栏和底部导航栏（二级界面打开时隐藏）
        local detailOpen = CharacterPanel.isDetailOpen()
        local smithOpen = BlacksmithPage.isOpen()
        local tavernOpen = TavernPage.isOpen()
        local arenaOpen = ArenaPage.isOpen()
        local marketOpen = MarketPage.isOpen()
        if not detailOpen and not smithOpen and not tavernOpen and not arenaOpen and not marketOpen then
            TopBar.draw(vg)
            BottomNav.draw(vg)
        elseif arenaOpen and not detailOpen and not smithOpen and not tavernOpen then
            local animP = ArenaPage.getAnimProgress()
            if animP < 1.0 then
                local fadeAlpha = 1.0 - animP
                nvgSave(vg)
                nvgGlobalAlpha(vg, fadeAlpha)
                TopBar.draw(vg)
                BottomNav.draw(vg)
                nvgRestore(vg)
            end
        elseif tavernOpen and not detailOpen and not smithOpen then
            local animP = TavernPage.getAnimProgress()
            if animP < 1.0 then
                local fadeAlpha = 1.0 - animP
                nvgSave(vg)
                nvgGlobalAlpha(vg, fadeAlpha)
                TopBar.draw(vg)
                BottomNav.draw(vg)
                nvgRestore(vg)
            end
        elseif marketOpen and not detailOpen and not smithOpen and not tavernOpen and not arenaOpen then
            local animP = MarketPage.getAnimProgress()
            if animP < 1.0 then
                local fadeAlpha = 1.0 - animP
                nvgSave(vg)
                nvgGlobalAlpha(vg, fadeAlpha)
                TopBar.draw(vg)
                BottomNav.draw(vg)
                nvgRestore(vg)
            end
        end
    end

    -- 全屏覆盖面板（最顶层）
    HeroRosterPanel.draw(vg)

    -- 玩家信息面板
    PlayerInfoPanel.draw(vg)

    -- 战利品管理页面（在奖励弹窗之下）
    LootBox.drawPage(vg)

    -- 奖励弹窗
    RewardPopup.draw(vg)

    -- 离线收益面板
    OfflineRewardPanel.draw(vg)

    -- 战斗力提升特效
    SpinePowerUpEffect.draw(vg)

    -- 冒险等级提升弹窗（最顶层）
    LevelUpPopup.draw(vg)

    -- 轮回 CG 视频（覆盖所有游戏 UI）
    if SamsaraCG.isActive() then
        SamsaraCG.draw(vg)
    end

    -- 轮回开场动画（覆盖所有游戏 UI）
    if IntroCutscene.isActive() then
        IntroCutscene.draw(vg)
    end

    nvgEndFrame(vg)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 开始界面打开时只更新它
    if StartScreen.isOpen() then
        StartScreen.update(dt)
        startScreenWasOpen_ = true
        return
    end

    -- StartScreen 刚关闭 → 自动弹出离线收益面板（调试用）
    if startScreenWasOpen_ then
        startScreenWasOpen_ = false
        OfflineRewardPanel.show({
            offlineSeconds  = 23025,
            maxSeconds      = 43200,
            multiplier      = 2.0,
            adventureExp    = 128000,
            adventurerExp   = 56000,
            rewards = {
                { type = "gold",    amount = 12500 },
                { type = "diamond", amount = 80 },
                { type = "essence", amount = 3200 },
                { type = "equip", templateId = "W5", quality = 5, level = 12 },
                { type = "equip", templateId = "W4", quality = 4, level = 8 },
                { type = "equip", templateId = "A3", quality = 3, level = 5 },
                { type = "equip", templateId = "W3", quality = 3, level = 7 },
                { type = "equip", templateId = "A2", quality = 2, level = 3 },
                { type = "equip", templateId = "W2", quality = 2, level = 4 },
                { type = "equip", templateId = "W1", quality = 1, level = 1 },
                { type = "equip", templateId = "A4", quality = 4, level = 10 },
                { type = "equip", templateId = "A5", quality = 5, level = 15 },
            },
            onClaim = function(doubled)
                print("[OfflineRewardPanel] claimed, doubled=" .. tostring(doubled))
            end,
        })
        print("[Standalone] auto-showed OfflineRewardPanel after StartScreen closed")
        GameBGM.start()
        GameSFX.start()
    end

    BottomNav.update(dt)

    -- ── BGM 轨道切换（优先级：城镇建筑 > 标签页）──
    do
        local tabIndex = BottomNav.getSelectedIndex()
        local bgmScene
        -- 城镇建筑
        if tabIndex == 4 and (BlacksmithPage.isOpen()
            or TavernPage.isOpen()
            or ArenaPage.isOpen()
            or MarketPage.isOpen()) then
            bgmScene = "town_building"
        -- 标签页
        elseif tabIndex == 2 then bgmScene = "popup"
        elseif tabIndex == 3 then bgmScene = BattleScene.isInTerminalTemple() and "samsara" or "battle"
        elseif tabIndex == 4 then bgmScene = "town"
        else bgmScene = "other"
        end
        GameBGM.setScene(bgmScene)
    end
    GameBGM.update(dt)

    -- 轮回 CG 视频更新（播放期间阻止其他 UI 更新和 BGM 切换）
    if SamsaraCG.isActive() then
        SamsaraCG.update(dt)
        return
    end

    -- 轮回开场动画更新（播放期间阻止其他 UI 更新和 BGM 切换）
    if IntroCutscene.isActive() then
        IntroCutscene.update(dt)
        return
    end

    -- 竞技场/副本对战更新（打开时独占）
    if ArenaBattleScene.isOpen() then
        ArenaBattleScene.update(dt)
    elseif DungeonBattleScene.isOpen() then
        DungeonBattleScene.update(dt)
    else
        -- 战斗场景始终更新（挂机持续进行）
        BattleScene.update(dt)
    end

    local tabIndex = BottomNav.getSelectedIndex()
    if tabIndex == 1 then
        CharacterPanel.update(dt)
    elseif tabIndex == 2 then
        DiaryPage.update(dt)
    end

    -- 角标刷新（始终执行，不受当前 tab 限制）
    BottomNav.setBadge(2, DiaryPage.hasAnyClaimable(), "redDot")

    -- 铁匠铺分解红点（背包满时提示）
    local equipData_ = ClientDispatcher.get("equipment")
    local bagFull_ = equipData_ and EquipmentSystem.isInventoryFull(equipData_) or false
    TownScene.setSmithRedDot(bagFull_)
    BlacksmithPage.setDecomposeRedDot(bagFull_)

    -- 市场/竞技场建筑红点（与 BottomNav 查询条件保持一致）
    TownScene.setMarketRedDot(MarketPage.hasPrivilegeRedDot())
    TownScene.setArenaRedDot(ArenaPage.hasTicketRedDot())

    RewardPopup.update(dt)
    OfflineRewardPanel.update(dt)
    LevelUpPopup.update(dt)
    TavernPage.update(dt)
    ArenaPage.update(dt)
    MarketPage.update(dt)
    PlayerInfoPanel.update(dt)
end

-- 完整点击判定：按下+松开位移过大视为滑动，不触发点击
local TAP_THRESHOLD = 15  -- 按下到松开的最大位移（设计像素），超过视为滑动
local pressStartDX, pressStartDY = 0, 0
local pressValid = false  -- 是否有有效的按下记录
-- 最小点击间隔（防止移动端单击误触发双击）
local MIN_TAP_INTERVAL = 0.12  -- 秒（120ms）
local lastTapTime = 0

local function openTrainingDummyBattle()
    local allies = CharacterPanel.getDeployedTeam()
    if not allies or #allies == 0 then
        print("[TrainingDummy][Standalone] no deployed heroes, cannot open")
        return
    end
    print("[TrainingDummy][Standalone] opening battle with allies=" .. tostring(#allies))
    DungeonBattleScene.open({
        allies = allies,
        data = {
            dungeonId = "training_dummy",
            floor = 1,
            monsterLevel = 1,
            monsters = { 1 },
            classBonus = "",
            classBonusValue = 0,
            rageTime = 999999,
            superRageTime = 999999,
            trainingDummy = true,
            dummyMaxHp = 1000000000000,
            dummyRegen = 1000000000000,
        },
        onClose = function()
            print("[TrainingDummy][Standalone] closed")
        end,
    })
end

function HandleMouseButtonDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local mousePos = input:GetMousePosition()
    local sx = mousePos.x / dpr / scale
    local sy = mousePos.y / dpr / scale
    local dx = sx - designOffsetX
    local dy = sy - designOffsetY
    pressStartDX, pressStartDY = dx, dy
    pressValid = true
    -- 竞技场对战全屏拦截（转发拖拽给段位奖励弹窗）
    if ArenaBattleScene.isOpen() then
        ArenaBattleScene.handleDragBegin(dx, dy)
        return
    end
    -- 副本/测试木桩全屏拦截
    if DungeonBattleScene.isOpen() then
        DungeonBattleScene.handleDragBegin(dx, dy)
        return
    end
    -- 冒险等级提升弹窗拦截（吞掉所有输入）
    if LevelUpPopup.isOpen() then return end
    -- 玩家信息面板拦截（转发拖拽给 AvatarSelectPanel）
    if PlayerInfoPanel.isOpen() then
        PlayerInfoPanel.handleDragBegin(dx, dy)
        return
    end
    -- 离线收益面板拦截
    if OfflineRewardPanel.isOpen() then
        OfflineRewardPanel.handleDragBegin(dx, dy)
        return
    end
    -- 奖励弹窗拦截
    if RewardPopup.handleDragBegin(dx, dy) then return end
    -- 战利品页面拖拽拦截
    if LootBox.handleDragBegin(dx, dy) then return end
    local tabIndex = BottomNav.getSelectedIndex()
    if tabIndex == 4 and BlacksmithPage.isOpen() then
        BlacksmithPage.handleDragBegin(dx, dy)
        return
    end
    if tabIndex == 4 and TavernPage.isOpen() then
        TavernPage.handleDragBegin(dx, dy)
        return
    end
    if tabIndex == 4 and ArenaPage.isOpen() then
        ArenaPage.handleDragBegin(dx, dy)
        return
    end
    if tabIndex == 1 then
        CharacterPanel.handleDragBegin(dx, dy)
    end
end

function HandleMouseMove(eventType, eventData)
    local mousePos = input:GetMousePosition()
    local sx = mousePos.x / dpr / scale
    local sy = mousePos.y / dpr / scale
    local dx = sx - designOffsetX
    local dy = sy - designOffsetY
    -- 竞技场对战全屏拦截（转发拖拽移动给段位奖励弹窗）
    if ArenaBattleScene.isOpen() then
        ArenaBattleScene.handleDragMove(dx, dy)
        return
    end
    -- 副本/测试木桩全屏拦截
    if DungeonBattleScene.isOpen() then
        DungeonBattleScene.handleDragMove(dx, dy)
        return
    end
    -- 冒险等级提升弹窗拦截（吞掉所有输入）
    if LevelUpPopup.isOpen() then return end
    -- 玩家信息面板拦截（转发拖拽移动给 AvatarSelectPanel）
    if PlayerInfoPanel.isOpen() then
        PlayerInfoPanel.handleDragMove(dx, dy)
        return
    end
    -- 离线收益面板拦截
    if OfflineRewardPanel.isOpen() then
        OfflineRewardPanel.handleDragMove(dx, dy)
        return
    end
    -- 奖励弹窗拦截
    if RewardPopup.handleDragMove(dx, dy) then return end
    -- 战利品页面拖拽拦截
    if LootBox.handleDragMove(dx, dy) then return end
    local tabIndex = BottomNav.getSelectedIndex()
    if tabIndex == 4 and BlacksmithPage.isOpen() then
        BlacksmithPage.handleDragMove(dx, dy)
        return
    end
    if tabIndex == 4 and TavernPage.isOpen() then
        TavernPage.handleDragMove(dx, dy)
        return
    end
    if tabIndex == 4 and ArenaPage.isOpen() then
        ArenaPage.handleDragMove(dx, dy)
        return
    end
    if tabIndex == 1 then
        CharacterPanel.handleDragMove(dx, dy)
    end
end

function HandleMouseButtonUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local mousePos = input:GetMousePosition()
    local sx = mousePos.x / dpr / scale   -- screen space
    local sy = mousePos.y / dpr / scale
    -- 设计空间
    local dx = sx - designOffsetX
    local dy = sy - designOffsetY
    -- 判断是否为有效点击（按下→松开位移小于阈值）
    local isTap = false
    if pressValid then
        local dist = math.abs(dx - pressStartDX) + math.abs(dy - pressStartDY)
        isTap = dist < TAP_THRESHOLD
    end
    pressValid = false
    -- 最小点击间隔保护（防止移动端单击误触发双击）
    if isTap then
        local now = time.elapsedTime
        if now - lastTapTime < MIN_TAP_INTERVAL then
            isTap = false
        else
            lastTapTime = now
        end
    end
    print(string.format("[Standalone][MouseUp] dx=%.0f dy=%.0f isTap=%s", dx, dy, tostring(isTap)))
    -- 开始界面拦截
    if StartScreen.isOpen() then
        if isTap then StartScreen.handleClick(dx, dy) end
        return
    end
    -- 竞技场对战全屏拦截（拖拽结束 + 点击）
    if ArenaBattleScene.isOpen() then
        ArenaBattleScene.handleDragEnd(dx, dy)
        if isTap then ArenaBattleScene.handleInput(dx, dy) end
        return
    end
    -- 副本/测试木桩全屏拦截（拖拽结束 + 点击）
    if DungeonBattleScene.isOpen() then
        DungeonBattleScene.handleDragEnd(dx, dy)
        if isTap then DungeonBattleScene.handleInput(dx, dy) end
        return
    end
    -- 冒险等级提升弹窗拦截（点击关闭）
    if LevelUpPopup.isOpen() then
        if isTap then LevelUpPopup.handleInput(dx, dy) end
        return
    end
    -- 玩家信息面板拦截（拖拽结束 + 点击处理）
    if PlayerInfoPanel.isOpen() then
        PlayerInfoPanel.handleDragEnd(dx, dy)
        if isTap then PlayerInfoPanel.handleInput(dx, dy) end
        return
    end
    -- 离线收益面板拦截（拖拽结束 + 点击）
    if OfflineRewardPanel.isOpen() then
        OfflineRewardPanel.handleDragEnd(dx, dy)
        if isTap then OfflineRewardPanel.handleInput(dx, dy) end
        return
    end
    -- 奖励弹窗拦截（拖拽结束 + 点击关闭）
    if RewardPopup.isOpen() then
        RewardPopup.handleDragEnd(dx, dy)
        if isTap then RewardPopup.handleInput(dx, dy) end
        return
    end
    -- 战利品页面拦截（拖拽结束 + 点击）
    if LootBox.isPageOpen() then
        LootBox.handleDragEnd(dx, dy)
        if isTap then LootBox.handleInput(dx, dy) end
        return
    end
    local tabIndex = BottomNav.getSelectedIndex()
    -- 铁匠铺：拖拽结束转发（与 TouchEnd 对齐）
    if tabIndex == 4 and BlacksmithPage.isOpen() then
        BlacksmithPage.handleDragEnd(dx, dy)
        if not isTap then return end
        BlacksmithPage.handleInput(dx, dy)
        return
    end
    -- 酒馆：拖拽结束转发
    if tabIndex == 4 and TavernPage.isOpen() then
        TavernPage.handleDragEnd(dx, dy)
        if not isTap then return end
        TavernPage.handleInput(dx, dy)
        return
    end
    -- 竞技场：拖拽结束转发
    if tabIndex == 4 and ArenaPage.isOpen() then
        ArenaPage.handleDragEnd(dx, dy)
        if not isTap then return end
        ArenaPage.handleInput(dx, dy)
        return
    end
    -- 角色界面：卡片拖拽落点始终处理，滚动惯性始终结算
    if tabIndex == 1 then
        if CharacterPanel.isDraggingCard() then
            CharacterPanel.handleInput(dx, dy)
            CharacterPanel.handleDragEnd(dx, dy)
            return
        end
        CharacterPanel.handleDragEnd(dx, dy)
    end
    -- 滑动操作不触发任何点击（防止滚动列表时误触）
    if not isTap then return end
    -- 以下全部是点击事件分发
    if DebugPanel.handleInput(sx, sy) then return end
    if HeroRosterPanel.handleInput(dx, dy) then return end
    -- 头像点击 → 打开玩家信息面板（TopBar 可见时生效）
    local detailOpen = CharacterPanel.isDetailOpen()
    local smithOpen = BlacksmithPage.isOpen()
    local tavernOpen = TavernPage.isOpen()
    local arenaOpen = ArenaPage.isOpen()
    local diaryOverlay = DiaryPage.hasOverlayOpen()
    print(string.format("[Standalone] avatar check: dx=%.0f dy=%.0f detail=%s smith=%s tavern=%s arena=%s arenaBattle=%s diary=%s",
        dx, dy,
        tostring(detailOpen), tostring(smithOpen), tostring(tavernOpen), tostring(arenaOpen),
        tostring(ArenaBattleScene.isOpen()), tostring(diaryOverlay)))
    if not detailOpen and not smithOpen and not tavernOpen and not arenaOpen
        and not ArenaBattleScene.isOpen() and not DungeonBattleScene.isOpen() and not diaryOverlay then
        if TopBar.hitTestTrainingDummy(dx, dy) then
            openTrainingDummyBattle()
            return
        end
        local hit = DrawUtil.hitTest(dx, dy, 98, 136, 150, 150)
        print(string.format("[Standalone] hitTest(%.0f,%.0f, 98,136, 150,150) = %s", dx, dy, tostring(hit)))
        if hit then
            PlayerInfoPanel.open()
            return
        end
    end
    if tabIndex == 1 then
        if CharacterPanel.handleInput(dx, dy) then return end
    elseif tabIndex == 2 then
        if DiaryPage.handleInput(dx, dy) then return end
    elseif tabIndex == 3 then
        if BattleScene.handleInput(dx, dy) then return end
    elseif tabIndex == 4 then
        if BlacksmithPage.isOpen() then
            BlacksmithPage.handleInput(dx, dy)
            return
        end
        if TavernPage.isOpen() then
            TavernPage.handleInput(dx, dy)
            return
        end
        if ArenaPage.isOpen() then
            ArenaPage.handleInput(dx, dy)
            return
        end
        if TownScene.handleInput(dx, dy) then return end
    end
    BottomNav.handleInput(dx, dy)
end

function HandleTouchBegin(eventType, eventData)
    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    local sx = tx / dpr / scale
    local sy = ty / dpr / scale
    local dx = sx - designOffsetX
    local dy = sy - designOffsetY
    pressStartDX, pressStartDY = dx, dy
    pressValid = true
    -- 竞技场对战全屏拦截（转发拖拽给段位奖励弹窗）
    if ArenaBattleScene.isOpen() then
        ArenaBattleScene.handleDragBegin(dx, dy)
        return
    end
    -- 副本/测试木桩全屏拦截
    if DungeonBattleScene.isOpen() then
        DungeonBattleScene.handleDragBegin(dx, dy)
        return
    end
    -- 冒险等级提升弹窗拦截（吞掉所有输入）
    if LevelUpPopup.isOpen() then return end
    -- 玩家信息面板拦截（转发拖拽给 AvatarSelectPanel）
    if PlayerInfoPanel.isOpen() then
        PlayerInfoPanel.handleDragBegin(dx, dy)
        return
    end
    -- 离线收益面板拦截
    if OfflineRewardPanel.isOpen() then
        OfflineRewardPanel.handleDragBegin(dx, dy)
        return
    end
    -- 奖励弹窗拦截
    if RewardPopup.handleDragBegin(dx, dy) then return end
    -- 战利品页面拦截
    if LootBox.handleDragBegin(dx, dy) then return end
    local tabIndex = BottomNav.getSelectedIndex()
    if tabIndex == 4 and BlacksmithPage.isOpen() then
        BlacksmithPage.handleDragBegin(dx, dy)
        return
    end
    if tabIndex == 4 and TavernPage.isOpen() then
        TavernPage.handleDragBegin(dx, dy)
        return
    end
    if tabIndex == 4 and ArenaPage.isOpen() then
        ArenaPage.handleDragBegin(dx, dy)
        return
    end
    if tabIndex == 1 then
        CharacterPanel.handleDragBegin(dx, dy)
    end
end

function HandleTouchMove(eventType, eventData)
    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    local sx = tx / dpr / scale
    local sy = ty / dpr / scale
    local dx = sx - designOffsetX
    local dy = sy - designOffsetY
    -- 竞技场对战全屏拦截（转发拖拽移动给段位奖励弹窗）
    if ArenaBattleScene.isOpen() then
        ArenaBattleScene.handleDragMove(dx, dy)
        return
    end
    -- 副本/测试木桩全屏拦截
    if DungeonBattleScene.isOpen() then
        DungeonBattleScene.handleDragMove(dx, dy)
        return
    end
    -- 冒险等级提升弹窗拦截（吞掉所有输入）
    if LevelUpPopup.isOpen() then return end
    -- 玩家信息面板拦截（转发拖拽移动给 AvatarSelectPanel）
    if PlayerInfoPanel.isOpen() then
        PlayerInfoPanel.handleDragMove(dx, dy)
        return
    end
    -- 离线收益面板拦截
    if OfflineRewardPanel.isOpen() then
        OfflineRewardPanel.handleDragMove(dx, dy)
        return
    end
    -- 奖励弹窗拦截
    if RewardPopup.handleDragMove(dx, dy) then return end
    -- 战利品页面拦截
    if LootBox.handleDragMove(dx, dy) then return end
    local tabIndex = BottomNav.getSelectedIndex()
    if tabIndex == 4 and BlacksmithPage.isOpen() then
        BlacksmithPage.handleDragMove(dx, dy)
        return
    end
    if tabIndex == 4 and TavernPage.isOpen() then
        TavernPage.handleDragMove(dx, dy)
        return
    end
    if tabIndex == 4 and ArenaPage.isOpen() then
        ArenaPage.handleDragMove(dx, dy)
        return
    end
    if tabIndex == 1 then
        CharacterPanel.handleDragMove(dx, dy)
    end
end

function HandleTouchEnd(eventType, eventData)
    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    local sx = tx / dpr / scale
    local sy = ty / dpr / scale
    local dx = sx - designOffsetX
    local dy = sy - designOffsetY
    -- 判断是否为有效点击
    local isTap = false
    if pressValid then
        local dist = math.abs(dx - pressStartDX) + math.abs(dy - pressStartDY)
        isTap = dist < TAP_THRESHOLD
    end
    pressValid = false
    -- 最小点击间隔保护（防止移动端单击误触发双击）
    if isTap then
        local now = time.elapsedTime
        if now - lastTapTime < MIN_TAP_INTERVAL then
            isTap = false
        else
            lastTapTime = now
        end
    end
    print(string.format("[Standalone][TouchEnd] dx=%.0f dy=%.0f isTap=%s start=%s lv=%s pi=%s off=%s rew=%s loot=%s",
        dx, dy, tostring(isTap),
        tostring(StartScreen.isOpen()), tostring(LevelUpPopup.isOpen()),
        tostring(PlayerInfoPanel.isOpen()), tostring(OfflineRewardPanel.isOpen()),
        tostring(RewardPopup.isOpen()), tostring(LootBox.isPageOpen())))
    -- 开始界面拦截
    if StartScreen.isOpen() then
        if isTap then StartScreen.handleClick(dx, dy) end
        return
    end
    -- 竞技场对战全屏拦截（拖拽结束 + 点击）
    if ArenaBattleScene.isOpen() then
        ArenaBattleScene.handleDragEnd(dx, dy)
        if isTap then ArenaBattleScene.handleInput(dx, dy) end
        return
    end
    -- 副本/测试木桩全屏拦截（拖拽结束 + 点击）
    if DungeonBattleScene.isOpen() then
        DungeonBattleScene.handleDragEnd(dx, dy)
        if isTap then DungeonBattleScene.handleInput(dx, dy) end
        return
    end
    -- 冒险等级提升弹窗拦截（点击关闭）
    if LevelUpPopup.isOpen() then
        if isTap then LevelUpPopup.handleInput(dx, dy) end
        return
    end
    -- 玩家信息面板拦截（拖拽结束 + 点击处理）
    if PlayerInfoPanel.isOpen() then
        PlayerInfoPanel.handleDragEnd(dx, dy)
        if isTap then PlayerInfoPanel.handleInput(dx, dy) end
        return
    end
    -- 离线收益面板拦截（拖拽结束 + 点击）
    if OfflineRewardPanel.isOpen() then
        OfflineRewardPanel.handleDragEnd(dx, dy)
        if isTap then OfflineRewardPanel.handleInput(dx, dy) end
        return
    end
    -- 奖励弹窗拦截（拖拽结束 + 点击关闭）
    if RewardPopup.isOpen() then
        RewardPopup.handleDragEnd(dx, dy)
        if isTap then RewardPopup.handleInput(dx, dy) end
        return
    end
    -- 战利品页面拦截（拖拽结束 + 点击）
    if LootBox.isPageOpen() then
        LootBox.handleDragEnd(dx, dy)
        if isTap then LootBox.handleInput(dx, dy) end
        return
    end
    local tabIndex = BottomNav.getSelectedIndex()
    -- 铁匠铺：拖拽结束转发
    if tabIndex == 4 and BlacksmithPage.isOpen() then
        BlacksmithPage.handleDragEnd(dx, dy)
        if not isTap then return end
        BlacksmithPage.handleInput(dx, dy)
        return
    end
    -- 酒馆：拖拽结束转发
    if tabIndex == 4 and TavernPage.isOpen() then
        TavernPage.handleDragEnd(dx, dy)
        if not isTap then return end
        TavernPage.handleInput(dx, dy)
        return
    end
    -- 竞技场：拖拽结束转发
    if tabIndex == 4 and ArenaPage.isOpen() then
        ArenaPage.handleDragEnd(dx, dy)
        if not isTap then return end
        ArenaPage.handleInput(dx, dy)
        return
    end
    -- 角色界面：卡片拖拽落点始终处理，滚动惯性始终结算
    if tabIndex == 1 then
        if CharacterPanel.isDraggingCard() then
            CharacterPanel.handleInput(dx, dy)
            CharacterPanel.handleDragEnd(dx, dy)
            return
        end
        CharacterPanel.handleDragEnd(dx, dy)
    end
    -- 滑动操作不触发任何点击
    if not isTap then return end
    -- 以下全部是点击事件分发
    if DebugPanel.handleInput(sx, sy) then return end
    if HeroRosterPanel.handleInput(dx, dy) then return end
    -- 头像点击 → 打开玩家信息面板（TopBar 可见时生效）
    do
        local detailOpen2 = CharacterPanel.isDetailOpen()
        local smithOpen2 = BlacksmithPage.isOpen()
        local tavernOpen2 = TavernPage.isOpen()
        local arenaOpen2 = ArenaPage.isOpen()
        local diaryOverlay2 = DiaryPage.hasOverlayOpen()
        print(string.format("[Standalone][Touch] avatar check: dx=%.0f dy=%.0f detail=%s smith=%s tavern=%s arena=%s arenaBattle=%s diary=%s",
            dx, dy,
            tostring(detailOpen2), tostring(smithOpen2), tostring(tavernOpen2), tostring(arenaOpen2),
            tostring(ArenaBattleScene.isOpen()), tostring(diaryOverlay2)))
        if not detailOpen2 and not smithOpen2 and not tavernOpen2 and not arenaOpen2
            and not ArenaBattleScene.isOpen() and not DungeonBattleScene.isOpen() and not diaryOverlay2 then
            if TopBar.hitTestTrainingDummy(dx, dy) then
                openTrainingDummyBattle()
                return
            end
            local hit = DrawUtil.hitTest(dx, dy, 98, 136, 150, 150)
            print(string.format("[Standalone][Touch] hitTest(%.0f,%.0f, 98,136, 150,150) = %s", dx, dy, tostring(hit)))
            if hit then
                PlayerInfoPanel.open()
                return
            end
        end
    end
    if tabIndex == 1 then
        if CharacterPanel.handleInput(dx, dy) then return end
    elseif tabIndex == 2 then
        if DiaryPage.handleInput(dx, dy) then return end
    elseif tabIndex == 3 then
        if BattleScene.handleInput(dx, dy) then return end
    elseif tabIndex == 4 then
        -- 铁匠铺二级界面优先拦截
        if BlacksmithPage.isOpen() then
            BlacksmithPage.handleInput(dx, dy)
            return
        end
        -- 酒馆二级界面拦截
        if TavernPage.isOpen() then
            TavernPage.handleInput(dx, dy)
            return
        end
        -- 竞技场二级界面拦截
        if ArenaPage.isOpen() then
            ArenaPage.handleInput(dx, dy)
            return
        end
        if TownScene.handleInput(dx, dy) then return end
    end
    BottomNav.handleInput(dx, dy)
end

function HandleScreenMode(eventType, eventData)
    RecalcLayout()
    print("[Standalone] ScreenMode → " .. physW .. "x" .. physH .. " dpr=" .. dpr)
end

function HandleMouseWheel(eventType, eventData)
    local wheel = eventData["Wheel"]:GetInt()
    -- 竞技场对战全屏拦截（转发滚轮给段位奖励弹窗）
    if ArenaBattleScene.isOpen() then
        ArenaBattleScene.handleScroll(wheel)
        return
    end
    -- 副本/测试木桩全屏拦截
    if DungeonBattleScene.isOpen() then
        DungeonBattleScene.handleScroll(wheel)
        return
    end
    -- 冒险等级提升弹窗拦截（吞掉所有输入）
    if LevelUpPopup.isOpen() then return end
    -- 玩家信息面板拦截（转发滚轮）
    if PlayerInfoPanel.isOpen() then
        PlayerInfoPanel.handleScroll(wheel)
        return
    end
    -- 离线收益面板拦截
    if OfflineRewardPanel.isOpen() then
        OfflineRewardPanel.handleScroll(wheel)
        return
    end
    -- 奖励弹窗拦截
    if RewardPopup.isOpen() then
        RewardPopup.handleScroll(wheel)
        return
    end
    -- 战利品页面拦截
    if LootBox.isPageOpen() then
        LootBox.handleScroll(wheel)
        return
    end
    local tabIndex = BottomNav.getSelectedIndex()
    if tabIndex == 4 and BlacksmithPage.isOpen() then
        BlacksmithPage.handleScroll(wheel)
        return
    end
    if tabIndex == 4 and TavernPage.isOpen() then
        TavernPage.handleScroll(wheel)
        return
    end
    if tabIndex == 4 and ArenaPage.isOpen() then
        ArenaPage.handleScroll(wheel)
        return
    end
    if tabIndex == 1 then
        CharacterPanel.handleScroll(wheel)
    end
    HeroRosterPanel.handleScroll(wheel * 60)
end

return Standalone
