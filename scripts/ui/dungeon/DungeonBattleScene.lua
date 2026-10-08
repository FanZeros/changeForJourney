-- ============================================================================
-- DungeonBattleScene - 副本战斗界面（独立场景）
-- 独立战斗场景（与 BattleScene 相互独立）
-- 职责: 副本战斗的渲染、更新、输入处理、结算
-- ============================================================================

local CF  = require("systems.CombatFormula")
local AD  = require("systems.AttributeDef")
local TM  = require("systems.ThreatManager")
local SEM = require("systems.StatusEffectManager")
local TAL = require("systems.TalentManager")
local MapAffixSystem    = require("systems.MapAffixSystem")
local BossAffixSystem = require("systems.BossAffixSystem")
local EnemySpawn = require("ui.battle.stage.BattleEnemySpawn")
local CombatRuntime = require("ui.dungeon.DungeonCombatRuntime")
local DungeonRewards = require("ui.dungeon.DungeonRewards")
local DungeonScope = require("ui.dungeon.DungeonBattleScope")
local DungeonConfig = require("config.DungeonConfig")

local BattleLayout      = require("core.BattleLayout")
local BattleCombat      = require("ui.battle.combat.BattleCombat")
local BattleStats       = require("systems.BattleStats")
local BattleDraw        = require("ui.battle.scene.BattleDraw")
local DarkIcon          = require("core.DarkIcon")  -- [暗黑化] 地图压暗滤镜
local BattleEffects     = require("ui.battle.combat.BattleEffects")
local SpineCardEffect  = require("ui.fx.SpineCardEffect")
local ProjectileSystem  = require("ui.battle.combat.ProjectileSystem")
local RCH              = require("systems.RelicConditionHandler")
local ART              = require("systems.ArtifactRuntime")

local GameConfig = require("config.GameConfig")
local StageConfig = require("config.StageConfig")
local Protocol   = require("shared.Protocol")
local HeroConfig = require("config.HeroConfig")
local PlayerStore = require("core.PlayerStore")
local DungeonBattle     = require("ui.dungeon.DungeonBattle")
local BattleResultPanel = require("ui.battle.popup.BattleResultPanel")
local BF                = require("systems.ButtonFeedback")
local DamageStatsPanel  = require("ui.battle.popup.DamageStatsPanel")
local SettingsPanel     = require("ui.hud.popup.SettingsPanel")

local drawTextStroke    = BattleDraw.drawTextStroke
local drawImageCentered = BattleDraw.drawImageCentered

-- BattleCombat 常用函数的本地别名
local getCardCX        = BattleCombat.getCardCX
local syncUnitHp       = BattleCombat.syncUnitHp
local addFloatingText  = BattleCombat.addFloatingText
local dealDamageToUnit = BattleCombat.dealDamageToUnit
local performAttack    = BattleCombat.performAttack

local DungeonScene = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量 ========================

-- 地图背景
local MAP_W, MAP_H = 1080, 2400
local MAP_CX, MAP_CY = 540, 1200

-- 背景漂移动效
local BG_DRIFT_Y_AMP    = 16
local BG_DRIFT_Y_PERIOD = 5.0

-- 敌方战场阴影
local ENEMY_SHADOW_CX, ENEMY_SHADOW_CY = 540, 804
local ENEMY_SHADOW_W, ENEMY_SHADOW_H   = 1080, 556

-- 己方战场阴影
local ALLY_SHADOW_CX, ALLY_SHADOW_CY = 540, 1760
local ALLY_SHADOW_W, ALLY_SHADOW_H   = 1080, 556

-- 敌方卡片组基准坐标
local ENEMY_CARD_CY      = BattleLayout.STRIP_CY
local ENEMY_TAG_OFFSET_Y  = -BattleLayout.CARD_H * 0.5 + 4
local ENEMY_NAME_OFFSET_Y = BattleLayout.CARD_H * 0.5 - 129
local ENEMY_HP_BG_OFFSET_Y = BattleLayout.CARD_H * 0.5 - 66
local ENEMY_HP_VAL_OFFSET_Y = BattleLayout.CARD_H * 0.5 - 84
local ENEMY_ATK_BG_OFFSET_Y = 181
local ENEMY_LVL_OFFSET_Y = BattleLayout.CARD_H * 0.5 - 4

-- 己方卡片组基准坐标
local ALLY_CARD_CY       = BattleLayout.STRIP_CY
local ALLY_TAG_OFFSET_Y   = -BattleLayout.CARD_H * 0.5 + 4
local ALLY_NAME_OFFSET_Y  = BattleLayout.CARD_H * 0.5 - 134
local ALLY_HP_BG_OFFSET_Y = BattleLayout.CARD_H * 0.5 - 66
local ALLY_HP_VAL_OFFSET_Y = BattleLayout.CARD_H * 0.5 - 84
local ALLY_ATK_BG_OFFSET_Y = 181
local ALLY_LVL_OFFSET_Y  = BattleLayout.CARD_H * 0.5 - 4

-- 副本标题区域
local DB = {
    TITLE_X = 540, TITLE_Y = 1170, TITLE_FONT = 52, TITLE_SW = 4,
    TITLE_SR = 0x31, TITLE_SG = 0x24, TITLE_SB = 0x24,
    -- 计时/状态文字
    TIME_X = 540, TIME_Y = 1235, TIME_FONT = 36, TIME_SW = 4,
    TIME_SR = 0x31, TIME_SG = 0x24, TIME_SB = 0x24,
    -- 狂暴提示颜色
    RAGE_R = 0xff, RAGE_G = 0x66, RAGE_B = 0x00,
    SUPER_RAGE_R = 0xff, SUPER_RAGE_G = 0x22, SUPER_RAGE_B = 0x22,
    -- 职业加成提示
    BONUS_Y = 1290, BONUS_FONT = 32,
    BONUS_R = 0x80, BONUS_G = 0xff, BONUS_B = 0x80,
    -- 撤退按钮
    SF_CX = 540, SF_CY = 2186, SF_W = 410, SF_H = 100,
    SF_FONT = 40, SF_R = 0x60, SF_G = 0x23, SF_B = 0x23,
}

-- 默认攻击间隔
local DEFAULT_ALLY_INTERVAL  = 1.0
local DEFAULT_ENEMY_INTERVAL = 1.5

-- 战斗结算状态
local BATTLE_ACTIVE = "active"
local BATTLE_WIN    = "win"
local BATTLE_LOSE   = "lose"

-- 结算面板延迟（秒）
local RESULT_DELAY = 1.5

-- 最大同屏敌人数
local MAX_FIELD = BattleLayout.MAX_PER_SIDE

-- 通天塔补位等待常量（死亡滑出后空位等待，已删除墓碑图）
local TOMBSTONE_REVIVE_TIME = 2.0
local DEATH_ANIM_DURATION   = BattleCombat.DEATH_ANIM_DURATION or 0.40
local REVIVE_ANIM_DURATION  = BattleCombat.REVIVE_ANIM_DURATION or 0.35

-- ======================== 撤退确认弹窗布局常量 ========================

