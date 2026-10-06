-- 结果页继续抽取按钮：消耗逐项量宽、分别绘图，混合支付不丢货币图标。
local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")

local M = {}

function M.hit(x, y, cx, cy, width, height)
    return math.abs(x - cx) <= width * 0.5 and math.abs(y - cy) <= height * 0.5
end

-- parts = { { icon = NanoVG句柄, type = 资源类型, amount = 数量 } }。
-- 调用方提供真实报价；这里只绘制，不扣费、不发送动作。
function M.draw(vg, cx, cy, width, height, label, parts, enough, freeText)
    parts = parts or {}
    local mixed = #parts > 1
    local labelFont, costFont = mixed and 30 or 36, mixed and 28 or 32
    local iconSize, partGap, labelGap = mixed and 34 or 40, 10, 12
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, labelFont)
    local labelW = nvgTextBounds(vg, 0, 0, label) or 0
    local items, costW = {}, 0
    nvgFontSize(vg, costFont)
    if freeText then
        costW = nvgTextBounds(vg, 0, 0, freeText) or 0
    else
        for index, part in ipairs(parts) do
            local caption = tostring(part.amount or 0)
            local textW = nvgTextBounds(vg, 0, 0, caption) or 0
            items[index] = { part = part, text = caption, width = textW }
            costW = costW + iconSize + 6 + textW + (index > 1 and partGap or 0)
        end
    end
    local gap = (costW > 0) and labelGap or 0
    local contentW = labelW + gap + costW
    local fit = math.min(1, (width - 28) / math.max(1, contentW))
    DarkIcon.drawNine(vg, "btn", cx - width * 0.5, cy - height * 0.5, width, height,
        { accent = "gold" })
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, fit, fit)
    local x = -contentW * 0.5
    DrawUtil.drawTextStroke(vg, x, 0, label, labelFont,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 255, 236, 190, 2)
    x = x + labelW + gap
    local r, g, b = 255, 255, 255
    if enough == false then r, g, b = 255, 90, 90 end
    if freeText then
        DrawUtil.drawTextStroke(vg, x, 0, freeText, costFont,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, r, g, b, 2)
    else
        for index, item in ipairs(items) do
            if index > 1 then x = x + partGap end
            local icon = item.part.icon
            if icon and icon >= 0 then
                DrawUtil.drawImageCentered(vg, icon, x + iconSize * 0.5, 0, iconSize, iconSize, 1)
            elseif item.part.type == "diamond" then
                DarkIcon.draw(vg, "gem", x + iconSize * 0.5, 0, iconSize, 1)
            end
            DrawUtil.drawTextStroke(vg, x + iconSize + 6, 0, item.text, costFont,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, r, g, b, 2)
            x = x + iconSize + 6 + item.width
        end
    end
    nvgRestore(vg)
end

return M
