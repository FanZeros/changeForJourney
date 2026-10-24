-- 三传说六条新增正文：独立真实NanoVG/Noto字体专项，不加载main，不读写玩家档。
-- 基于scaffold-2d的Start/Stop + NanoVGRender；实际Viewport右栏设计缩放，非等宽测量桩。
-- -awakening-font-baseline仅测原36号，打印溢出证据；默认验证真实Panel.draw最终字号/全文/关键词。
-- File/FileSystem封闭；唯一业务替身为显式owned fixture，点击声音边界静音。没有GPU截图/设备验收声明。
local TAG = "[legendary_awakening_text_font] "
local totals = { assertions = 0, failed = 0, samples = 0, glyphs = 0, hotspots = 0, overflow = 0, renders = 0 }
---@type NVGContextWrapper?
local vg = nil
local finished, cleaned, baseline = false, false, false
local patches = {} ---@type table[]
local ioCalls = 0
local fixture = { shards = 150, awakening = { _awk3Migrated = true }, extraTalent = {} }
local current = {} ---@type table
local modules = {} ---@type table
local BODY_X, BODY_Y, BODY_W, BODY_BOTTOM = 85, 1893.5, 910, 2110 - 12
local LANGS = { "zh_CN", "zh_TW", "en", "ja", "ko" }
local HEROES = { 16, 20, 25 }
local SIZES = { { 1920, 1080 }, { 1280, 720 } }

local function check(ok, message)
    totals.assertions = totals.assertions + 1
    if not ok then totals.failed = totals.failed + 1; print(TAG .. "FAIL " .. message) end