local CDL = {
    BG_CX = 540, BG_CY = 1100, BG_W = 950, BG_H = 647,
    -- 标题
    TITLE_CY = 847, TITLE_FONT = 60, TITLE_SW = 6,
    TITLE_SR = 0x46, TITLE_SG = 0x2f, TITLE_SB = 0x20,
    -- 副标题
    SUB_CY = 970, SUB_FONT = 40,
    SUB_R = 0xb6, SUB_G = 0xb0, SUB_B = 0x9d,
    -- 说明文本
    LINE1_CY = 1100, LINE_FONT = 38,
    LINE2_CY = 1160,
    LINE_R = 0x72, LINE_G = 0x58, LINE_B = 0x50,
    -- 确认按钮（红色）
    OK_CX = 340, OK_CY = 1310, OK_W = 310, OK_H = 100, OK_FONT = 40,
    OK_TR = 0x60, OK_TG = 0x23, OK_TB = 0x23,
    -- 取消按钮
    CANCEL_CX = 740, CANCEL_CY = 1310, CANCEL_W = 310, CANCEL_H = 100, CANCEL_FONT = 40,
    CANCEL_TR = 0x50, CANCEL_TG = 0x46, CANCEL_TB = 0x3c,
    -- 动画
    OPEN_DUR = 0.25, CLOSE_DUR = 0.20,
    SCALE_FROM = 0.8, SCALE_TO = 1.0,
}

-- ======================== 图片句柄 ========================

local imgMapGoldMine  = -1   -- 金币副本地图
local imgMapEquipment = -1  -- 装备副本地图
local imgMapBlackDiamond = -1 -- 黑钻副本地图
local imgMapBabelTower = -1  -- 通天塔地图
local imgMapLegacy    = -1  -- 旧遗迹/木桩保留原 MAP_FB1
local imgShadow       = -1
local imgRetreatBtn   = -1
local imgEnemyTag     = -1
local imgAllyTags     = {}



-- 确认弹窗图片




-- ======================== 状态 ========================

local state = {
    open = false,
    -- 对战数据
    allies = {},
    enemies = {},
    enemyQueue = {},  -- 后备敌人队列
    -- 战斗状态
    battleState = BATTLE_ACTIVE,
    resultTimer = 0,
    resultPanelShown = false,
    -- 结果回调
    onClose = nil,
    -- 撤退二级确认弹窗
    confirmOpen    = false,
    confirmClosing = false,
    confirmOpenTime  = 0,
    confirmCloseTime = 0,
}

-- 背景动效
local bgAnimTimer = 0

-- HP回复累计
local regenAccum = 0

local function resetOpenFailureState()
    MapAffixSystem.reset(state.allies)
    state.open = false
    state.allies = {}
    state.enemies = {}
    state.enemyQueue = {}
    state.battleState = BATTLE_ACTIVE
    state.resultTimer = 0
    state.resultPanelShown = false
    state.confirmOpen = false
    state.confirmClosing = false
    pcall(DungeonBattle.exit)
    pcall(RCH.reset)
    pcall(BossAffixSystem.clear)
end

-- ======================== 工具函数 ========================

local function hitTest(dx, dy, cx, cy, w, h)
    return dx >= cx - w * 0.5 and dx <= cx + w * 0.5
       and dy >= cy - h * 0.5 and dy <= cy + h * 0.5
end

local function easeOutCubic(t)
    local f = t - 1; return f * f * f + 1
end
local function easeInCubic(t)
    return t * t * t
end

-- 兼容旧快捷键调用；副本战斗加速已删除。
function DungeonScene.cycleBattleSpeed()
    return false
end

--- 九宫格绘制
local function drawNineSlice(vg, imgH, dx, dy, dw, dh, iTop, iRight, iBottom, iLeft)
    if imgH < 0 then return end
    local srcW, srcH = nvgImageSize(vg, imgH)
    if srcW <= 0 or srcH <= 0 then return end
    local sL, sR, sT, sB = iLeft, iRight, iTop, iBottom
    local sMW, sMH = srcW - sL - sR, srcH - sT - sB
    local dL = math.min(iLeft, dw * 0.5)
    local dR = math.min(iRight, dw * 0.5)
    local dT = math.min(iTop, dh * 0.5)
    local dB = math.min(iBottom, dh * 0.5)
    if sMW <= 0 or sMH <= 0 then
        local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, imgH, 1.0)
        ---@cast paint NVGpaint
        nvgBeginPath(vg); nvgRect(vg, dx, dy, dw, dh); nvgFillPaint(vg, paint); nvgFill(vg)
        return
    end
    local ix0 = math.floor(dx + 0.5)
    local iy0 = math.floor(dy + 0.5)
    local ix1 = math.floor(dx + dL + 0.5)
    local iy1 = math.floor(dy + dT + 0.5)
    local ix2 = math.floor(dx + dw - dR + 0.5)
    local iy2 = math.floor(dy + dh - dB + 0.5)
    local ix3 = math.floor(dx + dw + 0.5)
    local iy3 = math.floor(dy + dh + 0.5)
    local OV = 1
    local patches = {
        { ix1-OV, iy1-OV, ix2-ix1+OV*2, iy2-iy1+OV*2, sL, sT, sMW, sMH },
        { ix1-OV, iy0,    ix2-ix1+OV*2, iy1-iy0+OV,   sL, 0,  sMW, sT  },
        { ix1-OV, iy2-OV, ix2-ix1+OV*2, iy3-iy2+OV,   sL, sT+sMH, sMW, sB  },
        { ix0,    iy1-OV, ix1-ix0+OV,   iy2-iy1+OV*2, 0,  sT, sL,  sMH },
        { ix2-OV, iy1-OV, ix3-ix2+OV,   iy2-iy1+OV*2, sL+sMW, sT, sR, sMH },
        { ix0,    iy0,    ix1-ix0+OV, iy1-iy0+OV, 0,      0,      sL, sT },
        { ix2-OV, iy0,    ix3-ix2+OV, iy1-iy0+OV, sL+sMW, 0,      sR, sT },
        { ix0,    iy2-OV, ix1-ix0+OV, iy3-iy2+OV, 0,      sT+sMH, sL, sB },
        { ix2-OV, iy2-OV, ix3-ix2+OV, iy3-iy2+OV, sL+sMW, sT+sMH, sR, sB },
    }
    nvgShapeAntiAlias(vg, 0)
    for _, p in ipairs(patches) do
        local px, py, pw, ph = p[1], p[2], p[3], p[4]
        local sx, sy, sw, sh = p[5], p[6], p[7], p[8]
        if pw > 0 and ph > 0 and sw > 0 and sh > 0 then
            local scX, scY = pw / sw, ph / sh
            local paint = nvgImagePattern(vg, px - sx * scX, py - sy * scY,
                srcW * scX, srcH * scY, 0, imgH, 1.0)
            ---@cast paint NVGpaint
            nvgBeginPath(vg); nvgRect(vg, px, py, pw, ph); nvgFillPaint(vg, paint); nvgFill(vg)
        end
    end
    nvgShapeAntiAlias(vg, 1)
end

