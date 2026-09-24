-- ============================================================================
-- TowerTriBattle - 通天塔三行攻坚
-- 三队同一波、共同胜负：任一队全灭整层失败；三行全清才过波
-- 不复活、不独立推关（与 BattleTriDriver 挂机语义隔离）
-- ============================================================================

local AD               = require("systems.AttributeDef")
local TM               = require("systems.ThreatManager")
local SEM              = require("systems.StatusEffectManager")
local TAL              = require("systems.TalentManager")
local ART              = require("systems.ArtifactRuntime")
local RCH              = require("systems.RelicConditionHandler")
local NumberUtil       = require("core.NumberUtil")
local BattleCombat     = require("ui.BattleCombat")
local BattleEffects    = require("ui.BattleEffects")
local ProjectileSystem = require("ui.ProjectileSystem")
local BattleView       = require("ui.BattleView")
local BattleLayout     = require("core.BattleLayout")
local BattleTriPage    = require("ui.BattleTriPage")
local DungeonBattle    = require("ui.DungeonBattle")
local TowerWaveSplit   = require("ui.TowerWaveSplit")
local BattleResultPanel = require("ui.BattleResultPanel")
local BattleStats      = require("systems.BattleStats")
local HeroConfig       = require("config.HeroConfig")
local BF               = require("systems.ButtonFeedback")
local DrawUtil         = require("core.DrawUtil")
local StageConfig      = require("config.StageConfig")
local PlayerStore      = require("core.PlayerStore")

local TowerTriBattle = {}

local TEAM_COUNT = 3
local DEFAULT_ALLY_INTERVAL  = 1.0
local DEFAULT_ENEMY_INTERVAL = 1.5
local TOMBSTONE_REVIVE_TIME = 2.0
local DEATH_ANIM_DURATION = BattleCombat.DEATH_ANIM_DURATION or 0.40
local RESULT_DELAY = 1.2

local BATTLE_ACTIVE = "active"
local BATTLE_WIN    = "win"
local BATTLE_LOSE   = "lose"

---@class TowerLane
---@field teamIdx number
---@field allies table[]
---@field enemies table[]
---@field queue table[]
---@field cleared boolean
---@field wiped boolean
---@field combatState table
---@field psState table
---@field tmState table
---@field talRefs table
---@field beState table
---@field semState table
---@field regenAccum number

local state = {
    open = false,
    phase = BATTLE_ACTIVE,
    lanes = {},
    allAllies = {},
    floor = 1,
    wave = 1,
    resultTimer = 0,
    resultPanelShown = false,
    confirmOpen = false,
    battleSpeed = 1.0,
    onClose = nil,
    logicalW = 1920,
    logicalH = 1080,
}

local inited = false

local function getMainProgressStageId()
    local battleData = PlayerStore.Get("battle")
    return battleData and tonumber(battleData.maxStageId or battleData.currentStageId) or 0
end

local function getMaxUnlockedBattleSpeed()
    local stageId = getMainProgressStageId()
    if stageId <= 0 then return 1.0 end
    local diff = StageConfig.getDifficulty(stageId)
    if diff == StageConfig.DIFFICULTY_HARD then return 1.5 end
    if diff and diff ~= StageConfig.DIFFICULTY_NORMAL then return 2.0 end
    return 1.0
end

local function getBattleLogicDt(dt)
    local maxSpeed = getMaxUnlockedBattleSpeed()
    if state.battleSpeed > maxSpeed then state.battleSpeed = maxSpeed end
    if maxSpeed > 1.0 then return dt * state.battleSpeed end
    return dt
end

local function getSpeedText()
    if state.battleSpeed >= 2.0 then return "X2" end
    if state.battleSpeed >= 1.5 then return "X1.5" end
    return "X1"
end

