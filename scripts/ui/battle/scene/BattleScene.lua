-- ============================================================================
-- BattleScene - 战斗场景 UI
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- ============================================================================

local AD  = require("systems.AttributeDef")
local ART = require("systems.ArtifactRuntime")
local MAS = require("systems.MapAffixSystem")
local SC  = require("config.StageConfig")

local BattleLayout      = require("core.BattleLayout")
local BattleCombat      = require("ui.battle.combat.BattleCombat")
local StageBerserk     = require("ui.battle.stage.StageBerserk")
local BattleDraw        = require("ui.battle.scene.BattleDraw")
local BattleEffects     = require("ui.battle.combat.BattleEffects")
local ProjectileSystem  = require("ui.battle.combat.ProjectileSystem")
local LootBox           = require("ui.loot.LootBox")
local SweepDialog       = require("ui.battle.stage.SweepDialog")
local DamageStatsPanel  = require("ui.battle.popup.DamageStatsPanel")
local SpeechBubble      = require("ui.widget.SpeechBubble")
local BottomNav         = require("ui.hud.BottomNav")

local Diag = require("systems.BattleDiag")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化] 地图压暗滤镜

local BattleResultPanel = require("ui.battle.popup.BattleResultPanel")
local OfflineCalc = require("systems.OfflineCalc")
local DropSystem = require("systems.DropSystem")
local TerminalConfirmDialog = require("ui.battle.popup.TerminalConfirmDialog")
local MonsterInfoPopup = require("ui.battle.popup.MonsterInfoPopup")
local BattleSpeed = require("ui.battle.stage.BattleSpeed")
local BattleEnemySpawn = require("ui.battle.stage.BattleEnemySpawn")
local BattleTransitionHud = require("ui.battle.stage.BattleTransitionHud")
local BattleStageFlow = require("ui.battle.stage.BattleStageFlow")
local BattleAllyReset = require("ui.battle.scene.BattleAllyReset")
local BattleAllyLifecycle = require("ui.battle.scene.BattleAllyLifecycle")
local BattleStageNav = require("ui.battle.stage.BattleStageNav")
local BattleCasualty = require("ui.battle.combat.BattleCasualty")
local BattleStageLoad = require("ui.battle.stage.BattleStageLoad")
local BattleSceneTick = require("ui.battle.scene.BattleSceneTick")
local BattleScenePhases = require("ui.battle.scene.BattleScenePhases")
local BattleStageNavLogic = require("ui.battle.stage.BattleStageNavLogic")
local BattleDataRestore = require("ui.battle.scene.BattleDataRestore")
local BattleMountScope = require("ui.battle.scene.BattleMountScope")

local BattleScene = {}
BattleScene.GameState = require("core.GameState")

-- 己方场地上限（固定）
local MAX_FIELD_ALLIES = 5

-- ======================== 常量 ========================

local DESIGN_W = 1080

-- 地图背景（后续随关卡变化，参见 setMapBackground()）
local MAP_W, MAP_H = 1080, 2400
local MAP_CX, MAP_CY = 540, 1200

-- 卡片尺寸与敌我绘制共用同一事实源
local CARD_W, CARD_H = BattleLayout.CARD_W, BattleLayout.CARD_H

-- 敌方战场阴影
local ENEMY_SHADOW_CX, ENEMY_SHADOW_CY = 540, 804
local ENEMY_SHADOW_W, ENEMY_SHADOW_H   = 1080, 556

-- 己方战场阴影
local ALLY_SHADOW_CX, ALLY_SHADOW_CY = 540, 1760
local ALLY_SHADOW_W, ALLY_SHADOW_H   = 1080, 556

-- 敌方卡片组 基准坐标（单卡时的 X=540）
local ENEMY_CARD_CY      = 804
local ENEMY_TAG_OFFSET_Y  = -CARD_H * 0.5 + 4
local ENEMY_NAME_OFFSET_Y = CARD_H * 0.5 - 117
local ENEMY_HP_BG_OFFSET_Y = CARD_H * 0.5 - 54
local ENEMY_HP_VAL_OFFSET_Y = CARD_H * 0.5 - 72
local ENEMY_ATK_BG_OFFSET_Y = 181
local ENEMY_LVL_OFFSET_Y = CARD_H * 0.5 - 4

-- 己方卡片组 基准坐标
local ALLY_CARD_CY       = 1760
local ALLY_TAG_OFFSET_Y   = -CARD_H * 0.5 + 4
local ALLY_NAME_OFFSET_Y  = CARD_H * 0.5 - 134
local ALLY_HP_BG_OFFSET_Y = CARD_H * 0.5 - 66
local ALLY_HP_VAL_OFFSET_Y = CARD_H * 0.5 - 84
local ALLY_ATK_BG_OFFSET_Y = 181
local ALLY_LVL_OFFSET_Y  = CARD_H * 0.5 - 4

-- 关卡名 / 按钮坐标（合并到 table 减少 local 占用）
local NAV = BattleStageNav.NAV

-- (职业标签 TAG_SIZE / HP_BAR 已移至 BattleDraw)

-- 死亡即补位：退场+空位总时长（秒），期满新怪从右补入
local RESPAWN_DELAY = 1.0

-- [补位节流] 按 enemies 引用隔离的补位冷却（weak-key，多只同帧死亡时逐只补入防一齐涌入）
local reinforceCdByList = setmetatable({}, { __mode = "k" })

-- 死亡/复活动画常量（定义在 BattleCombat，此处引用）
local DEATH_ANIM_DURATION  = BattleCombat.DEATH_ANIM_DURATION
local REVIVE_ANIM_DURATION = BattleCombat.REVIVE_ANIM_DURATION

-- ======================== 图片 handles ========================

local vg_         = nil   -- 缓存 nvg context（init 赋值，loadStage 中切换地图用）
local currentChapter = 0  -- 当前章节号（用于检测章节变化、切换地图背景）

local imgMap      = -1
local pendingMapBgPath_ = nil  -- [启动优化] 地图背景惰性解码：loadStage 只记路径，首次 draw 前再解码
local imgShadow   = -1
local imgHeroCards   = {}   -- imgHeroCards[heroId] = nvg image handle
local imgMonsterCards = {}  -- imgMonsterCards[monsterId] = nvg image handle
local imgHpBg     = -1
local imgHpFill   = -1
local imgEsFill   = -1
local imgBtnBack  = -1
local imgBtnFwd   = -1
local imgBtnIcon  = -1
local imgEnemyTag = -1
local imgAllyTags = {}   -- classId(字符串) → 职业图标句柄
-- (CLASS_ICON_MAP 已移至 BattleDraw)

-- ======================== 数据 ========================

local stageName = "黑棘林道1-1"
local idleRangeText_ = nil  -- 挂机范围显示文本缓存

-- 默认攻击间隔（秒）
local DEFAULT_ALLY_INTERVAL  = 1.0
local DEFAULT_ENEMY_INTERVAL = 1.5

-- 敌方单位列表（场上）
local enemies = {}

-- 敌方等待队列（还没上场的敌人）
local enemyQueue = {}

-- 己方单位列表（由 setAllies 填充，init 不再预填占位数据）
local allies = {}
local dropLuck_ = 0  -- 单战线本场固定幸运值，阵亡紧凑和待更新配装不追溯改写

-- [EnemyGuard] 检测逻辑与己方生命周期同职责提取。
local _enemyGuardFired = false
---@type table|nil
local _allyLifecycle = nil
---@type fun()
local bindBattleExtracts
local function getAllyLifecycle()
    if not _allyLifecycle then bindBattleExtracts() end
    return _allyLifecycle
end
local function checkEnemiesCorruption(tag)
    return getAllyLifecycle().checkEnemiesCorruption(tag)
end

-- 当前关卡 ID
local currentStageId = 0101

local function getStageConfig()
    return require("shared.StageProvider").Get()
end
--- 获取当前关卡的敌方场地上限
---@return number
local function getStageMaxFieldEnemies()
    local entry = getStageConfig().getStage(currentStageId)
    if entry and entry.maxFieldEnemies then
        return entry.maxFieldEnemies
    end
    return 5 -- 默认值
end

-- 已首通关卡集合（内存，key=stageId, value=true）
local clearedStages = {}

-- 是否首通模式（由 loadStage 从 clearedStages 派生）
local isFirstClear = true

-- 玩家累计抵达过的最远关卡 ID（服务端 maxStageId，用于判断前进提示动画）
-- 初始=第一关已解锁（新档可立即挑战/挂机/选关）；此前初始 0 会导致：
-- 选关列表 fallback 只显示 1-1、扫荡弹窗无法识别关卡（当前关进度脱节）
local maxStageId_ = SC.NORMAL_FIRST_STAGE or 101

-- 当关击杀进度（死亡怪/总怪，首通模式用于行内进度显示）
local stageEnemyTotal_ = 0
local stageKillCount_ = 0

-- 是否已收到首次服务端 battle 数据（首次加载需无条件恢复关卡）
local initialBattleDataLoaded = false

-- 灰色前进按钮图片句柄
local imgBtnFwdGrey = -1

-- 暂停状态：用户切离战斗页面时暂停战斗逻辑
local isPaused = false
local regenAccum = 0          -- 每秒回血累积计时器

-- 首通战斗倍速：只影响 BattleScene 首通战斗逻辑，不影响挂机/副本/通天塔/网络计时
BattleScene.battleSpeed = 1.0
BattleScene.imgSpeedIcon = -1

-- 挂机寻怪计时
local SEARCH_ENEMY_DURATION = 3.0   -- "寻怪中"进度条时长（秒）
local searchingTimer = nil           -- nil=未寻怪; number=已过秒数

