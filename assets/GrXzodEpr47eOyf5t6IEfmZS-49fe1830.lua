-- ============================================================================
-- ArenaShopPage - 竞技场商店界面
-- 职责：商品列表绘制、购买交互、刷新倒计时
-- 被 ArenaPage.lua 的商店 Tab 调用
-- ============================================================================

local GameState   = require("core.GameState")
local ArenaConfig = require("config.ArenaConfig")
local DrawUtil        = require("core.DrawUtil")
local drawTextStroke  = DrawUtil.drawTextStroke
local Protocol    = require("shared.Protocol")
local BF          = require("systems.ButtonFeedback")
local RewardPopup = require("ui.RewardPopup")

local ArenaShopPage = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = 1080

-- ======================== 商品配置 ========================

local SHOP_ITEMS = {
    {
        id = 1, name = "随机强化卷轴", quality = 3,
        limitCycle = "weekly", limitCount = 20, price = 50,
        icon = "image/UI_icon_JZ_SJ.png",
        costIcon = "image/UI_icon_JJB_X.png",
        rewardCount = 10,
    },
    {
        id = 2, name = "洗练石", quality = 3,
        limitCycle = "weekly", limitCount = 4, price = 50,
        icon = "image/UI_icon_QH_1.png",
        costIcon = "image/UI_icon_JJB_X.png",
    },
    {
        id = 3, name = "点金石", quality = 5,
        limitCycle = "weekly", limitCount = 3, price = 150,
        icon = "image/UI_icon_QH_3.png",
        costIcon = "image/UI_icon_JJB_X.png",
    },
    {
        id = 4, name = "扫荡券", quality = 4,
        limitCycle = "weekly", limitCount = 2, price = 100,
        icon = "image/UI_icon_SDQ.png",
        costIcon = "image/UI_icon_JJB_X.png",
    },
    {
        id = 5, name = "冒险招募券", quality = 5,
        limitCycle = "weekly", limitCount = 5, price = 150,
        icon = "image/UI_icon_ZMQ_1.png",
        costIcon = "image/UI_icon_JJB_X.png",
    },
    {
        id = 6, name = "光之圣女-碎片", quality = 5,
        limitCycle = "weekly", limitCount = 1, price = 4000,
        icon = "image/角色图标/UI_icon_hero_15.png",
        costIcon = "image/UI_icon_JJB_X.png",
        rewardCount = 10,
        isShard = true, heroId = 15,
    },
}

-- ======================== 布局常量 ========================

---@type table
local L = {
    -- 标题
    TITLE_CX = 540, TITLE_CY = 497, TITLE_FONT = 42,
    TITLE_R = 0x7b, TITLE_G = 0x53, TITLE_B = 0x39,
    -- 刷新倒计时
    CD_CX = 540, CD_CY = 560, CD_FONT = 42,
    CD_LR = 0x45, CD_LG = 0x45, CD_LB = 0x45,
    CD_VR = 0xff, CD_VG = 0x2c, CD_VB = 0x2c,
    -- 商品卡片
    CARD_W = 314, CARD_H = 402,
    CARD_COLS = 3,
    CARD_GAP_X = 30, CARD_GAP_Y = 15,
    -- 第一个商品位置 (cx=195 → 左对齐推算)
    GRID_TOP_CY = 827,    -- 第一行中心Y
    -- 商品子元素（相对于卡片中心）
    NAME_OY = -160,   -- 商品名 Y偏移 (667-827)
    NAME_FONT = 38, NAME_SW = 5,
    ICON_OY = -44,    -- 商品图标 Y偏移 (783-827)
    ICON_W = 160, ICON_H = 160,
    COUNT_OX = 54, COUNT_OY = 6,   -- 数量角标 (249-195, 833-827)
    COUNT_FONT = 42, COUNT_SW = 5,
    LIMIT_OY = 66,    -- 限购文本 Y偏移 (893-827)
    LIMIT_FONT = 32,
    LIMIT_R = 0x4e, LIMIT_G = 0x4e, LIMIT_B = 0x4e,
    -- 购买按钮
    BTN_OY = 133,     -- 按钮中心 Y偏移 (960-827)
    BTN_W = 286, BTN_H = 84,
    BTN_ICON_W = 82, BTN_ICON_H = 82,
    BTN_FONT = 40, BTN_SW = 5,
}

-- 计算网格：3列居中
local TOTAL_GRID_W = L.CARD_COLS * L.CARD_W + (L.CARD_COLS - 1) * L.CARD_GAP_X
local GRID_LEFT = (DESIGN_W - TOTAL_GRID_W) * 0.5 + L.CARD_W * 0.5  -- 第一列中心X
local CARD_STEP_X = L.CARD_W + L.CARD_GAP_X
local CARD_STEP_Y = L.CARD_H + L.CARD_GAP_Y

-- ======================== 图片句柄 ========================

