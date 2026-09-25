-- ============================================================================
-- BattleCombatAnim - 卡牌攻击/受击/入场/死亡/补位 动画状态机
-- 从 BattleCombat 抽出；状态仍写在调用方传入的 BCS.cardAnims 上
-- ============================================================================

local PS = require("ui.battle.combat.ProjectileSystem")
local BattleLayout = require("core.BattleLayout")
local SettingsPanel = require("ui.hud.popup.SettingsPanel")

local M = {}

-- 攻击动画
local LUNGE_DISTANCE   = 60
local LUNGE_DURATION   = 0.12
local RETURN_DURATION  = 0.15
local RECOIL_DURATION  = 0.08
local RECOIL_RETURN    = 0.12
local RECOIL_DISTANCE  = 30
local CHARGE_START     = 0.7
local CHARGE_DISTANCE  = 25

-- 纵向弧线抖动（弧顶高度，像素）：攻击冲刺/回位、受击后退、蓄力前摇
local LUNGE_ARC_HEIGHT  = 18
local RECOIL_ARC_HEIGHT = 10
local CHARGE_ARC_HEIGHT = 6

-- 死亡/复活动画
local DEATH_HITSTOP        = 0.06
local DEATH_BURST_DUR      = 0.22
local DEATH_SETTLE_DUR     = 0.12
local DEATH_ANIM_DURATION  = DEATH_HITSTOP + DEATH_BURST_DUR + DEATH_SETTLE_DUR
local DEATH_ANIM_DISTANCE  = 80
local DEATH_OVERSHOOT      = 1.15
local REVIVE_ANIM_DURATION = 0.35
local REVIVE_ANIM_DISTANCE = 80
local TOMBSTONE_FADEIN     = 0.25

-- 队列前移补位（条带布局：敌人死亡后，后方敌人前移一格填入空位）
local ADVANCE_DURATION     = 0.28

-- 入场动画
local ENTER_ANIM_DURATION  = 0.30
local ENTER_ANIM_DISTANCE  = 100
local ENTER_STAGGER        = 0.06

-- 远程角色缩放攻击动画
local RANGED_CHARGE_SCALE  = 0.85
local RANGED_LUNGE_SCALE   = 1.15

M.DEATH_ANIM_DURATION  = DEATH_ANIM_DURATION
M.REVIVE_ANIM_DURATION = REVIVE_ANIM_DURATION
M.REVIVE_ANIM_DISTANCE = REVIVE_ANIM_DISTANCE
M.TOMBSTONE_FADEIN     = TOMBSTONE_FADEIN
M.CHARGE_START         = CHARGE_START
M.CHARGE_DISTANCE      = CHARGE_DISTANCE
M.LUNGE_DURATION       = LUNGE_DURATION
M.RETURN_DURATION      = RETURN_DURATION

--- 可随「特效显示」开关屏蔽的战斗卡牌动画（攻击前摇/后摇、受击后退）
local COMBAT_CARD_ANIM_STATES = {
    lunge = true,
    ["return"] = true,
    recoil = true,
    recoil_return = true,
}

local function isCombatCardAnimEnabled()
    return SettingsPanel.isEffectsEnabled()
end

local function isCombatCardAnimState(state)
    return state ~= nil and COMBAT_CARD_ANIM_STATES[state] == true
end

--- 判断是否远程/治疗单位
--- 英雄：按投射物配置判断；怪物：按 isRanged 标志判断
local function isRangedUnit(unit)
    if unit.heroId and PS.hasProjectile(unit.heroId) then
        return true
    end
    if unit.monsterId then
        return unit.isRanged == true
    end
    return false
end

function M.playAttack(BCS, attacker, isAlly)
    if not isCombatCardAnimEnabled() then return end
    BCS.cardAnims[attacker] = {
        state    = "lunge",
        timer    = 0,
        isAlly   = isAlly,
        lungeDir = isAlly and -1 or 1,
        isRanged = isRangedUnit(attacker),
    }
end

function M.setRecoil(BCS, target, lungeDir)
    if not isCombatCardAnimEnabled() then return end
    -- 已死亡的单位不设置 recoil，防止覆盖死亡动画
    if target.hp <= 0 then return end
    BCS.cardAnims[target] = { state = "recoil", timer = 0, lungeDir = lungeDir }
end

