-- ============================================================================
-- MarketPage - 城镇市场界面（道具商店）
-- 从城镇页面点击市场进入的二级界面
-- 职责：市场UI 背景、资源展示、道具商品列表、购买交互
-- 包含两个 Tab：道具 / 典藏
-- ============================================================================

local GameConfig = require("config.GameConfig")
local DarkIcon       = require("core.DarkIcon")  -- [暗黑化 P0] 矢量图标库
local GameState  = require("core.GameState")
local Protocol   = require("shared.Protocol")
local drawTextStroke = require("core.DrawUtil").drawTextStroke
local DrawUtil        = require("core.DrawUtil")  -- [三队并行] 返回键 chevron
local TownPageChrome  = require("ui.TownPageChrome")
local BF = require("systems.ButtonFeedback")
local RewardPopup = require("ui.RewardPopup")

local NumberUtil   = require("core.NumberUtil")
local ArtifactDefs = require("shared.artifact.ArtifactDefs")
local PlayerStore  = require("client.data.PlayerStore")
local StageConfig  = require("config.StageConfig")
local MarketShopCard = require("ui.MarketShopCard")
local MarketDraw = require("ui.MarketDraw")
local MarketInput = require("ui.MarketInput")
local MarketCollection = require("ui.MarketCollection")
local MarketResults = require("ui.MarketResults")
local MarketInit = require("ui.MarketInit")

local MarketPage = {}

--- sendAction 注入（由 Client.lua 调用 setSendAction 设置）
local sendAction_ = nil

function MarketPage.setSendAction(fn)
    sendAction_ = fn
end

-- ======================== 设计分辨率========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量 ========================

-- 上半部分
local P1 = {
    -- 1. 市场背景图(UI_SCBJ)
    BG_CX = 540, BG_W = 1080, BG_H = 783,
    -- 2. 名称背景
    NAME_BG_CX = 147, NAME_BG_CY = 136, NAME_BG_W = 294, NAME_BG_H = 123,
    NAME_TEXT_CX = 173, NAME_TEXT_CY = 130, NAME_FONT = 50,
    -- 资源栏公用
    RES_BG_W = 170, RES_BG_H = 47, RES_BG_R = 18, RES_BG_A = 204,
    RES_FONT = 33, RES_SW = 4, RES_SR = 0x23, RES_SG = 0x23, RES_SB = 0x23,
    -- 资源1（金币）
    R1_BG_CX = 738, R1_BG_CY = 303,
    R1_ICON_CX = 674, R1_ICON_CY = 303, R1_ICON_W = 82, R1_ICON_H = 82,
    R1_TX = 757, R1_TY = 304,
    -- 资源2（钻石）
    R2_BG_CX = 971, R2_BG_CY = 303,
    R2_ICON_CX = 898, R2_ICON_CY = 304, R2_ICON_W = 70, R2_ICON_H = 70,
    R2_TX = 988, R2_TY = 304,
    -- 下方面板
    LOWER_CX = 540, LOWER_CY = 1371, LOWER_W = 1080, LOWER_H = 2058,
    LOWER_IT = 200, LOWER_IR = 10, LOWER_IB = 200, LOWER_IL = 10,
    -- 标题装饰
    DECO_CX = 540, DECO_CY = 497, DECO_W = 660, DECO_H = 60,
    -- 标题文字
    TITLE_CX = 540, TITLE_CY = 497, TITLE_FONT = 42,
    TITLE_R = 0x7b, TITLE_G = 0x53, TITLE_B = 0x39,
}
P1.BG_CY = P1.BG_H * 0.5

-- Tab 系统
local TAB = {
    BACK_CX = 958, BACK_CY = 1150, BACK_W = 184, BACK_H = 143,
    BG_CX = 540, BG_CY = 2308, BG_W = 810, BG_H = 143,
    SLIDER_W = 277, SLIDER_H = 143,
    SI_T = 10, SI_R = 70, SI_B = 10, SI_L = 70,
    TEXT_Y = 2302, FONT = 40,
    ACT_R = 0x81, ACT_G = 0x57, ACT_B = 0x3c,
    INA_R = 255, INA_G = 255, INA_B = 255,
    ANIM_DUR = 0.35,
    ITEMS = {
        { name = "道具",   cx = 505, cy = 2308 },
        { name = "典藏",   cx = 772, cy = 2308 },
    },
    MAP   = { items = 1, collection = 2 },
    KEYS  = { "items", "collection" },
}

-- ======================== 商品配置 ========================

