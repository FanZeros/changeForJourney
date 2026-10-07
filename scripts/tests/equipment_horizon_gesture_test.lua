-- 配装横屏手势回归：调用真实 Horizon / CharacterDetail，其他页面与浮选详情 mock。
-- 覆盖跨栏同局部坐标、归属右栏奖励遮挡、浮选拖拽释放、关闭浮选首击槽位/页签。
function Start()
    local originalRequire = require
    local originalInput, originalTime = input, time
    local RT = originalRequire("boot.StandaloneRT")
    local viewport = originalRequire("core.Viewport")
    local originalRT, originalNotes = {}, viewport._notes
    for key, value in pairs(RT) do originalRT[key] = value end

    local assertions = 0
    local ok, err = pcall(function()
        local function check(condition, message)
            assertions = assertions + 1
            assert(condition, message)
        end
        local function noop() return false end
        ---@return any
        local function mock(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local calls = {}
        local function count(name)
            calls[name] = (calls[name] or 0) + 1
        end
        local function n(name) return calls[name] or 0 end
        ---@type any
        local state = {
            tri = true, reward = false, detailOpen = false, detailDragging = false,
            warehouseOpen = true, slot = nil, candidate = false, pinned = false,
        }
        ---@type any
        local drawState = {}
        ---@type any
        local detail = {}
        local cursor = { x = 0, y = 0 }
        input = { GetMousePosition = function() return cursor end }
        time = { elapsedTime = 100 }
        local clock = 100
        for key in pairs(RT) do RT[key] = nil end
        RT.logicalW, RT.logicalH, RT.dpr, RT.bootReady_ = 1920, 1080, 1, true
        viewport._notes = {}

        local keyword = { clear = noop, isOpen = noop, handleInput = noop }
        local draw = mock({
            talentKwText = keyword,
            DT_SLOT_SIZE = 160,
            DT_SLOTS = {
                { slot = "helmet", cx = 540, cy = 185 },
                { slot = "weapon", cx = 325, cy = 578 },
            },
            BTN_TAB_SLIDER_W = 180, BTN_TAB_SLIDER_H = 140,
            BTN_TAB_ATTR_CX = 255, BTN_TAB_ATTR_CY = 2308,
            BTN_TAB_EQUIP_CX = 445, BTN_TAB_EQUIP_CY = 2308,
            BTN_TAB_CLASS_CX = 635, BTN_TAB_CLASS_CY = 2308,
            BTN_TAB_AWAKEN_CX = 825, BTN_TAB_AWAKEN_CY = 2308,
            BTN_BACK_CX = 122, BTN_BACK_CY = 1150, BTN_BACK_W = 184, BTN_BACK_H = 143,
            BTN_UNEQUIP_CX = 211, BTN_UNEQUIP_CY = 105,
            BTN_EQUIP_CX = 869, BTN_EQUIP_CY = 105, BTN_BATCH_W = 304, BTN_BATCH_H = 100,
            SIDE_CARD_W = 180, SIDE_CARD_H = 300, ARROW_CY = 500,
            ARROW_BG_LEFT_CX = 300, ARROW_BG_RIGHT_CX = 780,
            ATTR_BOX_W = 440, ATTR_BOX_H = 60, ATTR_ROW_GAP = 9,
            ATTR_CLIP_TOP = 1264, ATTR_CLIP_HEIGHT = 552,
            setContext = function(ctx) drawState = ctx.detailState end,
        })
        local equipPanel = mock({
            -- 无装备候选，不 arm EquipCrossDrag：测的是普通属性/仓库滚动跨栏释放。
            peekSlotEquipAt = function() return nil end,
            peekItemAt = function() return nil end,
            isAttributeTogglePoint = function(x, y)
                return x >= 390 and x <= 690 and y >= 894 and y <= 962
            end,
            containsComparisonPoint = function(x, y)
                return (x >= 54 and x <= 532 and y >= 1068 and y <= 1688)
                    or (x >= 390 and x <= 690 and y >= 894 and y <= 962)
            end,
            handleInput = function(x, y)
                if x >= 390 and x <= 690 and y >= 894 and y <= 962 then
                    count("attributeToggle"); return true
                end
                return false
            end,
            handleDragBegin = function(x, y)
                return x >= 54 and x <= 532 and y >= 1068 and y <= 1688
            end,
            handleDragMove = function() count("comparisonMove"); return true end,
            handleDragEnd = function() count("comparisonEnd"); return true end,
        })
        local equipmentDetail = mock({
            isOpen = function() return state.detailOpen end,
            isCompactCorner = function() return state.detailOpen end,
            isPinned = function() return state.detailOpen end,
            getOwner = function() return "backpack" end,
            -- 可浮出仓库的详情矩形；右栏槽位/底部页签不在其命中区域内。
            containsPoint = function(x, y)
                return state.detailOpen and x >= 700 and x <= 1000 and y >= 1400 and y <= 1700
            end,
            close = function() state.detailOpen = false; count("detailClose") end,
            handleDragBegin = function()
                state.detailDragging = true; count("overlayBegin"); return true
            end,
            handleDragMove = function() count("overlayMove"); return true end,
            handleDragEnd = function()
                state.detailDragging = false; count("overlayEnd"); return true
            end,
            handleInput = function()
                check(not state.detailDragging, "浮选必须先 End 再派发 Input")
                count("overlayInput"); return true
            end,
        })
        local warehouse = mock({
            isOpen = function() return state.warehouseOpen end,
            isLeftMode = function() return true end,
            getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
            peekEquipAt = function(x, y)
                if state.candidate and x >= 80 and x <= 200 and y >= 1000 and y <= 1120 then
                    return { seq = 7, slot = "helmet" }
                end
                return nil
            end,
            acquireForEquipment = function(_, slot) state.slot = slot; count("acquire") end,
            releaseForEquipment = function() state.slot = nil; count("release") end,
            setEquipmentSlotFilter = function(slot) state.slot = slot; count("filter") end,
            handleDragBegin = function() count("warehouseBegin"); return true end,
            handleDragMove = function() count("warehouseMove"); return true end,
            handleDragEnd = function() count("warehouseEnd"); return true end,
            handleInput = function(x, y)
                count("warehouseInput")
                if state.candidate and x >= 80 and x <= 200 and y >= 1000 and y <= 1120 then
                    state.pinned, state.detailOpen = true, true
                    count("pin")
                end
                return true
            end,
        })
        local mods = {
            ["boot.StandaloneRT"] = RT,
            ["core.Viewport"] = viewport,
            ["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 } },
            ["config.HeroConfig"] = { get = function(id) return { name = tostring(id) } end },
            ["ui.character.detail.CharacterDetailDraw"] = draw,
            ["ui.character.detail.CharacterDetailAttrs"] = mock({ STAT_LAYOUT = {} }),
            ["ui.character.detail.CharacterDetailEquip"] = equipPanel,
            ["ui.character.equip.EquipmentDetail"] = equipmentDetail,
            ["ui.character.hero.AwakeningPanel"] = mock({ kwText = keyword }),
            ["ui.backpack.BackpackPanel"] = warehouse,
            ["ui.battle.tri.BattleTriPage"] = mock({ isOpen = function() return state.tri end }),
            ["ui.hud.BottomNav"] = { getSelectedIndex = function() return 3 end },
            ["ui.hud.popup.RewardPopup"] = mock({
                isOpen = function() return state.reward end,
                currentPanel = function() return "right" end,
                currentRowTag = function() return nil end,
                handleDragBegin = function() count("rewardBegin"); return true end,
                handleDragEnd = function() count("rewardEnd"); return true end,
                handleInput = function() count("rewardInput"); return true end,
            }),
            ["ui.character.EquipCrossDrag"] = mock({ isArmed = function() return false end }),
            ["ui.character.panel.CharacterPanel"] = mock({
                getOwnedHero = function() return { level = 1 } end,
                isDraggingCard = function() return false end,
                handleDragBegin = function(x, y)
                    count("characterBegin"); return detail.handleDragBegin(x, y)
                end,
                handleDragMove = function(x, y) return detail.handleDragMove(x, y) end,
                handleDragEnd = function(x, y)
                    count("characterEnd"); return detail.handleDragEnd(x, y)
                end,
                handleInput = function(x, y)
                    count("characterInput"); return detail.handleInput(x, y)
                end,
            }),
            ["runtime.GameAction"] = mock({ sendAction = function() count("action") end }),
            ["core.DrawUtil"] = mock({
                SEAMBAR_ASPECT = 0.04, SEAMBAR_ARROW_Y = 0.469,
                seamSlideX = function() return 0 end,
            }),
        }
        require = function(name)
            if name == "boot.StandaloneHorizonInput" or name == "boot.OfflineRewardOverlay"
                or name == "boot.SeamBackGesture" or name == "boot.DecomposeMarqueeGesture"
                or name == "boot.StandaloneHorizonWheel" then
                return originalRequire(name)
            end
            if not mods[name] then mods[name] = mock() end
            return mods[name]
        end
        -- 引擎 require 不依赖 package.loaded；钩子保持至所有事件结束。
        detail = originalRequire("ui.character.detail.CharacterDetail")
        mods["ui.character.detail.CharacterDetail"] = detail
        local slotTap, navigationTap = detail.handleEquipmentSlotTap, detail.handleNavigationTap
        detail.handleEquipmentSlotTap = function(x, y)
            count("slotHook"); return slotTap(x, y)
        end
        detail.handleNavigationTap = function(x, y)
            count("navigation"); return navigationTap(x, y)
        end
        detail.setContext({ getHeroRoster = function() return { { heroId = 1, owned = true } } end })
        originalRequire("boot.StandaloneHorizon")
        H_SEAM_BACK = true

        local button = { Button = { GetInt = function() return MOUSEB_LEFT end } }
        local function position(panel, x, y)
            local note = viewport.getNote(panel)
            local p = viewport.PANELS[panel]
            cursor.x = note.ox + p.bx * note.s + x * note.s * viewport.DS
            cursor.y = note.oy + p.by * note.s + y * note.s * viewport.DS
        end
        local function down(panel, x, y)
            position(panel, x, y)
            HandleMouseButtonDownHorizon("MouseButtonDown", button)
        end
        local function move(panel, x, y)
            position(panel, x, y)
            HandleMouseMoveHorizon("MouseMove", {})
        end
        local function up(panel, x, y)
            position(panel, x, y)
            clock = clock + 1
            time.elapsedTime = clock
            HandleMouseButtonUpHorizon("MouseButtonUp", button)
        end
        local function fixture(tri)
            state.tri, state.reward, state.detailOpen, state.detailDragging = tri, false, false, false
            state.warehouseOpen, state.candidate, state.pinned = true, false, false
            H_ox, H_oy, H_s = viewport.layout(1920, 1080)
            if tri then
                viewport.note("left", 0, 0, 1)
                viewport.note("right", 1920 - 486 - 972, 0, 1)
            else
                viewport.note("left", H_ox, H_oy, H_s)
                viewport.note("right", H_ox, H_oy, H_s)
            end
            viewport.note("center", H_ox, H_oy, H_s)
            detail.forceClose()
            detail.open(1, "equip")
            slotTap(540, 185)
            for key in pairs(calls) do calls[key] = nil end
        end

        -- A：普通列表拖拽，两栏局部 (100,1300) 完全相同但屏幕位移很大。
        -- 三行右栏贴屏幕右缘与常规 Viewport 两种布局都不能判 tap / 清部位。
        for _, tri in ipairs({ true, false }) do
            fixture(tri)
            down("left", 100, 1300)
            local startX = cursor.x
            up("right", 100, 1300)
            check(math.abs(cursor.x - startX) > 400, "A: 测试必须是真正跨栏而非原地点击")
            check(n("characterInput") == 0 and n("slotHook") == 0, "A: 左起右落同局部坐标不得 tap / slot clear")
            check(state.slot == "helmet" and n("filter") == 0, "A: 跨栏松手保留头盔筛选")
            check(n("warehouseEnd") > 0, "A: 左栏来源必须结束拖拽")

            fixture(tri)
            down("right", 100, 1300)
            up("left", 100, 1300)
            check(n("warehouseInput") == 0 and n("slotHook") == 0, "A: 右起左落不得伪装仓库点击")
            check(n("comparisonEnd") == 1 and not drawState.equipDragging, "A: 右栏滚动必须释放来源状态")
            check(state.slot == "helmet", "A: 反向跨栏释放也不清部位")
        end

        -- B：归属右栏 RewardPopup 返回 pid=right，但不得穿透预 slot / navigation hook。
        fixture(true)
        state.reward = true
        down("right", 100, 1300)
        up("right", 100, 1300)
        check(n("rewardBegin") == 1 and n("rewardEnd") == 1 and n("rewardInput") == 1, "B: 右栏奖励应收到正常 tap")
        check(n("slotHook") == 0 and n("filter") == 0 and state.slot == "helmet", "B: 奖励点击不能清部位")
        check(n("characterInput") == 0, "B: 奖励点击不能穿透角色页")
        state.detailOpen = true
        down("right", 255, 2308)
        up("right", 255, 2308)
        check(n("detailClose") == 1, "B: 覆盖层场景确实经历浮选 dismiss 分支")
        check(n("navigation") == 0 and n("slotHook") == 0 and drawState.tab == "equip", "B: 奖励遮挡时 dismiss 首击不能切页 / clear")

        -- C1：浮选内部起拖，跨栏离开浮选后松开，必须无条件 End。
        fixture(true)
        state.detailOpen = true
        down("left", 750, 1450)
        check(state.detailDragging and n("overlayBegin") == 1, "C1: 必须捕获真实浮选起拖分支")
        move("left", 800, 1500)
        up("right", 100, 1300)
        check(n("overlayMove") == 1 and n("overlayEnd") == 1 and not state.detailDragging, "C1: 浮选外释放也必须 End，不遗留 descDragging")
        check(n("overlayInput") == 0 and n("slotHook") == 0, "C1: 外部释放不得点击浮选或底层槽位")

        -- C2：内部大位移拖到按钮位置释放，不能将滚动误作按钮 Input。
        fixture(true)
        state.detailOpen = true
        down("left", 750, 1450)
        move("left", 900, 1640)
        up("left", 900, 1640)
        check(n("overlayEnd") == 1 and not state.detailDragging, "C2: 浮选内部拖拽释放必须 End")
        check(n("overlayInput") == 0, "C2: 浮选拖到按钮松开不得 Input")

        -- C3：正常 tap 保留；小于 15 逻辑屏幕像素的抖动不吞点击。
        fixture(true)
        state.detailOpen = true
        down("left", 900, 1640)
        up("left", 908, 1640)
        check(n("overlayBegin") == 1 and n("overlayEnd") == 1 and n("overlayInput") == 1, "C3: 正常浮选 tap 必须 End 后 Input 一次")
        check(n("warehouseInput") == 0 and n("slotHook") == 0, "C3: 浮选 tap 不得向底层派发")

        -- D：浮选外首击即导航真实 CharacterDetail 页签，仍不放行一般业务按钮。
        fixture(true)
        state.detailOpen = true
        down("right", 255, 2308)
        up("right", 255, 2308)
        check(n("detailClose") == 1 and n("navigation") == 1, "D: 首击关闭浮选并派发一次 navigation")
        check(drawState.tab == "attr" and not detail.isEquipTab() and n("release") == 1, "D: 首击已切属性并释放配装仓库")
        check(n("characterInput") == 0 and n("action") == 0, "D: dismiss 首击不能放行一般页面操作")

        fixture(true)
        slotTap(325, 578)
        for key in pairs(calls) do calls[key] = nil end
        state.detailOpen = true
        down("right", 540, 185)
        up("right", 540, 185)
        check(state.slot == "helmet" and n("filter") == 1, "D: 浮选外首击装备槽立即选部位")
        check(n("detailClose") == 1 and n("characterInput") == 0 and n("action") == 0, "D: 首击选槽不发送穿戴操作")

        -- D2：仓库 hover 后首击同格要 pin；空白/按钮没有 peek 则仍只关闭浮选。
        fixture(true)
        state.detailOpen, state.candidate = true, true
        down("left", 140, 1060)
        up("left", 140, 1060)
        check(n("detailClose") == 1 and n("warehouseInput") == 1 and n("pin") == 1 and state.pinned, "D2: hover 同格首击必须重新打开并 pin 一次")
        check(state.slot == "helmet" and n("slotHook") == 0 and n("action") == 0, "D2: pin 不清部位或发穿戴 action")
        fixture(true)
        state.detailOpen, state.candidate = true, true
        down("left", 300, 1060)
        up("left", 300, 1060)
        check(n("detailClose") == 1 and n("warehouseInput") == 0 and n("pin") == 0, "D2: 无装备格命中的 dismiss 首击不放行仓库按钮")

        -- F：标题首击属于比较内容，浮选保留、部位不清、没有实际穿装操作。
        for _, tri in ipairs({ true, false }) do
            fixture(tri)
            state.detailOpen = true
            down("right", 540, 930)
            up("right", 540, 930)
            check(n("attributeToggle") == 1 and n("characterInput") == 1,
                "F: 两种横屏布局标题首击均派发一次切换")
            check(state.detailOpen and n("detailClose") == 0 and state.slot == "helmet"
                and n("filter") == 0, "F: 标题切换保留钉住详情与装备部位")
            check(n("action") == 0, "F: 显示切换不发送穿戴操作")
        end

        -- 正常点击正向控制：右栏非槽 clear，左仓库点击保留右栏部位。
        fixture(true)
        down("left", 100, 1300)
        up("left", 100, 1300)
        check(n("warehouseInput") == 1 and state.slot == "helmet" and n("slotHook") == 0, "E: 左仓库正常点击保留右栏部位")
        down("right", 100, 1300)
        up("right", 100, 1300)
        check(state.slot == nil and n("filter") == 1, "E: 右栏有效非槽 tap 清部位")
        check(n("characterInput") == 1, "E: 普通 tap 不受上一手势状态残留影响")
    end)

    require, input, time = originalRequire, originalInput, originalTime
    viewport._notes = originalNotes
    for key in pairs(RT) do RT[key] = nil end
    for key, value in pairs(originalRT) do RT[key] = value end
    if ok then
        print("[equipment_horizon_gesture_test] ALL PASS: " .. assertions .. " assertions")
    else
        log:Write(LOG_ERROR, "[equipment_horizon_gesture_test] FAIL: " .. tostring(err))
    end
    engine:Exit()
end
