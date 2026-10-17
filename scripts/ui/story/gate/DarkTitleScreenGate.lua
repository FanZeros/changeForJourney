-- ============================================================================
-- DarkTitleScreen.lua — 横屏专属暗黑标题界面（HORIZON_MODE）
-- 全窗口（逻辑分辨率坐标）绘制：终焉之门大门背景 + 透明 LOGO 叠加 + 余烬粒子 +
-- 金饰角标 + "轻触屏幕继续" 脉冲。点击任意位置淡出进入游戏。
--
-- 背景：横屏标题是唯一标题界面。
--       本模块以横屏原生比例提供标题仪式感，素材全部取自本地 workspace。
-- 素材：image/界面底板/标题与加载/UI_TITLE_BG_GATE.png（1920×1080 大门背景）
--       image/界面底板/标题与加载/UI_LOGO_TM.png（1920×1080 透明 LOGO，与背景同构图对位）
-- 接入：Client.lua / Standalone.lua 的 HORIZON 渲染与输入路径（见各文件标记
--       [DarkTitleScreen]）。
-- ============================================================================

local I18n = require("core.I18n")

local DarkTitleScreen = {}

-- ── 状态 ──
---@type NVGContextWrapper?
local vg_       = nil
local isOpen_   = false
local timer_    = 0      -- 打开以来的累计时间（驱动动画）
local fadeOut_  = false  -- 是否正在淡出
local fadeA_    = 1.0    -- 淡出透明度 1→0
local langOpen_ = false  -- 左下语言弹出层
local imgLogo_  = -1     -- image/界面底板/标题与加载/UI_LOGO_TM.png（1920×1080 透明画布）
local imgGate_  = -1     -- image/界面底板/标题与加载/UI_TITLE_BG_GATE.png（1920×1080 大门背景）

local FADE_TIME = 0.55   -- 沿用原切入时长，关闭后接既有序章/离线结算
local REVEAL_TIME = 1.35
local exitTime_ = 0
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
    if vg_ ~= vg then imgGate_, imgLogo_ = -1, -1 end
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

--- 打开标题（首次启动时由 Standalone.Start 调用）
function DarkTitleScreen.open()
    if isOpen_ then return end
    isOpen_  = true
    timer_   = 0
    fadeOut_ = false
    fadeA_   = 1.0
    exitTime_ = 0
    langOpen_ = false
    DarkTitleScreen._langBtn, DarkTitleScreen._langHits = nil, {}
    print("[DarkTitleScreen] open")
end

--- 重新打开标题（清除存档后由 Standalone.requestResetToTitleScreen 调用）
--- 此时游戏已启动完毕，资源必然就绪，直接解锁点击
function DarkTitleScreen.reopen()
    isOpen_   = true
    timer_    = 0
    fadeOut_  = false
    fadeA_    = 1.0
    exitTime_ = 0
    langOpen_ = false
    DarkTitleScreen._langBtn, DarkTitleScreen._langHits = nil, {}
    ready_    = true
    print("[DarkTitleScreen] reopen")
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
    exitTime_ = 0
    langOpen_ = false
    print("[DarkTitleScreen] tap → fade out")
end

---@param dt number
function DarkTitleScreen.update(dt)
    if not isOpen_ then return end
    dt = math.max(0, tonumber(dt) or 0)
    timer_ = timer_ + dt
    if fadeOut_ then
        exitTime_ = math.min(FADE_TIME, exitTime_ + dt)
        fadeA_ = math.max(0, 1 - exitTime_ / FADE_TIME)
        if fadeA_ <= 0 then
            fadeA_   = 0
            isOpen_  = false
            fadeOut_ = false
            print("[DarkTitleScreen] closed")
        end
    end
end

local function smooth(value)
    local p = math.max(0, math.min(1, value))
    return p * p * (3 - 2 * p)
end

