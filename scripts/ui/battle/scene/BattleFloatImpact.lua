-- 战斗飘字「克制重击」：只绘制，不改变金额、合并、计时、预算或战斗状态。
-- 沿用独立样片的弹印/裂片/聚合/折收，时间映射到宿主已有寿命。
local DamageTypeIcon = require("ui.battle.scene.DamageTypeIcon")
local M = {}

local PRESETS = {
    damage = { duration = 0.64, holdEnd = 0.43, size = 1.0, color = { 238, 229, 206 } },
    crit = { duration = 0.76, holdEnd = 0.51, size = 1.28, color = { 255, 210, 142 } },
    heal = { duration = 0.82, holdEnd = 0.56, size = 1.0, color = { 147, 227, 171 } },
    shield = { duration = 0.66, holdEnd = 0.44, size = 0.96, color = { 190, 210, 224 } },
}
local OUTLINE = { { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 } }
local SHARDS = { { -1, -0.6, 0.3 }, { 0.8, -0.9, -0.4 }, { 1, 0.35, 0.6 } }
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function ease(v)
    local t = clamp(v, 0, 1)
    return 1 - (1 - t) ^ 3
end
local function mix(a, b, t) return a + (b - a) * t end

local function pose(ft, style, preset, side)
    local age = clamp(ft.timer / ft.duration, 0, 1) * preset.duration
    local enter = ease(age / 0.075)
    local settle = ease((age - 0.075) / 0.09)
    local out = clamp((age - preset.holdEnd) / (preset.duration - preset.holdEnd), 0, 1)
    local sx, sy = mix(0.78, 1.12, enter), mix(0.92, 1.05, enter)
    if age >= 0.075 then sx, sy = mix(1.12, 1, settle), mix(1.05, 1, settle) end
    if style == "crit" then
        sx, sy = mix(0.76, 1.17, enter), mix(0.83, 1.1, enter)
        if age >= 0.075 then sx, sy = mix(1.17, 1, settle), mix(1.1, 1, settle) end
    elseif style == "heal" then
        local grow = ease(age / 0.16)
        sx, sy = mix(0.86, 1, grow), mix(0.7, 1, grow)
    elseif style == "shield" then
        sx, sy = mix(1.14, 0.9, enter), mix(0.72, 1.08, enter)
        if age >= 0.075 then sx, sy = mix(0.9, 1, settle), mix(1.08, 1, settle) end
    end
    local pulse = clamp((ft.pulseTimer or 0) / 0.12, 0, 1)
    sx, sy = sx * (1 + 0.045 * pulse), sy * (1 + 0.045 * pulse)
    local x, y = side * 7 * (1 - settle), -3 * settle
    local angle = style == "crit" and side * -0.075 * (1 - settle) or 0
    if style == "heal" then
        x, y = 0, -4 * ease(age / 0.16)
        sx, sy = sx * (1 - out * 0.12), sy * (1 - out * 0.45)
    elseif style == "shield" then
        sx, sy = sx * (1 - out * 0.45), sy * (1 - out * 0.12)
    else
        x, sy = x + side * out * out * 12, sy * (1 - out * 0.2)
    end
    return {
        sx = sx, sy = sy, x = x, y = y, angle = angle, out = out, age = age,
        alpha = out < 0.7 and 1 or clamp((1 - out) / 0.3, 0, 1),
        impact = clamp(1 - age / 0.18, 0, 1),
    }
end

local function path(vg, points)
    nvgBeginPath(vg)
    nvgMoveTo(vg, points[1], points[2])
    for i = 3, #points, 2 do nvgLineTo(vg, points[i], points[i + 1]) end
end