local shopImg = {
    cardBg = {},    -- 品质1~5 → UI_SDICONBJ_1~5.png
    buyBtn = -1,    -- UI_SD_AN.png
    itemIcons = {}, -- 每个商品的图标
    costIcons = {}, -- 每个商品的消耗图标
    -- 二级弹窗
    dialogBg = -1,  -- UI_TY_EJQRK.png
    buyBtnYellow = -1, -- UI_AN_HUANG.png
    btnMinus = -1,  -- UI_AN_JIAN.png
    btnPlus = -1,   -- UI_AN_JIA.png
    coinIcon = -1,  -- UI_icon_JJB_X.png（弹窗消耗侧竞技币图标）
    qualityBg = {}, -- 品质1~5 → UI_icon_ZBBJ_1~5.png（通用资源品质框）
}

-- ======================== 弹窗动画常量 ========================

local POPUP_OPEN_DUR   = 0.25
local POPUP_CLOSE_DUR  = 0.20
local POPUP_SCALE_FROM = 0.8
local POPUP_SCALE_TO   = 1.0

local function easeOutCubic(t) local f = t - 1; return f * f * f + 1 end
local function easeInCubic(t) return t * t * t end

-- ======================== 状态 ========================

local shopState = {
    purchased = {},   -- { [itemId] = count } 本周已购买次数
    scrollY = 0,
    dragging = false,
    lastDragY = 0,
    -- 二级弹窗
    dialogOpen = false,
    dialogItemIdx = nil,  -- 当前弹窗对应的商品索引
    -- 弹窗动画
    popupAnimTime  = 0,
    popupClosing   = false,
    popupCloseTime = 0,
    -- 批量购买
    buyQuantity    = 1,
    buyMaxQuantity = 1,
    sliderDragging = false,
    -- 浮动提示
    floatText      = nil,
    floatTextX     = 0,
    floatTextY     = 0,
    floatTextTime  = 0,
}

-- ======================== 滚动区域 ========================

local SCROLL_TOP = 610        -- 标题下方开始
local SCROLL_BOT = 2240       -- tab 栏上方

-- ======================== Init ========================

function ArenaShopPage.init(vg)
    for i = 1, 5 do
        shopImg.cardBg[i] = nvgCreateImage(vg, "image/UI_SDICONBJ_" .. i .. ".png", 0)
    end
    shopImg.buyBtn = nvgCreateImage(vg, "image/UI_SD_AN.png", 0)

    for idx, item in ipairs(SHOP_ITEMS) do
        shopImg.itemIcons[idx] = nvgCreateImage(vg, item.icon, 0)
        shopImg.costIcons[idx] = nvgCreateImage(vg, item.costIcon, 0)
    end

    -- 二级弹窗图片
    shopImg.dialogBg = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    shopImg.buyBtnYellow = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    shopImg.btnMinus = nvgCreateImage(vg, "image/UI_AN_JIAN.png", 0)
    shopImg.btnPlus = nvgCreateImage(vg, "image/UI_AN_JIA.png", 0)
    shopImg.coinIcon = nvgCreateImage(vg, "image/UI_icon_JJB_X.png", 0)
    for i = 1, 6 do
        shopImg.qualityBg[i] = nvgCreateImage(vg, "image/UI_icon_ZBBJ_" .. i .. ".png", 0)
    end

    -- 碎片角标资源（DrawUtil 内部去重，多次调用安全）
    DrawUtil.initShardAssets(vg)

    shopState.purchased = {}
    shopState.scrollY = 0
    shopState.dialogOpen = false
    shopState.dialogItemIdx = nil
    print("[ArenaShopPage] init OK, items=" .. #SHOP_ITEMS)
end

-- ======================== 工具函数 ========================

local function drawImageCentered(vg, imgH, cx, cy, w, h, alpha)
    if imgH < 0 or alpha <= 0.01 then return end
    local x, y = cx - w * 0.5, cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, imgH, alpha)
    nvgBeginPath(vg); nvgRect(vg, x, y, w, h); nvgFillPaint(vg, paint); nvgFill(vg)
end

local function drawNineSlice(vg, imgH, dx, dy, dw, dh, iTop, iRight, iBottom, iLeft)
    if imgH < 0 then return end
    local srcW, srcH = nvgImageSize(vg, imgH)
    if srcW <= 0 or srcH <= 0 then return end
    local sL, sR, sT, sB = iLeft, iRight, iTop, iBottom
    local sMW, sMH = srcW - sL - sR, srcH - sT - sB
    if sMW <= 0 or sMH <= 0 then
        local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, imgH, 1.0)
        nvgBeginPath(vg); nvgRect(vg, dx, dy, dw, dh); nvgFillPaint(vg, paint); nvgFill(vg)
        return
    end
    local OV = 1
    local ix0, iy0 = math.floor(dx + 0.5), math.floor(dy + 0.5)
    local dL = math.min(iLeft, dw * 0.5)
    local dR = math.min(iRight, dw * 0.5)
    local dT = math.min(iTop, dh * 0.5)
    local dB = math.min(iBottom, dh * 0.5)
    local ix1, iy1 = math.floor(dx + dL + 0.5), math.floor(dy + dT + 0.5)
    local ix2, iy2 = math.floor(dx + dw - dR + 0.5), math.floor(dy + dh - dB + 0.5)
    local ix3, iy3 = math.floor(dx + dw + 0.5), math.floor(dy + dh + 0.5)
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

