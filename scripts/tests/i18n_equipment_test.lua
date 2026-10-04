-- 官方 Runtime 独立入口；真实 require，不依赖 package.loaded 预注入。
-- 覆盖四语全装备/类型/词缀/套装，以及模板、测量hook、语言切换与显示源数据不变。
local passed, failed = 0, 0
local function check(ok, label)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("[FAIL] " .. label)
    end
end

local function stable(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = stable(key) .. "=" .. stable(value[key]) end
    return "{" .. table.concat(parts, "|") .. "}"
end

local function numbers(text)
    local result = {}
    for token in text:gmatch("%d+%.?%d*") do result[#result + 1] = string.format("%g", tonumber(token)) end
    table.sort(result)
    return table.concat(result, "|")
end

local function run()
    -- 捕获真实NanoVG度量出口，后续spy与真实Noto字库分两轮，ctx独立不复用缓存。
    local nativeBounds, nativeSize, nativeFace = nvgTextBounds, nvgFontSize, nvgFontFace
    local nativeDelete = nvgDelete
    local metricContext = nvgCreate(1)
    local metricFont = nvgCreateFont(metricContext, "sans", "Fonts/NotoSansCJKkr-Bold.otf")
    check(metricFont >= 0, "生产NotoSansCJKkr-Bold真实字体加载")
    local realMetrics = false
    local I18n = require("core.I18n")
    local D = require("core.I18nEquipment")
    local Dynamic = require("core.I18nEquipmentText")
    local EC = require("config.EquipmentConfig")
    local AC = require("config.AffixConfig")
    local SC = require("config.EquipmentSetConfig")
    local ES = require("systems.EquipmentSystem")
    local original = stable({ EC.ITEMS, AC.AFFIXES, AC.CORRUPT_AFFIXES, SC.SETS })
    local ids, types, sources, affixes = {}, {}, {}, {}
    for id, tpl in pairs(EC.ITEMS) do
        ids[#ids + 1] = id
        types[tpl.type] = true
        sources[#sources + 1] = tpl.name
    end
    table.sort(ids)
    local typeCount = 0
    for name in pairs(types) do typeCount = typeCount + 1; sources[#sources + 1] = name end
    for _, affix in ipairs(AC.AFFIXES) do affixes[#affixes + 1] = affix end
    for _, affix in ipairs(AC.CORRUPT_AFFIXES) do affixes[#affixes + 1] = affix end
    for _, affix in ipairs(affixes) do sources[#sources + 1] = affix.name end
    local setSourceCount = 0
    for _, setId in ipairs(SC.SET_ORDER) do
        local def = SC.SETS[setId]
        for _, field in ipairs({ "name", "desc2", "desc4", "desc6" }) do
            sources[#sources + 1] = def[field]
            setSourceCount = setSourceCount + 1
        end
    end
    check(#ids == 353, "353个真实装备模板")
    check(typeCount == 25, "25个真实装备子类型")
    check(#affixes == 57 and #AC.AFFIXES == 44 and #AC.CORRUPT_AFFIXES == 13, "44普通+13魔化词缀")
    check(setSourceCount == 48, "12套名称及36条2/4/6说明")
    check(#sources == 483, "483个源文覆盖组合")

    local calls = {} ---@type table
    local currentFont = 24
    -- 确定性字体感知测宽：宽M/W、窄i/l、CJK全宽；不是截图或实机字体验收。
    local function measuredWidth(text, font)
        if realMetrics then
            nativeFace(metricContext, "sans")
            nativeSize(metricContext, font)
            local advance = nativeBounds(metricContext, 0, 0, text)
            return advance
        end
        local em = 0
        for _, codepoint in utf8.codes(text) do
            local char = utf8.char(codepoint)
            em = em + (codepoint >= 0x2E80 and 1 or
                ((char == "W" or char == "M") and 0.9 or
                ((char == "i" or char == "l" or char == " ") and 0.3 or 0.6)))
        end
        return em * font
    end
    nvgText = function(_, x, y, text)
        calls[#calls + 1] = { x = x, y = y, text = text, font = currentFont }
        return 0
    end
    nvgTextBox = function(_, x, y, _, text)
        calls[#calls + 1] = { x = x, y = y, text = text }
    end
    nvgTextBounds = function(_, _, _, text)
        calls.measured = text
        return measuredWidth(text, currentFont)
    end
    nvgTextBoxBounds = function(_, _, _, _, text)
        calls.boxMeasured = text
        return { 0, 0, 100, 32 }
    end
    for _, name in ipairs({ "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgFillColor", "nvgBeginPath",
        "nvgRoundedRect", "nvgRect", "nvgFill", "nvgCircle", "nvgStrokeWidth", "nvgStrokeColor", "nvgStroke",
        "nvgSave", "nvgRestore", "nvgTranslate", "nvgScale", "nvgIntersectScissor", "nvgGlobalAlpha" }) do
        _G[name] = function() end
    end
    nvgFontSize = function(_, font) currentFont = font end
    nvgCreateImage = function() return -1 end
    local Draw = require("core.DrawUtil")
    Draw.drawTextStroke = function(_, x, y, text, font)
        currentFont = font
        calls[#calls + 1] = { x = x, y = y, text = I18n.lookup(text), font = font }
    end
    Draw.drawDoubleChevron = function() end
    local Dark = require("core.DarkIcon")
    Dark.drawNine = function() end
    Dark.drawIconDark = function() end
    Dark.drawQualityBg = function() end
    local SetIcon = require("ui.widget.EquipmentSetIcon")
    SetIcon.drawBadge = function() end
    local Images = require("ui.widget.ImageCache")
    Images.getEquipIcon = function() return -1 end
    local Tutorial = require("systems.TutorialManager")
    Tutorial.isBuildingUnlocked = function() return false end
    Tutorial.isActive = function() return false end
    local Feedback = require("systems.ButtonFeedback")
    Feedback.begin = function() return false end
    Feedback.finish = function() end
    I18n.installDrawHook()
    local Detail = require("ui.character.equip.EquipmentDetail")
    Detail.init(nil)
    local State = require("core.GameState")
    State.getLevel = function() return 100 end
    State.getGold = function() return 10000000 end
    State.getEssence = function() return 10000000 end
    for _, name in ipairs({ "getWeaponScroll", "getOffhandScroll", "getArmorScroll", "getHelmetScroll",
        "getShoesScroll", "getAccessoryScroll" }) do State[name] = function() return 100000 end end
    local Enhance = require("ui.blacksmith.BlacksmithEnhance")
    local Refine = require("ui.blacksmith.BlacksmithRefine")
    local equip = ES.generate("W1", 1, 3)
    equip.seq = 90001
    equip.ascendLevel = 4
    equip.affixes = {
        { affixId = 1, key = "str", name = "力量", quality = 2, value = 2 },
        { affixId = 1001, key = "finalPhysAtkBonus", name = "最终物攻", quality = 1, value = 1.7 },
    }
    local state = { selectedEquip = equip, selectedSeq = equip.seq, selectedEquipSlot = "weapon" }
    local grade = { D = -1, C = -1, B = -1, A = -1, S = -1 }
    local function formatValue(_, value) return tostring(value) end
    Enhance.setContext({ state = state, imgGrade = grade, formatAffixValue = formatValue,
        formatCompact = tostring, imgEnhBtn = -1, imgGoldIcon = -1, imgGoldQBg = -1 })
    Refine.setContext({ state = state, imgGrade = grade, formatAffixValue = formatValue,
        imgLock = -1, imgEnhBtn = -1, imgReplaceBtn = -1, imgEssenceIcon = -1, imgGoldQBg = -1,
        imgXlBefore = -1, imgPlus = -1, imgQualityBg = {} })
    Enhance.updateEnhanceData(equip)
    Refine.updateRefineData(equip)
    local displaySnapshot = stable(equip)
    local function contains(text)
        for _, call in ipairs(calls) do if call.text == text then return true end end
        return false
    end
    local function clearCalls()
        for key in pairs(calls) do calls[key] = nil end
    end

    local langs = { "zh_TW", "en", "ja", "ko" }
    local combinations = 0
    for _, lang in ipairs(langs) do
        I18n.set(lang)
        for _, source in ipairs(sources) do
            local expected = D[lang][source]
            check(type(expected) == "string" and expected ~= "", lang .. "字典缺口:" .. source)
            check(I18n.lookup(source) == expected, lang .. "注册显示入口:" .. source)
            check(numbers(source) == numbers(expected or ""), lang .. "数字保持:" .. source)
            check(I18n.lookup(I18n.lookup(source)) == expected, lang .. "译文幂等:" .. source)
            combinations = combinations + 1
        end
        local name = EC.ITEMS.W1.name
        local expectedTitle = string.format(D[lang]["%s 升阶"], D[lang][name])
        check(Dynamic.lookup(name .. " 升阶", lang) == expectedTitle, lang .. "装备升阶旧拼接兼容")
        check(I18n.format("%s 升阶", I18n.lookup(name)) == expectedTitle, lang .. "升阶模板先译后填")
        local raw = "50% {0} %s"
        check(I18n.format("%s 升阶", raw) == string.format(D[lang]["%s 升阶"], raw), lang .. "参数百分号与占位符保持")
        for _, template in ipairs({
            { "腐化状态：诅咒 %d/%d 层", 1, 3 },
            { "腐化状态：诅咒 %d/%d 层（需神圣石洗除）", 3, 3 },
            { "已洗除 1 层诅咒，剩余 %d 层", 2 },
            { "词条倍率 ×%.2f → ×%.2f", 1.10, 1.20 },
            { "词条倍率 ×%.2f", 1.20 },
            { "副属性轮转强化 %d 次", 10 },
            { "%d 条随机词条", 2 },
        }) do
            local source = template[1]
            local rendered = string.format(source, table.unpack(template, 2))
            local expected = string.format(D[lang][source], table.unpack(template, 2))
            check(Dynamic.lookup(rendered, lang) == expected, lang .. "严格动态模板:" .. source)
            check(I18n.lookup(rendered) == expected, lang .. "动态注册入口:" .. source)
        end
        local gradeSource = "词缀「力量」品级 C → B"
        check(Dynamic.lookup(gradeSource, lang) == string.format(D[lang]["词缀「%s」品级 %s → %s"], D[lang]["力量"], "C", "B"), lang .. "词缀品级参数显示本地化")
        local list = D[lang]["力量"] .. Dynamic.separator(lang)
            .. string.format(D[lang]["词条倍率 ×%.2f"], 1.20)
        check(Dynamic.lookup("升阶获得：力量、词条倍率 ×1.20", lang)
            == string.format(D[lang]["升阶获得：%s"], list), lang .. "升阶所得列表")
        check(Dynamic.lookup("返还卷轴 武器+10 头盔+20", lang) ~= nil, lang .. "卷轴返还已登记部位")
        clearCalls()
        nvgTextBounds(nil, 0, 0, name)
        nvgText(nil, 0, 0, name)
        check(calls.measured == D[lang][name] and contains(calls.measured), lang .. "测量与绘制同译文")
        clearCalls()
        Detail.drawReadOnly(nil, equip, 0, 0)
        check(contains(D[lang][name]), lang .. "真实只读装备详情译名")
        check(contains(D[lang][equip.type]), lang .. "真实只读详情子类型")
        check(contains(D[lang]["最终物攻"]), lang .. "真实只读详情魔化词缀")
        local setEquip = ES.generate("W12", 81, 1)
        Detail.drawReadOnly(nil, setEquip, 0, 0)
        check(contains(I18n.format("%s  %d/6", I18n.lookup(SC.SETS.swordgate.name), 0)), lang .. "套装标题本地化")
        check(contains(D[lang][SC.SETS.swordgate.desc6]), lang .. "只读套装描述译文")
        clearCalls()
        Enhance.drawPanel(nil)
        check(contains(expectedTitle), lang .. "真实升阶标题动态显示")
        check(contains(D[lang]["力量"]) and contains(D[lang]["最终物攻"]), lang .. "升阶缓存不留旧语词缀")
        check(contains("???") and contains("+?"), lang .. "里程碑未知词条占位保持")
        clearCalls()
        Refine.drawPanel(nil)
        check(contains(D[lang]["力量"]) and contains(D[lang]["最终物攻"]), lang .. "洗练缓存不留旧语词缀")
        equip.corruptCount = 3
        clearCalls()
        Refine.drawPanel(nil)
        check(contains(string.format(D[lang]["腐化状态：诅咒 %d/%d 层（需神圣石洗除）"], 3, 3)), lang .. "洗练诅咒状态完整模板")
        equip.corruptCount = nil
    end
    -- 固定副词条数值和下一阶预览实际绘制，不把随机词条当成升阶目标。
    I18n.set("zh_CN")
    local codex = ES.generate("O13", 12, 4)
    codex.ascendLevel = 11
    state.selectedEquip, state.selectedEquipSlot = codex, "offhand"
    Enhance.updateEnhanceData(codex)
    clearCalls()
    Enhance.drawPanel(nil)
    local function shownAt(x, value)
        for _, call in ipairs(calls) do if call.x == x and call.text == value then return true end end
        return false
    end
    check(shownAt(473, ES.formatBaseStatValue("armor", ES.effectiveBaseStatValue(codex, 1))),
        "主属性升阶前值保留小数")
    local damageBefore = ES.effectiveBaseStatValue(codex, 3)
    local damageAfter = ES.effectiveBaseStatValue(codex, 3, nil, 12)
    check(shownAt(473, ES.formatBaseStatValue("magDmgBonus", damageBefore))
        and shownAt(856, ES.formatBaseStatValue("magDmgBonus", damageAfter)) and damageAfter > damageBefore,
        "+11到+12固定魔伤词条在绿色值框预览真实提升")
    codex.ascendLevel = 12
    Enhance.updateEnhanceData(codex)
    clearCalls()
    Enhance.drawPanel(nil)
    check(shownAt(856, ES.formatBaseStatValue("magPen", ES.effectiveBaseStatValue(codex, 2, nil, 13))),
        "+12到+13轮到固定穿透词条且可预览")
    check(ES.formatBaseStatValue("armor", 14.1) ~= ES.formatBaseStatValue("armor", 14.4),
        "护甲零头不再显示相同整数")
    state.selectedEquip, state.selectedEquipSlot = equip, "weapon"
    Enhance.updateEnhanceData(equip)
    local bulk = ES.generate("W1", 1, 1)
    state.selectedEquip, state.selectedEquipSlot = bulk, "weapon"
    State.getGold = function() return 10 ^ 14 end
    Enhance.updateEnhanceData(bulk)
    check(Enhance.handleInput(770, 2129) and Enhance.isDialogOpen(), "无随机词条也可预览固定副一键升阶")
    I18n.set("en")
    clearCalls()
    Enhance.drawConfirmDialog(nil)
    local bulkSummary
    for _, call in ipairs(calls) do if call.y == 1223 then bulkSummary = call end end
    check(bulkSummary and measuredWidth(bulkSummary.text, bulkSummary.font) <= 800,
        "多里程碑英文一键摘要缩字后不越出弹窗内框")
    Enhance.onOpen()
    state.selectedEquip, state.selectedEquipSlot = equip, "weapon"
    Enhance.updateEnhanceData(equip)
    I18n.set("zh_CN")
    check(combinations == 1932, "四语1932个全量覆盖组合")
    -- 正图片句柄覆盖锁图标实际绘制和热区；直接调用真实Draw入口，省掉业务输入副作用。
    local DetailDraw = require("ui.character.equip.EquipmentDetailDraw")
    local headerState = { heroId = nil, slot = nil, descScrollY = 0, descScrollMax = 0 }
    local drawnImages = {} ---@type table[]
    local titleCalls = {} ---@type table[]
    local rawDisplayText = I18n.displayText
    local rawRowCalls = 0
    local titleStroke = 3
    I18n.displayText = function(vg, x, y, text, endp)
        rawDisplayText(vg, x, y, text, endp)
        rawRowCalls = rawRowCalls + 1
        if rawRowCalls % 9 == 0 then
            titleCalls[#titleCalls + 1] = { x = x, y = y, text = text, font = currentFont,
                width = measuredWidth(text, currentFont), stroke = titleStroke, title = true }
        end
    end
    local headerDraw = DetailDraw.create({
        detState = headerState, setKw = {}, qualityColor = { { 255, 255, 255 } }, affixBadgeKey = {},
        getImages = function()
            return { powerIcon = 101, arrowUp = 102, arrowDown = 103, lock = 104,
                btnGreen = -1, btnYellow = -1, btnRed = -1, affixBadge = {} }
        end,
        drawImageCentered = function(_, image, cx, cy, width, height, alpha)
            drawnImages[#drawnImages + 1] = { image = image, cx = cx, cy = cy, w = width, h = height, alpha = alpha }
        end,
        drawTextStroke = function(_, x, y, text, font, _, r, g, b, stroke)
            titleCalls[#titleCalls + 1] = { x = x, y = y, text = text, font = font,
                width = measuredWidth(text, font), stroke = stroke, title = r == 255 and g == 255 and b == 255 }
        end,
        calcEquipPower = function() return 123456789 end,
        getEquipIcon = function() return -1 end,
        getStatName = tostring, formatStatValue = tostring,
        layoutButtons = function() return 1461, 0 end, clampDescScroll = function() end,
        compactViewHeight = function() return 430 end,
        compactSetLines = function() return nil, {} end,
        compactSetRowHeight = function() return 36 end,
        compactContentBottom = function() return 204 end,
        compactButtonRow = function() return 380, 380, 805, 300, 64 end,
        layout = { COMPACT_BG_W = 600, COMPACT_ICON_CY = 168, COMPACT_ICON_SIZE = 132,
            COMPACT_NAME_Y = 34, COMPACT_PAD_TOP = 28, COMPACT_QUALITY_Y = 122, COMPACT_STAT_Y0 = 248,
            COMPACT_TYPE_Y = 78, DESC_TOP = 980, REF_BG_CX = 805, REF_NAME_X = 470, REF_NAME_Y = 625,
            REF_NAME_FONT = 40, REF_TYPE_X = 470, REF_TYPE_Y = 706, REF_TYPE_FONT = 30,
            REF_QUALITY_X = 470, REF_QUALITY_Y = 861, REF_QUALITY_FONT = 30,
            REF_STAT_FONT = 34, REF_ARROW_GAP = 12, REF_ARROW_SIZE = 48,
            REF_ICON_CX = 903, REF_ICON_CY = 809, REF_ICON_SIZE = 290,
            REF_BTN_CX = 807, REF_BTN_W = 410, REF_BTN_H = 100, REF_BTN_FONT = 40 },
    })
    local headerCases, realMinimum = 0, 100
    for _, metricMode in ipairs({ "spy", "Noto" }) do
    realMetrics = metricMode == "Noto"
    if realMetrics then
        check(measuredWidth("mmmm", 20) > 0 and math.abs(measuredWidth("mmmm", 20) - 48) > 0.01,
            "Noto真实测宽出口不走等宽/spy估算")
    end
    for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
        I18n.set(lang)
        -- W11为报告的长英语反例；再扫353模板，宽字/CJK压力且不修改配置。
        local headerIds = { "W11" }
        for _, id in ipairs(ids) do if id ~= "W11" then headerIds[#headerIds + 1] = id end end
        for _, id in ipairs(headerIds) do
            local tpl = EC.ITEMS[id]
            local testEquip = { templateId = id, name = tpl.name, type = tpl.type, slot = tpl.slot,
                quality = 1, level = 1, locked = true, ascendLevel = 0 }
            local originalHeader = stable(testEquip)
            for _, compact in ipairs({ true, false }) do
                titleCalls, drawnImages, rawRowCalls = {}, {}, 0
                titleStroke = compact and 3 or 4
                headerState.lockHotspot = nil
                if compact then
                    headerDraw.drawCompactPanel(metricContext, testEquip, "", true)
                else
                    headerDraw.drawEquipPanel(metricContext, testEquip, 0, 805, 1120, 860, 1380, 1, false, "", false, true)
                end
                local nameY, typeY = compact and 34 or 625, compact and 78 or 706
                local panelLeft, panelRight = compact and 505 or 375, compact and 1105 or 1235
                local rebuilt, minFont, titleRight, rows = {}, 100, 0, 0
                for _, call in ipairs(titleCalls) do
                    if call.title and math.abs(call.y - nameY) < 45 then
                        rebuilt[#rebuilt + 1] = call.text
                        minFont = math.min(minFont, call.font)
                        titleRight = math.max(titleRight, call.x + call.width + call.stroke)
                        rows = rows + 1
                        check(call.x - call.stroke >= panelLeft and call.y - call.font * 0.5 - call.stroke >= (compact and 0 or 430)
                            and call.y + call.font * 0.5 + call.stroke < typeY - (compact and 13 or 15),
                            lang .. id .. "标题字框在标题带内")
                    end
                end
                local lock = nil ---@type table?
                local power = nil ---@type table?
                for _, image in ipairs(drawnImages) do
                    if image.image == 104 then lock = image end
                    if image.image == 101 then power = image end
                end
                local label = metricMode .. " " .. lang .. id .. (compact and " compact" or " full")
                if realMetrics then realMinimum = math.min(realMinimum, minFont) end
                check(table.concat(rebuilt) == I18n.lookup(tpl.name) and rows <= 2 and minFont >= 20,
                    label .. "全名不截断且两行可读")
                check(lock ~= nil and power ~= nil and lock.alpha == 1, label .. "正句柄locked图标/战力都绘制")
                if lock and power then
                    local hot = headerState.lockHotspot
                    check(hot ~= nil and hot.cx == lock.cx and hot.cy == lock.cy and hot.w > lock.w and hot.h > lock.h,
                        label .. "锁绘制/点击同源")
                    if hot then
                        check(hot.cx - hot.w * 0.5 > titleRight and hot.cx + hot.w * 0.5 < power.cx - power.w * 0.5
                            and hot.cx + hot.w * 0.5 <= panelRight, label .. "锁热区不出板/不撞标题战力")
                    end
                end
                check(stable(testEquip) == originalHeader, label .. "source名/ID/锁业务不变")
                headerCases = headerCases + 1
            end
        end
    end
    end
    I18n.displayText = rawDisplayText
    realMetrics = false
    nativeDelete(metricContext)
    print(string.format("[equipment-Noto-metrics] cases=3530 minimum_title_font=%.1f", realMinimum))
    check(headerCases == 7060, "五语353模板×compact/full×spy/Noto共7060布局回归")
    check(stable(equip) == displaySnapshot, "绘制/切语不修改装备实例数值与原名")
    for _, text in ipairs({ "未知装备 升阶", "image/练习用剑.png", "练习用剑 升阶奖励",
        "词缀「未知词缀」品级 C → B", "词条倍率 ×1.2", "将新增 力量、未知词条",
        "返还卷轴 武器+10 未知+1", "腐化状态：诅咒 1/3 层恶意后缀" }) do
        check(Dynamic.lookup(text, "en") == nil, "未登记模板原样回退:" .. text)
    end
    check(Dynamic.lookup(nil, "en") == nil and Dynamic.lookup(0, "en") == nil
        and Dynamic.lookup("", "en") == nil and Dynamic.lookup("力量", "xx") == nil, "动态空值与未知语言安全")
    I18n.set("zh_CN")
    for _, source in ipairs(sources) do check(I18n.lookup(source) == source, "简体显示保持:" .. source) end
    check(stable({ EC.ITEMS, AC.AFFIXES, AC.CORRUPT_AFFIXES, SC.SETS }) == original,
        "353模板ID/名称/归属/业务数值/词缀/套装配置全部未变")
    clearCalls()
    Enhance.drawPanel(nil)
    check(contains(EC.ITEMS.W1.name .. " 升阶"), "切回简体升阶标题保持原文")
    print(string.format("[i18n_equipment_test] passed=%d failed=%d combinations=%d", passed, failed, combinations))
    if failed == 0 then print("I18N EQUIPMENT: ALL PASS") end
end

function Start()
    print("[i18n_equipment_test] 开始装备五语显示回归")
    local ok, err = pcall(run)
    if not ok then
        failed = failed + 1
        print("[i18n_equipment_test] FAIL " .. tostring(err))
        log:Write(LOG_ERROR, "[i18n_equipment_test] " .. tostring(err))
    end
    print("[i18n_equipment_test] EXIT ok=" .. tostring(ok) .. " failed=" .. tostring(failed))
    if failed > 0 then log:Write(LOG_ERROR, "I18N EQUIPMENT: FAILED " .. tostring(failed)) end
    engine:Exit()
end
