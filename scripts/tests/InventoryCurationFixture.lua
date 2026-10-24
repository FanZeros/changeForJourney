-- 私有真实模块编译夹具：不运行Boot、不访问账号、不向原生File/FileSystem委托。
-- 所有持久化API仅操作内存字典；cache只允许读取.lua资源。Runtime由内部launcher冻结源码。
local M = {}

function M.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[key] = M.copy(item, seen) end
    return result
end

function M.same(actual, expected, path)
    path = path or "value"
    assert(type(actual) == type(expected), path .. " type " .. type(actual) .. "/" .. type(expected))
    if type(expected) ~= "table" then
        assert(actual == expected, path .. " " .. tostring(actual) .. "/" .. tostring(expected))
        return
    end
    for key, value in pairs(expected) do M.same(actual[key], value, path .. "/" .. tostring(key)) end
    for key in pairs(actual) do assert(expected[key] ~= nil, path .. " unexpected " .. tostring(key)) end
end

-- 记录每条原表边；回滚不能只恢复值，却偷偷替换外部持有的inventory/词缀/seed引用。
function M.aliases(root)
    local edges, visited = {}, {}
    local function walk(value)
        if type(value) ~= "table" or visited[value] then return end
        visited[value] = true
        for key, child in pairs(value) do
            if type(child) == "table" then
                edges[#edges + 1] = { parent = value, key = key, child = child }
                walk(child)
            end
        end
    end
    walk(root)
    return edges
end

function M.assertAliases(edges)
    for index, edge in ipairs(edges) do
        assert(edge.parent[edge.key] == edge.child, "rollback replaced table edge " .. index .. "/" .. tostring(edge.key))
    end
end

local function source(name)
    assert(type(name) == "string" and name:match("^[%w_%.]+$") and not name:find("..", 1, true), "script module only")
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "missing script " .. name)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

