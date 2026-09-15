-- ============================================================================
-- LootBoxPage.lua  —— 全屏战利品管理页面
-- 职责: 展示种子列表（按品质+等级分组），支持单个领取、一键领取、一键分解
-- 渲染: NanoVG 即时模式，设计分辨率 1080×2400
-- ============================================================================

local DrawUtil        = require("core.DrawUtil")
local EquipmentConfig = require("config.EquipmentConfig")
local ImageCache      = require("ui.ImageCache")
local BF              = require("systems.ButtonFeedback")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格
local lastClickX = 0
local lastClickY = 0

local drawTextStroke = DrawUtil.drawTextStroke

local LootBoxPage = {}

-- ======================== 九宫格绘制工具（复用 EquipmentDetail 已验证的实现）========================

--- 九宫格绘制
--- @param vg     any  NanoVG 上下文
--- @param img    number  nvgImage handle
--- @param dx     number  目标左上角 X
--- @param dy     number  目标左上角 Y
--- @param dw     number  目标宽度
--- @param dh     number  目标高度
--- @param iTop   number  上边距 inset
--- @param iRight number  右边距 inset
--- @param iBottom number 下边距 inset
--- @param iLeft  number  左边距 inset
local function drawNineSlice(vg, img, dx, dy, dw, dh, iTop, iRight, iBottom, iLeft)
    if img < 0 then return end

    local srcW, srcH = nvgImageSize(vg, img)
    if srcW <= 0 or srcH <= 0 then return end

    local sL = iLeft
    local sR = iRight
    local sT = iTop
    local sB = iBottom
    local sMW = srcW - sL - sR
    local sMH = srcH - sT - sB

    local dL = math.min(iLeft, dw * 0.5)
    local dR = math.min(iRight, dw * 0.5)
    local dT = math.min(iTop, dh * 0.5)
    local dB = math.min(iBottom, dh * 0.5)

    if sMW <= 0 or sMH <= 0 then
        local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, img, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, dx, dy, dw, dh)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        return
    end

    -- 整数分界点
    local ix0 = math.floor(dx + 0.5)
    local iy0 = math.floor(dy + 0.5)
    local ix1 = math.floor(dx + dL + 0.5)
    local iy1 = math.floor(dy + dT + 0.5)
    local ix2 = math.floor(dx + dw - dR + 0.5)
    local iy2 = math.floor(dy + dh - dB + 0.5)
    local ix3 = math.floor(dx + dw + 0.5)
    local iy3 = math.floor(dy + dh + 0.5)

    -- 9个patch: {destX, destY, destW, destH, srcX, srcY, srcW, srcH}
    -- 绘制顺序：中心→边→角，后画的覆盖先画的，用1px重叠消除缝隙
    local OV = 1
    local patches = {
        -- 中心
        { ix1 - OV, iy1 - OV, ix2 - ix1 + OV * 2, iy2 - iy1 + OV * 2, sL, sT, sMW, sMH },
        -- 四条边
        { ix1 - OV, iy0,      ix2 - ix1 + OV * 2, iy1 - iy0 + OV,     sL,       0,        sMW, sT  },
        { ix1 - OV, iy2 - OV, ix2 - ix1 + OV * 2, iy3 - iy2 + OV,     sL,       sT + sMH, sMW, sB  },
        { ix0,      iy1 - OV, ix1 - ix0 + OV,     iy2 - iy1 + OV * 2, 0,        sT,       sL,  sMH },
        { ix2 - OV, iy1 - OV, ix3 - ix2 + OV,     iy2 - iy1 + OV * 2, sL + sMW, sT,       sR,  sMH },
        -- 四个角
        { ix0,      iy0,      ix1 - ix0 + OV, iy1 - iy0 + OV, 0,        0,        sL, sT  },
        { ix2 - OV, iy0,      ix3 - ix2 + OV, iy1 - iy0 + OV, sL + sMW, 0,        sR, sT  },
        { ix0,      iy2 - OV, ix1 - ix0 + OV, iy3 - iy2 + OV, 0,        sT + sMH, sL, sB  },
        { ix2 - OV, iy2 - OV, ix3 - ix2 + OV, iy3 - iy2 + OV, sL + sMW, sT + sMH, sR, sB  },
    }

    nvgShapeAntiAlias(vg, 0)
    for _, p in ipairs(patches) do
        local px, py, pw, ph = p[1], p[2], p[3], p[4]
        local sx, sy, sw, sh = p[5], p[6], p[7], p[8]
        if pw > 0 and ph > 0 and sw > 0 and sh > 0 then
            local scaleX = pw / sw
            local scaleY = ph / sh
            local paint = nvgImagePattern(vg,
                px - sx * scaleX,
                py - sy * scaleY,
                srcW * scaleX,
                srcH * scaleY,
                0, img, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, px, py, pw, ph)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end
    end
    nvgShapeAntiAlias(vg, 1)
