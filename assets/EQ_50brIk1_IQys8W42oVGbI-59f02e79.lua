-- ============================================================================
-- SignInPanel - 签到面板（每周签到 / 每日签到）
-- 全屏面板：顶部背景 + 九宫格下方面板 + 可滚动签到条目 + 底部返回&Tab
-- ============================================================================

local GameConfig   = require("config.GameConfig")
local DrawUtil     = require("core.DrawUtil")
local ImageCache   = require("ui.ImageCache")
local RewardPopup  = require("ui.RewardPopup")
local SignInConfig  = require("shared.signin.SignInConfig")
local Protocol     = require("shared.Protocol")
local BF           = require("systems.ButtonFeedback")
local ResourceDefs = require("config.ResourceDefs")

local Panel = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量 ========================

-- 1. 顶部背景图 UI_MZQD_BJ.png — 顶端对齐
local TOP_BG = {
    CX = 540, W = 1080, H = 930,
    -- Y: 图片最上方与屏幕最上方对齐 → CY = H/2
    CY = 930 * 0.5,  -- 465
}

-- 2. 下方背景面板 UI_MZQD_1.png（九宫格）
local PANEL = {
    CX = 540, CY = 1546, W = 1080, H = 1708,
    IT = 200, IB = 10, IL = 150, IR = 150,
}

-- 3. 签到条目 UI_MZQD_2.png (1010×220)
local ENTRY = {
    CX = 540, W = 1010, H = 220,
    GAP = 10,  -- 间距 10px
    -- 第一条条目的绝对 Y（根据面板顶部 + 面板九宫格顶部偏移推算）
    -- 面板顶部 = 1546 - 1708*0.5 = 692，九宫格 top=200 → 内容起始 Y ≈ 892
    -- 第一条条目 CY = 892 + 220/2 = 951 ≈ 用户给的 Y946，取用户给的 951
    FIRST_CY = 951,

    -- 3-2) 天数值
    DAY_X = 90, DAY_Y_OFF = -5, DAY_FONT = 48,
    DAY_SW = 5,
    DAY_SR = 0x31, DAY_SG = 0x24, DAY_SB = 0x24,

    -- 3-3/4) 品质框 + 奖励图标
    ICON_CX = 266, ICON_CY_OFF = 0,
    FRAME_W = 160, FRAME_H = 160,
    ICON_W = 160, ICON_H = 160,

    -- 3-5) 数量角标（图标右下角）
    BADGE_FONT = 40, BADGE_SW = 5,

    -- 3-6) 锁标志
    LOCK_CX = 540, LOCK_CY_OFF = -5, LOCK_W = 138, LOCK_H = 138,

    -- 3-7) 按钮（九宫格 上下左右各20）
    BTN_CX = 856, BTN_CY_OFF = 0, BTN_W = 270, BTN_H = 122,
    BTN_INSET = 20,  -- 九宫格统一 inset
    BTN_FONT = 50,
    BTN_TEXT_A = 191,  -- 75% of 255
}
ENTRY.STEP = ENTRY.H + ENTRY.GAP  -- 230

-- 裁剪区域：从第一条条目顶部到 Y2185
local CLIP = {
    TOP = ENTRY.FIRST_CY - ENTRY.H * 0.5,   -- 841
    BOT = 2185,
}
CLIP.H = CLIP.BOT - CLIP.TOP

-- ======================== 每日签到布局常量 ========================

-- 每日顶部背景图 UI_MRQD_BJ.png — 顶端对齐
local DAILY_TOP_BG = {
    CX = 540, W = 1080, H = 930,
    CY = 930 * 0.5,  -- 465 (顶端对齐)
}

-- 每日下方背景面板 UI_MRQD_1.png（九宫格）
local DAILY_PANEL = {
    CX = 540, CY = 1546, W = 1080, H = 1708,
    IT = 200, IB = 10, IL = 150, IR = 150,
}

-- 每日签到网格
local DAILY_GRID = {
    COLS = 5,
    ITEM_W = 190, ITEM_H = 210,
    GAP_X = 14,  GAP_Y = 18,
    -- 第一个格子中心
    FIRST_CX = 134, FIRST_CY = 980,
    -- 步进
    STEP_X = 190 + 14,   -- 204
    STEP_Y = 210 + 18,   -- 228
    -- 从格子中心的偏移量
    DAY_DX = -58, DAY_DY = -76,       -- 天数值
    ICON_DX = 1,  ICON_DY = 3,        -- 奖励图标
    ICON_W = 148, ICON_H = 148,
    CHECK_DX = 73, CHECK_DY = -94,    -- 已签勾号
    CHECK_W = 80,  CHECK_H = 80,
    MISS_DX = 37,  MISS_DY = -76,     -- 补签戳章
    MISS_W = 134,  MISS_H = 56,
    MISS_TEXT_DY = -80,                -- 补签文字偏移
    -- 天数字体
    DAY_FONT = 34,
    DAY_STROKE_W = 5,
    DAY_STROKE_R = 0x24, DAY_STROKE_G = 0x13, DAY_STROKE_B = 0x33,
    -- 可签到天数颜色
    DAY_ACTIVE_R = 0xdf, DAY_ACTIVE_G = 0xa2, DAY_ACTIVE_B = 0x2d,
    -- 数量角标
    BADGE_FONT = 40, BADGE_SW = 5,
    -- 发光参数 (ec1bff, 多层外发光 —— 参考觉醒面板连接线外发光)
    GLOW_R = 0xec, GLOW_G = 0x1b, GLOW_B = 0xff,
    GLOW_BASE_ALPHA = 51,    -- 20% of 255 (与觉醒连接线一致)
    GLOW_WIDTH = 29,          -- 外发光扩散宽度 (与觉醒连接线一致)
    GLOW_LAYERS = 8,          -- 层数 (与觉醒连接线一致)
}

-- 每日签到裁剪区域
local DAILY_CLIP = {
    TOP = DAILY_GRID.FIRST_CY - DAILY_GRID.ITEM_H * 0.5 - DAILY_GRID.GLOW_WIDTH,  -- ~846
    BOT = 2070,
}
DAILY_CLIP.H = DAILY_CLIP.BOT - DAILY_CLIP.TOP

-- 每日签到按钮
local DAILY_SIGN_BTN = {
    CX = 540, CY = 2144, W = 410, H = 100,
    FONT = 40,
    TEXT_A = 191,  -- 75% of 255
    INSET = 20,
}

-- ======================== 补签确认弹窗布局（复用项目通用二级确认样式） ========================

