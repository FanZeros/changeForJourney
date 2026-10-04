-- 角色详情真实布局回归：不启动游戏、不访问玩家存档、不发送操作。
-- 基于scaffold-2d / 01-nanovg-standalone生命周期，沿用生产模式A、1080x2400和字体。
-- Runtime位置参数直接指定本测试；不要修改游戏main入口。
local HC = require("config.HeroConfig")
local CC = require("config.ClassConfig")
local Attrs = require("ui.character.detail.CharacterDetailAttrs")
local View = require("ui.character.detail.CharacterAttributeView")
local Stats = require("ui.character.detail.CharacterEquipStats")
local KeywordText = require("ui.widget.KeywordText")
local ETS = require("systems.ExtraTalentSystem")
local Draw = require("ui.character.detail.CharacterDetailDraw")
local DrawUtil = require("core.DrawUtil")
local Viewport = require("core.Viewport")

local M = {}
local PREFIX = "[character_detail_layout_test]"
local assertions, failures, renderCount = 0, 0, 0
---@type NVGContextWrapper?
local canvas = nil
local finished = false
local cards, icons = {}, {}

local function check(ok, message)
    assertions = assertions + 1
    if ok then print(PREFIX .. " PASS " .. message)
    else failures = failures + 1; print(PREFIX .. " FAIL " .. message) end
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.05 end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function shortHero()
    for _, id in ipairs(HC.getAllIds()) do
        if HC.get(id).name == "老六" then return id end
    end
    error("HeroConfig未找到截图角色老六")
end
local function longestHero()
    local longest, length = 0, -1
    for _, id in ipairs(HC.getAllIds()) do
        local count = utf8.len(HC.get(id).talentDesc or "") or 0
        if count > length then longest, length = id, count end
    end
    return longest
end

-- 可删除的截图入口复用同一fixture，无须另建永久测试。
-- 属性通过真实HC/CharacterDetailAttrs显式快照API计算。
function M.fixture(heroId, opts)
    opts = opts or {}
    local own = {
        level = opts.level or 70, exp = opts.longExp and 123456789012345 or 38,
        maxExp = opts.longExp and 987654321098765 or 100,
        awakening = opts.awakened and { [1] = true, [2] = true, [3] = true } or {},
        extraTalent = ETS.normalize({ stacks = 12345, burnKills = 6789, iceStatues = 3,
            splitKills = 1234, issuedCards = 88, preciseStored = 5, blockBank = 99999,
            conquerCarry = 15, shockKills = 8888, beamCharges = 3, overflowCount = 54321,
            shareCount = 9000, slashShadows = 4, nitroKills = 56789, gatlingKills = 2345,
            swordStacks = 4321, gateStacks = 7654, shieldStacks = 999999,
            biteTypes = { slash = true, crush = true, fire = true },
            markTypes = { slash = true, frost = true }, tickets = { fixture = true } }),
    }
    local snapshots = {
        heroes = { roster = { [tostring(heroId)] = own }, deployed = {} },
        equipment = { inventory = {}, equipped = {}, nextSeq = 100 }, artifacts = { bag = {} },
    }
    local state = { open = true, heroId = heroId, tab = "attr", tabFrom = "attr",
        openTime = time.elapsedTime - 10, tabSwitchTime = time.elapsedTime - 10,
        attrScrollY = opts.scroll or 0, attrScrollVel = 0, attrDragging = false,
        cardDragVisual = 0, cachedLeft = {}, cachedRight = {}, attrHits = {} }
    return { heroId = heroId, own = own, snapshots = snapshots, state = state,
        longClass = opts.longClass == true, longValues = opts.longValues == true,
        hits = { own = 0, attrs = 0, power = 0, roster = 0, clamp = 0,
            awakening = 0, panel = 0, church = 0, class = 0, keyword = 0, rows = 0 } }
end
M.shortHero = shortHero
M.longestHero = longestHero

-- 保存setContext实际upvalue（包括nil），不初始化生产UI。
local function savedContext()
    local fieldFor = { detailState = "detailState", getOwnedData = "getOwnedData",
        calcHeroPowerFn = "calcHeroPower", calcHeroEstimateFn = "calcHeroEstimate",
        CharacterDetailRef = "CharacterDetail", collectAttributes = "collectAttributes",
        clampAttrScroll = "clampAttrScroll", imgHeroCards = "imgHeroCards",
        imgClassIcons = "imgClassIcons", imgPower = "imgPower", imgLvlBadge = "imgLvlBadge" }
    local saved = {}
    for i = 1, 30 do
        local name, value = debug.getupvalue(Draw.setContext, i)
        if not name then break end
        if fieldFor[name] then saved[fieldFor[name]] = value end
    end
    return saved
