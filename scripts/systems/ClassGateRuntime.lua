-- ============================================================================
-- ClassGateRuntime - 六门契基础职 + 转职 101–224 新效果
-- 旧 adv_* talentId 已从 AdvancementConfig 撤掉，圣光/飞弹等不再触发。
-- 207/220 双持仍走 EquipmentSystem（talentId 未改）。
-- ============================================================================

local AD = require("systems.AttributeDef")
local CC = require("config.ClassConfig")

local CGR = {}

local function cid(unit)
    return unit and CC.normalize(unit.classId) or nil
end

local function hasGate(unit, talentId)
    if not unit or not unit.advTalentIds then return false end
    for _, tid in ipairs(unit.advTalentIds) do
        if tid == talentId then return true end
    end
    return false
end

local function maxHpOf(unit)
    if unit.attrs then return unit.attrs:get(AD.MAX_HP) or unit.maxHp or 1 end
    return unit.maxHp or 1
end

local function physAtkOf(unit)
    if unit.attrs then return unit.attrs:get(AD.PHYS_ATK) or 0 end
    return 0
end

local function teamHasSeal(allies)
    for _, u in ipairs(allies or {}) do
        if (u.hp or 0) > 0 and cid(u) == CC.SEAL then return true end
    end
    return false
end

--- 开战：门缝容量、裂隙计时、换面初始目标
---@param allies table[]
---@param enemies table[]
function CGR.onBattleStart(allies, enemies)
    for _, u in ipairs(allies or {}) do
        local id = cid(u)
        if id == CC.SEAL then
            local cap = maxHpOf(u) * 0.12
            if hasGate(u, "gate_101_latch") then cap = cap * 1.50 end
            u._gateCap = cap
            u._gateStored = 0
            u._gateEnemyRatio = hasGate(u, "gate_201_seal_strip") and 1.0
                or (hasGate(u, "gate_101_latch") and 0.50 or 0.30)
            print("[Gate] 封门人 " .. tostring(u.name) .. " 门缝容量=" .. math.floor(cap))
        elseif id == CC.SPOIL then
            u._spoilBones = 0
            u._spoilReady = false
            u._spoilCap = hasGate(u, "gate_103_bone_market") and 18 or 12
            u._spoilLastTarget = nil
        elseif id == CC.RIFT then
            u._riftCd = hasGate(u, "gate_105_offset") and 6 or 8
            u._riftLeft = 0
            u._riftCycle = 1
        elseif id == CC.MASK then
            local t = nil
            for _, e in ipairs(enemies or {}) do
                if (e.hp or 0) > 0 then t = e; break end
            end
            u._maskTarget = t
            u._maskWindow = 0
            u._maskArmorStrike = false
        elseif id == CC.DEBT then
            -- 延缓层挂在队友身上，司仪本人只负责施加
        elseif id == CC.ECHO then
            u._echoQueue = u._echoQueue or {}
        end
    end
end

--- 裂隙：克制向 1.25 拉近；换面：+0.1
---@param attacker table
---@param defender table
---@param typeMult number
---@return number
function CGR.adjustTypeMult(attacker, defender, typeMult)
    if not attacker or not typeMult then return typeMult end
    local id = cid(attacker)
    if id == CC.RIFT and (attacker._riftLeft or 0) > 0 then
        typeMult = typeMult + (1.25 - typeMult) * 0.5
    end
    if id == CC.MASK and defender and attacker._maskTarget == defender then
        typeMult = typeMult + 0.10
    end
    return typeMult
end

--- 换面窗口内下次攻击无视 20% 护甲
---@param attacker table
---@param rawArmor number
---@return number
function CGR.adjustArmor(attacker, rawArmor)
    if cid(attacker) == CC.MASK and attacker._maskArmorStrike then
        attacker._maskArmorStrike = false
        local keep = 0.80
        if hasGate(attacker, "gate_217_still") and (attacker._maskStill or 0) >= 5 then
            keep = 0.60
        end
        return rawArmor * keep
    end
    return rawArmor
end

