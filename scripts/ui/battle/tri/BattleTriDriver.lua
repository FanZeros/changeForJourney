-- ============================================================================
-- BattleTriDriver - 三栏并行战斗·轻量驱动器（Phase 3）
-- 每栏一支队伍的独立战斗: 出波 → 战斗 tick（mount 作用域内）→ 击杀奖励 → 推进
--
-- 与 BattleScene（栏1 全引擎）的分工:
--   栏1 = BattleScene（完整关卡进度/首通/终焉/掉落等）
--   栏2/3 = 本驱动器的轻量实现: 自动战斗、击杀奖励走 onKill 回调、
--           通关自动推进下一关、己方阵亡 3 秒后原地满血复活（挂机风格）
-- 依赖 Phase 2b 的 mount API: 本驱动 update/draw 前先 mount 自己的状态集。
-- ============================================================================
local BattleCombat      = require("ui.battle.combat.BattleCombat")
local BattleEffects     = require("ui.battle.combat.BattleEffects")
local ProjectileSystem  = require("ui.battle.combat.ProjectileSystem")
local SEM               = require("systems.StatusEffectManager")
local TM                = require("systems.ThreatManager")
local TAL               = require("systems.TalentManager")
local RCH               = require("systems.RelicConditionHandler")
local ART               = require("systems.ArtifactRuntime")
local CF                = require("systems.CombatFormula")
local AD                = require("systems.AttributeDef")
local MC                = require("config.MonsterConfig")
local SC                = require("config.StageConfig")
local NumberUtil        = require("core.NumberUtil")
local BattleLayout      = require("core.BattleLayout")
local BattleStats       = require("systems.BattleStats")
local BattleEnemySpawn  = require("ui.battle.stage.BattleEnemySpawn")

local BattleTriDriver = {}

local DEFAULT_ALLY_INTERVAL  = 1.2
local DEFAULT_ENEMY_INTERVAL = 2.0
local REVIVE_DELAY = 3.0
local RESPAWN_DELAY = 1.0
local REINFORCE_INTERVAL = 0.4
-- 全灭兜底：单单位复活计时失效（缺 attrs 等）时，按这个墙钟整队复活，避免永久卡死
local WIPE_RESET_DELAY = 5.0

--- 单位攻击间隔（魔改 buff 感知的最小实现：直接取 attrs 的实际间隔）
local function getLiveAttackInterval(unit, fallback)
    if unit and unit.attrs and unit.attrs.getActualInterval then
        local v = unit.attrs:getActualInterval()
        if v and v > 0.05 then return v end
    end
    return fallback
end

