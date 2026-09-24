-- ============================================================================
-- BattleSpeed - 首通战斗倍速按钮与逻辑 dt
-- 从 BattleScene 抽出；对外 API 仍由 BattleScene 包装（BattleTriPage 依赖）
-- ============================================================================

local BattleDraw = require("ui.battle.scene.BattleDraw")
local SC = require("config.StageConfig")

local M = {}

local SPEED_CX, SPEED_CY = 987, 311
local SPEED_W, SPEED_H = 130, 143

--- 按当前难度返回已解锁的最高倍速
---@param difficulty string|nil
---@return number
function M.getMaxUnlocked(difficulty)
    if difficulty == SC.DIFFICULTY_HELL or difficulty == SC.DIFFICULTY_NIGHTMARE
        or difficulty == SC.DIFFICULTY_PURGATORY or difficulty == SC.DIFFICULTY_TORMENT
        or difficulty == SC.DIFFICULTY_TORMENT2 or difficulty == SC.DIFFICULTY_TORMENT3
        or difficulty == SC.DIFFICULTY_TORMENT4 or difficulty == SC.DIFFICULTY_TORMENT5
        or difficulty == SC.DIFFICULTY_ANNIHILATION or difficulty == SC.DIFFICULTY_ANNIHILATION2
        or difficulty == SC.DIFFICULTY_ANNIHILATION3 or difficulty == SC.DIFFICULTY_ANNIHILATION4
        or difficulty == SC.DIFFICULTY_ANNIHILATION5 then
        return 2.0
    elseif difficulty == SC.DIFFICULTY_HARD then
        return 1.5
    end
    return 1.0
end

---@param speed number
---@return string
function M.getSpeedText(speed)
    if speed == 1.5 then
        return "X1.5"
    elseif speed >= 2.0 then
        return "X2"
    end
    return "X1"
end

--- 在 1.0 → 1.5 → 2.0 → 1.0 间循环（受 maxSpeed 限制）
---@param speed number
---@param maxSpeed number
---@return number
function M.cycle(speed, maxSpeed)
    if speed < 1.5 and maxSpeed >= 1.5 then
        return 1.5
    elseif speed < 2.0 and maxSpeed >= 2.0 then
        return 2.0
    end
    return 1.0
end

---@param dt number
---@param speed number
---@param maxSpeed number
---@param visible boolean
---@return number logicDt, number clampedSpeed
function M.getLogicDt(dt, speed, maxSpeed, visible)
    local s = speed
    if s > maxSpeed then
        s = maxSpeed
    end
    if visible then
        return dt * s, s
    end
    return dt, s
end

---@param dx number
---@param dy number
---@return boolean
function M.hitTest(dx, dy)
    return math.abs(dx - SPEED_CX) <= (SPEED_W * 0.5) and math.abs(dy - SPEED_CY) <= (SPEED_H * 0.5)
end

---@param vg userdata
---@param img number
---@param speed number
---@param visible boolean
function M.draw(vg, img, speed, visible)
    if not visible then return end
    local alpha = speed > 1.0 and 1.0 or 0.82
    BattleDraw.drawImageCentered(vg, img, SPEED_CX, SPEED_CY, SPEED_W, SPEED_H, alpha)
    BattleDraw.drawTextStroke(vg, SPEED_CX, 305,
        M.getSpeedText(speed), 52,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 6,
        { strokeColor = { 0x36, 0x77, 0x78 } })
end

return M
