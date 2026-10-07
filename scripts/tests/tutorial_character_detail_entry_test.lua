-- 详情入口专项：基于既有 tests 的 Start/pcall/engine:Exit 生命周期。
-- Runtime: .cli/UrhoXRuntime tests/tutorial_character_detail_entry_test.lua -tapcode_dir=/workspace -tool_mode -nosound -graphicsheadless
-- 整模块执行真实 TM/Recovery/CharacterDetail/CharacterInput/Draw2；页面、音效、装备业务为显式内存 spy。
-- BattleTriPage 执行资源中完整 shared helpers、draw 入口热点段、完整 handleInput；不声称整 draw/GPU 像素验收。
-- 所有源码经 cache:GetFile/ReadLine/Dispose/load env；无玩家档、action、全局 require/package 改写或随机数调用。
function Start()
    local TAG = "[tutorial_character_detail_entry_test] "
    local assertions, cases, failures = 0, 0, 0
    local sources, reads = {}, {}
    local function check(value, label)
        assertions = assertions + 1
        assert(value, label)
    end
    local function eq(actual, expected, label)
        check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
    end
    local function near(a, b, label)
        check(type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.00001, label)
    end
    local function copy(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for key, item in pairs(value) do out[key] = copy(item) end
        return out
    end
    local function same(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k, v in pairs(a) do if not same(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end
    local function noop() end
    local function source(path)
        if sources[path] then return sources[path] end
        local file = assert(cache:GetFile(path), "missing real source " .. path)
        local ok, text = pcall(function()
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            return table.concat(lines, "\n")
        end)
        file:Dispose()
        assert(ok, text)
        reads[#reads + 1], sources[path] = path, text
        return text
    end
    local function section(path, first, last)
        local text = source(path)
        local a = assert(text:find(first, 1, true), "missing source start " .. path .. " " .. first)
        local b = assert(text:find(last, a + #first, true), "missing source end " .. path .. " " .. last)
        return text:sub(a, b - 1)
    end
    local function compile(text, path, env)
        local fn, err = load(text, "@resource:" .. path, "t", env)
        assert(fn, err)
        return fn()
    end
    local function runCase(label, fn)
        cases = cases + 1
        local ok, err = pcall(fn)
        if ok then print(TAG .. "PASS " .. label)
        else
            failures = failures + 1
            local message = TAG .. "FAIL " .. label .. " " .. tostring(err)
            print(message)
            log:Write(LOG_ERROR, message)
        end
    end
    local function newContext(width, height)
        local c = { width = width, height = height, unlocked = 1, activeTeam = 1,
            clock = { elapsedTime = 100 }, modules = {}, env = {}, saves = {}, receipts = {}, opens = {},
            warehouse = { open = false }, frames = {}, actions = 0, drag = { active = false, moved = false },
            select = {}, scrolling = false, scroll = 0, dragY = 0, deltaY = 0, prepares = 0,
            memory = { session = { tutorialProgress = { version = 1, completed = {}, queue = {} }, claimedScenarios = {} },
                battle = { maxStageId = 102 }, heroes = { roster = { [1] = { level = 10 }, [2] = { level = 20 }, [3] = { level = 30 } },
                    deployed = { 1, 2, 3, 0 } }, equipment = { inventory = {}, equipped = {} } },
            teams = { { slots = { { state = "occupied", heroId = 1 }, { state = "occupied", heroId = 2 },
                { state = "occupied", heroId = 3 }, { state = "empty" } } },
                { slots = { { state = "occupied", heroId = 3 }, { state = "empty" }, { state = "empty" }, { state = "empty" } } },
                { slots = { { state = "locked" }, { state = "locked" }, { state = "locked" }, { state = "locked" } } } },
            roster = { { heroId = 3, owned = true, level = 30 }, { heroId = 1, owned = true, level = 10 },
                { heroId = 2, owned = true, level = 20 } } }
        local e, mods = c.env, c.modules
        setmetatable(e, { __index = _G })
        e._G, e.time = e, c.clock
        e.H_SEAM_BACK, e.H_TRI_L0 = true, true
        e.print = function(...) print(TAG .. "production", ...) end
        e.require = function(name)
            local mod = mods[name]
            assert(mod ~= nil, "unprepared dependency " .. tostring(name))
            return mod
        end
        -- No lazy real business fallback: every loaded module is allowlisted or an explicit spy.
        local function actual(name)
            local mod = compile(source(name:gsub("%.", "/") .. ".lua"), name, e)
            assert(type(mod) == "table", "real module result " .. name)
            mods[name] = mod
            return mod
        end
        c.actual = actual
        for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgTranslate", "nvgScale", "nvgResetTransform",
            "nvgScissor", "nvgIntersectScissor", "nvgResetScissor", "nvgBeginPath", "nvgRect", "nvgRoundedRect",
            "nvgFillColor", "nvgFillPaint", "nvgFill", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke",
            "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgText", "nvgTextBox", "nvgPathWinding", "nvgGlobalAlpha" }) do e[name] = noop end
        e.nvgTextBounds = function(_, _, _, text) return (utf8.len(text) or 0) * 10 end
        e.nvgRGBA = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
        e.nvgCreateImage = function() return -1 end
        e.nvgImagePattern, e.nvgImagePatternTinted = function() return {} end, function() return {} end
        c.store = { Get = function(key) return c.memory[key] end }
        mods["core.PlayerStore"] = c.store
        mods["core.I18n"] = { lookup = function(text) return text end, format = string.format }
        mods["config.HeroConfig"] = { get = function(id) return { name = "fixture hero " .. tostring(id) } end }
        mods["config.HeroAssetUtil"] = { ensureIcon = function() return -1 end }
        mods["config.ExpTable"] = { TEAM_COUNT = 3, getUnlockedTeamCount = function() return c.unlocked end }
        mods["ui.widget.HeroFrame"] = { draw = function(_, opts) c.frames[#c.frames + 1] = copy(opts) end }
        mods["core.DarkIcon"], mods["core.HorizonBg"] = {}, { draw = noop }
        mods["systems.GameSFX"] = { play = noop }
        mods["systems.StoryPlayer"] = { onPlace = noop }
        mods["ui.story.ScenarioDialogue"] = { isActive = function() return false end }
        mods["runtime.GameAction"] = { sendAction = function() c.actions = c.actions + 1; error("unexpected business action") end }
        local pagePaths = { "ui.church.ChurchPage", "ui.church.talent.TalentPage", "ui.tavern.TavernPage",
            "ui.market.MarketPage", "ui.loot.LootBoxPage", "ui.story.task.TaskPage", "ui.blacksmith.BlacksmithPage",
            "ui.hud.popup.PlayerInfoPanel", "ui.hud.popup.RewardPopup", "ui.hud.popup.OfflineRewardPanel",
            "ui.hud.popup.UpdateNoticePopup", "ui.hud.popup.LevelUpPopup", "ui.story.gate.DarkTitleScreenGate",
            "ui.story.gate.LetterIntro", "ui.story.gate.IntroCutscene", "ui.dungeon.DungeonBattleScene", "ui.tower.TowerBattleScene",
            "ui.battle.stage.SweepDialog", "ui.battle.popup.DamageStatsPanel", "ui.battle.stage.StageSelectDialog",
            "ui.battle.popup.TerminalConfirmDialog", "ui.character.equip.EquipmentDetail" }
        for _, name in ipairs(pagePaths) do
            mods[name] = { isOpen = function() return false end, isActive = function() return false end,
                isRecruitBusy = function() return false end, isRecruitConfirmOpen = function() return false end,
                currentRowTag = function() return nil end, close = noop, dismissHover = noop }
        end
        mods["ui.hud.BottomNav"] = { setTabLocked = noop, getSelectedIndex = function() return 3 end }
        mods["ui.town.TownScene"] = { cancelPendingPageOpen = noop }
        local panel = { getTeamSlotsData = function(t) return c.teams[t].slots end,
            getActiveTeamIdx = function() return c.activeTeam end,
            getOwnedHero = function(id) return c.memory.heroes.roster[tonumber(id)] end,
            getEffectiveLevel = function(id) return c.memory.heroes.roster[tonumber(id)].level end,
            getTeamSlotLayout = function(t)
                local result = {}
                for i, slot in ipairs(c.teams[t].slots) do result[i] = slot.heroId or 0 end
                return result
            end,
            prepareTutorial = function() c.activeTeam = 1; c.prepares = c.prepares + 1 end,
            setActiveTeam = function(t) if t > c.unlocked then return false end; c.activeTeam = t; return true end,
            isHeroesDataApplied = function() return true end }
        mods["ui.character.panel.CharacterPanel"] = panel
        local bag = c.warehouse
        mods["ui.backpack.BackpackPanel"] = { isOpen = function() return bag.open end,
            forceClose = function() bag.open = false end,
            acquireForEquipment = function(id) bag.open, bag.heroId, bag.acquires = true, id, (bag.acquires or 0) + 1 end,
            releaseForEquipment = function() bag.open, bag.heroId = false, nil end,
            setEquipmentSlotFilter = function(slot, id) bag.heroId, bag.slot = id, slot end,
            ensureTutorialEquipment = function(id, slot)
                local changed = not bag.open or bag.heroId ~= id or bag.slot ~= slot
                bag.open, bag.heroId, bag.slot = true, id, slot
                return changed
            end }
        mods["ui.character.equip.EquipmentBag"] = { isOpen = function() return false end, shouldBattleOverlay = function() return false end }
        for _, name in ipairs({ "config.ClassConfig", "systems.AttributeDef", "core.GameState", "config.EquipmentConfig",
            "systems.EquipmentSystem", "systems.EquipmentPower", "systems.ButtonFeedback", "ui.widget.ImageCache" }) do mods[name] = {} end
        mods["ui.character.detail.CharacterDetailAttrs"] = { collectAttributes = noop }
        mods["ui.character.detail.CharacterDetailEquip"] = { reset = noop, endSideDrag = noop, draw = noop }
        mods["ui.character.hero.AwakeningPanel"] = { reset = noop, setClassIcons = noop, setOwnedDataGetter = noop }
        mods["ui.character.hero.HeroScenario"] = { onOpenHero = noop }
        mods["ui.battle.combat.ProjectileSystem"] = { hasProjectile = function() return false end }
        mods["ui.hud.popup.SettingsPanel"] = { isEffectsEnabled = function() return true end }
        local layout = actual("core.BattleLayout")
        local combatAnim = actual("ui.battle.combat.BattleCombatAnim")
        c.combatAnim = combatAnim
        actual("config.GameConfig")
        actual("config.TutorialConfig")
        actual("core.NumberUtil")
        actual("core.DrawUtil")
        actual("core.Viewport")
        actual("ui.tutorial.TutorialOverlay")
        local tm = actual("systems.TutorialManager")
        c.tm = tm
        -- DetailDraw is a rendering spy; its clicked slot/tab constants are compiled from the real resource.
        local de = setmetatable({ M = {}, DESIGN_W = 1080, BattleLayout = layout }, { __index = e })
        compile(section("ui/character/detail/CharacterDetailDraw.lua", "local DT_SLOT_SIZE =", "-- ======================== 中间部分布局常量"), "DetailDraw slots", de)
        compile(section("ui/character/detail/CharacterDetailDraw.lua", "local BTN_UNEQUIP_CX,", "-- ======================== 底部按钮布局常量"), "DetailDraw batch constants", de)
        compile(section("ui/character/detail/CharacterDetailDraw.lua", "local BTN_BACK_CX,", "-- 左右切换箭头按钮布局"), "DetailDraw tabs", de)
        local dd = de.M
        dd.SIDE_CARD_W, dd.SIDE_CARD_H = layout.CARD_W, layout.CARD_H
        dd.setContext, dd.draw = noop, noop
        mods["ui.character.detail.CharacterDetailDraw"] = dd
        c.detailDraw = dd
        c.detail = actual("ui.character.detail.CharacterDetail")
        c.detail.setContext({ getHeroRoster = function() return c.roster end })
        local realOpen, realReceipt = c.detail.open, tm.notifyCharacterDetailOpened
        c.detail.open = function(id, tab)
            c.opens[#c.opens + 1] = { heroId = id, tab = tab }
            return realOpen(id, tab)
        end
        tm.notifyCharacterDetailOpened = function(entrySource, id)
            local result = realReceipt(entrySource, id)
            c.receipts[#c.receipts + 1] = { source = entrySource, heroId = id, result = result }
            return result
        end
        c.draw = actual("ui.character.panel.CharacterPanelDraw2")
        local draw = c.draw
        draw.setContext({ getTeamSlots = function() return c.teams[c.activeTeam].slots end,
            getHeroRoster = function() return c.roster end, getSlotPowerCache = function() return {} end,
            getRosterPowerCache = function() return {} end, getDragState = function() return c.drag end,
            getSelectSlotState = function() return c.select end, getHeroDeployTeams = function() return {} end,
            getUpgradeBadgeCache = function() return {} end, getActiveTeamIdx = function() return c.activeTeam end,
            getUnlockedTeamCount = function() return c.unlocked end, getTeams = function() return c.teams end,
            getTeamPowerCaches = function() return {} end })
        local rosterEnv = setmetatable({ Draw = draw, DESIGN_W = 1080, DESIGN_H = 2400,
            ROW1_CY = draw.ROW1_CY, ROW_SPACING = draw.ROW_SPACING, MAX_PER_ROW = draw.MAX_PER_ROW,
            SCROLL_TOP = draw.SCROLL_TOP, SCROLL_BOTTOM = draw.SCROLL_BOTTOM, heroRoster = c.roster, scrollY = 0 }, { __index = e })
        local rosterHit = compile(section("ui/character/panel/CharacterPanel.lua", "local function hitTestRosterCard", "\n-- heroes 推送可能原地修改共享表。")
            .. "\nreturn hitTestRosterCard", "CharacterPanel roster hit", rosterEnv)
        c.input = actual("ui.character.panel.CharacterInput").bind({ CharacterDetail = c.detail, Draw = draw, CharacterPanel = panel,
            hitTestRosterCard = function(x, y) rosterEnv.heroRoster, rosterEnv.scrollY = c.roster, c.scroll; return rosterHit(x, y) end,
            getTeamSlots = function() return c.teams[c.activeTeam].slots end, getSlotPowerCache = function() return {} end,
            getDragState = function() return c.drag end, getSelectSlotState = function() return c.select end,
            getTeams = function() return c.teams end, getTeamPowerCaches = function() return {} end,
            getHeroRoster = function() return c.roster end, getShardMap = function() return {} end,
            getActiveTeamIdx = function() return c.activeTeam end, getOnTeamChanged = function() return nil end,
            deployHeroToSlot = function() error("unexpected deploy") end, rebuildRoster = noop, refreshPowerCache = noop,
            refreshNavBadge = noop, isHeroDeployed = function() return false end,
            isInScrollArea = function(_, y) return y >= draw.SCROLL_TOP + draw.CONTENT_SHIFT_Y end,
            clampScroll = noop, getScroll = function() return c.scroll end, setScroll = function(v) c.scroll = v end,
            getIsDragging = function() return c.scrolling end, setIsDragging = function(v) c.scrolling = v end,
            getDragLastY = function() return c.dragY end, setDragLastY = function(v) c.dragY = v end,
            getDragDeltaY = function() return c.deltaY end, setDragDeltaY = function(v) c.deltaY = v end,
            setScrollVelocity = noop, SCROLL_WHEEL_STEP = 60, HC = mods["config.HeroConfig"] })
        local tri = { init = noop, isOpen = function() return c.triEnv.isOpen_ end, open = function() c.triEnv.isOpen_ = true end }
        mods["ui.battle.tri.BattleTriPage"] = tri
        c.tri = tri
        local be = setmetatable({ BattleTriPage = tri, BattleLayout = layout, BattleCombatAnim = combatAnim,
            COL_COUNT = 3, drivers = {},
            isOpen_ = true, region = { w = width, h = height }, ExpTable = mods["config.ExpTable"],
            ClientDispatcher = { get = c.store.Get }, TerminalConfirmDialog = mods["ui.battle.popup.TerminalConfirmDialog"],
            SweepDialog = mods["ui.battle.stage.SweepDialog"], DamageStatsPanel = mods["ui.battle.popup.DamageStatsPanel"],
            StageSelectDialog = mods["ui.battle.stage.StageSelectDialog"], RewardPopup = mods["ui.hud.popup.RewardPopup"],
            EquipmentBag = mods["ui.character.equip.EquipmentBag"], StageConfig = { isResourceStage = function() return false end },
            SoundToggle = { handleButtonInput = noop }, dialogToDesign = function() error("unexpected dialog route") end }, { __index = e })
        c.triEnv = be
        mods["ui.battle.scene.BattleScene"] = { isSpeedButtonVisible = function() return false end }
        compile(section("ui/battle/tri/BattleTriPage.lua", "local PLATE_AR =", "--- [三队并行] 行内矩形")
            .. "\nreturn { interior = interiorRect, visit = visitAllyCards }", "BattleTriPage complete shared helpers", be)
        -- Preserve helpers as upvalues for BOTH exact production fragments in one compilation.
        local shared = section("ui/battle/tri/BattleTriPage.lua", "local PLATE_AR =", "--- [三队并行] 行内矩形")
        local drawHead = section("ui/battle/tri/BattleTriPage.lua", "function BattleTriPage.draw(vg, logicalW, logicalH)", "    -- 统一战斗缩放:") .. "\nend\n"
        local inputBody = section("ui/battle/tri/BattleTriPage.lua", "function BattleTriPage.handleInput(wx, wy)", "\n---@param wx number\n---@param wy number\n---@return boolean\nfunction BattleTriPage.handleDragBegin")
        local stageGetter = section("ui/battle/tri/BattleTriPage.lua", "function BattleTriPage.getTeamStageId(teamIdx)", "--- 切换某队关卡")
        c.cardHelpers = compile(shared .. "\n" .. drawHead .. "\n" .. stageGetter .. "\n" .. inputBody
            .. "\nreturn { interior = interiorRect, visit = visitAllyCards }", "BattleTriPage production draw hotspot + full input", be)
        c.recovery = actual("ui.tutorial.TutorialPageRecovery")
        local pe = setmetatable({ TutorialManager = tm, Viewport = mods["core.Viewport"],
            ScenarioDialogue = mods["ui.story.ScenarioDialogue"], LetterIntro = mods["ui.story.gate.LetterIntro"],
            IntroCutscene = mods["ui.story.gate.IntroCutscene"], DarkTitleScreen = mods["ui.story.gate.DarkTitleScreenGate"],
            DungeonBattleScene = mods["ui.dungeon.DungeonBattleScene"], TowerBattleScene = mods["ui.tower.TowerBattleScene"],
            BottomNav = mods["ui.hud.BottomNav"], BattleTriPage = tri,
            logicalW = function() return c.width end, logicalH = function() return c.height end,
            DESIGN_W = function() return 1080 end, DESIGN_H = function() return 2400 end,
            vg = function() return {} end, applyFrame = noop }, { __index = e })
        c.project = compile(section("boot/StandaloneHorizon.lua", "local function HorizonDrawTutorialOverlay()", "\n--- [弹窗聚焦]")
            .. "\nreturn HorizonDrawTutorialOverlay", "Horizon actual screen/right projection", pe)
        c.start = function(group, saved)
            c.detail.forceClose()
            c.receipts, c.opens, c.saves, c.frames = {}, {}, {}, {}
            c.memory.session.tutorialProgress = saved or { version = 1, completed = {}, queue = {} }
            tm.init({}, c.store, function(progress) c.saves[#c.saves + 1] = copy(progress); c.memory.session.tutorialProgress = copy(progress) end)
            tm.update(0)
            if not saved then tm.startGroup(group) end
            tm.update(0.01)
            tm.update(0.46)
        end
        c.renderAvatar = function()
            tm.clearHotspots(); c.frames = {}
            draw.draw({}, c.scroll, false)
            local vp = mods["core.Viewport"]
            local scale = c.height / vp.BASE_H
            vp.note("right", c.width - vp.PW * scale - vp.PANELS.right.bx * scale, 0, scale)
            c.project()
        end
        c.renderBattle = function()
            for _, drv in pairs(be.drivers) do
                if not drv.combatState then drv.combatState = { cardAnims = {} } end
            end
            tm.clearHotspots(); tri.draw({}, c.width, c.height); c.project()
        end
        c.toScreen = function(hs)
            if hs.panel == "screen" then return hs.cx, hs.cy end
            local vp = mods["core.Viewport"]
            local note, p = vp.getNote(hs.panel), vp.PANELS[hs.panel]
            return note.ox + p.bx * note.s + hs.cx * (note.scaleX or note.s * vp.DS),
                note.oy + p.by * note.s + hs.cy * note.s * vp.DS
        end
        return c
    end
    local ok, err = pcall(function()
        for _, size in ipairs({ { 1920, 1080 }, { 1280, 800 } }) do
            local width, height = size[1], size[2]
            local prefix = width .. "x" .. height .. " "
            for _, group in ipairs({ 1, 2 }) do
                runCase(prefix .. "group=" .. group .. " real entry/open/equip/receipt", function()
                    local c = newContext(width, height)
                    -- Slot 1 is dead in battle; compacted allies starts at hero2, roster starts at hero3.
                    c.triEnv.drivers = { { stageId = 101, allies = { { heroId = 2, hp = 100 }, { heroId = 3, hp = 100 } } } }
                    c.start(group)
                    if group == 1 then c.renderBattle() else c.renderAvatar() end
                    local tm, hs = c.tm, c.tm.getCurrentHotspot()
                    check(hs ~= nil, "real producer registered entry hotspot")
                    eq(hs.panel, group == 1 and "screen" or "right", "entry coordinate domain")
                    local target = group == 1 and 2 or 1
                    eq(hs.heroId, target, "hotspot selects actual card/avatar, not roster[1]")
                    local x, y = c.toScreen(hs)
                    check(x >= 0 and x <= width and y >= 0 and y <= height, "projected entry inside real screen")
                    check(tm.canPointerStart(x, y), "screen projected target down allowed")
                    check(not tm.canPointerStart(x + hs.w * (group == 1 and 1 or height / 2400), y), "outside target blocked")
                    eq(tm.getProgress().step, 1, "down did not advance")
                    eq(tm.handleScreenClick(x, y), false, "target click forwarded to actual input")
                    eq(tm.getProgress().step, 1, "hotspot click cannot substitute successful open")
                    for _, event in ipairs({ "character_detail_opened", "click_highlight", "equipment_equipped" }) do tm.notifyEvent(event) end
                    eq(tm.getProgress().step, 1, "generic notifyEvent cannot bypass entry")
                    local before = #c.saves
                    if group == 1 then c.tri.handleInput(x, y) else c.input.handleInput(hs.cx, hs.cy) end
                    eq(#c.opens, 1, "real input open exactly once")
                    eq(c.opens[1].heroId, target, "input actual hero")
                    check(c.detail.isOpen() and c.detail.isEquipTab(), "real CharacterDetail open+equip")
                    eq(c.detail.getHeroId(), target, "real detail hero readback")
                    eq(#c.receipts, 1, "input source receipt exactly once")
                    eq(c.receipts[1].source, group == 1 and "battle" or "avatar", "production receipt source")
                    eq(c.receipts[1].heroId, target, "production receipt hero")
                    check(c.receipts[1].result, "real manager accepts verified receipt")
                    eq(tm.getProgress().step, 2, "verified open advances once")
                    eq(#c.saves, before + 1, "verified open saves once")
                    eq(tm.getEquipmentHeroId(), target, "runtime equipment target pinned to clicked hero")
                    check(not tm.notifyCharacterDetailOpened(group == 1 and "battle" or "avatar", target), "duplicate receipt rejected")
                    eq(#c.saves, before + 1, "duplicate does not persist")
                    c.detail.forceClose()
                    tm.update(0.01)
                    eq(c.detail.getHeroId(), target, "real Recovery reopens clicked hero, not first deployed/roster")
                    eq(c.warehouse.heroId, target, "warehouse same clicked hero")
                    check(c.detail.isEquipTab(), "recovered real equip tab")
                    local allowed = { version = true, completed = true, queue = true, group = true, step = true, newHeroId = true }
                    for _, saved in ipairs(c.saves) do
                        for key in pairs(saved) do check(allowed[key], "no new persisted field " .. key) end
                    end
                    eq(c.actions, 0, "entry/recovery never dispatch action")
                end)
            end
            runCase(prefix .. "battle actual helper geometry + dead/compact/locked/no-target", function()
                local c = newContext(width, height)
                c.start(1)
                local dead = { heroId = 1, hp = 0 }
                local fallen = { heroId = 2, hp = 100, _fallen = true }
                local battleAllies = {} ---@type table[]
                battleAllies[1], battleAllies[2], battleAllies[3] = dead, fallen, { heroId = 3, hp = 100 }
                c.triEnv.drivers = { { stageId = 101, allies = battleAllies },
                    { stageId = 101, allies = { { heroId = 2, hp = 100 } } } }
                c.renderBattle()
                local hs = assert(c.tm.getCurrentHotspot(), "live battle card hotspot missing")
                eq(hs.heroId, 3, "dead/fallen skipped without pretending array index is team slot")
                local selected = {}
                c.cardHelpers.visit(width, height, 1, function(unit, row, index, cx, cy, w, h)
                    selected[#selected + 1] = { hero = unit.heroId, row = row, index = index, cx = cx, cy = cy, w = w, h = h }
                end)
                eq(#selected, 1, "shared helper excludes dead/fallen and locked line")
                eq(selected[1].index, 3, "uncompacted drawing index preserved")
                near(hs.cx, selected[1].cx, "registration/shared input helper x")
                near(hs.cy, selected[1].cy, "registration/shared input helper y")
                near(hs.w, selected[1].w, "actual card width")
                local ix, iy, iw, ih = c.cardHelpers.interior(1, width, height)
                check(hs.cx - hs.w / 2 >= ix and hs.cx + hs.w / 2 <= ix + iw
                    and hs.cy - hs.h / 2 >= iy and hs.cy + hs.h / 2 <= iy + ih, "fully contained production card hotspot")
                c.tri.handleInput(0, height)
                eq(#c.opens, 0, "blank not a card open")
                c.triEnv.drivers[1].allies = { dead, fallen }
                c.renderBattle(); eq(c.tm.getCurrentHotspot(), nil, "all dead no hotspot")
                c.triEnv.drivers[1].allies = {}
                c.renderBattle(); eq(c.tm.getCurrentHotspot(), nil, "empty team no hotspot despite row2 hero")
                c.unlocked = 0
                c.triEnv.drivers[1].allies = { { heroId = 3, hp = 100 } }
                c.renderBattle(); eq(c.tm.getCurrentHotspot(), nil, "locked team no battle hotspot")
                c.unlocked = 1; c.triEnv.terminalRaid = {}
                c.renderBattle(); eq(c.tm.getCurrentHotspot(), nil, "terminal raid no ordinary entry hotspot")
            end)
            runCase(prefix .. "entry pointer button and immutable press identity", function()
                for _, group in ipairs({ 1, 2 }) do
                    local c = newContext(width, height)
                    c.triEnv.drivers = { { stageId = 101, allies = { { heroId = 2, hp = 100 } } } }
                    c.start(group)
                    local function render() if group == 1 then c.renderBattle() else c.renderAvatar() end end
                    render()
                    local tm, original = c.tm, copy(assert(c.tm.getCurrentHotspot(), "press target missing"))
                    local x, y = c.toScreen(original)
                    check(tm.canPointerStart(x, y, MOUSEB_LEFT), "entry left down remains allowed")
                    check(not tm.canPointerStart(x, y, MOUSEB_RIGHT), "entry right down cannot become left-open shortcut")
                    check(not tm.canPointerStart(x, y, MOUSEB_MIDDLE), "entry middle down rejected")
                    local token = assert(tm.beginDetailEntryPress(), "entry down identity token missing")
                    eq(token.heroId, original.heroId, "down token bound hero")
                    eq(token.source, group == 1 and "battle" or "avatar", "down token bound source")
                    check(tm.isDetailEntryPressValid(token), "same source/hero initial token valid")
                    render()
                    check(tm.isDetailEntryPressValid(token), "normal next-frame hotspot rebuild same identity valid")
                    if group == 1 then c.triEnv.drivers[1].allies[1].heroId = 3
                    else c.teams[1].slots[1].heroId = 3 end
                    render()
                    check(not tm.isDetailEntryPressValid(token) and token.invalid, "hero changed before up invalidates old press permanently")
                    if group == 1 then c.triEnv.drivers[1].allies[1].heroId = original.heroId
                    else c.teams[1].slots[1].heroId = original.heroId end
                    render()
                    check(not tm.isDetailEntryPressValid(token), "ABA hero restore cannot resurrect old down")
                    token = assert(tm.beginDetailEntryPress())
                    tm.clearHotspots(); c.project()
                    check(not tm.isDetailEntryPressValid(token), "missing visible hotspot cancels pending entry")
                    render(); check(not tm.isDetailEntryPressValid(token), "hotspot recovery not old press recovery")
                    token = assert(tm.beginDetailEntryPress())
                    tm.cancelDetailEntryPress()
                    check(not tm.isDetailEntryPressValid(token), "explicit drag cancel leaves old token invalid")
                    token = assert(tm.beginDetailEntryPress())
                    c.modules["ui.hud.popup.RewardPopup"].isOpen = function() return true end
                    tm.update(0.01)
                    check(not tm.isDetailEntryPressValid(token), "high-priority reward breaks pending press")
                    c.modules["ui.hud.popup.RewardPopup"].isOpen = function() return false end
                    render(); check(not tm.isDetailEntryPressValid(token), "reward closes but old down stays invalid")
                    token = assert(tm.beginDetailEntryPress())
                    tm.skipCurrentGroup()
                    check(not tm.isDetailEntryPressValid(token), "finish/reset invalidates press")
                    eq(#c.opens, 0, "button/identity guard probes do not open real detail")
                    eq(c.actions, 0, "guards do not dispatch action")
                end
                -- Non-entry equipment stage must keep its legacy right-click shortcut.
                local c = newContext(width, height)
                c.triEnv.drivers = { { stageId = 101, allies = { { heroId = 2, hp = 100 } } } }
                c.start(1); c.renderBattle()
                local hs = assert(c.tm.getCurrentHotspot())
                c.tri.handleInput(hs.cx, hs.cy); c.tm.update(0.01); c.tm.update(0.46)
                c.tm.registerHotspot("equip_slot_weapon", 325, 598, 160, 160, "screen")
                c.project(); c.tm.handleScreenClick(325, 598)
                c.tm.update(0.01); c.tm.update(0.46)
                c.tm.registerHotspot("equip_item_gifted", 500, 500, 100, 100, "screen")
                c.project()
                eq(c.tm.getCurrentHighlight(), "equip_item_gifted", "real equipment event stage reached")
                check(c.tm.canPointerStart(500, 500, MOUSEB_RIGHT), "non-entry gifted right-click remains allowed")
                eq(c.tm.beginDetailEntryPress(), nil, "non-entry stage does not create entry identity")
            end)
            runCase(prefix .. "battle real animation visibility and anchor intersection", function()
                local c = newContext(width, height)
                c.start(1)
                local unit = { heroId = 2, hp = 100, atkProgress = 0 }
                local combatState = { cardAnims = {} }
                c.triEnv.drivers = { { stageId = 101, allies = { unit }, combatState = combatState } }
                c.renderBattle()
                local anchor = copy(assert(c.tm.getCurrentHotspot(), "idle hotspot missing"))
                for _, animState in ipairs({ "entering", "reviving", "dying", "gone", "march", "advance" }) do
                    c.combatAnim.set(combatState, unit, { state = animState, timer = 0.06, lungeDir = -1 })
                    local before = copy(combatState.cardAnims[unit])
                    c.renderBattle()
                    eq(c.tm.getCurrentHotspot(), nil, "transitional/invisible animation has no target " .. animState)
                    check(same(before, combatState.cardAnims[unit]), "hotspot does not tick/mutate animation " .. animState)
                end
                c.combatAnim.set(combatState, unit, { state = "lunge", timer = c.combatAnim.LUNGE_DURATION * 0.5,
                    lungeDir = -1, isAlly = true, isRanged = false })
                c.renderBattle()
                local lunge = assert(c.tm.getCurrentHotspot(), "visible lunge anchor intersection missing")
                check(lunge.w < anchor.w and lunge.h < anchor.h, "real lunge and arc reduce intersection rather than reusing idle rectangle")
                -- Two center/extent round trips can move an equal edge by ~1e-14 at 1920px.
                -- Limit numerical slack to 1e-9 logical px; this is not visible clipping tolerance.
                local leftDelta = (lunge.cx - lunge.w / 2) - (anchor.cx - anchor.w / 2)
                local rightDelta = (lunge.cx + lunge.w / 2) - (anchor.cx + anchor.w / 2)
                local topDelta = (lunge.cy - lunge.h / 2) - (anchor.cy - anchor.h / 2)
                local bottomDelta = (lunge.cy + lunge.h / 2) - (anchor.cy + anchor.h / 2)
                print(TAG .. string.format("edge residual %dx%d L=%.17g R=%.17g T=%.17g B=%.17g",
                    width, height, leftDelta, rightDelta, topDelta, bottomDelta))
                check(leftDelta >= -1e-9 and rightDelta <= 1e-9
                    and topDelta >= -1e-9 and bottomDelta <= 1e-9,
                    "moving visible target remains inside unchanged ordinary click anchor")
                c.tri.handleInput(lunge.cx, lunge.cy)
                eq(c.detail.getHeroId(), 2, "original full input opens animation-intersection card")
                eq(c.tm.getEquipmentHeroId(), 2, "animation target actual receipt pinned hero")
                c.start(1)
                c.combatAnim.clear(combatState, unit)
                unit.atkProgress = 0.9
                c.renderBattle()
                local charge = assert(c.tm.getCurrentHotspot(), "charge target missing")
                check(charge.w < anchor.w and charge.h < anchor.h, "real charge/arc makes smaller visible target")
                c.combatAnim.clear(combatState, unit); unit.atkProgress = 0
                c.renderBattle()
                local restored = assert(c.tm.getCurrentHotspot(), "idle restored hotspot missing")
                near(restored.cx, anchor.cx, "idle restore center x")
                near(restored.w, anchor.w, "idle restore full anchor width")
            end)
            runCase(prefix .. "avatar real draw/hit/locked/drag/new-roster", function()
                local c = newContext(width, height)
                c.teams[1].slots[1] = { state = "empty" }
                c.start(2); c.renderAvatar()
                local hs = assert(c.tm.getCurrentHotspot(), "avatar hotspot missing")
                eq(hs.heroId, 2, "first occupied avatar selected when slot1 empty")
                local team, slot = c.draw.hitTestAvatarSlot(hs.cx, hs.cy)
                eq(team, 1, "real avatar hit team")
                eq(slot, 2, "real avatar hit slot")
                c.drag = { active = true, fromTeam = 1, fromSlot = 2, heroId = 2, cx = 0, cy = 0 }
                c.renderAvatar()
                eq(c.tm.getCurrentHotspot().heroId, 3, "dragged source excluded, next actual avatar target")
                c.teams[1].slots[3] = { state = "empty" }
                c.renderAvatar(); eq(c.tm.getCurrentHotspot(), nil, "only dragged occupied avatar no hotspot")
                c.drag = { active = false, moved = false }
                local ax, ay = c.draw.avatarCenter(1, 2)
                ax, ay = ax + c.draw.CONTENT_SHIFT_X, ay + c.draw.CONTENT_SHIFT_Y
                local opensBeforeDrag = #c.opens
                check(c.input.handleDragBegin(ax, ay), "real avatar drag begin captures source")
                c.input.handleDragMove(-500, -500)
                check(c.drag.active and c.drag.moved and c.drag.fromTeam == 1 and c.drag.fromSlot == 2,
                    "real Input move crosses threshold with original avatar source")
                c.renderAvatar(); eq(c.tm.getCurrentHotspot(), nil, "real drag makes source hotspot disappear")
                c.input.handleDragEnd(-500, -500)
                c.input.handleInput(-500, -500)
                check(not c.drag.active and c.drag.heroId == nil and c.drag.fromSlot == nil,
                    "real outside drop cancels and clears source state")
                eq(c.teams[1].slots[2].heroId, 2, "outside drag does not unequip or move avatar")
                eq(#c.opens, opensBeforeDrag, "outside drag does not open detail")
                eq(c.tm.getProgress().step, 1, "outside drag does not complete entry")
                c.renderAvatar(); eq(c.tm.getCurrentHotspot().heroId, 2, "cancelled drag restores actual source hotspot")
                c.drag = { active = false }
                c.unlocked = 0
                c.renderAvatar(); eq(c.tm.getCurrentHotspot(), nil, "locked avatars no hotspot")
                for _, frame in ipairs(c.frames) do
                    if frame.state == "locked" then
                        eq(c.draw.hitTestAvatarSlot(frame.cx + c.draw.CONTENT_SHIFT_X, frame.cy + c.draw.CONTENT_SHIFT_Y), nil,
                            "locked frame not clickable through real Draw hit")
                    end
                end
                c.unlocked = 1
                c.teams[1].slots = { { state = "empty" }, { state = "empty" }, { state = "empty" }, { state = "empty" } }
                c.renderAvatar(); eq(c.tm.getCurrentHotspot(), nil, "roster does not counterfeit avatar entry")
                c.tm.skipCurrentGroup(); c.tm.update(0.3)
                c.teams[2].slots[1] = { state = "empty" }
                c.tm.setNewHeroId(3); c.tm.startGroup(9); c.tm.update(0.01); c.tm.update(0.46)
                c.renderAvatar()
                local nhs = assert(c.tm.getCurrentHotspot(), "new hero roster hotspot lost")
                eq(c.tm.getCurrentHighlight(), "character_new_hero", "new hero teaching preserved")
                eq(nhs.panel, "right", "new hero roster domain preserved")
                local before = #c.opens
                c.input.handleInput(nhs.cx, nhs.cy)
                eq(#c.opens, before, "new hero roster click still guarded, must drag")
            end)
        end
        for _, group in ipairs({ 1, 2 }) do
            runCase("group=" .. group .. " forged source/hero/closed/closing/attr/settle receipts", function()
                local c = newContext(1920, 1080)
                c.triEnv.drivers = { { stageId = 101, allies = { { heroId = 2, hp = 100 } } } }
                c.start(group)
                if group == 1 then c.renderBattle() else c.renderAvatar() end
                local hs = assert(c.tm.getCurrentHotspot(), "producer hotspot missing")
                local target, entry = hs.heroId, group == 1 and "battle" or "avatar"
                local function rejected(label, entrySource, id)
                    local before = #c.saves
                    check(not c.tm.notifyCharacterDetailOpened(entrySource, id), label)
                    eq(c.tm.getProgress().step, 1, label .. " keeps entry step")
                    eq(#c.saves, before, label .. " no persist")
                end
                rejected("closed", entry, target)
                rejected("nil hero", entry, nil)
                rejected("zero hero", entry, 0)
                rejected("negative hero", entry, -1)
                rejected("fractional hero", entry, 1.5)
                rejected("invalid string hero", entry, "not-a-hero")
                rejected("NaN hero", entry, 0 / 0)
                rejected("infinite hero", entry, math.huge)
                c.detail.open(target, "equip")
                rejected("wrong source", group == 1 and "avatar" or "battle", target)
                rejected("unknown source", "roster", target)
                rejected("wrong receipt hero", entry, target == 1 and 2 or 1)
                c.detail.open(target == 1 and 2 or 1, "equip")
                rejected("wrong actual detail hero", entry, target)
                c.detail.open(target, "attr")
                rejected("actual attr tab", entry, target)
                c.detail.open(target, "equip"); c.detail.close()
                check(c.detail.isOpen() and not c.detail.isEquipTab() and c.detail.getHeroId() == nil, "real closing state readback")
                rejected("actual closing", entry, target)
                c.detail.forceClose(); rejected("force closed", entry, target)
                c.tm.clearHotspots(); c.detail.open(target, "equip")
                rejected("no registered target", entry, target)
                c.detail.forceClose()
                c.tm.init({}, c.store, function(progress) c.saves[#c.saves + 1] = copy(progress) end)
                c.tm.startGroup(group); c.tm.update(0.01) -- real recovery changed -> settle remaining
                if group == 1 then c.renderBattle() else c.renderAvatar() end
                c.detail.open(target, "equip")
                rejected("page settle still active", entry, target)
            end)
            runCase("group=" .. group .. " JSON cold restore resets entry without target persistence", function()
                local c = newContext(1280, 800)
                local saved = { version = 1, completed = {}, queue = { 4 }, group = group, step = 2, newHeroId = 3 }
                local frozen = copy(saved)
                local cold = cjson.decode(cjson.encode(saved))
                c.start(group, cold)
                eq(c.tm.getCurrentGroup(), group, "cold restores same active group")
                eq(c.tm.getProgress().step, 1, "cold restore step1 rather than unopened equip step")
                eq(c.tm.getEquipmentHeroId(), nil, "runtime-only previous clicked target not persisted")
                check(not c.detail.isOpen(), "cold entry does not automatically fake detail opening")
                check(same(saved, frozen), "input saved table untouched")
                eq(#c.tm.getProgress().queue, 1, "pending queue preserved")
                eq(c.tm.getProgress().queue[1], 4, "pending queue identity preserved")
                local expected = { version = 1, completed = {}, queue = { 4 }, group = group, step = 1, newHeroId = 3 }
                check(same(c.tm.getProgress(), expected), "cold snapshot exact existing schema only")
                eq(c.actions, 0, "cold restore no action/reward")
            end)
        end
        runCase("resource execution provenance", function()
            for _, path in ipairs({ "systems/TutorialManager.lua", "ui/tutorial/TutorialPageRecovery.lua",
                "ui/character/detail/CharacterDetail.lua", "ui/character/panel/CharacterInput.lua",
                "ui/character/panel/CharacterPanelDraw2.lua", "ui/battle/tri/BattleTriPage.lua", "boot/StandaloneHorizon.lua" }) do
                check(sources[path] ~= nil, "real cache resource read " .. path)
            end
            check(#reads >= 12, "resource-loaded dependencies executed; not copied event strings")
        end)
    end)
    if not ok then
        failures = failures + 1
        local message = TAG .. "FAIL Start exception " .. tostring(err)
        print(message); log:Write(LOG_ERROR, message)
    end
    if failures == 0 then print(TAG .. "ALL PASS: " .. cases .. " cases, " .. assertions .. " assertions")
    else print(TAG .. "FAIL: " .. failures .. " cases failed, " .. assertions .. " assertions") end
    engine:Exit()
end