local SHOP_ITEMS = {
    -- ===== 钻石商品（永久，不限购；定价已 /2） =====
    {
        id = 12, name = "冒险招募券", quality = 5, rewardCount = 1,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 90,
        icon = "image/货币道具/UI_icon_ZMQ_1.png",
        costIcon = "image/货币道具/UI_icon_SJ_X.png",
    },
    {
        id = 13, name = "洗练石", quality = 3, rewardCount = 2,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 90,
        icon = "image/货币道具/UI_icon_QH_1.png",
        costIcon = "image/货币道具/UI_icon_SJ_X.png",
    },
    {
        id = 14, name = "点金石", quality = 5, rewardCount = 1,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 250,
        icon = "image/货币道具/UI_icon_QH_3.png",
        costIcon = "image/货币道具/UI_icon_SJ_X.png",
    },
    {
        id = 22, name = "腐化石", quality = 5, rewardCount = 1,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 250,
        icon = "image/货币道具/UI_icon_FHS.png",
        costIcon = "image/货币道具/UI_icon_SJ_X.png",
    },
    {
        id = 15, name = "奥术粉尘", quality = 3, rewardCount = 288,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 90,
        icon = "image/货币道具/UI_icon_ASFC.png",
        costIcon = "image/货币道具/UI_icon_SJ_X.png",
    },
    {
        id = 16, name = "金币", quality = 1, rewardCount = 6666,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 94,
        icon = "image/货币道具/UI_icon_JB.png",
        costIcon = "image/货币道具/UI_icon_SJ_X.png",
    },
    {
        id = 17, name = "精粹", quality = 2, rewardCount = 666,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 94,
        icon = "image/货币道具/UI_icon_JC.png",
        costIcon = "image/货币道具/UI_icon_SJ_X.png",
    },
    {
        id = 20, name = "黄金钥匙", quality = 6, rewardCount = 1,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 300,
        icon = "image/货币道具/UI_icon_HJYS.png",
        costIcon = "image/货币道具/UI_icon_SJ_X.png",
    },
}

--- 与服务端 MarketService.SHOP_CONFIG_VERSION 保持一致；版本升级时会清空购买记录
local SHOP_CONFIG_VERSION = 7

--- 按商品 id 索引（SHOP_ITEMS 为展示顺序数组，禁止用 itemId 当下标）
local SHOP_ITEMS_BY_ID = {}
for _, item in ipairs(SHOP_ITEMS) do
    SHOP_ITEMS_BY_ID[item.id] = item
end

local function getShopItemById(itemId)
    return SHOP_ITEMS_BY_ID[itemId]
end

--- 计算实际支付价格
local function getActualPrice(item)
    return item.price
end

-- ======================== 商品网格布局 ========================

local SL = {
    -- 标题
    TITLE_CX = 540, TITLE_CY = 497, TITLE_FONT = 42,
    TITLE_R = 0x7b, TITLE_G = 0x53, TITLE_B = 0x39,
    -- 商品卡片
    CARD_W = 314, CARD_H = 402,
    CARD_COLS = 3,
    CARD_GAP_X = 30, CARD_GAP_Y = 15,
    GRID_TOP_CY = 827,
    -- 商品子元素
    NAME_OY = -160, NAME_FONT = 38, NAME_SW = 5,
    ICON_OY = -44, ICON_W = 160, ICON_H = 160,
    COUNT_OX = 54, COUNT_OY = 6, COUNT_FONT = 42, COUNT_SW = 5,
    LIMIT_OY = 66, LIMIT_FONT = 32,
    LIMIT_R = 0x4e, LIMIT_G = 0x4e, LIMIT_B = 0x4e,
    BTN_OY = 133, BTN_W = 286, BTN_H = 84,
    BTN_ICON_W = 82, BTN_ICON_H = 82, BTN_FONT = 40, BTN_SW = 5,
}

local TOTAL_GRID_W = SL.CARD_COLS * SL.CARD_W + (SL.CARD_COLS - 1) * SL.CARD_GAP_X
local GRID_LEFT = (DESIGN_W - TOTAL_GRID_W) * 0.5 + SL.CARD_W * 0.5
local CARD_STEP_X = SL.CARD_W + SL.CARD_GAP_X
local CARD_STEP_Y = SL.CARD_H + SL.CARD_GAP_Y

local SCROLL_TOP = 610
local SCROLL_BOT = 2240

local QUALITY_COLORS = {
    normal = { 181, 181, 181 },
    good   = { 162, 255, 148 },
    rare   = { 114, 242, 245 },
    epic   = { 239, 121, 255 },
}

local COL = {
    TITLE_CX = 540, TITLE_CY = 497, TITLE_FONT = 42,
    TITLE_R = 0x7b, TITLE_G = 0x53, TITLE_B = 0x39,
    CHEST_CX = 536, CHEST_CY = 883, CHEST_W = 984, CHEST_H = 616,
    NAME_X = 795, NAME_Y = 647, NAME_FONT = 70,
    DESC_X = 788, DESC_Y = 746, DESC_FONT = 30,
    PITY_W = 380, PITY_H = 70, PITY_R = 35, PITY_A = 128,
    RARE_PITY_X = 782, RARE_PITY_Y = 850,
    EPIC_PITY_X = 782, EPIC_PITY_Y = 934,
    PITY_FONT = 30,
    BTN_ONE_X = 323, BTN_TEN_X = 783, BTN_Y = 1081,
    BTN_W = 316, BTN_H = 122,
    BTN_TEXT_Y = 1058, BTN_FONT = 32,
    COST_ICON_Y = 1111, COST_ICON_SIZE = 58,
    COST_TEXT_Y = 1111, COST_FONT = 30,
    ONE_KEY = ArtifactDefs.DRAW_KEY_COST[1],
    TEN_KEY = ArtifactDefs.DRAW_KEY_COST[10],
    RARE_PITY_LEFT = 10, EPIC_PITY_LEFT = 50,
}

