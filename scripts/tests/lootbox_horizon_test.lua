-- 横屏遗匣路由回归：用内存窗口/输入替身驱动真实宿主事件函数。
function Start()
    local originalRequire = require
    local originalInput, originalTime = input, time
    local cursor = { x = 180, y = 400 }
    input = { GetMousePosition = function() return cursor end }
    time = { elapsedTime = 100 }
    local counters = { loot = 0, bag = 0, right = 0, reward = 0, close = 0, click = 0 }
    local globalReward = false
    local pageOpen = true
    local function noop() return false end
    local function mock(values)
        return setmetatable(values or {}, { __index = function() return noop end })
    end
    local mods = {
        ["boot.StandaloneRT"] = { logicalW = 1920, logicalH = 1080, dpr = 1, bootReady_ = true },
        ["ui.battle.tri.BattleTriPage"] = mock({
            isOpen = function() return true end,
            handleScroll = function(_, wx)
                if not wx or wx < 486 or wx > 1434 then return false end
                counters.bag = counters.bag + 1
                return true
            end,
        }),
        ["ui.loot.LootBoxPage"] = mock({
            isOpen = function() return pageOpen end,
            getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
            close = function() counters.close = counters.close + 1 pageOpen = false end,
        }),
        ["ui.loot.LootBox"] = mock({
            handleScroll = function() counters.loot = counters.loot + 1 return true end,
            handleInput = function() counters.click = counters.click + 1 return true end,
        }),
        ["ui.character.panel.CharacterPanel"] = mock({
            handleScroll = function() counters.right = counters.right + 1 end,
        }),
        ["ui.hud.popup.RewardPopup"] = mock({
            isOpen = function() return globalReward end,
            currentRowTag = function() return nil end,
            handleScroll = function() counters.reward = counters.reward + 1 return true end,
        }),
        ["core.DrawUtil"] = mock({
            SEAMBAR_ASPECT = 0.04,
            seamSlideX = function() return 0 end,
        }),
    }
    require = function(name)
        if name == "core.Viewport" then return originalRequire(name) end
        if not mods[name] then mods[name] = mock() end
        return mods[name]
    end
    package.loaded["boot.StandaloneHorizon"] = nil
    originalRequire("boot.StandaloneHorizon")
    require = originalRequire
    local wheel = { Wheel = { GetInt = function() return -1 end } }
    HandleMouseWheelHorizon("MouseWheel", wheel)
    assert(counters.loot == 1 and counters.bag == 0, "左栏滚轮不能被装备袋抢走")
    cursor.x = 1700
    HandleMouseWheelHorizon("MouseWheel", wheel)
    assert(counters.right == 1 and counters.loot == 1 and counters.bag == 0, "右栏滚轮不影响遗匣")
    cursor.x = 900
    HandleMouseWheelHorizon("MouseWheel", wheel)
    assert(counters.bag == 1, "中栏装备袋仍可滚动")
    globalReward = true
    HandleMouseWheelHorizon("MouseWheel", wheel)
    assert(counters.reward == 1 and counters.bag == 1, "全局奖励滚轮优先于装备袋")
    globalReward = false

    local button = { Button = { GetInt = function() return MOUSEB_LEFT end } }
    cursor.x, cursor.y = 200, 400
    HandleMouseButtonDownHorizon("MouseButtonDown", button)
    time.elapsedTime = 101
    HandleMouseButtonUpHorizon("MouseButtonUp", button)
    assert(counters.click == 1, "左栏点击交给遗匣")
    cursor.x = 200
    HandleMouseButtonDownHorizon("MouseButtonDown", button)
    cursor.x = 1700
    HandleMouseMoveHorizon("MouseMove", {})
    time.elapsedTime = 102
    HandleMouseButtonUpHorizon("MouseButtonUp", button)
    assert(counters.click == 1, "跨栏释放不得误触遗匣")

    -- 1920×1080 时左栏右缘486，中缝中心507.6（窗口坐标）。
    cursor.x, cursor.y = 507.6, 540
    HandleMouseButtonDownHorizon("MouseButtonDown", button)
    time.elapsedTime = 103
    HandleMouseButtonUpHorizon("MouseButtonUp", button)
    assert(counters.close == 1 and not pageOpen, "中缝返回按窗口坐标正确关闭")
    input, time = originalInput, originalTime
    print("[lootbox_horizon_test] 跨栏滚轮、全局优先、点击、拖拽、中缝返回全部通过")
end