local CONFIRM = {
    -- 确认框整体
    BG_CX = 540, BG_CY = 1110, BG_W = 950, BG_H = 647,
    -- 标题
    TITLE_CX = 540, TITLE_CY = 856, TITLE_FONT = 60, TITLE_SW = 6,
    TITLE_SR = 0x46, TITLE_SG = 0x2f, TITLE_SB = 0x20,
    -- 副标题
    SUB_CX = 540, SUB_CY = 967, SUB_FONT = 40,
    SUB_R = 0xb6, SUB_G = 0xb0, SUB_B = 0x9d,
    -- 内容背景框
    CONTENT_CX = 540, CONTENT_CY = 1121, CONTENT_W = 800, CONTENT_H = 218,
    -- 箭头
    ARROW_CX = 540, ARROW_CY = 1123, ARROW_W = 48, ARROW_H = 48,
    -- 左侧消耗（钻石）
    COST_CX = 415, COST_CY = 1122, COST_ICON_SIZE = 160,
    -- 右侧获得（奖励）
    REWARD_CX = 664, REWARD_CY = 1122, REWARD_ICON_SIZE = 160,
    -- 数量角标
    BADGE_FONT = 40, BADGE_SW = 5, BADGE_OX = 56, BADGE_OY = 50,
    -- 确认按钮
    BTN_CX = 540, BTN_CY = 1301, BTN_W = 410, BTN_H = 100,
    BTN_FONT = 40, BTN_INSET = 20,
    BTN_R = 0x64, BTN_G = 0x51, BTN_B = 0x29,
    -- 动画
    OPEN_DUR = 0.25, CLOSE_DUR = 0.20,
    SCALE_FROM = 0.8, SCALE_TO = 1.0,
}

-- 4. 返回按钮（与教堂面板一致）
local BTN_BACK = {
    CX = 122, CY = 2308, W = 184, H = 143,
}

-- 5. Tab 栏 + 滑块（与教堂面板一致）
local TAB = {
    BG_CX = 639, BG_CY = 2308, BG_W = 810, BG_H = 143,
    SLIDER_W = 410, SLIDER_H = 143,
    INSET_TOP = 10, INSET_BOTTOM = 10, INSET_LEFT = 70, INSET_RIGHT = 70,
    FONT_SIZE = 40,
    ACTIVE_R = 0x81, ACTIVE_G = 0x57, ACTIVE_B = 0x3c,
    INACTIVE_R = 255, INACTIVE_G = 255, INACTIVE_B = 255,
    ANIM_DUR = 0.35,
}

local TAB_ITEMS = {
    { key = "weekly", name = "每周签到", cx = 439, cy = 2308, textX = 439, textY = 2302 },
    { key = "daily",  name = "每日签到", cx = 839, cy = 2308, textX = 839, textY = 2302 },
}

-- ======================== 缓动函数 ========================

local function easeInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    local f = 2 * t - 2; return 0.5 * f * f * f + 1
end

local function easeOutCubic(t)
    local f = t - 1; return f * f * f + 1
end

local function easeInCubic(t)
    return t * t * t
end

-- 开关动画时长 & 滑动距离
local ANIM_OPEN_DUR  = 0.45
local ANIM_CLOSE_DUR = 0.38
local UPPER_SLIDE_DIST = 1200
local LOWER_SLIDE_DIST = 1600

-- ======================== 图片句柄 ========================

local imgTopBg    = -1  -- UI_MZQD_BJ.png
local imgPanel    = -1  -- UI_MZQD_1.png（九宫格面板）
local imgEntry    = -1  -- UI_MZQD_2.png（条目背景）
local imgBtnBack  = -1  -- UI_AN_FH.png（返回按钮）
local imgTabBg    = -1  -- UI_AN_1.png（Tab 背景）
local imgSlider   = -1  -- UI_AN_2.png（Tab 滑块）
local imgBtnSign  = -1  -- UI_AN_FANG_huang.png（签到按钮 - 黄）
local imgBtnDone  = -1  -- UI_AN_FANG_lv.png（已领取按钮 - 绿）
local imgBtnRetro = -1  -- UI_AN_FANG_hong.png（补签按钮 - 红）
local imgLock     = -1  -- ICON_GN_BAN.png（锁标志）

-- 每日签到专用图片
local imgDailyTopBg    = -1  -- UI_MRQD_BJ.png（每日顶部背景）
local imgDailyPanel    = -1  -- UI_MRQD_1.png（每日九宫格面板）
local imgDailyEntry    = -1  -- UI_MRQD_2.png（普通格子背景）
local imgDailyEntryAct = -1  -- UI_MRQD_3.png（可签到格子背景）
local imgCheckmark     = -1  -- UI_icon_GOU.png（已签勾号）
local imgMissedStamp   = -1  -- UI_JSJM_CZZ.png（补签戳章）
local imgDailySignBtn  = -1  -- UI_AN_HUANG.png（每日签到按钮）

-- 补签确认弹窗图片
local imgConfirmBg = -1   -- UI_TY_EJQRK.png（确认框背景）
local imgArrowIcon = -1   -- UI_TJP_JIANTOU.png（箭头分隔符）
local imgRedDot    = -1   -- ICON_HD.png（红点提示）

-- NanoVG 上下文
local vg_ = nil

-- ======================== 资源定义（统一引用中央注册表） ========================
local RESOURCE_DEFS = ResourceDefs.DEFS

local resIconCache = {}

local function getResIcon(resType)
    local cached = resIconCache[resType]
    if cached then return cached end
    if not vg_ then return -1 end
    local def = RESOURCE_DEFS[resType]
    if not def then return -1 end
    local handle = nvgCreateImage(vg_, def.iconPath, 0)
    resIconCache[resType] = handle
    return handle
end

-- ======================== 签到数据（服务端驱动） ========================

-- status: "available" 可签到 | "claimed" 已领取 | "missed" 补签 | "locked" 未解锁
local RETRO_SIGN_COST = SignInConfig.RETRO_COST  -- 120

--- 服务端推送的签到模块数据
local signinData_ = nil

--- sendAction 回调（由 Client.lua 注入）
local sendAction_ = nil

--- 当前区服开服时间戳（UTC os.time），0 表示未设置，退回自然月逻辑
local serverOpenTime_ = 0

--- 从服务端数据构建每周签到展示数据
---@return table[] WEEKLY_DATA
local function buildWeeklyData()
    local dayOfWeek = SignInConfig.getDayOfWeek(serverOpenTime_)  -- 1-7（基于开服时间）
    local claimed = (signinData_ and signinData_.weeklyClaimed) or {}
    local rewards = SignInConfig.WEEKLY_REWARDS
    local data = {}
    for i = 1, 7 do
        local reward = rewards[i]
        local status
        if claimed[i] then
            status = "claimed"
        elseif i < dayOfWeek then
            status = "missed"
        elseif i == dayOfWeek then
            status = "available"
        else
            status = "locked"
        end
        data[i] = {
            day = i,
            reward = { type = reward.type, amount = reward.amount },
            status = status,
        }
    end
    return data
