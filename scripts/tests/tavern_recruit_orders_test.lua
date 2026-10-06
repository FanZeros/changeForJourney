-- 酒馆双招募令专项：只读源码 + load(env)，不加载 main/真实历史/玩家档。
-- 唯一生产读取白名单在 SOURCE_FILES；其余 require、File、cache、cloud 都拒绝。
-- 运行 cwd 必须是 /home/Maker/tavern-recruit-orders-validation-20261006，不能是 /workspace。
-- .cli/UrhoXRuntime tests/tavern_recruit_orders_test.lua
--   -tapcode_dir=/workspace/changeForJourney-workspace1005 -tool_mode -nosound
--   -graphicsheadless -validate -validate-frames=60 -validate-timeout=45
--   -validate-output=/home/Maker/tavern-recruit-orders-validation-20261006/validate.json
-- 可选 -recruit-orders-review=locked|unlocked|stellar：仍隔离依赖，仅绘图换真实 NanoVG。
-- review 用 -graphicssurfaceless -screenshot=<绝对PNG> -screenshot-frame=120 -x1080 -y2400。
-- spy 是调用链/几何证据，不是视觉截图；review 输出才是真实引擎 PNG。

local ROOT = "/workspace"
for _, argument in ipairs(GetArguments()) do
    local projectRoot = argument:match("^%-tapcode_dir=(.+)$")
    if projectRoot then ROOT = projectRoot:gsub("/+$", "") end
end
local TAG = "[tavern_recruit_orders_test] "
local STANDARD = "image/界面底板/酒馆抽卡/UI_TAVERN_RECRUIT_ORDER_STANDARD.png"
local STELLAR = "image/界面底板/酒馆抽卡/UI_TAVERN_RECRUIT_ORDER_STELLAR.png"
local ORDERS = {
    { id = "standard", path = STANDARD, cx = 275, cy = 545, w = 450, h = 650 },
    { id = "stellar", path = STELLAR, cx = 815, cy = 545, w = 450, h = 650 },
}
local SOURCE_FILES = {
    ["ui.tavern.TavernPage"] = ROOT .. "/scripts/ui/tavern/TavernPage.lua",
    ["ui.tavern.TavernRecruitOrders"] = ROOT .. "/scripts/ui/tavern/TavernRecruitOrders.lua",
    ["config.UrGachaConfig"] = ROOT .. "/scripts/config/UrGachaConfig.lua",
    ["config.GachaConfig"] = ROOT .. "/scripts/config/GachaConfig.lua",
    ["core.DrawUtil"] = ROOT .. "/scripts/core/DrawUtil.lua",
}
local nativeFile, nativeCache = File, cache
local nativeTime, nativeCreateImage = time, nvgCreateImage
local sourceReads = {} ---@type string[]
local sources = {} ---@type table<string, string>
local contexts = {} ---@type any[]
local checks, groups = 0, 0
local failures = {} ---@type string[]
local initialLoaded = {} ---@type table<string, any>
for name in pairs(SOURCE_FILES) do initialLoaded[name] = package.loaded[name] end

local function check(ok, message)
    checks = checks + 1
    assert(ok, message)
