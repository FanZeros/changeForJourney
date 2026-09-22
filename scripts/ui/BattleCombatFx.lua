-- ============================================================================
-- BattleCombatFx - 飘字对象池 / 伤害排队 / 受击闪烁
-- 从 BattleCombat 抽出；状态仍写在调用方传入的 BCS 上
-- ============================================================================

local SettingsPanel = require("ui.SettingsPanel")

local M = {}

local FLOAT_TOTAL_FRAMES = 20
local FLOAT_FPS          = 30
local FLOAT_DURATION     = FLOAT_TOTAL_FRAMES / FLOAT_FPS
local MAX_FLOATING_TEXTS = 15
local FLOAT_FAST_FADE    = 17 / FLOAT_FPS
local HIT_FLASH_DURATION = 0.3

M.FLOAT_DURATION = FLOAT_DURATION
M.FLOAT_MOVE_DIST = 240
M.HIT_FLASH_DURATION = HIT_FLASH_DURATION

local function acquireFt(BCS)
    local n = #BCS.ftPool
    if n > 0 then
        local ft = BCS.ftPool[n]
        BCS.ftPool[n] = nil
        return ft
    end
    return {}
end

local function releaseFt(BCS, ft)
    ft.text = nil
    ft.color = nil
    BCS.ftPool[#BCS.ftPool + 1] = ft
end

function M.addFloatingText(BCS, text, cx, cy, color, isCrit, fontSize, deferred)
    if deferred then
        if #BCS.pendingFt >= 20 then
            table.remove(BCS.pendingFt, 1)
        end
        BCS.pendingFt[#BCS.pendingFt + 1] = {
            text = text, cx = cx, cy = cy,
            color = color, isCrit = isCrit or false, fontSize = fontSize,
        }
        if #BCS.pendingFt == 1 then
            BCS.ftSpawnCd = 0
        end
        return
    end
    while #BCS.floatingTexts >= MAX_FLOATING_TEXTS do
        local oldest = BCS.floatingTexts[1]
        if oldest.timer < FLOAT_FAST_FADE then
            oldest.timer = FLOAT_FAST_FADE
        else
            releaseFt(BCS, oldest)
            table.remove(BCS.floatingTexts, 1)
        end
        break
    end

    local angle = -math.pi * 0.5 + (math.random() - 0.5) * math.pi * 0.5
    local baseSize = fontSize or 80
    if isCrit then baseSize = baseSize * 2 end
    local entry = acquireFt(BCS)
    entry.text     = text
    entry.x        = cx
    entry.y        = cy
    entry.dirX     = math.cos(angle)
    entry.dirY     = math.sin(angle)
    entry.timer    = 0
    entry.duration = FLOAT_DURATION
    entry.color    = color
    entry.isCrit   = isCrit or false
    entry.fontSize = baseSize
    BCS.floatingTexts[#BCS.floatingTexts + 1] = entry
end

function M.updateFloatingTexts(BCS, dt, spawnFn)
    if #BCS.pendingFt > 0 then
        BCS.ftSpawnCd = BCS.ftSpawnCd - dt
        if BCS.ftSpawnCd <= 0 then
            local p = table.remove(BCS.pendingFt, 1)
            spawnFn(p.text, p.cx, p.cy, p.color, p.isCrit, p.fontSize, false)
            BCS.ftSpawnCd = 0.1
        end
    end
    local i = 1
    while i <= #BCS.floatingTexts do
        local ft = BCS.floatingTexts[i]
        ft.timer = ft.timer + dt
        if ft.timer >= ft.duration then
            releaseFt(BCS, ft)
            table.remove(BCS.floatingTexts, i)
        else
            i = i + 1
        end
    end
end

function M.setHitFlash(BCS, target)
    if not SettingsPanel.isEffectsEnabled() then return end
    BCS.hitFlashes[target] = { timer = 0 }
end

function M.updateHitFlashes(BCS, dt)
    local toRemove = {}
    for unit, flash in pairs(BCS.hitFlashes) do
        flash.timer = flash.timer + dt
        if flash.timer >= HIT_FLASH_DURATION then
            toRemove[#toRemove + 1] = unit
        end
    end
    for _, unit in ipairs(toRemove) do
        BCS.hitFlashes[unit] = nil
    end
end

function M.getHitFlashAlpha(BCS, unit)
    if not SettingsPanel.isEffectsEnabled() then return 0 end
    local flash = BCS.hitFlashes[unit]
    if not flash then return 0 end
    local t = flash.timer / HIT_FLASH_DURATION
    local alpha = (1 - t) * 180
    if t < 0.3 then
        alpha = 200
    end
    return math.max(0, math.floor(alpha))
end

function M.clearHitFlash(BCS, unit)
    BCS.hitFlashes[unit] = nil
end

return M
