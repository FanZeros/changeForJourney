-- T01：真实 TopBar.draw / handleInput / hotspot 回归，真实 BottomNav 路由与锁。
-- 仅替换底层绘图和外围依赖为内存 spy；不加载主入口、玩家存档，不发送 action。
-- /workspace/.cli/UrhoXRuntime tests/topbar_dungeon_entry_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
function Start()
    ---@type fun(name: string): any
    local nativeRequire = require
    local originals = {}
    local assertions, failures, cases, frames = 0, 0, 0, 0
    local function check(value, label)
        assertions = assertions + 1
        if not value then
            failures = failures + 1
            print("[FAIL] topbar_dungeon_entry_test: " .. label)
        end
    end
    local function runCase(label, fn)
        cases = cases + 1
        local before = failures
        local ok, err = pcall(fn)
        if not ok then check(false, label .. " exception: " .. tostring(err)) end
        if failures == before then print("[PASS] " .. label) end
    end
    local ok, err = pcall(function()
        local function noop() end
        local state = { tri = true, triAvailable = true, triHasIsOpen = true, tutorial = true }
        local capture = { buttons = {}, icons = {}, labels = {}, hotspots = {}, sounds = {}, selections = {} }
        local function clearCapture()
            capture.buttons, capture.icons, capture.labels, capture.hotspots = {}, {}, {}, {}
            capture.sounds, capture.selections = {}, {}
        end
        local tri = { isOpen = function() return state.tri end }
        local mods = {
            ["core.GameState"] = {
                getLevel = function() return 1 end, getExp = function() return 0 end,
                getMaxExp = function() return 100 end, getPower = function() return 318 end,
                getGold = function() return 0 end, getGems = function() return 0 end,
            },
            ["core.NumberUtil"] = { format = tostring },
            ["ui.character.panel.CharacterPanel"] = { isOwned = function() return false end },
            ["config.HeroAssetUtil"] = { ensureIcon = function() return -1 end },
            ["config.HeroConfig"] = { getAllIds = function() return {} end },
            ["ui.widget.HeroFrame"] = { draw = noop },
            ["config.GameEvents"] = {}, ["core.EventBus"] = {},
            ["core.PlayerStore"] = { Get = function() return nil end },
            ["core.I18n"] = { t = function(key)
                if key == "tab_dungeon" then return "副本" end
                if key == "tab_battle" then return "战斗" end
                return key
            end },
            ["core.DarkIcon"] = {
                drawNine = function(_, style, x, y, w, h, options)
                    capture.buttons[#capture.buttons + 1] = {
                        style = style, x = x, y = y, w = w, h = h, options = options,
                    }
                end,
                draw = function(_, name, cx, cy, size, alpha)
                    capture.icons[#capture.icons + 1] = { name = name, cx = cx, cy = cy, size = size, alpha = alpha }
                end,
            },
            ["core.DrawUtil"] = { drawTextStroke = function(_, x, y, text, size, align, r, g, b, stroke, options)
                capture.labels[#capture.labels + 1] = {
                    x = x, y = y, text = text, size = size, align = align,
                    r = r, g = g, b = b, stroke = stroke, options = options,
                }
            end },
            ["systems.TutorialManager"] = {
                isActive = function() return state.tutorial end,
                registerHotspot = function(key, cx, cy, w, h, panel)
                    capture.hotspots[#capture.hotspots + 1] = { key = key, cx = cx, cy = cy, w = w, h = h, panel = panel }
                end,
            },
            ["systems.GameSFX"] = { playUIMove = function(index) capture.sounds[#capture.sounds + 1] = index end },
        }
        -- Runtime 资源 require 不保证遵循 package.preload；按仓库专项模式显式拦截外围依赖。
        require = function(name)
            if name == "ui.battle.tri.BattleTriPage" then
                if not state.triAvailable then error("test tri dependency unavailable") end
                return state.triHasIsOpen and tri or {}
            end
            return mods[name] or nativeRequire(name)
        end
        for _, name in ipairs({ "nvgBeginPath", "nvgRoundedRect", "nvgFillColor", "nvgFill",
            "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgText" }) do
            originals[name] = { value = rawget(_G, name) }
            rawset(_G, name, noop)
        end
        originals.nvgTextBounds = { value = rawget(_G, "nvgTextBounds") }
        rawset(_G, "nvgTextBounds", function() return 100 end)
        -- nvgRGBA 保留真实 NVGcolor，图片句柄未初始化且exp=0，不创建/读取图形资源。
        local Nav = nativeRequire("ui.hud.BottomNav")
        mods["ui.hud.BottomNav"] = Nav
        local setSelectedIndex = Nav.setSelectedIndex
        Nav.setSelectedIndex = function(index)
            capture.selections[#capture.selections + 1] = index
            setSelectedIndex(index)
        end
        local TopBar = nativeRequire("ui.hud.TopBar")
        local function fixture(triOpen)
            state.tri, state.triAvailable, state.triHasIsOpen, state.tutorial = triOpen, true, true, true
            Nav.setAllLocked(false)
            Nav.setTabLocked(3, false)
            Nav.setTabLocked(5, false)
            Nav.setSelectedIndex(3)
            Nav.setBadge(3, false)
            Nav.setBadge(5, false)
            clearCapture()
        end
        local function render(offset, hide)
            clearCapture()
            TopBar.draw({}, offset, hide)
            frames = frames + 1
        end
        local function navIcons()
            local found = {}
            for _, icon in ipairs(capture.icons) do
                if icon.name:match("^nav_") then found[#found + 1] = icon end
            end
            return found
        end
        local function tabLabels()
            local found = {}
            for _, label in ipairs(capture.labels) do
                if label.text == "副本" or label.text == "战斗" then found[#found + 1] = label end
            end
            return found
        end
        local function countIcon(name)
            local count = 0
            for _, icon in ipairs(capture.icons) do if icon.name == name then count = count + 1 end end
            return count
        end
        local function checkHotspot(index, key, cx, cy, panel, offset, hide)
            local hs = capture.hotspots[index]
            check(hs and hs.key == key and hs.cx == cx and hs.cy == cy
                and hs.w == 196 and hs.h == 64 and hs.panel == panel, "注册热点对应可见按钮与所属栏")
            local hx, hy, hw, hh = TopBar.getPageTabHotspot(key, offset, hide)
            check(hx == cx and hy == cy and hw == 196 and hh == 64,
                "热点查询必须同源绘制/输入，不将页码3/5当按钮序号")
            local button = capture.buttons[index]
            check(button and button.x == hx - hw * 0.5 and button.y == hy - hh * 0.5
                and button.w == hw and button.h == hh, "实际绘制矩形与查询/注册矩形一致")
        end
        local function checkNoNavigation(label)
            check(#capture.selections == 0 and #capture.sounds == 0, label .. " 不派发路由/音效")
        end

        runCase("三行左栏只绘制一个副本，复用旧词条图标样式", function()
            fixture(true)
            render(-30)
            local icons, labels = navIcons(), tabLabels()
            check(#capture.buttons == 1 and #icons == 1 and #labels == 1, "只画一个按钮、入口图标和标签")
            check(icons[1] and icons[1].name == "nav_dungeon" and icons[1].cx == 108
                and icons[1].cy == 206 and icons[1].size == 36 and icons[1].alpha == 1, "副本复用原图标与大小")
            check(labels[1] and labels[1].text == "副本" and labels[1].x == 108 and labels[1].y == 234
                and labels[1].size == 20 and labels[1].stroke == 3
                and labels[1].r == 216 and labels[1].g == 201 and labels[1].b == 163, "副本复用词条与未选中颜色字号描边")
            check(capture.buttons[1] and capture.buttons[1].style == "plain"
                and capture.buttons[1].options.alpha == 1, "保留原未选中按钮样式")
            check(#capture.hotspots == 1 and countIcon("nav_battle") == 0,
                "三行不能恢复已常驻战斗/角色/城镇页签")
            checkHotspot(1, "tab_dungeon", 108, 214, "left", -30)
            check(TopBar.getPageTabHotspot("tab_battle", -30) == nil, "常驻战斗没有幽灵热点")
            check(TopBar.getPageTabHotspot("tab_character", -30) == nil
                and TopBar.getPageTabHotspot("tab_town", -30) == nil, "角色/城镇入口仍不恢复")
            check(not TopBar.hitTestAvatar(108, 214, -30), "副本中心不命中先执行的头像热区")
        end)
        runCase("三行点击实际绘制中心路由tab5，重复点击不重复音效", function()
            fixture(true)
            render(-30)
            local button = capture.buttons[1]
            local x, y = button.x + button.w * 0.5, button.y + button.h * 0.5
            check(TopBar.handleInput(x, y, -30), "绘制中心真实Input必须消费")
            check(Nav.getSelectedIndex() == 5 and #capture.selections == 1 and capture.selections[1] == 5,
                "真实BottomNav被设置为5且只派发一次")
            check(#capture.sounds == 1 and capture.sounds[1] == 2, "保留原导航音效")
            check(TopBar.handleInput(x, y, -30), "已选中副本仍消费点击")
            check(#capture.selections == 1 and #capture.sounds == 1, "重复点击不二次切换或播音效")
            render(-30)
            check(capture.buttons[1] and capture.buttons[1].style == "btn"
                and capture.buttons[1].options.accent == "gold", "tab5选中沿用金色按钮样式")
            local labels = tabLabels()
            check(labels[1] and labels[1].r == 240 and labels[1].g == 199 and labels[1].b == 94,
                "选中金色文字保留")
        end)
        runCase("tab5页签锁不可绕过，保持置灰且不显示红点", function()
            fixture(true)
            Nav.setTabLocked(5, true)
            Nav.setBadge(5, true, "redDot")
            render(-30)
            check(#capture.buttons == 1 and capture.buttons[1].options.alpha == 0.38,
                "锁定仍保留可见副本入口并置灰")
            check(countIcon("reddot") == 0, "锁定入口不泄露可领取红点")
            local icons, labels = navIcons(), tabLabels()
            check(icons[1] and icons[1].alpha == 0.38, "锁图标透明度保留")
            check(labels[1] and labels[1].r == 0x8b and labels[1].g == 0x95 and labels[1].b == 0xa5,
                "锁定文本灰蓝色保留")
            check(TopBar.handleInput(108, 214, -30), "页签锁仍消费命中，不穿透到下层")
            check(Nav.getSelectedIndex() == 3, "锁定不切tab5")
            checkNoNavigation("页签锁")
        end)
        runCase("allLocked守卫不可绕过且隐藏红点", function()
            fixture(true)
            Nav.setAllLocked(true)
            Nav.setBadge(5, true, "redDot")
            render(-30)
            check(#capture.buttons == 1 and capture.buttons[1].options.alpha == 0.38
                and countIcon("reddot") == 0, "全局锁仍画置灰入口且无红点")
            check(not TopBar.handleInput(108, 214, -30), "全局锁仍返回false")
            check(Nav.getSelectedIndex() == 3, "全局锁保留原tab")
            checkNoNavigation("全局锁")
        end)
        runCase("三行副本解锁红点保留且跟随offset", function()
            fixture(true)
            Nav.setBadge(5, true, "redDot")
            render(-30)
            check(countIcon("reddot") == 1, "解锁后仍显示原副本角标")
            for _, icon in ipairs(capture.icons) do
                if icon.name == "reddot" then
                    check(icon.cx == 108 + 196 * 0.38 and icon.cy == 214 - 64 * 0.38,
                        "红点跟随相同按钮中心offset")
                end
            end
        end)
        runCase("显式hidePageTabs=true优先于tri与旧布局", function()
            for _, triOpen in ipairs({ true, false }) do
                fixture(triOpen)
                render(-30, true)
                check(#capture.buttons == 0 and #navIcons() == 0 and #tabLabels() == 0
                    and #capture.hotspots == 0, "显式隐藏不画任何页签且不注册热点")
                for _, key in ipairs({ "tab_battle", "tab_dungeon" }) do
                    check(TopBar.getPageTabHotspot(key, -30, true) == nil, "显式隐藏热点查询nil")
                end
                check(not TopBar.handleInput(108, 214, -30, true)
                    and not TopBar.handleInput(316, 214, -30, true), "显式隐藏两旧位置均不可点")
                check(Nav.getSelectedIndex() == 3, "显式隐藏不改变选中tab")
                checkNoNavigation("显式隐藏")
            end
        end)
        runCase("非tri旧路径战斗/副本保持两按钮与原坐标", function()
            fixture(false)
            render(0, false)
            local icons, labels = navIcons(), tabLabels()
            check(#capture.buttons == 2 and #icons == 2 and #labels == 2 and #capture.hotspots == 2,
                "非tri仍只有战斗和副本两按钮")
            check(icons[1] and icons[1].name == "nav_battle" and icons[2] and icons[2].name == "nav_dungeon",
                "非tri旧入口顺序不变")
            checkHotspot(1, "tab_battle", 108, 244, "center", 0, false)
            checkHotspot(2, "tab_dungeon", 316, 244, "center", 0, false)
            check(TopBar.handleInput(316, 244, 0, false) and Nav.getSelectedIndex() == 5,
                "旧位置副本点击仍路由tab5")
            check(TopBar.handleInput(108, 244, 0, false) and Nav.getSelectedIndex() == 3,
                "旧位置战斗点击仍路由tab3")
            check(#capture.selections == 2 and capture.selections[1] == 5 and capture.selections[2] == 3
                and #capture.sounds == 2, "非tri路由与音效次数正常")
            clearCapture()
            Nav.setTabLocked(3, true)
            check(TopBar.handleInput(108, 244, 0) and Nav.getSelectedIndex() == 3,
                "旧战斗锁也消费但不派发")
            checkNoNavigation("旧战斗锁")
            Nav.setTabLocked(3, false)
            Nav.setTabLocked(5, true)
            check(TopBar.handleInput(316, 244, 0) and Nav.getSelectedIndex() == 3,
                "旧副本锁保留")
            checkNoNavigation("旧副本锁")
            Nav.setTabLocked(5, false)
            Nav.setAllLocked(true)
            check(not TopBar.handleInput(108, 244, 0) and not TopBar.handleInput(316, 244, 0),
                "旧路径全局锁也拒绝两入口")
            checkNoNavigation("旧全局锁")
        end)
        runCase("不同offset绘制/热点/输入边界一致且无幽灵旧槽", function()
            for _, triOpen in ipairs({ true, false }) do
                for _, oy in ipairs({ -30, 0, 37 }) do
                    fixture(triOpen)
                    render(oy)
                    local expected = triOpen and { { "tab_dungeon", 108 } }
                        or { { "tab_battle", 108 }, { "tab_dungeon", 316 } }
                    for index, entry in ipairs(expected) do
                        local cy = 244 + oy
                        checkHotspot(index, entry[1], entry[2], cy, oy == -30 and "left" or "center", oy)
                        local cx = entry[2]
                        for _, probe in ipairs({
                            { cx - 98, cy - 32, true }, { cx + 98, cy + 32, true },
                            { cx - 98.25, cy, false }, { cx + 98.25, cy, false },
                            { cx, cy - 32.25, false }, { cx, cy + 32.25, false },
                        }) do
                            check(TopBar.handleInput(probe[1], probe[2], oy) == probe[3],
                                "实际按钮四角/外缘命中与热点矩形一致")
                        end
                    end
                    if triOpen then
                        check(not TopBar.handleInput(316, 244 + oy, oy), "tri旧副本第二槽不保留幽灵点击")
                    end
                end
            end
            fixture(true)
            render()
            checkHotspot(1, "tab_dungeon", 108, 244, "center")
            check(TopBar.handleInput(108, 244) and Nav.getSelectedIndex() == 5, "默认offset=0仍同源")
        end)
        runCase("tri依赖不存在或缺isOpen时安全回退旧布局", function()
            for _, unavailable in ipairs({ true, false }) do
                fixture(true)
                state.triAvailable, state.triHasIsOpen = not unavailable, unavailable
                render(0)
                check(#capture.buttons == 2 and #capture.hotspots == 2, "缺tri依赖/方法回退两个旧入口")
                checkHotspot(1, "tab_battle", 108, 244, "center", 0)
                checkHotspot(2, "tab_dungeon", 316, 244, "center", 0)
                check(TopBar.handleInput(316, 244, 0) and Nav.getSelectedIndex() == 5,
                    "安全回退旧副本点击正常")
                render(0, true)
                check(#capture.buttons == 0 and not TopBar.handleInput(316, 244, 0, true),
                    "依赖不可用时显式隐藏仍优先")
            end
        end)
        runCase("教程非活动不注册热点，但入口仍可用", function()
            fixture(true)
            state.tutorial = false
            render(-30)
            check(#capture.buttons == 1 and #capture.hotspots == 0, "非教程帧仍画副本但无热点注册")
            local cx, cy = TopBar.getPageTabHotspot("tab_dungeon", -30)
            check(cx == 108 and cy == 214 and TopBar.handleInput(cx, cy, -30)
                and Nav.getSelectedIndex() == 5, "非教程热点查询/点击仍为真实按钮")
            check(TopBar.getPageTabHotspot("unknown", -30) == nil, "未知热点不生成坐标")
        end)
        Nav.setSelectedIndex = setSelectedIndex
    end)
    if not ok then check(false, "Start exception: " .. tostring(err)) end
    require = nativeRequire
    for name, saved in pairs(originals) do rawset(_G, name, saved.value) end
    if failures == 0 then
        print("[topbar_dungeon_entry_test] ALL PASS: " .. cases .. " cases, " .. assertions .. " assertions, " .. frames .. " real TopBar frames")
    else
        print("[FAIL] topbar_dungeon_entry_test: " .. failures .. " failures, " .. assertions .. " assertions")
    end
    engine:Exit()
end
