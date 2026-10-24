-- 手动预览/确认整理。服务只信PDM快照和本模块token，不接受客户端移动名单。
local PDM = require("rules.character.PlayerDataManager")
local Rules = require("systems.InventoryCuration")
local Blacksmith = require("rules.blacksmith.BlacksmithService")
local GameState = require("core.GameState")
local PlayerStore = require("core.PlayerStore")

local M = {}
local TOKEN_TTL = 120
local pending = {} ---@type table<string, table>
local busy = {}
local nextToken = 0
local persist = nil ---@type (fun(uid:number):boolean|nil)|nil
local persistHooks = {} ---@type table

--- 与副本事务相同的正式Flush接线；没有持久化入口时禁止确认。
---@param callback (fun(uid:number):boolean|nil)|nil
---@param hooks table|nil {begin=function(uid), finish=function(uid,success)}
function M.SetPersistCallback(callback, hooks)
    persist, persistHooks = callback, hooks or {}
    -- 运行时重绑持久化代表宿主生命周期改变，旧预览不得借用新宿主提交。
    pending = {}
end

--- 保存原table的边，而非序列化后重建；回滚恢复所有原子表和外部别名。
local function capture(value, records, seen)
    if type(value) ~= "table" or seen[value] then return end
    seen[value] = true
    local fields = {}
    records[#records + 1] = { target = value, fields = fields }
    for key, child in pairs(value) do
        fields[key] = child
        capture(child, records, seen)
    end
end

local function unchanged(records)
    for _, record in ipairs(records) do
        for key, value in pairs(record.fields) do
            if rawget(record.target, key) ~= value then return false end
        end
        for key in pairs(record.target) do
            if rawget(record.fields, key) == nil then return false end
        end
    end
    return true
end

local function restore(records)
    for _, record in ipairs(records) do
        for key in pairs(record.target) do record.target[key] = nil end
        for key, value in pairs(record.fields) do record.target[key] = value end
    end
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[key] = copy(child, seen) end
    return result
end

local function equal(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    seen = seen or {}
    if seen[a] then return seen[a] == b end
    seen[a] = b
    for key, value in pairs(a) do
        if not equal(value, b[key], seen) then return false end
    end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function readData(uid)
    local equipment, lootbox = PDM.GetModule(uid, "equipment"), PDM.GetModule(uid, "lootbox")
    if type(equipment) ~= "table" or type(lootbox) ~= "table" then return nil end
    return { equipment = equipment, lootbox = lootbox }
end

--- 待洗练内容从不暴露给UI；冻结全部现有/审计seq的存在性，确认再读。
local function pendingStatus(uid, data)
    local status = {}
    local function add(seq)
        local id = Rules.sequence(seq)
        if id and status[id] == nil then status[id] = Blacksmith.hasPendingRefine(uid, id) end
    end
    for key, equip in pairs(data.equipment.inventory or {}) do
        add(key)
        if type(equip) == "table" then add(equip.seq) end
    end
    for _, slots in pairs(data.equipment.equipped or {}) do
        if type(slots) == "table" then for _, seq in pairs(slots) do add(seq) end end
    end
    for _, seed in ipairs(data.lootbox.seeds or {}) do
        if type(seed) == "table" then
            add(seed.originalSeq)
            if type(seed.equip) == "table" then add(seed.equip.seq) end
        end
    end
    return status
end

local function revisions()
    -- 正式单机模块通知的单调凭据；只读服务端可访问源，绝不接受UI传入revision。
    return { equipment = PlayerStore.GetRevision("equipment"), lootbox = PlayerStore.GetRevision("lootbox") }
end

local function makePlan(uid, data)
    local called, plan, reason = pcall(Rules.plan, data.equipment, data.lootbox, {
        hasPendingRefine = function(seq) return Blacksmith.hasPendingRefine(uid, seq) end,
    })
    if not called then return nil, "整理数据异常，未移动任何装备" end
    return plan, reason
end

local function resultFor(plan, token)
    return {
        token = token, capacity = plan.capacity, changed = plan.changed,
        moveInCount = plan.moveInCount, moveOutCount = plan.moveOutCount,
        protectedCount = plan.protectedCount, counts = copy(plan.counts),
        protected = copy(plan.protected), reasons = copy(plan.reasons), groups = copy(plan.groups),
    }
end

---@param uid number
---@return boolean, string|nil, table|nil
function M.PreviewInventoryCuration(uid)
    local key = tostring(uid)
    if busy[key] then return false, "装备整理处理中" end
    pending[key] = nil
    local data = readData(uid)
    if not data then return false, "数据未加载" end
    local plan, reason = makePlan(uid, data)
    if not plan then return false, reason end
    local records = {}
    local seen = {}
    capture(data.equipment, records, seen)
    capture(data.lootbox, records, seen)
    nextToken = nextToken + 1
    local token = "curation:" .. key .. ":" .. tostring(nextToken)
    pending[key] = { token = token, createdAt = os.time(), data = data, records = records,
        plan = plan, status = pendingStatus(uid, data), revisions = revisions() }
    print("[InventoryCuration] preview uid=" .. key .. " in=" .. plan.moveInCount
        .. " out=" .. plan.moveOutCount .. " protected=" .. plan.protectedCount)
    return true, nil, resultFor(plan, token)
end

---@param uid number
---@param token string|nil
function M.CancelInventoryCuration(uid, token)
    local key = tostring(uid)
    if busy[key] then return false, "装备整理处理中" end
    local preview = pending[key]
    if token ~= nil and (not preview or token ~= preview.token) then return false, "整理预览已失效，请重新预览" end
    pending[key] = nil
    return true, nil, { token = token, cancelled = true }
end

--- 分配全新seq，不复活originalSeq；历史审计/穿戴/私有待洗练号永不被重挂。
local function allocate(uid, data, plan)
    local maximum = 0 ---@type number
    local invalid = false
    local function observe(seq)
        if seq == nil then return end
        local id = Rules.sequence(seq)
        if id then maximum = math.max(maximum, tonumber(id))
        else invalid = true end
    end
    for key, equip in pairs(data.equipment.inventory) do
        observe(key)
        if type(equip) == "table" then observe(equip.seq) end
    end
    for _, seed in ipairs(data.lootbox.seeds) do
        observe(seed.originalSeq)
        if type(seed.equip) == "table" then observe(seed.equip.seq) end
    end
    for _, slots in pairs(data.equipment.equipped or {}) do
        for _, seq in pairs(slots) do observe(seq) end
    end
    if invalid then return nil end
    local requested = data.equipment.nextSeq == nil and 1 or tonumber(data.equipment.nextSeq)
    if not requested or not Rules.sequence(requested) then return nil end
    local nextSeq = math.floor(math.max(requested, maximum + 1))
    local assigned = {}
    for _, move in ipairs(plan.moveIn) do
        local skipped = 0
        while Rules.sequence(nextSeq) and Blacksmith.hasPendingRefine(uid, nextSeq) do
            nextSeq = nextSeq + 1
            skipped = skipped + 1
            if skipped > 10000 then return nil end
        end
        if not Rules.sequence(nextSeq) or not Rules.sequence(nextSeq + 1) then return nil end
        assigned[move.index] = nextSeq
        nextSeq = nextSeq + 1
    end
    return assigned, nextSeq
end

local function applyLists(data, plan, assigned, nextSeq)
    local inventory, seeds = data.equipment.inventory, data.lootbox.seeds
    local newInventory, newSeeds, entering = {}, {}, {}
    for key, equip in pairs(inventory) do newInventory[key] = equip end
    for _, move in ipairs(plan.moveOut) do newInventory[move.key] = nil end
    for _, move in ipairs(plan.moveIn) do
        local seed = seeds[move.index]
        local seq = assigned[move.index]
        -- 唯一允许改动的原装备字段：入库实例序号；其他完整字段/嵌套引用原样保留。
        seed.equip.seq = seq
        newInventory[tostring(seq)] = seed.equip
        entering[move.index] = true
    end
    for index, seed in ipairs(seeds) do
        if not entering[index] then newSeeds[#newSeeds + 1] = seed end
    end
    for _, move in ipairs(plan.moveOut) do
        local equip = inventory[move.key]
        newSeeds[#newSeeds + 1] = { quality = equip.quality, level = equip.level, count = 1,
            equip = equip, source = "curation", originalSeq = move.seq }
    end
    -- 原inventory/seeds容器本身也保留；避免业务持有的别名在成功后悄悄看旧名单。
    for key in pairs(inventory) do inventory[key] = nil end
    for key, equip in pairs(newInventory) do inventory[key] = equip end
    for key in pairs(seeds) do seeds[key] = nil end
    for index, seed in ipairs(newSeeds) do seeds[index] = seed end
    data.equipment.nextSeq = nextSeq
end

---@param uid number
---@param token string
---@return boolean, string|nil, table|nil
function M.ApplyInventoryCuration(uid, token)
    local key = tostring(uid)
    if busy[key] then return false, "装备整理处理中" end
    local preview = pending[key]
    if type(token) ~= "string" or not preview or token ~= preview.token then
        return false, "整理预览已失效，请重新预览"
    end
    local data = readData(uid)
    local age = os.time() - preview.createdAt
    if not data or age < 0 or age > TOKEN_TTL or data.equipment ~= preview.data.equipment
        or data.lootbox ~= preview.data.lootbox or not unchanged(preview.records)
        or not equal(preview.revisions, revisions())
        or not equal(preview.status, pendingStatus(uid, data)) then
        pending[key] = nil
        return false, "整理预览已失效，请重新预览"
    end
    local plan, reason = makePlan(uid, data)
    if not plan then pending[key] = nil; return false, reason end
    if not equal(preview.plan, plan) then
        pending[key] = nil
        return false, "整理预览已失效，请重新预览"
    end
    if not plan.changed then
        pending[key] = nil
        return true, nil, resultFor(plan, token)
    end
    if type(persist) ~= "function" then return false, "整理持久化未接线" end
    local assigned, nextSeq = allocate(uid, data, plan)
    if not assigned then return false, "装备序列号异常，未移动任何装备" end
    local records, seen = {}, {}
    capture(PDM.GetAllModules(uid), records, seen)
    local stateBefore = GameState.exportSave()
    busy[key] = true
    -- begin失败意味着未获得通知队列所有权，不调用finish清掉另一个事务的队列。
    if persistHooks.begin then
        local called, started = pcall(persistHooks.begin, uid)
        if not called or started == false then busy[key] = nil; return false, "装备整理处理中" end
    end
    local called, saved = pcall(function()
        applyLists(data, plan, assigned, nextSeq)
        return persist(uid)
    end)
    if not called or saved ~= true then
        restore(records)
        -- 与正式Flush一致，只在线边界可能变化；货币镜像同副本事务静默回滚，不发事件。
        GameState.syncFromCurrency(stateBefore, { silent = true })
        if persistHooks.finish then
            local finished, err = pcall(persistHooks.finish, uid, false)
            if not finished then print("[InventoryCuration] rollback hold error=" .. tostring(err)) end
        end
        busy[key] = nil
        print("[InventoryCuration] rollback uid=" .. key .. " saved=" .. tostring(called and saved))
        return false, "整理存档失败，可重试"
    end
    -- 提交点后先消费token再通知；订阅异常不能让客户端重试产生第二次搬运。
    pending[key] = nil
    for _, name in ipairs({ "equipment", "lootbox" }) do
        local notified, err = pcall(PDM.MarkDirty, uid, name)
        if not notified then print("[InventoryCuration] committed notify " .. name .. " error=" .. tostring(err)) end
    end
    if persistHooks.finish then
        local finished, err = pcall(persistHooks.finish, uid, true)
        if not finished then print("[InventoryCuration] committed hold error=" .. tostring(err)) end
    end
    busy[key] = nil
    print("[InventoryCuration] committed uid=" .. key .. " in=" .. plan.moveInCount .. " out=" .. plan.moveOutCount)
    return true, nil, resultFor(plan, token)
end

function M.Cleanup(uid)
    if not busy[tostring(uid)] then pending[tostring(uid)] = nil end
end

return M