local function decoration(vg, style, p, width, size)
    local half = math.max(size, width * 0.5)
    if style == "crit" then
        if p.impact > 0 then
            path(vg, { -half - 14, 9, -half * 0.45, -7, -8, 5, half * 0.4, -9, half + 14, 1 })
            nvgStrokeColor(vg, nvgRGBA(106, 31, 28, math.floor(p.impact * 210)))
            nvgStrokeWidth(vg, 7); nvgStroke(vg)
            nvgStrokeColor(vg, nvgRGBA(226, 99, 66, math.floor(p.impact * 150)))
            nvgStrokeWidth(vg, 2); nvgStroke(vg)
        end
        local burst = clamp(p.age / 0.24, 0, 1)
        local strength = (1 - burst) * 0.7 + p.out * (1 - p.out)
        if strength > 0.01 then
            for _, shard in ipairs(SHARDS) do
                nvgSave(vg)
                local spread = 12 + burst * 30 + p.out * 22
                nvgTranslate(vg, shard[1] * (half + spread), shard[2] * spread)
                nvgRotate(vg, shard[3] + burst)
                nvgBeginPath(vg); nvgMoveTo(vg, -4, -1); nvgLineTo(vg, 5, -3)
                nvgLineTo(vg, 1, 3); nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(214, 159, 108, math.floor(strength * 255)))
                nvgFill(vg); nvgRestore(vg)
            end
        end
    elseif style == "heal" then
        local progress = ease(p.age / 0.24)
        for i = 1, 3 do
            local angle = i * math.pi * 2 / 3 + 0.3
            local radius = size * (0.8 - progress * 0.35) * (1 - p.out)
            nvgBeginPath(vg)
            nvgCircle(vg, math.cos(angle) * (half + radius * 0.3), math.sin(angle) * radius, 2.4)
            nvgFillColor(vg, nvgRGBA(155, 227, 169, math.floor(((1 - progress) * 0.65 + p.out * 0.2) * 255)))
            nvgFill(vg)
        end
    elseif style == "shield" then
        local alpha = p.impact * 0.65 + p.out * 0.2
        if alpha > 0.01 then
            for _, side in ipairs({ -1, 1 }) do
                local x = side * (half + 12 - p.out * 10)
                path(vg, { x - side * 8, -14, x, -9, x, 9, x - side * 8, 14 })
                nvgStrokeColor(vg, nvgRGBA(161, 196, 217, math.floor(alpha * 255)))
                nvgStrokeWidth(vg, 2); nvgStroke(vg)
            end
        end
    elseif p.impact > 0 then
        path(vg, { -half * 0.55, size * 0.37, half * 0.55, size * 0.37 })
        nvgStrokeColor(vg, nvgRGBA(140, 116, 79, math.floor(p.impact * 110)))
        nvgStrokeWidth(vg, 2); nvgStroke(vg)
    end
end

local function glyph(vg, ft, visual, rgb, size, icon, width)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, size)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local textX = -width * 0.5 + icon + (icon > 0 and 7 or 0)
    -- 深色描边保证任何底色上都可读。
    nvgFillColor(vg, nvgRGBA(18, 15, 16, 255))
    for _, offset in ipairs(OUTLINE) do nvgText(vg, textX + offset[1], offset[2], ft.text) end
    -- 本引擎的 nvgText 不支持渐变填充（实测渐变文字会回落成首色），
    -- 因此用实色属性色：文字主体为属性色，上缘叠一条提亮高光保留立体感。
    nvgFillColor(vg, nvgRGBA(rgb[1], rgb[2], rgb[3], 255))
    nvgText(vg, textX, 0, ft.text)
    local hi = math.min(255, math.floor(0.55 * 255 + rgb[1] * 0.45))
    local hg = math.min(255, math.floor(0.55 * 255 + rgb[2] * 0.45))
    local hb = math.min(255, math.floor(0.55 * 255 + rgb[3] * 0.45))
    nvgSave(vg)
    nvgIntersectScissor(vg, textX - size, -size * 0.52, width + size * 2, size * 0.30)
    nvgFillColor(vg, nvgRGBA(hi, hg, hb, 150))
    nvgText(vg, textX, 0, ft.text)
    nvgRestore(vg)
    if icon > 0 then DamageTypeIcon.draw(vg, visual, -width * 0.5 + icon * 0.5, 0, icon) end
