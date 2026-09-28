-- ============================================================================
-- BossAffixConfig.lua — Boss 专属词缀配置（v2.64，双端共享）
--
-- 目的：困难(Hard)及以上难度的章节 Boss 获得专属强化词缀，与 Normal 拉开
--       真正的机制差异（此前 Hard+ Boss 仅是 monsterLevel 数值缩放、纯复用）。
--
-- 设计原则：
--   * 只作用于章节 Boss（unit.isBoss，每章 stage5 首通唯一），不碰小怪。
--   * 全部用**百分比参数**（相对 Boss 自身属性），自动适配任意 monsterLevel，
--     无需按等级分表，也不会像 flat 值那样在高 ml 失效。
--   * 难度越高 → 词缀数量越多 + 数值越强（tier 1..14 梯度）。
--   * **确定性分配**：按 chapter 从固定词缀池连续取，同章同词缀可复现、可测试，
--     不用随机（保证 battle-lab 采样与玩家体验一致）。
--
-- 词缀类型（type）：
--   static  —— 出场时一次性改属性（护盾/生命/攻速）
--   enrage  —— 动态阶段：血量低于阈值触发攻速+伤害强化（tick 检测，一次性）
--   regen   —— 动态持续：每秒回血（tick）
--   thorns  —— 受击钩子：反弹所受伤害给攻击者（onBossDamaged）
-- ============================================================================

local BossAffixConfig = {}

--- 难度 → tier（0=Normal 无 Boss 词缀；1..14 递增）
BossAffixConfig.DIFF_TIER = {
    hard          = 1,
    nightmare     = 2,
    hell          = 3,
    purgatory     = 4,
    torment       = 5,
    torment2      = 6,
    torment3      = 7,
    torment4      = 8,
    torment5      = 9,
    annihilation  = 10,
    annihilation2 = 11,
    annihilation3 = 12,
    annihilation4 = 13,
    annihilation5 = 14,
}

--- tier → 词缀数量
---@param tier number
---@return number
function BossAffixConfig.getCountForTier(tier)
    if tier <= 0 then return 0 end
    if tier <= 2 then return 1 end   -- Hard / Nightmare：1 个
    if tier <= 5 then return 2 end   -- Hell / Purgatory / Torment：2 个
    return 3                          -- Torment2+ / 全湮灭：3 个
end

--- 词缀池（固定顺序，选取时按 chapter 起点连续取 count 个不重复）
BossAffixConfig.POOL_ORDER = {
    "warden_shield", "enrage", "fortify", "thorns", "haste", "regen",
}

-- ============================================================================
-- 词缀定义
--   base    : tier=1 时的基准参数值
--   perTier : 每提升 1 tier 的增量
--   cap     : 参数上限（防止高 tier 数值失控）
--   desc    : string.format 模板（%d 百分比 / %.1f 等，由 params 填充）
-- ============================================================================

---@type table<string, table>
BossAffixConfig.AFFIXES = {
    -- 守护壁垒：出场获得基于最大生命的能量护盾
    warden_shield = {
        name = "守护壁垒", type = "static",
        base = { shieldPct = 0.20 }, perTier = { shieldPct = 0.02 }, cap = { shieldPct = 0.60 },
        desc = "Boss 开场获得最大生命 %d%% 的护盾",
    },
    -- 强韧：最大生命提升
    fortify = {
        name = "强韧", type = "static",
        base = { hpPct = 0.15 }, perTier = { hpPct = 0.025 }, cap = { hpPct = 0.70 },
        desc = "Boss 最大生命 +%d%%",
    },
    -- 迅捷：攻击速度提升
    haste = {
        name = "迅捷", type = "static",
        base = { atkSpeedPct = 0.20 }, perTier = { atkSpeedPct = 0.02 }, cap = { atkSpeedPct = 0.60 },
        desc = "Boss 攻击速度 +%d%%",
    },
    -- 暴怒：血量低于阈值时攻速+伤害强化（阶段机制）
    enrage = {
        name = "暴怒", type = "enrage",
        base = { threshold = 0.40, atkSpeedPct = 0.30, dmgPct = 0.25 },
        perTier = { threshold = 0, atkSpeedPct = 0.03, dmgPct = 0.03 },
        cap = { threshold = 0.60, atkSpeedPct = 0.80, dmgPct = 0.80 },
        desc = "Boss 生命低于 %d%% 时攻速 +%d%%、伤害 +%d%%",
    },
    -- 再生：每秒回血
    regen = {
        name = "再生", type = "regen",
        base = { hpPctPerSec = 0.005 }, perTier = { hpPctPerSec = 0.0006 }, cap = { hpPctPerSec = 0.015 },
        desc = "Boss 每秒回复最大生命 %.1f%%",
    },
    -- 荆棘之体：受击反弹伤害
    thorns = {
        name = "荆棘之体", type = "thorns",
        base = { reflectPct = 0.10 }, perTier = { reflectPct = 0.012 }, cap = { reflectPct = 0.40 },
        desc = "攻击 Boss 时受到其 %d%% 伤害的反弹",
    },
}