local function hitTest(dx, dy, cx, cy, w, h)
    return dx >= cx - w * 0.5 and dx <= cx + w * 0.5
       and dy >= cy - h * 0.5 and dy <= cy + h * 0.5
end

-- ======================== 弹窗动画辅助 ========================

local function getPopupAnim()
    if shopState.popupClosing then
        local t = math.min(1.0, (time.elapsedTime - shopState.popupCloseTime) / POPUP_CLOSE_DUR)
        local e = easeInCubic(t)
        local scale = POPUP_SCALE_TO + (POPUP_SCALE_FROM - POPUP_SCALE_TO) * e
        return scale, 1.0 - e, (t >= 1.0)
    else
        local t = math.min(1.0, (time.elapsedTime - shopState.popupAnimTime) / POPUP_OPEN_DUR)
        local e = easeOutCubic(t)
        local scale = POPUP_SCALE_FROM + (POPUP_SCALE_TO - POPUP_SCALE_FROM) * e
        return scale, e, false
    end
end

-- ======================== 获取已购次数 ========================

local function getPurchased(itemId)
    return shopState.purchased[itemId] or 0
end

local function isSoldOut(item)
    return getPurchased(item.id) >= item.limitCount
end

-- 前向声明（drawPurchaseDialog 定义在 drawContent 之后，但在 drawContent 中调用）
local drawPurchaseDialog

-- ======================== 绘制单个商品卡片 ========================

local function drawShopCard(vg, idx, item, cx, cy)
    -- 1) 品质背景
    local bgImg = shopImg.cardBg[item.quality] or shopImg.cardBg[1]
    drawNineSlice(vg, bgImg,
        cx - L.CARD_W * 0.5, cy - L.CARD_H * 0.5,
        L.CARD_W, L.CARD_H, 20, 20, 20, 20)

    local bought = getPurchased(item.id)
    local soldOut = bought >= item.limitCount

    -- 2) 商品名
    drawTextStroke(vg, cx, cy + L.NAME_OY, item.name,
        L.NAME_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, L.NAME_SW, { strokeColor = { 0, 0, 0 } })

    -- 3) 商品图标（碎片商品加角标）
    local iconImg = shopImg.itemIcons[idx]
    if item.isShard and item.heroId then
        DrawUtil.drawShardIcon(vg, item.heroId, cx, cy + L.ICON_OY, L.ICON_W, soldOut and 0.4 or 1.0)
    elseif iconImg and iconImg >= 0 then
        drawImageCentered(vg, iconImg, cx, cy + L.ICON_OY, L.ICON_W, L.ICON_H, soldOut and 0.4 or 1.0)
    end

    -- 4) 数量角标（每次购买获得的数量，仅非角色商品）
    if not item.isHero then
        drawTextStroke(vg, cx + L.COUNT_OX, cy + L.COUNT_OY, tostring(item.rewardCount or 1),
            L.COUNT_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
            255, 255, 255, L.COUNT_SW, { strokeColor = { 0, 0, 0 } })
    end

    -- 5) 限购文本（显示剩余可购买次数）
    local remaining = item.limitCount - bought
    if remaining < 0 then remaining = 0 end
    local limitText
    if item.limitCycle == "forever" then
        limitText = "限购" .. remaining .. "次"
    else
        limitText = "限购" .. remaining .. "次/周"
    end
    nvgFontFace(vg, "sans"); nvgFontSize(vg, L.LIMIT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(L.LIMIT_R, L.LIMIT_G, L.LIMIT_B, 255))
    nvgText(vg, cx, cy + L.LIMIT_OY, limitText, nil)

    -- 6) 购买按钮背景
    local btnCY = cy + L.BTN_OY
    if soldOut then
        -- 已售罄：灰色蒙版
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - L.BTN_W * 0.5, btnCY - L.BTN_H * 0.5, L.BTN_W, L.BTN_H, 12)
        nvgFillColor(vg, nvgRGBA(80, 80, 80, 200))
        nvgFill(vg)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, L.BTN_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
        nvgText(vg, cx, btnCY, "已售罄", nil)
    else
        local _bfCard = BF.begin(vg, "asp_item_" .. idx, cx, btnCY, L.BTN_W, L.BTN_H)
        drawNineSlice(vg, shopImg.buyBtn,
            cx - L.BTN_W * 0.5, btnCY - L.BTN_H * 0.5,
            L.BTN_W, L.BTN_H, 10, 30, 10, 30)

        -- 7) 消耗组合（图标 + 价格）居中
        local priceStr = tostring(item.price)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, L.BTN_FONT)
        local bounds = {}
        local textW = nvgTextBounds(vg, 0, 0, priceStr, nil, bounds)
        local iconW = L.BTN_ICON_W
        local iconH = L.BTN_ICON_H
        local gap = 4
        local totalW = iconW + gap + textW
        local startX = cx - totalW * 0.5

        local costImg = shopImg.costIcons[idx]
        if costImg and costImg >= 0 then
            drawImageCentered(vg, costImg, startX + iconW * 0.5, btnCY, iconW, iconH, 1.0)
        end
        drawTextStroke(vg, startX + iconW + gap, btnCY, priceStr,
            L.BTN_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            255, 255, 255, L.BTN_SW, { strokeColor = { 0, 0, 0 } })
        BF.finish(vg, _bfCard)
    end
