-- ============================================================================
-- LocalCloud - serverCloud 本地替身（单机回环模式）
-- 职责: 以「每 uid 每 key 一个 JSON 文件」实现 serverCloud 的 Score/List/Quota/Rank
--       API 面，回调签名与真实 serverCloud 保持一致（异步形态、同步触发）。
-- 运行端: 仅单机模式（LocalHost.Boot 时写入 _G.serverCloud）
-- 存储位置: saves/cloud/<uid>/<sanitized key>.json（File 沙箱相对路径）
--
-- 调用约定: 双端代码全部使用冒号语法 serverCloud:Get(...)，即第一个参数为 self，
--           因此本模块所有方法均以冒号风格定义。
--
-- 已实现（阶段 0/1）:
--   Get / Set / SetInt / Add / Delete
--   BatchGet → :Key() → :Fetch()
--   BatchCommit → :ScoreSet() → :Commit()
--   BatchSet → :Set/:SetInt/:Add/:Delete → :Save()
--   list.Get/GetById/Add/Modify/ModifyKey/Delete
--   quota.Get/Add/Reset
--   GetRankList/GetUserRank/GetRankTotal
--
-- 注意: 单机模式下原子性/事务语义不敏感，Commit 直接顺序落盘。
-- ============================================================================

local LocalCloud = {}

local cjson = cjson

-- ======================== 内部存储 ========================

--- 内存缓存: data[uid][key] = 解码后的 Lua 值
local data = {}

--- 落盘计数（诊断）
local dirtyCount = 0

local function sanitizeKey(key)
    key = tostring(key or "nil")
    key = key:gsub("[^%w%-%_]", "_")
    if #key > 100 then
        key = key:sub(1, 100)
    end
    return key
end

local function ensureDir(path)
    local dir = path:match("^(.*)/[^/]+$")
    if dir then
        local fs = fileSystem
        if fs and not fs:DirExists(dir) then
            fs:CreateDir(dir)
        end
    end
end

local function readFileJson(path)
    local file = File(path, FILE_READ)
    if not file or not file:IsOpen() then
        return nil
    end
    local raw = file:ReadString()
    file:Close()
    if not raw or raw == "" then return nil end
    local ok, decoded = pcall(cjson.decode, raw)
    if ok then return decoded end
    print("[LocalCloud][WARN] decode failed path=" .. path .. " err=" .. tostring(decoded))
    return nil
end

local function writeFileJson(path, value)
    ensureDir(path)
    local okEncode, raw = pcall(cjson.encode, value)
    if not okEncode then
        print("[LocalCloud][ERROR] encode failed path=" .. tostring(path) .. " err=" .. tostring(raw))
        return false
    end
    local file = File(path, FILE_WRITE)
    if not file or not file:IsOpen() then
        print("[LocalCloud][ERROR] cannot open for write path=" .. tostring(path))
        return false
    end
    file:WriteString(raw)
    file:Close()
    return true
end

local function loadData(uid, key)
    local u = data[uid]
    if u and u[key] ~= nil then
        return u[key]
    end
    local path = "saves/cloud/" .. tostring(uid) .. "/" .. sanitizeKey(key) .. ".json"
    local loaded = readFileJson(path)
    if loaded == nil then
        return nil
    end
    data[uid] = data[uid] or {}
    data[uid][key] = loaded
    return loaded
end

local function saveData(uid, key, value)
    data[uid] = data[uid] or {}
    data[uid][key] = value
    local path = "saves/cloud/" .. tostring(uid) .. "/" .. sanitizeKey(key) .. ".json"
    local okWrite = writeFileJson(path, value)
    if okWrite then
        dirtyCount = dirtyCount + 1
    end
    return okWrite
end

local function invoke(events, method, ...)
    if not events then return end
    local cb = events[method]
    if type(cb) ~= "function" then return end
    local ok, err = pcall(cb, ...)
    if not ok then
        print("[LocalCloud][ERROR] callback " .. tostring(method) .. " failed: " .. tostring(err))
    end
end

-- ======================== Score API ========================

--- 读取: events.ok(scores) 其中 scores = { [key] = 值 }；缺失 key 值为 nil
function LocalCloud:Get(uid, key, events)
    local value = loadData(uid, key)
    local scores = {}
    scores[key] = value
    invoke(events, "ok", scores)
end