-- 神器宝箱：黄金钥匙不足时的快速购买确认框（布局参考 TavernPopups）
local KEY_CF = {
    MASK_A = 128,
    CX = 540, CY = 1110, W = 950, H = 647,
    TITLE_CX = 540, TITLE_CY = 856, TITLE_SIZE = 50, TITLE_STROKE_W = 6,
    SUB_CX = 540, SUB_CY = 967, SUB_SIZE = 40,
    SUB_R = 0xB6, SUB_G = 0xB0, SUB_B = 0x9D,
    CONTENT_CX = 540, CONTENT_CY = 1121, CONTENT_W = 800, CONTENT_H = 218, CONTENT_R = 16, CONTENT_A = 13,
    ARROW_CX = 540, ARROW_CY = 1123, ARROW_W = 48, ARROW_H = 48,
    DIAMOND_CX = 415, DIAMOND_CY = 1122, DIAMOND_W = 160, DIAMOND_H = 160,
    KEY_CX = 664, KEY_CY = 1122, KEY_W = 160, KEY_H = 160,
    BADGE_SIZE = 40, BADGE_STROKE_W = 5, BADGE_OX = 60, BADGE_OY = 55,
    BUY_CX = 540, BUY_CY = 1301, BUY_W = 410, BUY_H = 100,
    BUY_TEXT_SIZE = 40, BUY_TEXT_R = 0x64, BUY_TEXT_G = 0x51, BUY_TEXT_B = 0x29,
    BTN_INSET_TOP = 10, BTN_INSET_BOTTOM = 10, BTN_INSET_LEFT = 40, BTN_INSET_RIGHT = 40,
}

-- ======================== 二级弹窗布局 ========================

local DLG = {
    -- 九宫格背景（上150 下100 左右60）
    BG_CX = 540, BG_CY = 1211, BG_W = 950, BG_H = 847,
    BG_IT = 150, BG_IR = 60, BG_IB = 100, BG_IL = 60,
    -- 标题
    TITLE_CX = 540, TITLE_CY = 855, TITLE_FONT = 60, TITLE_SW = 6,
    TITLE_SR = 0x46, TITLE_SG = 0x2f, TITLE_SB = 0x20,
    -- 副标题
    SUB_CX = 540, SUB_CY = 967, SUB_FONT = 40,
    SUB_R = 0xb6, SUB_G = 0xb0, SUB_B = 0x9d,
    -- 商品背景图
    CONTENT_CX = 540, CONTENT_CY = 1121, CONTENT_W = 800, CONTENT_H = 218, CONTENT_R = 16,
    -- 商品图标（居中）
    ITEM_CX = 540, ITEM_CY = 1122, ITEM_ICON_SIZE = 160,
    -- 角标
    BADGE_FONT = 40, BADGE_SW = 5, BADGE_OX = 56, BADGE_OY = 50,
    -- 购买数量文本
    QTY_CX = 540, QTY_CY = 1278, QTY_FONT = 40, QTY_SW = 5,
    -- 减按钮
    MINUS_CX = 282, MINUS_CY = 1342, MINUS_W = 84, MINUS_H = 84,
    -- 加按钮
    PLUS_CX = 808, PLUS_CY = 1342, PLUS_W = 84, PLUS_H = 84,
    -- 滑条背景
    SLIDER_CX = 540, SLIDER_CY = 1342, SLIDER_W = 400, SLIDER_H = 24, SLIDER_R = 12,
    -- 滑块
    KNOB_SIZE = 36,
    KNOB_STROKE_R = 0x44, KNOB_STROKE_G = 0x2d, KNOB_STROKE_B = 0x19, KNOB_STROKE_W = 6,
    -- 消耗资源
    COST_CX = 540, COST_CY = 1416, COST_ICON_SIZE = 70, COST_FONT = 40, COST_SW = 5,
    -- 购买按钮
    BUY_CX = 540, BUY_CY = 1503, BUY_W = 410, BUY_H = 100, BUY_FONT = 40,
}

-- ======================== 动画参数 ========================

local ANIM_DUR       = 0.45
local CLOSE_DUR      = 0.38
local UPPER_DIST     = 1200
local LOWER_DIST     = 1600

local POPUP_OPEN_DUR   = 0.25
local POPUP_CLOSE_DUR  = 0.20
local POPUP_SCALE_FROM = 0.8
local POPUP_SCALE_TO   = 1.0

-- ======================== 缓动函数（TownPageChrome） ========================
local easeOutCubic   = TownPageChrome.easeOutCubic
local easeInCubic    = TownPageChrome.easeInCubic
local easeInOutCubic = TownPageChrome.easeInOutCubic

