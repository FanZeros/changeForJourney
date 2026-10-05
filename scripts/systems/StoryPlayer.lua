-- ============================================================================
-- StoryPlayer.lua — 后续情景排队与触发
-- 开场链不走这里。这里负责首通、进关、进建筑、离建筑、首次团灭。
-- 已领取（session.claimedScenarios）的情景不会再入队。
-- ============================================================================

local ClientDispatcher = require("runtime.ClientDispatcher")
local ScenarioDialogueConfig = require("config.ScenarioDialogueConfig")

local StoryPlayer = {}

---@type number[]
local queue_ = {}
---@type table<number, string>
local queuedBackgrounds_ = {}
local wipeReserved_ = false
local wipePending_ = false
---@type number|string|nil
local pendingWipeStage_ = nil

local PLACE = {
    town = { enter = 23 },
    church = { enter = 27, leave = { [1] = 28, [2] = 29, [3] = 30 } },
    tavern = { enter = 31, leave = { [1] = 32, [2] = 33, [3] = 34 } },
    smith = { enter = 47, leave = { [1] = 48, [2] = 49, [3] = 50 } },
}

-- 进关才播（不是首通）
local STAGE_ENTER = {
    [204] = { [1] = 41, [2] = 42, [3] = 43 },
    [999] = 61,
    [1999] = 68,
    [2401] = 63,
    [2505] = 64,
    [2705] = 65,
    [2905] = 67,
    [4701] = 70,
    [4705] = 71,
    [4805] = 72,
    [4905] = 73,
}

-- 首通后播。11/12/13 在三人已入队时跳过。
local STAGE_CLEAR = {
    [101] = { [1] = 5, [2] = 6, [3] = 7 },
    [102] = { [1] = 8, [2] = 9, [3] = 10 },
    [103] = { [1] = 11, [2] = 12, [3] = 13 },
    [104] = { [1] = 17, [2] = 18, [3] = 19 },
    [105] = { [1] = 20, [2] = 21, [3] = 22 },
    [201] = { [1] = 35, [2] = 36, [3] = 37 },
    [204] = { [1] = 44, [2] = 45, [3] = 46 },
    -- 205（第二章收尾）：原有角色分支情景之后追加 82（大狗嚼潜能引导，全角色通用）
    [205] = { [1] = 51, [2] = 52, [3] = 53, extra = { 82 } },
    [305] = { [1] = 58, [2] = 59, [3] = 60 },
    [999] = 62,
    [1305] = { [1] = 55, [2] = 56, [3] = 57 },
    [1999] = 69,
}

local WIPE = { [1] = 38, [2] = 39, [3] = 40 }

local FOLLOW = {
    [23] = { [1] = 24, [2] = 25, [3] = 26 },
}

---@return table
local function session()
    return ClientDispatcher.get("session") or {}
end

---@return integer
local function heroId()
    local id = tonumber(session().initialHeroId) or 1
    return math.floor(id)
end

---@param id number
---@return boolean
local function isClaimed(id)
    local data = session()
    -- 82带实体碎片奖励：有发奖台账时，起播预标记不能代替真正领取。
    -- 无台账的更早旧档仍尊重原claimed记录，避免已花掉碎片后重复补发。
    if id == 82 and type(data.scenarioRewardsGranted) == "table" then
        local granted = data.scenarioRewardsGranted
        return granted[tostring(id)] == true or granted[id] == true
    end
    local claimed = data.claimedScenarios
    if type(claimed) ~= "table" then return false end
    return claimed[tostring(id)] == true or claimed[id] == true
end

---@param spec number|table|nil
---@return number|nil
local function resolve(spec)
    if type(spec) == "number" then return spec end
    if type(spec) ~= "table" then return nil end
    local id = spec[heroId()] or spec[1]
    if type(id) ~= "number" then return nil end
    return id
end

