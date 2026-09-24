-- ============================================================================
-- CERuntime - 战斗侧测试开关（无敌 / 三倍速）
-- 只影响本机当场战斗，不写存档。
-- ============================================================================

local CERuntime = {}

local godMode_ = false
local speedOn_ = false
local speedHooked_ = false
local damageHooked_ = false

function CERuntime.isGodMode()
    return godMode_
end

function CERuntime.isSpeedOn()
    return speedOn_
end

function CERuntime.setGodMode(on)
    godMode_ = on == true
    print("[CE] godMode=" .. tostring(godMode_))
end

function CERuntime.toggleGodMode()
    CERuntime.setGodMode(not godMode_)
    return godMode_
end

function CERuntime.setSpeedOn(on)
    speedOn_ = on == true
    print("[CE] speed3x=" .. tostring(speedOn_))
    CERuntime.installSpeedHook()
end

function CERuntime.toggleSpeed()
    CERuntime.setSpeedOn(not speedOn_)
    return speedOn_
end

function CERuntime.installSpeedHook()
    if speedHooked_ then return end
    local ok, BattleScene = pcall(require, "ui.BattleScene")
    if not ok or not BattleScene or not BattleScene.getBattleLogicDt then
        print("[CE] speed hook skipped, BattleScene not ready")
        return
    end
    speedHooked_ = true
    local raw = BattleScene.getBattleLogicDt
    function BattleScene.getBattleLogicDt(dt)
        if speedOn_ then
            BattleScene.battleSpeed = 3
            return dt * 3
        end
        return raw(dt)
    end
    print("[CE] speed hook installed")
end

function CERuntime.installDamageHook()
    if damageHooked_ then return end
    local ok, UA = pcall(require, "systems.UnitAttributes")
    if not ok or not UA or not UA.takeDamage then
        print("[CE] damage hook skipped")
        return
    end
    damageHooked_ = true
    local raw = UA.takeDamage
    function UA:takeDamage(amount)
        if self._ceGod then return 0 end
        return raw(self, amount)
    end
    print("[CE] damage hook installed")
end

--- 无敌：给己方属性打标，并在每帧拉满，避免漏掉直接改 hp 的路径
function CERuntime.tick()
    CERuntime.installDamageHook()
    local ok, BattleScene = pcall(require, "ui.BattleScene")
    if not ok or not BattleScene or not BattleScene.getAllies then return end
    local allies = BattleScene.getAllies()
    if not allies then return end
    local AD = require("systems.AttributeDef")
    for _, ally in ipairs(allies) do
        if ally.attrs then
            ally.attrs._ceGod = godMode_
            if godMode_ and ally.attrs.fillHp then
                ally.attrs:fillHp()
                local maxHp = ally.attrs:get(AD.MAX_HP)
                ally.hp = maxHp
                ally.maxHp = maxHp
            end
        elseif godMode_ and ally.maxHp then
            ally.hp = ally.maxHp
        end
    end
end

return CERuntime
