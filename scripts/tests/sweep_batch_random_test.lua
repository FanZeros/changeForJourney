-- 独立纯 Lua 专项，仅加载概率模块，不加载 main/业务/存档/引擎资源。
-- 本地：package.path 加 scripts/?.lua 后 require 本文件并调用 run()。
-- Runtime：以 tests/sweep_batch_random_test.lua 为入口，Start() 执行并退出；失败抛错。
local BatchRandom = require("shared.sweep.BatchRandom")
local M = {}
local assertions = 0
local cases = 0
---@type string[]
local failures = {}

---@param condition boolean
---@param name string
local function check(condition, name)
    assertions = assertions + 1
    assert(condition, name)
end

---@param actual any
---@param expected any
---@param name string
local function eq(actual, expected, name)
    check(actual == expected, name .. "：" .. tostring(actual) .. " / " .. tostring(expected))
end

---@param name string
---@param fn fun()
local function runCase(name, fn)
    cases = cases + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. "：" .. tostring(err) end
    print("[扫荡批量概率专项] " .. (ok and "通过 " or "失败 ") .. name)
end

-- Park-Miller 的私有种子，不调用 math.randomseed，不依赖主进程或平台全局随机状态。
---@param seed integer
---@return fun():number
---@return fun():integer
local function seeded(seed)
    local state = seed
    local calls = 0
    return function()
        local nextState = (state * 16807) % 2147483647
        state = nextState
        calls = calls + 1
        return state / 2147483647
    end, function() return calls end
end

---@param fn fun():any
---@param needle string
local function rejects(fn, needle)
    local ok, err = pcall(fn)
    check(not ok, "必须拒绝而非返回伪结果")
    check(type(err) == "string" and err:find(needle, 1, true) ~= nil, "错误说明：" .. tostring(err))
end

---@param values number[]
---@param tail number?
---@return fun():number
---@return fun():integer
local function scripted(values, tail)
    local index = 0
    return function()
        index = index + 1
        return values[index] or tail or 0
    end, function() return index end
end

---@param n integer
---@param p number
---@return number[]
local function pmf(n, p)
    local result = {}
    -- 独立组合数公式而非被测几何/Beta/Gamma过程；完整支持集，数组从1开始。
    ---@type number
    local choose = 1
    for k = 0, n do
        result[k + 1] = choose * p ^ k * (1 - p) ^ (n - k)
        choose = choose * (n - k) / (k + 1)
    end
    return result
end

-- 每个统计检查均使用已知分布的 Bernstein 界；固定私有种子，无平台随机统计抖动。
-- L=log(2/alpha)，单条双尾误报概率<=alpha。不是要求采样恰等于期望或任意百分比。
local CONFIDENCE_LOG = math.log(2 / 1e-10)
---@param variance number
---@param bound number
---@param samples integer
---@return number
local function errorBound(variance, bound, samples)
    return math.sqrt(2 * math.max(0, variance) * CONFIDENCE_LOG / samples)
        + 2 * bound * CONFIDENCE_LOG / (3 * samples)
end

---@param n integer
---@param p number
---@param samples integer
---@param seed integer
local function distribution(n, p, samples, seed)
    local random = seeded(seed)
    local counts = {}
    for k = 0, n do counts[k + 1] = 0 end
    local mean = n * p
    local variance = mean * (1 - p)
    ---@type number, number
    local sum, centeredSum = 0, 0
    local supportOK = true
    for _ = 1, samples do
        local x = BatchRandom.binomial(n, p, random)
        if x < 0 or x > n or x ~= math.floor(x) then
            supportOK = false
            break
        end
        counts[x + 1] = counts[x + 1] + 1
        sum = sum + x
        centeredSum = centeredSum + (x - mean) ^ 2
    end
    check(supportOK, "所有结果为支持集内整数")
    local expected = pmf(n, p)
    ---@type number, integer
    local totalMass, totalCounts = 0, 0
    for k = 0, n do
        local q = assert(expected[k + 1], "完整PMF缺少分量")
        totalMass = totalMass + q
        totalCounts = totalCounts + counts[k + 1]
        check(math.abs(counts[k + 1] / samples - q) <= errorBound(q * (1 - q), 1, samples),
            "完整PMF分量 " .. k .. " 不符")
    end
    check(math.abs(totalMass - 1) < 1e-12, "独立PMF归一")
    eq(totalCounts, samples, "无遗漏样本")
    local observedMean = sum / samples
    check(math.abs(observedMean - mean) <= errorBound(variance, n, samples), "均值符合二项分布")
    local fourth = 3 * variance * variance + variance * (1 - 6 * p * (1 - p))
    local squaredBound = math.max(mean * mean, (n - mean) ^ 2)
    check(math.abs(centeredSum / samples - variance)
        <= errorBound(fourth - variance * variance, squaredBound, samples), "二阶中心矩符合真实方差")
    local sampleVariance = centeredSum / samples - (observedMean - mean) ^ 2
    check(math.abs(sampleVariance - variance) <= errorBound(fourth - variance * variance, squaredBound, samples)
        + errorBound(variance, n, samples) ^ 2, "样本方差符合二项分布")
    print(string.format("[扫荡批量概率专项] 分布 n=%d p=%.9g 样本=%d 均值=%.6f 方差=%.6f",
        n, p, samples, observedMean, sampleVariance))
