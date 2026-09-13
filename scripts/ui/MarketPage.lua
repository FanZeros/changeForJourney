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
local BF = require("systems.ButtonFeedback")
local RewardPopup = require("ui.RewardPopup")

local AdManager  = require("systems.AdManager")
local NumberUtil   = require("core.NumberUtil")
local MarketSchema = require("shared.market.MarketSchema")
local ArtifactDefs = require("shared.artifact.ArtifactDefs")
local PlayerStore  = require("client.data.PlayerStore")
local StageConfig  = require("config.StageConfig")

local MarketPage = {}

--- sendAction 注入（由 Client.lua 调用 setSendAction 设置）
local sendAction_ = nil

function MarketPage.setSendAction(fn)
    sendAction_ = fn
end

local function getPrivilegeAdRewardPoints()
    return MarketSchema.AD_PRIVILEGE_REWARD_PER_WATCH
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
    -- 资源0（特权点）— 金币左侧，间距同金币到钻石
    R0_BG_CX = 505, R0_BG_CY = 303,
    R0_ICON_CX = 441, R0_ICON_CY = 303, R0_ICON_W = 82, R0_ICON_H = 82,
    R0_TX = 524, R0_TY = 304,
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
    BACK_CX = 122, BACK_CY = 2308, BACK_W = 184, BACK_H = 143,
    BG_CX = 639, BG_CY = 2308, BG_W = 810, BG_H = 143,
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
    -- ===== 特权点商品（每日刷新）=====
    {
        id = 1, name = "扫荡券", quality = 4, rewardCount = 1,
        restockType = "daily", limitCount = -1,
        currency = "privilege", price = 1,
        icon = "image/UI_icon_SDQ.png",
        costIcon = "image/UI_icon_TQD_X.png",
    },
    {
        id = 2, name = "冒险招募券", quality = 4, rewardCount = 1,
        restockType = "daily", limitCount = -1,
        currency = "privilege", price = 1,
        icon = "image/UI_icon_ZMQ_1.png",
        costIcon = "image/UI_icon_TQD_X.png",
    },
    {
        id = 3, name = "钻石", quality = 5, rewardCount = 240,
        restockType = "daily", limitCount = -1,
        currency = "privilege", price = 1,
        icon = "image/UI_icon_SJ.png",
        costIcon = "image/UI_icon_TQD_X.png",
    },
    {
        id = 4, name = "随机卷轴", quality = 3, rewardCount = 20,
        restockType = "daily", limitCount = -1,
        currency = "privilege", price = 1,
        icon = "image/UI_icon_JZ_SJ.png",
        costIcon = "image/UI_icon_TQD_X.png",
    },
    {
        id = 5, name = "加速卡", quality = 5, rewardCount = 1,
        restockType = "daily", limitCount = -1,
        currency = "privilege", price = 10,
        icon = "image/UI_icon_JSK.png",
        costIcon = "image/UI_icon_TQD_X.png",
    },
    {
        id = 6, name = "随机优质遗物", quality = 2, rewardCount = 1,
        restockType = "daily", limitCount = -1,
        currency = "privilege", price = 1,
        icon = "image/ICON_SJYW.png",
        costIcon = "image/UI_icon_TQD_X.png",
    },
    {
        id = 7, name = "奥术粉尘", quality = 3, rewardCount = 288,
        restockType = "daily", limitCount = -1,
        currency = "privilege", price = 1,
        icon = "image/UI_icon_ASFC.png",
        costIcon = "image/UI_icon_TQD_X.png",
    },
    {
        id = 19, name = "星辉招募券", quality = 6, rewardCount = 1,
        restockType = "daily", limitCount = -1,
        currency = "privilege", price = 4,
        icon = "image/UI_icon_ZMQ_2.png",
        costIcon = "image/UI_icon_TQD_X.png",
    },
    {
        id = 23, name = "神圣石", quality = 6, rewardCount = 1,
        restockType = "daily", limitCount = -1,
        currency = "privilege", price = 5,
        icon = "image/UI_icon_SSS.png",
        costIcon = "image/UI_icon_TQD_X.png",
    },
    -- ===== 钻石商品（每日刷新，40% 折扣价=====
    {
        id = 8, name = "冒险招募券", quality = 5, rewardCount = 1,
        restockType = "daily", limitCount = -1,
        currency = "diamond", price = 180, discount = 0.4,
        icon = "image/UI_icon_ZMQ_1.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
    {
        id = 9, name = "洗练石", quality = 3, rewardCount = 2,
        restockType = "daily", limitCount = -1,
        currency = "diamond", price = 180, discount = 0.4,
        icon = "image/UI_icon_QH_1.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
    {
        id = 10, name = "随机卷轴", quality = 3, rewardCount = 10,
        restockType = "daily", limitCount = -1,
        currency = "diamond", price = 180, discount = 0.4,
        icon = "image/UI_icon_JZ_SJ.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
    {
        id = 11, name = "点金石", quality = 5, rewardCount = 1,
        restockType = "daily", limitCount = -1,
        currency = "diamond", price = 500, discount = 0.4,
        icon = "image/UI_icon_QH_3.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
    {
        id = 21, name = "腐化石", quality = 5, rewardCount = 1,
        restockType = "daily", limitCount = -1,
        currency = "diamond", price = 500, discount = 0.4,
        icon = "image/UI_icon_FHS.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
    -- ===== 钻石商品（永久，不限购） =====
    {
        id = 12, name = "冒险招募券", quality = 5, rewardCount = 1,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 180,
        icon = "image/UI_icon_ZMQ_1.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
    {
        id = 13, name = "洗练石", quality = 3, rewardCount = 2,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 180,
        icon = "image/UI_icon_QH_1.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
    {
        id = 14, name = "点金石", quality = 5, rewardCount = 1,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 500,
        icon = "image/UI_icon_QH_3.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
    {
        id = 22, name = "腐化石", quality = 5, rewardCount = 1,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 500,
        icon = "image/UI_icon_FHS.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
    {
        id = 15, name = "奥术粉尘", quality = 3, rewardCount = 288,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 180,
        icon = "image/UI_icon_ASFC.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
    {
        id = 16, name = "金币", quality = 1, rewardCount = 6666,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 188,
        icon = "image/UI_icon_JB.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
    {
        id = 17, name = "精粹", quality = 2, rewardCount = 666,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 188,
        icon = "image/UI_icon_JC.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
    -- ===== 星辉招募券（每日刷新） =====
    {
        id = 18, name = "星辉招募券", quality = 6, rewardCount = 1,
        restockType = "daily", limitCount = -1,
        currency = "diamond", price = 900, discount = 0.8,
        icon = "image/UI_icon_ZMQ_2.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
    {
        id = 20, name = "黄金钥匙", quality = 6, rewardCount = 1,
        restockType = "permanent", limitCount = -1,
        currency = "diamond", price = 600,
        icon = "image/UI_icon_HJYS.png",
        costIcon = "image/UI_icon_SJ_X.png",
    },
}

--- 与服务端 MarketService.SHOP_CONFIG_VERSION 保持一致；版本升级时会清空购买记录
local SHOP_CONFIG_VERSION = 5

--- 按商品 id 索引（SHOP_ITEMS 为展示顺序数组，禁止用 itemId 当下标）
local SHOP_ITEMS_BY_ID = {}
for _, item in ipairs(SHOP_ITEMS) do
    SHOP_ITEMS_BY_ID[item.id] = item
end

local function getShopItemById(itemId)
    return SHOP_ITEMS_BY_ID[itemId]
end

--- 计算实际支付价格（折扣后）
local function getActualPrice(item)
    if item.discount then
        return math.floor(item.price * item.discount)
    end
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
-- [已移除] UI层广告超时：AdManager 自身有三重超时保护（8s焦点清理/40s加载超时），
-- 此处的20s超时在玩家广告时长>20s时会误触发，导致SDK正常回调被忽略、服务端计数丢失。
local UPPER_DIST     = 1200
local LOWER_DIST     = 1600

local POPUP_OPEN_DUR   = 0.25
local POPUP_CLOSE_DUR  = 0.20
local POPUP_SCALE_FROM = 0.8
local POPUP_SCALE_TO   = 1.0

-- ======================== 缓动函数 ========================

local function easeOutCubic(t) t = t - 1; return t * t * t + 1 end
local function easeInCubic(t) return t * t * t end
local function easeInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t
    else local f = 2 * t - 2; return 0.5 * f * f * f + 1 end
end

-- ======================== 图片句柄 ========================

local img = {
    bg = -1, nameBg = -1, lowerBg = -1, titleDeco = -1,
    gold = -1, gem = -1, privilege = -1,
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
    privilegeIcon = -1, -- 弹窗消耗侧特权点图标(UI_icon_TQD.png)
    qualityBg = {},    -- 品质1~6
    btnMinus = -1,     -- 减按钮(UI_AN_JIAN.png)
    btnPlus = -1,      -- 加按钮(UI_AN_JIA.png)
    -- 特权
    privBg = -1,          -- UI_SC_TQBJ.png  上方背景 1080×930
    privLowerBg = -1,     -- UI_TJP_1.png    下方背景框（与 lowerBg 相同资源，单独记录语义）
    privProgBg = -1,      -- UI_TQ_JDY2.png  进度条背景
    privProgFill = -1,    -- UI_TQ_JDY1.png  进度条填充
    privDotActive = -1,   -- UI_TQ_1.png     已激活进度点
    privDotInactive = -1, -- UI_TQ_2.png     未激活进度点
    privRewardBg = -1,    -- UI_TQ_3.png     奖励背景
    privClaimBtn = -1,    -- UI_AN_LV.png    领取按钮（复用绿色按钮）
    imgRedDot    = -1,    -- ICON_HD.png     红点角标
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
    -- 特权 tab
    privScrollY = 0, privDragging = false, privLastDragY = 0,
    privWatchCount = 0,        -- 累计观看广告次数
    privRefreshHour = 0,       -- 刷新时间 时
    privRefreshMin = 0,        -- 刷新时间 分
    privClaimed = {},          -- { [threshold] = true }  已领取的奖励
    privAdWatching = false,    -- 正在播放广告（防重复点击）
    privAdCooldownUntil = 0,   -- 广告冷却截止时间（time.elapsedTime），默认见 MarketSchema.AD_PRIVILEGE_CLICK_COOLDOWN_SECS
    privRefreshTotalSecs = 0,  -- 刷新倒计时总秒数（服务端同步时设置，用于实时倒计时）
    privRefreshSyncTime = 0,   -- 服务端同步时的 time.elapsedTime（用于计算已经过时间）
    -- [已移除] 广告确认重试机制：现用AdManager + AdHandler 统一处理
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

local function drawShopCard(vg, idx, item, cx, cy)
    -- [暗黑化 P1-B5] 矢量卡底 + 品质语义描边
    local q = item.quality or 1
    DarkIcon.drawNine(vg, "plain",
        cx - SL.CARD_W * 0.5, cy - SL.CARD_H * 0.5,
        SL.CARD_W, SL.CARD_H,
        { accent = DarkIcon.QUALITY_TRIM[math.min(6, math.max(1, q))] })

    local bought = getPurchased(item.id)
    local soldOut = isSoldOut(item)

    -- 商品区
    drawTextStroke(vg, cx, cy + SL.NAME_OY, item.name,
        SL.NAME_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, SL.NAME_SW, { strokeColor = { 0, 0, 0 } })

    -- 商品图标
    local iconImg = img.itemIcons[idx]
    if iconImg and iconImg >= 0 then
        drawImageCentered(vg, iconImg, cx, cy + SL.ICON_OY, SL.ICON_W, SL.ICON_H, soldOut and 0.4 or 1.0)
    end

    -- 数量角标
    drawTextStroke(vg, cx + SL.COUNT_OX, cy + SL.COUNT_OY, tostring(item.rewardCount or 1),
        SL.COUNT_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        255, 255, 255, SL.COUNT_SW, { strokeColor = { 0, 0, 0 } })

    -- 限购文本（仅限购商品显示；不限购不显示）
    if item.limitCount ~= -1 then
        local remaining = item.limitCount - bought
        if remaining < 0 then remaining = 0 end
        local limitText
        if item.restockType == "cooldown" then
            local cdLeft = getCooldownRemaining(item)
            local cdStr
            if cdLeft > 0 then
                local h = math.floor(cdLeft / 3600)
                local m = math.floor((cdLeft % 3600) / 60)
                local s = cdLeft % 60
                cdStr = string.format("%d:%02d:%02d", h, m, s)
            else
                cdStr = item.restockPeriod or "2h"
            end
            limitText = "限购" .. remaining .. "分" .. cdStr
        elseif item.restockType == "daily" then
            limitText = "限购" .. remaining .. "份/日"
        else
            limitText = "限购" .. remaining .. "份"
        end
        nvgFontFace(vg, "sans"); nvgFontSize(vg, SL.LIMIT_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(SL.LIMIT_R, SL.LIMIT_G, SL.LIMIT_B, 255))
        nvgText(vg, cx, cy + SL.LIMIT_OY, limitText, nil)
    end

    -- 购买按钮
    ---@diagnostic disable-next-line: assign-type-mismatch
    local btnCY = cy + SL.BTN_OY
    ---@diagnostic disable-next-line: assign-type-mismatch
    local _sc = BF.begin(vg, "market_buy_" .. idx, cx, btnCY, SL.BTN_W, SL.BTN_H)
    if soldOut then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - SL.BTN_W * 0.5, btnCY - SL.BTN_H * 0.5, SL.BTN_W, SL.BTN_H, 12)
        nvgFillColor(vg, nvgRGBA(80, 80, 80, 200))
        nvgFill(vg)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, SL.BTN_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
        nvgText(vg, cx, btnCY, "已售罄", nil)
    else
        DarkIcon.drawNine(vg, "btn", cx - SL.BTN_W * 0.5, btnCY - SL.BTN_H * 0.5, SL.BTN_W, SL.BTN_H, { accent = "gold" })

        local actualPrice = getActualPrice(item)
        local priceStr = tostring(actualPrice)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, SL.BTN_FONT)
        local bounds = {}
        local textW = nvgTextBounds(vg, 0, 0, priceStr, nil, bounds)
        local iconW = SL.BTN_ICON_W
        local iconH = SL.BTN_ICON_H
        local gap = 4

        if item.discount then
            -- 折扣模式：图标+ 折扣价主体) + 原价(划线，偏移
            local origStr = tostring(item.price)
            nvgFontSize(vg, 26)
            local origW = nvgTextBounds(vg, 0, 0, origStr, nil, bounds)
            nvgFontSize(vg, SL.BTN_FONT)
            local discGap = 6
            local totalW = iconW + gap + textW + discGap + origW
            local startX = cx - totalW * 0.5

            local costImg = img.costIcons[idx]
            if costImg and costImg >= 0 then
                drawImageCentered(vg, costImg, startX + iconW * 0.5, btnCY, iconW, iconH, 1.0)
            end
            -- 折扣价（主体，白色）
            local discX = startX + iconW + gap
            drawTextStroke(vg, discX, btnCY, priceStr,
                SL.BTN_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                255, 255, 255, SL.BTN_SW, { strokeColor = { 0, 0, 0 } })
            -- 原价（小字 + 划线 + 描边，灰红色更醒目）
            local origX = discX + textW + discGap
            drawTextStroke(vg, origX, btnCY, origStr,
                26, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                255, 160, 140, 3,
                { alpha = 220 / 255, strokeColor = { 0, 0, 0 } })
            -- 划线
            nvgBeginPath(vg)
            nvgMoveTo(vg, origX - 2, btnCY)
            nvgLineTo(vg, origX + origW + 2, btnCY)
            nvgStrokeColor(vg, nvgRGBA(255, 160, 140, 220))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        else
            -- 普通模式
            local totalW = iconW + gap + textW
            local startX = cx - totalW * 0.5

            local costImg = img.costIcons[idx]
            if costImg and costImg >= 0 then
                drawImageCentered(vg, costImg, startX + iconW * 0.5, btnCY, iconW, iconH, 1.0)
            end
            drawTextStroke(vg, startX + iconW + gap, btnCY, priceStr,
                SL.BTN_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                255, 255, 255, SL.BTN_SW, { strokeColor = { 0, 0, 0 } })
        end
    end
    BF.finish(vg, _sc)
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
    elseif item.currency == "privilege" then
        dialogCostIcon = img.privilegeIcon or img.coinIcon
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
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 179))
    nvgText(vg, DLG.BUY_CX, DLG.BUY_CY, "购买", nil)
    BF.finish(vg, _sd)

    nvgRestore(vg)
end

-- ======================== Tab 内容绘制 ========================

local function drawLockedContent(vg)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, 48)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
    nvgText(vg, 540, 1100, "敬请期待", nil)

    nvgFontSize(vg, 36)
    nvgFillColor(vg, nvgRGBA(150, 150, 150, 200))
    nvgText(vg, 540, 1170, "该功能尚未开放", nil)
end

--- 神器宝箱是否已解锁（抵达噩梦难度）
---@return boolean
local function isArtifactChestUnlocked()
    local battle = PlayerStore.Get("battle")
    return StageConfig.hasReachedNightmare(battle)
end

local function drawCollectionLockedContent(vg)
    drawImageCentered(vg, img.titleDeco, P1.DECO_CX, P1.DECO_CY, P1.DECO_W, P1.DECO_H, 1.0)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, COL.TITLE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(COL.TITLE_R, COL.TITLE_G, COL.TITLE_B, 255))
    nvgText(vg, COL.TITLE_CX, COL.TITLE_CY, "典藏", nil)

    drawImageCentered(vg, img.collectionChestBg, COL.CHEST_CX, COL.CHEST_CY, COL.CHEST_W, COL.CHEST_H, 0.45)
    drawTextStroke(vg, COL.NAME_X, COL.NAME_Y, "神器宝箱", COL.NAME_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        180, 180, 180, 6, { strokeColor = { 0, 0, 0 }, italic = true })

    nvgFontFace(vg, "sans"); nvgFontSize(vg, 40)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(141, 95, 65, 255))
    nvgText(vg, 540, 1320, "抵达噩梦难度后开放", nil)

    local progress = StageConfig.formatProgressDisplay(
        (PlayerStore.Get("battle") or {}).maxStageId or 0)
    nvgFontSize(vg, 32)
    nvgFillColor(vg, nvgRGBA(150, 150, 150, 220))
    nvgText(vg, 540, 1380, "当前进度：" .. progress, nil)
end

local function drawRichTextCentered(vg, x, y, fontSize, strokeWidth, segments)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    local totalW = 0
    for _, seg in ipairs(segments) do
        totalW = totalW + nvgTextBounds(vg, 0, 0, seg.text)
    end
    local cursorX = x - totalW * 0.5
    for _, seg in ipairs(segments) do
        local w = nvgTextBounds(vg, 0, 0, seg.text)
        local c = seg.color or { 255, 255, 255 }
        drawTextStroke(vg, cursorX, y, seg.text, fontSize,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            c[1], c[2], c[3], strokeWidth, { strokeColor = { 0, 0, 0 }, italic = seg.italic == true })
        cursorX = cursorX + w
    end
end

local function drawPityText(vg, x, y, leftCount, qualityText, qualityColor)
    drawRichTextCentered(vg, x, y, COL.PITY_FONT, 4, {
        { text = tostring(leftCount), color = { 0xff, 0xe8, 0x28 } },
        { text = "次内必得", color = { 255, 255, 255 } },
        { text = qualityText, color = qualityColor },
        { text = "神器", color = { 255, 255, 255 } },
    })
end

local function getCollectionPityLeft()
    local artifacts = PlayerStore.Get("artifacts") or {}
    local rareCount = tonumber(artifacts.pityRare) or 0
    local epicCount = tonumber(artifacts.pityEpic) or 0
    local rareLeft = ArtifactDefs.PITY_RARE - rareCount
    local epicLeft = ArtifactDefs.PITY_EPIC - epicCount
    return math.max(1, rareLeft), math.max(1, epicLeft)
end

local function getKeyCost(count)
    if count == 1 and hasArtifactFreeDraw() then return 0 end
    return ArtifactDefs.DRAW_KEY_COST[count] or count
end

local function sendArtifactDraw(count)
    if not sendAction_ then return false end
    local payType = (count == 1 and hasArtifactFreeDraw()) and "free_daily" or "diamond"
    sendAction_(Protocol.ACTION_TYPES.ARTIFACT_DRAW, { count = count, payType = payType })
    return true
end

local function openKeyConfirm(count, needKeys, diamondCost)
    state.keyConfirmVisible = true
    state.keyConfirmClosing = false
    state.keyConfirmCount = count
    state.keyConfirmNeedKeys = needKeys
    state.keyConfirmDiamondCost = diamondCost
    state.keyConfirmAnimTime = time.elapsedTime
end

local function closeKeyConfirm()
    if not state.keyConfirmVisible then return end
    state.keyConfirmClosing = true
    state.keyConfirmCloseTime = time.elapsedTime
end

local function getKeyConfirmAnim()
    if state.keyConfirmClosing then
        local t = math.min((time.elapsedTime - state.keyConfirmCloseTime) / POPUP_CLOSE_DUR, 1.0)
        if t >= 1.0 then
            state.keyConfirmVisible = false
            state.keyConfirmClosing = false
            return POPUP_SCALE_FROM, 0
        end
        local scale = POPUP_SCALE_TO + (POPUP_SCALE_FROM - POPUP_SCALE_TO) * easeInCubic(t)
        return scale, 1.0 - t
    end
    local t = math.min((time.elapsedTime - state.keyConfirmAnimTime) / POPUP_OPEN_DUR, 1.0)
    local scale = POPUP_SCALE_FROM + (POPUP_SCALE_TO - POPUP_SCALE_FROM) * easeOutCubic(t)
    return scale, t
end

--- 检查黄金钥匙是否足够；不足则弹出钻石快速购买确认框
---@param count number 1 或 10
---@return boolean canProceed
local function checkKeyAndDraw(count)
    local keyCost = getKeyCost(count)
    local keys = GameState.getGoldenKey()
    if keyCost <= 0 or keys >= keyCost then
        if sendArtifactDraw(count) then
            state.floatText = "正在开启宝箱"
            state.floatTextX = count == 10 and COL.BTN_TEN_X or COL.BTN_ONE_X
            state.floatTextY = COL.BTN_Y - 120
            state.floatTextTime = time.elapsedTime
        else
            state.floatText = "网络未连接"
            state.floatTextX = 540
            state.floatTextY = COL.BTN_Y - 120
            state.floatTextTime = time.elapsedTime
        end
        return true
    end

    local shortfall = keyCost - keys
    local diamondCost = shortfall * ArtifactDefs.KEY_DIAMOND_PRICE
    openKeyConfirm(count, shortfall, diamondCost)
    print(string.format("[MarketPage] 黄金钥匙不足: 需%d 有%d 补购%d把 花费%d钻",
        keyCost, keys, shortfall, diamondCost))
    return false
end

local function drawCollectionDrawButton(vg, id, cx, countText, keyCost)
    local bf = BF.begin(vg, id, cx, COL.BTN_Y, COL.BTN_W, COL.BTN_H)
    drawImageCentered(vg, img.collectionDrawBtn, cx, COL.BTN_Y, COL.BTN_W, COL.BTN_H, 1.0)
    drawTextStroke(vg, cx, COL.BTN_TEXT_Y, countText, COL.BTN_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4, { strokeColor = { 0, 0, 0 } })

    local costStr = keyCost <= 0 and "免费" or ("x" .. tostring(keyCost))
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, COL.COST_FONT)
    local costTextW = nvgTextBounds(vg, 0, 0, costStr)
    local gap = 8
    local totalW = COL.COST_ICON_SIZE + gap + costTextW
    local iconX = cx - totalW * 0.5 + COL.COST_ICON_SIZE * 0.5
    local textX = iconX + COL.COST_ICON_SIZE * 0.5 + gap
    local keyIcon = img.goldenKey >= 0 and img.goldenKey or img.gem
    drawImageCentered(vg, keyIcon, iconX, COL.COST_ICON_Y, COL.COST_ICON_SIZE, COL.COST_ICON_SIZE, 1.0)
    drawTextStroke(vg, textX, COL.COST_TEXT_Y, costStr, COL.COST_FONT,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4, { strokeColor = { 0, 0, 0 } })
    BF.finish(vg, bf)
end

local function drawKeyConfirmDialog(vg)
    if not state.keyConfirmVisible then return end

    local pScale, pAlpha = getKeyConfirmAnim()
    if pAlpha <= 0.01 then return end

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(KEY_CF.MASK_A * pAlpha)))
    nvgFill(vg)

    nvgSave(vg)
    nvgTranslate(vg, KEY_CF.CX, KEY_CF.CY)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -KEY_CF.CX, -KEY_CF.CY)
    nvgGlobalAlpha(vg, pAlpha)

    DarkIcon.drawNine(vg, "panel", KEY_CF.CX - KEY_CF.W * 0.5, KEY_CF.CY - KEY_CF.H * 0.5, KEY_CF.W, KEY_CF.H, { titleH = 150 })

    drawTextStroke(vg, KEY_CF.TITLE_CX, KEY_CF.TITLE_CY, "黄金钥匙不足",
        KEY_CF.TITLE_SIZE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, KEY_CF.TITLE_STROKE_W, { strokeColor = { 0x59, 0x32, 0x19 } })

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, KEY_CF.SUB_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(KEY_CF.SUB_R, KEY_CF.SUB_G, KEY_CF.SUB_B, 255))
    nvgText(vg, KEY_CF.SUB_CX, KEY_CF.SUB_CY, "是否使用钻石快速购买", nil)

    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        KEY_CF.CONTENT_CX - KEY_CF.CONTENT_W * 0.5,
        KEY_CF.CONTENT_CY - KEY_CF.CONTENT_H * 0.5,
        KEY_CF.CONTENT_W, KEY_CF.CONTENT_H, KEY_CF.CONTENT_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, KEY_CF.CONTENT_A))
    nvgFill(vg)

    drawImageCentered(vg, img.confirmArrow, KEY_CF.ARROW_CX, KEY_CF.ARROW_CY, KEY_CF.ARROW_W, KEY_CF.ARROW_H, 1.0)
    DarkIcon.drawQualityBg(vg, 6, KEY_CF.DIAMOND_CX, KEY_CF.DIAMOND_CY, KEY_CF.DIAMOND_W, KEY_CF.DIAMOND_H, 1.0)  -- [暗黑化 P2-A]
    drawImageCentered(vg, img.diamondBig, KEY_CF.DIAMOND_CX, KEY_CF.DIAMOND_CY, KEY_CF.DIAMOND_W, KEY_CF.DIAMOND_H, 1.0)
    DarkIcon.drawQualityBg(vg, 6, KEY_CF.KEY_CX, KEY_CF.KEY_CY, KEY_CF.KEY_W, KEY_CF.KEY_H, 1.0)  -- [暗黑化 P2-A]
    drawImageCentered(vg, img.goldenKey, KEY_CF.KEY_CX, KEY_CF.KEY_CY, KEY_CF.KEY_W, KEY_CF.KEY_H, 1.0)

    local diamondEnough = GameState.getGems() >= state.keyConfirmDiamondCost
    local dBadgeR, dBadgeG, dBadgeB = 255, 255, 255
    if not diamondEnough then dBadgeR, dBadgeG, dBadgeB = 255, 50, 50 end
    drawTextStroke(vg,
        KEY_CF.DIAMOND_CX + KEY_CF.BADGE_OX, KEY_CF.DIAMOND_CY + KEY_CF.BADGE_OY,
        tostring(state.keyConfirmDiamondCost),
        KEY_CF.BADGE_SIZE, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        dBadgeR, dBadgeG, dBadgeB, KEY_CF.BADGE_STROKE_W, { strokeColor = { 0, 0, 0 } })
    drawTextStroke(vg,
        KEY_CF.KEY_CX + KEY_CF.BADGE_OX, KEY_CF.KEY_CY + KEY_CF.BADGE_OY,
        tostring(state.keyConfirmNeedKeys),
        KEY_CF.BADGE_SIZE, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        255, 255, 255, KEY_CF.BADGE_STROKE_W, { strokeColor = { 0, 0, 0 } })

    local _bfBuy = BF.begin(vg, "market_key_confirm", KEY_CF.BUY_CX, KEY_CF.BUY_CY, KEY_CF.BUY_W, KEY_CF.BUY_H)
    DarkIcon.drawNine(vg, "btn", KEY_CF.BUY_CX - KEY_CF.BUY_W * 0.5, KEY_CF.BUY_CY - KEY_CF.BUY_H * 0.5, KEY_CF.BUY_W, KEY_CF.BUY_H, { accent = "gold" })
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, KEY_CF.BUY_TEXT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(KEY_CF.BUY_TEXT_R, KEY_CF.BUY_TEXT_G, KEY_CF.BUY_TEXT_B, 255))
    nvgText(vg, KEY_CF.BUY_CX, KEY_CF.BUY_CY, "购买", nil)
    BF.finish(vg, _bfBuy)

    nvgRestore(vg)
