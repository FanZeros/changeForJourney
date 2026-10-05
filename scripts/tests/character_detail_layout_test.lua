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
local HeroAssetUtil = require("config.HeroAssetUtil")
local BattleLayout = require("core.BattleLayout")
local I18n = require("core.I18n")

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
        cardDragVisual = opts.cardDragVisual or 0, cachedLeft = {}, cachedRight = {}, attrHits = {} }
    state.tab, state.tabFrom = opts.tab or "attr", opts.tab or "attr"
    -- 五卡夹具用真实配置ID；每人拥有数据/战力独立，不能拿中心角色冒充侧卡。
    local roster, ownedById, powerById = {}, { [heroId] = own }, { [heroId] = 31415 }
    local ids = opts.rosterIds or (type(opts.roster) == "table" and opts.roster) or { heroId }
    if opts.roster == true and not opts.rosterIds then
        ids = {}
        for _, id in ipairs(HC.getAllIds()) do
            if id ~= heroId and #ids < 2 then ids[#ids + 1] = id end
        end
        ids[#ids + 1] = heroId
        for _, id in ipairs(HC.getAllIds()) do
            local used = false
            for _, included in ipairs(ids) do used = used or included == id end
            if not used and #ids < 5 then ids[#ids + 1] = id end
        end
    end
    local seen = {}
    for index, id in ipairs(ids) do
        assert(HC.get(id) and not seen[id], "fixture roster包含未知或重复英雄")
        seen[id] = true
        local data = id == heroId and own or copy(own)
        if id ~= heroId then data.level = 10 + index; data.exp = index end
        ownedById[id] = data
        powerById[id] = id == heroId and 31415 or 21000 + index * 101
        snapshots.heroes.roster[tostring(id)] = data
        roster[#roster + 1] = { heroId = id, owned = true }
    end
    assert(seen[heroId], "fixture中心角色必须在roster内")
    return { heroId = heroId, own = own, snapshots = snapshots, state = state,
        roster = roster, ownedById = ownedById, powerById = powerById,
        longClass = opts.longClass == true, longValues = opts.longValues == true,
        hits = { own = 0, attrs = 0, power = 0, roster = 0, clamp = 0,
            awakening = 0, panel = 0, church = 0, class = 0, keyword = 0, rows = 0,
            ownIds = {}, powerIds = {}, panelIds = {}, classPage = 0 } }
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
local function isolated(fixture, body, sharedKeyword)
    local restores = {}
    local function defer(restore) restores[#restores + 1] = restore end
    local function patch(target, key, replacement)
        local previous = target[key]
        defer(function() target[key] = previous end)
        target[key] = replacement
    end
    local oldContext = savedContext()
    local ok, result = xpcall(function()
    -- 所有新增安装也在保护域内；暖缓存调用显式传同一个实例，不自动new。
    local keyword = sharedKeyword or KeywordText.new()
    patch(Draw, "talentKwText", keyword)
    local oldRequire = require
    local fakePanel = { getOwnedHero = function(id)
        fixture.hits.panel = fixture.hits.panel + 1
        fixture.hits.panelIds[id] = true
        return assert(fixture.ownedById[id], "拥有数据请求了隔离fixture外角色")
    end, getEffectiveLevel = function(id)
        fixture.hits.panel = fixture.hits.panel + 1
        fixture.hits.panelIds[id] = true
        return assert(fixture.ownedById[id], "侧卡等级请求了隔离fixture外角色").level
    end }
    local fakeChurch = { hasAdvanceForHero = function(id)
        fixture.hits.church = fixture.hits.church + 1
        assert(fixture.ownedById[id], "教堂角标请求了隔离fixture外角色")
        return false
    end }
    -- 只隔离与轮播无关的转职业务页面，不替换Draw的class五卡路径。
    local classPage = {}
    for _, name in ipairs({ "init", "setHero", "drawBg", "drawContent", "drawConfirmPopup",
        "drawResetConfirmPopup", "drawFloatText" }) do
        classPage[name] = function() fixture.hits.classPage = fixture.hits.classPage + 1 end
    end
    patch(_G, "require", function(name)
        if name == "ui.character.panel.CharacterPanel" then return fakePanel end
        if name == "ui.church.ChurchPage" then return fakeChurch end
        if name == "ui.church.ChurchClassChange" then return classPage end
        if name == "ui.fx.SpineCardEffect" then return { draw = function() end } end
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
            fixture.hits.ownIds[id] = true
            return assert(fixture.ownedById[id], "getOwnedData请求了隔离fixture外角色")
        end,
        calcHeroPower = function(id)
            fixture.hits.power = fixture.hits.power + 1
            fixture.hits.powerIds[id] = true
            return assert(fixture.powerById[id], "战力请求了隔离fixture外角色")
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
                return fixture.roster
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
    return body(keyword, patch, defer)
    end, debug.traceback)
    for i = #restores, 1, -1 do restores[i]() end
    Draw.setContext(oldContext)
    Draw.markPowerDirty()
    return ok, result
end

-- 透传探针：记录的文本、路径、图片仍真正提交NanoVG。
-- 每次真实nvgText之前，按最终字体/对齐测量墨迹边界。
local function probe(vg, patch, defer)
    local calls = { texts = {}, rects = {}, images = {}, scissors = {}, circles = {}, points = {},
        cardImages = {}, scales = {}, stack = {}, saves = 0, restores = 0,
        measures = 0, keyword = nil, rows = nil }
    local font, align = 0, 0
    local textBounds = nvgTextBounds
    local nativeSave, nativeRestore = nvgSave, nvgRestore
    local function transform()
        local matrix = {}
        local result = nvgCurrentTransform(vg, matrix)
        if type(result) == "table" then matrix = result end
        assert(#matrix == 6, "真实NanoVG最终变换读取失败")
        return matrix
    end
    calls.frameTransform = transform()
    if defer then
        nativeSave(vg)
        defer(function()
            -- body抛错在任何嵌套层也恢复NanoVG栈/字体/裁剪，随后才退出外层frame。
            for _ = 1, #calls.stack do nativeRestore(vg) end
            nativeRestore(vg)
        end)
    end
    local function wrap(name, record)
        local native = _G[name]
        patch(_G, name, function(...)
            record(...)
            return native(...)
        end)
    end
    wrap("nvgSave", function()
        calls.saves = calls.saves + 1
        calls.stack[#calls.stack + 1] = { font = font, align = align, matrix = transform() }
    end)
    wrap("nvgRestore", function()
        calls.restores = calls.restores + 1
        local saved = assert(table.remove(calls.stack), "Draw越界弹出探针外层NanoVG栈")
        font, align = saved.font, saved.align
    end)
    wrap("nvgScale", function(_, sx, sy)
        calls.scales[#calls.scales + 1] = { x = sx, y = sy, depth = #calls.stack }
    end)
    wrap("nvgFontSize", function(_, size) font = size end)
    wrap("nvgTextAlign", function(_, value) align = value end)
    wrap("nvgTextBounds", function() calls.measures = calls.measures + 1 end)
    local recordingDisplay = false
    local function recordText(x, y, text, display)
        local bounds = {}
        local width = (display and I18n.displayBounds or textBounds)(vg, x, y, text, bounds)
        calls.texts[#calls.texts + 1] = { x = x, y = y, text = text, font = font,
            align = align, width = width, bounds = bounds }
    end
    wrap("nvgText", function(_, x, y, text)
        if not recordingDisplay then recordText(x, y, text, false) end
    end)
    -- installDrawHook之后富文本走raw函数；不能只探nvgText就漏掉天赋墨迹。
    local displayText = I18n.displayText
    patch(I18n, "displayText", function(ctx, x, y, text, endp)
        recordText(x, y, text, true)
        recordingDisplay = true
        local result = displayText(ctx, x, y, text, endp)
        recordingDisplay = false
        return result
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
    local cardImage = DrawUtil.drawCardImage
    patch(DrawUtil, "drawCardImage", function(ctx, image, cx, cy, w, h, alpha)
        local call = { image = image, x = cx, y = cy, w = w, h = h,
            matrix = transform(), stack = copy(calls.stack), scale = calls.scales[#calls.scales],
            imageStart = #calls.images, textStart = #calls.texts }
        calls.cardImages[#calls.cardImages + 1] = call
        local result = cardImage(ctx, image, cx, cy, w, h, alpha)
        call.imageEnd = #calls.images
        return result
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
local function sameMatrix(a, b)
    if #a ~= 6 or #b ~= 6 then return false end
    for i = 1, 6 do if not near(a[i], b[i]) then return false end end
    return true
end
local function currentMatrix(vg)
    local matrix = {}
    -- 本Runtime绑定返回新table而非修改传入table；两种绑定均保留真实返回。
    local result = nvgCurrentTransform(vg, matrix)
    return type(result) == "table" and result or matrix
end
local function projectedRect(matrix, x, y, w, h)
    return { x = matrix[1] * x + matrix[3] * y + matrix[5],
        y = matrix[2] * x + matrix[4] * y + matrix[6],
        w = math.sqrt(matrix[1]^2 + matrix[2]^2) * w,
        h = math.sqrt(matrix[3]^2 + matrix[4]^2) * h }
end
local function strictRatio(w, h, rw, rh)
    return w > 0 and h > 0 and math.abs(w / h - rw / rh) < 0.00001
end
-- 新增探针恢复清单覆盖上下文、图片API、矩阵/字体API、I18n raw通道与动态require。
local function restorationSnapshot(vg)
    local saved = { context = savedContext(), matrix = currentMatrix(vg), functions = {},
        requireFn = require, class = CC.get, keyword = Draw.talentKwText, card = DrawUtil.drawCardImage,
        display = I18n.displayText, language = I18n.get(), time = time, rows = Draw.drawAttributeRows }
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgScale", "nvgCreateImage", "nvgText",
        "nvgTextBounds", "nvgTextAlign", "nvgFontSize", "nvgImagePattern", "nvgCircle",
        "nvgRoundedRect", "nvgIntersectScissor", "nvgMoveTo", "nvgLineTo" }) do
        saved.functions[name] = _G[name]
    end
    return saved
end
local function restored(vg, prior)
    local context, same = savedContext(), sameMatrix(currentMatrix(vg), prior.matrix)
    for key, value in pairs(prior.context) do same = same and context[key] == value end
    for key, value in pairs(context) do same = same and prior.context[key] == value end
    for name, fn in pairs(prior.functions) do same = same and _G[name] == fn end
    return same and require == prior.requireFn and CC.get == prior.class
        and Draw.talentKwText == prior.keyword and DrawUtil.drawCardImage == prior.card
        and I18n.displayText == prior.display and I18n.get() == prior.language
        and time == prior.time and Draw.drawAttributeRows == prior.rows
end

local function safeRun(label, body)
    local ok, err = xpcall(body, debug.traceback)
    if not ok then check(false, label .. " 测试异常: " .. tostring(err)) end
end

local function verifyDraw(vg, fixture, label)
    local previous = { requireFn = require, class = CC.get, keyword = Draw.talentKwText,
        font = nvgFontSize, text = nvgText, rows = Draw.drawAttributeRows }
    local ok, result = isolated(fixture, function(keyword, patch, defer)
        local calls = probe(vg, patch, defer)
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
        if fixture.own.exp > 100000 then check(expText.font <= 28, label .. " 超长经验拟合且不放大原28号") end
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

-- 五张真实卡图经过DrawUtil整图映射；不能仅检查布局常量或局部scale。
local function verifyCarousel(vg)
    for _, tab in ipairs({ "attr", "class" }) do
        local scenarios = {}
        for _, slide in ipairs({ 0, 0.25, -0.25, 0.5, -0.5, 0.9, -0.9 }) do
            scenarios[#scenarios + 1] = { slide = slide }
        end
        for _, direction in ipairs({ -1, 1 }) do
            for _, progress in ipairs({ 0.25, 0.5, 0.75 }) do
                scenarios[#scenarios + 1] = { direction = direction, raw = progress, from = -direction * 0.25 }
            end
        end
        for _, scenario in ipairs(scenarios) do
            local fixture = M.fixture(shortHero(), { roster = true, tab = tab,
                cardDragVisual = scenario.slide or 0 })
            local label = tab .. " 五卡 " .. (scenario.direction
                and ("switch=" .. scenario.direction .. " t=" .. scenario.raw) or ("drag=" .. scenario.slide))
            local slide = scenario.slide or 0
            if scenario.direction then
                local t = scenario.raw
                local eased = t < 0.5 and 4 * t^3 or (0.5 * (2 * t - 2)^3 + 1)
                slide = (scenario.direction + scenario.from) * (1 - eased)
                fixture.state.switchDir, fixture.state.switchFrom = scenario.direction, scenario.from
                fixture.state.openTime = time.elapsedTime - t * Draw.SWITCH_ANIM_DURATION
            end
            local prior = restorationSnapshot(vg)
            local ok, err = isolated(fixture, function(_, patch, defer)
                if scenario.direction then
                    local now = time.elapsedTime
                    fixture.state.openTime = now - scenario.raw * Draw.SWITCH_ANIM_DURATION
                    patch(_G, "time", { elapsedTime = now })
                end
                local calls = probe(vg, patch, defer)
                local creations, create = {}, nvgCreateImage
                patch(_G, "nvgCreateImage", function(ctx, path, flags)
                    creations[path] = (creations[path] or 0) + 1
                    return create(ctx, path, flags)
                end)
                local context = savedContext()
                for _, entry in ipairs(fixture.roster) do
                    local id, path = entry.heroId, HeroAssetUtil.getCardPath(entry.heroId)
                    local cached = cards[id]
                    local image = HeroAssetUtil.ensureCard(vg, cards, id)
                    local again = HeroAssetUtil.ensureCard(vg, cards, id)
                    local sw, sh = nvgImageSize(vg, image)
                    check(image >= 0 and again == image and (creations[path] or 0) == (cached == nil and 1 or 0)
                        and sw == 768 and sh == 1365, label .. " hero" .. id .. " 真实ensureCard加载/复用768x1365")
                    check(context.getOwnedData(id) == fixture.ownedById[id],
                        label .. " hero" .. id .. " getOwnedData返回独立fixture")
                end
                Draw.draw(vg)
                check(#calls.cardImages == 5 and fixture.hits.power == 5 and fixture.hits.roster > 0,
                    label .. " 五卡实际绘制且五人独立战力各计算一次")
                if tab == "class" then check(fixture.hits.classPage > 0, label .. " 命中真实class重绘路径") end
                local allScales = #calls.scales >= 5
                for _, scale in ipairs(calls.scales) do allScales = allScales and near(scale.x, scale.y) end
                check(allScales, label .. " 全部真实nvgScale XY一致")
                local slots, order = { -2, -1, 1, 2, 0 }, { 1, 2, 4, 5, 3 }
                for index, call in ipairs(calls.cardImages) do
                    local id = fixture.roster[order[index]].heroId
                    local pos = slots[index] + slide
                    local scale = 1.18 - (1.18 - 0.92) * math.min(1, math.abs(pos))
                    local base = calls.frameTransform
                    local expected = { base[1] * scale, base[2] * scale, base[3] * scale, base[4] * scale,
                        base[1] * (540 + pos * 250) + base[3] * 544 + base[5],
                        base[2] * (540 + pos * 250) + base[4] * 544 + base[6] }
                    local frame = projectedRect(call.matrix, call.x - call.w * 0.5,
                        call.y - call.h * 0.5, call.w, call.h)
                    check(call.image == cards[id] and #call.stack > 0 and call.scale
                        and near(call.scale.x, scale) and near(call.scale.y, scale)
                        and sameMatrix(call.matrix, expected) and strictRatio(frame.w, frame.h, 538, 955),
                        label .. " slot" .. slots[index] .. " 最终frame变换/538:955可见框")
                    local image = calls.images[call.imageStart + 1]
                    local sx, sy = call.w / 538, call.h / 955
                    local source = image and projectedRect(call.matrix, image.x, image.y, image.w, image.h)
                    check(call.imageEnd == call.imageStart + 1 and image and image.image == call.image
                        and near(image.x, -call.w * 0.5 - 115 * sx)
                        and near(image.y, -call.h * 0.5 - 205 * sy)
                        and near(image.w, 768 * sx) and near(image.h, 1365 * sy)
                        and source and strictRatio(source.w, source.h, 768, 1365),
                        label .. " slot" .. slots[index] .. " 最终整图768:1365及115/205出框偏移，无cover裁切")
                    local finish = calls.cardImages[index + 1] and calls.cardImages[index + 1].textStart or #calls.texts
                    local level, power = false, false
                    for ti = call.textStart + 1, finish do
                        local text = calls.texts[ti]
                        level = level or (text.text == tostring(fixture.ownedById[id].level)
                            and near(text.y, call.h * 0.5 - 38))
                        power = power or (text.text == tostring(fixture.powerById[id])
                            and near(text.y, call.h * 0.5 - 83))
                    end
                    check(level and power and fixture.hits.powerIds[id],
                        label .. " slot" .. slots[index] .. " 卡底等级/战力使用各自fixture，不借中心值")
                    if slide == 0 then
                        local actualScale = slots[index] == 0 and 1.18 or 0.92
                        check(near(frame.w / math.abs(base[1]), BattleLayout.CARD_W * actualScale)
                            and near(frame.h / math.abs(base[4]), BattleLayout.CARD_H * actualScale),
                            label .. " slot" .. slots[index] .. " 中心1.18/侧卡0.92尺寸同步")
                    end
                end
                check(near(Draw.SIDE_CARD_W, BattleLayout.CARD_W * 0.92)
                    and near(Draw.SIDE_CARD_H, Draw.SIDE_CARD_W * 955 / 538)
                    and strictRatio(Draw.SIDE_CARD_W, Draw.SIDE_CARD_H, 538, 955),
                    label .. " SIDE_CARD_W/H与实际侧卡及更新后的比例一致")
                check(#calls.stack == 0 and calls.saves == calls.restores,
                    label .. " 完整Draw变换栈平衡")
            end)
            check(ok, label .. " 隔离执行成功" .. (ok and "" or (": " .. tostring(err))))
            check(restored(vg, prior), label .. " 成功/异常均恢复所有函数/context/最终frame变换")
        end
    end
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

local HEX_KEYS = { "str", "agi", "vit", "spi", "luk", "int" }
local function axisPoint(layout, index, radius)
    local angle = -math.pi * 0.5 + (index - 1) * math.pi / 3
    return layout.cx + math.cos(angle) * radius, layout.cy + math.sin(angle) * radius
end
local function textsNear(calls, label, x, y, radius)
    local result = {}
    for _, call in ipairs(calls.texts) do
        if call.text == label and math.abs(call.x - x) <= radius + 0.05
            and math.abs(call.y - y) <= radius + 0.05 then result[#result + 1] = call end
    end
    return result
end
-- 六轴逐一检查fill及全部八向描边，不能用空集合或仅中心值冒充通过。
local function verifyRadarNumbers(vg, label)
    local fixture, prior = M.fixture(shortHero()), restorationSnapshot(vg)
    local ok, err = isolated(fixture, function(_, patch, defer)
        local calls = probe(vg, patch, defer)
        local function audit(mode, values, preview, equipment, ordinary)
            calls.texts, calls.points, calls.circles = {}, {}, {}
            local legacy = mode == "legacy"
            local layout = legacy and { cx = Stats.LEGACY.HEX_CX, cy = Stats.LEGACY.HEX_CY,
                r = Stats.LEGACY.HEX_R, labelR = Stats.LEGACY.HEX_LABEL_R } or Stats.LAYOUT.radar
            local unchanged, peak = copy(values), 1
            for _, key in ipairs(HEX_KEYS) do
                peak = math.max(peak, values[key], preview and preview[key] or 0)
            end
            local maxValue = math.max(8, peak / 0.82)
            check(near(Stats.radarScale(values, preview), maxValue), label .. " " .. mode .. " 共享归一化不变")
            if legacy then Stats.drawLegacy(vg, values) else Stats.drawRadar(vg, values, preview, equipment) end
            check(matching(calls.circles, function(c)
                return near(c.x, layout.cx) and near(c.y, layout.cy) and near(c.r, 5)
            end) ~= nil and matching(calls.points, function(c)
                return near(c.x, layout.cx) and near(c.y, layout.cy - layout.r)
            end) ~= nil, label .. " " .. mode .. " 原中心/外圈半径不变")
            for index, key in ipairs(HEX_KEYS) do
                local x, y = axisPoint(layout, index, layout.labelR)
                local value = values[key]
                local text = legacy and tostring(value) or tostring(math.floor(value))
                if equipment then
                    local amount = math.abs(value) < 0.1 and string.format("%.6f", value) or string.format("%.1f", value)
                    text = amount:gsub("0+$", ""):gsub("%.$", "")
                    if value > 0 then text = "+" .. text end
                end
                local cy = y + (legacy and 18 or 16)
                local ink = textsNear(calls, text, x, cy, 3)
                local original, left, right = legacy and 38 or 34, legacy and 552 or 545, legacy and 1068 or 1075
                local maxWidth = legacy and 160 or 150
                left, right = math.max(left, x - maxWidth * 0.5), math.min(right, x + maxWidth * 0.5)
                local inside, fonts = #ink == 9, true
                for _, glyph in ipairs(ink) do
                    inside = inside and fits(glyph, left, right) and #glyph.bounds == 4
                        and glyph.bounds[2] >= cy - 40 and glyph.bounds[4] <= cy + 40
                    fonts = fonts and (ordinary and glyph.font == original or not ordinary and glyph.font < original)
                end
                check(inside and fonts, label .. " " .. mode .. " " .. key
                    .. " 六轴值及全部8描边bounds在可用框，" .. (ordinary and "原字号" .. original or "长值缩字"))
                local ratio = legacy and math.max(0.08, math.min(1, value / maxValue))
                    or math.max(equipment and 0 or 0.08, math.min(1, value / maxValue))
                local vx, vy = axisPoint(layout, index, layout.r * ratio)
                check(matching(calls.points, function(c) return near(c.x, vx) and near(c.y, vy) end) ~= nil
                    and values[key] == unchanged[key], label .. " " .. mode .. " " .. key .. " 数值/几何/8%或0下限不变")
                if preview then
                    local delta = preview[key] - value
                    local amount
                    if math.abs(delta - math.floor(delta + 0.5)) < 0.000001 then amount = string.format("%.0f", delta)
                    elseif math.abs(delta) < 0.1 then amount = string.format("%.6f", delta):gsub("0+$", ""):gsub("%.$", "")
                    else amount = string.format("%.1f", delta) end
                    local deltaText = (delta > 0 and "+" or "") .. amount
                    local dc = textsNear(calls, deltaText, x, y - layout.deltaOffset, 0)
                    check(#dc == 1 and fits(dc[1], math.max(545, x - 75), math.min(1075, x + 75))
                        and (ordinary and dc[1].font == 32 or not ordinary and dc[1].font < 32),
                        label .. " " .. mode .. " " .. key .. " signed delta完整精度/边界及" .. (ordinary and "32号" or "长值缩字"))
                end
            end
        end
        local long, nextLong, normal, nextNormal = {}, {}, {}, {}
        for index, key in ipairs(HEX_KEYS) do
            long[key] = 123456789012345 + index * 100
            nextLong[key] = long[key] + (index % 2 == 0 and -98765432109876 or 98765432109876)
            normal[key], nextNormal[key] = 42, 44
        end
        audit("legacy", long, nil, false, false)
        audit("radar-total", long, nextLong, false, false)
        audit("radar-equipment", long, nextLong, true, false)
        audit("legacy", normal, nil, false, true)
        audit("radar-total", normal, nextNormal, false, true)
        audit("radar-equipment", normal, nextNormal, true, true)
        -- 微量净增益与负数不被长值适配改变精度，也不能四舍五入成+0.0。
        calls.texts = {}
        local tiny = { str = 0.0042, agi = 0.125, vit = 0, spi = -0.0042, luk = 1.25, int = -2.5 }
        local nextTiny = copy(tiny)
        nextTiny.str, nextTiny.spi = tiny.str + 0.000123, tiny.spi - 0.000321
        Stats.drawRadar(vg, tiny, nextTiny, true)
        for index, text in ipairs({ "+0.0042", "+0.1", "0", "-0.0042", "+1.2", "-2.5" }) do
            local x, y = axisPoint(Stats.LAYOUT.radar, index, Stats.LAYOUT.radar.labelR)
            local ink = textsNear(calls, text, x, y + 16, 3)
            local precisionOK = #ink == 9
            for _, glyph in ipairs(ink) do precisionOK = precisionOK and glyph.font > 0 and glyph.font <= 34
                and fits(glyph, math.max(545, x - 75), math.min(1075, x + 75)) end
            check(precisionOK, label .. " 装备净值完整精度 " .. text .. " 描边拟合，不放大34号")
        end
        for _, sample in ipairs({ { axis = 1, text = "+0.000123" }, { axis = 4, text = "-0.000321" } }) do
            local x, y = axisPoint(Stats.LAYOUT.radar, sample.axis, Stats.LAYOUT.radar.labelR)
            local delta = textsNear(calls, sample.text, x, y - Stats.LAYOUT.radar.deltaOffset, 0)
            check(#delta == 1 and delta[1].font > 0 and delta[1].font <= 32
                and fits(delta[1], math.max(545, x - 75), math.min(1075, x + 75)),
                label .. " 微差值 " .. sample.text .. " 完整精度/边界，不放大32号")
        end
    end)
    check(ok, label .. " Stats完整真实六轴专项成功" .. (ok and "" or (": " .. tostring(err))))
    check(restored(vg, prior), label .. " Stats专项恢复真实API/context/frame")
end

-- 完整Draw读取真实天赋/ExtraTalent，复测fill墨迹和热区；不绑定中文输出或固定自适应字号。
local function verifyTalentDraw(vg, fixture, label, sharedKeyword, language)
    local prior = restorationSnapshot(vg)
    local ok, err = isolated(fixture, function(keyword, patch, defer)
        if language then
            local previous = I18n.get()
            defer(function() I18n.set(previous) end)
            assert(I18n.set(language), "未知测试语言")
        end
        local calls = probe(vg, patch, defer)
        local drawKw, drawn = keyword.draw, {}
        patch(keyword, "draw", function(self, ctx, text, x, y, width, font, lh, cx)
            drawn = { text = text, x = x, y = y, w = width, font = font, first = #calls.texts + 1 }
            drawn.h = drawKw(self, ctx, text, x, y, width, font, lh, cx)
            drawn.last = #calls.texts
            return drawn.h
        end)
        Draw.draw(vg)
        local extra = ETS.getDesc(fixture.heroId, fixture.own.extraTalent)
        local source = HC.get(fixture.heroId).talentDesc .. (extra ~= "" and ("\n" .. extra) or "")
        check(Draw.talentKwText == sharedKeyword and drawn.text == source and near(drawn.x, 105)
            and near(drawn.y, 2048) and near(drawn.w, 870) and drawn.h <= 172
            and keyword:lastHeight() == drawn.h, label .. " 完整Draw真实源文/成长说明/870宽172高")
        local reference = KeywordText.new()
        local height, lines = reference:measureHeight(vg, drawn.text, drawn.w, drawn.font)
        local warmH, warmLines = keyword:measureHeight(vg, drawn.text, drawn.w, drawn.font)
        if height ~= drawn.h or height ~= warmH or lines ~= warmLines then
            print(PREFIX .. " CACHE " .. label .. " freshH=" .. height .. " drawnH=" .. drawn.h
                .. " warmH=" .. warmH .. " freshLines=" .. lines .. " warmLines=" .. warmLines .. " font=" .. drawn.font)
        end
        check(height == drawn.h and height == warmH and lines == warmLines,
            label .. " 同vg暖缓存布局与新实例最终缩放复测一致")
        local inside, fragments = drawn.last >= drawn.first, {}
        for index = drawn.first, drawn.last do
            local glyph = calls.texts[index]
            inside = inside and fits(glyph, 105, 975) and #glyph.bounds == 4
                and glyph.bounds[2] >= 2048 - 3 and glyph.bounds[4] <= 2220 + 3
                and glyph.bounds[4] < 2236.5
            fragments[#fragments + 1] = glyph.text
        end
        local actualLayout = reference:_layout(vg, drawn.text, drawn.w, drawn.font)
        check(inside and table.concat(fragments) == actualLayout.displayText:gsub("\n", ""),
            label .. " 全部真实天赋片段墨迹留在正文/页签界内，未裁掉字符")
        local hotOK = #keyword.hotspots > 0
        for _, hit in ipairs(keyword.hotspots) do
            hotOK = hotOK and hit.x1 >= 104 and hit.x2 <= 976 and hit.y1 >= 2048
                and hit.y2 <= 2220 and hit.x2 > hit.x1 and hit.y2 > hit.y1
        end
        check(hotOK, label .. " 最终字号关键词热区完整且不进入页签")
        local title = matching(calls.texts, function(c) return near(c.x, 105) and near(c.y, 2012) end)
        check(title and title.font == 40 and fixture.hits.attrs == 1 and fixture.hits.power > 0
            and #calls.cardImages == #fixture.roster, label .. " 完整属性Draw含40号天赋标题/属性/真实卡图")
        check(#calls.stack == 0, label .. " 完整天赋Draw的frame栈平衡")
        return { height = drawn.h, font = drawn.font, lines = lines, hotspots = copy(keyword.hotspots) }
    end, sharedKeyword)
    check(ok, label .. " 完整天赋Draw成功" .. (ok and "" or (": " .. tostring(err))))
    check(restored(vg, prior), label .. " 天赋成功/异常恢复实例/API/语言/frame")
    return ok and err or nil
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
    for _, tab in ipairs({ "attr", "class" }) do
        local prior = restorationSnapshot(vg)
        local fixture = M.fixture(shortHero(), { longClass = true, roster = true, tab = tab })
        local ok, err = isolated(fixture, function(_, patch, defer)
            probe(vg, patch, defer)
            local create = nvgCreateImage
            patch(_G, "nvgCreateImage", function(...) return create(...) end)
            local card = DrawUtil.drawCardImage
            local draws = 0
            patch(DrawUtil, "drawCardImage", function(...)
                draws = draws + 1
                local result = card(...)
                if draws == 3 then
                    -- 真Draw仍在卡面save/scale内部，失败后必须弹出所有未完成层。
                    nvgSave(vg)
                    nvgScale(vg, 0.25, 0.25)
                    error("EXPECTED_LAYOUT_FAILURE_INSIDE_REAL_CARD")
                end
                return result
            end)
            Draw.draw(vg)
        end)
        check(not ok and tostring(err):find("EXPECTED_LAYOUT_FAILURE_INSIDE_REAL_CARD", 1, true) ~= nil,
            tab .. " 五卡真实Draw内部确实失败，不能假装完整绘制成功")
        check(restored(vg, prior), tab .. " 嵌套失败恢复真实加载/矩阵栈/context/I18n/全部API")
    end
    local prior = restorationSnapshot(vg)
    local fixture = M.fixture(shortHero(), { longClass = true })
    local ok, err = isolated(fixture, function(_, patch, defer)
        probe(vg, patch, defer)
        local language = I18n.get()
        defer(function() I18n.set(language) end)
        I18n.set("en")
        Draw.draw(vg)
        assert(fixture.hits.own > 0 and fixture.hits.panel > 0 and fixture.hits.church > 0
            and fixture.hits.class > 0, "失败探针未实际执行替身")
        error("EXPECTED_LAYOUT_FAILURE_AFTER_REAL_DRAW")
    end)
    check(not ok and tostring(err):find("EXPECTED_LAYOUT_FAILURE_AFTER_REAL_DRAW", 1, true) ~= nil,
        "完整真实Draw后确实触发主动失败，验证负向报告")
    check(restored(vg, prior), "完整Draw失败恢复原context、真实API、语言、动态require和NanoVG")
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

-- 模式A：所有宽高均用真实生产三面板layout×DS，不用竖屏contain冒充右栏。
-- 可外用传入逻辑宽/高/DPR；省略时使用当前graphics物理像素/DPR。
function M.beginFrame(vg, width, height, dpr)
    dpr = dpr or graphics:GetDPR()
    width = width or graphics:GetWidth() / dpr
    height = height or graphics:GetHeight() / dpr
    nvgBeginFrame(vg, width, height, dpr)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, width, height)
    nvgFillColor(vg, nvgRGBA(10, 11, 14, 255))
    nvgFill(vg)
    local ox, oy, s = Viewport.layout(width, height)
    local scale = s * Viewport.DS
    -- 与Viewport.begin一致，但不污染生产Viewport._notes。
    nvgSave(vg)
    nvgTranslate(vg, ox + Viewport.PANELS.right.bx * s, oy)
    nvgScale(vg, scale, scale)
    nvgIntersectScissor(vg, 0, 0, 1080, 2400)
    return scale
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
    safeRun("真实五卡比例/拖动/切换", function() verifyCarousel(canvas) end)
    safeRun("全角色天赋测量", function() verifyAllTalents(canvas) end)
    safeRun("滚动", function() verifyScroll(canvas) end)
    safeRun("主动失败恢复", function() verifyFailureRestoration(canvas) end)
    M.endFrame(canvas)
    local renderSizes = { { 1920, 1080 }, { 1280, 720 }, { 2560, 1440 }, { 1200, 1080 }, { 1080, 2400 } }
    -- 原五尺寸全部扩展；追加明确的小→大→小与DPR2/3，vg/Keyword实例始终不换。
    renderSizes[#renderSizes + 1] = { 960, 540 }
    renderSizes[#renderSizes + 1] = { 2560, 1440 }
    renderSizes[#renderSizes + 1] = { 960, 540 }
    renderSizes[#renderSizes + 1] = { 1280, 720, 2 }
    renderSizes[#renderSizes + 1] = { 1280, 720, 3 }
    local shortKeyword, longKeyword = KeywordText.new(), KeywordText.new()
    local warmSmall = {}
    for index, size in ipairs(renderSizes) do
        local label = size[1] .. "x" .. size[2] .. " DPR" .. (size[3] or 1)
        local scale = M.beginFrame(canvas, size[1], size[2], size[3] or 1)
        local ox, oy, s = Viewport.layout(size[1], size[2])
        check(sameMatrix(currentMatrix(canvas), { scale, 0, 0, scale,
            ox + Viewport.PANELS.right.bx * s, oy }), label .. " frame真实Viewport.layout×DS，无contain分支")
        safeRun("多尺寸长文本 " .. label, function()
            verifyDraw(canvas, M.fixture(shortHero(), { longExp = true, longClass = true, longValues = true }),
                "多尺寸完整属性/经验/职业 " .. label)
            local fixture, prior = M.fixture(shortHero()), restorationSnapshot(canvas)
            local ok, err = isolated(fixture, function(_, patch, defer)
                local calls = probe(canvas, patch, defer)
                local row = { name = "最大生命值", key = "hp", value = "123456789012345678901234567890%" }
                local _, hits = View.drawAttributeRows(canvas, { row }, 0, nil, { style = View.ATTRIBUTE_STYLE })
                local name, ink = textAt(calls, row.name, 1109), textsNear(calls, row.value, 514, 1109, 4)
                local gap = name ~= nil and #ink == 9
                for _, value in ipairs(ink) do gap = gap and name.bounds[3] + 15 <= value.bounds[1] and fits(value, 150, 520) end
                check(gap and #hits == 1 and hits[1].row == row,
                    label .. " 属性长值全8描边/名称墨迹15间距与真实命中")
                calls.texts = {}
                View.drawAttributeRows(canvas, { { name = "生命", key = "hp", value = "42" } }, 0, nil,
                    { style = View.ATTRIBUTE_STYLE })
                local normal = textsNear(calls, "42", 514, 1109, 4)
                local normalOK = #normal == 9
                for _, value in ipairs(normal) do normalOK = normalOK and value.font == 40 and fits(value, 150, 520) end
                check(normalOK, label .. " 普通属性值全8描边保留40号")
            end)
            check(ok, label .. " 属性描边专项成功" .. (ok and "" or (": " .. tostring(err))))
            check(restored(canvas, prior), label .. " 属性专项API/context/frame恢复")
            local short = verifyTalentDraw(canvas, M.fixture(shortHero(), { roster = true }),
                "短天赋 " .. label, shortKeyword)
            local long = verifyTalentDraw(canvas, M.fixture(longestHero(), { roster = true, awakened = true }),
                "最长天赋/追加技 " .. label, longKeyword)
            if index == 6 then warmSmall.short, warmSmall.long = short, long end
            if index == 8 then
                for _, kind in ipairs({ "short", "long" }) do
                    local previous, current = warmSmall[kind], kind == "short" and short or long
                    local equal = previous and current and previous.height == current.height
                        and previous.font == current.font and previous.lines == current.lines
                        and #previous.hotspots == #current.hotspots
                    if equal then
                        for hi, hit in ipairs(previous.hotspots) do
                            local now = current.hotspots[hi]
                            equal = equal and hit.name == now.name and near(hit.x1, now.x1) and near(hit.x2, now.x2)
                                and near(hit.y1, now.y1) and near(hit.y2, now.y2)
                        end
                    end
                    check(equal, label .. " " .. kind .. " 同vg同实例小→大→小高度/字号/热区一致")
                end
            end
            verifyRadarNumbers(canvas, label)
        end)
        -- 五语完整真实Draw只用语义/墨迹断言，不把中文名字或自适应字号写死。
        if index == 9 then
            safeRun("跨语言完整天赋Draw", function()
                for _, item in ipairs(I18n.LANGS) do
                    verifyTalentDraw(canvas, M.fixture(shortHero(), { roster = true }),
                        label .. " " .. item.id, shortKeyword, item.id)
                end
            end)
        end
        M.endFrame(canvas)
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
