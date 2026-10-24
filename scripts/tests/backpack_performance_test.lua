-- 真实 BackpackPanel -> Host -> Grids -> EquipmentPower，500件冷列表预算回归。
-- Runtime: tests/backpack_performance_test.lua -tool_mode -graphicsheadless -nosound
-- 仅cache源码读取/内存Store/CPU绘图记录；不启动main/Boot，不访问玩家File。
local TAG = "[backpack_performance_test]"
local assertions, failures = 0, 0
local function check(ok, message)
    assertions = assertions + 1
    if not ok then failures = failures + 1; print(TAG .. " FAIL " .. message) end
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function source(name)
    if _G.BACKPACK_SOURCE_OVERRIDES and _G.BACKPACK_SOURCE_OVERRIDES[name] then
        return _G.BACKPACK_SOURCE_OVERRIDES[name]
    end
    if name == "ui.backpack.BackpackEquipmentList" and _G.BACKPACK_BASELINE_SOURCE then
        return _G.BACKPACK_BASELINE_SOURCE
    end
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), name)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function fixture(overrides)
    local data, revisions, modules = {}, {}, {}
    local counts = { evaluate = 0, apply = 0, power = 0, build = 0, io = 0, hydrate = 0,
        captures = 0, classCheckers = 0, sorts = 0, concats = 0, heroReads = 0 }
    local metrics = { drawEvaluate = 0, drawPower = 0, updateMaxMs = 0, updateMaxEvaluate = 0, pumps = 0 }
    local env = setmetatable({}, { __index = _G })
    env._G, env.time = env, { elapsedTime = 100 }
    local render = { bounds = 0, text = 0, trig = 0, powerSettings = 0, inventoryVisits = 0,
        dpr = 1, scale = 1, width = 1080, height = 2400, font = 1, raster = 1, spacing = 0, blur = 0,
        record = false, commands = {}, matrix = { 1, 0, 0, 1, 0, 0 } }
    env.graphics = { GetDPR = function() return render.dpr end,
        GetWidth = function() return render.width end, GetHeight = function() return render.height end }
    env.pairs = function(value)
        if value ~= (data.equipment and data.equipment.inventory) then return pairs(value) end
        return function(t, key)
            local nextKey, item = next(t, key)
            if nextKey ~= nil then render.inventoryVisits = render.inventoryVisits + 1 end
            return nextKey, item
        end, value, nil
    end
    env.math = setmetatable({ sin = function(x) render.trig = render.trig + 1; return math.sin(x) end,
        cos = function(x) render.trig = render.trig + 1; return math.cos(x) end }, { __index = math })
    env.table = setmetatable({ sort = function(...)
        counts.sorts = counts.sorts + 1; return table.sort(...)
    end, concat = function(...)
        counts.concats = counts.concats + 1; return table.concat(...)
    end }, { __index = table })
    env.package = { loaded = modules, preload = {}, path = "" }
    env.File = function() counts.io = counts.io + 1; error("player IO forbidden") end
    env.fileSystem = setmetatable({}, { __index = function()
        return function() counts.io = counts.io + 1; error("player IO forbidden") end
    end })
    local drawIds, detailOpens, actions, messages = {}, {}, {}, {}
    local selected, owner, pinned = nil, nil, false
    local noop = function() end
    local function hit(x, y, cx, cy, w, h) return math.abs(x - cx) <= w / 2 and math.abs(y - cy) <= h / 2 end
    local forbiddenReads = {}
    local store = { Get = function(key)
            assert(not forbiddenReads[key], "unexpected manual dependency " .. key)
            if key == "heroes" then counts.heroReads = counts.heroReads + 1 end
            return data[key]
        end,
        GetRevision = function(key) return revisions[key] or 0 end,
        Subscribe = noop, Unsubscribe = noop }
    modules["core.PlayerStore"] = store
    local draw = { hitTest = hit, drawImageCentered = noop, drawTextStroke = noop, drawShardIcon = noop,
        seamSlideX = function() return 0 end }
    modules["core.DrawUtil"] = draw
    modules["core.DarkIcon"] = { drawNine = noop, drawQualityBg = noop, drawIconDark = noop, draw = noop,
        QUALITY_TRIM = { { 1, 2, 3 }, { 1, 2, 3 }, { 1, 2, 3 }, { 1, 2, 3 }, { 1, 2, 3 }, { 1, 2, 3 } } }
    modules["core.I18n"] = { t = function(s) return s end, lookup = function(s) return s end,
        format = string.format }
    modules["core.GameState"] = {}
    modules["core.UiToast"] = { show = function(s) messages[#messages + 1] = s end }
    modules["ui.widget.ImageCache"] = { init = noop, getEquipIcon = function(id)
        drawIds[#drawIds + 1] = id; return -1
    end }
    modules["ui.widget.QualityMark"] = { init = noop, draw = noop }
    modules["ui.widget.HeroFrame"] = { initImages = noop, draw = noop }
    modules["ui.widget.SetFilterDialog"] = { NONE_KEY = "none", close = noop, draw = noop,
        countSelected = function(t) local n = 0; for _, v in pairs(t) do if v then n = n + 1 end end; return n end,
        isOpen = function() return false end, handleHover = function() return false end }
    modules["ui.widget.EquipmentSetIcon"] = { drawBadge = noop, hasBadge = function() return false end,
        badgeLayout = function(cx, cy, size) return { x = cx - size / 2, size = size / 4 } end,
        levelLayout = function(_, cx, cy) return { x = cx + 70, y = cy + 70, fontSize = 30, align = 0 } end }
    modules["ui.hud.popup.SettingsPanel"] = { isEquipmentPowerEnabled = function()
        render.powerSettings = render.powerSettings + 1; return true
    end }
    modules["config.HeroAssetUtil"] = { preloadIcons = noop }
    modules["ui.character.panel.CharacterPanel"] = { getShards = function() return 0 end }
    modules["ui.character.detail.CharacterDetail"] = { getHeroId = function() return 1 end,
        isEquipTab = function() return true end, markPowerDirty = noop }
    modules["ui.character.equip.EquipmentDetail"] = {
        init = noop, drawIf = noop, getOwner = function() return owner end,
        isOpen = function() return selected ~= nil end, isPinned = function() return pinned end,
        open = function(seq) selected, owner = seq, "backpack"; detailOpens[#detailOpens + 1] = seq end,
        close = function() selected, owner, pinned = nil, nil, false end,
        dismissHover = function() if not pinned then selected, owner = nil, nil end end,
        pin = function() pinned = true end, setComparisonSlot = noop, setAnchor = noop,
        handleInput = function() return false end,
    }
    modules["systems.ButtonFeedback"] = { begin = function() return false end, finish = noop, trigger = noop }
    modules["systems.GameSFX"] = { playUIMove = noop, play = noop }
    modules["systems.TutorialManager"] = { isActive = function() return false end, notifyEvent = noop }
    modules["ui.loot.InventoryCurationDialog"] = { cancelSource = noop, drawEntry = noop }
    modules["ui.blacksmith.BlacksmithDecompose"] = { cancelMarquee = noop }
    modules["ui.backpack.BackpackItems"] = {}
    modules["ui.backpack.BackpackDialogs"] = { bind = function() return { closeTransferConfirm = noop } end }
    modules["ui.backpack.BackpackWindow"] = { bind = function() return noop, noop end }
    modules["runtime.GameAction"] = { sendAction = function(action, payload)
        actions[#actions + 1] = { action = action, payload = payload }; return true
    end }
    modules["ui.town.TownPageChrome"] = { easeOutCubic = function(t) return t end,
        easeInCubic = function(t) return t end, easeInOutCubic = function(t) return t end,
        drawNamePlate = noop, drawBack = noop, drawTabBar = noop,
        tabSlide = function() return 1, 1, 1 end, hitBack = function() return false end,
        hitTab = function(x, y)
            if y == 2308 and x == 540 then return 2 end
            if y == 2308 and x == 274 then return 1 end
        end }
    -- 菜单控件树不是本专项对象；保留真实Panel筛选状态并记录onChange适配。
    local filters = {}
    modules["ui.backpack.BackpackFilters"] = { attachInput = noop, bindWarehouse = function(state, _, gridState)
        filters.state, filters.gridState = state, gridState
        return { close = noop, draw = noop, drawOverlay = noop, isOpen = function() return false end,
            handleInput = function() return false end }
    end }
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgScissor", "nvgTranslate", "nvgScale", "nvgGlobalAlpha",
        "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFillColor", "nvgFill", "nvgStrokeColor", "nvgStrokeWidth",
        "nvgStroke", "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgText" }) do
        env[name] = function(...)
            if name == "nvgText" then render.text = render.text + 1 end
            if render.record and name ~= "nvgFontFace" and name ~= "nvgFontSize" and name ~= "nvgTextAlign" then
                local command = { name }
                for i = 2, select("#", ...) do command[#command + 1] = select(i, ...) end
                if name == "nvgText" and render.fontSize then command[#command + 1] = render.fontSize() end
                render.commands[#render.commands + 1] = command
            end
        end
    end
    env.nvgRGBA = function(...) return { ... } end
    env.nvgFindFont = function() return render.font end
    env.nvgCurrentTransform = function(_, matrix)
        for i = 1, 6 do matrix[i] = render.matrix[i] end
    end
    local fontSize = 40
    local setFont = env.nvgFontSize
    env.nvgFontSize = function(vg, size) fontSize = size; setFont(vg, size) end
    env.nvgTextBounds = function(_, _, _, text)
        render.bounds = render.bounds + 1
        return #text * 12 * (fontSize / 40) * render.raster
            + math.max(0, #text - 1) * render.spacing + render.blur * 0.1
    end
    render.fontSize = function() return fontSize end
    env.require = function(name)
        if modules[name] ~= nil then return modules[name] end
        assert(not name:match("^boot%.") and not name:match("^runtime%."), "undeclared dependency " .. name)
        local value = assert(load(overrides and overrides[name] or source(name), "@backpack-private/" .. name, "t", env))()
        modules[name] = assert(value, name)
        if name == "systems.EquipmentPower" then
            for method, counter in pairs({ evaluate = "evaluate", buildContext = "build" }) do
                local original = value[method]
                value[method] = function(...)
                    counts[counter] = counts[counter] + 1
                    return original(...)
                end
            end
        elseif name == "systems.EquipmentSystem" then
            for method, counter in pairs({ applyEquip = "apply", hydrate = "hydrate" }) do
                local original = value[method]
                value[method] = function(...)
                    counts[counter] = counts[counter] + 1
                    return original(...)
                end
            end
        elseif name == "ui.character.detail.EquipmentWearability" then
            local original = value.createClassChecker
            value.createClassChecker = function(...)
                counts.classCheckers = counts.classCheckers + 1; return original(...)
            end
        elseif name == "ui.backpack.BackpackEquipmentList" then
            local original = value.bind
            value.bind = function(deps)
                local capture = deps.capture
                deps.capture = function(...)
                    counts.captures = counts.captures + 1; return capture(...)
                end
                return original(deps)
            end
        elseif name == "systems.CombatPower" then
            local original = value.calculate
            value.calculate = function(...) counts.power = counts.power + 1; return original(...) end
        end
        return value
    end
    local panel = env.require("ui.backpack.BackpackPanel")
    local EP, EC = env.require("systems.EquipmentPower"), env.require("config.EquipmentConfig")
    local Eq = env.require("systems.EquipmentSystem")
    local Grids = env.require("ui.backpack.BackpackGrids")
    local latestGrids = {}
    local bind = Grids.bind
    Grids.bind = function(deps)
        local grids = bind(deps)
        latestGrids = grids
        return grids
    end
    local f = { panel = panel, EP = EP, EC = EC, Eq = Eq, data = data, counts = counts, render = render,
        vg = {}, modules = modules,
        metrics = metrics, env = env, filters = filters, actions = actions, detailOpens = detailOpens,
        drawIds = drawIds, forbiddenReads = forbiddenReads }
    function f.notify(key, invalidate)
        revisions[key] = (revisions[key] or 0) + 1
        if invalidate ~= false then EP.invalidate() end
    end
    function f.initialize()
        data.heroes = { roster = { [1] = { level = 80, awakening = {}, extraTalent = {} },
            [2] = { level = 80, awakening = {}, extraTalent = {} } },
            teams = { { slots = { 1, 2 } }, { slots = {} }, { slots = {} } }, deployed = { 1, 2 } }
        data.equipment = { inventory = {}, equipped = { [1] = {}, [2] = {} } }
        data.artifacts, data.talents = { bag = {}, equippedByTeam = {} }, { litNodes = {} }
        data.currency = { gold = 0 }
        for i = 1, 500 do
            local tid = EC.BY_SLOT.accessory[((i - 1) % #EC.BY_SLOT.accessory) + 1]
            local item = Eq.generate(tid, 30 + i % 40, 1 + i % 6)
            item.seq = i
            data.equipment.inventory[tostring(i)] = item
        end
        for _, key in ipairs({ "heroes", "equipment", "artifacts", "talents" }) do f.notify(key) end
    end
    function f.grids() return latestGrids end
    function f.list() return latestGrids.getCommittedEquipList() end
    function f.expFlow(replace)
        if replace then data.heroes = copy(data.heroes) end
        data.heroes.roster[1].exp = (data.heroes.roster[1].exp or 0) + 1
        for _, team in ipairs(data.heroes.teams) do team.exp = (team.exp or 0) + 1 end
        data.heroes.gold = (data.heroes.gold or 0) + 1
        data.currency.gold = data.currency.gold + 10
        f.notify("heroes"); f.notify("currency")
    end
    function f.draw()
        for i = #drawIds, 1, -1 do drawIds[i] = nil end
        local before = copy(counts)
        panel.draw(f.vg)
        metrics.drawEvaluate = metrics.drawEvaluate + counts.evaluate - before.evaluate
        metrics.drawPower = metrics.drawPower + counts.power - before.power
        check(counts.evaluate == before.evaluate and counts.apply == before.apply and counts.power == before.power
            and counts.build == before.build and counts.hydrate == before.hydrate, "Render contains no scoring/context/hydration")
    end
    function f.update()
        local before, start = counts.evaluate, os.clock()
        panel.update(1 / 60)
        metrics.updateMaxMs = math.max(metrics.updateMaxMs, (os.clock() - start) * 1000)
        metrics.updateMaxEvaluate = math.max(metrics.updateMaxEvaluate, counts.evaluate - before)
        metrics.pumps = metrics.pumps + 1
        check(counts.evaluate - before <= 128, "Update evaluation bounded independently of inventory size")
    end
    function f.finish(expected, stream)
        for frame = 1, 20000 do
            if stream then f.expFlow(frame % 5 == 0) end
            f.update()
            local list = f.list()
            check(#list == 0 or #list == expected, "private list never partially publishes")
            f.draw()
            if #list == expected and (expected == 0 or not list[1].powerPending) then return list, frame end
        end
        error("budget queue starvation")
    end
    f.initialize()
    return f
end

local function runAvailabilityTests()
    for _, heroMode in ipairs({ false, true }) do
        local f = fixture()
        f.panel.open("left", "equip")
        if heroMode then f.panel.setEquipmentSlotFilter(nil, 1) end
        local firstVisible, visibleFrames = nil, 0
        local builds = f.counts.build
        for frame = 1, 300 do
            -- 真实消费字段持续改变：不是仅 exp 通知；无通知 patch 也必须发现。
            for id, hero in pairs(f.data.heroes.roster) do
                hero.level = 80 + frame % 2
                hero.extraTalent.stacks = frame + id
                hero.extraTalent.issuedCards = frame * 2 + id
            end
            if frame % 3 == 0 then f.notify("heroes") end
            if frame % 5 == 0 then f.notify("artifacts") end
            if frame % 7 == 0 then f.notify("talents") end
            f.update()
            local list = f.list()
            f.draw()
            if #list == 500 and #f.drawIds > 0 then
                firstVisible = firstVisible or frame
                visibleFrames = visibleFrames + 1
                local first = list[1]
                local peek = f.panel.peekEquipAt(160, 840)
                check(peek and peek.seq == first.seq and f.drawIds[1] == first.templateId,
                    "continuous combat changes preserve rendered/clicked basic order")
                if heroMode then
                    check(first.power == nil and first.powerPending == true and not first.upgrade,
                        "pending hero score is not false zero or stale upgrade")
                end
            end
        end
        check(firstVisible == 1 and visibleFrames == 300,
            (heroMode and "hero" or "manual") .. " 500 basic entries remain visible throughout real growth/artifact/talent updates")
        if not heroMode then
            check(f.counts.build == builds and f.counts.evaluate == 0,
                "manual warehouse never builds hero context or evaluates candidates")
            -- profiler/依赖入口也不能偷偷读战斗模块；独立于上面的旧源可复现循环。
            if not _G.BACKPACK_BASELINE_SOURCE then
                for _, key in ipairs({ "heroes", "artifacts", "talents" }) do f.forbiddenReads[key] = true end
                f.update(); f.draw()
                check(f.panel.peekEquipAt(160, 840) ~= nil, "manual list presentation/input have no combat Store reads")
                for key in pairs(f.forbiddenReads) do f.forbiddenReads[key] = nil end
            end
        end
        if not _G.BACKPACK_BASELINE_SOURCE then
            -- 装备通知（含满仓同值通知）仍可频繁到来，完整basic每次Update恢复。
            for frame = 1, 30 do
                if frame % 2 == 0 then
                    local item = f.data.equipment.inventory["1"]
                    item.locked = not item.locked
                end
                f.notify("equipment")
                check(f.panel.peekEquipAt(160, 840) == nil, "equipment version blocks stale presented instance")
                f.update(); f.draw()
                check(#f.list() == 500 and f.panel.peekEquipAt(160, 840) ~= nil,
                    "frequent equipment notifications rebuild cheap full list next Update")
            end
            local shown = f.panel.peekEquipAt(160, 840)
            f.data.equipment.inventory[tostring(shown.seq)] = nil
            f.notify("equipment")
            check(f.panel.peekEquipAt(160, 840) == nil, "deleted displayed instance never remains clickable")
            f.update(); f.draw()
            check(#f.list() == 499 and f.panel.peekEquipAt(160, 840).seq ~= shown.seq,
                "deletion replaces basic list with current inventory")
            -- 候选是否可穿始终由当前权威checker决定，不相信pending列表的旧灰显。
            if heroMode then
                f.data.heroes.roster[1].level = 1
                local pending = f.list()
                check(pending[1].canWear == false, "no-notify level change refreshes pending wearability")
                local before = #f.actions
                f.panel.handleRightClick(160, 840)
                check(#f.actions == before, "right click rejects current authoritative level gate while score pending")
                f.data.heroes.roster[1].level = 80
                f.panel.handleRightClick(160, 840)
                check(#f.actions == before + 1, "pending basic list still permits authority-checked equip action")
            end
        end
        print(string.format("%s AVAILABILITY mode=%s firstVisible=%s visibleFrames=%d builds=%d",
            TAG, heroMode and "hero" or "manual", tostring(firstVisible), visibleFrames, f.counts.build - builds))
    end
end

local function runRenderHotPathTests()
    for _, classFilter in ipairs({ "all", "seal" }) do
        local f = fixture()
        -- 三队同时运行的25名册；只读CPU绘图spy，不启动战斗/存档或真GPU。
        for id = 1, 25 do
            f.data.heroes.roster[id] = { level = 80, awakening = { [1] = true },
                extraTalent = { stacks = id, nested = { issuedCards = id * 2 } } }
        end
        f.data.heroes.teams = { { slots = { 1, 2, 3, 4 } }, { slots = { 5, 6, 7, 8 } },
            { slots = { 9, 10, 11, 12 } } }
        f.panel.open("left", "equip")
        f.panel.setEquipmentSlotFilter(nil, 1)
        f.filters.state.classFilter = classFilter
        f.update(); f.draw()
        check(#f.list() == 500 and #f.drawIds > 0, "500-entry three-team render benchmark is populated")
        local before, renderBefore = copy(f.counts), copy(f.render)
        local start, frames = os.clock(), 240
        for _ = 1, frames do f.draw() end
        local elapsed = (os.clock() - start) * 1000
        local captures, classCheckers, sorts, concats = f.counts.captures - before.captures,
            f.counts.classCheckers - before.classCheckers, f.counts.sorts - before.sorts,
            f.counts.concats - before.concats
        print(string.format("%s RENDER_CPU class=%s frames=%d meanMs=%.4f captures=%d classCheckers=%d sorts=%d concats=%d hydrate=%d",
            TAG, classFilter, frames, elapsed / frames, captures, classCheckers, sorts, concats,
            f.counts.hydrate - before.hydrate))
        print(string.format("%s DRAW_CALLS class=%s bounds/frame=%.1f text/frame=%.1f trig/frame=%.1f settings/frame=%.1f inventoryKeys/frame=%.1f",
            TAG, classFilter, (f.render.bounds - renderBefore.bounds) / frames,
            (f.render.text - renderBefore.text) / frames, (f.render.trig - renderBefore.trig) / frames,
            (f.render.powerSettings - renderBefore.powerSettings) / frames,
            (f.render.inventoryVisits - renderBefore.inventoryVisits) / frames))
        if not _G.BACKPACK_SOURCE_OVERRIDES then
            check(captures == frames, "Render captures once, not present + getCommittedList twice")
            check(classCheckers == 0 and sorts == 0, "warm Render never rebuilds class rules or sorts/serializes hero fields")
            check(concats == 0, "warm Render compares values without allocating serialized request/wear keys")
            check(f.render.bounds - renderBefore.bounds == frames, "warm Render uses one raster/DPR probe, no per-cell measure")
            check(f.render.trig == renderBefore.trig and f.render.powerSettings - renderBefore.powerSettings == frames,
                "warm Render reuses identical16-direction offsets and reads settings once")
        end
        local growthStart = os.clock()
        for frame = 1, frames do
            -- 持续真实消费值变化但不通知；其余24名册不应重新深冻结。
            f.data.heroes.roster[1].extraTalent.nested.issuedCards = frame
            f.draw()
            check(#f.drawIds > 0, "combat growth never skips a rendered inventory frame")
        end
        print(string.format("%s GROWTH_DRAW_CPU class=%s frames=%d meanMs=%.4f",
            TAG, classFilter, frames, (os.clock() - growthStart) * 1000 / frames))
        check(f.counts.build == before.build and f.counts.hydrate == before.hydrate
            and f.counts.evaluate == before.evaluate and f.counts.power == before.power,
            "warm Render has zero preparation/hydration/scoring work")
        local shown = f.panel.peekEquipAt(160, 840)
        f.expFlow(true)
        f.draw()
        check(f.panel.peekEquipAt(160, 840).seq == shown.seq, "exp-only root replacement retains visible pointer order")
        -- 必须在同一Update之后、Render之前观察品质/集合的原地变化；不能按帧号缓存。
        f.update()
        f.filters.state.qualitySet[6] = true
        check(f.panel.peekEquipAt(160, 840) == nil, "same-frame quality patch rejects cached presented list")
        f.draw(); check(#f.drawIds == 0, "same-frame quality patch cannot render previous filter")
        f.update(); f.draw()
        check(#f.drawIds > 0, "current filter repopulates completely next Update")
        f.filters.state.setFilter.none = true
        check(f.panel.peekEquipAt(160, 840) == nil, "same-frame selected-set insertion rejects cached filter")
        f.update(); f.draw()
        f.filters.state.setFilter.none = nil
        check(f.panel.peekEquipAt(160, 840) == nil, "same-frame selected-set deletion rejects cached filter")
        f.filters.state.qualitySet = {}
        f.panel.setEquipmentSlotFilter(nil, 2)
        f.draw(); check(#f.drawIds == 0, "hero switch never displays previous hero version")
        f.update(); f.draw()
        check(#f.list() == 500 and #f.drawIds > 0, "hero switch keeps complete basic inventory available")
        check(f.counts.io == 0, "render benchmark never accesses player files")
    end
end

local function runSameFrameCaptureTests()
    local f = fixture()
    local scheduler = f.env.require("ui.backpack.BackpackEquipmentList").bind({
        capture = function() return { heroId = 1, filterKey = "same-frame" } end,
        buildBasic = function() return { { seq = 1, powerPending = true } } end,
        build = function() return { { seq = 1, power = 123, upgrade = true } } end,
        refresh = function(list, _, pending)
            if pending then return { { seq = list[1].seq, powerPending = true } } end
            return list
        end,
    })
    local mutations = {
        function() f.data.heroes.roster[1].level = 81 end,
        function() f.data.heroes.roster[1].advBranch = { first = 104 } end,
        function() f.data.heroes.roster[1].advBranch.second = 208 end,
        function() f.data.heroes.roster[1].advBranch.first = nil end,
        function() f.data.heroes.roster[1].awakening[1] = true end,
        function() f.data.heroes.roster[1].awakening[1] = nil end,
        function() f.data.heroes.roster[1].extraTalent.nested = { value = 1 } end,
        function() f.data.heroes.roster[1].extraTalent.nested.value = 2 end,
        function() f.data.heroes.roster[1].extraTalent.nested = nil end,
        function() f.data.heroes.teams[1].slots[1] = { heroId = 2 } end,
        function() f.data.heroes.roster[3] = { level = 80 } end,
        function() f.data.heroes.roster[3] = nil end,
    }
    for i, mutate in ipairs(mutations) do
        scheduler.getEquipList()
        scheduler.update()
        check(scheduler.present()[1].power == 123, "same-frame fixture starts scored " .. i)
        mutate() -- 不通知且不再Update；Render读取必须自己发现，不允许借同帧旧快照。
        local rendered = scheduler.present()
        check(rendered[1].power == nil and rendered[1].powerPending,
            "Render rejects same-frame unnotified combat patch " .. i)
        check(scheduler.getPresentedList()[1].power == nil,
            "pointer cannot resurrect invalid score " .. i)
    end
    scheduler.getEquipList(); scheduler.update()
    local scored = scheduler.present()
    f.expFlow(true)
    check(scheduler.present() == scored, "exp-only copied roster preserves scored identity")
    scheduler.freezeForClose()
    f.data.heroes.roster[1].level = 1
    check(scheduler.present() == scored and #scheduler.getPresentedList() == 0,
        "closing retains drawn score snapshot but disables pointer")
end

local function runDrawParityTests()
    -- 可由CPU runner注入030fda51源码，对每条真正绘图命令逐项比对；不需落盘旧文件。
    local reference = _G.BACKPACK_DRAW_REFERENCE
    for _, mode in ipairs({ "left", "inline" }) do
        local f, old = fixture(), reference and fixture(reference) or nil
        if old then old.data.equipment = copy(f.data.equipment) end
        local function each(fn) fn(f); if old then fn(old) end end
        each(function(x)
            for key, item in pairs(x.data.equipment.inventory) do
                item.ascendLevel, item.locked = tonumber(key) % 3, tonumber(key) % 7 == 0
            end
            x.panel.open(mode == "left" and "left" or false, "equip"); x.update(); x.draw()
            x.render.record = true
        end)
        local function draw(label)
            each(function(x) x.render.commands = {}; x.draw() end)
            if old then
                check(equal(f.drawIds, old.drawIds), label .. " old/new viewport IDs")
                check(equal(f.render.commands, old.render.commands), label .. " old/new draw command/color/position/font parity")
            end
        end
        for _, scroll in ipairs({ 0, 139.999, 140, 140.001, 239.999, 240, 240.001,
            429.999, 430, 430.001, 1900, 15000, 100000 }) do
            each(function(x) x.filters.gridState.scrollY = scroll end)
            draw(mode .. " scroll=" .. scroll)
        end
        -- 度量缓存热态后分别改变每个原生度量依赖，不能复用旧宽度。
        local changes = {
            function(x) x.render.dpr = 2; x.render.raster = 2 end,
            function(x) x.render.matrix[1], x.render.matrix[4] = 0.75, 0.75; x.render.raster = 1.5 end,
            function(x) x.render.width, x.render.height = 2400, 1080; x.render.raster = 1.25 end,
            function(x) x.render.font = 2; x.render.raster = 1.75 end,
            function(x) x.vg = {}; x.render.raster = 1.4 end,
            function(x) x.render.raster = 2.1 end, -- 同handle字体重载/frame pixelRatio，只能靠字形探针发现。
            function(x) x.render.spacing = 0.75 end,
            function(x) x.render.blur = 2 end,
            function(x) x.render.matrix[2], x.render.matrix[3] = 0.1, -0.1 end,
        }
        for i, mutate in ipairs(changes) do
            each(mutate)
            local before = f.render.bounds
            draw(mode .. " metric change=" .. i)
            check(f.render.bounds > before + 1, "changed metric remeasures real visible strings " .. i)
            before = f.render.bounds
            draw(mode .. " metric warm=" .. i)
            if not _G.BACKPACK_SOURCE_OVERRIDES then
                check(f.render.bounds == before + 1, "unchanged metric uses single probe " .. i)
            end
        end
        -- 不能把Render移到Update：无通知增删仍当帧更新容量文字。
        each(function(x)
            x.data.equipment.inventory["501"] = copy(x.data.equipment.inventory["1"])
        end)
        draw(mode .. " same-frame insert capacity")
        local capacity
        for _, command in ipairs(f.render.commands) do
            if command[1] == "nvgText" and tostring(command[4]):find("背包上限", 1, true) then capacity = command[4] end
        end
        check(capacity and capacity:find("501/", 1, true), "capacity immediately sees unnotified inventory insert")
        each(function(x) x.data.equipment.inventory["501"] = nil end)
        draw(mode .. " same-frame remove capacity")
        each(function(x) x.env.nvgCurrentTransform = false end)
        draw(mode .. " missing native measurement contract falls back uncached")
        each(function(x) x.panel.close(); x.notify("equipment"); x.update() end)
        draw(mode .. " closing frozen draw")
        check(f.panel.peekEquipAt(160, 840) == nil, "closing parity never restores input")
    end
end

local function runTests()
    runSameFrameCaptureTests()
    runDrawParityTests()
    if _G.BACKPACK_RENDER_ONLY then runRenderHotPathTests(); return end
    runAvailabilityTests()
    runRenderHotPathTests()
    if _G.BACKPACK_AVAILABILITY_ONLY then return end
    local f = fixture()
    local panel, data, metrics = f.panel, f.data, f.metrics
    local inventoryBefore = copy(data.equipment)
    panel.open("left", "equip")
    panel.setEquipmentSlotFilter(nil, 1)
    f.draw()
    check(#f.drawIds == 0 and f.counts.evaluate == 0 and f.counts.build == 0, "500 cold candidates not scored in first draw")
    check(panel.peekEquipAt(160, 840) == nil, "cold list has no hit target")
    f.update()
    check(#f.list() == 500 and f.list()[1].powerPending and panel.peekEquipAt(160, 840) == nil,
        "cheap complete list ready in first Update, not clickable until Render")
    f.draw()
    check(panel.peekEquipAt(160, 840) ~= nil, "pending score never blocks rendered basic inventory")
    local basicPeek = panel.peekEquipAt(160, 840)
    local list, frames = nil, 0
    for frame = 1, 20000 do
        f.expFlow(frame % 5 == 0)
        f.update()
        list = f.list()
        if #list == 500 and not list[1].powerPending then frames = frame; break end
    end
    local beforeNewRender = panel.peekEquipAt(160, 840)
    check(beforeNewRender and beforeNewRender.seq == basicPeek.seq,
        "basic-to-scored Update keeps last rendered order clickable until next Render")
    f.draw()
    check(frames > 1 and #list == 500, "500 entries complete under continuous roster/team exp and currency notifications")
    check(f.counts.build == 1, "exp replacement/invalidation never restarts private context")
    check(#f.drawIds > 0 and #f.drawIds < 100, "real grid only draws viewport after full scoring finishes")
    check(equal(data.equipment, inventoryBefore), "snapshot/hydrate/preview never mutate live inventory or equipped")
    local first = list[1]
    local peek = panel.peekEquipAt(160, 840)
    check(peek and peek.seq == first.seq and f.drawIds[1] == first.templateId, "draw and peek share presented order")
    panel.handleHover(160, 840); f.env.time.elapsedTime = f.env.time.elapsedTime + 0.4; panel.handleHover(160, 840)
    check(f.detailOpens[#f.detailOpens] == first.seq, "hover opens same displayed seq")
    panel.handleInput(160, 840)
    check(f.detailOpens[#f.detailOpens] == first.seq, "single click pins same displayed seq")
    panel.handleRightClick(160, 840)
    check(#f.actions == 1 and f.actions[1].payload.seq == first.seq, "right click submits same displayed seq through authoritative precheck")
    local stableBuilds, stableEvaluations = f.counts.build, f.counts.evaluate
    for i = 1, 20 do f.expFlow(i % 2 == 0); f.update(); f.draw() end
    check(f.list() == list and f.counts.build == stableBuilds and f.counts.evaluate == stableEvaluations,
        "completed list stable under continued equal notifications")

    -- Update完成新列表但Render尚未展示时，不能点击一个未见过的新排序。
    f.filters.state.sortKey, f.filters.state.sortAscending = "level", true
    check(panel.peekEquipAt(160, 840) == nil, "new sort blocks old cell immediately")
    f.draw(); check(#f.drawIds == 0, "new sort draws no stale old list")
    for i = 1, 20000 do f.update(); if #f.list() == 500 and not f.list()[1].powerPending then break end end
    check(#f.list() == 500 and panel.peekEquipAt(160, 840) == nil, "new commit cannot be hit before it is rendered")
    f.draw()
    list = f.list()
    peek = panel.peekEquipAt(160, 840)
    check(peek and peek.seq == list[1].seq and list[1].level <= list[500].level, "new rendered ascending level order is clickable")

    -- 评分中途筛选/装备/真实成长更换：撤销旧版本，不partialpublish。
    f.filters.state.sortKey = "power"
    f.update()
    f.filters.state.qualitySet[6] = true
    f.update()
    data.equipment.inventory["1"].locked = true
    f.notify("equipment")
    f.update()
    data.heroes.roster[2].extraTalent = { issuedCards = 4 }
    f.notify("heroes")
    check(panel.peekEquipAt(160, 840) == nil and f.list()[1] and f.list()[1].powerPending,
        "new structural version awaits Render; growth only invalidates scores")
    local count = 0
    for _, item in pairs(data.equipment.inventory) do if item.quality == 6 then count = count + 1 end end
    list = f.finish(count, true)
    for _, item in ipairs(list) do check(item.quality == 6, "only new quality filter committed") end

    -- 同步查询穿插：保留独立即时完整结果，不yield、不篡改在途ctx。
    f.filters.state.qualitySet, f.filters.state.sortKey = {}, "level"
    f.update()
    local synchronous = f.grids().getEquipList()
    check(#synchronous == 500 and coroutine.isyieldable() == false, "explicit synchronous query retains immediate full result")
    local synchronousAgain = f.grids().getEquipList()
    check(synchronous == synchronousAgain, "explicit synchronous cache identity retained")
    f.draw(); f.update()
    check(f.list() == synchronous, "synchronous complete result atomically usable without partial task overwrite")
    local EP = f.EP
    f.filters.state.sortAscending = false
    f.update()
    local context = EP.getContext(1)
    local score = EP.score(data.equipment.inventory["10"], 1)
    local preview = EP.evaluate(context, 10)
    check(type(score) == "number" and preview ~= nil, "synchronous getContext/score/evaluate still independent during private work")
    list = f.finish(500, true)
    check(list[1].level >= list[500].level, "private work finishes correct descending order after sync scoring")
    local function parity(label)
        local async = f.list()
        local synchronousList = f.grids().getEquipList()
        check(#async == #synchronousList, label .. " sync/async length")
        for i, item in ipairs(async) do
            local other = synchronousList[i]
            check(other and item.seq == other.seq and item.power == other.power and item.canWear == other.canWear
                and item.upgrade == other.upgrade and item.cannotEquipReason == other.cannotEquipReason,
                label .. " sync/async authoritative score/order/grey/recommendation " .. i)
        end
    end
    parity("generated full inventory")
    data.equipment.inventory["1"] = { templateId = "C1", level = 999, quality = 3 }
    data.equipment.inventory["2"] = { templateId = "A55", level = 1, quality = 3 }
    data.equipment.inventory["3"] = { templateId = "W1", level = 1, quality = 3 }
    f.notify("equipment")
    f.finish(500, true)
    parity("lean invalid-level/class and valid candidate")
    -- 原同步score优先equip.seq；只有缺seq才按源实例identity反查库存键。
    data.equipment.inventory["4"].seq = 5
    data.equipment.inventory["6"].seq = nil
    f.notify("equipment")
    f.finish(500, true)
    parity("mismatched seq/key and missing seq")
    panel.setEquipmentSlotFilter("weapon", 1)
    f.finish(1, true)
    parity("weapon structural selection")
    panel.setEquipmentSlotFilter(nil, 1)
    f.finish(500, true)

    -- 无通知的本地成长patch同样必须被commit终检和读取端发现。
    local growth = data.heroes.roster[1].extraTalent
    growth.issuedCards = 5
    check(#f.list() == 500 and f.list()[1].powerPending and panel.peekEquipAt(160, 840) ~= nil,
        "no-notify same-table growth invalidates score, not visible inventory")
    f.update()
    growth.issuedCards = 6
    check(#f.list() == 500 and f.list()[1].powerPending,
        "no-notify growth during private snapshot never exposes mixed score")
    list = f.finish(500, true)
    check(#list == 500, "no-notify growth restarts and finishes full latest version")

    -- 各战斗输入（包括原地名册值）不可错误忽略。
    local changes = {
        { "level", "heroes", function() data.heroes.roster[1].level = 81 end },
        { "team", "heroes", function() data.heroes.teams[1].slots = { 2, 1 } end },
        { "awakening", "heroes", function() data.heroes.roster[1].awakening = { [1] = true } end },
        { "branch", "heroes", function() data.heroes.roster[1].advBranch = { first = 104 } end },
        { "talent", "talents", function() data.talents.litNodes = { 113 } end },
        { "artifact", "artifacts", function() data.artifacts.bag = {} end },
        { "equipped", "equipment", function() data.equipment.equipped[1].accessory = 1 end },
    }
    for _, case in ipairs(changes) do
        local before = f.list()
        case[3](); f.notify(case[2])
        if case[2] == "equipment" then
            check(#f.list() == 0 and panel.peekEquipAt(160, 840) == nil, case[1] .. " invalidates structure before update")
        else
            check(#f.list() == 500 and f.list()[1].powerPending and panel.peekEquipAt(160, 840) ~= nil,
                case[1] .. " invalidates score without hiding inventory")
        end
        list = f.finish(500, true)
        check(list ~= before, case[1] .. " publishes fresh complete version")
    end
    -- 离页/关闭撤销，重入绝不恢复半成品；正式Store清根/换玩家identity模型。
    f.filters.state.sortKey = "power"; f.update()
    panel.handleInput(540, 2308); f.update()
    check(#f.list() == 0, "leaving equip tab cancels private work")
    panel.handleInput(274, 2308); f.update()
    f.draw()
    local drawnBeforeClose = copy(f.drawIds)
    check(#drawnBeforeClose > 0, "close fixture has actually rendered equipment")
    panel.close(); f.update()
    panel.releaseForEquipment()
    f.draw()
    check(panel.isOpen() and equal(drawnBeforeClose, f.drawIds), "closing keeps equipment artwork with page instead of clearing first")
    check(panel.peekEquipAt(160, 840) == nil, "closing visual snapshot cannot be clicked")
    -- 退场时即使后台装备版本变化，也只绘制原只读快照，不恢复评分任务。
    local beforeCloseCounts = copy(f.counts)
    f.notify("equipment")
    f.env.time.elapsedTime = f.env.time.elapsedTime + 0.1
    f.update(); f.draw()
    check(equal(drawnBeforeClose, f.drawIds) and equal(beforeCloseCounts, f.counts),
        "closing snapshot survives background notifications without scoring/hydration/IO")
    f.env.time.elapsedTime = f.env.time.elapsedTime + 1
    f.update(); f.draw()
    check(not panel.isOpen() and #f.drawIds == 0 and #f.list() == 0,
        "animation completion drops artwork and private work together")
    panel.open("left", "equip"); panel.setEquipmentSlotFilter(nil, 1)
    f.draw(); check(#f.drawIds == 0, "reentry never publishes prior session partial list")
    f.update()
    for _, key in ipairs({ "equipment", "heroes", "artifacts", "talents" }) do data[key] = copy(data[key]); f.notify(key) end
    check(#f.list() == 0, "player module root replacement discards prior player snapshot")
    f.finish(500, true)
    check(metrics.drawEvaluate == 0 and metrics.drawPower == 0 and f.counts.io == 0, "all draw paths zero evaluations and no player IO")
    print(string.format("%s METRICS coldFrames=%d updateMaxMs=%.3f updateMaxEvaluate=%d pumps=%d drawEvaluate=%d drawPower=%d",
        TAG, frames, metrics.updateMaxMs, metrics.updateMaxEvaluate, metrics.pumps, metrics.drawEvaluate, metrics.drawPower))
end

function Start()
    local ok, err = pcall(runTests)
    if not ok then check(false, "exception: " .. tostring(err)); print(TAG .. " " .. tostring(err)) end
    print(string.format("%s SUMMARY assertions=%d failures=%d %s", TAG, assertions, failures,
        failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