end

local function drawCollectionContent(vg)
    if not isArtifactChestUnlocked() then
        drawCollectionLockedContent(vg)
        return
    end

    drawImageCentered(vg, img.titleDeco, P1.DECO_CX, P1.DECO_CY, P1.DECO_W, P1.DECO_H, 1.0)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, COL.TITLE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(COL.TITLE_R, COL.TITLE_G, COL.TITLE_B, 255))
    nvgText(vg, COL.TITLE_CX, COL.TITLE_CY, "典藏", nil)

    drawImageCentered(vg, img.collectionChestBg, COL.CHEST_CX, COL.CHEST_CY, COL.CHEST_W, COL.CHEST_H, 1.0)

    drawTextStroke(vg, COL.NAME_X, COL.NAME_Y, "神器宝箱", COL.NAME_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 6, { strokeColor = { 0, 0, 0 }, italic = true })

    drawRichTextCentered(vg, COL.DESC_X, COL.DESC_Y - 18, COL.DESC_FONT, 4, {
        { text = "获得100金币，赠送", color = { 255, 255, 255 } },
        { text = "普通", color = QUALITY_COLORS.normal },
        { text = "、", color = { 255, 255, 255 } },
        { text = "优质", color = QUALITY_COLORS.good },
        { text = "、", color = { 255, 255, 255 } },
    })
    drawRichTextCentered(vg, COL.DESC_X, COL.DESC_Y + 18, COL.DESC_FONT, 4, {
        { text = "稀有", color = QUALITY_COLORS.rare },
        { text = "、", color = { 255, 255, 255 } },
        { text = "史诗", color = QUALITY_COLORS.epic },
        { text = "品质神器", color = { 255, 255, 255 } },
    })

    local rareLeft, epicLeft = getCollectionPityLeft()

    nvgBeginPath(vg)
    nvgRoundedRect(vg, COL.RARE_PITY_X - COL.PITY_W * 0.5, COL.RARE_PITY_Y - COL.PITY_H * 0.5,
        COL.PITY_W, COL.PITY_H, COL.PITY_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, COL.PITY_A)); nvgFill(vg)
    drawPityText(vg, COL.RARE_PITY_X, COL.RARE_PITY_Y, rareLeft, "稀有", QUALITY_COLORS.rare)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, COL.EPIC_PITY_X - COL.PITY_W * 0.5, COL.EPIC_PITY_Y - COL.PITY_H * 0.5,
        COL.PITY_W, COL.PITY_H, COL.PITY_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, COL.PITY_A)); nvgFill(vg)
    drawPityText(vg, COL.EPIC_PITY_X, COL.EPIC_PITY_Y, epicLeft, "史诗", QUALITY_COLORS.epic)

    local oneCost = getKeyCost(1)
    local oneText = oneCost <= 0 and "免费单抽" or "抽1次"
    drawCollectionDrawButton(vg, "collection_draw_1", COL.BTN_ONE_X, oneText, oneCost)
    drawCollectionDrawButton(vg, "collection_draw_10", COL.BTN_TEN_X, "抽10次", COL.TEN_KEY)
