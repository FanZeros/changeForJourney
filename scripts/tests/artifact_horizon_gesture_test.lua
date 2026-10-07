-- 神器横屏宿主回归：真实 ArtifactGesture / HorizonInput / Horizon / Viewport。
-- 其它页面只用内存 spy；不读写玩家存档、不执行安装/洗练、不以源码字符串代替调用。
function Start()
    local originalRequire = require
    local RT = originalRequire("boot.StandaloneRT")
    local VP = originalRequire("core.Viewport")
    local oldRT, oldGlobals, oldNotes = {}, {}, VP._notes
    for key, value in pairs(RT) do oldRT[key] = value end
    for key, value in pairs(_G) do oldGlobals[key] = value end
    local assertions = 0
    local ok, err = pcall(function()
        local function check(condition, label)
            assertions = assertions + 1
            assert(condition, label)
        end
        local function near(a, b, label)
            check(type(a) == "number" and math.abs(a - b) < 0.00001,
                label .. " actual=" .. tostring(a) .. " expected=" .. tostring(b))
        end
        local function noop() return false end
        ---@return any
        local function mock(values)
            return setmetatable(values or {}, { __index = function() return noop end })
        end
        ---@type any
        local state = { tri = false, church = true, arm = false, dragging = false,
            pointer = false, gates = {}, clock = 100, lastX = 0, lastY = 0 }
        ---@type any
        local events = {}
        ---@type any
        local cursor = { x = 0, y = 0 }
        ---@type any
        local ctx = { tx = 0, ty = 0, sx = 1, sy = 1, clip = nil, stack = {} }
        local function record(name, x, y)
            events[#events + 1] = { name = name, x = x, y = y,
                tx = ctx.tx, ty = ctx.ty, sx = ctx.sx, sy = ctx.sy,
                clip = ctx.clip, clock = state.clock }
        end
        local function count(name)
            local n = 0
            for _, event in ipairs(events) do if event.name == name then n = n + 1 end end
            return n
        end
        ---@return any
        local function last(name)
            for i = #events, 1, -1 do if events[i].name == name then return events[i] end end
            return nil
        end
        local function index(name)
            for i, event in ipairs(events) do if event.name == name then return i end end
            return 0
        end
        local function clear() events = {} end
        local function rect(x, y, w, h)
            return { x = ctx.tx + x * ctx.sx, y = ctx.ty + y * ctx.sy,
                w = w * ctx.sx, h = h * ctx.sy }
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
            local saved = assert(table.remove(ctx.stack), "NanoVG save/restore不配对")
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
            record("frame.begin")
        end
        nvgEndFrame = function()
            check(#ctx.stack == 0, "Horizon每帧恢复全部NanoVG状态")
            record("frame.end")
        end
        for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgFillColor", "nvgFill" }) do _G[name] = noop end
        input = { GetMousePosition = function() return cursor end }
        time = { elapsedTime = state.clock }

        local function page(name)
            return mock({
                isOpen = function() return state.gates[name] == true end,
                isActive = function() return state.gates[name] == true end,
                draw = function() record(name .. ".draw") end,
                handleInput = function(x, y) record(name .. ".tap", x, y); return true end,
                handleDragBegin = function(x, y) record(name .. ".down", x, y); return true end,
                handleDragMove = function(x, y) record(name .. ".move", x, y); return true end,
                handleDragEnd = function(x, y) record(name .. ".up", x, y); return true end,
                handleHover = function(x, y) record(name .. ".hover", x, y) end,
                getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
            })
        end
        local church = page("church")
        church.isOpen = function() return state.church end
        church.isArtifactInputActive = function() return state.church end
        church.close = function()
            record("church.close")
            state.church = false
        end
        local panel = mock({
            handleDragBegin = function(x, y)
                state.pointer, state.dragging = true, false
                state.startX, state.startY, state.lastX, state.lastY = x, y, x, y
                record("artifact.down", x, y)
            end,
            handleDragMove = function(x, y)
                state.lastX, state.lastY = x, y
                if state.pointer and state.arm
                    and math.abs(x - state.startX) + math.abs(y - state.startY) >= 24 then
                    state.dragging = true
                end
                record("artifact.move", x, y)
            end,
            handleDragEnd = function(x, y)
                record("artifact.up", x, y)
                local dragged = state.dragging
                state.pointer, state.dragging = false, false
                return dragged
            end,
            cancelPointer = function()
                state.pointer, state.dragging = false, false
                record("artifact.cancel")
            end,
            handleHover = function(x, y) record("artifact.leave", x, y) end,
            isItemDragging = function() return state.dragging end,
            drawDragOverlay = function()
                record("artifact.overlay", state.lastX, state.lastY)
            end,
        })
        local tri = page("tri")
        tri.isOpen = function() return state.tri end
        tri.drawHud = function() record("tri.hud") end
        local character = page("character")
        character.getTotalPower = function() return 0 end
        local gates = {
            ["ui.backpack.BackpackPanel"] = "backpack", ["ui.story.task.TaskPage"] = "task",
            ["ui.loot.LootBoxPage"] = "lootpage", ["ui.church.talent.TalentPage"] = "talent",
            ["ui.market.MarketPage"] = "market", ["ui.tavern.TavernPage"] = "tavern",
            ["ui.tower.TowerBattleScene"] = "tower", ["ui.dungeon.DungeonBattleScene"] = "dungeon",
            ["ui.hud.popup.RewardPopup"] = "reward", ["ui.hud.popup.PlayerInfoPanel"] = "player",
            ["ui.hud.popup.OfflineRewardPanel"] = "offline", ["ui.hud.popup.LevelUpPopup"] = "level",
            ["ui.hud.popup.UpdateNoticePopup"] = "notice", ["ui.battle.stage.SweepDialog"] = "sweep",
            ["ui.battle.popup.DamageStatsPanel"] = "damage", ["ui.battle.stage.StageSelectDialog"] = "stage",
            ["ui.battle.popup.TerminalConfirmDialog"] = "terminal",
            ["ui.tavern.TavernPopups"] = "tavernPopups", ["ui.tavern.TargetRecruitPanel"] = "targetRecruit",
            ["systems.TutorialManager"] = "tutorial", ["ui.story.gate.DarkTitleScreenGate"] = "title",
            ["ui.story.gate.StartScreen"] = "start", ["ui.story.gate.LetterIntro"] = "letter",
            ["ui.story.gate.IntroCutscene"] = "intro", ["ui.story.ScenarioDialogue"] = "scenario",
        }
        ---@type any
        local mods = {
            ["boot.StandaloneRT"] = RT, ["core.Viewport"] = VP,
            ["ui.church.ChurchPage"] = church, ["ui.church.ChurchArtifactPanel"] = panel,
            ["ui.character.hero.ArtifactDetailPanel"] = mock({
                dismissHover = function() record("detail.dismiss") end,
                closeImmediate = function() record("detail.close") end,
            }),
            ["ui.battle.tri.BattleTriPage"] = tri, ["ui.character.panel.CharacterPanel"] = character,
            ["ui.battle.scene.BattleScene"] = page("battle"), ["ui.town.TownScene"] = page("town"),
            ["ui.hud.BottomNav"] = { getSelectedIndex = function() return 3 end },
            ["core.DarkIcon"] = mock({ SHOWCASE = false }),
            ["core.DrawUtil"] = mock({ SEAMBAR_ASPECT = 0.04, SEAMBAR_ARROW_Y = 0.469,
                seamSlideX = function() return 0 end }),
            ["ui.character.EquipCrossDrag"] = mock({ draw = function() record("equipment.overlay") end }),
            ["ui.dev.KeyboardShortcuts"] = mock({ draw = function() record("keyboard.draw") end }),
            ["ui.dev.CEPanel"] = mock({ draw = function() record("ce.draw") end }),
        }
        for path, name in pairs(gates) do mods[path] = page(name) end
        mods["ui.hud.popup.RewardPopup"].currentPanel = function() return nil end
        mods["ui.hud.popup.RewardPopup"].currentRowTag = function() return nil end
        local realPaths = {
            ["boot.ArtifactGesture"] = true, ["boot.StandaloneHorizon"] = true,
            ["boot.StandaloneHorizonInput"] = true, ["boot.OfflineRewardOverlay"] = true,
            ["boot.SeamBackGesture"] = true, ["boot.DecomposeMarqueeGesture"] = true,
            ["boot.StandaloneHorizonWheel"] = true,
        }
        ---@type any
        local realModules = {}
        require = function(name)
            if realPaths[name] then
                if realModules[name] == nil then realModules[name] = originalRequire(name) end
                return realModules[name]
            end
            if not mods[name] then mods[name] = mock() end
            return mods[name]
        end
        for key in pairs(RT) do RT[key] = nil end
        RT.vg, RT.logicalW, RT.logicalH, RT.windowW, RT.windowH = {}, 1920, 1080, 1920, 1080
        RT.dpr, RT.bootReady_, RT.preload_ = 1, true, { active = false }
        VP._notes = {}
        require("boot.StandaloneHorizon")
        check(realModules["boot.ArtifactGesture"] ~= nil and realModules["boot.StandaloneHorizonInput"] ~= nil,
            "Horizon入口实际加载真实ArtifactGesture与HorizonInput")

        local button = { Button = { GetInt = function() return MOUSEB_LEFT end } }
        local function tick()
            state.clock = state.clock + 1
            time.elapsedTime = state.clock
        end
        local function screen(panelId, x, y)
            local note, p = assert(VP.getNote(panelId)), VP.PANELS[panelId]
            local sx = note.ox + p.bx * note.s + x * (note.scaleX or note.s * VP.DS)
            local sy = note.oy + p.by * note.s + y * note.s * VP.DS
            return ((RT.frameOx or 0) + sx * (RT.frameScale or 1)) * RT.dpr,
                ((RT.frameOy or 0) + sy * (RT.frameScale or 1)) * RT.dpr
        end
        local function position(panelId, x, y) cursor.x, cursor.y = screen(panelId, x, y) end
        local function down(panelId, x, y)
            position(panelId, x, y)
            HandleMouseButtonDownHorizon("MouseButtonDown", button)
        end
        local function move(panelId, x, y)
            position(panelId, x, y)
            HandleMouseMoveHorizon("MouseMove", {})
        end
        local function up(panelId, x, y)
            position(panelId, x, y); tick()
            HandleMouseButtonUpHorizon("MouseButtonUp", button)
        end
        local function touch(id, panelId, x, y, handler)
            local px, py = screen(panelId, x, y)
            px, py = math.floor(px + 0.5), math.floor(py + 0.5)
            local data = { TouchID = { GetInt = function() return id end },
                X = { GetInt = function() return px end }, Y = { GetInt = function() return py end } }
            tick(); handler("Touch", data)
            return px, py
        end
        local function fromLeft(px, py)
            local note, p = assert(VP.getNote("left")), VP.PANELS.left
            local sx = (px / RT.dpr - (RT.frameOx or 0)) / (RT.frameScale or 1)
            local sy = (py / RT.dpr - (RT.frameOy or 0)) / (RT.frameScale or 1)
            return (sx - note.ox - p.bx * note.s) / (note.scaleX or note.s * VP.DS),
                (sy - note.oy - p.by * note.s) / (note.s * VP.DS)
        end
        local function noForeignTap(label)
            for _, name in ipairs({ "character", "battle", "tri", "town", "backpack", "task", "talent",
                "market", "tavern", "lootpage" }) do
                check(count(name .. ".tap") == 0, label .. "不得向其它页派tap " .. name)
            end
        end
        local function fixture(triMode, dprValue, framed)
            state.tri, state.church, state.arm, state.dragging, state.pointer = triMode, true, false, false, false
            state.gates = {}
            RT.logicalW, RT.logicalH, RT.windowW, RT.windowH = 1920, 1080, 1920, 1080
            RT.dpr, RT.frameScale = dprValue, framed and 0.82 or 1
            RT.frameOx, RT.frameOy = framed and 97 or 0, framed and 41 or 0
            HandleNanoVGRenderHorizon()
            clear()
        end

        -- A：12组真实宿主布局（普通/三行 × DPR1/2/3 × 无/有frame变换）。
        for _, triMode in ipairs({ false, true }) do
            for _, dprValue in ipairs({ 1, 2, 3 }) do
                for _, framed in ipairs({ false, true }) do
                    fixture(triMode, dprValue, framed)
                    local label = "tri=" .. tostring(triMode) .. " dpr=" .. dprValue .. " framed=" .. tostring(framed)
                    down("left", 140, 1300)
                    check(count("artifact.down") == 1 and count("church.down") == 0, label .. "神器独占down")
                    near(last("artifact.down").x, 140, label .. "down设计x")
                    near(last("artifact.down").y, 1300, label .. "down设计y")
                    local px, py = screen("right", 140, 1300)
                    local ex, ey = fromLeft(px, py)
                    up("right", 140, 1300)
                    check(count("artifact.up") == 1 and count("church.tap") == 0, label .. "跨栏up只结束原手势")
                    near(last("artifact.up").x, ex, label .. "up仍用原left坐标而非right局部x")
                    near(last("artifact.up").y, ey, label .. "up仍用原left坐标y")
                    check(ex > 1080 and not state.pointer, label .. "跨栏确实越出原面板并清press")
                    noForeignTap(label)

                    clear(); down("left", 140, 1300); up("left", 145, 1302)
                    check(count("church.tap") == 1, label .. "小抖动真实tap只派一次")
                    near(last("church.tap").x, 145, label .. "tap落点x")
                    near(last("church.tap").y, 1302, label .. "tap落点y")
                    noForeignTap(label)

                    clear(); down("left", 140, 1300)
                    move("left", 400, 1300); move("left", 140, 1300); up("left", 140, 1300)
                    check(count("artifact.move") == 2 and count("artifact.up") == 1,
                        label .. "真实move捕获并结束")
                    check(count("church.tap") == 0, label .. "移远又移回不能变tap")

                    clear(); position("left", 210, 1380)
                    HandleEquipmentHoverTickHorizon(); tick(); HandleEquipmentHoverTickHorizon()
                    check(count("church.hover") == 2, label .. "静止鼠标HoverTick连续接Church")
                    near(last("church.hover").x, 210, label .. "hover设计x")
                    near(last("church.hover").y, 1380, label .. "hover设计y")
                    check(last("church.hover").clock > events[1].clock, label .. "静止推进不同时间")
                    position("right", 210, 1380); HandleEquipmentHoverTickHorizon()
                    check(count("artifact.leave") == 1 and count("church.hover") == 2,
                        label .. "离开left不伪造Church悬停")

                    clear(); state.arm = true
                    down("left", 140, 1300); move("left", 300, 1450)
                    check(state.dragging, label .. "内存神器已起拖")
                    clear(); HandleNanoVGRenderHorizon()
                    check(count("artifact.overlay") == 1, label .. "finishFrame拖拽末层只画一次")
                    local overlay, note = last("artifact.overlay"), VP.getNote("left")
                    near(overlay.tx, RT.frameOx + note.ox * RT.frameScale, label .. "overlay同note原点x")
                    near(overlay.ty, RT.frameOy + note.oy * RT.frameScale, label .. "overlay同note原点y")
                    near(overlay.sx, RT.frameScale * (note.scaleX or note.s * VP.DS), label .. "overlay同note横向scale")
                    near(overlay.sy, RT.frameScale * note.s * VP.DS, label .. "overlay同note纵向scale")
                    local renderedX = overlay.tx + overlay.x * overlay.sx
                    local renderedY = overlay.ty + overlay.y * overlay.sy
                    near(renderedX, cursor.x / RT.dpr, label .. "图标绘制位置与物理鼠标/DPR一致x")
                    near(renderedY, cursor.y / RT.dpr, label .. "图标绘制位置与物理鼠标/DPR一致y")
                    check(index("artifact.overlay") > index("church.draw")
                        and index("artifact.overlay") > index("character.draw")
                        and index("artifact.overlay") > index("equipment.overlay")
                        and index("artifact.overlay") > index("keyboard.draw"), label .. "神器图标在业务末层")
                    check(index("artifact.overlay") < index("ce.draw") and index("ce.draw") < index("frame.end"),
                        label .. "保留最高调试覆盖和frame结束顺序")
                    if triMode then check(index("artifact.overlay") > index("tri.hud"), label .. "拖拽图标高于tri HUD") end
                    up("left", 300, 1450)
                    check(count("church.tap") == 0 and not state.dragging, label .. "拖拽结束无业务tap")
                    clear(); HandleNanoVGRenderHorizon()
                    check(count("artifact.overlay") == 0, label .. "结束后不残留拖拽图标")
                end
            end
        end

        -- B：触摸主/副指隔离；故意把真实鼠标留右栏，必须使用事件坐标。
        for _, triMode in ipairs({ false, true }) do
            for _, dprValue in ipairs({ 1, 2, 3 }) do
                fixture(triMode, dprValue, true)
                position("right", 700, 900)
                local px, py = touch(41, "left", 140, 1300, HandleTouchBeginHorizon)
                local ex, ey = fromLeft(px, py)
                check(count("artifact.down") == 1, "touch主指捕获一次")
                near(last("artifact.down").x, ex, "touch事件坐标覆盖鼠标x")
                near(last("artifact.down").y, ey, "touch事件坐标覆盖鼠标y")
                touch(42, "right", 600, 900, HandleTouchBeginHorizon)
                touch(42, "right", 800, 900, HandleTouchMoveHorizon)
                touch(42, "right", 800, 900, HandleTouchEndHorizon)
                check(count("artifact.down") == 1 and count("artifact.move") == 0
                    and count("artifact.up") == 0 and state.pointer, "副指不得改写或结束主指")
                px, py = touch(41, "left", 140, 1300, HandleTouchEndHorizon)
                ex, ey = fromLeft(px, py)
                check(count("artifact.up") == 1 and count("church.tap") == 1, "主指正常tap一次")
                near(last("church.tap").x, ex, "touch松手落点x")
                near(last("church.tap").y, ey, "touch松手落点y")
                noForeignTap("touch隔离")
                clear(); state.arm = true
                touch(43, "left", 140, 1300, HandleTouchBeginHorizon)
                touch(43, "left", 400, 1450, HandleTouchMoveHorizon)
                touch(44, "left", 500, 1450, HandleTouchBeginHorizon)
                touch(43, "right", 140, 1300, HandleTouchEndHorizon)
                touch(44, "right", 140, 1300, HandleTouchEndHorizon)
                check(count("artifact.down") == 1 and count("artifact.move") == 1
                    and count("artifact.up") == 1 and count("church.tap") == 0,
                    "touch跨栏只结算主指，无副指结束穿透")
                check(not state.pointer and not state.dragging, "touch跨栏清拖拽")
                noForeignTap("touch跨栏")
            end
        end

        -- C：按压后布局/分辨率/DPR/frame变化必须取消，不产生旧坐标落点。
        local mutations = {
            { name = "note.ox", change = function() VP.getNote("left").ox = VP.getNote("left").ox + 7 end },
            { name = "note.oy", change = function() VP.getNote("left").oy = VP.getNote("left").oy + 9 end },
            { name = "note.s", change = function() VP.getNote("left").s = VP.getNote("left").s * 0.9 end },
            { name = "note.scaleX", change = function() VP.getNote("left").scaleX = 0.52 end },
            { name = "width", change = function() RT.logicalW = 2240 end },
            { name = "height", change = function() RT.logicalH = 1260 end },
            { name = "DPR", change = function() RT.dpr = 3 end },
            { name = "frameScale", change = function() RT.frameScale = 0.7 end },
            { name = "frameOx", change = function() RT.frameOx = 71 end },
            { name = "frameOy", change = function() RT.frameOy = 23 end },
        }
        for _, triMode in ipairs({ false, true }) do
            for _, mutation in ipairs(mutations) do
                fixture(triMode, 2, true); state.arm = true
                down("left", 140, 1300); move("left", 400, 1450)
                clear(); mutation.change()
                HandleMouseMoveHorizon("MouseMove", {})
                check(count("artifact.cancel") == 1 and count("detail.close") == 1
                    and not state.pointer and not state.dragging, mutation.name .. "变化取消手势及关闭详情")
                up("right", 140, 1300)
                check(count("artifact.up") == 0 and count("church.tap") == 0,
                    mutation.name .. "已取消的Up不结算/不tap")
                noForeignTap(mutation.name)
                clear(); HandleNanoVGRenderHorizon()
                check(count("artifact.overlay") == 0, mutation.name .. "取消后无图标")
            end
        end
        -- 不经move直接Up也必须检查快照；真实render切换布局取消drawing路径。
        fixture(false, 2, true); down("left", 140, 1300); clear()
        RT.frameOx = RT.frameOx + 8; up("left", 140, 1300)
        check(count("artifact.cancel") == 1 and count("artifact.up") == 0 and count("church.tap") == 0,
            "直接Up遇frame变化也取消")
        fixture(false, 2, true); state.arm = true
        down("left", 140, 1300); move("left", 400, 1450); clear()
        state.tri = true; HandleNanoVGRenderHorizon()
        check(count("artifact.cancel") == 1 and count("artifact.overlay") == 0,
            "普通切三行真实render更新note时取消拖拽")
        up("right", 140, 1300)
        check(count("church.tap") == 0, "布局取消后Up不透传")

        -- D：模态/覆盖页在手势中出现，真实draw不得把神器图标盖到模态之上。
        for _, triMode in ipairs({ false, true }) do
            for _, gate in ipairs({ "reward", "player", "level", "offline", "notice", "sweep", "damage", "stage",
                "tutorial", "title", "start", "letter", "intro", "scenario", "task", "backpack" }) do
                fixture(triMode, 2, true); state.arm = true
                down("left", 140, 1300); move("left", 400, 1450)
                clear(); state.gates[gate] = true
                HandleNanoVGRenderHorizon()
                check(count("artifact.cancel") == 1 and count("artifact.overlay") == 0
                    and not state.pointer and not state.dragging, gate .. "中途覆盖draw取消神器")
                up("left", 400, 1450)
                check(count("artifact.up") == 0 and count("church.tap") == 0, gate .. "取消后不结算旧神器")
                noForeignTap(gate .. "覆盖")
                state.gates[gate] = false
                -- 高层Up早退后，discarded由随后真实Up消费，不伪造新按压。
                up("left", 400, 1450)
                clear(); down("left", 140, 1300); up("left", 140, 1300)
                check(count("church.tap") == 1, gate .. "覆盖关闭后下一次正常tap恢复")
            end
        end
        -- E：模态在触摸主指手势中出现，结束后不能遗留activeTouchId锁住下一指。
        for _, triMode in ipairs({ false, true }) do
            for _, gate in ipairs({ "reward", "player", "level", "offline", "notice", "sweep", "damage", "stage" }) do
                fixture(triMode, 2, true); state.arm = true
                local label = gate .. " tri=" .. tostring(triMode)
                touch(51, "left", 140, 1300, HandleTouchBeginHorizon)
                touch(51, "left", 400, 1450, HandleTouchMoveHorizon)
                clear(); state.gates[gate] = true
                HandleNanoVGRenderHorizon()
                check(count("artifact.cancel") == 1 and count("artifact.overlay") == 0,
                    label .. "触摸中出现模态取消旧神器")
                touch(51, "left", 400, 1450, HandleTouchEndHorizon)
                check(count("artifact.up") == 0 and count("church.tap") == 0,
                    label .. "触摸模态取消不得结算旧神器")
                state.gates[gate] = false
                clear(); state.arm = false
                touch(52, "left", 140, 1300, HandleTouchBeginHorizon)
                touch(52, "left", 140, 1300, HandleTouchEndHorizon)
                check(count("artifact.down") == 1 and count("artifact.up") == 1 and count("church.tap") == 1,
                    label .. "触摸模态关闭后下一主指恢复，不能残留activeTouchId")
                noForeignTap(label .. "触摸恢复")
            end
        end
        -- F：left返回条与神器捕获重叠时，真实seam路由优先，不被神器down/up吃掉。
        fixture(true, 2, true)
        -- 返回条朝left内收2宿主px；1079设计x位于left内部且命中条左缘。
        down("left", 1079, 2400 * mods["core.DrawUtil"].SEAMBAR_ARROW_Y)
        check(count("artifact.down") == 0 and not state.pointer,
            "left seam按下不得捕获神器手势")
        up("left", 1079, 2400 * mods["core.DrawUtil"].SEAMBAR_ARROW_Y)
        check(count("church.close") == 1 and not state.church,
            "left seam返回真实调用Church.close一次")
        check(count("artifact.up") == 0 and count("church.tap") == 0,
            "left seam释放不结算神器或误派Church.tap")

        -- G：低缩放空白移动20设计px，虽不足15宿主px，仍不得被识别为tap。
        -- 分别覆盖直接Up的位移检查，以及Move后回原点的moved记忆；不让spy起拖兜底。
        for _, triMode in ipairs({ false, true }) do
            for _, withMove in ipairs({ false, true }) do
                fixture(triMode, 2, true)
                RT.logicalW, RT.logicalH, RT.windowW, RT.windowH = 960, 540, 960, 540
                HandleNanoVGRenderHorizon(); clear()
                local label = "低缩放 tri=" .. tostring(triMode) .. " move=" .. tostring(withMove)
                local px0, py0 = screen("left", 140, 1300)
                local px1, py1 = screen("left", 160, 1300)
                local hostDistance = (math.abs(px1 - px0) + math.abs(py1 - py0)) / RT.dpr / RT.frameScale
                check(hostDistance > 0 and hostDistance < 15, label .. "反例确实不足15宿主px")
                near((px1 - px0) / RT.dpr / RT.frameScale
                    / (VP.getNote("left").scaleX or VP.getNote("left").s * VP.DS),
                    20, label .. "反例确实移动20设计px")
                down("left", 140, 1300)
                if withMove then
                    move("left", 160, 1300)
                    up("left", 140, 1300)
                else
                    up("left", 160, 1300)
                end
                check(count("artifact.down") == 1 and count("artifact.up") == 1
                    and count("artifact.move") == (withMove and 1 or 0), label .. "真实神器手势正常结算")
                check(not state.arm and not state.dragging and not state.pointer,
                    label .. "空白移动未起拖且释放清按压")
                check(count("church.tap") == 0, label .. "设计位移阈值阻止空白滚动变tap")
            end
        end
        print("[artifact_horizon_gesture_test] real modules exercised; layout/DPR/frame/touch/hover/draw/seam/low-scale cases complete")
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
        print("[artifact_horizon_gesture_test] ALL PASS: " .. assertions .. " assertions")
    else
        print("[artifact_horizon_gesture_test] FAIL after " .. assertions .. " assertions: " .. tostring(err))
        log:Write(LOG_ERROR, "[artifact_horizon_gesture_test] FAIL after " .. assertions .. " assertions: " .. tostring(err))
    end
    engine:Exit()
end