end

-- ======================== 主绘制 ========================

function ArenaShopPage.drawContent(vg, weekId)
    -- 标题
    nvgFontFace(vg, "sans"); nvgFontSize(vg, L.TITLE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(L.TITLE_R, L.TITLE_G, L.TITLE_B, 255))
    nvgText(vg, L.TITLE_CX, L.TITLE_CY, "竞技场商店", nil)

    -- 刷新倒计时
    local nextSettlement = ArenaConfig.WEEK_EPOCH + ((weekId or 0) + 1) * ArenaConfig.WEEK_SECONDS
    local remainSec = math.max(0, nextSettlement - os.time())
    local days  = math.floor(remainSec / 86400)
    local hours = math.floor((remainSec % 86400) / 3600)
    local valueText
    if days > 0 then
        valueText = days .. "天" .. hours .. "时"
    else
        local mins = math.floor((remainSec % 3600) / 60)
        valueText = hours .. "时" .. mins .. "分"
    end
    local labelText = "刷新倒计时："
    nvgFontFace(vg, "sans"); nvgFontSize(vg, L.CD_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local bounds = {}
    local labelW = nvgTextBounds(vg, 0, 0, labelText, nil, bounds)
    local valueW = nvgTextBounds(vg, 0, 0, valueText, nil, bounds)
    local startX = L.CD_CX - (labelW + valueW) * 0.5

    nvgFillColor(vg, nvgRGBA(L.CD_LR, L.CD_LG, L.CD_LB, 255))
    nvgText(vg, startX, L.CD_CY, labelText, nil)
    nvgFillColor(vg, nvgRGBA(L.CD_VR, L.CD_VG, L.CD_VB, 255))
    nvgText(vg, startX + labelW, L.CD_CY, valueText, nil)

    -- 商品网格（可滚动区域）
    local rowCount = math.ceil(#SHOP_ITEMS / L.CARD_COLS)
    local totalH = rowCount * CARD_STEP_Y - L.CARD_GAP_Y
    local clipH = SCROLL_BOT - SCROLL_TOP
    local maxScroll = math.max(0, totalH - clipH)
    shopState.scrollY = math.max(0, math.min(shopState.scrollY, maxScroll))

    nvgSave(vg)
    nvgIntersectScissor(vg, 20, SCROLL_TOP, DESIGN_W - 40, clipH)
    nvgTranslate(vg, 0, -shopState.scrollY)

    for idx, item in ipairs(SHOP_ITEMS) do
        local col = ((idx - 1) % L.CARD_COLS)        -- 0,1,2
        local row = math.floor((idx - 1) / L.CARD_COLS)  -- 0,1,...
        local cx = GRID_LEFT + col * CARD_STEP_X
        local cy = L.GRID_TOP_CY + row * CARD_STEP_Y

        -- 可视剔除
        local screenCY = cy - shopState.scrollY
        if screenCY >= SCROLL_TOP - L.CARD_H and screenCY <= SCROLL_BOT + L.CARD_H then
            drawShopCard(vg, idx, item, cx, cy)
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 绘制二级弹窗（在最顶层）
    drawPurchaseDialog(vg)
end

-- ======================== 二级购买确认弹窗（与 MarketPage 统一样式） ========================

local DLG = {
    -- 确认框
    BG_CX = 540, BG_CY = 1211, BG_W = 950, BG_H = 847,
    BG_IT = 150, BG_IR = 60, BG_IB = 100, BG_IL = 60,
    -- 标题
    TITLE_CX = 540, TITLE_CY = 855, TITLE_FONT = 60, TITLE_SW = 6,
    TITLE_SR = 0x46, TITLE_SG = 0x2f, TITLE_SB = 0x20,
    -- 副标题
    SUB_CX = 540, SUB_CY = 967, SUB_FONT = 40,
    SUB_R = 0xb6, SUB_G = 0xb0, SUB_B = 0x9d,
    -- 内容背景框
    CONTENT_CX = 540, CONTENT_CY = 1121, CONTENT_W = 800, CONTENT_H = 218, CONTENT_R = 16,
    -- 商品图标（居中）
    ITEM_CX = 540, ITEM_CY = 1122, ITEM_ICON_SIZE = 160,
    -- 数量角标
    BADGE_FONT = 40, BADGE_SW = 5,
    BADGE_OX = 56, BADGE_OY = 50,
    -- 购买数量文本
    QTY_CX = 540, QTY_CY = 1278, QTY_FONT = 40, QTY_SW = 5,
    -- 减/加按钮
    MINUS_CX = 282, MINUS_CY = 1342, MINUS_W = 84, MINUS_H = 84,
    PLUS_CX = 808, PLUS_CY = 1342, PLUS_W = 84, PLUS_H = 84,
    -- 滑条
    SLIDER_CX = 540, SLIDER_CY = 1342, SLIDER_W = 400, SLIDER_H = 24, SLIDER_R = 12,
    KNOB_SIZE = 36,
    KNOB_STROKE_R = 0x44, KNOB_STROKE_G = 0x2d, KNOB_STROKE_B = 0x19, KNOB_STROKE_W = 6,
    -- 消耗资源（图标+文本居中排列）
    COST_CX = 540, COST_CY = 1416, COST_ICON_SIZE = 70, COST_FONT = 40, COST_SW = 5,
    -- 购买按钮
    BUY_CX = 540, BUY_CY = 1503, BUY_W = 410, BUY_H = 100, BUY_FONT = 40,
}

-- ======================== 二级弹窗绘制 ========================

drawPurchaseDialog = function(vg)
    if not shopState.dialogOpen or not shopState.dialogItemIdx then return end
    local idx = shopState.dialogItemIdx
    local item = SHOP_ITEMS[idx]
    if not item then return end

    local pScale, pAlpha, _ = getPopupAnim()

    -- 1) 纯黑遮罩 50%
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * pAlpha)))
    nvgFill(vg)

    -- scale+fade
    nvgSave(vg)
    nvgTranslate(vg, DLG.BG_CX, DLG.BG_CY)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -DLG.BG_CX, -DLG.BG_CY)
    nvgGlobalAlpha(vg, pAlpha)

    -- 2) 背景（九宫格 上150 下100 左右60）
    drawNineSlice(vg, shopImg.dialogBg,
        DLG.BG_CX - DLG.BG_W * 0.5, DLG.BG_CY - DLG.BG_H * 0.5,
        DLG.BG_W, DLG.BG_H, DLG.BG_IT, DLG.BG_IR, DLG.BG_IB, DLG.BG_IL)

    -- 3) 标题"购买道具"
    drawTextStroke(vg, DLG.TITLE_CX, DLG.TITLE_CY, "购买道具",
        DLG.TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DLG.TITLE_SW,
        { strokeColor = { DLG.TITLE_SR, DLG.TITLE_SG, DLG.TITLE_SB } })

    -- 4) 副标题"是否购买此道具"
    nvgFontFace(vg, "sans"); nvgFontSize(vg, DLG.SUB_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(DLG.SUB_R, DLG.SUB_G, DLG.SUB_B, 255))
    nvgText(vg, DLG.SUB_CX, DLG.SUB_CY, "是否购买此道具", nil)

    -- 5) 商品背景框
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        DLG.CONTENT_CX - DLG.CONTENT_W * 0.5,
        DLG.CONTENT_CY - DLG.CONTENT_H * 0.5,
        DLG.CONTENT_W, DLG.CONTENT_H, DLG.CONTENT_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))
    nvgFill(vg)

    -- 6) 品质背景 + 商品图标（居中，碎片加角标）
    local rewardBg = shopImg.qualityBg[item.quality] or shopImg.qualityBg[1]
    drawImageCentered(vg, rewardBg,
        DLG.ITEM_CX, DLG.ITEM_CY, DLG.ITEM_ICON_SIZE, DLG.ITEM_ICON_SIZE, 1.0)
    if item.isShard and item.heroId then
        DrawUtil.drawShardIcon(vg, item.heroId, DLG.ITEM_CX, DLG.ITEM_CY, DLG.ITEM_ICON_SIZE, 1.0)
    else
        local rewardImg = shopImg.itemIcons[idx]
        if rewardImg and rewardImg >= 0 then
            drawImageCentered(vg, rewardImg,
                DLG.ITEM_CX, DLG.ITEM_CY, DLG.ITEM_ICON_SIZE, DLG.ITEM_ICON_SIZE, 1.0)
        end
    end

    -- 7) 角标（图标右下角）
    drawTextStroke(vg,
        DLG.ITEM_CX + DLG.BADGE_OX, DLG.ITEM_CY + DLG.BADGE_OY,
        tostring(item.rewardCount or 1),
        DLG.BADGE_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        255, 255, 255, DLG.BADGE_SW, { strokeColor = { 0, 0, 0 } })

    -- 8) 购买数量文本 "购买数量:N"
    local qtyText = "购买数量:" .. shopState.buyQuantity
    drawTextStroke(vg, DLG.QTY_CX, DLG.QTY_CY, qtyText,
        DLG.QTY_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DLG.QTY_SW, { strokeColor = { 0, 0, 0 } })

    -- 9) 减按钮
    local _sm = BF.begin(vg, "asp_dlg_minus", DLG.MINUS_CX, DLG.MINUS_CY, DLG.MINUS_W, DLG.MINUS_H)
    drawImageCentered(vg, shopImg.btnMinus,
        DLG.MINUS_CX, DLG.MINUS_CY, DLG.MINUS_W, DLG.MINUS_H,
        shopState.buyQuantity <= 1 and 0.4 or 1.0)
    BF.finish(vg, _sm)

    -- 10) 加按钮
    local _sp = BF.begin(vg, "asp_dlg_plus", DLG.PLUS_CX, DLG.PLUS_CY, DLG.PLUS_W, DLG.PLUS_H)
    drawImageCentered(vg, shopImg.btnPlus,
        DLG.PLUS_CX, DLG.PLUS_CY, DLG.PLUS_W, DLG.PLUS_H,
        shopState.buyQuantity >= shopState.buyMaxQuantity and 0.4 or 1.0)
    BF.finish(vg, _sp)

    -- 11) 滑条背景
    local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sliderL, DLG.SLIDER_CY - DLG.SLIDER_H * 0.5,
        DLG.SLIDER_W, DLG.SLIDER_H, DLG.SLIDER_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 51))
    nvgFill(vg)

    -- 已填充部分
    local sliderFrac = 0
    if shopState.buyMaxQuantity > 1 then
        sliderFrac = (shopState.buyQuantity - 1) / (shopState.buyMaxQuantity - 1)
    end
    local fillW = DLG.SLIDER_W * sliderFrac
    if fillW > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sliderL, DLG.SLIDER_CY - DLG.SLIDER_H * 0.5,
            fillW, DLG.SLIDER_H, DLG.SLIDER_R)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 80))
        nvgFill(vg)
    end

    -- 12) 滑块（圆形，纯白+描边）
    local knobX = sliderL + DLG.SLIDER_W * sliderFrac
    local knobR = DLG.KNOB_SIZE * 0.5
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, DLG.SLIDER_CY, knobR)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(DLG.KNOB_STROKE_R, DLG.KNOB_STROKE_G, DLG.KNOB_STROKE_B, 255))
    nvgStrokeWidth(vg, DLG.KNOB_STROKE_W)
    nvgStroke(vg)

    -- 13) 消耗资源组合 "图标×N"
    local totalCost = item.price * shopState.buyQuantity
    local costStr = "×" .. tostring(totalCost)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, DLG.COST_FONT)
    local costTextW = nvgTextBounds(vg, 0, 0, costStr)
    local costIconW = DLG.COST_ICON_SIZE
    local costGap = 4
    local costTotalW = costIconW + costGap + costTextW
    local costStartX = DLG.COST_CX - costTotalW * 0.5
    drawImageCentered(vg, shopImg.coinIcon,
        costStartX + costIconW * 0.5, DLG.COST_CY, costIconW, DLG.COST_ICON_SIZE, 1.0)
    drawTextStroke(vg, costStartX + costIconW + costGap, DLG.COST_CY, costStr,
        DLG.COST_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, DLG.COST_SW, { strokeColor = { 0, 0, 0 } })

    -- 14) 购买按钮
    local _bfBuy = BF.begin(vg, "asp_confirm", DLG.BUY_CX, DLG.BUY_CY, DLG.BUY_W, DLG.BUY_H)
    drawNineSlice(vg, shopImg.buyBtnYellow,
        DLG.BUY_CX - DLG.BUY_W * 0.5, DLG.BUY_CY - DLG.BUY_H * 0.5,
        DLG.BUY_W, DLG.BUY_H, 10, 30, 10, 30)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, DLG.BUY_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 179))
    nvgText(vg, DLG.BUY_CX, DLG.BUY_CY, "购买", nil)
    BF.finish(vg, _bfBuy)

    -- 15) 浮动提示（在 scale 变换内绘制）
    if shopState.floatText then
        local FLOAT_DURATION = 1.5
        local FLOAT_DIST     = 100
        local elapsed = time.elapsedTime - shopState.floatTextTime
        if elapsed >= FLOAT_DURATION then
            shopState.floatText = nil
        else
            local t = elapsed / FLOAT_DURATION
            local alpha = 1.0 - t
            local offsetY = -FLOAT_DIST * t
            drawTextStroke(vg, shopState.floatTextX, shopState.floatTextY + offsetY,
                shopState.floatText,
                40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 80, 80, 6,
                { alpha = alpha })
        end
    end

    nvgRestore(vg)
