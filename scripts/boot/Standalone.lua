---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- Standalone - 单机模式入口
-- 职责: 创建场景/NanoVG/字体、设计分辨率缩放、事件订阅、渲染调度
-- ============================================================================

local GameConfig        = require("config.GameConfig")
local GameState         = require("core.GameState")
local ExpTable          = require("config.ExpTable")
local StageConfig       = require("config.StageConfig")
local DropSystem        = require("systems.DropSystem")
local EquipmentSystem   = require("systems.EquipmentSystem")
local LootBoxSystem     = require("systems.LootBoxSystem")
local ClientDispatcher  = require("runtime.ClientDispatcher")
local TopBar            = require("ui.hud.TopBar")
local BottomNav         = require("ui.hud.BottomNav")
local BattleScene       = require("ui.battle.scene.BattleScene")
local CharacterPanel    = require("ui.character.panel.CharacterPanel")
local DebugPanel        = require("ui.dev.DebugPanel")
local HeroRosterPanel   = require("ui.character.hero.HeroRosterPanel")
local RewardPopup       = require("ui.hud.popup.RewardPopup")
local TownScene         = require("ui.town.TownScene")
local BlacksmithPage    = require("ui.blacksmith.BlacksmithPage")
local ChurchPage        = require("ui.church.ChurchPage")
local TalentPage        = require("ui.church.talent.TalentPage")
local TavernPage        = require("ui.tavern.TavernPage")
local MarketPage        = require("ui.market.MarketPage")
local DungeonBattleScene = require("ui.dungeon.DungeonBattleScene")
local TowerBattleScene   = require("ui.tower.TowerBattleScene")
local TowerBuffPick      = require("ui.tower.TowerBuffPick")
local DungeonPage        = require("ui.dungeon.DungeonPage")
local BackpackPanel      = require("ui.backpack.BackpackPanel")
local LootBox           = require("ui.loot.LootBox")
local LootBoxPage       = require("ui.loot.LootBoxPage")
local LevelUpPopup      = require("ui.hud.popup.LevelUpPopup")
local UpdateNoticePopup = require("ui.hud.popup.UpdateNoticePopup")
local BattleCombat      = require("ui.battle.combat.BattleCombat")
local OfflineRewardPanel = require("ui.hud.popup.OfflineRewardPanel")
local PlayerInfoPanel   = require("ui.hud.popup.PlayerInfoPanel")
local RedeemCodePanel   = require("ui.hud.popup.RedeemCodePanel")
local StartScreen       = require("ui.story.gate.StartScreen")
local DarkTitleScreen   = require("ui.story.gate.DarkTitleScreenGate")  -- [DarkTitleScreen] 横屏暗黑标题
local BattleTriPage     = require("ui.battle.tri.BattleTriPage")    -- [三行并行] 三行战斗区
local SweepDialog       = require("ui.battle.stage.SweepDialog")          -- [三行并行] 全窗模态弹窗
local PlayerStore       = require("core.PlayerStore") -- [单机] 数据缓存（扫荡/选关弹窗读取 battle 模块）
local DamageStatsPanel  = require("ui.battle.popup.DamageStatsPanel")     -- [三行并行] 全窗模态弹窗
local StageSelectDialog = require("ui.battle.stage.StageSelectDialog")    -- [三行并行] 全窗模态弹窗
local BattleLayout      = require("core.BattleLayout")   -- [三行并行] 布阵模式切换
local ProjectileSystem  = require("ui.battle.combat.ProjectileSystem") -- [三行并行] 渲染缩放
local EventBus          = require("core.EventBus")
local GameEvents        = require("config.GameEvents")
local GameBGM           = require("systems.GameBGM")
local GameSFX           = require("systems.GameSFX")
local BattleEffects     = require("ui.battle.combat.BattleEffects")    -- [三行并行] 渲染缩放
local SpinePowerUpEffect = require("ui.fx.SpinePowerUpEffect")
local IntroCutscene      = require("ui.story.gate.IntroCutscene")
local LetterIntro        = require("ui.story.gate.LetterIntro")          -- [LetterIntro] 先祖来信（新档开场）
local CharacterDetail    = require("ui.character.detail.CharacterDetail")  -- [三队并行] 中缝返回键目标
local ScenarioDialogue   = require("ui.story.ScenarioDialogue")     -- [LetterIntro] 情景对话
local DrawUtil           = require("core.DrawUtil")
local DarkIcon           = require("core.DarkIcon")  -- 矢量图标库 + 画廊验收页
local StandaloneSave     = require("boot.StandaloneSave") -- [单机存档] 本地快照/恢复（无联网）
local ClientMsgHandler   = require("runtime.ClientMessageHandler")
local TutorialManager    = require("systems.TutorialManager")  -- 新手引导(去多人化重构时接线丢失,此处恢复)
local LocalActionBridge  = require("runtime.LocalActionBridge")
local StandaloneBoot     = require("boot.StandaloneBoot")
local StandaloneRT       = require("boot.StandaloneRT")
local StartupQueue       = require("boot.StartupQueue")
local SidePanelBattlePause = require("ui.battle.scene.SidePanelBattlePause")

local Standalone = {}

local localBridgeReady_ = false

local function localSendAction(action, params)
    return require("runtime.GameAction").sendAction(action, params)
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
---@type function?
local originalImageCreate_ = nil
---@type function?
local originalImageDelete_ = nil
---@type function?
local imageCreateWrapper_ = nil
---@type function?
local imageDeleteWrapper_ = nil
---@type function?
local invalidateImageCache_ = nil
local sceneRef_ = nil  -- 保存 scene 引用，供 requestResetToStartScreen 使用
local startScreenWasOpen_ = false
local postStartFlowDone_ = false  -- [LetterIntro] 开场/离线收益只触发一次（等标题关闭）
local storyBackfilled_ = false    -- 已首通关卡的未领情景只补排队一次
local startFlowBegun_ = false     -- 标题已关，BGM 已起；离线结算可能还在等角色刷新
local fontNormal = -1
---@type table|nil
local bootQueue_ = nil
local bootReady_ = false
---@type table|nil
local entryQueue_ = nil
local entryPrepared_ = false
---@type function|nil
local firstStageStep_ = nil

local function pumpBootQueue_()
    if not bootQueue_ then return end
    -- 整个init可在真实图片缓存未命中时让出；缓存命中不占解码额度。
    -- 每帧只恢复一次，不把多个轻步骤与下一个重步骤挤到同一帧。
    if bootQueue_:pump() then
        bootQueue_ = nil
        bootReady_ = true
        StandaloneRT.bootReady_ = true
        StandaloneRT.vg = vg
        DarkTitleScreen.setReady(true)
        print("[Standalone] boot queue complete, title unlocked")
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

-- 预载进度遮罩（全屏，W/H 为当前绘制空间尺寸；须在退出变换内调用）
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