--- 按 tier 缩放单个参数：base + perTier*(tier-1)，clamp 到 cap
---@param def table 词缀定义
---@param tier number
---@return table params
local function computeParams(def, tier)
    local params = {}
    for key, baseVal in pairs(def.base) do
        local per = (def.perTier and def.perTier[key]) or 0
        local capVal = (def.cap and def.cap[key]) or math.huge
        local v = baseVal + per * (tier - 1)
        if v > capVal then v = capVal end
        params[key] = v
    end
    return params
end

local function pct(v)
    return math.floor((tonumber(v) or 0) * 100 + 0.5)
end

--- 生成词缀的简短描述（带实际数值，UI 展示用）
---@param id string
---@param params table
---@return string
function BossAffixConfig.formatShortDesc(id, params)
    local p = params or {}
    if id == "warden_shield" then
        return "护盾 " .. pct(p.shieldPct) .. "%生命"
    elseif id == "fortify" then
        return "生命 +" .. pct(p.hpPct) .. "%"
    elseif id == "haste" then
        return "攻速 +" .. pct(p.atkSpeedPct) .. "%"
    elseif id == "enrage" then
        return "<" .. pct(p.threshold) .. "%血 攻速+" .. pct(p.atkSpeedPct)
            .. "% 伤害+" .. pct(p.dmgPct) .. "%"
    elseif id == "regen" then
        return "每秒回 " .. string.format("%.1f", (p.hpPctPerSec or 0) * 100) .. "%生命"
    elseif id == "thorns" then
        return "反弹 " .. pct(p.reflectPct) .. "%伤害"
    end
    return id
end

--- 生成词缀的完整描述（带实际数值）
---@param id string
---@param params table
---@return string
function BossAffixConfig.formatDesc(id, params)
    local def = BossAffixConfig.AFFIXES[id]
    if not def then return id end
    local p = params or {}
    if id == "enrage" then
        return string.format(def.desc, pct(p.threshold), pct(p.atkSpeedPct), pct(p.dmgPct))
    elseif id == "regen" then
        return string.format(def.desc, (p.hpPctPerSec or 0) * 100)
    elseif id == "warden_shield" then
        return string.format(def.desc, pct(p.shieldPct))
    elseif id == "fortify" then
        return string.format(def.desc, pct(p.hpPct))
    elseif id == "haste" then
        return string.format(def.desc, pct(p.atkSpeedPct))
    elseif id == "thorns" then
        return string.format(def.desc, pct(p.reflectPct))
    end
    return def.desc
end

--- 按 chapter 从池中确定性连续取 count 个词缀 ID（不重复）
---@param chapter number
---@param count number
---@return string[]
function BossAffixConfig.pickAffixIds(chapter, count)
    local pool = BossAffixConfig.POOL_ORDER
    local n = #pool
    local result = {}
    if count <= 0 or n == 0 then return result end
    if count > n then count = n end
    local startIdx = ((chapter - 1) % n) + 1
    for i = 0, count - 1 do
        local idx = ((startIdx - 1 + i) % n) + 1
        result[#result + 1] = pool[idx]
    end
    return result
end

--- 获取某关卡 Boss 的词缀列表（含最终 params 与展示文案）
---@param chapter number 全局章节号（1..345）
---@param difficulty string 难度字符串（SC.getDifficulty 返回值）
---@return table[]|nil affixes 空则返回 nil（Normal 或无词缀）
function BossAffixConfig.getAffixesForBoss(chapter, difficulty)
    local tier = BossAffixConfig.DIFF_TIER[difficulty] or 0
    if tier <= 0 then return nil end
    local count = BossAffixConfig.getCountForTier(tier)
    if count <= 0 then return nil end
    local ids = BossAffixConfig.pickAffixIds(chapter, count)
    local result = {}
    for _, id in ipairs(ids) do
        local def = BossAffixConfig.AFFIXES[id]
        if def then
            local params = computeParams(def, tier)
            result[#result + 1] = {
                id = id,
                name = def.name,
                type = def.type,
                tier = tier,
                params = params,
                shortDesc = BossAffixConfig.formatShortDesc(id, params),
                desc = BossAffixConfig.formatDesc(id, params),
            }
        end
    end
    return #result > 0 and result or nil
end

return BossAffixConfig
