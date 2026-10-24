-- ============================================================================
-- ArtifactBridge.lua — 神器属性桥接模块
-- ============================================================================

local AD = require("systems.AttributeDef")
local ArtifactDefs = require("shared.artifact.ArtifactDefs")
local ArtifactSchema = require("shared.artifact.ArtifactSchema")

local ArtifactBridge = {}

local function getArtifactData()
    local ok, PlayerStore = pcall(require, "core.PlayerStore")
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

--- [三队适配] teamIdx 透传给 Schema；缺省 1（旧调用兼容）
local function getEquippedArtifact(data, slot, subSlot, teamIdx)
    local artifactId = ArtifactSchema.getEquippedId(data, slot, subSlot or 1, teamIdx)
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

-- 策略只保存行为和作用域，不捕获 ArtifactDefs/AD 的可变配置值。
-- 每件神器仍独立收集 entries，再立即提交；不能跨神器批量重算。
local function flatBonus(attributeName)
    return function(_attrs, value, entries)
        add(entries, AD[attributeName], value)
    end
end

local function adjacentBonus(attributeName, offset)
    return function(_attrs, value, entries, ownerSlot, targetSlot)
        if ownerSlot and targetSlot == ownerSlot + offset then
            add(entries, AD[attributeName], value)
        end
    end
end

local function powerBonus(calculate)
    return function(attrs, value)
        addPowerOnly(attrs, calculate(value))
    end
end

local function convertHpToShield(attrs, value, entries)
    local maxHp = attrs:get(AD.MAX_HP)
    local convertedHp = maxHp * 0.5
    local hpBonus = attrs:get(AD.HP_BONUS)
    local hpBonusMult = 1 + hpBonus / 100
    if hpBonusMult <= 0 then hpBonusMult = 1 end
    add(entries, AD.MAX_HP, -convertedHp / hpBonusMult)
    add(entries, AD.ENERGY_SHIELD, convertedHp * value / 100)
end

local function ignoreArmorWithPenalty(attrs, value, entries)
    add(entries, AD.ARMOR_BONUS, -value)
    attrs.artifactIgnoreArmor = true
end

local function increaseHpWithoutHealing(attrs, value, entries)
    add(entries, AD.HP_BONUS, value)
    attrs.artifactNoHeal = true
end

local function multiplyExtraDamage(attrs, value)
    attrs.artifactExtraDamageMult = (attrs.artifactExtraDamageMult or 1.0) * (1 + value / 100)
end

local function tradeCritRateForDamage(attrs, value)
    attrs.artifactCritRateMult = (attrs.artifactCritRateMult or 1.0) * 0.5
    attrs.artifactCritDmgMult = (attrs.artifactCritDmgMult or 1.0) * (value / 100)
end

local function slowAttackWithDamageBonus(attrs, value, entries)
    add(entries, AD.ATK_INTERVAL, attrs:get(AD.ATK_INTERVAL) * 0.5)
    multiplyExtraDamage(attrs, value)
end

local function enableChaosDamage(attrs, value)
    addPowerOnly(attrs, 200 + value)
    attrs.artifactChaosDamageMult = value / 100
    attrs.artifactChaosDefenseDisabled = true
end

local function raiseBlockCap(attrs, value)
    attrs.artifactBlockCap = math.max(attrs.artifactBlockCap or 100, value)
    if attrs.recalc then attrs:recalc() end
end

---@class ArtifactEffectStrategy
---@field apply? fun(attrs: table, value: number, entries: table[], ownerSlot: number, targetSlot: number)
---@field runtime? boolean
---@field affectsOtherSlots? boolean

-- 属性/标记策略先执行，runtime 描述随后追加，最后提交本件 modifier。
-- 纯 runtime 效果无需空处理函数；未知 effectType 仍不产生任何效果。
---@type table<string, ArtifactEffectStrategy>
local EFFECT_STRATEGIES = {
    dodge_decay = { runtime = true },
    shield_threat_clear = { apply = flatBonus("ES_BONUS"), runtime = true },
    hp_to_shield = { apply = convertHpToShield },
    ignore_armor_armor_penalty = { apply = ignoreArmorWithPenalty },
    left_phys_atk_bonus = { apply = adjacentBonus("PHYS_ATK_BONUS", -1), affectsOtherSlots = true },
    right_mag_atk_bonus = { apply = adjacentBonus("MAG_ATK_BONUS", 1), affectsOtherSlots = true },
    hp_bonus_no_heal = { apply = increaseHpWithoutHealing, runtime = true },
    taunt_mask = { apply = multiplyExtraDamage, runtime = true },
    crit_dmg_mult_rate_half = { apply = tradeCritRateForDamage },
    slow_attack_damage_bonus = { apply = slowAttackWithDamageBonus },
    counter_attack = { apply = powerBonus(function(value) return value * 0.5 end), runtime = true },
    revive_damage_bonus = { apply = powerBonus(function(value) return 120 + value * 0.4 end), runtime = true },
    ghost_damage_bonus = { apply = powerBonus(function(value) return value * 0.35 end), runtime = true },
    judgment_res_down = { apply = powerBonus(function(value) return value * 2.0 end), runtime = true },
    chaos_damage = { apply = enableChaosDamage },
    block_cap_up = { apply = raiseBlockCap },
}

