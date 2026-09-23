-- ============================================================================
-- UiToast - 全屏短提示（右键装备失败/成功等）
-- 逻辑分辨率坐标，由 StandaloneHorizon 在 nvgEndFrame 前绘制。
-- ============================================================================

local UiToast = {}

local text_ = nil ---@type string|nil
local until_ = 0
local DURATION = 1.25

---@param text string
---@param duration number|nil
function UiToast.show(text, duration)
    if not text or text == "" then return end
    text_ = text
    until_ = time.elapsedTime + (duration or DURATION)
end

function UiToast.clear()
    text_ = nil
    until_ = 0
end

---@param vg any
---@param w number
---@param h number
function UiToast.draw(vg, w, h)
    if not text_ then return end
    local remain = until_ - time.elapsedTime
    if remain <= 0 then
        text_ = nil
        return
    end
    local alpha = 1.0
    local elapsed = DURATION - remain
    if elapsed < 0.12 then
        alpha = elapsed / 0.12
    elseif remain < 0.25 then
        alpha = remain / 0.25
    end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(22, math.min(w * 0.022, 34)))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local tw = nvgTextBounds(vg, 0, 0, text_)
    local padX, padY = 28, 14
    local tw2 = tw + padX * 2
    local th = 48
    local cx, cy = w * 0.5, h * 0.18
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - tw2 * 0.5, cy - th * 0.5, tw2, th, 12)
    nvgFillColor(vg, nvgRGBA(12, 10, 8, math.floor(200 * alpha)))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(196, 160, 90, math.floor(180 * alpha)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgFillColor(vg, nvgRGBA(244, 237, 224, math.floor(255 * alpha)))
    nvgText(vg, cx, cy, text_, nil)
end

return UiToast
