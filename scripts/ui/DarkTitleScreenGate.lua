-- ============================================================================
-- DarkTitleScreen.lua — 横屏专属暗黑标题界面（HORIZON_MODE）
-- 全窗口（逻辑分辨率坐标）绘制：终焉之门大门背景 + 透明 LOGO 叠加 + 余烬粒子 +
-- 金饰角标 + "轻触屏幕继续" 脉冲。点击任意位置淡出进入游戏。
--
-- 背景：竖屏 StartScreen（1080×2400 视频标题）在横屏三联布局下被
--       H_skipDone/skipForReconnect 跳过，导致 H5 无标题瞬间。
--       本模块以横屏原生比例补上标题仪式感，素材全部取自本地 workspace。
-- 素材：image/界面底板/标题与加载/UI_TITLE_BG_GATE.png（1920×1080 大门背景）
--       image/界面底板/标题与加载/UI_LOGO_TM.png（1920×1080 透明 LOGO，与背景同构图对位）
-- 接入：Client.lua / Standalone.lua 的 HORIZON 渲染与输入路径（见各文件标记
--       [DarkTitleScreen]）。
-- ============================================================================

local I18n = require("core.I18n")

local DarkTitleScreen = {}

-- ── 状态 ──
local vg_       = nil
local isOpen_   = false
local timer_    = 0      -- 打开以来的累计时间（驱动动画）
local fadeOut_  = false  -- 是否正在淡出
local fadeA_    = 1.0    -- 淡出透明度 1→0
local imgLogo_  = -1     -- image/界面底板/标题与加载/UI_LOGO_TM.png（1920×1080 透明画布）
local imgGate_  = -1     -- image/界面底板/标题与加载/UI_TITLE_BG_GATE.png（1920×1080 大门背景）

local FADE_TIME = 0.55   -- 淡出时长（秒）
local ready_    = true   -- 资源未就绪时锁点击，避免空背景进游戏

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
        imgLogo_ = nvgCreateImage(vg, "image/界面底板/标题与加载/UI_LOGO_TM.png", 0)
        if imgLogo_ < 0 then
            print("[DarkTitleScreen] WARN: UI_LOGO_TM.png load failed")
        end
    end
    if imgGate_ < 0 then
        imgGate_ = nvgCreateImage(vg, "image/界面底板/标题与加载/UI_TITLE_BG_GATE.png", 0)
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

--- 资源未就绪时锁点击（预载进行中不允许进入）
function DarkTitleScreen.setReady(ready)
    ready_ = ready and true or false
end

function DarkTitleScreen.isReady()
    return ready_
end

function DarkTitleScreen.isFading()
    return isOpen_ and fadeOut_
end

--- 点击任意位置 → 开始淡出（资源未就绪时忽略）
function DarkTitleScreen.handleTap()
    if not isOpen_ or fadeOut_ then return end
    if not ready_ then
        print("[DarkTitleScreen] tap ignored: resources not ready")
        return
    end
    fadeOut_ = true
    print("[DarkTitleScreen] tap → fade out")
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

    -- 5) 底部提示：未就绪显示加载进度，就绪后才允许轻触进入
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if not ready_ then
        local pct = DarkTitleScreen.loadPercent or 0
        local done = DarkTitleScreen.loadDone or 0
        local total = DarkTitleScreen.loadTotal or 0
        nvgFontSize(vg, math.max(18, math.min(w * 0.022, 28)))
        nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 220 * A))
        -- [启动诊断] 附带当前步骤名/耗时（有值时），定位超帧预算的 init
        local stepName = DarkTitleScreen.loadStep
        local stepMs = DarkTitleScreen.loadStepMs
        local pctText
        if stepName and stepMs then
            pctText = string.format("%s  %d%%  [%s %dms]", I18n.t("loading_res"), pct, tostring(stepName), stepMs)
        else
            pctText = string.format("%s  %d%%", I18n.t("loading_res"), pct)
        end
        nvgText(vg, w * 0.5, h * 0.78, pctText, nil)
        local bw = w * 0.36
        local bh = math.max(8, h * 0.01)
        local bx = (w - bw) * 0.5
        local by = h * 0.83
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bw, bh, bh * 0.5)
        nvgFillColor(vg, nvgRGBA(40, 36, 28, 180 * A))
        nvgFill(vg)
        local fw = math.max(bh, bw * math.min(1, pct / 100))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, fw, bh, bh * 0.5)
        nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 210 * A))
        nvgFill(vg)
        if total > 0 then
            nvgFontSize(vg, math.max(14, math.min(w * 0.016, 20)))
            nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 140 * A))
            nvgText(vg, w * 0.5, by + bh + h * 0.035, string.format("%d / %d", done, total), nil)
        end
    else
        local promptA = (0.30 + 0.62 * (0.5 + 0.5 * math.sin(t * 2.3))) * A
        nvgFontSize(vg, math.max(20, math.min(w * 0.024, 32)))
        nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], promptA * 255))
        nvgText(vg, w * 0.5, h * 0.78, I18n.t("tap_continue"), nil)
    end

    -- 标题页语言切换（左下）
    local chipW, chipH, gap = 92, 36, 8
    local x0 = 24
    local y0 = h - 24 - chipH
    DarkTitleScreen._langHits = {}
    local cur = I18n.get()
    for i, lang in ipairs(I18n.LANGS) do
        local x = x0 + (i - 1) * (chipW + gap)
        local on = lang.id == cur
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y0, chipW, chipH, 8)
        if on then
            nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 210 * A))
        else
            nvgFillColor(vg, nvgRGBA(20, 16, 12, 160 * A))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], (on and 240 or 90) * A))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(14, math.min(w * 0.014, 18)))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if on then
            nvgFillColor(vg, nvgRGBA(26, 18, 10, 255 * A))
        else
            nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 200 * A))
        end
        nvgText(vg, x + chipW * 0.5, y0 + chipH * 0.5, lang.label, nil)
        DarkTitleScreen._langHits[i] = { x = x, y = y0, w = chipW, h = chipH, id = lang.id }
    end
end

--- 标题页点语言芯片返回 true（吞掉继续）
---@param sx number 逻辑坐标 X
---@param sy number 逻辑坐标 Y
---@return boolean
function DarkTitleScreen.handleLanguageTap(sx, sy)
    local hits = DarkTitleScreen._langHits
    if not hits then return false end
    for i = 1, #hits do
        local r = hits[i]
        if sx >= r.x and sx <= r.x + r.w and sy >= r.y and sy <= r.y + r.h then
            I18n.set(r.id)
            local ok, SP = pcall(require, "ui.SettingsPanel")
            if ok and SP and SP.persistLanguage then SP.persistLanguage() end
            print("[DarkTitleScreen] language=" .. r.id)
            return true
        end
    end
    return false
end

return DarkTitleScreen