end

local function edgeCases()
    runCase("零次与零一概率不消费随机，检查点保留", function()
        local calls, checkpoints = 0, 0
        local function forbidden() calls = calls + 1; error("退化分布不应取随机") end
        local function progress() checkpoints = checkpoints + 1 end
        for _, n in ipairs({ 0, 1, 1000000, 10000000, 9007199254740991 }) do
            eq(BatchRandom.binomial(n, 0, forbidden, progress), 0, "p0")
            eq(BatchRandom.binomial(n, 1, forbidden, progress), n, "p1")
        end
        eq(BatchRandom.binomial(0, 0.314, forbidden), 0, "n0")
        eq(calls, 0, "全程随机调用0")
        check(checkpoints >= 10, "退化结果也可取消")
    end)
    runCase("参数与非法随机值拒绝，不读取外部环境", function()
        for _, n in ipairs({ -1, 0.5, math.huge, -math.huge, 0 / 0, 9007199254740992 }) do
            rejects(function() return BatchRandom.binomial(n, 0.5) end, "n 必须")
        end
        for _, p in ipairs({ -0.1, 1.1, math.huge, -math.huge, 0 / 0 }) do
            rejects(function() return BatchRandom.binomial(4, p) end, "p 必须")
        end
        for _, u in ipairs({ -0.1, 1, math.huge, -math.huge, 0 / 0 }) do
            rejects(function() return BatchRandom.binomial(4, 0.25, function() return u end) end, "随机源必须返回")
        end
        rejects(function() return BatchRandom.binomial(4, 0.25, function() return "无效" end) end, "随机源必须返回")
        rejects(function() return BatchRandom.binomial(4, 0.25, function() return nil end) end, "随机源必须返回")
        -- 故意越过静态类型以验收运行时入口校验。
        local invalid = false
        ---@cast invalid any
        rejects(function() return BatchRandom.binomial(4, 0.25, invalid) end, "随机源必须为函数")
        rejects(function() return BatchRandom.binomial(4, 0.25, nil, invalid) end, "检查点必须为函数")
        rejects(function() return BatchRandom.binomial(invalid, 0.25) end, "n 必须")
        rejects(function() return BatchRandom.binomial(4, invalid) end, "p 必须")
    end)
    runCase("几何跳跃确定路径与零随机", function()
        local random, calls = scripted({ 0.9, 0.6, 0.1 })
        -- p=.25：等待失败0次、1次、8次；第1/3次试验命中，其后越过n=10。
        eq(BatchRandom.binomial(10, 0.25, random), 2, "几何间隔确定结果")
        eq(calls(), 3, "按命中跳跃而非逐n")
        for _, n in ipairs({ 1, 10, 1000000, 10000000 }) do
            eq(BatchRandom.binomial(n, 1e-7, function() return 0 end), 0, "零随机表示无穷等待")
        end
        local zeroCalls = 0
        local x = BatchRandom.binomial(10000000, 0.5, function() zeroCalls = zeroCalls + 1; return 0 end)
        check(x >= 0 and x <= 10000000, "Beta/Gamma零源仍有限结束")
        check(zeroCalls < 256, "零源无拒绝死循环")
    end)
    runCase("极小概率保留log1p有效位，先比较避免除法溢出", function()
        eq(1 - 1e-20, 1, "极小概率确会令朴素减法丢失")
        -- n=最大安全整数，p=1e-20：特制U使等待约1000次，继而U0终止。
        local random, calls = scripted({ 1 - 1e-15, 0 })
        eq(BatchRandom.binomial(9007199254740991, 1e-20, random), 1, "极小正p仍可真实命中")
        eq(calls(), 2, "极小概率只两次随机")
        eq(BatchRandom.binomial(10000000, 1e-300, function() return 0.5 end), 0, "极小p不溢出")
        local smallest = 2 ^ -1074
        check(smallest > 0, "双精度保留最小次正规数")
        eq(BatchRandom.binomial(10000000, smallest, function() return 0.5 end), 0, "次正规概率无NaN")
        eq(BatchRandom.binomial(10000000, 1 - 2 ^ -53, function() return 0 end), 10000000, "接近1概率安全翻补")
    end)
    runCase("Beta低侧与高侧路径均执行", function()
        -- 第一Gamma z=-4、第二Gamma z=+4，接受随机=.1，令Beta明显低于p=.4。
        local radius = 1 - math.exp(-8)
        local random, calls = scripted({ radius, 0.5, 0.1, radius, 0, 0.1 })
        local lowBeta = BatchRandom.binomial(100, 0.4, random)
        check(calls() >= 6, "真实经过两次Gamma")
        check(lowBeta >= 51 and lowBeta <= 100, "Beta低于p时至少累计a=51")
        local highRandom, highCalls = scripted({ radius, 0, 0.1, radius, 0.5, 0.1 })
        local highBeta = BatchRandom.binomial(100, 0.4, highRandom)
        check(highCalls() >= 6, "高侧也经过两次Gamma")
        check(highBeta >= 0 and highBeta <= 50, "Beta高于p时缩到a-1=50")
    end)
