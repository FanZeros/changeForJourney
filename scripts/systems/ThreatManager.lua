-- ============================================================================
-- ThreatManager - 团队仇恨值管理器
-- 管理战斗中全队敌人对己方单位的共享仇恨值
-- 所有敌方单位基于相同的仇恨权重选择目标
-- 支持：仇恨产生（伤害/治疗）、仇恨衰减、仇恨加权目标选择
-- 支持：按职业差异化仇恨系数（ClassConfig 驱动）
-- ============================================================================

local AD = require("systems.AttributeDef")
local CC = require("config.ClassConfig")
local BattleLayout = require("core.BattleLayout")

local TM = {}
-- ======================== [多实例] 战斗状态容器 ========================
-- 每场并行战斗一个实例; TM.mount(s) 切换当前模拟的战斗
local function newState()
    return {
        threatTable = {},            -- threatTable[target] = threatValue
        hasKnightOrWarrior = false,  -- 队伍中是否有骑士/战士存活（射手天赋用）
        forcedTarget = nil,
        forcedTargetTimer = 0,
        knightFirstAttackReady = {}, -- [unit] = true，本场战斗骑士首次攻击仇恨倍率待触发
    }
end
local TM_DEFAULT = newState()
local TM_BCS = TM_DEFAULT
function TM.newState() return newState() end
function TM.mount(s) TM_BCS = s or TM_DEFAULT end
function TM.mountedState() return TM_BCS end

local ArtifactRuntime
local function getArtifactRuntime()
    if not ArtifactRuntime then ArtifactRuntime = require("systems.ArtifactRuntime") end
    return ArtifactRuntime
end

-- ======================== 默认配置（无职业时的兜底值） ========================

-- 仇恨产生系数（当单位没有 classId 时使用）
TM.DEFAULT_BASE_ATTACK_THREAT = 5     -- 默认攻击基础仇恨
TM.DEFAULT_DMG_THREAT_COEFF   = 1.0   -- 默认每点伤害仇恨系数
TM.DEFAULT_HEAL_THREAT_BASE   = 25    -- 默认治疗基础仇恨
TM.DEFAULT_HEAL_THREAT_COEFF  = 1.0   -- 默认每点治疗仇恨系数

-- 仇恨衰减
TM.DECAY_RATE         = 0.02    -- 每秒衰减当前仇恨值的 2%
TM.DECAY_MIN          = 0.5     -- 每秒最低衰减量

-- 目标选择中 静态仇恨属性(AD.THREAT) 的影响权重
TM.STATIC_THREAT_WEIGHT = 10    -- AD.THREAT 每 1 点 = 10 点动态仇恨等价

-- 骑士天赋"阵前叫嚣"：每场战斗第一次攻击获得20倍仇恨
TM.KNIGHT_FIRST_ATTACK_THREAT_MULT = 20

-- 射手天赋"远程攻击"：队伍中有骑士/战士时仇恨获得倍率降低
TM.RANGER_THREAT_REDUCTION = 0.80  -- 降低80%（即仇恨乘以0.2）

-- ======================== 仇恨表 ========================
-- 结构: TM_BCS.threatTable[target] = threatValue
-- 全队共享：所有敌方单位基于同一张仇恨表选择目标


-- ======================== 核心 API ========================

--- 重置所有仇恨数据（关卡切换时调用）
function TM.reset()
    TM_BCS.threatTable = {}
    TM_BCS.hasKnightOrWarrior = false
    TM_BCS.forcedTarget = nil
    TM_BCS.forcedTargetTimer = 0
    TM_BCS.knightFirstAttackReady = {}
end

--- 清除指定单位的仇恨记录（单位死亡/移除时调用）
---@param unit table 要移除的单位引用
function TM.removeUnit(unit)
    TM_BCS.threatTable[unit] = nil
    TM_BCS.knightFirstAttackReady[unit] = nil
    if TM_BCS.forcedTarget == unit then
        TM_BCS.forcedTarget = nil
        TM_BCS.forcedTargetTimer = 0
    end
end

--- 获取指定目标的团队仇恨值
---@param target table 目标（己方单位）
---@return number 仇恨值
function TM.getThreat(target)
    return TM_BCS.threatTable[target] or 0
end

--- 增加仇恨值
---@param target table 被仇恨的目标（己方单位）
---@param amount number 仇恨增量（已含倍率）
function TM.addThreat(target, amount)
    if amount <= 0 then return end
    amount = getArtifactRuntime().adjustThreatGain(target, amount)
    if amount <= 0 then return end
    local old = TM_BCS.threatTable[target] or 0
    TM_BCS.threatTable[target] = old + amount
end

--- 清空指定单位的动态仇恨值
---@param target table 目标单位
function TM.clearThreat(target)
    if not target then return end
    TM_BCS.threatTable[target] = 0