end

-- ======================== 布局常量（设计分辨率 1080×2400）========================

-- 面板
local PANEL_CX, PANEL_CY = 540, 1118
local PANEL_W, PANEL_H   = 950, 1547

-- 面板九宫格 insets（UI_TY_EJQRK 原图尺寸取 950×1547 本身作参考）
local PANEL_9P_TOP, PANEL_9P_RIGHT, PANEL_9P_BOTTOM, PANEL_9P_LEFT = 180, 40, 50, 40

-- 标题
local TITLE_CX, TITLE_CY   = 540, 413
local TITLE_SIZE            = 60
local TITLE_STROKE          = 6
local TITLE_STROKE_R        = 0x59
local TITLE_STROKE_G        = 0x32
local TITLE_STROKE_B        = 0x19

-- 副标题
local SUBTITLE_CX, SUBTITLE_CY = 540, 534
local SUBTITLE_SIZE             = 40

-- 组合条目
local COMBO_CX              = 540          -- 条目背景中心X
local COMBO_FIRST_CY        = 692          -- 第一个条目中心Y
local COMBO_W, COMBO_H      = 864, 216    -- 条目尺寸
local COMBO_GAP             = 10           -- 条目间距
local COMBO_RADIUS          = 16           -- 圆角

-- 品质图标
local ICON_CX_OFFSET        = 219 - 540    -- 相对 COMBO_CX 偏移
local ICON_SIZE             = 160

-- "?" 文本
local Q_MARK_SIZE           = 70

-- 品质文本
local TEXT_LEFT_X           = 343          -- 左对齐 X
local QUALITY_TEXT_Y_OFFSET = -30          -- 相对条目中心的偏移（条目上部）
local QUALITY_TEXT_SIZE     = 50
local QUALITY_STROKE        = 5

-- 数量文本
local COUNT_Y_OFFSET        = 36           -- 相对条目中心
local COUNT_SIZE            = 40
local COUNT_STROKE          = 5

-- 等级文本
local LEVEL_CX_OFFSET       = 219 - 540    -- 同品质图标X
local LEVEL_Y_OFFSET        = 72           -- 相对条目中心
local LEVEL_SIZE            = 40
local LEVEL_STROKE          = 5

-- 领取按钮（每行）
local CLAIM_CX_OFFSET       = 827 - 540    -- 相对 COMBO_CX
local CLAIM_W, CLAIM_H      = 216, 122
local CLAIM_9P              = 35           -- 九宫格 all 35
local CLAIM_TEXT_SIZE        = 40

-- 滚动裁剪底边
local SCROLL_CLIP_BOTTOM    = 1636

-- 底部按钮
local BTN_DECOMPOSE_CX      = 330
local BTN_CLAIM_ALL_CX      = 750
local BTN_Y                 = 1731
local BTN_W, BTN_H          = 390, 100
local BTN_9P_TB, BTN_9P_LR  = 15, 52      -- 九宫格 上下15 左右52
local BTN_TEXT_SIZE          = 40
local BTN_ALL_DECOMP_CX     = 540          -- 全部分解按钮（居中）
local BTN_ALL_DECOMP_Y      = 1950  -- 面板底部(1891)下方，悬浮在面板外

-- 确认弹窗
local CONFIRM_W             = 720
local CONFIRM_H             = 430
local CONFIRM_CX            = 540
local CONFIRM_CY            = 1200
local CONFIRM_BTN_W         = 250
local CONFIRM_BTN_H         = 86
local CONFIRM_CANCEL_CX     = 380
local CONFIRM_OK_CX         = 700
local CONFIRM_BTN_Y         = 1340

-- ======================== 状态 ========================

