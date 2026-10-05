-- B03 专项：真实 Driver/Page、RCH/TAL 及塔/副本/旧Scene生命周期，隔离内存。
-- 沿用 battle_cleared_monotonic 的独立源码加载脚手架；不读写玩家档。
-- Runtime tests/rch_battle_lane_isolation_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless -nosound
-- 战斗数值/渲染叶子为替身，真实 start/mount/reset/免疫消费/击杀与复活钩子不替换。
local TAG = "[rch_lane_isolation] "
local checks, failures = 0, 0
local function check(value, label)
    checks = checks + 1
    if value then print(TAG .. "PASS " .. label)
    else failures = failures + 1; print(TAG .. "FAIL " .. label) end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

function Start()
    local ok, err = xpcall(function()
        local nativeCache = cache
        local sources = {} ---@type table<string, string>
        local function source(name)
            if sources[name] then return sources[name] end
            local path = name:gsub("%.", "/") .. ".lua"
            local file = assert(nativeCache:GetFile(path), "缺少项目源码 " .. path)
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            file:Dispose()
            sources[name] = table.concat(lines, "\n")
            return sources[name]
        end
        local function noop() end
        local function stub(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local function newProcess()
            local env = setmetatable({ time = { elapsedTime = 100 } }, { __index = _G }) ---@type any
            env.File = function() error("B03禁止访问玩家文件") end
            env.fileSystem = stub({ FileExists = function() error("B03禁止查玩家档") end })
            env.cache = stub({ GetResource = function() error("B03不加载GPU/音频资源") end })
            local deps = {} ---@type table<string, any>
            local loading = {}
            local modules = { battle = { currentStageId = 101, maxStageId = 101, clearedStages = {},
                teamStageIds = { ["1"] = 101, ["2"] = 101, ["3"] = 101 } }, player = { level = 100 } }
            local ctx = { teams = {}, drivers = {}, deps = deps, modules = modules } ---@type any
            local owned = {}
            deps["core.PlayerStore"] = stub({ Get = function(key) return modules[key] end })
            deps["runtime.ClientDispatcher"] = stub({ get = function(key) return modules[key] end })
            deps["runtime.GameAction"] = stub()
            deps["boot.StandaloneSave"] = stub()
            deps["systems.ExtraTalentSystem"] = stub({ getOwned = function(id) return owned[id] end,
                tryTicketRevive = function() return false end, getReviveRateBonus = function() return 0 end })
            deps["systems.BattleDiag"] = stub({ logEnabled = false })
            deps["systems.StoryPlayer"] = stub()
            deps["systems.OfflineCalc"] = stub({ resolveIdleStageAnchors = function() return 101, 101 end,
                calcOnlineIdleRewards = function() return { gold = 0, adventureExp = 0 } end })
            deps["core.GameState"] = stub({ getLevel = function() return 100 end })
            deps["config.ExpTable"] = { getUnlockedTeamCount = function() return 3 end }
            deps["core.I18n"] = stub({ t = function(text) return text end })
            deps["ui.character.panel.CharacterPanel"] = stub({
                getDeployedTeam = function(t) return ctx.teams[t] or {} end,
                getTeamSignature = function(t) return "b03-team-" .. t end,
                getOwnedHero = function(id) return owned[id] end,
            })
            deps["ui.battle.combat.BattleCombatAnim"] = { DEATH_ANIM_DURATION = 0.4 }
            deps["ui.battle.stage.BattleStageNav"] = { NAV = {} }
            deps["ui.battle.stage.BattleStageNavLogic"] = { bind = function() return {} end }
            deps["ui.battle.scene.BattleDataRestore"] = { bind = function() return {} end }
            deps["ui.battle.popup.TerminalConfirmDialog"] = stub({ isOpen = function() return false end })
            deps["ui.story.gate.LetterIntro"] = { isOpen = function() return false end }
            deps["ui.story.gate.IntroCutscene"] = { isActive = function() return false end }
            deps["ui.story.ScenarioDialogue"] = { isActive = function() return false end }
            deps["shared.StageProvider"] = { Get = function() return env.require("config.StageConfig") end }
            -- 只替换绘制/伤害数值叶子；每个系统状态仍以独立容器模拟正式mount契约。
            local combatDefault = { ctx = {} }
            local combatState = combatDefault
            local combat = stub({
                newState = function() return { ctx = {}, cardAnims = {}, comboQueue = {} } end,
                mount = function(s) combatState = s or combatDefault end,
                mountedState = function() return combatState end,
                setContext = function(c) combatState.ctx = c end,
                reset = function() combatState.cardAnims = {}; combatState.comboQueue = {} end,
                getAliveUnits = function(list)
                    local alive = {}
                    for _, unit in ipairs(list) do if unit.hp > 0 then alive[#alive + 1] = unit end end
                    return alive
                end,
                syncUnitHp = function(unit)
                    if unit.attrs then unit.hp = unit.attrs:get("hp"); unit.maxHp = unit.attrs:get("maxHp") end
                end,
                getCardPos = function() return 100, 100 end,
                getCardCX = function() return 100 end,
                DEATH_ANIM_DURATION = 0.4, REVIVE_ANIM_DURATION = 0.35,
            })
            deps["ui.battle.combat.BattleCombat"] = combat
            for _, name in ipairs({ "ui.battle.combat.ProjectileSystem", "ui.battle.combat.BattleEffects" }) do
                local default = {}
                local current = default
                deps[name] = stub({ newState = function() return {} end, newFxState = function() return {} end,
                    mount = function(s) current = s or default end, mountedState = function() return current end,
                    getImageKeys = function() return {} end })
            end
            local realUI = {
                ["ui.battle.tri.BattleTriDriver"] = true, ["ui.battle.tri.BattleTriPage"] = true,
                ["ui.tower.TowerTriBattle"] = true, ["ui.tower.TowerWaveSplit"] = true,
                ["ui.dungeon.DungeonBattleScene"] = true, ["ui.dungeon.DungeonBattle"] = true,
                ["ui.battle.scene.BattleRuntimeContext"] = true,
                ["ui.battle.scene.BattleScene"] = true, ["ui.battle.scene.BattleAllyLifecycle"] = true,
                ["ui.battle.stage.BattleStageFlow"] = true, ["ui.battle.stage.BattleStageLoad"] = true,
                ["ui.battle.scene.BattleAllyReset"] = true, ["ui.battle.stage.BattleEnemySpawn"] = true,
                ["ui.battle.stage.StageBerserk"] = true,
            }
            env.require = function(name)
                if deps[name] ~= nil then return deps[name] end
                local isReal = name:match("^config%.") or name:match("^systems%.") or name:match("^shared%.")
                    or name == "core.BattleLayout" or name == "core.NumberUtil" or realUI[name]
                if not isReal then deps[name] = stub(); return deps[name] end
                assert(not loading[name], "循环依赖 " .. name)
                loading[name] = true
                local value = assert(load(source(name), "@真实B03/" .. name, "t", env))()
                loading[name] = nil
                deps[name] = value
                return value
            end
            local AD = env.require("systems.AttributeDef")
            local UA = env.require("systems.UnitAttributes")
            local function hero(id, resonance)
                local unit = { heroId = id, name = "B03合成角色" .. id, hp = 1000, maxHp = 1000,
                    awakeningNodes = { [1] = true, [2] = resonance == true, _awk3Migrated = true },
                    atkProgress = 0, classId = "spoil", advTalentIds = {}, litNodeSet = {},
                    attrs = UA.create({ [AD.MAX_HP] = 1000, [AD.PHYS_ATK] = 10,
                        [AD.THREAT] = 1, atkType = AD.ATK_SLASH }) }
                owned[id] = { awakening = unit.awakeningNodes, extraTalent = {} }
                return unit
            end
            ctx.hero, ctx.env, ctx.combat = hero, env, combat
            ctx.rch = env.require("systems.RelicConditionHandler")
            ctx.tal = env.require("systems.TalentManager")
            local Driver = env.require("ui.battle.tri.BattleTriDriver")
            local makeDriver = Driver.new
            Driver.new = function(t, options)
                local drv = makeDriver(t, options)
                ctx.drivers[t] = drv
                return drv
            end
            ctx.page = env.require("ui.battle.tri.BattleTriPage")
            ctx.scene = env.require("ui.battle.scene.BattleScene")
            ctx.tower = env.require("ui.tower.TowerTriBattle")
            ctx.dungeon = env.require("ui.dungeon.DungeonBattleScene")
            ctx.monster = function() return env.require("config.MonsterConfig").createMonster(1, 1) end
            ctx.kill = function(unit)
                unit.hp = 0; unit.attrs.final[AD.HP] = 0
            end
            ctx.hit = function(drv, unit, expected, label)
                drv:activate()
                eq(ctx.rch.onBeforeTakeDamage(unit, 25), expected, label)
            end
            ctx.count = function(drv, unit, expected, label)
                drv:activate()
                eq(ctx.rch.getImmunityCount(unit), expected, label)
            end
            ctx.open = function()
                for t = 1, 3 do ctx.teams[t] = { hero(14, true) } end
                ctx.page.open()
            end
            return ctx
        end
        local function case(name, fn)
            local caseOk, caseErr = xpcall(fn, debug.traceback)
            if not caseOk then check(false, name .. "异常: " .. tostring(caseErr)) end
        end
        case("正式Page三队开战与消费", function()
            local p = newProcess()
            p.open()
            for t = 1, 3 do p.count(p.drivers[t], p.teams[t][1], 10, "真实Page队" .. t .. "开场10") end
            local a, b, c = p.teams[1][1], p.teams[2][1], p.teams[3][1]
            p.hit(p.drivers[1], a, 0, "队1免疫第1击")
            p.hit(p.drivers[1], a, 0, "队1免疫第2击")
            p.drivers[2]:start(101)
            p.drivers[3]:start(101)
            p.count(p.drivers[1], a, 8, "队2开场/队3重开后队1仍8")
            p.count(p.drivers[2], b, 10, "队2重开仅本队重发10")
            p.count(p.drivers[3], c, 10, "队3重开仅本队重发10")
            p.hit(p.drivers[2], b, 0, "队2命中仅消费本队")
            p.count(p.drivers[1], a, 8, "队2消费后队1仍8")
            p.count(p.drivers[2], b, 9, "队2剩9")
            p.count(p.drivers[3], c, 10, "队3仍10")
            p.drivers[3]:retreatStage()
            p.count(p.drivers[1], a, 8, "队3真实退关不清队1")
            p.count(p.drivers[2], b, 9, "队3真实退关不清队2")
            p.drivers[1]:activate()
            eq(p.rch.onBeforeTakeDamage(a, 0), 0, "零伤害不消费免疫")
            eq(p.rch.getImmunityCount(a), 8, "零伤害后仍8")
            local foe = p.monster()
            p.kill(foe)
            local before = p.rch.getImmunityCount(a)
            p.tal.onEnemyDeath(foe, { a }, { foe })
            local after = p.rch.getImmunityCount(a)
            check(after == before + 1 or after == before + 2, "真实TAL击杀合法追加1或2次")
            p.tal.onEnemyDeath(foe, { a }, { foe })
            eq(p.rch.getImmunityCount(a), after, "重复死亡扫描不重复追加")
            p.count(p.drivers[2], b, 9, "队1击杀追加不串队2")
            print(TAG .. "EVIDENCE tri=" .. after .. ",9,10 expected=9-or-10,9,10")
            p.page.close()
        end)
        case("旧BattleScene重载与返回只挂载", function()
            local p = newProcess()
            p.open()
            local a = p.teams[1][1]
            p.hit(p.drivers[1], a, 0, "旧场景前主线消费1")
            local old = p.hero(14, true)
            p.scene.setAllies({ old })
            eq(p.rch.getImmunityCount(old), 10, "真实旧Scene setAllies开场10")
            eq(p.rch.onBeforeTakeDamage(old, 25), 0, "旧Scene消费1")
            p.scene.restoreContext()
            eq(p.rch.getImmunityCount(old), 9, "旧Scene restoreContext不得重发开场或抹额度")
            p.count(p.drivers[1], a, 9, "旧Scene真实reset不清正式主线")
            p.scene.reloadStage()
            p.count(p.drivers[1], a, 9, "旧Scene真实load/reload不清正式主线")
            p.page.close()
        end)
        case("塔三行与退出恢复", function()
            local p = newProcess()
            p.open()
            local main = p.teams[1][1]
            p.hit(p.drivers[1], main, 0, "塔前主线消费1")
            p.hit(p.drivers[1], main, 0, "塔前主线消费2")
            local mainRch = p.rch.mountedState and p.rch.mountedState()
            local mainTal = p.tal.mountedState()
            local towerTeams = { { p.hero(14, true) }, { p.hero(14, true) }, { p.hero(14, true) } }
            local towerRch = {}
            local originalStart = p.tal.onBattleStart
            p.tal.onBattleStart = function(allies, enemies)
                if p.rch.mountedState then towerRch[#towerRch + 1] = p.rch.mountedState() end
                return originalStart(allies, enemies)
            end
            p.tower.open({ teamAllies = towerTeams, data = { dungeonId = "babel_tower", floor = 1,
                wave = 1, monsterLevel = 1, monsters = { 1, 1, 1 }, rageTime = 999, superRageTime = 9999 } })
            p.tal.onBattleStart = originalStart
            if p.rch.mount and #towerRch == 3 then
                for t = 1, 3 do
                    p.rch.mount(towerRch[t])
                    eq(p.rch.getImmunityCount(towerTeams[t][1]), 10, "塔每线开场10 队" .. t)
                end
                p.rch.mount(towerRch[1])
                eq(p.rch.onBeforeTakeDamage(towerTeams[1][1], 25), 0, "塔线1消费免疫")
                p.rch.mount(towerRch[2])
                eq(p.rch.getImmunityCount(towerTeams[2][1]), 10, "塔线1消费不串线2")
            end
            p.drivers[2]:activate() -- 模拟宿主在close之前挂了别线，cleanup必须显式选塔容器。
            p.tower.forceClose()
            if p.rch.mountedState then eq(p.rch.mountedState(), mainRch, "塔退场恢复进入前RCH容器") end
            eq(p.tal.mountedState(), mainTal, "塔退场恢复进入前TAL引用")
            p.count(p.drivers[1], main, 8, "塔开场/退场主线仍8")
            p.count(p.drivers[2], p.teams[2][1], 10, "塔cleanup不清挂着的队2")
            p.page.close()
        end)
        case("副本重开/失败/正常与强制关闭", function()
            for _, closeName in ipairs({ "close", "forceClose" }) do
                local p = newProcess()
                p.open()
                local main = p.teams[1][1]
                p.hit(p.drivers[1], main, 0, "副本前主线消费1 " .. closeName)
                p.hit(p.drivers[1], main, 0, "副本前主线消费2 " .. closeName)
                local mainRch = p.rch.mountedState and p.rch.mountedState()
                local mainTal = p.tal.mountedState()
                local guest = p.hero(14, true)
                local opts = { allies = { guest }, data = { dungeonId = "gold_mine", floor = 1,
                    wave = 1, monsterLevel = 1, monsters = { { id = 1, count = 2 } },
                    rageTime = 999, superRageTime = 9999 } }
                p.dungeon.open(opts)
                eq(p.rch.getImmunityCount(guest), 10, "副本开场10 " .. closeName)
                eq(p.rch.onBeforeTakeDamage(guest, 25), 0, "副本消费1 " .. closeName)
                p.dungeon.open(opts)
                eq(p.rch.getImmunityCount(guest), 10, "副本重开仅本场重发10 " .. closeName)
                p.drivers[2]:activate()
                p.dungeon[closeName]()
                if p.rch.mountedState then eq(p.rch.mountedState(), mainRch, "副本恢复RCH " .. closeName) end
                eq(p.tal.mountedState(), mainTal, "副本恢复TAL " .. closeName)
                p.count(p.drivers[1], main, 8, "副本退场主线仍8 " .. closeName)
                p.count(p.drivers[2], p.teams[2][1], 10, "副本cleanup不清挂着的队2 " .. closeName)
                p.drivers[1]:activate()
                local DB = p.env.require("ui.dungeon.DungeonBattle")
                local generate = DB.generateEnemies
                DB.generateEnemies = function() error("B03预期副本初始化失败") end
                local failed = pcall(p.dungeon.open, opts)
                DB.generateEnemies = generate
                check(not failed and not p.dungeon.isOpen(), "副本失败清理可见错误并退场 " .. closeName)
                p.count(p.drivers[1], main, 8, "副本失败不清主线 " .. closeName)
                p.page.close()
            end
        end)
        case("整组规则容器恢复与塔初始化失败", function()
            local p = newProcess()
            p.open()
            local Runtime = p.env.require("ui.battle.scene.BattleRuntimeContext")
            local main = p.teams[1][1]
            p.drivers[1]:activate()
            p.rch.onBeforeTakeDamage(main, 25)
            p.rch.onBeforeTakeDamage(main, 25)
            local saved = Runtime.capture()
            local ruleFields = { "mapAffixState", "bossAffixState", "berserkState" }
            for _, field in ipairs(ruleFields) do saved[field]._b03Sentinel = "main-" .. field end
            local function restored(label)
                local actual = Runtime.capture()
                for _, field in ipairs(ruleFields) do
                    eq(actual[field], saved[field], label .. "恢复原" .. field .. "对象")
                    eq(actual[field]._b03Sentinel, "main-" .. field, label .. "原规则状态数值不清")
                end
                eq(p.rch.getImmunityCount(main), 8, label .. "恢复未消费免疫8")
            end
            local guest = p.hero(14, true)
            local dungeonOpts = { allies = { guest }, data = { dungeonId = "gold_mine", floor = 1,
                monsterLevel = 1, monsters = { { id = 1, count = 1 } }, rageTime = 999, superRageTime = 9999 } }
            p.dungeon.open(dungeonOpts)
            local isolated = Runtime.capture()
            for _, field in ipairs(ruleFields) do
                check(isolated[field] ~= saved[field] and isolated[field]._b03Sentinel == nil,
                    "副本独立空规则容器 " .. field)
            end
            p.dungeon.forceClose()
            restored("副本退出")
            local towerOpts = { teamAllies = { { guest }, { p.hero(14, true) }, { p.hero(14, true) } },
                data = { dungeonId = "babel_tower", floor = 1, wave = 1,
                    monsterLevel = 1, monsters = { 1, 1, 1 }, rageTime = 999, superRageTime = 9999 } }
            p.tower.open(towerOpts)
            isolated = Runtime.capture()
            for _, field in ipairs(ruleFields) do
                check(isolated[field] ~= saved[field] and isolated[field]._b03Sentinel == nil,
                    "塔独立空规则容器 " .. field)
            end
            p.tower.forceClose()
            restored("塔退出")
            local originalStart = p.tal.onBattleStart
            local starts = 0
            p.tal.onBattleStart = function(allies, enemies)
                starts = starts + 1
                originalStart(allies, enemies)
                if starts == 2 then error("B03预期塔第二线初始化失败") end
            end
            local didOpen = pcall(p.tower.open, towerOpts)
            p.tal.onBattleStart = originalStart
            check(not didOpen and not p.tower.isOpen() and starts == 2,
                "塔部分初始化真实失败后退场，错误不吞")
            restored("塔失败")
            p.scene.setAllies({ p.hero(14, true) })
            p.drivers[1]:activate()
            restored("旧Scene默认挂载后")
            p.page.update(0)
            local default = Runtime.capture()
            for _, field in ipairs(ruleFields) do check(default[field] ~= saved[field], "Page收尾恢复默认 " .. field) end
            p.drivers[1]:activate()
            restored("Page收尾未重置主线")
            p.page.close()
        end)
        case("真实宿主永久敌退场注销", function()
            local p = newProcess()
            p.open()
            local d1, d2 = p.drivers[1], p.drivers[2]
            local oldEnemy = d1.enemies[1]
            d1:activate()
            p.rch.addImmunityCharges(oldEnemy, 4)
            p.kill(oldEnemy)
            d1._tickDt = 0.1
            d1:reinforceDeadEnemies()
            eq(p.rch.getImmunityCount(oldEnemy), 4, "敌人尚在退场等待保留状态")
            d1._tickDt = 2
            d1.reinforceCd = 0
            d1:reinforceDeadEnemies()
            eq(p.rch.getImmunityCount(oldEnemy), 0, "Driver真实替换时注销旧敌状态")
            p.count(d2, p.teams[2][1], 10, "敌人注销不串另一线")
            d1:activate()
            local guest = p.hero(14, true)
            p.dungeon.open({ allies = { guest }, data = { dungeonId = "gold_mine", floor = 1,
                monsterLevel = 1, monsters = { { id = 1, count = 6 } }, rageTime = 999, superRageTime = 9999 } })
            local enemies = p.combat.mountedState().ctx.getEnemies()
            for _, enemy in ipairs(enemies) do p.rch.addImmunityCharges(enemy, 4); p.kill(enemy) end
            p.dungeon.update(0)
            for _, enemy in ipairs(enemies) do eq(p.rch.getImmunityCount(enemy), 0, "副本真实换批注销旧敌") end
            p.dungeon.forceClose()
            p.page.close()
        end)
        case("TAL弱键回收保留活单位与合法复活状态", function()
            local p = newProcess()
            local TAL = p.tal
            TAL.mount(TAL.newBattleRefs())
            local watcher = setmetatable({}, { __mode = "v" })
            do
                local retired = p.hero(14, false)
                TAL.initUnit(retired)
                watcher[1] = retired
            end
            collectgarbage("collect"); collectgarbage("collect")
            check(watcher[1] == nil, "真实TAL不强持已无外部引用的退场单位")
            local live = p.hero(14, true)
            TAL.initUnit(live)
            TAL.onBattleStart({ live }, {})
            live.litNodeSet[125] = true
            p.kill(live)
            check(TAL.onAllyDeath(live, { live }, p.combat.syncUnitHp), "GC对照首次合法复活")
            p.kill(live)
            collectgarbage("collect"); collectgarbage("collect")
            check(not TAL.onAllyDeath(live, { live }, p.combat.syncUnitHp),
                "仍由战线持有的阵亡等待单位GC不丢已用复活状态")
            eq(p.rch.getImmunityCount(live), 10, "GC不影响仍持有活/阵亡单位免疫10")
            TAL.reset()
            TAL.mount(TAL.newBattleRefs())
            do
                local retiredAfterReset = p.hero(14, false)
                TAL.initUnit(retiredAfterReset)
                watcher[2] = retiredAfterReset
            end
            collectgarbage("collect"); collectgarbage("collect")
            check(watcher[2] == nil, "无参TAL reset后的新表仍为弱键")
        end)
        case("容器API原位清理/注销/完整条件与复活", function()
            local p = newProcess()
            local RCH, TAL = p.rch, p.tal
            if not (RCH.newState and RCH.mount and RCH.mountedState and RCH.removeUnit) then
                check(false, "RCH必须提供newState/mount/mountedState/removeUnit容器API")
                return
            end
            local a, b = RCH.newState(), RCH.newState()
            local unit = p.hero(14, true)
            local other = p.hero(14, true)
            local AD = p.env.require("systems.AttributeDef")
            unit.relicConditions = {
                { condition = "战斗开始时免疫伤害次数+3", value = 3 },
                { condition = "战斗开始时初次攻击伤害加成+25%", value = 25 },
                { condition = "满血时", adKey = AD.PHYS_ATK, value = 5 },
                { kind = "great_aegis", value = 1 },
                { condition = "对血量低于30%增伤", value = 20 },
            }
            RCH.mount(a); RCH.initBattle({ unit })
            RCH.update({ unit }, 0)
            check(unit.attrs.modifiers.relic_cond_3 ~= nil, "真实RCH满血修饰符已施加")
            eq(RCH.onBeforeAttack(unit), 1.25, "初攻增伤第一次25%")
            eq(RCH.onBeforeAttack(unit), 1, "初攻增伤只一次")
            local target = p.hero(1, false); target.hp = 100
            eq(RCH.getDamageBonus(unit, target), 20, "低血目标增伤20%")
            RCH.mount(b); RCH.initBattle({ other }); RCH.addImmunityCharges(other, 7)
            RCH.removeUnit(unit)
            eq(RCH.getImmunityCount(other), 7, "错线注销不得清本线其他单位")
            RCH.mount(a)
            eq(RCH.getImmunityCount(unit), 3, "错线注销不清其他容器")
            local unitsTable = a.unitStates
            RCH.initBattle({ unit })
            eq(a.unitStates, unitsTable, "init原位清理容器表，句柄不失效")
            check(unit.attrs.modifiers.relic_cond_3 == nil, "init移除上一场活跃条件修饰符")
            RCH.removeUnit(unit)
            eq(RCH.getImmunityCount(unit), 0, "注销单位释放仅本线状态")
            RCH.mount(b); eq(RCH.getImmunityCount(other), 7, "其他容器额度保留7")
            local refs = TAL.newBattleRefs(); TAL.mount(refs)
            TAL.initUnit(other); TAL.onBattleStart({ other }, {})
            -- 合法死亡/复活不触发新开场；免疫计数保持，不补10。
            other.litNodeSet[125] = true
            p.kill(other)
            check(TAL.onAllyDeath(other, { other }, p.combat.syncUnitHp), "真实不死鸟合法复活一次")
            eq(RCH.getImmunityCount(other), 17, "合法复活不重发开场17")
            local before = RCH.getImmunityCount(other)
            p.kill(other)
            TAL.reset({ unit })
            check(not TAL.onAllyDeath(other, { other }, p.combat.syncUnitHp), "别线TAL reset不重置已用复活次数")
            eq(RCH.getImmunityCount(other), before, "第二死亡不抹或补免疫")
            RCH.reset(); eq(b.unitStates and next(b.unitStates), nil, "reset本容器原位清空")
            RCH.mount(a); eq(RCH.getImmunityCount(unit), 0, "已注销容器不复活旧状态")
        end)
    end, debug.traceback)
    if not ok then check(false, "测试初始化异常: " .. tostring(err)) end
    print(string.format(TAG .. "SUMMARY checks=%d failures=%d", checks, failures))
    print(TAG .. (failures == 0 and "RESULT ALL PASS" or "RESULT FAIL"))
    if failures > 0 then log:Write(LOG_ERROR, TAG .. "failures=" .. failures) end
    engine:Exit()
end
