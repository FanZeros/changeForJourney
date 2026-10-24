-- ============================================================================
-- ClassGateRuntime - 六门契基础职 + 转职 101–224 新效果
-- 旧 adv_* talentId 已从 AdvancementConfig 撤掉，圣光/飞弹等不再触发。
-- 207/220 双持仍走 EquipmentSystem（talentId 未改）。
-- ============================================================================

local AD = require("systems.AttributeDef")
local CC = require("config.ClassConfig")

local CGR = {}

-- 仅 225–230 融合使用；弱键绑定不写入 attrs，因此 clone/存档不会复制旧 owner。
local fusionOwners = setmetatable({}, { __mode = "k" })

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

local function fusionId(unit)
    for id = 225, 230 do
        if hasGate(unit, "gate_" .. id .. "_fusion") then return id end
    end
    return nil
end

local function inList(unit, units)
    for _, candidate in ipairs(units or {}) do if candidate == unit then return true end end
    return false
end

local function formulaOwner(attrsOrUnit)
    local binding = attrsOrUnit and fusionOwners[attrsOrUnit]
    if binding and binding.unit.attrs == attrsOrUnit
        and binding.unit._fusionToken == binding.token then
        return binding.unit
    end
    return attrsOrUnit
end

local function validFusionDefer(unit)
    local healer = unit and unit._gateDeferHealer
    return healer and fusionId(healer) == 230 and unit._fusionDeferToken ~= nil
        and healer._fusionToken == unit._fusionDeferToken
end

local function clearFusionDefer(unit)
    if not unit or not unit._fusionDeferToken then return end
    unit._gateDefer, unit._gateDeferHealer, unit._gateDeferChance = nil, nil, nil
    unit._gateDebtT, unit._gateDebtTaken, unit._gateWarPray = nil, nil, nil
    unit._gateWarPrayHit, unit._fusionDeferToken = nil, nil
end

local function clearStrip(target)
    if not target then return end
    if target.attrs then target.attrs:removeModifier("gate_fusion_strip") end
    target._fusionStripT, target._fusionStripSource, target._fusionStripToken = nil, nil, nil
end

--- 仅清融合本场状态；reset/start 在替换战线引用前调用，不扫别的并行队伍。
---@param allies table[]|nil
---@param enemies table[]|nil
function CGR.resetFusionBattle(allies, enemies)
    for _, units in ipairs({ allies or {}, enemies or {} }) do
        for _, u in ipairs(units) do
            clearFusionDefer(u)
            if u._fusionStripT then clearStrip(u) end
            if u._fusionToken then
                if u.attrs then
                    fusionOwners[u.attrs] = nil
                    u.attrs:removeModifier("gate_spoil_spd")
                    u.attrs:removeModifier("gate_fusion_borrow")
                    if u._fusionBaseAtkType then u.attrs.atkType = u._fusionBaseAtkType end
                end
                if u._fusionBaseAtkType then u.atkType = u._fusionBaseUnitAtkType end
                for target in pairs(u._fusionStripTargets or {}) do
                    if target._fusionStripSource == u then clearStrip(target) end
                end
                for target in pairs(u._fusionDeferTargets or {}) do
                    if target._gateDeferHealer == u then clearFusionDefer(target) end
                end
                for target in pairs(u._fusionRiftTargets or {}) do
                    if target._fusionRiftSource == u then
                        target._riftStacks, target._fusionRiftSource = nil, nil
                    end
                end
                u._gateCap, u._gateStored, u._gateEnemyRatio = nil, nil, nil
                u._spoilBones, u._spoilReady, u._spoilCap, u._spoilLastTarget = nil, nil, nil, nil
                u._riftCd, u._riftLeft, u._riftCycle = nil, nil, nil
                u._echoQueue = nil
                u._maskTarget, u._maskWindow, u._maskArmorStrike = nil, nil, nil
                u._fusionBorrowT, u._fusionBorrowLeech = nil, nil
                u._deferCount = nil
                u._fusionStripTargets, u._fusionDeferTargets, u._fusionRiftTargets = nil, nil, nil
                u._fusionBaseAtkType, u._fusionBaseUnitAtkType, u._fusionToken = nil, nil, nil
            end
        end
    end
end