local state = {
    visible        = false,
    seedSummary    = {},     -- { {quality, level, count}, ... }
    scrollY        = 0,      -- 滚动偏移（正数=向上滚，显示更下面的条目）
    maxScrollY     = 0,      -- 最大滚动量
    dragging       = false,
    dragStartY     = 0,
    dragStartScroll= 0,
    velocity       = 0,      -- 惯性滚动速度
}

-- 图片资源
local imgPanel  = -1   -- UI_TY_EJQRK
local imgBtnGreen = -1  -- UI_AN_FANG (领取按钮)
local imgBtnRed = -1    -- UI_AN_HONG (一键分解按钮)
local imgBtnYellow = -1 -- UI_AN_HUANG (一键领取按钮)
local imgBtnRedFang = -1 -- UI_AN_FANG_hong (分解单个按钮 - 红色方形)

local cachedVg = nil

-- 飘字 toast 状态
local floatText      = nil    -- 飘字文本（nil=不显示）
local floatTextTime  = 0      -- 飘字开始时间

-- 分解模式状态
local decomposeMode = false  -- true=分解模式（领取按钮变分解按钮）

-- 回调
local onClaimOneCallback      = nil   -- function(seedIndex)
local onClaimAllCallback      = nil   -- function()
local onDecomposeAllCallback  = nil   -- function()
local onDecomposeOneCallback  = nil   -- function(seedIndex)
local onCloseCallback         = nil   -- function()
local confirmAllDecomposeOpen = false -- true=显示全部分解二级确认弹窗

-- ======================== 工具 ========================

--- 解析 hex 颜色字符串 "rrggbb" → r, g, b (0-255)
local function hexToRGB(hex)
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    return r, g, b
end

--- 居中绘制图片
local function drawImageCentered(vg, img, cx, cy, w, h, alpha)
    if img < 0 then return end
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha or 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 计算最大滚动量
local function calcMaxScroll()
    local count = #state.seedSummary
    if count <= 0 then
        state.maxScrollY = 0
        return
    end
    -- 所有条目总高度
    local totalH = count * COMBO_H + (count - 1) * COMBO_GAP
    -- 可见区域高度: 从第一个条目顶部到裁剪底边
    local firstTop = COMBO_FIRST_CY - COMBO_H * 0.5
    local visibleH = SCROLL_CLIP_BOTTOM - firstTop
    state.maxScrollY = math.max(0, totalH - visibleH)
end

-- ======================== Public API ========================

--- 初始化
function LootBoxPage.init(vg)
    cachedVg = vg
    imgPanel = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    imgBtnGreen = nvgCreateImage(vg, "image/UI_AN_FANG.png", 0)
    imgBtnRed = nvgCreateImage(vg, "image/UI_AN_HONG.png", 0)
    imgBtnYellow = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    imgBtnRedFang = nvgCreateImage(vg, "image/UI_AN_FANG_hong.png", 0)
    print("[LootBoxPage] init OK, panel=" .. imgPanel
        .. " btnG=" .. imgBtnGreen .. " btnR=" .. imgBtnRed
        .. " btnY=" .. imgBtnYellow .. " btnRF=" .. imgBtnRedFang)
end

--- 设置回调
function LootBoxPage.setOnClaimOne(cb)        onClaimOneCallback = cb end
function LootBoxPage.setOnClaimAll(cb)        onClaimAllCallback = cb end
function LootBoxPage.setOnDecomposeAll(cb)    onDecomposeAllCallback = cb end
function LootBoxPage.setOnDecomposeOne(cb)    onDecomposeOneCallback = cb end
function LootBoxPage.setOnClose(cb)           onCloseCallback = cb end
function LootBoxPage.setOnAutoDecompose(cb)   end