--- 封门人：伤害先写门缝。返回剩余打到血条的量。
---@param target table
---@param damage number
---@return number
function CGR.absorbIncoming(target, damage)
    if target and cid(target) == CC.MASK then target._maskStill = 0 end
    if cid(target) ~= CC.SEAL or damage <= 0 then return damage end
    local cap = target._gateCap or (maxHpOf(target) * 0.12)
    target._gateCap = cap
    local stored = target._gateStored or 0
    local room = math.max(0, cap - stored)
    if room <= 0 then return damage end
    local absorbed = math.min(damage, room)
    target._gateStored = stored + absorbed
    local TM = require("systems.ThreatManager")
    TM.addThreat(target, absorbed * 0.5)
    return damage - absorbed
end

--- 司仪延缓：致死改为留 1 血并上 4 秒债。返回 true 表示拦住死亡。
---@param target table
---@return boolean
function CGR.tryDeferDeath(target)
    if not target or not target._gateDefer then return false end
    if target._gateDeferChance and math.random() > target._gateDeferChance then
        target._gateDefer = false
        return false
    end
    target._gateDefer = false
    target._gateDebtT = 4
    target._gateDebtTaken = 0
    if target.attrs then
        local one = 1
        target.attrs.final[AD.HP] = one
        target.hp = one
    else
        target.hp = 1
    end
    if target._gateWarPray and target.attrs then
        target.attrs:addModifier("gate_war_pray", { { key = AD.DMG_BONUS, flat = 25 } })
        target._gateWarPrayHit = true
    end
    print("[Gate] 延缓拦住 " .. tostring(target.name) .. " 致死，上债 4s")
    return true
end

--- 债期受伤 +15%
---@param target table
---@param damage number
---@return number
function CGR.applyDebtTaken(target, damage)
    if target and (target._gateDebtT or 0) > 0 then
        local out = damage * 1.15
        target._gateDebtTaken = (target._gateDebtTaken or 0) + out
        return out
    end
    return damage
end

--- 过量治疗 → 延缓层（每人 1 层）
---@param healer table
---@param target table
---@param overheal number
function CGR.onOverheal(healer, target, overheal)
    if cid(healer) ~= CC.DEBT then return end
    if not target or overheal <= 0 then return end
    local cap = hasGate(healer, "gate_111_defer2") and 2 or 1
    healer._deferCount = healer._deferCount or 0
    if target._gateDefer then return end
    if healer._deferCount >= cap then return end
    target._gateDefer = true
    target._gateDeferHealer = healer
    target._gateWarPray = hasGate(healer, "gate_221_war")
    target._gateDeferChance = hasGate(healer, "gate_222_blood") and 0.40 or 1
    healer._deferCount = healer._deferCount + 1
    if hasGate(healer, "gate_224_punish") then
        healer._punishReady = overheal
    end
end

local function extraHitPct(attacker)
    if attacker.attrs then
        local cat = AD.getAtkCategory(attacker.attrs.atkType or attacker.atkType)
        if cat == "physical" then return attacker.attrs:get(AD.PHYS_ATK) or 0 end
        return attacker.attrs:get(AD.MAG_ATK) or 0
    end
    return physAtkOf(attacker)
end

