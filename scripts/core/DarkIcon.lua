-- ============================================================================
-- DarkIcon - 暗黑魔塔风格 · 程序化矢量图标库 (P0)
-- ----------------------------------------------------------------------------
-- 目标: 用纯 NanoVG 矢量代码复刻绘制暗黑画风图标, 替代亮色卡通贴图。
-- 原则:
--   1. 零贴图依赖 —— 全部矢量绘制, 任意尺寸清晰
--   2. 中心点定位 —— draw(vg, name, cx, cy, size, alpha), 与原 drawImageCentered 对齐
--   3. alpha 全链路透传 —— 所有颜色预乘全局 alpha
--   4. 每帧重绘 —— 与原 nvgImagePattern 相同模式, 无纹理显存占用
-- 风格: 近黑暖调底 / 铁灰金属倒角 / 骨白铭刻 / 血红-余烬-琥珀点缀
-- ============================================================================

local DrawUtil = require("core.DrawUtil")

local DarkIcon = {}

-- ============================================================================
-- 调色板（暗黑魔塔主题）
-- ============================================================================

DarkIcon.Palette = {
    BG_DEEP  = { 13,  11,   9},   -- 近黑暖底
    METAL_D  = { 30,  26,  21},   -- 暗铁
    METAL_M  = { 48,  42,  34},   -- 中铁
    METAL_L  = { 96,  86,  70},   -- 铁高光
    BONE     = {216, 201, 163},   -- 骨白
    BONE_DIM = {150, 138, 110},   -- 暗骨
    OUTLINE  = { 10,   8,   6},   -- 万物描边
    GOLD     = {201, 151,  59},
    GOLD_HI  = {240, 199,  94},
    GOLD_DK  = {110,  78,  24},
    BLOOD    = {166,  30,  30},
    BLOOD_HI = {224,  72,  72},
    BLOOD_DK = {110,  16,  16},
    EMBER    = {255, 122,  40},   -- 余烬橙
    STEEL_L  = {168, 160, 146},   -- 钢高光
    STEEL_M  = {104,  96,  84},
    STEEL_D  = { 46,  42,  36},
}

--- 装备品质主题色（1粗铁 2青铜 3秘银 4符文 5黄金 6血钻）
local QUALITY_TRIM = {
    {138, 133, 120},
    { 95, 158,  62},
    { 62, 126, 194},
    {138,  78, 194},
    {216, 158,  46},
    {196,  58,  30},
}

DarkIcon.QUALITY_NAMES = { "粗铁", "青铜", "秘银", "符文", "黄金", "血钻" }
DarkIcon.QUALITY_TRIM  = QUALITY_TRIM  -- [暗黑化 P1-B5] 品质色表导出：plain 样式按品质传 accent 用

--- 底部导航页签图标名（顺序与 BottomNav.tabs 一致）
DarkIcon.NAV_NAMES = { "nav_hero", "nav_log", "nav_battle", "nav_town", "nav_dungeon" }

--- 画廊验收页开关（验收通过后置 false）
DarkIcon.SHOWCASE = false

-- ============================================================================
-- 绘制原语
-- ============================================================================

--- alpha(0-1) 与颜色 alpha(0-1) 合成到 0-255
local function mul255(alpha, a)
    local v = math.floor(alpha * a * 255 + 0.5)
    if v < 0 then v = 0 elseif v > 255 then v = 255 end
    return v
end

--- 纯色填充
local function fillC(vg, alpha, r, g, b, a)
    nvgFillColor(vg, nvgRGBA(r, g, b, mul255(alpha, a or 1)))
end

--- 纯色描边
local function strokeC(vg, alpha, r, g, b, a)
    nvgStrokeColor(vg, nvgRGBA(r, g, b, mul255(alpha, a or 1)))
end

--- 垂直渐变 paint（跨 y0→y1）
---@return NVGpaint paint
local function vGrad(vg, y0, y1, c1, c2, alpha, a1, a2)
    return nvgLinearGradient(vg, 0, y0, 0, y1,
        nvgRGBA(c1[1], c1[2], c1[3], mul255(alpha, a1 or 1)),
        nvgRGBA(c2[1], c2[2], c2[3], mul255(alpha, a2 or 1)))
end

--- 径向渐变 paint（inr→outr，色 c1→c2）
---@return NVGpaint paint
local function radGrad(vg, cx, cy, r0, r1, c1, c2, alpha, a1, a2)
    return nvgRadialGradient(vg, cx, cy, r0, r1,
        nvgRGBA(c1[1], c1[2], c1[3], mul255(alpha, a1 or 1)),
        nvgRGBA(c2[1], c2[2], c2[3], mul255(alpha, a2 or 1)))
end

--- 通用外描边（暗色，保证图标在任何底色上可读）
local function outline(vg, alpha, s)
    nvgStrokeColor(vg, nvgRGBA(10, 8, 6, mul255(alpha, 0.55)))
    nvgStrokeWidth(vg, math.max(1.5, s * 0.022))
    nvgStroke(vg)
end

--- 菱形路径（中心 cx,cy 半径 r）
local function diamondPath(vg, cx, cy, r)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, cy - r)
    nvgLineTo(vg, cx + r, cy)
    nvgLineTo(vg, cx, cy + r)
    nvgLineTo(vg, cx - r, cy)
    nvgClosePath(vg)
end

--- 火焰外轮廓路径（泪滴形，底宽顶尖）
local function flamePath(vg, cx, cy, s)
    local w  = s * 0.36
    local by = cy + s * 0.44
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - w, by - s * 0.16)
    nvgBezierTo(vg, cx - w, by, cx + w, by, cx + w, by - s * 0.16)
    nvgBezierTo(vg, cx + w * 1.02, cy - s * 0.02, cx + w * 0.42, cy - s * 0.20, cx + s * 0.03, cy - s * 0.48)
    nvgBezierTo(vg, cx - w * 0.42, cy - s * 0.20, cx - w * 1.02, cy - s * 0.02, cx - w, by - s * 0.16)
    nvgClosePath(vg)
end

--- 竖直长剑（原点为剑身中心，供旋转复用；粗描边 + 扁平渐变）
local function swordAtOrigin(vg, s, alpha)
    -- 剑刃
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -s * 0.50)
    nvgLineTo(vg, s * 0.085, -s * 0.28)
    nvgLineTo(vg, s * 0.085, s * 0.12)
    nvgLineTo(vg, 0, s * 0.20)
    nvgLineTo(vg, -s * 0.085, s * 0.12)
    nvgLineTo(vg, -s * 0.085, -s * 0.28)
    nvgClosePath(vg)
    nvgFillPaint(vg, vGrad(vg, -s * 0.5, s * 0.2,
        DarkIcon.Palette.STEEL_L, DarkIcon.Palette.STEEL_D, alpha))
    nvgFill(vg)
    -- 粗描边（与整套图标一致的卡通描边，不做渐隐）
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -s * 0.50)
    nvgLineTo(vg, s * 0.085, -s * 0.28)
    nvgLineTo(vg, s * 0.085, s * 0.12)
    nvgLineTo(vg, 0, s * 0.20)
    nvgLineTo(vg, -s * 0.085, s * 0.12)
    nvgLineTo(vg, -s * 0.085, -s * 0.28)
    nvgClosePath(vg)
    nvgStrokeColor(vg, nvgRGBA(10, 8, 6, mul255(alpha, 1)))
    nvgStrokeWidth(vg, math.max(2, s * 0.030))
    nvgStroke(vg)
    -- 血槽
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -s * 0.40)
    nvgLineTo(vg, 0, s * 0.08)
    strokeC(vg, alpha, 40, 36, 30, 0.85)
    nvgStrokeWidth(vg, math.max(1, s * 0.022))
    nvgStroke(vg)
    -- 护手
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -s * 0.20, s * 0.12, s * 0.40, s * 0.055, s * 0.02)
    fillC(vg, alpha, 122, 88, 30, 1)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -s * 0.20, s * 0.12, s * 0.40, s * 0.055, s * 0.02)
    strokeC(vg, alpha, 10, 8, 6, 1)
    nvgStrokeWidth(vg, math.max(1.5, s * 0.022))
    nvgStroke(vg)
    -- 剑柄
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -s * 0.032, s * 0.175, s * 0.064, s * 0.15, s * 0.015)
    fillC(vg, alpha, 58, 42, 30, 1)
    nvgFill(vg)
    -- 柄尾宝石
    nvgBeginPath(vg)
    nvgCircle(vg, 0, s * 0.36, s * 0.048)
    fillC(vg, alpha, 240, 199, 94, 1)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, 0, s * 0.36, s * 0.048)
    strokeC(vg, alpha, 10, 8, 6, 1)
    nvgStrokeWidth(vg, math.max(1.5, s * 0.020))
    nvgStroke(vg)
