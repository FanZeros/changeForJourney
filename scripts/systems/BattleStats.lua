-- ============================================================================
-- BattleStats - 战斗伤害 / 治疗 / 承伤统计（波次桶 + 累计桶 双口径）
-- 职责: 采集战斗中每个己方英雄的输出、治疗、承受伤害，供统计面板实时展示
-- 范围: 仅统计己方英雄；按队伍分桶（mount(teamIdx)，0=主线默认桶）
-- [累计统计] 双桶设计:
--   波次桶 buckets    —— 随 BattleCombat.reset() 每波清零（结算面板等旧口径）
--   累计桶 accumBuckets —— 跨波/跨场次累加，仅 resetAccum()(面板重置按钮)
--                          或 resetAccumForTeam()(队伍编成变更) 时清空
--   record* 同时写两桶；getSorted/getTotal/getDuration/hasData 传 useAccum=true 读累计
-- 归因: 以 heroId 为 key 聚合（避免 setAllies 重建单位引用导致累计丢失）
-- ============================================================================

local BattleStats = {}

-- stats[heroId] = {
--   heroId, name,
--   totalDamage,  -- 总输出（普攻+连击+天赋/弹射/飞剑+DOT）
--   physDamage,   -- 物理伤害分量
--   magDamage,    -- 魔法伤害分量
--   dotDamage,    -- 持续伤害(燃烧等)分量
--   critDamage,   -- 暴击伤害分量
--   hitCount,     -- 命中次数（所有直接伤害，含不可暴击类型）
--   critHitCount, -- 可暴击命中次数（暴击率分母）
--   critCount,    -- 暴击次数（仅 critHitCount 内统计）
--   totalHeal,    -- 总治疗量
--   hotHeal,      -- 持续治疗(HOT)分量
--   takenDamage,  -- 承受伤害
-- }
local buckets = { [0] = { stats = {}, startTime = nil, lastTime = nil } }
local activeKey = 0

-- [累计统计] 每队伍独立的跨场次累计桶：随 record* 同步累加，
-- 不随 BattleStats.reset()（每波清零）清空；仅手动重置或队伍编成变更时清。
local accumBuckets = {}

local function bucket()
    local b = buckets[activeKey]
    if not b then
        b = { stats = {}, startTime = nil, lastTime = nil }
        buckets[activeKey] = b
    end
    return b
end

local function stats()
    return bucket().stats
end

--- [累计统计] 当前挂载队伍的累计桶
local function accumBucket()
    local b = accumBuckets[activeKey]
    if not b then
        b = { stats = {}, startTime = nil, lastTime = nil }
        accumBuckets[activeKey] = b
    end
    return b
end

local function accumStats()
    return accumBucket().stats
end

--- 获取/创建某英雄的统计条目（同时建波次桶与累计桶条目）
local function ensure(heroId, name)
    local s = stats()[heroId]
    if not s then
        s = {
            heroId = heroId, name = name or "?",
            totalDamage = 0, physDamage = 0, magDamage = 0,
            dotDamage = 0, critDamage = 0,
            hitCount = 0, critHitCount = 0, critCount = 0,
            totalHeal = 0, hotHeal = 0,
            takenDamage = 0,
        }
        stats()[heroId] = s
    elseif name and (s.name == "?" or not s.name) then
        s.name = name
    end
    -- [累计统计] 累计桶条目（字段结构与波次桶一致）
    local a = accumStats()[heroId]
    if not a then
        a = {
            heroId = heroId, name = s.name,
            totalDamage = 0, physDamage = 0, magDamage = 0,
            dotDamage = 0, critDamage = 0,
            hitCount = 0, critHitCount = 0, critCount = 0,
            totalHeal = 0, hotHeal = 0,
            takenDamage = 0,
        }
        accumStats()[heroId] = a
    elseif name and (a.name == "?" or not a.name) then
        a.name = name
    end
    return s, a
end

--- 标记一次活动（更新计时窗口，波次桶与累计桶各自计时）
local function touch()
    local now = time.elapsedTime
    local b = bucket()
    if not b.startTime then b.startTime = now end
    b.lastTime = now
    local ab = accumBucket()
    if not ab.startTime then ab.startTime = now end
    ab.lastTime = now
end

--- 切换当前统计桶。0 是主线/默认战斗，多队战斗用各自队伍号。
---@param key number|nil
function BattleStats.mount(key)
    activeKey = tonumber(key) or 0
end

---@return number|nil
function BattleStats.mountedTeam()
    if activeKey > 0 then return activeKey end
    return nil
end

-- ======================== 采集接口 ========================

--- 记录一次普攻/连击输出伤害（己方英雄）
---@param attacker table 攻击者单位（需有 heroId）
---@param amount number 实际造成伤害
---@param category string|nil "physical" | "magical"
---@param isCrit boolean|nil 是否暴击
---@param critEligible boolean|nil 是否参与暴击率（默认 true；斩杀/飞剑/弹射等传 false）
function BattleStats.recordDamage(attacker, amount, category, isCrit, critEligible)
    if not attacker or not attacker.heroId or not amount or amount <= 0 then return end
    local s, a = ensure(attacker.heroId, attacker.name)
    s.totalDamage = s.totalDamage + amount
    a.totalDamage = a.totalDamage + amount
    if category == "magical" then
        s.magDamage = s.magDamage + amount
        a.magDamage = a.magDamage + amount
    else
        s.physDamage = s.physDamage + amount
        a.physDamage = a.physDamage + amount
    end
    s.hitCount = s.hitCount + 1
    a.hitCount = a.hitCount + 1
    if critEligible ~= false then
        s.critHitCount = s.critHitCount + 1
        a.critHitCount = a.critHitCount + 1
        if isCrit then
            s.critCount = s.critCount + 1
            s.critDamage = s.critDamage + amount
            a.critCount = a.critCount + 1
            a.critDamage = a.critDamage + amount
        end
    end
    touch()
