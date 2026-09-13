-- ============================================================================
-- DungeonPage - 副本页面（标签5：副本系统）
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- 基于: 副本栅格化.JSON 设计稿
-- ============================================================================

local DrawUtil      = require("core.DrawUtil")
local PlayerStore   = require("client.data.PlayerStore")
local BF            = require("systems.ButtonFeedback")
local Protocol      = require("shared.Protocol")
local GameEvents    = require("config.GameEvents")
local DungeonConfig     = require("config.DungeonConfig")
local DungeonIdleConfig = require("config.DungeonIdleConfig")
local RewardPopup       = require("ui.RewardPopup")
local PlayerInfoPanel   = require("ui.PlayerInfoPanel")
local NumberUtil    = require("core.NumberUtil")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格

local DungeonPage = {}

-- ======================== 网络请求状态 ========================
local pendingSweep     = false
local pendingChallenge = false
local pendingIdleClaim     = false
local pendingIdleClaimTime = 0
local pendingChallengeTime = 0  -- 超时安全阀（秒）
local PENDING_TIMEOUT = 5.0     -- 5秒无响应自动重置

-- ======================== 图片句柄 ========================

local imgTopPattern  = -1   -- UI_FB_BJ.png    顶部花纹
local imgCard1       = -1   -- UI_FBRK_1.png   副本卡片背景（金币矿洞）
local imgCard2       = -1   -- UI_FBRK_2.png   副本卡片背景（上古遗迹）
local imgCard3       = -1   -- UI_FBRK_3.png   副本卡片背景（通天塔）
local imgGold        = -1   -- UI_icon_JB_X.png 金币图标
local imgGem         = -1   -- UI_icon_SJ_X.png 宝石图标
local imgDust        = -1   -- UI_icon_ASFC.png 奥术尘图标
local imgRelic       = -1   -- ICON_SJYW.png 遗物图标
local imgQualityBg   = {}   -- UI_icon_ZBBJ_N.png 品质背景 (1-5)

-- 详情面板图片

local imgFloorBg1    = -1   -- ICON_LXBJ_1.png 上一层背景
local imgFloorBg2    = -1   -- ICON_LXBJ_2.png 当前层背景
local imgFloorBg3    = -1   -- ICON_LXBJ_3.png 下一层背景
local imgArrow       = -1   -- UI_TJP_JIANTOU.png 过渡箭头


local imgRedDot      = -1   -- ICON_HD.png 红点提示
local imgChest       = -1   -- UI_icon_FBBX.png 挂机宝箱

-- ======================== 布局常量（来自 JSON 设计稿）========================

-- 背景色 #EBE8DC
local BG_R, BG_G, BG_B = 0xEB, 0xE8, 0xDC

-- 顶部花纹（左上角定位）
local TOP_X, TOP_Y   = 0, 0
local TOP_W, TOP_H   = 1080, 198

-- 资源栏（与 TopBar 一致的样式）
local GOLD_BG_CX, GOLD_BG_CY = 732, 100
local GOLD_BG_W, GOLD_BG_H   = 170, 47
local GOLD_ICON_CX, GOLD_ICON_CY = 653, 100
local GOLD_ICON_SIZE = 73
local GEM_BG_CX, GEM_BG_CY   = 965, 100
local GEM_BG_W, GEM_BG_H     = 170, 47
local GEM_ICON_CX, GEM_ICON_CY = 884, 100
local GEM_ICON_SIZE  = 76
local RES_FONT_SIZE  = 33
local RES_STROKE_W   = 4
local RES_BG_ROUND   = 18

-- 副本卡片
local CARD_X, CARD_Y = 40, 210     -- 左上角
local CARD_W, CARD_H = 1000, 408
local CARD_ROUND     = 20

-- 卡片内文本（绝对坐标）
local TITLE_X, TITLE_Y   = 714, 253    -- "黄金矿洞"
local TITLE_SIZE         = 70
local TITLE_R, TITLE_G, TITLE_B = 0xFF, 0xF9, 0x68  -- #FFF968

-- 层级徽章
local BADGE_X, BADGE_Y   = 784, 348    -- 左上角
local BADGE_W, BADGE_H   = 206, 63
local BADGE_ROUND        = 28
local LEVEL_TXT_X, LEVEL_TXT_Y = 837, 359

-- 奖励标题
local REWARD_TITLE_X, REWARD_TITLE_Y = 72, 359

-- 奖励图标（左上角定位）
local REWARD1_X, REWARD1_Y = 72, 413
local REWARD2_X, REWARD2_Y = 246, 413
local REWARD_ICON_SIZE     = 160
-- 奖励数量文字（绝对坐标，右对齐）
local REWARD1_TXT_X, REWARD1_TXT_Y = 121, 525
local REWARD2_TXT_X, REWARD2_TXT_Y = 297, 525

-- 今日次数
local DAILY_TXT_X, DAILY_TXT_Y = 732, 521
local DAILY_R, DAILY_G, DAILY_B = 0x8D, 0xFF, 0x87  -- #8DFF87

-- 页面标题
local PAGE_TITLE_X, PAGE_TITLE_Y = 540, 160
local PAGE_TITLE_SIZE = 70

-- 通用描边宽度
local STROKE_W       = 6
local TEXT_SIZE_MD   = 40

-- ======================== 副本数据 ========================

-- 副本配置
local dungeonList = {
    {
        id = "gold_mine",
        name = "黄金矿洞",
        cardImage = "image/UI_FBRK_1.png",
        maxDaily = 2,
        rewards = {
            { type = "gold", icon = "image/UI_icon_JB_X.png", quality = 2, label = "扫荡" },
            { type = "gold", icon = "image/UI_icon_JB_X.png", quality = 2, label = "首通" },
        },
    },
    {
        id = "ancient_ruin",
        name = "上古遗迹",
        titleColor = { 0x78, 0xFF, 0xF7 },  -- #78FFF7
        cardImage = "image/UI_FBRK_2.png",
        maxDaily = 2,
        rewards = {
            { type = "dust",  icon = "image/UI_icon_ASFC.png", quality = 3, label = "奥术尘" },
            { type = "relic", icon = "image/ICON_SJYW.png", quality = 4, label = "遗物" },
        },
    },
    {
        id = "babel_tower",
        name = "通天塔",
        titleColor = { 0xFF, 0xD7, 0x00 },  -- #FFD700 金色
        cardImage = "image/UI_FBRK_3.png",
        maxDaily = 2,
        rewards = {
            { type = "diamond", icon = "image/UI_icon_SJ_X.png", quality = 5, label = "钻石" },
        },
    },
}

--- 获取当前层级对应的实际奖励数值
---@param dungeonId string 副本ID
---@param floor number 当前层数
---@return number reward1 第一个奖励数值(扫荡奖励)
---@return number reward2 第二个奖励数值(首通奖励)
local function getFloorRewards(dungeonId, floor)
    if dungeonId == "gold_mine" then
        local floorData = DungeonConfig.getGoldMineFloor(floor)
        if floorData then
            return floorData.sweepGold, floorData.firstGold
        end
    elseif dungeonId == "ancient_ruin" then
        local floorData = DungeonConfig.getAncientRuinFloor(floor)
        if floorData then
            return floorData.sweepDust, floorData.firstRelicCount
        end
    end
    return 0, 0
