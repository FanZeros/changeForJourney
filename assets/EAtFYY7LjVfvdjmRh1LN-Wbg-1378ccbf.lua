-- ============================================================================
-- TaskPanel - 任务面板（成就/周任务/日任务 切换）
-- 全屏面板：顶部背景 + 标题框 + 九宫格下方面板 + 任务条目列表 + 底部返回&Tab
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- ============================================================================

local GameConfig       = require("config.GameConfig")
local TaskConfig       = require("config.TaskConfig")
local Protocol         = require("shared.Protocol")
local DrawUtil         = require("core.DrawUtil")
local NumberUtil       = require("core.NumberUtil")
local ImageCache       = require("ui.ImageCache")
local RewardPopup      = require("ui.RewardPopup")
local BF               = require("systems.ButtonFeedback")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格

local Panel = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量 ========================

-- 1. 顶部背景图 UI_RW_BJ.png — 顶端对齐 1080×641
local TOP_BG = {
    CX = 540, W = 1080, H = 641,
    CY = 641 * 0.5,  -- 320.5  (顶端对齐)
}

-- 2. 标题标签（一模一样复制背包面板标题样式）
--    背景图 UI_TJP_MC.png + 白色文字，无图标
local TITLE = {
    BG_CX = 147, BG_CY = 136, BG_W = 294, BG_H = 123,
    TEXT_CX = 148, TEXT_CY = 130, FONT_SIZE = 50,
    TEXT = "任务",
}

-- 3. 下方背景框 UI_TJP_1.png（九宫格）
local LOWER_PANEL = {
    CX = 540, CY = 1425, W = 1080, H = 1949,
    IT = 200, IR = 10, IB = 200, IL = 10,
}

-- 4. 标题装饰 UI_JJC_BTBJ
local DECO = {
    CX = 540, CY = 614, W = 660, H = 60,
}

-- 5. 区域标题文字 "每日任务"
local SECTION_TITLE = {
    X = 540, Y = 614,
    FONT_SIZE = 40,
    R = 0x45, G = 0x45, B = 0x45,
}

-- 6. 任务条目
local ENTRY = {
    -- 组合背景
    BG_CX = 540, BG_W = 1010, BG_H = 220,
    FIRST_CY = 783,    -- 第一条中心 Y
    GAP = 13,          -- 条目间隔
    -- 品质框
    QUALITY_CX = 140, QUALITY_CY_OFF = -4, QUALITY_W = 160, QUALITY_H = 160,
    -- 奖励图标
    ICON_CX = 142, ICON_CY_OFF = -2, ICON_W = 160, ICON_H = 160,
    -- 数量角标（参考签到面板）
    BADGE_FONT = 40, BADGE_SW = 5,
    -- 需求文本
    DESC_X = 280, DESC_Y_OFF = -36, DESC_FONT = 40, DESC_MAX_W = 490,
    DESC_R = 0x5f, DESC_G = 0x37, DESC_B = 0x37,
    -- 进度条背景
    BAR_BG_CX = 507, BAR_BG_CY_OFF = 29, BAR_BG_W = 460, BAR_BG_H = 26,
    BAR_BG_R = 0x3a, BAR_BG_G = 0x2a, BAR_BG_B = 0x1e, BAR_BG_A = 80,
    BAR_INSET = 5,   -- 内容条与背景间距
    -- 进度文本
    PROG_CX = 507, PROG_CY_OFF = 28, PROG_FONT = 30, PROG_SW = 5,
    -- 状态按钮
    BTN_CX = 886, BTN_CY_OFF = -4, BTN_W = 210, BTN_H = 122,
    BTN_FONT = 50, BTN_TEXT_A = 191,  -- 75% 不透明度
}
ENTRY.STEP = ENTRY.BG_H + ENTRY.GAP  -- 233

-- 裁剪区域：条目区从第一条顶部到 Y2174
local CLIP = {
    TOP = ENTRY.FIRST_CY - ENTRY.BG_H * 0.5,   -- 673
    BOT = 2174,
}
CLIP.H = CLIP.BOT - CLIP.TOP

-- 7. 返回按钮（与铁匠铺一致）
local BTN_BACK = {
    CX = 122, CY = 2308, W = 184, H = 143,
}

