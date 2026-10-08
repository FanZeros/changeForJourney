-- ============================================================================
-- CERuntime - 战斗侧无敌测试开关
-- 只影响本机当场战斗，不写存档。
-- ============================================================================

local CERuntime = {}

local godMode_ = false
local damageHooked_ = false

function CERuntime.isGodMode()
    return godMode_
end

function CERuntime.isSpeedOn()
    return false
end

function CERuntime.setGodMode(on)
    godMode_ = on == true
    print("[CE] godMode=" .. tostring(godMode_))
end

function CERuntime.toggleGodMode()
    CERuntime.setGodMode(not godMode_)
    return godMode_
end

-- 旧测试入口仅保留无操作兼容，不能安装包装器或改写任何战斗时钟。
function CERuntime.setSpeedOn(on)
    return false
end

function CERuntime.toggleSpeed()
    return false
end

function CERuntime.installSpeedHook()
    return false
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
    local ok, BattleScene = pcall(require, "ui.battle.scene.BattleScene")
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
