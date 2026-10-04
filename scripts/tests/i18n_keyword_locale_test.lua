-- 独立关键词五语回归：官方Runtime执行Start+pcall+engine:Exit；不预注入package.loaded。
-- 入口 tests/i18n_keyword_locale_test.lua；无GPU，用显式NanoVG spy验证raw边界与几何。
local T = {}

-- 新增集合必须显式列出，避免动态计数掩盖漏译；原25项另行验证。
local STAT_KEYS = {
    "护盾伤害减免", "物理格挡概率", "魔法格挡概率", "物理暴击伤害", "魔法暴击伤害",
    "物理攻击加成", "魔法攻击加成", "物理伤害加成", "魔法伤害加成", "物理暴击率",
    "魔法暴击率", "治疗暴击率", "物理攻击力", "魔法攻击力", "物理穿透", "魔法穿透",
    "连击概率", "连击增伤", "攻击速度", "暴击伤害", "生命加成", "护甲加成", "护盾加成",
    "治疗加成", "闪避加成", "每秒回血", "命中值", "闪避值", "暴击率", "生命值",
    "怨引值", "怨引", "护甲", "护盾", "力量", "敏捷", "秘识", "体质", "命数", "魂火",
}
local ORIGINAL_KEYS = {
    "封门人", "拾骸者", "裂隙使", "回响客", "换面人", "司仪", "门缝", "拾骸", "裂隙",
    "回响", "换面", "延缓", "骸骨", "裂痕", "仇恨", "护甲克制", "连击", "超暴击",
    "能量护盾", "腐化", "腐化石", "神圣石", "洗练石", "点金石", "洗练",
}

