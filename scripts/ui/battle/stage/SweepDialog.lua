-- ============================================================================
-- SweepDialog - 主线扫荡弹窗
-- 入口：战斗界面右侧扫荡按钮（与战利品箱子 X=109 对称，X=971）
-- 功能：展示当前关卡、预计奖励，支持扫荡消耗/执行（后续下半部分扩展）
-- ============================================================================

local GameConfig        = require("config.GameConfig")
local GameState         = require("core.GameState")
local PlayerStore       = require("core.PlayerStore")
local SC                = require("config.StageConfig")
local ImageCache        = require("ui.widget.ImageCache")
local DrawUtil          = require("core.DrawUtil")

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice

local BF = require("systems.ButtonFeedback")
local SweepDialog = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 入口按钮布局 ========================
-- 战利品箱子位置：BOX_CX=109, BOX_CY=2115
-- 扫荡按钮以 X=540 镜像：X = 540*2 - 109 = 971
local BTN_CX   = 971
local BTN_CY   = 2115
local BTN_W    = 130
local BTN_H    = 144

-- ======================== 弹窗布局常量 ========================

local D = {
    -- 弹窗背景框（九宫格）
    BG_CX   = 540,  BG_CY   = 1195,
    BG_W    = 950,  BG_H    = 1250,
    BG_IT   = 180,

    -- 标题 "主线扫荡"
    TT_X    = 540,  TT_Y    = 705,
    TT_FONT = 60,   TT_SW   = 6,
    TT_SR   = 0x46, TT_SG   = 0x2f, TT_SB = 0x20,

    -- 副标题提示
    SUB_X   = 540,  SUB_Y   = 816,
    SUB_FONT = 40,
    SUB_R   = 0xb6, SUB_G   = 0xb0, SUB_B = 0x9d,

    -- 当前关卡区域背景
    CUR_BG_CX = 540, CUR_BG_CY = 918,
    CUR_BG_W  = 800, CUR_BG_H  = 80, CUR_BG_R = 16, CUR_BG_A = 13,

    -- "当前关卡" 标签（左对齐）
    CUR_LBL_X = 169, CUR_LBL_Y = 918,
    CUR_LBL_FONT = 40,
    CUR_LBL_R = 0x8d, CUR_LBL_G = 0x5f, CUR_LBL_B = 0x41,

    -- 关卡名（右对齐）
    CUR_VAL_X = 904, CUR_VAL_Y = 918,
    CUR_VAL_FONT = 40, CUR_VAL_SW = 6,

    -- "预计奖励" 标题
    REW_TT_X = 540, REW_TT_Y = 1008,
    REW_TT_FONT = 40, REW_TT_SW = 6,

    -- 奖励区域背景
    REW_BG_CX = 540, REW_BG_CY = 1119,
    REW_BG_W  = 800, REW_BG_H  = 220, REW_BG_R = 16, REW_BG_A = 13,

    -- 奖励图标行
    REW_ICON_Y  = 1124,
    REW_ICON_SZ = 160,    -- 品质背景框尺寸
    REW_ICON_PAD = 12,    -- 图标内缩量
    REW_ICON_GAP = 30,    -- 图标间距

    -- 奖励信息行（共用样式常量，行位置由 INFO_ROWS 定义）
    INF_FONT   = 40,
    INF_VAL_SW = 6,
    INF_LBL_X  = 169,
    INF_VAL_X  = 904,
    INF_BG_W   = 800, INF_BG_H = 80, INF_BG_R = 16, INF_BG_A = 13,
    INF_LBL_R  = 0x8d, INF_LBL_G = 0x5f, INF_LBL_B = 0x41,

    -- 扫荡次数（沿用购买道具弹窗的数量控件）
    QTY_CX = 540, QTY_CY = 1440, QTY_FONT = 40,
    MINUS_CX = 282, PLUS_CX = 798, STEP_CY = 1510, STEP_SIZE = 84,
    SLIDER_CX = 540, SLIDER_CY = 1510, SLIDER_W = 400, SLIDER_H = 24,
    KNOB_SIZE = 36,

    -- 扫荡券消耗
    TKT_ICON_CY = 1600, TKT_ICON_SZ = 70, TKT_FONT = 40,

    -- 确认按钮（扫荡）
    ACT_CX   = 540,  ACT_CY  = 1700,
    ACT_W    = 410,  ACT_H   = 100,
    ACT_FONT = 40,
}

