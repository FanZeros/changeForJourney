-- ============================================================================
-- ArenaBattleScene - 竞技场对战界面
-- 基于战斗界面修改：隐藏标签栏、换地图、显示玩家名、倒计时、投降按钮
-- 集成 BattleCombat 实现真实自动战斗
-- ============================================================================

local CF  = require("systems.CombatFormula")
local AD  = require("systems.AttributeDef")
local TM  = require("systems.ThreatManager")
local SEM = require("systems.StatusEffectManager")
local TAL = require("systems.TalentManager")
local MapAffixSystem    = require("systems.MapAffixSystem")

---@class BattleCombatModule
---@field getCardCX fun(units: table, index: number): number
---@field syncUnitHp fun(unit: table)
---@field addFloatingText fun(text: string, cx: number, cy: number, color: table, isCrit: boolean, fontSize?: number)
---@field dealDamageToUnit fun(target: table, damage: number, isTargetAlly: boolean, prefix: string, color: table, source?: table, statMeta?: table): number
---@field performAttack fun(attacker: table, targetList: table, isAlly: boolean)

---@type BattleCombatModule
local BattleCombat      = require("ui.BattleCombat")
local BattleStats       = require("systems.BattleStats")
local BattleDraw        = require("ui.BattleDraw")
local BattleEffects     = require("ui.BattleEffects")
local ProjectileSystem  = require("ui.ProjectileSystem")
local RCH              = require("systems.RelicConditionHandler")
local ART              = require("systems.ArtifactRuntime")

local GameConfig = require("config.GameConfig")
local Protocol   = require("shared.Protocol")
local HeroConfig = require("config.HeroConfig")
local ArenaRankRewardDialog = require("ui.ArenaRankRewardDialog")
local BattleResultPanel     = require("ui.BattleResultPanel")
local BF                    = require("systems.ButtonFeedback")
local SettingsPanel         = require("ui.SettingsPanel")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格

local drawTextStroke    = BattleDraw.drawTextStroke
local drawImageCentered = BattleDraw.drawImageCentered

-- BattleCombat 常用函数的本地别名
local getCardCX        = BattleCombat.getCardCX
local syncUnitHp       = BattleCombat.syncUnitHp
local addFloatingText  = BattleCombat.addFloatingText
local dealDamageToUnit = BattleCombat.dealDamageToUnit
local performAttack    = BattleCombat.performAttack

local ArenaBattle = {}

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
local ENEMY_CARD_CY      = 804
local ENEMY_TAG_OFFSET_Y  = -215
local ENEMY_NAME_OFFSET_Y = 90
local ENEMY_HP_BG_OFFSET_Y = 153
local ENEMY_HP_VAL_OFFSET_Y = 135
local ENEMY_ATK_BG_OFFSET_Y = 181
local ENEMY_LVL_OFFSET_Y = 215

-- 己方卡片组基准坐标
local ALLY_CARD_CY       = 1760
local ALLY_TAG_OFFSET_Y   = -215
local ALLY_NAME_OFFSET_Y  = 85
local ALLY_HP_BG_OFFSET_Y = 153
local ALLY_HP_VAL_OFFSET_Y = 135
local ALLY_ATK_BG_OFFSET_Y = 181
local ALLY_LVL_OFFSET_Y  = 215

-- "竞技场" 标题
local AB = {
    TITLE_X = 540, TITLE_Y = 1192, TITLE_FONT = 60, TITLE_SW = 4,
    TITLE_SR = 0x31, TITLE_SG = 0x24, TITLE_SB = 0x24,
    -- "剩余XX秒" 倒计时
    TIME_X = 540, TIME_Y = 1258, TIME_FONT = 40, TIME_SW = 4,
    TIME_SR = 0x31, TIME_SG = 0x24, TIME_SB = 0x24,
    TIME_SEC_R = 0xff, TIME_SEC_G = 0x90, TIME_SEC_B = 0x90,
    -- 投降按钮
    SF_CX = 540, SF_CY = 2186, SF_W = 410, SF_H = 100,
    SF_FONT = 40, SF_R = 0x60, SF_G = 0x23, SF_B = 0x23,
    -- 默认限时（秒，与 GameConfig.Battle.TIME_LIMIT_SEC 对齐）
    DEFAULT_DURATION = GameConfig.Battle.TIME_LIMIT_SEC,
}

