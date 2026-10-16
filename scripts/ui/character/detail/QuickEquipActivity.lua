-- 一键装备的纯绘制等待态：沿用 DarkIcon 的暗铁/旧铜，不表示实际百分比。
local M = {}

function M.draw(vg, cx, cy, width, height, now)
    local phase = (now % 2.4) / 2.4
    local angle = phase * math.pi * 2
    local pulse = 0.5 + 0.5 * math.sin(angle)
    local ringX = cx - width * 0.5 + 26
    nvgSave(vg)
    -- 只与宿主裁剪相交，不改输入、全局透明度或外层滑入变换。
    nvgIntersectScissor(vg, cx - width * 0.5 + 8, cy - height * 0.5 + 8, width - 16, height - 16)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - width * 0.5 + 11, cy - height * 0.5 + 11, width - 22, height - 22, 5)
    nvgStrokeWidth(vg, 5)
    nvgStrokeColor(vg, nvgRGBA(183, 126, 64, math.floor(12 + pulse * 13)))
    nvgStroke(vg)
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBA(214, 163, 91, math.floor(52 + pulse * 36)))
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgCircle(vg, ringX, cy, 12)
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBA(124, 90, 58, 150))
    nvgStroke(vg)
    for i = 1, 2 do
        local start = i == 1 and angle or -angle + math.pi
        local radius = i == 1 and 12 or 7
        nvgBeginPath(vg)
        nvgArc(vg, ringX, cy, radius, start, start + math.pi * 1.15, NVG_CW)
        nvgStrokeWidth(vg, 5)
        nvgStrokeColor(vg, nvgRGBA(207, 146, 67, 28))
        nvgStroke(vg)
        nvgStrokeWidth(vg, 1.8)
        nvgStrokeColor(vg, nvgRGBA(239, 196, 128, i == 1 and 235 or 170))
        nvgStroke(vg)
    end

    -- 六枚微光循环而非逐个填满：长搜索也不会假装接近完成。
    for i = 1, 6 do
        local light = math.max(0, math.cos(angle - (i - 1) * math.pi / 3)) ^ 6
        local x, y = cx + (i - 3.5) * 17, cy + 29
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, 5)
        nvgFillColor(vg, nvgRGBA(220, 151, 65, math.floor(8 + light * 24)))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, y - 2.5)
        nvgLineTo(vg, x + 2.5, y)
        nvgLineTo(vg, x, y + 2.5)
        nvgLineTo(vg, x - 2.5, y)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(239, 196, 128, math.floor(45 + light * 200)))
        nvgFill(vg)
    end
    nvgRestore(vg)
end

return M
