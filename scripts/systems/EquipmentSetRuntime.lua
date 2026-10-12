-- ============================================================================
-- EquipmentSetRuntime - 套装 4/6 件战斗被动
-- 2 件属性已由 EquipmentSetSystem.applyToUnit 注入。
-- 高阶效果统一读取 EquipmentSetConfig；不扩大触发概率、阈值或层数。
-- ============================================================================

local AD = require("systems.AttributeDef")
local ESC = require("config.EquipmentSetConfig")
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

local function effectMeta(setId, category, noThreat)
    return { instantDamage = true, noCounter = true, noThreat = noThreat or false,
        category = category, critEligible = false, setId = setId }
end

local function modifierMatches(attrs, id, key, flat)
    local entries = attrs.modifiers and attrs.modifiers[id]
    return entries and #entries == 1 and entries[1].key == key
        and entries[1].flat == flat and (entries[1].pct or 0) == 0
end

--- 只应用确定性的四件属性；同 id 覆盖，换套/跌破阈值清旧值。
--- 调用顺序与实战一致：装备和两件属性之后，神器属性之前。
---@param attrs table|nil
---@return table|nil
function ESR.applyStaticBonuses(attrs)
    if not attrs then return attrs end
    local nitros = ESC.SETS.nitros.effect4
    local extra = attrs._setFour == "nitros"
        and math.min(nitros.comboCap, math.floor(math.max(0, attrs:get(AD.HIT_VALUE)) / nitros.hitStep)
            * nitros.comboPerStep) or 0
    if extra > 0 then
        if not modifierMatches(attrs, "set4_nitros", AD.COMBO_RATE, extra) then
            attrs:addModifier("set4_nitros", { { key = AD.COMBO_RATE, flat = extra } })
        end
    else
        attrs:removeModifier("set4_nitros")
    end
    if attrs._setFour == "starless" then
        local pen = ESC.SETS.starless.effect4.magPen
        if not modifierMatches(attrs, "set4_starless", AD.MAG_PEN, pen) then
            attrs:addModifier("set4_starless", { { key = AD.MAG_PEN, flat = pen } })
        end
    else
        attrs:removeModifier("set4_starless")
    end
    return attrs
end

local function teamKey(unit)
    -- 不带队号的旧战斗/调用方传入的是同一队；显式队号绝不串队。
    return tonumber(unit.teamIdx) or unit.teamIdx or "unassigned"
end

--- 同队司仪袍六件光环，不叠加；需要变化时先克隆 attrs，保护复用快照。
--- 不执行计时器、条件被动或重置运行态。
---@param units table[]|nil
---@return table[]|nil
function ESR.applyTeamAura(units)
    local activeTeams = {}
    for _, unit in ipairs(units or {}) do
        if six(unit) == "last_rite" then activeTeams[teamKey(unit)] = true end
    end
    local bonus = ESC.SETS.last_rite.effect6.teamShieldBonus
    for _, unit in ipairs(units or {}) do
        local attrs = unit.attrs
        if attrs then
            local active = activeTeams[teamKey(unit)]
            local existing = attrs.modifiers and attrs.modifiers.set6_last_rite
            if (active and not modifierMatches(attrs, "set6_last_rite", AD.ES_BONUS, bonus))
                or (not active and existing) then
                unit.attrs = attrs:clone()
                if active then
                    unit.attrs:addModifier("set6_last_rite", { { key = AD.ES_BONUS, flat = bonus } })
                else
                    unit.attrs:removeModifier("set6_last_rite")
                end
            end
        end
    end
    return units
end

--- 清理本场套装运行态；不移除装备属性、永久成长或英雄库存。
---@param unit table
---@param preserveTempShield boolean|nil 已清过新场边界后初始化套装时保留新开战天赋盾
function ESR.resetBattleState(unit, preserveTempShield)
    if not unit then return end
    unit._setShell = 0
    unit._setFacelessT = 0
    unit._crystal = 0
    unit._setCrystal = 0
    unit._setSwordWin = 0
    unit._setSwordDmgWin = 0
    unit._setStarCd = ESC.SETS.starless.effect6.interval
    unit._setNitroT = 0
    unit._setGamble = 0
    unit._setEmber = nil
    unit._setEmberSrc = nil
    if unit.attrs then
        -- 新场/换波边界显式清临时盾，不能依赖属性重算顺带抹掉。
        if not preserveTempShield then unit.attrs.tempEnergyShield = 0 end
        unit.attrs:removeModifier("set6_nitros_spd")
        unit.attrs:removeModifier("set4_gamble")
        unit.attrs:removeModifier("set4_bonehunger")
    end
