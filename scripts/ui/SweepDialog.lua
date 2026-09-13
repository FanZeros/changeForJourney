-- ============================================================================
-- SweepDialog - 主线扫荡弹窗
-- 入口：战斗界面右侧扫荡按钮（与战利品箱子 X=109 对称，X=971）
-- 功能：展示当前关卡、预计奖励，支持扫荡消耗/执行（后续下半部分扩展）
-- ============================================================================

local GameConfig        = require("config.GameConfig")
local GameState         = require("core.GameState")
local PlayerStore       = require("client.data.PlayerStore")
local SC                = require("config.StageConfig")
local ImageCache        = require("ui.ImageCache")
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
    -- 遮罩
    OVL_A   = 128,   -- 50% 不透明度

    -- 弹窗背景框（九宫格）
    BG_CX   = 540,  BG_CY   = 1195,
    BG_W    = 950,  BG_H    = 1117,
    BG_IT   = 180,  BG_IR   = 40,  BG_IB = 50, BG_IL = 40,

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

    -- 扫荡券区域（背景仅右侧两角圆角）
    TKT_BG_CX   = 564,  TKT_BG_CY   = 1522,
    TKT_BG_W    = 162,  TKT_BG_H    = 47,
    TKT_BG_RA   = 24,   -- 右侧圆角半径
    TKT_BG_A    = 26,   -- 10% 不透明度 (0.1*255≈26)
    TKT_ICON_CX = 484,  TKT_ICON_CY = 1522, TKT_ICON_SZ = 70,
    TKT_TXT_CX  = 573,  TKT_TXT_CY  = 1522,  TKT_FONT = 40,

    -- 确认按钮（扫荡）
    ACT_CX   = 540,  ACT_CY  = 1619,
    ACT_W    = 410,  ACT_H   = 100,
    ACT_FONT = 40,
}

-- ======================== 奖励项定义 ========================
-- 每个奖励项：{ quality, iconPath, label }
local REWARD_ITEMS = {
    { quality = 2, iconPath = "image/UI_icon_JB.png",      label = "金币"     },
    { quality = 2, iconPath = "image/UI_icon_JB.png",      label = "随机装备",  isEquip = true  },
    { quality = 3, iconPath = "image/UI_icon_JZ_SJ.png",   label = "随机卷轴" },
}
-- 装备图标用固定的 B 品质背景占位
local EQUIP_PLACEHOLDER_QUALITY = 2

-- ======================== 信息行定义 ========================
-- label: 显示文本, field: StageConfig 字段名, cy: 行中心Y坐标
local INFO_ROWS = {
    { label = "冒险等级经验", field = "adventureExp",  cy = 1291 },
    { label = "冒险家经验",   field = "adventurerExp", cy = 1390 },
}

-- ======================== 扫荡消耗常量 ========================
local SWEEP_COST = 1   -- 每次扫荡消耗扫荡券数

-- ======================== 文本宽度缓存（防 scale 动画闪烁） ========================
local _txtWidthCache = {}

-- ======================== 图片句柄 ========================

local imgBtnSweep   = -1   -- UI_ICON_SD.png（入口按钮图标）
local imgBg         = -1   -- UI_TY_EJQRK.png（弹窗九宫格背景）
local imgActBtn     = -1   -- UI_AN_HUANG.png（确认扫荡按钮背景）
local imgTicketIcon = -1   -- UI_icon_SDQ_X.png（扫荡券图标）

-- 奖励图标缓存 [index] = nvgImage
local rewardIconCache = {}

local cachedVg = nil

-- ======================== 状态 ========================