--- 显示页面
function LootBoxPage.show(summary)
    state.visible = true
    state.seedSummary = summary or {}
    state.scrollY = 0
    state.velocity = 0
    state.dragging = false
    decomposeMode = false
    confirmAllDecomposeOpen = false
    calcMaxScroll()
    print("[LootBoxPage] show, items=" .. #state.seedSummary)
end

--- 关闭页面
function LootBoxPage.hide()
    state.visible = false
    state.dragging = false
    confirmAllDecomposeOpen = false
    if onCloseCallback then onCloseCallback() end
end

--- 是否可见
function LootBoxPage.isVisible()
    return state.visible
end

--- 刷新数据（外部数据变化时调用）
function LootBoxPage.refresh(summary)
    state.seedSummary = summary or {}
    calcMaxScroll()
    -- 修正滚动越界
    if state.scrollY > state.maxScrollY then
        state.scrollY = state.maxScrollY
    end
    -- 如果没有内容了，自动关闭
    if #state.seedSummary <= 0 then
        LootBoxPage.hide()
    end
end

--- 更新（惯性滚动）
function LootBoxPage.update(dt)
    if not state.visible then return end

    -- 惯性滚动
    if not state.dragging and math.abs(state.velocity) > 0.5 then
        state.scrollY = state.scrollY + state.velocity * dt
        state.velocity = state.velocity * 0.92  -- 阻尼
        -- 边界钳制
        if state.scrollY < 0 then
            state.scrollY = 0
            state.velocity = 0
        elseif state.scrollY > state.maxScrollY then
            state.scrollY = state.maxScrollY
            state.velocity = 0
        end
    else
        state.velocity = 0
    end
end

--- 绘制
function LootBoxPage.draw(vg)
    -- 飘字 toast：在页面可见性检查前渲染，确保页面隐藏时仍能显示
    if floatText then
        local FLOAT_DURATION = 1.5
        local FLOAT_DIST     = 100
        local elapsed = time.elapsedTime - floatTextTime
        if elapsed >= FLOAT_DURATION then
            floatText = nil
        else
            local t = elapsed / FLOAT_DURATION
            local alpha = 1.0 - t
            local offsetY = -FLOAT_DIST * t
            drawTextStroke(vg, PANEL_CX, PANEL_CY + offsetY, floatText,
                40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 80, 80, 6,
                { alpha = alpha })
        end
    end
    if not state.visible then return end

    -- 1. 全屏黑色遮罩 50%
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
    nvgFill(vg)

    -- 2. 面板背景（九宫格）
    DarkIcon.drawNine(vg, "panel", PANEL_CX - PANEL_W * 0.5, PANEL_CY - PANEL_H * 0.5, PANEL_W, PANEL_H, { titleH = PANEL_9P_TOP })

    -- 3. 标题 "战利品"
    drawTextStroke(vg, TITLE_CX, TITLE_CY, "战利品", TITLE_SIZE,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, TITLE_STROKE,
        { strokeColor = { TITLE_STROKE_R, TITLE_STROKE_G, TITLE_STROKE_B } })

    -- 4. 副标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, SUBTITLE_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 255))
    nvgText(vg, SUBTITLE_CX, SUBTITLE_CY, "战斗中获得的装备会先存在战利品中", nil)

    -- 5. 条目列表（带滚动裁剪）
    nvgSave(vg)
    -- 裁剪区域: 面板内部，从第一个条目顶部到 SCROLL_CLIP_BOTTOM
    local clipTop = COMBO_FIRST_CY - COMBO_H * 0.5 - 10
    local clipH = SCROLL_CLIP_BOTTOM - clipTop
    nvgScissor(vg, PANEL_CX - PANEL_W * 0.5, clipTop, PANEL_W, clipH)

    for i, entry in ipairs(state.seedSummary) do
        local comboY = COMBO_FIRST_CY + (i - 1) * (COMBO_H + COMBO_GAP) - state.scrollY
        -- 跳过不可见的条目
        local itemTop = comboY - COMBO_H * 0.5
        local itemBot = comboY + COMBO_H * 0.5
        if itemBot >= clipTop and itemTop <= SCROLL_CLIP_BOTTOM then
            drawComboItem(vg, entry, i, COMBO_CX, comboY)
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 8-9. 分解按钮（分解模式下显示"取消分解"，正常模式显示"一键分解"）
    local decompBtnText = decomposeMode and "取消分解" or "一键分解"
    local _bfDecomp = BF.begin(vg, "lbp_decompose", BTN_DECOMPOSE_CX, BTN_Y, BTN_W, BTN_H)
    -- [暗黑化 P1-B3] 矢量按钮：分解模式=金 取消分解=红
    DarkIcon.drawNine(vg, "btn",
        BTN_DECOMPOSE_CX - BTN_W * 0.5, BTN_Y - BTN_H * 0.5, BTN_W, BTN_H,
        { accent = decomposeMode and "gold" or "red" })
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BTN_TEXT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))  -- 75% 不透明度
    nvgText(vg, BTN_DECOMPOSE_CX, BTN_Y, decompBtnText, nil)
    BF.finish(vg, _bfDecomp)

    -- 10-11. 一键领取按钮
    local _bfClaimAll = BF.begin(vg, "lbp_claim_all", BTN_CLAIM_ALL_CX, BTN_Y, BTN_W, BTN_H)
    DarkIcon.drawNine(vg, "btn", BTN_CLAIM_ALL_CX - BTN_W * 0.5, BTN_Y - BTN_H * 0.5, BTN_W, BTN_H, { accent = "gold" })
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BTN_TEXT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))  -- 75% 不透明度
    nvgText(vg, BTN_CLAIM_ALL_CX, BTN_Y, "一键领取", nil)
    BF.finish(vg, _bfClaimAll)

    -- 12. 全部分解按钮（居中，面板底部）
    local _bfAllDecomp = BF.begin(vg, "lbp_all_decompose", BTN_ALL_DECOMP_CX, BTN_ALL_DECOMP_Y, BTN_W, BTN_H)
    DarkIcon.drawNine(vg, "btn", BTN_ALL_DECOMP_CX - BTN_W * 0.5, BTN_ALL_DECOMP_Y - BTN_H * 0.5, BTN_W, BTN_H, { accent = "red" })
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BTN_TEXT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))
    nvgText(vg, BTN_ALL_DECOMP_CX, BTN_ALL_DECOMP_Y, "全部分解", nil)
    BF.finish(vg, _bfAllDecomp)

    if confirmAllDecomposeOpen then
        local totalCount = 0
        for _, entry in ipairs(state.seedSummary) do
            totalCount = totalCount + (entry.count or 0)
        end

        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, 1080, 2400)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 170))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, CONFIRM_CX - CONFIRM_W * 0.5, CONFIRM_CY - CONFIRM_H * 0.5,
            CONFIRM_W, CONFIRM_H, 24)
        nvgFillColor(vg, nvgRGBA(245, 228, 200, 245))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(68, 45, 25, 230))
        nvgStrokeWidth(vg, 4)
        nvgStroke(vg)

        drawTextStroke(vg, CONFIRM_CX, CONFIRM_CY - 150, "确认全部分解", 52,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 5,
            { strokeColor = { 68, 45, 25 } })

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 34)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(88, 46, 45, 255))
        nvgText(vg, CONFIRM_CX, CONFIRM_CY - 45, "将分解战利品箱子中的全部装备", nil)
        nvgText(vg, CONFIRM_CX, CONFIRM_CY + 5, "共 " .. tostring(totalCount) .. " 件，分解后无法撤回", nil)
        nvgText(vg, CONFIRM_CX, CONFIRM_CY + 55, "是否继续？", nil)

        local _bfCancel = BF.begin(vg, "lbp_all_decomp_cancel", CONFIRM_CANCEL_CX, CONFIRM_BTN_Y, CONFIRM_BTN_W, CONFIRM_BTN_H)
        DarkIcon.drawNine(vg, "btn", CONFIRM_CANCEL_CX - CONFIRM_BTN_W * 0.5, CONFIRM_BTN_Y - CONFIRM_BTN_H * 0.5, CONFIRM_BTN_W, CONFIRM_BTN_H, { accent = "gold" })
        nvgFontSize(vg, 38)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))
        nvgText(vg, CONFIRM_CANCEL_CX, CONFIRM_BTN_Y, "取消", nil)
        BF.finish(vg, _bfCancel)

        local _bfOk = BF.begin(vg, "lbp_all_decomp_ok", CONFIRM_OK_CX, CONFIRM_BTN_Y, CONFIRM_BTN_W, CONFIRM_BTN_H)
        DarkIcon.drawNine(vg, "btn", CONFIRM_OK_CX - CONFIRM_BTN_W * 0.5, CONFIRM_BTN_Y - CONFIRM_BTN_H * 0.5, CONFIRM_BTN_W, CONFIRM_BTN_H, { accent = "red" })
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))
        nvgText(vg, CONFIRM_OK_CX, CONFIRM_BTN_Y, "确认分解", nil)
        BF.finish(vg, _bfOk)
    end