-- 段位图标（左上角可点击）
local TIER = {
    CX = 120, CY = 120, W = 160, H = 160,
}

-- 默认攻击间隔
local DEFAULT_ALLY_INTERVAL  = 1.0
local DEFAULT_ENEMY_INTERVAL = 1.5

-- 战斗结算状态
local BATTLE_ACTIVE   = "active"
local BATTLE_WIN      = "win"
local BATTLE_LOSE     = "lose"
local BATTLE_TIMEOUT  = "timeout"

-- 结算弹窗延迟（秒）
local RESULT_DELAY = 1.5

-- ======================== 投降确认弹窗布局常量 ========================

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
    -- 确认按钮（红色按钮 - 破坏性操作用红色）
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

local imgMap = -1
local imgShadow = -1
local imgSurrenderBtn = -1
local imgEnemyTag = -1
local imgAllyTags = {}
local imgTierIcons = {}  -- ICON_DW_1~8

-- 投降确认弹窗图片




-- ======================== 状态 ========================

local state = {
    open = false,
    timer = AB.DEFAULT_DURATION,
    totalDuration = AB.DEFAULT_DURATION,
    myName = "我方玩家",
    enemyName = "对手玩家",
    -- 对战数据
    allies = {},
    enemies = {},
    targetUid = nil,    -- 对手 uid（用于提交结果）
    -- 战斗状态
    battleState = BATTLE_ACTIVE,
    resultTimer = 0,    -- 结算延迟计时器
    resultSubmitted = false,  -- 是否已提交结果
    -- 段位信息
    tierIndex = 1,
    arenaScore = 0,
    claimedIds = {},
    -- 结果回调
    onSurrender = nil,
    onTimeout = nil,
    onWin = nil,
    onLose = nil,
    -- 服务器结算数据（由 onActionResult 填充）
    serverResult = nil,
    -- 投降二级确认弹窗
    confirmOpen    = false,
    confirmClosing = false,
    confirmOpenTime  = 0,
    confirmCloseTime = 0,
}

-- 背景动效
local bgAnimTimer = 0

-- HP回复累计
local regenAccum = 0

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

--- 九宫格绘制（供确认弹窗使用）
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
            nvgBeginPath(vg); nvgRect(vg, px, py, pw, ph); nvgFillPaint(vg, paint); nvgFill(vg)
        end
    end
    nvgShapeAntiAlias(vg, 1)
end

--- 获取确认弹窗动画状态 (scale, alpha)
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

