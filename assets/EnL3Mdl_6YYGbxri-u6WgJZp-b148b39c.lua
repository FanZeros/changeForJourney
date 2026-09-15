-- ============================================================================
-- TavernShopPage - 酒馆商店界面
-- 职责：酒馆商店商品列表绘制、购买交互
-- 被 TavernPage.lua 的商店 Tab 调用
-- 布局与 ArenaShopPage 完全一致，商品/货币替换为酒馆数据
-- ============================================================================

local GameState      = require("core.GameState")
local drawTextStroke = require("core.DrawUtil").drawTextStroke
local Protocol       = require("shared.Protocol")
local BF             = require("systems.ButtonFeedback")
local PlayerStore    = require("client.data.PlayerStore")
local ClientDispatcher = require("network.ClientDispatcher")
local TavernConfig     = require("config.TavernConfig")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格

local TavernShopPage = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = 1080

-- ======================== 商品配置 ========================
-- 数据来源：建筑-酒馆招募.txt「酒馆商店」章节
-- 英雄 ID 对应：1=大狗嚼 2=黄桃龙 3=叮咚鸡 4=接化发掌门 5=叠甲怪 6=阿姨压
--               7=信光机兵 8=愤怒的小雀 9=卡皮巴拉 10=铁憨憨 11=熬夜冠军 12=雪皇
--               13=弹弹弹 14=内鬼 15=复活吧爱人 16=万剑归宗 20=摘星星星人