-- 8. Tab 栏（与铁匠铺一致，3 个按钮）
local TAB = {
    BG_CX = 639, BG_CY = 2308, BG_W = 810, BG_H = 143,
    SLIDER_W = 277, SLIDER_H = 143,
    INSET_TOP = 10, INSET_BOTTOM = 10, INSET_LEFT = 70, INSET_RIGHT = 70,
    FONT_SIZE = 40,
    TEXT_Y = 2302,
    ACTIVE_R = 0x81, ACTIVE_G = 0x57, ACTIVE_B = 0x3c,
    INACTIVE_R = 255, INACTIVE_G = 255, INACTIVE_B = 255,
    ANIM_DUR = 0.35,
}

local TAB_ITEMS = {
    { key = "daily",       name = "日任务", cx = 372, cy = 2308 },
    { key = "weekly",      name = "周任务", cx = 638, cy = 2308 },
    { key = "achievement", name = "成就",   cx = 905, cy = 2308 },
}

-- 各 tab 对应的区域标题
local TAB_SECTION_TITLES = {
    daily       = "每日任务",
    weekly      = "每周任务",
    achievement = "成就",
}

-- ======================== 滚动参数 ========================

local SCROLL_FRICTION   = 0.90
local SCROLL_MIN_VEL    = 0.5
local SCROLL_WHEEL_STEP = 60

-- ======================== 缓动函数 ========================

local function easeInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    local f = 2 * t - 2; return 0.5 * f * f * f + 1
end

local function easeOutCubic(t)
    local u = 1 - t; return 1 - u * u * u
end

local function easeInCubic(t)
    return t * t * t
end

-- ======================== 图片句柄 ========================

local imgTopBg     = -1  -- UI_RW_BJ.png
local imgTitleBg   = -1  -- UI_TJP_MC.png

local imgDeco      = -1  -- UI_JJC_BTBJ.png
local imgEntryBg   = -1  -- UI_RW_1.png
local imgBarBg     = -1  -- UI_RW_JDT2.png  进度条背景
local imgBarFill   = -1  -- UI_RW_JDT1.png
local imgBtnBack   = -1  -- UI_AN_FH.png
local imgTabBg     = -1  -- UI_AN_1.png

local imgBtnRed    = -1  -- UI_AN_FANG_hong.png  未满足
local imgBtnYellow = -1  -- UI_AN_FANG_huang.png 领取
local imgBtnGreen  = -1  -- UI_AN_FANG_lv.png    已领取
local imgRedDot    = -1  -- ICON_HD.png           红点提示

-- 品质框缓存 [quality] = handle
local qualityBgCache = {}  -- [暗黑化 P2-A] 已废弃：品质框改矢量绘制，保留空表避免未定义引用
-- 奖励图标缓存 [path] = handle
local rewardIconCache = {}

local vg_ = nil

-- ======================== 面板状态 ========================

local state = {
    open      = false,
    closing   = false,
    openTime  = 0,
    closeTime = 0,
    tab       = "daily",       -- "daily" | "weekly" | "achievement"
    tabFrom   = "daily",
    tabSwitchTime = 0,
    scrollY   = 0,
    scrollMax = 0,
    dragging  = false,
    lastDragY = 0,
    scrollVel = 0,
}

-- 任务进度数据（服务端推送）
local serverTaskData = nil  -- 服务端推送的完整 task 模块数据
local sendAction = nil      -- 注入的 sendAction 函数

-- 开关动画参数（与 BlacksmithPage 一致）
local ANIM_OPEN_DUR  = 0.45
local ANIM_CLOSE_DUR = 0.38
local UPPER_SLIDE_DIST = 1200   -- 上半部分从屏幕上方滑入的距离
local LOWER_SLIDE_DIST = 1600   -- 下半部分从屏幕下方滑入的距离

-- ======================== 辅助函数 ========================

local function getTabIndex(key)
    for i, item in ipairs(TAB_ITEMS) do
        if item.key == key then return i end
    end
    return 1  -- 默认日任务
end

--- [暗黑化 P2-A] 品质框改矢量绘制，原 ZBBJ 贴图缓存函数废弃（保留接口名，返回品质号）
local function getQualityBg(quality)
    return quality
end

--- 获取奖励图标（缓存）
local function getRewardIcon(path)
    local cached = rewardIconCache[path]
    if cached then return cached end
    if not vg_ then return -1 end
    local handle = nvgCreateImage(vg_, path, 0)
    rewardIconCache[path] = handle
    return handle
