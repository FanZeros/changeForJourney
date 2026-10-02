-- 角色拖拽跨栏释放回归：宿主必须取消拖拽，不能把落点误当编队槽。
function Start()
    local originalRequire = require
    local originalInput, originalTime = input, time
    local cursor = { x = 1400, y = 400 }
    input = { GetMousePosition = function() return cursor end }
    time = { elapsedTime = 100 }
    local dragging, armed = false, false
    local drops, cancels = 0, 0
    local function noop() return false end
    local function mock(values)
        return setmetatable(values or {}, { __index = function() return noop end })
    end
    local mods = {
        ["ui.character.panel.CharacterPanel"] = mock({
            isDraggingCard = function() return dragging end,
            handleDragBegin = function() armed = true end,
            handleDragMove = function() if armed then dragging = true end end,
            handleInput = function(x, y)
                if dragging and x >= 0 and y >= 0 then drops = drops + 1 end
                dragging = false
                return true
            end,
            handleDragEnd = function()
                if armed then cancels = cancels + 1 end
                armed, dragging = false, false
            end,
        }),
    }
    local RT = originalRequire("boot.StandaloneRT")
    local savedRT = {}
    for k, v in pairs(RT) do savedRT[k] = v end
    RT.logicalW, RT.logicalH, RT.dpr, RT.bootReady_ = 1920, 1080, 1, true
    require = function(name)
        if name == "boot.StandaloneRT" then return RT end
        if name == "core.Viewport" or name == "boot.StandaloneHorizonInput"
            or name == "boot.OfflineRewardOverlay" then return originalRequire(name) end
        if not mods[name] then mods[name] = mock() end
        return mods[name]
    end
    package.loaded["boot.StandaloneHorizon"] = nil
    originalRequire("boot.StandaloneHorizon")
    require = originalRequire
    local viewport = originalRequire("core.Viewport")
    H_ox, H_oy, H_s = viewport.layout(1920, 1080)
    local button = { Button = { GetInt = function() return MOUSEB_LEFT end } }
    local function beginDrag()
        cursor.x = 1400
        HandleMouseButtonDownHorizon("MouseButtonDown", button)
        cursor.x = 1420
        HandleMouseMoveHorizon("MouseMove", {})
        assert(dragging, "右栏拖拽应正常开始")
    end
    beginDrag()
    cursor.x = 180
    HandleMouseButtonUpHorizon("MouseButtonUp", button)
    assert(not dragging and not armed and drops == 0, "左栏释放应取消拖拽且不修改编队")
    beginDrag()
    cursor.x = 10
    HandleMouseButtonUpHorizon("MouseButtonUp", button)
    assert(not dragging and not armed and drops == 0, "面板外释放应取消拖拽")
    beginDrag()
    cursor.x = 1420
    HandleMouseButtonUpHorizon("MouseButtonUp", button)
    assert(not dragging and not armed and drops == 1, "右栏正常释放应交给角色面板")
    assert(cancels == 3, "每次拖拽均结束且不残留状态")
    input, time = originalInput, originalTime
    for k in pairs(RT) do RT[k] = nil end
    for k, v in pairs(savedRT) do RT[k] = v end
    print("[character_drag_horizon_test] ALL PASS: outside cancel, right drop")
    engine:Exit()
end
