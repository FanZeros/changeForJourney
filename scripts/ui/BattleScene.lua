-- ============================================================================
-- BattleScene - 战斗场景 UI
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- ============================================================================

local CF  = require("systems.CombatFormula")
local AD  = require("systems.AttributeDef")
local TM  = require("systems.ThreatManager")
local SEM = require("systems.StatusEffectManager")
local TAL = require("systems.TalentManager")
local RCH = require("systems.RelicConditionHandler")
local ART = require("systems.ArtifactRuntime")
local MAS = require("systems.MapAffixSystem")
local SC  = require("config.StageConfig")
local MC  = require("config.MonsterConfig")
local GameConfig = require("config.GameConfig")
local HeroAssetUtil = require("config.HeroAssetUtil")

local BattleCombat      = require("ui.BattleCombat")
local StageBerserk     = require("ui.StageBerserk")
local BattleDraw        = require("ui.BattleDraw")
local BattleEffects     = require("ui.BattleEffects")
local ProjectileSystem  = require("ui.ProjectileSystem")
local LootBox           = require("ui.LootBox")
local SweepDialog       = require("ui.SweepDialog")
local DamageStatsPanel  = require("ui.DamageStatsPanel")
local BattleStats       = require("systems.BattleStats")
local SpeechBubble      = require("ui.SpeechBubble")
local SpineCardEffect   = require("ui.SpineCardEffect")
local GameBGM           = require("systems.GameBGM")
local BottomNav         = require("ui.BottomNav")
local SettingsPanel     = require("ui.SettingsPanel")

local ExpTable = require("config.ExpTable")
local Diag = require("systems.BattleDiag")
local NumberUtil = require("core.NumberUtil")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化] 地图压暗滤镜

local BattleResultPanel = require("ui.BattleResultPanel")
local OfflineCalc = require("systems.OfflineCalc")
local StageUtils = require("shared.StageUtils")
local StageProvider = require("shared.StageProvider")
local ChallengerServerConfig = require("shared.ChallengerServerConfig")
local ArtifactBridge = require("systems.ArtifactBridge")
local ServerListConfig = require("shared.ServerListConfig")
local PlayerInfoPanel = require("ui.PlayerInfoPanel")

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
local ENEMY_NAME_OFFSET_Y = 90
local ENEMY_HP_BG_OFFSET_Y = 153
local ENEMY_HP_VAL_OFFSET_Y = 135
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
local NAV = {
    STAGE_CX = 540, STAGE_CY = 1276,
    BACK_BG_CX = 116, BACK_BG_CY = 1277, BACK_BG_W = 232, BACK_BG_H = 226,
    BACK_ICON_CX = 81, BACK_ICON_CY = 1258, BACK_ICON_W = 53, BACK_ICON_H = 81,
    BACK_TEXT_CX = 88, BACK_TEXT_CY = 1326,
    FWD_BG_CX = 964, FWD_BG_CY = 1277, FWD_BG_W = 232, FWD_BG_H = 226,
    FWD_ICON_CX = 998, FWD_ICON_CY = 1258, FWD_ICON_W = 53, FWD_ICON_H = 81,
    FWD_TEXT_CX = 991, FWD_TEXT_CY = 1325,
}

-- (职业标签 TAG_SIZE / HP_BAR / ATK_BAR 已移至 BattleDraw)

-- 墓碑复活间隔（秒）
local TOMBSTONE_REVIVE_TIME = 2.0

-- 死亡即补位：退场+空位总时长（秒），期满新怪从右补入
local RESPAWN_DELAY = 1.0

-- 死亡/复活动画常量（定义在 BattleCombat，此处引用）
local DEATH_ANIM_DURATION  = BattleCombat.DEATH_ANIM_DURATION
local REVIVE_ANIM_DURATION = BattleCombat.REVIVE_ANIM_DURATION

-- ======================== 图片 handles ========================

local vg_         = nil   -- 缓存 nvg context（init 赋值，loadStage 中切换地图用）
local currentChapter = 0  -- 当前章节号（用于检测章节变化、切换地图背景）

local imgMap      = -1
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
local imgDeath    = -1    -- 墓碑图片



-- ======================== 数据 ========================

local stageName = "黑棘林道1-1"
local idleRangeText_ = nil  -- 挂机范围显示文本缓存

-- 默认攻击间隔（秒）
local DEFAULT_ALLY_INTERVAL  = 1.0
local DEFAULT_ENEMY_INTERVAL = 1.5

-- ======================== 长按怪物信息弹窗 ========================
local LONG_PRESS_THRESHOLD = 0.4  -- 秒
local longPress = {
    active = false,       -- 是否正在检测
    fired = false,        -- 是否已触发弹窗
    startTime = 0,
    startX = 0,
    startY = 0,
    showPopup = false,    -- 弹窗是否显示
    unit = nil,           -- 命中的怪物 unit
}

-- 攻击类型名称
local ATK_TYPE_NAMES = {
    [1] = "斩击", [2] = "粉碎", [3] = "穿刺", [4] = "火焰",
    [5] = "冰霜", [6] = "闪电", [7] = "暗影", [8] = "神圣",
}
-- 护甲类型名称
local ARMOR_TYPE_NAMES = {
    [1] = "皮甲", [2] = "轻甲", [3] = "重甲", [4] = "板甲", [5] = "布甲",
}

-- 前向声明（实现在文件末尾）
local updateLongPress
local drawMonsterInfoPopup

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
    return StageProvider.GetForServer(PlayerInfoPanel.getServerId())
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
local maxStageId_ = 0

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

-- 背景过渡动画（缩放+渐隐/渐入）
local bgTransAnim = nil  -- nil=无动画; { timer, zoomTarget }
local BG_TRANS_DURATION   = 0.45  -- 总时长
local BG_FADE_OUT_RATIO   = 0.45  -- 前 45% 为缩放淡出，后 55% 为淡入
local BG_ZOOM_FWD_TARGET  = 1.3   -- 前进：放大淡出
local BG_ZOOM_BACK_TARGET = 0.7   -- 后退：缩小淡出

-- ======================== 终焉神殿确认弹窗 ========================




-- 弹窗状态
local confirmDialog = {
    open     = false,
    closing  = false,
    openTime = 0,
    closeTime = 0,
    pendingNextId = nil,  -- 待进入的终焉神殿关卡 ID
}

-- 弹窗动画参数
local CONFIRM_OPEN_DUR  = 0.25
local CONFIRM_CLOSE_DUR = 0.20
local CONFIRM_SCALE_FROM = 0.8
local CONFIRM_SCALE_TO   = 1.0

-- 弹窗布局常量（设计分辨率 1080×2400，对齐购买道具弹窗样式）
local CDL = {
    BG_CX = 540, BG_CY = 1100, BG_W = 950, BG_H = 647,
    -- 标题（白色 + 棕色描边，位于卡片顶部边缘）
    TITLE_CY  = 847,  TITLE_FONT = 60, TITLE_SW = 6,
    TITLE_SR = 0x46, TITLE_SG = 0x2f, TITLE_SB = 0x20,
    -- 副标题（#725850）
    SUB_CY = 960, SUB_FONT = 40,
    -- 正文行（#725850）
    LINE1_CY  = 1060, LINE_FONT  = 38,
    LINE2_CY  = 1120,
    LINE3_CY  = 1180, LINE3_FONT = 32,
    -- 确认按钮（九宫格绿色按钮）
    OK_CX = 340, OK_CY = 1310, OK_W = 310, OK_H = 100, OK_FONT = 40,
    OK_TR = 0x2a, OK_TG = 0x52, OK_TB = 0x18,  -- 按钮文字颜色
    -- 取消按钮（九宫格灰色按钮）
    CANCEL_CX = 740, CANCEL_CY = 1310, CANCEL_W = 310, CANCEL_H = 100, CANCEL_FONT = 40,
    CANCEL_TR = 0x50, CANCEL_TG = 0x46, CANCEL_TB = 0x3c,
}

--- 全局章节号转难度内相对章节号
local function getRelativeChapter(chapter)
    return SC.getRelativeChapter(chapter)
end

--- 九宫格绘制（局部函数，与其他页面一致）
local function drawNineSlice(vg, img, dx, dy, dw, dh, iTop, iRight, iBottom, iLeft)
    if img < 0 then return end
    local iw, ih = nvgImageSize(vg, img)
    if iw <= 0 or ih <= 0 then return end
    -- 九个区域的源/目标坐标
    local sx = { 0, iLeft, iw - iRight }
    local sy = { 0, iTop, ih - iBottom }
    local sw = { iLeft, iw - iLeft - iRight, iRight }
    local sh = { iTop, ih - iTop - iBottom, iBottom }
    local ddx = { dx, dx + iLeft, dx + dw - iRight }
    local ddy = { dy, dy + iTop, dy + dh - iBottom }
    local ddw = { iLeft, dw - iLeft - iRight, iRight }
    local ddh = { iTop, dh - iTop - iBottom, iBottom }
    for row = 1, 3 do
        for col = 1, 3 do
            if ddw[col] > 0 and ddh[row] > 0 then
                local scaleX = ddw[col] / sw[col]
                local scaleY = ddh[row] / sh[row]
                nvgSave(vg)
                nvgTranslate(vg, ddx[col], ddy[row])
                nvgScale(vg, scaleX, scaleY)
                nvgBeginPath(vg)
                nvgRect(vg, 0, 0, sw[col], sh[row])
                local pat = nvgImagePattern(vg, -sx[col], -sy[row], iw, ih, 0, img, 1.0)
                nvgFillPaint(vg, pat)
                nvgFill(vg)
                nvgRestore(vg)
            end
        end
    end
end

--- 弹窗缓动函数
local function easeOutCubic(t)
    local t1 = 1 - t
    return 1 - t1 * t1 * t1
end
local function easeInCubic(t)
    return t * t * t
end

--- 获取确认弹窗动画状态
---@return number scale, number alpha, boolean done
local function getConfirmAnim()
    if confirmDialog.closing then
        local t = math.min(1.0, (time.elapsedTime - confirmDialog.closeTime) / CONFIRM_CLOSE_DUR)
        local e = easeInCubic(t)
        local scale = CONFIRM_SCALE_TO + (CONFIRM_SCALE_FROM - CONFIRM_SCALE_TO) * e
        return scale, 1.0 - e, (t >= 1.0)
    else
        local t = math.min(1.0, (time.elapsedTime - confirmDialog.openTime) / CONFIRM_OPEN_DUR)
        local e = easeOutCubic(t)
        local scale = CONFIRM_SCALE_FROM + (CONFIRM_SCALE_TO - CONFIRM_SCALE_FROM) * e
        return scale, e, false
    end
end

--- 获取轮回后的难度中文名
local function getDifficultyDisplayName(diff)
    return getStageConfig().getDifficultyDisplayName(diff)
end

--- 绘制终焉神殿确认弹窗（样式对齐购买道具弹窗）
local function drawConfirmDialog(vg)
    if not confirmDialog.open and not confirmDialog.closing then return end

    local pScale, pAlpha, done = getConfirmAnim()
    if confirmDialog.closing and done then
        confirmDialog.closing = false
        confirmDialog.open = false
        confirmDialog.pendingNextId = nil
        return
    end

    -- 获取当前难度和轮回后难度名
    local stageConfig = getStageConfig()
    local currentDiff = stageConfig.getDifficulty(currentStageId)
    local nextDiff = stageConfig.getNextDifficulty(currentDiff)
    local nextDiffName = getDifficultyDisplayName(nextDiff)

    -- 1) 黑色遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * pAlpha)))
    nvgFill(vg)

    -- 2) 缩放+淡入变换
    nvgSave(vg)
    nvgTranslate(vg, CDL.BG_CX, CDL.BG_CY)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -CDL.BG_CX, -CDL.BG_CY)
    nvgGlobalAlpha(vg, pAlpha)

    -- 3) 九宫格背景
    DarkIcon.drawNine(vg, "panel", CDL.BG_CX - CDL.BG_W * 0.5, CDL.BG_CY - CDL.BG_H * 0.5, CDL.BG_W, CDL.BG_H, { titleH = 40 })

    -- 4) 标题（白色 + 棕色描边，与购买弹窗一致）
    BattleDraw.drawTextStroke(vg, CDL.BG_CX, CDL.TITLE_CY, "⚠ 终焉神殿", CDL.TITLE_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, CDL.TITLE_SW,
        { strokeColor = { CDL.TITLE_SR, CDL.TITLE_SG, CDL.TITLE_SB } })

    -- 5) 副标题（与购买弹窗 "是否购买此道具" 同位置同风格）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, CDL.SUB_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 255))
    nvgText(vg, CDL.BG_CX, CDL.SUB_CY, "确认进入终焉神殿？", nil)

    -- 6) 说明文本（#725850）
    nvgFontSize(vg, CDL.LINE_FONT)
    nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
    nvgText(vg, CDL.BG_CX, CDL.LINE1_CY, "进入后将无法退出", nil)
    nvgText(vg, CDL.BG_CX, CDL.LINE2_CY, "通关后进入「" .. nextDiffName .. "」轮回", nil)

    nvgFontSize(vg, CDL.LINE3_FONT)
    nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 200))
    nvgText(vg, CDL.BG_CX, CDL.LINE3_CY, "（挑战失败将回退到上一关）", nil)

    -- 7) 确认按钮（九宫格绿色按钮）
    DarkIcon.drawNine(vg, "btn", CDL.OK_CX - CDL.OK_W * 0.5, CDL.OK_CY - CDL.OK_H * 0.5, CDL.OK_W, CDL.OK_H, { accent = "green" })
    nvgFontFace(vg, "sans"); nvgFontSize(vg, CDL.OK_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(CDL.OK_TR, CDL.OK_TG, CDL.OK_TB, 255))
    nvgText(vg, CDL.OK_CX, CDL.OK_CY, "进入", nil)

    -- 8) 取消按钮（九宫格灰色按钮）
    DarkIcon.drawNine(vg, "btn", CDL.CANCEL_CX - CDL.CANCEL_W * 0.5, CDL.CANCEL_CY - CDL.CANCEL_H * 0.5, CDL.CANCEL_W, CDL.CANCEL_H, { accent = "green" })
    nvgFontFace(vg, "sans"); nvgFontSize(vg, CDL.CANCEL_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(CDL.CANCEL_TR, CDL.CANCEL_TG, CDL.CANCEL_TB, 255))
    nvgText(vg, CDL.CANCEL_CX, CDL.CANCEL_CY, "取消", nil)

    nvgRestore(vg)
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
local drawImageCentered = BattleDraw.drawImageCentered
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
    local diff = getStageConfig().getDifficulty(currentStageId)
    if diff == SC.DIFFICULTY_HELL or diff == SC.DIFFICULTY_NIGHTMARE
        or diff == SC.DIFFICULTY_PURGATORY or diff == SC.DIFFICULTY_TORMENT
        or diff == SC.DIFFICULTY_TORMENT2 or diff == SC.DIFFICULTY_TORMENT3
        or diff == SC.DIFFICULTY_TORMENT4 or diff == SC.DIFFICULTY_TORMENT5
        or diff == SC.DIFFICULTY_ANNIHILATION or diff == SC.DIFFICULTY_ANNIHILATION2
        or diff == SC.DIFFICULTY_ANNIHILATION3 or diff == SC.DIFFICULTY_ANNIHILATION4
        or diff == SC.DIFFICULTY_ANNIHILATION5 then
        return 2.0
    elseif diff == SC.DIFFICULTY_HARD then
        return 1.5
    end
    return 1.0
