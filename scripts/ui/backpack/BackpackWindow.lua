-- 仓库旧全窗模态适配：绘制和输入共用同一 letterbox 坐标变换。
local M = {}

function M.bind(deps)
    local function layout(logicalW, logicalH, rect)
        local rx, ry = rect and rect.x or 0, rect and rect.y or 0
        local rw, rh = rect and rect.w or logicalW, rect and rect.h or logicalH
        local fit = math.min(rw / deps.width, rh / deps.height)
        return rx, ry, rw, rh, fit,
            rx + (rw - deps.width * fit) * 0.5,
            ry + (rh - deps.height * fit) * 0.5
    end
    local function draw(vg, logicalW, logicalH, rect)
        if not deps.isOpen() or not deps.isWindowMode() then return end
        local rx, ry, rw, rh, fit, x, y = layout(logicalW, logicalH, rect)
        nvgBeginPath(vg)
        nvgRect(vg, rx, ry, rw, rh)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
        nvgFill(vg)
        nvgSave(vg)
        nvgTranslate(vg, x, y)
        nvgScale(vg, fit, fit)
        deps.drawBody(vg)
        nvgRestore(vg)
    end
    local function toDesignCoords(wx, wy, logicalW, logicalH, rect)
        local _, _, _, _, fit, x, y = layout(logicalW, logicalH, rect)
        return (wx - x) / fit, (wy - y) / fit
    end
    return draw, toDesignCoords
end
return M