local function collectAllAllies()
    local list = {}
    for t = 1, TEAM_COUNT do
        local lane = state.lanes[t]
        if lane then
            for _, u in ipairs(lane.allies) do
                list[#list + 1] = u
            end
        end
    end
    return list
end

local function collectFieldEnemies()
    local list = {}
    for t = 1, TEAM_COUNT do
        local lane = state.lanes[t]
        if lane then
            for _, u in ipairs(lane.enemies) do
                list[#list + 1] = u
            end
        end
    end
    return list
end

local function mountLane(lane)
    BattleCombat.mount(lane.combatState)
    ProjectileSystem.mount(lane.psState)
    TM.mount(lane.tmState)
    TAL.mount(lane.talRefs)
    BattleEffects.mount(lane.beState)
    SEM.mount(lane.semState)
end

local function bindLaneContext(lane)
    BattleCombat.setContext({
        getAllies  = function() return lane.allies end,
        getEnemies = function() return lane.enemies end,
        ALLY_CARD_CY  = BattleLayout.STRIP_CY,
        ENEMY_CARD_CY = BattleLayout.STRIP_CY,
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
        onTalentDealDamage = function(attacker, target, tgtCX, tgtCY, pfx, applyDamage, projOpts)
            BattleCombat.onTalentDealDamage(attacker, target, tgtCX, tgtCY, pfx, applyDamage, projOpts, lane.allies, lane.enemies)
        end,
    })
end

local function resetLaneVisuals()
    local s = BattleCombat.mountedState()
    if s then
        s.floatingTexts = {}
        s.pendingFt = {}
        s.ftSpawnCd = 0
        s.cardAnims = {}
        s.hitFlashes = {}
        s.hpBuffers = {}
        s.comboQueue = {}
        s.unitDamageAccum = {}
    end
    BattleEffects.reset()
    ProjectileSystem.reset()
    TM.reset()
    SEM.reset()
end

local function initLaneUnits(lane)
    mountLane(lane)
    resetLaneVisuals()
    for _, u in ipairs(lane.allies) do
        u.atkProgress = 0
        u._artifactDeathHandled = nil
        u._towerDeathNotified = nil
        u.reviveTimer = nil
        TAL.initUnit(u)
    end
    for _, u in ipairs(lane.enemies) do
        u.atkProgress = 0
        u.reviveTimer = nil
        TAL.initUnit(u)
    end
    BattleCombat.playEnterAnims(lane.enemies, -1)
    BattleCombat.playEnterAnims(lane.allies, 1)
    TM.onBattleStart(lane.allies, lane.enemies)
    TAL.onBattleStart(lane.allies, lane.enemies)
    bindLaneContext(lane)
end

local function tickTombstones(lane, dt)
    for i, unit in ipairs(lane.enemies) do
        if unit.hp <= 0 then
            if not unit.reviveTimer then
                unit.reviveTimer = -DEATH_ANIM_DURATION
                unit.atkProgress = 0
                TM.removeUnit(unit)
                SEM.removeUnit(unit)
                BattleCombat.setCardAnim(unit, {
                    state = "dying", timer = 0,
                    lungeDir = -1,
                    knockbackMult = 1.0 + (unit._overkillRatio or 0) * 2.0,
                    noTombstone = true,
                })
            end
            unit.reviveTimer = unit.reviveTimer + dt
            if unit.reviveTimer < 0 then
                unit.atkProgress = 0
            else
                unit.atkProgress = math.min(1.0, unit.reviveTimer / TOMBSTONE_REVIVE_TIME)
                if unit.reviveTimer >= TOMBSTONE_REVIVE_TIME and #lane.queue > 0 then
                    local newUnit = table.remove(lane.queue, 1)
                    TAL.initUnit(newUnit)
                    newUnit.atkProgress = 0
                    newUnit.reviveTimer = nil
                    lane.enemies[i] = newUnit
                    BattleCombat.clearCardAnim(unit)
                    BattleCombat.clearHitFlash(unit)
                    BattleCombat.setCardAnim(newUnit, {
                        state = "reviving", timer = 0, lungeDir = -1,
                    })
                    TM.onBattleStart(lane.allies, lane.enemies)
                end
            end
        end
    end
end

local function laneEnemiesCleared(lane)
    if #lane.queue > 0 then return false end
    if #lane.enemies == 0 then return true end
    for _, u in ipairs(lane.enemies) do
        if u.hp > 0 then return false end
        if u.reviveTimer and u.reviveTimer < TOMBSTONE_REVIVE_TIME and #lane.queue > 0 then
            return false
        end
    end
    return true
end

local function laneAlliesWiped(lane)
    if #lane.allies == 0 then return true end
    local alive = BattleCombat.getAliveUnits(lane.allies)
    return #alive == 0
end

local function tickLane(lane, dt)
    mountLane(lane)
    bindLaneContext(lane)
    if lane.cleared or lane.wiped then
        BattleCombat.updateCardAnims(dt)
        BattleCombat.updateFloatingTexts(dt)
        BattleCombat.updateHitFlashes(dt)
        BattleEffects.update(dt)
        ProjectileSystem.update(dt)
        return
    end

    tickTombstones(lane, dt)

    local allyAlive = BattleCombat.getAliveUnits(lane.allies)
    if #allyAlive == 0 and #lane.allies > 0 then
        for _, unit in ipairs(lane.allies) do
            if unit.hp <= 0 and not unit._artifactDeathHandled then
                unit._artifactDeathHandled = true
                if not unit._towerDeathNotified then
                    unit._towerDeathNotified = true
                    DungeonBattle.onAllyDeath(unit)
                end
                local revived = ART.onAllyDeath(unit)
                if not revived then
                    revived = TAL.onAllyDeath(unit, lane.allies, BattleCombat.syncUnitHp)
                end
            end
        end
        allyAlive = BattleCombat.getAliveUnits(lane.allies)
        if #allyAlive == 0 then
            lane.wiped = true
            print(string.format("[TowerTriBattle] 队%d 全灭", lane.teamIdx))
            return
        end
    end

    if laneEnemiesCleared(lane) then
        lane.cleared = true
        print(string.format("[TowerTriBattle] 队%d 清波 候会合", lane.teamIdx))
        return
    end

    local hasAliveEnemy = #BattleCombat.getAliveUnits(lane.enemies) > 0
    local hasAliveAlly  = #allyAlive > 0

    for _, unit in ipairs(lane.allies) do
        if unit.hp > 0 and not SEM.isFrozen(unit) then
            local interval = unit.atkInterval or DEFAULT_ALLY_INTERVAL
            interval = interval * DungeonBattle.getAtkIntervalMultiplier(unit)
            BattleCombat.advanceAttackProgress(unit, dt, interval, hasAliveEnemy, function()
                BattleCombat.performAttack(unit, lane.enemies, true)
            end)
        end
    end
    for _, unit in ipairs(lane.enemies) do
        if unit.hp > 0 and not SEM.isFrozen(unit) then
            local interval = unit.atkInterval or DEFAULT_ENEMY_INTERVAL
            BattleCombat.advanceAttackProgress(unit, dt, interval, hasAliveAlly, function()
                BattleCombat.performAttack(unit, lane.allies, false)
            end)
        end
    end

    for _, u in ipairs(lane.allies) do
        if u.hp > 0 and u.attrs then u.attrs:tickEnergyShield(dt) end
    end
    for _, u in ipairs(lane.enemies) do
        if u.hp > 0 and u.attrs then u.attrs:tickEnergyShield(dt) end
    end

    BattleCombat.updateHpBuffers(lane.allies, dt)
    BattleCombat.updateHpBuffers(lane.enemies, dt)
    TM.update(dt)
    SEM.update(dt, {
        onDot = function(unit, source, dmg)
            local isUnitAlly = false
            for _, u in ipairs(lane.allies) do
                if u == unit then isUnitAlly = true; break end
            end
            BattleCombat.dealDamageToUnit(unit, dmg, isUnitAlly, "灼烧 ", { 255, 120, 30 }, source, { isDot = true })
        end,
        onHot = function(unit, source, heal)
            if unit.attrs and unit.hp > 0 then
                local actual = unit.attrs:heal(heal)
                BattleCombat.syncUnitHp(unit)
                if actual > 0 then
                    local isUnitAlly = false
                    for _, u in ipairs(lane.allies) do
                        if u == unit then isUnitAlly = true; break end
                    end
                    local list = isUnitAlly and lane.allies or lane.enemies
                    local cx, cy = BattleLayout.STRIP_W * 0.5, BattleLayout.STRIP_CY
                    for ii, uu in ipairs(list) do
                        if uu == unit then cx, cy = BattleCombat.getCardPos(list, ii); break end
                    end
                    BattleCombat.addFloatingText("恢复 +" .. NumberUtil.format(actual), cx, cy, { 0, 255, 82 }, false)
                end
            end
        end,
    })
    TAL.update(dt, lane.allies, lane.enemies, {
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
            return BattleCombat.dealTalentDamage(attacker, target, damage, isTargetAlly, prefix, color, projOpts, lane.allies, lane.enemies)
        end,
        syncHp = function(unit)
            BattleCombat.syncUnitHp(unit)
        end,
        performAttack = function(attacker, targetList, isAlly)
            BattleCombat.performAttack(attacker, targetList, isAlly)
        end,
    })

    pcall(RCH.update, lane.allies, 0)
    pcall(RCH.update, lane.enemies, 0)

    lane.regenAccum = (lane.regenAccum or 0) + dt
    while lane.regenAccum >= 1.0 do
        lane.regenAccum = lane.regenAccum - 1.0
        for _, unit in ipairs(lane.allies) do
            if unit.hp > 0 and unit.attrs then
                local regen = unit.attrs:get(AD.HP_REGEN) or 0
                if regen > 0 then
                    unit.attrs:heal(regen)
                    BattleCombat.syncUnitHp(unit)
                end
            end
        end
        for _, unit in ipairs(lane.enemies) do
            if unit.hp > 0 and unit.attrs then
                local regen = unit.attrs:get(AD.HP_REGEN) or 0
                if regen > 0 then
                    unit.attrs:heal(regen)
                    BattleCombat.syncUnitHp(unit)
                end
            end
        end
    end

    for _, u in ipairs(lane.enemies) do
        if u.hp <= 0 and not u._towerKillReported then
            u._towerKillReported = true
            DungeonBattle.onEnemyKill(nil)
        end
    end

    ProjectileSystem.update(dt)
    BattleCombat.updateComboQueue(dt)
    BattleEffects.update(dt)
    BattleCombat.updateCardAnims(dt)
    BattleCombat.updateFloatingTexts(dt)
    BattleCombat.updateHitFlashes(dt)
end

function TowerTriBattle.init(vg)
    if inited then return end
    inited = true
    BattleView.init(vg)
    BattleTriPage.init(vg)
    BattleEffects.init(vg)
    ProjectileSystem.init(vg)
    BattleResultPanel.init(vg)
    print("[TowerTriBattle] init OK")
end

function TowerTriBattle.isOpen()
    return state.open
end

function TowerTriBattle.isActive()
    return state.open
end

---@param opts table { teamAllies = { [1]=table[], [2]=table[], [3]=table[] }, data = table, onClose = function }
function TowerTriBattle.open(opts)
    opts = opts or {}
    state.open = true
    state.phase = BATTLE_ACTIVE
    state.resultTimer = 0
    state.resultPanelShown = false
    state.confirmOpen = false
    state.onClose = opts.onClose
    state.battleSpeed = 1.0
    local maxSpeed = getMaxUnlockedBattleSpeed()
    if maxSpeed > 1.0 then state.battleSpeed = 1.0 end

    local data = opts.data or {}
    state.floor = data.floor or 1
    state.wave = data.wave or 1

    DungeonBattle.enter(data, {})
    local lanesSplit = TowerWaveSplit.splitToLanes(data.monsters, data.monsterLevel or 1)
    local teamAllies = opts.teamAllies or {}

    state.lanes = {}
    local combinedAllies = {}
    for t = 1, TEAM_COUNT do
        local allies = teamAllies[t] or {}
        local split = lanesSplit[t] or { field = {}, queue = {} }
        local lane = {
            teamIdx = t,
            allies = allies,
            enemies = split.field,
            queue = split.queue,
            cleared = false,
            wiped = false,
            combatState = BattleCombat.newState("tower" .. t),
            psState = ProjectileSystem.newState(),
            tmState = TM.newState(),
            talRefs = TAL.newBattleRefs(),
            beState = BattleEffects.newFxState(),
            semState = SEM.newSemState(),
            regenAccum = 0,
        }
        state.lanes[t] = lane
        for _, u in ipairs(allies) do
            combinedAllies[#combinedAllies + 1] = u
            if u.attrs then
                u.attrs:fillHp()
                u.hp = u.attrs.final[AD.MAX_HP]
                u.maxHp = u.attrs.final[AD.MAX_HP]
            end
        end
        print(string.format("[TowerTriBattle] lane%d allies=%d field=%d queue=%d",
            t, #allies, #lane.enemies, #lane.queue))
    end
    state.allAllies = combinedAllies
    DungeonBattle.enter(data, combinedAllies)

    RCH.reset()
    ART.reset()
    TAL.reset()
    BattleStats.reset()
    local allForRCH = {}
    for _, u in ipairs(combinedAllies) do allForRCH[#allForRCH + 1] = u end
    for t = 1, TEAM_COUNT do
        for _, u in ipairs(state.lanes[t].enemies) do
            allForRCH[#allForRCH + 1] = u
        end
    end
    RCH.initBattle(allForRCH)
    ART.initBattle(combinedAllies)

    for t = 1, TEAM_COUNT do
        initLaneUnits(state.lanes[t])
    end

    local okTBR, TBR = pcall(require, "systems.TowerBuffRuntime")
    if okTBR and TBR then
        if TBR.resetWaveTimers then TBR.resetWaveTimers() end
        if TBR.applyMechanicInit then
            TBR.applyMechanicInit(combinedAllies, collectFieldEnemies())
        end
    end

    print(string.format("[TowerTriBattle] open floor=%d wave=%d allies=%d",
        state.floor, state.wave, #combinedAllies))
end

function TowerTriBattle.close()
    if not state.open then return end
    state.open = false
    state.phase = BATTLE_ACTIVE
    state.confirmOpen = false
    DungeonBattle.exit()
    RCH.reset()
    ART.reset()
    BattleCombat.mount(nil)
    ProjectileSystem.mount(nil)
    TM.mount(nil)
    TAL.mount(nil)
    BattleEffects.mount(nil)
    SEM.mount(nil)
    BattleLayout.setMode("strip")
    local cb = state.onClose
    state.onClose = nil
    if cb then cb() end
    print("[TowerTriBattle] close")
end

function TowerTriBattle.forceClose()
    if not state.open then return end
    state.onClose = nil
    TowerTriBattle.close()
end

function TowerTriBattle.getAllies()
    return state.allAllies
end

local function finishWin()
    if state.phase ~= BATTLE_ACTIVE then return end
    state.phase = BATTLE_WIN
    state.resultTimer = 0
    DungeonBattle.onVictory()
    print("[TowerTriBattle] 三军清波 floor=" .. tostring(state.floor) .. " wave=" .. tostring(state.wave))
end

local function finishLose()
    if state.phase ~= BATTLE_ACTIVE then return end
    state.phase = BATTLE_LOSE
    state.resultTimer = 0
    DungeonBattle.onDefeat()
    print("[TowerTriBattle] 攻坚失败 floor=" .. tostring(state.floor) .. " wave=" .. tostring(state.wave))
end

function TowerTriBattle.update(dt)
    if not state.open then return end
    BattleLayout.setMode("strip")
    local triScale = BattleLayout.CARD_SCALE or 0.48
    ProjectileSystem.setRenderScale(triScale)
    BattleEffects.setRenderScale(triScale)

    if state.phase ~= BATTLE_ACTIVE then
        state.resultTimer = state.resultTimer + dt
        BattleResultPanel.update(dt)
        if state.phase == BATTLE_LOSE and state.resultTimer >= RESULT_DELAY and not state.resultPanelShown then
            if DungeonBattle.isResultReady() then
                state.resultPanelShown = true
                local _, _, elapsedSecs = DungeonBattle.getResultState()
                BattleResultPanel.show({
                    isWin = false,
                    elapsedSecs = elapsedSecs,
                    heroStats = BattleStats.buildHeroDamageStats(state.allAllies, HeroConfig.HEROES),
                    rewards = {},
                    onClose = function()
                        TowerTriBattle.close()
                    end,
                })
            end
        end
        for t = 1, TEAM_COUNT do
            local lane = state.lanes[t]
            if lane then
                mountLane(lane)
                BattleCombat.updateCardAnims(dt)
                BattleCombat.updateFloatingTexts(dt)
                BattleEffects.update(dt)
            end
        end
        return
    end

    local logicDt = getBattleLogicDt(dt)
    DungeonBattle.update(logicDt, collectFieldEnemies(), state.allAllies)
    ART.update(logicDt)

    if DungeonBattle.isTimeLimitExceeded() then
        finishLose()
        return
    end

    local okTBR, TBR = pcall(require, "systems.TowerBuffRuntime")
    if okTBR and TBR and TBR.update then
        pcall(TBR.update, logicDt, state.allAllies, collectFieldEnemies(), function(unit, duration)
            for t = 1, TEAM_COUNT do
                local lane = state.lanes[t]
                if lane then
                    for _, e in ipairs(lane.enemies) do
                        if e == unit then
                            mountLane(lane)
                            SEM.apply(unit, "frozen", duration, nil, nil)
                            return
                        end
                    end
                end
            end
        end)
    end

    for t = 1, TEAM_COUNT do
        tickLane(state.lanes[t], logicDt)
    end

    local anyWiped, allCleared = false, true
    for t = 1, TEAM_COUNT do
        local lane = state.lanes[t]
        if lane.wiped then anyWiped = true end
        if not lane.cleared then allCleared = false end
    end
    if anyWiped then
        finishLose()
        return
    end
    if allCleared then
        finishWin()
    end
end

function TowerTriBattle.draw(vg, logicalW, logicalH)
    if not state.open then return end
    logicalW = logicalW or state.logicalW
    logicalH = logicalH or state.logicalH
    state.logicalW, state.logicalH = logicalW, logicalH
    TowerTriBattle.init(vg)
    BattleLayout.setMode("strip")

    BattleTriPage.drawL1Underlay(vg, logicalW, logicalH)
    BattleTriPage.drawL0(vg, logicalW, logicalH)

    local contentScale = 1.0
    for row = 1, TEAM_COUNT do
        local ix, iy, iw, ih = BattleTriPage.getInteriorRectFor(row, logicalW, logicalH)
        if iw and ih then
            contentScale = math.min(contentScale,
                math.min(iw / BattleLayout.STRIP_W, ih / BattleLayout.STRIP_H))
        end
    end

    for row = 1, TEAM_COUNT do
        local lane = state.lanes[row]
        local ix, iy, iw, ih = BattleTriPage.getInteriorRectFor(row, logicalW, logicalH)
        if lane and ix then
            local dw = BattleLayout.STRIP_W * contentScale
            local dh = BattleLayout.STRIP_H * contentScale
            nvgSave(vg)
            nvgScissor(vg, ix, iy, iw, ih)
            nvgTranslate(vg, ix + (iw - dw) * 0.5, iy + (ih - dh) * 0.5 + ih * 0.06)
            nvgScale(vg, contentScale, contentScale)
            mountLane(lane)
            BattleView.draw(vg, { allies = lane.allies, enemies = lane.enemies }, nil, true)
            nvgRestore(vg)

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 22)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local remain = #lane.queue
            for _, u in ipairs(lane.enemies) do
                if u.hp > 0 then remain = remain + 1 end
            end
            local tag
            if lane.wiped then
                tag = string.format("【小队%d】全灭", row)
            elseif lane.cleared then
                tag = string.format("【小队%d】待会合", row)
            else
                tag = string.format("【小队%d】剩余%d", row, remain)
            end
            if lane.wiped then
                nvgFillColor(vg, nvgRGBA(255, 120, 110, 255))
            elseif lane.cleared then
                nvgFillColor(vg, nvgRGBA(140, 220, 150, 255))
            else
                nvgFillColor(vg, nvgRGBA(215, 222, 240, 255))
            end
            nvgText(vg, ix + 28, iy + 25, tag, nil)
        end
    end

    local elapsed = DungeonBattle.getElapsed()
    local remaining = DungeonBattle.getTimeRemaining()
    local ragePhase = DungeonBattle.getRagePhase()
    local timeText
    local tr, tg, tb = 255, 255, 255
    if ragePhase == 2 then
        timeText = string.format("超级狂暴 剩余%.0fs", remaining)
        tr, tg, tb = 255, 34, 34
    elseif ragePhase == 1 then
        timeText = string.format("狂暴中 剩余%.0fs", remaining)
        tr, tg, tb = 255, 102, 0
    else
        timeText = string.format("通天塔 第%d层  波次 %d/10  剩余%.0fs", state.floor, state.wave, remaining)
        if remaining <= 30 then tr, tg, tb = 255, 144, 144 end
    end
    DrawUtil.drawTextStroke(vg, logicalW * 0.5, 28, timeText, 28,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, tr, tg, tb, 4)

    -- 撤退
    local rx, ry, rw, rh = logicalW * 0.5, logicalH - 42, 220, 56
    nvgBeginPath(vg)
    nvgRoundedRect(vg, rx - rw * 0.5, ry - rh * 0.5, rw, rh, 10)
    nvgFillColor(vg, nvgRGBA(90, 28, 28, 220))
    nvgFill(vg)
    DrawUtil.drawTextStroke(vg, rx, ry, "撤退", 26,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 220, 220, 3)

    -- 倍速
    if getMaxUnlockedBattleSpeed() > 1.0 and state.phase == BATTLE_ACTIVE then
        local sx, sy = logicalW - 70, 40
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx - 48, sy - 22, 96, 44, 8)
        nvgFillColor(vg, nvgRGBA(20, 28, 36, 210))
        nvgFill(vg)
        DrawUtil.drawTextStroke(vg, sx, sy, getSpeedText(), 22,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 220, 235, 255, 3)
    end

    if state.confirmOpen then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, logicalW, logicalH)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, logicalW * 0.5 - 280, logicalH * 0.5 - 140, 560, 280, 16)
        nvgFillColor(vg, nvgRGBA(28, 22, 20, 245))
        nvgFill(vg)
        DrawUtil.drawTextStroke(vg, logicalW * 0.5, logicalH * 0.5 - 70, "确认撤退？", 36,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 230, 200, 4)
        DrawUtil.drawTextStroke(vg, logicalW * 0.5, logicalH * 0.5 - 20, "本层进度将丢失", 24,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 200, 180, 160, 3)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, logicalW * 0.5 - 220, logicalH * 0.5 + 50, 180, 56, 10)
        nvgFillColor(vg, nvgRGBA(140, 40, 40, 240))
        nvgFill(vg)
        DrawUtil.drawTextStroke(vg, logicalW * 0.5 - 130, logicalH * 0.5 + 78, "撤退", 26,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, logicalW * 0.5 + 40, logicalH * 0.5 + 50, 180, 56, 10)
        nvgFillColor(vg, nvgRGBA(70, 70, 70, 240))
        nvgFill(vg)
        DrawUtil.drawTextStroke(vg, logicalW * 0.5 + 130, logicalH * 0.5 + 78, "取消", 26,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
    end

    if BattleResultPanel.isOpen() then
        local fit = math.min(logicalW / 1080, logicalH / 2400)
        nvgSave(vg)
        nvgTranslate(vg, (logicalW - 1080 * fit) * 0.5, (logicalH - 2400 * fit) * 0.5)
        nvgScale(vg, fit, fit)
        BattleResultPanel.draw(vg)
        nvgRestore(vg)
    end
end

local function hitBox(x, y, cx, cy, w, h)
    return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5
end

function TowerTriBattle.cycleBattleSpeed()
    if getMaxUnlockedBattleSpeed() <= 1.0 or state.phase ~= BATTLE_ACTIVE then
        return false
    end
    local maxSpeed = getMaxUnlockedBattleSpeed()
    if state.battleSpeed < 1.5 and maxSpeed >= 1.5 then
        state.battleSpeed = 1.5
    elseif state.battleSpeed < 2.0 and maxSpeed >= 2.0 then
        state.battleSpeed = 2.0
    else
        state.battleSpeed = 1.0
    end
    print("[TowerTriBattle] speed " .. getSpeedText())
    return true
end

function TowerTriBattle.handleClick(wx, wy)
    if not state.open then return true end
    local logicalW, logicalH = state.logicalW, state.logicalH

    if BattleResultPanel.isOpen() then
        local fit = math.min(logicalW / 1080, logicalH / 2400)
        local dx = (wx - (logicalW - 1080 * fit) * 0.5) / fit
        local dy = (wy - (logicalH - 2400 * fit) * 0.5) / fit
        BattleResultPanel.handleInput(dx, dy)
        return true
    end

    if state.confirmOpen then
        if hitBox(wx, wy, logicalW * 0.5 - 130, logicalH * 0.5 + 78, 180, 56) then
            BF.trigger("tower_tri_retreat_ok")
            state.confirmOpen = false
            finishLose()
            return true
        end
        if hitBox(wx, wy, logicalW * 0.5 + 130, logicalH * 0.5 + 78, 180, 56) then
            state.confirmOpen = false
            return true
        end
        return true
    end

    if state.phase ~= BATTLE_ACTIVE then return true end

    if getMaxUnlockedBattleSpeed() > 1.0 and hitBox(wx, wy, logicalW - 70, 40, 96, 44) then
        return TowerTriBattle.cycleBattleSpeed()
    end

    if hitBox(wx, wy, logicalW * 0.5, logicalH - 42, 220, 56) then
        BF.trigger("tower_tri_retreat")
        state.confirmOpen = true
        return true
    end
    return true
end

function TowerTriBattle.handleInput(wx, wy)
    return TowerTriBattle.handleClick(wx, wy)
end

return TowerTriBattle