-- ======================== 图片句柄 ========================

local img = {
    bg = -1, nameBg = -1, lowerBg = -1, titleDeco = -1,
    gold = -1, gem = -1,
    btnBack = -1, tabBg = -1, slider = -1,
    -- 商品
    cardBg = {},       -- 品质1~6
    buyBtn = -1,
    itemIcons = {},
    costIcons = {},
    -- 弹窗
    dialogBg = -1, buyBtnYellow = -1,
    coinIcon = -1,     -- 弹窗消耗侧金币图标 (UI_icon_JB.png)
    diamondIcon = -1,  -- 弹窗消耗侧钻石图标 (UI_icon_SJ.png)
    qualityBg = {},    -- 品质1~6
    btnMinus = -1,     -- 减按钮(UI_AN_JIAN.png)
    btnPlus = -1,      -- 加按钮(UI_AN_JIA.png)
    -- 典藏
    collectionChestBg = -1, -- UI_SCDC_KC1.png
    collectionDrawBtn = -1, -- UI_SCDC_AN.png
    goldenKey = -1,
    diamondBig = -1,
    confirmArrow = -1,
}

-- ======================== 状态========================

local state = {
    open = false, closing = false, openTime = 0, closeTime = 0,
    tab = "items", tabFrom = "items", tabSwitchTime = 0,
    -- 商品
    purchased = {},    -- { [itemId] = { count, firstBuyTime, dayId } }
    shopConfigVersion = 0,
    scrollY = 0, dragging = false, lastDragY = 0,
    -- 弹窗
    dialogOpen = false, dialogItemIdx = nil,
    popupAnimTime = 0, popupClosing = false, popupCloseTime = 0,
    -- 批量购买
    buyQuantity = 1, buyMaxQuantity = 1,
    sliderDragging = false,
    -- 浮动提示
    floatText = nil, floatTextX = 0, floatTextY = 0, floatTextTime = 0,
    -- 神器宝箱：黄金钥匙快速购买确认框
    keyConfirmVisible = false,
    keyConfirmClosing = false,
    keyConfirmAnimTime = 0,
    keyConfirmCloseTime = 0,
    keyConfirmCount = 1,
    keyConfirmNeedKeys = 0,
    keyConfirmDiamondCost = 0,
    artifactFreeDrawDayId = 0,
}

-- ======================== 工具函数 ========================

local drawImageCentered = DrawUtil.drawImageCentered

local drawNineSlice = DrawUtil.drawNineSlice

local hitTest = DrawUtil.hitTest

--- 数字格式化（委托给 NumberUtil，支持 K/M/B/T）
local function formatNumber(n)
    return NumberUtil.format(n)
end

-- ======================== 弹窗动画辅助 ========================

local function getPopupAnim()
    if state.popupClosing then
        local t = math.min(1.0, (time.elapsedTime - state.popupCloseTime) / POPUP_CLOSE_DUR)
        local e = easeInCubic(t)
        local scale = POPUP_SCALE_TO + (POPUP_SCALE_FROM - POPUP_SCALE_TO) * e
        return scale, 1.0 - e, (t >= 1.0)
    else
        local t = math.min(1.0, (time.elapsedTime - state.popupAnimTime) / POPUP_OPEN_DUR)
        local e = easeOutCubic(t)
        local scale = POPUP_SCALE_FROM + (POPUP_SCALE_TO - POPUP_SCALE_FROM) * e
        return scale, e, false
    end
end

-- ======================== 购买次数 ========================

local COOLDOWN_SECONDS = { ["2h"] = 7200 }

--- 获取当天编号（UTC+8，与服务端getDayId 保持一致）
local function getDayId()
    return math.floor((os.time() + 28800) / 86400)
end

local function hasArtifactFreeDraw()
    local artifacts = PlayerStore.Get("artifacts") or {}
    local usedDayId = tonumber(artifacts.dailyFreeDrawDayId) or tonumber(state.artifactFreeDrawDayId) or 0
    return usedDayId ~= getDayId()
end

--- 获取冷却型商品剩余补货秒数（0 = 无冷却或已到期）
local function getCooldownRemaining(item)
    if not item or item.restockType ~= "cooldown" then return 0 end
    local rec = state.purchased[item.id]
    if not rec then return 0 end
    local firstBuyTime = rec.firstBuyTime or 0
    if firstBuyTime <= 0 or (rec.count or 0) <= 0 then return 0 end
    local cd = COOLDOWN_SECONDS[item.restockPeriod] or 7200
    local elapsed = os.time() - firstBuyTime
    if elapsed >= cd then return 0 end
    return cd - elapsed
end

