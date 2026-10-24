-- 三队正式 Driver:start 首通剧情怪回归：只读真实源码，隔离 GPU/声音/玩家文件叶子。
-- 基于 team_drop_luck/resource_dungeon_battle 的私有 require 实例模式，不拷贝 start 片段。
-- 运行 tests/tri_story_spawn_test.lua -tapcode_dir=/workspace/game2 -tool_mode -graphicsheadless -nosound。
-- 必须读 RESULT ALL PASS checks=N；Runtime exit 0 不是通过凭据。
-- 同时复用私有实例验证Driver同步分段：真实Monitor开关、回调后绑定、错误/返回/RNG/协程边界。
local TAG = "[tri_story_spawn] "
local checks = 0
local function check(value, label)
    checks = checks + 1
    assert(value, label)
    print(TAG .. "PASS " .. label)
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function noop() end

local function fixture(options)
    options = options or {}
    local nativeCache = cache
    local env = setmetatable({}, { __index = _G }) ---@type any
    local loaded = {} ---@type table<string, any>
    local loading = {} ---@type table<string, boolean>
    local realLoads = {} ---@type table<string, boolean>
    local records = { liveReads = 0, savedReads = 0, panelCalls = 0, factoryCalls = 0,
        gpuCalls = 0, fileCalls = 0, actions = 0, affixes = {}, generated = {}, marked = {} }
    local data = { live = {}, battle = { clearedStages = {} },
        session = { introCompleted = true, initialHeroId = 1, claimedScenarios = {}, scenarioRewardsGranted = {} } } ---@type any
    env._G, env.math, env.time = env, copy(math), { elapsedTime = 100 }
    if options.performance then
        records.clock = { wall = 0, cpu = 0, wallReads = 0, cpuReads = 0, rngCalls = 0 }
        local clock = records.clock
        env.os = copy(os)
        env.os.clock = function() return clock.cpu end -- 业务自身时钟与监测读取分开计数。
        env.Time = { GetSystemTime = function(receiver)
            assert(receiver == env.Time, "计时必须使用Time静态接收者")
            clock.wallReads = clock.wallReads + 1
            return clock.wall
        end }
        env.collectgarbage = function(kind) assert(kind == "count"); return 1024 end
        env.graphics = { GetNumBatches = function() return 0 end, GetNumPrimitives = function() return 0 end }
        -- 私有可重放RNG，不改全局种子；开启/关闭使用完全相同的输入流。
        local seed = 1729
        env.math.random = function(low, high)
            seed = (seed * 48271) % 2147483647
            clock.rngCalls, clock.rngState = clock.rngCalls + 1, seed
            local value = seed / 2147483647
            if low == nil then return value end
            if high == nil then high, low = low, 1 end
            return low + math.floor(value * (high - low + 1))
        end
        env.math.randomseed = function() error("专项不能重设RNG") end
    end
    env.package = { loaded = loaded, preload = {}, path = "" }
    env.print = noop -- 只关业务高频初始化日志；断言/异常由外层输出。
    local function forbiddenFile()
        records.fileCalls = records.fileCalls + 1
        error("专项禁止读写玩家文件/存档")
    end
    local function forbiddenGPU()
        records.gpuCalls = records.gpuCalls + 1
        error("专项禁止创建GPU/声音资源")
    end
    env.File = forbiddenFile
    env.fileSystem = setmetatable({}, { __index = function() return forbiddenFile end })
    env.cache = {
        GetFile = function(_, path)
            assert(type(path) == "string" and path:match("%.lua$") and not path:find("..", 1, true),
                "只读项目Lua资源 " .. tostring(path))
            return nativeCache:GetFile(path)
        end,
        GetResource = forbiddenGPU,
    }
    env.nvgCreate, env.nvgCreateImage, env.nvgCreateFont = forbiddenGPU, forbiddenGPU, forbiddenGPU
    env.Scene, env.Sound, env.VideoPlayer = forbiddenGPU, forbiddenGPU, forbiddenGPU
    loaded["runtime.ClientDispatcher"] = { get = function(key)
        if key == "battle" then records.savedReads = records.savedReads + 1 end
        return data[key]
    end }
    loaded["core.PlayerStore"] = { Get = function(key) return data[key] end }
    loaded["ui.battle.scene.BattleScene"] = { getClearedStages = function()
        records.liveReads = records.liveReads + 1
        return data.live
    end }
    loaded["ui.character.panel.CharacterPanel"] = {
        getTeamSignature = function(t) records.panelCalls = records.panelCalls + 1; return "fixture-team-" .. t end,
        getDeployedTeam = function(t)
            records.panelCalls = records.panelCalls + 1
            return { assert(env.require("config.HeroConfig").createHero(t, 3, nil, nil, false)) }
        end,
    }
    loaded["systems.GameSFX"] = { play = noop, playHit = noop, playHeroAttack = noop,
        playMonsterAttack = noop, playDeath = noop, playUI = noop }
    loaded["ui.hud.popup.SettingsPanel"] = { isEffectsEnabled = function() return true end,
        isDamageNumbersEnabled = function() return false end }
    loaded["ui.widget.SpeechBubble"] = { trigger = noop, reset = noop, update = noop }
    loaded["ui.hud.BottomNav"] = { setSelectedIndex = noop, setAllLocked = noop }
    loaded["runtime.GameAction"] = { sendAction = function()
        records.actions = records.actions + 1
        error("专项不允许玩家动作")
    end }
    loaded["boot.StandaloneSave"] = { Flush = forbiddenFile,
        RequestSave = options.performance and function() records.saveRequests = (records.saveRequests or 0) + 1 end or forbiddenFile }
    env.require = function(name)
        if loaded[name] ~= nil then return loaded[name] end
        assert(not loading[name], "未隔离的循环依赖 " .. name)
        assert(not name:match("^rules%.") and not name:match("^boot%."), "专项禁止加载玩家规则/存档 " .. name)
        loading[name] = true
        local path = name:gsub("%.", "/") .. ".lua"
        local file = assert(env.cache:GetFile(path), "缺少真实源码 " .. path)
        assert(file:IsOpen(), "源码无法打开 " .. path)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        local moduleEnv = env
        if options.performance and name == "core.PerformanceMonitor" then
            moduleEnv = setmetatable({ os = { clock = function()
                records.clock.cpuReads = records.clock.cpuReads + 1
                return records.clock.cpu
            end } }, { __index = env })
        end
        local chunk = assert(load(table.concat(lines, "\n"), "@tri-story/" .. path, "t", moduleEnv))
        local value = chunk()
        assert(value ~= nil, "真实模块未返回实例 " .. name)
        loaded[name], realLoads[name], loading[name] = value, true, nil
        return value
    end
    local Driver = env.require("ui.battle.tri.BattleTriDriver")
    local SC = env.require("config.StageConfig")
    local Spawn = env.require("ui.battle.stage.BattleEnemySpawn")
    local Story = env.require("systems.StoryPlayer")
    local Entries = env.require("ui.battle.stage.StageEntryEvents")
    local MAS = env.require("systems.MapAffixSystem")
    local BAS = env.require("systems.BossAffixSystem")
    local Berserk = env.require("ui.battle.stage.StageBerserk")
    for _, name in ipairs({ "ui.battle.tri.BattleTriDriver", "ui.battle.stage.BattleEnemySpawn",
        "config.MonsterConfig", "config.StageConfig", "systems.UnitAttributes", "ui.battle.combat.BattleCombat",
        "systems.TalentManager", "systems.StoryPlayer", "ui.battle.stage.StageEntryEvents" }) do
        check(realLoads[name] == true, "完整真实require实例 " .. name)
    end
    local generate, mark = Spawn.generateEnemyList, Spawn.markFirstClearBonusSpawnPhase
    Spawn.generateEnemyList = function(entry, first)
        records.generated[#records.generated + 1] = { entry = entry, first = first }
        return generate(entry, first)
    end
    Spawn.markFirstClearBonusSpawnPhase = function(unit, index, count)
        records.marked[#records.marked + 1] = { unit = unit, index = index, count = count }
        return mark(unit, index, count)
    end
    local function spy(module, name, key)
        local original = assert(module[name], "缺少真实API " .. name)
        module[name] = function(...)
            records.affixes[key] = (records.affixes[key] or 0) + 1
            return original(...)
        end
    end
    spy(MAS, "onStageLoad", "mapLoad"); spy(MAS, "applyStaticAffixes", "mapApply"); spy(MAS, "tick", "mapTick")
    spy(BAS, "onStageLoad", "bossLoad"); spy(BAS, "applyToBosses", "bossApply"); spy(BAS, "clear", "bossClear")
    spy(Berserk, "enter", "berserkEnter"); spy(Berserk, "exit", "berserkExit")
    local function reset(live, saved, hero)
        data.live = live or {}
        data.battle = { clearedStages = saved or {}, currentStageId = 204, maxStageId = 4905 }
        data.session = { introCompleted = true, initialHeroId = hero or 1,
            claimedScenarios = {}, scenarioRewardsGranted = {} }
        Story.resetAll(); Entries.reset()
        records.generated, records.marked = {}, {}
    end
    return { require = env.require, Driver = Driver, SC = SC, Spawn = Spawn, Story = Story,
        Entries = Entries, MAS = MAS, BAS = BAS, Berserk = Berserk, data = data, records = records, reset = reset }
end

local function wave(drv)
    local list = {}
    for _, unit in ipairs(drv.enemies) do list[#list + 1] = unit end
    for _, unit in ipairs(drv.enemyQueue) do list[#list + 1] = unit end
    return list
end
local function countId(list, id)
    local count = 0
    for _, unit in ipairs(list) do if unit.monsterId == id then count = count + 1 end end
    return count
end
local function checkWave(f, drv, stageId, first, expectedBonus, label)
    local entry = assert(f.SC.getStage(stageId))
    local list = wave(drv)
    local bonus = first and expectedBonus or {}
    eq(drv.stageId, stageId, label .. "消费目标关")
    eq(drv.battleLab, false, label .. "正式非lab路径")
    eq(#list, (first and entry.firstCount or entry.idleCount) + #bonus, label .. "真实firstCount/idleCount加bonus")
    eq(drv.stageTotal, #list, label .. "stageTotal包括队列")
    eq(#drv.enemies, math.min(entry.maxFieldEnemies, f.require("core.BattleLayout").MAX_PER_SIDE), label .. "同屏上限")
    check(drv.active and drv._started and drv.introTimer > 0, label .. "真实开战与入场计时")
    local generated = f.records.generated[#f.records.generated]
    eq(generated.entry, entry, label .. "完整配置原表透传真生成器")
    eq(generated.first, first, label .. "首通快照透传而非options.firstClear")
    eq(#f.records.marked, #bonus, label .. "正式markPhase调用数")
    local bossCount, markedCount = 0, 0
    for _, unit in ipairs(list) do
        check(unit.hp > 0 and unit.attrs ~= nil, label .. "真MonsterConfig/UnitAttributes单位")
        eq(unit.level, entry.monsterLevel, label .. "等级与当前entry一致")
        if unit.isBoss then bossCount = bossCount + 1 end
        if unit._isBonusMonster then markedCount = markedCount + 1 end
    end
    eq(bossCount, entry.bossId > 0 and 1 or 0, label .. "普通Boss未被附加怪覆盖")
    eq(markedCount, #bonus, label .. "没有误标普通怪")
    for index, id in ipairs(expectedBonus) do
        eq(countId(list, id), first and 1 or 0, label .. "剧情怪" .. id .. "恰一次/已通无")
        if first then
            local phase = index == 1 and "start" or index == #bonus and "end" or "middle"
            local marked = f.records.marked[index]
            eq(marked.unit.monsterId, id, label .. "标记对应正确附加单位")
            eq(marked.unit._bonusSpawnPhase, phase, label .. "阶段标记" .. phase)
            eq(marked.index, index, label .. "阶段索引")
            eq(marked.count, #bonus, label .. "阶段总数")
            if phase == "start" then
                eq(countId(drv.enemies, id), 1, label .. "开场剧情怪在field而非队列")
                eq(countId(drv.enemyQueue, id), 0, label .. "开场剧情怪未重复入queue")
                eq(drv.combatState.cardAnims[marked.unit].state, "entering", label .. "真实卡牌入场动画")
            end
        end
    end
end

local function productionCases(f)
    local stories = {
        { id = 204, bonus = 1004, story = 41 }, { id = 2505, bonus = 1005, story = 64 },
        { id = 2705, bonus = 1006, story = 65 }, { id = 2905, bonus = 1007, story = 67 },
        { id = 4705, bonus = 1005, story = 71 }, { id = 4805, bonus = 1006, story = 72 },
        { id = 4905, bonus = 1007, story = 73 },
    }
    -- 正式三队不能加载/清除全局MAS/BAS，保留已有宿主词缀实例作为哨兵。
    -- MapAffixConfig从折磨II chapter139起才非空；使用实际139章作为哨兵。
    f.MAS.onStageLoad(139, {}); f.BAS.onStageLoad(139, f.SC.DIFFICULTY_TORMENT2)
    local mapBefore, bossBefore = f.MAS.getActiveAffixes(), f.BAS.getActiveAffixes()
    check(f.MAS.hasAffixes() and f.BAS.hasAffixes(), "词缀哨兵是真非空正式配置")
    f.records.affixes = {}
    local drivers = {}
    for t = 1, 3 do drivers[t] = f.Driver.new(t, { firstClear = t == 2 }) end
    for _, case in ipairs(stories) do
        eq(f.SC.getStage(case.id).firstClearBonusMonster, case.bonus, "正式剧情映射 " .. case.id)
        local mirror
        for t = 1, 3 do
            local drv = drivers[t]
            local label = "队" .. t .. " stage=" .. case.id
            f.reset()
            drv:start(case.id)
            checkWave(f, drv, case.id, true, { case.bonus }, label .. "首次")
            local pending = f.Story.take("battle")
            eq(pending and pending.scenarioId, case.story, label .. "实际进场配套剧情")
            eq(f.Story.take("battle"), nil, label .. "未重复入队")
            if mirror then
                eq(drv.stageTotal, mirror, label .. "三队镜像数量")
            else mirror = drv.stageTotal end
            -- 其他队首通只改共享账本，不追溯修改本场敌人；真正start再取新快照。
            local oldField, oldQueue = drv.enemies, drv.enemyQueue
            f.data.battle.clearedStages[tostring(case.id)] = true
            eq(drv.enemies, oldField, label .. "账本变化不回灌在场数组")
            eq(drv.enemyQueue, oldQueue, label .. "账本变化不回灌后备数组")
            eq(countId(wave(drv), case.bonus), 1, label .. "本场首通快照保留")
            f.records.marked = {}
            drv:start(case.id)
            checkWave(f, drv, case.id, false, { case.bonus }, label .. "已通重开")
            eq(f.Story.take("battle"), nil, label .. "同关重开入场事件会话去重")
            -- 四来源逐一为唯一true，其余键false，不能被另一个false覆盖。
            for _, source in ipairs({ "live", "saved" }) do
                for _, key in ipairs({ case.id, tostring(case.id) }) do
                    local numeric, text = { [case.id] = false, [tostring(case.id)] = false },
                        { [case.id] = false, [tostring(case.id)] = false }
                    if source == "live" then numeric[key] = true else text[key] = true end
                    f.reset(numeric, text)
                    drv:start(case.id)
                    checkWave(f, drv, case.id, false, { case.bonus }, label .. "已通" .. source .. "/" .. type(key))
                end
            end
            f.reset({ [case.id] = 1, [tostring(case.id)] = false },
                { [case.id] = "true", [tostring(case.id)] = false })
            drv:start(case.id)
            checkWave(f, drv, case.id, true, { case.bonus }, label .. "非boolean不得算已通")
        end
    end
    -- 204的主角分支使用账号初始英雄，而非运行驱动teamIdx。
    for hero = 1, 3 do
        f.reset(nil, nil, hero)
        drivers[3]:start(204)
        eq(f.Story.take("battle").scenarioId, 40 + hero, "204入场按初始英雄分支" .. hero)
    end
    eq(next(f.records.affixes), nil, "全部正式Driver:start未解除MAS/BAS/Berserk lab-only")
    eq(f.MAS.getActiveAffixes(), mapBefore, "正式三队保留宿主MAS原实例")
    eq(f.BAS.getActiveAffixes(), bossBefore, "正式三队保留宿主BAS原实例")
    return drivers
end

local function resourceAndTerminalCases(f, drivers)
    local DC = f.require("config.DungeonConfig")
    for _, id in ipairs(DC.RESOURCE_IDS) do
        -- 找真实借用有剧情附加怪的主线层，证明资源entry确实剥离bonus而非空白负例。
        local chosen, original
        for floor = 2, DC.MAX_FLOOR[id] do
            local entry = DC.getCombatEntry(id, floor)
            local source = f.SC.getStage(entry.id)
            if source.firstClearBonusMonster or source.firstClearBonusMonsters then
                chosen, original = floor, source
                break
            end
        end
        check(chosen ~= nil and original ~= nil, id .. "存在真实借用剧情怪源关")
        local resourceId = DC.getStageId(id, chosen)
        local entry = f.SC.getStage(resourceId)
        eq(entry.sourceStageId, original.id, id .. "资源源关映射未变")
        eq(entry.firstClearBonusMonster, nil, id .. "不继承单值bonus")
        eq(entry.firstClearBonusMonsters, nil, id .. "不继承bonus列表")
        for t = 1, 3 do
            f.reset()
            drivers[t]:start(204) -- 同一实例先有1004，换资源必须清旧bonus。
            f.Story.resetAll()
            f.records.generated, f.records.marked = {}, {}
            drivers[t]:start(resourceId)
            eq(drivers[t].stageTotal, entry.idleCount, id .. "队" .. t .. "真实常驻数不加主线bonus")
            eq(f.records.generated[1].first, false, id .. "资源不走首通出怪")
            eq(#f.records.marked, 0, id .. "资源不调用markPhase")
            eq(f.Story.take(), nil, id .. "资源不通知主线剧情")
            for _, unit in ipairs(wave(drivers[t])) do
                check(not unit._isBonusMonster and unit.monsterId ~= original.firstClearBonusMonster
                    and unit.monsterId ~= 1004, id .. "换关后无旧/源剧情附加怪")
                eq(unit.goldReward, 0, id .. "怪物金币归资源规则不叠加")
                eq(unit.expReward, 0, id .. "怪物经验归资源规则不叠加")
            end
        end
    end
    -- 不测轮回推进/共享HP归属（另一个专项负责），仅守住start显式生成三boss分支。
    for _, stageId in ipairs({ 999, 1999, 2999 }) do
        for t = 1, 3 do
            for _, cleared in ipairs({ false, true }) do
                f.reset(cleared and { [stageId] = true } or {}, cleared and { [tostring(stageId)] = true } or {})
                drivers[t]:start(stageId)
                local entry = f.SC.getStage(stageId)
                eq(#f.records.generated, 0, "终焉" .. stageId .. "不走普通生成器")
                eq(#f.records.marked, 0, "终焉不标剧情怪")
                eq(drivers[t].stageTotal, #entry.monsters, "终焉队" .. t .. "三个显式boss不退idleCount=0")
                eq(#drivers[t].enemyQueue, 0, "终焉显式boss全在场")
                for index, unit in ipairs(drivers[t].enemies) do
                    eq(unit.monsterId, entry.monsters[index], "终焉显式boss顺序")
                    eq(unit.isBoss, true, "终焉正式路径保留boss标记")
                    check(not unit._isBonusMonster, "终焉boss未误标为剧情附加怪")
                end
            end
        end
    end
    eq(next(f.records.affixes), nil, "正式资源/终焉start仍不加载全局lab词缀")
end

local function labCases(f)
    for _, first in ipairs({ true, false }) do
        f.reset({ [2505] = true }, { ["2505"] = true })
        f.records.affixes = {}
        local liveBefore, savedBefore, panelBefore = f.records.liveReads, f.records.savedReads, f.records.panelCalls
        local allies = { assert(f.require("config.HeroConfig").createHero(1, 3, nil, nil, false)) }
        local lab = f.Driver.new(926, { battleLab = true, firstClear = first, timeLimit = 23,
            allyFactory = function() f.records.factoryCalls = f.records.factoryCalls + 1; return allies end })
        local callbacks = 0
        lab.onStageChanged = function() callbacks = callbacks + 1 end
        lab:start(2505)
        eq(lab.allies, allies, "lab保留显式注入allyFactory原表")
        eq(lab.firstClear, first, "lab仍由options.firstClear决定")
        eq(lab.stageTotal, first and 31 or 10, "lab已通账本不覆盖注入首通/挂机配置")
        eq(f.records.generated[1].first, first, "lab透传原firstClear")
        eq(countId(wave(lab), 1005), first and 1 or 0, "lab注入剧情怪行为不变")
        eq(f.records.liveReads, liveBefore, "lab不读取玩家live账本")
        eq(f.records.savedReads, savedBefore, "lab不读取玩家saved账本")
        eq(f.records.panelCalls, panelBefore, "lab不读玩家编队")
        eq(callbacks, 0, "lab不通知玩家关卡改变")
        eq(f.Story.take(), nil, "lab不触发玩家剧情")
        eq(lab.dropLuck, 0, "lab固定幸运值不读玩家奖励状态")
        eq(lab._labTimeLimit, 23, "lab注入超时仍保留")
        eq(f.records.affixes.mapLoad, 1, "lab保留MAS加载")
        if first then
            eq(f.records.affixes.bossLoad, 1, "lab首通保留BAS加载")
            eq(f.records.affixes.bossApply, 1, "lab首通保留Boss词缀作用到完整波")
            eq(f.records.affixes.berserkEnter, 1, "lab首通保留狂暴入口")
            eq(countId(lab.enemies, 1005), 1, "lab原首通附加怪仍开场")
        else
            eq(f.records.affixes.bossClear, 1, "lab挂机仍清BAS")
            eq(f.records.affixes.berserkExit, 1, "lab挂机仍退出狂暴")
        end
    end
    eq(f.records.factoryCalls, 2, "两个lab分别消费注入factory一次")
    eq(f.records.gpuCalls, 0, "全程无GPU/声音资源调用")
    eq(f.records.fileCalls, 0, "全程无玩家文件/存档调用")
    eq(f.records.actions, 0, "全程无玩家动作")
end

local function performanceCases()
    local function equal(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
        for key in pairs(b) do if a[key] == nil then return false end end
        return true
    end
    local function exercise(enabled)
        local f = fixture({ performance = true })
        f.reset()
        local monitor = f.require("core.PerformanceMonitor")
        local clock = f.records.clock
        local events, totals, returned, drops, errors = {}, {}, {}, {}, {}
        local wraps, originalWrap = 0, monitor.wrap
        monitor.wrap = function(name, fn) wraps = wraps + 1; return originalWrap(name, fn) end
        -- 创建时回调仍是nil、监测关闭；之后再开启也必须计到这份实例。
        local drv = f.Driver.new(2)
        eq(wraps, 10, "每实例只在构造时包装十个同步入口")
        local methods = {}
        for _, name in ipairs({ "update", "tick", "start", "flushExtraTalents", "queuePendingKills",
            "invokeOnKill", "notifyStageCleared", "tickRewards", "advanceStage", "retreatStage" }) do
            methods[name] = drv[name]
        end
        local function event(name)
            events[#events + 1] = name
            totals[name] = (totals[name] or 0) + 1
            clock.wall, clock.cpu = clock.wall + 1, clock.cpu + .0005
        end
        local function values(label, ...)
            local pack = table.pack(...)
            returned[#returned + 1] = { label = label, count = pack.n }
            return pack
        end
        local function noResult(label, ...)
            eq(values(label, ...).n, 0, label .. "仍返回零个值而非一个nil")
        end
        local token = {}
        local ets = f.require("systems.ExtraTalentSystem")
        ets.flush = function() event("flush"); return nil, false, token, nil end
        local talent = f.require("systems.TalentManager")
        local reset = talent.reset
        talent.reset = function(...) event("reset"); return reset(...) end
        local spawn = f.Spawn.generateEnemyList
        f.Spawn.generateEnemyList = function(...) event("spawn"); return spawn(...) end
        local firstKill, secondKill, clears = 0, 0, 0
        drv.onKill = function(data)
            event("kill1"); firstKill = firstKill + 1
            eq(#drv.pendingKills, 0, "onKill前已消费pending，重入不会重复发奖")
            check(#drv.rewardQueue > 0, "onKill前逐杀掉落已经排队")
            eq(data.teamIdx, 2, "后绑定onKill保持点调用payload而非self")
            eq(data.expReward, 8, "聚合经验不变")
            eq(data.goldReward, 10, "聚合金币不变")
            eq(data.allyCount, 2, "活人归属数量不变")
            eq(table.concat(data.heroIds, ","), "1,3", "活人归属顺序不变")
            -- 同步重入仍不能重复消费；计时是inclusive而非改变奖励事务。
            noResult("重入空queue", drv:queuePendingKills())
            return nil, false, token, nil
        end
        drv.onStageCleared = function(team, stage)
            event("clear1"); clears = clears + 1
            eq(team, 2, "后绑定通关回调队号不变")
            eq(stage, drv.stageId, "后绑定通关回调当前关不变")
            check(firstKill > 0, "通关回调仍晚于onKill")
            return nil, false, token, nil
        end
        drv.onDrop = function(data)
            event("drop"); drops[#drops + 1] = copy(data)
            return nil, false, token, nil
        end
        if enabled then monitor.start(); monitor.beginFrame("战斗同步专项") end
        local tuple = values("flush转发", drv:flushExtraTalents())
        eq(tuple.n, 4, "flush转发保留尾nil返回数")
        check(tuple[1] == nil and tuple[2] == false and tuple[3] == token and tuple[4] == nil,
            "flush转发不吞nil/false/对象引用")
        noResult("start", drv:start(101))
        drv.allies = { { hp = 10, heroId = 1 }, { hp = 0, heroId = 2, _triDeathHandled = true },
            { hp = 20, heroId = 3 } }
        drv.enemies, drv.enemyQueue, drv.introTimer = {}, {}, 0
        drv:reportKill({ expReward = 3, goldReward = 4 })
        drv:reportKill({ expReward = 5, goldReward = 6 })
        noResult("清波tick", drv:tick(.01))
        noResult("行军tick", drv:tick(.1)) -- 先消费两条drop，clear不能重复。
        eq(firstKill, 1, "首次onKill恰一次")
        eq(clears, 1, "行军多帧通关回调恰一次")
        eq(#drops, 2, "tickRewards逐条顺序消费两杀掉落")
        eq(drops[1].stageId, 101, "延迟掉落保留旧关卡")
        eq(table.concat(drops[2].heroIds, ","), "1,3", "延迟掉落保留活人归属")
        noResult("行军结束tick", drv:tick(2)) -- 真advanceStage→start，不替换构建。
        eq(drv.stageId, 102, "真advanceStage仍前进102")
        drv.onKill = function(data)
            event("kill2"); secondKill = secondKill + 1
            eq(data.stageId, 102, "替换后onKill收到当前关")
            return nil, false, token, nil
        end
        drv.onStageCleared = function(team, stage)
            event("clear2"); eq(team, 2, "替换后通关队号")
            eq(stage, 102, "替换后通关关卡")
            return nil, false, token, nil
        end
        tuple = values("当前onKill转发", drv:invokeOnKill({ stageId = 102 }))
        eq(tuple.n, 4, "当前onKill转发保留多返回尾nil")
        check(tuple[2] == false and tuple[3] == token, "当前onKill转发保持对象引用")
        tuple = values("当前通关转发", drv:notifyStageCleared())
        eq(tuple.n, 4, "当前通关转发保留多返回尾nil")
        check(tuple[2] == false and tuple[3] == token, "当前通关转发保持对象引用")
        drv:reportKill({ expReward = 1, goldReward = 2 })
        noResult("retreatStage", drv:retreatStage())
        eq(drv.stageId, 101, "真retreatStage仍退101")
        eq(secondKill, 2, "退关start消费pending时调用新onKill而非初始化捕获")
        eq(f.records.saveRequests, 1, "退关只请求一次保存，文件仍封闭")
        -- nil回调保持原guard；不会调用转发器、不会改变奖励队列消费。
        drv.onKill, drv.onStageCleared = nil, nil
        drv:reportKill({ expReward = 1, goldReward = 2 })
        noResult("无回调queue", drv:queuePendingKills())
        drv.enemies, drv.enemyQueue, drv.introTimer = {}, {}, 0
        noResult("无回调清波", drv:tick(.01))

        -- 每个新分段的错误必须原对象抛出，不能吞错、改为返回值或继续后续事件。
        local function expectError(label, fn)
            local failure = table.pack(pcall(fn))
            eq(failure.n, 2, label .. "错误返回数")
            eq(failure[1], false, label .. "仍抛出")
            eq(failure[2], token, label .. "保持原错误对象")
            errors[#errors + 1] = label
        end
        ets.flush = function() event("flush-error"); error(token, 0) end
        expectError("flush", function() drv:flushExtraTalents() end)
        expectError("start", function() drv:start(102) end)
        expectError("advance", function() drv:advanceStage() end)
        expectError("retreat", function() drv:retreatStage() end)
        drv.pendingKills = { { stageId = 101, expReward = 1, goldReward = 2 } }
        drv.onKill = function() event("kill-error"); error(token, 0) end
        expectError("queue/onKill", function() drv:queuePendingKills() end)
        eq(#drv.pendingKills, 0, "onKill抛错仍先消费pending，不重复发奖")
        drv.onDrop = function() event("drop-error"); error(token, 0) end
        local beforeDrops = #drv.rewardQueue
        expectError("tickRewards", function() drv:tickRewards(1) end)
        eq(#drv.rewardQueue, beforeDrops - 1, "onDrop抛错仍先出队一条，不改消费顺序")
        ets.flush = function() event("flush") end
        drv.onStageCleared = function() event("clear-error"); error(token, 0) end
        drv.rewardQueue, drv.enemies, drv.enemyQueue, drv.introTimer = {}, {}, {}, 0
        drv._clearReported, drv.marchTimer = false, 0
        expectError("tick/onStageCleared", function() drv:tick(.01) end)
        eq(drv._clearReported, true, "通关抛错仍先记_clearReported")
        eq(drv.marchTimer, 0, "通关抛错不提前执行beginMarch")
        -- 不只比较开/关一致：同时固定旧语义的调用数与顺序，防止两边一起漏调。
        eq(totals.flush, 11, "八次Driver直接flush加三次真实TAL.reset内部flush")
        eq(totals["flush-error"], 4, "四个flush错误出口没有重试或吞错")
        eq(totals.reset, 3, "只有三次成功start重置天赋")
        eq(totals.spawn, 3, "只有三次成功start构建敌人")
        eq(totals.drop, 2, "只有达到真实奖励间隔的两条drop被消费")
        local eventOrder = table.concat(events, ",")
        check(eventOrder:find("flush,kill1,clear1,drop,drop", 1, true) ~= nil,
            "真实tick同步flush→聚合onKill→通关→后帧drop顺序")
        eq(wraps, 10, "多次tick/start/推进/退关不再次创建包装闭包")
        for name, method in pairs(methods) do eq(drv[name], method, "实例方法身份稳定 " .. name) end
        if enabled then clock.wall = clock.wall + 16; monitor.beginFrame("战斗同步专项") end
        local snapshot = monitor.snapshot()
        if enabled then
            -- TAL.reset自身还会flush三次，但不是Driver直接helper的调用，不能混计。
            local expected = { ["队伍2.ETS.flush"] = 12,
                ["队伍2.onKill"] = firstKill + secondKill + totals["kill-error"],
                ["队伍2.onStageCleared"] = totals.clear1 + totals.clear2 + totals["clear-error"],
                ["队伍2.start"] = 5, ["队伍2.advanceStage"] = 2, ["队伍2.retreatStage"] = 2,
                ["队伍2.tickRewards"] = 6, ["队伍2.queuePendingKills"] = 7, ["队伍2.tick"] = 5 }
            for name, count in pairs(expected) do
                local actual = 0
                for _, row in ipairs(snapshot.sections) do if row.name == name then actual = row.calls end end
                eq(actual, count, "真实Monitor开启分段调用数 " .. name)
            end
        else
            eq(clock.wallReads, 0, "关闭所有Driver分段零墙钟读取")
            eq(clock.cpuReads, 0, "关闭所有Driver分段零CPU时钟读取")
            eq(#snapshot.sections, 0, "关闭不记录分段")
        end
        eq(f.records.gpuCalls + f.records.fileCalls + f.records.actions, 0, "诊断对照无GPU/玩家文件/动作")
        return { events = eventOrder, totals = totals, returns = returned, drops = drops,
            errors = errors, rngCalls = clock.rngCalls, rngState = clock.rngState,
            f = f, drv = drv, monitor = monitor }
    end
    local off, on = exercise(false), exercise(true)
    eq(off.events, on.events, "开启/关闭全部事件顺序完全一致")
    check(equal(off.returns, on.returns), "开启/关闭全部返回值个数一致")
    check(equal(off.drops, on.drops), "开启/关闭延迟奖励完整payload与顺序一致")
    eq(table.concat(off.errors, ","), table.concat(on.errors, ","), "开启/关闭错误路径顺序一致")
    eq(off.rngCalls, on.rngCalls, "开启/关闭真实start出怪RNG消费计数一致")
    eq(off.rngState, on.rngState, "开启/关闭真实start出怪RNG终态一致")
    for name, count in pairs(off.totals) do eq(on.totals[name], count, "开启/关闭事件计数一致 " .. name) end

    -- 真实协程跨yield不计内层，同步宿主另有resume分段；不伪造isyieldable。
    local clock, monitor, drv = on.f.records.clock, on.monitor, on.drv
    local reads = clock.wallReads + clock.cpuReads
    local calls = 0
    drv.onStageCleared = function(team, stage)
        calls = calls + 1
        coroutine.yield("paused", nil, team)
        return nil, false, stage, nil
    end
    local co = coroutine.create(function() return drv:notifyStageCleared() end)
    local first = table.pack(coroutine.resume(co))
    eq(first.n, 4, "协程yield返回数不变")
    check(first[1] and first[2] == "paused" and first[3] == nil and first[4] == 2, "协程yield内容不变")
    clock.wall, clock.cpu = clock.wall + 5000, clock.cpu + 2
    local last = table.pack(coroutine.resume(co))
    eq(last.n, 5, "协程完成多返回尾nil不变")
    check(last[1] and last[2] == nil and last[3] == false and last[4] == drv.stageId and last[5] == nil,
        "协程完成值与nil位置不变")
    eq(calls, 1, "跨yield回调只执行一次")
    eq(clock.wallReads + clock.cpuReads, reads, "跨yield转发不读时钟、不把等待归入同步重活")
    monitor.stop()
end

function Start()
    local ok, err = xpcall(function()
        local f = fixture()
        local drivers = productionCases(f)
        resourceAndTerminalCases(f, drivers)
        labCases(f)
        performanceCases()
    end, debug.traceback)
    if ok then print(TAG .. "RESULT ALL PASS checks=" .. checks)
    else
        print(TAG .. "RESULT FAIL checks=" .. checks .. " error=" .. tostring(err))
        log:Write(LOG_ERROR, TAG .. tostring(err))
    end
    engine:Exit()
end
