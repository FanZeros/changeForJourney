-- 独立关键词五语回归：官方Runtime执行Start+pcall+engine:Exit；不预注入package.loaded。
-- 入口 tests/i18n_keyword_locale_test.lua；无GPU，用显式NanoVG spy验证raw边界与几何。
local T = {}

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
    local savedDefs = {}
    for key, def in pairs(KW.KEYWORDS) do
        savedDefs[key] = { title = def.title, desc = def.desc }
        count = count + 1
        for _, lang in ipairs({ "zh_TW", "en", "ja", "ko" }) do
            local translated = assert(Locale.get(key, lang))
            check(translated.title ~= "" and translated.desc ~= "", key .. "/" .. lang .. " nonempty")
            check(Locale.lookup(def.title, lang) == translated.title, "title exact lookup")
            check(Locale.lookup(def.desc, lang) == translated.desc, "desc exact lookup")
            check(sameNumbers(def.desc, translated.desc), key .. "/" .. lang .. " numbers")
            local _, n1 = def.desc:gsub("\n", "")
            local _, n2 = translated.desc:gsub("\n", "")
            check(n1 == n2, key .. "/" .. lang .. " paragraphs")
            fields = fields + 2
        end
    end
    check(count == 25 and fields == 200, "25 keywords / 200 localized title+desc fields")
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
        check(hs and hs.name == "回响" and hs.text == "回响", "unknown source preserves keyword display")
        check(hs and math.abs(hs.x2 - hs.x1 - 40) < 0.001, "raw keyword width equals displayed source width")
        for _, text in ipairs(measured) do check(not text:find("Echo", 1, true), "raw measurements do not translate fragments") end
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