end

--- 获取任务进度（从服务端数据）
local function getProgress(taskId)
    if not serverTaskData then
        return { current = 0, claimed = false }
    end
    local cat = TaskConfig.getCategory(taskId)
    local current = 0
    local claimed = false
    local task = TaskConfig.findById(taskId)
    local condKey = task and task.condKey or taskId

    if cat == "daily" then
        current = (serverTaskData.dailyProg   or {})[condKey] or 0
        claimed = (serverTaskData.dailyClaimed or {})[taskId] == true
    elseif cat == "weekly" then
        current = (serverTaskData.weeklyProg   or {})[condKey] or 0
        claimed = (serverTaskData.weeklyClaimed or {})[taskId] == true
    else -- achievement
        current = (serverTaskData.achProg    or {})[condKey] or 0
        claimed = (serverTaskData.achClaimed or {})[taskId] == true
    end
    return { current = current, claimed = claimed }
end

--- 获取任务状态
local function getTaskStatus(task)
    local prog = getProgress(task.id)
    if prog.claimed then
        return TaskConfig.STATUS.CLAIMED
    elseif prog.current >= task.target then
        return TaskConfig.STATUS.CLAIMABLE
    else
        return TaskConfig.STATUS.LOCKED
    end
end

--- 状态排序优先级：可领取(CLAIMABLE)=1  未完成(LOCKED)=2  已领取(CLAIMED)=3
local STATUS_ORDER = {
    [TaskConfig.STATUS.CLAIMABLE] = 1,
    [TaskConfig.STATUS.LOCKED]    = 2,
    [TaskConfig.STATUS.CLAIMED]   = 3,
}

--- 排好序的列表缓存（按 tab key 索引），数据变更时清空
local sortedCache = {}

--- 获取当前 tab 的任务列表（按状态排序）
local function getTaskList()
    local key = state.tab
    if sortedCache[key] then return sortedCache[key] end

    local source
    if key == "daily" then
        source = TaskConfig.DAILY
    elseif key == "weekly" then
        source = TaskConfig.WEEKLY
    else
        source = TaskConfig.ACHIEVEMENT
    end

    -- 浅拷贝后按状态排序（同状态保持原始顺序）
    local sorted = {}
    for i, t in ipairs(source) do
        sorted[i] = t
    end
    table.sort(sorted, function(a, b)
        local sa = STATUS_ORDER[getTaskStatus(a)] or 2
        local sb = STATUS_ORDER[getTaskStatus(b)] or 2
        if sa ~= sb then return sa < sb end
        return false  -- 同状态保持原始顺序（stable sort tie-break）
    end)

    sortedCache[key] = sorted
    return sorted
end

--- 计算滚动最大值
local function calcScrollMax(count)
    local contentH = count * ENTRY.STEP - ENTRY.GAP
    return math.max(0, contentH - CLIP.H)
end

local function clampScroll()
    state.scrollY = math.max(0, math.min(state.scrollMax, state.scrollY))
end

-- ======================== 绘制：任务条目列表 ========================

