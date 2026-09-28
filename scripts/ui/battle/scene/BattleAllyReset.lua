-- ============================================================================
-- BattleAllyReset - 己方单位属性快照隔离与重置
-- 从 BattleScene 抽出
-- ============================================================================

local AD = require("systems.AttributeDef")
local BattleCombat = require("ui.battle.combat.BattleCombat")

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
    u._fallenAt = nil
    BattleCombat.clearCardAnim(u)
    if u.attrs then
        local restored = M.restoreFromSnapshot(u)
        if not restored then
            if u.heroId then
                local HC = require("config.HeroConfig")
                local CP = require("ui.character.panel.CharacterPanel")
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
                    -- [927 遗物后端移除] RelicBridge 已删除，不再应用遗物条件
                    -- [928 三队并行] ArtifactBridge 保留 teamIdx 参数（多队神器数据隔离）
                    local artifactEffects = require("systems.ArtifactBridge").applyToUnit(newUnit.attrs, partySlot, nil, u.artifactTeamIdx or 1)
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

--- [阵亡紧凑] 退场完成 → 移队尾 → 存活者前移一格（四条战斗线共用）
--- 时间兜底：动画状态若卡住不到 gone（anim 被覆盖/清除/特效开关等），
--- 退场登记后超过 退场时长+0.3s 仍悬挂就强制紧凑，杜绝"空槽不前移"卡死。
---@param allies table[]
---@param now number time.elapsedTime
function M.compactFallen(allies, now)
    local BattleCombatAnim = require("ui.battle.combat.BattleCombatAnim")
    local BattleLayout = require("core.BattleLayout")
    local grace = (BattleCombatAnim.DEATH_ANIM_DURATION or 0.5) + 0.3
    for i = #allies, 1, -1 do
        local u = allies[i]
        if u._fallenPending then
            local st = BattleCombat.getAnimState(u)
            if u.hp > 0 then
                -- 退场途中被拉起：取消紧凑，留在原位
                u._fallenPending = nil
                u._fallenAt = nil
            elseif st == "gone" or st == nil
                or (u._fallenAt ~= nil and now - u._fallenAt >= grace) then
                if st ~= "gone" and st ~= nil then
                    print(string.format("[AllyCompact] 动画状态卡住兜底: name=%s st=%s 悬挂%.2fs → 强制紧凑",
                        tostring(u.name), tostring(st), now - u._fallenAt))
                    BattleCombat.clearCardAnim(u)
                end
                u._fallenPending = nil
                u._fallenAt = nil
                u._fallen = true
                table.remove(allies, i)
                table.insert(allies, u)
                for j = i, #allies - 1 do
                    local moved = allies[j]
                    if moved.hp > 0 then
                        BattleCombat.setCardAnim(moved, { state = "advance", timer = 0, lungeDir = 1,
                            advanceDist = BattleLayout.STRIP_PITCH })
                    end
                end
            end
        end
    end
end

--- 恢复己方出场顺序（原位排序，调用方持有的数组引用不变）
--- 「阵亡紧凑」会把阵亡英雄 table.remove + insert 到队尾（BattleCasualty），
--- 渲染按数组下标定位（BattleDraw → BattleLayout.cardPos），所以顺序一旦被打乱，
--- 切关后角色站位就会和编队槽位不一致。切关统一调这里复位。
--- 没有原始槽位号时保持现有顺序，不做任何改动。
---@param allies table[]
function M.restoreOrder(allies)
    if not allies or #allies < 2 then return end
    -- 只按「记录过槽位的单位」判断是否需要重排，避免无槽位信息时误排
    local hasSlot = false
    for _, u in ipairs(allies) do
        if u._slotOrder then hasSlot = true break end
    end
    if not hasSlot then return end
    table.sort(allies, function(a, b)
        local oa = a._slotOrder or math.huge
        local ob = b._slotOrder or math.huge
        if oa ~= ob then return oa < ob end
        return false  -- 稳定：相等时保持相对顺序
    end)
end

return M
