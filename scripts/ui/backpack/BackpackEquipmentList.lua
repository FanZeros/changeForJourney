-- 私有仓库列表调度器。结构列表先就绪，角色评分后台完成；Render不驱动评分。
local PlayerStore = require("core.PlayerStore")
local EquipmentPower = require("systems.EquipmentPower")
local M = {}

local function sameValue(a, b)
    if type(a) ~= "table" then return a == b end
    if type(b) ~= "table" then return false end
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

-- 每次读取都比较消费值：不能用 heroes 引用/revision/帧号跳过无通知 patch。
-- 比较时不复制、不串化；只对实际变化的行冻结，持续成长不再深拷贝全名册。
local function observeHeroes(heroes, snapshot)
    local changed = false
    for team = 1, 3 do
        for slot = 1, 4 do
            local index, id = (team - 1) * 4 + slot, slotId(heroes, team, slot)
            if id ~= snapshot.slots[index] then
                snapshot.slots[index], changed = id, true
            end
        end
    end
    local roster = heroes.roster or {}
    for id, hero in pairs(roster) do
        local old = snapshot.roster[id]
        if not old then old = {}; snapshot.roster[id] = old; changed = true end
        if hero.level ~= old.level then old.level, changed = hero.level, true end
        if not sameValue(hero.advBranch, old.advBranch) then
            old.advBranch, changed = copyValue(hero.advBranch), true
        end
        if not sameValue(hero.awakening, old.awakening) then
            old.awakening, changed = copyValue(hero.awakening), true
        end
        if not sameValue(hero.extraTalent, old.extraTalent) then
            old.extraTalent, changed = copyValue(hero.extraTalent), true
        end
    end
    for id in pairs(snapshot.roster) do
        if roster[id] == nil then snapshot.roster[id], changed = nil, true end
    end
    return changed
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
    local heroSnapshot = { slots = {}, roster = {} }
    local heroVersion = 0
    local function heroKey(heroes)
        if observeHeroes(heroes or {}, heroSnapshot) then heroVersion = heroVersion + 1 end
        return heroVersion
    end
    ---@type table|nil
    local lastRequest = nil
    local function revision(key)
        return PlayerStore.GetRevision and PlayerStore.GetRevision(key) or 0
    end
    local function capture(synchronous)
        local filters = deps.capture()
        local equipment, equipRevision = PlayerStore.Get("equipment"), revision("equipment")
        local heroes, artifacts, talents, version = nil, nil, nil, nil
        local artifactRevision, talentRevision = 0, 0
        if filters.heroId ~= nil then
            heroes = PlayerStore.Get("heroes")
            version = heroKey(heroes) -- 每次比较实际字段，包括同帧原地嵌套增删。
            artifacts, talents = PlayerStore.Get("artifacts"), PlayerStore.Get("talents")
            artifactRevision, talentRevision = revision("artifacts"), revision("talents")
        end
        local previous = lastRequest
        local structureSame = previous and previous.filterKey == filters.filterKey
            and previous.equipment == equipment and previous.equipRevision == equipRevision
        local request = previous
        if not structureSame or previous.heroes ~= heroes or previous.heroVersion ~= version
            or previous.artifacts ~= artifacts or previous.talents ~= talents
            or previous.artifactRevision ~= artifactRevision or previous.talentRevision ~= talentRevision then
            request = {}
            for key, value in pairs(filters) do request[key] = value end
            request.equipment, request.equipRevision = equipment, equipRevision
            request.heroes, request.heroVersion = heroes, version
            request.artifacts, request.talents = artifacts, talents
            request.artifactRevision, request.talentRevision = artifactRevision, talentRevision
            -- 只在依赖确实改变时生成key/请求外壳，不按帧缓存任何值检查。
            request.key = structureSame and previous.key or table.concat({ filters.filterKey,
                tostring(equipment), tostring(equipRevision) }, "|")
            request.scoreKey = request.key
            if filters.heroId ~= nil then
                request.scoreKey = table.concat({ request.key, tostring(version), tostring(artifacts),
                    tostring(artifactRevision), tostring(talents), tostring(talentRevision) }, "|")
            end
            lastRequest = request
        end
        if synchronous then
            -- 显式同步契约追踪全部源；manual的Update/Render/指针不读战斗模块。
            local sync = {}
            for key, value in pairs(request) do sync[key] = value end
            local parts = { request.scoreKey }
            for _, key in ipairs({ "heroes", "artifacts", "talents" }) do
                parts[#parts + 1] = tostring(PlayerStore.Get(key))
                parts[#parts + 1] = tostring(revision(key))
            end
            parts[#parts + 1] = tostring(heroKey(PlayerStore.Get("heroes")))
            sync.syncKey = table.concat(parts, "|")
            return sync
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
            local jobRequest = {}
            for key, value in pairs(request) do jobRequest[key] = value end
            job = coroutine.create(function()
                -- context 仅写任务外壳，不能污染Render复用的只读依赖请求。
                jobRequest.context = EquipmentPower.buildContext(jobRequest.heroId, {
                    heroes = jobRequest.heroes, equipment = jobRequest.equipment,
                    artifacts = jobRequest.artifacts, talents = jobRequest.talents, checkpoint = checkpoint,
                    cacheFixedTeammates = true,
                })
                return deps.build(jobRequest, checkpoint)
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
