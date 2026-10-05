-- 侧栏返回回归：沿用 forge_backpack_layer_test；真实宿主/输入/几何，页面仅内存替身。
-- 不加载 main 或存档；直接以 tests/seam_back_horizon_test.lua 为入口。
local assertions = 0
local function check(condition, label)
    assertions = assertions + 1
    assert(condition, label)
end
local function near(actual, expected, label)
    check(type(actual) == "number" and math.abs(actual - expected) < 0.00001,
        label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

function Start()
    assertions = 0
    ---@type any
    local oldGlobals = {}
    for key, value in pairs(_G) do oldGlobals[key] = value end
    local originalRequire = require
    ---@type any
    local oldLoaded = {}
    ---@type any
    local loaded = package and package.loaded
    if loaded then for key, value in pairs(loaded) do oldLoaded[key] = value end end
    ---@type any
    local saved = { rt = nil, viewport = nil, rtValues = {}, notes = nil }
    local ok, err = pcall(function()
        local RT = originalRequire("boot.StandaloneRT")
        local VP = originalRequire("core.Viewport")
        local Draw = originalRequire("core.DrawUtil")
        saved.rt, saved.viewport, saved.notes = RT, VP, VP._notes
        for key, value in pairs(RT) do saved.rtValues[key] = value end
        local function noop() return false end
        ---@return any
        local function mock(values)
            return setmetatable(values or {}, { __index = function() return noop end })
        end
        ---@type any
        local state = { tri = true, tab = 3, gates = {}, pages = {}, row = nil, panel = nil,
            leftMode = true, clock = 100, compact = false }
        ---@type any
        local events, bars = {}, {}
        ---@type any
        local cursor = { x = -1000, y = -1000 }
        ---@type any
        local paint = { tx = 0, ty = 0, sx = 1, sy = 1, clip = nil, stack = {} }
        ---@type any
        local capture = {}
        local ids = { "character", "smith", "loot", "task", "backpack", "talent", "church", "tavern", "market" }
        local function record(name, x, y)
            events[#events + 1] = { name = name, x = x, y = y }
        end
        local function count(name)
            local n = 0
            for _, event in ipairs(events) do if event.name == name then n = n + 1 end end
            return n
        end
        local function closeCount()
            local n = 0
            for _, id in ipairs(ids) do n = n + count(id .. ".close") end
            return n
        end
        local function noBusinessTap(label)
            for _, event in ipairs(events) do
                check(not event.name:match("^business%."), label .. " leaked=" .. event.name)
            end
        end
        local function rect(x, y, w, h)
            local x1, x2 = paint.tx + x * paint.sx, paint.tx + (x + w) * paint.sx
            local y1, y2 = paint.ty + y * paint.sy, paint.ty + (y + h) * paint.sy
            return { x = math.min(x1, x2), y = math.min(y1, y2), w = math.abs(x2 - x1), h = math.abs(y2 - y1) }
        end
        local function intersect(a, b)
            if not a then return b end
            local x, y = math.max(a.x, b.x), math.max(a.y, b.y)
            return { x = x, y = y, w = math.max(0, math.min(a.x + a.w, b.x + b.w) - x),
                h = math.max(0, math.min(a.y + a.h, b.y + b.h) - y) }
        end
        nvgSave = function()
            paint.stack[#paint.stack + 1] = { tx = paint.tx, ty = paint.ty, sx = paint.sx, sy = paint.sy, clip = paint.clip }
        end
        nvgRestore = function()
            local value = assert(table.remove(paint.stack), "NanoVG save/restore")
            paint.tx, paint.ty, paint.sx, paint.sy, paint.clip = value.tx, value.ty, value.sx, value.sy, value.clip
        end
        nvgTranslate = function(_, x, y) paint.tx, paint.ty = paint.tx + x * paint.sx, paint.ty + y * paint.sy end
        nvgScale = function(_, x, y) paint.sx, paint.sy = paint.sx * x, paint.sy * y end
        nvgScissor = function(_, x, y, w, h) paint.clip = rect(x, y, w, h) end
        nvgIntersectScissor = function(_, x, y, w, h) paint.clip = intersect(paint.clip, rect(x, y, w, h)) end
        nvgResetScissor = function() paint.clip = nil end
        nvgResetTransform = function() paint.tx, paint.ty, paint.sx, paint.sy = 0, 0, 1, 1 end
        nvgBeginFrame = function(_, width, height, dpr)
            paint.tx, paint.ty, paint.sx, paint.sy, paint.clip, paint.stack = 0, 0, 1, 1, nil, {}
            bars = {}
            near(width, RT.windowW, "render windowW")
            near(height, RT.windowH, "render windowH")
            near(dpr, RT.dpr, "render DPR")
        end
        nvgEndFrame = function() check(#paint.stack == 0, "render restores NanoVG stack") end
        for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgFillColor", "nvgFill" }) do _G[name] = noop end
        nvgRGBA = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
        input = { GetMousePosition = function() return cursor end }
        time = { elapsedTime = state.clock }

        local function page(id)
            return mock({
                isOpen = function() return state.pages[id].open end,
                getSeamAnim = function()
                    local p = state.pages[id]
                    return p.ot, p.ct, p.od, p.cd
                end,
                close = function()
                    record(id .. ".close")
                    state.pages[id].ct = state.clock
                end,
                draw = noop,
                handleDragBegin = function(x, y) record(id .. ".down", x, y); return true end,
                handleDragMove = function(x, y) record(id .. ".move", x, y); return true end,
                handleDragEnd = function(x, y) record(id .. ".up", x, y); return false end,
                handleInput = function(x, y) record("business." .. id .. ".input", x, y); return true end,
                handleNavigationTap = function(x, y) record("business." .. id .. ".navigation", x, y); return true end,
                handleEquipmentSlotTap = function(x, y) record("business." .. id .. ".slot", x, y); return false end,
            })
        end
        ---@type any
        local pages = {}
        for _, id in ipairs(ids) do
            state.pages[id] = { open = false, ot = 90, ct = 0, od = 0.45, cd = 0.38, scale = 1 }
            pages[id] = page(id)
        end
        pages.backpack.isLeftMode = function() return state.leftMode end
        pages.talent.getHorizonWidthScale = function() return state.pages.talent.scale end
        local function gate(id)
            return mock({
                isOpen = function() return state.gates[id] == true end,
                isActive = function() return state.gates[id] == true end,
                isVisible = function() return state.gates[id] == true end,
                handleInput = function(x, y) record(id .. ".input", x, y); return true end,
                handleTap = function() record(id .. ".tap"); return true end,
                handleDragBegin = function(x, y) record(id .. ".down", x, y); return true end,
                handleDragMove = function(x, y) record(id .. ".move", x, y); return true end,
                handleDragEnd = function(x, y) record(id .. ".up", x, y); return false end,
                handleClick = function(x, y) record(id .. ".input", x, y); return true end,
                close = function() record(id .. ".close"); state.gates[id] = false end,
            })
        end
        local tri = mock({
            isOpen = function() return state.tri end,
            handleDragBegin = function(x, y) record("tri.down", x, y); return true end,
            handleDragMove = function(x, y) record("tri.move", x, y); return true end,
            handleDragEnd = function(x, y) record("tri.up", x, y); return false end,
            handleInput = function(x, y)
                if state.gates.terminal or state.gates.sweep or state.gates.damage or state.gates.stage then
                    record("dialog.input", x, y)
                else record("business.tri.input", x, y) end
                return true
            end,
        })
        local reward, level, tutorial, ce = gate("reward"), gate("level"), gate("tutorial"), gate("ce")
        reward.currentRowTag = function() return state.row end
        reward.currentPanel = function() return state.panel end
        level.getPresentationVersion = function() return 1 end
        level.isPresentationBlocked = function() return false end
        tutorial.isInputActive = function() return true end
        tutorial.canPointerStart = function() return false end
        tutorial.handleScreenClick = function() record("tutorial.input"); return true end
        ce.handleDown = function() return state.gates.ce == true end
        ce.handleUp = function() return state.gates.ce == true end
        local characterPanel = mock({
            getTotalPower = function() return 0 end,
            isDetailOpen = function() return state.pages.character.open end,
            handleDragBegin = pages.character.handleDragBegin,
            handleDragMove = pages.character.handleDragMove,
            handleDragEnd = pages.character.handleDragEnd,
            handleInput = pages.character.handleInput,
        })
        local equipmentDetail = mock({
            isCompactCorner = function() return state.compact end,
            close = function() state.compact = false; record("equipment.close") end,
        })
        local business = function(id)
            return mock({ handleInput = function() record("business." .. id .. ".input"); return true end })
        end
        local drawProxy = setmetatable({
            drawBackSeamBar = function(_, cx, cy, sw, sh, dir, bw, bh)
                bars[#bars + 1] = { cx = cx, cy = cy, sw = sw, sh = sh, top = cy - sh * 0.5,
                    dir = dir, bw = bw, bh = bh, wx = paint.tx + cx * paint.sx,
                    wy = paint.ty + (cy - sh * 0.5 + sh * Draw.SEAMBAR_ARROW_Y) * paint.sy,
                    ws = paint.sx, hs = paint.sy }
            end,
        }, { __index = Draw })
        ---@type any
        local mods = {
            ["boot.StandaloneRT"] = RT, ["core.Viewport"] = VP, ["core.DrawUtil"] = drawProxy,
            ["ui.character.detail.CharacterDetail"] = pages.character,
            ["ui.blacksmith.BlacksmithPage"] = pages.smith,
            ["ui.loot.LootBoxPage"] = pages.loot, ["ui.loot.LootBox"] = pages.loot,
            ["ui.story.task.TaskPage"] = pages.task, ["ui.backpack.BackpackPanel"] = pages.backpack,
            ["ui.church.talent.TalentPage"] = pages.talent, ["ui.church.ChurchPage"] = pages.church,
            ["ui.tavern.TavernPage"] = pages.tavern, ["ui.market.MarketPage"] = pages.market,
            ["ui.character.panel.CharacterPanel"] = characterPanel,
            ["ui.character.equip.EquipmentDetail"] = equipmentDetail,
            ["ui.battle.tri.BattleTriPage"] = tri,
            ["ui.battle.scene.BattleScene"] = business("battle"), ["ui.town.TownScene"] = business("town"),
            ["ui.hud.BottomNav"] = { getSelectedIndex = function() return state.tab end },
            ["ui.hud.popup.RewardPopup"] = reward, ["ui.hud.popup.LevelUpPopup"] = level,
            ["systems.TutorialManager"] = tutorial, ["ui.dev.CEPanel"] = ce,
            ["core.DarkIcon"] = mock({ SHOWCASE = false }),
            ["core.BattleLayout"] = mock({ CARD_SCALE = 0.6 }),
        }
        local gatePaths = {
            ["ui.hud.popup.OfflineRewardPanel"] = "offline", ["ui.hud.popup.PlayerInfoPanel"] = "playerinfo",
            ["ui.hud.popup.UpdateNoticePopup"] = "notice", ["ui.battle.popup.TerminalConfirmDialog"] = "terminal",
            ["ui.story.gate.DarkTitleScreenGate"] = "title", ["ui.story.gate.StartScreen"] = "start",
            ["ui.story.gate.LetterIntro"] = "letter",
            ["ui.story.ScenarioDialogue"] = "scenario", ["ui.tower.TowerBattleScene"] = "tower",
            ["ui.dungeon.DungeonBattleScene"] = "dungeon", ["ui.character.hero.HeroRosterPanel"] = "roster",
            ["ui.battle.stage.SweepDialog"] = "sweep", ["ui.battle.popup.DamageStatsPanel"] = "damage",
            ["ui.battle.stage.StageSelectDialog"] = "stage",
        }
        for path, id in pairs(gatePaths) do mods[path] = gate(id) end
        -- 保留旧 intro 门禁断言，映射到现有真实开场入口；不 mock 已删 IntroCutscene。
        mods["ui.story.ScenarioDialogue"].isActive = function()
            return state.gates.scenario == true or state.gates.intro == true or state.gates.slice == true
        end
        mods["ui.story.ScenarioDialogue"].isSliceActive = function() return state.gates.slice == true end
        mods["ui.story.SamsaraRecordPanel"] = gate("record")
        ---@type any
        local realBoot = {}
        if loaded then
            for name in pairs(loaded) do if name:match("^boot%.") then loaded[name] = nil end end
        end
        -- 新 boot 模块也走真实加载；只代理 bind 以取得宿主创建的 ctx，不伪造 seamGesture。
        require = function(name)
            check(name ~= "main" and not name:match("[Ss]ave") and not name:match("[Pp]layer[Dd]ata"),
                "fixture forbids main/save require: " .. name)
            if mods[name] then return mods[name] end
            if name:match("^boot%.") then
                if realBoot[name] == nil then
                    local actual = originalRequire(name)
                    if name == "boot.StandaloneHorizonInput" then
                        realBoot[name] = setmetatable({ bind = function(ctx)
                            capture.ctx = ctx
                            return actual.bind(ctx)
                        end }, { __index = actual })
                    else realBoot[name] = actual end
                end
                return realBoot[name]
            end
            mods[name] = mock()
            return mods[name]
        end
        for key in pairs(RT) do RT[key] = nil end
        RT.vg, RT.logicalW, RT.logicalH, RT.windowW, RT.windowH = {}, 1920, 1080, 1920, 1080
        RT.dpr, RT.bootReady_, RT.preload_ = 1, true, { active = false }
        RT.DESIGN_W, RT.DESIGN_H = 1080, 2400
        VP._notes = {}
        require("boot.StandaloneHorizon")
        check(capture.ctx and capture.ctx.seamGesture and capture.ctx.seamHitAt,
            "capture real Horizon ctx.seamGesture")
        check(realBoot["boot.StandaloneHorizonInput"] ~= nil, "real HorizonInput loaded")
        check(drawProxy.seamSlideX == Draw.seamSlideX and capture.ctx.Viewport == VP,
            "real DrawUtil.seamSlideX and Viewport")
        local ctx = capture.ctx
        local gesture = ctx.seamGesture
        local button = { Button = { GetInt = function() return MOUSEB_LEFT end } }
        local rightButton = { Button = { GetInt = function() return MOUSEB_RIGHT end } }
        local function tick(dt)
            state.clock = state.clock + (dt or 0.2)
            time.elapsedTime = state.clock
        end
        local function pixel(x, y)
            return ((RT.frameOx or 0) + x * (RT.frameScale or 1)) * RT.dpr,
                ((RT.frameOy or 0) + y * (RT.frameScale or 1)) * RT.dpr
        end
        local function position(x, y) cursor.x, cursor.y = pixel(x, y) end
        local function down(x, y) position(x, y); HandleMouseButtonDownHorizon("MouseButtonDown", button) end
        local function move(x, y) position(x, y); HandleMouseMoveHorizon("MouseMove", {}) end
        local function up(x, y, dt)
            position(x, y); tick(dt); HandleMouseButtonUpHorizon("MouseButtonUp", button)
        end
        local function click(x, y) down(x, y); up(x, y) end
        local function touch(id, x, y, handler, dt)
            local px, py = pixel(x, y)
            local ix, iy = math.floor(px + 0.5), math.floor(py + 0.5)
            local data = { TouchID = { GetInt = function() return id end },
                X = { GetInt = function() return ix end }, Y = { GetInt = function() return iy end } }
            tick(dt or 0)
            handler("Touch", data)
        end
        local function render() HandleNanoVGRenderHorizon() end
        local function reset(id, triMode, width, height, dpi, scale, ox, oy)
            if gesture.hasPress() then gesture.up(-1000, -1000, true) end
            ctx.OfflineRewardOverlay.cancel()
            state.gates, state.row, state.panel, state.compact = {}, nil, nil, false
            state.tri, state.tab, state.leftMode = triMode ~= false, 3, true
            tick(2)
            for _, key in ipairs(ids) do
                state.pages[key] = { open = key == id, ot = state.clock - 10, ct = 0, od = 0.45, cd = 0.38, scale = 1 }
            end
            if id == "smith" then state.pages.backpack.open = true end
            RT.logicalW, RT.logicalH, RT.dpr = width or 1920, height or 1080, dpi or 1
            RT.frameScale, RT.frameOx, RT.frameOy = scale or 1, ox or 0, oy or 0
            RT.windowW = (RT.logicalW * RT.frameScale + RT.frameOx * 2) * RT.dpr
            RT.windowH = (RT.logicalH * RT.frameScale + RT.frameOy * 2) * RT.dpr
            RT.bootReady_, RT.preload_ = true, { active = false }
            VP._notes = {}
            events = {}
            render()
            events = {}
        end
        ---@return any
        local function expected(id)
            local ox, oy, ps = VP.layout(RT.logicalW, RT.logicalH)
            if state.tri then ox, oy, ps = 0, 0, RT.logicalH / VP.PH end
            local p = state.pages[id]
            local scale = id == "talent" and math.max(1, p.scale) or 1
            local sign = id == "character" and 1 or -1
            local edge = id == "character" and (RT.logicalW - VP.PW * ps)
                or (ox + (id == "smith" and VP.PANELS.right.bx or VP.PW * scale) * ps)
            local height = VP.PH * ps
            local width = height * Draw.SEAMBAR_ASPECT
            local slide = Draw.seamSlideX(sign, p.ot, p.ct, p.od, p.cd, 1080 * scale) * ps * VP.DS
            return { x = edge - sign * width * 0.5 + slide + sign * 2,
                y = oy + height * Draw.SEAMBAR_ARROW_Y, top = oy, sw = width, sh = height,
                edge = edge + slide, dir = sign == 1 and "right" or "left" }
        end
        ---@return any
        local function arrow(id, total)
            local target = expected(id)
            if total then check(#bars == total, "render bar count " .. id .. " actual=" .. #bars) end
            ---@type any
            local found = nil
            for _, bar in ipairs(bars) do
                if math.abs(bar.cx - target.x) < 0.00001 and bar.dir == target.dir then
                    check(not found, "one rendered bar per id " .. id)
                    found = bar
                end
            end
            check(found ~= nil, "rendered arrow geometry " .. id)
            near(found.top, target.top, "bar top " .. id)
            near(found.sw, target.sw, "bar width " .. id)
            near(found.sh, target.sh, "bar height " .. id)
            local px, py = pixel(target.x, target.y)
            near(found.wx * RT.dpr, px, "draw/pointer frame X " .. id)
            near(found.wy * RT.dpr, py, "draw/pointer frame Y " .. id)
            local hit = ctx.seamHitAt(target.x, target.y)
            check(hit and hit.id == id and hit.generation == state.pages[id].ot, "real seam hit at arrow center " .. id)
            check(math.abs(target.x - target.edge) > 2, "arrow center is not 2px page-side sliver " .. id)
            check(ctx.seamHitAt(target.x, target.top + target.sh * 0.05) == nil,
                "bar body is not arrow hit " .. id)
            return target
        end
        local function owns(label) check(gesture.hasPress(), label .. " owns seam press") end
        local function released(label) check(not gesture.hasPress(), label .. " releases seam press") end
        local function cancelled(label)
            check(closeCount() == 0, label .. " does not close")
            noBusinessTap(label)
        end
        local function recover(id, label)
            render()
            local a = arrow(id)
            events = {}
            click(a.x, a.y)
            check(count(id .. ".close") == 1 and closeCount() == 1, label .. " next normal click recovers")
            noBusinessTap(label .. " recovery")
            released(label)
        end

        for _, id in ipairs(ids) do
            reset(id)
            local a = arrow(id, 1)
            check(not gesture.up(a.x, a.y, false), "gesture Up without Down " .. id)
            up(a.x, a.y); up(a.x, a.y)
            cancelled("orphan/repeated Up " .. id)
            position(a.x, a.y)
            HandleMouseButtonDownHorizon("MouseButtonDown", rightButton)
            check(not gesture.hasPress(), "right mouse cannot arm return " .. id)
            events = {}
            down(a.x, a.y); owns(id); up(a.x, a.y)
            check(count(id .. ".close") == 1 and closeCount() == 1, "arrow center closes only owner " .. id)
            noBusinessTap("arrow " .. id); released(id)
            up(a.x, a.y)
            check(count(id .. ".close") == 1, "duplicate Up never repeats close " .. id)
            render()
            a = arrow(id, 1)
            down(a.x, a.y); owns("closing " .. id); up(a.x, a.y)
            check(count(id .. ".close") == 1, "closing bar never repeats close " .. id)
            noBusinessTap("closing " .. id)
        end

        for _, id in ipairs(ids) do
            if id ~= "character" then
                for _, owner in ipairs({ id, "character" }) do
                    reset(id)
                    state.pages.character.open = true
                    render(); events = {}
                    local a = arrow(owner, 2)
                    click(a.x, a.y)
                    check(count(owner .. ".close") == 1 and closeCount() == 1,
                        "simultaneous left/right independently closes " .. id .. "/" .. owner)
                    noBusinessTap("simultaneous " .. id)
                end
            end
        end
        reset("smith"); state.pages.loot.open, state.pages.character.open = true, true
        render(); arrow("smith", 3); arrow("loot", 3); arrow("character", 3)
        for _, id in ipairs(ids) do
            reset(id)
            local a = arrow(id, 1)
            state.compact = true
            click(a.x, a.y)
            check(count("equipment.close") == 1 and count(id .. ".close") == 1,
                "valid return dismisses compact equipment detail " .. id)
            reset(id)
            a = arrow(id, 1)
            state.compact = true
            down(a.x, a.y); move(a.x, a.y + 20); up(a.x, a.y)
            check(count("equipment.close") == 0 and state.compact, "cancelled return preserves compact detail " .. id)
            cancelled("compact cancel " .. id)
        end
        reset("smith", false, 1200, 1080)
        state.pages.backpack.open = false
        render(); events = {}
        local smithOnly = arrow("smith", 1)
        click(smithOnly.x, smithOnly.y)
        check(count("smith.close") == 1, "non-tri independent smith without backpack")
        noBusinessTap("independent smith")
        reset("backpack", false, 1200, 1080)
        state.leftMode = false
        render()
        check(#bars == 0, "non-left standalone backpack has no seam return")
        reset("talent"); state.pages.talent.scale = 1.22; render()
        local wide = arrow("talent", 1)
        click(wide.x, wide.y)
        check(count("talent.close") == 1, "wide talent uses real slide distance")

        for _, dpi in ipairs({ 1, 2, 3 }) do
            for _, frame in ipairs({ { s = 1, x = 0, y = 0 }, { s = 0.75, x = 37, y = 19 } }) do
                for _, id in ipairs(ids) do
                    reset(id, true, 1920, 1080, dpi, frame.s, frame.x, frame.y)
                    local a = arrow(id, 1)
                    click(a.x, a.y)
                    check(count(id .. ".close") == 1, "tri DPR/frame " .. id .. "/" .. dpi .. "/" .. frame.s)
                    noBusinessTap("DPR/frame " .. id)
                end
                for _, id in ipairs({ "backpack", "smith" }) do
                    reset(id, false, 1200, 1080, dpi, frame.s, frame.x, frame.y)
                    local a = arrow(id, 1)
                    check(H_oy > 0 and H_s < 1, "narrow non-tri H_oy letterbox " .. id)
                    check(ctx.seamHitAt(a.x, a.y - H_oy) == nil, "letterbox Y must include H_oy " .. id)
                    click(a.x, a.y)
                    check(count(id .. ".close") == 1, "non-tri standalone DPR/frame " .. id .. "/" .. dpi)
                    noBusinessTap("non-tri " .. id)
                    if id == "smith" then check(count("backpack.close") == 0, "smith owns combined return") end
                end
            end
        end

        for _, id in ipairs(ids) do
            reset(id, true, 1920, 1080, 3, 0.8, 23, 11)
            local a = arrow(id, 1)
            cursor.x, cursor.y = -10000, -10000
            touch(11, a.x, a.y, HandleTouchEndHorizon)
            cancelled("orphan touch " .. id)
            touch(11, a.x, a.y, HandleTouchBeginHorizon); owns("touch " .. id)
            touch(12, a.x + 100, a.y, HandleTouchBeginHorizon)
            touch(12, a.x + 100, a.y, HandleTouchMoveHorizon)
            touch(12, a.x + 100, a.y, HandleTouchEndHorizon)
            check(closeCount() == 0, "secondary touch cannot release primary " .. id)
            touch(11, a.x, a.y, HandleTouchEndHorizon)
            check(count(id .. ".close") == 1 and closeCount() == 1, "touch arrow center " .. id)
            released("touch " .. id); noBusinessTap("touch " .. id)
            touch(11, a.x, a.y, HandleTouchEndHorizon)
            check(count(id .. ".close") == 1, "duplicate touch End " .. id)
        end
        for _, id in ipairs({ "backpack", "smith" }) do
            reset(id, false, 1200, 1080, 2, 0.75, 37, 19)
            local a = arrow(id, 1)
            touch(11, a.x, a.y, HandleTouchBeginHorizon)
            touch(11, a.x, a.y, HandleTouchEndHorizon)
            check(count(id .. ".close") == 1, "non-tri letterbox touch " .. id)
            noBusinessTap("non-tri touch " .. id)
        end

        for _, useTouch in ipairs({ false, true }) do
            reset("church")
            local a = arrow("church", 1)
            local startX = RT.logicalW * 0.5
            check(ctx.seamHitAt(startX, a.y) == nil, "old tri drag starts outside seam")
            if useTouch then
                touch(11, startX, a.y, HandleTouchBeginHorizon)
                touch(11, a.x, a.y, HandleTouchMoveHorizon)
                touch(11, a.x, a.y, HandleTouchEndHorizon)
            else down(startX, a.y); move(a.x, a.y); up(a.x, a.y) end
            check(count("tri.down") == 1 and count("tri.up") >= 1, "old tri source released " .. tostring(useTouch))
            cancelled("old tri drag to seam " .. tostring(useTouch))
            recover("church", "old tri drag")
        end
        for _, id in ipairs(ids) do
            for _, mode in ipairs({ "out-return", "same-bar-large", "touch-out-return", "touch-same-bar-large" }) do
                reset(id)
                local a = arrow(id, 1)
                local useTouch = mode:match("^touch") ~= nil
                local out = mode:match("out%-return") ~= nil
                local mx, my = out and (a.x + a.sw + 10) or a.x, out and a.y or (a.y + 20)
                if not out then check(ctx.seamHitAt(mx, my).id == id, "large move stays on same arrow " .. id) end
                if useTouch then
                    touch(11, a.x, a.y, HandleTouchBeginHorizon)
                    touch(11, mx, my, HandleTouchMoveHorizon)
                    touch(11, a.x, a.y, HandleTouchMoveHorizon)
                    touch(11, a.x, a.y, HandleTouchEndHorizon)
                else
                    down(a.x, a.y); move(mx, my); move(a.x, a.y); up(a.x, a.y)
                end
                cancelled(mode .. " " .. id); released(mode)
                recover(id, mode)
            end
            reset(id)
            local a = arrow(id, 1)
            down(a.x, a.y); move(a.x + 7, a.y + 7); up(a.x + 7, a.y + 7)
            check(count(id .. ".close") == 1, "small drift below tap threshold " .. id)
        end

        local blockers = { "reward", "terminal", "offline", "level", "playerinfo", "notice", "title", "start",
            "letter", "intro", "scenario", "tutorial", "tower", "dungeon", "ce", "roster", "sweep", "damage", "stage", "record", "slice" }
        for _, blocker in ipairs(blockers) do
            reset("church")
            state.pages.character.open = true
            render()
            local a, b = arrow("church", 2), arrow("character", 2)
            state.gates[blocker] = true
            render(); events = {}
            check(#bars == 0 and ctx.seamHitAt(a.x, a.y) == nil and ctx.seamHitAt(b.x, b.y) == nil,
                "full-window blocker hides both returns " .. blocker)
            click(a.x, a.y); click(b.x, b.y)
            check(closeCount() == 0, "full-window blocker cannot close either sidebar " .. blocker)
            check(not gesture.hasPress(), "blocked click cannot arm seam " .. blocker)
            for _, path in ipairs({ "move", "render", "up" }) do
                reset("church")
                a = arrow("church", 1)
                down(a.x, a.y); owns("new modal " .. blocker)
                state.gates[blocker] = true
                if path == "move" then
                    move(a.x, a.y)
                    state.gates[blocker] = false
                elseif path == "render" then
                    render()
                    state.gates[blocker] = false
                end
                up(a.x, a.y)
                cancelled("press/new modal " .. blocker .. "/" .. path)
                released("modal mouse " .. blocker)
                state.gates[blocker] = false
                recover("church", "modal " .. blocker .. "/" .. path)
            end
            reset("church", true, 1920, 1080, 2, 0.8, 23, 11)
            a = arrow("church", 1)
            touch(11, a.x, a.y, HandleTouchBeginHorizon)
            state.gates[blocker] = true
            touch(11, a.x, a.y, HandleTouchMoveHorizon)
            state.gates[blocker] = false
            touch(11, a.x, a.y, HandleTouchEndHorizon)
            cancelled("touch/modal Move then dismiss " .. blocker)
            recover("church", "touch/modal " .. blocker)
        end
        reset("church"); local a = arrow("church", 1)
        down(a.x, a.y); RT.bootReady_ = false; render(); RT.bootReady_ = true; up(a.x, a.y)
        cancelled("boot readiness changes during press"); recover("church", "boot readiness")
        for _, panelId in ipairs({ "left", "center", "right" }) do
            reset("church")
            state.pages.character.open = true
            state.gates.reward, state.row, state.panel = true, 1, panelId
            render(); events = {}
            a = arrow("church", 2)
            click(a.x, a.y)
            check(count("church.close") == 1, "row reward allows sidebar return panel=" .. panelId)
            noBusinessTap("row reward")
        end

        local mutations = {
            { id = "generation", apply = function() state.pages.smith.ot = state.clock - 1 end },
            { id = "logicalW/windowW", apply = function() RT.logicalW, RT.windowW = RT.logicalW + 8, RT.windowW + 8 end },
            { id = "logicalH/windowH", apply = function() RT.logicalH, RT.windowH = RT.logicalH + 1, RT.windowH + 1 end },
            { id = "windowW-only", apply = function() RT.windowW = RT.windowW + 8 end },
            { id = "windowH-only", apply = function() RT.windowH = RT.windowH + 8 end },
            { id = "dpr", apply = function() RT.dpr = 2 end },
            { id = "frameScale", apply = function() RT.frameScale = 0.9 end },
            { id = "frameOx", apply = function() RT.frameOx = 12 end },
            { id = "frameOy", apply = function() RT.frameOy = 12 end },
            { id = "tri-mode", apply = function() state.tri = not state.tri end },
        }
        for _, mutation in ipairs(mutations) do
            for _, useTouch in ipairs({ false, true }) do
                for _, latch in ipairs({ false, true }) do
                    reset("smith", true, 1458, 1080)
                    a = arrow("smith", 1)
                    local before = { ot = state.pages.smith.ot, lw = RT.logicalW, lh = RT.logicalH, ww = RT.windowW,
                        wh = RT.windowH, dpi = RT.dpr, scale = RT.frameScale, ox = RT.frameOx, oy = RT.frameOy, tri = state.tri }
                    if useTouch then touch(11, a.x, a.y, HandleTouchBeginHorizon) else down(a.x, a.y) end
                    mutation.apply()
                    render()
                    if latch then
                        if useTouch then touch(11, a.x, a.y, HandleTouchMoveHorizon) else move(a.x, a.y) end
                        state.pages.smith.ot = before.ot
                        RT.logicalW, RT.logicalH, RT.windowW, RT.windowH = before.lw, before.lh, before.ww, before.wh
                        RT.dpr, RT.frameScale, RT.frameOx, RT.frameOy = before.dpi, before.scale, before.ox, before.oy
                        state.tri = before.tri
                        render()
                    end
                    if useTouch then touch(11, a.x, a.y, HandleTouchEndHorizon) else up(a.x, a.y) end
                    cancelled("press mutation " .. mutation.id .. "/latch=" .. tostring(latch) .. "/touch=" .. tostring(useTouch))
                    released(mutation.id)
                    recover("smith", mutation.id)
                end
            end
        end
        reset("smith", false, 1458, 1080); a = arrow("smith", 1)
        down(a.x, a.y); state.tri = true; render(); up(a.x, a.y)
        cancelled("non-tri to tri unchanged seam geometry"); recover("smith", "non-tri to tri")
        reset("church"); a = arrow("church", 1)
        down(a.x, a.y); state.pages.church.open, state.pages.task.open = false, true
        render(); up(a.x, a.y)
        cancelled("different page id at identical arrow"); recover("task", "page id")

        for _, id in ipairs(ids) do
            reset(id)
            state.pages[id].ot = state.clock - 0.22
            render(); events = {}
            a = arrow(id, 1)
            down(a.x, a.y); up(a.x, a.y, 0)
            check(count(id .. ".close") == 1, "same-frame opening arrow click " .. id)
            noBusinessTap("opening " .. id)
            reset(id)
            state.pages[id].ot = state.clock - 0.22
            render(); events = {}
            a = arrow(id, 1)
            down(a.x, a.y); tick(0.16); render(); up(a.x, a.y, 0)
            check(closeCount() <= 1 and count(id .. ".close") == closeCount(),
                "moving same arrow stationary click closes owner or consumes " .. id)
            released("moving arrow " .. id); noBusinessTap("moving arrow " .. id)
            up(a.x, a.y, 0)
            check(closeCount() <= 1, "animated duplicate Up no repeat " .. id)
            reset(id)
            state.pages[id].ct = state.clock - 0.08
            render(); events = {}
            a = arrow(id, 1)
            down(a.x, a.y); up(a.x, a.y, 0)
            cancelled("already closing " .. id); released("already closing " .. id)
        end
        check(assertions > 1000, "ALL PASS requires full matrix assertion count")
    end)
    require = originalRequire
    if saved.viewport then saved.viewport._notes = saved.notes end
    if saved.rt then
        for key in pairs(saved.rt) do saved.rt[key] = nil end
        for key, value in pairs(saved.rtValues) do saved.rt[key] = value end
    end
    if loaded then
        local added = {}
        for key in pairs(loaded) do if oldLoaded[key] == nil then added[#added + 1] = key end end
        for _, key in ipairs(added) do loaded[key] = nil end
        for key, value in pairs(oldLoaded) do loaded[key] = value end
    end
    local added = {}
    for key in pairs(_G) do if oldGlobals[key] == nil then added[#added + 1] = key end end
    for _, key in ipairs(added) do _G[key] = nil end
    for key, value in pairs(oldGlobals) do _G[key] = value end
    if ok then
        print("[seam_back_horizon_test] ALL PASS: " .. assertions .. " assertions")
    else
        local message = "[seam_back_horizon_test] [FAIL] " .. tostring(err) .. " (" .. assertions .. " assertions)"
        print(message)
        log:Write(LOG_ERROR, message)
    end
    engine:Exit()
end
