-- ============================================================================
-- BattleAllyLifecycle - BattleScene 单位设置/属性刷新/重载辅助（行为保持提取）
-- bind 注入具名依赖；场景状态始终通过 getter/setter 读写，不回灌旧快照。
-- ============================================================================

local AD = require("systems.AttributeDef")
local TM = require("systems.ThreatManager")
local SEM = require("systems.StatusEffectManager")
local TAL = require("systems.TalentManager")
local RCH = require("systems.RelicConditionHandler")
local ART = require("systems.ArtifactRuntime")
local SC = require("config.StageConfig")
local Diag = require("systems.BattleDiag")
local BattleCombat = require("ui.battle.combat.BattleCombat")
local BattleEffects = require("ui.battle.combat.BattleEffects")
local ProjectileSystem = require("ui.battle.combat.ProjectileSystem")
local SpeechBubble = require("ui.widget.SpeechBubble")
local BottomNav = require("ui.hud.BottomNav")
local BattleAllyReset = require("ui.battle.scene.BattleAllyReset")

local M = {}

function M.getLiveAttackInterval(unit, fallback)
    if unit and unit.attrs and unit.attrs.getActualInterval then
        local attrInterval = unit.attrs:getActualInterval()
        local cachedAttrInterval = unit._lastAttrInterval
        local currentInterval = unit.atkInterval
        if not currentInterval or not cachedAttrInterval
            or math.abs(currentInterval - cachedAttrInterval) <= 0.0001 then
            unit.atkInterval = attrInterval
        end
        unit._lastAttrInterval = attrInterval
    end
    return unit.atkInterval or fallback
end