end

--- 预览当前副本可领取挂机奖励
---@param dungeonId string
---@return number amount
---@return number accumSec
local function getIdleClaimPreview(dungeonId)
    local dungeon = PlayerStore.Get("dungeon")
    if not dungeon then return 0, 0 end
    local sub = dungeon[dungeonId]
    if not sub then return 0, 0 end
    local idleFloor = DungeonIdleConfig.getIdleFloorFromSub(sub)
    local accumSec = sub.idleAccumSec or 0
    local amount = DungeonIdleConfig.calcReward(dungeonId, idleFloor, accumSec)
    return amount, accumSec
end

local function getIdleMaxHourText()
    local hours = math.floor((DungeonIdleConfig.MAX_ACCUM_SEC or 0) / 3600 + 0.5)
    return tostring(hours) .. "h"
end

--- 格式化挂机累积时长（显示用）
---@param sec number
---@return string
local function formatIdleDuration(sec)
    sec = math.min(math.floor(tonumber(sec) or 0), DungeonIdleConfig.MAX_ACCUM_SEC)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then
        return string.format("%d:%02d", h, m)
    end
    return tostring(m) .. "分"
end

--- 判断副本是否已解锁
---@param dungeonId string
---@return boolean unlocked
---@return string|nil lockText 未解锁时的提示文字
local function isDungeonUnlocked(dungeonId)
    local unlockReq = DungeonConfig.UNLOCK_CONDITIONS[dungeonId]
    if not unlockReq or unlockReq <= 0 then return true, nil end
    local battleData = PlayerStore.Get("battle")
    local maxStageId = battleData and tonumber(battleData.maxStageId) or 0
    if maxStageId >= unlockReq then return true, nil end
    -- 格式化关卡号: 0305 → "3-5关", 1305 → "13-5关"
    local chapter = math.floor(unlockReq / 100)
    local stage   = unlockReq % 100
    local txt = "抵达" .. chapter .. "-" .. stage .. "关时解锁"
    return false, txt
end

-- ======================== 详情面板布局常量 ========================

-- 背景框（九宫格）
local DT_BG_CX, DT_BG_CY = 540, 1195
local DT_BG_W, DT_BG_H   = 950, 1117
local DT_BG_IT, DT_BG_IR, DT_BG_IB, DT_BG_IL = 180, 40, 50, 40

-- 标题
local DT_TITLE_X, DT_TITLE_Y = 540, 705
local DT_TITLE_FONT = 60
local DT_TITLE_SR, DT_TITLE_SG, DT_TITLE_SB = 0x59, 0x32, 0x19  -- 描边 #593219
local DT_TITLE_SW = 6

-- 副本类型文本
local DT_TYPE_X, DT_TYPE_Y = 540, 816
local DT_TYPE_FONT = 40
local DT_TYPE_R, DT_TYPE_G, DT_TYPE_B = 0xB6, 0xB0, 0x9D  -- #b6b09d

-- 上方内容背景
local DT_CONTENT_CX, DT_CONTENT_CY = 540, 1019
local DT_CONTENT_W, DT_CONTENT_H   = 800, 325
local DT_CONTENT_ROUND = 16

-- 层数显示
local DT_FLOOR_PREV_CX, DT_FLOOR_PREV_CY = 253, 1002  -- 上一层
local DT_FLOOR_CURR_CX, DT_FLOOR_CURR_CY = 540, 1002  -- 当前层
local DT_FLOOR_NEXT_CX, DT_FLOOR_NEXT_CY = 828, 1002  -- 下一层
local DT_FLOOR_BG_SIZE = 182
local DT_FLOOR_FONT    = 65
local DT_FLOOR_SW      = 5  -- 层数描边

-- 过渡箭头
local DT_ARROW1_CX, DT_ARROW1_CY = 395, 1003
local DT_ARROW2_CX, DT_ARROW2_CY = 688, 1003
local DT_ARROW_SIZE = 48

-- "当前层数" 文本
local DT_CURLVL_X, DT_CURLVL_Y = 540, 1134
local DT_CURLVL_FONT = 36
local DT_CURLVL_SW   = 5

-- 奖励区域背景（下方）
local DT_REW_BG_CX, DT_REW_BG_CY = 540, 1328
local DT_REW_BG_W, DT_REW_BG_H   = 800, 220
local DT_REW_BG_ROUND = 16

-- 剩余次数文本
local DT_DAILY_X, DT_DAILY_Y = 540, 1530
local DT_DAILY_FONT = 40
local DT_DAILY_R, DT_DAILY_G, DT_DAILY_B = 0x8D, 0xFF, 0x88  -- #8dff88
local DT_DAILY_SW = 5

-- 扫荡按钮
local DT_SWEEP_CX, DT_SWEEP_CY = 330, 1633
local DT_SWEEP_W, DT_SWEEP_H   = 390, 100
local DT_SWEEP_FONT = 40

-- 挑战按钮
local DT_FIGHT_CX, DT_FIGHT_CY = 750, 1633
local DT_FIGHT_W, DT_FIGHT_H   = 390, 100
local DT_FIGHT_FONT = 40

-- 按钮九宫格 insets（UI_AN_HUANG / UI_AN_LV 统一）
local DT_BTN_NP_T, DT_BTN_NP_R, DT_BTN_NP_B, DT_BTN_NP_L = 15, 60, 15, 60

-- 挂机宝箱（详情面板底边下方）
local DT_PANEL_BOTTOM = DT_BG_CY + DT_BG_H * 0.5  -- 1753.5
local DT_CHEST_GAP    = 24
local DT_CHEST_CX     = 540
local DT_CHEST_CY     = DT_PANEL_BOTTOM + DT_CHEST_GAP + 70  -- 底边 + 间距 + 半高
local DT_CHEST_SIZE   = 140
local DT_CHEST_HINT_Y = DT_CHEST_CY + 70 + 24  -- 宝箱下方
local DT_CHEST_REWARD_Y = DT_CHEST_HINT_Y + 42
local DT_CHEST_HINT_FONT = 32
local DT_CHEST_REWARD_FONT = 30

-- ======================== 状态 ========================

-- 奖励图标缓存
local rewardIconCache = {}

-- 运行时状态（per-dungeon）
local dungeonState = {
    gold_mine    = { floor = 1, dailyUsed = 0, dailyMax = 2, idleAccumSec = 0 },
    ancient_ruin = { floor = 1, dailyUsed = 0, dailyMax = 2, idleAccumSec = 0 },
    babel_tower  = { floor = 1, dailyUsed = 0, dailyMax = 2, idleAccumSec = 0 },
}

-- 当前选中副本状态（兼容旧代码的快捷引用）
local currentFloor = 1
local dailyUsed    = 0
local dailyMax     = 2

-- 详情面板状态
local detailOpen = false
local detailDungeon = nil  -- 当前打开的副本数据

