-- 配装下部回归：纯 NanoVG 绘图探针，不依赖字体/贴图或存档。
function Start()
    local originalRequire, originalTime = require, time
    local savedGlobals, textCalls, paths, rects, scissorCalls, imageCalls = {}, {}, {}, {}, {}, {}
    local function run()
    local color, fillColor, strokeColor, path = {}, {}, {}, {}
    local fontSize, strokeWidth = 0, 0
    local count = 0
    local function check(value, message)
        assert(value, message)
        count = count + 1
    end
    local function hook(name, fn)
        if savedGlobals[name] == nil then savedGlobals[name] = _G[name] end
        _G[name] = fn
    end
    local function noop() end
    for _, name in ipairs({ "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgFill", "nvgStroke",
        "nvgStrokeColor", "nvgStrokeWidth", "nvgFillPaint", "nvgRoundedRect", "nvgCircle",
        "nvgSave", "nvgRestore", "nvgIntersectScissor", "nvgClosePath" }) do hook(name, noop) end
    hook("nvgFontSize", function(vg, size) fontSize = size end)
    hook("nvgRect", noop)
    hook("nvgRoundedRect", function(vg, x, y, w, h, radius)
        rects[#rects + 1] = { x = x, y = y, w = w, h = h, radius = radius }
    end)
    hook("nvgIntersectScissor", function(vg, x, y, w, h)
        scissorCalls[#scissorCalls + 1] = { x = x, y = y, w = w, h = h }
    end)
    hook("nvgImagePattern", function(vg, x, y, w, h, angle, image)
        imageCalls[#imageCalls + 1] = { x = x, y = y, w = w, h = h, image = image }
        return {}
    end)
    local nativeRGBA = nvgRGBA
    hook("nvgRGBA", function(r, g, b, a)
        color = { r, g, b, a }
        return nativeRGBA(r, g, b, a)
    end)
    hook("nvgFillColor", function() fillColor = color end)
    hook("nvgStrokeColor", function() strokeColor = color end)
    hook("nvgStrokeWidth", function(vg, width) strokeWidth = width end)
    hook("nvgFill", function() path.fill = fillColor end)
    hook("nvgStroke", function() path.stroke = strokeColor; path.strokeWidth = strokeWidth end)
    hook("nvgClosePath", function() path.closed = true end)
    hook("nvgTextBounds", function(vg, x, y, value) return utf8.len(tostring(value)) * 16 end)
    hook("nvgText", function(vg, x, y, value)
        textCalls[#textCalls + 1] = { x = x, y = y, value = tostring(value), color = color, fontSize = fontSize }
    end)
    hook("nvgBeginPath", function() path = {}; paths[#paths + 1] = path end)
    hook("nvgMoveTo", function(vg, x, y) path[#path + 1] = { x, y } end)
    hook("nvgLineTo", function(vg, x, y) path[#path + 1] = { x, y } end)
    hook("nvgLinearGradient", function() return {} end)
    time = { elapsedTime = 20 }

    local rows = {}
    for i = 1, 12 do
        rows[i] = { key = "attr" .. i, name = "属性" .. i, value = tostring(i), currentValue = i,
            delta = i == 1 and 5 or (i == 2 and -3 or 0), deltaText = i == 1 and "+5" or "-3",
            beneficial = i == 1, desc = "属性说明" .. i }
    end
    local current = { left = {}, right = {}, stats = { str = 10, agi = 8, vit = 6, spi = 4, luk = 3, int = 2 } }
    local preview = { left = {}, right = {}, stats = { str = 20, agi = 5, vit = 6, spi = 4, luk = 3, int = 2 } }
    local selection = nil
    local buildCount, requestedSeq, requestedSlot = 0, nil, nil
    local summaries = {
        { setId = "A", name = "旧套装", count = 6, twoActive = true, fourActive = true, sixActive = true },
        { setId = "B", name = "第二套装", count = 1 },
    }
    local previewSummaries = {
        { setId = "A", name = "旧套装", count = 1 },
        { setId = "C", name = "新套装", count = 6, twoActive = true, fourActive = true, sixActive = true },
    }
    local description = string.rep("完整套装效果不会截断，", 28)
    local heroes = { roster = { [1] = { level = 10 } } }
    local equipment = { inventory = { ["7"] = { enhanceLevel = 1 } }, equipped = {} }
    local AD = { META = {}, formatAttrDisplayValue = function(key, value) return tostring(value) end }
    local cfg = { name = "测试套装", desc2 = description, desc4 = description, desc6 = description }
    local mods = {
        ["systems.AttributeDef"] = AD,
        ["config.EquipmentSetConfig"] = { get = function() return cfg end },
        -- 本测试只验配装布局，套装图标由独立 set_icon_badge_test 覆盖。
        ["ui.widget.EquipmentSetIcon"] = { draw = function() return false end },
        ["core.DrawUtil"] = { drawTextStroke = function(vg, x, y, value, size, align, r, g, b)
            nvgFontSize(vg, size)
            nvgFillColor(vg, nvgRGBA(r or 255, g or 255, b or 255, 255))
            nvgText(vg, x, y, value)
        end },
        ["ui.character.detail.CharacterDetailAttrs"] = { STAT_LAYOUT = {}, displayOrderIndex = function() return {} end },
        ["core.PlayerStore"] = { Get = function(key)
            if key == "heroes" then return heroes end
            if key == "equipment" then return equipment end
            return nil
        end },
        ["runtime.ClientDispatcher"] = { get = function() return nil end },
        ["config.HeroConfig"] = {},
        ["systems.EquipmentSystem"] = {},
        ["systems.EquipmentSetSystem"] = {},
        ["ui.character.equip.EquipmentDetail"] = { getSelection = function() return selection end },
        ["ui.character.detail.EquipmentPreview"] = {
            build = function(heroId, level, seq, slot)
                buildCount = buildCount + 1
                requestedSeq, requestedSlot = seq, slot
                return { current = current, preview = seq and preview or nil, rows = rows,
                    currentSets = summaries, previewSets = previewSummaries,
                    candidate = seq and { seq = seq, slot = slot, name = "测试候选" } or nil }
            end,
        },
    }
    require = function(name) return mods[name] or originalRequire(name) end
    -- 差集几何使用真实纯模块，只有数据/资源依赖被 mock。
    local RadarDiff = originalRequire("ui.character.detail.CharacterRadarDiff")
    local Stats = originalRequire("ui.character.detail.CharacterEquipStats")
    mods["ui.character.detail.CharacterEquipStats"] = Stats
    local Shared = originalRequire("ui.character.detail.CharacterAttributeView")
    for _, name in ipairs({ "config.HeroAssetUtil", "config.ClassConfig", "config.ExpTable",
        "ui.character.equip.EquipmentBag", "config.EquipmentConfig", "ui.widget.HeroFrame",
        "ui.character.hero.AwakeningPanel", "systems.ButtonFeedback", "core.DarkIcon",
        "systems.ExtraTalentSystem", "core.I18n" }) do mods[name] = {} end
    mods["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 } }
    mods["ui.widget.KeywordText"] = { new = function() return {} end }
    local Draw = originalRequire("ui.character.detail.CharacterDetailDraw")
    local Panel = originalRequire("ui.character.detail.CharacterDetailEquip")
    local attrs, radar, sets = Stats.LAYOUT.attrs, Stats.LAYOUT.radar, Stats.LAYOUT.sets
    local ax, ay = attrs.x + 100, attrs.y + 100
    local sx, sy = sets.x + 100, sets.y + 100
    local sharedPaths = {}
    hook("nvgCreateImage", function(vg, filename)
        sharedPaths[#sharedPaths + 1] = filename
        return #sharedPaths
    end)
    Draw.initImages({})

    local function rendered(value)
        for _, call in ipairs(textCalls) do if call.value == value then return call end end
        return nil
    end
    local function clearDraw() textCalls, paths, rects, scissorCalls, imageCalls = {}, {}, {}, {}, {} end
    local function draw() clearDraw(); Panel.draw({}, 1, { equipSlot = requestedSlot }) end
    local function near(a, b) return math.abs(a - b) < 0.000001 end
    local function sameColor(actual, r, g, b, a)
        return actual and actual[1] == r and actual[2] == g and actual[3] == b
            and (a == nil or actual[4] == a)
    end
    local function deltaSign(actual)
        if sameColor(actual, 115, 218, 135) then return 1 end
        if sameColor(actual, 235, 110, 100) then return -1 end
        return 0
    end
    local function radarPaths()
        local polygons, regions, edges = {}, {}, {}
        for _, points in ipairs(paths) do
            if points.closed and #points >= 3 and points.fill then
                polygons[#polygons + 1] = points
                if deltaSign(points.fill) ~= 0 then regions[#regions + 1] = points end
            end
            if #points == 2 and deltaSign(points.stroke) ~= 0 then edges[#edges + 1] = points end
        end
        return polygons, regions, edges
    end
    local function sameVertices(actual, expected)
        if #actual ~= #expected then return false end
        for i, point in ipairs(expected) do
            if not near(actual[i][1], point.x) or not near(actual[i][2], point.y) then return false end
        end
        return true
    end
    local function matchesComparison(regions, edges, comparison)
        if #regions ~= #comparison.regions or #edges ~= #comparison.edges then return false end
        for i, region in ipairs(comparison.regions) do
            if not sameVertices(regions[i], region.vertices)
                or deltaSign(regions[i].fill) ~= region.sign or regions[i].fill[4] ~= 75 then return false end
        end
        for i, edge in ipairs(comparison.edges) do
            if not sameVertices(edges[i], { edge.from, edge.to })
                or deltaSign(edges[i].stroke) ~= edge.sign or edges[i].stroke[4] ~= 255
                or edges[i].strokeWidth ~= 3 then return false end
        end
        return true
    end
    local function containsPoint(points, x, y)
        local inside = false
        for i = 1, #points do
            local a, b = points[i], points[i % #points + 1]
            if (a[2] > y) ~= (b[2] > y)
                and x < a[1] + (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) then
                inside = not inside
            end
        end
        return inside
    end

    check(Draw.drawAttributeRows == Stats.drawAttributeRows and Stats.drawAttributeRows == Shared.drawAttributeRows,
        "两页调用同一个drawAttributeRows而非复制属性行")
    check(Draw.ATTRIBUTE_STYLE == Stats.ATTRIBUTE_STYLE and Shared.STYLE.rowH == 60
        and Shared.STYLE.rowStep == 69, "共用属性行风格对象60高69步长")
    check(Draw.ATTR_FIRST_ROW_Y == Shared.ATTRIBUTE_LAYOUT.firstY
        and Draw.ATTR_CLIP_TOP == Shared.ATTRIBUTE_LAYOUT.y
        and Draw.ATTR_CLIP_HEIGHT == Shared.ATTRIBUTE_LAYOUT.h,
        "属性页M.ATTR原输入坐标完全不变")
    check(attrs.y == 1050 and attrs.h == math.floor(552 * 1.3 + 0.5) and attrs.h == 718,
        "属性区原552高度放大30%取整718且顶边1050")
    check(radar.y == attrs.y and radar.h == attrs.h and radar.cy == 1403,
        "雷达区同步718高度且中心1403")
    check(sets.y == 1866 and sets.h == 348 and Stats.LAYOUT.setTitleY == 1818
        and attrs.y + attrs.h < Stats.LAYOUT.setTitleY and Stats.LAYOUT.setTitleY < sets.y,
        "套装区缩至348高从1866开始且标题1818不侵入属性区")
    check(radar.r == Stats.LEGACY.HEX_R and radar.labelR == Stats.LEGACY.HEX_LABEL_R
        and radar.r == 175 and radar.labelR == 230, "共用175雷达半径和230标签半径")
    clearDraw(); Stats.drawBackground({})
    check(#imageCalls == 1 and sharedPaths[imageCalls[1].image]:find("UI_JSJM_0.png", 1, true)
        and imageCalls[1].y == Stats.LAYOUT.panel.y and imageCalls[1].w == 1080
        and imageCalls[1].h == 1579, "配装复用原底板句柄1080x1579等比平移至890")
    clearDraw(); Stats.drawHeader({}, nil, nil)
    local dividerImages = 0
    for _, call in ipairs(imageCalls) do
        if sharedPaths[call.image]:find("UI_JSXQ_FGXJ.png", 1, true) then dividerImages = dividerImages + 1 end
    end
    check(dividerImages == 2, "配装标题和套装之间复用属性页同一分隔线句柄")
    local defaultStatus = false
    for _, call in ipairs(textCalls) do
        if call.value:find("当前已穿戴属性", 1, true) then defaultStatus = true end
    end
    check(not defaultStatus, "无候选header不画当前已穿戴属性冗余文本")
    clearDraw(); Stats.drawHeader({}, { name = "测试候选" }, "职业不符")
    check(rendered("试穿失败：职业不符") ~= nil, "有候选失败仍显示错误提示")
    clearDraw(); Stats.drawHeader({}, nil, "暂不可用")
    check(rendered("预览提示：暂不可用") ~= nil, "无候选错误仍显示预览提示")
    local sample = { { key = "a", name = "同样属性", value = "42" } }
    clearDraw(); Draw.drawAttributeRows({}, sample, 0, Shared.ATTRIBUTE_LAYOUT)
    local originalName, originalValue = rendered("同样属性"), rendered("42")
    local originalRow = rects[1]
    clearDraw(); Stats.drawRows({}, sample, 0)
    local equipName, equipValue = rendered("同样属性"), rendered("42")
    check(originalName.x == equipName.x and originalValue.x == equipValue.x
        and originalName.y == originalValue.y and equipName.y == equipValue.y
        and equipName.x == 167 and equipValue.x == 510, "同一行名称左数值右坐标完全复用")
    check(originalValue.fontSize == 35 and equipValue.fontSize == 35
        and equipValue.color[1] == 255 and equipName.color[1] == 0xE8,
        "无delta同35号白数字和E8DCC8名称")
    check(rects[1].w == originalRow.w and rects[1].h == originalRow.h
        and rects[1].radius == originalRow.radius and rects[1].radius == 20,
        "两页440x60圆角20行底完全同款")
    check(scissorCalls[1].x == 40 and scissorCalls[1].w == 500,
        "配装属性clip同属性页x40宽500")
    check(#imageCalls == 1 and sharedPaths[imageCalls[1].image]:find("ICON_XX.png", 1, true),
        "属性行装饰复用ICON_XX句柄")
    local _, hits = Stats.drawRows({}, sample, 0)
    check(Shared.rowAt(hits, ax, attrs.y + 30) == sample[1]
        and Shared.rowAt(hits, ax, attrs.y + Stats.LAYOUT.rowH + 4) == nil,
        "可见行hit匹配60高且行距不出现幽灵hit")
    clearDraw(); Stats.drawRows({}, { { key = "d", name = "同样属性", value = "42", delta = 5 } }, 0)
    local deltaName, deltaValue, deltaLabel = rendered("同样属性"), rendered("42"), rendered("+5.0")
    check(deltaName.x == equipName.x and deltaName.y == equipName.y
        and deltaValue.x == equipValue.x and deltaValue.y == equipValue.y
        and deltaName.fontSize == equipName.fontSize and deltaValue.fontSize == equipValue.fontSize
        and deltaName.fontSize == 35 and deltaValue.fontSize == 35
        and deltaValue.y == attrs.y + Shared.STYLE.rowH * 0.5,
        "delta不移动名称或当前值baseline、不缩原35号内容，与无delta坐标完全一致")
    check(deltaLabel.x == deltaValue.x and deltaLabel.y == deltaValue.y - 35
        and deltaLabel.fontSize == 20 and rects[1].h == Shared.STYLE.rowH,
        "20号delta单独叠在当前数值cy-35上方，原60高属性行不变")
    check(#scissorCalls == 2 and scissorCalls[1].y == attrs.y and scissorCalls[1].h == attrs.h
        and scissorCalls[2].x == attrs.x and scissorCalls[2].w == attrs.w
        and scissorCalls[2].y == attrs.y - 20 and scissorCalls[2].h == attrs.h + 20,
        "delta独立上扩20px裁剪，首行上方差值不被原属性行clip切掉")

    check(math.abs(Stats.radarScale(current.stats, preview.stats) - 20 / 0.82) < 0.000001, "新旧几何共用最大值尺度")
    check(Stats.radarScale({}, {}) == 8, "无候选与属性页同样采用max(8,peak/.82)尺度")
    check(Stats.LEGACY.HEX_CY == 1535.5 and Stats.LEGACY.HEX_LABEL_R == 230, "属性页原雷达布局不变")
    local layout = Stats.LAYOUT.radar
    local mixed = RadarDiff.compare(current.stats, preview.stats, layout.cx, layout.cy,
        layout.r, Stats.radarScale(current.stats, preview.stats))
    clearDraw(); Stats.drawRadar({}, current.stats, preview.stats)
    local polygons, regions, edges = radarPaths()
    check(#polygons == 1 + #mixed.regions and #polygons[1] == 6
        and sameColor(polygons[1].fill, 0xC4, 0x8A, 0x3A, 70)
        and sameColor(polygons[1].stroke, 0xE8, 0xDC, 0xC8, 200),
        "仅一份淡金当前基图加差集区域，不再整块绘制cyan候选六边形")
    check(sameVertices(polygons[1], mixed.oldVertices)
        and near((layout.cy - mixed.newVertices[1].y) / (layout.cy - polygons[1][1][2]), 2),
        "同一尺度旧基图保持力量10且新顶点20为2倍半径")
    check(matchesComparison(regions, edges, mixed) and #edges == 4 and #regions == 4,
        "混合增减只画真实移动边，交叉扇区拆分绿红两段和差集三角形")
    local greenEdges, redEdges, triangles, sharedCrossing = 0, 0, 0, false
    for _, edge in ipairs(edges) do
        if deltaSign(edge.stroke) > 0 then greenEdges = greenEdges + 1 else redEdges = redEdges + 1 end
    end
    for _, region in ipairs(regions) do if #region == 3 then triangles = triangles + 1 end end
    sharedCrossing = near(edges[1][2][1], edges[2][1][1]) and near(edges[1][2][2], edges[2][1][2])
    check(greenEdges == 2 and redEdges == 2 and triangles == 2 and sharedCrossing,
        "力量增敏捷减的相邻边在交点连接，两种颜色各两段且交叉区分两三角")
    local commonX, commonY = layout.cx, layout.cy - 1
    local commonUntinted = containsPoint(polygons[1], commonX, commonY)
    for _, region in ipairs(regions) do
        if containsPoint(region, commonX, commonY) then commonUntinted = false end
    end
    check(commonUntinted, "新旧共有中心内区只保留淡金底，不重复涂绿红")
    check(rendered("+10") and rendered("-3"), "六围标签显示正负numeric delta")
    check(rendered("力量").x == layout.cx and rendered("力量").y == layout.cy - layout.labelR - 24
        and rendered("力量").fontSize == 26 and rendered("10").x == layout.cx
        and rendered("10").y == layout.cy - layout.labelR + 16 and rendered("10").fontSize == 34
        and rendered("+10").y == layout.cy - layout.labelR - 58,
        "六围差值在ly-58，不移动原名称ly-24和34号当前值ly+16")
    check(#scissorCalls == 0, "雷达不另设474宽scissor裁掉左右标签")

    clearDraw(); Stats.drawRadar({}, current.stats, current.stats)
    polygons, regions, edges = radarPaths()
    check(#polygons == 1 and #regions == 0 and #edges == 0
        and not rendered("+0") and not rendered("+0.0"), "未改变候选没有额外边、差集或零delta")
    local singleCurrent = { str = 10, agi = 10, vit = 10, spi = 10, luk = 10, int = 10 }
    local singlePreview = { str = 20, agi = 10, vit = 10, spi = 10, luk = 10, int = 10 }
    local single = RadarDiff.compare(singleCurrent, singlePreview, layout.cx, layout.cy,
        layout.r, Stats.radarScale(singleCurrent, singlePreview))
    clearDraw(); Stats.drawRadar({}, singleCurrent, singlePreview)
    polygons, regions, edges = radarPaths()
    check(#polygons == 3 and #regions == 2 and #regions[1] == 4 and #regions[2] == 4
        and matchesComparison(regions, edges, single), "只增力量是old基图加两差集quad而非候选整poly")
    check(#edges == 2 and deltaSign(edges[1].stroke) == 1 and deltaSign(edges[2].stroke) == 1
        and single.edges[1].sector == 1 and single.edges[2].sector == 6,
        "只增力量恰好两条绿色邻边，不重画其余四条未变化边")
    commonUntinted = containsPoint(polygons[1], commonX, commonY)
    for _, region in ipairs(regions) do
        if containsPoint(region, commonX, commonY) then commonUntinted = false end
    end
    check(commonUntinted, "只增力量的共有基图内区不涂差集颜色")

    clearDraw(); Stats.drawLegacy({}, current.stats)
    local legacyPolygons = radarPaths()
    local legacyOutline = legacyPolygons[1]
    clearDraw(); Stats.drawRadar({}, current.stats, nil)
    local equipPolygons, noPreviewRegions, noPreviewEdges = radarPaths()
    check(#equipPolygons == 1 and #noPreviewRegions == 0 and #noPreviewEdges == 0
        and near(Stats.LEGACY.HEX_CY - legacyOutline[1][2],
            radar.cy - equipPolygons[1][1][2]), "无候选普通值轮廓尺度与原属性页完全一致")
    clearDraw(); Stats.drawRadar({}, { str = 38.745624, agi = 8 }, nil)
    check(rendered("38") and not rendered("38.745624"), "雷达只显示整数避免raw六围长小数越出画布")
    -- legacy基图允许0.08视觉下限；纯差集比较允许0，低值UI不锁死两者半径相等。
    clearDraw(); Stats.drawRadar({}, { str = 0.04, agi = 1 }, { str = 0.05, agi = 1 })
    local tinyDelta = rendered("+0.01")
    check(tinyDelta and not rendered("+0.0") and rendered("0").fontSize == 34
        and tinyDelta.y == layout.cy - layout.labelR - 58,
        "低值使用raw差值+0.01且保留原整数当前值字号/坐标，不预言visualfloor几何")

    local union = Stats.unionSets(summaries, previewSummaries)
    check(#union == 3, "不同套装取并集而非固定数量截断")
    clearDraw(); Stats.drawSets({}, union, 0, true)
    local invalid = false
    for _, call in ipairs(textCalls) do
        if call.value:find("失效", 1, true) and math.abs(call.color[1] - 235) < 1 then invalid = true end
    end
    check(invalid, "原激活后失效的套装效果标红")
    clearDraw(); Stats.drawRows({}, rows, 0)
    check(math.abs(rendered("+5").color[2] - 218) < 1 and math.abs(rendered("-3").color[1] - 235) < 1, "属性变化绿增红减")
    clearDraw(); Stats.drawRows({}, { { key = "new", name = "新属性", value = "0", currentValue = 0,
        previewValue = 90, delta = 90 } }, 0)
    check(rendered("0") and not rendered("90"), "新预览属性显示current0而不是preview90")
    clearDraw(); Stats.drawRows({}, {
        { key = "_effCritRate", name = "暴击率", value = "7.6%", currentValue = 7.6 },
        { key = "atkInterval", name = "攻击间隔", value = "0.83s", currentValue = 0.83 },
    }, 0)
    check(rendered("7.6%") and rendered("0.83s"), "百分比和攻击秒数保留API原显示格式")

    Panel.reset(1, nil); draw()
    check(requestedSeq == nil and requestedSlot == nil, "无候选只请求current且nil槽不回退主手")
    check(rendered("当前已穿戴属性 · 选中或悬停装备以试穿") == nil,
        "无候选面板不再显示当前已穿戴属性提示")
    local firstRowY = attrs.y + Shared.STYLE.rowH * 0.5
    check(Panel.handleHover(ax, firstRowY, 1), "当前可见属性支持hover说明而非旧装备hover")
    time.elapsedTime = 20.31
    Panel.handleHover(ax, firstRowY, 1)
    clearDraw(); Panel.drawSetCodex({})
    check(rendered("属性说明1") ~= nil, "同属性key停留0.3秒显示说明")
    Panel.handleHover(ax, firstRowY + Shared.STYLE.rowStep, 1)
    clearDraw(); Panel.drawSetCodex({})
    check(not rendered("属性说明1") and not rendered("属性说明2"), "换属性key立即清旧说明并重启延时")
    time.elapsedTime = 20.62
    Panel.handleHover(ax, firstRowY + Shared.STYLE.rowStep, 1)
    clearDraw(); Panel.drawSetCodex({})
    check(rendered("属性说明2") ~= nil, "新属性key延时完成显示自己的说明")
    Panel.handleHover(-1, -1, 1)
    clearDraw(); Panel.drawSetCodex({})
    check(#textCalls == 0, "离开属性区不遗留hover说明")
    time.elapsedTime = 20
    local previousBuilds = buildCount
    draw(); check(buildCount == previousBuilds, "候选key相同0.2秒内命中缓存")
    Panel.markDirty(); draw(); check(buildCount == previousBuilds + 1, "markDirty立即使缓存失效")
    selection = { seq = 7, slot = "weapon", heroId = 1, owner = "backpack", pinned = true }
    requestedSlot = "offhand"; draw()
    check(requestedSeq == 7 and requestedSlot == "offhand", "显式副手保留weapon候选")
    check(rendered("试穿 · 未穿戴：测试候选") ~= nil, "候选标题明确试穿未穿戴")
    selection.owner = "smith"; draw(); check(requestedSeq == nil, "排除smith选中来源")
    selection.owner = "bag"; requestedSlot = nil; draw(); check(requestedSeq == 7 and requestedSlot == nil, "bag来源与自然槽nil支持")
    selection.owner = "character"; draw(); check(requestedSeq == 7, "character来源候选支持")
    local stableBuilds = buildCount
    time.elapsedTime = 21; draw()
    check(buildCount == stableBuilds, "超0.2秒数据签名不变不重复深拷贝/预览")
    equipment.inventory["7"].enhanceLevel = 2
    time.elapsedTime = 22; draw()
    check(buildCount == stableBuilds + 1, "候选原地升阶变化由签名使缓存失效")

    check(Panel.peekItemAt(ax, ay) == nil and not Panel.isItemDragging(), "旧网格不再有装备peek或dragItem")
    check(Panel.handleRightClick(ax, ay, 1) == false, "旧网格右击不穿装")
    check(Panel.beginSideDrag(70, 750) == false and Panel.handleInput(70, 750, 1, {}) == false, "旧顶部侧栏无不可见热区")
    check(Panel.handleInput(Draw.BTN_TAB_EQUIP_CX, Draw.BTN_TAB_EQUIP_CY, 1, {}) == false, "下部面板不吞配装页签")
    check(Panel.handleInput(ax, ay, 1, {}) == true, "属性区内只管理自身说明")
    check(Panel.containsComparisonPoint(ax, ay) and Panel.containsComparisonPoint(radar.cx, radar.cy)
        and Panel.containsComparisonPoint(sx, sy), "比较命中覆盖attrs/radar/sets")
    check(not Panel.containsComparisonPoint(540, 790)
        and not Panel.containsComparisonPoint(Draw.BTN_TAB_EQUIP_CX, Draw.BTN_TAB_EQUIP_CY), "比较命中排除六槽与页签")
    check(not Panel.onPointerMove(radar.cx, sets.y), "移动始终不进入装备拖拽")

    check(Panel.handleSideScroll(-1000, ax, ay), "属性wheel命中")
    draw(); check(rendered("属性12") ~= nil and not rendered("属性1"), "属性wheel向下钳制到最后行")
    check(Panel.handleSideScroll(1000, ax, ay), "属性wheel向上命中")
    draw(); check(rendered("属性1") ~= nil, "属性wheel上界钳制归零")
    check(Panel.handleDragBegin(ax, ay), "属性drag开始")
    check(Panel.handleDragMove(ax, attrs.y - attrs.h * 10)
        and Panel.handleDragEnd(ax, attrs.y - attrs.h * 10), "属性drag移动结束")
    draw(); check(rendered("属性12") ~= nil, "属性drag下界钳制")
    check(Panel.handleSideScroll(-1000, sx, sy), "套装wheel独立命中")
    draw(); check(rendered("第二套装") ~= nil and rendered("属性12") ~= nil, "滚套装不改变属性scroll且可见最后不同套装")
    check(Panel.handleDragBegin(sx, sy), "套装drag开始")
    Panel.handleDragMove(sx, sets.y + sets.h * 100)
    Panel.handleDragEnd(sx, sets.y + sets.h * 100)
    draw(); check(rendered("旧套装") ~= nil, "套装drag向下拖归零")
    check(not Panel.handleDragBegin(radar.cx, radar.cy), "雷达不是拖装备或滚动区")
    check(Panel.handleSideScroll(-1, radar.cx, radar.cy), "雷达wheel消费但不借用旧scrollTarget")
    check(not Panel.handleSideScroll(-1, Draw.BTN_TAB_EQUIP_CX, Draw.BTN_TAB_EQUIP_CY), "wheel不吞页签")
    Panel.clear(); draw(); check(rendered("属性1") ~= nil, "clear清滚动与候选缓存")

    print("[character_equip_panel_test] ALL PASS: " .. count .. " 个断言")
    end

    local ok, failure = pcall(run)
    require, time = originalRequire, originalTime
    for name, value in pairs(savedGlobals) do _G[name] = value end
    if not ok then print("[character_equip_panel_test] FAIL: " .. tostring(failure)) end
    -- 失败也恢复mock并显式退出，不让断言异常变成挂起/timeout。
    engine:Exit()
end