end

--- 绘制单个组合条目
---@param vg    any
---@param entry table  { quality, level, count }
---@param index number 1-based index
---@param cx    number 中心X
---@param cy    number 中心Y
function drawComboItem(vg, entry, index, cx, cy)
    local quality = entry.quality
    local level   = entry.level
    local count   = entry.count

    -- 5.1 组合背景框（纯黑 5% 不透明度，圆角）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - COMBO_W * 0.5, cy - COMBO_H * 0.5, COMBO_W, COMBO_H, COMBO_RADIUS)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))  -- 5% of 255 ≈ 13
    nvgFill(vg)

    -- 品质信息
    local qDef = EquipmentConfig.QUALITY[quality] or EquipmentConfig.QUALITY[1]
    local qr, qg, qb = hexToRGB(qDef.color)

    -- 5.2 品质背景框图标
    local iconCX = cx + ICON_CX_OFFSET
    local bgImg = ImageCache.getQualityBg(quality)
    drawImageCentered(vg, bgImg, iconCX, cy, ICON_SIZE, ICON_SIZE, 1.0)

    -- 5.3 "?" 问号
    drawTextStroke(vg, iconCX, cy, "?", Q_MARK_SIZE,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)

    -- 5.4 品质文本 (如 "优质装备")
    local qualityLabel = qDef.name .. "装备"
    drawTextStroke(vg, TEXT_LEFT_X, cy + QUALITY_TEXT_Y_OFFSET, qualityLabel, QUALITY_TEXT_SIZE,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, qr, qg, qb, QUALITY_STROKE)

    -- 5.5 数量 (如 "×10")
    local countText = "×" .. tostring(count)
    drawTextStroke(vg, TEXT_LEFT_X, cy + COUNT_Y_OFFSET, countText, COUNT_SIZE,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 255, 255, 255, COUNT_STROKE)

    -- 5.6 等级 (如 "Lv.5")
    local lvText = "Lv." .. tostring(level)
    drawTextStroke(vg, iconCX, cy + LEVEL_Y_OFFSET, lvText, LEVEL_SIZE,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, LEVEL_STROKE)

    -- 5.7 按钮（分解模式下显示红色"分解"，正常模式显示绿色"领取"）[暗黑化 P1-B3]
    local claimCX = cx + CLAIM_CX_OFFSET
    local btnId = decomposeMode and ("lbp_decompose_" .. index) or ("lbp_claim_" .. index)
    local btnText = decomposeMode and "分解" or "领取"
    local _bfClaim = BF.begin(vg, btnId, claimCX, cy, CLAIM_W, CLAIM_H)
    DarkIcon.drawNine(vg, "btn",
        claimCX - CLAIM_W * 0.5, cy - CLAIM_H * 0.5, CLAIM_W, CLAIM_H,
        { accent = decomposeMode and "red" or "green" })

    -- 5.8 按钮文本
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, CLAIM_TEXT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))  -- 75% 不透明度
    nvgText(vg, claimCX, cy, btnText, nil)
    BF.finish(vg, _bfClaim)
