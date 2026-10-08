-- 角色属性页与配装页共同绘图：只接收已有句柄/数据，沿用外层 frame 与字体。
local DrawUtil = require("core.DrawUtil")
local AD = require("systems.AttributeDef")
local M = {}

M.STYLE = {
    boxW = 440, rowH = 78, rowStep = 88, radius = 20,
    deltaOffset = 37, deltaFontSize = 28,
    boxCX = 310, decoX = 137, decoSize = 20, nameX = 167, valueX = 510,
    fontSize = 35, minFontSize = 22, nameValueGap = 15,
    nameColor = { 0xE8, 0xDC, 0xC8, 255 }, valueColor = { 255, 255, 255, 255 },
    rowColor = { 0, 0, 0, 26 }, stroke = 4,
    green = { 115, 218, 135, 255 }, red = { 235, 110, 100, 255 },
}
-- 两页共用78高/88行距，属性页保留独立大字号与列宽，配装保留差值区。
---@type table<string, any>
M.ATTRIBUTE_STYLE = {}
for key, value in pairs(M.STYLE) do M.ATTRIBUTE_STYLE[key] = value end
M.ATTRIBUTE_STYLE.rowH, M.ATTRIBUTE_STYLE.rowStep = 78, 88
M.ATTRIBUTE_STYLE.fontSize = 40
M.ATTRIBUTE_STYLE.boxW, M.ATTRIBUTE_STYLE.boxCX = 460, 300
M.ATTRIBUTE_STYLE.decoX, M.ATTRIBUTE_STYLE.nameX, M.ATTRIBUTE_STYLE.valueX = 120, 150, 520
M.ATTRIBUTE_LAYOUT = { x = 40, y = 1070, w = 500, h = 874, firstY = 1109 }
M.RADAR = { r = 175, labelR = 230 }
M.ATTRIBUTE_RADAR = { cx = 800, cy = 1507, r = 195, labelR = 238 }
M.BACKGROUND = { w = 1080, h = 1579, originalTop = 821 }
M.DIVIDER = { cx = 540, w = 1010, h = 37 }
local images = { background = -1, divider = -1, deco = -1 }

-- Draw.initImages 一次性注入；测试未初始化贴图时安全跳过。
function M.setSharedImages(shared)
    images = shared or { background = -1, divider = -1, deco = -1 }
end

function M.drawImage(vg, image, cx, cy, w, h)
    if not image or image < 0 then return end
    local x, y = cx - w * 0.5, cy - h * 0.5
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    local paint = nvgImagePattern(vg, x, y, w, h, 0, image, 1.0)
    ---@cast paint NVGpaint
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

function M.drawBackground(vg, top)
    M.drawImage(vg, images.background, 540, top + M.BACKGROUND.h * 0.5,
        M.BACKGROUND.w, M.BACKGROUND.h)
end

function M.drawDivider(vg, y)
    M.drawImage(vg, images.divider, M.DIVIDER.cx, y, M.DIVIDER.w, M.DIVIDER.h)
end

function M.drawTitle(vg, x, y, title)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0x23, 0x23, 0x23, 255))
    for i = 0, 15 do
        local angle = i * math.pi * 2 / 16
        nvgText(vg, x + math.cos(angle) * 4, y + math.sin(angle) * 4, title, nil)
    end
    nvgFillColor(vg, nvgRGBA(0xF7, 0xFE, 0x77, 255))
    nvgText(vg, x, y, title, nil)
end

-- 两页六围/派生数值共用精度，只格式化显示，不取整或改写实际属性。
function M.formatNumber(value, decimals)
    local number = tonumber(value) or 0
    if math.type(number) == "integer" then return tostring(number) end
    local amount = string.format("%." .. tostring(decimals or 6) .. "f", number)
    amount = amount:gsub("0+$", ""):gsub("%.$", "")
    return amount == "-0" and "0" or amount
end

function M.formatInterval(value)
    return M.formatNumber(value) .. "s"
end

local function formattedValue(row)
    if row.value ~= nil then return tostring(row.value) end
    local value = row.currentValue
    if type(value) == "number" then
        if row.key == "atkInterval" then return M.formatInterval(value) end
        if AD.META[row.key] and AD.formatAttrDisplayValue then
            return AD.formatAttrDisplayValue(row.key, value)
        end
        return string.format("%.2f", value):gsub("%.?0+$", "")
    end
    return value ~= nil and tostring(value) or "—"
end

--- 显示排序与颜色共用增益判断；攻击间隔下降等改善项按绿色优先。
function M.changePriority(row)
    local delta = tonumber(row.delta) or 0
    if math.abs(delta) < 0.000001 then return 3 end
    local beneficial = row.beneficial
    if beneficial == nil then beneficial = delta > 0 end
    return beneficial and 1 or 2
end

local function deltaLabel(row)
    local priority = M.changePriority(row)
    if priority == 3 then return "", M.STYLE.green end
    local delta = tonumber(row.delta) or 0
    local label = row.deltaText
    if not label or label == "" then
        label = (delta > 0 and "+" or "") .. (math.abs(delta) >= 100
            and string.format("%.0f", delta) or string.format("%.1f", delta))
    end
    return tostring(label), priority == 1 and M.STYLE.green or M.STYLE.red
end

