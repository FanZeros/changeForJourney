local Contours = require("ui.widget.TalentGlyphContours")
local ExtraPainters = require("ui.widget.TalentGlyphExtra")

---@class TalentGlyphSample
---@field id? number
---@field name string
---@field glyph string|number
---@field color string
---@field shape string

local M = {}

local PALETTE = {
    green = { top = { 52, 65, 53 }, bottom = { 18, 29, 23 }, rim = { 104, 126, 84 } },
    red = { top = { 68, 48, 43 }, bottom = { 31, 18, 18 }, rim = { 151, 81, 62 } },
    blue = { top = { 48, 57, 69 }, bottom = { 17, 23, 34 }, rim = { 91, 115, 145 } },
    purple = { top = { 58, 48, 68 }, bottom = { 26, 19, 35 }, rim = { 123, 96, 145 } },
    yellow = { top = { 67, 59, 39 }, bottom = { 30, 25, 16 }, rim = { 147, 120, 68 } },
    neutral = { top = { 55, 53, 47 }, bottom = { 24, 23, 21 }, rim = { 120, 111, 92 } },
}

local function polygon(vg, points)
    nvgBeginPath(vg)
    for i, point in ipairs(points) do
        if i == 1 then nvgMoveTo(vg, point[1], point[2])
        else nvgLineTo(vg, point[1], point[2]) end
    end
    nvgClosePath(vg)
end

local function platePath(vg, shape)
    nvgBeginPath(vg)
    if shape == "diamond" then
        nvgMoveTo(vg, 47, 5)
        nvgQuadTo(vg, 50, 2, 53, 5)
        nvgLineTo(vg, 95, 47)
        nvgQuadTo(vg, 98, 50, 95, 53)
        nvgLineTo(vg, 53, 95)
        nvgQuadTo(vg, 50, 98, 47, 95)
        nvgLineTo(vg, 5, 53)
        nvgQuadTo(vg, 2, 50, 5, 47)
        nvgClosePath(vg)
    elseif shape == "hex" then
        for i = 0, 5 do
            local angle = -math.pi * 0.5 + i * math.pi / 3
            local x = 50 + math.cos(angle) * 46
            local y = 50 + math.sin(angle) * 46
            if i == 0 then nvgMoveTo(vg, x, y) else nvgLineTo(vg, x, y) end
        end
        nvgClosePath(vg)
    else
        nvgCircle(vg, 50, 50, 46)
    end
end

local function makeColor(opacity)
    return function(r, g, b, a)
        return nvgRGBA(r, g, b, math.floor(a * opacity + 0.5))
    end
end

