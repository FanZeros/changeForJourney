-- ============================================================================
-- CombatPower - 按真实属性消费计价的共用战力入口。
-- attrs 已完成六围、装备、常规/最终乘区派生；这里不重算、不修改单位或存档。
-- 沿用 AttributeDef.valueModel，不作战斗模拟，也不补接未启用的职业能力。
-- ============================================================================

local AD = require("systems.AttributeDef")
local CF = require("systems.CombatFormula")
local AC = require("config.AwakeningConfig")
local HC = require("config.HeroConfig")
local CC = require("config.ClassConfig")
local ESC = require("config.EquipmentSetConfig")

local M = {}

---@class EffectivePowerUnit
---@field heroId number|string|nil
---@field attrs table
---@field awakeningNodes table|nil
---@field awakening table|nil
---@field advTalentIds string[]|nil
---@field classId string|nil
---@field dmgMainType string|nil
---@field artifactEffects table[]|nil
---@field partySlot number|nil
---@field teamIdx number|nil
---@field _etsDisabled boolean|nil

---@class EffectivePowerContext
---@field teamUnits EffectivePowerUnit[]|nil 仅该英雄真实所属队，不是活动队或全部名册
---@field talentsData table|nil 包含 litNodes
---@field heroesData table|nil 包含 roster
---@field equipmentData table|nil 属性已由调用方应用
---@field artifactsData table|nil 神器属性已由调用方应用

local function finite(value, fallback)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then
        return fallback or 0
    end
    return n
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function unitValue(key)
    local meta = AD.META[key]
    if not meta then return 0 end
    local weight = finite(meta.valueModel)
    return meta.dataType == AD.TYPE_PCT and weight / 100 or weight
end

---@param attrs table|nil
---@param key string
---@return number
local function read(attrs, key)
    if not attrs then return 0 end
    if type(attrs.get) == "function" then return finite(attrs:get(key)) end
    return finite(attrs.final and attrs.final[key])
end

local function uncapped(attrs, key)
    if type(attrs.getUncapped) == "function" then
        return finite(attrs:getUncapped(key))
    end
    if attrs._uncapped and attrs._uncapped[key] ~= nil then
        return finite(attrs._uncapped[key])
    end
    return read(attrs, key)
end

---@param unit EffectivePowerUnit
local function definition(unit)
    local id = tonumber(unit.heroId)
    return id and HC.get(id) or nil
end

---@param unit EffectivePowerUnit
local function category(unit)
    -- 老六 #18 的静态 dmgMainType 误标物理，普攻实际是暗影魔法。
    return AD.getAtkCategory(unit.attrs and unit.attrs.atkType)
end

---@param unit EffectivePowerUnit
---@param context EffectivePowerContext
local function owned(unit, context)
    local roster = context.heroesData and context.heroesData.roster or {}
    return roster[tonumber(unit.heroId)] or roster[tostring(unit.heroId)] or {}
end

---@param unit EffectivePowerUnit
---@param context EffectivePowerContext
local function awakening(unit, context)
    return unit.awakeningNodes or unit.awakening or owned(unit, context).awakening
end

---@param unit EffectivePowerUnit
---@param stage number
---@param context EffectivePowerContext
local function hasStage(unit, stage, context)
    return AC.hasStage(awakening(unit, context), stage)
end

---@param unit EffectivePowerUnit
---@param talentId string
local function hasGate(unit, talentId)
    for _, id in ipairs(unit.advTalentIds or {}) do
        if id == talentId then return true end
    end
    return false
end

---@param unit EffectivePowerUnit
local function staticDamageType(unit)
    local def = definition(unit)
    return unit.dmgMainType or (def and def.dmgMainType)
end

---@param unit EffectivePowerUnit
local function classId(unit)
    local def = definition(unit)
    return CC.normalize(unit.classId or (def and def.classId))
end

---@param unit EffectivePowerUnit
local function setFour(unit)
    return unit.attrs and unit.attrs._setFour
end

---@param unit EffectivePowerUnit
local function setSix(unit)
    local id = unit.attrs and unit.attrs._setSix
    return id and ESC.SETS[id] and id or nil
end