--- 按关卡配置生成一波敌人（上限 4 = 列阵每侧上限）
---@param stageId number
---@return table[] enemies
---@return number stageLevel
local function buildWave(stageId)
    local entry = SC.getStage and SC.getStage(stageId) or nil
    local list = {}
    local level = entry and (entry.monsterLevel or 1) or 1
    if entry and type(entry.monsters) == "table" then
        local types = entry.monsters
        local count = math.min(#types, BattleLayout.MAX_PER_SIDE)
        for i = 1, count do
            local u = MC.createMonster(types[i], level)
            if u then list[#list + 1] = u end
        end
        if entry.bossId and entry.bossId > 0 and #list < BattleLayout.MAX_PER_SIDE then
            local boss = MC.createMonster(entry.bossId, level)
            if boss then
                boss.isBoss = true
                list[#list + 1] = boss
            end
        end
    end
    -- 兜底: 配置缺失时用基础怪
    if #list == 0 then
        local u = MC.createMonster(1, level)
        if u then list[#list + 1] = u end
    end
    return list, level
end

--- 新建驱动器
---@param teamIdx number 队伍索引（2/3）
---@return table drv
function BattleTriDriver.new(teamIdx)
    ---@class table
    local drv = {
        teamIdx  = teamIdx,
        stageId  = SC.NORMAL_FIRST_STAGE,
        allies   = {},
        enemies  = {},
        enemyQueue = {},
        reinforceCd = 0,
        teamSignature = nil,
        kills    = 0,
        stageTotal = 0,
        active   = false,
        -- [多实例] 各子系统状态
        combatState = BattleCombat.newState("tri" .. teamIdx),
        psState     = ProjectileSystem.newState(),
        tmState     = TM.newState(),
        talRefs     = TAL.newBattleRefs(),
        beState     = BattleEffects.newFxState(),
        semState    = SEM.newSemState(),
        onKill      = nil,  -- function(data) 由 TriPage/宿主注入
        onStageChanged = nil,
    }

    --- mount 本战斗的全部子系统状态
    function drv.mount()
        BattleStats.mount(drv.teamIdx)
        BattleCombat.mount(drv.combatState)
        ProjectileSystem.mount(drv.psState)
        TM.mount(drv.tmState)
        TAL.mount(drv.talRefs)
        BattleEffects.mount(drv.beState)
        SEM.mount(drv.semState)
    end

    --- 注入 BattleCombat ctx（在 mounted 状态上）
    function drv.bindContext()
        BattleCombat.setContext({
            getAllies  = function() return drv.allies end,
            getEnemies = function() return drv.enemies end,
            ALLY_CARD_CY  = BattleLayout.FIELD_CY,
            ENEMY_CARD_CY = BattleLayout.FIELD_CY,
            -- [三战场独立发音] 攻击命中回调：投射物表现 + 音效（与行1 BattleScene 同逻辑；
            -- spawn 落到本行 mount 的 psState，各行互不干扰）
            onAttackHit = function(attacker, target, atkCX, atkCY, tgtCX, tgtCY, result, applyHit)
                local hasHeroEffect = attacker.heroId
                                      and ProjectileSystem.hasHeroEffect(attacker.heroId)
                local hasMonsterEffect = attacker.atkEffect
                                         and ProjectileSystem.hasMonsterProjectile(attacker.atkEffect)

                local hitCallback = function()
                    if applyHit then
                        local ok, err = pcall(applyHit)
                        if not ok then
                            print("[TriDriver] applyHit ERROR: " .. tostring(err))
                        end
                    end
                    if result.category ~= "healing" and target.attrs then
                        local armorType = target.attrs.armorType or 1
                        BattleEffects.spawn(armorType, tgtCX, tgtCY)
                    end
                end

                local projOpts = result.category == "healing" and { target = target, forceBezier = true } or nil

                if hasHeroEffect then
                    ProjectileSystem.spawn(attacker.heroId, atkCX, atkCY, tgtCX, tgtCY, hitCallback, projOpts)
                elseif hasMonsterEffect then
                    local isMelee = (attacker.isRanged ~= true)
                    ProjectileSystem.spawnByKey(attacker.atkEffect, atkCX, atkCY, tgtCX, tgtCY, hitCallback, isMelee, projOpts)
                else
                    hitCallback()
                end
            end,
        })
    end

    --- 复活单个己方单位（缺 attrs 时退回满血兜底，保证一定复活）
    ---@param u table
    function drv:reviveUnit(u)
        u._triReviveTimer = nil
        u.atkProgress = 0
        if u.attrs then
            u.attrs:fillHp()
            u.hp = u.attrs.final[AD.HP]
        else
            -- 无 attrs 的单位无法走属性回血，用记录过的上限兜底
            u.hp = u.maxHp or u.hp or 1
            if u.hp <= 0 then u.hp = 1 end
        end
        local cx, cy = BattleLayout.cardPos("ally", 1)
        BattleCombat.addFloatingText("复活", cx, cy, { 120, 255, 160 }, false)
    end

    --- 挂载本队状态并注入上下文。绘制和更新都必须先调用，避免串用上一队状态。
    function drv:activate()
        self.mount()
        self.bindContext()
    end

    --- 开始/重开一场战斗
    function drv:start(stageId)
        stageId = tonumber(stageId) or self.stageId or SC.NORMAL_FIRST_STAGE
        if not SC.getStage(stageId) then
            stageId = SC.NORMAL_FIRST_STAGE
        end
        self.stageId = stageId
        self.kills = 0
        -- 清理上一轮残留的复活/全灭计时，避免沿用旧进度
        self._wipeTimer = nil
        self:activate()
        -- 己方: 从编队页构建新单位（应用装备/神器/遗物）
        local CharacterPanel = require("ui.character.panel.CharacterPanel")
        self.teamSignature = CharacterPanel.getTeamSignature(self.teamIdx)
        self.allies = CharacterPanel.getDeployedTeam(self.teamIdx) or {}
        -- 敌方
        local entry = SC.getStage(stageId)
        local allEnemies = entry and BattleEnemySpawn.generateEnemyList(entry, false) or {}
        if #allEnemies == 0 then allEnemies = buildWave(stageId) end
        local maxField = (entry and entry.maxFieldEnemies) or BattleLayout.MAX_PER_SIDE
        maxField = math.min(maxField, BattleLayout.MAX_PER_SIDE)
        self.enemies, self.enemyQueue = BattleEnemySpawn.assignEnemiesToField(allEnemies, maxField)
        self.stageTotal = #allEnemies
        self.reinforceCd = 0
        -- 状态复位（mount 作用域内）
        BattleCombat.reset()
        BattleEffects.reset()
        ProjectileSystem.reset()
        TM.reset()
        -- 单位初始化
        for _, u in ipairs(self.allies) do
            u.atkProgress = 0
            TAL.initUnit(u)
        end
        for _, u in ipairs(self.enemies) do
            u.atkProgress = 0
            TAL.initUnit(u)
        end
        RCH.initBattle(self.allies)
        ART.initBattle(self.allies)
        TM.onBattleStart(self.allies, self.enemies)
        TAL.onBattleStart(self.allies, self.enemies)
        self.bindContext()
        self.active = true
        print(string.format("[TriDriver] 队%d 开战 stage=%s allies=%d enemies=%d",
            self.teamIdx, tostring(stageId), #self.allies, #self.enemies))
    end

    --- 击杀奖励上报
    function drv:reportKill(unit)
        self.kills = self.kills + 1
        if self.onKill then
            local heroIds = {}
            for _, u in ipairs(self.allies) do
                if u.hp > 0 then heroIds[#heroIds + 1] = u.heroId end
            end
            self.onKill({
                teamIdx   = self.teamIdx,
                stageId   = self.stageId,
                expReward = unit.expReward or 0,
                goldReward = unit.goldReward or 0,
                heroIds   = heroIds,
                allyCount = #heroIds,
            })
        end
    end

    function drv:reportDefeatedEnemies()
        for _, u in ipairs(self.enemies) do
            if u.hp <= 0 and not u._triKillReported then
                u._triKillReported = true
                self:reportKill(u)
            end
        end
    end

    --- 死亡后按原战斗补位：后方敌人前移，队列里的下一只从队尾进入。
    function drv:reinforceDeadEnemies()
        local enemies = self.enemies
        local queue = self.enemyQueue
        for i = #enemies, 1, -1 do
            local unit = enemies[i]
            if unit.hp <= 0 then
                if not unit.reviveTimer then
                    unit.reviveTimer = 0
                    unit.atkProgress = 0
                    TM.removeUnit(unit)
                    SEM.removeUnit(unit)
                    BattleCombat.setCardAnim(unit, { state = "dying", timer = 0, lungeDir = -1, noTombstone = true })
                end
                unit.reviveTimer = unit.reviveTimer + (self._tickDt or 0)
                if unit.reviveTimer >= RESPAWN_DELAY and self.reinforceCd <= 0 then
                    self.reinforceCd = REINFORCE_INTERVAL
                    for j = i, #enemies - 1 do
                        local moved = enemies[j + 1]
                        enemies[j] = moved
                        BattleCombat.setCardAnim(moved, { state = "advance", timer = 0, lungeDir = -1,
                            advanceDist = BattleLayout.STRIP_PITCH })
                    end
                    if #queue > 0 then
                        local newUnit = table.remove(queue, 1)
                        newUnit.atkProgress = 0
                        TAL.initUnit(newUnit)
                        enemies[#enemies] = newUnit
                        BattleCombat.clearCardAnim(unit)
                        BattleCombat.setCardAnim(newUnit, { state = "reviving", timer = 0, lungeDir = -1 })
                    else
                        table.remove(enemies)
                        BattleCombat.clearCardAnim(unit)
                    end
                end
            end
        end
    end

    --- 通关推进
    function drv:advanceStage()
        local nextId = SC.getNextStageId(self.stageId)
        if not nextId then
            self:start(self.stageId)
            return
        end
        print(string.format("[TriDriver] 队%d 通关 %s → %s",
            self.teamIdx, tostring(self.stageId), tostring(nextId)))
        self:start(nextId)
        if self.onStageChanged then self.onStageChanged(self.teamIdx, self.stageId) end
    end

    --- 战斗 tick（须已 mount）
    function drv:tick(dt)
        if not self.active then return end
        self._tickDt = dt
        local allies, enemies = self.allies, self.enemies
        if #allies == 0 then return end

        -- 己方阵亡复活计时
        for _, u in ipairs(allies) do
            if u.hp <= 0 then
                u._triReviveTimer = (u._triReviveTimer or 0) + dt
                if u._triReviveTimer >= REVIVE_DELAY then
                    u._triReviveTimer = nil
                    self:reviveUnit(u)
                end
            end
        end

        -- 存活统计
        local hasAliveEnemy, hasAliveAlly = false, false
        for _, u in ipairs(enemies) do
            if u.hp > 0 then hasAliveEnemy = true break end
        end
        for _, u in ipairs(allies) do
            if u.hp > 0 then hasAliveAlly = true break end
        end

        self:reportDefeatedEnemies()
        self.reinforceCd = math.max(0, (self.reinforceCd or 0) - dt)
        self:reinforceDeadEnemies()
        hasAliveEnemy = false
        for _, u in ipairs(enemies) do
            if u.hp > 0 then hasAliveEnemy = true break end
        end

        -- 通关: 敌方全灭（先结算最后一击再切换到下一关）
        if not hasAliveEnemy and #self.enemyQueue == 0 and #self.enemies == 0 then
            self:reportDefeatedEnemies()
            self:advanceStage()
            return
        end
        -- 失败: 己方全灭（等待复活计时，不推进战斗）
        if not hasAliveAlly then
            -- [兜底] 复活计时只对「拿得到 attrs」的单位推进；一旦单位缺 attrs，
            -- 上面永远不会复活它，全灭就会永久卡住。这里按墙钟兜底整队复活。
            self._wipeTimer = (self._wipeTimer or 0) + dt
            if self._wipeTimer >= WIPE_RESET_DELAY then
                self._wipeTimer = nil
                for _, u in ipairs(allies) do
                    u._triReviveTimer = nil
                    self:reviveUnit(u)
                end
                BattleCombat.addFloatingText("重整旗鼓", BattleLayout.STRIP_W * 0.5, BattleLayout.STRIP_CY,
                    { 120, 255, 160 }, false)
                print(string.format("[TriDriver] 队%d 全灭兜底复活 allies=%d", self.teamIdx, #allies))
            end
            BattleCombat.updateCardAnims(dt)
            BattleCombat.updateFloatingTexts(dt)
            BattleCombat.updateHitFlashes(dt)
            return
        end
        self._wipeTimer = nil

        -- 攻击推进
        for _, unit in ipairs(allies) do
            if unit.hp > 0 and not SEM.isFrozen(unit) then
                local interval = getLiveAttackInterval(unit, DEFAULT_ALLY_INTERVAL)
                BattleCombat.advanceAttackProgress(unit, dt, interval, hasAliveEnemy, function()
                    BattleCombat.performAttack(unit, enemies, true)
                end)
            end
        end
        for _, unit in ipairs(enemies) do
            if unit.hp > 0 and not SEM.isFrozen(unit) then
                local interval = getLiveAttackInterval(unit, DEFAULT_ENEMY_INTERVAL)
                BattleCombat.advanceAttackProgress(unit, dt, interval, hasAliveAlly, function()
                    BattleCombat.performAttack(unit, allies, false)
                end)
            end
        end

        -- 状态子系统 tick（mount 作用域内）
        RCH.update(allies, 0)
        BattleCombat.updateHpBuffers(allies, dt)
        BattleCombat.updateHpBuffers(enemies, dt)
        TM.update(dt)
        SEM.update(dt, {
            onDot = function(unit, source, dmg)
                local isUnitAlly = BattleLayout.detectGroup({ unit }) == "ally"
                BattleCombat.dealDamageToUnit(unit, dmg, isUnitAlly, "灼烧 ", { 255, 120, 30 }, source, { isDot = true })
            end,
            onHot = function(unit, source, heal)
                if unit.attrs and unit.hp > 0 then
                    local actual = unit.attrs:heal(heal)
                    if actual > 0 then
                        local isUnitAlly = BattleLayout.detectGroup({ unit }) == "ally"
                        local list = isUnitAlly and allies or enemies
                        local cx, cy = BattleLayout.STRIP_W * 0.5, BattleLayout.STRIP_CY
                        for ii, uu in ipairs(list) do
                            if uu == unit then cx, cy = BattleCombat.getCardPos(list, ii) break end
                        end
                        BattleCombat.addFloatingText("恢复 +" .. NumberUtil.format(actual), cx, cy, { 0, 255, 82 }, false)
                    end
                end
            end,
        })
        TAL.update(dt, allies, enemies, {
            healUnit = function(unit, amount)
                if unit.attrs and unit.hp > 0 then
                    local actual = unit.attrs:heal(amount)
                    return actual
                end
                return 0
            end,
            dealDamage = function(target, damage, isTargetAlly, prefix, color, source)
                return BattleCombat.dealDamageToUnit(target, damage, isTargetAlly, prefix, color, source)
            end,
            dealTalentDamage = function(attacker, target, damage, isTargetAlly, prefix, color, projOpts)
                return BattleCombat.dealTalentDamage(attacker, target, damage, isTargetAlly, prefix, color, projOpts, allies, enemies)
            end,
            syncHp = function(unit)
                BattleCombat.syncUnitHp(unit)
            end,
            performAttack = function(attacker, targetList, isAlly)
                BattleCombat.performAttack(attacker, targetList, isAlly)
            end,
        })

        -- 能量护盾恢复
        for _, u in ipairs(allies) do
            if u.hp > 0 and u.attrs then u.attrs:tickEnergyShield(dt) end
        end
        for _, u in ipairs(enemies) do
            if u.hp > 0 and u.attrs then u.attrs:tickEnergyShield(dt) end
        end

        -- 投射物 / 连击
        ProjectileSystem.update(dt)
        BattleCombat.updateComboQueue(dt)

        -- 纯视觉层
        BattleEffects.update(dt)
        BattleCombat.updateCardAnims(dt)
        BattleCombat.updateFloatingTexts(dt)
        BattleCombat.updateHitFlashes(dt)
    end

    --- 便捷: mount + tick
    function drv:update(dt)
        local CharacterPanel = require("ui.character.panel.CharacterPanel")
        local signature = CharacterPanel.getTeamSignature(self.teamIdx)
        if signature ~= self.teamSignature then
            print(string.format("[TriDriver] 队%d 编队变化，刷新当前关卡 %s", self.teamIdx, tostring(self.stageId)))
            self:start(self.stageId)
        end
        self:activate()
        self:tick(dt)
    end

    return drv
end

return BattleTriDriver
