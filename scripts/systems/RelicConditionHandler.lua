-- ============================================================================
-- RelicConditionHandler - 遗物条件词条运行时触发器
-- 处理 B 类（条件型）和 C 类（特殊机制）词条在战斗中的实时生效/失效
-- ============================================================================

local AD = require("systems.AttributeDef")
local TM = require("systems.ThreatManager")

local RCH = {}

-- 百分比加成类属性：词条文本带 %，但应写入 flat 而非 pct（与 RelicBridge 常驻词条一致）
local BONUS_PCT_KEYS = {
    [AD.HP_BONUS]        = true,
    [AD.ARMOR_BONUS]     = true,
    [AD.ES_BONUS]        = true,
    [AD.PHYS_ATK_BONUS]  = true,
    [AD.MAG_ATK_BONUS]   = true,
}

local function makeCondModEntry(adKey, value, isPercent)
    if isPercent and BONUS_PCT_KEYS[adKey] then
        return { key = adKey, flat = value }
    end
    if isPercent then
        return { key = adKey, pct = value }
    end
    return { key = adKey, flat = value }
end

-- 每个 unit 的条件状态存储
-- unitStates[unit] = { activeModIds = {}, triggered = {}, immunityCount = 0, ... }
local unitStates = {}

local function newUnitState(unit)
    return {
        conditions = unit.relicConditions or {},
        activeModIds = {},
        triggered = {},
        immunityCount = 0,      -- 免疫伤害剩余次数（遗物/天赋等共用）
        firstAttackBonus = 0,
        firstAttackUsed = false,
        timedBuffs = {},
    }
end

--- 确保单位拥有 RCH 运行时状态（天赋等可追加免疫次数）
---@param unit table
---@return table|nil
local function ensureUnitState(unit)
    if not unit then return nil end
    local state = unitStates[unit]
    if not state then
        state = newUnitState(unit)
        unitStates[unit] = state
    end
    return state
end

--- 追加免疫伤害次数（与遗物 affix 67 等同池，由 onBeforeTakeDamage 统一消费）
---@param unit table
---@param count number
function RCH.addImmunityCharges(unit, count)
    count = tonumber(count) or 0
    if count <= 0 or not unit then return end
    local state = ensureUnitState(unit)
    state.immunityCount = (state.immunityCount or 0) + count
end

--- 在战斗开始时初始化所有己方单位的条件词条
---@param allies table[] 己方单位列表（含 unit.relicConditions）
function RCH.initBattle(allies)
    unitStates = {}
    for _, unit in ipairs(allies) do
        if unit.relicConditions and #unit.relicConditions > 0 then
            local state = newUnitState(unit)
            unitStates[unit] = state
            RCH._applyBattleStartEffects(unit, state)
        end
    end
end

--- 处理"战斗开始时"类一次性效果
function RCH._applyBattleStartEffects(unit, state)
    for _, cond in ipairs(state.conditions) do
        if cond.condition then
            local condText = cond.condition

            -- "战斗开始时仇恨值+N" (affix 61)
            if condText:find("战斗开始") and cond.adKey == AD.THREAT then
                if cond.isPercent then
                    -- 百分比仇恨不太合理，但防御性处理
                    TM.addThreat(unit, cond.value)
                else
                    TM.addThreat(unit, cond.value)
                end
                state.triggered["battleStart_threat"] = true
            end

            -- "战斗开始时免疫伤害次数+N" (affix 67)
            if condText:find("战斗开始") and condText:find("免疫") then
                state.immunityCount = state.immunityCount + (cond.value or 0)
                state.triggered["battleStart_immunity"] = true
            end

            -- "战斗开始时初次攻击伤害加成+N%" (affix 87)
            if condText:find("战斗开始") and condText:find("初次攻击") then
                state.firstAttackBonus = state.firstAttackBonus + (cond.value or 0)
                state.triggered["battleStart_firstAtk"] = true
            end
        end
    end
end

