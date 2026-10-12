-- 启动素材专项：完整真实模块源码隔离load，GPU/业务仅有限外围spy，不读玩家档。
-- Town cold draw作敏感性对照；preload不是draw/update，不把计数mock当设备性能验收。
local TAG = "[startup_assets_test]"
local assertions, failures = 0, 0
local function check(value, label)
    assertions = assertions + 1
    if not value then failures = failures + 1 end
    print(TAG .. (value and " PASS " or " FAIL ") .. label)
end
local function noop() end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

function Start()
    -- 旧projectile_arc入口只含顶层代码，无Start/Exit；仅进程内执行原文后退出。
    -- 不改旧断言、不写临时入口；与素材专项各自独立Runtime进程。
    for _, arg in ipairs(GetArguments()) do
        if arg == "-assets-run-projectile-arc" or arg == "-assets-run-host-integration" then
            local path = arg == "-assets-run-projectile-arc" and "tests/projectile_arc_test.lua"
                or "tests/dark_effects_host_integration_test.lua"
            local file = assert(cache:GetFile(path))
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            file:Dispose()
            local text = table.concat(lines, "\n")
            local env = setmetatable({}, { __index = _G })
            env._G = env
            local ok, err = xpcall(function()
                assert(load(text, "@" .. path, "t", env))()
                if arg == "-assets-run-host-integration" then env.Start() end
            end, debug.traceback)
            if not ok then print(TAG .. " ORIGINAL_HARNESS_ERROR " .. tostring(err)) end
            engine:Exit()
            return
        end
    end
    local ok, err = xpcall(function()
        local nativeRequire, nativeImage = require, nvgCreateImage
        local clock, sources = { elapsedTime = 100 }, {}
        local loads, patterns, cards, images = {}, {}, {}, {}
        local context, count, sideEffects = {}, 0, 0
        local function forbidden() sideEffects = sideEffects + 1; error("ASSETS_FORBIDDEN_BUSINESS") end
        local function source(path)
            if not sources[path] then
                local file = assert(cache:GetFile(path), "missing real source " .. path)
                local lines = {}
                while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
                file:Dispose()
                sources[path] = table.concat(lines, "\n")
            end
            return sources[path]
        end
        local function section(path, first, last)
            local text = source(path)
            local a = assert(text:find(first, 1, true), first)
            assert(not text:find(first, a + #first, true), "ambiguous " .. first)
            local b = assert(text:find(last, a + #first, true), last)
            return text:sub(a, b - 1)
        end
        local real = { ["config.ExpTable"] = true, ["config.StageConfig"] = true,
            ["config.HeroAssetUtil"] = true, ["config.MonsterConfig"] = true,
            ["core.BattleLayout"] = true, ["config.AwakeningConfig"] = true,
            ["ui.battle.combat.BattleCombatAnim"] = true, ["systems.AttributeDef"] = true }
        local function environment(mocks, fields)
            local env = setmetatable(fields or {}, { __index = _G })
            env._G, env.time, env.File = env, clock, forbidden
            env.require = function(name)
                if mocks[name] ~= nil then return mocks[name] end
                assert(real[name], "undeclared import " .. name)
                return nativeRequire(name)
            end
            env.math = setmetatable({ random = forbidden, randomseed = forbidden }, { __index = math })
            for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFillPaint", "nvgFill",
                "nvgFillColor", "nvgSave", "nvgRestore", "nvgTranslate", "nvgRotate", "nvgScale",
                "nvgCircle", "nvgStroke", "nvgStrokeColor", "nvgStrokeWidth", "nvgMoveTo", "nvgLineTo",
                "nvgScissor", "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgText", "nvgShapeAntiAlias" }) do
                env[name] = noop
            end
            env.nvgRGBA = function(...) return { ... } end
            env.nvgRadialGradient = function() return {} end
            env.nvgImagePatternTinted = function() return {} end
            env.nvgImageSize = function() return 256, 256 end
            env.nvgCreateImage = function(vg, path, flags)
                count = count + 1
                loads[#loads + 1] = { vg = vg, path = path, flags = flags }
                images[count] = path
                return count
            end
            env.nvgImagePattern = function(_, x, y, w, h, angle, image, alpha)
                patterns[#patterns + 1] = { path = images[image], image = image, x = x, y = y,
                    w = w, h = h, angle = angle, alpha = alpha }
                return {}
            end
            return env
        end
        local function compile(path, mocks, fields)
            local env = environment(mocks, fields)
            return assert(load(source(path), "@startup-real/" .. path, "t", env))(), env
        end
        local function pathCount(path, list)
            local n = 0
            for _, entry in ipairs(list or loads) do if entry.path == path then n = n + 1 end end
            return n
        end
        local DrawUtil = { drawTextStroke = noop,
            drawCardImage = function(_, image) cards[#cards + 1] = image end }
        local expeditionCalls = {}
        local townMocks = {
            ["ui.town.TownExpeditionIcon"] = { draw = function(_, x, y, size)
                expeditionCalls[#expeditionCalls + 1] = { x, y, size }
            end },
            ["core.GameState"] = { getLevel = function() return 100 end },
            ["core.DarkIcon"] = { draw = noop, drawNine = noop },
            ["core.HorizonBg"] = { draw = noop }, ["core.DrawUtil"] = DrawUtil,
            ["systems.ButtonFeedback"] = { begin = function() return false end, finish = noop, trigger = noop },
            ["ui.loot.LootBox"] = { getCount = function() return 0 end, drawRates = noop },
            ["systems.TutorialManager"] = { isActive = function() return false end,
                isBuildingUnlocked = function() return true end, registerHotspot = forbidden },
            ["ui.blacksmith.BlacksmithPage"] = { canEnhanceAny = function() return false end },
            ["ui.church.talent.TalentPage"] = { hasAnyUnusedTalent = function() return false end },
            ["ui.church.ChurchPage"] = { hasAnyChurchBadge = function() return false end },
            ["ui.story.task.TaskPage"] = { hasClaimable = function() return false end },
        }
        local Town = compile("ui/town/TownScene.lua", townMocks)
        Town.preload(nil)
        check(#loads == 0, "Town无context预热不读图")
        Town.init(context)
        check(#loads == 0, "Town.init仅保存context")
        local callback = 0
        Town.setOnExpeditionClick(function() callback = callback + 1 end)
        Town.handleInput(520, 1480)
        clock.elapsedTime = 101
        Town.preload(nil)
        local warm = #loads
        check(warm == 19, "Town真实预热保留原19图，白色远征导航使用独立矢量")
        local townPaths = {
            "image/界面底板/城镇世界/UI_CZ_YX.png", "image/通用图标/ICON_CZ_YX.png",
            "image/界面底板/城镇世界/UI_CZ_GJ.png", "image/通用图标/ICON_CZ_GJ.png",
            "image/界面底板/城镇世界/UI_CZ_CK.png", "image/通用图标/ICON_CZ_TJP.png",
            "image/界面底板/城镇世界/UI_CZ_JT.png", "image/界面底板/城镇世界/UI_CZ_TREE.png",
            "image/城镇建筑/UI_CZ_EXPEDITION_GATE.png", "image/界面底板/城镇世界/UI_CZ_JG.png",
            "image/界面底板/城镇世界/UI_CZ_SJ.png", "image/界面底板/城镇世界/UI_CZ_TJP.png",
            "image/通用图标/ICON_CZ_CK.png", "image/通用图标/ICON_CZ_JT.png",
            "image/通用图标/ICON_CZ_TREE.png", "image/通用图标/ICON_CZ_JG.png",
            "image/通用图标/ICON_CZ_SC.png", "image/通用图标/ICON_UP.png", "image/通用图标/UI_ICON_SUO.png",
        }
        for _, path in ipairs(townPaths) do check(pathCount(path) == 1, "Town真实预热路径恰好一次 " .. path) end
        check(callback == 0, "预热不消费到期的真实城镇延迟业务回调")
        for _, entry in ipairs(loads) do check(entry.vg == context and entry.flags == 0, "Town init context及flags保持") end
        Town.preload(context)
        check(#loads == warm, "Town重复preload不重复图片调用")
        Town.draw(context)
        check(#loads == warm and callback == 1, "Town首次完整draw新增图片0且原延迟回调仍正常")
        check(#expeditionCalls == 1 and expeditionCalls[1][1] == 460 and expeditionCalls[1][2] == 1610
            and expeditionCalls[1][3] == 48, "Town远征名牌真实调用独立白色罗盘，48尺寸与既定位置保持")
        Town.draw(context)
        check(#loads == warm and callback == 1, "Town后续draw缓存命中，延迟回调恰好一次")
        local ColdTown = compile("ui/town/TownScene.lua", townMocks)
        ColdTown.init(context)
        local before = #loads
        ColdTown.draw(context)
        check(#loads - before == 19, "独立cold真模块首draw仍19张，证明warm对照非空绘制")

        local combat = {
            getCardAnimOffsetY = function() return 0 end, getChargeOffsetY = function() return 0 end,
            getCardAnimArcY = function() return 0 end, getCardScale = function() return 1 end,
            getAnimState = function() return "idle" end, getTransitionAlpha = function() return 1 end,
            getHitFlashAlpha = function() return 0 end, getHpBuffer = function() return 1 end,
            getFloatingTexts = function() return {} end, getCardCX = function() return 300 end,
            getCardCY = function() return 180 end,
        }
        local drawMocks = { ["systems.StatusEffectManager"] = { getVisuals = function() return {} end },
            ["systems.TalentManager"] = { getConquerStacks = function() return 0 end },
            ["core.NumberUtil"] = { format = tostring }, ["core.DrawUtil"] = DrawUtil,
            ["systems.ExtraTalentSystem"] = { drawOrbit = noop } }
        local Icon, iconEnv = compile("ui/battle/scene/DamageTypeIcon.lua", {})
        drawMocks["ui.battle.scene.DamageTypeIcon"] = Icon
        local Draw = compile("ui/battle/scene/BattleDraw.lua", drawMocks)
        local hero = { heroId = 1, hp = 10, maxHp = 10, name = "hero", level = 1 }
        local monster = { monsterId = 1, hp = 10, maxHp = 10, name = "monster", level = 1 }
        local units = { hero, monster, hero, {} }
        local originalUnits = copy(units)
        local imageContext = { combat = combat, imgHeroCards = {}, imgMonsterCards = {},
            imgHpBg = -1, imgAllyTags = {} }
        Draw.setContext(imageContext)
        before = #loads
        Draw.preloadCards(context, {})
        check(#loads == before, "空在场列表不预热未在场卡面")
        Draw.preloadCards(context, units)
        check(#loads - before == 2, "仅真实在场英雄/怪物加载，各ID重复只一次")
        check(same(units, originalUnits) and next(imageContext.imgHeroCards) == nil,
            "卡面预热不改单位/战斗共享后台缓存")
        local warmedHero, warmedMonster = count - 1, count
        before = #loads
        Draw.preloadCards(context, units)
        check(#loads == before, "重复卡面preload命中原cardImage缓存")
        Draw.drawCardGroup(context, { hero }, 1000, 0, 0, 0, 0, 0, 0, -1, true)
        Draw.drawCardGroup(context, { monster }, 1000, 0, 0, 0, 0, 0, 0, -1, false)
        check(#loads == before and cards[#cards - 1] == warmedHero and cards[#cards] == warmedMonster,
            "完整drawCardGroup复用预热句柄而非另一个测试缓存")
        imageContext.imgHeroCards[1], imageContext.imgMonsterCards[1] = 0, 900
        Draw.preloadCards(context, units)
        Draw.drawCardGroup(context, { hero }, 1000, 0, 0, 0, 0, 0, 0, -1, true)
        check(#loads == before and cards[#cards] == 0, "后台缓存到达后优先使用，合法0句柄保持")

        local psMocks = { ["systems.GameSFX"] = {}, ["systems.BattleStats"] = {}, ["systems.BattleDiag"] = {} }
        local PS = compile("ui/battle/combat/ProjectileSystem.lua", psMocks)
        PS.init(context)
        local gatePath = "image/特效投射物/EF_skill_20.png"
        local getX = function(_, i) return 300 + i end
        before = #loads
        local drawBefore = #patterns
        PS.drawStarGates(context, {}, 180, getX, true)
        PS.drawStarGates(context, { hero, monster, { heroId = 20, hp = 0 } }, 180, getX, true)
        PS.drawStarGates(context, { { heroId = 20, hp = 0, _starGateSummoned = true },
            { heroId = 20, hp = 0, _starGatePersistsAfterDeath = true } }, 180, getX, false)
        check(#loads == before and #patterns == drawBefore, "无hero20/普通死亡/缺任一持续标志不读图不画门")
        local gateHero = { heroId = 20, hp = 10, _starGateCount = 2 }
        local gateSnapshot = copy(gateHero)
        PS.drawStarGates(context, { gateHero }, 180, getX, true)
        check(pathCount(gatePath) == 1 and pathCount(gatePath, patterns) == 2, "活hero20只加载一次并画两星门")
        check(same(gateHero, gateSnapshot) and PS.getActiveCount() == 0,
            "星门draw不召唤投射物/改变hp或召唤字段")
        drawBefore = #patterns
        PS.drawStarGates(context, { { heroId = 20, hp = 0,
            _starGatePersistsAfterDeath = true, _starGateSummoned = true } }, 180, getX, false)
        check(#patterns - drawBefore == 1 and pathCount(gatePath) == 1, "死后已召唤且持续规则仍画，缓存不重读")
        local ColdPS = compile("ui/battle/combat/ProjectileSystem.lua", psMocks)
        ColdPS.init(context)
        before = #loads
        ColdPS.drawStarGates(context, { { heroId = 20, hp = 0,
            _starGatePersistsAfterDeath = true, _starGateSummoned = true } }, 180, getX, false)
        check(#loads - before == 1, "独立冷缓存死后持续星门仍首次取图")

        local viewMocks = { ["ui.battle.scene.BattleDraw"] = Draw,
            ["ui.battle.combat.BattleEffects"] = { draw = noop },
            ["ui.battle.combat.ProjectileSystem"] = PS, ["ui.battle.combat.BattleCombat"] = combat,
            ["systems.ExtraTalentSystem"] = { drawIceStatues = noop } }
        local View = compile("ui/battle/scene/BattleView.lua", viewMocks)
        local mapPath = "image/关卡地图/MAP_1.png"
        View.init(context); View.init(context)
        check(pathCount(mapPath) == 0, "BattleView.init幂等且不加载MAP_1")
        before = #loads; drawBefore = #patterns
        for _ = 1, 3 do View.draw(context, { allies = {}, enemies = {} }, nil, true) end
        check(#loads == before and #patterns == drawBefore, "三行skipBg真draw不读地图且不画底带")
        View.draw(context, {}, 901, false)
        check(pathCount(mapPath) == 0 and patterns[#patterns].image == 901,
            "非skipBg外部有效bg保持且不读默认map")
        View.draw(context, {}, 0, false)
        check(pathCount(mapPath) == 0 and patterns[#patterns].image == 0, "外部合法0句柄兼容")
        View.draw(context, {}, nil, false)
        check(pathCount(mapPath) == 1 and patterns[#patterns].path == mapPath,
            "非skipBg缺外部图仍首次加载并绘制MAP_1")
        View.draw(context, {}, nil, false)
        check(pathCount(mapPath) == 1, "默认map后续draw仅加载一次")

        local progress = { currentStageId = 201, maxStageId = 101,
            teamStageIds = { ["1"] = 201, ["2"] = 301, ["3"] = 401 }, clearedStages = {} }
        local progressBefore = copy(progress)
        local triMocks = { ["ui.battle.scene.BattleView"] = View,
            ["ui.battle.combat.BattleCombat"] = combat, ["ui.battle.combat.ProjectileSystem"] = PS,
            ["runtime.ClientDispatcher"] = { get = function(key) return key == "battle" and progress or nil end },
            ["ui.battle.scene.BattleScene"] = { getStageId = function() return progress.currentStageId end,
                pumpBattleCards = forbidden, update = forbidden },
            ["ui.battle.tri.BattleTriDriver"] = { new = forbidden },
            ["ui.battle.stage.StageSelectDialog"] = { init = noop },
            ["ui.widget.SoundToggle"] = { initImages = noop },
        }
        for _, name in ipairs({ "systems.ThreatManager", "systems.TalentManager", "ui.battle.combat.BattleEffects",
            "systems.StatusEffectManager", "ui.hud.popup.RewardPopup", "ui.battle.stage.SweepDialog",
            "ui.battle.popup.DamageStatsPanel", "ui.battle.popup.TerminalConfirmDialog", "ui.battle.tri.TerminalRaid",
            "ui.character.equip.EquipmentBag", "systems.BattleStats", "core.I18n", "systems.RelicConditionHandler",
            "ui.battle.scene.BattleMountScope", "ui.battle.stage.BattleSpeed" }) do triMocks[name] = {} end
        -- 现有Tri新增回收模块只在编译时取函数；素材预热禁止实际回收/转生业务。
        triMocks["ui.battle.tri.TerminalReincarnation"] = { discardDriver = forbidden }
        triMocks["ui.battle.scene.BattleMountScope"] = { wrap = noop }
        triMocks["ui.battle.tri.BattleEntryPreparation"] = compile("ui/battle/tri/BattleEntryPreparation.lua", {
            ["ui.battle.scene.BattleDraw"] = Draw,
            ["ui.battle.scene.BattleMountScope"] = { run = forbidden },
        })
        local Tri = compile("ui/battle/tri/BattleTriPage.lua", triMocks)
        before = #loads
        Tri.preload(context)
        check(not Tri.isOpen() and Tri.getTeamStageId(1) == nil and Tri.getTeamStageId(2) == nil,
            "Tri预热不open/不创建驱动")
        check(same(progress, progressBefore) and sideEffects == 0, "Tri预热不推进battle/不发回执/不改存档进度")
        check(pathCount(Tri.resolveBackgroundPath(201)) > 0
            and pathCount(Tri.resolveBackgroundPath(1001)) > 0 and pathCount(Tri.resolveBackgroundPath(2001)) > 0,
            "Tri首屏按一队真实关及二三锁定章节预热")
        local triWarm = #loads
        Tri.preload(context)
        check(#loads == triWarm, "Tri重复预热不重载L0/行背景")
        progress.maxStageId = 1906
        Tri.preload(context)
        check(pathCount(Tri.resolveBackgroundPath(301)) > 0 and pathCount(Tri.resolveBackgroundPath(401)) > 0,
            "解锁二三队无driver时仍从存档队关预热")
        check(progress.currentStageId == 201 and progress.teamStageIds["2"] == 301 and sideEffects == 0,
            "解锁行预热只读，不创建/推进剧情战斗")
        local SC = nativeRequire("config.StageConfig")
        progress.teamStageIds = { [2] = 999, [3] = 501 }
        before = #loads
        Tri.preload(context)
        check(pathCount(Tri.resolveBackgroundPath(SC.getTerminalPrevStageId(999))) > 0
            and pathCount(Tri.resolveBackgroundPath(501)) > 0,
            "存档数字队键兼容，二队终焉按真实建驱动规则回退背景")
        check(progress.teamStageIds[2] == 999 and progress.currentStageId == 201,
            "终焉展示回退不改写存档队关")
        check(pathCount(mapPath) == 1, "Tri自身预热没有额外加载默认MAP_1")
        local freshContext = {}
        before = #loads; Town.init(freshContext); Town.preload(freshContext)
        check(#loads - before == 19, "Town新context完整重载19图，不借旧context")
        before = #loads; View.init(freshContext); View.draw(freshContext, {}, nil, true)
        check(#loads - before == 1 and pathCount(mapPath) == 1, "View新context只重载tag，skipBg仍不读map")
        imageContext.imgHeroCards, imageContext.imgMonsterCards = {}, {}
        before = #loads; Draw.preloadCards(freshContext, units)
        check(#loads - before == 2, "Draw新context重载两在场卡面，不借旧direct缓存")
        before = #loads; Tri.preload(freshContext)
        check(#loads - before == 4, "Tri新context重载L0与三行背景，不借旧L1")

        -- 真Standalone wrapper/队列配置/pump/Stop边界；不require生产入口或启动存档。
        local Queue = compile("boot/StartupQueue.lua", {})
        local title = compile("ui/story/gate/DarkTitleScreenGate.lua", { ["core.I18n"] = {} })
        title.open(); title.setReady(false)
        local boundary = environment({ ["ui.battle.stage.StageSelectDialog"] = { close = noop },
            ["ui.fx.SpineCardEffect"] = { destroy = noop }, ["ui.fx.SpineResultEffect"] = { destroy = noop },
            ["ui.fx.DarkEffectSprites"] = { destroy = noop },
            -- Stop新接入的外围呈现/故事清理，只记录可调用性，不启动实际故事或塔场景。
            ["systems.StoryPlayer"] = { resetAll = noop }, ["ui.tavern.RecruitAnim"] = { destroy = noop },
            ["ui.tower.TowerBuffSidebar"] = { destroy = noop },
            ["ui.widget.DesignWidgetSurface"] = { shutdown = noop },
            ["systems.ExtraTalentSystem"] = { flush = noop },
            ["ui.battle.scene.BattleMountScope"] = { runDefault = function(fn) fn() end },
            ["ui.battle.combat.BattleCasualty"] = { flushRewards = noop },
            ["ui.dungeon.DungeonBattleScope"] = { run = function(_, fn) fn() end },
            ["ui.tower.TowerTriBattle"] = { flushPendingGrowth = noop },
            ["ui.character.hero.AwakeningArtwork"] = { destroy = noop },
            ["rules.tower.TowerService"] = { ResetToDefault = noop } }, {
            LetterIntro = { reset = noop }, ScenarioDialogue = { reset = noop },
            CharacterPanel = { destroyPresentation = noop }, TowerBattleScene = { resetToDefault = noop },
            TowerBuffPick = { destroy = noop },
            StartupQueue = Queue, StandaloneRT = {}, DarkTitleScreen = title, vg = context,
            BattleTriPage = { setBattleReady = function(ready) triMocks.ready = ready end, flushPendingGrowth = noop },
            Standalone = {}, RewardPopup = { clearBattleRewards = noop }, StandaloneSave = { Flush = noop },
            SpinePowerUpEffect = { destroy = noop }, LevelUpPopup = { destroy = noop },
        })
        boundary.nvgDelete = noop
        local boundaryCompleted, resumedAfterStop = 0, 0
        boundary.bootSteps = {
            { "firstStage", function()
                for i = 1, 5 do boundary.nvgCreateImage(context, "boundary-" .. i .. ".png", 0) end
                boundaryCompleted = boundaryCompleted + 1
            end },
            { "BattleAssets", function() end },
        }
        assert(load(section("boot/Standalone.lua", "    -- 2.5 图片去重按context+flags+path隔离", "    -- 3. Font"),
            "@startup-real/Standalone.image-wrapper", "t", boundary))()
        local configCode = section("boot/Standalone.lua", "    bootQueue_ = StartupQueue.new(bootSteps, {", "    -- 轻量接线")
        local pumpCode = section("boot/Standalone.lua", "local function pumpBootQueue_()", "-- [一次性加载] 三段式加载")
        assert(load(configCode, "@startup-real/Standalone.queue-config", "t", boundary))()
        local pump = assert(load(pumpCode .. "\nreturn pumpBootQueue_", "@startup-real/Standalone.pump", "t", boundary))()
        before = #loads
        pump(); title.handleTap()
        check(#loads - before <= 2 and boundaryCompleted == 0 and not title.isFading()
            and not boundary.StandaloneRT.bootReady_, "合作式半初始化让出时title未ready且不能进入")
        local warmTown, warmEnv = compile("ui/town/TownScene.lua", townMocks)
        warmEnv.nvgCreateImage = boundary.nvgCreateImage
        warmTown.init(context)
        local townQueue = Queue.new({ { "Town", function() warmTown.preload(context) end } },
            { clock = function() return 0 end })
        local done, frames = false, 0
        while not done and frames < 20 do
            before = #loads; frames = frames + 1
            done = townQueue:pump()
            check(#loads - before <= 2, "真实Town preload/host wrapper每泵至多两新图 " .. frames)
        end
        before = #loads; warmTown.draw(context)
        check(done and frames == 10 and #loads == before, "合作式Town预热19张分10泵，首完整draw新增0")
        assert(load(section("boot/Standalone.lua", "function Standalone.Stop()", "--- 标题关闭后按真实离线时长结算"),
            "@startup-real/Standalone.Stop", "t", boundary))()
        boundary.Standalone.Stop(); pump()
        check(boundary.bootQueue_ == nil and not boundary.StandaloneRT.bootReady_ and boundaryCompleted == 0,
            "真实Stop丢弃挂起worker，后续pump不恢复已释放context")
        boundary.bootSteps = {
            { "firstStage", function() resumedAfterStop = resumedAfterStop + 1 end },
            { "BattleAssets", function() end },
        }
        assert(load(configCode, "@startup-real/Standalone.fresh-queue", "t", boundary))()
        pump()
        check(resumedAfterStop == 1 and triMocks.ready == true and not boundary.StandaloneRT.bootReady_
            and not title.isReady(), "首场准备成功后解除战斗门禁，但标题继续等待素材步骤")
        pump()
        check(boundaryCompleted == 0 and boundary.StandaloneRT.bootReady_ and title.isReady(),
            "全部启动步骤结束后独立解锁标题")
        title.setReady(false); triMocks.ready = false
        boundary.bootSteps = {
            { "firstStage", function() error("EXPECTED_FIRST_STAGE_FAILURE") end },
            { "BattleAssets", function() end },
        }
        assert(load(configCode, "@startup-real/Standalone.first-stage-failure", "t", boundary))()
        pump()
        check(not triMocks.ready and not boundary.StandaloneRT.bootReady_,
            "首场准备抛错时不解除BattleTri门禁")
        pump()
        check(title.isReady() and boundary.StandaloneRT.bootReady_ and not triMocks.ready,
            "后续素材步骤成功也不能恢复失败首场的BattleTri门禁")
        title.setReady(false); triMocks.ready = false
        boundary.bootSteps = {
            { "firstStage", function() end },
            { "BattleAssets", function() error("EXPECTED_ASSET_FAILURE") end },
        }
        assert(load(configCode, "@startup-real/Standalone.failed-assets", "t", boundary))()
        pump()
        check(triMocks.ready and not boundary.StandaloneRT.bootReady_,
            "首场准备成功后即使素材步骤失败也保留战斗容错")
        pump()
        check(title.isReady() and triMocks.ready and boundary.StandaloneRT.bootReady_,
            "素材失败沿用旧启动容错且不遗留BattleTri冻结")
        -- 可选只读边界复现，审查输出不冒称支持同VM完整重启；不改生产修复。
        for _, arg in ipairs(GetArguments()) do
            if arg == "-assets-audit-stop-restart" then
                local partialTown, partialEnv = compile("ui/town/TownScene.lua", townMocks)
                local fakeVG, freshVG = {}, {}
                boundary.vg = fakeVG
                assert(load(section("boot/Standalone.lua", "    -- 2.5 图片去重按context+flags+path隔离", "    -- 3. Font"),
                    "@startup-audit/Standalone.image-wrapper", "t", boundary))()
                partialEnv.nvgCreateImage = boundary.nvgCreateImage
                partialTown.init(fakeVG)
                boundary.bootSteps = { { "Town", function() partialTown.preload(fakeVG) end } }
                assert(load(configCode, "@startup-audit/partial-town", "t", boundary))()
                before = #loads; pump()
                local partialLoads = #loads - before
                boundary.Standalone.Stop()
                partialTown.init(freshVG)
                before = #loads; partialTown.preload(freshVG)
                print(string.format("%s AUDIT stop_restart same_module=true partial_loads=%d fresh_context_loads=%d incomplete=%s",
                    TAG, partialLoads, #loads - before, tostring(partialLoads < 19 and #loads == before)))
            end
        end
        -- 视觉专项仍执行完整真实模块；有限替身仅涵盖GPU、音效出口、队号和浮字输入。
        -- 不改全局、不加载玩家档、不复制生产轨迹函数；期望尺寸/时序独立写在测试数据中。
        do
            local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.000001 end
            local function length(x, y) return math.sqrt(x * x + y * y) end
            -- 仿射记录器按NanoVG的局部变换顺序组合，同时记录原始参数与最终坐标。
            -- 字体度量明确限定为每字符0.6字号；验证几何/状态，不冒称GPU像素或真实字形验收。
            local function recorder(env)
                local matrix = { 1, 0, 0, 1, 0, 0 } ---@type number[]
                local rec = { calls = {}, state = { matrix = matrix,
                    font = 13, alpha = 0.63, stroke = 2, color = { 11, 22, 33, 255 },
                    face = "原字体", align = 0 }, stack = {} }
                local function emit(name, ...)
                    local call = { name = name, args = { ... }, state = copy(rec.state) }
                    rec.calls[#rec.calls + 1] = call
                    return call
                end
                local function point(x, y)
                    local m = rec.state.matrix
                    return m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
                end
                local function scaleLength(v)
                    local m = rec.state.matrix
                    return v * length(m[1], m[2])
                end
                local function compose(a, b, c, d, x, y)
                    local m = rec.state.matrix
                    rec.state.matrix = { m[1] * a + m[3] * b, m[2] * a + m[4] * b,
                        m[1] * c + m[3] * d, m[2] * c + m[4] * d,
                        m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6] }
                end
                env.nvgSave = function() emit("保存"); rec.stack[#rec.stack + 1] = copy(rec.state) end
                env.nvgRestore = function()
                    emit("恢复"); rec.state = assert(table.remove(rec.stack), "记录器恢复栈下溢")
                end
                env.nvgTranslate = function(_, x, y) emit("平移", x, y); compose(1, 0, 0, 1, x, y) end
                env.nvgScale = function(_, x, y) emit("缩放", x, y); compose(x, 0, 0, y, 0, 0) end
                env.nvgRotate = function(_, a)
                    emit("旋转", a); compose(math.cos(a), math.sin(a), -math.sin(a), math.cos(a), 0, 0)
                end
                env.nvgGlobalAlpha = function(_, a) rec.state.alpha = a; emit("透明度", a) end
                env.nvgFontSize = function(_, s) rec.state.font = s; emit("字号", s) end
                env.nvgFontFace = function(_, s) rec.state.face = s end
                env.nvgTextAlign = function(_, a) rec.state.align = a end
                env.nvgStrokeColor = function(_, c) emit("描边颜色", c) end
                env.nvgFillColor = function(_, c) rec.state.color = c; emit("填充颜色", c) end
                env.nvgStrokeWidth = function(_, w)
                    rec.state.stroke = w; local c = emit("描边", w); c.width = scaleLength(w)
                end
                env.nvgTextBounds = function(_, _, _, text)
                    return (utf8.len(text) or #text) * rec.state.font * 0.6
                end
                env.nvgText = function(_, x, y, text)
                    local c = emit("文字", x, y, text)
                    c.x, c.y = point(x, y); c.size = scaleLength(rec.state.font)
                end
                for _, spec in ipairs({ { "nvgMoveTo", "起点" }, { "nvgLineTo", "线段" },
                    { "nvgQuadTo", "二次曲线" }, { "nvgCircle", "圆" },
                    { "nvgRect", "矩形" }, { "nvgRoundedRect", "圆角矩形" } }) do
                    env[spec[1]] = function(_, ...)
                        local c = emit(spec[2], ...)
                        c.x, c.y = point(c.args[1], c.args[2])
                        if spec[2] == "圆" then c.radius = scaleLength(c.args[3])
                        elseif spec[2] == "矩形" or spec[2] == "圆角矩形" then
                            c.w, c.h = scaleLength(c.args[3]), scaleLength(c.args[4])
                            c.cx, c.cy = point(c.args[1] + c.args[3] / 2, c.args[2] + c.args[4] / 2)
                        elseif spec[2] == "二次曲线" then c.ex, c.ey = point(c.args[3], c.args[4]) end
                    end
                end
                env.nvgClosePath = function() emit("闭合") end
                env.nvgLinearGradient = function(_, ...) return emit("线性渐变", ...) end
                env.nvgRadialGradient = function(_, ...) return emit("径向渐变", ...) end
                env.nvgImagePattern = function(_, x, y, w, h, angle, image, alpha)
                    local c = emit("图案", x, y, w, h, angle, image, alpha)
                    c.cx, c.cy = point(x + w / 2, y + h / 2)
                    c.w, c.h, c.path = scaleLength(w), scaleLength(h), images[image]
                    return c
                end
                env.nvgDeleteImage = noop
                rec.find = function(name)
                    local result = {}
                    for _, c in ipairs(rec.calls) do if c.name == name then result[#result + 1] = c end end
                    return result
                end
                rec.clear = function() rec.calls = {} end
                return rec
            end
            -- 独立真实白罗盘：不是计数mock替代像素语义，完整load后检查白色/轮廓/位置/状态。
            local ExpeditionIcon, expeditionEnv = compile("ui/town/TownExpeditionIcon.lua", {})
            local er = recorder(expeditionEnv)
            local expeditionState = copy(er.state)
            before = #loads
            ExpeditionIcon.draw(context, 460, 1610, 48)
            local ring, needle, ink = er.find("圆"), er.find("起点"), er.find("填充颜色")
            check(#ring == 2 and near(ring[1].x, 460) and near(ring[1].y, 1610)
                and near(ring[1].radius, 48 * 0.36) and #needle == 9,
                "真实远征白罗盘双层环/四轴/菱形轮廓与460,1610,48位置尺寸保持")
            check(#ink == 1 and ink[1].args[1][1] == 255 and ink[1].args[1][2] == 255
                and ink[1].args[1][3] == 255 and ink[1].args[1][4] == 255
                and #loads == before and same(er.state, expeditionState) and #er.stack == 0,
                "真实远征白罗盘非金色纹理、不读图且完整恢复NanoVG状态")

            local sounds = {}
            local VisualPS, psEnv = compile("ui/battle/combat/ProjectileSystem.lua", {
                ["systems.GameSFX"] = { play = function(key, team) sounds[#sounds + 1] = { key, team } end },
                ["systems.BattleStats"] = { mountedTeam = function() return 2 end },
                ["systems.BattleDiag"] = { logEnabled = false },
            })
            local pr = recorder(psEnv)
            VisualPS.init(context)
            -- 独立配置快照：所有公开生成入口及其真实配置，不从生产常量生成期望。
            local cases = {}
            local function add(entry, key, kind, duration, lift, h, opts)
                cases[#cases + 1] = { entry = entry, key = key, kind = kind, duration = duration,
                    lift = lift, h = h or 200, opts = opts or {}, label = entry .. " " .. tostring(key) }
            end
            for _, id in ipairs({ 1, 4, 5, 10, 11, 16 }) do add("英雄", id, "melee", 0.45, 0) end
            add("英雄", 18, "melee", 0.40, 0); add("英雄", 24, "melee", 0.50, 0)
            for _, id in ipairs({ 2, 21 }) do add("英雄", id, "fly", 0.55, 40) end
            for _, id in ipairs({ 3, 7, 13, 22 }) do add("英雄", id, "fly", 0.50, 40) end
            for _, id in ipairs({ 8, 12, 14 }) do add("英雄", id, "fly", 0.55, 96) end
            add("英雄", 25, "fly", 0.70, 40)
            add("英雄", 6, "lightning", 0.35, 0)
            add("英雄", 9, "bezier", 0.65, 64)
            for _, id in ipairs({ 15, 19 }) do add("英雄", id, "bezier", 0.65, 112) end
            add("英雄", 20, "bezier", 0.60, 96); add("英雄", 23, "bezier", 0.65, 96)
            for _, key in ipairs({ "EF_MS_8", "EF_MS_24", "EF_MS_27", "EF_MS_46", "EF_MS_50", "EF_MS_53",
                "EF_ATK_2", "EF_ATK_21" }) do add("怪物", key, "fly", 0.55, 40) end
            for _, key in ipairs({ "EF_MS_13", "EF_ATK_3", "EF_ATK_13", "EF_ATK_22" }) do
                add("怪物", key, "fly", 0.50, 40)
            end
            for _, key in ipairs({ "EF_MS_9", "EF_MS_30", "EF_MS_39", "EF_MS_43", "EF_MS_1", "EF_ATK_1",
                "EF_ATK_4", "EF_ATK_5", "EF_ATK_8", "EF_ATK_10", "EF_ATK_11", "EF_ATK_16",
                "EF_MS_22", "EF_MS_36" }) do add("怪物", key, "melee", 0.45, 0) end
            add("怪物", "EF_MS_7", "shake", 0.45, 40)
            add("怪物", "EF_ATK_6", "lightning", 0.35, 0)
            for _, key in ipairs({ "EF_MS_47", "EF_ZY_106", "EF_ZY_224", "EF_MS_16", "EF_ATK_9", "EF_ATK_23" }) do
                add("怪物", key, "bezier", 0.65, 96)
            end
            add("怪物", "EF_ATK_20", "bezier", 0.60, 96)
            add("技能", 11, "bezier", 0.55, 40, 400)
            add("技能", 20, "bezier", 0.55, 96)
            add("天赋", "EF_ZY_106", "bezier", 0.55, 96)
            add("天赋", "EF_ZY_224", "bezier", 0.45, 96)
            add("英雄", 1, "bezier", 0.45, 112, 200, { forceBezier = true })
            add("英雄", 9, "bezier", 0.65, 112, 200, { forceBezier = true })
            add("怪物", "EF_MS_8", "bezier", 0.55, 112, 200, { forceBezier = true })
            add("怪物", "EF_MS_47", "bezier", 0.65, 112, 200, { forceBezier = true })
            add("怪物近战", "EF_MS_7", "melee", 0.45, 0)
            add("怪物近战", "EF_MS_47", "melee", 0.45, 0)
            add("英雄穿透", 2, "pierce", 0.55, 40)
            add("怪物穿透", "EF_MS_8", "pierce", 0.55, 40)

            local function spawnCase(c, hit, dist)
                dist = dist or 400
                local opts = copy(c.opts); opts.bezierSide = 1
                if c.entry == "英雄" then VisualPS.spawn(c.key, 10, 120, 10 + dist, 120, hit, opts)
                elseif c.entry == "怪物" or c.entry == "怪物近战" then
                    VisualPS.spawnByKey(c.key, 10, 120, 10 + dist, 120, hit, c.entry == "怪物近战", opts)
                elseif c.entry == "技能" then VisualPS.spawnSkill(c.key, 10, 120, 10 + dist, 120, hit, opts)
                elseif c.entry == "天赋" then VisualPS.spawnTalent(c.key, 10, 120, 10 + dist, 120, hit, opts)
                else
                    VisualPS.spawnPierce(c.entry == "英雄穿透" and { heroId = c.key } or { key = c.key },
                        10, 120, 10 + dist, 120, { { atT = 0.5, onHit = hit } }, { onArrive = noop })
                end
                return assert(VisualPS.mountedState().projectiles[1], c.label)
            end
            local function trailCheck(cx, cy, px, py, size, t, label)
                local dx, dy = px - cx, py - cy
                local dist = length(dx, dy)
                local gradients, circles = pr.find("线性渐变"), pr.find("圆")
                if dist < 2 then check(#gradients == 0 and #circles == 0, label .. "微位移不画拖尾"); return end
                local tail = math.min(dist, size * 1.5) / 2
                local nx, ny = dx / dist, dy / dist
                local ex, ey = cx + nx * tail, cy + ny * tail
                local headW, tailW, glow = size * 0.175, size * 0.025, size * 0.2
                local g = assert(gradients[1]).args
                check(#gradients == 1 and near(g[1], cx) and near(g[2], cy)
                    and near(g[3], ex) and near(g[4], ey) and g[5][4] == math.floor(180 * (1 - t * 0.5)),
                    label .. "拖尾方向/透明度保持且尾长为原dist封顶值50%")
                local points = pr.find("起点")
                local lines = pr.find("线段")
                check(#points == 1 and #lines == 3 and near(points[1].x, cx - ny * headW)
                    and near(points[1].y, cy + nx * headW)
                    and near(lines[1].x, cx + ny * headW) and near(lines[1].y, cy - nx * headW)
                    and near(lines[2].x, ex + ny * tailW) and near(lines[2].y, ey - nx * tailW)
                    and near(lines[3].x, ex - ny * tailW) and near(lines[3].y, ey + nx * tailW),
                    label .. "拖尾四顶点头宽/尾宽50%")
                local radial = assert(pr.find("径向渐变")[1]).args
                check(#circles == 1 and near(circles[1].x, cx) and near(circles[1].y, cy)
                    and near(circles[1].radius, glow) and near(radial[3], glow / 10) and near(radial[4], glow),
                    label .. "拖尾发光半径及内径50%")
            end
            local function runCase(c, rs, dist, lift)
                dist, lift = dist or 400, lift or c.lift
                local pierce = c.kind == "pierce"
                local laneY = pierce and 0 or -2 * math.min(34, dist * 0.045)
                local endY = 120 + laneY * 0.15
                local durationScale = pierce and 1 or (c.kind == "bezier" or c.key == 8 or c.key == 12 or c.key == 14)
                    and 0.94 or 0.86
                local duration = c.duration * durationScale
                local hitRatio = c.kind == "melee" and dist / (dist + 250)
                    or c.kind == "lightning" and 0.3 or pierce and 0.5 or 1
                local label = c.label .. (c.opts.forceBezier and "治疗强制弧" or "") .. " 布局倍率" .. rs
                VisualPS.reset(); VisualPS.setRenderScale(rs)
                local hits = 0
                local p = spawnCase(c, function() hits = hits + 1 end, dist)
                check(p.cfg.type == c.kind and near(p.cfg.duration, c.duration)
                    and near(p.durationScale or 1, durationScale) and near(p.arcLift, lift)
                    and near(p.startX, 10) and near(p.startY, 120)
                    and near(p.endX, 10 + dist) and near(p.endY, endY), label .. "独立轨迹/生命周期配置保持")
                VisualPS.update(duration / 2)
                local snapshot, state = copy(p), copy(pr.state)
                pr.clear(); VisualPS.draw(context)
                check(same(p, snapshot) and same(pr.state, state) and #pr.stack == 0,
                    label .. "绘制不推进timer/到达状态且保存恢复完整")
                local cx, cy = 10 + dist / 2, (120 + endY) / 2 - (lift * rs - laneY) / 2
                local angle = math.atan(endY - 120, dist)
                if c.kind == "melee" then
                    local d = length(dist, endY - 120)
                    local flown = (d + 250) * durationScale / 2
                    cx, cy = 10 + dist / d * flown, 120 + (endY - 120) / d * flown
                elseif c.kind == "lightning" then cx, cy = 10 + dist / 2, (120 + endY) / 2
                elseif c.kind == "shake" then
                    local d = length(dist, endY - 120)
                    local offset = math.sin(15) * 6
                    cx, cy = cx - (endY - 120) / d * offset, cy + dist / d * offset
                end
                if c.kind ~= "melee" and c.kind ~= "lightning" then
                    local prevT = c.kind == "bezier" and 0.44 or 0.42
                    local px = 10 + dist * prevT
                    local py = 120 + (endY - 120) * prevT + 2 * (1 - prevT) * prevT * (laneY - lift * rs)
                    trailCheck(cx, cy, px, py, (c.kind == "bezier" or c.kind == "shake") and 80 or 100, 0.5, label)
                end
                local image = assert(pr.find("图案")[1])
                local w = c.kind == "lightning" and math.max(100, length(dist, endY - 120)) or 100 * rs
                local h = c.kind == "lightning" and 100 or c.h / 2 * rs
                check(#pr.find("图案") == 1 and near(image.w, w) and near(image.h, h)
                    and near(image.cx, cx) and near(image.cy, cy), label .. "图案/矩形尺寸50%且真实飞行中心不变")
                local rect = assert(pr.find("矩形")[1])
                check(near(rect.w, w) and near(rect.h, h) and near(rect.cx, cx) and near(rect.cy, cy),
                    label .. "实际绘制矩形与图案一致")
                local key = type(c.key) == "number" and (c.entry == "技能" and "EF_skill_" or "EF_ATK_") .. c.key or c.key
                if c.entry == "英雄" and c.key == 8 then key = "EF_ATK_8_BLUE" end
                check(image.path == "image/特效投射物/" .. key .. ".png", label .. "真实图片路径不变")
                local rotation = pr.find("旋转")
                if c.key == 8 or c.key == 14 or c.key == "EF_MS_16" then angle = angle + math.pi * 4 end
                check(#rotation == 0 and near(angle, 0) or #rotation == 1 and near(rotation[1].args[1], angle),
                    label .. "切线/自转角度不变")
                check(hits == (hitRatio <= 0.5 and 1 or 0), label .. "中段命中次数符合独立时序")
                -- 第二次独立生成专测精确命中边界和0.15秒余量，不靠绘制反推时序。
                VisualPS.reset(); hits = 0; spawnCase(c, function() hits = hits + 1 end, dist)
                local hitTime = duration * hitRatio
                VisualPS.update(hitTime - 0.0000001)
                check(hits == 0, label .. "命中前不回调")
                VisualPS.update(0.0000002)
                check(hits == 1 and VisualPS.getActiveCount() == 1, label .. "命中恰好一次且未提前移除")
                VisualPS.update(duration + 0.15 - hitTime - 0.0000002)
                check(hits == 1 and VisualPS.getActiveCount() == 1, label .. "生命周期保留原0.15秒尾部")
                VisualPS.update(0.0000002)
                check(hits == 1 and VisualPS.getActiveCount() == 0, label .. "原生命周期结束精确移除")
            end
            for _, c in ipairs(cases) do
                runCase(c, 1)
                if c.entry == "技能" or c.entry == "天赋" or c.opts.forceBezier or c.kind == "shake" then runCase(c, 0.4) end
            end
            for _, i in ipairs({ 9, 18, 24, 45, #cases - 1 }) do runCase(cases[i], 0.4) end
            runCase(cases[9], 0.4, 5000, 72)
            -- 微位移边界由公开穿透入口生成，仍走真实draw分派及helper。
            VisualPS.reset(); VisualPS.setRenderScale(1)
            VisualPS.spawnPierce({ heroId = 2 }, 10, 120, 10, 120,
                { { atT = 1, onHit = noop } })
            VisualPS.update(0.275); pr.clear(); VisualPS.draw(context)
            trailCheck(10, 106, 10, 106.3584, 100, 0.5, "同点穿透")
            check(near(pr.find("图案")[1].cx, 10) and near(pr.find("图案")[1].cy, 106),
                "同点穿透微位移仍保留原浅弧中心")

            -- 多目标穿透只生成一发，真实排序/按沿途进度回调/最终到达保持，不仅测试单命中。
            VisualPS.reset(); VisualPS.setRenderScale(0.4)
            local hitOrder, arrivals = {}, 0
            local hitEvents = { { atT = 0.75, onHit = function() hitOrder[#hitOrder + 1] = "后" end },
                { atT = 0.25, onHit = function() hitOrder[#hitOrder + 1] = "前" end } }
            check(VisualPS.spawnPierce({ heroId = 2 }, 10, 120, 410, 120, hitEvents,
                { onArrive = function() arrivals = arrivals + 1 end }) == true
                and VisualPS.getActiveCount() == 1 and hitEvents[1].atT == 0.25, "穿透入口仍排序且只生成一发")
            VisualPS.update(0.55 * 0.25 - 0.0000001)
            check(#hitOrder == 0 and arrivals == 0, "多目标穿透首命中前不触发")
            VisualPS.update(0.0000002)
            check(same(hitOrder, { "前" }) and arrivals == 0, "多目标穿透原0.25进度只命中前目标")
            VisualPS.update(0.55 * 0.5)
            check(same(hitOrder, { "前", "后" }) and arrivals == 0, "多目标穿透原0.75进度命中后目标")
            VisualPS.update(0.55 * 0.25)
            check(same(hitOrder, { "前", "后" }) and arrivals == 1 and VisualPS.getActiveCount() == 1,
                "多目标穿透最终到达恰好一次且仍保留尾部")
            VisualPS.update(0.15)
            check(VisualPS.getActiveCount() == 0 and arrivals == 1 and #hitOrder == 2,
                "多目标穿透原寿命移除不重复命中")

            -- 长短闪电按原连接长度延展，不把长链宽度再乘布局倍率或0.5。
            for _, entry in ipairs({ "英雄", "怪物" }) do
                for _, dist in ipairs({ 40, 600 }) do
                    for _, t in ipairs({ 0.15, 0.3, 0.8 }) do
                        VisualPS.reset(); VisualPS.setRenderScale(0.4)
                        local c = { entry = entry, key = entry == "英雄" and 6 or "EF_ATK_6", opts = {} }
                        spawnCase(c, noop, dist); VisualPS.update(0.35 * 0.86 * t)
                        pr.clear(); VisualPS.draw(context)
                        local image = assert(pr.find("图案")[1])
                        local dy = -2 * math.min(34, dist * 0.045) * 0.15
                        local extend = t < 0.3 and 1 - (1 - t / 0.3) ^ 2 or 1
                        local fullDist = length(dist, dy)
                        local width = math.max(100, fullDist * extend)
                        check(near(image.w, width) and near(image.h, 100)
                            and near(image.cx, 10 + dist * extend / 2) and near(image.cy, 120 + dy * extend / 2)
                            and near(image.args[7], t > 0.7 and 1 - (t - 0.7) / 0.3 or 1),
                            entry .. "闪电 距离" .. dist .. " 进度" .. t .. " 最低宽100/厚100且长连接与淡出保持")
                        if dist == 600 and t >= 0.3 then
                            local angle = math.atan(dy, dist)
                            check(near(image.cx - math.cos(angle) * width / 2, 10)
                                and near(image.cy - math.sin(angle) * width / 2, 120)
                                and near(image.cx + math.cos(angle) * width / 2, 610)
                                and near(image.cy + math.sin(angle) * width / 2, 120 + dy), "长闪电两端仍连接完整起终点")
                        end
                    end
                end
            end

            -- slashTint当前无公开配置，有限注入公开mountedState夹具覆盖真实slash分派，不改源码。
            VisualPS.reset(); VisualPS.setRenderScale(0.4)
            VisualPS.mountedState().projectiles[1] = { cfg = { type = "slash", imgKey = "EF_skill_11",
                imgW = 160, imgH = 320, duration = 1, slashTint = { 255, 50, 50 } },
                timer = 0.7, startX = 10, startY = 120, endX = 410, endY = 120 }
            pr.clear(); VisualPS.draw(context)
            local slash = assert(pr.find("图案")[1]); local glow = assert(pr.find("径向渐变")[1]).args
            check(near(slash.w, 28.16) and near(slash.h, 56.32) and near(slash.cx, 410) and near(slash.cy, 120)
                and near(glow[3], 14.08) and near(glow[4], 70.4) and near(pr.find("圆")[1].radius, 70.4),
                "斩击动态尺寸/红光各50%，目标中心不变，光晕保留原布局行为")

            -- 飞剑公开技能入口：展开/齐射/首命中→穿透120→转向→折返→二次命中。
            VisualPS.reset(); VisualPS.setRenderScale(0.4)
            local firstHits, returnHits = 0, 0
            VisualPS.spawnSkill(16, 10, 120, 410, 120, function()
                firstHits = firstHits + 1
                return { hitX = 410, hitY = 120, dirX = 1, dirY = 0,
                    onReturnHit = function() returnHits = returnHits + 1 end }
            end, { flyingSwordCount = 4, flyingSwordIndex = 1, flyingSwordRadius = 90 })
            local sword = assert(VisualPS.mountedState().projectiles[1])
            check(near(sword.ringX, 10) and near(sword.ringY, 84) and near(sword.durationScale, 0.86),
                "飞剑展开半径仍90乘布局倍率而非视觉倍率")
            local swordTime = 0
            local function swordAt(t, duration, x, y, w, angle, label)
                local nextTime = t * duration
                VisualPS.update(nextTime - swordTime); swordTime = nextTime
                local beforeSword, state = copy(sword), copy(pr.state)
                pr.clear(); VisualPS.draw(context)
                local image = assert(pr.find("图案")[1])
                check(near(image.cx, x) and near(image.cy, y) and near(image.w, w) and near(image.h, w)
                    and same(sword, beforeSword) and same(pr.state, state) and #pr.stack == 0,
                    label .. "尺寸50%且位置/生命周期/绘制状态不变")
                local rotations = pr.find("旋转")
                check(#rotations == 0 and near(angle, 0) or #rotations == 1 and near(rotations[1].args[1], angle),
                    label .. "朝向保持")
            end
            swordAt(0.16, 0.731, 10, 88.5, 38.75, 0, "飞剑展开")
            local attackT = ((0.5 - 0.32) / 0.68) ^ 2
            local volleyX, volleyY = 10 + 400 * attackT, 84 + 30.6 * attackT
            swordAt(0.5, 0.731, volleyX, volleyY, 40, math.atan(30.6, 400), "飞剑齐射")
            trailCheck(volleyX, volleyY, 10, 84, 90, 0.5, "飞剑齐射")
            VisualPS.update(0.731 * (0.32 + 0.68 * 0.92) - swordTime - 0.0000001)
            check(firstHits == 0, "飞剑首命中前不回调")
            VisualPS.update(0.0000002); swordTime = 0
            check(firstHits == 1 and returnHits == 0 and sword.isFlybackReturn and sword.timer == 0
                and sword.behindX == 530 and sword.behindY == 120 and VisualPS.getActiveCount() == 1,
                "飞剑原首命中阈值转换同对象，穿透距离120及timer重置保持")
            swordAt(0.2, 0.645, 529.04, 120, 35.2, 0, "飞剑折返穿透")
            trailCheck(529.04, 120, 511.04, 120, 84, 0.2, "飞剑折返穿透")
            swordAt(0.325, 0.645, 530, 120, 35.2, math.pi / 2, "飞剑转向")
            check(#pr.find("线性渐变") == 0, "飞剑原地转向不新增拖尾")
            swordAt(0.7, 0.645, 500, 120, 35.2, math.pi, "飞剑折返")
            trailCheck(500, 120, 520, 120, 84, 0.7, "飞剑折返")
            VisualPS.update(0.645 * 0.98 - swordTime - 0.0000001)
            check(returnHits == 0, "飞剑二次命中前不回调")
            VisualPS.update(0.0000002)
            check(firstHits == 1 and returnHits == 1 and VisualPS.getActiveCount() == 1,
                "飞剑原0.98二次命中阈值且回调各一次")
            VisualPS.update(0.645 * 0.02 + 0.15 - 0.0000002)
            check(VisualPS.getActiveCount() == 1 and returnHits == 1, "折返生命周期仍含0.15秒余量")
            VisualPS.update(0.0000002)
            check(VisualPS.getActiveCount() == 0 and firstHits == 1 and returnHits == 1, "折返移除不重复命中")

            -- 治疗目标死亡仍走真实update取消路径，视觉缩小不能改变回调/移除。
            VisualPS.reset(); local target = { hp = 10 }; local cancelled = 0
            VisualPS.spawn(9, 10, 120, 410, 120, function() cancelled = cancelled + 1 end,
                { forceBezier = true, target = target })
            target.hp = 0; VisualPS.update(0)
            check(cancelled == 1 and VisualPS.mountedState().projectiles[1].timer == 0.65,
                "治疗死亡目标仍立即回调并跳到原尾部")
            VisualPS.update(0.12)
            check(cancelled == 1 and VisualPS.getActiveCount() == 0, "治疗死亡取消仅一次并按原尾部移除")
            local blueSound = false
            for _, s in ipairs(sounds) do if s[1] == "EF_ATK_8" and s[2] == 2 then blueSound = true end end
            check(blueSound, "蓝色小鸟真实音效出口仍使用旧EF_ATK_8及原队号")

            -- 常驻门独立布局/脉冲尺寸保持；生产helper显式visualScale=1，不能随投掷物缩小。
            for _, rs in ipairs({ 1, 0.4 }) do
                for _, ally in ipairs({ true, false }) do
                    VisualPS.reset(); VisualPS.setRenderScale(rs); VisualPS.update(0.25)
                    local gateUnit = { heroId = 20, hp = ally and 10 or 0, _starGateCount = 2,
                        _starGatePersistsAfterDeath = true, _starGateSummoned = true }
                    local unitBefore, state = copy(gateUnit), copy(pr.state)
                    pr.clear(); VisualPS.drawStarGates(context, { gateUnit }, 999, function() return 300 end,
                        ally, function() return 180 end)
                    local paints, circles, radial = pr.find("图案"), pr.find("圆"), pr.find("径向渐变")
                    for index = 1, 2 do
                        local x = 300 + (index == 1 and -118 or 118)
                        local y = 62 + math.sin(0.5 + index * 1.7) * 9
                        local size = 118 * (0.94 + 0.06 * math.sin(0.85 + index)) * rs
                        local image = assert(paints[index])
                        check(near(image.w, size * rs) and near(image.h, size * rs)
                            and near(image.cx, x) and near(image.cy, y)
                            and near(circles[index * 2 - 1].radius, size * 0.62)
                            and near(circles[index * 2].radius, size * 0.38)
                            and near(radial[index].args[3], size * 0.18) and near(radial[index].args[4], size * 0.62),
                            "星门" .. index .. " 倍率" .. rs .. " 原图/双层光晕/脉冲/中心保持")
                    end
                    check(same(gateUnit, unitBefore) and VisualPS.getActiveCount() == 0
                        and same(pr.state.matrix, state.matrix) and #pr.stack == 0, "常驻门不修改召唤对象且图片局部变换恢复")
                end
            end

            -- 浮字使用真实BattleDraw及真实DrawUtil八方向描边；不把drawTextStroke mock为空。
            local strokeUtil, strokeEnv = compile("core/DrawUtil.lua", {})
            local fr = recorder(strokeEnv)
            local floatMocks = copy(drawMocks); floatMocks["core.DrawUtil"] = strokeUtil
            local FloatDraw, floatEnv = compile("ui/battle/scene/BattleDraw.lua", floatMocks)
            for name, value in pairs(strokeEnv) do
                if name:find("nvg", 1, true) == 1 then floatEnv[name], iconEnv[name] = value, value end
            end
            local floatQueue = {}
            FloatDraw.setContext({ combat = { getFloatingTexts = function() return floatQueue end } })
            local function floatCase(kind, font, t, color, label)
                local ft = { text = "123", fontSize = font, duration = 2, timer = 2 * t,
                    x = 300, y = 180, dirX = 0.6, dirY = -0.8, color = color, kind = kind }
                floatQueue = { ft }
                local beforeFloat, state = copy(ft), copy(fr.state)
                fr.clear(); FloatDraw.drawFloatingTexts(context)
                local texts, scales = fr.find("文字"), fr.find("缩放")
                local x, y = 300 + 144 * t, 180 - 192 * t
                local size = math.max(1, math.floor(font * (1 - 0.75 * t)))
                local icon = math.max(22, size * 0.92)
                local known = kind and kind ~= "" and kind ~= "未知"
                local offset = known and (icon * 0.92 + 2) / 2 or 0
                -- 独立帧样本：出生/2帧立即255，仅最后5帧淡出，18帧为102。
                local alpha = assert(({ [0] = 255, [0.1] = 255, [0.25] = 255,
                    [0.5] = 255, [0.9] = 102, [1] = 0 })[t])
                if alpha == 0 then
                    check(#fr.calls == 0 and same(fr.state, state) and same(ft, beforeFloat), label .. "透明时不绘制不污染状态")
                    return
                end
                local fill = assert(texts[9])
                local m = fill.state.matrix
                check(#texts == 9 and #scales >= 1 and near(scales[1].args[1], 0.7) and near(scales[1].args[2], 0.7)
                    and near(fill.size, size * 0.7) and fill.args[3] == "123"
                    and near(fill.x, x + offset * 0.7) and near(fill.y, y)
                    and near(m[1] * x + m[3] * y + m[5], x) and near(m[2] * x + m[4] * y + m[6], y),
                    label .. "普通/自定义字号70%且240轨迹锚点保持")
                local dx = { -5, 5, 0, 0, -3.535, 3.535, -3.535, 3.535 }
                local dy = { 0, 0, -5, 5, -3.535, -3.535, 3.535, 3.535 }
                local outline = true
                for i = 1, 8 do
                    outline = outline and near(texts[i].x - fill.x, dx[i] * 0.7)
                        and near(texts[i].y - fill.y, dy[i] * 0.7) and near(texts[i].size, size * 0.7)
                end
                check(outline and near(fill.state.alpha, alpha / 255), label .. "真实八向描边及即显/末段淡出保持")
                local circles, points, rects, strokes = fr.find("圆"), fr.find("起点"), fr.find("圆角矩形"), fr.find("描边")
                local iconX = x - size * 1.8 / 2 - 1
                local unit = icon / 72 * 0.7
                local base = x + (iconX - x) * 0.7
                if kind == "magic" then
                    check(#fr.find("二次曲线") == 4 and near(points[1].x, base + 13 * unit)
                        and near(points[1].y, y - 28 * unit), label .. "旧magic解析为暗影月刃，中心/尺寸70%")
                elseif kind == "heal" then
                    check(#points == 2 and #fr.find("线段") == 12 and near(points[1].x, base - 7 * unit)
                        and near(points[1].y, y - 23 * unit), label .. "治疗十字完整轮廓与最小22尺寸70%")
                elseif kind and kind:find("phys", 1, true) then
                    check(near(points[1].x, base + 18 * unit) and near(points[1].y, y - 29 * unit),
                        label .. "斩击刀刃中心/间距70%")
                elseif kind == "burn" then
                    check(#fr.find("二次曲线") == 6 and #circles == 4
                        and near(points[1].y, y + 29 * unit), label .. "灼烧火焰六曲线及独立DOT三点角标70%")
                elseif kind == "shield" then
                    check(#fr.find("二次曲线") == 2 and near(points[1].x, base)
                        and near(points[1].y, y - 28 * unit), label .. "吸盾徽记实际尺寸70%")
                elseif kind == "block" then
                    check(#fr.find("二次曲线") == 2 and #scales == 3
                        and near(points[5].x, base + 25 * unit) and near(points[5].y, y + (24 - 28 * 0.34) * unit),
                        label .. "格挡保留斩击主体并右下盾角标，不被属性遮住")
                elseif kind == "crit" then
                    check(#scales == 3 and near(points[5].x, base + 25 * unit)
                        and near(points[5].y, y + (-24 - 27 * 0.34) * unit), label .. "暴击保留属性主体并右上星角标")
                else check(#circles == 0 and #points == 0 and #rects == 0 and #strokes == 0 and #scales == 1,
                    label .. "无kind/未知kind不画图也不占图标宽") end
                if kind and kind:find("crit", 1, true) and kind ~= "crit" then
                    check(#scales == 3 and near(points[5].x, base + 25 * unit)
                        and near(points[5].y, y + (-24 - 27 * 0.34) * unit), label .. "复合暴击角标同样70%且不盖刀刃")
                end
                if known then
                    check(near(scales[2].args[1], icon / 72) and near(scales[2].args[2], icon / 72),
                        label .. "图标72设计空间按实际字号缩放")
                end
                for _, s in ipairs(strokes) do
                    local badgeScale = s.state.matrix[1] / (icon / 72 * 0.7)
                    check((near(badgeScale, 1) or near(badgeScale, 0.34))
                        and near(s.width, s.args[1] * unit * badgeScale) and near(s.state.alpha, alpha / 255),
                        label .. "描边按主体/角标局部比例缩放且alpha仅乘一次")
                end
                for _, gradient in ipairs(fr.find("线性渐变")) do
                    check(gradient.args[5][4] == 255 and gradient.args[6][4] == 255,
                        label .. "骨白/属性色高光均不再双乘alpha")
                end
                local rgb = fill.state.color
                check(rgb[1] == color[1] and rgb[2] == color[2] and rgb[3] == color[3], label .. "浮字语义颜色保持")
                check(same(ft, beforeFloat) and floatQueue[1] == ft and #floatQueue == 1
                    and same(fr.state, state) and #fr.stack == 0, label .. "对象/排队/轨迹字段保持且完整恢复字体/颜色/透明度/变换")
                -- 下一次真实普通图片绘制必须看不到浮字的0.7局部变换。
                fr.clear(); FloatDraw.drawImageCentered(context, 900, 20, 30, 80, 40, 1)
                local nextImage = assert(fr.find("图案")[1])
                check(near(nextImage.cx, 20) and near(nextImage.cy, 30) and near(nextImage.w, 80)
                    and near(nextImage.h, 40) and same(fr.state, state), label .. "下一次绘制尺寸/中心未污染")
            end
            floatCase(nil, 40, 0.5, { 255, 255, 255 }, "普通无kind")
            floatCase("phys", 40, 0.5, { 255, 236, 170 }, "物理普通")
            floatCase("phys_crit", 80, 0.5, { 255, 236, 170 }, "物理暴击大字")
            floatCase("magic", 64, 0.25, { 120, 220, 255 }, "魔法自定义字号")
            floatCase("heal", 1, 0.5, { 90, 235, 130 }, "治疗字号1图标最小22")
            floatCase("burn", 30, 0.1, { 255, 140, 40 }, "灼烧即显")
            floatCase("block", 48, 0.9, { 7, 8, 9 }, "格挡淡出")
            floatCase("shield", 48, 0.5, { 7, 8, 9 }, "护盾")
            floatCase("crit", 90, 0.5, { 255, 70, 70 }, "独立暴击")
            floatCase("未知", 42, 0.5, { 7, 8, 9 }, "未知kind无空占位")
            floatCase("", 42, 0.5, { 7, 8, 9 }, "空kind无空占位")
            floatCase(nil, 40, 0, { 7, 8, 9 }, "初生浮字")
            floatCase(nil, 40, 1, { 7, 8, 9 }, "寿命终点浮字")
            local a = { text = "甲", fontSize = 40, duration = 2, timer = 1,
                x = 100, y = 200, dirX = 1, dirY = 0, color = { 1, 2, 3 }, kind = "heal" }
            local b = { text = "乙", fontSize = 80, duration = 2, timer = 0.5,
                x = 700, y = 600, dirX = -1, dirY = -1, color = { 1, 2, 3 } }
            floatQueue = { a, b }; local queueBefore = copy(floatQueue); local state = copy(fr.state)
            fr.clear(); FloatDraw.drawFloatingTexts(context)
            local texts = fr.find("文字")
            check(#texts == 18 and texts[9].args[3] == "甲" and texts[18].args[3] == "乙"
                and near(texts[18].x, 640) and near(texts[18].y, 540) and near(texts[18].size, 45.5)
                and same(floatQueue, queueBefore) and floatQueue[1] == a and floatQueue[2] == b
                and same(fr.state, state) and #fr.stack == 0,
                "同队列相邻两浮字各围绕自己的中心缩放，顺序/对象不变且不积累70%变换")
        end
        check(nvgCreateImage == nativeImage and clock.elapsedTime == 101, "隔离环境不改全局nvg或推进真实时钟")
        check(sources["ui/town/TownScene.lua"] and sources["ui/battle/scene/BattleDraw.lua"]
            and sources["ui/battle/scene/BattleView.lua"] and sources["ui/battle/tri/BattleTriPage.lua"]
            and sources["ui/battle/combat/ProjectileSystem.lua"], "五个正式完整模块均实际读取执行")
    end, debug.traceback)
    if not ok then failures = failures + 1; print(TAG .. " HARNESS_ERROR " .. tostring(err)) end
    print(string.format("%s RESULT assertions=%d failures=%d %s", TAG, assertions, failures,
        failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
