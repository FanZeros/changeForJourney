-- 屏幕逻辑坐标的新手引导绘制；帧变换、DPR 与字体由宿主负责。
-- hs 是实际可点击矩形；spotlight 可单独指定视觉范围，hole 不能用于点击命中。
local TutorialOverlay = {}

---@class TutorialOverlayRect
---@field cx number
---@field cy number
---@field w number
---@field h number
---@field spotlight TutorialOverlayRect? 仅视觉范围，不参与命中。

---@class TutorialOverlayLayout
---@field bubble TutorialOverlayRect
---@field skip TutorialOverlayRect
---@field hs TutorialOverlayRect?
---@field hole TutorialOverlayRect?
---@field fontSize number
---@field lineHeight number
---@field padding number
---@field lines string[]?
---@field skipVisible boolean?

local RECOVERY_TEXT = "暂时找不到引导目标，可点击跳过继续。"
local GAP, VISUAL_PAD = 12, 8

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

---@param cx number
---@param cy number
---@param w number
---@param h number
---@return TutorialOverlayRect
local function rect(cx, cy, w, h)
    return { cx = cx, cy = cy, w = w, h = h }
end

---@param a TutorialOverlayRect
---@param b TutorialOverlayRect?
---@return boolean
local function overlaps(a, b)
    return b ~= nil and math.abs(a.cx - b.cx) < (a.w + b.w) * 0.5
        and math.abs(a.cy - b.cy) < (a.h + b.h) * 0.5
end

---@param hs TutorialOverlayRect?
---@return TutorialOverlayRect?
local function visibleTarget(width, height, hs)
    if not hs or hs.w <= 0 or hs.h <= 0 then return nil end
    local left = math.max(0, hs.cx - hs.w * 0.5)
    local top = math.max(0, hs.cy - hs.h * 0.5)
    local right = math.min(width, hs.cx + hs.w * 0.5)
    local bottom = math.min(height, hs.cy + hs.h * 0.5)
    if right <= left or bottom <= top then return nil end
    return rect((left + right) * 0.5, (top + bottom) * 0.5, right - left, bottom - top)
end

