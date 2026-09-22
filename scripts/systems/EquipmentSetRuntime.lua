-- ============================================================================
-- EquipmentSetRuntime - 套装 4/6 件战斗被动
-- 2 件属性已由 EquipmentSetSystem.applyToUnit 注入。
-- 司仪袍 6 件不改死亡（拍板：死亡留给职业延缓）→ 改为全队护盾+8%。
-- 万剑门扉飞剑给队友共享，本人不触发。
-- ============================================================================

local AD = require("systems.AttributeDef")
local EquipmentSetSystem = require("systems.EquipmentSetSystem")

local ESR = {}

local function four(unit)
    local f = EquipmentSetSystem.activeHighSets(unit)
    return f
end

local function six(unit)
    local _, s = EquipmentSetSystem.activeHighSets(unit)
    return s
end

---@param unit table
function ESR.onBattleStart(unit, allies)
    if not unit then return end
    unit._setShell = 0
    unit._setFacelessT = 0
    unit._setCrystal = 0
    unit._setSwordWin = 0
    unit._setStarCd = 8
    if six(unit) == "last_rite" and unit.attrs then
        -- 6 件不改死亡：全队护盾加成
        for _, a in ipairs(allies or { unit }) do
            if a.attrs then
                a.attrs:addModifier("set6_last_rite", { { key = AD.ES_BONUS, flat = 8 } })
            end
        end
    end
    if four(unit) == "nitros" and unit.attrs then
        local hit = unit.attrs:get(AD.HIT_VALUE) or 0
        local extra = math.min(10, math.floor(hit / 80) * 2)
        if extra > 0 then
            unit.attrs:addModifier("set4_nitros", { { key = AD.COMBO_RATE, flat = extra } })
        end
    end
    if four(unit) == "starless" and unit.attrs then
        unit.attrs:addModifier("set4_starless", { { key = AD.MAG_PEN, flat = 8 } })
    end
    unit._setGamble = 0
    unit._setEmber = nil
end

--- 叠甲虫壳 4 件减伤
---@param target table
---@param damage number
---@return number
function ESR.onIncoming(target, damage, source)
    if four(target) == "carapace" then
        target._setShell = math.min(8, (target._setShell or 0) + 1)
        local red = 1 - (target._setShell * 0.015)
        damage = damage * red
    end
    if target._setEmber then
        damage = damage * 1.08
    end
    return damage
end

--- 格挡后：铁壁 4/6
---@param target table
---@param attacker table|nil
---@param blockedAmount number
---@param dealDmgFn function|nil
function ESR.onBlocked(target, attacker, blockedAmount, dealDmgFn)
    if four(target) ~= "ironwall" then return end
    if target.attrs then
        local heal = (target.maxHp or target.attrs:get(AD.MAX_HP) or 0) * 0.01
        if heal > 0 then
            target.attrs:heal(heal)
            target.hp = target.attrs:get(AD.HP)
        end
    end
    if six(target) == "ironwall" and attacker and dealDmgFn and (blockedAmount or 0) > 0 then
        dealDmgFn(attacker, blockedAmount * 0.30, true, "铁壁 ", { 180, 160, 120 }, {
            instantDamage = true, noCounter = true,
        })
    end
end