end

--- 从服务端数据构建每日签到展示数据
---@return table[] DAILY_DATA
local function buildDailyData()
    local dayOfPeriod = SignInConfig.getDayOfServerPeriod(serverOpenTime_)  -- 1-30
    local claimed = (signinData_ and signinData_.dailyClaimed) or {}
    local rewards = SignInConfig.DAILY_REWARDS
    local data = {}
    for i = 1, 30 do
        local reward = rewards[i]
        local status
        if claimed[i] then
            status = "claimed"
        elseif i < dayOfPeriod then
            status = "missed"
        elseif i == dayOfPeriod then
            status = "available"
        else
            status = "locked"
        end
        data[i] = {
            day = i,
            reward = { type = reward.type, amount = reward.amount },
            status = status,
        }
    end
    return data
end

--- 缓存构建结果（每次服务端推送时重建）
local WEEKLY_DATA = {}
local DAILY_DATA = {}

--- 刷新签到展示数据
local function refreshDisplayData()
    WEEKLY_DATA = buildWeeklyData()
    DAILY_DATA  = buildDailyData()
end

-- ======================== 状态 ========================

local state = {
    open = false,
    closing = false,
    openTime = 0,
    closeTime = 0,
    tab = "weekly",        -- "daily" | "weekly"
    tabFrom = "weekly",
    tabSwitchTime = 0,
    scrollY = 0,
    dragging = false,
    lastDragY = 0,
    -- 补签确认弹窗
    confirmOpen = false,
    confirmClosing = false,
    confirmOpenTime = 0,
    confirmCloseTime = 0,
    confirmItem = nil,      -- 待补签的条目引用
    confirmSource = nil,    -- "daily" | "weekly"
}

-- ======================== 辅助 ========================

local function getTabIndex(key)
    for i, item in ipairs(TAB_ITEMS) do
        if item.key == key then return i end
    end
    return 1
end

-- ======================== 补签确认弹窗辅助 ========================

local function openConfirmDialog(item, source)
    state.confirmOpen = true
    state.confirmClosing = false
    state.confirmOpenTime = time.elapsedTime
    state.confirmItem = item
    state.confirmSource = source or state.tab
    print("[SignInPanel] 打开补签确认 - 第" .. item.day .. "天")
end

local function closeConfirmDialog()
    if state.confirmClosing then return end
    state.confirmClosing = true
    state.confirmCloseTime = time.elapsedTime
end

--- 返回确认弹窗动画 (scale, alpha)
local function getConfirmAnim()
    if not state.confirmOpen then return 0, 0 end
    local C = CONFIRM
    if state.confirmClosing then
        local elapsed = time.elapsedTime - state.confirmCloseTime
        local rawT = math.min(1.0, elapsed / C.CLOSE_DUR)
        local t = easeInCubic(rawT)
        local scale = C.SCALE_TO + (C.SCALE_FROM - C.SCALE_TO) * t
        local alpha = 1.0 - t
        return scale, alpha
    else
        local elapsed = time.elapsedTime - state.confirmOpenTime
        local rawT = math.min(1.0, elapsed / C.OPEN_DUR)
        local t = easeOutCubic(rawT)
        local scale = C.SCALE_FROM + (C.SCALE_TO - C.SCALE_FROM) * t
        local alpha = t
        return scale, alpha
    end
end

-- ======================== Public API ========================

function Panel.init(vg)
    vg_ = vg
    imgTopBg   = nvgCreateImage(vg, "image/UI_MZQD_BJ.png", 0)
    imgPanel   = nvgCreateImage(vg, "image/UI_MZQD_1.png", 0)
    imgEntry   = nvgCreateImage(vg, "image/UI_MZQD_2.png", 0)
    imgBtnBack = nvgCreateImage(vg, "image/UI_AN_FH.png", 0)
    imgTabBg   = nvgCreateImage(vg, "image/UI_AN_1.png", 0)
    imgSlider  = nvgCreateImage(vg, "image/UI_AN_2.png", 0)
    imgBtnSign  = nvgCreateImage(vg, "image/UI_AN_FANG_huang.png", 0)
    imgBtnDone  = nvgCreateImage(vg, "image/UI_AN_FANG_lv.png", 0)
    imgBtnRetro = nvgCreateImage(vg, "image/UI_AN_FANG_hong.png", 0)
    imgLock     = nvgCreateImage(vg, "image/ICON_GN_BAN.png", 0)
    -- 每日签到图片
    imgDailyTopBg    = nvgCreateImage(vg, "image/UI_MRQD_BJ.png", 0)
    imgDailyPanel    = nvgCreateImage(vg, "image/UI_MRQD_1.png", 0)
    imgDailyEntry    = nvgCreateImage(vg, "image/UI_MRQD_2.png", 0)
    imgDailyEntryAct = nvgCreateImage(vg, "image/UI_MRQD_3.png", 0)
    imgCheckmark     = nvgCreateImage(vg, "image/UI_icon_GOU.png", 0)
    imgMissedStamp   = nvgCreateImage(vg, "image/UI_JSJM_CZZ.png", 0)
    imgDailySignBtn  = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    -- 确认弹窗图片
    imgConfirmBg  = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    imgArrowIcon  = nvgCreateImage(vg, "image/UI_TJP_JIANTOU.png", 0)
    imgRedDot     = nvgCreateImage(vg, "image/ICON_HD.png", 0)
    ImageCache.init(vg)
    print("[SignInPanel] init OK")
end

--- 设置服务端推送的签到数据（由 Client.lua 调用）
function Panel.setSignInData(data)
    signinData_ = data
    refreshDisplayData()
    print("[SignInPanel] setSignInData OK")
end

--- 注入 sendAction 回调（由 Client.lua 调用）
function Panel.setSendAction(fn)
    sendAction_ = fn
end

--- 设置当前区服开服时间（由 Client.lua 在选服/重连时调用）
---@param openTime number UTC 时间戳（os.time 格式），0 表示未设置
function Panel.setServerOpenTime(openTime)
    serverOpenTime_ = openTime or 0
    -- 开服时间变更后立即重建展示数据，确保当天/剩余时间正确
    refreshDisplayData()
end

--- 获取当前缓存的开服时间
---@return number
function Panel.getServerOpenTime()
    return serverOpenTime_
end

function Panel.open()
    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    require("systems.GameSFX").playUIMove(1)
    state.scrollY = 0
    state.dragging = false
    state.tab = "weekly"
    state.tabFrom = "weekly"
    state.tabSwitchTime = 0
    refreshDisplayData()  -- 每次打开时从最新服务端数据重建展示数据
    -- 请求服务端检查签到周期是否过期（跨周/跨月时触发重置并推送最新数据）
    if sendAction_ then
        sendAction_(Protocol.ACTION_TYPES.GET_SIGNIN_STATE, {})
    end
    print("[SignInPanel] open")
