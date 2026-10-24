-- 输入热点回归：真实路由/手势/坐标模块，页面叶子为可观测内存替身。
-- 不运行 main，不读玩家档；可选 INPUT_MOVE_BASELINE 仅由外部 source host 注入冻结旧源码。
-- 原生入口也独立断言每个 Move/leave/延时/捕获；不把 CPU 结果当设备帧率验收。
function Start()
    local nativeCache = cache
    local baseline = rawget(_G, "INPUT_MOVE_BASELINE") --[[@as table<string, string>?]]
    local assertions, cases = 0, 0
    local function check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end
    local allowed = {
        ["boot.StandaloneHorizonInput"] = true, ["boot.StandaloneHorizonWheel"] = true,
        ["boot.RewardGesture"] = true,
        ["boot.ArtifactGesture"] = true, ["boot.SeamBackGesture"] = true,
        ["boot.DecomposeMarqueeGesture"] = true, ["boot.TerminalInput"] = true,
        ["core.Viewport"] = true, ["ui.tower.TowerLayout"] = true,
        ["ui.character.hero.AwakeningArtwork"] = true,
    }
    local sources = {} ---@type table<string, string>
    local function source(name)
        if sources[name] then return sources[name] end
        assert(allowed[name], "undeclared source: " .. tostring(name))
        local file = assert(nativeCache:GetFile(name:gsub("%.", "/") .. ".lua"))
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        sources[name] = table.concat(lines, "\n")
        return sources[name]
    end
    ---@param old boolean
    ---@return any
    local function fixture(old)
        local env = setmetatable({}, { __index = _G })
        local loaded, mods = {}, {}
        local events, counts = {}, {}
        local s = { tri = true, tab = 3, gates = {}, cursor = { x = 0, y = 0 },
            width = 1920, height = 1080, dpr = 1, clock = { elapsedTime = 100 },
            overlay = false, armed = false, dragCard = false, record = true,
            hovered = {}, tips = {}, since = {}, marquee = false, tutorialEntry = false,
            rewardPanel = false, rewardLarge = false, version = 1, seam = false }
        local function count(key) counts[key] = (counts[key] or 0) + 1 end
        local function record(name, ...)
            if not s.record then return end
            local args = { name, string.format("%.6f", s.clock.elapsedTime) }
            for i = 1, select("#", ...) do args[#args + 1] = tostring(select(i, ...)) end
            events[#events + 1] = table.concat(args, "|")
        end
        local function noop() return false end
        local function mock(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local function flag(key)
            count("blockerQueries")
            return s.gates[key] == true
        end
        local function hover(name, x, y, delay)
            record(name .. ".hover", x, y)
            count("hover")
            local key = x >= 0 and y >= 0 and math.floor(x / 100) .. ":" .. math.floor(y / 100) or nil
            if s.hovered[name] ~= key then
                s.hovered[name], s.since[name], s.tips[name] = key, s.clock.elapsedTime, false
                record(name .. ".leave", key or "none")
            elseif key and s.clock.elapsedTime - (s.since[name] or 0) >= (delay or 0.3) then
                s.tips[name] = true
                record(name .. ".tip", key)
            end
        end
        local function page(name)
            return mock({
                isOpen = function() return flag(name) end,
                isActive = function() return flag(name) end,
                handleHover = function(x, y) hover(name, x, y, name == "loot" and 0.5 or 0.3) end,
                handleDragBegin = function(x, y) record(name .. ".down", x, y); return true end,
                handleDragMove = function(x, y) record(name .. ".move", x, y); return true end,
                handleDragEnd = function(x, y) record(name .. ".up", x, y); return true end,
                handleInput = function(x, y) record(name .. ".tap", x, y); return true end,
                handleScroll = function(w, x, y) record(name .. ".wheel", w, x, y); return true end,
                handleRightClick = function(x, y) record(name .. ".right", x, y); return true end,
                getPresentationVersion = function() return s.version end,
                getPresentationKey = function() return tostring(s.version) end,
            })
        end
        local paths = {
            ["ui.hud.TopBar"] = "top", ["ui.battle.scene.BattleScene"] = "battle",
            ["ui.character.panel.CharacterPanel"] = "character", ["ui.dev.CEPanel"] = "ce",
            ["ui.character.hero.HeroRosterPanel"] = "roster", ["ui.hud.popup.RewardPopup"] = "reward",
            ["ui.town.TownScene"] = "town", ["ui.blacksmith.BlacksmithPage"] = "smith",
            ["ui.church.ChurchPage"] = "church", ["ui.church.talent.TalentPage"] = "talent",
            ["ui.tavern.TavernPage"] = "tavern", ["ui.market.MarketPage"] = "market",
            ["ui.dungeon.DungeonBattleScene"] = "dungeon", ["ui.tower.TowerBattleScene"] = "tower",
            ["ui.dungeon.DungeonPage"] = "dungeonpage", ["ui.backpack.BackpackPanel"] = "backpack",
            ["ui.loot.LootBox"] = "lootdrag", ["ui.loot.LootBoxPage"] = "loot",
            ["ui.story.task.TaskPage"] = "task", ["ui.hud.popup.LevelUpPopup"] = "level",
            ["ui.hud.popup.OfflineRewardPanel"] = "offline", ["ui.hud.popup.UpdateNoticePopup"] = "notice",
            ["ui.hud.popup.PlayerInfoPanel"] = "player", ["ui.story.gate.StartScreen"] = "start",
            ["ui.story.gate.DarkTitleScreenGate"] = "title", ["ui.battle.tri.BattleTriPage"] = "tri",
            ["ui.battle.stage.SweepDialog"] = "sweep", ["ui.battle.popup.DamageStatsPanel"] = "damage",
            ["ui.battle.stage.StageSelectDialog"] = "stage", ["ui.battle.popup.TerminalConfirmDialog"] = "terminal",
            ["ui.story.gate.IntroCutscene"] = "intro", ["ui.story.gate.LetterIntro"] = "letter",
            ["ui.character.detail.CharacterDetail"] = "detail", ["ui.character.equip.EquipmentBag"] = "bag",
            ["ui.story.ScenarioDialogue"] = "story", ["systems.TutorialManager"] = "tutorial",
        }
        for path, name in pairs(paths) do mods[path] = page(name) end
        local function mod(path) return mods[path] end
        mods["ui.hud.BottomNav"] = { getSelectedIndex = function() return s.tab end }
        mod("ui.battle.tri.BattleTriPage").isOpen = function() return s.tri end
        mod("ui.battle.tri.BattleTriPage").handleScroll = function(w, x, y)
            record("tri.wheel-probe", w, x, y); return false
        end
        local reward = mod("ui.hud.popup.RewardPopup")
        reward.blocksPageInput = function()
            -- 真实RewardPopup会同步行内可见性：查询不是纯读，不能随闭图快路省略。
            if s.gates.rewardEffects then record("reward.visibility-sync") end
            return flag("reward")
        end
        reward.isLarge = function() return s.rewardLarge end
        reward.currentPanel = function() return s.rewardPanel or nil end
        reward.cancelDrag = function() record("reward.cancel") end
        reward.handleLargePointer = function(phase, x, y, w, h, tap)
            record("reward.large", phase, x, y, w, h, tap)
        end
        reward.handleLargeScroll = noop
        local character = mod("ui.character.panel.CharacterPanel")
        character.isDraggingCard = function() return s.dragCard end
        local backpack = mod("ui.backpack.BackpackPanel")
        backpack.isLeftMode = function() return true end
        backpack.handleMarqueeBegin = function(x, y)
            if not s.marquee then return false end
            record("marquee.begin", x, y); return true
        end
        backpack.canMarquee = function() return s.marquee end
        backpack.isMarqueeActive = function() return s.marquee end
        backpack.handleMarqueeMove = function(x, y) record("marquee.move", x, y) end
        backpack.handleMarqueeEnd = function(x, y) record("marquee.end", x, y); s.marquee = false end
        backpack.cancelMarquee = function() record("marquee.cancel"); s.marquee = false end
        local church = mod("ui.church.ChurchPage")
        church.isArtifactInputActive = function() return s.gates.church == true end
        mods["ui.church.ChurchArtifactPanel"] = mock({
            handleHover = function(x, y) hover("artifact", x, y) end,
            handleDragBegin = function(x, y) record("artifact.down", x, y) end,
            handleDragMove = function(x, y) record("artifact.move", x, y) end,
            handleDragEnd = function(x, y) record("artifact.up", x, y); return true end,
            cancelPointer = function() record("artifact.cancel") end,
        })
        mods["ui.character.hero.ArtifactDetailPanel"] = mock({
            closeImmediate = function() record("artifact.close") end,
        })
        local cross = mock({
            isArmed = function() return s.armed end,
            move = function(x, y) record("cross.move", x, y); return true end,
            finish = function(x, y) record("cross.end", x, y); s.armed = false; return true end,
            cancel = function() record("cross.cancel"); s.armed = false end,
            getSource = function() return "backpack" end,
        })
        mods["ui.character.EquipCrossDrag"] = cross
        local curation = mock({
            isOpen = function() return s.gates.curation == true end,
            hasPress = function() return false end,
            bindHost = function() end,
            pointer = function(kind, button, x, y, id)
                record("curation", kind, button, x, y, id); return true
            end,
        })
        mods["ui.loot.InventoryCurationDialog"] = curation
        local detail = mock({ isCompactCorner = noop, isPinned = noop })
        mods["ui.character.equip.EquipmentDetail"] = detail
        local tutorial = mod("systems.TutorialManager")
        tutorial.isInputActive = function() return s.gates.tutorial == true end
        tutorial.canPointerStart = function() return true end
        tutorial.beginDetailEntryPress = function() return s.tutorialEntry and {} or nil end
        tutorial.isDetailEntryPressValid = function(p) return not p.invalid end
        tutorial.cancelDetailEntryPress = function() record("tutorial.cancel") end
        tutorial.handleScreenClick = function() record("tutorial.tap"); return true end
        mods["runtime.LocalActionBridge"] = { isSweepPending = function() return s.gates.pending == true end }
        env.input = {
            GetMousePosition = function() count("pointerReads"); return s.cursor end,
            GetKeyDown = noop,
        }
        env.time = s.clock
        env.require = function(name)
            if loaded[name] then return loaded[name] end
            if allowed[name] then
                local text = old and baseline and baseline[name] or source(name)
                local value = assert(load(text, "@" .. name, "t", env))()
                loaded[name] = value
                return value
            end
            if not mods[name] then mods[name] = mock() end
            return mods[name]
        end
        env.H_ox, env.H_oy, env.H_s = 231, 0, 1
        mod("ui.tower.TowerBattleScene").getLayout = function(w, h)
            return env.require("ui.tower.TowerLayout").compute(w, h)
        end
        mod("ui.tower.TowerBattleScene").handleClick = function(x, y) record("tower.tap", x, y) end
        local vp = env.require("core.Viewport")
        for _, id in ipairs({ "left", "center", "right" }) do vp.note(id, 231, 0, 1) end
        local rt = { frameScale = 1, frameOx = 0, frameOy = 0,
            logicalW = 1920, logicalH = 1080, dpr = 1 }
        local overlay = mock({
            toDesign = function(x, y) return x, y end,
            handleDown = function(x, y, b) record("offline.down", x, y, b) end,
            handleMove = function(x, y) record("offline.move", x, y) end,
            handleUp = function(x, y, b) record("offline.up", x, y, b) end,
            handleWheel = function(w, x, y)
                if not s.gates.offline then return false end
                record("offline.wheel", w, x, y); return true
            end,
        })
        local ctx = {
            vg = function() return false end, logicalW = function() return s.width end,
            logicalH = function() return s.height end,
            windowW = function() return s.width end, windowH = function() return s.height end,
            dpr = function() count("dprReads"); return s.dpr end,
            bootReady_ = function() return true end, DESIGN_W = 1080, DESIGN_H = 2400,
            toDesign = function(x, y)
                count("conversions")
                return (x - rt.frameOx) / rt.frameScale, (y - rt.frameOy) / rt.frameScale
            end,
            talentPageUsesWideLayout = noop, syncTalentPageLayout = noop, talentPageRightEdge = noop,
            equipOverlayDesign = function(x, y)
                if s.overlay and x >= 100 and x <= 200 then return x, y, detail end
            end,
            seamHitAt = function(x, y)
                if s.seam and x >= 480 and x <= 490 then
                    return { key = "test", openedAt = 1, close = function() record("seam.close") end }
                end
            end,
            seamInputBlocked = noop, RT = rt, Viewport = vp, OfflineRewardOverlay = overlay,
        }
        env.require("boot.StandaloneHorizonInput").bind(ctx)
        local f = { state = s, rt = rt, env = env, events = events, counts = counts,
            artwork = loaded["ui.character.hero.AwakeningArtwork"], ctx = ctx }
        function f.position(x, y)
            s.cursor.x = (x * rt.frameScale + rt.frameOx) * s.dpr
            s.cursor.y = (y * rt.frameScale + rt.frameOy) * s.dpr
        end
        function f.event(kind, x, y, button)
            f.position(x, y)
            local b = button or MOUSEB_LEFT
            local data = { Button = { GetInt = function() return b end }, Wheel = { GetInt = function() return 1 end } }
            env["HandleMouse" .. kind .. "Horizon"]("Mouse" .. kind, data)
        end
        function f.move(x, y) f.event("Move", x, y) end
        function f.down(x, y, b) f.event("ButtonDown", x, y, b) end
        function f.up(x, y, b) f.event("ButtonUp", x, y, b) end
        function f.tick(dt)
            s.clock.elapsedTime = s.clock.elapsedTime + (dt or 0.016)
            env.HandleEquipmentHoverTickHorizon()
        end
        function f.touch(kind, x, y, id)
            local data = {}
            for key, value in pairs({ X = (x * rt.frameScale + rt.frameOx) * s.dpr,
                Y = (y * rt.frameScale + rt.frameOy) * s.dpr, TouchID = id }) do
                data[key] = { GetInt = function() return value end }
            end
            env["HandleTouch" .. kind .. "Horizon"]("Touch" .. kind, data)
        end
        function f.n(needle)
            local n = 0
            for _, value in ipairs(events) do if value:sub(1, #needle + 1) == needle .. "|" then n = n + 1 end end
            return n
        end
        function f.clear()
            for i = #events, 1, -1 do events[i] = nil end
            for key in pairs(counts) do counts[key] = nil end
        end
        return f
    end
    local function compare(label, fn)
        cases = cases + 1
        local candidate = fixture(false)
        fn(candidate)
        if baseline then
            local old = fixture(true)
            fn(old)
            check(#old.events == #candidate.events, label .. " trace length " .. #old.events .. "/" .. #candidate.events)
            for i = 1, #old.events do check(old.events[i] == candidate.events[i], label .. " trace#" .. i
                .. " old=" .. old.events[i] .. " new=" .. tostring(candidate.events[i])) end
        end
        print("[PASS] input_move_performance_test " .. label .. " events=" .. #candidate.events)
    end
    local ok, why = pcall(function()
        compare("101-event burst preserves hover and leave", function(f)
            f.state.gates.backpack, f.state.gates.market, f.state.gates.bag = true, true, true
            for i = 1, 101 do f.move(120 + i % 70, 480) end
            check(f.n("backpack.hover") == 101 and f.n("character.hover") == 101,
                "every business hover/leave survives burst")
            check((f.counts.conversions or 0) >= 202, "each sample converts immediately without deferral")
            f.move(1800, 480)
            check(f.state.hovered.backpack == nil, "cross-panel leave is immediate")
            f.move(100, 480)
            check(f.state.hovered.backpack ~= nil, "reentry is immediate")
        end)
        compare("stationary and repeated move timers", function(f)
            f.state.gates.backpack = true
            f.move(130, 480)
            f.tick(0.299)
            check(not f.state.tips.backpack, "not before original hover threshold")
            f.tick(0.002)
            check(f.state.tips.backpack, "stationary tick advances hover timer")
            f.state.tips.backpack = false
            f.move(240, 480)
            f.state.clock.elapsedTime = f.state.clock.elapsedTime + 0.301
            f.move(240, 480)
            check(f.state.tips.backpack, "same-coordinate Move still advances timer")
            f.state.overlay = true
            local before = f.n("backpack.hover")
            f.move(130, 480)
            check(f.n("backpack.hover") == before, "floating detail retains candidate")
            f.state.overlay = false
            f.move(1800, 480)
            check(not f.state.tips.backpack and f.state.hovered.backpack == nil, "leave clears candidate")
        end)
        compare("loot half-second delay and every crossing", function(f)
            f.state.gates.loot = true
            f.move(130, 480)
            f.state.clock.elapsedTime = f.state.clock.elapsedTime + 0.499
            f.move(130, 480)
            check(not f.state.tips.loot, "loot not early")
            f.state.clock.elapsedTime = f.state.clock.elapsedTime + 0.002
            f.move(130, 480)
            check(f.state.tips.loot, "loot repeated move still matures")
            for i = 1, 12 do f.move(1800, 480); f.move(130, 480) end
            check(f.n("loot.hover") == 27, "all intermediate leave/reentry calls preserved")
        end)
        for _, tri in ipairs({ true, false }) do
            for _, dpi in ipairs({ 1, 2, 3 }) do
                compare("drag/touch/order tri=" .. tostring(tri) .. " dpr=" .. dpi, function(f)
                    f.state.tri, f.state.dpr, f.rt.dpr = tri, dpi, dpi
                    f.rt.frameScale, f.rt.frameOx, f.rt.frameOy = 0.8, 17, 23
                    f.state.gates.backpack = true
                    f.down(300, 480)
                    for i = 1, 101 do f.move(300, 480 + i % 37) end
                    check(f.n("backpack.move") == 101, "all drag samples preserved")
                    f.up(300, 700)
                    check(f.n("backpack.tap") == 0, "drag not converted into tap")
                    f.state.clock.elapsedTime = f.state.clock.elapsedTime + 1
                    f.down(300, 480); f.up(300, 480)
                    check(f.n("backpack.tap") == 1, "next normal tap not lost")
                    f.touch("Begin", 300, 480, 7)
                    f.touch("Move", 300, 510, 8)
                    local before = f.n("backpack.move")
                    for i = 1, 31 do f.touch("Move", 300, 480 + i, 7) end
                    check(f.n("backpack.move") == before + 31, "primary touch trajectory preserved, secondary ignored")
                    f.touch("End", 300, 540, 8)
                    f.touch("End", 300, 540, 7)
                    f.down(1800, 400)
                    f.up(300, 400)
                    check(f.n("backpack.tap") == 1, "cross-panel release cannot tap")
                    f.event("Wheel", 300, 400)
                end)
            end
        end
        compare("tower every move and transient cancellation", function(f)
            f.state.gates.tower = true
            f.down(800, 400)
            for i = 1, 101 do f.move(800, 400 + i % 11) end
            check(f.n("tower.move") == 101, "tower keeps every drag sample")
            f.up(800, 450)
            check(f.n("tower.tap") == 0, "tower drag not a tap")
            f.state.clock.elapsedTime = f.state.clock.elapsedTime + 1
            f.down(800, 400)
            f.rt.frameScale = 0.9
            f.move(800, 400)
            f.rt.frameScale = 1
            f.up(800, 400)
            check(f.n("tower.tap") == 0, "temporary frame change permanently invalidates old press")
            f.state.clock.elapsedTime = f.state.clock.elapsedTime + 1
            f.down(800, 400); f.up(800, 400)
            check(f.n("tower.tap") == 1, "fresh tower tap works")
        end)
        compare("armed cross-drag every point and final release", function(f)
            f.state.armed = true
            for i = 1, 101 do f.move(100 + i, 480) end
            check(f.n("cross.move") == 101, "armed drag cannot be coalesced")
            f.up(1700, 800)
            check(f.n("cross.end") == 1 and not f.state.armed, "release exactly once")
        end)
        compare("seam captured out-and-back cancels tap", function(f)
            f.state.seam = true
            f.down(485, 480); f.move(700, 480); f.move(485, 480); f.up(485, 480)
            check(f.n("seam.close") == 0, "excursion must not be lost")
            f.state.clock.elapsedTime = f.state.clock.elapsedTime + 1
            f.down(485, 480); f.up(485, 480)
            check(f.n("seam.close") == 1, "new seam tap still works")
        end)
        compare("marquee captures right mouse trajectory", function(f)
            f.state.gates.backpack, f.state.marquee = true, true
            f.down(100, 400, MOUSEB_RIGHT)
            for i = 1, 101 do f.move(100 + i, 400 + i) end
            check(f.n("marquee.move") == 101, "all marquee points")
            f.up(260, 560, MOUSEB_RIGHT)
            check(f.n("marquee.end") == 1, "right release captured")
        end)
        compare("artifact press and blocked cancellation", function(f)
            f.state.gates.church = true
            f.down(100, 400)
            for i = 1, 51 do f.move(100 + i, 400) end
            check(f.n("artifact.move") == 51, "artifact trajectory intact")
            f.state.gates.notice = true
            f.move(1800, 400)
            f.up(1800, 400)
            check(f.n("church.tap") == 0, "blocked artifact release not business click")
        end)
        compare("large reward begin/move/end sequence", function(f)
            f.state.rewardLarge = true
            f.down(800, 400)
            for i = 1, 101 do f.move(800, 400 + i) end
            f.up(800, 600)
            check(f.n("reward.large") == 103, "large reward keeps every move")
            f.state.rewardLarge = false
            f.tick()
        end)
        for _, gate in ipairs({ "notice", "title", "letter", "intro", "story", "offline", "level",
            "player", "terminal", "stage", "sweep", "damage", "curation", "pending" }) do
            compare("modal " .. gate, function(f)
                f.state.gates.backpack = true
                f.down(130, 400)
                f.state.gates[gate] = true
                for i = 1, 17 do f.move(130, 400 + i) end
                f.touch("Begin", 130, 400, 1)
                f.touch("Move", 130, 440, 1)
                f.touch("End", 130, 440, 1)
                f.up(130, 440)
                f.event("Wheel", 130, 440)
                f.tick()
            end)
        end
        compare("tutorial detail-entry excursion and frame invalidation", function(f)
            f.state.gates.tutorial, f.state.tutorialEntry = true, true
            f.down(1800, 400); f.move(1800, 460); f.move(1800, 400)
            f.rt.frameOx = 18
            f.up(1800, 400)
            check(f.n("character.tap") == 0, "tutorial invalid press cannot be revived")
        end)
        compare("artwork open residual press blocked invalid validate", function(f)
            local a = f.artwork
            local valid, validates = true, 0
            check(a.open(1, 1, 600, 900, function() validates = validates + 1; return valid end), "artwork opens")
            f.down(800, 400)
            f.move(850, 450); f.move(800, 400)
            f.up(800, 400)
            check(a.isOpen(), "out-and-back excursion cancels close tap")
            f.state.gates.notice = true
            f.down(800, 400); f.move(800, 450)
            valid = false
            f.move(800, 450)
            f.up(800, 450)
            f.state.gates.notice = false
            check(not a.isOpen() and not a.hasPress(), "invalid validation closes state and releases residual press")
            check(validates > 0, "real validation path executed")
            check(a.open(1, 1, 600, 900, function() return true end), "artwork reopens")
            f.touch("Begin", 800, 400, 1)
            a.close()
            check(a.hasPress(), "explicit close retains captured press")
            f.touch("Move", 850, 450, 1)
            f.touch("End", 850, 450, 1)
            check(not a.hasPress() and f.n("character.tap") == 0, "residual touch release never falls through")
        end)
        compare("closed artwork retains reward visibility side effects", function(f)
            f.state.gates.rewardEffects = true
            for i = 1, 101 do f.move(800, 480) end
            check(f.n("reward.visibility-sync") >= 101, "closed artwork still executes effectful blocker")
            f.tick()
        end)
        -- blocked包含奖励同步，完全关闭也保持调用；state/press存在时仍在validate之前。
        do
            local f = fixture(false)
            local a, order = f.artwork, {}
            local pointer = a.bindInput({ runtime = f.rt,
                blocked = function() order[#order + 1] = "blocked"; return false end,
                position = function() return 1, 1 end, source = function() return "mouse" end,
                cancelUnderlyingPress = function() order[#order + 1] = "cancel" end })
            for i = 1, 101 do check(not pointer("move", MOUSEB_LEFT), "closed artwork does not consume move") end
            check(#order == 101, "closed artwork preserves host blocker side effects")
            a.open(1, 1, 600, 900, function() order[#order + 1] = "validate"; return true end)
            order = {}
            pointer("move", MOUSEB_LEFT)
            check(order[1] == "blocked" and order[2] == "validate", "open artwork original blocker/validate order")
        end
        if baseline then
            local old, new = fixture(true), fixture(false)
            local function burst(f, rounds)
                f.state.record = false
                for r = 1, rounds do
                    for i = 1, 101 do f.move(800 + i % 17, 480) end
                end
            end
            burst(old, 5); burst(new, 5)
            old.clear(); new.clear()
            local t = os.clock(); burst(old, 100); local oldCPU = os.clock() - t
            t = os.clock(); burst(new, 100); local newCPU = os.clock() - t
            check(old.counts.hover == new.counts.hover, "benchmark business hover calls identical")
            check(new.counts.pointerReads == old.counts.pointerReads * 2 / 3, "three pointer reads become two")
            check(new.counts.conversions == old.counts.conversions * 2 / 3, "three conversions become two")
            check(new.counts.blockerQueries == old.counts.blockerQueries, "all host blocker queries retained")
            print(string.format("[input_move_performance_test] CPU 101x100 baseline=%.6fs candidate=%.6fs pointer=%d/%d conversions=%d/%d blockerQueries=%d/%d hover=%d/%d",
                oldCPU, newCPU, old.counts.pointerReads, new.counts.pointerReads,
                old.counts.conversions, new.counts.conversions, old.counts.blockerQueries,
                new.counts.blockerQueries, old.counts.hover, new.counts.hover))
        end
    end)
    if not ok then
        print("[FAIL] input_move_performance_test " .. tostring(why))
        error(why)
    end
    print("[input_move_performance_test] ALL PASS cases=" .. cases .. " assertions=" .. assertions)
    engine:Exit()
end
