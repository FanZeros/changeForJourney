-- 状态时序专项：真实 SEM / CF 源码在私有白名单环境执行，不加载 main / 档案 / 网络。
-- 目标 attrs 与结算回调仅为内存边界；不代替完整治疗投射物链、存档或设备验收。
-- 由主代理统一官方 build / 隔离 Runtime；不能以 engine:Exit() 代替业务 RESULT。
local PREFIX = "[status_effect_timing] "
local checks, failures, cases = 0, {}, 0
local function check(ok, label)
    checks = checks + 1
    if not ok then failures[#failures + 1] = label; print(PREFIX .. "FAIL " .. label) end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function near(actual, expected, label)
    check(type(actual) == "number" and math.abs(actual - expected) <= 1e-8,
        label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

local ALLOWED = {
    ["systems.AttributeDef"] = true,
    ["systems.CombatFormula"] = true,
    ["systems.StatusEffectManager"] = true,
    ["systems.BattleDiag"] = true,
    ["core.BattleLayout"] = true,
}
local sources = {}
local function source(path)
    if sources[path] then return sources[path] end
    local file = assert(cache:GetFile(path), "缺少白名单源码 " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local text = table.concat(lines, "\n")
    sources[path] = text
    return text
end
local function fixture()
    local loaded, rng = {}, { calls = 0 }
    local privateMath = {} ---@type table<string, any>
    for k, v in pairs(math) do privateMath[k] = v end
    -- 固定私有骰：仅用于检查燃烧既有暴击分支，不改宿主随机种子。
    privateMath.random = function() rng.calls = rng.calls + 1; return 0.5 end
    local env = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, next = next,
        tonumber = tonumber, tostring = tostring, type = type, select = select,
        setmetatable = setmetatable, getmetatable = getmetatable,
        math = privateMath, table = table, string = string, print = print,
        os = { clock = os.clock },
    }
    env._G = env
    local function import(name)
        if loaded[name] then return loaded[name] end
        assert(ALLOWED[name], "禁止加载非白名单模块 " .. tostring(name))
        local path = name:gsub("%.", "/") .. ".lua"
        local compile = load --[[@as fun(text: string, name: string, mode: string, env: table): function?, string?]]
        local chunk, why = compile(source(path), "@status-private/" .. path, "t", env)
        assert(chunk, tostring(why))
        local value = chunk()
        loaded[name] = value
        return value
    end
    env.require = import
    local sem, cf, ad = import("systems.StatusEffectManager"), import("systems.CombatFormula"), import("systems.AttributeDef")
    return { sem = sem, cf = cf, ad = ad, rng = rng }
end
local function unit(f, resistance)
    return { hp = 10000, name = "memory-target", attrs = {
        get = function(_, key)
            assert(key == f.ad.ABNORMAL_RES, "不允许额外属性读取 " .. tostring(key))
            return resistance or 0
        end,
    } }
end
local function isolated(f)
    local state = f.sem.newSemState()
    f.sem.mount(state)
    return state
end
local function counter()
    local events = {}
    return events, {
        onHot = function(u, src, amount) events[#events + 1] = { u = u, src = src, amount = amount, kind = "hot" } end,
        onDot = function(u, src, amount, crit)
            events[#events + 1] = { u = u, src = src, amount = amount, crit = crit, kind = "dot" }
        end,
    }
end

local function testHotResistanceAndSteps(f)
    local sem = f.sem
    -- 分割不依赖公式结果产生期望：三抗性都应有完整 5 秒 / 5 跳。
    for _, resistance in ipairs({ 0, 50, 80 }) do
        for _, step in ipairs({ 1, 0.1, 1 / 60, 5, 50 }) do
            isolated(f)
            local target, src = unit(f, resistance), { name = "capybara" }
            local events, cb = counter()
            sem.apply(target, sem.HOT, 5, src, { hps = 10.6, dmgReduction = true })
            near(sem.get(target, sem.HOT).remaining, 5, "HOT不缩时 res=" .. resistance)
            local frames = math.ceil(5 / step)
            for _ = 1, frames do sem.update(step, cb) end
            eq(#events, 5, "完整5秒恰5跳 res=" .. resistance .. " step=" .. step)
            for _, event in ipairs(events) do
                check(event.u == target and event.src == src and event.kind == "hot", "HOT来源/目标保持")
                eq(event.amount, 11, "HOT原有四舍五入不变")
            end
            check(not sem.has(target, sem.HOT), "末跳后到期清理")
            sem.update(20, cb)
            eq(#events, 5, "过期后不继续跳")
        end
    end
    eq(f.rng.calls, 0, "HOT不消费暴击骰")
end

local function testNegativeAndMark(f)
    local sem = f.sem
    for _, row in ipairs({ { 0, 5 }, { 50, 2.5 }, { 80, 1 }, { 120, 1 } }) do
        isolated(f)
        local target = unit(f, row[1])
        near(f.cf.calcAbnormalDuration(5, row[1]), row[2], "真实CF异常时长和80%封顶")
        for _, kind in ipairs({ sem.BURNING, sem.FROZEN, sem.SHOCKED, sem.VULNERABLE, sem.ARCANE_MARK }) do
            sem.apply(target, kind, 5, target, { dps = 10, mult = 0.2 })
            near(sem.get(target, kind).remaining, row[2], "负面缩时不变 " .. kind .. "/" .. row[1])
        end
        sem.apply(target, sem.MARKED, 5, target, { mult = 0.25 })
        near(sem.get(target, sem.MARKED).remaining, 5, "战术标记仍豁免抗性")
        local events, cb = counter()
        sem.update(10, cb)
        eq(#events, math.floor(row[2] + 1e-9), "负面燃烧只跳有效时长")
        check(next(sem.mountedState().effects) == nil, "负面与标记到期都清理")
    end
    isolated(f)
    local target = unit(f, 80)
    sem.apply(target, sem.MARKED, 2, target, { mult = 0.25 })
    near(sem.getDamageTakenMult(target), 1.25, "标记原倍率")
    sem.update(0.9)
    local old = sem.get(target, sem.MARKED)
    sem.apply(target, sem.MARKED, 3, target, { mult = 0.4 })
    check(sem.get(target, sem.MARKED) ~= old, "mark仍为普通覆盖身份")
    near(sem.get(target, sem.MARKED).remaining, 3, "mark刷新时长")
    near(sem.getDamageTakenMult(target), 1.4, "mark刷新倍率")
    sem.update(3)
    check(not sem.has(target, sem.MARKED), "mark准确边界清理")
    near(sem.getDamageTakenMult(target), 1, "mark清理后恢复倍率")
end

local function testRefresh(f)
    isolated(f)
    local sem, target = f.sem, unit(f, 80)
    local sourceA, sourceB = { name = "first" }, { name = "latest" }
    local events, cb = counter()
    sem.apply(target, sem.HOT, 5, sourceA, { hps = 10, armorBuff = true })
    local before = sem.get(target, sem.HOT)
    sem.update(0.9, cb)
    for i = 1, 10 do
        local data = { hps = 20 + i, dmgReduction = true }
        local timer = sem.get(target, sem.HOT).tickTimer
        sem.apply(target, sem.HOT, 5, sourceB, data)
        local effect = sem.get(target, sem.HOT)
        near(effect.tickTimer, timer, ".9秒重施保留相位")
        near(effect.remaining, 5, "刷新完整5秒")
        check(effect.source == sourceB and effect.data == data and not effect.data.armorBuff,
            "source/data完整更新而非混入旧字段")
        near(sem.getDamageTakenMult(target), 0.95, "新HOT减伤标记生效")
        sem.update(0.9, cb)
    end
    eq(#events, 9, "持续每.9秒刷新仍每秒跳而非饥饿")
    check(sem.get(target, sem.HOT) ~= before, "HOT刷新用新身份保护回调")
    eq(events[1] and events[1].amount, 21, "下一跳读取最新hps")
    eq(events[#events] and events[#events].amount, 29, "t=9的后续跳读取当时最新hps")
    for _, event in ipairs(events) do check(event.src == sourceB, "下一跳来源已更新") end
    local countBefore = #events
    sem.update(4.1, cb)
    eq(#events - countBefore, 5, "停止刷新后余相位加有效寿命恰五跳")
    check(not sem.has(target, sem.HOT), "刷新结束后最终到期")
end

local function testBoundary(f)
    local sem = f.sem
    for _, kind in ipairs({ sem.HOT, sem.BURNING }) do
        for _, row in ipairs({ { 0.5, 0 }, { 0.9999, 0 }, { 1, 1 }, { 1.0001, 1 }, { 2.5, 2 }, { 5, 5 } }) do
            isolated(f)
            local target = unit(f, 0)
            local events, cb = counter()
            sem.apply(target, kind, row[1], target, { hps = 4, dps = 7 })
            sem.update(100, cb)
            eq(#events, row[2], "跨过期不多跳 " .. kind .. "/" .. row[1])
            check(not sem.has(target, kind), "跨过期删除旧效果")
        end
        isolated(f)
        local target = unit(f, 0)
        local events, cb = counter()
        sem.apply(target, kind, 5, target, { hps = 4, dps = 7 })
        sem.update(4.9, cb)
        eq(#events, 4, "到期前最后一跳仍等待 " .. kind)
        sem.update(0.1, cb)
        eq(#events, 5, "浮点4.9+.1准确末跳 " .. kind)
        check(not sem.has(target, kind), "浮点末帧清理 " .. kind)
        isolated(f)
        events, cb = counter()
        sem.apply(target, kind, 1, target, { hps = 4, dps = 7 })
        sem.update(1 - 1e-5, cb)
        eq(#events, 0, "容差不能吞掉真实剩余时间")
        check(sem.has(target, kind), "真实边界前仍有效")
        sem.update(1e-5, cb)
        eq(#events, 1, "补齐剩余时间才跳")
        check(not sem.has(target, kind), "补齐后清理")
    end
    isolated(f)
    local target = unit(f, 0)
    local events, cb = counter()
    sem.apply(target, sem.HOT, 5, target, { hps = 10 })
    sem.update(0.9, cb)
    local effect = sem.get(target, sem.HOT)
    for _, dt in ipairs({ 0, -0.1, -100, 0 / 0, math.huge }) do
        sem.update(dt, cb)
        check(sem.get(target, sem.HOT) == effect, "无效dt不替换效果")
        near(effect.remaining, 4.1, "非正/非有限dt不延长/消耗生命周期")
        near(effect.tickTimer, 0.9, "非正/非有限dt不后退相位")
        eq(#events, 0, "非正/非有限dt不跳")
    end
    sem.update(0.1, cb)
    eq(#events, 1, "非正dt后正常恢复")
    sem.removeUnit(target)
    sem.apply(target, sem.HOT, 1, target, { hps = 10 })
    sem.update(10) -- 无回调只倒计时，不留下欠账。
    check(not sem.has(target, sem.HOT), "无回调仍清到期效果")
    sem.apply(target, sem.HOT, 0, target, { hps = 10 })
    check(not sem.has(target, sem.HOT), "零时长不施加")
    sem.apply(target, sem.HOT, -1, target, { hps = 10 })
    check(not sem.has(target, sem.HOT), "负时长不施加")
end

local function testBurning(f)
    isolated(f)
    local sem, target = f.sem, unit(f, 0)
    local sourceA, sourceB = { name = "dragonA" }, { name = "dragonB" }
    local events, cb = counter()
    sem.apply(target, sem.BURNING, 2, sourceA, { dps = 10 })
    sem.update(0.9, cb)
    sem.apply(target, sem.BURNING, 2, sourceB, { dps = 20 })
    near(sem.get(target, sem.BURNING).tickTimer, 0, "非叠层燃烧覆盖仍归零")
    sem.update(0.1, cb)
    eq(#events, 0, "HOT修复不改变普通燃烧覆盖相位")
    sem.update(1.9, cb)
    eq(#events, 2, "普通燃烧到期末跳也修复")
    eq(events[1] and events[1].amount, 20, "普通燃烧覆盖dps")
    check(events[1] and events[1].src == sourceB, "普通燃烧覆盖来源")

    sem.apply(target, sem.BURNING, 2, sourceA, { dps = 10, stackable = true, maxStacks = 3 })
    sem.update(0.9, cb)
    local effect = sem.get(target, sem.BURNING)
    sem.apply(target, sem.BURNING, 3, sourceB,
        { dps = 20, stackable = true, maxStacks = 3, canCrit = true, critRate = 100, critDmg = 50 })
    check(sem.get(target, sem.BURNING) == effect, "叠层燃烧仍原位更新")
    near(effect.tickTimer, 0.9, "叠层保留相位")
    near(effect.remaining, 3, "叠层刷新时长")
    eq(effect.data.stacks, 2, "燃烧二层")
    eq(effect.data.dps, 30, "叠层累加dps")
    check(effect.source == sourceA, "叠层仍保留最初来源")
    sem.apply(target, sem.BURNING, 4, sourceB, { dps = 5, stackable = true, maxStacks = 3 })
    eq(sem.getBurningStacks(target), 3, "燃烧三层封顶")
    eq(effect.data.dps, 35, "第三层dps")
    sem.apply(target, sem.BURNING, 5, sourceB,
        { dps = 999, stackable = true, maxStacks = 3, critRate = 0, critDmg = 999 })
    eq(effect.data.dps, 35, "满层不再加dps")
    eq(effect.data.critRate, 100, "满层仍不覆盖原暴率")
    eq(effect.data.critDmg, 50, "满层仍不覆盖原暴伤")
    near(effect.remaining, 5, "满层仅刷新时长")
    local callsBefore, eventsBefore = f.rng.calls, #events
    sem.update(5, cb)
    eq(#events - eventsBefore, 5, "叠层刷新保留.9相位且不多跳")
    eq(f.rng.calls - callsBefore, 5, "每个可暴燃烧跳恰一个骰")
    for i = eventsBefore + 1, #events do
        check(events[i].src == sourceA and events[i].crit == true, "叠层保留来源/原暴击规则")
        eq(events[i].amount, 53, "原燃烧暴伤50%仍为floor(35*1.5+.5)")
    end
    check(not sem.has(target, sem.BURNING), "叠层到期清理")
end

local function testCallbacks(f)
    local sem = f.sem
    for _, kind in ipairs({ sem.HOT, sem.BURNING }) do
        for _, operation in ipairs({ "remove", "replace", "removeUnit", "reset", "death" }) do
            isolated(f)
            local target = unit(f, 0)
            local calls, replacement = 0, {}
            local function onTick()
                calls = calls + 1
                if operation == "remove" then sem.remove(target, kind)
                elseif operation == "removeUnit" then sem.removeUnit(target)
                elseif operation == "reset" then sem.reset()
                elseif operation == "death" then target.hp = 0
                else
                    sem.remove(target, kind)
                    sem.apply(target, kind, 7, replacement, { hps = 99, dps = 99 })
                end
            end
            sem.apply(target, kind, 5, target, { hps = 4, dps = 7 })
            sem.update(20, { onHot = onTick, onDot = onTick })
            eq(calls, 1, "回调" .. operation .. "停止旧效果后续跳 " .. kind)
            local current = sem.get(target, kind)
            if operation == "replace" then
                check(current and current.source == replacement, "回调新效果不被旧到期误删")
                near(current and current.remaining, 7, "新效果不消费旧帧超期dt")
                near(current and current.tickTimer, 0, "移除重建不继承旧相位")
            else
                check(current == nil, "回调移除/死亡/清场后无残留 " .. operation)
            end
        end
    end
    isolated(f)
    local target, replacement = unit(f, 0), {}
    local calls = 0
    sem.apply(target, sem.HOT, 1, target, { hps = 10 })
    sem.update(10, { onHot = function()
        calls = calls + 1
        sem.apply(target, sem.HOT, 5, replacement, { hps = 30 })
    end })
    eq(calls, 1, "准确到期回调刷新HOT仅结算旧生命周期")
    local current = sem.get(target, sem.HOT)
    check(current and current.source == replacement, "到期回调刷新HOT不误删")
    near(current and current.tickTimer, 0, "到期回调刷新不继承未来跳数")
    near(current and current.remaining, 5, "到期回调刷新完整寿命")

    isolated(f)
    calls = 0
    sem.apply(target, sem.BURNING, 1, target, { dps = 10, stackable = true })
    sem.update(10, { onDot = function()
        calls = calls + 1
        sem.apply(target, sem.BURNING, 5, replacement, { dps = 20, stackable = true })
    end })
    current = sem.get(target, sem.BURNING)
    eq(calls, 1, "燃烧原位刷新不消费旧寿命外dt")
    check(current and current.source == target, "原位刷新仍保留原来源")
    near(current and current.remaining, 5, "原位刷新时长不被旧到期删除")
    eq(sem.getBurningStacks(target), 2, "到期回调仍可正常叠层")
    sem.update(1, {})
    near(sem.get(target, sem.BURNING).remaining, 4, "无回调仍正常倒计时")
end

local function testMountIsolation(f)
    local sem = f.sem
    local first, second = sem.newSemState(), sem.newSemState()
    local target = unit(f, 80)
    sem.mount(first)
    sem.apply(target, sem.HOT, 5, target, { hps = 10 })
    local events, cb = counter()
    sem.update(0.9, cb)
    local firstEffect = sem.get(target, sem.HOT)
    sem.mount(second)
    check(not sem.has(target, sem.HOT), "同一单位key跨mount不共享状态")
    sem.apply(target, sem.HOT, 2, target, { hps = 20 })
    sem.update(2, cb)
    eq(#events, 2, "第二实例单独两跳")
    near(firstEffect.tickTimer, 0.9, "第二实例更新不推进第一实例相位")
    near(firstEffect.remaining, 4.1, "第二实例更新不推进第一实例时长")
    sem.mount(first)
    sem.update(0.1, cb)
    eq(#events, 3, "重新mount第一实例接续原跳")
    eq(events[3] and events[3].amount, 10, "第一实例仍原hps")
    sem.mount(second)
    sem.apply(target, sem.HOT, 5, target, { hps = 20 })
    local secondEffect = sem.get(target, sem.HOT)
    sem.mount(first)
    local calls = 0
    sem.update(20, { onHot = function() calls = calls + 1; sem.mount(second) end })
    eq(calls, 1, "回调切mount中止旧实例剩余跳")
    check(sem.get(target, sem.HOT) == secondEffect, "切mount不误删新实例效果")
    near(secondEffect.remaining, 5, "切mount不推进新实例寿命")
    near(secondEffect.tickTimer, 0, "切mount不推进新实例相位")
    sem.reset()
    sem.mount(first)
    check(sem.has(target, sem.HOT), "另一实例reset不清当前实例")
    target.hp = 0
    sem.update(1, cb)
    check(next(first.effects) == nil, "已死单位不跳并清理")
    sem.apply(target, sem.HOT, 5, target, { hps = 10 })
    check(not sem.has(target, sem.HOT), "死亡单位不接受HOT")
    sem.mount(nil)
    check(not sem.has(target, sem.HOT), "默认mount也独立")
end

function Start()
    print(PREFIX .. "BEGIN real SEM/CF; memory-only whitelist; no main/save/network")
    local ok, why = pcall(function()
        local f = fixture()
        for _, test in ipairs({ testHotResistanceAndSteps, testNegativeAndMark, testRefresh,
            testBoundary, testBurning, testCallbacks, testMountIsolation }) do
            cases = cases + 1
            test(f)
        end
    end)
    if not ok then failures[#failures + 1] = tostring(why); print(PREFIX .. "ERROR " .. tostring(why)) end
    print(string.format("%scases=%d checks=%d failure_count=%d RESULT=%s", PREFIX,
        cases, checks, #failures, #failures == 0 and "PASS" or "FAIL"))
    engine:Exit()
end