-- 几何布局是纯函数，不依赖字体、输入、引擎状态或模块缓存。
---@param width number
---@param height number
---@param hs TutorialOverlayRect?
---@param textWidth? number 未换行文字总宽度，由 draw 的字体测量提供。
---@param desiredHeight? number draw 测得的实际换行高度。
---@return TutorialOverlayLayout
local function makeLayout(width, height, hs, textWidth, desiredHeight)
    local widthSafe, heightSafe = math.max(1, width), math.max(1, height)
    local margin = math.min(16, widthSafe * 0.04, heightSafe * 0.04)
    local fontSize = heightSafe >= 540 and 20 or 16
    local lineHeight, padding = fontSize * 1.4, math.min(20, widthSafe * 0.06)
    local target = visibleTarget(widthSafe, heightSafe, hs)
    ---@type TutorialOverlayRect?
    local hole = nil
    if target then
        local visual = visibleTarget(widthSafe, heightSafe, hs.spotlight) or target
        local pad = hs.spotlight and 0 or VISUAL_PAD
        local left = math.max(0, visual.cx - visual.w * 0.5 - pad)
        local top = math.max(0, visual.cy - visual.h * 0.5 - pad)
        local right = math.min(widthSafe, visual.cx + visual.w * 0.5 + pad)
        local bottom = math.min(heightSafe, visual.cy + visual.h * 0.5 + pad)
        hole = rect((left + right) * 0.5, (top + bottom) * 0.5, right - left, bottom - top)
    end
    local skipW = math.min(120, widthSafe - margin * 2)
    local skipH = math.min(44, heightSafe - margin * 2)
    local bottomY = heightSafe - margin - skipH * 0.5
    local skip = rect(widthSafe - margin - skipW * 0.5, bottomY, skipW, skipH)
    if overlaps(skip, hole) then
        skip = rect(margin + skipW * 0.5, bottomY, skipW, skipH)
    end
    if overlaps(skip, hole) and hole then
        -- 两个底角都被目标占用时，保留当前侧边，只向上移动必要的距离。
        skip.cy = clamp(hole.cy - hole.h * 0.5 - GAP - skipH * 0.5,
            margin + skipH * 0.5, bottomY)
    end

    local maxW = math.max(1, math.min(520, widthSafe - margin * 2))
    local wantedW = math.min(maxW, math.max(math.min(220, maxW), (textWidth or 440) + padding * 2))
    local estimatedLines = math.max(1, math.ceil((textWidth or 440) / math.max(1, wantedW - padding * 2)))
    local wantedH = desiredHeight or (estimatedLines * lineHeight + padding * 2)
    local safe = rect(widthSafe * 0.5, heightSafe * 0.5,
        widthSafe - margin * 2, heightSafe - margin * 2)
    ---@type TutorialOverlayRect[]
    local regions = {}
    local function addRegion(left, top, right, bottom)
        if right > left and bottom > top then
            regions[#regions + 1] = rect((left + right) * 0.5, (top + bottom) * 0.5,
                right - left, bottom - top)
        end
    end
    if hole then
        local left, top = hole.cx - hole.w * 0.5, hole.cy - hole.h * 0.5
        local right, bottom = hole.cx + hole.w * 0.5, hole.cy + hole.h * 0.5
        -- 优先放目标上方，其次下方；矮横屏允许左右侧方。
        addRegion(margin, margin, widthSafe - margin, top - GAP)
        addRegion(margin, bottom + GAP, widthSafe - margin, heightSafe - margin)
        addRegion(margin, margin, left - GAP, heightSafe - margin)
        addRegion(right + GAP, margin, widthSafe - margin, heightSafe - margin)
    else
        regions[1] = safe
    end
    ---@type TutorialOverlayRect[]
    local available = {}
    for _, room in ipairs(regions) do
        if not overlaps(room, skip) then
            available[#available + 1] = room
        else
            local left, top = room.cx - room.w * 0.5, room.cy - room.h * 0.5
            local right, bottom = room.cx + room.w * 0.5, room.cy + room.h * 0.5
            local sx0, sy0 = skip.cx - skip.w * 0.5 - GAP, skip.cy - skip.h * 0.5 - GAP
            local sx1, sy1 = skip.cx + skip.w * 0.5 + GAP, skip.cy + skip.h * 0.5 + GAP
            local pieces = {
                rect(room.cx, (top + math.min(bottom, sy0)) * 0.5, room.w, math.min(bottom, sy0) - top),
                rect(room.cx, (math.max(top, sy1) + bottom) * 0.5, room.w, bottom - math.max(top, sy1)),
                rect((left + math.min(right, sx0)) * 0.5, room.cy, math.min(right, sx0) - left, room.h),
                rect((math.max(left, sx1) + right) * 0.5, room.cy, right - math.max(left, sx1), room.h),
            }
            for _, piece in ipairs(pieces) do
                if piece.w > 0 and piece.h > 0 then available[#available + 1] = piece end
            end
        end
    end
    ---@type TutorialOverlayRect?
    local chosen = nil
    local bestCapacity = -1
    for _, room in ipairs(available) do
        if room.w >= wantedW and room.h >= wantedH then chosen = room; break end
        local capacity = math.min(wantedW, room.w) * math.min(wantedH, room.h)
        if capacity > bestCapacity then bestCapacity, chosen = capacity, room end
    end
    -- 目标铺满全屏时无空白可用，优先让提示和跳过保留在屏幕内。
    local room = chosen or safe
    local bubbleW, bubbleH = math.min(wantedW, room.w), math.min(wantedH, room.h)
    local bubbleCX = clamp(target and target.cx or widthSafe * 0.5,
        room.cx - room.w * 0.5 + bubbleW * 0.5, room.cx + room.w * 0.5 - bubbleW * 0.5)
    local bubbleCY = room.cy
    if target and room.cy < target.cy then
        bubbleCY = room.cy + room.h * 0.5 - bubbleH * 0.5
    elseif target and room.cy > target.cy then
        bubbleCY = room.cy - room.h * 0.5 + bubbleH * 0.5
    end
    return {
        bubble = rect(bubbleCX, bubbleCY, bubbleW, bubbleH), skip = skip,
        hs = target, hole = hole, fontSize = fontSize, lineHeight = lineHeight, padding = padding,
    }
end

---@param width number
---@param height number
---@param hs TutorialOverlayRect?
---@param textWidth? number
---@return TutorialOverlayLayout
function TutorialOverlay.layout(width, height, hs, textWidth)
    return makeLayout(width, height, hs, textWidth)
end

---@param vg any
---@param text string
---@param maxWidth number
---@return string[]
local function wrapText(vg, text, maxWidth)
    ---@type string[]
    local lines = {}
    local line = ""
    for _, codepoint in utf8.codes(text) do
        local char = utf8.char(codepoint)
        if char == "\n" then
            lines[#lines + 1], line = line, ""
        elseif char ~= "\r" then
            local candidate = line .. char
            local advance = nvgTextBounds(vg, 0, 0, candidate)
            if line ~= "" and advance > maxWidth then
                lines[#lines + 1], line = line, char
            else
                line = candidate
            end
        end
    end
    lines[#lines + 1] = line
    return lines
end

local function rounded(vg, box, radius)
    nvgRoundedRect(vg, box.cx - box.w * 0.5, box.cy - box.h * 0.5, box.w, box.h, radius)
end

---@param vg any 宿主初始化过 sans 字体的 NanoVG 上下文。
---@param width number
---@param height number
---@param hs TutorialOverlayRect?
---@param text string?
---@param elapsed number
---@param groupElapsed number
---@param alpha number
---@param invisible? boolean 等待动画/事件的步骤只显示跳过按钮。
---@param allowDrag? boolean 拖拽教学不压暗整个屏幕，以便同时看到源卡与目标槽。
---@param preparing? boolean 缺热点的短暂页面准备期显示等待，不误报目标失效。
---@return TutorialOverlayLayout
function TutorialOverlay.draw(vg, width, height, hs, text, elapsed, groupElapsed, alpha, invisible, allowDrag, preparing)
    local initial = TutorialOverlay.layout(width, height, hs)
    local displayText = (initial.hs or preparing) and (text or "") or RECOVERY_TEXT
    nvgSave(vg)
    -- 保留宿主的屏幕逻辑帧变换，只清除之前残留的面板裁剪。
    nvgResetScissor(vg)
    nvgScissor(vg, 0, 0, math.max(1, width), math.max(1, height))
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, initial.fontSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local textWidth = 0
    for paragraph in (displayText .. "\n"):gmatch("(.-)\n") do
        textWidth = textWidth + nvgTextBounds(vg, 0, 0, paragraph)
    end
    local result = TutorialOverlay.layout(width, height, hs, textWidth)
    local lines = wrapText(vg, displayText, math.max(1, result.bubble.w - result.padding * 2))
    result = makeLayout(width, height, hs, textWidth, #lines * result.lineHeight + result.padding * 2)
    lines = wrapText(vg, displayText, math.max(1, result.bubble.w - result.padding * 2))
    local maxLines = math.max(1, math.floor((result.bubble.h - result.padding * 2) / result.lineHeight))
    if #lines > maxLines then
        local last = lines[maxLines] or ""
        while last ~= "" and nvgTextBounds(vg, 0, 0, last .. "…") > result.bubble.w - result.padding * 2 do
            local lastStart = utf8.offset(last, -1)
            last = lastStart and last:sub(1, lastStart - 1) or ""
        end
        lines[maxLines] = last .. "…"
        for i = #lines, maxLines + 1, -1 do lines[i] = nil end
    end
    result.lines, result.skipVisible = lines, groupElapsed >= 1
    local opacity = clamp(alpha, 0, 1)
    if opacity > 0.01 then
        if not invisible then
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, math.max(1, width), math.max(1, height))
            if result.hole then
                rounded(vg, result.hole, 10)
                -- 填充方向只作用于最近的子路径：标记洞，不要标记外层全屏矩形。
                nvgPathWinding(vg, NVG_HOLE)
            end
            if not allowDrag then
                nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(170 * opacity)))
                nvgFill(vg)
            end
            if result.hole then
                nvgBeginPath(vg)
                rounded(vg, result.hole, 10)
                local pulse = 0.72 + 0.28 * (0.5 + 0.5 * math.sin(elapsed * 4))
                nvgStrokeColor(vg, nvgRGBA(255, 215, 88, math.floor(255 * opacity * pulse)))
                nvgStrokeWidth(vg, 2)
                nvgStroke(vg)
            end
            if displayText ~= "" then
                nvgBeginPath(vg)
                rounded(vg, result.bubble, 12)
                nvgFillColor(vg, nvgRGBA(248, 236, 211, math.floor(255 * opacity)))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(183, 139, 63, math.floor(255 * opacity)))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
                nvgSave(vg)
                local bubble = result.bubble
                nvgIntersectScissor(vg, bubble.cx - bubble.w * 0.5, bubble.cy - bubble.h * 0.5, bubble.w, bubble.h)
                nvgFillColor(vg, nvgRGBA(67, 42, 24, math.floor(255 * opacity)))
                local top = bubble.cy - (#lines * result.lineHeight) * 0.5
                for i, line in ipairs(lines) do
                    nvgText(vg, bubble.cx - bubble.w * 0.5 + result.padding,
                        top + (i - 1) * result.lineHeight, line, nil)
                end
                nvgRestore(vg)
            end
        end
        if result.skipVisible then
            nvgBeginPath(vg)
            rounded(vg, result.skip, 10)
            nvgFillColor(vg, nvgRGBA(87, 60, 25, math.floor(245 * opacity)))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(237, 193, 88, math.floor(255 * opacity)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
            nvgFontSize(vg, result.fontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 222, 134, math.floor(255 * opacity)))
            nvgText(vg, result.skip.cx, result.skip.cy, "跳过 >", nil)
        end
    end
    nvgRestore(vg)
    return result
end

return TutorialOverlay
