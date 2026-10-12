-- 塔之暗契三选一：UI 组件承担文字/按钮，程序几何与独立 Spine 承担装饰。
-- 复用宿主帧与设计坐标桥，不开第二帧；卡面命中区不随装饰动画漂移。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local Presentation = require("ui.tower.TowerPresentation")
local Effect = require("ui.tower.TowerOathEffect")

local View = {}
---@class TowerChoiceWidgets
---@field root Panel
---@field name Label
---@field quality Label
---@field action Button
---@field signature string
---@type TowerChoiceWidgets[]
local cards = {}
---@type Panel?
local header = nil
---@type Label?
local title = nil
---@type Label?
local floorLabel = nil
---@type Label?
local hint = nil
---@type Panel?
local footer = nil
---@type Button?
local cancel = nil
---@type Label?
local notice = nil
local layoutKey = ""
local COPPER = {168, 121, 76, 255}
local BONE = {231, 219, 195, 255}

-- 每层只恢复自己保存的状态；子绘制失败时不让外层误弹仍未释放的内部栈。
local function withState(vg, draw)
    nvgSave(vg)
    local ok, err = xpcall(draw, debug.traceback)
    nvgRestore(vg)
    if not ok then error(err, 0) end
end

local function label(x, y, w, h, textSize, color)
    return UI.Label {
        text = "", position = "absolute", left = x, top = y, width = w, height = h,
        fontSize = textSize * .75, fontColor = color or BONE,
        textAlign = "center", verticalAlign = "middle", whiteSpace = "nowrap",
        autoFitText = true, flexShrink = 1, pointerEvents = "none",
    }
end

local function button(x, y, w, h)
    return UI.Button {
        text = "", position = "absolute", left = x, top = y, width = w, height = h,
        fontSize = 26 * .75, fontFamily = "sans", fontWeight = "normal",
        autoFitText = true, pointerEvents = "none", padding = 0,
        borderRadius = 2, borderWidth = 1, borderColor = COPPER, textColor = BONE,
        backgroundColor = {48, 32, 27, 255}, hoverBackgroundColor = {70, 41, 32, 255},
        disabledBackgroundColor = {27, 24, 23, 255}, disabledTextColor = {116, 108, 95, 255},
        boxShadow = false,
    }
end

function View.cardRect(index, landscape)
    if landscape then return 360 + (index - 1) * 600, 620, 550, 540 end
    return 540, 744 + (index - 1) * 368, 998, 321
end

function View.fit(width, height)
    if not width or not height then return 1, 0, 0 end
    if width <= 0 or height <= 0 then return 0, 0, 0 end
    local fit = math.min(width / 1920, height / 1080)
    return fit, (width - 1920 * fit) * .5, (height - 1080 * fit) * .5
end

function View.cancelRect(landscape)
    if landscape then return 1705, 986, 230, 64 end
    return 875, 1900, 260, 76
end

-- 截角暗铁外壳，不复用旧亮色底图；边缘装饰不遮住文字。
local function plate(vg, x, y, width, height, color, emphasis)
    local cut = 16
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + cut, y)
    nvgLineTo(vg, x + width - cut, y)
    nvgLineTo(vg, x + width, y + cut)
    nvgLineTo(vg, x + width, y + height - cut)
    nvgLineTo(vg, x + width - cut, y + height)
    nvgLineTo(vg, x + cut, y + height)
    nvgLineTo(vg, x, y + height - cut)
    nvgLineTo(vg, x, y + cut)
    nvgClosePath(vg)
    local top = nvgRGBA(34, 29, 28, 255)
    local bottom = nvgRGBA(14, 15, 17, 255)
    ---@cast top NVGcolor
    ---@cast bottom NVGcolor
    local paint = nvgLinearGradient(vg, x, y, x, y + height, top, bottom)
    ---@cast paint NVGpaint
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    local border = nvgRGBA(color[1], color[2], color[3], emphasis and 240 or 150)
    ---@cast border NVGcolor
    nvgStrokeColor(vg, border)
    nvgStrokeWidth(vg, emphasis and 3 or 2)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + 32, y + 15)
    nvgLineTo(vg, x + width - 32, y + 15)
    nvgMoveTo(vg, x + 32, y + height - 15)
    nvgLineTo(vg, x + width - 32, y + height - 15)
    nvgStrokeColor(vg, border)
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

