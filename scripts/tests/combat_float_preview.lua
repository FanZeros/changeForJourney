-- 基于 scaffold-2d 生命周期及 NanoVG 示例的独立表现样片。
-- 所有命中均为内存模拟，不加载 main/Boot/Combat/Settings/玩家存档。
local UI = require("urhox-libs/UI")
local Style = require("tests.float_preview.ImpactStyle")
local NumberUtil = require("core.NumberUtil")
local AD = require("systems.AttributeDef")

---@type NVGContextWrapper?
local vg = nil
local DESIGN_W, DESIGN_H = 1920, 1080
local elapsed, lastEvent, frames = 0, -1, 0
local paused, dense = false, true
---@type number
local fixedPhase = -1
local selfTest = false
local checks = 0
local geometryKey = ""
local font = "float-preview"
local singleStates, laneStates = {}, {}
local singleTargets, laneTargets = {}, {}
local oldNumbers = {}
local previewLabels = {}
local titleLabel = UI.Label { text = "战斗飘字 · 克制重击", fontSize = 30 }
local subtitleLabel = UI.Label { text = "独立动态样片 / 普通轻弹 · 暴击裂印 · 治疗聚合 · 吸盾压缩", fontSize = 17 }
local pauseButton = UI.Button { text = "暂停", fontSize = 16, onClick = function(self)
    paused = not paused
    ---@cast self Button
    self:SetText(paused and "继续" or "暂停")
    print("[FloatPreview] 暂停=" .. tostring(paused))
end }

local TYPES = {
    { title = "01  普通伤害", detail = "短促弹出 / 稳定读数 / 快速擦除", amount = 1286,
        meta = { channel = "damage", atkType = AD.ATK_SLASH } },
    { title = "02  暴击", detail = "重击回弹 / 短裂痕 / 三枚碎片", amount = 4938,
        meta = { channel = "damage", atkType = AD.ATK_FIRE, isCrit = true } },
    { title = "03  治疗", detail = "柔和展开 / 光点聚合 / 内收", amount = 864,
        meta = { channel = "heal", atkType = AD.ATK_HOLY } },
    { title = "04  护盾吸收", detail = "硬质压缩 / 盾纹 / 紧凑折收", amount = 732,
        meta = { channel = "shield", atkType = AD.ATK_ICE } },
}
local function rgba(r, g, b, a) return nvgRGBA(r, g, b, a or 255) end
local function rect(ctx, x, y, w, h, rgb, radius)
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, x, y, w, h, radius or 6)
    nvgFillColor(ctx, rgba(rgb[1], rgb[2], rgb[3], rgb[4])); nvgFill(ctx)
end
local function line(ctx, x1, y1, x2, y2, rgb, width)
    nvgBeginPath(ctx); nvgMoveTo(ctx, x1, y1); nvgLineTo(ctx, x2, y2)
    nvgStrokeColor(ctx, rgba(rgb[1], rgb[2], rgb[3], rgb[4])); nvgStrokeWidth(ctx, width or 1); nvgStroke(ctx)
end

local function resetPreview()
    for _, state in ipairs(singleStates) do Style.reset(state) end
    for _, state in ipairs(laneStates) do Style.reset(state) end
    oldNumbers, elapsed, lastEvent = {}, 0, -1
    print("[FloatPreview] 重新播放，正式战斗状态未加载")
end
local replayButton = UI.Button { text = "重新播放", fontSize = 16, onClick = resetPreview }
local densityButton = UI.Button { text = "密集连击：开", fontSize = 16, onClick = function(self)
    dense = not dense
    ---@cast self Button
    self:SetText(dense and "密集连击：开" or "密集连击：关")
    resetPreview()
end }
local expandedLanes = false
local laneButton = UI.Button { text = "三行放大", fontSize = 16, onClick = function(self)
    expandedLanes = not expandedLanes
    ---@cast self Button
    self:SetText(expandedLanes and "返回对比" or "三行放大")
    for _, item in ipairs(previewLabels) do item.widget:SetVisible(not expandedLanes) end
    print("[FloatPreview] 三行放大=" .. tostring(expandedLanes))
end }
local noteLabel = UI.Label { text = "独立样片：不改战斗，不震屏，不读取玩家档。", fontSize = 16 }

