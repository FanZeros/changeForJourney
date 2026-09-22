-- ============================================================================
-- BattleScene - 战斗场景 UI
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- ============================================================================

local AD  = require("systems.AttributeDef")
local TM  = require("systems.ThreatManager")
local SEM = require("systems.StatusEffectManager")
local TAL = require("systems.TalentManager")
local RCH = require("systems.RelicConditionHandler")
local ART = require("systems.ArtifactRuntime")
local MAS = require("systems.MapAffixSystem")
local SC  = require("config.StageConfig")

local BattleCombat      = require("ui.BattleCombat")
local StageBerserk     = require("ui.StageBerserk")
local BattleDraw        = require("ui.BattleDraw")
local BattleEffects     = require("ui.BattleEffects")
local ProjectileSystem  = require("ui.ProjectileSystem")
local LootBox           = require("ui.LootBox")
local SweepDialog       = require("ui.SweepDialog")
local DamageStatsPanel  = require("ui.DamageStatsPanel")
local SpeechBubble      = require("ui.SpeechBubble")
local BottomNav         = require("ui.BottomNav")

local Diag = require("systems.BattleDiag")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化] 地图压暗滤镜

local BattleResultPanel = require("ui.BattleResultPanel")
local OfflineCalc = require("systems.OfflineCalc")
local TerminalConfirmDialog = require("ui.TerminalConfirmDialog")
local MonsterInfoPopup = require("ui.MonsterInfoPopup")
local BattleSpeed = require("ui.BattleSpeed")
local BattleEnemySpawn = require("ui.BattleEnemySpawn")
local BattleTransitionHud = require("ui.BattleTransitionHud")
local BattleStageFlow = require("ui.BattleStageFlow")
local BattleAllyReset = require("ui.BattleAllyReset")
local BattleStageNav = require("ui.BattleStageNav")
local BattleCasualty = require("ui.BattleCasualty")
local BattleStageLoad = require("ui.BattleStageLoad")
local BattleSceneTick = require("ui.BattleSceneTick")
local BattleScenePhases = require("ui.BattleScenePhases")
local BattleStageNavLogic = require("ui.BattleStageNavLogic")
local BattleDataRestore = require("ui.BattleDataRestore")

local BattleScene = {}
BattleScene.GameState = require("core.GameState")

-- 己方场地上限（固定）
local MAX_FIELD_ALLIES = 5

-- ======================== 常量 ========================

local DESIGN_W = 1080

-- 地图背景（后续随关卡变化，参见 setMapBackground()）
local MAP_W, MAP_H = 1080, 2400
local MAP_CX, MAP_CY = 540, 1200

-- 卡片尺寸（BattleDraw/BattleCombat 各自有副本，此处仅供本文件布局引用）
local CARD_W, CARD_H = 198, 438

-- 敌方战场阴影
local ENEMY_SHADOW_CX, ENEMY_SHADOW_CY = 540, 804
local ENEMY_SHADOW_W, ENEMY_SHADOW_H   = 1080, 556

-- 己方战场阴影
local ALLY_SHADOW_CX, ALLY_SHADOW_CY = 540, 1760
local ALLY_SHADOW_W, ALLY_SHADOW_H   = 1080, 556

-- 敌方卡片组 基准坐标（单卡时的 X=540）
local ENEMY_CARD_CY      = 804
local ENEMY_TAG_OFFSET_Y  = -215
local ENEMY_NAME_OFFSET_Y = 102
local ENEMY_HP_BG_OFFSET_Y = 165
local ENEMY_HP_VAL_OFFSET_Y = 147
local ENEMY_ATK_BG_OFFSET_Y = 181
local ENEMY_LVL_OFFSET_Y = 215

-- 己方卡片组 基准坐标
local ALLY_CARD_CY       = 1760
local ALLY_TAG_OFFSET_Y   = -215
local ALLY_NAME_OFFSET_Y  = 85
local ALLY_HP_BG_OFFSET_Y = 153
local ALLY_HP_VAL_OFFSET_Y = 135
local ALLY_ATK_BG_OFFSET_Y = 181
local ALLY_LVL_OFFSET_Y  = 215

-- 关卡名 / 按钮坐标（合并到 table 减少 local 占用）
local NAV = BattleStageNav.NAV