-- Design resolution (Mode A — 1080x2400 竖屏)
local DESIGN_W = GameConfig.Design.WIDTH
local DESIGN_H = GameConfig.Design.HEIGHT

-- 全窗口底色。UI_WORLD_BG / UI_CZ_BJ 已被三行石框、关卡图和各页底板盖住，不再加载。

-- [Standalone] battle 状态本地同步：无 Server 推送时，把 BattleScene 本地进度
-- （maxStageId_/clearedStages）每秒比对一次，变化才发布实时镜像，
-- 供 TutorialManager / BottomNav / DungeonBattleScene 的建筑与页签解锁判定使用
---@type table
local battleSync = { lastMax = -1, lastCleared = {}, lastStages = {}, acc = 0 }
local BattleProgressSchema = require("shared.battle.BattleSchema")
local function progressRank(id)
    local previous = StageConfig.getTerminalPrevStageId(id)
    return previous and previous + 0.5 or id
end

-- 只承认严格 true 的正整数事实；数字/字符串键归一，不排序、不拼接全账本。
local function clearedSnapshot(entries)
    local normalized, count = {}, 0
    if type(entries) == "table" then
        for key, value in pairs(entries) do
            local id = (type(key) == "number" or type(key) == "string")
                and math.tointeger(tonumber(key) or 0)
            if value == true and id and id > 0 then
                local savedKey = tostring(id)
                if not normalized[savedKey] then
                    normalized[savedKey] = true
                    count = count + 1
                end
            end
        end
    end
    return normalized, count
end

