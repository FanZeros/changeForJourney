-- ============================================================================
-- BattleSpeed - 已移除战斗倍速的旧接口兼容层
-- 不读取难度或账户进度，不绘制按钮，不拦截点击；战斗始终使用真实 dt。
-- ============================================================================

local M = {}

---@param difficulty string|nil
---@return number
function M.getMaxUnlocked(difficulty)
    return 1
end

---@param battle table|nil
---@param memoryMaxStageId number|nil
---@param memoryCleared table|nil
---@return number
function M.getAccountMaxUnlocked(battle, memoryMaxStageId, memoryCleared)
    return 1
end

---@param speed number
---@return string
function M.getSpeedText(speed)
    return "X1"
end

---@param speed number
---@param maxSpeed number
---@return number
function M.cycle(speed, maxSpeed)
    return 1
end

---@param dt number
---@param speed number
---@param maxSpeed number
---@param visible boolean
---@return number logicDt, number clampedSpeed
function M.getLogicDt(dt, speed, maxSpeed, visible)
    return dt, 1
end

---@param dx number
---@param dy number
---@return boolean
function M.hitTest(dx, dy)
    return false
end

---@param vg any
---@param img number
---@param speed number
---@param visible boolean
---@return boolean
function M.draw(vg, img, speed, visible)
    return false
end

return M
