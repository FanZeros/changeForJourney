-- 扫荡批量计数的独立概率模块；不加载业务、文件或引擎对象。
-- 保持二项分布，不保持旧版逐杀随机序列；随机源应为相互独立的 [0,1) 均匀数。
local M = {}

---@alias BatchRandomSource fun(): number
---@alias BatchRandomCheckpoint fun(): boolean?
---@class BatchRandomState
---@field random BatchRandomSource
---@field checkpoint BatchRandomCheckpoint?
---@field draws integer

-- 仅为失效/恶意随机源提供有限失败边界；触顶抛错，绝不改返回期望值或近似计数。
-- 正常源的拒绝次数没有数学上的有限上界，故这不是保证必定成功的随机调用上界。
local MAX_DRAWS = 65536
local MAX_GAMMA_ATTEMPTS = 4096
local MAX_SAFE_N = 9007199254740991 -- 2^53-1；也保证 n/2 与整数累计可精确表示。
local SMALL_MEAN = 16
local TWO_PI = 2 * math.pi

---@param state BatchRandomState
local function checkpoint(state)
    if state.checkpoint and state.checkpoint() == false then
        error("批量随机已取消", 0)
    end
end

---@param state BatchRandomState
---@return number
local function uniform(state)
    checkpoint(state) -- 每次取随机数前可 yield/取消，拒绝循环同样不能绕过。
    if state.draws >= MAX_DRAWS then error("批量随机超过随机调用安全上限", 0) end
    state.draws = state.draws + 1
    local u = state.random()
    if type(u) ~= "number" or not (u >= 0 and u < 1) then
        error("批量随机源必须返回 [0,1) 内的有限数字", 0)
    end
    return u
end

-- Lua 5.4 没有标准 math.log1p；修正 1+x 的舍入，尤其不能令极小 p 的 log(1-p)=0。
-- 本文件调用的 x 均严格大于 -1；若 1+x 舍入为 1，返回 x 保留其有效位。
---@param x number
---@return number
local function log1p(x)
    local y = 1 + x
    if y == 1 then return x end
    return math.log(y) * (x / (y - 1))
end

-- 稳定计算 log(1+t)-t，供 Gamma 的对数接受判据消除大 shape 时的相消。
---@param t number
---@return number
local function log1pMinusX(t)
    if math.abs(t) < 0.001 then
        return t * t * (-0.5 + t * (1 / 3 + t * (-0.25 + t * (0.2
            + t * (-1 / 6 + t * (1 / 7 - t / 8))))))
    end
    return log1p(t) - t
end

-- Marsaglia-Tsang (2000), shape>=1。正态只用于 Gamma 提案，不是二项计数近似。
-- Box-Muller 用 1-U∈(0,1]：U=0 合法地产生半径0，无 log(0)、无钳制/重抽偏差。
-- 不缓存另一正态数，避免跨请求共享状态或 yield 后相互污染。
---@param shape integer
---@param state BatchRandomState
---@return number
local function gamma(shape, state)
    local d = shape - 1 / 3
    local c = 1 / math.sqrt(9 * d)
    for _ = 1, MAX_GAMMA_ATTEMPTS do
        local radial = uniform(state)
        local angle = uniform(state)
        local z = math.sqrt(-2 * log1p(-radial)) * math.cos(TWO_PI * angle)
        local t = c * z
        if t > -1 then
            local base = 1 + t
            local v = base * base * base
            local u = uniform(state)
            local z2 = z * z
            -- 1-v+log(v) = 3*(log1p(t)-t)-t^2*(3+t)。两级判据是精确拒绝采样。
            if u < 1 - 0.0331 * z2 * z2 or u == 0
                or math.log(u) < 0.5 * z2 + d * (3 * log1pMinusX(t) - t * t * (3 + t)) then
                return d * v
            end
        end
    end
    error("批量随机 Gamma 拒绝次数超过安全上限", 0)
end

--- 采样 Binomial(n,p)，返回实际随机整数而不是期望值。
--- 小 np：独立几何等待时间跳过失败；大 np：Beta 次序统计量拆分，每轮至少减半 n。
--- 数学依据：n 个 U(0,1) 的第 a 个次序统计量 B~Beta(a,n-a+1)。给定 B，
--- p<=B 时下侧 a-1 个点落入 [0,p] 的数为 Bin(a-1,p/B)；p>B 时已含 a 个点，
--- 余下数为 Bin(n-a,(p-B)/(1-B))。Beta=Ga/(Ga+Gb)，两独立 Gamma 共尺度。
--- 每轮翻补使用 Bin(n,p)=n-Bin(n,1-p)，offset+direction*X 始终表示原结果。
--- “精确”指分布恒等式及拒绝采样，无正态/泊松计数近似；仍受双精度/RNG离散性限制。
--- checkpoint 可直接 coroutine.yield；返回 false 或抛错中断，异常原样传播，无部分结果。
--- 无 I/O、无回滚随机源：取消前已消费的随机数不会恢复。nil/true 表示继续。
---@param n number 有限整数，0..2^53-1
---@param p number 有限概率，0..1
---@param random BatchRandomSource? 默认 math.random，不重设全局种子
---@param check BatchRandomCheckpoint? 同步调用；含退化结果也会检查
---@return integer
function M.binomial(n, p, random, check)
    if type(n) ~= "number" or not (n >= 0 and n <= MAX_SAFE_N) or n ~= math.floor(n) then
        error("批量随机 n 必须为 0..2^53-1 的整数", 0)
    end
    if type(p) ~= "number" or not (p >= 0 and p <= 1) then
        error("批量随机 p 必须为 0..1 的有限概率", 0)
    end
    if random ~= nil and type(random) ~= "function" then error("批量随机源必须为函数", 0) end
    if check ~= nil and type(check) ~= "function" then error("批量随机检查点必须为函数", 0) end
    local state = { random = random or math.random, checkpoint = check, draws = 0 }
    ---@cast state BatchRandomState
    local trials = math.floor(n)
    local probability = p
    local offset, direction = 0, 1
    checkpoint(state)
    while trials > 0 and probability > 0 do
        checkpoint(state)
        if probability > 0.5 then
            offset = offset + direction * trials
            direction = -direction
            probability = 1 - probability
        end
        if probability == 0 then break end
        if trials * probability <= SMALL_MEAN then
            local logFailure = log1p(-probability)
            local remaining = trials
            local successes = 0
            while remaining > 0 do
                -- G=floor(log(U)/log(1-p))，P(G=g)=(1-p)^g*p。
                -- U=0 对应无穷等待，在当前有限区间直接结束，不重抽或制造全掉。
                local u = uniform(state)
                if u == 0 then break end
                local logSurvival = math.log(u)
                -- 先比较再除，极小 p 的商可溢出为 inf，但剩余次数与乘积仍安全。
                if logSurvival <= remaining * logFailure then break end
                local gap = math.floor(logSurvival / logFailure)
                remaining = remaining - gap - 1
                successes = successes + 1
            end
            offset = offset + direction * successes
            break
        end
        local a = 1 + math.floor(trials / 2)
        local b = trials - a + 1
        local ga = gamma(a, state)
        local gb = gamma(b, state)
        local beta = ga / (ga + gb)
        if not (beta > 0 and beta < 1) then error("批量随机 Beta 超出有效开区间", 0) end
        if beta >= probability then
            trials = a - 1
            probability = probability / beta
        else
            offset = offset + direction * a
            trials = b - 1
            probability = (probability - beta) / (1 - beta)
        end
    end
    checkpoint(state)
    return math.floor(offset)
end

return M
