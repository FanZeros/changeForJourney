-- ============================================================================
-- AwakeningGrowth - 觉醒1「永久成长层」配置驱动模块
-- ----------------------------------------------------------------------------
-- 目标：把 ExtraTalentSystem.onEnemyDeath 里的 `if heroId == N then bump()`
--       硬编码叠层链、以及 bruteEntries 的 `if heroId == N` 属性映射链，
--       抽成「数据表 + 执行器」，方便后续按角色调整触发口径/成长曲线。
--
-- 既有角色保留原成长口径；#17 蓝色大肥鱼补齐任意击杀 stacks+1→魔攻+0.2。
-- 后续成长调整通过修改本表的 cond / fields / cap / curve 实现，
--    不再回到 ExtraTalentSystem 里写 if heroId == N。
--
-- 两块数据：
--   AG.RULES[heroId]    → 击杀时如何叠层（触发条件 cond + 要加的字段 fields）
--   AG.ATTR_MAP[heroId] → 叠好的字段如何换算成永久属性（旧 bruteEntries）
--
-- 机制类追加技（觉醒2/3 的 biteTypes / iceStatues / preciseStored 等带专属
-- 条件或副作用的分支）仍留在 ExtraTalentSystem.onEnemyDeath 的 n4/n7 分支，
-- 因为它们是英雄特有玩法、不产生「线性 flat 永久属性」。
-- ============================================================================

local AD = require("systems.AttributeDef")

local AG = {}

-- ======================== 触发条件（数据驱动） ========================
-- 每个条件接收 ctx = { deadEnemy, killer, enemies, hasStatus }，返回 boolean。
-- ctx.hasStatus(unit, statusKey) 由调用方注入（避免本模块耦合 StatusEffectManager）。
-- 新增口径（方案1）只需在此登记一个谓词，再在 RULES 里引用其 key。
AG.CONDITIONS = {
    --- 任意击杀
    any       = function(_) return true end,
    --- 击杀处于燃烧状态的敌人
    burning   = function(c) return c.hasStatus(c.deadEnemy, "burning") end,
    --- 击杀处于感电状态的敌人
    shocked   = function(c) return c.hasStatus(c.deadEnemy, "shocked") end,
    --- 击杀被标记的敌人
    marked    = function(c) return c.hasStatus(c.deadEnemy, "marked") end,
    --- 氮气冲刺击杀（#21 雷电麦坤）
    nitroKill = function(c) return c.killer ~= nil and c.killer._nitroKill == true end,
    --- 暴击击杀（#14 内鬼 / #18 老六）——死亡敌人身上由击杀归因写 _killedByCrit
    critKill  = function(c) return c.deadEnemy ~= nil and c.deadEnemy._killedByCrit == true end,
    --- 通宵斩击杀（#11 熬夜冠军）——死亡敌人身上写 _killedByNightSlash（精确一次性，
    ---   不读 attacker._nightSlashKill 粘性标记，否则首次通宵斩后任意击杀都会误算）
    nightSlashKill = function(c) return c.deadEnemy ~= nil and c.deadEnemy._killedByNightSlash == true end,
    --- 弹射击杀（#13 弹弹弹）——死亡敌人身上由 dealDamageToUnit 写 _killedByRicochet
    ricochetKill   = function(c) return c.deadEnemy ~= nil and c.deadEnemy._killedByRicochet == true end,
}

-- ======================== 击杀叠层规则（觉醒1） ========================
-- cond   : AG.CONDITIONS 的 key，省略 = "any"
-- fields : { {字段名, 每次增量, 上限?}, ... }，上限省略 = 无上限（永久层）
-- 只有已点觉醒1（n1）时才会调用 applyGrowth，故此处不再判 n1。
AG.RULES = {
    [1]  = { cond = "any",       fields = { { "stacks", 1 } } },
    [2]  = { cond = "burning",   fields = { { "burnKills", 1 }, { "stacks", 1 } } },
    [3]  = { cond = "any",       fields = { { "stacks", 1 } } },
    [4]  = { cond = "any",       fields = { { "stacks", 1 } } },
    [5]  = { cond = "any",       fields = { { "stacks", 1 } } },
    [6]  = { cond = "shocked",   fields = { { "shockKills", 1 }, { "stacks", 1 } } },
    [7]  = { cond = "any",       fields = { { "stacks", 1 } } },
    -- #8 愤怒的小雀（杠杆②）：标记击杀 ×2（原 ×1，已有门槛，提倍率补偿）
    [8]  = { cond = "marked",    fields = { { "stacks", 2 } } },
    -- #11 熬夜冠军（杠杆②）：通宵斩击杀 ×2（原任意击杀 ×1）
    [11] = { cond = "nightSlashKill", fields = { { "stacks", 2 } } },
    [12] = { cond = "any",       fields = { { "stacks", 1 } } },
    -- #13 弹弹弹（杠杆②）：弹射击杀 ×2（原任意击杀 ×1）
    [13] = { cond = "ricochetKill",   fields = { { "stacks", 2 } } },
    -- #14 内鬼（杠杆②）：暴击击杀 ×2（原任意击杀 ×1）
    [14] = { cond = "critKill",  fields = { { "stacks", 2 } } },
    [16] = { cond = "any",       fields = { { "swordStacks", 1 }, { "stacks", 1 } } },
    [17] = { cond = "any",       fields = { { "stacks", 1 } } },
    -- #18 老六（杠杆②）：暴击击杀 ×2（原任意击杀 ×1）
    [18] = { cond = "critKill",  fields = { { "stacks", 2 } } },
    [19] = { cond = "any",       fields = { { "stacks", 1 } } },
    [20] = { cond = "any",       fields = { { "gateStacks", 1 }, { "stacks", 1 } } },
    [21] = { cond = "nitroKill", fields = { { "nitroKills", 1 }, { "stacks", 1 } } },
    [22] = { cond = "any",       fields = { { "gatlingKills", 1 }, { "stacks", 1 } } },
    [24] = { cond = "any",       fields = { { "stacks", 1 } } },
    [25] = { cond = "any",       fields = { { "stacks", 1 } } },
}

