-- ============================================================================
-- TerminalRaid - 终焉神殿三队协同战（共享生命池）
-- 三支小队各面对一个独立攻击的终焉 Boss，三 Boss 共用一个生命池：
--   任一路造成伤害 → 池扣血 → sync 回写三路 Boss 的显示 HP
-- 胜利条件：池被打空（任一队达成即全队胜利）
-- 失败条件：三队全部失守，或超过 GameConfig.Battle.TIME_LIMIT_SEC
-- 单队失守不退关：该队停摆（defeated[row]=true），其余队继续作战
-- ============================================================================
local AD = require("systems.AttributeDef")

local TerminalRaid = {}

function TerminalRaid.new(stageId, drivers)
    local raid = { stageId = stageId, hp = 0, maxHp = 0, enemies = {}, elapsed = 0, lines = {} }
    for row = 1, 3 do
        local drv = drivers[row]
        if drv and drv.stageId == stageId and #drv.allies > 0 then
            local enemy = drv.enemies[1]
            if enemy and enemy.attrs then
                raid.enemies[#raid.enemies + 1] = enemy
                raid.lines[row] = enemy   -- 行归属：胜利时按队结算 Boss 击杀奖励
                raid.maxHp = raid.maxHp + enemy.hp
            end
        end
    end
    raid.hp = raid.maxHp
    raid.defeated = {}
    raid.finished = false
    raid.originalDamage = {}

    function raid:onTeamDefeated(teamIdx)
        if self.defeated[teamIdx] or self.finished then return end
        self.defeated[teamIdx] = true
        print(string.format("[TerminalRaid] 小队%d 失守，其他小队继续作战", teamIdx))
        local fighting = false
        for row = 1, 3 do
            local drv = drivers[row]
            if drv and drv.terminalRaid == self and not self.defeated[row] then
                for _, ally in ipairs(drv.allies) do
                    if ally.hp > 0 then fighting = true break end
                end
            end
        end
        if not fighting then self:finish(false) end
    end

    function raid:finish(won)
        if self.finished then return end
        self.finished = true
        self.won = won
        print(string.format("[TerminalRaid] %s stage=%d", won and "胜利" or "失败", self.stageId))
    end

    function raid:release()
        for enemy, original in pairs(self.originalDamage) do
            enemy.attrs.takeDamage = original.takeDamage
            enemy.attrs.heal = original.heal
        end
    end

    function raid:sync()
        for _, enemy in ipairs(self.enemies) do
            enemy.hp = self.hp
            enemy.maxHp = self.maxHp
            enemy.attrs.final[AD.HP] = self.hp
            enemy.attrs.final[AD.MAX_HP] = self.maxHp
        end
    end

    for _, enemy in ipairs(raid.enemies) do
        local attrs = enemy.attrs
        local takeDamage = attrs.takeDamage
        local heal = attrs.heal
        raid.originalDamage[enemy] = { takeDamage = takeDamage, heal = heal }
        attrs.takeDamage = function(self, amount, resistance)
            if raid.hp <= 0 then return 0 end
            local before = raid.hp
            raid:sync()
            local actual = takeDamage(self, amount, resistance)
            raid.hp = math.max(0, before - actual)
            raid:sync()
            return actual
        end
        attrs.heal = function(self, amount)
            if raid.hp <= 0 then return 0 end
            raid:sync()
            local actual = heal(self, amount)
            raid.hp = math.min(raid.maxHp, raid.hp + actual)
            raid:sync()
            return actual
        end
    end
    raid:sync()
    print(string.format("[TerminalRaid] 三队协同开始 stage=%d 敌方战线=%d 共享生命=%.0f",
        stageId, #raid.enemies, raid.maxHp))
    return raid
end

return TerminalRaid
