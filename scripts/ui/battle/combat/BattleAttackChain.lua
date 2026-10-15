-- 多目标主攻击的串行弹射；复用各目标已计算的伤害包与宿主弹体。
local M = {}

function M.start(pack, attacker, startX, startY, deps)
    local nextIndex = 1
    local fromX, fromY = startX, startY
    local function fireNext()
        if not deps.isCurrent() then return end
        local event = pack.events[nextIndex]
        while event do
            local target, x, y = deps.resolve(event.target)
            if target and not pack.hitTargets[target] then
                local landed = false
                deps.emit(attacker, target, fromX, fromY, x, y, event.result, function()
                    if landed or not deps.isCurrent() then return end
                    landed = true
                    event.applyHit(target)
                    if not deps.isCurrent() then return end
                    -- 飞行中死亡/离场的目标不命中，保留本段从上一命中点重新发射。
                    if event.result.projectileHitTarget then
                        fromX, fromY = event.result.projectileHitX, event.result.projectileHitY
                        nextIndex = nextIndex + 1
                    end
                    fireNext()
                end)
                return
            end
            nextIndex = nextIndex + 1
            event = pack.events[nextIndex]
        end
    end
    fireNext()
end

return M
