-- ============================================================================
-- BattleStats - 本次战斗的伤害 / 治疗 / 承伤统计
-- 职责: 采集战斗中每个己方英雄的输出、治疗、承受伤害，供统计面板实时展示
-- 范围: 仅统计「本次战斗」——随 BattleCombat.reset() 每波清零；仅统计己方英雄
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
local stats = {}

local startTime = nil   -- 第一次记录的时间
local lastTime  = nil   -- 最后一次活动的时间（用于排除寻怪等待，DPS 更准确）

--- 获取/创建某英雄的统计条目
local function ensure(heroId, name)
    local s = stats[heroId]
    if not s then
        s = {
            heroId = heroId, name = name or "?",
            totalDamage = 0, physDamage = 0, magDamage = 0,
            dotDamage = 0, critDamage = 0,
            hitCount = 0, critHitCount = 0, critCount = 0,
            totalHeal = 0, hotHeal = 0,
            takenDamage = 0,
        }
        stats[heroId] = s
    elseif name and (s.name == "?" or not s.name) then
        s.name = name
    end
    return s
end

--- 标记一次活动（更新计时窗口）
local function touch()
    local now = time.elapsedTime
    if not startTime then startTime = now end
    lastTime = now
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
    local s = ensure(attacker.heroId, attacker.name)
    s.totalDamage = s.totalDamage + amount
    if category == "magical" then
        s.magDamage = s.magDamage + amount
    else
        s.physDamage = s.physDamage + amount
    end
    s.hitCount = s.hitCount + 1
    if critEligible ~= false then
        s.critHitCount = s.critHitCount + 1
        if isCrit then
            s.critCount = s.critCount + 1
            s.critDamage = s.critDamage + amount
        end
    end
    touch()
end

--- 记录一次持续伤害(DOT)输出，按来源英雄归因
---@param source table|nil 伤害来源单位（需有 heroId）
---@param amount number 实际造成伤害
function BattleStats.recordDotDamage(source, amount)
    if not source or not source.heroId or not amount or amount <= 0 then return end
    local s = ensure(source.heroId, source.name)
    s.totalDamage = s.totalDamage + amount
    s.dotDamage   = s.dotDamage + amount
    touch()
end

--- 记录一次治疗输出（己方治疗者）
---@param healer table 治疗者单位（需有 heroId）
---@param amount number 实际治疗量
---@param isHot boolean|nil 是否持续治疗(HOT)
function BattleStats.recordHeal(healer, amount, isHot)
    if not healer or not healer.heroId or not amount or amount <= 0 then return end
    local s = ensure(healer.heroId, healer.name)
    s.totalHeal = s.totalHeal + amount
    if isHot then
        s.hotHeal = s.hotHeal + amount
    end
    touch()
end

--- 记录一次承受伤害（己方英雄被打）
---@param target table 受击者单位（需有 heroId）
---@param amount number 实际承受伤害
function BattleStats.recordTaken(target, amount)
    if not target or not target.heroId or not amount or amount <= 0 then return end
    local s = ensure(target.heroId, target.name)
    s.takenDamage = s.takenDamage + amount
    touch()
end

-- ======================== 生命周期 ========================

--- 清零（每波战斗开始时由 BattleCombat.reset 调用）
function BattleStats.reset()
    stats = {}
    startTime = nil
    lastTime  = nil
end

-- ======================== 查询接口 ========================

--- 战斗有效时长（秒，从首次伤害到最后一次活动）
---@return number
function BattleStats.getDuration()
    if not startTime or not lastTime then return 0 end
    return math.max(0, lastTime - startTime)
end

--- 按指定字段降序排序，返回英雄统计列表
---@param sortKey string "totalDamage" | "totalHeal" | "takenDamage"
---@return table[] 排序后的统计条目数组
function BattleStats.getSorted(sortKey)
    local list = {}
    for _, s in pairs(stats) do
        list[#list + 1] = s
    end
    table.sort(list, function(a, b)
        return (a[sortKey] or 0) > (b[sortKey] or 0)
    end)
    return list
end

--- 求某字段在所有英雄上的总和
---@param field string
---@return number
function BattleStats.getTotal(field)
    local sum = 0
    for _, s in pairs(stats) do
        sum = sum + (s[field] or 0)
    end
    return sum
end

--- 是否已有任何统计数据
---@return boolean
function BattleStats.hasData()
    return next(stats) ~= nil
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