--- 每帧更新：检查 HP 阈值条件，动态添加/移除修饰符
---@param allies table[] 己方单位列表
---@param battleTime number 当前战斗已经过时间（秒）
function RCH.update(allies, battleTime)
    for _, unit in ipairs(allies) do
        local state = unitStates[unit]
        if state and unit.hp > 0 and unit.attrs then
            RCH._checkHpConditions(unit, state)
            RCH._checkTimedBuffs(unit, state, battleTime)
        end
    end
end

--- 检查 HP 阈值条件
function RCH._checkHpConditions(unit, state)
    local hpPct = unit.hp / math.max(1, unit.maxHp)

    for idx, cond in ipairs(state.conditions) do
        if cond.condition and cond.adKey and not cond.special then
            local condText = cond.condition
            local modId = "relic_cond_" .. idx
            local shouldApply = false

            -- "满血时" — HP == 100%
            if condText:find("满血") then
                shouldApply = (hpPct >= 0.999)

            -- "生命低于25%时" / "生命低于50%时"
            elseif condText:find("生命低于") or condText:find("生命值低于") then
                local threshold = condText:match("低于(%d+)%%")
                if threshold then
                    threshold = tonumber(threshold) / 100
                    -- 区分"首次低于"（一次性）和普通阈值（持续）
                    if condText:find("首次") then
                        -- 首次低于 → 触发限时 buff（在 _checkFirstBelow 中处理）
                        -- 这里跳过，由专门逻辑处理
                    else
                        shouldApply = (hpPct < threshold)
                    end
                end
            end

            -- 应用或移除条件修饰符
            if shouldApply and not state.activeModIds[modId] then
                -- 应用修饰符
                local entries = { makeCondModEntry(cond.adKey, cond.value, cond.isPercent) }
                unit.attrs:addModifier(modId, entries)
                state.activeModIds[modId] = true
            elseif not shouldApply and state.activeModIds[modId] then
                -- 移除修饰符
                unit.attrs:removeModifier(modId)
                state.activeModIds[modId] = nil
            end
        end
    end

    -- "首次生命值低于X%时" 一次性触发（affix 92）
    RCH._checkFirstBelow(unit, state, hpPct)
end

--- 处理"首次低于X%"的一次性限时 buff
function RCH._checkFirstBelow(unit, state, hpPct)
    for idx, cond in ipairs(state.conditions) do
        if cond.condition and cond.condition:find("首次") and not state.triggered["firstBelow_" .. idx] then
            local threshold = cond.condition:match("低于(%d+)%%")
            local duration = cond.condition:match("(%d+)秒")
            if threshold and hpPct < tonumber(threshold) / 100 then
                state.triggered["firstBelow_" .. idx] = true
                local modId = "relic_firstBelow_" .. idx
                if cond.adKey and unit.attrs then
                    local entries = { makeCondModEntry(cond.adKey, cond.value, cond.isPercent) }
                    unit.attrs:addModifier(modId, entries)
                    state.activeModIds[modId] = true
                    -- 如果有时间限制，记录到 timedBuffs
                    if duration then
                        state.timedBuffs[#state.timedBuffs + 1] = {
                            expireAt = os.clock() + tonumber(duration),
                            modId = modId,
                        }
                    end
                end
            end
        end
    end
end

--- 检查限时 buff 是否到期
function RCH._checkTimedBuffs(unit, state, battleTime)
    local now = os.clock()
    local i = 1
    while i <= #state.timedBuffs do
        local buff = state.timedBuffs[i]
        if now >= buff.expireAt then
            -- 移除到期的 buff
            if state.activeModIds[buff.modId] then
                unit.attrs:removeModifier(buff.modId)
                state.activeModIds[buff.modId] = nil
            end
            table.remove(state.timedBuffs, i)
        else
            i = i + 1
        end
    end
end

--- 攻击前回调：处理"每次攻击获得仇恨值"和"初次攻击伤害加成"
---@param attacker table 攻击者
---@return number damageMultiplier 额外伤害乘数（1.0 = 无加成）
function RCH.onBeforeAttack(attacker)
    local state = unitStates[attacker]
    if not state then return 1.0 end

    local mult = 1.0

    -- 初次攻击伤害加成（affix 87）
    if state.firstAttackBonus > 0 and not state.firstAttackUsed then
        mult = mult + state.firstAttackBonus / 100
        state.firstAttackUsed = true
    end

    return mult