end

function Panel.close()
    if state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    state.dragging = false
    print("[SignInPanel] close")
end

function Panel.isOpen()
    return state.open
end

--- 返回打开/关闭动画进度 (0=完全关闭, 1=完全打开)
--- 用于 Client.lua 在动画期间渐变隐藏 TopBar/BottomNav
function Panel.getAnimProgress()
    if not state.open then return 0 end
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        local rawT = math.min(1.0, elapsed / ANIM_CLOSE_DUR)
        return 1 - easeInCubic(rawT)
    else
        local elapsed = time.elapsedTime - state.openTime
        local rawT = math.min(1.0, elapsed / ANIM_OPEN_DUR)
        return easeOutCubic(rawT)
    end
end

function Panel.update(dt)
    -- 关闭动画结束后真正关闭
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        if elapsed >= ANIM_CLOSE_DUR then
            state.open = false
            state.closing = false
            print("[SignInPanel] closed (anim done)")
        end
    end
    -- 确认弹窗关闭动画
    if state.confirmClosing then
        local elapsed = time.elapsedTime - state.confirmCloseTime
        if elapsed >= CONFIRM.CLOSE_DUR then
            state.confirmOpen = false
            state.confirmClosing = false
            state.confirmItem = nil
            state.confirmSource = nil
        end
    end
end

-- ======================== 每日签到格子绘制辅助 ========================

--- 计算每日签到第 idx 个格子的中心坐标 (1-based)
local function dailyGridPos(idx)
    local col = (idx - 1) % DAILY_GRID.COLS           -- 0..4
    local row = math.floor((idx - 1) / DAILY_GRID.COLS)  -- 0..n
    local cx = DAILY_GRID.FIRST_CX + col * DAILY_GRID.STEP_X
    local cy = DAILY_GRID.FIRST_CY + row * DAILY_GRID.STEP_Y
    return cx, cy
end

--- 绘制外发光（多层矩形 stroke 模拟柔和外发光，参考觉醒面板连接线发光）
local function drawGlow(vg, cx, cy, w, h)
    local G = DAILY_GRID
    local halfW, halfH = w * 0.5, h * 0.5
    local glowR, glowG, glowB = G.GLOW_R, G.GLOW_G, G.GLOW_B
    local glowBaseAlpha = G.GLOW_BASE_ALPHA
    local glowWidth = G.GLOW_WIDTH
    local layers = G.GLOW_LAYERS

    -- 从外到内逐层绘制，总距离平滑衰减（与觉醒连接线一致）
    for layer = layers, 1, -1 do
        local t = layer / layers  -- 1.0(最外) → 接近0(最内)
        local alpha = glowBaseAlpha * (1.0 - t)  -- 线性衰减：最内层最亮，最外层趋近0
        local strokeW = 2 + glowWidth * 2 * t  -- 从内 2px 到外 glowWidth*2
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - halfW, cy - halfH, w, h, 4)
        nvgStrokeColor(vg, nvgRGBA(glowR, glowG, glowB, math.floor(alpha + 0.5)))
        nvgStrokeWidth(vg, strokeW)
        nvgStroke(vg)
    end
end

--- 绘制每日签到面板的格子内容（在 nvgTranslate 之后调用）
local function drawDailyGrid(vg)
    local data = DAILY_DATA
    local G = DAILY_GRID

    for i, item in ipairs(data) do
        local cx, cy = dailyGridPos(i)
        local screenCY = cy - state.scrollY

        -- 可见性粗检
        if screenCY >= DAILY_CLIP.TOP - G.ITEM_H and screenCY <= DAILY_CLIP.BOT + G.ITEM_H then
            local isAvailable = (item.status == "available")

            -- 发光效果（仅可签到）
            if isAvailable then
                drawGlow(vg, cx, cy, G.ITEM_W, G.ITEM_H)
            end

            -- 格子背景
            local bgImg = isAvailable and imgDailyEntryAct or imgDailyEntry
            DrawUtil.drawImageCentered(vg, bgImg, cx, cy, G.ITEM_W, G.ITEM_H, 1.0)

            -- 奖励图标
            local resImg = getResIcon(item.reward.type)
            if resImg and resImg >= 0 then
                DrawUtil.drawImageCentered(vg, resImg,
                    cx + G.ICON_DX, cy + G.ICON_DY, G.ICON_W, G.ICON_H, 1.0)
            end

            -- 数量角标（图标右下角）
            local amtStr = tostring(item.reward.amount or 1)
            local badgeX = cx + G.ICON_DX + G.ICON_W * 0.5 - 4
            local badgeY = cy + G.ICON_DY + G.ICON_H * 0.5 - 4
            DrawUtil.drawTextStroke(vg, badgeX, badgeY, amtStr,
                G.BADGE_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM,
                255, 255, 255, G.BADGE_SW)

            -- 天数值
            if isAvailable then
                -- 可签到：金色无描边
                nvgFontFace(vg, "sans"); nvgFontSize(vg, G.DAY_FONT)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(G.DAY_ACTIVE_R, G.DAY_ACTIVE_G, G.DAY_ACTIVE_B, 255))
                nvgText(vg, cx + G.DAY_DX, cy + G.DAY_DY, tostring(item.day), nil)
            else
                -- 其他状态：白色+描边
                DrawUtil.drawTextStroke(vg, cx + G.DAY_DX, cy + G.DAY_DY,
                    tostring(item.day),
                    G.DAY_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    255, 255, 255, G.DAY_STROKE_W,
                    { strokeColor = { G.DAY_STROKE_R, G.DAY_STROKE_G, G.DAY_STROKE_B } })
            end

            -- 已签到：黑色遮罩 + 勾号
            if item.status == "claimed" then
                nvgBeginPath(vg)
                nvgRect(vg, cx - G.ITEM_W * 0.5, cy - G.ITEM_H * 0.5, G.ITEM_W, G.ITEM_H)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))  -- 50%
                nvgFill(vg)
                DrawUtil.drawImageCentered(vg, imgCheckmark,
                    cx + G.CHECK_DX, cy + G.CHECK_DY, G.CHECK_W, G.CHECK_H, 1.0)
            end

            -- 已错过：补签戳章 + 文字 + 钻石消耗提示
            if item.status == "missed" then
                DrawUtil.drawImageCentered(vg, imgMissedStamp,
                    cx + G.MISS_DX, cy + G.MISS_DY, G.MISS_W, G.MISS_H, 1.0)
                nvgFontFace(vg, "sans"); nvgFontSize(vg, 30)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, cx + G.MISS_DX, cy + G.MISS_TEXT_DY, "补签", nil)
            end
        end
    end
end

-- ======================== 每周签到绘制 ========================