local SHOP_ITEMS = {
    {
        id = 1, name = "冒险招募券", quality = 5,
        limitCycle = "daily", limitCount = -1, price = 40,
        icon = "image/UI_icon_ZMQ_1.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 102, name = "星辉招募券", quality = 6,
        limitCycle = "daily", limitCount = -1, price = 160,
        icon = "image/UI_icon_ZMQ_2.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    -- N 碎片（品质3）
    {
        id = 2, name = "大狗嚼-碎片", quality = 3,
        limitCycle = "daily", limitCount = -1, price = 15,
        icon = "image/角色图标/UI_icon_hero_1.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 3, name = "黄桃龙-碎片", quality = 3,
        limitCycle = "daily", limitCount = -1, price = 15,
        icon = "image/角色图标/UI_icon_hero_2.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 4, name = "叮咚鸡-碎片", quality = 3,
        limitCycle = "daily", limitCount = -1, price = 15,
        icon = "image/角色图标/UI_icon_hero_3.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    -- R 碎片（品质4）
    {
        id = 5, name = "接化发掌门-碎片", quality = 4,
        limitCycle = "daily", limitCount = -1, price = 60,
        icon = "image/角色图标/UI_icon_hero_4.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 6, name = "叠甲怪-碎片", quality = 4,
        limitCycle = "daily", limitCount = -1, price = 60,
        icon = "image/角色图标/UI_icon_hero_5.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 7, name = "阿姨压-碎片", quality = 4,
        limitCycle = "daily", limitCount = -1, price = 60,
        icon = "image/角色图标/UI_icon_hero_6.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 8, name = "信光机兵-碎片", quality = 4,
        limitCycle = "daily", limitCount = -1, price = 60,
        icon = "image/角色图标/UI_icon_hero_7.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 9, name = "愤怒的小雀-碎片", quality = 4,
        limitCycle = "daily", limitCount = -1, price = 60,
        icon = "image/角色图标/UI_icon_hero_8.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 10, name = "卡皮巴拉-碎片", quality = 4,
        limitCycle = "daily", limitCount = -1, price = 60,
        icon = "image/角色图标/UI_icon_hero_9.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    -- SR 碎片（品质5）
    {
        id = 11, name = "铁憨憨-碎片", quality = 5,
        limitCycle = "daily", limitCount = -1, price = 250,
        icon = "image/角色图标/UI_icon_hero_10.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 12, name = "熬夜冠军-碎片", quality = 5,
        limitCycle = "daily", limitCount = -1, price = 250,
        icon = "image/角色图标/UI_icon_hero_11.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 13, name = "雪皇-碎片", quality = 5,
        limitCycle = "daily", limitCount = -1, price = 250,
        icon = "image/角色图标/UI_icon_hero_12.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 14, name = "弹弹弹-碎片", quality = 5,
        limitCycle = "daily", limitCount = -1, price = 250,
        icon = "image/角色图标/UI_icon_hero_13.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 15, name = "内鬼-碎片", quality = 5,
        limitCycle = "daily", limitCount = -1, price = 250,
        icon = "image/角色图标/UI_icon_hero_14.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 16, name = "复活吧爱人-碎片", quality = 5,
        limitCycle = "daily", limitCount = -1, price = 250,
        icon = "image/角色图标/UI_icon_hero_15.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 17, name = "闪电卖鸡-碎片", quality = 5,
        limitCycle = "daily", limitCount = -1, price = 250,
        icon = "image/角色图标/UI_icon_hero_21.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 18, name = "小黑子-碎片", quality = 5,
        limitCycle = "daily", limitCount = -1, price = 250,
        icon = "image/角色图标/UI_icon_hero_22.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 19, name = "真布诗人-碎片", quality = 5,
        limitCycle = "daily", limitCount = -1, price = 250,
        icon = "image/角色图标/UI_icon_hero_23.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 101, name = "万剑归宗-碎片", quality = 6,
        limitCycle = "daily", limitCount = -1, price = 1125, rewardHeroId = 16,
        icon = "image/角色图标/UI_icon_hero_16.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
    {
        id = 103, name = "摘星星星人-碎片", quality = 6,
        limitCycle = "daily", limitCount = -1, price = 1125, rewardHeroId = 20,
        icon = "image/角色图标/UI_icon_hero_20.png",
        costIcon = "image/UI_icon_JGB_X.png",
    },
}

--- 招募券置顶：冒险招募券 → 星辉招募券 → 其余商品
local function isRecruitTicketShopItem(item)
    return item.id == 1 or item.id == 102
        or item.name == "冒险招募券" or item.name == "星辉招募券"
end

local function getShopDisplayItems()
    local tickets, others = {}, {}
    for _, item in ipairs(SHOP_ITEMS) do
        if isRecruitTicketShopItem(item) then
            tickets[#tickets + 1] = item
        else
            others[#others + 1] = item
        end
    end
    table.sort(tickets, function(a, b)
        if a.id == 1 then return true end
        if b.id == 1 then return false end
        return a.id < b.id
    end)
    local ordered = {}
    for _, item in ipairs(tickets) do ordered[#ordered + 1] = item end
    for _, item in ipairs(others) do ordered[#ordered + 1] = item end
    return ordered
end

local function getShopItemById(itemId)
    for _, item in ipairs(SHOP_ITEMS) do
        if item.id == itemId then return item end
    end
    return nil
end

-- ======================== 布局常量 ========================

local L = {
    -- 标题
    TITLE_CX = 540, TITLE_CY = 497, TITLE_FONT = 42,
    TITLE_R = 0x7b, TITLE_G = 0x53, TITLE_B = 0x39,
    -- 货币栏（酒馆币显示）
    COIN_BAR_CX = 540, COIN_BAR_CY = 565,
    COIN_ICON_W = 54, COIN_ICON_H = 54,
    COIN_FONT = 36,
    COIN_R = 0x45, COIN_G = 0x45, COIN_B = 0x45,
    COIN_VR = 0xff, COIN_VG = 0xef, COIN_VB = 0x67,
    -- 商品卡片
    CARD_W = 314, CARD_H = 402,
    CARD_COLS = 3,
    CARD_GAP_X = 30, CARD_GAP_Y = 15,
    GRID_TOP_CY = 827,
    -- 商品子元素（相对卡片中心）
    NAME_OY = -160, NAME_FONT = 38, NAME_SW = 5,
    ICON_OY = -44,  ICON_W = 160,   ICON_H = 160,
    COUNT_OX = 54,  COUNT_OY = 6,   COUNT_FONT = 42, COUNT_SW = 5,
    LIMIT_OY = 66,  LIMIT_FONT = 32,
    LIMIT_R = 0x4e, LIMIT_G = 0x4e, LIMIT_B = 0x4e,
    -- 购买按钮
    BTN_OY = 133, BTN_W = 286, BTN_H = 84,
    BTN_ICON_W = 82, BTN_ICON_H = 82,
    BTN_FONT = 40, BTN_SW = 5,
}

-- 计算网格：3列居中
local TOTAL_GRID_W = L.CARD_COLS * L.CARD_W + (L.CARD_COLS - 1) * L.CARD_GAP_X
local GRID_LEFT    = (DESIGN_W - TOTAL_GRID_W) * 0.5 + L.CARD_W * 0.5
local CARD_STEP_X  = L.CARD_W + L.CARD_GAP_X
local CARD_STEP_Y  = L.CARD_H + L.CARD_GAP_Y

-- ======================== 图片句柄 ========================

local shopImg = {
    pageBg      = -1,  -- UI_TJP_1.png（页面背景框）
    titleDeco   = -1,  -- UI_JJC_BTBJ.png（标题装饰）
    cardBg      = {},  -- 品质1~6 → UI_SDICONBJ_1~6.png
    buyBtn      = -1,  -- UI_SD_AN.png
    itemIcons   = {},  -- 每个商品图标
    costIcons   = {},  -- 每个商品消耗图标
    coinBarIcon = -1,  -- UI_icon_JGB_X.png（顶部货币栏）
    -- 二级弹窗
    dialogBg     = -1, -- UI_TY_EJQRK.png
    buyBtnYellow = -1, -- UI_AN_HUANG.png
    btnMinus     = -1, -- UI_AN_JIAN.png
    btnPlus      = -1, -- UI_AN_JIA.png
    coinIcon     = -1, -- UI_icon_JGB_X.png（弹窗消耗图标）
    qualityBg    = {}, -- 品质1~5 → UI_icon_ZBBJ_1~5.png
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
    purchased      = {},     -- { [itemId] = count }
    shopDayId      = 0,
    shopWeekId     = 0,
    scrollY        = 0,
    dragging       = false,
    lastDragY      = 0,
    -- 二级弹窗
    dialogOpen     = false,
    dialogItemId   = nil,
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
    -- 酒馆币气泡提示
    coinTipOpen    = false,
    coinTipTime    = 0,
    -- 等待服务端购买响应
    pendingBuy     = false,
    pendingBuyTime = 0,
}

local PENDING_BUY_TIMEOUT = 8

-- ======================== 滚动区域 ========================

local SCROLL_TOP = 610
local SCROLL_BOT = 2240

-- ======================== 二级弹窗布局 ========================

local DLG = {
    BG_CX = 540, BG_CY = 1211, BG_W = 950, BG_H = 847,
    BG_IT = 150, BG_IR = 60,   BG_IB = 100, BG_IL = 60,
    TITLE_CX = 540, TITLE_CY = 855, TITLE_FONT = 60, TITLE_SW = 6,
    TITLE_SR = 0x46, TITLE_SG = 0x2f, TITLE_SB = 0x20,
    SUB_CX = 540, SUB_CY = 967, SUB_FONT = 40,
    SUB_R = 0xb6, SUB_G = 0xb0, SUB_B = 0x9d,
    CONTENT_CX = 540, CONTENT_CY = 1121, CONTENT_W = 800, CONTENT_H = 218, CONTENT_R = 16,
    ITEM_CX = 540, ITEM_CY = 1122, ITEM_ICON_SIZE = 160,
    BADGE_FONT = 40, BADGE_SW = 5, BADGE_OX = 56, BADGE_OY = 50,
    QTY_CX = 540, QTY_CY = 1278, QTY_FONT = 40, QTY_SW = 5,
    MINUS_CX = 282, MINUS_CY = 1342, MINUS_W = 84, MINUS_H = 84,
    PLUS_CX  = 808, PLUS_CY  = 1342, PLUS_W  = 84, PLUS_H  = 84,
    SLIDER_CX = 540, SLIDER_CY = 1342, SLIDER_W = 400, SLIDER_H = 24, SLIDER_R = 12,
    KNOB_SIZE = 36,
    KNOB_STROKE_R = 0x44, KNOB_STROKE_G = 0x2d, KNOB_STROKE_B = 0x19, KNOB_STROKE_W = 6,
    COST_CX = 540, COST_CY = 1416, COST_ICON_SIZE = 70, COST_FONT = 40, COST_SW = 5,
    BUY_CX = 540, BUY_CY = 1503, BUY_W = 410, BUY_H = 100, BUY_FONT = 40,
}

-- ======================== Init ========================

function TavernShopPage.init(vg)
    shopImg.pageBg    = nvgCreateImage(vg, "image/UI_TJP_1.png",    0)
    shopImg.titleDeco = nvgCreateImage(vg, "image/UI_JJC_BTBJ.png", 0)
    for i = 1, 6 do
        shopImg.cardBg[i]   = nvgCreateImage(vg, "image/UI_SDICONBJ_" .. i .. ".png", 0)
    end
    for i = 1, 6 do
    -- [暗黑化 P2-A] 原 ZBBJ 贴图加载已移除（矢量品质框替代）
    end
    shopImg.buyBtn      = nvgCreateImage(vg, "image/UI_SD_AN.png",       0)
    -- [暗黑化 P1-B5] 原 image/UI_TY_EJQRK.png 贴图加载已移除（矢量绘制替代）
    -- [暗黑化 P1-B5] 原 image/UI_AN_HUANG.png 贴图加载已移除（矢量绘制替代）
    shopImg.buyBtnYellow= nvgCreateImage(vg, "image/UI_AN_HUANG.png",    0)
    shopImg.btnMinus    = nvgCreateImage(vg, "image/UI_AN_JIAN.png",     0)
    shopImg.btnPlus     = nvgCreateImage(vg, "image/UI_AN_JIA.png",      0)
    shopImg.coinIcon    = nvgCreateImage(vg, "image/UI_icon_JGB_X.png",  0)

    for _, item in ipairs(SHOP_ITEMS) do
        shopImg.itemIcons[item.id] = nvgCreateImage(vg, item.icon,     0)
        shopImg.costIcons[item.id] = nvgCreateImage(vg, item.costIcon, 0)
    end

    shopState.purchased  = {}
    shopState.scrollY    = 0
    shopState.dialogOpen = false
    shopState.dialogItemId = nil
    shopState.pendingBuy = false

    -- 同步服务端 tavern.shopPurchased（限购次数）
    TavernShopPage.syncPurchasedFromStore()
    if not shopState.tavernSubscribed then
        shopState.tavernSubscribed = true
        PlayerStore.Subscribe("tavern", function(data)
            if not data then return end
            if data.shopPurchased then
                TavernShopPage.setPurchased(data.shopPurchased)
            end
            shopState.shopDayId  = tonumber(data.shopDayId)  or 0
            shopState.shopWeekId = tonumber(data.shopWeekId) or 0
        end)
    end

    print("[TavernShopPage] init OK, items=" .. #SHOP_ITEMS)
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
    local dL = math.min(iLeft,   dw * 0.5)
    local dR = math.min(iRight,  dw * 0.5)
    local dT = math.min(iTop,    dh * 0.5)
    local dB = math.min(iBottom, dh * 0.5)
    local ix1 = math.floor(dx + dL + 0.5);      local iy1 = math.floor(dy + dT + 0.5)
    local ix2 = math.floor(dx + dw - dR + 0.5); local iy2 = math.floor(dy + dh - dB + 0.5)
    local ix3 = math.floor(dx + dw + 0.5);      local iy3 = math.floor(dy + dh + 0.5)
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
        return POPUP_SCALE_TO + (POPUP_SCALE_FROM - POPUP_SCALE_TO) * e, 1.0 - e, (t >= 1.0)
    else
        local t = math.min(1.0, (time.elapsedTime - shopState.popupAnimTime) / POPUP_OPEN_DUR)
        local e = easeOutCubic(t)
        return POPUP_SCALE_FROM + (POPUP_SCALE_TO - POPUP_SCALE_FROM) * e, e, false
    end
end

local function getPurchased(itemId)
    local item = TavernConfig.getShopItem(itemId)
    local p = shopState.purchased
    local count = p[itemId] or p[tostring(itemId)] or 0
    if item and item.limitCycle == "daily" then
        if (shopState.shopDayId or 0) ~= TavernConfig.calcDayId() then
            return 0
        end
    elseif item and item.limitCycle == "weekly" then
        if (shopState.shopWeekId or 0) ~= TavernConfig.calcWeekId() then
            return 0
        end
    end
    return count
end

local function isSoldOut(item)
    if item.limitCount < 0 then return false end  -- 不限购
    return getPurchased(item.id) >= item.limitCount
end

local SHARD_ITEM_HERO_ID = {
    [2] = 1, [3] = 2, [4] = 3,
    [5] = 4, [6] = 5, [7] = 6, [8] = 7, [9] = 8, [10] = 9,
    [11] = 10, [12] = 11, [13] = 12, [14] = 13, [15] = 14, [16] = 15,
    [17] = 21, [18] = 22, [19] = 23,
    [101] = 16, [103] = 20,
}

local function getShardHeroId(item)
    return item.rewardHeroId or SHARD_ITEM_HERO_ID[item.id]
end

local function isOwnedHero(heroId)
    if not heroId then return false end
    local heroesData = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes")
    local roster = heroesData and heroesData.roster
    if not roster then return false end
    local heroData = roster[heroId] or roster[tostring(heroId)]
    return heroData ~= nil and heroData.level ~= nil
end

local function isLockedByOwnership(item)
    local heroId = getShardHeroId(item)
    return heroId ~= nil and not isOwnedHero(heroId)
end

local function showFloatText(text, x, y)
    shopState.floatText     = text
    shopState.floatTextX    = x
    shopState.floatTextY    = y
    shopState.floatTextTime = time.elapsedTime
end

--- 浮动提示（列表页/弹窗通用，绘制于最顶层）
local function drawFloatTextOverlay(vg)
    if not shopState.floatText then return end
    local FLOAT_DUR  = 1.5
    local FLOAT_DIST = 100
    local elapsed    = time.elapsedTime - shopState.floatTextTime
    if elapsed >= FLOAT_DUR then
        shopState.floatText = nil
        return
    end
    local t = elapsed / FLOAT_DUR
    drawTextStroke(vg,
        shopState.floatTextX, shopState.floatTextY - FLOAT_DIST * t,
        shopState.floatText,
        40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 80, 80, 6, { alpha = 1.0 - t })
end

--- 列表购买按钮命中（避免拖拽滚动吞掉点击）
local function hitAnyListBuyButton(dx, dy)
    if shopState.dialogOpen then return false end
    local displayItems = getShopDisplayItems()
    for idx, item in ipairs(displayItems) do
        local col   = (idx - 1) % L.CARD_COLS
        local row   = math.floor((idx - 1) / L.CARD_COLS)
        local cx    = GRID_LEFT + col * CARD_STEP_X
        local cy    = L.GRID_TOP_CY + row * CARD_STEP_Y - shopState.scrollY
        local btnCY = cy + L.BTN_OY
        if hitTest(dx, dy, cx, btnCY, L.BTN_W, L.BTN_H) then
            return true
        end
    end
    return false
end

-- 前向声明
local drawPurchaseDialog

-- ======================== 绘制单个商品卡片 ========================

local function drawShopCard(vg, idx, item, cx, cy)
    -- [暗黑化 P1-B5] 矢量卡底 + 品质语义描边
    local q = item.quality or 1
    DarkIcon.drawNine(vg, "plain",
        cx - L.CARD_W * 0.5, cy - L.CARD_H * 0.5,
        L.CARD_W, L.CARD_H,
        { accent = DarkIcon.QUALITY_TRIM[math.min(6, math.max(1, q))] })

    local bought   = getPurchased(item.id)
    local soldOut  = item.limitCount >= 0 and bought >= item.limitCount
    local locked   = isLockedByOwnership(item)

    -- 商品名
    drawTextStroke(vg, cx, cy + L.NAME_OY, item.name,
        L.NAME_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, L.NAME_SW, { strokeColor = { 0, 0, 0 } })

    -- 商品图标
    local iconImg = shopImg.itemIcons[item.id]
    if iconImg and iconImg >= 0 then
        drawImageCentered(vg, iconImg, cx, cy + L.ICON_OY, L.ICON_W, L.ICON_H, (soldOut or locked) and 0.4 or 1.0)
    end

    -- 数量角标（每次购买1个，不显示"×1"）
    -- 仅冒险招募券 id=1 不需要角标，其余碎片默认1个
    -- 不显示角标（均为1个/次）

    -- 限购文本（仅限购商品显示；不限购不显示）
    if item.limitCount >= 0 then
        local remaining = math.max(0, item.limitCount - bought)
        local limitText
        if item.limitCycle == "daily" then
            limitText = "限购" .. remaining .. "次/日"
        else
            limitText = "限购" .. remaining .. "次/周"
        end
        nvgFontFace(vg, "sans"); nvgFontSize(vg, L.LIMIT_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(L.LIMIT_R, L.LIMIT_G, L.LIMIT_B, 255))
        nvgText(vg, cx, cy + L.LIMIT_OY, limitText, nil)
    end

    -- 购买按钮
    ---@diagnostic disable-next-line: assign-type-mismatch
    local btnCY = cy + L.BTN_OY
    if soldOut then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - L.BTN_W * 0.5, btnCY - L.BTN_H * 0.5, L.BTN_W, L.BTN_H, 12)
        nvgFillColor(vg, nvgRGBA(80, 80, 80, 200))
        nvgFill(vg)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, L.BTN_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
        nvgText(vg, cx, btnCY, "已售罄", nil)
    elseif locked then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - L.BTN_W * 0.5, btnCY - L.BTN_H * 0.5, L.BTN_W, L.BTN_H, 12)
        nvgFillColor(vg, nvgRGBA(80, 80, 80, 200))
        nvgFill(vg)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 34)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
        nvgText(vg, cx, btnCY, "拥有后可买", nil)
    else
        local _bf = BF.begin(vg, "tsp_item_" .. idx, cx, btnCY, L.BTN_W, L.BTN_H)
        DarkIcon.drawNine(vg, "btn", cx - L.BTN_W * 0.5, btnCY - L.BTN_H * 0.5, L.BTN_W, L.BTN_H, { accent = "gold" })

        -- 消耗图标 + 价格居中
        local priceStr = tostring(item.price)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, L.BTN_FONT)
        local textW  = nvgTextBounds(vg, 0, 0, priceStr)
        local totalW = L.BTN_ICON_W + 4 + textW
        local startX = cx - totalW * 0.5
        local costImg = shopImg.costIcons[item.id]
        if costImg and costImg >= 0 then
            drawImageCentered(vg, costImg, startX + L.BTN_ICON_W * 0.5, btnCY, L.BTN_ICON_W, L.BTN_ICON_H, 1.0)
        end
        drawTextStroke(vg, startX + L.BTN_ICON_W + 4, btnCY, priceStr,
            L.BTN_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            255, 255, 255, L.BTN_SW, { strokeColor = { 0, 0, 0 } })
        BF.finish(vg, _bf)
    end
end

-- ======================== 酒馆币来源气泡 ========================

local COIN_TIP_TEXT = "抽到已满觉醒的角色时将会自动转化为酒馆币"
local COIN_TIP_DUR  = 3.0  -- 自动消失时长（秒）

---@param vg any
---@param bgCX number 资源栏中心X
---@param bgCY number 资源栏中心Y
---@param bgW number 资源栏宽度
---@param bgH number 资源栏高度
local function drawCoinTip(vg, bgCX, bgCY, bgW, bgH)
    if not shopState.coinTipOpen then return end

    -- 超时自动关闭
    local elapsed = time.elapsedTime - shopState.coinTipTime
    if elapsed > COIN_TIP_DUR then
        shopState.coinTipOpen = false
        return
    end

    -- 淡入淡出
    local alpha = 1.0
    if elapsed < 0.15 then
        alpha = elapsed / 0.15
    elseif elapsed > COIN_TIP_DUR - 0.3 then
        alpha = (COIN_TIP_DUR - elapsed) / 0.3
    end
    alpha = math.max(0, math.min(1, alpha))

    -- 气泡尺寸与位置（在资源栏上方）
    local TIP_W = 560
    local TIP_H = 60
    local TIP_R = 14
    local TIP_CX = bgCX
    local TIP_CY = bgCY - bgH * 0.5 - 12 - TIP_H * 0.5  -- 资源栏上方12px
    local ARROW_SIZE = 8

    nvgSave(vg)
    nvgGlobalAlpha(vg, alpha)

    -- 小三角箭头（向下指向资源栏）
    local arrowCX = TIP_CX
    local arrowBot = TIP_CY + TIP_H * 0.5 + ARROW_SIZE
    nvgBeginPath(vg)
    nvgMoveTo(vg, arrowCX, arrowBot)
    nvgLineTo(vg, arrowCX - ARROW_SIZE, arrowBot - ARROW_SIZE)
    nvgLineTo(vg, arrowCX + ARROW_SIZE, arrowBot - ARROW_SIZE)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(0x2a, 0x1f, 0x14, 230))
    nvgFill(vg)

    -- 圆角气泡背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, TIP_CX - TIP_W * 0.5, TIP_CY - TIP_H * 0.5, TIP_W, TIP_H, TIP_R)
    nvgFillColor(vg, nvgRGBA(0x2a, 0x1f, 0x14, 230))
    nvgFill(vg)

    -- 气泡文字
    nvgFontFace(vg, "sans"); nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xff, 0xef, 0xd0, 255))
    nvgText(vg, TIP_CX, TIP_CY, COIN_TIP_TEXT, nil)

    nvgRestore(vg)
end

-- ======================== 主绘制 ========================

function TavernShopPage.drawContent(vg)
    -- 背景框（九宫格：上200 左10 右10 下200）
    -- 原始标注：中心 X540 Y1371，尺寸 1080×2058
    DarkIcon.drawNine(vg, "plain", 540 - 1080 * 0.5, 1371 - 2058 * 0.5, 1080, 2058)

    -- 标题装饰（UI_JJC_BTBJ.png，与竞技场相同位置 X540 Y497 W660 H60）
    drawImageCentered(vg, shopImg.titleDeco, L.TITLE_CX, L.TITLE_CY, 660, 60, 1.0)

    -- 标题文字（叠在装饰上方）
    nvgFontFace(vg, "sans"); nvgFontSize(vg, L.TITLE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(L.TITLE_R, L.TITLE_G, L.TITLE_B, 255))
    nvgText(vg, L.TITLE_CX, L.TITLE_CY, "酒馆商店", nil)

    -- 酒馆币资源栏（竞技场风格：圆角黑底 + 图标 + 描边文字）
    -- 布局参考 ArenaPage R1 组（bg中心534→540 偏移+6）
    local RES_BG_W = 220
    local RES_BG_H = 47
    local RES_BG_R = 18
    local RES_BG_A = 204
    local RES_BG_CX = 540
    local RES_BG_CY = L.COIN_BAR_CY
    local RES_ICON_CX = RES_BG_CX - 80   -- 图标在 bg 左侧，部分外露
    local RES_ICON_CY = RES_BG_CY
    local RES_ICON_W  = 82
    local RES_ICON_H  = 82

    -- 圆角黑底
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        RES_BG_CX - RES_BG_W * 0.5, RES_BG_CY - RES_BG_H * 0.5,
        RES_BG_W, RES_BG_H, RES_BG_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, RES_BG_A))
    nvgFill(vg)

    -- 货币图标
    drawImageCentered(vg, shopImg.coinBarIcon,
        RES_ICON_CX, RES_ICON_CY, RES_ICON_W, RES_ICON_H, 1.0)

    -- 数值（白字深色描边）
    local coinStr = tostring(GameState.getTavernCoin())
    drawTextStroke(vg, RES_BG_CX + 20, RES_BG_CY, coinStr,
        33, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4, { strokeColor = { 0x23, 0x23, 0x23 } })

    -- 酒馆币来源气泡提示（点击资源栏弹出）
    drawCoinTip(vg, RES_BG_CX, RES_BG_CY, RES_BG_W, RES_BG_H)

    -- 商品网格（可滚动）
    local displayItems = getShopDisplayItems()
    local rowCount  = math.ceil(#displayItems / L.CARD_COLS)
    local totalH    = rowCount * CARD_STEP_Y - L.CARD_GAP_Y
    local clipH     = SCROLL_BOT - SCROLL_TOP
    local maxScroll = math.max(0, totalH - clipH)
    shopState.scrollY = math.max(0, math.min(shopState.scrollY, maxScroll))

    nvgSave(vg)
    nvgIntersectScissor(vg, 20, SCROLL_TOP, DESIGN_W - 40, clipH)
    nvgTranslate(vg, 0, -shopState.scrollY)

    for idx, item in ipairs(displayItems) do
        local col = (idx - 1) % L.CARD_COLS
        local row = math.floor((idx - 1) / L.CARD_COLS)
        local cx  = GRID_LEFT + col * CARD_STEP_X
        local cy  = L.GRID_TOP_CY + row * CARD_STEP_Y
        local screenCY = cy - shopState.scrollY
        if screenCY >= SCROLL_TOP - L.CARD_H and screenCY <= SCROLL_BOT + L.CARD_H then
            drawShopCard(vg, idx, item, cx, cy)
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 二级弹窗（最顶层）
    drawPurchaseDialog(vg)

    -- 浮动提示（列表/弹窗通用，必须在弹窗之后绘制）
    drawFloatTextOverlay(vg)
end

-- ======================== 二级购买确认弹窗 ========================

drawPurchaseDialog = function(vg)
    if not shopState.dialogOpen or not shopState.dialogItemId then return end
    local item = getShopItemById(shopState.dialogItemId)
    if not item then return end

    local pScale, pAlpha, _ = getPopupAnim()

    -- 遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * pAlpha)))
    nvgFill(vg)

    nvgSave(vg)
    nvgTranslate(vg, DLG.BG_CX, DLG.BG_CY)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -DLG.BG_CX, -DLG.BG_CY)
    nvgGlobalAlpha(vg, pAlpha)

    -- 背景
    DarkIcon.drawNine(vg, "panel", DLG.BG_CX - DLG.BG_W * 0.5, DLG.BG_CY - DLG.BG_H * 0.5, DLG.BG_W, DLG.BG_H, { titleH = DLG.BG_IT })

    -- 标题
    drawTextStroke(vg, DLG.TITLE_CX, DLG.TITLE_CY, "购买道具",
        DLG.TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DLG.TITLE_SW,
        { strokeColor = { DLG.TITLE_SR, DLG.TITLE_SG, DLG.TITLE_SB } })

    -- 副标题
    nvgFontFace(vg, "sans"); nvgFontSize(vg, DLG.SUB_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(DLG.SUB_R, DLG.SUB_G, DLG.SUB_B, 255))
    nvgText(vg, DLG.SUB_CX, DLG.SUB_CY, "是否购买此道具", nil)

    -- 商品背景框
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        DLG.CONTENT_CX - DLG.CONTENT_W * 0.5,
        DLG.CONTENT_CY - DLG.CONTENT_H * 0.5,
        DLG.CONTENT_W, DLG.CONTENT_H, DLG.CONTENT_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))
    nvgFill(vg)

    -- 品质背景 + 商品图标
    local rewardImg = shopImg.itemIcons[item.id]
    DarkIcon.drawQualityBg(vg, item.quality or 1, DLG.ITEM_CX, DLG.ITEM_CY, DLG.ITEM_ICON_SIZE, DLG.ITEM_ICON_SIZE, 1.0)  -- [暗黑化 P2-A]
    if rewardImg and rewardImg >= 0 then
        drawImageCentered(vg, rewardImg, DLG.ITEM_CX, DLG.ITEM_CY, DLG.ITEM_ICON_SIZE, DLG.ITEM_ICON_SIZE, 1.0)
    end

    -- 角标
    drawTextStroke(vg,
        DLG.ITEM_CX + DLG.BADGE_OX, DLG.ITEM_CY + DLG.BADGE_OY,
        "×1",
        DLG.BADGE_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        255, 255, 255, DLG.BADGE_SW, { strokeColor = { 0, 0, 0 } })

    -- 购买数量文本
    drawTextStroke(vg, DLG.QTY_CX, DLG.QTY_CY,
        "购买数量:" .. shopState.buyQuantity,
        DLG.QTY_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DLG.QTY_SW, { strokeColor = { 0, 0, 0 } })

    -- 减按钮
    local _sm = BF.begin(vg, "tsp_dlg_minus", DLG.MINUS_CX, DLG.MINUS_CY, DLG.MINUS_W, DLG.MINUS_H)
    drawImageCentered(vg, shopImg.btnMinus,
        DLG.MINUS_CX, DLG.MINUS_CY, DLG.MINUS_W, DLG.MINUS_H,
        shopState.buyQuantity <= 1 and 0.4 or 1.0)
    BF.finish(vg, _sm)

    -- 加按钮
    local _sp = BF.begin(vg, "tsp_dlg_plus", DLG.PLUS_CX, DLG.PLUS_CY, DLG.PLUS_W, DLG.PLUS_H)
    drawImageCentered(vg, shopImg.btnPlus,
        DLG.PLUS_CX, DLG.PLUS_CY, DLG.PLUS_W, DLG.PLUS_H,
        shopState.buyQuantity >= shopState.buyMaxQuantity and 0.4 or 1.0)
    BF.finish(vg, _sp)

    -- 滑条背景
    local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sliderL, DLG.SLIDER_CY - DLG.SLIDER_H * 0.5,
        DLG.SLIDER_W, DLG.SLIDER_H, DLG.SLIDER_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 51))
    nvgFill(vg)

    -- 已填充
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

    -- 滑块
    local knobX = sliderL + DLG.SLIDER_W * sliderFrac
    nvgBeginPath(vg); nvgCircle(vg, knobX, DLG.SLIDER_CY, DLG.KNOB_SIZE * 0.5)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(DLG.KNOB_STROKE_R, DLG.KNOB_STROKE_G, DLG.KNOB_STROKE_B, 255))
    nvgStrokeWidth(vg, DLG.KNOB_STROKE_W); nvgStroke(vg)

    -- 消耗资源
    local totalCost = item.price * shopState.buyQuantity
    local costStr   = "×" .. tostring(totalCost)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, DLG.COST_FONT)
    local costTextW  = nvgTextBounds(vg, 0, 0, costStr)
    local costTotalW = DLG.COST_ICON_SIZE + 4 + costTextW
    local costStartX = DLG.COST_CX - costTotalW * 0.5
    drawImageCentered(vg, shopImg.coinIcon,
        costStartX + DLG.COST_ICON_SIZE * 0.5, DLG.COST_CY, DLG.COST_ICON_SIZE, DLG.COST_ICON_SIZE, 1.0)
    drawTextStroke(vg, costStartX + DLG.COST_ICON_SIZE + 4, DLG.COST_CY, costStr,
        DLG.COST_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, DLG.COST_SW, { strokeColor = { 0, 0, 0 } })

    -- 购买按钮
    local _bfBuy = BF.begin(vg, "tsp_confirm", DLG.BUY_CX, DLG.BUY_CY, DLG.BUY_W, DLG.BUY_H)
    DarkIcon.drawNine(vg, "btn", DLG.BUY_CX - DLG.BUY_W * 0.5, DLG.BUY_CY - DLG.BUY_H * 0.5, DLG.BUY_W, DLG.BUY_H, { accent = "gold" })
    nvgFontFace(vg, "sans"); nvgFontSize(vg, DLG.BUY_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, shopState.pendingBuy and 100 or 179))
    nvgText(vg, DLG.BUY_CX, DLG.BUY_CY, shopState.pendingBuy and "购买中..." or "购买", nil)
    BF.finish(vg, _bfBuy)

    nvgRestore(vg)