end

---@param ft table 宿主飘字，只读
---@param slot number 本帧同目标的展示序号，不写回战斗列表
---@param bounds? table 当前战场设计坐标范围
function M.draw(vg, ft, slot, bounds)
    if not ft.text or ft.text == "" or not ft.duration or ft.duration <= 0
        or not ft.timer or ft.timer < 0 or ft.timer >= ft.duration then return end
    local visual = DamageTypeIcon.resolve(ft, ft.kind)
    local style = visual and (visual.channel == "heal" and "heal" or visual.channel == "shield" and "shield"
        or visual.isCrit and "crit" or "damage") or "damage"
    local preset = PRESETS[style]
    local side = slot % 2 == 0 and 1 or -1
    local p = pose(ft, style, preset, side)
    if p.alpha <= 0 then return end
    local baseSize = ft.baseFontSize or ((ft.fontSize or 80) / (ft.isCrit and 2 or 1))
    local size = math.max(1, baseSize * 0.7 * preset.size)
    -- 优先用宿主按属性算好的颜色（斩击/粉碎/穿刺/火/冰/雷/暗/圣各自一色，
    -- 治疗绿、吸盾灰、暴击红）；preset.color 只作兜底，否则 8 种伤害同色。
    local rgb = ft.color or preset.color
    nvgSave(vg)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, size)
    local textWidth = nvgTextBounds(vg, 0, 0, ft.text) or size
    local icon = visual and style ~= "heal" and size * 0.72 or 0
    local width = textWidth + icon + (icon > 0 and 7 or 0)
    -- 仅压缩整组显示宽度，不截金额或改格式；外层宿主的缩放/裁剪继续生效。
    local fit = bounds and math.min(1, 200 / math.max(1, width)) or 1
    local row = (slot - 1) % 3
    local column = math.floor((slot - 1) / 3)
    local x = ft.x + p.x + (row == 1 and -12 or row == 2 and 12 or 0)
        + (column > 0 and (column % 2 == 0 and -1 or 1) * math.ceil(column / 2) * 28 or 0)
    local y = ft.y + p.y + (row == 1 and -76 or row == 2 and 76 or -4)
    if bounds then
        local mx = math.min(bounds.w * 0.5, width * p.sx * fit * 0.5 + 48 * fit)
        local my = math.min(bounds.h * 0.5, math.max(size * p.sy * fit * 0.7, 34) + 6)
        x = clamp(x, bounds.x + mx, bounds.x + bounds.w - mx)
        y = clamp(y, bounds.y + my, bounds.y + bounds.h - my)
        nvgIntersectScissor(vg, bounds.x, bounds.y, bounds.w, bounds.h)
    end
    nvgTranslate(vg, x, y); nvgRotate(vg, p.angle); nvgScale(vg, p.sx * fit, p.sy * fit)
    nvgGlobalAlpha(vg, p.alpha)
    if visual then decoration(vg, style, p, width, size) end
    if p.out > 0 and (style == "damage" or style == "crit") then
        local bands = style == "crit" and 3 or 1
        local height = size * 1.6
        for i = 1, bands do
            nvgSave(vg)
            local bandY = -height * 0.5 + (i - 1) * height / bands
            nvgIntersectScissor(vg, -width * 0.5 - 4, bandY, (width + 8) * (1 - p.out), height / bands)
            nvgTranslate(vg, (i % 2 == 0 and -1 or 1) * p.out * 7, 0)
            glyph(vg, ft, visual, rgb, size, icon, width)
            nvgRestore(vg)
        end
    else
        glyph(vg, ft, visual, rgb, size, icon, width)
    end
    nvgRestore(vg)
end

return M
