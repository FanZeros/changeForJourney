-- 属性页/配装下部回归：真实共享模块 + 纯 NanoVG 绘图探针，不依赖字体/贴图或存档。
function Start()
    local originalRequire, originalTime = require, time
    local savedGlobals, textCalls, paths, rects, scissorCalls, imageCalls = {}, {}, {}, {}, {}, {}
    local count = 0
    local function check(value, message)
        assert(value, message)
        count = count + 1
    end
    local function run()
    local color, fillColor, strokeColor, path = {}, {}, {}, {}
    local fontSize, strokeWidth, textAlign = 0, 0, 0
    local function hook(name, fn)
        -- 用包装表保留原本为nil的全局，重复hook也不能覆盖最初快照。
        if savedGlobals[name] == nil then savedGlobals[name] = { value = _G[name] } end
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
    -- 测量随字号缩放，长雷达数值检查才能验证实际拟合后的边界。
    local function textWidth(value, size) return (utf8.len(tostring(value)) or 0) * 16 * size / 27 end
    hook("nvgTextBounds", function(vg, x, y, value) return textWidth(value, fontSize) end)
    hook("nvgTextAlign", function(vg, align) textAlign = align end)
    hook("nvgText", function(vg, x, y, value)
        textCalls[#textCalls + 1] = { x = x, y = y, value = tostring(value), color = fillColor,
            fontSize = fontSize, align = textAlign, width = textWidth(value, fontSize) }
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
    local bonusRows = { { key = "equipBonus", name = "装备净增益", value = "+5.5", currentValue = 5.5,
        desc = "装备来源说明", delta = 2, deltaText = "+2.0" } }
    local bonuses = { rows = bonusRows, current = { stats = { str = 5.5 } }, preview = { stats = { str = 7.5 } } }
    local buildCount, requestedSeq, requestedSlot, requestedBonuses = 0, nil, nil, false
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
            nvgTextAlign(vg, align)
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
            build = function(heroId, level, seq, slot, options)
                buildCount = buildCount + 1
                requestedSeq, requestedSlot = seq, slot
                requestedBonuses = options and options.includeEquipmentBonuses == true
                return { current = current, preview = seq and preview or nil, rows = rows,
                    equipmentBonuses = requestedBonuses and bonuses or nil,
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
    mods["core.I18n"] = { get = function() return "zh_CN" end, lookup = function(s) return s end, format = string.format }
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
    local function requiredText(value)
        local call = rendered(value)
        check(call ~= nil, "绘图文本存在：" .. value)
        return call or error("绘图文本缺失：" .. value)
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
    check(Draw.ATTRIBUTE_STYLE == Shared.ATTRIBUTE_STYLE
        and Stats.ATTRIBUTE_STYLE == Shared.STYLE and Draw.ATTRIBUTE_STYLE ~= Stats.ATTRIBUTE_STYLE
        and Shared.STYLE.rowH == 60 and Shared.STYLE.rowStep == 69 and Shared.STYLE.fontSize == 35,
        "同绘图API分离独立属性风格与默认60高69步长35号配装风格")
    check(Shared.ATTRIBUTE_STYLE.rowH == 78 and Shared.ATTRIBUTE_STYLE.rowStep == 88
        and Shared.ATTRIBUTE_STYLE.fontSize == 40 and Shared.ATTRIBUTE_STYLE.boxW == 460
        and Shared.ATTRIBUTE_STYLE.boxCX == 300 and Shared.ATTRIBUTE_STYLE.nameX == 150
        and Shared.ATTRIBUTE_STYLE.valueX == 520, "属性页独立78高88步长40号与460宽新坐标")
    check(Draw.rowAt == Shared.rowAt and Stats.rowAt == Shared.rowAt,
        "两页导出同一可见行命中API，不另算固定行高")
    check(Draw.ATTR_FIRST_ROW_Y == Shared.ATTRIBUTE_LAYOUT.firstY
        and Draw.ATTR_CLIP_TOP == Shared.ATTRIBUTE_LAYOUT.y
        and Draw.ATTR_CLIP_HEIGHT == Shared.ATTRIBUTE_LAYOUT.h
        and Shared.ATTRIBUTE_LAYOUT.x == 40 and Shared.ATTRIBUTE_LAYOUT.w == 500
        and Draw.ATTR_FIRST_ROW_Y == 1109 and Draw.ATTR_CLIP_TOP == 1070 and Draw.ATTR_CLIP_HEIGHT == 874,
        "属性页输入坐标同源更新为x40宽500顶1070高874首行1109")
    check(Draw.ATTR_BOX_W == 460 and Draw.ATTR_BOX_H == 78 and Draw.ATTR_COL1_CX == 300
        and Draw.ATTR_ROW_GAP == 10, "属性页导出行尺寸与新风格同步")
    check(attrs.y == 1050 and attrs.h == 718 and Stats.LAYOUT.rowH == 60 and Stats.LAYOUT.rowStep == 69,
        "配装属性区固定718高度顶1050，独立保留60高69步长")
    check(radar.y == attrs.y and radar.h == attrs.h and radar.cy == 1403,
        "雷达区同步718高度且中心1403")
    check(sets.y == 1866 and sets.h == 348 and Stats.LAYOUT.setTitleY == 1818
        and attrs.y + attrs.h < Stats.LAYOUT.setTitleY and Stats.LAYOUT.setTitleY < sets.y,
        "套装区缩至348高从1866开始且标题1818不侵入属性区")
    check(radar.r == Shared.RADAR.r and radar.labelR == Shared.RADAR.labelR
        and radar.r == 175 and radar.labelR == 230
        and Stats.LEGACY.HEX_R == 195 and Stats.LEGACY.HEX_LABEL_R == 238,
        "配装雷达175/230固定，与属性页独立195/238分离")
    clearDraw(); Stats.drawBackground({})
    check(#imageCalls == 1 and sharedPaths[imageCalls[1].image]:find("UI_JSJM_0.png", 1, true)
        and imageCalls[1].y == Stats.LAYOUT.panel.y and imageCalls[1].w == 1080
        and imageCalls[1].h == 1579, "配装复用原底板句柄1080x1579等比平移至890")
    clearDraw(); Stats.drawHeader({}, "character")
    local dividerImages = 0
    for _, call in ipairs(imageCalls) do
        if sharedPaths[call.image]:find("UI_JSXQ_FGXJ.png", 1, true) then dividerImages = dividerImages + 1 end
    end
    check(dividerImages == 2, "配装标题和套装之间复用属性页同一分隔线句柄")
    local setHeader, staleSetHeader = rendered("套装效果"), false
    for _, call in ipairs(textCalls) do
        if call.value:find("套装效果", 1, true) and call.value ~= "套装效果" then staleSetHeader = true end
    end
    check(setHeader and setHeader.x == sets.x + 20 and setHeader.y == Stats.LAYOUT.setTitleY + 4
        and setHeader.fontSize == 31 and not staleSetHeader,
        "套装header仅套装效果，无完整说明等冗余后缀")
    local defaultStatus = false
    for _, call in ipairs(textCalls) do
        if call.value:find("当前已穿戴属性", 1, true) then defaultStatus = true end
    end
    check(not defaultStatus, "无候选header不画当前已穿戴属性冗余文本")
    clearDraw(); Stats.drawHeader({}, "character")
    check(rendered("试穿失败：职业不符") == nil, "配装标题不再绘制试穿失败行")
    clearDraw(); Stats.drawHeader({}, "character")
    check(rendered("预览提示：暂不可用") == nil, "配装标题不再绘制预览提示行")
    local function toggleTriangles()
        local count = 0
        for _, p in ipairs(paths) do
            if #p == 3 and p.closed and p.fill then
                local first = p[1]
                if first[2] == Stats.LAYOUT.titleY and (first[1] == 414 or first[1] == 666) then
                    count = count + 1
                end
            end
        end
        return count
    end
    clearDraw(); Stats.drawHeader({}, "character")
    check(rendered("角色属性") and toggleTriangles() == 2 and not rendered("‹") and not rendered("›"),
        "角色属性标题左右显示实心切换三角，不依赖文字箭头")
    clearDraw(); Stats.drawHeader({}, "equipment")
    check(rendered("装备加成") and toggleTriangles() == 2,
        "装备加成标题左右同样显示实心切换三角")
    local sample = { { key = "a", name = "同样属性", value = "42" } }
    clearDraw(); Draw.drawAttributeRows({}, sample, 0, Shared.ATTRIBUTE_LAYOUT, { style = Draw.ATTRIBUTE_STYLE })
    local originalName, originalValue = requiredText("同样属性"), requiredText("42")
    local originalRow = rects[1]
    clearDraw(); Stats.drawRows({}, sample, 0)
    local equipName, equipValue = requiredText("同样属性"), requiredText("42")
    check(originalName.x == 150 and originalValue.x == 520
        and originalName.y == originalValue.y and originalName.y == 1109
        and equipName.y == equipValue.y and equipName.y == attrs.y + 30
        and equipName.x == 167 and equipValue.x == 510,
        "同API通过opts.style采用属性页新坐标，默认配装名称左数值右坐标不变")
    check(originalName.fontSize == 40 and originalValue.fontSize == 40
        and equipName.fontSize == 35 and equipValue.fontSize == 35
        and sameColor(originalValue.color, 255, 255, 255) and sameColor(equipValue.color, 255, 255, 255)
        and sameColor(originalName.color, 0xE8, 0xDC, 0xC8) and sameColor(equipName.color, 0xE8, 0xDC, 0xC8),
        "属性页独立40号、配装仍35号，白数字/E8DCC8名称配色不变")
    check(originalRow.x == 70 and originalRow.y == 1070 and originalRow.w == 460 and originalRow.h == 78
        and rects[1].x == 90 and rects[1].y == attrs.y and rects[1].w == 440 and rects[1].h == 60
        and rects[1].radius == originalRow.radius and rects[1].radius == 20,
        "属性460x78与配装440x60独立，共用圆角20与绘图实现")
    check(scissorCalls[1].x == 40 and scissorCalls[1].w == 500,
        "配装属性clip同属性页x40宽500")
    check(#imageCalls == 1 and sharedPaths[imageCalls[1].image]:find("ICON_XX.png", 1, true),
        "属性行装饰复用ICON_XX句柄")
    local _, hits = Stats.drawRows({}, sample, 0)
    check(Shared.rowAt(hits, ax, attrs.y + 30) == sample[1]
        and Shared.rowAt(hits, ax, attrs.y + Stats.LAYOUT.rowH + 4) == nil,
        "可见行hit匹配60高且行距不出现幽灵hit")

    -- 同API交替调用：opts.style只控制本次绘制，绝不污染后续默认配装。
    local attributeLayout, attributeStyle = Shared.ATTRIBUTE_LAYOUT, Draw.ATTRIBUTE_STYLE
    clearDraw()
    local attributeMax, attributeHits = Draw.drawAttributeRows({}, rows, 0, attributeLayout,
        { style = attributeStyle })
    check(attributeMax == 172 and #attributeHits == 10 and #rects == 10,
        "属性页12行78高88步长总内容1046、874视口可见10行且scroll上限172")
    check(requiredText("属性1").y == 1109 and requiredText("属性2").y == 1197
        and requiredText("属性10").y == 1901 and not rendered("属性11") and not rendered("属性12"),
        "属性页首行与第10末可见行位置正确、88行距且隐藏后两行")
    check(#scissorCalls == 1 and scissorCalls[1].x == 40 and scissorCalls[1].y == 1070
        and scissorCalls[1].w == 500 and scissorCalls[1].h == 874 and not rendered("+5"),
        "属性页独立874裁剪，默认不显示配装delta")
    local attributeFirst, attributeFirstIndex = Draw.rowAt(attributeHits, ax, 1070)
    local attributeLast, attributeLastIndex = Draw.rowAt(attributeHits, ax, 1939)
    check(attributeFirst == rows[1] and attributeFirstIndex == 1
        and attributeLast == rows[10] and attributeLastIndex == 10
        and Draw.rowAt(attributeHits, ax, 1069) == nil and Draw.rowAt(attributeHits, ax, 1940) == nil,
        "属性页首末可见行准确命中，视口外与末行底边不命中")
    check(Draw.rowAt(attributeHits, ax, 1147) == rows[1]
        and Draw.rowAt(attributeHits, ax, 1148) == nil and Draw.rowAt(attributeHits, ax, 1153) == nil
        and Draw.rowAt(attributeHits, ax, 1158) == rows[2]
        and Draw.rowAt(attributeHits, 39, 1109) == nil and Draw.rowAt(attributeHits, 541, 1109) == nil,
        "属性页78高行与10px间隙半开命中，左右clip外无幽灵热区")
    clearDraw()
    local clampedAttributeMax, lastAttributeHits = Draw.drawAttributeRows({}, rows, 10000, attributeLayout,
        { style = attributeStyle })
    check(clampedAttributeMax == attributeMax and #lastAttributeHits == 10
        and lastAttributeHits[1].index == 3 and lastAttributeHits[1].y == 1074
        and lastAttributeHits[1].h == 78 and lastAttributeHits[#lastAttributeHits].index == 12
        and lastAttributeHits[#lastAttributeHits].y + lastAttributeHits[#lastAttributeHits].h == 1944,
        "属性页过大scroll钳制至末行12贴视口底，首可见行3保留完整78高")
    check(Draw.rowAt(lastAttributeHits, ax, 1070) == nil
        and Draw.rowAt(lastAttributeHits, ax, 1074) == rows[3]
        and Draw.rowAt(lastAttributeHits, ax, 1943) == rows[12]
        and Draw.rowAt(lastAttributeHits, ax, 1944) == nil,
        "属性页滚底首行前留白不命中、末行可见末像素命中但clip底外排除")
    clearDraw()
    local _, partialAttributeHits = Draw.drawAttributeRows({}, rows, 40, attributeLayout,
        { style = attributeStyle })
    check(partialAttributeHits[1].index == 1 and partialAttributeHits[1].y == 1070
        and partialAttributeHits[1].h == 38
        and Draw.rowAt(partialAttributeHits, ax, 1069) == nil
        and Draw.rowAt(partialAttributeHits, ax, 1107) == rows[1]
        and Draw.rowAt(partialAttributeHits, ax, 1108) == nil,
        "属性页中途scroll首行只按实际可见38px命中，不保留被裁切部分")
    clearDraw()
    Draw.drawAttributeRows({}, rows, -100, attributeLayout, { style = attributeStyle })
    check(requiredText("属性1").y == 1109, "属性页负scroll钳制为零")
    clearDraw()
    local equipMax, equipHits = Draw.drawAttributeRows({}, rows, 0, attrs)
    check(equipMax == 101 and #equipHits == 11 and requiredText("属性1").fontSize == 35
        and requiredText("属性2").y - requiredText("属性1").y == 69
        and rects[1].w == 440 and rects[1].h == 60,
        "属性大字号调用后默认API仍为配装35号60高69距，上限101不被污染")
    check(equipHits[1].index == 1 and equipHits[1].y == 1050 and equipHits[1].h == 60
        and equipHits[#equipHits].index == 11 and equipHits[#equipHits].h == 28
        and Stats.rowAt(equipHits, ax, 1767) == rows[11] and Stats.rowAt(equipHits, ax, 1768) == nil,
        "配装原首行完整、末行11只28px可见，clip底不命中")
    check(Stats.rowAt(equipHits, ax, 1109) == rows[1]
        and Stats.rowAt(equipHits, ax, 1110) == nil and Stats.rowAt(equipHits, ax, 1118) == nil
        and Stats.rowAt(equipHits, ax, 1119) == rows[2], "配装原9px间隙仍无幽灵命中")
    clearDraw()
    local _, lastEquipHits = Stats.drawRows({}, rows, 10000)
    check(lastEquipHits[1].index == 2 and lastEquipHits[1].y == 1050 and lastEquipHits[1].h == 28
        and lastEquipHits[#lastEquipHits].index == 12 and lastEquipHits[#lastEquipHits].h == 60
        and Stats.rowAt(lastEquipHits, ax, 1050) == rows[2]
        and Stats.rowAt(lastEquipHits, ax, 1767) == rows[12],
        "配装滚底仍首行2裁剪28px、末行12完整60px，不使用属性页scroll")
    local longValue = "123456789012345678901234567890"
    local longRow = { { key = "long", name = "最长属性名称", value = longValue } }
    for _, mode in ipairs({ { style = attributeStyle, layout = attributeLayout },
        { style = Shared.STYLE, layout = attrs } }) do
        clearDraw()
        Draw.drawAttributeRows({}, longRow, 0, mode.layout, { style = mode.style })
        local longName, longNumber = requiredText("最长属性名称"), requiredText(longValue)
        check(longNumber.fontSize < mode.style.fontSize and longName.fontSize >= mode.style.minFontSize
            and longName.x + longName.width + mode.style.nameValueGap <= longNumber.x - longNumber.width + 1,
            "长数值优先缩数字并保留名称最小字号与分隔，不互相挤压")
        check(longNumber.align == NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE
            and longNumber.x == mode.style.valueX and longNumber.x <= mode.layout.x + mode.layout.w
            and longNumber.x - longNumber.width >= longName.x
            and longName.y == longNumber.y, "两页长数字完整保留，右锚点/基线及clip边界不变")
    end
    check(Shared.STYLE.fontSize == 35 and Shared.STYLE.rowH == 60 and Shared.STYLE.rowStep == 69
        and Stats.LAYOUT.attrs.h == 718 and Shared.ATTRIBUTE_STYLE.fontSize == 40,
        "交替大字号/长数字绘制不修改两页风格对象或配装固定高度")

    clearDraw(); Stats.drawRows({}, { { key = "d", name = "同样属性", value = "42", delta = 5 } }, 0)
    local deltaName, deltaValue, deltaLabel = requiredText("同样属性"), requiredText("42"), requiredText("+5.0")
    check(deltaName.x == equipName.x and deltaName.y == equipName.y
        and deltaValue.x == equipValue.x and deltaValue.y == equipValue.y
        and deltaName.fontSize == equipName.fontSize and deltaValue.fontSize == equipValue.fontSize
        and deltaName.fontSize == 35 and deltaValue.fontSize == 35
        and deltaValue.y == attrs.y + Shared.STYLE.rowH * 0.5,
        "delta不移动名称或当前值baseline、不缩原35号内容，与无delta坐标完全一致")
    check(deltaLabel.x == deltaValue.x and deltaLabel.y == deltaValue.y - 28
        and deltaLabel.fontSize == 20 and rects[1].h == Shared.STYLE.rowH,
        "20号delta下移7px至当前数值cy-28，原60高属性行不变")
    check(#scissorCalls == 2 and scissorCalls[1].y == attrs.y and scissorCalls[1].h == attrs.h
        and scissorCalls[2].x == attrs.x and scissorCalls[2].w == attrs.w
        and scissorCalls[2].y == attrs.y - 20 and scissorCalls[2].h == attrs.h + 20,
        "delta独立上扩20px裁剪，首行上方差值不被原属性行clip切掉")

    check(math.abs(Stats.radarScale(current.stats, preview.stats) - 20 / 0.82) < 0.000001, "新旧几何共用最大值尺度")
    check(Stats.radarScale({}, {}) == 8, "无候选与属性页同样采用max(8,peak/.82)尺度")
    check(Stats.LEGACY.HEX_CX == Shared.ATTRIBUTE_RADAR.cx
        and Stats.LEGACY.HEX_CY == Shared.ATTRIBUTE_RADAR.cy and Stats.LEGACY.HEX_CY == 1507
        and Shared.ATTRIBUTE_RADAR.cx == 800 and Shared.ATTRIBUTE_RADAR.r == 195
        and Shared.ATTRIBUTE_RADAR.labelR == 238 and Draw.HEX_CX == 800 and Draw.HEX_CY == 1507
        and Draw.HEX_LABEL_R == 238, "属性页雷达与导出输入坐标同源独立800/1507/195/238")
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
        and rendered("+10").y == layout.cy - layout.labelR - 51,
        "六围差值下移7px至ly-51，不移动原名称ly-24和34号当前值ly+16")
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
    local legacyName, legacyValue = requiredText("力量"), requiredText("10")
    check(legacyName.x == 800 and legacyName.y == 1507 - 238 - 26 and legacyName.fontSize == 30
        and legacyValue.x == 800 and legacyValue.y == 1507 - 238 + 18 and legacyValue.fontSize == 38,
        "属性页雷达独立30号名称38号数值、ly-26/ly+18基线")
    check(#legacyPolygons == 1 and #legacyOutline == 6 and #scissorCalls == 0,
        "属性页只绘当前六边形，不引入配装预览差集或标签scissor")
    clearDraw(); Stats.drawRadar({}, current.stats, nil)
    local equipPolygons, noPreviewRegions, noPreviewEdges = radarPaths()
    local sameNormalizedOutline = #legacyOutline == #equipPolygons[1]
    for i, point in ipairs(legacyOutline) do
        local equipPoint = equipPolygons[1][i]
        local legacyDX, legacyDY = point[1] - Stats.LEGACY.HEX_CX, point[2] - Stats.LEGACY.HEX_CY
        local equipDX, equipDY = equipPoint[1] - radar.cx, equipPoint[2] - radar.cy
        if not near(math.sqrt(legacyDX * legacyDX + legacyDY * legacyDY) / Stats.LEGACY.HEX_R,
            math.sqrt(equipDX * equipDX + equipDY * equipDY) / radar.r) then sameNormalizedOutline = false end
    end
    check(#equipPolygons == 1 and #noPreviewRegions == 0 and #noPreviewEdges == 0
        and sameNormalizedOutline, "无候选六轴归一化半径与属性页一致，不要求195/175物理半径相等")
    check(requiredText("力量").fontSize == 26 and requiredText("10").fontSize == 34
        and requiredText("10").y == radar.cy - 230 + 16,
        "放大属性雷达调用后配装名称26数值34及原基线不被污染")
    clearDraw(); Stats.drawLegacy({}, { agi = 12345678901234567890, vit = 0.12345678901234567 })
    local legacyRightValues = 0
    local legacyInside = true
    for _, call in ipairs(textCalls) do
        if call.y > 1507 and call.x > 800 and tonumber(call.value) then
            legacyRightValues = legacyRightValues + 1
            if call.fontSize >= 38 or call.x + call.width * 0.5 + 3 > 1080
                or call.x - call.width * 0.5 < 550 then legacyInside = false end
        end
    end
    check(legacyRightValues == 1 and legacyInside, "属性页右下长小数按38号缩放后含描边仍在1080画布内")
    local legacyLongTop = requiredText(tostring(12345678901234567890))
    check(legacyLongTop.fontSize < 38 and legacyLongTop.x + legacyLongTop.width * 0.5 + 3 <= 1080,
        "属性页右上超长数值保持完整文本并按实际标签可用宽缩放")
    clearDraw(); Stats.drawRadar({}, { str = 38.745624, agi = 8 }, nil)
    check(rendered("38") and not rendered("38.745624"), "雷达只显示整数避免raw六围长小数越出画布")
    -- legacy基图允许0.08视觉下限；纯差集比较允许0，低值UI不锁死两者半径相等。
    clearDraw(); Stats.drawRadar({}, { str = 0.04, agi = 1 }, { str = 0.05, agi = 1 })
    local tinyDelta = rendered("+0.01")
    check(tinyDelta and not rendered("+0.0") and rendered("0").fontSize == 34
        and tinyDelta.y == layout.cy - layout.labelR - 51,
        "低值使用raw差值+0.01且保留原整数当前值字号/坐标，不预言visualfloor几何")

    local union = Stats.unionSets(summaries, previewSummaries)
    check(#union == 3, "不同套装取并集而非固定数量截断")
    clearDraw(); Stats.drawSets({}, union, 0, true)
    local invalid = false
    for _, call in ipairs(textCalls) do
        if call.value:find("失效", 1, true) and math.abs(call.color[1] - 235) < 1 then invalid = true end
    end
    check(invalid, "原激活后失效的套装效果标红")
    -- 短描述隔离三档状态文案；随后还原长描述，保留原滚动/完整换行回归。
    local longDescriptions = { cfg.desc2, cfg.desc4, cfg.desc6 }
    cfg.desc2, cfg.desc4, cfg.desc6 = "二件测试效果", "四件测试效果", "六件测试效果"
    local effectDescriptions = { cfg.desc2, cfg.desc4, cfg.desc6 }
    clearDraw(); Stats.drawSets({}, Stats.unionSets({ summaries[2] }, nil), 0, false)
    local hasInactiveText = false
    for _, call in ipairs(textCalls) do
        if call.value:find("未激活", 1, true) then hasInactiveText = true end
    end
    check(not hasInactiveText, "未激活套装不输出未激活文字")
    for i, descriptionText in ipairs(effectDescriptions) do
        local inactive = requiredText(tostring(i * 2) .. "件 · " .. descriptionText)
        check(sameColor(inactive.color, 139, 132, 119, 210)
            and inactive.fontSize == 27, "未激活档位省略状态但保留完整描述与灰色")
    end
    clearDraw(); Stats.drawSets({}, Stats.unionSets({ summaries[1] }, nil), 0, false)
    for i, descriptionText in ipairs(effectDescriptions) do
        local active = requiredText(tostring(i * 2) .. "件 · 激活  " .. descriptionText)
        check(sameColor(active.color, 115, 218, 135, 255), "当前套装已激活档位保留激活文字与绿色")
    end
    clearDraw(); Stats.drawSets({}, Stats.unionSets({ summaries[1] }, { previewSummaries[1] }), 0, true)
    for i, descriptionText in ipairs(effectDescriptions) do
        local lost = requiredText(tostring(i * 2) .. "件 · 失效  " .. descriptionText)
        check(sameColor(lost.color, 235, 110, 100, 255), "试穿使旧激活档位失效时保留失效文字与红色")
    end
    clearDraw(); Stats.drawSets({}, Stats.unionSets(nil, { previewSummaries[2] }), 0, true)
    for i, descriptionText in ipairs(effectDescriptions) do
        local activated = requiredText(tostring(i * 2) .. "件 · 激活  " .. descriptionText)
        check(sameColor(activated.color, 115, 218, 135, 255), "试穿新激活档位仍显示激活文字与绿色")
    end
    clearDraw(); Stats.drawSets({}, Stats.unionSets({ summaries[2] }, { summaries[2] }), 0, true)
    for i, descriptionText in ipairs(effectDescriptions) do
        local inactivePreview = requiredText(tostring(i * 2) .. "件 · " .. descriptionText)
        check(sameColor(inactivePreview.color, 139, 132, 119, 210)
            and not inactivePreview.value:find("未激活", 1, true),
            "试穿前后均未激活档位省略状态且不误标失效红色")
    end
    cfg.desc2, cfg.desc4, cfg.desc6 = longDescriptions[1], longDescriptions[2], longDescriptions[3]
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
    check(rendered("试穿 · 未穿戴：测试候选") == nil, "选中候选保留预览但不绘制试穿提示行")
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

    local toggleX, toggleY = 540, Stats.LAYOUT.titleY
    check(Panel.getAttributeMode() == "character" and not requestedBonuses,
        "初始模式仍为角色总属性且不额外构建装备差分")
    check(Panel.isAttributeTogglePoint(toggleX, toggleY) and Panel.containsComparisonPoint(toggleX, toggleY),
        "标题属于切换与比较保留热区，钉住候选首击不被dismiss吞掉")
    check(Panel.handleInput(toggleX, toggleY, 1, { equipSlot = "offhand" }), "标题单击消费并切换")
    local toggleBuilds = buildCount
    draw()
    check(Panel.getAttributeMode() == "equipment" and requestedBonuses and buildCount == toggleBuilds + 1,
        "切换装备加成触发一次按需重建")
    check(rendered("装备加成") and rendered("装备净增益") and rendered("+5.5") and not rendered("属性1"),
        "装备模式标题/列表/雷达只显示净贡献，不回退角色总属性")
    local cachedBuilds = buildCount
    draw(); check(buildCount == cachedBuilds, "装备模式后续帧继续命中缓存")
    Panel.handleInput(ax, firstRowY, 1, {})
    clearDraw(); Panel.drawSetCodex({})
    check(rendered("装备来源说明"), "装备行说明使用来源口径")
    Panel.handleInput(toggleX, toggleY, 1, {})
    clearDraw(); Panel.drawSetCodex({})
    check(#textCalls == 0 and Panel.getAttributeMode() == "character", "切回角色属性清理旧说明和热区")
    draw(); check(rendered("角色属性") and rendered("属性1") and not requestedBonuses,
        "切回后恢复总属性且滚动归顶")
    Panel.handleInput(toggleX, toggleY, 1, {})
    local oldBonusRows = bonuses.rows
    bonuses.rows = {}
    draw(); check(rendered("暂无装备增益") and not rendered("属性1"), "无增益显示空态，不展示基础数值")
    bonuses.rows = oldBonusRows
    Panel.handleInput(toggleX, toggleY, 1, {})
    draw()
    clearDraw(); Stats.drawRadar({}, {}, nil, true)
    local zeroPolygons = radarPaths()
    local allCentered = true
    for _, point in ipairs(zeroPolygons[1]) do
        if not near(point[1], radar.cx) or not near(point[2], radar.cy) then allCentered = false end
    end
    check(allCentered, "空装六围落中心而不是8%视觉下限虚构增益")
    clearDraw(); Stats.drawRadar({}, { str = 2.8597845, agi = 0.012345 }, nil, true)
    check(rendered("+2.9") and not rendered("+2.859785"), "装备六围正常值保留一位小数，不以长raw小数撑出栏外")
    local narrow = requiredText("+0.012345")
    check(narrow.fontSize > 0 and narrow.fontSize <= 34
        and narrow.x + narrow.width * 0.5 + 3 <= 1080,
        "微小六围增益不显示成+0或+0.0，仅在宽度需要时缩字号保留完整文本")
    clearDraw(); Stats.drawRadar({}, { agi = 1234567890123 }, nil, true)
    local longEquipRadar = requiredText("+1234567890123")
    check(longEquipRadar.fontSize < 34, "超长装备六围数值按栏内可用宽度缩放")
    check(longEquipRadar.align == NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE
        and longEquipRadar.x + longEquipRadar.width * 0.5 + 3 <= 1080
        and longEquipRadar.x - longEquipRadar.width * 0.5 >= 550,
        "超长配装雷达数字按缩后字号测量、含描边仍在栏内不越1080画布")
    end

    local ok, failure = pcall(run)
    require, time = originalRequire, originalTime
    for name, snapshot in pairs(savedGlobals) do _G[name] = snapshot.value end
    local restored, restoreFailure = pcall(function()
        check(require == originalRequire and time == originalTime, "成功失败均恢复真实require/time")
        for name, snapshot in pairs(savedGlobals) do
            check(_G[name] == snapshot.value, "成功失败均恢复NanoVG全局：" .. name)
        end
    end)
    if ok and restored then
        print("[character_equip_panel_test] ALL PASS: " .. count .. " 个断言（含恢复校验）")
    else
        print("[character_equip_panel_test] FAIL: " .. tostring(failure or restoreFailure)
            .. "；已通过 " .. count .. " 个断言")
    end
    -- 失败也恢复mock并显式退出，不让断言异常变成挂起/timeout。
    engine:Exit()
end
