-- 仓库网格滚动 / 道具靠线布局隔离回归。
-- 由主会话统一 LSP/build 后运行指定 Runtime；必须看到本测试 ALL PASS，exit0 不足。
-- 仅 cache:GetFile 读取下面八个固定 Lua 源；私有 env/require，无 main/Boot/PlayerStore.Init。
-- 覆盖：真实 Panel 完整 applyLayout/常量、open/持有入口、update、handleInput、drawBody，
--       真实 GridHost/预算列表/Grids、EquipLink，以及真实 DarkIcon.drawNine 的金线绘图调用。
-- 边界：不执行整个 Panel 模块/资源初始化/详情弹窗/分解模块/宿主视口；这些叶子为 stub。
-- NanoVG 用 CPU scissor/translate 记录器，不代表 GPU 像素、设备触控或字体字墨验收。

local PREFIX = "[backpack_grid_scroll_test] "
local passes, failures = 0, {}
local function check(condition, label)
    if condition then passes = passes + 1
    else failures[#failures + 1] = label; print(PREFIX .. "FAIL " .. label) end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
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
local function hitTest(x, y, cx, cy, w, h)
    return math.abs(x - cx) <= w * .5 and math.abs(y - cy) <= h * .5
end

-- 白名单是字面量完整路径；不由 require 参数拼任意磁盘路径，不提供原生 File 给被测代码。
local SOURCE_PATHS = {
    ["ui.backpack.BackpackPanel"] = "ui/backpack/BackpackPanel.lua",
    ["ui.backpack.BackpackGridHost"] = "ui/backpack/BackpackGridHost.lua",
    ["ui.backpack.BackpackEquipmentList"] = "ui/backpack/BackpackEquipmentList.lua",
    ["ui.backpack.BackpackGrids"] = "ui/backpack/BackpackGrids.lua",
    ["ui.backpack.BackpackEquipLink"] = "ui/backpack/BackpackEquipLink.lua",
    ["core.DarkIcon"] = "core/DarkIcon.lua",
    ["core.NumberUtil"] = "core/NumberUtil.lua",
    ["config.GameConfig"] = "config/GameConfig.lua",
}
local sourceCache = {}
local nativeCache = cache
local nativeRequire, nativePackage, nativeFile = require, package, File
local sourceReads = 0
local function readSource(name)
    local path = assert(SOURCE_PATHS[name], "source outside fixed whitelist: " .. tostring(name))
    if sourceCache[name] then return sourceCache[name] end
    local file = assert(nativeCache:GetFile(path), "missing whitelisted Lua " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    sourceReads = sourceReads + 1
    local text = table.concat(lines, "\n")
    sourceCache[name] = text
    return text
end
-- 完整、唯一边界切片；边界漂移即失败，不静默换用测试公式/旧代码。
local function section(source, first, after)
    local beginAt = assert(source:find(first, 1, true), "missing section " .. first)
    assert(not source:find(first, beginAt + #first, true), "ambiguous section " .. first)
    local endAt = assert(source:find(after, beginAt + #first, true), "missing section end " .. after)
    return source:sub(beginAt, endAt - 1)
end
local function intersection(a, b)
    if not a then return b end
    local x, y = math.max(a.x, b.x), math.max(a.y, b.y)
    return { x = x, y = y, w = math.max(0, math.min(a.x + a.w, b.x + b.w) - x),
        h = math.max(0, math.min(a.y + a.h, b.y + b.h) - y) }
end
local function rectOf(call)
    return { x = call.cx - call.w * .5, y = call.cy - call.h * .5 + call.ty,
        w = call.w, h = call.h }
end

local function newHarness()
    local counts = { base = 45, shards = 15, equipmentRevision = 0 }
    local vg = { ty = 0, stack = {}, calls = {}, paths = {}, path = {},
        scissor = false, stroke = {}, intersections = 0 }
    local effects = { forbidden = 0, binds = 0, gridBinds = 0, genericScores = 0, qualityMarks = 0, uiSounds = 0 }
    local function forbidden(name)
        effects.forbidden = effects.forbidden + 1
        error("isolation forbids " .. name, 2)
    end
    -- 无 __index=_G：任何未声明 API 都失败，不允许绕回引擎 require/玩家档/网络。
    local env = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, next = next,
        tonumber = tonumber, tostring = tostring, type = type, select = select, setmetatable = setmetatable,
        pcall = pcall, print = print, math = copy(math), string = copy(string), table = copy(table),
        coroutine = { create = coroutine.create, resume = coroutine.resume, status = coroutine.status,
            yield = coroutine.yield },
        time = { elapsedTime = 100 },
        NVG_ALIGN_RIGHT = 4, NVG_ALIGN_BOTTOM = 8, NVG_ALIGN_CENTER = 2,
        NVG_ALIGN_MIDDLE = 16, NVG_ALIGN_LEFT = 1, NVG_ALIGN_TOP = 32,
    }
    env._G = env
    env.File = function() forbidden("File") end
    local deniedObject = setmetatable({}, { __index = function(_, name)
        return function() forbidden("filesystem/cache." .. tostring(name)) end
    end })
    env.fileSystem, env.filesystem, env.cache = deniedObject, deniedObject, deniedObject
    env.GetFileSystem, env.GetCache = function() forbidden("GetFileSystem") end,
        function() forbidden("GetCache") end
    env.io, env.network = deniedObject, deniedObject
    env.os = setmetatable({ clock = os.clock }, { __index = function(_, name)
        return function() forbidden("os." .. tostring(name)) end
    end }) -- 预算调度仅可读 CPU 时钟；不开放文件/进程 API。
    env.dofile, env.loadfile = function() forbidden("dofile") end, function() forbidden("loadfile") end
    env.math.random, env.math.randomseed = function() forbidden("RNG") end, function() forbidden("RNG seed") end

    env.nvgSave = function() vg.stack[#vg.stack + 1] = { ty = vg.ty, scissor = vg.scissor } end
    env.nvgRestore = function()
        local saved = assert(table.remove(vg.stack), "unbalanced nvgRestore")
        vg.ty, vg.scissor = saved.ty, saved.scissor
    end
    env.nvgTranslate = function(_, x, y)
        assert(x == 0, "this recorder only models vertical translation")
        vg.ty = vg.ty + y
    end
    env.nvgScissor = function(_, x, y, w, h)
        vg.scissor = { x = x, y = y + vg.ty, w = w, h = h }
    end
    env.nvgIntersectScissor = function(_, x, y, w, h)
        vg.intersections = vg.intersections + 1
        vg.scissor = intersection(vg.scissor or nil, { x = x, y = y + vg.ty, w = w, h = h })
    end
    env.nvgBeginPath = function() vg.path = {} end
    env.nvgMoveTo = function(_, x, y) vg.path[#vg.path + 1] = { x = x, y = y + vg.ty } end
    env.nvgLineTo = env.nvgMoveTo
    env.nvgStrokeColor = function(_, color) vg.stroke = color end
    env.nvgStroke = function()
        vg.paths[#vg.paths + 1] = { points = vg.path, color = vg.stroke }
    end
    env.nvgRGBA = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    env.nvgLinearGradient = function() return {} end
    env.nvgTextBounds = function(_, _, _, text) return #text * 12 end
    for _, name in ipairs({ "nvgRoundedRect", "nvgRoundedRectVarying", "nvgRect", "nvgFillColor",
        "nvgFillPaint", "nvgStrokeWidth", "nvgFill", "nvgFontFace", "nvgFontSize", "nvgTextAlign",
        "nvgText", "nvgClosePath" }) do env[name] = noop end

    local inventory, itemDefs = {}, {}
    for i = 1, 60 do
        inventory[tostring(i)] = { templateId = "fixture", level = 85, quality = 1,
            seq = i, locked = false, baseStats = {} }
    end
    -- 一个零数量定义穿插在真源中，防止点击误用 ITEM_DEFS 原索引而非 buildItemList。
    itemDefs[1] = { key = "empty", quality = 1, getter = function() return 0 end }
    for i = 1, 45 do
        local index = i
        itemDefs[#itemDefs + 1] = { key = "item_" .. i, name = "fixture " .. i, quality = 1,
            getter = function() return index <= counts.base and index or 0 end }
    end
    local equipData = { inventory = inventory, equipped = {} }
    local itemDetail = { open = false, def = false }
    local equipmentDetail = { getOwner = function() return nil end, close = noop, dismissHover = noop,
        isOpen = function() return false end, drawIf = noop }
    local filterDialog = { isOpen = function() return false end, close = noop, draw = noop,
        countSelected = function() return 0 end }
    local drawUtil = { hitTest = hitTest, drawImageCentered = noop, drawShardIcon = noop }
    local modules = {
        ["core.DrawUtil"] = drawUtil,
        ["core.PlayerStore"] = {
            Get = function(key) return key == "equipment" and equipData or nil end,
            GetRevision = function(key) return key == "equipment" and counts.equipmentRevision or 0 end,
            Init = function() forbidden("PlayerStore.Init") end,
        },
        ["config.EquipmentConfig"] = { ITEMS = { fixture = { name = "fixture", quality = 1 } }, QUALITY = { 1 } },
        ["config.EquipmentSetConfig"] = { orderedSetIds = function() return {} end,
            getSetIdForTemplate = function() return nil end },
        ["ui.character.detail.EquipmentWearability"] = {
            createClassChecker = function() return function() return true end end,
            getFields = function(equip) return "accessory", "fixture", "onehand", equip.level end,
        },
        ["systems.EquipmentPower"] = {
            genericScore = function(equip)
                effects.genericScores = effects.genericScores + 1
                return equip.seq
            end,
            score = function() forbidden("synchronous equipment score") end,
        },
        ["systems.EquipmentSystem"] = { MAX_INVENTORY = 500, getAscendLevel = function() return 0 end },
        ["systems.AttributeDef"] = { META = {} },
        ["ui.hud.popup.SettingsPanel"] = { isEquipmentPowerEnabled = function() return false end },
        ["config.AdvancementConfig"] = { getDualWieldMode = function() return nil end },
        ["config.HeroConfig"] = {
            getAllIds = function() local ids = {}; for i = 1, 15 do ids[i] = i end; return ids end,
            get = function(id) return { name = "shard fixture " .. id, quality = 1 } end,
        },
        ["ui.character.panel.CharacterPanel"] = {
            getShards = function(id) return id <= counts.shards and id or 0 end,
        },
        ["ui.widget.ImageCache"] = { getEquipIcon = function() return 1 end },
        ["ui.widget.HeroFrame"] = {},
        ["ui.widget.EquipmentSetIcon"] = {
            hasBadge = function() return false end, drawBadge = noop,
            levelLayout = function(_, cx, cy, size)
                return { x = cx + size * .5 - 8, y = cy + size * .5 - 6, fontSize = 40, align = 12 }
            end,
            badgeLayout = function(cx, cy, size) return { x = cx - size * .5, y = cy, size = 44 } end,
        },
        ["systems.TutorialManager"] = { isActive = function() return false end },
        ["ui.character.equip.EquipmentDetail"] = equipmentDetail,
        ["ui.widget.SetFilterDialog"] = filterDialog,
        ["systems.GameSFX"] = { playUIMove = function() effects.uiSounds = effects.uiSounds + 1 end },
    }
    env.package = { loaded = modules, preload = {}, path = "", cpath = "" }
    env.require = function(name)
        if modules[name] ~= nil then return modules[name] end
        assert(name ~= "ui.backpack.BackpackPanel", "full Panel module must not run")
        local source = readSource(name) -- 名称必须在固定白名单，否则立即拒绝。
        local result = assert(load(source, "@isolated-grid/" .. name, "t", env))()
        modules[name] = assert(result, "module returned nil " .. name)
        return result
    end
    local realDarkIcon = env.require("core.DarkIcon")
    local darkIcon = {
        drawNine = realDarkIcon.drawNine, drawIconDark = noop,
        drawQualityBg = function(_, _, cx, cy, w, h)
            vg.calls[#vg.calls + 1] = { cx = cx, cy = cy, w = w, h = h,
                ty = vg.ty, scissor = vg.scissor and copy(vg.scissor) or nil }
        end,
    }
    -- 真 DarkIcon 仅用于面板金线；品质底记录器不影响真实 Grids 的布局/裁剪控制流。
    modules["core.DarkIcon"] = darkIcon
    env.DarkIcon, env.DrawUtil = darkIcon, drawUtil
    env.GameConfig = env.require("config.GameConfig")
    env.EquipmentConfig = modules["config.EquipmentConfig"]
    env.EquipmentSystem = modules["systems.EquipmentSystem"]
    env.PlayerStore = modules["core.PlayerStore"]
    local realGrids = env.require("ui.backpack.BackpackGrids")
    local bindGrids = realGrids.bind
    realGrids.bind = function(deps)
        effects.gridBinds = effects.gridBinds + 1
        return bindGrids(deps)
    end
    env.BackpackGridHost = env.require("ui.backpack.BackpackGridHost")
    local realLink = env.require("ui.backpack.BackpackEquipLink")
    local linkBinding = { deps = {}, api = {} }
    env.BackpackEquipLink = { bind = function(deps)
        -- 只注入叶子角色/左页查询，持有状态机、clickItem/cellAt 全部仍是生产实现。
        deps.getLeftPage = function() return { isOpen = function() return false end } end
        deps.getCharacterDetail = function() return nil end
        effects.binds = effects.binds + 1
        linkBinding.deps, linkBinding.api = deps, realLink.bind(deps)
        return linkBinding.api
    end }
    env.ITEM_DEFS, env.ITEM_DET_ANIM_DUR = itemDefs, .2
    env.SetFilterDialog, env.EquipmentDetail = filterDialog, equipmentDetail
    env.BF = { begin = function() return false end, finish = noop }
    env.QualityMark = { draw = function() effects.qualityMarks = effects.qualityMarks + 1 end }
    env.I18n = { lookup = function(text) return text end, format = string.format }
    modules["core.I18n"] = { t = function(key) return key end }
    env.TownPageChrome = {
        easeOutCubic = function(t) return t end, easeInCubic = function(t) return t end,
        drawNamePlate = noop, drawBack = noop, drawTabBar = noop,
        hitBack = function() return false end,
        tabSlide = function() return 1, 1, 1 end,
        hitTab = function(x, y, items, w, h)
            for i, item in ipairs(items) do if hitTest(x, y, item.cx, item.cy, w, h) then return i end end
            return nil
        end,
    }
    env.Curation = { cancelSource = noop, drawEntry = noop }
    env.BlacksmithDecompose = { cancelMarquee = noop, onOpen = noop, onTabSwitch = noop,
        isPopupOpen = function() return false end, drawUpperSlot = noop, drawPanel = noop,
        drawAutoDecomposePopup = noop }
    env.ensureDecomposeReady, env.drawItemDetail = noop, noop
    env.closeTransferConfirm, env.closeUrConvertDialog = noop, noop
    env.qualityChecked, env.setChecked = function() return true end, function() return true end
    env.getItemIcon, env.getInventoryCount = function() return 1 end, function() return 60 end
    env.imgCheckmark, env.imgLock, env.imgTopBg, env.imgTitleBg, env.imgTabBg = -1, -1, -1, -1, -1
    env.imgHeroIcons, env.SCROLL_WHEEL_STEP = {}, 60

    local panelSource = readSource("ui.backpack.BackpackPanel")
    -- 以下均为完整闭包或完整入口函数，保留生产词法作用域；不复制 applyLayout/scroll 公式。
    local chunk = table.concat({
        section(panelSource, "local Panel = {}", "-- 品质边框颜色"),
        section(panelSource, "local SCROLL_FRICTION", "-- ======================== 缓动函数"),
        section(panelSource, "local decomposeState = {", "--- 分解模式下某稀有度"),
        section(panelSource, "local itemDetState = {", "local ITEM_DET_ANIM_DUR"),
        section(panelSource, "local state = {", "-- 开关动画参数"),
        section(panelSource, "local ANIM_OPEN_DUR", "-- ======================== 辅助函数"),
        section(panelSource, "local gridHost = BackpackGridHost.bind({", "-- ======================== 道具详情弹窗"),
        section(panelSource, "local function openPage(mode, initialTab)", "filterBar = BackpackFilters.bindWarehouse"),
        section(panelSource, "function Panel.open(mode, initialTab)", "--- 是否打开"),
        section(panelSource, "function Panel.update(dt)", "--- 绘制"),
        section(panelSource, "local function drawBody(vg)", "function Panel.draw(vg)"),
        section(panelSource, "function Panel.handleInput(dx, dy)", "-- ======================== 拖拽/滚轮"),
        [[return { Panel = Panel, GRID = GRID, state = state, detail = itemDetState,
            columns = CELL_COL_CX, tabs = TAB_ITEMS, lower = LOWER_PANEL,
            calcScrollMax = gridHost.calcScrollMax, clampScroll = clampScroll,
            grids = function() return gridHost end, drawBody = drawBody, applyLayout = applyLayout,
            clip = function() return CLIP_TOP, CLIP_H end,
            host = function() return hostMode_ end }]],
    }, "\n")
    local h = assert(load(chunk, "@isolated-grid/Panel-complete-closures", "t", env))()
    h.env, h.vg, h.effects, h.counts, h.link = env, vg, effects, counts, linkBinding
    h.inventory, h.inventoryBefore = inventory, copy(inventory)
    h.reset = function()
        assert(#vg.stack == 0 and vg.ty == 0, "render transform leaked")
        vg.calls, vg.paths, vg.path = {}, {}, {}
        vg.scissor, vg.intersections = false, 0
    end
    h.render = function()
        h.reset()
        env.time.elapsedTime = h.state.openTime + 2 -- 所有面板动画完成，布局坐标不混入动画偏移。
        h.Panel.update(0) -- 生产唯一预算驱动；Render/点击不能偷走同步构建职责。
        local before = effects.genericScores
        h.drawBody(vg)
        eq(effects.genericScores, before, "draw never scores equipment")
        return vg.calls
    end
    return h
end

local EXPECTED = {
    inline = { item = 680.5, equip = 1030, bottom = 2020 },
    left = { item = 480, equip = 760, bottom = 1980 },
    window = { item = 480, equip = 760, bottom = 1980 },
}
local function open(h, mode, tab)
    local argument = mode == "left" and "left" or mode == "window" and true or false
    h.Panel.open(argument, tab)
    eq(h.host(), mode, "open host " .. mode)
    eq(h.state.tab, tab or "equip", "open initialTab " .. tostring(tab))
end
local function assertLayout(h, mode, tab, label)
    local expected = EXPECTED[mode]
    eq(h.GRID.FIRST_ROW_TOP, expected[tab], label .. " first row")
    eq(h.GRID.CLIP_BOTTOM, expected.bottom, label .. " fixed bottom")
    local top, height = h.clip()
    eq(top, h.GRID.FIRST_ROW_TOP, label .. " Panel CLIP_TOP synchronized")
    eq(top + height, expected.bottom, label .. " Panel CLIP_H synchronized")
end
local function itemClick(h, x, y, expected, label)
    h.detail.open, h.detail.def = false, nil
    local clicked = h.link.api.clickItem(x, y)
    eq(clicked, expected ~= nil, label .. " consumed")
    eq(h.detail.open, expected ~= nil, label .. " detail open")
    -- 碎片定义由真实 buildItemList 每次动态构造，比较稳定身份而非跨调用table地址。
    -- 普通道具则仍要求命中原定义引用，不能用相同名称的错误格子代替。
    if expected and expected.isShard then
        local actual = h.detail.def
        check(actual ~= nil and actual.isShard == true and actual.key == expected.key
            and actual.heroId == expected.heroId and actual.quality == expected.quality
            and actual.getter() == expected.getter(), label .. " exact production shard identity/count")
    else
        eq(h.detail.def, expected, label .. " exact production list entry")
    end
    h.detail.open, h.detail.def = false, nil
end
local function assertDraw(h, tab, scroll, label)
    local grid, state = h.GRID, h.state
    state.scrollY = scroll
    local calls = h.render()
    local window = { x = 0, y = grid.FIRST_ROW_TOP, w = 1080,
        h = grid.CLIP_BOTTOM - grid.FIRST_ROW_TOP }
    local list = tab == "item" and h.grids().buildItemList() or h.grids().getEquipList()
    local visible, clippedEmpty = 0, 0
    for index, call in ipairs(calls) do
        local rect = rectOf(call)
        local inWindow, effective = intersection(window, rect), intersection(call.scissor, rect)
        check(call.scissor ~= nil and call.scissor.y == window.y
            and call.scissor.h == window.h, label .. " live grid clip " .. index)
        if effective.w > 1 and effective.h > 1 then visible = visible + 1
        elseif inWindow.w > 1 and inWindow.h > 1 then clippedEmpty = clippedEmpty + 1 end
        if tab == "item" and inWindow.w > 1 and inWindow.h > 1 then
            -- 从实际绘图矩形的可见交集取点击点，而不是复制生产命中公式。
            itemClick(h, rect.x + rect.w * .5, inWindow.y + inWindow.h * .5,
                list[index], label .. " drawn/click identity " .. index)
        end
    end
    eq(clippedEmpty, 0, label .. " no visible cell clipped empty (original scroll regression)")
    check(visible >= 20, label .. " nonempty visible rows count=" .. visible)
    eq(#h.vg.stack, 0, label .. " balanced save/restore")
    eq(h.vg.ty, 0, label .. " transform restored")
    if tab == "item" then
        eq(#calls, #list, label .. " actual buildItemList owns drawing order including shards/zero-count filter")
        itemClick(h, h.columns[1], window.y - .25, nil, label .. " above clip rejected")
        itemClick(h, h.columns[1], grid.CLIP_BOTTOM + .25, nil, label .. " below clip rejected")
    end
    return calls
end
local function assertGoldGap(h, mode, label)
    h.state.scrollY = 0
    local calls = h.render()
    local goldY = {}
    -- 读取真实 DarkIcon.drawNine 的语义金线 Stroke，不重写 LOWER_PANEL 的布局公式作 oracle。
    for _, path in ipairs(h.vg.paths) do
        local points, color = path.points, path.color
        if #points == 2 and points[1].y == points[2].y and points[2].x - points[1].x > 700
            and color.r == 201 and color.g == 151 and color.b == 59 then
            goldY[#goldY + 1] = points[1].y
        end
    end
    eq(#goldY, 1, label .. " real panel has one semantic title gold line")
    if #goldY == 1 then
        eq(goldY[1], mode == "inline" and 650.5 or 450, label .. " gold line unchanged")
        eq(rectOf(assert(calls[1])).y - goldY[1], 30, label .. " first drawn row exactly 30 below actual gold line")
    end
    eq(h.effects.qualityMarks, 0, label .. " item does not draw equipment quality filter")
end
local function clickTab(h, tab, mode, label)
    h.detail.open, h.detail.def = false, nil
    h.state.scrollY, h.state.scrollMax, h.state.scrollVel = 431, 9999, 17
    local target = assert(({ equip = h.tabs[1], item = h.tabs[2], decompose = h.tabs[3] })[tab])
    check(h.Panel.handleInput(target.cx, target.cy), label .. " real Panel input consumes tab")
    eq(h.state.tab, tab, label .. " real Panel tab changes")
    eq(h.state.scrollY, 0, label .. " tab resets scroll")
    eq(h.state.scrollMax, 0, label .. " tab invalidates old maximum before next draw")
    eq(h.state.scrollVel, 0, label .. " tab cancels old velocity")
    if tab ~= "decompose" then assertLayout(h, mode, tab, label) end
end
local function assertTail(h, tab, label)
    h.state.scrollY = 100000
    local calls = h.render() -- 真实 GridHost.calcScrollMax + Grids draw + clamp，不在测试算最大值。
    eq(h.state.scrollY, h.state.scrollMax, label .. " over-scroll clamped to actual max")
    check(h.state.scrollMax > 0, label .. " long list really scrolls")
    local bottom, count = -math.huge, 0
    for _, call in ipairs(calls) do
        local rect = rectOf(call)
        bottom = math.max(bottom, rect.y + rect.h)
        if rect.y + rect.h == h.GRID.CLIP_BOTTOM then
            count = count + 1
            local clipped = intersection(call.scissor, rect)
            eq(clipped.h, rect.h, label .. " last row fully visible " .. count)
        end
    end
    eq(bottom, h.GRID.CLIP_BOTTOM, label .. " actual tail bottom aligns unchanged clip bottom")
    eq(count, 5, label .. " all five last-row cells visible")
    if tab == "item" then
        local list = h.grids().buildItemList()
        local last = assert(calls[#calls])
        itemClick(h, last.cx, last.cy + last.ty, list[#list], label .. " tail shard click")
    else
        local last = assert(calls[#calls])
        local equip = h.link.api.cellAt(last.cx, last.cy + last.ty)
        check(equip ~= nil, label .. " tail equipment click agrees with drawing")
    end
end

local function testModes()
    for _, mode in ipairs({ "inline", "left", "window" }) do
        local h = newHarness()
        -- 第一轮就从 item 打开：能捕获 LAYOUT_ORIG 被 item 顶部污染的回归。
        open(h, mode, "item")
        assertLayout(h, mode, "item", mode .. " initial item")
        assertGoldGap(h, mode, mode .. " gold gap")
        for _, scroll in ipairs({ 0, 600, 100000 }) do
            assertDraw(h, "item", scroll, mode .. " item scroll " .. scroll)
        end
        assertTail(h, "item", mode .. " item tail")
        h.state.scrollY = 0
        local first = h.render()[1]
        -- 完整 Panel.handleInput 到真实 clickItem，而非仅私有 API 单独命中。
        h.detail.open = false
        check(h.Panel.handleInput(first.cx, first.cy), mode .. " real Panel first-row input")
        eq(h.detail.def, h.grids().buildItemList()[1], mode .. " real Panel opens actual first item")
        h.detail.open, h.detail.def = false, nil
        itemClick(h, first.cx + first.w * .5 + 1, first.cy, nil, mode .. " horizontal gutter")
        itemClick(h, first.cx, first.cy + first.h * .5 + 1, nil, mode .. " vertical gutter")
        local boundGrids = h.grids()
        clickTab(h, "equip", mode, mode .. " item->equip")
        for _, scroll in ipairs({ 0, 600, 100000 }) do
            assertDraw(h, "equip", scroll, mode .. " equip original scroll regression " .. scroll)
        end
        assertTail(h, "equip", mode .. " unchanged equipment tail")
        check(h.effects.qualityMarks > 0, mode .. " equipment filters still drawn")
        clickTab(h, "item", mode, mode .. " equip->item")
        assertDraw(h, "item", 311, mode .. " item after reusing bound Grids")
        eq(h.grids(), boundGrids, mode .. " layout switching uses same bound GridHost instance")
        eq(h.effects.gridBinds, 1, mode .. " layout switching keeps lazy Grids binding once")
        -- default open 与反复宿主切换不得继承上次 item FIRST_ROW_TOP。
        open(h, mode, nil)
        assertLayout(h, mode, "equip", mode .. " default equipment open unchanged")
        open(h, "inline", "item")
        open(h, "left", "equip")
        assertLayout(h, "left", "equip", mode .. " cross-host equipment unchanged")
        open(h, "window", "item")
        assertLayout(h, "window", "item", mode .. " cross-host item")
        eq(h.effects.forbidden, 0, mode .. " no persistence/network/RNG access")
        check(same(h.inventory, h.inventoryBefore), mode .. " equipment inventory never mutated")
    end
end

local function testOwnershipRestore()
    for _, mode in ipairs({ "inline", "left", "window" }) do
        local h = newHarness()
        open(h, mode, "item")
        assertTail(h, "item", mode .. " before borrowed warehouse")
        local savedY = h.state.scrollY
        h.state.scrollMax = 99999 -- capture 故意过期；restore 必须重算而非相信快照。
        check(h.Panel.acquireForEquipment(7, nil), mode .. " real acquire equipment")
        eq(h.host(), "left", mode .. " acquire changes host to left")
        eq(h.state.tab, "equip", mode .. " automatic selectEquipTab")
        assertLayout(h, "left", "equip", mode .. " automatic equipment layout")
        eq(h.state.scrollY, 0, mode .. " automatic equipment resets item scroll")
        -- 两个 owner 重叠：非末尾 release 不能提前恢复 item/原宿主。
        check(h.Panel.acquireForBlacksmith(), mode .. " second real warehouse owner")
        h.Panel.releaseForEquipment()
        eq(h.state.tab, "equip", mode .. " first release keeps equipment")
        eq(h.host(), "left", mode .. " first release keeps left host")
        h.Panel.releaseWarehouse("blacksmith")
        eq(h.host(), mode, mode .. " final release restores manual host")
        eq(h.state.tab, "item", mode .. " final release restores manual item tab")
        assertLayout(h, mode, "item", mode .. " restored item layout")
        eq(h.state.scrollY, savedY, mode .. " saved item scroll retained")
        check(h.state.scrollMax ~= 99999, mode .. " restore recalculated stale maximum before draw")
        eq(h.state.scrollMax, h.calcScrollMax(#h.grids().buildItemList()), mode .. " restore uses current production item list")
        assertTail(h, "item", mode .. " restored item tail")

        -- 借用期间库存减少：释放当帧即重算并 clamp，不能等下一次 draw 才修正。
        h.state.scrollMax = 99999
        check(h.Panel.acquireForEquipment(7, nil), mode .. " acquire before item shrink")
        h.counts.base, h.counts.shards = 5, 0
        h.Panel.releaseForEquipment()
        assertLayout(h, mode, "item", mode .. " shrunk restore")
        eq(h.state.scrollMax, 0, mode .. " restore small current item list has zero max before draw")
        eq(h.state.scrollY, 0, mode .. " restore clamps stale saved item scroll before draw")
        h.counts.base, h.counts.shards = 45, 15
        -- 原快照 max=0，借用期间增至长列表，restore 同样必须重算。
        check(h.Panel.acquireForEquipment(7, nil), mode .. " acquire before item growth")
        h.Panel.releaseForEquipment()
        check(h.state.scrollMax > 0, mode .. " restored maximum grows from stale zero")
        eq(h.state.scrollY, 0, mode .. " growth does not invent scroll offset")
        assertDraw(h, "item", 600, mode .. " after growth restore")
        eq(h.effects.forbidden, 0, mode .. " ownership only touches isolated memory")
        check(same(h.inventory, h.inventoryBefore), mode .. " ownership never mutates equipment")
    end
end

local function testRealCallbacks()
    local h = newHarness()
    open(h, "inline", "item")
    h.link.deps.setLeftMode()
    eq(h.host(), "left", "actual Panel setLeftMode callback")
    assertLayout(h, "left", "item", "setLeftMode respects active item tab before automatic selection")
    h.link.deps.selectEquipTab()
    assertLayout(h, "left", "equip", "actual Panel selectEquipTab removes item layout")
    h.link.deps.restoreView({ mode = "inline", tab = "item", scrollY = 99999, scrollMax = 99999 })
    assertLayout(h, "inline", "item", "actual Panel restoreView callback")
    eq(h.state.scrollY, h.state.scrollMax, "restore clamps oversized item offset immediately")
    assertTail(h, "item", "callback-restored item tail")
    h.link.deps.restoreView({ mode = "window", tab = "equip", scrollY = 80, scrollMax = 80 })
    assertLayout(h, "window", "equip", "restore equipment layout unchanged")
    eq(h.state.scrollY, 80, "equipment restore preserves preexisting scroll offset")
    eq(h.state.scrollMax, 80, "equipment restore preserves preexisting scroll maximum")
    assertTail(h, "equip", "callback-restored equipment tail")
    -- 装备少于35件仍绘制35槽；不能套用 item 的实际件数规则吞掉已有80像素滚动。
    for i = 2, 60 do h.inventory[tostring(i)] = nil end
    h.counts.equipmentRevision = h.counts.equipmentRevision + 1
    h.link.deps.restoreView({ mode = "left", tab = "equip", scrollY = 80, scrollMax = 80 })
    eq(#h.grids().getEquipList(), 0, "changed equipment version rejects stale presented list before Update/Render")
    eq(h.state.scrollY, 80, "small equipment restore keeps old 80 offset before draw")
    eq(h.state.scrollMax, 80, "small equipment restore keeps old 80 maximum before draw")
    h.render()
    eq(#h.grids().getEquipList(), 1, "small equipment inventory presents one real item after Update/Render")
    eq(h.state.scrollY, 80, "equipment 35-slot rendering keeps original 80 offset")
    eq(h.state.scrollMax, 80, "equipment 35-slot maximum remains original 80")
    h.link.deps.restoreView({ mode = "inline", tab = "decompose", scrollY = 321, scrollMax = 765 })
    eq(h.state.scrollY, 321, "decompose restore preserves independent scroll offset")
    eq(h.state.scrollMax, 765, "decompose restore preserves independent max")
    clickTab(h, "item", "inline", "decompose->item selects fresh item layout")
    assertTail(h, "item", "item after decompose")
    eq(h.effects.binds, 1, "real EquipLink remains bound once across all layout callbacks")
    eq(h.effects.forbidden, 0, "callback tests no forbidden access")
end

function Start()
    print(PREFIX .. "start isolated real Panel/Grids/EquipLink layout regression")
    local ok, err = pcall(function()
        testModes()
        testOwnershipRestore()
        testRealCallbacks()
        eq(sourceReads, 8, "only eight fixed whitelisted Lua sources read")
        check(require == nativeRequire and package == nativePackage and File == nativeFile,
            "global require/package/File untouched")
    end)
    if not ok then check(false, "exception: " .. tostring(err)) end
    print(string.format("%s%s (%d passed, %d failures)", PREFIX,
        #failures == 0 and "ALL PASS" or "FAILED", passes, #failures))
    engine:Exit()
end