function M.bind(deps)
    local getStageConfig = deps.getStageConfig
    local getStageMaxFieldEnemies = deps.getStageMaxFieldEnemies
    local loadStage = deps.loadStage
    local resetAllyUnit = deps.resetAllyUnit
    local startBattleTalents = deps.startBattleTalents
    local recalcIdleIncome = deps.recalcIdleIncome
    local getAllies = deps.getAllies
    local getEnemies = deps.getEnemies
    local getEnemyQueue = deps.getEnemyQueue
    local get = deps.get
    local set = deps.set
    local MAX_FIELD_ALLIES = deps.MAX_FIELD_ALLIES
    local ALLY_CARD_CY = deps.ALLY_CARD_CY

    -- [EnemyGuard] 检测 enemies 列表是否被英雄数据污染（一次性报警）
    local function checkEnemiesCorruption(tag)
        if get("_enemyGuardFired") then return end
        local enemies, allies = getEnemies(), getAllies()
        for _, u in ipairs(enemies) do
            if u.heroId and not u.monsterId then
                set("_enemyGuardFired", true)
                local parts = { "[EnemyGuard] CORRUPTION_DETECTED tag=" .. tag
                    .. " enemies contains HERO data! len=" .. #enemies }
                for j, e in ipairs(enemies) do
                    parts[#parts + 1] = string.format("  [%d] heroId=%s monsterId=%s instId=%s hp=%s name=%s",
                        j, tostring(e.heroId), tostring(e.monsterId),
                        tostring(e.instanceId), tostring(e.hp), tostring(e.name))
                end
                parts[#parts + 1] = "  allies_len=" .. #allies
                for j, a in ipairs(allies) do
                    parts[#parts + 1] = string.format("  ally[%d] heroId=%s hp=%s name=%s",
                        j, tostring(a.heroId), tostring(a.hp), tostring(a.name))
                end
                parts[#parts + 1] = "  enemies_ref=" .. tostring(enemies) .. " allies_ref=" .. tostring(allies)
                print(table.concat(parts, "\n"))
                return true
            end
        end
        return false
    end

    --- 恢复主战斗的 BattleCombat 上下文（副本/竞技场关闭后必须调用）
    local function setupBattleCombatContext()
        BattleCombat.setContext({
            getAllies = getAllies,
            getEnemies = getEnemies,
            ALLY_CARD_CY = ALLY_CARD_CY,
            ENEMY_CARD_CY = deps.ENEMY_CARD_CY,
            globalDmgMult = 1.0,
            onCrit = function(attacker, isAlly)
                if isAlly then
                    SpeechBubble.trigger(attacker, "crit")
                end
            end,
            onAttackHit = function(attacker, target, atkCX, atkCY, tgtCX, tgtCY, result, applyHit)
                local hasHeroEffect = attacker.heroId
                                      and ProjectileSystem.hasHeroEffect(attacker.heroId)
                local hasMonsterEffect = attacker.atkEffect
                                         and ProjectileSystem.hasMonsterProjectile(attacker.atkEffect)
                local hitCallback = function()
                    if result.category == "healing" and Diag.logEnabled then
                        print(string.format("[HealDiag4] hitCallback FIRED healer=%s target=%s hp=%.0f applyHit=%s",
                            tostring(attacker.name), tostring(target.name), target.hp or -1, tostring(applyHit ~= nil)))
                    end
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
                BattleCombat.onTalentDealDamage(attacker, target, tgtCX, tgtCY, pfx, applyDamage, projOpts, getAllies(), getEnemies())
            end,
        })
    end

    --- 重置战斗状态（新单位加入时调用）
    local function resetBattle()
        set("battleActive", true)
        set("battleTimeoutElapsed", 0)
        if get("isFirstClear") then
            set("firstClearTimeLeft", require("config.GameConfig").Battle.TIME_LIMIT_SEC)
        else
            set("firstClearTimeLeft", nil)
        end
        Diag.reset()
        BattleCombat.reset()
        BattleEffects.reset()
        ProjectileSystem.reset()
        SpeechBubble.reset()
        TM.reset()
        SEM.reset()
        TAL.reset()
        RCH.reset()
        ART.reset(getAllies())
        for _, u in ipairs(getAllies()) do
            Diag.installSentinel(u)
            resetAllyUnit(u)
            TAL.initUnit(u)
        end
        RCH.initBattle(getAllies())
        ART.initBattle(getAllies())
        for _, u in ipairs(getEnemies()) do
            Diag.installSentinel(u)
            u.atkProgress = 0
            TAL.initUnit(u)
        end
        TM.onBattleStart(getAllies(), getEnemies())
        TAL.onBattleStart(getAllies(), getEnemies())
        checkEnemiesCorruption("RESET_BATTLE_EXIT")
    end

    --- 设置敌方单位列表（DebugPanel 用）
    local function setEnemies(list)
        local maxField = getStageMaxFieldEnemies()
        set("enemies", {})
        set("enemyQueue", {})
        for i, u in ipairs(list) do
            if i <= maxField then
                local enemies = getEnemies()
                enemies[#enemies + 1] = u
            else
                local enemyQueue = getEnemyQueue()
                enemyQueue[#enemyQueue + 1] = u
            end
        end
        resetBattle()
    end

    --- 设置己方单位列表（DebugPanel 用）
    local function setAllies(list)
        checkEnemiesCorruption("setAllies_ENTRY")
        print(string.format("[EnemyGuard] setAllies called listLen=%d enemies_ref=%s enemies_len=%d allies_ref=%s",
            #list, tostring(getEnemies()), #getEnemies(), tostring(getAllies())))
        if #list > MAX_FIELD_ALLIES then
            local trimmed = {}
            for i = 1, MAX_FIELD_ALLIES do
                trimmed[i] = list[i]
            end
            set("allies", trimmed)
        else
            set("allies", list)
        end
        -- 保留创建时的实际槽位，密集列表序号只用于无槽位 Debug 单位的显示顺序。
        for i, u in ipairs(getAllies()) do
            u._slotOrder = u.partySlot or u._slotOrder or i
        end
        for _, u in ipairs(getAllies()) do
            BattleAllyReset.createSnapshot(u)
        end
        for i, u in ipairs(getAllies()) do
            if u.attrs and AD.getAtkCategory(u.attrs.atkType) == "healing" then
                u._diagInitHealer = true
                local healAmt = u.attrs:get(AD.HEAL_AMOUNT)
                local baseHealAmt = u.attrs:getBase(AD.HEAL_AMOUNT)
                local hp = u.attrs:get(AD.HP)
                local maxHp = u.attrs:get(AD.MAX_HP)
                local snapHealAmt = u._baseSnapshot and u._baseSnapshot:get(AD.HEAL_AMOUNT) or -1
                print(string.format(
                    "[HealDiag2] INIT_HEALER [%d] name=%s id=%s lv=%s"
                    .. " healAmt_final=%.1f healAmt_base=%.1f snap_healAmt=%.1f"
                    .. " hp=%d/%d atkType=%s atkCoeff=%.2f",
                    i, tostring(u.name), tostring(u.heroId), tostring(u.level),
                    healAmt, baseHealAmt, snapHealAmt,
                    hp, maxHp,
                    tostring(u.attrs.atkType), u.attrs.atkCoeff or 1.0
                ))
            end
        end
        local wasSearching = (get("searchingTimer") ~= nil) and (not get("battleActive"))
        resetBattle()
        if wasSearching then
            set("battleActive", false)
            print("[BattleScene] setAllies: 恢复寻怪状态 searchingTimer=" .. tostring(get("searchingTimer")))
        end
        if getEnemies() == getAllies() then
            print("[EnemyGuard] CRITICAL: enemies === allies (same table ref!) after setAllies+resetBattle")
        end
        checkEnemiesCorruption("setAllies_EXIT")
        print(string.format("[EnemyGuard] setAllies EXIT enemies_ref=%s allies_ref=%s enemies_len=%d allies_len=%d",
            tostring(getEnemies()), tostring(getAllies()), #getEnemies(), #getAllies()))
        Diag.scanNow(getAllies(), getEnemies(), "setAllies_postReset")
        recalcIdleIncome()
    end

    --- 属性与神器效果一起延迟到下波提交，不改变当前战斗状态。
    local function refreshAllyStats()
        local HC = require("config.HeroConfig")
        local CharacterPanel = require("ui.character.panel.CharacterPanel")
        for _, u in ipairs(getAllies()) do
            -- 阵亡者也更新下波快照，但不提前复活。
            if u.heroId then
                local owned = CharacterPanel.getOwnedHero and CharacterPanel.getOwnedHero(u.heroId)
                if owned and owned.level then
                    local heroLevel = CharacterPanel.getEffectiveLevel
                        and CharacterPanel.getEffectiveLevel(u.heroId) or owned.level
                    local newUnit = HC.createHero(u.heroId, heroLevel, owned.advBranch, owned.awakening, owned.extraTalent)
                    if newUnit and newUnit.attrs then
                        local partySlot = BattleAllyReset.getPartySlot(u, CharacterPanel)
                        if CharacterPanel.applyEquippedItems then
                            local eqArmorType = CharacterPanel.applyEquippedItems(newUnit.attrs, u.heroId, partySlot)
                            if eqArmorType then
                                newUnit.armorType = eqArmorType
                            end
                        end
                        local artifactEffects = require("systems.ArtifactBridge").applyToUnit(newUnit.attrs, partySlot, nil, u.artifactTeamIdx or 1)
                        -- 空表用于明确卸下旧神器效果；与属性快照同步生效。
                        u._pendingArtifactEffects = artifactEffects or {}
                        u._pendingSnapshot = newUnit.attrs
                        u._pendingArmorType = newUnit.armorType
                        -- 必须无条件写回，nil 也代表明确重置，不能保留上一职业/觉醒节点。
                        u.classId = newUnit.classId
                        u.classBranchId = newUnit.classBranchId
                        u.awakeningNodes = newUnit.awakeningNodes
                        u.advBranch = newUnit.advBranch
                        u.advTalentIds = newUnit.advTalentIds
                        local currentStatLevel = u._pendingLevel or u.level
                        u._pendingLevel = heroLevel
                        if heroLevel > currentStatLevel then
                            print(string.format("[BattleScene] refreshAllyStats: hero %s statLv %d→%d stored as pending",
                                tostring(u.heroId), currentStatLevel, heroLevel))
                            if u.hp > 0 then
                                local idx = 1
                                for ai, a in ipairs(getAllies()) do
                                    if a == u then idx = ai; break end
                                end
                                local cx = BattleCombat.getCardCX(getAllies(), idx)
                                require("ui.fx.SpineCardEffect").playLevelUp(cx, ALLY_CARD_CY)
                            end
                        else
                            print(string.format("[BattleScene] refreshAllyStats: hero %s attrs refreshed (equip/awaken change), pending",
                                tostring(u.heroId)))
                        end
                    end
                end
            end
        end
        recalcIdleIncome()
    end

    local function debugInstantClear()
        local enemyQueue = getEnemyQueue()
        for i = #enemyQueue, 1, -1 do enemyQueue[i] = nil end
        for _, e in ipairs(getEnemies()) do
            if e.hp > 0 then e.hp = 0 end
        end
        set("waveStartTime", nil)
        set("waveKillCount", 0)
        set("waveGoldEarned", 0)
        set("waveExpEarned", 0)
        print("[BattleScene][Debug] 立即通关: 已清除所有敌人")
    end

    local function debugJumpToStage(stageId)
        local stageConfig = getStageConfig()
        local stage = stageConfig.getStage(stageId)
        if not stage then
            print("[BattleScene][Debug] 无效关卡 ID: " .. tostring(stageId))
            return
        end
        set("searchingTimer", nil)
        set("defeatTimer", nil)
        set("reincarnationTimer", nil)
        set("regenAccum", 0)
        set("bgTransAnim", { timer = 0, zoomTarget = get("BG_ZOOM_FWD_TARGET") })
        BottomNav.setAllLocked(false)
        set("maxStageId_", stageId)
        set("clearedStages", {})
        for k, v in pairs(stageConfig.buildClearedStagesUpTo(stageId)) do
            local numKey = tonumber(k)
            if numKey and v then get("clearedStages")[numKey] = true end
        end
        set("isFirstClear", not get("clearedStages")[stageId])
        recalcIdleIncome()
        loadStage(stageId, true)
        for _, u in ipairs(getAllies()) do resetAllyUnit(u) end
        startBattleTalents()
        print("[BattleScene][Debug] 跳转到关卡 " .. stageId .. " (" .. stage.name .. ")")
    end

    local function reloadStage(opts)
        set("searchingTimer", nil)
        set("defeatTimer", nil)
        set("regenAccum", 0)
        if opts and opts.startSearching then
            loadStage(get("currentStageId"))
            set("battleActive", false)
            set("searchingTimer", 0)
            print("[BattleScene] 首次进入，以寻怪模式启动")
        else
            loadStage(get("currentStageId"), true)
            BattleAllyReset.restoreOrder(getAllies())
            for _, u in ipairs(getAllies()) do resetAllyUnit(u) end
            startBattleTalents()
        end
    end

    local function resetToDefault()
        require("ui.battle.stage.StageEntryEvents").reset()
        require("systems.StoryPlayer").resetWipe()
        set("currentStageId", 0101)
        set("clearedStages", {})
        set("isFirstClear", true)
        set("initialBattleDataLoaded", false)
        set("battleActive", false)
        set("isPaused", false)
        set("searchingTimer", nil)
        set("defeatTimer", nil)
        set("reincarnationTimer", nil)
        set("regenAccum", 0)
        set("bgAnimTimer", 0)
        set("bgTransAnim", nil)
        set("currentChapter", 0)
        set("maxStageId_", SC.NORMAL_FIRST_STAGE or 101)
        set("enemies", {})
        set("enemyQueue", {})
        SEM.reset()
        TAL.reset()
        RCH.reset()
        ART.reset(getAllies())
        BattleCombat.reset()
        ProjectileSystem.reset()
        BottomNav.setAllLocked(false)
        print("[BattleScene] resetToDefault OK (deferred loadStage)")
    end

    return {
        checkEnemiesCorruption = checkEnemiesCorruption,
        setupBattleCombatContext = setupBattleCombatContext,
        setEnemies = setEnemies,
        setAllies = setAllies,
        refreshAllyStats = refreshAllyStats,
        debugInstantClear = debugInstantClear,
        debugJumpToStage = debugJumpToStage,
        reloadStage = reloadStage,
        resetToDefault = resetToDefault,
    }
end

return M
