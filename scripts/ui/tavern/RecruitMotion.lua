-- 招募牌背的铜金短流纹。沿宿主卡牌变换绘制，绝不进入正面文字区域。
-- 不创建纹理/粒子/时间队列，只采样调用方给定的局部进度。
local M = {}

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function point(distance, width, height)
    local perimeter = 2 * (width + height)
    local d = distance % perimeter
    if d < width then return d - width * 0.5, -height * 0.5 end
    if d < width + height then return width * 0.5, d - width - height * 0.5 end
    if d < 2 * width + height then return width * 1.5 + height - d, height * 0.5 end
    return -width * 0.5, perimeter - d - height * 0.5
end

---@param vg any
---@param cx number
---@param cy number
---@param width number
---@param height number
---@param t number 当前牌的0..1局部进度，不是全局时间
---@param alpha number
function M.drawBackEdge(vg, cx, cy, width, height, t, alpha)
    if vg == nil or not finite(cx) or not finite(cy) or not finite(width) or not finite(height)
        or not finite(t) or not finite(alpha) or width <= 20 or height <= 20
        or t <= 0 or t >= 0.58 or alpha <= 0 then return end
    local progress = t / 0.58
    local envelope = math.sin(progress * math.pi) * math.max(0, math.min(1, alpha))
    local w, h = width - 12, height - 12
    local perimeter = 2 * (w + h)
    nvgSave(vg)
    -- 两段短纹只在牌背内缘行进，保持中部契约印与稀有度/名称干净。
    for trail = 1, 2 do
        local head = (progress * 0.55 + (trail - 1) * 0.5) * perimeter
        for segment = 1, 5 do
            local distance = head - segment * 5
            local x1, y1 = point(distance, w, h)
            local x2, y2 = point(distance + 4, w, h)
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx + x1, cy + y1)
            nvgLineTo(vg, cx + x2, cy + y2)
            nvgStrokeWidth(vg, 1.25)
            nvgStrokeColor(vg, nvgRGBA(212, 170, 96, math.floor((138 - segment * 18) * envelope)))
            nvgStroke(vg)
        end
    end
    nvgRestore(vg)
end

return M