-- ======================== 奖励项定义 ========================
-- 每个奖励项：{ quality, iconPath, label }
local REWARD_ITEMS = {
    { quality = 2, iconPath = "image/货币道具/UI_icon_JB.png",      label = "金币"     },
    { quality = 2, iconPath = "image/货币道具/UI_icon_JB.png",      label = "随机装备",  isEquip = true  },
    { quality = 3, iconPath = "image/货币道具/UI_icon_JZ_SJ.png",   label = "随机卷轴" },
}
-- 装备图标用固定的 B 品质背景占位
local EQUIP_PLACEHOLDER_QUALITY = 2

-- ======================== 信息行定义 ========================
-- label: 显示文本, field: StageConfig 字段名, cy: 行中心Y坐标
local INFO_ROWS = {
    { label = "远征队员经验", field = "adventurerExp", cy = 1340 },
}

-- ======================== 扫荡消耗常量 ========================
local SWEEP_COST = 1   -- 每次扫荡消耗扫荡券数

-- ======================== 图片句柄 ========================

local imgBtnSweep   = -1   -- UI_ICON_SD.png（入口按钮图标）
local imgBg         = -1   -- UI_TY_EJQRK.png（弹窗九宫格背景）
local imgTicketIcon = -1   -- UI_icon_SDQ_X.png（扫荡券图标）
local imgMinus     = -1   -- UI_AN_JIAN.png
local imgPlus      = -1   -- UI_AN_JIA.png

-- 奖励图标缓存 [index] = nvgImage
local rewardIconCache = {}

local cachedVg = nil

-- ======================== 状态 ========================

local SWEEP_MAX = 10
local _sweepRewardCache = nil   ---@type table|nil
local _sweepRewardStageId = nil

local state = {
    open      = false,
    openTime  = 0,
    count     = 1,
    sliderDragging = false,
}

-- ======================== 动画常量 ========================

local ANIM_OPEN_DUR  = 0.18
local ANIM_CLOSE_DUR = 0.14

-- ======================== 工具 ========================

local function hitTestRect(dx, dy, cx, cy, w, h)
    return dx >= cx - w * 0.5 and dx <= cx + w * 0.5
       and dy >= cy - h * 0.5 and dy <= cy + h * 0.5
end

local function hitTestCircle(dx, dy, cx, cy, r)
    local ddx, ddy = dx - cx, dy - cy
    return ddx * ddx + ddy * ddy <= r * r
end

--- 难度内的相对章节号
local function getRelativeChapter(chapter)
    return SC.getRelativeChapter(chapter)
end

--- 难度中文名
local DIFF_NAMES = {
    [SC.DIFFICULTY_NORMAL]    = "普通",
    [SC.DIFFICULTY_HARD]      = "困难",
    [SC.DIFFICULTY_NIGHTMARE] = "噩梦",
    [SC.DIFFICULTY_HELL]      = "地狱",
    [SC.DIFFICULTY_PURGATORY] = "炼狱",
    [SC.DIFFICULTY_TORMENT]   = "折磨",
    [SC.DIFFICULTY_TORMENT2]  = "折磨II",
    [SC.DIFFICULTY_TORMENT3]  = "折磨III",
    [SC.DIFFICULTY_TORMENT4]  = "折磨IV",
    [SC.DIFFICULTY_TORMENT5]      = "折磨V",
    [SC.DIFFICULTY_ANNIHILATION]  = "湮灭",
    [SC.DIFFICULTY_ANNIHILATION2] = "湮灭II",
    [SC.DIFFICULTY_ANNIHILATION3] = "湮灭III",
    [SC.DIFFICULTY_ANNIHILATION4] = "湮灭IV",
    [SC.DIFFICULTY_ANNIHILATION5] = "湮灭V",
}

