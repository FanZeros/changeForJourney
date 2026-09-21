---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- Standalone - 单机模式入口（当前项目为单机：.project/settings.json multiplayer.enabled=false）
-- 职责: 创建场景/NanoVG/字体、分帧启动、Update 主循环、事件订阅
-- 横屏绘制/输入已拆到 network/StandaloneHorizon.lua
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
local ChurchPage        = require("ui.ChurchPage")
local TavernPage        = require("ui.TavernPage")
local MarketPage        = require("ui.MarketPage")
local DungeonBattleScene = require("ui.DungeonBattleScene")
local TowerBattleScene   = require("ui.TowerBattleScene")
local TowerBuffPick      = require("ui.TowerBuffPick")
local DungeonPage        = require("ui.DungeonPage")
local BackpackPanel      = require("ui.BackpackPanel")
local LootBox           = require("ui.LootBox")
local LootBoxPage       = require("ui.LootBoxPage")
local LevelUpPopup      = require("ui.LevelUpPopup")
local BattleCombat      = require("ui.BattleCombat")
local OfflineRewardPanel = require("ui.OfflineRewardPanel")
local PlayerInfoPanel   = require("ui.PlayerInfoPanel")
local RedeemCodePanel   = require("ui.RedeemCodePanel")
local MailPanel         = require("ui.MailPanel")
local AnnouncementPanel = require("ui.AnnouncementPanel")
local AnnouncementConfig = require("shared.AnnouncementConfig")
local DiaryPage         = require("ui.DiaryPage")
local StartScreen       = require("ui.StartScreen")
local DarkTitleScreen   = require("ui.DarkTitleScreenGate")  -- [DarkTitleScreen] 横屏暗黑标题
local BattleTriPage     = require("ui.BattleTriPage")    -- [三行并行] 三行战斗区
local SweepDialog       = require("ui.SweepDialog")          -- [三行并行] 全窗模态弹窗
local PlayerStore       = require("client.data.PlayerStore") -- [单机] 数据缓存（扫荡/选关弹窗读取 battle 模块）
local DamageStatsPanel  = require("ui.DamageStatsPanel")     -- [三行并行] 全窗模态弹窗
local StageSelectDialog = require("ui.StageSelectDialog")    -- [三行并行] 全窗模态弹窗
local BattleLayout      = require("core.BattleLayout")   -- [三行并行] 布阵模式切换
local ProjectileSystem  = require("ui.ProjectileSystem") -- [三行并行] 渲染缩放
local EventBus          = require("core.EventBus")
local GameEvents        = require("config.GameEvents")
local GameBGM           = require("systems.GameBGM")
local GameSFX           = require("systems.GameSFX")
local BattleEffects     = require("ui.BattleEffects")    -- [三行并行] 渲染缩放
local SpinePowerUpEffect = require("ui.SpinePowerUpEffect")
local IntroCutscene      = require("ui.IntroCutscene")
local LetterIntro        = require("ui.LetterIntro")          -- [LetterIntro] 先祖来信（新档开场）
local CharacterDetail    = require("ui.CharacterDetail")  -- [三队并行] 中缝返回键目标
local ScenarioDialogue   = require("ui.ScenarioDialogue")     -- [LetterIntro] 情景对话
local ScenarioDialogueConfig = require("config.ScenarioDialogueConfig") -- [LetterIntro] 情景配置
local DrawUtil           = require("core.DrawUtil")
local DarkIcon           = require("core.DarkIcon")  -- [暗黑化 P0] 矢量图标库 + 画廊验收页
local StandaloneSave     = require("network.StandaloneSave") -- [单机存档] 本地快照/恢复（无联网）
local Horizon           = require("network.StandaloneHorizon") -- [重构] 横屏绘制/输入
local ClientMsgHandler   = require("network.ClientMessageHandler")
local LocalActionBridge  = require("network.LocalActionBridge")
local TaskPanel          = require("ui.TaskPanel")
local SignInPanel        = require("ui.SignInPanel")

local Standalone = {}

local localBridgeReady_ = false

local function localSendAction(action, params)
    return require("network.Client").sendAction(action, params)
end

--- 单机无服务器：所有 Client.sendAction 落到本地 Handler
---@param action string
---@param params table|nil
---@return boolean handled
function Standalone.tryLocalAction(action, params)
    if not localBridgeReady_ then
        return false
    end
    return LocalActionBridge.dispatch(action, params)
end

