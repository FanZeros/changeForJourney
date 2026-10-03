-- 锻炉/左栏仓库层级回归：真实 Horizon、Viewport、BlacksmithDraw，页面为只读 spy。
-- 不读写玩家存档、不执行锻造或穿戴事务；覆盖三行/普通横屏、单帧次数、动画裁剪和点击路由。
local assertions = 0
local function check(condition, label)
    assertions = assertions + 1
    assert(condition, label)
end

function Start()
    local originalRequire = require
    local RT = originalRequire("boot.StandaloneRT")
    local VP = originalRequire("core.Viewport")
    local Draw = originalRequire("ui.blacksmith.BlacksmithDraw")
    local oldRT, oldGlobals, oldNotes = {}, {}, VP._notes
    for key, value in pairs(RT) do oldRT[key] = value end
    for key, value in pairs(_G) do oldGlobals[key] = value end
    local ok, err = pcall(function()
        local function noop() return false end
        ---@return any
        local function mock(values)
            return setmetatable(values or {}, { __index = function() return noop end })
        end
        local calls, records = {}, {}
        local function record(name)
            calls[name] = (calls[name] or 0) + 1
            records[#records + 1] = name
        end
        local function at(name)
            for i, v in ipairs(records) do if v == name then return i end end
            return 0
        end
        local state = { tri = false, smith = true, reward = false, closeOnDraw = false }
        local cursor, clock = { x = 0, y = 0 }, { elapsedTime = 100 }
        input = { GetMousePosition = function() return cursor end }
        time = clock
        -- NanoVG模拟遵循：scissor设置时变换到窗口坐标，后续平移不能带动宿主裁剪。
        local ctx = { tx = 0, ty = 0, sx = 1, sy = 1, clip = nil, stack = {} }
        local function rect(x, y, w, h)
            return { x = ctx.tx + x * ctx.sx, y = ctx.ty + y * ctx.sy, w = w * ctx.sx, h = h * ctx.sy }
        end
        local function intersect(a, b)
            if not a then return b end
            local x, y = math.max(a.x, b.x), math.max(a.y, b.y)
            return { x = x, y = y, w = math.max(0, math.min(a.x + a.w, b.x + b.w) - x),
                h = math.max(0, math.min(a.y + a.h, b.y + b.h) - y) }
        end
        nvgSave = function()
            ctx.stack[#ctx.stack + 1] = { tx = ctx.tx, ty = ctx.ty, sx = ctx.sx, sy = ctx.sy, clip = ctx.clip }
        end
        nvgRestore = function()
            local saved = assert(table.remove(ctx.stack), "save/restore不配对")
            ctx.tx, ctx.ty, ctx.sx, ctx.sy, ctx.clip = saved.tx, saved.ty, saved.sx, saved.sy, saved.clip
        end
        nvgTranslate = function(_, x, y) ctx.tx, ctx.ty = ctx.tx + x * ctx.sx, ctx.ty + y * ctx.sy end
        nvgScale = function(_, x, y) ctx.sx, ctx.sy = ctx.sx * x, ctx.sy * y end
        nvgScissor = function(_, x, y, w, h) ctx.clip = rect(x, y, w, h) end
        nvgIntersectScissor = function(_, x, y, w, h) ctx.clip = intersect(ctx.clip, rect(x, y, w, h)) end
        nvgResetScissor = function() ctx.clip = nil end
        nvgResetTransform = function() ctx.tx, ctx.ty, ctx.sx, ctx.sy = 0, 0, 1, 1 end
        nvgBeginFrame = function()
            ctx.tx, ctx.ty, ctx.sx, ctx.sy, ctx.clip, ctx.stack = 0, 0, 1, 1, nil, {}
        end
        nvgEndFrame = function() check(#ctx.stack == 0, "每帧恢复全部NanoVG状态") end
        for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgFillColor", "nvgFill" }) do _G[name] = noop end
        local function page(name)
            return mock({
                draw = function() record(name .. ".draw") end,
                handleInput = function() record(name .. ".input"); return true end,
                handleDragBegin = function() record(name .. ".down"); return true end,
                handleDragEnd = function() record(name .. ".up"); return true end,
                handleScroll = function() record(name .. ".wheel"); return true end,
            })
        end
        local smith, backpack = page("smith"), page("backpack")
        smith.isOpen = function() return state.smith end
        smith.getSeamAnim = function() return 1, 0, 0.45, 0.38 end
        smith.drawUnderlay = function() record("smith.underlay") end
        smith.draw = function()
            if not state.smith then return end
            record("smith.draw")
            if state.closeOnDraw then state.smith = false end
        end
        backpack.isOpen = function() return true end
        backpack.isLeftMode = function() return true end
        backpack.getSeamAnim = function() return 1, 0, 0.45, 0.38 end
        local reward = mock({
            isOpen = function() return state.reward end,
            currentPanel = function() return "left" end,
            drawContent = function() record("reward.draw") end,
        })
        local mods = {
            ["boot.StandaloneRT"] = RT, ["core.Viewport"] = VP,
            ["ui.blacksmith.BlacksmithPage"] = smith, ["ui.backpack.BackpackPanel"] = backpack,
            ["ui.hud.BottomNav"] = { getSelectedIndex = function() return 3 end },
            ["ui.character.panel.CharacterPanel"] = mock({ getTotalPower = function() return 0 end }),
            ["ui.battle.scene.BattleScene"] = page("battle"),
            ["ui.battle.tri.BattleTriPage"] = mock({
                isOpen = function() return state.tri end,
                draw = function() record("tri.draw") end,
                drawHud = function() record("tri.hud") end,
            }),
            ["ui.hud.popup.RewardPopup"] = reward,
            ["ui.loot.LootBox"] = mock({ drawPage = function() record("loot.draw") end }),
            ["ui.story.task.TaskPage"] = page("task"),
            ["core.DrawUtil"] = mock({ SEAMBAR_ASPECT = 0.04, SEAMBAR_ARROW_Y = 0.469,
                seamSlideX = function() return 0 end }),
        }
        for key in pairs(RT) do RT[key] = nil end
        RT.vg, RT.logicalW, RT.logicalH, RT.windowW, RT.windowH = {}, 1920, 1080, 1920, 1080
        RT.dpr, RT.bootReady_, RT.preload_ = 1, true, { active = false }
        require = function(name)
            if name == "boot.StandaloneHorizonInput" or name == "boot.OfflineRewardOverlay" then
                return originalRequire(name)
            end
            if not mods[name] then mods[name] = mock() end
            return mods[name]
        end
        originalRequire("boot.StandaloneHorizon")
        local function clearCalls() calls, records = {}, {} end
        for _, tri in ipairs({ false, true }) do
            state.tri, state.smith, state.closeOnDraw, state.reward = tri, true, false, false
            clearCalls()
            HandleNanoVGRenderHorizon()
            check(calls["smith.draw"] == 1, "两种布局锻炉每帧只画一次 tri=" .. tostring(tri))
            check(calls["backpack.draw"] == 1, "两种布局仓库每帧只画一次")
            check(at("smith.underlay") < at("backpack.draw"), "锻炉垫底仍在仓库下")
            check(at("smith.draw") < at("backpack.draw"), "锻炉本体在仓库之下")
            check(at("backpack.draw") < at("loot.draw") and at("loot.draw") < at("task.draw"), "左栏其他页面既有优先级保留")
            if tri then check(at("tri.hud") < at("smith.draw"), "锻炉仍覆盖三行战斗") end
            state.closeOnDraw = true
            clearCalls()
            HandleNanoVGRenderHorizon()
            check(calls["smith.draw"] == 1 and calls["backpack.draw"] == 1, "关闭完成帧仍不重复/漏画")
            clearCalls()
            HandleNanoVGRenderHorizon()
            check(not calls["smith.draw"] and calls["backpack.draw"] == 1, "锻炉关闭后仓库恢复普通层")

            state.smith, state.closeOnDraw, state.reward = true, false, true
            clearCalls()
            HandleNanoVGRenderHorizon()
            check(at("reward.draw") > at("backpack.draw"), "左栏奖励保持在仓库之上")
            state.reward = false
            clearCalls()
            local note, p = VP.getNote("left"), VP.PANELS.left
            cursor.x, cursor.y = note.ox + p.bx * note.s + 100 * note.s * VP.DS, note.oy + 1300 * note.s * VP.DS
            local button = { Button = { GetInt = function() return MOUSEB_LEFT end } }
            HandleMouseButtonDownHorizon("MouseButtonDown", button)
            clock.elapsedTime = clock.elapsedTime + 1
            HandleMouseButtonUpHorizon("MouseButtonUp", button)
            check(calls["backpack.input"] == 1 and not calls["smith.input"], "左仓库点击不穿透锻炉")
            clearCalls()
            note, p = VP.getNote("center"), VP.PANELS.center
            cursor.x, cursor.y = note.ox + p.bx * note.s + 100 * note.s * VP.DS, note.oy + 1300 * note.s * VP.DS
            HandleMouseButtonDownHorizon("MouseButtonDown", button)
            clock.elapsedTime = clock.elapsedTime + 1
            HandleMouseButtonUpHorizon("MouseButtonUp", button)
            check(calls["smith.input"] == 1 and not calls["backpack.input"], "中栏锻炉仍可操作")
        end
        require = originalRequire

        -- 使用真实BlacksmithDraw实现，在不同平移阶段检查子裁剪仍受宿主中栏约束。
        local clips, closed = {}, 0
        local smithState = { open = true, closing = false, openTime = 0, closeTime = 0,
            tab = "xilian", tabFrom = "xilian", tabSwitchTime = 0 }
        local impl = Draw.bind({
            state = smithState, DESIGN_W = 1080, DESIGN_H = 2400,
            ANIM_DURATION = 0.45, CLOSE_ANIM_DURATION = 0.38, TAB_ANIM_DURATION = 0.35,
            LOWER_BG_CY = 1800, LOWER_BG_H = 800, TAB_BG_CY = 2312, TAB_BG_H = 112,
            TAB_MAP = { qianghua = 1, xilian = 2 },
            DrawUtil = { drawImageCentered = function() clips[#clips + 1] = ctx.clip end },
            I18n = { t = function() return "锻炉" end },
            TownPageChrome = { drawNamePlate = noop, drawTabBar = noop },
            SpineResultEffect = { isPlaying = function() return false end },
            drawWorkbenchSlot = noop, drawTabContent = function() clips[#clips + 1] = ctx.clip end,
            easeInOutCubic = function(t) return t end,
            closeAutoWarehouse = function() closed = closed + 1 end,
        })
        for _, offset in ipairs({ -1080, -800, -400, 0 }) do
            nvgBeginFrame()
            VP.begin({}, VP.PANELS.center, 0, 0, 1)
            nvgTranslate({}, offset, 0)
            clips = {}
            impl.drawPageImpl({})
            check(#clips == 2, "真实锻炉背景/内容均执行")
            for _, clip in ipairs(clips) do
                check(clip and clip.x >= 486 and clip.x + clip.w <= 972.00001,
                    "锻炉动画裁剪不越入左仓库 offset=" .. offset)
            end
            VP.finish({})
            check(#ctx.stack == 0, "真实锻炉恢复宿主状态")
        end
        smithState.closing, smithState.closeTime = true, clock.elapsedTime - 1
        impl.drawPageImpl({})
        check(not smithState.open and not smithState.closing and closed == 1, "关闭动画仍释放仓库持有一次")
    end)
    require = originalRequire
    VP._notes = oldNotes
    for key in pairs(RT) do RT[key] = nil end
    for key, value in pairs(oldRT) do RT[key] = value end
    local added = {}
    for key in pairs(_G) do if oldGlobals[key] == nil then added[#added + 1] = key end end
    for _, key in ipairs(added) do _G[key] = nil end
    for key, value in pairs(oldGlobals) do _G[key] = value end
    if ok then
        print("[forge_backpack_layer_test] ALL PASS: " .. assertions .. " assertions")
    else
        log:Write(LOG_ERROR, "[forge_backpack_layer_test] " .. tostring(err))
    end
    engine:Exit()
end