end

-- ======================== 输入处理 ========================

function ArenaShopPage.handleInput(dx, dy)
    -- 弹窗打开时优先处理弹窗交互
    if shopState.dialogOpen then
        -- 关闭动画期间阻断所有输入
        if shopState.popupClosing then return true end

        -- 减按钮
        if hitTest(dx, dy, DLG.MINUS_CX, DLG.MINUS_CY, DLG.MINUS_W, DLG.MINUS_H) then
            BF.trigger("asp_dlg_minus")
            if shopState.buyQuantity > 1 then
                shopState.buyQuantity = shopState.buyQuantity - 1
            end
            return true
        end

        -- 加按钮
        if hitTest(dx, dy, DLG.PLUS_CX, DLG.PLUS_CY, DLG.PLUS_W, DLG.PLUS_H) then
            BF.trigger("asp_dlg_plus")
            if shopState.buyQuantity < shopState.buyMaxQuantity then
                shopState.buyQuantity = shopState.buyQuantity + 1
            end
            return true
        end

        -- 滑条点击（整个滑条区域 + 滑块溢出范围）
        local sliderHitH = math.max(DLG.SLIDER_H, DLG.KNOB_SIZE) + 20
        if hitTest(dx, dy, DLG.SLIDER_CX, DLG.SLIDER_CY, DLG.SLIDER_W + DLG.KNOB_SIZE, sliderHitH) then
            local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
            local frac = math.max(0, math.min(1, (dx - sliderL) / DLG.SLIDER_W))
            local qty = math.floor(frac * (shopState.buyMaxQuantity - 1) + 0.5) + 1
            shopState.buyQuantity = math.max(1, math.min(shopState.buyMaxQuantity, qty))
            shopState.sliderDragging = true
            return true
        end

        -- 点击购买按钮 → 确认购买
        if hitTest(dx, dy, DLG.BUY_CX, DLG.BUY_CY, DLG.BUY_W, DLG.BUY_H) then
            BF.trigger("asp_confirm")
            local idx = shopState.dialogItemIdx
            local item = SHOP_ITEMS[idx]
            if item then
                local totalCost = item.price * shopState.buyQuantity
                local coins = GameState.getArenaCoin()
                if coins < totalCost then
                    print("[ArenaShop] 竞技币不足: 需要" .. totalCost .. " 当前" .. coins)
                    shopState.floatText = "竞技币不足"
                    shopState.floatTextX = DLG.BUY_CX
                    shopState.floatTextY = DLG.BUY_CY
                    shopState.floatTextTime = time.elapsedTime
                    return true
                else
                    print("[ArenaShop] 发送购买请求: itemId=" .. item.id .. " qty=" .. shopState.buyQuantity .. " (" .. item.name .. ")")
                    require("network.Client").sendAction(Protocol.ACTION_TYPES.ARENA_SHOP_BUY, {
                        itemId = item.id,
                        quantity = shopState.buyQuantity,
                    })
                end
            end
            shopState.popupClosing = true
            shopState.popupCloseTime = time.elapsedTime
            return true
        end

        -- 同帧保护：防止弹窗打开同帧的点击事件立即关闭弹窗
        if time.elapsedTime - shopState.popupAnimTime < 0.05 then return true end

        -- 点击确认框外部 → 关闭弹窗（动画）
        if not hitTest(dx, dy, DLG.BG_CX, DLG.BG_CY, DLG.BG_W, DLG.BG_H) then
            shopState.popupClosing = true
            shopState.popupCloseTime = time.elapsedTime
        end
        return true  -- 弹窗打开时吞掉所有点击
    end

    -- 检测点击了哪个商品的购买按钮 → 打开二级弹窗
    for idx, item in ipairs(SHOP_ITEMS) do
        local col = ((idx - 1) % L.CARD_COLS)
        local row = math.floor((idx - 1) / L.CARD_COLS)
        local cx = GRID_LEFT + col * CARD_STEP_X
        local cy = L.GRID_TOP_CY + row * CARD_STEP_Y - shopState.scrollY

        local btnCY = cy + L.BTN_OY
        if hitTest(dx, dy, cx, btnCY, L.BTN_W, L.BTN_H) then
            if isSoldOut(item) then
                print("[ArenaShop] 商品已售罄: " .. item.name)
                return true
            end
            BF.trigger("asp_item_" .. idx)
            -- 打开确认弹窗
            shopState.dialogOpen = true
            shopState.dialogItemIdx = idx
            shopState.popupAnimTime = time.elapsedTime
            shopState.popupClosing = false
            shopState.sliderDragging = false
            -- 计算最大可购买数量
            shopState.buyQuantity = 1
            local bought = getPurchased(item.id)
            shopState.buyMaxQuantity = math.max(1, item.limitCount - bought)
            print("[ArenaShop] 打开购买确认: " .. item.name .. " maxQty=" .. shopState.buyMaxQuantity)
            return true
        end
    end
    return false