end

-- ============================================================================
-- 图标绘制器（name → function(vg, cx, cy, s, alpha, opts)）
-- ============================================================================

local painters = {}

--- 金币（暗金做旧）
painters.gold = function(vg, cx, cy, s, alpha)
    local r = s * 0.47
    -- 外缘暗铜环
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r)
    fillC(vg, alpha, 74, 54, 20, 1)
    nvgFill(vg)
    outline(vg, alpha, s)
    -- 锤纹主面
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r * 0.80)
    nvgFillPaint(vg, radGrad(vg, cx - r * 0.35, cy - r * 0.35, r * 0.1, r * 1.05,
        DarkIcon.Palette.GOLD_HI, DarkIcon.Palette.GOLD_DK, alpha))
    nvgFill(vg)
    -- 内环刻线
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r * 0.56)
    strokeC(vg, alpha, 110, 78, 24, 0.9)
    nvgStrokeWidth(vg, math.max(1, s * 0.026))
    nvgStroke(vg)
    -- 中央菱形印记
    diamondPath(vg, cx, cy, s * 0.17)
    fillC(vg, alpha, 160, 116, 40, 1)
    nvgFill(vg)
    diamondPath(vg, cx, cy, s * 0.17)
    strokeC(vg, alpha, 10, 8, 6, 0.45)
    nvgStrokeWidth(vg, math.max(1, s * 0.016))
    nvgStroke(vg)
    -- 左上高光点
    nvgBeginPath(vg)
    nvgCircle(vg, cx - s * 0.24, cy - s * 0.26, s * 0.055)
    fillC(vg, alpha, 247, 230, 170, 0.9)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, cx - s * 0.13, cy - s * 0.33, s * 0.028)
    fillC(vg, alpha, 247, 230, 170, 0.55)
    nvgFill(vg)
end

--- 宝石（血红六棱切面）
painters.gem = function(vg, cx, cy, s, alpha)
    local R = s * 0.46
    local function hexPts(rr)
        local pts = {}
        for k = 0, 5 do
            local a = math.rad(-90 + k * 60)
            pts[k + 1] = { cx + rr * math.cos(a), cy + rr * math.sin(a) }
        end
        return pts
    end
    local outer = hexPts(R)
    -- 外形
    nvgBeginPath(vg)
    nvgMoveTo(vg, outer[1][1], outer[1][2])
    for k = 2, 6 do nvgLineTo(vg, outer[k][1], outer[k][2]) end
    nvgClosePath(vg)
    fillC(vg, alpha, 140, 20, 20, 1)
    nvgFill(vg)
    outline(vg, alpha, s)
    -- 底部暗面（下方两棱到中心）
    local function facet(i1, i2, r, g, b, a)
        nvgBeginPath(vg)
        nvgMoveTo(vg, outer[i1][1], outer[i1][2])
        nvgLineTo(vg, outer[i2][1], outer[i2][2])
        nvgLineTo(vg, cx, cy)
        nvgClosePath(vg)
        fillC(vg, alpha, r, g, b, a)
        nvgFill(vg)
    end
    facet(3, 4, 176, 26, 26, 1)   -- 右下
    facet(4, 5, 104, 14, 14, 1)   -- 底
    facet(2, 3, 206, 42, 42, 1)   -- 右上受光
    facet(5, 6, 120, 16, 16, 1)   -- 左下背光
    -- 顶面台
    local table = hexPts(R * 0.52)
    nvgBeginPath(vg)
    nvgMoveTo(vg, table[1][1], table[1][2])
    for k = 2, 6 do nvgLineTo(vg, table[k][1], table[k][2]) end
    nvgClosePath(vg)
    fillC(vg, alpha, 224, 72, 72, 1)
    nvgFill(vg)
    -- 台面高光
    nvgBeginPath(vg)
    nvgMoveTo(vg, table[6][1], table[6][2])
    nvgLineTo(vg, table[1][1], table[1][2])
    nvgLineTo(vg, table[2][1], table[2][2])
    nvgLineTo(vg, cx - R * 0.05, cy - R * 0.05)
    nvgClosePath(vg)
    fillC(vg, alpha, 255, 150, 140, 0.45)
    nvgFill(vg)
    -- 内部血光
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, R * 0.42)
    nvgFillPaint(vg, radGrad(vg, cx, cy, 0, R * 0.42,
        { 255, 110, 110 }, { 255, 110, 110 }, alpha, 0.30, 0))
    nvgFill(vg)
end

--- 战力（余烬火焰）
painters.power = function(vg, cx, cy, s, alpha)
    -- 外焰
    flamePath(vg, cx, cy, s)
    nvgFillPaint(vg, vGrad(vg, cy - s * 0.48, cy + s * 0.44,
        { 255, 180, 60 }, { 122, 28, 8 }, alpha))
    nvgFill(vg)
    outline(vg, alpha * 0.8, s)
    -- 内焰
    flamePath(vg, cx, cy + s * 0.10, s * 0.52)
    nvgFillPaint(vg, vGrad(vg, cy - s * 0.15, cy + s * 0.44,
        { 255, 224, 138 }, { 232, 93, 26 }, alpha))
    nvgFill(vg)
    -- 焰芯
    flamePath(vg, cx, cy + s * 0.20, s * 0.26)
    fillC(vg, alpha, 255, 240, 190, 0.95)
    nvgFill(vg)
end

--- 红点（余烬光点 + 白色感叹号）
painters.reddot = function(vg, cx, cy, s, alpha)
    -- 外辉光
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, s * 0.48)
    nvgFillPaint(vg, radGrad(vg, cx, cy, s * 0.10, s * 0.48,
        DarkIcon.Palette.EMBER, DarkIcon.Palette.EMBER, alpha, 0.45, 0))
    nvgFill(vg)
    -- 核心
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, s * 0.24)
    fillC(vg, alpha, 202, 34, 26, 1)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, s * 0.24)
    strokeC(vg, alpha, 255, 255, 255, 0.9)
    nvgStrokeWidth(vg, math.max(1.5, s * 0.035))
    nvgStroke(vg)
    -- 白色感叹号（竖条 + 圆点）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - s * 0.038, cy - s * 0.16, s * 0.076, s * 0.18, s * 0.038)
    fillC(vg, alpha, 255, 255, 255, 1)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy + s * 0.125, s * 0.045)
    fillC(vg, alpha, 255, 255, 255, 1)
    nvgFill(vg)
end

