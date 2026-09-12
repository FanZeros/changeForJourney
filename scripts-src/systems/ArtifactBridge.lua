-- ============================================================================
-- ArtifactBridge.lua — 神器属性桥接模块
-- ============================================================================

local AD = require("systems.AttributeDef")
local ArtifactDefs = require("shared.artifact.ArtifactDefs")
local ArtifactSchema = require("shared.artifact.ArtifactSchema")

local ArtifactBridge = {}

local function getArtifactData()
    local ok, PlayerStore = pcall(require, "client.data.PlayerStore")
    if ok and PlayerStore and PlayerStore.Get then
        return PlayerStore.Get("artifacts")
    end
    return nil
end

local function findArtifactById(data, artifactId)
    artifactId = tostring(artifactId or "")
    for _, artifact in ipairs((data and data.bag) or {}) do
        if tostring(artifact.id) == artifactId then
            return artifact
        end
    end
    return nil
end

local function getEquippedArtifact(data, slot, subSlot)
    local artifactId = ArtifactSchema.getEquippedId(data, slot, subSlot or 1)
    if not artifactId then return nil end
    return findArtifactById(data, artifactId)
end

local function add(entries, key, value)
    value = tonumber(value) or 0
    if value == 0 then return end
    entries[#entries + 1] = { key = key, flat = value }
end

local function addPowerOnly(attrs, value)
    value = tonumber(value) or 0
    if value <= 0 then return end
    attrs.artifactPowerBonus = (attrs.artifactPowerBonus or 0) + value
end

local function makeRuntimeEffect(artifact, effectType, extra)
    local def = ArtifactDefs.get(artifact.artifactId)
    local effect = {
        artifactInstanceId = tostring(artifact.id),
        artifactId = artifact.artifactId,
        name = def and def.name or "神器",
        effectType = effectType,
        value = tonumber(artifact.value) or 0,
    }
    local threatClearValue = ArtifactDefs.getThreatClearValue and ArtifactDefs.getThreatClearValue(artifact) or nil
    if threatClearValue ~= nil then
        effect.threatClearValue = threatClearValue
    end
    if extra then
        for k, v in pairs(extra) do effect[k] = v end
    end
    return effect
end

local function applyArtifactToTarget(attrs, artifact, ownerSlot, targetSlot, runtimeEffects)
    if not artifact then return end
    local def = ArtifactDefs.get(artifact.artifactId)
    if not def then return end

    local value = tonumber(artifact.value) or 0
    local entries = {}
    local effectType = def.effectType

    if effectType == "dodge_decay" then
        runtimeEffects[#runtimeEffects + 1] = makeRuntimeEffect(artifact, effectType)
    elseif effectType == "shield_threat_clear" then
        add(entries, AD.ES_BONUS, value)
        runtimeEffects[#runtimeEffects + 1] = makeRuntimeEffect(artifact, effectType)
    elseif effectType == "hp_to_shield" then
        local maxHp = attrs:get(AD.MAX_HP)
        local convertedHp = maxHp * 0.5
        local hpBonus = attrs:get(AD.HP_BONUS)
        local hpBonusMult = 1 + hpBonus / 100
        if hpBonusMult <= 0 then hpBonusMult = 1 end
        add(entries, AD.MAX_HP, -convertedHp / hpBonusMult)
        add(entries, AD.ENERGY_SHIELD, convertedHp * value / 100)
    elseif effectType == "ignore_armor_armor_penalty" then
        add(entries, AD.ARMOR_BONUS, -value)
        attrs.artifactIgnoreArmor = true
    elseif effectType == "left_phys_atk_bonus" then
        if ownerSlot and targetSlot == ownerSlot - 1 then
            add(entries, AD.PHYS_ATK_BONUS, value)
        end
    elseif effectType == "right_mag_atk_bonus" then
        if ownerSlot and targetSlot == ownerSlot + 1 then
            add(entries, AD.MAG_ATK_BONUS, value)
        end
    elseif effectType == "hp_bonus_no_heal" then
        add(entries, AD.HP_BONUS, value)
        attrs.artifactNoHeal = true
        runtimeEffects[#runtimeEffects + 1] = makeRuntimeEffect(artifact, effectType)
    elseif effectType == "taunt_mask" then
        attrs.artifactExtraDamageMult = (attrs.artifactExtraDamageMult or 1.0) * (1 + value / 100)
        runtimeEffects[#runtimeEffects + 1] = makeRuntimeEffect(artifact, effectType)
    elseif effectType == "crit_dmg_mult_rate_half" then
        attrs.artifactCritRateMult = (attrs.artifactCritRateMult or 1.0) * 0.5
        attrs.artifactCritDmgMult = (attrs.artifactCritDmgMult or 1.0) * (value / 100)
    elseif effectType == "slow_attack_damage_bonus" then
        add(entries, AD.ATK_INTERVAL, attrs:get(AD.ATK_INTERVAL) * 0.5)
        attrs.artifactExtraDamageMult = (attrs.artifactExtraDamageMult or 1.0) * (1 + value / 100)
    elseif effectType == "counter_attack" then
        addPowerOnly(attrs, value * 0.5)
        runtimeEffects[#runtimeEffects + 1] = makeRuntimeEffect(artifact, effectType)
    elseif effectType == "revive_damage_bonus" then
        addPowerOnly(attrs, 120 + value * 0.4)
        runtimeEffects[#runtimeEffects + 1] = makeRuntimeEffect(artifact, effectType)
    elseif effectType == "ghost_damage_bonus" then
        addPowerOnly(attrs, value * 0.35)
        runtimeEffects[#runtimeEffects + 1] = makeRuntimeEffect(artifact, effectType)
    elseif effectType == "judgment_res_down" then
        addPowerOnly(attrs, value * 2.0)
        runtimeEffects[#runtimeEffects + 1] = makeRuntimeEffect(artifact, effectType)
    elseif effectType == "chaos_damage" then
        addPowerOnly(attrs, 200 + value)
        attrs.artifactChaosDamageMult = value / 100
        attrs.artifactChaosDefenseDisabled = true
    elseif effectType == "block_cap_up" then
        attrs.artifactBlockCap = math.max(attrs.artifactBlockCap or 100, value)
        if attrs.recalc then attrs:recalc() end
    end

    if #entries > 0 then
        attrs:addModifier("artifact_" .. tostring(ownerSlot or "x") .. "_" .. tostring(artifact.id), entries)
    end
end

--- 应用影响指定出战槽位的神器效果。
---@param attrs table UnitAttributes
---@param partySlot number 出战槽位 1~5
---@param artifactData table|nil 可选神器模块数据
---@return table[] runtimeEffects 需要战斗运行时处理的效果
function ArtifactBridge.applyToUnit(attrs, partySlot, artifactData)
    if not attrs or not partySlot then return {} end
    local data = artifactData or getArtifactData()
    if not data then return {} end

    local runtimeEffects = {}

    for slot = 1, ArtifactSchema.SLOT_COUNT do
        for subSlot = 1, ArtifactSchema.SUB_SLOT_COUNT do
            local artifact = getEquippedArtifact(data, slot, subSlot)
            if artifact then
                if slot == partySlot then
                    applyArtifactToTarget(attrs, artifact, slot, partySlot, runtimeEffects)
                else
                    local def = ArtifactDefs.get(artifact.artifactId)
                    if def and (def.effectType == "left_phys_atk_bonus" or def.effectType == "right_mag_atk_bonus") then
                        applyArtifactToTarget(attrs, artifact, slot, partySlot, runtimeEffects)
                    end
                end
            end
        end
    end

    return runtimeEffects
end

return ArtifactBridge
