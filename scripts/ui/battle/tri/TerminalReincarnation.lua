-- 终焉胜利只结账，不切关；等主线对白/奖励真实收尾，再走既有轮回动画。
-- 状态由 BattleScene 持有，清档/读档丢弃 pending 后旧动画 token 不再有效。
local M = {}
local ETS = require("systems.ExtraTalentSystem")

---@class TerminalReincarnationPending
---@field targetStageId number
---@field terminalStageId number
---@field fromDifficulty string
---@field toDifficulty string
---@field triTerminal boolean
---@field token number
---@field timer number
---@field animationStarted boolean

local function isBlocked()
    local Reward = require("ui.hud.popup.RewardPopup")
    return Reward.isOpen() or Reward.hasPendingBattleRewards()
        or require("ui.story.ScenarioDialogue").isActive()
        or require("ui.story.gate.IntroCutscene").isActive()
        or require("ui.story.gate.LetterIntro").isOpen()
        -- 横屏同时可见战场与城镇；不等未进入的锻炉/教堂二级菜单剧情。
        or require("systems.StoryPlayer").hasPending("battle_town")
        or not require("systems.TutorialManager").canPlayPendingStory()
        or require("ui.tutorial.TutorialPageRecovery").isPendingStoryBlocked("battle_town")
end

---@param pending TerminalReincarnationPending
---@param dt number
---@param delay number
---@param onReincarnate function|nil
---@param complete function
function M.tick(pending, dt, delay, onReincarnate, complete)
    if pending.animationStarted then return end
    if isBlocked() then
        pending.timer = 0
        return
    end
    pending.timer = pending.timer + math.max(0, dt)
    if pending.timer < delay then return end
    -- 先登记动画态再调外部闭包，兼容同步 skip/完成，也防下一帧重复 start。
    pending.animationStarted = true
    print("[BattleScene] 终焉剧情及奖励已完成，开始轮回动画 token=" .. pending.token)
    if onReincarnate then
        onReincarnate({ fromDifficulty = pending.fromDifficulty, toDifficulty = pending.toDifficulty,
            newStageId = pending.targetStageId, reincarnationToken = pending.token })
    else
        complete(pending.token)
    end
end

-- 三队生命周期由Page注入真实驱动，事务期间暂时抑制各队独立存档。
---@param drivers table
---@param stageId number
---@param setApplying function
function M.enterTeams(drivers, stageId, setApplying)
    setApplying(true)
    local ok, err = pcall(function()
        for row = 1, 3 do
            local drv = drivers[row]
            if drv then
                drv.pendingStageId = nil
                drv._syncedMainStage = stageId
                drv:start(stageId)
            end
        end
    end)
    setApplying(false)
    if not ok then error(err) end
end

---@param raid table
---@param drivers table
---@param previous number
---@param scene table
---@param gotoTeamStage function
function M.retreat(raid, drivers, previous, scene, gotoTeamStage)
    for _, drv in pairs(drivers) do
        drv:activate()
        ETS.flush() -- 协同失败时其他未全灭战线的实际成长也提交，重开前逐域结清。
        drv.pendingStageId = previous or raid.stageId
    end
    scene.adoptStageProgress(previous)
    gotoTeamStage(1, previous)
    require("ui.hud.BottomNav").setAllLocked(false)
    require("systems.GameBGM").setScene("battle")
    for row = 2, 3 do
        if drivers[row] then drivers[row]:start(previous or raid.stageId) end
    end
    print(string.format("[BattleTriPage] 终焉失败，三队协同结束 stage=%d", raid.stageId))
end

---@param raid table
---@param drivers table
---@param settle function
---@param scene table
function M.settleVictory(raid, drivers, settle, scene)
    -- 保留finished协同及三队终焉背景，补齐最后一线打空后的其他线死亡回执。
    for _, drv in pairs(drivers) do
        drv.pendingStageId = nil
        drv:activate()
        drv:reportDefeatedEnemies()
        ETS.flush()
    end
    settle(raid)
    scene.completeTriTerminal(raid.stageId)
    print(string.format("[BattleTriPage] 终焉胜利已结算，等待轮回 stage=%d", raid.stageId))
end

-- 放弃运行态协同不走胜负结算，读档/清档不能追加旧战斗奖励。
function M.discardRaid(raid, drivers)
    if not raid then return end
    raid:release()
    for _, drv in pairs(drivers) do drv.terminalRaid = nil end
end

---@param drv table
function M.discardDriver(drv)
    drv.active = false
    drv.pendingKills, drv.rewardQueue = {}, {}
    drv.rewardTimer, drv.pendingStageId = 0, nil
    drv.psState.projectiles, drv.combatState.comboQueue = {}, {}
    drv.onKill, drv.onDrop, drv.onStageCleared, drv.onStageChanged, drv.onAllDead = nil, nil, nil, nil, nil
    drv:activate()
    ETS.discard() -- 清档/读档直接丢弃旧战线pending与dirty，不走战斗结算。
    require("systems.RelicConditionHandler").reset()
    require("systems.ArtifactRuntime").reset(drv.allies)
end

return M