local function grantBorrow(unit, target)
    if fusionId(unit) ~= 229 or not hasGate(unit, "gate_109_borrow")
        or not target or (target.hp or 0) <= 0 then return end
    local atkType = target.attrs and target.attrs.atkType or target.atkType
    unit._fusionBorrowLeech = AD.getAtkCategory(atkType) == "healing"
    -- 治疗目标只等待下一次实际扣血普攻；4秒仅限非治疗目标的攻速。
    unit._fusionBorrowT = not unit._fusionBorrowLeech and 4 or nil
    if unit.attrs then
        unit.attrs:removeModifier("gate_fusion_borrow")
        if not unit._fusionBorrowLeech then
            unit.attrs:addModifier("gate_fusion_borrow", { { key = AD.ATK_SPEED, flat = 8 } })
        end
    end
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
    CGR.resetFusionBattle(allies, enemies)
    for _, u in ipairs(allies or {}) do
        if fusionId(u) then
            u._fusionToken = {}
            if u.attrs then
                fusionOwners[u.attrs] = { unit = u, token = u._fusionToken }
                u._fusionBaseAtkType = u.attrs.atkType
                u._fusionBaseUnitAtkType = u.atkType
            end
        end
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
            grantBorrow(u, t)
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
    attacker, defender = formulaOwner(attacker), formulaOwner(defender)
    local id = cid(attacker)
    if fusionId(attacker) == 229 and attacker._maskTarget and defender == attacker._maskTarget.attrs then
        defender = attacker._maskTarget
    end
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
    attacker = formulaOwner(attacker)
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
    if target and target._fusionDeferToken and not validFusionDefer(target) then
        clearFusionDefer(target)
        return false
    end
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
    if target and target._fusionDeferToken and not validFusionDefer(target) then
        clearFusionDefer(target)
    end
    if target and (target._gateDebtT or 0) > 0 then
        local out = damage * 1.15
        target._gateDebtTaken = (target._gateDebtTaken or 0) + out
        return out
    end
    return damage
end

--- 普攻入口在 TAL 调用；附伤已经由 BC 调 absorb/applyDebt，不能在这里重复接线。
function CGR.modifyFusionIncoming(target, damage)
    if validFusionDefer(target) then damage = CGR.applyDebtTaken(target, damage) end
    if fusionId(target) == 225 and target._fusionToken then
        damage = CGR.absorbIncoming(target, damage)
    end
    return damage
end

function CGR.tryFusionDeferDeath(target)
    return validFusionDefer(target) and CGR.tryDeferDeath(target) or false
end

--- 过量治疗 → 延缓层（每人 1 层）
---@param healer table
---@param target table
---@param overheal number
function CGR.onOverheal(healer, target, overheal)
    if cid(healer) ~= CC.DEBT then return end
    if not target or overheal <= 0 then return end
    if fusionId(healer) == 230 then
        if not healer._fusionToken then return end
        healer._fusionDeferTargets = healer._fusionDeferTargets or {}
        local count = 0
        for unit in pairs(healer._fusionDeferTargets) do
            if validFusionDefer(unit) and (unit.hp or 0) > 0
                and (unit._gateDefer or (unit._gateDebtT or 0) > 0) then
                count = count + 1
            else
                clearFusionDefer(unit)
                healer._fusionDeferTargets[unit] = nil
            end
        end
        healer._deferCount = count
        if validFusionDefer(target) and (target._gateDebtT or 0) > 0 then return end
    end
    local cap = hasGate(healer, "gate_111_defer2") and 2 or 1
    healer._deferCount = healer._deferCount or 0
    if target._gateDefer then return end
    if healer._deferCount >= cap then return end
    target._gateDefer = true
    target._gateDeferHealer = healer
    target._gateWarPray = hasGate(healer, "gate_221_war")
    target._gateDeferChance = hasGate(healer, "gate_222_blood") and 0.40 or 1
    healer._deferCount = healer._deferCount + 1
    if fusionId(healer) == 230 then
        target._fusionDeferToken = healer._fusionToken
        healer._fusionDeferTargets[target] = true
    end
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

-- 226 仅骸骨额击改选；不调用 CF.calcAttack/TM.selectTarget，避免消耗普攻 RNG。
-- 优势以正式 AD 基础克制表 >1 定义；倍率并列保留原目标，否则列表顺序稳定择首。
local function spoilExtraTarget(attacker, target, targets)
    if fusionId(attacker) ~= 226 or not hasGate(attacker, "gate_104_peel") then return target end
    local function valid(unit)
        return unit and (unit.hp or 0) > 0 and unit.attrs and unit.attrs:isAlive()
            and not unit.artifactUntargetable
    end
    local atkType = attacker.attrs and attacker.attrs.atkType or attacker.atkType
    local best = valid(target) and target or nil
    local bestMult = best and AD.getTypeMult(atkType, best.attrs.armorType or best.armorType) or 1
    bestMult = math.max(1, bestMult)
    for _, unit in ipairs(targets or {}) do
        if valid(unit) then
            local mult = AD.getTypeMult(atkType, unit.attrs.armorType or unit.armorType)
            if mult > bestMult then best, bestMult = unit, mult end
            if not best then best = unit end
        end
    end
    return best
