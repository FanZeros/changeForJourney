-- ============================================================================
-- ArtifactRuntime.lua — 神器战斗运行时效果
-- ============================================================================

local AD = require("systems.AttributeDef")
local TM = require("systems.ThreatManager")
local CF = require("systems.CombatFormula")

local ArtifactRuntime = {}

local unitStates = {}

local function getUnitHp(unit)
    if unit and unit.attrs then
        return unit.attrs:get(AD.HP), unit.attrs:get(AD.MAX_HP)
    end
    return unit and (unit.hp or 0) or 0, unit and (unit.maxHp or 0) or 0
end

local function syncUnitHp(unit)
    if unit and unit.attrs then
        unit.hp = unit.attrs:get(AD.HP)
        unit.maxHp = unit.attrs:get(AD.MAX_HP)
    end
end

local function addTempModifier(unit, state, id, entries)
    if not unit or not unit.attrs then return end
    unit.attrs:addModifier(id, entries)
    state.activeModIds[id] = true
    syncUnitHp(unit)
end

local function removeTempModifier(unit, state, id)
    if not unit or not unit.attrs or not id then return end
    unit.attrs:removeModifier(id)
    state.activeModIds[id] = nil
    syncUnitHp(unit)
end

local function addTempExtraDamageMult(unit, state, id, value)
    if not unit or not unit.attrs then return end
    value = tonumber(value) or 0
    local mult = 1 + value / 100
    if mult <= 0 then mult = 1 end
    state.activeExtraDamageMults[id] = mult
    unit.attrs.artifactExtraDamageMult = (unit.attrs.artifactExtraDamageMult or 1.0) * mult
end

local function removeTempExtraDamageMult(unit, state, id)
    if not unit or not unit.attrs or not id then return end
    local mult = state.activeExtraDamageMults[id]
    if mult and mult ~= 0 then
        unit.attrs.artifactExtraDamageMult = (unit.attrs.artifactExtraDamageMult or 1.0) / mult
        if math.abs(unit.attrs.artifactExtraDamageMult - 1.0) < 0.0001 then
            unit.attrs.artifactExtraDamageMult = nil
        end
    end
    state.activeExtraDamageMults[id] = nil
end

local function ensureState(unit)
    if not unit then return nil end
    local state = unitStates[unit]
    if not state then
        state = { effects = {}, activeModIds = {}, activeExtraDamageMults = {} }
        unitStates[unit] = state
    end
    return state
end