-- NanoVG context & font
local vg = nil
local sceneRef_ = nil  -- 保存 scene 引用，供 requestResetToStartScreen 使用
local startScreenWasOpen_ = false
local postStartFlowDone_ = false  -- [LetterIntro] 开场/离线收益只触发一次（等标题关闭）
local fontNormal = -1
local bootQueue_ = nil
local bootIdx_ = 0
local bootReady_ = false
-- [启动优化] 标题提前解锁：核心 UI（到 TownScene 为止）完成后即可点击进入，
-- 弹窗类 init / 接线 / firstStage 在标题后的后台帧继续分步消化。
-- 用户反馈的 64~66% 卡死均为旧包行为；提前解锁可把剩余重活彻底移出"进游戏前"。
local TITLE_UNLOCK_STEP = 9

local function pumpBootQueue_()
    if not bootQueue_ then return end
    -- 每帧最多消化 8ms，避免单步解码把预览判定成引擎异常
    local tFrame = time.elapsedTime
    while bootQueue_ and (time.elapsedTime - tFrame) < 0.008 do
        bootIdx_ = bootIdx_ + 1
        local step = bootQueue_[bootIdx_]
        if not step then
            bootQueue_ = nil
            bootReady_ = true; horizonCtx.bootReady = true
            DarkTitleScreen.setReady(true)
            print("[Standalone] boot queue complete, title unlocked")
            return
        end
        local name, fn = step[1], step[2]
        local t0 = time.elapsedTime
        local ok, err = pcall(fn)
        local dt = time.elapsedTime - t0
        local total = bootQueue_ and #bootQueue_ or bootIdx_
        if not ok then
            print("[Standalone] boot step FAIL " .. tostring(name) .. ": " .. tostring(err))
        else
            print(string.format("[Standalone] boot step %d/%d %s (%.0fms)",
                bootIdx_, total, name, dt * 1000))
        end
        DarkTitleScreen.loadDone = bootIdx_
        DarkTitleScreen.loadTotal = total
        DarkTitleScreen.loadPercent = math.floor(bootIdx_ * 100 / math.max(1, total))
        -- [启动诊断] 加载条上直接显示步骤名与耗时，便于真机定位哪一步超帧预算
        DarkTitleScreen.loadStep = name
        DarkTitleScreen.loadStepMs = math.floor(dt * 1000)
        if bootIdx_ >= TITLE_UNLOCK_STEP then
            -- 核心步骤完成：解锁标题（后台继续泵完剩余步骤）
            bootReady_ = true; horizonCtx.bootReady = true
            DarkTitleScreen.setReady(true)
        else
            DarkTitleScreen.setReady(false)
        end
        if dt >= 0.008 then break end
    end
end

-- [一次性加载] 三段式加载：
--   FG 前台预载：进游戏前只载 80MB 核心 UI（小图优先，进度遮罩），快进游戏
--   BG 后台补载：游戏运行中每帧 3ms 温和补载剩余小图，无感
--   惰性：>1MB 大图（地图/立绘/弹窗底）保持首次使用时加载（与原版一致，去重包装保证只载一次）
-- 自适应低端设备：不把 500MB+ 全量贴图塞进显存，避免卡顿/OOM
local preload_ = { active = false, bg = false, list = {}, idx = 0, bytes = 0, deadline = nil,
                    dwpActive = false, dwpDone = 0, dwpTotal = 0, skipWait = false }
local PRELOAD_FG_BUDGET = 80 * 1024 * 1024   -- 前台预载字节预算
local PRELOAD_TIME_LIMIT = 180               -- DWP 预下载等待上限（秒）；超时后仍允许进入，避免永久卡死
local BG_FRAME_BUDGET = 0.003                -- 后台补载每帧时间预算（秒）
local BG_SKIP_SIZE = 1024 * 1024             -- 后台跳过的大图阈值（1MB，保持惰性）

-- Design resolution (Mode A — 1080x2400 竖屏)
local DESIGN_W = GameConfig.Design.WIDTH
local DESIGN_H = GameConfig.Design.HEIGHT

-- [重构] 横屏模块共享状态（表引用，Horizon 与本文件读写同一份）
local horizonCtx = {
    vg = nil,
    logicalW = 0,
    logicalH = 0,
    dpr = 1,
    DESIGN_W = DESIGN_W,
    DESIGN_H = DESIGN_H,
    bootReady = false,
    preload = preload_,
    drawPreloadOverlay = nil, -- 下方 DrawPreloadOverlay 定义后补上
}