local function drawWeeklyContent(vg, skipTopBg)
    -- 1. 顶部背景图（顶端对齐）—— 动画时由上层单独绘制
    if not skipTopBg then
        DrawUtil.drawImageCentered(vg, imgTopBg, TOP_BG.CX, TOP_BG.CY, TOP_BG.W, TOP_BG.H, 1.0)
        -- 刷新时间文本（跟随顶部背景）
        local remainSec = SignInConfig.getWeeklyRemainSeconds(serverOpenTime_)
        local timeStr = SignInConfig.formatRemainTime(remainSec)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 38)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0xb4, 0xff, 0xb0, 255))
        nvgText(vg, 190, 468, "刷新时间", nil)
        nvgFillColor(vg, nvgRGBA(0x17, 0x62, 0x1c, 255))
        nvgText(vg, 442, 468, timeStr, nil)
    end

    -- 2. 下方九宫格面板背景
    DrawUtil.drawNineSlice(vg, imgPanel,
        PANEL.CX - PANEL.W * 0.5, PANEL.CY - PANEL.H * 0.5,
        PANEL.W, PANEL.H, PANEL.IT, PANEL.IR, PANEL.IB, PANEL.IL)

    -- 3. 签到条目列表（可滚动裁剪）
    local data = WEEKLY_DATA
    local count = #data
    local totalH = count * ENTRY.STEP - ENTRY.GAP
    local maxScroll = math.max(0, totalH - CLIP.H)
    state.scrollY = math.max(0, math.min(state.scrollY, maxScroll))

    nvgSave(vg)
    nvgScissor(vg, 0, CLIP.TOP, DESIGN_W, CLIP.H)
    nvgTranslate(vg, 0, -state.scrollY)

    for i, item in ipairs(data) do
        local cy = ENTRY.FIRST_CY + (i - 1) * ENTRY.STEP
        local screenCY = cy - state.scrollY

        if screenCY >= CLIP.TOP - ENTRY.H and screenCY <= CLIP.BOT + ENTRY.H then
            DrawUtil.drawImageCentered(vg, imgEntry, ENTRY.CX, cy, ENTRY.W, ENTRY.H, 1.0)

            DrawUtil.drawTextStroke(vg, ENTRY.DAY_X, cy + ENTRY.DAY_Y_OFF,
                tostring(item.day),
                ENTRY.DAY_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, ENTRY.DAY_SW,
                { strokeColor = { ENTRY.DAY_SR, ENTRY.DAY_SG, ENTRY.DAY_SB } })

            local def = RESOURCE_DEFS[item.reward.type]
            if def then
                local qBgImg = ImageCache.getQualityBg(def.quality)
                if qBgImg and qBgImg >= 0 then
                    DrawUtil.drawImageCentered(vg, qBgImg,
                        ENTRY.ICON_CX, cy + ENTRY.ICON_CY_OFF,
                        ENTRY.FRAME_W, ENTRY.FRAME_H, 1.0)
                end
                local resImg = getResIcon(item.reward.type)
                if resImg and resImg >= 0 then
                    DrawUtil.drawImageCentered(vg, resImg,
                        ENTRY.ICON_CX, cy + ENTRY.ICON_CY_OFF,
                        ENTRY.ICON_W, ENTRY.ICON_H, 1.0)
                end
            end

            local amtStr = tostring(item.reward.amount or 1)
            local badgeX = ENTRY.ICON_CX + ENTRY.FRAME_W * 0.5 - 8
            local badgeY = cy + ENTRY.ICON_CY_OFF + ENTRY.FRAME_H * 0.5 - 8
            DrawUtil.drawTextStroke(vg, badgeX, badgeY, amtStr,
                ENTRY.BADGE_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM,
                255, 255, 255, ENTRY.BADGE_SW)

            -- 第二列锁图标（常态显示，代表未来开放的第二份奖励）
            DrawUtil.drawImageCentered(vg, imgLock,
                ENTRY.LOCK_CX, cy + ENTRY.LOCK_CY_OFF,
                ENTRY.LOCK_W, ENTRY.LOCK_H, 1.0)

            -- 右侧按钮（所有状态都显示按钮）
            local btnImg, btnText
            if item.status == "available" or item.status == "locked" then
                btnImg = imgBtnSign;  btnText = "签到"
            elseif item.status == "claimed" then
                btnImg = imgBtnDone;  btnText = "已领取"
            else -- "missed"
                btnImg = imgBtnRetro; btnText = "补签"
            end

            DrawUtil.drawNineSlice(vg, btnImg,
                ENTRY.BTN_CX - ENTRY.BTN_W * 0.5,
                cy + ENTRY.BTN_CY_OFF - ENTRY.BTN_H * 0.5,
                ENTRY.BTN_W, ENTRY.BTN_H,
                ENTRY.BTN_INSET, ENTRY.BTN_INSET, ENTRY.BTN_INSET, ENTRY.BTN_INSET)

            nvgFontFace(vg, "sans"); nvgFontSize(vg, ENTRY.BTN_FONT)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, ENTRY.BTN_TEXT_A))
            nvgText(vg, ENTRY.BTN_CX, cy + ENTRY.BTN_CY_OFF, btnText, nil)

            -- locked 状态：叠加黑色 50% 遮罩
            if item.status == "locked" then
                nvgBeginPath(vg)
                nvgRect(vg, ENTRY.CX - ENTRY.W * 0.5, cy - ENTRY.H * 0.5,
                    ENTRY.W, ENTRY.H)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))  -- 50%
                nvgFill(vg)
            end
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)
end

-- ======================== 每日签到绘制 ========================