local function makeLabel(text, size, rgb)
    local label = UI.Label { text = text, fontSize = size, fontColor = rgb or { 213, 198, 166, 255 },
        position = "absolute", pointerEvents = "none" }
    return label
end
local function initContent()
    for i = 1, 4 do
        singleStates[i], singleTargets[i] = Style.newState(), {}
    end
    for i = 1, 4 do
        laneStates[i], laneTargets[i] = Style.newState(), { {}, {}, {}, {} }
    end
end

local function initUI()
    UI.Init({ theme = "default-dark", scale = UI.Scale.DEFAULT,
        fonts = { { family = "sans", weights = {
            normal = "Fonts/NotoSansCJKkr-Bold.otf", bold = "Fonts/NotoSansCJKkr-Bold.otf",
        } } } })
    local children = { titleLabel, subtitleLabel, pauseButton, replayButton, densityButton, laneButton, noteLabel }
    for i, item in ipairs(TYPES) do
        local x = 44 + (i - 1) * 466
        local label = makeLabel(item.title, 23)
        previewLabels[#previewLabels + 1] = { widget = label, x = x + 22, y = 181, size = 23 }
        children[#children + 1] = label
        local detail = makeLabel(item.detail, 16, { 137, 127, 111, 255 })
        previewLabels[#previewLabels + 1] = { widget = detail, x = x + 22, y = 219, size = 16 }
        children[#children + 1] = detail
    end
    for _, spec in ipairs({
        { text = "高速连击 · 新旧节奏对比", x = 64, y = 486, size = 24 },
        { text = "旧：持续上移、持续缩小", x = 70, y = 534, size = 17 },
        { text = "新：弹出、短驻留、收束", x = 584, y = 534, size = 17 },
        { text = "三行密集场景 · 每行独立预算", x = 1130, y = 486, size = 24 },
        { text = "旧侧只复现当前移动/缩放节奏；新侧为候选表现，不是正式战斗录像。", x = 64, y = 948, size = 15 },
    }) do
        local label = makeLabel(spec.text, spec.size)
        previewLabels[#previewLabels + 1] = { widget = label, x = spec.x, y = spec.y, size = spec.size }
        children[#children + 1] = label
    end
    UI.SetRoot(UI.Panel { width = "100%", height = "100%", pointerEvents = "box-none", children = children })
end

local function layoutUI()
    local w, h, dpr = graphics:GetWidth(), graphics:GetHeight(), graphics:GetDPR()
    local scale = math.min(w / DESIGN_W, h / DESIGN_H)
    local uiScale = UI.GetScale()
    local factor = scale / uiScale
    local ox, oy = (w - DESIGN_W * scale) * 0.5 / uiScale, (h - DESIGN_H * scale) * 0.5 / uiScale
    local key = table.concat({ w, h, dpr, uiScale }, ":")
    if key == geometryKey then return end
    geometryKey = key
    local function place(widget, x, y, width, height, size)
        widget:SetStyle({ position = "absolute", left = ox + x * factor, top = oy + y * factor,
            width = width * factor, height = height * factor, fontSize = size * factor })
    end
    place(titleLabel, 54, 36, 1300, 56, 32)
    place(subtitleLabel, 56, 98, 1800, 35, 18)
    titleLabel:SetStyle({ fontColor = { 237, 221, 189, 255 } })
    subtitleLabel:SetStyle({ fontColor = { 147, 136, 120, 255 } })
    for _, item in ipairs(previewLabels) do place(item.widget, item.x, item.y, 760, 40, item.size) end
    place(pauseButton, 54, 1004, 118, 48, 16)
    place(replayButton, 188, 1004, 160, 48, 16)
    place(densityButton, 364, 1004, 220, 48, 16)
    place(laneButton, 600, 1004, 168, 48, 16)
    place(noteLabel, 806, 1014, 1060, 34, 16)
    for _, button in ipairs({ pauseButton, replayButton, densityButton, laneButton }) do
        button:SetStyle({ backgroundColor = { 73, 55, 35, 255 }, hoverBackgroundColor = { 100, 76, 44, 255 },
            pressedBackgroundColor = { 48, 37, 25, 255 }, textColor = { 237, 221, 189, 255 },
            borderColor = { 134, 101, 56, 255 }, borderWidth = 1, borderRadius = 4,
            backgroundGradient = false, hoverBackgroundGradient = false, pressedBackgroundGradient = false,
            boxShadow = false, hoverBoxShadow = false, pressedBoxShadow = false })
    end
    noteLabel:SetStyle({ fontColor = { 149, 139, 122, 255 } })
end

local function spawnEvent(index)
    local tick = index % 72
    if tick == 0 then
        for i, item in ipairs(TYPES) do
            Style.add(singleStates[i], singleTargets[i], item.amount, 0, 0, item.meta)
        end
    end
    local burst = tick >= 8 and tick <= 38
    if burst and (dense and tick % 3 == 0 or not dense and tick % 12 == 0) then
        local crit = tick % 9 == 0
        local amount = crit and 438 or 186
        local meta = { channel = "damage", atkType = AD.ATK_SLASH, isCrit = crit, fontSize = 56 }
        Style.add(laneStates[4], laneTargets[4][1], amount, 0, 0, meta)
        oldNumbers[#oldNumbers + 1] = { age = 0, amount = amount, isCrit = crit }
    end
    if tick > 5 and tick < 56 and (dense and tick % 4 == 0 or not dense and tick % 16 == 0) then
        for row = 1, 3 do
            local slot = (math.floor(tick / 4) + row) % 4 + 1
            local styleIndex = (math.floor(tick / 8) + row) % 4 + 1
            local item = TYPES[styleIndex]
            local meta = { channel = item.meta.channel, atkType = item.meta.atkType,
                isCrit = item.meta.isCrit, fontSize = 45 }
            Style.add(laneStates[row], laneTargets[row][slot], item.amount + tick * 3,
                138 + (slot - 1) * 226, 180, meta)
        end
    end
end
local function step(dt)
    for _, state in ipairs(singleStates) do Style.update(state, dt) end
    for _, state in ipairs(laneStates) do Style.update(state, dt) end
    for i = #oldNumbers, 1, -1 do
        local entry = oldNumbers[i]
        entry.age = entry.age + dt
        if entry.age >= 0.7 then table.remove(oldNumbers, i) end
    end
    elapsed = elapsed + dt
    local eventIndex = math.floor(elapsed * 30)
    while lastEvent < eventIndex do lastEvent = lastEvent + 1; spawnEvent(lastEvent) end
end

local function advance(dt)
    if paused or fixedPhase >= 0 then return end
    dt = math.max(0, math.min(dt, 0.1))
    local slices = math.max(1, math.ceil(dt * 120))
    for _ = 1, slices do step(dt / slices) end
end

local function check(condition, message)
    checks = checks + 1
    assert(condition, message)
end

local function checkControls()
    UI.Layout()
    for _, button in ipairs({ pauseButton, replayButton, densityButton, laneButton }) do
        local bounds = button:GetAbsoluteLayoutForHitTest()
        check(bounds.w > 0 and bounds.h > 0 and button:HitTest(bounds.x + bounds.w / 2, bounds.y + bounds.h / 2),
            "真实UI按钮布局及中心命中")
    end
    resetPreview(); step(0.3)
    local before, ft = elapsed, laneStates[4].entries[1]
    local age = ft.age
    pauseButton:OnClick(nil); advance(0.1)
    check(paused and elapsed == before and ft.age == age, "暂停回调冻结整条样片时间轴")
    pauseButton:OnClick(nil); advance(0.1)
    check(not paused and elapsed > before and ft.age > age, "继续回调恢复时间轴")
    replayButton:OnClick(nil)
    check(elapsed == 0 and lastEvent == -1 and #oldNumbers == 0, "重播回调清新旧模拟")
    for _, state in ipairs(laneStates) do check(#state.entries == 0 and next(state.index) == nil, "重播清战线索引") end
    densityButton:OnClick(nil); check(not dense, "密集按钮关闭")
    densityButton:OnClick(nil); check(dense, "密集按钮恢复")
    laneButton:OnClick(nil); check(expandedLanes and not previewLabels[1].widget.props.visible, "放大按钮切换展示")
    laneButton:OnClick(nil); check(not expandedLanes and previewLabels[1].widget.props.visible, "返回按钮恢复展示")
    resetPreview()
    print("[FloatPreview] CONTROLS PASS checks=" .. checks .. "，真实控件布局/回调，非设备输入验收")
end

function Start()
    for _, arg in ipairs(GetArguments()) do
        local phase = arg:match("^%-float%-phase=([%d.]+)$")
        if phase then fixedPhase = tonumber(phase) or -1 end
        if arg == "-float-selftest" then selfTest = true end
        if arg == "-float-lanes" then expandedLanes = true end
    end
    vg = assert(nvgCreate(1), "飘字样片 NanoVG 初始化失败")
    assert(nvgCreateFont(vg, font, "Fonts/NotoSansCJKkr-Bold.otf") >= 0, "飘字样片字体加载失败")
    initContent(); initUI(); layoutUI()
    if selfTest then checkControls() end
    for _, item in ipairs(previewLabels) do item.widget:SetVisible(not expandedLanes) end
    laneButton:SetText(expandedLanes and "返回对比" or "三行放大")
    -- 固定截图只冻结四类型字龄；下方用同一时间轴模拟新旧命中和到期。
    if fixedPhase >= 0 then
        for _ = 1, 120 do step(1 / 120) end
        for i, item in ipairs(TYPES) do
            Style.reset(singleStates[i])
            Style.add(singleStates[i], singleTargets[i], item.amount, 0, 0, item.meta)
            Style.update(singleStates[i], fixedPhase)
        end
        print("[FloatPreview] 固定字龄=" .. fixedPhase .. "，下方新旧共享模拟时刻=" .. elapsed)
    end
    input.mouseMode = MM_ABSOLUTE
    SubscribeToEvent("Update", "HandleFloatPreviewUpdate")
    SubscribeToEvent(vg, "NanoVGRender", "HandleFloatPreviewRender")
    print("[FloatPreview] READY 克制重击，四类型/新旧节奏/三行模拟，固定相位=" .. fixedPhase)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleFloatPreviewUpdate(eventType, eventData)
    advance(eventData:GetFloat("TimeStep"))
end

local function targetCard(ctx, x, y, width, height, enemy)
    rect(ctx, x, y, width, height, enemy and { 44, 32, 29 } or { 31, 39, 35 }, 5)
    nvgBeginPath(ctx); nvgRoundedRect(ctx, x + 4, y + 4, width - 8, height - 8, 3)
    nvgStrokeColor(ctx, rgba(103, 86, 62, 160)); nvgStrokeWidth(ctx, 1); nvgStroke(ctx)
    rect(ctx, x + 10, y + height - 16, width - 20, 4, { 17, 18, 16 }, 1)
    rect(ctx, x + 10, y + height - 16, (width - 20) * 0.67, 4, enemy and { 132, 56, 48 } or { 82, 117, 89 }, 1)
    line(ctx, x + width * 0.5, y + 18, x + width * 0.5, y + height - 29, { 83, 76, 61, 150 }, 2)
    line(ctx, x + width * 0.3, y + 30, x + width * 0.7, y + 30, { 83, 76, 61, 150 }, 2)
end

local function drawSingles(ctx)
    for i, state in ipairs(singleStates) do
        local x = 44 + (i - 1) * 466
        rect(ctx, x, 163, 440, 275, { 29, 25, 22 })
        line(ctx, x + 20, 256, x + 420, 256, { 67, 55, 40 }, 1)
        nvgSave(ctx); nvgTranslate(ctx, x + 220, 340)
        for _, ft in ipairs(state.entries) do Style.draw(ctx, ft, font, { x = -204, y = -76, w = 408, h = 150 }) end
        nvgRestore(ctx)
    end
end
local function drawComparison(ctx)
    rect(ctx, 44, 522, 500, 408, { 26, 23, 20 })
    rect(ctx, 558, 522, 500, 408, { 29, 25, 22 })
    for _, x in ipairs({ 294, 808 }) do targetCard(ctx, x - 55, 760, 110, 132, true) end
    nvgSave(ctx); nvgIntersectScissor(ctx, 60, 575, 468, 340)
    for i, ft in ipairs(oldNumbers) do
        local t = ft.age / 0.7
        local x, y = 294 + ((i % 5) - 2) * t * 30, 753 - t * 170
        local size = (ft.isCrit and 112 or 56) * (1 - t * 0.75)
        nvgFontFace(ctx, font); nvgFontSize(ctx, size)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, rgba(18, 14, 12)); nvgText(ctx, x + 2, y + 2, NumberUtil.format(ft.amount))
        local a = math.floor(255 * math.min(1, (1 - t) * 4))
        nvgFillColor(ctx, ft.isCrit and rgba(255, 90, 82, a) or rgba(238, 229, 206, a))
        nvgText(ctx, x, y, NumberUtil.format(ft.amount))
    end
    nvgRestore(ctx)
    nvgSave(ctx); nvgTranslate(ctx, 808, 688)
    for _, ft in ipairs(laneStates[4].entries) do Style.draw(ctx, ft, font, { x = -224, y = -148, w = 448, h = 330 }) end
    nvgRestore(ctx)
end
local function drawLanes(ctx)
    for row = 1, 3 do
        local x, y, scale = 1120, 533 + (row - 1) * 134, 0.36
        local panelW, panelH = 760, 130
        if expandedLanes then
            x, y, scale = 294, 174 + (row - 1) * 266, 0.7
            panelW, panelH = 1332, 256
        end
        rect(ctx, x, y, panelW, panelH, { 27, 24, 21 })
        nvgSave(ctx); nvgTranslate(ctx, x + (panelW - 948 * scale) * 0.5, y); nvgScale(ctx, scale, scale)
        nvgIntersectScissor(ctx, 0, 0, 948, 360)
        for slot = 1, 4 do
            targetCard(ctx, 93 + (slot - 1) * 226, 148, 92, 150, slot > 2)
        end
        for _, ft in ipairs(laneStates[row].entries) do Style.draw(ctx, ft, font, { x = 4, y = 4, w = 940, h = 352 }) end
        nvgRestore(ctx)
    end
end

function HandleFloatPreviewRender()
    if not vg then return end
    layoutUI()
    local dpr = graphics:GetDPR()
    local w, h = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    local scale = math.min(w / DESIGN_W, h / DESIGN_H)
    nvgBeginFrame(vg, w, h, dpr)
    rect(vg, 0, 0, w, h, { 17, 15, 13 }, 0)
    nvgSave(vg)
    nvgTranslate(vg, (w - DESIGN_W * scale) * 0.5, (h - DESIGN_H * scale) * 0.5)
    nvgScale(vg, scale, scale)
    line(vg, 54, 143, 1866, 143, { 106, 81, 48 }, 2)
    if not expandedLanes then drawSingles(vg); drawComparison(vg) end
    drawLanes(vg)
    line(vg, 54, 988, 1866, 988, { 67, 55, 40 }, 1)
    nvgRestore(vg); nvgEndFrame(vg)
    frames = frames + 1
    if frames == 1 then print("[FloatPreview] FIRST_RENDER，字形与属性徽记已绘制") end
end

function Stop()
    for _, state in ipairs(singleStates) do Style.reset(state) end
    for _, state in ipairs(laneStates) do Style.reset(state) end
    UI.Shutdown()
    if vg then nvgDelete(vg); vg = nil end
    print("[FloatPreview] STOP，绘制帧=" .. frames .. "，所有样片目标引用已释放")
end