--- 角色（大头盔）
painters.nav_hero = function(vg, cx, cy, s, alpha)
    -- 盔体（高圆顶 + 微收下缘）
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - s * 0.32, cy + s * 0.14)
    nvgBezierTo(vg, cx - s * 0.36, cy - s * 0.52, cx + s * 0.36, cy - s * 0.52, cx + s * 0.32, cy + s * 0.14)
    nvgLineTo(vg, cx + s * 0.36, cy + s * 0.34)
    nvgLineTo(vg, cx - s * 0.36, cy + s * 0.34)
    nvgClosePath(vg)
    nvgFillPaint(vg, vGrad(vg, cy - s * 0.42, cy + s * 0.34,
        DarkIcon.Palette.STEEL_L, DarkIcon.Palette.STEEL_D, alpha))
    nvgFill(vg)
    outline(vg, alpha, s)
    -- 盔顶高光
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - s * 0.17, cy - s * 0.26)
    nvgBezierTo(vg, cx - s * 0.08, cy - s * 0.40, cx + s * 0.08, cy - s * 0.40, cx + s * 0.17, cy - s * 0.26)
    strokeC(vg, alpha, 222, 214, 198, 0.6)
    nvgStrokeWidth(vg, math.max(1, s * 0.035))
    nvgStroke(vg)
    -- T 字面甲缝（窄缝，避免误读为挂锁）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - s * 0.025, cy - s * 0.34, s * 0.05, s * 0.42, s * 0.02)
    fillC(vg, alpha, 8, 7, 5, 1)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - s * 0.20, cy + s * 0.06, s * 0.40, s * 0.06, s * 0.028)
    fillC(vg, alpha, 8, 7, 5, 1)
    nvgFill(vg)
    -- 呼吸孔
    for k = -1, 1 do
        nvgBeginPath(vg)
        nvgCircle(vg, cx + k * s * 0.06, cy + s * 0.22, s * 0.015)
        fillC(vg, alpha, 8, 7, 5, 0.9)
        nvgFill(vg)
    end
    -- 侧铆钉
    for _, kx in ipairs({ -1, 1 }) do
        nvgBeginPath(vg)
        nvgCircle(vg, cx + kx * s * 0.26, cy - s * 0.10, s * 0.024)
        fillC(vg, alpha, 130, 120, 104, 1)
        nvgFill(vg)
    end
end

--- 日志（符文典籍）
painters.nav_log = function(vg, cx, cy, s, alpha)
    -- 封皮
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - s * 0.34, cy - s * 0.42, s * 0.68, s * 0.84, s * 0.07)
    nvgFillPaint(vg, vGrad(vg, cy - s * 0.42, cy + s * 0.42,
        { 84, 60, 36 }, { 40, 27, 15 }, alpha))
    nvgFill(vg)
    outline(vg, alpha, s)
    -- 书脊
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - s * 0.34, cy - s * 0.42, s * 0.11, s * 0.84, s * 0.07)
    fillC(vg, alpha, 28, 19, 11, 1)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - s * 0.225, cy - s * 0.36)
    nvgLineTo(vg, cx - s * 0.225, cy + s * 0.36)
    strokeC(vg, alpha, 140, 118, 82, 0.5)
    nvgStrokeWidth(vg, math.max(1, s * 0.018))
    nvgStroke(vg)
    -- 页缘
    nvgBeginPath(vg)
    nvgRect(vg, cx + s * 0.26, cy - s * 0.37, s * 0.06, s * 0.74)
    fillC(vg, alpha, 176, 158, 120, 0.95)
    nvgFill(vg)
    -- 金符文
    nvgBeginPath(vg)
    nvgCircle(vg, cx + s * 0.04, cy, s * 0.22)
    nvgFillPaint(vg, radGrad(vg, cx + s * 0.04, cy, 0, s * 0.22,
        DarkIcon.Palette.GOLD_HI, DarkIcon.Palette.GOLD_HI, alpha, 0.30, 0))
    nvgFill(vg)
    diamondPath(vg, cx + s * 0.04, cy, s * 0.13)
    fillC(vg, alpha, 240, 199, 94, 1)
    nvgFill(vg)
    diamondPath(vg, cx + s * 0.04, cy, s * 0.055)
    fillC(vg, alpha, 255, 240, 200, 1)
    nvgFill(vg)
    -- 角扣
    for _, ky in ipairs({ -1, 1 }) do
        nvgBeginPath(vg)
        nvgCircle(vg, cx + s * 0.28, cy + ky * s * 0.36, s * 0.032)
        fillC(vg, alpha, 160, 118, 44, 1)
        nvgFill(vg)
    end
end

--- 战斗（交叉双剑 · 粗描边风格，无光影）
painters.nav_battle = function(vg, cx, cy, s, alpha)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, math.rad(45))
    swordAtOrigin(vg, s, alpha)
    nvgRestore(vg)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, math.rad(-45))
    swordAtOrigin(vg, s, alpha)
    nvgRestore(vg)
end

--- 城镇（石砌塔楼）
painters.nav_town = function(vg, cx, cy, s, alpha)
    -- 塔身
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - s * 0.30, cy - s * 0.12, s * 0.60, s * 0.56, s * 0.03)
    nvgFillPaint(vg, vGrad(vg, cy - s * 0.12, cy + s * 0.44,
        { 104, 95, 79 }, { 44, 38, 30 }, alpha))
    nvgFill(vg)
    outline(vg, alpha, s)
    -- 垛口
    local mw = s * 0.16
    local mxs = { -s * 0.30, -s * 0.08, s * 0.14 }
    for _, mx in ipairs(mxs) do
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx + mx, cy - s * 0.26, mw, s * 0.15, s * 0.02)
        fillC(vg, alpha, 112, 102, 85, 1)
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx + mx, cy - s * 0.26, mw, s * 0.15, s * 0.02)
        strokeC(vg, alpha, 10, 8, 6, 0.55)
        nvgStrokeWidth(vg, math.max(1, s * 0.018))
        nvgStroke(vg)
    end
    -- 砖缝
    strokeC(vg, alpha, 20, 17, 13, 0.55)
    nvgStrokeWidth(vg, math.max(1, s * 0.014))
    for _, ly in ipairs({ 0.05, 0.20, 0.33 }) do
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s * 0.30, cy + s * ly)
        nvgLineTo(vg, cx + s * 0.30, cy + s * ly)
        nvgStroke(vg)
    end
    -- 错缝竖线
    local ticks = { { -0.18, 0.05 }, { 0.10, 0.05 }, { -0.02, 0.20 }, { 0.22, 0.20 }, { 0.16, 0.33 } }
    for _, tk in ipairs(ticks) do
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + s * tk[1], cy + s * (tk[2] - 0.10))
        nvgLineTo(vg, cx + s * tk[1], cy + s * tk[2])
        nvgStroke(vg)
    end
    -- 拱门
    nvgBeginPath(vg)
    nvgRoundedRectVarying(vg, cx - s * 0.10, cy + s * 0.10, s * 0.20, s * 0.34,
        s * 0.10, s * 0.10, 0, 0)
    fillC(vg, alpha, 10, 8, 6, 1)
    nvgFill(vg)
    -- 箭窗（余烬光）
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy - s * 0.02, s * 0.09)
    nvgFillPaint(vg, radGrad(vg, cx, cy - s * 0.02, 0, s * 0.09,
        DarkIcon.Palette.EMBER, DarkIcon.Palette.EMBER, alpha, 0.5, 0))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - s * 0.022, cy - s * 0.075, s * 0.044, s * 0.11, s * 0.02)
    fillC(vg, alpha, 255, 170, 70, 0.95)
    nvgFill(vg)
end

--- 副本（余烬骷髅）
painters.nav_dungeon = function(vg, cx, cy, s, alpha)
    -- 骨白辉光
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, s * 0.55)
    nvgFillPaint(vg, radGrad(vg, cx, cy, s * 0.15, s * 0.55,
        DarkIcon.Palette.BONE, DarkIcon.Palette.BONE, alpha, 0.14, 0))
    nvgFill(vg)
    -- 颅顶
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, cy - s * 0.08, s * 0.30, s * 0.27)
    nvgFillPaint(vg, vGrad(vg, cy - s * 0.35, cy + s * 0.15,
        DarkIcon.Palette.BONE, { 138, 123, 94 }, alpha))
    nvgFill(vg)
    outline(vg, alpha * 0.7, s)
    -- 下颚
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - s * 0.17, cy + s * 0.10, s * 0.34, s * 0.20, s * 0.06)
    fillC(vg, alpha, 150, 134, 102, 1)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - s * 0.17, cy + s * 0.10, s * 0.34, s * 0.20, s * 0.06)
    strokeC(vg, alpha, 10, 8, 6, 0.4)
    nvgStrokeWidth(vg, math.max(1, s * 0.016))
    nvgStroke(vg)
    -- 眼窝（余烬瞳光）
    for _, kx in ipairs({ -1, 1 }) do
        nvgBeginPath(vg)
        nvgCircle(vg, cx + kx * s * 0.115, cy - s * 0.06, s * 0.078)
        fillC(vg, alpha, 12, 9, 7, 1)
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, cx + kx * s * 0.115, cy - s * 0.06, s * 0.05)
        nvgFillPaint(vg, radGrad(vg, cx + kx * s * 0.115, cy - s * 0.06, 0, s * 0.05,
            DarkIcon.Palette.EMBER, DarkIcon.Palette.EMBER, alpha, 0.95, 0))
        nvgFill(vg)
    end
    -- 鼻孔
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, cy + s * 0.02)
    nvgLineTo(vg, cx + s * 0.045, cy + s * 0.10)
    nvgLineTo(vg, cx - s * 0.045, cy + s * 0.10)
    nvgClosePath(vg)
    fillC(vg, alpha, 12, 9, 7, 1)
    nvgFill(vg)
    -- 牙缝
    strokeC(vg, alpha, 70, 58, 42, 0.9)
    nvgStrokeWidth(vg, math.max(1, s * 0.018))
    for _, tx in ipairs({ -0.06, 0, 0.06 }) do
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + s * tx, cy + s * 0.13)
        nvgLineTo(vg, cx + s * tx, cy + s * 0.26)
        nvgStroke(vg)
    end