local function drawDailyContent(vg, skipTopBg)
    -- 1. 每日顶部背景图（顶端对齐）—— 动画时由上层单独绘制
    if not skipTopBg then
        DrawUtil.drawImageCentered(vg, imgDailyTopBg,
            DAILY_TOP_BG.CX, DAILY_TOP_BG.CY, DAILY_TOP_BG.W, DAILY_TOP_BG.H, 1.0)
        -- 刷新时间文本（跟随顶部背景）
        local remainSec = SignInConfig.getServerPeriodRemainSeconds(serverOpenTime_)
        local timeStr = SignInConfig.formatRemainTime(remainSec)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 38)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0xe2, 0xb0, 0xff, 255))
        nvgText(vg, 190, 468, "刷新时间", nil)
        nvgFillColor(vg, nvgRGBA(0x31, 0x17, 0x62, 255))
        nvgText(vg, 442, 468, timeStr, nil)
    end

    -- 2. 每日下方九宫格面板背景
    DrawUtil.drawNineSlice(vg, imgDailyPanel,
        DAILY_PANEL.CX - DAILY_PANEL.W * 0.5, DAILY_PANEL.CY - DAILY_PANEL.H * 0.5,
        DAILY_PANEL.W, DAILY_PANEL.H,
        DAILY_PANEL.IT, DAILY_PANEL.IR, DAILY_PANEL.IB, DAILY_PANEL.IL)

    -- 3. 网格区域（可滚动裁剪）
    local data = DAILY_DATA
    local rows = math.ceil(#data / DAILY_GRID.COLS)
    local totalH = rows * DAILY_GRID.STEP_Y - DAILY_GRID.GAP_Y
    local clipContentH = DAILY_CLIP.BOT - (DAILY_GRID.FIRST_CY - DAILY_GRID.ITEM_H * 0.5)
    local maxScroll = math.max(0, totalH - clipContentH)
    state.scrollY = math.max(0, math.min(state.scrollY, maxScroll))

    nvgSave(vg)
    nvgScissor(vg, 0, DAILY_CLIP.TOP, DESIGN_W, DAILY_CLIP.H)
    nvgTranslate(vg, 0, -state.scrollY)

    drawDailyGrid(vg)

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 4. 签到按钮（固定位置，不随滚动）
    -- 查找当前是否有 available 状态的条目
    local hasAvailable = false
    for _, item in ipairs(data) do
        if item.status == "available" then hasAvailable = true; break end
    end

    if hasAvailable then
        local _bf1 = BF.begin(vg, "sip_daily_sign", DAILY_SIGN_BTN.CX, DAILY_SIGN_BTN.CY, DAILY_SIGN_BTN.W, DAILY_SIGN_BTN.H)
        DrawUtil.drawNineSlice(vg, imgDailySignBtn,
            DAILY_SIGN_BTN.CX - DAILY_SIGN_BTN.W * 0.5,
            DAILY_SIGN_BTN.CY - DAILY_SIGN_BTN.H * 0.5,
            DAILY_SIGN_BTN.W, DAILY_SIGN_BTN.H,
            DAILY_SIGN_BTN.INSET, DAILY_SIGN_BTN.INSET,
            DAILY_SIGN_BTN.INSET, DAILY_SIGN_BTN.INSET)

        nvgFontFace(vg, "sans"); nvgFontSize(vg, DAILY_SIGN_BTN.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, DAILY_SIGN_BTN.TEXT_A))
        nvgText(vg, DAILY_SIGN_BTN.CX, DAILY_SIGN_BTN.CY, "签到", nil)
        BF.finish(vg, _bf1)
    end
end

-- ======================== Tab 红点判断 ========================

--- 指定 tab 是否有可领取的签到奖励
---@param tabKey string "daily"|"weekly"
---@return boolean
local function hasTabClaimable(tabKey)
    if not signinData_ then
        refreshDisplayData()
    end
    local data = (tabKey == "daily") and DAILY_DATA or WEEKLY_DATA
    for _, item in ipairs(data) do
        if item.status == "available" then return true end
    end
    return false
end

-- ======================== 补签确认弹窗绘制 ========================

local function drawConfirmDialog(vg)
    if not state.confirmOpen or not state.confirmItem then return end
    local item = state.confirmItem
    local C = CONFIRM
    local pScale, pAlpha = getConfirmAnim()
    if pAlpha <= 0 then return end

    -- 1) 全屏黑色遮罩（跟随动画 alpha）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * pAlpha)))
    nvgFill(vg)

    -- 2) 弹窗 scale + fade 变换
    nvgSave(vg)
    nvgTranslate(vg, C.BG_CX, C.BG_CY)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -C.BG_CX, -C.BG_CY)
    nvgGlobalAlpha(vg, pAlpha)

    -- 3) 确认框背景（九宫格）
    DrawUtil.drawNineSlice(vg, imgConfirmBg,
        C.BG_CX - C.BG_W * 0.5, C.BG_CY - C.BG_H * 0.5,
        C.BG_W, C.BG_H, 40, 40, 40, 40)

    -- 4) 标题 "补签确认"
    DrawUtil.drawTextStroke(vg, C.TITLE_CX, C.TITLE_CY, "补签确认",
        C.TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, C.TITLE_SW,
        { strokeColor = { C.TITLE_SR, C.TITLE_SG, C.TITLE_SB } })

    -- 5) 副标题
    nvgFontFace(vg, "sans"); nvgFontSize(vg, C.SUB_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C.SUB_R, C.SUB_G, C.SUB_B, 255))
    nvgText(vg, C.SUB_CX, C.SUB_CY, "是否消耗钻石进行补签？", nil)

    -- 6) 内容背景框（纯黑 5% 圆角矩形）
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        C.CONTENT_CX - C.CONTENT_W * 0.5,
        C.CONTENT_CY - C.CONTENT_H * 0.5,
        C.CONTENT_W, C.CONTENT_H, 12)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))
    nvgFill(vg)

    -- 7) 箭头分隔符
    DrawUtil.drawImageCentered(vg, imgArrowIcon,
        C.ARROW_CX, C.ARROW_CY, C.ARROW_W, C.ARROW_H, 1.0)

    -- 8) 左侧消耗（钻石）
    local diamondDef = RESOURCE_DEFS["diamond"]
    local costQBg = ImageCache.getQualityBg(diamondDef.quality)
    if costQBg and costQBg >= 0 then
        DrawUtil.drawImageCentered(vg, costQBg,
            C.COST_CX, C.COST_CY, C.COST_ICON_SIZE, C.COST_ICON_SIZE, 1.0)
    end
    local diamondIcon = getResIcon("diamond")
    if diamondIcon and diamondIcon >= 0 then
        DrawUtil.drawImageCentered(vg, diamondIcon,
            C.COST_CX, C.COST_CY, C.COST_ICON_SIZE, C.COST_ICON_SIZE, 1.0)
    end
    DrawUtil.drawTextStroke(vg,
        C.COST_CX + C.BADGE_OX, C.COST_CY + C.BADGE_OY,
        tostring(RETRO_SIGN_COST),
        C.BADGE_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        255, 255, 255, C.BADGE_SW, { strokeColor = { 0, 0, 0 } })

    -- 9) 右侧获得（奖励物品）
    local rewardDef = RESOURCE_DEFS[item.reward.type]
    if rewardDef then
        local rewardQBg = ImageCache.getQualityBg(rewardDef.quality)
        if rewardQBg and rewardQBg >= 0 then
            DrawUtil.drawImageCentered(vg, rewardQBg,
                C.REWARD_CX, C.REWARD_CY, C.REWARD_ICON_SIZE, C.REWARD_ICON_SIZE, 1.0)
        end
        local rewardImg = getResIcon(item.reward.type)
        if rewardImg and rewardImg >= 0 then
            DrawUtil.drawImageCentered(vg, rewardImg,
                C.REWARD_CX, C.REWARD_CY, C.REWARD_ICON_SIZE, C.REWARD_ICON_SIZE, 1.0)
        end
    end
    DrawUtil.drawTextStroke(vg,
        C.REWARD_CX + C.BADGE_OX, C.REWARD_CY + C.BADGE_OY,
        tostring(item.reward.amount),
        C.BADGE_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        255, 255, 255, C.BADGE_SW, { strokeColor = { 0, 0, 0 } })

    -- 10) 确认按钮（黄色）
    local _bf2 = BF.begin(vg, "sip_confirm", C.BTN_CX, C.BTN_CY, C.BTN_W, C.BTN_H)
    DrawUtil.drawNineSlice(vg, imgDailySignBtn,
        C.BTN_CX - C.BTN_W * 0.5, C.BTN_CY - C.BTN_H * 0.5,
        C.BTN_W, C.BTN_H,
        C.BTN_INSET, C.BTN_INSET, C.BTN_INSET, C.BTN_INSET)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, C.BTN_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C.BTN_R, C.BTN_G, C.BTN_B, 255))
    nvgText(vg, C.BTN_CX, C.BTN_CY, "确认补签", nil)
    BF.finish(vg, _bf2)

    nvgRestore(vg)
