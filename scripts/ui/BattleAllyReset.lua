-- ============================================================================
-- BattleAllyReset - 己方单位属性快照隔离与重置
-- 从 BattleScene 抽出
-- ============================================================================

local AD = require("systems.AttributeDef")
local BattleCombat = require("ui.BattleCombat")

local M = {}

--- 为单位创建基线快照（调用时机：setAllies / fallback 重建后）
---@param u table
function M.createSnapshot(u)
    if u.attrs then
        u._baseSnapshot = u.attrs:clone()
    end
    u._baseArmorType = u.armorType
    u._pendingSnapshot = nil
    u._pendingArmorType = nil
end

--- 从快照恢复单位属性
---@param u table
---@return boolean
function M.restoreFromSnapshot(u)
    if u._pendingSnapshot then
        u._hadPendingSnapshot = true
        u._baseSnapshot = u._pendingSnapshot
        u._pendingSnapshot = nil
    else
        u._hadPendingSnapshot = false
    end
    if u._pendingLevel then
        u.level = u._pendingLevel
        u._pendingLevel = nil
    end
    if u._pendingArmorType then
        u._baseArmorType = u._pendingArmorType
        u._pendingArmorType = nil
    end
    if u._baseArmorType then
        u.armorType = u._baseArmorType
    end
    if u._baseSnapshot then
        u.attrs = u._baseSnapshot:clone()
        if u.attrs and AD.getAtkCategory(u.attrs.atkType) == "healing" then
            local snapHeal = u._baseSnapshot:get(AD.HEAL_AMOUNT)
            local clonedHeal = u.attrs:get(AD.HEAL_AMOUNT)
            if snapHeal <= 0 or clonedHeal <= 0 then
                print(string.format(
                    "[HealDiag3] RESTORE_SNAP_ZERO name=%s id=%s snapHeal=%.1f clonedHeal=%.1f"
                    .. " hadPending=%s atkType=%d",
                    tostring(u.name), tostring(u.heroId or "?"),
                    snapHeal, clonedHeal,
                    tostring(u._hadPendingSnapshot or false),
                    u.attrs.atkType or -1
                ))
            end
        end
        return true
    end
    return false
end

--- 重置单个己方单位（从快照恢复干净属性 → 填满血）
---@param u table
---@param allies table[]
---@param syncUnitHp fun(u: table)
function M.resetAllyUnit(u, allies, syncUnitHp)
    u.atkProgress = 0
    u.reviveTimer = nil
    u._fallen = nil
    u._fallenPending = nil
    BattleCombat.clearCardAnim(u)
    if u.attrs then
        local restored = M.restoreFromSnapshot(u)
        if not restored then
            if u.heroId then
                local HC = require("config.HeroConfig")
                local CP = require("ui.CharacterPanel")
                local owned = CP.getOwnedHero and CP.getOwnedHero(u.heroId)
                local heroLevel = (CP.getEffectiveLevel and CP.getEffectiveLevel(u.heroId))
                    or (owned and owned.level) or u.level
                local newUnit = HC.createHero(u.heroId,
                    heroLevel,
                    (owned and owned.advBranch) or u.advBranch,
                    owned and owned.awakening,
                    owned and owned.extraTalent)
                if newUnit and newUnit.attrs then
                    local partySlot = nil
                    for ai, a in ipairs(allies) do
                        if a == u then partySlot = ai; break end
                    end
                    if CP.applyEquippedItems then
                        local eqArmorType = CP.applyEquippedItems(newUnit.attrs, u.heroId, partySlot)
                        if eqArmorType then
                            newUnit.armorType = eqArmorType
                        end
                    end
                    local RelicBridge = require("systems.RelicBridge")
                    local relicConds = RelicBridge.applyToUnit(newUnit.attrs, newUnit.classId or u.classId)
                    if relicConds and #relicConds > 0 then
                        u.relicConditions = relicConds
                    end
                    local artifactEffects = require("systems.ArtifactBridge").applyToUnit(newUnit.attrs, partySlot)
                    if artifactEffects and #artifactEffects > 0 then
                        u.artifactEffects = artifactEffects
                    else
                        u.artifactEffects = nil
                    end
                    u.attrs = newUnit.attrs
                    u.armorType = newUnit.armorType
                    u.level = newUnit.level
                    u.advBranch = newUnit.advBranch
                    u.advTalentIds = newUnit.advTalentIds
                    u.awakeningNodes = newUnit.awakeningNodes
                end
            end
            M.createSnapshot(u)
        end
        u.attrs:fillHp()
        u.maxHp       = u.attrs.final[AD.MAX_HP]
        u.hp          = u.attrs.final[AD.HP]
        u.atkInterval = u.attrs:getActualInterval()
        u._lastAttrInterval = u.atkInterval
    else
        print("[BattleDiag] RESET_NO_ATTRS name=" .. tostring(u.name)
            .. " id=" .. tostring(u.heroId or u.instanceId or "?")
            .. " hp=" .. tostring(u.hp) .. "/" .. tostring(u.maxHp)
            .. " sentinel=" .. tostring(u._sentinelInstalled or false)
            .. " trace=" .. tostring(u._attrsSetNilTrace or "none"))
        u.hp = u.maxHp
    end
    syncUnitHp(u)
    if u.attrs and AD.getAtkCategory(u.attrs.atkType) == "healing" then
        local healAmt = u.attrs:get(AD.HEAL_AMOUNT)
        if healAmt <= 0 then
            local baseH = u.attrs:getBase(AD.HEAL_AMOUNT)
            local snapH = u._baseSnapshot and u._baseSnapshot:get(AD.HEAL_AMOUNT) or -1
            print(string.format(
                "[HealDiag2] RESET_HEALER_ZERO name=%s id=%s healAmt_final=%.1f"
                .. " healAmt_base=%.1f snap_healAmt=%.1f hp=%d/%d",
                tostring(u.name), tostring(u.heroId),
                healAmt, baseH, snapH, u.hp, u.maxHp or 0
            ))
        end
    end
end

return M