-- 失败延迟后退
local DEFEAT_DELAY = 1.5            -- 失败后等待时间（秒）
local defeatTimer = nil              -- nil=未触发; number=已过秒数
local terminalDefeatPending = false  -- 终焉神殿失败后需要回退到上一关
local defeatByTimeout = false        -- 本次失败是否由战斗限时触发

-- 轮回计时（终焉神殿专用）
local REINCARNATION_DELAY = 2.0      -- 轮回过渡时长（秒）
local reincarnationTimer = nil       -- nil=未触发; number=已过秒数

-- 首通战斗限时（秒，nil=不限时/挂机模式）
local victoryMarch = nil             -- 已通关后的真实时钟行军，battleActive=false仍推进
local firstClearTimeLeft = nil

-- 击杀回调: function(data) 其中 data = { expReward, goldReward, allyCount, expMult }
local onEnemyKillCallback = nil

-- 首通回调: function(clearedStageId) — 关卡首次通关时通知外部持久化
local onFirstClearCallback = nil
local onStageLoadedCallback = nil

-- 关卡切换回调: function(newStageId) — 前进/后退切换关卡时通知外部持久化
local onStageChangedCallback = nil

-- 敌方掉落回调: function(data) 其中 data = { stageId, enemyCX, enemyCY }
local onEnemyDropCallback = nil

-- 轮回回调: function(data) 其中 data = { fromDifficulty, toDifficulty, newStageId }
local onReincarnateCallback = nil

-- 全体阵亡回调: function() — 非终焉神殿战斗失败（全员阵亡）时触发
local onAllDeadCallback = nil

-- 待完成的轮回（用于延迟加载，等外部动画结束后调用 completeReincarnation）
---@type {targetStageId:number, fromDifficulty:number, toDifficulty:number}|nil
local pendingReincarnation = nil

-- (战斗动画状态: floatingTexts/cardAnims/hitFlashes/hpBuffers 已移至 BattleCombat)

-- 背景走动：放大再回正（模拟迈步），不做淡出换图
local bgTransAnim = nil  -- nil=无动画; { timer, zoomTarget }
local BG_TRANS_DURATION   = 0.72  -- 总时长（放大半步 + 回正半步）
local BG_ZOOM_FWD_TARGET  = 1.32  -- 前进峰值
local BG_ZOOM_BACK_TARGET = 1.22  -- 后退也放大（迈步感），峰值略低
--- 全局章节号转难度内相对章节号
local function getRelativeChapter(chapter)
    return SC.getRelativeChapter(chapter)
end

-- 背景持续动效：上下缓慢漂移
local bgAnimTimer = 0
local BG_DRIFT_Y_AMP    = 16    -- 垂直漂移幅度（像素）
local BG_DRIFT_Y_PERIOD = 5.0   -- 垂直漂移周期（秒）

-- 战斗是否进行中（init 不再预加载关卡，等 setBattleData 首次到达后启动）
local battleActive = false

-- 战斗超时增伤计时（秒，战斗逻辑时间；随每场战斗/每波重开清零）
local battleTimeoutElapsed = 0
local BattleTimeout = require("systems.BattleTimeout")

-- 挂机收益缓存（每分钟）—— 直接由 OfflineCalc 统一公式计算
local cachedGoldPerMin = 0
local cachedExpPerMin  = 0

-- 波次效率测量（纯本地，用于战斗统计，不参与收益显示）
local waveStartTime = nil      -- 本波次开始时间（time.elapsedTime）
local waveKillCount = 0        -- 本波次击杀数
local waveGoldEarned = 0       -- 本波次获得金币
local waveExpEarned = 0        -- 本波次获得经验

-- (工具绘制函数 drawImageCentered/drawImageMirrored/drawTextStroke 已移至 BattleDraw)
---@type fun(vg, img, cx, cy, w, h, alpha)
local drawImageCentered = BattleDraw.drawImageCentered
---@type fun(vg, img, cx, cy, w, h, alpha)
local drawImageMirrored = BattleDraw.drawImageMirrored
local drawTextStroke    = BattleDraw.drawTextStroke
-- ======================== BattleCombat 本地别名 ========================
local getAliveUnits       = BattleCombat.getAliveUnits
local getCardCX           = BattleCombat.getCardCX
local syncUnitHp          = BattleCombat.syncUnitHp
local addFloatingText     = BattleCombat.addFloatingText
local dealDamageToUnit    = BattleCombat.dealDamageToUnit
local performAttack       = BattleCombat.performAttack
local updateCardAnims     = BattleCombat.updateCardAnims
local updateFloatingTexts = BattleCombat.updateFloatingTexts
local updateHitFlashes    = BattleCombat.updateHitFlashes
local updateComboQueue    = BattleCombat.updateComboQueue

function BattleScene.getMaxUnlockedBattleSpeed()
    local Page = require("ui.battle.tri.BattleTriPage")
    if Page.isOpen() then return Page.getMaxUnlockedBattleSpeed() end
    return BattleSpeed.getMaxUnlocked(getStageConfig().getDifficulty(currentStageId))
end

function BattleScene.isSpeedButtonVisible()
    local Page = require("ui.battle.tri.BattleTriPage")
    if Page.isOpen() then return Page.isSpeedButtonVisible() end
    return isFirstClear and battleActive and not isPaused
        and BattleScene.getMaxUnlockedBattleSpeed() > 1.0
        and not BattleResultPanel.isOpen()
        and not TerminalConfirmDialog.isOpen()
        and not SweepDialog.isOpen() and not DamageStatsPanel.isOpen()
        and searchingTimer == nil and defeatTimer == nil and reincarnationTimer == nil
end

function BattleScene.getBattleLogicDt(dt)
    local Page = require("ui.battle.tri.BattleTriPage")
    if Page.isOpen() then return Page.getBattleLogicDt(dt) end
    local logicDt, speed = BattleSpeed.getLogicDt(
        dt, BattleScene.battleSpeed, BattleScene.getMaxUnlockedBattleSpeed(),
        BattleScene.isSpeedButtonVisible())
    BattleScene.battleSpeed = speed
    return logicDt
end

local getLiveAttackInterval = BattleAllyLifecycle.getLiveAttackInterval

function BattleScene.getSpeedText()
    return BattleSpeed.getSpeedText(BattleScene.battleSpeed)
end

function BattleScene.drawSpeedButton(vg)
    BattleSpeed.draw(vg, BattleScene.imgSpeedIcon, BattleScene.battleSpeed, BattleScene.isSpeedButtonVisible())
end

function BattleScene.cycleBattleSpeed()
    if not BattleScene.isSpeedButtonVisible() then return false end
    BattleScene.battleSpeed = BattleSpeed.cycle(BattleScene.battleSpeed, BattleScene.getMaxUnlockedBattleSpeed())
    print("[BattleScene] 首通战斗倍速切换: " .. BattleScene.getSpeedText())
    return true
end

function BattleScene.handleSpeedButtonInput(dx, dy)
    if not BattleSpeed.hitTest(dx, dy) then return false end
    return BattleScene.cycleBattleSpeed()
end

-- ======================== 属性快照隔离（委托 BattleAllyReset） ========================
local function resetAllyUnit(u)
    BattleAllyReset.resetAllyUnit(u, allies, syncUnitHp)
end

-- BattleDraw 本地别名
---@type fun(vg, units, baseCY, tagOffY, nameOffY, hpBgOffY, hpValOffY, atkBgOffY, lvlOffY, tagImg, isAllyGroup)
local drawCardGroup       = BattleDraw.drawCardGroup
---@type fun(vg)
local drawFloatingTexts   = BattleDraw.drawFloatingTexts

-- ======================== 关卡系统 ========================
--- 重新计算挂机收益（每分钟金币/经验）
--- 直接调用 OfflineCalc 统一公式：固定杀怪效率 × 60秒 → 每分钟收益
local function recalcIdleIncome()
    if maxStageId_ <= 0 then
        cachedGoldPerMin = 0
        cachedExpPerMin = 0
        return
    end
    local heroCount = #allies
    local prevGold = cachedGoldPerMin
    local prevExp  = cachedExpPerMin
    -- 账户收益只读权威最高节点及严格true账本；当前选关和首通模式不参与。
    local savedBattle = require("runtime.ClientDispatcher").get("battle")
    local accountMax = type(savedBattle) == "table" and tonumber(savedBattle.maxStageId) or nil
    local incomeMax = accountMax and accountMax > 0 and accountMax or maxStageId_
    local ledger
    if accountMax and accountMax > 0 then
        ledger = type(savedBattle.clearedStages) == "table" and savedBattle.clearedStages or {}
    else
        ledger = clearedStages
    end
    local maxCleared = ledger[incomeMax] == true or ledger[tostring(incomeMax)] == true
    local battleSnapshot = {
        maxStageId = incomeMax,
        clearedStages = { [incomeMax] = maxCleared },
    }
    local stageConfig = getStageConfig()
    local incomeStageId, dropStageId = OfflineCalc.resolveIdleStageAnchors(battleSnapshot, stageConfig)
    local rewards = OfflineCalc.calcOnlineIdleRewards(60, incomeStageId, heroCount, dropStageId, stageConfig)
    if rewards then
        cachedGoldPerMin = rewards.gold or 0
        cachedExpPerMin  = (rewards.adventureExp or 0) + (rewards.adventurerExp or 0)
    else
        cachedGoldPerMin = 0
        cachedExpPerMin = 0
    end
    -- [DEBUG] 收益变化诊断：如果收益下降则高亮警告
    local goldDelta = cachedGoldPerMin - prevGold
    local expDelta  = cachedExpPerMin - prevExp
    local tag = (goldDelta < 0 or expDelta < 0) and "⚠️DECREASE" or "OK"
    print(string.format("[INCOME_DEBUG] recalcIdleIncome [%s]: gold=%d→%d(%+d) exp=%d→%d(%+d) incomeStage=%d dropStage=%d maxStage=%d heroes=%d currentStage=%s firstClear=%s",
        tag, prevGold, cachedGoldPerMin, goldDelta, prevExp, cachedExpPerMin, expDelta,
        incomeStageId, dropStageId, maxStageId_, heroCount, tostring(currentStageId), tostring(isFirstClear)))