local function paintPlate(vg, palette, shape, opacity)
    local rgba = makeColor(opacity)
    platePath(vg, shape)
    nvgFillColor(vg, rgba(9, 8, 7, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, rgba(5, 5, 5, 255))
    nvgStrokeWidth(vg, 4)
    nvgStroke(vg)

    nvgSave(vg)
    nvgTranslate(vg, 50, 50)
    nvgScale(vg, 0.92, 0.92)
    nvgTranslate(vg, -50, -50)
    platePath(vg, shape)
    local metalTop = rgba(104, 98, 83, 255)
    local metalBottom = rgba(27, 26, 23, 255)
    ---@cast metalTop NVGcolor
    ---@cast metalBottom NVGcolor
    nvgFillPaint(vg, nvgLinearGradient(vg, 22, 10, 78, 90, metalTop, metalBottom))
    nvgFill(vg)
    nvgStrokeColor(vg, rgba(20, 19, 16, 255))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)

    nvgTranslate(vg, 50, 50)
    nvgScale(vg, 0.93, 0.93)
    nvgTranslate(vg, -50, -50)
    platePath(vg, shape)
    nvgFillColor(vg, rgba(14, 13, 12, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, rgba(palette.rim[1], palette.rim[2], palette.rim[3], 175))
    nvgStrokeWidth(vg, 1.1)
    nvgStroke(vg)

    nvgTranslate(vg, 50, 50)
    nvgScale(vg, 0.96, 0.96)
    nvgTranslate(vg, -50, -50)
    platePath(vg, shape)
    local top = rgba(palette.top[1], palette.top[2], palette.top[3], 255)
    local bottom = rgba(palette.bottom[1], palette.bottom[2], palette.bottom[3], 255)
    ---@cast top NVGcolor
    ---@cast bottom NVGcolor
    nvgFillPaint(vg, nvgLinearGradient(vg, 24, 12, 66, 88, top, bottom))
    nvgFill(vg)
    nvgStrokeColor(vg, rgba(11, 10, 9, 255))
    nvgStrokeWidth(vg, 1.1)
    nvgStroke(vg)
    nvgRestore(vg)
end

local function solid(vg)
    nvgFill(vg)
    nvgStroke(vg)
end

local function wing(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 20, 62)
    nvgBezierTo(vg, 18, 48, 31, 40, 49, 34)
    nvgBezierTo(vg, 64, 29, 77, 24, 84, 19)
    nvgBezierTo(vg, 86, 33, 77, 43, 64, 47)
    nvgBezierTo(vg, 72, 46, 77, 44, 80, 42)
    nvgBezierTo(vg, 80, 53, 70, 63, 59, 66)
    nvgBezierTo(vg, 64, 65, 68, 63, 71, 60)
    nvgBezierTo(vg, 68, 72, 57, 81, 44, 82)
    nvgBezierTo(vg, 28, 86, 19, 79, 20, 62)
    nvgClosePath(vg)
    solid(vg)
end

local function fist(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 29, 43)
    nvgLineTo(vg, 48, 43)
    nvgLineTo(vg, 43, 54)
    nvgLineTo(vg, 33, 56)
    nvgLineTo(vg, 34, 61)
    nvgLineTo(vg, 47, 58)
    nvgLineTo(vg, 56, 43)
    nvgLineTo(vg, 75, 43)
    nvgQuadTo(vg, 78, 43, 78, 47)
    nvgLineTo(vg, 78, 65)
    nvgQuadTo(vg, 77, 70, 73, 73)
    nvgLineTo(vg, 54, 83)
    nvgQuadTo(vg, 51, 85, 47, 82)
    nvgLineTo(vg, 28, 71)
    nvgQuadTo(vg, 24, 68, 25, 63)
    nvgLineTo(vg, 26, 46)
    nvgQuadTo(vg, 26, 43, 29, 43)
    nvgClosePath(vg)
    solid(vg)
    for i = 0, 3 do
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 27 + i * 13, 24, 11, 17, 3)
        solid(vg)
    end
end

local function staff(vg)
    polygon(vg, { { 21, 73 }, { 53, 41 }, { 60, 48 }, { 28, 80 } })
    solid(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, 24, 77, 5)
    solid(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 51, 35)
    nvgQuadTo(vg, 44, 39, 46, 46)
    nvgQuadTo(vg, 49, 55, 58, 57)
    nvgQuadTo(vg, 63, 57, 66, 52)
    nvgLineTo(vg, 51, 35)
    nvgClosePath(vg)
    solid(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, 66, 31, 14)
    solid(vg)
end

local function roundShield(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, 50, 51, 25)
    nvgStrokeWidth(vg, 6)
    nvgStroke(vg)
    for _, x in ipairs({ 40, 50, 60 }) do
        local halfH = x == 50 and 19 or 16
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x - 2.7, 51 - halfH, 5.4, halfH * 2, 1.4)
        nvgFill(vg)
    end
end