--- 获取商品已购次数（每日型跨天后视为 0 / 冷却型到期后视为 0）
local function getPurchased(itemId)
    local rec = state.purchased[itemId]
    if not rec then return 0 end
    local item = getShopItemById(itemId)
    if not item then return rec.count or 0 end
    -- 每日型补货检测：跨天 → 已购次数归零
    if item.restockType == "daily" then
        local currentDay = getDayId()
        if (rec.dayId or 0) ~= currentDay then
            return 0
        end
    -- 冷却型补货检测：倒计时到期 → 存货补满
    elseif item.restockType == "cooldown" then
        local firstBuyTime = rec.firstBuyTime or 0
        if firstBuyTime > 0 and (rec.count or 0) > 0 then
            local cd = COOLDOWN_SECONDS[item.restockPeriod] or 7200
            if (os.time() - firstBuyTime) >= cd then
                return 0
            end
        end
    end
    return rec.count or 0
end

local function isSoldOut(item)
    if item.limitCount == -1 then return false end  -- 永久不限购
    return getPurchased(item.id) >= item.limitCount
end

-- ======================== 商品卡片绘制 ========================


local _shopCard
local function bindShopCard()
    _shopCard = MarketShopCard.bind({
        SL = SL, DLG = DLG, P1 = P1, DESIGN_W = DESIGN_W, SHOP_ITEMS = SHOP_ITEMS,
        BF = BF, img = img, state = state,
        drawImageCentered = drawImageCentered, drawTextStroke = drawTextStroke,
        getActualPrice = getActualPrice, getCooldownRemaining = getCooldownRemaining,
        getPopupAnim = getPopupAnim, getPurchased = getPurchased, isSoldOut = isSoldOut,
    })
end

local function drawShopCard(vg, idx, item, cx, cy)
    bindShopCard()
    return _shopCard.drawShopCard(vg, idx, item, cx, cy)
end

-- ======================== 二级弹窗绘制（前向声明） ========================

local drawPurchaseDialog

