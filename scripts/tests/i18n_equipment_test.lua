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
    nvgText = function(_, x, y, text)
        calls[#calls + 1] = { x = x, y = y, text = text }
        return 0
    end
    nvgTextBox = function(_, x, y, _, text)
        calls[#calls + 1] = { x = x, y = y, text = text }
    end
    nvgTextBounds = function(_, _, _, text)
        calls.measured = text
        return (utf8.len(text) or #text) * 12
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
    nvgCreateImage = function() return -1 end
    local Draw = require("core.DrawUtil")
    Draw.drawTextStroke = function(_, x, y, text)
        calls[#calls + 1] = { x = x, y = y, text = I18n.lookup(text) }
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
    check(combinations == 1932, "四语1932个全量覆盖组合")
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
