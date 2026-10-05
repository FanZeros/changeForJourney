-- 觉醒说明与影画切片回归：正文/关键词锚点保留，真实 Panel.draw 单层框、固定采样与热区。
local engineRequire = require
local mocks = {}
rawset(_G, "require", function(name) return mocks[name] or engineRequire(name) end)
local noop = function() end
local capture = { enabled = false, paths = {}, fills = {}, strokes = {}, paints = {}, labels = {} }
local path = { points = {}, closed = false }
local fill = { kind = "color", color = {} }
local stroke = { color = {}, width = 0 }
local colorArgs = {}
local nativeRGBA = nvgRGBA
local nativeTime = time
local clock = { elapsedTime = 0 }
local hasCG = false
local vg = {}
local assertions = 0
local frames = 0

local function check(condition, message)
    assertions = assertions + 1
    assert(condition, message)
end

-- 保留真实 NVGcolor 返回值，只旁路捕获入参；不把全局 nvgRGBA 的类型改成 table。
rawset(_G, "nvgRGBA", function(r, g, b, a)
    local color = nativeRGBA(r, g, b, a)
    colorArgs[color] = { r, g, b, a }
    return color
end)
rawset(_G, "time", clock)
mocks["systems.ButtonFeedback"] = { begin = function() return false end, finish = noop }
mocks["core.DrawUtil"] = {
    drawTextStroke = function(_, x, y, text)
        if capture.enabled then
            capture.labels[#capture.labels + 1] = { x = x, y = y, text = text }
        end
    end,
    drawImageCentered = noop, drawShardIcon = noop,
    hitTest = function() return false end,
}
-- KeywordText 当前使用的语言/原文绘制出口仍接既有确定性测量 mock。
mocks["core.I18n"] = {
    lookup = function(text) return text end,
    get = function() return "zh-CN" end,
    displayText = function(...) return nvgText(...) end,
    displayBounds = function(...) return nvgTextBounds(...) end,
}
for _, name in ipairs({ "nvgFontFace", "nvgTextAlign", "nvgSave", "nvgRestore" }) do
    rawset(_G, name, noop)
end
rawset(_G, "nvgBeginPath", function()
    path = { points = {}, closed = false }
    if capture.enabled then capture.paths[#capture.paths + 1] = path end
end)
local function addPoint(_, x, y)
    path.points[#path.points + 1] = { x, y }
end
rawset(_G, "nvgMoveTo", addPoint)
rawset(_G, "nvgLineTo", addPoint)
rawset(_G, "nvgClosePath", function() path.closed = true end)
rawset(_G, "nvgFillColor", function(_, color)
    fill = { kind = "color", color = colorArgs[color] or {} }
end)
rawset(_G, "nvgFillPaint", function(_, paint)
    fill = { kind = "paint", paint = paint }
end)
rawset(_G, "nvgFill", function()
    if capture.enabled then
        capture.fills[#capture.fills + 1] = { path = path, source = fill }
    end
end)
rawset(_G, "nvgStrokeColor", function(_, color) stroke.color = colorArgs[color] or {} end)
rawset(_G, "nvgStrokeWidth", function(_, width) stroke.width = width end)
rawset(_G, "nvgStroke", function()
    if capture.enabled then
        capture.strokes[#capture.strokes + 1] = { path = path, color = stroke.color, width = stroke.width }
    end
end)
rawset(_G, "nvgCreateImage", function(_, imagePath)
    if imagePath:find("UI_JX_JT.png", 1, true) then return 201 end
    if hasCG and imagePath:find("CG_H", 1, true) then return 501 end
    return -1
end)
rawset(_G, "nvgImageSize", function() return 1800, 2400 end)
local function imagePaint(ox, oy, dw, dh, angle, image, alpha, tint)
    local paint = { ox = ox, oy = oy, dw = dw, dh = dh, angle = angle,
        image = image, alpha = alpha, tint = tint }
    if capture.enabled then capture.paints[#capture.paints + 1] = paint end
    return paint
end
rawset(_G, "nvgImagePattern", function(_, ox, oy, dw, dh, angle, image, alpha)
    return imagePaint(ox, oy, dw, dh, angle, image, alpha, nil)
end)
rawset(_G, "nvgImagePatternTinted", function(_, ox, oy, dw, dh, angle, image, color)
    return imagePaint(ox, oy, dw, dh, angle, image, nil, colorArgs[color])
end)
local fontSize = 36
rawset(_G, "nvgFontSize", function(_, size) fontSize = size end)
rawset(_G, "nvgTextBounds", function(_, _, _, text)
    local width = 0
    for _, cp in utf8.codes(text) do width = width + (cp > 127 and fontSize or fontSize * 0.55) end
    return width
end)
local titles = {}
rawset(_G, "nvgText", function(_, x, y, text) titles[#titles + 1] = { x = x, y = y, text = text } end)

-- 独立写出设计几何，不读取/新增生产 API；捕获每次真实路径以发现 expand 或额外框。
local polygons = {
    { { 36, 300 }, { 372, 300 }, { 420, 1812 }, { 36, 1812 } },
    { { 372, 300 }, { 708, 300 }, { 660, 1812 }, { 420, 1812 } },
    { { 708, 300 }, { 1044, 300 }, { 1044, 1812 }, { 660, 1812 } },
}
local centers = { 204, 540, 876 }
local darkBase = { 8, 10, 18, 235 }
local darkOverlay = { 8, 10, 18, 110 }
local goldOverlay = { 232, 201, 106, 22 }
local normalFrame = { 232, 201, 106, 190 }
local selectedFrame = { 255, 239, 103, 245 }

local function sameColor(actual, expected)
    return actual and actual[1] == expected[1] and actual[2] == expected[2]
        and actual[3] == expected[3] and actual[4] == expected[4]
end

local function checkPath(actual, expected, context)
    check(actual.closed and #actual.points == 4, context .. "应为单一闭合四边形")
    for point = 1, 4 do
        check(actual.points[point][1] == expected[point][1]
            and actual.points[point][2] == expected[point][2], context .. "路径不得向外扩张")
    end
end

local function checkSelection(frame, selected, context)
    check(#frame.strokes == 3, context .. "三片总共只能描边三次，不能叠多层框")
    for i, border in ipairs(frame.strokes) do
        check(border.width == (i == selected and 4 or 2), context .. "选中4px/未选中2px且不呼吸")
        check(sameColor(border.color, i == selected and selectedFrame or normalFrame),
            context .. "选中/未选中金色和透明度保持固定")
    end
end

local function drawFrame(Panel, heroId)
    capture.paths, capture.fills, capture.strokes, capture.paints, capture.labels = {}, {}, {}, {}, {}
    capture.enabled = true
    Panel.draw(vg, heroId)
    capture.enabled = false
    frames = frames + 1
    return { paths = capture.paths, fills = capture.fills, strokes = capture.strokes,
        paints = capture.paints, labels = capture.labels }
end

local function samplingSignature(frame)
    local out = {}
    for _, paint in ipairs(frame.paints) do
        out[#out + 1] = table.concat({ paint.ox, paint.oy, paint.dw, paint.dh, paint.angle,
            paint.image, tostring(paint.alpha), paint.tint and table.concat(paint.tint, ",") or "color" }, ":")
    end
    return table.concat(out, "|")
end

local function checkFrame(frame, count, selected, available, context)
    checkSelection(frame, selected, context)
    local pathsPerSlice = available and 4 or 3
    local fillsPerSlice = available and 3 or 2
    check(#frame.paths == pathsPerSlice * 3, context .. "只允许暗底/CG/罩/单框所需路径")
    check(#frame.fills == fillsPerSlice * 3, context .. "填充层数固定，无图仍保留暗底和状态罩")
    check(#frame.paints == (available and 3 or 0), context .. "三片共用CG或完整缺图回退")
    local overlays, states = {}, {}
    for _, label in ipairs(frame.labels) do
        if label.y == 1782 then states[#states + 1] = label.text end
    end
    check(#states == 3, context .. "必须真实绘制三片状态标签")
    for i = 1, 3 do
        for layer = 1, pathsPerSlice do
            checkPath(frame.paths[(i - 1) * pathsPerSlice + layer], polygons[i], context .. "切片" .. i)
        end
        local firstFill = (i - 1) * fillsPerSlice + 1
        local base = frame.fills[firstFill]
        local overlay = frame.fills[firstFill + fillsPerSlice - 1]
        check(base.source.kind == "color" and sameColor(base.source.color, darkBase),
            context .. "三片基础暗底统一，缺图不能变白底")
        check(overlay.source.kind == "color"
            and sameColor(overlay.source.color, i <= count and goldOverlay or darkOverlay),
            context .. "active金色罩22，next/locked统一暗罩110")
        overlays[i] = overlay.source.color
        local expectedState = i <= count and "已嵌合" or (i == count + 1 and "可嵌合" or "未解锁")
        check(states[i] == expectedState, context .. "夹具必须覆盖真实active/next/locked状态")
        if available then
            local imageFill = frame.fills[firstFill + 1]
            local paint = frame.paints[i]
            check(imageFill.source.kind == "paint" and imageFill.source.paint == paint,
                context .. "真实CG采样必须填充该切片")
            check(paint.ox == -27 and paint.oy == 300 and paint.dw == 1134 and paint.dh == 1512
                and paint.angle == 0 and paint.image == 501, context .. "图片保持完整源图共用居中采样")
            check(i <= count and paint.alpha == 1 and paint.tint == nil
                or i > count and paint.alpha == nil and sameColor(paint.tint, { 168, 168, 168, 255 }),
                context .. "状态仅改变彩/染灰，不改变图片变换")
        end
    end
    for a = 1, 2 do
        for b = a + 1, 3 do
            if (a <= count) == (b <= count) then
                check(sameColor(overlays[a], overlays[b]), context .. "同状态切片罩色完全一致")
            end
            if a ~= selected and b ~= selected then
                check(sameColor(frame.strokes[a].color, frame.strokes[b].color),
                    context .. "不同片编号不得改变未选中金框配色")
            end
        end
    end
    local expectedButton = selected <= count and "已嵌合"
        or (selected == count + 1 and "嵌合" or "需先嵌合前阶")
    local buttonText = ""
    for _, label in ipairs(frame.labels) do
        if label.x == 720 and label.y == 2160 then buttonText = label.text end
    end
    check(buttonText == expectedButton, context .. "只切换查看，不放宽前阶嵌合门禁")
end

local function hotspotProbes()
    local probes = {}
    for _, t in ipairs({ 0, 0.5, 1 }) do
        local y = 300 + 1512 * t
        local seam1, seam2 = 372 + 48 * t, 708 - 48 * t
        for _, probe in ipairs({
            { seam1 - 0.25, y, 1 }, { seam1, y, 2 }, { seam1 + 0.25, y, 2 },
            { seam2 - 0.25, y, 2 }, { seam2, y, 3 }, { seam2 + 0.25, y, 3 },
            { 36, y, 1 }, { 1044, y, 3 }, { 35.75, y, 0 }, { 1044.25, y, 0 },
        }) do probes[#probes + 1] = probe end
    end
    probes[#probes + 1] = { 540, 299.75, 0 }
    probes[#probes + 1] = { 540, 1812.25, 0 }
    return probes
end

function Start()
    local ok, err = pcall(function()
        local Panel = require("ui.character.hero.AwakeningPanel")
        local Config = require("config.AwakeningConfig")
        local KeywordText = require("ui.widget.KeywordText")
        local realDraw = Panel.kwText.draw
        local expectedY = 1963 - 139 * 0.5
        local draws = 0
        local checks = 0
        Panel.kwText.draw = function(self, context, text, x, y, width, size, lineHeight, center)
            check(y == expectedY, "觉醒说明应整体下移33设计像素")
            check(width == 910 and size == 36 and center == 540, "说明宽度字号及居中保持")
            draws = draws + 1
            return realDraw(self, context, text, x, y, width, size, lineHeight, center)
        end
        Panel.setOwnedDataGetter(function() return { shards = 150, awakening = {} } end)
        for _, heroId in ipairs({ 1, 6, 12 }) do
            Panel.reset(heroId)
            Panel.draw(vg, heroId)
            checks = checks + 1
        end
        -- 所有英雄和节点的热区跟随正文锚点；不用单独补输入偏移。
        local helper = KeywordText.new()
        for heroId = 1, 25 do
            for node = 1, Config.NODE_COUNT do
                local text = Config.getNodeEffect(heroId, node)
                if text then
                    helper:draw(vg, text, 85, expectedY, 910, 36, nil, 540)
                    for _, hit in ipairs(helper.hotspots) do
                        check(hit.y1 >= expectedY, "关键词热区必须跟随新正文位置")
                        check(hit.y2 <= 2110, "关键词热区不得覆盖嵌合按钮")
                        checks = checks + 1
                    end
                end
            end
        end
        local nodeTitle = false
        for _, text in ipairs(titles) do
            if text.text:find("初醒", 1, true) and text.y == 1860 then nodeTitle = true end
        end
        check(nodeTitle and Panel.BTN_CY == 2160, "阶段标题与嵌合按钮保持原位")
        check(draws == 3, "必须真实调用觉醒正文绘制")
        check(checks > 3, "原关键词热区回归不得因空mock而失效")

        local ownedData = { shards = 150, awakening = { _awk3Migrated = true } }
        Panel.setOwnedDataGetter(function() return ownedData end)
        local probes = hotspotProbes()
        local selectionTimes = { 0, 0.53, 13 }
        for _, available in ipairs({ false, true }) do
            hasCG = available
            Panel.initImages(vg) -- 使用公开初始化刷新资源缓存；同时打开真实箭头时间分支。
            for count = 0, 3 do
                ownedData.awakening = { _awk3Migrated = true }
                for i = 1, count do ownedData.awakening[i] = true end
                check(Config.countActivated(ownedData.awakening) == count, "夹具按新三阶存档明确覆盖0/1/2/3")
                Panel.reset(1)
                clock.elapsedTime = 0
                local context = "CG=" .. tostring(available) .. " awakening=" .. count
                local resetFrame = drawFrame(Panel, 1)
                checkFrame(resetFrame, count, math.min(count + 1, 3), available, context .. " reset")
                local sampling = samplingSignature(resetFrame)
                -- 所有选择×不同时间：覆盖active/next/locked选中与未选中，禁止呼吸/多层框。
                for _, elapsed in ipairs({ 0, 0.37, math.pi * 0.5, math.pi, 999.25 }) do
                    clock.elapsedTime = elapsed
                    for selected = 1, 3 do
                        check(Panel.handleInput(centers[selected], 1056, 1), context .. "点击切片应被消费")
                        local frame = drawFrame(Panel, 1)
                        local case = context .. " selected=" .. selected .. " time=" .. elapsed
                        checkFrame(frame, count, selected, available, case)
                        check(samplingSignature(frame) == sampling, case .. "切换选择/时间不得改变任何CG采样")
                    end
                end
                -- 分割线/外缘在顶、中、底闭合；同一个点从三种选择和时间进入始终命中同一片。
                for previous = 1, 3 do
                    clock.elapsedTime = selectionTimes[previous]
                    for _, probe in ipairs(probes) do
                        check(Panel.handleInput(centers[previous], 1056, 1), context .. "热区前置选择")
                        local handled = Panel.handleInput(probe[1], probe[2], 1)
                        check(handled == (probe[3] ~= 0), context .. "固定切片内外命中不得随选择扩张")
                        local selected = probe[3] ~= 0 and probe[3] or previous
                        local frame = drawFrame(Panel, 1)
                        checkSelection(frame, selected, context .. "边缘点击")
                        check(samplingSignature(frame) == sampling, context .. "边缘点击不改变CG采样")
                    end
                end
            end
        end
        check(draws == frames + 3, "每个描边/热区样本均须经过真实Panel.draw和正文绘制")
        Panel.kwText.draw = realDraw
        print("[awakening_text_layout_test] ALL PASS assertions=" .. assertions
            .. " checks=" .. checks .. " panelFrames=" .. (frames + 3))
    end)
    rawset(_G, "nvgRGBA", nativeRGBA)
    rawset(_G, "time", nativeTime)
    if not ok then
        log:Write(LOG_ERROR, "[awakening_text_layout_test] FAIL assertions=" .. assertions .. " " .. tostring(err))
    end
    engine:Exit()
end