local function ensure(landscape)
    Surface.init()
    local key = landscape and "landscape" or "portrait"
    if key == layoutKey and header then return end
    View.destroyWidgets()
    layoutKey = key
    local width, height = landscape and 1920 or 1080, landscape and 1080 or 2400
    header = UI.Panel {width = width, height = height, pointerEvents = "none"}
    title = label(landscape and 120 or 65, landscape and 64 or 390, landscape and 1680 or 950, 65, 48)
    floorLabel = label(landscape and 120 or 65, landscape and 145 or 468, landscape and 1680 or 950, 50, 32, COPPER)
    hint = label(landscape and 120 or 65, landscape and 218 or 524, landscape and 1680 or 950, 46, 28)
    header:AddChild(title)
    header:AddChild(floorLabel)
    header:AddChild(hint)
    footer = UI.Panel {width = width, height = height, pointerEvents = "none"}
    local cx, cy, cw, ch = View.cancelRect(landscape)
    cancel = button(cx - cw * .5, cy - ch * .5, cw, ch)
    notice = label(landscape and 90 or 60, landscape and 935 or 1770,
        landscape and 1360 or 950, 68, 23, {161, 148, 127, 255})
    footer:AddChild(notice)
    footer:AddChild(cancel)
    for index = 1, 3 do
        local _, _, w, h = View.cardRect(index, landscape)
        local root = UI.Panel {width = w, height = h, pointerEvents = "none"}
        local name = label(landscape and 28 or 190, 26, landscape and w - 56 or 540, 62, 36)
        local quality = label(landscape and 28 or 760, landscape and 272 or 30,
            landscape and w - 56 or 210, 40, 24)
        local action = button(landscape and 70 or 695, landscape and h - 78 or h - 70,
            landscape and w - 140 or 270, 48)
        root:AddChild(name)
        root:AddChild(quality)
        root:AddChild(action)
        cards[index] = {root = root, name = name, quality = quality, action = action, signature = ""}
    end
end

function View.drawHeader(vg, state, landscape)
    ensure(landscape)
    local currentTitle, currentFloor, currentHint, root = title, floorLabel, hint, header
    if not currentTitle or not currentFloor or not currentHint or not root then return end
    currentTitle:SetText(Presentation.text("塔之暗契"))
    currentFloor:SetText(Presentation.text("第%d层", state.floor))
    currentHint:SetText(Presentation.text("三枚契印 · 择一承受"))
    Surface.draw(root, vg, landscape and 1920 or 1080, landscape and 1080 or 2400)
end