end

-- ======================== 输入处理 ========================

function TavernShopPage.handleInput(dx, dy)
    if shopState.dialogOpen then
        if shopState.popupClosing then return true end
        if shopState.pendingBuy then return true end

        -- 减
        if hitTest(dx, dy, DLG.MINUS_CX, DLG.MINUS_CY, DLG.MINUS_W, DLG.MINUS_H) then
            BF.trigger("tsp_dlg_minus")
            if shopState.buyQuantity > 1 then shopState.buyQuantity = shopState.buyQuantity - 1 end
            return true
        end
        -- 加
        if hitTest(dx, dy, DLG.PLUS_CX, DLG.PLUS_CY, DLG.PLUS_W, DLG.PLUS_H) then
            BF.trigger("tsp_dlg_plus")
            if shopState.buyQuantity < shopState.buyMaxQuantity then
                shopState.buyQuantity = shopState.buyQuantity + 1
            end
            return true
        end
        -- 滑条
        local sliderHitH = math.max(DLG.SLIDER_H, DLG.KNOB_SIZE) + 20
        if hitTest(dx, dy, DLG.SLIDER_CX, DLG.SLIDER_CY, DLG.SLIDER_W + DLG.KNOB_SIZE, sliderHitH) then
            local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
            local frac = math.max(0, math.min(1, (dx - sliderL) / DLG.SLIDER_W))
            local qty  = math.floor(frac * (shopState.buyMaxQuantity - 1) + 0.5) + 1
            shopState.buyQuantity = math.max(1, math.min(shopState.buyMaxQuantity, qty))
            shopState.sliderDragging = true
            return true
        end
        -- 购买确认
        if hitTest(dx, dy, DLG.BUY_CX, DLG.BUY_CY, DLG.BUY_W, DLG.BUY_H) then
            if shopState.pendingBuy then return true end
            BF.trigger("tsp_confirm")
            local item = getShopItemById(shopState.dialogItemId)
            if item then
                local totalCost = item.price * shopState.buyQuantity
                local coins     = GameState.getTavernCoin()
                if coins < totalCost then
                    showFloatText("酒馆币不足", DLG.BUY_CX, DLG.BUY_CY)
                elseif isLockedByOwnership(item) then
                    showFloatText("拥有该角色后可购买碎片", DLG.BUY_CX, DLG.BUY_CY)
                else
                    local sent = require("network.Client").sendAction(
                        Protocol.ACTION_TYPES.TAVERN_SHOP_BUY, {
                            itemId   = item.id,
                            quantity = shopState.buyQuantity,
                        })
                    if sent then
                        shopState.pendingBuy     = true
                        shopState.pendingBuyTime = time.elapsedTime
                    else
                        showFloatText("网络未连接", DLG.BUY_CX, DLG.BUY_CY)
                    end
                end
            end
            return true
        end
        -- 同帧保护
        if time.elapsedTime - shopState.popupAnimTime < 0.05 then return true end
        -- 点击弹窗外关闭
        if not hitTest(dx, dy, DLG.BG_CX, DLG.BG_CY, DLG.BG_W, DLG.BG_H) then
            shopState.popupClosing  = true
            shopState.popupCloseTime = time.elapsedTime
        end
        return true
    end

    -- 点击酒馆币资源栏：弹出/关闭来源说明气泡
    if hitTest(dx, dy, L.COIN_BAR_CX, L.COIN_BAR_CY, 220, 47) then
        shopState.coinTipOpen = true
        shopState.coinTipTime = time.elapsedTime
        return true
    end

    -- 商品购买按钮点击
    local displayItems = getShopDisplayItems()
    for idx, item in ipairs(displayItems) do
        local col   = (idx - 1) % L.CARD_COLS
        local row   = math.floor((idx - 1) / L.CARD_COLS)
        local cx    = GRID_LEFT + col * CARD_STEP_X
        local cy    = L.GRID_TOP_CY + row * CARD_STEP_Y - shopState.scrollY
        local btnCY = cy + L.BTN_OY
        if hitTest(dx, dy, cx, btnCY, L.BTN_W, L.BTN_H) then
            if isSoldOut(item) then
                showFloatText("已售罄", cx, btnCY)
                return true
            end
            if isLockedByOwnership(item) then
                showFloatText("拥有该角色后可购买碎片", cx, btnCY)
                return true
            end
            BF.trigger("tsp_item_" .. idx)
            shopState.dialogOpen    = true
            shopState.dialogItemId  = item.id
            shopState.popupAnimTime = time.elapsedTime
            shopState.popupClosing  = false
            shopState.sliderDragging = false
            shopState.buyQuantity   = 1
            shopState.buyMaxQuantity = math.max(1, item.limitCount - getPurchased(item.id))
            return true
        end
    end
    return false
