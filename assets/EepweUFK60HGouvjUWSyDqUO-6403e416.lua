-- ============================================================================
-- TowerBuffRuntime - 通天塔强化运行时效果（完整实装）
-- 职责: 将已选强化应用到战斗单位（stat类直接加属性，mechanic类提供钩子）
-- 所有35个强化效果的运行时逻辑均在此实装
-- ============================================================================

local AD          = require("systems.AttributeDef")
local TowerConfig = require("config.TowerConfig")
local CC          = require("config.ClassConfig")

local TBR = {}

-- ======================== stat 属性映射 ========================

local STAT_APPLY = {
    physAtkBonus = { key = AD.PHYS_ATK_BONUS, isPercent = true },
    magAtkBonus  = { key = AD.MAG_ATK_BONUS,  isPercent = true },
    hpBonus      = { key = AD.HP_BONUS,       isPercent = true },
    critRate     = { key = AD.CRIT_RATE,      isPercent = true },
    critDmg      = { key = AD.CRIT_DMG,       isPercent = true },
    dodge        = { key = AD.DODGE,          isPercent = false },
    comboRate    = { key = AD.COMBO_RATE,     isPercent = true },
    comboBonus   = { key = AD.COMBO_DMG_UP,   isPercent = true },
    atkHeal      = { key = AD.ATK_HEAL,       isPercent = false },
    atkSpeed     = { key = AD.ATK_SPEED,      isPercent = true },
    physPen      = { key = AD.PHYS_PEN,       isPercent = false },
    magPen       = { key = AD.MAG_PEN,        isPercent = false },
    blockRatio   = { key = AD.PHYS_BLOCK_RATIO, isPercent = true },
    healBonus    = { key = AD.HEAL_BONUS,     isPercent = true },
}

-- ======================== HP 同步工具 ========================

--- 属性重算改变 MAX_HP 后，按旧血量比例同步运行时 HP，避免下一次受击时从旧 attrs HP 跳回
---@param unit table
---@param oldHp number|nil
---@param oldMaxHp number|nil
local function syncHpAfterMaxHpChange(unit, oldHp, oldMaxHp)
    if not unit or not unit.attrs then return end
    local newMaxHp = unit.attrs:get(AD.MAX_HP)
    local newHp = unit.attrs:get(AD.HP)

    if oldHp and oldMaxHp and oldMaxHp > 0 then
        if oldHp <= 0 then
            newHp = 0
        else
            newHp = math.floor(oldHp * newMaxHp / oldMaxHp + 0.5)
            if newHp < 1 then newHp = 1 end
        end
    end

    newHp = math.max(0, math.min(newHp, newMaxHp))
    unit.attrs.final[AD.HP] = newHp
    unit.maxHp = newMaxHp
    unit.hp = newHp
end

-- ======================== 应用 stat 类强化 ========================