local function addEffect(unit, effect)
    local state = ensureState(unit)
    if not state then return end
    state.effects[#state.effects + 1] = effect
end

function ArtifactRuntime.reset()
    unitStates = {}
end

function ArtifactRuntime.initBattle(allies)
    unitStates = {}
    for _, unit in ipairs(allies or {}) do
        if unit.artifactEffects and #unit.artifactEffects > 0 then
            for _, effect in ipairs(unit.artifactEffects) do
                addEffect(unit, effect)
            end
            ArtifactRuntime._applyBattleStart(unit, unitStates[unit])
        end
    end
end

function ArtifactRuntime._applyBattleStart(unit, state)
    for idx, effect in ipairs(state.effects) do
        if effect.effectType == "dodge_decay" then
            local decay = tonumber(effect.value) or 0
            if unit.attrs then
                local modId = "artifact_dodge_decay_" .. tostring(idx)
                local startValue = 200
                addTempModifier(unit, state, modId, { { key = AD.DODGE_BONUS, flat = startValue } })
                effect.remaining = startValue
                effect.step = math.max(0, decay)
                effect.modId = modId
            end
        end
    end
end

function ArtifactRuntime.onDodge(unit)
    local state = unitStates[unit]
    if not state or not unit or not unit.attrs then return end
    for _, effect in ipairs(state.effects) do
        if effect.effectType == "dodge_decay" and effect.modId and (effect.remaining or 0) > 0 then
            local nextValue = math.max(0, (effect.remaining or 0) - (effect.step or 1))
            effect.remaining = nextValue
            if nextValue > 0 then
                addTempModifier(unit, state, effect.modId, { { key = AD.DODGE_BONUS, flat = nextValue } })
            else
                removeTempModifier(unit, state, effect.modId)
            end
        end
    end
end

function ArtifactRuntime.canHeal(unit)
    local state = unitStates[unit]
    if not state then return true end
    for _, effect in ipairs(state.effects) do
        if effect.effectType == "hp_bonus_no_heal" then
            return false
        end
    end
    return true
end

function ArtifactRuntime.adjustThreatGain(unit, amount)
    local state = unitStates[unit]
    amount = tonumber(amount) or 0
    if not state or amount <= 0 then return amount end
    local extraRatio = 0
    for _, effect in ipairs(state.effects) do
        if effect.effectType == "taunt_mask" then
            local value = math.max(0, tonumber(effect.value) or 0)
            extraRatio = extraRatio + value * 2 / 100
        end
    end
    return amount + amount * extraRatio
end

function ArtifactRuntime.onShieldBroken(unit)
    local state = unitStates[unit]
    if not state then return end
    for _, effect in ipairs(state.effects) do
        if effect.effectType == "shield_threat_clear" and not effect.triggered then
            effect.triggered = true
            if TM.reduceThreatPercent then
                TM.reduceThreatPercent(unit, tonumber(effect.threatClearValue) or 0)
            else
                TM.clearThreat(unit)
            end
        end
    end
end

function ArtifactRuntime.checkShieldBreak(unit, shieldBefore)
    if not unit or not unit.attrs then return end
    shieldBefore = tonumber(shieldBefore) or 0
    if shieldBefore <= 0 then return end
    local shieldAfter = (unit.attrs.energyShield or 0) + (unit.attrs.tempEnergyShield or 0)
    if shieldAfter <= 0 then
        ArtifactRuntime.onShieldBroken(unit)
    end
end

function ArtifactRuntime.onBeforeTakeDamage(unit, attacker, damage, isUnitAlly)
    local state = unitStates[unit]
    if not state or not attacker or not unit or damage <= 0 then return damage end
    for _, effect in ipairs(state.effects) do
        if effect.effectType == "counter_attack" and math.random() < 0.5 then
            effect.pendingCounter = effect.pendingCounter or {}
            local atk = unit.attrs and unit.attrs:get(AD.PHYS_ATK) or 0
            local mag = unit.attrs and unit.attrs:get(AD.MAG_ATK) or 0
            local baseAtk = math.max(atk, mag)
            local counterDamage = baseAtk * ((tonumber(effect.value) or 0) / 100)
            if unit.attrs and unit.attrs.artifactExtraDamageMult then
                counterDamage = counterDamage * unit.attrs.artifactExtraDamageMult
            end
            counterDamage = math.max(1, math.floor(counterDamage + 0.5))
            effect.pendingCounter[#effect.pendingCounter + 1] = {
                target = attacker,
                damage = counterDamage,
                isTargetAlly = not isUnitAlly,
            }
        end
    end
    return damage
end

function ArtifactRuntime.consumeCounterAttacks(unit)
    local state = unitStates[unit]
    if not state then return nil end
    local result = nil
    for _, effect in ipairs(state.effects) do
        if effect.pendingCounter and #effect.pendingCounter > 0 then
            result = result or {}
            for _, entry in ipairs(effect.pendingCounter) do
                result[#result + 1] = entry
            end
            effect.pendingCounter = nil
        end
    end
    return result
end

function ArtifactRuntime.onAllyDeath(unit)
    local state = unitStates[unit]
    if not state or not unit or not unit.attrs then return false end
    for _, effect in ipairs(state.effects) do
        if effect.effectType == "revive_damage_bonus" and not effect.triggered then
            effect.triggered = true
            local _hp, maxHp = getUnitHp(unit)
            unit.attrs.final[AD.HP] = math.max(1, math.floor(maxHp * 0.5 + 0.5))
            syncUnitHp(unit)
            local modId = "artifact_revive_damage_bonus_" .. tostring(effect.artifactInstanceId or "x")
            addTempExtraDamageMult(unit, state, modId, tonumber(effect.value) or 0)
            return true
        elseif effect.effectType == "ghost_damage_bonus" and not effect.triggered then
            effect.triggered = true
            unit.attrs.final[AD.HP] = 1
            syncUnitHp(unit)
            unit.artifactUntargetable = true
            effect.ghostTimer = 10.0
            local modId = "artifact_ghost_damage_bonus_" .. tostring(effect.artifactInstanceId or "x")
            effect.modId = modId
            addTempExtraDamageMult(unit, state, modId, tonumber(effect.value) or 0)
            TM.removeUnit(unit)
            return true
        end
    end
    return false
end

function ArtifactRuntime.onAfterAttack(attacker, target, result)
    local state = unitStates[attacker]
    if not state or not attacker or not target or not result or not result.isHit then return end
    for _, effect in ipairs(state.effects) do
        if effect.effectType == "judgment_res_down" then
            if effect.lastTarget ~= target then
                effect.lastTarget = target
                effect.stacks = 0
            end
            effect.stacks = math.min((effect.stacks or 0) + 1, 8)
            attacker.artifactJudgmentStacks = attacker.artifactJudgmentStacks or {}
            attacker.artifactJudgmentStacks[target] = {
                category = result.category,
                value = (tonumber(effect.value) or 0) * effect.stacks,
            }
        end
    end
end

function ArtifactRuntime.update(dt)
    dt = tonumber(dt) or 0
    for unit, state in pairs(unitStates) do
        for _, effect in ipairs(state.effects) do
            if effect.effectType == "ghost_damage_bonus" and effect.ghostTimer then
                effect.ghostTimer = effect.ghostTimer - dt
                if effect.ghostTimer <= 0 then
                    effect.ghostTimer = nil
                    unit.artifactUntargetable = nil
                    removeTempExtraDamageMult(unit, state, effect.modId)
                    if unit.attrs and unit.hp > 0 then
                        unit.attrs.final[AD.HP] = 0
                        syncUnitHp(unit)
                    end
                end
            end
        end
    end
end

return ArtifactRuntime
