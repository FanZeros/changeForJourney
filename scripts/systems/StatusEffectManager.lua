-- ============================================================================
-- StatusEffectManager - 状态效果管理器
-- 管理战斗中的持续状态效果（燃烧、感电、冰冻、标记、持续治疗）
-- 模块级单例，参考 ThreatManager 模式
-- ============================================================================

local AD = require("systems.AttributeDef")
local CF = require("systems.CombatFormula")
local Diag = require("systems.BattleDiag")

local function statusLog(msg)
    if Diag.logEnabled then
        print(msg)
    end
end

local SEM = {}
---@class StatusEffectEntry
---@field remaining number
---@field source table
---@field data table
---@field tickTimer number
---@class StatusEffectState
---@field effects table<table, table<string, StatusEffectEntry>>
-- [多实例] 状态效果表随战斗 mount 切换（避免并行战斗 DOT/HOT 多重 tick）
---@return StatusEffectState
local function newSemState()
    return { effects = {} }
end
local SEM_DEFAULT = newSemState()
local SEM_BCS = SEM_DEFAULT
function SEM.newSemState() return newSemState() end
function SEM.mount(s) SEM_BCS = s or SEM_DEFAULT end
function SEM.mountedState() return SEM_BCS end


-- ======================== 效果类型常量 ========================

SEM.BURNING    = "burning"     -- 燃烧DOT (黄桃龙)
SEM.SHOCKED    = "shocked"     -- 感电增伤 (阿姨压)
SEM.FROZEN     = "frozen"      -- 冰冻停攻 (雪皇)
SEM.MARKED     = "marked"      -- 标记增伤 (愤怒的小雀)
SEM.HOT        = "hot"         -- 持续治疗 (卡皮巴拉)
SEM.VULNERABLE = "vulnerable"  -- 易伤诅咒 (转职天赋105/209/210)
SEM.ARCANE_MARK = "arcane_mark" -- 秘法印记 (星图节点113)，与 VULNERABLE 独立叠乘

-- ======================== 效果表 ========================
-- 结构: SEM_BCS.effects[unit] = { [effectType] = { remaining, source, data, tickTimer } }


-- ======================== 核心 API ========================

--- 重置所有效果（关卡切换时调用）
function SEM.reset()
    SEM_BCS.effects = {}
end

--- 施加状态效果（同类型刷新）
---@param unit table 目标单位
---@param effectType string 效果类型常量
---@param baseDuration number 基础持续时间（秒）
---@param source table 施加者单位
---@param data table 效果数据 { dps=, mult=, hps= }
function SEM.apply(unit, effectType, baseDuration, source, data)
    if not unit or unit.hp <= 0 then return end

    -- HOT 是正面治疗；MARKED 是战术标记，均不受异常抗性缩时。
    local duration = baseDuration
    if effectType ~= SEM.MARKED and effectType ~= SEM.HOT and unit.attrs then
        local abnormalRes = unit.attrs:get(AD.ABNORMAL_RES) or 0
        duration = CF.calcAbnormalDuration(baseDuration, abnormalRes)
    end

    if duration <= 0 then
        statusLog("[SEM] " .. unit.name .. " 抗性抵御了 " .. effectType)
        return
    end

    if not SEM_BCS.effects[unit] then
        SEM_BCS.effects[unit] = {}
    end

    -- 叠层支持：data.stackable=true 时叠加而非覆盖
    local d = data or {}
    if d.stackable and effectType == SEM.BURNING then
        local existing = SEM_BCS.effects[unit][effectType]
        if existing then
            local maxStacks = d.maxStacks or 3
            local curStacks = existing.data.stacks or 1
            if curStacks < maxStacks then
                -- 叠加一层：累加 dps，刷新持续时间
                existing.data.stacks = curStacks + 1
                existing.data.dps = (existing.data.dps or 0) + (d.dps or 0)
                existing.remaining = duration
                existing.tickTimer = existing.tickTimer  -- 保留 tick 进度
                -- 传递暴击属性
                if d.canCrit then existing.data.canCrit = true end
                if d.critRate then existing.data.critRate = d.critRate end
                if d.critDmg  then existing.data.critDmg  = d.critDmg  end
                statusLog("[SEM] " .. unit.name .. " 燃烧叠加至 " .. existing.data.stacks .. " 层")
                return
            else
                -- 已满层：仅刷新持续时间
                existing.remaining = duration
                statusLog("[SEM] " .. unit.name .. " 燃烧已满 " .. maxStacks .. " 层，刷新持续时间")
                return
            end
        end
        -- 首次施加带叠层标记
        d.stacks = 1
    end

    -- HOT 刷新只换来源/数据/持续时间，保留已经走过的秒跳进度。
    -- 使用新效果身份：tick 回调中的刷新不会被旧效果的到期清理误删。
    local previous = SEM_BCS.effects[unit][effectType]
    local tickTimer = effectType == SEM.HOT and previous and previous.tickTimer or 0
    SEM_BCS.effects[unit][effectType] = {
        remaining = duration,
        source    = source,
        data      = d,
        tickTimer = tickTimer,  -- 普通燃烧覆盖仍重置；叠层燃烧走上方原规则
    }

    statusLog("[SEM] " .. unit.name .. " 获得 " .. effectType .. " (" .. string.format("%.1f", duration) .. "s)")