--- 将所有已选 stat 强化应用到己方全体单位
---@param allies table[] 己方单位列表
---@param buffIds number[] 已选强化ID列表
function TBR.applyStatBuffs(allies, buffIds)
    if not buffIds or #buffIds == 0 then return end

    for _, buffId in ipairs(buffIds) do
        local buff = TowerConfig.BUFFS_BY_ID[buffId]
        if buff and buff.effectType == "stat" and buff.stats then
            -- 收集所有 stat entries（全部使用 flat，因为是"加到属性值上"而非"乘以百分比"）
            local entries = {}
            for statKey, value in pairs(buff.stats) do
                local mapping = STAT_APPLY[statKey]
                if mapping then
                    entries[#entries + 1] = { key = mapping.key, flat = value }
                end
            end
            if #entries > 0 then
                for _, unit in ipairs(allies) do
                    if unit.hp > 0 and unit.attrs then
                        if not buff.classReq or unit.classId == buff.classReq then
                            local oldHp = unit.hp
                            local oldMaxHp = unit.maxHp or unit.attrs:get(AD.MAX_HP)
                            unit.attrs:addModifier("tower_buff_" .. buffId, entries)
                            if buff.stats.hpBonus then
                                syncHpAfterMaxHpChange(unit, oldHp, oldMaxHp)
                            end
                        end
                    end
                end
            end
        end
    end

    -- 重新同步 HP
    for _, unit in ipairs(allies) do
        if unit.attrs then
            unit.maxHp = unit.attrs:get(AD.MAX_HP)
            unit.hp = unit.attrs:get(AD.HP)
            if unit.hp > unit.maxHp then
                unit.hp = unit.maxHp
                unit.attrs.final[AD.HP] = unit.maxHp
            end
        end
    end
end

-- ======================== mechanic 运行时状态 ========================

---@type table|nil
local M = nil  -- 运行时状态容器

--- 初始化 mechanic 运行时状态
---@param buffIds number[]
function TBR.initMechanics(buffIds)
    M = {
        buffIds       = {},          -- 活跃的 mechanic buff id 列表
        -- 通用计时/计数
        battleTime        = 0,       -- 当前波战斗时间
        killDmgStack      = 0,       -- #16 斩杀狂潮层数
        killDmgTimer      = 0,       -- #16 斩杀狂潮倒计时
        killHpStack       = 0,       -- #17 战意凝聚层数
        allies            = nil,     -- 当前通天塔己方单位引用，用于击杀叠层实时改属性
        freezeTimer       = 0,       -- #21 霜寒领域计时
        deathImmunityTimer = 0,      -- #23 亡者遗志倒计时
        -- 职业专属状态
        mageAccumulate    = {},      -- { [unitInstanceId] = accDmgPct } 法师蓄力层数
        assassinImmunity  = {},      -- { [unitInstanceId] = remainingCharges } 刺客免疫次数
        warriorNoHeal     = {},      -- { [unitInstanceId] = true } 嗜血狂战禁疗标记
    }
    for _, buffId in ipairs(buffIds) do
        local buff = TowerConfig.BUFFS_BY_ID[buffId]
        if buff and buff.effectType == "mechanic" then
            M.buffIds[#M.buffIds + 1] = buffId
        end
    end
    print("[TowerBuffRuntime] initMechanics: " .. #M.buffIds .. " mechanic buffs active")
end

--- 应用 mechanic 类初始化效果（战斗开始/新波次时对单位做一次性修改）
---@param allies table[] 己方单位列表
---@param enemies table[] 敌方单位列表（用于统计坦数量等）
function TBR.applyMechanicInit(allies, enemies)
    if not M then return end
    M.allies = allies

    for _, buffId in ipairs(M.buffIds) do
        local buff = TowerConfig.BUFFS_BY_ID[buffId]
        if not buff then goto continue end
        local mid = buff.mechanicId
        local params = buff.params or {}

        -- #18 连击风暴：全体连击增伤×2（在当前基础上再加同等数值）
        if mid == "combo_dmg_double" then
            for _, unit in ipairs(allies) do
                if unit.hp > 0 and unit.attrs then
                    local current = unit.attrs:get(AD.COMBO_DMG_UP)
                    if current > 0 then
                        unit.attrs:addModifier("tower_combo_double_" .. (unit.heroId or 0), {
                            { key = AD.COMBO_DMG_UP, flat = current }
                        })
                    end
                end
            end

        -- #20 迅雷之势：全体攻击间隔-25%（乘法）
        elseif mid == "interval_reduce" then
            local reduce = (params.reduce or 25) / 100
            for _, unit in ipairs(allies) do
                if unit.hp > 0 and unit.atkInterval then
                    unit.atkInterval = unit.atkInterval * (1 - reduce)
                end
            end

        -- #24 守护誓约：骑士仇恨倍率+200%+初始仇恨2000（通过 ThreatManager 处理）
        -- 注：仇恨初始值在 TowerBattleScene.startWave 中通过 ThreatManager.onBattleStart 后追加

        -- #26 嗜血狂战：战士生命+1000%但禁疗
        elseif mid == "warrior_bloodlust" then
            local hpBonus = params.hpBonus or 1000
            for _, unit in ipairs(allies) do
                if unit.hp > 0 and unit.classId == CC.WARRIOR and unit.attrs then
                    local oldHp = unit.hp
                    local oldMaxHp = unit.maxHp or unit.attrs:get(AD.MAX_HP)
                    unit.attrs:addModifier("tower_warrior_bloodlust_" .. (unit.heroId or 0), {
                        { key = AD.HP_BONUS, flat = hpBonus }
                    })
                    syncHpAfterMaxHpChange(unit, oldHp, oldMaxHp)
                    M.warriorNoHeal[unit.instanceId or unit.heroId or 0] = true
                end
            end

        -- #27 狂战之魂：战士每损5%→攻速+10%（动态，在 getAtkIntervalMult 中处理）

        -- #28 蓄能爆裂：法师间隔×2（初始化时修改）
        elseif mid == "mage_charge_burst" then
            local intervalMult = (params.intervalMult or 100) / 100
            for _, unit in ipairs(allies) do
                if unit.hp > 0 and unit.classId == CC.MAGE and unit.atkInterval then
                    unit.atkInterval = unit.atkInterval * (1 + intervalMult)
                end
            end

        -- #29 奥术聚能：法师蓄力初始化
        elseif mid == "mage_accumulate" then
            for _, unit in ipairs(allies) do
                if unit.hp > 0 and unit.classId == CC.MAGE then
                    M.mageAccumulate[unit.instanceId or unit.heroId or 0] = 0
                end
            end

        -- #31 后援射击：射手每有一个战士/骑士→攻速+25%
        elseif mid == "ranger_support" then
            local perTank = params.perTank or 25
            local tankCount = 0
            for _, unit in ipairs(allies) do
                if unit.hp > 0 and (unit.classId == CC.KNIGHT or unit.classId == CC.WARRIOR) then
                    tankCount = tankCount + 1
                end
            end
            if tankCount > 0 then
                local bonus = tankCount * perTank
                for _, unit in ipairs(allies) do
                    if unit.hp > 0 and unit.classId == CC.RANGER and unit.attrs then
                        unit.attrs:addModifier("tower_ranger_support_" .. (unit.heroId or 0), {
                            { key = AD.ATK_SPEED, flat = bonus }
                        })
                    end
                end
            end

        -- #33 虚影闪避：刺客免疫次数初始化
        elseif mid == "assassin_immunity" then
            local count = params.count or 10
            for _, unit in ipairs(allies) do
                if unit.hp > 0 and unit.classId == CC.ASSASSIN then
                    local uid = unit.instanceId or unit.heroId or 0
                    M.assassinImmunity[uid] = (M.assassinImmunity[uid] or 0) + count
                end
            end

        -- #35 生命圣约：牧师存活时全体生命+30%
        elseif mid == "priest_aura_hp" then
            local hpBonus = params.hpBonus or 30
            local priestAlive = false
            for _, unit in ipairs(allies) do
                if unit.hp > 0 and unit.classId == CC.PRIEST then
                    priestAlive = true
                    break
                end
            end
            if priestAlive then
                for _, unit in ipairs(allies) do
                    if unit.hp > 0 and unit.attrs then
                        local oldHp = unit.hp
                        local oldMaxHp = unit.maxHp or unit.attrs:get(AD.MAX_HP)
                        unit.attrs:addModifier("tower_priest_aura_hp_" .. (unit.heroId or 0), {
                            { key = AD.HP_BONUS, flat = hpBonus }
                        })
                        syncHpAfterMaxHpChange(unit, oldHp, oldMaxHp)
                    end
                end
            end
        end

        ::continue::
    end
end

--- 重置波次内计时器（新波次开始时调用）
function TBR.resetWaveTimers()
    if not M then return end
    M.killDmgStack = 0
    M.killDmgTimer = 0
    M.freezeTimer = 0
    M.deathImmunityTimer = 0
    M.battleTime = 0
    -- 蓄力重置
    for k in pairs(M.mageAccumulate) do
        M.mageAccumulate[k] = 0
    end
end

--- 检查是否拥有指定 mechanicId
---@param mechanicId string
---@return table|nil buff配置（含params）
function TBR.hasMechanic(mechanicId)
    if not M then return nil end
    for _, buffId in ipairs(M.buffIds) do
        local buff = TowerConfig.BUFFS_BY_ID[buffId]
        if buff and buff.mechanicId == mechanicId then
            return buff
        end
    end
    return nil
end

-- ======================== 每帧更新 ========================

--- 每帧更新（战斗进行中调用）
---@param dt number
---@param allies table[]
---@param enemies table[]
---@param freezeFn function(unit, duration) 冰冻单位回调
function TBR.update(dt, allies, enemies, freezeFn)
    if not M then return end
    M.battleTime = M.battleTime + dt

    -- 斩杀狂潮倒计时
    if M.killDmgTimer > 0 then
        M.killDmgTimer = M.killDmgTimer - dt
        if M.killDmgTimer <= 0 then
            M.killDmgStack = 0
            M.killDmgTimer = 0
        end
    end

    -- 亡者遗志无敌倒计时
    if M.deathImmunityTimer > 0 then
        M.deathImmunityTimer = M.deathImmunityTimer - dt
    end

    -- #21 霜寒领域：每隔10秒冰冻全体敌人
    local freezeBuff = TBR.hasMechanic("periodic_freeze")
    if freezeBuff and freezeFn then
        M.freezeTimer = M.freezeTimer + dt
        local interval = freezeBuff.params and freezeBuff.params.interval or 10
        if M.freezeTimer >= interval then
            M.freezeTimer = M.freezeTimer - interval
            local freezeDur = freezeBuff.params and freezeBuff.params.duration or 2
            local frozenCount = 0
            for _, enemy in ipairs(enemies) do
                if enemy.hp > 0 then
                    freezeFn(enemy, freezeDur)
                    frozenCount = frozenCount + 1
                end
            end
            print("[TowerBuffRuntime] 霜寒领域触发! 冰冻 " .. frozenCount .. " 个敌人 " .. freezeDur .. "秒")
        end
    end

    -- #29 奥术聚能：法师每秒蓄力+20%
    local mageAcc = TBR.hasMechanic("mage_accumulate")
    if mageAcc then
        local perSec = mageAcc.params and mageAcc.params.perSec or 20
        for _, unit in ipairs(allies) do
            if unit.hp > 0 and unit.classId == CC.MAGE then
                local uid = unit.instanceId or unit.heroId or 0
                if M.mageAccumulate[uid] then
                    M.mageAccumulate[uid] = M.mageAccumulate[uid] + perSec * dt
                end
            end
        end
    end
end

-- ======================== 伤害钩子 ========================

--- 伤害倍率修正（己方攻击时调用，返回乘法倍率）
---@param attacker table 攻击者（己方单位）
---@param target table 目标（敌方单位）
---@return number multiplier (1.0=无修正)
function TBR.getDamageMultiplier(attacker, target)
    if not M then return 1.0 end
    local mult = 1.0

    -- #11 绝境爆发：攻击者生命<30%→伤害+25%
    local lowHpDmg = TBR.hasMechanic("low_hp_dmg_bonus")
    if lowHpDmg and attacker.hp and attacker.maxHp and attacker.maxHp > 0 then
        local threshold = lowHpDmg.params and lowHpDmg.params.threshold or 30
        if attacker.hp / attacker.maxHp * 100 < threshold then
            mult = mult * (1 + (lowHpDmg.params.bonus or 25) / 100)
        end
    end

    -- #12 强者之怒：攻击者生命>80%→伤害+20%
    local highHpDmg = TBR.hasMechanic("high_hp_dmg_bonus")
    if highHpDmg and attacker.hp and attacker.maxHp and attacker.maxHp > 0 then
        local threshold = highHpDmg.params and highHpDmg.params.threshold or 80
        if attacker.hp / attacker.maxHp * 100 > threshold then
            mult = mult * (1 + (highHpDmg.params.bonus or 20) / 100)
        end
    end

    -- #14 先发制人：战斗前30秒伤害+20%
    local earlyDmg = TBR.hasMechanic("early_dmg_bonus")
    if earlyDmg then
        local duration = earlyDmg.params and earlyDmg.params.duration or 30
        if M.battleTime <= duration then
            mult = mult * (1 + (earlyDmg.params.bonus or 20) / 100)
        end
    end

    -- #16 斩杀狂潮叠层
    if M.killDmgStack > 0 and TBR.hasMechanic("kill_dmg_stack") then
        mult = mult * (1 + M.killDmgStack / 100)
    end

    -- #28 蓄能爆裂：法师额外伤害+200%
    local chargeBurst = TBR.hasMechanic("mage_charge_burst")
    if chargeBurst and attacker.classId == CC.MAGE then
        local dmgMult = chargeBurst.params and chargeBurst.params.dmgMult or 200
        mult = mult * (1 + dmgMult / 100)
    end

    -- #29 奥术聚能：法师蓄力累计额外伤害（攻击时消耗）
    local mageAcc = TBR.hasMechanic("mage_accumulate")
    if mageAcc and attacker.classId == CC.MAGE then
        local uid = attacker.instanceId or attacker.heroId or 0
        local accPct = M.mageAccumulate[uid] or 0
        if accPct > 0 then
            mult = mult * (1 + accPct / 100)
            M.mageAccumulate[uid] = 0  -- 攻击后清空
        end
    end

    return mult
end

--- 消费一次通天塔伤害免疫（有副作用，只能在确认本次会造成伤害前调用）
---@param defender table 受伤者（己方单位）
---@return boolean immune 是否免疫此次伤害
function TBR.consumeDamageImmunity(defender)
    if not M or not defender then return false end

    -- #23 亡者遗志：无敌期间
    if M.deathImmunityTimer > 0 then
        return true
    end

    -- #33 虚影闪避：刺客免疫次数
    if defender.classId == CC.ASSASSIN and TBR.hasMechanic("assassin_immunity") then
        local uid = defender.instanceId or defender.heroId or 0
        local charges = tonumber(M.assassinImmunity[uid]) or 0
        if charges > 0 then
            M.assassinImmunity[uid] = charges - 1
            return true
        end
        M.assassinImmunity[uid] = nil
    end

    return false
end

--- 受伤倍率修正（己方受到攻击时调用，不消费免疫次数）
---@param defender table 受伤者（己方单位）
---@return number multiplier (1.0=无修正, <1.0=减伤)
function TBR.getDamageTakenMultiplier(defender)
    if not M or not defender then return 1.0 end
    local mult = 1.0

    -- #13 绝境护盾：生命<30%受伤-50%
    local lowHpReduce = TBR.hasMechanic("low_hp_dmg_reduce")
    if lowHpReduce and defender.hp and defender.maxHp and defender.maxHp > 0 then
        local threshold = lowHpReduce.params and lowHpReduce.params.threshold or 30
        if defender.hp / defender.maxHp * 100 < threshold then
            mult = mult * (1 - (lowHpReduce.params.reduce or 50) / 100)
        end
    end

    -- #25 不屈之盾：骑士生命<40%→减伤20%, <20%→减伤40%
    local knightFortify = TBR.hasMechanic("knight_fortify")
    if knightFortify and defender.classId == CC.KNIGHT and defender.hp and defender.maxHp and defender.maxHp > 0 then
        local hpPct = defender.hp / defender.maxHp * 100
        local thresholds = knightFortify.params and knightFortify.params.thresholds or {40, 20}
        local reduces = knightFortify.params and knightFortify.params.reduces or {20, 40}
        -- 从低阈值开始检查（优先取更高减伤）
        if hpPct <= thresholds[2] then
            mult = mult * (1 - reduces[2] / 100)
        elseif hpPct <= thresholds[1] then
            mult = mult * (1 - reduces[1] / 100)
        end
    end

    return mult
end

--- 获取单位的攻击间隔动态倍率（每帧调用）
--- 用于 #27 狂战之魂（战士损失HP→攻速提升）
---@param unit table
---@return number 间隔乘数 (1.0=不变, <1.0=加快)
function TBR.getAtkIntervalMultiplier(unit)
    if not M then return 1.0 end

    -- #27 狂战之魂：战士每损5%HP→攻速+10%
    local furyBuff = TBR.hasMechanic("warrior_fury")
    if furyBuff and unit.classId == CC.WARRIOR and unit.hp and unit.maxHp and unit.maxHp > 0 then
        local lostPct = (1 - unit.hp / unit.maxHp) * 100
        local stacks = math.floor(lostPct / (furyBuff.params and furyBuff.params.perLost or 5))
        local atkSpeedBonus = stacks * (furyBuff.params and furyBuff.params.atkSpeedPer or 10)
        if atkSpeedBonus > 0 then
            -- 攻击间隔 = base / (1 + bonus%)
            return 1 / (1 + atkSpeedBonus / 100)
        end
    end

    return 1.0
end

--- 暴击后是否触发超暴击（#30 精准连射）
---@param attacker table
---@param isCrit boolean 本次是否暴击
---@return boolean 是否应该再额外计算一次暴击
function TBR.shouldSuperCrit(attacker, isCrit)
    if not M then return false end
    if not isCrit then return false end
    if attacker.classId ~= CC.RANGER then return false end
    return TBR.hasMechanic("ranger_super_crit") ~= nil
end

--- 是否禁止治疗（#26 嗜血狂战）
---@param unit table
---@return boolean
function TBR.isHealBlocked(unit)
    if not M then return false end
    local uid = unit.instanceId or unit.heroId or 0
    return M.warriorNoHeal[uid] == true
end

-- ======================== 击杀/死亡回调 ========================

--- 将战意凝聚当前层数实时应用到全体存活己方
local function applyKillHpStackToAllies()
    if not M or not M.allies then return end
    for _, unit in ipairs(M.allies) do
        if unit.hp > 0 and unit.attrs then
            local oldHp = unit.hp
            local oldMaxHp = unit.maxHp or unit.attrs:get(AD.MAX_HP)
            unit.attrs:addModifier("tower_kill_hp_stack", {
                { key = AD.HP_BONUS, flat = M.killHpStack }
            })
            syncHpAfterMaxHpChange(unit, oldHp, oldMaxHp)
        end
    end
end

--- 击杀回调
---@param killer table 击杀者
function TBR.onEnemyKill(killer)
    if not M then return end

    -- #16 斩杀狂潮
    local killDmg = TBR.hasMechanic("kill_dmg_stack")
    if killDmg then
        local perKill = killDmg.params and killDmg.params.perKill or 5
        local cap = killDmg.params and killDmg.params.cap or 30
        M.killDmgStack = math.min(M.killDmgStack + perKill, cap)
        M.killDmgTimer = killDmg.params and killDmg.params.duration or 15
    end

    -- #17 战意凝聚
    local killHp = TBR.hasMechanic("kill_hp_stack")
    if killHp then
        local perKill = killHp.params and killHp.params.perKill or 5
        local cap = killHp.params and killHp.params.cap or 50
        local oldStack = M.killHpStack
        M.killHpStack = math.min(M.killHpStack + perKill, cap)
        if M.killHpStack ~= oldStack then
            applyKillHpStackToAllies()
        end
    end
end

--- 己方死亡回调
---@param deadUnit table 死亡单位
function TBR.onAllyDeath(deadUnit)
    if not M then return end

    -- #23 亡者遗志
    local deathImm = TBR.hasMechanic("death_immunity")
    if deathImm then
        M.deathImmunityTimer = deathImm.params and deathImm.params.duration or 5
    end
end

-- ======================== 终结审判 ========================

--- 对低HP目标有概率直接消灭
---@param target table
---@return boolean
function TBR.checkExecute(target)
    if not M then return false end
    local exec = TBR.hasMechanic("execute")
    if not exec then return false end
    if target.hp <= 0 then return false end

    local maxHp = target.maxHp or (target.attrs and target.attrs:get(AD.MAX_HP)) or 0
    if maxHp <= 0 then return false end

    local hpThreshold = exec.params and exec.params.hpThreshold or 10
    local chance = exec.params and exec.params.chance or 10

    if target.hp / maxHp * 100 <= hpThreshold then
        if math.random(100) <= chance then
            return true
        end
    end
    return false
end

-- ======================== 查询接口 ========================

--- 获取狂暴提前时间（#22 战争催化）
---@return number
function TBR.getRageAdvance()
    local buff = TBR.hasMechanic("early_rage")
    if buff then
        return buff.params and buff.params.advance or 15
    end
    return 0
end

--- 获取战意凝聚累计的生命加成百分比
---@return number
function TBR.getKillHpStack()
    if not M then return 0 end
    return M.killHpStack
end

--- 获取骑士额外初始仇恨（#24 守护誓约）
---@return number threatMult 仇恨倍率加成百分比（如200表示+200%）
---@return number initialThreat 额外初始仇恨
function TBR.getKnightThreatBonus()
    local buff = TBR.hasMechanic("knight_threat")
    if not buff then return 0, 0 end
    local p = buff.params or {}
    return p.mult or 200, p.initial or 2000
end

--- 清理
function TBR.cleanup()
    M = nil
end

return TBR