local function thunderSword(vg)
    polygon(vg, { { 50, 18 }, { 57, 28 }, { 55, 66 }, { 65, 69 }, { 62, 74 }, { 55, 73 }, { 54, 83 }, { 57, 85 }, { 50, 88 }, { 43, 85 }, { 46, 83 }, { 45, 73 }, { 38, 74 }, { 35, 69 }, { 45, 66 }, { 43, 28 } })
    solid(vg)
    for _, side in ipairs({ -1, 1 }) do
        nvgSave(vg)
        nvgTranslate(vg, 50, 0)
        nvgScale(vg, side, 1)
        polygon(vg, { { -18, 22 }, { -27, 31 }, { -32, 43 }, { -32, 58 }, { -25, 74 }, { -16, 82 }, { -21, 68 }, { -13, 73 }, { -20, 60 }, { -11, 64 }, { -18, 53 }, { -9, 55 }, { -17, 46 }, { -11, 45 }, { -18, 37 }, { -14, 37 }, { -18, 30 }, { -13, 32 } })
        solid(vg)
        nvgRestore(vg)
    end
end

local function swiftSword(vg)
    polygon(vg, { { 76, 24 }, { 80, 24 }, { 80, 42 }, { 47, 68 }, { 40, 60 }, { 66, 26 } })
    solid(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 35, 57)
    nvgQuadTo(vg, 26, 59, 31, 65)
    nvgLineTo(vg, 46, 80)
    nvgQuadTo(vg, 52, 84, 54, 76)
    nvgClosePath(vg)
    solid(vg)
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 28, 78)
    nvgLineTo(vg, 40, 66)
    nvgStrokeWidth(vg, 9)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)
    nvgRestore(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 61, 28)
    nvgBezierTo(vg, 45, 23, 28, 27, 20, 35)
    nvgBezierTo(vg, 31, 34, 39, 40, 45, 45)
    nvgLineTo(vg, 61, 28)
    nvgClosePath(vg)
    solid(vg)
end

local PAINTERS = { wing = wing, fist = fist, staff = staff, roundShield = roundShield, thunderSword = thunderSword, swiftSword = swiftSword }

local function contourPainter(id)
    local paths = assert(Contours[id], "缺少矢量图标 " .. tostring(id))
    return function(vg)
        nvgBeginPath(vg)
        for _, contour in ipairs(paths) do
            local points = contour.points
            nvgMoveTo(vg, points[1], points[2])
            for i = 3, #points, 2 do
                nvgLineTo(vg, points[i], points[i + 1])
            end
            nvgClosePath(vg)
            nvgPathWinding(vg, contour.hole and NVG_HOLE or NVG_SOLID)
        end
        nvgFill(vg)
        nvgStroke(vg)
    end
end

for id in pairs(Contours) do PAINTERS[id] = contourPainter(id) end
for id, painter in pairs(ExtraPainters) do PAINTERS[id] = painter end

local BASE_GLYPHS = { [1] = "wing", [2] = "fist", [5] = "swiftSword", [33] = "staff", [104] = "roundShield", [114] = "thunderSword" }
local COLORS = { ["绿"] = "green", ["红"] = "red", ["蓝"] = "blue", ["紫"] = "purple", ["黄"] = "yellow", ["无"] = "neutral" }
local SHAPES = { small = "circle", medium = "diamond", large = "hex" }

---@param node table
---@return TalentGlyphSample
function M.getSample(node)
    local iconId = tonumber(node.icon:match("UI_icon_TF_(%d+)%.png"))
    local glyph = BASE_GLYPHS[iconId] or iconId
    assert(PAINTERS[glyph], "未实现图标 " .. tostring(iconId))
    return { id = iconId, name = node.name, glyph = glyph, color = COLORS[node.color], shape = SHAPES[node.st] }
end

