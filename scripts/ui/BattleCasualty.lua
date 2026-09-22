-- ============================================================================
-- BattleCasualty - 战斗死亡补位 / 己方阵亡紧凑 / 胜负判定
-- 从 BattleScene.update 抽出；状态仍由调用方持有，经 ctx 注入
-- ============================================================================

local TM  = require("systems.ThreatManager")
local TAL = require("systems.TalentManager")
local SEM = require("systems.StatusEffectManager")
local ART = require("systems.ArtifactRuntime")
local BattleCombat = require("ui.BattleCombat")
local SpeechBubble = require("ui.SpeechBubble")
local StageBerserk = require("ui.StageBerserk")
local Diag = require("systems.BattleDiag")
local BattleLayout = require("core.BattleLayout")

local M = {}

local REINFORCE_INTERVAL = 0.4

---@param ctx table BattleScene 运行时上下文
---@param logicDt number
---@return boolean consumed 若已处理胜负并应提前 return 则为 true
function M.process(ctx, logicDt)
    local enemies = ctx.enemies
    local allies = ctx.allies
    local enemyQueue = ctx.enemyQueue
    local getCardCX = ctx.getCardCX
    local getAliveUnits = ctx.getAliveUnits
    local syncUnitHp = ctx.syncUnitHp
    local RESPAWN_DELAY = ctx.RESPAWN_DELAY
    local reinforceCdByList = ctx.reinforceCdByList
    local ENEMY_CARD_CY = ctx.ENEMY_CARD_CY
    local ALLY_CARD_CY = ctx.ALLY_CARD_CY
    local currentStageId = ctx.currentStageId
    local stageName = ctx.stageName
    local getStageConfig = ctx.getStageConfig

    -- ---- 敌人死亡处理（死亡即补位：怪物池有剩余立刻替换新怪，不播墓碑动画） ----
    -- [补位节流] 多只敌人同帧死亡时，补位/收缩按 0.4s 间隔逐只进行
    --（首只按 RESPAWN_DELAY 1s，其后每只 +0.4s：AOE 杀 3 只 ≈1.8s 补全
    --；冷却按 enemies 引用隔离存 weak-key 表，三行多场战斗互不干扰）
    local reinforceCd = (reinforceCdByList[enemies] or 0) - logicDt
    if reinforceCd < 0 then reinforceCd = 0 end
    reinforceCdByList[enemies] = reinforceCd
    for i, unit in ipairs(enemies) do
    if unit.hp <= 0 then
        -- 首次检测到死亡：发放击杀奖励（替换与墓碑共用，仅一次）
        if not unit.reviveTimer then
            unit.reviveTimer = 0  -- 标记已处理
            unit.atkProgress = 0
            TM.removeUnit(unit)   -- 清除仇恨记录（仅一次）
            TAL.onEnemyDeath(unit, allies, enemies)  -- 转职天赋: 敌人死亡钩子（影袭等）
            SEM.removeUnit(unit)  -- 清除状态效果

            -- 波次效率累计（本地 UI 统计）
            ctx.waveKillCount = ctx.waveKillCount + 1
            ctx.waveGoldEarned = ctx.waveGoldEarned + (unit.goldReward or 0)
            ctx.waveExpEarned  = ctx.waveExpEarned + (unit.expReward or 0)

            -- 发放击杀奖励（经验 + 金币）
            if ctx.onEnemyKillCallback and (unit.expReward or unit.goldReward) then
                local allyCount = #allies
                local expMult = require("config.ExpTable").getHeroCountExpMult(allyCount)
                -- 收集上场冒险家 heroId 列表
                local heroIds = {}
                for _, ally in ipairs(allies) do
                    if ally.heroId then
                        heroIds[#heroIds + 1] = ally.heroId
                    end
                end
                ctx.onEnemyKillCallback({
                    expReward  = unit.expReward or 0,
                    goldReward = unit.goldReward or 0,
                    allyCount  = allyCount,
                    expMult    = expMult,
                    heroIds    = heroIds,
                    stageId    = currentStageId,
                })
            end

            -- 掉落回调（通知外部生成装备掉落）
            if ctx.onEnemyDropCallback then
                local enemyCX = getCardCX(enemies, i)
                print("[BattleScene] enemy died, calling dropCallback stageId=" .. tostring(currentStageId))
                ctx.onEnemyDropCallback({
                    stageId = currentStageId,
                    enemyCX = enemyCX,
                    enemyCY = ENEMY_CARD_CY,
                })
            else
                print("[BattleScene] enemy died, but ctx.onEnemyDropCallback is nil!")
            end

            -- 击杀台词触发（击杀者说台词）
            if unit._killedBy and unit._killedBy.heroId then
                SpeechBubble.trigger(unit._killedBy, "kill")
            end

            -- 与 BattleScene 注入字段同名（stageKillCount，不是 stageKillCount_）
            ctx.stageKillCount = (ctx.stageKillCount or 0) + 1
            -- 死亡退场动画：条带布局下向右滑出（0.4s）；池空不再显示墓碑（完全隐藏空位）
            local okRatio = unit._overkillRatio or 0
            BattleCombat.setCardAnim(unit, { state = "dying", timer = 0, lungeDir = -1,
                knockbackMult = 1.0 + okRatio * 2.0, noTombstone = true })
        end

        unit.reviveTimer = unit.reviveTimer + logicDt

        if #enemyQueue > 0 then
            -- [死亡即补位 v2] 退场(向右滑出0.4s) → 1s 空位 → 新怪从右滑入补位
            -- [补位节流] 同帧多只待补位时按 REINFORCE_INTERVAL 逐只补入
            if unit.reviveTimer >= RESPAWN_DELAY and reinforceCd <= 0 then
                reinforceCd = REINFORCE_INTERVAL
                reinforceCdByList[enemies] = reinforceCd
                -- [队列前移补位] 死亡槽位 i 由后方敌人依次前移一格填入，
                -- 新怪从怪物池进入队尾淡入补齐（保持敌我阵列紧凑）
                for j = i, #enemies - 1 do
                    local moved = enemies[j + 1]
                    enemies[j] = moved
                    BattleCombat.setCardAnim(moved, { state = "advance", timer = 0, lungeDir = -1,
                        advanceDist = require("core.BattleLayout").STRIP_PITCH })
                end
                local newUnit = table.remove(enemyQueue, 1)
                Diag.installSentinel(newUnit)
                TAL.initUnit(newUnit)
                TAL.checkMarkTarget(allies, enemies)
                newUnit.atkProgress = 0
                enemies[#enemies] = newUnit
                -- 清理旧单位残留的动画状态
                BattleCombat.clearCardAnim(unit)
                BattleCombat.clearHitFlash(unit)
                -- 新怪从右侧滑入淡入补位（队尾）
                BattleCombat.setCardAnim(newUnit, { state = "reviving", timer = 0, lungeDir = -1 })
            end
        else
            -- [池空前移] 无后续敌人：死亡槽位仍由后方敌人前移填位（队列收缩，共享补位节流）
            if unit.reviveTimer >= RESPAWN_DELAY and reinforceCd <= 0 then
                reinforceCd = REINFORCE_INTERVAL
                reinforceCdByList[enemies] = reinforceCd
                for j = i, #enemies - 1 do
                    local moved = enemies[j + 1]
                    enemies[j] = moved
                    BattleCombat.setCardAnim(moved, { state = "advance", timer = 0, lungeDir = -1,
                        advanceDist = require("core.BattleLayout").STRIP_PITCH })
                end
                table.remove(enemies)
                BattleCombat.clearCardAnim(unit)
                BattleCombat.clearHitFlash(unit)
            end
        end
    end
    end

    -- ---- 墓碑处理（己方）：死亡淡出动画，不复活 ----
    for _, unit in ipairs(allies) do
    if unit.hp <= 0 and not unit.reviveTimer then
        -- 神器: 死亡拦截（神圣十架复活 / 亡魂之祭）
        local artifactRevived = ART.onAllyDeath(unit)
        if artifactRevived then
            local idx = 1
            for ai, a in ipairs(allies) do
                if a == unit then idx = ai; break end
            end
            local cx = BattleCombat.getCardCX(allies, idx)
            require("ui.SpineCardEffect").playRevive(cx, ALLY_CARD_CY)
        else
            -- 天赋: 死亡拦截（复活吧爱人复活）
            local revived = TAL.onAllyDeath(unit, allies, syncUnitHp)
            if revived then
                -- 复活成功，跳过死亡处理；播放复活 Spine 特效
                local idx = 1
                for ai, a in ipairs(allies) do
                    if a == unit then idx = ai; break end
                end
                local cx = BattleCombat.getCardCX(allies, idx)
                require("ui.SpineCardEffect").playRevive(cx, ALLY_CARD_CY)
            else
                -- 阵亡台词触发
                SpeechBubble.trigger(unit, "death")

                unit.reviveTimer = 0       -- 标记已处理，防止重复调用
                unit._fallenPending = true -- [阵亡紧凑] 退场完成后移至队尾
                unit.atkProgress = 0
                TM.removeUnit(unit)
                SEM.removeUnit(unit)
                -- 启动死亡动画：角色向下滑出（lungeDir=+1），超额伤害增加击退；完成后直接隐藏
                local okRatio = unit._overkillRatio or 0
                BattleCombat.setCardAnim(unit, { state = "dying", timer = 0, lungeDir = 1,
                    knockbackMult = 1.0 + okRatio * 2.0, noTombstone = true })
            end
        end
    end
    end

    -- [阵亡紧凑] 阵亡英雄退场动画完成后移至队尾，存活英雄前移填位
    -- （单位对象保留：下一关 resetAllyUnit 全员重置复活）
    for i = #allies, 1, -1 do
    local u = allies[i]
    if u._fallenPending then
        local st = BattleCombat.getAnimState(u)
        if st == "gone" or st == nil then
            u._fallenPending = nil
            u._fallen = true
            table.remove(allies, i)
            table.insert(allies, u)
            for j = i, #allies - 1 do
                local moved = allies[j]
                if moved.hp > 0 then
                    BattleCombat.setCardAnim(moved, { state = "advance", timer = 0, lungeDir = 1,
                        advanceDist = require("core.BattleLayout").STRIP_PITCH })
                end
            end
        end
    end
    end

    -- 检查是否有存活单位
    local allyAlive  = getAliveUnits(allies)
    local enemyAlive = getAliveUnits(enemies)

    -- 胜利条件：场上敌人全灭 + 队列为空
    if #enemyAlive == 0 and #enemyQueue == 0 then
    ctx.settleWaveEfficiency()
    ctx.resetWaveTimers()



    local wasFirstClear = ctx.isFirstClear
    if ctx.isFirstClear then
        -- 首通完成：标记关卡已通关，解锁前进按钮
        ctx.clearedStages[currentStageId] = true
        ctx.isFirstClear = false
        StageBerserk.exit()
        print("[BattleScene] 首通完成: " .. stageName)
        -- 通知外部持久化（Client 会发送 NEXT_STAGE 到服务端）
        if ctx.onFirstClearCallback then
            ctx.onFirstClearCallback(currentStageId)
        end
    end
    -- 胜利台词触发（随机选一名存活英雄）
    local aliveHeroesV = {}
    for _, u in ipairs(allies) do
        if u.hp > 0 and u.heroId then
            aliveHeroesV[#aliveHeroesV + 1] = u
        end
    end
    if #aliveHeroesV > 0 then
        local speaker = aliveHeroesV[math.random(#aliveHeroesV)]
        SpeechBubble.trigger(speaker, "victory")
    end

    -- 终焉神殿：胜利 → 进入轮回计时
    if getStageConfig().isTerminalTemple(currentStageId) then
        if ctx.reincarnationTimer == nil then
            ctx.reincarnationTimer = 0
            ctx.battleActive = false
            print("[BattleScene] 终焉神殿胜利，进入轮回倒计时")
        end
        return true
    end

    -- 首通成功：自动前进到下一关（不回到寻怪模式）
    if wasFirstClear then
        ctx.nextStage()
    elseif ctx.searchingTimer == nil then
        -- 挂机模式：进入寻怪倒计时
        ctx.searchingTimer = 0
        ctx.battleActive = false
    end
    return true
    end
    -- 失败条件：己方全灭
    if #allyAlive == 0 then
        StageBerserk.exit()
    -- 战败也结算已有的效率数据（不完整波次仍有参考价值）
    ctx.settleWaveEfficiency()

    -- 终焉神殿：失败 → 回退到上一关（该难度最后一关）
    if getStageConfig().isTerminalTemple(currentStageId) then
        if ctx.defeatTimer == nil then
            ctx.defeatTimer = 0
            ctx.battleActive = false
            ctx.terminalDefeatPending = true
            ctx.defeatByTimeout = false
            print("[BattleScene] 终焉神殿失败，准备回退到上一关")
        end
        return true
    end
    if ctx.defeatTimer == nil then
        ctx.defeatTimer = 0
        ctx.battleActive = false
        ctx.defeatByTimeout = false
        if ctx.onAllDeadCallback then ctx.onAllDeadCallback() end
    end
    return true
    end




    return false
end

return M