end

-- ======================== 输入处理 ========================

--- 处理点击事件（设计空间坐标）
---@param dx number
---@param dy number
---@return boolean 是否消费
function LootBoxPage.handleInput(dx, dy)
    if not state.visible then return false end

    if confirmAllDecomposeOpen then
        if math.abs(dx - CONFIRM_CANCEL_CX) <= CONFIRM_BTN_W * 0.5
           and math.abs(dy - CONFIRM_BTN_Y) <= CONFIRM_BTN_H * 0.5 then
            BF.trigger("lbp_all_decomp_cancel")
            confirmAllDecomposeOpen = false
            return true
        end
        if math.abs(dx - CONFIRM_OK_CX) <= CONFIRM_BTN_W * 0.5
           and math.abs(dy - CONFIRM_BTN_Y) <= CONFIRM_BTN_H * 0.5 then
            BF.trigger("lbp_all_decomp_ok")
            confirmAllDecomposeOpen = false
            if onDecomposeAllCallback then
                onDecomposeAllCallback()
            end
            return true
        end
        return true
    end

    -- 全部分解按钮（位于面板外部，必须在面板边界检测前处理）
    if math.abs(dx - BTN_ALL_DECOMP_CX) <= BTN_W * 0.5
       and math.abs(dy - BTN_ALL_DECOMP_Y) <= BTN_H * 0.5 then
        BF.trigger("lbp_all_decompose")
        if #state.seedSummary <= 0 then
            LootBoxPage.showToast("战利品为空")
        else
            confirmAllDecomposeOpen = true
        end
        return true
    end

    -- 点击遮罩区域（面板外部）→ 关闭
    if dx < PANEL_CX - PANEL_W * 0.5 or dx > PANEL_CX + PANEL_W * 0.5
       or dy < PANEL_CY - PANEL_H * 0.5 or dy > PANEL_CY + PANEL_H * 0.5 then
        LootBoxPage.hide()
        return true
    end

    -- 底部按钮区域
    -- 分解按钮（切换分解模式 / 取消分解模式）
    if math.abs(dx - BTN_DECOMPOSE_CX) <= BTN_W * 0.5
       and math.abs(dy - BTN_Y) <= BTN_H * 0.5 then
        lastClickX = dx
        lastClickY = dy
        BF.trigger("lbp_decompose")
        decomposeMode = not decomposeMode
        return true
    end
    -- 一键领取
    if math.abs(dx - BTN_CLAIM_ALL_CX) <= BTN_W * 0.5
       and math.abs(dy - BTN_Y) <= BTN_H * 0.5 then
        BF.trigger("lbp_claim_all")
        if onClaimAllCallback then
            onClaimAllCallback()
        end
        return true
    end
    -- 条目内的按钮（分解模式→分解单个，正常模式→领取单个）
    for i, entry in ipairs(state.seedSummary) do
        local comboY = COMBO_FIRST_CY + (i - 1) * (COMBO_H + COMBO_GAP) - state.scrollY
        local claimCX = COMBO_CX + CLAIM_CX_OFFSET
        if math.abs(dx - claimCX) <= CLAIM_W * 0.5
           and math.abs(dy - comboY) <= CLAIM_H * 0.5
           and comboY - COMBO_H * 0.5 >= (COMBO_FIRST_CY - COMBO_H * 0.5 - 10)
           and comboY + COMBO_H * 0.5 <= SCROLL_CLIP_BOTTOM then
            if decomposeMode then
                BF.trigger("lbp_decompose_" .. i)
                if onDecomposeOneCallback then
                    onDecomposeOneCallback(i)
                end
            else
                BF.trigger("lbp_claim_" .. i)
                lastClickX = dx
                lastClickY = dy
                if onClaimOneCallback then
                    onClaimOneCallback(i)
                end
            end
            return true
        end
    end

    -- 消费面板内的所有点击（防止穿透）
    return true