---@param id number
---@return boolean
function StoryPlayer.enqueue(id)
    if session().introCompleted ~= true then
        print("[StoryPlayer] skip enqueue " .. tostring(id) .. " intro not done")
        return false
    end
    if isClaimed(id) then return false end
    for i = 1, #queue_ do
        if queue_[i] == id then return false end
    end
    queue_[#queue_ + 1] = id
    print("[StoryPlayer] enqueue scenario " .. tostring(id) .. " queue=" .. #queue_)
    return true
end

---@param spec number|table|nil
local function enqueueSpec(spec)
    -- 全角色通用的追加情景（spec.extra = { id, ... }），与角色分支情景一起排队
    if type(spec) == "table" and type(spec.extra) == "table" then
        for _, extraId in ipairs(spec.extra) do
            StoryPlayer.enqueue(extraId)
        end
    end
    local id = resolve(spec)
    if not id then return end
    if id == 11 or id == 12 or id == 13 then
        local heroes = ClientDispatcher.get("heroes") or {}
        local roster = heroes.roster or {}
        local starterCount = 0
        for _, heroId in ipairs({ 1, 2, 3 }) do
            local hero = roster[heroId] or roster[tostring(heroId)]
            if type(hero) == "table" and hero.level then
                starterCount = starterCount + 1
            end
        end
        if session().starterTrioReady == true or isClaimed(id) or starterCount >= 3 then
            print("[StoryPlayer] skip recruit scenario " .. tostring(id)
                .. " starters=" .. tostring(starterCount))
            return
        end
    end
    StoryPlayer.enqueue(id)
end

---@param place string
---@param phase string "enter"|"leave"
function StoryPlayer.onPlace(place, phase)
    local def = PLACE[place]
    if not def then return end
    enqueueSpec(def[phase])
end

---@param stageId number|string
---@param phase string "enter"|"clear"
function StoryPlayer.onStage(stageId, phase)
    local id = tonumber(stageId)
    if not id then return end
    local spec = (phase == "clear" and STAGE_CLEAR or STAGE_ENTER)[math.floor(id)]
    if spec then
        print("[StoryPlayer] stage " .. tostring(id) .. " " .. phase
            .. " hero=" .. tostring(heroId()))
    end
    enqueueSpec(spec)
end

---@param stageId number|string|nil 失败瞬间的战场，延迟播放后仍使用原地点。
function StoryPlayer.onWipe(stageId)
    -- 三个英雄分支属于同一次首次全灭；take 后到领取前仍保留运行态预留。
    for _, scenarioId in pairs(WIPE) do
        if isClaimed(scenarioId) then
            wipePending_ = false
            pendingWipeStage_ = nil
            return false
        end
    end
    if wipeReserved_ then return false end
    if session().introCompleted ~= true then
        if not wipePending_ then pendingWipeStage_ = stageId end
        wipePending_ = true
        return false
    end
    local originalStage = wipePending_ and pendingWipeStage_ or stageId
    local id = resolve(WIPE)
    if not id or not StoryPlayer.enqueue(id) then return false end
    wipeReserved_ = true
    wipePending_ = false
    pendingWipeStage_ = nil
    queuedBackgrounds_[id] = require("config.StoryBackgroundConfig").forStage(originalStage)
    print("[StoryPlayer] first wipe reserved scenario=" .. tostring(id))
    return true
end

function StoryPlayer.resetWipe()
    wipeReserved_ = false
    wipePending_ = false
    pendingWipeStage_ = nil
    for i = #queue_, 1, -1 do
        local id = queue_[i]
        if id == 38 or id == 39 or id == 40 then
            table.remove(queue_, i)
            queuedBackgrounds_[id] = nil
        end
    end
end

--- 清档只清运行态，不改持久领取及情景82发奖账本。
function StoryPlayer.resetAll()
    queue_ = {}
    queuedBackgrounds_ = {}
    StoryPlayer.resetWipe()
end

--- 当前情景播完后要接的下一句（如城镇 23 → 24）
---@param id number
---@return number|nil
function StoryPlayer.followOf(id)
    return resolve(FOLLOW[id])
end

--- [旧档补播 2026-09-30] 0922 联网壳删除后"首通触发情景"接线断裂，
--- 期间已首通关卡的老玩家（如已通 205 却从未见过情景 82）永远不会再触发。
--- 启动时扫描 battle.clearedStages，把已首通但未领取（claimedScenarios 无记录）
--- 的情景按关卡顺序补入队；enqueue 内部自带 introCompleted/isClaimed/去重守卫。
---@return integer 新入队数量
function StoryPlayer.backfillCleared()
    local battle = ClientDispatcher.get("battle") or {}
    local cleared = battle.clearedStages
    if type(cleared) ~= "table" then return 0 end
    local ids = {}
    for k, value in pairs(cleared) do
        local n = tonumber(k)
        if value == true and n then ids[#ids + 1] = math.floor(n) end
    end
    table.sort(ids)
    local added = 0
    for _, id in ipairs(ids) do
        local spec = STAGE_CLEAR[id]
        if spec then
            local before = #queue_
            enqueueSpec(spec)
            added = added + (#queue_ - before)
        end
    end
    if added > 0 then
        print("[StoryPlayer] backfill cleared stages enqueued=" .. added)
    end
    return added
end

--- 取出下一段可播放情景。没有则返回 nil。
---@return table|nil
function StoryPlayer.take()
    if wipePending_ then StoryPlayer.onWipe(pendingWipeStage_) end
    while #queue_ > 0 do
        local id = table.remove(queue_, 1)
        local background = id and queuedBackgrounds_[id]
        if id then queuedBackgrounds_[id] = nil end
        if id and not isClaimed(id) then
            local cfg = ScenarioDialogueConfig["SCENARIO_" .. tostring(id)]
            if cfg and cfg.steps and #cfg.steps > 0 then
                if background then
                    local visual = {}
                    for key, value in pairs(cfg) do visual[key] = value end
                    visual.background = background
                    cfg = visual
                end
                print("[StoryPlayer] take scenario " .. tostring(id)
                    .. " steps=" .. #cfg.steps .. " mode=" .. tostring(cfg.mode))
                return { scenarioId = id, config = cfg }
            end
            print("[StoryPlayer] missing steps for scenario " .. tostring(id))
        end
    end
    return nil
end

return StoryPlayer