local function drawTaskList(vg)
    local tasks = getTaskList()
    local count = #tasks
    state.scrollMax = calcScrollMax(count)
    clampScroll()

    nvgSave(vg)
    nvgScissor(vg, 0, CLIP.TOP, DESIGN_W, CLIP.H)
    nvgTranslate(vg, 0, -state.scrollY)

    for idx, task in ipairs(tasks) do
        local cy = ENTRY.FIRST_CY + (idx - 1) * ENTRY.STEP
        local status = getTaskStatus(task)
        local prog = getProgress(task.id)

        -- 1) 条目背景
        DrawUtil.drawImageCentered(vg, imgEntryBg,
            ENTRY.BG_CX, cy, ENTRY.BG_W, ENTRY.BG_H, 1.0)

        -- 2) 品质框 [暗黑化 P2-A]
        DarkIcon.drawQualityBg(vg, task.reward.quality,
            ENTRY.QUALITY_CX, cy + ENTRY.QUALITY_CY_OFF,
            ENTRY.QUALITY_W, ENTRY.QUALITY_H, 1.0)

        -- 3) 奖励图标
        local icon = getRewardIcon(task.reward.icon)
        if icon and icon >= 0 then
            DrawUtil.drawImageCentered(vg, icon,
                ENTRY.ICON_CX, cy + ENTRY.ICON_CY_OFF,
                ENTRY.ICON_W, ENTRY.ICON_H, 1.0)
        end

        -- 4) 数量角标（参考签到面板: drawTextStroke, 白字黑描边）
        local amtStr = tostring(task.reward.amount)
        local badgeX = ENTRY.ICON_CX + ENTRY.ICON_W * 0.5 - 4
        local badgeY = cy + ENTRY.ICON_CY_OFF + ENTRY.ICON_H * 0.5 - 4
        DrawUtil.drawTextStroke(vg, badgeX, badgeY, amtStr,
            ENTRY.BADGE_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM,
            255, 255, 255, ENTRY.BADGE_SW)

        -- 5) 需求文本（自适应缩放：超宽时缩小字号）
        nvgFontFace(vg, "sans")
        local descFontSize = ENTRY.DESC_FONT
        nvgFontSize(vg, descFontSize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local textW = nvgTextBounds(vg, 0, 0, task.name)
        if textW > ENTRY.DESC_MAX_W then
            descFontSize = math.floor(descFontSize * ENTRY.DESC_MAX_W / textW)
            nvgFontSize(vg, descFontSize)
        end
        nvgFillColor(vg, nvgRGBA(ENTRY.DESC_R, ENTRY.DESC_G, ENTRY.DESC_B, 255))
        nvgText(vg, ENTRY.DESC_X, cy + ENTRY.DESC_Y_OFF, task.name, nil)

        -- 6) 进度条背景（UI_RW_JDT2 图片填充，圆角裁剪）
        local barBgX = ENTRY.BAR_BG_CX - ENTRY.BAR_BG_W * 0.5
        local barBgY = cy + ENTRY.BAR_BG_CY_OFF - ENTRY.BAR_BG_H * 0.5
        local barR = ENTRY.BAR_BG_H * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barBgX, barBgY, ENTRY.BAR_BG_W, ENTRY.BAR_BG_H, barR)
        local bgPat = nvgImagePattern(vg, barBgX, barBgY, ENTRY.BAR_BG_W, ENTRY.BAR_BG_H, 0, imgBarBg, 1.0)
        nvgFillPaint(vg, bgPat)
        nvgFill(vg)

        -- 7) 进度条内容（UI_RW_JDT1 图片填充，带 inset）
        local ratio = math.min(1.0, prog.current / task.target)
        if ratio > 0 then
            local fillX = barBgX + ENTRY.BAR_INSET
            local fillY = barBgY + ENTRY.BAR_INSET
            local fillMaxW = ENTRY.BAR_BG_W - ENTRY.BAR_INSET * 2
            local fillH = ENTRY.BAR_BG_H - ENTRY.BAR_INSET * 2
            local fillW = math.max(fillH, fillMaxW * ratio)  -- 最小为高度（保持圆角）
            local fillR = fillH * 0.5

            nvgSave(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, fillX, fillY, fillW, fillH, fillR)
            nvgIntersectScissor(vg, fillX, fillY, fillW, fillH)

            -- 用图片做进度条纹理
            local pat = nvgImagePattern(vg, fillX, fillY, fillMaxW, fillH, 0, imgBarFill, 1.0)
            nvgFillPaint(vg, pat)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, fillX, fillY, fillW, fillH, fillR)
            nvgFill(vg)
            nvgRestore(vg)
        end

        -- 8) 进度数值文本（白字黑描边）
        local progText = tostring(prog.current) .. "/" .. tostring(task.target)
        DrawUtil.drawTextStroke(vg,
            ENTRY.PROG_CX, cy + ENTRY.PROG_CY_OFF, progText,
            ENTRY.PROG_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, ENTRY.PROG_SW)

        -- 9) 状态按钮
        local btnImg, btnText
        if status == TaskConfig.STATUS.LOCKED then
            btnImg = imgBtnRed
            btnText = "未满足"
        elseif status == TaskConfig.STATUS.CLAIMABLE then
            btnImg = imgBtnYellow
            btnText = "领取"
        else
            btnImg = imgBtnGreen
            btnText = "已领取"
        end
        local btnCY = cy + ENTRY.BTN_CY_OFF
        local _bf1 = BF.begin(vg, "tp_claim_" .. idx, ENTRY.BTN_CX, btnCY, ENTRY.BTN_W, ENTRY.BTN_H)
        DrawUtil.drawImageCentered(vg, btnImg,
            ENTRY.BTN_CX, btnCY, ENTRY.BTN_W, ENTRY.BTN_H, 1.0)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, ENTRY.BTN_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, ENTRY.BTN_TEXT_A))
        nvgText(vg, ENTRY.BTN_CX, btnCY, btnText, nil)
        BF.finish(vg, _bf1)
    end

    nvgRestore(vg)
