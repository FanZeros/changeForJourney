-- ============================================================================
-- DarkTitleScreen.lua — 横屏专属暗黑标题界面（HORIZON_MODE）
-- 全窗口（逻辑分辨率坐标）绘制：终焉之门大门背景 + 透明 LOGO 叠加 + 余烬粒子 +
-- 金饰角标 + "轻触屏幕继续" 脉冲。点击任意位置淡出进入游戏。
--
-- 背景：竖屏 StartScreen（1080×2400 视频标题）在横屏三联布局下被
--       H_skipDone/skipForReconnect 跳过，导致 H5 无标题瞬间。
--       本模块以横屏原生比例补上标题仪式感，素材全部取自本地 workspace。
-- 素材：image/UI_TITLE_BG_GATE.png（1920×1080 大门背景）
--       image/LOGO终焉之门_透明版.png（1920×1080 透明 LOGO，与背景同构图对位）
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
local imgLogo_  = -1     -- image/LOGO终焉之门_透明版.png（1920×1080 透明画布）
local imgGate_  = -1     -- image/UI_TITLE_BG_GATE.png（1920×1080 大门背景）

local FADE_TIME = 0.55   -- 淡出时长（秒）

-- 暗黑魔塔色板（与 DarkIcon/UI 暗黑化一致）
local C_BG_TOP    = {  6,  6, 10 }
local C_GOLD      = { 216, 201, 163 }   -- 骨金（提示文字/角标）

-- ============================================================================
-- 生命周期
-- ============================================================================

--- 初始化（加载 LOGO 与大门背景贴图，仅一次）
---@param vg NVGContextWrapper
function DarkTitleScreen.init(vg)
    vg_ = vg
    if imgLogo_ < 0 then
        imgLogo_ = nvgCreateImage(vg, "image/LOGO终焉之门_透明版.png", 0)
        if imgLogo_ < 0 then
            print("[DarkTitleScreen] WARN: LOGO终焉之门_透明版.png load failed")
        end
    end
    if imgGate_ < 0 then
        imgGate_ = nvgCreateImage(vg, "image/UI_TITLE_BG_GATE.png", 0)
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

    -- 1)+2) 大门背景 + 透明 LOGO（同一相对 cover 矩形，任意 DPR/空间尺度下严格对位）
    local imgAR = 16 / 9
    local winAR = w / h
    local dw, dh
    if winAR > imgAR then
        dw, dh = w, w / imgAR
    else
        dh, dw = h, h * imgAR
    end
    local dx, dy = (w - dw) * 0.5, (h - dh) * 0.5

    if imgGate_ >= 0 then
        local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, imgGate_, A)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(C_BG_TOP[1], C_BG_TOP[2], C_BG_TOP[3], 255 * A))
        nvgFill(vg)
    end

    if imgLogo_ >= 0 then
        local la = (0.88 + 0.12 * (0.5 + 0.5 * math.sin(t * 1.4))) * A
        -- [fix] LOGO 以屏幕中心缩放至 50%（原先与大门口共用全屏 cover 矩形，过大）
        local LOGO_SCALE = 0.5
        local lw, lh = dw * LOGO_SCALE, dh * LOGO_SCALE
        -- [fix] 标题上移 15% 屏高
        local lx, ly = (w - lw) * 0.5, (h - lh) * 0.5 - h * 0.15
        local paint = nvgImagePattern(vg, lx, ly, lw, lh, 0, imgLogo_, la)
        nvgBeginPath(vg)
        nvgRect(vg, lx, ly, lw, lh)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end

    -- 5) "轻触屏幕继续" 脉冲提示
    local promptA = (0.30 + 0.62 * (0.5 + 0.5 * math.sin(t * 2.3))) * A
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(20, math.min(w * 0.024, 32)))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], promptA * 255))
    nvgText(vg, w * 0.5, h * 0.66, "轻 触 屏 幕 继 续", nil)
end

return DarkTitleScreen
