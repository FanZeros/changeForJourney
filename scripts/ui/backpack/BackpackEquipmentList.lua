-- 私有仓库列表调度器。结构列表先就绪，角色评分后台完成；Render不驱动评分。
local PlayerStore = require("core.PlayerStore")
local EquipmentPower = require("systems.EquipmentPower")
local M = {}

local combatFields = { "level", "advBranch", "awakening", "extraTalent" }
local function sameValue(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not sameValue(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function copyValue(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copyValue(child) end
    return result
end
local function slotId(heroes, team, slot)
    local row = heroes.teams and (heroes.teams[team] or heroes.teams[tostring(team)])
    local slots = heroes.teams and (row and row.slots or {}) or (team == 1 and heroes.deployed or {}) or {}
    local id = slots[slot] or slots[tostring(slot)]
    if type(id) == "table" then id = id.heroId end
    return tonumber(id)
end

-- 冻结消费值，不按 heroes 引用/revision 跳过检查：无通知原地成长也必须同帧拒旧。
-- 相等时只比较，不再为每次 Render/指针读取排序、递归串化整个名册。
local function sameHeroes(heroes, snapshot)
    if not snapshot then return false end
    for team = 1, 3 do
        for slot = 1, 4 do
            if slotId(heroes, team, slot) ~= snapshot.slots[(team - 1) * 4 + slot] then return false end
        end
    end
    local count = 0
    for id, hero in pairs(heroes.roster or {}) do
        count = count + 1
        local old = snapshot.roster[id]
        if not old then return false end
        for _, field in ipairs(combatFields) do
            if not sameValue(hero[field], old[field]) then return false end
        end
    end
    return count == snapshot.count
end
local function freezeHeroes(heroes)
    local snapshot = { slots = {}, roster = {}, count = 0 }
    for team = 1, 3 do
        for slot = 1, 4 do snapshot.slots[(team - 1) * 4 + slot] = slotId(heroes, team, slot) end
    end
    for id, hero in pairs(heroes.roster or {}) do
        local row = {}
        for _, field in ipairs(combatFields) do row[field] = copyValue(hero[field]) end
        snapshot.roster[id] = row
        snapshot.count = snapshot.count + 1
    end
    return snapshot
end

function M.bind(deps)
    local empty, basic, committed, syncList, presented = {}, {}, {}, {}, {}
    local basicKey, committedKey, syncKey, presentedKey = nil, nil, nil, nil
    local presentedScoreKey = nil
    ---@type table|nil
    local closingList = nil
    local job, jobKey = nil, nil
    local deadline, steps = 0, 0
    -- 一次不可抢占的装备评分/种子构建/排序可能超过预算；这是协作式软预算。
    local budget, maxSteps = deps.budgetSeconds or 0.001, deps.maxSteps or 64
    local api = {}
    ---@type table|nil
    local heroSnapshot = nil
    local heroVersion = 0
    local function heroKey(heroes)
        heroes = heroes or {}
        if not sameHeroes(heroes, heroSnapshot) then
            heroSnapshot = freezeHeroes(heroes)
            heroVersion = heroVersion + 1
        end
        return tostring(heroVersion)
    end
    local function capture(synchronous)
        -- capture 可复用不可变筛选快照；任务的 context/版本只写自己的请求外壳。
        local request = {}
        for key, value in pairs(deps.capture()) do request[key] = value end
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
            parts[#parts + 1] = heroKey(heroes)
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
            syncParts[#syncParts + 1] = heroKey(PlayerStore.Get("heroes"))
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
    local function committedFor(request)
        if committedKey == request.scoreKey then return committed end
        if basicKey == request.key then basic = view(basic, request, request.heroId ~= nil); return basic end
        return empty -- 新筛选/装备版本不可点击上个版本的残影。
    end
    function api.getCommittedList()
        return committedFor(capture())
    end
    function api.present()
        if closingList then return closingList end
        local request = capture()
        presented = committedFor(request)
        presentedKey = request.key
        presentedScoreKey = committedKey == request.scoreKey and request.scoreKey or nil
        return presented
    end
    function api.getPresentedList()
        if closingList then return empty end
        local request = capture()
        if presentedKey ~= request.key then return empty end
        -- basic→scored 的新排序必须等 Render 呈现；指针仍读上次实际画出的顺序。
        if request.heroId ~= nil and presentedScoreKey ~= request.scoreKey then
            presented = view(presented, request, true)
        end
        return presented
    end
    function api.freezeForClose()
        -- 只保留最后实际呈现的只读列表用于退场，不再评分，也不允许它参与指针命中。
        if not closingList then closingList = presented end
        job, jobKey = nil, nil
        presentedKey, presentedScoreKey = nil, nil
    end
    function api.cancel()
        closingList = nil
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
