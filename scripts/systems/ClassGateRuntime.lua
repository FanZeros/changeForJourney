-- ============================================================================
-- ClassGateRuntime - 六门契基础职战斗被动（转职 101–224 仍走旧 TalentEffect）
-- seal 门缝 / spoil 拾骸 / rift 裂隙 / echo 回响 / mask 换面 / debt 延缓
-- ============================================================================

local AD = require("systems.AttributeDef")
local CC = require("config.ClassConfig")

local CGR = {}

local function cid(unit)
    return unit and CC.normalize(unit.classId) or nil
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
            u._gateCap = cap
            u._gateStored = 0
            print("[Gate] 封门人 " .. tostring(u.name) .. " 门缝容量=" .. math.floor(cap))
        elseif id == CC.SPOIL then
            u._spoilBones = 0
            u._spoilReady = false
        elseif id == CC.RIFT then
            u._riftCd = 8
            u._riftLeft = 0
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
        return rawArmor * 0.80
    end
    return rawArmor
end

--- 封门人：伤害先写门缝。返回剩余打到血条的量。
---@param target table
---@param damage number
---@return number
function CGR.absorbIncoming(target, damage)
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
    target._gateDefer = false
    target._gateDebtT = 4
    if target.attrs then
        local one = 1
        target.attrs.final[AD.HP] = one
        target.hp = one
    else
        target.hp = 1
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
        return damage * 1.15
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
    target._gateDefer = true
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
        attacker._echoQueue[#attacker._echoQueue + 1] = {
            t = 1.2, target = target, dmg = dmg,
        }
    elseif id == CC.SPOIL then
        if attacker._spoilReady and dealDmgFn and target and (target.hp or 0) > 0 then
            attacker._spoilReady = false
            attacker._spoilBones = math.max(0, (attacker._spoilBones or 0) - 6)
            local extra = extraHitPct(attacker) * 0.40
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
        target._riftStacks = math.min(5, (target._riftStacks or 0) + 1)
    end
end

---@param deadEnemy table
---@param allies table[]
function CGR.onEnemyDeath(deadEnemy, allies)
    for _, ally in ipairs(allies or {}) do
        if (ally.hp or 0) > 0 then
            local id = cid(ally)
            if id == CC.SPOIL then
                local n = math.min(12, (ally._spoilBones or 0) + 1)
                ally._spoilBones = n
                if n >= 12 then ally._spoilReady = true end
                if ally.attrs then
                    ally.attrs:addModifier("gate_spoil_spd", {
                        { key = AD.ATK_SPEED, flat = n * 1.2 },
                    })
                end
            elseif id == CC.MASK then
                ally._maskWindow = 3
                ally._maskArmorStrike = true
                ally._maskTarget = nil
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
            if u._gateDebtT <= 0 then u._gateDebtT = nil end
        end

        local id = cid(u)
        if (u.hp or 0) <= 0 then goto cont end

        if id == CC.SEAL then
            local stored = u._gateStored or 0
            if stored > 0 then
                local rel = stored * 0.20 * dt
                u._gateStored = math.max(0, stored - rel)
                local toEnemy = rel * 0.30
                local toSelf = rel * 0.70
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
        elseif id == CC.RIFT then
            if (u._riftLeft or 0) > 0 then
                u._riftLeft = u._riftLeft - dt
            else
                u._riftCd = (u._riftCd or 8) - dt
                if u._riftCd <= 0 then
                    u._riftCd = 8
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
                            dealDmg(tgt, job.dmg, false, "回响 ", { 180, 210, 160 }, {
                                instantDamage = true, threatScale = 0.10,
                            })
                            TM.addThreat(u, job.dmg * 0.10)
                        end
                        table.remove(q, i)
                    else
                        i = i + 1
                    end
                end
            end
        elseif id == CC.MASK then
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
        end
        ::cont::
    end
end

return CGR