end

-- ======================== Public API ========================

--- 指定 tab 是否有可领取的任务
---@param tabKey string "daily"|"weekly"|"achievement"
---@return boolean
local function hasTabClaimable(tabKey)
    if not serverTaskData then return false end
    local source
    if tabKey == "daily" then
        source = TaskConfig.DAILY
    elseif tabKey == "weekly" then
        source = TaskConfig.WEEKLY
    else
        source = TaskConfig.ACHIEVEMENT
    end
    for _, task in ipairs(source) do
        if getTaskStatus(task) == TaskConfig.STATUS.CLAIMABLE then
            return true
        end
    end
    return false
end

--- 是否有可领取的任务（遍历日/周/成就三类，任一 CLAIMABLE 即返回 true）
---@return boolean
function Panel.hasClaimable()
    if not serverTaskData then return false end
    local categories = { TaskConfig.DAILY, TaskConfig.WEEKLY, TaskConfig.ACHIEVEMENT }
    for _, list in ipairs(categories) do
        for _, task in ipairs(list) do
            if getTaskStatus(task) == TaskConfig.STATUS.CLAIMABLE then
                return true
            end
        end
    end
    return false
end

--- 初始化（加载图片资源）
---@param vg any NanoVG 上下文
function Panel.init(vg)
    vg_ = vg
    imgTopBg     = nvgCreateImage(vg, "image/UI_RW_BJ.png", 0)
    -- [暗黑化 P1-B5] 原 image/UI_TJP_1.png 贴图加载已移除（矢量绘制替代）
    imgPanel     = nvgCreateImage(vg, "image/UI_TJP_1.png", 0)
    imgDeco      = nvgCreateImage(vg, "image/UI_JJC_BTBJ.png", 0)
    imgEntryBg   = nvgCreateImage(vg, "image/UI_RW_1.png", 0)
    imgBarBg     = nvgCreateImage(vg, "image/UI_RW_JDT2.png", 0)
    imgBarFill   = nvgCreateImage(vg, "image/UI_RW_JDT1.png", 0)
    imgBtnBack   = nvgCreateImage(vg, "image/UI_AN_FH.png", 0)
    -- [暗黑化 P1-B5] 原 image/UI_AN_2.png 贴图加载已移除（矢量绘制替代）
    imgSlider    = nvgCreateImage(vg, "image/UI_AN_2.png", 0)
    imgBtnRed    = nvgCreateImage(vg, "image/UI_AN_FANG_hong.png", 0)
    imgBtnYellow = nvgCreateImage(vg, "image/UI_AN_FANG_huang.png", 0)
    imgBtnGreen  = nvgCreateImage(vg, "image/UI_AN_FANG_lv.png", 0)
    imgRedDot    = nvgCreateImage(vg, "image/ICON_HD.png", 0)

    print("[TaskPanel] init OK")
end

--- 打开面板
function Panel.open()
    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    require("systems.GameSFX").playUIMove(1)
    state.tab = "daily"
    state.tabFrom = "daily"
    state.tabSwitchTime = 0
    state.scrollY = 0
    state.scrollMax = 0
    state.dragging = false
    state.scrollVel = 0
    print("[TaskPanel] open")
end

--- 关闭面板
function Panel.close()
    if state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    state.dragging = false
    print("[TaskPanel] close")
end

--- 是否打开
---@return boolean
function Panel.isOpen()
    return state.open
end

--- 返回打开/关闭动画进度 (0=完全关闭, 1=完全打开)
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