-- 在最终变换/对齐下复测墨迹边界；字号缩放不能假设字体栅格宽度严格线性。
function M.fitText(vg, text, fontSize, align, x, y, left, right, padding)
    local bounds = {}
    local size, advance = fontSize, 0
    local inset = padding or 0
    nvgFontFace(vg, "sans")
    nvgTextLetterSpacing(vg, 0)
    nvgTextAlign(vg, align)
    for iteration = 1, 24 do
        nvgFontSize(vg, size)
        advance = nvgTextBounds(vg, x, y, text, bounds)
        if (bounds[1] >= left + inset and bounds[3] <= right - inset) or iteration == 24 then break end
        local actual = math.max(x - bounds[1], bounds[3] - x)
        local available = math.max(1, math.min(x - left - inset, right - inset - x))
        if align == NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE then
            actual, available = math.max(1, bounds[3] - x), math.max(1, right - inset - x)
        elseif align == NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE then
            actual, available = math.max(1, x - bounds[1]), math.max(1, x - left - inset)
        end
        size = size * math.min(0.9, available / math.max(1, actual) * 0.97)
    end
    return size, advance, bounds
end

--- 共用绘制/测量/命中逻辑，属性页可传独立大字号风格；配装差值不改原基线。
function M.drawAttributeRows(vg, rows, scroll, layout, options)
    local opts = options or {}
    local style = opts.style or M.STYLE
    local rect = layout or M.ATTRIBUTE_LAYOUT
    local firstY = rect.firstY or (rect.y + style.rowH * 0.5)
    local bottom = firstY + math.max(0, #rows - 1) * style.rowStep + style.rowH * 0.5
    local maxScroll = math.max(0, bottom - rect.y - rect.h)
    local offset = math.max(0, math.min(maxScroll, scroll or 0))
    local hits, changes = {}, {}
    nvgSave(vg)
    nvgIntersectScissor(vg, rect.x, rect.y, rect.w, rect.h)
    for i, row in ipairs(rows) do
        local cy = firstY + (i - 1) * style.rowStep - offset
        local top, rowBottom = cy - style.rowH * 0.5, cy + style.rowH * 0.5
        if rowBottom > rect.y and top < rect.y + rect.h then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, style.boxCX - style.boxW * 0.5, top,
                style.boxW, style.rowH, style.radius)
            local bg = style.rowColor
            nvgFillColor(vg, nvgRGBA(bg[1], bg[2], bg[3], bg[4]))
            nvgFill(vg)
            M.drawImage(vg, images.deco, style.decoX, cy, style.decoSize, style.decoSize)
            local value = formattedValue(row)
            local delta, deltaColor = "", style.green
            if opts.showDelta then delta, deltaColor = deltaLabel(row) end
            local baseline = cy
            local name = tostring(row.name or row.key or "")
            local nameBounds = {}
            nvgFontFace(vg, "sans")
            nvgTextLetterSpacing(vg, 0)
            nvgFontSize(vg, style.minFontSize)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgTextBounds(vg, style.nameX, baseline, name, nameBounds)
            local nameReserve = math.min(math.max(0, nameBounds[3] - style.nameX),
                (style.valueX - style.nameX) * 0.5)
            local valueX = style.valueX - style.stroke - 2
            local valueFont, _, valueBounds = M.fitText(vg, value, style.fontSize,
                NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, valueX, baseline,
                style.nameX + nameReserve + style.nameValueGap, style.valueX + style.stroke, style.stroke)
            M.fitText(vg, name, style.fontSize, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                style.nameX, baseline, rect.x, valueBounds[1] - style.stroke - style.nameValueGap, 0)
            local nc = style.nameColor
            nvgFillColor(vg, nvgRGBA(nc[1], nc[2], nc[3], nc[4]))
            nvgText(vg, style.nameX, baseline, name, nil)
            local vc = style.valueColor
            DrawUtil.drawTextStroke(vg, valueX, baseline, value, valueFont,
                NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, vc[1], vc[2], vc[3], style.stroke)
            if delta ~= "" then
                changes[#changes + 1] = { y = cy - style.deltaOffset, text = delta, color = deltaColor }
            end
            local desc = row.desc
            if type(desc) ~= "string" or desc == "" then desc = AD.getDesc(row.key) end
            hits[#hits + 1] = { x = rect.x, y = math.max(rect.y, top), w = rect.w,
                h = math.min(rect.y + rect.h, rowBottom) - math.max(rect.y, top),
                row = row, index = i, key = row.key, name = name, desc = desc }
        end
    end
    nvgRestore(vg)
    if #changes > 0 then
        -- 独立末层叠加：允许首行差值伸入上方留白，且不被后画的行底覆盖。
        nvgSave(vg)
        nvgIntersectScissor(vg, rect.x, rect.y - 20, rect.w, rect.h + 20)
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        for _, change in ipairs(changes) do
            local deltaFont = style.deltaFontSize or 28
            nvgFontSize(vg, deltaFont)
            local width = nvgTextBounds(vg, 0, 0, change.text) or 0
            local maxWidth = math.min(style.boxW - 20, style.valueX - rect.x - 12)
            if width > maxWidth then nvgFontSize(vg, deltaFont * maxWidth / width) end
            local color = change.color
            nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], color[4]))
            nvgText(vg, style.valueX, change.y, change.text, nil)
        end
        nvgRestore(vg)
    end
    return maxScroll, hits
end

-- 与绘图返回的可见片段共用命中，行间留白没有幽灵说明热区。
function M.rowAt(hits, x, y)
    for _, hit in ipairs(hits or {}) do
        if x >= hit.x and x <= hit.x + hit.w and y >= hit.y and y < hit.y + hit.h then
            return hit.row, hit.index
        end
    end
    return nil
end

return M