--- [一次性加载] 预载进度遮罩（全屏，W/H 为当前绘制空间尺寸；须在退出变换内调用）
local function DrawPreloadOverlay(vg, W, H)
    -- 进度源: DWP 下载进度（等待期主显示）；fallback 兼容旧 idx/total
    local total = (preload_.dwpTotal > 0) and preload_.dwpTotal or #preload_.list
    local done = (preload_.dwpTotal > 0) and preload_.dwpDone or preload_.idx
    local p = total > 0 and (done / total) or 0
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(13, 11, 9, 255))
    nvgFill(vg)
    DrawUtil.drawTextStroke(vg, W * 0.5, H * 0.42, "资源下载中",
        math.floor(H * 0.034), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        240, 199, 94, 3)
    local bw = W * 0.42
    local bh = math.max(10, H * 0.008)
    local bx = (W - bw) * 0.5
    local by = H * 0.48
    DarkIcon.drawNine(vg, "slot", bx, by, bw, bh)
    local fw = math.max(bh - 6, (bw - 6) * p)
    DarkIcon.drawNine(vg, "fill", bx + 3, by + 3, fw, bh - 6)
    DrawUtil.drawTextStroke(vg, W * 0.5, by + bh * 2.4,
        string.format("%d / %d", done, total),
        math.floor(H * 0.024), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        216, 201, 163, 2)
end

horizonCtx.drawPreloadOverlay = DrawPreloadOverlay
Horizon.bind(horizonCtx)

-- [Standalone] battle 状态本地同步：无 Server 推送时，把 BattleScene 本地进度
-- （maxStageId_/clearedStages）每秒比对一次，变化才经 handleStateUpdate 写入，
-- 供 TutorialManager / BottomNav / DungeonBattleScene 的建筑与页签解锁判定使用
local battleSync = { lastMax = -1, lastCleared = -1, acc = 0 }
local function SyncBattleState(dt)
    battleSync.acc = battleSync.acc + (dt or 0)
    if battleSync.acc < 1.0 then return end
    battleSync.acc = 0
    local maxId = BattleScene.getMaxStageId()
    local cleared = BattleScene.getClearedStages()
    local clearedN = 0
    for _ in pairs(cleared) do clearedN = clearedN + 1 end
    if maxId == battleSync.lastMax and clearedN == battleSync.lastCleared then return end
    if battleSync.lastMax == -1 then
        print("[Standalone] battle 状态首次同步: maxStageId=" .. tostring(maxId) .. ", cleared=" .. clearedN)
    end
    battleSync.lastMax = maxId
    battleSync.lastCleared = clearedN
    local clearedStr = {}
    for k in pairs(cleared) do clearedStr[tostring(k)] = true end
    ClientDispatcher.handleStateUpdate(cjson.encode({
        modules = { battle = { maxStageId = maxId, clearedStages = clearedStr } }
    }))
end

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
    horizonCtx.logicalW = logicalW
    horizonCtx.logicalH = logicalH
    horizonCtx.dpr = dpr
    horizonCtx.DESIGN_W = DESIGN_W
    horizonCtx.DESIGN_H = DESIGN_H
end

-- ============================================================================
-- Module API
-- ============================================================================