end

---@param unit table
---@param allies table[]|nil
function ESR.onBattleStart(unit, allies)
    if not unit then return end
    -- TAL 开头已经清新场残留；这里不能抹掉刚施加的开战临时盾。
    ESR.resetBattleState(unit, true)
    ESR.applyStaticBonuses(unit.attrs)
    ESR.applyTeamAura(allies or { unit })
end

--- 无面窗口供普攻、连击、额伤/治疗仇恨入口共用；下一击不消费窗口。
---@param unit table|nil
---@return boolean
function ESR.shouldSkipThreat(unit)
    return unit ~= nil and six(unit) == "faceless" and (unit._setFacelessT or 0) > 0
end

--- 叠甲减伤、余烬与晶蚀全伤易伤（普攻/连击/额伤共用）。
---@param target table
---@param damage number
---@param source table|nil
---@return number
function ESR.onIncoming(target, damage, source)
    if not target or damage <= 0 then return damage end
    if four(target) == "carapace" then
        local cfg = ESC.SETS.carapace.effect4
        target._setShell = math.min(cfg.maxStacks, (target._setShell or 0) + 1)
        damage = damage * math.max(0, 1 - target._setShell * cfg.damageReductionPerStack)
    end
    if (target._setEmber or 0) > 0 then
        damage = damage * (1 + ESC.SETS.emberscout.effect4.damageTakenRatio)
    end
    local crystal = ESC.SETS.riftcrystal.effect4
    local layers = math.min(crystal.maxStacks, math.max(0, target._crystal or 0))
    if layers > 0 then damage = damage * (1 + layers * crystal.damageTakenPerStack) end
    return damage
end

--- 格挡后：直接七参 BattleCombat.dealDamageToUnit，真实持有者是第六参。
---@param target table
---@param attacker table|nil
---@param blockedAmount number
---@param dealDmgFn function|nil
---@param attackerIsAlly boolean|nil 反射目标所属阵营（不是伤害类型）
function ESR.onBlocked(target, attacker, blockedAmount, dealDmgFn, attackerIsAlly)
    if not target or (target.hp or 0) <= 0 or four(target) ~= "ironwall" then return end
    if target.attrs then
        local heal = (target.maxHp or target.attrs:get(AD.MAX_HP) or 0) * ESC.SETS.ironwall.effect4.healMaxHpRatio
        if heal > 0 then
            target.attrs:heal(heal)
            target.hp = target.attrs:get(AD.HP)
        end
    end
    if six(target) == "ironwall" and attacker and dealDmgFn and (blockedAmount or 0) > 0 then
        dealDmgFn(attacker, blockedAmount * ESC.SETS.ironwall.effect6.reflectRatio,
            attackerIsAlly == true, "铁壁 ", { 180, 160, 120 }, target,
            effectMeta("ironwall", "magical", true))
    end
end