end

-- ============================================================================
-- Public API
-- ============================================================================

--- 绘制暗黑图标
---@param vg any NanoVG 上下文
---@param name string 图标名: gold/gem/power/reddot/nav_hero/nav_log/nav_battle/nav_town/nav_dungeon
---@param cx number 中心 X（设计空间）
---@param cy number 中心 Y（设计空间）
---@param size number 边长
---@param alpha number 透明度 0-1
---@param opts table|nil 可选扩展参数（保留）
function DarkIcon.draw(vg, name, cx, cy, size, alpha, opts)
    local p = painters[name]
    if not p then return end
    local a = alpha or 1
    if a <= 0.01 then return end
    p(vg, cx, cy, size, a, opts)
end

--- 绘制装备品质框（暗黑金属边框 + 品质饰色 + 角铆钉）
---@param vg any
---@param quality number 品质 1-6
---@param cx number 中心 X
---@param cy number 中心 Y
---@param w number 宽
---@param h number 高
---@param alpha number 透明度 0-1
function DarkIcon.drawQualityFrame(vg, quality, cx, cy, w, h, alpha)
    local a = alpha or 1
    if a <= 0.01 then return end
    local q = math.max(1, math.min(6, math.floor(quality or 1)))
    local trim = QUALITY_TRIM[q]
    local u = math.min(w, h)
    local x, y = cx - w * 0.5, cy - h * 0.5
    local r = u * 0.10

    -- 高品质外辉光
    if q >= 3 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x - 3, y - 3, w + 6, h + 6, r + 2)
        strokeC(vg, a, trim[1], trim[2], trim[3], q >= 5 and 0.22 or 0.12)
        nvgStrokeWidth(vg, u * 0.045)
        nvgStroke(vg)
    end
    if q >= 5 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x - 7, y - 7, w + 14, h + 14, r + 5)
        strokeC(vg, a, trim[1], trim[2], trim[3], 0.10)
        nvgStrokeWidth(vg, u * 0.05)
        nvgStroke(vg)
    end

    -- 底体
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillPaint(vg, vGrad(vg, y, y + h, { 32, 27, 21 }, { 16, 13, 10 }, a))
    nvgFill(vg)
    -- 外描边
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    strokeC(vg, a, 0, 0, 0, 0.6)
    nvgStrokeWidth(vg, math.max(1.5, u * 0.018))
    nvgStroke(vg)
    -- 金属倒角（上亮下暗渐变描边）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + u * 0.015, y + u * 0.015, w - u * 0.03, h - u * 0.03, r * 0.85)
    nvgStrokePaint(vg, vGrad(vg, y, y + h, DarkIcon.Palette.METAL_L, { 12, 10, 8 }, a))
    nvgStrokeWidth(vg, math.max(1, u * 0.03))
    nvgStroke(vg)
    -- 品质饰边
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + u * 0.07, y + u * 0.07, w - u * 0.14, h - u * 0.14, r * 0.6)
    strokeC(vg, a, trim[1], trim[2], trim[3], 0.9)
    nvgStrokeWidth(vg, math.max(1, u * 0.025))
    nvgStroke(vg)
    -- 角铆钉
    local inset = u * 0.07
    local studR = u * 0.040
    for _, sx in ipairs({ x + inset, x + w - inset }) do
        for _, sy in ipairs({ y + inset, y + h - inset }) do
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, studR)
            fillC(vg, a, trim[1], trim[2], trim[3], 1)
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, studR)
            strokeC(vg, a, 0, 0, 0, 0.55)
            nvgStrokeWidth(vg, math.max(1, u * 0.012))
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, sx - studR * 0.3, sy - studR * 0.3, studR * 0.3)
            fillC(vg, a, 255, 250, 230, 0.75)
            nvgFill(vg)
        end
    end
end

--- 品质底框统一入口（P2-A）：替代 UI_icon_ZBBJ_1~6 / KP_TY_N~UR 贴图
--- 与 drawImageCentered 同参风格（中心点定位），quality 自动 clamp 1-6
---@param vg any
---@param quality number 品质（1粗铁 2青铜 3秘银 4符文 5黄金 6血钻）
---@param cx number 中心 X
---@param cy number 中心 Y
---@param w number 宽
---@param h number 高
---@param alpha number|nil 透明度 0-1（默认 1）
function DarkIcon.drawQualityBg(vg, quality, cx, cy, w, h, alpha)
    local q = math.floor(tonumber(quality) or 1)
    DarkIcon.drawQualityFrame(vg, math.max(1, math.min(6, q)), cx, cy, w, h, alpha or 1)
end

--- 明显压暗档 tint（P2-B）：装备/神器等彩色图标整体压至约 28% 亮度（乘法叠色，保留透明底）
--- 可调档：数值越低越暗；白 (255,255,255) = 原样
DarkIcon.ICON_TINT_DARK = { 72, 64, 54 }

--- 图标压暗绘制（P2-B）：装备/神器/天赋等亮色卡通风图标的暗黑化
--- 与 drawImageCentered 同参风格（中心点定位）；乘法叠色保留源图透明通道
---@param vg any
---@param img number nvgCreateImage 句柄
---@param cx number 中心 X
---@param cy number 中心 Y
---@param w number 宽
---@param h number 高
---@param alpha number|nil 透明度 0-1（默认 1）
function DarkIcon.drawIconDark(vg, img, cx, cy, w, h, alpha)
    local a = alpha or 1
    if a <= 0.01 or not img or img < 0 then return end
    local t = DarkIcon.ICON_TINT_DARK
    local x, y = cx - w * 0.5, cy - h * 0.5
    local tint = nvgRGBA(t[1], t[2], t[3], math.floor(a * 255 + 0.5))
    local paint = nvgImagePatternTinted(vg, x, y, w, h, 0, img, tint)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 暗黑场景底图：压暗 tint + 边缘晕影（用于关卡地图等大幅明亮底图的暗黑化）
--- tint 取暖灰（保留暖色层次），晕影聚焦战场中心；alpha 用于场景切换过渡
---@param vg any
---@param img number nvgCreateImage 句柄
---@param cx number 中心 X
---@param cy number 中心 Y
---@param w number 宽
---@param h number 高
---@param alpha number 透明度 0-1
function DarkIcon.drawDarkScene(vg, img, cx, cy, w, h, alpha)
    local a = alpha or 1
    if a <= 0.01 then return end
    local x, y = cx - w * 0.5, cy - h * 0.5

    -- 1) 暖灰压暗 tint（约 38% 亮度，保留暖色层次）
    local tint = nvgRGBA(96, 84, 72, math.floor(a * 255 + 0.5))
    local paint = nvgImagePatternTinted(vg, x, y, w, h, 0, img, tint)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)

    -- 2) 边缘晕影（中心透明 → 四角压黑，聚焦战场）
    local rIn = math.min(w, h) * 0.38
    local rOut = math.max(w, h) * 0.62
    local vig = nvgRadialGradient(vg, cx, cy, rIn, rOut,
        nvgRGBA(5, 4, 3, 0), nvgRGBA(5, 4, 3, math.floor(a * 150 + 0.5)))
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, vig)
    nvgFill(vg)
end

