-- 真实 TM / TutorialOverlay / Viewport / Horizon 投影与输入回归；页面和存档只用内存 spy。
-- 仅捕获真实 Horizon 的 ctx，输入直接 bind；不加载玩家存档、不发 action、不创建图形资源。
-- Runtime: tests/tutorial_horizon_input_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
function Start()
    ---@type fun(name: string): any
    local nativeRequire = require
    local originals, nvgOriginals = {}, {}
    local originalInput, originalTime = input, time
    local VP = nativeRequire("core.Viewport")
    local originalNotes = VP._notes
    local assertions, failures, cases = 0, 0, 0
    local function check(value, label)
        assertions = assertions + 1
        if not value then failures = failures + 1; print("[FAIL] tutorial_horizon_input_test: " .. label) end
    end
    local function runCase(label, fn)
        cases = cases + 1
        local before = failures
        local ok, err = pcall(fn)
        if not ok then check(false, label .. " exception: " .. tostring(err)) end
        if before == failures then print("[PASS] " .. label) end
    end
    local function horizonGlobal(key)
        return type(key) == "string" and (key:match("^H_") or key:match("^Handle.*Horizon$"))
    end
    for key, value in pairs(_G) do if horizonGlobal(key) then originals[key] = value end end
    local ok, err = pcall(function()
        local function noop() return false end
        ---@return any
        local function mock(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local calls, events = {}, {}
        local function record(name, x, y)
            calls[name] = (calls[name] or 0) + 1
            events[#events + 1] = { name = name, x = x, y = y }
        end
        local function n(name) return calls[name] or 0 end
        local function clearCalls() calls, events = {}, {} end
        local state = { tri = false, reward = false, detail = false, missing = false, owner = "character",
            seamSmith = false, warehouse = false, pinned = false }
        local cursor = { x = 0, y = 0 }
        local clock = { elapsedTime = 100 }
        input = { GetMousePosition = function() return cursor end }
        time = clock
        ---@type any
        local RT = { logicalW = 1920, logicalH = 1080, windowW = 1920, windowH = 1080,
            DESIGN_W = 1080, DESIGN_H = 2400, dpr = 1, frameOx = 0, frameOy = 0,
            frameScale = 1, vg = {}, bootReady_ = true, preload_ = { active = false } }
        local data = { session = { claimedScenarios = {} }, heroes = { roster = {} },
            equipment = { equipped = {} }, battle = { maxStageId = 102 } }
        local Store = { Get = function(key) return data[key] end }
        local methods = { "handleInput", "handleClick", "handleDragBegin", "handleDragMove",
            "handleDragEnd", "handleEquipmentSlotTap", "handleNavigationTap", "close" }
        ---@return any
        local function page(name, fields)
            local base = {}
            for _, method in ipairs(methods) do
                base[method] = function(x, y) record(name .. "." .. method, x, y); return false end
            end
            for key, value in pairs(fields or {}) do base[key] = value end
            return mock(base)
        end
        local mods = {
            ["boot.StandaloneRT"] = RT, ["core.Viewport"] = VP,
            ["boot.OfflineRewardOverlay"] = { bind = function() return mock() end },
            ["ui.hud.BottomNav"] = mock({ getSelectedIndex = function() return 3 end }),
            ["ui.story.ScenarioDialogue"] = mock(),
            ["ui.battle.tri.BattleTriPage"] = page("tri", { isOpen = function() return state.tri end }),
            ["ui.backpack.BackpackPanel"] = page("backpack", {
                isOpen = function() return state.warehouse end,
                isLeftMode = function() return true end,
                getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
                peekEquipAt = function(x, y)
                    if state.warehouse and math.abs(x - 140) <= 60 and math.abs(y - 1060) <= 60 then
                        return { seq = 7, slot = "weapon" }
                    end
                    return nil
                end,
                handleInput = function(x, y)
                    record("backpack.handleInput", x, y)
                    state.detail, state.pinned, state.owner = true, true, "backpack"
                    return true
                end,
            }),
            ["ui.blacksmith.BlacksmithPage"] = page("smith", {
                isOpen = function() return state.seamSmith end,
                getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
            }),
            ["ui.character.detail.CharacterDetail"] = page("characterDetail", {
                isOpen = function() return true end,
                getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
            }),
            ["ui.character.equip.EquipmentDetail"] = page("detail", {
                isOpen = function() return state.detail end,
                isCompactCorner = function() return state.detail end,
                isPinned = function() return state.pinned end,
                getOwner = function() return state.owner end,
                containsPoint = function(x, y)
                    return state.detail and x >= 700 and x <= 1000 and y >= 1400 and y <= 1700
                end,
                close = function() state.detail = false; record("detail.close") end,
            }),
            ["ui.hud.popup.RewardPopup"] = page("reward", {
                isOpen = function() return state.reward end,
                currentPanel = function() return state.reward and "right" or nil end,
                currentRowTag = function() return nil end,
            }),
            ["core.DarkIcon"] = mock({ SHOWCASE = false }),
            ["core.DrawUtil"] = mock({ SEAMBAR_ASPECT = 0.04, SEAMBAR_ARROW_Y = 0.469,
                seamSlideX = function() return 0 end,
                hitTest = function(x, y, cx, cy, w, h)
                    return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5
                end,
            }),
            ["runtime.GameAction"] = mock({ sendAction = function() record("action") end }),
        }
        ---@type any
        local captured = nil
        local capturing = true
        require = function(name)
            if name == "systems.TutorialManager" or name == "ui.tutorial.TutorialOverlay"
                or name == "config.TutorialConfig" or name == "config.GameConfig" then
                return nativeRequire(name)
            end
            if name == "boot.StandaloneHorizonInput" then
                if capturing then return { bind = function(ctx) captured = ctx end } end
                return nativeRequire(name)
            end
            if not mods[name] then mods[name] = page(name) end
            return mods[name]
        end
        local TM = nativeRequire("systems.TutorialManager")
        local Overlay = nativeRequire("ui.tutorial.TutorialOverlay")
        mods["systems.TutorialManager"], mods["ui.tutorial.TutorialOverlay"] = TM, Overlay
        mods["ui.character.panel.CharacterPanel"] = page("character", {
            draw = function()
                if not state.missing then
                    local key = TM.getCurrentHighlight()
                    if key then TM.registerHotspot(key, 540, 600, 160, 100, "right") end
                end
            end,
        })
        -- 图形函数只替换底层绘制；保留实际 Overlay.layout/draw 和 Horizon note 投影。
        for _, name in ipairs({ "nvgBeginFrame", "nvgEndFrame", "nvgSave", "nvgRestore",
            "nvgTranslate", "nvgScale", "nvgResetTransform", "nvgResetScissor", "nvgScissor",
            "nvgIntersectScissor", "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFillColor",
            "nvgFill", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgFontFace",
            "nvgFontSize", "nvgTextAlign", "nvgText", "nvgPathWinding" }) do
            nvgOriginals[name] = { value = rawget(_G, name) }; rawset(_G, name, noop)
        end
        nvgOriginals.nvgTextBounds = { value = rawget(_G, "nvgTextBounds") }
        rawset(_G, "nvgTextBounds", function(_, _, _, text) return utf8.len(text) * 10 end)
        nativeRequire("boot.StandaloneHorizon")
        check(captured ~= nil and captured.Viewport == VP, "捕获真实 Horizon ctx / Viewport")
        capturing = false
        local InputModule = nativeRequire("boot.StandaloneHorizonInput")
        local left = { Button = { GetInt = function() return MOUSEB_LEFT end } }
        local function invoke(name, event) rawget(_G, name)(name, event or left) end
        local function screenPosition(x, y)
            cursor.x = (RT.frameOx + x * RT.frameScale) * RT.dpr
            cursor.y = (RT.frameOy + y * RT.frameScale) * RT.dpr
        end
        local function panelPosition(panel, x, y)
            local note, p = VP.getNote(panel), VP.PANELS[panel]
            return note.ox + p.bx * note.s + x * (note.scaleX or note.s * VP.DS),
                note.oy + p.by * note.s + y * note.s * VP.DS
        end
        local function click(x, y)
            screenPosition(x, y)
            invoke("HandleMouseButtonDownHorizon")
            clock.elapsedTime = clock.elapsedTime + 0.2
            invoke("HandleMouseButtonUpHorizon")
        end
        local function fixture(tri, transformed, dpr)
            state.tri, state.reward, state.detail, state.missing, state.owner = tri, false, false, false, "character"
            state.seamSmith, state.warehouse, state.pinned = false, false, false
            RT.dpr, RT.frameScale = dpr, transformed and 0.8 or 1
            RT.frameOx, RT.frameOy = transformed and 37 or 0, transformed and 23 or 0
            VP._notes = {}
            data.session = { claimedScenarios = {} }
            TM.init(RT.vg, Store, function(progress) data.session.tutorialProgress = progress; record("persist") end)
            TM.update(0)
            TM.onScenarioClaimed(5)
            TM.update(1.2)
            InputModule.bind(captured)
            H_SEAM_BACK = true
            invoke("HandleNanoVGRenderHorizon", {})
            clearCalls()
        end
        local function noBusiness(label)
            check(n("detail.handleDragBegin") == 0 and n("detail.handleInput") == 0
                and n("detail.close") == 0, label .. " 不按压/点击/关闭装备浮层")
            check(n("character.handleInput") == 0 and n("character.handleDragBegin") == 0
                and n("tri.handleInput") == 0 and n("tri.handleDragBegin") == 0
                and n("characterDetail.close") == 0 and n("smith.close") == 0 and n("action") == 0, label .. " 不派发下层业务/返回/action")
        end
        for _, tri in ipairs({ false, true }) do
            for _, transformed in ipairs({ false, true }) do
                for _, dpr in ipairs({ 1, 2, 3 }) do
                    local label = (tri and "tri" or "ordinary") .. " frame=" .. tostring(transformed) .. " DPR=" .. dpr
                    runCase(label .. " 目标单次推进", function()
                        fixture(tri, transformed, dpr)
                        local x, y = panelPosition("right", 540, 600)
                        check(TM.canPointerStart(x, y), "真实 note 投影目标 down 放行")
                        check(not TM.canPointerStart(x + 45, y), "按钮外不以光环放行")
                        local before = TM.getProgress().step
                        screenPosition(x, y)
                        invoke("HandleMouseButtonDownHorizon")
                        check(TM.getProgress().step == before, "down 不推进")
                        clock.elapsedTime = clock.elapsedTime + 0.2
                        invoke("HandleMouseButtonUpHorizon")
                        check(TM.getProgress().step == before + 1 and n("persist") == 1, "up 仅推进/持久化一次")
                        check(n("character.handleInput") == 1, "目标点击传给所属右栏一次")
                        invoke("HandleMouseButtonUpHorizon")
                        check(TM.getProgress().step == before + 1 and n("character.handleInput") == 1, "重复 up 不二次推进/派发")
                    end)
                    runCase(label .. " 非目标浮层与返回条", function()
                        fixture(tri, transformed, dpr)
                        state.detail = true
                        local x, y = panelPosition("right", 850, 1550)
                        check(captured.equipOverlayDesign(x, y) ~= nil, "点确实命中真实浮层逆变换")
                        local before = TM.getProgress().step
                        click(x, y)
                        noBusiness("非目标浮层")
                        check(TM.getProgress().step == before and state.detail, "不推进且浮层保持")
                        state.seamSmith = not tri -- 普通横屏返回条由锻炉提供；tri 使用右角色详情条。
                        local seamX = nil ---@type number?
                        local seamY = RT.logicalH * 0.469
                        for sx = 0, RT.logicalW do
                            if captured.seamHitAt(sx, seamY) then seamX = sx; break end
                        end
                        check(seamX ~= nil, "真实返回条命中存在")
                        if seamX then click(seamX, seamY) end
                        noBusiness("非目标返回条")
                        check(TM.getProgress().step == before and state.detail, "返回条 down/up 不推进或dismiss")
                    end)
                    runCase(label .. " 缺热点 skip 首击优先", function()
                        fixture(tri, transformed, dpr)
                        state.detail, state.missing = true, true
                        invoke("HandleNanoVGRenderHorizon", {})
                        clearCalls()
                        check(TM.getCurrentHotspot() == nil, "真实 Horizon 本帧缺热点")
                        local layout = Overlay.layout(RT.logicalW, RT.logicalH, nil)
                        check(not TM.canPointerStart(layout.skip.cx, layout.skip.cy), "skip down 先屏蔽浮层dismiss")
                        click(layout.skip.cx, layout.skip.cy)
                        check(TM.getProgress().completed["1"] == true and n("persist") == 1, "缺热点 skip 完成并保存一次")
                        noBusiness("skip")
                        check(state.detail, "skip 首击不关闭浮层")
                        TM.update(0.3)
                        check(TM.getCurrentGroup() == nil, "skip 淡出后释放教程")
                    end)
                    runCase(label .. " 奖励让位 / bag owner", function()
                        fixture(tri, transformed, dpr)
                        state.reward = true
                        check(TM.canPointerStart(0, 0) and not TM.isInputActive(), "奖励打开教程输入让位")
                        local x, y = panelPosition("right", 850, 1550)
                        local before = TM.getProgress().step
                        click(x, y)
                        check(n("reward.handleInput") == 1 and n("reward.handleDragBegin") == 1, "非教程目标奖励收到 down/up tap")
                        check(TM.getProgress().step == before and n("character.handleInput") == 0, "奖励不推进/穿透教程")
                        state.reward, state.detail, state.owner = false, true, "bag"
                        local rx, ry = panelPosition("right", 850, 1550)
                        local lx, ly = panelPosition("left", 850, 1550)
                        local dx, dy, ed = captured.equipOverlayDesign(rx, ry)
                        check(dx and math.abs(dx - 850) < 0.00001 and math.abs(dy - 1550) < 0.00001
                            and ed == mods["ui.character.equip.EquipmentDetail"], "真实 bag owner 挂 right 且设计坐标正确")
                        check(captured.equipOverlayDesign(lx, ly) == nil, "bag owner 不挂 left")
                    end)
                end
            end
        end
        runCase("Gifted 事件步骤同仓库格双击仍派发两次", function()
            for _, tri in ipairs({ false, true }) do
                fixture(tri, true, 2)
                local targetX, targetY = panelPosition("right", 540, 600)
                -- 用真实 TM 的点击步骤进入 gifted 等待装备回执步骤，而非改内部配置/状态。
                TM.handleScreenClick(targetX, targetY)
                TM.handleScreenClick(targetX, targetY)
                check(TM.getCurrentHighlight() == "equip_item_gifted", "真实TM已进入gifted事件步骤")
                state.warehouse = true
                local x, y = panelPosition("left", 140, 1060)
                clearCalls()
                screenPosition(x, y)
                invoke("HandleMouseButtonDownHorizon")
                clock.elapsedTime = clock.elapsedTime + 0.15
                invoke("HandleMouseButtonUpHorizon")
                check(n("backpack.handleInput") == 1 and state.detail and state.pinned,
                    "仓库首击派发一次并pin浮层")
                local firstTime = clock.elapsedTime
                local before = TM.getProgress().step
                screenPosition(x, y)
                invoke("HandleMouseButtonDownHorizon")
                check(n("detail.close") == 1 and not state.detail,
                    "第二击同格按下确实经过真实浮层dismiss")
                clock.elapsedTime = clock.elapsedTime + 0.15
                invoke("HandleMouseButtonUpHorizon")
                check(clock.elapsedTime - firstTime < 0.2 and n("backpack.handleInput") == 2,
                    "0.2秒内第二击dismiss后仍补派发同仓库格，不被吞掉")
                check(TM.getProgress().step == before and not TM.isGroupCompleted(1)
                    and n("persist") == 0, "两次点击不伪装穿戴成功，仍等待真实装备回执")
                local hits = 0
                for _, e in ipairs(events) do
                    if e.name == "backpack.handleInput" then
                        hits = hits + 1
                        check(math.abs(e.x - 140) < 0.00001 and math.abs(e.y - 1060) < 0.00001,
                            "两次都派到同仓库格真实设计坐标")
                    end
                end
                check(hits == 2 and n("detail.handleInput") == 0 and n("action") == 0,
                    "恰好两次仓库Input，无浮层或额外action")
            end
        end)
        runCase("非gifted事件教程不补派发仓库dismiss点击", function()
            fixture(true, true, 2)
            TM.skipCurrentGroup()
            TM.update(0.3)
            TM.startGroup(8)
            TM.update(0.3)
            check(TM.getCurrentHighlight() == "tavern_btn_gacha10", "真实非gifted事件步骤")
            state.warehouse, state.detail, state.pinned, state.owner = true, true, true, "backpack"
            clearCalls()
            local x, y = panelPosition("left", 140, 1060)
            click(x, y)
            check(n("detail.close") == 1 and n("backpack.handleDragBegin") == 1,
                "非gifted也实际经历浮层dismiss按压路径")
            check(n("backpack.handleInput") == 0 and n("action") == 0
                and TM.getCurrentHighlight() == "tavern_btn_gacha10",
                "非gifted不能借装备格例外穿透或推进教程")
        end)
        -- Touch payload 只含 TouchID/X/Y，坐标量化为真实整数物理像素；鼠标刻意不在目标上。
        local function touch(id, x, y)
            local px = math.floor((RT.frameOx + x * RT.frameScale) * RT.dpr + 0.5)
            local py = math.floor((RT.frameOy + y * RT.frameScale) * RT.dpr + 0.5)
            return {
                TouchID = { GetInt = function() return id end },
                X = { GetInt = function() return px end },
                Y = { GetInt = function() return py end },
            }
        end
        local function touchFixture(tri, dpr)
            fixture(tri, true, dpr)
            cursor.x, cursor.y = 0, 0
            local x, y = panelPosition("right", 540, 600)
            return x, y, TM.getProgress().step
        end
        runCase("Touch target X/Y + frame/DPR 不读取鼠标", function()
            for _, tri in ipairs({ false, true }) do
                local x, y, before = touchFixture(tri, 3)
                local event = touch(41, x, y)
                check(event.Button == nil and cursor.x == 0 and cursor.y == 0, "touch payload 无Button，鼠标在0,0")
                invoke("HandleTouchBeginHorizon", event)
                check(TM.getProgress().step == before and n("character.handleDragBegin") == 1, "touch down 到右栏但不推进")
                clock.elapsedTime = clock.elapsedTime + 0.2
                invoke("HandleTouchEndHorizon", event)
                check(TM.getProgress().step == before + 1 and n("persist") == 1
                    and n("character.handleInput") == 1, "touch target up 推进/透传恰好一次")
                local found = false
                for _, e in ipairs(events) do
                    if e.name == "character.handleInput" then
                        found = true
                        check(math.abs(e.x - 540) < 1 and math.abs(e.y - 600) < 1,
                            "整数物理touch经frame/DPR逆变换落在实际右栏设计目标")
                    end
                end
                check(found and cursor.x == 0 and cursor.y == 0, "实际业务收到touch坐标，鼠标未被伪造移动")
                invoke("HandleTouchEndHorizon", event)
                check(TM.getProgress().step == before + 1 and n("character.handleInput") == 1, "重复touch up不推进/派发")
            end
        end)
        runCase("Touch 缺热点 skip 优先于浮层", function()
            touchFixture(true, 2)
            state.detail, state.missing = true, true
            invoke("HandleNanoVGRenderHorizon", {})
            clearCalls()
            local layout = Overlay.layout(RT.logicalW, RT.logicalH, nil)
            local event = touch(51, layout.skip.cx, layout.skip.cy)
            invoke("HandleTouchBeginHorizon", event)
            check(state.detail and not TM.getProgress().completed["1"], "touch skip down不dismiss/提前完成")
            clock.elapsedTime = clock.elapsedTime + 0.2
            invoke("HandleTouchEndHorizon", event)
            check(TM.getCurrentHotspot() == nil and TM.getProgress().completed["1"] == true
                and n("persist") == 1, "touch缺热点skip完成并保存一次")
            noBusiness("touch skip")
            check(state.detail and cursor.x == 0 and cursor.y == 0, "touch skip首击保留浮层，不读取鼠标")
        end)
        runCase("Touch 第二指不能释放或推进主指", function()
            local x, y, before = touchFixture(true, 3)
            local primary, secondary = touch(61, x, y), touch(62, x, y)
            invoke("HandleTouchBeginHorizon", primary)
            invoke("HandleTouchBeginHorizon", secondary)
            invoke("HandleTouchMoveHorizon", touch(62, x + 180, y + 150))
            invoke("HandleTouchEndHorizon", secondary)
            check(TM.getProgress().step == before and n("persist") == 0
                and n("character.handleInput") == 0 and n("character.handleDragBegin") == 1
                and n("character.handleDragMove") == 0 and n("character.handleDragEnd") == 0,
                "不同ID begin/move/end不覆盖、释放或推进主指")
            clock.elapsedTime = clock.elapsedTime + 0.2
            invoke("HandleTouchEndHorizon", primary)
            check(TM.getProgress().step == before + 1 and n("persist") == 1
                and n("character.handleInput") == 1, "次指释放后主指仍可完成一次目标tap")
            invoke("HandleTouchEndHorizon", secondary)
            check(TM.getProgress().step == before + 1 and n("character.handleInput") == 1,
                "主指结束后旧次指up仍不派发")
        end)
        runCase("Touch 目标拖出取消点击", function()
            local x, y, before = touchFixture(false, 2)
            invoke("HandleTouchBeginHorizon", touch(71, x, y))
            invoke("HandleTouchMoveHorizon", touch(71, x + 100, y + 150))
            clock.elapsedTime = clock.elapsedTime + 0.2
            invoke("HandleTouchEndHorizon", touch(71, x + 100, y + 150))
            check(TM.getProgress().step == before and n("persist") == 0
                and n("character.handleInput") == 0, "touch拖出不推进/点击")
            check(n("character.handleDragBegin") == 1 and n("character.handleDragMove") == 1
                and n("character.handleDragEnd") == 1, "touch拖出仍释放右栏来源手势")
            local target = touch(72, x, y)
            invoke("HandleTouchBeginHorizon", target)
            clock.elapsedTime = clock.elapsedTime + 0.2
            invoke("HandleTouchEndHorizon", target)
            check(TM.getProgress().step == before + 1 and n("character.handleInput") == 1,
                "取消后新指tap恢复，不遗留capture")
        end)
    end)
    if not ok then check(false, "Start exception: " .. tostring(err)) end
    require, input, time = nativeRequire, originalInput, originalTime
    VP._notes = originalNotes
    for name, saved in pairs(nvgOriginals) do rawset(_G, name, saved.value) end
    local added = {}
    for key in pairs(_G) do if horizonGlobal(key) and originals[key] == nil then added[#added + 1] = key end end
    for _, key in ipairs(added) do rawset(_G, key, nil) end
    for key, value in pairs(originals) do rawset(_G, key, value) end
    if failures == 0 then
        print("[tutorial_horizon_input_test] ALL PASS: " .. cases .. " cases, " .. assertions .. " assertions")
    else print("[FAIL] tutorial_horizon_input_test: " .. failures .. " failures, " .. assertions .. " assertions") end
    engine:Exit()
end