---@param attacker table
---@param defender table
---@param result table
---@param isAlly boolean
---@param dealDmgFn function|nil 六参闭包：target, damage, targetIsAlly, prefix, color, opts
---@param targetList table[]|nil
function ESR.onAfterAttack(attacker, defender, result, isAlly, dealDmgFn, targetList)
    if not attacker or not result or result.isMiss or result.category == "healing" then return end
    local f, s = four(attacker), six(attacker)
    local cfg4 = f and ESC.SETS[f] and ESC.SETS[f].effect4 or {}
    local cfg6 = s and ESC.SETS[s] and ESC.SETS[s].effect6 or {}

    if f == "faceless" and defender and defender.maxHp and defender.hp then
        if defender.hp / math.max(1, defender.maxHp) < cfg4.hpThreshold and result.totalDamage then
            if dealDmgFn and defender.hp > 0 then
                dealDmgFn(defender, result.totalDamage * cfg4.damageRatio, not isAlly,
                    "无面 ", { 180, 180, 200 }, effectMeta(f, result.category, ESR.shouldSkipThreat(attacker)))
            end
        end
    end

    if f == "riftcrystal" and defender and math.random() < cfg4.procChance then
        defender._crystal = math.min(cfg4.maxStacks, (defender._crystal or 0) + 1)
        if s == "riftcrystal" and defender._crystal >= cfg4.maxStacks and dealDmgFn and attacker.attrs then
            local mag = (attacker.attrs:get(AD.MAG_ATK) or 0) * cfg6.magRatio
            dealDmgFn(defender, mag, not isAlly, "晶碎 ", { 120, 200, 230 }, effectMeta(f, "magical"))
            defender.atkProgress = math.max(0, (defender.atkProgress or 0)
                - (defender.isBoss and cfg6.bossProgressLoss or cfg6.progressLoss))
            defender._crystal = 0
        end
    end

    if f == "tidepress" and dealDmgFn and targetList and math.random() < cfg4.procChance then
        local other = nil
        for _, t in ipairs(targetList) do
            if t ~= defender and (t.hp or 0) > 0 then other = t; break end
        end
        if other then
            dealDmgFn(other, (result.totalDamage or 0) * cfg4.splashRatio, not isAlly,
                "水脉 ", { 80, 180, 210 }, effectMeta(f, result.category))
            if s == "tidepress" then
                other.atkProgress = math.max(0, (other.atkProgress or 0) - cfg6.progressLoss)
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
            dealDmgFn(second, (result.totalDamage or 0) * cfg6.pierceRatio, not isAlly,
                "硝烟 ", { 230, 120, 60 }, effectMeta(s, result.category))
        elseif n <= 1 and attacker.attrs then
            attacker.attrs:addModifier("set6_nitros_spd", { { key = AD.ATK_SPEED, flat = cfg6.speedBonus } })
            attacker._setNitroT = cfg6.duration
        end
    end

    if f == "emberscout" and defender then
        defender._setEmber = cfg4.duration
        defender._setEmberSrc = attacker
    end

    if f == "gambler" and attacker.attrs then
        if result.isCrit then
            attacker._setGamble = 0
            attacker.attrs:removeModifier("set4_gamble")
            if s == "gambler" and dealDmgFn and defender then
                dealDmgFn(defender, (result.totalDamage or 0) * cfg6.damageRatio, not isAlly,
                    "残响 ", { 200, 80, 110 }, effectMeta(f, result.category))
            end
        else
            attacker._setGamble = math.min(cfg4.maxStacks, (attacker._setGamble or 0) + 1)
            attacker.attrs:addModifier("set4_gamble", {
                { key = AD.CRIT_RATE, flat = cfg4.critPerStack * attacker._setGamble },
            })
            if s == "gambler" then
                local lost = math.max(0, (attacker.maxHp or 0) - (attacker.hp or 0))
                attacker.attrs:heal(lost * cfg6.healLostHpRatio)
                attacker.hp = attacker.attrs:get(AD.HP)
            end
        end
    end

    if f == "bonehunger" and attacker.attrs then
        local hp = attacker.hp or attacker.attrs:get(AD.HP) or 1
        local mx = attacker.maxHp or attacker.attrs:get(AD.MAX_HP) or 1
        if hp / math.max(1, mx) < cfg4.hpThreshold then
            attacker.attrs:addModifier("set4_bonehunger", { { key = AD.ATK_SPEED, flat = cfg4.speedBonus } })
        else
            attacker.attrs:removeModifier("set4_bonehunger")
        end
    end

    if s == "carapace" and (attacker._setShell or 0) >= ESC.SETS.carapace.effect4.maxStacks then
        local layers = attacker._setShell
        attacker._setShell = 0
        if dealDmgFn and defender then
            dealDmgFn(defender, (result.totalDamage or 0) * layers * cfg6.damageRatioPerStack, not isAlly,
                "虫壳 ", { 200, 140, 60 }, effectMeta(s, result.category))
        end
        local TM = require("systems.ThreatManager")
        TM.forceTarget(attacker, cfg6.tauntDuration)
    end
end

---@param healer table
---@param target table
---@param overheal number
function ESR.onOverheal(healer, target, overheal)
    if four(healer) == "last_rite" and target and target.attrs and overheal > 0 then
        local add = overheal * ESC.SETS.last_rite.effect4.overhealShieldRatio
        target.attrs.tempEnergyShield = (target.attrs.tempEnergyShield or 0) + add
    end
end

