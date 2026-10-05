-- ============================================================================
-- CharacterEquipStats - 配装属性/套装展示与共享六围雷达（纯 NanoVG）
-- 只消费 EquipmentPreview 的结果；不计算穿装、职业校验或属性派生。
-- ============================================================================

local AD = require("systems.AttributeDef")
local EquipmentSetConfig = require("config.EquipmentSetConfig")
local DrawUtil = require("core.DrawUtil")
local DetailAttrs = require("ui.character.detail.CharacterDetailAttrs")
local AttributeView = require("ui.character.detail.CharacterAttributeView")
local EquipmentSetIcon = require("ui.widget.EquipmentSetIcon")

local M = {}
local drawTextStroke = DrawUtil.drawTextStroke

-- 设计坐标继续由角色详情外层转换，子模块不另起 NanoVG frame/字体/UI 树。
M.LAYOUT = {
    panel = { x = 24, y = 890, w = 1032, h = 1334 },
    titleY = 930,
    title = { x = 390, y = 894, w = 300, h = 68 },
    attrs = { x = AttributeView.ATTRIBUTE_LAYOUT.x, y = 1050,
        w = AttributeView.ATTRIBUTE_LAYOUT.w, h = 718 },
    radar = { x = 550, y = 1050, w = 530, h = 718, cx = 800, cy = 1403,
        r = AttributeView.RADAR.r, labelR = AttributeView.RADAR.labelR,
        deltaFontSize = 32, deltaOffset = 58 },
    sets = { x = 54, y = 1866, w = 972, h = 348 },
    attrTitleY = 1010,
    setTitleY = 1818,
    rowH = AttributeView.STYLE.rowH,
    rowStep = AttributeView.STYLE.rowStep,
}

local COLOR = {
    gold = { 196, 160, 90, 240 },
    text = { 232, 220, 200, 255 },
    muted = { 139, 132, 119, 210 },
    green = { 115, 218, 135, 255 },
    red = { 235, 110, 100, 255 },
    current = { 193, 187, 175, 220 },
}

local function ink(vg, color)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
end

local function text(vg, x, y, str, size, color, align)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, size)
    nvgTextAlign(vg, align or (NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE))
    ink(vg, color or COLOR.text)
    nvgText(vg, x, y, tostring(str or ""), nil)
end

local function plate(vg, rect)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, rect.x, rect.y, rect.w, rect.h, AttributeView.STYLE.radius)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
    nvgFill(vg)
end

function M.contains(rect, x, y)
    return x ~= nil and y ~= nil and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