end

function BattleScene.isSpeedButtonVisible()
    return isFirstClear and battleActive and not isPaused
        and BattleScene.getMaxUnlockedBattleSpeed() > 1.0
        and not BattleResultPanel.isOpen()
        and not confirmDialog.open and not confirmDialog.closing
        and not SweepDialog.isOpen() and not DamageStatsPanel.isOpen()
        and searchingTimer == nil and defeatTimer == nil and reincarnationTimer == nil
end

function BattleScene.getBattleLogicDt(dt)
    local maxSpeed = BattleScene.getMaxUnlockedBattleSpeed()
    if BattleScene.battleSpeed > maxSpeed then
        BattleScene.battleSpeed = maxSpeed
    end
    if BattleScene.isSpeedButtonVisible() then
        return dt * BattleScene.battleSpeed
    end
    return dt
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
    if BattleScene.battleSpeed == 1.5 then
        return "X1.5"
    elseif BattleScene.battleSpeed >= 2.0 then
        return "X2"
    end
    return "X1"
end

function BattleScene.drawSpeedButton(vg)
    if not BattleScene.isSpeedButtonVisible() then return end
    local alpha = BattleScene.battleSpeed > 1.0 and 1.0 or 0.82
    drawImageCentered(vg, BattleScene.imgSpeedIcon, 987, 311, 130, 143, alpha)
    drawTextStroke(vg, 987, 305,
        BattleScene.getSpeedText(), 52,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 6,
        { strokeColor = { 0x36, 0x77, 0x78 } })
end

function BattleScene.handleSpeedButtonInput(dx, dy)
    if not BattleScene.isSpeedButtonVisible() then return false end
    if math.abs(dx - 987) <= 65 and math.abs(dy - 311) <= 71.5 then
        local maxSpeed = BattleScene.getMaxUnlockedBattleSpeed()
        if BattleScene.battleSpeed < 1.5 and maxSpeed >= 1.5 then
            BattleScene.battleSpeed = 1.5
        elseif BattleScene.battleSpeed < 2.0 and maxSpeed >= 2.0 then
            BattleScene.battleSpeed = 2.0
        else
            BattleScene.battleSpeed = 1.0
        end
        print("[BattleScene] 首通战斗倍速切换: " .. BattleScene.getSpeedText())
        return true
    end
    return false
end

-- ======================== 属性快照隔离 ========================

--- 为单位创建基线快照（调用时机：setAllies / fallback 重建后）
--- 快照 = attrs 的深拷贝，包含全部持久性 modifier（职业/转职/星图/装备）
---@param u table battle unit
local function createSnapshot(u)
    if u.attrs then
        u._baseSnapshot = u.attrs:clone()
    end
    u._baseArmorType = u.armorType  -- 记录当前护甲类型
    u._pendingSnapshot = nil  -- 清除待应用快照
    u._pendingArmorType = nil
end

--- 从快照恢复单位属性
--- 如有 pendingSnapshot（战斗中的升级/换装），提升为新的 baseSnapshot
--- 然后从 baseSnapshot clone 出干净的 live attrs
---@param u table battle unit
---@return boolean 是否成功恢复
local function restoreFromSnapshot(u)
    -- 消费 pending（升级/换装产生的待应用数据）
    if u._pendingSnapshot then
        u._hadPendingSnapshot = true  -- [HealDiag3] 标记曾消费 pending
        u._baseSnapshot = u._pendingSnapshot
        u._pendingSnapshot = nil
    else
        u._hadPendingSnapshot = false
    end
    -- 同步待定等级
    if u._pendingLevel then
        u.level = u._pendingLevel
        u._pendingLevel = nil
    end
    -- 同步待定护甲类型（换装导致护甲类型变化）
    if u._pendingArmorType then
        u._baseArmorType = u._pendingArmorType
        u._pendingArmorType = nil
    end
    if u._baseArmorType then
        u.armorType = u._baseArmorType
    end
    -- 从 base 快照 clone 出干净 attrs（不含运行时 buff）
    if u._baseSnapshot then
        u.attrs = u._baseSnapshot:clone()
        -- [HealDiag3] 恢复快照时检查治疗者的 HEAL_AMOUNT 是否正常
        if u.attrs and AD.getAtkCategory(u.attrs.atkType) == "healing" then
            local snapHeal = u._baseSnapshot:get(AD.HEAL_AMOUNT)
            local clonedHeal = u.attrs:get(AD.HEAL_AMOUNT)
            if snapHeal <= 0 or clonedHeal <= 0 then
                print(string.format(
                    "[HealDiag3] RESTORE_SNAP_ZERO name=%s id=%s snapHeal=%.1f clonedHeal=%.1f"
                    .. " hadPending=%s atkType=%d",
                    tostring(u.name), tostring(u.heroId or "?"),
                    snapHeal, clonedHeal,
                    tostring(u._hadPendingSnapshot or false),
                    u.attrs.atkType or -1
                ))
            end
        end
        return true
    end
    return false
end

--- 重置单个己方单位状态（从快照恢复干净属性 → 填满血 → 同步 flat 字段）
--- 如有 pendingSnapshot（战斗中的升级/换装），在此时消费并生效
local function resetAllyUnit(u)
    u.atkProgress = 0
    u.reviveTimer = nil
    if u.attrs then
        local restored = restoreFromSnapshot(u)
        if not restored then
            -- fallback: 无快照时全量重建（首次加载或异常情况）
            if u.heroId then
                local HC = require("config.HeroConfig")
                local CP = require("ui.CharacterPanel")
                local owned = CP.getOwnedHero and CP.getOwnedHero(u.heroId)
                local heroLevel = (CP.getEffectiveLevel and CP.getEffectiveLevel(u.heroId))
                    or (owned and owned.level) or u.level
                local newUnit = HC.createHero(u.heroId,
                    heroLevel,
                    (owned and owned.advBranch) or u.advBranch,
                    owned and owned.awakening)
                if newUnit and newUnit.attrs then
                    local partySlot = nil
                    for ai, a in ipairs(allies) do
                        if a == u then partySlot = ai; break end
                    end
                    if CP.applyEquippedItems then
                        -- 查找出战槽位索引，确保槽位强化加成正确计算
                        local eqArmorType = CP.applyEquippedItems(newUnit.attrs, u.heroId, partySlot)
                        if eqArmorType then
                            newUnit.armorType = eqArmorType
                        end
                    end
                    -- 遗物词条属性加成（与 CharacterPanel.getDeployedTeam 一致）
                    local RelicBridge = require("systems.RelicBridge")
                    local relicConds = RelicBridge.applyToUnit(newUnit.attrs, newUnit.classId or u.classId)
                    if relicConds and #relicConds > 0 then
                        u.relicConditions = relicConds
                    end
                    if CP.applyAvatarFrameAttributes then
                        CP.applyAvatarFrameAttributes(newUnit.attrs)
                    end
                    local artifactEffects = ArtifactBridge.applyToUnit(newUnit.attrs, partySlot)
                    if artifactEffects and #artifactEffects > 0 then
                        u.artifactEffects = artifactEffects
                    else
                        u.artifactEffects = nil
                    end
                    u.attrs = newUnit.attrs
                    u.armorType = newUnit.armorType
                    u.level = newUnit.level
                    u.advBranch = newUnit.advBranch
                    u.advTalentIds = newUnit.advTalentIds
                    u.awakeningNodes = newUnit.awakeningNodes
                end
            end
            createSnapshot(u)
        end
        u.attrs:fillHp()
        u.maxHp       = u.attrs.final[AD.MAX_HP]
        u.hp          = u.attrs.final[AD.HP]
        u.atkInterval = u.attrs:getActualInterval()
        u._lastAttrInterval = u.atkInterval
    else
        -- [诊断] attrs 为 nil 时无法正确重置，记录此异常
        print("[BattleDiag] RESET_NO_ATTRS name=" .. tostring(u.name)
            .. " id=" .. tostring(u.heroId or u.instanceId or "?")
            .. " hp=" .. tostring(u.hp) .. "/" .. tostring(u.maxHp)
            .. " sentinel=" .. tostring(u._sentinelInstalled or false)
            .. " trace=" .. tostring(u._attrsSetNilTrace or "none"))
        u.hp = u.maxHp
    end
    syncUnitHp(u)
    -- [HealDiag2] resetAllyUnit后检查治疗者属性是否正确恢复
    if u.attrs and AD.getAtkCategory(u.attrs.atkType) == "healing" then
        local healAmt = u.attrs:get(AD.HEAL_AMOUNT)
        if healAmt <= 0 then
            local baseH = u.attrs:getBase(AD.HEAL_AMOUNT)
            local snapH = u._baseSnapshot and u._baseSnapshot:get(AD.HEAL_AMOUNT) or -1
            print(string.format(
                "[HealDiag2] RESET_HEALER_ZERO name=%s id=%s healAmt_final=%.1f"
                .. " healAmt_base=%.1f snap_healAmt=%.1f hp=%d/%d",
                tostring(u.name), tostring(u.heroId),
                healAmt, baseH, snapH, u.hp, u.maxHp or 0
            ))
        end
    end
end

-- BattleDraw 本地别名
local drawCardGroup       = BattleDraw.drawCardGroup
local drawFloatingTexts   = BattleDraw.drawFloatingTexts
local drawProgressBar     = BattleDraw.drawProgressBar

-- ======================== 关卡系统 ========================

--- 根据关卡配置生成全部敌人列表
--- 格式化数字：超过4位数转换为k
---@param n number
---@return string
local function formatNumber(n)
    return NumberUtil.format(n)
end

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

--- 解析首通附加特殊怪 ID 列表（兼容 firstClearBonusMonster 单值）
---@param stageEntry StageEntry
---@return number[]|nil
local function getFirstClearBonusMonsterIds(stageEntry)
    local ids = stageEntry.firstClearBonusMonsters
    if ids and #ids > 0 then
        return ids
    end
    if stageEntry.firstClearBonusMonster then
        return { stageEntry.firstClearBonusMonster }
    end
    return nil
end

--- 标记首通附加特殊怪出场阶段：
--- 1 个：开场；2 个：开场 + 最后；3 个及以上：开场 + 中间若干 + 最后。
---@param bonusUnit table
---@param index number
---@param count number
local function markFirstClearBonusSpawnPhase(bonusUnit, index, count)
    bonusUnit._isBonusMonster = true
    if index == 1 then
        bonusUnit._bonusSpawnPhase = "start"
    elseif index == count then
        bonusUnit._bonusSpawnPhase = "end"
    else
        bonusUnit._bonusSpawnPhase = "middle"
    end
end