-- ============================================================================
-- 矢量九宫格面板体系（Track B · 替代贴图九宫格，见 docs/暗黑魔塔改造总体方案.md §4）
-- ============================================================================

--- 语义色表
local NINE_ACCENTS = {
    gold   = { 201, 151,  59 },
    green  = {  95, 158,  62 },
    blue   = {  62, 126, 194 },
    red    = { 196,  58,  30 },
    purple = { 138,  78, 194 },
}

--- 解析 accent 参数（字符串键 / {r,g,b} 表）
local function resolveAccent(v, default)
    if not v then return default end
    if type(v) == "table" then return v end
    return NINE_ACCENTS[v] or default
end

--- 暗黑矢量面板（直接绘制，天然任意拉伸，无需切片）
---@param vg any
---@param style string "panel" 弹窗底(标题带+金饰线) | "plain" 纯底板
---                   | "btn" 按钮条 | "slot" 凹槽 | "fill" 进度填充
---@param x number 左上角 X（与 drawNineSlice 同参风格）
---@param y number 左上角 Y
---@param w number 宽
---@param h number 高
---@param opts table|nil { accent, titleH, studs, radius, alpha }
function DarkIcon.drawNine(vg, style, x, y, w, h, opts)
    local a = (opts and opts.alpha) or 1
    if a <= 0.01 then return end
    opts = opts or {}
    local u = math.min(w, h)
    local accent = resolveAccent(opts.accent, NINE_ACCENTS.gold)

    if style == "panel" then
        local r = opts.radius or u * 0.046
        local bandH = opts.titleH or math.max(70, math.min(190, h * 0.17))
        if bandH > h * 0.5 then bandH = h * 0.5 end
        -- 1) 标题带（整块圆角底）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, r)
        nvgFillPaint(vg, vGrad(vg, y, y + bandH, { 36, 30, 23 }, { 23, 18, 13 }, a))
        nvgFill(vg)
        -- 2) 主体（自金线起，底部圆角）
        nvgBeginPath(vg)
        nvgRoundedRectVarying(vg, x, y + bandH, w, h - bandH, 0, 0, r, r)
        nvgFillPaint(vg, vGrad(vg, y + bandH, y + h, { 28, 23, 18 }, { 16, 13, 10 }, a))
        nvgFill(vg)
        -- 3) 语义饰线 + 端点菱形
        nvgBeginPath(vg)
        nvgMoveTo(vg, x + r * 0.4, y + bandH)
        nvgLineTo(vg, x + w - r * 0.4, y + bandH)
        strokeC(vg, a, accent[1], accent[2], accent[3], 0.9)
        nvgStrokeWidth(vg, math.max(1.5, u * 0.006))
        nvgStroke(vg)
        if opts.studs ~= false and w > 220 then
            diamondPath(vg, x + r * 0.4, y + bandH, u * 0.028)
            fillC(vg, a, accent[1], accent[2], accent[3], 1)
            nvgFill(vg)
            diamondPath(vg, x + w - r * 0.4, y + bandH, u * 0.028)
            fillC(vg, a, accent[1], accent[2], accent[3], 1)
            nvgFill(vg)
        end
        -- 4) 骨白发丝内衬
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x + u * 0.014, y + u * 0.014, w - u * 0.028, h - u * 0.028, r * 0.85)
        strokeC(vg, a, 216, 201, 163, 0.08)
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        -- 5) 顶缘高光 + 外描边
        nvgBeginPath(vg)
        nvgMoveTo(vg, x + r * 0.5, y + 1)
        nvgLineTo(vg, x + w - r * 0.5, y + 1)
        strokeC(vg, a, 150, 134, 111, 0.5)
        nvgStrokeWidth(vg, math.max(1, u * 0.004))
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, r)
        strokeC(vg, a, 0, 0, 0, 0.6)
        nvgStrokeWidth(vg, math.max(1.5, u * 0.006))
        nvgStroke(vg)
    elseif style == "plain" then
        local r = opts.radius or u * 0.06
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, r)
        nvgFillPaint(vg, vGrad(vg, y, y + h, { 28, 23, 18 }, { 16, 13, 10 }, a))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x + u * 0.016, y + u * 0.016, w - u * 0.032, h - u * 0.032, r * 0.85)
        strokeC(vg, a, 216, 201, 163, 0.08)
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, r)
        if opts.accent then
            -- 语义色描边（品质/稀有度编码的可选支持）
            strokeC(vg, a, accent[1], accent[2], accent[3], 0.55)
            nvgStrokeWidth(vg, math.max(1.5, u * 0.02))
        else
            strokeC(vg, a, 0, 0, 0, 0.6)
            nvgStrokeWidth(vg, math.max(1.5, u * 0.008))
        end
        nvgStroke(vg)
    elseif style == "btn" then
        local br = opts.radius or h * 0.3
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, br)
        nvgFillPaint(vg, vGrad(vg, y, y + h, { 42, 36, 29 }, { 26, 21, 16 }, a))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, br)
        strokeC(vg, a, accent[1], accent[2], accent[3], 0.95)
        nvgStrokeWidth(vg, math.max(1.5, u * 0.03))
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x + br * 0.6, y + math.max(1.5, h * 0.08))
        nvgLineTo(vg, x + w - br * 0.6, y + math.max(1.5, h * 0.08))
        strokeC(vg, a, accent[1], accent[2], accent[3], 0.3)
        nvgStrokeWidth(vg, math.max(1, u * 0.02))
        nvgStroke(vg)
    elseif style == "slot" then
        local sr = opts.radius or h * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, sr)
        fillC(vg, a, 16, 13, 10, 1)
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x + sr * 0.5, y + math.max(1, h * 0.2))
        nvgLineTo(vg, x + w - sr * 0.5, y + math.max(1, h * 0.2))
        strokeC(vg, a, 0, 0, 0, 0.5)
        nvgStrokeWidth(vg, math.max(1, u * 0.03))
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, sr)
        strokeC(vg, a, 0, 0, 0, 0.55)
        nvgStrokeWidth(vg, math.max(1, u * 0.022))
        nvgStroke(vg)
    elseif style == "fill" then
        local fr = opts.radius or h * 0.5
        local cDark = { accent[1] * 0.55, accent[2] * 0.55, accent[3] * 0.55 }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, fr)
        nvgFillPaint(vg, vGrad(vg, y, y + h, accent, cDark, a))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x + fr * 0.5, y + math.max(1, h * 0.22))
        nvgLineTo(vg, x + w - fr * 0.5, y + math.max(1, h * 0.22))
        strokeC(vg, a, 255, 240, 200, 0.5)
        nvgStrokeWidth(vg, math.max(1, u * 0.02))
        nvgStroke(vg)
    end
end

-- ============================================================================
-- 画廊验收页（新旧对比）
-- ============================================================================

---@type table<string, string> 旧图标贴图路径（对比用）
local OLD_PATHS = {
    gold         = "image/UI_icon_JB_X.png",
    gem          = "image/UI_icon_SJ_X.png",
    power        = "image/ICON_ZDL.png",
    reddot       = "image/ICON_HD.png",
    nav_hero     = "image/ICON_GN_1.png",
    nav_log      = "image/ICON_GN_2.png",
    nav_battle   = "image/ICON_GN_3.png",
    nav_town     = "image/ICON_GN_4.png",
    nav_dungeon  = "image/ICON_GN_5.png",
}

---@type table<string, number> 旧图标句柄缓存
local oldImgs = {}

local function getOldImg(vg, name)
    local h = oldImgs[name]
    if h then return h end
    h = nvgCreateImage(vg, OLD_PATHS[name] or "", 0)
    oldImgs[name] = h
    return h
end

local function drawOldIcon(vg, img, cx, cy, size)
    if not img or img < 0 then return end
    local x, y = cx - size * 0.5, cy - size * 0.5
    local paint = nvgImagePattern(vg, x, y, size, size, 0, img, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, size, size)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 画廊单元：新图标（大）+ 旧图标（右下小）+ 名称