--- 获取确认弹窗动画状态
local function getConfirmAnim()
    local C = CDL
    if state.confirmClosing then
        local t = math.min(1.0, (time.elapsedTime - state.confirmCloseTime) / C.CLOSE_DUR)
        local e = easeInCubic(t)
        return C.SCALE_TO + (C.SCALE_FROM - C.SCALE_TO) * e, 1.0 - e
    else
        local t = math.min(1.0, (time.elapsedTime - state.confirmOpenTime) / C.OPEN_DUR)
        local e = easeOutCubic(t)
        return C.SCALE_FROM + (C.SCALE_TO - C.SCALE_FROM) * e, e
    end
end

--- 绘制撤退确认弹窗
local function drawConfirmDialog(vg)
    if not state.confirmOpen then return end
    local C = CDL
    local pScale, pAlpha = getConfirmAnim()
    if pAlpha <= 0 then return end

    -- 黑色遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * pAlpha)))
    nvgFill(vg)

    -- 弹窗缩放 + 淡入
    nvgSave(vg)
    nvgTranslate(vg, C.BG_CX, C.BG_CY)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -C.BG_CX, -C.BG_CY)
    nvgGlobalAlpha(vg, pAlpha)

    -- 九宫格背景
    DarkIcon.drawNine(vg, "panel", C.BG_CX - C.BG_W * 0.5, C.BG_CY - C.BG_H * 0.5, C.BG_W, C.BG_H, { titleH = 40 })

    -- 标题
    drawTextStroke(vg, C.BG_CX, C.TITLE_CY, "确认撤退？",
        C.TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, C.TITLE_SW,
        { strokeColor = { C.TITLE_SR, C.TITLE_SG, C.TITLE_SB } })

    -- 副标题
    nvgFontFace(vg, "sans"); nvgFontSize(vg, C.SUB_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C.SUB_R, C.SUB_G, C.SUB_B, 255))
    nvgText(vg, C.BG_CX, C.SUB_CY, "本场战斗将判定为失败", nil)

    -- 说明
    nvgFontFace(vg, "sans"); nvgFontSize(vg, C.LINE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C.LINE_R, C.LINE_G, C.LINE_B, 255))
    nvgText(vg, C.BG_CX, C.LINE1_CY, "撤退不会消耗挑战次数", nil)
    nvgText(vg, C.BG_CX, C.LINE2_CY, "可以随时重新挑战本层", nil)

    -- 确认按钮（红色）
    DarkIcon.drawNine(vg, "btn", C.OK_CX - C.OK_W * 0.5, C.OK_CY - C.OK_H * 0.5, C.OK_W, C.OK_H, { accent = "red" })
    nvgFontFace(vg, "sans"); nvgFontSize(vg, C.OK_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C.OK_TR, C.OK_TG, C.OK_TB, 255))
    nvgText(vg, C.OK_CX, C.OK_CY, "撤退", nil)

    -- 取消按钮（灰色）
    DarkIcon.drawNine(vg, "btn", C.CANCEL_CX - C.CANCEL_W * 0.5, C.CANCEL_CY - C.CANCEL_H * 0.5, C.CANCEL_W, C.CANCEL_H, { accent = "green" })
    nvgFontFace(vg, "sans"); nvgFontSize(vg, C.CANCEL_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C.CANCEL_TR, C.CANCEL_TG, C.CANCEL_TB, 255))
    nvgText(vg, C.CANCEL_CX, C.CANCEL_CY, "取消", nil)

    nvgRestore(vg)
end

--- 获取副本地图图片
local function getMapImage()
    local cfg = DungeonBattle.getConfig()
    if cfg.dungeonId == "gold_mine" then
        return imgMapGoldMine
    elseif cfg.dungeonId == "equipment_vault" then
        return imgMapEquipment
    elseif cfg.dungeonId == "black_diamond" then
        return imgMapBlackDiamond
    elseif cfg.dungeonId == "babel_tower" then
        return imgMapBabelTower
    end
    return imgMapLegacy -- 旧遗迹、木桩与旧默认背景不变。
end

--- 获取副本标题文字
local function getDungeonTitle()
    local cfg = DungeonBattle.getConfig()
    if cfg.dungeonId == "training_dummy" then
        return "测试木桩 · DPS测试"
    elseif cfg.dungeonId == "babel_tower" then
        return string.format("通天塔 第%d层", cfg.floor)
    end
    local def = DungeonConfig.DEFINITIONS[cfg.dungeonId]
    return string.format("%s 第%d层 · 队伍%d", def and def.name or "副本", cfg.floor, cfg.teamIdx or 1)
end

--- 职业名称映射
local CLASS_NAMES = {
    warrior  = "拾骸者", spoil = "拾骸者",
    mage     = "裂隙使", rift = "裂隙使",
    archer   = "回响客", echo = "回响客", ranger = "回响客",
    assassin = "换面人", mask = "换面人",
    priest   = "司仪", debt = "司仪",
}

-- 每次死亡的天赋事件与副本结算分离；必须在清状态、丢旧敌人、胜利早返前扫描。
local function reportDefeatedEnemies()
    for _, unit in ipairs(state.enemies) do
        if unit.hp <= 0 then
            TAL.onEnemyDeath(unit, state.allies, state.enemies)
        else
            TAL.resetEnemyDeath(unit)
            if unit.reviveTimer then
                unit.reviveTimer = nil
                BattleCombat.clearCardAnim(unit)
            end
        end
    end
end