end

-- ======================== 滚动 ========================

function ArenaShopPage.handleDragBegin(dx, dy)
    if shopState.dialogOpen then
        if shopState.popupClosing then return true end
        -- 滑条拖拽开始
        local sliderHitH = math.max(DLG.SLIDER_H, DLG.KNOB_SIZE) + 20
        if hitTest(dx, dy, DLG.SLIDER_CX, DLG.SLIDER_CY, DLG.SLIDER_W + DLG.KNOB_SIZE, sliderHitH) then
            shopState.sliderDragging = true
            local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
            local frac = math.max(0, math.min(1, (dx - sliderL) / DLG.SLIDER_W))
            local qty = math.floor(frac * (shopState.buyMaxQuantity - 1) + 0.5) + 1
            shopState.buyQuantity = math.max(1, math.min(shopState.buyMaxQuantity, qty))
        end
        return true
    end
    if dy >= SCROLL_TOP and dy <= SCROLL_BOT then
        shopState.dragging = true
        shopState.lastDragY = dy
        return true
    end
    return false
end

function ArenaShopPage.handleDragMove(dx, dy)
    if shopState.dialogOpen then
        if shopState.sliderDragging and not shopState.popupClosing then
            local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
            local frac = math.max(0, math.min(1, (dx - sliderL) / DLG.SLIDER_W))
            local qty = math.floor(frac * (shopState.buyMaxQuantity - 1) + 0.5) + 1
            shopState.buyQuantity = math.max(1, math.min(shopState.buyMaxQuantity, qty))
        end
        return true
    end
    if shopState.dragging then
        shopState.scrollY = shopState.scrollY + (shopState.lastDragY - dy)
        shopState.lastDragY = dy
        return true
    end
    return false