---@param attacker table
---@param defender table
---@param result table
---@param isAlly boolean
---@param dealDmgFn function|nil
---@param targetList table[]|nil
function ESR.onAfterAttack(attacker, defender, result, isAlly, dealDmgFn, targetList)
    if not attacker or not result or result.isMiss then return end
    local f, s = four(attacker), six(attacker)

    if f == "faceless" and defender and defender.maxHp and defender.hp then
        if defender.hp / math.max(1, defender.maxHp) < 0.5 and result.totalDamage then
            -- 4 件低血暴伤：下一次结算已过，用追加段近似 25%
            if dealDmgFn and defender.hp > 0 then
                dealDmgFn(defender, result.totalDamage * 0.25, not isAlly, "无面 ", { 180, 180, 200 }, {
                    instantDamage = true,
                })
            end
        end
    end

    if s == "faceless" and (attacker._setFacelessT or 0) > 0 then
        attacker._setFacelessT = 0
        local TM = require("systems.ThreatManager")
        TM.clearThreat(attacker)
    end

    if f == "riftcrystal" and defender and math.random() < 0.15 then
        defender._crystal = math.min(5, (defender._crystal or 0) + 1)
        if s == "riftcrystal" and defender._crystal >= 5 and dealDmgFn and attacker.attrs then
            local mag = (attacker.attrs:get(AD.MAG_ATK) or 0) * 0.80
            dealDmgFn(defender, mag, not isAlly, "晶碎 ", { 120, 200, 230 }, { instantDamage = true })
            defender.atkProgress = math.max(0, (defender.atkProgress or 0) - (defender.isBoss and 0.2 or 0.6))
            defender._crystal = 0
        end
    end

    if f == "tidepress" and dealDmgFn and targetList and math.random() < 0.30 then
        local other = nil
        for _, t in ipairs(targetList) do
            if t ~= defender and (t.hp or 0) > 0 then other = t; break end
        end
        if other then
            local dmg = (result.totalDamage or 0) * 0.35
            dealDmgFn(other, dmg, not isAlly, "水脉 ", { 80, 180, 210 }, { instantDamage = true })
            if s == "tidepress" then
                other.atkProgress = math.max(0, (other.atkProgress or 0) - 0.20)
            end
        end
    end

    if s == "nitros" and result.comboCount and result.comboCount > 0 and dealDmgFn and targetList then
        local second = nil
        local n = 0
        for _, t in ipairs(targetList) do
            if (t.hp or 0) > 0 then
                n = n + 1
                if t ~= defender and not second then second = t end
            end
        end
        if second then
            dealDmgFn(second, (result.totalDamage or 0) * 0.50, not isAlly, "硝烟 ", { 230, 120, 60 }, {
                instantDamage = true,
            })
        elseif n <= 1 and attacker.attrs then
            attacker.attrs:addModifier("set6_nitros_spd", { { key = AD.ATK_SPEED, flat = 12 } })
            attacker._setNitroT = 2
        end
    end

    if f == "emberscout" and defender then
        defender._setEmber = 2
        defender._setEmberSrc = attacker
    end

    if f == "gambler" and attacker.attrs then
        if result.isCrit then
            attacker._setGamble = 0
            attacker.attrs:removeModifier("set4_gamble")
            if s == "gambler" and dealDmgFn and defender then
                dealDmgFn(defender, (result.totalDamage or 0) * 0.30, not isAlly, "残响 ", { 200, 80, 110 }, {
                    instantDamage = true,
                })
            end
        else
            attacker._setGamble = math.min(3, (attacker._setGamble or 0) + 1)
            attacker.attrs:addModifier("set4_gamble", {
                { key = AD.CRIT_RATE, flat = 6 * attacker._setGamble },
            })
            if s == "gambler" and attacker.attrs then
                local lost = math.max(0, (attacker.maxHp or 0) - (attacker.hp or 0))
                attacker.attrs:heal(lost * 0.01)
                attacker.hp = attacker.attrs:get(AD.HP)
            end
        end
    end

    if f == "bonehunger" and attacker.attrs then
        local hp = attacker.hp or attacker.attrs:get(AD.HP) or 1
        local mx = attacker.maxHp or attacker.attrs:get(AD.MAX_HP) or 1
        if hp / math.max(1, mx) < 0.70 then
            attacker.attrs:addModifier("set4_bonehunger", { { key = AD.ATK_SPEED, flat = 8 } })
        else
            attacker.attrs:removeModifier("set4_bonehunger")
        end
    end

    if s == "carapace" and (attacker._setShell or 0) >= 8 then
        local layers = attacker._setShell
        attacker._setShell = 0
        if dealDmgFn and defender then
            dealDmgFn(defender, (result.totalDamage or 0) * layers * 0.02, not isAlly, "虫壳 ", { 200, 140, 60 }, {
                instantDamage = true,
            })
        end
        local TM = require("systems.ThreatManager")
        TM.forceTarget(attacker, 2.0)
    end
end