local function showcaseCell(vg, name, label, cx, cy, size)
    DarkIcon.draw(vg, name, cx, cy, size, 1)
    local old = getOldImg(vg, name)
    if old and old >= 0 then
        drawOldIcon(vg, old, cx + size * 0.38, cy + size * 0.38, size * 0.34)
    end
    DrawUtil.drawTextStroke(vg, cx, cy + size * 0.62, label, 26,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 216, 201, 163, 2)
end

--- 绘制画廊验收页（设计空间 1080x2400，在 Standalone 末尾调用）
---@param vg any
function DarkIcon.drawShowcase(vg)
    local P = DarkIcon.Palette
    -- 背景幕
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(13, 11, 9, 247))
    nvgFill(vg)

    -- 标题
    DrawUtil.drawTextStroke(vg, 540, 150, "暗黑魔塔 · 图标画廊", 64,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 240, 199, 94, 4)
    DrawUtil.drawTextStroke(vg, 540, 218, "core/DarkIcon.lua 程序化矢量绘制 · 右下角小图为原图", 28,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 150, 138, 110, 2)

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 80, 268)
    nvgLineTo(vg, 1000, 268)
    strokeC(vg, 1, 96, 86, 70, 0.6)
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 一、功能图标
    DrawUtil.drawTextStroke(vg, 84, 330, "功能图标", 40,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 201, 151, 59, 3)
    local funcs = { { "gold", "金币" }, { "gem", "钻石" }, { "power", "战力" }, { "reddot", "红点" } }
    for k, it in ipairs(funcs) do
        showcaseCell(vg, it[1], it[2], 120 + (k - 1) * 280, 520, 170)
    end

    -- 二、导航页签
    DrawUtil.drawTextStroke(vg, 84, 700, "导航页签", 40,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 201, 151, 59, 3)
    local navLabels = { "角色", "日志", "战斗", "城镇", "副本" }
    for k = 1, 5 do
        local cx = 108 + (k - 1) * 216
        DarkIcon.draw(vg, DarkIcon.NAV_NAMES[k], cx, 920, 140, 1)
        local old = getOldImg(vg, DarkIcon.NAV_NAMES[k])
        if old and old >= 0 then
            drawOldIcon(vg, old, cx + 52, 972, 50)
        end
        DrawUtil.drawTextStroke(vg, cx, 1030, navLabels[k], 30,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 216, 201, 163, 2)
    end

    -- 三、装备品质框
    DrawUtil.drawTextStroke(vg, 84, 1170, "装备品质框", 40,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 201, 151, 59, 3)
    for q = 1, 6 do
        local cx = 130 + (q - 1) * 164
        DarkIcon.drawQualityFrame(vg, q, cx, 1360, 150, 150, 1)
        DrawUtil.drawTextStroke(vg, cx, 1462, q .. "品 " .. DarkIcon.QUALITY_NAMES[q], 26,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 216, 201, 163, 2)
    end

    -- 四、矢量九宫格（drawNine 五种样式验收）
    DrawUtil.drawTextStroke(vg, 84, 1560, "矢量九宫格 drawNine", 40,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 201, 151, 59, 3)
    -- panel 弹窗底（含标题带文字示意，实际由各模块自绘）
    DarkIcon.drawNine(vg, "panel", 70, 1620, 400, 280)
    DrawUtil.drawTextStroke(vg, 270, 1655, "面板 panel", 30,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 216, 201, 163, 2)
    -- plain 纯底板
    DarkIcon.drawNine(vg, "plain", 510, 1620, 260, 180)
    -- btn 按钮条（金/绿/红语义色）
    DarkIcon.drawNine(vg, "btn", 810, 1620, 210, 64, { accent = "gold" })
    DarkIcon.drawNine(vg, "btn", 810, 1700, 210, 64, { accent = "green" })
    DarkIcon.drawNine(vg, "btn", 810, 1780, 210, 64, { accent = "red" })
    -- slot 凹槽 + fill 进度填充（余烬/蓝）
    DarkIcon.drawNine(vg, "slot", 70, 1950, 420, 34)
    DarkIcon.drawNine(vg, "fill", 73, 1953, 290, 28)
    DarkIcon.drawNine(vg, "slot", 530, 1950, 300, 34)
    DarkIcon.drawNine(vg, "fill", 533, 1953, 180, 28, { accent = "blue" })
    -- 区块标注
    DrawUtil.drawTextStroke(vg, 270, 1935, "panel", 26,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 150, 138, 110, 2)
    DrawUtil.drawTextStroke(vg, 640, 1835, "plain", 26,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 150, 138, 110, 2)
    DrawUtil.drawTextStroke(vg, 915, 1880, "btn", 26,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 150, 138, 110, 2)
    DrawUtil.drawTextStroke(vg, 510, 2035, "slot + fill (ember / blue)", 26,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 150, 138, 110, 2)

    -- 五、细节样张（大图验收）
    DrawUtil.drawTextStroke(vg, 84, 2140, "细节样张", 40,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 201, 151, 59, 3)
    DarkIcon.draw(vg, "nav_battle", 230, 2280, 190, 1)
    DarkIcon.draw(vg, "nav_dungeon", 540, 2280, 190, 1)
    DarkIcon.draw(vg, "gem", 850, 2280, 190, 1)

    -- 页脚
    DrawUtil.drawTextStroke(vg, 540, 2390, "P1: drawNine 迁移 AnnouncementPanel → MailPanel → … · 关卡地图暗黑滤镜", 26,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 150, 138, 110, 2)
end

-- ============================================================================
-- 天赋符号系统（P2-10 试点）：矢量统一重绘替代 85 张 KTX 贴图
-- 结构：金属铭牌底座 + 系色符文符号；符号按效果类型归 ~10 类，覆盖全部 153 语义名
-- ============================================================================

--- 天赋 5 系色（与节点 color 字段映射）
local TALENT_COLORS = {
    红 = { 196,  58,  30 },
    绿 = {  95, 158,  62 },
    黄 = { 216, 158,  46 },
    蓝 = {  62, 126, 194 },
    紫 = { 138,  78, 194 },
    无 = { 150, 138, 110 },
}

--- 金属铭牌底座（圆形，暗铁渐变 + 系色饰环 + 黑描边）
local function drawTalentMedal(vg, colorKey, cx, cy, size, a)
    local r = size * 0.5
    local col = TALENT_COLORS[colorKey] or TALENT_COLORS["无"]
    -- 外黑描边
    nvgBeginPath(vg); nvgCircle(vg, cx, cy, r)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(a * 255)))
    nvgFill(vg)
    -- 主体暗铁渐变
    nvgBeginPath(vg); nvgCircle(vg, cx, cy, r * 0.92)
    nvgFillPaint(vg, vGrad(vg, cy - r, cy + r, { 44, 38, 30 }, { 18, 15, 11 }, a))
    nvgFill(vg)
    -- 系色饰环
    nvgBeginPath(vg); nvgCircle(vg, cx, cy, r * 0.78)
    strokeC(vg, a, col[1], col[2], col[3], 0.85)
    nvgStrokeWidth(vg, math.max(1.2, size * 0.035))
    nvgStroke(vg)
    -- 内圈细线（精细层次）
    nvgBeginPath(vg); nvgCircle(vg, cx, cy, r * 0.60)
    strokeC(vg, a, col[1], col[2], col[3], 0.35)
    nvgStrokeWidth(vg, math.max(1, size * 0.018))
    nvgStroke(vg)
    -- 顶缘高光
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy, r * 0.88, -2.6, -0.6, NVG_CW)
    strokeC(vg, a, 150, 134, 111, 0.5)
    nvgStrokeWidth(vg, math.max(1, size * 0.02))
    nvgStroke(vg)
end

-- 各符号 painter：在 (cx,cy) 中心、半径 s 内绘制系色符号（粗黑描边+系色填充+高光）
local glyphPainters

local function glyphPath(vg, col, a)
    nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], math.floor(a * 235)))
    -- [fix] 描边改系色亮调（原黑色描边导致线描类符号——剑刃/法杖杆/风弧/弓——暗底上不可见）
    local hl = {
        math.floor(col[1] + (255 - col[1]) * 0.45),
        math.floor(col[2] + (255 - col[2]) * 0.45),
        math.floor(col[3] + (255 - col[3]) * 0.45),
    }
    nvgStrokeColor(vg, nvgRGBA(hl[1], hl[2], hl[3], math.floor(a * 255)))
