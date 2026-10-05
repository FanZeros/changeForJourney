-- 仓库横屏快速手势回归：真实 Horizon + Viewport，页面/Link API 为 spy。
-- 只验证路由边界，不模拟穿戴事务；Link 的 handleEquipClick/Right 实现另测。
-- Runtime: tests/backpack_quick_horizon_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
function Start()
    ---@type fun(name: string): any
    local originalRequire = _G.require
    local originalInput, originalTime = _G.input, _G.time
    local RT = originalRequire("boot.StandaloneRT")
    local viewport = originalRequire("core.Viewport")
    local originalRT, originalNotes, originalGlobals = {}, viewport._notes, {}
    local function horizonGlobal(key)
        return type(key) == "string" and (key:match("^H_") or key:match("^Handle.*Horizon$"))
    end
    for key, value in pairs(RT) do originalRT[key] = value end
    for key, value in pairs(_G) do
        if horizonGlobal(key) then originalGlobals[key] = value end
    end
    local function resetRT(values)
        for key in pairs(RT) do RT[key] = nil end
        for key, value in pairs(values) do RT[key] = value end
    end
    local assertions, failures = 0, 0
    local ok, err = pcall(function()
        local function check(condition, message)
            assertions = assertions + 1
            if not condition then
                failures = failures + 1
                print("[backpack_quick_horizon_test] FAIL: " .. message)
            end
        end
        local function noop() return false end
        ---@return any
        local function mock(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local calls, inputTimes = {}, {}
        local function count(name) calls[name] = (calls[name] or 0) + 1 end
        local function n(name) return calls[name] or 0 end
        ---@type any
        local state = {
            tri = true, grid = true, warehouse = true, leftMode = true,
            task = false, loot = false, modal = false, tutorial = false,
            detail = false, pinned = false, overlayPoint = false,
            armed = false, dragging = false, draggingCard = false,
        }
        local cursor = { x = 0, y = 0 }
        _G.input = { GetMousePosition = function() return cursor end }
        _G.time = { elapsedTime = 100 }
        local clock = 100
        local candidate = { seq = 7, slot = "helmet", templateId = "H1" }
        local function hitGrid(x, y)
            return state.grid and x >= 80 and x <= 200 and y >= 1000 and y <= 1120
        end
        -- API spy 仅表示 Backpack 把装备格事件交给 Link；不发送生产 action。
        local api = {
            handleEquipClick = function() count("apiClick"); return true end,
            handleEquipRight = function() count("apiRight"); return true end,
        }
        local warehouse = mock({
            isOpen = function() return state.warehouse end,
            isLeftMode = function() return state.leftMode end,
            getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
            peekEquipAt = function(x, y)
                if hitGrid(x, y) then return candidate end
                return nil
            end,
            handleDragBegin = function() count("backpackBegin"); return true end,
            handleDragEnd = function() count("backpackEnd"); return true end,
            haltScroll = function() count("haltScroll") end,
            handleInput = function(x, y)
                count("backpackInput")
                inputTimes[#inputTimes + 1] = time.elapsedTime
                if hitGrid(x, y) then return api.handleEquipClick(candidate) end
                return true
            end,
            handleRightClick = function(x, y)
                count("backpackRight")
                if hitGrid(x, y) then return api.handleEquipRight(candidate) end
                return false
            end,
        })
        local equipmentDetail = mock({
            isOpen = function() return state.detail end,
            isCompactCorner = function() return state.detail end,
            isPinned = function() return state.detail and state.pinned end,
            getOwner = function() return "backpack" end,
            containsPoint = function() return state.detail and state.overlayPoint end,
            close = function() state.detail, state.pinned = false, false; count("closePin") end,
        })
        local crossDrag = mock({
            arm = function(item, _, _, source)
                check(item == candidate and source == "backpack", "arm 使用仓库真实候选/来源")
                state.armed = true; count("arm")
            end,
            isArmed = function() return state.armed end,
            getSource = function() return "backpack" end,
            move = function() count("dragMove"); return state.dragging end,
            finish = function()
                check(state.armed, "finish 必须在 isArmed=true 时调用")
                state.armed = false; count("finish")
                return state.dragging
            end,
        })
        local mods = {
            ["boot.StandaloneRT"] = RT,
            ["core.Viewport"] = viewport,
            ["ui.backpack.BackpackPanel"] = warehouse,
            ["ui.character.equip.EquipmentDetail"] = equipmentDetail,
            ["ui.character.EquipCrossDrag"] = crossDrag,
            ["ui.character.panel.CharacterPanel"] = mock({
                isDraggingCard = function() return state.draggingCard end,
                handleInput = function() count("characterInput"); return true end,
                handleRightClick = function() count("characterRight"); return true end,
            }),
            ["ui.character.detail.CharacterDetail"] = mock({ isEquipTab = function() return true end }),
            ["ui.battle.tri.BattleTriPage"] = mock({ isOpen = function() return state.tri end }),
            ["ui.hud.BottomNav"] = { getSelectedIndex = function() return 3 end },
            ["ui.hud.popup.RewardPopup"] = mock({
                isOpen = function() return state.modal end,
                currentPanel = function() return nil end,
                currentRowTag = function() return nil end,
                handleInput = function() count("modalInput"); return true end,
            }),
            ["systems.TutorialManager"] = mock({ isActive = function() return state.tutorial end }),
            ["ui.battle.popup.TerminalConfirmDialog"] = mock({ isOpen = noop }),
            ["ui.tavern.TavernPopups"] = mock({ isBlocking = noop }),
            ["ui.tavern.TargetRecruitPanel"] = mock({ isOpen = noop }),
            ["ui.story.task.TaskPage"] = mock({
                isOpen = function() return state.task end,
                getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
                handleInput = function() count("taskInput"); return true end,
            }),
            ["ui.loot.LootBoxPage"] = mock({
                isOpen = function() return state.loot end,
                getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
                handleRightClick = function() count("lootRight"); return true end,
            }),
            ["ui.loot.LootBox"] = mock({ handleInput = function() count("lootInput"); return true end }),
            ["runtime.GameAction"] = mock({ sendAction = function() count("action") end }),
            ["core.DrawUtil"] = mock({
                SEAMBAR_ASPECT = 0.04, SEAMBAR_ARROW_Y = 0.469,
                seamSlideX = function() return 0 end,
            }),
        }
        -- Runtime require 可忽略 package.loaded；全程包装 _G.require 拦截动态依赖。
        _G.require = function(name)
            if name == "boot.StandaloneHorizonInput" or name == "boot.OfflineRewardOverlay"
                or name == "boot.SeamBackGesture" or name == "boot.TerminalInput"
                or name == "boot.StandaloneHorizonWheel" then
                return originalRequire(name)
            end
            if not mods[name] then mods[name] = mock() end
            return mods[name]
        end
        originalRequire("boot.StandaloneHorizon")
        local left = { Button = { GetInt = function() return MOUSEB_LEFT end } }
        local right = { Button = { GetInt = function() return MOUSEB_RIGHT end } }
        local function position(panel, x, y)
            local note, p = viewport.getNote(panel), viewport.PANELS[panel]
            cursor.x = note.ox + p.bx * note.s + x * note.s * viewport.DS
            cursor.y = note.oy + p.by * note.s + y * note.s * viewport.DS
        end
        local function realDownUp(panel, x, y, at, button)
            position(panel, x, y)
            time.elapsedTime = at - 0.01
            HandleMouseButtonDownHorizon("MouseButtonDown", button or left)
            time.elapsedTime = at
            HandleMouseButtonUpHorizon("MouseButtonUp", button or left)
        end
        local function fixture(tri)
            state.tri, state.grid, state.warehouse, state.leftMode = tri, true, true, true
            state.task, state.loot, state.modal, state.tutorial = false, false, false, false
            state.detail, state.pinned, state.overlayPoint = false, false, false
            state.armed, state.dragging, state.draggingCard = false, false, false
            resetRT({ logicalW = 1920, logicalH = 1080, dpr = 1, bootReady_ = true })
            viewport._notes = {}
            H_ox, H_oy, H_s = viewport.layout(1920, 1080)
            H_SEAM_BACK = true
            viewport.note("center", H_ox, H_oy, H_s)
            if tri then
                viewport.note("left", 0, 0, 1)
                viewport.note("right", 1920 - 486 - 972, 0, 1)
            else
                viewport.note("left", H_ox, H_oy, H_s)
                viewport.note("right", H_ox, H_oy, H_s)
            end
            for key in pairs(calls) do calls[key] = nil end
            for key in pairs(inputTimes) do inputTimes[key] = nil end
            clock = clock + 1
            time.elapsedTime = clock
        end
        local function noEquipmentSend(label)
            check(n("apiClick") == 0 and n("apiRight") == 0 and n("action") == 0,
                label .. " 不发送装备 API/action")
        end

        for _, tri in ipairs({ true, false }) do
            local prefix = tri and "tri: " or "viewport: "
            fixture(tri)
            realDownUp("left", 140, 1060, clock)
            realDownUp("left", 140, 1060, clock + 0.08)
            check(n("backpackInput") == 2 and n("apiClick") == 2, prefix .. "0.08s 双击两次都到 handleInput/Link")
            check(#inputTimes == 2 and math.abs(inputTimes[2] - inputTimes[1] - 0.08) < 0.00001,
                prefix .. "双击时间间隔确为0.08s，不能用1秒掩盖防抖")
            check(n("arm") == 2 and n("finish") == 2 and not state.armed,
                prefix .. "未达拖拽阈值 finish=false 仍放行两次 tap")
            check(n("characterInput") == 0 and n("action") == 0, prefix .. "仓库 tap 不穿透右栏/不发送生产 action")

            fixture(tri)
            realDownUp("left", 140, 1060, clock, right)
            check(n("backpackRight") == 1 and n("apiRight") == 1, prefix .. "右键 down/up 只派发一次")
            check(n("backpackInput") == 0 and n("arm") == 0 and n("finish") == 0,
                prefix .. "右键不混入左键/装备拖拽")

            fixture(tri)
            realDownUp("left", 140, 1060, clock)
            -- 第二击到来前 hover 详情打开；光标不在 overlay，关闭后同格仍路由。
            state.detail = true
            realDownUp("left", 140, 1060, clock + 0.08)
            check(n("closePin") == 1 and n("backpackInput") == 2 and n("apiClick") == 2,
                prefix .. "hover关闭后的快速第二击也到 handleInput")

            fixture(tri)
            state.grid = false
            realDownUp("left", 300, 1060, clock)
            realDownUp("left", 300, 1060, clock + 0.08)
            check(n("backpackInput") == 1, prefix .. "非装备格仍受0.12s通用防抖")
            realDownUp("left", 300, 1060, clock + 0.09, right)
            noEquipmentSend(prefix .. "无grid")

            for _, blocked in ipairs({ "modal", "task", "loot", "warehouse", "leftMode" }) do
                fixture(tri)
                state[blocked] = blocked ~= "warehouse" and blocked ~= "leftMode"
                realDownUp("left", 140, 1060, clock)
                realDownUp("left", 140, 1060, clock + 0.08, right)
                noEquipmentSend(prefix .. blocked)
                check(n("backpackInput") == 0 and n("backpackRight") == 0,
                    prefix .. blocked .. " 不路由到仓库")
                if blocked == "modal" then check(n("modalInput") == 1, prefix .. "全局模态实际接收左键") end
                if blocked == "task" then check(n("taskInput") == 1, prefix .. "Task实际接收左键") end
                if blocked == "loot" then check(n("lootInput") == 1 and n("lootRight") == 1, prefix .. "Loot自管左右键") end
            end

            fixture(tri)
            state.dragging = true
            position("left", 140, 1060)
            HandleMouseButtonDownHorizon("MouseButtonDown", left)
            check(state.armed and n("arm") == 1, prefix .. "真拖拽已arm")
            position("left", 190, 1110)
            HandleMouseMoveHorizon("MouseMove", {})
            -- 回到原格释放：即使坐标满足tap，finish=true仍必须消费事件。
            position("left", 140, 1060)
            time.elapsedTime = clock
            HandleMouseButtonUpHorizon("MouseButtonUp", left)
            check(n("dragMove") == 1 and n("finish") == 1 and n("haltScroll") == 1 and not state.armed,
                prefix .. "真drag finish=true结束并haltScroll")
            check(n("backpackInput") == 0, prefix .. "真drag不能派发tap")
            noEquipmentSend(prefix .. "真drag")

            fixture(tri)
            state.grid, state.detail, state.pinned = false, true, true
            -- 无 overlayPoint、无装备格：只关闭pin，不激活背后按钮。
            realDownUp("left", 300, 1060, clock)
            check(n("closePin") == 1 and not state.detail and not state.pinned,
                prefix .. "overlay外空白只关闭pin")
            check(n("backpackBegin") == 1 and n("backpackInput") == 0,
                prefix .. "关闭pin允许dragBegin但不派发tap")
            noEquipmentSend(prefix .. "关闭pin")
        end
    end)

    _G.require, _G.input, _G.time = originalRequire, originalInput, originalTime
    viewport._notes = originalNotes
    resetRT(originalRT)
    local addedGlobals = {}
    for key in pairs(_G) do
        if horizonGlobal(key) and originalGlobals[key] == nil then addedGlobals[#addedGlobals + 1] = key end
    end
    for _, key in ipairs(addedGlobals) do _G[key] = nil end
    for key, value in pairs(originalGlobals) do _G[key] = value end
    if ok and failures == 0 then
        print("[backpack_quick_horizon_test] ALL PASS: " .. assertions .. " assertions")
    else
        print("[backpack_quick_horizon_test] FAIL: " .. tostring(err or failures .. " assertions failed"))
        log:Write(LOG_ERROR, "[backpack_quick_horizon_test] FAIL: " .. tostring(err or failures .. " assertions failed"))
    end
    engine:Exit()
end