local function applyArtifactToTarget(attrs, artifact, ownerSlot, targetSlot, runtimeEffects)
    if not artifact then return end
    local def = ArtifactDefs.get(artifact.artifactId)
    if not def then return end

    local value = tonumber(artifact.value) or 0
    local entries = {}
    local effectType = def.effectType
    local strategy = EFFECT_STRATEGIES[effectType]

    if strategy then
        if strategy.apply then
            strategy.apply(attrs, value, entries, ownerSlot, targetSlot)
        end
        if strategy.runtime then
            runtimeEffects[#runtimeEffects + 1] = makeRuntimeEffect(artifact, effectType)
        end
    end

    if #entries > 0 then
        attrs:addModifier("artifact_" .. tostring(ownerSlot or "x") .. "_" .. tostring(artifact.id), entries)
    end
end

--- 应用影响指定出战槽位的神器效果。
--- [三队适配] teamIdx 指定读取哪支队伍的装配表（缺省 1，主线战斗旧行为不变）
---@param attrs table UnitAttributes
---@param partySlot number 出战槽位 1~4
---@param artifactData table|nil 可选神器模块数据
---@param teamIdx? number 队伍索引 1~3，缺省 1
---@return table[] runtimeEffects 需要战斗运行时处理的效果
function ArtifactBridge.applyToUnit(attrs, partySlot, artifactData, teamIdx)
    if not attrs or not partySlot then return {} end
    local data = artifactData or getArtifactData()
    if not data then return {} end

    local runtimeEffects = {}

    for slot = 1, ArtifactSchema.SLOT_COUNT do
        for subSlot = 1, ArtifactSchema.SUB_SLOT_COUNT do
            local artifact = getEquippedArtifact(data, slot, subSlot, teamIdx)
            if artifact then
                if slot == partySlot then
                    applyArtifactToTarget(attrs, artifact, slot, partySlot, runtimeEffects)
                else
                    local def = ArtifactDefs.get(artifact.artifactId)
                    -- 两次短路读取保持动态 effectType 访问器的原有时序。
                    if def and (def.effectType == "left_phys_atk_bonus"
                        or def.effectType == "right_mag_atk_bonus") then
                        applyArtifactToTarget(attrs, artifact, slot, partySlot, runtimeEffects)
                    end
                end
            end
        end
    end

    return runtimeEffects
end

--- 队伍展示分项：只读已装 schema，不水合/迁移存档，也不应用战斗属性。
--- 常规效果要求来源槽有真实拥有英雄；左右增益按实际邻位目标判定。
--- 同实例在本队只计一次，未知定义/悬空引用忽略，不另加子槽等级门禁。
---@param artifactData table|nil
---@param teamSlots table|nil 面板槽位（state/heroId）
---@param ownedSet table|nil 面板真实拥有集合
---@param teamIdx? number
---@return number
function ArtifactBridge.getTeamPower(artifactData, teamSlots, ownedSet, teamIdx)
    if type(artifactData) ~= "table" or type(teamSlots) ~= "table"
        or type(ownedSet) ~= "table" then return 0 end
    local byId = {}
    for _, artifact in ipairs(artifactData.bag or {}) do
        if type(artifact) == "table" and artifact.id ~= nil then
            local id = tostring(artifact.id)
            if id ~= "" and not byId[id] then byId[id] = artifact end
        end
    end
    local function hasHero(slot)
        local target = teamSlots[slot] or teamSlots[tostring(slot)]
        if type(target) ~= "table" or target.state ~= "occupied" then return false end
        local heroId = tonumber(target.heroId)
        local owned = heroId and (ownedSet[heroId] or ownedSet[tostring(heroId)])
        return heroId ~= nil and heroId > 0 and type(owned) == "table"
    end
    local total, counted = 0, {}
    for slot = 1, ArtifactSchema.SLOT_COUNT do
        for subSlot = 1, ArtifactSchema.SUB_SLOT_COUNT do
            local equippedId = ArtifactSchema.getEquippedId(artifactData, slot, subSlot, teamIdx)
            local id = equippedId ~= nil and tostring(equippedId) or ""
            local artifact = byId[id]
            local def = artifact and ArtifactDefs.get(artifact.artifactId)
            if def and not counted[id] then
                local target = slot
                if def.effectType == "left_phys_atk_bonus" then target = slot - 1
                elseif def.effectType == "right_mag_atk_bonus" then target = slot + 1 end
                if target >= 1 and target <= ArtifactSchema.SLOT_COUNT and hasHero(target) then
                    counted[id] = true
                    total = total + ArtifactDefs.getPower(artifact)
                end
            end
        end
    end
    return total
end

return ArtifactBridge