end

--- 移除指定效果
---@param unit table
---@param effectType string
function SEM.remove(unit, effectType)
    if SEM_BCS.effects[unit] then
        SEM_BCS.effects[unit][effectType] = nil
        -- 清理空表
        if not next(SEM_BCS.effects[unit]) then
            SEM_BCS.effects[unit] = nil
        end
    end
end

--- 清理单位所有效果（单位死亡/移除时调用）
---@param unit table
function SEM.removeUnit(unit)
    SEM_BCS.effects[unit] = nil
end

--- 查询是否有指定效果
---@param unit table
---@param effectType string
---@return boolean
function SEM.has(unit, effectType)
    return SEM_BCS.effects[unit] ~= nil and SEM_BCS.effects[unit][effectType] ~= nil
end

--- 获取指定效果数据
---@param unit table
---@param effectType string
---@return StatusEffectEntry|nil
function SEM.get(unit, effectType)
    if SEM_BCS.effects[unit] then
        return SEM_BCS.effects[unit][effectType]
    end
    return nil
end

--- 检查单位是否被冰冻（攻击进度检查专用）
---@param unit table
---@return boolean
function SEM.isFrozen(unit)
    return SEM.has(unit, SEM.FROZEN)
end

--- 获取燃烧叠层数
---@param unit table
---@return number 叠层数（无燃烧返回0）
function SEM.getBurningStacks(unit)
    local e = SEM.get(unit, SEM.BURNING)
    if e then return e.data.stacks or 1 end
    return 0
end

--- 统计当前处于指定状态的单位数量（从列表中）
---@param unitList table 单位列表
---@param effectType string 效果类型
---@return number
function SEM.countUnitsWithEffect(unitList, effectType)
    local count = 0
    for _, u in ipairs(unitList) do
        if u.hp > 0 and SEM.has(u, effectType) then
            count = count + 1
        end
    end
    return count
end

--- 获取受伤倍率（感电+20%、标记+25%，可叠乘）
---@param unit table
---@return number 倍率（无效果返回1.0）
function SEM.getDamageTakenMult(unit)
    local mult = 1.0
    if not SEM_BCS.effects[unit] then return mult end

    local shocked = SEM_BCS.effects[unit][SEM.SHOCKED]
    if shocked then
        mult = mult * (1.0 + (shocked.data.mult or 0.20))
    end

    local marked = SEM_BCS.effects[unit][SEM.MARKED]
    if marked then
        mult = mult * (1.0 + (marked.data.mult or 0.25))
    end

    local vuln = SEM_BCS.effects[unit][SEM.VULNERABLE]
    if vuln then
        mult = mult * (1.0 + (vuln.data.mult or 0.20))
    end

    local arcaneMark = SEM_BCS.effects[unit][SEM.ARCANE_MARK]
    if arcaneMark then
        mult = mult * (1.0 + (arcaneMark.data.mult or 0.08))
    end

    -- 冰冻增伤（觉醒效果 Hero12 Node2: data.extraDmgMult）
    local frozen = SEM_BCS.effects[unit][SEM.FROZEN]
    if frozen and frozen.data.extraDmgMult then
        mult = mult * (1.0 + frozen.data.extraDmgMult)
    end

    local hot = SEM_BCS.effects[unit][SEM.HOT]
    if hot and hot.data and hot.data.dmgReduction then
        mult = mult * 0.95
    end

    return mult
end

-- 视觉样式映射
local VISUAL_MAP = {
    [SEM.BURNING] = { icon = "🔥", r = 255, g = 100, b = 30  },
    [SEM.SHOCKED] = { icon = "⚡", r = 180, g = 180, b = 255 },
    [SEM.FROZEN]  = { icon = "❄️",  r = 100, g = 200, b = 255 },
    [SEM.MARKED]  = { icon = "🎯", r = 255, g = 80,  b = 80  },
    [SEM.HOT]        = { icon = "💚", r = 80,  g = 255, b = 120 },
    [SEM.VULNERABLE] = { icon = "💀", r = 200, g = 50,  b = 200 },
    [SEM.ARCANE_MARK] = { icon = "🔮", r = 160, g = 100, b = 255 },
}

