-- ============================================================================
-- BattleTriDriver - 三栏并行战斗·轻量驱动器（Phase 3）
-- 每栏一支队伍的独立战斗: 出波 → 战斗 tick（mount 作用域内）→ 击杀奖励 → 推进
--
-- 与 BattleScene（栏1 全引擎）的分工:
--   栏1 = BattleScene（完整关卡进度/首通/终焉/掉落等）
--   栏2/3 = 本驱动器的轻量实现: 自动战斗、击杀奖励走 onKill 回调、
--           通关自动推进下一关；己方阵亡无倒计时复活（仅神器/天赋瞬时拦截，
--           原地复活），救不回的退场后由后排补位（与主线 BattleCasualty 同规则）
-- 依赖 Phase 2b 的 mount API: 本驱动 update/draw 前先 mount 自己的状态集。
-- ============================================================================
local BattleCombat      = require("ui.battle.combat.BattleCombat")
local BattleEffects     = require("ui.battle.combat.BattleEffects")
local ProjectileSystem  = require("ui.battle.combat.ProjectileSystem")
local SEM               = require("systems.StatusEffectManager")
local TM                = require("systems.ThreatManager")
local TAL               = require("systems.TalentManager")
local ETS               = require("systems.ExtraTalentSystem")
local BattleAllyLifecycle = require("ui.battle.scene.BattleAllyLifecycle")
local BattleMountScope  = require("ui.battle.scene.BattleMountScope")
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
local DropSystem        = require("systems.DropSystem")

local BattleTriDriver = {}

local DEFAULT_ALLY_INTERVAL  = 1.2
local DEFAULT_ENEMY_INTERVAL = 2.0
local RESPAWN_DELAY = 1.0
local ENTER_ANIM_DURATION = 0.30
local ENTER_STAGGER = 0.06
local REWARD_INTERVAL = 0.05
local REINFORCE_INTERVAL = 0.4
local MARCH_DURATION = 2.0
local MARCH_ZOOM = 1.06
local MARCH_ZOOM_END = 0.65
local MARCH_STEP = 7

--- 单位攻击间隔（魔改 buff 感知的最小实现：直接取 attrs 的实际间隔）
local function getLiveAttackInterval(unit, fallback)
    if unit and unit.attrs and unit.attrs.getActualInterval then
        local v = unit.attrs:getActualInterval()
        if v and v >= 0.05 then return v end
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
    if SC.isResourceStage(stageId) then
        for _, unit in ipairs(list) do
            unit.goldReward, unit.expReward = 0, 0
        end
    end
    return list, level
end

