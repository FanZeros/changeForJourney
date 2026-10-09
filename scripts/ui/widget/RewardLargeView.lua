-- 一次性多项奖励的全窗视图；绘制、命中与滚动共用布局，物品只读。
local I18n = require("core.I18n")
local DarkIcon = require("core.DarkIcon")
local ItemView = require("ui.widget.RewardItemView")
local ResourceDefs = require("config.ResourceDefs")
local EquipmentConfig = require("config.EquipmentConfig")
local M = { THRESHOLD = 10, ROW_H = 200 }
local ROW_H, CELL_W, ICON = M.ROW_H, 180, 132

function M.layout(width, height, count)
    local scale = math.min(width / 1600, height / 1000)
    if scale <= 0 then scale = 1 end
    local sw, sh = width / scale, height / scale
    local w, h = math.min(1460, sw - 48), math.min(900, sh - 48)
    local x, y = (sw - w) * 0.5, (sh - h) * 0.5
    local gridW = w - 440
    local cols = math.max(1, math.floor(gridW / CELL_W))
    local rows = math.max(1, math.floor((h - 256) / ROW_H))
    local gridH = rows * ROW_H
    return { scale = scale, sw = sw, sh = sh, x = x, y = y, w = w, h = h,
        gx = x + 36, gy = y + 136, gw = gridW, gh = gridH, cols = cols, rows = rows,
        maxScroll = math.max(0, (math.ceil(count / cols) - rows) * ROW_H),
        dx = x + w - 376, dy = y + 136, dw = 340, dh = h - 240,
        footerY = y + h - 64, closeX = x + w - 40, closeY = y + 40 }
end

function M.cell(layout, index, scroll)
    local row = math.floor((index - 1) / layout.cols)
    local col = (index - 1) % layout.cols
    return layout.gx + (col + 0.5) * layout.gw / layout.cols,
        layout.gy + row * ROW_H + ICON * 0.5 + 8 - scroll
end

local function contains(x, y, rx, ry, w, h)
    return x >= rx and x <= rx + w and y >= ry and y <= ry + h
end

function M.target(l, x, y)
    if contains(x, y, l.dx, l.dy, l.dw, l.dh) then return "detail" end
    if contains(x, y, l.gx, l.gy, l.gw, l.gh) then return "grid" end
    return nil
end

function M.hit(l, x, y, count, scroll, repeatDraw)
    if not contains(x, y, l.x, l.y, l.w, l.h)
        or math.abs(x - l.closeX) < 24 and math.abs(y - l.closeY) < 24 then return "close" end
    if math.abs(y - l.footerY) <= 28 then
        if math.abs(x - (l.gx + 68)) <= 60 then return "prev" end
        if math.abs(x - (l.gx + l.gw - 68)) <= 60 then return "next" end
        if repeatDraw and math.abs(x - (l.dx + l.dw * 0.25)) <= 78 then return "repeat", 1 end
        if repeatDraw and math.abs(x - (l.dx + l.dw * 0.75)) <= 78 then return "repeat", 10 end
    end
    if M.target(l, x, y) == "grid" then
        local row = math.floor((y - l.gy + scroll) / ROW_H)
        local col = math.floor((x - l.gx) / (l.gw / l.cols))
        local index = row * l.cols + col + 1
        if index >= 1 and index <= count then return "item", index end
    end
    return nil
end

-- 已本地化的片段原样描边与绘制，整段在折行/拼接前完成查表。
local function text(vg, x, y, value, font, align)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, font)
    nvgTextAlign(vg, align or (NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE))
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
    for _, offset in ipairs({ { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 },
        { -1.4, -1.4 }, { 1.4, -1.4 }, { -1.4, 1.4 }, { 1.4, 1.4 } }) do
        I18n.displayText(vg, x + offset[1], y + offset[2], value, nil)
    end
    nvgFillColor(vg, nvgRGBA(232, 220, 196, 255))
    I18n.displayText(vg, x, y, value, nil)
end

