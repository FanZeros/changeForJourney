-- ============================================================================
-- TerminalRaid - 终焉神殿三队协同战（同编号共享生命）
-- 每队面对全部三名 Boss；只有同编号 Boss 共用生命，攻击/护盾/状态各线独立。
--   队1/2/3 的敌人1 → 生命池1；敌人2 → 生命池2；敌人3 → 生命池3
-- 任一生命池归零，该编号的三路 Boss 同时死亡；全部生命池归零才胜利。
-- 单队失守后停止攻击，但退场视觉仍由驱动推进；全灭收尾不冻结死亡动画。
-- ============================================================================
local AD = require("systems.AttributeDef")

local TerminalRaid = {}
TerminalRaid.FAILURE_HOLD_SEC = 1.0

function TerminalRaid.new(stageId, drivers)
    local raid = {
        stageId = stageId, hp = 0, maxHp = 0, enemies = {}, pools = {}, lines = {},
        elapsed = 0, defeated = {}, finished = false, finishElapsed = 0, originalDamage = {},
    }
    for row = 1, 3 do
        local drv = drivers[row]
        if drv and drv.stageId == stageId then
            raid.lines[row] = {}
            if #drv.allies == 0 then raid.defeated[row] = true end
            for index, enemy in ipairs(drv.enemies) do
                if enemy.attrs then
                    local pool = raid.pools[index]
                    if not pool then
                        pool = { hp = enemy.hp, maxHp = enemy.maxHp, enemies = {} }
                        raid.pools[index] = pool
                    end
                    pool.enemies[#pool.enemies + 1] = enemy
                    raid.enemies[#raid.enemies + 1] = enemy
                    raid.lines[row][index] = enemy
                end
            end
        end
    end

    function raid:onTeamDefeated(teamIdx)
        if self.defeated[teamIdx] or self.finished then return end
        self.defeated[teamIdx] = true
        print(string.format("[TerminalRaid] 小队%d 失守，停止战斗并完成退场", teamIdx))
        local fighting = false
        for row = 1, 3 do
            local drv = drivers[row]
            if drv and drv.terminalRaid == self and not self.defeated[row] then
                -- 后更新的战线必须先获得神器/天赋瞬时复活机会，再确认全灭。
                fighting = true
                break
            end
        end
        if not fighting then self:finish(false) end
    end

    function raid:finish(won)
        if self.finished then return end
        self.finished = true
        self.won = won
        self.finishElapsed = 0
        print(string.format("[TerminalRaid] %s stage=%d", won and "胜利" or "失败待退场", self.stageId))
    end

    function raid:release()
        for enemy, original in pairs(self.originalDamage) do
            enemy.attrs.takeDamage = original.takeDamage
            enemy.attrs.heal = original.heal
        end
    end

    function raid:sync()
        local hp, maxHp = 0, 0
        for _, pool in ipairs(self.pools) do
            hp = hp + pool.hp
            maxHp = maxHp + pool.maxHp
            for _, enemy in ipairs(pool.enemies) do
                enemy.hp = pool.hp
                enemy.maxHp = pool.maxHp
                enemy.attrs.final[AD.HP] = pool.hp
                enemy.attrs.final[AD.MAX_HP] = pool.maxHp
            end
        end
        -- 汇总仅供进度条/胜负判定；不能作为任何单只 Boss 的生命上限。
        self.hp, self.maxHp = hp, maxHp
    end

    for _, pool in ipairs(raid.pools) do
        for _, enemy in ipairs(pool.enemies) do
            local attrs = enemy.attrs
            local takeDamage = attrs.takeDamage
            local heal = attrs.heal
            raid.originalDamage[enemy] = { takeDamage = takeDamage, heal = heal }
            attrs.takeDamage = function(self, amount, resistance)
                if pool.hp <= 0 or raid.finished then return 0 end
                raid:sync()
                local actual = takeDamage(self, amount, resistance)
                pool.hp = math.max(0, pool.hp - actual)
                raid:sync()
                return actual
            end
            attrs.heal = function(self, amount)
                if pool.hp <= 0 or raid.finished then return 0 end
                raid:sync()
                local actual = heal(self, amount)
                pool.hp = math.min(pool.maxHp, pool.hp + actual)
                raid:sync()
                return actual
            end
        end
    end
    raid:sync()
    if raid.maxHp <= 0 or (raid.defeated[1] and raid.defeated[2] and raid.defeated[3]) then
        raid:finish(false)
    end
    print(string.format("[TerminalRaid] 协同开始 stage=%d 生命池=%d 敌人实例=%d 总生命=%.0f",
        stageId, #raid.pools, #raid.enemies, raid.maxHp))
    return raid
end

return TerminalRaid
