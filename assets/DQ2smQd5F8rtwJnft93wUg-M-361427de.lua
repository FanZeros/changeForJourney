-- ============================================================================
-- Viewport - 横屏 PC 多面板视口管理（changeForJourney）
-- 把 N 个 1080x2400 竖屏设计面板并排放进 1920x1080 横屏空间：
--   每面板 scale 0.45 -> 486x1080，高度占满
--   布局：左轨120 + 486 + 111 + 486 + 111 + 486 + 右轨120 = 1920
-- ============================================================================

local Viewport = {}
Viewport.ENABLED = true

Viewport.BASE_W, Viewport.BASE_H = 1458, 1080  -- 3 x 486 面板无缝拼接
Viewport.PW, Viewport.PH = 486, 1080  -- 面板视口（base 坐标，1080x2400 * DS）
Viewport.DESIGN_W, Viewport.DESIGN_H = 1080, 2400  -- 竖屏设计稿
Viewport.DS = 0.45                                   -- 设计缩放：设计稿 -> 面板视口

-- 面板定义（横屏 base 坐标，无间隔紧贴）
Viewport.PANELS = {
    left   = { id = 'left',   bx = 0,   by = 0 },
    center = { id = 'center', bx = 486, by = 0 },
    right  = { id = 'right',  bx = 972, by = 0 },
}
Viewport.ORDER = { 'left', 'center', 'right' }

-- 计算横屏 letterbox：实际逻辑窗口 -> 偏移与等比缩放
function Viewport.layout(logicalW, logicalH)
    local s = math.min(logicalW / Viewport.BASE_W, logicalH / Viewport.BASE_H)
    local ox = (logicalW - Viewport.BASE_W * s) * 0.5
    local oy = (logicalH - Viewport.BASE_H * s) * 0.5
    return ox, oy, s
end

-- 进入面板设计空间（1080x2400 坐标系，页面代码零改动）
-- [修复] 原实现缺少 DS 缩放：内容按 s 直接绘制且裁剪区只有 486x1080，
-- 导致每个面板只显示设计稿左上角（半宽、不到半高）。现按 s*DS 缩放内容、
-- 裁剪区放宽到完整设计稿，面板完整显示 1080x2400
function Viewport.begin(vg, p, ox, oy, s)
    nvgSave(vg)
    nvgTranslate(vg, ox + p.bx * s, oy + p.by * s)
    local cs = s * Viewport.DS
    nvgScale(vg, cs, cs)
    nvgIntersectScissor(vg, 0, 0, Viewport.DESIGN_W, Viewport.DESIGN_H)
end

function Viewport.finish(vg)
    nvgRestore(vg)
end

-- 屏幕逻辑坐标 -> 命中面板与该面板设计坐标（除数与 begin 的内容缩放一致）
function Viewport.hit(px, py, ox, oy, s)
    local cs = s * Viewport.DS
    for _, id in ipairs(Viewport.ORDER) do
        local p = Viewport.PANELS[id]
        local x0, y0 = ox + p.bx * s, oy + p.by * s
        if px >= x0 and px <= x0 + Viewport.PW * s and py >= y0 and py <= y0 + Viewport.PH * s then
            return id, (px - x0) / cs, (py - y0) / cs
        end
    end
    return nil
end

return Viewport