end

glyphPainters = {
    -- 剑（攻击/物理）：斜置单手剑
    sword = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s * 0.34, cy + s * 0.34)
        nvgLineTo(vg, cx + s * 0.30, cy - s * 0.30)
        nvgStrokeWidth(vg, s * 0.11); nvgLineCap(vg, NVG_BUTT)
        nvgStroke(vg)
        -- 护手与柄
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s * 0.10, cy + s * 0.14); nvgLineTo(vg, cx + s * 0.14, cy - s * 0.10)
        nvgStrokeWidth(vg, s * 0.10); nvgStroke(vg)
        nvgBeginPath(vg); nvgCircle(vg, cx - s * 0.34, cy + s * 0.34, s * 0.08)
        nvgFill(vg)
    end,
    -- 盾（防御/壁垒）
    shield = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy - s * 0.42)
        nvgLineTo(vg, cx + s * 0.34, cy - s * 0.26)
        nvgLineTo(vg, cx + s * 0.28, cy + s * 0.14)
        nvgQuadTo(vg, cx + s * 0.22, cy + s * 0.40, cx, cy + s * 0.46)
        nvgQuadTo(vg, cx - s * 0.22, cy + s * 0.40, cx - s * 0.28, cy + s * 0.14)
        nvgLineTo(vg, cx - s * 0.34, cy - s * 0.26)
        nvgClosePath(vg)
        nvgFill(vg); nvgStrokeWidth(vg, s * 0.035); nvgStroke(vg)
    end,
    -- 药瓶（治疗/生命）
    potion = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        -- 瓶身圆
        nvgBeginPath(vg); nvgCircle(vg, cx, cy + s * 0.12, s * 0.30)
        nvgFill(vg); nvgStrokeWidth(vg, s * 0.035); nvgStroke(vg)
        -- 瓶颈
        nvgBeginPath(vg)
        nvgRect(vg, cx - s * 0.09, cy - s * 0.36, s * 0.18, s * 0.22)
        nvgFill(vg); nvgStroke(vg)
        -- 瓶塞
        nvgBeginPath(vg)
        nvgRect(vg, cx - s * 0.13, cy - s * 0.46, s * 0.26, s * 0.12)
        nvgFillColor(vg, nvgRGBA(150, 134, 111, math.floor(a * 235)))
        nvgFill(vg)
    end,
    -- 法杖（奥术）：斜杆 + 顶端宝珠（杆加粗、珠放大提升辨识度）
    staff = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s * 0.26, cy + s * 0.40)
        nvgLineTo(vg, cx + s * 0.24, cy - s * 0.24)
        nvgStrokeWidth(vg, s * 0.085); nvgStroke(vg)
        -- 顶端宝珠 + 光芒
        nvgBeginPath(vg); nvgCircle(vg, cx + s * 0.30, cy - s * 0.32, s * 0.18)
        nvgFill(vg); nvgStrokeWidth(vg, s * 0.03); nvgStroke(vg)
        nvgBeginPath(vg); nvgCircle(vg, cx + s * 0.30, cy - s * 0.32, s * 0.30)
        strokeC(vg, a, col[1], col[2], col[3], 0.4)
        nvgStrokeWidth(vg, s * 0.03); nvgStroke(vg)
    end,
    -- 星（暴击/终极）
    star = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        nvgBeginPath(vg)
        for i = 0, 9 do
            local ang = -math.pi * 0.5 + i * math.pi * 0.2
            local rr = (i % 2 == 0) and s * 0.44 or s * 0.18
            local px, py = cx + math.cos(ang) * rr, cy + math.sin(ang) * rr
            if i == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
        end
        nvgClosePath(vg)
        nvgFill(vg); nvgStrokeWidth(vg, s * 0.03); nvgStroke(vg)
    end,
    -- 准星（瞄准/致命）
    crosshair = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        nvgBeginPath(vg); nvgCircle(vg, cx, cy, s * 0.30)
        nvgStrokeWidth(vg, s * 0.07); nvgStroke(vg)
        nvgBeginPath(vg)
        for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
            nvgMoveTo(vg, cx + d[1] * s * 0.16, cy + d[2] * s * 0.16)
            nvgLineTo(vg, cx + d[1] * s * 0.44, cy + d[2] * s * 0.44)
        end
        nvgStrokeWidth(vg, s * 0.07); nvgStroke(vg)
        nvgBeginPath(vg); nvgCircle(vg, cx, cy, s * 0.08)
        nvgFill(vg)
    end,
    -- 风/羽（急速/闪避）：三道弧形风刃
    wind = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        for i = 0, 2 do
            nvgBeginPath(vg)
            local oy = (i - 1) * s * 0.24
            nvgMoveTo(vg, cx - s * 0.38, cy + oy)
            nvgQuadTo(vg, cx + s * 0.10, cy + oy - s * 0.16, cx + s * 0.38, cy + oy)
            nvgStrokeWidth(vg, s * 0.075 - i * s * 0.015)
            nvgLineCap(vg, NVG_ROUND)
            nvgStroke(vg)
        end
    end,
    -- 弓（远程）
    bow = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, s * 0.40, -math.pi * 0.42, math.pi * 0.42, NVG_CW)
        nvgStrokeWidth(vg, s * 0.09); nvgStroke(vg)
        -- 弦
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + s * 0.40 * math.cos(-math.pi * 0.42), cy + s * 0.40 * math.sin(-math.pi * 0.42))
        nvgLineTo(vg, cx + s * 0.40 * math.cos(math.pi * 0.42), cy + s * 0.40 * math.sin(math.pi * 0.42))
        nvgStrokeWidth(vg, s * 0.03); nvgStroke(vg)
        -- 箭
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s * 0.30, cy); nvgLineTo(vg, cx + s * 0.34, cy)
        nvgStrokeWidth(vg, s * 0.035); nvgStroke(vg)
    end,
    -- 书（博学/魔典）
    tome = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        -- 封面（右页）
        nvgBeginPath(vg)
        nvgRect(vg, cx - s * 0.34, cy - s * 0.30, s * 0.62, s * 0.60)
        nvgFill(vg); nvgStrokeWidth(vg, s * 0.035); nvgStroke(vg)
        -- 书脊
        nvgBeginPath(vg)
        nvgRect(vg, cx - s * 0.42, cy - s * 0.34, s * 0.10, s * 0.68)
        nvgFillColor(vg, nvgRGBA(150, 134, 111, math.floor(a * 235)))
        nvgFill(vg)
        -- 封面符文星
        nvgBeginPath(vg); nvgCircle(vg, cx + s * 0.0, cy + s * 0.0, s * 0.14)
        strokeC(vg, a, 230, 215, 180, 0.9)
        nvgStrokeWidth(vg, s * 0.03); nvgStroke(vg)
    end,
    -- 拳（体魄/力量）
    fist = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - s * 0.30, cy - s * 0.22, s * 0.56, s * 0.48, s * 0.12)
        nvgFill(vg); nvgStrokeWidth(vg, s * 0.035); nvgStroke(vg)
        -- 指节
        nvgBeginPath(vg)
        for i = 0, 2 do
            nvgMoveTo(vg, cx - s * 0.18 + i * s * 0.18, cy - s * 0.22)
            nvgLineTo(vg, cx - s * 0.18 + i * s * 0.18, cy - s * 0.06)
        end
        nvgStrokeWidth(vg, s * 0.032); nvgStroke(vg)
        -- 腕
        nvgBeginPath(vg)
        nvgRect(vg, cx - s * 0.18, cy + s * 0.26, s * 0.36, s * 0.16)
        nvgFill(vg)
    end,
    -- 头盔（骑士/假面）
    helm = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy + s * 0.06, s * 0.36, math.pi, 0, NVG_CW)
        nvgLineTo(vg, cx + s * 0.36, cy + s * 0.30)
        nvgLineTo(vg, cx - s * 0.36, cy + s * 0.30)
        nvgClosePath(vg)
        nvgFill(vg); nvgStrokeWidth(vg, s * 0.035); nvgStroke(vg)
        -- 面甲缝
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s * 0.20, cy + s * 0.10); nvgLineTo(vg, cx + s * 0.20, cy + s * 0.10)
        nvgMoveTo(vg, cx - s * 0.16, cy + s * 0.22); nvgLineTo(vg, cx + s * 0.16, cy + s * 0.22)
        strokeC(vg, a, 0, 0, 0, 0.85)
        nvgStrokeWidth(vg, s * 0.032); nvgStroke(vg)
        -- 顶脊
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy - s * 0.40); nvgLineTo(vg, cx, cy - s * 0.16)
        strokeC(vg, a, 230, 215, 180, 0.7)
        nvgStrokeWidth(vg, s * 0.035); nvgStroke(vg)
    end,
    -- 指环（印记/徽记）
    ring = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        nvgBeginPath(vg); nvgCircle(vg, cx, cy + s * 0.08, s * 0.28)
        nvgStrokeWidth(vg, s * 0.11); nvgStroke(vg)
        -- 宝石
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy - s * 0.36)
        nvgLineTo(vg, cx + s * 0.14, cy - s * 0.22)
        nvgLineTo(vg, cx, cy - s * 0.08)
        nvgLineTo(vg, cx - s * 0.14, cy - s * 0.22)
        nvgClosePath(vg)
        nvgFill(vg); nvgStrokeWidth(vg, s * 0.03); nvgStroke(vg)
    end,
    -- 旗（战旗/鼓舞）
    flag = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        -- 旗杆
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s * 0.30, cy - s * 0.44); nvgLineTo(vg, cx - s * 0.30, cy + s * 0.44)
        nvgStrokeWidth(vg, s * 0.07); nvgStroke(vg)
        -- 旗面
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s * 0.24, cy - s * 0.38)
        nvgLineTo(vg, cx + s * 0.36, cy - s * 0.26)
        nvgLineTo(vg, cx + s * 0.16, cy - s * 0.02)
        nvgLineTo(vg, cx + s * 0.36, cy + s * 0.22)
        nvgLineTo(vg, cx - s * 0.24, cy + s * 0.10)
        nvgClosePath(vg)
        nvgFill(vg); nvgStrokeWidth(vg, s * 0.032); nvgStroke(vg)
    end,
    -- 问号（终焉环占位节点：待填充内容）
    query = function(vg, cx, cy, s, col, a)
        glyphPath(vg, col, a)
        nvgFontSize(vg, s * 0.72)
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], math.floor(a * 235)))
        nvgText(vg, cx, cy - s * 0.02, "？", nil)
    end,
}

