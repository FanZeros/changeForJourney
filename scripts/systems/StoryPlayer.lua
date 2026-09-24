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
    [205] = { [1] = 51, [2] = 52, [3] = 53 },
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
    local claimed = session().claimedScenarios
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
    local id = resolve(spec)
    if not id then return end
    if (id == 11 or id == 12 or id == 13) and session().starterTrioReady then
        print("[StoryPlayer] skip recruit scenario " .. tostring(id))
        return
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

function StoryPlayer.onWipe()
    print("[StoryPlayer] wipe hero=" .. tostring(heroId()))
    enqueueSpec(WIPE)
end

--- 当前情景播完后要接的下一句（如城镇 23 → 24）
---@param id number
---@return number|nil
function StoryPlayer.followOf(id)
    return resolve(FOLLOW[id])
end

--- 取出下一段可播放情景。没有则返回 nil。
---@return table|nil
function StoryPlayer.take()
    while #queue_ > 0 do
        local id = table.remove(queue_, 1)
        if id and not isClaimed(id) then
            local cfg = ScenarioDialogueConfig["SCENARIO_" .. tostring(id)]
            if cfg and cfg.steps and #cfg.steps > 0 then
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