end

---@param attacker table
---@param target table
---@param result table
---@param isAlly boolean
---@param dealDmgFn function
---@param allies table[]|nil
---@param targets table[]|nil
function CGR.onAfterAttack(attacker, target, result, isAlly, dealDmgFn, allies, targets)
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
            token = fusionId(attacker) == 228 and attacker._fusionToken or nil,
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
        local extraTarget = target
        if attacker._spoilReady and fusionId(attacker) == 226 then
            extraTarget = spoilExtraTarget(attacker, target, targets)
        end
        if attacker._spoilReady and dealDmgFn and extraTarget and (extraTarget.hp or 0) > 0 then
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
                dealDmgFn(extraTarget, extra, not isAlly, "拾骸 ", { 200, 160, 90 }, {
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
        if fusionId(attacker) == 227 then
            attacker._fusionRiftTargets = attacker._fusionRiftTargets or {}
            attacker._fusionRiftTargets[target] = true
            target._fusionRiftSource = attacker
        end
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
        -- 借面只消费一次实际普攻扣血；miss/全盾不消费，也不从额伤或连击另计吸血。
        if fusionId(attacker) == 229 and attacker._fusionBorrowLeech
            and (result.actualDamage or 0) > 0
            and (attacker.hp or 0) > 0 and attacker.attrs then
            attacker.attrs:heal(result.actualDamage * 0.08)
            attacker.hp = attacker.attrs:get(AD.HP)
            attacker._fusionBorrowLeech = false
        end
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

-- 邻域: [不受影响] [i-1 削甲] [i 死亡复制目标] [i+1 削甲] [不受影响]
-- 只用本战线原列表相邻槽位，不穿越空槽/死者，不触碰其他队。
-- ARMOR=PHYS_ARMOR；MAG_ARMOR 是护盾别名。pct=-20 为百分点，刷新同 id 不叠加。
local function stripNeighbors(source, deadEnemy, enemies)
    local index
    for i, enemy in ipairs(enemies or {}) do
        if enemy == deadEnemy then index = i; break end
    end
    if not index then return end
    source._fusionStripTargets = source._fusionStripTargets or {}
    for _, i in ipairs({ index - 1, index + 1 }) do
        local target = enemies[i]
        if target and (target.hp or 0) > 0 and target.attrs and not target.artifactUntargetable then
            target.attrs:addModifier("gate_fusion_strip", { { key = AD.ARMOR, pct = -20 } })
            target._fusionStripT, target._fusionStripSource, target._fusionStripToken = 2, source, source._fusionToken
            source._fusionStripTargets[target] = true
        end
    end
end

---@param deadEnemy table
---@param allies table[]
---@param enemies table[]|nil
function CGR.onEnemyDeath(deadEnemy, allies, enemies)
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
                local isFusion = fusionId(ally) == 229
                if not isFusion or ally._maskTarget == deadEnemy then
                    if isFusion and hasGate(ally, "gate_110_stripface") then
                        stripNeighbors(ally, deadEnemy, enemies)
                    end
                    ally._maskWindow = 3
                    ally._maskArmorStrike = true
                    ally._maskTarget = nil
                    if hasGate(ally, "gate_110_stripface") and not isFusion then
                        ally._maskSplash = 2
                    end
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
    local function periodicDamage(source, target, damage, isTargetAlly, prefix, color, opts)
        if fusionId(source) then
            if ctx and ctx.dealTalentDamage then
                return ctx.dealTalentDamage(source, target, damage, isTargetAlly, prefix, color, opts)
            end
            if dealDmg then return dealDmg(target, damage, isTargetAlly, prefix, color, source, opts) end
        elseif dealDmg then
            -- 原非融合六参口径不改；融合明确保留伤害来源并把 opts 放到 meta。
            return dealDmg(target, damage, isTargetAlly, prefix, color, opts)
        end
    end
    local TM = require("systems.ThreatManager")

    for _, target in ipairs(enemies or {}) do
        if target._fusionStripT then
            local source = target._fusionStripSource
            target._fusionStripT = target._fusionStripT - dt
            if target._fusionStripT <= 0 or (target.hp or 0) <= 0
                or not source or source._fusionToken ~= target._fusionStripToken then
                clearStrip(target)
                if source and source._fusionStripTargets then source._fusionStripTargets[target] = nil end
            end
        end
    end

    for _, u in ipairs(allies or {}) do
        if u._fusionDeferToken and (not validFusionDefer(u) or (u.hp or 0) <= 0) then
            local healer = u._gateDeferHealer
            if healer and healer._fusionDeferTargets then
                healer._fusionDeferTargets[u] = nil
                healer._deferCount = math.max(0, (healer._deferCount or 1) - 1)
            end
            clearFusionDefer(u)
        end
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
                if u._fusionDeferToken then
                    if src and src._fusionDeferTargets then src._fusionDeferTargets[u] = nil end
                    clearFusionDefer(u)
                end
            end
        end

        local id = cid(u)
        if (u.hp or 0) <= 0 then
            if fusionId(u) == 228 then u._echoQueue = {} end
            if fusionId(u) == 229 then
                u._fusionBorrowT, u._fusionBorrowLeech = nil, nil
                if u.attrs then u.attrs:removeModifier("gate_fusion_borrow") end
            end
            if fusionId(u) == 227 and u._fusionBaseAtkType and u.attrs then
                u.attrs.atkType, u.atkType = u._fusionBaseAtkType, u._fusionBaseUnitAtkType
                u._riftLeft = 0
            end
            goto cont
        end

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
                        periodicDamage(u, tgt, toEnemy, false, "门缝 ", { 160, 140, 200 }, {
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
                if u._riftLeft <= 0 and fusionId(u) == 227 and u.attrs and u._fusionBaseAtkType then
                    u.attrs.atkType, u.atkType = u._fusionBaseAtkType, u._fusionBaseUnitAtkType
                end
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
                    local current = fusionId(u) ~= 228 or
                        (job.token == u._fusionToken and inList(job.target, enemies)
                            and (job.target.hp or 0) > 0 and not job.target.artifactUntargetable)
                    if not current then job.t = 0 end
                    if job.t <= 0 then
                        local tgt = job.target
                        if current and tgt and (tgt.hp or 0) > 0 then
                            local dmg = job.dmg
                            if job.crit and u.attrs then
                                local cr = u.attrs:get(AD.CRIT_RATE) or 0
                                if hasGate(u, "gate_214_eye") or math.random() * 100 < cr * 0.40 then
                                    dmg = dmg * (1 + (u.attrs:get(AD.CRIT_DMG) or 100) / 100)
                                end
                            end
                            periodicDamage(u, tgt, dmg, false, "回响 ", { 180, 210, 160 }, {
                                instantDamage = true, threatScale = 0.10,
                            })
                            if fusionId(u) ~= 228 then TM.addThreat(u, dmg * 0.10) end
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
            if (u._fusionBorrowT or 0) > 0 then
                u._fusionBorrowT = u._fusionBorrowT - dt
                if u._fusionBorrowT <= 0 then
                    u._fusionBorrowT = nil
                    if u.attrs then u.attrs:removeModifier("gate_fusion_borrow") end
                end
            end
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
                            grantBorrow(u, e)
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

-- 仅将司仪路径纳入纯治疗审计；其他职业即使当前为神圣类型，
-- 仍可能储存伤害、改变攻击类型或创建延迟攻击。
local DEFENSIVE_DEBT_ADV = {
    gate_debt_defer = true, gate_111_defer2 = true, gate_112_confess = true,
    gate_221_war = true, gate_222_blood = true, gate_223_pardon = true,
    gate_230_fusion = true,
    adv_111_inspire = true, adv_112_group_heal = true,
    adv_221_war_ritual = true, adv_222_blood_ritual = true, adv_223_divine_blessing = true,
    adv_101_holy_light = true, adv_201_advanced_holy = true,
    adv_202_praise_blessing = true, adv_203_cross_shield = true,
}

---@param unit table
---@return boolean provenNone
---@return string reason
function CGR.inspectHealerOffense(unit)
    if type(unit) ~= "table" or CC.normalize(unit.classId) ~= CC.DEBT then
        return false, "class_not_audited_debt"
    end
    if unit._echoQueue ~= nil and (type(unit._echoQueue) ~= "table" or next(unit._echoQueue) ~= nil) then
        return false, "class_pending_echo"
    end
    if unit._punishReady ~= nil and unit._punishReady ~= 0 then return false, "class_pending_punish" end
    if unit._gateStored ~= nil and unit._gateStored ~= 0 then return false, "class_stored_damage" end
    if unit.advTalentIds ~= nil then
        if type(unit.advTalentIds) ~= "table" then return false, "class_unknown_adv" end
        for _, talentId in pairs(unit.advTalentIds) do
            if talentId == "gate_224_punish" or talentId == "adv_224_divine_punishment" then
                return false, "class_punishment_potential"
            end
            if not DEFENSIVE_DEBT_ADV[talentId] then return false, "class_unknown_adv" end
        end
    end
    return true, "class_debt_none"
end

return CGR