end

local function statisticalCases()
    ---@type {n:integer,p:number}[]
    local configs = {
        { n = 1, p = 0.25 }, { n = 2, p = 0.5 }, { n = 5, p = 0.25 },
        { n = 8, p = 0.5 }, { n = 12, p = 0.125 }, { n = 12, p = 0.875 },
        { n = 32, p = 0.5 }, -- np=16几何边界
        { n = 33, p = 0.5 }, -- np>16的最小Beta拆分
        { n = 65, p = 0.25 }, { n = 65, p = 0.75 }, { n = 80, p = 0.35 },
        { n = 127, p = 0.4 },
    }
    for index, config in ipairs(configs) do
        runCase("完整PMF及矩 n=" .. config.n .. " p=" .. config.p, function()
            distribution(config.n, config.p, 40000, 31217 + index * 941)
        end)
    end
    runCase("相同随机流的逐样本补概率对称", function()
        for _, n in ipairs({ 1, 33, 127, 1000000, 10000000 }) do
            for _, p in ipairs({ 0.125, 0.25, 0.375 }) do
                local ra, ca = seeded(7781)
                local rb, cb = seeded(7781)
                for _ = 1, 256 do
                    eq(BatchRandom.binomial(n, p, ra) + BatchRandom.binomial(n, 1 - p, rb), n, "逐样本互补")
                end
                eq(ca(), cb(), "互补随机消费一致")
            end
        end
    end)
    runCase("小概率大n仍有方差，不是泊松或期望返回", function()
        for _, p in ipairs({ 1e-7, 0.0000017, 0.125, 0.5, 0.9999999 }) do
            local n, samples = 1000000, 12000
            local random = seeded(7011)
            local mean, variance = n * p, n * p * (1 - p)
            ---@type number, number
            local sum, squares = 0, 0
            for _ = 1, samples do
                local x = BatchRandom.binomial(n, p, random)
                check(x >= 0 and x <= n and x == math.floor(x), "大n整数支持集")
                sum = sum + x
                squares = squares + (x - mean) ^ 2
            end
            -- 大n若直接用n作为Bernstein界会过松，此处用精确矩的Chebyshev宽界，
            -- 固定源下8标准误（均值）/12标准误（二阶矩），并显式拒绝零方差。
            check(math.abs(sum / samples - mean) < 8 * math.sqrt(variance / samples), "大n均值")
            local fourth = 3 * variance * variance + variance * (1 - 6 * p * (1 - p))
            check(math.abs(squares / samples - variance)
                < 12 * math.sqrt((fourth - variance * variance) / samples), "大n真实方差")
            check(squares > 0, "不是固定期望值")
        end
    end)
end

