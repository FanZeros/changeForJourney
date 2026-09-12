-- ============================================================================
-- DarkTitleScreen.lua — 横屏专属暗黑标题界面（HORIZON_MODE）
-- 全窗口（逻辑分辨率坐标）绘制：暗黑径向渐变 + UI_LOGO 呼吸 + 余烬粒子 +
-- 金饰角标 + "轻触屏幕继续" 脉冲。点击任意位置淡出进入游戏。
--
-- 背景：竖屏 StartScreen（1080×2400 视频标题）在横屏三联布局下被
--       H_skipDone/skipForReconnect 跳过，导致 H5 无标题瞬间。
--       本模块以横屏原生比例补上标题仪式感，素材全部取自本地 workspace。
-- 接入：Client.lua / Standalone.lua 的 HORIZON 渲染与输入路径（见各文件标记
--       [DarkTitleScreen]）。
-- ============================================================================

local DarkTitleScreen = {}

-- ── 状态 ──
local vg_       = nil
local isOpen_   = false
local timer_    = 0      -- 打开以来的累计时间（驱动动画）
local fadeOut_  = false  -- 是否正在淡出
local fadeA_    = 1.0    -- 淡出透明度 1→0
local imgLogo_  = -1     -- image/UI_LOGO.png（948×545）
local LOGO_AR   = 948 / 545
local embers_   = {}     -- 余烬粒子 {x0, y0, speed, drift, size, phase, alpha}

local FADE_TIME = 0.55   -- 淡出时长（秒）
local EMBER_N   = 26

-- 暗黑魔塔色板（与 DarkIcon/UI 暗黑化一致）
local C_BG_TOP    = {  6,  6, 10 }
local C_BG_BOT    = { 14, 14, 22 }
local C_GOLD      = { 216, 201, 163 }   -- 骨金（AnnouncementPanel 标题色）
local C_GOLD_DIM  = { 212, 175,  55 }   -- 亮金（发光/余烬）

-- ── 工具 ──
local function radial(vg, cx, cy, r, inner, outer)
    local paint = nvgRadialGradient(vg, cx, cy, 0, r, inner, outer)
    nvgBeginPath(vg)
    nvgRect(vg, cx - r, cy - r, r * 2, r * 2)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

local function seedEmbers(w, h)
    embers_ = {}
    for i = 1, EMBER_N do
        embers_[i] = {
            x0    = math.random() * w,
            y0    = h * 0.15 + math.random() * h * 0.9,   -- 允许略超下界，向上飘
            speed = 10 + math.random() * 26,               -- px/s 上升
            drift = 8 + math.random() * 22,                -- 水平摆动幅度
            size  = 1.4 + math.random() * 2.2,
            phase = math.random() * math.pi * 2,
            alpha = 0.12 + math.random() * 0.38,
        }
    end
end

-- ============================================================================
-- 生命周期
-- ============================================================================

--- 初始化（加载 LOGO 贴图，仅一次）
---@param vg NVGContextWrapper
function DarkTitleScreen.init(vg)
    vg_ = vg
    if imgLogo_ < 0 then
        imgLogo_ = nvgCreateImage(vg, "image/UI_LOGO.png", 0)
        if imgLogo_ < 0 then
            print("[DarkTitleScreen] WARN: UI_LOGO.png load failed")
        end
    end
end

--- 打开标题（横屏路径首帧调用）
function DarkTitleScreen.open()
    if isOpen_ then return end
    isOpen_  = true
    timer_   = 0
    fadeOut_ = false
    fadeA_   = 1.0
    print("[DarkTitleScreen] open")
end

function DarkTitleScreen.isOpen()
    return isOpen_
end

--- 点击任意位置 → 开始淡出（由输入层在 tap 时调用）
function DarkTitleScreen.handleTap()
    if isOpen_ and not fadeOut_ then
        fadeOut_ = true
        print("[DarkTitleScreen] tap → fade out")
    end
end

---@param dt number
function DarkTitleScreen.update(dt)
    if not isOpen_ then return end
    timer_ = timer_ + dt
    if fadeOut_ then
        fadeA_ = fadeA_ - dt / FADE_TIME
        if fadeA_ <= 0 then
            fadeA_   = 0
            isOpen_  = false
            fadeOut_ = false
            print("[DarkTitleScreen] closed")
        end
    end
end

-- ============================================================================
-- 绘制（全窗口逻辑坐标：调用方先 nvgResetTransform，传入 logicalW/logicalH）
-- ============================================================================