---@param hero EffectivePowerUnit
---@param context EffectivePowerContext
---@return EffectivePowerUnit[]
local function teamFor(hero, context)
    local team = {}
    local found = false
    for _, unit in ipairs(context.teamUnits or {}) do
        if unit and unit.attrs then
            -- 候选装备的 hero 是本次估值的权威实例，不能沿用队伍里的旧本人。
            if unit == hero or (tonumber(hero.heroId) and tonumber(unit.heroId) == tonumber(hero.heroId)) then
                if not found then team[#team + 1] = hero end
                found = true
            else
                team[#team + 1] = unit
            end
        end
    end
    if not found then team[#team + 1] = hero end
    return team
end

-- 字段矩阵的零贡献部分：六围及其最终加成已派生；常规/最终目标加成已入 attrs。
-- hp/resistance/dropLuck 是运行时/探索/派生值；threat 非单调，不作战力。
-- 其余字段仅在下方的防御、输出、治疗、真实副通道中读取，不做兜底加和。
local DEFENSE_KEYS = { AD.MAX_HP, AD.ARMOR, AD.ENERGY_SHIELD, AD.DODGE }

---@param attrs table
---@param rateKey string
---@param ratioKey string
local function blockPower(attrs, rateKey, ratioKey)
    if attrs.artifactChaosDefenseDisabled then return 0 end
    -- 与 MAS.getEffectiveBlockRate 一致：实战读截断前概率，支持多重格挡。
    -- 神器显式扩大/限定概率上限；无神器时不擅自把实际多重格挡截到 100。
    local rate = math.max(0, uncapped(attrs, rateKey))
    if attrs.artifactBlockCap and rate > 100 then
        rate = math.min(rate, math.max(100, finite(attrs.artifactBlockCap, 100)))
    end
    local ratio = clamp(read(attrs, ratioKey), 0, 80) / 100
    if rate <= 0 or ratio <= 0 then return 0 end
    local count = math.floor(rate / 100)
    local chance = rate / 100 - count
    local expectedReduction = 1 - (1 - ratio) ^ count * (1 - chance * ratio)
    -- 默认 60% 比例时保留原格挡权值；ratio 本身 VM=0，但必须改变有效概率贡献。
    local defaultRatio = math.max(0.01, AD.getDefault(ratioKey) / 100)
    return expectedReduction / defaultRatio * unitValue(rateKey) * 100
end

-- 暴率/暴伤都是加法合并后再吃神器倍率。合并量用统一通用权值，避免
-- 已满暴率时增加另一来源改变组成占比，造成无效词条仍改变分数。
---@param attrs table
---@param cat string
---@return number power
---@return number probability
---@return number critMult
---@return number rawRate
local function critPower(attrs, cat, extraRate)
    local rate = read(attrs, AD.CRIT_RATE) + (extraRate or 0)
    local damage = read(attrs, AD.CRIT_DMG)
    if cat == "healing" then
        rate = read(attrs, AD.HEAL_CRIT_RATE)
        damage = read(attrs, AD.HEAL_CRIT_DMG)
    elseif cat == "physical" then
        rate = rate + read(attrs, AD.PHYS_CRIT_RATE)
        damage = damage + read(attrs, AD.PHYS_CRIT_DMG)
    else
        rate = rate + read(attrs, AD.MAG_CRIT_RATE)
        damage = damage + read(attrs, AD.MAG_CRIT_DMG)
    end
    if cat ~= "healing" then
        rate = rate * finite(attrs.artifactCritRateMult, 1)
        damage = damage * finite(attrs.artifactCritDmgMult, 1)
    end
    local rawRate = math.max(0, rate)
    if cat ~= "healing" then
        rate, damage = CF.applyCritOverflow(rawRate, damage, attrs)
    end
    local probability = clamp(rate, 0, 100) / 100
    local rateKey = cat == "healing" and AD.HEAL_CRIT_RATE or AD.CRIT_RATE
    local damageKey = cat == "healing" and AD.HEAL_CRIT_DMG or AD.CRIT_DMG
    -- CD=100 与不暴击等效；CD<100 的暴击会降低伤害，而不是奖励有害暴率。
    -- 没有暴击概率时，整项为零（不计默认200%暴伤）。
    local excess = damage - 100
    local power = probability * excess * (unitValue(rateKey) + unitValue(damageKey))
    return power, probability, damage / 100, rawRate
end

---@param unit EffectivePowerUnit
---@param cat string
local function primaryCritPower(unit, cat)
    local attrs = unit.attrs
    local power, probability, multiplier, rawRate = critPower(attrs, cat)
    local id = tonumber(unit.heroId)
    local mods = attrs.modifiers or {}
    if id == 3 and cat == "physical" and not mods.talent_precise then
        -- 每第三刀实际挂PHYS_CRIT_RATE+100；不是所有攻击都强制暴击。
        local forcedPower, forcedProbability = critPower(attrs, cat, 100)
        return power * (2 / 3) + forcedPower / 3,
            probability * (2 / 3) + forcedProbability / 3, multiplier, rawRate
    elseif id == 18 and cat == "magical" and not mods.laoliu_first_crit then
        -- 开战第一击确实+100泛暴率；以一次机制的暴伤消费份额补偿，
        -- 不猜战斗时长/首击占比，也不把首击当持续必暴。运行时已有modifier不重加。
        local forcedPower, forcedProbability = critPower(attrs, cat, 100)
        local fullWeight = unitValue(AD.CRIT_RATE) + unitValue(AD.CRIT_DMG)
        local damageShare = fullWeight > 0 and unitValue(AD.CRIT_DMG) / fullWeight or 0
        return power + (forcedPower - power) * damageShare,
            math.max(probability, forcedProbability), multiplier, rawRate
    end
    return power, probability, multiplier, rawRate
end

local function comboMoments(rate)
    local expected = math.max(0, rate) / 100
    local count = math.floor(expected)
    local chance = expected - count
    local triangular = count * (count + 1) / 2 + chance * (count + 1)
    return expected, triangular
end

---@param attrs table
local function comboContribution(rate, damage)
    local expected, triangular = comboMoments(rate)
    -- sum(i=1..N)(1+D*i/100) = E[N]+D/100*E[N(N+1)/2]。
    -- rate 不封顶100；无连击时 triangular=0，孤立连伤不贡献。
    return expected * unitValue(AD.COMBO_RATE) * 100
        + damage * triangular * unitValue(AD.COMBO_DMG_UP)
end

---@param unit EffectivePowerUnit
---@param context EffectivePowerContext
local function comboPower(unit, context)
    local attrs = unit.attrs
    local rate, damage = read(attrs, AD.COMBO_RATE), read(attrs, AD.COMBO_DMG_UP)
    if tonumber(unit.heroId) == 7 and hasStage(unit, 3, context) then
        local mods = attrs.modifiers or {}
        if not mods.talent_flash and not mods.awaken_flash7_boost and not mods.awaken_flash_exclusive then
            -- 信光机兵III只有蓄力轮+300%连击，其他轮-999%。计实际4/5轮周期，
            -- 不把临时连击当永久词条；也不重复加已经挂在运行时attrs里的修改器。
            local cycle = hasStage(unit, 1, context) and 4 or 5
            return (comboContribution(rate - 999, damage) * (cycle - 1)
                + comboContribution(rate + 300, damage + 30)) / cycle
        end
    end
    return comboContribution(rate, damage)
end

---@param unit EffectivePowerUnit
local function attackInterval(unit)
    if type(unit.attrs.getActualInterval) == "function" then
        return math.max(0.05, finite(unit.attrs:getActualInterval(), 0.05))
    end
    local base = math.max(0.05, finite(read(unit.attrs, AD.ATK_INTERVAL), 1))
    local denominator = math.max(0.01, 1 + read(unit.attrs, AD.ATK_SPEED) / 100)
    return math.max(0.05, base / denominator)
end

---@param unit EffectivePowerUnit
local function frequencyPower(unit)
    local def = definition(unit)
    local reference = def and finite(def.atkInterval, 1) or 1
    reference = math.max(0.05, reference)
    -- 参考间隔不可随候选变化；攻速、装备间隔、神器减速只计一次实际节奏。
    return (reference / attackInterval(unit) - 1) * unitValue(AD.ATK_SPEED) * 100
end

---@param attrs table
---@param cat string
local function damageStatsPower(attrs, cat)
    local chaos = attrs.artifactChaosDamageMult ~= nil
    local bonus = read(attrs, AD.DMG_BONUS)
    local pen = 0
    if chaos then
        bonus = bonus + read(attrs, AD.PHYS_DMG_BONUS) + read(attrs, AD.MAG_DMG_BONUS)
        pen = read(attrs, AD.PHYS_PEN) + read(attrs, AD.MAG_PEN)
    elseif cat == "physical" then
        bonus = bonus + read(attrs, AD.PHYS_DMG_BONUS)
        pen = read(attrs, AD.PHYS_PEN)
    else
        bonus = bonus + read(attrs, AD.MAG_DMG_BONUS)
        pen = read(attrs, AD.MAG_PEN)
    end
    local result = bonus * unitValue(AD.DMG_BONUS)
        + pen * unitValue(cat == "physical" and AD.PHYS_PEN or AD.MAG_PEN)
        + read(attrs, AD.FINAL_DAMAGE_BONUS) * unitValue(AD.FINAL_DAMAGE_BONUS)
    if not chaos then
        result = result
            + read(attrs, AD.ADVANTAGE_DMG_BONUS) * unitValue(AD.ADVANTAGE_DMG_BONUS)
            + read(attrs, AD.DISADVANTAGE_DMG_BONUS) * unitValue(AD.DISADVANTAGE_DMG_BONUS)
    end
    return result
end

---@param unit EffectivePowerUnit
---@param context EffectivePowerContext
local function holyOutput(unit, context)
    return category(unit) == "healing" and read(unit.attrs, AD.HEAL_AMOUNT) > 0
        and 1 + read(unit.attrs, AD.HEAL_BONUS) / 100 > 0
end

---@param unit EffectivePowerUnit
---@param context EffectivePowerContext
local function damageOutput(unit, context)
    local cat = category(unit)
    if cat ~= "healing" then
        local key = cat == "physical" and AD.PHYS_ATK or AD.MAG_ATK
        if read(unit.attrs, key) > 0 then return true end
    end
    if tonumber(unit.heroId) == 17 and read(unit.attrs, AD.MAG_ATK) > 0 then return true end
    if setSix(unit) == "starless" and read(unit.attrs, AD.MAG_ATK) > 0 then return true end
    if tonumber(unit.heroId) == 15 and not unit._etsDisabled
        and hasStage(unit, 3, context) and read(unit.attrs, AD.MAG_ATK) > 0 then
        local extra = owned(unit, context).extraTalent or {}
        if finite(extra.issuedCards) > 0 then return true end
    end
    return false
end

---@param hero EffectivePowerUnit
---@param team EffectivePowerUnit[]
---@param context EffectivePowerContext
local function shieldAvailable(hero, team, context)
    local attrs = hero.attrs
    if read(attrs, AD.ENERGY_SHIELD) > 0
        or finite(attrs.energyShield) > 0 or finite(attrs.tempEnergyShield) > 0 then return true end
    -- last_rite4 的实际实现可把过量治疗直接加到无盾目标；Elwyn与124
    -- 则要求目标原有护盾上限，不能替无盾英雄凭空解锁盾减伤。
    for _, healer in ipairs(team) do
        if holyOutput(healer, context) and setFour(healer) == "last_rite" then return true end
    end
    return false
end

---@param hero EffectivePowerUnit
---@param context EffectivePowerContext
local function counterCoefficient(hero, context)
    if hero.artifactEffects then
        local coefficient = 0
        for _, effect in ipairs(hero.artifactEffects) do
            if effect.effectType == "counter_attack" then
                coefficient = coefficient + math.max(0, finite(effect.value)) / 100 * 0.5
            end
        end
        return coefficient
    end
    -- 兼容只带神器存档的调用方；不猜活动队、不把邻位神器当本人反击。
    local data = context.artifactsData
    local slot, team = tonumber(hero.partySlot), tonumber(hero.teamIdx)
    if not data or not slot or not team or slot < 1 or slot > 4 or team < 1 or team > 3 then return 0 end
    local Schema = require("shared.artifact.ArtifactSchema")
    local Defs = require("shared.artifact.ArtifactDefs")
    local coefficient = 0
    for subSlot = 1, Schema.SUB_SLOT_COUNT do
        local id = Schema.getEquippedId(data, slot, subSlot, team)
        for _, artifact in ipairs(data.bag or {}) do
            if id and tostring(artifact.id) == tostring(id) then
                local def = Defs.get(artifact.artifactId)
                if def and def.effectType == "counter_attack" then
                    coefficient = coefficient + math.max(0, finite(artifact.value)) / 100 * 0.5
                end
                break
            end
        end
    end
    return coefficient
end

-- Melissa 共鸣按“供给源英雄”计价：只计实际入选的魔伤+.25魔攻加成和魔穿，
-- 不因为队里有Melissa就把异系攻击/暴击/穿透等全额保留。Top筛选不改原队列。
---@param hero EffectivePowerUnit
---@param team EffectivePowerUnit[]
---@param context EffectivePowerContext
local function resonancePower(hero, team, context)
    local result = 0
    for _, melissa in ipairs(team) do
        if tonumber(melissa.heroId) == 20 and read(melissa.attrs, AD.MAG_ATK) > 0 then
            local stage3 = hasStage(melissa, 3, context)
            local contributors = {}
            for index, unit in ipairs(team) do
                if stage3 or staticDamageType(unit) == "魔法" then
                    local bonus = math.max(0, read(unit.attrs, AD.MAG_DMG_BONUS)
                        + read(unit.attrs, AD.MAG_ATK_BONUS) * 0.25)
                    local pen = math.max(0, read(unit.attrs, AD.MAG_PEN))
                    local score = bonus + pen * 0.6
                    if score > 0 then
                        contributors[#contributors + 1] = {
                            unit = unit, bonus = bonus, pen = pen, score = score, index = index,
                        }
                    end
                end
            end
            table.sort(contributors, function(a, b)
                if a.score == b.score then return a.index < b.index end
                return a.score > b.score
            end)
            for index = 1, math.min(stage3 and 4 or 3, #contributors) do
                local contribution = contributors[index]
                if contribution.unit == hero then
                    local weight = 1.5 * (stage3 and 1.5 or 1)
                    result = result + weight * (contribution.bonus * unitValue(AD.MAG_DMG_BONUS)
                        + contribution.pen * unitValue(AD.MAG_PEN))
                end
            end
        end
    end
    return result
end

-- 原 runtimeOnly 节点估值：124 small=4，其余 large=15；门控/概率按实际消费。
local RUNTIME_NODE_POWER = { [113] = 15, [115] = 15, [124] = 4, [125] = 15, [126] = 15, [128] = 15 }

---@param hero EffectivePowerUnit
---@param team EffectivePowerUnit[]
---@param context EffectivePowerContext
---@param primaryDamage boolean
---@param critProbability number
local function runtimePower(hero, team, context, primaryDamage, critProbability)
    local lit = context.talentsData and context.talentsData.litNodes
    local nodes = {}
    if lit then
        for _, id in ipairs(lit) do nodes[tonumber(id) or id] = true end
    else
        for id, enabled in pairs(hero.litNodeSet or {}) do
            if enabled then nodes[tonumber(id) or id] = true end
        end
    end
    local result = 0
    local healing = holyOutput(hero, context)
    for id, power in pairs(RUNTIME_NODE_POWER) do
        if nodes[id] then
            local factor = 0
            if id == 113 then
                if primaryDamage and staticDamageType(hero) == "魔法" then factor = 0.15 end
            elseif id == 115 then
                if primaryDamage then factor = critProbability end
            elseif id == 124 then
                if healing then
                    for _, target in ipairs(team) do
                        if read(target.attrs, AD.ENERGY_SHIELD) > 0 then factor = 1; break end
                    end
                end
            elseif id == 125 then
                if read(hero.attrs, AD.MAX_HP) > 0 then factor = 1 end
            elseif id == 126 then
                if damageOutput(hero, context) then factor = 1 end
            elseif id == 128 then
                if primaryDamage or healing then
                    for _, target in ipairs(team) do
                        -- 裸额伤不读 DMG_BONUS；全奶队不因这项伤加buff涨战力。
                        if category(target) ~= "healing" and damageOutput(target, context) then
                            factor = 0.15; break
                        end
                    end
                end
            end
            result = result + power * factor
        end
    end
    return result
end

--- 返回未取整战力；UI只在展示处round，装备搜索直接比较此number。
---@param hero EffectivePowerUnit|nil 已装配真实属性的运行时单位或独立候选副本
---@param context EffectivePowerContext|nil
---@return number
function M.calculate(hero, context)
    if not hero or not hero.attrs then return 0 end
    context = context or {}
    local attrs = hero.attrs
    local team = teamFor(hero, context)
    local cat = category(hero)
    local id = tonumber(hero.heroId)
    local total = 0
    for _, key in ipairs(DEFENSE_KEYS) do
        total = total + math.max(0, read(attrs, key)) * unitValue(key)
    end
    total = total + blockPower(attrs, AD.PHYS_BLOCK_RATE, AD.PHYS_BLOCK_RATIO)
        + blockPower(attrs, AD.MAG_BLOCK_RATE, AD.MAG_BLOCK_RATIO)
        + clamp(read(attrs, AD.ABNORMAL_RES), 0, 80) * unitValue(AD.ABNORMAL_RES)
    if shieldAvailable(hero, team, context) then
        total = total + clamp(read(attrs, AD.ES_DMG_REDUCE), 0, 80) * unitValue(AD.ES_DMG_REDUCE)
    end

    local atkKey = cat == "physical" and AD.PHYS_ATK or AD.MAG_ATK
    local primaryDamage = cat ~= "healing" and read(attrs, atkKey) > 0
    local healing = holyOutput(hero, context)
    local outputPower = 0
    local critProbability, critMult, rawCritRate = 0, 1, 0
    if primaryDamage then
        local crit, probability, multiplier, rawRate = primaryCritPower(hero, cat)
        critProbability, critMult, rawCritRate = probability, multiplier, rawRate
        outputPower = read(attrs, atkKey) * unitValue(atkKey)
            + damageStatsPower(attrs, cat) + crit
            + comboPower(hero, context) + read(attrs, AD.HIT_VALUE) * unitValue(AD.HIT_VALUE)
        total = total + outputPower
    elseif healing then
        local healCrit = critPower(attrs, "healing")
        local effectiveHeal = read(attrs, AD.HEAL_AMOUNT) * (1 + read(attrs, AD.HEAL_BONUS) / 100)
        total = total + effectiveHeal * unitValue(AD.HEAL_AMOUNT) + healCrit
    end
    if primaryDamage or healing then total = total + frequencyPower(hero) end

    -- 禁止自身回血不禁止给队友施疗；裸技能治疗不读取 HEAL_AMOUNT 或奶暴。
    local regen = attrs.artifactNoHeal and 0 or math.max(0, CF.calcHpRegen(attrs))
    local atkHeal = (attrs.artifactNoHeal or not primaryDamage) and 0 or math.max(0, CF.calcAtkHeal(attrs))
    total = total + regen * unitValue(AD.HP_REGEN) + atkHeal * unitValue(AD.ATK_HEAL)

    -- #14 超暴击：额伤复制已结算 totalDamage*(critMult-1)，不是再改CD。
    if id == 14 and primaryDamage and hasStage(hero, 3, context) and critMult > 1 then
        local superProbability = math.min(20, math.max(0, rawCritRate - 100) / 4) / 100
        total = total + math.max(0, outputPower) * critProbability * superProbability * (critMult - 1)
    end

    -- #17高压水枪：物理普攻之外确实有基于魔攻、吃魔伤/魔穿/魔暴的冰霜溅射。
    if id == 17 and primaryDamage and cat ~= "magical" and read(attrs, AD.MAG_ATK) > 0 then
        local coefficient = hasStage(hero, 2, context) and 0.55 or 0.40
        local magicCrit = critPower(attrs, "magical")
        total = total + coefficient * (read(attrs, AD.MAG_ATK) * unitValue(AD.MAG_ATK)
            + damageStatsPower(attrs, "magical") + magicCrit)
    end

    -- #20 常驻星门提速只读攻速和连击，转化合计上限40%。这是独立真实通道，
    -- 普攻频率封顶后仍可有效，但不得把已封顶星门的超额词条继续计入此项。
    if id == 20 and primaryDamage then
        local gateSpeed = clamp(math.max(0, read(attrs, AD.ATK_SPEED)) * 0.001
            + math.max(0, read(attrs, AD.COMBO_RATE)) * 0.0008, 0, 0.40)
        total = total + gateSpeed * unitValue(AD.ATK_SPEED) * 100
    end

    -- #21 氮气仅觉醒III额外消费魔伤；不消费魔攻/魔穿/魔暴。
    if id == 21 and primaryDamage and hasStage(hero, 3, context) then
        local proc = (30 + math.min(20, math.floor(math.max(0, read(attrs, AD.HIT_VALUE)) / 80) * 2)) / 100
        total = total + proc * 1.8 * read(attrs, AD.MAG_DMG_BONUS) * unitValue(AD.MAG_DMG_BONUS)
    end

    -- 裸魔攻副通道只计其实际倍率，不顺带保留魔伤/穿透/暴击。
    local bareMagicCoefficient = 0
    if setSix(hero) == "starless" then
        local cfg = ESC.SETS.starless.effect6
        bareMagicCoefficient = bareMagicCoefficient + cfg.magRatio / cfg.interval
    end
    if primaryDamage and setFour(hero) == "riftcrystal" and setSix(hero) == "riftcrystal" then
        local cfg = ESC.SETS.riftcrystal
        bareMagicCoefficient = bareMagicCoefficient + cfg.effect6.magRatio
            * cfg.effect4.procChance / cfg.effect4.maxStacks
    end
    if id == 15 and not hero._etsDisabled and hasStage(hero, 3, context) then
        local extra = owned(hero, context).extraTalent or {}
        local cards = math.max(0, finite(extra.issuedCards))
        -- 已发卡按实际张数；无卡但觉醒I已接线复活发卡时，只保留一张机制补偿，
        -- 不假设本场死亡/复活次数，更不对裸魔攻启用魔伤、魔穿或魔暴。
        if cards <= 0 and hasStage(hero, 1, context) then cards = 1 end
        if cards > 0 then bareMagicCoefficient = bareMagicCoefficient + 0.6 * cards end
    end
    if cat ~= "magical" then
        total = total + math.max(0, read(attrs, AD.MAG_ATK)) * unitValue(AD.MAG_ATK) * bareMagicCoefficient
    end

    local counter = counterCoefficient(hero, context)
    if counter > 0 then
        local base = math.max(read(attrs, AD.PHYS_ATK), read(attrs, AD.MAG_ATK), 0)
        total = total + base * unitValue(AD.PHYS_ATK) * counter
            * math.max(0, finite(attrs.artifactExtraDamageMult, 1))
    end

    -- 回响独立暴击与普攻不同：107读取泛R*.4（直到泛R250），214直接必暴，
    -- 倍率1+泛CD/100，不读类型暴率/暴伤、不吃神器暴击倍率。
    if primaryDamage and classId(hero) == CC.ECHO then
        local probability = hasGate(hero, "gate_214_eye") and 1
            or (hasGate(hero, "gate_107_aftertone") and clamp(read(attrs, AD.CRIT_RATE) * 0.4, 0, 100) / 100 or 0)
        if probability > 0 then
            total = total + math.max(0, read(attrs, AD.CRIT_DMG)) * unitValue(AD.CRIT_DMG) * probability * 0.45
        end
        if hasGate(hero, "gate_216_heavy") then
            local excessSpeed = math.max(0, read(attrs, AD.ATK_SPEED) - 100)
            total = total + math.max(0, outputPower) * 0.45 * excessSpeed * 0.02
        end
    end

    total = total + resonancePower(hero, team, context)
        + runtimePower(hero, team, context, primaryDamage, critProbability)
        + AC.calcTotalCombatPower(tonumber(hero.heroId), awakening(hero, context))
        + math.max(0, finite(attrs.artifactPowerBonus))
    return math.max(0, finite(total))
end

return M
