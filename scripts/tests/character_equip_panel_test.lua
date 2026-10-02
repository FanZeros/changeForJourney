-- 配装下部回归：纯 NanoVG 绘图探针，不依赖字体/贴图或存档。
function Start()
    local originalRequire, originalTime = require, time
    local savedGlobals, textCalls, paths, rects, scissorCalls, imageCalls = {}, {}, {}, {}, {}, {}
    local color, path = {}, {}
    local fontSize = 0
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
    hook("nvgFillColor", noop)
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

    check(Draw.drawAttributeRows == Stats.drawAttributeRows and Stats.drawAttributeRows == Shared.drawAttributeRows,
        "两页调用同一个drawAttributeRows而非复制属性行")
    check(Draw.ATTRIBUTE_STYLE == Stats.ATTRIBUTE_STYLE and Shared.STYLE.rowH == 60
        and Shared.STYLE.rowStep == 69, "共用属性行风格对象60高69步长")
    check(Draw.ATTR_FIRST_ROW_Y == Shared.ATTRIBUTE_LAYOUT.firstY
        and Draw.ATTR_CLIP_TOP == Shared.ATTRIBUTE_LAYOUT.y
        and Draw.ATTR_CLIP_HEIGHT == Shared.ATTRIBUTE_LAYOUT.h,
        "属性页M.ATTR原输入坐标完全不变")
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
    clearDraw(); Stats.drawRows({}, { { key = "d", name = "变化属性", value = "42", delta = 5 } }, 0)
    check(rendered("变化属性").y == rendered("42").y and rendered("+5.0").y > rendered("42").y
        and rendered("+5.0").y + rendered("+5.0").fontSize * 0.5 <= attrs.y + Shared.STYLE.rowH,
        "变化行名称当前同baseline，delta在行内第二baseline不占更多行高")

    check(math.abs(Stats.radarScale(current.stats, preview.stats) - 20 / 0.82) < 0.000001, "双轮廓共用最大值尺度")
    check(Stats.radarScale({}, {}) == 8, "无候选与属性页同样采用max(8,peak/.82)尺度")
    check(Stats.LEGACY.HEX_CY == 1535.5 and Stats.LEGACY.HEX_LABEL_R == 230, "属性页原雷达布局不变")
    clearDraw(); Stats.drawRadar({}, current.stats, preview.stats)
    local outline = {}
    for _, points in ipairs(paths) do if #points == 6 then outline[#outline + 1] = points end end
    check(#outline == 2, "当前和试穿各一份六边形轮廓")
    local layout = Stats.LAYOUT.radar
    local beforeR = layout.cy - outline[1][1][2]
    local afterR = layout.cy - outline[2][1][2]
    check(math.abs(afterR / beforeR - 2) < 0.000001, "相同尺度保留力量20/10的2倍轮廓关系")
    check(rendered("+10") and rendered("-3"), "六围标签显示正负numeric delta")
    check(#scissorCalls == 0, "雷达不另设474宽scissor裁掉左右标签")
    clearDraw(); Stats.drawLegacy({}, current.stats)
    local legacyOutline = nil
    for _, points in ipairs(paths) do if #points == 6 then legacyOutline = points; break end end
    clearDraw(); Stats.drawRadar({}, current.stats, nil)
    local equipOutline = nil
    for _, points in ipairs(paths) do if #points == 6 then equipOutline = points; break end end
    check(math.abs((Stats.LEGACY.HEX_CY - legacyOutline[1][2])
        - (radar.cy - equipOutline[1][2])) < 0.000001, "无候选轮廓尺度与原属性页完全一致")
    clearDraw(); Stats.drawRadar({}, { str = 38.745624, agi = 8 }, nil)
    check(rendered("38") and not rendered("38.745624"), "雷达只显示整数避免raw六围长小数越出画布")

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
    check(rendered("当前已穿戴属性 · 选中或悬停装备以试穿") ~= nil, "无候选标题提示当前")
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
    check(Panel.handleDragMove(ax, -5000) and Panel.handleDragEnd(ax, -5000), "属性drag移动结束")
    draw(); check(rendered("属性12") ~= nil, "属性drag下界钳制")
    check(Panel.handleSideScroll(-1000, sx, sy), "套装wheel独立命中")
    draw(); check(rendered("第二套装") ~= nil and rendered("属性12") ~= nil, "滚套装不改变属性scroll且可见最后不同套装")
    check(Panel.handleDragBegin(sx, sy), "套装drag开始")
    Panel.handleDragMove(sx, 20000); Panel.handleDragEnd(sx, 20000)
    draw(); check(rendered("旧套装") ~= nil, "套装drag向下拖归零")
    check(not Panel.handleDragBegin(radar.cx, radar.cy), "雷达不是拖装备或滚动区")
    check(Panel.handleSideScroll(-1, radar.cx, radar.cy), "雷达wheel消费但不借用旧scrollTarget")
    check(not Panel.handleSideScroll(-1, Draw.BTN_TAB_EQUIP_CX, Draw.BTN_TAB_EQUIP_CY), "wheel不吞页签")
    Panel.clear(); draw(); check(rendered("属性1") ~= nil, "clear清滚动与候选缓存")

    require, time = originalRequire, originalTime
    for name, value in pairs(savedGlobals) do _G[name] = value end
    print("[character_equip_panel_test] ALL PASS: " .. count .. " 个断言")
    engine:Exit()
end