--- 获取扫荡关卡显示名称。只显示最高已通关，不再拼「5-1至5-5」。
local function getCurrentStageName()
    local battleData = PlayerStore.Get("battle")
    local maxStageId = battleData and (battleData.maxStageId or battleData.currentStageId)
    if not maxStageId or maxStageId == 0 then return "未知关卡" end

    local cleared = battleData.clearedStages or {}
    local function isCleared(id)
        return cleared[id] or cleared[tostring(id)]
    end
    local stageId = maxStageId
    if not isCleared(stageId) then
        stageId = SC.getPrevStageId(stageId) or SC.getLastStageOfPrevDifficulty(stageId)
    end
    if stageId and SC.isTerminalTemple(stageId) then
        stageId = SC.getPrevStageId(stageId) or SC.getTerminalPrevStageId(stageId)
            or SC.getLastStageOfPrevDifficulty(stageId)
    end
    local entry = stageId and SC.getStage(stageId) or nil
    if not entry then return "未知关卡" end

    local diff = SC.getDifficulty(entry.id)
    local diffName = DIFF_NAMES[diff] or "普通"
    return diffName .. " " .. getRelativeChapter(entry.chapter) .. "-" .. entry.stage
end

--- 获取弹窗动画缩放系数（打开/关闭）
local function getAnimScale()
    if not state.open then return 0 end
    local elapsed = time.elapsedTime - state.openTime
    local t = math.min(elapsed / ANIM_OPEN_DUR, 1.0)
    -- 弹性进入（overshoot）
    local k = 1.0 + 0.08 * math.sin(t * math.pi)
    return t * k
end

--- 是否有可用的已通关关卡（与扫荡结算的关卡回退规则一致）
local function canSweepStage()
    local battleData = PlayerStore.Get("battle")
    local maxStageId = battleData and (battleData.maxStageId or battleData.currentStageId)
    if not maxStageId or maxStageId == 0 then return false end
    local cleared = battleData.clearedStages or {}
    local stageId = maxStageId
    if not (cleared[stageId] or cleared[tostring(stageId)]) then
        stageId = SC.getPrevStageId(stageId) or SC.getLastStageOfPrevDifficulty(stageId)
    end
    if stageId and SC.isTerminalTemple(stageId) then
        stageId = SC.getPrevStageId(stageId) or SC.getTerminalPrevStageId(stageId)
            or SC.getLastStageOfPrevDifficulty(stageId)
    end
    local entry = stageId and SC.getStage(stageId)
    return entry ~= nil and (entry.monsterLevel or 0) > 0
end

local function getMaxCount()
    if not canSweepStage() then return 0 end
    return math.min(SWEEP_MAX, math.max(0, math.floor(GameState.getSweepTicket() or 0) / SWEEP_COST))
end

local function setSliderCount(x)
    local maxCount = getMaxCount()
    if maxCount < 1 then return end
    local sliderL = D.SLIDER_CX - D.SLIDER_W * 0.5
    local frac = math.max(0, math.min(1, (x - sliderL) / D.SLIDER_W))
    state.count = math.floor(frac * (maxCount - 1) + 0.5) + 1
end

-- ======================== Public API ========================

--- 初始化（在 BattleScene.init 中调用）
---@param vg any NanoVG 上下文
function SweepDialog.init(vg)
    cachedVg = vg
    imgBtnSweep = nvgCreateImage(vg, "image/通用图标/UI_ICON_SD.png", 0)
    imgBg       = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TY_EJQRK.png", 0)

    -- 预加载奖励图标（装备用 "?" 文字绘制，无需加载图片）
    for i, item in ipairs(REWARD_ITEMS) do
        if not item.isEquip then
            rewardIconCache[i] = nvgCreateImage(vg, item.iconPath, 0)
        end
    end

    -- 次数按钮 & 扫荡券图标
    imgTicketIcon = nvgCreateImage(vg, "image/货币道具/UI_icon_SDQ_X.png", 0)
    imgMinus     = nvgCreateImage(vg, "image/按钮/UI_AN_JIAN.png", 0)
    imgPlus      = nvgCreateImage(vg, "image/按钮/UI_AN_JIA.png", 0)

    -- 初始化 ImageCache（如未初始化）
    ImageCache.init(vg)

    print("[SweepDialog] init OK")
end

--- 打开弹窗
function SweepDialog.open()
    if state.open then return end
    state.open     = true
    state.openTime = time.elapsedTime
    state.count    = 1
    state.sliderDragging = false
    print("[SweepDialog] open, tickets=" .. tostring(GameState.getSweepTicket() or 0)
        .. ", maxCount=" .. getMaxCount())
    -- 重新打开时清除预估奖励缓存，确保数据最新
    _sweepRewardCache = nil