end

-- ======================== 特权奖励配置 ========================

-- 观看广告累计次数奖励梯度（来源：建筑-市场.txt 市场-特权配置表
local PRIVILEGE_REWARDS = {
    { threshold = 5,  quality = 5, icon = "image/UI_icon_ZMQ_1.png", amount = 5,    label = "冒险招募券" },
    { threshold = 10, quality = 5, icon = "image/UI_icon_SJ.png",    amount = 1000, label = "钻石" },
    { threshold = 15, quality = 5, icon = "image/UI_icon_SJ.png",    amount = 2000, label = "钻石" },
    { threshold = 20, quality = 6, icon = "image/UI_icon_HJYS.png",  amount = 10,   label = "黄金钥匙" },
    { threshold = 25, quality = 6, icon = "image/UI_icon_ZMQ_2.png", amount = 10,   label = "星辉招募券" },
    { threshold = 30, quality = 2, icon = "image/UI_icon_JC.png", amount = "大量", label = "大量精粹" },
}

-- 奖励图标预加载句柄（在 init 时填充）
local privRewardIcons = {}   -- { [i] = imgHandle }

-- 特权页布局常量
local PV = {
    -- 上方背景
    BG_CX = 540, BG_CY = 465, BG_W = 1080, BG_H = 930,
    -- 刷新时间文字（CENTER 对齐，中心 X：190/441，无描边）
    REFRESH_LABEL_CX = 190, REFRESH_LABEL_Y = 467, REFRESH_FONT = 38,
    REFRESH_TIME_CX  = 441, REFRESH_TIME_Y  = 467,
    -- 下方背景框（九宫格）
    LOWER_CX = 540, LOWER_CY = 1547, LOWER_W = 1080, LOWER_H = 1706,
    LOWER_IT = 200, LOWER_IR = 150,  LOWER_IB = 10,   LOWER_IL = 150,
    -- 黑色半透明条（进度条左侧装饰）
    STRIP_CX = 195, STRIP_CY = 1480, STRIP_W = 140, STRIP_H = 1068, STRIP_R = 30,
    -- 进度条背景
    PROG_BG_CX = 195, PROG_BG_CY = 1528, PROG_BG_W = 30, PROG_BG_H = 938,
    -- 进度条内边距
    PROG_PAD = 5,
    -- 奖励行第一行基准 Y（相对原始设计坐标）
    ROW_FIRST_Y = 1046,
    ROW_STEP    = 48 + 220,  -- 间距48 + 行高220
    ROW_MAX_Y   = 1993,      -- 截断 Y（绝对设计坐标）
    -- 进度条
    DOT_X = 195, DOT_W = 70, DOT_H = 70,
    -- 奖励背景（规格书 Y1051，进度点 Y1046，差值 +5）
    REWARD_BG_CX = 610, REWARD_BG_W = 637, REWARD_BG_H = 220, REWARD_BG_OY = 5,
    -- 进度需求背景（左侧文字区）
    REQ_BG_CX = 485, REQ_BG_W = 209, REQ_BG_H = 142, REQ_BG_R = 40,
    -- 文字偏移（相对行 CY）
    LABEL_X = 487, LABEL_OY = -24,   -- "累计观看" / "可领取 相对行中心Y 的偏移
    PROG_X  = 485, PROG_OY  =  26,   -- "0/5" 偏移
    -- 品质+奖励图标
    ICON_CX = 824, ICON_W = 160, ICON_H = 160,
    -- 角标
    BADGE_OX = 56, BADGE_OY = 50,
    -- 已领取遮罩文字
    CLAIMED_TEXT_X = 613, CLAIMED_TEXT_OY = -6,
    -- ===== 下半底栏（特权点 + 观看广告按钮） =====
    -- 1. 特权点背景（纯黑10%，圆角18）
    BOT_PT_BG_CX = 245, BOT_PT_BG_CY = 2109, BOT_PT_BG_W = 256, BOT_PT_BG_H = 140, BOT_PT_BG_R = 18,
    -- 2. 特权点大图标 UI_icon_TQD
    BOT_PT_ICON_CX = 127, BOT_PT_ICON_CY = 2111, BOT_PT_ICON_W = 160, BOT_PT_ICON_H = 160,
    -- 3. 文本"特权点 居中 X264 Y2075 字号38 颜色454545
    BOT_PT_LABEL_CX = 264, BOT_PT_LABEL_Y = 2075, BOT_PT_LABEL_FONT = 38,
    -- 4. 特权点数值 左对齐与"特权点"相同 X，Y2136 字号54 纯白+描边232323
    BOT_PT_VAL_X = 264, BOT_PT_VAL_Y = 2136, BOT_PT_VAL_FONT = 54,
    -- 5. 观看广告按钮背景 UI_AN_DA
    BOT_AD_BTN_CX = 759, BOT_AD_BTN_CY = 2108, BOT_AD_BTN_W = 570, BOT_AD_BTN_H = 148,
    -- 6. "观看广告"文字 斜体 居中 X759 Y2083 字号50 纯白+纯黑描边5
    BOT_AD_TEXT_CX = 759, BOT_AD_TEXT_Y = 2083, BOT_AD_TEXT_FONT = 50,
    -- 7. 特权点小图标 UI_icon_TQD_X 居中 X725 Y2140 70*70
    BOT_AD_ICON_CX = 725, BOT_AD_ICON_CY = 2140, BOT_AD_ICON_W = 70, BOT_AD_ICON_H = 70,
    -- 8. "+1"文字 居中 X782 Y2140 字号40 黑色75%不透明
    BOT_AD_PLUS_CX = 782, BOT_AD_PLUS_Y = 2140, BOT_AD_PLUS_FONT = 40,
    -- 滚动量
    SCROLL_TOP_Y = 940,   -- 奖励区截断上边界
    SCROLL_BOT_Y = 1993,  -- 奖励区截断下边界
}