-- UTF-8 按实际字宽折行；所有行保留，超长详情通过独立滚动访问。
local function lines(vg, value, width, font)
    local result, line = {}, ""
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, font)
    for _, code in utf8.codes(I18n.lookup(tostring(value or ""))) do
        local char = utf8.char(code)
        if char == "\n" then
            result[#result + 1], line = line, ""
        elseif line ~= "" and (I18n.displayBounds(vg, 0, 0, line .. char) or 0) > width then
            result[#result + 1], line = line, char
        else line = line .. char end
    end
    result[#result + 1] = line
    return result
end

local function button(vg, cx, cy, width, label)
    DarkIcon.drawNine(vg, "btn", cx - width * 0.5, cy - 26, width, 52, { accent = "gold" })
    text(vg, cx, cy, label, 24, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
end

local function drawDetail(vg, l, state)
    local item = state.items[state.selectedIndex or 1]
    if not item then return end
    nvgSave(vg)
    nvgIntersectScissor(vg, l.dx, l.dy, l.dw, l.dh)
    nvgTranslate(vg, l.dx, l.dy - (state.detailScroll or 0))
    local y = 18
    for _, line in ipairs(lines(vg, ItemView.name(item), l.dw - 12, 30)) do
        text(vg, 6, y, line, 30); y = y + 36
    end
    for _, line in ipairs(lines(vg, ItemView.quantity(item, true), l.dw - 12, 26)) do
        text(vg, 6, y, line, 26); y = y + 32
    end
    local quality = item.quality and EquipmentConfig.QUALITY[item.quality]
    if quality then text(vg, 6, y, I18n.lookup(quality.name), 24); y = y + 32 end
    if item.destination == "lootbox" then text(vg, 6, y, I18n.lookup("已入遗匣"), 24); y = y + 32 end
    if item.type == "equip" and item.templateId then
        local detail = require("ui.character.equip.EquipmentDetail")
        local dw, dh = detail.readOnlySize(item)
        local fit = math.min(1, (l.dw - 8) / math.max(1, dw))
        nvgSave(vg)
        nvgScale(vg, fit, fit)
        detail.drawReadOnly(vg, item, 4 / fit, y / fit)
        nvgRestore(vg)
        y = y + dh * fit
    else
        local desc = item.desc or ""
        if item.type == "artifact" then desc = require("shared.artifact.ArtifactDefs").getEffectText(item)
        elseif type(ResourceDefs.getRewardDescription) == "function" then desc = ResourceDefs.getRewardDescription(item)
        else
            local def = ResourceDefs.DEFS[item.type]
            desc = desc ~= "" and desc or (def and def.desc) or ""
        end
        for _, line in ipairs(lines(vg, desc, l.dw - 12, 24)) do
            text(vg, 6, y, line, 24); y = y + 32
        end
    end
    state.detailMax = math.max(0, y + 16 - l.dh)
    state.detailScroll = math.min(state.detailScroll or 0, state.detailMax)
    nvgRestore(vg)
end

function M.draw(vg, l, state, drawItem, finished, shown)
    nvgSave(vg)
    nvgScale(vg, l.scale, l.scale)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, l.sw, l.sh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 185))
    nvgFill(vg)
    DarkIcon.drawNine(vg, "panel", l.x, l.y, l.w, l.h, { titleH = 90 })
    text(vg, l.x + 36, l.y + 40, I18n.lookup(state.title) .. " · " .. tostring(#state.items), 36)
    text(vg, l.closeX, l.closeY, "×", 40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local summary = I18n.lookup(state.subtitle ~= "" and state.subtitle or "点击物品查看详情")
    local summaryFont = 24
    nvgFontFace(vg, "sans"); nvgFontSize(vg, summaryFont)
    local width = I18n.displayBounds(vg, 0, 0, summary) or 0
    if width > l.w - 72 then summaryFont = math.max(16, summaryFont * (l.w - 72) / width) end
    text(vg, l.x + 36, l.y + 94, summary, summaryFont)
    nvgSave(vg)
    nvgIntersectScissor(vg, l.gx, l.gy, l.gw, l.gh)
    local first = math.max(1, math.floor(state.scrollY / ROW_H) * l.cols + 1)
    local last = math.min(#state.items, first + (l.rows + 1) * l.cols - 1)
    for index = first, last do
        local cx, cy = M.cell(l, index, state.scrollY)
        if index <= shown and cy - ICON * 0.5 < l.gy + l.gh and cy + ICON * 0.5 > l.gy then
            drawItem(vg, state.items[index], cx, cy, ICON, index)
            if index == state.selectedIndex then
                nvgBeginPath(vg); nvgRoundedRect(vg, cx - ICON * 0.5 - 3, cy - ICON * 0.5 - 3, ICON + 6, ICON + 6, 10)
                nvgStrokeColor(vg, nvgRGBA(247, 222, 135, 255)); nvgStrokeWidth(vg, 3); nvgStroke(vg)
            end
            nvgSave(vg)
            nvgIntersectScissor(vg, cx - l.gw / l.cols * 0.5 + 6, cy + ICON * 0.5, l.gw / l.cols - 12, 58)
            text(vg, cx, cy + ICON * 0.5 + 20, I18n.lookup(ItemView.name(state.items[index])), 22, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            text(vg, cx, cy + ICON * 0.5 + 44, ItemView.quantity(state.items[index]), 22, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgRestore(vg)
        end
    end
    nvgRestore(vg)
    if state.scrollMax > 0 then
        local thumbH = math.max(32, l.gh * l.gh / (l.gh + state.scrollMax))
        nvgBeginPath(vg); nvgRoundedRect(vg, l.gx + l.gw - 4,
            l.gy + state.scrollY / state.scrollMax * (l.gh - thumbH), 4, thumbH, 2)
        nvgFillColor(vg, nvgRGBA(247, 222, 135, 210)); nvgFill(vg)
    end
    if finished then drawDetail(vg, l, state)
    else text(vg, l.dx + 10, l.dy + 36, I18n.lookup("点击跳过"), 28) end
    local pageSize = l.rows * l.cols
    local page = math.ceil(state.scrollY / (l.rows * ROW_H)) + 1
    local pages = math.max(1, math.ceil(#state.items / pageSize))
    button(vg, l.gx + 68, l.footerY, 120, "‹")
    button(vg, l.gx + l.gw - 68, l.footerY, 120, "›")
    text(vg, l.gx + l.gw * 0.5, l.footerY, tostring(page) .. " / " .. tostring(pages), 26,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if finished and state.repeatDraw then
        local RepeatButton = require("ui.widget.RepeatDrawButton")
        for _, count in ipairs({ 1, 10 }) do
            local cost, parts = state.repeatDraw.getCost(count), {}
            for _, part in ipairs(cost.parts or {}) do
                parts[#parts + 1] = { icon = state.getResourceIcon(part.type), type = part.type, amount = part.amount }
            end
            RepeatButton.draw(vg, l.dx + l.dw * (count == 1 and 0.25 or 0.75), l.footerY,
                156, 52, count == 1 and "继续单开" or "继续十连", parts, cost.enough, cost.freeText)
        end
    else text(vg, l.dx + l.dw * 0.5, l.footerY, finished and I18n.lookup("点击空白处关闭") or I18n.lookup("点击跳过"), 24,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE) end
    nvgRestore(vg)
end

return M