--- 补充后备队列中的敌人到场上
local function refillEnemies()
    while #state.enemies < MAX_FIELD and #state.enemyQueue > 0 do
        local u = table.remove(state.enemyQueue, 1)
        state.enemies[#state.enemies + 1] = u
        u.atkProgress = 0
        -- 入场动画
        BattleCombat.playEnterAnims({u}, -1)
    end
end

-- ======================== Public API ========================

local dungeonBattleInited_ = false
local dungeonBattleVg_ = nil

function DungeonScene.init(vg)
    if dungeonBattleInited_ then return end
    dungeonBattleInited_ = true
    dungeonBattleVg_ = vg
    imgMapGoldMine   = nvgCreateImage(vg, DungeonConfig.DEFINITIONS.gold_mine.cardImage, 0)
    imgMapEquipment = nvgCreateImage(vg, DungeonConfig.DEFINITIONS.equipment_vault.cardImage, 0)
    imgMapBlackDiamond = nvgCreateImage(vg, DungeonConfig.DEFINITIONS.black_diamond.cardImage, 0)
    imgMapBabelTower = nvgCreateImage(vg, "image/战斗背景/通天塔.png", 0)
    imgMapLegacy     = nvgCreateImage(vg, "image/关卡地图/MAP_FB1.png", 0)
    -- 阴影板绘制为 1080x556（源图 1080x610 压扁），使用 SHADOW 副本，调整原图不影响其他用法
    imgShadow        = nvgCreateImage(vg, "image/界面底板/通用面板/UI_YWJM_MAPYY_SHADOW.png", 0)
    imgRetreatBtn    = nvgCreateImage(vg, "image/按钮/UI_AN_HONG.png", 0)
    imgEnemyTag      = nvgCreateImage(vg, "image/通用图标/ICON_ZY_XG.png", 0)
    for i = 1, 6 do
        imgAllyTags[i] = nvgCreateImage(vg, "image/通用图标/ICON_ZY_" .. i .. ".png", 0)
    end

    -- 确认弹窗图片
    imgBtnRed    = nvgCreateImage(vg, "image/按钮/UI_AN_FANG_hong.png", 0)
    imgBtnGray   = nvgCreateImage(vg, "image/按钮/UI_AN_FANG.png", 0)
    BattleEffects.init(vg)
    ProjectileSystem.init(vg)
    BattleResultPanel.init(vg)
    print("[DungeonBattleScene] init OK")
end

--- 打开副本战斗
---@param opts table { allies, data, onClose }
function DungeonScene.open(opts)
    if not dungeonBattleInited_ and dungeonBattleVg_ then
        DungeonScene.init(dungeonBattleVg_)
    end
    MapAffixSystem.reset(opts and opts.allies)
    print("[DungeonBattleScene] open() called, opts=" .. tostring(opts))
    opts = opts or {}
    state.open = false

    local okOpen, openErr = pcall(function()
        state.allies = opts.allies or {}
        print("[DungeonBattleScene] allies count=" .. #state.allies .. ", state.open=" .. tostring(state.open))
        state.onClose = opts.onClose
        state.battleState = BATTLE_ACTIVE
        state.resultTimer = 0
        state.resultPanelShown = false
        state.rewardOverflow = nil
        state.reinforceCd = 0
        bgAnimTimer = 0
        regenAccum = 0
        state.confirmOpen = false
        state.confirmClosing = false

        -- 通知 DungeonBattle 模块进入副本模式
        local data = opts.data or {}
        DungeonBattle.enter(data, state.allies)

    -- 生成副本敌人
    local allEnemies = DungeonBattle.generateEnemies()
    state.enemies, state.enemyQueue = EnemySpawn.assignEnemiesToField(
        allEnemies, DungeonBattle.getConfig().maxFieldEnemies or MAX_FIELD)
    if #allEnemies == 0 then error("副本敌人列表为空") end

    -- 重置战斗子系统
    BattleCombat.reset()
    BattleEffects.reset()
    ProjectileSystem.reset()
    TM.reset()
    SEM.reset()
    TAL.reset()
    BattleStats.reset()
    RCH.reset()
    ART.reset(state.allies)

    -- 初始化所有单位
    for _, u in ipairs(state.allies) do
        u.atkProgress = 0
        u._artifactDeathHandled = nil
        u._towerDeathNotified = nil
        u._fallen = nil
        u._fallenPending = nil
        u._fallenAt = nil
        if u.attrs then
            u.attrs:fillHp()
            u.hp = u.attrs.final[AD.MAX_HP]
        end
        TAL.initUnit(u)
    end
    for _, u in ipairs(allEnemies) do
        u.atkProgress = 0
        TAL.initUnit(u)
    end
    local combatCfg = DungeonBattle.getConfig()
    if combatCfg.resourceCombat then
        local entry = combatCfg.stageEntry
        MapAffixSystem.onStageLoad(entry.chapter, state.allies, entry.mode)
        MapAffixSystem.applyStaticAffixes(allEnemies)
        BossAffixSystem.onStageLoad(entry.chapter, StageConfig.getDifficulty(entry.id))
        BossAffixSystem.applyToBosses(allEnemies)
        CombatRuntime.getBerserk().enter(state.enemies, state.allies)
    else
        BossAffixSystem.clear()
    end

    -- 初始化条件词条运行时（免疫/增伤，由天赋等系统消费）
    local allUnitsForRCH = {}
    for _, u in ipairs(state.allies) do allUnitsForRCH[#allUnitsForRCH + 1] = u end
    for _, u in ipairs(allEnemies) do allUnitsForRCH[#allUnitsForRCH + 1] = u end
    RCH.initBattle(allUnitsForRCH)
    ART.initBattle(state.allies)

    -- 入场动画
    BattleCombat.playEnterAnims(state.enemies, -1)
    BattleCombat.playEnterAnims(state.allies, 1)

    -- 仇恨/天赋初始化
    TM.onBattleStart(state.allies, state.enemies)
    TAL.onBattleStart(state.allies, state.enemies)

    -- 通天塔 mechanic 初始化（每波开始时应用一次性效果）
    if (opts.data or {}).dungeonId == "babel_tower" then
        local okTBR, TBR = pcall(require, "systems.TowerBuffRuntime")
        if okTBR and TBR then
            if TBR.resetWaveTimers then TBR.resetWaveTimers() end
            if TBR.applyMechanicInit then TBR.applyMechanicInit(state.allies, state.enemies) end
        end
    end

    -- 设置 BattleCombat 上下文
    BattleCombat.setContext({
        getAllies   = function() return state.allies end,
        getEnemies = function() return state.enemies end,
        ALLY_CARD_CY  = ALLY_CARD_CY,
        ENEMY_CARD_CY = ENEMY_CARD_CY,
        onCrit = function(attacker, isAlly)
            -- 副本无暴击台词
        end,
        onAttackHit = function(attacker, target, atkCX, atkCY, tgtCX, tgtCY, result, applyHit)
            local hasHeroEffect = attacker.heroId
                                  and ProjectileSystem.hasHeroEffect(attacker.heroId)
            local hasMonsterEffect = attacker.atkEffect
                                     and ProjectileSystem.hasMonsterProjectile(attacker.atkEffect)

            local hitCallback = function()
                if applyHit then applyHit() end
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
            BattleCombat.onTalentDealDamage(attacker, target, tgtCX, tgtCY, pfx, applyDamage, projOpts, state.allies, state.enemies)
        end,
    })

        print("[DungeonBattleScene] open - " .. getDungeonTitle()
            .. " | allies=" .. #state.allies .. " enemies=" .. #state.enemies
            .. " queue=" .. #state.enemyQueue)
    end)

    if not okOpen then
        print("[DungeonBattleScene] open failed: " .. tostring(openErr))
        resetOpenFailureState()
        error(openErr)
    end

    state.open = true
end

function DungeonScene.close(discardGrowth)
    local ETS = require("systems.ExtraTalentSystem")
    if discardGrowth then ETS.discard() else ETS.flush() end -- 已在DungeonScope内；清档不能提交。
    if DungeonBattle.isTrainingDummy() then DamageStatsPanel.close() end
    state.open = false
    MapAffixSystem.reset(state.allies)
    DungeonBattle.exit()
    RCH.reset()
    ART.reset(state.allies)
    -- 作用域包装器还原宿主挂载，无需重置主线天赋/计时。
    BossAffixSystem.clear()
    state.enemies, state.enemyQueue, state.allies = {}, {}, {}
    state.onClose = nil
    state.confirmOpen, state.confirmClosing = false, false
    state.rewardOverflow = nil
    BattleCombat.reset()
    ProjectileSystem.reset()
    BattleEffects.reset()
    print("[DungeonBattleScene] close")
end

--- 强制关闭（不触发结算面板，不调用 onClose 回调）
--- 由 TowerBattleScene 在波次结束时调用，用于关闭当前波次战斗
function DungeonScene.forceClose(discardGrowth)
    if not state.open and not discardGrowth then return end
    DungeonScene.close(discardGrowth)
    state.battleState = BATTLE_ACTIVE
    state.resultTimer = 0
    state.resultPanelShown = false
    print("[DungeonBattleScene] forceClose (tower wave transition)")
end

function DungeonScene.isOpen()
    return state.open
end

--- 处理服务器返回的 DUNGEON_WIN 结果
function DungeonScene.onActionResult(data)
    if not state.open then return false end
    return DungeonBattle.setServerResult(data)
end

-- 横屏宿主传逻辑尺寸；未传尺寸的旧调用按设计尺寸处理。
local function landscapeFit(width, height)
    local w, h = width or 1920, height or 1080
    local fit = math.min(w / 1920, h / 1080)
    return fit, (w - 1920 * fit) * 0.5, (h - 1080 * fit) * 0.5
end

local function beginCenteredOverlay(vg, width, height, centerY, contentHeight)
    local fit = math.min((width or 1920) / 1120, (height or 1080) / contentHeight)
    nvgSave(vg)
    nvgTranslate(vg, (width or 1920) * 0.5, (height or 1080) * 0.5)
    nvgScale(vg, fit, fit)
    nvgTranslate(vg, -540, -centerY)
end

function DungeonScene.draw(vg, width, height)
    if not state.open then return end
    width, height = width or 1920, height or 1080
    local fit, ox, oy = landscapeFit(width, height)
    local mapImg = getMapImage()
    local driftY = -BG_DRIFT_Y_AMP * (1.0 - math.cos(bgAnimTimer * 2 * math.pi / BG_DRIFT_Y_PERIOD)) * 0.5
    nvgSave(vg)
    nvgScissor(vg, 0, 0, width, height)
    if mapImg and mapImg > 0 then
        local imageW, imageH = nvgImageSize(vg, mapImg)
        if imageW > 0 and imageH > 0 then
            local cover = math.max(width / imageW, (height + BG_DRIFT_Y_AMP * 2) / imageH)
            DarkIcon.drawDarkScene(vg, mapImg, width * 0.5, height * 0.5 + driftY,
                imageW * cover, imageH * cover, 1.0)
        end
    end
    nvgTranslate(vg, ox, oy)
    nvgScale(vg, fit, fit)

    drawTextStroke(vg, 960, 90, getDungeonTitle(), 52,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
    local cfg = DungeonBattle.getConfig()
    local timeText, timeR, timeG, timeB = "", 255, 255, 255
    if DungeonBattle.isTrainingDummy() then
        local dur = BattleStats.getDuration()
        local dps = dur > 0.1 and math.floor(BattleStats.getTotal("totalDamage", false) / dur) or 0
        timeText = string.format("已测试 %.1fs · DPS %s", DungeonBattle.getElapsed(), require("core.NumberUtil").format(dps))
    else
        local remaining, rage = DungeonBattle.getTimeRemaining(), DungeonBattle.getRagePhase()
        timeText = string.format("剩余 %.0fs", remaining)
        if rage == 2 then
            timeText = string.format("超级狂暴! 剩余%.0fs", remaining)
            timeR, timeG, timeB = DB.SUPER_RAGE_R, DB.SUPER_RAGE_G, DB.SUPER_RAGE_B
        elseif rage == 1 then
            timeText = string.format("狂暴中 剩余%.0fs", remaining)
            timeR, timeG, timeB = DB.RAGE_R, DB.RAGE_G, DB.RAGE_B
        elseif remaining <= 30 then timeG, timeB = 144, 144 end
    end
    drawTextStroke(vg, 960, 165, timeText, 36,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, timeR, timeG, timeB, 4)
    if #state.enemyQueue > 0 then
        drawTextStroke(vg, 960, 225, "后备敌人 " .. tostring(#state.enemyQueue), 32,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
    end
    if cfg.resourceCombat then
        local names = {}
        for _, affix in ipairs(MapAffixSystem.getActiveAffixes() or {}) do names[#names + 1] = affix.name end
        for _, affix in ipairs(BossAffixSystem.getActiveAffixes() or {}) do names[#names + 1] = "首领·" .. affix.name end
        if #names > 0 then
            drawTextStroke(vg, 960, 990, table.concat(names, " · "), 26,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 210, 160, 3)
        end
    end
    local classId, bonusVal = DungeonBattle.getClassBonus()
    if classId and classId ~= "" then
        local label = (classId == "priest" or classId == "debt") and "治疗" or "伤害"
        drawTextStroke(vg, 960, 1030, string.format("%s +%.0f%%%s", CLASS_NAMES[classId] or classId, bonusVal * 100, label),
            30, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, DB.BONUS_R, DB.BONUS_G, DB.BONUS_B, 3)
    end

    -- 卡牌、投射物和飘字共享948×360战场，不单独平移任一阵营。
    nvgSave(vg)
    nvgTranslate(vg, (1920 - BattleLayout.STRIP_W * 1.75) * 0.5, 310)
    nvgScale(vg, 1.75, 1.75)
    BattleDraw.drawCardGroup(vg, state.enemies, BattleLayout.STRIP_CY,
        ENEMY_TAG_OFFSET_Y, ENEMY_NAME_OFFSET_Y, ENEMY_HP_BG_OFFSET_Y, ENEMY_HP_VAL_OFFSET_Y,
        ENEMY_ATK_BG_OFFSET_Y, ENEMY_LVL_OFFSET_Y, imgEnemyTag, false)
    BattleDraw.drawCardGroup(vg, state.allies, BattleLayout.STRIP_CY,
        ALLY_TAG_OFFSET_Y, ALLY_NAME_OFFSET_Y, ALLY_HP_BG_OFFSET_Y, ALLY_HP_VAL_OFFSET_Y,
        ALLY_ATK_BG_OFFSET_Y, ALLY_LVL_OFFSET_Y, imgAllyTags[1], true)
    if SettingsPanel.isEffectsEnabled() then
        ProjectileSystem.drawStarGates(vg, state.allies, BattleLayout.STRIP_CY, getCardCX, true)
        ProjectileSystem.drawStarGates(vg, state.enemies, BattleLayout.STRIP_CY, getCardCX, false)
        BattleEffects.draw(vg)
        ProjectileSystem.draw(vg)
        SpineCardEffect.draw(vg, "dungeon")
    end
    if SettingsPanel.isDamageNumbersEnabled() then
        BattleDraw.drawFloatingTexts(vg)
    end
    nvgRestore(vg)

    local feedback = BF.begin(vg, "dbs_retreat", 1750, 110, 260, 90)
    drawImageCentered(vg, imgRetreatBtn, 1750, 110, 260, 90, 1.0)
    drawTextStroke(vg, 1750, 110, DungeonBattle.isTrainingDummy() and "退出" or "撤退", 36,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
    BF.finish(vg, feedback)
    if DungeonBattle.isTrainingDummy() then
        drawTextStroke(vg, 170, 110, "统计", 36,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
    end
    nvgRestore(vg)

    BattleResultPanel.draw(vg, width, height)
    if state.resultPanelShown and state.rewardOverflow then
        drawTextStroke(vg, width * 0.5, height * 0.92, state.rewardOverflow, 24,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 220, 140, 3)
    end
    if DungeonBattle.isTrainingDummy() and DamageStatsPanel.isOpen() then
        beginCenteredOverlay(vg, width, height, 1195, 1300)
        DamageStatsPanel.draw(vg)
        nvgRestore(vg)
    end
    if state.confirmOpen then
        beginCenteredOverlay(vg, width, height, CDL.BG_CY, 800)
        drawConfirmDialog(vg)
        nvgRestore(vg)
    end
end

function DungeonScene.update(dt)
    if not state.open then return end

    -- 确认弹窗关闭动画
    if state.confirmClosing then
        local elapsed = time.elapsedTime - state.confirmCloseTime
        if elapsed >= CDL.CLOSE_DUR then
            state.confirmOpen    = false
            state.confirmClosing = false
        end
    end

    -- 背景漂移
    bgAnimTimer = bgAnimTimer + dt

    -- 投射物、连击与视觉统一使用真实 dt，不再读取旧倍率状态。
    if state.battleState == BATTLE_ACTIVE then
        ProjectileSystem.update(dt)
        BattleCombat.updateComboQueue(dt)
    end

    BattleEffects.update(dt)
    BattleCombat.updateCardAnims(dt)
    BattleCombat.updateFloatingTexts(dt)
    BattleCombat.updateHitFlashes(dt)

    -- 结算面板更新
    BattleResultPanel.update(dt)

    -- 战斗结束后的结算延迟阶段
    if state.battleState ~= BATTLE_ACTIVE then
        state.resultTimer = state.resultTimer + dt
        if state.resultTimer >= RESULT_DELAY and not state.resultPanelShown then
            -- 检查 DungeonBattle 结算数据是否就绪
            if DungeonBattle.isResultReady() then
                state.resultPanelShown = true
                local _, isWin, elapsedSecs, srvResult = DungeonBattle.getResultState()

                -- 构建英雄输出统计（与战斗中 DamageStatsPanel 一致，走 BattleStats）
                local heroStats = BattleStats.buildHeroDamageStats(state.allies, HeroConfig.HEROES)

                -- 构建奖励列表
                local rewards = (isWin and srvResult) and DungeonRewards.build(srvResult) or {}
                state.rewardOverflow = isWin and DungeonRewards.overflowText(srvResult) or nil

                -- 展示结算面板
                BattleResultPanel.show({
                    isWin       = isWin and (not srvResult or srvResult.success ~= false),
                    elapsedSecs = elapsedSecs,
                    heroStats   = heroStats,
                    rewards     = rewards,
                    onClose     = function()
                        if state.onClose then state.onClose() end
                        DungeonScene.close()
                    end,
                })
            end
        end
        return
    end

    -- ==== 以下为 BATTLE_ACTIVE 阶段逻辑 ====
    local logicDt = dt

    -- DungeonBattle 计时（狂暴阶段检测，狂暴加成施加到怪物与己方单位）
    DungeonBattle.update(logicDt, state.enemies, state.allies)

    -- 战斗超时增伤：复用 DungeonBattle.elapsed，每帧回写全局伤害倍率（木桩 DPS 测试豁免）
    if not DungeonBattle.isTrainingDummy() then
        local _toMult = require("systems.BattleTimeout").calcMult(DungeonBattle.getElapsed())
        local _bcs = BattleCombat.mountedState()
        if _bcs and _bcs.ctx then
            _bcs.ctx.globalDmgMult = _toMult
        end
    end

    -- 地图/Boss词缀与主线同一公共链，队列的静态加成已在开场应用。
    if DungeonBattle.getConfig().resourceCombat then
        MapAffixSystem.tick(logicDt, state.allies, state.enemies)
        BossAffixSystem.tick(logicDt, state.enemies)
    end

    ART.update(logicDt, state.allies)

    -- 战斗限时：超时自动判负
    if DungeonBattle.isTimeLimitExceeded() then
        state.battleState = BATTLE_LOSE
        state.resultTimer = 0
        DungeonBattle.onDefeat()
        print("[DungeonBattleScene] 战斗超时! 自动失败")
        return
    end

    -- 通天塔 mechanic per-frame 更新（冰冻计时器、法师蓄力等）
    local isTowerUpdate = (DungeonBattle.getConfig().dungeonId == "babel_tower")
    if isTowerUpdate then
        local okTBR, TBR = pcall(require, "systems.TowerBuffRuntime")
        if okTBR and TBR and TBR.update then
            local okUpdate, updateErr = pcall(function()
                TBR.update(logicDt, state.allies, state.enemies, function(unit, duration)
                    -- 冰冻回调：通过 SEM 施加冰冻效果
                    SEM.apply(unit, "frozen", duration, nil, nil)
                end)
            end)
            if not okUpdate then
                print("[DungeonBattleScene] TowerBuffRuntime.update failed: " .. tostring(updateErr))
            end
        elseif not okTBR then
            print("[DungeonBattleScene] TBR require failed: " .. tostring(TBR))
        end
    end

    -- 条件词条运行时（RCH）
    local okRchAlly, rchAllyErr = pcall(RCH.update, state.allies, 0)
    if not okRchAlly then
        print("[DungeonBattleScene] RelicConditionHandler.update allies failed: " .. tostring(rchAllyErr))
    end
    local okRchEnemy, rchEnemyErr = pcall(RCH.update, state.enemies, 0)
    if not okRchEnemy then
        print("[DungeonBattleScene] RelicConditionHandler.update enemies failed: " .. tostring(rchEnemyErr))
    end

    -- ---- 胜负检测 ----
    reportDefeatedEnemies()
    local allyAlive = BattleCombat.getAliveUnits(state.allies)
    local enemyAlive = BattleCombat.getAliveUnits(state.enemies)

    local isTowerMode = (DungeonBattle.getConfig().dungeonId == "babel_tower")

    if isTowerMode then
        -- ════ 通天塔模式：死亡滑出后空位等待补位（已删除墓碑图） ══════
        for i, unit in ipairs(state.enemies) do
            if unit.hp <= 0 then
                -- 首次检测死亡：启动死亡动画
                if not unit.reviveTimer then
                    unit.reviveTimer = -DEATH_ANIM_DURATION
                    unit.atkProgress = 0
                    TM.removeUnit(unit)
                    SEM.removeUnit(unit)
                    BattleCombat.setCardAnim(unit, {
                        state = "dying", timer = 0,
                        lungeDir = -1,
                        knockbackMult = 1.0 + (unit._overkillRatio or 0) * 2.0,
                        noTombstone = true,
                    })
                end

                unit.reviveTimer = unit.reviveTimer + logicDt

                if unit.reviveTimer < 0 then
                    -- 死亡动画阶段
                    unit.atkProgress = 0
                else
                    -- 空位等待阶段（进度条填充）
                    unit.atkProgress = math.min(1.0, unit.reviveTimer / TOMBSTONE_REVIVE_TIME)

                    -- 倒计时结束 + 队列有替补 → 原地替换
                    if unit.reviveTimer >= TOMBSTONE_REVIVE_TIME and #state.enemyQueue > 0 then
                        local newUnit = table.remove(state.enemyQueue, 1)
                        TAL.initUnit(newUnit)
                        newUnit.atkProgress = 0
                        state.enemies[i] = newUnit
                        BattleCombat.clearCardAnim(unit)
                        BattleCombat.clearHitFlash(unit)
                        BattleCombat.setCardAnim(newUnit, {
                            state = "reviving", timer = 0,
                            lungeDir = -1
                        })
                    end
                end
            end
        end

        -- 胜利条件：全部敌人死亡（含空位等待）且队列为空
        if DungeonBattle.isTrainingDummy() then
            return
        end
        local anyAliveOrReviving = false
        for _, u in ipairs(state.enemies) do
            if u.hp > 0 then
                anyAliveOrReviving = true
                break
            end
            -- 还在空位等待中（有队列可替换）
            if u.reviveTimer and u.reviveTimer < TOMBSTONE_REVIVE_TIME and #state.enemyQueue > 0 then
                anyAliveOrReviving = true
                break
            end
        end
        if not anyAliveOrReviving and #state.enemyQueue == 0 and #state.enemies > 0 then
            -- 检查是否所有死亡敌人都已完成退场（不是正在替换中）
            local allDone = true
            for _, u in ipairs(state.enemies) do
                if u.hp > 0 then allDone = false; break end
            end
            if allDone then
                state.battleState = BATTLE_WIN
                state.resultTimer = 0
                DungeonBattle.onVictory()
                print("[DungeonBattleScene] 胜利! 通天塔波次敌方全灭")
                return
            end
        end
    elseif DungeonBattle.getConfig().resourceCombat then
        local complete = require("ui.dungeon.DungeonEnemyLifecycle").tick(state, logicDt)
        if complete then
            state.battleState = BATTLE_WIN
            state.resultTimer = 0
            DungeonBattle.onVictory()
            return
        end
    else
        -- ════ 木桩/兼容副本模式 ══════
        if DungeonBattle.isTrainingDummy() then
            -- 木桩被打空时立刻回满，不进入胜利结算，保证 DPS 测试连续进行。
            for _, unit in ipairs(state.enemies) do
                if unit.hp <= 0 and unit.attrs then
                    unit.attrs:fillHp()
                    syncUnitHp(unit)
                    TAL.resetEnemyDeath(unit)
                    unit.atkProgress = 0
                    BattleCombat.clearCardAnim(unit)
                    BattleCombat.clearHitFlash(unit)
                end
            end
        elseif #enemyAlive == 0 and #state.enemies > 0 then
            if #state.enemyQueue > 0 then
                local alive = {}
                for _, u in ipairs(state.enemies) do
                    if u.hp > 0 then alive[#alive + 1] = u end
                end
                state.enemies = alive
                refillEnemies()
                TM.onBattleStart(state.allies, state.enemies)
            else
                state.battleState = BATTLE_WIN
                state.resultTimer = 0
                DungeonBattle.onVictory()
                print("[DungeonBattleScene] 胜利! 敌方全灭")
                return
            end
        end
    end

    local function notifyTowerAllyDeath(unit)
        if isTowerMode and unit and unit.hp <= 0 and not unit._towerDeathNotified then
            unit._towerDeathNotified = true
            DungeonBattle.onAllyDeath(unit)
        end
    end

    -- 通天塔亡者遗志等死亡回调必须先于神器复活/亡魂拦截。
    -- 死亡拦截顺序与主线 BattleScene 保持一致：神器 → 天赋（复活吧爱人复活）→ 判负。
    for _, unit in ipairs(state.allies) do
        if unit.hp <= 0 and not unit._artifactDeathHandled then
            notifyTowerAllyDeath(unit)
            unit._artifactDeathHandled = true

            local revived = ART.onAllyDeath(unit)
            if not revived then
                revived = TAL.onAllyDeath(unit, state.allies, syncUnitHp)
            end

            if revived then
                local idx = 1
                for ai, ally in ipairs(state.allies) do
                    if ally == unit then idx = ai; break end
                end
                local cx = getCardCX(state.allies, idx)
                if unit.hp > 0 then
                    -- 播放坐标/尺寸仍在948×360条带内；draw外层1.75与fit只乘一次。
                    SpineCardEffect.playRevive(cx, BattleLayout.STRIP_CY, nil, "dungeon",
                        BattleLayout.CARD_W * BattleLayout.CARD_SCALE,
                        BattleLayout.CARD_H * BattleLayout.CARD_SCALE)
                end
            else
                -- [阵亡紧凑] 救不回：退场动画 → 移队尾 → 存活者前移补位（与主线同规则）
                unit.atkProgress = 0
                TM.removeUnit(unit)
                SEM.removeUnit(unit)
                unit._fallenPending = true
                unit._fallenAt = time.elapsedTime
                BattleCombat.setCardAnim(unit, {
                    state = "dying", timer = 0, lungeDir = 1,
                    knockbackMult = 1.0 + (unit._overkillRatio or 0) * 2.0,
                    noTombstone = true,
                })
            end
        end
    end
    -- [阵亡紧凑] 退场完成 → 移队尾 → 存活者前移一格（含卡住兜底）
    require("ui.battle.scene.BattleAllyReset").compactFallen(state.allies, time.elapsedTime)
    allyAlive = BattleCombat.getAliveUnits(state.allies)

    if #allyAlive == 0 and #state.allies > 0 then
        if DungeonBattle.isTrainingDummy() then
            for _, unit in ipairs(state.allies) do
                if unit.hp <= 0 and unit.attrs then
                    unit.attrs:fillHp()
                    syncUnitHp(unit)
                    unit.atkProgress = 0
                    unit._fallen = nil
                    unit._fallenPending = nil
                    unit._fallenAt = nil
                    unit._artifactDeathHandled = nil
                    BattleCombat.clearCardAnim(unit)
                    BattleCombat.clearHitFlash(unit)
                end
            end
        else
            state.battleState = BATTLE_LOSE
            state.resultTimer = 0
            DungeonBattle.onDefeat()
            print("[DungeonBattleScene] 失败! 己方全灭")
            return
        end
    end

    -- 通天塔：检测己方单位首次死亡（触发亡者遗志等）
    if isTowerMode then
        for _, unit in ipairs(state.allies) do
            notifyTowerAllyDeath(unit)
        end
    end

    -- ---- 攻击进度更新 ----
    local hasAliveEnemy = #BattleCombat.getAliveUnits(state.enemies) > 0
    local hasAliveAlly  = #allyAlive > 0

    for _, unit in ipairs(state.allies) do
        if unit.hp > 0 and not SEM.isFrozen(unit) and not unit._trainingDummy then
            local interval = unit.atkInterval or DEFAULT_ALLY_INTERVAL
            -- 通天塔动态攻击间隔倍率（战士狂怒等）
            interval = interval * DungeonBattle.getAtkIntervalMultiplier(unit)
            BattleCombat.advanceAttackProgress(unit, logicDt, interval, hasAliveEnemy, function()
                performAttack(unit, state.enemies, true)
            end)
        end
    end

    for _, unit in ipairs(state.enemies) do
        if unit.hp > 0 and not SEM.isFrozen(unit) and not unit._trainingDummy then
            local interval = unit.atkInterval or DEFAULT_ENEMY_INTERVAL
            BattleCombat.advanceAttackProgress(unit, logicDt, interval, hasAliveAlly, function()
                performAttack(unit, state.allies, false)
            end)
        end
    end

    -- ---- 能量护盾恢复 ----
    for _, u in ipairs(state.allies) do
        if u.hp > 0 and u.attrs then u.attrs:tickEnergyShield(logicDt) end
    end
    for _, u in ipairs(state.enemies) do
        if u.hp > 0 and u.attrs then u.attrs:tickEnergyShield(logicDt) end
    end

    if DungeonBattle.isTrainingDummy() then
        for _, unit in ipairs(state.enemies) do
            if unit._trainingDummy and unit.attrs then
                unit.attrs:fillHp()
                syncUnitHp(unit)
            end
        end
    end

    -- ---- 血条缓冲 ----
    BattleCombat.updateHpBuffers(state.allies, logicDt)
    BattleCombat.updateHpBuffers(state.enemies, logicDt)

    -- ---- 仇恨衰减 ----
    TM.update(logicDt)

    -- ---- 状态效果（DOT/HOT） ----
    reportDefeatedEnemies()
    local okSem, semErr = pcall(SEM.update, logicDt, {
        onDot = function(unit, source, dmg)
            local isUnitAlly = false
            for _, u in ipairs(state.allies) do
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
                    for _, u in ipairs(state.allies) do
                        if u == unit then isUnitAlly = true; break end
                    end
                    local cy = isUnitAlly and ALLY_CARD_CY or ENEMY_CARD_CY
                    local list = isUnitAlly and state.allies or state.enemies
                    local cx = DESIGN_W * 0.5
                    for ii, u in ipairs(list) do
                        if u == unit then cx = getCardCX(list, ii); break end
                    end
                    addFloatingText("恢复 +" .. tostring(actual), cx, cy, {0, 255, 82}, false)
                end
            end
        end,
    })
    if not okSem then
        print("[DungeonBattleScene] SEM.update failed: " .. tostring(semErr))
    end

    -- ---- 天赋计时器 ----
    local okTal, talErr = pcall(TAL.update, logicDt, state.allies, state.enemies, {
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
            return BattleCombat.dealTalentDamage(attacker, target, damage, isTargetAlly, prefix, color, projOpts, state.allies, state.enemies)
        end,
        syncHp = function(unit)
            syncUnitHp(unit)
        end,
        performAttack = function(attacker, targetList, isAlly)
            performAttack(attacker, targetList, isAlly)
        end,
    })
    if not okTal then
        print("[DungeonBattleScene] TAL.update failed: " .. tostring(talErr))
    end

    -- ---- 每秒回血 ----
    regenAccum = regenAccum + logicDt
    while regenAccum >= 1.0 do
        regenAccum = regenAccum - 1.0
        local allUnits = {}
        for _, u in ipairs(state.allies) do allUnits[#allUnits + 1] = u end
        for _, u in ipairs(state.enemies) do allUnits[#allUnits + 1] = u end
        for _, unit in ipairs(allUnits) do
            if unit.hp > 0 and unit.attrs then
                local regen = CF.calcHpRegen(unit.attrs)
                if regen > 0 then
                    local actual = unit.attrs:heal(regen)
                    syncUnitHp(unit)
                end
            end
        end
    end
end

--- 处理点击输入
---@param dx number 宿主逻辑X
---@param dy number 宿主逻辑Y
---@param width number|nil
---@param height number|nil
---@return boolean
function DungeonScene.handleInput(dx, dy, width, height)
    if not state.open then return false end
    width, height = width or 1920, height or 1080

    -- 弹层反变换与绘制一致；不允许下层撤退按钮穿透。
    if state.confirmOpen then
        if state.confirmClosing then return true end
        local fit = math.min(width / 1120, height / 800)
        dx, dy = (dx - width * 0.5) / fit + 540, (dy - height * 0.5) / fit + CDL.BG_CY
    elseif state.battleState == BATTLE_ACTIVE and DungeonBattle.isTrainingDummy() and DamageStatsPanel.isOpen() then
        local fit = math.min(width / 1120, height / 1300)
        DamageStatsPanel.handleInput((dx - width * 0.5) / fit + 540, (dy - height * 0.5) / fit + 1195)
        return true
    else
        local fit, ox, oy = landscapeFit(width, height)
        dx, dy = (dx - ox) / fit, (dy - oy) / fit
    end

    -- 确认弹窗优先拦截
    if state.confirmOpen and not state.confirmClosing then
        local C = CDL
        -- 确认（撤退）
        if hitTest(dx, dy, C.OK_CX, C.OK_CY, C.OK_W, C.OK_H) then
            BF.trigger("dbs_confirm_retreat")
            state.confirmClosing  = true
            state.confirmCloseTime = time.elapsedTime
            print("[DungeonBattleScene] 确认撤退")
            state.battleState = BATTLE_LOSE
            state.resultTimer = 0
            DungeonBattle.onDefeat()
            return true
        end
        -- 取消
        if hitTest(dx, dy, C.CANCEL_CX, C.CANCEL_CY, C.CANCEL_W, C.CANCEL_H) then
            BF.trigger("dbs_cancel_retreat")
            state.confirmClosing  = true
            state.confirmCloseTime = time.elapsedTime
            print("[DungeonBattleScene] 取消撤退")
            return true
        end
        -- 点击弹窗外也关闭
        return true
    end

    -- 结算面板
    if state.battleState ~= BATTLE_ACTIVE then
        if BattleResultPanel.isOpen() then
            BattleResultPanel.handleInput(dx, dy)
        end
        return true
    end

    if DungeonBattle.isTrainingDummy() and hitTest(dx, dy, 170, 110, 150, 90) then
        DamageStatsPanel.open(100 + (DungeonBattle.getConfig().teamIdx or 1))
        return true
    end

    -- 撤退按钮
    if hitTest(dx, dy, 1750, 110, 260, 90) then
        BF.trigger("dbs_retreat")
        if DungeonBattle.isTrainingDummy() then
            if state.onClose then state.onClose() end
            DungeonScene.close()
            return true
        end
        state.confirmOpen     = true
        state.confirmClosing  = false
        state.confirmOpenTime = time.elapsedTime
        print("[DungeonBattleScene] 打开撤退确认弹窗")
        return true
    end

    return true  -- 消费事件防穿透
end

--- 处理拖拽开始
function DungeonScene.handleDragBegin(dx, dy)
    if not state.open then return false end
    return false
end

--- 处理拖拽移动
function DungeonScene.handleDragMove(dx, dy)
    if not state.open then return false end
    return false
end

--- 处理拖拽结束
function DungeonScene.handleDragEnd(dx, dy)
    if not state.open then return false end
    return false
end

--- 处理滚轮
function DungeonScene.handleScroll(wheel)
    if not state.open then return false end
    return false
end

-- 所有访问公共战斗状态的入口都在独立挂载内运行；即使异常也还原宿主。
for _, name in ipairs({ "open", "close", "forceClose", "update", "draw", "handleInput" }) do
    local implementation = DungeonScene[name]
    DungeonScene[name] = function(...)
        local teamIdx = DungeonBattle.getConfig().teamIdx
        if name == "open" then
            local opts = select(1, ...)
            teamIdx = opts and opts.data and opts.data.teamIdx or 1
        end
        return DungeonScope.run(teamIdx, implementation, ...)
    end
end

return DungeonScene