-- 文字宽度缓存（避免 nvgScale 下多段文本抖动，见铁律 #15）
local _privTextWidthCache = {}
local function getCachedTextWidth(vg, text, fontSize)
    local key = text .. "\0" .. tostring(fontSize)
    local w = _privTextWidthCache[key]
    if not w then
        w = nvgTextBounds(vg, 0, 0, text)
        _privTextWidthCache[key] = w
    end
    return w
end

-- ======================== 特权页绘制（内部内容，在 lowerOY translate 内） ========================

local function drawPrivilegeContent(vg)
    -- 注意：此函数在 nvgTranslate(0, lowerOY) 内执行
    -- 刷新时间文字位于上方 Banner，由 draw() 上半部分条件块统一绘制，此处不绘制。

    -- 黑色装饰条（固定不动，5% 不透明度）
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        PV.STRIP_CX - PV.STRIP_W * 0.5, PV.STRIP_CY - PV.STRIP_H * 0.5,
        PV.STRIP_W, PV.STRIP_H, PV.STRIP_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))   -- 5% 黑13/255
    nvgFill(vg)

    -- ===== 奖励行 + 进度条背景 + 进度条填充 + 进度点（随滚动移动） =====
    local totalRows = #PRIVILEGE_REWARDS
    local totalH = totalRows * (PV.REWARD_BG_H + 48) - 48
    local maxScroll = math.max(0, (PV.ROW_FIRST_Y + totalH) - PV.ROW_MAX_Y)
    state.privScrollY = math.max(0, math.min(state.privScrollY, maxScroll))

    nvgSave(vg)
    nvgIntersectScissor(vg, 0, PV.SCROLL_TOP_Y, DESIGN_W, PV.SCROLL_BOT_Y - PV.SCROLL_TOP_Y)
    nvgTranslate(vg, 0, -state.privScrollY)

    -- 进度条背景/填充的高度动态计算：从第一个奖励点到最后一个奖励点
    local firstDotY  = PV.ROW_FIRST_Y
    local lastDotY   = PV.ROW_FIRST_Y + (totalRows - 1) * (PV.REWARD_BG_H + 48)
    local dynProgCY  = (firstDotY + lastDotY) * 0.5   -- 背景中心 Y
    local dynProgH   = lastDotY - firstDotY            -- 背景高度（首末点间距）

    -- 进度条背景 (UI_TQ_JDY2) 随滚动移动，高度动态覆盖首到末奖励点
    drawImageCentered(vg, img.privProgBg,
        PV.PROG_BG_CX, dynProgCY, PV.PROG_BG_W, dynProgH, 1.0)

    -- 进度条填充 (UI_TQ_JDY1, 内边距5) 随滚动移动
    local progX = PV.PROG_BG_CX - PV.PROG_BG_W * 0.5 + PV.PROG_PAD
    local progW = PV.PROG_BG_W - PV.PROG_PAD * 2
    local progTop = dynProgCY - dynProgH * 0.5 + PV.PROG_PAD
    local progBotFull = dynProgCY + dynProgH * 0.5 - PV.PROG_PAD
    local progH = progBotFull - progTop

    -- 进度填充：从第一个门槛(5次)开始，从上往下增长到最后一个门槛(30次)
    local minThreshold = PRIVILEGE_REWARDS[1].threshold               -- 5
    local maxThreshold = PRIVILEGE_REWARDS[#PRIVILEGE_REWARDS].threshold -- 30
    local watchClamped = math.max(0, state.privWatchCount - minThreshold)
    local watchFrac    = math.min(1.0, watchClamped / (maxThreshold - minThreshold))
    local fillH = progH * watchFrac
    if img.privProgFill >= 0 and fillH > 1 then
        -- 从顶部往下填充
        local paint = nvgImagePattern(vg, progX, progTop, progW, progH, 0, img.privProgFill, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, progX, progTop, progW, fillH)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end

    for i, reward in ipairs(PRIVILEGE_REWARDS) do
        local rowCY = PV.ROW_FIRST_Y + (i - 1) * (PV.REWARD_BG_H + 48)
        local screenRowCY = rowCY - state.privScrollY
        -- 视口外跳过绘制
        if screenRowCY >= PV.SCROLL_TOP_Y - PV.REWARD_BG_H and screenRowCY <= PV.SCROLL_BOT_Y + PV.REWARD_BG_H then

            local isClaimed  = state.privClaimed[reward.threshold] == true
            local isClaimable = (not isClaimed) and (state.privWatchCount >= reward.threshold)

            -- 进度条
            local dotImg = (state.privWatchCount >= reward.threshold) and img.privDotActive or img.privDotInactive
            drawImageCentered(vg, dotImg,
                PV.DOT_X, rowCY, PV.DOT_W, PV.DOT_H, 1.0)

            -- 奖励背景框 (UI_TQ_3)，规格 Y1051 比进度点 Y1046 低 5px
            drawImageCentered(vg, img.privRewardBg,
                PV.REWARD_BG_CX, rowCY + PV.REWARD_BG_OY, PV.REWARD_BG_W, PV.REWARD_BG_H, 1.0)

            -- 进度需求背景（黑色10%，圆角40）
            nvgBeginPath(vg)
            nvgRoundedRect(vg,
                PV.REQ_BG_CX - PV.REQ_BG_W * 0.5, rowCY - PV.REQ_BG_H * 0.5,
                PV.REQ_BG_W, PV.REQ_BG_H, PV.REQ_BG_R)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))   -- 10% 黑26/255
            nvgFill(vg)

            -- "累计观看" / "可领取" 文字（以需求背景中心 X 居中）
            local labelText   = isClaimable and "可领取" or "累计观看"
            local labelColorR = isClaimable and 0xfa or 0xff
            local labelColorG = isClaimable and 0xff or 0xff
            local labelColorB = isClaimable and 0x7e or 0xff
            drawTextStroke(vg, PV.REQ_BG_CX, rowCY + PV.LABEL_OY, labelText,
                PV.REFRESH_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                labelColorR, labelColorG, labelColorB, 5,
                { strokeColor = { 0x31, 0x24, 0x24 } })

            -- 进度文字 "当前/阈值"（居中）
            local progText = tostring(math.min(state.privWatchCount, reward.threshold))
                .. "/" .. tostring(reward.threshold)
            drawTextStroke(vg, PV.REQ_BG_CX, rowCY + PV.PROG_OY, progText,
                PV.REFRESH_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, 5,
                { strokeColor = { 0x31, 0x24, 0x24 } })

            -- 品质背景 + 奖励图标
            DarkIcon.drawQualityBg(vg, reward.quality or 1,
                PV.ICON_CX, rowCY, PV.ICON_W, PV.ICON_H, isClaimed and 0.4 or 1.0)  -- [暗黑化 P2-A]
            local rewardIconImg = privRewardIcons[i]
            if rewardIconImg and rewardIconImg >= 0 then
                drawImageCentered(vg, rewardIconImg,
                    PV.ICON_CX, rowCY, PV.ICON_W, PV.ICON_H, isClaimed and 0.4 or 1.0)
            end

            -- 奖励数量角标（右下角，与其他地方样式一致）
            drawTextStroke(vg,
                PV.ICON_CX + PV.BADGE_OX, rowCY + PV.BADGE_OY,
                tostring(reward.amount),
                40, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                255, 255, 255, 5, { strokeColor = { 0, 0, 0 } })

            -- 已领取状态：黑色50%遮罩 + "已领取文字
            if isClaimed then
                -- 用 UI_TQ_3 图片 alpha 形状裁剪遮罩（与 TalentStarMap 同技巧）
                -- blend: dst × (1 - srcAlpha)，图片透明区不受影响，不透明区变暗50%
                nvgGlobalCompositeBlendFuncSeparate(vg,
                    NVG_ZERO, NVG_ONE_MINUS_SRC_ALPHA,
                    NVG_ZERO, NVG_ONE)
                local maskPaint = nvgImagePattern(vg,
                    PV.REWARD_BG_CX - PV.REWARD_BG_W * 0.5,
                    rowCY + PV.REWARD_BG_OY - PV.REWARD_BG_H * 0.5,
                    PV.REWARD_BG_W, PV.REWARD_BG_H, 0, img.privRewardBg, 0.5)
                nvgBeginPath(vg)
                nvgRect(vg,
                    PV.REWARD_BG_CX - PV.REWARD_BG_W * 0.5,
                    rowCY + PV.REWARD_BG_OY - PV.REWARD_BG_H * 0.5,
                    PV.REWARD_BG_W, PV.REWARD_BG_H)
                nvgFillPaint(vg, maskPaint)
                nvgFill(vg)
                nvgGlobalCompositeOperation(vg, NVG_SOURCE_OVER)  -- 恢复默认混合
                -- "已领取
                drawTextStroke(vg, PV.CLAIMED_TEXT_X, rowCY + PV.CLAIMED_TEXT_OY, "已领取",
                    48, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                    0x50, 0xff, 0x50, 6, { strokeColor = { 0, 0, 0 } })
            end

            -- 可领取状态：整行高亮边框提示（玩家点击整个奖励行即可领取，无单独按钮）
            if isClaimable then
                nvgBeginPath(vg)
                nvgRoundedRect(vg,
                    PV.REWARD_BG_CX - PV.REWARD_BG_W * 0.5 - 3,
                    rowCY + PV.REWARD_BG_OY - PV.REWARD_BG_H * 0.5 - 3,
                    PV.REWARD_BG_W + 6, PV.REWARD_BG_H + 6, 12)
                nvgStrokeColor(vg, nvgRGBA(0xfa, 0xff, 0x7e, 200))
                nvgStrokeWidth(vg, 3)
                nvgStroke(vg)
            end
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- ===== 底栏：特权点展示 + 观看广告按钮 =====

    -- 1. 特权点背景（纯黑10%，圆角18）
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        PV.BOT_PT_BG_CX - PV.BOT_PT_BG_W * 0.5, PV.BOT_PT_BG_CY - PV.BOT_PT_BG_H * 0.5,
        PV.BOT_PT_BG_W, PV.BOT_PT_BG_H, PV.BOT_PT_BG_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))   -- 10% 黑26/255
    nvgFill(vg)

    -- 2. 特权点大图标 UI_icon_TQD
    drawImageCentered(vg, img.privPointIcon,
        PV.BOT_PT_ICON_CX, PV.BOT_PT_ICON_CY, PV.BOT_PT_ICON_W, PV.BOT_PT_ICON_H, 1.0)

    -- 3. 文本"特权点（居中X264，颜色54545，无描边）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, PV.BOT_PT_LABEL_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0x45, 0x45, 0x45, 255))
    nvgText(vg, PV.BOT_PT_LABEL_CX, PV.BOT_PT_LABEL_Y, "特权点", nil)

    -- 4. 特权点数值（LEFT 对齐同 X264，Y2136，字号54，纯白+描边232323）
    local ptVal = tostring(GameState.getPrivilegePoint())
    drawTextStroke(vg, PV.BOT_PT_VAL_X, PV.BOT_PT_VAL_Y, ptVal,
        PV.BOT_PT_VAL_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 5, { strokeColor = { 0x23, 0x23, 0x23 } })

    -- 5+6+7+8. 观看广告按钮（带点击反馈）
    local adSc = BF.begin(vg, "priv_watch_ad", PV.BOT_AD_BTN_CX, PV.BOT_AD_BTN_CY,
        PV.BOT_AD_BTN_W, PV.BOT_AD_BTN_H)

    -- 5. 按钮背景 UI_AN_DA
    drawImageCentered(vg, img.privAdBtn,
        PV.BOT_AD_BTN_CX, PV.BOT_AD_BTN_CY, PV.BOT_AD_BTN_W, PV.BOT_AD_BTN_H, 1.0)

    if state.privAdWatching then
        -- 6. 加载中：文字"加载中..."（斜体，居中，字号50，半透明脉冲）
        local pulse = math.abs(math.sin(time.elapsedTime * 3.0))  -- 呼吸闪烁
        local loadAlpha = math.floor(140 + 115 * pulse)
        drawTextStroke(vg, PV.BOT_AD_TEXT_CX, PV.BOT_AD_TEXT_Y, "加载中..",
            PV.BOT_AD_TEXT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 5, { strokeColor = { 0, 0, 0 }, italic = true, alpha = loadAlpha / 255 })
    elseif state.privAdCooldownUntil > 0 and time.elapsedTime < state.privAdCooldownUntil then
        -- 6. 冷却中：显示倒计时秒数
        local cdRemain = math.ceil(state.privAdCooldownUntil - time.elapsedTime)
        local cdText = string.format("冷却 %ds", cdRemain)
        drawTextStroke(vg, PV.BOT_AD_TEXT_CX, PV.BOT_AD_TEXT_Y, cdText,
            PV.BOT_AD_TEXT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            200, 200, 200, 5, { strokeColor = { 0, 0, 0 }, italic = true })
    else
        -- 6. 正常：文字"观看广告"（斜体，居中 X759 Y2083，字号50，纯白+纯黑描边5）
        drawTextStroke(vg, PV.BOT_AD_TEXT_CX, PV.BOT_AD_TEXT_Y, "观看广告",
            PV.BOT_AD_TEXT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 5, { strokeColor = { 0, 0, 0 }, italic = true })

        -- 7. 特权点小图标 UI_icon_TQD_X
        drawImageCentered(vg, img.privilege,
            PV.BOT_AD_ICON_CX, PV.BOT_AD_ICON_CY, PV.BOT_AD_ICON_W, PV.BOT_AD_ICON_H, 1.0)

        -- 8. "+N"文字（居中 X782 Y2140，字号40，纯黑75%）
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, PV.BOT_AD_PLUS_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))   -- 75% 黑191/255
        nvgText(vg, PV.BOT_AD_PLUS_CX, PV.BOT_AD_PLUS_Y,
            "+" .. tostring(getPrivilegeAdRewardPoints()), nil)
    end

    BF.finish(vg, adSc)
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

