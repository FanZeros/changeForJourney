-- 真实 TM / TutorialOverlay / Viewport / Horizon 投影与输入回归；页面和存档只用内存 spy。
-- 仅捕获真实 Horizon 的 ctx，输入直接 bind；不加载玩家存档、不发 action、不创建图形资源。
-- Runtime: tests/tutorial_horizon_input_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
function Start()
    ---@type fun(name: string): any
    local nativeRequire = require
    local originals, nvgOriginals, overlayOriginals = {}, {}, {}
    local originalInput, originalTime = input, time
    local VP = nativeRequire("core.Viewport")
    local originalNotes = VP._notes
    local assertions, failures, cases = 0, 0, 0
    local function check(value, label)
        assertions = assertions + 1
        if not value then failures = failures + 1; print("[FAIL] tutorial_horizon_input_test: " .. label) end
    end
    local function runCase(label, fn)
        cases = cases + 1
        local before = failures
        local ok, err = pcall(fn)
        if not ok then check(false, label .. " exception: " .. tostring(err)) end
        if before == failures then print("[PASS] " .. label) end
    end
    local function horizonGlobal(key)
        return type(key) == "string" and (key:match("^H_") or key:match("^Handle.*Horizon$"))
    end
    for key, value in pairs(_G) do if horizonGlobal(key) then originals[key] = value end end
    local ok, err = pcall(function()
        local function noop() return false end
        ---@return any
        local function mock(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local calls, events = {}, {}
        local function record(name, x, y)
            calls[name] = (calls[name] or 0) + 1
            events[#events + 1] = { name = name, x = x, y = y }
        end
        local function n(name) return calls[name] or 0 end
        local function clearCalls() calls, events = {}, {} end
        local state = { tri = false, reward = false, detail = false, missing = false, owner = "character",
            seamSmith = false, warehouse = false, pinned = false, characterOpen = false,
            characterHeroId = 0, characterTab = "attr", targetHeroId = 1, allowCharacterOpen = true,
            story = false }
        local recoveryCalls = {}
        local function preparePage(vg, store, highlight, newHeroId, initial, equipmentHeroId)
            recoveryCalls[#recoveryCalls + 1] = { vg = vg, store = store, highlight = highlight,
                newHeroId = newHeroId, initial = initial, equipmentHeroId = equipmentHeroId }
            return false
        end
        local cursor = { x = 0, y = 0 }
        local clock = { elapsedTime = 100 }
        input = { GetMousePosition = function() return cursor end }
        time = clock
        ---@type any
        local RT = { logicalW = 1920, logicalH = 1080, windowW = 1920, windowH = 1080,
            DESIGN_W = 1080, DESIGN_H = 2400, dpr = 1, frameOx = 0, frameOy = 0,
            frameScale = 1, vg = {}, bootReady_ = true, preload_ = { active = false } }
        local data = { session = { claimedScenarios = {} }, heroes = { roster = {} },
            equipment = { equipped = {} }, battle = { maxStageId = 102 } }
        local Store = { Get = function(key) return data[key] end }
        local methods = { "handleInput", "handleClick", "handleDragBegin", "handleDragMove",
            "handleDragEnd", "handleEquipmentSlotTap", "handleNavigationTap", "close" }
        ---@return any
        local function page(name, fields)
            local base = {}
            for _, method in ipairs(methods) do
                base[method] = function(x, y) record(name .. "." .. method, x, y); return false end
            end
            for key, value in pairs(fields or {}) do base[key] = value end
            return mock(base)
        end
        ---@type any
        local tutorialManager = nil
        local mods = {
            ["boot.StandaloneRT"] = RT, ["core.Viewport"] = VP,
            -- 本套只验证投影/输入；页面恢复另用真实Recovery专项，避免无状态spy反复报changed。
            ["ui.tutorial.TutorialPageRecovery"] = { isBlocked = function() return false end,
                prepare = preparePage },
            ["boot.OfflineRewardOverlay"] = { bind = function() return mock() end },
            ["ui.hud.BottomNav"] = mock({ getSelectedIndex = function() return 3 end }),
            ["ui.story.ScenarioDialogue"] = mock({ isActive = function() return state.story end }),
            ["ui.battle.popup.TerminalConfirmDialog"] = page("terminalConfirm"),
            ["ui.tavern.TargetRecruitPanel"] = page("targetRecruit"),
            ["ui.tavern.TavernPopups"] = page("tavernPopups"),
            ["ui.battle.tri.BattleTriPage"] = page("tri", { isOpen = function() return state.tri end }),
            ["ui.backpack.BackpackPanel"] = page("backpack", {
                isOpen = function() return state.warehouse end,
                isLeftMode = function() return true end,
                getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
                peekEquipAt = function(x, y)
                    if state.warehouse and math.abs(x - 140) <= 60 and math.abs(y - 1060) <= 60 then
                        return { seq = 7, slot = "weapon" }
                    end
                    return nil
                end,
                handleRightClick = function(x, y)
                    record("backpack.handleRightClick", x, y)
                    return true
                end,
                handleInput = function(x, y)
                    record("backpack.handleInput", x, y)
                    state.detail, state.pinned, state.owner = true, true, "backpack"
                    return true
                end,
            }),
            ["ui.blacksmith.BlacksmithPage"] = page("smith", {
                isOpen = function() return state.seamSmith end,
                getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
            }),
            ["ui.character.detail.CharacterDetail"] = page("characterDetail", {
                isOpen = function() return state.characterOpen end,
                getHeroId = function() return state.characterHeroId end,
                isEquipTab = function() return state.characterTab == "equip" end,
                open = function(heroId, tab)
                    record("characterDetail.open", heroId, tab)
                    if not state.allowCharacterOpen then return false end
                    state.characterOpen, state.characterHeroId = true, heroId
                    state.characterTab = tab or tutorialManager.getPreferredCharacterTab() or "attr"
                    return true
                end,
                close = function() state.characterOpen = false; record("characterDetail.close") end,
                getSeamAnim = function() return 1, 0, 0.45, 0.38 end,
            }),
            ["ui.character.equip.EquipmentDetail"] = page("detail", {
                isOpen = function() return state.detail end,
                isCompactCorner = function() return state.detail end,
                isPinned = function() return state.pinned end,
                getOwner = function() return state.owner end,
                containsPoint = function(x, y)
                    return state.detail and x >= 700 and x <= 1000 and y >= 1400 and y <= 1700
                end,
                close = function() state.detail = false; record("detail.close") end,
            }),
            ["ui.hud.popup.RewardPopup"] = page("reward", {
                isOpen = function() return state.reward end,
                currentPanel = function() return state.reward and "right" or nil end,
                currentRowTag = function() return nil end,
            }),
            ["core.I18n"] = { lookup = function(text) return text end },
            ["core.DarkIcon"] = mock({ SHOWCASE = false }),
            ["core.DrawUtil"] = mock({ SEAMBAR_ASPECT = 0.04, SEAMBAR_ARROW_Y = 0.469,
                seamSlideX = function() return 0 end,
                hitTest = function(x, y, cx, cy, w, h)
                    return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5
                end,
            }),
            ["runtime.GameAction"] = mock({ sendAction = function() record("action") end }),
        }
        ---@type any
        local captured = nil
        local capturing = true
        require = function(name)
            if name == "systems.TutorialManager" or name == "ui.tutorial.TutorialOverlay"
                or name == "config.TutorialConfig" or name == "config.GameConfig"
                or name == "boot.SeamBackGesture" then
                return nativeRequire(name)
            end
            if name == "boot.StandaloneHorizonInput" then
                if capturing then return { bind = function(ctx) captured = ctx end } end
                return nativeRequire(name)
            end
            if not mods[name] then mods[name] = page(name) end
            return mods[name]
        end
        local TM = nativeRequire("systems.TutorialManager")
        tutorialManager = TM
        local Overlay = nativeRequire("ui.tutorial.TutorialOverlay")
        mods["systems.TutorialManager"], mods["ui.tutorial.TutorialOverlay"] = TM, Overlay
        local projected, drawn = nil, nil ---@type any, any
        overlayOriginals.module, overlayOriginals.draw = Overlay, Overlay.draw
        Overlay.draw = function(vg, width, height, hotspot, ...)
            projected = hotspot
            drawn = overlayOriginals.draw(vg, width, height, hotspot, ...)
            return drawn
        end
        local function battleTarget()
            return RT.logicalW * 0.5 + RT.logicalH * 0.13, RT.logicalH * 0.2, 100, 80
        end
        local function openFromBattle(x, y)
            record("battle.openDetail", x, y)
            mods["ui.character.detail.CharacterDetail"].open(state.targetHeroId)
            return TM.notifyCharacterDetailOpened("battle", state.targetHeroId)
        end
        local function registerBattleTarget()
            if state.missing or TM.getCurrentHighlight() ~= "battle_hero_detail" then return end
            local x, y, w, h = battleTarget()
            TM.registerCharacterDetailHotspot("battle_hero_detail", state.targetHeroId, x, y, w, h, "screen")
        end
        mods["ui.battle.tri.BattleTriPage"].draw = registerBattleTarget
        mods["ui.battle.tri.BattleTriPage"].handleRightClick = function(x, y)
            record("tri.handleRightClick", x, y)
            return true
        end
        mods["ui.battle.tri.BattleTriPage"].handleInput = function(x, y)
            record("tri.handleInput", x, y)
            local tx, ty, w, h = battleTarget()
            if TM.getCurrentHighlight() == "battle_hero_detail"
                and math.abs(x - tx) <= w * 0.5 and math.abs(y - ty) <= h * 0.5 then
                openFromBattle(x, y)
                return true
            end
            return false
        end
        -- 普通布局只借旧BattleScene.draw注册screen来验证投影，不虚造其Horizon业务路由。
        mods["ui.battle.scene.BattleScene"] = page("battle", { draw = registerBattleTarget })
        mods["ui.character.panel.CharacterPanel"] = page("character", {
            handleRightClick = function(x, y) record("character.handleRightClick", x, y); return true end,
            isDetailOpen = function() return state.characterOpen end,
            draw = function()
                if not state.missing then
                    local key = TM.getCurrentHighlight()
                    if key == "character_slot_1" then
                        TM.registerCharacterDetailHotspot(key, state.targetHeroId, 540, 600, 160, 100, "right")
                    elseif key and key ~= "battle_hero_detail" and key ~= "town_overview"
                        and key ~= "building_church" and key ~= "building_tavern" then
                        TM.registerHotspot(key, 540, 600, 160, 100, "right")
                    end
                end
            end,
            handleInput = function(x, y)
                record("character.handleInput", x, y)
                if TM.getCurrentHighlight() == "character_slot_1"
                    and math.abs(x - 540) <= 80 and math.abs(y - 600) <= 50 then
                    mods["ui.character.detail.CharacterDetail"].open(state.targetHeroId)
                    TM.notifyCharacterDetailOpened("avatar", state.targetHeroId)
                    return true
                end
                return false
            end,
        })
        local townSourceFile = assert(cache:GetFile("ui/town/TownScene.lua"), "缺真实TownScene源码")
        local townLines = {}
        while not townSourceFile:IsEof() do townLines[#townLines + 1] = townSourceFile:ReadLine() end
        townSourceFile:Dispose()
        local townSource = table.concat(townLines, "\n")
        local townFirst = assert(townSource:find("-- 城镇总览高亮完整左栏", 1, true))
        local townLast = assert(townSource:find("-- 第7个地点", townFirst, true))
        local townEnv = { _tmActive = true, _TM = TM }
        local townRegistration, townError = load(townSource:sub(townFirst, townLast - 1),
            "@真实TownScene总览注册", "t", townEnv)
        assert(townRegistration, townError)
        local tavernFirst = assert(townSource:find("-- 酒馆\n", 1, true))
        local tavernLast = assert(townSource:find("-- 仓库（背包入口）", tavernFirst, true))
        local tavernLine = assert(townSource:match('(    if _tmActive and not tavernLocked then _TM.registerHotspot%("building_tavern"[^\n]+)'))
        local tavernEnv = { _tmActive = true, tavernLocked = false, _TM = TM }
        local tavernRegistration, tavernError = load(townSource:sub(tavernFirst, tavernLast - 1)
            .. tavernLine, "@真实TownScene酒馆注册", "t", tavernEnv)
        assert(tavernRegistration, tavernError)
        mods["ui.town.TownScene"] = page("town", { draw = function()
            if state.missing then return end
            if TM.getCurrentHighlight() == "town_overview" then
                townRegistration()
            elseif TM.getCurrentHighlight() == "building_tavern" then
                tavernRegistration()
            elseif TM.getCurrentHighlight() == "building_church" then
                TM.registerHotspot("building_church", 540, 1100, 200, 180, "left")
            end
        end })
        -- 图形函数只替换底层绘制；保留实际 Overlay.layout/draw 和 Horizon note 投影。
        for _, name in ipairs({ "nvgBeginFrame", "nvgEndFrame", "nvgSave", "nvgRestore",
            "nvgTranslate", "nvgScale", "nvgResetTransform", "nvgResetScissor", "nvgScissor",
            "nvgIntersectScissor", "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFillColor",
            "nvgFill", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgFontFace",
            "nvgFontSize", "nvgTextAlign", "nvgText", "nvgPathWinding" }) do
            nvgOriginals[name] = { value = rawget(_G, name) }; rawset(_G, name, noop)
        end
        nvgOriginals.nvgTextBounds = { value = rawget(_G, "nvgTextBounds") }
        rawset(_G, "nvgTextBounds", function(_, _, _, text) return utf8.len(text) * 10 end)
        nativeRequire("boot.StandaloneHorizon")
        check(captured ~= nil and captured.Viewport == VP, "捕获真实 Horizon ctx / Viewport")
        -- 只读抽取生产投影函数，覆盖非默认scaleX；不复制它的公式作为待测实现。
        local projectionFile = assert(cache:GetFile("boot/StandaloneHorizon.lua"), "缺真实Horizon源码")
        local projectionLines = {}
        while not projectionFile:IsEof() do projectionLines[#projectionLines + 1] = projectionFile:ReadLine() end
        projectionFile:Dispose()
        local projectionSource = table.concat(projectionLines, "\n")
        local first = assert(projectionSource:find("local function HorizonDrawTutorialOverlay()", 1, true))
        local last = assert(projectionSource:find("\n--- [弹窗聚焦]", first, true))
        local projectionEnv = setmetatable({ TutorialManager = TM, Viewport = VP,
            BottomNav = mods["ui.hud.BottomNav"],
            ScenarioDialogue = mods["ui.story.ScenarioDialogue"], LetterIntro = mock(), IntroCutscene = mock(),
            DarkTitleScreen = mock(), DungeonBattleScene = mock(), TowerBattleScene = mock(),
            logicalW = function() return RT.logicalW end, logicalH = function() return RT.logicalH end,
            DESIGN_W = function() return RT.DESIGN_W end, DESIGN_H = function() return RT.DESIGN_H end,
            vg = function() return RT.vg end, applyFrame = noop }, { __index = _G })
        local projectionChunk, projectionError = load(projectionSource:sub(first, last - 1)
            .. "\nreturn HorizonDrawTutorialOverlay", "@真实Horizon教程投影", "t", projectionEnv)
        assert(projectionChunk, projectionError)
        local projectTutorial = projectionChunk()
        capturing = false
        local InputModule = nativeRequire("boot.StandaloneHorizonInput")
        local left = { Button = { GetInt = function() return MOUSEB_LEFT end } }
        local function invoke(name, event) rawget(_G, name)(name, event or left) end
        local function screenPosition(x, y)
            cursor.x = (RT.frameOx + x * RT.frameScale) * RT.dpr
            cursor.y = (RT.frameOy + y * RT.frameScale) * RT.dpr
        end
        local function panelPosition(panel, x, y)
            local note, p = VP.getNote(panel), VP.PANELS[panel]
            return note.ox + p.bx * note.s + x * (note.scaleX or note.s * VP.DS),
                note.oy + p.by * note.s + y * note.s * VP.DS
        end
        local function click(x, y)
            screenPosition(x, y)
            invoke("HandleMouseButtonDownHorizon")
            clock.elapsedTime = clock.elapsedTime + 0.2
            invoke("HandleMouseButtonUpHorizon")
        end
        local function fixture(tri, transformed, dpr, groupId)
            local group = groupId or 2 -- 原右栏输入矩阵保留，首步改走组2头像真实成功回执。
            RT.logicalW, RT.logicalH, RT.windowW, RT.windowH = 1920, 1080, 1920, 1080
            state.tri, state.reward, state.detail, state.missing, state.owner = tri, false, false, false, "character"
            state.seamSmith, state.warehouse, state.pinned = false, false, false
            state.characterOpen, state.characterHeroId, state.characterTab = false, 0, "attr"
            state.targetHeroId, state.allowCharacterOpen, state.story = 1, true, false
            recoveryCalls = {}
            mods["ui.tutorial.TutorialPageRecovery"].prepare = preparePage
            RT.dpr, RT.frameScale = dpr, transformed and 0.8 or 1
            RT.frameOx, RT.frameOy = transformed and 37 or 0, transformed and 23 or 0
            VP._notes = {}
            data.session = { claimedScenarios = {} }
            TM.init(RT.vg, Store, function(progress) data.session.tutorialProgress = progress; record("persist") end)
            TM.update(0)
            TM.onScenarioClaimed(group == 1 and 5 or 8)
            TM.update(0.3) -- 情景回执后的安静窗口先启动教程
            TM.update(1.2)
            InputModule.bind(captured)
            H_SEAM_BACK = true
            invoke("HandleNanoVGRenderHorizon", {})
            clearCalls()
        end
        local function noBusiness(label)
            check(n("detail.handleDragBegin") == 0 and n("detail.handleInput") == 0
                and n("detail.close") == 0, label .. " 不按压/点击/关闭装备浮层")
            check(n("character.handleInput") == 0 and n("character.handleDragBegin") == 0
                and n("tri.handleInput") == 0 and n("tri.handleDragBegin") == 0
                and n("characterDetail.close") == 0 and n("smith.close") == 0 and n("action") == 0, label .. " 不派发下层业务/返回/action")
        end
        for _, tri in ipairs({ false, true }) do
            for _, transformed in ipairs({ false, true }) do
                for _, dpr in ipairs({ 1, 2, 3 }) do
                    local label = (tri and "tri" or "ordinary") .. " frame=" .. tostring(transformed) .. " DPR=" .. dpr
                    runCase(label .. " 目标单次推进", function()
                        fixture(tri, transformed, dpr)
                        local x, y = panelPosition("right", 540, 600)
                        local hs = TM.getCurrentHotspot()
                        check(TM.getCurrentGroup() == 2 and TM.getCurrentHighlight() == "character_slot_1"
                            and hs and hs.panel == "right" and hs.heroId == state.targetHeroId,
                            "原right矩阵采用组2携hero的avatar入口")
                        check(TM.canPointerStart(x, y), "真实 note 投影目标 down 放行")
                        check(not TM.canPointerStart(x + 45, y), "按钮外不以光环放行")
                        local before = TM.getProgress().step
                        screenPosition(x, y)
                        invoke("HandleMouseButtonDownHorizon")
                        check(TM.getProgress().step == before, "down 不推进")
                        clock.elapsedTime = clock.elapsedTime + 0.2
                        invoke("HandleMouseButtonUpHorizon")
                        check(TM.getProgress().step == before + 1 and n("persist") == 1, "up 仅推进/持久化一次")
                        check(n("character.handleInput") == 1, "目标点击传给所属右栏一次")
                        check(n("characterDetail.open") == 1 and state.characterOpen
                            and state.characterHeroId == state.targetHeroId and state.characterTab == "equip"
                            and TM.getEquipmentHeroId() == state.targetHeroId
                            and TM.getCurrentHighlight() == "equip_btn_auto",
                            "avatar业务真实打开同hero配装详情后才接受并进入一键装备")
                        TM.notifyEvent("character_detail_opened")
                        check(TM.getProgress().step == before + 1 and n("persist") == 1,
                            "普通详情事件不推进后续步骤或重复保存")
                        invoke("HandleMouseButtonUpHorizon")
                        check(TM.getProgress().step == before + 1 and n("character.handleInput") == 1, "重复 up 不二次推进/派发")
                    end)
                    runCase(label .. " 非目标浮层与返回条", function()
                        fixture(tri, transformed, dpr)
                        state.detail = true
                        local x, y = panelPosition("right", 850, 1550)
                        check(captured.equipOverlayDesign(x, y) ~= nil, "点确实命中真实浮层逆变换")
                        local before = TM.getProgress().step
                        click(x, y)
                        noBusiness("非目标浮层")
                        check(TM.getProgress().step == before and state.detail, "不推进且浮层保持")
                        state.seamSmith = not tri -- 普通横屏返回条由锻炉提供；tri 使用右角色详情条。
                        state.characterOpen = tri -- 保留原tri详情返回条的真实开页资格，不靠永久isOpen=true。
                        local seamX = nil ---@type number?
                        local seamY = RT.logicalH * 0.469
                        for sx = 0, RT.logicalW do
                            if captured.seamHitAt(sx, seamY) then seamX = sx; break end
                        end
                        check(seamX == nil, "教程期间下层返回条不绘制也不命中")
                        click(RT.logicalW * 0.5, seamY)
                        noBusiness("非目标返回条")
                        check(TM.getProgress().step == before and state.detail, "返回条 down/up 不推进或dismiss")
                    end)
                    runCase(label .. " 缺热点 skip 首击优先", function()
                        fixture(tri, transformed, dpr)
                        state.detail, state.missing = true, true
                        invoke("HandleNanoVGRenderHorizon", {})
                        clearCalls()
                        check(TM.getCurrentHotspot() == nil, "真实 Horizon 本帧缺热点")
                        local layout = Overlay.layout(RT.logicalW, RT.logicalH, nil)
                        check(not TM.canPointerStart(layout.skip.cx, layout.skip.cy), "skip down 先屏蔽浮层dismiss")
                        click(layout.skip.cx, layout.skip.cy)
                        check(TM.getProgress().completed["2"] == true and n("persist") == 1, "缺热点 skip 完成并保存一次")
                        noBusiness("skip")
                        check(state.detail, "skip 首击不关闭浮层")
                        TM.update(0.3)
                        check(TM.getCurrentGroup() == nil, "skip 淡出后释放教程")
                    end)
                    runCase(label .. " 奖励让位 / bag owner", function()
                        fixture(tri, transformed, dpr)
                        state.reward = true
                        check(TM.canPointerStart(0, 0) and not TM.isInputActive(), "奖励打开教程输入让位")
                        local x, y = panelPosition("right", 850, 1550)
                        local before = TM.getProgress().step
                        click(x, y)
                        check(n("reward.handleInput") == 1 and n("reward.handleDragBegin") == 1, "非教程目标奖励收到 down/up tap")
                        check(TM.getProgress().step == before and n("character.handleInput") == 0, "奖励不推进/穿透教程")
                        state.reward, state.detail, state.owner = false, true, "bag"
                        local rx, ry = panelPosition("right", 850, 1550)
                        local lx, ly = panelPosition("left", 850, 1550)
                        local dx, dy, ed = captured.equipOverlayDesign(rx, ry)
                        check(dx and math.abs(dx - 850) < 0.00001 and math.abs(dy - 1550) < 0.00001
                            and ed == mods["ui.character.equip.EquipmentDetail"], "真实 bag owner 挂 right 且设计坐标正确")
                        check(captured.equipOverlayDesign(lx, ly) == nil, "bag owner 不挂 left")
                    end)
                end
            end
        end
        for _, transformed in ipairs({ false, true }) do
            for _, ratio in ipairs({ 1, 2, 3 }) do
                for _, size in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 844, 390 } }) do
                    runCase("battle screen tri frame=" .. tostring(transformed) .. " DPR=" .. ratio
                        .. " " .. size[1] .. "x" .. size[2], function()
                        fixture(true, transformed, ratio, 1)
                        RT.logicalW, RT.logicalH, RT.windowW, RT.windowH = size[1], size[2], size[1], size[2]
                        invoke("HandleNanoVGRenderHorizon", {})
                        clearCalls()
                        local x, y, w, h = battleTarget()
                        local hs = TM.getCurrentHotspot()
                        check(TM.getCurrentGroup() == 1 and TM.getCurrentHighlight() == "battle_hero_detail"
                            and hs and hs.panel == "screen" and hs.heroId == state.targetHeroId,
                            "组1真实battle目标携hero并注册screen")
                        check(projected and projected.cx == x and projected.cy == y
                            and projected.w == w and projected.h == h and projected.spotlight == nil,
                            "生产Horizon screen投影直通逻辑矩形，不重复缩放或借右栏note")
                        check(drawn and drawn.hs and math.abs(drawn.hs.cx - x) < 0.00001
                            and math.abs(drawn.hs.cy - y) < 0.00001 and math.abs(drawn.hs.w - w) < 0.00001
                            and math.abs(drawn.hs.h - h) < 0.00001,
                            "实际Overlay命中保留screen目标完整尺寸")
                        check(TM.canPointerStart(x, y) and not TM.canPointerStart(x + w * 0.5 + 1, y),
                            "screen目标边界放行，光环外扩不扩大点击")
                        local rx, ry = panelPosition("right", 540, 600)
                        local before = TM.getProgress().step
                        click(rx, ry)
                        check(TM.getProgress().step == before and TM.getEquipmentHeroId() == nil,
                            "组1右栏头像不能替代battle入口成功")
                        noBusiness("screen非目标右栏")
                        screenPosition(x, y)
                        invoke("HandleMouseButtonDownHorizon")
                        check(TM.getProgress().step == before and not state.characterOpen
                            and n("tri.handleDragBegin") == 0 and n("persist") == 0,
                            "screen down只捕获tri入口身份，不启动下层拖拽/开详情/提前推进")
                        clock.elapsedTime = clock.elapsedTime + 0.2
                        invoke("HandleMouseButtonUpHorizon")
                        check(TM.getProgress().step == before + 1 and n("persist") == 1
                            and n("tri.handleInput") == 1 and n("battle.openDetail") == 1
                            and n("characterDetail.open") == 1 and n("character.handleInput") == 0,
                            "screen up真实tri业务打开详情并以battle回执只推进保存一次")
                        check(state.characterOpen and state.characterHeroId == state.targetHeroId
                            and state.characterTab == "equip" and TM.getEquipmentHeroId() == state.targetHeroId
                            and TM.getCurrentHighlight() == "equip_slot_weapon",
                            "组1接受目标hero，后续仍真实武器槽步骤")
                        for _, event in ipairs(events) do
                            if event.name == "tri.handleInput" then
                                check(math.abs(event.x - x) < 0.00001 and math.abs(event.y - y) < 0.00001,
                                    "tri业务实际收到逆frame/DPR后的screen逻辑坐标")
                            end
                        end
                        invoke("HandleMouseButtonUpHorizon")
                        check(TM.getProgress().step == before + 1 and n("tri.handleInput") == 1
                            and n("persist") == 1, "重复screen up不二次派发/推进/保存")
                        TM.update(0)
                        local recovery = recoveryCalls[#recoveryCalls]
                        check(recovery and recovery.highlight == "equip_slot_weapon"
                            and recovery.equipmentHeroId == state.targetHeroId,
                            "真实TM将已接受hero作为Recovery.prepare第6参传给后续配装")
                    end)
                end
            end
        end
        for _, group in ipairs({ 1, 2 }) do
            runCase("详情入口成功门控 group=" .. group, function()
                fixture(true, true, 2, group)
                local source = group == 1 and "battle" or "avatar"
                local wrongSource = group == 1 and "avatar" or "battle"
                local detail = mods["ui.character.detail.CharacterDetail"]
                local x, y = battleTarget()
                if group == 2 then x, y = panelPosition("right", 540, 600) end
                local before = TM.getProgress().step
                check(TM.handleScreenClick(x, y) == false and TM.getProgress().step == before
                    and n("persist") == 0, "pointerTarget点击只透传，不伪造详情成功")
                TM.notifyEvent("character_detail_opened")
                check(TM.getProgress().step == before and TM.getEquipmentHeroId() == nil
                    and n("persist") == 0, "普通character_detail_opened事件绝不绕过入口验证")
                check(not TM.notifyCharacterDetailOpened(source, state.targetHeroId), "详情未打开不接受成功回执")
                detail.open(state.targetHeroId, "attr")
                check(not TM.notifyCharacterDetailOpened(source, state.targetHeroId), "非配装tab不接受成功回执")
                detail.open(state.targetHeroId + 1, "equip")
                check(not TM.notifyCharacterDetailOpened(source, state.targetHeroId), "详情真实hero与热点不符不接受")
                detail.open(state.targetHeroId, "equip")
                check(not TM.notifyCharacterDetailOpened(wrongSource, state.targetHeroId), "错误入口来源不接受")
                check(not TM.notifyCharacterDetailOpened(source, state.targetHeroId + 1), "错误回执hero不接受")
                check(TM.getProgress().step == before and TM.getEquipmentHeroId() == nil
                    and n("persist") == 0, "所有失败回执不锁错hero/推进/保存")
                check(TM.notifyCharacterDetailOpened(source, state.targetHeroId), "匹配来源热点及已打开配装hero后才接受")
                check(TM.getProgress().step == before + 1 and TM.getEquipmentHeroId() == state.targetHeroId
                    and n("persist") == 1, "本组成功只推进保存一次并锁定hero")
                check(not TM.notifyCharacterDetailOpened(source, state.targetHeroId), "重复已接受回执不推进后续装备步骤")
                TM.update(0)
                local recovery = recoveryCalls[#recoveryCalls]
                check(recovery and recovery.equipmentHeroId == state.targetHeroId
                    and recovery.highlight == (group == 1 and "equip_slot_weapon" or "equip_btn_auto"),
                    "两组后续Recovery收到本组实际接受hero")
            end)
        end
        runCase("avatar目标透传但开页失败不推进", function()
            fixture(true, true, 2)
            state.allowCharacterOpen = false
            local x, y = panelPosition("right", 540, 600)
            local before = TM.getProgress().step
            click(x, y)
            check(n("character.handleInput") == 1 and n("characterDetail.open") == 1
                and not state.characterOpen and TM.getProgress().step == before
                and TM.getEquipmentHeroId() == nil and n("persist") == 0,
                "fake业务确实尝试打开而失败，真实TM不把目标tap当成功")
            state.allowCharacterOpen = true
            click(x, y)
            check(TM.getProgress().step == before + 1 and n("persist") == 1
                and TM.getEquipmentHeroId() == state.targetHeroId, "真实开页恢复后新tap才接受一次成功")
        end)
        local function overlaps(a, b)
            return a and b and math.abs(a.cx - b.cx) < (a.w + b.w) * 0.5
                and math.abs(a.cy - b.cy) < (a.h + b.h) * 0.5
        end
        for _, tri in ipairs({ false, true }) do
            for _, size in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 844, 390 } }) do
                runCase("城镇酒馆入口 " .. tostring(tri) .. " " .. size[1] .. "x" .. size[2], function()
                    fixture(tri, true, 2)
                    TM.skipCurrentGroup()
                    TM.update(0.3)
                    TM.startGroup(4)
                    TM.update(1.2)
                    RT.logicalW, RT.logicalH = size[1], size[2]
                    RT.windowW, RT.windowH = size[1], size[2]
                    invoke("HandleNanoVGRenderHorizon", {})
                    check(TM.getCurrentHighlight() == "building_tavern" and projected and projected.spotlight == nil,
                        "真实宿主投影明确酒馆目标，不再制造空白继续区")
                    if not projected or not drawn then return end
                    local hotspot = TM.getCurrentHotspot()
                    check(hotspot and hotspot.panel == "left" and hotspot.cx == 832 and hotspot.cy == 1400
                        and hotspot.w == 397 and hotspot.h == 387, "真实TownScene酒馆注册精确位置尺寸")
                    local note, panel = VP.getNote("left"), VP.PANELS.left
                    local scaleX, scaleY = note.scaleX or note.s * VP.DS, note.s * VP.DS
                    local expectedLeft, expectedTop = note.ox + panel.bx * note.s, note.oy + panel.by * note.s
                    check(math.abs(projected.cx - expectedLeft - 832 * scaleX) < 0.00001
                        and math.abs(projected.cy - expectedTop - 1400 * scaleY) < 0.00001
                        and math.abs(projected.w - 397 * scaleX) < 0.00001
                        and math.abs(projected.h - 387 * scaleY) < 0.00001, "酒馆热点精确跟随当前Viewport note")
                    check(drawn.hole and drawn.hs and drawn.hole.w <= drawn.hs.w + 16.001
                        and drawn.hole.h <= drawn.hs.h + 16.001, "最终draw只开酒馆小目标洞而非完整左栏")
                    check(not overlaps(drawn.bubble, drawn.hole) and not overlaps(drawn.skip, drawn.hole),
                        "提示及跳过不遮真实酒馆目标")
                    local x, y = panelPosition("left", 540, 150)
                    local bx, by = panelPosition("left", 540, 1100)
                    local tx, ty = panelPosition("left", 832, 1400)
                    local before = TM.getProgress().step
                    clearCalls()
                    check(not TM.canPointerStart(x, y), "原顶部空白带不再放行")
                    check(not TM.canPointerStart(bx, by) and TM.canPointerStart(tx, ty),
                        "其他建筑down阻断，仅酒馆目标放行")
                    click(bx, by)
                    check(TM.getProgress().step == before and not TM.isGroupCompleted(4), "非目标建筑点击不完成教程")
                    check(n("town.handleInput") == 0 and n("action") == 0, "非目标建筑不穿透业务或发action")
                    click(x, y)
                    check(not TM.isGroupCompleted(4) and n("persist") == 0 and n("town.handleInput") == 0,
                        "空白点击不完成、不保存、不派发")
                    click(tx, ty)
                    check(TM.getProgress().step == before and not TM.isGroupCompleted(4)
                        and n("persist") == 0 and n("town.handleInput") == 1,
                        "酒馆目标只透传一次，不把延迟打开前的点击当成功")
                    TM.notifyEvent("enter_tavern")
                    check(TM.isGroupCompleted(4) and n("persist") == 1,
                        "成功开页回执enter_tavern才完成且只保存一次")
                    TM.notifyEvent("enter_tavern")
                    check(n("persist") == 1, "重复成功回执不二次保存")
                    TM.update(0.3)
                    TM.startGroup(5)
                    TM.update(1.2)
                    invoke("HandleNanoVGRenderHorizon", {})
                    check(TM.getCurrentHighlight() == "building_church" and projected and projected.spotlight == nil,
                        "下一个建筑教程不继承其他目标或spotlight")
                    check(drawn and drawn.hole and drawn.hs and drawn.hole.w <= drawn.hs.w + 16.001,
                        "建筑教程保留原小热点光环")
                    state.missing = true
                    invoke("HandleNanoVGRenderHorizon", {})
                    check(projected == nil and drawn and drawn.hs == nil and drawn.hole == nil,
                        "缺目标时旧洞不残留，不制造虚假可见目标")
                end)
            end
        end
        runCase("生产投影复用非默认scaleX与屏幕裁切", function()
            fixture(true, true, 3)
            local spot = { cx = 540, cy = 1200, w = 1080, h = 2400 }
            for _, panelId in ipairs({ "left", "right", "modal" }) do
                for _, size in ipairs({ { 1920, 1080 }, { 844, 390 } }) do
                    RT.logicalW, RT.logicalH = size[1], size[2]
                    local scale = size[2] / 1080
                    local panel = VP.PANELS[panelId]
                    local origin = panelId == "right" and (size[1] - 486 * scale - panel.bx * scale) or 0
                    local sx, sy = 0.37 * scale, VP.DS * scale
                    if panel then VP.note(panelId, origin, 0, scale, sx) end
                    TM.clearHotspots()
                    TM.registerHotspot(TM.getCurrentHighlight(), 540, 150, 160, 100, panelId, spot)
                    projectTutorial()
                    check(projected and projected.spotlight and drawn.hs ~= nil,
                        "抽取真实投影支持 " .. panelId .. " 非默认横缩")
                    if projected and projected.spotlight then
                        local expectedX, expectedY, expectedW, expectedH
                        if panelId == "modal" then
                            local fit = math.min(size[1] / 1080, size[2] / 2400)
                            expectedX, expectedY = size[1] * 0.5, size[2] * 0.5
                            expectedW, expectedH = 1080 * fit, 2400 * fit
                        else
                            expectedX, expectedY = origin + panel.bx * scale + 540 * sx, 1200 * sy
                            expectedW, expectedH = 1080 * sx, 2400 * sy
                        end
                        check(math.abs(projected.spotlight.cx - expectedX) < 0.00001
                            and math.abs(projected.spotlight.cy - expectedY) < 0.00001
                            and math.abs(projected.spotlight.w - expectedW) < 0.00001
                            and math.abs(projected.spotlight.h - expectedH) < 0.00001,
                            "独立视觉矩形与热点共用真实note/模态fit")
                        check(math.abs(drawn.hs.w - projected.w) < 0.00001
                            and math.abs(drawn.hs.h - projected.h) < 0.00001,
                            "非默认scaleX下命中范围仍仅实际热点")
                    end
                end
            end
            TM.clearHotspots()
            TM.registerHotspot(TM.getCurrentHighlight(), -1200, 150, 100, 100, "left", spot)
            projectTutorial()
            check(drawn.hs == nil and drawn.hole == nil, "完全出屏点击目标不因整栏视觉矩形而被伪造")
        end)
        runCase("普通与tri screen投影恒等及独立spotlight", function()
            for _, tri in ipairs({ false, true }) do
                fixture(tri, true, 3, 1)
                for _, size in ipairs({ { 1920, 1080 }, { 844, 390 } }) do
                    RT.logicalW, RT.logicalH = size[1], size[2]
                    local x, y, w, h = battleTarget()
                    local spot = { cx = x + 20, cy = y + 10, w = 180, h = 120 }
                    VP._notes = {} -- screen不依赖任何右/中栏note，普通模式只验投影不验战斗业务。
                    TM.clearHotspots()
                    TM.registerCharacterDetailHotspot("battle_hero_detail", state.targetHeroId, x, y, w, h, "screen")
                    local hs = TM.getCurrentHotspot()
                    hs.spotlight = spot
                    projectTutorial()
                    check(projected and projected.cx == x and projected.cy == y and projected.w == w and projected.h == h,
                        "ordinary/tri screen热点不因外帧/DPR/无note重复投影")
                    check(projected and projected.spotlight and projected.spotlight.cx == spot.cx
                        and projected.spotlight.cy == spot.cy and projected.spotlight.w == spot.w
                        and projected.spotlight.h == spot.h,
                        "screen独立视觉矩形也走project(rect,0,0,1,1)")
                    check(drawn and drawn.hs and math.abs(drawn.hs.w - w) < 0.00001
                        and math.abs(drawn.hs.h - h) < 0.00001
                        and not TM.canPointerStart(x + w * 0.5 + 1, y),
                        "screen视觉spotlight不扩大实际点击目标")
                    check(n("tri.handleInput") == 0 and n("battle.openDetail") == 0,
                        "纯投影不声称ordinary战斗业务可达或成功")
                end
            end
        end)
        runCase("准备期非法按下延迟松开不能推进", function()
            fixture(true, false, 1)
            local x, y = panelPosition("right", 540, 600)
            local before = TM.getProgress().step
            local allow = false
            mods["ui.tutorial.TutorialPageRecovery"].prepare = function()
                if not allow then allow = true; return true end
                return false
            end
            screenPosition(x, y)
            invoke("HandleMouseButtonDownHorizon")
            TM.update(0.5)
            invoke("HandleNanoVGRenderHorizon", {})
            invoke("HandleMouseButtonUpHorizon")
            check(TM.getProgress().step == before and n("character.handleInput") == 0,
                "准备期被挡down不可在就绪up伪造一次点击")
            mods["ui.tutorial.TutorialPageRecovery"].prepare = preparePage
        end)
        runCase("Gifted 事件步骤同仓库格双击仍派发两次", function()
            for _, tri in ipairs({ false, true }) do
                fixture(tri, true, 2, 1)
                local battleX, battleY = battleTarget()
                local firstStep = TM.getProgress().step
                if tri then
                    click(battleX, battleY) -- 实际三队宿主down/up→fake业务open→真实TM成功回执。
                    check(n("tri.handleInput") == 1, "gifted三队首步真实Input路由到battle业务一次")
                else
                    -- 普通布局不虚造三队Input可达：仍模拟组1battle目标透传及业务成功链。
                    check(TM.handleScreenClick(battleX, battleY) == false
                        and TM.getProgress().step == firstStep, "gifted普通布局battle目标tap本身不推进")
                    check(openFromBattle(battleX, battleY), "gifted普通布局显式模拟真实battle开页成功回执")
                end
                check(TM.getProgress().step == firstStep + 1 and TM.getCurrentHighlight() == "equip_slot_weapon"
                    and state.characterOpen and state.characterTab == "equip"
                    and TM.getEquipmentHeroId() == state.targetHeroId and n("characterDetail.open") == 1,
                    "组1首步battle成功后接受同hero且进入武器槽，不能以avatar或裸事件代替")
                TM.update(0)
                invoke("HandleNanoVGRenderHorizon", {})
                local targetX, targetY = panelPosition("right", 540, 600)
                click(targetX, targetY)
                check(TM.getCurrentHighlight() == "equip_item_gifted", "真实TM武器槽点击进入gifted事件步骤")
                state.warehouse = true
                local x, y = panelPosition("left", 140, 1060)
                clearCalls()
                screenPosition(x, y)
                invoke("HandleMouseButtonDownHorizon")
                clock.elapsedTime = clock.elapsedTime + 0.15
                invoke("HandleMouseButtonUpHorizon")
                check(n("backpack.handleInput") == 1 and state.detail and state.pinned,
                    "仓库首击派发一次并pin浮层")
                local firstTime = clock.elapsedTime
                local before = TM.getProgress().step
                screenPosition(x, y)
                invoke("HandleMouseButtonDownHorizon")
                check(n("detail.close") == 1 and not state.detail,
                    "第二击同格按下确实经过真实浮层dismiss")
                clock.elapsedTime = clock.elapsedTime + 0.15
                invoke("HandleMouseButtonUpHorizon")
                check(clock.elapsedTime - firstTime < 0.2 and n("backpack.handleInput") == 2,
                    "0.2秒内第二击dismiss后仍补派发同仓库格，不被吞掉")
                check(TM.getProgress().step == before and not TM.isGroupCompleted(1)
                    and n("persist") == 0, "两次点击不伪装穿戴成功，仍等待真实装备回执")
                local hits = 0
                for _, e in ipairs(events) do
                    if e.name == "backpack.handleInput" then
                        hits = hits + 1
                        check(math.abs(e.x - 140) < 0.00001 and math.abs(e.y - 1060) < 0.00001,
                            "两次都派到同仓库格真实设计坐标")
                    end
                end
                check(hits == 2 and n("detail.handleInput") == 0 and n("action") == 0,
                    "恰好两次仓库Input，无浮层或额外action")
            end
        end)
        runCase("非gifted事件教程不补派发仓库dismiss点击", function()
            fixture(true, true, 2)
            TM.skipCurrentGroup()
            TM.update(0.3)
            TM.startGroup(8)
            TM.update(0.3)
            check(TM.getCurrentHighlight() == "tavern_btn_gacha10", "真实非gifted事件步骤")
            state.warehouse, state.detail, state.pinned, state.owner = true, true, true, "backpack"
            clearCalls()
            local x, y = panelPosition("left", 140, 1060)
            click(x, y)
            check(n("detail.close") == 1 and n("backpack.handleDragBegin") == 1,
                "非gifted也实际经历浮层dismiss按压路径")
            check(n("backpack.handleInput") == 0 and n("action") == 0
                and TM.getCurrentHighlight() == "tavern_btn_gacha10",
                "非gifted不能借装备格例外穿透或推进教程")
        end)
        -- Touch payload 只含 TouchID/X/Y，坐标量化为真实整数物理像素；鼠标刻意不在目标上。
        local function touch(id, x, y)
            local px = math.floor((RT.frameOx + x * RT.frameScale) * RT.dpr + 0.5)
            local py = math.floor((RT.frameOy + y * RT.frameScale) * RT.dpr + 0.5)
            return {
                TouchID = { GetInt = function() return id end },
                X = { GetInt = function() return px end },
                Y = { GetInt = function() return py end },
            }
        end
        local function touchFixture(tri, dpr, groupId)
            fixture(tri, true, dpr, groupId)
            cursor.x, cursor.y = 0, 0
            local x, y = panelPosition("right", 540, 600)
            if groupId == 1 then x, y = battleTarget() end
            return x, y, TM.getProgress().step
        end
        runCase("Touch target X/Y + frame/DPR 不读取鼠标", function()
            for _, tri in ipairs({ false, true }) do
                local x, y, before = touchFixture(tri, 3)
                local event = touch(41, x, y)
                check(event.Button == nil and cursor.x == 0 and cursor.y == 0, "touch payload 无Button，鼠标在0,0")
                invoke("HandleTouchBeginHorizon", event)
                check(TM.getProgress().step == before and n("character.handleDragBegin") == 0, "touch down 到右栏但不推进")
                clock.elapsedTime = clock.elapsedTime + 0.2
                invoke("HandleTouchEndHorizon", event)
                check(TM.getProgress().step == before + 1 and n("persist") == 1
                    and n("character.handleInput") == 1, "touch target up 推进/透传恰好一次")
                local found = false
                for _, e in ipairs(events) do
                    if e.name == "character.handleInput" then
                        found = true
                        check(math.abs(e.x - 540) < 1 and math.abs(e.y - 600) < 1,
                            "整数物理touch经frame/DPR逆变换落在实际右栏设计目标")
                    end
                end
                check(found and cursor.x == 0 and cursor.y == 0, "实际业务收到touch坐标，鼠标未被伪造移动")
                invoke("HandleTouchEndHorizon", event)
                check(TM.getProgress().step == before + 1 and n("character.handleInput") == 1, "重复touch up不推进/派发")
            end
        end)
        runCase("Touch battle screen frame/DPR真实回执及多指", function()
            for _, ratio in ipairs({ 1, 2, 3 }) do
                local x, y, before = touchFixture(true, ratio, 1)
                local primary, secondary = touch(81, x, y), touch(82, x, y)
                invoke("HandleTouchBeginHorizon", primary)
                invoke("HandleTouchBeginHorizon", secondary)
                invoke("HandleTouchMoveHorizon", touch(82, x + 120, y + 100))
                invoke("HandleTouchEndHorizon", secondary)
                check(TM.getProgress().step == before and n("tri.handleDragBegin") == 0
                    and n("tri.handleDragMove") == 0 and n("tri.handleInput") == 0
                    and n("persist") == 0 and not state.characterOpen,
                    "screen第二指不抢主指/派发业务/伪造成功")
                clock.elapsedTime = clock.elapsedTime + 0.2
                invoke("HandleTouchEndHorizon", primary)
                check(TM.getProgress().step == before + 1 and n("tri.handleInput") == 1
                    and n("characterDetail.open") == 1 and n("persist") == 1
                    and TM.getEquipmentHeroId() == state.targetHeroId and cursor.x == 0 and cursor.y == 0,
                    "screen主touch以物理整数X/Y经frame/DPR进入battle成功链，不读鼠标")
                for _, event in ipairs(events) do
                    if event.name == "tri.handleInput" then
                        check(math.abs(event.x - x) < 1 and math.abs(event.y - y) < 1,
                            "screen touch实际传给tri的逻辑坐标不重套Viewport")
                    end
                end
                invoke("HandleTouchEndHorizon", primary)
                invoke("HandleTouchEndHorizon", secondary)
                check(TM.getProgress().step == before + 1 and n("tri.handleInput") == 1
                    and n("persist") == 1, "screen重复主指/旧次指up不再推进/派发")
            end
        end)
        runCase("Touch battle screen拖出取消且新tap恢复", function()
            local x, y, before = touchFixture(true, 2, 1)
            invoke("HandleTouchBeginHorizon", touch(91, x, y))
            invoke("HandleTouchMoveHorizon", touch(91, x + 100, y + 150))
            clock.elapsedTime = clock.elapsedTime + 0.2
            invoke("HandleTouchEndHorizon", touch(91, x + 100, y + 150))
            check(TM.getProgress().step == before and n("persist") == 0 and n("tri.handleInput") == 0
                and n("characterDetail.open") == 0, "screen拖出不伪造打开或推进")
            check(n("tri.handleDragBegin") == 0 and n("tri.handleDragMove") == 0
                and n("tri.handleDragEnd") == 1, "screen入口不启动拖拽，取消仍释放来源清理")
            local target = touch(92, x, y)
            invoke("HandleTouchBeginHorizon", target)
            clock.elapsedTime = clock.elapsedTime + 0.2
            invoke("HandleTouchEndHorizon", target)
            check(TM.getProgress().step == before + 1 and n("tri.handleInput") == 1
                and n("persist") == 1, "screen取消后新touch tap真实打开并仅推进一次")
        end)
        runCase("Touch 缺热点 skip 优先于浮层", function()
            touchFixture(true, 2)
            state.detail, state.missing = true, true
            invoke("HandleNanoVGRenderHorizon", {})
            clearCalls()
            local layout = Overlay.layout(RT.logicalW, RT.logicalH, nil)
            local event = touch(51, layout.skip.cx, layout.skip.cy)
            invoke("HandleTouchBeginHorizon", event)
            check(state.detail and not TM.getProgress().completed["2"], "touch skip down不dismiss/提前完成")
            clock.elapsedTime = clock.elapsedTime + 0.2
            invoke("HandleTouchEndHorizon", event)
            check(TM.getCurrentHotspot() == nil and TM.getProgress().completed["2"] == true
                and n("persist") == 1, "touch缺热点skip完成并保存一次")
            noBusiness("touch skip")
            check(state.detail and cursor.x == 0 and cursor.y == 0, "touch skip首击保留浮层，不读取鼠标")
        end)
        runCase("Touch 第二指不能释放或推进主指", function()
            local x, y, before = touchFixture(true, 3)
            local primary, secondary = touch(61, x, y), touch(62, x, y)
            invoke("HandleTouchBeginHorizon", primary)
            invoke("HandleTouchBeginHorizon", secondary)
            invoke("HandleTouchMoveHorizon", touch(62, x + 180, y + 150))
            invoke("HandleTouchEndHorizon", secondary)
            check(TM.getProgress().step == before and n("persist") == 0
                and n("character.handleInput") == 0 and n("character.handleDragBegin") == 0
                and n("character.handleDragMove") == 0 and n("character.handleDragEnd") == 0,
                "不同ID begin/move/end不覆盖、释放或推进主指")
            clock.elapsedTime = clock.elapsedTime + 0.2
            invoke("HandleTouchEndHorizon", primary)
            check(TM.getProgress().step == before + 1 and n("persist") == 1
                and n("character.handleInput") == 1, "次指释放后主指仍可完成一次目标tap")
            invoke("HandleTouchEndHorizon", secondary)
            check(TM.getProgress().step == before + 1 and n("character.handleInput") == 1,
                "主指结束后旧次指up仍不派发")
        end)
        runCase("Touch 目标拖出取消点击", function()
            local x, y, before = touchFixture(false, 2)
            invoke("HandleTouchBeginHorizon", touch(71, x, y))
            invoke("HandleTouchMoveHorizon", touch(71, x + 100, y + 150))
            clock.elapsedTime = clock.elapsedTime + 0.2
            invoke("HandleTouchEndHorizon", touch(71, x + 100, y + 150))
            check(TM.getProgress().step == before and n("persist") == 0
                and n("character.handleInput") == 0, "touch拖出不推进/点击")
            check(n("character.handleDragBegin") == 0 and n("character.handleDragMove") == 0
                and n("character.handleDragEnd") == 1, "touch入口不启动右栏拖拽，取消仍释放来源清理")
            local target = touch(72, x, y)
            invoke("HandleTouchBeginHorizon", target)
            clock.elapsedTime = clock.elapsedTime + 0.2
            invoke("HandleTouchEndHorizon", target)
            check(TM.getProgress().step == before + 1 and n("character.handleInput") == 1,
                "取消后新指tap恢复，不遗留capture")
        end)
        -- 新入口按压身份专项：只通过真实Horizon down/move/up，绝不代抄生产token实现。
        local entryRoutes = {
            { name = "battle/tri", tri = true, group = 1, page = "tri" },
            { name = "avatar/tri", tri = true, group = 2, page = "character" },
            { name = "avatar/ordinary", tri = false, group = 2, page = "character" },
        }
        local function entryPosition(route)
            if route.group == 1 then return battleTarget() end
            return panelPosition("right", 540, 600)
        end
        local rightButton = { Button = { GetInt = function() return MOUSEB_RIGHT end } }
        local function entryPointer(kind, id)
            return {
                down = function(x, y)
                    if kind == "touch" then invoke("HandleTouchBeginHorizon", touch(id, x, y))
                    else screenPosition(x, y); invoke("HandleMouseButtonDownHorizon") end
                end,
                move = function(x, y)
                    if kind == "touch" then invoke("HandleTouchMoveHorizon", touch(id, x, y))
                    else screenPosition(x, y); invoke("HandleMouseMoveHorizon", {}) end
                end,
                up = function(x, y)
                    clock.elapsedTime = clock.elapsedTime + 0.2
                    if kind == "touch" then invoke("HandleTouchEndHorizon", touch(id, x, y))
                    else screenPosition(x, y); invoke("HandleMouseButtonUpHorizon") end
                end,
            }
        end
        local function noEntryTap(route, before, label)
            check(TM.getCurrentGroup() == route.group and TM.getProgress().step == before
                and TM.getEquipmentHeroId() == nil and not state.characterOpen
                and n("characterDetail.open") == 0 and n("persist") == 0,
                label .. " 不开详情/锁错hero/推进/保存")
            check(n("tri.handleInput") == 0 and n("character.handleInput") == 0
                and n("tri.handleDragBegin") == 0 and n("character.handleDragBegin") == 0
                and n("tri.handleDragMove") == 0 and n("character.handleDragMove") == 0
                and n("tri.handleRightClick") == 0 and n("character.handleRightClick") == 0
                and n("action") == 0, label .. " 不派发下层点击/拖拽/右键/action")
        end
        local function freshEntryTap(route, pointer, before, label)
            local x, y = entryPosition(route)
            pointer.down(x, y)
            check(n(route.page .. ".handleDragBegin") == 0 and n("characterDetail.open") == 0,
                label .. " 新down仍只capture不启动业务拖拽")
            pointer.up(x, y)
            check(TM.getProgress().step == before + 1 and TM.getEquipmentHeroId() == state.targetHeroId
                and state.characterOpen and state.characterHeroId == state.targetHeroId
                and n(route.page .. ".handleInput") == 1 and n("characterDetail.open") == 1
                and n("persist") == 1, label .. " 新手势恢复真实成功链一次")
        end
        for _, route in ipairs(entryRoutes) do
            for _, kind in ipairs({ "mouse", "touch" }) do
                for _, mutation in ipairs({ "hero_changed", "hero_changed_back", "missing_one_frame" }) do
                    runCase("入口身份 " .. route.name .. " " .. kind .. " " .. mutation, function()
                        fixture(route.tri, true, 3, route.group)
                        cursor.x, cursor.y = 0, 0
                        local pointer = entryPointer(kind, 101)
                        local x, y = entryPosition(route)
                        local before = TM.getProgress().step
                        pointer.down(x, y)
                        check(n(route.page .. ".handleDragBegin") == 0 and n("characterDetail.open") == 0,
                            "真实入口down不启动下层拖拽/开详情")
                        if mutation == "missing_one_frame" then state.missing = true
                        else state.targetHeroId = 2 end
                        invoke("HandleNanoVGRenderHorizon", {})
                        check(mutation ~= "missing_one_frame" or TM.getCurrentHotspot() == nil,
                            "缺热点变体确实有一帧无真实目标")
                        if mutation ~= "hero_changed" then
                            state.missing, state.targetHeroId = false, 1
                            invoke("HandleNanoVGRenderHorizon", {})
                        end
                        pointer.up(x, y)
                        noEntryTap(route, before, "旧入口身份up")
                        pointer.up(x, y)
                        noEntryTap(route, before, "旧身份重复up")
                        freshEntryTap(route, pointer, before, "身份/热点恢复后")
                    end)
                end
                runCase("入口同hero逐帧重注册 " .. route.name .. " " .. kind, function()
                    fixture(route.tri, true, 2, route.group)
                    local pointer = entryPointer(kind, 102)
                    local x, y = entryPosition(route)
                    local before = TM.getProgress().step
                    pointer.down(x, y)
                    for _ = 1, 3 do invoke("HandleNanoVGRenderHorizon", {}) end
                    pointer.up(x, y)
                    check(TM.getProgress().step == before + 1 and n("characterDetail.open") == 1
                        and n(route.page .. ".handleInput") == 1 and n("persist") == 1,
                        "同hero同来源逐帧重建热点不误取消合法手势")
                end)
                runCase("入口拖出再回来仍取消 " .. route.name .. " " .. kind, function()
                    fixture(route.tri, true, 2, route.group)
                    local pointer = entryPointer(kind, 103)
                    local x, y = entryPosition(route)
                    local before = TM.getProgress().step
                    pointer.down(x, y)
                    pointer.move(x + 100, y + 150)
                    pointer.move(x, y)
                    pointer.up(x, y)
                    noEntryTap(route, before, "拖出回原点旧up")
                    freshEntryTap(route, pointer, before, "拖出取消后")
                end)
                for _, transform in ipairs({ "dpr", "frameScale", "frameOx", "frameOy", "logicalW", "logicalH" }) do
                    runCase("按住变换 " .. route.name .. " " .. kind .. " " .. transform, function()
                        fixture(route.tri, true, 2, route.group)
                        local pointer = entryPointer(kind, 104)
                        local x, y = entryPosition(route)
                        local before = TM.getProgress().step
                        pointer.down(x, y)
                        if transform == "dpr" then RT.dpr = 3
                        elseif transform == "frameScale" then RT.frameScale = 0.9
                        elseif transform == "frameOx" then RT.frameOx = RT.frameOx + 11
                        elseif transform == "frameOy" then RT.frameOy = RT.frameOy + 7
                        elseif transform == "logicalW" then RT.logicalW, RT.windowW = 1880, 1880
                        else RT.logicalH, RT.windowH = 1040, 1040 end
                        invoke("HandleNanoVGRenderHorizon", {})
                        x, y = entryPosition(route)
                        pointer.up(x, y) -- 重新按新frame/DPR给出相同实际目标，不用坐标越界替代token检测。
                        noEntryTap(route, before, "按住变换旧up")
                        freshEntryTap(route, pointer, before, "变换后的新手势")
                    end)
                end
                runCase("入口一次失效后变换还原仍取消 " .. route.name .. " " .. kind, function()
                    fixture(route.tri, true, 2, route.group)
                    local pointer = entryPointer(kind, 109)
                    local x, y = entryPosition(route)
                    local before = TM.getProgress().step
                    local originalDpr = RT.dpr
                    pointer.down(x, y)
                    RT.dpr = 3
                    invoke("HandleNanoVGRenderHorizon", {})
                    pointer.move(x, y) -- 变换期仍指向同一逻辑目标，不以越界造成取消。
                    RT.dpr = originalDpr
                    invoke("HandleNanoVGRenderHorizon", {})
                    pointer.up(x, y)
                    noEntryTap(route, before, "DPR变更再还原旧up")
                    freshEntryTap(route, pointer, before, "DPR还原后的新手势")
                end)
                for _, overlay in ipairs({ "reward", "story" }) do
                    for _, releaseBlocked in ipairs({ false, true }) do
                        runCase("入口让位恢复 " .. route.name .. " " .. kind .. " " .. overlay
                            .. " release=" .. tostring(releaseBlocked), function()
                            fixture(route.tri, true, 2, route.group)
                            local pointer = entryPointer(kind, 105)
                            local x, y = entryPosition(route)
                            local before = TM.getProgress().step
                            pointer.down(x, y)
                            state[overlay] = true
                            TM.update(0)
                            invoke("HandleNanoVGRenderHorizon", {})
                            check(not TM.isInputActive(), "高优先级窗口真实阻断入口输入")
                            if releaseBlocked then pointer.up(x, y) end
                            state[overlay] = false
                            TM.update(0)
                            invoke("HandleNanoVGRenderHorizon", {})
                            pointer.up(x, y)
                            noEntryTap(route, before, "让位后旧up")
                            freshEntryTap(route, pointer, before, "让位恢复后的新手势")
                        end)
                    end
                end
            end
            runCase("主touch身份变化不被第二指覆盖 " .. route.name, function()
                fixture(route.tri, true, 3, route.group)
                cursor.x, cursor.y = 0, 0
                local pointer = entryPointer("touch", 107)
                local x, y = entryPosition(route)
                local before = TM.getProgress().step
                pointer.down(x, y)
                invoke("HandleTouchBeginHorizon", touch(108, x, y))
                invoke("HandleTouchMoveHorizon", touch(108, x + 140, y + 100))
                invoke("HandleTouchEndHorizon", touch(108, x, y))
                noEntryTap(route, before, "第二指不可释放主指身份")
                state.targetHeroId = 2
                invoke("HandleNanoVGRenderHorizon", {})
                state.targetHeroId = 1
                invoke("HandleNanoVGRenderHorizon", {})
                pointer.up(x, y)
                noEntryTap(route, before, "换hero又恢复后主指旧up")
                freshEntryTap(route, pointer, before, "多指与身份变化后新主指")
            end)
            runCase("入口右键阻断且不释放左键 " .. route.name, function()
                fixture(route.tri, true, 3, route.group)
                local x, y = entryPosition(route)
                local before = TM.getProgress().step
                check(TM.canPointerStart(x, y, MOUSEB_LEFT)
                    and not TM.canPointerStart(x, y, MOUSEB_RIGHT), "入口仅放行左键/触摸")
                screenPosition(x, y)
                invoke("HandleMouseButtonDownHorizon", rightButton)
                invoke("HandleMouseButtonUpHorizon", rightButton)
                noEntryTap(route, before, "右键入口")
                invoke("HandleMouseButtonDownHorizon")
                invoke("HandleMouseButtonDownHorizon", rightButton)
                invoke("HandleMouseButtonUpHorizon", rightButton)
                noEntryTap(route, before, "左键按住期间副键down/up")
                clock.elapsedTime = clock.elapsedTime + 0.2
                invoke("HandleMouseButtonUpHorizon")
                check(TM.getProgress().step == before + 1 and n(route.page .. ".handleInput") == 1
                    and n("characterDetail.open") == 1 and n("persist") == 1,
                    "副键未清主键token，主键up仍真实成功一次")
                invoke("HandleMouseButtonUpHorizon", rightButton)
                check(TM.getProgress().step == before + 1 and n("persist") == 1,
                    "成功后旧右键up不重复推进/保存")
            end)
            runCase("入口取消后普通来源拖拽未损坏 " .. route.name, function()
                fixture(route.tri, true, 2, route.group)
                local pointer = entryPointer("mouse", 106)
                local x, y = entryPosition(route)
                local before = TM.getProgress().step
                pointer.down(x, y); pointer.move(x + 100, y + 150); pointer.up(x, y)
                noEntryTap(route, before, "入口旧拖拽取消")
                TM.skipCurrentGroup(); TM.update(0.3)
                check(not TM.isActive(), "确实离开入口教学后验证普通手势，不走教学放行例外")
                clearCalls()
                pointer.down(x, y); pointer.move(x + 40, y + 40); pointer.up(x + 40, y + 40)
                check(n(route.page .. ".handleDragBegin") == 1 and n(route.page .. ".handleDragMove") == 1
                    and n(route.page .. ".handleDragEnd") >= 1 and n(route.page .. ".handleInput") == 0,
                    "普通来源仍真实收到Begin/Move/End，未因入口cancel留坏capture")
            end)
        end
        for _, tri in ipairs({ false, true }) do
            runCase("gifted保留右键快捷穿戴路由 " .. tostring(tri), function()
                fixture(tri, true, 2, 1)
                local bx, by = battleTarget()
                if tri then click(bx, by) else openFromBattle(bx, by) end
                TM.update(0); invoke("HandleNanoVGRenderHorizon", {})
                local rx, ry = panelPosition("right", 540, 600)
                click(rx, ry)
                check(TM.getCurrentHighlight() == "equip_item_gifted", "右键反例真实走完组1battle及武器槽进入gifted")
                state.warehouse = true
                clearCalls()
                local x, y = panelPosition("left", 140, 1060)
                check(TM.canPointerStart(x, y, MOUSEB_RIGHT), "gifted事件步骤仍放行右键，不被入口专用限制误伤")
                screenPosition(x, y)
                invoke("HandleMouseButtonDownHorizon", rightButton)
                invoke("HandleMouseButtonUpHorizon", rightButton)
                check(n("backpack.handleRightClick") == 1 and n("backpack.handleInput") == 0
                    and n("characterDetail.open") == 0 and n("persist") == 0
                    and TM.getCurrentHighlight() == "equip_item_gifted",
                    "右键仅派发真实仓库快捷穿戴业务一次，不以spy伪造穿戴成功")
            end)
        end
        for _, transformed in ipairs({ false, true }) do
            for _, ratio in ipairs({ 1, 2, 3 }) do
                runCase("选关滚轮 frame=" .. tostring(transformed) .. " DPR=" .. ratio, function()
                    fixture(true, transformed, ratio)
                    TM.skipCurrentGroup()
                    TM.update(1)
                    mods["ui.battle.stage.StageSelectDialog"].isOpen = function() return true end
                    mods["ui.battle.tri.BattleTriPage"].handleScroll = function(wheel, x, y)
                        record("stageWheel", x, y)
                        check(wheel == -1, "滚轮增量保持不变")
                        return true
                    end
                    screenPosition(650, 350)
                    invoke("HandleMouseWheelHorizon", { Wheel = { GetInt = function() return -1 end } })
                    local event = events[#events]
                    check(n("stageWheel") == 1 and event.name == "stageWheel"
                        and math.abs(event.x - 650) < 0.00001 and math.abs(event.y - 350) < 0.00001,
                        "选关滚轮与点击共用逆外帧及DPR坐标，不传屏幕逻辑坐标")
                    mods["ui.battle.stage.StageSelectDialog"].isOpen = function() return false end
                    mods["ui.battle.tri.BattleTriPage"].handleScroll = noop
                end)
            end
        end
    end)
    if not ok then check(false, "Start exception: " .. tostring(err)) end
    if overlayOriginals.module then overlayOriginals.module.draw = overlayOriginals.draw end
    require, input, time = nativeRequire, originalInput, originalTime
    VP._notes = originalNotes
    for name, saved in pairs(nvgOriginals) do rawset(_G, name, saved.value) end
    local added = {}
    for key in pairs(_G) do if horizonGlobal(key) and originals[key] == nil then added[#added + 1] = key end end
    for _, key in ipairs(added) do rawset(_G, key, nil) end
    for key, value in pairs(originals) do rawset(_G, key, value) end
    if failures == 0 then
        print("[tutorial_horizon_input_test] ALL PASS: " .. cases .. " cases, " .. assertions .. " assertions")
    else print("[FAIL] tutorial_horizon_input_test: " .. failures .. " failures, " .. assertions .. " assertions") end
    engine:Exit()
end