drawPurchaseDialog = function(vg)
    if not state.dialogOpen or not state.dialogItemIdx then return end
    local idx = state.dialogItemIdx
    local item = SHOP_ITEMS[idx]
    if not item then return end

    local pScale, pAlpha, _ = getPopupAnim()

    -- 遮罩
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

    -- 1. 背景（九宫格 上150 下100 左右60）
    DarkIcon.drawNine(vg, "panel", DLG.BG_CX - DLG.BG_W * 0.5, DLG.BG_CY - DLG.BG_H * 0.5, DLG.BG_W, DLG.BG_H, { titleH = DLG.BG_IT })

    -- 2. 标题"购买道具"
    drawTextStroke(vg, DLG.TITLE_CX, DLG.TITLE_CY, "购买道具",
        DLG.TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DLG.TITLE_SW,
        { strokeColor = { DLG.TITLE_SR, DLG.TITLE_SG, DLG.TITLE_SB } })

    -- 3. 副标题是否购买此物品
    nvgFontFace(vg, "sans"); nvgFontSize(vg, DLG.SUB_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(DLG.SUB_R, DLG.SUB_G, DLG.SUB_B, 255))
    nvgText(vg, DLG.SUB_CX, DLG.SUB_CY, "是否购买此物品", nil)

    -- 4. 商品背景图
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        DLG.CONTENT_CX - DLG.CONTENT_W * 0.5,
        DLG.CONTENT_CY - DLG.CONTENT_H * 0.5,
        DLG.CONTENT_W, DLG.CONTENT_H, DLG.CONTENT_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))
    nvgFill(vg)

    -- 5. 品质背景 + 商品图标（居中）
    DarkIcon.drawQualityBg(vg, item.quality or 1,
        DLG.ITEM_CX, DLG.ITEM_CY, DLG.ITEM_ICON_SIZE, DLG.ITEM_ICON_SIZE, 1.0)  -- [暗黑化 P2-A]
    local rewardImg = img.itemIcons[idx]
    if rewardImg and rewardImg >= 0 then
        drawImageCentered(vg, rewardImg,
            DLG.ITEM_CX, DLG.ITEM_CY, DLG.ITEM_ICON_SIZE, DLG.ITEM_ICON_SIZE, 1.0)
    end

    -- 6. 角标（图标右下角，样式不变）
    drawTextStroke(vg,
        DLG.ITEM_CX + DLG.BADGE_OX, DLG.ITEM_CY + DLG.BADGE_OY,
        tostring(item.rewardCount or 1),
        DLG.BADGE_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        255, 255, 255, DLG.BADGE_SW, { strokeColor = { 0, 0, 0 } })

    -- 7. 购买数量文本 "购买数量:N"
    local qtyText = "购买数量:" .. state.buyQuantity
    drawTextStroke(vg, DLG.QTY_CX, DLG.QTY_CY, qtyText,
        DLG.QTY_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DLG.QTY_SW, { strokeColor = { 0, 0, 0 } })

    -- 8. 减按钮
    local _sm = BF.begin(vg, "market_dlg_minus", DLG.MINUS_CX, DLG.MINUS_CY, DLG.MINUS_W, DLG.MINUS_H)
    drawImageCentered(vg, img.btnMinus,
        DLG.MINUS_CX, DLG.MINUS_CY, DLG.MINUS_W, DLG.MINUS_H,
        state.buyQuantity <= 1 and 0.4 or 1.0)
    BF.finish(vg, _sm)

    -- 9. 加按钮
    local _sp = BF.begin(vg, "market_dlg_plus", DLG.PLUS_CX, DLG.PLUS_CY, DLG.PLUS_W, DLG.PLUS_H)
    drawImageCentered(vg, img.btnPlus,
        DLG.PLUS_CX, DLG.PLUS_CY, DLG.PLUS_W, DLG.PLUS_H,
        state.buyQuantity >= state.buyMaxQuantity and 0.4 or 1.0)
    BF.finish(vg, _sp)

    -- 10. 滑条背景
    local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
    local sliderR = DLG.SLIDER_CX + DLG.SLIDER_W * 0.5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sliderL, DLG.SLIDER_CY - DLG.SLIDER_H * 0.5,
        DLG.SLIDER_W, DLG.SLIDER_H, DLG.SLIDER_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 51))
    nvgFill(vg)

    -- 已填充部分
    local sliderFrac = 0
    if state.buyMaxQuantity > 1 then
        sliderFrac = (state.buyQuantity - 1) / (state.buyMaxQuantity - 1)
    end
    local fillW = DLG.SLIDER_W * sliderFrac
    if fillW > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sliderL, DLG.SLIDER_CY - DLG.SLIDER_H * 0.5,
            fillW, DLG.SLIDER_H, DLG.SLIDER_R)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 80))
        nvgFill(vg)
    end

    -- 11. 滑块（圆形，纯白+描边）
    local knobX = sliderL + DLG.SLIDER_W * sliderFrac
    local knobR = DLG.KNOB_SIZE * 0.5
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, DLG.SLIDER_CY, knobR)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(DLG.KNOB_STROKE_R, DLG.KNOB_STROKE_G, DLG.KNOB_STROKE_B, 255))
    nvgStrokeWidth(vg, DLG.KNOB_STROKE_W)
    nvgStroke(vg)

    -- 12. 消耗资源组合 "图标×N"
    local actualPrice = getActualPrice(item)
    local totalCost = actualPrice * state.buyQuantity
    local costStr = "×" .. tostring(totalCost)
    local dialogCostIcon = img.coinIcon
    if item.currency == "diamond" then
        dialogCostIcon = img.diamondIcon or img.coinIcon
    end
    -- 测量文本宽度以居中排列 图标+文本
    nvgFontFace(vg, "sans"); nvgFontSize(vg, DLG.COST_FONT)
    local costTextW = nvgTextBounds(vg, 0, 0, costStr)
    local costIconW = DLG.COST_ICON_SIZE
    local costGap = 4
    local costTotalW = costIconW + costGap + costTextW
    local costStartX = DLG.COST_CX - costTotalW * 0.5
    drawImageCentered(vg, dialogCostIcon,
        costStartX + costIconW * 0.5, DLG.COST_CY, costIconW, DLG.COST_ICON_SIZE, 1.0)
    drawTextStroke(vg, costStartX + costIconW + costGap, DLG.COST_CY, costStr,
        DLG.COST_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, DLG.COST_SW, { strokeColor = { 0, 0, 0 } })

    -- 购买按钮
    local _sd = BF.begin(vg, "market_dlg_buy", DLG.BUY_CX, DLG.BUY_CY, DLG.BUY_W, DLG.BUY_H)
    DarkIcon.drawNine(vg, "btn", DLG.BUY_CX - DLG.BUY_W * 0.5, DLG.BUY_CY - DLG.BUY_H * 0.5, DLG.BUY_W, DLG.BUY_H, { accent = "gold" })
    nvgFontFace(vg, "sans"); nvgFontSize(vg, DLG.BUY_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(244, 237, 224, 179))
    nvgText(vg, DLG.BUY_CX, DLG.BUY_CY, "购买", nil)
    BF.finish(vg, _sd)

    nvgRestore(vg)
end

-- ======================== Tab 内容绘制 ========================

local _collection
local function bindCollection()
    _collection = MarketCollection.bind({
        COL = COL,
        P1 = P1,
        KEY_CF = KEY_CF,
        DESIGN_W = DESIGN_W,
        DESIGN_H = DESIGN_H,
        BF = BF,
        img = img,
        state = state,
        QUALITY_COLORS = QUALITY_COLORS,
        POPUP_OPEN_DUR = POPUP_OPEN_DUR,
        POPUP_CLOSE_DUR = POPUP_CLOSE_DUR,
        POPUP_SCALE_FROM = POPUP_SCALE_FROM,
        POPUP_SCALE_TO = POPUP_SCALE_TO,
        easeOutCubic = easeOutCubic,
        easeInCubic = easeInCubic,
        drawImageCentered = drawImageCentered,
        drawTextStroke = drawTextStroke,
        Protocol = Protocol,
        getSendAction = function() return sendAction_ end,
        getDayId = getDayId,
        hasArtifactFreeDraw = hasArtifactFreeDraw,
    })
end

local function ensureCollection()
    if not _collection then bindCollection() end
    return _collection