--- 新建驱动器
---@param teamIdx number 队伍索引（2/3）
---@param options? table 独立战斗测试可注入 allyFactory，并禁止正常奖励与关卡推进
---@return table drv
function BattleTriDriver.new(teamIdx, options)
    options = options or {}
    ---@class table
    local drv = {
        teamIdx  = teamIdx,
        battleLab = options.battleLab == true,
        allyFactory = options.allyFactory,
        firstClear = options.firstClear == true,
        stageId  = SC.NORMAL_FIRST_STAGE,
        allies   = {},
        enemies  = {},
        enemyQueue = {},
        reinforceCd = 0,
        teamSignature = nil,
        kills    = 0,
        stageTotal = 0,
        pendingKills = {},
        rewardQueue = {},
        rewardTimer = 0,
        dropLuck = 0,
        introTimer = 0,
        marchTimer = 0,
        marchNotice = false,
        active   = false,
        -- [多实例] 各子系统状态
        combatState = BattleCombat.newState("tri" .. teamIdx),
        psState     = ProjectileSystem.newState(),
        tmState     = TM.newState(),
        talRefs     = TAL.newBattleRefs(),
        talUnitStates = TAL.newUnitStates(),
        etsState    = ETS.newState(),
        beState     = BattleEffects.newFxState(),
        semState    = SEM.newSemState(),
        rchState    = RCH.newState(),
        onKill      = nil,  -- function(data) 由 TriPage/宿主注入
        onDrop      = nil,
        onStageCleared = nil,
        terminalRaid = nil,
        onStageChanged = nil,
        onAllDead   = nil,  -- 普通关全灭出口；终焉由协同宿主结算
    }

    --- mount 本战斗的全部子系统状态
    function drv.mount()
        BattleStats.mount(drv.teamIdx)
        BattleCombat.mount(drv.combatState)
        ProjectileSystem.mount(drv.psState)
        TM.mount(drv.tmState)
        TAL.mount(drv.talRefs)
        TAL.mountUnitStates(drv.talUnitStates)
        ETS.mount(drv.etsState)
        BattleEffects.mount(drv.beState)
        SEM.mount(drv.semState)
        RCH.mount(drv.rchState)
    end

    --- 注入 BattleCombat ctx（在 mounted 状态上）
    function drv.bindContext()
        BattleCombat.setContext({
            getAllies  = function() return drv.allies end,
            getEnemies = function() return drv.enemies end,
            ALLY_CARD_CY  = BattleLayout.FIELD_CY,
            ENEMY_CARD_CY = BattleLayout.FIELD_CY,
            -- 战斗超时增伤：本场已持续时间 → 敌我双方全局伤害倍率
            globalDmgMult = require("systems.BattleTimeout").calcMult(drv._timeoutElapsed or 0),
            -- [三战场独立发音] 攻击命中回调：投射物表现 + 音效（与行1 BattleScene 同逻辑；
            -- spawn 落到本行 mount 的 psState，各行互不干扰）
            onAttackHit = function(attacker, target, atkCX, atkCY, tgtCX, tgtCY, result, applyHit)
                local hasHeroEffect = attacker.heroId
                                      and ProjectileSystem.hasHeroEffect(attacker.heroId)
                local hasMonsterEffect = attacker.atkEffect
                                         and ProjectileSystem.hasMonsterProjectile(attacker.atkEffect)

                local hitCallback = function()
                    if applyHit then applyHit() end
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

    --- 全灭退回上一关。第一关没有上一关，就在原地重开。
    function drv:retreatStage()
        self:activate()
        ETS.flush() -- 胜败都提交本线已触发的永久成长，不能借用最近一线的挂载。
        if self.terminalRaid then
            self.terminalRaid:onTeamDefeated(self.teamIdx)
            return
        end
        local prevId = SC.getPrevStageId(self.stageId) or self.stageId
        print(string.format("[TriDriver] 队%d 全灭，从 %s 退回 %s",
            self.teamIdx, tostring(self.stageId), tostring(prevId)))
        if self.teamIdx == 1 then
            local BattleScene = require("ui.battle.scene.BattleScene")
            BattleScene.adoptStageProgress(prevId)
            local ClientDispatcher = require("runtime.ClientDispatcher")
            local battle = ClientDispatcher.get("battle")
            if type(battle) == "table" then
                battle.currentStageId = prevId
                local cleared = battle.clearedStages
                local nextCleared = type(cleared) == "table" and cleared[tostring(prevId)] == true
                battle.battleMode = SC.isResourceStage(prevId) and "idle"
                    or (nextCleared and "idle" or "firstClear")
            end
        end
        self._syncedMainStage = prevId
        self:start(prevId)
        -- 驱动完成退关之后合并保存请求，不在战斗帧重复序列化整个背包。
        require("boot.StandaloneSave").RequestSave()
        BattleCombat.addFloatingText("退回上一关", BattleLayout.STRIP_W * 0.5, BattleLayout.STRIP_CY,
            { 255, 140, 120 }, false)
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
        local previousStageId = self.stageId
        local wasStarted = self._started == true
        self:activate()
        ETS.flush() -- 手动换关/阵容重开兜底：先结清旧战斗，再构建新单位。
        -- 只有真正换关才允许再次提示终焉；门禁处原地循环重开不重复弹窗。
        if previousStageId ~= stageId then self._terminalPrompted = false end
        if self.pendingKills and #self.pendingKills > 0 then
            self:queuePendingKills()
        end
        self.stageId = stageId
        self.pendingStageId = nil
        self.marchTimer = 0
        self.marchNotice = false
        self.kills = 0
        self._clearReported = false
        self._wipeReported = false
        self._labDefeated = false
        self._labTimedOut = false
        self._labElapsed = 0
        self._labTimeLimit = options.timeLimit or 300
        self._timeoutElapsed = 0   -- 战斗超时增伤计时（每场重开清零）
        self._terminalStopped = false
        self:activate()
        TAL.reset()
        self.talUnitStates = TAL.mountedUnitStates()
        -- 清理旧战线单位的临时效果，不触碰其他队的神器状态
        ART.reset(self.allies)
        RCH.reset()
        -- 己方: 正常战斗从编队页构建；战斗实验室由测试配置创建独立单位
        if self.battleLab then
            self.teamSignature = nil
            self.allies = self.allyFactory() or {}
        else
            local CharacterPanel = require("ui.character.panel.CharacterPanel")
            self.teamSignature = CharacterPanel.getTeamSignature(self.teamIdx)
            self.allies = CharacterPanel.getDeployedTeam(self.teamIdx) or {}
        end
        -- 本场固定幸运值：队伍重开才更新，阵亡、换装和延迟领奖不追溯改写。
        self.dropLuck = self.battleLab and 0 or DropSystem.captureTeamLuck(self.allies)
        -- 每场捕获共享首通账本，正式三队也要生成与入场剧情对应的附加怪。
        -- 不改实验室专用全局词缀状态；资源关和终焉仍使用各自的出怪规则。
        local entry = SC.getStage(stageId)
        local isTerminal = not self.battleLab and SC.isTerminalTemple(stageId)
        local firstClearForSpawn = self.firstClear
        if not self.battleLab then
            local liveCleared = require("ui.battle.scene.BattleScene").getClearedStages() or {}
            local battle = require("runtime.ClientDispatcher").get("battle")
            local savedCleared = type(battle) == "table" and battle.clearedStages or {}
            savedCleared = type(savedCleared) == "table" and savedCleared or {}
            firstClearForSpawn = not SC.isResourceStage(stageId) and not isTerminal
                and liveCleared[stageId] ~= true and liveCleared[tostring(stageId)] ~= true
                and savedCleared[stageId] ~= true and savedCleared[tostring(stageId)] ~= true
        end
        local allEnemies
        if isTerminal then
            allEnemies = {}
            for _, monsterId in ipairs(entry.monsters) do
                local boss = MC.createMonster(monsterId, entry.monsterLevel)
                if boss then
                    boss.isBoss = true
                    allEnemies[#allEnemies + 1] = boss
                end
            end
        else
            allEnemies = entry and BattleEnemySpawn.generateEnemyList(entry, firstClearForSpawn) or {}
        end
        if firstClearForSpawn and entry and not SC.isResourceStage(stageId) then
            -- 生成顺序为普通怪后接附加怪；首/末附加怪使用正式出场阶段标记。
            local bonusIds = BattleEnemySpawn.getFirstClearBonusMonsterIds(entry)
            if bonusIds then
                for i = 1, #bonusIds do
                    BattleEnemySpawn.markFirstClearBonusSpawnPhase(allEnemies[#allEnemies - #bonusIds + i], i, #bonusIds)
                end
            end
        end
        if #allEnemies == 0 and not self.battleLab then allEnemies = buildWave(stageId) end
        local maxField = (entry and entry.maxFieldEnemies) or BattleLayout.MAX_PER_SIDE
        maxField = math.min(maxField, BattleLayout.MAX_PER_SIDE)
        self.enemies, self.enemyQueue = BattleEnemySpawn.assignEnemiesToField(allEnemies, maxField)
        self.stageTotal = #allEnemies
        self.pendingKills = {}
        self.reinforceCd = 0
        -- 状态复位（mount 作用域内）
        BattleCombat.reset()
        BattleEffects.reset()
        ProjectileSystem.reset()
        TM.reset()
        SEM.reset() -- 每场普通战斗也只清本队，旧单位DOT/HOT不能继续tick。
        if self.battleLab then
            -- 仅在独立测试入口使用全局词缀状态，不能与游戏内战斗交错运行
            local MAS = require("systems.MapAffixSystem")
            MAS.onStageLoad(self.firstClear and (entry.chapter or 0) or 0, self.allies)
            if MAS.hasAffixes() then
                local wave = {}
                for _, u in ipairs(self.enemies) do wave[#wave + 1] = u end
                for _, u in ipairs(self.enemyQueue) do wave[#wave + 1] = u end
                MAS.applyStaticAffixes(wave)
            end
            -- Boss 词缀（v2.64）：battle-lab 首通同样模拟 Hard+ Boss 强化
            local BAS = require("systems.BossAffixSystem")
            if self.firstClear and entry then
                BAS.onStageLoad(entry.chapter or 0, SC.getDifficulty(stageId))
                if BAS.hasAffixes() then
                    local wave = {}
                    for _, u in ipairs(self.enemies) do wave[#wave + 1] = u end
                    for _, u in ipairs(self.enemyQueue) do wave[#wave + 1] = u end
                    BAS.applyToBosses(wave)
                end
            else
                BAS.clear()
            end
        end
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
        if self.battleLab then
            local Berserk = require("ui.battle.stage.StageBerserk")
            if self.firstClear then Berserk.enter(self.enemies, self.allies) else Berserk.exit() end
        end
        local skipAllyEnter = self._skipAllyEnter == true
        self._skipAllyEnter = nil
        BattleCombat.playEnterAnims(self.enemies, -1)
        BattleCombat.playEnterAnims(self.allies, 1, { skip = skipAllyEnter })
        local enterCount = #self.enemies
        if not skipAllyEnter then
            enterCount = math.max(#self.allies, #self.enemies)
        end
        self.introTimer = ENTER_ANIM_DURATION + math.max(0, enterCount - 1) * ENTER_STAGGER
        self.bindContext()
        self.active = true
        self._started = true
        print(string.format("[TriDriver] 队%d 开战 stage=%s allies=%d enemies=%d",
            self.teamIdx, tostring(stageId), #self.allies, #self.enemies))
        if not self.battleLab then
            if self.onStageChanged and (not wasStarted or previousStageId ~= stageId) then
                self.onStageChanged(self.teamIdx, stageId)
            end
            -- 实际进场才通知剧情；同关重开也允许模块按会话/领取账本去重。
            if not SC.isResourceStage(stageId) then
                require("ui.battle.stage.StageEntryEvents").notify(stageId, self.teamIdx)
            end
        end
    end

    --- 死亡只记账。经验、金币和掉落等本关结束再一次性结算。
    function drv:reportKill(unit)
        self.kills = self.kills + 1
        if self.battleLab then return end
        local pending = self.pendingKills
        -- 资源每杀奖励由 DC 的重复收益 API 结算，绝不叠加借用怪物的金币/经验。
        local isResourceStage = SC.isResourceStage(self.stageId)
        local heroIds = {}
        if isResourceStage then
            -- 资源逐杀记下当时仍存活的队员；关末死亡/切队不改变已赚经验的归属。
            for _, ally in ipairs(self.allies) do
                if ally.hp > 0 then heroIds[#heroIds + 1] = ally.heroId end
            end
        end
        pending[#pending + 1] = {
            stageId = self.stageId,
            heroIds = isResourceStage and heroIds or nil,
            teamIdx = self.teamIdx,
            dropLuck = self.dropLuck,
            expReward = not isResourceStage and (unit.expReward or 0) or 0,
            goldReward = not isResourceStage and (unit.goldReward or 0) or 0,
        }
    end

    function drv:queuePendingKills()
        local pending = self.pendingKills
        if not pending or #pending == 0 then
            self.pendingKills = {}
            return
        end
        local heroIds = {}
        for _, u in ipairs(self.allies) do
            if u.hp > 0 then heroIds[#heroIds + 1] = u.heroId end
        end
        local stageId = pending[1].stageId
        local expReward = 0
        local goldReward = 0
        local queue = self.rewardQueue or {}
        self.rewardQueue = queue
        for i = 1, #pending do
            local kill = pending[i]
            expReward = expReward + (kill.expReward or 0)
            goldReward = goldReward + (kill.goldReward or 0)
            queue[#queue + 1] = { stageId = kill.stageId, dropOnly = true,
                teamIdx = kill.teamIdx, dropLuck = kill.dropLuck, heroIds = kill.heroIds or heroIds }
        end
        self.pendingKills = {} -- 先消费，升级刷新等同步回调重入start不能重复发奖。
        if self.onKill and (expReward > 0 or goldReward > 0) then
            self.onKill({
                teamIdx = self.teamIdx,
                stageId = stageId,
                expReward = expReward,
                goldReward = goldReward,
                heroIds = heroIds,
                allyCount = #heroIds,
            })
        end
    end

    function drv:tickRewards(dt)
        local queue = self.rewardQueue
        if not queue or #queue == 0 or not self.onDrop then return end
        self.rewardTimer = (self.rewardTimer or 0) + dt
        while self.rewardTimer >= REWARD_INTERVAL and #queue > 0 do
            self.rewardTimer = self.rewardTimer - REWARD_INTERVAL
            self.onDrop(table.remove(queue, 1))
        end
        if #queue == 0 then self.rewardTimer = 0 end
    end

    function drv:reportDefeatedEnemies()
        for _, u in ipairs(self.enemies) do
            if u.hp <= 0 then
                TAL.onEnemyDeath(u, self.allies, self.enemies)
                if self.terminalRaid and not u._terminalDeathVisual then
                    u._terminalDeathVisual = true
                    u.atkProgress = 0
                    TM.removeUnit(u)
                    SEM.removeUnit(u)
                    BattleCombat.setCardAnim(u, { state = "dying", timer = 0, lungeDir = -1, noTombstone = true })
                end
                -- 终焉共享池的奖励仍由协同宿主结算，天赋事件不跟奖励锁绑定。
                if not self.terminalRaid and not u._triKillReported then
                    u._triKillReported = true
                    self:reportKill(u)
                end
            else
                TAL.resetEnemyDeath(u)
                u._triKillReported = nil
                if u.reviveTimer then
                    u.reviveTimer = nil
                    BattleCombat.clearCardAnim(u)
                end
            end
        end
    end

    --- 死亡后按原战斗补位：后方敌人前移，队列里的下一只从队尾进入。
    function drv:reinforceDeadEnemies()
        if self.terminalRaid then return end
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

    --- 通关后前进；提示由行内底部持续展示，不进入浮字或弹窗。
    function drv:beginMarch()
        if (self.marchTimer or 0) > 0 then return end
        self.marchTimer = MARCH_DURATION
        self.marchNotice = true
        for _, unit in ipairs(self.allies) do
            if unit.hp > 0 then
                BattleCombat.setCardAnim(unit, { state = "march", timer = 0, lungeDir = -1 })
            end
        end
        print(string.format("[TriDriver] 队%d 前进开始 stage=%s duration=%.1f",
            self.teamIdx, tostring(self.stageId), MARCH_DURATION))
    end

    --- 背景、行军预约、实际推进共用目标；账户账本仅决定是否跳过已通终焉。
    ---@return number destinationId
    ---@return number|nil waitingTerminalId
    function drv:resolveAdvanceStage()
        if self.battleLab then return self.stageId, nil end
        local nextId = SC.getNextStageId(self.stageId)
        if not nextId or not SC.isTerminalTemple(nextId) then
            return nextId or self.stageId, nil
        end
        local BattleScene = require("ui.battle.scene.BattleScene")
        local battle = require("runtime.ClientDispatcher").get("battle")
        local savedMax = type(battle) == "table" and (tonumber(battle.maxStageId) or 0) or 0
        local liveCleared = BattleScene.getClearedStages()
        local savedCleared = type(battle) == "table" and battle.clearedStages or {}
        savedCleared = type(savedCleared) == "table" and savedCleared or {}
        local terminalCleared = liveCleared[nextId] == true or liveCleared[tostring(nextId)] == true
            or savedCleared[nextId] == true or savedCleared[tostring(nextId)] == true
        local liveMax = BattleScene.getMaxStageId()
        local livePrev, savedPrev = SC.getTerminalPrevStageId(liveMax), SC.getTerminalPrevStageId(savedMax)
        local liveRank = livePrev and livePrev + 0.5 or liveMax
        local savedRank = savedPrev and savedPrev + 0.5 or savedMax
        return SC.resolveAutoAdvance(self.stageId, math.max(liveRank, savedRank),
            { [nextId] = terminalCleared })
    end

    --- 保留旧调用接口；未通终焉仍返回终焉入口，实际推进会等待确认。
    function drv:getAdvanceStageId()
        local destination, waitingTerminal = self:resolveAdvanceStage()
        return waitingTerminal or destination
    end

    --- 背景单向放大后保持峰值并淡出；第三个返回值是下层背景的目标关卡。
    --- 终焉仍等玩家确认，无下一关则原地重开，均用当前背景承接。
    function drv:getMarchBackground()
        local remaining = self.marchTimer or 0
        if remaining <= 0 then return 1, 1 end
        local progress = math.max(0, math.min(1, 1 - remaining / MARCH_DURATION))
        local zoomProgress = math.min(1, progress / MARCH_ZOOM_END)
        local zoomEase = zoomProgress * zoomProgress * (3 - 2 * zoomProgress)
        local fadeProgress = math.max(0, (progress - MARCH_ZOOM_END) / (1 - MARCH_ZOOM_END))
        local fadeEase = fadeProgress * fadeProgress * (3 - 2 * fadeProgress)
        local nextId = self:getAdvanceStageId()
        local backgroundStageId = nextId and not SC.isTerminalTemple(nextId) and nextId or self.stageId
        return 1 + (MARCH_ZOOM - 1) * zoomEase, 1 - fadeEase, backgroundStageId
    end

    --- 通关推进
    function drv:advanceStage()
        self.marchTimer = 0
        self.marchNotice = false
        local nextId, waitingTerminalId = self:resolveAdvanceStage()
        if waitingTerminalId then
            local BattleScene = require("ui.battle.scene.BattleScene")
            self._syncedMainStage = self.stageId
            -- 终焉需玩家确认：未确认时原地继续刷本关，整队不能停摆；
            -- 只提示一次，取消后仍可由前进按钮或选关再次进入终焉。
            if self.teamIdx == 1 and BattleScene.getStageId() == self.stageId
                and not self._terminalPrompted then
                self._terminalPrompted = true
                BattleScene.nextStage()
            end
            print(string.format("[TriDriver] 队%d 通关 %s，等待确认终焉 %s，继续原地刷本关",
                self.teamIdx, tostring(self.stageId), tostring(waitingTerminalId)))
            self._skipAllyEnter = true
            self:start(self.stageId)
            return
        end
        local clearedId = self.stageId
        print(string.format("[TriDriver] 队%d 通关 %s → %s",
            self.teamIdx, tostring(clearedId), tostring(nextId)))
        self._syncedMainStage = nextId
        self._clearReported = false
        self._skipAllyEnter = true
        self:start(nextId)
        -- 下一关敌人入场完成之前仍显示前进提示；空编队不进入提示状态。
        self.marchNotice = #self.allies > 0
    end

    --- 失守只停业务，死亡动画/生命拖尾仍推进；取消未落地攻击，不能借视觉收尾回血或伤害。
    function drv:tickTerminalStopped(dt)
        if not self._terminalStopped then
            self._terminalStopped = true
            self.psState.projectiles = {}
            self.combatState.comboQueue = {}
            for _, unit in ipairs(self.enemies) do
                unit.atkProgress = 0
                if unit.hp > 0 then BattleCombat.clearCardAnim(unit) end
            end
        end
        -- finished(false)可能来自本帧后半的DOT/敌攻；此时业务已停止，不能
        -- 再调用复活/伤害钩子，但新阵亡仍需登记并完成退场。
        for _, unit in ipairs(self.allies) do
            if unit.hp <= 0 and not unit._triDeathHandled then
                unit._triDeathHandled = true
                unit.atkProgress = 0
                TM.removeUnit(unit)
                SEM.removeUnit(unit)
                unit._fallenPending = true
                unit._fallenAt = time.elapsedTime
                BattleCombat.setCardAnim(unit, { state = "dying", timer = 0, lungeDir = 1,
                    knockbackMult = 1.0 + (unit._overkillRatio or 0) * 2.0, noTombstone = true })
            end
        end
        BattleCombat.updateHpBuffers(self.allies, dt)
        BattleCombat.updateHpBuffers(self.enemies, dt)
        BattleEffects.update(dt)
        BattleCombat.updateCardAnims(dt)
        BattleCombat.updateFloatingTexts(dt)
        BattleCombat.updateHitFlashes(dt)
        require("ui.battle.scene.BattleAllyReset").compactFallen(self.allies, time.elapsedTime)
    end

    --- 战斗 tick：逻辑时钟只用于伤害/状态，真实时钟用于入场/行军/掉落/视觉。
    --- 单参调用兼容实验室及旧宿主，绝不在驱动内部再次乘全局倍率。
    function drv:tick(realDt, logicDt)
        if not self.active then return end
        local dt = logicDt or realDt
        self._tickDt = dt
        self:tickRewards(realDt)
        -- 共享池可以由另一条战线打空：先分发本线死亡，再走失守/胜利早返。
        if self.terminalRaid then self.terminalRaid:sync() end
        self:reportDefeatedEnemies()
        local allies, enemies = self.allies, self.enemies
        if self.terminalRaid and self.terminalRaid.defeated[self.teamIdx] then
            self:tickTerminalStopped(realDt)
            return
        end
        if self.terminalRaid and self.terminalRaid.finished then
            self:tickTerminalStopped(realDt)
            return
        end
        if #allies == 0 then
            self.marchTimer = 0
            self.marchNotice = false
            return
        end
        if (self.introTimer or 0) > 0 or (self.terminalRaid and self.terminalRaid._introPending) then
            self.introTimer = math.max(0, (self.introTimer or 0) - realDt)
            BattleCombat.updateCardAnims(realDt)
            BattleCombat.updateFloatingTexts(realDt)
            BattleCombat.updateHitFlashes(realDt)
            if self.introTimer <= 0 then self.marchNotice = false end
            return
        end
        if (self.marchTimer or 0) <= 0 then self.marchNotice = false end
        -- 入场/空队/行军/失守不消耗战斗时钟；倍率需在本帧攻击前更新。
        if (self.marchTimer or 0) <= 0 and (#enemies > 0 or #self.enemyQueue > 0) then
            self._timeoutElapsed = (self._timeoutElapsed or 0) + dt
            self.combatState.ctx.globalDmgMult = require("systems.BattleTimeout").calcMult(self._timeoutElapsed)
        end
        if self.battleLab then
            self._labElapsed = self._labElapsed + dt
            if self._labElapsed >= self._labTimeLimit then
                self._labTimedOut = true
                self.active = false
                return
            end
        end

        -- 倒下的人先试瞬时拦截复活（神器/天赋，原地复活）；救不回的退场，由后排补位。
        if not self.battleLab then
            for _, u in ipairs(allies) do
                if u.hp <= 0 and not u._triDeathHandled then
                    local revived = ART.onAllyDeath(u)
                    if not revived then
                        revived = TAL.onAllyDeath(u, allies, BattleCombat.syncUnitHp)
                    end
                    if revived then
                        local idx = 1
                        for ai, a in ipairs(allies) do
                            if a == u then idx = ai break end
                        end
                        local cx, cy = BattleCombat.getCardPos(allies, idx)
                        BattleCombat.addFloatingText("复活", cx, cy, { 120, 255, 160 }, false)
                        -- 仅给真正回到正生命的本人加视觉；亡魂拦截不等于回血复活。
                        if u.hp > 0 then
                            require("ui.fx.SpineCardEffect").playRevive(cx, cy, nil, "tri" .. self.teamIdx,
                                BattleLayout.CARD_W * BattleLayout.CARD_SCALE,
                                BattleLayout.CARD_H * BattleLayout.CARD_SCALE)
                        end
                    else
                        u._triDeathHandled = true
                        u.atkProgress = 0
                        TM.removeUnit(u)
                        SEM.removeUnit(u)
                        -- [阵亡紧凑] 退场动画播完后移至队尾，存活者前移补位
                        u._fallenPending = true
                        u._fallenAt = time.elapsedTime
                        BattleCombat.setCardAnim(u, { state = "dying", timer = 0, lungeDir = 1,
                            knockbackMult = 1.0 + (u._overkillRatio or 0) * 2.0, noTombstone = true })
                    end
                elseif u.hp > 0 then
                    u._triDeathHandled = nil
                end
            end
            -- [阵亡紧凑] 与主线 BattleCasualty 同规则：退场完成 → 移队尾 → 存活者前移一格（含卡住兜底）
            require("ui.battle.scene.BattleAllyReset").compactFallen(allies, time.elapsedTime)
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
        hasAliveAlly = false
        for _, u in ipairs(allies) do
            if u.hp > 0 then hasAliveAlly = true break end
        end
        if self.terminalRaid then
            if self.terminalRaid.hp <= 0 then
                self.terminalRaid:finish(true)
                self:tickTerminalStopped(realDt)
                return
            end
            if not hasAliveAlly then
                self:retreatStage()
                self:tickTerminalStopped(realDt)
                return
            end
            if self.terminalRaid.finished then
                self:tickTerminalStopped(realDt)
                return
            end
        end
        if self.battleLab and not hasAliveAlly then
            self._labDefeated = true
            self.active = false
            return
        end

        -- 通关奖励只做展示，不挡住前进和下一关。
        if not self.terminalRaid and not hasAliveEnemy and #self.enemyQueue == 0 and #self.enemies == 0 then
            self:reportDefeatedEnemies()
            if self.battleLab then
                self._clearReported = true
                self.active = false
                return
            end
            if not self._clearReported then
                self._clearReported = true
                ETS.flush()
                self:queuePendingKills()
                if self.onStageCleared then self.onStageCleared(self.teamIdx, self.stageId) end
            end
            if (self.marchTimer or 0) <= 0 then
                self:beginMarch()
            end
            self.marchTimer = self.marchTimer - realDt
            for _, unit in ipairs(allies) do
                if unit.hp > 0 then
                    local step = math.sin(self.marchTimer * 10) * MARCH_STEP
                    BattleCombat.setCardAnim(unit, {
                        state = "march", timer = 0, lungeDir = -1, marchStep = step,
                    })
                end
            end
            BattleCombat.updateCardAnims(realDt)
            BattleCombat.updateFloatingTexts(realDt)
            BattleCombat.updateHitFlashes(realDt)
            if self.marchTimer <= 0 then
                self:advanceStage()
            end
            return
        end
        -- 失败: 己方全灭，退回上一关。已通关记录保留。
        if not hasAliveAlly then
            if self.battleLab then
                self._labDefeated = true
                self.active = false
                return
            end
            if not self._wipeReported then
                self._wipeReported = true
                if self.onAllDead then self.onAllDead(self.teamIdx, self.stageId) end
            end
            self:retreatStage()
            return
        end

        -- 攻击推进
        for _, unit in ipairs(allies) do
            if self.terminalRaid and self.terminalRaid.hp <= 0 then break end
            if unit.hp > 0 and not SEM.isFrozen(unit) then
                local interval = getLiveAttackInterval(unit, DEFAULT_ALLY_INTERVAL)
                BattleCombat.advanceAttackProgress(unit, dt, interval, hasAliveEnemy, function()
                    BattleCombat.performAttack(unit, enemies, true)
                end)
            end
        end
        for _, unit in ipairs(enemies) do
            if self.terminalRaid and self.terminalRaid.hp <= 0 then break end
            if unit.hp > 0 and not SEM.isFrozen(unit) then
                local interval = getLiveAttackInterval(unit, DEFAULT_ENEMY_INTERVAL)
                BattleCombat.advanceAttackProgress(unit, dt, interval, hasAliveAlly, function()
                    BattleCombat.performAttack(unit, allies, false)
                end)
            end
        end

        -- 状态子系统 tick（mount 作用域内）
        ART.update(dt, allies)
        RCH.update(allies, 0)
        if self.battleLab then
            ART.update(dt)
            require("systems.MapAffixSystem").tick(dt, allies, enemies)
            local BAS = require("systems.BossAffixSystem")
            if self.firstClear and BAS.hasAffixes() then
                BAS.tick(dt, enemies)
            end
            if self.firstClear then
                require("ui.battle.stage.StageBerserk").update(dt, enemies, allies)
            end
        end
        BattleCombat.updateHpBuffers(allies, dt)
        BattleCombat.updateHpBuffers(enemies, dt)
        TM.update(dt)
        -- 攻击/神器等本帧新死亡必须早于 SEM.update 的死人状态清理。
        self:reportDefeatedEnemies()
        SEM.update(dt, {
            onDot = function(unit, source, dmg)
                local isUnitAlly = BattleLayout.detectGroup({ unit }) == "ally"
                BattleCombat.dealDamageToUnit(unit, dmg, isUnitAlly, "", { 255, 120, 30 }, source, { isDot = true, floatKind = "burn" })
            end,
            onHot = function(unit, source, heal)
                if unit.attrs and unit.hp > 0 then
                    local actual = unit.attrs:heal(heal)
                    BattleCombat.syncUnitHp(unit)
                    if actual > 0 then
                        local isUnitAlly = BattleLayout.detectGroup({ unit }) == "ally"
                        local list = isUnitAlly and allies or enemies
                        local cx, cy = BattleLayout.STRIP_W * 0.5, BattleLayout.STRIP_CY
                        for ii, uu in ipairs(list) do
                            if uu == unit then cx, cy = BattleCombat.getCardPos(list, ii) break end
                        end
                        BattleCombat.addFloatingText("+" .. NumberUtil.format(actual), cx, cy, { 0, 255, 82 }, false, nil, false, "heal")
                    end
                end
            end,
        })
        TAL.update(dt, allies, enemies, {
            healUnit = function(unit, amount)
                if unit.attrs and unit.hp > 0 then
                    local actual = unit.attrs:heal(amount)
                    BattleCombat.syncUnitHp(unit)
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

        -- 生命/能量护盾恢复：按逻辑秒推进，生命回复受 HEAL_BONUS 增幅与 heal 禁疗守门。
        for _, u in ipairs(allies) do
            if u.hp > 0 and u.attrs then
                local regen = CF.calcHpRegen(u.attrs)
                if regen > 0 then
                    u.attrs:heal(regen * dt)
                    BattleCombat.syncUnitHp(u)
                end
                u.attrs:tickEnergyShield(dt)
            end
        end
        for _, u in ipairs(enemies) do
            if u.hp > 0 and u.attrs then
                local regen = CF.calcHpRegen(u.attrs)
                if regen > 0 then
                    u.attrs:heal(regen * dt)
                    BattleCombat.syncUnitHp(u)
                end
                u.attrs:tickEnergyShield(dt)
            end
        end

        -- 投射物 / 连击
        ProjectileSystem.update(dt)
        BattleCombat.updateComboQueue(dt)
        self:reportDefeatedEnemies()

        -- 纯视觉层
        BattleEffects.update(realDt)
        BattleCombat.updateCardAnims(realDt)
        BattleCombat.updateFloatingTexts(realDt)
        BattleCombat.updateHitFlashes(realDt)
    end

    --- 便捷: mount + tick
    function drv:update(dt, logicDt)
        if not self.battleLab and not SC.isResourceStage(self.stageId) then
            require("ui.battle.stage.StageEntryEvents").retry(self.teamIdx)
        end
        -- 协同期间签名变更不能单路重开，否则会破坏同编号共享池绑定。
        if not self.battleLab and not self.terminalRaid then
            self._sigTick = (self._sigTick or 0) + 1
            if self._sigTick >= 15 then
                self._sigTick = 0
                local CharacterPanel = require("ui.character.panel.CharacterPanel")
                local signature = CharacterPanel.getTeamSignature(self.teamIdx)
                if signature ~= self.teamSignature and (self.marchTimer or 0) <= 0 then
                    self:start(self.stageId)
                    return
                end
            end
        end
        self:activate()
        self:tick(dt, logicDt)
    end

    return drv
end

return BattleTriDriver