-- 星图原数值必须逐字、顺序、重复次数、百分比单位一致，不归一化1.0为1。
local function numberLiterals(text)
    local out = {}
    for token in text:gmatch("%d+%.?%d*%%?") do out[#out + 1] = token end
    return table.concat(out, "|")
end

local function sameNumbers(a, b)
    -- 源文「一次/一条/一层」可译成1；关键原有数值必须逐项保留，包括重复值。
    local required, available = {}, {}
    for v in a:gmatch("%d+%.?%d*") do
        local n = assert(tonumber(v))
        required[n] = (required[n] or 0) + 1
    end
    for v in b:gmatch("%d+%.?%d*") do
        local n = assert(tonumber(v))
        available[n] = (available[n] or 0) + 1
    end
    for v, n in pairs(required) do if (available[v] or 0) < n then return false end end
    return true
end

local function flatten(layout, explicitNewlines)
    local lines = {}
    for _, line in ipairs(layout.lines) do
        local pieces = {}
        for _, piece in ipairs(line.pieces) do
            assert(utf8.len(piece.text), "invalid UTF-8 fragment")
            pieces[#pieces + 1] = piece.text
        end
        lines[#lines + 1] = table.concat(pieces)
    end
    return table.concat(lines, explicitNewlines and "\n" or "")
end

local function keywordKeys(layout)
    local out = {}
    for _, line in ipairs(layout.lines) do
        for _, piece in ipairs(line.pieces) do
            if piece.keyword then out[#out + 1] = piece.key end
        end
    end
    return table.concat(out, "|")
end

function T.run()
    local KW = require("config.KeywordConfig")
    local Locale = require("core.I18nKeywords")
    local I18n = require("core.I18n")
    local KeywordText = require("ui.widget.KeywordText")
    local Sets = require("config.EquipmentSetConfig")
    local SetLocale = require("core.I18nEquipmentSets")
    local checks, count, fields, setCases = 0, 0, 0, 0
    local function check(condition, label)
        checks = checks + 1
        assert(condition, "[keyword locale] " .. label)
    end
    local originalLang = I18n.get()
    local TalentText = require("core.I18nTalentText")
    check(KW.get("护盾伤害减免").title == "护盾减伤", "shield stable key has short title")
    for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
        I18n.set(lang)
        local expected = lang == "zh_CN" and "护盾减伤"
            or require("core.I18nEquipment")[lang]["护盾减伤"]
        check(I18n.lookup("护盾减伤") == expected, lang .. " shield short label translated")
        check(Locale.get("护盾伤害减免", lang).title == expected,
            lang .. " shield popup uses matching short title")
        local found = false
        for _, term in ipairs(Locale.terms(lang)) do
            if term.text == expected and term.key == "护盾伤害减免" then found = true end
        end
        check(found, lang .. " short label maps back to stable keyword")
        check(TalentText.label("护盾减伤", lang) == TalentText.label("护盾伤害减免", lang),
            lang .. " old and short talent atoms retain same translation")
        check(TalentText.lookup("全体护盾减伤+12%", lang) ~= nil,
            lang .. " short talent sentence remains fully translatable")
    end
    I18n.set(originalLang)
    local expectedKeys, statKeys = {}, {}
    check(#ORIGINAL_KEYS == 25 and #STAT_KEYS == 40, "explicit original25 + new40 sets")
    for _, key in ipairs(ORIGINAL_KEYS) do
        check(not expectedKeys[key] and KW.get(key) ~= nil, "original key exists / " .. key)
        expectedKeys[key] = true
    end
    for _, key in ipairs(STAT_KEYS) do
        check(not expectedKeys[key] and KW.get(key) ~= nil, "new key exists / " .. key)
        expectedKeys[key], statKeys[key] = true, true
    end
    local savedDefs = {}
    for key, def in pairs(KW.KEYWORDS) do
        check(expectedKeys[key] == true, "complete registered key set / " .. key)
        savedDefs[key] = { title = def.title, desc = def.desc }
        count = count + 1
        for _, lang in ipairs({ "zh_TW", "en", "ja", "ko" }) do
            local translated = assert(Locale.get(key, lang))
            check(translated.title ~= "" and translated.desc ~= "", key .. "/" .. lang .. " nonempty")
            check(Locale.lookup(def.desc, lang) ~= nil and (lang == "zh_TW" or translated.desc ~= def.desc),
                key .. "/" .. lang .. " description explicitly registered (traditional may equal source)")
            check(Locale.lookup(def.title, lang) == translated.title, "title exact lookup")
            check(Locale.lookup(def.desc, lang) == translated.desc, "desc exact lookup")
            check(sameNumbers(def.desc, translated.desc), key .. "/" .. lang .. " numbers")
            if statKeys[key] then
                check(numberLiterals(def.desc) == numberLiterals(translated.desc), key .. "/" .. lang .. " exact numeric literals/units/order")
                local sourceFormula = ({
                    ["物理格挡概率"] = "(1-格挡比例)", ["魔法格挡概率"] = "(1-格挡比例)",
                    ["物理穿透"] = "1:1", ["魔法穿透"] = "1:1",
                    ["攻击速度"] = "=基础间隔/(1+攻击速度%)",
                    ["命中值"] = "=(命中值+150)/(闪避值+150)",
                    ["闪避值"] = "=(命中值+150)/(闪避值+150)", ["护甲"] = "护甲/(护甲+100)",
                })[key]
                if sourceFormula then
                    local function symbols(text)
                        local out = {}
                        for symbol in text:gmatch("[=()+/:%%-]") do out[#out + 1] = symbol end
                        return table.concat(out)
                    end
                    check(def.desc:find(sourceFormula, 1, true) ~= nil, "source formula fixture / " .. key)
                    check(symbols(def.desc) == symbols(translated.desc), key .. "/" .. lang .. " formula operators/percent unchanged")
                end
            end
            local _, n1 = def.desc:gsub("\n", "")
            local _, n2 = translated.desc:gsub("\n", "")
            check(n1 == n2, key .. "/" .. lang .. " paragraphs")
            fields = fields + 2
        end
    end
    check(count == 65 and fields == count * 4 * 2 and fields == 520,
        "65 keywords / 520 localized title+desc fields")
    check(Locale.get("unknown", "en") == nil, "unknown key")
    check(Locale.lookup("未登记整句：回响", "en") == nil, "no substring lookup")
    check(Locale.lookup("回响", "fr") == nil, "unknown language")
    check(Locale.lookup(nil, "en") == nil, "nil source")
    local copy = assert(Locale.get("回响", "en"))
    copy.title = "mutated display copy"
    check(Locale.get("回响", "en").title == "Echo", "display definition is a copy")

    local kt = KeywordText.new()
    local samples = {
        zh_CN = "回响客与回响，裂隙使与裂隙。",
        zh_TW = "回響客與回響，裂隙使與裂隙。",
        en = "Echoist and ECHO; Riftweaver and Rift.",
        ja = "残響客と残響、裂け目使いと裂け目。",
        ko = "메아리객의 메아리와 열극사의 열극.",
    }
    for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
        I18n.set(lang)
        local sample = samples[lang]
        local layout = kt:_layout(nil, sample, 10000, 20)
        check(keywordKeys(layout) == "回响客|回响|裂隙使|裂隙", "translated longest-match / " .. lang)
        check(flatten(layout, true) == sample, "display text unchanged / " .. lang)
        kt:draw(nil, sample, 40, 80, 10000, 20, 28)
        check(#kt.hotspots == 4, "four original-key hotspots / " .. lang)
        local h = kt.hotspots[2]
        check(h.name == "回响" and h.text ~= "", "hotspot stores original key and display fragment")
        kt:handleInput((h.x1 + h.x2) / 2, (h.y1 + h.y2) / 2)
        check(kt.popup and kt.popup.key == "回响", "popup original key")
        check(kt.popup and kt.popup.name == Locale.get("回响", lang).title, "popup localized title")
        check(kt.popup and kt.popup.desc == Locale.get("回响", lang).desc, "popup localized desc")
        kt:closePopup()
        for key, def in pairs(KW.KEYWORDS) do
            local title = kt:_layout(nil, def.title, 10000, 20)
            check(title.displayText == Locale.get(key, lang).title, "source-title→display / " .. key .. lang)
            local desc = kt:_layout(nil, def.desc, 10000, 20)
            check(flatten(desc, true) == Locale.get(key, lang).desc, "source-desc→display / " .. key .. lang)
            local displayName = assert(Locale.name(key, lang))
            local isolated = "[" .. displayName .. "]"
            local nameLayout = kt:_layout(nil, isolated, 10000, 20)
            check(keywordKeys(nameLayout) == key, "all65 localized display name→original key / " .. key .. lang)
            check(flatten(nameLayout, true) == isolated, "localized display name unchanged / " .. key .. lang)
            kt:draw(nil, isolated, 40, 80, 10000, 20, 28)
            check(#kt.hotspots == 1 and kt.hotspots[1].name == key, "all65 original-key hotspot / " .. key .. lang)
            local hotspot = kt.hotspots[1]
            check(kt:handleInput((hotspot.x1 + hotspot.x2) / 2, (hotspot.y1 + hotspot.y2) / 2),
                "all65 click accepted / " .. key .. lang)
            local expected = assert(Locale.get(key, lang))
            check(kt.popup and kt.popup.key == key and kt.popup.name == expected.title
                and kt.popup.desc == expected.desc, "all65 click localized original-key popup / " .. key .. lang)
            kt:closePopup()
        end
        local seenTerms = {}
        local priorLength = math.huge
        for _, term in ipairs(Locale.terms(lang)) do
            check(KW.get(term.key) ~= nil and not seenTerms[term.text], "unique known alias / " .. term.text .. lang)
            check(#term.text <= priorLength, "longest terms first / " .. lang)
            priorLength, seenTerms[term.text] = #term.text, term.key
        end
        local TalentText = require("core.I18nTalentText")
        local Equipment = require("core.I18nEquipment")
        for _, key in ipairs(STAT_KEYS) do
            for _, label in ipairs({ TalentText.label(key, lang) or "", Equipment[lang] and Equipment[lang][key] or "" }) do
                if label ~= "" then
                    -- 无上下文同词Threat明确归旧「仇恨」；Threat Value才是怨引值。
                    local expectedKey = lang == "en" and label == "Threat" and "仇恨" or key
                    local sampleLabel = "[" .. label .. "]"
                    check(keywordKeys(kt:_layout(nil, sampleLabel, 10000, 20)) == expectedKey,
                        "existing stat label alias / " .. key .. lang .. label)
                    check(seenTerms[label] == expectedKey, "explicit alias ownership / " .. key .. lang .. label)
                end
            end
        end
        for _, setId in ipairs(Sets.orderedSetIds()) do
            local set = assert(Sets.get(setId))
            for _, field in ipairs({ "desc2", "desc4", "desc6" }) do
                local source = set[field]
                local display = I18n.lookup(source)
                local layout = kt:_layout(nil, source, 10000, 20)
                check(flatten(layout, true) == display, "set full source→display / " .. setId .. field .. lang)
                check(sameNumbers(source, display), "set numeric semantics / " .. setId .. field .. lang)
                if lang ~= "zh_CN" then
                    local expected = SetLocale[lang][source]
                    check(type(expected) == "string" and expected ~= "" and display == expected,
                        "set full desc registered / " .. setId .. "/" .. field .. "/" .. lang)
                end
                kt:draw(nil, source, 10, 20, 10000, 20)
                for _, h in ipairs(kt.hotspots) do
                    check(KW.get(h.name) ~= nil and h.x2 > h.x1, "set hotspot original key / " .. setId)
                end
                setCases = setCases + 1
            end
        end
    end

    I18n.set("en")
    local boundaries = "Echoist echoing preEcho Echoes éEcho Echoé Echo2 Echo_tag Echo-like echo ECHO (Echo)."
    local boundaryLayout = kt:_layout(nil, boundaries, 10000, 20)
    check(keywordKeys(boundaryLayout) == "回响客|回响|回响|回响", "English word boundaries/case/Latin UTF-8")
    check(flatten(boundaryLayout, true) == boundaries, "boundary matching does not rewrite text")
    local aliases = kt:_layout(nil, "Sacred Stone and Holy Stone; Alchemy Stone and Gold Stone.", 10000, 20)
    check(keywordKeys(aliases) == "神圣石|神圣石|点金石|点金石", "registered dictionary aliases")
    for _, case in ipairs({
        { lang = "en", text = "Gate-gap and Door-gap; Threat Value, Threat Weight, Threat.",
            keys = { "门缝", "门缝", "怨引值", "怨引", "仇恨" } },
        { lang = "ja", text = "敵視値、敵視重み、敵視、ヘイト。門の隙間と隙間。",
            keys = { "怨引值", "怨引", "仇恨", "仇恨", "门缝", "门缝" } },
        { lang = "en", text = "Phys crit DMG, Physical Crit DMG, Crit DMG; Physical Crit Rate, Phys Crit Rate; ASPD.",
            keys = { "物理暴击伤害", "物理暴击伤害", "暴击伤害", "物理暴击率", "物理暴击率", "攻击速度" } },
        { lang = "ja", text = "物理会心ダメージ、物理会心率、物理会心。防御補正、防御。",
            keys = { "物理暴击伤害", "物理暴击率", "物理暴击率", "护甲加成", "护甲" } },
        { lang = "ko", text = "물리 치명타 피해, 물리 치명 피해, 치명타 피해, 치명 피해; 어그로 수치.",
            keys = { "物理暴击伤害", "物理暴击伤害", "暴击伤害", "暴击伤害", "怨引值" } },
    }) do
        I18n.set(case.lang)
        local layout = kt:_layout(nil, case.text, 10000, 20)
        check(keywordKeys(layout) == table.concat(case.keys, "|"), "alias longest ownership / " .. case.lang .. case.text)
        check(flatten(layout, true) == case.text, "aliases only highlight, never translate / " .. case.lang)
        kt:draw(nil, case.text, 40, 80, 10000, 20, 28)
        check(#kt.hotspots == #case.keys, "alias hotspot count / " .. case.lang)
        for i, key in ipairs(case.keys) do
            local hotspot = kt.hotspots[i]
            check(hotspot.name == key, "alias hotspot original key / " .. key)
            check(kt:handleInput((hotspot.x1 + hotspot.x2) / 2, (hotspot.y1 + hotspot.y2) / 2), "alias click / " .. key)
            local expected = assert(Locale.get(key, case.lang))
            check(kt.popup and kt.popup.key == key and kt.popup.name == expected.title
                and kt.popup.desc == expected.desc, "alias popup original key and localized definition / " .. key)
            kt:closePopup()
        end
    end
    I18n.set("en")
    local wide = kt:_layout(nil, "xx Energy Shield yy", 10000, 20)
    check(keywordKeys(wide) == "能量护盾", "multiword keyword")
    local narrow = kt:_layout(nil, "Energy Shield", 30, 20)
    check(#narrow.lines > 1 and flatten(narrow, false) == "Energy Shield", "oversized keyword UTF-8-safe wrapping")
    for _, line in ipairs(narrow.lines) do
        check(line.width <= 30 + 0.001, "oversized keyword line width")
        for _, piece in ipairs(line.pieces) do check(piece.key == "能量护盾", "wrapped fragments keep key") end
    end
    for _, lang in ipairs({ "zh_CN", "zh_TW", "ja", "ko" }) do
        I18n.set(lang)
        local sample = samples[lang]
        local layout = kt:_layout(nil, sample, 40, 20)
        check(flatten(layout, false) == sample, "UTF-8 narrow wrap roundtrip / " .. lang)
        for _, line in ipairs(layout.lines) do check(line.width <= 40 + 0.001, "CJK line bounded") end
    end
    I18n.set("en")
    local newlines = kt:_layout(nil, "Echo\n\nRift\n", 10000, 20)
    check(#newlines.lines == 4 and flatten(newlines, true) == "Echo\n\nRift\n", "explicit empty/trailing lines")
    local same = kt:_layout(nil, "Echo", 1000, 20)
    check(same == kt:_layout(nil, "Echo", 1000, 20), "cache hit")
    for i = 1, 30 do kt:_layout(nil, "unknown " .. i, 1000, 20) end
    check(#kt._cacheKeys <= 16, "bounded layout cache")
    kt:draw(nil, "Echo", 10, 20, 1000, 20)
    local first = kt.hotspots[1]
    kt:setHover(first.x1 + 1, first.y1 + 1)
    kt:handleInput(first.x1 + 1, first.y1 + 1)
    I18n.set("ja")
    check(not kt:isOpen() and #kt.hotspots == 0 and kt.hoverIdx == nil, "language switch clears popup/hover/hotspots")
    check(not kt:handleInput(first.x1 + 1, first.y1 + 1), "stale locale hotspot cannot consume click")
    kt:draw(nil, "回响", 10, 20, 1000, 20)
    local jp = kt.hotspots[1]
    kt:handleInput(jp.x1 + 1, jp.y1 + 1)
    kt:draw(nil, "裂隙", 10, 20, 1000, 20)
    check(not kt:isOpen() and kt.hotspots[1].name == "裂隙", "new content clears old popup and replaces hotspot")
    kt:setTransform(function(x, y) return x / 2, y / 2 end)
    kt:setPopupTransform(function(x, y) return x * 2, y * 2 end)
    local r = kt.hotspots[1]
    local localX, localY = (r.x1 + r.x2) / 2, (r.y1 + r.y2) / 2
    check(kt:handleInput(localX * 2, localY * 2), "transformed input hits")
    check(kt.popup and kt.popup.cx == localX * 2 and kt.popup.topY == r.y1 * 2, "popup anchor transformed")
    kt:clear()

    -- 显式替换NanoVG函数而不是package.loaded；安装真实I18n hook捕获spy。
    local functions = { "nvgText", "nvgTextBounds", "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgFillColor", "nvgRGBA" }
    local saved, drawn, measured = {}, {}, {}
    for _, name in ipairs(functions) do saved[name] = _G[name] end
    local fontSize = 20
    _G.nvgFontFace = function() end
    _G.nvgFontSize = function(_, size) fontSize = size end
    _G.nvgTextAlign = function() end
    _G.nvgFillColor = function() end
    _G.nvgRGBA = function() return nil end
    _G.nvgText = function(_, x, y, text)
        drawn[#drawn + 1] = { x = x, y = y, text = text }
    end
    _G.nvgTextBounds = function(_, _, _, text)
        measured[#measured + 1] = text
        local width = 0
        for _, code in utf8.codes(text) do width = width + (code <= 127 and fontSize * 0.55 or fontSize) end
        return width
    end
    local ok, err = pcall(function()
        I18n.installDrawHook()
        I18n.set("en")
        local unknown = "甲乙回响丙丁力量戊己"
        check(I18n.lookup(unknown) == unknown, "unknown full source stays unchanged")
        local spyVg = {} --[[@as any]]
        local raw = KeywordText.new()
        local fallback = raw:_layout(nil, unknown, 10000, 20)
        local contextLayout = raw:_layout(spyVg, unknown, 10000, 20)
        check(contextLayout ~= fallback and #measured > 0, "measurement context invalidates fallback cache")
        raw:draw(spyVg, unknown, 0, 0, 10000, 20)
        local textPieces = {}
        for _, item in ipairs(drawn) do textPieces[#textPieces + 1] = item.text end
        check(table.concat(textPieces) == unknown, "raw segments bypass substring draw hook")
        local hs = raw.hotspots[1]
        local strength = raw.hotspots[2]
        check(keywordKeys(contextLayout) == "回响|力量" and #raw.hotspots == 2,
            "unknown full source highlights old/new keywords in source order")
        check(hs and hs.name == "回响" and hs.text == "回响", "unknown source preserves keyword display")
        check(strength and strength.name == "力量" and strength.text == "力量", "unknown source preserves new stat display")
        check(hs and math.abs(hs.x2 - hs.x1 - 40) < 0.001, "raw keyword width equals displayed source width")
        check(strength and math.abs(strength.x2 - strength.x1 - 40) < 0.001, "raw new stat width equals displayed source width")
        for _, text in ipairs(measured) do
            check(not text:find("Echo", 1, true) and not text:find("STR", 1, true),
                "raw measurements do not translate old/new fragments")
        end
        raw:handleInput((strength.x1 + strength.x2) / 2, (strength.y1 + strength.y2) / 2)
        check(raw.popup and raw.popup.key == "力量" and raw.popup.desc == Locale.get("力量", "en").desc,
            "raw new stat click uses original key, not retranslated fragment")
        raw:closePopup()
        drawn = {}
        raw:draw(spyVg, KW.get("回响").desc, 0, 0, 10000, 20)
        textPieces = {}
        for _, item in ipairs(drawn) do textPieces[#textPieces + 1] = item.text end
        local expected = assert(Locale.lookup(KW.get("回响").desc, "en")):gsub("\n", "")
        check(table.concat(textPieces) == expected, "translated full source rendered exactly once")
    end)
    for _, name in ipairs(functions) do _G[name] = saved[name] end
    I18n.set(originalLang)
    if not ok then error(err) end
    for key, def in pairs(KW.KEYWORDS) do
        check(def.title == savedDefs[key].title and def.desc == savedDefs[key].desc, "config unchanged / " .. key)
    end
    print("I18N KEYWORD LOCALE: ALL PASS; checks=" .. checks .. "; keywords=" .. count .. "; localized_fields=" .. fields .. "; set_desc_cases=" .. setCases)
    return { checks = checks, keywords = count, localizedFields = fields, setDescCases = setCases }
end

function Start()
    local ok, err = pcall(T.run)
    if not ok then
        print("I18N KEYWORD LOCALE: FAIL " .. tostring(err))
        log:Write(LOG_ERROR, "[i18n_keyword_locale_test] " .. tostring(err))
    end
    engine:Exit()
end