end

-- ======================== 滚动/拖拽 ========================

function TavernShopPage.handleDragBegin(dx, dy)
    if shopState.dialogOpen then
        if shopState.popupClosing then return end
        if shopState.pendingBuy then return end
        local sliderHitH = math.max(DLG.SLIDER_H, DLG.KNOB_SIZE) + 20
        if hitTest(dx, dy, DLG.SLIDER_CX, DLG.SLIDER_CY, DLG.SLIDER_W + DLG.KNOB_SIZE, sliderHitH) then
            shopState.sliderDragging = true
            local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
            local frac = math.max(0, math.min(1, (dx - sliderL) / DLG.SLIDER_W))
            local qty  = math.floor(frac * (shopState.buyMaxQuantity - 1) + 0.5) + 1
            shopState.buyQuantity = math.max(1, math.min(shopState.buyMaxQuantity, qty))
        end
        return
    end
    -- 购买按钮区域不启动滚动拖拽，避免移动端轻滑导致点击失效
    if hitAnyListBuyButton(dx, dy) then return end
    if dy >= SCROLL_TOP and dy <= SCROLL_BOT then
        shopState.dragging  = true
        shopState.lastDragY = dy
    end
end

function TavernShopPage.handleDragMove(dx, dy)
    if shopState.dialogOpen then
        if shopState.sliderDragging and not shopState.popupClosing then
            local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
            local frac = math.max(0, math.min(1, (dx - sliderL) / DLG.SLIDER_W))
            local qty  = math.floor(frac * (shopState.buyMaxQuantity - 1) + 0.5) + 1
            shopState.buyQuantity = math.max(1, math.min(shopState.buyMaxQuantity, qty))
        end
        return
    end
    if shopState.dragging then
        shopState.scrollY   = shopState.scrollY + (shopState.lastDragY - dy)
        shopState.lastDragY = dy
    end
