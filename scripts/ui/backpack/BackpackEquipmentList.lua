-- 私有仓库列表调度器。Render/指针只读已提交版本，整库工作仅由 Update 驱动。
local PlayerStore = require("core.PlayerStore")
local EquipmentPower = require("systems.EquipmentPower")
local M = {}

local function append(parts, value)
    local kind = type(value)
    if kind ~= "table" then
        local text = tostring(value)
        parts[#parts + 1] = kind .. #text .. ":" .. text
        return
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        return tostring(a) < tostring(b)
    end)
    parts[#parts + 1] = "{"
    for _, key in ipairs(keys) do append(parts, key); append(parts, value[key]) end
    parts[#parts + 1] = "}"
end

-- 不删除 heroes revision：显式同步查询仍按通知失效。预算列表只剔除评分从不消费的经验/货币。
-- 签名冻结值而非名册引用，原地patch（含无通知）也能发现等级/转职/觉醒/成长/编队改变。
local function heroSignature(heroes)
    local parts = {}
    heroes = heroes or {}
    for team = 1, 3 do
        local row = heroes.teams and (heroes.teams[team] or heroes.teams[tostring(team)])
        local slots = heroes.teams and (row and row.slots or {}) or (team == 1 and heroes.deployed or {}) or {}
        for slot = 1, 4 do
            local id = slots[slot] or slots[tostring(slot)]
            if type(id) == "table" then id = id.heroId end
            append(parts, tonumber(id))
        end
    end
    local ids = {}
    for id in pairs(heroes.roster or {}) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        return tostring(a) < tostring(b)
    end)
    for _, id in ipairs(ids) do
        local hero = heroes.roster[id]
        append(parts, id)
        for _, field in ipairs({ "level", "advBranch", "awakening", "extraTalent" }) do
            append(parts, hero[field])
        end
    end
    return table.concat(parts, "|")
end

function M.bind(deps)
    local empty, committed, syncList, presented = {}, {}, {}, {}
    local committedKey, syncKey, presentedKey = nil, nil, nil
    local job, jobKey = nil, nil
    local deadline, steps = 0, 0
    -- 一次不可抢占的装备评分/种子构建/排序可能超过预算；这是协作式软预算。
    local budget, maxSteps = deps.budgetSeconds or 0.001, deps.maxSteps or 64
    local api = {}
    local function capture()
        local request = deps.capture()
        local heroes = PlayerStore.Get("heroes")
        local heroRevision = PlayerStore.GetRevision and PlayerStore.GetRevision("heroes")
        -- ExtraTalent 本地镜像可原地patch且不发Store通知；小名册语义每次采样，
        -- revision/identity保留给显式同步契约，不能拿它们代替真实输入值。
        local observedSignature = heroSignature(heroes)
        request.heroes = heroes
        request.equipment = PlayerStore.Get("equipment")
        request.artifacts = PlayerStore.Get("artifacts")
        request.talents = PlayerStore.Get("talents")
        local parts = { request.filterKey, observedSignature }
        for _, key in ipairs({ "equipment", "artifacts", "talents" }) do
            parts[#parts + 1] = tostring(request[key])
            parts[#parts + 1] = tostring(PlayerStore.GetRevision and PlayerStore.GetRevision(key) or 0)
        end
        -- ClearCache/换玩家会替换三根模块引用；即使同名同等级也不复用前玩家列表。
        request.key = table.concat(parts, "|")
        request.syncKey = request.key .. "|" .. tostring(heroes) .. "|" .. tostring(heroRevision)
        return request
    end
    local function checkpoint()
        steps = steps + 1
        if steps >= maxSteps or os.clock() >= deadline then coroutine.yield() end
    end
    local function publish(request, list)
        committed, committedKey = list, request.key
    end

    -- 显式同步查询保留原契约；绝不被 draw/hover/click 调用，不向它传 checkpoint。
    function api.getEquipList()
        local request = capture()
        if PlayerStore.GetRevision and syncKey == request.syncKey then return syncList end
        local list = deps.build(request)
        syncList, syncKey = list, request.syncKey
        -- 同步查询的完整结果也可直接使用，但绝不替换/驱动在途私有协程。
        publish(request, list)
        return list
    end
    function api.getCommittedList()
        local request = capture()
        if committedKey == request.key then return committed end
        return empty -- 新筛选/装备版本不可点击上个版本的残影。
    end
    function api.present()
        presented = api.getCommittedList()
        presentedKey = committedKey
        return presented
    end
    function api.getPresentedList()
        if presentedKey == capture().key then return presented end
        return empty
    end
    function api.cancel()
        job, jobKey = nil, nil
        committed, committedKey, syncList, syncKey = {}, nil, {}, nil
        presented, presentedKey = {}, nil
    end
    function api.update()
        local started = os.clock()
        local request = capture()
        if committedKey == request.key then job, jobKey = nil, nil; return end
        if not job or jobKey ~= request.key then
            jobKey = request.key
            job = coroutine.create(function()
                -- 不使用全局 badge/getContext cache：经验通知的 invalidate generation
                -- 与同步评分不能取消/替换本列表的完整私有上下文。
                request.context = request.heroId ~= nil and EquipmentPower.buildContext(request.heroId, {
                    heroes = request.heroes, equipment = request.equipment,
                    artifacts = request.artifacts, talents = request.talents, checkpoint = checkpoint,
                    cacheFixedTeammates = true,
                }) or nil
                return deps.build(request, checkpoint)
            end)
        end
        local currentJob, currentKey = job, jobKey
        steps, deadline = 0, started + budget
        local ok, list = coroutine.resume(currentJob)
        if not ok then
            job, jobKey = nil, nil
            print("[BackpackEquipmentList] prepare failed: " .. tostring(list))
        elseif coroutine.status(currentJob) == "dead" then
            job, jobKey = nil, nil
            if currentKey == capture().key then publish(request, list) end
        end
    end
    return api
end
return M