end

--- 按比例清除指定单位的动态仇恨值
---@param target table 目标单位
---@param percent number 清除比例，100表示全部清除
function TM.reduceThreatPercent(target, percent)
    if not target then return end
    percent = math.max(0, math.min(100, tonumber(percent) or 0))
    if percent <= 0 then return end
    local old = TM_BCS.threatTable[target] or 0
    TM_BCS.threatTable[target] = math.max(0, old * (1 - percent / 100))
end

--- 设置指定单位的动态仇恨值
---@param target table 目标单位
---@param amount number 仇恨值
function TM.setThreat(target, amount)
    if not target then return end
    TM_BCS.threatTable[target] = math.max(0, tonumber(amount) or 0)
end

--- 嘲讽：确保目标仇恨至少领先其他存活队友指定数值
---@param target table 嘲讽单位
---@param allyList table 己方单位列表
---@param leadAmount number 领先数值
function TM.tauntToLead(target, allyList, leadAmount)
    if not target or target.hp <= 0 then return end
    local maxThreat = 0
    for _, ally in ipairs(allyList or {}) do
        if ally ~= target and ally.hp > 0 then
            local threat = TM_BCS.threatTable[ally] or 0
            if threat > maxThreat then maxThreat = threat end
        end
    end
    local targetThreat = TM_BCS.threatTable[target] or 0
    local desired = maxThreat + math.max(0, leadAmount or 0)
    if targetThreat < desired then
        TM_BCS.threatTable[target] = desired
    end
end

--- 强制嘲讽：短时间内敌人优先选择该目标
---@param target table 嘲讽单位
---@param duration number 持续时间（秒）
function TM.forceTarget(target, duration)
    if not target or target.hp <= 0 then return end
    TM_BCS.forcedTarget = target
    TM_BCS.forcedTargetTimer = math.max(TM_BCS.forcedTargetTimer or 0, duration or 0)
end

--- 战斗开始时初始化仇恨（处理骑士天赋"阵前叫嚣"等）
--- 应在 loadStage 或 resetBattle 后、战斗开始前调用
---@param allies table 己方单位列表
---@param enemies table 敌方单位列表
function TM.onBattleStart(allies, enemies)
    -- 检测队伍中是否有骑士/战士存活（用于射手天赋"远程攻击"）
    TM_BCS.hasKnightOrWarrior = false
    for _, ally in ipairs(allies) do
        if ally.hp > 0 and (ally.classId == CC.KNIGHT or ally.classId == CC.WARRIOR) then
            TM_BCS.hasKnightOrWarrior = true
            break
        end
    end

    for _, ally in ipairs(allies) do
        if ally.classId == CC.KNIGHT and ally.hp > 0 then
            TM_BCS.knightFirstAttackReady[ally] = true
            print("[Threat] 骑士 " .. ally.name .. " 阵前叫嚣: 首次攻击仇恨×" .. TM.KNIGHT_FIRST_ATTACK_THREAT_MULT)
        end
    end

    if TM_BCS.hasKnightOrWarrior then
        print("[Threat] 队伍中有骑士/战士，射手仇恨倍率降低" .. (TM.RANGER_THREAT_REDUCTION * 100) .. "%")
    end
end

--- 造成伤害时产生仇恨
--- 使用单位的 classId 查找对应职业的仇恨系数
---@param damageSource table 造成伤害的己方单位
---@param damage number 实际伤害量
---@param includeBaseThreat boolean|nil 是否计入本次攻击基础仇恨；多目标攻击只应有一次为 true
---@param threatScale number|nil 仇恨倍率缩放（如灵月飞剑 0.1）；默认 1.0
function TM.onDamageDealt(damageSource, damage, includeBaseThreat, threatScale)
    if not damageSource then return end
    if includeBaseThreat == nil then includeBaseThreat = true end
    if threatScale == nil then threatScale = 1.0 end
    damage = math.floor((damage or 0) + 0.0001)
    -- 获取职业仇恨系数
    local classId = damageSource.classId
    local baseThreat, dmgCoeff

    if classId then
        baseThreat = CC.getBaseAttackThreat(classId)
        dmgCoeff   = CC.getDmgThreatCoeff(classId)
    else
        baseThreat = TM.DEFAULT_BASE_ATTACK_THREAT
        dmgCoeff   = TM.DEFAULT_DMG_THREAT_COEFF
    end

    -- AD.THREAT 属性倍率
    local threatMult = 1.0
    if damageSource.attrs then
        threatMult = damageSource.attrs:get(AD.THREAT)
        if threatMult < 1 then threatMult = 1 end
    end

    local amount = ((includeBaseThreat and baseThreat or 0) + damage * dmgCoeff) * threatMult * threatScale

    if includeBaseThreat and classId == CC.KNIGHT and TM_BCS.knightFirstAttackReady[damageSource] then
        amount = amount * TM.KNIGHT_FIRST_ATTACK_THREAT_MULT
        TM_BCS.knightFirstAttackReady[damageSource] = nil
        print("[Threat] 骑士 " .. tostring(damageSource.name) .. " 阵前叫嚣首次攻击: 仇恨×" .. TM.KNIGHT_FIRST_ATTACK_THREAT_MULT)
    end

    -- 射手天赋"远程攻击"：队伍有骑士/战士时仇恨降低80%
    if classId == CC.RANGER and TM_BCS.hasKnightOrWarrior then
        amount = amount * (1.0 - TM.RANGER_THREAT_REDUCTION)
    end

    TM.addThreat(damageSource, amount)