function M.new(disk)
    local h = { disk = disk or {}, pending = {}, failure = "", flushCalls = 0,
        pushes = {}, notificationOrder = {}, randomCalls = 0, fileCalls = 0, fsCalls = 0,
        committed = false, queue = false, clock = 1000 }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.time = { elapsedTime = h.clock }
    env.math = M.copy(math)
    env.math.random = function()
        h.randomCalls = h.randomCalls + 1
        error("forbidden RNG in curation/claim/cold restore")
    end
    env.math.randomseed = function() error("forbidden randomseed") end
    env.os = M.copy(os)
    env.os.time = function() return math.floor(h.clock) end
    local function virtualPath(path)
        assert(path == "standalone_save.json" or path == "standalone_save.pending.json"
            or (h.allowBootFixture and path == "gacha_history.json"), "unauthorized virtual path " .. tostring(path))
        return path
    end
    -- Literal save names are virtual dictionary keys only. Native File/FS never captured or called.
    env.File = function(path, mode)
        path = virtualPath(path)
        h.fileCalls = h.fileCalls + 1
        local opened = mode == FILE_WRITE or h.disk[path] ~= nil
        local handle = {}
        function handle:IsOpen() return opened end
        function handle:ReadString() assert(opened and mode == FILE_READ); return h.disk[path] end
        function handle:WriteString(text)
            assert(opened and mode == FILE_WRITE and path == "standalone_save.pending.json")
            h.disk[path] = text
            return true
        end
        function handle:Close() opened = false end
        function handle:Dispose() opened = false end
        return handle
    end
    env.fileSystem = {
        FileExists = function(_, path) h.fsCalls = h.fsCalls + 1; return h.disk[virtualPath(path)] ~= nil end,
        Delete = function(_, path) h.fsCalls = h.fsCalls + 1; h.disk[virtualPath(path)] = nil; return true end,
        Rename = function(_, from, to)
            h.fsCalls = h.fsCalls + 1
            from, to = virtualPath(from), virtualPath(to)
            assert(from == "standalone_save.pending.json" and to == "standalone_save.json")
            if h.disk[from] == nil then return false end
            h.disk[to], h.disk[from], h.committed = h.disk[from], nil, true
            return true
        end,
    }
    local function noop() end
    local loaded, mocks = {}, {}
    mocks["ui.battle.scene.BattleScene"] = {
        getStageId = function() return 101 end, getMaxStageId = function() return 101 end,
        getClearedStages = function() return {} end,
    }
    mocks["rules.offline.OfflineService"] = {
        HasPendingRewards = function() return true end, MarkOnline = noop,
    }
    -- PlayerStore/Dispatcher均为真实模块；attach后Init提供正式单调revision验证ABA。
    -- Real BlacksmithService is loaded on demand, unless a test explicitly needs a pending-only seam.
    env.require = function(name)
        if name == "cjson" then return cjson end
        -- 旧overflow夹具会加载UI声明但不Init/渲染；引擎内置只读库按原require解析。
        if h.allowBootFixture and name:match("^urhox%-libs[./]") then return require(name) end
        if mocks[name] then return mocks[name] end
        if loaded[name] ~= nil then return loaded[name] end
        assert(not name:match("^boot%.") or name == "boot.StandaloneSave" or h.allowBootFixture, "game boot forbidden")
        assert(name ~= "runtime.LocalActionBridge" or h.allowBootFixture, "live bridge forbidden")
        local chunk = assert(load(source(name), "@curation-test/" .. name, "t", env))
        local result = chunk()
        loaded[name] = result == nil and true or result
        return loaded[name]
    end
    h.env, h.require, h.loaded, h.mocks = env, env.require, loaded, mocks
    function h:setTime(value) self.clock = value; self.env.time.elapsedTime = value end
    function h:attach(modules)
        self.modules = modules
        self.PDM = self.require("rules.character.PlayerDataManager")
        self.Dispatcher = self.require("runtime.ClientDispatcher")
        local cacheModules = self.Dispatcher.getAll()
        for key in pairs(cacheModules) do cacheModules[key] = nil end
        for key, value in pairs(modules) do cacheModules[key] = value end
        self.modules = cacheModules
        self.PDM.AttachLocalModules(1, cacheModules)
        self.require("core.PlayerStore").Init()
        self.require("core.GameState").setLocalPlayerSync(function() end)
        self.PDM.Setup({ serverDispatcher = { pushModule = function(_, name, data)
            if self.queue then self.queue[name] = data return end
            assert(self.committed, "notification before persistence " .. name)
            self.pushes[name] = (self.pushes[name] or 0) + 1
            self.notificationOrder[#self.notificationOrder + 1] = name
            self.Dispatcher.set(name, data, { normalized = true })
        end } })
        return cacheModules
    end
    function h:connectService()
        self.Service = self.require("rules.equipment.InventoryCurationService")
        self.Save = self.require("boot.StandaloneSave")
        self.Service.SetPersistCallback(function()
            self.flushCalls = self.flushCalls + 1
            assert(#self.notificationOrder == 0, "no pre-Flush notification")
            if self.failure == "false" then return false end
            if self.failure == "nil" then return nil end
            if self.failure == "throw" then error("expected Flush exception") end
            return self.Save.Flush()
        end, {
            begin = function() self.queue = {} end,
            finish = function(_, success)
                local queued = self.queue
                self.queue = false
                if not success then return end
                if type(queued) == "table" then
                    for name, data in pairs(queued) do
                        assert(self.committed, "queued notification before commit")
                        self.pushes[name] = (self.pushes[name] or 0) + 1
                        self.notificationOrder[#self.notificationOrder + 1] = name
                        self.Dispatcher.set(name, data, { normalized = true })
                    end
                end
            end,
        })
        return self.Service
    end
    function h:resetNotifications()
        self.pushes, self.notificationOrder, self.committed = {}, {}, false
    end
    return h
end

-- 确定性夹具，绝不调用generate/roll；正式hydrate只作用于新构建夹具。
function M.item(h, templateId, level, quality)
    local item = { templateId = templateId or "W1", level = level or 1,
        quality = quality or 1, ascendLevel = 0, affixes = {} }
    h.require("systems.EquipmentSystem").hydrate(item)
    return item
end

function M.bag(h, count, templateId)
    local equipment = { inventory = {}, equipped = {}, nextSeq = count + 1,
        settings = { autoQuality = 0, autoLevel = 0 } }
    local filler = M.item(h, templateId, 1, 1)
    for index = 1, count do
        local item = M.copy(filler)
        item.seq = index
        equipment.inventory[tostring(index)] = item
    end
    return equipment
end

function M.box(items)
    local seeds = {}
    for _, item in ipairs(items) do
        seeds[#seeds + 1] = { quality = item.quality, level = item.level, count = 1, equip = item, source = "overflow" }
    end
    return { seeds = seeds }
end

function M.modules(h, count)
    return {
        equipment = M.bag(h, count), lootbox = { seeds = {} },
        heroes = { roster = { [1] = { level = 100 } }, deployed = { 1, 0, 0, 0 },
            teams = { { slots = { 1, 0, 0, 0 } }, { slots = { 0, 0, 0, 0 } }, { slots = { 0, 0, 0, 0 } } } },
        player = { name = "curation-test", level = 10, exp = 0, maxExp = 100 },
        session = { lastOnlineTime = 1 }, currency = { gold = 1000, gems = 200 },
        battle = { currentStageId = 101, maxStageId = 101, clearedStages = {}, teamStageIds = { 101, 101, 101 } },
    }
end

return M
