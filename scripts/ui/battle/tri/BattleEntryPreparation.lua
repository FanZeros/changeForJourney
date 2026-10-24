-- 入场资源的运行时凭据：只对应真实驱动/编队/关卡，不进入存档或攻击时序。
local Draw = require("ui.battle.scene.BattleDraw")
local Scope = require("ui.battle.scene.BattleMountScope")
local M = {}

function M.new()
    local snapshot = nil ---@type table|nil
    local generation = {}
    local entry = {}

    function entry.invalidate()
        snapshot = nil
        generation = {}
    end

    function entry.isPrepared(ready, drivers, unlocked, getSignature)
        if not ready or not snapshot or snapshot.unlocked ~= unlocked then return false end
        for row = 1, unlocked do
            local cached, drv = snapshot[row], drivers[row]
            if not cached or not drv or cached.driver ~= drv or cached.stageId ~= drv.stageId
                or cached.signature ~= drv.teamSignature
                or drv.teamSignature ~= getSignature(row) then return false end
        end
        return true
    end

    function entry.prepare(vg, drivers, unlocked, getSignature, rebuild)
        if rebuild then
            -- start不yield；先恢复调用方挂载，再进入跨帧图片预热。
            Scope.run(function()
                for row = 1, unlocked do
                    local drv = drivers[row]
                    if drv and drv.teamSignature ~= getSignature(row) then
                        drv:start(drv.stageId)
                    end
                end
            end)
        end
        local token = generation
        local candidate = { unlocked = unlocked }
        -- 先冻结全部队伍身份，再进入可yield的加载，不能把中途新队误作已预热。
        for row = 1, unlocked do
            local drv = drivers[row]
            if drv then
                candidate[row] = { driver = drv, stageId = drv.stageId, signature = drv.teamSignature }
            end
        end
        for row = 1, unlocked do
            local cached = candidate[row]
            if cached then
                local drv = cached.driver
                Draw.preloadCards(vg, drv.allies)
                Draw.preloadCards(vg, drv.enemies)
                Draw.preloadCards(vg, drv.enemyQueue)
            end
            if generation ~= token then return false end
        end
        snapshot = candidate
        if not entry.isPrepared(true, drivers, unlocked, getSignature) then
            snapshot = nil
            return false
        end
        return true
    end

    return entry
end

return M