-- ======================== 永久属性映射（旧 bruteEntries） ========================
-- 每条：{ field=源字段, key=属性key, mult=每层系数, curve?=(flat,value)->flat }
-- 只有 field 值 > 0 才生成条目（与旧 `data.xxx > 0` 守卫一致）。
-- 注意：#9/#10/#15/#23 的成长字段由「非击杀」钩子累积
--       (onOverflowHeal / onShareFatal / onSuccessfulRevive)，故不在 RULES 内，
--       但它们的属性映射仍在这里。
--       #16/#20/#21/#22 的专长字段走 getSwordCoeffBonus 等系数接口，不进本表；
--       它们被叠的 stacks 目前无属性映射（沿用旧行为的冗余计数）。
AG.ATTR_MAP = {
    [1]  = { { field = "stacks",        key = AD.MAX_HP,          mult = 1    } },
    [2]  = { { field = "burnKills",     key = AD.MAG_ATK,         mult = 0.2  } },
    [3]  = { { field = "stacks",        key = AD.PHYS_ATK,        mult = 0.2  } },
    [4]  = { { field = "stacks",        key = AD.MAX_HP,          mult = 0.5  } },
    [5]  = { { field = "stacks",        key = AD.ARMOR,           mult = 0.2  } },
    [6]  = { { field = "shockKills",    key = AD.MAG_ATK,         mult = 0.2  } },
    [7]  = { { field = "stacks",        key = AD.COMBO_RATE,      mult = 0.1  } },
    [8]  = { { field = "stacks",        key = AD.DMG_BONUS,       mult = 0.15 } },
    [9]  = { { field = "overflowCount", key = AD.SPI,             mult = 0.05 } },
    [10] = { { field = "shareCount",    key = AD.MAX_HP,          mult = 3    } },
    [11] = { { field = "stacks",        key = AD.PHYS_ATK,        mult = 0.3  } },
    [12] = { { field = "stacks",        key = AD.MAG_ATK,         mult = 0.2  } },
    [13] = { { field = "stacks",        key = AD.PHYS_ATK,        mult = 0.25 } },
    [14] = {
        { field = "stacks", key = AD.PHYS_ATK_BONUS, mult = 0.1 },
        { field = "stacks", key = AD.MAG_ATK_BONUS,  mult = 0.1 },
    },
    [15] = { { field = "stacks",        key = AD.MAX_HP,          mult = 2    } },
    [17] = { { field = "stacks",        key = AD.MAG_ATK,         mult = 0.2  } },
    [18] = { { field = "stacks",        key = AD.CRIT_RATE,       mult = 0.1  } },
    [19] = { { field = "stacks",        key = AD.SPI,             mult = 0.05 } },
    [23] = { { field = "shieldStacks",  key = AD.ENERGY_SHIELD,   mult = 1    } },
    [24] = { { field = "stacks",        key = AD.MAX_HP,          mult = 1    } },
    [25] = { { field = "stacks",        key = AD.PHYS_ATK,        mult = 0.3  } },
}

-- ======================== 执行器 ========================

--- 按配置叠一次觉醒1成长层（调用方保证已点 n1）。
---@param heroId number
---@param extra table 归一化后的追加技存档表（就地修改；结构见 systems.ExtraTalentSystem 的 ExtraTalentData）
---@param ctx table { deadEnemy, killer, enemies, hasStatus }
---@return boolean applied 是否命中触发条件并叠层
function AG.applyGrowth(heroId, extra, ctx)
    local rule = AG.RULES[heroId]
    if not rule or not extra then return false end
    local cond = AG.CONDITIONS[rule.cond] or AG.CONDITIONS.any
    if not cond(ctx or {}) then return false end
    for _, f in ipairs(rule.fields) do
        local name, inc, cap = f[1], (f[2] or 1), f[3]
        local cur = tonumber(extra[name]) or 0
        local nv = cur + inc
        if cap then nv = math.min(cap, nv) end
        extra[name] = nv
    end
    return true
end

--- 把已叠的成长字段换算成永久属性 modifier 条目（等价旧 bruteEntries）。
---@param heroId number
---@param data table 结构见 systems.ExtraTalentSystem 的 ExtraTalentData
---@return table[] entries { { key=..., flat=... }, ... }
function AG.buildAttrEntries(heroId, data)
    local entries = {}
    local map = AG.ATTR_MAP[heroId]
    if not map or not data then return entries end
    for _, e in ipairs(map) do
        local v = tonumber(data[e.field]) or 0
        if v > 0 then
            local flat = v * e.mult
            if e.curve then flat = e.curve(flat, v) end
            entries[#entries + 1] = { key = e.key, flat = flat }
        end
    end
    return entries
end

--- 是否有该英雄的击杀叠层规则（供外部判定/调试）
---@param heroId number
---@return boolean
function AG.hasRule(heroId)
    return AG.RULES[heroId] ~= nil
end

return AG