local TAB_DRAW = { collection = drawCollectionContent, privilege = drawPrivilegeContent, items = drawItemsContent }

-- ======================== 特权数据同步 API ========================

--- 接收服务端推送的 privilege 模块数据
function MarketPage.setPrivilegeData(data)
    if not data then return end
    if data.watchCount ~= nil then
        state.privWatchCount = data.watchCount
    end
    -- 刷新时间：转为总秒数并记录同步时刻，用于实时倒计时
    if data.refreshHour ~= nil or data.refreshMin ~= nil then
        local h = data.refreshHour or state.privRefreshHour
        local m = data.refreshMin  or state.privRefreshMin
        state.privRefreshHour       = h
        state.privRefreshMin        = m
        state.privRefreshTotalSecs  = h * 3600 + m * 60
        state.privRefreshSyncTime   = time.elapsedTime
    end
    if data.claimed then
        state.privClaimed = {}
        for _, th in ipairs(data.claimed) do
            state.privClaimed[th] = true
        end
    end
    print("[MarketPage] privilege data synced, watchCount=" .. tostring(state.privWatchCount))
end

--- 断线时释放广告观看锁，避免重连后按钮永久不可点
function MarketPage.onServerDisconnect()
    if state.privAdWatching then
        print("[MarketPage] onServerDisconnect: clearing privAdWatching lock")
    end
    state.privAdWatching = false
end

--- 是否需要在市场建筑标签显示红点
--- 条件：有特权点 AND 至少一件特权商品未售罄（可购买）
--- 注意：getCooldownRemaining 不能作为条件——冷却期内仍可购买剩余次数；
---       isSoldOut 内部的 getPurchased 已处理"冷却到期→自动归零视为补货"逻辑
function MarketPage.hasPrivilegeRedDot()
    local pts = GameState.getPrivilegePoint()
    if pts <= 0 then return false end
    for _, item in ipairs(SHOP_ITEMS) do
        if item.currency == "privilege" then
            if not isSoldOut(item) then
                return true
            end
        end
    end
    return false
end

-- ======================== Public API ========================