local state = {
    open      = false,
    openTime  = 0,
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

--- 获取扫荡关卡显示名称（格式："普通 5-1至5-5"）
local function getCurrentStageName()
    local battleData = PlayerStore.Get("battle")
    local maxStageId = battleData and (battleData.maxStageId or battleData.currentStageId)
    if not maxStageId or maxStageId == 0 then return "未知关卡" end

    -- 从 maxStageId 往前收集最多 5 个关卡（与服务端逻辑一致）
    local prevId = SC.getPrevStageId(maxStageId)
    if not prevId then
        prevId = SC.getLastStageOfPrevDifficulty(maxStageId)
    end
    if not prevId then return "未知关卡" end

    local stages = {}
    local id = prevId
    while id and #stages < 5 do
        local entry = SC.getStage(id)
        if entry then stages[#stages + 1] = entry end
        local nextPrev = SC.getPrevStageId(id)
        if not nextPrev then
            nextPrev = SC.getLastStageOfPrevDifficulty(id)
        end
        id = nextPrev
    end

    if #stages == 0 then return "未知关卡" end

    -- 取首尾关卡（stages[1]是最接近当前的，stages[#stages]是最远的）
    local first = stages[#stages]  -- 最远的（编号最小）
    local last  = stages[1]        -- 最近的（编号最大）
    local diff = SC.getDifficulty(last.id)
    local diffName = DIFF_NAMES[diff] or "普通"

    local firstChap = getRelativeChapter(first.chapter)
    local lastChap  = getRelativeChapter(last.chapter)

    if #stages == 1 then
        return diffName .. " " .. firstChap .. "-" .. first.stage
    else
        return diffName .. " " .. firstChap .. "-" .. first.stage .. "至" .. lastChap .. "-" .. last.stage
    end
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

-- ======================== Public API ========================

--- 初始化（在 BattleScene.init 中调用）
---@param vg any NanoVG 上下文
function SweepDialog.init(vg)
    cachedVg = vg
    imgBtnSweep = nvgCreateImage(vg, "image/UI_ICON_SD.png", 0)
    imgBg       = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)

    -- 预加载奖励图标（装备用 "?" 文字绘制，无需加载图片）
    for i, item in ipairs(REWARD_ITEMS) do
        if not item.isEquip then
            rewardIconCache[i] = nvgCreateImage(vg, item.iconPath, 0)
        end
    end

    -- 确认按钮 & 扫荡券图标
    imgActBtn     = nvgCreateImage(vg, "image/UI_AN_HUANG.png",   0)
    imgTicketIcon = nvgCreateImage(vg, "image/UI_icon_SDQ_X.png", 0)

    -- 初始化 ImageCache（如未初始化）
    ImageCache.init(vg)

    print("[SweepDialog] init OK")
end

--- 打开弹窗
function SweepDialog.open()
    if state.open then return end
    state.open     = true
    state.openTime = time.elapsedTime
    -- 重新打开时清除预估奖励缓存，确保数据最新
    _sweepRewardCache = nil
end

--- 关闭弹窗
function SweepDialog.close()
    state.open = false
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
    drawTextStroke(vg, BTN_CX, 2174, "扫荡", 32,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
    BF.finish(vg, _ds)
end

-- ======================== 绘制弹窗 ========================

--- 获取缓存的文本宽度（防止 scale 动画中 hinting 抖动）
local function getCachedTextW(vg, text, fontSize)
    local key = text .. "\0" .. tostring(fontSize)
    if not _txtWidthCache[key] then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        _txtWidthCache[key] = nvgTextBounds(vg, 0, 0, text)
    end
    return _txtWidthCache[key]
end

--- 缓存单次扫荡预估奖励（避免每帧重复计算）
local _sweepRewardCache = nil   ---@type table|nil
local _sweepRewardStageId = nil

--- 扫荡固定参数（与服务端 SweepService 保持一致）
local SWEEP_REWARD_MINUTES = 10   -- 扫荡 = 领取 N 分钟挂机收益（与服务端 SweepService.REWARD_MINUTES 一致）
local IdleIncomeConfig = require("config.IdleIncomeConfig")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格

--- 获取扫荡单次预估奖励，结果按帧缓存
--- 与服务端 SweepService 完全一致：基于玩家最高进度关卡 maxStageId，
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

    -- 金币 & 经验 = 挂机收益/分钟 × N 分钟（与服务端一致）
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

    local scale = getAnimScale()
    if scale <= 0.01 then return end

    -- 1) 全屏黑色遮罩 50%
    local ovlAlpha = math.floor(D.OVL_A * math.min(scale * 2, 1.0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, ovlAlpha))
    nvgFill(vg)

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

    -- 11) 奖励信息行（冒险等级经验 × 2 行）
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

    -- 12) 扫荡券区域
    -- 背景（仅右侧两角圆角）
    local tkL = D.TKT_BG_CX - D.TKT_BG_W * 0.5
    local tkT = D.TKT_BG_CY - D.TKT_BG_H * 0.5
    nvgBeginPath(vg)
    nvgRoundedRectVarying(vg, tkL, tkT, D.TKT_BG_W, D.TKT_BG_H,
        0, D.TKT_BG_RA, D.TKT_BG_RA, 0)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, D.TKT_BG_A)); nvgFill(vg)
    -- 扫荡券图标
    if imgTicketIcon >= 0 then
        drawImageCentered(vg, imgTicketIcon, D.TKT_ICON_CX, D.TKT_ICON_CY,
            D.TKT_ICON_SZ, D.TKT_ICON_SZ, 1.0)
    end
    -- 文本 "拥有数/消耗数"（白色+黑描边，以 TKT_TXT_CX 为分割点）
    -- 拥有数右对齐于分割点，"/消耗数" 左对齐于分割点，整体视觉上居中于 X=TKT_TXT_CX
    local owned    = GameState.getSweepTicket() or 0
    local ownedStr = tostring(owned)
    local costStr  = "/" .. tostring(SWEEP_COST)
    local tr, tg, tb = 0xff, 0x44, 0x44
    if owned >= SWEEP_COST then tr, tg, tb = 0x63, 0xff, 0x84 end
    drawTextStroke(vg, D.TKT_TXT_CX, D.TKT_TXT_CY, ownedStr,
        D.TKT_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        tr, tg, tb, 4, { strokeColor = { 0, 0, 0 } })
    drawTextStroke(vg, D.TKT_TXT_CX, D.TKT_TXT_CY, costStr,
        D.TKT_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4, { strokeColor = { 0, 0, 0 } })

    -- 13) 确认按钮（扫荡）
    if imgActBtn >= 0 then
        drawImageCentered(vg, imgActBtn, D.ACT_CX, D.ACT_CY, D.ACT_W, D.ACT_H, 1.0)
    else
        -- 图片缺失时用纯色兜底
        nvgBeginPath(vg)
        nvgRoundedRect(vg, D.ACT_CX - D.ACT_W * 0.5, D.ACT_CY - D.ACT_H * 0.5,
            D.ACT_W, D.ACT_H, 16)
        nvgFillColor(vg, nvgRGBA(220, 180, 60, 220)); nvgFill(vg)
    end
    nvgFontFace(vg, "sans"); nvgFontSize(vg, D.ACT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 178))   -- 纯黑 70%
    nvgText(vg, D.ACT_CX, D.ACT_CY, "扫荡", nil)

    nvgRestore(vg)
end

-- ======================== 输入处理 ========================

--- 处理触摸/点击输入
---@param x number 点击X
---@param y number 点击Y
---@return boolean consumed 是否消费事件
function SweepDialog.handleInput(x, y)
    -- 弹窗已打开：优先检测确认按钮，再判断背景外关闭
    if state.open then
        -- 扫荡确认按钮
        if hitTestRect(x, y, D.ACT_CX, D.ACT_CY, D.ACT_W, D.ACT_H) then
            if SweepDialog.onSweep then SweepDialog.onSweep() end
            -- 不关闭面板，让玩家可以连续扫荡；奖励由 RewardPanel 展示后关闭
            return true
        end
        -- 点击背景外关闭
        local inBg = hitTestRect(x, y, D.BG_CX, D.BG_CY, D.BG_W, D.BG_H)
        if not inBg then
            SweepDialog.close()
        end
        return true
    end
    return false
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