end

function ArenaShopPage.handleDragEnd()
    shopState.sliderDragging = false
    shopState.dragging = false
end

function ArenaShopPage.isDragging()
    return shopState.dragging or shopState.sliderDragging
end

function ArenaShopPage.handleScroll(wheel)
    if shopState.dialogOpen or shopState.popupClosing then return end  -- 弹窗打开时阻止滚动
    shopState.scrollY = shopState.scrollY - wheel * 60
end

function ArenaShopPage.resetScroll()
    shopState.scrollY = 0
    shopState.dragging = false
end

-- ======================== 服务器响应 ========================

--- 设置已购买数据（由 ArenaPage.onActionResult 调用）
--- 注意：cjson.decode 将 JSON 数字键反序列化为字符串键，需要转换为数字键
---@param purchased table { [itemId] = count }
function ArenaShopPage.setPurchased(purchased)
    local fixed = {}
    if purchased then
        for k, v in pairs(purchased) do
            local numK = tonumber(k)
            if numK then
                fixed[numK] = tonumber(v) or 0
            end
        end
    end
    shopState.purchased = fixed
    print("[ArenaShopPage] setPurchased: " .. #SHOP_ITEMS .. " items tracked")
end

-- camelCase → snake_case 卷轴类型映射（服务端用 camelCase，RewardPopup 用 snake_case）
local SCROLL_TYPE_TO_REWARD = {
    weaponScroll    = "weapon_scroll",
    offhandScroll   = "offhand_scroll",
    armorScroll     = "armor_scroll",
    accessoryScroll = "accessory_scroll",
}

--- 处理购买成功响应
---@param data table { itemId, purchased, arenaCoin, rewardDetail }
function ArenaShopPage.onBuyResult(data)
    -- 服务器响应时弹窗可能已在关闭动画中，直接完成关闭
    shopState.dialogOpen = false
    shopState.dialogItemIdx = nil
    shopState.popupClosing = false

    if data.success == false then
        print("[ArenaShopPage] 购买失败: " .. tostring(data.reason))
        return
    end
    local itemId = tonumber(data.itemId)
    if itemId then
        shopState.purchased[itemId] = tonumber(data.purchased) or (getPurchased(itemId) + 1)
        print("[ArenaShopPage] 购买成功: itemId=" .. itemId
            .. " 已购=" .. tostring(shopState.purchased[itemId]))
    end
    -- 竞技币由 PlayerStore 代理，无需写入 GameState

    -- 随机卷轴购买成功时，展示奖励弹窗显示实际获得的卷轴类型
    local detail = data.rewardDetail
    if detail then
        if detail.scrolls then
            -- 新格式：每个独立随机，按类型聚合
            local rewards = {}
            for st, n in pairs(detail.scrolls) do
                local rewardKey = SCROLL_TYPE_TO_REWARD[st]
                if rewardKey and n > 0 then
                    rewards[#rewards + 1] = { type = rewardKey, amount = n }
                end
            end
            if #rewards > 0 then
                RewardPopup.show("购买成功", rewards)
            end
        elseif detail.scrollType then
            -- 兼容旧格式
            local rewardKey = SCROLL_TYPE_TO_REWARD[detail.scrollType]
            if rewardKey then
                RewardPopup.show("购买成功", {
                    { type = rewardKey, amount = detail.amount or 1 },
                })
            end
        end
    end
end

--- 弹窗动画 update
function ArenaShopPage.update(dt)
    if not shopState.dialogOpen then return end
    if shopState.popupClosing then
        local _, _, done = getPopupAnim()
        if done then
            shopState.popupClosing = false
            shopState.dialogOpen = false
            shopState.dialogItemIdx = nil
            return
        end
    end
end

--- 弹窗是否打开
function ArenaShopPage.isDialogOpen()
    return shopState.dialogOpen
end

--- 关闭弹窗（外部调用，如返回键）
function ArenaShopPage.closeDialog()
    if not shopState.dialogOpen then return end
    if shopState.popupClosing then return end
    shopState.popupClosing = true
    shopState.popupCloseTime = time.elapsedTime
end

return ArenaShopPage