function MarketPage.init(vg)
    img.bg       = nvgCreateImage(vg, "image/UI_SCBJ.png", 0)
    img.nameBg   = nvgCreateImage(vg, "image/UI_TJP_MC.png", 0)
    img.lowerBg  = nvgCreateImage(vg, "image/UI_TJP_1.png", 0)
    img.titleDeco = nvgCreateImage(vg, "image/UI_JJC_BTBJ.png", 0)
    img.gold     = nvgCreateImage(vg, "image/UI_icon_JB_X.png", 0)
    img.gem      = nvgCreateImage(vg, "image/UI_icon_SJ_X.png", 0)
    img.privilege = nvgCreateImage(vg, "image/UI_icon_TQD_X.png", 0)

    img.btnBack  = nvgCreateImage(vg, "image/UI_AN_FH.png", 0)
    img.tabBg    = nvgCreateImage(vg, "image/UI_AN_1.png", 0)
    img.slider   = nvgCreateImage(vg, "image/UI_AN_2.png", 0)

    -- 商品卡片
    for i = 1, 6 do
        img.cardBg[i] = nvgCreateImage(vg, "image/UI_SDICONBJ_" .. i .. ".png", 0)
    end
    img.buyBtn = nvgCreateImage(vg, "image/UI_SD_AN.png", 0)
    for idx, item in ipairs(SHOP_ITEMS) do
        img.itemIcons[idx] = nvgCreateImage(vg, item.icon, 0)
        img.costIcons[idx] = nvgCreateImage(vg, item.costIcon, 0)
    end

    -- 弹窗
    img.dialogBg = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    img.buyBtnYellow = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    img.btnMinus = nvgCreateImage(vg, "image/UI_AN_JIAN.png", 0)
    img.btnPlus = nvgCreateImage(vg, "image/UI_AN_JIA.png", 0)
    -- [暗黑化 P1-B5] 原 image/UI_SD_AN.png 贴图加载已移除（矢量绘制替代）
    img.diamondIcon = nvgCreateImage(vg, "image/UI_icon_SJ_X.png", 0)
    img.privilegeIcon = nvgCreateImage(vg, "image/UI_icon_TQD_X.png", 0)
    for i = 1, 6 do
    -- [暗黑化 P2-A] 原 ZBBJ 贴图加载已移除（矢量品质框替代）
    end

    -- 特权图片
    -- [暗黑化 P1-B5] 原 image/UI_AN_HUANG.png 贴图加载已移除（矢量绘制替代）
    img.privProgBg      = nvgCreateImage(vg, "image/UI_TQ_JDY2.png", 0)
    img.privProgFill    = nvgCreateImage(vg, "image/UI_TQ_JDY1.png", 0)
    img.privDotActive   = nvgCreateImage(vg, "image/UI_TQ_1.png", 0)
    img.privDotInactive = nvgCreateImage(vg, "image/UI_TQ_2.png", 0)
    img.privRewardBg    = nvgCreateImage(vg, "image/UI_TQ_3.png", 0)
    img.privClaimBtn    = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    img.privPointIcon   = nvgCreateImage(vg, "image/UI_icon_TQD.png", 0)   -- 特权点大图标
    img.privAdBtn       = nvgCreateImage(vg, "image/UI_AN_DA.png", 0)      -- 观看广告按钮背景
    img.collectionChestBg = nvgCreateImage(vg, "image/UI_SCDC_KC1.png", 0)
    img.collectionDrawBtn = nvgCreateImage(vg, "image/UI_SCDC_AN.png", 0)
    img.goldenKey = nvgCreateImage(vg, "image/UI_icon_HJYS.png", 0)
    img.diamondBig = nvgCreateImage(vg, "image/UI_icon_SJ.png", 0)
    img.confirmArrow = nvgCreateImage(vg, "image/UI_TJP_JIANTOU.png", 0)
    for i, reward in ipairs(PRIVILEGE_REWARDS) do
        privRewardIcons[i] = nvgCreateImage(vg, reward.icon, 0)
    end

    state.purchased = {}
    state.scrollY = 0
    state.privScrollY = 0
    state.privClaimed = {}
    state.privWatchCount = 0
    state.dialogOpen = false
    state.dialogItemIdx = nil

    print("[MarketPage] init OK, items=" .. #SHOP_ITEMS)
end

function MarketPage.open()
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
    state.privScrollY = 0
    state.privDragging = false
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

-- [已移除] AD_CONFIRM_TIMEOUT / AD_CONFIRM_MAX_RETRIES：现用AdManager + AdHandler 统一处理

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
    -- [已移除] UI层广告超时：由 AdManager 三重超时保护统一处理
end

-- ======================== 主绘制========================

function MarketPage.draw(vg)
    if not state.open then return end

    local rawT, progress, lowerProgress

    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        rawT = math.min(1.0, elapsed / CLOSE_DUR)
        progress = 1 - easeInCubic(rawT)
        lowerProgress = progress
        if rawT >= 1.0 then
            state.open = false; state.closing = false; return
        end
    else
        local elapsed = time.elapsedTime - state.openTime
        rawT = math.min(1.0, elapsed / ANIM_DUR)
        progress = easeOutCubic(rawT)
        lowerProgress = progress
    end

    local upperOY = -UPPER_DIST * (1 - progress)
    local lowerOY =  LOWER_DIST * (1 - lowerProgress)
    local overlayAlpha = math.floor(180 * progress)

    -- Tab 切换进度
    local tabT = 1.0
    if state.tabSwitchTime > 0 then
        tabT = math.min(1.0, (time.elapsedTime - state.tabSwitchTime) / TAB.ANIM_DUR)
    end
    local tabEased = easeInOutCubic(tabT)
    local tabIdx = TAB.MAP[state.tab] or 3
    local fromIdx = TAB.MAP[state.tabFrom] or tabIdx
    local isAnimating = (tabT < 1.0 and tabIdx ~= fromIdx)

    -- 全屏遮罩
    nvgBeginPath(vg); nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha)); nvgFill(vg)

    -- ========== 上半部分（从上方滑入） ==========
    nvgSave(vg)
    nvgTranslate(vg, 0, upperOY)

    -- 状态初始化（绘制分离，仅在实际切换到特权tab 时执行一次）
    if state.tab == "privilege" and state.privRefreshSyncTime == 0 then
        -- 与服务端 getDayId 一致：UTC+8 午夜 0:00 切日（非中午 12 点）
        local secsOfDay = (os.time() + 28800) % 86400
        state.privRefreshTotalSecs = 86400 - secsOfDay
        state.privRefreshSyncTime  = time.elapsedTime
    end

    -- 资源栏数据（切换动画时两侧都可能绘制，提前计算一次）
    local resGroups = {
        { bgCX = P1.R0_BG_CX, bgCY = P1.R0_BG_CY, iCX = P1.R0_ICON_CX, iCY = P1.R0_ICON_CY,
          iW = P1.R0_ICON_W, iH = P1.R0_ICON_H, tX = P1.R0_TX, tY = P1.R0_TY,
          icon = img.privilege, val = formatNumber(GameState.getPrivilegePoint()) },
        { bgCX = P1.R1_BG_CX, bgCY = P1.R1_BG_CY, iCX = P1.R1_ICON_CX, iCY = P1.R1_ICON_CY,
          iW = P1.R1_ICON_W, iH = P1.R1_ICON_H, tX = P1.R1_TX, tY = P1.R1_TY,
          icon = img.gold, val = formatNumber(GameState.getGold()) },
        { bgCX = P1.R2_BG_CX, bgCY = P1.R2_BG_CY, iCX = P1.R2_ICON_CX, iCY = P1.R2_ICON_CY,
          iW = P1.R2_ICON_W, iH = P1.R2_ICON_H, tX = P1.R2_TX, tY = P1.R2_TY,
          icon = img.gem, val = formatNumber(GameState.getGems()) },
    }

    -- 绘制指定 tab 的上半部分可变内容（背景图 + 资源栏/刷新时间）
    local function drawUpperVariant(tabKey)
        -- 背景图（特权 tab 专属上方背景，其余用标准背景图
        -- 使用 nvgIntersectScissor 而非 nvgScissor，以保留外层动画裁剪区域，防止内容溢出屏幕
        nvgSave(vg); nvgIntersectScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        if tabKey == "privilege" then
            drawImageCentered(vg, img.privBg, PV.BG_CX, PV.BG_CY, PV.BG_W, PV.BG_H, 1.0)
        else
            drawImageCentered(vg, img.bg, P1.BG_CX, P1.BG_CY, P1.BG_W, P1.BG_H, 1.0)
        end
        nvgRestore(vg)
        -- 特权 tab：刷新时间文字
        if tabKey == "privilege" and state.privRefreshSyncTime > 0 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, PV.REFRESH_FONT)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0xff, 0xfa, 0x7b, 255))
            nvgText(vg, PV.REFRESH_LABEL_CX, PV.REFRESH_LABEL_Y, "刷新时间", nil)
            nvgFillColor(vg, nvgRGBA(0x9d, 0x50, 0x2a, 255))
            local remaining = math.max(0, state.privRefreshTotalSecs - (time.elapsedTime - state.privRefreshSyncTime))
            local remH = math.floor(remaining / 3600)
            local remM = math.floor((remaining % 3600) / 60)
            nvgText(vg, PV.REFRESH_TIME_CX, PV.REFRESH_TIME_Y, string.format("%d:%02d", remH, remM), nil)
        end
        -- 资源栏（非特权 tab）
        if tabKey ~= "privilege" then
            for _, r in ipairs(resGroups) do
                nvgBeginPath(vg)
                nvgRoundedRect(vg, r.bgCX - P1.RES_BG_W * 0.5, r.bgCY - P1.RES_BG_H * 0.5,
                    P1.RES_BG_W, P1.RES_BG_H, P1.RES_BG_R)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, P1.RES_BG_A)); nvgFill(vg)
                drawImageCentered(vg, r.icon, r.iCX, r.iCY, r.iW, r.iH, 1.0)
                drawTextStroke(vg, r.tX, r.tY, r.val,
                    P1.RES_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    255, 255, 255, P1.RES_SW,
                    { strokeColor = { P1.RES_SR, P1.RES_SG, P1.RES_SB } })
            end
        end
    end

    -- tab 切换时上半部分也参与水平平移（与下方内容区同方向、同进度条
    if isAnimating then
        local dir = (tabIdx > fromIdx) and 1 or -1
        local newOX = DESIGN_W * dir * (1 - tabEased)
        local oldOX = -DESIGN_W * dir * tabEased
        nvgSave(vg); nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgSave(vg); nvgTranslate(vg, oldOX, 0); drawUpperVariant(state.tabFrom); nvgRestore(vg)
        nvgSave(vg); nvgTranslate(vg, newOX, 0); drawUpperVariant(state.tab);     nvgRestore(vg)
        nvgResetScissor(vg); nvgRestore(vg)
    else
        drawUpperVariant(state.tab)
    end

    -- 名称背景 + 文字（固定，不参与水平滑动）
    drawImageCentered(vg, img.nameBg, P1.NAME_BG_CX, P1.NAME_BG_CY, P1.NAME_BG_W, P1.NAME_BG_H, 1.0)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, P1.NAME_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, P1.NAME_TEXT_CX, P1.NAME_TEXT_CY, "市场", nil)

    nvgRestore(vg)  -- 上半部分 end

    -- ========== 下半部分（从下方滑入） ==========
    nvgSave(vg)
    nvgTranslate(vg, 0, lowerOY)

    -- 下方背景框（封装为函数以支持水平滑动动画）
    local function drawLowerBg(tabKey)
        if tabKey ~= "privilege" then
            DarkIcon.drawNine(vg, "plain", P1.LOWER_CX - P1.LOWER_W * 0.5, P1.LOWER_CY - P1.LOWER_H * 0.5, P1.LOWER_W, P1.LOWER_H)
        else
            -- 特权下方背景框（九宫格 UI_TJP_1）
            DarkIcon.drawNine(vg, "plain", PV.LOWER_CX - PV.LOWER_W * 0.5, PV.LOWER_CY - PV.LOWER_H * 0.5, PV.LOWER_W, PV.LOWER_H)
        end
    end

    if isAnimating then
        local dir = (tabIdx > fromIdx) and 1 or -1
        local newOX = DESIGN_W * dir * (1 - tabEased)
        local oldOX = -DESIGN_W * dir * tabEased
        nvgSave(vg); nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgSave(vg); nvgTranslate(vg, oldOX, 0); drawLowerBg(state.tabFrom); nvgRestore(vg)
        nvgSave(vg); nvgTranslate(vg, newOX, 0); drawLowerBg(state.tab);     nvgRestore(vg)
        nvgResetScissor(vg); nvgRestore(vg)
    else
        drawLowerBg(state.tab)
    end

    -- ========== Tab 内容 ==========
    local contentClipTop = 430
    local contentClipBot = math.min(DESIGN_H - lowerOY, 2300)
    -- isAnimating 已在函数顶部计算，此处直接复用

    if isAnimating then
        local dir = (tabIdx > fromIdx) and 1 or -1
        local newOX = DESIGN_W * dir * (1 - tabEased)
        local oldOX = -DESIGN_W * dir * tabEased

        nvgSave(vg); nvgScissor(vg, 0, contentClipTop, DESIGN_W, contentClipBot - contentClipTop)

        nvgSave(vg); nvgTranslate(vg, oldOX, 0)
        local oldFn = TAB_DRAW[state.tabFrom]
        if oldFn then oldFn(vg) end
        nvgRestore(vg)

        nvgSave(vg); nvgTranslate(vg, newOX, 0)
        local newFn = TAB_DRAW[state.tab]
        if newFn then newFn(vg) end
        nvgRestore(vg)

        nvgResetScissor(vg); nvgRestore(vg)
    else
        nvgSave(vg); nvgScissor(vg, 0, contentClipTop, DESIGN_W, contentClipBot - contentClipTop)
        local fn = TAB_DRAW[state.tab]
        if fn then fn(vg) end
        nvgResetScissor(vg); nvgRestore(vg)
    end

    -- ========== 返回按钮 & Tab 栏==========
    local _sb = BF.begin(vg, "market_back", TAB.BACK_CX, TAB.BACK_CY, TAB.BACK_W, TAB.BACK_H)
    drawImageCentered(vg, img.btnBack, TAB.BACK_CX, TAB.BACK_CY, TAB.BACK_W, TAB.BACK_H, 1.0)
    BF.finish(vg, _sb)
    drawImageCentered(vg, img.tabBg, TAB.BG_CX, TAB.BG_CY, TAB.BG_W, TAB.BG_H, 1.0)

    -- 滑块动画
    local targetItem = TAB.ITEMS[tabIdx]
    local fromItem = TAB.ITEMS[fromIdx]
    local sliderCX = fromItem.cx + (targetItem.cx - fromItem.cx) * tabEased
    local sliderCY = fromItem.cy + (targetItem.cy - fromItem.cy) * tabEased
    DarkIcon.drawNine(vg, "btn", sliderCX - TAB.SLIDER_W * 0.5, sliderCY - TAB.SLIDER_H * 0.5, TAB.SLIDER_W, TAB.SLIDER_H, { accent = "gold" })

    -- Tab 文字 + 特权 tab 红点角标
    for i, item in ipairs(TAB.ITEMS) do
        local isActive = (state.tab == TAB.KEYS[i])
        nvgFontFace(vg, "sans"); nvgFontSize(vg, TAB.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(TAB.ACT_R, TAB.ACT_G, TAB.ACT_B, 255))
        else
            nvgFillColor(vg, nvgRGBA(TAB.INA_R, TAB.INA_G, TAB.INA_B, 255))
        end
        nvgText(vg, item.cx, TAB.TEXT_Y, item.name, nil)

        -- 道具 tab（index 1）：有特权点且有可购买特权商品时显示红点角标
        if i == 1 and MarketPage.hasPrivilegeRedDot() then
            local textHalfW = getCachedTextWidth(vg, item.name, TAB.FONT) * 0.5
            local rdSz = 30
            local rdX  = item.cx + textHalfW + 10
            local rdY  = TAB.TEXT_Y - 18
            DarkIcon.draw(vg, "reddot", rdX, rdY, rdSz, 1.0)end
    end

    -- 弹窗（在裁剪区域外绘制，遮罩覆盖全屏）
    drawPurchaseDialog(vg)
    drawKeyConfirmDialog(vg)

    nvgRestore(vg)  -- 下半部分 end

    -- 浮动提示（在所有变换之外渲染，确保坐标正确）
    if state.floatText then
        local FLOAT_DURATION = 1.5
        local FLOAT_DIST     = 100
        local elapsed = time.elapsedTime - state.floatTextTime
        if elapsed >= FLOAT_DURATION then
            state.floatText = nil
        else
            local t       = elapsed / FLOAT_DURATION
            local offsetY = -FLOAT_DIST * t
            drawTextStroke(vg, state.floatTextX, state.floatTextY + offsetY,
                state.floatText,
                40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 80, 80, 6,
                { alpha = 1.0 - t })
        end
    end
