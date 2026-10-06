-- 洗练材料悬停说明：复用材料列表几何，浮窗在页面内容裁剪恢复后绘制。
local DrawUtil = require("core.DrawUtil")
local ResourceDefs = require("config.ResourceDefs")

local M = {}
local hoverIndex, hoverSince = 0, 0
local DELAY, FADE, WIDTH, PAD = 0.3, 0.15, 580, 24
local FONT, LINE_H, TITLE_H = 30, 42, 48

function M.bounds(layout, count)
    local height = count * 80 + 16
    local bottom = layout.EXTRA_ICON_CY - layout.EXTRA_ICON_SIZE * 0.5 - 8
    return { x = layout.EXTRA_ICON_CX - 160, y = bottom - height,
        w = 320, h = height, bottom = bottom, itemH = 80 }
end

function M.rowAt(x, y, bounds, count)
    if x < bounds.x or x > bounds.x + bounds.w
        or y < bounds.y + 8 or y >= bounds.bottom - 8 then return 0 end
    local index = math.floor((y - bounds.y - 8) / bounds.itemH) + 1
    return index >= 1 and index <= count and index or 0
end

function M.clear()
    hoverIndex, hoverSince = 0, 0
end

function M.hover(x, y, layout, options, open)
    local index = open and M.rowAt(x, y, M.bounds(layout, #options), #options) or 0
    if index ~= hoverIndex then
        hoverIndex, hoverSince = index, time.elapsedTime
        if index > 0 then print("[BlacksmithRefine] 材料说明: " .. options[index].name) end
    end
end

function M.isHovered(index)
    return hoverIndex == index
end

local function wrap(vg, text)
    local lines, line = {}, ""
    for _, code in utf8.codes(text) do
        local character = utf8.char(code)
        if character == "\n" then
            lines[#lines + 1], line = line, ""
        elseif line ~= "" and nvgTextBounds(vg, 0, 0, line .. character) > WIDTH - PAD * 2 then
            lines[#lines + 1], line = line, character
        else
            line = line .. character
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

function M.draw(vg, layout, options, open)
    if not open then M.clear(); return end
    local option = options[hoverIndex]
    local elapsed = time.elapsedTime - hoverSince
    if not option or elapsed < DELAY then return end
    local def = ResourceDefs.DEFS[option.type]
    if not def or not def.desc then return end
    nvgSave(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, FONT)
    local lines = wrap(vg, def.desc)
    local height = PAD * 2 + TITLE_H + #lines * LINE_H
    local bounds = M.bounds(layout, #options)
    local left = math.max(20, math.min(1080 - WIDTH - 20, layout.EXTRA_ICON_CX - WIDTH * 0.5))
    -- 默认在整个列表上方，不盖住其余材料行；仍保留宿主面板的裁剪。
    local top = math.max(20, math.min(2400 - height - 20, bounds.y - height - 16))
    nvgGlobalAlpha(vg, math.min(1, (elapsed - DELAY) / FADE))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, left, top, WIDTH, height, 16)
    nvgFillColor(vg, nvgRGBA(30, 25, 20, 245))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(120, 100, 80, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    DrawUtil.drawTextStroke(vg, left + PAD, top + PAD + TITLE_H * 0.5,
        option.name .. " · 使用说明", 34, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        240, 230, 210, 2)
    nvgFontSize(vg, FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(225, 218, 200, 255))
    for index, text in ipairs(lines) do
        nvgText(vg, left + PAD, top + PAD + TITLE_H + (index - 0.5) * LINE_H, text, nil)
    end
    nvgRestore(vg)
end

return M
