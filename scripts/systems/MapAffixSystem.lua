-- ============================================================================
-- MapAffixSystem.lua — 地图词缀战斗效果系统
-- 职责：根据当前关卡 chapter 获取词缀配置，并在战斗中应用效果
-- 分为两类：
--   1. 静态词缀：在怪物生成后一次性修改属性（energy_barrier, iron_wall, haste_realm）
--   2. 动态词缀：在战斗 tick 中持续检查/应用（berserk_low_hp, decay_land, ancient_fog, time_rift 等）
-- ============================================================================

local MapAffixConfig = require("config.MapAffixConfig")
local AD             = require("systems.AttributeDef")
local SEM            = require("systems.StatusEffectManager")

local MapAffixSystem = {}

local RIFT_MOD_ID = "map_affix_time_rift"

-- ======================== 运行时状态 ========================

local function recalcUnitAttackInterval(unit)
    if not unit or not unit.attrs then return end
    if unit.attrs.getActualInterval then
        unit.atkInterval = unit.attrs:getActualInterval()
        unit._lastAttrInterval = unit.atkInterval
    else
        local baseInterval = unit.attrs.final[AD.ATK_INTERVAL] or 1.5
        unit.atkInterval = baseInterval / (1 + math.max(0, unit.attrs.final[AD.ATK_SPEED] or 0) / 100)
        unit._lastAttrInterval = unit.atkInterval
    end
end

--- 当前激活的词缀列表（loadStage 时设置）
local activeAffixes_ = nil  ---@type table[]|nil

--- 动态词缀运行时状态
local runtimeState_ = {
    -- 衰败之地
    decayElapsed = 0,
    decayStacks = 0,
    -- 远古之雾 / 时空裂隙
    periodicTimer = 0,
    fogActive = false,
    fogTimer = 0,
    riftActive = false,
    riftTimer = 0,
    -- 蚀甲之触：每个己方单位的腐蚀层 { [unitInstanceId] = { {expireTime, pct}, ... } }
    corrodeStacks = {},
    -- 冰冻之莲
    frostLotusTimer = 0,
}

local function resetRuntimeState()
    runtimeState_.decayElapsed = 0
    runtimeState_.decayStacks = 0
    runtimeState_.periodicTimer = 0
    runtimeState_.fogActive = false
    runtimeState_.fogTimer = 0
    runtimeState_.riftActive = false
    runtimeState_.riftTimer = 0
    runtimeState_.corrodeStacks = {}
    runtimeState_.frostLotusTimer = 0
end

-- ======================== 公开 API ========================

--- 清除己方单位上的词缀 debuff 标记（切关/重置时调用）
---@param allies table[]|nil
function MapAffixSystem.clearDebuffsFromAllies(allies)
    if not allies then return end
    for _, ally in ipairs(allies) do
        if ally._fogHitDebuff and ally.attrs and ally.attrs.final then
            ally.attrs.final[AD.HIT_VALUE] = (ally.attrs.final[AD.HIT_VALUE] or 0) + ally._fogHitDebuff
            ally._fogHitDebuff = nil
            ally._fogExpire = nil
        end
        if ally._riftAtkDebuff and ally.attrs and ally.attrs.final then
            if ally.attrs.removeModifier then
                ally.attrs:removeModifier(RIFT_MOD_ID)
            else
                ally.attrs.final[AD.ATK_SPEED] = (ally.attrs.final[AD.ATK_SPEED] or 0) + ally._riftAtkDebuff
            end
            ally._riftAtkDebuff = nil
            ally._riftExpire = nil
            -- 恢复攻击间隔
            recalcUnitAttackInterval(ally)
        end
        -- 清理蚀甲缓存
        if ally.attrs then
            ally.attrs._corrodeArmorPct = nil
        end
    end
end

--- 清理当前战斗的所有词缀状态（跨战斗场景切换时调用）
---@param allies table[]|nil
function MapAffixSystem.reset(allies)
    MapAffixSystem.clearDebuffsFromAllies(allies)
    activeAffixes_ = nil
    resetRuntimeState()
