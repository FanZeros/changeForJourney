-- ============================================================================
-- HeroScenario.lua — 四人玩梗角色的入队 / 闲聊情景
-- 入队与闲聊均只播一次（都写入 session.claimedScenarios 落档）。
-- 2026-09-30 方案A+C：闲聊不再用"每进程一次"的内存标记（重启必弹 → 玩家
-- 体感"点详情一直显示剧情"），改为与入队一致地 markClaimed 落档；
-- 同时订阅 ScenarioDialogue 的结束广播消化 pending_ 队列，消除"延迟到
-- 下次点击才突然补播"的坏体感。
-- ============================================================================

local ScenarioDialogueConfig = require("config.ScenarioDialogueConfig")
local ScenarioDialogue = require("ui.story.ScenarioDialogue")
local ClientDispatcher = require("runtime.ClientDispatcher")
local EventBus = require("core.EventBus")

local HeroScenario = {}

local JOIN_ID = { [18] = 74, [19] = 75, [24] = 76, [25] = 77 }
local IDLE_ID = { [18] = 78, [19] = 79, [24] = 80, [25] = 81 }

-- 兼容层：旧版本把闲聊标记只存内存（idleSeen_），重启必弹。
-- 现已统一改为写 session.claimedScenarios 落档，此内存表仅保留给
-- "落档失败"的极端情况做进程内去重，避免同一次运行里反复弹。
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
    -- 同步状态更新可能重入 UI 刷新；异常不得中断打开/播放流程
    local okApply, errApply = pcall(function()
        ClientDispatcher.handleStateUpdate(cjson.encode({ modules = { session = updated } }))
    end)
    if not okApply then
        print("[HeroScenario] markClaimed state update failed: " .. tostring(errApply))
    end
    -- 入队只该播一次：立刻落档，避免播放中途退出后重启重播
    local okSave, StandaloneSave = pcall(require, "boot.StandaloneSave")
    if okSave and StandaloneSave and StandaloneSave.Flush then
        local okFlush, errFlush = pcall(StandaloneSave.Flush)
        if not okFlush then
            print("[HeroScenario] save flush failed: " .. tostring(errFlush))
        end
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
    -- 方案A：闲聊与入队一致，看 claimedScenarios 落档记录（终身一次），
    -- idleSeen_ 仅作为落档失败时的进程内兜底去重
    if not idleId or isClaimed(idleId) or idleSeen_[heroId] then
        if onFinish then onFinish() end
        return
    end
    local shown = showScenario(idleId, function()
        if onFinish then onFinish() end
    end)
    if shown then
        idleSeen_[heroId] = true
        markClaimed(idleId)
    else
        -- 没播出来（配置缺失或已有对话在播），不标记已看，交给排队重试
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
--- 防卡死：showScenario 持续失败（配置缺失等）时 enqueue→drain 会无限递归爆栈，
--- 用重试计数封顶，超限直接丢弃该请求
--- ⚠️ 必须赋值给前向声明的 local（drainPending = function），
--- 不能写 local function drainPending()——那会重新声明新 local 遮蔽前向声明，
--- 使 playIdle/playJoinThenIdle 捕获的 upvalue 永远为 nil，busy 兜底路径崩溃
--- （回归测试 hero_scenario_claim_test 用例7 抓到）。
local drainDepth_ = 0
local DRAIN_MAX_DEPTH = 8
drainPending = function()
    if ScenarioDialogue.isActive() or #pending_ == 0 then return end
    if drainDepth_ >= DRAIN_MAX_DEPTH then
        print("[HeroScenario] drain depth cap reached, drop " .. tostring(pending_[1]))
        table.remove(pending_, 1)
        return
    end
    drainDepth_ = drainDepth_ + 1
    local heroId = table.remove(pending_, 1)
    playJoinThenIdle(heroId, function()
        drainDepth_ = 0
        drainPending()
    end)
    drainDepth_ = drainDepth_ - 1
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

---@param heroId integer
---@return boolean
local function ownsHero(heroId)
    local heroes = ClientDispatcher.get("heroes") or {}
    local roster = heroes.roster or {}
    local owned = roster[heroId] or roster[tostring(heroId)]
    return type(owned) == "table" and owned.level ~= nil
end

--- 打开或切换到四人时：没获得不播；已获得且没看过入队就先播入队，否则播一次落档闲聊
---@param heroId number|nil
function HeroScenario.onOpenHero(heroId)
    local hid = heroIdOf(heroId)
    if not JOIN_ID[hid] then return end
    if not ownsHero(hid) then
        print("[HeroScenario] skip unowned hero " .. tostring(hid))
        return
    end
    print("[HeroScenario] open hero " .. tostring(hid))
    playJoinThenIdle(hid, drainPending)
end

-- 方案C：任意情景对话（含 StoryPlayer 的城镇/关卡剧情）自然结束时，
-- 立即消化 pending_ 积压，不再等玩家下一次点击详情才突然补播。
-- 订阅在模块首次 require 时注册一次（module 级 local，天然去重）。
EventBus.on("scenario_dialogue_finished", function()
    drainPending()
end)

return HeroScenario