end

-- ======================== 输入处理 ========================

function MarketPage.handleInput(dx, dy)
    if not state.open or state.closing then return false end

    -- 黄金钥匙快速购买确认框
    if state.keyConfirmVisible then
        if state.keyConfirmClosing then return true end
        if time.elapsedTime - state.keyConfirmAnimTime < 0.05 then return true end

        if hitTest(dx, dy, KEY_CF.BUY_CX, KEY_CF.BUY_CY, KEY_CF.BUY_W, KEY_CF.BUY_H) then
            BF.trigger("market_key_confirm")
            if GameState.getGems() < state.keyConfirmDiamondCost then
                state.floatText = "钻石不足"
                state.floatTextX = KEY_CF.BUY_CX
                state.floatTextY = KEY_CF.BUY_CY - 80
                state.floatTextTime = time.elapsedTime
                return true
            end
            local drawCount = state.keyConfirmCount
            closeKeyConfirm()
            sendArtifactDraw(drawCount)
            state.floatText = "正在开启宝箱"
            state.floatTextX = drawCount == 10 and COL.BTN_TEN_X or COL.BTN_ONE_X
            state.floatTextY = COL.BTN_Y - 120
            state.floatTextTime = time.elapsedTime
            return true
        end
        if not hitTest(dx, dy, KEY_CF.CX, KEY_CF.CY, KEY_CF.W, KEY_CF.H) then
            closeKeyConfirm()
        end
        return true
    end

    -- 弹窗优先
    if state.dialogOpen then
        if state.popupClosing then return true end

        -- 减按钮
        if hitTest(dx, dy, DLG.MINUS_CX, DLG.MINUS_CY, DLG.MINUS_W, DLG.MINUS_H) then
            BF.trigger("market_dlg_minus")
            if state.buyQuantity > 1 then
                state.buyQuantity = state.buyQuantity - 1
            end
            return true
        end

        -- 加按钮
        if hitTest(dx, dy, DLG.PLUS_CX, DLG.PLUS_CY, DLG.PLUS_W, DLG.PLUS_H) then
            BF.trigger("market_dlg_plus")
            if state.buyQuantity < state.buyMaxQuantity then
                state.buyQuantity = state.buyQuantity + 1
            end
            return true
        end

        -- 滑条点击（整个滑条区域 + 滑块溢出范围）
        local sliderHitH = math.max(DLG.SLIDER_H, DLG.KNOB_SIZE) + 20
        if hitTest(dx, dy, DLG.SLIDER_CX, DLG.SLIDER_CY, DLG.SLIDER_W + DLG.KNOB_SIZE, sliderHitH) then
            local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
            local frac = math.max(0, math.min(1, (dx - sliderL) / DLG.SLIDER_W))
            local qty = math.floor(frac * (state.buyMaxQuantity - 1) + 0.5) + 1
            state.buyQuantity = math.max(1, math.min(state.buyMaxQuantity, qty))
            state.sliderDragging = true
            return true
        end

        -- 购买按钮
        if hitTest(dx, dy, DLG.BUY_CX, DLG.BUY_CY, DLG.BUY_W, DLG.BUY_H) then
            BF.trigger("market_dlg_buy")
            local idx = state.dialogItemIdx
            local item = SHOP_ITEMS[idx]
            if item and sendAction_ then
                local actualCost = getActualPrice(item) * state.buyQuantity
                local currName = "金币"
                local balance = 0
                if item.currency == "diamond" then
                    currName = "钻石"
                    balance = GameState.getGems()
                elseif item.currency == "privilege" then
                    currName = "特权点"
                    balance = GameState.getPrivilegePoint()
                else
                    balance = GameState.getGold()
                end

                if balance < actualCost then
                    print("[MarketPage] " .. currName .. "不足: 需要" .. actualCost .. " 当前" .. balance)
                    state.floatText = currName .. "不足"
                    state.floatTextX = DLG.BUY_CX
                    state.floatTextY = DLG.BUY_CY
                    state.floatTextTime = time.elapsedTime
                    return true
                else
                    print("[MarketPage] 发送购买请求 itemId=" .. item.id .. " qty=" .. state.buyQuantity .. " (" .. item.name .. ")")
                    sendAction_(Protocol.ACTION_TYPES.MARKET_BUY, { itemId = item.id, quantity = state.buyQuantity })
                end
            end
            state.popupClosing = true
            state.popupCloseTime = time.elapsedTime
            return true
        end

        -- 同帧保护
        if time.elapsedTime - state.popupAnimTime < 0.05 then return true end

        -- 点击弹窗外部关闭
        if not hitTest(dx, dy, DLG.BG_CX, DLG.BG_CY, DLG.BG_W, DLG.BG_H) then
            state.popupClosing = true
            state.popupCloseTime = time.elapsedTime
        end
        return true
    end

    -- 广告加载中：禁用所有其他按钮（返回、Tab切换、领取奖励、购买等）
    if state.privAdWatching then
        return true
    end

    -- 返回按钮
    if hitTest(dx, dy, TAB.BACK_CX, TAB.BACK_CY, TAB.BACK_W, TAB.BACK_H) then
        BF.trigger("market_back")
        MarketPage.close(); return true
    end

    -- Tab 切换
    for i, item in ipairs(TAB.ITEMS) do
        if hitTest(dx, dy, item.cx, item.cy, TAB.SLIDER_W, TAB.SLIDER_H) then
            local newTab = TAB.KEYS[i]
            if state.tab ~= newTab then
                state.tabFrom = state.tab
                state.tabSwitchTime = time.elapsedTime
                state.tab = newTab
                require("systems.GameSFX").playUIMove(2)
                state.scrollY = 0
                state.privScrollY = 0
                print("[MarketPage] 切换到 " .. item.name)
            end
            return true
        end
    end

    -- 特权 Tab：观看广告按钮
    if state.tab == "privilege" then
        if hitTest(dx, dy, PV.BOT_AD_BTN_CX, PV.BOT_AD_BTN_CY, PV.BOT_AD_BTN_W, PV.BOT_AD_BTN_H) then
            if state.privAdWatching then
                -- 防重复点击
                return true
            end
            -- 冷却检查：看完广告后 N 秒内禁止再次点击（防止 SDK 未完全清理导致卡住）
            if state.privAdCooldownUntil > 0 and time.elapsedTime < state.privAdCooldownUntil then
                state.floatTextX    = PV.BOT_AD_BTN_CX
                state.floatTextY    = PV.BOT_AD_BTN_CY
                state.floatTextTime = time.elapsedTime
                state.floatText     = "广告冷却中，请稍后再试"
                return true
            end
            BF.trigger("priv_watch_ad")
            state.privAdWatching = true
            AdManager.ShowAdWithMute(function(result)
                state.privAdWatching = false
                -- 设置冷却，防止看完广告后立即再点导致 SDK 未清理卡死
                state.privAdCooldownUntil = time.elapsedTime + MarketSchema.AD_PRIVILEGE_CLICK_COOLDOWN_SECS
                result = result or {}
                if result.success then
                    -- AD_CONFIRM 已由 AdManager 统一发送给服务端（AdHandler 结算奖励区
                    -- 服务端结算后会推送 privilege 模块更新（watchCount +1）
                    if result.reason == "absolute_timeout_deferred" then
                        -- 长时间后台回来，连接已死，奖励将在重连后自动补发
                        print("[MarketPage] 广告完成但网络待恢复，奖励将在重连后自动发放")
                        state.floatTextX    = PV.BOT_AD_BTN_CX
                        state.floatTextY    = PV.BOT_AD_BTN_CY
                        state.floatTextTime = time.elapsedTime
                        state.floatText     = "奖励将在网络恢复后自动发送"
                    else
                        -- 正常成功：显示广告奖励弹窗
                        local adRewards = { { type = "privilege_point", amount = getPrivilegeAdRewardPoints() } }
                        RewardPopup.show("广告奖励", adRewards)
                        print("[MarketPage] 广告完成（reason=" .. tostring(result.reason) .. "），等待服务端推送")
                    end
                else
                    print("[MarketPage] 广告未完成 " .. tostring(result.reason))
                    state.floatTextX    = PV.BOT_AD_BTN_CX
                    state.floatTextY    = PV.BOT_AD_BTN_CY
                    state.floatTextTime = time.elapsedTime
                    if result.reason == "already_loading" then
                        state.floatText = "广告正在加载中"
                    else
                        state.floatText = "广告加载失败，请稍后再试"
                    end
                end
            end, "privilege")
            return true
        end
    end

    -- 特权 Tab：点击奖励行领取
    if state.tab == "privilege" then
        for i, reward in ipairs(PRIVILEGE_REWARDS) do
            local rowCY = PV.ROW_FIRST_Y + (i - 1) * (PV.REWARD_BG_H + 48) - state.privScrollY
            local isClaimed   = state.privClaimed[reward.threshold] == true
            local isClaimable = (not isClaimed) and (state.privWatchCount >= reward.threshold)
            if isClaimable then
                -- 整个奖励背景行均可点击
                if hitTest(dx, dy, PV.REWARD_BG_CX, rowCY + PV.REWARD_BG_OY, PV.REWARD_BG_W, PV.REWARD_BG_H) then
                    print("[MarketPage] 领取特权奖励 threshold=" .. reward.threshold)
                    if sendAction_ then
                        sendAction_(Protocol.ACTION_TYPES.CLAIM_PRIVILEGE_REWARD,
                            { threshold = reward.threshold })
                    end
                    return true
                end
            end
        end
    end

    -- 典藏 Tab：神器宝箱抽取按钮
    if state.tab == "collection" then
        if not isArtifactChestUnlocked() then
            return true
        end
        local drawCount, btnId, btnCX = nil, nil, nil
        if hitTest(dx, dy, COL.BTN_ONE_X, COL.BTN_Y, COL.BTN_W, COL.BTN_H) then
            drawCount, btnId, btnCX = 1, "collection_draw_1", COL.BTN_ONE_X
        elseif hitTest(dx, dy, COL.BTN_TEN_X, COL.BTN_Y, COL.BTN_W, COL.BTN_H) then
            drawCount, btnId, btnCX = 10, "collection_draw_10", COL.BTN_TEN_X
        end
        if drawCount then
            BF.trigger(btnId)
            checkKeyAndDraw(drawCount)
            return true
        end
    end

    -- 道具 Tab：商品购买按钮
    if state.tab == "items" then
        for idx, item in ipairs(SHOP_ITEMS) do
            local col = ((idx - 1) % SL.CARD_COLS)
            local row = math.floor((idx - 1) / SL.CARD_COLS)
            local cx = GRID_LEFT + col * CARD_STEP_X
            local cy = SL.GRID_TOP_CY + row * CARD_STEP_Y - state.scrollY

            local btnCY = cy + SL.BTN_OY
            if hitTest(dx, dy, cx, btnCY, SL.BTN_W, SL.BTN_H) then
                if isSoldOut(item) then
                    print("[MarketPage] 商品已售罄 " .. item.name)
                    return true
                end
                BF.trigger("market_buy_" .. idx)
                state.dialogOpen = true
                state.dialogItemIdx = idx
                state.popupAnimTime = time.elapsedTime
                state.popupClosing = false
                state.sliderDragging = false
                -- 计算最大可购买数量
                state.buyQuantity = 1
                if item.limitCount == -1 then
                    state.buyMaxQuantity = 99
                else
                    local bought = getPurchased(item.id)
                    state.buyMaxQuantity = math.max(1, item.limitCount - bought)
                end
                print("[MarketPage] 打开购买确认: " .. item.name .. " maxQty=" .. state.buyMaxQuantity)
                return true
            end
        end
    end

    return true  -- 消费事件防穿透