function View.drawCard(vg, index, choice, state, landscape, keyword, elapsed, token)
    ensure(landscape)
    local widgets = cards[index]
    if not widgets then return end
    local cx, cy, width, height = View.cardRect(index, landscape)
    local x, y = cx - width * .5, cy - height * .5
    local quality = math.max(1, math.min(3, math.floor(tonumber(choice.quality) or 1)))
    local color = Presentation.rarityColor(quality)
    local picked = state.pendingRequest and state.pendingRequest.buffId == choice.id
    local allowed = not state.pending and (not state.retryBuffId or state.retryBuffId == choice.id)
    plate(vg, x, y, width, height, color, picked or false)
    local iconX, iconY = landscape and cx or x + 103, landscape and y + 180 or y + 164
    local sealSize, iconSize = landscape and 220 or 175, landscape and 145 or 126
    withState(vg, function()
        nvgIntersectScissor(vg, x + 8, y + 10, width - 16, height - 20)
        Effect.draw(vg, iconX, iconY, sealSize, math.max(0, elapsed - (index - 1) * .10), token, quality)
        Effect.drawIcon(vg, Presentation.icon(choice), iconX, iconY, iconSize, (allowed or picked) and 1 or .55)
    end)
    widgets.name:SetText(Presentation.name(choice))
    local qualityText = Presentation.rarity(quality)
    local qualityWidth = landscape and width - 56 or 210
    local qualitySize = 24
    withState(vg, function()
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, qualitySize)
        while nvgTextBounds(vg, 0, 0, qualityText) > qualityWidth - 8 and qualitySize > 14 do
            qualitySize = qualitySize - 1
            nvgFontSize(vg, qualitySize)
        end
    end)
    -- 固定宽Label的autoFit不保证所有译文收缩；字号先于文本更新，避免旧测量缓存。
    widgets.quality:SetFontSize(qualitySize * .75)
    widgets.quality:SetText(qualityText)
    widgets.quality:SetFontColor({color[1], color[2], color[3], 255})
    widgets.action:SetText(Presentation.text(picked and "正在铭刻" or "铭刻"))
    widgets.action:SetDisabled(not allowed)
    withState(vg, function()
        nvgTranslate(vg, x, y)
        Surface.draw(widgets.root, vg, width, height)
    end)
    -- 长译文先测真实字体再缩字；完整描述不裁掉，隐藏区不保留关键词热区。
    local descX = landscape and x + 34 or x + 205
    local descY = landscape and y + 325 or y + 109
    local descW, descH = landscape and width - 68 or 755, landscape and 125 or 124
    local text = Presentation.description(choice)
    local size = landscape and 29 or 32
    local measured = keyword:measureHeight(vg, text, descW, size)
    while measured > descH and size > 16 do
        size = size - 1
        measured = keyword:measureHeight(vg, text, descW, size)
    end
    withState(vg, function()
        nvgIntersectScissor(vg, descX, descY, descW, descH)
        keyword:draw(vg, text, descX, descY, descW, size)
    end)
    for h = #keyword.hotspots, 1, -1 do
        local spot = keyword.hotspots[h]
        if spot.x1 < descX or spot.x2 > descX + descW or spot.y1 < descY or spot.y2 > descY + descH then
            table.remove(keyword.hotspots, h)
        end
    end
end

function View.drawFooter(vg, state, landscape)
    ensure(landscape)
    local currentCancel, currentNotice, root = cancel, notice, footer
    if not currentCancel or not currentNotice or not root then return end
    currentCancel:SetText(Presentation.text("稍后选择"))
    currentCancel:SetDisabled(state.pending)
    currentNotice:SetText(Presentation.text(state.retryBuffId and "仅可重试原契印"
        or "选择保留，战斗继续；强化从下一层生效"))
    Surface.draw(root, vg, landscape and 1920 or 1080, landscape and 1080 or 2400)
end

function View.drawKeywordPopup(vg, keyword, index, landscape)
    -- KeywordText 的旧设计宽为1080；将气泡置于窗口内同宽局部空间，第三卡不挤向左侧。
    local cx = View.cardRect(index, landscape)
    local offset = landscape and math.max(0, math.min(840, cx - 540)) or 0
    keyword:setPopupTransform(function(x, y) return x - offset, y end)
    withState(vg, function()
        nvgTranslate(vg, offset, 0)
        keyword:drawPopup(vg)
    end)
end

function View.destroyWidgets()
    if header then header:Destroy() end
    if footer then footer:Destroy() end
    for _, widgets in ipairs(cards) do widgets.root:Destroy() end
    cards = {}
    header, title, floorLabel, hint, footer, cancel, notice = nil, nil, nil, nil, nil, nil, nil
    layoutKey = ""
end

return View