end

-- ======================== 主绘制 ========================

function Panel.draw(vg)
    if not state.open then return end

    -- ── 动画进度 ──
    local progress
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        local rawT = math.min(1.0, elapsed / ANIM_CLOSE_DUR)
        progress = 1 - easeInCubic(rawT)
    else
        local elapsed = time.elapsedTime - state.openTime
        local rawT = math.min(1.0, elapsed / ANIM_OPEN_DUR)
        progress = easeOutCubic(rawT)
    end
    local upperOY = -UPPER_SLIDE_DIST * (1 - progress)
    local lowerOY =  LOWER_SLIDE_DIST * (1 - progress)
    local overlayAlpha = math.floor(180 * progress)

    -- ── 全屏暗色遮罩 ──
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
    nvgFill(vg)

    -- ── 上半部分：顶部背景图（从上方滑入） ──
    nvgSave(vg)
    nvgTranslate(vg, 0, upperOY)
    if state.tab == "daily" then
        DrawUtil.drawImageCentered(vg, imgDailyTopBg,
            DAILY_TOP_BG.CX, DAILY_TOP_BG.CY, DAILY_TOP_BG.W, DAILY_TOP_BG.H, 1.0)
        -- 每日刷新时间文本
        do
            local remainSec = SignInConfig.getServerPeriodRemainSeconds(serverOpenTime_)
            local timeStr = SignInConfig.formatRemainTime(remainSec)
            nvgFontFace(vg, "sans"); nvgFontSize(vg, 38)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0xe2, 0xb0, 0xff, 255))
            nvgText(vg, 190, 468, "刷新时间", nil)
            nvgFillColor(vg, nvgRGBA(0x31, 0x17, 0x62, 255))
            nvgText(vg, 442, 468, timeStr, nil)
        end
    else
        DrawUtil.drawImageCentered(vg, imgTopBg, TOP_BG.CX, TOP_BG.CY, TOP_BG.W, TOP_BG.H, 1.0)
        -- 每周刷新时间文本
        do
            local remainSec = SignInConfig.getWeeklyRemainSeconds(serverOpenTime_)
            local timeStr = SignInConfig.formatRemainTime(remainSec)
            nvgFontFace(vg, "sans"); nvgFontSize(vg, 38)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0xb4, 0xff, 0xb0, 255))
            nvgText(vg, 190, 468, "刷新时间", nil)
            nvgFillColor(vg, nvgRGBA(0x17, 0x62, 0x1c, 255))
            nvgText(vg, 442, 468, timeStr, nil)
        end
    end
    nvgRestore(vg)

    -- ── 下半部分：面板内容 + 返回 + Tab（从下方滑入） ──
    nvgSave(vg)
    nvgTranslate(vg, 0, lowerOY)

    -- 根据当前 tab 绘制对应内容（跳过顶部背景）
    if state.tab == "daily" then
        drawDailyContent(vg, true)
    else
        drawWeeklyContent(vg, true)
    end

    -- 返回按钮
    DrawUtil.drawImageCentered(vg, imgBtnBack, BTN_BACK.CX, BTN_BACK.CY, BTN_BACK.W, BTN_BACK.H, 1.0)

    -- Tab 背景
    DrawUtil.drawImageCentered(vg, imgTabBg, TAB.BG_CX, TAB.BG_CY, TAB.BG_W, TAB.BG_H, 1.0)

    -- Tab 滑块（带动画）
    local tabIdx = getTabIndex(state.tab)
    local fromIdx = getTabIndex(state.tabFrom)
    local tabElapsed = time.elapsedTime - state.tabSwitchTime
    local tabT = math.min(1.0, tabElapsed / TAB.ANIM_DUR)
    local tabEased = easeInOutCubic(tabT)

    local targetItem = TAB_ITEMS[tabIdx]
    local fromItem = TAB_ITEMS[fromIdx]
    local sliderCX = fromItem.cx + (targetItem.cx - fromItem.cx) * tabEased
    local sliderCY = fromItem.cy + (targetItem.cy - fromItem.cy) * tabEased

    DrawUtil.drawNineSlice(vg, imgSlider,
        sliderCX - TAB.SLIDER_W * 0.5, sliderCY - TAB.SLIDER_H * 0.5,
        TAB.SLIDER_W, TAB.SLIDER_H,
        TAB.INSET_TOP, TAB.INSET_RIGHT, TAB.INSET_BOTTOM, TAB.INSET_LEFT)

    -- Tab 文字 + 红点
    for i, item in ipairs(TAB_ITEMS) do
        local isActive = (state.tab == item.key)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, TAB.FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(TAB.ACTIVE_R, TAB.ACTIVE_G, TAB.ACTIVE_B, 255))
        else
            nvgFillColor(vg, nvgRGBA(TAB.INACTIVE_R, TAB.INACTIVE_G, TAB.INACTIVE_B, 255))
        end
        nvgText(vg, item.textX, item.textY, item.name, nil)

        -- 红点：有可领取签到时显示（选中也保留）
        if imgRedDot >= 0 and hasTabClaimable(item.key) then
            local upSize = 30
            local textHalfW = nvgTextBounds(vg, 0, 0, item.name) * 0.5
            local upX = item.textX + textHalfW + 10
            local upY = item.textY - 18
            DrawUtil.drawImageCentered(vg, imgRedDot, upX, upY, upSize, upSize, 1.0)
        end
    end

    nvgRestore(vg)

    -- ── 补签确认弹窗（最顶层，不参与上下滑动） ──
    drawConfirmDialog(vg)
end

-- ======================== 输入处理 ========================

