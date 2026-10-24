-- 战斗用真实时钟：侧栏暂停只扣除暂停区间，不改引擎全局 time 或 UI 时钟。
-- dt 驱动的攻击/动画由宿主跳过；本模块保护死亡兜底、耗时与历史CPU限时buff。
local BattleClock = {}
local paused = false
local wallOffset, cpuOffset = 0, 0
local pausedWall, pausedCpu = 0, 0

---@return number
function BattleClock.now()
    local wall = paused and pausedWall or time.elapsedTime
    return wall - wallOffset
end

--- 保留旧 os.clock() 计时语义，只剔除侧栏暂停期间消耗的 CPU 时间。
---@return number
function BattleClock.cpuNow()
    local cpu = paused and pausedCpu or os.clock()
    return cpu - cpuOffset
end

---@param value boolean
function BattleClock.setPaused(value)
    value = value == true
    if value == paused then return end
    local wall, cpu = time.elapsedTime, os.clock()
    if value then
        pausedWall, pausedCpu = wall, cpu
    else
        wallOffset = wallOffset + math.max(0, wall - pausedWall)
        cpuOffset = cpuOffset + math.max(0, cpu - pausedCpu)
    end
    paused = value
end

---@return boolean
function BattleClock.isPaused()
    return paused
end

-- 不提供重置offset：仍存活的死亡登记/累计统计必须保持同一时间坐标。
return BattleClock