-- 详情面板弹出动画
local detailAnimT   = 1.0   -- 动画进度 0→1
local DETAIL_ANIM_DUR = 0.25 -- 动画时长（秒）

-- ======================== 工具函数 ========================

--- 居中绘制图片
local function drawImageCentered(vg, img, cx, cy, w, h, alpha)
    if img < 0 then return end
    alpha = alpha or 1.0
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 左上角定位绘制图片
local function drawImageTopLeft(vg, img, x, y, w, h, alpha)
    if img < 0 then return end
    alpha = alpha or 1.0
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 绘制圆角矩形（左上角定位）
local function drawRoundedRect(vg, x, y, w, h, r, rr, gg, bb, aa)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillColor(vg, nvgRGBA(rr, gg, bb, aa))
    nvgFill(vg)
end

--- 格式化数字（委托给 NumberUtil，支持 K/M/B/T）
local function formatNumber(n)
    return NumberUtil.format(n)
end

--- 从 PlayerStore 获取货币数据
local function getGold()
    local currency = PlayerStore.Get("currency")
    if currency and currency.gold then return currency.gold end
    return 0
end

local function getGem()
    local currency = PlayerStore.Get("currency")
    if currency then return currency.gems or 0 end
    return 0
end

--- 获取副本数据（从 PlayerStore 读取）
local function getDungeonData()
    local dungeon = PlayerStore.Get("dungeon")
    if not dungeon then return end

    -- 金币矿洞
    if dungeon.gold_mine then
        local gm = dungeon.gold_mine
        dungeonState.gold_mine.floor         = gm.floor or 1
        dungeonState.gold_mine.dailyUsed     = gm.dailyUsed or 0
        dungeonState.gold_mine.dailyMax      = dungeon.dailyMax or 2
        dungeonState.gold_mine.idleAccumSec  = gm.idleAccumSec or 0
    end

    -- 上古遗迹
    if dungeon.ancient_ruin then
        local ar = dungeon.ancient_ruin
        dungeonState.ancient_ruin.floor         = ar.floor or 1
        dungeonState.ancient_ruin.dailyUsed     = ar.dailyUsed or 0
        dungeonState.ancient_ruin.dailyMax      = dungeon.dailyMax or 2
        dungeonState.ancient_ruin.idleAccumSec  = ar.idleAccumSec or 0
    end

    -- 通天塔
    if dungeon.babel_tower then
        local bt = dungeon.babel_tower
        dungeonState.babel_tower.floor         = bt.floor or 1
        dungeonState.babel_tower.dailyUsed     = bt.dailyUsed or 0
        dungeonState.babel_tower.dailyMax      = 2
        dungeonState.babel_tower.idleAccumSec  = bt.idleAccumSec or 0
    end

    -- 更新快捷引用（默认使用当前打开的面板，或 gold_mine）
    local activeId = (detailDungeon and detailDungeon.id) or "gold_mine"
    local s = dungeonState[activeId] or dungeonState.gold_mine
    currentFloor = s.floor
    dailyUsed    = s.dailyUsed
    dailyMax     = s.dailyMax
end

-- ======================== Public API ========================

function DungeonPage.init(vg)
    imgTopPattern = nvgCreateImage(vg, "image/UI_FB_BJ.png", 0)
    imgCard1      = nvgCreateImage(vg, "image/UI_FBRK_1.png", 0)
    imgCard2      = nvgCreateImage(vg, "image/UI_FBRK_2.png", 0)
    imgCard3      = nvgCreateImage(vg, "image/UI_FBRK_3.png", 0)
    imgGold       = nvgCreateImage(vg, "image/UI_icon_JB_X.png", 0)
    imgGem        = nvgCreateImage(vg, "image/UI_icon_SJ_X.png", 0)
    imgDust       = nvgCreateImage(vg, "image/UI_icon_ASFC.png", 0)
    imgRelic      = nvgCreateImage(vg, "image/ICON_SJYW.png", 0)
    -- 加载品质背景 1-6
    for i = 1, 6 do
        imgQualityBg[i] = nvgCreateImage(vg, "image/UI_icon_ZBBJ_" .. tostring(i) .. ".png", 0)
    end

    -- 详情面板图片
    imgDetailBg  = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    imgFloorBg1  = nvgCreateImage(vg, "image/ICON_LXBJ_1.png", 0)
    imgFloorBg2  = nvgCreateImage(vg, "image/ICON_LXBJ_2.png", 0)
    imgFloorBg3  = nvgCreateImage(vg, "image/ICON_LXBJ_3.png", 0)
    -- [暗黑化 P1-B5] 原 image/UI_AN_HUANG.png 贴图加载已移除（矢量绘制替代）
    -- [暗黑化 P1-B5] 原 image/UI_AN_LV.png 贴图加载已移除（矢量绘制替代）
    imgBtnGreen  = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    imgRedDot    = nvgCreateImage(vg, "image/ICON_HD.png", 0)
    imgChest     = nvgCreateImage(vg, "image/UI_icon_FBBX.png", 0)

    print("[DungeonPage] init OK")
end