end

--- 加载关卡时调用：根据 chapter 设置当前词缀
---@param chapter number
---@param allies table[]|nil 当前己方单位（用于清除旧 debuff）
---@param mode string|nil 赛季词缀模式
function MapAffixSystem.onStageLoad(chapter, allies, mode)
    -- 先清除上一关残留在英雄身上的 debuff
    MapAffixSystem.clearDebuffsFromAllies(allies)

    if mode == "challenger_s1" then
        activeAffixes_ = MapAffixConfig.getAffixesForChallengerS1(chapter)
    else
        activeAffixes_ = MapAffixConfig.getAffixesForChapter(chapter)
    end
    resetRuntimeState()
    if activeAffixes_ then
        local names = {}
        for _, a in ipairs(activeAffixes_) do names[#names + 1] = a.name end
        print("[MapAffix] 加载词缀 chapter=" .. chapter .. " count=" .. #activeAffixes_
            .. " [" .. table.concat(names, ", ") .. "]")
    end
end

--- 获取当前激活的词缀列表（UI 展示用）
---@return table[]|nil
function MapAffixSystem.getActiveAffixes()
    return activeAffixes_
end

--- 是否有激活词缀
---@return boolean
function MapAffixSystem.hasAffixes()
    return activeAffixes_ ~= nil and #activeAffixes_ > 0
end

-- ======================== 静态词缀：应用到怪物 ========================

--- 在怪物生成后调用，应用静态属性修改
---@param enemies table[] 怪物列表
function MapAffixSystem.applyStaticAffixes(enemies)
    if not activeAffixes_ or #enemies == 0 then return end

    for _, affix in ipairs(activeAffixes_) do
        local id = affix.id
        local p = affix.params

        if id == "energy_barrier" then
            -- 给所有怪物添加基于最大HP百分比的能量护盾
            for _, enemy in ipairs(enemies) do
                if enemy.attrs and enemy.attrs.final then
                    local maxHp = enemy.attrs.final[AD.MAX_HP] or 0
                    local shieldAmount = math.floor(maxHp * p.shieldPct + 0.5)
                    if shieldAmount > 0 then
                        enemy.attrs.final[AD.ENERGY_SHIELD] = (enemy.attrs.final[AD.ENERGY_SHIELD] or 0) + shieldAmount
                        enemy.attrs.energyShield = enemy.attrs.final[AD.ENERGY_SHIELD]
                    end
                end
            end

        elseif id == "iron_wall" then
            -- 所有怪物护甲+固定值
            for _, enemy in ipairs(enemies) do
                if enemy.attrs and enemy.attrs.final then
                    enemy.attrs.final[AD.ARMOR] = (enemy.attrs.final[AD.ARMOR] or 0) + p.armorAdd
                end
            end

        elseif id == "tenacious_will" then
            -- 所有怪物异常抗性+固定值
            for _, enemy in ipairs(enemies) do
                if enemy.attrs and enemy.attrs.final then
                    enemy.attrs.final[AD.ABNORMAL_RES] = (enemy.attrs.final[AD.ABNORMAL_RES] or 0) + p.abnormalResAdd
                end
            end

        elseif id == "haste_realm" then
            -- 攻击力降低，攻速增加
            for _, enemy in ipairs(enemies) do
                if enemy.attrs and enemy.attrs.final then
                    local phys = enemy.attrs.final[AD.PHYS_ATK] or 0
                    local mag = enemy.attrs.final[AD.MAG_ATK] or 0
                    if phys > 0 then
                        enemy.attrs.final[AD.PHYS_ATK] = phys * (1 - p.atkReduce)
                    end
                    if mag > 0 then
                        enemy.attrs.final[AD.MAG_ATK] = mag * (1 - p.atkReduce)
                    end
                    -- 攻速加成（atkSpeedBonus 为小数形式 0.80 = 80%，ATK_SPEED 单位为百分比整数）
                    enemy.attrs.final[AD.ATK_SPEED] = (enemy.attrs.final[AD.ATK_SPEED] or 0) + p.atkSpeedBonus * 100
                    -- 重算实际攻击间隔
                    local baseInterval = enemy.attrs.final[AD.ATK_INTERVAL] or 1.5
                    enemy.atkInterval = baseInterval / (1 + (enemy.attrs.final[AD.ATK_SPEED] or 0) / 100)
                end
            end
        end
    end
end

-- ======================== 动态词缀：战斗 tick ========================

--- 获取单位的唯一标识（英雄用 heroId，怪物用 instanceId）
---@param unit table
---@return string|nil
local function getUnitKey(unit)
    if unit.heroId then return "h" .. tostring(unit.heroId) end
    if unit.instanceId then return "m" .. tostring(unit.instanceId) end
    return nil
end

--- 获取词缀参数（按 id 查找）
---@param id string
---@return table|nil
local function getAffixParams(id)
    if not activeAffixes_ then return nil end
    for _, a in ipairs(activeAffixes_) do
        if a.id == id then return a.params end
    end
    return nil
end

--- 是否激活指定词缀
---@param id string
---@return boolean
function MapAffixSystem.hasAffix(id)
    return getAffixParams(id) ~= nil
end

--- 每帧调用：更新动态词缀（衰败之地、远古之雾、时空裂隙）
---@param dt number deltaTime
---@param allies table[] 己方单位列表
---@param enemies table[] 敌方单位列表
function MapAffixSystem.tick(dt, allies, enemies)
    if not activeAffixes_ then return end

    local now = runtimeState_.decayElapsed + dt
    runtimeState_.decayElapsed = now

    -- ---- 衰败之地：每10秒怪物伤害+4%，上限40% ----
    local decayP = getAffixParams("decay_land")
    if decayP then
        local interval = decayP.tickInterval or 10
        local newStacks = math.floor(now / interval)
        local maxStacks = math.floor((decayP.maxBonus or 0.40) / (decayP.perTick or 0.04) + 0.5)
        runtimeState_.decayStacks = math.min(newStacks, maxStacks)
    end

    -- ---- 工具：计算单位的异常抗性减持续比例 ----
    local function getResistMult(unit)
        if not unit.attrs or not unit.attrs.final then return 1.0 end
        local res = math.min(unit.attrs.final[AD.ABNORMAL_RES] or 0, 80)  -- cap 80%
        return 1.0 - res / 100
    end

    -- ---- 远古之雾 / 时空裂隙：周期性 debuff（逐单位追踪到期时间） ----
    runtimeState_.periodicTimer = runtimeState_.periodicTimer + dt

    local fogP = getAffixParams("ancient_fog")
    if fogP then
        local interval = fogP.interval or 15
        local duration = fogP.duration or 8
        local cycle = interval + duration
        local phase = runtimeState_.periodicTimer % cycle
        local wasActive = runtimeState_.fogActive
        runtimeState_.fogActive = (phase >= interval)
        -- 施加
        if runtimeState_.fogActive and not wasActive then
            for _, ally in ipairs(allies) do
                if ally.attrs and ally.attrs.final and ally.hp > 0 then
                    local personalDur = duration * getResistMult(ally)
                    ally.attrs.final[AD.HIT_VALUE] = (ally.attrs.final[AD.HIT_VALUE] or 0) - fogP.hitReduce
                    ally._fogHitDebuff = fogP.hitReduce
                    ally._fogExpire = now + personalDur
                end
            end
        end
        -- 逐单位检查到期
        for _, ally in ipairs(allies) do
            if ally._fogHitDebuff and ally._fogExpire and now >= ally._fogExpire then
                ally.attrs.final[AD.HIT_VALUE] = (ally.attrs.final[AD.HIT_VALUE] or 0) + ally._fogHitDebuff
                ally._fogHitDebuff = nil
                ally._fogExpire = nil
            end
        end
        -- 全局结束时兜底清理（防残留）
        if not runtimeState_.fogActive and wasActive then
            for _, ally in ipairs(allies) do
                if ally._fogHitDebuff and ally.attrs and ally.attrs.final then
                    ally.attrs.final[AD.HIT_VALUE] = (ally.attrs.final[AD.HIT_VALUE] or 0) + ally._fogHitDebuff
                    ally._fogHitDebuff = nil
                    ally._fogExpire = nil
                end
            end
        end
    end

    local riftP = getAffixParams("time_rift")
    if riftP then
        local interval = riftP.interval or 15
        local duration = riftP.duration or 8
        local cycle = interval + duration
        local offsetTimer = math.max(0, runtimeState_.periodicTimer - interval * 0.5)
        local phase = offsetTimer % cycle
        local wasActive = runtimeState_.riftActive
        runtimeState_.riftActive = (phase >= interval)
        -- atkSpeedReduce 配置是小数形式（0.20 = 20%），ATK_SPEED 存储单位为百分比整数，需要 ×100
        local reduceValue = riftP.atkSpeedReduce * 100
        -- 施加
        if runtimeState_.riftActive and not wasActive then
            for _, ally in ipairs(allies) do
                if ally.attrs and ally.attrs.final and ally.hp > 0 then
                    local personalDur = duration * getResistMult(ally)
                    if ally.attrs.addModifier then
                        ally.attrs:removeModifier(RIFT_MOD_ID)
                        ally.attrs:addModifier(RIFT_MOD_ID, {
                            { key = AD.ATK_SPEED, flat = -reduceValue },
                        })
                    else
                        ally.attrs.final[AD.ATK_SPEED] = (ally.attrs.final[AD.ATK_SPEED] or 0) - reduceValue
                    end
                    ally._riftAtkDebuff = reduceValue
                    ally._riftExpire = now + personalDur
                    recalcUnitAttackInterval(ally)
                end
            end
        end
        -- 逐单位检查到期
        for _, ally in ipairs(allies) do
            if ally._riftAtkDebuff and ally._riftExpire and now >= ally._riftExpire then
                if ally.attrs and ally.attrs.removeModifier then
                    ally.attrs:removeModifier(RIFT_MOD_ID)
                elseif ally.attrs and ally.attrs.final then
                    ally.attrs.final[AD.ATK_SPEED] = (ally.attrs.final[AD.ATK_SPEED] or 0) + ally._riftAtkDebuff
                end
                ally._riftAtkDebuff = nil
                ally._riftExpire = nil
                recalcUnitAttackInterval(ally)
            end
        end
        -- 全局结束时兜底清理
        if not runtimeState_.riftActive and wasActive then
            for _, ally in ipairs(allies) do
                if ally._riftAtkDebuff and ally.attrs and ally.attrs.final then
                    if ally.attrs.removeModifier then
                        ally.attrs:removeModifier(RIFT_MOD_ID)
                    else
                        ally.attrs.final[AD.ATK_SPEED] = (ally.attrs.final[AD.ATK_SPEED] or 0) + ally._riftAtkDebuff
                    end
                    ally._riftAtkDebuff = nil
                    ally._riftExpire = nil
                    recalcUnitAttackInterval(ally)
                end
            end
        end
    end

    -- ---- 蚀甲之触：清理过期层 + 更新 attrs 缓存 ----
    local corrP = getAffixParams("corrode_armor")
    if corrP then
        for uid, stacks in pairs(runtimeState_.corrodeStacks) do
            local i = 1
            while i <= #stacks do
                if now >= stacks[i].expire then
                    table.remove(stacks, i)
                else
                    i = i + 1
                end
            end
            if #stacks == 0 then
                runtimeState_.corrodeStacks[uid] = nil
            end
        end
        -- 同步缓存到 allies 的 attrs 对象
        for _, ally in ipairs(allies) do
            local uid = getUnitKey(ally)
            if uid and ally.attrs then
                local stacks = runtimeState_.corrodeStacks[uid]
                if stacks and #stacks > 0 then
                    ally.attrs._corrodeArmorPct = math.min(#stacks * corrP.perHitPct, corrP.maxPct)
                else
                    ally.attrs._corrodeArmorPct = nil
                end
            end
        end
    end

    -- ---- 冰冻之莲：每隔N秒冰冻一个随机己方角色 ----
    local frostP = getAffixParams("frost_lotus")
    if frostP then
        runtimeState_.frostLotusTimer = runtimeState_.frostLotusTimer + dt
        local interval = frostP.interval or 7
        if runtimeState_.frostLotusTimer >= interval then
            runtimeState_.frostLotusTimer = runtimeState_.frostLotusTimer - interval
            -- 随机选一个存活且未被冰冻的己方单位
            local candidates = {}
            for _, ally in ipairs(allies) do
                if ally.hp > 0 and not SEM.isFrozen(ally) then
                    candidates[#candidates + 1] = ally
                end
            end
            if #candidates > 0 then
                local target = candidates[math.random(#candidates)]
                SEM.apply(target, SEM.FROZEN, frostP.freezeDuration, nil, nil)
            end
        end
    end
end

-- ======================== 战斗事件钩子 ========================

--- 濒死狂怒：检查怪物是否进入低血状态并应用增幅
--- 在每次怪物受伤后调用
---@param enemy table 受伤的怪物
function MapAffixSystem.onEnemyDamaged(enemy)
    if not activeAffixes_ then return end
    local p = getAffixParams("berserk_low_hp")
    if not p then return end
    if enemy._berserkApplied then return end  -- 已触发过

    local maxHp = enemy.attrs and enemy.attrs.final and enemy.attrs.final[AD.MAX_HP] or 1
    local hpPct = enemy.hp / maxHp
    if hpPct <= p.threshold then
        enemy._berserkApplied = true
        -- 攻速加成（atkSpeedBonus 为小数形式 0.40 = 40%，ATK_SPEED 单位为百分比整数）
        enemy.attrs.final[AD.ATK_SPEED] = (enemy.attrs.final[AD.ATK_SPEED] or 0) + p.atkSpeedBonus * 100
        local baseInterval = enemy.attrs.final[AD.ATK_INTERVAL] or 1.5
        enemy.atkInterval = baseInterval / (1 + (enemy.attrs.final[AD.ATK_SPEED] or 0) / 100)
        -- 伤害加成标记（由 getDamageMultiplier 读取）
        enemy._berserkDmgBonus = p.dmgBonus
    end
end

--- 复仇之誓：当一只怪物被击杀时触发
--- 返回 true 表示需要触发额外攻击回合
---@return boolean
function MapAffixSystem.onEnemyKilled()
    if not activeAffixes_ then return false end
    return getAffixParams("vengeance_oath") ~= nil
end

--- 蚀甲之触：怪物攻击命中时调用
---@param target table 被命中的己方 battle unit
function MapAffixSystem.onAllyHit(target)
    if not activeAffixes_ then return end
    local p = getAffixParams("corrode_armor")
    if not p then return end
    if not target.attrs or not target.attrs.final then return end

    local uid = getUnitKey(target)
    if not uid then return end

    local stacks = runtimeState_.corrodeStacks[uid] or {}
    -- 检查是否达到上限
    local currentPct = #stacks * p.perHitPct
    if currentPct >= p.maxPct then return end

    -- 计算实际持续时间（受异常抗性影响）
    local res = math.min(target.attrs.final[AD.ABNORMAL_RES] or 0, 80)
    local actualDuration = p.layerDuration * (1 - res / 100)

    -- 添加新层
    stacks[#stacks + 1] = { expire = runtimeState_.decayElapsed + actualDuration }
    runtimeState_.corrodeStacks[uid] = stacks

    -- 同步蚀甲比例到 attrs 对象上（供 CombatFormula 读取）
    local newPct = math.min(#stacks * p.perHitPct, p.maxPct)
    target.attrs._corrodeArmorPct = newPct
end

--- 获取目标当前蚀甲百分比（供伤害计算时扣减护甲）
--- 支持 battle unit 或 UnitAttributes 对象
---@param target table
---@return number 0~0.5 护甲降低比例
function MapAffixSystem.getCorrodeArmorPct(target)
    -- 快速路径：直接从 attrs 对象上读取缓存值
    if target._corrodeArmorPct then
        return target._corrodeArmorPct
    end
    -- 慢路径：通过 uid 查找（兼容 battle unit 直接调用）
    if not activeAffixes_ then return 0 end
    local p = getAffixParams("corrode_armor")
    if not p then return 0 end
    local uid = getUnitKey(target)
    if not uid then return 0 end
    local stacks = runtimeState_.corrodeStacks[uid]
    if not stacks or #stacks == 0 then return 0 end
    return math.min(#stacks * p.perHitPct, p.maxPct)
end

--- 厚重鳞甲：判断本次暴击是否被免疫
---@return boolean true=暴击被压制为普通伤害
function MapAffixSystem.shouldSuppressCrit()
    if not activeAffixes_ then return false end
    local p = getAffixParams("thick_scales")
    if not p then return false end
    return math.random() < p.chance
end

--- 衰败之地：获取当前怪物伤害加成倍率
---@return number 加成值（如0.12 = +12%）
function MapAffixSystem.getDecayDamageBonus()
    if not activeAffixes_ then return 0 end
    local p = getAffixParams("decay_land")
    if not p then return 0 end
    return runtimeState_.decayStacks * (p.perTick or 0.04)
end

--- 格挡压制：获取格挡率削减值
---@return number 削减值（如0.30 = -30 个百分点）
function MapAffixSystem.getBlockReduce()
    if not activeAffixes_ then return 0 end
    local p = getAffixParams("block_suppress")
    if not p then return 0 end
    return p.blockReduce
end

--- 格挡压制：对战斗用格挡率应用 debuff（从未截断值扣减，超 100% 可抵消）
---@param blockRate number 格挡率百分比（应使用 getUncapped 读取）
---@return number
function MapAffixSystem.applyBlockReduce(blockRate)
    if not blockRate or blockRate <= 0 then return 0 end
    local reduce = MapAffixSystem.getBlockReduce()
    if reduce <= 0 then return blockRate end
    return math.max(0, blockRate - reduce * 100)
end

--- 从 attrs 读取含词缀的战斗格挡率
---@param attrs table UnitAttributes
---@param blockRateKey string
---@return number
function MapAffixSystem.getEffectiveBlockRate(attrs, blockRateKey)
    if not attrs then return 0 end
    -- 必须用 getUncapped：面板可显示 150%，但 get() 会先截到 100%/神器上限；
    -- 格挡压制按“截断前数值 - 削减”计算，超 100% 部分才能抵消词缀（见 V1.0.24）。
    local rate = attrs.getUncapped and attrs:getUncapped(blockRateKey) or attrs:get(blockRateKey)
    return MapAffixSystem.applyBlockReduce(rate)
end

--- 生命猎手：获取对HP部分的额外伤害加成
---@return number 加成值（如0.12 = +12%）
function MapAffixSystem.getLifeHunterBonus()
    if not activeAffixes_ then return 0 end
    local p = getAffixParams("life_hunter")
    if not p then return 0 end
    return p.hpDmgBonus
end

--- 治疗荒漠：获取治疗削减值
---@return number 削减值（如0.40 = -40%）
function MapAffixSystem.getHealReduce()
    if not activeAffixes_ then return 0 end
    local p = getAffixParams("heal_desert")
    if not p then return 0 end
    return MapAffixConfig.clampHealReduce(p.healReduce)
end

--- 濒死狂怒：获取怪物额外伤害加成
---@param attacker table
---@return number 加成值
function MapAffixSystem.getBerserkDmgBonus(attacker)
    if attacker._berserkDmgBonus then
        return attacker._berserkDmgBonus
    end
    return 0
end

--- 远古之雾是否激活中
---@return boolean
function MapAffixSystem.isFogActive()
    return runtimeState_.fogActive
end

--- 时空裂隙是否激活中
---@return boolean
function MapAffixSystem.isRiftActive()
    return runtimeState_.riftActive
end

return MapAffixSystem
