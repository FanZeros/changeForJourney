-- ============================================================================
-- Viewport - 横屏 PC 多面板视口管理（changeForJourney）
-- 把 N 个 1080x2400 竖屏设计面板并排放进 1920x1080 横屏空间：
--   每面板 scale 0.45 -> 486x1080，高度占满
--   布局：左轨120 + 486 + 111 + 486 + 111 + 486 + 右轨120 = 1920
-- ============================================================================

local Viewport = {}
Viewport.ENABLED = true

Viewport.BASE_W, Viewport.BASE_H = 1920, 1080
Viewport.PW, Viewport.PH = 486, 1080  -- 1080x2400 * 0.45

-- 面板定义（横屏 base 坐标）
Viewport.PANELS = {
    left   = { id = 'left',   bx = 120,  by = 0 },
    center = { id = 'center', bx = 717,  by = 0 },
    right  = { id = 'right',  bx = 1314, by = 0 },
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
function Viewport.begin(vg, p, ox, oy, s)
    nvgSave(vg)
    nvgTranslate(vg, ox + p.bx * s, oy + p.by * s)
    nvgScale(vg, s, s)
    nvgIntersectScissor(vg, 0, 0, Viewport.PW, Viewport.PH)
end

function Viewport.finish(vg)
    nvgRestore(vg)
end

-- 屏幕逻辑坐标 -> 命中面板与该面板设计坐标
function Viewport.hit(px, py, ox, oy, s)
    for _, id in ipairs(Viewport.ORDER) do
        local p = Viewport.PANELS[id]
        local x0, y0 = ox + p.bx * s, oy + p.by * s
        if px >= x0 and px <= x0 + Viewport.PW * s and py >= y0 and py <= y0 + Viewport.PH * s then
            return id, (px - x0) / s, (py - y0) / s
        end
    end
    return nil
end

return Viewport