end

local function drawLockedContent(vg)
    return ensureCollection().drawLockedContent(vg)
end

local function isArtifactChestUnlocked()
    return ensureCollection().isArtifactChestUnlocked()
end

local function getKeyCost(count)
    return ensureCollection().getKeyCost(count)
end

local function checkKeyAndDraw(count)
    return ensureCollection().checkKeyAndDraw(count)
end

local function closeKeyConfirm()
    return ensureCollection().closeKeyConfirm()
end

local function drawKeyConfirmDialog(vg)
    return ensureCollection().drawKeyConfirmDialog(vg)
end

local function drawCollectionContent(vg)
    return ensureCollection().drawCollectionContent(vg)
end

local function sendArtifactDraw(count)
    return ensureCollection().sendArtifactDraw(count)
end

local function drawItemsContent(vg)
    -- 标题
    drawImageCentered(vg, img.titleDeco, P1.DECO_CX, P1.DECO_CY, P1.DECO_W, P1.DECO_H, 1.0)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, SL.TITLE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(SL.TITLE_R, SL.TITLE_G, SL.TITLE_B, 255))
    nvgText(vg, SL.TITLE_CX, SL.TITLE_CY, "市场商店", nil)

    -- 商品网格
    local rowCount = math.ceil(#SHOP_ITEMS / SL.CARD_COLS)
    local totalH = rowCount * CARD_STEP_Y - SL.CARD_GAP_Y
    local contentTop = SL.GRID_TOP_CY - SL.CARD_H * 0.5
    local contentBottom = contentTop + totalH
    local clipH = SCROLL_BOT - SCROLL_TOP
    local maxScroll = math.max(0, contentBottom - SCROLL_BOT)
    state.scrollY = math.max(0, math.min(state.scrollY, maxScroll))

    nvgSave(vg)
    nvgIntersectScissor(vg, 20, SCROLL_TOP, DESIGN_W - 40, clipH)
    nvgTranslate(vg, 0, -state.scrollY)

    for idx, item in ipairs(SHOP_ITEMS) do
        local col = ((idx - 1) % SL.CARD_COLS)
        local row = math.floor((idx - 1) / SL.CARD_COLS)
        local cx = GRID_LEFT + col * CARD_STEP_X
        local cy = SL.GRID_TOP_CY + row * CARD_STEP_Y

        local screenCY = cy - state.scrollY
        if screenCY >= SCROLL_TOP - SL.CARD_H and screenCY <= SCROLL_BOT + SL.CARD_H then
            drawShopCard(vg, idx, item, cx, cy)
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)
end

local TAB_DRAW = { collection = drawCollectionContent, items = drawItemsContent }

-- ======================== Public API ========================

local _marketInit
local function bindMarketInit()
    _marketInit = MarketInit.bind({
        img = img,
        state = state,
        SHOP_ITEMS = SHOP_ITEMS,
    })
end

function MarketPage.init(vg)
    if not _marketInit then bindMarketInit() end
    return _marketInit.init(vg)
end

function MarketPage.open()
    if not _marketInit then bindMarketInit() end
    if not _marketInit.isInited() and _marketInit.getVg() then
        MarketPage.init(_marketInit.getVg())
    end
    if not _marketInit.isInited() then
        print("[MarketPage] open before init, skip")
        return
    end
    -- 打开时从 PlayerStore 刷新限购状态，避免热更/重连后会话内 purchased 过期
    local marketData = PlayerStore.Get("market")
    if marketData then
        MarketPage.setMarketData(marketData)
    end
    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    require("systems.GameSFX").playUIMove(1)
    state.scrollY = 0
    state.dragging = false
    state.tab = "items"
    state.tabFrom = "items"
    state.tabSwitchTime = 0
    state.dialogOpen = false
    state.dialogItemIdx = nil
    state.popupClosing = false
    print("[MarketPage] 打开市场")
end

function MarketPage.close()
    if state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    -- 关闭弹窗
    if state.dialogOpen then
        state.dialogOpen = false
        state.dialogItemIdx = nil
        state.popupClosing = false
    end
    state.keyConfirmVisible = false
    state.keyConfirmClosing = false
    print("[MarketPage] 关闭市场（动画）")
end

function MarketPage.isOpen() return state.open end

--- 强制关闭（跳过动画，用于安全恢复 — 离开 tab4 时调用）
function MarketPage.forceClose()
    if not state.open then return end
    print("[MarketPage] forceClose: 跳过动画强制关闭 (closing=" .. tostring(state.closing) .. ")")
    state.open = false
    state.closing = false
    if state.dialogOpen then
        state.dialogOpen = false
        state.dialogItemIdx = nil
        state.popupClosing = false
    end
end

function MarketPage.getAnimProgress()
    if not state.open then return 0 end
    if state.closing then
        local t = math.min(1.0, (time.elapsedTime - state.closeTime) / CLOSE_DUR)
        return 1 - easeInCubic(t)
    else
        local t = math.min(1.0, (time.elapsedTime - state.openTime) / ANIM_DUR)
        return easeOutCubic(t)
    end
