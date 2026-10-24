-- 塔与普通战斗一致性专项：真实Tower/属性/动画/塔倍率/副本倍率与共享BC函数。
-- 只读cache资源进入私有环境；File/FS/cloud/业务事件封闭，不加载main、不读玩家档。
-- 攻击/成长/绘制/复活来源为明确叶子spy；不以CPU记录器冒称GPU或设备验收。
-- 统一官方构建后独立运行：UrhoXRuntime tests/tower_battle_consistency_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
function Start()
    local TAG = "[tower_battle_consistency_test] "
    local checks, cases, failures = 0, 0, 0
    local sources = {} ---@type table<string, string>
    local fixtures = {} ---@type table[]
    local function noop() end
    local function check(value, message)
        checks = checks + 1
        assert(value, message)
    end
    local function eq(actual, expected, message)
        check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
    end
    local function near(actual, expected, message)
        check(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
            message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
    end
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
    -- 顶层函数以无缩进end终止；只提取生产函数正文，不复制被测规则。
    local function functionText(path, signature)
        local text = read(path)
        local first = assert(text:find(signature, 1, true), "missing production function " .. signature)
        assert(not text:find(signature, first + #signature, true), "ambiguous production function " .. signature)
        local last = assert(text:find("\nend", first, true), "missing function end " .. signature)
        return text:sub(first, last + 3)
    end
    local function getState(fn)
        for index = 1, 100 do
            local name, value = debug.getupvalue(fn, index)
            if name == "state" then return value end
            if not name then break end
        end
        error("missing production state")
    end
    local function run(name, body)
        cases = cases + 1
        local ok, err = xpcall(body, debug.traceback)
        if ok then print(TAG .. "PASS " .. name)
        else failures = failures + 1; print(TAG .. "FAIL " .. name .. " " .. tostring(err)) end
    end
    local function fixture()
        local f = { io = 0, actions = 0, saves = 0, attacks = {}, advances = {}, deaths = {}, kills = 0,
            plays = {}, texts = {}, draws = {}, views = {}, cancels = {}, activeEffects = {},
            scales = {}, visualTicks = 0, clock = { elapsedTime = 100 }, effectsEnabled = true,
            mods = {}, loaded = {}, split = {}, flushed = 0, wins = 0, defeats = 0,
            matrix = { sx = 1, sy = 1, tx = 0, ty = 0 }, stack = {}, clip = false } ---@type table
        fixtures[#fixtures + 1] = f
        local mods = f.mods ---@type table
        local function denied()
            f.io = f.io + 1
            error("native IO/network forbidden in tower consistency fixture")
        end
        local env = { assert = assert, error = error, type = type, tonumber = tonumber, tostring = tostring,
            pairs = pairs, ipairs = ipairs, next = next, select = select, pcall = pcall, xpcall = xpcall,
            setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset,
            rawequal = rawequal, math = {}, table = table, string = string, utf8 = utf8,
            print = noop, time = f.clock } ---@type table
        for key, value in pairs(math) do env.math[key] = value end
        env.math.random, env.math.randomseed = denied, denied
        env._G = env
        for _, key in ipairs({ "File", "FileSystem", "GetFileSystem", "GetCache", "GetEngine", "loadfile", "dofile",
            "SendEvent", "SubscribeToEvent", "UnsubscribeFromEvent" }) do env[key] = denied end
        for _, key in ipairs({ "fileSystem", "cache", "engine", "io", "os", "package", "network", "clientCloud", "serverCloud" }) do
            env[key] = setmetatable({}, { __index = denied, __newindex = denied })
        end
        for _, key in ipairs({ "NVG_ALIGN_LEFT", "NVG_ALIGN_RIGHT", "NVG_ALIGN_CENTER", "NVG_ALIGN_TOP",
            "NVG_ALIGN_MIDDLE", "NVG_ALIGN_BOTTOM" }) do env[key] = _G[key] end
        env.require = function(name) return assert(mods[name], "unprepared dependency " .. tostring(name)) end
        env.print = function(...)
            local words = {} ---@type string[]
            for index = 1, select("#", ...) do words[index] = tostring(select(index, ...)) end
            local text = table.concat(words, " ")
            local lower = text:lower()
            assert(not lower:find(" failed", 1, true) and not lower:find("error:", 1, true)
                and not text:find("异常", 1, true), "unexpected production diagnostic " .. text)
        end
        f.env = env
        f.load = function(name)
            if f.loaded[name] then return f.loaded[name] end
            local value = compile(name:gsub("%.", "/") .. ".lua", env)
            mods[name], f.loaded[name] = value, value
            return value
        end
        local function scoped()
            local current = { ctx = {}, cardAnims = {}, hitFlashes = {}, comboQueue = {} } ---@type table
            local api = {} ---@type table
            api.newState = function() return { ctx = {}, cardAnims = {}, hitFlashes = {}, comboQueue = {} } end
            api.newFxState, api.newSemState, api.newBattleRefs = api.newState, api.newState, api.newState
            api.mount = function(value) current = value or api.newState() end
            api.mountedState = function() return current end
            api.reset, api.init, api.initUnit, api.initBattle, api.onBattleStart = noop, noop, noop, noop, noop
            api.update = function() f.visualTicks = f.visualTicks + 1 end
            api.setRenderScale = function(value) api.scale = value; f.scales[#f.scales + 1] = value end
            return api
        end
        local bc, ps, tm, tal, ets, fx, sem, rch = scoped(), scoped(), scoped(), scoped(), scoped(), scoped(), scoped(), scoped()
        mods["ui.battle.combat.BattleCombat"], mods["ui.battle.combat.ProjectileSystem"] = bc, ps
        mods["systems.ThreatManager"], mods["systems.TalentManager"], mods["systems.ExtraTalentSystem"] = tm, tal, ets
        mods["ui.battle.combat.BattleEffects"], mods["systems.StatusEffectManager"], mods["systems.RelicConditionHandler"] = fx, sem, rch
        tm.removeUnit, sem.removeUnit, sem.apply = noop, noop, noop
        sem.isFrozen = function(unit) return unit.testFrozen == true end
        ps.hasHeroEffect, ps.hasMonsterProjectile, ps.hasProjectile = function() return false end, function() return false end, function() return false end
        ps.spawn, ps.spawnByKey = noop, noop
        local unitStates = {} ---@type table
        tal.mountedUnitStates = function() return unitStates end
        tal.resetEnemyDeath = function(unit) unit._testDeathReported = nil end
        tal.onEnemyDeath = function(unit)
            if not unit._testDeathReported then
                unit._testDeathReported = true
                f.deaths[unit] = (f.deaths[unit] or 0) + 1
            end
        end
        tal.onAllyDeath = function(unit)
            f.talentCalls = (f.talentCalls or 0) + 1
            if f.talentRevive then return f.talentRevive(unit) end
            return false
        end
        ets.flush = function() f.flushed = f.flushed + 1 end
        ets.discard = noop
        local art = { reset = noop, initBattle = noop, update = noop,
            onAllyDeath = function(unit)
                f.artifactCalls = (f.artifactCalls or 0) + 1
                if f.artifactRevive then return f.artifactRevive(unit) end
                return false
            end } ---@type table
        mods["systems.ArtifactRuntime"] = art
        mods["ui.hud.popup.SettingsPanel"] = { isEffectsEnabled = function() return f.effectsEnabled end,
            isDamageNumbersEnabled = function() return true end }
        local ad = f.load("systems.AttributeDef") ---@type table
        local attrs = f.load("systems.UnitAttributes") ---@type table
        local layout = f.load("core.BattleLayout") ---@type table
        layout.setMode("strip")
        local cc = f.load("config.ClassConfig") ---@type table
        mods["config.MonsterConfig"] = { MONSTERS = {} }
        f.load("config.TowerConfig")
        f.load("ui.tower.TowerLayout")
        f.load("ui.battle.combat.BattleMotionPolish")
        local anim = f.load("ui.battle.combat.BattleCombatAnim") ---@type table
        bc.DEATH_ANIM_DURATION, bc.REVIVE_ANIM_DURATION = anim.DEATH_ANIM_DURATION, anim.REVIVE_ANIM_DURATION
        bc.setContext = function(value) bc.mountedState().ctx = value end
        bc.setCardAnim = function(unit, value) anim.set(bc.mountedState(), unit, value) end
        bc.clearCardAnim = function(unit) anim.clear(bc.mountedState(), unit) end
        bc.getAnimState = function(unit) return anim.getState(bc.mountedState(), unit) end
        bc.playEnterAnims = function(list, direction) anim.playEnter(bc.mountedState(), list, direction) end
        bc.updateCardAnims = function(dt) anim.update(bc.mountedState(), dt); f.visualTicks = f.visualTicks + 1 end
        bc.clearHitFlash = function(unit) bc.mountedState().hitFlashes[unit] = nil end
        bc.clearFloatingTexts, bc.updateFloatingTexts, bc.updateHitFlashes, bc.updateHpBuffers = noop, noop, noop, noop
        bc.updateComboQueue, bc.onTalentDealDamage = noop, noop
        bc.dealDamageToUnit, bc.dealTalentDamage = noop, noop
        bc.getCardCX = function(list, index) return layout.posForList(list, index) end
        bc.getCardPos = function(list, index) return layout.posForList(list, index) end
        bc.syncUnitHp = function(unit) unit.hp = unit.attrs.final[ad.HP]; unit.maxHp = unit.attrs.final[ad.MAX_HP] end
        bc.getAliveUnits = function(list)
            local alive = {} ---@type table[]
            for _, unit in ipairs(list) do if unit.hp > 0 then alive[#alive + 1] = unit end end
            return alive
        end
        bc.addFloatingText = function(...) f.texts[#f.texts + 1] = { ... } end
        bc.addCombatNumber = function(...) f.texts[#f.texts + 1] = { ... } end
        bc.performAttack = function(unit, target, ally)
            f.attacks[#f.attacks + 1] = { unit = unit, target = target, ally = ally }
        end
        -- 共享函数的所有规则直接来自BC；外围状态模块明确spy，不加载庞大伤害图。
        local sharedEnv = setmetatable({ BattleCombat = bc, TM = tm, SEM = sem, TAL = tal,
            BattleLayout = layout }, { __index = env })
        for _, name in ipairs({ "getLiveAttackInterval", "reinforceEnemies", "advanceAttackProgress" }) do
            local code = functionText("ui/battle/combat/BattleCombat.lua", "function BattleCombat." .. name .. "(")
            assert(load(code, "@real-BC/" .. name, "t", sharedEnv))()
        end
        local combatSource = read("ui/battle/combat/BattleCombat.lua")
        bc.MAX_ATTACKS_PER_FRAME = assert(tonumber(combatSource:match("BattleCombat%.MAX_ATTACKS_PER_FRAME%s*=%s*(%d+)")))
        bc.MIN_ATTACKS_PER_FRAME = assert(tonumber(combatSource:match("BattleCombat%.MIN_ATTACKS_PER_FRAME%s*=%s*(%d+)")))
        local advance = bc.advanceAttackProgress
        bc.advanceAttackProgress = function(unit, dt, interval, hasTarget, onAttack)
            f.advances[#f.advances + 1] = { unit = unit, dt = dt, interval = interval, hasTarget = hasTarget }
            return advance(unit, dt, interval, hasTarget, onAttack)
        end
        mods["systems.BattleDiag"] = { logEnabled = false }
        local cf = {} ---@type table
        assert(load(functionText("systems/CombatFormula.lua", "function CF.calcHpRegen("),
            "@real-CF/regen", "t", setmetatable({ CF = cf, AD = ad }, { __index = env })))()
        mods["systems.CombatFormula"] = cf
        mods["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 }, Battle = { TIME_LIMIT_SEC = 300 } }
        mods["config.HeroConfig"] = { HEROES = {} }
        mods["config.StageConfig"] = {}
        mods["config.DungeonConfig"] = { isResourceDungeon = function() return false end }
        mods["shared.Protocol"] = { ACTION_TYPES = { TOWER_WAVE_WIN = "tower_win", DUNGEON_WIN = "dungeon_win" } }
        mods["ui.battle.stage.BattleEnemySpawn"] = {}
        mods["ui.dungeon.DungeonCombatRuntime"] = {}
        mods["runtime.GameAction"] = { sendAction = function() f.actions = f.actions + 1; error("business action forbidden") end }
        local tbr = f.load("systems.TowerBuffRuntime") ---@type table
        local db = f.load("ui.dungeon.DungeonBattle") ---@type table
        -- 倍率/计时/击杀回调保留真实函数；记录TBR实际消费，不把被幂等拒绝的入口计成新杀。
        local onKill = db.onEnemyKill
        local runtimeKill = tbr.onEnemyKill
        f.killEntries = {}
        db.onEnemyKill = function(killer, deadUnit)
            f.killEntries[#f.killEntries + 1] = { killer = killer, target = deadUnit }
            return onKill(killer, deadUnit)
        end
        tbr.onEnemyKill = function(killer) f.kills = f.kills + 1; return runtimeKill(killer) end
        -- 完整统一伤害函数也来自生产；护盾前置/套装/神器/统计/音效等明确无副作用叶子spy。
        f.directDamage = function(target, damage, source)
            local damageEnv = setmetatable({ BCS = bc.mountedState(), AD = ad, DungeonBattle = db,
                ClassGateRuntime = { applyDebtTaken = function(_, value) return value end,
                    absorbIncoming = function(_, value) return value end, tryDeferDeath = function() return false end },
                EquipmentSetRuntime = { onIncoming = function(_, value) return value end, shouldSkipThreat = function() return false end },
                ETS = { absorbBulwarkWard = function(_, value) return value end }, TAL = tal,
                ART = { onBeforeTakeDamage = function(_, _, value) return value end, checkShieldBreak = noop },
                BattleStats = { recordDamage = noop, recordDotDamage = noop, recordTaken = noop, mountedTeam = function() return 0 end },
                RCH = { shouldSkipThreat = function() return false end }, TM = { onDamageDealt = noop },
                GameSFX = { play = noop }, syncUnitHp = bc.syncUnitHp, getCardPos = bc.getCardPos,
                addCombatNumber = bc.addCombatNumber, setHitFlash = noop }, { __index = env })
            local path = "ui/battle/combat/BattleCombat.lua"
            local sections = {} ---@type string[]
            for _, signature in ipairs({ "local function findUnitIndex(", "local function isAllyUnit(",
                "local function applyGlobalDmgMult(", "local function resolveDamageStatCategory(",
                "local function dealDamageToUnit(" }) do
                sections[#sections + 1] = functionText(path, signature)
            end
            local hit = assert(load(table.concat(sections, "\n") .. "\nreturn dealDamageToUnit",
                "@real-BC/dealDamageToUnit", "t", damageEnv))()
            return hit(target, damage, false, "", nil, source)
        end
        db.onVictory = function() f.wins = f.wins + 1 end
        db.onDefeat = function() f.defeats = f.defeats + 1 end
        mods["ui.battle.scene.BattleAllyReset"] = { compactFallen = noop }
        mods["ui.battle.scene.BattleAllyLifecycle"] = { isTowerOffenseRegistryKnown = function() return true end }
        mods["systems.BattleOffenseGuard"] = { reset = noop, update = function() return false end }
        mods["systems.BattleTimeout"] = { calcMult = function() return 1 end }
        mods["ui.battle.combat.BattleClock"] = { now = function() return f.clock.elapsedTime end }
        mods["systems.ButtonFeedback"] = { trigger = noop }
        mods["core.NumberUtil"] = { format = tostring }
        mods["core.DrawUtil"] = { drawTextStroke = noop }
        mods["ui.battle.scene.BattlePauseOverlay"] = { init = noop, draw = noop }
        mods["ui.battle.popup.BattleResultPanel"] = { init = noop, update = noop, show = noop, draw = noop,
            isOpen = function() return false end }
        mods["systems.BattleStats"] = { reset = noop, buildHeroDamageStats = function() return {} end }
        local function snapshot()
            return { sx = f.matrix.sx, sy = f.matrix.sy, tx = f.matrix.tx, ty = f.matrix.ty,
                clip = f.clip, depth = #f.stack }
        end
        f.snapshot = snapshot
        env.nvgSave = function() f.stack[#f.stack + 1] = snapshot() end
        env.nvgRestore = function()
            local old = assert(table.remove(f.stack), "unbalanced restore") ---@type table
            f.matrix = { sx = old.sx, sy = old.sy, tx = old.tx, ty = old.ty }; f.clip = old.clip
        end
        env.nvgTranslate = function(_, x, y)
            f.matrix.tx = f.matrix.tx + x * f.matrix.sx; f.matrix.ty = f.matrix.ty + y * f.matrix.sy
        end
        env.nvgScale = function(_, x, y) f.matrix.sx = f.matrix.sx * x; f.matrix.sy = f.matrix.sy * y end
        env.nvgScissor = function(_, x, y, w, h) f.clip = { x = x, y = y, w = w, h = h } end
        env.nvgIntersectScissor = env.nvgScissor
        for _, key in ipairs({ "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgFillColor", "nvgText" }) do env[key] = noop end
        env.nvgRGBA = function(...) return { ... } end
        mods["ui.battle.scene.BattleView"] = { init = noop, draw = function(_, data)
            f.views[#f.views + 1] = { allies = data.allies, transform = snapshot() }
        end }
        mods["ui.battle.tri.BattleTriPage"] = { init = noop, drawL0 = noop, drawL1Underlay = noop,
            getInteriorRectFor = function(row) return 20, 80 + (row - 1) * 310, 1672, 280 end }
        mods["ui.tower.TowerBuffSidebar"] = { drawConfirmation = noop }
        mods["ui.tower.TowerPresentation"] = { text = function(s, ...) return string.format(s, ...) end }
        mods["ui.tower.TowerWaveSplit"] = { splitToLanes = function() return f.split end }
        local card = {} ---@type table
        card.playRevive = function(x, y, callback, scope, width, height)
            f.plays[#f.plays + 1] = { x = x, y = y, scope = scope, width = width, height = height, callback = callback }
            f.activeEffects[scope] = true
        end
        card.draw = function(_, scope) f.draws[#f.draws + 1] = { scope = scope, transform = snapshot() } end
        card.stopAll = function(scope)
            assert(type(scope) == "string" and scope:match("^tower[123]$"), "tower cannot cancel foreign/global scope")
            f.cancels[#f.cancels + 1] = scope; f.activeEffects[scope] = nil
        end
        card.update = noop
        mods["ui.fx.SpineCardEffect"] = card
        local host = f.load("ui.tower.TowerTriBattle") ---@type table
        f.host, f.state, f.bc, f.db, f.tbr, f.ad, f.layout, f.anim, f.cc = host, getState(host.isOpen), bc, db, tbr, ad, layout, anim, cc
        f.unit = function(id, enemy)
            local value = attrs.create({ [ad.MAX_HP] = 1000, [ad.ATK_INTERVAL] = 2, [ad.ATK_SPEED] = 0 }) ---@type table
            value:fillHp()
            return { heroId = not enemy and id or nil, monsterId = enemy and id or nil, instanceId = id,
                classId = cc.WARRIOR, attrs = value, hp = value.final[ad.HP], maxHp = value.final[ad.MAX_HP],
                atkProgress = 0, atkInterval = value:getActualInterval() }
        end
        f.open = function(count, buffs)
            f.split = {}
            local teams = {} ---@type table[]
            for row = 1, 3 do
                teams[row] = {}
                local enemies = {} ---@type table[]
                for index = 1, count or 1 do
                    teams[row][index] = f.unit(row * 10 + index)
                    enemies[index] = f.unit(row * 100 + index, true)
                end
                f.split[row] = { field = enemies, queue = {} }
            end
            tbr.initMechanics(buffs or {})
            host.open({ teamAllies = teams, data = { dungeonId = "babel_tower", floor = 1, wave = 1,
                monsters = {}, monsterLevel = 1, rageTime = 30, superRageTime = 60 } })
        end
        f.ready = function()
            for _, lane in ipairs(f.state.lanes) do
                lane.introTimer = 0; lane.combatState.cardAnims = {}
                for _, list in ipairs({ lane.allies, lane.enemies }) do
                    for _, unit in ipairs(list) do unit.atkProgress = 0 end
                end
            end
        end
        f.step = function(dt, paused) f.clock.elapsedTime = f.clock.elapsedTime + dt; host.update(dt, paused) end
        f.kill = function(unit) unit.hp = 0; unit.attrs.final[ad.HP] = 0 end
        f.interval = function(unit)
            for index = #f.advances, 1, -1 do
                if f.advances[index].unit == unit then return f.advances[index].interval end
            end
            error("unit never reached real host attack advancement")
        end
        return f
    end

    run("共享BC实时属性、fallback及攻击进度", function()
        local f = fixture() ---@type table
        local unit = f.unit(1) ---@type table
        near(f.bc.getLiveAttackInterval(unit, 7), 2, "真实attrs基础2秒")
        unit.attrs:addModifier("speed", { { key = f.ad.ATK_SPEED, flat = 100 } })
        near(f.bc.getLiveAttackInterval(unit, 7), 1, "加速立即读取attrs不依赖缓存")
        unit.attrs:addModifier("speed", { { key = f.ad.ATK_SPEED, flat = -50 } })
        near(f.bc.getLiveAttackInterval(unit, 7), 4, "减速立即读取attrs")
        eq(unit.atkInterval, 2, "实时helper不反写缓存")
        unit.attrs:removeModifier("speed")
        f.tbr.applyStatBuffs({ unit }, { 9 })
        near(f.bc.getLiveAttackInterval(unit, 7), 2 / 1.2, "正式疾风先手真实属性加速不被缓存间隔吃掉")
        near(f.bc.getLiveAttackInterval({}, 7), 7, "缺属性走原fallback")
        near(f.bc.getLiveAttackInterval({ attrs = { getActualInterval = function() return .01 end } }, 7), 7,
            "不接受非法小间隔")
        unit.attrs:addModifier("speed", { { key = f.ad.ATK_SPEED, flat = 100000 } })
        near(f.bc.getLiveAttackInterval(unit, 7), .05, "真实attrs极高攻速保留下限")
        local attacks = 0
        unit.atkProgress = .75
        f.bc.advanceAttackProgress(unit, .25, .5, true, function() attacks = attacks + 1 end)
        eq(attacks, 1, "调用真实共享推进函数触发一次")
        near(unit.atkProgress, .25, "攻击后保留超额进度")
    end)
    run("真实TBR静态20/28、动态27与Dungeon正常狂暴倍率组合", function()
        local f = fixture() ---@type table
        f.open(1, { 20, 20, 27, 28 }); f.ready()
        local warrior = f.state.lanes[1].allies[1] ---@type table
        local mage = f.state.lanes[2].allies[1] ---@type table
        local enemy = f.state.lanes[1].enemies[1] ---@type table
        mage.classId = f.cc.MAGE
        f.tbr.applyMechanicInit(f.state.allAllies, { enemy })
        near(f.tbr.getStaticIntervalMultiplier(warrior), .75 * .75, "重复20分别相乘")
        near(f.tbr.getStaticIntervalMultiplier(mage), .75 * .75 * 2, "法师28不丢且不是全队减速")
        local output = warrior.atkInterval
        f.tbr.applyMechanicInit(f.state.allAllies, { enemy })
        near(warrior.atkInterval, output, "跨波复用单位不重复乘静态输出")
        warrior.hp = warrior.maxHp * .5; warrior.attrs.final[f.ad.HP] = warrior.hp
        near(f.db.getAtkIntervalMultiplier(warrior), .5, "旧API仍只给动态27")
        near(f.db.getAtkIntervalMultiplier(warrior, false), .5, "显式false保持旧调用语义")
        near(f.db.getAtkIntervalMultiplier(warrior, true), .75 * .75 * .5, "true含静态与动态")
        near(f.db.getAtkIntervalMultiplier(enemy, true), 1, "敌方不借己方塔暗契")
        local speedUnits = { warrior, mage, enemy } ---@type table[]
        for _, unit in ipairs(speedUnits) do
            unit.attrs:addModifier("live_speed", { { key = f.ad.ATK_SPEED, flat = 100 } })
        end
        f.step(.01)
        near(f.interval(warrior), 1 * .75 * .75 * .5, "Tower真实攻击使用实时attrs乘静态动态")
        near(f.interval(mage), 1 * .75 * .75 * 2, "Tower法师蓄力倍率保留")
        near(f.interval(enemy), 1, "Tower敌人也实时读取攻速")
        f.db.update(30, { enemy }, f.state.allAllies)
        f.step(.01)
        near(f.interval(warrior), .75 * .75 * .5 / 1.5, "狂暴50%与暗契不互相覆盖")
        near(f.interval(mage), .75 * .75 * 2 / 1.5, "狂暴保留28延长")
        near(f.interval(enemy), 1 / 1.5, "敌方狂暴50%")
        near(f.db.getAtkIntervalMultiplier(warrior), .5, "狂暴后旧API不重复包含狂暴")
        warrior.attrs:addModifier("live_speed", { { key = f.ad.ATK_SPEED, flat = -50 } })
        f.step(.01)
        near(f.interval(warrior), 4 * .75 * .75 * .5 / 1.5, "狂暴期间再减速仍即时跟随")
        f.db.update(30, { enemy }, f.state.allAllies)
        f.step(.01)
        near(f.interval(warrior), 4 * .75 * .75 * .5 / 2, "超级狂暴100%是阶段替换不复乘旧50%")
        local previous = f.interval(warrior)
        f.step(.01); near(f.interval(warrior), previous, "同阶段连续帧不再次叠乘")
        warrior.hp = warrior.maxHp; warrior.attrs.final[f.ad.HP] = warrior.hp
        f.step(.01)
        near(f.interval(warrior), 4 * .75 * .75 / 2, "HP恢复立即取消动态27")
        f.host.close()
        near(f.db.getAtkIntervalMultiplier(warrior, true), 1, "退出塔后倍率不泄漏")
    end)
    run("真实Tower初始错峰入场禁攻、暂停及大dt不倒灌", function()
        for _, effects in ipairs({ true, false }) do
            local f = fixture() ---@type table
            f.effectsEnabled = effects; f.open(4)
            for _, lane in ipairs(f.state.lanes) do near(lane.introTimer, .48, "四卡完整错峰入场时长") end
            local before = f.visualTicks
            f.step(.20)
            eq(#f.attacks, 0, "入场不攻击")
            eq(#f.advances, 0, "入场不积累攻击进度")
            check(f.visualTicks > before, "入场仍推进必要视觉")
            local remain = f.state.lanes[1].introTimer
            f.step(100, true)
            near(f.state.lanes[1].introTimer, remain, "暂停不消耗入场计时")
            eq(#f.attacks, 0, "暂停不攻击")
            f.step(10)
            eq(#f.attacks, 0, "跨越入场的大dt不一次倾泻攻击")
            for _, lane in ipairs(f.state.lanes) do
                for _, list in ipairs({ lane.allies, lane.enemies }) do
                    for _, unit in ipairs(list) do near(unit.atkProgress, 0, "入场后无隐藏积攒") end
                end
            end
            f.step(.25)
            check(#f.advances > 0, "下一活动帧恢复攻击推进")
            near(f.state.lanes[1].allies[1].atkProgress, .125, "只消费入场后的真实dt")
            f.host.close()
        end
    end)
    run("共享BC一秒前移队尾补位、冷却及引用动画", function()
        local f = fixture() ---@type table
        local a, b, c, d, e, tail = f.unit(101, true), f.unit(102, true), f.unit(103, true), f.unit(104, true),
            f.unit(105, true), f.unit(106, true)
        local enemies = { a, b, c, d } ---@type table[]
        local queue = { e, tail } ---@type table[]
        f.kill(a)
        f.bc.setCardAnim(a, { state = "dying", timer = 0, lungeDir = -1 })
        local cooldown = f.bc.reinforceEnemies(enemies, queue, .5, 0)
        cooldown = f.bc.reinforceEnemies(enemies, queue, .49, cooldown)
        check(enemies[1] == a and #queue == 2, "0.99秒不提前补位")
        cooldown = f.bc.reinforceEnemies(enemies, queue, .011, cooldown)
        check(enemies[1] == b and enemies[2] == c and enemies[3] == d and enemies[4] == e,
            "一秒后后方保持顺序前移，新敌从队尾进入")
        check(#queue == 1 and queue[1] == tail, "仅消费首个后备")
        near(cooldown, .4, "补位新冷却0.4秒")
        for _, unit in ipairs({ b, c, d }) do
            local animation = f.bc.mountedState().cardAnims[unit] ---@type table
            eq(animation.state, "advance", "存活者前移动画")
            near(animation.advanceDist, f.layout.STRIP_PITCH, "前移精确一格")
        end
        eq(f.bc.mountedState().cardAnims[e].state, "reviving", "新敌补位动画")
        eq(f.bc.mountedState().cardAnims[a], nil, "旧敌动画清理")
        near(e.atkProgress, 0, "新敌攻击进度清零")
        f.kill(c); c.reviveTimer = 1
        cooldown = f.bc.reinforceEnemies(enemies, queue, .2, cooldown)
        check(enemies[2] == c and #queue == 1, "达到死亡等待仍受补位冷却约束")
        cooldown = f.bc.reinforceEnemies(enemies, queue, .201, cooldown)
        check(enemies[1] == b and enemies[2] == d and enemies[3] == e and enemies[4] == tail,
            "冷却结束后第二死者前移补位")
        f.kill(d); d.reviveTimer = 1
        f.bc.reinforceEnemies(enemies, queue, .5, cooldown)
        check(#enemies == 3 and enemies[1] == b and enemies[2] == e and enemies[3] == tail,
            "无后备也移除死者并紧凑")
    end)
    run("真实Tower补位前上报击杀一次、各线独立及最终清波", function()
        local f = fixture() ---@type table
        f.open(4); f.ready()
        local lane = f.state.lanes[1] ---@type table
        local old = lane.enemies[1] ---@type table
        local b, c, d = lane.enemies[2], lane.enemies[3], lane.enemies[4]
        local replacement = f.unit(199, true) ---@type table
        lane.queue = { replacement }
        f.kill(old)
        f.step(.99)
        eq(f.kills, 1, "移除前即报告塔杀数一次")
        eq(f.deaths[old], 1, "死亡天赋事件一次")
        check(lane.enemies[1] == old, "宿主0.99秒未前移")
        f.step(.011)
        check(lane.enemies[1] == b and lane.enemies[2] == c and lane.enemies[3] == d and lane.enemies[4] == replacement,
            "宿主委托共享补位保持列表身份")
        eq(f.kills, 1, "移除旧敌不丢或重复计杀")
        eq(f.state.lanes[2].enemies[1].monsterId, 201, "其他战线列表不受影响")
        for _, current in ipairs(f.state.lanes) do
            for _, unit in ipairs(current.enemies) do f.kill(unit) end
            current.queue = {}
        end
        f.step(.01)
        eq(f.state.phase, "win", "最后敌人已死立即清波，不等待尸体退场冷却")
        eq(f.wins, 1, "三行仅一次胜利")
        eq(f.kills, 13, "原十二敌加补位一只精确十三杀")
        eq(f.deaths[old], 1, "已移除者不重报")
        f.step(1); eq(f.wins, 1, "结算update不重复胜利")
        f.host.close()
    end)
    run("真实统一伤害投射物落地与Tower兜底只计一次16/17、复活再杀", function()
        local f = fixture() ---@type table
        f.open(2, { 16, 17 }); f.ready()
        local lane = f.state.lanes[1] ---@type table
        local attacker = lane.allies[1] ---@type table
        local victim = lane.enemies[1] ---@type table
        local ps = f.mods["ui.battle.combat.ProjectileSystem"] ---@type table
        local nativeUpdate = ps.update
        local landed = false
        ps.update = function(dt)
            nativeUpdate(dt)
            if f.bc.mountedState() == lane.combatState and not landed then
                landed = true
                local actual = f.directDamage(victim, victim.hp + 1, attacker)
                check(actual > 0 and victim.hp == 0, "完整真实dealDamageToUnit扣除最后HP")
                eq(f.kills, 1, "伤害出口先进入真实DB/TBR计杀")
            end
        end
        f.step(.01)
        check(landed and victim._towerKillReported, "PS更新中的最后一击已绑定敌人身份")
        eq(f.kills, 1, "Tower末尾死亡扫描不重复消费击杀")
        eq(f.deaths[victim], 1, "真实伤害与宿主重复死亡扫描仍只一次事件")
        eq(f.killEntries[1].target, victim, "真实BC伤害出口透传目标给DB")
        eq(f.killEntries[1].killer, attacker, "真实BC保留击杀来源")
        near(f.tbr.getDamageMultiplier(attacker, lane.enemies[2]), 1.05, "16恰好一层5%")
        near(attacker.attrs:get(f.ad.HP_BONUS), 5, "17恰好一层5%")
        f.db.onEnemyKill(attacker, victim)
        eq(f.kills, 1, "显式重复DB入口也不重复加层")
        ps.update = nativeUpdate
        victim.attrs:fillHp(); f.bc.syncUnitHp(victim)
        f.step(.01)
        check(victim._towerKillReported == nil, "活单位扫描清除上次死亡身份")
        local secondHit = false
        ps.update = function(dt)
            nativeUpdate(dt)
            if f.bc.mountedState() == lane.combatState and not secondHit then
                secondHit = true
                f.directDamage(victim, victim.hp + 1, attacker)
            end
        end
        f.step(.01)
        eq(f.kills, 2, "同一敌人复活再死允许第二次击杀")
        eq(f.deaths[victim], 2, "复活再死允许第二次死亡事件")
        near(f.tbr.getDamageMultiplier(attacker, lane.enemies[2]), 1.10, "16第二次合法死亡才到两层")
        near(attacker.attrs:get(f.ad.HP_BONUS), 10, "17第二次合法死亡才到两层")
        f.host.close()
    end)
    run("299.2秒PS或连击最后一击立即胜利且保留待处理己方死亡优先", function()
        for _, outlet in ipairs({ "projectile", "combo" }) do
            local f = fixture() ---@type table
            f.open(1); f.ready()
            local trigger = f.mods["ui.battle.combat.ProjectileSystem"] ---@type table
            local native = trigger.update
            local function hit()
                local mounted = f.bc.mountedState() ---@type table
                for _, lane in ipairs(f.state.lanes) do
                    if mounted == lane.combatState and lane.enemies[1].hp > 0 then
                        f.directDamage(lane.enemies[1], lane.enemies[1].hp + 1, lane.allies[1])
                    end
                end
            end
            if outlet == "projectile" then trigger.update = function(dt) native(dt); hit() end
            else f.bc.updateComboQueue = hit end
            f.db.update(299.19, {}, f.state.allAllies)
            f.step(.01)
            near(f.db.getElapsed(), 299.2, "最后一击在300秒硬限前落地")
            eq(f.state.phase, "win", outlet .. "末尾清波本帧即时胜利")
            eq(f.kills, 3, "三线三只敌人各计一次")
            eq(f.wins, 1, "只提交一次胜利")
            eq(f.defeats, 0, "未被尸体1秒延迟拖到超时")
            f.step(1)
            eq(f.state.phase, "win", "胜利后跨300秒不反转判负")
            eq(f.defeats, 0, "胜利后不发生超时失败")
            f.host.close()
        end
        local f = fixture() ---@type table
        f.open(1); f.ready()
        local lane = f.state.lanes[1] ---@type table
        local ps = f.mods["ui.battle.combat.ProjectileSystem"] ---@type table
        local fired = false
        ps.update = function()
            if f.bc.mountedState() == lane.combatState and not fired then
                fired = true; f.kill(lane.allies[1]); f.kill(lane.enemies[1])
            end
        end
        f.step(.01)
        check(not lane.cleared, "末尾同时出现未处理己方死亡不提前清波")
        eq(f.state.phase, "active", "先留给下帧原复活/全灭入口")
        f.step(.01)
        eq(f.state.phase, "lose", "无复活的真实全灭优先于敌方清波")
        eq(f.defeats, 1, "全灭失败出口一次")
        f.host.close()
    end)
    run("真实Tower持续回血按regen乘dt且暂停停表", function()
        local f = fixture() ---@type table
        f.open(1); f.ready()
        local ally = f.state.lanes[1].allies[1] ---@type table
        local enemy = f.state.lanes[1].enemies[1] ---@type table
        local regenUnits = { ally, enemy } ---@type table[]
        for _, unit in ipairs(regenUnits) do
            unit.attrs:setBases({ [f.ad.HP_REGEN] = 40, [f.ad.HEAL_BONUS] = 25 })
            unit.hp = 100; unit.attrs.final[f.ad.HP] = 100
        end
        f.step(.25)
        -- 正式heal仅把整数部分落HP，0.5余量留在属性容器，下次恢复继续消费。
        near(ally.hp, 112, "己方0.25秒即时恢复12整数HP，不等待整秒")
        near(enemy.hp, 112, "敌方同一持续回血与整数落HP规则")
        near(ally.attrs._healFrac, .5, "己方12.5治疗保留0.5小数余量")
        near(enemy.attrs._healFrac, .5, "敌方12.5治疗保留0.5小数余量")
        f.step(100, true); near(ally.hp, 112, "暂停无回血")
        near(ally.attrs._healFrac, .5, "暂停不消费小数余量")
        f.step(.75); near(ally.hp, 150, "累计一秒连同小数余量精确恢复50")
        near(enemy.hp, 150, "敌方累计一秒同样精确恢复50")
        near(ally.attrs._healFrac, 0, "后续37.5加既有0.5恰好落38HP")
        f.host.close()
    end)
    run("真实Horizon四状态及独立Tower.draw重设缩放", function()
        local f = fixture() ---@type table
        local mode = { tri = false, dungeon = false, tower = false } ---@type table
        local henv = setmetatable({ Viewport = { layout = function() return 0, 0, 1 end },
            logicalW = function() return 1280 end, logicalH = function() return 800 end,
            BattleLayout = f.layout, ProjectileSystem = f.mods["ui.battle.combat.ProjectileSystem"],
            BattleEffects = f.mods["ui.battle.combat.BattleEffects"],
            BattleTriPage = { isOpen = function() return mode.tri end },
            DungeonBattleScene = { isOpen = function() return mode.dungeon end },
            TowerBattleScene = { isActive = function() return mode.tower end },
            CharacterPanel = { getTotalPower = function() return 100 end },
            TopBar = { setTotalPower = noop } }, { __index = f.env })
        local text = functionText("boot/StandaloneHorizon.lua", "local function HorizonUpdateTransform(")
        local transform = assert(load(text .. "\nreturn HorizonUpdateTransform", "@real-Horizon-transform", "t", henv))()
        for _, key in ipairs({ "none", "tri", "dungeon", "tower" }) do
            mode.tri, mode.dungeon, mode.tower = key == "tri", key == "dungeon", key == "tower"
            transform()
            local expected = key == "none" and 1 or f.layout.CARD_SCALE
            near(f.mods["ui.battle.combat.ProjectileSystem"].scale, expected, key .. "投射物缩放")
            near(f.mods["ui.battle.combat.BattleEffects"].scale, expected, key .. "命中特效缩放")
        end
        mode.tower = false; transform()
        near(f.mods["ui.battle.combat.ProjectileSystem"].scale, 1, "离塔恢复普通模式")
        f.open(1); f.ready()
        f.mods["ui.battle.combat.ProjectileSystem"].setRenderScale(1)
        f.mods["ui.battle.combat.BattleEffects"].setRenderScale(1)
        f.host.draw({}, 1280, 800)
        near(f.mods["ui.battle.combat.ProjectileSystem"].scale, f.layout.CARD_SCALE, "独立Tower.draw不继承旧scale")
        near(f.mods["ui.battle.combat.BattleEffects"].scale, f.layout.CARD_SCALE, "独立Tower.draw同步效果scale")
        eq(#f.stack, 0, "塔绘制归还NVG栈")
        f.host.close()
    end)
    run("塔复活正HP才播、亡魂不伪播、独立scope绘制与close重开", function()
        for _, source in ipairs({ "artifact", "talent", "ghost", "none" }) do
            local f = fixture() ---@type table
            f.open(2); f.ready()
            local lane = f.state.lanes[2] ---@type table
            local unit = lane.allies[2] ---@type table
            f.kill(unit)
            local function revive(target)
                if source == "ghost" then return true end
                target.hp = 100; target.attrs.final[f.ad.HP] = 100
                return true
            end
            if source == "artifact" or source == "ghost" then f.artifactRevive = revive
            elseif source == "talent" then f.talentRevive = revive end
            f.step(.01)
            local success = source == "artifact" or source == "talent"
            eq(#f.plays, success and 1 or 0, "仅正HP复活播放 " .. source)
            if success then
                local play = f.plays[1] ---@type table
                eq(play.scope, "tower2", "塔不借tri2/dungeon scope")
                local x, y = f.layout.posForList(lane.allies, 2)
                near(play.x, x, "复活定位第二卡x"); near(play.y, y, "复活定位第二卡y")
                check(play.width > 0 and play.height > 0, "复活特效有实际卡面尺寸")
                check(#f.texts > 0, "正HP复活有文字反馈")
                f.step(.01); eq(#f.plays, 1, "同次复活不重复播")
            elseif source == "ghost" then
                eq(unit.hp, 0, "亡魂拦截仍是死亡HP")
                check(not unit._fallenPending, "亡魂成功拦截不误进永久阵亡")
            else check(unit._fallenPending, "未救回沿原阵亡紧凑出口") end
            eq(f.artifactCalls, 1, "神器先行且每死亡只检查一次")
            eq(f.talentCalls or 0, (source == "artifact" or source == "ghost") and 0 or 1, "神器成功不再调用天赋")
            f.activeEffects["tri1"], f.activeEffects["battle"], f.activeEffects["dungeon"] = true, true, true
            f.draws, f.views = {}, {}
            f.host.draw({}, 1280, 800)
            eq(#f.views, 3, "真实Tower.draw三行卡面")
            eq(#f.draws, 3, "每行一个独立scope绘制")
            for row = 1, 3 do
                local draw, view = f.draws[row], f.views[row] ---@type table, table
                eq(draw.scope, "tower" .. row, "对应塔scope")
                check(draw.transform.clip == view.transform.clip and draw.transform.depth == view.transform.depth,
                    "特效继承本行卡面裁剪及栈深")
                near(draw.transform.sx, view.transform.sx, "特效与卡面相同缩放")
                near(draw.transform.tx, view.transform.tx, "特效与卡面相同x变换")
                near(draw.transform.ty, view.transform.ty, "特效与卡面相同y变换")
            end
            f.effectsEnabled = false; f.draws = {}
            f.host.draw({}, 1280, 800); eq(#f.draws, 0, "效果关闭塔不绘制复活层")
            f.effectsEnabled = true
            local closed = #f.cancels
            f.host.close()
            for row = 1, 3 do
                check(f.activeEffects["tower" .. row] == nil, "close清本塔scope")
            end
            check(#f.cancels >= closed + 3, "close逐行释放塔scope")
            check(f.activeEffects.tri1 and f.activeEffects.battle and f.activeEffects.dungeon, "close不清宿主/副本scope")
            f.open(1); f.ready()
            for row = 1, 3 do f.activeEffects["tower" .. row] = true end
            f.open(1)
            for row = 1, 3 do check(f.activeEffects["tower" .. row] == nil, "同进程重开清旧塔特效") end
            f.host.forceClose()
            check(f.activeEffects.tri1 and f.activeEffects.battle, "forceClose仍保留其他scope")
        end
    end)
    run("所有私有fixture原生IO与Action保持零", function()
        for _, f in ipairs(fixtures) do
            eq(f.io, 0, "File/FS/cloud/RNG原生访问为零")
            eq(f.actions, 0, "业务Action为零")
            eq(f.saves, 0, "不读取或保存玩家档")
        end
    end)
    print(TAG .. "RESULT cases=" .. cases .. " checks=" .. checks .. " failures=" .. failures)
    print(TAG .. (failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
