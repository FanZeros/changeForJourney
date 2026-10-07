-- 本轮 UI 反馈回归：真实加载完整模块，仅数据、资源与底层绘图边界使用替身。
-- 复用现有 cache:GetFile + load 隔离环境和 NanoVG 仿射探针模式；不访问玩家存档。
-- 这里只证明调用顺序、命中与宽度预算，不证明引擎 GPU、字体或实机触控效果。
local TAG = "[ui_feedback_regression_test]"
local assertions, cases, failures = 0, 0, 0

local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
end

local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

local function near(actual, expected, label)
    check(type(actual) == "number" and math.abs(actual - expected) < 0.00001,
        label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

local function source(path)
    local file = assert(cache:GetFile(path), "真实脚本缺失 " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function noop() end

-- 绘图替身只模拟本轮实际使用的平移、缩放、字号与对齐；不能当作截图验收。
---@return any
local function fixture()
    local f = { calls = {}, modules = {}, loaded = {}, clock = { elapsedTime = 100 },
        matrix = { tx = 0, ty = 0, sx = 1, sy = 1, font = 26, align = 0 },
        stack = {}, imagePaths = {}, nextImage = 0 }
    local env = setmetatable({ time = f.clock, H_SEAM_BACK = true,
        H_focusPanel = false, H_TRI_ROW = false }, { __index = _G })
    f.env = env
    function f.record(name, values)
        local call = values or {}
        call.name = name
        f.calls[#f.calls + 1] = call
        return call
    end
    function f.screen(x, y)
        return f.matrix.tx + x * f.matrix.sx, f.matrix.ty + y * f.matrix.sy
    end
    function f.clear()
        eq(#f.stack, 0, "上轮探针矩阵已恢复")
        f.calls = {}
        f.matrix = { tx = 0, ty = 0, sx = 1, sy = 1, font = 26, align = 0 }
    end
    function f.all(name)
        local out = {}
        for _, call in ipairs(f.calls) do
            if call.name == name then out[#out + 1] = call end
        end
        return out
    end
    function f.at(name)
        for i, call in ipairs(f.calls) do if call.name == name then return i end end
        return 0
    end
    function f.width(text, size)
        return (utf8.len(tostring(text)) or 0) * size * 0.6
    end
    function f.load(name)
        if f.modules[name] ~= nil then return f.modules[name] end
        if f.loaded[name] ~= nil then return f.loaded[name] end
        local path = name:gsub("%.", "/") .. ".lua"
        local module = assert(load(source(path), "@" .. path, "t", env))()
        f.loaded[name] = module
        return module
    end
    env.require = f.load
    -- 所有绘图接口必须显式隔离，禁止把假 vg 交给原生 GPU 接口。
    for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFillColor",
        "nvgStrokeColor", "nvgStrokeWidth", "nvgFill", "nvgStroke", "nvgCircle",
        "nvgMoveTo", "nvgLineTo", "nvgClosePath", "nvgFontFace", "nvgFontBlur",
        "nvgTextLetterSpacing", "nvgGlobalAlpha", "nvgSkewX", "nvgFillPaint",
        "nvgScissor", "nvgIntersectScissor", "nvgResetScissor" }) do env[name] = noop end
    env.nvgRGBA = function(r, g, b, a) return { r, g, b, a } end
    for _, name in ipairs({ "nvgLinearGradient", "nvgRadialGradient", "nvgBoxGradient",
        "nvgImagePattern" }) do env[name] = function() return {} end end
    env.nvgSave = function()
        local copy = {}
        for key, value in pairs(f.matrix) do copy[key] = value end
        f.stack[#f.stack + 1] = copy
    end
    env.nvgRestore = function()
        f.matrix = assert(table.remove(f.stack), "NanoVG save/restore 不配对")
    end
    env.nvgTranslate = function(_, x, y)
        f.matrix.tx, f.matrix.ty = f.matrix.tx + x * f.matrix.sx, f.matrix.ty + y * f.matrix.sy
    end
    env.nvgScale = function(_, x, y)
        f.matrix.sx, f.matrix.sy = f.matrix.sx * x, f.matrix.sy * y
    end
    env.nvgFontSize = function(_, size) f.matrix.font = size end
    env.nvgTextAlign = function(_, align) f.matrix.align = align end
    env.nvgTextBounds = function(_, _, _, text) return f.width(text, f.matrix.font) end
    env.nvgText = function(_, x, y, text)
        local sx, sy = f.screen(x, y)
        f.record("text", { x = sx, y = sy, text = tostring(text), font = f.matrix.font,
            align = f.matrix.align, width = f.width(text, f.matrix.font) * f.matrix.sx })
    end
    env.nvgCreateImage = function(_, path)
        f.nextImage = f.nextImage + 1
        f.imagePaths[f.nextImage] = path
        f.record("image.load", { path = path, handle = f.nextImage })
        return f.nextImage
    end
    local function drawImage(_, handle, x, y, w, h)
        f.record("image.draw", { path = f.imagePaths[handle], handle = handle, x = x, y = y, w = w, h = h })
    end
    local draw = { drawImageCentered = drawImage, drawImageCover = drawImage, drawCardImage = noop,
        drawNineSlice = noop, drawShardIcon = noop, drawBackChevron = noop, seamSlideX = function() return 0 end }
    -- 命中函数也加载生产实现，避免测试自行写出另一套边界规则。
    draw.hitTest = f.load("core.DrawUtil").hitTest
    draw.drawTextStroke = function(vg, x, y, text, size, align)
        env.nvgFontSize(vg, size)
        env.nvgTextAlign(vg, align)
        env.nvgText(vg, x, y, text)
        if text == "测试顶层提示" then f.record("float") end
    end
    f.modules["core.DrawUtil"] = draw
    local dark = { drawNine = function(_, kind, x, y, w, h)
            local sx, sy = f.screen(x, y)
            f.record("nine", { kind = kind, x = sx, y = sy, w = w, h = h })
        end,
        drawQualityBg = noop, drawIconDark = drawImage,
        draw = function(_, kind, x, y, size, alpha)
            local sx, sy = f.screen(x, y)
            f.record("icon", { kind = kind, x = sx, y = sy, size = size, alpha = alpha })
        end,
        QUALITY_TRIM = { { 255, 255, 255 }, { 0, 200, 0 }, { 0, 100, 255 },
            { 180, 0, 200 }, { 255, 200, 0 }, { 255, 0, 0 } } }
    f.modules["core.DarkIcon"] = dark
    f.modules["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 } }
    f.modules["systems.ButtonFeedback"] = { begin = function(_, id, x, y, w, h)
        local sx, sy = f.screen(x, y)
        f.record("button.draw", { id = id, x = sx, y = sy, w = w, h = h })
        return false
    end, finish = noop, trigger = function(id) f.record("button.trigger", { id = id }) end }
    f.modules["core.NumberUtil"] = { format = tostring }
    f.modules["core.I18n"] = { t = function(key) return key end, lookup = function(key) return key end,
        format = string.format, get = function() return "zh_CN" end }
    f.modules["ui.widget.KeywordText"] = { new = function() return { clear = noop, drawPopup = noop } end }
    f.modules["ui.widget.ImageCache"] = { init = noop, getEquipIcon = function() return 999 end,
        getQualityBg = function() return -1 end }
    f.modules["ui.widget.HeroFrame"] = { draw = noop }
    f.modules["config.HeroAssetUtil"] = { preloadIcons = noop, ensureCard = function() return -1 end }
    f.modules["systems.TutorialManager"] = { isActive = function() return false end }
    f.modules["systems.GameSFX"] = { play = noop, playUIMove = noop }
    f.data = {}
    f.modules["core.PlayerStore"] = { Get = function(key) return f.data[key] end,
        GetField = function(key, field) return f.data[key] and f.data[key][field] end, Subscribe = noop }
    f.modules["runtime.ClientDispatcher"] = { get = function(key) return f.data[key] end }
    f.modules["ui.character.panel.CharacterPanel"] = { getOwnedHero = function() return { level = 60 } end,
        getEffectiveLevel = function() return 60 end, getShards = function() return 0 end }
    f.modules["config.HeroConfig"] = { get = function() return { classId = "seal", name = "测试角色" } end,
        getAllIds = function() return {} end }
    f.modules["core.GameState"] = setmetatable({ getTavernCoin = function() return 7 end },
        { __index = function() return function() return 0 end end })
    return f
end

local function resetButtonCase()
    local f = fixture()
    f.modules["systems.EquipmentPower"] = {}
    local actions = {}
    f.modules["runtime.GameAction"] = { sendAction = function(action, params)
        actions[#actions + 1] = { action = action, params = params }
    end }
    local protocol = f.load("shared.Protocol")
    local page = f.load("ui.church.ChurchClassChange")
    page.init({})
    page.setHero(1)
    f.clear()
    page.drawContent({})
    local reset = {}
    for _, call in ipairs(f.all("button.draw")) do if call.id == "ccc_reset" then reset[#reset + 1] = call end end
    eq(#reset, 1, "真实 drawContent 只画一个重置按钮")
    local rect = reset[1]
    near(rect.x, 540, "实际重置中心 X")
    near(rect.y, 1940, "树平移 -300 后实际重置中心 Y")
    near(rect.w, 410, "保留原重置宽度")
    near(rect.h, 100, "保留原重置高度")
    eq(#f.stack, 0, "完整转职树恢复矩阵")
    -- 点在屏幕/详情页设计空间；没有先替生产 handler 加回 300 的偷换。
    local inside = { { rect.x, rect.y }, { rect.x - rect.w * .5, rect.y },
        { rect.x + rect.w * .5, rect.y }, { rect.x, rect.y - rect.h * .5 },
        { rect.x, rect.y + rect.h * .5 }, { rect.x - rect.w * .5, rect.y - rect.h * .5 },
        { rect.x + rect.w * .5, rect.y + rect.h * .5 } }
    for i, point in ipairs(inside) do
        local before = #f.all("button.trigger")
        eq(page.handleResetButton(point[1], point[2]), true, "中心/边缘触发 " .. i)
        eq(#f.all("button.trigger"), before + 1, "命中只触发一次反馈 " .. i)
        eq(#actions, i, "命中首次直接发送一次重置动作 " .. i)
        eq(actions[i].action, protocol.ACTION_TYPES.RESET_CLASS, "使用原重置协议")
        eq(actions[i].params.heroId, 1, "保留当前英雄重置目标")
    end
    local outside = { { 540, 2240 }, { rect.x - rect.w * .5 - 1, rect.y },
        { rect.x + rect.w * .5 + 1, rect.y }, { rect.x, rect.y - rect.h * .5 - 1 },
        { rect.x, rect.y + rect.h * .5 + 1 }, { 0, 0 }, { 1080, 2400 } }
    for i, point in ipairs(outside) do
        local before = #f.all("button.trigger")
        eq(page.handleResetButton(point[1], point[2]), false, "旧中心/按钮外不触发 " .. i)
        eq(#f.all("button.trigger"), before, "按钮外不产生反馈 " .. i)
        eq(#actions, #inside, "按钮外不发送重置动作 " .. i)
    end
end

---@return any, any, any
local function artifactFixture()
    local f = fixture()
    local detail = { visible = false, selection = false, cover = false, consume = false }
    local api = { init = noop, setEquipActionStateGetter = noop, setOnEquip = noop, setOnRefine = noop,
        hide = function() detail.visible = false end,
        closeImmediate = function() detail.visible = false end, dismissHover = noop,
        isVisible = function() return detail.visible end, isPinned = function() return detail.visible end,
        getSelection = function() return detail.selection end,
        containsPoint = function() return detail.visible and detail.cover end,
        handleTap = function(x, y)
            f.record("detail.tap", { x = x, y = y })
            return detail.consume
        end,
        show = function(artifact, location, slot, subSlot, team)
            detail.visible = true
            detail.selection = { artifactId = tostring(artifact.id), location = location,
                slot = slot, subSlot = subSlot, teamIdx = team }
            f.record("detail.show", { id = tostring(artifact.id), location = location })
        end,
        draw = function() f.record("detail.draw") end }
    f.modules["ui.character.hero.ArtifactDetailPanel"] = api
    f.modules["config.ArtifactAssetUtil"] = { preloadIcons = noop, drawIcon = function(_, item, x, y, size)
        if item then f.record("artifact.icon", { id = tostring(item.id), x = x, y = y, size = size }) end
    end }
    f.modules["config.ExpTable"] = { getUnlockedTeamCount = function() return 3 end,
        getTeamUnlockText = function() return "已解锁" end }
    f.data.player = { level = 60 }
    f.data.artifacts = { bag = { { id = "101", artifactId = 1, quality = 2, valueRatio = 4321 },
        { id = "102", artifactId = 2, quality = 2, valueRatio = 4322 } }, equipped = {}, equippedByTeam = {} }
    local panel = f.load("ui.church.ChurchArtifactPanel")
    panel.init({})
    f.clear()
    return f, panel, detail
end

local function artifactLayerCase()
    local f, panel = artifactFixture()
    check(type(panel.drawOverlay) == "function", "神器详情有独立 overlay 公共入口")
    panel.drawContent({})
    eq(#f.all("detail.draw"), 0, "真实神器 drawContent 不再绘制详情")
    panel.drawOverlay({})
    eq(#f.all("detail.draw"), 1, "真实神器 drawOverlay 恰好委托一次详情")
    f.modules["ui.church.ChurchArtifactDrawPanel"] = { drawBg = function() f.record("chest.bg") end,
        drawContent = function() f.record("chest.content") end,
        drawKeyConfirmDialog = function() f.record("key.confirm") end }
    f.modules["ui.fx.SpineCardEffect"] = { draw = function() f.record("card.fx") end }
    -- 内容仍执行真实 Panel；记录边界不替换其 drawOverlay 或 drawContent 方法。
    local realPanel = { drawBg = function(vg) f.record("artifact.bg"); panel.drawBg(vg) end,
        drawContent = function(vg) f.record("artifact.content"); panel.drawContent(vg) end,
        drawOverlay = panel.drawOverlay, canUpgradeAnyArtifact = function() return false end }
    f.modules["ui.church.ChurchArtifactPanel"] = realPanel
    local state = { open = true, closing = false, openTime = 0, tab = "shenqi", tabFrom = "shenqi",
        tabSwitchTime = 0, rosterScrollVelocity = 0, rosterDragging = false, slotLiftProgress = 0,
        floatText = "测试顶层提示", floatTextTime = 100, floatTextX = 540, floatTextY = 100 }
    local draw = f.load("ui.church.ChurchDraw").bind({ state = state, DESIGN_W = 1080, DESIGN_H = 2400,
        ANIM = { OPEN_DUR = .45, CLOSE_DUR = .38, UPPER_SLIDE_OUT = 1200, UPPER_SLIDE_IN = 1200,
            LOWER_SLIDE_DIST = 1600, SLOT_LIFT = 300, SELECT_DUR = .25 },
        CHURCH = {}, CHAR_SLOT = { CX = 540, CY = 600 }, ROSTER = {},
        TAB = { ANIM_DUR = .35 }, TAB_MAP = { shenqi = 1, baoxiang = 2 }, TAB_KEYS = { "shenqi", "baoxiang" },
        TAB_ITEMS = {}, img = { iconUp = -1 }, powerCache = {}, HC = f.modules["config.HeroConfig"],
        DarkIcon = f.modules["core.DarkIcon"], DrawUtil = f.modules["core.DrawUtil"],
        GameState = f.modules["core.GameState"], NumberUtil = f.modules["core.NumberUtil"],
        drawImageCentered = f.modules["core.DrawUtil"].drawImageCentered,
        drawTextStroke = f.modules["core.DrawUtil"].drawTextStroke, getHeroCardImage = function() return -1 end,
        easeInCubic = function(t) return t end, easeOutCubic = function(t) return t end,
        easeInOutCubic = function(t) return t end,
        updateSlotAnim = noop, updateSelectAnim = noop, updateRosterSlide = noop,
        TownPageChrome = { drawBack = function() f.record("back") end,
            drawTabBar = function() f.record("tab") end, drawNamePlate = function() f.record("name") end } })
    f.clear()
    draw.drawPageImpl({})
    eq(#f.all("detail.draw"), 1, "教堂稳定神器页只画一次详情")
    for _, name in ipairs({ "artifact.content", "back", "tab", "name" }) do
        check(f.at(name) > 0 and f.at(name) < f.at("detail.draw"), name .. " 位于神器详情下层")
    end
    check(f.at("detail.draw") < f.at("key.confirm") and f.at("key.confirm") < f.at("card.fx")
        and f.at("card.fx") < f.at("float"), "高优先级确认/特效/提示仍在详情上层")
    eq(#f.stack, 0, "教堂详情绘制后矩阵恢复")
    -- 页签切换中只画双方内容，不让旧神器浮层盖住新宝箱页。
    state.tab, state.tabFrom, state.tabSwitchTime = "baoxiang", "shenqi", f.clock.elapsedTime - .175
    f.clear()
    draw.drawPageImpl({})
    eq(#f.all("detail.draw"), 0, "页签切换动画不绘制神器详情")
    eq(#f.all("artifact.content"), 1, "动画旧神器内容保留")
    eq(#f.all("chest.content"), 1, "动画新宝箱内容保留")
    state.tabFrom, state.tabSwitchTime = "baoxiang", 0
    f.clear()
    draw.drawPageImpl({})
    eq(#f.all("detail.draw"), 0, "稳定宝箱页不绘制神器详情")
end

local function artifactInputCase()
    local f, panel, detail = artifactFixture()
    panel.drawContent({})
    local icons = f.all("artifact.icon")
    eq(#icons, 2, "真实神器网格绘制两个未装备实例")
    local first, second = icons[1], icons[2]
    detail.consume = true
    eq(panel.handleTabInput(310, 2150), true, "详情优先拦截底部置换按钮")
    eq(#f.all("button.trigger"), 0, "详情消费后不触发底部按钮")
    detail.consume = false
    eq(panel.handleTabInput(first.x, first.y), true, "神器原网格点击保留")
    eq(detail.selection.artifactId, first.id, "原格点击打开相同神器详情")
    detail.cover = true
    eq(panel.handleDragBegin(second.x, second.y), false, "浮层下的其它神器格不穿透拖动")
    eq(panel.hasPointer(), false, "被挡格不创建手势")
    eq(panel.handleDragBegin(first.x, first.y), true, "被夹紧浮层盖住的原神器格仍可拖动")
    eq(panel.hasPointer(), true, "原神器格建立 pointer")
    eq(panel.handleDragMove(first.x + 20, first.y), true, "原神器格达到拖动阈值")
    eq(panel.isItemDragging(), true, "原格进入真实物品拖动")
    panel.cancelPointer()
    -- 同实例但不同装配位置不能冒充原来源格；与生产 selection 的维度一致。
    detail.visible, detail.cover = true, true
    detail.selection = { artifactId = first.id, location = "slot", teamIdx = 1, slot = 1, subSlot = 1 }
    eq(panel.handleDragBegin(first.x, first.y), false, "同 ID 不同 location 不享受原格例外")
    eq(panel.hasPointer(), false, "错误来源不留下 pointer")
end

---@return any
local function equipmentFixture()
    local f = fixture()
    local item = { templateId = "TEST", quality = 2, level = 8, slot = "weapon", type = "单手剑",
        grip = "onehand", name = "测试装备", enhanceLevel = 0 }
    f.data.equipment = { inventory = { ["1"] = item }, equipped = {} }
    f.data.heroes = { roster = { [1] = { level = 60 } } }
    f.modules["config.EquipmentConfig"] = { ITEMS = { TEST = item }, QUALITY = { {}, {}, {}, {}, {}, {} } }
    f.modules["config.EquipmentSetConfig"] = { orderedSetIds = function() return {} end,
        getSetIdForTemplate = function() return nil end }
    f.modules["ui.character.detail.EquipmentWearability"] = { getFields = function(equip)
        return equip.slot, equip.type, equip.grip, equip.level
    end }
    f.modules["systems.EquipmentPower"] = { score = function(equip, heroId, slot)
        f.record("power.score", { item = equip, heroId = heroId, slot = slot })
        return f.power
    end, getContext = function() return {} end,
        evaluate = function() return { valid = true, gain = 0 } end }
    f.modules["systems.EquipmentSystem"] = { MAX_INVENTORY = 300,
        getHeroSlots = function() return f.heroSlots or {} end,
        getAscendLevel = function() return 0 end }
    f.modules["ui.character.equip.EquipmentDetail"] = { getOwner = function() return false end,
        isOpen = function() return false end, close = noop, drawIf = noop, init = noop }
    f.modules["ui.battle.tri.BattleTriPage"] = { isOpen = function() return false end }
    f.modules["ui.church.ChurchPage"] = { hasAdvanceForHero = function() return false end }
    f.showEquipmentPower = false
    f.modules["ui.hud.popup.SettingsPanel"] = {
        isEquipmentPowerEnabled = function() return f.showEquipmentPower == true end,
        isSetIconsEnabled = function() return true end,
    }
    -- 角标布局使用真实共享模块，未把正文宽度预算挪到测试实现里。
    f.modules["ui.widget.EquipmentSetIcon"] = nil
    f.item = item
    return f
end

local function assertPowerLayout(f, label, cellSize)
    local powerIcons, powerTexts = {}, {}
    for _, call in ipairs(f.all("icon")) do if call.kind == "power" then powerIcons[#powerIcons + 1] = call end end
    for _, call in ipairs(f.all("text")) do
        check(not call.text:find("战力 ", 1, true), label .. " 不带战力文字前缀")
        if call.text == tostring(f.power) then powerTexts[#powerTexts + 1] = call end
    end
    eq(#powerIcons, 1, label .. " 单格只画一个 power 图标")
    eq(#powerTexts, 1, label .. " 完整保留原贡献数值")
    local icon, text = powerIcons[1], powerTexts[1]
    near(icon.size, 22, label .. " 图标占位 22px")
    eq(text.align, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM, label .. " 数值保留右下对齐")
    local textLeft, iconLeft = text.x - text.width, icon.x - icon.size * .5
    near(textLeft - (icon.x + icon.size * .5), 4, label .. " 图标数值间隔 4px")
    check(text.x - iconLeft <= cellSize * .62 + .00001, label .. " 总预算含图标与间隔")
    near(text.y - (icon.y + icon.size * .5), 0, label .. " 数值与图标下沿对齐")
    if #tostring(f.power) > 10 then
        check(text.font < 26, label .. " 长数字确实缩字号")
        near(text.width, cellSize * .62 - 22 - 4, label .. " 长数字扣除图标与间隔后拟合")
    else
        near(text.font, 26, label .. " 短数字不无谓缩小")
    end
end

local function equipmentCase()
    local f = equipmentFixture()
    local state = { scrollY = 0, closing = false }
    local grids = f.load("ui.backpack.BackpackGrids").bind({
        GRID = { COLS = 5, CELL_SIZE = 160, GAP = 30, CELL_RADIUS = 24, FIRST_ROW_TOP = 627, CLIP_BOTTOM = 1780 },
        CELL_COL_CX = { 160, 350, 540, 730, 920 }, DESIGN_W = 1080,
        state = state, decomposeState = {}, ITEM_DEFS = {},
        calcScrollMax = function() return 0 end, clampScroll = noop, isLeftMode = function() return false end,
        getEquipmentSlotFilter = function() return nil, nil end,
        getImgLock = function() return -1 end, getImgHeroIcons = function() return {} end })
    local bag = f.load("ui.character.equip.EquipmentBag")
    bag.open(nil, "全部装备", nil)
    f.clock.elapsedTime = 101
    -- 详情页只隔离不相关的下部属性布局；完整 draw 仍走真实装备槽循环。
    f.modules["ui.character.detail.CharacterDetailAttrs"] = {}
    f.modules["ui.character.detail.CharacterEquipStats"] = { LEGACY = {}, drawBackground = noop }
    f.modules["ui.character.detail.CharacterAttributeView"] = {
        ATTRIBUTE_STYLE = { boxW = 440, rowH = 60, boxCX = 310, rowStep = 77 },
        ATTRIBUTE_LAYOUT = { firstY = 1200, y = 1200, h = 500 } }
    f.modules["ui.character.hero.AwakeningPanel"] = {}
    f.modules["systems.ExtraTalentSystem"] = {}
    f.modules["ui.character.equip.EquipmentBag"] = { draw = noop, isOpen = function() return false end }
    local detail = f.load("ui.character.detail.CharacterDetailDraw")
    local ds = { open = true, closing = false, heroId = 1, openTime = 0, tab = "equip", tabFrom = "equip",
        tabSwitchTime = 0, attrDragging = false, attrScrollVel = 0, attrScrollY = 0 }
    detail.setContext({ detailState = ds, getOwnedData = function() return { level = 60, exp = 0, maxExp = 5 } end,
        CharacterDetail = { _imgIconUp = -1, _getEquipIcon = function() return 999 end,
            _hasUpgradeForSlot = function() return false end },
        imgHeroCards = {}, imgHeroIcons = {}, imgClassIcons = {},
        calcHeroPower = function() return 0 end, collectAttributes = noop, clampAttrScroll = noop })
    -- 显示关闭只屏蔽数字与图标，不能改变等级位置、评分结果或候选顺序。
    f.power = 1234
    local function assertHidden(label)
        for _, call in ipairs(f.all("icon")) do check(call.kind ~= "power", label .. " 隐藏战力图标") end
        for _, call in ipairs(f.all("text")) do check(call.text ~= "1234", label .. " 隐藏战力数字") end
    end
    local function levelSnapshot()
        local levels = {}
        for _, call in ipairs(f.all("text")) do
            if call.text == "Lv.8" then levels[#levels + 1] = table.concat({ call.x, call.y, call.font, call.align }, "|") end
        end
        check(#levels > 0, "关闭战力显示仍绘制等级")
        return table.concat(levels, ";")
    end
    local function checkPreference(draw, label)
        f.showEquipmentPower = false
        f.clear()
        draw()
        assertHidden(label)
        local offLevel = levelSnapshot()
        f.showEquipmentPower = true
        f.clear()
        draw()
        assertPowerLayout(f, label, 160)
        eq(levelSnapshot(), offLevel, label .. " 开关不改变等级位置、字号或对齐")
        f.showEquipmentPower = false
    end
    local listOff = grids.getEquipList()
    checkPreference(function() grids.drawEquipGrid({}) end, "BackpackGrids 偏好")
    f.showEquipmentPower = true
    local listOn = grids.getEquipList()
    eq(#listOn, #listOff, "开关不改变仓库候选数量")
    for i, entry in ipairs(listOff) do
        eq(listOn[i].seq, entry.seq, "开关不改变装备排序")
        eq(listOn[i].power, entry.power, "开关不改变评分结果")
    end
    checkPreference(function() bag.draw({}) end, "EquipmentBag 偏好")
    f.heroSlots = { weapon = 1 }
    checkPreference(function() detail.draw({}) end, "CharacterDetailDraw 偏好")
    f.heroSlots = nil
    f.showEquipmentPower = true
    for _, power in ipairs({ 0, 1234, 123456789012345678 }) do
        f.power = power
        f.clear()
        grids.drawEquipGrid({})
        assertPowerLayout(f, "BackpackGrids " .. tostring(power), 160)
        f.clear()
        bag.draw({})
        assertPowerLayout(f, "EquipmentBag " .. tostring(power), 160)
        f.heroSlots = { weapon = 1 }
        f.clear()
        detail.draw({})
        assertPowerLayout(f, "CharacterDetailDraw " .. tostring(power), 160)
        local score = f.all("power.score")
        eq(#score, 1, "详情评分只计算已装备格")
        eq(score[1].item, f.item, "详情未替换原装备对象")
        eq(score[1].heroId, 1, "详情保留原角色评分上下文")
        eq(score[1].slot, "weapon", "详情保留原槽评分上下文")
        f.heroSlots = nil
    end
    -- EquipmentBag 横屏复用同一数字行，但格子缩为 150px，预算也必须随格子收缩。
    f.power = 123456789012345678
    bag.setOverlayRegion(0, 0, 2000, 1020)
    f.clear()
    bag.draw({}, { skipOverlay = true })
    assertPowerLayout(f, "EquipmentBag 横屏", 150)
end

local function coinCase()
    local f = equipmentFixture()
    local canonical = "image/货币道具/UI_icon_JGB_X.png"
    local defs = f.load("config.ResourceDefs")
    eq(defs.DEFS.tavern_coin.iconPath, canonical, "ResourceDefs 指向现有酒馆币图")
    eq(defs.ID_TO_TYPE["11"], "tavern_coin", "奖励酒馆币 ID 兼容")
    eq(defs.DEFS.tavern_coin.quality, 3, "酒馆币品质不变")
    eq(defs.DEFS.tavern_coin.name, "酒馆币", "酒馆币名称不变")
    local asset = cache:GetFile(canonical)
    check(asset ~= nil, "官方资源查找能读取现有酒馆币 PNG（非 GPU 解码证明）")
    if asset then asset:Dispose() end
    -- 奖励公共 API 走真实 ResourceDefs -> getResourceIcon -> draw 路径。
    f.modules["ui.widget.RewardCascade"] = { easeOutBack = function(t) return t end,
        new = function() return { start = noop } end }
    f.modules["ui.widget.BattleRewardQueue"] = { new = function() return {} end }
    f.modules["ui.widget.ResultRepeatFooter"] = { EXTRA_HEIGHT = 0 }
    local rewards = f.load("ui.hud.popup.RewardPopup")
    rewards.init({})
    rewards.show("酒馆币回归", { { type = "tavern_coin", amount = 7 } }, { cascade = false })
    f.clock.elapsedTime = 102
    f.clear()
    rewards.drawContent({})
    local function hasDraw(path)
        for _, call in ipairs(f.all("image.draw")) do if call.path == path then return true end end
        return false
    end
    check(hasDraw(canonical), "奖励通过中央定义实际绘制酒馆币路径")
    -- 保留真实背包宿主与网格；只隔离装备链接/分解等本轮无关子系统。
    f.modules["ui.backpack.BackpackDialogs"] = { bind = function() return { closeTransferConfirm = noop } end }
    f.modules["ui.backpack.BackpackEquipLink"] = { bind = function() return {
        getEquipmentSlotFilter = function() return nil, nil end,
        onManualOpen = noop, drawFilterHint = noop } end }
    f.modules["ui.widget.QualityMark"] = { init = noop }
    f.modules["ui.widget.SetFilterDialog"] = { close = noop, draw = noop }
    f.modules["ui.blacksmith.BlacksmithDecompose"] = { cancelMarquee = noop, setContext = noop,
        init = noop, applyProfile = noop }
    f.modules["config.BlacksmithConfig"] = {}
    f.modules["config.UrGachaConfig"] = {}
    f.modules["ui.town.TownPageChrome"] = { easeOutCubic = function(t) return t end,
        easeInCubic = function(t) return t end, drawNamePlate = noop, drawBack = noop, drawTabBar = noop,
        tabSlide = function() return 2, 2, 1 end }
    local backpack = f.load("ui.backpack.BackpackPanel")
    backpack.init({})
    backpack.open(false, "item")
    f.clock.elapsedTime = 103
    f.clear()
    backpack.draw({})
    check(hasDraw(canonical), "背包真实 ITEM_DEFS/缓存/道具网格绘制现有酒馆币路径")
    eq(#f.stack, 0, "背包道具绘制恢复矩阵")
    -- 商店初始化和公共绘制保持真实，商品购买事务不会执行。
    local shop = f.load("ui.tavern.TavernShopPage")
    shop.init({})
    f.clear()
    shop.drawContent({})
    check(hasDraw(canonical), "商店资源栏及商品消耗图复用相同酒馆币路径")
    eq(#f.stack, 0, "商店绘制恢复矩阵")
end

function Start()
    for _, case in ipairs({ { "重置按钮原屏幕逆变换", resetButtonCase },
        { "神器内容/浮层调用顺序", artifactLayerCase }, { "神器点击/原格拖动例外", artifactInputCase },
        { "三处装备贡献图标与长数字预算", equipmentCase }, { "酒馆币真实资源及三处绘制路径", coinCase } }) do
        cases = cases + 1
        local ok, err = pcall(case[2])
        if ok then print(TAG .. " PASS " .. case[1])
        else
            failures = failures + 1
            print(TAG .. " FAIL " .. case[1] .. " " .. tostring(err))
            if log then log:Write(LOG_ERROR, TAG .. " " .. tostring(err)) end
        end
    end
    print(TAG .. (failures == 0 and " ALL PASS" or " FAILED") .. " cases=" .. cases
        .. " assertions=" .. assertions .. " failures=" .. failures)
    if engine and engine.Exit then engine:Exit() end
end