--- 获取单位当前的视觉效果列表（渲染用，返回数组）
---@param unit table
---@return table[] { {icon, r, g, b}, ... }
function SEM.getVisuals(unit)
    local result = {}
    if SEM_BCS.effects[unit] then
        for effectType, _ in pairs(SEM_BCS.effects[unit]) do
            local vis = VISUAL_MAP[effectType]
            if vis then
                result[#result + 1] = { icon = vis.icon, r = vis.r, g = vis.g, b = vis.b }
            end
        end
    end
    return result
end

-- 仅吸收秒跳/到期计算的浮点舍入误差，不把整帧 dt 当容差。
local TIME_EPSILON = 1e-9

--- 每帧更新：只消耗有效生命周期内的 dt，先完成到期边界的秒跳再清理。
---@param dt number 帧间隔（秒）
---@param callbacks table { onDot=function(unit,source,damage), onHot=function(unit,source,heal) }
function SEM.update(dt, callbacks)
    if not (dt > 0) or dt == math.huge then return end
    callbacks = callbacks or {}
    local state, effects = SEM_BCS, SEM_BCS.effects

    -- 回调可以施加/移除状态、清场甚至切换 mount。固定本帧身份，新增效果从下帧计时。
    local pending = {}
    for unit, unitEffects in pairs(effects) do
        for effectType, effect in pairs(unitEffects) do
            pending[#pending + 1] = { unit = unit, unitEffects = unitEffects,
                effectType = effectType, effect = effect }
        end
    end

    for _, entry in ipairs(pending) do
        if SEM_BCS ~= state or state.effects ~= effects then return end
        local unit, unitEffects = entry.unit, entry.unitEffects
        local effectType, effect = entry.effectType, entry.effect
        local function isCurrent()
            return SEM_BCS == state and state.effects == effects
                and effects[unit] == unitEffects and unitEffects[effectType] == effect
        end

        if unit.hp <= 0 then
            effects[unit] = nil
        elseif isCurrent() then
            local activeDt = math.min(dt, math.max(0, effect.remaining))
            local onTick = effectType == SEM.BURNING and callbacks.onDot
                or effectType == SEM.HOT and callbacks.onHot
            if onTick then
                -- 分段走到每个秒跳：回调刷新时只继承已经走过的相位，不能继承整帧未来跳数。
                -- activeDt 固定在本帧原效果生命周期内，超期 dt 不再结算。
                local left = activeDt
                while left > 0 and unit.hp > 0 and isCurrent() do
                    local step = math.min(left, math.max(0, 1.0 - effect.tickTimer))
                    effect.remaining = math.max(0, effect.remaining - step)
                    effect.tickTimer = effect.tickTimer + step
                    left = left - step
                    if effect.tickTimer + TIME_EPSILON >= 1.0 then
                        effect.tickTimer = math.max(0, effect.tickTimer - 1.0)
                        if effectType == SEM.BURNING then
                            local dps = effect.data.dps or 0
                            if dps > 0 then
                                local tickDmg = math.floor(dps + 0.5)
                                -- 燃烧暴击支持（觉醒 Hero2 Node3/6），原骰序/倍率不变。
                                local isBurnCrit = false
                                if effect.data.canCrit then
                                    local cr = effect.data.critRate or 0
                                    if math.random() * 100 < cr then
                                        isBurnCrit = true
                                        local cd = effect.data.critDmg or 50
                                        tickDmg = math.floor(tickDmg * (1 + cd / 100) + 0.5)
                                    end
                                end
                                onTick(unit, effect.source, tickDmg, isBurnCrit)
                            end
                        else
                            local hps = effect.data.hps or 0
                            if hps > 0 then
                                onTick(unit, effect.source, math.floor(hps + 0.5))
                            end
                        end
                    end
                    -- 叠层燃烧在回调内原位刷新 remaining，继续保留其叠层/来源规则。
                    if effect.remaining <= TIME_EPSILON then break end
                end
            else
                -- 没有对应回调时仍倒计时，不补记未处理的 DOT/HOT 秒跳（保留原约定）。
                effect.remaining = math.max(0, effect.remaining - activeDt)
            end

            if SEM_BCS ~= state or state.effects ~= effects then return end
            if unit.hp <= 0 then
                effects[unit] = nil
            elseif isCurrent() then
                if effect.remaining <= TIME_EPSILON then
                    unitEffects[effectType] = nil
                    statusLog("[SEM] " .. unit.name .. " 的 " .. effectType .. " 效果到期")
                end
                if not next(unitEffects) then effects[unit] = nil end
            end
        end
    end
end

return SEM
