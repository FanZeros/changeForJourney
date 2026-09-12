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

-- ======================== 效果类型常量 ========================

SEM.BURNING    = "burning"     -- 燃烧DOT (麦琪)
SEM.SHOCKED    = "shocked"     -- 感电增伤 (露娜)
SEM.FROZEN     = "frozen"      -- 冰冻停攻 (艾丝翠德)
SEM.MARKED     = "marked"      -- 标记增伤 (绫音)
SEM.HOT        = "hot"         -- 持续治疗 (芙罗拉)
SEM.VULNERABLE = "vulnerable"  -- 易伤诅咒 (转职天赋105/209/210)
SEM.ARCANE_MARK = "arcane_mark" -- 秘法印记 (星图节点113)，与 VULNERABLE 独立叠乘

-- ======================== 效果表 ========================
-- 结构: effects[unit] = { [effectType] = { remaining, source, data, tickTimer } }

local effects = {}

-- ======================== 核心 API ========================

--- 重置所有效果（关卡切换时调用）
function SEM.reset()
    effects = {}
end

--- 施加状态效果（同类型刷新）
---@param unit table 目标单位
---@param effectType string 效果类型常量
---@param baseDuration number 基础持续时间（秒）
---@param source table 施加者单位
---@param data table 效果数据 { dps=, mult=, hps= }
function SEM.apply(unit, effectType, baseDuration, source, data)
    if not unit or unit.hp <= 0 then return end

    -- 异常抗性减免（MARKED 不受抗性影响，属于战术标记）
    local duration = baseDuration
    if effectType ~= SEM.MARKED and unit.attrs then
        local abnormalRes = unit.attrs:get(AD.ABNORMAL_RES) or 0
        duration = CF.calcAbnormalDuration(baseDuration, abnormalRes)
    end

    if duration <= 0 then
        statusLog("[SEM] " .. unit.name .. " 抗性抵御了 " .. effectType)
        return
    end

    if not effects[unit] then
        effects[unit] = {}
    end

    -- 叠层支持：data.stackable=true 时叠加而非覆盖
    local d = data or {}
    if d.stackable and effectType == SEM.BURNING then
        local existing = effects[unit][effectType]
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

    -- 同类型刷新（覆盖）
    effects[unit][effectType] = {
        remaining = duration,
        source    = source,
        data      = d,
        tickTimer = 0,  -- DOT/HOT 每秒 tick 计时器
    }

    statusLog("[SEM] " .. unit.name .. " 获得 " .. effectType .. " (" .. string.format("%.1f", duration) .. "s)")
end

--- 移除指定效果
---@param unit table
---@param effectType string
function SEM.remove(unit, effectType)
    if effects[unit] then
        effects[unit][effectType] = nil
        -- 清理空表
        if not next(effects[unit]) then
            effects[unit] = nil
        end
    end
end

--- 清理单位所有效果（单位死亡/移除时调用）
---@param unit table
function SEM.removeUnit(unit)
    effects[unit] = nil
end

--- 查询是否有指定效果
---@param unit table
---@param effectType string
---@return boolean
function SEM.has(unit, effectType)
    return effects[unit] ~= nil and effects[unit][effectType] ~= nil
end

--- 获取指定效果数据
---@param unit table
---@param effectType string
---@return table|nil
function SEM.get(unit, effectType)
    if effects[unit] then
        return effects[unit][effectType]
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
    if not effects[unit] then return mult end

    local shocked = effects[unit][SEM.SHOCKED]
    if shocked then
        mult = mult * (1.0 + (shocked.data.mult or 0.20))
    end

    local marked = effects[unit][SEM.MARKED]
    if marked then
        mult = mult * (1.0 + (marked.data.mult or 0.25))
    end

    local vuln = effects[unit][SEM.VULNERABLE]
    if vuln then
        mult = mult * (1.0 + (vuln.data.mult or 0.20))
    end

    local arcaneMark = effects[unit][SEM.ARCANE_MARK]
    if arcaneMark then
        mult = mult * (1.0 + (arcaneMark.data.mult or 0.08))
    end

    -- 冰冻增伤（觉醒效果 Hero12 Node2: data.extraDmgMult）
    local frozen = effects[unit][SEM.FROZEN]
    if frozen and frozen.data.extraDmgMult then
        mult = mult * (1.0 + frozen.data.extraDmgMult)
    end

    local hot = effects[unit][SEM.HOT]
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
    if effects[unit] then
        for effectType, _ in pairs(effects[unit]) do
            local vis = VISUAL_MAP[effectType]
            if vis then
                result[#result + 1] = { icon = vis.icon, r = vis.r, g = vis.g, b = vis.b }
            end
        end
    end
    return result
end

--- 每帧更新：倒计时、DOT/HOT tick
---@param dt number 帧间隔（秒）
---@param callbacks table { onDot=function(unit,source,damage), onHot=function(unit,source,heal) }
function SEM.update(dt, callbacks)
    callbacks = callbacks or {}

    for unit, unitEffects in pairs(effects) do
        -- 跳过已死亡单位
        if unit.hp <= 0 then
            effects[unit] = nil
        else
            local toRemove = {}

            for effectType, effect in pairs(unitEffects) do
                -- 倒计时
                effect.remaining = effect.remaining - dt

                if effect.remaining <= 0 then
                    toRemove[#toRemove + 1] = effectType
                else
                    -- DOT tick（燃烧）
                    if effectType == SEM.BURNING and callbacks.onDot then
                        effect.tickTimer = effect.tickTimer + dt
                        while effect.tickTimer >= 1.0 do
                            effect.tickTimer = effect.tickTimer - 1.0
                            local dps = effect.data.dps or 0
                            if dps > 0 then
                                local tickDmg = math.floor(dps + 0.5)
                                -- 燃烧暴击支持（觉醒 Hero2 Node3/6）
                                local isBurnCrit = false
                                if effect.data.canCrit then
                                    local cr = effect.data.critRate or 0
                                    if math.random() * 100 < cr then
                                        isBurnCrit = true
                                        local cd = effect.data.critDmg or 50
                                        tickDmg = math.floor(tickDmg * (1 + cd / 100) + 0.5)
                                    end
                                end
                                callbacks.onDot(unit, effect.source, tickDmg, isBurnCrit)
                            end
                        end
                    end

                    -- HOT tick（持续治疗）
                    if effectType == SEM.HOT and callbacks.onHot then
                        effect.tickTimer = effect.tickTimer + dt
                        while effect.tickTimer >= 1.0 do
                            effect.tickTimer = effect.tickTimer - 1.0
                            local hps = effect.data.hps or 0
                            if hps > 0 then
                                callbacks.onHot(unit, effect.source, math.floor(hps + 0.5))
                            end
                        end
                    end
                end
            end

            -- 移除到期效果
            for _, effectType in ipairs(toRemove) do
                unitEffects[effectType] = nil
                statusLog("[SEM] " .. unit.name .. " 的 " .. effectType .. " 效果到期")
            end

            -- 清理空表
            if not next(unitEffects) then
                effects[unit] = nil
            end
        end
    end
end

return SEM