---@param healer table
---@param target table
---@param overheal number
function ESR.onOverheal(healer, target, overheal)
    if four(healer) == "last_rite" and target and target.attrs and overheal > 0 then
        local add = overheal * 0.20
        target.attrs.energyShield = (target.attrs.energyShield or 0) + add
    end
end

---@param deadEnemy table
---@param allies table[]
---@param enemies table[]|nil
function ESR.onEnemyDeath(deadEnemy, allies, enemies)
    for _, a in ipairs(allies or {}) do
        if six(a) == "faceless" then
            a._setFacelessT = 4
            local TM = require("systems.ThreatManager")
            TM.clearThreat(a)
        end
        if six(a) == "bonehunger" and a.attrs then
            local mx = a.maxHp or a.attrs:get(AD.MAX_HP) or 0
            a.attrs:heal(mx * 0.03)
            a.hp = a.attrs:get(AD.HP)
        end
    end
    if deadEnemy and deadEnemy._setEmber and six(deadEnemy._setEmberSrc) == "emberscout" then
        local nxt = nil
        for _, e in ipairs(enemies or {}) do
            if e ~= deadEnemy and (e.hp or 0) > 0 then nxt = e; break end
        end
        if nxt then
            nxt._setEmber = 2
            nxt._setEmberSrc = deadEnemy._setEmberSrc
        end
        deadEnemy._setEmber = nil
    end
end

---@param dt number
---@param allies table[]
---@param enemies table[]
---@param ctx table|nil
function ESR.update(dt, allies, enemies, ctx)
    local dealDmg = ctx and ctx.dealDamage
    for _, u in ipairs(allies or {}) do
        if (u._setNitroT or 0) > 0 then
            u._setNitroT = u._setNitroT - dt
            if u._setNitroT <= 0 and u.attrs then
                u.attrs:removeModifier("set6_nitros_spd")
            end
        end
        if (u._setFacelessT or 0) > 0 then
            u._setFacelessT = u._setFacelessT - dt
        end
        if (u._setEmber or 0) > 0 then
            u._setEmber = u._setEmber - dt
            if u._setEmber <= 0 then u._setEmber = nil end
        end
        -- 万剑门扉：光环给队友，穿套本人不飞
        if four(u) == "swordgate" then
            u._setSwordWin = (u._setSwordWin or 0) + dt
            local need = 6
            if u._setSwordWin >= need then
                u._setSwordWin = 0
                local swords = (six(u) == "swordgate") and 2 or 1
                local dmg = (u._setSwordDmgWin or 0) * 0.15
                u._setSwordDmgWin = 0
                if dealDmg and dmg > 0 then
                    for i = 1, swords do
                        local tgt = nil
                        local alive = {}
                        for _, e in ipairs(enemies or {}) do
                            if (e.hp or 0) > 0 then alive[#alive + 1] = e end
                        end
                        if #alive > 0 then
                            tgt = alive[math.random(#alive)]
                            -- 本人不飞：打在随机敌人上，仇恨记在队友最高仇恨者；简化为无仇恨飞剑
                            dealDmg(tgt, dmg, false, "门剑 ", { 200, 200, 220 }, {
                                instantDamage = true, noCounter = true,
                            })
                        end
                    end
                end
            end
        end
        if six(u) == "starless" then
            u._setStarCd = (u._setStarCd or 8) - dt
            if u._setStarCd <= 0 then
                u._setStarCd = 8
                local lowest = nil
                local lp = 2
                for _, e in ipairs(enemies or {}) do
                    if (e.hp or 0) > 0 and e.maxHp then
                        local p = e.hp / math.max(1, e.maxHp)
                        if p < lp then lp = p; lowest = e end
                    end
                end
                if lowest and dealDmg and u.attrs then
                    local mag = (u.attrs:get(AD.MAG_ATK) or 0) * 1.20
                    dealDmg(lowest, mag, false, "无光 ", { 80, 60, 140 }, {
                        instantDamage = true, noCounter = true,
                    })
                end
            end
        end
    end
end

--- 飞剑窗口累计自身伤害
function ESR.addSwordWindowDamage(unit, amount)
    if four(unit) == "swordgate" then
        unit._setSwordDmgWin = (unit._setSwordDmgWin or 0) + (amount or 0)
    end
end

return ESR