--- 天赋语义名 → 符号类型关键词规则（顺序敏感：先专后泛，命中即返）
--- 新增天赋节点自动归类，无需逐名维护
local TALENT_KIND_RULES = {
    { "？？", "query" },  -- [终焉环] 占位节点专属问号符号
    { "弓", "bow" },   { "箭", "bow" },   { "狙", "bow" },   { "射手", "bow" },
    { "瞄准", "crosshair" }, { "准星", "crosshair" }, { "致命", "crosshair" },
    { "暴击", "crosshair" }, { "弱点", "crosshair" }, { "钻心", "crosshair" }, { "狩猎", "crosshair" },
    { "盾", "shield" }, { "壁垒", "shield" }, { "铠甲", "shield" }, { "重甲", "shield" },
    { "甲", "shield" }, { "屏障", "shield" }, { "壁垒", "shield" }, { "守护", "shield" },
    { "誓约", "shield" }, { "龟壳", "shield" }, { "磐石", "shield" }, { "结界", "shield" },
    { "护幕", "shield" }, { "圣域", "shield" }, { "反击", "shield" },
    { "治疗", "potion" }, { "愈", "potion" }, { "生机", "potion" }, { "回春", "potion" },
    { "生命", "potion" }, { "泉", "potion" }, { "恩泽", "potion" }, { "祷言", "potion" },
    { "圣辉", "potion" }, { "仁心", "potion" }, { "牧师", "potion" }, { "回响", "potion" },
    { "杖", "staff" }, { "魔", "staff" }, { "奥术", "staff" }, { "秘法", "staff" },
    { "秘纹", "staff" }, { "星", "staff" }, { "法核", "staff" }, { "魔导", "staff" },
    { "虚空", "staff" }, { "深渊", "staff" }, { "法阵", "staff" }, { "法环", "staff" },
    { "魔力", "staff" }, { "法盾", "staff" }, { "魔法", "staff" }, { "蚀", "staff" },
    { "魔法帽", "staff" }, { "法帽", "staff" },  -- [fix] 法系"魔法帽"先于 helm 的"帽"命中，避免误画头盔
    { "帽", "helm" }, { "盔", "helm" }, { "假面", "helm" }, { "面具", "helm" }, { "骑士", "helm" },
    { "步", "wind" }, { "灵敏", "wind" }, { "灵巧", "wind" }, { "急速", "wind" },
    { "风", "wind" }, { "蝉翼", "wind" }, { "影", "wind" }, { "闪避", "wind" },
    { "指环", "ring" },
    { "旗", "flag" }, { "鼓舞", "flag" }, { "战吼", "flag" }, { "号角", "flag" }, { "誓约", "flag" },
    { "印记", "ring" }, { "徽", "ring" }, { "之魂", "ring" }, { "共鸣", "ring" },
    { "帽", "helm" }, { "盔", "helm" }, { "假面", "helm" }, { "面具", "helm" }, { "骑士", "helm" },
    { "书", "tome" }, { "博学", "tome" }, { "聪颖", "tome" }, { "魔典", "tome" }, { "之悟", "tome" },
    { "拳", "fist" }, { "体", "fist" }, { "力量", "fist" },
    { "剑", "sword" }, { "刃", "sword" }, { "锋", "sword" }, { "锤", "sword" }, { "斧", "sword" },
    { "斩", "sword" }, { "击", "sword" }, { "杀", "sword" }, { "刺", "sword" }, { "刀", "sword" },
    { "破甲", "sword" }, { "连击", "sword" }, { "连斩", "sword" }, { "攻势", "sword" }, { "狂暴", "sword" },
}

--- 按语义名解析符号类型（先专后泛，fallback star）
---@param name string 天赋节点名
---@return string kind
function DarkIcon.matchTalentKind(name)
    if not name then return "star" end
    for _, rule in ipairs(TALENT_KIND_RULES) do
        if string.find(name, rule[1], 1, true) then return rule[2] end
    end
    return "star"
end

--- 按语义名直接绘制天赋符号（铭牌 + 符号）
---@param vg any
---@param name string 天赋节点名
---@param colorKey string 系别: 红/绿/黄/蓝/紫/无
---@param cx number 中心 X
---@param cy number 中心 Y
---@param size number 直径
---@param alpha number|nil 透明度 0-1
function DarkIcon.drawTalentGlyphByName(vg, name, colorKey, cx, cy, size, alpha)
    DarkIcon.drawTalentGlyph(vg, DarkIcon.matchTalentKind(name), colorKey, cx, cy, size, alpha)
end

--- 天赋矢量符号图标（P2-10 试点）：铭牌底座 + 效果类型符号 + 系色
---@param vg any
---@param kind string 符号类型: sword/shield/potion/staff/star/crosshair/wind/bow
---@param colorKey string 系别: 红/绿/黄/蓝/紫/无
---@param cx number 中心 X
---@param cy number 中心 Y
---@param size number 直径
---@param alpha number|nil 透明度 0-1
function DarkIcon.drawTalentGlyph(vg, kind, colorKey, cx, cy, size, alpha)
    local a = alpha or 1
    if a <= 0.01 then return end
    local col = TALENT_COLORS[colorKey] or TALENT_COLORS["无"]
    local painter = glyphPainters[kind] or glyphPainters.star
    drawTalentMedal(vg, colorKey, cx, cy, size, a)
    nvgSave(vg)
    painter(vg, cx, cy, size * 0.92, col, a)
    nvgRestore(vg)
end

DarkIcon.TALENT_COLORS = TALENT_COLORS
DarkIcon.drawTalentMedal = drawTalentMedal  -- [混合方案用] 金属铭牌底座独立暴露

return DarkIcon