--- 绘制投降确认弹窗
local function drawConfirmDialog(vg)
    if not state.confirmOpen then return end
    local C = CDL
    local pScale, pAlpha = getConfirmAnim()
    if pAlpha <= 0 then return end

    -- 1) 黑色遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * pAlpha)))
    nvgFill(vg)

    -- 2) 弹窗缩放 + 淡入变换
    nvgSave(vg)
    nvgTranslate(vg, C.BG_CX, C.BG_CY)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -C.BG_CX, -C.BG_CY)
    nvgGlobalAlpha(vg, pAlpha)

    -- 3) 九宫格背景
    DarkIcon.drawNine(vg, "panel", C.BG_CX - C.BG_W * 0.5, C.BG_CY - C.BG_H * 0.5, C.BG_W, C.BG_H, { titleH = 40 })

    -- 4) 标题
    drawTextStroke(vg, C.BG_CX, C.TITLE_CY, "确认投降？",
        C.TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, C.TITLE_SW,
        { strokeColor = { C.TITLE_SR, C.TITLE_SG, C.TITLE_SB } })

    -- 5) 副标题
    nvgFontFace(vg, "sans"); nvgFontSize(vg, C.SUB_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C.SUB_R, C.SUB_G, C.SUB_B, 255))
    nvgText(vg, C.BG_CX, C.SUB_CY, "本场战斗将判定为失败", nil)

    -- 6) 说明文本
    nvgFontFace(vg, "sans"); nvgFontSize(vg, C.LINE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C.LINE_R, C.LINE_G, C.LINE_B, 255))
    nvgText(vg, C.BG_CX, C.LINE1_CY, "积分将根据战斗结果计算", nil)
    nvgText(vg, C.BG_CX, C.LINE2_CY, "本次挑战机会消耗", nil)

    -- 7) 确认按钮（红色）
    DarkIcon.drawNine(vg, "btn", C.OK_CX - C.OK_W * 0.5, C.OK_CY - C.OK_H * 0.5, C.OK_W, C.OK_H, { accent = "red" })
    nvgFontFace(vg, "sans"); nvgFontSize(vg, C.OK_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C.OK_TR, C.OK_TG, C.OK_TB, 255))
    nvgText(vg, C.OK_CX, C.OK_CY, "投降", nil)

    -- 8) 取消按钮（灰色）
    DarkIcon.drawNine(vg, "btn", C.CANCEL_CX - C.CANCEL_W * 0.5, C.CANCEL_CY - C.CANCEL_H * 0.5, C.CANCEL_W, C.CANCEL_H, { accent = "green" })
    nvgFontFace(vg, "sans"); nvgFontSize(vg, C.CANCEL_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C.CANCEL_TR, C.CANCEL_TG, C.CANCEL_TB, 255))
    nvgText(vg, C.CANCEL_CX, C.CANCEL_CY, "取消", nil)

    nvgRestore(vg)
end

-- ======================== 战斗结束处理 ========================

local function submitBattleResult(isWin)
    if state.resultSubmitted then return end
    state.resultSubmitted = true

    require("network.Client").sendAction(Protocol.ACTION_TYPES.ARENA_BATTLE_RESULT, {
        targetUid = state.targetUid,
        isWin     = isWin,
    })
    print("[ArenaBattleScene] 提交战斗结果: " .. (isWin and "胜利" or "失败")
        .. " targetUid=" .. tostring(state.targetUid))
end

-- ======================== Public API ========================

function ArenaBattle.init(vg)
    imgMap = nvgCreateImage(vg, "image/MAP_JJC.png", 0)
    imgShadow = nvgCreateImage(vg, "image/UI_YWJM_MAPYY.png", 0)
    imgSurrenderBtn = nvgCreateImage(vg, "image/UI_AN_HONG.png", 0)
    imgEnemyTag = nvgCreateImage(vg, "image/ICON_ZY_XG.png", 0)
    for i = 1, 6 do
        imgAllyTags[i] = nvgCreateImage(vg, "image/ICON_ZY_" .. i .. ".png", 0)
    end
    for i = 1, 8 do
        imgTierIcons[i] = nvgCreateImage(vg, "image/ICON_DW_" .. i .. ".png", 0)
    end
    -- 投降确认弹窗图片
    imgConfirmBg = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    imgBtnRed    = nvgCreateImage(vg, "image/UI_AN_FANG_hong.png", 0)
    imgBtnGray   = nvgCreateImage(vg, "image/UI_AN_FANG.png", 0)
    BattleEffects.init(vg)
    ProjectileSystem.init(vg)
    ArenaRankRewardDialog.init(vg)
    BattleResultPanel.init(vg)
    print("[ArenaBattleScene] init OK")
end

