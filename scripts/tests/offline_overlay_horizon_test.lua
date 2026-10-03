-- 无图形集成回归：真实 StandaloneHorizon + OfflineRewardOverlay + Viewport。
-- 页面均为默认返回 false 的 spy；不加载业务存档、不发送 action、不创建图形资源。
-- Runtime: tests/offline_overlay_horizon_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- 弹窗关闭后的 0.08s 仓库快装由 backpack_quick_horizon_test.lua 覆盖，不在这里重复。
function Start()
    ---@type fun(name: string): any
    local originalRequire = _G.require
    local originalInput, originalTime = rawget(_G, "input"), rawget(_G, "time")
    local originalGlobals, originalNvg, originalRT, originalViewport = {}, {}, {}, {}
    local originalLoadedHorizon = package.loaded["boot.StandaloneHorizon"]
    ---@type any
    local RT = nil
    ---@type any
    local viewport = nil
    local originalNotes = nil ---@type any
    local caseCount, casePasses, assertions, failures = 0, 0, 0, 0
    local function horizonGlobal(key)
        return type(key) == "string" and (key:match("^H_") or key:match("^Handle.*Horizon$"))
    end
    for key, value in pairs(_G) do
        if horizonGlobal(key) then originalGlobals[key] = value end
    end
    local function check(condition, label)
        assertions = assertions + 1
        if not condition then
            failures = failures + 1
            print("[FAIL] offline_overlay_horizon_test: " .. label)
        end
    end
    local function runCase(label, fn)
        caseCount = caseCount + 1
        local before = failures
        local ok, err = pcall(fn)
        if not ok then check(false, label .. " exception: " .. tostring(err)) end
        if failures == before then
            casePasses = casePasses + 1
            print("[PASS] " .. label)
        end
    end
    local function restoreTable(target, saved)
        for key in pairs(target) do target[key] = nil end
        for key, value in pairs(saved) do target[key] = value end
    end

    local ok, err = pcall(function()
        RT = originalRequire("boot.StandaloneRT")
        viewport = originalRequire("core.Viewport")
        -- 直接加载真实模块，绝不替换 bind/输入实现。
        local overlayModule = originalRequire("boot.OfflineRewardOverlay")
        for key, value in pairs(RT) do originalRT[key] = value end
        originalNotes = viewport._notes
        for _, name in ipairs({ "begin", "finish", "beginFromNote" }) do
            originalViewport[name] = viewport[name]
        end
        local function noop() return false end
        ---@return any
        local function mock(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local calls, events, drawings, frames = {}, {}, {}, {}
        local function count(name) calls[name] = (calls[name] or 0) + 1 end
        local function n(name) return calls[name] or 0 end
        local function record(name, x, y, wheel)
            count(name)
            events[#events + 1] = { name = name, x = x, y = y, wheel = wheel }
        end
        ---@type any
        local state = {
            mode = "ordinary", offline = true, level = false, warehouse = true,
            detail = false, detailHit = false, grid = false, armed = false,
            draggingCard = false, closeOnClaim = false, notice = false, story = false,
            title = false, letter = false, ce = false, pip = false, talent = false,
            task = false, towerTri = false, reward = false, dungeon = false, towerFloor = 7,
        }
        local cursor = { x = 0, y = 0 }
        local clock = { elapsedTime = 100 }
        rawset(_G, "input", { GetMousePosition = function() return cursor end })
        rawset(_G, "time", clock)
        local viewportDepth = 0
        -- 保留真实 Viewport 的变换、裁剪和 note；只记录调用期间是否仍在面板视口内。
        viewport.begin = function(...)
            originalViewport.begin(...)
            viewportDepth = viewportDepth + 1
        end
        viewport.finish = function(...)
            originalViewport.finish(...)
            viewportDepth = viewportDepth - 1
        end
        viewport.beginFromNote = function(...)
            local entered = originalViewport.beginFromNote(...)
            if entered then viewportDepth = viewportDepth + 1 end
            return entered
        end

        -- NanoVG 状态模拟：translate 必须乘已有 scale；scale 累乘父帧与面板缩放。
        -- scissor 在设置时转换为窗口逻辑坐标，后续 translate 不再移动该裁剪矩形。
        ---@type any
        local vgState = { sx = 1, sy = 1, tx = 0, ty = 0, clip = nil, stack = {} }
        local function copyRect(rect)
            if not rect then return nil end
            return { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
        end
        local function transformRect(x, y, w, h)
            return { x = vgState.tx + x * vgState.sx, y = vgState.ty + y * vgState.sy,
                w = w * vgState.sx, h = h * vgState.sy }
        end
        local function intersect(a, b)
            if not a then return b end
            local x, y = math.max(a.x, b.x), math.max(a.y, b.y)
            return { x = x, y = y, w = math.max(0, math.min(a.x + a.w, b.x + b.w) - x),
                h = math.max(0, math.min(a.y + a.h, b.y + b.h) - y) }
        end
        local function snapshot(name, width, height)
            drawings[#drawings + 1] = {
                name = name, width = width, height = height,
                sx = vgState.sx, sy = vgState.sy, tx = vgState.tx, ty = vgState.ty,
                clip = copyRect(vgState.clip), viewportDepth = viewportDepth,
                -- 真实 OfflineRewardPanel 的 1760 宽背景，超出 1080 设计稿但不应被面板 clip 切掉。
                widePanel = transformRect(-340, 220, 1760, 1400),
            }
        end
        local function stub(name, fn)
            originalNvg[name] = { value = rawget(_G, name) }
            rawset(_G, name, fn or noop)
        end
        stub("nvgBeginFrame", function(_, width, height, dpr)
            vgState.sx, vgState.sy, vgState.tx, vgState.ty = 1, 1, 0, 0
            vgState.clip, vgState.stack = nil, {}
            frames[#frames + 1] = { width = width, height = height, dpr = dpr }
            count("frameBegin")
        end)
        stub("nvgEndFrame", function()
            count("frameEnd")
            check(#vgState.stack == 0 and viewportDepth == 0, "每帧结束恢复全部 save/Viewport")
        end)
        stub("nvgSave", function()
            vgState.stack[#vgState.stack + 1] = { sx = vgState.sx, sy = vgState.sy,
                tx = vgState.tx, ty = vgState.ty, clip = copyRect(vgState.clip) }
        end)
        stub("nvgRestore", function()
            local saved = table.remove(vgState.stack)
            if not saved then error("NanoVG restore without save") end
            vgState.sx, vgState.sy, vgState.tx, vgState.ty = saved.sx, saved.sy, saved.tx, saved.ty
            vgState.clip = saved.clip
        end)
        stub("nvgTranslate", function(_, x, y)
            vgState.tx = vgState.tx + x * vgState.sx
            vgState.ty = vgState.ty + y * vgState.sy
        end)
        stub("nvgScale", function(_, x, y)
            vgState.sx, vgState.sy = vgState.sx * x, vgState.sy * y
        end)
        stub("nvgResetTransform", function()
            vgState.sx, vgState.sy, vgState.tx, vgState.ty = 1, 1, 0, 0
        end)
        stub("nvgScissor", function(_, x, y, w, h) vgState.clip = transformRect(x, y, w, h) end)
        stub("nvgIntersectScissor", function(_, x, y, w, h)
            vgState.clip = intersect(vgState.clip, transformRect(x, y, w, h))
        end)
        stub("nvgResetScissor", function() vgState.clip = nil end)
        for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFillColor",
            "nvgFill", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgFontFace",
            "nvgFontSize", "nvgTextAlign", "nvgText", "nvgGlobalAlpha", "nvgFillPaint" }) do
            stub(name)
        end
        -- nvgRGBA/NVG 枚举沿用引擎定义，绝不把数字/假颜色写入全局类型源头。

        local lowerMethods = { "handleInput", "handleClick", "handleRightClick", "handleHover",
            "handleScroll", "handleDragBegin", "handleDragMove", "handleDragEnd",
            "handleEquipmentSlotTap", "handleNavigationTap" }
        ---@return any
        local function page(name, fields)
            local base = {}
            for _, method in ipairs(lowerMethods) do
                base[method] = function(x, y, wheel)
                    record(name .. "." .. method, x, y, wheel)
                    return false
                end
            end
            for key, value in pairs(fields or {}) do base[key] = value end
            return mock(base)
        end
        local offline = mock({
            isOpen = function() return state.offline end,
            draw = function()
                count("offline.draw")
                snapshot("offline")
            end,
            handleDragBegin = function(x, y) record("offline.down", x, y); return false end,
            handleDragMove = function(x, y) record("offline.move", x, y); return false end,
            handleDragEnd = function(x, y) record("offline.up", x, y); return false end,
            handleScroll = function(wheel) record("offline.wheel", nil, nil, wheel); return false end,
            handleInput = function(x, y)
                record("offline.input", x, y)
                -- 只记录命中；没有奖励、存档、dispatcher 或领取 action。
                -- 无队员时真实 Panel.layoutNow 的领取按钮为 (540,1366)，420x100。
                if math.abs(x - 540) <= 210 and math.abs(y - 1366) <= 50 then
                    count("offline.claim")
                    if state.closeOnClaim then state.offline = false end
                end
                return false
            end,
        })
        local candidate = { seq = 7, slot = "helmet", templateId = "H1" }
        local backpack = page("backpack", {
            isOpen = function() return state.warehouse end,
            isLeftMode = function() return true end,
            getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
            peekEquipAt = function(x, y)
                if state.grid and x >= 80 and x <= 200 and y >= 1000 and y <= 1120 then return candidate end
                return nil
            end,
            close = function() count("seam.close"); state.warehouse = false; return false end,
        })
        local detail = page("detail", {
            isOpen = function() return state.detail end,
            isCompactCorner = function() return state.detail end,
            isPinned = function() return false end,
            getOwner = function() return "backpack" end,
            containsPoint = function() return state.detail and state.detailHit end,
            close = function() count("detail.close"); state.detail = false; return false end,
        })
        local crossDrag = mock({
            arm = function(item, _, _, source)
                check(item == candidate and source == "backpack", "下层真实按压路由 arm 正确装备与来源")
                state.armed = true
                count("cross.arm")
                return false
            end,
            isArmed = function() return state.armed end,
            getSource = function() return "backpack" end,
            move = function() count("cross.move"); return false end,
            cancel = function() state.armed = false; count("cross.cancel"); return false end,
            finish = function() state.armed = false; count("cross.finish"); return false end,
        })
        local mods = {
            ["boot.StandaloneRT"] = RT,
            ["core.Viewport"] = viewport,
            ["boot.OfflineRewardOverlay"] = overlayModule,
            ["ui.hud.popup.OfflineRewardPanel"] = offline,
            ["ui.hud.popup.UpdateNoticePopup"] = mock({
                isOpen = function() return state.notice end,
                handleInput = function() count("notice.input"); return true end,
                draw = function() if state.notice then snapshot("notice") end end,
            }),
            ["ui.story.ScenarioDialogue"] = mock({
                isActive = function() return state.story end,
                advance = function() count("story.advance") end,
            }),
            ["ui.story.gate.DarkTitleScreenGate"] = mock({
                isOpen = function() return state.title end,
                handleTap = function() count("title.tap") end,
            }),
            ["ui.story.gate.LetterIntro"] = mock({
                isOpen = function() return state.letter end,
                handleTap = function() count("letter.tap") end,
            }),
            ["ui.dev.CEPanel"] = mock({
                handleDown = function() return state.ce end,
                handleUp = function() if state.ce then count("ce.up") end; return state.ce end,
                handleWheel = function() if state.ce then count("ce.wheel") end; return state.ce end,
                draw = function() snapshot("ce") end,
            }),
            ["ui.hud.popup.LevelUpPopup"] = page("level", {
                isOpen = function() return state.level end,
                draw = function(_, width, height)
                    if state.level then count("level.draw"); snapshot("level", width, height) end
                    return false
                end,
                handleInput = function(x, y, width, height)
                    record("level.handleInput", x, y)
                    check(width == RT.logicalW and height == RT.logicalH, "升级输入透传宿主逻辑宽高")
                    return true
                end,
            }),
            ["ui.hud.popup.PlayerInfoPanel"] = page("pip", {
                isOpen = function() return state.pip end,
                draw = function() if state.pip then snapshot("pip") end end,
            }),
            ["ui.church.talent.TalentPage"] = page("talent", {
                isOpen = function() return state.talent end,
                getHorizonWidthScale = function() return 1 end,
            }),
            ["ui.hud.popup.RewardPopup"] = page("reward", {
                isOpen = function() return state.reward end,
                currentPanel = function() return nil end,
                currentRowTag = function() return nil end,
                draw = function() if state.reward then snapshot("reward") end end,
                hitPanel = function() return state.reward end,
            }),
            ["ui.story.task.TaskPage"] = page("task", {
                isOpen = function() return state.task end,
                getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
                draw = function() if state.task then snapshot("task") end end,
                close = function() state.task = false; count("task.close") end,
                handleInput = function(x, y)
                    record("task.handleInput", x, y)
                    -- 沿用真实 TownPageChrome 的返回热区与 H_SEAM_BACK 条件。
                    if not H_SEAM_BACK and math.abs(x - 958) <= 92 and math.abs(y - 1150) <= 71.5 then
                        state.task = false
                        count("task.close")
                    end
                    return true
                end,
            }),
            ["ui.dungeon.DungeonBattleScene"] = page("dungeon", {
                isOpen = function() return state.dungeon end,
            }),
            ["ui.backpack.BackpackPanel"] = backpack,
            ["ui.character.equip.EquipmentDetail"] = detail,
            ["ui.character.EquipCrossDrag"] = crossDrag,
            ["ui.character.panel.CharacterPanel"] = page("character", {
                getTotalPower = function() return 123 end,
                isDraggingCard = function() return state.draggingCard end,
                handleDragEnd = function(x, y)
                    state.draggingCard = false
                    record("character.handleDragEnd", x, y)
                    return false
                end,
            }),
            ["ui.character.detail.CharacterDetail"] = page("characterDetail", {
                isOpen = function() return state.detailHit end,
                isEquipTab = function() return true end,
                getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
                close = function() count("seam.close"); state.detailHit = false; return false end,
            }),
            ["ui.battle.tri.BattleTriPage"] = page("tri", {
                isOpen = function() return state.mode == "tri" or state.towerTri end,
            }),
            ["ui.tower.TowerBattleScene"] = page("tower", {
                isActive = function() return state.mode == "tower" end,
                draw = function() if state.task then snapshot("tower") end end,
                close = function() count("tower.close"); state.mode = "ordinary"; state.towerFloor = 0 end,
            }),
            ["ui.hud.BottomNav"] = mock({ getSelectedIndex = function() return 3 end }),
            ["core.BattleLayout"] = mock({ CARD_SCALE = 1 }),
            ["core.DarkIcon"] = mock({ SHOWCASE = false }),
            ["core.DrawUtil"] = mock({ SEAMBAR_ASPECT = 0.04, SEAMBAR_ARROW_Y = 0.469,
                seamSlideX = function() return 0 end }),
            ["runtime.GameAction"] = mock({ sendAction = function() count("action"); return false end }),
        }
        -- Runtime 的 require 可绕过 package.preload/loaded，所以拦截 _G.require 的动态依赖。
        rawset(_G, "require", function(name)
            if name == "boot.StandaloneHorizonInput" or name == "boot.OfflineRewardOverlay" then
                return originalRequire(name)
            end
            if not mods[name] then mods[name] = page(name) end
            return mods[name]
        end)

        local function invoke(handler, event)
            local fn = rawget(_G, handler)
            if type(fn) ~= "function" then error("missing Horizon API: " .. handler) end
            fn(handler, event or {})
        end
        local function integer(value) return { GetInt = function() return value end } end
        local left, right = { Button = integer(MOUSEB_LEFT) }, { Button = integer(MOUSEB_RIGHT) }
        local wheel = { Wheel = integer(-2) }
        local function touch(id, x, y)
            -- 没有 Button，误走鼠标读取时应立即报错，而不是 silently 返回 0。
            return { TouchID = integer(id), X = integer(x), Y = integer(y) }
        end
        local function framePosition(x, y)
            return (RT.frameOx + x * RT.frameScale) * RT.dpr,
                (RT.frameOy + y * RT.frameScale) * RT.dpr
        end
        local function positionWindow(x, y)
            cursor.x, cursor.y = framePosition(x, y)
        end
        local function overlayPosition(x, y)
            local fit = math.min(RT.logicalW / 1080, RT.logicalH / 2400)
            return framePosition((RT.logicalW - 1080 * fit) * 0.5 + x * fit,
                (RT.logicalH - 2400 * fit) * 0.5 + y * fit)
        end
        local function positionOverlay(x, y) cursor.x, cursor.y = overlayPosition(x, y) end
        local function positionPanel(id, x, y)
            local note, p = viewport.getNote(id), viewport.PANELS[id]
            positionWindow(note.ox + p.bx * note.s + x * note.s * viewport.DS,
                note.oy + p.by * note.s + y * note.s * viewport.DS)
        end
        local function closeEnough(a, b) return type(a) == "number" and math.abs(a - b) < 0.00001 end
        local function checkXY(name, x, y, label)
            local found = 0
            for _, event in ipairs(events) do
                if event.name == name then
                    found = found + 1
                    check(closeEnough(event.x, x) and closeEnough(event.y, y), label .. " " .. name .. " 坐标")
                end
            end
            check(found > 0, label .. " 实际收到 " .. name)
        end
        local function checkNoLowerInput(label, allowed)
            local leaked = {}
            for name, amount in pairs(calls) do
                if amount > 0 and not (allowed and allowed[name])
                    and not name:match("^offline%.") and not name:match("^cross%.")
                    and (name:match("%.handle") or name == "action" or name == "seam.close" or name == "detail.close") then
                    leaked[#leaked + 1] = name .. "=" .. amount
                end
            end
            table.sort(leaked)
            check(#leaked == 0, label .. " 下层输入/hover/wheel/seam.close/action 为零 " .. table.concat(leaked, ","))
            check(n("cross.arm") == 0 and n("cross.move") == 0 and n("cross.finish") == 0,
                label .. " 未激活下层装备手势")
            check(n("offline.claim") <= n("offline.input"), label .. " 领取只可能来自离线 tap")
        end
        local function checkNoClaim(label)
            check(n("offline.input") == 0 and n("offline.claim") == 0, label .. " 没有领取/tap")
        end
        local function clearCalls()
            for key in pairs(calls) do calls[key] = nil end
            for key in pairs(events) do events[key] = nil end
        end
        local function fixture(mode, dpr, transformed, open)
            state.mode, state.offline, state.level = mode, open ~= false, false
            state.warehouse, state.grid = true, false
            state.detail, state.detailHit, state.armed = false, false, false
            state.draggingCard, state.closeOnClaim = false, false
            state.notice, state.story, state.title, state.letter, state.ce = false, false, false, false, false
            state.pip, state.talent = false, false
            state.task, state.towerTri, state.reward, state.dungeon, state.towerFloor = false, false, false, false, 7
            restoreTable(RT, {
                logicalW = 1920, logicalH = 1080, windowW = 1920, windowH = 1080,
                DESIGN_W = 1080, DESIGN_H = 2400, dpr = dpr or 1,
                frameOx = transformed and 37 or 0, frameOy = transformed and 23 or 0,
                frameScale = transformed and 0.8 or 1, vg = {}, bootReady_ = true,
                preload_ = { active = false },
            })
            viewport._notes = {}
            viewportDepth = 0
            clearCalls()
            for key in pairs(drawings) do drawings[key] = nil end
            for key in pairs(frames) do frames[key] = nil end
            clock.elapsedTime = clock.elapsedTime + 10
            -- 每个 case 重载以重置真实 Horizon/Overlay 的局部 press/touch/debounce 状态。
            package.loaded["boot.StandaloneHorizon"] = nil
            originalRequire("boot.StandaloneHorizon")
            invoke("HandleNanoVGRenderHorizon")
        end
        local function checkDraw(name, label)
            local found = {}
            for _, draw in ipairs(drawings) do if draw.name == name then found[#found + 1] = draw end end
            check(#found == 1, label .. " 绘制恰好一次，actual=" .. #found)
            if #found ~= 1 then return end
            local draw = found[1]
            local fit = name == "level" and 1 or math.min(RT.logicalW / 1080, RT.logicalH / 2400)
            local ox = name == "level" and 0 or (RT.logicalW - 1080 * fit) * 0.5
            local oy = name == "level" and 0 or (RT.logicalH - 2400 * fit) * 0.5
            check(closeEnough(draw.sx, RT.frameScale * fit) and closeEnough(draw.sy, RT.frameScale * fit)
                and closeEnough(draw.tx, RT.frameOx + ox * RT.frameScale)
                and closeEnough(draw.ty, RT.frameOy + oy * RT.frameScale), label .. " 累计父 frame + 全窗 letterbox matrix")
            local clip = draw.clip
            check(clip and closeEnough(clip.x, RT.frameOx) and closeEnough(clip.y, RT.frameOy)
                and closeEnough(clip.w, RT.logicalW * RT.frameScale)
                and closeEnough(clip.h, RT.logicalH * RT.frameScale), label .. " 全窗 clip，不是1080面板 clip")
            check(draw.viewportDepth == 0, label .. " 绘制不处于面板 Viewport 内")
            if name == "level" then
                check(draw.width == RT.logicalW and draw.height == RT.logicalH,
                    label .. " 升级 draw 使用宿主逻辑宽高，不由宿主 letterbox")
            else
                check(draw.widePanel.w > 1080 * fit * RT.frameScale
                    and clip and draw.widePanel.x > clip.x
                    and draw.widePanel.x + draw.widePanel.w < clip.x + clip.w,
                    label .. " 1760宽奖励背景完整包含于全窗裁剪")
            end
        end
        local function click(button)
            invoke("HandleMouseButtonDownHorizon", button or left)
            clock.elapsedTime = clock.elapsedTime + 0.2
            invoke("HandleMouseButtonUpHorizon", button or left)
        end

        for _, mode in ipairs({ "ordinary", "tri", "tower" }) do
            runCase(mode .. " 离线全窗唯一绘制", function()
                fixture(mode)
                checkDraw("offline", mode)
                check(n("offline.draw") == 1 and n("level.draw") == 0, mode .. " 不借升级窗绘制分支")
                check(n("frameBegin") == 1 and n("frameEnd") == 1, mode .. " 一对 BeginFrame/EndFrame")
                checkNoLowerInput(mode .. " render")
            end)
        end
        runCase("tri 仅 LevelUp 打开仍绘制一次", function()
            fixture("tri", 1, false, false)
            clearCalls()
            for key in pairs(drawings) do drawings[key] = nil end
            state.level = true
            invoke("HandleNanoVGRenderHorizon")
            checkDraw("level", "tri LevelUp-only")
            check(n("level.draw") == 1 and n("offline.draw") == 0, "LevelUp 不依赖 offline/reward/playerinfo 开启")
            checkNoLowerInput("LevelUp-only")
        end)

        for _, mode in ipairs({ "ordinary", "tri", "tower" }) do
            for _, zone in ipairs({ { name = "left", x = 250 }, { name = "center", x = 960 }, { name = "right", x = 1680 } }) do
                runCase(mode .. " " .. zone.name .. " down/up/right/wheel/hover 消费", function()
                    fixture(mode)
                    clearCalls()
                    positionWindow(zone.x, 506)
                    local expectedX, expectedY = (zone.x - 717) / 0.45, 506 / 0.45
                    invoke("HandleMouseMoveHorizon")
                    invoke("HandleEquipmentHoverTickHorizon")
                    check(n("offline.move") == 0, "未按下的 hover 不伪造 offline 拖拽")
                    invoke("HandleMouseButtonDownHorizon", left)
                    invoke("HandleMouseMoveHorizon")
                    clock.elapsedTime = clock.elapsedTime + 0.2
                    invoke("HandleMouseButtonUpHorizon", left)
                    click(right)
                    invoke("HandleMouseWheelHorizon", wheel)
                    invoke("HandleMouseMoveHorizon")
                    invoke("HandleEquipmentHoverTickHorizon")
                    check(n("offline.down") == 1 and n("offline.move") == 1 and n("offline.up") == 1
                        and n("offline.input") == 1, "左右按钮不会混入左键拖拽/tap")
                    check(n("offline.wheel") == 1 and n("offline.claim") == 0, "任何栏滚轮都交给离线且外部点不领取")
                    checkXY("offline.down", expectedX, expectedY, zone.name)
                    checkXY("offline.move", expectedX, expectedY, zone.name)
                    checkXY("offline.up", expectedX, expectedY, zone.name)
                    checkXY("offline.input", expectedX, expectedY, zone.name)
                    checkNoLowerInput(mode .. " " .. zone.name)
                end)
            end
        end
        for _, seam in ipairs({ { name = "left seam", x = 505.6 }, { name = "right seam", x = 1414.4 } }) do
            runCase(seam.name .. " 离线阻止下层 close", function()
                fixture("tri")
                state.detailHit = true -- CharacterDetail 的真实右缝 close 分支也处于激活状态。
                clearCalls()
                positionWindow(seam.x, 1080 * 0.469)
                click()
                check(n("offline.input") == 1 and n("seam.close") == 0, seam.name .. " 全窗消费，未关闭仓库/角色详情")
                check(state.warehouse and state.detailHit, seam.name .. " 下层页仍开着")
                checkNoLowerInput(seam.name)
            end)
        end

        for _, mode in ipairs({ "ordinary", "tri", "tower" }) do
            for _, dpr in ipairs({ 1, 2, 3 }) do
                runCase(mode .. " 非零 frame + DPR=" .. dpr .. " 绘制/点击吻合", function()
                    fixture(mode, dpr, true)
                    checkDraw("offline", mode .. " DPR=" .. dpr)
                    check(#frames == 1 and frames[1].dpr == dpr and frames[1].width == 1920
                        and frames[1].height == 1080, "BeginFrame 使用窗口逻辑尺寸和真实 DPR")
                    clearCalls()
                    positionOverlay(540, 1375)
                    -- 此点经累计矩阵后为整数物理坐标，避免浮点 GetInt mock 掩盖真实触摸量化。
                    check(cursor.x == math.floor(cursor.x) and cursor.y == math.floor(cursor.y), "测试输入是整数物理像素")
                    local draw = drawings[1]
                    check(closeEnough(cursor.x, (draw.tx + 540 * draw.sx) * dpr)
                        and closeEnough(cursor.y, (draw.ty + 1375 * draw.sy) * dpr), "输入物理像素等于实际绘制 matrix * DPR")
                    click()
                    checkXY("offline.down", 540, 1375, "frame/DPR down")
                    checkXY("offline.up", 540, 1375, "frame/DPR up")
                    checkXY("offline.input", 540, 1375, "frame/DPR claim")
                    check(n("offline.claim") == 1, "正确坐标只领取一次")
                    checkNoLowerInput("frame/DPR")
                end)
            end
        end

        runCase("crossDrag 按压后离线出现：cancel 非 finish，无 offline down 不领取", function()
            fixture("tri", 1, false, false)
            state.grid = true
            clearCalls()
            positionPanel("left", 140, 1060)
            invoke("HandleMouseButtonDownHorizon", left)
            check(state.armed and n("cross.arm") == 1 and n("backpack.handleDragBegin") == 1, "下层由真实 Horizon down arm")
            clearCalls()
            state.offline = true
            positionOverlay(540, 1375)
            invoke("HandleMouseButtonUpHorizon", left)
            check(n("cross.cancel") == 1 and n("cross.finish") == 0 and not state.armed, "离线接管只 cancel，绝不落点 finish")
            check(n("backpack.handleDragEnd") == 1, "释放仓库旧按压")
            checkXY("backpack.handleDragEnd", -1, -1, "仓库取消哨兵")
            check(n("offline.down") == 0, "弹窗没收到本次 down")
            checkNoClaim("旧 crossDrag up")
            checkNoLowerInput("旧 crossDrag up", { ["backpack.handleDragEnd"] = true })
            -- 上面的 -1/-1 是唯一允许的下层结束，不是 input；清除后验证额外 up 不再取消/领取。
            clearCalls()
            invoke("HandleMouseButtonUpHorizon", left)
            invoke("HandleEquipmentHoverTickHorizon")
            checkNoClaim("重复无 down up")
            check(n("cross.cancel") == 0, "cancel 只执行一次")
            checkNoLowerInput("重复 up")
        end)
        runCase("浮选详情按压后离线出现：取消浮选，无 finish/input/领取", function()
            fixture("tri", 2, true, false)
            state.detail, state.detailHit = true, true
            clearCalls()
            positionPanel("left", 140, 1060)
            invoke("HandleMouseButtonDownHorizon", left)
            check(n("detail.handleDragBegin") == 1 and n("cross.arm") == 0, "真实浮层先接到 down")
            clearCalls()
            state.offline = true
            positionOverlay(540, 1375)
            invoke("HandleMouseButtonUpHorizon", left)
            check(n("detail.handleDragEnd") == 1 and n("detail.handleInput") == 0,
                "只释放浮层按压，不执行浮选点击")
            check(n("cross.finish") == 0 and n("seam.close") == 0 and n("action") == 0,
                "浮选旧 up 不落点、不关下层页面、不发 action")
            check(n("offline.down") == 0, "浮选旧按压不是 offline down")
            checkNoClaim("旧浮选 up")
            checkNoLowerInput("旧浮选 up", { ["detail.handleDragEnd"] = true })
            clearCalls()
            invoke("HandleMouseButtonUpHorizon", left)
            checkNoClaim("浮选重复 up")
            checkNoLowerInput("浮选重复 up")
        end)

        for _, dpr in ipairs({ 1, 2, 3 }) do
            runCase("TouchID/X/Y-only DPR=" .. dpr .. " 单指坐标正确，第二指不可领取", function()
                fixture("tri", dpr, true)
                clearCalls()
                positionWindow(250, 100) -- 鼠标故意在另一栏，touch 绝不能读取 GetMousePosition。
                local x, y = overlayPosition(540, 1375)
                local primary = touch(41, x, y)
                local secondary = touch(42, x, y)
                check(primary.Button == nil and secondary.Button == nil, "touch payload 确实没有 Button")
                check(cursor.x ~= x and cursor.y ~= y, "鼠标与触摸物理坐标确实不同")
                invoke("HandleTouchEndHorizon", secondary)
                checkNoClaim("没有 offline down 的触摸 up")
                invoke("HandleTouchBeginHorizon", primary)
                checkXY("offline.down", 540, 1375, "第一指")
                invoke("HandleTouchBeginHorizon", secondary)
                local outX, outY = overlayPosition(740, 1375)
                invoke("HandleTouchMoveHorizon", touch(42, outX, outY))
                clock.elapsedTime = clock.elapsedTime + 0.2
                invoke("HandleTouchEndHorizon", secondary)
                check(n("offline.down") == 1 and n("offline.move") == 0 and n("offline.up") == 0,
                    "第二指 down/move/up 不覆盖主指或结束按压")
                checkNoClaim("第二指释放")
                invoke("HandleTouchMoveHorizon", primary)
                clock.elapsedTime = clock.elapsedTime + 0.2
                invoke("HandleTouchEndHorizon", primary)
                checkXY("offline.move", 540, 1375, "主指仍持有 capture")
                checkXY("offline.up", 540, 1375, "第一指 up")
                checkXY("offline.input", 540, 1375, "第一指 tap")
                check(n("offline.claim") == 1 and n("offline.up") == 1, "只有第一指正确领取一次")
                clock.elapsedTime = clock.elapsedTime + 0.2
                invoke("HandleTouchEndHorizon", secondary)
                check(n("offline.claim") == 1 and n("offline.input") == 1 and n("offline.up") == 1,
                    "主指结束后的第二指 up 仍不可领取")
                checkNoLowerInput("touch 主/副指")
            end)
        end
        runCase("弹窗关闭后旧鼠标 Up 不穿透中缝", function()
            fixture("tri")
            clearCalls()
            positionWindow(505.6, 1080 * 0.469)
            invoke("HandleMouseButtonDownHorizon", left)
            state.offline = false
            invoke("HandleMouseButtonUpHorizon", left)
            check(n("seam.close") == 0, "关闭动画结束后旧离线按压不关闭下层页面")
            checkNoClaim("closed-before-up")
        end)
        runCase("tri 来源拖拽中途弹窗出现仍释放", function()
            fixture("tri", 1, false, false)
            clearCalls()
            positionWindow(960, 506)
            invoke("HandleMouseButtonDownHorizon", left)
            check(n("tri.handleDragBegin") == 1, "三行页面收到原拖拽")
            state.offline = true
            invoke("HandleMouseButtonUpHorizon", left)
            check(n("tri.handleDragEnd") == 1, "离线接管结束三行来源拖拽")
            check(n("tri.handleInput") == 0, "不能把来源 Up 派成三行点击")
            checkNoClaim("tri old press")
        end)
        for _, top in ipairs({ "title", "letter", "story" }) do
            runCase(top .. " 显示时离线让出绘制与 Touch", function()
                fixture("tri")
                clearCalls()
                state[top] = true
                invoke("HandleNanoVGRenderHorizon")
                check(n("offline.draw") == 0, "高层覆盖时不画离线")
                local x, y = overlayPosition(540, 1375)
                local event = touch(8, x, y)
                invoke("HandleTouchBeginHorizon", event)
                invoke("HandleTouchEndHorizon", event)
                local target = top == "story" and "story.advance" or top .. ".tap"
                check(n(target) == 1, "真实无 Button Touch 派到高层 " .. target)
                checkNoClaim("top touch")
            end)
        end
        runCase("CE 接管鼠标时取消离线领取", function()
            fixture("tri")
            clearCalls()
            state.ce = true
            positionOverlay(540, 1375)
            click()
            check(n("ce.up") == 1, "CE Down/Up 优先级一致")
            checkNoClaim("CE")
        end)

        -- 升级回归只验证宿主的真实 render/input 链；Popup 以 spy 实现新宽高接口，
        -- 不在这里复制它的 widget/动画/领取逻辑，不将 mock pass 当成真实像素验收。
        local levelAllowed = { ["level.handleInput"] = true }
        for _, mode in ipairs({ "ordinary", "tri", "tower" }) do
            for _, dpr in ipairs({ 1, 2, 3 }) do
                runCase(mode .. " LevelUp 全窗+DPR=" .. dpr .. " 唯一绘制与左右中输入", function()
                    fixture(mode, dpr, true, false)
                    state.level, state.pip, state.talent = true, true, true
                    clearCalls()
                    for key in pairs(drawings) do drawings[key] = nil end
                    invoke("HandleNanoVGRenderHorizon")
                    checkDraw("level", mode .. " level frame/DPR")
                    local levelIndex, ceIndex, pipIndex = 0, 0, 0
                    for index, draw in ipairs(drawings) do
                        if draw.name == "level" then levelIndex = index end
                        if draw.name == "ce" then ceIndex = index end
                        if draw.name == "pip" then pipIndex = index end
                    end
                    check(ceIndex > levelIndex and levelIndex > pipIndex, "升级位于PIP/业务之上、CE之下")
                    clearCalls()
                    for _, x in ipairs({ 250, 960, 1680 }) do
                        positionWindow(x, 505)
                        invoke("HandleMouseMoveHorizon")
                        invoke("HandleEquipmentHoverTickHorizon")
                        click()
                        click(right)
                        invoke("HandleMouseWheelHorizon", wheel)
                        checkXY("level.handleInput", x, 505, "宿主frame逆变换")
                        -- 每轮清空事件，保证 checkXY 不拿上一区的点作比较。
                        for key in pairs(events) do events[key] = nil end
                    end
                    check(n("level.handleInput") == 3, "仅左键三次tap，右键/wheel/hover不触发升级")
                    checkNoLowerInput("LevelUp 全窗输入", levelAllowed)
                end)
            end
        end
        for _, mode in ipairs({ "ordinary", "tri", "tower" }) do
            runCase(mode .. " LevelUp/Offline/Update/CE 模态顺序保留", function()
                fixture(mode)
                state.level, state.pip, state.notice = true, true, true
                clearCalls()
                for key in pairs(drawings) do drawings[key] = nil end
                invoke("HandleNanoVGRenderHorizon")
                local order = {}
                for index, draw in ipairs(drawings) do order[draw.name] = index end
                check(order.level < order.offline and order.offline < order.notice and order.notice < order.ce,
                    "draw升级<离线<更新<CE")
                positionWindow(505.6, 1080 * 0.469)
                click()
                check(n("notice.input") == 1 and n("level.handleInput") == 0 and n("offline.input") == 0,
                    "Update先消费，不向离线/升级派tap")
                state.notice = false
                clearCalls()
                click()
                check(n("offline.input") == 1 and n("level.handleInput") == 0, "Offline先于升级")
                state.offline, state.ce = false, true
                clearCalls()
                click()
                invoke("HandleMouseWheelHorizon", wheel)
                check(n("ce.up") == 1 and n("ce.wheel") == 1 and n("level.handleInput") == 0, "CE先于升级")
                checkNoLowerInput("top chain")
            end)
        end
        for _, seam in ipairs({ { name = "left", x = 505.6 }, { name = "right", x = 1414.4 } }) do
            for _, modal in ipairs({ "level", "pip" }) do
                runCase(seam.name .. " seam " .. modal .. " 不点穿", function()
                    fixture("tri", 2, true, false)
                    state[modal], state.detailHit = true, true
                    clearCalls()
                    positionWindow(seam.x, 1080 * 0.469)
                    click()
                    check(n("seam.close") == 0 and state.warehouse and state.detailHit, "模态不关闭仓库/角色详情")
                    if modal == "level" then
                        check(n("level.handleInput") == 1 and n("pip.handleInput") == 0, "升级先于PIP/seam")
                        checkNoLowerInput("level seam", levelAllowed)
                    else
                        check(n("pip.handleInput") == 1, "PIP用自身坐标消费seam点")
                    end
                end)
            end
        end
        runCase("PIP滚轮优先于Talent/Battle", function()
            fixture("tri", 2, true, false)
            state.pip, state.talent = true, true
            clearCalls()
            positionWindow(250, 505)
            invoke("HandleMouseWheelHorizon", wheel)
            check(n("pip.handleScroll") == 1 and n("talent.handleScroll") == 0 and n("tri.handleScroll") == 0,
                "PIP在古树缩放/战斗装备袋之前接滚轮")
        end)
        for _, source in ipairs({ "cross", "detail", "card", "tri" }) do
            runCase(source .. " 旧按压中途升级：cancel不finish/tap", function()
                fixture("tri", 2, true, false)
                if source == "cross" then state.grid = true
                elseif source == "detail" then state.detail, state.detailHit = true, true end
                clearCalls()
                if source == "card" then positionPanel("right", 140, 1060)
                elseif source == "tri" then positionWindow(960, 505)
                else positionPanel("left", 140, 1060) end
                invoke("HandleMouseButtonDownHorizon", left)
                if source == "card" then state.draggingCard = true end
                check(source ~= "cross" or state.armed, "cross来自真实Horizon down")
                clearCalls()
                state.level = true
                positionWindow(505.6, 1080 * 0.469)
                invoke("HandleMouseButtonUpHorizon", left)
                check(n("cross.finish") == 0 and n("seam.close") == 0 and n("level.handleInput") == 0,
                    "旧来源Up不落点/点seam/误触升级按钮")
                if source == "cross" then
                    check(n("cross.cancel") == 1 and n("backpack.handleDragEnd") == 1 and not state.armed,
                        "cross取消并释放来源")
                elseif source == "detail" then
                    check(n("detail.handleDragEnd") == 1 and n("detail.handleInput") == 0, "只释放浮选，不点击/关闭它")
                elseif source == "card" then
                    check(n("character.handleDragEnd") == 1 and n("character.handleInput") == 0 and not state.draggingCard,
                        "只取消角色拖拽，不交换卡片")
                else
                    check(n("tri.handleDragEnd") == 1 and n("tri.handleInput") == 0, "只释放三行来源拖拽")
                end
            end)
        end
        for _, kind in ipairs({ "mouse", "touch" }) do
            for _, cancelled in ipairs({ "closed", "moved", "resized" }) do
                runCase("LevelUp " .. kind .. " " .. cancelled .. " 消费但不tap", function()
                    fixture("tri", 2, true, false)
                    state.level = true
                    clearCalls()
                    local x, y = framePosition(505, 505)
                    if kind == "mouse" then
                        positionWindow(505, 505)
                        invoke("HandleMouseButtonDownHorizon", left)
                    else
                        invoke("HandleTouchBeginHorizon", touch(51, x, y))
                    end
                    if cancelled == "closed" then state.level = false
                    elseif cancelled == "resized" then RT.logicalW = 2000
                    elseif kind == "mouse" then
                        positionWindow(550, 505)
                        invoke("HandleMouseMoveHorizon")
                        positionWindow(505, 505)
                        invoke("HandleMouseMoveHorizon")
                    else
                        local ox, oy = framePosition(550, 505)
                        invoke("HandleTouchMoveHorizon", touch(51, ox, oy))
                        invoke("HandleTouchMoveHorizon", touch(51, x, y))
                    end
                    if kind == "mouse" then invoke("HandleMouseButtonUpHorizon", left)
                    else invoke("HandleTouchEndHorizon", touch(51, x, y)) end
                    check(n("level.handleInput") == 0 and n("seam.close") == 0, "旧/移动/尺寸变更Up不派tap")
                    checkNoLowerInput("level cancel")
                end)
            end
        end
        for _, dpr in ipairs({ 1, 2, 3 }) do
            runCase("LevelUp TouchID/X/Y-only DPR=" .. dpr .. " 主副指/mouse分离", function()
                fixture("tri", dpr, true, false)
                state.level, state.pip = true, true
                clearCalls()
                positionWindow(250, 100)
                local x, y = framePosition(960, 505)
                local primary, secondary = touch(61, x, y), touch(62, x, y)
                invoke("HandleTouchBeginHorizon", primary)
                invoke("HandleTouchBeginHorizon", secondary)
                invoke("HandleTouchMoveHorizon", secondary)
                invoke("HandleTouchEndHorizon", secondary)
                check(n("level.handleInput") == 0, "副指不能结束主指升级tap")
                invoke("HandleTouchMoveHorizon", primary)
                invoke("HandleTouchEndHorizon", primary)
                checkXY("level.handleInput", 960, 505, "touch frame+DPR")
                check(n("level.handleInput") == 1, "只有主指派一次tap")
                checkNoLowerInput("level touch", levelAllowed)
                -- 主指先结束并关闭后，已捕获的副指结束仍不得走无Button鼠标/seam链。
                invoke("HandleTouchBeginHorizon", primary)
                invoke("HandleTouchBeginHorizon", secondary)
                invoke("HandleTouchEndHorizon", primary)
                state.level = false
                invoke("HandleTouchEndHorizon", secondary)
                check(n("level.handleInput") == 2 and n("seam.close") == 0, "关闭后副指Up仍消费")
            end)
        end

        runCase("LevelUp已打开：Down不碰浮选详情", function()
            fixture("tri", 2, true, false)
            state.level, state.detail, state.detailHit = true, true, true
            clearCalls()
            positionPanel("left", 140, 1060)
            click()
            check(n("level.handleInput") == 1 and n("detail.handleDragBegin") == 0
                and n("detail.close") == 0 and n("detail.handleInput") == 0,
                "升级Down早于装备浮选命中和空白关闭")
            check(state.detail and n("cross.arm") == 0, "下层候选保持，不启动跨栏装备手势")
            checkNoLowerInput("level before detail", levelAllowed)
        end)
        for _, property in ipairs({ "frameScale", "frameOx", "frameOy", "dpr" }) do
            runCase("LevelUp按压后 " .. property .. " 变更不tap", function()
                fixture("tri", 2, true, false)
                state.level = true
                clearCalls()
                positionWindow(960, 505)
                invoke("HandleMouseButtonDownHorizon", left)
                RT[property] = RT[property] + 1
                positionWindow(960, 505)
                invoke("HandleMouseButtonUpHorizon", left)
                check(n("level.handleInput") == 0 and n("seam.close") == 0, "frame/DPR变化不能误投升级按钮")
                checkNoLowerInput("level frame changed")
            end)
        end
        for _, kind in ipairs({ "mouse", "touch" }) do
            runCase("LevelUp旧" .. kind .. "按压后Update接管", function()
                fixture("tri", 2, true, false)
                state.level = true
                clearCalls()
                positionWindow(960, 505)
                local x, y = framePosition(960, 505)
                if kind == "mouse" then invoke("HandleMouseButtonDownHorizon", left)
                else invoke("HandleTouchBeginHorizon", touch(91, x, y)) end
                state.notice = true
                if kind == "mouse" then invoke("HandleMouseButtonUpHorizon", left)
                else invoke("HandleTouchEndHorizon", touch(91, x, y)) end
                check(n("notice.input") == 1 and n("level.handleInput") == 0, "后出现的Update仍高于升级捕获")
                checkNoLowerInput("update interrupt level")
            end)
        end

        for _, towerTri in ipairs({ false, true }) do
            for _, dpr in ipairs({ 1, 2, 3 }) do
                runCase("Tower Task tri=" .. tostring(towerTri) .. " DPR=" .. dpr .. " 覆盖/输入/返回保留塔", function()
                    fixture("tower", dpr, true, false)
                    state.task, state.towerTri, state.talent, state.dungeon = true, towerTri, true, true
                    clearCalls()
                    for key in pairs(drawings) do drawings[key] = nil end
                    invoke("HandleNanoVGRenderHorizon")
                    local taskDraw = nil ---@type any
                    local towerIndex = nil ---@type integer?
                    local taskIndex = nil ---@type integer?
                    local taskCount = 0
                    for index, draw in ipairs(drawings) do
                        if draw.name == "tower" then towerIndex = index end
                        if draw.name == "task" then taskDraw, taskIndex, taskCount = draw, index, taskCount + 1 end
                    end
                    check(taskCount == 1 and towerIndex < taskIndex, "Task唯一绘制且高于塔")
                    check(taskDraw and taskDraw.viewportDepth == 1 and closeEnough(taskDraw.sx, RT.frameScale * 0.45)
                        and closeEnough(taskDraw.tx, RT.frameOx) and closeEnough(taskDraw.ty, RT.frameOy),
                        "Task使用0,0左栏Viewport与frame变换")
                    check(taskDraw and taskDraw.clip and closeEnough(taskDraw.clip.w, 486 * RT.frameScale)
                        and closeEnough(taskDraw.clip.h, 1080 * RT.frameScale), "Task clip只覆盖左栏")
                    check(H_SEAM_BACK == false, "塔早退无seam条，自带返回可画可点")
                    clearCalls()
                    positionPanel("left", 540, 396)
                    click()
                    checkXY("task.handleDragBegin", 540, 396, "塔Task down")
                    checkXY("task.handleDragEnd", 540, 396, "塔Task up")
                    checkXY("task.handleInput", 540, 396, "塔Task tab")
                    check(n("tower.handleClick") == 0 and n("tri.handleInput") == 0, "左栏tap不交塔/tri")
                    clearCalls()
                    positionPanel("left", 540, 1200)
                    invoke("HandleMouseButtonDownHorizon", left)
                    positionPanel("left", 540, 1000)
                    invoke("HandleMouseMoveHorizon")
                    invoke("HandleMouseButtonUpHorizon", left)
                    checkXY("task.handleDragMove", 540, 1000, "塔Task drag")
                    check(n("task.handleInput") == 0 and n("task.handleDragEnd") == 1, "拖动不领取但结束Task拖拽")
                    clearCalls()
                    positionWindow(486, 505)
                    click()
                    checkXY("task.handleInput", 1080, 505 / 0.45, "左栏边界包含")
                    clearCalls()
                    positionWindow(250, 505)
                    invoke("HandleMouseWheelHorizon", wheel)
                    check(n("task.handleScroll") == 1 and n("talent.handleScroll") == 0
                        and n("tri.handleScroll") == 0 and n("dungeon.handleScroll") == 0,
                        "Task滚轮先于Talent/Battle/Dungeon")
                    clearCalls()
                    for _, x in ipairs({ 505.6, 960, 1680 }) do
                        positionWindow(x, 1080 * 0.469)
                        click()
                        invoke("HandleMouseWheelHorizon", wheel)
                    end
                    check(n("task.handleInput") == 0 and n("task.handleScroll") == 0 and n("tower.handleClick") == 0
                        and n("tri.handleInput") == 0 and n("tri.handleScroll") == 0 and n("seam.close") == 0,
                        "非左栏输入/wheel/seam全部消费")
                    clearCalls()
                    positionPanel("left", 958, 1150)
                    click()
                    check(n("task.close") == 1 and not state.task and state.mode == "tower" and state.towerFloor == 7,
                        "页面自带返回仅关Task，塔楼层仍保留")
                    state.dungeon = false
                    clearCalls()
                    positionWindow(960, 505)
                    click()
                    check(n("tower.handleClick") == 1 and n("tri.handleInput") == 0 and n("tower.close") == 0,
                        "关闭Task后恢复塔点击，即使tri仍open")
                end)
            end
        end
        runCase("Tower Task低于Reward/PIP/LevelUp", function()
            fixture("tower", 2, true, false)
            state.task, state.towerTri, state.reward, state.pip, state.level = true, true, true, true, true
            clearCalls()
            for key in pairs(drawings) do drawings[key] = nil end
            invoke("HandleNanoVGRenderHorizon")
            local order = {}
            for index, draw in ipairs(drawings) do order[draw.name] = index end
            check(order.tower < order.task and order.task < order.reward and order.reward < order.pip
                and order.pip < order.level, "塔<Task<Reward<PIP<LevelUp")
            positionWindow(250, 505)
            click()
            check(n("level.handleInput") == 1 and n("task.handleInput") == 0, "升级保持最高业务输入")
            state.level, state.reward = false, false
            clearCalls()
            positionOverlay(540, 1375)
            click()
            checkXY("pip.handleInput", 540, 1375, "塔PIP draw/input letterbox一致")
            check(n("task.handleInput") == 0 and n("tower.handleClick") == 0, "PIP不下放Task/塔")
        end)

        for _, kind in ipairs({ "mouse", "touch" }) do
            runCase(kind .. " 拖出再回原点不能 tap", function()
                fixture("tri", 2, true)
                clearCalls()
                if kind == "mouse" then
                    positionOverlay(540, 1375)
                    invoke("HandleMouseButtonDownHorizon", left)
                    positionOverlay(740, 1375)
                    invoke("HandleMouseMoveHorizon")
                    positionOverlay(540, 1375)
                    invoke("HandleMouseMoveHorizon")
                    clock.elapsedTime = clock.elapsedTime + 0.3
                    invoke("HandleMouseButtonUpHorizon", left)
                else
                    local x, y = overlayPosition(540, 1375)
                    local outX, outY = overlayPosition(740, 1375)
                    invoke("HandleTouchBeginHorizon", touch(5, x, y))
                    invoke("HandleTouchMoveHorizon", touch(5, outX, outY))
                    invoke("HandleTouchMoveHorizon", touch(5, x, y))
                    clock.elapsedTime = clock.elapsedTime + 0.3
                    invoke("HandleTouchEndHorizon", touch(5, x, y))
                end
                check(n("offline.down") == 1 and n("offline.move") == 2 and n("offline.up") == 1,
                    "完整 down -> 移出 -> 回原点 -> up 链")
                checkNoClaim(kind .. " sticky moved")
                checkNoLowerInput(kind .. " drag return")
            end)
        end
    end)
    if not ok then check(false, "Start exception: " .. tostring(err)) end

    -- 无论断言/模块异常，都恢复 require、引擎全局、真实 RT/Viewport 与全部 NanoVG stub。
    rawset(_G, "require", originalRequire)
    rawset(_G, "input", originalInput)
    rawset(_G, "time", originalTime)
    for name, saved in pairs(originalNvg) do rawset(_G, name, saved.value) end
    if RT then restoreTable(RT, originalRT) end
    if viewport then
        viewport._notes = originalNotes
        for name, fn in pairs(originalViewport) do viewport[name] = fn end
    end
    package.loaded["boot.StandaloneHorizon"] = originalLoadedHorizon
    local addedGlobals = {}
    for key in pairs(_G) do
        if horizonGlobal(key) and originalGlobals[key] == nil then addedGlobals[#addedGlobals + 1] = key end
    end
    for _, key in ipairs(addedGlobals) do rawset(_G, key, nil) end
    for key, value in pairs(originalGlobals) do rawset(_G, key, value) end
    if failures == 0 then
        print("[offline_overlay_horizon_test] ALL PASS: " .. casePasses .. "/" .. caseCount
            .. " cases, " .. assertions .. " assertions")
    else
        print("[FAIL] offline_overlay_horizon_test: " .. casePasses .. "/" .. caseCount
            .. " cases passed, " .. failures .. " failures, " .. assertions .. " assertions")
    end
    engine:Exit()
end