end

--- 拖拽开始
function LootBoxPage.handleDragBegin(dx, dy)
    if not state.visible then return false end
    -- 只处理滚动区域内的拖拽
    local clipTop = COMBO_FIRST_CY - COMBO_H * 0.5 - 10
    if dy >= clipTop and dy <= SCROLL_CLIP_BOTTOM
       and dx >= PANEL_CX - PANEL_W * 0.5 and dx <= PANEL_CX + PANEL_W * 0.5 then
        state.dragging = true
        state.dragStartY = dy
        state.dragStartScroll = state.scrollY
        state.velocity = 0
        return true
    end
    return false
end

--- 拖拽移动
function LootBoxPage.handleDragMove(dx, dy)
    if not state.visible or not state.dragging then return false end
    local delta = state.dragStartY - dy
    state.scrollY = state.dragStartScroll + delta
    -- 边界钳制
    if state.scrollY < 0 then state.scrollY = 0 end
    if state.scrollY > state.maxScrollY then state.scrollY = state.maxScrollY end
    -- 计算速度（用于惯性）
    state.velocity = delta / 0.016  -- 近似一帧的速度
    return true
end

--- 拖拽结束
function LootBoxPage.handleDragEnd(dx, dy)
    if not state.visible or not state.dragging then return false end
    state.dragging = false
    -- velocity 保留，update 中做惯性滚动
    return true
end

--- 显示飘字提示（居中向上飘出淡去）
---@param text string
function LootBoxPage.showToast(text)
    floatText     = text
    floatTextTime = time.elapsedTime
end

--- 鼠标滚轮滚动
---@param wheel number 滚轮方向（正=上，负=下）
function LootBoxPage.handleScroll(wheel)
    if not state.visible then return false end
    local step = 80  -- 每格滚动像素
    state.scrollY = state.scrollY - wheel * step
    if state.scrollY < 0 then state.scrollY = 0 end
    if state.scrollY > state.maxScrollY then state.scrollY = state.maxScrollY end
    return true
end

--- 获取最后点击位置
function LootBoxPage.getLastClickPos()
    return lastClickX, lastClickY
end

return LootBoxPage