end

-- 替换仅存活于词法作用域：成功、主动失败与真实异常均恢复。
-- require钩子仅隔离动态CP拥有数据与教堂角标，不碰玩家存档。
-- Draw/View/KeywordText/HC/Attrs/ETS/NanoVG测量均保留真实实现。
local function isolated(fixture, body)
    local restores = {}
    local function patch(target, key, replacement)
        local previous = target[key]
        restores[#restores + 1] = function() target[key] = previous end
        target[key] = replacement
    end
    local oldContext = savedContext()
    local keyword = KeywordText.new()
    patch(Draw, "talentKwText", keyword)
    local oldRequire = require
    local fakePanel = { getOwnedHero = function(id)
        fixture.hits.panel = fixture.hits.panel + 1
        assert(id == fixture.heroId, "拥有数据请求了隔离fixture外角色")
        return fixture.own
    end }
    local fakeChurch = { hasAdvanceForHero = function(id)
        fixture.hits.church = fixture.hits.church + 1
        assert(id == fixture.heroId, "教堂角标请求了隔离fixture外角色")
        return false
    end }
    patch(_G, "require", function(name)
        if name == "ui.character.panel.CharacterPanel" then return fakePanel end
        if name == "ui.church.ChurchPage" then return fakeChurch end
        return oldRequire(name)
    end)
    if fixture.longClass then
        local getClass = CC.get
        patch(CC, "get", function(id)
            fixture.hits.class = fixture.hits.class + 1
            local cfg = assert(getClass(id))
            local result = copy(cfg)
            result.name = "The exceptionally translated master of eternal silent shadow guardians"
            return result
        end)
    end
    local context = {
        detailState = fixture.state, imgHeroCards = cards, imgClassIcons = icons,
        getOwnedData = function(id)
            fixture.hits.own = fixture.hits.own + 1
            assert(id == fixture.heroId, "getOwnedData请求了隔离fixture外角色")
            return fixture.own
        end,
        calcHeroPower = function(id)
            fixture.hits.power = fixture.hits.power + 1
            assert(id == fixture.heroId, "战力请求了隔离fixture外角色")
            return 31415
        end,
        collectAttributes = function(id, cfg, level)
            fixture.hits.attrs = fixture.hits.attrs + 1
            assert(id == fixture.heroId and cfg == HC.get(id) and level == fixture.own.level,
                "Draw必须传真实HC配置与fixture等级给属性收集器")
            local attrs = Attrs.collectAttributes(id, cfg, level, fixture.snapshots)
            if fixture.longValues then
                attrs.left[1].value = "123456789012345678901234567890%"
                attrs.left[1].name = "最大生命值"
                for key in pairs(attrs.stats) do attrs.stats[key] = 123456789012345 end
            end
            return attrs
        end,
        clampAttrScroll = function()
            fixture.hits.clamp = fixture.hits.clamp + 1
            local state = fixture.state
            state.attrScrollY = math.max(0, math.min(state.attrScrollMax or 100000, state.attrScrollY))
        end,
        CharacterDetail = {
            _getHeroRoster = function()
                fixture.hits.roster = fixture.hits.roster + 1
                return { { heroId = fixture.heroId, owned = true } }
            end,
            hasAwakeningUpgrade = function(id)
                fixture.hits.awakening = fixture.hits.awakening + 1
                assert(id == fixture.heroId)
                return false
            end, _imgIconUp = -1,
        },
    }
    Draw.setContext(context)
    Draw.markPowerDirty()
    local ok, result = xpcall(function() return body(keyword, patch) end, debug.traceback)
    for i = #restores, 1, -1 do restores[i]() end
    Draw.setContext(oldContext)
    Draw.markPowerDirty()
    return ok, result
end

-- 透传探针：记录的文本、路径、图片仍真正提交NanoVG。
-- 每次真实nvgText之前，按最终字体/对齐测量墨迹边界。
local function probe(vg, patch)
    local calls = { texts = {}, rects = {}, images = {}, scissors = {}, circles = {}, points = {},
        measures = 0, keyword = nil, rows = nil }
    local font, align = 0, 0
    local textBounds = nvgTextBounds
    local function wrap(name, record)
        local native = _G[name]
        patch(_G, name, function(...)
            record(...)
            return native(...)
        end)
    end
    wrap("nvgFontSize", function(_, size) font = size end)
    wrap("nvgTextAlign", function(_, value) align = value end)
    wrap("nvgTextBounds", function() calls.measures = calls.measures + 1 end)
    wrap("nvgText", function(_, x, y, text)
        local bounds = {}
        local width = textBounds(vg, x, y, text, bounds)
        calls.texts[#calls.texts + 1] = { x = x, y = y, text = text, font = font,
            align = align, width = width, bounds = bounds }
    end)
    wrap("nvgRoundedRect", function(_, x, y, w, h)
        calls.rects[#calls.rects + 1] = { x = x, y = y, w = w, h = h }
    end)
    wrap("nvgImagePattern", function(_, x, y, w, h, _, image)
        calls.images[#calls.images + 1] = { x = x, y = y, w = w, h = h, image = image }
    end)
    wrap("nvgIntersectScissor", function(_, x, y, w, h)
        calls.scissors[#calls.scissors + 1] = { x = x, y = y, w = w, h = h }
    end)
    wrap("nvgCircle", function(_, x, y, r)
        calls.circles[#calls.circles + 1] = { x = x, y = y, r = r }
    end)
    for _, name in ipairs({ "nvgMoveTo", "nvgLineTo" }) do
        wrap(name, function(_, x, y) calls.points[#calls.points + 1] = { x = x, y = y } end)
    end
    return calls
end
local function matching(array, predicate)
    for _, call in ipairs(array) do if predicate(call) then return call end end
    return nil
end
local function textAt(calls, text, y)
    local result = nil
    for _, call in ipairs(calls.texts) do
        if call.text == text and near(call.y, y) then result = call end
    end
    return result
end
local function fits(c, x, right)
    if not c or not c.width or c.width <= 0 or #c.bounds ~= 4 then return false end
    -- 引擎字体墨迹边缘含约2px抗锯齿/字形外伸，允许3px；不允许排版越界。
    return c.bounds[1] >= x - 3 and c.bounds[3] <= right + 3
end
local function geometry(array, x, y, w, h)
    return matching(array, function(c)
        return near(c.x, x) and near(c.y, y) and near(c.w, w) and near(c.h, h)
    end)
end
local function safeRun(label, body)
    local ok, err = xpcall(body, debug.traceback)
    if not ok then check(false, label .. " 测试异常: " .. tostring(err)) end
end

local function verifyDraw(vg, fixture, label)
    local previous = { requireFn = require, class = CC.get, keyword = Draw.talentKwText,
        font = nvgFontSize, text = nvgText, rows = Draw.drawAttributeRows }
    local ok, result = isolated(fixture, function(keyword, patch)
        local calls = probe(vg, patch)
        local backDraw = DrawUtil.drawBackChevron
        patch(DrawUtil, "drawBackChevron", function(ctx, cx, cy, w, h, direction)
            calls.back = { x = cx - w * 0.5, y = cy - h * 0.5, w = w, h = h }
            return backDraw(ctx, cx, cy, w, h, direction)
        end)
        local drawKw = keyword.draw
        patch(keyword, "draw", function(self, ctx, text, x, y, width, size, lh, cx)
            fixture.hits.keyword = fixture.hits.keyword + 1
            local height = drawKw(self, ctx, text, x, y, width, size, lh, cx)
            calls.keyword = { text = text, x = x, y = y, w = width, font = size, h = height }
            return height
        end)
        local drawRows = Draw.drawAttributeRows
        patch(Draw, "drawAttributeRows", function(ctx, rows, scroll, layout, options)
            fixture.hits.rows = fixture.hits.rows + 1
            local maxScroll, hits = drawRows(ctx, rows, scroll, layout, options)
            calls.rows = { rows = rows, maxScroll = maxScroll, hits = hits, layout = layout,
                style = options.style }
            return maxScroll, hits
        end)
        Draw.draw(vg)
        check(fixture.hits.own >= 2 and fixture.hits.attrs == 1 and fixture.hits.power == 1,
            label .. " 真实Draw命中隔离拥有数据/属性/战力")
        check(fixture.hits.roster > 0 and fixture.hits.awakening == 1
            and fixture.hits.panel > 0 and fixture.hits.church == 1,
            label .. " 名册/觉醒/教堂等所有动态替身确实命中")
        check(fixture.hits.keyword == 1 and fixture.hits.rows == 1 and calls.measures > 20,
            label .. " 真实KeywordText/AttributeView和引擎字体测量执行")
        if fixture.longClass then check(fixture.hits.class > 0, label .. " 超长职业翻译替身命中") end
        if fixture.state.attrScrollVel ~= 0 then check(fixture.hits.clamp > 0, label .. " 惯性滚动clamp替身命中") end
        check(geometry(calls.rects, 94, 958, 300, 64) ~= nil, label .. " 真实职业框中心244,990，尺寸300x64")
        check(geometry(calls.images, 415, 963, 590, 54) ~= nil, label .. " 真实经验贴图中心710,990，尺寸590x54")
        check(calls.back and near(calls.back.x, 50) and near(calls.back.y, 835)
            and near(calls.back.w, 144) and near(calls.back.h, 100)
            and calls.back.y + calls.back.h < 958 and calls.back.y + calls.back.h < 1070,
            label .. " 非三行属性页真实返回箭头122,885 144x100，不遮职业或前两行")
        local oldFirst, oldSecond = View.rowAt(fixture.state.attrHits, 205, 1109), View.rowAt(fixture.state.attrHits, 205, 1197)
        check(oldFirst and oldSecond and not Stats.contains(calls.back, 205, 1109)
            and not Stats.contains(calls.back, 205, 1197), label .. " 旧返回区域两点现在属于属性行，不命中新返回矩形")
        check(geometry(calls.scissors, 40, 1070, 500, 874) ~= nil, label .. " 真实属性裁剪区40,1070,500,874")
        check(calls.rows.layout == View.ATTRIBUTE_LAYOUT and calls.rows.style == View.ATTRIBUTE_STYLE,
            label .. " Draw共用真实属性布局和40号字体风格")
        check(#fixture.state.attrHits == 10 and fixture.state.attrHits[1].index == 1
            and fixture.state.attrHits[10].index == 10,
            label .. " 首屏恰好十条属性可见")
        local allInClip = true
        for _, hit in ipairs(fixture.state.attrHits) do
            allInClip = allInClip and hit.y >= 1070 and hit.y + hit.h <= 1944 and hit.h > 0
        end
        check(allInClip and #calls.rows.rows > 10 and calls.rows.maxScroll > 0,
            label .. " 热区均裁剪，更多真实属性可继续滚动")
        check(near(fixture.state.attrHits[1].y, 1070) and near(fixture.state.attrHits[10].y, 1862)
            and near(fixture.state.attrHits[10].h, 78), label .. " 第十行1862..1940完整可见")
        check(textAt(calls, fixture.state.attrHits[1].name, 1109) ~= nil,
            label .. " 首行名称真实绘制于1109")
        local classText
        for _, c in ipairs(calls.texts) do
            if near(c.y, 990) and not c.text:find("^Lv%.") then classText = c end
        end
        local exp = "Lv." .. fixture.own.level .. "  " .. math.floor(fixture.own.exp)
            .. "/" .. math.floor(fixture.own.maxExp)
        local expText = textAt(calls, exp, 990)
        check(fits(classText, 94, 394) and fits(expText, 415, 1005),
            label .. " 最终墨迹边界留在分开的职业/经验框内")
        local framedTextFits = true
        for _, c in ipairs(calls.texts) do
            if c.text == exp or (classText and c.text == classText.text and math.abs(c.y - 990) <= 5) then
                local left, right = c.text == exp and 415 or 94, c.text == exp and 1005 or 394
                framedTextFits = framedTextFits and fits(c, left, right)
            end
        end
        check(framedTextFits, label .. " 职业与经验所有描边墨迹也不越界")
        if fixture.longClass then check(classText.font < 34, label .. " 超长职业翻译确实缩字") end
        if fixture.own.exp > 100000 then check(expText.font < 28, label .. " 超长经验确实缩字") end
        local center = matching(calls.circles, function(c) return near(c.x, 800) and near(c.y, 1507) and near(c.r, 5) end)
        local outer = matching(calls.points, function(c) return near(c.x, 800) and near(c.y, 1312) end)
        local labelText = textAt(calls, "力量", 1243)
        check(center and outer and labelText and near(labelText.x, 800),
            label .. " 真实雷达中心cy1507、半径195、标签半径238")
        local kw = assert(calls.keyword)
        local title = textAt(calls, HC.get(fixture.heroId).talentName .. "：", 2012)
        check(title and near(title.x, 105) and near(title.font, 40), label .. " 真实天赋标题y2012，40号字体")
        check(near(kw.x, 105) and near(kw.y, 2048) and near(kw.w, 870),
            label .. " 真实KeywordText起点2048、折行宽870")
        check(kw.h <= 172 and kw.font >= 18 and kw.font <= 34 and kw.y + kw.h <= 2220,
            label .. " 天赋适配172高，不进入底部页签顶2236.5")
        check(keyword:lastHeight() == kw.h, label .. " 高度来自真实draw而非仅查静态常量")
        local hotOK = true
        for _, h in ipairs(keyword.hotspots) do
            hotOK = hotOK and h.x1 >= 104 and h.x2 <= 976 and h.y1 >= 2048 and h.y2 <= 2220
        end
        if not hotOK then
            for _, h in ipairs(keyword.hotspots) do print(PREFIX .. " HOT " .. h.name .. " " .. h.x1 .. "," .. h.y1 .. "," .. h.x2 .. "," .. h.y2) end
        end
        check(hotOK and (fixture.heroId ~= shortHero() or #keyword.hotspots > 0),
            label .. " 真实关键词热区适配最终字号和边界")
        local glyphOK = true
        for _, c in ipairs(calls.texts) do
            if c.y >= 2048 and c.y < 2236.5 then
                glyphOK = glyphOK and fits(c, 105, 975) and #c.bounds == 4 and c.bounds[4] < 2236.5
                if not fits(c, 105, 975) or c.bounds[4] >= 2236.5 then
                    print(PREFIX .. " GLYPH " .. label .. " text=" .. c.text .. " x=" .. c.x .. " y=" .. c.y
                        .. " font=" .. c.font .. " bounds=" .. table.concat(c.bounds, ","))
                end
            end
        end
        check(glyphOK, label .. " 天赋真实墨迹边界在页签顶部之上")
        check(textAt(calls, "属性", 2302) ~= nil and textAt(calls, "配装", 2302) ~= nil,
            label .. " 完整draw包含底部页签")
        if fixture.longValues then
            local row = fixture.state.cachedLeft[1]
            local nameCall = textAt(calls, row.name, 1109)
            local valueCall = textAt(calls, row.value, 1109)
            if nameCall and valueCall then
                print(PREFIX .. " VALUE name=" .. table.concat(nameCall.bounds, ",")
                    .. " value=" .. table.concat(valueCall.bounds, ",") .. " font=" .. valueCall.font)
            end
            check(nameCall and valueCall and valueCall.font < 40
                and nameCall.bounds[3] < valueCall.bounds[1] and fits(valueCall, 150, 520),
                label .. " 极长属性值缩字，名称/数值墨迹不重叠")
            local radarFits = true
            for _, c in ipairs(calls.texts) do
                if c.text == tostring(123456789012345) and c.y > 1100 and c.y < 1900 then
                    radarFits = radarFits and fits(c, 540, 1080)
                    if not fits(c, 540, 1080) then print(PREFIX .. " RADAR " .. c.x .. "," .. c.y .. " " .. table.concat(c.bounds, ",")) end
                end
            end
            check(radarFits, label .. " 极长雷达数字墨迹留在右列")
        end
        print(PREFIX .. " DRAW " .. label .. " hero=" .. fixture.heroId .. " rows=" .. #calls.rows.rows
            .. " talentFont=" .. kw.font .. " talentHeight=" .. kw.h)
        return calls
    end)
    check(ok, label .. " 完整真实draw成功" .. (ok and "" or (": " .. tostring(result))))
    check(require == previous.requireFn and CC.get == previous.class and Draw.talentKwText == previous.keyword
        and nvgFontSize == previous.font and nvgText == previous.text and Draw.drawAttributeRows == previous.rows,
        label .. " 成功路径恢复全部替换函数")
    return ok and result or nil
end

local function verifyScroll(vg)
    local fixture = M.fixture(shortHero())
    local ok, err = isolated(fixture, function()
        Draw.draw(vg)
        local state = fixture.state
        local maxScroll, rows = state.attrScrollMax, state.cachedLeft
        state.attrScrollY = 19
        Draw.draw(vg)
        local first = state.attrHits[1]
        check(first.index == 1 and near(first.y, 1070) and near(first.h, 59), " 滚动后首行可见片段高59")
        local row, index = View.rowAt(state.attrHits, 200, 1070.1)
        check(row == rows[1] or (row.key == rows[1].key and index == 1), "rowAt命中首行可见片段")
        check(View.rowAt(state.attrHits, 200, 1069.9) == nil
            and View.rowAt(state.attrHits, 200, 1134) == nil, "rowAt拒绝裁剪外像素和十像素行距")
        check(View.rowAt(state.attrHits, 39, 1080) == nil and View.rowAt(state.attrHits, 541, 1080) == nil,
            "rowAt拒绝横向裁剪外像素")
        state.attrScrollY = 60
        Draw.draw(vg)
        local last = state.attrHits[#state.attrHits]
        check(last.index == 11 and last.h < 78 and last.y + last.h == 1944,
            "第十一行部分片段裁剪至真实底边")
        local bottomRow, bottomIndex = View.rowAt(state.attrHits, 200, 1943.9)
        check(bottomRow and bottomIndex == 11 and View.rowAt(state.attrHits, 200, 1944) == nil,
            "rowAt仅命中底部可见片段，排除底边外像素")
        state.attrScrollY = maxScroll + 100000
        Draw.draw(vg)
        local final = state.attrHits[#state.attrHits]
        check(final.index == #state.cachedLeft and near(final.h, 78) and near(final.y + final.h, 1944),
            "真实绘制限制超大滚动，末条真实属性完整出现")
        state.attrScrollY, state.attrScrollVel, state.attrDragging = 0, 2, false
        Draw.draw(vg)
        check(fixture.hits.clamp == 1 and near(state.attrScrollY, 2) and near(state.attrScrollVel, 1.8),
            "真实Draw惯性调用隔离clamp，并应用0.90摩擦")
    end)
    check(ok, "滚动/裁剪片段真实绘制成功" .. (ok and "" or (": " .. tostring(err))))
end

local function verifyAllTalents(vg)
    local ids = HC.getAllIds()
    check(#ids == 25 and shortHero() == 18, "HeroConfig共25人，截图老六真实id18")
    local measured, extraMeasured, reduced = 0, 0, 0
    for _, id in ipairs(ids) do
        local fixture = M.fixture(id, { awakened = true })
        local ok, err = isolated(fixture, function()
            local kw = KeywordText.new()
            nvgFontFace(vg, "sans")
            local base = HC.get(id).talentDesc
            local extra = ETS.getDesc(id, fixture.own.extraTalent)
            if extra == "" then
                local awakening = fixture.own.awakening
                fixture.own.awakening = {}
                extra = ETS.getDesc(id, fixture.own.extraTalent)
                fixture.own.awakening = awakening
            end
            local samples = { { text = base, font = 34, extra = false } }
            if extra ~= "" then samples[#samples + 1] = { text = base .. "\n" .. extra, font = 28, extra = true } end
            for _, sample in ipairs(samples) do
                local size = sample.font
                while size > 18 and kw:measureHeight(vg, sample.text, 870, size) > 172 do size = size - 1 end
                local height, lines = kw:measureHeight(vg, sample.text, 870, size)
                local drawn = kw:draw(vg, sample.text, 105, 2048, 870, size)
                check(height == drawn and drawn <= 172,
                    "hero" .. id .. (sample.extra and " 代表ExtraTalent" or " 基础天赋") .. " 真实字体适配 字号="
                        .. size .. " lines=" .. lines .. " h=" .. drawn)
                measured = measured + 1
                if sample.extra then extraMeasured = extraMeasured + 1 end
                if size < sample.font then reduced = reduced + 1 end
            end
            check(fixture.hits.panel > 0, "hero" .. id .. " ExtraTalent确实读取隔离觉醒fixture")
        end)
        check(ok, "hero" .. id .. " 天赋测量作用域成功恢复" .. (ok and "" or (": " .. tostring(err))))
    end
    check(measured == 50 and extraMeasured == 25, "25基础天赋加25真实代表ExtraTalent说明全部测量")
    print(PREFIX .. " FONT_AUDIT samples=" .. measured .. " adaptive=" .. reduced .. " longestHero=" .. longestHero())
end

local function verifyFailureRestoration(vg)
    local prior = { context = savedContext(), requireFn = require, class = CC.get,
        keyword = Draw.talentKwText, rows = Draw.drawAttributeRows, text = nvgText }
    local fixture = M.fixture(shortHero(), { longClass = true })
    local ok, err = isolated(fixture, function(_, patch)
        probe(vg, patch)
        Draw.draw(vg)
        assert(fixture.hits.own > 0 and fixture.hits.panel > 0 and fixture.hits.church > 0
            and fixture.hits.class > 0, "失败探针未实际执行替身")
        error("EXPECTED_LAYOUT_FAILURE_AFTER_REAL_DRAW")
    end)
    local restored = savedContext()
    local same = true
    for key, value in pairs(prior.context) do same = same and restored[key] == value end
    for key, value in pairs(restored) do same = same and prior.context[key] == value end
    check(not ok and tostring(err):find("EXPECTED_LAYOUT_FAILURE_AFTER_REAL_DRAW", 1, true) ~= nil,
        "完整真实Draw后确实触发主动失败，验证负向报告")
    check(same and require == prior.requireFn and CC.get == prior.class and Draw.talentKwText == prior.keyword
        and nvgText == prior.text and Draw.drawAttributeRows == prior.rows,
        "失败路径恢复原context、真实API、动态require和NanoVG")
    verifyDraw(vg, M.fixture(shortHero()), "主动失败之后")
end

function M.init(vg)
    -- 与boot/Standalone.lua相同字体和回退顺序，每种字体最多创建一次。
    local font = nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf")
    if font < 0 then font = nvgCreateFont(vg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf") end
    assert(font >= 0, "生产字体加载失败")
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 40)
    assert((nvgTextBounds(vg, 0, 0, "生命暴击123") or 0) > 100, "真实字体测量失败")
    Draw.initImages(vg)
    for i = 1, 6 do
        icons[i] = nvgCreateImage(vg, "image/通用图标/ICON_ZY_" .. i .. ".png", 0)
        assert(icons[i] >= 0, "真实职业图标加载失败: " .. i)
    end
end

-- 截图直接绘制完整生产Draw，绕过启动/资源加载界面。
function M.preview(vg, fixture)
    local ok, err = isolated(fixture, function() Draw.draw(vg) end)
    assert(ok, err)
end

-- 模式A：竖屏contain，横屏复用真实生产右栏变换。
function M.beginFrame(vg)
    local dpr = graphics:GetDPR()
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    nvgBeginFrame(vg, width, height, dpr)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, width, height)
    nvgFillColor(vg, nvgRGBA(10, 11, 14, 255))
    nvgFill(vg)
    if width > height then
        local ox, oy, s = Viewport.layout(width, height)
        -- 显式采用模式A生产右栏几何，不修改Viewport记录。
        nvgSave(vg)
        nvgTranslate(vg, ox + Viewport.PANELS.right.bx * s, oy)
        nvgScale(vg, s * Viewport.DS, s * Viewport.DS)
        nvgIntersectScissor(vg, 0, 0, 1080, 2400)
    else
        local scale = math.min(width / 1080, height / 2400)
        nvgSave(vg)
        nvgTranslate(vg, (width - 1080 * scale) * 0.5, (height - 2400 * scale) * 0.5)
        nvgScale(vg, scale, scale)
        nvgIntersectScissor(vg, 0, 0, 1080, 2400)
    end
end
function M.endFrame(vg) nvgRestore(vg); nvgEndFrame(vg) end

local function report()
    if finished then return end
    finished = true
    if failures == 0 then print(PREFIX .. " ALL PASS assertions=" .. assertions .. " realRenderFrames=" .. renderCount)
    else print(PREFIX .. " FAILURES=" .. failures .. " assertions=" .. assertions .. " realRenderFrames=" .. renderCount) end
    engine:Exit()
end

function HandleCharacterDetailLayoutRender()
    if finished or not canvas then return end
    renderCount = renderCount + 1
    M.beginFrame(canvas)
    safeRun("短描述完整Draw", function() verifyDraw(canvas, M.fixture(shortHero()), "短描述老六") end)
    safeRun("最长描述完整Draw", function()
        verifyDraw(canvas, M.fixture(longestHero(), { awakened = true }), "最长描述加追加技")
    end)
    safeRun("长经验/翻译/数值完整Draw", function()
        verifyDraw(canvas, M.fixture(shortHero(), { longExp = true, longClass = true, longValues = true }), "超长经验职业数值")
    end)
    safeRun("全角色天赋测量", function() verifyAllTalents(canvas) end)
    safeRun("滚动", function() verifyScroll(canvas) end)
    safeRun("主动失败恢复", function() verifyFailureRestoration(canvas) end)
    M.endFrame(canvas)
    local renderSizes = { { 1920, 1080 }, { 1280, 720 }, { 2560, 1440 }, { 1200, 1080 }, { 1080, 2400 } }
    for _, size in ipairs(renderSizes) do
        nvgBeginFrame(canvas, size[1], size[2], 1)
        local scale = math.min(size[1] / 1080, size[2] / 2400)
        nvgSave(canvas)
        nvgScale(canvas, scale, scale)
        safeRun("多尺寸长文本", function()
            local fixture = M.fixture(shortHero(), { longExp = true, longClass = true, longValues = true })
            local ok, err = isolated(fixture, function(_, patch)
                local calls = probe(canvas, patch)
                local row = { name = "最大生命值", key = "hp", value = "123456789012345678901234567890%" }
                local _, hits = View.drawAttributeRows(canvas, { row }, 0, nil, { style = View.ATTRIBUTE_STYLE })
                local name = textAt(calls, row.name, 1109)
                local value = textAt(calls, row.value, 1109)
                check(name and value and name.bounds[3] + 15 <= value.bounds[1]
                    and fits(value, 150, 520), "多尺寸名称/数值墨迹间隔 " .. size[1])
                check(#hits == 1 and hits[1].row == row, "多尺寸测量不改变属性及命中")
                local shortRow = { name = "生命", key = "hp", value = "42" }
                View.drawAttributeRows(canvas, { shortRow }, 0, nil, { style = View.ATTRIBUTE_STYLE })
                local shortValue = textAt(calls, "42", 1109)
                check(shortValue and shortValue.font == 40 and fits(shortValue, 150, 520),
                    "多尺寸普通值保持40号且不无效循环缩字 " .. size[1])
                print(PREFIX .. " SHORT_FONT scale=" .. scale .. " font=" .. tostring(shortValue and shortValue.font))
                for _, sample in ipairs({ { text = "Lv.70  123456789012345/987654321098765", x = 710, left = 415, right = 1005, size = 28 },
                    { text = "The exceptionally translated master of eternal silent shadow guardians", x = 244, left = 136, right = 352, size = 34 } }) do
                    local font, _, bounds = View.fitText(canvas, sample.text, sample.size,
                        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, sample.x, 990, sample.left, sample.right, 7)
                    check(font > 0 and bounds[1] >= sample.left + 7 and bounds[3] <= sample.right - 7,
                        "多尺寸经验/职业复测含描边 " .. size[1])
                end
            end)
            check(ok, "多尺寸两项专项成功 " .. size[1] .. (ok and "" or tostring(err)))
        end)
        nvgRestore(canvas)
        nvgEndFrame(canvas)
    end
    report()
end

function Start()
    print(PREFIX .. " START 真实渲染/隔离fixture，不使用PlayerStore/boot/存档")
    local ok, err = xpcall(function()
        canvas = assert(nvgCreate(1))
        M.init(canvas)
        SubscribeToEvent(canvas, "NanoVGRender", "HandleCharacterDetailLayoutRender")
        -- 误用graphicsheadless时明确失败，不能无渲染却报通过。
        SubscribeToEvent("Update", function()
            if not finished and time.elapsedTime > 20 then
                check(false, "未收到NanoVGRender，本测试必须使用真实surfaceless渲染")
                report()
            end
        end)
    end, debug.traceback)
    if not ok then check(false, "初始化异常: " .. tostring(err)); report() end
end
function Stop()
    if canvas then nvgDelete(canvas); canvas = nil end
end
return M
