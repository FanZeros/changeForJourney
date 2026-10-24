-- 无进攻能力跨宿主专项：真实 Guard / TerminalRaid / Page / Tower / Dungeon / 兼容 Scene。
-- 能力结论为显式 Cap.inspect 叶子 spy；真实能力分类/普通 Driver 由 no_offense_defeat_test 覆盖。
-- 不复制生产判败条件；完整 cache 源码在私有 env 中加载，保存/发奖/UI/攻击为明确外围 spy。
-- 不加载 main，不通过原生 File/FS/cloud，不用旧 dist 结果声称最新源已通过。
-- 统一官方 build 后独立 Runtime 执行；必须同时检查 ALL PASS 与实际进程退出码。
function Start()
    local TAG = "[no_offense_hosts_test] "
    local cases, checks, failures = 0, 0, 0
    local sources = {} ---@type table
    local fixtures = {} ---@type table[]
    local function noop() end
    local function check(value, message)
        checks = checks + 1
        assert(value, message)
    end
    local function eq(actual, expected, message)
        check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
    end
    ---@param path string
    ---@return string
    local function read(path)
        if sources[path] then return sources[path] end
        local file = assert(cache:GetFile(path), "missing production resource " .. path)
        local ok, text = pcall(function()
            local lines = {} ---@type string[]
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            return table.concat(lines, "\n")
        end)
        file:Dispose()
        assert(ok, text)
        sources[path] = text
        return text
    end
    local function compile(path, env)
        return assert(load(read(path), "@resource:" .. path, "t", env))()
    end
    local function slot(fn, key, replacement, write)
        for index = 1, 200 do
            local name, value = debug.getupvalue(fn, index)
            if not name then break end
            if name == key then
                if write then debug.setupvalue(fn, index, replacement) end
                return value
            end
        end
        error("missing real closure upvalue " .. key)
    end
    local function get(fn, key) return slot(fn, key) end
    local function set(fn, key, value) return slot(fn, key, value, true) end
    local function run(name, fn)
        cases = cases + 1
        local ok, err = xpcall(fn, debug.traceback)
        if ok then print(TAG .. "PASS " .. name)
        else failures = failures + 1; print(TAG .. "FAIL " .. name .. " " .. tostring(err)) end
    end
    local function fixture()
        local f = { io = 0, actions = 0, saves = 0, wins = 0, defeats = 0, flushes = 0,
            scopeRuns = 0, elapsed = 0, trace = {}, logs = {}, capRecords = {}, proven = {},
            clock = { elapsedTime = 100 }, mods = {}, loaded = {}, split = {},
            controls = { paused = false, entering = false, timeLimit = false, dummy = false },
            cfg = { dungeonId = "gold_mine", teamIdx = 1, resourceCombat = false } } ---@type table
        fixtures[#fixtures + 1] = f
        local mods = f.mods ---@type table
        local function denied()
            f.io = f.io + 1
            error("native IO/network forbidden in no-offense fixture")
        end
        local env = { assert = assert, error = error, type = type, tonumber = tonumber, tostring = tostring,
            pairs = pairs, ipairs = ipairs, next = next, select = select, pcall = pcall, xpcall = xpcall,
            setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset,
            rawequal = rawequal, math = {}, string = string, table = table, utf8 = utf8,
            print = noop, time = f.clock } ---@type table
        for key, value in pairs(math) do env.math[key] = value end
        env.math.random, env.math.randomseed = denied, denied
        env._G = env
        for _, key in ipairs({ "File", "GetFileSystem", "GetCache", "GetEngine", "loadfile", "dofile",
            "SendEvent", "SubscribeToEvent", "UnsubscribeFromEvent" }) do env[key] = denied end
        for _, key in ipairs({ "fileSystem", "cache", "engine", "io", "os", "package", "network",
            "clientCloud", "serverCloud" }) do
            env[key] = setmetatable({}, { __index = denied, __newindex = denied })
        end
        env.print = function(...)
            local values = {} ---@type string[]
            for index = 1, select("#", ...) do values[index] = tostring(select(index, ...)) end
            local line = table.concat(values, " ")
            f.logs[#f.logs + 1] = line
            -- 本专项无预期生产异常，已知pcall日志不能被noop吞掉误判业务通过。
            local lower = line:lower()
            if lower:find(" failed", 1, true) or lower:find("failure:", 1, true)
                or lower:find("error:", 1, true) or line:find("异常", 1, true) then
                error("unexpected production diagnostic " .. line)
            end
        end
        env.require = function(name)
            return assert(mods[name], "unprepared dependency " .. tostring(name))
        end
        f.env = env
        f.load = function(name)
            if f.loaded[name] then return f.loaded[name] end
            local result = compile(name:gsub("%.", "/") .. ".lua", env)
            mods[name], f.loaded[name] = result, result
            return result
        end
        f.record = function(value) f.trace[#f.trace + 1] = value end
        local function scoped(label)
            local current = { ctx = {}, comboQueue = {}, cardAnims = {} } ---@type table
            local api = {} ---@type table
            api.newState = function() return { ctx = {}, comboQueue = {}, cardAnims = {} } end
            api.newFxState, api.newSemState, api.newBattleRefs = api.newState, api.newState, api.newState
            api.mount = function(value) current = value or { ctx = {}, comboQueue = {}, cardAnims = {} } end
            api.mountedState = function() return current end
            api.reset = noop
            api.init, api.initUnit, api.initBattle, api.onBattleStart = noop, noop, noop, noop
            api.setRenderScale = noop
            api.setContext = function(value) current.ctx = value end
            api.update = function(dt)
                f.record(label)
                if f.onUpdate then f.onUpdate(label, dt, current) end
            end
            return api
        end
        local bc, ps, sem, tal, ets, tm, fx, rch = scoped("combat"), scoped("projectile"), scoped("status"),
            scoped("talent"), scoped("growth"), scoped("threat"), scoped("effects"), scoped("relic")
        bc.DEATH_ANIM_DURATION, bc.REVIVE_ANIM_DURATION = .4, .35
        bc.getAliveUnits = function(list)
            local result = {} ---@type table[]
            for _, unit in ipairs(list) do if unit.hp > 0 then result[#result + 1] = unit end end
            return result
        end
        bc.getCardCX, bc.getCardPos = function() return 100 end, function() return 100, 180 end
        bc.syncUnitHp = function(unit) unit.hp = unit.attrs.final.hp end
        bc.advanceAttackProgress = noop -- 不替代宿主时序；具体攻击能力在主专项真链验证。
        bc.performAttack, bc.dealDamageToUnit, bc.dealTalentDamage = noop, noop, noop
        bc.onTalentDealDamage, bc.addCombatNumber, bc.addFloatingText = noop, noop, noop
        bc.clearFloatingTexts, bc.updateHpBuffers = noop, noop
        bc.playEnterAnims = function(units)
            for _, unit in ipairs(units) do bc.mountedState().cardAnims[unit] = { state = "entering" } end
        end
        bc.updateComboQueue = function(dt)
            f.record("combo")
            if f.onCombo then f.onCombo(dt, bc.mountedState()) end
        end
        bc.updateCardAnims, bc.updateFloatingTexts, bc.updateHitFlashes = noop, noop, noop
        bc.setCardAnim = function(unit, value) bc.mountedState().cardAnims[unit] = value end
        bc.clearCardAnim = function(unit) bc.mountedState().cardAnims[unit] = nil end
        bc.clearHitFlash = noop
        bc.getAnimState = function(unit)
            if f.controls.entering then return "entering" end
            local value = bc.mountedState().cardAnims[unit] ---@type table|nil
            return value and value.state or "idle"
        end
        bc.hasEnteringUnits = function() return f.controls.entering end
        ps.hasHeroEffect, ps.hasMonsterProjectile = function() return false end, function() return false end
        ps.spawn, ps.spawnByKey = noop, noop
        sem.isFrozen = function() return false end
        sem.removeUnit, sem.apply = noop, noop
        tal.onEnemyDeath, tal.resetEnemyDeath, tal.checkMarkTarget = noop, noop, noop
        tal.onAllyDeath = function(unit, allies, sync)
            f.record("talent-revive")
            if f.reviveTalent then return f.reviveTalent(unit, allies, sync) end
            return false
        end
        local unitStates = {} ---@type table
        tal.newUnitStates = function() return {} end
        tal.mountUnitStates = function(value) unitStates = value end
        tal.mountedUnitStates = function() return unitStates end
        tal.update = function(dt, allies, enemies)
            f.record("talent")
            if f.onTalent then f.onTalent(dt, allies, enemies) end
        end
        ets.flush = function() f.flushes = f.flushes + 1 end
        ets.discard = noop
        tm.removeUnit = noop
        mods["ui.battle.combat.BattleCombat"], mods["ui.battle.combat.ProjectileSystem"] = bc, ps
        mods["systems.StatusEffectManager"], mods["systems.TalentManager"] = sem, tal
        mods["systems.ExtraTalentSystem"], mods["systems.ThreatManager"] = ets, tm
        mods["ui.battle.combat.BattleEffects"], mods["systems.RelicConditionHandler"] = fx, rch
        mods["systems.ArtifactRuntime"] = { reset = noop, initBattle = noop, update = noop,
            onAllyDeath = function(unit)
                f.record("artifact-revive")
                if f.reviveArtifact then return f.reviveArtifact(unit) end
                return false
            end }
        mods["systems.CombatFormula"] = { calcHpRegen = function() return 0 end }
        mods["systems.AttributeDef"] = { HP = "hp", MAX_HP = "maxHp", COMBO_RATE = "combo", ATK_FIRE = 4, ATK_HOLY = 8 }
        mods["core.BattleLayout"] = { CARD_W = 198, CARD_H = 351, CARD_SCALE = .48,
            STRIP_W = 948, STRIP_H = 360, STRIP_CY = 180, FIELD_CY = 180,
            MAX_PER_SIDE = 4, MODE = "strip", setMode = function(value) mods["core.BattleLayout"].MODE = value end }
        local statsTeam = 0
        mods["systems.BattleStats"] = { reset = noop, update = noop,
            mount = function(value) statsTeam = value end, mountedTeam = function() return statsTeam end,
            buildHeroDamageStats = function() return {} end }
        mods["ui.battle.combat.BattleClock"] = { now = function() return f.clock.elapsedTime end }
        mods["systems.BattleTimeout"] = { calcMult = function() return 1 end }
        mods["ui.battle.scene.BattleAllyReset"] = { compactFallen = noop, restoreOrder = noop, resetAllyUnit = noop }
        mods["ui.fx.SpineCardEffect"] = { playRevive = noop }
        mods["ui.battle.scene.BattlePauseOverlay"] = { init = noop, draw = noop }
        mods["ui.battle.scene.BattleView"] = { init = noop, draw = noop }
        mods["ui.battle.scene.BattleDraw"] = { drawTextStroke = noop, drawImageCentered = noop,
            drawImageMirrored = noop, drawCardGroup = noop, drawFloatingTexts = noop }
        mods["ui.battle.popup.BattleResultPanel"] = { init = noop, update = noop, draw = noop,
            isOpen = function() return false end,
            show = function(value) f.result = value end }
        mods["ui.battle.popup.DamageStatsPanel"] = { isOpen = function() return false end, close = noop }
        mods["ui.hud.popup.SettingsPanel"] = { isEffectsEnabled = function() return false end,
            isDamageNumbersEnabled = function() return false end }
        mods["systems.ButtonFeedback"] = { trigger = noop }
        mods["core.DarkIcon"], mods["core.DrawUtil"] = {}, {}
        mods["core.NumberUtil"] = { format = tostring }
        mods["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 } }
        mods["config.HeroConfig"] = { HEROES = {} }
        mods["shared.Protocol"] = {}
        mods["core.PlayerStore"] = { Get = function() return {} end }
        mods["runtime.GameAction"] = { sendAction = function() f.actions = f.actions + 1; error("action forbidden") end }
        mods["boot.StandaloneSave"] = { Flush = function() f.saves = f.saves + 1; return true end,
            RequestSave = function() f.saves = f.saves + 1 end }
        mods["systems.MapAffixSystem"] = { reset = noop, tick = noop, onStageLoad = noop,
            applyStaticAffixes = noop, hasAffixes = function() return false end }
        mods["systems.BossAffixSystem"] = { clear = noop, tick = noop, onStageLoad = noop,
            applyToBosses = noop, hasAffixes = function() return false end }
        mods["config.StageConfig"] = { NORMAL_FIRST_STAGE = 101,
            isTerminalTemple = function(id) return id == 999 end,
            isResourceStage = function(id) return id >= 100000 end,
            getStage = function(id) return { id = id, name = "test", monsterLevel = 1, chapter = 1 } end,
            getStageDisplayName = function() return "test" end,
            getTerminalPrevStageId = function() return 2305 end,
            getDifficulty = function() return "normal" end }
        mods["config.DungeonConfig"] = { DEFINITIONS = {}, isStageUnlocked = function() return true end }
        mods["ui.dungeon.DungeonRewards"] = { build = function() return {} end, overflowText = function() return nil end }
        mods["ui.dungeon.DungeonCombatRuntime"] = { getScopedModules = function() return {} end,
            getBerserk = function() return { enter = noop, update = noop, exit = noop } end }
        mods["ui.dungeon.DungeonBattle"] = {
            enter = function(data) f.cfg = data end, exit = noop,
            getConfig = function() return f.cfg end, getElapsed = function() return f.elapsed end,
            update = function(dt) f.elapsed = f.elapsed + dt; f.record("dungeon-clock") end,
            isTrainingDummy = function() return f.controls.dummy end,
            isTimeLimitExceeded = function() return f.controls.timeLimit end,
            getAtkIntervalMultiplier = function() return 1 end,
            onEnemyKill = noop, onAllyDeath = noop,
            onVictory = function() f.wins = f.wins + 1; f.record("win") end,
            onDefeat = function(reason) f.defeats = f.defeats + 1; f.defeatReason = reason; f.record("defeat") end,
            isResultReady = function() return true end,
            getResultState = function() return true, f.wins > 0, f.elapsed, {} end }
        mods["systems.TowerBuffRuntime"] = { update = noop }
        mods["ui.tower.TowerWaveSplit"] = { splitToLanes = function() return f.split end }
        mods["ui.tower.TowerLayout"], mods["ui.tower.TowerBuffSidebar"], mods["ui.tower.TowerPresentation"] = {}, {}, {}
        mods["ui.battle.combat.BattleCombatAnim"] = { ENTRY_DURATION = .3 }
        mods["ui.battle.scene.BattleMountScope"] = { wrap = noop,
            run = function(fn, ...) return fn(...) end, mountDefault = noop }
        -- 能力分类只是一张预设真值表。宿主/Guard/raid函数正文全部来自实际资源，不在此重写。
        mods["systems.BattleOffenseCapabilities"] = { inspect = function(lane)
            local record = { lane = lane, traceLength = #f.trace } ---@type table
            f.capRecords[#f.capRecords + 1] = record
            for _, key in ipairs({ "allies", "enemies", "combatState", "projectileState", "semState",
                "talentStates", "talentRefs", "etsState" }) do
                check(type(lane[key]) == "table", "host supplied actual lane state " .. key)
            end
            f.record("inspect")
            if f.onInspect then f.onInspect(lane) end
            return f.proven[lane.allies]
        end }
        mods["systems.DropSystem"] = {}
        mods["systems.BattleDiag"] = { update = noop, installSentinel = noop, scanNow = noop }
        mods["ui.widget.SpeechBubble"] = { update = noop, trigger = noop }
        mods["ui.hud.BottomNav"] = {}
        mods["config.TowerConfig"] = { BUFFS = {}, BUFFS_BY_ID = {} } -- registry叶子边界，不冒称全塔强化能力验收。
        f.load("ui.battle.scene.BattleAllyLifecycle")
        f.guard = f.load("systems.BattleOffenseGuard")
        f.unit = function(hp)
            local attrs = { final = { hp = hp or 100, maxHp = 100 }, tickEnergyShield = noop } ---@type table
            attrs.fillHp = function(self) self.final.hp = self.final.maxHp end
            attrs.heal = function(self, amount)
                local actual = math.min(amount, self.final.maxHp - self.final.hp)
                self.final.hp = self.final.hp + actual
                return actual
            end
            attrs.takeDamage = function(self, amount)
                local actual = math.min(self.final.hp, amount)
                self.final.hp = self.final.hp - actual
                return actual
            end
            return { hp = hp or 100, maxHp = 100, attrs = attrs, atkProgress = 0, atkInterval = 1000 }
        end
        f.lane = function(row)
            local lane = { teamIdx = row, allies = { f.unit() }, enemies = { f.unit() }, queue = {},
                enemyQueue = {}, cleared = false, wiped = false, active = true, introTimer = 0,
                combatState = bc.newState(), psState = ps.newState(), semState = sem.newSemState(),
                talRefs = tal.newBattleRefs(), talUnitStates = {}, etsState = ets.newState(),
                tmState = tm.newState(), beState = fx.newFxState(), rchState = rch.newState(), regenAccum = 0 } ---@type table
            f.proven[lane.allies] = true
            return lane
        end
        f.step = function(host, dt, paused)
            f.clock.elapsedTime = f.clock.elapsedTime + dt
            host.update(dt, paused)
        end
        return f
    end

    local function offenseLane(lane)
        return { allies = lane.allies, enemies = lane.enemies, combatState = lane.combatState,
            projectileState = lane.psState, semState = lane.semState, talentStates = lane.talUnitStates,
            talentRefs = lane.talRefs, etsState = lane.etsState }
    end
    local function pageFixture()
        local f = fixture() ---@type table
        local mods = f.mods ---@type table
        for _, name in ipairs({ "ui.hud.popup.RewardPopup", "ui.battle.stage.SweepDialog",
            "ui.battle.stage.StageSelectDialog", "ui.widget.SoundToggle", "ui.character.equip.EquipmentBag" }) do
            mods[name] = {}
        end
        mods["config.ExpTable"] = { TEAM_COUNT = 3, getUnlockedTeamCount = function() return 3 end }
        local battle = { currentStageId = 101, teamStageIds = { 101, 101, 101 } } ---@type table
        mods["runtime.ClientDispatcher"] = { get = function() return battle end, notifySubscribers = noop }
        mods["core.I18n"] = { lookup = function(value) return value end }
        mods["ui.battle.popup.TerminalConfirmDialog"] = { update = noop }
        mods["ui.battle.tri.BattleEntryPreparation"] = { new = function()
            return { invalidate = noop, isPrepared = function() return true end }
        end }
        mods["ui.battle.tri.TerminalReincarnation"] = { discardDriver = noop,
            captureOrigins = function() return {} end, safeStage = function(id) return id end,
            settleVictory = function() f.wins = f.wins + 1 end,
            retreat = function(raid)
                f.defeats = f.defeats + 1; f.defeatReason = raid.failureReason
            end }
        mods["ui.battle.scene.BattleScene"] = { getStageId = function() return 101 end,
            updateTriReincarnation = noop }
        mods["ui.story.gate.LetterIntro"] = { isOpen = function() return f.controls.paused end }
        mods["ui.story.gate.IntroCutscene"] = { isActive = function() return false end }
        mods["ui.story.ScenarioDialogue"] = { isActive = function() return false end }
        local raidModule = f.load("ui.battle.tri.TerminalRaid") ---@type table
        local page = f.load("ui.battle.tri.BattleTriPage") ---@type table
        local drivers = get(page.update, "drivers") ---@type table
        for row = 1, 3 do
            local lane = f.lane(row) ---@type table
            lane.stageId, lane._syncedMainStage, lane._offenseEligible = 101, 101, true
            lane.getOffenseLane = offenseLane
            lane.activate, lane.reportDefeatedEnemies = noop, noop
            lane.update = function(self, dt, logicDt)
                eq(dt, logicDt, "Page uses real dt for each lane")
                f.record("driver" .. self.teamIdx)
                if f.onDriver then f.onDriver(self, dt) end
            end
            drivers[row] = lane
        end
        for _, lane in ipairs(drivers) do lane.stageId = 999; lane._syncedMainStage = 999 end
        local raid = raidModule.new(999, drivers) ---@type table
        for _, lane in ipairs(drivers) do lane.terminalRaid = raid end
        set(page.update, "terminalRaid", raid)
        set(page.update, "isOpen_", true)
        -- ensureDrivers保留真实代码，但一队stage与Scene一致，避免无关外部切关同步。
        mods["ui.battle.scene.BattleScene"].getStageId = function() return 999 end
        f.page, f.raid, f.drivers = page, raid, drivers
        return f
    end
    run("Page three drivers update before one shared five-second grace", function()
        local f = pageFixture() ---@type table
        local calls = 0
        local original = f.raid.updateOffense
        f.raid.updateOffense = function(self, dt, eligible)
            calls = calls + 1
            eq(f.trace[#f.trace - 2], "driver1", "driver1 updated before shared check")
            eq(f.trace[#f.trace - 1], "driver2", "driver2 updated before shared check")
            eq(f.trace[#f.trace], "driver3", "driver3 updated before shared check")
            return original(self, dt, eligible)
        end
        f.step(f.page, .5)
        eq(f.raid._noOffenseElapsed, 0, "first observed frame only establishes baseline")
        for _ = 1, 9 do f.step(f.page, .5) end
        check(not f.raid.finished, "three drivers do not triple-count grace")
        eq(f.raid._noOffenseElapsed, 4.5, "shared grace consumes one real dt per frame")
        f.step(f.page, .5)
        eq(calls, 11, "exactly one shared update per active frame")
        check(f.raid.finished and not f.raid.won, "all lines incapable reaches shared loss")
        eq(f.raid.failureReason, "no_offense", "independent shared failure reason")
        eq(f.defeats, 0, "normal failure hold retained at first failure observation")
        for _, driver in ipairs(f.drivers) do
            eq(driver.allies[1].hp, 100, "no-offense loss never sets living ally HP to zero")
        end
        f.step(f.page, .5)
        eq(f.defeats, 0, "raid remains through original one-second hold")
        f.step(f.page, .5)
        eq(f.defeats, 1, "original retreat settlement runs once after hold")
        eq(f.defeatReason, "no_offense", "reason survives normal settlement boundary")
        eq(f.wins, 0, "no victory or rewards fabricated")
    end)
    run("Page any living attacking line prevents shared loss and restores fresh grace", function()
        local f = pageFixture() ---@type table
        f.proven[f.drivers[3].allies] = false
        for _ = 1, 20 do f.step(f.page, .5) end
        check(not f.raid.finished, "one capable line keeps cooperative raid alive")
        eq(f.raid._noOffenseElapsed, nil, "capable line clears all earlier shared grace")
        f.proven[f.drivers[3].allies] = true
        f.step(f.page, .5)
        for _ = 1, 9 do f.step(f.page, .5) end
        check(not f.raid.finished, "capability loss receives its own complete fresh grace")
        f.step(f.page, .5)
        eq(f.raid.failureReason, "no_offense", "only later all-line incapability fails")
    end)
    run("Page last driver can restore offense or finish victory before shared decision", function()
        for _, mode in ipairs({ "offense", "victory", "revival" }) do
            local f = pageFixture() ---@type table
            f.step(f.page, .1)
            f.step(f.page, 4.5)
            f.onDriver = function(driver)
                if driver.teamIdx ~= 3 then return end
                if mode == "victory" then
                    for _, pool in ipairs(f.raid.pools) do pool.hp = 0 end
                    f.raid:sync()
                else
                    if mode == "revival" then
                        driver.allies[1].hp = 100
                        driver.allies[1].attrs.final.hp = 100
                    end
                    f.proven[driver.allies] = false
                end
            end
            f.step(f.page, .5)
            if mode == "victory" then
                check(f.raid.finished and f.raid.won, "last line shared-pool victory wins race")
                eq(f.wins, 1, "victory boundary called exactly once")
            else
                check(not f.raid.finished, "last driver " .. mode .. " cancels failure")
                eq(f.raid._noOffenseElapsed, nil, "last driver capability is observed after update")
            end
            eq(f.raid.failureReason, nil, "no late failure reason on " .. mode)
            eq(f.defeats, 0, "no defeat settlement on " .. mode)
        end
    end)
    run("Page entry and story pause exclude time and discard partial grace", function()
        local f = pageFixture() ---@type table
        f.drivers[2].introTimer = .3
        for _ = 1, 3 do f.step(f.page, 20) end
        eq(f.raid._noOffenseElapsed, nil, "intro time never starts offense grace")
        eq(f.raid.elapsed, 0, "intro time never enters raid clock")
        f.drivers[2].introTimer = 0
        f.step(f.page, .1)
        f.step(f.page, 4)
        f.controls.paused = true
        f.step(f.page, 100)
        f.controls.paused = false
        f.step(f.page, .1)
        check(not f.raid.finished, "story pause does not reach no-offense timeout")
        -- 暂停前累计是否reset由真实宿主契约决定；后续恢复不能倒算100秒。
        check((f.raid._noOffenseElapsed or 0) <= 4.1, "pause real time excluded on resumption")
        f.drivers[1]._offenseEligible = false
        f.step(f.page, 100)
        eq(f.raid._noOffenseElapsed, nil, "a noneligible lane resets shared grace")
        check(not f.raid.finished, "ineligible lane cannot fail the raid")
    end)
    run("raid defeated lines excluded and release/finished reset private guard", function()
        local f = pageFixture() ---@type table
        f.proven[f.drivers[1].allies] = false
        f.raid.defeated[1] = true
        f.raid:updateOffense(.1, true)
        eq(f.raid._noOffenseElapsed, 0, "defeated attacking line not counted")
        f.raid:updateOffense(4, true)
        f.raid:release()
        eq(f.raid._noOffenseElapsed, nil, "release clears grace")
        f.raid:updateOffense(100, false)
        check(not f.raid.finished, "released/ineligible old owner cannot accrue time")
        f.raid:finish(true)
        f.raid:updateOffense(100, true)
        check(f.raid.won, "finished victory immutable")
        eq(f.raid.failureReason, nil, "finished victory has no no-offense reason")
    end)

    local function towerFixture()
        local f = fixture() ---@type table
        f.mods["ui.battle.tri.BattleTriPage"] = { init = noop }
        local host = f.load("ui.tower.TowerTriBattle") ---@type table
        local state = get(host.isOpen, "state") ---@type table
        state.open, state.phase, state.floor, state.wave = true, "active", 1, 1
        state.lanes, state.allAllies = {}, {}
        for row = 1, 3 do
            local lane = f.lane(row) ---@type table
            state.lanes[row] = lane
            state.allAllies[#state.allAllies + 1] = lane.allies[1]
        end
        f.host, f.state = host, state
        return f
    end
    run("tower any single incapable line loses layer without faking wipe or HP", function()
        for disabled = 1, 3 do
            local f = towerFixture() ---@type table
            for row, lane in ipairs(f.state.lanes) do f.proven[lane.allies] = row == disabled end
            f.step(f.host, .1)
            for _ = 1, 9 do f.step(f.host, .5) end
            eq(f.state.phase, "active", "tower full grace retained row=" .. disabled)
            f.step(f.host, .5)
            eq(f.state.phase, "lose", "any single lane reaches whole-layer loss row=" .. disabled)
            eq(f.state.failureReason, "no_offense", "tower independent failure reason")
            eq(f.state.lanes[disabled].failureReason, "no_offense", "failure records responsible lane")
            eq(f.defeats, 1, "existing whole-layer defeat boundary called once")
            for _, lane in ipairs(f.state.lanes) do
                check(not lane.wiped, "no-offense is not fabricated team wipe")
                eq(lane.allies[1].hp, 100, "all tower living HP preserved")
            end
            f.step(f.host, 2)
            eq(f.defeats, 1, "result update never resubmits defeat")
            check(f.result and f.result.isWin == false, "normal tower result presentation remains reachable")
        end
    end)
    run("tower checks after every lane update and cleared lines do not fail", function()
        local f = towerFixture() ---@type table
        f.onInspect = function()
            eq(f.trace[#f.trace], "inspect", "Guard inspector reached after host completed ticks")
            local projectiles, talents = 0, 0
            for _, value in ipairs(f.trace) do
                if value == "projectile" then projectiles = projectiles + 1 end
                if value == "talent" then talents = talents + 1 end
            end
            check(projectiles >= 3 and talents >= 3, "all three full lane updates precede Guard inspection")
        end
        f.step(f.host, .1)
        f.onInspect = nil
        f.step(f.host, 4.5)
        f.state.lanes[1].enemies[1].hp = 0
        f.state.lanes[1].enemies[1].attrs.final.hp = 0
        f.proven[f.state.lanes[2].allies], f.proven[f.state.lanes[3].allies] = false, false
        f.step(f.host, .5)
        eq(f.state.phase, "active", "line clear cancels its threshold-time failure")
        check(f.state.lanes[1].cleared, "actual tower clear branch ran")
        eq(f.state.lanes[1]._noOffenseElapsed, nil, "cleared line grace reset")
        for row = 2, 3 do
            f.state.lanes[row].enemies[1].hp = 0
            f.state.lanes[row].enemies[1].attrs.final.hp = 0
        end
        f.step(f.host, .5)
        eq(f.state.phase, "win", "all-line clear remains victory priority")
        eq(f.wins, 1, "normal victory boundary exactly once")
        eq(f.defeats, 0, "no false whole-layer defeat")
    end)
    run("tower revive and final-lane capability restoration precede no-offense", function()
        for _, source in ipairs({ "artifact", "talent" }) do
            local f = towerFixture() ---@type table
            local target = f.state.lanes[1] ---@type table
            f.proven[f.state.lanes[2].allies], f.proven[f.state.lanes[3].allies] = false, false
            f.step(f.host, .1)
            f.step(f.host, 4.5)
            target.allies[1].hp, target.allies[1].attrs.final.hp = 0, 0
            local function revive(unit)
                unit.hp, unit.attrs.final.hp = 100, 100
                f.proven[target.allies] = false
                return true
            end
            if source == "artifact" then f.reviveArtifact = revive else f.reviveTalent = revive end
            f.step(f.host, .5)
            eq(f.state.phase, "active", "tower " .. source .. " revive runs before failure")
            eq(target.allies[1].hp, 100, "real host revival hook result retained")
            check(not target.wiped, "revived lane never marked wiped")
            eq(target._noOffenseElapsed, nil, "revival capability cancels prior grace")
            eq(f.defeats, 0, "revival does not call whole-layer defeat")
        end
    end)
    run("tower pause stops grace and entering frame invalidates old grace", function()
        local f = towerFixture() ---@type table
        f.step(f.host, .1)
        f.step(f.host, 4)
        f.step(f.host, 100, true)
        eq(f.state.lanes[1]._noOffenseElapsed, 4, "paused tower does not count100 seconds")
        eq(f.state.phase, "active", "paused tower active")
        f.step(f.host, .5)
        eq(f.state.lanes[1]._noOffenseElapsed, 4.5, "resume counts only real current frame dt")
        for _, lane in ipairs(f.state.lanes) do
            lane.combatState.cardAnims[lane.allies[1]] = { state = "entering" }
        end
        f.step(f.host, 50)
        for _, lane in ipairs(f.state.lanes) do
            eq(lane._noOffenseElapsed, nil, "entry frame resets each lane grace")
            lane.combatState.cardAnims = {}
        end
        f.step(f.host, .1)
        for _ = 1, 9 do f.step(f.host, .5) end
        eq(f.state.phase, "active", "after entry must receive complete fresh grace")
        f.step(f.host, .5)
        eq(f.state.failureReason, "no_offense", "fresh post-entry grace can still expire")
    end)

    local function dungeonFixture(resource, dummy)
        local f = fixture() ---@type table
        f.controls.dummy = dummy == true
        f.cfg.resourceCombat = resource == true
        f.mods["ui.battle.stage.BattleEnemySpawn"] = {}
        f.load("ui.dungeon.DungeonBattleScope")
        f.load("ui.dungeon.DungeonEnemyLifecycle")
        local host = f.load("ui.dungeon.DungeonBattleScene") ---@type table
        -- isOpen保持未包装的真实闭包，能拿到原state；update仍经真实DungeonScope.run。
        local state = get(host.isOpen, "state") ---@type table
        local lane = f.lane(1) ---@type table
        state.open, state.battleState, state.resultTimer = true, "active", 0
        state.resultPanelShown, state.confirmOpen, state.confirmClosing = false, false, false
        state.allies, state.enemies, state.enemyQueue = lane.allies, lane.enemies, {}
        f.host, f.state, f.laneData = host, state, lane
        return f
    end
    run("Dungeon resource and compatibility real update fail through original result path", function()
        for _, resource in ipairs({ false, true }) do
            local f = dungeonFixture(resource) ---@type table
            f.step(f.host, .1)
            for _ = 1, 9 do f.step(f.host, .5) end
            eq(f.state.battleState, "active", "dungeon full grace before threshold resource=" .. tostring(resource))
            f.step(f.host, .5)
            eq(f.state.battleState, "lose", "dungeon reaches no-offense defeat")
            eq(f.state.failureReason, "no_offense", "dungeon independent failure reason")
            eq(f.state.allies[1].hp, 100, "dungeon living ally HP not zeroed")
            eq(f.defeats, 1, "dungeon original onDefeat once")
            eq(f.wins, 0, "no fabricated victory/reward")
            f.step(f.host, 2)
            check(f.result and f.result.isWin == false, "original dungeon result delay and panel still reachable")
            eq(f.defeats, 1, "result frame not a duplicate defeat")
        end
    end)
    run("Dungeon victory priority and resource queue refill precede Guard", function()
        for _, resource in ipairs({ false, true }) do
            local f = dungeonFixture(resource) ---@type table
            f.step(f.host, .1)
            f.step(f.host, 4.5)
            f.state.enemies[1].hp, f.state.enemies[1].attrs.final.hp = 0, 0
            f.step(f.host, .5)
            eq(f.state.battleState, "win", "same-threshold preexisting clear beats no-offense")
            eq(f.wins, 1, "real dungeon clear path wins")
            eq(f.defeats, 0, "victory never routes defeat")
            check(f.state.failureReason ~= "no_offense", "victory not tagged as offense failure")
        end
        local f = dungeonFixture(true) ---@type table
        f.step(f.host, .1)
        f.step(f.host, 4.5)
        local old = f.state.enemies[1] ---@type table
        local reserve = f.unit() ---@type table
        f.state.enemyQueue[1] = reserve
        old.hp, old.attrs.final.hp = 0, 0
        f.step(f.host, .5)
        eq(f.state.battleState, "active", "resource actual reserve prevents victory")
        eq(f.state.enemies[1], reserve, "real DungeonEnemyLifecycle moves reserve into battlefield")
        eq(f.wins, 0, "reserve not silently dropped as cleared")
        eq(f.defeats, 0, "newly entering reserve cannot expire old grace")
    end)
    run("Dungeon artifact and talent revival precede no-offense", function()
        for _, source in ipairs({ "artifact", "talent" }) do
            local f = dungeonFixture(true) ---@type table
            f.step(f.host, .1)
            f.step(f.host, 4.5)
            f.state.allies[1].hp, f.state.allies[1].attrs.final.hp = 0, 0
            local function revive(unit)
                unit.hp, unit.attrs.final.hp = 100, 100
                f.proven[f.state.allies] = false
                return true
            end
            if source == "artifact" then f.reviveArtifact = revive else f.reviveTalent = revive end
            f.step(f.host, .5)
            eq(f.state.battleState, "active", "dungeon " .. source .. " revival wins failure race")
            eq(f.state.allies[1].hp, 100, "revived HP retained")
            eq(f.state._noOffenseElapsed, nil, "revived offense cancels old grace")
            eq(f.defeats, 0, "no defeat after successful revive")
            local artifactIndex, talentIndex = 0, 0
            for index, value in ipairs(f.trace) do
                if value == "artifact-revive" then artifactIndex = index end
                if value == "talent-revive" then talentIndex = index end
            end
            check(artifactIndex > 0, "real host artifact revival hook reached")
            if source == "talent" then check(talentIndex > artifactIndex, "artifact-before-talent contract preserved") end
        end
    end)
    run("Dungeon paused and training dummy never accumulate or fail", function()
        local f = dungeonFixture(true) ---@type table
        f.step(f.host, .1)
        f.step(f.host, 4)
        f.step(f.host, 100, true)
        eq(f.state._noOffenseElapsed, 4, "paused dungeon grace frozen")
        eq(f.state.battleState, "active", "paused dungeon cannot fail")
        f.step(f.host, .5)
        eq(f.state._noOffenseElapsed, 4.5, "dungeon resume only current dt")
        local dummy = dungeonFixture(false, true) ---@type table
        for _ = 1, 15 do dummy.step(dummy.host, 1) end
        eq(dummy.state.battleState, "active", "training dummy excluded from no-offense")
        eq(dummy.state._noOffenseElapsed, nil, "dummy no grace state")
        eq(dummy.defeats, 0, "dummy no defeat boundary")
    end)
    run("Dungeon inspect observes scope-owned eight states and frame-end capability", function()
        local f = dungeonFixture(true) ---@type table
        local hostCombat = f.mods["ui.battle.combat.BattleCombat"].mountedState() ---@type table
        f.step(f.host, .1)
        check(#f.capRecords > 0, "real dungeon reaches real Guard/Cap leaf")
        local first = f.capRecords[1].lane ---@type table
        eq(first.allies, f.state.allies, "dungeon allies passed by original ref")
        eq(first.enemies, f.state.enemies, "dungeon enemies passed by original ref")
        check(first.combatState ~= hostCombat, "dungeon guard receives private scope, not paused host")
        eq(f.mods["ui.battle.combat.BattleCombat"].mountedState(), hostCombat, "scope restores host combat ref")
        f.step(f.host, 4.5)
        f.onTalent = function(_, allies)
            f.proven[allies] = false
        end
        f.step(f.host, .5)
        eq(f.state.battleState, "active", "last TAL tick capability restores before guard decision")
        eq(f.state._noOffenseElapsed, nil, "late frame capability resets accumulated grace")
    end)

    -- 兼容Scene完整update与真实Casualty/Phases/Tick；只注入初始化态，不替换被测正文。
    local function sceneFixture()
        local f = fixture() ---@type table
        local mods = f.mods ---@type table
        for _, name in ipairs({ "ui.loot.LootBox", "ui.battle.stage.SweepDialog", "ui.hud.BottomNav",
            "systems.OfflineCalc", "systems.DropSystem", "ui.battle.stage.BattleTransitionHud",
            "ui.battle.stage.BattleEnemySpawn", "ui.battle.stage.BattleStageLoad", "ui.battle.scene.BattleDataRestore" }) do
            mods[name] = {}
        end
        mods["ui.battle.stage.StageBerserk"] = { isActive = function() return false end, exit = noop }
        mods["ui.battle.popup.MonsterInfoPopup"] = { update = noop }
        mods["ui.battle.popup.TerminalConfirmDialog"] = { update = noop }
        mods["ui.widget.SpeechBubble"] = { update = noop, trigger = noop }
        mods["systems.BattleDiag"] = { update = noop, installSentinel = noop, scanNow = noop }
        mods["core.GameState"] = {}
        mods["ui.battle.stage.BattleStageNav"] = { NAV = {} }
        mods["ui.battle.stage.BattleStageFlow"] = { pumpBattleCards = function(value) return value end }
        f.load("ui.battle.scene.BattleAllyLifecycle")
        mods["ui.battle.stage.BattleStageNavLogic"] = {}
        mods["ui.battle.stage.StageEntryEvents"] = { retry = noop }
        mods["ui.battle.tri.BattleTriPage"] = { isOpen = function() return f.controls.triOpen == true end }
        mods["shared.StageProvider"] = { Get = function() return mods["config.StageConfig"] end }
        f.load("ui.battle.combat.BattleCasualty")
        f.load("ui.battle.scene.BattleScenePhases")
        f.load("ui.battle.scene.BattleSceneTick")
        local host = f.load("ui.battle.scene.BattleScene") ---@type table
        -- 轮回流程不属于本专项；外围入口固定无待办，保留真实Scene.update其余全链。
        host.updateTriReincarnation = function() return false end
        local lane = f.lane(1) ---@type table
        set(host.update, "allies", lane.allies)
        set(host.update, "enemies", lane.enemies)
        set(host.update, "enemyQueue", {})
        set(host.update, "battleActive", true)
        set(host.update, "isFirstClear", false)
        set(host.update, "firstClearTimeLeft", nil)
        -- 原Tick调用的完整性检查只读叶子；不加载可编辑名册或存档。
        set(host.update, "checkEnemiesCorruption", noop)
        host.setOnAllDead(function(reason) f.defeats = f.defeats + 1; f.defeatReason = reason end)
        f.host, f.laneData = host, lane
        return f
    end

    run("compatibility Scene real Casualty then Guard fails living units with separate reason", function()
        local f = sceneFixture() ---@type table
        local owner = get(f.host.update, "offenseOwner") ---@type table
        f.step(f.host, .1)
        for _ = 1, 9 do f.step(f.host, .5) end
        check(get(f.host.update, "battleActive"), "compatibility Scene still active before five seconds")
        f.step(f.host, .5)
        check(not get(f.host.update, "battleActive"), "Scene enters normal loss transition")
        eq(get(f.host.update, "defeatTimer"), 0, "original Scene defeat delay starts at zero")
        eq(get(f.host.update, "defeatByTimeout"), false, "no-offense not fabricated as time limit")
        eq(owner.failureReason, "no_offense", "Scene distinct failure reason")
        eq(f.defeatReason, "no_offense", "existing callback receives independent reason")
        eq(f.defeats, 1, "Scene original defeat callback exactly once")
        eq(f.laneData.allies[1].hp, 100, "Scene living unit remains living")
        f.step(f.host, .5)
        eq(f.defeats, 1, "normal defeat delay not duplicate failure")
    end)
    run("compatibility Scene growth flush reentry cannot consume new battle rewards or fail new allies", function()
        local f = sceneFixture() ---@type table
        local owner = get(f.host.update, "offenseOwner") ---@type table
        f.step(f.host, .1)
        f.step(f.host, 4.5)
        local ets = f.mods["systems.ExtraTalentSystem"] ---@type table
        local casualty = f.mods["ui.battle.combat.BattleCasualty"] ---@type table
        local pending = get(casualty.flushRewards, "pendingRewards") ---@type table
        local newScope = ets.newState() ---@type table
        local replacement = { f.unit() } ---@type table
        local deliveries, growthFlushes = 0, 0
        local newRewards = { { callback = function() deliveries = deliveries + 1 end, data = {} } }
        pending[newScope] = newRewards
        -- 结账通知是显式外围重入边界；真正Scene/Guard及Casualty奖励队列不替换。
        ets.flush = function()
            growthFlushes = growthFlushes + 1
            set(f.host.update, "allies", replacement)
            ets.mount(newScope)
        end
        f.step(f.host, .5)
        eq(growthFlushes, 1, "old qualifying battle reaches actual growth-flush boundary once")
        eq(get(f.host.update, "allies"), replacement, "synchronous replacement remains current allies")
        eq(ets.mountedState(), newScope, "replacement growth domain retained")
        eq(deliveries, 0, "old failure cannot flush newly mounted battle rewards")
        eq(pending[newScope], newRewards, "new battle pending queue identity and contents untouched")
        check(get(f.host.update, "battleActive"), "old failure cannot stop replacement battle")
        eq(get(f.host.update, "defeatTimer"), nil, "old failure cannot start replacement defeat delay")
        check(owner.failureReason ~= "no_offense", "replacement not tagged as no-offense failure")
        eq(f.defeats, 0, "replacement receives no stale all-dead callback")
        eq(replacement[1].hp, 100, "replacement living HP retained")
    end)
    run("compatibility Scene victory and revival keep original priority", function()
        for _, mode in ipairs({ "victory", "artifact", "talent" }) do
            local f = sceneFixture() ---@type table
            local owner = get(f.host.update, "offenseOwner") ---@type table
            f.step(f.host, .1)
            f.step(f.host, 4.5)
            if mode == "victory" then
                f.laneData.enemies[1].hp, f.laneData.enemies[1].attrs.final.hp = 0, 0
            else
                f.laneData.allies[1].hp, f.laneData.allies[1].attrs.final.hp = 0, 0
                local function revive(unit)
                    unit.hp, unit.attrs.final.hp = 100, 100
                    f.proven[f.laneData.allies] = false
                    return true
                end
                if mode == "artifact" then f.reviveArtifact = revive else f.reviveTalent = revive end
            end
            f.step(f.host, .5)
            eq(f.defeats, 0, "Scene " .. mode .. " handled before no-offense")
            check(owner.failureReason ~= "no_offense", "Scene no false reason on " .. mode)
            if mode == "victory" then
                eq(get(f.host.update, "searchingTimer"), 0, "actual Casualty win enters normal idle search")
                check(not get(f.host.update, "battleActive"), "actual Scene victory stops business")
            else
                eq(f.laneData.allies[1].hp, 100, "actual Casualty revival result retained")
                check(get(f.host.update, "battleActive"), "revived Scene remains active")
                eq(owner._noOffenseElapsed, nil, "revived Scene gets no stale failure grace")
            end
        end
    end)
    run("compatibility Scene pause entry and late death never count as no-offense", function()
        local f = sceneFixture() ---@type table
        local owner = get(f.host.update, "offenseOwner") ---@type table
        f.step(f.host, .1)
        f.step(f.host, 4)
        set(f.host.update, "isPaused", true)
        f.step(f.host, 100)
        eq(owner._noOffenseElapsed, 4, "Scene actual Phases pause freezes offense grace")
        set(f.host.update, "isPaused", false)
        f.step(f.host, .5)
        eq(owner._noOffenseElapsed, 4.5, "Scene resume only counts current dt")
        local bcs = f.mods["ui.battle.combat.BattleCombat"].mountedState() ---@type table
        bcs.cardAnims[f.laneData.allies[1]] = { state = "entering" }
        f.step(f.host, 10)
        eq(owner._noOffenseElapsed, nil, "Scene captureFrame excludes whole entry frame")
        bcs.cardAnims = {}
        f.step(f.host, .1)
        f.step(f.host, 4.5)
        f.onCombo = function()
            local unit = f.laneData.allies[1] ---@type table
            unit.hp, unit.attrs.final.hp = 0, 0
        end
        f.step(f.host, .5)
        eq(owner._noOffenseElapsed, nil, "late frame death defers to next real Casualty revival")
        eq(f.defeats, 0, "late frame death not prematurely sent as no-offense")
        eq(owner.failureReason, nil, "late death has no fabricated offense reason")
    end)
    run("compatibility Scene cannot advance alongside an open TriPage", function()
        local f = sceneFixture() ---@type table
        local owner = get(f.host.update, "offenseOwner") ---@type table
        f.controls.triOpen = true
        for _ = 1, 20 do f.step(f.host, 1) end
        eq(owner._noOffenseElapsed, nil, "inactive compatibility host never starts duplicate grace")
        eq(#f.capRecords, 0, "TriPage ownership excludes default Scene inspection")
        eq(f.defeats, 0, "no duplicate-host defeat")
    end)
    run("all private fixtures deny native IO and preserve production diagnostic audit", function()
        for _, f in ipairs(fixtures) do
            eq(f.io, 0, "fixture native File/FS/cloud calls zero")
            eq(f.actions, 0, "fixture business Action calls zero")
            for _, line in ipairs(f.logs) do
                local lower = line:lower()
                check(not lower:find(" failed", 1, true) and not lower:find("failure:", 1, true)
                    and not lower:find("error:", 1, true) and not line:find("异常", 1, true),
                    "production diagnostic audit " .. line)
            end
        end
    end)
    print(TAG .. "SUMMARY cases=" .. cases .. " checks=" .. checks .. " failures=" .. failures)
    print(TAG .. (failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
