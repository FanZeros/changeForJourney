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
            if arg == "-assets-run-host-integration" then
                -- 仅进程内补新增宿主依赖到既有局部环境，不重写原165条断言。
                env.StartupQueue = require("boot.StartupQueue")
                local old, patched = text:gsub("{nvgCreateImage=function%(ctx,path,flags%)",
                    "{StandaloneRT={},nvgCreateImage=function(ctx,path,flags)")
                assert(patched == 1, "unique original wrapperEnv dependency anchor")
                text = old
            end
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
            ["core.BattleLayout"] = true, ["config.AwakeningConfig"] = true }
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
        local townMocks = {
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
        check(warm == 19, "Town真实预热覆盖19个既有图片调用")
        check(callback == 0, "预热不消费到期的真实城镇延迟业务回调")
        for _, entry in ipairs(loads) do check(entry.vg == context and entry.flags == 0, "Town init context及flags保持") end
        Town.preload(context)
        check(#loads == warm, "Town重复preload不重复图片调用")
        Town.draw(context)
        check(#loads == warm and callback == 1, "Town首次完整draw新增图片0且原延迟回调仍正常")
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
        triMocks["ui.battle.scene.BattleMountScope"] = { wrap = noop }
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
            ["ui.widget.DesignWidgetSurface"] = { shutdown = noop } }, {
            StartupQueue = Queue, StandaloneRT = {}, DarkTitleScreen = title, vg = context,
            BattleTriPage = { setBattleReady = function(ready) triMocks.ready = ready end },
            Standalone = {}, RewardPopup = { clearBattleRewards = noop }, StandaloneSave = { Flush = noop },
            SpinePowerUpEffect = { destroy = noop }, LevelUpPopup = { destroy = noop },
        })
        boundary.nvgDelete = noop
        local boundaryCompleted, resumedAfterStop = 0, 0
        boundary.bootSteps = { { "BattleAssets", function()
            for i = 1, 5 do boundary.nvgCreateImage(context, "boundary-" .. i .. ".png", 0) end
            boundaryCompleted = boundaryCompleted + 1
        end } }
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
        boundary.bootSteps = { { "BattleAssets", function() resumedAfterStop = resumedAfterStop + 1 end } }
        assert(load(configCode, "@startup-real/Standalone.fresh-queue", "t", boundary))()
        pump()
        check(resumedAfterStop == 1 and boundaryCompleted == 0 and triMocks.ready == true
            and boundary.StandaloneRT.bootReady_ and title.isReady(), "新队列独立完成，旧挂起worker从未恢复")
        title.setReady(false); triMocks.ready = false
        boundary.bootSteps = { { "BattleAssets", function() error("EXPECTED_ASSET_FAILURE") end } }
        assert(load(configCode, "@startup-real/Standalone.failed-assets", "t", boundary))()
        pump()
        check(title.isReady() and triMocks.ready == true and boundary.StandaloneRT.bootReady_,
            "最终素材失败沿用旧容错且不遗留新battleReady冻结")
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