function DungeonPage.draw(vg)
    -- 刷新数据
    getDungeonData()

    -- 1. 全屏背景色
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(BG_R, BG_G, BG_B, 255))
    nvgFill(vg)

    -- 2. 顶部花纹
    drawImageTopLeft(vg, imgTopPattern, TOP_X, TOP_Y, TOP_W, TOP_H, 1.0)

    -- 3. 页面标题 "副本" (已移除)

    -- 4. 资源栏 - 金币（与 TopBar 一致）
    do
        -- 金币背景: 居中, 170x47, r=18, 黑色80%
        nvgBeginPath(vg)
        nvgRoundedRect(vg, GOLD_BG_CX - GOLD_BG_W * 0.5, GOLD_BG_CY - GOLD_BG_H * 0.5, GOLD_BG_W, GOLD_BG_H, RES_BG_ROUND)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
        nvgFill(vg)
        -- 金币图标: 居中(653,100), 73x73
        drawImageCentered(vg, imgGold, GOLD_ICON_CX, GOLD_ICON_CY, GOLD_ICON_SIZE, GOLD_ICON_SIZE, 1.0)
        -- 金币数值: left=bgLeft+44, Y=100, font 33, 白色描边4
        local goldBgLeft = GOLD_BG_CX - GOLD_BG_W * 0.5
        DrawUtil.drawTextStroke(vg, goldBgLeft + 44, GOLD_BG_CY, formatNumber(getGold()),
            RES_FONT_SIZE, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            255, 255, 255, RES_STROKE_W)
    end

    -- 5. 资源栏 - 宝石（与 TopBar 一致）
    do
        -- 钻石背景: 居中, 170x47, r=18, 黑色80%
        nvgBeginPath(vg)
        nvgRoundedRect(vg, GEM_BG_CX - GEM_BG_W * 0.5, GEM_BG_CY - GEM_BG_H * 0.5, GEM_BG_W, GEM_BG_H, RES_BG_ROUND)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
        nvgFill(vg)
        -- 钻石图标: 居中(884,100), 76x76
        drawImageCentered(vg, imgGem, GEM_ICON_CX, GEM_ICON_CY, GEM_ICON_SIZE, GEM_ICON_SIZE, 1.0)
        -- 钻石数值: left=bgLeft+44, Y=100, font 33, 白色描边4
        local gemBgLeft = GEM_BG_CX - GEM_BG_W * 0.5
        DrawUtil.drawTextStroke(vg, gemBgLeft + 44, GEM_BG_CY, formatNumber(getGem()),
            RES_FONT_SIZE, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            255, 255, 255, RES_STROKE_W)
    end

    -- 6. 副本卡片（循环绘制所有副本）
    local CARD_GAP = 20  -- 卡片之间的间距
    local cardImages = { imgCard1, imgCard2, imgCard3 }

    for cardIdx, dungeon in ipairs(dungeonList) do
        local cardY = CARD_Y + (cardIdx - 1) * (CARD_H + CARD_GAP)
        local cardCX = CARD_X + CARD_W * 0.5
        local cardCY = cardY + CARD_H * 0.5

        -- 获取该副本的状态
        local st = dungeonState[dungeon.id] or dungeonState.gold_mine
        local cardFloor = st.floor
        local cardDailyUsed = st.dailyUsed
        local cardDailyMax = st.dailyMax

        local _bf = (not detailOpen) and BF.begin(vg, "dungeon_card_" .. cardIdx, cardCX, cardCY, CARD_W, CARD_H)

        -- 卡片背景图（圆角裁剪）
        nvgSave(vg)
        nvgScissor(vg, CARD_X, cardY, CARD_W, CARD_H)
        local cardImg = cardImages[cardIdx] or imgCard1
        drawImageTopLeft(vg, cardImg, CARD_X, cardY, CARD_W, CARD_H, 1.0)

        -- 解锁判断
        local unlocked, lockText = isDungeonUnlocked(dungeon.id)

        if not unlocked then
            -- 未解锁：黑色遮罩 + 提示文字
            nvgBeginPath(vg)
            nvgRect(vg, CARD_X, cardY, CARD_W, CARD_H)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
            nvgFill(vg)
            -- 居中显示解锁条件文字
            DrawUtil.drawTextStroke(vg, CARD_X + CARD_W * 0.5, cardY + CARD_H * 0.5, lockText or "未解锁",
                44, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, STROKE_W)
        else
            -- 已解锁：正常绘制卡片内容
            -- 卡片内部元素（相对于当前卡片 Y 偏移）
            local yOff = cardY - CARD_Y

            -- 副本名称（斜体 + 右对齐 X=993）
            nvgSave(vg)
            local titleAnchorX, titleAnchorY = 993, TITLE_Y + yOff + TITLE_SIZE * 0.5
            nvgTranslate(vg, titleAnchorX, titleAnchorY)
            nvgSkewX(vg, -math.tan(math.rad(12)))
            nvgTranslate(vg, -titleAnchorX, -titleAnchorY)
            local tR = dungeon.titleColor and dungeon.titleColor[1] or TITLE_R
            local tG = dungeon.titleColor and dungeon.titleColor[2] or TITLE_G
            local tB = dungeon.titleColor and dungeon.titleColor[3] or TITLE_B
            DrawUtil.drawTextStroke(vg, 993, titleAnchorY, dungeon.name,
                TITLE_SIZE, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                tR, tG, tB, STROKE_W)
            nvgRestore(vg)

            -- 层级徽章背景（半透明黑色）
            drawRoundedRect(vg, BADGE_X, BADGE_Y + yOff, BADGE_W, BADGE_H, BADGE_ROUND, 0, 0, 0, 128)

            -- 层级文字
            local levelText = "第" .. cardFloor .. "层"
            DrawUtil.drawTextStroke(vg, BADGE_X + BADGE_W * 0.5, BADGE_Y + yOff + BADGE_H * 0.5, levelText,
                TEXT_SIZE_MD, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, STROKE_W)

            -- 奖励标题
            DrawUtil.drawTextStroke(vg, REWARD_TITLE_X, REWARD_TITLE_Y + yOff + TEXT_SIZE_MD * 0.5, "副本奖励",
                TEXT_SIZE_MD, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                255, 255, 255, STROKE_W)

            -- 奖励图标（品质背景 + 资源图标内缩 + 数量角标）
            local REWARD_POSITIONS = {
                { x = REWARD1_X, y = REWARD1_Y + yOff },
                { x = REWARD2_X, y = REWARD2_Y + yOff },
            }
            local REWARD_INNER = REWARD_ICON_SIZE - 24
            local BADGE_FONT_SZ = 36
            local BADGE_STROKE_W = 4
            local r1, r2 = getFloorRewards(dungeon.id, cardFloor)
            local rewardAmounts = { r1, r2 }

            for i, reward in ipairs(dungeon.rewards) do
                local pos = REWARD_POSITIONS[i]
                if not pos then break end
                local rx, ry = pos.x, pos.y
                local cx = rx + REWARD_ICON_SIZE * 0.5
                local cy = ry + REWARD_ICON_SIZE * 0.5

                -- 1) 品质背景
                DarkIcon.drawQualityBg(vg, reward.quality or 1, cx, cy, REWARD_ICON_SIZE, REWARD_ICON_SIZE, 1.0)  -- [暗黑化 P2-A]

                -- 2) 资源图标（内缩绘制）
                if not rewardIconCache[reward.icon] then
                    rewardIconCache[reward.icon] = nvgCreateImage(vg, reward.icon, 0)
                end
                local icon = rewardIconCache[reward.icon]
                if icon and icon >= 0 then
                    drawImageCentered(vg, icon, cx, cy, REWARD_INNER, REWARD_INNER, 1.0)
                end

                -- 3) 数量角标（右下角偏移8px，16方向描边）
                local amt = rewardAmounts[i] or 0
                if amt > 0 then
                    local amtStr = formatNumber(amt)
                    local bx = cx + REWARD_ICON_SIZE * 0.5 - 8
                    local by = cy + REWARD_ICON_SIZE * 0.5 - 8
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, BADGE_FONT_SZ)
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                    -- 黑色描边（16方向）
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                    local sStep = math.pi * 2 / 16
                    for si = 0, 15 do
                        local sa = si * sStep
                        nvgText(vg, bx + math.cos(sa) * BADGE_STROKE_W, by + math.sin(sa) * BADGE_STROKE_W, amtStr, nil)
                    end
                    -- 白色前景
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                    nvgText(vg, bx, by, amtStr, nil)
                end
            end

            -- 今日次数（右对齐 X=993，显示剩余次数，耗尽变红）
            local cardRemain = cardDailyMax - cardDailyUsed
            if cardRemain < 0 then cardRemain = 0 end
            local dailyTxt = "今日次数：" .. cardRemain .. "/" .. cardDailyMax
            local cardDR, cardDG, cardDB = DAILY_R, DAILY_G, DAILY_B
            if cardRemain <= 0 then
                cardDR, cardDG, cardDB = 0xFF, 0x44, 0x44
            end
            DrawUtil.drawTextStroke(vg, 993, DAILY_TXT_Y + yOff + TEXT_SIZE_MD * 0.5, dailyTxt,
                TEXT_SIZE_MD, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                cardDR, cardDG, cardDB, STROKE_W)

            -- 红点：有剩余扫荡次数时，在卡片右上角显示
            if cardRemain > 0 and imgRedDot >= 0 then
                local rdSz = 44
                local rdX = CARD_X + CARD_W - 30
                local rdY = cardY + 30
                drawImageCentered(vg, imgRedDot, rdX, rdY, rdSz, rdSz, 1.0)
            end
        end

        nvgRestore(vg)  -- 恢复圆角裁剪

        BF.finish(vg, _bf)
    end

   -- 8. 详情面板（覆盖在最上层）
    -- 新手引导热点注册
    do
        local TM = require("systems.TutorialManager")
        if TM.isActive() then
            local cardCX = CARD_X + CARD_W * 0.5  -- 540
            local cardY = CARD_Y  -- 210 (gold_mine)
            local cardCY = cardY + CARD_H * 0.5  -- 414
            TM.registerHotspot("dungeon_gold_mine", cardCX, cardCY, CARD_W, CARD_H)
        end
    end

    if detailOpen and detailDungeon then
        DungeonPage.drawDetailPanel(vg)
    end