end
local function patch(target, key, value)
    patches[#patches + 1] = { target = target, key = key, previous = target[key] }
    rawset(target, key, value)
end
local function denyIO(...)
    ioCalls = ioCalls + 1
    error("awakening font test forbids File/FS access: " .. tostring(select(1, ...)))
end
local function sealIO()
    patch(_G, "File", denyIO)
    patch(_G, "FileSystem", denyIO)
    patch(_G, "fileSystem", setmetatable({}, { __index = function() return denyIO end }))
    patch(_G, "GetFileSystem", denyIO)
end
local function cleanup()
    if cleaned then return end
    cleaned = true
    if modules.Panel then modules.Panel.kwText:clear(); modules.Panel.setOwnedDataGetter(nil) end
    if modules.I18n then modules.I18n.set(modules.language) end
    for i = #patches, 1, -1 do
        local item = patches[i]
        rawset(item.target, item.key, item.previous)
    end
    patches = {}
end

local function prepare()
    -- 封闭必须早于任何用户模块require；引擎资源缓存仍能加载正式字体/源码/图片。
    sealIO()
    modules.I18n = require("core.I18n")
    modules.language = modules.I18n.get()
    modules.Config = require("config.AwakeningConfig")
    modules.Extra = require("core.I18nDictExtra")
    modules.Keyword = require("ui.widget.KeywordText")
    modules.Viewport = require("core.Viewport")
    modules.Panel = require("ui.character.hero.AwakeningPanel")
    modules.Panel.setOwnedDataGetter(function() return fixture end)
    modules.Panel.initImages(vg)
    local sounds = require("systems.GameSFX")
    patch(sounds, "play", function() end) -- 关键词点击声音，不替换文字/热区/输入实现。
    local displayText = modules.I18n.displayText
    patch(modules.I18n, "displayText", function(ctx, x, y, text, endp)
        if current.capturing then
            local bounds = {}
            local advance = modules.I18n.displayBounds(ctx, x, y, text, bounds)
            current.glyphs[#current.glyphs + 1] = { text = text, bounds = bounds, advance = advance }
            totals.glyphs = totals.glyphs + 1
        end
        return displayText(ctx, x, y, text, endp) -- 真绘制，不替换nvgText/Bounds或字体。
    end)
    local draw = modules.Panel.kwText.draw
    patch(modules.Panel.kwText, "draw", function(self, ctx, text, x, y, width, size, lh, cx)
        current = { text = text, x = x, y = y, width = width, font = size, cx = cx,
            glyphs = {}, capturing = true }
        local h = draw(self, ctx, text, x, y, width, size, lh, cx)
        current.capturing, current.height = false, h
        return h
    end)
end

local function translated(source, lang)
    local expected = lang == "zh_CN" and source or modules.Extra[lang][source]
    check(type(expected) == "string" and expected ~= "", lang .. "新增正文有明确整句词典")
    check(modules.I18n.lookup(source) == expected, lang .. "真实I18n采用当前整句译文")
    return expected
end

local function baselineSample(heroId, stage, lang)
    local source = assert(modules.Config.getNodeEffect(heroId, stage))
    local expected = translated(source, lang)
    local keyword = modules.Keyword.new()
    local height, lines = keyword:measureHeight(vg, source, BODY_W, 36)
    current = { capturing = true, glyphs = {} }
    local drawn = keyword:draw(vg, source, BODY_X, BODY_Y, BODY_W, 36, nil, 540)
    current.capturing = false
    check(height == drawn and height > 0, "baseline真实测量/绘制高度一致")
    local fragments, bottom = {}, BODY_Y
    for _, glyph in ipairs(current.glyphs) do
        fragments[#fragments + 1] = glyph.text
        check(#glyph.bounds == 4, "baseline真实字墨bounds存在")
        bottom = math.max(bottom, glyph.bounds[4] or BODY_Y)
    end
    check(table.concat(fragments) == expected, "baseline保留整句所有字符")
    local overflow = BODY_Y + height > BODY_BOTTOM or bottom > BODY_BOTTOM
    if overflow then totals.overflow = totals.overflow + 1 end
    totals.samples = totals.samples + 1
    print(TAG .. "BASELINE lang=" .. lang .. " hero=" .. heroId .. " stage=" .. stage
        .. " font=36 lines=" .. lines .. " h=" .. height .. " inkBottom=" .. bottom
        .. " available=" .. (BODY_BOTTOM - BODY_Y) .. " overflow=" .. tostring(overflow))
end

local function finalSample(heroId, stage, lang, label, short)
    local Panel = modules.Panel
    local source = assert(modules.Config.getNodeEffect(heroId, stage))
    local expected = short and modules.I18n.lookup(source) or translated(source, lang)
    Panel.reset(heroId)
    check(Panel.handleInput(204 + (stage - 1) * 336, 1056, heroId), label .. "真实切片选择")
    Panel.draw(vg, heroId)
    check(current.text == source and current.x == BODY_X and current.y == BODY_Y
        and current.width == BODY_W and current.cx == 540,
        label .. "源正文/1893.5锚点/910宽/居中不变")
    check(Panel.BTN_CX == 720 and Panel.BTN_CY == 2160 and Panel.BTN_W == 520 and Panel.BTN_H == 100,
        label .. "按钮位置尺寸完全不变")
    local reference = modules.Keyword.new()
    local height, lines = reference:measureHeight(vg, source, BODY_W, current.font)
    local original = reference:measureHeight(vg, source, BODY_W, 36)
    check(current.font >= 18 and current.font <= 36 and current.height == height
        and BODY_Y + height <= BODY_BOTTOM, label .. "最终真实字号/高度留12px按钮间距")
    check((original <= BODY_BOTTOM - BODY_Y and current.font == 36)
        or (original > BODY_BOTTOM - BODY_Y and current.font < 36), label .. "只对确实溢出正文缩号")
    if current.font < 36 then
        check(reference:measureHeight(vg, source, BODY_W, current.font + 1) > BODY_BOTTOM - BODY_Y,
            label .. "整数最大可用字号，不多缩")
    end
    if short then check(current.font == 36, label .. "原短正文保持36号") end
    local fragments, bottom = {}, BODY_Y
    for _, glyph in ipairs(current.glyphs) do
        fragments[#fragments + 1] = glyph.text
        check(#glyph.bounds == 4 and glyph.bounds[1] >= BODY_X - 0.01
            and glyph.bounds[3] <= BODY_X + BODY_W + 0.01 and glyph.bounds[2] >= BODY_Y - 0.01
            and glyph.bounds[4] <= BODY_BOTTOM + 0.01, label .. "真实字墨逐段留在正文安全区")
        bottom = math.max(bottom, glyph.bounds[4] or BODY_Y)
    end
    check(#current.glyphs > 0 and table.concat(fragments) == expected,
        label .. "实际绘制全文逐字符相等，不截断省略")
    local layout = reference:_layout(vg, source, BODY_W, current.font)
    local keywords = 0
    for _, line in ipairs(layout.lines) do
        for _, piece in ipairs(line.pieces) do if piece.keyword then keywords = keywords + 1 end end
    end
    check(#Panel.kwText.hotspots == keywords, label .. "所有原关键词片段保留热点")
    for _, hit in ipairs(Panel.kwText.hotspots) do
        totals.hotspots = totals.hotspots + 1
        check(hit.x1 >= BODY_X and hit.x2 <= BODY_X + BODY_W and hit.y1 >= BODY_Y
            and hit.y2 + 4 < 2110 and hit.y2 <= BODY_BOTTOM,
            label .. "关键词热点及4px点击宽容不进入按钮")
        local popup = Panel.handleInput((hit.x1 + hit.x2) * 0.5, (hit.y1 + hit.y2) * 0.5, heroId)
        check(popup and Panel.kwText.popup and Panel.kwText.popup.key == hit.key,
            label .. "真实Panel输入仍打开该关键词")
        Panel.kwText:closePopup()
    end
    totals.samples = totals.samples + 1
    print(TAG .. "FIT " .. label .. " font=" .. current.font .. " originalH=" .. original
        .. " lines=" .. lines .. " h=" .. height .. " inkBottom=" .. bottom .. " keywords=" .. keywords)
end

function Start()
    for _, arg in ipairs(GetArguments()) do if arg == "-awakening-font-baseline" then baseline = true end end
    local ok, err = xpcall(function()
        vg = assert(nvgCreate(1), "real NanoVG context required")
        check(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0, "exact native multilingual sans font")
        check(nvgFindFont(vg, "sans-bold") < 0, "不借UI私有sans-bold或其他字体替代")
        prepare()
        SubscribeToEvent(vg, "NanoVGRender", "HandleLegendaryAwakeningFontRender")
    end, debug.traceback)
    if not ok then check(false, "Start " .. tostring(err)); cleanup(); finished = true; engine:Exit() end
end

function HandleLegendaryAwakeningFontRender()
    if finished or not vg then return end
    local index = totals.renders + 1
    local size = SIZES[index]
    if not size then return end
    totals.renders = index
    -- 模式A，来自实际横屏Viewport.layout×DS；frame物理尺寸以逻辑/DPR1明确指定。
    nvgBeginFrame(vg, size[1], size[2], 1)
    nvgSave(vg)
    local ox, oy, scale = modules.Viewport.layout(size[1], size[2])
    nvgTranslate(vg, ox + modules.Viewport.PANELS.right.bx * scale, oy)
    nvgScale(vg, scale * modules.Viewport.DS, scale * modules.Viewport.DS)
    local ok, err = xpcall(function()
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 36)
        local bounds = {}
        check(nvgTextBounds(vg, 0, 0, "W国i", bounds) > 0 and #bounds == 4,
            "实际frame中原生字体返回字墨边界")
        check(nvgTextBounds(vg, 0, 0, "WWW") > nvgTextBounds(vg, 0, 0, "iii") * 2,
            "真实比例字体非等宽mock")
        for _, lang in ipairs(LANGS) do
            check(modules.I18n.set(lang), "真实语言切换 " .. lang)
            for _, heroId in ipairs(HEROES) do
                for stage = 2, 3 do
                    local label = size[1] .. "x" .. size[2] .. " " .. lang .. " H" .. heroId .. "/" .. stage
                    if baseline then baselineSample(heroId, stage, lang)
                    else finalSample(heroId, stage, lang, label, false) end
                end
            end
            if not baseline then
                for _, heroId in ipairs({ 1, 6, 12 }) do
                    finalSample(heroId, 1, lang, size[1] .. " " .. lang .. " shortH" .. heroId, true)
                end
            end
        end
    end, debug.traceback)
    nvgRestore(vg)
    nvgEndFrame(vg)
    if not ok then check(false, "harness " .. tostring(err)) end
    if baseline or index == #SIZES or not ok then
        check(ioCalls == 0, "独立Runtime全部File/FS请求0，无玩家档IO")
        check(totals.samples == (baseline and 30 or 90), "五语六新增正文及原短文完整测绘覆盖")
        finished = true
        cleanup()
        print(TAG .. "FINAL " .. (totals.failed == 0 and "ALL PASS" or "FAILED")
            .. " baseline=" .. tostring(baseline) .. " assertions=" .. totals.assertions .. " failed=" .. totals.failed
            .. " samples=" .. totals.samples .. " glyphs=" .. totals.glyphs .. " hotspots=" .. totals.hotspots
            .. " overflow=" .. totals.overflow .. " renders=" .. totals.renders .. " FileFS=" .. ioCalls)
        engine:Exit()
    end
end

function Stop()
    cleanup()
    if vg then nvgDelete(vg); vg = nil end
    print(TAG .. "STOP finished=" .. tostring(finished) .. " failed=" .. totals.failed)
end