end

function TavernShopPage.handleDragEnd()
    shopState.sliderDragging = false
    shopState.dragging       = false
end

function TavernShopPage.isDragging()
    return shopState.dragging or shopState.sliderDragging
end

function TavernShopPage.handleScroll(wheel)
    if shopState.dialogOpen or shopState.popupClosing then return end
    shopState.scrollY = shopState.scrollY - wheel * 60
end

function TavernShopPage.resetScroll()
    shopState.scrollY        = 0
    shopState.dragging       = false
end

-- ======================== 服务器响应 ========================

---@param purchased table { [itemId] = count }
function TavernShopPage.setPurchased(purchased)
    local fixed = {}
    for k, v in pairs(purchased or {}) do
        local numK = tonumber(k)
        if numK then
            fixed[numK] = tonumber(v) or 0
        end
    end
    shopState.purchased = fixed
end

--- 从 PlayerStore / ClientDispatcher 读取 tavern.shopPurchased
function TavernShopPage.syncPurchasedFromStore()
    local tavern = ClientDispatcher.get("tavern") or PlayerStore.Get("tavern")
    if not tavern then return end
    if tavern.shopPurchased then
        TavernShopPage.setPurchased(tavern.shopPurchased)
    end
    shopState.shopDayId  = tonumber(tavern.shopDayId)  or 0
    shopState.shopWeekId = tonumber(tavern.shopWeekId) or 0