end

-- ======================== 详情面板绘制 ========================

function DungeonPage.drawDetailPanel(vg)
    -- easeOutBack 缓动函数
    local function easeOutBack(t)
        local c1 = 1.70158
        local c3 = c1 + 1
        return 1 + c3 * ((t - 1) ^ 3) + c1 * ((t - 1) ^ 2)
    end

    -- 动画缩放值
    local scale = easeOutBack(detailAnimT)
    local maskAlpha = math.floor(128 * detailAnimT)

    -- 1. 全屏遮罩（透明度跟随动画）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, maskAlpha))
    nvgFill(vg)

    -- 2. 面板内容整体缩放（以面板中心为锚点）
    nvgSave(vg)
    nvgTranslate(vg, DT_BG_CX, DT_BG_CY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -DT_BG_CX, -DT_BG_CY)

    -- 3. 九宫格弹窗背景 UI_TY_EJQRK
    local bgX = DT_BG_CX - DT_BG_W * 0.5
    local bgY = DT_BG_CY - DT_BG_H * 0.5
    DarkIcon.drawNine(vg, "panel", bgX, bgY, DT_BG_W, DT_BG_H, { titleH = DT_BG_IT })

    -- 3. 标题（白色 + #593219描边6）
    DrawUtil.drawTextStroke(vg, DT_TITLE_X, DT_TITLE_Y, detailDungeon.name,
        DT_TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DT_TITLE_SW,
        { strokeColor = { DT_TITLE_SR, DT_TITLE_SG, DT_TITLE_SB } })

    -- 4. 副本类型文本（无描边）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, DT_TYPE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(DT_TYPE_R, DT_TYPE_G, DT_TYPE_B, 255))
    nvgText(vg, DT_TYPE_X, DT_TYPE_Y, "每日副本", nil)

    -- 5. 上方内容区域背景（圆角矩形，黑色5%透明度）
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        DT_CONTENT_CX - DT_CONTENT_W * 0.5,
        DT_CONTENT_CY - DT_CONTENT_H * 0.5,
        DT_CONTENT_W, DT_CONTENT_H, DT_CONTENT_ROUND)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))  -- 5% of 255 ≈ 13
    nvgFill(vg)

    -- 6. 三个层数背景图
    -- 上一层 (ICON_LXBJ_1)
    drawImageCentered(vg, imgFloorBg1, DT_FLOOR_PREV_CX, DT_FLOOR_PREV_CY,
        DT_FLOOR_BG_SIZE, DT_FLOOR_BG_SIZE, 1.0)
    -- 当前层 (ICON_LXBJ_2)
    drawImageCentered(vg, imgFloorBg2, DT_FLOOR_CURR_CX, DT_FLOOR_CURR_CY,
        DT_FLOOR_BG_SIZE, DT_FLOOR_BG_SIZE, 1.0)
    -- 下一层 (ICON_LXBJ_3)
    drawImageCentered(vg, imgFloorBg3, DT_FLOOR_NEXT_CX, DT_FLOOR_NEXT_CY,
        DT_FLOOR_BG_SIZE, DT_FLOOR_BG_SIZE, 1.0)

    -- 7. 层数数字（白色 + 黑色描边5）
    local prevFloor = currentFloor - 1  -- 第1层时显示0
    local nextFloor = currentFloor + 1

    DrawUtil.drawTextStroke(vg, DT_FLOOR_PREV_CX, DT_FLOOR_PREV_CY, tostring(prevFloor),
        DT_FLOOR_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DT_FLOOR_SW)

    DrawUtil.drawTextStroke(vg, DT_FLOOR_CURR_CX, DT_FLOOR_CURR_CY, tostring(currentFloor),
        DT_FLOOR_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DT_FLOOR_SW)

    DrawUtil.drawTextStroke(vg, DT_FLOOR_NEXT_CX, DT_FLOOR_NEXT_CY, tostring(nextFloor),
        DT_FLOOR_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DT_FLOOR_SW)

    -- 8. 过渡箭头（两个，在层数图标之间）
    drawImageCentered(vg, imgArrow, DT_ARROW1_CX, DT_ARROW1_CY,
        DT_ARROW_SIZE, DT_ARROW_SIZE, 1.0)
    drawImageCentered(vg, imgArrow, DT_ARROW2_CX, DT_ARROW2_CY,
        DT_ARROW_SIZE, DT_ARROW_SIZE, 1.0)

    -- ==================== 下半部分 ====================

    -- 14. "当前层数" 文本（白色 + 黑色描边5）
    local curLvlText = "当前层数"
    DrawUtil.drawTextStroke(vg, DT_CURLVL_X, DT_CURLVL_Y, curLvlText,
        DT_CURLVL_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, DT_CURLVL_SW)

    -- 15. 奖励区域背景（圆角矩形，黑色5%透明度）
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        DT_REW_BG_CX - DT_REW_BG_W * 0.5,
        DT_REW_BG_CY - DT_REW_BG_H * 0.5,
        DT_REW_BG_W, DT_REW_BG_H, DT_REW_BG_ROUND)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))  -- 5% of 255 ≈ 13
    nvgFill(vg)

    -- 16. 奖励图标（居中排布在奖励区域内，参考 OfflineRewardPanel 样式）
    local rewards = detailDungeon.rewards
    if rewards and #rewards > 0 then
        local REWARD_SZ = REWARD_ICON_SIZE  -- 160
        local REWARD_IN = REWARD_SZ - 24    -- 136 内缩
        local REWARD_GAP = 20
        local totalW = #rewards * REWARD_SZ + (#rewards - 1) * REWARD_GAP
        local startX = DT_REW_BG_CX - totalW * 0.5 + REWARD_SZ * 0.5

        -- 动态获取当前层奖励数值
        local dtSweepGold, dtFirstGold = getFloorRewards(detailDungeon.id, currentFloor)
        local dtRewardAmounts = { dtSweepGold, dtFirstGold }

        for i, reward in ipairs(rewards) do
            local cx = startX + (i - 1) * (REWARD_SZ + REWARD_GAP)
            local cy = DT_REW_BG_CY

            -- 品质背景 [暗黑化 P2-A]
            DarkIcon.drawQualityBg(vg, reward.quality or 1, cx, cy, REWARD_SZ, REWARD_SZ, 1.0)

            -- 资源图标（内缩绘制）
            if not rewardIconCache[reward.icon] then
                rewardIconCache[reward.icon] = nvgCreateImage(vg, reward.icon, 0)
            end
            local icon = rewardIconCache[reward.icon]
            if icon and icon >= 0 then
                drawImageCentered(vg, icon, cx, cy, REWARD_IN, REWARD_IN, 1.0)
            end

            -- 数量角标（右下角偏移8px，16方向描边）
            local dtAmt = dtRewardAmounts[i] or 0
            if dtAmt > 0 then
                local amtStr = formatNumber(dtAmt)
                local bx = cx + REWARD_SZ * 0.5 - 8
                local by = cy + REWARD_SZ * 0.5 - 8
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 36)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                -- 黑色描边（16方向）
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                local sStep = math.pi * 2 / 16
                for si = 0, 15 do
                    local sa = si * sStep
                    nvgText(vg, bx + math.cos(sa) * 4, by + math.sin(sa) * 4, amtStr, nil)
                end
                -- 白色前景
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, bx, by, amtStr, nil)
            end
        end
    end

    -- 17. 剩余次数文本（有剩余=#8dff88，耗尽=红色 + 黑色描边5）
    local dailyRemain = dailyMax - dailyUsed
    if dailyRemain < 0 then dailyRemain = 0 end
    local dailyText = "今日次数:" .. dailyRemain .. "/" .. dailyMax
    local dtR, dtG, dtB = DT_DAILY_R, DT_DAILY_G, DT_DAILY_B
    if dailyRemain <= 0 then
        dtR, dtG, dtB = 0xFF, 0x44, 0x44  -- 红色警告
    end
    DrawUtil.drawTextStroke(vg, DT_DAILY_X, DT_DAILY_Y, dailyText,
        DT_DAILY_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        dtR, dtG, dtB, DT_DAILY_SW)

    -- 18. 扫荡按钮背景 UI_AN_HUANG（九宫格）
    local sweepDisabled = (currentFloor <= 1) or (dailyRemain <= 0)
    local _bfSweep = BF.begin(vg, "dt_sweep_btn", DT_SWEEP_CX, DT_SWEEP_CY, DT_SWEEP_W, DT_SWEEP_H)
    nvgGlobalAlpha(vg, sweepDisabled and 0.45 or 1.0)
    DarkIcon.drawNine(vg, "btn", DT_SWEEP_CX - DT_SWEEP_W * 0.5, DT_SWEEP_CY - DT_SWEEP_H * 0.5, DT_SWEEP_W, DT_SWEEP_H, { accent = "gold" })
    BF.finish(vg, _bfSweep)

    -- 19. 扫荡按钮文本 "扫荡上一层"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, DT_SWEEP_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, sweepDisabled and 100 or 191))
    nvgText(vg, DT_SWEEP_CX, DT_SWEEP_CY, "扫荡上一层", nil)
    nvgGlobalAlpha(vg, 1.0)  -- 恢复全局透明度

    -- 20. 挑战按钮背景 UI_AN_LV（九宫格）
    local _bfFight = BF.begin(vg, "dt_fight_btn", DT_FIGHT_CX, DT_FIGHT_CY, DT_FIGHT_W, DT_FIGHT_H)
    DarkIcon.drawNine(vg, "btn", DT_FIGHT_CX - DT_FIGHT_W * 0.5, DT_FIGHT_CY - DT_FIGHT_H * 0.5, DT_FIGHT_W, DT_FIGHT_H, { accent = "green" })
    BF.finish(vg, _bfFight)

    -- 21. 挑战按钮文本 "挑战"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, DT_FIGHT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))  -- 纯黑不透明度75%
    nvgText(vg, DT_FIGHT_CX, DT_FIGHT_CY, "挑战", nil)

    -- 22. 挂机宝箱（面板正下方）
    local idleAmount = 0
    if detailDungeon then
        idleAmount = select(1, getIdleClaimPreview(detailDungeon.id))
    end
    local _bfChest = BF.begin(vg, "dt_idle_chest", DT_CHEST_CX, DT_CHEST_CY, DT_CHEST_SIZE, DT_CHEST_SIZE)
    drawImageCentered(vg, imgChest, DT_CHEST_CX, DT_CHEST_CY, DT_CHEST_SIZE, DT_CHEST_SIZE, 1.0)
    BF.finish(vg, _bfChest)
    if idleAmount > 0 and imgRedDot >= 0 then
        local rdX = DT_CHEST_CX + DT_CHEST_SIZE * 0.5 - 18
        local rdY = DT_CHEST_CY - DT_CHEST_SIZE * 0.5 + 18
        drawImageCentered(vg, imgRedDot, rdX, rdY, 44, 44, 1.0)
    end

    -- 23. 挂机时长 / 上限提示
    if detailDungeon then
        local _, accumSec = getIdleClaimPreview(detailDungeon.id)
        accumSec = math.min(accumSec or 0, DungeonIdleConfig.MAX_ACCUM_SEC)
        local timeTxt
        local maxHourText = getIdleMaxHourText()
        if DungeonIdleConfig.getFillRatio(accumSec) >= 1 then
            timeTxt = "挂机已满(" .. maxHourText .. ")"
        else
            timeTxt = "挂机 " .. formatIdleDuration(accumSec) .. "/" .. maxHourText
        end
        DrawUtil.drawTextStroke(vg, DT_CHEST_CX, DT_CHEST_HINT_Y, timeTxt,
            DT_CHEST_HINT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            0xB6, 0xB0, 0x9D, 4)
        DrawUtil.drawTextStroke(vg, DT_CHEST_CX, DT_CHEST_REWARD_Y, "已存奖励：" .. formatNumber(idleAmount),
            DT_CHEST_REWARD_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            0xFF, 0xEA, 0x00, 4)
    end

    nvgRestore(vg)  -- 结束面板缩放变换
