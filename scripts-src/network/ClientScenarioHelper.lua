---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- ClientScenarioHelper.lua — 情景对话辅助函数（从 Client.lua 拆分）
-- 职责: 检查情景已领取、播放情景链、首次访问建筑情景
-- ============================================================================

local PlayerStore = require("client.data.PlayerStore")
local ScenarioDialogueConfig = require("config.ScenarioDialogueConfig")
local Protocol = require("shared.Protocol")

local ScenarioHelper = {}

-- 依赖注入
local deps_

-- 本地已触发标记（防止异步 claim 返回前重复触发）
-- 一旦 playFirstVisit/playChain 决定播放某个情景，立即标记到这里。
-- 这样即使服务端推送 claimedScenarios 有延迟，也不会重复触发。
local pendingClaims_ = {}

--- 注入外部依赖
---@param deps { sendAction: function }
function ScenarioHelper.setup(deps)
    deps_ = deps
end

--- 检查某个情景是否已被领取（服务端 claimedScenarios 或本地 pending 标记）
---@param scenarioId number
---@return boolean
function ScenarioHelper.isClaimed(scenarioId)
    -- 本地 pending 标记（异步 claim 尚未被服务端推送回来前的防护）
    if pendingClaims_[tostring(scenarioId)] then
        return true
    end

    local sessionData = PlayerStore.Get("session")
    if not sessionData then return false end
    local claimed = sessionData.claimedScenarios
    if not claimed then return false end
    return claimed[tostring(scenarioId)] == true or claimed[scenarioId] == true
end

--- 播放一组情景链：先播放主情景，结束后（若有 heroId）播放英雄分支情景。
--- 播放结束后发送 CLAIM_SCENARIO_REWARD，然后调用 onFinish（若提供）。
---
--- @param mainId    number|nil  主情景 ID（nil = 跳过主情景，直接播英雄分支）
--- @param followIds table|nil   { [heroId] = scenarioId } 英雄分支映射（可选）
--- @param onFinish  function|nil 全部结束后的回调（用于打开建筑页等）
function ScenarioHelper.playChain(mainId, followIds, onFinish)
    local ScenarioDialogue = require("ui.ScenarioDialogue")
    local sendAction = deps_.sendAction

    -- 决定英雄分支
    local heroFollowId = nil
    if followIds then
        local sessionData = PlayerStore.Get("session")
        local heroId = sessionData and sessionData.initialHeroId
        if heroId then
            heroFollowId = followIds[heroId]
        end
    end

    -- 播放英雄分支的内部函数（主情景后或直接调用）
    local function playHeroBranch()
        if heroFollowId and not ScenarioHelper.isClaimed(heroFollowId) then
            local followConfig = ScenarioDialogueConfig["SCENARIO_" .. heroFollowId]
            if followConfig then
                -- 标记本地 pending
                pendingClaims_[tostring(heroFollowId)] = true
                -- 英雄分支情景均为 type=none（无实际奖励），在展示对话【前】发送 claim。
                sendAction(Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD, { scenarioId = heroFollowId })
                deps_.onPendingNotify(heroFollowId)
                ScenarioDialogue.show({
                    mode       = followConfig.mode,
                    background = followConfig.background,
                    steps      = followConfig.steps,
                    onFinish = function()
                        if onFinish then onFinish() end
                    end,
                })
                return
            end
        end
        if onFinish then onFinish() end
    end

    -- mainId 为 nil 时跳过主情景，直接播英雄分支
    if mainId == nil then
        playHeroBranch()
        return
    end

    local mainConfig = ScenarioDialogueConfig["SCENARIO_" .. mainId]
    if not mainConfig then
        if onFinish then onFinish() end
        return
    end

    -- 标记本地 pending（在播放前立即标记，防止异步期间重复触发）
    pendingClaims_[tostring(mainId)] = true

    -- 无奖励情景（type=none）：在展示对话【前】发送 claim，
    -- 防止玩家对话途中失败/退出导致 onFinish 不触发、服务端不记录，重进后反复播放。
    local hasRewards = mainConfig.rewards ~= nil
    if not hasRewards then
        sendAction(Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD, { scenarioId = mainId })
        deps_.onPendingNotify(mainId)
    end

    ScenarioDialogue.show({
        mode       = mainConfig.mode,
        background = mainConfig.background,
        steps      = mainConfig.steps,
        onFinish = function()
            if hasRewards then
                sendAction(Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD, { scenarioId = mainId })
                deps_.onPendingNotify(mainId)
            end
            playHeroBranch()
        end,
    })
end

--- 手动标记某个情景为本地 pending（用于绕过 playChain 直接调用 ScenarioDialogue 的场景）
---@param scenarioId number
function ScenarioHelper.markPending(scenarioId)
    pendingClaims_[tostring(scenarioId)] = true
end

--- 触发首次访问建筑的情景链。若已领取或场景不可用则直接执行 onFinish。
--- entryId 为 nil 时跳过入场情景，直接播放英雄分支（用于离场情景）。
--- @param entryId   number|nil     入场情景 ID（nil = 只播英雄分支）
--- @param followIds table|nil      { [heroId] = scenarioId } 英雄分支（可选）
--- @param onFinish  function|nil   全部结束后的回调
function ScenarioHelper.playFirstVisit(entryId, followIds, onFinish)
    if entryId == nil then
        if followIds then
            ScenarioHelper.playChain(nil, followIds, onFinish)
        elseif onFinish then
            onFinish()
        end
        return
    end
    if ScenarioHelper.isClaimed(entryId) then
        if onFinish then onFinish() end
        return
    end
    ScenarioHelper.playChain(entryId, followIds, onFinish)
end

return ScenarioHelper