--- 更新（惯性滚动 + 关闭动画）
function Panel.update(dt)
    if not state.open then return end
    -- 关闭动画结束后真正关闭
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        if elapsed >= ANIM_CLOSE_DUR then
            state.open = false
            state.closing = false
            print("[TaskPanel] closed (anim done)")
        end
        return
    end
    if not state.dragging and math.abs(state.scrollVel) > SCROLL_MIN_VEL then
        state.scrollY = state.scrollY + state.scrollVel
        state.scrollVel = state.scrollVel * SCROLL_FRICTION
        clampScroll()
    else
        state.scrollVel = 0
    end
end

--- 绘制
function Panel.draw(vg)
    if not state.open then return end

    -- === 动画进度计算（与 BlacksmithPage 一致） ===
    local progress, lowerProgress
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        local rawT = math.min(1.0, elapsed / ANIM_CLOSE_DUR)
        progress      = 1 - easeInCubic(rawT)
        lowerProgress = progress
    else
        local elapsed = time.elapsedTime - state.openTime
        local rawT = math.min(1.0, elapsed / ANIM_OPEN_DUR)
        progress      = easeOutCubic(rawT)
        lowerProgress = progress
    end

    local upperOY = -UPPER_SLIDE_DIST * (1 - progress)
    local lowerOY =  LOWER_SLIDE_DIST * (1 - lowerProgress)
    local overlayAlpha = math.floor(180 * progress)

    -- === 全屏暗色遮罩 ===
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
    nvgFill(vg)

    -- === 上半部分（从屏幕上方滑入）：顶部背景 + 标题 ===
    nvgSave(vg)
    nvgTranslate(vg, 0, upperOY)

    -- 1. 顶部背景图（顶端对齐）
    DrawUtil.drawImageCentered(vg, imgTopBg, TOP_BG.CX, TOP_BG.CY, TOP_BG.W, TOP_BG.H, 1.0)

    -- 3. 标题（与背包一致：背景图 + 白色文字，无描边）
    DrawUtil.drawImageCentered(vg, imgTitleBg, TITLE.BG_CX, TITLE.BG_CY, TITLE.BG_W, TITLE.BG_H, 1.0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TITLE.FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, TITLE.TEXT_CX, TITLE.TEXT_CY, TITLE.TEXT, nil)

    nvgRestore(vg)

    -- === 下半部分（从屏幕下方滑入）：面板 + 内容 + Tab ===
    nvgSave(vg)
    nvgTranslate(vg, 0, lowerOY)

    -- 2. 下方背景框（九宫格）
    DarkIcon.drawNine(vg, "plain", LOWER_PANEL.CX - LOWER_PANEL.W * 0.5, LOWER_PANEL.CY - LOWER_PANEL.H * 0.5, LOWER_PANEL.W, LOWER_PANEL.H)

    -- 4. 标题装饰
    DrawUtil.drawImageCentered(vg, imgDeco, DECO.CX, DECO.CY, DECO.W, DECO.H, 1.0)

    -- 5. 区域标题文字（跟随 tab）
    local sectionText = TAB_SECTION_TITLES[state.tab] or "每日任务"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, SECTION_TITLE.FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(SECTION_TITLE.R, SECTION_TITLE.G, SECTION_TITLE.B, 255))
    nvgText(vg, SECTION_TITLE.X, SECTION_TITLE.Y, sectionText, nil)

    -- 6. 任务条目列表
    drawTaskList(vg)

    -- 7. 返回按钮（与铁匠铺一致）
    DrawUtil.drawImageCentered(vg, imgBtnBack, BTN_BACK.CX, BTN_BACK.CY, BTN_BACK.W, BTN_BACK.H, 1.0)

    -- 8. Tab 背景
    DrawUtil.drawImageCentered(vg, imgTabBg, TAB.BG_CX, TAB.BG_CY, TAB.BG_W, TAB.BG_H, 1.0)

    -- 9. Tab 滑块（带动画，与铁匠铺一致）
    local tabIdx = getTabIndex(state.tab)
    local fromIdx = getTabIndex(state.tabFrom)
    local tabElapsed = time.elapsedTime - state.tabSwitchTime
    local tabT = math.min(1.0, tabElapsed / TAB.ANIM_DUR)
    local tabEased = easeInOutCubic(tabT)

    local targetItem = TAB_ITEMS[tabIdx]
    local fromItem = TAB_ITEMS[fromIdx]
    local sliderCX = fromItem.cx + (targetItem.cx - fromItem.cx) * tabEased
    local sliderCY = fromItem.cy + (targetItem.cy - fromItem.cy) * tabEased

    DarkIcon.drawNine(vg, "btn", sliderCX - TAB.SLIDER_W * 0.5, sliderCY - TAB.SLIDER_H * 0.5, TAB.SLIDER_W, TAB.SLIDER_H, { accent = "gold" })

    -- 10. Tab 文字 + 红点
    for i, item in ipairs(TAB_ITEMS) do
        local isActive = (state.tab == item.key)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, TAB.FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(TAB.ACTIVE_R, TAB.ACTIVE_G, TAB.ACTIVE_B, 255))
        else
            nvgFillColor(vg, nvgRGBA(TAB.INACTIVE_R, TAB.INACTIVE_G, TAB.INACTIVE_B, 255))
        end
        nvgText(vg, item.cx, TAB.TEXT_Y, item.name, nil)

        -- 红点：有可领取任务时显示（选中也保留）
        if imgRedDot >= 0 and hasTabClaimable(item.key) then
            local upSize = 30
            local textHalfW = nvgTextBounds(vg, 0, 0, item.name) * 0.5
            local upX = item.cx + textHalfW + 10
            local upY = TAB.TEXT_Y - 18
            DrawUtil.drawImageCentered(vg, imgRedDot, upX, upY, upSize, upSize, 1.0)
        end
    end

    nvgRestore(vg)
