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
            decompose = false, marquee = false, beginAccepted = true, autoPopup = false,
            setFilter = false, itemDetail = false, closing = false, nav = 3,
            offline = false, levelup = false, playerinfo = false, updateNotice = false,
            title = false, letter = false, intro = false, dialogue = false, ce = false,
            sweep = false, damage = false, stage = false, terminal = false,
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
        local marqueeCoords = { begin = {}, move = {}, finish = {} }
        local function canMarquee()
            return state.warehouse and state.leftMode and state.decompose and not state.closing
                and not state.autoPopup and not state.setFilter and not state.itemDetail
        end
        local warehouse = mock({
            canMarquee = canMarquee,
            isPopupOpen = function() return state.autoPopup or state.setFilter or state.itemDetail end,
            isMarqueeActive = function() return state.marquee end,
            handleMarqueeBegin = function(x, y)
                count("marqueeBegin")
                marqueeCoords.begin[#marqueeCoords.begin + 1] = { x = x, y = y }
                if not canMarquee() or not state.beginAccepted then return false end
                state.marquee = true
                return true
            end,
            handleMarqueeMove = function(x, y)
                count("marqueeMove")
                marqueeCoords.move[#marqueeCoords.move + 1] = { x = x, y = y }
                return state.marquee
            end,
            handleMarqueeEnd = function(x, y)
                count("marqueeEnd")
                marqueeCoords.finish[#marqueeCoords.finish + 1] = { x = x, y = y }
                local active = state.marquee
                state.marquee = false
                return active
            end,
            cancelMarquee = function() count("marqueeCancel"); state.marquee = false end,
            handleHover = function() count("backpackHover") end,
            handleDragMove = function() count("backpackMove") end,
            handleScroll = function() count("backpackScroll") end,
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
                handleHover = function() count("characterHover") end,
                handleDragMove = function() count("characterMove") end,
                handleDragEnd = function() count("characterEnd") end,
            }),
            ["ui.character.detail.CharacterDetail"] = mock({ isEquipTab = function() return true end }),
            ["ui.battle.tri.BattleTriPage"] = mock({ isOpen = function() return state.tri end }),
            ["ui.hud.BottomNav"] = { getSelectedIndex = function() return state.nav end },
            ["ui.hud.popup.RewardPopup"] = mock({
                isOpen = function() return state.modal end,
                currentPanel = function() return nil end,
                currentRowTag = function() return nil end,
                handleInput = function() count("modalInput"); return true end,
            }),
            ["systems.TutorialManager"] = mock({ isActive = function() return state.tutorial end }),
            ["ui.battle.popup.TerminalConfirmDialog"] = mock({ isOpen = function() return state.terminal end }),
            ["ui.hud.popup.OfflineRewardPanel"] = mock({ isOpen = function() return state.offline end }),
            ["ui.hud.popup.LevelUpPopup"] = mock({ isOpen = function() return state.levelup end }),
            ["ui.hud.popup.PlayerInfoPanel"] = mock({ isOpen = function() return state.playerinfo end }),
            ["ui.hud.popup.UpdateNoticePopup"] = mock({ isOpen = function() return state.updateNotice end }),
            ["ui.story.gate.DarkTitleScreenGate"] = mock({ isOpen = function() return state.title end }),
            ["ui.story.gate.LetterIntro"] = mock({ isOpen = function() return state.letter end }),
            ["ui.story.gate.IntroCutscene"] = mock({ isActive = function() return state.intro end }),
            ["ui.story.ScenarioDialogue"] = mock({ isActive = function() return state.dialogue end }),
            ["ui.dev.CEPanel"] = mock({ isOpen = function() return state.ce end }),
            ["ui.battle.stage.SweepDialog"] = mock({ isOpen = function() return state.sweep end }),
            ["ui.battle.popup.DamageStatsPanel"] = mock({ isOpen = function() return state.damage end }),
            ["ui.battle.stage.StageSelectDialog"] = mock({ isOpen = function() return state.stage end }),
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
                or name == "boot.SeamBackGesture" or name == "boot.DecomposeMarqueeGesture"
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
            cursor.x = (RT.frameOx or 0) + (note.ox + p.bx * note.s + x * note.s * viewport.DS) * (RT.frameScale or 1)
            cursor.y = (RT.frameOy or 0) + (note.oy + p.by * note.s + y * note.s * viewport.DS) * (RT.frameScale or 1)
            cursor.x, cursor.y = cursor.x * RT.dpr, cursor.y * RT.dpr
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
            for _, key in ipairs({ "decompose", "marquee", "autoPopup", "setFilter", "itemDetail", "closing",
                "offline", "levelup", "playerinfo", "updateNotice", "title", "letter", "intro", "dialogue",
                "ce", "sweep", "damage", "stage", "terminal" }) do state[key] = false end
            state.beginAccepted, state.nav = true, 3
            marqueeCoords = { begin = {}, move = {}, finish = {} }
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

            local function downMarquee()
                state.decompose = true
                position("left", 140, 1060)
                HandleMouseButtonDownHorizon("MouseButtonDown", right)
                check(state.marquee and n("marqueeBegin") == 1, prefix .. "右键Down成功独占框选")
                local point = marqueeCoords.begin[1] or {}
                check(math.abs((point.x or -1) - 140) < 0.00001 and math.abs((point.y or -1) - 1060) < 0.00001,
                    prefix .. "Begin使用原左栏设计坐标")
            end
            local function exclusive(label)
                noEquipmentSend(prefix .. label)
                check(n("backpackInput") == 0 and n("backpackRight") == 0 and n("backpackMove") == 0
                    and n("characterInput") == 0 and n("characterRight") == 0 and n("characterMove") == 0
                    and n("arm") == 0 and n("finish") == 0,
                    prefix .. label .. " 不穿透格点击/装备/角色/滚动拖拽")
            end
            -- 移动/释放直接落在别栏：不能重新 resolve 到右栏局部坐标。
            for _, target in ipairs({ "center", "right" }) do
                fixture(tri); downMarquee()
                position(target, 180, 1110)
                local origin = viewport.getNote("left")
                local winX = (cursor.x / RT.dpr - (RT.frameOx or 0)) / (RT.frameScale or 1)
                local winY = (cursor.y / RT.dpr - (RT.frameOy or 0)) / (RT.frameScale or 1)
                local expectedX = (winX - origin.ox) / (origin.s * viewport.DS)
                local expectedY = (winY - origin.oy) / (origin.s * viewport.DS)
                HandleMouseMoveHorizon("MouseMove", {})
                HandleEquipmentHoverTickHorizon()
                HandleMouseWheelHorizon("MouseWheel", { Wheel = { GetInt = function() return -1 end } })
                check(n("marqueeMove") == 1 and n("backpackHover") == 0 and n("characterHover") == 0
                    and n("backpackScroll") == 0, prefix .. "框选独占Move/hoverTick/滚轮 " .. target)
                HandleMouseButtonUpHorizon("MouseButtonUp", right)
                local moved, ended = marqueeCoords.move[1] or {}, marqueeCoords.finish[1] or {}
                for _, point in ipairs({ moved, ended }) do
                    check(math.abs((point.x or -1) - expectedX) < 0.00001
                        and math.abs((point.y or -1) - expectedY) < 0.00001,
                        prefix .. "跨" .. target .. "Move/End捕获原左栏坐标（非目标栏180）")
                end
                check(n("marqueeEnd") == 1 and not state.marquee, prefix .. "跨栏右键Up仅结束一次")
                exclusive("跨栏释放")
                position("left", 140, 1060)
                HandleEquipmentHoverTickHorizon()
                check(n("backpackHover") == 1, prefix .. "释放后恢复hover")
            end

            fixture(tri)
            RT.dpr, RT.frameScale, RT.frameOx, RT.frameOy = 2, 0.8, 37, 23
            downMarquee()
            position("left", 190, 1110); HandleMouseMoveHorizon("MouseMove", {})
            HandleMouseButtonUpHorizon("MouseButtonUp", right)
            local highDpi = marqueeCoords.finish[1] or {}
            check(n("marqueeEnd") == 1 and math.abs((highDpi.x or -1) - 190) < 0.00001
                and math.abs((highDpi.y or -1) - 1110) < 0.00001,
                prefix .. "DPR2+宿主frame缩放偏移稳定时设计坐标正确")
            exclusive("稳定DPR2框选")

            -- 八类全局模态分别从真实读取点观察；恢复后旧Up仍不能提交。
            for _, blocked in ipairs({ "modal", "offline", "levelup", "playerinfo", "updateNotice",
                "title", "letter", "intro", "dialogue", "ce", "sweep", "damage", "stage", "terminal",
                "tutorial", "task", "loot", "autoPopup", "setFilter", "itemDetail", "closing" }) do
                fixture(tri); downMarquee()
                state[blocked] = true
                HandleEquipmentHoverTickHorizon() -- 无Move的瞬时modal同样永久取消。
                check(not state.marquee and n("marqueeCancel") > 0, prefix .. blocked .. " 出现即取消")
                state[blocked] = false
                position("right", 140, 1060)
                HandleMouseMoveHorizon("MouseMove", {})
                HandleEquipmentHoverTickHorizon()
                check(n("marqueeMove") == 0 and n("backpackHover") == 0 and n("characterHover") == 0,
                    prefix .. blocked .. " 关闭后仍独占且不复活Move/hover")
                HandleMouseButtonUpHorizon("MouseButtonUp", right)
                check(n("marqueeEnd") == 0, prefix .. blocked .. " 旧Up消费且不提交")
                exclusive(blocked .. "取消")
                -- Up后下一次明确右键Down才可以重新开始，不保留取消锁。
                position("left", 140, 1060)
                HandleMouseButtonDownHorizon("MouseButtonDown", right)
                check(state.marquee and n("marqueeBegin") == 2, prefix .. blocked .. " 新Down可重新开始")
                HandleMouseButtonUpHorizon("MouseButtonUp", right)
                check(n("marqueeEnd") == 1, prefix .. blocked .. " 新Up提交一次")
            end
            -- 宿主/页面身份变化即使恢复原值，也不能让旧按压复活。
            for _, change in ipairs({ "warehouse", "leftMode", "decompose", "tri", "width", "height", "dpr",
                "frameScale", "frameOx", "frameOy", "hostScale", "hostOx", "hostOy", "moduleCancel" }) do
                fixture(tri); downMarquee()
                local restore = function() end
                if change == "warehouse" or change == "leftMode" or change == "decompose" then
                    state[change] = false; restore = function() state[change] = true end
                elseif change == "tri" then
                    state.tri = not tri; restore = function() state.tri = tri end
                elseif change == "moduleCancel" then
                    warehouse.cancelMarquee()
                elseif change == "hostScale" then
                    local old = H_s; H_s = H_s + 0.1; restore = function() H_s = old end
                elseif change == "hostOx" then
                    local old = H_ox; H_ox = H_ox + 10; restore = function() H_ox = old end
                elseif change == "hostOy" then
                    local old = H_oy; H_oy = H_oy + 10; restore = function() H_oy = old end
                else
                    local key = change == "width" and "logicalW" or change == "height" and "logicalH" or change
                    local old = RT[key]
                    RT[key] = change == "dpr" and 2 or change == "frameScale" and 0.8 or (old or 0) + 10
                    restore = function() RT[key] = old end
                end
                HandleEquipmentHoverTickHorizon()
                restore()
                check(not state.marquee, prefix .. change .. " 观察变化后取消")
                position("right", 180, 1110); HandleMouseMoveHorizon("MouseMove", {})
                HandleMouseButtonUpHorizon("MouseButtonUp", right)
                check(n("marqueeMove") == 0 and n("marqueeEnd") == 0,
                    prefix .. change .. " 恢复旧尺寸/页面仍不复活")
                exclusive(change)
            end

            fixture(tri); downMarquee()
            HandleMouseButtonDownHorizon("MouseButtonDown", left)
            check(not state.marquee, prefix .. "其他按钮取消框选不启动别的手势")
            HandleMouseButtonUpHorizon("MouseButtonUp", left)
            position("right", 180, 1110); HandleMouseMoveHorizon("MouseMove", {})
            HandleMouseButtonUpHorizon("MouseButtonUp", right)
            check(n("marqueeEnd") == 0 and n("marqueeMove") == 0, prefix .. "非右键Up不释放旧右键消费权")
            exclusive("其他按钮取消")

            fixture(tri); state.decompose, state.beginAccepted = true, false
            realDownUp("left", 140, 1060, clock, right)
            check(n("marqueeBegin") == 1 and n("marqueeMove") == 0 and n("marqueeEnd") == 0,
                prefix .. "Begin返回false不启动捕获")
            check(n("backpackRight") == 1 and n("apiRight") == 1,
                prefix .. "Begin失败保留原右键fallback且只调用一次")

            -- 真实触摸处理器将原语义派成左键；不能用鼠标right冒充触摸。
            local function touchData(id)
                return { X = { GetInt = function() return cursor.x end },
                    Y = { GetInt = function() return cursor.y end },
                    TouchID = { GetInt = function() return id end } }
            end
            fixture(tri); state.decompose = true
            position("left", 140, 1060)
            HandleTouchBeginHorizon("TouchBegin", touchData(71))
            HandleTouchEndHorizon("TouchEnd", touchData(71))
            check(n("backpackInput") == 1 and n("apiClick") == 1 and n("marqueeBegin") == 0,
                prefix .. "原触摸短按仍走左键tap而非框选")
            fixture(tri); state.decompose, state.dragging = true, true
            position("left", 140, 1060); HandleTouchBeginHorizon("TouchBegin", touchData(72))
            position("left", 190, 1110); HandleTouchMoveHorizon("TouchMove", touchData(72))
            HandleTouchEndHorizon("TouchEnd", touchData(72))
            check(n("arm") == 1 and n("finish") == 1 and n("dragMove") == 1 and n("marqueeBegin") == 0,
                prefix .. "原触摸拖拽仍按原arm/move/finish")
            check(n("backpackInput") == 0, prefix .. "原触摸拖拽不伪tap")
            fixture(tri); downMarquee()
            position("left", 140, 1060); HandleTouchBeginHorizon("TouchBegin", touchData(73))
            HandleTouchEndHorizon("TouchEnd", touchData(73))
            position("right", 180, 1110); HandleMouseButtonUpHorizon("MouseButtonUp", right)
            check(n("marqueeEnd") == 0 and n("backpackInput") == 0 and n("arm") == 0,
                prefix .. "框选遇触摸取消但旧右键Up仍消费")
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