end
--- 结算当前波次（仅统计用，不再影响收益显示）
local function settleWaveEfficiency()
    if not waveStartTime or waveKillCount <= 0 then return end
    -- 波次统计仅用于战斗日志/调试，收益显示完全由 OfflineCalc 驱动
    waveStartTime = nil
end
--- 重置波次计时状态
local function resetWaveTimers()
    waveStartTime = time.elapsedTime
    waveKillCount = 0
    waveGoldEarned = 0
    waveExpEarned = 0
end

local function generateEnemyList(stageEntry)
    return BattleEnemySpawn.generateEnemyList(stageEntry, isFirstClear)
end

local function assignEnemiesToField(allEnemies, maxField)
    return BattleEnemySpawn.assignEnemiesToField(allEnemies, maxField)
end

local function generateIdleEnemyList()
    return BattleEnemySpawn.generateIdleEnemyList(getStageConfig(), maxStageId_, currentStageId)
end

local function captureDropLuck()
    dropLuck_ = DropSystem.captureTeamLuck(allies)
end

local function startBattleTalents()
    captureDropLuck()
    BattleStageFlow.startBattleTalents(allies, enemies)
end
--- 恢复主战斗的 BattleCombat 上下文（副本/竞技场关闭后必须调用）
--- 将 ctx.getAllies / ctx.getEnemies 重新指向主战斗的 allies/enemies
local function setupBattleCombatContext()
    return getAllyLifecycle().setupBattleCombatContext()
end

-- [卡牌分帧加载] 英雄卡/怪物卡/投射物图，首次进战斗时构建队列，由 update 分帧消化
---@type table[]|nil
local battleCardQueue = nil
local function ensureBattleCards(vg)
    battleCardQueue = BattleStageFlow.ensureBattleCards({
        imgHeroCards = imgHeroCards,
        imgMonsterCards = imgMonsterCards,
        vg = vg,
    }, battleCardQueue)
end

local function pumpBattleCards()
    battleCardQueue = BattleStageFlow.pumpBattleCards(battleCardQueue, vg_)
end
--- 加载关卡
---@param stageId number 4位关卡ID, 如 0101
---@param skipBattleStart? boolean 跳过 TAL/TM 战斗启动（调用方自行在 resetAllyUnit 后调用 startBattleTalents）
---@param deferEnter? boolean 三行兼容Scene加载不提前通知实际Driver进场
local function loadStage(stageId, skipBattleStart, deferEnter)
    -- 任意实际切关/重开都取消旧行军，避免选关后预约再次跳关。
    victoryMarch = nil
    BattleMountScope.mountDefault()
    local ctx = {
        currentStageId = currentStageId, stageName = stageName, maxStageId_ = maxStageId_,
        isFirstClear = isFirstClear, idleRangeText_ = idleRangeText_,
        searchingTimer = searchingTimer, defeatTimer = defeatTimer, reincarnationTimer = reincarnationTimer,
        pendingReincarnation = pendingReincarnation, terminalDefeatPending = terminalDefeatPending,
        currentChapter = currentChapter, vg_ = vg_,
        enemies = enemies, enemyQueue = enemyQueue, allies = allies,
        stageEnemyTotal_ = stageEnemyTotal_, stageKillCount_ = stageKillCount_,
        _enemyGuardFired = _enemyGuardFired, battleActive = battleActive,
        firstClearTimeLeft = firstClearTimeLeft, onStageLoadedCallback = onStageLoadedCallback,
        clearedStages = clearedStages,
        battleTimeoutElapsed = battleTimeoutElapsed,
        ensureBattleCards = ensureBattleCards, getStageConfig = getStageConfig,
        recalcIdleIncome = recalcIdleIncome, resetWaveTimers = resetWaveTimers,
        generateIdleEnemyList = generateIdleEnemyList, generateEnemyList = generateEnemyList,
        assignEnemiesToField = assignEnemiesToField, startBattleTalents = startBattleTalents,
        setMapBackground = BattleScene.setMapBackground,
    }
    BattleStageLoad.load(ctx, stageId, skipBattleStart)
    currentStageId = ctx.currentStageId
    stageName = ctx.stageName
    maxStageId_ = ctx.maxStageId_
    isFirstClear = ctx.isFirstClear
    idleRangeText_ = ctx.idleRangeText_
    searchingTimer = ctx.searchingTimer
    defeatTimer = ctx.defeatTimer
    reincarnationTimer = ctx.reincarnationTimer
    pendingReincarnation = ctx.pendingReincarnation
    terminalDefeatPending = ctx.terminalDefeatPending
    currentChapter = ctx.currentChapter
    enemies = ctx.enemies
    enemyQueue = ctx.enemyQueue
    stageEnemyTotal_ = ctx.stageEnemyTotal_
    stageKillCount_ = ctx.stageKillCount_
    _enemyGuardFired = ctx._enemyGuardFired
    battleActive = ctx.battleActive
    firstClearTimeLeft = ctx.firstClearTimeLeft
    battleTimeoutElapsed = ctx.battleTimeoutElapsed or 0
    print("[BattleScene] stage loaded id=" .. tostring(stageId))
    if not deferEnter and currentStageId == stageId then
        require("ui.battle.stage.StageEntryEvents").notify(stageId, 1)
    end
end

local _navLogic
local _dataRestore
bindBattleExtracts = function()
    local getters = {
        currentStageId = function() return currentStageId end,
        maxStageId_ = function() return maxStageId_ end,
        clearedStages = function() return clearedStages end,
        stageName = function() return stageName end,
        pendingReincarnation = function() return pendingReincarnation end,
        onStageChangedCallback = function() return onStageChangedCallback end,
        BG_ZOOM_FWD_TARGET = function() return BG_ZOOM_FWD_TARGET end,
        BG_ZOOM_BACK_TARGET = function() return BG_ZOOM_BACK_TARGET end,
        initialBattleDataLoaded = function() return initialBattleDataLoaded end,
        battleActive = function() return battleActive end,
        searchingTimer = function() return searchingTimer end,
        defeatTimer = function() return defeatTimer end,
        reincarnationTimer = function() return reincarnationTimer end,
        victoryMarch = function() return victoryMarch end,
        isFirstClear = function() return isFirstClear end,
        _enemyGuardFired = function() return _enemyGuardFired end,
    }
    local function get(key)
        return getters[key]()
    end
    local function set(key, value)
        if key == "searchingTimer" then searchingTimer = value
        elseif key == "defeatTimer" then defeatTimer = value
        elseif key == "reincarnationTimer" then reincarnationTimer = value
        elseif key == "victoryMarch" then victoryMarch = value
        elseif key == "bgTransAnim" then bgTransAnim = value
        elseif key == "regenAccum" then regenAccum = value
        elseif key == "pendingReincarnation" then pendingReincarnation = value
        elseif key == "maxStageId_" then maxStageId_ = value
        elseif key == "clearedStages" then clearedStages = value
        elseif key == "battleActive" then battleActive = value
        elseif key == "initialBattleDataLoaded" then initialBattleDataLoaded = value
        elseif key == "isFirstClear" then isFirstClear = value
        end
    end
    local function setLifecycle(key, value)
        if key == "dropLuck" then dropLuck_ = value
        elseif key == "reincarnationTimer" then reincarnationTimer = value
        elseif key == "allies" then allies = value
        elseif key == "enemies" then enemies = value
        elseif key == "enemyQueue" then enemyQueue = value
        elseif key == "_enemyGuardFired" then _enemyGuardFired = value
        elseif key == "battleTimeoutElapsed" then battleTimeoutElapsed = value
        elseif key == "firstClearTimeLeft" then firstClearTimeLeft = value
        elseif key == "waveStartTime" then waveStartTime = value
        elseif key == "waveKillCount" then waveKillCount = value
        elseif key == "waveGoldEarned" then waveGoldEarned = value
        elseif key == "waveExpEarned" then waveExpEarned = value
        elseif key == "currentStageId" then currentStageId = value
        elseif key == "isPaused" then isPaused = value
        elseif key == "bgAnimTimer" then bgAnimTimer = value
        elseif key == "currentChapter" then currentChapter = value
        else set(key, value)
        end
    end
    local shared = {
        getStageConfig = getStageConfig,
        loadStage = loadStage,
        resetAllyUnit = resetAllyUnit,
        startBattleTalents = startBattleTalents,
        recalcIdleIncome = recalcIdleIncome,
        getAllies = function() return allies end,
        get = get,
        set = set,
    }
    _navLogic = BattleStageNavLogic.bind(shared)
    _dataRestore = BattleDataRestore.bind(shared)
    _allyLifecycle = BattleAllyLifecycle.bind({
        getStageConfig = getStageConfig, getStageMaxFieldEnemies = getStageMaxFieldEnemies,
        loadStage = loadStage, resetAllyUnit = resetAllyUnit,
        startBattleTalents = startBattleTalents, recalcIdleIncome = recalcIdleIncome,
        getAllies = function() return allies end, getEnemies = function() return enemies end,
        getEnemyQueue = function() return enemyQueue end, get = get, set = setLifecycle,
        MAX_FIELD_ALLIES = MAX_FIELD_ALLIES, ALLY_CARD_CY = ALLY_CARD_CY, ENEMY_CARD_CY = ENEMY_CARD_CY,
    })
