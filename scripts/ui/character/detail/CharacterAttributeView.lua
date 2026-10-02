-- 角色属性页与配装页共同绘图：只接收已有句柄/数据，沿用外层 frame 与字体。
local DrawUtil = require("core.DrawUtil")
local AD = require("systems.AttributeDef")
local M = {}

M.STYLE = {
    boxW = 440, rowH = 60, rowStep = 69, radius = 20,
    boxCX = 310, decoX = 137, decoSize = 20, nameX = 167, valueX = 510,
    fontSize = 35, minFontSize = 22, nameValueGap = 15,
    nameColor = { 0xE8, 0xDC, 0xC8, 255 }, valueColor = { 255, 255, 255, 255 },
    rowColor = { 0, 0, 0, 26 }, stroke = 4,
    green = { 115, 218, 135, 255 }, red = { 235, 110, 100, 255 },
}
M.ATTRIBUTE_LAYOUT = { x = 40, y = 1264, w = 500, h = 552, firstY = 1294 }
M.RADAR = { r = 175, labelR = 230 }
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
    nvgFillPaint(vg, nvgImagePattern(vg, x, y, w, h, 0, image, 1.0))
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

local function formattedValue(row)
    if row.value ~= nil then return tostring(row.value) end
    local value = row.currentValue
    if type(value) == "number" then
        if row.key == "atkInterval" then return string.format("%.2fs", value) end
        if AD.META[row.key] and AD.formatAttrDisplayValue then
            return AD.formatAttrDisplayValue(row.key, value)
        end
        return string.format("%.2f", value):gsub("%.?0+$", "")
    end
    return value ~= nil and tostring(value) or "—"
end

local function deltaLabel(row)
    local delta = tonumber(row.delta) or 0
    if math.abs(delta) < 0.000001 then return "", M.STYLE.green end
    local label = row.deltaText
    if not label or label == "" then
        label = (delta > 0 and "+" or "") .. (math.abs(delta) >= 100
            and string.format("%.0f", delta) or string.format("%.1f", delta))
    end
    local beneficial = row.beneficial
    if beneficial == nil then beneficial = delta > 0 end
    return tostring(label), beneficial and M.STYLE.green or M.STYLE.red
end

--- 共用60px行/69px步长、名称左数值右、底色/装饰/字体/描边和可见行命中。
--- 差值叠加在数值上方；名称、当前值、字号和原有行高均保持不变。
function M.drawAttributeRows(vg, rows, scroll, layout, options)
    local style = M.STYLE
    local rect = layout or M.ATTRIBUTE_LAYOUT
    local opts = options or {}
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
            local valueFont = style.fontSize
            local name = tostring(row.name or row.key or "")
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, style.fontSize)
            local nameW = nvgTextBounds(vg, 0, 0, name)
            nvgFontSize(vg, valueFont)
            local valW = nvgTextBounds(vg, 0, 0, value)
            nvgFontSize(vg, style.fontSize)
            local maxNameW = style.valueX - style.nameX - valW - style.nameValueGap
            if maxNameW > 0 and nameW > maxNameW then
                nvgFontSize(vg, math.max(style.minFontSize,
                    math.floor(style.fontSize * maxNameW / nameW)))
            end
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local nc = style.nameColor
            nvgFillColor(vg, nvgRGBA(nc[1], nc[2], nc[3], nc[4]))
            nvgText(vg, style.nameX, baseline, name, nil)
            local vc = style.valueColor
            DrawUtil.drawTextStroke(vg, style.valueX, baseline, value, valueFont,
                NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, vc[1], vc[2], vc[3], style.stroke)
            if delta ~= "" then
                changes[#changes + 1] = { y = cy - 35, text = delta, color = deltaColor }
            end
            ---@type table
            local meta = AD.META[row.key]
            hits[#hits + 1] = { x = rect.x, y = math.max(rect.y, top), w = rect.w,
                h = math.min(rect.y + rect.h, rowBottom) - math.max(rect.y, top),
                row = row, index = i, key = row.key, name = name,
                desc = row.desc or (meta and meta.desc) or "该属性为当前角色的最终面板数值。" }
        end
    end
    nvgRestore(vg)
    if #changes > 0 then
        -- 独立末层叠加：允许首行差值伸入上方留白，且不被后画的行底覆盖。
        nvgSave(vg)
        nvgIntersectScissor(vg, rect.x, rect.y - 20, rect.w, rect.h + 20)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        for _, change in ipairs(changes) do
            local color = change.color
            nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], color[4]))
            nvgText(vg, style.valueX, change.y, change.text, nil)
        end
        nvgRestore(vg)
    end
    return maxScroll, hits
end

-- 与绘图返回的可见片段共用命中，9px行距没有幽灵说明热区。
function M.rowAt(hits, x, y)
    for _, hit in ipairs(hits or {}) do
        if x >= hit.x and x <= hit.x + hit.w and y >= hit.y and y < hit.y + hit.h then
            return hit.row, hit.index
        end
    end
    return nil
end

return M