---@param attacker table
---@param target table
---@param result table
---@param isAlly boolean
---@param dealDmgFn function
---@param allies table[]|nil
function CGR.onAfterAttack(attacker, target, result, isAlly, dealDmgFn, allies)
    if not attacker or not result or result.isMiss then return end
    local id = cid(attacker)
    if id == CC.ECHO and dealDmgFn and target and isAlly then
        attacker._echoQueue = attacker._echoQueue or {}
        local dmg = (result.totalDamage or 0) * 0.45
        if teamHasSeal(allies) then dmg = dmg * 1.15 end
        local delay = hasGate(attacker, "gate_107_aftertone") and 0.8 or 1.2
        local same = 0
        for _, job in ipairs(attacker._echoQueue) do
            if job.target == target then same = same + 1 end
        end
        if hasGate(attacker, "gate_108_stacktone") then
            if same >= 2 then return end
            if same == 1 then dmg = (result.totalDamage or 0) * 0.70 end
        end
        if hasGate(attacker, "gate_216_heavy") then
            local spd = attacker.attrs and (attacker.attrs:get(AD.ATK_SPEED) or 0) or 0
            if spd > 100 then dmg = dmg * (1 + (spd - 100) * 0.02) end
        end
        attacker._echoQueue[#attacker._echoQueue + 1] = {
            t = delay, target = target, dmg = dmg,
            crit = hasGate(attacker, "gate_214_eye") or hasGate(attacker, "gate_107_aftertone"),
        }
    elseif id == CC.SPOIL then
        if target then
            if hasGate(attacker, "gate_208_peelchain") then
                if attacker._spoilLastTarget == target then
                    attacker._spoilChain = (attacker._spoilChain or 0) + 1
                else
                    attacker._spoilChain = 0
                end
                attacker._spoilLastTarget = target
            end
        end
        if attacker._spoilReady and dealDmgFn and target and (target.hp or 0) > 0 then
            attacker._spoilReady = false
            local extraMul = 0.40
            if hasGate(attacker, "gate_206_bone_debt") then extraMul = 0.80 end
            if hasGate(attacker, "gate_205_tide") then extraMul = 0.40 end
            if not hasGate(attacker, "gate_205_tide") then
                attacker._spoilBones = math.max(0, (attacker._spoilBones or 0) - 6)
            else
                attacker._spoilTide = true
            end
            if hasGate(attacker, "gate_103_bone_market") and attacker.attrs then
                local lost = math.max(0, maxHpOf(attacker) - (attacker.hp or 0))
                attacker.attrs:heal(lost * 0.04)
                attacker.hp = attacker.attrs:get(AD.HP)
            end
            if hasGate(attacker, "gate_206_bone_debt") and attacker.attrs then
                local cur = attacker.hp or attacker.attrs:get(AD.HP) or 0
                attacker.attrs:takeDamage(cur * 0.03)
                attacker.hp = attacker.attrs:get(AD.HP)
            end
            local extra = extraHitPct(attacker) * extraMul
            if extra > 0 then
                dealDmgFn(target, extra, not isAlly, "拾骸 ", { 200, 160, 90 }, {
                    instantDamage = true,
                })
            end
            if attacker.attrs then
                attacker.attrs:removeModifier("gate_spoil_spd")
                local n = attacker._spoilBones or 0
                if n > 0 then
                    attacker.attrs:addModifier("gate_spoil_spd", {
                        { key = AD.ATK_SPEED, flat = n * 1.2 },
                    })
                end
            end
        end
    elseif id == CC.RIFT and (attacker._riftLeft or 0) > 0 and target then
        local add = hasGate(attacker, "gate_209_mass") and 0.7 or 1
        if hasGate(attacker, "gate_209_mass") then
            -- 群缝：给全体敌人加层，由调用方 enemies 不在此；退化为当前目标 *1
            target._riftStacks = math.min(5, (target._riftStacks or 0) + add)
        else
            target._riftStacks = math.min(5, (target._riftStacks or 0) + 1)
        end
        if hasGate(attacker, "gate_105_offset") and (target._riftStacks or 0) >= 3 and dealDmgFn then
            local mag = extraHitPct(attacker) * 0.60
            dealDmgFn(target, mag, not isAlly, "错位 ", { 140, 100, 200 }, { instantDamage = true })
            target._riftStacks = 0
        end
        if hasGate(attacker, "gate_106_deep") and attacker.attrs then
            local cycle = { AD.ATK_FIRE, AD.ATK_ICE, AD.ATK_LIGHTNING, AD.ATK_SHADOW }
            attacker._riftCycle = (attacker._riftCycle or 1)
            local nxt = cycle[attacker._riftCycle]
            if hasGate(attacker, "gate_211_choose") then
                -- 择缝：锁暗影（对多数甲不亏）
                nxt = AD.ATK_SHADOW
            else
                attacker._riftCycle = (attacker._riftCycle % 4) + 1
                if hasGate(attacker, "gate_212_burst") and dealDmgFn then
                    dealDmgFn(target, extraHitPct(attacker), not isAlly, "爆缝 ", { 180, 80, 200 }, { instantDamage = true })
                end
            end
            attacker.attrs.atkType = nxt
            attacker.atkType = nxt
        end
    elseif id == CC.MASK then
        if hasGate(attacker, "gate_219_lethal") and result.isCrit and not attacker._lethalUsed then
            attacker.atkProgress = 1.0
            attacker._lethalUsed = true
        end
        if attacker._gateWarPrayHit and attacker.attrs then
            attacker.attrs:removeModifier("gate_war_pray")
            attacker._gateWarPrayHit = nil
        end
    end
    if attacker._gateWarPrayHit and attacker.attrs then
        attacker.attrs:removeModifier("gate_war_pray")
        attacker._gateWarPrayHit = nil
    end
