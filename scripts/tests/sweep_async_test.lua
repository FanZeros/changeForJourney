-- 分帧扫荡真实规则专项；不启动main/Boot，不读写玩家档，不构建。
-- 外部冻结源码loader可传SWEEP_ASYNC_OPTIONS.oracleSource(relativeLuaPath)，固定旧树a590320d。
-- 未提供旧树明确NOT RUN；本文件不把当前实现当作历史oracle。
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
    h.disk, h.wallet = F.copy(h.data), F.copy(h.data.currency)
    return h
end

-- 每512/4096个checkpoint模拟一片；非末片必须真实coroutine.yield。
-- 小样本还在每个control.check完整比较；大样本每个yield与prepare完成比较全树及原引用。
local function prepare(h, config, extra)
    local before = snapshot(h)
    local stats = { checkpoints = 0, checks = 0, yields = 0, perPhase = {}, last = {},
        maxCpu = 0, resumed = 0, committed = 0 }
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
        if stats.last[phase] ~= nil then check(done >= stats.last[phase], "同phase进度不倒退 " .. phase) end
        stats.last[phase] = done
        stats.checkpoints = stats.checkpoints + 1
        stats.perPhase[phase] = (stats.perPhase[phase] or 0) + 1
        if checkpointExtra then checkpointExtra(phase, done, total) end
        if config.exhaustive or stats.checkpoints % budget == 0 then
            untouched(h, before, "checkpoint/yield " .. phase)
        end
        if stats.checkpoints % budget == 0 or config.cancelPhase == phase then
            stats.yields = stats.yields + 1
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

local function parity(h, old, result, expected)
    same(result, expected, "固定a590320d完整回执/装备字段/顺序严格一致")
    same(h.data, old.data, "固定旧树全部模块值严格一致")
    same(h.wallet, old.wallet, "固定旧树GameState严格一致")
    same(h.disk, old.disk, "固定旧树保存候选严格一致")
    same(h.dirty, old.dirty, "固定旧树通知集合与次数一致")
    eq(h.notifications, old.notifications, "固定旧树总通知数")
    eq(h.events, old.events, "固定旧树余额事件")
    eq(h.rngCalls, old.rngCalls, "固定旧树RNG消费数量")
    eq(h.seed, old.seed, "固定旧树RNG最终状态")
    eq(h.persists, old.persists, "固定旧树保存次数")
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
    if not oldFixture then print(TAG .. "NOT RUN fixed a590320d oracle: provide oracleSource"); return end
    for _, stage in ipairs({ 1905, 100001, 200001, 300001 }) do
        for _, initial in ipairs({ 0, 499, 500 }) do
            for _, auto in ipairs({ {}, { autoQuality = 6, autoLevel = 0 }, { autoQuality = 2, autoLevel = 30 } }) do
                run("固定旧源码同seed/完整顺序/容量/自动分解 " .. stage .. "/" .. initial .. "/" .. tostring(auto.autoQuality or 0), function()
                    local config = { stage = stage, count = 31, initial = initial, auto = auto, seed = 1021 }
                    local h, old = configure(F, config), configure(oldFixture, config)
                    local candidate, reason, stats = prepare(h, config)
                    check(candidate ~= nil, "私有候选成功 " .. tostring(reason))
                    local ok, err, expected = old.Sweep.Sweep(1, config.count, 1, stage)
                    check(ok, "固定旧源码oracle成功 " .. tostring(err))
                    local result = committed(h, candidate, stats)
                    parity(h, old, result, expected)
                    local available = math.max(0, h.ES.MAX_INVENTORY - initial)
                    eq(result.inventoryCount, math.min(#result.equips, available), "500件实际空位精确交付")
                    eq(result.lootboxCount, #result.equips - result.inventoryCount, "保留装备完整守恒")
                    if initial == 500 then eq(result.inventoryCount, 0, "真满包不再装入新装备") end
                end)
            end
        end
    end
    for _, growth in ipairs({ "resonance", "cap", "capped" }) do
        for _, stage in ipairs({ 101, 100001, 200001 }) do
            run("固定旧源码成长/共鸣/满级边界 " .. growth .. "/" .. stage, function()
                local config = { stage = stage, count = 30, growth = growth, initial = 0, seed = 881 }
                local h, old = configure(F, config), configure(oldFixture, config)
                local candidate, reason, stats = prepare(h, config)
                check(candidate ~= nil, "成长准备成功 " .. tostring(reason))
                local ok, err, expected = old.Sweep.Sweep(1, config.count, 1, stage)
                check(ok, "旧成长oracle成功 " .. tostring(err))
                parity(h, old, committed(h, candidate, stats), expected)
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
                if oldFixture then
                    local old = configure(oldFixture, config)
                    failure(old, kind)
                    eq(old.Sweep.Sweep(1, config.count, 1, stage), false, "固定旧树相同故障同样失败")
                    same(h.data, old.data, "新旧相同故障最终全值一致")
                    eq(h.seed, old.seed, "故障RNG终态保持")
                    eq(h.rngCalls, old.rngCalls, "故障RNG次数保持")
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
        run("100000券自然RNG完整完成/逐片yield " .. stage, function()
            local config = { stage = stage, count = 100000, initial = 500, seed = 1021, budget = 4096 }
            local h = configure(F, config)
            print(TAG .. "LARGE BEGIN stage=" .. stage .. " count=" .. config.count)
            local start = os.clock()
            local candidate, reason, stats = prepare(h, config)
            stats.prepareCpu = os.clock() - start
            print(TAG .. "LARGE PREPARED stage=" .. stage .. " cpu=" .. stats.prepareCpu .. " yields=" .. stats.yields)
            check(candidate ~= nil, "100k真实候选完成 " .. tostring(reason))
            check(stats.yields > 1, "100k必须分多片真实yield")
            eq(stats.resumed, stats.yields + 1, "每非末片真实yield后才能继续")
            local entry = assert(h.SC.getStage(stage))
            eq(stats.last.generate, entry.idleCount * config.count, "生成阶段逐杀完整到总量")
            local result = committed(h, candidate, stats)
            eq(result.kills, entry.idleCount * config.count, "100k无截断总杀数")
            eq(result.count, config.count, "100k无截断场数")
            if oldFixture then
                local old = configure(oldFixture, config)
                local ok, err, expected = old.Sweep.Sweep(1, config.count, 1, stage)
                check(ok, "旧100k完整执行 " .. tostring(err))
                parity(h, old, result, expected)
            else print(TAG .. "NOT RUN 100k fixed-source oracle " .. stage) end
            if stage == 1905 or stage == 200001 then
                check(result.equipCount > 1000, "自然RNG真实千件以上装备，不用强制零掉落")
                eq(result.lootboxCount, #result.equips, "真满包全部保留装备进遗匣")
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