---@param deadEnemy table
---@param allies table[]
---@param enemies table[]|nil
function ESR.onEnemyDeath(deadEnemy, allies, enemies)
    if not deadEnemy or (deadEnemy.hp or 0) > 0 then return end
    for _, a in ipairs(allies or {}) do
        if (a.hp or 0) > 0 and six(a) == "faceless" then
            a._setFacelessT = ESC.SETS.faceless.effect6.duration
            local TM = require("systems.ThreatManager")
            TM.clearThreat(a)
        end
        if (a.hp or 0) > 0 and six(a) == "bonehunger" and a.attrs then
            local mx = a.maxHp or a.attrs:get(AD.MAX_HP) or 0
            a.attrs:heal(mx * ESC.SETS.bonehunger.effect6.healMaxHpRatio)
            a.hp = a.attrs:get(AD.HP)
        end
    end
    if deadEnemy and (deadEnemy._setEmber or 0) > 0 and six(deadEnemy._setEmberSrc) == "emberscout" then
        local remaining = ESC.SETS.emberscout.effect6.spreadTargets
        for _, enemy in ipairs(enemies or {}) do
            if enemy ~= deadEnemy and (enemy.hp or 0) > 0 then
                enemy._setEmber = ESC.SETS.emberscout.effect4.duration
                enemy._setEmberSrc = deadEnemy._setEmberSrc
                remaining = remaining - 1
                if remaining <= 0 then break end
            end
        end
    end
    if deadEnemy then
        deadEnemy._setEmber = nil
        deadEnemy._setEmberSrc = nil
    end
end

local function tickEmber(unit, dt)
    if unit._setEmber then
        local left = unit._setEmber - dt
        if left <= 0 then
            unit._setEmber = nil
            unit._setEmberSrc = nil
        else
            unit._setEmber = left
        end
    else
        unit._setEmberSrc = nil
    end
end

---@param dt number
---@param allies table[]
---@param enemies table[]
---@param ctx table|nil ctx.dealDamage 使用七参直接函数，与 onBlocked 一致。
function ESR.update(dt, allies, enemies, ctx)
    local dealDmg = ctx and ctx.dealDamage
    local seen = {}
    for _, list in ipairs({ allies or {}, enemies or {} }) do
        for _, u in ipairs(list) do
            if not seen[u] then
                seen[u] = true
                tickEmber(u, dt)
            end
        end
    end
    for _, u in ipairs(allies or {}) do
        if (u._setNitroT or 0) > 0 then
            u._setNitroT = math.max(0, u._setNitroT - dt)
            if u._setNitroT <= 0 and u.attrs then
                u.attrs:removeModifier("set6_nitros_spd")
            end
        end
        if (u._setFacelessT or 0) > 0 then
            u._setFacelessT = math.max(0, u._setFacelessT - dt)
        end
        -- 死亡只暂停周期输出；限时增益和减益仍按本场时间清理。
        if (u.hp or 0) <= 0 then goto continue_unit end
        if four(u) == "swordgate" then
            local cfg = ESC.SETS.swordgate
            u._setSwordWin = (u._setSwordWin or 0) + dt
            if u._setSwordWin >= cfg.effect4.interval then
                u._setSwordWin = 0
                local swords = cfg.effect4.swordCount + (six(u) == "swordgate" and cfg.effect6.extraSwords or 0)
                local dmg = (u._setSwordDmgWin or 0) * cfg.effect4.damageRatio
                u._setSwordDmgWin = 0
                if dealDmg and dmg > 0 then
                    for _ = 1, swords do
                        local alive = {}
                        for _, e in ipairs(enemies or {}) do
                            if (e.hp or 0) > 0 then alive[#alive + 1] = e end
                        end
                        if #alive > 0 then
                            local tgt = alive[math.random(#alive)]
                            dealDmg(tgt, dmg, false, "门剑 ", { 200, 200, 220 }, u,
                                effectMeta("swordgate", "physical", true))
                        end
                    end
                end
            end
        end
        if six(u) == "starless" then
            local cfg = ESC.SETS.starless.effect6
            u._setStarCd = (u._setStarCd or cfg.interval) - dt
            if u._setStarCd <= 0 then
                u._setStarCd = cfg.interval
                local lowest = nil
                local lp = 2
                for _, e in ipairs(enemies or {}) do
                    if (e.hp or 0) > 0 and e.maxHp then
                        local p = e.hp / math.max(1, e.maxHp)
                        if p < lp then lp = p; lowest = e end
                    end
                end
                if lowest and dealDmg and u.attrs then
                    local mag = (u.attrs:get(AD.MAG_ATK) or 0) * cfg.magRatio
                    dealDmg(lowest, mag, false, "无光 ", { 80, 60, 140 }, u,
                        effectMeta("starless", "magical", true))
                end
            end
        end
        ::continue_unit::
    end
end

--- 飞剑窗口累计自身伤害
function ESR.addSwordWindowDamage(unit, amount)
    if four(unit) == "swordgate" then
        unit._setSwordDmgWin = (unit._setSwordDmgWin or 0) + (amount or 0)
    end
end

return ESR