end

function MarketPage.handleDragBegin(dx, dy)
    if not state.open or state.closing then return false end
    if state.dialogOpen then
        if state.popupClosing then return true end
        -- 滑条拖拽开始
        local sliderHitH = math.max(DLG.SLIDER_H, DLG.KNOB_SIZE) + 20
        if hitTest(dx, dy, DLG.SLIDER_CX, DLG.SLIDER_CY, DLG.SLIDER_W + DLG.KNOB_SIZE, sliderHitH) then
            state.sliderDragging = true
            local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
            local frac = math.max(0, math.min(1, (dx - sliderL) / DLG.SLIDER_W))
            local qty = math.floor(frac * (state.buyMaxQuantity - 1) + 0.5) + 1
            state.buyQuantity = math.max(1, math.min(state.buyMaxQuantity, qty))
        end
        return true
    end
    if state.tab == "items" and dy >= SCROLL_TOP and dy <= SCROLL_BOT then
        state.dragging = true
        state.lastDragY = dy
        return true
    end
    if state.tab == "privilege" and dy >= PV.SCROLL_TOP_Y and dy <= PV.SCROLL_BOT_Y then
        state.privDragging = true
        state.privLastDragY = dy
        return true
    end
    return true
end

function MarketPage.handleDragMove(dx, dy)
    if not state.open or state.closing then return false end
    if state.dialogOpen then
        if state.sliderDragging and not state.popupClosing then
            local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
            local frac = math.max(0, math.min(1, (dx - sliderL) / DLG.SLIDER_W))
            local qty = math.floor(frac * (state.buyMaxQuantity - 1) + 0.5) + 1
            state.buyQuantity = math.max(1, math.min(state.buyMaxQuantity, qty))
        end
        return true
    end
    if state.dragging then
        state.scrollY = state.scrollY + (state.lastDragY - dy)
        state.lastDragY = dy
        return true
    end
    if state.privDragging then
        state.privScrollY = state.privScrollY + (state.privLastDragY - dy)
        state.privLastDragY = dy
        return true
    end
    return true
end

function MarketPage.handleDragEnd(dx, dy)
    if not state.open or state.closing then return false end
    state.sliderDragging = false
    state.dragging = false
    state.privDragging = false
    return true
end

function MarketPage.handleScroll(wheel)
    if not state.open or state.closing then return false end
    if state.dialogOpen or state.popupClosing or state.keyConfirmVisible then return true end
    if state.tab == "items" then
        state.scrollY = state.scrollY - wheel * 60
    elseif state.tab == "privilege" then
        state.privScrollY = state.privScrollY - wheel * 60
    end
    return true
end

-- ======================== 服务端结果处理========================

--- 接收服务端MARKET_BUY 操作结果
function MarketPage.onActionResult(data)
    if data.action == Protocol.ACTION_TYPES.ARTIFACT_DRAW then
        if data.success then
            local artifactData = PlayerStore.Get("artifacts")
            if artifactData then
                if data.pityRare ~= nil then artifactData.pityRare = data.pityRare end
                if data.pityEpic ~= nil then artifactData.pityEpic = data.pityEpic end
            end

            if data.dailyFreeDrawDayId ~= nil then
                state.artifactFreeDrawDayId = data.dailyFreeDrawDayId
                local artifactData = PlayerStore.Get("artifacts")
                if artifactData then artifactData.dailyFreeDrawDayId = data.dailyFreeDrawDayId end
            end
            local rewards = {}
            for _, artifact in ipairs(data.artifacts or {}) do
                rewards[#rewards + 1] = {
                    type = "artifact",
                    id = artifact.id,
                    artifactId = artifact.artifactId,
                    name = ArtifactDefs.getName(artifact),
                    quality = artifact.quality or 1,
                    value = artifact.value or 0,
                    valueRatio = artifact.valueRatio,
                    threatClearValue = artifact.threatClearValue,
                    threatClearRatio = artifact.threatClearRatio,
                }
            end
            if #rewards > 0 then
                RewardPopup.show("神器宝箱", rewards)
            end
            state.floatText = "获得" .. tostring(#rewards) .. "件神器"
        else
            state.floatText = data.reason or "抽取失败"
        end
        state.floatTextX = 540
        state.floatTextY = COL.BTN_Y - 120
        state.floatTextTime = time.elapsedTime
        return
    end

    if data.action ~= Protocol.ACTION_TYPES.MARKET_BUY then return end

    if data.success then
        local itemId = data.itemId
        if itemId and data.purchased then
            -- 用服务端返回的已购次数 + 倒计时起点更新本地状态
            local rec = state.purchased[itemId]
            if not rec then rec = { count = 0, firstBuyTime = 0, dayId = 0 } end
            rec.count = data.purchased
            if data.firstBuyTime then
                rec.firstBuyTime = data.firstBuyTime
            end
            -- 每日型商品：记录当天 dayId，确保跨天后 getPurchased 能正确重置
            local item = getShopItemById(itemId)
            if item and item.restockType == "daily" then
                rec.dayId = getDayId()
            end
            state.purchased[itemId] = rec
        end
        print("[MarketPage] 购买成功: itemId=" .. tostring(data.itemId)
            .. " reward=" .. tostring(data.rewardName) .. "x" .. tostring(data.rewardCount)
            .. " purchased=" .. tostring(data.purchased))

        -- 特殊奖励展示：随机卷轴展示实际卷轴；随机遗物展示遗物；加速卡展示生效提示
        local detail = data.rewardDetail
        if detail then
            local shownSpecial = false
            local SCROLL_MAP = {
                weaponScroll    = "weapon_scroll",
                offhandScroll   = "offhand_scroll",
                armorScroll     = "armor_scroll",
                accessoryScroll = "accessory_scroll",
            }
            if detail.scrolls then
                -- 新格式：每个独立随机，按类型聚合
                local rewards = {}
                for st, n in pairs(detail.scrolls) do
                    local rewardKey = SCROLL_MAP[st]
                    if rewardKey and n > 0 then
                        rewards[#rewards + 1] = { type = rewardKey, amount = n }
                    end
                end
                if #rewards > 0 then
                    RewardPopup.show("购买成功", rewards)
                    shownSpecial = true
                end
            elseif detail.scrollType then
                -- 兼容旧格式
                local rewardKey = SCROLL_MAP[detail.scrollType]
                if rewardKey then
                    RewardPopup.show("购买成功", {
                        { type = rewardKey, amount = detail.amount or 1 },
                    })
                    shownSpecial = true
                end
            elseif detail.relics then
                local rewards = {}
                for _, relic in ipairs(detail.relics) do
                    rewards[#rewards + 1] = { type = "relic", relicType = relic.type or 1, quality = relic.quality or 2 }
                end
                if #rewards > 0 then
                    RewardPopup.show("购买成功", rewards)
                    shownSpecial = true
                end
            elseif detail.speedCardExpireAt then
                RewardPopup.show("购买成功", { { type = "speed_card", amount = data.rewardCount or 1 } })
                shownSpecial = true
            end
            data.marketSpecialShown = shownSpecial
        end
    else
        print("[MarketPage] 购买失败: " .. tostring(data.reason))
    end
end

--- 接收服务端推送的 market 模块数据（purchased 购买记录）
function MarketPage.setMarketData(data)
    if not data then return end

    local incomingVersion = tonumber(data.shopConfigVersion) or 0
    if incomingVersion >= SHOP_CONFIG_VERSION
        and (state.shopConfigVersion or 0) < SHOP_CONFIG_VERSION then
        state.purchased = {}
        print("[MarketPage] shop config version migrated to " .. SHOP_CONFIG_VERSION)
    end
    if incomingVersion > 0 then
        state.shopConfigVersion = incomingVersion
    end

    if data.purchased ~= nil then
        -- 服务端 purchased: { [itemId] = { count, firstBuyTime, dayId } }
        local newPurchased = {}
        for idStr, rec in pairs(data.purchased) do
            local id = tonumber(idStr)
            if id and rec then
                newPurchased[id] = {
                    count        = rec.count or 0,
                    firstBuyTime = rec.firstBuyTime or 0,
                    dayId        = rec.dayId or 0,
                }
            end
        end
        state.purchased = newPurchased
        print("[MarketPage] 已同步服务端购买记录")
    end
end

--- 清理同会话切区时的市场页区服数据缓存
function MarketPage.resetSessionData()
    state.purchased = {}
    state.shopConfigVersion = 0
    state.privClaimed = {}
    state.privWatchCount = 0
    state.privRefreshHour = 0
    state.privRefreshMin = 0
    state.privRefreshTotalSecs = 0
    state.privRefreshSyncTime = 0
    state.privAdWatching = false
    state.privAdCooldownUntil = 0
    state.artifactFreeDrawDayId = 0
    state.dialogOpen = false
    state.dialogItemIdx = nil
    state.keyConfirmVisible = false
    state.keyConfirmClosing = false
    print("[MarketPage] session data reset")
end

return MarketPage