end

--- 关闭弹窗
function SweepDialog.close()
    state.open = false
    state.sliderDragging = false
end

--- 是否已打开
function SweepDialog.isOpen()
    return state.open
end

-- ======================== 绘制入口按钮 ========================

--- 绘制战斗界面右侧扫荡入口按钮
---@param vg any
function SweepDialog.drawButton(vg)
    if imgBtnSweep < 0 then return end
    local _ds = BF.begin(vg, "sweep_btn", BTN_CX, BTN_CY, BTN_W, BTN_H)
    drawImageCentered(vg, imgBtnSweep, BTN_CX, BTN_CY, BTN_W, BTN_H, 1.0)
    -- 图标下方绘制"扫荡"文字标签（样式与战利品文字保持一致：白色 32px 描边4）
    drawTextStroke(vg, BTN_CX, BTN_CY + BTN_H * 0.42, "扫荡", 32,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
    BF.finish(vg, _ds)
end

-- ======================== 绘制弹窗 ========================

--- 扫荡固定参数（与本地 SweepService 保持一致）
local SWEEP_REWARD_MINUTES = 10   -- 扫荡 = 领取 N 分钟挂机收益（与本地 SweepService.REWARD_MINUTES 一致）
local IdleIncomeConfig = require("config.IdleIncomeConfig")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格

--- 获取扫荡单次预估奖励，结果按帧缓存
--- 与本地 SweepService 完全一致：基于玩家最高进度关卡 maxStageId，
--- 领取 SWEEP_REWARD_MINUTES 分钟的挂机收益（IdleIncomeConfig）
---@return table|nil rewards  adventureExp / adventurerExp / gold 等
local function getSweepRewardEstimate()
    local heroesData = PlayerStore.Get("heroes")
    local battleData = PlayerStore.Get("battle")
    local maxStageId = battleData and (battleData.maxStageId or battleData.currentStageId)
    if not maxStageId or maxStageId == 0 then return nil end

    if _sweepRewardStageId ~= maxStageId then
        -- 关卡变化，清缓存
        _sweepRewardCache   = nil
        _sweepRewardStageId = maxStageId
    end
    if _sweepRewardCache then return _sweepRewardCache end

    -- 出战英雄数
    local deployed  = heroesData and heroesData.deployed or {}
    local heroCount = #deployed
    if heroCount == 0 then heroCount = 1 end

    -- 金币 & 经验 = 挂机收益/分钟 × N 分钟（与本地 SweepService 一致）
    local cfgGoldPerMin, cfgExpPerMin = IdleIncomeConfig.get(maxStageId)
    local gold    = math.floor(cfgGoldPerMin * SWEEP_REWARD_MINUTES)
    local baseExp = math.floor(cfgExpPerMin * SWEEP_REWARD_MINUTES)

    -- 英雄经验 = baseExp × 出战人数倍率
    local ExpTable = require("config.ExpTable")
    local heroCountMult = ExpTable.heroCountExpMult[heroCount] or 1.0
    local heroExpTotal  = math.floor(baseExp * heroCountMult)

    _sweepRewardCache = {
        gold          = gold,
        adventureExp  = baseExp,
        adventurerExp = heroExpTotal,
    }
    return _sweepRewardCache
end

--- 读取关卡奖励数值并格式化
local function getStageRewardStr(field)
    local rewards = getSweepRewardEstimate()
    if not rewards then return "---" end
    local v = rewards[field]
    if not v or v <= 0 then return "---" end
    v = v * (state.count or 1)
    if v >= 10000 then return string.format("%.1f万", v / 10000) end
    return tostring(math.floor(v))
end

--- 绘制单个奖励图标（品质背景 + 内容图标 + 文字标签）
---@param vg any
---@param cx number 中心X
---@param cy number 中心Y
---@param itemIdx number 奖励项索引
local function drawRewardIcon(vg, cx, cy, itemIdx)
    local item = REWARD_ITEMS[itemIdx]
    if not item then return end

    local sz    = D.REW_ICON_SZ
    local inner = sz - D.REW_ICON_PAD * 2

    -- 品质背景框
    local qBg = ImageCache.getQualityBg(item.quality)
    if qBg >= 0 then
        drawImageCentered(vg, qBg, cx, cy, sz, sz, 1.0)
    end

    -- 内容图标
    if item.isEquip then
        -- 与战利品箱一致：品质背景框 + "?" 问号描边
        drawTextStroke(vg, cx, cy, "?", sz * 0.58,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, sz * 0.04)
    else
        local iconImg = rewardIconCache[itemIdx]
        if iconImg and iconImg >= 0 then
            drawImageCentered(vg, iconImg, cx, cy, inner, inner, 1.0)
        end
    end


end

--- 绘制弹窗全部内容（遮罩 + 面板）
---@param vg any
function SweepDialog.draw(vg)
    if not state.open then return end

    -- 扫荡次数随实际持有扫荡券变化，不能在扣券后保留超额选择
    local maxCount = getMaxCount()
    state.count = math.max(1, math.min(state.count, maxCount))

    local scale = getAnimScale()
    if scale <= 0.01 then return end

    -- 不再铺全屏灰色遮罩

    -- 弹窗内容以 BG_CX/BG_CY 为中心缩放
    nvgSave(vg)
    nvgTranslate(vg, D.BG_CX, D.BG_CY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -D.BG_CX, -D.BG_CY)

    -- 2) 弹窗背景框（九宫格）
    if imgBg >= 0 then
        DarkIcon.drawNine(vg, "panel", D.BG_CX - D.BG_W * 0.5, D.BG_CY - D.BG_H * 0.5, D.BG_W, D.BG_H, { titleH = D.BG_IT })
    end

    -- 3) 标题 "主线扫荡"
    drawTextStroke(vg, D.TT_X, D.TT_Y, "主线扫荡",
        D.TT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, D.TT_SW,
        { strokeColor = { D.TT_SR, D.TT_SG, D.TT_SB } })

    -- 4) 副标题 "消耗扫荡券可以快速获得资源"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, D.SUB_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(D.SUB_R, D.SUB_G, D.SUB_B, 255))
    nvgText(vg, D.SUB_X, D.SUB_Y, "消耗扫荡券可以快速获得资源", nil)

    -- 5) 当前关卡区域背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        D.CUR_BG_CX - D.CUR_BG_W * 0.5, D.CUR_BG_CY - D.CUR_BG_H * 0.5,
        D.CUR_BG_W, D.CUR_BG_H, D.CUR_BG_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, D.CUR_BG_A))
    nvgFill(vg)

    -- 6) "当前关卡" 标签（左对齐）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, D.CUR_LBL_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(D.CUR_LBL_R, D.CUR_LBL_G, D.CUR_LBL_B, 255))
    nvgText(vg, D.CUR_LBL_X, D.CUR_LBL_Y, "扫荡关卡", nil)

    -- 7) 关卡名（右对齐，绿色描边）
    local stageName = getCurrentStageName()
    drawTextStroke(vg, D.CUR_VAL_X, D.CUR_VAL_Y, stageName,
        D.CUR_VAL_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        0x63, 0xff, 0x84, D.CUR_VAL_SW,
        { strokeColor = { 0, 0, 0 } })

    -- 8) "预计奖励" 标题（白色描边）
    drawTextStroke(vg, D.REW_TT_X, D.REW_TT_Y, "预计奖励",
        D.REW_TT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, D.REW_TT_SW,
        { strokeColor = { 0, 0, 0 } })

    -- 9) 奖励区域背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        D.REW_BG_CX - D.REW_BG_W * 0.5, D.REW_BG_CY - D.REW_BG_H * 0.5,
        D.REW_BG_W, D.REW_BG_H, D.REW_BG_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, D.REW_BG_A))
    nvgFill(vg)

    -- 10) 奖励图标行（居中排列）
    local count   = #REWARD_ITEMS
    local totalW  = count * D.REW_ICON_SZ + (count - 1) * D.REW_ICON_GAP
    local startX  = D.BG_CX - totalW * 0.5 + D.REW_ICON_SZ * 0.5
    local iconCY  = D.REW_ICON_Y  -- Y=1124 为图标行中心坐标

    for i = 1, count do
        local cx = startX + (i - 1) * (D.REW_ICON_SZ + D.REW_ICON_GAP)
        drawRewardIcon(vg, cx, iconCY, i)
    end

    -- 11) 奖励信息行（远征等级经验 × 2 行）
    for _, row in ipairs(INFO_ROWS) do
        -- 行背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 540 - D.INF_BG_W * 0.5, row.cy - D.INF_BG_H * 0.5,
            D.INF_BG_W, D.INF_BG_H, D.INF_BG_R)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, D.INF_BG_A)); nvgFill(vg)
        -- 左标签
        nvgFontFace(vg, "sans"); nvgFontSize(vg, D.INF_FONT)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(D.INF_LBL_R, D.INF_LBL_G, D.INF_LBL_B, 255))
        nvgText(vg, D.INF_LBL_X, row.cy, row.label, nil)
        -- 右数值（绿色 + 黑描边）
        local valStr = getStageRewardStr(row.field)
        drawTextStroke(vg, D.INF_VAL_X, row.cy, valStr,
            D.INF_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
            0x63, 0xff, 0x84, D.INF_VAL_SW, { strokeColor = { 0, 0, 0 } })
    end

    -- 次数选择：与购买道具一致的减号、滑条和加号
    drawTextStroke(vg, D.QTY_CX, D.QTY_CY, "扫荡次数:" .. state.count,
        D.QTY_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 5, { strokeColor = { 0, 0, 0 } })

    local minus = BF.begin(vg, "sweep_dlg_minus", D.MINUS_CX, D.STEP_CY, D.STEP_SIZE, D.STEP_SIZE)
    drawImageCentered(vg, imgMinus, D.MINUS_CX, D.STEP_CY, D.STEP_SIZE, D.STEP_SIZE,
        state.count <= 1 and 0.4 or 1.0)
    BF.finish(vg, minus)
    local plus = BF.begin(vg, "sweep_dlg_plus", D.PLUS_CX, D.STEP_CY, D.STEP_SIZE, D.STEP_SIZE)
    drawImageCentered(vg, imgPlus, D.PLUS_CX, D.STEP_CY, D.STEP_SIZE, D.STEP_SIZE,
        state.count >= maxCount and 0.4 or 1.0)
    BF.finish(vg, plus)

    local sliderL = D.SLIDER_CX - D.SLIDER_W * 0.5
    local sliderFrac = maxCount > 1 and (state.count - 1) / (maxCount - 1) or 0
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sliderL, D.SLIDER_CY - D.SLIDER_H * 0.5,
        D.SLIDER_W, D.SLIDER_H, D.SLIDER_H * 0.5)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 51))
    nvgFill(vg)
    local fillW = D.SLIDER_W * sliderFrac
    if fillW > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sliderL, D.SLIDER_CY - D.SLIDER_H * 0.5,
            fillW, D.SLIDER_H, D.SLIDER_H * 0.5)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 80))
        nvgFill(vg)
    end
    nvgBeginPath(vg)
    nvgCircle(vg, sliderL + fillW, D.SLIDER_CY, D.KNOB_SIZE * 0.5)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, maxCount > 0 and 255 or 100))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(0x44, 0x2d, 0x19, 255))
    nvgStrokeWidth(vg, 6)
    nvgStroke(vg)

    -- 消耗与拥有数：数量与扫荡次数同步
    local cost = SWEEP_COST * state.count
    local owned = GameState.getSweepTicket() or 0
    local costStr = "×" .. tostring(cost) .. "  (拥有 " .. tostring(owned) .. ")"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, D.TKT_FONT)
    local costTextW = nvgTextBounds(vg, 0, 0, costStr)
    local costTotalW = D.TKT_ICON_SZ + 4 + costTextW
    local costStartX = D.BG_CX - costTotalW * 0.5
    drawImageCentered(vg, imgTicketIcon, costStartX + D.TKT_ICON_SZ * 0.5,
        D.TKT_ICON_CY, D.TKT_ICON_SZ, D.TKT_ICON_SZ, 1.0)
    drawTextStroke(vg, costStartX + D.TKT_ICON_SZ + 4, D.TKT_ICON_CY, costStr,
        D.TKT_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, owned >= cost and 255 or 90,
        owned >= cost and 255 or 90, 5, { strokeColor = { 0, 0, 0 } })

    -- 确认按钮（无券时禁用）
    local canSweep = maxCount >= 1
    local confirm = BF.begin(vg, "sweep_dlg_confirm", D.ACT_CX, D.ACT_CY, D.ACT_W, D.ACT_H)
    DarkIcon.drawNine(vg, "btn", D.ACT_CX - D.ACT_W * 0.5, D.ACT_CY - D.ACT_H * 0.5,
        D.ACT_W, D.ACT_H, { accent = canSweep and "gold" or nil })
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, D.ACT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(244, 237, 224, canSweep and 255 or 110))
    nvgText(vg, D.ACT_CX, D.ACT_CY,
        canSweep and "扫荡" or (canSweepStage() and "扫荡券不足" or "尚无可扫荡关卡"), nil)
    BF.finish(vg, confirm)

    nvgRestore(vg)
