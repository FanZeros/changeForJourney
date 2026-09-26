-- ============================================================================
-- BattleScenePhases - 暂停/失败延迟/轮回/寻怪 前置阶段（玩法不变）
-- M.process(ctx, dt) 返回 true 表示 update 应提前 return
-- ============================================================================

local ProjectileSystem = require("ui.battle.combat.ProjectileSystem")
local BattleEffects    = require("ui.battle.combat.BattleEffects")
local SpeechBubble     = require("ui.widget.SpeechBubble")
local BottomNav        = require("ui.hud.BottomNav")
local BattleCombat     = require("ui.battle.combat.BattleCombat")
local TM  = require("systems.ThreatManager")
local SEM = require("systems.StatusEffectManager")
local TAL = require("systems.TalentManager")
local RCH = require("systems.RelicConditionHandler")
local ART = require("systems.ArtifactRuntime")
local Diag = require("systems.BattleDiag")
local BattleAllyReset = require("ui.battle.scene.BattleAllyReset")

local M = {}

function M.process(ctx, dt)
    local isPaused = ctx.isPaused
    local defeatTimer = ctx.defeatTimer
    local reincarnationTimer = ctx.reincarnationTimer
    local searchingTimer = ctx.searchingTimer
    local terminalDefeatPending = ctx.terminalDefeatPending
    local defeatByTimeout = ctx.defeatByTimeout
    local isFirstClear = ctx.isFirstClear
    local currentStageId = ctx.currentStageId
    local maxStageId_ = ctx.maxStageId_
    local battleActive = ctx.battleActive
    local enemies = ctx.enemies
    local enemyQueue = ctx.enemyQueue
    local allies = ctx.allies
    local clearedStages = ctx.clearedStages
    local stageName = ctx.stageName
    local pendingReincarnation = ctx.pendingReincarnation
    local bgTransAnim = ctx.bgTransAnim
    local regenAccum = ctx.regenAccum
    local DEFEAT_DELAY = ctx.DEFEAT_DELAY
    local REINCARNATION_DELAY = ctx.REINCARNATION_DELAY
    local SEARCH_ENEMY_DURATION = ctx.SEARCH_ENEMY_DURATION
    local BG_ZOOM_BACK_TARGET = ctx.BG_ZOOM_BACK_TARGET
    local BG_ZOOM_FWD_TARGET = ctx.BG_ZOOM_FWD_TARGET
    local updateCardAnims = ctx.updateCardAnims
    local updateFloatingTexts = ctx.updateFloatingTexts
    local updateHitFlashes = ctx.updateHitFlashes
    local updateComboQueue = ctx.updateComboQueue
    local getStageConfig = ctx.getStageConfig
    local loadStage = ctx.loadStage
    local resetAllyUnit = ctx.resetAllyUnit
    local startBattleTalents = ctx.startBattleTalents
    local onStageChangedCallback = ctx.onStageChangedCallback
    local onReincarnateCallback = ctx.onReincarnateCallback
    local recalcIdleIncome = ctx.recalcIdleIncome
    local generateIdleEnemyList = ctx.generateIdleEnemyList
    local assignEnemiesToField = ctx.assignEnemiesToField
    local BattleScene = ctx.BattleScene

    -- [修复] 这里不回写 battleActive：本文件内 loadStage 会把 ctx.battleActive 置 true
    -- （失败回退/轮回/寻怪开始都走这条），若用进入 process 时缓存的旧值覆盖，
    -- 会让回退重开后 battleActive 永远停在 false，下一帧 update 直接早退 → 战斗卡死。
    -- 本文件确实需要改 battleActive 的地方（寻怪开始）直接写 ctx.battleActive。
    local function writeback()
        ctx.defeatTimer = defeatTimer
        ctx.reincarnationTimer = reincarnationTimer
        ctx.searchingTimer = searchingTimer
        ctx.terminalDefeatPending = terminalDefeatPending
        ctx.defeatByTimeout = defeatByTimeout
        ctx.pendingReincarnation = pendingReincarnation
        ctx.bgTransAnim = bgTransAnim
        ctx.regenAccum = regenAccum
        ctx.enemies = enemies
        ctx.enemyQueue = enemyQueue
        ctx.maxStageId_ = maxStageId_
        ctx.stageName = stageName
        ctx.isFirstClear = isFirstClear
        ctx.currentStageId = currentStageId
    end

    -- 暂停时只更新动画/浮字（保持视觉流畅），不推进战斗逻辑
    if isPaused then
        ProjectileSystem.update(dt)
        BattleEffects.update(dt)
        updateCardAnims(dt)
        updateFloatingTexts(dt)
        updateHitFlashes(dt)
        updateComboQueue(dt)
        SpeechBubble.update(dt)
        writeback(); return true
    end


    -- ---- 失败延迟后退 ----
    if defeatTimer ~= nil then
        defeatTimer = defeatTimer + dt
        ProjectileSystem.update(dt)
        BattleEffects.update(dt)
        updateCardAnims(dt)
        updateFloatingTexts(dt)
        updateHitFlashes(dt)
        updateComboQueue(dt)
        SpeechBubble.update(dt)
        if defeatTimer >= DEFEAT_DELAY then
            defeatTimer = nil
            defeatByTimeout = false
            local targetId
            if terminalDefeatPending then
                -- 终焉神殿失败：回退到该难度最后一关
                terminalDefeatPending = false
                targetId = getStageConfig().getTerminalPrevStageId(currentStageId) or currentStageId
                -- 解锁导航（终焉神殿中导航被锁定）
                BottomNav.setAllLocked(false)
                -- 恢复战斗 BGM（终焉神殿使用 samsara BGM）
                require("systems.GameBGM").setScene("battle")
                print("[BattleScene] 终焉神殿失败，回退 → " .. tostring(targetId))
            elseif not isFirstClear then
                -- 挂机模式：阵亡不回退，重新加载当前关卡继续战斗
                targetId = currentStageId
                print("[BattleScene] 挂机模式阵亡，重新加载当前关 → " .. tostring(targetId))
            else
                targetId = getStageConfig().getPrevStageId(currentStageId) or currentStageId
                print("[BattleScene] 战斗失败，自动后退 → " .. tostring(targetId))
            end
            bgTransAnim = { timer = 0, zoomTarget = BG_ZOOM_BACK_TARGET }
            loadStage(targetId, true)  -- skipBattleStart
            regenAccum = 0
            -- 阵亡紧凑会打乱 allies 顺序（全灭时尤其明显），先还原再重置
            BattleAllyReset.restoreOrder(allies)
            for _, u in ipairs(allies) do
                resetAllyUnit(u)
                -- 开战天赋会 addModifier 并重算属性。先满血，重算才能保留满血，
                -- 否则死亡时的 0 血会被 recalc 写回，回退后立刻再次全灭并卡死。
                if u.attrs then u.attrs:fillHp() end
            end
            startBattleTalents()
            local AD = require("systems.AttributeDef")
            local revived = 0
            for _, u in ipairs(allies) do
                if u.attrs then
                    u.hp = u.attrs.final[AD.HP]
                    u.maxHp = u.attrs.final[AD.MAX_HP]
                end
                if (u.hp or 0) > 0 then revived = revived + 1 end
            end
            print(string.format("[BattleScene] 失败回退重开 allies=%d revived=%d", #allies, revived))
            if onStageChangedCallback then
                onStageChangedCallback(targetId)
            end
        end
        writeback(); return true
    end

    -- ---- 轮回计时（终焉神殿专用） ----
    if reincarnationTimer ~= nil then
        reincarnationTimer = reincarnationTimer + dt
        ProjectileSystem.update(dt)
        BattleEffects.update(dt)
        updateCardAnims(dt)
        updateFloatingTexts(dt)
        updateHitFlashes(dt)
        updateComboQueue(dt)
        SpeechBubble.update(dt)
        if reincarnationTimer >= REINCARNATION_DELAY then
            reincarnationTimer = nil
            -- 解锁导航
            BottomNav.setAllLocked(false)
            -- 确定轮回目标
            local currentDiff = getStageConfig().getDifficulty(currentStageId)
            local targetStageId = getStageConfig().getReincarnationTarget(currentDiff)
            if not targetStageId then
                print("[BattleScene] 轮回目标无效，当前难度: " .. tostring(currentDiff))
                writeback(); return true
            end
            local targetDiff = getStageConfig().getDifficulty(targetStageId)

            if onReincarnateCallback then
                -- 有外部回调（Client/Standalone）：先播放开场动画，延迟加载关卡
                ---@diagnostic disable-next-line: assign-type-mismatch
                pendingReincarnation = {
                    targetStageId = targetStageId,
                    terminalStageId = currentStageId,
                    fromDifficulty = currentDiff,
                    toDifficulty = targetDiff,
                }
                print("[BattleScene] 轮回倒计时结束，等待外部动画完成后调用 completeReincarnation")
                onReincarnateCallback({
                    fromDifficulty = currentDiff,
                    toDifficulty = targetDiff,
                    newStageId = targetStageId,
                })
            else
                -- 无回调（安全回退）：直接加载关卡
                clearedStages[currentStageId] = true
                if targetStageId > maxStageId_ then
                    maxStageId_ = targetStageId
                    recalcIdleIncome()
                end
                require("systems.GameBGM").setScene("battle")
                bgTransAnim = { timer = 0, zoomTarget = BG_ZOOM_FWD_TARGET }
                loadStage(targetStageId, true)
                regenAccum = 0
                for _, u in ipairs(allies) do resetAllyUnit(u) end
                startBattleTalents()
                if onStageChangedCallback then
                    onStageChangedCallback(targetStageId)
                end
                print("[BattleScene] 轮回完成（无回调）→ " .. stageName .. " (难度: " .. tostring(targetDiff) .. ")")
            end
        end
        writeback(); return true
    end

    -- ---- 挂机寻怪倒计时 ----
    if searchingTimer ~= nil then
        searchingTimer = searchingTimer + dt
        ProjectileSystem.update(dt)
        BattleEffects.update(dt)
        updateCardAnims(dt)
        updateFloatingTexts(dt)
        updateHitFlashes(dt)
        updateComboQueue(dt)
        SpeechBubble.update(dt)
        if searchingTimer >= SEARCH_ENEMY_DURATION then
            searchingTimer = nil
            regenAccum = 0
            -- 开战前刷新属性（装备/槽位强化等可能在寻怪期间才同步完成）
            BattleScene.refreshAllyStats()
            for _, u in ipairs(allies) do resetAllyUnit(u) end
            -- 生成新一波敌人（挂机用5关混合；首通保留 loadStage 已生成的阵容）
            do
                if not isFirstClear then
                    local allEnemies, maxField = generateIdleEnemyList()
                    enemies, enemyQueue = assignEnemiesToField(allEnemies, maxField)
                else
                    -- 首通：loadStage 已按 assignEnemiesToField 放置特殊怪，寻怪结束后勿重新生成
                    for _, u in ipairs(enemies) do
                        u.atkProgress = 0
                    end
                end
                -- 直接写 ctx：writeback 不再回写 battleActive（见文件上方注释）
                battleActive = true
                ctx.battleActive = true
                BattleCombat.reset()
                BattleEffects.reset()
                ProjectileSystem.reset()
                TM.reset()
                SEM.reset()
                TAL.reset()
                RCH.reset()
                ART.reset()
                RCH.initBattle(allies)
                ART.initBattle(allies)
                for _, u in ipairs(allies) do
                    Diag.installSentinel(u)
                    TAL.initUnit(u)
                end
                for _, u in ipairs(enemies) do
                    Diag.installSentinel(u)
                    u.atkProgress = 0
                    TAL.initUnit(u)
                end
                for _, u in ipairs(enemyQueue) do
                    Diag.installSentinel(u)
                end
                -- 新波次敌人入场动画
                BattleCombat.playEnterAnims(enemies, -1)
                TM.onBattleStart(allies, enemies)
                TAL.onBattleStart(allies, enemies)
                -- [诊断] 搜索完成后即时扫描
                Diag.scanNow(allies, enemies, "searchTimer_newWave")
                print("[BattleScene] " .. (isFirstClear and "首通寻怪完成，开战" or "挂机新波次开始"))
            end
        end
        writeback(); return true
    end


    writeback()
    return false
end

return M