---@param vg NVGContextWrapper
---@param w number 窗口逻辑宽
---@param h number 窗口逻辑高
function DarkTitleScreen.draw(vg, w, h)
    if not isOpen_ or w <= 0 or h <= 0 then return end
    local t = timer_
    local A = fadeA_   -- 全局透明度（淡出时揭示底层）

    -- 1) 背景竖向渐变（比游戏底色更深一档，突出标题）
    local bgPaint = nvgLinearGradient(vg, 0, 0, 0, h,
        nvgRGBA(C_BG_TOP[1],  C_BG_TOP[2],  C_BG_TOP[3],  255 * A),
        nvgRGBA(C_BG_BOT[1],  C_BG_BOT[2],  C_BG_BOT[3],  255 * A))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, bgPaint)
    nvgFill(vg)

    -- 2) 标志后方暖金辉光（呼吸）
    local glowR = math.min(w, h) * 0.52
    local glowA = (26 + 10 * (0.5 + 0.5 * math.sin(t * 1.1))) * A
    radial(vg, w * 0.5, h * 0.40, glowR,
        nvgRGBA(C_GOLD_DIM[1], C_GOLD_DIM[2], C_GOLD_DIM[3], glowA),
        nvgRGBA(0, 0, 0, 0))

    -- 3) 余烬粒子（缓缓上升的金色光点）
    for i = 1, #embers_ do
        local e  = embers_[i]
        local y  = (e.y0 - e.speed * t) % (h * 1.15)
        local x  = e.x0 + math.sin(t * 0.7 + e.phase) * e.drift
        local tw = 0.6 + 0.4 * math.sin(t * 2.1 + e.phase * 1.7)
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, e.size)
        nvgFillColor(vg, nvgRGBA(C_GOLD_DIM[1], C_GOLD_DIM[2], C_GOLD_DIM[3],
            e.alpha * tw * A))
        nvgFill(vg)
    end

    -- 4) LOGO（948×545，含"宿命旅途"字样），呼吸 + 轻微浮动
    if imgLogo_ >= 0 then
        local lw = math.min(w * 0.46, h * 0.56 * LOGO_AR, 660)
        local lh = lw / LOGO_AR
        local cx = w * 0.5
        local cy = h * 0.40 + math.sin(t * 1.2) * 4
        local la = (0.93 + 0.07 * math.sin(t * 1.6)) * A
        local paint = nvgImagePattern(vg, cx - lw * 0.5, cy - lh * 0.5, lw, lh, 0, imgLogo_, la)
        nvgBeginPath(vg)
        nvgRect(vg, cx - lw * 0.5, cy - lh * 0.5, lw, lh)
        nvgFillPaint(vg, paint)
        nvgFill(vg)

        -- LOGO 下分隔线：细金线 + 中央菱形
        local ly  = cy + lh * 0.5 + math.min(h * 0.045, 42)
        local half = lw * 0.36
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - half, ly)
        nvgLineTo(vg, cx - 14, ly)
        nvgMoveTo(vg, cx + 14, ly)
        nvgLineTo(vg, cx + half, ly)
        nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 120 * A))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, ly - 6)
        nvgLineTo(vg, cx + 6, ly)
        nvgLineTo(vg, cx, ly + 6)
        nvgLineTo(vg, cx - 6, ly)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 170 * A))
        nvgFill(vg)
    end

    -- 5) "轻触屏幕继续" 脉冲提示
    local promptA = (0.30 + 0.62 * (0.5 + 0.5 * math.sin(t * 2.3))) * A
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(20, math.min(w * 0.024, 32)))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], promptA * 255))
    nvgText(vg, w * 0.5, h * 0.66, "轻 触 屏 幕 继 续", nil)

    -- 6) 四角金色角标（L 形）
    local inset = math.min(w, h) * 0.035
    local len   = math.min(w, h) * 0.075
    nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 70 * A))
    nvgStrokeWidth(vg, 2)
    for _, cx in ipairs({ true, false }) do
        for _, cy in ipairs({ true, false }) do
            local px = cx and inset or (w - inset)
            local py = cy and inset or (h - inset)
            local sx = cx and 1 or -1
            local sy = cy and 1 or -1
            nvgBeginPath(vg)
            nvgMoveTo(vg, px + sx * len, py)
            nvgLineTo(vg, px, py)
            nvgLineTo(vg, px, py + sy * len)
            nvgStroke(vg)
        end
    end

    -- 7) 底部小字
    nvgFontSize(vg, math.max(13, math.min(w * 0.013, 17)))
    nvgFillColor(vg, nvgRGBA(160, 152, 130, 110 * A))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(vg, inset + 8, h - inset * 0.9, "宿命旅途 · 单机版", nil)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgText(vg, w - inset - 8, h - inset * 0.9, "H5", nil)
end

return DarkTitleScreen