end

-- ======================== Public API ========================

function BattleScene.init(vg)
    -- 新NanoVG上下文不能复用旧卡牌句柄或已完成队列；同上下文切关不失效。
    if vg_ ~= vg then
        battleCardQueue = nil
        for id in pairs(imgHeroCards) do imgHeroCards[id] = nil end
        for id in pairs(imgMonsterCards) do imgMonsterCards[id] = nil end
    end
    vg_ = vg  -- 缓存，供 loadStage 切换地图背景
    -- 地图背景延后到 loadStage / 首次绘制，避免启动解码 1MB+ MAP_1
    currentChapter = 1
    -- 阴影板绘制为 1080x556（源图 1080x610 压扁），使用 SHADOW 副本，调整原图不影响其他用法
    imgShadow   = nvgCreateImage(vg, "image/界面底板/通用面板/UI_YWJM_MAPYY_SHADOW.png", 0)
    -- [卡牌惰性加载] 英雄卡/怪物卡大图改为首次进战斗时加载（ensureBattleCards）
    -- ⚠️ 新增怪物 ID 时必须补充到 ensureBattleCards 的加载清单！
    -- 否则 BattleDraw 会 fallback 到 imgMonsterCards[1]（怪物1的贴图）。
    -- 战斗卡牌改到首次进战斗时分帧加载（见 loadStage → ensureBattleCards）
    imgHpBg     = nvgCreateImage(vg, "image/界面底板/战斗/UI_ZD_HP1.png", 0)
    imgHpFill   = nvgCreateImage(vg, "image/界面底板/战斗/UI_ZD_HPT2.png", 0)
    imgEsFill   = nvgCreateImage(vg, "image/界面底板/战斗/UI_ZD_HPT3.png", 0)
    imgBtnBack  = nvgCreateImage(vg, "image/界面底板/通用面板/UI_YWJM_XYGA.png", 0)
    imgBtnFwd     = nvgCreateImage(vg, "image/界面底板/通用面板/UI_YWJM_XYGB.png", 0)
    imgBtnFwdGrey = nvgCreateImage(vg, "image/界面底板/通用面板/UI_YWJM_XYG.png", 0)
    imgBtnIcon    = nvgCreateImage(vg, "image/界面底板/通用面板/UI_YWJM_XYG2.png", 0)
    BattleScene.imgSpeedIcon  = nvgCreateImage(vg, "image/通用图标/UI_ICON_kong.png", 0)
    imgEnemyTag = nvgCreateImage(vg, "image/通用图标/ICON_ZY_XG.png", 0)
    for i = 1, 6 do
        imgAllyTags[i] = nvgCreateImage(vg, "image/通用图标/ICON_ZY_" .. i .. ".png", 0)
    end

    -- 初始化攻击特效模块
    BattleEffects.init(vg)

    -- 初始化投射物系统
    ProjectileSystem.init(vg)

    -- 初始化战斗结算面板（副本通用）
    BattleResultPanel.init(vg)

    -- 初始化台词气泡系统
    SpeechBubble.init({
        getCardCX          = getCardCX,
        getAllies           = function() return allies end,
        getCardAnimOffsetY = BattleCombat.getCardAnimOffsetY,
        getChargeOffsetY   = BattleCombat.getChargeOffsetY,
        ALLY_CARD_CY       = ALLY_CARD_CY,
        CARD_H             = CARD_H,
    })

    -- 初始化子模块上下文
    setupBattleCombatContext()
    BattleDraw.setContext({
        combat          = BattleCombat,
        imgHeroCards    = imgHeroCards,
        imgMonsterCards = imgMonsterCards,
        imgHpBg         = imgHpBg,
        imgHpFill       = imgHpFill,
        imgEsFill       = imgEsFill,
        imgAllyTags     = imgAllyTags,
    })

    -- 初始化战利品箱子
    LootBox.init(vg)

    -- 初始化扫荡弹窗
    SweepDialog.init(vg)
    SweepDialog.onSweep = function(count, teamIdx)
        require("runtime.GameAction").sendAction(
            require("shared.Protocol").ACTION_TYPES.SWEEP,
            { count = count or 1, teamIdx = teamIdx or 1 })
    end

    -- 初始化战斗统计面板
    DamageStatsPanel.init(vg)

    -- 不再在 init 预加载关卡：等 setBattleData 首次到达后统一加载正确的关卡
    -- （避免选服前就加载占位角色和战斗场地）

    print("[BattleScene] init OK (deferred loadStage)")
end

