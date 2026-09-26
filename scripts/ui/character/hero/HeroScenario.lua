-- ============================================================================
-- HeroScenario.lua — 四人玩梗角色的入队 / 闲聊情景
-- 入队只播一次（写入 session.claimedScenarios）；闲聊每次进游戏每个角色播一次。
-- ============================================================================

local ScenarioDialogueConfig = require("config.ScenarioDialogueConfig")
local ScenarioDialogue = require("ui.story.ScenarioDialogue")
local ClientDispatcher = require("runtime.ClientDispatcher")

local HeroScenario = {}

local JOIN_ID = { [18] = 74, [19] = 75, [24] = 76, [25] = 77 }
local IDLE_ID = { [18] = 78, [19] = 79, [24] = 80, [25] = 81 }

---@type table<integer, boolean>
local idleSeen_ = {}

-- 对话正在播时新来的入队请求先排队，当前对话（含退场动画）结束后再播，避免静默丢弃
---@type integer[]
local pending_ = {}

---@param heroId integer
local function enqueue(heroId)
    for i = 1, #pending_ do
        if pending_[i] == heroId then return end
    end
    pending_[#pending_ + 1] = heroId
end

-- 前向声明：播放函数在对话忙时入队后需要立刻尝试消化队列
---@type fun()
local drainPending

---@param v any
---@return integer
local function heroIdOf(v)
    local n = tonumber(v)
    if not n then return 0 end
    return math.floor(n)
end

---@return table, table
local function sessionAndClaimed()
    local sessionData = ClientDispatcher.get("session") or {}
    local claimed = sessionData.claimedScenarios
    if type(claimed) ~= "table" then
        claimed = {}
    end
    return sessionData, claimed
end

---@param id integer
---@return boolean
local function isClaimed(id)
    local _, claimed = sessionAndClaimed()
    return claimed[tostring(id)] == true or claimed[id] == true
end

---@param id integer
local function markClaimed(id)
    local sessionData, claimed = sessionAndClaimed()
    claimed[tostring(id)] = true
    local updated = {}
    for k, v in pairs(sessionData) do
        updated[k] = v
    end
    updated.claimedScenarios = claimed
    ClientDispatcher.handleStateUpdate(cjson.encode({ modules = { session = updated } }))
    -- 入队只该播一次：立刻落档，避免播放中途退出后重启重播
    local okSave, StandaloneSave = pcall(require, "boot.StandaloneSave")
    if okSave and StandaloneSave and StandaloneSave.Flush then
        StandaloneSave.Flush()
    end
    print("[HeroScenario] claimed scenario " .. tostring(id))
end

---@param id integer
---@param onFinish function|nil
---@return boolean
local function showScenario(id, onFinish)
    if ScenarioDialogue.isActive() then
        print("[HeroScenario] skip show, dialogue active id=" .. tostring(id))
        return false
    end
    local cfg = ScenarioDialogueConfig["SCENARIO_" .. tostring(id)]
    if not cfg or not cfg.steps then
        print("[HeroScenario] missing config " .. tostring(id))
        return false
    end
    ScenarioDialogue.show({
        mode = cfg.mode or "small",
        steps = cfg.steps,
        onFinish = onFinish,
    })
    print("[HeroScenario] show scenario " .. tostring(id))
    return true
end

---@param heroId integer
---@param onFinish function|nil
local function playIdle(heroId, onFinish)
    local idleId = IDLE_ID[heroId]
    if not idleId or idleSeen_[heroId] then
        if onFinish then onFinish() end
        return
    end
    local shown = showScenario(idleId, function()
        idleSeen_[heroId] = true
        if onFinish then onFinish() end
    end)
    if shown then
        idleSeen_[heroId] = true
    else
        -- 没播出来（配置缺失或已有对话在播），不占用本局次数，交给排队重试
        enqueue(heroId)
        drainPending()
    end
end

---@param heroId integer
---@param onFinish function|nil
local function playJoinThenIdle(heroId, onFinish)
    local joinId = JOIN_ID[heroId]
    if not joinId then
        if onFinish then onFinish() end
        return
    end
    local heroes = ClientDispatcher.get("heroes") or {}
    local roster = heroes.roster or {}
    local owned = roster[heroId] or roster[tostring(heroId)]
    if isClaimed(joinId) or (type(owned) == "table" and owned.level) then
        if not isClaimed(joinId) then markClaimed(joinId) end
        playIdle(heroId, onFinish)
        return
    end
    local shown = showScenario(joinId, function()
        playIdle(heroId, onFinish)
    end)
    if shown then
        markClaimed(joinId)
    else
        -- 对话忙或配置缺失：不标记已看，排队等当前对话结束再播
        enqueue(heroId)
        drainPending()
    end
end

--- 当前对话结束后把排队的入队/闲聊补上
local function drainPending()
    if ScenarioDialogue.isActive() or #pending_ == 0 then return end
    local heroId = table.remove(pending_, 1)
    playJoinThenIdle(heroId, drainPending)
end

--- 招募结果里 isNew 的四人，播入队再接闲聊
---@param results table|nil
function HeroScenario.onRecruitResults(results)
    if type(results) ~= "table" then return end
    local queue = {}
    for i = 1, #results do
        local row = results[i]
        if row and row.type == "hero" and row.isNew then
            local hid = heroIdOf(row.heroId)
            if JOIN_ID[hid] then
                queue[#queue + 1] = hid
                print("[HeroScenario] recruit new hero " .. tostring(hid))
            end
        end
    end
    local function nextAt(index)
        if index > #queue then
            drainPending()
            return
        end
        playJoinThenIdle(queue[index], function()
            nextAt(index + 1)
        end)
    end
    nextAt(1)
end

--- 打开或切换到四人时：没看过入队就先播入队，否则本局闲聊一次
---@param heroId number|nil
function HeroScenario.onOpenHero(heroId)
    local hid = heroIdOf(heroId)
    if not JOIN_ID[hid] then return end
    print("[HeroScenario] open hero " .. tostring(hid))
    playJoinThenIdle(hid, drainPending)
end

return HeroScenario