end

-- ======================== 输入处理 ========================

---@return boolean 是否消费了事件
function Panel.handleInput(dx, dy)
    if not state.open then return false end

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
                state.scrollY = 0
                sortedCache[item.key] = nil  -- 切换时清除该 tab 排序缓存
                print("[TaskPanel] 切换到 " .. item.name)
            end
            return true
        end
    end

    -- 条目按钮点击（领取奖励）
    local tasks = getTaskList()
    for idx, task in ipairs(tasks) do
        local cy = ENTRY.FIRST_CY + (idx - 1) * ENTRY.STEP - state.scrollY
        local btnCY = cy + ENTRY.BTN_CY_OFF
        if DrawUtil.hitTest(dx, dy, ENTRY.BTN_CX, btnCY, ENTRY.BTN_W, ENTRY.BTN_H) then
            local status = getTaskStatus(task)
            if status == TaskConfig.STATUS.CLAIMABLE then
                BF.trigger("tp_claim_" .. idx)
                if sendAction then
                    sendAction(Protocol.ACTION_TYPES.CLAIM_TASK, { taskId = task.id })
                    print("[TaskPanel] 领取奖励(服务端): " .. task.id)
                else
                    print("[TaskPanel] sendAction 未注入，无法领取: " .. task.id)
                end
            elseif status == TaskConfig.STATUS.LOCKED then
                print("[TaskPanel] 任务未完成: " .. task.id)
            else
                print("[TaskPanel] 已领取: " .. task.id)
            end
            return true
        end
    end

    return true  -- 面板打开时消费所有事件
end

-- ======================== 拖拽/滚轮 ========================

function Panel.handleDragBegin(dx, dy)
    if not state.open then return false end
    if dy >= CLIP.TOP and dy <= CLIP.BOT then
        state.dragging = true
        state.lastDragY = dy
        state.scrollVel = 0
        return true
    end
    return true
end

function Panel.handleDragMove(dx, dy)
    if not state.open then return false end
    if state.dragging then
        local delta = state.lastDragY - dy
        state.scrollY = state.scrollY + delta
        state.scrollVel = delta
        state.lastDragY = dy
        clampScroll()
        return true
    end
    return true
end

function Panel.handleDragEnd(dx, dy)
    if not state.open then return false end
    state.dragging = false
    return true
end

function Panel.handleScroll(wheel)
    if not state.open then return false end
    state.scrollY = state.scrollY - wheel * SCROLL_WHEEL_STEP
    clampScroll()
    return true
end

-- ======================== 服务端数据接口 ========================

--- 接收服务端推送的任务数据
---@param data table 服务端 task 模块完整数据
function Panel.setTaskData(data)
    serverTaskData = data
    sortedCache = {}  -- 数据变更，清除排序缓存以触发重新排序
end

--- 注入 sendAction（由 Client.lua 调用）
---@param fn function
function Panel.setSendAction(fn)
    sendAction = fn
end

return Panel