--- 打开竞技场对战
---@param opts table { myName, enemyName, allies, enemies, targetUid, duration, onSurrender, onTimeout, onWin, onLose }
function ArenaBattle.open(opts)
    MapAffixSystem.reset(opts and opts.allies)
    opts = opts or {}
    state.open = true
    state.totalDuration = opts.duration or AB.DEFAULT_DURATION
    state.timer = state.totalDuration
    state.myName = opts.myName or "我方玩家"
    state.enemyName = opts.enemyName or "对手玩家"
    state.allies = opts.allies or {}
    state.enemies = opts.enemies or {}
    state.targetUid = opts.targetUid
    state.tierIndex = opts.tierIndex or 1
    state.arenaScore = opts.arenaScore or 0
    state.claimedIds = opts.claimedIds or {}
    state.onSurrender = opts.onSurrender
    state.onTimeout = opts.onTimeout
    state.onWin = opts.onWin
    state.onLose = opts.onLose
    state.battleState = BATTLE_ACTIVE
    state.resultTimer = 0
    state.resultSubmitted = false
    state.resultPanelShown = false
    state.serverResult = nil
    bgAnimTimer = 0
    regenAccum = 0

    -- 重置战斗子系统
    BattleCombat.reset()
    BattleEffects.reset()
    ProjectileSystem.reset()
    TM.reset()
    SEM.reset()
    TAL.reset()
    RCH.reset()
    ART.reset()

    -- 初始化所有单位
    for _, u in ipairs(state.allies) do
        u.atkProgress = 0
        TAL.initUnit(u)
    end
    for _, u in ipairs(state.enemies) do
        u.atkProgress = 0
        TAL.initUnit(u)
    end

    -- 初始化遗物条件词条（B/C类）：合并双方单位，RCH 内部按 relicConditions 过滤
    local allUnitsForRCH = {}
    for _, u in ipairs(state.allies) do allUnitsForRCH[#allUnitsForRCH + 1] = u end
    for _, u in ipairs(state.enemies) do allUnitsForRCH[#allUnitsForRCH + 1] = u end
    RCH.initBattle(allUnitsForRCH)
    ART.initBattle(state.allies)

    -- 入场动画
    BattleCombat.playEnterAnims(state.enemies, -1)  -- 敌方从上方滑入
    BattleCombat.playEnterAnims(state.allies, 1)    -- 己方从下方滑入

    -- 仇恨初始化
    TM.onBattleStart(state.allies, state.enemies)
    TAL.onBattleStart(state.allies, state.enemies)

    -- 设置 BattleCombat 上下文
    BattleCombat.setContext({
        getAllies   = function() return state.allies end,
        getEnemies = function() return state.enemies end,
        globalDmgMult = 0.35, -- 竞技场全体伤害调整为35%，延长战斗时间并降低互秒随机性
        ALLY_CARD_CY  = ALLY_CARD_CY,
        ENEMY_CARD_CY = ENEMY_CARD_CY,
        onCrit = function(attacker, isAlly)
            -- 竞技场无台词气泡，可留空
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

            -- 治疗类投射物传入 target 引用，目标死亡时提前取消投射物飞行
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
            BattleCombat.onTalentDealDamage(attacker, target, tgtCX, tgtCY, pfx, applyDamage, projOpts, state.allies, state.enemies)
        end,
    })

    print("[ArenaBattleScene] 打开竞技场对战 - " .. state.myName .. " vs " .. state.enemyName
        .. " | 己方 " .. #state.allies .. " | 敌方 " .. #state.enemies)
end

function ArenaBattle.close()
    state.open = false
    MapAffixSystem.reset(state.allies)
    RCH.reset()
    ART.reset()
    -- 恢复主战斗的 BattleCombat 上下文和 TAL/TM 天赋状态
    -- 修复: 竞技场 open 时覆盖了 ctx，导致主战斗恢复后治疗为 0
    local okBattle, BattleScene = pcall(require, "ui.BattleScene")
    if okBattle and BattleScene and BattleScene.restoreContext then
        BattleScene.restoreContext()
    end
    print("[ArenaBattleScene] 关闭竞技场对战")
end

function ArenaBattle.isOpen()
    return state.open
end

--- 处理服务器返回的 ARENA_BATTLE_RESULT 结果
function ArenaBattle.onActionResult(data)
    -- ARENA_BATTLE_RESULT 响应：包含 scoreChange 字段
    if data.scoreChange ~= nil then
        state.serverResult = data
        print("[ArenaBattleScene] 收到战斗结算: win=" .. tostring(data.isWin)
            .. " scoreChange=" .. tostring(data.scoreChange)
            .. " coinReward=" .. tostring(data.coinReward))
    end
end

function ArenaBattle.draw(vg)
    if not state.open then return end

    -- 1. 地图背景（MAP_JJC.png，带垂直漂移）
    local driftY = -BG_DRIFT_Y_AMP * (1.0 - math.cos(bgAnimTimer * 2 * math.pi / BG_DRIFT_Y_PERIOD)) * 0.5
    drawImageCentered(vg, imgMap, MAP_CX, MAP_CY + driftY, MAP_W, MAP_H, 1.0)

    -- 2. 敌方战场阴影
    drawImageCentered(vg, imgShadow, ENEMY_SHADOW_CX, ENEMY_SHADOW_CY,
        ENEMY_SHADOW_W, ENEMY_SHADOW_H, 1.0)

    -- 3. 敌方玩家名
    drawTextStroke(vg, 540, 525, state.enemyName, 40,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)

    -- 4. 敌方卡片组（带战斗动画偏移）
    BattleDraw.drawCardGroup(vg, state.enemies, ENEMY_CARD_CY,
        ENEMY_TAG_OFFSET_Y, ENEMY_NAME_OFFSET_Y,
        ENEMY_HP_BG_OFFSET_Y, ENEMY_HP_VAL_OFFSET_Y,
        ENEMY_ATK_BG_OFFSET_Y, ENEMY_LVL_OFFSET_Y, imgEnemyTag, false)

    -- 5. "竞技场" 标题文本
    drawTextStroke(vg, AB.TITLE_X, AB.TITLE_Y, "竞技场",
        AB.TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, AB.TITLE_SW,
        { strokeColor = { AB.TITLE_SR, AB.TITLE_SG, AB.TITLE_SB } })

    -- 6. "剩余XX秒" 倒计时文本
    local secs = math.max(0, math.ceil(state.timer))
    local preText = "剩余"
    local secText = tostring(secs)
    local postText = "秒"

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, AB.TIME_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local preW = nvgTextBounds(vg, 0, 0, preText, nil, {})
    local secW = nvgTextBounds(vg, 0, 0, secText, nil, {})
    local postW = nvgTextBounds(vg, 0, 0, postText, nil, {})
    local totalW = preW + secW + postW
    local startX = AB.TIME_X - totalW * 0.5

    drawTextStroke(vg, startX, AB.TIME_Y, preText,
        AB.TIME_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, AB.TIME_SW,
        { strokeColor = { AB.TIME_SR, AB.TIME_SG, AB.TIME_SB } })

    drawTextStroke(vg, startX + preW, AB.TIME_Y, secText,
        AB.TIME_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        AB.TIME_SEC_R, AB.TIME_SEC_G, AB.TIME_SEC_B, AB.TIME_SW,
        { strokeColor = { AB.TIME_SR, AB.TIME_SG, AB.TIME_SB } })

    drawTextStroke(vg, startX + preW + secW, AB.TIME_Y, postText,
        AB.TIME_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, AB.TIME_SW,
        { strokeColor = { AB.TIME_SR, AB.TIME_SG, AB.TIME_SB } })

    -- 7. 己方战场阴影
    drawImageCentered(vg, imgShadow, ALLY_SHADOW_CX, ALLY_SHADOW_CY,
        ALLY_SHADOW_W, ALLY_SHADOW_H, 1.0)

    -- 8. 己方玩家名
    drawTextStroke(vg, 540, 2046, state.myName, 40,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)

    -- 9. 己方卡片组（带战斗动画偏移）
    BattleDraw.drawCardGroup(vg, state.allies, ALLY_CARD_CY,
        ALLY_TAG_OFFSET_Y, ALLY_NAME_OFFSET_Y,
        ALLY_HP_BG_OFFSET_Y, ALLY_HP_VAL_OFFSET_Y,
        ALLY_ATK_BG_OFFSET_Y, ALLY_LVL_OFFSET_Y, imgAllyTags[1], true)

    -- 10. 投降按钮背景
    local _bfSF = BF.begin(vg, "abs_surrender", AB.SF_CX, AB.SF_CY, AB.SF_W, AB.SF_H)
    drawImageCentered(vg, imgSurrenderBtn, AB.SF_CX, AB.SF_CY, AB.SF_W, AB.SF_H, 1.0)

    -- 11. 投降文本
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, AB.SF_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(AB.SF_R, AB.SF_G, AB.SF_B, 255))
    nvgText(vg, AB.SF_CX, AB.SF_CY, "投降", nil)
    BF.finish(vg, _bfSF)

    -- 12. 段位图标（左上角）
    local tierIdx = math.max(1, math.min(8, state.tierIndex))
    local tierImg = imgTierIcons[tierIdx] or imgTierIcons[1]
    local _bfTier = BF.begin(vg, "abs_tier", TIER.CX, TIER.CY, TIER.W, TIER.H)
    drawImageCentered(vg, tierImg, TIER.CX, TIER.CY, TIER.W, TIER.H, 1.0)
    BF.finish(vg, _bfTier)

    -- 13. 攻击特效渲染
    if SettingsPanel.isEffectsEnabled() then
        ProjectileSystem.drawStarGates(vg, state.allies, ALLY_CARD_CY, getCardCX, true)
        ProjectileSystem.drawStarGates(vg, state.enemies, ENEMY_CARD_CY, getCardCX, false)
        BattleEffects.draw(vg)
        ProjectileSystem.draw(vg)
    end

    -- 14. 浮动伤害文字
    if SettingsPanel.isDamageNumbersEnabled() then
        BattleDraw.drawFloatingTexts(vg, BattleCombat.getFloatingTexts())
    end

    -- 15. 战斗结算面板（替代原简单文字）
    BattleResultPanel.draw(vg)

    -- 16. 段位奖励弹窗
    ArenaRankRewardDialog.draw(vg)

    -- 17. 投降二级确认弹窗（最顶层渲染）
    drawConfirmDialog(vg)
end

function ArenaBattle.update(dt)
    if not state.open then return end

    -- 投降确认弹窗：关闭动画结束后重置状态
    if state.confirmClosing then
        local elapsed = time.elapsedTime - state.confirmCloseTime
        if elapsed >= CDL.CLOSE_DUR then
            state.confirmOpen    = false
            state.confirmClosing = false
        end
    end

    -- 段位奖励弹窗更新
    ArenaRankRewardDialog.update(dt)

    -- 背景漂移动效
    bgAnimTimer = bgAnimTimer + dt

    -- 攻击特效更新
    BattleEffects.update(dt)
    ProjectileSystem.update(dt)

    -- 卡片动画更新（入场/攻击/受击/死亡）
    BattleCombat.updateCardAnims(dt)
    BattleCombat.updateFloatingTexts(dt)
    BattleCombat.updateHitFlashes(dt)
    BattleCombat.updateComboQueue(dt)

    -- 结算面板更新
    BattleResultPanel.update(dt)

    -- 战斗结束后进入结算延迟阶段
    if state.battleState ~= BATTLE_ACTIVE then
        state.resultTimer = state.resultTimer + dt
        -- 结算延迟后展示结算面板（仅触发一次）
        if state.resultTimer >= RESULT_DELAY and not state.resultPanelShown then
            state.resultPanelShown = true
            -- 构建英雄输出统计（与战斗中 DamageStatsPanel 一致，走 BattleStats）
            local heroStats = BattleStats.buildHeroDamageStats(state.allies, HeroConfig.HEROES)
            -- 构建奖励列表
            local rewards = {}
            if state.serverResult then
                local sr = state.serverResult
                if sr.coinReward and sr.coinReward > 0 then
                    rewards[#rewards + 1] = { type = "arena_coin", amount = sr.coinReward }
                end
                if sr.diamondReward and sr.diamondReward > 0 then
                    rewards[#rewards + 1] = { type = "diamond", amount = sr.diamondReward }
                end
            end
            -- 计算战斗耗时
            local totalDuration = state.totalDuration or AB.DEFAULT_DURATION
            local elapsed = totalDuration - math.max(0, state.timer)
            -- 展示面板
            BattleResultPanel.show({
                isWin       = (state.battleState == BATTLE_WIN),
                elapsedSecs = elapsed,
                heroStats   = heroStats,
                rewards     = rewards,
                arenaMode   = true,
                scoreChange = state.serverResult and state.serverResult.scoreChange or 0,
                onClose     = function()
                    ArenaBattle.close()
                end,
            })
        end
        return
    end

    -- 倒计时
    if state.timer > 0 then
        state.timer = state.timer - dt
        if state.timer <= 0 then
            state.timer = 0
            state.battleState = BATTLE_TIMEOUT
            state.resultTimer = 0
            submitBattleResult(false)  -- 超时判负
            print("[ArenaBattleScene] 时间到! 判负")
            if state.onTimeout then state.onTimeout() end
            return
        end
    end

    -- 遗物条件词条：每帧检查 HP 阈值条件（双方单位）
    RCH.update(state.allies, 0)
    RCH.update(state.enemies, 0)

    -- ---- 胜负检测 ----
    local allyAlive = BattleCombat.getAliveUnits(state.allies)
    local enemyAlive = BattleCombat.getAliveUnits(state.enemies)

    if #enemyAlive == 0 and #state.enemies > 0 then
        state.battleState = BATTLE_WIN
        state.resultTimer = 0
        submitBattleResult(true)
        print("[ArenaBattleScene] 胜利! 敌方全灭")
        if state.onWin then state.onWin() end
        return
    end

    if #allyAlive == 0 and #state.allies > 0 then
        for _, unit in ipairs(state.allies) do
            if unit.hp <= 0 then
                ART.onAllyDeath(unit)
            end
        end
        allyAlive = BattleCombat.getAliveUnits(state.allies)
    end

    if #allyAlive == 0 and #state.allies > 0 then
        state.battleState = BATTLE_LOSE
        state.resultTimer = 0
        submitBattleResult(false)
        print("[ArenaBattleScene] 失败! 己方全灭")
        if state.onLose then state.onLose() end
        return
    end

    -- ---- 攻击进度更新 ----
    local hasAliveEnemy = #enemyAlive > 0
    local hasAliveAlly  = #allyAlive > 0

    for _, unit in ipairs(state.allies) do
        if unit.hp > 0 and not SEM.isFrozen(unit) then
            local interval = unit.atkInterval or DEFAULT_ALLY_INTERVAL
            BattleCombat.advanceAttackProgress(unit, dt, interval, hasAliveEnemy, function()
                performAttack(unit, state.enemies, true)
            end)
        end
    end

    for _, unit in ipairs(state.enemies) do
        if unit.hp > 0 and not SEM.isFrozen(unit) then
            local interval = unit.atkInterval or DEFAULT_ENEMY_INTERVAL
            BattleCombat.advanceAttackProgress(unit, dt, interval, hasAliveAlly, function()
                performAttack(unit, state.allies, false)
            end)
        end
    end

    -- ---- 能量护盾恢复 ----
    for _, u in ipairs(state.allies) do
        if u.hp > 0 and u.attrs then u.attrs:tickEnergyShield(dt) end
    end
    for _, u in ipairs(state.enemies) do
        if u.hp > 0 and u.attrs then u.attrs:tickEnergyShield(dt) end
    end

    -- ---- 血条缓冲更新 ----
    BattleCombat.updateHpBuffers(state.allies, dt)
    BattleCombat.updateHpBuffers(state.enemies, dt)

    -- ---- 仇恨衰减 ----
    TM.update(dt)
    ART.update(dt)

    -- ---- 状态效果更新（DOT/HOT） ----
    SEM.update(dt, {
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

    -- ---- 天赋计时器更新 ----
    TAL.update(dt, state.allies, state.enemies, {
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

    -- ---- 每秒回血（HP_REGEN 属性） ----
    regenAccum = regenAccum + dt
    while regenAccum >= 1.0 do
        regenAccum = regenAccum - 1.0
        local allUnits = {}
        for _, u in ipairs(state.allies) do allUnits[#allUnits + 1] = u end
        for _, u in ipairs(state.enemies) do allUnits[#allUnits + 1] = u end
        for _, unit in ipairs(allUnits) do
            if unit.hp > 0 and unit.attrs then
                local regen = unit.attrs:get(AD.HP_REGEN) or 0
                if regen > 0 then
                    local actual = unit.attrs:heal(regen)
                    syncUnitHp(unit)
                end
            end
        end
    end
end

--- 处理点击输入
---@param dx number 设计空间X (0~1080)
---@param dy number 设计空间Y (0~2400)
---@return boolean
function ArenaBattle.handleInput(dx, dy)
    if not state.open then return false end

    -- 投降确认弹窗优先拦截（最高层级）
    if state.confirmOpen and not state.confirmClosing then
        local C = CDL
        -- 确认（投降）
        if hitTest(dx, dy, C.OK_CX, C.OK_CY, C.OK_W, C.OK_H) then
            BF.trigger("abs_confirm_surrender")
            state.confirmClosing  = true
            state.confirmCloseTime = time.elapsedTime
            print("[ArenaBattleScene] 确认投降")
            state.battleState = BATTLE_LOSE
            state.resultTimer = 0
            submitBattleResult(false)
            -- 不在此处关闭场景，让 update 的 resultTimer 机制触发结算面板
            -- 结算面板的 onClose 回调会调用 ArenaBattle.close()
            return true
        end
        -- 取消
        if hitTest(dx, dy, C.CANCEL_CX, C.CANCEL_CY, C.CANCEL_W, C.CANCEL_H) then
            BF.trigger("abs_cancel_surrender")
            state.confirmClosing  = true
            state.confirmCloseTime = time.elapsedTime
            print("[ArenaBattleScene] 取消投降")
            return true
        end
        -- 点击弹窗外区域也关闭
        return true
    end

    -- 段位奖励弹窗优先拦截
    if ArenaRankRewardDialog.isOpen() then
        ArenaRankRewardDialog.handleInput(dx, dy)
        return true
    end

    -- 战斗结束后：如果结算面板已打开，由面板处理点击关闭
    if state.battleState ~= BATTLE_ACTIVE then
        if BattleResultPanel.isOpen() then
            BattleResultPanel.handleInput(dx, dy)
        end
        return true
    end

    -- 段位图标点击 → 打开段位奖励弹窗
    if hitTest(dx, dy, TIER.CX, TIER.CY, TIER.W, TIER.H) then
        BF.trigger("abs_tier")
        print("[ArenaBattleScene] 点击段位图标")
        ArenaRankRewardDialog.open({
            currentScore = state.arenaScore,
            claimedIds = state.claimedIds,
        })
        return true
    end

    -- 投降按钮 → 打开二级确认弹窗
    if hitTest(dx, dy, AB.SF_CX, AB.SF_CY, AB.SF_W, AB.SF_H) then
        BF.trigger("abs_surrender")
        state.confirmOpen     = true
        state.confirmClosing  = false
        state.confirmOpenTime = time.elapsedTime
        print("[ArenaBattleScene] 打开投降确认弹窗")
        return true
    end

    return true  -- 消费事件防穿透
end

--- 处理拖拽开始
function ArenaBattle.handleDragBegin(dx, dy)
    if not state.open then return false end
    if ArenaRankRewardDialog.isOpen() then
        return ArenaRankRewardDialog.handleDragBegin(dx, dy)
    end
    return false
end

--- 处理拖拽移动
function ArenaBattle.handleDragMove(dx, dy)
    if not state.open then return false end
    if ArenaRankRewardDialog.isOpen() then
        return ArenaRankRewardDialog.handleDragMove(dx, dy)
    end
    return false
end

--- 处理拖拽结束
function ArenaBattle.handleDragEnd(dx, dy)
    if not state.open then return false end
    if ArenaRankRewardDialog.isOpen() then
        return ArenaRankRewardDialog.handleDragEnd(dx, dy)
    end
    return false
end

--- 处理滚轮
function ArenaBattle.handleScroll(wheel)
    if not state.open then return false end
    if ArenaRankRewardDialog.isOpen() then
        return ArenaRankRewardDialog.handleScroll(wheel)
    end
    return false
end

--- 获取剩余时间
function ArenaBattle.getRemainingTime()
    return state.timer
end

return ArenaBattle