function LocalCloud:Set(uid, key, value, events)
    saveData(uid, key, value)
    invoke(events, "ok")
end

function LocalCloud:SetInt(uid, key, value, events)
    saveData(uid, key, value)
    invoke(events, "ok")
end

function LocalCloud:Add(uid, key, delta, events)
    local current = loadData(uid, key)
    if type(current) ~= "number" then current = 0 end
    current = current + (tonumber(delta) or 0)
    saveData(uid, key, current)
    invoke(events, "ok", current)
end

function LocalCloud:Delete(uid, key, events)
    data[uid] = data[uid] or {}
    data[uid][key] = nil
    invoke(events, "ok")
end

-- ======================== BatchGet ========================

--- batch = serverCloud:BatchGet(uid)
--- batch:Key(key)  追加读取 key
--- batch:Fetch({ ok = function(scores) scores[key]... end, error = function(code, reason) end })
function LocalCloud:BatchGet(uid)
    local keys = {}
    local batch = {}

    function batch:Key(key)
        keys[#keys + 1] = key
        return self
    end

    function batch:Player(_otherUid)
        -- 单机不跨 uid 读取，占位
        return self
    end

    function batch:Fetch(events)
        local scores = {}
        for _, key in ipairs(keys) do
            scores[key] = loadData(uid, key)
        end
        invoke(events, "ok", scores)
    end

    return batch
end

-- ======================== BatchCommit ========================

--- commit = serverCloud:BatchCommit(label)
--- commit:ScoreSet(uid, key, table)
--- commit:Commit({ ok = function() end, error = function(code, reason) end })
function LocalCloud:BatchCommit(_label)
    local ops = {}
    local commit = {}

    function commit:ScoreSet(uid, key, value)
        ops[#ops + 1] = { uid = uid, key = key, value = value }
        return self
    end

    function commit:Commit(events)
        for _, op in ipairs(ops) do
            saveData(op.uid, op.key, op.value)
        end
        invoke(events, "ok")
        return self
    end

    function commit:Save(_desc, events)
        invoke(events, "ok")
        return self
    end

    return commit
end

--- batch = serverCloud:BatchSet(uid)
--- batch:Set(key, value) / :SetInt(key, value) / :Add(key, delta) / :Delete(key)
--- batch:Save(description, events?)
function LocalCloud:BatchSet(uid)
    local batch = {}

    function batch:Set(key, value)
        saveData(uid, key, value)
        return self
    end

    function batch:SetInt(key, value)
        saveData(uid, key, value)
        return self
    end

    function batch:Add(key, delta)
        local current = loadData(uid, key)
        if type(current) ~= "number" then current = 0 end
        current = current + (tonumber(delta) or 0)
        saveData(uid, key, current)
        return self
    end

    function batch:Delete(key)
        data[uid] = data[uid] or {}
        data[uid][key] = nil
        return self
    end

    function batch:Save(_desc, events)
        invoke(events, "ok")
        return self
    end

    return batch
end

-- ======================== 排行榜（简单实现） ========================

--- 排行榜数据: 每个榜单 key 一个文件（存于 uid="__rank__" 下），内容 { [uid] = score }
--- score 支持数字或 { iscore = n, name = "..." } 形态（ArenaService 双写策略）
local function rankStoreKey(rankKey)
    return "rank:" .. sanitizeKey(rankKey)
end

local function rankGetEntries(rankKey)
    return loadData("__rank__", rankStoreKey(rankKey)) or {}
end

local function rankSetEntries(rankKey, entries)
    saveData("__rank__", rankStoreKey(rankKey), entries)
end

--- GetRankList(key, start, count, [orderAsc,] events)
--- 返回 ok(list, total)，list 元素 { userId, score, name }
function LocalCloud:GetRankList(rankKey, start, count, a, b)
    local orderAsc, events
    if type(a) == "table" then
        events = a
    else
        orderAsc = a
        events = b
    end
    start = math.max(1, tonumber(start) or 1)
    count = tonumber(count) or 10

    local entries = rankGetEntries(rankKey)
    local list = {}
    for uidStr, entry in pairs(entries) do
        local score = entry
        local name = nil
        if type(entry) == "table" then
            score = entry.iscore or 0
            name = entry.name
        end
        list[#list + 1] = { userId = tonumber(uidStr), score = score, name = name }
    end
    table.sort(list, function(x, y)
        if orderAsc then
            return x.score < y.score
        end
        return x.score > y.score
    end)

    local page = {}
    for i = start, math.min(start + count - 1, #list) do
        page[#page + 1] = list[i]
    end
    invoke(events, "ok", page, #list)
end

function LocalCloud:GetUserRank(uid, rankKey, events)
    local entries = rankGetEntries(rankKey)
    local mine = entries[tostring(uid)]
    local score = 0
    if type(mine) == "table" then
        score = mine.iscore or 0
    elseif mine ~= nil then
        score = mine
    end
    local better = 0
    for _, entry in pairs(entries) do
        local s = entry
        if type(entry) == "table" then s = entry.iscore or 0 end
        if s > score then better = better + 1 end
    end
    invoke(events, "ok", better + 1, score)
end

function LocalCloud:GetRankTotal(rankKey, events)
    local entries = rankGetEntries(rankKey)
    local total = 0
    for _ in pairs(entries) do total = total + 1 end
    invoke(events, "ok", total)
end

-- ======================== list 子对象 ========================

--- 列表存储: saves/cloud/<uid>/list_<key>.json = { items = {...} }
local function listPath(uid, key)
    return "saves/cloud/" .. tostring(uid) .. "/list_" .. sanitizeKey(key) .. ".json"
end

local function listLoad(uid, key)
    local raw = readFileJson(listPath(uid, key))
    if type(raw) == "table" and type(raw.items) == "table" then
        return raw.items
    end
    return {}
end

local function listSave(uid, key, items)
    ensureDir(listPath(uid, key))
    writeFileJson(listPath(uid, key), { items = items })
end

LocalCloud.list = {}

function LocalCloud.list:Get(uid, key, events)
    invoke(events, "ok", listLoad(uid, key))
end

function LocalCloud.list:GetById(uid, key, itemId, events)
    local items = listLoad(uid, key)
    for _, item in ipairs(items) do
        if item.id == itemId then
            invoke(events, "ok", item)
            return
        end
    end
    invoke(events, "error", 404, "item not found")
end

function LocalCloud.list:Add(uid, key, item, events)
    local items = listLoad(uid, key)
    items[#items + 1] = item
    listSave(uid, key, items)
    invoke(events, "ok")
end

function LocalCloud.list:Modify(uid, key, itemId, patch, events)
    local items = listLoad(uid, key)
    for idx, item in ipairs(items) do
        if item.id == itemId then
            if type(patch) == "table" then
                for k, v in pairs(patch) do item[k] = v end
            end
            items[idx] = item
            listSave(uid, key, items)
            invoke(events, "ok")
            return
        end
    end
    invoke(events, "error", 404, "item not found")
end

function LocalCloud.list:ModifyKey(uid, key, itemId, field, value, events)
    return self:Modify(uid, key, itemId, { [field] = value }, events)
end

function LocalCloud.list:Delete(uid, key, itemId, events)
    local items = listLoad(uid, key)
    local result = {}
    for _, item in ipairs(items) do
        if item.id ~= itemId then
            result[#result + 1] = item
        end
    end
    listSave(uid, key, result)
    invoke(events, "ok")
end

-- ======================== quota 子对象 ========================

--- 配额: 存于 saves/cloud/<uid>/quota.json = { [quotaKey] = value }
LocalCloud.quota = {}

function LocalCloud.quota:Get(uid, quotaKey, events)
    local q = loadData(uid, "quota") or {}
    invoke(events, "ok", q[quotaKey] or 0)
end

function LocalCloud.quota:Add(uid, quotaKey, delta, events)
    local q = loadData(uid, "quota") or {}
    q[quotaKey] = (tonumber(q[quotaKey]) or 0) + (tonumber(delta) or 0)
    saveData(uid, "quota", q)
    invoke(events, "ok", q[quotaKey])
end

function LocalCloud.quota:Reset(uid, quotaKey, events)
    local q = loadData(uid, "quota") or {}
    q[quotaKey] = 0
    saveData(uid, "quota", q)
    invoke(events, "ok")
end

-- ======================== 诊断 ========================

--- 落盘计数（诊断用）
function LocalCloud:GetDirtyCount()
    return dirtyCount
end

--- 清空内存缓存（不清文件；供测试用）
function LocalCloud:ClearCache()
    data = {}
end

return LocalCloud