end

-- ======================== 输入处理 ========================

--- 处理触摸/点击输入
---@param x number 点击X
---@param y number 点击Y
---@return boolean consumed 是否消费事件
function SweepDialog.handleInput(x, y)
    if not state.open then return false end

    local maxCount = getMaxCount()
    state.count = math.max(1, math.min(state.count, maxCount))
    if hitTestRect(x, y, D.MINUS_CX, D.STEP_CY, D.STEP_SIZE, D.STEP_SIZE) then
        BF.trigger("sweep_dlg_minus")
        state.count = math.max(1, state.count - 1)
        print("[SweepDialog] count=" .. state.count .. "/" .. maxCount)
        return true
    end
    if hitTestRect(x, y, D.PLUS_CX, D.STEP_CY, D.STEP_SIZE, D.STEP_SIZE) then
        BF.trigger("sweep_dlg_plus")
        if maxCount > 0 then state.count = math.min(maxCount, state.count + 1) end
        print("[SweepDialog] count=" .. state.count .. "/" .. maxCount)
        return true
    end
    if maxCount > 1 and hitTestRect(x, y, D.SLIDER_CX, D.SLIDER_CY,
        D.SLIDER_W + D.KNOB_SIZE, math.max(D.SLIDER_H, D.KNOB_SIZE) + 20) then
        setSliderCount(x)
        print("[SweepDialog] slider count=" .. state.count .. "/" .. maxCount)
        return true
    end
    if hitTestRect(x, y, D.ACT_CX, D.ACT_CY, D.ACT_W, D.ACT_H) then
        if maxCount < 1 then
            print("[SweepDialog] sweep blocked: " .. (canSweepStage() and "扫荡券不足" or "当前关卡无法扫荡"))
            return true
        end
        BF.trigger("sweep_dlg_confirm")
        print("[SweepDialog] submit count=" .. state.count .. " tickets=" .. GameState.getSweepTicket())
        if SweepDialog.onSweep then SweepDialog.onSweep(state.count) end
        return true
    end
    if not hitTestRect(x, y, D.BG_CX, D.BG_CY, D.BG_W, D.BG_H) then
        SweepDialog.close()
    end
    return true