end


function MarketPage.update(dt)
    if not state.open then return end
    -- 弹窗关闭动画
    if state.dialogOpen and state.popupClosing then
        local _, _, done = getPopupAnim()
        if done then
            state.popupClosing = false
            state.dialogOpen = false
            state.dialogItemIdx = nil
        end
    end
end

-- ======================== 主绘制========================

local _pageDraw
local function bindPageDraw()
    _pageDraw = MarketDraw.bind({
        ANIM_DUR = ANIM_DUR,
        BF = BF,
        CLOSE_DUR = CLOSE_DUR,
        DESIGN_H = DESIGN_H,
        DESIGN_W = DESIGN_W,
        DarkIcon = DarkIcon,
        GameState = GameState,
        LOWER_DIST = LOWER_DIST,
        P1 = P1,
        TAB = TAB,
        TAB_DRAW = TAB_DRAW,
        TownPageChrome = TownPageChrome,
        UPPER_DIST = UPPER_DIST,
        drawImageCentered = drawImageCentered,
        drawKeyConfirmDialog = drawKeyConfirmDialog,
        drawPurchaseDialog = drawPurchaseDialog,
        drawTextStroke = drawTextStroke,
        easeInCubic = easeInCubic,
        easeInOutCubic = easeInOutCubic,
        easeOutCubic = easeOutCubic,
        formatNumber = formatNumber,
        img = img,
        state = state
    })
end

local function drawPageImpl(vg)
    bindPageDraw()
    return _pageDraw.drawPageImpl(vg)
end

-- ======================== 输入处理 ========================

local _input
local function bindInput()
    _input = MarketInput.bind({
        BF = BF,
        CARD_STEP_X = CARD_STEP_X,
        CARD_STEP_Y = CARD_STEP_Y,
        COL = COL,
        DLG = DLG,
        GRID_LEFT = GRID_LEFT,
        GameState = GameState,
        KEY_CF = KEY_CF,
        MarketPage = MarketPage,
        Protocol = Protocol,
        SCROLL_BOT = SCROLL_BOT,
        SCROLL_TOP = SCROLL_TOP,
        SHOP_ITEMS = SHOP_ITEMS,
        SL = SL,
        TAB = TAB,
        TownPageChrome = TownPageChrome,
        checkKeyAndDraw = checkKeyAndDraw,
        closeKeyConfirm = closeKeyConfirm,
        getActualPrice = getActualPrice,
        getPurchased = getPurchased,
        hitTest = hitTest,
        isArtifactChestUnlocked = isArtifactChestUnlocked,
        isSoldOut = isSoldOut,
        sendAction_ = sendAction_,
        sendArtifactDraw = sendArtifactDraw,
        state = state
    })
end

function MarketPage.handleInput(dx, dy)
    bindInput()
    return _input.handleInput(dx, dy)
end

function MarketPage.handleDragBegin(dx, dy)
    bindInput()
    return _input.handleDragBegin(dx, dy)
end

function MarketPage.handleDragMove(dx, dy)
    bindInput()
    return _input.handleDragMove(dx, dy)
end

function MarketPage.handleDragEnd(dx, dy)
    bindInput()
    return _input.handleDragEnd(dx, dy)
end

function MarketPage.handleScroll(wheel)
    bindInput()
    return _input.handleScroll(wheel)
end

-- ======================== 服务端结果处理========================

local _marketResults
local function bindMarketResults()
    _marketResults = MarketResults.bind({
        state = state,
        Protocol = Protocol,
        COL = COL,
        getShopItemById = getShopItemById,
        getDayId = getDayId,
        SHOP_CONFIG_VERSION = SHOP_CONFIG_VERSION,
    })
end

local function ensureMarketResults()
    if not _marketResults then bindMarketResults() end
    return _marketResults
end

--- 接收服务端MARKET_BUY 操作结果
function MarketPage.onActionResult(data)
    return ensureMarketResults().onActionResult(data)
end

--- 接收服务端推送的 market 模块数据（purchased 购买记录）
function MarketPage.setMarketData(data)
    return ensureMarketResults().setMarketData(data)
end

--- 清理同会话切区时的市场页区服数据缓存
function MarketPage.resetSessionData()
    return ensureMarketResults().resetSessionData()
end

--- [水平滑入] 整页从屏幕边缘滑入/滑出(与中缝返回条同步);0=完全展开
function MarketPage.getSeamAnim()
    return state.openTime, state.closeTime, ANIM_DUR, CLOSE_DUR
end

function MarketPage.draw(vg)
    local ot, ct, od, cd = MarketPage.getSeamAnim()
    local ox = DrawUtil.seamSlideX(-1, ot, ct, od, cd, 1080)
    if ox ~= 0 then
        nvgSave(vg)
        nvgTranslate(vg, ox, 0)
    end
    drawPageImpl(vg)
    if ox ~= 0 then
        nvgRestore(vg)
    end
end

return MarketPage