local function controlCases()
    runCase("固定种子重复以及百万千万n随机调用实测界", function()
        local maximum = 0
        for _, n in ipairs({ 1000000, 10000000 }) do
            for _, p in ipairs({ 1e-8, 1e-4, 0.125, 0.5, 0.875, 1 - 1e-8 }) do
                for seed = 1, 40 do
                    local ra, ca = seeded(seed * 907 + 3)
                    local rb, cb = seeded(seed * 907 + 3)
                    local a = BatchRandom.binomial(n, p, ra)
                    local b = BatchRandom.binomial(n, p, rb)
                    eq(a, b, "固定种子逐样本重现")
                    eq(ca(), cb(), "固定种子随机消费重现")
                    -- 这是固定样本回归预算，不冒称所有合法随机流都有1024次理论上界。
                    check(ca() < 1024, "固定大n样本随机调用小于1024，不逐n")
                    maximum = math.max(maximum, ca())
                end
            end
        end
        print("[扫荡批量概率专项] 固定百万/千万样本最大随机调用=" .. maximum)
    end)
    runCase("检查点逐次yield与并发交错不改变私有随机结果", function()
        local ra, ca = seeded(51817)
        local rb, cb = seeded(61211)
        local expectedA = BatchRandom.binomial(10000000, 0.37, ra)
        local expectedB = BatchRandom.binomial(1000000, 0.499, rb)
        local ya, cya = seeded(51817)
        local yb, cyb = seeded(61211)
        local yields = 0
        local function progress() yields = yields + 1; coroutine.yield("检查点") end
        local ta = coroutine.create(function() return BatchRandom.binomial(10000000, 0.37, ya, progress) end)
        local tb = coroutine.create(function() return BatchRandom.binomial(1000000, 0.499, yb, progress) end)
        local results = {}
        for _ = 1, 2048 do
            for index, thread in ipairs({ ta, tb }) do
                if coroutine.status(thread) ~= "dead" then
                    local ok, value = coroutine.resume(thread)
                    check(ok, "yield后恢复不报错：" .. tostring(value))
                    if coroutine.status(thread) == "dead" then results[index] = value
                    else eq(value, "检查点", "真实让出") end
                end
            end
            if coroutine.status(ta) == "dead" and coroutine.status(tb) == "dead" then break end
        end
        eq(coroutine.status(ta), "dead", "A有限结束")
        eq(coroutine.status(tb), "dead", "B有限结束")
        eq(results[1], expectedA, "A与同步相同")
        eq(results[2], expectedB, "B与同步相同")
        eq(cya(), ca(), "A随机消费相同")
        eq(cyb(), cb(), "B随机消费相同")
        check(yields > ca() + cb(), "检查点覆盖取随机与拆分")
    end)
    runCase("取消/异常身份传播且无部分计数", function()
        local random, calls = seeded(9017)
        local points = 0
        rejects(function()
            return BatchRandom.binomial(10000000, 0.37, random, function()
                points = points + 1
                return points < 9
            end)
        end, "已取消")
        check(calls() > 0 and calls() < 9, "取消发生在随机消费中途")
        rejects(function() return BatchRandom.binomial(0, 1, nil, function() return false end) end, "已取消")
        local sentinel = { reason = "宿主停止" }
        local ok, err = pcall(function()
            return BatchRandom.binomial(1000000, 0.5, random, function() error(sentinel) end)
        end)
        eq(ok, false, "检查点throw向外传播")
        eq(err, sentinel, "保留原异常对象身份")
        local sourceOK, sourceError = pcall(function()
            return BatchRandom.binomial(1000000, 0.5, function() error(sentinel) end)
        end)
        eq(sourceOK, false, "随机源throw向外传播")
        eq(sourceError, sentinel, "随机源原异常身份")
        local cancelled = false
        local thread = coroutine.create(function()
            return BatchRandom.binomial(10000000, 0.2, random, function()
                coroutine.yield("暂停")
                return not cancelled
            end)
        end)
        eq(coroutine.resume(thread), true, "取消前真实yield")
        cancelled = true
        local resumed, cancelError = coroutine.resume(thread)
        eq(resumed, false, "resume后false取消")
        check(tostring(cancelError):find("已取消", 1, true) ~= nil, "恢复后的取消错误")
    end)
    runCase("Gamma拒绝循环有限失败，拒绝期间仍可取消", function()
        local calls = 0
        local nearOne = 1 - 2 ^ -52
        local function hostile()
            calls = calls + 1
            return calls % 3 == 2 and 0 or nearOne -- z约8.49，接受随机接近1，持续拒绝。
        end
        rejects(function() return BatchRandom.binomial(34, 0.5, hostile) end, "Gamma 拒绝次数")
        eq(calls, 4096 * 3, "拒绝轮数有界，不返回近似")
        calls = 0
        local points = 0
        rejects(function()
            return BatchRandom.binomial(34, 0.5, hostile, function()
                points = points + 1
                if points == 40 then return false end
            end)
        end, "已取消")
        check(calls > 3 and calls < 40, "拒绝期间检查点生效")
    end)
    runCase("几何恶意源触顶失败而非逐千万次试验", function()
        local calls = 0
        rejects(function()
            return BatchRandom.binomial(10000000, 1e-10, function()
                calls = calls + 1
                return 1 - 2 ^ -52
            end)
        end, "随机调用安全上限")
        eq(calls, 65536, "异常源有限失败")
    end)
end

---@return {cases:integer,assertions:integer,failures:integer}
function M.run()
    assertions, cases, failures = 0, 0, {}
    edgeCases()
    statisticalCases()
    controlCases()
    print(string.format("[扫荡批量概率专项] 汇总：组数=%d 断言=%d 失败=%d", cases, assertions, #failures))
    for _, failure in ipairs(failures) do print("[扫荡批量概率专项] 失败详情 " .. failure) end
    assert(#failures == 0, "扫荡批量概率专项失败")
    return { cases = cases, assertions = assertions, failures = #failures }
end

function Start()
    M.run()
    if engine then engine:Exit() end
end

return M