end

--- 攻击后回调：处理"每次攻击获得仇恨值+X%"
---@param attacker table 攻击者
---@param threatGained number 本次攻击实际获得的基础仇恨
function RCH.onAfterAttack(attacker, threatGained)
    local state = unitStates[attacker]
    if not state then return end

    for _, cond in ipairs(state.conditions) do
        if cond.condition and cond.condition:find("每次攻击") and cond.adKey == AD.THREAT then
            -- "每次攻击获得的仇恨值+X%" — 额外增加仇恨
            if cond.isPercent then
                local bonus = math.floor(threatGained * cond.value / 100)
                TM.addThreat(attacker, bonus)
            else
                TM.addThreat(attacker, cond.value)
            end
        end
    end
end

--- 受到伤害前回调：处理免疫伤害和终结机制
---@param target table 受击目标
---@param damage number 即将受到的伤害
---@return number adjustedDamage 调整后的伤害（0 = 免疫）
function RCH.onBeforeTakeDamage(target, damage)
    if (tonumber(damage) or 0) <= 0 then return damage end
    local state = unitStates[target]
    if not state then return damage end

    -- 免疫伤害次数（affix 67）
    local charges = tonumber(state.immunityCount) or 0
    if charges > 0 then
        state.immunityCount = charges - 1
        return 0  -- 完全免疫
    end
    state.immunityCount = 0

    return damage
end

--- 攻击命中后回调：处理终结机制（affix 89）
---@param attacker table 攻击者
---@param target table 被攻击目标
---@return boolean executed 是否触发了终结
function RCH.onAfterHit(attacker, target)
    local state = unitStates[attacker]
    if not state then return false end

    for _, cond in ipairs(state.conditions) do
        if cond.special and cond.special == "execute" then
            -- "[刺客]进行攻击时，有50%概率终结血量低于X%的敌人"
            local threshold = cond.executeThreshold or 0.15
            local chance = cond.executeChance or 0.5
            if target.hp > 0 then
                local tgtPct = target.hp / math.max(1, target.maxHp)
                if tgtPct < threshold and math.random() < chance then
                    return true  -- 触发终结
                end
            end
        end
    end
    return false
end

--- 闪避触发回调：处理"触发闪避时仇恨值-N"（affix 70）
---@param unit table 触发闪避的单位
function RCH.onDodge(unit)
    local state = unitStates[unit]
    if not state then return end

    for _, cond in ipairs(state.conditions) do
        if cond.condition and cond.condition:find("触发闪避") and cond.adKey == AD.THREAT then
            -- 减少仇恨
            TM.addThreat(unit, -(cond.value or 0))
        end
    end
end

--- 计算对目标的增伤修正（affix 47: "对血量低于30%增伤"）
---@param attacker table 攻击者
---@param target table 目标
---@return number bonusPct 增伤百分比（0 = 无加成）
function RCH.getDamageBonus(attacker, target)
    local state = unitStates[attacker]
    if not state then return 0 end

    local bonus = 0
    local tgtPct = target.hp / math.max(1, target.maxHp)

    for _, cond in ipairs(state.conditions) do
        if cond.condition and cond.condition:find("对血量低于") then
            local threshold = cond.condition:match("低于(%d+)%%")
            if threshold and tgtPct < tonumber(threshold) / 100 then
                bonus = bonus + (cond.value or 0)
            end
        end
    end

    return bonus
end

--- 清理战斗状态
function RCH.reset()
    -- 移除所有活跃修饰符
    for unit, state in pairs(unitStates) do
        if unit.attrs then
            for modId, _ in pairs(state.activeModIds) do
                unit.attrs:removeModifier(modId)
            end
        end
    end
    unitStates = {}
end

--- 获取单位是否有免疫状态（供 UI 显示）
function RCH.getImmunityCount(unit)
    local state = unitStates[unit]
    return state and state.immunityCount or 0
end

return RCH
