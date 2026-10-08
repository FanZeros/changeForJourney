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
    hook("nvgTextLetterSpacing", noop)
    hook("nvgTextBounds", function(vg, x, y, value, bounds)
        local width = textWidth(value, fontSize)
        if bounds then
            local offset = textAlign & NVG_ALIGN_RIGHT ~= 0 and width
                or (textAlign & NVG_ALIGN_CENTER ~= 0 and width * 0.5 or 0)
            bounds[1], bounds[2], bounds[3], bounds[4] = x - offset, y - fontSize * 0.5,
                x - offset + width, y + fontSize * 0.5
        end
        return width, bounds
    end)
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
    local latestResult = {}
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
    local actualAD = originalRequire("systems.AttributeDef")
    local AD = { META = {}, getDesc = actualAD.getDesc,
        formatAttrDisplayValue = function(key, value) return tostring(value) end }
    local tooltipDrawn = nil
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
                latestResult = { current = current, preview = seq and preview or nil, rows = rows,
                    equipmentBonuses = requestedBonuses and bonuses or nil,
                    currentSets = summaries, previewSets = previewSummaries,
                    candidate = seq and { seq = seq, slot = slot, name = "测试候选" } or nil }
                return latestResult
            end,
        },
    }
    require = function(name) return mods[name] or originalRequire(name) end
    -- 差集几何使用真实纯模块，只有数据/资源依赖被 mock。
    local RadarDiff = originalRequire("ui.character.detail.CharacterRadarDiff")
    local Stats = originalRequire("ui.character.detail.CharacterEquipStats")
    local sortCount = 0
    -- 只包依赖入口计数，仍调用真实排序函数，不改共享模块方法。
    mods["ui.character.detail.CharacterEquipStats"] = setmetatable({
        sortComparisonRows = function(input)
            sortCount = sortCount + 1
            return Stats.sortComparisonRows(input)
        end,
        drawTooltip = function(vg, tip)
            tooltipDrawn = tip
            return Stats.drawTooltip(vg, tip)
        end,
    }, { __index = Stats })
    local Shared = originalRequire("ui.character.detail.CharacterAttributeView")
    for _, name in ipairs({ "config.HeroAssetUtil", "config.ClassConfig", "config.ExpTable",
        "ui.character.equip.EquipmentBag", "config.EquipmentConfig", "ui.widget.HeroFrame",
        "ui.character.hero.AwakeningPanel", "systems.ButtonFeedback", "core.DarkIcon",
        "systems.ExtraTalentSystem", "systems.EquipmentPower", "core.I18n" }) do mods[name] = {} end
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
        and Shared.STYLE.rowH == 78 and Shared.STYLE.rowStep == 88 and Shared.STYLE.fontSize == 35,
        "同绘图API分离字号与列宽，配装行距跟随属性页78高88步长")
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
    check(attrs.y == 1050 and attrs.h == 718 and Stats.LAYOUT.rowH == 78 and Stats.LAYOUT.rowStep == 88,
        "配装属性区保持718高度顶1050，行尺寸扩大为78高88步长")
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
    check(rendered("角色属性") and toggleTriangles() == 0 and not rendered("‹") and not rendered("›"),
        "角色属性标题仅文字，不叠加括号、箭头或旧左右三角")
    clearDraw(); Stats.drawHeader({}, "equipment")
    check(rendered("装备加成") and toggleTriangles() == 0,
        "装备加成标题仅文字，切换热区仍保留")
    local sample = { { key = "a", name = "同样属性", value = "42" } }
    clearDraw(); Draw.drawAttributeRows({}, sample, 0, Shared.ATTRIBUTE_LAYOUT, { style = Draw.ATTRIBUTE_STYLE })
    local originalName, originalValue = requiredText("同样属性"), requiredText("42")
    local originalRow = rects[1]
    clearDraw(); Stats.drawRows({}, sample, 0)
    local equipName, equipValue = requiredText("同样属性"), requiredText("42")
    check(originalName.x == 150 and originalValue.x == 514
        and originalName.y == originalValue.y and originalName.y == 1109
        and equipName.y == equipValue.y and equipName.y == attrs.y + 39
        and equipName.x == 167 and equipValue.x == 504,
        "属性与配装保留名称坐标，数值内收6像素给描边留空间")
    check(originalName.fontSize == 40 and originalValue.fontSize == 40
        and equipName.fontSize == 35 and equipValue.fontSize == 35
        and sameColor(originalValue.color, 255, 255, 255) and sameColor(equipValue.color, 255, 255, 255)
        and sameColor(originalName.color, 0xE8, 0xDC, 0xC8) and sameColor(equipName.color, 0xE8, 0xDC, 0xC8),
        "属性页独立40号、配装仍35号，白数字/E8DCC8名称配色不变")
    check(originalRow.x == 70 and originalRow.y == 1070 and originalRow.w == 460 and originalRow.h == 78
        and rects[1].x == 90 and rects[1].y == attrs.y and rects[1].w == 440 and rects[1].h == 78
        and rects[1].radius == originalRow.radius and rects[1].radius == 20,
        "两页共用78行高，属性460宽与配装440宽独立，圆角20不变")
    check(scissorCalls[1].x == 40 and scissorCalls[1].w == 500,
        "配装属性clip同属性页x40宽500")
    check(#imageCalls == 1 and sharedPaths[imageCalls[1].image]:find("ICON_XX.png", 1, true),
        "属性行装饰复用ICON_XX句柄")
    local _, hits = Stats.drawRows({}, sample, 0)
    check(Shared.rowAt(hits, ax, attrs.y + 39) == sample[1]
        and Shared.rowAt(hits, ax, attrs.y + Stats.LAYOUT.rowH + 4) == nil,
        "可见行hit匹配78高且10像素行距不出现幽灵hit")

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
    check(equipMax == 328 and #equipHits == 9 and requiredText("属性1").fontSize == 35
        and requiredText("属性2").y - requiredText("属性1").y == 88
        and rects[1].w == 440 and rects[1].h == 78,
        "配装35号78高88距，上限328与属性页相同行距而独立视口")
    check(equipHits[1].index == 1 and equipHits[1].y == 1050 and equipHits[1].h == 78
        and equipHits[#equipHits].index == 9 and equipHits[#equipHits].h == 14
        and Stats.rowAt(equipHits, ax, 1767) == rows[9] and Stats.rowAt(equipHits, ax, 1768) == nil,
        "配装首行完整、末行9仅14px可见，clip底不命中")
    check(Stats.rowAt(equipHits, ax, 1127) == rows[1]
        and Stats.rowAt(equipHits, ax, 1128) == nil and Stats.rowAt(equipHits, ax, 1137) == nil
        and Stats.rowAt(equipHits, ax, 1138) == rows[2], "配装10px行距无幽灵命中")
    clearDraw()
    local _, lastEquipHits = Stats.drawRows({}, rows, 10000)
    check(lastEquipHits[1].index == 4 and lastEquipHits[1].y == 1050 and lastEquipHits[1].h == 14
        and lastEquipHits[#lastEquipHits].index == 12 and lastEquipHits[#lastEquipHits].h == 78
        and Stats.rowAt(lastEquipHits, ax, 1050) == rows[4]
        and Stats.rowAt(lastEquipHits, ax, 1767) == rows[12],
        "配装滚底首行4裁剪14px、末行12完整78px，不使用属性页scroll")
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
            and longNumber.x == mode.style.valueX - mode.style.stroke - 2 and longNumber.x <= mode.layout.x + mode.layout.w
            and longNumber.x - longNumber.width >= longName.x
            and longName.y == longNumber.y, "两页长数字完整保留，右锚点/基线及clip边界不变")
    end
    check(Shared.STYLE.fontSize == 35 and Shared.STYLE.rowH == 78 and Shared.STYLE.rowStep == 88
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
    check(deltaLabel.x == Shared.STYLE.valueX and deltaLabel.y == deltaValue.y - 37
        and Shared.STYLE.deltaFontSize == 28 and deltaLabel.fontSize == 28 and rects[1].h == Shared.STYLE.rowH,
        "配装delta保留原右锚点和28号，当前值内收描边不改变78高88距与cy-37基线")
    clearDraw(); Stats.drawRows({}, rows, 0)
    local firstDelta, secondDelta, firstValue, secondValue = requiredText("+5"), requiredText("-3"),
        requiredText("1"), requiredText("2")
    check(firstDelta.fontSize == 28 and secondDelta.fontSize == 28
        and firstDelta.y + firstDelta.fontSize * 0.5 < firstValue.y - 35 * 0.5 - 4
        and secondDelta.y - secondDelta.fontSize * 0.5 > firstValue.y + 35 * 0.5 + 4
        and secondValue.y == attrs.y + 39 + 88,
        "放大红绿差值仍与本行及上行35号主数值含描边不重叠")
    check(#scissorCalls == 2 and scissorCalls[1].y == attrs.y and scissorCalls[1].h == attrs.h
        and scissorCalls[2].x == attrs.x and scissorCalls[2].w == attrs.w
        and scissorCalls[2].y == attrs.y - 20 and scissorCalls[2].h == attrs.h + 20
        and firstDelta.y - firstDelta.fontSize * 0.5 >= scissorCalls[2].y
        and firstDelta.y + firstDelta.fontSize * 0.5 <= scissorCalls[2].y + scissorCalls[2].h,
        "delta独立上扩20px裁剪覆盖完整28号首行，属性clip不变")
    for _, sign in ipairs({ 1, -1 }) do
        local longDeltaText = (sign > 0 and "+" or "-") .. string.rep("1234567890", 8)
        clearDraw(); Stats.drawRows({}, { { key = "longDelta", name = "同样属性", value = "42",
            delta = sign * 100, deltaText = longDeltaText } }, 0)
        local longDelta = requiredText(longDeltaText)
        local maxWidth = math.min(Shared.STYLE.boxW - 20, Shared.STYLE.valueX - attrs.x - 12)
        check(longDelta.fontSize > 0 and longDelta.fontSize < 28 and longDelta.width <= maxWidth + 0.000001
            and longDelta.x - longDelta.width >= attrs.x + 12 and longDelta.x <= attrs.x + attrs.w
            and longDelta.align == NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE
            and longDelta.y == attrs.y + 39 - 37 and deltaSign(longDelta.color) == sign,
            "超长红绿列表差值保留全文并按可用宽缩字，右锚点/颜色/基线不变")
        check(requiredText("同样属性").fontSize == 35 and requiredText("42").fontSize == 35,
            "长delta缩字不影响名称和当前值")
    end

    -- 打乱源序且同key不同增减：颜色优先级来自beneficial，而不是delta符号或属性名。
    local comparisonRows = {
        { key = "none", deltaText = "+幽灵", beneficial = true },
        { key = "loss", delta = -4 },
        { key = "zero", delta = 0, beneficial = false },
        { key = "atkInterval", delta = -0.2, beneficial = true },
        { key = "tinyPlus", delta = 0.0000005, beneficial = true },
        { key = "atkInterval", delta = 0.3, beneficial = false },
        { key = "gain", delta = 3 },
        { key = "tinyMinus", delta = -0.0000005, beneficial = false },
        { key = "zGain", delta = -2, beneficial = true },
        { key = "aLoss", delta = 9, beneficial = false },
        { key = "aGain", delta = 6, beneficial = true },
        { key = "zLoss", delta = -1, beneficial = false },
    }
    local order = { 4, 7, 9, 11, 2, 6, 10, 12, 1, 3, 5, 8 }
    local sourceSnapshot = {}
    for i, row in ipairs(comparisonRows) do
        row.name, row.value, row.desc = "排序属性" .. i, tostring(i), "排序说明" .. i
        if row.delta and math.abs(row.delta) >= 0.000001 then row.deltaText = tostring(row.delta) end
        sourceSnapshot[i] = { row = row, fields = {} }
        for key, value in pairs(row) do sourceSnapshot[i].fields[key] = value end
    end
    local sortedRows = Stats.sortComparisonRows(comparisonRows)
    check(sortedRows ~= comparisonRows and #sortedRows == #comparisonRows
        and #Stats.sortComparisonRows(nil) == 0, "排序仅复制数组，nil安全且不丢行")
    for i, sourceIndex in ipairs(order) do
        check(sortedRows[i] == comparisonRows[sourceIndex]
            and Shared.changePriority(sortedRows[i]) == (i <= 4 and 1 or (i <= 8 and 2 or 3)),
            "绿/红/无变化组保持原行引用和源序：" .. i)
    end
    local sourceUnchanged = true
    for i, snapshot in ipairs(sourceSnapshot) do
        local row = comparisonRows[i] or error("排序丢失源行：" .. i)
        if row ~= snapshot.row then sourceUnchanged = false end
        for key, value in pairs(snapshot.fields) do
            if row[key] ~= value then sourceUnchanged = false end
        end
        for key, value in pairs(row) do
            if snapshot.fields[key] ~= value then sourceUnchanged = false end
        end
    end
    check(sourceUnchanged, "排序不改源数组顺序或行内容，不添加排序字段")
    clearDraw(); Stats.drawRows({}, sortedRows, 0)
    check(deltaSign(requiredText("-0.2").color) == 1 and deltaSign(requiredText("0.3").color) == -1
        and not rendered("+幽灵") and not rendered("0.0000005") and not rendered("-0.0000005"),
        "负攻击间隔绿色、正攻击间隔红色，nil/zero/tiny不显示变化字")

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
    local radarName, radarValue, radarDelta = requiredText("力量"), requiredText("10"), requiredText("+10")
    check(radarName.x == layout.cx and radarName.y == layout.cy - layout.labelR - 24
        and radarName.fontSize == 26 and radarValue.x == layout.cx
        and radarValue.y == layout.cy - layout.labelR + 16 and radarValue.fontSize == 34
        and layout.deltaFontSize == 32 and layout.deltaOffset == 58
        and radarDelta.fontSize == 32 and requiredText("-3").fontSize == 32
        and radarDelta.y == layout.cy - layout.labelR - 58,
        "六围红绿delta放大32号移至ly-58，原26号名称和34号当前值基线不动")
    check(radarDelta.y + radarDelta.fontSize * 0.5 + 4 < radarName.y - radarName.fontSize * 0.5
        and radarName.y + radarName.fontSize * 0.5 + 3 < radarValue.y - radarValue.fontSize * 0.5
        and radarDelta.y - radarDelta.fontSize * 0.5 >= attrs.y,
        "雷达delta/名称/当前值含描边间距不重叠，顶部大字不越属性区")
    check(#scissorCalls == 0, "雷达不另设474宽scissor裁掉左右标签")
    for _, sign in ipairs({ 1, -1 }) do
        local longStats = {}
        for _, key in ipairs({ "str", "agi", "vit", "spi", "luk", "int" }) do
            longStats[key] = sign * 123456789012345
        end
        clearDraw(); Stats.drawRadar({}, {}, longStats)
        local expectedDelta, deltaCount = (sign > 0 and "+" or "-") .. "123456789012345", 0
        for _, call in ipairs(textCalls) do
            if deltaSign(call.color) ~= 0 then
                deltaCount = deltaCount + 1
                local maxWidth = math.min(150, (1080 - call.x - 5) * 2, (call.x - 540 - 5) * 2)
                check(call.value == expectedDelta and call.fontSize > 0 and call.fontSize < 32
                    and call.width <= maxWidth + 0.000001 and call.x - call.width * 0.5 >= 545 - 0.000001
                    and call.x + call.width * 0.5 <= 1075 + 0.000001
                    and call.align == NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE and deltaSign(call.color) == sign,
                    "六轴超长红绿delta全文缩放，按左右画布可用宽不越界")
            end
        end
        check(deltaCount == 6, "六轴长delta全部保留，不裁掉左右标签")
    end

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
    local legacyLongTop = requiredText(Shared.formatNumber(12345678901234567890))
    check(legacyLongTop.fontSize < 38 and legacyLongTop.x + legacyLongTop.width * 0.5 + 3 <= 1080,
        "属性页右上超长数值保持完整文本并按实际标签可用宽缩放")
    clearDraw(); Stats.drawRadar({}, { str = 38.745624, agi = 8 }, nil)
    check(rendered("38.745624") and not rendered("38"), "配装雷达保留实际六围小数，用测量缩放防止越出画布")
    clearDraw(); Stats.drawLegacy({}, { str = 38.745624, agi = 8 })
    check(rendered("38.745624") and not rendered("38"), "属性页和配装页六围显示使用同一精度")
    -- legacy基图允许0.08视觉下限；纯差集比较允许0，低值UI不锁死两者半径相等。
    clearDraw(); Stats.drawRadar({}, { str = 0.04, agi = 1 }, { str = 0.05, agi = 1 })
    local tinyDelta = rendered("+0.01")
    check(tinyDelta and not rendered("+0.0") and rendered("0.04").fontSize == 34
        and tinyDelta.fontSize == 32 and tinyDelta.y == layout.cy - layout.labelR - 58,
        "低值当前六围0.04与raw差值+0.01都保留精度/坐标，不预言visualfloor几何")

    -- 纯视觉六围过渡：原数字/差集oracle不变，动画只插值归一化轮廓。
    do
        local axes = { "str", "agi", "vit", "spi", "luk", "int" }
        local function sameVisual(a, b)
            if not near(a.maxValue, b.maxValue) or not near(a.floor, b.floor)
                or (a.preview == nil) ~= (b.preview == nil) then return false end
            for _, key in ipairs(axes) do
                if not near(a.current[key], b.current[key]) then return false end
                if a.preview and not near(a.preview[key], b.preview[key]) then return false end
            end
            return true
        end
        local transition = Stats.createRadarTransition()
        local baseline = transition:sample(current.stats, preview.stats, false, "hero1", 100)
        local scale = 20 / 0.82
        check(rawget(baseline, "stats") == nil and rawget(baseline, "attrs") == nil
            and baseline.current ~= current.stats
            and baseline.preview ~= preview.stats and near(baseline.maxValue, scale) and baseline.floor == 0.08,
            "transition首绘静默且只返回纯视觉六轴/尺度，不冒充attrs/stats快照")
        for _, key in ipairs(axes) do
            check(near(baseline.current[key], math.max(0.08, current.stats[key] / scale))
                and near(baseline.preview[key], math.max(0.08, preview.stats[key] / scale)),
                "首绘六轴立即为真实终点归一化半径：" .. key)
        end
        local empty = {}
        local start = transition:sample(empty, nil, true, "hero1", 100)
        check(sameVisual(start, baseline), "角色切空装备起点完全沿用当前视觉形状而不是跳中心")
        local halfway = transition:sample(empty, nil, true, "hero1", 100.16)
        check(near(halfway.maxValue, scale + (8 - scale) * 0.875)
            and near(halfway.floor, 0.08 * 0.125), "0.32秒中点easeOutCubic=.875且尺度/下限同步插值")
        for _, key in ipairs(axes) do
            check(near(halfway.current[key], baseline.current[key] * 0.125)
                and near(halfway.preview[key], baseline.preview[key] * 0.125),
                "中点六轴current/preview连续收束：" .. key)
        end
        for i = 1, 30 do
            check(sameVisual(halfway, transition:sample(empty, nil, true, "hero1", 100.16)),
                "同墙钟重复sample不加速/重开过渡：" .. i)
        end
        local finish = transition:sample(empty, nil, true, "hero1", 100.32)
        check(finish.preview == nil and finish.floor == 0 and finish.maxValue == 8,
            "0.32秒终点精确且不残留已关闭的预览轮廓")
        for _, key in ipairs(axes) do check(finish.current[key] == 0, "空装终点六轴中心：" .. key) end
        clearDraw(); Stats.drawRadar({}, empty, nil, true, finish)
        local centered = radarPaths()
        for _, point in ipairs(centered[1]) do
            check(near(point[1], layout.cx) and near(point[2], layout.cy), "纯视觉空装drawRadar顶点中心")
        end
        clearDraw(); Stats.drawLegacy({}, current.stats, finish)
        local collapsedLegacy = radarPaths()
        check(requiredText("10") and not rendered("0.5"), "legacy视觉收束时数字仍为真实10，不显示临时值")
        for _, point in ipairs(collapsedLegacy[1]) do
            check(near(point[1], Stats.LEGACY.HEX_CX) and near(point[2], Stats.LEGACY.HEX_CY),
                "legacy可选纯视觉可落中心，不被旧8%下限再次钳制")
        end

        transition:reset()
        local initial = transition:sample(current.stats, preview.stats, false, "hero1", 110)
        transition:sample(empty, nil, true, "hero1", 110)
        local interrupted = transition:sample(empty, nil, true, "hero1", 110.08)
        local redirected = transition:sample(current.stats, preview.stats, false, "hero2", 110.08)
        check(sameVisual(interrupted, redirected), "快速切hero/模式从中途视觉接续，不跳旧源或新终点")
        local quickMid = transition:sample(current.stats, preview.stats, false, "hero2", 110.24)
        for _, key in ipairs(axes) do
            check(near(quickMid.current[key], interrupted.current[key]
                + (initial.current[key] - interrupted.current[key]) * 0.875)
                and near(quickMid.preview[key], interrupted.preview[key]
                + (initial.preview[key] - interrupted.preview[key]) * 0.875),
                "快切新中点从中途轮廓easeOutCubic：" .. key)
        end
        local quickEnd = transition:sample(current.stats, preview.stats, false, "hero2", 110.40)
        check(sameVisual(quickEnd, initial), "快切完成精确回到新hero真实六轴")
        local otherHost = Stats.createRadarTransition()
        local otherShape = otherHost:sample(empty, nil, true, "hero2", 110.40)
        check(otherShape.current.str == 0 and sameVisual(transition:sample(current.stats, preview.stats,
            false, "hero2", 110.40), initial), "两个宿主私有闭包互不串形状/动画时钟")
        quickEnd.current.str = -999
        quickEnd.preview.agi = -999
        check(sameVisual(transition:sample(current.stats, preview.stats, false, "hero2", 110.40), initial),
            "返回视觉表可被调用方修改而不污染闭包")
        transition:reset()
        local reopened = transition:sample(empty, nil, true, "hero3", 1)
        check(sameVisual(reopened, otherShape), "reset清旧身份/时钟/形状，低墙钟重新首绘静默")

        local sourceStats, sourcePreview = { str = 10, agi = 8, vit = 6, spi = 4, luk = 3, int = 2 },
            { str = 20, agi = 5, vit = 6, spi = 4, luk = 3, int = 2 }
        local sourceCopy, previewCopy = {}, {}
        for key, value in pairs(sourceStats) do sourceCopy[key] = value end
        for key, value in pairs(sourcePreview) do previewCopy[key] = value end
        transition:sample(sourceStats, sourcePreview, false, "hero4", 2)
        transition:sample(bonuses.current.stats, bonuses.preview.stats, true, "hero4", 2.1)
        local displayVisual = transition:sample(bonuses.current.stats, bonuses.preview.stats, true, "hero4", 2.26)
        clearDraw(); Stats.drawRadar({}, bonuses.current.stats, bonuses.preview.stats, true, displayVisual)
        local animatedPolygons, animatedRegions, animatedEdges = radarPaths()
        local visualOracle = RadarDiff.compare(displayVisual.current, displayVisual.preview,
            layout.cx, layout.cy, layout.r, 1)
        check(sameVertices(animatedPolygons[1], visualOracle.oldVertices)
            and matchesComparison(animatedRegions, animatedEdges, visualOracle),
            "动画差集仍由真实RadarDiff共用oracle比较纯视觉六轴，不复制公式")
        check(requiredText("+5.5") and requiredText("+2") and not rendered("+10") and not rendered("-3"),
            "动画中装备主数字和差值立即为最终+5.5/+2，不借旧英雄临时数值")
        clearDraw(); Stats.drawLegacy({}, sourceStats, displayVisual)
        check(requiredText("10") and requiredText("8") and not rendered("+5.5"),
            "同一视觉形状传legacy也只显示自己的真实六围数字")
        local unchanged = true
        for key, value in pairs(sourceStats) do if sourceCopy[key] ~= value then unchanged = false end end
        for key, value in pairs(sourceCopy) do if sourceStats[key] ~= value then unchanged = false end end
        for key, value in pairs(sourcePreview) do if previewCopy[key] ~= value then unchanged = false end end
        for key, value in pairs(previewCopy) do if sourcePreview[key] ~= value then unchanged = false end end
        check(unchanged and bonuses.current.stats.str == 5.5 and bonuses.preview.stats.str == 7.5,
            "sample与两种draw均不改源stats/预览六围或添加动画字段")
        transition:sample(bonuses.current.stats, bonuses.preview.stats, true, "hero4", 2.42)
        local updated = { str = 6.5, agi = 2 }
        local stable = transition:sample(updated, nil, true, "hero4", 2.5)
        check(near(stable.current.str, updated.str / Stats.radarScale(updated)) and stable.preview == nil,
            "稳定style下新stats表/数值立即刷新，不每帧重新开动画")
        clearDraw(); Stats.drawRadar({}, updated, nil, true, stable)
        local refreshedPolygons = radarPaths()
        local refreshedOracle = RadarDiff.compare(updated, nil, layout.cx, layout.cy, layout.r,
            Stats.radarScale(updated))
        check(sameVertices(refreshedPolygons[1], refreshedOracle.oldVertices),
            "同style更新终点沿用真实同尺度oracle")
    end

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
    -- 避免 .xxxxxx5 的二进制表示落在十进制中点两侧；仍独立断言六位精度，不降位数。
    clearDraw(); Stats.drawRadar({}, { str = 2.8597846, agi = 0.012345 }, nil, true)
    check(rendered("+2.859785") and not rendered("+2.9") and Shared.formatNumber(2.8597846) == "2.859785",
        "装备六围保留六位小数精度，字号测量防止撑出栏外")
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

    -- 真实Panel消费打乱的两种来源：排序只在刷新做，滚动/说明使用显示行而非源索引。
    local savedRows, savedBonusRows = rows, bonuses.rows
    rows = comparisonRows
    local equipmentRows = {}
    for i = #comparisonRows, 1, -1 do
        local row = {}
        for key, value in pairs(comparisonRows[i]) do row[key] = value end
        row.name, row.desc = "装备排序" .. i, "装备排序说明" .. i
        equipmentRows[#equipmentRows + 1] = row
    end
    bonuses.rows = equipmentRows
    equipment.inventory["8"] = { enhanceLevel = 1 }
    heroes.roster[2] = { level = 1 }
    for _, mode in ipairs({ "character", "equipment" }) do
        if Panel.getAttributeMode() ~= mode then Panel.toggleAttributeMode() end
        selection = { seq = 7, slot = "weapon", heroId = 1, owner = "bag", pinned = true }
        requestedSlot = nil
        Panel.reset(1, nil)
        local source = mode == "equipment" and equipmentRows or comparisonRows
        local indices = mode == "equipment" and { 2, 4, 6, 9, 1, 3, 7, 11, 5, 8, 10, 12 } or order
        local beforeBuild, beforeSort = buildCount, sortCount
        draw()
        local display = mode == "equipment" and latestResult.equipmentBonuses or latestResult
        local cachedRows = display.displayRows
        check(buildCount == beforeBuild + 1 and sortCount == beforeSort + (mode == "equipment" and 2 or 1)
            and display.rows == source and cachedRows ~= source and #cachedRows == #source,
            mode .. "首次刷新缓存独立显示数组，角色/装备排序次数准确且不改源数组")
        for i, sourceIndex in ipairs(indices) do
            check(cachedRows[i] == source[sourceIndex], mode .. "真实Panel首次稳定绿/红/无变化分组：" .. i)
        end
        local first = cachedRows[1]
        check(requiredText(first.name).y == firstRowY and not rendered(cachedRows[12].name),
            mode .. "首次显示变化优先首行，未滚动就不显示末行")
        local cachedBuild, cachedSort = buildCount, sortCount
        draw()
        check(buildCount == cachedBuild and sortCount == cachedSort and display.displayRows == cachedRows,
            mode .. "同key后续帧复用已排序数组，不重复sort")
        Panel.handleInput(ax, firstRowY, 1, {})
        clearDraw(); Panel.drawSetCodex({})
        check(rendered(first.desc) and not rendered(source[1].desc),
            mode .. "首行tooltip取真实排序行说明，不取源首行")
        Panel.handleSideScroll(-1000, ax, ay); draw()
        local lastY = requiredText(cachedRows[12].name).y
        check(not rendered(first.name), mode .. "排序列表可滚到底且首条改善项已离开视口")
        draw()
        check(requiredText(cachedRows[12].name).y == lastY and not rendered(first.name)
            and buildCount == cachedBuild and sortCount == cachedSort,
            mode .. "每帧命中缓存不重置滚动也不排序")
        time.elapsedTime = time.elapsedTime + 0.31; draw()
        check(requiredText(cachedRows[12].name).y == lastY and not rendered(first.name)
            and buildCount == cachedBuild and sortCount == cachedSort and display.displayRows == cachedRows,
            mode .. "超缓存检查间隔签名不变仍复用排序并保持滚底")
        -- 滚底首行4只剩14px：按真实可见片段点击，说明必须对应displayRows[4]。
        Panel.handleInput(ax, attrs.y + 1, 1, {})
        clearDraw(); Panel.drawSetCodex({})
        check(rendered(cachedRows[4].desc) and not rendered(source[4].desc),
            mode .. "滚底裁剪行tooltip与排序后的真实行对应")
        selection.seq = 8; draw()
        check(buildCount == cachedBuild + 1 and sortCount == cachedSort + (mode == "equipment" and 2 or 1)
            and requiredText(first.name).y == firstRowY and not rendered(cachedRows[12].name),
            mode .. "换候选立即刷新排序并滚动归顶")
        clearDraw(); Panel.drawSetCodex({})
        check(#textCalls == 0, mode .. "换候选清旧排序行tooltip")
        Panel.handleSideScroll(-1000, ax, ay); draw()
        local bottomY = requiredText(cachedRows[12].name).y
        for _, reason in ipairs({ "markDirty", "selfLevel", "otherLevel", "enhance" }) do
            Panel.handleInput(ax, attrs.y + 1, 1, {})
            beforeBuild, beforeSort = buildCount, sortCount
            if reason == "markDirty" then
                first.value = "同序数值更新" .. mode
                Panel.markDirty()
            elseif reason == "selfLevel" then
                heroes.roster[1].level = heroes.roster[1].level + 1
            elseif reason == "otherLevel" then
                heroes.roster[2].level = heroes.roster[2].level + 1
                time.elapsedTime = time.elapsedTime + 0.31
            else
                equipment.inventory["8"].enhanceLevel = equipment.inventory["8"].enhanceLevel + 1
                time.elapsedTime = time.elapsedTime + 0.31
            end
            draw()
            check(buildCount == beforeBuild + 1 and sortCount == beforeSort + (mode == "equipment" and 2 or 1)
                and requiredText(cachedRows[12].name).y == bottomY and not rendered(first.name),
                mode .. "同序刷新保留滚底，仅重建/排序一次：" .. reason)
            clearDraw(); Panel.drawSetCodex({})
            check(#textCalls == 0, mode .. "同序刷新也清旧tooltip：" .. reason)
        end
        -- 5px拖动保留惯性；重建只换数值/签名不应抹掉velocity或本帧继续移动。
        Panel.handleSideScroll(1000, ax, ay)
        Panel.handleDragBegin(ax, ay); Panel.handleDragMove(ax, ay - 5); Panel.handleDragEnd(ax, ay - 5)
        draw()
        check(near(requiredText(first.name).y, firstRowY - 10), mode .. "拖动结束首帧应用5px惯性")
        Panel.markDirty(); draw()
        check(near(requiredText(first.name).y, firstRowY - 14.5), mode .. "markDirty同序刷新保留滚动及0.9衰减惯性")
        heroes.roster[2].level = heroes.roster[2].level + 1
        time.elapsedTime = time.elapsedTime + 0.31; draw()
        check(near(requiredText(first.name).y, firstRowY - 18.55), mode .. "另一英雄level签名刷新仍保留惯性而非归顶")
        Panel.handleSideScroll(-1000, ax, ay); draw()
        Panel.handleInput(ax, attrs.y + 1, 1, {})
        -- 同一候选原地更新数据并改变改善项：缓存失效后新首行不能沿用旧hit/tip。
        first.beneficial = false
        equipment.inventory["8"].enhanceLevel = equipment.inventory["8"].enhanceLevel + 1
        beforeBuild, beforeSort = buildCount, sortCount
        time.elapsedTime = time.elapsedTime + 0.31; draw()
        local refreshed = mode == "equipment" and latestResult.equipmentBonuses or latestResult
        check(buildCount == beforeBuild + 1 and sortCount == beforeSort + (mode == "equipment" and 2 or 1)
            and refreshed.displayRows ~= cachedRows and refreshed.displayRows[1] == cachedRows[2]
            and requiredText(cachedRows[2].name).y == firstRowY and not rendered(cachedRows[12].name),
            mode .. "原地数据签名刷新重排一次且归顶，新改善项成为首行")
        clearDraw(); Panel.drawSetCodex({})
        check(#textCalls == 0, mode .. "原地数据刷新清旧tooltip")
        Panel.handleInput(ax, firstRowY, 1, {})
        clearDraw(); Panel.drawSetCodex({})
        check(rendered(cachedRows[2].desc) and not rendered(first.desc),
            mode .. "刷新后首行tooltip对应新排序，不遗留旧hit")
    end
    rows, bonuses.rows = savedRows, savedBonusRows
    Panel.clear()

    -- 真实配装宿主私有transition接线：切样式/英雄动画，缓存刷新不重开时钟。
    do
        local savedCurrent, savedPreview, savedSelection = current, preview, selection
        if Panel.getAttributeMode() ~= "character" then Panel.toggleAttributeMode() end
        selection = { seq = 7, slot = "weapon", heroId = 1, owner = "bag", pinned = true }
        requestedSlot = nil
        time.elapsedTime = 40
        Panel.reset(1, nil)
        draw()
        local expectedTransition = Stats.createRadarTransition()
        local expected = expectedTransition:sample(current.stats, preview.stats, false, "1|character", 40)
        local function matchesVisual(visual)
            local polygons, regions, edges = radarPaths()
            local oracle = RadarDiff.compare(visual.current, visual.preview,
                radar.cx, radar.cy, radar.r, 1)
            return sameVertices(polygons[1], oracle.oldVertices) and matchesComparison(regions, edges, oracle)
        end
        check(matchesVisual(expected), "Panel首绘立即为当前英雄真实归一化六轴")
        Panel.toggleAttributeMode(); draw()
        expected = expectedTransition:sample(bonuses.current.stats, bonuses.preview.stats,
            true, "1|equipment", 40)
        check(matchesVisual(expected) and rendered("+5.5") and rendered("+2"),
            "Panel切装备起点不跳轮廓，数字/delta已是最终装备贡献")
        time.elapsedTime = 40.16; draw()
        expected = expectedTransition:sample(bonuses.current.stats, bonuses.preview.stats,
            true, "1|equipment", 40.16)
        check(matchesVisual(expected), "Panel0.16秒中点匹配私有闭包easeOutCubic")
        local oldBonusStats = bonuses.current.stats
        bonuses.current.stats = { str = 5.5 }
        for i = 1, 10 do
            Panel.markDirty(); draw()
            check(matchesVisual(expected), "Panel相同墙钟数据重建/新表不重开动画：" .. i)
        end
        bonuses.current.stats = oldBonusStats
        Panel.toggleAttributeMode(); draw()
        expected = expectedTransition:sample(current.stats, preview.stats, false, "1|character", 40.16)
        check(matchesVisual(expected), "Panel快切回角色属性从中点形状连续接上")
        time.elapsedTime = 40.48; draw()
        expected = expectedTransition:sample(current.stats, preview.stats, false, "1|character", 40.48)
        check(matchesVisual(expected) and requiredText("10") and requiredText("+10") and requiredText("-3"),
            "Panel快切终点/真实数字/原差集oracle保持")

        current = { left = {}, right = {}, stats = { str = 2, agi = 28, vit = 9, spi = 13, luk = 4, int = 1 } }
        preview = { left = {}, right = {}, stats = { str = 5, agi = 26, vit = 9, spi = 13, luk = 4, int = 1 } }
        Panel.reset(2, nil) -- 与真实上层syncEquipmentWarehouse活动切英雄调用一致。
        clearDraw(); Panel.draw({}, 2, { equipSlot = nil })
        expected = expectedTransition:sample(current.stats, preview.stats, false, "2|character", 40.48)
        check(matchesVisual(expected) and requiredText("28") and requiredText("-2"),
            "活动Panel.reset换英雄保留当前视觉起点，新英雄真实数字已更新")
        time.elapsedTime = 40.64
        clearDraw(); Panel.draw({}, 2, { equipSlot = nil })
        expected = expectedTransition:sample(current.stats, preview.stats, false, "2|character", 40.64)
        check(matchesVisual(expected), "Panel英雄变更中点六轴完整过渡")
        time.elapsedTime = 40.80
        clearDraw(); Panel.draw({}, 2, { equipSlot = nil })
        expected = expectedTransition:sample(current.stats, preview.stats, false, "2|character", 40.80)
        check(matchesVisual(expected), "Panel英雄变更0.32秒终点精准归一化")
        Panel.reset(nil, nil)
        expectedTransition:reset()
        current, preview = savedCurrent, savedPreview
        time.elapsedTime = 1
        Panel.reset(1, nil); draw()
        expected = expectedTransition:sample(current.stats, preview.stats, false, "1|character", 1)
        check(matchesVisual(expected), "Panel关闭reset(nil)后低墙钟重开静默，无旧英雄形状/时钟残留")
        Panel.toggleAttributeMode(); draw()
        Panel.clear()
        expectedTransition:reset()
        draw()
        expected = expectedTransition:sample(bonuses.current.stats, bonuses.preview.stats, true, "1|equipment", 1)
        check(matchesVisual(expected), "Panel显式clear中断动画并使下一首绘静默")
        Panel.toggleAttributeMode()
        selection = savedSelection
        Panel.clear()
        time.elapsedTime = 41
    end

    -- 真实属性说明通过公开点击/悬停链取出；原布局探针仍绘制完整浮层。
    if Panel.getAttributeMode() ~= "character" then Panel.toggleAttributeMode() end
    local definitionKeys = {}
    for key in pairs(actualAD.META) do
        if key ~= actualAD.HP then definitionKeys[#definitionKeys + 1] = key end
    end
    table.sort(definitionKeys)
    for _, key in ipairs(definitionKeys) do
        local expected = actualAD.getDesc(key)
        check(type(expected) == "string" and expected ~= "", "可显示属性有词条解释：" .. key)
        local row = { key = key, name = actualAD.META[key].name, currentValue = 1, value = "1" }
        rows = { row }
        Panel.reset(1, nil); draw()
        check(Panel.handleInput(ax, firstRowY, 1, {}), "无预填desc属性点击命中：" .. key)
        Panel.drawSetCodex({})
        check(tooltipDrawn and tooltipDrawn.key == key and tooltipDrawn.name == row.name
            and tooltipDrawn.desc == expected, "点击显示属性定义而非最终数值占位：" .. key)
        Panel.reset(1, nil); draw()
        local _, hits = Shared.drawAttributeRows({}, rows, 0)
        check(#hits == 1 and hits[1].desc == expected
            and Shared.rowAt(hits, hits[1].x + 1, hits[1].y + 1) == row,
            "共享行说明同源且不改变命中返回契约：" .. key)
        Panel.handleHover(ax, firstRowY, 1)
        Panel.drawSetCodex({})
        check(tooltipDrawn == nil, "悬停仍遵守延时：" .. key)
        time.elapsedTime = time.elapsedTime + 0.31
        Panel.handleHover(ax, firstRowY, 1)
        Panel.drawSetCodex({})
        check(tooltipDrawn and tooltipDrawn.desc == expected, "悬停显示属性本身内容：" .. key)
    end
    check(actualAD.getDesc(actualAD.MAX_HP) == "生命上限。生命归零则死亡。",
        "生命值截图正文使用生命上限与死亡规则")
    check(actualAD.getDesc(actualAD.ARMOR_BONUS) == "百分比增加护甲。",
        "护甲加成补齐已有关键词说明")
    for _, supplied in ipairs({ "装备来源说明", "动态暴击与神器说明", "" }) do
        local row = { key = actualAD.MAX_HP, name = "生命值", value = "100", desc = supplied }
        local expected = supplied ~= "" and supplied or actualAD.getDesc(actualAD.MAX_HP)
        rows = { row }
        Panel.reset(1, nil); draw()
        Panel.handleInput(ax, firstRowY, 1, {})
        Panel.drawSetCodex({})
        check(tooltipDrawn and tooltipDrawn.desc == expected,
            "自定义说明优先、空说明回退属性定义：" .. supplied)
        local _, hits = Shared.drawAttributeRows({}, rows, 0)
        check(hits[1].desc == expected and row.desc == supplied, "共享说明不改写原始行")
    end
    rows = { { key = "_unknownStat", name = "未知属性", value = "0" } }
    Panel.reset(1, nil); draw()
    Panel.handleInput(ax, firstRowY, 1, {})
    Panel.drawSetCodex({})
    check(tooltipDrawn and tooltipDrawn.desc == "", "未知属性不伪造最终结果说明")
    rows = savedRows
    Panel.clear()
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