---@param vg any
---@param sample TalentGlyphSample
---@param cx number
---@param cy number
---@param size number
---@param alpha number?
function M.draw(vg, sample, cx, cy, size, alpha)
    local palette = assert(PALETTE[sample.color], "未知图标配色")
    local painter = assert(PAINTERS[sample.glyph], "未知图标符号")
    local opacity = alpha or 1
    if opacity <= 0 then return end
    local rgba = makeColor(opacity)
    nvgSave(vg)
    nvgTranslate(vg, cx - size * 0.5, cy - size * 0.5)
    nvgScale(vg, size / 100, size / 100)
    paintPlate(vg, palette, sample.shape, opacity)

    nvgSave(vg)
    nvgTranslate(vg, 50, 50)
    local glyphScale = sample.shape == "diamond" and 0.72 or (sample.shape == "hex" and 0.80 or 0.85)
    nvgScale(vg, glyphScale, glyphScale)
    nvgTranslate(vg, -50, -50)
    nvgSave(vg)
    nvgTranslate(vg, 0.7, 1.5)
    nvgFillColor(vg, rgba(6, 6, 5, 245))
    nvgStrokeColor(vg, rgba(6, 6, 5, 245))
    nvgStrokeWidth(vg, 3.6)
    nvgLineJoin(vg, NVG_ROUND)
    painter(vg)
    nvgRestore(vg)

    local boneTop = rgba(232, 222, 195, 255)
    local boneBottom = rgba(154, 139, 111, 255)
    ---@cast boneTop NVGcolor
    ---@cast boneBottom NVGcolor
    local bonePaint = nvgLinearGradient(vg, 27, 23, 63, 82, boneTop, boneBottom)
    nvgFillPaint(vg, bonePaint)
    nvgStrokePaint(vg, bonePaint)
    nvgStrokeWidth(vg, 0.65)
    painter(vg)

    nvgFillColor(vg, rgba(27, 24, 19, 255))
    nvgStrokeColor(vg, rgba(27, 24, 19, 255))
    if sample.glyph == "wing" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, 32, 66)
        nvgBezierTo(vg, 27, 55, 42, 46, 51, 52)
        nvgBezierTo(vg, 57, 57, 57, 64, 53, 69)
        nvgStrokeWidth(vg, 4.2)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)
    elseif sample.glyph == "staff" then
        nvgBeginPath(vg)
        nvgCircle(vg, 63, 27, 3.2)
        nvgFill(vg)
    elseif sample.glyph == "roundShield" then
        for i = 0, 7 do
            local angle = i * math.pi * 0.25
            nvgBeginPath(vg)
            nvgCircle(vg, 50 + math.cos(angle) * 25, 51 + math.sin(angle) * 25, 1.4)
            nvgFill(vg)
        end
    elseif sample.glyph == "thunderSword" then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 48.5, 30, 3, 32, 1)
        nvgFill(vg)
    elseif sample.glyph == 127 then
        for _, p in ipairs({ { 37, 37 }, { 63, 37 }, { 50, 50 }, { 37, 63 }, { 63, 63 } }) do
            nvgBeginPath(vg)
            nvgCircle(vg, p[1], p[2], 3.8)
            nvgFill(vg)
        end
    elseif sample.glyph == 60 then
        polygon(vg, { { 50, 33 }, { 62, 42 }, { 61, 57 }, { 50, 65 }, { 39, 57 }, { 38, 42 } })
        nvgStrokeWidth(vg, 2.4)
        nvgStroke(vg)
    elseif sample.glyph == 116 or sample.glyph == 117 then
        nvgBeginPath(vg)
        nvgMoveTo(vg, 50, 28)
        nvgLineTo(vg, 50, 67)
        nvgMoveTo(vg, 34, 42)
        nvgLineTo(vg, 66, 42)
        nvgStrokeWidth(vg, 3.2)
        nvgStroke(vg)
    elseif sample.glyph == 133 then
        nvgBeginPath(vg)
        nvgMoveTo(vg, 42, 71)
        nvgLineTo(vg, 58, 71)
        nvgStrokeWidth(vg, 2.3)
        nvgStroke(vg)
    elseif sample.glyph == 134 or sample.glyph == 135 then
        nvgBeginPath(vg)
        nvgMoveTo(vg, 50, 28)
        nvgLineTo(vg, 50, 60)
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
    nvgRestore(vg)
    nvgRestore(vg)
end

return M
