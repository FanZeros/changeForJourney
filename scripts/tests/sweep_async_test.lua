-- 分帧扫荡真实规则专项；不启动main/Boot，不读写玩家档，不构建。
-- 新版批量计数保持分布，但不保留旧逐杀同seed装备/RNG序列；新版同seed逐件完整复现另行断言。
-- 外部冻结源码loader可传SWEEP_ASYNC_OPTIONS.oracleSource(relativeLuaPath)，固定旧树a590320d。
-- 旧树仅作固定收益/成长口径及未改resource context骰序oracle；缺旧树明确NOT RUN，不冒称历史逐件一致。
local F = require("tests.SweepRegressionFixture")
local TAG = "[sweep_async_test] "
local options = rawget(_G, "SWEEP_ASYNC_OPTIONS") or {}
local assertions, cases, passed = 0, 0, 0
local failures = {} ---@type string[]
local phases = { prepare = true, generate = true, classify = true }

local function check(value, message)
    assertions = assertions + 1
    assert(value, message)
end
local function eq(actual, expected, message)
    check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function same(actual, expected, message)
    check(F.equal(actual, expected), message)
end
local function run(label, callback)
    cases = cases + 1
    local start = os.clock()
    local ok, err = pcall(callback)
    if ok then
        passed = passed + 1
        print(TAG .. "PASS " .. label .. string.format(" cpu=%.6f", os.clock() - start))
    else
        failures[#failures + 1] = label .. " => " .. tostring(err)
        print(TAG .. "FAIL " .. failures[#failures])
    end
end

local function capture(value, records, seen)
    if type(value) ~= "table" or seen[value] then return end
    seen[value] = true
    local fields = {}
    records[#records + 1] = { target = value, fields = fields }
    for key, child in pairs(value) do
        fields[key] = child
        capture(child, records, seen)
    end
end
local function snapshot(h)
    local records = {}
    capture(h.data, records, {})
    return { data = F.copy(h.data), wallet = F.copy(h.wallet), disk = F.copy(h.disk),
        dataRef = h.data, walletRef = h.wallet, diskRef = h.disk, records = records,
        notifications = h.notifications, events = h.events, persists = h.persists,
        dirty = F.copy(h.dirty), finishes = F.copy(h.finishes) }
end
local function untouched(h, before, label)
    same(h.data, before.data, label .. " 全部live字段值")
    same(h.wallet, before.wallet, label .. " GameState全部值")
    same(h.disk, before.disk, label .. " 已保存快照全部值")
    eq(h.data, before.dataRef, label .. " live根引用")
    for _, record in ipairs(before.records) do
        for key, value in pairs(record.fields) do
            if type(value) == "table" then
                eq(record.target[key], value, label .. " 原table边 " .. tostring(key))
            end
        end
    end
    eq(h.notifications, before.notifications, label .. " 通知数")
    eq(h.events, before.events, label .. " 余额事件数")
    eq(h.persists, before.persists, label .. " 保存数")
    same(h.dirty, before.dirty, label .. " dirty集合")
    same(h.finishes, before.finishes, label .. " 事务finish集合")
end

-- 在独立env加载同一个SweepRegressionFixture；仅cache源码读取来自指定旧树。
-- 不改全局require/package.loaded/math，不允许旧树通过dist回退。
local function oracleFixture()
    if type(options.oracleSource) ~= "function" then return nil end
    local source = options.oracleSource
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.cache = { GetFile = function(_, relative)
        assert(type(relative) == "string" and relative:match("^[%w_/]+%.lua$")
            and not relative:find("..", 1, true), "oracle源码白名单")
        local text, cursor = source(relative), 1
        assert(type(text) == "string", "oracle源码必须显式提供 " .. relative)
        return {
            IsEof = function() return cursor > #text end,
            ReadLine = function()
                local ending = text:find("\n", cursor, true)
                local line = text:sub(cursor, ending and ending - 1 or #text)
                cursor = ending and ending + 1 or #text + 1
                return line
            end,
            Dispose = function() end,
        }
    end }
    env.File = function() error("oracle业务File禁止") end
    env.fileSystem = setmetatable({}, { __index = function() error("oracle业务FileSystem禁止") end })
    env.io = false
    env.loadfile = function() error("oracle loadfile禁止") end
    env.dofile = function() error("oracle dofile禁止") end
    return assert(load(source("tests/SweepRegressionFixture.lua"), "@a590320d/SweepRegressionFixture", "t", env))()
end

local function configure(fixture, config)
    local h = fixture.new()
    fixture.install(h, config.initial or 0)
    h.data.currency.sweepTicket = config.count or 11
    h.data.currency.essence = 123
    h.data.equipment.settings = F.copy(config.auto or {})
    h.data.lootbox.autoDecomposeNotice = { count = 2, essence = 17, seq = 3, at = 1, lastQuality = 1 }
    -- 已有装备与遗匣嵌套字段必须原样保留，不作为新掉落重抽/追溯分解。
    local old = assert(h.ES.generate("C1", 1, 1))
    old.testNested = { immutable = { "legacy", 2, 7 }, lockedBy = false }
    old.locked, old.ascendLevel, old.refineCount = true, 12, 3
    h.LS.addEquipment(h.data.lootbox, old)
    local growth = config.growth or "stable"
    h.data.heroes.roster = {}
    for id = 1, 8 do
        local level = growth == "cap" and 199 or growth == "capped" and 200
            or growth == "stable" and 100 or (id <= 4 and 1 or 2)
        h.data.heroes.roster[id] = { level = level,
            exp = growth == "cap" and h.ET.hero[199] - 1
                or growth == "capped" and 777 or growth == "resonance" and id <= 4 and 19 or 0,
            maxExp = -1, extra = { untouched = id } }
    end
    h.data.heroes.teams = { { slots = { 4, 1, 3, 2 } }, { slots = {} }, { slots = {} } }
    h.data.heroes.deployed = { 4, 1, 3, 2 }
    h.data.player = { level = growth == "cap" and 199 or growth == "capped" and 200
        or growth == "stable" and 100 or 1,
        exp = growth == "cap" and h.ET.player[199] - 1 or growth == "capped" and 999 or 19,
        maxExp = -1, untouched = { "player" } }
    h.data.battle.clearedStages[101] = true
    h.seed, h.rngCalls = config.seed or 1021, 0
    h.forceRandom = config.forceRandom
    if config.forceRandom == 0 and fixture == F then
        -- 仅故障/取消/满包等端点夹具：旧forceRandom=0意为所有p>0命中，
        -- 新几何二项采样的0不具此含义，显式替换该私有h内的计数采样器。
        -- 不替换全局或夹具文件；自然RNG复现/大样本绝不走此stub，不作概率验证。
        h.require("shared.sweep.BatchRandom").binomial = function(n, p, _, checkpoint)
            if checkpoint then checkpoint() end
            return p > 0 and n or 0
        end
    end
    h.disk, h.wallet = F.copy(h.data), F.copy(h.data.currency)
    return h
end

-- 每512/4096个checkpoint模拟一片；非末片必须真实coroutine.yield。
-- 小样本还在每个control.check完整比较；大样本每个yield与prepare完成比较全树及原引用。
local function prepare(h, config, extra)
    local before = snapshot(h)
    local stats = { checkpoints = 0, checks = 0, yields = 0, perPhase = {}, last = {}, totals = {},
        yieldPhases = {}, maxCpu = 0, resumed = 0, committed = 0 }
    local control = extra or {}
    local budget = config.budget or 512
    local cancelled = false
    local checkExtra, checkpointExtra = control.check, control.checkpoint
    control.summaryLogs = true
    control.check = function()
        stats.checks = stats.checks + 1
        if config.exhaustive then untouched(h, before, "control.check") end
        if cancelled then return false, "expected cancelled" end
        if checkExtra then return checkExtra() end
        return true
    end
    control.isCancelled = function() return cancelled end
    control.checkpoint = function(phase, done, total)
        check(phases[phase], "checkpoint只在私有准备阶段 " .. tostring(phase))
        check(type(done) == "number" and done >= 0, "checkpoint进度非负")
        check(type(total) == "number" and total >= 0, "checkpoint总数非负")
        if phase ~= "prepare" then check(done <= total, "已知生成/分类进度不超总量") end
        if stats.last[phase] ~= nil then check(done >= stats.last[phase], "同phase进度不倒退 " .. phase) end
        -- 批量采样尚未知装备数时generate 0/0；随后逐件阶段0/实际装备数，不新增phase。
        stats.last[phase], stats.totals[phase] = done, total
        stats.checkpoints = stats.checkpoints + 1
        stats.perPhase[phase] = (stats.perPhase[phase] or 0) + 1
        if checkpointExtra then checkpointExtra(phase, done, total) end
        if config.exhaustive or stats.checkpoints % budget == 0 then
            untouched(h, before, "checkpoint/yield " .. phase)
        end
        if stats.checkpoints % budget == 0 or config.cancelPhase == phase then
            stats.yields = stats.yields + 1
            stats.yieldPhases[phase] = (stats.yieldPhases[phase] or 0) + 1
            if config.count == 100000 and stats.yields % 128 == 0 then
                print(TAG .. "LARGE PROGRESS stage=" .. tostring(config.stage) .. " phase=" .. phase
                    .. " done=" .. done .. " total=" .. total .. " yields=" .. stats.yields)
            end
            coroutine.yield(phase, done, total)
        end
    end
    control.onCommitted = function(result)
        stats.committed = stats.committed + 1
        -- 生产会pcall通知；断言失败必须留在外层统计，不能被生产容错误吞成PASS。
        local ok, err = pcall(function()
            check(h.committed and h.persists == 1, "onCommitted在真实persist成功后")
            eq(h.notifications, before.notifications, "onCommitted在模块通知前")
            check(type(result) == "table", "onCommitted得到真实回执")
        end)
        if not ok then stats.callbackFailure = tostring(err) end
        if config.onCommittedThrow then error("expected onCommitted exception") end
    end
    local output = {}
    local co = coroutine.create(function()
        local candidate, reason = h.Sweep.PrepareSweep(1,
            { count = config.count or 11, teamIdx = 1, stageId = config.stage or 1905 }, control)
        output.candidate, output.reason = candidate, reason
    end)
    while coroutine.status(co) ~= "dead" do
        local start = os.clock()
        local ok, phase = coroutine.resume(co)
        stats.maxCpu = math.max(stats.maxCpu, os.clock() - start)
        stats.resumed = stats.resumed + 1
        check(ok, "准备协程必须正常返回 " .. tostring(phase))
        if coroutine.status(co) ~= "dead" then
            untouched(h, before, "外部观察suspended")
            if config.cancelPhase == phase then cancelled = true end
        end
        check(stats.resumed < 1000000, "协程有界完成，不能永久等待")
    end
    untouched(h, before, "PrepareSweep返回后")
    stats.before, stats.control = before, control
    return output.candidate, output.reason, stats
end

local function committed(h, candidate, stats)
    local start = os.clock()
    local done = table.pack(h.Sweep.CommitSweep(1, candidate, stats.control))
    stats.commitCpu = os.clock() - start
    check(done[1], "CommitSweep成功 " .. tostring(done[2]))
    eq(h.persists, 1, "只保存一次")
    eq(stats.committed, 1, "成功标记仅一次")
    eq(stats.callbackFailure, nil, "到账回调被生产pcall时序断言仍向外报告")
    eq(h.data.currency.sweepTicket, 0, "准备结束统一扣全部券")
    check(h.notifications > 0, "只在最终成功后发布模块")
    eq(#h.finishes, 1, "只结束一个事务")
    eq(h.finishes[1], true, "事务成功收尾")
    return done[3]
end

-- 新版自身复现不是历史oracle：两独立私有env同seed，分帧与同步包装必须逐件完全一致。
local function reproducible(h, replay, result, expected)
    same(result, expected, "新版同seed完整回执/全部装备字段/顺序严格复现（非旧逐杀一致）")
    eq(#result.equips, #expected.equips, "新版同seed完整装备件数")
    for index, equip in ipairs(result.equips) do
        same(equip, expected.equips[index], "新版同seed逐件完整复现 " .. index)
    end
    same(h.data, replay.data, "新版同seed全部模块值严格复现")
    same(h.wallet, replay.wallet, "新版同seed GameState严格复现")
    same(h.disk, replay.disk, "新版同seed保存候选严格复现")
    same(h.dirty, replay.dirty, "新版同seed通知集合与次数复现")
    eq(h.notifications, replay.notifications, "新版同seed总通知数")
    eq(h.events, replay.events, "新版同seed余额事件")
    eq(h.rngCalls, replay.rngCalls, "新版同seed RNG消费数量复现")
    eq(h.seed, replay.seed, "新版同seed RNG最终状态复现")
    eq(h.persists, replay.persists, "新版同seed保存次数")
    same(h.finishes, replay.finishes, "新版同seed事务收尾复现")
end

local function replayCurrent(h, result, config)
    check(config.forceRandom == nil, "正式新版复现只用自然RNG，不stub采样")
    local replay = configure(F, config)
    local ok, err, expected = replay.Sweep.Sweep(1, config.count, 1, config.stage)
    check(ok, "新版同步包装同seed复现成功 " .. tostring(err))
    reproducible(h, replay, result, expected)
end

local function conserved(h, result, config, stats)
    local initial = config.initial or 0
    local available = math.max(0, h.ES.MAX_INVENTORY - initial)
    eq(result.inventoryCount, math.min(#result.equips, available), "500件实际空位精确交付")
    eq(result.lootboxCount, #result.equips - result.inventoryCount, "保留装备完整守恒")
    eq(result.equipCount, #result.equips + (result.autoDecomposeCount or 0), "生成装备=保留件+自动分解件，无截断")
    eq(h.ES.getInventoryCount(h.data.equipment), initial + result.inventoryCount, "实际库存新增件数守恒")
    eq(h.LS.getTotalCount(h.data.lootbox), 1 + result.lootboxCount, "实际遗匣旧件加新增件守恒")
    same(h.data.lootbox.seeds[1], stats.before.data.lootbox.seeds[1], "已有完整装备及嵌套字段不重抽/不追溯分解")
    local entry = assert(h.SC.getStage(config.stage))
    eq(result.count, config.count, "不截扫荡场数")
    eq(result.kills, entry.idleCount * config.count, "不截扫荡总杀数")
    eq(stats.last.generate, result.equipCount, "生成末进度为实际装备数，不是逐杀数")
    eq(stats.totals.generate, result.equipCount, "生成最终total为实际装备数（采样期间允许0/0未知）")
    eq(stats.last.classify, result.equipCount, "全部生成装备均完成分类")
    eq(result.ticketDrop, 0, "扫荡不额外产券")
    if initial == 500 then eq(result.inventoryCount, 0, "真满包不再装入新装备") end
    if (config.auto or {}).autoQuality == 6 and (config.auto or {}).autoLevel == 0 then
        eq(#result.equips, 0, "全品质自动分解不保留新掉落")
        eq(result.autoDecomposeCount or 0, result.equipCount, "全品质分解覆盖全部生成件")
    end
end

-- 只比旧固定收益及成长，不要求随机装备/卷轴/通知分支或RNG序列等同旧版。
local function fixedParity(h, old, result, expected, config)
    for _, key in ipairs({ "count", "kills", "stageId", "teamIdx", "ticketLeft", "ticketDrop",
        "dropLuck", "playerExp", "heroExp", "heroExpTotal" }) do
        eq(result[key], expected[key], "固定a590320d非随机口径 " .. key)
    end
    same(result.playerProgress, expected.playerProgress, "固定旧树玩家成长回执")
    same(result.heroProgress, expected.heroProgress, "固定旧树逐英雄/共鸣成长回执")
    for _, name in ipairs({ "heroes", "player", "battle", "dungeon", "artifacts", "talents", "session" }) do
        same(h.data[name], old.data[name], "固定旧树非掉落模块 " .. name)
        same(h.disk[name], old.disk[name], "固定旧树保存成长/固定模块 " .. name)
    end
    eq(h.persists, old.persists, "固定旧树同样只保存一次")
    eq(h.events, old.events, "固定旧树余额事件次数")
    eq(h.data.currency.sweepTicket, old.data.currency.sweepTicket, "固定旧树统一扣券口径")
    for _, key in ipairs({ "level", "exp", "maxExp" }) do
        eq(h.wallet[key], old.wallet[key], "固定旧树GameState成长字段 " .. key)
    end
    local id = old.DC.decodeStageId(config.stage)
    if not id then
        eq(result.gold, expected.gold, "主线固定金币保持旧口径")
        eq(result.diamond, expected.diamond, "主线固定黑晶保持旧口径")
        eq(h.data.currency.gold, old.data.currency.gold, "主线实际金币到账保持旧口径")
    else
        -- 旧每杀floor(raw)+Bernoulli(frac)，新只改变这些独立尾数的采样序列。
        -- 支持区间是严格数学边界，不以旧的一次随机结果或epsilon当概率oracle。
        local raw = old.DC.getStageRewardAmount(config.stage, 1)
        eq(h.DC.getStageRewardAmount(config.stage, 1), raw, "资源每杀期望沿用旧配置")
        if id ~= "equipment_vault" then
            local key = id == "gold_mine" and "gold" or "diamond"
            local minimum, maximum = math.floor(raw) * result.kills, math.ceil(raw) * result.kills
            for _, value in ipairs({ result[key], expected[key] }) do
                check(value % 1 == 0 and value >= minimum and value <= maximum,
                    "新旧资源随机舍入落在逐杀严格支持区间 " .. key)
            end
            local estimate = h.Rewards.calculate(h.SC.getStage(config.stage), 4, config.count, false, 0, 1)
            eq(estimate[key], raw * result.kills, "资源只读期望=旧每杀raw乘完整杀数")
            eq(result[id == "gold_mine" and "diamond" or "gold"], 0, "资源不借用另一类货币")
            eq(#result.equips, 0, "金币/黑晶副本不借用主线装备掉落")
        else
            eq(result.gold, expected.gold, "装备副本固定金币保持旧口径")
            eq(result.diamond, expected.diamond, "装备副本固定黑晶保持旧口径")
        end
    end
end

local function testPurity()
    for _, stage in ipairs({ 1905, 100001, 200001, 300001 }) do
        run("每check/checkpoint私有准备纯读 " .. stage, function()
            local config = { stage = stage, count = 1, initial = 0, forceRandom = 0, exhaustive = true, budget = 16 }
            local h = configure(F, config)
            local candidate, reason, stats = prepare(h, config)
            check(candidate ~= nil, "真实候选生成 " .. tostring(reason))
            check(stats.checks > 0 and stats.checkpoints > 0, "必须调用控制check/checkpoint")
            check(stats.yields > 0, "小预算下真实yield")
            check(stats.perPhase.prepare and stats.perPhase.generate and stats.perPhase.classify,
                "生成装备的三准备阶段均观察到")
            local result = committed(h, candidate, stats)
            eq(result.count, 1, "实际执行一场")
            check(h.data.heroes.roster[4].exp > 0, "成长在最后一次提交到账")
            local saved = snapshot(h)
            eq(h.Sweep.CommitSweep(1, candidate, stats.control), false, "候选不能二次提交")
            untouched(h, saved, "重复提交无扣券发奖")
        end)
    end
end

local function testOracle(oldFixture)
    if not oldFixture then print(TAG .. "NOT RUN fixed a590320d收益/成长oracle: provide oracleSource; 新版同seed复现仍完整运行") end
    for _, stage in ipairs({ 1905, 100001, 200001, 300001 }) do
        for _, initial in ipairs({ 0, 499, 500 }) do
            for _, auto in ipairs({ {}, { autoQuality = 6, autoLevel = 0 }, { autoQuality = 2, autoLevel = 30 } }) do
                run("新版同seed逐件复现/旧固定收益口径/容量/自动分解 " .. stage .. "/" .. initial .. "/" .. tostring(auto.autoQuality or 0), function()
                    local config = { stage = stage, count = 31, initial = initial, auto = auto, seed = 1021 }
                    local h = configure(F, config)
                    local candidate, reason, stats = prepare(h, config)
                    check(candidate ~= nil, "私有候选成功 " .. tostring(reason))
                    local result = committed(h, candidate, stats)
                    replayCurrent(h, result, config)
                    conserved(h, result, config, stats)
                    if oldFixture then
                        local old = configure(oldFixture, config)
                        local ok, err, expected = old.Sweep.Sweep(1, config.count, 1, stage)
                        check(ok, "固定旧源码oracle成功 " .. tostring(err))
                        fixedParity(h, old, result, expected, config)
                    end
                end)
            end
        end
    end
    for _, growth in ipairs({ "resonance", "cap", "capped" }) do
        for _, stage in ipairs({ 101, 100001, 200001 }) do
            run("新版成长复现/旧共鸣满级口径 " .. growth .. "/" .. stage, function()
                local config = { stage = stage, count = 30, growth = growth, initial = 0, seed = 881 }
                local h = configure(F, config)
                local candidate, reason, stats = prepare(h, config)
                check(candidate ~= nil, "成长准备成功 " .. tostring(reason))
                local result = committed(h, candidate, stats)
                replayCurrent(h, result, config)
                conserved(h, result, config, stats)
                if oldFixture then
                    local old = configure(oldFixture, config)
                    local ok, err, expected = old.Sweep.Sweep(1, config.count, 1, stage)
                    check(ok, "旧成长oracle成功 " .. tostring(err))
                    fixedParity(h, old, result, expected, config)
                end
            end)
        end
    end
end

local function testResourceContexts(oldFixture)
    if not oldFixture then print(TAG .. "NOT RUN context fixed-source oracle: provide oracleSource"); return end
    for _, id in ipairs({ "gold_mine", "equipment_vault", "black_diamond" }) do
        local probe = F.new()
        local floors = { 1, probe.DC.LEGACY_MAX_FLOOR[id], probe.DC.MAX_FLOOR[id] }
        for _, floor in ipairs(floors) do
            for _, kills in ipairs({ 1, 2, 20 }) do
                for heroCount = 1, 4 do
                    run("资源请求上下文旧序/无预骰 " .. id .. "/" .. floor .. "/" .. kills .. "/" .. heroCount, function()
                        local h, old = F.new(), oldFixture.new()
                        F.install(h, 0); oldFixture.install(old, 0)
                        h.seed, old.seed, h.rngCalls, old.rngCalls = 719, 719, 0, 0
                        local stage = assert(h.DC.getStageId(id, floor))
                        local context = h.DC.createStageRewardsContext(stage, kills, heroCount)
                        eq(h.rngCalls, 0, "创建配置上下文不能预消费RNG")
                        eq(h.seed, 719, "创建配置上下文不能改变seed")
                        for _ = 1, 8 do
                            local actual = h.DC.getStageRewards(stage, kills, heroCount, context)
                            local expected = old.DC.getStageRewards(stage, kills, heroCount)
                            same(actual, expected, "全部种子/顺序/卷轴/经验字段精确相同")
                            eq(h.rngCalls, old.rngCalls, "每次调用RNG消费相同")
                            eq(h.seed, old.seed, "每次调用seed相同")
                        end
                    end)
                end
            end
        end
    end
end

local function testCancellation()
    for _, stage in ipairs({ 1905, 200001 }) do
        for _, phase in ipairs({ "prepare", "generate", "classify" }) do
            run("取消前从未扣券发奖 " .. stage .. "/" .. phase, function()
                local config = { stage = stage, count = 11, initial = 500, forceRandom = 0, cancelPhase = phase }
                local h = configure(F, config)
                local candidate, reason, stats = prepare(h, config)
                eq(candidate, nil, "取消不得返回可提交候选")
                check(type(reason) == "string", "取消有明确原因")
                check(stats.yields > 0, "真实从暂停片取消")
                eq(stats.committed, 0, "取消不宣称已到账")
            end)
        end
    end
    for _, kind in ipairs({ "false", "throw" }) do
        run("check拒绝/异常准备不落地 " .. kind, function()
            local config = { count = 11, initial = 500 }
            local h = configure(F, config)
            local candidate, reason = prepare(h, config, { check = function()
                if kind == "throw" then error("expected control failure") end
                return false, "expected refusal"
            end })
            eq(candidate, nil, "失败控制不得有候选")
            check(type(reason) == "string", "失败有原因")
            eq(h.rngCalls, 0, "初始拒绝零RNG")
        end)
    end
end

local function testGuards()
    for _, name in ipairs({ "currency", "battle", "heroes", "player", "equipment", "dungeon", "lootbox", "artifacts", "talents" }) do
        for _, kind in ipairs({ "value", "root", "nested" }) do
            run("候选失效不覆盖外部变更 " .. name .. "/" .. kind, function()
                local config = { count = 1, initial = 0, forceRandom = 0 }
                local h = configure(F, config)
                h.data[name].asyncProbe = { nested = { value = 7 } }
                local candidate, reason, stats = prepare(h, config)
                check(candidate ~= nil, "guard真实候选 " .. tostring(reason))
                if kind == "value" then h.data[name].asyncProbe.nested.value = 8
                elseif kind == "root" then h.data[name] = F.copy(h.data[name])
                else h.data[name].asyncProbe.nested = F.copy(h.data[name].asyncProbe.nested) end
                local external = snapshot(h)
                eq(h.Sweep.CommitSweep(1, candidate, stats.control), false, "变化必须拒绝旧候选")
                untouched(h, external, "拒绝不反写外部最新值/引用")
                eq(stats.committed, 0, "拒绝不宣称到账")
                eq(h.Sweep.CommitSweep(1, candidate, stats.control), false, "失败尝试候选也被消费")
            end)
        end
    end
    for _, kind in ipairs({ "uid", "control" }) do
        run("候选身份单次消费 " .. kind, function()
            local h = configure(F, { count = 1 })
            local candidate, reason, stats = prepare(h, { count = 1 })
            check(candidate ~= nil, "候选身份夹具 " .. tostring(reason))
            eq(h.Sweep.CommitSweep(kind == "uid" and 2 or 1, candidate,
                kind == "control" and {} or stats.control), false, "错身份拒绝")
            untouched(h, stats.before, "错身份零落地")
            eq(h.Sweep.CommitSweep(1, candidate, stats.control), false, "错身份尝试不留下可重放候选")
        end)
    end
end

local function testFirstCheckpointMutation()
    for _, kind in ipairs({ "tickets", "team" }) do
        run("首checkpoint外部变更不能混旧参数 " .. kind, function()
            local h = configure(F, { count = 1, initial = 0 })
            local changed, latest = false, snapshot(h)
            local control = {
                check = function() return true end,
                checkpoint = function(phase)
                    if changed or phase ~= "prepare" then return end
                    changed = true
                    if kind == "tickets" then h.data.currency.sweepTicket = 2
                    else
                        h.data.heroes.teams[1].slots = { 1, 4, 3, 2 }
                        h.data.heroes.deployed = { 1, 4, 3, 2 }
                    end
                    latest = snapshot(h)
                end,
            }
            local candidate, reason = h.Sweep.PrepareSweep(1, { count = 1, teamIdx = 1, stageId = 1905 }, control)
            check(changed, "确实从首prepare检查点改变live")
            eq(candidate, nil, "禁止旧参数/新快照混合候选")
            eq(reason, "sweep_stale", "明确过期而不是业务不合法")
            eq(h.rngCalls, 0, "参数过期在生成前拒绝零RNG")
            untouched(h, latest, "服务不撤回外部最新变更")
        end)
    end
end

local function failure(h, kind)
    if kind == "generation-nil" or kind == "generation-throw" then
        local original, calls = h.ES.generateRandom, 0
        h.ES.generateRandom = function(...)
            calls = calls + 1
            if calls == 3 then
                if kind == "generation-nil" then return nil end
                error("expected generation failure")
            end
            return original(...)
        end
    elseif kind == "delivery" then
        local original, calls = h.LS.deliverEquipment, 0
        h.LS.deliverEquipment = function(...)
            local result = original(...)
            calls = calls + 1
            if calls == 3 then error("expected third delivery failure") end
            return result
        end
    elseif kind == "onLoad" then
        h.onLoad = function(name, data)
            if name == "currency" then data.gold = -999; error("expected onLoad failure") end
        end
    else
        h.failure = kind
        h.beforePersist = function()
            h.data.equipment.inventory = {}
            h.data.heroes.roster = {}
            h.data.session.claimedScenarios = { injected = true }
            h.data.session.lastOnlineTime = 999
        end
    end
end
local function rollback(h, before, label)
    same(h.data, before.data, label .. " 全模块严格回滚")
    same(h.wallet, before.wallet, label .. " GameState回滚")
    same(h.disk, before.disk, label .. " 旧保存快照保留")
    for _, record in ipairs(before.records) do
        for key, value in pairs(record.fields) do
            if type(value) == "table" then eq(record.target[key], value, label .. " 原table边回滚") end
        end
    end
    eq(h.notifications, before.notifications, label .. " 无半成品通知")
    eq(h.events, before.events, label .. " 无半成品事件")
    same(h.dirty, before.dirty, label .. " 无dirty泄露")
end
local function testFailures(oldFixture)
    for _, stage in ipairs({ 1905, 200001 }) do
        for _, kind in ipairs({ "generation-nil", "generation-throw", "delivery", "false", "nil", "throw", "onLoad" }) do
            run("准备或提交失败原位回滚 " .. stage .. "/" .. kind, function()
                local config = { stage = stage, count = 1, initial = 499, forceRandom = 0 }
                local h = configure(F, config)
                failure(h, kind)
                local before = snapshot(h)
                local candidate, reason, stats = prepare(h, config)
                if kind:match("^generation") then
                    eq(candidate, nil, "生成失败不得返回候选")
                    eq(h.persists, 0, "生成失败不进事务落盘")
                else
                    check(candidate ~= nil, "真实准备成功后注入提交失败 " .. tostring(reason))
                    eq(h.Sweep.CommitSweep(1, candidate, stats.control), false, "提交失败回执")
                    eq(stats.committed, 0, "失败不发送到账成功标记")
                    eq(#h.finishes, 1, "失败释放事务")
                    eq(h.finishes[1], false, "失败finish(false)")
                end
                rollback(h, before, kind)
                -- 故障中的RNG消费也只要求新版自身可复现，不锁旧逐杀序列。
                local replay = configure(F, config)
                failure(replay, kind)
                local replayBefore = snapshot(replay)
                local replayCandidate, _, replayStats = prepare(replay, config)
                if kind:match("^generation") then eq(replayCandidate, nil, "新版同故障仍在生成阶段失败")
                else
                    check(replayCandidate ~= nil, "新版同故障完整准备后提交")
                    eq(replay.Sweep.CommitSweep(1, replayCandidate, replayStats.control), false, "新版同故障提交失败")
                    eq(h.Sweep.CommitSweep(1, candidate, stats.control), false, "提交失败候选也只能消费一次")
                end
                rollback(replay, replayBefore, "新版故障复现 " .. kind)
                eq(h.seed, replay.seed, "新版同故障RNG终态复现")
                eq(h.rngCalls, replay.rngCalls, "新版同故障RNG消费复现")
                if oldFixture then
                    local old = configure(oldFixture, config)
                    failure(old, kind)
                    eq(old.Sweep.Sweep(1, config.count, 1, stage), false, "固定旧树相同故障同样失败")
                    same(h.data, old.data, "新旧相同故障最终全值一致，不比较旧随机序列")
                end
            end)
        end
    end
    run("未接保存入口准备前零RNG拒绝", function()
        local config = { count = 11, initial = 0 }
        local h = configure(F, config)
        h.Transaction.SetPersistCallback(nil)
        local candidate, reason, stats = prepare(h, config)
        eq(candidate, nil, "无保存接口不能生成候选")
        check(type(reason) == "string", "无保存接口明确拒绝")
        eq(h.rngCalls, 0, "保存未接线生成前拒绝零RNG")
        eq(stats.committed, 0, "无保存不能有到账标记")
    end)
    run("通知前到账标记异常也不重发奖励", function()
        local config = { count = 11, initial = 500, onCommittedThrow = true }
        local h = configure(F, config)
        local candidate, reason, stats = prepare(h, config)
        check(candidate ~= nil, "标记异常准备成功 " .. tostring(reason))
        committed(h, candidate, stats)
        local after = snapshot(h)
        eq(h.Sweep.CommitSweep(1, candidate, stats.control), false, "已到账后不允许重发")
        untouched(h, after, "已到账后第二次无任何变化")
    end)
    run("真500满包缺遗匣拒绝/全分解允许", function()
        for _, auto in ipairs({ false, true }) do
            local config = { count = 1, initial = 500, forceRandom = 0,
                auto = auto and { autoQuality = 6, autoLevel = 0 } or {} }
            local h = configure(F, config)
            h.data.lootbox = nil
            local candidate, reason, stats = prepare(h, config)
            if auto then
                check(candidate ~= nil, "全分解无需匣 " .. tostring(reason))
                local result = committed(h, candidate, stats)
                check(result.autoDecomposeCount > 0, "真实新掉落全部分解")
                eq(h.ES.getInventoryCount(h.data.equipment), 500, "已有500件不追溯")
            else
                eq(candidate, nil, "真满包保留件无匣拒绝")
                eq(h.persists, 0, "缺安全容器不落盘")
            end
        end
    end)
end

local function testPresentation()
    run("100000项展示整理分帧/同类稳定/原引用/单次token", function()
        local h = F.new()
        local preparation = h.require("ui.widget.RewardPreparation")
        local rewards, expected = {}, {}
        local kinds = { "gold", "hero", "equip", "artifact" }
        for index = 1, 100000 do
            local item = { type = kinds[(index - 1) % 4 + 1], quality = (index % 6) + 1,
                level = (index % 11) + 1, ordinal = index, equip = { original = index, extra = { index } } }
            rewards[index], expected[index] = item, item
        end
        local original = F.copy(rewards)
        local function group(item)
            return item.type == "hero" and 2 or item.type == "equip" and 3 or item.type == "artifact" and 4 or 1
        end
        table.sort(expected, function(a, b)
            local ga, gb = group(a), group(b)
            if ga ~= gb then return ga < gb end
            if ga > 1 and a.quality ~= b.quality then return a.quality > b.quality end
            if ga == 3 and a.level ~= b.level then return a.level > b.level end
            return a.ordinal < b.ordinal
        end)
        local token = {}
        local yields, checkpoints, resumes = 0, 0, 0
        local co = coroutine.create(function()
            token = preparation.prepare(rewards, function(phase, done, total)
                eq(phase, "presentation", "展示阶段checkpoint身份")
                check(done >= 0 and done <= total and total == #rewards, "展示进度范围")
                checkpoints = checkpoints + 1
                yields = yields + 1
                coroutine.yield()
            end)
        end)
        while coroutine.status(co) ~= "dead" do
            local ok, reason = coroutine.resume(co)
            check(ok, "展示协程完成 " .. tostring(reason))
            resumes = resumes + 1
            check(resumes < 100000, "展示有界完成")
        end
        check(yields > 1, "大展示不能同步table.sort一次堵塞")
        eq(resumes, yields + 1, "展示每非末片有真实yield")
        same(rewards, original, "输入原始完整值不修改")
        local items = preparation.take(token, rewards)
        check(type(items) == "table", "真实准备token可消费")
        eq(#items, #rewards, "整理不截断奖励项")
        for index, item in ipairs(expected) do
            eq(items[index], item, "按原规则排序且同类稳定，复用原item " .. index)
            eq(items[index].equip, rewards[item.ordinal].equip, "深层equip不复制 " .. index)
        end
        eq(preparation.take(token, rewards), nil, "展示token只能消费一次")
        print(TAG .. "PRESENTATION items=" .. #items .. " checkpoints=" .. checkpoints .. " yields=" .. yields)
    end)
end

local function testLarge(oldFixture)
    for _, stage in ipairs({ 1905, 100001, 200001, 300001 }) do
        run("100000券自然RNG完整场数/杀数/实际装备进度 " .. stage, function()
            local config = { stage = stage, count = 100000, initial = 500, seed = 1021, budget = 4096 }
            local h = configure(F, config)
            print(TAG .. "LARGE BEGIN stage=" .. stage .. " count=" .. config.count)
            local start = os.clock()
            local candidate, reason, stats = prepare(h, config)
            stats.prepareCpu = os.clock() - start
            print(TAG .. "LARGE PREPARED stage=" .. stage .. " cpu=" .. stats.prepareCpu .. " yields=" .. stats.yields)
            check(candidate ~= nil, "100k真实候选完成 " .. tostring(reason))
            check((stats.yieldPhases.prepare or 0) > 0, "大库存私有prepare必须真实yield且保持全树/引用一致")
            -- 金币/黑晶批量常量计数没有逐kill帧，100k本身不要求多yield。
            -- 主线/装备副本仍须按实际完整装备生成与分类分片，不能同步跳过全部生成。
            if stage == 1905 or stage == 200001 then
                check(stats.yields > 1 and (stats.yieldPhases.generate or 0) > 0, "千件自然装备真实分帧生成")
            end
            eq(stats.resumed, stats.yields + 1, "每非末片真实yield后才能继续")
            local entry = assert(h.SC.getStage(stage))
            local result = committed(h, candidate, stats)
            eq(result.kills, entry.idleCount * config.count, "100k无截断总杀数")
            eq(result.count, config.count, "100k无截断场数")
            conserved(h, result, config, stats)
            replayCurrent(h, result, config)
            if oldFixture then
                local old = configure(oldFixture, config)
                local ok, err, expected = old.Sweep.Sweep(1, config.count, 1, stage)
                check(ok, "旧100k完整执行，仅比较固定收益/成长口径 " .. tostring(err))
                fixedParity(h, old, result, expected, config)
            else print(TAG .. "NOT RUN 100k fixed-source收益/成长oracle " .. stage .. "; 新版复现非旧逐件一致") end
            if stage == 1905 or stage == 200001 then
                check(result.equipCount > 1000, "自然RNG真实千件以上装备，不用强制零掉落")
                eq(result.lootboxCount, #result.equips, "真满包全部保留装备进遗匣")
            else
                eq(result.equipCount, 0, "金币/黑晶常量计数无需生成装备")
            end
            print(TAG .. string.format("LARGE stage=%d kills=%d checkpoints=%d yields=%d resumes=%d prepareCpu=%.6f maxSliceCpu=%.6f commitCpu=%.6f rng=%d equips=%d",
                stage, result.kills, stats.checkpoints, stats.yields, stats.resumed, stats.prepareCpu,
                stats.maxCpu, stats.commitCpu, h.rngCalls, result.equipCount))
        end)
    end
end

function Start()
    assertions, cases, passed, failures = 0, 0, 0, {}
    local requireBefore, randomBefore = require, math.random
    local loadedBefore = {}; for key, value in pairs(package.loaded) do loadedBefore[key] = value end
    local oldFixture = oracleFixture()
    local mode = options.mode or "quick"
    if mode ~= "large" then
        testPurity()
        testOracle(oldFixture)
        testResourceContexts(oldFixture)
        testCancellation()
        testGuards()
        testFirstCheckpointMutation()
        testFailures(oldFixture)
        testPresentation()
    end
    if mode == "large" or mode == "all" then testLarge(oldFixture) end
    run("隔离全局require/math/package", function()
        eq(require, requireBefore, "全局require不变")
        eq(math.random, randomBefore, "全局RNG函数不变")
        for key, value in pairs(loadedBefore) do eq(package.loaded[key], value, "全局package旧模块不变 " .. key) end
        for key in pairs(package.loaded) do check(loadedBefore[key] ~= nil, "全局package无新增 " .. key) end
    end)
    print(TAG .. "SUMMARY cases=" .. cases .. " passed=" .. passed .. " failed=" .. #failures .. " assertions=" .. assertions)
    engine:Exit()
    if #failures > 0 then error(TAG .. table.concat(failures, "\n")) end
    print(TAG .. "ALL PASS")
end
