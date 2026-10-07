-- 浮选装备详情拖拽回归：详情开着时按下空白，应关闭详情并把拖拽下放给底层页面；
-- 松开时不按 tap 派发点击（防误触页面按钮）；详情关闭后正常 tap 不受影响。
function Start()
    local originalRequire = require
    local originalInput, originalTime = input, time
    local cursor = { x = 200, y = 400 }
    input = { GetMousePosition = function() return cursor end }
    time = { elapsedTime = 100 }

    local counters = { close = 0, dragBegin = 0, dragMove = 0, dragEnd = 0, click = 0 }
    local detailOpen = true  -- 浮选详情（compact corner）初始开着

    local function noop() return false end
    local function mock(values)
        return setmetatable(values or {}, { __index = function() return noop end })
    end

    local mods = {
        ["boot.StandaloneRT"] = { logicalW = 1920, logicalH = 1080, dpr = 1, bootReady_ = true },
        ["ui.battle.tri.BattleTriPage"] = mock({
            isOpen = function() return true end,
        }),
        ["ui.loot.LootBoxPage"] = mock({
            isOpen = function() return true end,
            getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
        }),
        ["ui.loot.LootBox"] = mock({
            handleDragBegin = function() counters.dragBegin = counters.dragBegin + 1 return true end,
            handleDragMove = function() counters.dragMove = counters.dragMove + 1 return true end,
            handleDragEnd = function() counters.dragEnd = counters.dragEnd + 1 return true end,
            handleInput = function() counters.click = counters.click + 1 return true end,
        }),
        ["ui.character.equip.EquipmentDetail"] = mock({
            isCompactCorner = function() return detailOpen end,
            isOpen = function() return detailOpen end,
            containsPoint = function() return false end,
            getOwner = function() return "backpack" end,
            close = function()
                if detailOpen then
                    detailOpen = false
                    counters.close = counters.close + 1
                end
            end,
        }),
        ["ui.character.EquipCrossDrag"] = mock({
            isArmed = function() return false end,
        }),
        ["core.DrawUtil"] = mock({
            SEAMBAR_ASPECT = 0.04,
            SEAMBAR_ARROW_Y = 0.469,
            seamSlideX = function() return 0 end,
        }),
    }

    local RT = originalRequire("boot.StandaloneRT")
    local originalRT = {}
    for key, value in pairs(RT) do originalRT[key] = value end
    for key, value in pairs(mods["boot.StandaloneRT"]) do RT[key] = value end
    require = function(name)
        if name == "core.Viewport" or name == "boot.StandaloneHorizonInput"
            or name == "boot.OfflineRewardOverlay" or name == "boot.DecomposeMarqueeGesture"
            or name == "boot.StandaloneHorizonWheel" then return originalRequire(name) end
        if name == "boot.StandaloneRT" then return RT end
        if not mods[name] then mods[name] = mock() end
        return mods[name]
    end
    -- [注意] Horizon 在事件函数体内运行时才 require EquipmentDetail，
    -- 而引擎 require 不读 package.loaded，所以 require 钩子必须保持到事件派发结束
    package.loaded["boot.StandaloneHorizon"] = nil
    originalRequire("boot.StandaloneHorizon")
    local viewport = originalRequire("core.Viewport")
    H_ox, H_oy, H_s = viewport.layout(1920, 1080)

    local button = { Button = { GetInt = function() return MOUSEB_LEFT end } }

    -- 场景 A1：详情开着，按下空白（同位置松开，未移动）
    --   期望：详情被关闭；按下下放给页面（dragBegin）；松开不派发点击（tap 抑制）
    cursor.x, cursor.y = 200, 400
    HandleMouseButtonDownHorizon("MouseButtonDown", button)
    assert(counters.close == 1, "A1: 按下空白应关闭浮选详情")
    assert(not detailOpen, "A1: 详情应已关闭")
    assert(counters.dragBegin == 1, "A1: 按下应下放给页面 dragBegin（修复前被吞掉）")
    time.elapsedTime = 101
    HandleMouseButtonUpHorizon("MouseButtonUp", button)
    assert(counters.click == 0, "A1: 关详情的松开不得误触页面点击")

    -- 场景 A2：详情关闭动画期间再按下并拖动（详情已关，走正常路由）
    --   期望：dragBegin/dragMove 正常，列表可拖
    detailOpen = true
    counters.dragBegin, counters.dragMove = 0, 0
    cursor.x, cursor.y = 200, 400
    HandleMouseButtonDownHorizon("MouseButtonDown", button)
    assert(counters.close == 2, "A2: 第二次按下也应关闭详情")
    assert(counters.dragBegin == 1, "A2: 按下下放 dragBegin")
    cursor.y = 440
    HandleMouseMoveHorizon("MouseMove", {})
    assert(counters.dragMove == 1, "A2: 移动应驱动页面 dragMove（修复前无法拖拽）")
    time.elapsedTime = 102
    HandleMouseButtonUpHorizon("MouseButtonUp", button)
    assert(counters.click == 0, "A2: 拖动后松开不派发点击")

    -- 场景 B：详情已关，正常 tap 不受 detailDismissPress 残留影响
    detailOpen = false
    counters.click = 0
    cursor.x, cursor.y = 200, 400
    HandleMouseButtonDownHorizon("MouseButtonDown", button)
    time.elapsedTime = 103
    HandleMouseButtonUpHorizon("MouseButtonUp", button)
    assert(counters.click == 1, "B: 详情关闭后正常 tap 应派发页面点击")
    assert(counters.close == 2, "B: 无详情按下不应触发 close")

    require = originalRequire
    input, time = originalInput, originalTime
    for key in pairs(RT) do RT[key] = nil end
    for key, value in pairs(originalRT) do RT[key] = value end
    print("[equip_detail_drag_horizon_test] PASS: 详情关闭+拖拽下放+tap抑制+正常tap恢复")
    engine:Exit()
end
