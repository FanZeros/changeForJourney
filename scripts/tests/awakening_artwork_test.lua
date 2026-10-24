-- 真实Artwork/Panel/Horizon输入与Stop回归；CG用项目真资源，其它页面/存档只用内存spy。
-- Runtime: tests/awakening_artwork_test.lua -tapcode_dir=/workspace/game3 -tool_mode
-- 显式像素验收分支：不加载游戏boot/存档，不安装spy，Runtime截图完成后自行退出。
local function startArtworkScreenshot()
    local Surface = require("ui.widget.DesignWidgetSurface")
    local Artwork = require("ui.character.hero.AwakeningArtwork")
    local vg = nvgCreate(1)
    assert(vg, "截图NanoVG上下文创建失败")
    -- 与Standalone.Start同名同资源；Surface.init只注册UI私有上下文，不能给宿主提供sans。
    local font = nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf")
    if font < 0 then font = nvgCreateFont(vg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf") end
    assert(font >= 0, "截图宿主sans字体加载失败")
    local cg = nvgCreateImage(vg, "image/角色CG/CG_H1.png", 0)
    assert(cg and cg >= 0, "截图真实CG加载失败")
    local width, height = nvgImageSize(vg, cg)
    Surface.init()
    assert(Artwork.open(1, cg, width, height, function() return true end), "截图Artwork打开失败")
    local openedAt = time.elapsedTime
    local handler = function()
        local dpr = graphics:GetDPR()
        local w, h = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
        nvgBeginFrame(vg, w, h, dpr)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(12, 15, 23, 255))
        nvgFill(vg)
        Artwork.draw(vg, w, h)
        nvgEndFrame(vg)
        if time.elapsedTime - openedAt > 45 then engine:Exit() end
    end
    SubscribeToEvent(vg, "NanoVGRender", handler)
    print("[awakening_artwork_test] PIXEL MODE: real CG/UI/Artwork, waiting for Runtime screenshot")
    return { vg = vg, image = cg, handler = handler } -- 明确保活上下文到截图退出。
end

