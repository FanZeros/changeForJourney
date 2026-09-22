-- ============================================================================
-- Talent Sera helpers extracted from TalentManager
-- Bound via M.bind(deps); original local function names preserved.
-- ============================================================================

local ETS = require("systems.ExtraTalentSystem")

local M = {}

function M.bind(deps)
    local hasAwaken = deps.hasAwaken
    local talentLog = deps.talentLog
    local AD = deps.AD

--- 小黑子「法术机关枪」：推进攻击计数（普攻与连击共用；连射弹在 onBeforeAttack 中排除）
---@param attacker table
---@param s table
local function tickSeraMachineGunCount(attacker, s)
    if not attacker.attrs then return end
    s.machineGunNormalCount = (s.machineGunNormalCount or 0) + 1
    local interval = 20
    if hasAwaken(attacker, 1) then interval = 18 end
    if hasAwaken(attacker, 5) then interval = 15 end
    interval = math.max(8, interval - ETS.getGatlingCut(attacker))
    if s.machineGunNormalCount % interval == 0 then
        s.machineGunShotsLeft = hasAwaken(attacker, 3) and 12 or 10
        s.machineGunShotTimer = 0
        s.machineGunInBurst = true
        if hasAwaken(attacker, 4) then
            attacker.attrs:addModifier("sera_burst_pen", {
                { key = AD.MAG_PEN, flat = 9999 },
            })
        end
        if hasAwaken(attacker, 6) then
            attacker.attrs:addModifier("sera_burst_speed", {
                { key = AD.ATK_SPEED, flat = 50 },
            })
        end
        talentLog(string.format("[Talent] 小黑子 法术机关枪：第%d次攻击启动连射×%d",
            s.machineGunNormalCount, s.machineGunShotsLeft))
    end
end

    return {
        tickSeraMachineGunCount = tickSeraMachineGunCount,
    }
end

return M
