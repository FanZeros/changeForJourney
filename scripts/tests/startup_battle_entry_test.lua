-- 入场准备回归：真实Standalone闭包/完整HandleUpdate、Tri/Driver/EnemySpawn/Draw；
-- 显式外围spy隔离GPU、持久化和攻击。只读声明源码，不读写玩家档、不运行main。
-- Horizon只抽取原文完整三行分支（含实际Tri.draw之后的ready标记），不复制门控逻辑。
local TAG = "[startup_battle_entry_test]"
local assertions, failures, cases = 0, 0, 0
local function check(value, label)
    assertions = assertions + 1
    if not value then failures = failures + 1 end
    print(TAG .. (value and " PASS " or " FAIL ") .. label)
end
local function noop() end
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}; seen[value] = result
    for key, item in pairs(value) do result[key] = copy(item, seen) end
    return result
end
local function same(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for key, value in pairs(a) do if not same(value, b[key], seen) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function source(path)
    local file = assert(cache:GetFile(path), "missing declared source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function section(text, first, last)
    local a = assert(text:find(first, 1, true), "missing source anchor " .. first)
    assert(not text:find(first, a + #first, true), "ambiguous source anchor " .. first)
    local b = assert(text:find(last, a + #first, true), "missing end anchor " .. last)
    return text:sub(a, b - 1)
end
-- 仅隔离副本内配置夹具；被测函数仍为实际生产闭包，没有改写函数体。
local function upvalue(fn, name)
    for index = 1, 200 do
        local key, value = debug.getupvalue(fn, index)
        if not key then break end
        if key == name then return value, index end
    end
    error("missing real closure upvalue " .. name)
end
local function setvalue(fn, name, value)
    local _, index = upvalue(fn, name)
    debug.setupvalue(fn, index, value)
end
local function passive()
    return { init = noop, initImages = noop, draw = noop, drawPage = noop, drawButton = noop,
        drawUnderlay = noop, update = noop,
        destroy = noop, shutdown = noop, close = noop, forceClose = noop, hide = noop, reset = noop,
        resetToDefault = noop, isOpen = function() return false end,
        isActive = function() return false end, isVisible = function() return false end }
end

local function fixture(options)
    options = options or {}
    local modules = { battle = { currentStageId = options.stage or 201, maxStageId = options.maxStage or 2001,
        teamStageIds = { ["1"] = options.stage or 201, ["2"] = 305, ["3"] = 401 },
        clearedStages = { ["905"] = true, ["1905"] = true }, battleMode = "idle" },
        session = { lastOnlineTime = options.newSave and 0 or 1699999940,
            firstLoginTime = 1699999800, introCompleted = not options.newSave },
        player = { level = 100 }, equipment = { inventory = {}, equipped = {} } }
    if options.maxStage == 101 then modules.battle.clearedStages = {} end
    local counts = { starts = 0, updates = 0, images = 0, pumps = 0, calc = 0,
        shown = 0, flush = 0, reconcile = 0, checked = 0, starter = 0, random = 0,
        mutations = 0, claims = 0, readonly = 0, tick = 0, firstStage = 0 }
    local trace, drivers, loaded, loading, sources, images, cardHandles = {}, {}, {}, {}, {}, {}, {}
    local clock = { elapsedTime = 100 }
    local controls = { imageFailure = nil, failPrepare = false, failClaim = false, failFirstStage = false,
        pending = false, letterOpen = false, titleOpen = true, titleFading = false,
        viewportOpen = false, titleReady = false, shown = nil, yieldEvery = true,
        dialogueOpen = false, dialogue = nil }
    local mounts = {}
    local mocks = {}
    local env = setmetatable({}, { __index = _G })
    env._G, env.time = env, clock
    local function record(name) trace[#trace + 1] = name end
    local function forbidden(label)
        return function() counts.mutations = counts.mutations + 1; error("FORBIDDEN_" .. label) end
    end
    env.File, env.io = forbidden("PLAYER_FILE"), nil
    env.math = setmetatable({ random = function() counts.random = counts.random + 1; error("FORBIDDEN_RANDOM") end,
        randomseed = forbidden("RANDOMSEED") }, { __index = math })
    env.os = setmetatable({ time = function() return 1700000000 end }, { __index = os })
    local nvgNoops = { "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFillPaint", "nvgFill",
        "nvgFillColor", "nvgSave", "nvgRestore", "nvgTranslate", "nvgRotate", "nvgScale",
        "nvgCircle", "nvgStroke", "nvgStrokeColor", "nvgStrokeWidth", "nvgMoveTo", "nvgLineTo",
        "nvgScissor", "nvgIntersectScissor", "nvgResetScissor", "nvgFontFace", "nvgFontSize",
        "nvgTextAlign", "nvgText", "nvgTextBox", "nvgShapeAntiAlias", "nvgGlobalAlpha",
        "nvgResetTransform", "nvgDelete", "nvgDeleteImage" }
    for _, name in ipairs(nvgNoops) do env[name] = noop end
    env.nvgRGBA = function(...) return { ... } end
    env.nvgRadialGradient, env.nvgLinearGradient = function() return {} end, function() return {} end
    env.nvgTextBounds = function(_, _, _, text) return #text * 8 end
    env.nvgImageSize = function() return 768, 1365 end
    env.nvgImagePattern, env.nvgImagePatternTinted = function() return {} end, function() return {} end
    env.nvgCreateImage = function(vg, path, flags)
        counts.images = counts.images + 1
        record("image:" .. path)
        images[#images + 1] = { context = vg, path = path, flags = flags }
        if controls.imageFailure == path then return -1 end
        return counts.images
    end
    env.nvgCreate, env.nvgCreateFont = function() return {} end, function() return 1 end
    env.SubscribeToEvent = noop
    env.HandleEquipmentHoverTickHorizon = noop
    env.H_AUTO_OPEN_TRI, env.H_AUTO_TAB, env.H_AUTO_OPEN_PANEL = false, nil, nil
    env.graphics = { GetWidth = function() return 1920 end, GetHeight = function() return 1080 end,
        GetDPR = function() return 1 end }
    local scene = { CreateComponent = function() return {} end }
    scene.CreateChild = function() return { CreateComponent = function() return {} end } end
    env.Scene = function() return scene end
    env.renderer = { SetViewport = noop }
    env.Viewport = { new = function() return {} end }

    local function stateModule(name)
        local default = { name = name, id = "default", ctx = {}, cardAnims = {}, comboQueue = {} }
        local current = default
        local function new(id)
            return { name = name, id = id, ctx = {}, cardAnims = {}, comboQueue = {} }
        end
        local api = { newState = new, newFxState = new, newSemState = new,
            newBattleRefs = new, mount = function(value) current = value or default end,
            mountedState = function() return current end, reset = noop,
            initUnit = noop, initBattle = noop, onBattleStart = noop,
            draw = noop, drawStarGates = noop, setRenderScale = noop,
            setContext = function(value) current.ctx = value end,
            update = forbidden(name .. "_BUSINESS_UPDATE"), performAttack = forbidden("ATTACK"),
            dealDamageToUnit = forbidden("DAMAGE"), updateComboQueue = forbidden("COMBO") }
        mounts[#mounts + 1] = api
        return api
    end
    local Combat = stateModule("combat")
    Combat.playEnterAnims = noop
    Combat.updateCardAnims, Combat.updateFloatingTexts, Combat.updateHitFlashes = noop, noop, noop
    Combat.getCardAnimOffsetY, Combat.getChargeOffsetY, Combat.getCardAnimArcY = function() return 0 end,
        function() return 0 end, function() return 0 end
    Combat.getCardScale, Combat.getTransitionAlpha = function() return 1 end, function() return 1 end
    Combat.getAnimState = function() return "idle" end
    Combat.getHitFlashAlpha, Combat.getHpBuffer = function() return 0 end, function() return 1 end
    Combat.getFloatingTexts = function() return {} end
    Combat.getCardCX, Combat.getCardCY = function() return 300 end, function() return 180 end
    local PS, Effects = stateModule("projectiles"), stateModule("effects")
    PS.preloadBattleEffects = noop
    local TAL, ETS = stateModule("talents"), stateModule("extraTalents")
    local unitsState = {}
    TAL.newUnitStates = function() return {} end
    TAL.mountUnitStates = function(value) unitsState = value end
    TAL.mountedUnitStates = function() return unitsState end
    TAL.reset = function() unitsState = {} end
    TAL.getConquerStacks = function() return 0 end
    TAL.resetEnemyDeath = noop
    ETS.normalize = function(value) return value or {} end
    ETS.applyToAttrs, ETS.drawOrbit, ETS.drawIceStatues = noop, noop, noop
    local Status = stateModule("status")
    Status.getVisuals = function() return {} end
    local Threat, Conditions = stateModule("threat"), stateModule("conditions")
    local statsTeam = 9
    local Stats = { mount = function(team) statsTeam = team end, mountedTeam = function() return statsTeam end }
    mocks["ui.battle.combat.BattleCombat"], mocks["ui.battle.combat.ProjectileSystem"] = Combat, PS
    mocks["ui.battle.combat.BattleEffects"], mocks["systems.TalentManager"] = Effects, TAL
    mocks["systems.ExtraTalentSystem"], mocks["systems.StatusEffectManager"] = ETS, Status
    mocks["systems.ThreatManager"], mocks["systems.RelicConditionHandler"] = Threat, Conditions
    mocks["systems.BattleStats"] = Stats
    mocks["systems.ArtifactRuntime"] = { reset = noop, initBattle = noop, onAllyDeath = forbidden("REVIVE") }
    mocks["systems.CombatFormula"] = {}
    mocks["ui.battle.scene.BattleAllyLifecycle"] = { bind = forbidden("ALLY_PENDING") }
    mocks["systems.DropSystem"] = { captureTeamLuck = function() return 0 end }
    mocks["ui.battle.stage.StageEntryEvents"] = { notify = function(id, team) record("stage:" .. team .. ":" .. id) end,
        retry = noop }
    mocks["ui.church.talent.TalentStarMap"] = { getLitNodeEffects = function() return {} end }
    mocks["systems.TutorialManager"] = { init = noop, update = noop, notifyEvent = noop,
        getCurrentHighlight = function() return nil end, isActive = function() return false end,
        canPlayPendingStory = function() return false end }
    mocks["core.DrawUtil"] = { initShardAssets = noop, drawTextStroke = noop, drawBackSeamBar = noop,
        drawCardImage = function(_, handle) cardHandles[#cardHandles + 1] = handle end }
    mocks["core.I18n"] = { lookup = function(value) return value end, installDrawHook = noop,
        format = string.format }
    mocks["core.GameState"] = { getLevel = function() return 100 end, reset = noop }
    mocks["runtime.ClientDispatcher"] = { get = function(key) return modules[key] end,
        subscribe = noop, notifySubscribers = noop, hasData = function() return false end,
        handleStateUpdate = function(json)
            local input = cjson.decode(json)
            for key, value in pairs(input.modules) do modules[key] = value end
            if input.modules.heroes and loaded["ui.character.panel.CharacterPanel"] then
                loaded["ui.character.panel.CharacterPanel"].setHeroesData(input.modules.heroes)
            end
        end }
    mocks["core.PlayerStore"] = { Get = function(key) return modules[key] end, Init = noop,
        Subscribe = noop, Update = noop }
    local panelDraw = { MAX_SLOTS = 4, MAX_PER_ROW = 5, CARD_W = 198, CARD_H = 351,
        CARD_SPACING = 205, CARD_CY = 300, ROW1_CY = 600, ROW_SPACING = 200,
        NAME_BG_DY = 100, NAME_BG_H = 40, SCROLL_TOP = 450, SCROLL_BOTTOM = 2200,
        SCROLL_LEFT = 0, SCROLL_RIGHT = 1080, DESIGN_W = 1080, ROSTER_BOTTOM_DY = 130,
        getSlotCX = function(index) return index * 205 end, setContext = noop, initImages = noop,
        getSharedImages = function() return {} end, draw = noop, resetPresentation = noop }
    mocks["ui.character.panel.CharacterPanelDraw2"] = panelDraw
    mocks["ui.character.panel.CharacterPower"] = { bind = function(deps)
        return { calcHeroPower = function(id) return tonumber(id) or 0 end,
            applyEquippedItems = function() return nil end,
            getHeroLevel = function(id)
                local own = deps.get("ownedSet")[id]
                return own and own.level or 1
            end,
            refreshPowerCache = noop, refreshNavBadge = noop, updateBadges = noop }
    end }
    for _, name in ipairs({ "CharacterDeploy", "CharacterInput", "CharacterProgress" }) do
        mocks["ui.character.panel." .. name] = { bind = function() return {} end }
    end
    mocks["systems.EquipmentSystem"] = { isInventoryFull = function() return false end }
    mocks["systems.ArtifactBridge"] = { applyToUnit = function() return {} end }
    mocks["systems.LootBoxSystem"] = {}
    local Scene = passive()
    Scene.battleSpeed = 1
    local sceneStage = modules.battle.currentStageId
    Scene.getStageId = function() return sceneStage end
    Scene.getMaxStageId = function() return modules.battle.maxStageId end
    Scene.getClearedStages = function() return modules.battle.clearedStages end
    Scene.cancelTriReincarnation = noop
    Scene.adoptStageProgress = function(id) sceneStage = id end
    Scene.resetToDefault = function() sceneStage = 101 end
    Scene.setAllies, Scene.refreshAllyStats = noop, noop
    Scene.reloadStage = function()
        counts.firstStage = counts.firstStage + 1
        if controls.failFirstStage then error("EXPECTED_FIRST_STAGE_FAILURE") end
    end
    Scene.getAllies, Scene.getEnemies = function() return {} end, function() return {} end
    Scene.pumpBattleCards = function() counts.pumps = counts.pumps + 1; error("FORBIDDEN_BIG_CARD_PUMP") end
    Scene.update = function() counts.tick = counts.tick + 1; error("FORBIDDEN_SINGLE_SCENE_TICK") end
    Scene.isInTerminalTemple, Scene.isSpeedButtonVisible = function() return false end, function() return false end
    mocks["ui.battle.scene.BattleScene"] = Scene
    local offline = passive()
    offline.show = function(data) controls.shown = data; controls.viewportOpen = true
        counts.shown = counts.shown + 1; record("show") end
    offline.isOpen = function() return controls.viewportOpen end
    offline.close = function() controls.viewportOpen = false end
    mocks["ui.hud.popup.OfflineRewardPanel"] = offline
    local Service = { HasPendingRewards = function(uid) assert(uid == 1); return controls.pending end,
        Cleanup = function(uid) assert(uid == 1); controls.pending = false end,
        CalcOnEnter = function(uid)
            assert(uid == 1); counts.calc = counts.calc + 1; record("calc")
            if options.newSave or options.noReward then return nil end
            controls.pending = true
            return { offlineSeconds = 60, maxSeconds = 86400, multiplier = 1.25,
                adventureExp = 11, adventurerExp = 99, heroExpPreview = { { heroId = 1, expGain = 33 } },
                rewards = { { type = "gold", amount = 777 } }, hardCapSeconds = 604800,
                cappedByHardCap = false, tailRatio = 0.1 }
        end }
    mocks["rules.offline.OfflineService"] = Service
    local Save = { SetBattlePage = noop, RestoreData = noop, ApplyBattleProgress = noop, Update = noop,
        Flush = function() counts.flush = counts.flush + 1; record("flush") end,
        ReconcileOfflineBoundary = function() counts.reconcile = counts.reconcile + 1; record("reconcile") end,
        OfflineChecked = function() counts.checked = counts.checked + 1; record("checked") end }
    mocks["boot.StandaloneSave"] = Save
    local title = passive()
    title.isOpen = function() return controls.titleOpen end
    title.isFading = function() return controls.titleFading end
    title.setReady = function(value) controls.titleReady = value end
    title.open, title.reopen = function() controls.titleOpen = true end, function() controls.titleOpen = true end
    mocks["ui.story.gate.DarkTitleScreenGate"] = title
    local letter = passive()
    letter.isOpen = function() return controls.letterOpen end
    letter.start = function(callback) controls.letterOpen = true; controls.letterFinish = callback; record("letter") end
    letter.reset = function() controls.letterOpen = false; controls.letterFinish = nil end
    mocks["ui.story.gate.LetterIntro"] = letter
    mocks["runtime.GameAction"] = { sendAction = function(action)
        if action == "grant_starter_trio" then
            counts.starter = counts.starter + 1; record("starter")
            local roster = {}
            for _, id in ipairs({ 1, 2, 3 }) do roster[tostring(id)] = { level = 1, exp = 0, shards = 0 } end
            modules.heroes = { roster = roster, deployed = { 1, 2, 3, 0 }, teams = {} }
            loaded["ui.character.panel.CharacterPanel"].setHeroesData(modules.heroes)
            return true
        elseif action == "claim_offline_rewards" then
            counts.claims = counts.claims + 1
            if controls.failClaim then return false end
            controls.pending = false
            return true
        end
        error("undeclared action " .. action)
    end }
    mocks["runtime.LocalActionBridge"] = { init = noop }
    mocks["runtime.ClientMessageHandler"] = { resetSessionBridgeState = noop }
    mocks["boot.StandaloneBoot"] = { resetPendingBattleRewards = noop, run = noop }
    mocks["boot.StandaloneHorizon"] = {}
    local rt = {}; mocks["boot.StandaloneRT"] = rt
    for _, name in ipairs({ "ui.hud.TopBar", "ui.hud.BottomNav", "ui.dev.DebugPanel", "ui.dev.CEPanel",
        "ui.character.hero.HeroRosterPanel", "ui.hud.popup.RewardPopup", "ui.town.TownScene",
        "ui.blacksmith.BlacksmithPage", "ui.church.ChurchPage", "ui.church.talent.TalentPage",
        "ui.tavern.TavernPage", "ui.tavern.RecruitAnim", "ui.market.MarketPage", "ui.dungeon.DungeonBattleScene",
        "ui.tower.TowerBattleScene", "ui.tower.TowerBuffPick", "ui.dungeon.DungeonPage",
        "ui.backpack.BackpackPanel", "ui.loot.LootBox", "ui.loot.LootBoxPage", "ui.hud.popup.LevelUpPopup",
        "ui.hud.popup.UpdateNoticePopup", "ui.hud.popup.PlayerInfoPanel", "ui.hud.popup.RedeemCodePanel",
        "ui.story.gate.StartScreen", "ui.battle.stage.SweepDialog", "ui.battle.popup.DamageStatsPanel",
        "ui.battle.stage.StageSelectDialog", "ui.battle.popup.TerminalConfirmDialog", "systems.GameBGM",
        "systems.GameSFX", "ui.fx.SpinePowerUpEffect", "ui.story.gate.IntroCutscene",
        "ui.character.detail.CharacterDetail", "ui.character.equip.EquipmentBag", "ui.story.ScenarioDialogue",
        "core.DarkIcon", "ui.fx.SpineCardEffect", "ui.fx.SpineResultEffect", "ui.fx.DarkEffectSprites",
        "ui.widget.DesignWidgetSurface", "ui.dev.KeyboardShortcuts", "ui.character.hero.HeroScenario",
        "rules.dungeon.DungeonService", "rules.dungeon.DungeonIdleService",
        "ui.widget.SoundToggle", "ui.battle.tri.TerminalRaid", "ui.character.EquipCrossDrag",
        "ui.tower.TowerBuffSidebar" }) do
        if not mocks[name] then mocks[name] = passive() end
    end
    mocks["ui.hud.TopBar"].markAvatarViewed, mocks["ui.hud.TopBar"].setTotalPower = noop, noop
    mocks["ui.hud.BottomNav"].setBadge, mocks["ui.hud.BottomNav"].refreshTownBadge = noop, noop
    mocks["ui.hud.BottomNav"].refreshUnlockState = noop
    mocks["ui.hud.BottomNav"].getSelectedIndex = function() return 3 end
    mocks["ui.hud.BottomNav"].setSelectedIndex = noop
    mocks["ui.dev.CEPanel"].pollHotkey = noop
    mocks["ui.hud.popup.RewardPopup"].clearBattleRewards = noop
    mocks["ui.hud.popup.RewardPopup"].hasPendingBattleRewards = function() return false end
    mocks["ui.hud.popup.RewardPopup"].currentRowTag, mocks["ui.hud.popup.RewardPopup"].currentPanel = function() return nil end,
        function() return nil end
    mocks["ui.hud.popup.RewardPopup"].drawRegion = noop
    mocks["ui.town.TownScene"].preload, mocks["ui.town.TownScene"].setSmithRedDot = noop, noop
    mocks["ui.blacksmith.BlacksmithPage"].setDecomposeRedDot = noop
    mocks["ui.backpack.BackpackPanel"].isLeftMode = function() return true end
    mocks["ui.dungeon.DungeonPage"].isTowerChallengePending = function() return false end
    mocks["ui.character.detail.CharacterDetail"].setContext, mocks["ui.character.detail.CharacterDetail"].markPowerDirty = noop, noop
    mocks["ui.character.detail.CharacterDetail"].hasAnyUpgradeForHero = function() return false end
    mocks["ui.character.detail.CharacterDetail"].hasAwakeningUpgrade = function() return false end
    mocks["systems.GameBGM"].setScene, mocks["systems.GameBGM"].start, mocks["systems.GameBGM"].stop = noop, noop, noop
    mocks["systems.GameSFX"].start, mocks["systems.GameSFX"].stop, mocks["systems.GameSFX"].preload = noop, noop, noop
    mocks["ui.fx.SpinePowerUpEffect"].preload, mocks["ui.fx.SpinePowerUpEffect"].resetSession = noop, noop
    mocks["ui.fx.SpineCardEffect"].stopAll, mocks["ui.fx.SpineResultEffect"].stop = noop, noop
    mocks["ui.character.hero.HeroScenario"].resetAll = noop
    mocks["ui.story.ScenarioDialogue"].isActive = function() return controls.dialogueOpen end
    mocks["ui.story.ScenarioDialogue"].show = function(opts)
        controls.dialogueOpen, controls.dialogue = true, opts
        record("opening:" .. tostring(opts.title))
    end
    mocks["ui.story.ScenarioDialogue"].reset = function()
        controls.dialogueOpen, controls.dialogue = false, nil
    end
    mocks["ui.tutorial.TutorialPageRecovery"] = {
        -- 夹具所有二级菜单关闭；正式nav3三行页已开时左右城镇/主线同时可见。
        getStoryPlace = function()
            local tri = loaded["ui.battle.tri.BattleTriPage"]
            return tri and tri.isOpen() and "battle_town" or "battle"
        end,
        isPendingStoryBlocked = function(place)
            assert(place == "battle" or place == "battle_town"); return false
        end,
    }
    mocks["rules.dungeon.DungeonService"].Cleanup, mocks["rules.dungeon.DungeonIdleService"].Cleanup = noop, noop
    mocks["ui.character.equip.EquipmentBag"].shouldBattleOverlay = function() return false end
    mocks["ui.character.equip.EquipmentBag"].setOverlayRegion = noop
    mocks["ui.dev.CERuntime"] = { installSpeedHook = noop, tick = noop }
    mocks["ui.hud.popup.SettingsPanel"] = { isEffectsEnabled = function() return false end }
    local real = { ["boot.Standalone"] = true, ["boot.StartupQueue"] = true,
        ["systems.StoryPlayer"] = true, ["ui.battle.tri.TerminalReincarnation"] = true,
        ["ui.battle.tri.BattleTriPage"] = true, ["ui.battle.tri.BattleTriDriver"] = true,
        ["ui.battle.tri.BattleEntryPreparation"] = true,
        ["ui.battle.scene.BattleMountScope"] = true, ["ui.battle.scene.BattleDraw"] = true,
        ["ui.battle.scene.BattleView"] = true, ["ui.battle.stage.BattleEnemySpawn"] = true,
        ["ui.battle.combat.BattleCombatAnim"] = true, ["ui.battle.stage.BattleSpeed"] = true,
        ["ui.character.panel.CharacterPanel"] = true, ["ui.character.panel.CharacterHeroSync"] = true,
        ["ui.character.panel.CharacterRosterSort"] = true,
        ["systems.AttributeDef"] = true, ["systems.UnitAttributes"] = true, ["systems.BattleTimeout"] = true,
        ["systems.TalentEffect"] = true, ["core.BattleLayout"] = true,
        ["core.NumberUtil"] = true, ["core.EventBus"] = true, ["shared.heroes.HeroResonance"] = true }
    env.require = function(name)
        if mocks[name] then return mocks[name] end
        if loaded[name] then return loaded[name] end
        assert(real[name] or name:match("^config%."), "undeclared real dependency " .. name)
        assert(not loading[name], "unexpected dependency cycle " .. name)
        loading[name] = true
        local path = name:gsub("%.", "/") .. ".lua"
        local text = source(path); sources[path] = text
        local result = assert(load(text, "@entry-real/" .. path, "t", env))()
        loading[name], loaded[name] = nil, result
        if name == "ui.battle.tri.BattleTriDriver" then
            local new = result.new
            result.new = function(...)
                local drv = new(...); drivers[#drivers + 1] = drv
                local start, update = drv.start, drv.update
                drv.start = function(self, ...)
                    counts.starts = counts.starts + 1; record("start:" .. self.teamIdx)
                    return start(self, ...)
                end
                drv.update = function(self, ...)
                    counts.updates = counts.updates + 1
                    return update(self, ...)
                end
                return drv
            end
        elseif name == "ui.battle.tri.BattleTriPage" then
            local prepare = result.prepareEntry
            result.prepareEntry = function(...)
                record("prepare")
                if controls.failPrepare then error("EXPECTED_ENTRY_FAILURE") end
                return prepare(...)
            end
        end
        return result
    end
    env.cache = { GetFile = forbidden("UNDECLARED_RESOURCE") }
    local Panel = env.require("ui.character.panel.CharacterPanel")
    Panel.init(nil)
    local presentationDestroys, presentationOrder = 0, {}
    local destroyPresentation = Panel.destroyPresentation
    Panel.destroyPresentation = function(...)
        presentationDestroys = presentationDestroys + 1
        presentationOrder[#presentationOrder + 1] = "Character"
        return destroyPresentation(...)
    end
    mocks["ui.hud.popup.LevelUpPopup"].destroy = function()
        presentationOrder[#presentationOrder + 1] = "LevelUp"
    end
    mocks["ui.widget.DesignWidgetSurface"].shutdown = function()
        presentationOrder[#presentationOrder + 1] = "Surface"
    end
    local function heroes(ids)
        local roster = {}
        for _, id in ipairs(ids) do roster[tostring(id)] = { level = 5 + id, exp = id, shards = 0 } end
        return { roster = roster, deployed = copy(ids), teams = { { slots = copy(ids) },
            { slots = { 4, 0, 0, 0 } }, { slots = { 5, 0, 0, 0 } } } }
    end
    local data = heroes(options.single and { 1 } or { 1, 2, 3 })
    if not options.newSave and not options.single then
        data.roster["4"], data.roster["5"] = { level = 9, exp = 0 }, { level = 10, exp = 0 }
    end
    if options.newSave or options.single then data.teams = {} end
    if not options.late then modules.heroes = data; Panel.setHeroesData(data) end
    local Tri, Queue = env.require("ui.battle.tri.BattleTriPage"), env.require("boot.StartupQueue")
    local Draw = env.require("ui.battle.scene.BattleDraw")
    Draw.setContext({ combat = Combat, imgHeroCards = {}, imgMonsterCards = {}, imgHpBg = -1,
        imgAllyTags = { -1, -1, -1, -1, -1, -1 } })
    local Boot = env.require("boot.Standalone")
    -- 仅本地闭包输入：不调用真实场景/字体/存档初始化，准备门控和Update主体均为原函数。
    setvalue(env.HandleUpdate, "bootReady_", true)
    local show = upvalue(env.HandleUpdate, "showOfflineRewardPanel_")
    local prepare = upvalue(show, "prepareEntry_")
    local context = {}
    setvalue(prepare, "vg", context)
    -- 原firstStage步骤完整函数体；只把外围场景/存档依赖绑定到上述明确spy。
    local firstStageText = section(sources["boot/Standalone.lua"], '        { "firstStage", function()',
        '        { "BattleAssets", function()')
    local firstStageEnv = setmetatable({ StandaloneSave = Save,
        TopBar = mocks["ui.hud.TopBar"], CharacterPanel = Panel, BattleScene = Scene }, { __index = env })
    local firstStage = assert(load("return {\n" .. firstStageText .. "\n}",
        "@entry-real/Standalone.firstStage-step", "t", firstStageEnv))()[1][2]
    setvalue(prepare, "firstStageStep_", firstStage)
    rt.vg, rt.logicalW, rt.logicalH, rt.bootReady_ = context, 1920, 1080, true
    rt.preload_ = { active = false }
    local evt = VariantMap()
    evt["TimeStep"] = Variant(0.016)
    ---@cast evt UpdateEventData
    local function step() return env.HandleUpdate("Update", evt) end
    local function state()
        return { queue = upvalue(prepare, "entryQueue_"), prepared = upvalue(prepare, "entryPrepared_"),
            post = upvalue(env.HandleUpdate, "postStartFlowDone_") }
    end
    local function fingerprint()
        local result = { modules = copy(modules), drivers = {} }
        for i, drv in ipairs(drivers) do
            result.drivers[i] = { stage = drv.stageId, kills = drv.kills, total = drv.stageTotal,
                active = drv.active, intro = drv.introTimer, march = drv.marchTimer,
                timeout = drv._timeoutElapsed, allies = copy(drv.allies), enemies = copy(drv.enemies),
                queue = copy(drv.enemyQueue), rewards = copy(drv.rewardQueue), pending = copy(drv.pendingKills) }
        end
        return result
    end
    local function mountSnapshot()
        local result = { units = TAL.mountedUnitStates(), extra = ETS.mountedState(), team = Stats.mountedTeam() }
        for i, api in ipairs(mounts) do result[i] = api.mountedState() end
        return result
    end
    local function mountsEqual(before)
        if before.units ~= TAL.mountedUnitStates() or before.extra ~= ETS.mountedState()
            or before.team ~= Stats.mountedTeam() then return false end
        for i, api in ipairs(mounts) do if api.mountedState() ~= before[i] then return false end end
        return true
    end
    local horizonText = source("boot/StandaloneHorizon.lua"); sources["boot/StandaloneHorizon.lua"] = horizonText
    local branch = section(horizonText, "    -- [三行并行] 战斗模式布局: 经营(左) | 三行战斗(中段) | 角色(右) 铺满窗口",
        "    -- 全局弹窗层（模态，绘制于中面板空间，坐标与原竖屏逻辑一致）")
    local hen = setmetatable({ RT = rt, BattleTriPage = Tri, vg = function() return context end,
        logicalW = function() return 1920 end, logicalH = function() return 1080 end,
        Viewport = { begin = noop, finish = noop, PANELS = { left = {}, center = {}, right = {} } },
        TownScene = mocks["ui.town.TownScene"], ChurchPage = mocks["ui.church.ChurchPage"],
        TalentPage = mocks["ui.church.talent.TalentPage"], TavernPage = mocks["ui.tavern.TavernPage"],
        MarketPage = mocks["ui.market.MarketPage"], BlacksmithPage = mocks["ui.blacksmith.BlacksmithPage"],
        BackpackPanel = mocks["ui.backpack.BackpackPanel"], LootBox = mocks["ui.loot.LootBox"],
        LootBoxPage = mocks["ui.loot.LootBoxPage"], TaskPage = passive(),
        TopBar = mocks["ui.hud.TopBar"], CharacterPanel = { draw = noop },
        PlayerInfoPanel = mocks["ui.hud.popup.PlayerInfoPanel"], RewardPopup = mocks["ui.hud.popup.RewardPopup"],
        DarkTitleScreen = title, EquipCrossDrag = mocks["ui.character.EquipCrossDrag"],
        KeyboardShortcuts = mocks["ui.dev.KeyboardShortcuts"], DrawUtil = mocks["core.DrawUtil"],
        talentPageUsesWideLayout = function() return false end, drawWideTalentPage = noop,
        seamBackList = function() return {} end, drawRewardInPanel = noop,
        HorizonDrawPageModal = noop, HorizonDrawIntroOverlay = noop, drawEquipDetailOverlay = noop,
        HorizonDrawTutorialOverlay = noop, finishFrame = function() record("render-finish") end,
        seamGesture = { cancelIfBlocked = noop }, TutorialManager = { clearHotspots = noop },
        HorizonUpdateTransform = noop, applyFrame = noop, bootReady_ = function() return rt.bootReady_ end,
        windowW = function() return 1920 end, windowH = function() return 1080 end,
        dpr = function() return 1 end, StartScreen = mocks["ui.story.gate.StartScreen"],
        nvgBeginFrame = noop, horizonInputContext = {} }, { __index = env })
    hen._G = hen
    local renderGate = section(horizonText, "function HandleNanoVGRenderHorizon()",
        "    -- 横屏底色。石框、关卡图和各页底板负责可见画面，不再铺 UI_WORLD_BG。")
    local renderBranch = assert(load(renderGate .. branch .. "\nend\nreturn HandleNanoVGRenderHorizon",
        "@entry-real/Horizon.entry-gate-and-tri-branch", "t", hen))()
    local function render() record("render"); return renderBranch() end
    local function installBudget()
        local wrapper = section(source("boot/Standalone.lua"), "    -- 2.5 图片去重按context+flags+path隔离", "    -- 3. Font")
        local wrapEnv = setmetatable({ StartupQueue = Queue, vg = context }, { __index = env })
        wrapEnv._G = wrapEnv
        assert(load(wrapper, "@entry-real/Standalone.image-budget", "t", wrapEnv))()
        env.nvgCreateImage = wrapEnv.nvgCreateImage
    end
    local function resetCounters()
        for key in pairs(counts) do counts[key] = 0 end
        trace = {}
    end
    return { env = env, boot = Boot, tri = Tri, panel = Panel, queue = Queue, modules = modules,
        counts = counts, controls = controls, drivers = drivers, sources = sources, context = context,
        show = show, prepare = prepare, step = step, render = render, state = state, budget = installBudget,
        snapshot = fingerprint, mountSnapshot = mountSnapshot, mountsEqual = mountsEqual,
        data = data, images = images, resetCounts = resetCounters,
        trace = function() return trace end, rt = rt, combat = Combat, ps = PS, effects = Effects,
        clock = clock, cardHandles = cardHandles,
        presentationState = function() return presentationDestroys, table.concat(presentationOrder, ",") end }
end

local function scenario(name, callback)
    cases = cases + 1
    local ok, err = xpcall(callback, debug.traceback)
    if not ok then check(false, name .. " HARNESS_ERROR " .. tostring(err)) end
end
local function drain(f, limit)
    local pumps = 0
    while f.state().queue and pumps < (limit or 80) do
        local before = f.counts.images
        local mounted = f.mountSnapshot()
        f.step(); pumps = pumps + 1
        if f.state().queue then
            local images, cards = f.counts.images, #f.cardHandles
            f.render()
            check(f.counts.images == images and #f.cardHandles == cards and not f.rt.entryRendered,
                "entryPreparing原Horizon暗底分支不画半成品/不加载大卡 #" .. pumps)
        end
        check(f.counts.images - before <= 2, "entry每泵至多两新图 #" .. pumps)
        check(f.mountsEqual(mounted), "entry正常/挂起泵恢复全部mount #" .. pumps)
        check(f.counts.calc == 0 and f.counts.shown == 0 and f.counts.updates == 0,
            "entry半成品或完成当帧不算离线/不tick #" .. pumps)
    end
    check(pumps > 0 and not f.state().queue and f.rt.entryPrepared and not f.rt.entryPreparing,
        "entry队列实际完成")
    return pumps
end

function Start()
    local originalRequire, originalImage, originalFile = require, nvgCreateImage, File
    scenario("旧档三队准备", function()
        local f = fixture()
        f.tri.setBattleReady(false)
        check(not f.tri.prepareEntry(f.context) and #f.drivers == 0 and not f.tri.isOpen(),
            "首场失败门禁不能建driver/返回伪成功")
        f.tri.setBattleReady(true)
        f.controls.titleOpen = false
        f.budget(); f.resetCounts()
        check(f.show() == false and f.rt.entryPreparing and not f.rt.entryRendered,
            "旧档先排准备队列，未render不能离线")
        local pumps = drain(f)
        check(pumps > 1 and #f.drivers == 3 and f.counts.starts == 3, "不同队真实driver各建一次")
        check(f.drivers[1].stageId == 201 and f.drivers[2].stageId == 305 and f.drivers[3].stageId == 401,
            "三队从自己stage恢复，不借主线201")
        check(#f.drivers[1].allies == 3 and #f.drivers[2].allies == 1 and #f.drivers[3].allies == 1,
            "真实HeroConfig工厂按真实队槽创建3/1/1人")
        check(#f.drivers[2].enemyQueue > 0 and #f.drivers[2].enemies == 4,
            "真实305首波有候补，不是空列表spy")
        local HC, MC = f.env.require("config.HeroAssetUtil"), f.env.require("config.MonsterConfig")
        local loadedPaths = {}
        for _, image in ipairs(f.images) do loadedPaths[image.path] = true end
        for row, drv in ipairs(f.drivers) do
            for _, list in ipairs({ drv.allies, drv.enemies, drv.enemyQueue }) do
                for _, unit in ipairs(list) do
                    local path = unit.heroId and HC.getCardPath(unit.heroId)
                        or string.format("image/怪物卡牌/KP_GW_%d.png", MC.getCardArtId(unit.monsterId))
                    check(loadedPaths[path], "真实在场及候补卡warm T" .. row .. " " .. path)
                end
            end
        end
        local before = f.snapshot()
        check(not f.show() and f.counts.calc == 0, "准备完成仍须实际Tri.draw帧")
        local imageCount = f.counts.images
        f.render()
        check(f.rt.entryRendered and #f.cardHandles > 0 and f.counts.images == imageCount,
            "Horizon实际Tri.draw后标记，warm首draw新增大卡0")
        check(same(f.snapshot(), before), "实际draw不改战斗/奖励/存档字段")
        check(f.show() and f.counts.calc == 1 and f.counts.shown == 1, "render之后才允许离线结算")
        local data = f.controls.shown
        check(data.offlineSeconds == 60 and data.maxSeconds == 86400 and data.multiplier == 1.25
            and data.adventureExp == 11 and data.adventurerExp == 99
            and same(data.rewards, { { type = "gold", amount = 777 } })
            and data.hardCapSeconds == 604800 and data.tailRatio == 0.1,
            "旧离线参数/奖励逐字段原样透传")
        setvalue(f.env.HandleUpdate, "postStartFlowDone_", true)
        local frozen, starts = f.snapshot(), f.counts.starts
        for _ = 1, 40 do f.step() end
        check(f.counts.updates == 0 and f.counts.tick == 0 and f.counts.pumps == 0
            and same(f.snapshot(), frozen), "离线pending40帧不tick真实driver/单Scene/全图鉴")
        check(f.counts.starts == starts and f.counts.calc == 1 and f.counts.shown == 1,
            "重复Update不重准备/不重算/不重弹")
        local flush = f.counts.flush
        f.controls.failClaim = true
        check(not data.onClaim() and f.controls.pending and f.counts.flush == flush,
            "领取失败保留pending不额外Flush")
        f.controls.failClaim = false
        check(data.onClaim() and not f.controls.pending and f.counts.flush == flush + 1,
            "成功原onClaim回执才Flush")
        f.step()
        check(f.counts.updates == 3 and f.counts.pumps == 0, "领取后才恢复三队update，无后台大图pump")
        local entries = f.trace(); local calcIndex, renderIndex = 0, 0
        for index, name in ipairs(entries) do
            if name == "render-finish" then renderIndex = index elseif name == "calc" then calcIndex = index end
        end
        check(renderIndex > 0 and calcIndex > renderIndex, "真实trace顺序prepare→render-finish→Calc")
        check(f.counts.random == 0 and f.counts.mutations == 0, "准备/待领/首intro帧无攻击发奖random或玩家File")
    end)
    scenario("新档单人升级三人", function()
        local f = fixture({ newSave = true, single = true, stage = 101, maxStage = 101 })
        f.budget(); f.tri.prepareEntry(f.context)
        check(#f.drivers == 1 and #f.drivers[1].allies == 1, "开场前旧single驱动真实一人")
        f.rt.entryPrepared, f.rt.entryRendered = true, true
        setvalue(f.prepare, "entryPrepared_", true)
        local old = f.drivers[1].allies
        f.controls.titleOpen, f.controls.titleFading = true, true
        f.step()
        check(f.counts.starter == 1 and f.controls.letterOpen and not f.rt.entryPrepared and not f.rt.entryRendered,
            "grant_starter_trio真实开场闭包失效旧prepared/rendered")
        check(f.drivers[1].allies == old and #old == 1, "信件期间不偷偷tick重建single")
        f.controls.titleOpen = false
        f.controls.letterOpen = false
        local starts = f.counts.starts
        assert(f.controls.letterFinish)()
        local opening = f.env.require("config.ScenarioDialogueConfig")
        local openingConfigs = { opening.OPENING, table.unpack(opening.OPENING_JOINS) }
        check(#openingConfigs == 4 and not f.state().queue and f.controls.dialogueOpen,
            "信件结束先进入完整门厅+三人介绍四段，不提前prepare")
        for index, cfg in ipairs(openingConfigs) do
            local dialogue = assert(f.controls.dialogue, "missing opening dialogue " .. index)
            check(dialogue.steps == cfg.steps and dialogue.title == cfg.title
                and dialogue.background == cfg.background and dialogue.mode == cfg.mode,
                "真实开场段顺序/正文/场景保持 #" .. index)
            local frozen = f.snapshot()
            for _ = 1, 3 do f.step() end
            check(not f.state().queue and not f.state().post and f.counts.calc == 0
                and f.counts.updates == 0 and f.counts.pumps == 0 and same(f.snapshot(), frozen),
                "开场正文完成前不prepare/离线/战斗/奖励改动 #" .. index)
            f.controls.dialogueOpen = false
            dialogue.onFinish()
            local afterFinish = f.snapshot()
            dialogue.onFinish()
            check(same(f.snapshot(), afterFinish), "开场旧token重复完成不改下一段存档 #" .. index)
            if index < 4 then
                check(f.controls.dialogueOpen and not f.state().queue and not f.state().post
                    and f.modules.session.deferredOpening == true
                    and f.modules.session.deferredOpeningIndex == index + 1,
                    "完成后立即接续下一段，仍独占开场 #" .. index)
            end
        end
        check(f.modules.session.deferredOpening == false
            and f.modules.session.deferredOpeningCompletedVersion == 1,
            "全部四段真实完成后才持久标记开场完成")
        check(f.state().queue and not f.state().post and f.counts.calc == 0,
            "finishIntro只排真实prepare，未渲染不算离线")
        drain(f)
        check(f.counts.starts == starts + 1 and #f.drivers == 1 and #f.drivers[1].allies == 3
            and f.drivers[1].allies ~= old, "同次prepare马上重建3hero，不等15update/不造第二driver")
        local warmStarts = f.counts.starts
        f.tri.prepareEntry(f.context); f.tri.prepareEntry(f.context)
        check(f.counts.starts == warmStarts, "重复prepare同签名不再重建")
        check(not f.show(), "三人已准备但新render帧仍必需")
        f.render(); f.step()
        check(f.state().post and f.counts.calc == 1 and f.counts.shown == 0,
            "新档render后沿原Calc首次无离线包，不伪弹收益")
        check(f.counts.starter == 1, "后续旧introCompleted判定不重授三人")
    end)
    scenario("迟到角色", function()
        local f = fixture({ late = true, stage = 201 })
        f.controls.titleOpen = false
        setvalue(f.prepare, "entryPrepared_", true)
        f.rt.entryPrepared, f.rt.entryRendered = true, true
        check(not f.show() and not f.state().queue and f.counts.calc == 0,
            "角色未到达旧ready标记也不能建离线包")
        f.modules.heroes = f.data
        f.budget()
        check(not f.show() and f.state().queue and not f.rt.entryPrepared and not f.rt.entryRendered,
            "真实setHeroesData晚水合失效ready/render，排重新prepare")
        drain(f)
        check(#f.drivers[1].allies == 3 and f.drivers[1].allies[2].heroId == 2
            and f.drivers[1].allies[2].level == 7, "晚水合prepare用真实HeroConfig新等级，不用默认lv1")
        check(not f.show() and f.counts.calc == 0, "晚水合队列结束当帧仍不结算")
        f.render(); check(f.show() and f.counts.calc == 1, "晚水合新draw后才Calc")
    end)
    scenario("准备失败与显式重试", function()
        local f = fixture({ stage = 101, maxStage = 101 })
        f.controls.titleOpen, f.controls.failPrepare = false, true
        f.show(); f.step(); f.step()
        check(not f.state().prepared and not f.rt.entryPrepared and not f.rt.entryPreparing
            and f.counts.calc == 0 and #f.drivers == 0, "准备异常不伪就绪/不发离线，不泄漏Preparing")
        f.render()
        check(not f.rt.entryRendered and f.counts.calc == 0, "失败准备没有Tri实际draw不能render ready")
        f.controls.failPrepare = false
        f.show(); f.step(); f.step()
        check(f.rt.entryPrepared and f.counts.starts == 1 and f.counts.calc == 0,
            "后续新队列成功仍先交渲染")
        f.render(); check(f.show(), "失败后真实prepare+render可恢复")
    end)
    scenario("Stop取消挂起", function()
        local f = fixture({ stage = 101, maxStage = 101 })
        f.controls.titleOpen = false; f.budget(); f.show(); f.step(); f.step()
        check(f.state().queue and not f.state().prepared and f.counts.images == 2,
            "Stop夹具真图片预算yield而非空worker")
        local count, starts = f.counts.images, f.counts.starts
        f.boot.Stop(); f.step()
        local presentationDestroys, presentationOrder = f.presentationState()
        check(presentationDestroys == 1 and presentationOrder == "LevelUp,Character,Surface",
            "真实Stop仅一次释放角色展示，保持LevelUp→Character→Surface顺序")
        check(not f.state().queue and not f.rt.entryPrepared and not f.rt.entryRendered
            and not f.rt.entryPreparing and f.counts.images == count and f.counts.starts == starts,
            "真实Stop丢弃worker，后续Update不能恢复旧VG/ready")
    end)
    scenario("清档取消并重新开场", function()
        local f = fixture({ stage = 201, maxStage = 2001 })
        f.controls.titleOpen = false; f.budget(); f.show(); f.step(); f.step()
        check(f.state().queue, "清档前真实挂起entry存在")
        local oldDriver = f.drivers[1]
        f.controls.pending = true
        f.boot.requestResetToStartScreen()
        check(not f.state().queue and not f.rt.entryPrepared and not f.rt.entryRendered
            and not f.rt.entryPreparing and not f.controls.pending and not f.state().post,
            "清档真实reset丢弃旧queue/ready/pending/post")
        check(not oldDriver.active and #oldDriver.pendingKills == 0 and #oldDriver.rewardQueue == 0
            and oldDriver.onKill == nil and oldDriver.onStageChanged == nil,
            "清档真实Tri discard旧driver/奖励出口，不结算残留队列")
        check(f.modules.session.introCompleted == false and f.modules.battle.currentStageId == 101,
            "清档原session/battle字段回到真实默认")
        local imageCount = f.counts.images
        f.step()
        check(f.counts.images == imageCount and f.counts.calc == 0,
            "新标题Update不恢复旧挂起images/Calc")
        f.controls.titleOpen, f.controls.titleFading = true, true
        f.step()
        check(f.counts.starter == 1 and f.controls.letterOpen, "清档重新走一次三人开场")
    end)
    scenario("外部回执已水合但旧prepared", function()
        local f = fixture({ single = true, stage = 101, maxStage = 101 })
        f.controls.titleOpen = false
        f.tri.prepareEntry(f.context)
        setvalue(f.prepare, "entryPrepared_", true)
        f.rt.entryPrepared, f.rt.entryRendered = true, true
        local old = f.drivers[1].allies
        f.modules.heroes = { roster = { ["1"] = { level = 6 }, ["2"] = { level = 7 }, ["3"] = { level = 8 } },
            deployed = { 1, 2, 3, 0 }, teams = {} }
        f.panel.setHeroesData(f.modules.heroes)
        check(f.panel.isHeroesDataApplied() and #old == 1 and f.drivers[1].allies == old,
            "外部真实回执isApplied=true且签名失效，driver仍旧一人")
        local beforeCalc = f.counts.calc
        local accepted = f.show()
        check(not accepted and f.counts.calc == beforeCalc and f.state().queue and not f.rt.entryRendered,
            "外部先水合也必须废旧prepared/rendered，不能直接Calc旧single")
        if f.state().queue then
            f.budget(); f.resetCounts(); drain(f)
            check(#f.drivers[1].allies == 3 and not f.show(), "外部回执重新prepare真实三人后仍等新render")
            f.render(); check(f.show(), "外部回执重prepare+重render恢复离线入口")
        end
    end)
    scenario("false首场门禁保留且原步骤重试", function()
        local f = fixture({ stage = 101, maxStage = 101 })
        f.controls.titleOpen, f.controls.failFirstStage = false, true
        f.tri.setBattleReady(false)
        for attempt = 1, 3 do
            f.show(); f.step(); f.step()
            check(f.counts.firstStage == attempt and not f.tri.isBattleReady()
                and f.counts.calc == 0 and not f.rt.entryPrepared and #f.drivers == 0,
                "firstStage原reloadStage失败不解除首场门禁/不Calc #" .. attempt)
        end
        f.controls.failFirstStage = false
        f.show(); f.step()
        check(f.tri.isBattleReady() and f.counts.firstStage == 4 and not f.rt.entryPrepared
            and f.counts.calc == 0 and #f.drivers == 0,
            "仅原firstStage闭包成功解除battleReady，下帧才prepare")
        f.step()
        check(f.rt.entryPrepared and not f.show(), "首场成功重试完整prepare仍等待render")
        f.render()
        check(f.show() and f.counts.calc == 1, "首场失败可由原步骤重试恢复，无显式放宽门禁")
    end)
    scenario("跨yield挂载与重建异常", function()
        local f = fixture({ single = true, stage = 101, maxStage = 101 })
        f.controls.titleOpen = false
        f.tri.prepareEntry(f.context)
        f.modules.heroes = { roster = { ["1"] = { level = 6 }, ["2"] = { level = 7 }, ["3"] = { level = 8 } },
            deployed = { 1, 2, 3, 0 }, teams = {} }
        f.panel.setHeroesData(f.modules.heroes)
        local oldImage = f.env.nvgCreateImage
        f.env.nvgCreateImage = function(vg, path, flags)
            f.queue.checkpoint(); return oldImage(vg, path, flags)
        end
        local q = f.queue.new({ { "prepare", function() return f.tri.prepareEntry({}) end } },
            { clock = function() return 0 end })
        local mounted, done, pumps = f.mountSnapshot(), false, 0
        while not done and pumps < 60 do
            done = q:pump(); pumps = pumps + 1
            check(f.mountsEqual(mounted), "外层Scope.wrap跨yield也不留最后重建队 #" .. pumps)
        end
        check(done and pumps > 1 and #f.drivers[1].allies == 3 and f.counts.updates == 0,
            "跨yield真重建完成且零战斗update")
        f.panel.setHeroesData({ roster = { ["1"] = { level = 6 }, ["2"] = { level = 7 } },
            deployed = { 1, 2, 0, 0 }, teams = {} })
        local originalStart = f.drivers[1].start
        f.drivers[1].start = function(self)
            self.mount(); error("EXPECTED_DRIVER_REBUILD_FAILURE")
        end
        mounted = f.mountSnapshot()
        local ok, err = pcall(f.tri.prepareEntry, f.context)
        check(not ok and tostring(err):find("EXPECTED_DRIVER_REBUILD_FAILURE", 1, true)
            and f.mountsEqual(mounted), "重建异常原错误透传且所有mount恢复")
        f.drivers[1].start = originalStart
    end)
    scenario("图片yield期间外部水合", function()
        local f = fixture({ single = true, stage = 101, maxStage = 101 })
        f.controls.titleOpen = false
        f.tri.prepareEntry(f.context)
        f.panel.setHeroesData({ roster = { ["1"] = { level = 6 }, ["2"] = { level = 7 }, ["3"] = { level = 8 } },
            deployed = { 1, 2, 3, 0 }, teams = {} })
        f.budget(); f.show()
        f.state().queue.maxImages = 1
        f.step(); f.step()
        check(f.state().queue and #f.drivers[1].allies == 3 and not f.tri.isEntryPrepared(),
            "真实prepare已冻结三人但卡预热yield仍无有效凭据")
        f.modules.heroes = { roster = { ["1"] = { level = 6 }, ["2"] = { level = 7 }, ["4"] = { level = 9 } },
            deployed = { 1, 2, 4, 0 }, teams = {} }
        f.panel.setHeroesData(f.modules.heroes)
        local pumps = 0
        while f.state().queue and pumps < 60 do
            local mounted = f.mountSnapshot()
            f.step(); pumps = pumps + 1
            check(f.mountsEqual(mounted) and f.counts.calc == 0 and f.counts.updates == 0,
                "旧candidate水合后继续图片yield仍不Calc/tick且恢复mount #" .. pumps)
        end
        check(not f.state().queue and not f.rt.entryPrepared and not f.rt.entryRendered
            and not f.tri.isEntryPrepared(), "旧candidate完成也不能把中途新阵容标为预热完成")
        local starts = f.counts.starts
        check(not f.show() and f.state().queue, "旧candidate失效后下一次show排真实新prepare")
        drain(f)
        check(f.counts.starts == starts + 1 and f.drivers[1].allies[3].heroId == 4
            and f.tri.isEntryPrepared() and not f.show(), "新prepare只重建一次真实hero4并等新render")
        f.render()
        check(f.show() and f.counts.calc == 1, "图片yield换阵容后新prepare/render才允许离线")
    end)
    scenario("缺卡图片沿原容错不冒称加载成功", function()
        local f = fixture({ stage = 101, maxStage = 101 })
        local missing = f.env.require("config.HeroAssetUtil").getCardPath(2)
        f.controls.titleOpen, f.controls.imageFailure = false, missing
        f.budget(); f.show(); drain(f)
        check(f.tri.isEntryPrepared() and #f.drivers[1].allies == 3 and f.counts.calc == 0,
            "单卡返回-1保留原容错且仍按真实阵容/渲染门禁，不伪算离线")
        local loads = f.counts.images
        f.render()
        local sawFailure = false
        for _, handle in ipairs(f.cardHandles) do if handle == -1 then sawFailure = true end end
        check(sawFailure and f.counts.images == loads and f.rt.entryRendered,
            "真实Draw缓存-1交原绘制容错，首帧不反复解码，不称全部卡加载成功")
        check(f.show() and f.counts.calc == 1 and f.counts.updates == 0 and f.counts.random == 0,
            "缺卡不改离线/随机/战斗计时旧规则")
    end)
    scenario("反复open/update没有图鉴pump", function()
        local f = fixture({ stage = 101, maxStage = 101 })
        f.tri.setBattleReady(true)
        f.tri.open(); local starts = f.counts.starts
        for _ = 1, 5 do f.tri.open() end
        local before = f.snapshot()
        f.controls.letterOpen = true
        for _ = 1, 20 do f.tri.update(0.25) end
        check(f.counts.starts == starts and f.counts.updates == 0 and f.counts.pumps == 0
            and same(f.snapshot(), before), "信件期间重复open/update不建队/不tick/不pump大卡")
        f.controls.letterOpen = false
        f.tri.update(0.016)
        check(f.counts.updates == 1 and f.counts.pumps == 0 and f.counts.starts == starts,
            "正式tri update仅真实driver，不消费全图鉴loader")
    end)
    check(require == originalRequire and nvgCreateImage == originalImage and File == originalFile,
        "全局require/nvg/File保持，隔离环境零真实档IO")
    print(string.format("%s RESULT cases=%d assertions=%d failures=%d %s", TAG, cases, assertions, failures,
        failures == 0 and "ALL PASS" or "FAILED"))
    if failures > 0 then log:Write(LOG_ERROR, TAG .. " failures=" .. failures) end
    engine:Exit()
end