function BattleScene.draw(vg)
    -- [启动优化] 地图背景惰性解码：首次 draw 前再创建（单帧只解一张）
    if pendingMapBgPath_ and vg then
        local t0 = time.elapsedTime
        imgMap = nvgCreateImage(vg, pendingMapBgPath_, 0)
        pendingMapBgPath_ = nil
        print(string.format("[BattleScene] 地图背景解码 %.0fms（惰性）", (time.elapsedTime - t0) * 1000))
    end
    -- 1. 地图背景（上下漂移 + 切关走动：放大再回正）
    -- 只向上漂移：0 → -8 → 0，不会向下露出黑底
    local driftY = -BG_DRIFT_Y_AMP * (1.0 - math.cos(bgAnimTimer * 2 * math.pi / BG_DRIFT_Y_PERIOD)) * 0.5
    local mapScale = 1.0
    local walkY = 0
    local mapAlpha = 1.0
    local alignRight = false
    if bgTransAnim then
        local duration = bgTransAnim.duration or BG_TRANS_DURATION
        local t = math.min(bgTransAnim.timer / duration, 1.0)
        local peak = bgTransAnim.zoomTarget or BG_ZOOM_FWD_TARGET
        if peak < 1.0 then
            peak = 2.0 - peak
        end
        if t < 0.45 then
            -- 右边缘对齐放大，模拟往画面右侧迈出
            local u = t / 0.45
            mapScale = 1.0 + (peak - 1.0) * (u * u)
            alignRight = true
            mapAlpha = 1.0
        else
            -- 透明淡入回原本大小
            local u = (t - 0.45) / 0.55
            local fade = u * u * (3 - 2 * u)
            mapScale = peak + (1.0 - peak) * fade
            mapAlpha = fade
            alignRight = true
        end
    end
    local mapX = MAP_CX
    if alignRight then
        mapX = MAP_CX + MAP_W * 0.5 - MAP_W * mapScale * 0.5
    end
    -- 裁进设计画布，放大时不溢到邻栏
    nvgSave(vg)
    nvgIntersectScissor(vg, MAP_CX - MAP_W * 0.5, MAP_CY - MAP_H * 0.5, MAP_W, MAP_H)
    DarkIcon.drawDarkScene(vg, imgMap, mapX, MAP_CY + driftY + walkY,
        MAP_W * mapScale, MAP_H * mapScale, mapAlpha)
    nvgRestore(vg)

    -- 2. 敌方战场阴影
    drawImageCentered(vg, imgShadow, ENEMY_SHADOW_CX, ENEMY_SHADOW_CY,
        ENEMY_SHADOW_W, ENEMY_SHADOW_H, 1.0)

    -- 3a. 地图词缀 + Boss 词缀标签（仅首通模式显示，挂机模式不显示）
    --     地图词缀金色（折磨II+ 才有）；Boss 词缀绯红带"首领"前缀（Hard+ Boss 关才有）
    if isFirstClear then
        local lines = {}
        if MAS.hasAffixes() then
            local affixes = MAS.getActiveAffixes()
            if affixes then
                for _, affix in ipairs(affixes) do
                    lines[#lines + 1] = { text = affix.name .. ": " .. affix.shortDesc, r = 255, g = 190, b = 80 }
                end
            end
        end
        local BAS = require("systems.BossAffixSystem")
        if BAS.hasAffixes() then
            local bossAffixes = BAS.getActiveAffixes()
            if bossAffixes then
                for _, affix in ipairs(bossAffixes) do
                    lines[#lines + 1] = { text = "首领·" .. affix.name .. ": " .. affix.shortDesc, r = 235, g = 96, b = 96 }
                end
            end
        end
        if #lines > 0 then
            -- 每个词缀显示一行，从下往上排列
            local lineH = 34
            local bottomY = 468  -- 最后一行Y位置（与剩余敌人Y=525保持57px间距）
            local baseY = bottomY - (#lines - 1) * lineH
            for i, ln in ipairs(lines) do
                local lineY = baseY + (i - 1) * lineH
                drawTextStroke(vg, 540, lineY, ln.text, 28,
                    NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, ln.r, ln.g, ln.b, 3)
            end
        end
    end

    -- 3b. "剩余敌人 X" 文本
    BattleStageNav.drawRemainEnemies(vg, #enemyQueue)

    -- 4. 敌方卡片组
    drawCardGroup(vg, enemies, ENEMY_CARD_CY,
        ENEMY_TAG_OFFSET_Y, ENEMY_NAME_OFFSET_Y,
        ENEMY_HP_BG_OFFSET_Y, ENEMY_HP_VAL_OFFSET_Y,
        ENEMY_ATK_BG_OFFSET_Y, ENEMY_LVL_OFFSET_Y, imgEnemyTag, false)
    require("systems.ExtraTalentSystem").drawIceStatues(vg)

    -- 5~11. 关卡名 / 前进后退
    idleRangeText_ = BattleStageNav.drawStageTitle(vg, {
        isFirstClear = isFirstClear,
        idleRangeText = idleRangeText_,
        maxStageId = maxStageId_,
        getStageConfig = getStageConfig,
        getRelativeChapter = getRelativeChapter,
        stageName = stageName,
        battleActive = battleActive,
        firstClearTimeLeft = firstClearTimeLeft,
    })
    BattleStageNav.drawNavButtons(vg, {
        isFirstClear = isFirstClear,
        isTerminal = getStageConfig().isTerminalTemple(currentStageId),
        currentStageId = currentStageId,
        maxStageId = maxStageId_,
        getStageConfig = getStageConfig,
        imgBtnBack = imgBtnBack,
        imgBtnIcon = imgBtnIcon,
        imgBtnFwd = imgBtnFwd,
        imgBtnFwdGrey = imgBtnFwdGrey,
    })

    -- 12. 己方战场阴影
    drawImageCentered(vg, imgShadow, ALLY_SHADOW_CX, ALLY_SHADOW_CY,
        ALLY_SHADOW_W, ALLY_SHADOW_H, 1.0)

    -- 13. "我的队伍" 文本
    BattleStageNav.drawTeamLabel(vg)

    -- 14. 己方卡片组
    drawCardGroup(vg, allies, ALLY_CARD_CY,
        ALLY_TAG_OFFSET_Y, ALLY_NAME_OFFSET_Y,
        ALLY_HP_BG_OFFSET_Y, ALLY_HP_VAL_OFFSET_Y,
        ALLY_ATK_BG_OFFSET_Y, ALLY_LVL_OFFSET_Y, imgAllyTags[1], true)

    -- 14.5 首通战斗倍速按钮
    BattleScene.drawSpeedButton(vg)

    -- 14.5~14.7 战斗特效
    if require("ui.hud.popup.SettingsPanel").isEffectsEnabled() then
        -- 常驻召唤物（摘星星星人星门，漂浮在卡片旁并自转）
        ProjectileSystem.drawStarGates(vg, allies, ALLY_CARD_CY, getCardCX, true)
        ProjectileSystem.drawStarGates(vg, enemies, ENEMY_CARD_CY, getCardCX, false)

        -- 投射物（在卡片之上）
        ProjectileSystem.draw(vg)

        -- 攻击特效（在投射物之上、浮动文字之下）
        BattleEffects.draw(vg)

        -- 卡片 Spine 特效（升级/复活，在攻击特效之上）
        require("ui.fx.SpineCardEffect").draw(vg, "battle")
    end

    -- 15. 浮动伤害数字
    if require("ui.hud.popup.SettingsPanel").isDamageNumbersEnabled() then
        drawFloatingTexts(vg)
    end

    -- 15.2 台词气泡（在浮动文字之上、战利品之下）
    SpeechBubble.draw(vg)

    -- 15.5 战利品箱子已迁至全局左下角（Client 左栏层绘制），此处不再绘制

    -- 15.5.1 扫荡按钮入口（与战利品箱子对称）
    SweepDialog.drawButton(vg)

    -- 15.5.2 战斗统计按钮入口（扫荡按钮左侧）
    DamageStatsPanel.drawButton(vg)

    -- 15.6 挂机收益率 → 推送给全局战利品箱（整页左下角）绘制
    local speedCardActive = BattleScene.GameState.getSpeedCardRemainSecs() > 0
    local displayGoldPerMin = speedCardActive and math.floor(cachedGoldPerMin * 1.2 + 0.5) or cachedGoldPerMin
    local displayExpPerMin = speedCardActive and math.floor(cachedExpPerMin * 1.2 + 0.5) or cachedExpPerMin
    LootBox.setRates(displayGoldPerMin, displayExpPerMin)

    -- 首通狂暴提示横幅（战斗进行中触发时弹出并淡出）
    if StageBerserk.isActive() then
        local bText, bAlpha, bPhase = StageBerserk.getBanner()
        if bText then
            local bnR, bnG, bnB = 255, 170, 40                              -- 一阶狂暴：橙黄
            if bPhase and bPhase >= 2 then bnR, bnG, bnB = 255, 70, 60 end  -- 二阶超级狂暴：红
            drawTextStroke(vg, 540, 660, bText, 38,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, bnR, bnG, bnB, 5, { alpha = bAlpha })
        end
    end

    -- Boss 暴怒提示横幅（v2.64，Boss 词缀 enrage 触发；绯红，y=608 与狂暴错开）
    do
        local BAS = require("systems.BossAffixSystem")
        local bossText, bossAlpha = BAS.getBanner()
        if bossText then
            drawTextStroke(vg, 540, 608, bossText, 36,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 235, 90, 90, 5, { alpha = bossAlpha })
        end
    end

    -- 16. 战斗结束提示 / 寻怪中进度条 / 失败倒计时
    BattleTransitionHud.draw(vg, {
        battleActive = battleActive,
        reincarnationTimer = reincarnationTimer,
        searchingTimer = searchingTimer,
        defeatTimer = defeatTimer,
        defeatByTimeout = defeatByTimeout,
        stageName = stageName,
        currentStageId = currentStageId,
        getStageConfig = getStageConfig,
        drawTextStroke = drawTextStroke,
    })

    -- ---- 扫荡弹窗（在寻怪进度条之上、终焉确认弹窗之下） ----
    SweepDialog.draw(vg)

    -- ---- 战斗统计面板（在扫荡弹窗之上、终焉确认弹窗之下） ----
    DamageStatsPanel.draw(vg)

    -- ---- 终焉神殿确认弹窗（最上层绘制） ----
    TerminalConfirmDialog.draw(vg, currentStageId, getStageConfig)

    -- ---- 副本结算面板（最顶层） ----
    BattleResultPanel.draw(vg)

    -- ---- 长按怪物属性弹窗（最最顶层） ----
    MonsterInfoPopup.draw(vg)
end
--- 三队页面不再走 BattleScene.update，但仍要分帧加载角色/怪物卡面。
function BattleScene.pumpBattleCards()
    if vg_ then ensureBattleCards(vg_) end
    pumpBattleCards()
end

function BattleScene.update(dt)
    -- 同一帧只能有一个战斗宿主；三行打开时兼容Scene不再次推进/乘倍率。
    if require("ui.battle.tri.BattleTriPage").isOpen() then return end
    require("ui.battle.stage.StageEntryEvents").retry(1)
    pumpBattleCards()
    for _, list in ipairs({ enemies, enemyQueue }) do
        for _, unit in ipairs(list) do
            if unit and unit.monsterId == 1007 and unit.attrs then
                if unit.attrs.base then unit.attrs.base[AD.COMBO_RATE] = nil end
                if unit.attrs.derived then unit.attrs.derived[AD.COMBO_RATE] = nil end
                if unit.attrs.flatMod then unit.attrs.flatMod[AD.COMBO_RATE] = nil end
                if unit.attrs.pctMod then unit.attrs.pctMod[AD.COMBO_RATE] = nil end
                if unit.attrs.final then unit.attrs.final[AD.COMBO_RATE] = 0 end
            end
        end
    end

    -- ---- 长按怪物检测 ----
    MonsterInfoPopup.update(enemies)

    -- ---- 终焉神殿确认弹窗关闭动画更新 ----
    TerminalConfirmDialog.update()

    -- ---- 暂停 / 失败延迟 / 轮回 / 寻怪（委托 BattleScenePhases） ----
    local _phCtx = {
        isPaused = isPaused, defeatTimer = defeatTimer, reincarnationTimer = reincarnationTimer,
        searchingTimer = searchingTimer, terminalDefeatPending = terminalDefeatPending,
        defeatByTimeout = defeatByTimeout, isFirstClear = isFirstClear,
        currentStageId = currentStageId, maxStageId_ = maxStageId_,
        battleActive = battleActive, enemies = enemies, enemyQueue = enemyQueue, allies = allies,
        clearedStages = clearedStages, stageName = stageName,
        pendingReincarnation = pendingReincarnation, bgTransAnim = bgTransAnim, regenAccum = regenAccum,
        DEFEAT_DELAY = DEFEAT_DELAY, REINCARNATION_DELAY = REINCARNATION_DELAY,
        SEARCH_ENEMY_DURATION = SEARCH_ENEMY_DURATION,
        BG_ZOOM_BACK_TARGET = BG_ZOOM_BACK_TARGET, BG_ZOOM_FWD_TARGET = BG_ZOOM_FWD_TARGET,
        updateCardAnims = updateCardAnims, updateFloatingTexts = updateFloatingTexts,
        updateHitFlashes = updateHitFlashes, updateComboQueue = updateComboQueue,
        getStageConfig = getStageConfig, loadStage = loadStage, resetAllyUnit = resetAllyUnit,
        startBattleTalents = startBattleTalents, captureDropLuck = captureDropLuck,
        onStageChangedCallback = onStageChangedCallback,
        onReincarnateCallback = onReincarnateCallback, recalcIdleIncome = recalcIdleIncome,
        generateIdleEnemyList = generateIdleEnemyList, assignEnemiesToField = assignEnemiesToField,
        BattleScene = BattleScene,
    }
    if BattleScenePhases.process(_phCtx, dt) then
        defeatTimer = _phCtx.defeatTimer
        reincarnationTimer = _phCtx.reincarnationTimer
        searchingTimer = _phCtx.searchingTimer
        terminalDefeatPending = _phCtx.terminalDefeatPending
        defeatByTimeout = _phCtx.defeatByTimeout
        battleActive = _phCtx.battleActive
        pendingReincarnation = _phCtx.pendingReincarnation
        bgTransAnim = _phCtx.bgTransAnim
        regenAccum = _phCtx.regenAccum
        enemies = _phCtx.enemies
        enemyQueue = _phCtx.enemyQueue
        maxStageId_ = _phCtx.maxStageId_
        stageName = _phCtx.stageName
        isFirstClear = _phCtx.isFirstClear
        currentStageId = _phCtx.currentStageId
        return
    end
    defeatTimer = _phCtx.defeatTimer
    reincarnationTimer = _phCtx.reincarnationTimer
    searchingTimer = _phCtx.searchingTimer
    terminalDefeatPending = _phCtx.terminalDefeatPending
    defeatByTimeout = _phCtx.defeatByTimeout
    battleActive = _phCtx.battleActive
    pendingReincarnation = _phCtx.pendingReincarnation
    bgTransAnim = _phCtx.bgTransAnim
    regenAccum = _phCtx.regenAccum
    enemies = _phCtx.enemies
    enemyQueue = _phCtx.enemyQueue
    maxStageId_ = _phCtx.maxStageId_
    stageName = _phCtx.stageName

    -- 暂停已由 Phases 消费；胜利行军是停战后的真实时钟阶段，不能放在
    -- battleActive 守卫后，也不能再触发一次胜负/挂机寻怪/攻击逻辑。
    if victoryMarch then
        BattleEffects.update(dt)
        updateCardAnims(dt)
        updateFloatingTexts(dt)
        updateHitFlashes(dt)
        SpeechBubble.update(dt)
        bgAnimTimer = bgAnimTimer + dt
        if bgTransAnim then
            bgTransAnim.timer = bgTransAnim.timer + dt
            if bgTransAnim.timer >= (bgTransAnim.duration or BG_TRANS_DURATION) then
                bgTransAnim = nil
            end
        end
        _navLogic.tickVictoryMarch(dt)
        return
    end
    if not battleActive then return end

    local logicDt = BattleScene.getBattleLogicDt(dt)

    -- 首通战斗限时：超时自动失败（与全灭同逻辑）
    if isFirstClear and firstClearTimeLeft then
        firstClearTimeLeft = firstClearTimeLeft - logicDt
        if firstClearTimeLeft <= 0 then
            firstClearTimeLeft = 0
            StageBerserk.exit()
            settleWaveEfficiency()
            print("[BattleScene] 首通战斗超时，自动失败")
            if getStageConfig().isTerminalTemple(currentStageId) then
                if defeatTimer == nil then
                    defeatTimer = 0
                    battleActive = false
                    terminalDefeatPending = true
                    defeatByTimeout = true
                end
            elseif defeatTimer == nil then
                defeatTimer = 0
                battleActive = false
                defeatByTimeout = true
                if onAllDeadCallback then onAllDeadCallback() end
            end
            return
        end
    end

    -- first-clear berserk timer
    if StageBerserk.isActive() then
        StageBerserk.update(logicDt, enemies, allies)
    end

    -- 战斗超时增伤：累计本场时长，每帧回写全局伤害倍率（敌我双方同时生效）
    battleTimeoutElapsed = battleTimeoutElapsed + logicDt
    local _toMult = BattleTimeout.calcMult(battleTimeoutElapsed)
    local _bcs = BattleCombat.mountedState()
    if _bcs and _bcs.ctx then
        _bcs.ctx.globalDmgMult = _toMult
    end

    ART.update(logicDt, allies)
    -- ---- 敌人死亡处理 / 己方阵亡紧凑 / 胜负判定（委托 BattleCasualty） ----
    local _casCtx = {
        enemies = enemies, allies = allies, enemyQueue = enemyQueue,
        getCardCX = getCardCX, getAliveUnits = getAliveUnits, syncUnitHp = syncUnitHp,
        RESPAWN_DELAY = RESPAWN_DELAY, reinforceCdByList = reinforceCdByList,
        ENEMY_CARD_CY = ENEMY_CARD_CY, ALLY_CARD_CY = ALLY_CARD_CY,
        currentStageId = currentStageId, stageName = stageName, getStageConfig = getStageConfig,
        waveKillCount = waveKillCount, waveGoldEarned = waveGoldEarned, waveExpEarned = waveExpEarned,
        onEnemyKillCallback = onEnemyKillCallback, onEnemyDropCallback = onEnemyDropCallback,
        onFirstClearCallback = onFirstClearCallback, onAllDeadCallback = onAllDeadCallback,
        stageKillCount = stageKillCount_, isFirstClear = isFirstClear, clearedStages = clearedStages,
        dropLuck = dropLuck_,
        reincarnationTimer = reincarnationTimer, battleActive = battleActive,
        searchingTimer = searchingTimer, defeatTimer = defeatTimer,
        terminalDefeatPending = terminalDefeatPending, defeatByTimeout = defeatByTimeout,
        settleWaveEfficiency = settleWaveEfficiency, resetWaveTimers = resetWaveTimers,
        nextStage = BattleScene.nextStage,
        beginVictoryMarch = BattleScene.beginVictoryMarch,
    }
    local stageIdBeforeCas = currentStageId
    local _casConsumed = BattleCasualty.process(_casCtx, logicDt)
    waveKillCount = _casCtx.waveKillCount
    waveGoldEarned = _casCtx.waveGoldEarned
    waveExpEarned = _casCtx.waveExpEarned
    -- 首通胜利会在 process 内 nextStage/loadStage，新关击杀进度已清零。
    -- 不能再用本帧开战前的 stageKillCount 写回，否则新关百分比沿用上一关。
    if currentStageId ~= stageIdBeforeCas then
        print(string.format("[BattleScene] 新关进度已重置: %s -> %s kill=%d/%d",
            tostring(stageIdBeforeCas), tostring(currentStageId),
            stageKillCount_, stageEnemyTotal_))
    else
        stageKillCount_ = _casCtx.stageKillCount
    end
    -- Nav 可能在胜利回调中开始行军或直接加载新关（最高末关/跳过终焉）。
    -- ctx 属于旧战斗，不能覆盖停战状态或新关从账本派生的首通状态。
    if currentStageId == stageIdBeforeCas then
        isFirstClear = _casCtx.isFirstClear
        reincarnationTimer = _casCtx.reincarnationTimer
        battleActive = victoryMarch == nil and _casCtx.battleActive
        searchingTimer = _casCtx.searchingTimer
        defeatTimer = _casCtx.defeatTimer
        terminalDefeatPending = _casCtx.terminalDefeatPending
        defeatByTimeout = _casCtx.defeatByTimeout
    end
    if _casConsumed then return end

    -- ---- 攻击进度 / DOT HOT / 天赋计时 / 护盾回血（委托 BattleSceneTick） ----
    local _tickCtx = {
        enemies = enemies, allies = allies, isFirstClear = isFirstClear,
        regenAccum = regenAccum,
        DEFAULT_ALLY_INTERVAL = DEFAULT_ALLY_INTERVAL,
        DEFAULT_ENEMY_INTERVAL = DEFAULT_ENEMY_INTERVAL,
        ALLY_CARD_CY = ALLY_CARD_CY, ENEMY_CARD_CY = ENEMY_CARD_CY, DESIGN_W = DESIGN_W,
        getLiveAttackInterval = getLiveAttackInterval,
        performAttack = performAttack,
        checkEnemiesCorruption = checkEnemiesCorruption,
        dealDamageToUnit = dealDamageToUnit,
        syncUnitHp = syncUnitHp,
        getCardCX = getCardCX,
        addFloatingText = addFloatingText,
    }
    BattleSceneTick.tick(_tickCtx, logicDt)
    regenAccum = _tickCtx.regenAccum

    -- ---- 投射物 / 连击：与伤害时机绑定，必须跟随 logicDt ----
    ProjectileSystem.update(logicDt)
    updateComboQueue(logicDt)

    -- ---- 纯视觉层：用真实 dt，2 倍速时不叠加特效/飘字算力 ----
    BattleEffects.update(dt)
    updateCardAnims(dt)
    updateFloatingTexts(dt)
    updateHitFlashes(dt)
    SpeechBubble.update(dt)

    -- ---- 诊断：周期性完整性检查（真实时间，避免倍速下扫描过频） ----
    Diag.update(dt, allies, enemies)

    -- ---- 更新背景持续动效 ----
    bgAnimTimer = bgAnimTimer + dt

    -- ---- 更新背景过渡动画 ----
    if bgTransAnim then
        bgTransAnim.timer = bgTransAnim.timer + dt
        local duration = bgTransAnim.duration or BG_TRANS_DURATION
        if bgTransAnim.timer >= duration then
            bgTransAnim = nil
        end
    end
end

-- ======================== 外部接口 ========================
--- 设置关卡名
function BattleScene.setStageName(name)
    stageName = name
end
--- 切换地图背景（后续随关卡变化调用）
function BattleScene.setMapBackground(vg, path)
    if imgMap >= 0 then
        nvgDeleteImage(vg, imgMap)
        imgMap = -1
    end
    -- [启动优化] 只记路径，首次 draw 前再解码：loadStage 在启动队列内执行，
    -- 同步解码数 MB 关卡地图会撑爆单帧预算（预览判引擎异常，加载条 97-98% 卡死）
    pendingMapBgPath_ = path
end
--- 设置敌方单位列表（DebugPanel 用）
function BattleScene.setEnemies(list)
    return getAllyLifecycle().setEnemies(list)
end
--- 设置己方单位列表（DebugPanel 用）
function BattleScene.setAllies(list)
    return getAllyLifecycle().setAllies(list)
end
--- 获取默认攻击间隔（供 DebugPanel 等外部模块使用）
function BattleScene.getDefaultAllyInterval()
    return DEFAULT_ALLY_INTERVAL
end

function BattleScene.getDefaultEnemyInterval()
    return DEFAULT_ENEMY_INTERVAL
end
--- 获取己方场地上限
function BattleScene.getMaxFieldUnits()
    return MAX_FIELD_ALLIES
end
--- 获取当前己方单位列表（引用，非副本）
function BattleScene.getAllies()
    return allies
end
--- 获取当前敌方单位列表（引用，非副本）[修复] BattleTriPage 依赖此接口，此前缺失导致每帧 nil 调用
function BattleScene.getEnemies()
    return enemies
end
--- 获取当前关卡 ID [修复] BattleTriPage 依赖（此前仅暴露 getCurrentStageId）
function BattleScene.getStageId()
    return currentStageId
end
--- 三行第一队通关后，只同步主线关卡号，不重开 BattleScene 自己的战斗。
--- 否则存档已到下一关，BattleScene 仍停在旧关，下一帧会把第一队拉回去。
---@param stageId number
function BattleScene.adoptStageProgress(stageId)
    stageId = tonumber(stageId)
    if not stageId or not getStageConfig().getStage(stageId) then return end
    local resourceStage = SC.isResourceStage(stageId)
    if not resourceStage and stageId > maxStageId_ then
        maxStageId_ = stageId
    end
    currentStageId = stageId
    isFirstClear = not resourceStage and not (clearedStages[stageId] or clearedStages[tostring(stageId)])
end
--- 三行普通关通关：三队共享解锁与首通账本，各队保留独立的当前关卡。
--- 一队追赶已被其他队通关的节点时仍要同步当前关，不能被奖励去重拦住。
---@param stageId number
---@param teamIdx number
---@return boolean firstClear
function BattleScene.completeTriStageClear(stageId, teamIdx)
    local id = tonumber(stageId)
    if not id or id % 1 ~= 0 or not SC.getStage(id) or SC.isTerminalTemple(id)
        or not teamIdx or teamIdx % 1 ~= 0 or teamIdx < 1 or teamIdx > 3 then
        return false
    end
    local ClientDispatcher = require("runtime.ClientDispatcher")
    local battle = ClientDispatcher.get("battle")
    if SC.isResourceStage(id) then
        local DC = require("config.DungeonConfig")
        local dungeon = ClientDispatcher.get("dungeon")
        if type(dungeon) ~= "table" or type(battle) ~= "table" then return false end
        if not DC.isStageUnlocked(id, battle, dungeon) then return false end
        local dungeonId, floor = DC.decodeStageId(id)
        local sub = dungeon[dungeonId]
        if type(sub) ~= "table" then sub = { floor = 1, cleared = {} }; dungeon[dungeonId] = sub end
        if type(sub.cleared) ~= "table" then sub.cleared = {} end
        local wasCleared = floor <= DC.getHighestClearedFloor(sub, dungeonId)
        sub.cleared[tostring(floor)] = true
        sub.floor = math.min(DC.MAX_FLOOR[dungeonId], math.max(tonumber(sub.floor) or 1, floor + 1))
        local nextId = SC.getNextStageId(id) or id
        if type(battle.teamStageIds) ~= "table" then battle.teamStageIds = {} end
        battle.teamStageIds[tostring(teamIdx)] = nextId
        if teamIdx == 1 then
            BattleScene.adoptStageProgress(nextId)
            battle.currentStageId, battle.battleMode = nextId, "idle"
        end
        if not wasCleared then
            print(string.format("[BattleScene] 队%d 资源通关 %s 层%d，主线进度保持%s", teamIdx, dungeonId, floor, tostring(battle.maxStageId)))
        end
        ClientDispatcher.notifySubscribers("dungeon")
        ClientDispatcher.notifySubscribers("battle")
        require("boot.StandaloneSave").Flush()
        return false -- 资源奖励按击杀发放，不触发主线首次通关回调。
    end
    local savedCleared = type(battle) == "table" and battle.clearedStages or {}
    savedCleared = savedCleared or {}
    local wasCleared = clearedStages[id] == true or clearedStages[tostring(id)] == true
        or savedCleared[id] == true or savedCleared[tostring(id)] == true
    clearedStages[id] = true
    -- 末关跳过规则与Driver/存档预约同源，未通终焉仍停在普通末关。
    local nextId = SC.getNextStageId(id)
    local terminalCleared = nextId and (clearedStages[nextId] == true or clearedStages[tostring(nextId)] == true
        or savedCleared[nextId] == true or savedCleared[tostring(nextId)] == true)
    local savedMax = type(battle) == "table" and tonumber(battle.maxStageId) or 0
    local progressId = SC.resolveAutoAdvance(id, math.max(maxStageId_, savedMax or 0),
        nextId and { [nextId] = terminalCleared } or {})
    maxStageId_ = math.max(maxStageId_, savedMax or 0, progressId)
    if teamIdx == 1 then
        BattleScene.adoptStageProgress(progressId)
    end
    if type(battle) == "table" then
        battle.clearedStages = savedCleared
        savedCleared[tostring(id)] = true
        battle.maxStageId = maxStageId_
        if teamIdx == 1 then
            battle.currentStageId = currentStageId
            battle.battleMode = isFirstClear and "firstClear" or "idle"
        end
    end
    print(string.format("[BattleScene] 队%d 通关 stage=%d first=%s current=%s max=%s",
        teamIdx, id, tostring(not wasCleared), tostring(currentStageId), tostring(maxStageId_)))
    if not wasCleared then BattleScene.onFirstClear(id, teamIdx) end
    -- 直接通知镜像/UI，不通过整表回灌重载其他正在战斗的队伍。
    if type(battle) == "table" then
        ClientDispatcher.notifySubscribers("battle")
        require("boot.StandaloneSave").Flush()
    end
    return not wasCleared
end
--- [终焉协同] 三队共享生命池打空后调用：等价主线「终焉胜利 → 轮回」。
--- 奖励去重：只有该终焉关此前未通关时才触发首通回调（重打已通关的终焉
--- 不再重复发 fcExp/首通奖励，与主线 BattleCasualty 的 isFirstClear 门槛一致）。
function BattleScene.completeTriTerminal(stageId)
    if not SC.isTerminalTemple(stageId) or currentStageId ~= stageId then return false end
    local targetId = SC.getReincarnationTarget(SC.getDifficulty(stageId))
    if not targetId then return false end
    local savedBattle = require("runtime.ClientDispatcher").get("battle")
    local savedCleared = type(savedBattle) == "table" and savedBattle.clearedStages or {}
    savedCleared = type(savedCleared) == "table" and savedCleared or {}
    local wasFirstClear = not (clearedStages[stageId] or clearedStages[tostring(stageId)]
        or savedCleared[stageId] or savedCleared[tostring(stageId)])
    clearedStages[stageId] = true
    maxStageId_ = math.max(maxStageId_, targetId)
    loadStage(targetId, true, require("ui.battle.tri.BattleTriPage").isOpen())
    for _, u in ipairs(allies) do resetAllyUnit(u) end
    startBattleTalents()
    BottomNav.setAllLocked(false)
    require("systems.GameBGM").setScene("battle")
    if onStageChangedCallback then onStageChangedCallback(targetId) end
    local ClientDispatcher = require("runtime.ClientDispatcher")
    local battle = ClientDispatcher.get("battle")
    if type(battle) == "table" then
        battle.currentStageId = targetId
        battle.maxStageId = math.max(tonumber(battle.maxStageId) or 0, targetId)
        battle.clearedStages = battle.clearedStages or {}
        battle.clearedStages[tostring(stageId)] = true
        local targetCleared = battle.clearedStages[tostring(targetId)] == true
        battle.battleMode = targetCleared and "idle" or "firstClear"
        require("boot.StandaloneSave").Flush()
    end
    if wasFirstClear and onFirstClearCallback then onFirstClearCallback(stageId) end
    return true
end
--- 触发敌方击杀回调 [修复] BattleTriPage 三队战斗驱动依赖（与主战斗内部调用同构）
---@param data table { expReward, goldReward, allyCount, expMult, heroIds, stageId }
function BattleScene.onEnemyKill(data)
    if onEnemyKillCallback then
        onEnemyKillCallback(data)
    end
end
--- 获取当前关卡敌方场地上限
function BattleScene.getMaxFieldEnemies()
    return getStageMaxFieldEnemies()
end
--- 获取当前关卡 ID
function BattleScene.getCurrentStageId()
    return currentStageId
end
--- [Standalone 状态同步] 本地最远抵达关卡（Client 模式以服务端推送为准）
---@return number
function BattleScene.getMaxStageId()
    return maxStageId_
end
--- 当关击杀进度（死亡怪/总怪）；挂机模式返回 nil（进度无意义）
---@return number|nil killed
---@return number total
function BattleScene.getStageKillProgress()
    if not isFirstClear then return nil end
    if stageEnemyTotal_ <= 0 then return nil end
    if stageKillCount_ > stageEnemyTotal_ then stageKillCount_ = stageEnemyTotal_ end
    return stageKillCount_, stageEnemyTotal_
end
--- [Standalone 状态同步] 本地已通关表（key 可能为 number，写入状态前需 tostring）
---@return table
function BattleScene.getClearedStages()
    return clearedStages
end
--- [三行并行] 选关页面: 跳转到指定关卡（仅允许 ≤ 已解锁最大关卡）
---@param opts? { deferEnter?: boolean } 三行由真实Driver发送入场通知
function BattleScene.gotoStage(stageId, opts)
    if not _navLogic then bindBattleExtracts() end
    return _navLogic.gotoStage(stageId, opts)
end
--- 当前是否处于终焉神殿关卡
function BattleScene.isInTerminalTemple()
    return getStageConfig().isTerminalTemple(currentStageId)
end
--- 实际执行进入终焉神殿（确认后调用）
local function doEnterTerminalTemple(nextId)
    if not _navLogic then bindBattleExtracts() end
    return _navLogic.doEnterTerminalTemple(nextId)
end
--- 前进到下一关
function BattleScene.nextStage()
    if not _navLogic then bindBattleExtracts() end
    return _navLogic.nextStage()
end

function BattleScene.beginMapMarch(duration)
    bgTransAnim = { timer = 0, zoomTarget = BG_ZOOM_FWD_TARGET, duration = duration or 2.0 }
end

function BattleScene.beginVictoryMarch()
    if not _navLogic then bindBattleExtracts() end
    return _navLogic.beginVictoryMarch()
end
--- 后退到上一关
function BattleScene.prevStage()
    if not _navLogic then bindBattleExtracts() end
    return _navLogic.prevStage()
end
--- 处理设计空间内的点击（由 Standalone 调用）
---@param dx number 设计空间X (0~1080)
---@param dy number 设计空间Y (0~2400)
---@return boolean 是否命中了按钮
function BattleScene.handleInput(dx, dy)
    -- 副本结算面板打开时，拦截所有输入
    if BattleResultPanel.isOpen() then
        BattleResultPanel.handleInput(dx, dy)
        return true
    end

    -- 确认弹窗打开时，拦截所有输入
    if TerminalConfirmDialog.handleInput(dx, dy, doEnterTerminalTemple) then
        return true
    end

    -- 扫荡弹窗（已打开时拦截所有输入；入口按钮点击）
    if SweepDialog.handleInput(dx, dy) then return true end
    -- 战斗统计面板（已打开时拦截所有输入，需在按钮判定之前）
    if DamageStatsPanel.handleInput(dx, dy) then return true end
    if SweepDialog.handleButtonInput(dx, dy) then return true end
    if DamageStatsPanel.handleButtonInput(dx, dy) then return true end

    -- 首通战斗倍速按钮
    if BattleScene.handleSpeedButtonInput(dx, dy) then return true end

    -- 终焉神殿：禁用后退和前进
    local isTerminalInput = getStageConfig().isTerminalTemple(currentStageId)

    -- 后退按钮区域（挂机模式禁用）
    if isFirstClear and dx >= NAV.BACK_BG_CX - NAV.BACK_BG_W * 0.5 and dx <= NAV.BACK_BG_CX + NAV.BACK_BG_W * 0.5
       and dy >= NAV.BACK_BG_CY - NAV.BACK_BG_H * 0.5 and dy <= NAV.BACK_BG_CY + NAV.BACK_BG_H * 0.5 then
        if not isTerminalInput then
            BattleScene.prevStage()
        end
        return true
    end

    -- 前进按钮区域（仅挂机模式可用）
    if not isFirstClear and dx >= NAV.FWD_BG_CX - NAV.FWD_BG_W * 0.5 and dx <= NAV.FWD_BG_CX + NAV.FWD_BG_W * 0.5
       and dy >= NAV.FWD_BG_CY - NAV.FWD_BG_H * 0.5 and dy <= NAV.FWD_BG_CY + NAV.FWD_BG_H * 0.5 then
        if not isTerminalInput then
            BattleScene.nextStage()
        end
        return true
    end

    return false
end
--- 重新加载当前关卡（DebugPanel 用）
--- 注册敌方击杀回调
--- callback(data): data = { expReward, goldReward, allyCount, expMult, heroIds }
---   expReward  = 怪物基础经验（已含品质倍率）
---   goldReward = 怪物基础金币（已含品质倍率）
---   allyCount  = 当前上场远征队员数量
---   expMult    = 远征队员数量经验倍率
---   heroIds    = 上场远征队员 heroId 列表
---@param callback function|nil
function BattleScene.setOnEnemyKill(callback)
    onEnemyKillCallback = callback
end
--- 注册首通回调（关卡首次通关时触发）
---@param callback function|nil  function(clearedStageId)
function BattleScene.setOnFirstClear(callback)
    onFirstClearCallback = callback
end
--- 三行战斗通关后复用首通奖励弹窗。
---@param clearedStageId number
---@param teamIdx number|nil 缺省为一队；其他队只推进共享解锁，不切一队当前关
function BattleScene.onFirstClear(clearedStageId, teamIdx)
    if onFirstClearCallback then
        onFirstClearCallback(clearedStageId, teamIdx)
    end
end
--- 注册关卡加载完成回调（每次 loadStage 结束时触发）
---@param callback function|nil  function(stageId, isFirstClear)
function BattleScene.setOnStageLoaded(callback)
    onStageLoadedCallback = callback
end
--- 注册关卡切换回调（前进/后退时触发）
---@param callback function|nil  function(newStageId)
function BattleScene.setOnStageChanged(callback)
    onStageChangedCallback = callback
end
--- 注册敌方掉落回调（每次击杀敌人时触发）
--- callback(data): data = { stageId, enemyCX, enemyCY, isFirstClear }
---@param callback function|nil
function BattleScene.setOnEnemyDrop(callback)
    onEnemyDropCallback = callback
end
--- 注册轮回回调（终焉神殿战斗结束轮回时触发）
--- callback(data): data = { fromDifficulty, toDifficulty, newStageId }
---@param callback function|nil
function BattleScene.setOnReincarnate(callback)
    onReincarnateCallback = callback
end
--- 注册全体阵亡回调（非终焉神殿全员阵亡战败时触发，每次阵亡仅触发一次）
---@param callback function|nil
function BattleScene.setOnAllDead(callback)
    onAllDeadCallback = callback
end
--- 完成轮回：外部动画（IntroCutscene）播放结束后调用，执行实际的关卡加载
function BattleScene.completeReincarnation()
    if not _navLogic then bindBattleExtracts() end
    return _navLogic.completeReincarnation()
end
--- 从服务端推送的战斗数据恢复状态
---@param data table  { currentStageId, maxStageId, clearedStages, autoBattle }
function BattleScene.setBattleData(data)
    if not _dataRestore then bindBattleExtracts() end
    return _dataRestore.setBattleData(data)
end
--- 轻量级属性刷新：英雄升级后更新场上 ally 的属性，不重置战斗状态
function BattleScene.refreshAllyStats()
    return getAllyLifecycle().refreshAllyStats()
end
--- [Debug] 立即通关当前关卡（杀死所有敌人 + 清空队列，让胜利检测自然触发）
function BattleScene.debugInstantClear()
    return getAllyLifecycle().debugInstantClear()
end
--- [DEBUG] 跳转到指定关卡（调试面板用，同步本地进度；持久化由 GM_JUMP_STAGE 负责）
---@param stageId number 目标关卡 ID
function BattleScene.debugJumpToStage(stageId)
    return getAllyLifecycle().debugJumpToStage(stageId)
end
--- 重新加载当前关卡
---@param opts? { startSearching?: boolean }  startSearching=true 时以"寻怪中"进度条启动（首次进入用）
function BattleScene.reloadStage(opts)
    return getAllyLifecycle().reloadStage(opts)
end
--- 重置战斗场景到初始默认状态（清除存档后调用）
function BattleScene.resetToDefault()
    victoryMarch = nil
    return getAllyLifecycle().resetToDefault()
end
--- 暂停战斗（切离战斗页面时调用）
function BattleScene.pause()
    if not isPaused then
        isPaused = true
        print("[BattleScene] 战斗暂停")
    end
end
--- 恢复战斗（切回战斗页面时调用）
function BattleScene.resume()
    if isPaused then
        isPaused = false
        print("[BattleScene] 战斗恢复")
    end
end
--- 恢复主战斗上下文（副本/竞技场关闭后调用，无论是否 paused）
--- 同时恢复 BattleCombat 上下文 + TAL/TM 天赋系统
function BattleScene.restoreContext()
    setupBattleCombatContext()
    startBattleTalents()
    print("[BattleScene] restoreContext - 主战斗上下文已恢复 (allies=" .. #allies .. " enemies=" .. #enemies .. ")")
end
--- 查询暂停状态
function BattleScene.isPaused()
    return isPaused
end

-- ======================== 长按怪物信息（委托 MonsterInfoPopup） ========================
--- 按下开始（由 ClientInput dispatchDragBegin 调用）
function BattleScene.handlePressBegin(dx, dy)
    MonsterInfoPopup.handlePressBegin(dx, dy)
end
--- 按下结束（由 ClientInput dispatchDragEnd 调用）
function BattleScene.handlePressEnd()
    MonsterInfoPopup.handlePressEnd()
end

-- 只包装业务操作，getter不碰挂载；保留主线Lifecycle/Nav/Restore拆分和函数签名。
BattleMountScope.wrap(BattleScene, {
    "init", "draw", "update", "setEnemies", "setAllies", "refreshAllyStats", "restoreContext",
    "setBattleData", "reloadStage", "resetToDefault", "debugJumpToStage", "debugInstantClear",
    "gotoStage", "nextStage", "prevStage", "completeReincarnation", "completeTriTerminal",
    "completeTriStageClear", "handleInput", "beginVictoryMarch",
}, true)

return BattleScene

