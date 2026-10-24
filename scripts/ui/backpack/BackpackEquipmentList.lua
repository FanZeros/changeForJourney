-- 私有仓库列表调度器。结构列表先就绪，角色评分后台完成；Render不驱动评分。
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

-- 签名冻结值而非名册引用，原地patch（含无通知）也能发现真实成长。
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
    local empty, basic, committed, syncList, presented = {}, {}, {}, {}, {}
    local basicKey, committedKey, syncKey, presentedKey = nil, nil, nil, nil
    local presentedScoreKey = nil
    local job, jobKey = nil, nil
    local deadline, steps = 0, 0
    -- 一次不可抢占的装备评分/种子构建/排序可能超过预算；这是协作式软预算。
    local budget, maxSteps = deps.budgetSeconds or 0.001, deps.maxSteps or 64
    local api = {}
    local function capture(synchronous)
        local request = deps.capture()
        request.equipment = PlayerStore.Get("equipment")
        local parts = { request.filterKey, tostring(request.equipment),
            tostring(PlayerStore.GetRevision and PlayerStore.GetRevision("equipment") or 0) }
        -- 结构只依赖筛选/装备；战斗成长不能让真实库存从界面消失。
        request.key = table.concat(parts, "|")
        request.scoreKey, request.syncKey = request.key, request.key
        if request.heroId ~= nil then
            local heroes = PlayerStore.Get("heroes")
            request.heroes = heroes
            request.artifacts = PlayerStore.Get("artifacts")
            request.talents = PlayerStore.Get("talents")
            parts[#parts + 1] = heroSignature(heroes)
            for _, key in ipairs({ "artifacts", "talents" }) do
                parts[#parts + 1] = tostring(request[key])
                parts[#parts + 1] = tostring(PlayerStore.GetRevision and PlayerStore.GetRevision(key) or 0)
            end
            request.scoreKey = table.concat(parts, "|")
            request.syncKey = request.scoreKey .. "|" .. tostring(heroes) .. "|"
                .. tostring(PlayerStore.GetRevision and PlayerStore.GetRevision("heroes") or 0)
        end
        if synchronous then
            -- 仅显式同步契约追踪全部源；manual的Update/Render/指针不读这些模块。
            local syncParts = { request.syncKey }
            for _, key in ipairs({ "heroes", "artifacts", "talents" }) do
                local source = PlayerStore.Get(key)
                syncParts[#syncParts + 1] = tostring(source)
                syncParts[#syncParts + 1] = tostring(PlayerStore.GetRevision and PlayerStore.GetRevision(key) or 0)
            end
            syncParts[#syncParts + 1] = heroSignature(PlayerStore.Get("heroes"))
            request.syncKey = table.concat(syncParts, "|")
        end
        return request
    end
    local function checkpoint()
        steps = steps + 1
        if steps >= maxSteps or os.clock() >= deadline then coroutine.yield() end
    end
    local function publish(request, list)
        committed, committedKey = list, request.scoreKey
    end
    local function view(list, request, pending)
        return deps.refresh and deps.refresh(list, request, pending) or list
    end

    -- 显式同步查询保留原契约；绝不被 draw/hover/click 调用。
    function api.getEquipList()
        local request = capture(true)
        if PlayerStore.GetRevision and syncKey == request.syncKey then return syncList end
        local list = deps.build(request)
        syncList, syncKey = list, request.syncKey
        publish(request, list)
        return list
    end
    function api.getCommittedList()
        local request = capture()
        if committedKey == request.scoreKey then return committed end
        if basicKey == request.key then basic = view(basic, request, request.heroId ~= nil); return basic end
        return empty -- 新筛选/装备版本不可点击上个版本的残影。
    end
    function api.present()
        local request = capture()
        presented = api.getCommittedList()
        presentedKey = request.key
        presentedScoreKey = committedKey == request.scoreKey and request.scoreKey or nil
        return presented
    end
    function api.getPresentedList()
        local request = capture()
        if presentedKey ~= request.key then return empty end
        -- basic→scored 的新排序必须等 Render 呈现；指针仍读上次实际画出的顺序。
        if request.heroId ~= nil and presentedScoreKey ~= request.scoreKey then
            presented = view(presented, request, true)
        end
        return presented
    end
    function api.cancel()
        job, jobKey = nil, nil
        basic, basicKey, committed, committedKey, syncList, syncKey = {}, nil, {}, nil, {}, nil
        presented, presentedKey, presentedScoreKey = {}, nil, nil
    end
    function api.update()
        local started = os.clock()
        local request = capture()
        if basicKey ~= request.key then
            -- 完整廉价列表一次提交，不等待复制全库/角色预览；没有半成品或假角色评分。
            basic, basicKey = deps.buildBasic(request), request.key
        end
        basic = view(basic, request, request.heroId ~= nil)
        if request.heroId == nil then
            publish(request, basic)
            job, jobKey = nil, nil
            return
        end
        if committedKey == request.scoreKey then job, jobKey = nil, nil; return end
        if not job or jobKey ~= request.scoreKey then
            jobKey = request.scoreKey
            job = coroutine.create(function()
                -- 私有快照只在对应战斗版本有效；取消评分不取消基础列表。
                request.context = EquipmentPower.buildContext(request.heroId, {
                    heroes = request.heroes, equipment = request.equipment,
                    artifacts = request.artifacts, talents = request.talents, checkpoint = checkpoint,
                    cacheFixedTeammates = true,
                })
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
            if currentKey == capture().scoreKey then publish(request, list) end
        end
    end
    return api
end
return M