end

---@param deadEnemy table
---@param allies table[]
function CGR.onEnemyDeath(deadEnemy, allies)
    for _, ally in ipairs(allies or {}) do
        if (ally.hp or 0) > 0 then
            local id = cid(ally)
            if id == CC.SPOIL then
                local gain = 1
                if hasGate(ally, "gate_207_weapon_master") or hasGate(ally, "adv_207_weapon_master") then
                    -- 双械：骸骨获取 -30%，用 70% 概率代替分数骨
                    if math.random() > 0.70 then gain = 0 end
                end
                if hasGate(ally, "gate_208_peelchain") then
                    gain = gain + (ally._spoilChain or 0)
                end
                if deadEnemy and (deadEnemy.isBoss or deadEnemy.isElite) and hasGate(ally, "gate_104_peel") then
                    gain = gain + 3
                end
                local cap = ally._spoilCap or 12
                local n = math.min(cap, (ally._spoilBones or 0) + gain)
                ally._spoilBones = n
                if n >= cap then ally._spoilReady = true end
                if ally.attrs then
                    ally.attrs:addModifier("gate_spoil_spd", {
                        { key = AD.ATK_SPEED, flat = n * 1.2 },
                    })
                end
            elseif id == CC.MASK then
                ally._maskWindow = 3
                ally._maskArmorStrike = true
                ally._maskTarget = nil
                if hasGate(ally, "gate_110_stripface") then
                    ally._maskSplash = 2
                end
            end
        end
    end
end