end

--- 滑条拖拽使用与三行弹窗相同的窗口坐标逆映射。
function SweepDialog.handleDragBegin(x, y)
    if not state.open then return false end
    if getMaxCount() > 1 and hitTestRect(x, y, D.SLIDER_CX, D.SLIDER_CY,
        D.SLIDER_W + D.KNOB_SIZE, math.max(D.SLIDER_H, D.KNOB_SIZE) + 20) then
        state.sliderDragging = true
        setSliderCount(x)
    end
    return true
end

function SweepDialog.handleDragMove(x, _y)
    if not state.sliderDragging then return false end
    setSliderCount(x)
    return true
end

function SweepDialog.handleDragEnd()
    if not state.sliderDragging then return false end
    state.sliderDragging = false
    print("[SweepDialog] slider final count=" .. state.count)
    return true
end

--- 确认扫荡回调（由外部绑定，如 BattleScene.lua）
---@type function|nil
SweepDialog.onSweep = nil

--- 处理入口按钮点击（由 BattleScene 在 lootBox 之后调用）
---@param x number
---@param y number
---@return boolean consumed
function SweepDialog.handleButtonInput(x, y)
    if state.open then return false end
    -- 命中检测：点击是否在扫荡按钮区域内
    if math.abs(x - BTN_CX) <= BTN_W * 0.5 and math.abs(y - BTN_CY) <= BTN_H * 0.5 then
        BF.trigger("sweep_btn")
        SweepDialog.open()
        return true
    end
    return false
end

return SweepDialog
