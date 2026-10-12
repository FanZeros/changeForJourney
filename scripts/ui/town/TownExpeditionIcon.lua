-- 城镇远征名牌白色罗盘：独立矢量模块，不依赖彩色素材/角标设置。
local M = {}
function M.draw(vg, cx, cy, size)
    nvgSave(vg)
    local radius = size * 0.36
    -- 黑色外描边与白色轮廓对应城镇其他白色小图标。
    for _, stroke in ipairs({ { 7, 0, 0, 0 }, { 3, 255, 255, 255 } }) do
        nvgStrokeWidth(vg, stroke[1] * size / 48)
        nvgStrokeColor(vg, nvgRGBA(stroke[2], stroke[3], stroke[4], 255))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, radius)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy - radius - size * 0.09)
        nvgLineTo(vg, cx, cy - radius + size * 0.09)
        nvgMoveTo(vg, cx, cy + radius - size * 0.09)
        nvgLineTo(vg, cx, cy + radius + size * 0.09)
        nvgMoveTo(vg, cx - radius - size * 0.09, cy)
        nvgLineTo(vg, cx - radius + size * 0.09, cy)
        nvgMoveTo(vg, cx + radius - size * 0.09, cy)
        nvgLineTo(vg, cx + radius + size * 0.09, cy)
        nvgStroke(vg)
    end
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + size * 0.17, cy - size * 0.24)
    nvgLineTo(vg, cx + size * 0.065, cy + size * 0.08)
    nvgLineTo(vg, cx - size * 0.17, cy + size * 0.24)
    nvgLineTo(vg, cx - size * 0.065, cy - size * 0.08)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgFill(vg)
    nvgStrokeWidth(vg, size / 24)
    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 255))
    nvgStroke(vg)
    nvgRestore(vg)
end
return M