end

--- 治疗时产生仇恨（团队共享）
---@param healer table 治疗者（己方单位）
---@param healAmount number 治疗量
function TM.onHealingDone(healer, healAmount)
    local classId = healer.classId
    local healBase, healCoeff

    if classId then
        healBase  = CC.getHealThreatBase(classId)
        healCoeff = CC.getHealThreatCoeff(classId)
    else
        healBase  = TM.DEFAULT_HEAL_THREAT_BASE
        healCoeff = TM.DEFAULT_HEAL_THREAT_COEFF
    end

    -- AD.THREAT 属性倍率
    local threatMult = 1.0
    if healer.attrs then
        threatMult = healer.attrs:get(AD.THREAT)
        if threatMult < 1 then threatMult = 1 end
    end

    local amount = (healBase + healAmount * healCoeff) * threatMult

    -- 射手天赋"远程攻击"：队伍有骑士/战士时仇恨降低80%
    if classId == CC.RANGER and TM_BCS.hasKnightOrWarrior then
        amount = amount * (1.0 - TM.RANGER_THREAT_REDUCTION)
    end

    TM.addThreat(healer, amount)
end

--- 每帧更新：仇恨衰减
---@param dt number 帧间隔（秒）
function TM.update(dt)
    if TM_BCS.forcedTarget then
        TM_BCS.forcedTargetTimer = TM_BCS.forcedTargetTimer - dt
        if TM_BCS.forcedTargetTimer <= 0 or TM_BCS.forcedTarget.hp <= 0 then
            TM_BCS.forcedTarget = nil
            TM_BCS.forcedTargetTimer = 0
        end
    end
    for target, threat in pairs(TM_BCS.threatTable) do
        local decay = math.max(TM.DECAY_MIN * dt, threat * TM.DECAY_RATE * dt)
        local newThreat = threat - decay
        if newThreat <= 0 then
            TM_BCS.threatTable[target] = nil
        else
            TM_BCS.threatTable[target] = newThreat
        end
    end
end

--- 基于团队仇恨选择目标
--- 结合动态仇恨值 + 静态 AD.THREAT 属性做加权随机
---@param targetList table 目标列表（己方单位）
---@return number 被选中目标在列表中的索引（1-based），0 = 无有效目标
function TM.selectTarget(targetList)
    if TM_BCS.forcedTarget and TM_BCS.forcedTarget.hp > 0 and TM_BCS.forcedTargetTimer > 0 and not TM_BCS.forcedTarget.artifactUntargetable then
        for i, u in ipairs(targetList) do
            if u == TM_BCS.forcedTarget then
                return i
            end
        end
    end

    local alive = {}
    local totalWeight = 0

    for i, u in ipairs(targetList) do
        if u.hp > 0 and not u.artifactUntargetable then
            local dynamicThreat = TM.getThreat(u)

            local staticThreat = 1
            if u.attrs then
                staticThreat = u.attrs:get(AD.THREAT)
                if staticThreat < 1 then staticThreat = 1 end
            end
            local staticBonus = staticThreat * TM.STATIC_THREAT_WEIGHT

            -- [前后排] 乘以位置受击权重: 前排(靠中心)被攻击概率显著更高
            local weight = (dynamicThreat + staticBonus) * BattleLayout.hitWeight(i)
            totalWeight = totalWeight + weight
            alive[#alive + 1] = { index = i, weight = weight }
        end
    end

    if #alive == 0 then return 0 end
    if #alive == 1 then return alive[1].index end

    local roll = math.random() * totalWeight
    local cumulative = 0
    for _, a in ipairs(alive) do
        cumulative = cumulative + a.weight
        if roll <= cumulative then
            return a.index
        end
    end
    return alive[#alive].index
end

--- 获取全部仇恨列表（调试用）
---@return table[] { unit, threat }
function TM.getThreatsFor()
    local result = {}
    for target, threat in pairs(TM_BCS.threatTable) do
        result[#result + 1] = { unit = target, threat = threat }
    end
    table.sort(result, function(a, b) return a.threat > b.threat end)
    return result
end

return TM