end

function TavernShopPage.isPendingBuy()
    return shopState.pendingBuy
end

---@param data table { itemId, purchased, tavernCoin, success, reason }
function TavernShopPage.onBuyResult(data)
    shopState.pendingBuy     = false
    shopState.pendingBuyTime = 0
    shopState.popupClosing   = false

    if data.success == false then
        print("[TavernShopPage] 购买失败: " .. tostring(data.reason))
        shopState.dialogOpen    = true
        shopState.popupAnimTime = time.elapsedTime
        showFloatText(data.reason or "购买失败", DLG.BUY_CX, DLG.BUY_CY)
        return
    end

    shopState.dialogOpen     = false
    shopState.dialogItemId   = nil

    if data.shopPurchased then
        TavernShopPage.setPurchased(data.shopPurchased)
    else
        local itemId = tonumber(data.itemId)
        if itemId then
            shopState.purchased[itemId] = tonumber(data.purchased)
                or (getPurchased(itemId) + (shopState.buyQuantity or 1))
        end
    end
    shopState.shopDayId  = TavernConfig.calcDayId()
    shopState.shopWeekId = TavernConfig.calcWeekId()

    local itemId = tonumber(data.itemId)
    if itemId then
        print("[TavernShopPage] 购买成功: itemId=" .. itemId
            .. " 已购=" .. tostring(getPurchased(itemId)))
        local item = getShopItemById(itemId)
        if item then
            local qty = tonumber(data.quantity) or shopState.buyQuantity or 1
            local RewardPopup = require("ui.RewardPopup")
            if isRecruitTicketShopItem(item) then
                local rewardType = (itemId == 102) and "stellar_ticket" or "adventure_ticket"
                RewardPopup.show("购买成功", {
                    { type = rewardType, amount = qty },
                })
            elseif item.rewardType == "shard" and item.rewardHeroId then
                local shardQty = (item.rewardCount or 1) * qty
                RewardPopup.show("购买成功", {
                    { type = "shard", heroId = item.rewardHeroId, amount = shardQty },
                })
            end
        end
    end
end

-- ======================== update ========================

function TavernShopPage.update(dt)
    if shopState.pendingBuy and shopState.pendingBuyTime > 0 then
        if time.elapsedTime - shopState.pendingBuyTime >= PENDING_BUY_TIMEOUT then
            shopState.pendingBuy     = false
            shopState.pendingBuyTime = 0
            showFloatText("购买超时，请重试", DLG.BUY_CX, DLG.BUY_CY)
            print("[TavernShopPage] pendingBuy timeout")
        end
    end
    if not shopState.dialogOpen then return end
    if shopState.popupClosing then
        local _, _, done = getPopupAnim()
        if done then
            shopState.popupClosing = false
            if not shopState.pendingBuy then
                shopState.dialogOpen   = false
                shopState.dialogItemId = nil
            end
        end
    end
end

function TavernShopPage.isDialogOpen()
    return shopState.dialogOpen
end

function TavernShopPage.closeDialog()
    if not shopState.dialogOpen or shopState.popupClosing then return end
    shopState.popupClosing  = true
    shopState.popupCloseTime = time.elapsedTime
end

return TavernShopPage