function M.update(BCS, dt)
    local toRemove = {}
    for unit, anim in pairs(BCS.cardAnims) do
        if not isCombatCardAnimEnabled() and isCombatCardAnimState(anim.state) then
            toRemove[#toRemove + 1] = unit
            goto continue
        end
        -- delay 处理（入场交错延迟）
        if anim.delay and anim.delay > 0 then
            anim.delay = anim.delay - dt
            if anim.delay > 0 then
                goto continue
            end
            -- delay 刚结束，把超出的时间加到 timer
            anim.timer = anim.timer + (-anim.delay)
            anim.delay = 0
            goto skip_timer
        end
        anim.timer = anim.timer + dt
        ::skip_timer::
        if anim.state == "entering" then
            if anim.timer >= ENTER_ANIM_DURATION then
                toRemove[#toRemove + 1] = unit
            end
        elseif anim.state == "lunge" then
            if anim.timer >= LUNGE_DURATION then
                anim.state = "return"
                anim.timer = 0
            end
        elseif anim.state == "return" then
            if anim.timer >= RETURN_DURATION then
                toRemove[#toRemove + 1] = unit
            end
        elseif anim.state == "recoil" then
            if anim.timer >= RECOIL_DURATION then
                anim.state = "recoil_return"
                anim.timer = 0
            end
        elseif anim.state == "recoil_return" then
            if anim.timer >= RECOIL_RETURN then
                toRemove[#toRemove + 1] = unit
            end
        elseif anim.state == "dying" then
            if anim.timer >= DEATH_ANIM_DURATION then
                anim.state = "gone"   -- 退场完成 → 空位期（已删除墓碑）
                anim.timer = 0
            end
        elseif anim.state == "gone" then
            -- 空位期：停留至被替换（不渲染，无过渡）
        elseif anim.state == "tombstone_in" or anim.state == "dead_done" then
            -- 兼容旧存档/中途状态：视为空位
            anim.state = "gone"
        elseif anim.state == "reviving" then
            if anim.timer >= REVIVE_ANIM_DURATION then
                toRemove[#toRemove + 1] = unit
            end
        elseif anim.state == "advance" then
            if anim.timer >= ADVANCE_DURATION then
                toRemove[#toRemove + 1] = unit
            end
        end
        ::continue::
    end
    for _, unit in ipairs(toRemove) do
        BCS.cardAnims[unit] = nil
    end
end

function M.getOffsetY(BCS, unit)
    local anim = BCS.cardAnims[unit]
    if anim and not isCombatCardAnimEnabled() and isCombatCardAnimState(anim.state) then
        return 0
    end
    if not anim then return 0 end

    if anim.state == "lunge" then
        if anim.isRanged then return 0 end
        local t = math.min(1, anim.timer / LUNGE_DURATION)
        t = 1 - (1 - t) * (1 - t)  -- ease-out
        return anim.lungeDir * LUNGE_DISTANCE * t
    elseif anim.state == "return" then
        if anim.isRanged then return 0 end
        local t = math.min(1, anim.timer / RETURN_DURATION)
        t = t * t  -- ease-in
        return anim.lungeDir * LUNGE_DISTANCE * (1 - t)
    elseif anim.state == "recoil" then
        local t = math.min(1, anim.timer / RECOIL_DURATION)
        t = 1 - (1 - t) * (1 - t)
        return anim.lungeDir * RECOIL_DISTANCE * t
    elseif anim.state == "recoil_return" then
        local t = math.min(1, anim.timer / RECOIL_RETURN)
        t = 1 - (1 - t) * (1 - t)
        return anim.lungeDir * RECOIL_DISTANCE * (1 - t)
    elseif anim.state == "dying" then
        local elapsed = anim.timer
        local mult = anim.knockbackMult or 1.0
        local dist = DEATH_ANIM_DISTANCE * mult
        if elapsed < DEATH_HITSTOP then
            return 0
        elseif elapsed < DEATH_HITSTOP + DEATH_BURST_DUR then
            local t = (elapsed - DEATH_HITSTOP) / DEATH_BURST_DUR
            t = 1 - (1 - t) * (1 - t) * (1 - t)
            return anim.lungeDir * dist * DEATH_OVERSHOOT * t
        else
            local t = math.min(1, (elapsed - DEATH_HITSTOP - DEATH_BURST_DUR) / DEATH_SETTLE_DUR)
            t = 1 - (1 - t) * (1 - t)
            local ratio = DEATH_OVERSHOOT + (1.0 - DEATH_OVERSHOOT) * t
            return anim.lungeDir * dist * ratio
        end
    elseif anim.state == "reviving" then
        local t = math.min(1, anim.timer / REVIVE_ANIM_DURATION)
        t = 1 - (1 - t) * (1 - t)
        return anim.lungeDir * REVIVE_ANIM_DISTANCE * (1 - t)
    elseif anim.state == "entering" then
        if anim.delay and anim.delay > 0 then
            return anim.lungeDir * ENTER_ANIM_DISTANCE
        end
        local t = math.min(1, anim.timer / ENTER_ANIM_DURATION)
        t = 1 - (1 - t) * (1 - t)
        return anim.lungeDir * ENTER_ANIM_DISTANCE * (1 - t)
    elseif anim.state == "advance" then
        if BattleLayout.MODE ~= "strip" then return 0 end
        local dist = anim.advanceDist or 0
        if dist <= 0 then return 0 end
        local t = math.min(1, anim.timer / ADVANCE_DURATION)
        t = 1 - (1 - t) * (1 - t)
        return anim.lungeDir * dist * (1 - t)
    end
    return 0
end

--- 纵向弧线抖动（屏幕 Y 轴，向上为负）
--- 攻击冲刺/回位、受击后退走抛物线弧，蓄力前摇轻微上浮
function M.getArcOffsetY(BCS, unit, isAllyGroup)
    local anim = BCS.cardAnims[unit]
    if anim and not isCombatCardAnimEnabled() and isCombatCardAnimState(anim.state) then
        return 0
    end
    if anim then
        if anim.state == "lunge" and not anim.isRanged then
            local t = math.min(1, anim.timer / LUNGE_DURATION)
            return -LUNGE_ARC_HEIGHT * math.sin(t * math.pi)
        elseif anim.state == "return" and not anim.isRanged then
            local t = math.min(1, anim.timer / RETURN_DURATION)
            return -LUNGE_ARC_HEIGHT * math.sin(t * math.pi)
        elseif anim.state == "recoil" then
            local t = math.min(1, anim.timer / RECOIL_DURATION)
            return -RECOIL_ARC_HEIGHT * math.sin(t * math.pi)
        elseif anim.state == "recoil_return" then
            local t = math.min(1, anim.timer / RECOIL_RETURN)
            return -RECOIL_ARC_HEIGHT * math.sin(t * math.pi)
        end
        return 0
    end
    if not isCombatCardAnimEnabled() then return 0 end
    if unit.hp <= 0 or isRangedUnit(unit) then return 0 end
    local p = unit.atkProgress or 0
    if p < CHARGE_START then return 0 end
    local t = (p - CHARGE_START) / (1.0 - CHARGE_START)
    return -CHARGE_ARC_HEIGHT * t * t
end

function M.getTransitionAlpha(BCS, unit)
    local anim = BCS.cardAnims[unit]
    if not anim then return 1.0 end
    if anim.state == "dying" then
        if anim.timer < DEATH_HITSTOP then
            return 1.0
        end
        local fadeT = math.min(1, (anim.timer - DEATH_HITSTOP) / (DEATH_ANIM_DURATION - DEATH_HITSTOP))
        return 1.0 - fadeT
    elseif anim.state == "gone" or anim.state == "tombstone_in" or anim.state == "dead_done" then
        return 0
    elseif anim.state == "reviving" then
        return math.min(1, anim.timer / REVIVE_ANIM_DURATION)
    elseif anim.state == "entering" then
        if anim.delay and anim.delay > 0 then
            return 0
        end
        return math.min(1, anim.timer / ENTER_ANIM_DURATION)
    end
    return 1.0
end

function M.getChargeOffsetY(BCS, unit, isAllyGroup)
    if not isCombatCardAnimEnabled() then return 0 end
    if unit.hp <= 0 then return 0 end
    if BCS.cardAnims[unit] then return 0 end
    if isRangedUnit(unit) then return 0 end
    local p = unit.atkProgress or 0
    if p < CHARGE_START then return 0 end
    local t = (p - CHARGE_START) / (1.0 - CHARGE_START)
    local dir = isAllyGroup and 1 or -1
    return dir * CHARGE_DISTANCE * t
end

function M.getCardScale(BCS, unit, _isAllyGroup)
    if not isCombatCardAnimEnabled() then return 1.0 end
    if not isRangedUnit(unit) then return 1.0 end
    if unit.hp <= 0 then return 1.0 end

    local anim = BCS.cardAnims[unit]
    if anim then
        if anim.state == "lunge" and anim.isRanged then
            local t = math.min(1, anim.timer / LUNGE_DURATION)
            t = 1 - (1 - t) * (1 - t)
            return RANGED_CHARGE_SCALE + (RANGED_LUNGE_SCALE - RANGED_CHARGE_SCALE) * t
        elseif anim.state == "return" and anim.isRanged then
            local t = math.min(1, anim.timer / RETURN_DURATION)
            t = t * t
            return RANGED_LUNGE_SCALE + (1.0 - RANGED_LUNGE_SCALE) * t
        end
        return 1.0
    end

    local p = unit.atkProgress or 0
    if p < CHARGE_START then return 1.0 end
    local t = (p - CHARGE_START) / (1.0 - CHARGE_START)
    return 1.0 + (RANGED_CHARGE_SCALE - 1.0) * t
end

function M.getState(BCS, unit)
    local anim = BCS.cardAnims[unit]
    return anim and anim.state or nil
end

function M.set(BCS, unit, animData)
    BCS.cardAnims[unit] = animData
end

function M.clear(BCS, unit)
    BCS.cardAnims[unit] = nil
end

function M.playEnter(BCS, units, lungeDir)
    for i, unit in ipairs(units) do
        BCS.cardAnims[unit] = {
            state    = "entering",
            timer    = 0,
            lungeDir = lungeDir,
            delay    = (i - 1) * ENTER_STAGGER,
        }
    end
end

return M