end

--- 记录一次持续伤害(DOT)输出，按来源英雄归因
---@param source table|nil 伤害来源单位（需有 heroId）
---@param amount number 实际造成伤害
function BattleStats.recordDotDamage(source, amount)
    if not source or not source.heroId or not amount or amount <= 0 then return end
    local s, a = ensure(source.heroId, source.name)
    s.totalDamage = s.totalDamage + amount
    s.dotDamage   = s.dotDamage + amount
    a.totalDamage = a.totalDamage + amount
    a.dotDamage   = a.dotDamage + amount
    touch()
end

--- 记录一次治疗输出（己方治疗者）
---@param healer table 治疗者单位（需有 heroId）
---@param amount number 实际治疗量
---@param isHot boolean|nil 是否持续治疗(HOT)
function BattleStats.recordHeal(healer, amount, isHot)
    if not healer or not healer.heroId or not amount or amount <= 0 then return end
    local s, a = ensure(healer.heroId, healer.name)
    s.totalHeal = s.totalHeal + amount
    a.totalHeal = a.totalHeal + amount
    if isHot then
        s.hotHeal = s.hotHeal + amount
        a.hotHeal = a.hotHeal + amount
    end
    touch()
end

--- 记录一次承受伤害（己方英雄被打）
---@param target table 受击者单位（需有 heroId）
---@param amount number 实际承受伤害
function BattleStats.recordTaken(target, amount)
    if not target or not target.heroId or not amount or amount <= 0 then return end
    local s, a = ensure(target.heroId, target.name)
    s.takenDamage = s.takenDamage + amount
    a.takenDamage = a.takenDamage + amount
    touch()
end

-- ======================== 生命周期 ========================

--- 清零（每波战斗开始时由 BattleCombat.reset 调用）
--- 注意：只清波次桶，[累计统计] accum 桶不受影响（跨场次保留）
function BattleStats.reset()
    buckets[activeKey] = { stats = {}, startTime = nil, lastTime = nil }
end

--- [累计统计] 重置当前挂载队伍的累计数据（统计面板「重置」按钮调用）
function BattleStats.resetAccum()
    accumBuckets[activeKey] = { stats = {}, startTime = nil, lastTime = nil }
end

--- [累计统计] 重置指定队伍编成的累计数据（队伍变更时由编队回调调用）
--- 队伍号直接对应桶 key；队伍0(主线默认桶)不受编队变更影响，不在此清。
---@param teamIdx number|nil 变更的队伍号；nil 时清所有队伍桶
function BattleStats.resetAccumForTeam(teamIdx)
    if teamIdx == nil then
        accumBuckets = {}
        return
    end
    local key = tonumber(teamIdx) or 0
    accumBuckets[key] = { stats = {}, startTime = nil, lastTime = nil }
end

-- ======================== 查询接口 ========================

--- 战斗有效时长（秒，从首次伤害到最后一次活动）
---@param useAccum? boolean true 时返回累计时长（统计面板累计口径）
---@return number
function BattleStats.getDuration(useAccum)
    local b = useAccum and accumBucket() or bucket()
    if not b.startTime or not b.lastTime then return 0 end
    return math.max(0, b.lastTime - b.startTime)
end

--- 按指定字段降序排序，返回英雄统计列表
---@param sortKey string "totalDamage" | "totalHeal" | "takenDamage"
---@param useAccum? boolean 累计统计 true 时读累计桶（跨场次）
---@return table[] 排序后的统计条目数组
function BattleStats.getSorted(sortKey, useAccum)
    local list = {}
    local src = useAccum and accumStats() or stats()
    for _, s in pairs(src) do
        list[#list + 1] = s
    end
    table.sort(list, function(a, b)
        return (a[sortKey] or 0) > (b[sortKey] or 0)
    end)
    return list
end

--- 求某字段在所有英雄上的总和
---@param field string
---@param useAccum? boolean 累计统计 true 时读累计桶（跨场次）
---@return number
function BattleStats.getTotal(field, useAccum)
    local sum = 0
    local src = useAccum and accumStats() or stats()
    for _, s in pairs(src) do
        sum = sum + (s[field] or 0)
    end
    return sum
end

--- 是否已有任何统计数据
---@param useAccum? boolean 累计统计 true 时看累计桶
---@return boolean
function BattleStats.hasData(useAccum)
    local src = useAccum and accumStats() or stats()
    return next(src) ~= nil
end

--- 构建结算面板的英雄输出列表（与 DamageStatsPanel 伤害页同一数据源）
---@param allies table[] 己方参战单位（用于补齐未输出英雄与 quality）
---@param heroLookup table|nil 如 HeroConfig.HEROES
---@return table[] { heroId, quality, totalDamage }[]
function BattleStats.buildHeroDamageStats(allies, heroLookup)
    local damageByHero = {}
    for _, s in ipairs(BattleStats.getSorted("totalDamage")) do
        damageByHero[s.heroId] = s.totalDamage or 0
    end
    local heroStats = {}
    for _, u in ipairs(allies or {}) do
        if u.heroId then
            local hConf = heroLookup and heroLookup[u.heroId]
            heroStats[#heroStats + 1] = {
                heroId      = u.heroId,
                quality     = hConf and hConf.quality or 1,
                totalDamage = damageByHero[u.heroId] or 0,
            }
        end
    end
    table.sort(heroStats, function(a, b) return a.totalDamage > b.totalDamage end)
    return heroStats
end

return BattleStats
