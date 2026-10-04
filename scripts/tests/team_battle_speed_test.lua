-- 全局倍速回归：真实Page/Driver/Scene/Speed及攻击进度；
-- 仅单位、战斗子系统dt出口、渲染与存档使用替身。
-- Runtime: tests/team_battle_speed_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
function Start()
    local nativeRequire = require
    local checks, failures, cases, brokenCases = 0, 0, 0, 0
    local function check(ok, label)
        checks = checks + 1
        if not ok then failures = failures + 1 end
        print("[team_battle_speed] " .. (ok and "PASS " or "FAIL ") .. label)
    end
    local function eq(actual, expected, label)
        check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
    end
    local function near(actual, expected, label)
        check(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
            label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
    end
    local function run(label, callback)
        cases = cases + 1
        local before = failures
        local ok, err = pcall(callback)
        if not ok then check(false, "harness " .. label .. " " .. tostring(err)) end
        if failures > before then brokenCases = brokenCases + 1 end
    end
    local function source(name)
        local f = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "source " .. name)
        local lines = {}
        while not f:IsEof() do lines[#lines + 1] = f:ReadLine() end
        f:Dispose()
        return table.concat(lines, "\n")
    end
    local SC = nativeRequire("config.StageConfig")
    local Exp = nativeRequire("config.ExpTable")
    local AD = nativeRequire("systems.AttributeDef")
    local function noop() end
    local function stub(fields)
        return setmetatable(fields or {}, { __index = function() return noop end })
    end
    local NORMAL = SC.NORMAL_FIRST_STAGE
    local HARD = SC.getFirstStageId(SC.DIFFICULTY_HARD)
    local NIGHTMARE = SC.getFirstStageId(SC.DIFFICULTY_NIGHTMARE)
    -- 每个夹具重新加载生产模块，不修改源码或玩家存档。
    local function fixture(maxId, ids, unlockAll)
        ids = ids or { NORMAL, NORMAL, NORMAL }
        local battle = { currentStageId = ids[1], maxStageId = maxId,
            teamCurrentStageIds = { ids[1], ids[2], ids[3] }, battleMode = "idle",
            clearedStages = unlockAll == false and {} or { ["905"] = true, ["1905"] = true } }
        local modules = { battle = battle, session = { introCompleted = true, claimedScenarios = {} } }
        local loaded, mocks, drivers, traces, hud = {}, {}, {}, {}, {}
        local gates = { letter = false, intro = false, story = false, sweep = false,
            stats = false, select = false, terminal = false, equipment = false, reward = false }
        local rosterEmpty = {}
        local mountedTeam = 0
        local function record(name, dt, unit)
            traces[#traces + 1] = { name = name, dt = dt, row = mountedTeam, unit = unit }
        end
        local function stateModule(constructor)
            local current = {}
            local m = stub({ mount = function(s) current = s or {} end,
                mountedState = function() return current end, reset = noop })
            m[constructor] = function() return {} end
            return m
        end
        for name, constructor in pairs({
            ["ui.battle.combat.ProjectileSystem"] = "newState",
            ["ui.battle.combat.BattleEffects"] = "newFxState",
            ["systems.ThreatManager"] = "newState",
            ["systems.TalentManager"] = "newBattleRefs",
            ["systems.StatusEffectManager"] = "newSemState",
            ["systems.RelicConditionHandler"] = "newState",
        }) do mocks[name] = stateModule(constructor) end
        local function outlet(moduleName, key, traceName, dtArg)
            mocks[moduleName][key] = function(...)
                local args = { ... }
                record(traceName, args[dtArg or 1])
            end
        end
        outlet("ui.battle.combat.ProjectileSystem", "update", "projectile")
        outlet("ui.battle.combat.BattleEffects", "update", "fx")
        outlet("systems.ThreatManager", "update", "threat")
        outlet("systems.TalentManager", "update", "talent")
        outlet("systems.StatusEffectManager", "update", "status")
        mocks["systems.StatusEffectManager"].isFrozen = function() return false end
        mocks["systems.ArtifactRuntime"] = stub({
            update = function(dt) record("artifact", dt) end,
            onAllyDeath = function() return false end,
        })
        mocks["systems.BattleStats"] = stub({
            mount = function(t) mountedTeam = t or 0 end,
            mountedTeam = function() return mountedTeam end,
        })
        local function unit(heroId)
            local u = { heroId = heroId, monsterId = heroId and nil or 1,
                hp = 10000, maxHp = 10000, atkProgress = 0, attacks = 0 }
            u.attrs = { final = {}, getActualInterval = function() return 1 end,
                tickEnergyShield = function(_, dt) record("shield", dt, u) end,
                takeDamage = function(_, amount) return amount end,
                heal = function(_, amount) return amount end }
            return u
        end
        mocks["config.MonsterConfig"] = { createMonster = function() return unit() end }
        mocks["ui.character.panel.CharacterPanel"] = stub({
            getTeamSignature = function(t) return "speed-team-" .. t end,
            getDeployedTeam = function(t) return rosterEmpty[t] and {} or { unit(t) } end,
        })
        mocks["ui.battle.stage.BattleEnemySpawn"] = stub({
            generateEnemyList = function() return { unit() } end,
            generateIdleEnemyList = function() return { unit() }, 1 end,
            assignEnemiesToField = function(units) return units, {} end,
        })
        mocks["systems.AttributeDef"] = AD
        mocks["config.StageConfig"] = SC
        mocks["shared.StageProvider"] = { Get = function() return SC end }
        mocks["config.ExpTable"] = Exp
        mocks["config.GameConfig"] = nativeRequire("config.GameConfig")
        mocks["shared.battle.BattleSchema"] = nativeRequire("shared.battle.BattleSchema")
        mocks["core.BattleLayout"] = nativeRequire("core.BattleLayout")
        mocks["core.NumberUtil"] = nativeRequire("core.NumberUtil")
        mocks["shared.StageUtils"] = nativeRequire("shared.StageUtils")
        mocks["runtime.ClientDispatcher"] = stub({ get = function(key) return modules[key] end })
        mocks["core.GameState"] = stub()
        mocks["core.I18n"] = stub({ lookup = function(t) return t end,
            format = function(fmt, ...) return string.format(fmt, ...) end })
        mocks["boot.StandaloneSave"] = stub({ Flush = function() return true end })
        mocks["ui.battle.stage.StageEntryEvents"] = stub()
        mocks["ui.battle.scene.BattleAllyReset"] = stub()
        mocks["ui.battle.stage.BattleStageFlow"] = stub({ ensureBattleCards = function() return {} end })
        mocks["ui.battle.stage.BattleStageNav"] = stub({ NAV = {} })
        mocks["ui.battle.stage.StageBerserk"] = stub({ isActive = function() return false end })
        mocks["systems.MapAffixSystem"] = stub({ hasAffixes = function() return false end })
        mocks["systems.BossAffixSystem"] = stub({ hasAffixes = function() return false end })
        mocks["systems.OfflineCalc"] = { resolveIdleStageAnchors = function() return NORMAL, NORMAL end,
            calcOnlineIdleRewards = function() return {} end }
        mocks["systems.BattleTimeout"] = { calcMult = function(elapsed)
            record("timeoutMult", elapsed)
            return 1
        end }
        mocks["ui.battle.scene.BattleDraw"] = stub({
            drawTextStroke = function(_, _, _, text) hud[#hud + 1] = text end,
        })
        mocks["ui.battle.combat.BattleCombatCombo"] = { bind = function() return stub() end }
        for name, key in pairs({
            ["ui.story.gate.LetterIntro"] = "letter", ["ui.story.gate.IntroCutscene"] = "intro",
            ["ui.story.ScenarioDialogue"] = "story", ["ui.battle.stage.SweepDialog"] = "sweep",
            ["ui.battle.popup.DamageStatsPanel"] = "stats", ["ui.battle.stage.StageSelectDialog"] = "select",
            ["ui.battle.popup.TerminalConfirmDialog"] = "terminal",
        }) do
            local gateKey = key
            mocks[name] = stub({ isOpen = function() return gates[gateKey] end,
                isActive = function() return gates[gateKey] end })
        end
        mocks["ui.character.equip.EquipmentBag"] = stub({
            shouldBattleOverlay = function() return gates.equipment end,
            hasOverlayRegion = function() return gates.equipment end,
        })
        mocks["ui.hud.popup.RewardPopup"] = stub({
            currentRowTag = function() return gates.reward and 1 or nil end,
        })
        mocks["ui.battle.popup.BattleResultPanel"] = stub({ isOpen = function() return false end })
        local targets = {
            ["ui.battle.scene.BattleScene"] = true, ["ui.battle.tri.BattleTriPage"] = true,
            ["ui.battle.tri.BattleTriDriver"] = true, ["ui.battle.tri.TerminalRaid"] = true,
            ["ui.battle.stage.BattleSpeed"] = true, ["ui.battle.combat.BattleCombat"] = true,
            ["ui.battle.scene.BattleMountScope"] = true, ["ui.battle.stage.BattleStageLoad"] = true,
            ["ui.battle.stage.BattleStageNavLogic"] = true, ["ui.battle.scene.BattleDataRestore"] = true,
        }
        local env = setmetatable({}, { __index = _G })
        for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgScissor", "nvgIntersectScissor",
            "nvgTranslate", "nvgScale", "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFill",
            "nvgFillPaint", "nvgFillColor", "nvgFontFace", "nvgFontSize", "nvgTextAlign",
            "nvgText", "nvgTextBox" }) do env[name] = noop end
        env.nvgCreateImage = function() return -1 end
        env.nvgImagePattern = function() return {} end
        env.nvgRGBA = function() return {} end
        env.nvgTextBounds = function(_, _, _, text) return #text * 8 end
        env.time = { elapsedTime = 100 }
        local function isolatedRequire(name)
            if mocks[name] then return mocks[name] end
            if loaded[name] then return loaded[name] end
            if targets[name] then
                loaded[name] = assert(load(source(name), "@" .. name, "t", env))()
                return loaded[name]
            end
            mocks[name] = stub()
            return mocks[name]
        end
        env.require = isolatedRequire
        local Combat = isolatedRequire("ui.battle.combat.BattleCombat")
        -- 保留真实攻击进度运算与循环，记录实际Driver传入的每个dt。
        local progress = Combat.advanceAttackProgress
        Combat.advanceAttackProgress = function(u, dt, interval, hasTarget, onAttack)
            record("attack", dt, u)
            return progress(u, dt, interval, hasTarget, onAttack)
        end
        Combat.performAttack = function(u) u.attacks = u.attacks + 1 end
        for key, trace in pairs({ updateComboQueue = "combo", updateCardAnims = "card",
            updateFloatingTexts = "floating", updateHitFlashes = "flash" }) do
            local traceName = trace
            Combat[key] = function(dt) record(traceName, dt) end
        end
        Combat.updateHpBuffers = function(_, dt) record("hpBuffer", dt) end
        Combat.playEnterAnims, Combat.setCardAnim, Combat.clearCardAnim = noop, noop, noop
        local Scene = isolatedRequire("ui.battle.scene.BattleScene")
        Scene.onFirstClear = noop
        Scene.setBattleData(battle) -- 真实恢复让旧Scene停在寻怪阶段。
        local Driver = isolatedRequire("ui.battle.tri.BattleTriDriver")
        local newDriver = Driver.new
        Driver.new = function(t, options)
            local drv = newDriver(t, options)
            drivers[t] = drv
            return drv
        end
        local Page = isolatedRequire("ui.battle.tri.BattleTriPage")
        local Speed = isolatedRequire("ui.battle.stage.BattleSpeed")
        Page.setTeamStageIds(ids)
        Page.open()
        for _, drv in pairs(drivers) do drv.introTimer = 0 end
        local ctx = { Page = Page, Scene = Scene, Driver = Driver, Speed = Speed,
            drivers = drivers, battle = battle, gates = gates, traces = traces, hud = hud,
            rosterEmpty = rosterEmpty, unit = unit, newDriver = newDriver }
        function ctx.clearTraces()
            for i = #traces, 1, -1 do traces[i] = nil end
        end
        function ctx.assertDt(name, row, dt, count)
            local found = 0
            for _, entry in ipairs(traces) do
                if entry.name == name and entry.row == row then
                    found = found + 1
                    near(entry.dt, dt, "row" .. row .. " " .. name .. " dt")
                end
            end
            eq(found, count, "row" .. row .. " " .. name .. " calls")
        end
        function ctx.pageApi(name, fallback, ...)
            local fn = Page[name]
            check(type(fn) == "function", "Page independent API " .. name)
            if type(fn) == "function" then return fn(...) end
            -- 缺接口已计FAIL；回退只暴露旧生产行为，不伪造成功。
            print("[team_battle_speed] BASELINE fallback Scene." .. name .. " (Page API missing)")
            if fallback then return fallback(...) end
            return nil
        end
        function ctx.render()
            for i = #hud, 1, -1 do hud[i] = nil end
            Page.draw({}, 1920, 1080)
            Page.drawHud({}, 1920, 1080)
        end
        function ctx.click(row)
            local x, y, w = Page.getInteriorRectFor(row, 1920, 1080)
            return Page.handleInput(x + w - 4 - 29 - 17, y + 29 + 2)
        end
        return ctx
    end
    -- 先执行真实Page更新：当前基线三队实际均只收到1倍逻辑时钟。
    for _, speed in ipairs({ 1, 1.5, 2 }) do
        run("Page shared clock X" .. speed, function()
            local ctx = fixture(NIGHTMARE, { NORMAL, HARD, NIGHTMARE })
            ctx.Scene.battleSpeed = speed
            ctx.clearTraces()
            ctx.Page.update(0.1)
            for row = 1, 3 do
                local drv = ctx.drivers[row]
                near(drv.allies[1].atkProgress, 0.1 * speed, "Page real ally progress row" .. row)
                near(drv.enemies[1].atkProgress, 0.1 * speed, "Page real enemy progress row" .. row)
                near(drv._timeoutElapsed, 0.1 * speed, "Page timeout row" .. row)
                ctx.assertDt("attack", row, 0.1 * speed, 2)
                for _, name in ipairs({ "status", "threat", "talent", "artifact", "projectile", "combo" }) do
                    ctx.assertDt(name, row, 0.1 * speed, 1)
                end
                ctx.assertDt("shield", row, 0.1 * speed, 2)
                for _, name in ipairs({ "fx", "card", "floating", "flash" }) do
                    ctx.assertDt(name, row, 0.1, 1)
                end
            end
            near(ctx.Scene.battleSpeed, speed, "old searching Scene does not lower shared speed")
        end)
    end
    run("account max versus lagging team/terminal ids", function()
        for _, entry in ipairs({ { NORMAL, 1 }, { HARD, 1.5 }, { NIGHTMARE, 2 },
            { SC.TERMINAL_NORMAL, 1 }, { SC.TERMINAL_HARD, 1.5 }, { SC.TERMINAL_NIGHTMARE, 2 } }) do
            local ctx = fixture(entry[1])
            near(ctx.pageApi("getMaxUnlockedBattleSpeed", ctx.Scene.getMaxUnlockedBattleSpeed),
                entry[2], "account max " .. entry[1] .. " while all current normal")
            near(ctx.Scene.getMaxUnlockedBattleSpeed(), entry[2], "open Scene delegates max")
        end
        local ctx = fixture(HARD)
        ctx.battle.maxStageId = NIGHTMARE
        near(ctx.pageApi("getMaxUnlockedBattleSpeed", ctx.Scene.getMaxUnlockedBattleSpeed), 2, "saved max ahead of Scene")
        ctx.battle.maxStageId = NORMAL
        near(ctx.pageApi("getMaxUnlockedBattleSpeed", ctx.Scene.getMaxUnlockedBattleSpeed), 1.5, "live Scene max ahead of save")
    end)
    run("terminal numeric order cannot lower global cap", function()
        local ctx = fixture(SC.TERMINAL_NIGHTMARE)
        ctx.battle.maxStageId = 4605
        near(ctx.pageApi("getMaxUnlockedBattleSpeed", ctx.Scene.getMaxUnlockedBattleSpeed), 2,
            "live nightmare terminal id2999 remains above saved hard4605")
        near(ctx.Scene.getMaxUnlockedBattleSpeed(), 2, "Scene same terminal partial order")
        ctx.Scene.battleSpeed = 2
        ctx.Page.update(0.1)
        near(ctx.Scene.battleSpeed, 2, "clock does not clamp to lower numeric winner")
        ctx = fixture(4605)
        ctx.battle.maxStageId = SC.TERMINAL_NIGHTMARE
        near(ctx.pageApi("getMaxUnlockedBattleSpeed", ctx.Scene.getMaxUnlockedBattleSpeed), 2,
            "saved nightmare terminal id2999 remains above live hard4605")
    end)
    run("clamp once and lower account max", function()
        local ctx = fixture(NIGHTMARE)
        local clockCalls = 0
        if type(ctx.Page.getBattleLogicDt) == "function" then
            local clock = ctx.Page.getBattleLogicDt
            ctx.Page.getBattleLogicDt = function(dt) clockCalls = clockCalls + 1 return clock(dt) end
        else
            check(false, "Page getBattleLogicDt missing; observe real update regardless")
        end
        ctx.Scene.battleSpeed = 2
        ctx.battle.maxStageId = HARD
        ctx.Scene.setBattleData(ctx.battle)
        ctx.clearTraces()
        ctx.Page.update(0.1)
        near(ctx.Scene.battleSpeed, 1.5, "lower highest difficulty clamps global selection")
        eq(clockCalls, 1, "Page computes one logic dt per frame, not three")
        for row = 1, 3 do ctx.assertDt("attack", row, 0.15, 2) end
        ctx.battle.maxStageId = NORMAL
        ctx.Scene.setBattleData(ctx.battle)
        ctx.Page.update(0.1)
        near(ctx.Scene.battleSpeed, 1, "normal downgrade clamps to X1")
    end)
    run("Page and compatibility Scene API independent of searching", function()
        local ctx = fixture(NIGHTMARE)
        ctx.Scene.battleSpeed = 2
        eq(ctx.pageApi("isSpeedButtonVisible", ctx.Scene.isSpeedButtonVisible), true, "real active rows despite searching")
        eq(ctx.Scene.isSpeedButtonVisible(), true, "open Scene delegates visibility")
        near(ctx.pageApi("getBattleLogicDt", ctx.Scene.getBattleLogicDt, 0.125), 0.25, "Page independent clock")
        near(ctx.Scene.getBattleLogicDt(0.125), 0.25, "open Scene delegates clock")
        ctx.Page.close()
        near(ctx.Scene.getMaxUnlockedBattleSpeed(), 1, "closed Scene retains current-stage unlock")
        eq(ctx.Scene.isSpeedButtonVisible(), false, "closed searching Scene keeps old gate")
        near(ctx.Scene.getBattleLogicDt(0.125), 0.125, "closed Scene old default dt")
        near(ctx.Scene.battleSpeed, 1, "closed Scene old clamp")
    end)
    run("real row2/row3 HUD clicks share global selection", function()
        local ctx = fixture(NIGHTMARE)
        ctx.render()
        eq(#ctx.hud, 3, "one real BattleSpeed label per unlocked row")
        for _, text in ipairs(ctx.hud) do eq(text, "X1", "initial global HUD label") end
        check(ctx.click(2), "row2 click consumed")
        near(ctx.Scene.battleSpeed, 1.5, "row2 increments shared speed")
        ctx.render()
        eq(#ctx.hud, 3, "three HUD labels after row2")
        for _, text in ipairs(ctx.hud) do eq(text, "X1.5", "all rows share row2 change") end
        check(ctx.click(3), "row3 click consumed")
        near(ctx.Scene.battleSpeed, 2, "row3 increments same speed")
        ctx.render()
        for _, text in ipairs(ctx.hud) do eq(text, "X2", "all rows share row3 change") end
        check(ctx.click(1), "row1 cycle consumed")
        near(ctx.Scene.battleSpeed, 1, "global cycle returns X1")
    end)
    run("empty/locked/inactive rows cannot enable speed", function()
        local ctx = fixture(NIGHTMARE)
        for _, drv in pairs(ctx.drivers) do drv.allies = {} end
        eq(ctx.pageApi("isSpeedButtonVisible", ctx.Scene.isSpeedButtonVisible), false, "all empty rows hidden")
        ctx.battle.maxStageId, ctx.battle.clearedStages = NORMAL, {}
        ctx.Scene.setBattleData(ctx.battle)
        ctx.drivers[2].allies, ctx.drivers[3].allies = { ctx.unit(2) }, { ctx.unit(3) }
        ctx.render()
        ctx.Scene.battleSpeed = 1
        ctx.click(2)
        near(ctx.Scene.battleSpeed, 1, "locked row cannot change shared speed")
        eq(ctx.pageApi("isSpeedButtonVisible", ctx.Scene.isSpeedButtonVisible), false, "locked populated rows do not qualify")
        ctx.battle.maxStageId = NIGHTMARE
        ctx.Scene.setBattleData(ctx.battle)
        ctx.drivers[2].active, ctx.drivers[3].active = false, false
        eq(ctx.pageApi("isSpeedButtonVisible", ctx.Scene.isSpeedButtonVisible), false, "inactive rows do not qualify")
        ctx.drivers[3].active = true
        eq(ctx.pageApi("isSpeedButtonVisible", ctx.Scene.isSpeedButtonVisible), true, "single qualifying row3 enables shared button")
    end)
    run("intro/march real time with no timeout acceleration", function()
        local ctx = fixture(NIGHTMARE)
        for row = 1, 3 do
            local drv = ctx.drivers[row]
            drv._timeoutElapsed, drv.introTimer = 0, 0.3
            drv:update(0.1, 0.2)
            near(drv.introTimer, 0.2, "intro real duration row" .. row)
            near(drv._timeoutElapsed, 0, "intro excludes combat timeout row" .. row)
            near(drv.allies[1].atkProgress, 0, "intro no attacks row" .. row)
            drv.introTimer, drv.enemies, drv.enemyQueue = 0, {}, {}
            drv:beginMarch()
            drv._timeoutElapsed = 0
            drv:tick(0.1, 0.2)
            near(drv.marchTimer, 1.9, "march real duration row" .. row)
            near(drv._timeoutElapsed, 0, "march excludes combat timeout row" .. row)
        end
        eq(ctx.pageApi("isSpeedButtonVisible", ctx.Scene.isSpeedButtonVisible), false, "all marching rows hide speed")
    end)
    run("explicit Driver logical dt; reinforcement and reward cadence", function()
        local ctx = fixture(NIGHTMARE)
        local drv = ctx.drivers[2]
        ctx.Scene.battleSpeed = 2
        drv.rewardQueue = { {}, {}, {} }
        local drops = 0
        drv.onDrop = function() drops = drops + 1 end
        drv.rewardTimer = 0
        drv:update(0.03, 0.06)
        eq(drops, 0, "reward waits real 0.05 rather than logical 0.06")
        near(drv.rewardTimer, 0.03, "reward uses real dt")
        near(drv.allies[1].atkProgress, 0.06, "explicit update forwards logic dt")
        local fallen, nextEnemy = ctx.unit(), ctx.unit()
        fallen.hp, fallen.reviveTimer = 0, 0.9
        drv.enemies, drv.enemyQueue, drv.reinforceCd = { fallen, ctx.unit() }, { nextEnemy }, 0
        drv:tick(0.06, 0.12)
        check(drv.enemies[2] == nextEnemy and #drv.enemyQueue == 0,
            "dead enemy refill reaches 1s by logical dt")
        eq(drops, 1, "rewards use accumulated real 0.09")
    end)
    run("modal hides UI without resetting battle clock; story early return", function()
        local ctx = fixture(NIGHTMARE)
        for _, key in ipairs({ "sweep", "stats", "select", "terminal", "equipment", "reward" }) do
            ctx.gates[key] = true
            ctx.Scene.battleSpeed = 2
            eq(ctx.pageApi("isSpeedButtonVisible", ctx.Scene.isSpeedButtonVisible), false, key .. " hides speed")
            near(ctx.pageApi("getBattleLogicDt", ctx.Scene.getBattleLogicDt, 0.1), 0.2, key .. " does not reset selected logic speed")
            ctx.gates[key] = false
        end
        for _, key in ipairs({ "letter", "intro", "story" }) do
            ctx.gates[key] = true
            ctx.clearTraces()
            local before = ctx.drivers[1].allies[1].atkProgress
            ctx.Page.update(0.1)
            eq(#ctx.traces, 0, key .. " Page early return before all subsystem updates")
            near(ctx.drivers[1].allies[1].atkProgress, before, key .. " blocks real progress")
            ctx.gates[key] = false
        end
    end)
    run("terminal shared elapsed once and timeout window scales with attacks", function()
        local previous = SC.getTerminalPrevStageId(SC.TERMINAL_NIGHTMARE)
        local ctx = fixture(previous, { previous, previous, previous })
        ctx.Scene.getClearedStages()[previous] = true
        ctx.battle.clearedStages[tostring(previous)] = true
        check(ctx.Page.gotoTeamStage(2, SC.TERMINAL_NIGHTMARE), "real Page enters shared raid")
        local raid = ctx.drivers[2].terminalRaid
        check(raid ~= nil, "real TerminalRaid attached")
        if not raid then return end
        for _, drv in pairs(ctx.drivers) do drv.introTimer = 0 end
        ctx.Scene.battleSpeed = 2
        eq(ctx.pageApi("isSpeedButtonVisible", ctx.Scene.isSpeedButtonVisible), false, "raid hides button")
        ctx.clearTraces()
        ctx.Page.update(0.1)
        near(raid.elapsed, 0.2, "raid elapsed one shared logical step, not three or real")
        near(ctx.Scene.battleSpeed, 2, "raid retains chosen global selection")
        for row = 1, 3 do ctx.assertDt("attack", row, 0.2, 2) end
        local limit = nativeRequire("config.GameConfig").Battle.TIME_LIMIT_SEC
        raid.elapsed = limit - 0.15
        ctx.Page.update(0.1)
        eq(raid.finished, true, "logical timeout crosses fixed time limit in one real frame")
        eq(raid.won, false, "clock does not expand terminal victory window")
    end)
    run("legacy single-argument Driver and battleLab do not read global speed", function()
        local ctx = fixture(NIGHTMARE)
        ctx.Scene.battleSpeed = 2
        local drv = ctx.drivers[2]
        drv:update(0.1)
        near(drv.allies[1].atkProgress, 0.1, "normal one-arg update remains caller-owned dt")
        local lab = ctx.newDriver(2, { battleLab = true, allyFactory = function() return { ctx.unit(2) } end })
        lab:start(HARD)
        lab.introTimer = 0
        local saved = { ctx.Page.getTeamStageIds()[1], ctx.Page.getTeamStageIds()[2], ctx.Page.getTeamStageIds()[3] }
        lab:update(0.1)
        near(lab.allies[1].atkProgress, 0.1, "battleLab one-arg attack remains X1")
        near(lab._labElapsed, 0.1, "battleLab elapsed old semantics")
        near(lab._timeoutElapsed, 0.1, "battleLab timeout old semantics")
        lab:tick(0.1)
        near(lab.allies[1].atkProgress, 0.2, "battleLab one-arg tick never multiplies global")
        for row = 1, 3 do eq(ctx.Page.getTeamStageIds()[row], saved[row], "lab does not mutate normal row" .. row) end
    end)
    run("real BattleSpeed old visibility/default helper contract", function()
        local ctx = fixture(NIGHTMARE)
        near(ctx.Speed.getMaxUnlocked(SC.DIFFICULTY_NORMAL), 1, "normal helper cap")
        near(ctx.Speed.getMaxUnlocked(SC.DIFFICULTY_HARD), 1.5, "hard helper cap")
        near(ctx.Speed.getMaxUnlocked(SC.DIFFICULTY_NIGHTMARE), 2, "nightmare helper cap")
        local dt, selected = ctx.Speed.getLogicDt(0.1, 2, 1.5, false)
        near(dt, 0.1, "old helper hidden uses real dt")
        near(selected, 1.5, "old helper still clamps selection")
        check(ctx.Speed.hitTest(987, 311) and not ctx.Speed.hitTest(0, 0), "real speed hit test")
    end)
    print(string.format("[team_battle_speed] RESULT cases=%d casesFailed=%d checks=%d failures=%d (real Page/Driver/Scene/Speed/attack progress)",
        cases, brokenCases, checks, failures))
    if failures == 0 then print("[team_battle_speed] ALL PASS")
    else log:Write(LOG_ERROR, "[team_battle_speed] FAIL " .. failures .. " checks") end
    engine:Exit()
end