---@param dt number
---@param allies table[]
---@param enemies table[]
---@param ctx table|nil { dealDamage: fun }
function CGR.update(dt, allies, enemies, ctx)
    local dealDmg = ctx and ctx.dealDamage
    local TM = require("systems.ThreatManager")

    for _, u in ipairs(allies or {}) do
        if (u._gateDebtT or 0) > 0 then
            u._gateDebtT = u._gateDebtT - dt
            if u._gateDebtT <= 0 then
                local healer = u._gateDeferHealer
                if healer and hasGate(healer, "gate_112_confess") then
                    local taken = u._gateDebtTaken or 0
                    local healAmt = taken * 0.10
                    if hasGate(healer, "gate_223_pardon") then healAmt = healAmt * 3 end
                    local cap = maxHpOf(u) * 0.20
                    healAmt = math.min(healAmt, cap)
                    for _, ally in ipairs(allies or {}) do
                        if (ally.hp or 0) > 0 and ally.attrs then
                            ally.attrs:heal(healAmt)
                            ally.hp = ally.attrs:get(AD.HP)
                        end
                    end
                end
                local src = u._gateDeferHealer
                if src then src._deferCount = math.max(0, (src._deferCount or 1) - 1) end
                u._gateDebtT = nil
                u._gateDebtTaken = nil
            end
        end

        local id = cid(u)
        if (u.hp or 0) <= 0 then goto cont end

        if id == CC.SEAL then
            local stored = u._gateStored or 0
            local cap = u._gateCap or (maxHpOf(u) * 0.12)
            if hasGate(u, "gate_102_sluice") and stored >= cap and stored > 0 then
                local TM = require("systems.ThreatManager")
                TM.forceTarget(u, 2.0)
                local dump = stored * 0.30
                u._gateStored = stored - dump
                stored = u._gateStored
                if hasGate(u, "gate_204_recoil") then
                    u.atkProgress = math.min(1, (u.atkProgress or 0) + 0.40)
                end
            end
            if stored > 0 then
                local rel = stored * 0.20 * dt
                u._gateStored = math.max(0, stored - rel)
                local ratio = u._gateEnemyRatio or 0.30
                local skipSelf = hasGate(u, "gate_203_deadgate") or hasGate(u, "gate_201_seal_strip")
                local toEnemy = rel * ratio
                local toSelf = skipSelf and 0 or (rel * (1 - ratio))
                if toSelf > 0 and u.attrs then
                    u.attrs:takeDamage(toSelf)
                    u.hp = u.attrs:get(AD.HP)
                end
                if toEnemy > 0 and dealDmg then
                    local tgt = nil
                    for _, e in ipairs(enemies or {}) do
                        if (e.hp or 0) > 0 then tgt = e; break end
                    end
                    if tgt then
                        dealDmg(tgt, toEnemy, false, "门缝 ", { 160, 140, 200 }, {
                            instantDamage = true, noCounter = true,
                        })
                    end
                end
            end
        elseif id == CC.SPOIL then
            if u._spoilTide then
                u._spoilBones = math.max(0, (u._spoilBones or 0) - dt)
                if (u._spoilBones or 0) <= 0 then u._spoilTide = false end
            end
        elseif id == CC.RIFT then
            if (u._riftLeft or 0) > 0 then
                u._riftLeft = u._riftLeft - dt
            else
                local cdNeed = hasGate(u, "gate_105_offset") and 6 or 8
                u._riftCd = (u._riftCd or cdNeed) - dt
                if u._riftCd <= 0 then
                    u._riftCd = cdNeed
                    u._riftLeft = 4
                end
            end
        elseif id == CC.ECHO then
            local q = u._echoQueue
            if q and dealDmg then
                local i = 1
                while i <= #q do
                    local job = q[i]
                    job.t = job.t - dt
                    if job.t <= 0 then
                        local tgt = job.target
                        if tgt and (tgt.hp or 0) > 0 then
                            local dmg = job.dmg
                            if job.crit and u.attrs then
                                local cr = u.attrs:get(AD.CRIT_RATE) or 0
                                if hasGate(u, "gate_214_eye") or math.random() * 100 < cr * 0.40 then
                                    dmg = dmg * (1 + (u.attrs:get(AD.CRIT_DMG) or 100) / 100)
                                end
                            end
                            dealDmg(tgt, dmg, false, "回响 ", { 180, 210, 160 }, {
                                instantDamage = true, threatScale = 0.10,
                            })
                            TM.addThreat(u, dmg * 0.10)
                            if hasGate(u, "gate_213_wind") and u.attrs then
                                u._windEcho = math.min(3, (u._windEcho or 0) + 1)
                                u.attrs:addModifier("gate_wind_echo", {
                                    { key = AD.ATK_SPEED, flat = 12 * u._windEcho },
                                })
                            end
                        end
                        table.remove(q, i)
                    else
                        i = i + 1
                    end
                end
            end
        elseif id == CC.MASK then
            u._maskStill = (u._maskStill or 0) + dt
            if hasGate(u, "gate_218_thousand") and u._maskStill >= 5 and u.attrs then
                u.attrs:addModifier("gate_thousand", { { key = AD.ATK_SPEED, flat = 40 } })
            end
            if (u._maskWindow or 0) > 0 then
                u._maskWindow = u._maskWindow - dt
                if not u._maskTarget then
                    for _, e in ipairs(enemies or {}) do
                        if (e.hp or 0) > 0 then
                            u._maskTarget = e
                            break
                        end
                    end
                end
                if u._maskWindow <= 0 then
                    u._maskWindow = 0
                end
            end
            if (u._maskSplash or 0) > 0 then
                u._maskSplash = u._maskSplash - dt
                for _, e in ipairs(enemies or {}) do
                    if (e.hp or 0) > 0 then e._maskFace = true end
                end
                if u._maskSplash <= 0 then u._maskSplash = nil end
            end
        elseif id == CC.DEBT then
            if (u._punishReady or 0) > 0 and dealDmg and math.random() < 0.40 then
                local tgt = nil
                for _, e in ipairs(enemies or {}) do
                    if (e.hp or 0) > 0 then tgt = e; break end
                end
                if tgt then
                    dealDmg(tgt, u._punishReady * 3.0, false, "罚忏 ", { 180, 80, 160 }, {
                        instantDamage = true,
                    })
                end
                u._punishReady = nil
            end
        end
        ::cont::
    end
end

return CGR