end
local function eq(actual, expected, message)
    check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function near(actual, expected, message)
    check(type(actual) == "number" and math.abs(actual - expected) < 0.00001,
        message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, child in pairs(a) do if not same(child, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function noop() end
local function source(name)
    local path = assert(SOURCE_FILES[name], "source denied: " .. tostring(name))
    assert(path:sub(1, 1) == "/" and path:sub(-4) == ".lua" and not path:find("..", 1, true),
        "only absolute allowlisted Lua source reads")
    if not sources[name] then
        -- native File 唯一出口：固定白名单绝对源码路径，明确 FILE_READ，不能传入玩家文件。
        local file = assert(nativeFile(path, FILE_READ), "source File unavailable: " .. path)
        assert(file:IsOpen(), "source open failed: " .. path)
        local ok, text = pcall(function()
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            return table.concat(lines, "\n")
        end)
        file:Dispose()
        assert(ok, text)
        sources[name] = text
        sourceReads[#sourceReads + 1] = path
    end
    return sources[name]
end
local function rect(cx, cy, w, h)
    return { x = cx - w * 0.5, y = cy - h * 0.5, w = w, h = h }
end
local function within(inner, outer, padding)
    local p = padding or 0
    return inner.x - p >= outer.x - 0.00001 and inner.y - p >= outer.y - 0.00001
        and inner.x + inner.w + p <= outer.x + outer.w + 0.00001
        and inner.y + inner.h + p <= outer.y + outer.h + 0.00001
end
local function boundaryPoints(order, delta)
    local r = rect(order.cx, order.cy, order.w, order.h)
    local d = delta or 0
    return {
        { r.x + d, r.y + d }, { order.cx, r.y + d }, { r.x + r.w - d, r.y + d },
        { r.x + d, order.cy }, { order.cx, order.cy }, { r.x + r.w - d, order.cy },
        { r.x + d, r.y + r.h - d }, { order.cx, r.y + r.h - d },
        { r.x + r.w - d, r.y + r.h - d },
    }
end

-- 精确热区 oracle（设计坐标，独立于生产模块常量）：
-- y220  +------------450------------+   90 gap   +------------450------------+
--       | standard (275,545)        |           | stellar (815,545)         |
-- y870  +---------------------------+           +---------------------------+
--       x50                       x500        x590                       x1040
-- 边界含端点，边外 0.001 与 gap 不切池。海报只切池，绝不能扣券/钻/发 gacha。
-- 旧 stellar(249,558) 在新左牌内，应选 standard；旧 x29..49 独有区域没有热区。

local NVG_NAMES = {
    "nvgSave", "nvgRestore", "nvgTranslate", "nvgScale", "nvgScissor", "nvgIntersectScissor",
    "nvgResetScissor", "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFillColor", "nvgFillPaint",
    "nvgFill", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgFontFace", "nvgFontSize",
    "nvgTextAlign", "nvgTextBounds", "nvgText", "nvgImagePattern", "nvgImagePatternTinted",
    "nvgCreateImage", "nvgImageSize", "nvgRGBA", "nvgRGBAf", "nvgFontBlur", "nvgMoveTo",
    "nvgLineTo", "nvgClosePath", "nvgLinearGradient", "nvgBoxGradient", "nvgCircle",
    "nvgShapeAntiAlias", "nvgTextLetterSpacing", "nvgTextLineHeight",
}

local function newContext(options)
    options = options or {}
    local ctx = { deps = {}, calls = {}, loads = {}, handles = {}, imageResponses = copy(options.imageResponses or {}), actions = {},
        pulls = {}, confirms = {}, histories = {}, messages = {}, sfx = {}, tutorial = {},
        subscribers = {}, shopInputs = {}, forbidden = {}, vg = options.vg or {},
        memory = { currency = { recruitTicket = 100, stellarRecruitTicket = 100, diamond = 100000,
            gachaPitySR = 2, gachaPitySSR = 7, urPityUR = 11 },
            heroes = { roster = { [1] = { level = 1 } } }, battle = { maxStageId = options.stage or 7001 } },
        allowConfirm = true, animPlaying = false, popupBlocking = false, targetOpen = false,
        clock = { elapsedTime = 100 }, stack = {}, tx = 0, ty = 0, sx = 1, sy = 1,
        fontSize = 40, align = NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, nextHandle = 0, review = options.review == true,
    } ---@type any
    for _, response in pairs(ctx.imageResponses) do
        if type(response) == "number" and response >= 0 then ctx.handles[response] = "reserved" end
    end
    contexts[#contexts + 1] = ctx
    local env = {} ---@type any
    ctx.env = env
    -- 不继承 _G：任何遗漏依赖须显式加 mock，绝不退回真实 File/require/Store。
    for _, key in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select",
        "tonumber", "tostring", "type", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal" }) do
        env[key] = _G[key]
    end
    env.math, env.string, env.table, env.utf8 = copy(math), copy(string), copy(table), copy(utf8)
    env._G, env.time, env.H_SEAM_BACK = env, ctx.clock, true
    for _, key in ipairs({ "NVG_ALIGN_LEFT", "NVG_ALIGN_RIGHT", "NVG_ALIGN_CENTER", "NVG_ALIGN_TOP",
        "NVG_ALIGN_MIDDLE", "NVG_ALIGN_BOTTOM", "NVG_ALIGN_BASELINE", "NVG_IMAGE_NEAREST",
        "NVG_ROUND", "FILE_READ", "FILE_WRITE", "FILE_READWRITE" }) do env[key] = _G[key] end
    env.print = noop -- 原 Page 每次点击日志太密；专项 harness 自己汇报每组结果。
    local function denied(label)
        return function()
            ctx.forbidden[#ctx.forbidden + 1] = label
            error("isolated tavern test forbids " .. label)
        end
    end
    local function deniedObject(label)
        return setmetatable({}, { __index = function(_, key) return denied(label .. "." .. tostring(key)) end })
    end
    env.File = denied("player File (all paths/modes)")
    env.cache, env.fileSystem = deniedObject("cache"), deniedObject("fileSystem")
    env.io, env.os, env.package, env.debug = deniedObject("io"), deniedObject("os"), deniedObject("package"), deniedObject("debug")
    env.clientCloud, env.serverCloud, env.network = deniedObject("clientCloud"), deniedObject("serverCloud"), deniedObject("network")
    env.loadfile, env.dofile, env.GetFileSystem = denied("loadfile"), denied("dofile"), denied("GetFileSystem")
    env.SubscribeToEvent, env.SendEvent = denied("global events"), denied("global SendEvent")
    env.engine = deniedObject("engine")
    local function record(kind, data)
        data = data or {}
        data.kind = kind
        ctx.calls[#ctx.calls + 1] = data
        return data
    end
    ctx.record = record
    local function shape(x, y, w, h)
        return { x = x * ctx.sx + ctx.tx, y = y * ctx.sy + ctx.ty, w = w * ctx.sx, h = h * ctx.sy }
    end
    env.nvgRGBA = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    env.nvgRGBAf = function(r, g, b, a) return env.nvgRGBA(r * 255, g * 255, b * 255, a * 255) end
    env.nvgSave = function()
        ctx.stack[#ctx.stack + 1] = { ctx.tx, ctx.ty, ctx.sx, ctx.sy, ctx.fontSize, ctx.align,
            copy(ctx.fillColor), copy(ctx.strokeColor), ctx.strokeWidth }
    end
    env.nvgRestore = function()
        local previous = assert(table.remove(ctx.stack), "unbalanced NanoVG restore")
        ctx.tx, ctx.ty, ctx.sx, ctx.sy, ctx.fontSize, ctx.align = table.unpack(previous, 1, 6)
        ctx.fillColor, ctx.strokeColor, ctx.strokeWidth = previous[7], previous[8], previous[9]
    end
    env.nvgTranslate = function(_, x, y) ctx.tx, ctx.ty = ctx.tx + x * ctx.sx, ctx.ty + y * ctx.sy end
    env.nvgScale = function(_, x, y) ctx.sx, ctx.sy = ctx.sx * x, ctx.sy * y end
    env.nvgBeginPath = function() ctx.shape, ctx.paint = {}, false end
    env.nvgRect = function(_, x, y, w, h) ctx.shape = shape(x, y, w, h) end
    env.nvgRoundedRect = env.nvgRect
    env.nvgFillColor = function(_, color) ctx.fillColor, ctx.paint = color, false end
    env.nvgFillPaint = function(_, paint) ctx.paint = paint end
    env.nvgFill = function()
        if ctx.paint and ctx.paint.image ~= nil then
            local r = ctx.shape
            record("image", { path = ctx.paint.path, handle = ctx.paint.image, rect = copy(r),
                cx = r.x + r.w * 0.5, cy = r.y + r.h * 0.5, w = r.w, h = r.h, alpha = ctx.paint.alpha,
                sample = copy(ctx.paint.rect), tint = copy(ctx.paint.tint) })
        else record("fill", { rect = copy(ctx.shape), color = copy(ctx.fillColor), paint = copy(ctx.paint) }) end
    end
    env.nvgStrokeColor = function(_, color) ctx.strokeColor = color end
    env.nvgStrokeWidth = function(_, width) ctx.strokeWidth = width end
    env.nvgStroke = function()
        record("stroke", { rect = copy(ctx.shape), color = copy(ctx.strokeColor), width = ctx.strokeWidth or 1 })
    end
    env.nvgImagePattern = function(_, x, y, w, h, _, image, alpha)
        return { image = image, path = ctx.handles[image], alpha = alpha, rect = shape(x, y, w, h) }
    end
    env.nvgImagePatternTinted = function(_, x, y, w, h, angle, image, color)
        local paint = env.nvgImagePattern(ctx.vg, x, y, w, h, angle, image, (color.a or 255) / 255)
        paint.tint = color
        return paint
    end
    env.nvgCreateImage = function(_, path)
        assert(type(path) == "string" and path:sub(1, 6) == "image/", "unexpected image path: " .. tostring(path))
        ctx.loads[#ctx.loads + 1] = path
        local response = ctx.imageResponses[path]
        if response ~= nil then
            if response == false then return nil end
            if response >= 0 then ctx.handles[response] = path end
            return response
        end
        local handle = ctx.nextHandle
        while ctx.handles[handle] ~= nil do handle = handle + 1 end
        ctx.nextHandle = handle + 1
        ctx.handles[handle] = path
        return handle
    end
    env.nvgImageSize = function(_, handle)
        local path = ctx.handles[handle]
        if path == STANDARD or path == STELLAR then return 900, 1300 end
        if path and path:find("KCLH_", 1, true) then return 675, 1000 end
        return 1080, 2400
    end
    env.nvgFontSize = function(_, size) ctx.fontSize = size end
    env.nvgTextAlign = function(_, align) ctx.align = align end
    env.nvgTextBounds = function(_, _, _, text) return (utf8.len(text) or #text) * ctx.fontSize end
    env.nvgText = function(_, x, y, text)
        local width = env.nvgTextBounds(ctx.vg, 0, 0, text)
        local left = x
        if ctx.align & NVG_ALIGN_CENTER ~= 0 then left = x - width * 0.5
        elseif ctx.align & NVG_ALIGN_RIGHT ~= 0 then left = x - width end
        local top = y - ctx.fontSize * 0.5
        if ctx.align & NVG_ALIGN_TOP ~= 0 then top = y
        elseif ctx.align & NVG_ALIGN_BOTTOM ~= 0 then top = y - ctx.fontSize end
        record("text", { text = text, x = x * ctx.sx + ctx.tx, y = y * ctx.sy + ctx.ty,
            rect = shape(left, top, width, ctx.fontSize), fontSize = ctx.fontSize, color = copy(ctx.fillColor) })
        return x + width
    end
    for _, name in ipairs({ "nvgScissor", "nvgIntersectScissor", "nvgResetScissor", "nvgFontFace",
        "nvgFontBlur", "nvgMoveTo", "nvgLineTo", "nvgClosePath", "nvgCircle", "nvgShapeAntiAlias",
        "nvgTextLetterSpacing", "nvgTextLineHeight" }) do env[name] = noop end
    for _, name in ipairs({ "nvgLinearGradient", "nvgBoxGradient" }) do env[name] = function() return {} end end
    if ctx.review then
        -- 只开放绘图API，其他全局仍是同一隔离 sandbox。没有 require/package.loaded 预注入。
        for _, name in ipairs(NVG_NAMES) do env[name] = assert(_G[name], "missing real NanoVG " .. name) end
        env.nvgCreateImage = function(vg, path, flags)
            assert(type(path) == "string" and path:sub(1, 6) == "image/", "review only loads image resources")
            ctx.loads[#ctx.loads + 1] = path
            return nativeCreateImage(vg, path, flags)
        end
    end

    local function mock(name, values)
        ctx.deps[name] = setmetatable(values, { __index = function(_, method)
            return denied("unmocked " .. name .. "." .. tostring(method))
        end })
        return ctx.deps[name]
    end
    mock("config.GameConfig", { Design = { WIDTH = 1080, HEIGHT = 2400 } })
    mock("core.BattleLayout", {})
    mock("config.HeroConfig", { SHARD_DUPE_CONVERT = 10,
        get = function(id) return { name = "测试角色" .. tostring(id) } end })
    mock("shared.Protocol", { ACTION_TYPES = { GACHA_PULL = "gacha_pull", TAVERN_SHOP_BUY = "tavern_shop_buy" } })
    mock("core.I18n", { t = function(text) return text == "tavern" and "酒馆" or text end,
        get = function() return "zh_CN" end, lookup = function(text) return text end })
    mock("runtime.ClientDispatcher", {
        get = function(name) return ctx.memory[name] end,
        subscribe = function(name, callback) ctx.subscribers[name] = callback end,
    })
    mock("core.GameState", {
        getRecruitTicket = function() return ctx.memory.currency.recruitTicket end,
        getStellarRecruitTicket = function() return ctx.memory.currency.stellarRecruitTicket end,
        getGems = function() return ctx.memory.currency.diamond end,
    })
    mock("systems.GachaSystem", {
        setPityCounts = function(sr, ssr) ctx.pitySR, ctx.pitySSR = sr, ssr end,
        getSSRPityRemain = function() return 80 - (ctx.pitySSR or 0) end,
        canPull = function(count)
            if ctx.memory.currency.recruitTicket >= count then return true, "ticket" end
            if ctx.memory.currency.diamond >= count * 180 then return true, "diamond" end
            return false, "none"
        end,
        pull = function(count, payType)
            ctx.pulls[#ctx.pulls + 1] = { count = count, payType = payType }
            return nil -- 明确spy出口：不扣币、不产生结果/历史。
        end,
    })
    ctx.popups = mock("ui.tavern.TavernPopups", {
        setContext = function(value) ctx.popupContext = value end,
        init = function() ctx.popupInit = (ctx.popupInit or 0) + 1 end,
        resetAll = function() ctx.popupBlocking = false end,
        isBlocking = function() return ctx.popupBlocking end,
        isRecruitConfirmOpen = function() return ctx.confirmOpen == true end,
        checkAndShowConfirm = function(count)
            ctx.confirms[#ctx.confirms + 1] = count
            return ctx.allowConfirm
        end,
        recordHistory = function(results, pool) ctx.histories[#ctx.histories + 1] = { results = results, pool = pool } end,
        showFloatText = function(text, x, y) ctx.messages[#ctx.messages + 1] = { text = text, x = x, y = y } end,
        formatGachaFailReason = tostring,
        drawAll = noop, update = noop, openInfo = noop,
        handleInput = function() return true end,
        handleDragBegin = noop, handleDragMove = noop, handleDragEnd = noop, handleScroll = noop,
    })
    mock("ui.tavern.RecruitAnim", { init = noop, setOnAgain = function(fn) ctx.again = fn end,
        isPlaying = function() return ctx.animPlaying end,
        draw = noop, update = noop, start = denied("unexpected recruit animation/results"),
        handleInput = function() return true end,
    })
    mock("ui.tavern.TavernShopPage", { init = noop, resetScroll = noop, syncPurchasedFromStore = noop,
        drawContent = function() record("shop") end,
        handleInput = function(x, y) ctx.shopInputs[#ctx.shopInputs + 1] = { x, y }; return false end,
        isPendingBuy = function() return false end, onBuyResult = denied("unexpected shop purchase"),
        update = noop, handleDragBegin = noop, handleDragMove = noop, handleDragEnd = noop, handleScroll = noop,
    })
    mock("ui.tavern.TargetRecruitPanel", { init = noop, draw = noop,
        isOpen = function() return ctx.targetOpen end, close = function() ctx.targetOpen = false end,
        open = function(pool) ctx.targetOpen = true; ctx.targetPool = pool end,
        handleInput = function() return true end,
    })
    mock("systems.ButtonFeedback", { begin = function(_, id, cx, cy, w, h)
            record("button", { id = id, cx = cx, cy = cy, w = w, h = h }); return false
        end, finish = noop, trigger = function(id) ctx.feedback = id end })
    mock("systems.GameSFX", { playUIMove = function(n) ctx.sfx[#ctx.sfx + 1] = n end })
    mock("systems.TutorialManager", { isActive = function() return true end,
        registerHotspot = function(id, cx, cy, w, h, region)
            record("hotspot", { id = id, cx = cx, cy = cy, w = w, h = h, region = region })
        end,
        setNewHeroId = noop, notifyEvent = function(name) ctx.tutorial[#ctx.tutorial + 1] = name end,
    })
    mock("systems.StoryPlayer", { onPlace = noop })

    env.require = function(name)
        if ctx.deps[name] ~= nil then return ctx.deps[name] end
        assert(SOURCE_FILES[name], "unexpected require blocked: " .. tostring(name))
        local chunk, why = load(source(name), "@" .. SOURCE_FILES[name], "t", env)
        assert(chunk, why)
        local module = chunk()
        assert(type(module) == "table", "expected real module: " .. name)
        ctx.deps[name] = module
        return module
    end
    ctx.drawUtil = env.require("core.DrawUtil")
    -- 页面装饰叶子保持 mock；review 对其实际画简单底板，核心 Page/Orders/DrawUtil 均真实。
    mock("core.DarkIcon", { drawNine = function(vg, _, x, y, w, h)
        record("nine", { rect = { x = x, y = y, w = w, h = h } })
        if ctx.review then
            env.nvgBeginPath(vg); env.nvgRoundedRect(vg, x, y, w, h, 12)
            env.nvgFillColor(vg, env.nvgRGBA(28, 22, 18, 245)); env.nvgFill(vg)
            env.nvgStrokeColor(vg, env.nvgRGBA(152, 127, 74, 220)); env.nvgStrokeWidth(vg, 3); env.nvgStroke(vg)
        end
    end })
    mock("ui.town.TownPageChrome", {
        easeOutCubic = function(t) return 1 - (1 - t) ^ 3 end, easeInCubic = function(t) return t ^ 3 end,
        drawNamePlate = function(vg, image, text, opts)
            record("nameplate")
            if ctx.review then
                ctx.drawUtil.drawImageCentered(vg, image, 147, 136, 294, 123, 1)
                ctx.drawUtil.drawTextStroke(vg, opts.textCX, opts.textCY, text, opts.font,
                    NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 244, 237, 224, 3)
            end
        end,
        drawBack = noop, hitBack = function() return false end,
        tabSlide = function(state, mapping) return mapping[state.tab], mapping[state.tabFrom], 1 end,
        hitTab = function(x, y, items, w, h)
            for index, item in ipairs(items) do if ctx.drawUtil.hitTest(x, y, item.cx, item.cy, w, h) then return index end end
            return nil
        end,
        drawTabBar = function(vg, _, config)
            record("tabs")
            if ctx.review then
                for index, item in ipairs(config.items) do
                    ctx.drawUtil.drawRoundedRectCentered(vg, item.cx, item.cy, config.sliderW, config.sliderH,
                        12, 28, 22, 18, 240)
                    ctx.drawUtil.drawTextStroke(vg, item.textX, item.textY, item.name, config.font,
                        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 244, 237, 224, 3)
                end
            end
        end,
    })
    -- 新模块最终API已冻结：额外直测load失败/句柄0/纯入口，不替代上面的真实Page接线。
    ctx.imageResponses = copy(options.imageResponses or {})
    ctx.ur = env.require("config.UrGachaConfig")
    ctx.ur.setPoolEnabled(options.enabled ~= false)
    ctx.page = env.require("ui.tavern.TavernPage")
    ctx.page.setSendAction(function(action, params)
        ctx.actions[#ctx.actions + 1] = { action = action, params = copy(params) }
        return false -- 绝不转发；真实Page应释放pending，后续每个按钮边界可独立验证。
    end)
    ctx.initialMemory = copy(ctx.memory)
    ctx.page.init(ctx.vg)
    ctx.page.open()
    ctx.clock.elapsedTime = 101 -- 真实页面滑入0.45s已完成；无 main/真实clock写入。
    ctx.page.update(1)
    function ctx.click(x, y) return ctx.page.handleInput(x, y) end
    function ctx.draw()
        ctx.calls, ctx.stack, ctx.tx, ctx.ty, ctx.sx, ctx.sy = {}, {}, 0, 0, 1, 1
        ctx.page.draw(ctx.vg)
        if not ctx.review then eq(#ctx.stack, 0, "Page/Orders balance NanoVG save/restore") end
        return ctx.calls
    end
    function ctx.safe()
        eq(#ctx.forbidden, 0, "no player IO/cloud/global/unmocked dependency calls")
        check(same(ctx.memory, ctx.initialMemory), "UI never writes memory currency/roster/battle snapshot")
    end
    return ctx
end

local function calls(ctx, kind, path)
    local result = {}
    for _, entry in ipairs(ctx.calls) do
        if entry.kind == kind and (path == nil or entry.path == path) then result[#result + 1] = entry end
    end
    return result
end
local function oneImage(ctx, order)
    local list = {}
    for _, image in ipairs(calls(ctx, "image", order.path)) do
        if not image.tint then list[#list + 1] = image end
    end
    eq(#list, 1, order.id .. " base poster drawn exactly once")
    local image = assert(list[1])
    near(image.cx, order.cx, order.id .. " center x")
    near(image.cy, order.cy, order.id .. " center y")
    near(image.w, order.w, order.id .. " width")
    near(image.h, order.h, order.id .. " height")
    check(image.alpha > 0, order.id .. " visible image")
    near(image.sample.w / image.sample.h, 900 / 1300, order.id .. " complete PNG aspect, not old 440x204")
    return image
end
local function selectedFrames(ctx, order)
    local result = {}
    local box = rect(order.cx, order.cy, order.w, order.h)
    for _, call in ipairs(calls(ctx, "stroke")) do
        if call.rect.x and call.rect.w > order.w * 0.5 and call.rect.h > order.h * 0.5
            and math.abs(call.rect.x + call.rect.w * 0.5 - order.cx) < 5 then
            check(within(call.rect, box, (call.width or 0) * 0.5), order.id .. " selected ink inside 450x650")
            result[#result + 1] = call
        end
    end
    return result
end
local function noRecruit(ctx, message)
    eq(#ctx.actions, 0, message .. " no currency/gacha action")
    eq(#ctx.pulls, 0, message .. " no local gacha consume")
    eq(#ctx.confirms, 0, message .. " no purchase confirmation")
    eq(#ctx.histories, 0, message .. " no recruit history")
    eq(#ctx.tutorial, 0, message .. " no fake gacha tutorial event")
    ctx.safe()
end

local function isolationCases()
    local first = newContext()
    local second = newContext({ stage = 7000 })
    check(first.page ~= second.page and first.ur ~= second.ur, "real Page/Ur module cache belongs to each env")
    first.click(815, 545)
    eq(first.page.getSelectedPoolId(), "stellar", "first isolated instance switched")
    eq(second.page.getSelectedPoolId(), "standard", "second independent instance not switched")
    eq(first.popupInit, 1, "Page.init uses mock Popups once")
    local before = #first.loads
    first.page.init(first.vg)
    eq(#first.loads, before, "idempotent init does not reload images")
    noRecruit(first, "isolated page selection")
    noRecruit(second, "isolated closed threshold")
end
local function resourceAndLayoutCases()
    -- 资源读只走已知两张 Image，不使用 File/player API，不创建 GPU。
    for _, order in ipairs(ORDERS) do
        local image = assert(nativeCache:GetResource("Image", order.path), "missing PNG " .. order.path)
        eq(image:GetWidth(), 900, order.id .. " actual PNG width")
        eq(image:GetHeight(), 1300, order.id .. " actual PNG height")
    end
    local ctx = newContext()
    ctx.draw()
    for _, order in ipairs(ORDERS) do oneImage(ctx, order) end
    check(#selectedFrames(ctx, ORDERS[1]) > 0, "selected standard has large inset frame")
    local loadCounts = { [STANDARD] = 0, [STELLAR] = 0 }
    for _, path in ipairs(ctx.loads) do if loadCounts[path] then loadCounts[path] = loadCounts[path] + 1 end end
    for _, order in ipairs(ORDERS) do eq(loadCounts[order.path], 1, order.id .. " requested correct PNG once") end
    for _ = 1, 3 do ctx.draw() end
    for _, order in ipairs(ORDERS) do
        local count = 0
        for _, path in ipairs(ctx.loads) do if path == order.path then count = count + 1 end end
        eq(count, 1, order.id .. " not reloaded on draw")
    end
    ctx.click(815, 545); ctx.draw()
    check(#selectedFrames(ctx, ORDERS[2]) > 0, "selected stellar frame matches whole right poster")
    local poolTextCount = 0
    for _, call in ipairs(calls(ctx, "text")) do
        if call.y >= 220 and call.y <= 870 then
            local left, right = rect(275, 545, 450, 650), rect(815, 545, 450, 650)
            check(within(call.rect, left) or within(call.rect, right), "poster text inside its 450x650: " .. call.text)
            poolTextCount = poolTextCount + 1
        end
    end
    check(poolTextCount > 0, "real Orders renders poster labels (not empty spy)")
    noRecruit(ctx, "draw/init/poster switch")
end
local function fullHotspotCases()
    local ctx = newContext()
    for index, order in ipairs(ORDERS) do
        local opposite = ORDERS[3 - index]
        for _, inset in ipairs({ 0, 0.001, 24 }) do
            for number, point in ipairs(boundaryPoints(order, inset)) do
                ctx.click(opposite.cx, opposite.cy)
                eq(ctx.page.getSelectedPoolId(), opposite.id, "reset opposite before poster edge")
                ctx.click(point[1], point[2])
                eq(ctx.page.getSelectedPoolId(), order.id, order.id .. " whole poster boundary/inset=" .. inset .. "/" .. number)
            end
        end
        local box = rect(order.cx, order.cy, order.w, order.h)
        local outside = { { box.x - 0.001, order.cy }, { box.x + box.w + 0.001, order.cy },
            { order.cx, box.y - 0.001 }, { order.cx, box.y + box.h + 0.001 } }
        for _, point in ipairs(outside) do
            ctx.click(opposite.cx, opposite.cy); ctx.click(point[1], point[2])
            eq(ctx.page.getSelectedPoolId(), opposite.id, order.id .. " edge-outside not clickable")
        end
    end
    noRecruit(ctx, "all poster edges")
end
local function gapAndOldHotspotCases()
    local ctx = newContext()
    for _, base in ipairs(ORDERS) do
        for _, x in ipairs({ 500.001, 515, 540, 565, 589.999 }) do
            for _, y in ipairs({ 220, 300, 545, 700, 870 }) do
                ctx.click(base.cx, base.cy); ctx.click(x, y)
                eq(ctx.page.getSelectedPoolId(), base.id, "90px gap does not switch " .. x .. "/" .. y)
            end
        end
    end
    ctx.click(815, 545); ctx.click(249, 558)
    eq(ctx.page.getSelectedPoolId(), "standard", "old stellar center now belongs only to new standard poster")
    for _, y in ipairs({ 456, 500, 558, 620, 660 }) do
        for _, x in ipairs({ 29, 40, 49.999 }) do
            ctx.click(815, 545); ctx.click(x, y)
            eq(ctx.page.getSelectedPoolId(), "stellar", "old-only stellar hotspot is dead")
        end
    end
    eq(#ctx.messages, 0, "gap/old hotspot has no lock prompt")
    noRecruit(ctx, "gap and obsolete hotspot")
end
local function thresholdAndDisabledCases()
    local ctx = newContext({ stage = 7000 })
    local ur = ctx.ur
    for _, sample in ipairs({ { value = 0, want = false }, { value = 7000, want = false },
        { value = 7001, want = true }, { value = "7001", want = true }, { value = 14001, want = true },
        { value = "not-a-stage", want = false } }) do
        eq(ur.checkPoolUnlocked({}, {}, { maxStageId = sample.value }), sample.want, "real 7001 gate " .. sample.value)
    end
    ctx.draw()
    oneImage(ctx, ORDERS[2])
    local lockedDraw = copy(ctx.calls)
    local lockedLayers = calls(ctx, "image", STELLAR)
    eq(#lockedLayers, 2, "locked poster draws base plus alpha-matched tint, not rectangular shade")
    local shade = assert(lockedLayers[2])
    check(shade.tint and shade.tint.r == 0 and shade.tint.g == 0 and shade.tint.b == 0
        and shade.tint.a > 0, "locked poster has explicit black tinted PNG alpha mask")
    check(same(shade.rect, lockedLayers[1].rect), "locked shade uses exact base poster bounds")
    eq(#selectedFrames(ctx, ORDERS[2]), 0, "locked poster cannot have selected large frame")
    local lockText, lockReason = false, false
    for _, text in ipairs(calls(ctx, "text")) do
        lockText = lockText or text.text == "未解锁"
        lockReason = lockReason or text.text == "进入地狱难度后开放"
        if text.y >= 220 and text.y <= 870 then
            check(within(text.rect, rect(275, 545, 450, 650)) or within(text.rect, rect(815, 545, 450, 650)),
                "locked poster text remains inside its own bounds: " .. text.text)
        end
    end
    check(lockText and lockReason, "locked visual state explicitly labels unlock condition")
    for _, point in ipairs(boundaryPoints(ORDERS[2])) do
        local previous = #ctx.messages
        ctx.click(point[1], point[2])
        eq(ctx.page.getSelectedPoolId(), "standard", "locked poster not selected at whole-card edge")
        eq(#ctx.messages, previous + 1, "locked poster explains unlock at every visible edge")
        check(ctx.messages[#ctx.messages].text:find("地狱", 1, true), "lock message says hell threshold")
    end
    ctx.click(249, 558)
    eq(#ctx.messages, 9, "old stellar center cannot show hidden lock prompt inside standard")
    ctx.memory.battle.maxStageId = 7001
    ctx.initialMemory = copy(ctx.memory)
    ctx.draw()
    oneImage(ctx, ORDERS[2])
    eq(#calls(ctx, "image", STELLAR), 1, "unlocked-but-unselected poster has no locked dark tint")
    eq(#selectedFrames(ctx, ORDERS[2]), 0, "unselected unlocked poster has no selected large frame")
    check(not same(lockedDraw, ctx.calls), "locked and unlocked-unselected draw semantics differ")
    local chooseText = false
    for _, text in ipairs(calls(ctx, "text")) do
        if text.x == 815 then
            chooseText = chooseText or text.text == "选择"
            check(text.text ~= "未解锁" and text.text ~= "进入地狱难度后开放", "unselected unlocked is not mislabeled locked")
        end
    end
    check(chooseText, "unselected unlocked right poster says choose")
    local previous = #ctx.messages
    ctx.click(815, 545)
    eq(ctx.page.getSelectedPoolId(), "stellar", "7001 live refresh enables right poster")
    eq(#ctx.messages, previous, "unlocked-unselected selection does not show locked prompt")
    noRecruit(ctx, "threshold gate")
    local disabled = newContext({ enabled = false })
    disabled.draw()
    eq(#calls(disabled, "image", STELLAR), 0, "disabled stellar pool not drawn")
    for _, point in ipairs(boundaryPoints(ORDERS[2])) do disabled.click(point[1], point[2]) end
    disabled.click(29, 558); disabled.click(249, 558)
    eq(disabled.page.getSelectedPoolId(), "standard", "disabled pool has no visible/obsolete hidden hotspot")
    eq(#disabled.messages, 0, "disabled pool invisible zone does not show lock prompt")
    noRecruit(disabled, "disabled pool")
end
local function buttonAndCurrencyCases()
    for index, order in ipairs(ORDERS) do
        local ctx = newContext()
        ctx.click(order.cx, order.cy); ctx.draw()
        local buttons = calls(ctx, "button")
        for _, wanted in ipairs({ { id = "tavern_recruit1", cx = 314, cy = 1902, w = 410, h = 100, count = 1 },
            { id = "tavern_recruit10", cx = 766, cy = 1902, w = 410, h = 100, count = 10 } }) do
            local matching = {}
            for _, button in ipairs(buttons) do if button.id == wanted.id then matching[#matching + 1] = button end end
            eq(#matching, 1, "existing button drawn once " .. wanted.id)
            for _, key in ipairs({ "cx", "cy", "w", "h" }) do eq(matching[1][key], wanted[key], "unchanged button " .. key) end
            for _, point in ipairs(boundaryPoints(wanted)) do
                local before = #ctx.actions
                ctx.click(point[1], point[2])
                eq(#ctx.actions, before + 1, "existing 1/10 boundary sends exactly one mock request")
                eq(ctx.confirms[#ctx.confirms], wanted.count, "existing confirmation wiring count")
                local action = ctx.actions[#ctx.actions]
                eq(action.action, "gacha_pull", "unchanged action ID")
                eq(action.params.count, wanted.count, "unchanged count")
                eq(action.params.poolId, order.id, "selected poster only changes request poolId")
                eq(action.params.payType, "ticket", "ticket payment unchanged")
                eq(ctx.page.isRecruitBusy(), false, "failed mock send clears pending between independent clicks")
            end
        end
        eq(#ctx.pulls, 0, "injected action bridge never consumes local currency")
        eq(#ctx.histories, 0, "failed mock requests never touch recruit history")
        ctx.safe()
        local confirmations, actions = #ctx.confirms, #ctx.actions
        ctx.allowConfirm = false
        ctx.click(314, 1902); ctx.click(766, 1902)
        eq(#ctx.confirms, confirmations + 2, "real buttons still go through confirmation gate")
        eq(#ctx.actions, actions, "confirmation rejection adds no action")
        ctx.safe()
    end
end
local function shopAndBlockingCases()
    local ctx = newContext()
    ctx.click(815, 545)
    ctx.click(740, 2308); ctx.draw()
    eq(#calls(ctx, "shop"), 1, "real Page switched to shop branch")
    eq(#calls(ctx, "image", STANDARD), 0, "shop does not draw standard poster")
    eq(#calls(ctx, "image", STELLAR), 0, "shop does not draw stellar poster")
    for _, order in ipairs(ORDERS) do
        for _, point in ipairs(boundaryPoints(order)) do ctx.click(point[1], point[2]) end
    end
    ctx.click(249, 558); ctx.click(40, 558)
    eq(ctx.page.getSelectedPoolId(), "stellar", "shop poster coordinates never switch pool")
    check(#ctx.shopInputs >= 18, "shop input actually forwarded to mock shop, not swallowed fixture")
    eq(#ctx.messages, 0, "shop has no poster lock interactions")
    noRecruit(ctx, "shop posters")
    ctx.click(340, 2308)
    ctx.popupBlocking = true
    ctx.click(275, 545)
    eq(ctx.page.getSelectedPoolId(), "stellar", "modal popup blocks underlying poster")
    ctx.popupBlocking, ctx.animPlaying = false, true
    ctx.click(275, 545)
    eq(ctx.page.getSelectedPoolId(), "stellar", "recruit animation blocks underlying poster")
    ctx.animPlaying, ctx.targetOpen = false, true
    ctx.click(275, 545)
    eq(ctx.page.getSelectedPoolId(), "stellar", "target modal blocks underlying poster")
    ctx.targetOpen = false
    ctx.page.forceClose(); ctx.click(275, 545)
    eq(ctx.page.getSelectedPoolId(), "stellar", "closed Page blocks underlying poster")
    noRecruit(ctx, "blocking/closed posters")
end
local function refreshMetaCases()
    local ctx = newContext()
    for round = 1, 3 do
        ctx.page.refreshDisplay()
        if ctx.subscribers.currency then ctx.subscribers.currency(ctx.memory.currency) end
        ctx.page.setStellarUpHero(nil, round == 2 and 16 or 20, { name = "测试UP" .. round })
        ctx.draw()
        for _, order in ipairs(ORDERS) do oneImage(ctx, order) end
        ctx.click(815, 545)
        eq(ctx.page.getSelectedPoolId(), "stellar", "refresh meta retains new right poster hotspot")
        ctx.click(249, 558)
        eq(ctx.page.getSelectedPoolId(), "standard", "refresh meta does not revive old stellar hotspot")
    end
    ctx.page.forceClose(); ctx.page.open(); ctx.clock.elapsedTime = 102
    ctx.draw()
    for _, order in ipairs(ORDERS) do oneImage(ctx, order) end
    noRecruit(ctx, "meta/up/currency/reopen refresh")
end
local function moduleFailureCases()
    for _, response in ipairs({ -1, false }) do
        local ctx = newContext({ stage = 7000, imageResponses = { [STANDARD] = response, [STELLAR] = response } })
        local orders = ctx.env.require("ui.tavern.TavernRecruitOrders")
        local pools = orders.createPools()
        orders.refreshPoolMeta(pools)
        eq(pools[1].cx, 275, "actual module standard layout")
        eq(pools[2].cx, 815, "actual module stellar layout")
        ctx.draw()
        eq(#calls(ctx, "image", STANDARD), 0, "missing standard image uses visible fallback")
        eq(#calls(ctx, "image", STELLAR), 0, "missing stellar image uses visible fallback")
        for _, order in ipairs(ORDERS) do
            local visible = 0
            for _, fill in ipairs(calls(ctx, "fill")) do
                if fill.rect.x and fill.rect.w > order.w * 0.5 and fill.rect.h > order.h * 0.5
                    and within(fill.rect, rect(order.cx, order.cy, order.w, order.h)) then visible = visible + 1 end
            end
            check(visible > 0, "missing poster has visible non-hidden fallback " .. order.id)
            local index, pool = orders.hitTest(order.cx, order.cy, pools)
            eq(index, order.id == "standard" and 1 or 2, "real module hits fallback whole poster")
            eq(pool.id, order.id, "module hit returns correct pool without recruiting")
        end
        local before = #ctx.loads
        for _ = 1, 3 do ctx.draw(); orders.init(ctx.vg, pools) end
        eq(#ctx.loads, before, "missing image not reloaded every draw/idempotent init")
        ctx.click(815, 545)
        eq(ctx.page.getSelectedPoolId(), "standard", "missing art still respects actual locked gate")
        noRecruit(ctx, "module missing artwork")
    end
    local ctx = newContext({ imageResponses = { [STANDARD] = 0 } })
    ctx.draw()
    eq(oneImage(ctx, ORDERS[1]).handle, 0, "real module and DrawUtil accept valid image handle0")
    local orders = ctx.env.require("ui.tavern.TavernRecruitOrders")
    ctx.calls = {}
    orders.draw(ctx.vg, {}, nil)
    eq(#ctx.calls, 0, "empty module draw balanced/inert with nil selected index")
    eq(#ctx.stack, 0, "empty module draw balances save/restore")
    local first, second = orders.hitTest(815, 545, {})
    eq(first, nil, "empty module hit index nil")
    eq(second, nil, "empty module hit pool nil")
    orders.refreshPoolMeta({})
    noRecruit(ctx, "module handle0 empty pools")
end
local function finalSafetyCases()
    for _, ctx in ipairs(contexts) do if ctx.initialMemory then ctx.safe() end end
    eq(File, nativeFile, "global File untouched")
    eq(cache, nativeCache, "global cache untouched")
    eq(time, nativeTime, "global runtime clock untouched")
    eq(nvgCreateImage, nativeCreateImage, "global NanoVG API untouched")
    for name in pairs(SOURCE_FILES) do eq(package.loaded[name], initialLoaded[name], "global module cache untouched " .. name) end
    for _, path in ipairs(sourceReads) do
        local allowed = false
        for _, permitted in pairs(SOURCE_FILES) do if path == permitted then allowed = true end end
        check(allowed and path:sub(1, 1) == "/", "all native File reads are absolute allowlisted Lua source")
    end
end

local function reviewMode()
    for _, argument in ipairs(GetArguments()) do
        if argument == "-recruit-orders-review" then return "unlocked" end
        local value = argument:match("^%-recruit%-orders%-review=(.+)$")
        if value then
            assert(value == "locked" or value == "unlocked" or value == "stellar", "invalid review state")
            return value
        end
    end
    return nil
end
---@type any
local reviewContext = nil
---@type any
local reviewVG = nil
local reviewFrameCount = 0
local function startReview(mode)
    reviewVG = assert(nvgCreate(1), "cannot create actual review NanoVG context")
    check(nvgCreateFont(reviewVG, "sans", "Fonts/MiSans-Regular.ttf") >= 0, "actual review font loaded")
    reviewContext = newContext({ review = true, vg = reviewVG, stage = mode == "locked" and 7000 or 7001 })
    if mode == "stellar" then reviewContext.click(815, 545) end
    SubscribeToEvent(reviewVG, "NanoVGRender", "HandleTavernRecruitOrdersReview")
    print(TAG .. "REVIEW state=" .. mode .. " actual Page/Orders/DrawUtil/PNG; chrome/action/history/save remain mocked")
end
function HandleTavernRecruitOrdersReview()
    local w, h, dpr = graphics:GetWidth(), graphics:GetHeight(), graphics:GetDPR()
    local logicalW, logicalH = w / dpr, h / dpr
    local scale = math.min(logicalW / 1080, logicalH / 2400)
    nvgBeginFrame(reviewVG, logicalW, logicalH, dpr)
    nvgSave(reviewVG)
    nvgScale(reviewVG, scale, scale)
    nvgTranslate(reviewVG, (logicalW / scale - 1080) * 0.5, (logicalH / scale - 2400) * 0.5)
    reviewContext.page.draw(reviewVG)
    nvgRestore(reviewVG)
    nvgEndFrame(reviewVG)
    reviewFrameCount = reviewFrameCount + 1
    if reviewFrameCount == 1 then
        noRecruit(reviewContext, "actual review render")
        print(TAG .. "REVIEW FIRST FRAME PASS (not an automated visual-quality assertion)")
    end
end

function Start()
    local ok, mode = pcall(reviewMode)
    if not ok then log:Write(LOG_ERROR, TAG .. tostring(mode)); engine:Exit(); return end
    if mode then
        local started, why = pcall(startReview, mode)
        if not started then log:Write(LOG_ERROR, TAG .. "REVIEW FAIL " .. tostring(why)); engine:Exit() end
        return -- 截图/validate参数负责退出，不能在Start立刻Exit吞掉真实绘制帧。
    end
    local tests = {
        { "independent-real-Page-and-mocked-history", isolationCases },
        { "two-real-900x1300-assets-and-450x650-layout", resourceAndLayoutCases },
        { "full-poster-inclusive-edges-and-outside", fullHotspotCases },
        { "gap-and-obsolete-stellar-hotspot", gapAndOldHotspotCases },
        { "real-7001-gate-locked-vs-unselected-and-disabled", thresholdAndDisabledCases },
        { "unchanged-1-and-10-buttons-and-currency-action-spy", buttonAndCurrencyCases },
        { "shop-modal-animation-and-closed-no-poster-interaction", shopAndBlockingCases },
        { "refresh-meta-up-and-currency-never-revive-old-hotspot", refreshMetaCases },
        { "real-module-missing-images-handle0-and-empty-pools", moduleFailureCases },
        { "final-all-contexts-player-IO-and-global-isolation", finalSafetyCases },
    }
    for _, test in ipairs(tests) do
        local passed, why = pcall(test[2])
        groups = groups + 1
        if passed then print(TAG .. "[PASS] " .. test[1])
        else
            local message = test[1] .. " " .. tostring(why)
            failures[#failures + 1] = message
            print(TAG .. "[FAIL] " .. message)
            log:Write(LOG_ERROR, TAG .. message)
        end
    end
    if #failures == 0 then print(TAG .. "RESULT ALL PASS groups=" .. groups .. " checks=" .. checks)
    else print(TAG .. "RESULT FAIL groups=" .. groups .. " checks=" .. checks .. " failures=" .. #failures) end
    -- 不在Start调用Exit：让必传-validate完成帧预算、写JSON；立即Exit会漏报告。
end