--- UTF-8 逐字换行；保留显式换行，不裁掉任何套装描述。
function M.wrapText(vg, value, fontSize, maxW)
    local source = tostring(value or "")
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    local lines, line = {}, ""
    for _, codepoint in utf8.codes(source) do
        local char = utf8.char(codepoint)
        if char == "\n" then
            lines[#lines + 1] = line
            line = ""
        else
            local trial = line .. char
            if line ~= "" and nvgTextBounds(vg, 0, 0, trial) > maxW then
                lines[#lines + 1] = line
                line = char
            else
                line = trial
            end
        end
    end
    if line ~= "" or #lines == 0 then lines[#lines + 1] = line end
    return lines
end

local function scrollbar(vg, rect, scroll, maxScroll)
    if maxScroll <= 0 then return end
    local thumbH = math.max(32, rect.h * rect.h / (rect.h + maxScroll))
    local thumbY = rect.y + (rect.h - thumbH) * scroll / maxScroll
    nvgBeginPath(vg)
    nvgRoundedRect(vg, rect.x + rect.w - 5, rect.y, 3, rect.h, 1.5)
    nvgFillColor(vg, nvgRGBA(196, 160, 90, 32))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, rect.x + rect.w - 5, thumbY, 3, thumbH, 1.5)
    nvgFillColor(vg, nvgRGBA(196, 160, 90, 160))
    nvgFill(vg)
end

--- 属性页同一绘制API，配装只增加独立delta和滚动条。
M.drawAttributeRows = AttributeView.drawAttributeRows
M.ATTRIBUTE_STYLE = AttributeView.STYLE
M.rowAt = AttributeView.rowAt

--- 只复制显示数组：绿色改善、红色下降、无变化；同组保留原属性顺序。
function M.sortComparisonRows(rows)
    local groups, sorted = { {}, {}, {} }, {}
    for _, row in ipairs(rows or {}) do
        local group = groups[AttributeView.changePriority(row)]
        group[#group + 1] = row
    end
    for _, group in ipairs(groups) do
        for _, row in ipairs(group) do sorted[#sorted + 1] = row end
    end
    return sorted
end

function M.drawRows(vg, rows, scroll)
    local rect = M.LAYOUT.attrs
    local maxScroll, hits = M.drawAttributeRows(vg, rows, scroll, rect, { showDelta = true })
    scrollbar(vg, rect, math.max(0, math.min(maxScroll, scroll or 0)), maxScroll)
    return maxScroll, hits
end

--- 当前/试穿摘要并集。只展示状态，不重新推导套装互斥或计数。
function M.unionSets(current, preview)
    local byId, result = {}, {}
    for _, row in ipairs(current or {}) do
        local id = row.setId
        if id then
            local entry = { setId = id, name = row.name, current = row, preview = nil }
            byId[id] = entry
            result[#result + 1] = entry
        end
    end
    for _, row in ipairs(preview or {}) do
        local id = row.setId
        if id then
            local entry = byId[id]
            if not entry then
                entry = { setId = id, name = row.name, current = nil, preview = nil }
                byId[id] = entry
                result[#result + 1] = entry
            end
            entry.preview = row
        end
    end
    table.sort(result, function(a, b)
        local ac = math.max(a.current and a.current.count or 0, a.preview and a.preview.count or 0)
        local bc = math.max(b.current and b.current.count or 0, b.preview and b.preview.count or 0)
        if ac ~= bc then return ac > bc end
        return tostring(a.setId) < tostring(b.setId)
    end)
    return result
end

local PIECES = {
    { n = 2, active = "twoActive", desc = "desc2" },
    { n = 4, active = "fourActive", desc = "desc4" },
    { n = 6, active = "sixActive", desc = "desc6" },
}

function M.drawSets(vg, sets, scroll, hasPreview)
    local rect = M.LAYOUT.sets
    plate(vg, rect)
    local blocks, totalH = {}, 0
    for _, set in ipairs(sets) do
        local def = EquipmentSetConfig.get(set.setId)
        local block = { set = set, lines = {}, top = totalH, h = 58 }
        for _, piece in ipairs(PIECES) do
            local wasActive = set.current and set.current[piece.active] == true
            local active = hasPreview and set.preview and set.preview[piece.active] == true
                or (not hasPreview and wasActive)
            local color = active and COLOR.green or (wasActive and hasPreview and COLOR.red or COLOR.muted)
            local status = active and "激活  " or (wasActive and hasPreview and "失效  " or "")
            local description = def and def[piece.desc] or "暂无效果说明"
            local lines = M.wrapText(vg, tostring(piece.n) .. "件 · " .. status .. description,
                27, rect.w - 60)
            block.lines[#block.lines + 1] = { text = lines, color = color }
            block.h = block.h + #lines * 36 + 12
        end
        block.h = block.h + 18
        blocks[#blocks + 1] = block
        totalH = totalH + block.h
    end
    local maxScroll = math.max(0, totalH - rect.h)
    local offset = math.max(0, math.min(maxScroll, scroll or 0))
    nvgSave(vg)
    nvgIntersectScissor(vg, rect.x + 4, rect.y, rect.w - 12, rect.h)
    if #sets == 0 then
        text(vg, rect.x + 20, rect.y + 36, "暂无套装；穿戴同套装备可激活 2 / 4 / 6 件效果", 27, COLOR.muted)
    end
    for _, block in ipairs(blocks) do
        local y = rect.y + block.top - offset
        if y + block.h > rect.y and y < rect.y + rect.h then
            local set = block.set
            local def = EquipmentSetConfig.get(set.setId)
            local currentN = set.current and set.current.count or 0
            local previewN = set.preview and set.preview.count or 0
            local counts = tostring(currentN) .. "/6"
            if hasPreview then counts = counts .. " → " .. tostring(previewN) .. "/6" end
            EquipmentSetIcon.draw(vg, set.setId, rect.x + 43, y + 28, 46, 1)
            text(vg, rect.x + 80, y + 28, set.name or (def and def.name) or set.setId, 31,
                def and def.color or COLOR.gold)
            text(vg, rect.x + rect.w - 24, y + 28, counts, 28, COLOR.current,
                NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            local lineY = y + 62
            for _, line in ipairs(block.lines) do
                for _, value in ipairs(line.text) do
                    text(vg, rect.x + 20, lineY, value, 27, line.color, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                    lineY = lineY + 36
                end
                lineY = lineY + 12
            end
            nvgBeginPath(vg)
            nvgMoveTo(vg, rect.x + 20, y + block.h - 8)
            nvgLineTo(vg, rect.x + rect.w - 24, y + block.h - 8)
            nvgStrokeColor(vg, nvgRGBA(196, 160, 90, 48))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
    end
    nvgRestore(vg)
    scrollbar(vg, rect, offset, maxScroll)
    return maxScroll
end

function M.drawBackground(vg)
    AttributeView.drawBackground(vg, M.LAYOUT.panel.y)
end

-- 属性页原标题绘图同一实现，字体/frame仍由外层管理。
M.drawLegacyTitle = AttributeView.drawTitle

function M.drawHeader(vg, attributeMode)
    local equipmentMode = attributeMode == "equipment"
    local title = require("core.I18n").lookup(equipmentMode and "装备加成" or "角色属性")
    AttributeView.drawTitle(vg, 540, M.LAYOUT.titleY, title)
    AttributeView.drawDivider(vg, M.LAYOUT.attrs.y - 20)
    AttributeView.drawDivider(vg, M.LAYOUT.setTitleY - 28)
    drawTextStroke(vg, M.LAYOUT.sets.x + 20, M.LAYOUT.setTitleY + 4,
        "套装效果", 31, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        0x66, 0xf8, 0x62, 4)
end

function M.drawEmptyBonuses(vg, available)
    local rect = M.LAYOUT.attrs
    local message = available and "暂无装备增益" or "装备加成暂不可用"
    text(vg, rect.x + 20, rect.y + 34, message, 28, COLOR.muted)
end

--- 共用属性页归一化；有候选仅把并集peak放入同一尺度，不分别归一化。
function M.radarScale(current, preview)
    local peak = 1
    for _, key in ipairs({ "str", "agi", "vit", "spi", "luk", "int" }) do
        peak = math.max(peak, tonumber(current and current[key]) or 0,
            tonumber(preview and preview[key]) or 0)
    end
    return math.max(8, peak / 0.82)
end

function M.drawTooltip(vg, tip)
    if not tip then return end
    local rect = M.LAYOUT.panel
    local width = 850
    local lines = M.wrapText(vg, tip.desc, 27, width - 48)
    local height = math.min(680, 78 + #lines * 36)
    local x = math.max(rect.x + 16, math.min(tip.x, rect.x + rect.w - width - 16))
    local y = math.max(rect.y + 114, math.min(tip.y - height - 10, rect.y + rect.h - height - 12))
    plate(vg, { x = x, y = y, w = width, h = height })
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, width, height, 14)
    nvgFillColor(vg, nvgRGBA(31, 23, 17, 248))
    nvgFill(vg)
    text(vg, x + 24, y + 32, tip.name, 30, COLOR.gold)
    nvgSave(vg)
    nvgIntersectScissor(vg, x + 16, y + 58, width - 32, height - 66)
    for i, line in ipairs(lines) do
        text(vg, x + 24, y + 66 + (i - 1) * 36, line, 27, COLOR.text, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    end
    nvgRestore(vg)
end

-- 属性页雷达使用独立放大布局，导出的点击坐标与绘图始终同源。
M.LEGACY = {
    STAT_BOX_W = 437, STAT_BOX_H = 95,
    STAT_COL1_CX = 308.5, STAT_COL2_CX = 771.5,
    STAT_ROW1_CY = 1641, STAT_ROW_STEP = 111,
    STAT_LAYOUT = DetailAttrs.STAT_LAYOUT,
    HEX_CX = AttributeView.ATTRIBUTE_RADAR.cx, HEX_CY = AttributeView.ATTRIBUTE_RADAR.cy,
    HEX_R = AttributeView.ATTRIBUTE_RADAR.r, HEX_LABEL_R = AttributeView.ATTRIBUTE_RADAR.labelR,
    HEX_NAMES = { "力量", "敏捷", "体质", "魂火", "命数", "秘识" },
}

local HEX_KEYS = { "str", "agi", "vit", "spi", "luk", "int" }
local HEX_COLORS = {
    { 0xE2, 0x4A, 0x3B }, { 0x3D, 0xDC, 0x6E }, { 0xC4, 0x8A, 0x3A },
    { 0xC0, 0x58, 0xE8 }, { 0xFF, 0xD2, 0x3A }, { 0x3E, 0xC6, 0xE0 },
}

local function hexPoint(cx, cy, i, radius)
    local angle = -math.pi * 0.5 + (i - 1) * math.pi / 3
    return cx + math.cos(angle) * radius, cy + math.sin(angle) * radius
end

local function strokeDashed(vg, x1, y1, x2, y2, dash, gap)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 0 then return end
    local ux, uy = dx / len, dy / len
    local pos = 0
    while pos < len do
        local seg = math.min(dash, len - pos)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1 + ux * pos, y1 + uy * pos)
        nvgLineTo(vg, x1 + ux * (pos + seg), y1 + uy * (pos + seg))
        nvgStroke(vg)
        pos = pos + dash + gap
    end
end

local function radarGrid(vg, cx, cy, radius, labelR)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, labelR + 28)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
    nvgFill(vg)
    -- 外圈实线，内圈和六轴虚线，与原属性页一致。
    for ring = 1, 3 do
        local rr = radius * ring / 3
        nvgStrokeColor(vg, nvgRGBA(0xA9, 0xA0, 0x8F, ring == 3 and 170 or 110))
        nvgStrokeWidth(vg, ring == 3 and 2 or 1.5)
        for i = 1, 6 do
            local ax, ay = hexPoint(cx, cy, i, rr)
            local bx, by = hexPoint(cx, cy, i % 6 + 1, rr)
            if ring == 3 then
                nvgBeginPath(vg)
                nvgMoveTo(vg, ax, ay)
                nvgLineTo(vg, bx, by)
                nvgStroke(vg)
            else
                strokeDashed(vg, ax, ay, bx, by, 7, 5)
            end
        end
    end
    nvgStrokeColor(vg, nvgRGBA(0xA9, 0xA0, 0x8F, 120))
    nvgStrokeWidth(vg, 1.5)
    for i = 1, 6 do
        local x, y = hexPoint(cx, cy, i, radius)
        strokeDashed(vg, cx, cy, x, y, 6, 5)
    end
end

local function radarOutline(vg, values, cx, cy, radius, maxValue, color, fill, width)
    nvgBeginPath(vg)
    for i, key in ipairs(HEX_KEYS) do
        local ratio = math.max(0.08, math.min(1, (tonumber(values[key]) or 0) / maxValue))
        local x, y = hexPoint(cx, cy, i, radius * ratio)
        if i == 1 then nvgMoveTo(vg, x, y) else nvgLineTo(vg, x, y) end
    end
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(fill[1], fill[2], fill[3], fill[4]))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], color[4]))
    nvgStrokeWidth(vg, width or 2)
    nvgStroke(vg)
end

local function radarCenter(vg, cx, cy)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, 5)
    nvgFillColor(vg, nvgRGBA(0xFF, 0xF4, 0xD6, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, 5)
    nvgStrokeColor(vg, nvgRGBA(0xC4, 0x8A, 0x3A, 255))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
end

-- 数字在真实字体/缩放下复测，描边也留在右列内；普通值保留原字号。
local function radarNumberFont(vg, label, size, x, y, maxWidth, margin, stroke)
    local left = math.max(540 + margin, x - maxWidth * 0.5)
    local right = math.min(1080 - margin, x + maxWidth * 0.5)
    return AttributeView.fitText(vg, label, size, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        x, y, left, right, stroke or 0)
end

--- 属性页独立放大雷达；归一化与数据口径不变，不接收或读取预览。
function M.drawLegacy(vg, statValues)
    local layout = M.LEGACY
    local values = statValues or {}
    local maxValue = M.radarScale(values)
    radarGrid(vg, layout.HEX_CX, layout.HEX_CY, layout.HEX_R, layout.HEX_LABEL_R)
    radarOutline(vg, values, layout.HEX_CX, layout.HEX_CY, layout.HEX_R, maxValue,
        { 0xE8, 0xDC, 0xC8, 200 }, { 0xC4, 0x8A, 0x3A, 70 }, 2)
    radarCenter(vg, layout.HEX_CX, layout.HEX_CY)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for i, name in ipairs(layout.HEX_NAMES) do
        local color = HEX_COLORS[i]
        local lx, ly = hexPoint(layout.HEX_CX, layout.HEX_CY, i, layout.HEX_LABEL_R)
        text(vg, lx, ly - 26, name, 30, color, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local valueText = tostring(values[HEX_KEYS[i]] or 0)
        local font = radarNumberFont(vg, valueText, 38, lx, ly + 18, 160, 12, 3)
        drawTextStroke(vg, lx, ly + 18, valueText,
            font, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, color[1], color[2], color[3], 3)
    end
end

-- 只在配装雷达叠加差集；属性页 drawLegacy 的底图/比例保持原样。
local RadarDiff = require("ui.character.detail.CharacterRadarDiff")

---@param vertices CharacterRadarPoint[]
local function radarPolygon(vg, vertices)
    nvgBeginPath(vg)
    for i, point in ipairs(vertices) do
        if i == 1 then nvgMoveTo(vg, point.x, point.y) else nvgLineTo(vg, point.x, point.y) end
    end
    nvgClosePath(vg)
end

--- 淡金当前图不重染共享内区；仅增减面积/真正移动的试穿边分别用绿/红。
function M.drawRadar(vg, current, preview, equipmentMode)
    local layout = M.LAYOUT.radar
    local values = current or {}
    local maxValue = M.radarScale(values, preview)
    -- 总属性沿用8%视觉下限；装备净增益允许0落在中心，避免空装虚构六围。
    local visualFloor = equipmentMode and 0 or maxValue * 0.08
    local visualCurrent, visualPreview = {}, preview and {} or nil
    for _, key in ipairs(HEX_KEYS) do
        visualCurrent[key] = math.max(visualFloor, tonumber(values[key]) or 0)
        if visualPreview then
            visualPreview[key] = math.max(visualFloor, tonumber(preview[key]) or 0)
        end
    end
    local comparison = RadarDiff.compare(visualCurrent, visualPreview,
        layout.cx, layout.cy, layout.r, maxValue)
    -- 不另设雷达scissor：最右标签cx≈999、数字完整保留在1080画布内。
    radarGrid(vg, layout.cx, layout.cy, layout.r, layout.labelR)
    radarPolygon(vg, comparison.oldVertices)
    nvgFillColor(vg, nvgRGBA(0xC4, 0x8A, 0x3A, 70))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(0xE8, 0xDC, 0xC8, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    for _, region in ipairs(comparison.regions) do
        local color = region.sign > 0 and COLOR.green or COLOR.red
        radarPolygon(vg, region.vertices)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 75))
        nvgFill(vg)
    end
    for _, edge in ipairs(comparison.edges) do
        local color = edge.sign > 0 and COLOR.green or COLOR.red
        nvgBeginPath(vg)
        nvgMoveTo(vg, edge.from.x, edge.from.y)
        nvgLineTo(vg, edge.to.x, edge.to.y)
        nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 255))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end
    radarCenter(vg, layout.cx, layout.cy)
    for i, name in ipairs(M.LEGACY.HEX_NAMES) do
        local key = HEX_KEYS[i]
        local lx, ly = hexPoint(layout.cx, layout.cy, i, layout.labelR)
        local currentValue = tonumber(values[key]) or 0
        local nextValue = preview and tonumber(preview[key]) or currentValue
        local color = HEX_COLORS[i]
        text(vg, lx, ly - 24, name, 26, color, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local valueText = tostring(math.floor(currentValue))
        if equipmentMode then
            local amount = math.abs(currentValue) < 0.1 and string.format("%.6f", currentValue)
                or string.format("%.1f", currentValue)
            valueText = amount:gsub("0+$", ""):gsub("%.$", "")
            if currentValue > 0 then valueText = "+" .. valueText end
        end
        local valueFont = radarNumberFont(vg, valueText, 34, lx, ly + 16, 150, 5, 3)
        drawTextStroke(vg, lx, ly + 16, valueText,
            valueFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, color[1], color[2], color[3], 3)
        local delta = nextValue - currentValue
        if preview and math.abs(delta) > 0.000001 then
            local amount
            if math.abs(delta - math.floor(delta + 0.5)) < 0.000001 then
                amount = string.format("%.0f", delta)
            elseif math.abs(delta) < 0.1 then
                -- 小数变化不显示成 +0.0；不影响当前数值的字号和基线。
                amount = string.format("%.6f", delta):gsub("0+$", ""):gsub("%.$", "")
            else
                amount = string.format("%.1f", delta)
            end
            local deltaText = (delta > 0 and "+" or "") .. amount
            local deltaFont = radarNumberFont(vg, deltaText, layout.deltaFontSize,
                lx, ly - layout.deltaOffset, 150, 5, 0)
            text(vg, lx, ly - layout.deltaOffset, deltaText, deltaFont,
                delta > 0 and COLOR.green or COLOR.red, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end
    end
end

return M