local function sameProgressMap(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key, value in pairs(b) do if a[key] ~= value then return false end end
    return true
end

local function SyncBattleState(dt)
    if not bootReady_ or StandaloneRT.entryPreparing then return end
    battleSync.acc = battleSync.acc + (dt or 0)
    if battleSync.acc < 1.0 then return end
    battleSync.acc = 0
    local maxId = tonumber(BattleScene.getMaxStageId()) or 0
    local liveLedger = BattleScene.getClearedStages()
    local mergedCleared, clearedN = clearedSnapshot(liveLedger)
    local battle = ClientDispatcher.get("battle")
    if type(battle) ~= "table" then battle = {} end
    local savedCleared = clearedSnapshot(battle.clearedStages)
    local ledgersDiffer = not sameProgressMap(mergedCleared, savedCleared)
    for key in pairs(savedCleared) do
        if not mergedCleared[key] then
            mergedCleared[key] = true
            clearedN = clearedN + 1
        end
    end
    -- 只从本轮两源取并集，不以旧缓存补事实；两源明确清空时允许合法清档。
    -- 补原场景账本但不回灌场景/驱动，不重开当前波或改变 pending 属性。
    if type(liveLedger) == "table" then
        for key in pairs(mergedCleared) do
            local id = tonumber(key)
            if liveLedger[id] ~= true then liveLedger[id] = true end
        end
    end
    local savedMax = tonumber(battle.maxStageId) or 0
    local mergedMax = progressRank(maxId) >= progressRank(savedMax) and maxId or savedMax
    local savedMaxChanged = battle.maxStageId ~= mergedMax
    battle.maxStageId = mergedMax
    if not sameProgressMap(battle.clearedStages, mergedCleared) then
        battle.clearedStages = mergedCleared
    end

    -- 仅三队小表规范化以判断进度；不在稳态调用完整 Capture 再扫描两份账本。
    -- 浅拷贝来自当前模块，非进度字段（效率/挂机/扩展数据）保持当前引用和值。
    local candidate = {}
    for key, value in pairs(battle) do candidate[key] = value end
    candidate.clearedStages = mergedCleared
    local liveTeams = BattleTriPage.getTeamStageIds()
    if type(liveTeams) == "table" then
        local savedTeams = type(battle.teamStageIds) == "table" and battle.teamStageIds or {}
        local ids = {}
        for team = 1, 3 do
            ids[tostring(team)] = liveTeams[team] or liveTeams[tostring(team)]
                or savedTeams[tostring(team)] or savedTeams[team]
        end
        candidate.teamStageIds = ids
        candidate.currentStageId = ids["1"] or battle.currentStageId
    end
    BattleProgressSchema.normalizeTeamStageIds(candidate, false)
    local teams = candidate.teamStageIds
    if candidate.maxStageId == battleSync.lastMax
        and battle.maxStageId == candidate.maxStageId
        and sameProgressMap(mergedCleared, battleSync.lastCleared)
        and sameProgressMap(teams, battleSync.lastStages)
        and battle.currentStageId == candidate.currentStageId
        and sameProgressMap(battle.teamStageIds, teams)
        and battle.teamCurrentStageIds == nil and not ledgersDiffer and not savedMaxChanged then return end

    local captured = StandaloneSave.CaptureBattleProgress(candidate)
    if battleSync.lastMax == -1 then
        print("[Standalone] battle 状态首次同步: maxStageId=" .. tostring(captured.maxStageId) .. ", cleared=" .. clearedN)
    elseif ledgersDiffer then
        print("[Standalone] battle 通关账本合并: cleared=" .. clearedN)
    end
    battleSync.lastMax = captured.maxStageId
    -- 冻结比较值，不能与可原地修改的已发布模块共用账本/队伍表。
    battleSync.lastCleared = clearedSnapshot(captured.clearedStages)
    battleSync.lastStages = { ["1"] = captured.teamStageIds["1"],
        ["2"] = captured.teamStageIds["2"], ["3"] = captured.teamStageIds["3"] }
    ClientDispatcher.publishLive("battle", captured)
end

-- 仅缓存红点显示。真实装备投递仍直接调用 EquipmentSystem.isInventoryFull。
---@type table
local inventoryBadge = { ready = false, full = false, acc = 0 }
local function updateInventoryBadges(dt)
    local equipment = ClientDispatcher.get("equipment")
    local inventory = type(equipment) == "table" and equipment.inventory or nil
    local revision = PlayerStore.GetRevision and PlayerStore.GetRevision("equipment") or 0
    inventoryBadge.acc = inventoryBadge.acc + math.max(0, dt or 0)
    if not inventoryBadge.ready or inventoryBadge.equipment ~= equipment
        or inventoryBadge.inventory ~= inventory or inventoryBadge.revision ~= revision
        or inventoryBadge.acc >= 0.5 then
        inventoryBadge.full = type(inventory) == "table"
            and EquipmentSystem.isInventoryFull(equipment) or false
        inventoryBadge.equipment, inventoryBadge.inventory = equipment, inventory
        inventoryBadge.revision, inventoryBadge.acc, inventoryBadge.ready = revision, 0, true
    end
    -- 仍每帧设置两个显示标志，页面重开/显示重置不借旧控件状态。
    TownScene.setSmithRedDot(inventoryBadge.full)
    BlacksmithPage.setDecomposeRedDot(inventoryBadge.full)
end

local physW, physH, dpr, logicalW, logicalH

local function RecalcLayout()
    physW  = graphics:GetWidth()
    physH  = graphics:GetHeight()
    dpr    = graphics:GetDPR()
    if not dpr or dpr <= 0 then dpr = 1 end
    local windowW = physW / dpr
    local windowH = physH / dpr
    -- Landscape canvas stays 1920x1080. Half-screen and full-screen only scale.
    local frameW, frameH = 1920, 1080
    local frameScale = 1
    if windowW > 0 and windowH > 0 then
        frameScale = math.min(windowW / frameW, windowH / frameH)
    end
    if frameScale <= 0 then frameScale = 1 end
    local frameOx = (windowW - frameW * frameScale) * 0.5
    local frameOy = (windowH - frameH * frameScale) * 0.5
    logicalW = frameW
    logicalH = frameH
    StandaloneRT.vg = vg
    StandaloneRT.bootReady_ = bootReady_
    StandaloneRT.windowW = windowW
    StandaloneRT.windowH = windowH
    StandaloneRT.frameScale = frameScale
    StandaloneRT.frameOx = frameOx
    StandaloneRT.frameOy = frameOy
    StandaloneRT.logicalW = logicalW
    StandaloneRT.logicalH = logicalH
    StandaloneRT.dpr = dpr
    StandaloneRT.DESIGN_W = DESIGN_W
    StandaloneRT.DESIGN_H = DESIGN_H
    StandaloneRT.DrawPreloadOverlay = DrawPreloadOverlay
    StandaloneRT.preload_ = preload_
end

-- ============================================================================
-- Module API
-- ============================================================================

--- 分帧启动完成后的接线（必须在 CharacterPanel/BattleScene/TownScene init 之后）
function Standalone._bootWiring()
    StandaloneBoot.run({
        vg = vg,
        localSendAction = localSendAction,
        setLocalBridgeReady = function()
            localBridgeReady_ = true
        end,
    })
end

function Standalone.Start()
    battleSync = { lastMax = -1, lastCleared = {}, lastStages = {}, acc = 0 }
    inventoryBadge = { ready = false, full = false, acc = 0 }
    entryQueue_, entryPrepared_ = nil, false
    StandaloneRT.entryPrepared, StandaloneRT.entryPreparing, StandaloneRT.entryRendered = false, false, false
    BattleTriPage.setBattleReady(false)
    StandaloneSave.SetBattlePage(BattleTriPage)
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
    if not vg then
        print("[Standalone] ERROR: nvgCreate failed")
        return
    end
    require("core.I18n").installDrawHook()

    -- 2.5 图片去重按context+flags+path隔离；删除句柄时同步失效缓存。
    -- 否则新特效释放图片后会重新取得死句柄，重启/多context也会借到错误纹理。
    local handleCache = {}
    local cacheActive = true
    invalidateImageCache_ = function() cacheActive = false; handleCache = {} end
    local createImage, deleteImage = nvgCreateImage, nvgDeleteImage
    originalImageCreate_, originalImageDelete_ = createImage, deleteImage
    imageCreateWrapper_ = function(ctx, path, flags)
        -- Stop后外部hook可能仍闭包引用本wrapper；此时直通而非复用旧context句柄。
        if not cacheActive then return createImage(ctx, path, flags) end
        local byContext = handleCache[ctx]
        if not byContext then byContext = {}; handleCache[ctx] = byContext end
        local key = tostring(flags or 0) .. ":" .. path
        local cached = byContext[key]
        if cached then return cached end
        StartupQueue.checkpoint()
        local handle = createImage(ctx, path, flags)
        if handle and handle > 0 then byContext[key] = handle end
        return handle
    end
    imageDeleteWrapper_ = function(ctx, handle)
        local byContext = handleCache[ctx]
        if byContext then
            for key, cached in pairs(byContext) do
                if cached == handle then byContext[key] = nil end
            end
        end
        return deleteImage(ctx, handle)
    end
    nvgCreateImage, nvgDeleteImage = imageCreateWrapper_, imageDeleteWrapper_

    -- 3. Font：Noto Sans CJK KR Bold（OFL，覆盖中日韩英；旧圆体 CN 无韩文）
    fontNormal = nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf")
    if fontNormal < 0 then
        print("[Standalone] WARN: NotoSansCJKkr-Bold.otf load failed, fallback rounded CN")
        fontNormal = nvgCreateFont(vg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
    end
    if fontNormal < 0 then
        print("[Standalone] ERROR: font load failed")
    else
        print("[Standalone] font OK id=" .. tostring(fontNormal))
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
    DarkTitleScreen.open()
    local bootSteps = {
        { "LetterIntro", function() LetterIntro.init(vg) end },
        { "TopBar", function() TopBar.init(vg) end },
        { "BottomNav", function() BottomNav.init(vg) end },
        { "BattleScene", function() BattleScene.init(vg) end },
        { "IntroCutscene", function() IntroCutscene.init(vg, scene) end },
        { "ScenarioDialogue", function() ScenarioDialogue.init(vg, scene) end },
        { "CharacterPanel", function() CharacterPanel.init(vg) end },
        { "BackpackPanel", function() BackpackPanel.init(vg) end },
        { "TownScene", function() TownScene.init(vg); TownScene.preload(vg) end },
        { "RewardPopup", function() RewardPopup.init(vg) end },
        { "OfflineRewardPanel", function() OfflineRewardPanel.init(vg) end },
        { "LevelUpPopup", function() LevelUpPopup.init(vg) end },
        { "UpdateNoticePopup", function() UpdateNoticePopup.init(vg) end },
        { "PlayerInfoPanel", function() PlayerInfoPanel.init(vg) end },
        { "SpinePowerUp", function()
            SpinePowerUpEffect.init()
            SpinePowerUpEffect.preload(vg)
        end },
        { "TutorialManager", function()
            TutorialManager.init(vg, PlayerStore, function(progress)
                local session = ClientDispatcher.get("session")
                if session then session.tutorialProgress = progress end
            end)
        end },
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
        { "BattleAssets", function()
            BattleTriPage.preload(vg)
            local BattleDraw = require("ui.battle.scene.BattleDraw")
            BattleDraw.preloadCards(vg, BattleScene.getAllies())
            BattleDraw.preloadCards(vg, BattleScene.getEnemies())
            ProjectileSystem.preloadBattleEffects()
            GameSFX.preload("hit")
        end },
        { "BattleEntry", function()
            entryPrepared_ = BattleTriPage.prepareEntry(vg)
            StandaloneRT.entryPrepared = entryPrepared_
        end },
    }
    for _, step in ipairs(bootSteps) do
        if step[1] == "firstStage" then firstStageStep_ = step[2] break end
    end
    bootQueue_ = StartupQueue.new(bootSteps, {
        onComplete = function(index, name, elapsed, ok, err)
            -- 只有首场准备步骤完整成功后才解除战斗门禁；后续素材预热失败仍可沿用旧容错。
            if name == "firstStage" and ok then BattleTriPage.setBattleReady(true) end
            if not ok then
                print("[Standalone] boot step FAIL " .. name .. ": " .. tostring(err))
            else
                print(string.format("[Standalone] boot step %d/%d %s (%.0fms span)",
                    index, #bootSteps, name, elapsed * 1000))
            end
            DarkTitleScreen.loadDone = index
            DarkTitleScreen.loadTotal = #bootSteps
            DarkTitleScreen.loadPercent = math.floor(index * 100 / #bootSteps)
            DarkTitleScreen.loadStep = name
            DarkTitleScreen.loadStepMs = math.floor(elapsed * 1000)
        end,
    })
    -- 就绪后才放行输入/游戏：防止部分初始化让出期间触发开场与回执。
    bootReady_ = false
    StandaloneRT.bootReady_ = false
    print("[Standalone] boot queue " .. #bootSteps .. " steps (title first, cooperative images)")

    -- 轻量接线（不解码贴图，可在首帧完成）
    ClientMsgHandler.setup({ sendAction = localSendAction })
    ClientMsgHandler.setupDataSubscriptions()

    RedeemCodePanel.setSendAction(function(action, params)
        local sent = localSendAction(action, params)
        if not sent then
            RedeemCodePanel.onActionResult({ success = false, reason = "本地处理失败", redeemAction = true })
        end
    end)
    TavernPage.setSendAction(localSendAction)
    MarketPage.setSendAction(localSendAction)

    -- 5.05 远征等级提升弹窗：监听 PLAYER_LEVEL_UP 事件，并刷新解锁状态
    EventBus.on(GameEvents.PLAYER_LEVEL_UP, function(data)
        local newLevel = data.toLevel or data.level
        local fromLevel = data.fromLevel or math.max(1, newLevel - 1)
        local unlocks = require("config.ExpeditionProgress").getRangeUnlocks(fromLevel, newLevel)
        LevelUpPopup.show(newLevel, unlocks, fromLevel)
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
    if Standalone.cancelOpening then Standalone.cancelOpening() end
    LetterIntro.reset()
    ScenarioDialogue.reset()
    require("systems.StoryPlayer").resetAll()
    -- 启动尚未完成时丢弃挂起任务，不能在已释放的VG上下文继续恢复。
    bootQueue_ = nil
    entryQueue_, entryPrepared_ = nil, false
    StandaloneRT.entryPrepared, StandaloneRT.entryPreparing, StandaloneRT.entryRendered = false, false, false
    bootReady_ = false
    StandaloneRT.bootReady_ = false
    inventoryBadge = { ready = false, full = false, acc = 0 }
    RewardPopup.clearBattleRewards()
    require("ui.battle.stage.StageSelectDialog").close()
    -- 逐域消费后再保存；不能只flush最后draw/update挂载的那一条战线。
    local ETS = require("systems.ExtraTalentSystem")
    ETS.flush() -- 兼容内置默认/非场景调用留下的当前域；后续仍逐独立域消费。
    BattleTriPage.flushPendingGrowth()
    require("ui.battle.scene.BattleMountScope").runDefault(function()
        ETS.flush()
        require("ui.battle.combat.BattleCasualty").flushRewards()
    end)
    require("ui.dungeon.DungeonBattleScope").run(1, ETS.flush)
    require("ui.tower.TowerTriBattle").flushPendingGrowth()
    StandaloneSave.Flush()  -- [单机存档] 退出前立即落盘
    SpinePowerUpEffect.destroy()
    require("ui.fx.SpineCardEffect").destroy()
    require("ui.fx.SpineResultEffect").destroy()
    require("ui.fx.DarkEffectSprites").destroy()
    require("ui.tavern.RecruitAnim").destroy()
    LevelUpPopup.destroy()
    CharacterPanel.destroyPresentation()
    require("ui.character.hero.AwakeningArtwork").destroy()
    TowerBattleScene.resetToDefault()
    require("rules.tower.TowerService").ResetToDefault(1)
    TowerBuffPick.destroy()
    require("ui.tower.TowerBuffSidebar").destroy()
    require("ui.widget.DesignWidgetSurface").shutdown()
    -- 不覆盖其他所有者后装的hook；让仍被引用的旧wrapper直通，再只撤下本会话包装。
    if invalidateImageCache_ then invalidateImageCache_() end
    invalidateImageCache_ = nil
    if nvgCreateImage == imageCreateWrapper_ and originalImageCreate_ then
        nvgCreateImage = originalImageCreate_
    end
    if nvgDeleteImage == imageDeleteWrapper_ and originalImageDelete_ then
        nvgDeleteImage = originalImageDelete_
    end
    originalImageCreate_, originalImageDelete_, imageCreateWrapper_, imageDeleteWrapper_ = nil, nil, nil, nil
    if vg then
        nvgDelete(vg)
        vg = nil
    end
end

--- 入场重建只发生在开局/清档，不在攻击期同步加载，也不推进离线待领期间的战斗。
local function prepareEntry_()
    if entryPrepared_ and not BattleTriPage.isEntryPrepared() then
        entryPrepared_ = false
        StandaloneRT.entryPrepared, StandaloneRT.entryRendered = false, false
    end
    if entryPrepared_ then return true end
    if not entryQueue_ then
        StandaloneRT.entryPreparing = true
        StandaloneRT.entryRendered = false
        entryQueue_ = StartupQueue.new({
            { "firstStageRetry", function()
                if not BattleTriPage.isBattleReady() then
                    assert(firstStageStep_, "首场准备未初始化")()
                    BattleTriPage.setBattleReady(true)
                end
            end },
            { "BattleEntry", function()
                entryPrepared_ = BattleTriPage.prepareEntry(vg)
            end },
        }, { onComplete = function(_, _, _, ok, err)
            if not ok then print("[Standalone] 入场战斗准备失败: " .. tostring(err)) end
        end })
    end
    return false
end

--- 标题关闭后按真实离线时长结算并弹窗。不足 1 分钟不弹。
--- 必须先完成真实战斗准备及一帧绘制，角色数据齐备后才计算离线收益。
local function showOfflineRewardPanel_()
    local CharacterPanel = require("ui.character.panel.CharacterPanel")
    if not CharacterPanel.isHeroesDataApplied() then
        local heroesData = ClientDispatcher.get("heroes")
        if heroesData then
            CharacterPanel.setHeroesData(heroesData)
            entryPrepared_ = false
            StandaloneRT.entryPrepared, StandaloneRT.entryRendered = false, false
        end
    end
    if not CharacterPanel.isHeroesDataApplied() then
        print("[Standalone] 角色数据未刷新，推迟离线结算")
        return false
    end
    if not prepareEntry_() or not StandaloneRT.entryRendered then return false end
    local LocalActionBridge = require("runtime.LocalActionBridge")
    LocalActionBridge.init()
    StandaloneSave.ReconcileOfflineBoundary()
    local OfflineService = require("rules.offline.OfflineService")
    local panelData = OfflineService.CalcOnEnter(1)
    StandaloneSave.OfflineChecked()
    if not panelData then
        StandaloneSave.Flush()
        print("[Standalone] no offline reward to show")
        return true
    end
    OfflineRewardPanel.show({
        offlineSeconds = panelData.offlineSeconds,
        maxSeconds     = panelData.maxSeconds,
        multiplier     = panelData.multiplier or 1.0,
        adventureExp   = panelData.adventureExp,
        adventurerExp  = panelData.adventurerExp,
        heroExpPreview = panelData.heroExpPreview,
        teamSources    = panelData.teamSources,
        rewards        = panelData.rewards,
        -- [7日硬顶] 封顶提示
        hardCapSeconds  = panelData.hardCapSeconds,
        cappedByHardCap = panelData.cappedByHardCap,
        tailRatio       = panelData.tailRatio,
        onClaim = function()
            local handled = localSendAction("claim_offline_rewards", {})
            if handled and not OfflineService.HasPendingRewards(1) then
                StandaloneSave.Flush()
            end
            print("[OfflineRewardPanel] claim sent handled=" .. tostring(handled))
            return handled and not OfflineService.HasPendingRewards(1)
        end,
    })
    print("[Standalone] showed real OfflineRewardPanel seconds="
        .. tostring(panelData.offlineSeconds)
        .. " rewards=" .. tostring(panelData.rewards and #panelData.rewards or 0))
    return true
end

--- [LetterIntro] 新档标记开场剧情完成（session 整表替换，必须带全字段）
local function markIntroCompleted_(deferOpening)
    local sessionData = ClientDispatcher.get("session") or {}
    local claimed = sessionData.claimedScenarios or {}
    claimed["1"] = true  -- 旧点将情景不再播放
    claimed["2"] = true
    claimed["3"] = true
    claimed["4"] = true
    claimed["11"] = true  -- 三人已在开场入队，不再用 1-3 补人
    claimed["12"] = true
    claimed["13"] = true
    local updated = {}
    for k, v in pairs(sessionData) do
        updated[k] = v
    end
    updated.lastOnlineTime = sessionData.lastOnlineTime or 0
    updated.firstLoginTime = sessionData.firstLoginTime or 0
    updated.introCompleted = true
    if deferOpening and sessionData.introCompleted ~= true then
        -- 仅真正新档预留前置四段介绍；沿用旧字段以兼容未播完的存档。
        updated.deferredOpening = true
        updated.deferredOpeningIndex = 1
    end
    updated.claimedScenarios = claimed
    if not updated.initialHeroId then
        updated.initialHeroId = 1
    end
    ClientDispatcher.handleStateUpdate(cjson.encode({ modules = { session = updated } }))
    require("boot.StandaloneSave").Flush()
    print("[Standalone] intro completed flag saved (scenario 1 claimed, initialHeroId="
        .. tostring(updated.initialHeroId) .. ")")
end

--- 开场链独占到最后一段，清档/退出使旧信件与对白回调失效。
local openingFlowToken_ = 0
local openingFlowActive_ = false
local function cancelOpening_()
    openingFlowToken_ = openingFlowToken_ + 1
    openingFlowActive_ = false
end

local function finishIntro_()
    openingFlowActive_ = false
    print("[Standalone] intro chain finished, unlock game")
    GameBGM.setScene("battle", { fromStart = true })
    markIntroCompleted_()
    postStartFlowDone_ = showOfflineRewardPanel_()
end

--- 旧延播档从未完成的段落接续，新档信件结束后顺序播放门厅与三人入队。
local function playOpening_(token)
    if token ~= openingFlowToken_ then return end
    local story = require("systems.StoryPlayer")
    local pending = story.takeDeferredOpening()
    if not pending then finishIntro_(); return end
    local cfg = pending.config
    GameBGM.setScene("letter", { fromStart = true })
    ScenarioDialogue.show({
        mode = cfg.mode or "large", background = cfg.background,
        backgroundIsCg = cfg.backgroundIsCg, title = cfg.title, steps = cfg.steps,
        onFinish = function()
            if token ~= openingFlowToken_ then return end
            if story.finishDeferredOpening(pending.deferredToken) then playOpening_(token) end
        end,
    })
end

local function resumeOpening_()
    openingFlowToken_ = openingFlowToken_ + 1
    openingFlowActive_ = true
    postStartFlowDone_ = false
    playOpening_(openingFlowToken_)
end

--- 首通/入场排队的情景，等奖励弹窗关掉后再用横屏对话条播放
local function tryPlayPendingStory_()
    if not TutorialManager.canPlayPendingStory() then return end
    if ScenarioDialogue.isActive() or LetterIntro.isOpen() or IntroCutscene.isActive() then
        return
    end
    local recovery = require("ui.tutorial.TutorialPageRecovery")
    local place = recovery.getStoryPlace()
    if RewardPopup.isOpen() or OfflineRewardPanel.isOpen()
        or recovery.isPendingStoryBlocked(place) then return end
    local rewardBlocked = require("boot.BattleRewardOverlay").isBlocked()
    if RewardPopup.hasPendingBattleRewards() and not rewardBlocked then return end
    local pending
    -- 旧回执和关卡队列只归主线，不能抢菜单自己的首次介绍。
    if place == "battle" or place == "battle_town" then
        pending = ClientMsgHandler.consumePendingScenarioDialogue()
        if not pending then pending = ClientMsgHandler.consumePendingFollowUpDialogue() end
    end
    if not pending or not pending.config or not pending.config.steps or #pending.config.steps == 0 then
        pending = require("systems.StoryPlayer").take(place)
    end
    if not pending or not pending.config or not pending.config.steps or #pending.config.steps == 0 then
        return
    end
    local cfg = pending.config
    local scenarioId = pending.scenarioId
    if scenarioId then
        local sessionData = ClientDispatcher.get("session") or {}
        local updated = {}
        for k, v in pairs(sessionData) do updated[k] = v end
        if scenarioId == 82 then
            -- 奖励剧情未播完退出应可重播；只有真实领奖成功才写claimed。
            -- 先建立台账，兼容首次播放时尚未有任何领奖记录的新档。
            updated.scenarioRewardsGranted = sessionData.scenarioRewardsGranted or {}
        else
            local claimed = sessionData.claimedScenarios or {}
            claimed[tostring(scenarioId)] = true
            updated.claimedScenarios = claimed
        end
        ClientDispatcher.handleStateUpdate(cjson.encode({ modules = { session = updated } }))
    end
    print("[Standalone] play pending story id=" .. tostring(scenarioId)
        .. " steps=" .. #cfg.steps .. " mode=" .. tostring(cfg.mode))
    ScenarioDialogue.show({
        mode = cfg.mode or "small",
        background = cfg.background,
        backgroundIsCg = cfg.backgroundIsCg,
        title = cfg.title,
        eyeOpen = cfg.eyeOpen,
        steps = cfg.steps,
        onFinish = function()
            if scenarioId then
                print("[Standalone] claim scenario reward id=" .. tostring(scenarioId))
                -- 恢复引导触发链: claim 结果处理时 fireTutorial → onScenarioClaimed
                ClientMsgHandler.setPendingTutorialNotify(scenarioId)
                -- 其他情景仍沿用起播预标记；82也兼容旧中断档的预标记。
                -- 真正发奖仍由scenarioRewardsGranted台账防重，不以起播标记代替领取。
                localSendAction("claim_scenario_reward", { scenarioId = scenarioId, preClaimed = true })
                local followId = require("systems.StoryPlayer").followOf(scenarioId)
                if followId then
                    print("[Standalone] enqueue follow scenario " .. tostring(followId))
                    require("systems.StoryPlayer").enqueue(followId)
                end
            end
        end,
    })
end

--- [LetterIntro] 新档开场链：完整先祖来信 → 门厅 → 三人入队 → 进游戏
local function startIntroChain_()
    entryPrepared_ = false
    StandaloneRT.entryPrepared, StandaloneRT.entryRendered = false, false
    markIntroCompleted_(true)
    local handled = localSendAction("grant_starter_trio", {})
    print("[Standalone] grant starter trio at intro start handled=" .. tostring(handled))
    openingFlowToken_ = openingFlowToken_ + 1
    openingFlowActive_ = true
    postStartFlowDone_ = false
    local token = openingFlowToken_
    GameBGM.setScene("letter", { fromStart = true })
    LetterIntro.start(function() playOpening_(token) end)
end
Standalone.cancelOpening = cancelOpening_

--- 清除存档后重置客户端状态并回到开始界面
--- 由 DebugPanel 的 reset_save 处理器调用
function Standalone.requestResetToStartScreen()
    local TAG = "[Standalone][DIAG-RESET]"
    local t0 = os.clock()
    cancelOpening_()
    print(string.format("%s requestResetToStartScreen START clock=%.4f", TAG, t0))

    -- 1. 停止 BGM & SFX
    GameBGM.stop()
    GameSFX.stop()
    print(string.format("%s step1: BGM/SFX stopped clock=%.4f", TAG, os.clock()))

    -- 2. 关闭所有打开的面板/弹窗
    RewardPopup.clearBattleRewards()
    require("ui.battle.stage.StageSelectDialog").close()
    if MarketPage.isOpen()          then MarketPage.close()          end
    if TavernPage.isOpen()          then TavernPage.close()          end
    -- 锻炉强制关闭（联动仓库由其 closeAutoWarehouse 处理，这里再兜底关仓库）
    if BlacksmithPage.isOpen()      then BlacksmithPage.forceClose() end
    if BackpackPanel.isOpen()       then BackpackPanel.close()       end
    if ChurchPage.isOpen()          then ChurchPage.close()          end
    if TalentPage.isOpen()          then TalentPage.close()          end
    if HeroRosterPanel.isVisible()  then HeroRosterPanel.hide()      end
    if RewardPopup.isOpen()         then RewardPopup.close()         end
    if OfflineRewardPanel.isOpen()  then OfflineRewardPanel.close()  end
    if LevelUpPopup.isOpen()        then LevelUpPopup.destroy()      end
    if PlayerInfoPanel.isOpen()     then PlayerInfoPanel.close()      end
    -- LootBoxPage 直接使用顶部引用
    if LootBoxPage.isVisible()      then LootBoxPage.hide()          end
    print(string.format("%s step2: panels closed clock=%.4f", TAG, os.clock()))

    -- 清档先硬关闭资源战斗，不触发旧结算/onClose；详情和规则pending也归旧会话。
    TowerBattleScene.resetToDefault()
    DungeonBattleScene.forceClose(true) -- 清档直接丢弃副本pending/dirty，不提交旧战斗成长。
    require("rules.tower.TowerService").ResetToDefault(1)
    DungeonBattleScene.forceClose()
    DungeonPage.close()
    require("rules.dungeon.DungeonService").Cleanup(1)
    require("rules.dungeon.DungeonIdleService").Cleanup(1)

    -- 清档先丢弃旧驱动、终焉及待发奖励；不能把旧队预约关写回新档。
    BattleTriPage.resetToDefault()
    StandaloneBoot.resetPendingBattleRewards()
    -- 离线待领包属于旧会话；新档不能重发或领取旧账户收益。
    require("rules.offline.OfflineService").Cleanup(1)
    require("systems.StoryPlayer").resetAll()
    require("ui.character.hero.HeroScenario").resetAll()
    ClientMsgHandler.resetSessionBridgeState()
    ScenarioDialogue.reset()
    battleSync = { lastMax = -1, lastCleared = {}, lastStages = {}, acc = 0 }
    inventoryBadge = { ready = false, full = false, acc = 0 }

    -- 清档先取消旧会话特效，不在新英雄／战力同步期间补播旧动画。
    SpinePowerUpEffect.resetSession()
    require("ui.fx.SpineCardEffect").stopAll()
    require("ui.fx.SpineResultEffect").stop()
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
            heroes    = { roster = { ["1"] = { level = 1, exp = 0, shards = 0 } }, deployed = { 1 } },
            battle    = { currentStageId = 101, maxStageId = 101, clearedStages = {}, battleMode = "idle" },
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
    storyBackfilled_ = false
    startFlowBegun_ = false
    entryQueue_, entryPrepared_ = nil, false
    StandaloneRT.entryPrepared, StandaloneRT.entryPreparing, StandaloneRT.entryRendered = false, false, false
    print(string.format("%s step11: startScreenWasOpen_=true clock=%.4f", TAG, os.clock()))

    -- 12. 回到标题。不能重跑 Start，否则事件重复注册并把页面叠坏。
    local BattleTriPage = require("ui.battle.tri.BattleTriPage")
    BattleTriPage.setBattleReady(true)
    if not BattleTriPage.isOpen() then
        BattleTriPage.open()
    end
    DarkTitleScreen.reopen()

    print(string.format("%s requestResetToStartScreen DONE elapsed=%.4fs clock=%.4f", TAG, os.clock() - t0, os.clock()))
end

-- ============================================================================
-- Global event handlers (SubscribeToEvent requires global function names)
-- ============================================================================

function HandleNanoVGRender(eventType, eventData)
    ---@diagnostic disable-next-line: undefined-global
    return HandleNanoVGRenderHorizon(eventType, eventData)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    -- UI/回执仍用真实时间；先冻结战斗绝对时钟，标题/开场提前返回也不补暂停时长。
    SidePanelBattlePause.refresh()
    -- 等待回执使用真实帧时间；标题/暂停不阻断超时，也不另订阅 Update 覆盖主循环。
    PlayerStore.Update(dt)
    -- 特效用真实时钟收尾，不随战斗倍速，不被标题／剧情提前返回冻结。
    SpinePowerUpEffect.update(dt)
    require("ui.fx.SpineCardEffect").update(dt)
    require("ui.fx.SpineResultEffect").update(dt)
    require("ui.dev.CEPanel").pollHotkey()
    -- 分帧启动：每帧 1 个模块 init，标题可先画出来
    pumpBootQueue_()
    if not bootReady_ then
        if StartScreen.isOpen() then StartScreen.update(dt) end
        if DarkTitleScreen.isOpen() then DarkTitleScreen.update(dt) end
        return
    end
    if entryQueue_ then
        if entryQueue_:pump() then
            entryQueue_ = nil
            StandaloneRT.entryPrepared = entryPrepared_
            StandaloneRT.entryPreparing = false
        end
        -- 完成当帧也先交给渲染；下一帧才允许离线计算与领取窗出现。
        return
    end

    -- [DWP 异步预下载] 等待期：
    --   1) 标题画面可显示，但资源未完成前不允许进入（避免无背景界面）
    --   2) 下载完成后解锁标题点击；超时后仍解锁，避免永久卡死
    --   3) 主线程全程不做任何同步加载
    if preload_.active then
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

    -- 鼠标静止时也检查装备悬停计时，移到其他格子则由命中检测立即收起旧说明。
    HandleEquipmentHoverTickHorizon()

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

    -- [DarkTitleScreen] 横屏标题动画。未淡出时不跑游戏逻辑；淡出期间放行，
    -- 让三行战斗先 open，避免标题揭开时底下还是竖屏 BattleScene。
    if DarkTitleScreen.isOpen() then
        DarkTitleScreen.update(dt)
        startScreenWasOpen_ = true
        if not DarkTitleScreen.isFading() then
            return
        end
        local sessionData = ClientDispatcher.get("session") or {}
        local heroesData = ClientDispatcher.get("heroes") or {}
        local ownedCount = 0
        if type(heroesData.roster) == "table" then
            for _, hero in pairs(heroesData.roster) do
                if type(hero) == "table" and hero.level then
                    ownedCount = ownedCount + 1
                end
            end
        end
        local introDone = sessionData.introCompleted == true or ownedCount > 1
        if not introDone and not LetterIntro.isOpen() then
            print("[Standalone] cover game before intro")
            startIntroChain_()
        end
        if introDone and BottomNav.getSelectedIndex() == 3
            and not BattleTriPage.isOpen()
            and not DungeonBattleScene.isOpen()
            and not TowerBattleScene.isActive() then
            BattleTriPage.open()
        end
    end

    -- 开始页/标题刚关闭 → 完整开场或旧未完成段接续，结束后才弹离线收益。
    -- 必须等 DarkTitleScreen 关闭后再播，否则信件会被标题盖住且点击被吞
    if not postStartFlowDone_ and not DarkTitleScreen.isOpen() then
        if not startFlowBegun_ then
            startFlowBegun_ = true
            startScreenWasOpen_ = false
            GameBGM.start()
            GameSFX.start()
        end
        local sessionData = ClientDispatcher.get("session") or {}
        local battleData = ClientDispatcher.get("battle") or {}
        local heroesData = ClientDispatcher.get("heroes") or {}
        local ownedCount = 0
        if type(heroesData.roster) == "table" then
            for _, hero in pairs(heroesData.roster) do
                if type(hero) == "table" and hero.level then
                    ownedCount = ownedCount + 1
                end
            end
        end
        -- 已有多名角色的旧档不再重走开场，避免重启后又补初始角色。
        local introDone = sessionData.introCompleted == true or ownedCount > 1
        if introDone and sessionData.introCompleted ~= true then
            print("[Standalone] legacy save detected, mark intro completed")
            markIntroCompleted_()
        end
        if not openingFlowActive_ and introDone and sessionData.deferredOpening == true then
            resumeOpening_()
        elseif not openingFlowActive_ and introDone and not LetterIntro.isOpen() then
            -- 角色还没刷新时保持未完成，下一帧再结算。
            if showOfflineRewardPanel_() then postStartFlowDone_ = true end
        elseif not openingFlowActive_ and not introDone then
            print("[Standalone] new save detected, starting complete intro chain")
            startIntroChain_()
        end
    end

    -- 开场介绍不让教程、后台战斗或旧剧情插入；最后一段结束后再结算离线收益。
    if openingFlowActive_ then
        if LetterIntro.isOpen() then LetterIntro.update(dt)
        elseif ScenarioDialogue.isActive() then ScenarioDialogue.update(dt) end
        return
    end

    BottomNav.update(dt)

    -- 按实际打开的菜单自动触发，覆盖城镇点击、教程恢复和其他直达入口。
    if postStartFlowDone_ then
        local place = require("ui.tutorial.TutorialPageRecovery").getStoryPlace()
        local story = require("systems.StoryPlayer")
        if place == "battle_town" then
            local battle = ClientDispatcher.get("battle") or {}
            local cleared = battle.clearedStages or {}
            -- 三行布局一开始就画城镇，但故事抵达城门仍应在第一章通关之后。
            if cleared[105] == true or cleared["105"] == true
                or (tonumber(battle.maxStageId) or 0) >= 201 then
                story.onPlace("town", "enter")
            end
        else
            story.onPlace(place, "enter")
        end
    end

    -- [横屏接线 0928] 新手引导每帧驱动（原 ClientUpdate 接线，重构时丢失）
    -- 热点在绘制帧开始时清空，输入始终可读取最近一次实际渲染的坐标。
    TutorialManager.update(dt)
    -- 通知引导当前所在面板（enter_panel_* 类步骤推进）
    do
        local TAB_PANEL_EVENTS = { [3] = "enter_panel_battle", [5] = "enter_panel_dungeon" }
        local tutTab = BottomNav.getSelectedIndex()
        if TAB_PANEL_EVENTS[tutTab] then
            TutorialManager.notifyEvent(TAB_PANEL_EVENTS[tutTab])
        end
    end

    -- ── BGM 轨道切换（优先级：城镇建筑 > 标签页）──
    -- [LetterIntro] 开场链（信/过场/情景1）期间不自动切轨，轨道由开场链自控
    if not (LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive()) then
    do
        local tabIndex = BottomNav.getSelectedIndex()
        local bgmScene
        -- 城镇建筑
        if tabIndex == 4 and (BlacksmithPage.isOpen()
            or ChurchPage.isOpen()
            or TalentPage.isOpen()
            or TavernPage.isOpen()
            or MarketPage.isOpen()) then
            bgmScene = "town_building"
        -- 标签页
        elseif tabIndex == 3 then bgmScene = BattleScene.isInTerminalTemple() and "samsara" or "battle"
        elseif tabIndex == 4 then
            bgmScene = "town"
            require("systems.StoryPlayer").onPlace("town", "enter")
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
    else
        -- 进游戏后一次性把已首通但未领取的情景补入队（如情景82）；
        -- 等数据齐（battle/session 恢复）再扫，随后由 tryPlayPendingStory_ 自然播出
        if postStartFlowDone_ and not storyBackfilled_ and ClientDispatcher.hasData() then
            storyBackfilled_ = true
            local okBf, errBf = pcall(function()
                require("systems.StoryPlayer").backfillCleared()
            end)
            if not okBf then
                print("[Standalone] story backfill failed: " .. tostring(errBf))
            end
        end
        tryPlayPendingStory_()
        require("ui.character.hero.HeroScenario").update()
    end

    -- 横屏专用: 战斗布局恒为 strip
    BattleLayout.setMode("strip")
    local triRenderScale = BattleTriPage.isOpen() and BattleLayout.CARD_SCALE or 1.0
    ProjectileSystem.setRenderScale(triRenderScale)
    BattleEffects.setRenderScale(triRenderScale)
    if BattleTriPage.isOpen() and (DungeonBattleScene.isOpen() or TowerBattleScene.isActive()) then
        BattleTriPage.close()
    end

    require("ui.dev.CERuntime").installSpeedHook()
    require("ui.dev.CERuntime").tick()
    -- 待领取离线奖励时暂停战斗；Flush仍沿原事务语义保存，但不推进在线时间边界。
    local awaitingOfflineClaim = require("rules.offline.OfflineService").HasPendingRewards(1)
    local sidePanelsPaused = SidePanelBattlePause.refresh()
    if postStartFlowDone_ and not awaitingOfflineClaim then
        -- 守卫只围住战斗派发，不能全局return或传dt=0（仍会判胜/连击/发奖）。
        -- 塔/副本内部保留确认、结算与回执超时的真实dt；只跳过ACTIVE战斗。
        if TowerBattleScene.isActive() then
            TowerBattleScene.update(dt, sidePanelsPaused)
        elseif DungeonBattleScene.isOpen() then
            DungeonBattleScene.update(dt, sidePanelsPaused)
        elseif BattleTriPage.isOpen() then
            if not sidePanelsPaused then BattleTriPage.update(dt) end
        elseif BottomNav.getSelectedIndex() ~= 5 and BottomNav.getSelectedIndex() ~= 3 then
            -- 副本详情/结算退出仍暂停原三队；不能启动默认战场清掉其天赋状态。
            -- 返回tab3的首帧由下方守卫重开三队，不抢先驱动默认场景。
            if not sidePanelsPaused then BattleScene.update(dt) end
        end
    end
    require("ui.dev.CERuntime").tick()

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
        ---@diagnostic disable-next-line: undefined-global
        if math.floor(H_AUTO_TAB) ~= 3 and BattleTriPage.isOpen() then
            BattleTriPage.close()  -- 避免三栏战斗页全屏覆盖目标面板
        end
        ---@diagnostic disable-next-line: undefined-global
        BottomNav.setSelectedIndex(math.floor(H_AUTO_TAB))
        ---@diagnostic disable-next-line: undefined-global
        print("[ValidateHook] switched tab: " .. tostring(H_AUTO_TAB))
    end
    ---@diagnostic disable-next-line: undefined-global
    if H_AUTO_OPEN_PANEL and H_skipDone and not H_shotPanelOpened then
        H_shotPanelOpened = true
        ---@diagnostic disable-next-line: undefined-global
        local panelMod = require(require("ui.ModuleMap").resolve(H_AUTO_OPEN_PANEL))
        if panelMod and panelMod.open then
            panelMod.open()
            ---@diagnostic disable-next-line: undefined-global
            print("[ValidateHook] opened panel: " .. tostring(H_AUTO_OPEN_PANEL))
        end
    end
    CharacterPanel.updateBadges()
    if tabIndex == 1 then
        CharacterPanel.update(dt)
    elseif tabIndex == 5 or (tabIndex == 3 and DungeonPage.isTowerChallengePending()) then
        DungeonPage.update(dt)
    end
    if tabIndex ~= 5 and not DungeonBattleScene.isOpen() and not TowerBattleScene.isActive()
        and not (tabIndex == 3 and DungeonPage.isTowerChallengePending()) then
        -- 选关发出的塔请求在tab3继续等回执/超时；导航离开仍取消迟到挑战。
        DungeonPage.close()
    end
    if BackpackPanel.isOpen() and BackpackPanel.isLeftMode() then
        BackpackPanel.update(dt)
    end

    -- 铁匠铺分解红点：通知/引用变化即刷新，未通知原地增删至多约半秒兜底。
    updateInventoryBadges(dt)

    LootBox.update(dt)
    RewardPopup.update(dt)
    OfflineRewardPanel.update(dt)
    LevelUpPopup.update(dt)
    TavernPage.update(dt)
    MarketPage.update(dt)
    PlayerInfoPanel.update(dt)
    local KeyboardShortcuts = require("ui.dev.KeyboardShortcuts")
    KeyboardShortcuts.update()
end

function HandleMouseButtonDown(eventType, eventData)
    if not bootReady_ or StandaloneRT.entryPreparing then return end
    ---@diagnostic disable-next-line: undefined-global
    return HandleMouseButtonDownHorizon(eventType, eventData)
end

function HandleMouseMove(eventType, eventData)
    if not bootReady_ or StandaloneRT.entryPreparing then return end
    ---@diagnostic disable-next-line: undefined-global
    return HandleMouseMoveHorizon(eventType, eventData)
end

function HandleMouseButtonUp(eventType, eventData)
    if not bootReady_ or StandaloneRT.entryPreparing then return end
    ---@diagnostic disable-next-line: undefined-global
    return HandleMouseButtonUpHorizon(eventType, eventData)
end

function HandleTouchBegin(eventType, eventData)
    if not bootReady_ or StandaloneRT.entryPreparing then return end
    ---@diagnostic disable-next-line: undefined-global
    return HandleTouchBeginHorizon(eventType, eventData)
end

function HandleTouchMove(eventType, eventData)
    if not bootReady_ or StandaloneRT.entryPreparing then return end
    ---@diagnostic disable-next-line: undefined-global
    return HandleTouchMoveHorizon(eventType, eventData)
end

function HandleTouchEnd(eventType, eventData)
    if not bootReady_ or StandaloneRT.entryPreparing then return end
    ---@diagnostic disable-next-line: undefined-global
    return HandleTouchEndHorizon(eventType, eventData)
end

function HandleScreenMode(eventType, eventData)
    RecalcLayout()
    print(string.format("[Standalone] ScreenMode window %.0fx%.0f dpr=%.2f frame 1920x1080 scale=%.3f", StandaloneRT.windowW or 0, StandaloneRT.windowH or 0, dpr, StandaloneRT.frameScale or 1))
end

function HandleMouseWheel(eventType, eventData)
    if not bootReady_ or StandaloneRT.entryPreparing then return end
    ---@diagnostic disable-next-line: undefined-global
    return HandleMouseWheelHorizon(eventType, eventData)
end




require("boot.StandaloneHorizon")

return Standalone