-- (职业标签 TAG_SIZE / HP_BAR / ATK_BAR 已移至 BattleDraw)

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
local imgAtkBg    = -1
local imgAtkFill  = -1
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

-- [EnemyGuard] 检测 enemies 列表是否被英雄数据污染（一次性报警）
local _enemyGuardFired = false
local function checkEnemiesCorruption(tag)
    if _enemyGuardFired then return end
    for i, u in ipairs(enemies) do
        if u.heroId and not u.monsterId then
            _enemyGuardFired = true
            local parts = { "[EnemyGuard] CORRUPTION_DETECTED tag=" .. tag
                .. " enemies contains HERO data! len=" .. #enemies }
            for j, e in ipairs(enemies) do
                parts[#parts + 1] = string.format("  [%d] heroId=%s monsterId=%s instId=%s hp=%s name=%s",
                    j, tostring(e.heroId), tostring(e.monsterId),
                    tostring(e.instanceId), tostring(e.hp), tostring(e.name))
            end
            parts[#parts + 1] = "  allies_len=" .. #allies
            for j, a in ipairs(allies) do
                parts[#parts + 1] = string.format("  ally[%d] heroId=%s hp=%s name=%s",
                    j, tostring(a.heroId), tostring(a.hp), tostring(a.name))
            end
            parts[#parts + 1] = "  enemies_ref=" .. tostring(enemies) .. " allies_ref=" .. tostring(allies)
            print(table.concat(parts, "\n"))
            return true
        end
    end
    return false
end

-- 当前关卡 ID
local currentStageId = 0101

local function getStageConfig()
    return require("shared.StageProvider").GetForServer(require("ui.PlayerInfoPanel").getServerId())
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

-- 挂机收益缓存（每分钟）—— 直接由 OfflineCalc 统一公式计算
local cachedGoldPerMin = 0
local cachedExpPerMin  = 0

-- 波次效率测量（纯本地，用于战斗统计，不参与收益显示）
local waveStartTime = nil      -- 本波次开始时间（time.elapsedTime）
local waveKillCount = 0        -- 本波次击杀数
local waveGoldEarned = 0       -- 本波次获得金币
local waveExpEarned = 0        -- 本波次获得经验

-- (工具绘制函数 drawImageCentered/drawImageMirrored/drawTextStroke/drawProgressBar 已移至 BattleDraw)
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
    return BattleSpeed.getMaxUnlocked(getStageConfig().getDifficulty(currentStageId))
end

function BattleScene.isSpeedButtonVisible()
    return isFirstClear and battleActive and not isPaused
        and BattleScene.getMaxUnlockedBattleSpeed() > 1.0
        and not BattleResultPanel.isOpen()
        and not TerminalConfirmDialog.isOpen()
        and not SweepDialog.isOpen() and not DamageStatsPanel.isOpen()
        and searchingTimer == nil and defeatTimer == nil and reincarnationTimer == nil
end

function BattleScene.getBattleLogicDt(dt)
    local logicDt, speed = BattleSpeed.getLogicDt(
        dt, BattleScene.battleSpeed, BattleScene.getMaxUnlockedBattleSpeed(),
        BattleScene.isSpeedButtonVisible())
    BattleScene.battleSpeed = speed
    return logicDt
end

local function getLiveAttackInterval(unit, fallback)
    if unit and unit.attrs and unit.attrs.getActualInterval then
        local attrInterval = unit.attrs:getActualInterval()
        local cachedAttrInterval = unit._lastAttrInterval
        local currentInterval = unit.atkInterval
        if not currentInterval or not cachedAttrInterval
            or math.abs(currentInterval - cachedAttrInterval) <= 0.0001 then
            unit.atkInterval = attrInterval
        end
        unit._lastAttrInterval = attrInterval
    end
    return unit.atkInterval or fallback
end

function BattleScene.getSpeedText()
    return BattleSpeed.getSpeedText(BattleScene.battleSpeed)
end

function BattleScene.drawSpeedButton(vg)
    BattleSpeed.draw(vg, BattleScene.imgSpeedIcon, BattleScene.battleSpeed, BattleScene.isSpeedButtonVisible())
end

function BattleScene.handleSpeedButtonInput(dx, dy)
    if not BattleScene.isSpeedButtonVisible() then return false end
    if not BattleSpeed.hitTest(dx, dy) then return false end
    BattleScene.battleSpeed = BattleSpeed.cycle(BattleScene.battleSpeed, BattleScene.getMaxUnlockedBattleSpeed())
    print("[BattleScene] 首通战斗倍速切换: " .. BattleScene.getSpeedText())
    return true
end

-- ======================== 属性快照隔离（委托 BattleAllyReset） ========================
local function createSnapshot(u)
    BattleAllyReset.createSnapshot(u)
end

local function resetAllyUnit(u)
    BattleAllyReset.resetAllyUnit(u, allies, syncUnitHp)
end

-- BattleDraw 本地别名
---@type fun(vg, units, baseCY, tagOffY, nameOffY, hpBgOffY, hpValOffY, atkBgOffY, lvlOffY, tagImg, isAllyGroup)
local drawCardGroup       = BattleDraw.drawCardGroup
---@type fun(vg)
local drawFloatingTexts   = BattleDraw.drawFloatingTexts
---@type fun(vg, imgBg, imgFill, cx, cy, bgW, bgH, padding, progress)
local drawProgressBar     = BattleDraw.drawProgressBar

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
    local battleSnapshot = {
        currentStageId = currentStageId,
        maxStageId     = maxStageId_,
        clearedStages  = clearedStages,
        battleMode     = isFirstClear and "firstClear" or "idle",
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

local function startBattleTalents()
    BattleStageFlow.startBattleTalents(allies, enemies)
end

--- 恢复主战斗的 BattleCombat 上下文（副本/竞技场关闭后必须调用）
--- 将 ctx.getAllies / ctx.getEnemies 重新指向主战斗的 allies/enemies
local function setupBattleCombatContext()
    BattleCombat.setContext({
        getAllies    = function() return allies end,
        getEnemies  = function() return enemies end,
        ALLY_CARD_CY  = ALLY_CARD_CY,
        ENEMY_CARD_CY = ENEMY_CARD_CY,
        -- 暴击回调：触发暴击台词
        onCrit = function(attacker, isAlly)
            if isAlly then
                SpeechBubble.trigger(attacker, "crit")
            end
        end,
        onAttackHit = function(attacker, target, atkCX, atkCY, tgtCX, tgtCY, result, applyHit)
            local hasHeroEffect = attacker.heroId
                                  and ProjectileSystem.hasHeroEffect(attacker.heroId)
            local hasMonsterEffect = attacker.atkEffect
                                     and ProjectileSystem.hasMonsterProjectile(attacker.atkEffect)

            local hitCallback = function()
                if result.category == "healing" and Diag.logEnabled then
                    print(string.format("[HealDiag4] hitCallback FIRED healer=%s target=%s hp=%.0f applyHit=%s",
                        tostring(attacker.name), tostring(target.name), target.hp or -1, tostring(applyHit ~= nil)))
                end
                if applyHit then
                    local ok, err = pcall(applyHit)
                    if not ok then
                        print("[HealDiag4] applyHit ERROR: " .. tostring(err))
                    end
                end
                if result.category ~= "healing" and target.attrs then
                    local armorType = target.attrs.armorType or 1
                    BattleEffects.spawn(armorType, tgtCX, tgtCY)
                end
            end

            local projOpts = result.category == "healing" and { target = target, forceBezier = true } or nil

            if hasHeroEffect then
                ProjectileSystem.spawn(attacker.heroId, atkCX, atkCY, tgtCX, tgtCY, hitCallback, projOpts)
            elseif hasMonsterEffect then
                local isMelee = (attacker.isRanged ~= true)
                ProjectileSystem.spawnByKey(attacker.atkEffect, atkCX, atkCY, tgtCX, tgtCY, hitCallback, isMelee, projOpts)
            else
                hitCallback()
            end
        end,
        onTalentDealDamage = function(attacker, target, tgtCX, tgtCY, pfx, applyDamage, projOpts)
            BattleCombat.onTalentDealDamage(attacker, target, tgtCX, tgtCY, pfx, applyDamage, projOpts, allies, enemies)
        end,
    })
end

-- [卡牌分帧加载] 英雄卡/怪物卡/投射物图，首次进战斗时构建队列，由 update 分帧消化
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
local function loadStage(stageId, skipBattleStart)
    local ctx = {
        currentStageId = currentStageId, stageName = stageName, maxStageId_ = maxStageId_,
        isFirstClear = isFirstClear, idleRangeText_ = idleRangeText_,
        searchingTimer = searchingTimer, defeatTimer = defeatTimer, reincarnationTimer = reincarnationTimer,
        currentChapter = currentChapter, vg_ = vg_,
        enemies = enemies, enemyQueue = enemyQueue, allies = allies,
        stageEnemyTotal_ = stageEnemyTotal_, stageKillCount_ = stageKillCount_,
        _enemyGuardFired = _enemyGuardFired, battleActive = battleActive,
        firstClearTimeLeft = firstClearTimeLeft, onStageLoadedCallback = onStageLoadedCallback,
        clearedStages = clearedStages,
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
    currentChapter = ctx.currentChapter
    enemies = ctx.enemies
    enemyQueue = ctx.enemyQueue
    stageEnemyTotal_ = ctx.stageEnemyTotal_
    stageKillCount_ = ctx.stageKillCount_
    _enemyGuardFired = ctx._enemyGuardFired
    battleActive = ctx.battleActive
    firstClearTimeLeft = ctx.firstClearTimeLeft
end

local _navLogic
local _dataRestore
local function bindBattleExtracts()
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
        isFirstClear = function() return isFirstClear end,
    }
    local function get(key)
        return getters[key]()
    end
    local function set(key, value)
        if key == "searchingTimer" then searchingTimer = value
        elseif key == "defeatTimer" then defeatTimer = value
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
end

-- ======================== Public API ========================

function BattleScene.init(vg)
    vg_ = vg  -- 缓存，供 loadStage 切换地图背景
    -- 地图背景延后到 loadStage / 首次绘制，避免启动解码 1MB+ MAP_1
    currentChapter = 1
    imgShadow   = nvgCreateImage(vg, "image/界面底板/通用面板/UI_YWJM_MAPYY.png", 0)
    -- [卡牌惰性加载] 英雄卡/怪物卡大图改为首次进战斗时加载（ensureBattleCards）
    -- ⚠️ 新增怪物 ID 时必须补充到 ensureBattleCards 的加载清单！
    -- 否则 BattleDraw 会 fallback 到 imgMonsterCards[1]（怪物1的贴图）。
    -- 战斗卡牌改到首次进战斗时分帧加载（见 loadStage → ensureBattleCards）
    imgHpBg     = nvgCreateImage(vg, "image/界面底板/战斗/UI_ZD_HP1.png", 0)
    imgHpFill   = nvgCreateImage(vg, "image/界面底板/战斗/UI_ZD_HPT2.png", 0)
    imgEsFill   = nvgCreateImage(vg, "image/界面底板/战斗/UI_ZD_HPT3.png", 0)
    imgAtkBg    = nvgCreateImage(vg, "image/界面底板/战斗/UI_ZD_GJT1.png", 0)
    imgAtkFill  = nvgCreateImage(vg, "image/界面底板/战斗/UI_ZD_GJT2.png", 0)
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
        imgAtkBg        = imgAtkBg,
        imgAtkFill      = imgAtkFill,
        imgAllyTags     = imgAllyTags,
    })

    -- 初始化战利品箱子
    LootBox.init(vg)

    -- 初始化扫荡弹窗
    SweepDialog.init(vg)
    SweepDialog.onSweep = function()
        require("network.GameAction").sendAction(
            require("shared.Protocol").ACTION_TYPES.SWEEP, {})
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
    if bgTransAnim then
        local t = math.min(bgTransAnim.timer / BG_TRANS_DURATION, 1.0)
        -- 0→1→0 的迈步鼓包，峰值在中点
        local bump = math.sin(t * math.pi)
        local peak = bgTransAnim.zoomTarget or BG_ZOOM_FWD_TARGET
        if peak < 1.0 then
            peak = 2.0 - peak  -- 旧「缩小淡出」值转成放大
        end
        mapScale = 1.0 + (peak - 1.0) * bump
        walkY = -36.0 * bump  -- 同步微微上移，模拟迈步
    end
    -- 裁进设计画布，放大时不溢到邻栏
    nvgSave(vg)
    nvgIntersectScissor(vg, MAP_CX - MAP_W * 0.5, MAP_CY - MAP_H * 0.5, MAP_W, MAP_H)
    DarkIcon.drawDarkScene(vg, imgMap, MAP_CX, MAP_CY + driftY + walkY,
        MAP_W * mapScale, MAP_H * mapScale, 1.0)
    nvgRestore(vg)

    -- 2. 敌方战场阴影
    drawImageCentered(vg, imgShadow, ENEMY_SHADOW_CX, ENEMY_SHADOW_CY,
        ENEMY_SHADOW_W, ENEMY_SHADOW_H, 1.0)

    -- 3a. 地图词缀标签（仅首通模式显示，挂机模式不显示）
    if isFirstClear and MAS.hasAffixes() then
        local affixes = MAS.getActiveAffixes()
        if affixes then
            -- 每个词缀显示一行："词缀名: 简短说明"，从下往上排列
            local lineH = 34
            local bottomY = 468  -- 最后一行Y位置（与剩余敌人Y=525保持57px间距）
            local baseY = bottomY - (#affixes - 1) * lineH
            for i, affix in ipairs(affixes) do
                local lineY = baseY + (i - 1) * lineH
                local text = affix.name .. ": " .. affix.shortDesc
                drawTextStroke(vg, 540, lineY, text, 28,
                    NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 190, 80, 3)
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
    if require("ui.SettingsPanel").isEffectsEnabled() then
        -- 常驻召唤物（摘星星星人星门，漂浮在卡片旁并自转）
        ProjectileSystem.drawStarGates(vg, allies, ALLY_CARD_CY, getCardCX, true)
        ProjectileSystem.drawStarGates(vg, enemies, ENEMY_CARD_CY, getCardCX, false)

        -- 投射物（在卡片之上）
        ProjectileSystem.draw(vg)

        -- 攻击特效（在投射物之上、浮动文字之下）
        BattleEffects.draw(vg)

        -- 卡片 Spine 特效（升级/复活，在攻击特效之上）
        require("ui.SpineCardEffect").draw(vg)
    end

    -- 15. 浮动伤害数字
    if require("ui.SettingsPanel").isDamageNumbersEnabled() then
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

function BattleScene.update(dt)
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
        startBattleTalents = startBattleTalents, onStageChangedCallback = onStageChangedCallback,
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
    ART.update(logicDt)


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
        reincarnationTimer = reincarnationTimer, battleActive = battleActive,
        searchingTimer = searchingTimer, defeatTimer = defeatTimer,
        terminalDefeatPending = terminalDefeatPending, defeatByTimeout = defeatByTimeout,
        settleWaveEfficiency = settleWaveEfficiency, resetWaveTimers = resetWaveTimers,
        nextStage = BattleScene.nextStage,
    }
    local _casConsumed = BattleCasualty.process(_casCtx, logicDt)
    waveKillCount = _casCtx.waveKillCount
    waveGoldEarned = _casCtx.waveGoldEarned
    waveExpEarned = _casCtx.waveExpEarned
    stageKillCount_ = _casCtx.stageKillCount
    isFirstClear = _casCtx.isFirstClear
    reincarnationTimer = _casCtx.reincarnationTimer
    battleActive = _casCtx.battleActive
    searchingTimer = _casCtx.searchingTimer
    defeatTimer = _casCtx.defeatTimer
    terminalDefeatPending = _casCtx.terminalDefeatPending
    defeatByTimeout = _casCtx.defeatByTimeout
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
        if bgTransAnim.timer >= BG_TRANS_DURATION then
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

--- 重置战斗状态（新单位加入时调用）
local function resetBattle()
    battleActive = true
    if isFirstClear then
        firstClearTimeLeft = require("config.GameConfig").Battle.TIME_LIMIT_SEC
    else
        firstClearTimeLeft = nil
    end
    Diag.reset()
    BattleCombat.reset()
    BattleEffects.reset()
    ProjectileSystem.reset()
    SpeechBubble.reset()  -- 清空台词气泡
    TM.reset()   -- 清空仇恨表
    SEM.reset()  -- 清空状态效果
    TAL.reset()  -- 清空天赋运行时状态
    RCH.reset()  -- 清空遗物条件状态
    ART.reset()  -- 清空神器条件状态
    -- 重置所有己方单位（清除Buff → 重新应用装备 → 填满血）& 初始化天赋
    for _, u in ipairs(allies) do
        Diag.installSentinel(u)
        resetAllyUnit(u)
        TAL.initUnit(u)
    end
    RCH.initBattle(allies)  -- 重新初始化遗物条件词条
    ART.initBattle(allies)  -- 重新初始化神器条件效果
    for _, u in ipairs(enemies) do
        Diag.installSentinel(u)
        u.atkProgress = 0
        TAL.initUnit(u)
    end
    -- 触发战斗开始仇恨（骑士"阵前叫嚣"等）
    TM.onBattleStart(allies, enemies)
    TAL.onBattleStart(allies, enemies)
    -- [EnemyGuard] resetBattle 出口检查
    checkEnemiesCorruption("RESET_BATTLE_EXIT")
end

--- 设置敌方单位列表（DebugPanel 用）
function BattleScene.setEnemies(list)
    -- 限制场上上限（使用当前关卡的敌方场地上限）
    local maxField = getStageMaxFieldEnemies()
    enemies = {}
    enemyQueue = {}
    for i, u in ipairs(list) do
        if i <= maxField then
            enemies[#enemies + 1] = u
        else
            enemyQueue[#enemyQueue + 1] = u
        end
    end
    resetBattle()
end

--- 设置己方单位列表（DebugPanel 用）
function BattleScene.setAllies(list)
    -- [EnemyGuard] setAllies 入口检查：此时 enemies 是否已被污染
    checkEnemiesCorruption("setAllies_ENTRY")
    print(string.format("[EnemyGuard] setAllies called listLen=%d enemies_ref=%s enemies_len=%d allies_ref=%s",
        #list, tostring(enemies), #enemies, tostring(allies)))

    -- 限制场上上限
    if #list > MAX_FIELD_ALLIES then
        local trimmed = {}
        for i = 1, MAX_FIELD_ALLIES do
            trimmed[i] = list[i]
        end
        allies = trimmed
    else
        allies = list
    end
    -- 为所有 ally 创建初始基线快照（此时 unit 已含全部持久性 modifier + 装备）
    for _, u in ipairs(allies) do
        createSnapshot(u)
    end
    -- [HealDiag2] setAllies时记录所有治疗者属性
    for i, u in ipairs(allies) do
        if u.attrs and AD.getAtkCategory(u.attrs.atkType) == "healing" then
            u._diagInitHealer = true  -- [HealDiag3] 永久标记初始治疗者
            local healAmt = u.attrs:get(AD.HEAL_AMOUNT)
            local baseHealAmt = u.attrs:getBase(AD.HEAL_AMOUNT)
            local hp = u.attrs:get(AD.HP)
            local maxHp = u.attrs:get(AD.MAX_HP)
            local snapHealAmt = u._baseSnapshot and u._baseSnapshot:get(AD.HEAL_AMOUNT) or -1
            print(string.format(
                "[HealDiag2] INIT_HEALER [%d] name=%s id=%s lv=%s"
                .. " healAmt_final=%.1f healAmt_base=%.1f snap_healAmt=%.1f"
                .. " hp=%d/%d atkType=%s atkCoeff=%.2f",
                i, tostring(u.name), tostring(u.heroId), tostring(u.level),
                healAmt, baseHealAmt, snapHealAmt,
                hp, maxHp,
                tostring(u.attrs.atkType), u.attrs.atkCoeff or 1.0
            ))
        end
    end
    -- 保存 searching 状态：setBattleData 首次加载时已设置 searchingTimer，
    -- resetBattle 会将 battleActive 置 true 覆盖寻怪状态，需在之后恢复
    local wasSearching = (searchingTimer ~= nil) and (not battleActive)
    resetBattle()
    if wasSearching then
        battleActive = false
        -- searchingTimer 未被 resetBattle 修改，无需恢复
        print("[BattleScene] setAllies: 恢复寻怪状态 searchingTimer=" .. tostring(searchingTimer))
    end
    -- [EnemyGuard] setAllies 出口检查：enemies 是否变成了 allies 的引用
    if enemies == allies then
        print("[EnemyGuard] CRITICAL: enemies === allies (same table ref!) after setAllies+resetBattle")
    end
    checkEnemiesCorruption("setAllies_EXIT")
    print(string.format("[EnemyGuard] setAllies EXIT enemies_ref=%s allies_ref=%s enemies_len=%d allies_len=%d",
        tostring(enemies), tostring(allies), #enemies, #allies))
    -- [诊断] setAllies 后即时扫描（首次加载走此路径）
    Diag.scanNow(allies, enemies, "setAllies_postReset")
    recalcIdleIncome()
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
function BattleScene.gotoStage(stageId)
    if not _navLogic then bindBattleExtracts() end
    return _navLogic.gotoStage(stageId)
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
--- callback(data): data = { stageId, enemyCX, enemyCY }
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
    local HC = require("config.HeroConfig")
    local CharacterPanel = require("ui.CharacterPanel")
    for _, u in ipairs(allies) do
        -- 跳过已死亡的单位
        if u.heroId and u.hp > 0 then
            local owned = CharacterPanel.getOwnedHero and CharacterPanel.getOwnedHero(u.heroId)
            if owned and owned.level then
                local heroLevel = CharacterPanel.getEffectiveLevel
                    and CharacterPanel.getEffectiveLevel(u.heroId) or owned.level
                -- 重建完整属性（含最新等级/觉醒/转职/装备），存入 _pendingSnapshot 延迟生效
                -- 当前战斗中 u.attrs / u.hp / u.maxHp / u.atkInterval 保持不变
                local newUnit = HC.createHero(u.heroId, heroLevel, owned.advBranch, owned.awakening, owned.extraTalent)
                if newUnit and newUnit.attrs then
                    local partySlot = nil
                    for ai, a in ipairs(allies) do
                        if a == u then partySlot = ai; break end
                    end
                    -- 应用已穿戴装备属性（含槽位强化加成）
                    if CharacterPanel.applyEquippedItems then
                        local eqArmorType = CharacterPanel.applyEquippedItems(newUnit.attrs, u.heroId, partySlot)
                        if eqArmorType then
                            newUnit.armorType = eqArmorType
                        end
                    end
                    -- 应用遗物词条属性加成（与 getDeployedTeam 一致）
                    local RelicBridge = require("systems.RelicBridge")
                    local relicConds = RelicBridge.applyToUnit(newUnit.attrs, newUnit.classId or u.classId)
                    if relicConds and #relicConds > 0 then
                        u.relicConditions = relicConds
                    end
                    local artifactEffects = require("systems.ArtifactBridge").applyToUnit(newUnit.attrs, partySlot)
                    if artifactEffects and #artifactEffects > 0 then
                        u.artifactEffects = artifactEffects
                    else
                        u.artifactEffects = nil
                    end
                    -- 存入待定快照，下次波次切换时生效
                    u._pendingSnapshot = newUnit.attrs
                    u._pendingArmorType = newUnit.armorType
                    -- 觉醒/转职变更需立即同步运行时节点，否则 TalentManager.hasAwaken 仍按旧阶判定
                    if newUnit.awakeningNodes then
                        u.awakeningNodes = newUnit.awakeningNodes
                    end
                    if newUnit.advBranch then
                        u.advBranch = newUnit.advBranch
                    end
                    if newUnit.advTalentIds then
                        u.advTalentIds = newUnit.advTalentIds
                    end
                    -- 等级变化时记录待定等级（使用有效等级，含共鸣加成）
                    local currentStatLevel = u._pendingLevel or u.level
                    if heroLevel > currentStatLevel then
                        u._pendingLevel = heroLevel
                        print(string.format("[BattleScene] refreshAllyStats: hero %s statLv %d→%d stored as pending",
                            tostring(u.heroId), currentStatLevel, heroLevel))

                        -- 升级 Spine 特效：立即播放作为视觉反馈
                        local idx = 1
                        for ai, a in ipairs(allies) do
                            if a == u then idx = ai; break end
                        end
                        local cx = BattleCombat.getCardCX(allies, idx)
                        require("ui.SpineCardEffect").playLevelUp(cx, ALLY_CARD_CY)
                    else
                        print(string.format("[BattleScene] refreshAllyStats: hero %s attrs refreshed (equip/awaken change), pending",
                            tostring(u.heroId)))
                    end
                end
            end
        end
    end
    recalcIdleIncome()
end

--- [Debug] 立即通关当前关卡（杀死所有敌人 + 清空队列，让胜利检测自然触发）
function BattleScene.debugInstantClear()
    -- 清空待出场队列
    for i = #enemyQueue, 1, -1 do enemyQueue[i] = nil end
    -- 击杀场上所有敌人
    for _, e in ipairs(enemies) do
        if e.hp > 0 then e.hp = 0 end
    end
    -- 重置波次计时，避免秒杀数据污染效率缓冲区
    waveStartTime = nil
    waveKillCount = 0
    waveGoldEarned = 0
    waveExpEarned = 0
    print("[BattleScene][Debug] 立即通关: 已清除所有敌人")
end

--- [DEBUG] 跳转到指定关卡（调试面板用，同步本地进度；持久化由 GM_JUMP_STAGE 负责）
---@param stageId number 目标关卡 ID
function BattleScene.debugJumpToStage(stageId)
    local stageConfig = getStageConfig()
    local stage = stageConfig.getStage(stageId)
    if not stage then
        print("[BattleScene][Debug] 无效关卡 ID: " .. tostring(stageId))
        return
    end
    searchingTimer = nil
    defeatTimer = nil
    reincarnationTimer = nil
    regenAccum = 0
    bgTransAnim = { timer = 0, zoomTarget = BG_ZOOM_FWD_TARGET }
    BottomNav.setAllLocked(false)

    -- 重建进度：含此前所有难度与终焉神殿，不含当前难度终焉
    maxStageId_ = stageId
    clearedStages = {}
    for k, v in pairs(stageConfig.buildClearedStagesUpTo(stageId)) do
        local numKey = tonumber(k)
        if numKey and v then
            clearedStages[numKey] = true
        end
    end
    isFirstClear = not clearedStages[stageId]
    recalcIdleIncome()

    loadStage(stageId, true)
    for _, u in ipairs(allies) do resetAllyUnit(u) end
    startBattleTalents()
    print("[BattleScene][Debug] 跳转到关卡 " .. stageId .. " (" .. stage.name .. ")")
end

--- 重新加载当前关卡
---@param opts? { startSearching?: boolean }  startSearching=true 时以"寻怪中"进度条启动（首次进入用）
function BattleScene.reloadStage(opts)
    searchingTimer = nil
    defeatTimer = nil
    regenAccum = 0

    if opts and opts.startSearching then
        -- 首次进入：loadStage 做完整初始化（不需 resetAllyUnit）
        loadStage(currentStageId)
        -- 进入寻怪状态，等服务端装备/天赋数据同步完毕
        -- searchingTimer 到期后会自动 resetAllyUnit + 重新生成敌人 + startBattleTalents
        battleActive = false
        searchingTimer = 0
        print("[BattleScene] 首次进入，以寻怪模式启动")
    else
        -- 常规重载：skipBattleStart → resetAllyUnit → startBattleTalents
        loadStage(currentStageId, true)
        for _, u in ipairs(allies) do resetAllyUnit(u) end
        startBattleTalents()
    end
end

--- 重置战斗场景到初始默认状态（清除存档后调用）
function BattleScene.resetToDefault()
    currentStageId = 0101
    clearedStages = {}
    isFirstClear = true
    initialBattleDataLoaded = false
    battleActive = false  -- 等 setBattleData 首次到达后再启动（与 init 一致）
    isPaused = false
    searchingTimer = nil
    defeatTimer = nil
    reincarnationTimer = nil
    regenAccum = 0
    bgAnimTimer = 0
    bgTransAnim = nil
    currentChapter = 0
    maxStageId_ = SC.NORMAL_FIRST_STAGE or 101
    enemies = {}
    enemyQueue = {}
    SEM.reset()
    TAL.reset()
    RCH.reset()
    ART.reset()
    BattleCombat.reset()
    ProjectileSystem.reset()
    -- 解锁导航（防止终焉神殿锁定残留）
    BottomNav.setAllLocked(false)
    -- 不再在此调用 loadStage：initialBattleDataLoaded=false 会让 setBattleData 统一处理
    print("[BattleScene] resetToDefault OK (deferred loadStage)")
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

return BattleScene