function Panel.handleInput(dx, dy)
    if not state.open then return false end
    if state.closing then return true end  -- 关闭动画中，消费事件但不处理

    -- === 补签确认弹窗输入（最高优先级） ===
    if state.confirmOpen and not state.confirmClosing then
        -- 同帧保护：防止 openConfirmDialog() 同帧的点击事件立即关闭弹窗
        if time.elapsedTime - state.confirmOpenTime < 0.05 then return true end

        -- 确认按钮
        if DrawUtil.hitTest(dx, dy, CONFIRM.BTN_CX, CONFIRM.BTN_CY,
                CONFIRM.BTN_W, CONFIRM.BTN_H) then
            BF.trigger("sip_confirm")
            local item = state.confirmItem
            local source = state.confirmSource
            if item and sendAction_ then
                sendAction_(Protocol.ACTION_TYPES.RETRO_SIGN, {
                    day = item.day,
                    source = source,  -- "daily" | "weekly"
                })
                local prefix = source == "daily" and "每日" or ""
                print("[SignInPanel] " .. prefix .. "补签第 " .. item.day .. " 天 → 发送服务端")
            end
            closeConfirmDialog()
            return true
        end
        -- 点击弹窗外部关闭
        local bgL = CONFIRM.BG_CX - CONFIRM.BG_W * 0.5
        local bgR = CONFIRM.BG_CX + CONFIRM.BG_W * 0.5
        local bgT = CONFIRM.BG_CY - CONFIRM.BG_H * 0.5
        local bgB = CONFIRM.BG_CY + CONFIRM.BG_H * 0.5
        if dx < bgL or dx > bgR or dy < bgT or dy > bgB then
            closeConfirmDialog()
        end
        return true  -- 弹窗打开时消费所有事件
    end
    if state.confirmClosing then return true end  -- 关闭动画中也消费事件

    -- 返回按钮
    if DrawUtil.hitTest(dx, dy, BTN_BACK.CX, BTN_BACK.CY, BTN_BACK.W, BTN_BACK.H) then
        Panel.close()
        return true
    end

    -- Tab 切换
    for i, item in ipairs(TAB_ITEMS) do
        if DrawUtil.hitTest(dx, dy, item.cx, item.cy, TAB.SLIDER_W, TAB.SLIDER_H) then
            if state.tab ~= item.key then
                state.tabFrom = state.tab
                state.tabSwitchTime = time.elapsedTime
                state.tab = item.key
                state.scrollY = 0  -- 切换 tab 重置滚动
                print("[SignInPanel] 切换到 " .. item.name)
            end
            return true
        end
    end

    -- === 每日签到输入处理 ===
    if state.tab == "daily" then
        -- 签到按钮（固定位置，不随滚动）
        if DrawUtil.hitTest(dx, dy, DAILY_SIGN_BTN.CX, DAILY_SIGN_BTN.CY,
                DAILY_SIGN_BTN.W, DAILY_SIGN_BTN.H) then
            BF.trigger("sip_daily_sign")
            -- 找到第一个 available 条目并发送签到请求
            for _, item in ipairs(DAILY_DATA) do
                if item.status == "available" then
                    if sendAction_ then
                        sendAction_(Protocol.ACTION_TYPES.DAILY_SIGN, { day = item.day })
                        print("[SignInPanel] 每日签到第 " .. item.day .. " 天 → 发送服务端")
                    end
                    break
                end
            end
            return true
        end

        -- 网格区域点击（补签）
        if dy >= DAILY_CLIP.TOP and dy <= DAILY_CLIP.BOT then
            local localY = dy + state.scrollY
            for i, item in ipairs(DAILY_DATA) do
                local cx, cy = dailyGridPos(i)
                local halfW = DAILY_GRID.ITEM_W * 0.5
                local halfH = DAILY_GRID.ITEM_H * 0.5
                if dx >= cx - halfW and dx <= cx + halfW
                    and localY >= cy - halfH and localY <= cy + halfH then
                    if item.status == "missed" then
                        openConfirmDialog(item, "daily")
                    elseif item.status == "claimed" then
                        print("[SignInPanel] 每日第 " .. item.day .. " 天已领取")
                    end
                    return true
                end
            end
        end

        return true  -- 消费事件防穿透
    end

    -- === 每周签到输入处理 ===
    if dy >= CLIP.TOP and dy <= CLIP.BOT then
        local localY = dy + state.scrollY
        for i, item in ipairs(WEEKLY_DATA) do
            local cy = ENTRY.FIRST_CY + (i - 1) * ENTRY.STEP
            local btnL = ENTRY.BTN_CX - ENTRY.BTN_W * 0.5
            local btnR = ENTRY.BTN_CX + ENTRY.BTN_W * 0.5
            local btnT = cy + ENTRY.BTN_CY_OFF - ENTRY.BTN_H * 0.5
            local btnB = cy + ENTRY.BTN_CY_OFF + ENTRY.BTN_H * 0.5
            if dx >= btnL and dx <= btnR and localY >= btnT and localY <= btnB then
                if item.status == "available" then
                    if sendAction_ then
                        sendAction_(Protocol.ACTION_TYPES.WEEKLY_SIGN, { day = item.day })
                        print("[SignInPanel] 每周签到第 " .. item.day .. " 天 → 发送服务端")
                    end
                elseif item.status == "missed" then
                    openConfirmDialog(item, "weekly")
                elseif item.status == "locked" then
                    -- 锁定状态不可操作
                else
                    print("[SignInPanel] 第 " .. item.day .. " 天已领取")
                end
                return true
            end
        end
    end

    return true  -- 消费事件防穿透
end

--- 是否有可领取的签到奖励（每周或每日任意一条 status=="available"）
---@return boolean
function Panel.hasClaimable()
    -- 确保数据已刷新
    if signinData_ then
        refreshDisplayData()
    end
    for _, item in ipairs(WEEKLY_DATA) do
        if item.status == "available" then return true end
    end
    for _, item in ipairs(DAILY_DATA) do
        if item.status == "available" then return true end
    end
    return false
end

function Panel.handleDragBegin(dx, dy)
    if not state.open or state.closing then return not state.open and false or true end
    if dy >= CLIP.TOP and dy <= CLIP.BOT then
        state.dragging = true
        state.lastDragY = dy
    end
    return true
end

function Panel.handleDragMove(dx, dy)
    if not state.open or state.closing then return not state.open and false or true end
    if state.dragging then
        state.scrollY = state.scrollY + (state.lastDragY - dy)
        state.lastDragY = dy
    end
    return true
end

function Panel.handleDragEnd(dx, dy)
    if not state.open or state.closing then return not state.open and false or true end
    state.dragging = false
    return true
end

function Panel.handleScroll(wheel)
    if not state.open or state.closing then return not state.open and false or true end
    state.scrollY = state.scrollY - wheel * 60
    return true
end

return Panel