local screenshotState = nil ---@type table?
function Start()
    for _, arg in ipairs(GetArguments()) do
        if arg == "-artwork-screenshot" then
            local ok, result = pcall(startArtworkScreenshot)
            if ok then screenshotState = result else
                log:Write(LOG_ERROR, "[awakening_artwork_test] screenshot: " .. tostring(result)); engine:Exit()
            end
            return
        end
    end
    ---@type fun(name: string): any
    local nativeRequire = require
    local originalGlobals, hooks = {}, {}
    for key, value in pairs(_G) do originalGlobals[key] = value end
    local VP = nativeRequire("core.Viewport")
    local oldNotes = VP._notes
    local assertions, failures = 0, 0
    local function check(condition, label)
        assertions = assertions + 1
        if not condition then failures = failures + 1; print("[ArtworkTest] FAIL: " .. label) end
    end
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.00001 end
    local function hook(name, fn)
        if not hooks[name] then hooks[name] = { value = _G[name] } end
        _G[name] = fn
    end
    local resources = {}
    local artwork, surface = nil, nil ---@type any, any
    local ok, err = xpcall(function()
        local function noop() return false end
        ---@return any
        local function mock(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local cfg = nativeRequire("config.HeroConfig")
        local awakeningConfig = nativeRequire("config.AwakeningConfig")
        local ui = nativeRequire("urhox-libs/UI")
        local drawUtil = nativeRequire("core.DrawUtil")
        local vg = nvgCreate(1)
        assert(vg, "创建真实NanoVG上下文失败")
        resources.vg = vg
        local cgPath = "image/角色CG/CG_H1.png"
        local cg = nvgCreateImage(vg, cgPath, 0)
        assert(cg and cg >= 0, "真实仓库CG加载失败：" .. cgPath)
        resources.cg = cg
        local sourceW, sourceH = nvgImageSize(vg, cg)
        assert(sourceW > 0 and sourceH > 0, "真实CG无尺寸")
        local images, removed = {}, {}
        images[cg] = cgPath
        local nativeCreate, nativeDelete = nvgCreateImage, nvgDeleteImage
        hook("nvgCreateImage", function(ctx, path, flags)
            if path == cgPath then return cg end -- 已加载的同上下文真CG句柄，不伪造图片。
            local image = nativeCreate(ctx, path, flags)
            if image and image >= 0 then images[image] = path end
            return image
        end)
        hook("nvgDeleteImage", function(ctx, image)
            removed[image] = true
            return nativeDelete(ctx, image)
        end)
        ---@type any
        local state = { heroId = 1, awakenTab = true, full = true, gates = {}, tri = false, escape = false,
            keys = {} }
        local own = { awakening = { true, true, true }, _awk3Migrated = true, shards = 0, extraTalent = {} }
        local cursor, events = { x = 0, y = 0 }, {}
        local function record(name) events[name] = (events[name] or 0) + 1 end
        local function clearCalls() events = {} end
        local function count(name) return events[name] or 0 end
        local clock = { elapsedTime = 100 }
        time = clock
        input = { GetMousePosition = function() return cursor end,
            GetKeyPress = function(_, key) return (state.escape and key == KEY_ESCAPE) or state.keys[key] == true end,
            GetQualifierDown = function() return false end }
        ---@type any
        local RT = { vg = vg, logicalW = 1920, logicalH = 1080, windowW = 1920, windowH = 1080,
            DESIGN_W = 1080, DESIGN_H = 2400, dpr = 1, frameOx = 0, frameOy = 0, frameScale = 1,
            bootReady_ = true, preload_ = { active = false } }
        local gatePaths = {
            ["ui.hud.popup.RewardPopup"] = "reward", ["ui.hud.popup.PlayerInfoPanel"] = "player",
            ["ui.hud.popup.LevelUpPopup"] = "level", ["ui.hud.popup.OfflineRewardPanel"] = "offline",
            ["ui.hud.popup.UpdateNoticePopup"] = "notice", ["ui.battle.stage.StageSelectDialog"] = "stage",
            ["ui.battle.stage.SweepDialog"] = "sweep", ["ui.battle.popup.DamageStatsPanel"] = "damage",
            ["ui.battle.popup.TerminalConfirmDialog"] = "terminal", ["ui.dev.CEPanel"] = "ce",
            ["systems.TutorialManager"] = "tutorial", ["ui.story.gate.StartScreen"] = "start",
            ["ui.story.gate.DarkTitleScreenGate"] = "title", ["ui.story.gate.LetterIntro"] = "letter",
            ["ui.story.gate.IntroCutscene"] = "intro", ["ui.story.ScenarioDialogue"] = "scenario",
            ["ui.dungeon.DungeonBattleScene"] = "dungeon", ["ui.tower.TowerBattleScene"] = "tower",
        }
        local function page(name, gate)
            return mock({ isOpen = function() return gate and state.gates[gate] == true or false end,
                isActive = function() return gate and state.gates[gate] == true or false end,
                getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
                draw = function() record(name .. ".draw") end,
                handleInput = function() record(name .. ".tap"); return true end,
                handleTap = function() record(name .. ".tap"); return true end,
                advance = function() record(name .. ".tap"); return true end,
                claim = function() record(name .. ".claim"); return true end,
                open = function() record(name .. ".open") end,
                cycleBattleSpeed = function() record(name .. ".speed"); return false end,
                handleDragBegin = function() record(name .. ".down"); return true end,
                handleDragEnd = function() record(name .. ".up"); return false end,
                close = function() record(name .. ".close") end })
        end
        local realPaths = { ["ui.character.hero.AwakeningArtwork"] = true,
            ["ui.character.hero.AwakeningPanel"] = true, ["boot.StandaloneHorizon"] = true,
            ["boot.StandaloneHorizonInput"] = true, ["boot.StandaloneHorizonWheel"] = true,
            ["ui.dev.KeyboardShortcuts"] = true, ["boot.Standalone"] = true,
            ["boot.SeamBackGesture"] = true, ["core.DrawUtil"] = true,
            ["ui.widget.DesignWidgetSurface"] = true, ["urhox-libs/UI"] = true }
        local loaded, mods = {}, {}
        mods["boot.StandaloneRT"], mods["core.Viewport"] = RT, VP
        mods["config.HeroConfig"], mods["config.AwakeningConfig"] = cfg, awakeningConfig
        mods["config.GameConfig"] = nativeRequire("config.GameConfig")
        mods["core.DrawUtil"], mods["urhox-libs/UI"] = drawUtil, ui
        mods["core.I18n"] = { lookup = function(value) return value end }
        mods["core.DarkIcon"] = mock({ SHOWCASE = false })
        mods["ui.widget.KeywordText"] = { new = function() return mock() end }
        mods["ui.widget.HeroFrame"] = mock()
        mods["systems.ExtraTalentSystem"] = { getStageStatus = function() return "" end }
        mods["systems.ButtonFeedback"] = mock({ trigger = function(name) record(name) end })
        mods["runtime.GameAction"] = { sendAction = function() record("action"); return false end }
        mods["core.PlayerStore"] = { Get = function() return nil end }
        mods["ui.character.detail.CharacterDetail"] = mock({ getHeroId = function() return state.heroId end,
            isAwakenTab = function() return state.awakenTab end,
            isOpen = function() return true end, getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
            close = function() record("detail.close") end })
        mods["ui.character.panel.CharacterPanel"] = page("character")
        mods["ui.character.panel.CharacterPanel"].isDetailOpen = function() return true end
        mods["ui.battle.tri.BattleTriPage"] = page("tri")
        mods["ui.battle.tri.BattleTriPage"].isOpen = function() return state.tri end
        mods["ui.hud.BottomNav"] = { getSelectedIndex = function() return 3 end }
        mods["boot.OfflineRewardOverlay"] = { bind = function() return mock({
            toDesign = function(x, y) return x, y end }) end }
        mods["boot.ArtifactGesture"] = { bind = function() return mock() end }
        mods["boot.DecomposeMarqueeGesture"] = { bind = function() return mock() end }
        for path, gate in pairs(gatePaths) do mods[path] = page(gate, gate) end
        mods["ui.hud.popup.RewardPopup"].currentRowTag = function() return nil end
        mods["ui.hud.popup.RewardPopup"].currentPanel = function() return nil end
        require = function(name)
            if mods[name] then return mods[name] end
            if realPaths[name] then
                if not loaded[name] then loaded[name] = nativeRequire(name) end
                return loaded[name]
            end
            if name:match("^urhox%-libs/") then return nativeRequire(name) end
            mods[name] = page(name)
            return mods[name]
        end
        artwork = require("ui.character.hero.AwakeningArtwork")
        local panel = require("ui.character.hero.AwakeningPanel")
        panel.setOwnedDataGetter(function(id) return id == 1 and own or nil end)
        panel.initImages(vg)
        local shortcuts = require("ui.dev.KeyboardShortcuts")
        surface = require("ui.widget.DesignWidgetSurface")
        surface.init() -- UI.Init内部会prime独立上下文，必须在宿主绘图探针装入前完成。
        VP._notes = {}
        require("boot.StandaloneHorizon")

        -- NanoVG仅记录底层绘图，UI.Panel/Label仍用真实实现与真实Yoga节点。
        local transform = { tx = 0, ty = 0, sx = 1, sy = 1, clip = nil, stack = {} }
        local paints, chromeRoots = {}, {}
        local function rect(x, y, w, h)
            return { x = transform.tx + x * transform.sx, y = transform.ty + y * transform.sy,
                w = w * transform.sx, h = h * transform.sy }
        end
        hook("nvgSave", function()
            transform.stack[#transform.stack + 1] = { tx = transform.tx, ty = transform.ty,
                sx = transform.sx, sy = transform.sy, clip = transform.clip }
        end)
        hook("nvgRestore", function()
            local previous = assert(table.remove(transform.stack), "NanoVG栈不配对")
            transform.tx, transform.ty, transform.sx, transform.sy, transform.clip =
                previous.tx, previous.ty, previous.sx, previous.sy, previous.clip
        end)
        hook("nvgTranslate", function(_, x, y)
            transform.tx, transform.ty = transform.tx + x * transform.sx, transform.ty + y * transform.sy
        end)
        hook("nvgScale", function(_, x, y) transform.sx, transform.sy = transform.sx * x, transform.sy * y end)
        hook("nvgResetTransform", function() transform.tx, transform.ty, transform.sx, transform.sy = 0, 0, 1, 1 end)
        hook("nvgResetScissor", function() transform.clip = nil end)
        hook("nvgScissor", function(_, x, y, w, h) transform.clip = rect(x, y, w, h) end)
        hook("nvgIntersectScissor", function(_, x, y, w, h) transform.clip = rect(x, y, w, h) end)
        hook("nvgBeginFrame", function()
            transform.tx, transform.ty, transform.sx, transform.sy, transform.clip = 0, 0, 1, 1, nil
            transform.stack, paints = {}, {}
        end)
        hook("nvgEndFrame", function() check(#transform.stack == 0, "宿主绘制恢复全部NanoVG栈") end)
        hook("nvgImagePattern", function(_, x, y, w, h, angle, image)
            local bound = rect(x, y, w, h)
            bound.image, bound.clip = image, transform.clip
            paints[#paints + 1] = bound
            return {}
        end)
        for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgFillColor", "nvgFill", "nvgFillPaint",
            "nvgGlobalAlpha", "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgText", "nvgMoveTo",
            "nvgLineTo", "nvgClosePath", "nvgStroke", "nvgStrokeColor", "nvgStrokeWidth" }) do hook(name, noop) end
        hook("nvgTextBounds", function(_, _, _, text) return (utf8.len(text) or 0) * 12 end)
        local nativeSubtree = ui.RenderWidgetSubtree
        resources.ui, resources.subtree = ui, nativeSubtree
        ui.RenderWidgetSubtree = function(root)
            chromeRoots[#chromeRoots + 1] = root -- 只截GPU渲染边界，保留真实控件/布局/生命周期。
        end
        local function open()
            state.heroId, state.awakenTab = 1, true
            own.awakening = { true, true, true }
            check(panel.openArtwork(vg, 1), "真实Panel满觉醒复用真CG打开")
        end
        local function imagePaint()
            for i = #paints, 1, -1 do if paints[i].image == cg then return paints[i] end end
            return nil
        end
        local function position(x, y)
            cursor.x = (RT.frameOx + x * RT.frameScale) * RT.dpr
            cursor.y = (RT.frameOy + y * RT.frameScale) * RT.dpr
        end
        local function mouse(method, x, y, button)
            position(x, y)
            local data = { Button = { GetInt = function() return button or MOUSEB_LEFT end } }
            _G[method]("Mouse", data)
        end
        local function down(x, y, button) mouse("HandleMouseButtonDownHorizon", x or 900, y or 500, button) end
        local function up(x, y, button) mouse("HandleMouseButtonUpHorizon", x or 900, y or 500, button) end
        local function move(x, y) mouse("HandleMouseMoveHorizon", x, y) end
        local function touch(handler, id, x, y)
            local px, py = math.floor((RT.frameOx + x * RT.frameScale) * RT.dpr + 0.5),
                math.floor((RT.frameOy + y * RT.frameScale) * RT.dpr + 0.5)
            _G[handler]("Touch", { TouchID = { GetInt = function() return id end },
                X = { GetInt = function() return px end }, Y = { GetInt = function() return py end } })
        end
        local function noTap(label)
            local total = 0
            for name, n in pairs(events) do if name:match("%.tap$") then total = total + n end end
            check(total == 0 and count("action") == 0, label .. "没有下层点击/业务动作")
        end
        local function draw() clock.elapsedTime = clock.elapsedTime + 0.05; HandleNanoVGRenderHorizon() end
        local function fresh()
            artwork.destroy()
            state.gates, state.keys, state.escape = {}, {}, false
            state.heroId, state.awakenTab = 1, true
            own.awakening = { true, true, true }
            RT.logicalW, RT.logicalH, RT.windowW, RT.windowH = 1920, 1080, 1920, 1080
            RT.dpr, RT.frameScale, RT.frameOx, RT.frameOy = 1, 1, 0, 0
            clearCalls(); open()
        end

        check(not artwork.open(1, -1, sourceW, sourceH, function() return true end)
            and not artwork.open(1, nil, sourceW, sourceH, function() return true end), "invalid句柄不打开")
        check(not artwork.open(1, cg, 0, sourceH, function() return true end)
            and not artwork.open(1, cg, sourceW, 0, function() return true end), "零尺寸不打开")
        check(not artwork.open(1, cg, sourceW, sourceH, function() return false end), "无效阶段validate不打开")
        for _, nodes in ipairs({ {}, { true }, { true, true }, { true, false, true } }) do
            own.awakening = nodes
            check(not panel.openArtwork(vg, 1), "未满觉醒门禁拒绝查看完整图")
        end
        open(); own.awakening[3] = false
        check(not artwork.isOpen(), "打开后觉醒阶段失效自动关闭")
        open(); state.heroId = 2
        check(not artwork.isOpen(), "打开后切英雄自动关闭")
        open(); state.awakenTab = false
        check(not artwork.isOpen(), "离开觉醒tab自动关闭")
        fresh()
        check(panel.handleInput(panel.VIEW_CX, panel.VIEW_CY, 1) and artwork.isOpen()
            and count("awp_view") == 1, "实际查看全图按钮使用initImages上下文且触发反馈")
        noTap("按钮打开")

        -- 真实Horizon末层：普通/三行、DPR与frame变换下图片完整contain且始终全游戏中央。
        for _, tri in ipairs({ false, true }) do
            for _, scale in ipairs({ 1, 0.8 }) do
                state.tri, RT.frameScale, RT.frameOx, RT.frameOy = tri, scale, 47, 29
                RT.dpr = 2
                draw()
                local p = assert(imagePaint(), "真实Horizon未绘制CG")
                local b = assert(artwork.getImageBounds(RT.logicalW, RT.logicalH))
                check(near(b.w / b.h, sourceW / sourceH) and b.w <= RT.logicalW - 64 + 0.00001
                    and b.h <= RT.logicalH - 220 + 0.00001, "真实源图完整contain，不cover裁切")
                check(near(p.x + p.w * 0.5, RT.frameOx + RT.logicalW * scale * 0.5)
                    and near(p.y + p.h * 0.5, RT.frameOy + RT.logicalH * scale * 0.5),
                    "末层CG中心属于整个游戏frame而非右栏viewport")
                check(p.clip and near(p.clip.x, RT.frameOx) and near(p.clip.y, RT.frameOy)
                    and near(p.clip.w, RT.logicalW * scale) and near(p.clip.h, RT.logicalH * scale),
                    "完整图scissor为全游戏窗口，不残留右栏clip")
            end
        end
        state.tri = false
        fresh(); down(); up(); check(not artwork.isOpen() and not artwork.hasPress(), "鼠标点击关闭全图")
        noTap("鼠标关闭")
        fresh(); down(); move(930, 500); move(900, 500); up()
        check(artwork.isOpen() and not artwork.hasPress(), "移远回原点永久取消tap，不误关闭")
        noTap("拖动取消")
        fresh(); down(); up(915, 500)
        check(artwork.isOpen(), "直接Up阈值15边界不当点击")
        fresh(); down(nil, nil, MOUSEB_RIGHT); up(nil, nil, MOUSEB_RIGHT)
        check(artwork.isOpen() and not artwork.hasPress(), "副鼠键吞掉但不建立主键press/关闭")
        down(); up(nil, nil, MOUSEB_RIGHT)
        check(artwork.hasPress() and artwork.isOpen(), "副鼠键松手不结束主键press")
        up(); check(not artwork.isOpen(), "主键仍可正常关闭")
        fresh(); artwork.handleDown(900, 500, MOUSEB_LEFT, "mouse", RT)
        artwork.handleUp(900, 500, MOUSEB_LEFT, 77, RT)
        check(artwork.hasPress() and artwork.isOpen(), "异source松手不能结束原press")
        artwork.handleUp(900, 500, MOUSEB_LEFT, "mouse", RT)
        check(not artwork.isOpen(), "原source释放一次")

        for _, key in ipairs({ "logicalW", "logicalH", "dpr", "frameScale", "frameOx", "frameOy" }) do
            fresh(); down()
            local old = RT[key]
            RT[key] = old + (key == "frameScale" and 0.1 or 7)
            draw() -- ABA必须在真实渲染observe经过B，恢复A也不得复活press。
            RT[key] = old
            draw(); up()
            check(artwork.isOpen() and not artwork.hasPress(), key .. " ABA观测永久取消旧tap")
            noTap(key .. " ABA")
        end
        fresh(); down(); artwork.close(); open(); up()
        check(artwork.isOpen() and not artwork.hasPress(), "close/reopen旧鼠标松手被吞，不关闭新图")
        noTap("close/reopen")
        fresh(); down(); state.escape = true; shortcuts.update(); state.escape = false
        check(not artwork.isOpen() and count("detail.close") == 0, "真实Esc仅关闭全图不关闭底层角色页")
        up(); noTap("Esc旧松手")

        -- 真实键盘guard：图被上层模态覆盖时Space/Return保留原confirm，不操作底层图或角色页。
        for _, gate in ipairs({ "scenario", "letter", "reward", "offline", "level" }) do
            for _, key in ipairs({ KEY_SPACE, KEY_RETURN }) do
                fresh(); state.gates[gate] = true; clearCalls()
                state.keys[key] = true; shortcuts.update(); state.keys = {}
                local expected = gate .. (gate == "offline" and ".claim" or ".tap")
                local total = 0
                for _, n in pairs(events) do total = total + n end
                check(count(expected) == 1 and total == 1, gate .. "上层确认键仍只调用原模态一次")
                check(artwork.isOpen() and count("detail.close") == 0, gate .. "确认不关闭底层影画/角色页")
            end
        end
        for _, key in ipairs({ KEY_SPACE, KEY_RETURN, KEY_F, KEY_I, KEY_B, KEY_6 }) do
            fresh(); clearCalls(); state.keys[key] = true; shortcuts.update(); state.keys = {}
            check(next(events) == nil and artwork.isOpen(), "无上层影画期间确认无动作且其它快捷键吞掉")
        end

        -- Touch分支真实接线，鼠标故意留他处；主指独占，副指不可改写或穿透。
        fresh(); position(1700, 900)
        touch("HandleTouchBeginHorizon", 11, 700, 450)
        touch("HandleTouchBeginHorizon", 12, 1200, 700)
        touch("HandleTouchMoveHorizon", 12, 1500, 850)
        touch("HandleTouchEndHorizon", 12, 1500, 850)
        check(artwork.hasPress() and artwork.isOpen(), "副指不改写/结束主指")
        up(700, 450)
        check(artwork.hasPress() and artwork.isOpen(), "mouse松手不能结束touch主press")
        touch("HandleTouchEndHorizon", 11, 700, 450)
        check(not artwork.isOpen() and not artwork.hasPress(), "主指事件坐标正常关闭")
        touch("HandleTouchEndHorizon", 12, 1500, 850); noTap("副指晚松手")
        fresh(); touch("HandleTouchBeginHorizon", 21, 700, 450)
        artwork.close(); open()
        touch("HandleTouchEndHorizon", 21, 700, 450)
        check(artwork.isOpen() and not artwork.hasPress(), "touch close/reopen旧松手不关闭新图")
        touch("HandleTouchBeginHorizon", 22, 700, 450); touch("HandleTouchEndHorizon", 22, 700, 450)
        check(not artwork.isOpen(), "旧touch结束释放所有权，下次主指可关闭")

        for _, gate in ipairs({ "reward", "player", "level", "offline", "notice", "stage", "sweep",
            "damage", "terminal", "ce", "tutorial", "start", "title", "letter", "intro", "scenario",
            "dungeon", "tower" }) do
            for _, touchMode in ipairs({ false, true }) do
                fresh()
                if touchMode then touch("HandleTouchBeginHorizon", 31, 700, 450) else down() end
                state.gates[gate] = true; draw()
                check(imagePaint() == nil, gate .. "上层覆盖不画全图")
                if touchMode then touch("HandleTouchEndHorizon", 31, 700, 450) else up() end
                check(artwork.isOpen() and not artwork.hasPress(), gate .. "覆盖中旧松手取消且吞掉")
                noTap(gate .. "覆盖中松手")
                state.gates[gate] = false; draw()
                if touchMode then
                    touch("HandleTouchBeginHorizon", 32, 700, 450)
                    touch("HandleTouchEndHorizon", 32, 700, 450)
                else down(); up() end
                check(not artwork.isOpen(), gate .. "覆盖关闭后下一真实点击恢复")
            end
        end

        -- 主指按住后副指先结束；覆盖中或主图已关，副指均不得成为无Down的上层点击。
        for _, gate in ipairs({ "notice", "title", "letter", "scenario" }) do
            fresh()
            touch("HandleTouchBeginHorizon", 41, 700, 450)
            touch("HandleTouchBeginHorizon", 42, 1200, 700)
            state.gates["level"], state.gates[gate] = true, true
            draw(); clearCalls()
            touch("HandleTouchEndHorizon", 42, 1200, 700)
            noTap(gate .. "覆盖中副指无Down松手")
            check(artwork.hasPress(), gate .. "副指结束不影响主指所有权")
            touch("HandleTouchEndHorizon", 41, 700, 450)
            state.gates = {}
        end

        fresh(); draw()
        local lastChrome = assert(chromeRoots[#chromeRoots], "缺真实UI chrome")
        local labels = lastChrome:GetChildren()
        local titleLabel, hintLabel = labels[1], labels[2]
        check(lastChrome.node ~= nil and #labels == 2 and labels[1]:GetText():find("觉醒", 1, true)
            and labels[2]:GetText() == "点击关闭 / Esc", "真实新UI标题/提示控件已建树")
        local standalone = require("boot.Standalone")
        standalone.Stop()
        local frameCount = assertions
        surface.init() -- Stop后独立UI上下文prime不应清掉宿主NanoVG探针栈。
        check(assertions >= frameCount, "Stop后Surface可重新初始化")
        check(not artwork.isOpen() and not artwork.hasPress() and lastChrome.node == nil
            and titleLabel.node == nil and hintLabel.node == nil, "真实Stop销毁完整chrome树并清全图press")
        local w, h = nvgImageSize(vg, cg)
        check(not removed[cg] and w == sourceW and h == sourceH, "Stop未删除复用的宿主CG句柄")
        open(); draw()
        check(chromeRoots[#chromeRoots] ~= lastChrome and chromeRoots[#chromeRoots].node ~= nil,
            "Stop后重开创建新控件，不复用已释放Yoga树")
        noTap("测试全程无业务写入")
    end, debug.traceback)
    local cleanupOk, cleanupError = pcall(function()
        if artwork then artwork.destroy() end
        if surface then surface.shutdown() end
        if resources.ui then resources.ui.RenderWidgetSubtree = resources.subtree end
        if resources.vg then
            local delete = hooks.nvgDeleteImage and hooks.nvgDeleteImage.value or nvgDeleteImage
            if resources.cg then delete(resources.vg, resources.cg) end
            nvgDelete(resources.vg)
        end
    end)
    require = nativeRequire
    VP._notes = oldNotes
    local added = {}
    for key in pairs(_G) do if originalGlobals[key] == nil then added[#added + 1] = key end end
    for _, key in ipairs(added) do _G[key] = nil end
    for key, value in pairs(originalGlobals) do _G[key] = value end
    if ok and cleanupOk and failures == 0 then
        print("[awakening_artwork_test] ALL PASS: " .. assertions .. " assertions")
    else
        local message = tostring(err or cleanupError or (failures .. " failed assertions"))
        print("[awakening_artwork_test] FAIL: " .. message .. "; " .. assertions .. " assertions")
        log:Write(LOG_ERROR, "[awakening_artwork_test] " .. message)
    end
    engine:Exit()
end