end

function DungeonPage.update(dt)
    -- 详情面板弹出动画
    if detailOpen and detailAnimT < 1.0 then
        detailAnimT = detailAnimT + dt / DETAIL_ANIM_DUR
        if detailAnimT > 1.0 then detailAnimT = 1.0 end
    end

    -- pending 超时安全阀：防止服务端无响应时按钮永久卡死
    if pendingChallenge then
        pendingChallengeTime = pendingChallengeTime + dt
        if pendingChallengeTime >= PENDING_TIMEOUT then
            print("[DungeonPage] pendingChallenge timeout, force reset")
            pendingChallenge = false
            pendingChallengeTime = 0
        end
    end

    if pendingIdleClaim then
        pendingIdleClaimTime = pendingIdleClaimTime + dt
        if pendingIdleClaimTime >= PENDING_TIMEOUT then
            print("[DungeonPage] pendingIdleClaim timeout, force reset")
            pendingIdleClaim = false
            pendingIdleClaimTime = 0
        end
    end
end

function DungeonPage.handleInput(dx, dy)
    -- 详情面板打开时，优先处理面板内交互
    if detailOpen then
        -- 挂机宝箱绘制在详情面板外侧，必须先于“点击背景外关闭面板”处理
        if DrawUtil.hitTest(dx, dy, DT_CHEST_CX, DT_CHEST_CY, DT_CHEST_SIZE, DT_CHEST_SIZE) then
            BF.trigger("dt_idle_chest")
            if pendingIdleClaim then
                print("[DungeonPage] idle claim pending, skip")
                return true
            end
            local dId = detailDungeon and detailDungeon.id
            if not dId then return true end
            local amount = select(1, getIdleClaimPreview(dId))
            if amount <= 0 then
                print("[DungeonPage] no idle reward to claim dungeon=" .. dId)
                return true
            end
            pendingIdleClaim = true
            pendingIdleClaimTime = 0
            print("[DungeonPage] sending DUNGEON_IDLE_CLAIM dungeon=" .. dId)
            require("network.Client").sendAction(
                Protocol.ACTION_TYPES.DUNGEON_IDLE_CLAIM,
                { dungeonId = dId }
            )
            return true
        end

        -- 点击九宫格背景外区域 → 关闭面板
        if not DrawUtil.hitTest(dx, dy, DT_BG_CX, DT_BG_CY, DT_BG_W, DT_BG_H) then
            detailOpen = false
            detailDungeon = nil
            return true
        end

        -- 扫荡按钮
        if DrawUtil.hitTest(dx, dy, DT_SWEEP_CX, DT_SWEEP_CY, DT_SWEEP_W, DT_SWEEP_H) then
            BF.trigger("dt_sweep_btn")
            if pendingSweep then
                print("[DungeonPage] sweep request pending, skip")
            elseif currentFloor <= 1 then
                print("[DungeonPage] floor=1, nothing to sweep")
            elseif dailyUsed >= dailyMax then
                print("[DungeonPage] daily sweep limit reached")
            else
                pendingSweep = true
                local dId = detailDungeon.id
                if dId == "babel_tower" then
                    print("[DungeonPage] sending TOWER_SWEEP")
                    require("network.Client").sendAction(
                        Protocol.ACTION_TYPES.TOWER_SWEEP, {}
                    )
                else
                    print("[DungeonPage] sending DUNGEON_SWEEP dungeon=" .. dId .. " floor=" .. (currentFloor - 1))
                    require("network.Client").sendAction(
                        Protocol.ACTION_TYPES.DUNGEON_SWEEP,
                        { dungeonId = dId }
                    )
                end
            end
            return true
        end

        -- 挑战按钮
        if DrawUtil.hitTest(dx, dy, DT_FIGHT_CX, DT_FIGHT_CY, DT_FIGHT_W, DT_FIGHT_H) then
            BF.trigger("dt_fight_btn")
            if pendingChallenge then
                print("[DungeonPage] challenge request pending, skip")
            else
                pendingChallenge = true
                pendingChallengeTime = 0
                local dId = detailDungeon.id
                if dId == "babel_tower" then
                    -- 通天塔走专用协议
                    print("[DungeonPage] sending TOWER_CHALLENGE floor=" .. currentFloor)
                    require("network.Client").sendAction(
                        Protocol.ACTION_TYPES.TOWER_CHALLENGE, {}
                    )
                else
                    print("[DungeonPage] sending DUNGEON_CHALLENGE dungeon=" .. dId .. " floor=" .. currentFloor)
                    require("network.Client").sendAction(
                        Protocol.ACTION_TYPES.DUNGEON_CHALLENGE,
                        { dungeonId = dId, floor = currentFloor }
                    )
                end
            end
            return true
        end

        return true  -- 消费所有点击，阻止穿透
    end

    -- 卡片点击检测 → 打开详情面板（循环检测所有卡片）
    local CARD_GAP = 20
    local cardCX = CARD_X + CARD_W * 0.5
    for cardIdx, dungeon in ipairs(dungeonList) do
        local cardY = CARD_Y + (cardIdx - 1) * (CARD_H + CARD_GAP)
        local cardCY = cardY + CARD_H * 0.5
        if DrawUtil.hitTest(dx, dy, cardCX, cardCY, CARD_W, CARD_H) then
            -- 未解锁的卡片不可点击
            local unlocked = isDungeonUnlocked(dungeon.id)
            if not unlocked then return true end

            detailDungeon = dungeon
            -- 更新快捷引用到该副本的状态
            local s = dungeonState[dungeon.id] or dungeonState.gold_mine
            currentFloor = s.floor
            dailyUsed    = s.dailyUsed
            dailyMax     = s.dailyMax
            detailOpen = true
            detailAnimT = 0  -- 重置动画进度
            print("[DungeonPage] detail panel opened: " .. detailDungeon.name)
            return true
        end
    end
    return false