-- 程序化门缝光与余烬：不读图、不消耗游戏随机数，任意尺寸都在宿主帧内绘制。
local function drawGateLight(vg, w, h, reveal, opening, alpha)
    local cx, cy = w * 0.5, h * 0.55
    local radius = math.min(w, h) * (0.32 + opening * 0.5)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius)
    nvgFillPaint(vg, nvgRadialGradient(vg, cx, cy, 0, radius,
        nvgRGBA(240,186,91,math.floor((35 + opening * 95) * reveal * alpha)), nvgRGBA(178,112,41,0)))
    nvgFill(vg)
    local seamW = math.max(1, math.min(w, h) * (0.0015 + opening * 0.016))
    local seamH = h * (0.20 + 0.22 * reveal)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - seamW * 0.5, cy - seamH * 0.5, seamW, seamH, seamW * 0.5)
    nvgFillColor(vg, nvgRGBA(255,222,155,math.floor((32 + opening * 100) * reveal * alpha)))
    nvgFill(vg)
    for i = 1, 28 do
        local phase = (timer_ * (0.035 + (i % 5) * 0.006) + i * 0.6180339) % 1
        local x = w * (0.17 + ((i * 37) % 101) / 101 * 0.66)
            + math.sin(timer_ * 0.45 + i * 2.3) * w * 0.009
        local y = h * (0.98 - phase * 0.82)
        local opacity = math.sin(phase * math.pi) * reveal * alpha
        local r = math.max(0.7, math.min(w,h) * (0.0008 + (i % 3) * 0.0004))
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, r)
        nvgFillColor(vg, nvgRGBA(235,180,95,math.floor(opacity * 150)))
        nvgFill(vg)
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
    local reveal = smooth(t / REVEAL_TIME)
    local opening = smooth(exitTime_ / FADE_TIME)
    nvgSave(vg)
    nvgIntersectScissor(vg, 0, 0, w, h)

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

    -- 初次进场从暗幕显现；点继续时背景略向两侧展开，LOGO不被拆开。
    if imgGate_ >= 0 then
        if opening > 0 then
            local shift = w * 0.08 * opening
            for half = 1, 2 do
                local offset = half == 1 and -shift or shift
                nvgSave(vg)
                nvgIntersectScissor(vg, (half - 1) * w * 0.5, 0, w * 0.5, h)
                nvgBeginPath(vg); nvgRect(vg, 0, 0, w, h)
                nvgFillPaint(vg, nvgImagePattern(vg, dx + offset, dy, dw, dh, 0, imgGate_, A))
                nvgFill(vg)
                nvgRestore(vg)
            end
        else
            local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, imgGate_, A)
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, w, h)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(C_BG_TOP[1], C_BG_TOP[2], C_BG_TOP[3], 255 * A))
        nvgFill(vg)
    end

    nvgBeginPath(vg); nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(6,6,10,math.floor((1 - reveal) * 245 * A)))
    nvgFill(vg)
    drawGateLight(vg, w, h, reveal, opening, A)

    if imgLogo_ >= 0 then
        local la = (0.88 + 0.12 * (0.5 + 0.5 * math.sin(t * 1.4))) * A * reveal
        -- LOGO 以屏幕中心缩放至 50%
        local LOGO_SCALE = 0.5
        local lw, lh = dw * LOGO_SCALE, dh * LOGO_SCALE
        -- 标题上移 15% 屏高
        local lx, ly = (w - lw) * 0.5, (h - lh) * 0.5 - h * 0.15
        local paint = nvgImagePattern(vg, lx, ly, lw, lh, 0, imgLogo_, la)
        nvgBeginPath(vg)
        nvgRect(vg, lx, ly, lw, lh)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end
    -- 轻微收拢暗边，突出中央大门，不覆盖底部语言/加载控件。
    local edge = w * 0.16
    for side = 1, 2 do
        local x = side == 1 and 0 or w - edge
        nvgBeginPath(vg); nvgRect(vg, x, 0, edge, h)
        local from = side == 1 and x or x + edge
        local to = side == 1 and x + edge or x
        nvgFillPaint(vg, nvgLinearGradient(vg, from, 0, to, 0,
            nvgRGBA(5,5,8,math.floor(140 * A)), nvgRGBA(5,5,8,0)))
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

    -- 标题页语言：左下角一颗按钮，点开上弹列表
    local btnW = math.max(132, math.min(w * 0.16, 176))
    local btnH = math.max(36, math.min(h * 0.05, 44))
    local x0 = 20
    local y0 = h - 20 - btnH
    local cur = I18n.get()
    local curLabel = I18n.displayName(cur)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x0, y0, btnW, btnH, 10)
    nvgFillColor(vg, nvgRGBA(20, 16, 12, 180 * A))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 200 * A))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(14, math.min(w * 0.016, 20)))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 230 * A))
    nvgText(vg, x0 + btnW * 0.5, y0 + btnH * 0.5, curLabel, nil)
    DarkTitleScreen._langBtn = { x = x0, y = y0, w = btnW, h = btnH }

    DarkTitleScreen._langHits = {}
    if langOpen_ then
        local rowH = btnH
        local n = #I18n.LANGS
        local popH = n * rowH
        local popY = y0 - 8 - popH
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x0, popY, btnW, popH, 10)
        nvgFillColor(vg, nvgRGBA(14, 12, 10, 230 * A))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 160 * A))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        for i, lang in ipairs(I18n.LANGS) do
            local ry = popY + (i - 1) * rowH
            local on = lang.id == cur
            if on then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, x0 + 4, ry + 3, btnW - 8, rowH - 6, 7)
                nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 210 * A))
                nvgFill(vg)
            end
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(14, math.min(w * 0.015, 18)))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if on then
                nvgFillColor(vg, nvgRGBA(26, 18, 10, 255 * A))
            else
                nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 220 * A))
            end
            nvgText(vg, x0 + btnW * 0.5, ry + rowH * 0.5, I18n.displayName(lang.id), nil)
            DarkTitleScreen._langHits[i] = { x = x0, y = ry, w = btnW, h = rowH, id = lang.id }
        end
    end
    nvgRestore(vg)
end

--- 标题页语言按钮/弹出项：命中返回 true（吞掉继续）
---@param sx number 逻辑坐标 X
---@param sy number 逻辑坐标 Y
---@return boolean
function DarkTitleScreen.handleLanguageTap(sx, sy)
    if not isOpen_ or fadeOut_ then return isOpen_ end
    if langOpen_ then
        local hits = DarkTitleScreen._langHits
        if hits then
            for i = 1, #hits do
                local r = hits[i]
                if sx >= r.x and sx <= r.x + r.w and sy >= r.y and sy <= r.y + r.h then
                    I18n.set(r.id)
                    local ok, SP = pcall(require, "ui.hud.popup.SettingsPanel")
                    if ok and SP and SP.persistLanguage then SP.persistLanguage() end
                    langOpen_ = false
                    print("[DarkTitleScreen] language=" .. r.id)
                    return true
                end
            end
        end
        local btn = DarkTitleScreen._langBtn
        if btn and sx >= btn.x and sx <= btn.x + btn.w and sy >= btn.y and sy <= btn.y + btn.h then
            langOpen_ = false
            return true
        end
        langOpen_ = false
        return true  -- 弹出打开时点空白只关菜单，不进游戏
    end
    local btn = DarkTitleScreen._langBtn
    if btn and sx >= btn.x and sx <= btn.x + btn.w and sy >= btn.y and sy <= btn.y + btn.h then
        langOpen_ = true
        print("[DarkTitleScreen] language menu open")
        return true
    end
    return false
end

return DarkTitleScreen