---@param queue table[]
---@param unit table
local function insertBonusMonsterIntoQueue(queue, unit)
    if unit._bonusSpawnPhase == "middle" then
        local insertPos = math.floor(#queue / 2) + 1
        table.insert(queue, insertPos, unit)
    else
        queue[#queue + 1] = unit
    end
end

---@param stageEntry StageEntry
---@return table[] allEnemies
local function generateEnemyList(stageEntry)
    local totalCount = isFirstClear and stageEntry.firstCount or stageEntry.idleCount
    local monsterTypes = stageEntry.monsters  -- {type1, type2, type3}
    local level = stageEntry.monsterLevel
    local list = {}

    -- 如果有 Boss，最后一只是 Boss
    local normalCount = totalCount
    if stageEntry.bossId > 0 then
        normalCount = totalCount - 1
    end

    -- 普通怪：从 3 种类型中轮流选择
    for i = 1, normalCount do
        local typeIdx = ((i - 1) % #monsterTypes) + 1
        local monsterId = monsterTypes[typeIdx]
        local unit = MC.createMonster(monsterId, level)
        if unit then
            list[#list + 1] = unit
        end
    end

    -- Boss（插入到普通怪剩余一半的位置，即列表中间）
    if stageEntry.bossId > 0 then
        local bossUnit = MC.createMonster(stageEntry.bossId, level)
        if bossUnit then
            local insertPos = math.ceil(#list / 2) + 1
            table.insert(list, insertPos, bossUnit)
        end
    end

    -- 首通附加特殊怪物：旅程19服及以上按阶段分批出场（开场/中间/最后）
    if isFirstClear then
        local bonusIds = getFirstClearBonusMonsterIds(stageEntry)
        if bonusIds then
            local bonusAtStart = ServerListConfig.isFirstClearBonusAtStart(PlayerInfoPanel.getServerId())
            local bonusCount = #bonusIds
            for i, monsterId in ipairs(bonusIds) do
                local bonusUnit = MC.createMonster(monsterId, level)
                if bonusUnit then
                    if bonusAtStart then
                        markFirstClearBonusSpawnPhase(bonusUnit, i, bonusCount)
                    end
                    list[#list + 1] = bonusUnit
                end
            end
        end
    end

    return list
end

--- 分配敌人到场上与队列；首通特殊怪按阶段出场（开场/中间/最后）
---@param allEnemies table[]
---@param maxField number
---@return table[] fieldEnemies, table[] queueEnemies
local function assignEnemiesToField(allEnemies, maxField)
    local field = {}
    local queue = {}
    local fieldCount = 0
    for _, u in ipairs(allEnemies) do
        if not u._isBonusMonster then
            if fieldCount < maxField then
                field[#field + 1] = u
                fieldCount = fieldCount + 1
            else
                queue[#queue + 1] = u
            end
        end
    end
    for _, u in ipairs(allEnemies) do
        if u._isBonusMonster then
            if u._bonusSpawnPhase == "start" then
                if fieldCount >= maxField and #field > 0 then
                    local bumped = table.remove(field, #field)
                    table.insert(queue, 1, bumped)
                else
                    fieldCount = fieldCount + 1
                end
                field[#field + 1] = u
            else
                insertBonusMonsterIntoQueue(queue, u)
            end
        end
    end
    return field, queue
end

--- 挂机模式：从 maxStageId_ 前 5 关混合生成怪物（不同等级）
--- 每关按 idleCount 取怪，等级各自不同，模拟玩家在这 5 关范围内挂机
---@return table[] allEnemies, number maxField
local function generateIdleEnemyList()
    local IDLE_STAGE_COUNT = 5
    local stageConfig = getStageConfig()
    local stages = StageUtils.collectPrevStages(maxStageId_, IDLE_STAGE_COUNT, stageConfig)
    -- 新玩家可能不足 5 关，有多少用多少
    if #stages == 0 then
        -- fallback: 用当前关卡（极端情况）
        local entry = stageConfig.getStage(currentStageId)
        if entry then
            return generateEnemyList(entry), entry.maxFieldEnemies or 5
        end
        return {}, 5
    end

    local allEnemies = {}
    local maxField = 0

    -- 平均分配每关出怪数量：取各关 idleCount 中最小的（保持战斗节奏一致）
    -- 每关各出 2 只（总计 10 只一波，5 只上场 5 只队列），保持场面丰富但不过于拥挤
    local perStage = 2

    for _, entry in ipairs(stages) do
        local monsterTypes = entry.monsters
        local level = entry.monsterLevel
        -- 取各关 maxFieldEnemies 的最大值作为场地上限
        if (entry.maxFieldEnemies or 5) > maxField then
            maxField = entry.maxFieldEnemies or 5
        end

        local hasBoss = entry.bossId and entry.bossId > 0

        if hasBoss then
            -- Boss 关：1 只普通怪 + 1 只 Boss
            local monsterId = monsterTypes[1]
            local unit = MC.createMonster(monsterId, level)
            if unit then
                unit._idleStageId = entry.id
                allEnemies[#allEnemies + 1] = unit
            end
            local bossUnit = MC.createMonster(entry.bossId, level)
            if bossUnit then
                bossUnit._idleStageId = entry.id
                allEnemies[#allEnemies + 1] = bossUnit
            end
        else
            -- 非 Boss 关：perStage 只普通怪，从怪物类型中轮流选取
            for i = 1, perStage do
                local typeIdx = ((i - 1) % #monsterTypes) + 1
                local monsterId = monsterTypes[typeIdx]
                local unit = MC.createMonster(monsterId, level)
                if unit then
                    unit._idleStageId = entry.id
                    allEnemies[#allEnemies + 1] = unit
                end
            end
        end
    end

    -- 保证场地上限至少 5
    if maxField < 5 then maxField = 5 end

    print(string.format("[BattleScene] 挂机混合出怪: %d只来自%d关 (maxField=%d)",
        #allEnemies, #stages, maxField))
    return allEnemies, maxField
end

--- 从等待队列补充敌人到场上（填补空位）
local function refillEnemies()
    -- 移除场上已死亡的单位，同时清理其仇恨记录
    local alive = {}
    for _, u in ipairs(enemies) do
        if u.hp > 0 then
            alive[#alive + 1] = u
        else
            TM.removeUnit(u)
            SEM.removeUnit(u)
        end
    end

    -- 计算需要补充的数量（使用当前关卡的敌方场地上限）
    local slotsAvail = getStageMaxFieldEnemies() - #alive
    local toAdd = math.min(slotsAvail, #enemyQueue)

    for _ = 1, toAdd do
        local unit = table.remove(enemyQueue, 1)
        alive[#alive + 1] = unit
    end

    enemies = alive
end

--- 初始化天赋/仇恨的战斗启动序列（必须在 resetAllyUnit 之后调用）
local function startBattleTalents()
    RCH.reset()
    RCH.initBattle(allies)
    ART.reset()
    ART.initBattle(allies)
    TAL.reset()
    for _, u in ipairs(allies) do
        TAL.initUnit(u)
    end
    for _, u in ipairs(enemies) do
        TAL.initUnit(u)
    end
    TM.onBattleStart(allies, enemies)
    TAL.onBattleStart(allies, enemies)
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

            local projOpts = result.category == "healing" and { target = target } or nil

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
-- 背景: KP_GW 水墨新卡为 572x1024 PNG（64 张 ~90MB），
-- Web/WASM 端单张解码 ~0.3s，同步一次性加载会冻结主线程 30-60s（表现为卡死）。
-- 分帧策略: 每帧预算 8ms，Web 端实际每帧消化 1 张，卡面渐进出现，战斗逻辑全程不冻结。
local battleCardQueue = nil   -- nil=未构建; table=加载中
local function ensureBattleCards(vg)
    if battleCardQueue then return end
    battleCardQueue = {}
    local q = battleCardQueue
    -- 预填 -1（对齐原 init 语义: 表始终有值，加载完成后覆盖；BattleDraw 依赖 img < 0 判空）
    for _, id in ipairs(HeroAssetUtil.getAssetIds()) do
        if imgHeroCards[id] == nil then imgHeroCards[id] = -1 end
    end
    for _, id in ipairs({1001, 1002, 1003, 1004, 1005, 1006, 1007, 201, 202, 203, 204, 205, 206}) do
        if imgMonsterCards[id] == nil then imgMonsterCards[id] = -1 end
    end
    for id = 1, 54 do
        if imgMonsterCards[id] == nil then imgMonsterCards[id] = -1 end
    end
    -- 英雄卡（编队卡面优先出现）
    for _, id in ipairs(HeroAssetUtil.getAssetIds()) do
        q[#q + 1] = {
            path = HeroAssetUtil.getCardPath(id),
            apply = function(h)
                if h and h >= 0 then imgHeroCards[id] = h end
            end,
        }
    end
    -- 怪物卡 (1~54 / 1001~1007 / 201~206)
    local monsterIds = {}
    for id = 1, 54 do monsterIds[#monsterIds + 1] = id end
    for _, id in ipairs({1001, 1002, 1003, 1004, 1005, 1006, 1007}) do
        monsterIds[#monsterIds + 1] = id
    end
    for id = 201, 206 do monsterIds[#monsterIds + 1] = id end
    for _, id in ipairs(monsterIds) do
        q[#q + 1] = {
            path = string.format("image/怪物卡牌/KP_GW_%d.png", id),
            apply = function(h) imgMonsterCards[id] = h end,
        }
    end
    -- 投射物/特效图（战斗中弹道首用会卡顿，一并预热）
    for _, key in ipairs(ProjectileSystem.getImageKeys()) do
        q[#q + 1] = {
            path = "image/特效投射物/" .. key .. ".png",
            fn = function() ProjectileSystem.prewarmOne(key) end,
        }
    end
    print("[BattleScene] 战斗卡牌分帧加载启动: " .. #q .. " 项")
end

--- 每帧消化加载队列；仅消化 DWP 已下载完成的项（未完成的跳过下一帧重试，
--- 杜绝泵内同步等待下载），时间预算内尽量多载
local function pumpBattleCards()
    if not battleCardQueue then return end
    local cache = GetCache()
    local t0 = time.elapsedTime
    local i = 1
    while i <= #battleCardQueue and time.elapsedTime - t0 < 0.008 do
        local job = battleCardQueue[i]
        local st = cache:GetDownloadState(job.path)
        if st == DOWNLOAD_COMPLETED or st == DOWNLOAD_FAILED or job.downloadSkip then
            -- 已就绪（或下载失败/未入清单，直接解码兜底）
            if st == DOWNLOAD_FAILED and not job.downloadSkip then
                job.downloadSkip = true   -- 失败项重试一次（不无限卡队列）
                i = i + 1
            else
                table.remove(battleCardQueue, i)
                if job.fn then
                    job.fn()
                else
                    local h = nvgCreateImage(vg_, job.path, 0)
                    if job.apply then job.apply(h) end
                end
            end
        else
            i = i + 1   -- 下载中：跳过，下一帧再试
        end
    end
    if #battleCardQueue == 0 then
        print("[BattleScene] 战斗卡牌分帧加载完成")
        battleCardQueue = nil
    end
end

--- 加载关卡
---@param stageId number 4位关卡ID, 如 0101
---@param skipBattleStart? boolean 跳过 TAL/TM 战斗启动（调用方自行在 resetAllyUnit 后调用 startBattleTalents）
local function loadStage(stageId, skipBattleStart)
    ensureBattleCards(vg_)
    local stageConfig = getStageConfig()
    local entry = stageConfig.getStage(stageId)
    if not entry then
        print("[BattleScene] 关卡不存在: " .. tostring(stageId))
        return
    end

    currentStageId = stageId
    stageName = entry.name
    isFirstClear = not clearedStages[stageId]
    idleRangeText_ = nil  -- 关卡变化时重新计算挂机范围文本

    searchingTimer = nil
    defeatTimer = nil
    reincarnationTimer = nil

    -- 切关时重置波次计时（丢弃未完成波次数据）
    resetWaveTimers()

    -- 章节变化时切换地图背景
    -- 挂机模式：使用范围内最早（最低）章节的背景素材
    local bgChapter = entry.chapter
    if not isFirstClear then
        local stages = StageUtils.collectPrevStages(maxStageId_, 5, stageConfig)
        if #stages > 0 then
            bgChapter = stages[#stages].chapter  -- 最低关的章节
        end
    end
    if bgChapter ~= currentChapter and vg_ then
        currentChapter = bgChapter
        if isFirstClear and entry.mapBg then
            -- 终焉神殿使用自定义地图背景
            BattleScene.setMapBackground(vg_, "image/关卡地图/" .. entry.mapBg)
        else
            -- 困难/噩梦/地狱复用普通难度地图：chapter 24+ 按 23 章循环映射
            local mapChapter = ((currentChapter - 1) % 23) + 1
            BattleScene.setMapBackground(vg_, "image/关卡地图/MAP_" .. mapChapter .. ".png")
        end
    end

    -- 生成全部敌人（挂机模式用5关混合，首通用单关卡）
    local allEnemies, maxField
    if not isFirstClear then
        allEnemies, maxField = generateIdleEnemyList()
    else
        allEnemies = generateEnemyList(entry)
        maxField = entry.maxFieldEnemies or 5
    end

    -- 前 maxField 个上场，其余入队列
    -- 特殊怪物（_isBonusMonster）占用 maxField 名额（避免超出屏幕），替换末位普通怪物
    enemies, enemyQueue = assignEnemiesToField(allEnemies, maxField)

    -- ---- 地图词缀：仅首通模式生效，挂机模式不应用 ----
    if isFirstClear then
        local affixConfig = ChallengerServerConfig.GetByServerId(PlayerInfoPanel.getServerId())
        if affixConfig and affixConfig.seasonAffixMode == "difficulty_count" then
            MAS.onStageLoad(entry.chapter, allies, "challenger_s1")
        else
            MAS.onStageLoad(entry.chapter, allies)
        end
        if MAS.hasAffixes() then
            local allEnemiesToBuff = {}
            for _, u in ipairs(enemies) do allEnemiesToBuff[#allEnemiesToBuff+1] = u end
            for _, u in ipairs(enemyQueue) do allEnemiesToBuff[#allEnemiesToBuff+1] = u end
            MAS.applyStaticAffixes(allEnemiesToBuff)
        end
    else
        MAS.onStageLoad(0, allies)  -- 挂机模式：清除词缀
    end

    -- [EnemyGuard] loadStage 重置 guard（每次加载新关都允许再次报警）
    _enemyGuardFired = false
    -- [EnemyGuard] loadStage 完成后验证 enemies 内容
    print(string.format("[EnemyGuard] loadStage stageId=%s enemies_len=%d enemies_ref=%s allies_len=%d",
        tostring(stageId), #enemies, tostring(enemies), #allies))
    for i, u in ipairs(enemies) do
        print(string.format("[EnemyGuard]   enemy[%d] monsterId=%s instanceId=%s heroId=%s hp=%s name=%s",
            i, tostring(u.monsterId), tostring(u.instanceId), tostring(u.heroId), tostring(u.hp), tostring(u.name)))
    end

    -- 安装哨兵（loadStage 路径，与 resetBattle 对齐）
    for _, u in ipairs(allies) do
        Diag.installSentinel(u)
    end
    for _, u in ipairs(enemies) do
        Diag.installSentinel(u)
    end
    for _, u in ipairs(enemyQueue) do
        Diag.installSentinel(u)
    end

    -- 重置战斗状态
    battleActive = true
    if isFirstClear then
        firstClearTimeLeft = GameConfig.Battle.TIME_LIMIT_SEC
    else
        firstClearTimeLeft = nil
    end
    BattleCombat.reset()
    BattleEffects.reset()
    ProjectileSystem.reset()
    TM.reset()   -- 清空仇恨表
    SEM.reset()  -- 清空状态效果
    RCH.initBattle(allies)  -- 初始化遗物条件词条（战斗开始时效果在此触发）
    ART.initBattle(allies)  -- 初始化神器战斗运行时效果
    for _, u in ipairs(allies) do
        u.atkProgress = 0
    end
    for _, u in ipairs(enemies) do
        u.atkProgress = 0
    end

    -- 入场动画（交错滑入）
    BattleCombat.playEnterAnims(enemies, -1)  -- 敌方从上方滑入
    BattleCombat.playEnterAnims(allies, 1)    -- 己方从下方滑入

    -- 重置台词气泡
    SpeechBubble.reset()

    if not skipBattleStart then
        -- 完整战斗启动：TAL/TM 初始化 + 入场台词
        startBattleTalents()

        -- [诊断] 战斗开始后即时完整性扫描
        Diag.scanNow(allies, enemies, "loadStage_postInit_s" .. tostring(stageId))

        local aliveHeroes = {}
        for _, u in ipairs(allies) do
            if u.hp > 0 and u.heroId then
                aliveHeroes[#aliveHeroes + 1] = u
            end
        end
        if #aliveHeroes > 0 then
            local speaker = aliveHeroes[math.random(#aliveHeroes)]
            SpeechBubble.trigger(speaker, "entry")
        end
    end

    -- 首通狂暴属于关卡加载状态，不应依赖 skipBattleStart。
    -- nextStage/reload/失败重进等路径会用 skipBattleStart=true 延后天赋启动，
    -- 但首通狂暴计时必须仍然在战斗恢复后正常推进。
    if isFirstClear then
        StageBerserk.enter(enemies, allies)
    else
        StageBerserk.exit()
    end

    recalcIdleIncome()

    print("[BattleScene] 加载关卡: " .. entry.name
        .. " | 场上: " .. #enemies
        .. " | 队列: " .. #enemyQueue
        .. " | 等级: " .. entry.monsterLevel)

    if onStageLoadedCallback then
        onStageLoadedCallback(stageId, isFirstClear)
    end
end

-- ======================== Public API ========================

function BattleScene.init(vg)
    vg_ = vg  -- 缓存，供 loadStage 切换地图背景
    -- 地图背景（loadStage 会根据章节自动切换）
    imgMap      = nvgCreateImage(vg, "image/关卡地图/MAP_1.png", 0)
    currentChapter = 1
    imgShadow   = nvgCreateImage(vg, "image/UI_YWJM_MAPYY.png", 0)
    -- [卡牌惰性加载] 英雄卡/怪物卡大图改为首次进战斗时加载（ensureBattleCards）
    -- ⚠️ 新增怪物 ID 时必须补充到 ensureBattleCards 的加载清单！
    -- 否则 BattleDraw 会 fallback 到 imgMonsterCards[1]（怪物1的贴图）。
    ensureBattleCards(vg)
    imgHpBg     = nvgCreateImage(vg, "image/UI_ZD_HP1.png", 0)
    imgHpFill   = nvgCreateImage(vg, "image/UI_ZD_HPT2.png", 0)
    imgEsFill   = nvgCreateImage(vg, "image/UI_ZD_HPT3.png", 0)
    imgAtkBg    = nvgCreateImage(vg, "image/UI_ZD_GJT1.png", 0)
    imgAtkFill  = nvgCreateImage(vg, "image/UI_ZD_GJT2.png", 0)
    imgBtnBack  = nvgCreateImage(vg, "image/UI_YWJM_XYGA.png", 0)
    imgBtnFwd     = nvgCreateImage(vg, "image/UI_YWJM_XYGB.png", 0)
    imgBtnFwdGrey = nvgCreateImage(vg, "image/UI_YWJM_XYG.png", 0)
    imgBtnIcon    = nvgCreateImage(vg, "image/UI_YWJM_XYG2.png", 0)
    BattleScene.imgSpeedIcon  = nvgCreateImage(vg, "image/UI_ICON_kong.png", 0)
    imgEnemyTag = nvgCreateImage(vg, "image/ICON_ZY_XG.png", 0)
    for i = 1, 6 do
        imgAllyTags[i] = nvgCreateImage(vg, "image/ICON_ZY_" .. i .. ".png", 0)
    end
    imgDeath    = nvgCreateImage(vg, "image/KP_Death.png", 0)

    -- 终焉神殿确认弹窗
    imgConfirmBg = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    imgBtnGreen  = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    imgBtnGray   = nvgCreateImage(vg, "image/UI_AN_FANG.png", 0)

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
        imgDeath        = imgDeath,
    })

    -- 初始化战利品箱子
    LootBox.init(vg)

    -- 初始化扫荡弹窗
    SweepDialog.init(vg)
    SweepDialog.onSweep = function()
        require("network.Client").sendAction(
            require("shared.Protocol").ACTION_TYPES.SWEEP, {})
    end

    -- 初始化战斗统计面板
    DamageStatsPanel.init(vg)

    -- 不再在 init 预加载关卡：等 setBattleData 首次到达后统一加载正确的关卡
    -- （避免选服前就加载占位角色和战斗场地）

    print("[BattleScene] init OK (deferred loadStage)")
end

function BattleScene.draw(vg)
    -- 1. 地图背景（上下漂移 + 场景切换过渡）
    -- 只向上漂移：0 → -8 → 0，不会向下露出黑底
    local driftY = -BG_DRIFT_Y_AMP * (1.0 - math.cos(bgAnimTimer * 2 * math.pi / BG_DRIFT_Y_PERIOD)) * 0.5
    -- 底图：带垂直漂移 [暗黑化 P1: 压暗 tint + 边缘晕影]
    DarkIcon.drawDarkScene(vg, imgMap, MAP_CX, MAP_CY + driftY, MAP_W, MAP_H, 1.0)
    -- 场景切换过渡叠加层
    if bgTransAnim then
        local t = math.min(bgTransAnim.timer / BG_TRANS_DURATION, 1.0)
        if t <= BG_FADE_OUT_RATIO then
            local p = t / BG_FADE_OUT_RATIO  -- 0→1
            local transScale = 1.0 + (bgTransAnim.zoomTarget - 1.0) * p
            local bgAlpha = 1.0 - p
            DarkIcon.drawDarkScene(vg, imgMap, MAP_CX, MAP_CY + driftY,
                MAP_W * transScale, MAP_H * transScale, bgAlpha)
        end
    end

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
    local remainCount = #enemyQueue
    local remainText = "剩余敌人 " .. tostring(remainCount)
    drawTextStroke(vg, 540, 525, remainText, 40,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)

    -- 4. 敌方卡片组
    drawCardGroup(vg, enemies, ENEMY_CARD_CY,
        ENEMY_TAG_OFFSET_Y, ENEMY_NAME_OFFSET_Y,
        ENEMY_HP_BG_OFFSET_Y, ENEMY_HP_VAL_OFFSET_Y,
        ENEMY_ATK_BG_OFFSET_Y, ENEMY_LVL_OFFSET_Y, imgEnemyTag, false)

    -- 5. 关卡名（挂机模式显示范围文本，首通模式显示关卡名）
    if not isFirstClear then
        if not idleRangeText_ then
            -- 缓存挂机范围文本，避免每帧重算
            local stageConfig = getStageConfig()
            local stages = StageUtils.collectPrevStages(maxStageId_, 5, stageConfig)
            if #stages > 0 then
                local last = stages[#stages]  -- 最低关（起始）
                local first = stages[1]       -- 最高关（结束）
                local diffName = getStageConfig().getDifficultyDisplayName(getStageConfig().getDifficulty(first.id))
                idleRangeText_ = string.format("%s %d-%d 至 %d-%d",
                    diffName, getRelativeChapter(last.chapter), last.stage,
                    getRelativeChapter(first.chapter), first.stage)
            else
                idleRangeText_ = "挂机中"
            end
        end
        drawTextStroke(vg, NAV.STAGE_CX, NAV.STAGE_CY, idleRangeText_, 40,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
        -- 挂机状态提示
        drawTextStroke(vg, NAV.STAGE_CX, NAV.STAGE_CY + 44, "挂机中...", 30,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 200, 220, 255, 3)
    else
        drawTextStroke(vg, NAV.STAGE_CX, NAV.STAGE_CY, stageName, 40,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
        if battleActive and firstClearTimeLeft then
            local secs = math.max(0, math.ceil(firstClearTimeLeft))
            local urgent = secs <= 30
            drawTextStroke(vg, NAV.STAGE_CX, NAV.STAGE_CY + 48,
                string.format("剩余 %d 秒", secs), 34,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                urgent and 255 or 255, urgent and 144 or 255, urgent and 144 or 255, 4,
                { strokeColor = { 0x31, 0x24, 0x24 } })
        end
        -- 首通狂暴读秒（与副本一致：常驻显示战斗用时，随狂暴阶段变文案/变色）
        if StageBerserk.isActive() then
            local bElapsed = StageBerserk.getElapsed()
            local bPhase   = StageBerserk.getRagePhase()
            local tText, tR, tG, tB
            if bPhase == 2 then
                tText = string.format("超级狂暴! %.0fs", bElapsed)
                tR, tG, tB = 255, 34, 34
            elseif bPhase == 1 then
                tText = string.format("狂暴中 %.0fs", bElapsed)
                tR, tG, tB = 255, 102, 0
            else
                tText = string.format("已用时 %.0fs", bElapsed)
                tR, tG, tB = 255, 255, 255
            end
            local subY = (battleActive and firstClearTimeLeft) and (NAV.STAGE_CY + 92) or (NAV.STAGE_CY + 48)
            drawTextStroke(vg, NAV.STAGE_CX, subY, tText, 34,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, tR, tG, tB, 4,
                { strokeColor = { 0x31, 0x24, 0x24 } })
        end
    end
    -- 6. 后退按钮（挂机模式隐藏，终焉神殿变暗）
    local isTerminal = getStageConfig().isTerminalTemple(currentStageId)
    if isFirstClear then
        local backAlpha = isTerminal and 0.3 or 1.0
        drawImageMirrored(vg, imgBtnBack, NAV.BACK_BG_CX, NAV.BACK_BG_CY, NAV.BACK_BG_W, NAV.BACK_BG_H, backAlpha)
        -- 7. 后退图标（水平镜像）
        drawImageMirrored(vg, imgBtnIcon, NAV.BACK_ICON_CX, NAV.BACK_ICON_CY, NAV.BACK_ICON_W, NAV.BACK_ICON_H, backAlpha)
        -- 8. 后退文本
        local backC = isTerminal and 100 or 255
        drawTextStroke(vg, NAV.BACK_TEXT_CX, NAV.BACK_TEXT_CY, "后退", 40,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, backC, backC, backC, 4)
    end

    -- 9. 前进按钮（仅挂机模式显示，终焉神殿时不可用）
    if not isFirstClear then
        local canAdvance = not isTerminal
        local fwdImg = canAdvance and imgBtnFwd or imgBtnFwdGrey
        drawImageCentered(vg, fwdImg, NAV.FWD_BG_CX, NAV.FWD_BG_CY, NAV.FWD_BG_W, NAV.FWD_BG_H, 1.0)
        -- 10. 前进图标（未首通时暗化）+ 可前进且下一关未进入时左右漂浮 + 闪烁动画
        local fwdAlpha = canAdvance and 1.0 or 0.4
        local stageConfig = getStageConfig()
        local nextId = stageConfig.getNextStageId(currentStageId)
        -- 仅当下一关超出玩家累计抵达记录时才播放提示动画（首通引导）
        -- 终焉神殿 ID 可能小于末关 ID（3999 < 9205），需单独高亮
        local fwdFloating = canAdvance and nextId ~= nil
            and (nextId > maxStageId_ or stageConfig.isTerminalTemple(nextId))
        local fwdFloatX = fwdFloating and math.sin(time.elapsedTime * 3.0) * 10 or 0
        -- 闪烁：用较快频率（5Hz）的 sin 波驱动，与摇摆同步
        local fwdBlink = fwdFloating and (0.5 + 0.5 * math.sin(time.elapsedTime * 10.0)) or 1.0
        -- 图标：alpha 在 0.55~1.0 之间脉冲
        local fwdIconAlpha = fwdAlpha * (fwdFloating and (0.55 + 0.45 * fwdBlink) or 1.0)
        drawImageCentered(vg, imgBtnIcon, NAV.FWD_ICON_CX + fwdFloatX, NAV.FWD_ICON_CY, NAV.FWD_ICON_W, NAV.FWD_ICON_H, fwdIconAlpha)
        -- 11. 前进文本 + 可前进时漂浮；文字颜色在白色与金黄之间闪烁
        local fwdCBase = canAdvance and 255 or 150
        local fwdCg = fwdFloating and math.floor(220 + (255 - 220) * fwdBlink) or fwdCBase
        local fwdCb = fwdFloating and math.floor(60  + (255 - 60)  * fwdBlink) or fwdCBase
        drawTextStroke(vg, NAV.FWD_TEXT_CX + fwdFloatX, NAV.FWD_TEXT_CY, "前进", 40,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, fwdCBase, fwdCg, fwdCb, 4)
    end

    -- 12. 己方战场阴影
    drawImageCentered(vg, imgShadow, ALLY_SHADOW_CX, ALLY_SHADOW_CY,
        ALLY_SHADOW_W, ALLY_SHADOW_H, 1.0)

    -- 13. "我的队伍" 文本
    drawTextStroke(vg, 540, 2046, "我的队伍", 40,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)

    -- 14. 己方卡片组
    drawCardGroup(vg, allies, ALLY_CARD_CY,
        ALLY_TAG_OFFSET_Y, ALLY_NAME_OFFSET_Y,
        ALLY_HP_BG_OFFSET_Y, ALLY_HP_VAL_OFFSET_Y,
        ALLY_ATK_BG_OFFSET_Y, ALLY_LVL_OFFSET_Y, imgAllyTags[1], true)

    -- 14.5 首通战斗倍速按钮
    BattleScene.drawSpeedButton(vg)

    -- 14.5~14.7 战斗特效
    if SettingsPanel.isEffectsEnabled() then
        -- 常驻召唤物（摘星星星人星门，漂浮在卡片旁并自转）
        ProjectileSystem.drawStarGates(vg, allies, ALLY_CARD_CY, getCardCX, true)
        ProjectileSystem.drawStarGates(vg, enemies, ENEMY_CARD_CY, getCardCX, false)

        -- 投射物（在卡片之上）
        ProjectileSystem.draw(vg)

        -- 攻击特效（在投射物之上、浮动文字之下）
        BattleEffects.draw(vg)

        -- 卡片 Spine 特效（升级/复活，在攻击特效之上）
        SpineCardEffect.draw(vg)
    end

    -- 15. 浮动伤害数字
    if SettingsPanel.isDamageNumbersEnabled() then
        drawFloatingTexts(vg)
    end

    -- 15.2 台词气泡（在浮动文字之上、战利品之下）
    SpeechBubble.draw(vg)

    -- 15.5 战利品箱子（图标 + 飞行动画 + 红点）
    LootBox.draw(vg)

    -- 15.5.1 扫荡按钮入口（与战利品箱子对称）
    SweepDialog.drawButton(vg)

    -- 15.5.2 战斗统计按钮入口（扫荡按钮左侧）
    DamageStatsPanel.drawButton(vg)

    -- 15.6 挂机收益显示（在 LootBox 之上绘制，避免被遮挡）
    local speedCardActive = BattleScene.GameState.getSpeedCardRemainSecs() > 0
    local speedBonusText = speedCardActive and "（+20%）" or ""
    if cachedGoldPerMin > 0 then
        local displayGoldPerMin = speedCardActive and math.floor(cachedGoldPerMin * 1.2 + 0.5) or cachedGoldPerMin
        drawTextStroke(vg, 221, 2104, "金币+" .. formatNumber(displayGoldPerMin) .. "/分钟" .. speedBonusText, 30,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 255, 243, 105, 3)
    end
    if cachedExpPerMin > 0 then
        local displayExpPerMin = speedCardActive and math.floor(cachedExpPerMin * 1.2 + 0.5) or cachedExpPerMin
        drawTextStroke(vg, 221, 2153, "经验+" .. formatNumber(displayExpPerMin) .. "/分钟" .. speedBonusText, 30,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 73, 255, 244, 3)
    end

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
    if not battleActive then
        if reincarnationTimer ~= nil then
            -- ---- 轮回过渡提示 ----
            local progress = math.min(1, reincarnationTimer / REINCARNATION_DELAY)
            -- 轮回光环效果（脉冲发光）
            local pulse = 0.6 + 0.4 * math.sin(reincarnationTimer * 4)
            local alpha = math.floor(180 * pulse)
            drawTextStroke(vg, 540, 1170, "轮回", 80,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 200, 160, 255, 6)
            -- 进度条
            local BAR_W, BAR_H = 360, 28
            local BAR_X = 540 - BAR_W * 0.5
            local BAR_Y = 1230
            nvgBeginPath(vg)
            nvgRoundedRect(vg, BAR_X, BAR_Y, BAR_W, BAR_H, 6)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
            nvgFill(vg)
            if progress > 0 then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, BAR_X + 2, BAR_Y + 2, (BAR_W - 4) * progress, BAR_H - 4, 5)
                nvgFillColor(vg, nvgRGBA(180, 140, 255, alpha))
                nvgFill(vg)
            end
            local nextTargetId = getStageConfig().getReincarnationTarget(getStageConfig().getDifficulty(currentStageId))
            local nextDiff = nextTargetId and getStageConfig().getDifficulty(nextTargetId) or nil
            local diffName = nextDiff and getStageConfig().getDifficultyDisplayName(nextDiff) or "未知"
            drawTextStroke(vg, 540, BAR_Y + BAR_H + 20, "即将进入" .. diffName .. "难度...", 30,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 200, 200, 255, 3)
        elseif searchingTimer ~= nil then
            -- ---- 寻怪中进度条 ----
            local progress = math.min(1, searchingTimer / SEARCH_ENEMY_DURATION)
            local BAR_W, BAR_H = 400, 36
            local BAR_X = 540 - BAR_W * 0.5
            local BAR_Y = 1190
            -- 背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, BAR_X, BAR_Y, BAR_W, BAR_H, 8)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
            nvgFill(vg)
            -- 填充
            if progress > 0 then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, BAR_X + 3, BAR_Y + 3, (BAR_W - 6) * progress, BAR_H - 6, 6)
                nvgFillColor(vg, nvgRGBA(100, 200, 255, 220))
                nvgFill(vg)
            end
            -- 文本
            drawTextStroke(vg, 540, BAR_Y + BAR_H * 0.5, "寻怪中...", 32,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
        elseif defeatTimer ~= nil then
            -- ---- 战败提示 ----
            local failText = defeatByTimeout and "时间到!" or "失败..."
            drawTextStroke(vg, 540, 1190, failText, 72,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 200, 80, 80, 6)
            drawTextStroke(vg, 540, 1250, stageName, 36,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 220, 220, 220, 4)
        else
            -- ---- 首通胜利提示 ----
            drawTextStroke(vg, 540, 1190, "胜利!", 72,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 220, 50, 6)
            drawTextStroke(vg, 540, 1250, stageName, 36,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 220, 220, 220, 4)
        end
    end

    -- ---- 扫荡弹窗（在寻怪进度条之上、终焉确认弹窗之下） ----
    SweepDialog.draw(vg)

    -- ---- 战斗统计面板（在扫荡弹窗之上、终焉确认弹窗之下） ----
    DamageStatsPanel.draw(vg)

    -- ---- 终焉神殿确认弹窗（最上层绘制） ----
    drawConfirmDialog(vg)

    -- ---- 副本结算面板（最顶层） ----
    BattleResultPanel.draw(vg)

    -- ---- 长按怪物属性弹窗（最最顶层） ----
    drawMonsterInfoPopup(vg)
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
    updateLongPress()

    -- ---- 终焉神殿确认弹窗关闭动画更新 ----
    if confirmDialog.closing then
        local _, _, done = getConfirmAnim()
        if done then
            confirmDialog.closing = false
            confirmDialog.open = false
            confirmDialog.pendingNextId = nil
        end
    end

    -- ---- 战利品箱子始终更新（飞行动画 + 领取检测，不受战斗状态影响） ----
    LootBox.update(dt)

    -- 暂停时只更新动画/浮字（保持视觉流畅），不推进战斗逻辑
    if isPaused then
        ProjectileSystem.update(dt)
        BattleEffects.update(dt)
        updateCardAnims(dt)
        updateFloatingTexts(dt)
        updateHitFlashes(dt)
        updateComboQueue(dt)
        SpeechBubble.update(dt)
        return
    end


    -- ---- 失败延迟后退 ----
    if defeatTimer ~= nil then
        defeatTimer = defeatTimer + dt
        ProjectileSystem.update(dt)
        BattleEffects.update(dt)
        updateCardAnims(dt)
        updateFloatingTexts(dt)
        updateHitFlashes(dt)
        updateComboQueue(dt)
        SpeechBubble.update(dt)
        if defeatTimer >= DEFEAT_DELAY then
            defeatTimer = nil
            defeatByTimeout = false
            local targetId
            if terminalDefeatPending then
                -- 终焉神殿失败：回退到该难度最后一关
                terminalDefeatPending = false
                targetId = getStageConfig().getTerminalPrevStageId(currentStageId) or currentStageId
                -- 解锁导航（终焉神殿中导航被锁定）
                BottomNav.setAllLocked(false)
                -- 恢复战斗 BGM（终焉神殿使用 samsara BGM）
                GameBGM.setScene("battle")
                print("[BattleScene] 终焉神殿失败，回退 → " .. tostring(targetId))
            elseif not isFirstClear then
                -- 挂机模式：阵亡不回退，重新加载当前关卡继续战斗
                targetId = currentStageId
                print("[BattleScene] 挂机模式阵亡，重新加载当前关 → " .. tostring(targetId))
            else
                targetId = getStageConfig().getPrevStageId(currentStageId) or currentStageId
                print("[BattleScene] 战斗失败，自动后退 → " .. tostring(targetId))
            end
            bgTransAnim = { timer = 0, zoomTarget = BG_ZOOM_BACK_TARGET }
            loadStage(targetId, true)  -- skipBattleStart
            regenAccum = 0
            for _, u in ipairs(allies) do resetAllyUnit(u) end
            startBattleTalents()
            if onStageChangedCallback then
                onStageChangedCallback(targetId)
            end
        end
        return
    end

    -- ---- 轮回计时（终焉神殿专用） ----
    if reincarnationTimer ~= nil then
        reincarnationTimer = reincarnationTimer + dt
        ProjectileSystem.update(dt)
        BattleEffects.update(dt)
        updateCardAnims(dt)
        updateFloatingTexts(dt)
        updateHitFlashes(dt)
        updateComboQueue(dt)
        SpeechBubble.update(dt)
        if reincarnationTimer >= REINCARNATION_DELAY then
            reincarnationTimer = nil
            -- 解锁导航
            BottomNav.setAllLocked(false)
            -- 确定轮回目标
            local currentDiff = getStageConfig().getDifficulty(currentStageId)
            local targetStageId = getStageConfig().getReincarnationTarget(currentDiff)
            if not targetStageId then
                print("[BattleScene] 轮回目标无效，当前难度: " .. tostring(currentDiff))
                return
            end
            local targetDiff = getStageConfig().getDifficulty(targetStageId)

            if onReincarnateCallback then
                -- 有外部回调（Client/Standalone）：先播放开场动画，延迟加载关卡
                ---@diagnostic disable-next-line: assign-type-mismatch
                pendingReincarnation = {
                    targetStageId = targetStageId,
                    terminalStageId = currentStageId,
                    fromDifficulty = currentDiff,
                    toDifficulty = targetDiff,
                }
                print("[BattleScene] 轮回倒计时结束，等待外部动画完成后调用 completeReincarnation")
                onReincarnateCallback({
                    fromDifficulty = currentDiff,
                    toDifficulty = targetDiff,
                    newStageId = targetStageId,
                })
            else
                -- 无回调（安全回退）：直接加载关卡
                clearedStages[currentStageId] = true
                if targetStageId > maxStageId_ then
                    maxStageId_ = targetStageId
                    recalcIdleIncome()
                end
                GameBGM.setScene("battle")
                bgTransAnim = { timer = 0, zoomTarget = BG_ZOOM_FWD_TARGET }
                loadStage(targetStageId, true)
                regenAccum = 0
                for _, u in ipairs(allies) do resetAllyUnit(u) end
                startBattleTalents()
                if onStageChangedCallback then
                    onStageChangedCallback(targetStageId)
                end
                print("[BattleScene] 轮回完成（无回调）→ " .. stageName .. " (难度: " .. tostring(targetDiff) .. ")")
            end
        end
        return
    end

    -- ---- 挂机寻怪倒计时 ----
    if searchingTimer ~= nil then
        searchingTimer = searchingTimer + dt
        ProjectileSystem.update(dt)
        BattleEffects.update(dt)
        updateCardAnims(dt)
        updateFloatingTexts(dt)
        updateHitFlashes(dt)
        updateComboQueue(dt)
        SpeechBubble.update(dt)
        if searchingTimer >= SEARCH_ENEMY_DURATION then
            searchingTimer = nil
            regenAccum = 0
            -- 开战前刷新属性（装备/槽位强化等可能在寻怪期间才同步完成）
            BattleScene.refreshAllyStats()
            for _, u in ipairs(allies) do resetAllyUnit(u) end
            -- 生成新一波敌人（挂机用5关混合；首通保留 loadStage 已生成的阵容）
            do
                if not isFirstClear then
                    local allEnemies, maxField = generateIdleEnemyList()
                    enemies, enemyQueue = assignEnemiesToField(allEnemies, maxField)
                else
                    -- 首通：loadStage 已按 assignEnemiesToField 放置特殊怪，寻怪结束后勿重新生成
                    for _, u in ipairs(enemies) do
                        u.atkProgress = 0
                    end
                end
                battleActive = true
                BattleCombat.reset()
                BattleEffects.reset()
                ProjectileSystem.reset()
                TM.reset()
                SEM.reset()
                TAL.reset()
                RCH.reset()
                ART.reset()
                RCH.initBattle(allies)
                ART.initBattle(allies)
                for _, u in ipairs(allies) do
                    Diag.installSentinel(u)
                    TAL.initUnit(u)
                end
                for _, u in ipairs(enemies) do
                    Diag.installSentinel(u)
                    u.atkProgress = 0
                    TAL.initUnit(u)
                end
                for _, u in ipairs(enemyQueue) do
                    Diag.installSentinel(u)
                end
                -- 新波次敌人入场动画
                BattleCombat.playEnterAnims(enemies, -1)
                TM.onBattleStart(allies, enemies)
                TAL.onBattleStart(allies, enemies)
                -- [诊断] 搜索完成后即时扫描
                Diag.scanNow(allies, enemies, "searchTimer_newWave")
                print("[BattleScene] " .. (isFirstClear and "首通寻怪完成，开战" or "挂机新波次开始"))
            end
        end
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
    ART.update(logicDt)


    -- ---- 敌人死亡处理（死亡即补位：怪物池有剩余立刻替换新怪，不播墓碑动画） ----
    for i, unit in ipairs(enemies) do
        if unit.hp <= 0 then
            -- 首次检测到死亡：发放击杀奖励（替换与墓碑共用，仅一次）
            if not unit.reviveTimer then
                unit.reviveTimer = 0  -- 标记已处理
                unit.atkProgress = 0
                TM.removeUnit(unit)   -- 清除仇恨记录（仅一次）
                TAL.onEnemyDeath(unit, allies, enemies)  -- 转职天赋: 敌人死亡钩子（影袭等）
                SEM.removeUnit(unit)  -- 清除状态效果

                -- 波次效率累计（本地 UI 统计）
                waveKillCount = waveKillCount + 1
                waveGoldEarned = waveGoldEarned + (unit.goldReward or 0)
                waveExpEarned  = waveExpEarned + (unit.expReward or 0)

                -- 发放击杀奖励（经验 + 金币）
                if onEnemyKillCallback and (unit.expReward or unit.goldReward) then
                    local allyCount = #allies
                    local expMult = ExpTable.getHeroCountExpMult(allyCount)
                    -- 收集上场冒险家 heroId 列表
                    local heroIds = {}
                    for _, ally in ipairs(allies) do
                        if ally.heroId then
                            heroIds[#heroIds + 1] = ally.heroId
                        end
                    end
                    onEnemyKillCallback({
                        expReward  = unit.expReward or 0,
                        goldReward = unit.goldReward or 0,
                        allyCount  = allyCount,
                        expMult    = expMult,
                        heroIds    = heroIds,
                        stageId    = currentStageId,
                    })
                end

                -- 掉落回调（通知外部生成装备掉落）
                if onEnemyDropCallback then
                    local enemyCX = getCardCX(enemies, i)
                    print("[BattleScene] enemy died, calling dropCallback stageId=" .. tostring(currentStageId))
                    onEnemyDropCallback({
                        stageId = currentStageId,
                        enemyCX = enemyCX,
                        enemyCY = ENEMY_CARD_CY,
                    })
                else
                    print("[BattleScene] enemy died, but onEnemyDropCallback is nil!")
                end

                -- 击杀台词触发（击杀者说台词）
                if unit._killedBy and unit._killedBy.heroId then
                    SpeechBubble.trigger(unit._killedBy, "kill")
                end

                -- 死亡退场动画：条带布局下向右滑出（0.4s）；池空走原竖直墓碑流程
                local okRatio = unit._overkillRatio or 0
                BattleCombat.setCardAnim(unit, { state = "dying", timer = 0, lungeDir = -1,
                    knockbackMult = 1.0 + okRatio * 2.0, noTombstone = (#enemyQueue > 0) })
            end

            unit.reviveTimer = unit.reviveTimer + logicDt

            if #enemyQueue > 0 then
                -- [死亡即补位 v2] 退场(向右滑出0.4s) → 1s 空位 → 新怪从右滑入补位
                if unit.reviveTimer >= RESPAWN_DELAY then
                    local newUnit = table.remove(enemyQueue, 1)
                    Diag.installSentinel(newUnit)
                    TAL.initUnit(newUnit)
                    TAL.checkMarkTarget(allies, enemies)
                    newUnit.atkProgress = 0
                    enemies[i] = newUnit
                    -- 清理旧单位残留的动画状态
                    BattleCombat.clearCardAnim(unit)
                    BattleCombat.clearHitFlash(unit)
                    -- 新怪从右侧滑入入场
                    BattleCombat.setCardAnim(newUnit, { state = "reviving", timer = 0, lungeDir = -1 })
                end
            else
                -- 怪物池为空：保留墓碑表现（进度条渐进至 100% 停驻）
                unit.atkProgress = math.min(1.0, (unit.atkProgress or 0) + logicDt / TOMBSTONE_REVIVE_TIME)
            end
        end
    end

    -- ---- 墓碑处理（己方）：死亡淡出动画，不复活 ----
    for _, unit in ipairs(allies) do
        if unit.hp <= 0 and not unit.reviveTimer then
            -- 神器: 死亡拦截（神圣十架复活 / 亡魂之祭）
            local artifactRevived = ART.onAllyDeath(unit)
            if artifactRevived then
                local idx = 1
                for ai, a in ipairs(allies) do
                    if a == unit then idx = ai; break end
                end
                local cx = BattleCombat.getCardCX(allies, idx)
                SpineCardEffect.playRevive(cx, ALLY_CARD_CY)
            else
                -- 天赋: 死亡拦截（复活吧爱人复活）
                local revived = TAL.onAllyDeath(unit, allies, syncUnitHp)
                if revived then
                    -- 复活成功，跳过死亡处理；播放复活 Spine 特效
                    local idx = 1
                    for ai, a in ipairs(allies) do
                        if a == unit then idx = ai; break end
                    end
                    local cx = BattleCombat.getCardCX(allies, idx)
                    SpineCardEffect.playRevive(cx, ALLY_CARD_CY)
                else
                    -- 阵亡台词触发
                    SpeechBubble.trigger(unit, "death")

                    unit.reviveTimer = 0       -- 标记已处理，防止重复调用
                    unit.atkProgress = 0
                    TM.removeUnit(unit)
                    SEM.removeUnit(unit)
                    -- 启动死亡动画：角色向下滑出（lungeDir=+1），超额伤害增加击退
                    local okRatio = unit._overkillRatio or 0
                    BattleCombat.setCardAnim(unit, { state = "dying", timer = 0, lungeDir = 1, knockbackMult = 1.0 + okRatio * 2.0 })
                end
            end
        end
    end

    -- 检查是否有存活单位
    local allyAlive  = getAliveUnits(allies)
    local enemyAlive = getAliveUnits(enemies)

    -- 胜利条件：场上敌人全灭 + 队列为空
    if #enemyAlive == 0 and #enemyQueue == 0 then
        settleWaveEfficiency()
        resetWaveTimers()



        local wasFirstClear = isFirstClear
        if isFirstClear then
            -- 首通完成：标记关卡已通关，解锁前进按钮
            clearedStages[currentStageId] = true
            isFirstClear = false
            StageBerserk.exit()
            print("[BattleScene] 首通完成: " .. stageName)
            -- 通知外部持久化（Client 会发送 NEXT_STAGE 到服务端）
            if onFirstClearCallback then
                onFirstClearCallback(currentStageId)
            end
        end
        -- 胜利台词触发（随机选一名存活英雄）
        local aliveHeroesV = {}
        for _, u in ipairs(allies) do
            if u.hp > 0 and u.heroId then
                aliveHeroesV[#aliveHeroesV + 1] = u
            end
        end
        if #aliveHeroesV > 0 then
            local speaker = aliveHeroesV[math.random(#aliveHeroesV)]
            SpeechBubble.trigger(speaker, "victory")
        end

        -- 终焉神殿：胜利 → 进入轮回计时
        if getStageConfig().isTerminalTemple(currentStageId) then
            if reincarnationTimer == nil then
                reincarnationTimer = 0
                battleActive = false
                print("[BattleScene] 终焉神殿胜利，进入轮回倒计时")
            end
            return
        end

        -- 首通成功：自动前进到下一关（不回到寻怪模式）
        if wasFirstClear then
            BattleScene.nextStage()
        elseif searchingTimer == nil then
            -- 挂机模式：进入寻怪倒计时
            searchingTimer = 0
            battleActive = false
        end
        return
    end
    -- 失败条件：己方全灭
    if #allyAlive == 0 then
            StageBerserk.exit()
        -- 战败也结算已有的效率数据（不完整波次仍有参考价值）
        settleWaveEfficiency()

        -- 终焉神殿：失败 → 回退到上一关（该难度最后一关）
        if getStageConfig().isTerminalTemple(currentStageId) then
            if defeatTimer == nil then
                defeatTimer = 0
                battleActive = false
                terminalDefeatPending = true
                defeatByTimeout = false
                print("[BattleScene] 终焉神殿失败，准备回退到上一关")
            end
            return
        end
        if defeatTimer == nil then
            defeatTimer = 0
            battleActive = false
            defeatByTimeout = false
            if onAllDeadCallback then onAllDeadCallback() end
        end
        return
    end



    -- ---- 更新攻击进度 ----
    -- 预先统计双方存活数，无目标时进度条停在满格等待
    local hasAliveEnemy = false
    for _, u in ipairs(enemies) do
        if u.hp > 0 then hasAliveEnemy = true; break end
    end
    local hasAliveAlly = false
    for _, u in ipairs(allies) do
        if u.hp > 0 then hasAliveAlly = true; break end
    end

    for _, unit in ipairs(allies) do
        if unit.hp > 0 and not SEM.isFrozen(unit) then
            local interval = getLiveAttackInterval(unit, DEFAULT_ALLY_INTERVAL)
            BattleCombat.advanceAttackProgress(unit, logicDt, interval, hasAliveEnemy, function()
                performAttack(unit, enemies, true)
            end)
        end
    end

    -- [EnemyGuard] 每帧检查 enemies 是否被污染（仅首次触发）
    checkEnemiesCorruption("UPDATE_LOOP")

    for _, unit in ipairs(enemies) do
        if unit.hp > 0 and not SEM.isFrozen(unit) then
            local interval = getLiveAttackInterval(unit, DEFAULT_ENEMY_INTERVAL)
            BattleCombat.advanceAttackProgress(unit, logicDt, interval, hasAliveAlly, function()
                performAttack(unit, allies, false)
            end)
        end
    end

    -- ---- 遗物条件词条每帧检查（HP阈值、限时buff到期等） ----
    RCH.update(allies, 0)

    -- ---- 更新血条缓冲（白色拖尾） ----
    BattleCombat.updateHpBuffers(allies, logicDt)
    BattleCombat.updateHpBuffers(enemies, logicDt)

    -- ---- 更新仇恨衰减 ----
    TM.update(logicDt)

    -- ---- 更新状态效果（DOT/HOT tick） ----
    SEM.update(logicDt, {
        onDot = function(unit, source, dmg)
            -- 判断目标是否为己方
            local isUnitAlly = false
            for _, u in ipairs(allies) do
                if u == unit then isUnitAlly = true; break end
            end
            dealDamageToUnit(unit, dmg, isUnitAlly, "灼烧 ", {255, 120, 30}, source, { isDot = true })
        end,
        onHot = function(unit, source, heal)
            if unit.attrs and unit.hp > 0 then
                local actual = unit.attrs:heal(heal)
                syncUnitHp(unit)
                if actual > 0 then
                    local isUnitAlly = false
                    for _, u in ipairs(allies) do
                        if u == unit then isUnitAlly = true; break end
                    end
                    local cy = isUnitAlly and ALLY_CARD_CY or ENEMY_CARD_CY
                    local list = isUnitAlly and allies or enemies
                    local cx = DESIGN_W * 0.5
                    for ii, u in ipairs(list) do
                        if u == unit then cx = getCardCX(list, ii); break end
                    end
                    addFloatingText("恢复 +" .. NumberUtil.format(actual), cx, cy, {0, 255, 82}, false)
                    -- 战斗统计：HOT 持续治疗输出（来源为己方英雄时归因）
                    if source and source.heroId then
                        BattleStats.recordHeal(source, actual, true)
                    end
                end
            end
        end,
    })

    -- ---- 更新天赋计时器（转职天赋: 10秒周期/巡游射击延迟/暗影倒计时等） ----
    TAL.update(logicDt, allies, enemies, {
        healUnit = function(unit, amount)
            if unit.attrs and unit.hp > 0 then
                local actual = unit.attrs:heal(amount)
                syncUnitHp(unit)
                return actual
            end
            return 0
        end,
        dealDamage = function(target, damage, isTargetAlly, prefix, color, source)
            return dealDamageToUnit(target, damage, isTargetAlly, prefix, color, source)
        end,
        dealTalentDamage = function(attacker, target, damage, isTargetAlly, prefix, color, projOpts)
            return BattleCombat.dealTalentDamage(attacker, target, damage, isTargetAlly, prefix, color, projOpts, allies, enemies)
        end,
        syncHp = function(unit)
            syncUnitHp(unit)
        end,
        performAttack = function(attacker, targetList, isAlly)
            performAttack(attacker, targetList, isAlly)
        end,
    })

    -- ---- 地图词缀动态 tick（仅首通模式） ----
    if isFirstClear and MAS.hasAffixes() then
        MAS.tick(logicDt, allies, enemies)
    end

    -- ---- 能量护盾恢复 tick ----
    for _, u in ipairs(allies) do
        if u.hp > 0 and u.attrs then u.attrs:tickEnergyShield(logicDt) end
    end
    for _, u in ipairs(enemies) do
        if u.hp > 0 and u.attrs then u.attrs:tickEnergyShield(logicDt) end
    end

    -- ---- 每秒回血（HP_REGEN 属性） ----
    regenAccum = regenAccum + logicDt
    while regenAccum >= 1.0 do
        regenAccum = regenAccum - 1.0
        local allUnits = {}
        for _, u in ipairs(allies)  do allUnits[#allUnits + 1] = { unit = u, isAlly = true  } end
        for _, u in ipairs(enemies) do allUnits[#allUnits + 1] = { unit = u, isAlly = false } end
        for _, entry in ipairs(allUnits) do
            local u = entry.unit
            if u.hp > 0 and u.attrs then
                local regenAmt = CF.calcHpRegen(u.attrs)
                if regenAmt > 0 then
                    local actual = u.attrs:heal(regenAmt)
                    if actual > 0 then
                        syncUnitHp(u)
                        -- 显示回血浮字，让玩家看到 HP_REGEN 的实际回复量
                        local list = entry.isAlly and allies or enemies
                        local cy = entry.isAlly and ALLY_CARD_CY or ENEMY_CARD_CY
                        local cx = DESIGN_W * 0.5
                        for ii, uu in ipairs(list) do
                            if uu == u then cx = getCardCX(list, ii); break end
                        end
                        addFloatingText("回复 +" .. NumberUtil.format(actual), cx, cy, {0, 255, 82}, false)
                    end
                end
            end
        end
    end

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
    end
    imgMap = nvgCreateImage(vg, path, 0)
end

--- 重置战斗状态（新单位加入时调用）
local function resetBattle()
    battleActive = true
    if isFirstClear then
        firstClearTimeLeft = GameConfig.Battle.TIME_LIMIT_SEC
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

--- [Standalone 状态同步] 本地已通关表（key 可能为 number，写入状态前需 tostring）
---@return table
function BattleScene.getClearedStages()
    return clearedStages
end

--- [三行并行] 选关页面: 跳转到指定关卡（仅允许 ≤ 已解锁最大关卡）
function BattleScene.gotoStage(stageId)
    stageId = tonumber(stageId)
    if not stageId or stageId < 1 then return false, "无效关卡" end
    if stageId > maxStageId_ then return false, "关卡尚未解锁" end
    loadStage(stageId, true)
    if onStageChangedCallback then
        onStageChangedCallback(stageId)
    end
    return true
end

--- 当前是否处于终焉神殿关卡
function BattleScene.isInTerminalTemple()
    return getStageConfig().isTerminalTemple(currentStageId)
end

--- 实际执行进入终焉神殿（确认后调用）
local function doEnterTerminalTemple(nextId)
    searchingTimer = nil
    defeatTimer = nil
    bgTransAnim = { timer = 0, zoomTarget = BG_ZOOM_FWD_TARGET }
    loadStage(nextId, true)
    regenAccum = 0
    for _, u in ipairs(allies) do resetAllyUnit(u) end
    startBattleTalents()
    BottomNav.setAllLocked(true)
    GameBGM.setScene("samsara", { fromStart = true })
    if onStageChangedCallback then
        onStageChangedCallback(nextId)
    end
    print("[BattleScene] 确认进入终焉神殿 → " .. stageName)
end

--- 前进到下一关
function BattleScene.nextStage()
    local stageConfig = getStageConfig()
    local nextId = stageConfig.getNextStageId(currentStageId)
    if nextId then
        -- 终焉神殿：只有历史最高关卡已进入下一难度时才跳过
        if stageConfig.isTerminalTemple(nextId) then
            local currentDiff = stageConfig.getDifficulty(currentStageId)
            local skipToId, shouldSkip = stageConfig.shouldSkipTerminal(currentStageId, maxStageId_, clearedStages)
            if skipToId and shouldSkip then
                print("[BattleScene] 终焉神殿已跳过(maxStage=" .. maxStageId_
                    .. " upper=" .. tostring(stageConfig.getProgressUpperBound(maxStageId_, clearedStages, nil))
                    .. " skipTo=" .. tostring(skipToId) .. ") → " .. tostring(skipToId))
                nextId = skipToId
            else
                -- 未通关：弹出确认弹窗
                confirmDialog.open = true
                confirmDialog.closing = false
                confirmDialog.openTime = time.elapsedTime
                confirmDialog.pendingNextId = nextId
                print("[BattleScene] 终焉神殿确认弹窗打开, nextId=" .. tostring(nextId))
                return
            end
        end
        searchingTimer = nil
        defeatTimer = nil
        -- 背景过渡：放大淡出 → 淡入
        bgTransAnim = { timer = 0, zoomTarget = BG_ZOOM_FWD_TARGET }
        loadStage(nextId, true)  -- skipBattleStart: TAL/TM 延后到 resetAllyUnit 之后
        regenAccum = 0
        for _, u in ipairs(allies) do resetAllyUnit(u) end
        startBattleTalents()  -- 在干净 attrs 上应用天赋 buff
        -- 通知外部持久化当前关卡进度
        if onStageChangedCallback then
            onStageChangedCallback(nextId)
        end
        print("[BattleScene] 前进 → " .. stageName)
    else
        print("[BattleScene] 已是最后一关")
    end
end

--- 后退到上一关
function BattleScene.prevStage()
    local stageConfig = getStageConfig()
    local prevId = stageConfig.getPrevStageId(currentStageId)
    -- 跨难度回退：当前是某难度第一关时，回退到上一难度末关
    if not prevId then
        prevId = stageConfig.getLastStageOfPrevDifficulty(currentStageId)
    end
    if prevId then
        searchingTimer = nil
        defeatTimer = nil
        -- 背景过渡：缩小淡出 → 淡入
        bgTransAnim = { timer = 0, zoomTarget = BG_ZOOM_BACK_TARGET }
        loadStage(prevId, true)  -- skipBattleStart: TAL/TM 延后到 resetAllyUnit 之后
        regenAccum = 0
        for _, u in ipairs(allies) do resetAllyUnit(u) end
        startBattleTalents()  -- 在干净 attrs 上应用天赋 buff
        -- 通知外部持久化当前关卡进度
        if onStageChangedCallback then
            onStageChangedCallback(prevId)
        end
        print("[BattleScene] 后退 → " .. stageName)
    else
        print("[BattleScene] 已是第一关")
    end
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
    if confirmDialog.open or confirmDialog.closing then
        if confirmDialog.closing then return true end
        -- 打开动画未完成时不响应按钮（但消费事件防穿透）
        if (time.elapsedTime - confirmDialog.openTime) < CONFIRM_OPEN_DUR then return true end
        -- 确认按钮「进入」
        if dx >= CDL.OK_CX - CDL.OK_W * 0.5 and dx <= CDL.OK_CX + CDL.OK_W * 0.5
           and dy >= CDL.OK_CY - CDL.OK_H * 0.5 and dy <= CDL.OK_CY + CDL.OK_H * 0.5 then
            local nextId = confirmDialog.pendingNextId
            confirmDialog.open = false
            confirmDialog.pendingNextId = nil
            if nextId then
                doEnterTerminalTemple(nextId)
            end
            return true
        end
        -- 取消按钮
        if dx >= CDL.CANCEL_CX - CDL.CANCEL_W * 0.5 and dx <= CDL.CANCEL_CX + CDL.CANCEL_W * 0.5
           and dy >= CDL.CANCEL_CY - CDL.CANCEL_H * 0.5 and dy <= CDL.CANCEL_CY + CDL.CANCEL_H * 0.5 then
            confirmDialog.closing = true
            confirmDialog.closeTime = time.elapsedTime
            return true
        end
        -- 点击弹窗外区域 → 取消
        if dx < CDL.BG_CX - CDL.BG_W * 0.5 or dx > CDL.BG_CX + CDL.BG_W * 0.5
           or dy < CDL.BG_CY - CDL.BG_H * 0.5 or dy > CDL.BG_CY + CDL.BG_H * 0.5 then
            confirmDialog.closing = true
            confirmDialog.closeTime = time.elapsedTime
        end
        return true  -- 消费所有点击，阻止穿透
    end

    -- 扫荡弹窗（已打开时拦截所有输入；入口按钮点击）
    if SweepDialog.handleInput(dx, dy) then return true end
    -- 战斗统计面板（已打开时拦截所有输入，需在按钮判定之前）
    if DamageStatsPanel.handleInput(dx, dy) then return true end
    if SweepDialog.handleButtonInput(dx, dy) then return true end
    if DamageStatsPanel.handleButtonInput(dx, dy) then return true end

    -- 战利品箱子点击（优先于导航按钮）
    if LootBox.handleInput(dx, dy) then return true end

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
---   allyCount  = 当前上场冒险家数量
---   expMult    = 冒险家数量经验倍率
---   heroIds    = 上场冒险家 heroId 列表
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
    if not pendingReincarnation then
        print("[BattleScene] completeReincarnation called but no pending data")
        return
    end
    local pr = pendingReincarnation
    pendingReincarnation = nil

    if pr.terminalStageId then
        clearedStages[pr.terminalStageId] = true
    end
    if pr.targetStageId and pr.targetStageId > maxStageId_ then
        maxStageId_ = pr.targetStageId
        recalcIdleIncome()
    end

    -- 切换 BGM 回战斗
    GameBGM.setScene("battle")
    -- 背景过渡
    bgTransAnim = { timer = 0, zoomTarget = BG_ZOOM_FWD_TARGET }
    loadStage(pr.targetStageId, true)
    regenAccum = 0
    for _, u in ipairs(allies) do resetAllyUnit(u) end
    startBattleTalents()
    -- 通知关卡变更
    if onStageChangedCallback then
        onStageChangedCallback(pr.targetStageId)
    end
    print("[BattleScene] 轮回完成 → " .. stageName .. " (难度: " .. tostring(pr.toDifficulty) .. ")")
end

--- 从服务端推送的战斗数据恢复状态
---@param data table  { currentStageId, maxStageId, clearedStages, autoBattle }
function BattleScene.setBattleData(data)
    if not data then return end

    -- 恢复已通关关卡集合
    if data.clearedStages then
        clearedStages = {}
        for k, v in pairs(data.clearedStages) do
            -- 服务端以 tostring(stageId) 为 key 存储，本地以 number 为 key
            local numKey = tonumber(k)
            if numKey and v then
                clearedStages[numKey] = true
            end
        end
    end

    -- 用 maxStageId 补全 clearedStages（后备推断：低于 maxStageId 的关卡必定已通关）
    local maxSId = data.maxStageId and tonumber(data.maxStageId)
    if maxSId then
        -- 与服务端存档对齐（Debug 跳回低进度时需降低 maxStageId_）
        maxStageId_ = maxSId
        -- 更新挂机收益显示（maxStageId 变化后立即刷新，不等下一关加载）
        recalcIdleIncome()
        local stageConfig = getStageConfig()
        local sid = stageConfig.getFirstStageId
            and stageConfig.getFirstStageId(stageConfig.DIFFICULTY_NORMAL)
            or 0101
        while sid and sid < maxSId do
            if not clearedStages[sid] then
                clearedStages[sid] = true
            end
            local nextSid = stageConfig.getNextStageId(sid)
            if not nextSid and stageConfig.isTerminalTemple(sid) then
                -- 终焉神殿无 next，跨难度继续填充
                local diff = stageConfig.getDifficulty(sid)
                nextSid = stageConfig.getReincarnationTarget(diff)
            end
            sid = nextSid
        end
    end

    -- 恢复当前关卡（如果与本地不同则切换）
    local serverStageId = data.currentStageId and tonumber(data.currentStageId)

    -- 🔴 修复中间状态：通关消息已落盘但推进消息未到（两条消息间掉线/存档）
    -- 表现：currentStageId == maxStageId 且 clearedStages[maxStageId] == true
    -- 此时客户端误判为挂机模式（isFirstClear=false），实际应为首通模式
    -- 修复：从本地 clearedStages 中移除该标记，让 isFirstClear 正确计算为 true
    -- 安全性：服务端 clearedStages 不变，不会重复发放首通奖励
    -- ⚠️ 守卫：如果 maxStageId 的下一关是终焉神殿，说明玩家已打到难度末关并从神殿
    --   返回/重连，此时应保持挂机模式（显示前进按钮→进入终焉神殿确认框），不触发修复
    local stageConfig = getStageConfig()
    local nextOfMax = maxSId and stageConfig.getNextStageId(maxSId)
    local isAtTerminalEntrance = nextOfMax and stageConfig.isTerminalTemple(nextOfMax)
    if maxSId and serverStageId and serverStageId == maxSId and clearedStages[maxSId]
       and not isAtTerminalEntrance then
        clearedStages[maxSId] = nil
        print("[BattleScene] 修复中间状态: 关卡" .. tostring(maxSId)
            .. "已标记通关但未推进(currentStageId==maxStageId)，恢复为首通模式")
    end

    -- 首次加载兜底：如果 currentStageId 落后于 maxStageId，
    -- 说明上次存档异常或版本更新导致进度不同步，以 maxStageId 为准恢复到最新进度
    if not initialBattleDataLoaded and serverStageId and maxSId then
        if maxSId > serverStageId then
            print("[BattleScene] 检测到进度落后: currentStageId=" .. tostring(serverStageId)
                .. " 但 maxStageId=" .. tostring(maxSId) .. "，使用 maxStageId 恢复")
            serverStageId = maxSId
        end
    end

    if serverStageId and serverStageId ~= currentStageId then
        -- 首次加载数据时无条件恢复（否则 init 里 loadStage(0101) 已启动战斗，isBusy=true 会拦截）
        if not initialBattleDataLoaded then
            loadStage(serverStageId)
            regenAccum = 0
            -- 首次加载进入寻怪模式，等服务端装备/天赋数据同步完毕再开战
            battleActive = false
            searchingTimer = 0
            print("[BattleScene] 首次加载，恢复关卡(寻怪模式): " .. tostring(serverStageId))
        else
            -- 后续推送：仅在战斗未激活时才接受切换，避免打断进行中的战斗或轮回倒计时
            local isBusy = battleActive or (searchingTimer ~= nil) or (defeatTimer ~= nil) or (reincarnationTimer ~= nil)
            if not isBusy then
                loadStage(serverStageId, true)  -- skipBattleStart
                regenAccum = 0
                for _, u in ipairs(allies) do resetAllyUnit(u) end
                startBattleTalents()
                print("[BattleScene] 从服务端恢复关卡: " .. tostring(serverStageId))
            else
                local reason = battleActive and "battleActive" or (searchingTimer ~= nil) and "searching" or (defeatTimer ~= nil) and "defeat" or "reincarnation"
                print("[BattleScene] 战斗进行中，忽略服务端关卡切换: server=" .. tostring(serverStageId) .. " local=" .. tostring(currentStageId) .. " reason=" .. reason)
            end
        end
    elseif not initialBattleDataLoaded then
        -- 首次加载且关卡未切换（serverStageId == currentStageId 或 serverStageId 为 nil）
        -- init 不再预加载关卡，这里统一触发 loadStage 进入寻怪模式
        local stageToLoad = serverStageId or currentStageId
        loadStage(stageToLoad)
        battleActive = false
        searchingTimer = 0
        print("[BattleScene] 首次加载，加载关卡(寻怪模式): " .. tostring(stageToLoad))
    end
    -- 首次加载时立即计算收益预估（OfflineCalc 统一公式，无需等待效率积累）
    if not initialBattleDataLoaded then
        recalcIdleIncome()
    end

    initialBattleDataLoaded = true

    -- 无论是否切换关卡，都刷新 isFirstClear（clearedStages 可能已更新）
    -- 注意：当战斗进行中(isBusy)时关卡切换被忽略，此时应以本地 currentStageId 为准
    -- 否则 serverStageId（可能是旧值）会导致 isFirstClear 被错误设为 false
    isFirstClear = not clearedStages[currentStageId]
    if not isFirstClear and StageBerserk.isActive() then
        StageBerserk.exit()
    end

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
                local newUnit = HC.createHero(u.heroId, heroLevel, owned.advBranch, owned.awakening)
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
                    local artifactEffects = ArtifactBridge.applyToUnit(newUnit.attrs, partySlot)
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
                        SpineCardEffect.playLevelUp(cx, ALLY_CARD_CY)
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
    maxStageId_ = 0
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

-- ======================== 长按怪物信息 ========================

--- 按下开始（由 ClientInput dispatchDragBegin 调用）
function BattleScene.handlePressBegin(dx, dy)
    longPress.active = true
    longPress.fired = false
    longPress.startTime = time.elapsedTime
    longPress.startX = dx
    longPress.startY = dy
    longPress.showPopup = false
    longPress.unit = nil
end

--- 按下结束（由 ClientInput dispatchDragEnd 调用）
function BattleScene.handlePressEnd()
    longPress.active = false
    longPress.fired = false
    -- 松开时关闭弹窗
    if longPress.showPopup then
        longPress.showPopup = false
        longPress.unit = nil
    end
end

--- 长按检测（在 BattleScene.update 中调用）
updateLongPress = function()
    if not longPress.active or longPress.fired then return end
    local elapsed = time.elapsedTime - longPress.startTime
    if elapsed < LONG_PRESS_THRESHOLD then return end

    -- 到达长按阈值，检测命中哪个怪物
    longPress.fired = true
    local dx, dy = longPress.startX, longPress.startY

    for i, u in ipairs(enemies) do
        if u.hp and u.hp > 0 then
            local cx = getCardCX(enemies, i)
            local cy = ENEMY_CARD_CY
            if math.abs(dx - cx) <= CARD_W * 0.5 and math.abs(dy - cy) <= CARD_H * 0.5 then
                longPress.unit = u
                longPress.showPopup = true
                print("[BattleScene] 长按命中怪物: " .. tostring(u.name))
                return
            end
        end
    end
end

--- 绘制怪物属性弹窗
drawMonsterInfoPopup = function(vg)
    if not longPress.showPopup or not longPress.unit then return end
    local u = longPress.unit
    local monCfg = u.monsterId and MC.MONSTERS[u.monsterId]

    -- 预估行数来动态计算高度
    local lineCount = 4  -- 攻击类型+护甲+目标+间隔
    if u.attrs and u.attrs.final then lineCount = lineCount + 1 end  -- 攻击力
    if monCfg and monCfg.attrs then
        for _ in pairs(monCfg.attrs) do lineCount = lineCount + 1 end
    end
    lineCount = lineCount + 1  -- 当前HP

    -- 弹窗位置（怪物卡片上方，高度自适应）
    local popCX = 540
    local popH = 100 + lineCount * 48
    local popCY = ENEMY_CARD_CY - CARD_H * 0.5 - popH * 0.5 - 10
    local popW = 600
    local popR = 16

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, popCX - popW * 0.5, popCY - popH * 0.5, popW, popH, popR)
    nvgFillColor(vg, nvgRGBA(20, 15, 10, 235))
    nvgFill(vg)
    -- 边框
    nvgStrokeColor(vg, nvgRGBA(180, 150, 80, 200))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)

    -- 标题：怪物名字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 42)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, popCX, popCY - popH * 0.5 + 40, u.name or "未知", nil)

    -- 分割线
    nvgBeginPath(vg)
    nvgMoveTo(vg, popCX - popW * 0.4, popCY - popH * 0.5 + 68)
    nvgLineTo(vg, popCX + popW * 0.4, popCY - popH * 0.5 + 68)
    nvgStrokeColor(vg, nvgRGBA(180, 150, 80, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 属性列表
    nvgFontSize(vg, 34)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(230, 225, 210, 255))

    local startY = popCY - popH * 0.5 + 100
    local lineH = 48
    local labelX = popCX - popW * 0.4
    local valueX = popCX + 40
    local line = 0

    -- 攻击类型
    local atkTypeName = "未知"
    if monCfg and monCfg.atkType then
        atkTypeName = ATK_TYPE_NAMES[monCfg.atkType] or ("类型" .. monCfg.atkType)
    end
    nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
    nvgText(vg, labelX, startY + line * lineH, "攻击类型", nil)
    nvgFillColor(vg, nvgRGBA(255, 200, 100, 255))
    nvgText(vg, valueX, startY + line * lineH, atkTypeName, nil)
    line = line + 1

    -- 护甲类型
    local armorName = "未知"
    if monCfg and monCfg.armorType then
        armorName = ARMOR_TYPE_NAMES[monCfg.armorType] or ("类型" .. monCfg.armorType)
    end
    nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
    nvgText(vg, labelX, startY + line * lineH, "护甲类型", nil)
    nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
    nvgText(vg, valueX, startY + line * lineH, armorName, nil)
    line = line + 1

    -- 攻击目标数
    if monCfg and monCfg.atkTargets then
        nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
        nvgText(vg, labelX, startY + line * lineH, "攻击目标", nil)
        nvgFillColor(vg, nvgRGBA(230, 225, 210, 255))
        nvgText(vg, valueX, startY + line * lineH, tostring(monCfg.atkTargets) .. "个", nil)
        line = line + 1
    end

    -- 攻击间隔
    if monCfg and monCfg.atkInterval then
        nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
        nvgText(vg, labelX, startY + line * lineH, "攻击间隔", nil)
        nvgFillColor(vg, nvgRGBA(230, 225, 210, 255))
        nvgText(vg, valueX, startY + line * lineH, string.format("%.1f秒", monCfg.atkInterval), nil)
        line = line + 1
    end

    -- 攻击力（根据攻击类型显示物攻或魔攻）
    if u.attrs and u.attrs.final then
        local atkCategory = monCfg and AD.getAtkCategory(monCfg.atkType) or "physical"
        local atkKey = (atkCategory == "magical") and AD.MAG_ATK or AD.PHYS_ATK
        local atkLabel = (atkCategory == "magical") and "魔法攻击" or "物理攻击"
        local atkVal = u.attrs.final[atkKey] or 0
        if atkVal > 0 then
            nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
            nvgText(vg, labelX, startY + line * lineH, atkLabel, nil)
            nvgFillColor(vg, nvgRGBA(255, 130, 80, 255))
            nvgText(vg, valueX, startY + line * lineH, tostring(math.floor(atkVal)), nil)
            line = line + 1
        end
    end

    -- 特殊属性（每条换行，读取实际战斗值，含等级/品质加成）
    if monCfg and monCfg.attrs and next(monCfg.attrs) then
        for key, _ in pairs(monCfg.attrs) do
            if not (u.monsterId == 1007 and key == AD.COMBO_RATE) then
                local meta = AD.META and AD.META[key]
                local cnName = meta and meta.name or key
                local dataType = meta and meta.dataType or AD.TYPE_FLOAT
                -- 从实际属性容器读取计算后的值
                local val = (u.attrs and u.attrs.final and u.attrs.final[key]) or 0
                local valStr
                if dataType == AD.TYPE_PCT then
                    valStr = tostring(math.floor(val)) .. "%"
                elseif dataType == AD.TYPE_INT then
                    valStr = tostring(math.floor(val))
                else
                    valStr = string.format("%.1f", val)
                end
                nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
                nvgText(vg, labelX, startY + line * lineH, "特殊", nil)
                nvgFillColor(vg, nvgRGBA(200, 100, 255, 255))
                nvgText(vg, valueX, startY + line * lineH, cnName .. " " .. valStr, nil)
                line = line + 1
            end
        end
    end

    -- 当前HP
    if u.hp then
        nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
        nvgText(vg, labelX, startY + line * lineH, "当前生命", nil)
        nvgFillColor(vg, nvgRGBA(100, 255, 100, 255))
        nvgText(vg, valueX, startY + line * lineH, tostring(math.floor(u.hp)), nil)
    end

    -- 提示
    nvgFontSize(vg, 26)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(150, 140, 120, 180))
    nvgText(vg, popCX, popCY + popH * 0.5 - 24, "松开关闭", nil)
end

return BattleScene