end

-- ======================== 网络响应处理 ========================

--- 服务端操作结果回调（由 Client.lua 调用）
---@param data table { action, success, reason, ... }
function DungeonPage.onActionResult(data)
    local action = data.action

    -- 扫荡结果
    if action == Protocol.ACTION_TYPES.DUNGEON_SWEEP then
        pendingSweep = false
        if data.success then
            print("[DungeonPage] SWEEP OK: floor=" .. tostring(data.sweepFloor)
                .. " gold=" .. tostring(data.gold)
                .. " dust=" .. tostring(data.dust)
                .. " relics=" .. tostring(data.relics and #data.relics or 0)
                .. " daily=" .. tostring(data.dailyUsed) .. "/" .. tostring(data.dailyMax))
            -- 更新本地显示数据
            dailyUsed = data.dailyUsed or dailyUsed
            dailyMax  = data.dailyMax or dailyMax
            -- 同步 dungeonState
            local dId = data.dungeonId or "gold_mine"
            if dungeonState[dId] then
                dungeonState[dId].dailyUsed = dailyUsed
                dungeonState[dId].dailyMax  = dailyMax
            end

            -- 组装奖励列表并弹出奖励面板
            local rewards = {}
            if (data.gold or 0) > 0 then
                rewards[#rewards + 1] = { type = "gold", amount = data.gold }
            end
            if (data.dust or 0) > 0 then
                rewards[#rewards + 1] = { type = "arcane_dust", amount = data.dust }
            end
            if data.relics and #data.relics > 0 then
                for _, r in ipairs(data.relics) do
                    rewards[#rewards + 1] = { type = "relic", relicType = r.type, quality = r.quality or 4 }
                end
            end
            RewardPopup.show("扫荡奖励", rewards)
        else
            print("[DungeonPage] SWEEP FAIL: " .. tostring(data.reason))
        end
        return
    end

    -- 副本挂机/离线收益领取
    if action == Protocol.ACTION_TYPES.DUNGEON_IDLE_CLAIM then
        pendingIdleClaim = false
        pendingIdleClaimTime = 0
        if data.success then
            -- 忽略迟到的旧区服响应，避免覆盖新区服的 idleAccumSec
            local respSid = tonumber(data.serverId)
            local curSid = PlayerInfoPanel.getServerId()
            if respSid and curSid and respSid ~= curSid then
                print(string.format(
                    "[DungeonPage] IDLE CLAIM stale sid=%s cur=%s, ignore accum update",
                    tostring(respSid), tostring(curSid)))
                return
            end

            local amount = data.amount or 0
            local rewardType = data.rewardType or "gold"
            print("[DungeonPage] IDLE CLAIM OK: dungeon=" .. tostring(data.dungeonId)
                .. " amount=" .. tostring(amount)
                .. " type=" .. tostring(rewardType))
            getDungeonData()
            local dId = data.dungeonId
            if dId and dungeonState[dId] and data.accumSec ~= nil then
                dungeonState[dId].idleAccumSec = data.accumSec
            end
            if amount > 0 then
                RewardPopup.show("挂机奖励", {
                    { type = rewardType, amount = amount },
                })
            end
        else
            print("[DungeonPage] IDLE CLAIM FAIL: " .. tostring(data.reason))
        end
        return
    end

    -- 挑战结果（服务端返回战斗配置，进入副本战斗场景）
    if action == Protocol.ACTION_TYPES.DUNGEON_CHALLENGE then
        pendingChallenge = false
        if data.success then
            print("[DungeonPage] CHALLENGE OK: dungeon=" .. tostring(data.dungeonId)
                .. " floor=" .. tostring(data.floor)
                .. " monsterLv=" .. tostring(data.monsterLevel))
            -- 关闭详情面板
            local openedDungeonId = detailDungeon and detailDungeon.id or data.dungeonId
            detailOpen = false
            detailDungeon = nil
            -- 打开独立副本战斗场景（类似竞技场）
            local DungeonBattleScene = require("ui.DungeonBattleScene")
            local CharacterPanel = require("ui.CharacterPanel")
            local allies = CharacterPanel.getDeployedTeam()
            print("[DungeonPage] opening DungeonBattleScene with " .. #allies .. " allies, dungeon=" .. tostring(openedDungeonId))
            DungeonBattleScene.open({
                allies    = allies,
                data      = data,
                dungeonId = openedDungeonId,
                onClose   = function()
                    print("[DungeonPage] DungeonBattleScene closed")
                end,
            })
        else
            print("[DungeonPage] CHALLENGE FAIL: " .. tostring(data.reason))
        end
        return
    end

    -- ==================== 通天塔协议处理 ====================

    -- 通天塔挑战结果 → 打开 TowerBattleScene
    if action == Protocol.ACTION_TYPES.TOWER_CHALLENGE then
        pendingChallenge = false
        if data.success then
            print("[DungeonPage] TOWER_CHALLENGE OK: floor=" .. tostring(data.floor)
                .. " wave=" .. tostring(data.wave) .. " monsterLv=" .. tostring(data.monsterLevel))
            detailOpen = false
            detailDungeon = nil
            local TowerBattleScene = require("ui.TowerBattleScene")
            local TowerBuffPick    = require("ui.TowerBuffPick")
            local CharacterPanel   = require("ui.CharacterPanel")
            local allies = CharacterPanel.getDeployedTeam()
            -- 初始化三选一面板（如尚未 init）
            -- TowerBuffPick.init 在主场景 init 时已调用
            TowerBattleScene.open({
                allies     = allies,
                data       = data,
                sendAction = function(act, params)
                    require("network.Client").sendAction(act, params)
                end,
                onClose    = function()
                    print("[DungeonPage] TowerBattleScene closed")
                end,
            })
        else
            print("[DungeonPage] TOWER_CHALLENGE FAIL: " .. tostring(data.reason))
        end
        return
    end

    -- 通天塔扫荡结果
    if action == Protocol.ACTION_TYPES.TOWER_SWEEP then
        pendingSweep = false
        if data.success then
            print("[DungeonPage] TOWER_SWEEP OK: floor=" .. tostring(data.sweepFloor)
                .. " diamond=" .. tostring(data.diamondReward))
            dungeonState.babel_tower.dailyUsed = data.dailyUsed or 0
            dailyUsed = dungeonState.babel_tower.dailyUsed
            local rewards = {}
            if (data.diamondReward or 0) > 0 then
                rewards[#rewards + 1] = { type = "diamond", amount = data.diamondReward }
            end
            RewardPopup.show("扫荡奖励", rewards)
        else
            print("[DungeonPage] TOWER_SWEEP FAIL: " .. tostring(data.reason))
        end
        return
    end

    -- 通天塔波次胜利 → 转发给 TowerBattleScene
    if action == Protocol.ACTION_TYPES.TOWER_WAVE_WIN then
        local TowerBattleScene = require("ui.TowerBattleScene")
        if TowerBattleScene.isActive() then
            TowerBattleScene.onWaveWinResult(data)
        end
        return
    end

    -- 通天塔整层通关 → 转发给 TowerBattleScene + 更新本地层数
    if action == Protocol.ACTION_TYPES.TOWER_FLOOR_WIN then
        if data.success then
            dungeonState.babel_tower.floor = data.nextFloor or (dungeonState.babel_tower.floor + 1)
            currentFloor = dungeonState.babel_tower.floor
        end
        local TowerBattleScene = require("ui.TowerBattleScene")
        if TowerBattleScene.isActive() then
            TowerBattleScene.onFloorWinResult(data)
        end
        return
    end

    -- ==================== 常规副本协议处理 ====================

    -- 战斗胜利结果
    if action == Protocol.ACTION_TYPES.DUNGEON_WIN then
        if data.success then
            print("[DungeonPage] WIN OK: dungeon=" .. tostring(data.dungeonId)
                .. " floor=" .. tostring(data.floor)
                .. " firstClear=" .. tostring(data.firstClear)
                .. " gold=" .. tostring(data.gold)
                .. " dust=" .. tostring(data.dust)
                .. " relics=" .. tostring(data.relics and #data.relics or 0)
                .. " nextFloor=" .. tostring(data.nextFloor))
            -- 更新本地楼层显示
            local dId = data.dungeonId or "gold_mine"
            if dungeonState[dId] then
                dungeonState[dId].floor = data.nextFloor or dungeonState[dId].floor
            end
            currentFloor = data.nextFloor or currentFloor
            -- 把奖励数据传给 DungeonBattle，供结算面板展示
            local DungeonBattle = require("ui.DungeonBattle")
            DungeonBattle.setServerResult(data)
            -- 同时通知 DungeonBattleScene（它的 onActionResult 也会处理）
        else
            print("[DungeonPage] WIN FAIL: " .. tostring(data.reason))
            -- 即使失败也通知 DungeonBattle（避免结算面板永远等待）
            local DungeonBattle = require("ui.DungeonBattle")
            DungeonBattle.setServerResult({ success = false, gold = 0 })
        end
        return
    end
end

return DungeonPage