--- 分帧启动完成后的接线（必须在 CharacterPanel/BattleScene/TownScene init 之后）
function Standalone._bootWiring()
    -- 5.1 阵容变更回调：角色面板出战变动 → 同步战斗画面 → 重载关卡 → 更新 TopBar 战力
    -- [三队并行] 回调携带 teamIdx：队1 同步战斗画面；队2/3 编队先本地生效（并行战斗 Phase 3 接入）
    CharacterPanel.setOnTeamChanged(function(teamIdx)
        teamIdx = tonumber(teamIdx) or 1
        local team = CharacterPanel.getDeployedTeam(teamIdx)
        local deployedIds = {}
        for _, unit in ipairs(team) do
            if unit.heroId then
                deployedIds[#deployedIds + 1] = unit.heroId
            end
        end
        if localBridgeReady_ then
            localSendAction(require("shared.Protocol").ACTION_TYPES.SET_TEAM, {
                teamIdx = teamIdx,
                heroIds = deployedIds,
            })
        end
        if teamIdx ~= 1 then
            print("[Standalone] 队伍" .. teamIdx .. " 编队变更")
            return
        end
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
    -- [三栏并行] 提取为局部函数，BattleScene（栏1）与 BattleTriPage（栏2/3）共用
    local handleKillRewards = function(data)
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
    end
    BattleScene.setOnEnemyKill(handleKillRewards)
    BattleTriPage.setOnKill(handleKillRewards)  -- [三栏并行] 栏2/3 击杀奖励同源

    -- 5.15 城镇铁匠铺点击 → 打开铁匠铺界面
    TownScene.setOnSmithClick(function()
        BlacksmithPage.init(vg)
        BlacksmithPage.open()
    end)
    -- 城郊礼拜堂点击 → 打开教堂界面（转职/天赋/祈祷）
    TownScene.setOnChurchClick(function()
        ChurchPage.init(vg)
        ChurchPage.open()
    end)
    -- 5.16 城镇酒馆点击 → 打开酒馆界面
    TownScene.setOnTavernClick(function()
        TavernPage.init(vg)
        TavernPage.open()
    end)
    -- 5.18 城镇市场点击 → 打开市场界面
    TownScene.setOnMarketClick(function()
        MarketPage.init(vg)
        MarketPage.open()
    end)
    -- 5.25 城镇仓库点击 → 打开背包（横屏全窗模态）
    TownScene.setOnWarehouseClick(function()
        BackpackPanel.open("left")
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

    -- 5.242 heroes 初始状态注入：Standalone 模式无 Server 推送，右面板"我的冒险家"
    -- （CharacterPanel.ownedSet）依赖 heroes 模块状态；默认大狗嚼 Lv1 已部署
    if not ClientDispatcher.get("heroes") then
        local cjson = cjson
        ClientDispatcher.handleStateUpdate(cjson.encode({
            modules = { heroes = {
                roster = { [1] = { level = 1, exp = 0, shards = 0 } },
                deployed = { 1 },
            } }
        }))
        print("[Standalone] 初始化 heroes 数据（大狗嚼 Lv1）")
    end

    PlayerStore.Subscribe("signin", function(data, _fieldKey)
        if data then SignInPanel.setSignInData(data) end
    end)
    PlayerStore.Subscribe("task", function(data, _fieldKey)
        if data then TaskPanel.setTaskData(data) end
    end)
    PlayerStore.Subscribe("market", function(data, _fieldKey)
        if data then MarketPage.setMarketData(data) end
    end)

    LocalActionBridge.init()
    localBridgeReady_ = true
    do
        local mailData = ClientDispatcher.get("mail")
        if mailData then
            local okMail, MailService = pcall(require, "server.mail.MailService")
            if okMail and MailService.BuildMailList then
                MailPanel.setMailData(MailService.BuildMailList(1))
            end
        end
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

    -- 5.24 轮回回调：倒计时结束 → 播放开场动画 → 完成关卡加载
    BattleScene.setOnReincarnate(function(data)
        print("[Standalone] reincarnation triggered, starting intro cutscene (difficulty "
            .. tostring(data.fromDifficulty) .. " → " .. tostring(data.toDifficulty) .. ")")
        IntroCutscene.reset()
        IntroCutscene.start(function()
            print("[Standalone] reincarnation intro finished, completing stage load")
            BattleScene.completeReincarnation()
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
                helmetScroll    = "helmet_scroll",
                shoesScroll     = "shoes_scroll",
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
            RewardPopup.show("首通奖励", rewards, { row = 1 })  -- [三行并行] 卡在行1内显示
        end
    end)

    -- 5.3 初始阵容同步/关卡重载已拆到 boot 队列独立步 firstStage
    --     （loadStage 内生成敌人+重置战斗，原与全部接线同帧执行会撑爆帧预算）

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

    print("[Standalone] boot wiring done")
end

function Standalone.Start()
    -- 0. PlayerStore 初始化：单机模式下此前从未调用（仅多人 Client.lua 调），
    --    导致 SyncBattleState 写入的 battle 模块不会落到 PlayerStore 缓存，
    --    扫荡/选关弹窗读 PlayerStore.Get("battle") 恒为 nil → "未知关卡"
    PlayerStore.Init()

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
    horizonCtx.vg = vg
    if not vg then
        print("[Standalone] ERROR: nvgCreate failed")
        return
    end

    -- 2.5 [一次性加载] 全局贴图去重：同一路径全生命周期只加载一次，
    -- 启动预载与各模块 init 共用同一句柄，避免重复占用显存与二次解码
    local handleCache = {}
    local origNvgCreateImage = nvgCreateImage
    nvgCreateImage = function(ctx, path, flags)
        local cached = handleCache[path]
        if cached then return cached end
        local handle = origNvgCreateImage(ctx, path, flags)
        if handle and handle >= 0 then handleCache[path] = handle end
        return handle
    end

    -- 3. Font
    fontNormal = nvgCreateFont(vg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
    if fontNormal < 0 then
        print("[Standalone] ERROR: font load failed")
    end

    -- 4. Layout
    RecalcLayout()

    -- 4.5 碎片角标（头像按需加载）
    DrawUtil.initShardAssets(vg)

    -- 4.8 [单机存档] 恢复本地存档（GameState + Dispatcher 各模块）
    -- ⚠️ 须在一切 UI/数据初始化之前：各系统初始化均为 "if not get(x)" 守卫
    StandaloneSave.RestoreData()

    -- 5. 先出标题：只加载标题必要贴图，其余模块分帧补 init，避免预览首帧卡死
    StartScreen.init(vg, scene)
    DarkTitleScreen.init(vg)
    DarkTitleScreen.setReady(false)
    bootQueue_ = {
        { "LetterIntro", function() LetterIntro.init(vg) end },
        { "TopBar", function() TopBar.init(vg) end },
        { "BottomNav", function() BottomNav.init(vg) end },
        { "BattleScene", function() BattleScene.init(vg) end },
        { "IntroCutscene", function() IntroCutscene.init(vg, scene) end },
        { "ScenarioDialogue", function() ScenarioDialogue.init(vg, scene) end },
        { "CharacterPanel", function() CharacterPanel.init(vg) end },
        { "DiaryPage", function() DiaryPage.init(vg) end },
        { "TownScene", function() TownScene.init(vg) end },
        { "RewardPopup", function() RewardPopup.init(vg) end },
        { "OfflineRewardPanel", function() OfflineRewardPanel.init(vg) end },
        { "LevelUpPopup", function() LevelUpPopup.init(vg) end },
        { "PlayerInfoPanel", function() PlayerInfoPanel.init(vg) end },
        { "SpinePowerUp", function() SpinePowerUpEffect.init() end },
        { "bootWiring", function() Standalone._bootWiring() end },
        { "firstStage", function()
            -- [启动优化] 初始阵容同步 + 关卡重载：独立一帧执行
            -- （loadStage 生成敌人/重置战斗较重，原挤在 bootWiring 同帧导致 97-98% 卡死）
            -- [单机存档] 回灌战斗进度（须在阵容同步前：setBattleData 先切到存档关卡，
            -- 随后 setAllies + reloadStage 用恢复出的阵容重载同一关卡）
            StandaloneSave.ApplyBattleProgress()
            TopBar.markAvatarViewed()
            TopBar.setTotalPower(CharacterPanel.getTotalPower())
            local initialTeam = CharacterPanel.getDeployedTeam()
            if #initialTeam > 0 then
                BattleScene.setAllies(initialTeam)
                -- 首次进入以"寻怪中"模式启动，等待服务端数据（装备/天赋/职业）同步完毕后再开战
                BattleScene.reloadStage({ startSearching = true })
                print("[Standalone] 初始阵容同步: " .. #initialTeam .. " 个英雄（寻怪模式）")
            end
        end },
    }
    bootIdx_ = 0
    print("[Standalone] boot queue " .. #bootQueue_ .. " steps (title first)")

    -- 轻量接线（不解码贴图，可在首帧完成）
    ClientMsgHandler.setup({ sendAction = localSendAction })
    ClientMsgHandler.setupDataSubscriptions()
    AnnouncementPanel.setAnnouncementData(AnnouncementConfig.buildWithDates(0))

    RedeemCodePanel.setSendAction(function(action, params)
        local sent = localSendAction(action, params)
        if not sent then
            RedeemCodePanel.onActionResult({ success = false, reason = "本地处理失败", redeemAction = true })
        end
    end)
    MailPanel.setSendAction(localSendAction)
    SignInPanel.setSendAction(localSendAction)
    TaskPanel.setSendAction(localSendAction)
    TavernPage.setSendAction(localSendAction)
    MarketPage.setSendAction(localSendAction)

    -- 5.05 冒险等级提升弹窗：监听 PLAYER_LEVEL_UP 事件，并刷新解锁状态
    EventBus.on(GameEvents.PLAYER_LEVEL_UP, function(data)
        local newLevel = data.level
        local unlocks = ExpTable.getLevelUnlocks(newLevel)
        LevelUpPopup.show(newLevel, unlocks)
        -- 刷新各模块解锁状态
        CharacterPanel.refreshSlotUnlocks()
        BottomNav.refreshUnlockState(vg)
    end)

    -- 5.1~5.3 接线延后到 bootWiring

    -- 6. Events
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")

    -- 7. 不再全量 DownloadResources(711 张/250MB)：预览/Web 会卡死在标题。
    --    图片按需 DWP + nvgCreateImage 去重缓存；标题可立即点击。
    DarkTitleScreen.setReady(false)  -- 等 boot 队列完成再解锁
    print("[Standalone] skip full AssetManifest DWP wait")

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
    StandaloneSave.Flush()  -- [单机存档] 退出前立即落盘
    SpinePowerUpEffect.destroy()
    if vg then
        nvgDelete(vg)
        vg = nil
    end
end

--- [LetterIntro] StartScreen 关闭后的离线收益弹窗（原 StartScreen 关闭钩子内容提取）
local function showOfflineRewardPanel_()
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
end

--- [LetterIntro] 新档标记开场剧情完成（session.introCompleted，模块级整体替换需带全字段）
local function markIntroCompleted_()
    local sessionData = ClientDispatcher.get("session") or {}
    local claimed = sessionData.claimedScenarios or {}
    claimed["1"] = true  -- 跳过情景1仍标记已领取，避免后续系统再拉起
    local updated = {
        lastOnlineTime   = sessionData.lastOnlineTime or 0,
        firstLoginTime   = sessionData.firstLoginTime or 0,
        introCompleted   = true,
        claimedScenarios = claimed,
    }
    ClientDispatcher.handleStateUpdate(cjson.encode({ modules = { session = updated } }))
    print("[Standalone] intro completed flag saved (session.introCompleted=true, scenario 1 claimed)")
end

--- [LetterIntro] 新档开场链：只播先祖来信，结束后直接解锁进游戏（不再播睁眼过场/情景1）
local function startIntroChain_()
    GameBGM.setScene("letter", { fromStart = true })
    LetterIntro.start(function()
        print("[Standalone] letter finished, skip cutscene/scenario, unlocking")
        GameBGM.setScene("battle", { fromStart = true })
        markIntroCompleted_()
        showOfflineRewardPanel_()
    end)
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
    if MarketPage.isOpen()          then MarketPage.close()          end
    if TavernPage.isOpen()          then TavernPage.close()          end
    if BlacksmithPage.isOpen()      then BlacksmithPage.close()      end
    if ChurchPage.isOpen()          then ChurchPage.close()          end
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

    -- 6. 重置 ClientDispatcher 中的 equipment / lootbox / session 为初始数据
    --    不能调用 ClientDispatcher.reset() 因为会销毁所有订阅者
    local cjson = cjson
    ClientDispatcher.handleStateUpdate(cjson.encode({
        modules = {
            equipment = { inventory = {}, equipped = {}, nextSeq = 1 },
            lootbox   = { seeds = {} },
            session   = { lastOnlineTime = 0, firstLoginTime = 0, introCompleted = false },
        }
    }))
    print(string.format("%s step6: ClientDispatcher.handleStateUpdate (equip/lootbox/session reset) done clock=%.4f", TAG, os.clock()))

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
    LetterIntro.reset()
    print(string.format("%s step10: IntroCutscene.reset done clock=%.4f", TAG, os.clock()))

    -- 11. 设置标志：重新进入开始界面流程（等标题关闭后再走开场链）
    startScreenWasOpen_ = true
    postStartFlowDone_ = false
    print(string.format("%s step11: startScreenWasOpen_=true clock=%.4f", TAG, os.clock()))

    -- 12. 重新打开 StartScreen
    StartScreen.reopen(sceneRef_)

    print(string.format("%s requestResetToStartScreen DONE elapsed=%.4fs clock=%.4f", TAG, os.clock() - t0, os.clock()))
end

-- ============================================================================
-- Global event handlers (SubscribeToEvent requires global function names)
-- ============================================================================

function HandleNanoVGRender(eventType, eventData)
    return Horizon.render()
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    -- 分帧启动：每帧 1 个模块 init，标题可先画出来
    pumpBootQueue_()
    if not bootReady_ then
        local dt = eventData["TimeStep"]:GetFloat()
        if StartScreen.isOpen() then StartScreen.update(dt) end
        if DarkTitleScreen.isOpen() then DarkTitleScreen.update(dt) end
        return
    end

    -- [DWP 异步预下载] 等待期：
    --   1) 标题画面可显示，但资源未完成前不允许进入（避免无背景界面）
    --   2) 下载完成后解锁标题点击；超时后仍解锁，避免永久卡死
    --   3) 主线程全程不做任何同步加载
    if preload_.active then
        local dt = eventData["TimeStep"]:GetFloat()
        if StartScreen.isOpen() then
            StartScreen.update(dt)
        end
        if DarkTitleScreen.isOpen() then
            DarkTitleScreen.update(dt)
        end
        local total = preload_.dwpTotal
        local done = preload_.dwpDone
        local pct = (total > 0) and math.floor(done * 100 / total) or 0
        DarkTitleScreen.loadPercent = pct
        DarkTitleScreen.loadDone = done
        DarkTitleScreen.loadTotal = total
        DarkTitleScreen.setReady(false)

        if preload_.dwpActive and preload_.deadline == nil then
            preload_.deadline = time.elapsedTime + PRELOAD_TIME_LIMIT
        end
        local timedOut = false
        if preload_.dwpActive and preload_.deadline ~= nil
           and time.elapsedTime > preload_.deadline then
            timedOut = true
            preload_.dwpActive = false
            print("[Standalone] DWP 预下载超时(" .. PRELOAD_TIME_LIMIT .. "s)，解锁进入（引擎后台继续）")
        end
        if not preload_.dwpActive then
            preload_.active = false
            DarkTitleScreen.setReady(true)
            print("[Standalone] DWP 预下载等待结束（" .. pct .. "%），标题可点击进入"
                .. (timedOut and " [timeout]" or ""))
            -- 不 return：本帧立刻进入下方开场判定
        else
            return
        end
    end

    local dt = eventData["TimeStep"]:GetFloat()

    -- [Standalone] battle 状态本地同步（建筑/页签解锁判定依赖）
    SyncBattleState(dt)

    -- [单机存档] 变更检测 + 防抖落盘
    StandaloneSave.Update(dt)

    -- 开始界面打开时只更新它
    if StartScreen.isOpen() then
        StartScreen.update(dt)
        startScreenWasOpen_ = true
        return
    end

    -- [DarkTitleScreen] 横屏标题动画（预载/游戏在标题下方继续进行）
    if DarkTitleScreen.isOpen() then
        DarkTitleScreen.update(dt)
        startScreenWasOpen_ = true
        return
    end

    -- 开始页/标题刚关闭 → 老档弹离线收益；新档走开场链（先祖来信→过场→情景1）
    -- 必须等 DarkTitleScreen 关闭后再播，否则信件会被标题盖住且点击被吞
    if not postStartFlowDone_ then
        postStartFlowDone_ = true
        startScreenWasOpen_ = false
        GameBGM.start()
        GameSFX.start()
        local sessionData = ClientDispatcher.get("session")
        local introDone = sessionData and sessionData.introCompleted or false
        if introDone then
            showOfflineRewardPanel_()
        else
            print("[Standalone] new save detected, starting intro chain (letter → cutscene → scenario 1)")
            startIntroChain_()
        end
    end

    BottomNav.update(dt)

    -- ── BGM 轨道切换（优先级：城镇建筑 > 标签页）──
    -- [LetterIntro] 开场链（信/过场/情景1）期间不自动切轨，轨道由开场链自控
    if not (LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive()) then
    do
        local tabIndex = BottomNav.getSelectedIndex()
        local bgmScene
        -- 城镇建筑
        if tabIndex == 4 and (BlacksmithPage.isOpen()
            or ChurchPage.isOpen()
            or TavernPage.isOpen()
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
    end -- [LetterIntro] 守卫闭合
    GameBGM.update(dt)

    -- [LetterIntro] 先祖来信更新（信件期间独占，阻止其他 UI 更新）
    if LetterIntro.isOpen() then
        LetterIntro.update(dt)
        return
    end

    -- 轮回开场动画更新（播放期间阻止其他 UI 更新和 BGM 切换）
    if IntroCutscene.isActive() then
        IntroCutscene.update(dt)
        return
    end

    -- [LetterIntro] 情景对话更新（large 全屏期间阻止其他 UI 更新）
    if ScenarioDialogue.isActive() then
        ScenarioDialogue.update(dt)
        if ScenarioDialogue.isFullscreen() then
            return
        end
    end

    -- [三行并行] 横屏专用: 战斗布局恒为 strip（竖屏 classic 已移除）
    BattleLayout.setMode("strip")
    local triRenderScale = BattleTriPage.isOpen() and BattleLayout.CARD_SCALE or 1.0
    ProjectileSystem.setRenderScale(triRenderScale)
    BattleEffects.setRenderScale(triRenderScale)
    if BattleTriPage.isOpen() and (DungeonBattleScene.isOpen() or TowerBattleScene.isActive()) then
        BattleTriPage.close()
    end

    -- 副本/通天塔对战更新（打开时独占）
    if TowerBattleScene.isActive() then
        TowerBattleScene.update(dt)
    elseif DungeonBattleScene.isOpen() then
        DungeonBattleScene.update(dt)
    elseif BattleTriPage.isOpen() then
        -- [三栏并行] 三栏页内部会以 default 状态驱动 BattleScene.update（栏1 引擎）
        BattleTriPage.update(dt)
    else
        -- 战斗场景始终更新（挂机持续进行）
        BattleScene.update(dt)
    end

    local tabIndex = BottomNav.getSelectedIndex()
    -- [三行并行] 三行战斗区常驻: tab3 下恒开（Dungeon 独占时由守卫暂收, 关闭后自动重开）
    if tabIndex == 3 and not BattleTriPage.isOpen()
        and not DungeonBattleScene.isOpen() and not TowerBattleScene.isActive() then
        BattleTriPage.open()
    end
    -- 临时验证钩子: 无输入环境强制打开三栏页（仅 _validate_entry.lua 置位时生效）
    ---@diagnostic disable-next-line: undefined-global
    if H_AUTO_OPEN_TRI and H_skipDone and not BattleTriPage.isOpen() then
        BattleTriPage.open()
    end
    -- 临时验证钩子: 无输入环境强制打开任意 ui 面板（仅 _validate_entry.lua 置位时生效，B3/B5 截图验收用）
    ---@diagnostic disable-next-line: undefined-global
    if H_AUTO_TAB and H_skipDone and not H_shotTabSet then
        H_shotTabSet = true
        if math.floor(H_AUTO_TAB) ~= 3 and BattleTriPage.isOpen() then
            BattleTriPage.close()  -- 避免三栏战斗页全屏覆盖目标面板
        end
        BottomNav.setSelectedIndex(math.floor(H_AUTO_TAB))
        print("[ValidateHook] switched tab: " .. tostring(H_AUTO_TAB))
    end
    ---@diagnostic disable-next-line: undefined-global
    if H_AUTO_OPEN_PANEL and H_skipDone and not H_shotPanelOpened then
        H_shotPanelOpened = true
        local panelMod = require("ui." .. tostring(H_AUTO_OPEN_PANEL))
        if panelMod and panelMod.open then
            panelMod.open()
            print("[ValidateHook] opened panel: " .. tostring(H_AUTO_OPEN_PANEL))
        end
    end
    if tabIndex == 1 then
        CharacterPanel.update(dt)
    elseif tabIndex == 2 then
        DiaryPage.update(dt)
    elseif tabIndex == 5 then
        DungeonPage.update(dt)
    end
    -- [仓库入口] 背包左栏页动画由宿主驱动（DiaryPage 已让位）
    if BackpackPanel.isOpen() and BackpackPanel.isLeftMode() then
        BackpackPanel.update(dt)
    end

    -- 角标刷新（始终执行，不受当前 tab 限制）
    BottomNav.setBadge(2, DiaryPage.hasAnyClaimable(), "redDot")

    -- 铁匠铺分解红点（背包满时提示）
    local equipData_ = ClientDispatcher.get("equipment")
    local bagFull_ = equipData_ and EquipmentSystem.isInventoryFull(equipData_) or false
    TownScene.setSmithRedDot(bagFull_)
    BlacksmithPage.setDecomposeRedDot(bagFull_)

    RewardPopup.update(dt)
    OfflineRewardPanel.update(dt)
    LevelUpPopup.update(dt)
    TavernPage.update(dt)
    MarketPage.update(dt)
    PlayerInfoPanel.update(dt)
end

function HandleMouseButtonDown(eventType, eventData)
    if not bootReady_ then return end
    return Horizon.mouseDown(eventType, eventData)
end

function HandleMouseMove(eventType, eventData)
    return Horizon.mouseMove(eventType, eventData)
end

function HandleMouseButtonUp(eventType, eventData)
    if not bootReady_ then return end
    return Horizon.mouseUp(eventType, eventData)
end

function HandleTouchBegin(eventType, eventData)
    return Horizon.touchBegin(eventType, eventData)
end

function HandleTouchMove(eventType, eventData)
    return Horizon.touchMove(eventType, eventData)
end

function HandleTouchEnd(eventType, eventData)
    return Horizon.touchEnd(eventType, eventData)
end

function HandleScreenMode(eventType, eventData)
    RecalcLayout()
    print("[Standalone] ScreenMode → " .. physW .. "x" .. physH .. " dpr=" .. dpr)
end

function HandleMouseWheel(eventType, eventData)
    return Horizon.mouseWheel(eventType, eventData)
end



return Standalone
