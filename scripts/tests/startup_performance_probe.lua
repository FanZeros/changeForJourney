-- Startup regression/performance probe. Baseline: 5fca1d82; same probe for later A/B.
-- Based on scaffold-2d's Start/Update/Stop lifecycle and equipment_ascend_freeze_repro's
-- cache:GetFile -> load(..., env) isolation. Never require main/Standalone in host _G.
-- Run from /workspace in a FRESH Runtime process (no official build required):
-- ./.cli/UrhoXRuntime tests/startup_performance_probe.lua -tapcode_dir=. -tool_mode -graphicssurfaceless
-- Add -startup-enter to tap the ready title, let the REAL compact LetterIntro finish,
-- and sample at least 180 battle Update AND NanoVGRender callbacks with starter trio.
-- Options: -startup-frames=180 (minimum 180), -startup-max-frames=1800, -startup-top=8.
-- Native TimeStep/random consumption/GC remain unchanged. CPU = os.clock (process CPU,
-- may include driver workers); wall = native time.elapsedTime, NOT TimeStep/FPS/GPU time.
-- Module/function timings are inclusive; nested totals must NOT be added together.
-- Coroutine yield intervals are excluded from active CPU/wall; span_wall includes waits.
-- File/FS are sealed in env, save IO is stubbed, other project code/resources are real.
-- Persistence snapshot/serialization cost is intentionally excluded; not a save benchmark.
-- Original engine-library require is retained; library-internal calls are not instrumented.
---@diagnostic disable: param-type-mismatch, assign-type-mismatch
local TAG = "[startup-probe]"
local nativeRequire, nativeLoad, nativeCache = require, load, cache
local nativeTime, nativeClock, nativePrint = time, os.clock, print
local nativeSubscribe, nativeCoroutine = SubscribeToEvent, coroutine
local nativeCreateImage, nativeDeleteImage = nvgCreateImage, nvgDeleteImage
---@type table
local ctx = { modules = {}, loading = {}, engineModules = {}, metrics = {}, errors = {},
    scopes = {}, images = {}, requests = {}, frames = 0, renders = 0, phase = "load",
    enter = false, sampleFrames = 180, maxFrames = 1800, top = 8, seed = 20261007,
    sourceRoot = "/workspace",
    done = false, started = false, stopped = false, bootDone = false, bootSteps = 0,
    titleReadyFrame = -1, bootDoneFrame = -1, battleFirstFrame = -1, entered = false,
    requireCalls = 0, sourceLoads = 0, sourceBytes = 0, engineCalls = 0,
    loadDepth = 0, requireCpu = 0, requireWall = 0,
    fileAttempts = 0, fsQueries = 0, denied = 0, saveCalls = {}, productionLines = 0,
    requestDepth = 0, requestHookInstalled = false, contextIds = {}, nextContextId = 0,
    activeImages = {}, updateTasks = 0, drawTasks = 0, initTasks = 0, frameBootTasks = 0,
    frameLoads = 0, frameImages = 0, frameRequests = 0, dtTotal = 0, dtMax = 0,
    frameWork = {}, observedFrames = {}, eventImageStats = {}, imageOwners = {},
    battleUpdates = 0, battleRenders = 0, renderPending = false, endRequested = false, driverRefs = {} }
local overrides = {}
local env = setmetatable({}, { __index = function(_, key)
    local value = overrides[key]
    if value ~= nil then return value end
    return _G[key]
end, __newindex = function(_, key, value) overrides[key] = value end })
env._G = env
local function wall() return nativeTime.elapsedTime end
local function traceback(err)
    return debug and debug.traceback and debug.traceback(tostring(err), 2) or tostring(err)
end
local function capture(name, err)
    local message = tostring(err)
    local key = name .. "|" .. message
    local item = ctx.errors[key]
    if not item then
        item = { name = name, message = message, count = 0, firstFrame = ctx.frames }
        ctx.errors[key] = item
    end
    item.count = item.count + 1
end
local function metric(key)
    local m = ctx.metrics[key]
    if not m then
        m = { name = key, calls = 0, cpu = 0, wall = 0, span = 0, cpuMax = 0,
            wallMax = 0, errors = 0, cpuFrame = 0, wallFrame = 0 }
        ctx.metrics[key] = m
    end
    return m
end
local function threadKey() return nativeCoroutine.running() end
local function pauseScopes()
    local stack = ctx.scopes[threadKey()]
    if not stack then return end
    local c, w = nativeClock(), wall()
    for _, s in ipairs(stack) do
        if s.active then
            s.cpu = s.cpu + c - s.c0
            s.wall = s.wall + w - s.w0
            s.active = false
        end
    end
end
local function resumeScopes()
    local stack = ctx.scopes[threadKey()]
    if not stack then return end
    local c, w = nativeClock(), wall()
    for _, s in ipairs(stack) do
        if not s.active then s.c0, s.w0, s.active = c, w, true end
    end
end
local function measured(key, fn, ...)
    local m = metric(key)
    local c, w = nativeClock(), wall()
    local s = { name = key, c0 = c, w0 = w, beginWall = w, cpu = 0, wall = 0, active = true }
    local thread = threadKey()
    local stack = ctx.scopes[thread]
    if not stack then stack = {}; ctx.scopes[thread] = stack end
    stack[#stack + 1] = s
    local result = table.pack(xpcall(fn, traceback, ...))
    local endCpu, endWall = nativeClock(), wall()
    if s.active then
        s.cpu = s.cpu + endCpu - s.c0
        s.wall = s.wall + endWall - s.w0
    end
    stack[#stack] = nil
    m.calls = m.calls + 1
    local cpuMs, wallMs = s.cpu * 1000, s.wall * 1000
    m.cpu, m.wall, m.span = m.cpu + cpuMs, m.wall + wallMs, m.span + (endWall - s.beginWall) * 1000
    if cpuMs > m.cpuMax then m.cpuMax, m.cpuFrame = cpuMs, ctx.frames end
    if wallMs > m.wallMax then m.wallMax, m.wallFrame = wallMs, ctx.frames end
    if not result[1] then
        m.errors = m.errors + 1
        capture(key, result[2])
        error(result[2], 0) -- retain production pcall/error propagation (never fake success).
    end
    return table.unpack(result, 2, result.n)
end
local function guarded(key, fn, ...)
    local result = table.pack(pcall(measured, key, fn, ...))
    return result[1], table.unpack(result, 2, result.n)
end
-- A future startup coroutine may suspend inside init. Keep the wrappers yieldable,
-- and don't charge other Update/draw work during suspension to that init's CPU.
env.coroutine = setmetatable({ yield = function(...)
    pauseScopes()
    local result = table.pack(nativeCoroutine.yield(...))
    resumeScopes()
    return table.unpack(result, 1, result.n)
end }, { __index = nativeCoroutine })
local function deny(operation)
    return function(...)
        ctx.denied = ctx.denied + 1
        error("STARTUP_PROBE_FORBIDDEN " .. operation, 0)
    end
end
-- No native File object is ever constructed. Direct File calls receive a closed
-- sink (existing PlayerInfo play-time autosave can fail harmlessly, without IO).
local closedFile = { IsOpen = function() return false end, IsEof = function() return true end,
    Close = function() end, Dispose = function() end, WriteString = function() return false end,
    ReadString = deny("File.ReadString"), ReadLine = deny("File.ReadLine") }
env.File = function(path, mode)
    ctx.fileAttempts = ctx.fileAttempts + 1
    local key = "File:" .. tostring(mode) .. ":" .. tostring(path)
    ctx.saveCalls[key] = (ctx.saveCalls[key] or 0) + 1
    return closedFile
end
env.fileSystem = setmetatable({ FileExists = function(_, path)
    ctx.fsQueries = ctx.fsQueries + 1
    local key = "FS.absent:" .. tostring(path)
    ctx.saveCalls[key] = (ctx.saveCalls[key] or 0) + 1
    return false -- empty test namespace, NOT a real filesystem query.
end }, { __index = function(_, key) return deny("FS." .. tostring(key)) end })
env.GetFileSystem = function() return env.fileSystem end
env.FileSystem = function() return env.fileSystem end
env.io = setmetatable({}, { __index = function(_, key) return deny("io." .. tostring(key)) end })
env.os = { clock = nativeClock, time = os.time, date = os.date, difftime = os.difftime }
env.loadfile, env.dofile = deny("loadfile"), deny("dofile")
for _, key in ipairs({ "network", "clientCloud", "serverCloud" }) do
    env[key] = setmetatable({}, { __index = function(_, method) return deny(key .. "." .. tostring(method)) end })
end
local function sourcePath(path)
    return type(path) == "string" and not path:find("..", 1, true)
        and not path:match("^[/\\]") and path:match("^[%w_/-]+%.lua$") ~= nil
end
-- Resource reads remain real. GetFile is restricted to relative Lua source, so a
-- module cannot use cache as a side door to standalone_save/settings/play_time.
env.cache = setmetatable({ GetFile = function(_, path)
    assert(sourcePath(path), "STARTUP_PROBE_FORBIDDEN cache:GetFile " .. tostring(path))
    return nativeCache:GetFile(path)
end, GetResource = function(_, kind, path, ...)
    assert(kind ~= "File" and kind ~= "PackageFile", "STARTUP_PROBE_FORBIDDEN resource type")
    assert(type(path) == "string" and not path:find("..", 1, true) and not path:match("^[/\\]"),
        "STARTUP_PROBE_FORBIDDEN resource path " .. tostring(path))
    return nativeCache:GetResource(kind, path, ...)
end }, { __index = function(_, key)
    -- Other cache API is not needed by this startup chain; fail closed, not passthrough.
    return deny("cache." .. tostring(key))
end })
env.GetResourceCache = function() return env.cache end
env.load = function(text, name, mode, target)
    assert(target == nil or target == env, "STARTUP_PROBE_FORBIDDEN load environment")
    return nativeLoad(text, name, mode or "t", env)
end
env.package = { loaded = ctx.modules, preload = {} }
env.print = function(...)
    ctx.productionLines = ctx.productionLines + 1
    local args = table.pack(...)
    for i = 1, args.n do args[i] = tostring(args[i]) end
    local line = table.concat(args, " ", 1, args.n)
    if line:find("[Standalone] boot step ", 1, true) then
        ctx.bootSteps = ctx.bootSteps + 1
        ctx.frameBootTasks = ctx.frameBootTasks + 1
    end
    if line:find("boot queue complete", 1, true) then ctx.bootDone = true end
    if line:find(" FAIL ", 1, true) or line:find("ERROR", 1, true) or line:find("failed:", 1, true) then
        capture("production.log", line)
    end
    -- Captured/summarized, never print per-frame production diagnostics.
end
local function imageKey(context, path, flags)
    local id = ctx.contextIds[context]
    if not id then
        ctx.nextContextId = ctx.nextContextId + 1
        id = ctx.nextContextId
        ctx.contextIds[context] = id
    end
    return tostring(id) .. ":" .. tostring(flags or 0) .. ":" .. tostring(path)
end
local function imageOwner()
    local stack = ctx.scopes[threadKey()] or {}
    for i = #stack, 1, -1 do
        local key = stack[i].name
        if key:match("^draw|") or key:match("^init|") or key:match("^update|") then return key end
    end
    return "Start/require"
end
local function observeWork()
    ctx.frameWork[ctx.frames] = (ctx.frameWork[ctx.frames] or 0) + 1
end
-- Installed BEFORE Standalone.Start takes its native function reference. Thus
-- native stats are beneath its real cache and cover Start/init/first draw misses.
env.nvgCreateImage = function(context, path, flags)
    assert(not tostring(path):match("^https?://"), "STARTUP_PROBE_FORBIDDEN remote image")
    local key = imageKey(context, path, flags)
    local item = ctx.images[key]
    local owner = imageOwner()
    if not item then
        item = { name = key, calls = 0, failed = 0, repeatedLive = 0, owner = owner, firstFrame = ctx.frames }
        ctx.images[key] = item
    end
    local group = ctx.imageOwners[owner]
    if not group then group = { name = owner, calls = 0, cpu = 0, wall = 0 }; ctx.imageOwners[owner] = group end
    group.calls = group.calls + 1
    item.calls = item.calls + 1
    ctx.frameImages = ctx.frameImages + 1
    observeWork()
    if ctx.activeImages[key] then item.repeatedLive = item.repeatedLive + 1 end
    local cpu0, wall0 = nativeClock(), wall()
    local handle = measured("decode|" .. key, nativeCreateImage, context, path, flags)
    group.cpu, group.wall = group.cpu + (nativeClock() - cpu0) * 1000, group.wall + (wall() - wall0) * 1000
    if not handle or handle <= 0 then
        item.failed = item.failed + 1
    else
        ctx.activeImages[key] = handle
    end
    return handle
end
env.nvgDeleteImage = function(context, handle)
    for key, value in pairs(ctx.activeImages) do
        if value == handle and key:match("^(%d+):") == tostring(ctx.contextIds[context]) then
            ctx.activeImages[key] = nil
        end
    end
    return nativeDeleteImage(context, handle)
end
local function readSource(name)
    local path = name:gsub("%.", "/") .. ".lua"
    assert(sourcePath(path), "invalid project module " .. tostring(name))
    local file = assert(nativeCache:GetFile(path), "missing readonly source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local text = table.concat(lines, "\n")
    ctx.sourceBytes = ctx.sourceBytes + #text
    return text, path
end
local function saveStub(module)
    -- Load the REAL module into env (no top-level IO), retaining pure progress APIs.
    -- Replace every persistence entry before publishing the module or calling Start.
    for _, name in ipairs({ "RestoreData", "Update", "Flush", "Wipe", "ReconcileOfflineBoundary", "OfflineChecked" }) do
        assert(type(module[name]) == "function", "save contract changed: " .. name)
        module[name] = function()
            ctx.saveCalls["StandaloneSave." .. name] = (ctx.saveCalls["StandaloneSave." .. name] or 0) + 1
            if name == "RestoreData" then return false end
            if name == "Flush" then return true end
        end
    end
    for _, name in ipairs({ "CaptureBattleProgress", "SetBattlePage", "ApplyBattleProgress" }) do
        assert(type(module[name]) == "function", "missing pure save API " .. name)
    end
end
local function instrument(name, module)
    if type(module) ~= "table" then return end
    for key, original in pairs(module) do
        if type(original) == "function" then
            local kind
            if key == "init" or key == "Init" then kind = "init"
            elseif key == "update" or key == "Update" then kind = "update"
            elseif key == "draw" or key == "Draw" then kind = "draw"
            elseif (name == "boot.StandaloneBoot" and key == "run")
                or (name == "boot.Standalone" and key == "_bootWiring") then kind = "init" end
            if kind and name ~= "boot.StandaloneSave" then
                module[key] = function(...)
                    observeWork()
                    if kind == "init" then ctx.initTasks = ctx.initTasks + 1
                    elseif kind == "update" then ctx.updateTasks = ctx.updateTasks + 1
                    else ctx.drawTasks = ctx.drawTasks + 1 end
                    return measured(kind .. "|" .. name .. "." .. key, original, ...)
                end
            end
        end
    end
    if name == "ui.battle.tri.BattleTriDriver" then
        local factory = assert(module.new)
        module.new = function(team, ...)
            local drv = factory(team, ...)
            ctx.driverRefs[team] = drv
            return drv
        end
    end
    if name == "ui.battle.tri.BattleTriPage" then
        local original = assert(module.setBattleReady)
        module.setBattleReady = function(ready)
            local result = table.pack(original(ready))
            if ready == true then
                ctx.bootDone = true
                if ctx.bootDoneFrame < 0 then ctx.bootDoneFrame = ctx.frames end
            end
            return table.unpack(result, 1, result.n)
        end
    end
end
local function loadProject(name)
    ctx.requireCalls = ctx.requireCalls + 1
    if name == "cjson" then return cjson end
    if name:match("^urhox%-libs[./]") or name:match("^LuaScripts/") then
        ctx.engineCalls = ctx.engineCalls + 1
        if not ctx.engineModules[name] then
            ctx.engineModules[name] = true
            return measured("engine-require|" .. name, nativeRequire, name)
        end
        return nativeRequire(name) -- no library source reload, no host require override.
    end
    if ctx.modules[name] ~= nil then return ctx.modules[name] end
    assert(not ctx.loading[name], "isolated cyclic require " .. tostring(name))
    ctx.loading[name] = true
    ctx.sourceLoads, ctx.frameLoads = ctx.sourceLoads + 1, ctx.frameLoads + 1
    observeWork()
    local rootLoad = ctx.loadDepth == 0
    local cpu0, wall0 = nativeClock(), wall()
    ctx.loadDepth = ctx.loadDepth + 1
    local result = table.pack(pcall(measured, "require|" .. name, function()
        local text, path = readSource(name)
        -- Source loading avoids the Runtime require macro/global environment entirely.
        return assert(nativeLoad(text, "@" .. ctx.sourceRoot .. "/scripts/" .. path, "t", env))()
    end))
    ctx.loadDepth = ctx.loadDepth - 1
    if rootLoad then
        ctx.requireCpu = ctx.requireCpu + (nativeClock() - cpu0) * 1000
        ctx.requireWall = ctx.requireWall + (wall() - wall0) * 1000
    end
    ctx.loading[name] = nil
    if not result[1] then error(result[2], 0) end
    local module = result[2]
    if module == nil then module = true end
    if name == "boot.StandaloneSave" then saveStub(module) end
    instrument(name, module)
    ctx.modules[name], ctx.loading[name] = module, nil
    return module
end
env.require = loadProject
local requestOriginal = { value = false }
local function installRequestHook()
    -- Start already installed its cache. Outer observation preserves that real cache.
    -- Request counters explicitly cover POST-Start only; decode counters cover all.
    local original = env.nvgCreateImage
    requestOriginal.value = original
    env.nvgCreateImage = function(context, path, flags)
        local key = imageKey(context, path, flags)
        ctx.requests[key] = (ctx.requests[key] or 0) + 1
        ctx.frameRequests = ctx.frameRequests + 1
        return original(context, path, flags)
    end
    ctx.requestHookInstalled = true
end
local function phase()
    local title = ctx.modules["ui.story.gate.DarkTitleScreenGate"]
    local letter = ctx.modules["ui.story.gate.LetterIntro"]
    local tri = ctx.modules["ui.battle.tri.BattleTriPage"]
    if not title then return "load" end
    if title.isOpen() then return title.isFading() and "title-fade" or "title" end
    if letter and letter.isOpen() then return "letter" end
    local rt = ctx.modules["boot.StandaloneRT"]
    if rt and rt.entryPreparing then return "entering" end
    local dispatcher = ctx.modules["runtime.ClientDispatcher"]
    local session = dispatcher and dispatcher.get("session")
    if ctx.bootDone and tri and tri.isOpen() and session and session.introCompleted == true then return "battle" end
    return "entering"
end
local function tasksForFrame(label)
    local key = "tasks|" .. label
    local m = metric(key)
    m.calls = m.calls + 1
    -- count instrumented exported init/update/draw + project loads + actual decodes.
    -- These are observable work calls, NOT all Lua calls or a scheduler queue length.
    local tasks = ctx.initTasks + ctx.updateTasks + ctx.drawTasks + ctx.frameLoads + ctx.frameImages
    m.cpu = m.cpu + tasks -- print this separately as task counts, never as time.
    if tasks > m.cpuMax then m.cpuMax, m.cpuFrame = tasks, ctx.frames end
    m.wall = m.wall + ctx.frameBootTasks
    m.wallMax = math.max(m.wallMax, ctx.frameBootTasks)
    ctx.observedFrames[ctx.frames] = true
    local images = ctx.eventImageStats[label]
    if not images then images = { calls = 0, decodes = 0, max = 0, maxFrame = 0, loads = 0, requests = 0 }; ctx.eventImageStats[label] = images end
    images.calls, images.decodes = images.calls + 1, images.decodes + ctx.frameImages
    images.loads, images.requests = images.loads + ctx.frameLoads, images.requests + ctx.frameRequests
    if ctx.frameImages > images.max then images.max, images.maxFrame = ctx.frameImages, ctx.frames end
end
local function printMetric(m)
    nativePrint(string.format("%s METRIC %s calls=%d cpu_total_ms=%.3f cpu_max_ms=%.3f cpu_max_frame=%d wall_total_ms=%.3f wall_max_ms=%.3f wall_max_frame=%d span_wall_total_ms=%.3f errors=%d",
        TAG, m.name, m.calls, m.cpu, m.cpuMax, m.cpuFrame, m.wall, m.wallMax, m.wallFrame, m.span, m.errors))
end
local function ranked(prefix, count, score)
    local list = {}
    for key, m in pairs(ctx.metrics) do
        if key:sub(1, #prefix) == prefix then list[#list + 1] = m end
    end
    table.sort(list, function(a, b)
        local av, bv = a[score], b[score]
        return av == bv and a.name < b.name or av > bv
    end)
    for i = 1, math.min(count, #list) do printMetric(list[i]) end
end
local function checkTrio()
    local dispatcher = ctx.modules["runtime.ClientDispatcher"]
    local panel = ctx.modules["ui.character.panel.CharacterPanel"]
    local scene = ctx.modules["ui.battle.scene.BattleScene"]
    if not dispatcher or not panel or not scene then return false end
    local heroes = dispatcher.get("heroes")
    if not heroes or not heroes.roster then return false end
    for id = 1, 3 do
        if not (heroes.roster[id] or heroes.roster[tostring(id)]) then return false end
    end
    local team = panel.getDeployedTeam(1)
    -- 三行已经接管时验证实际参战驱动，不用已暂停的兼容Scene旧单人快照替代。
    local driver = ctx.driverRefs[1]
    local allies = driver and driver.allies or scene.getAllies()
    if #team ~= 3 or #allies ~= 3 then return false end
    local seen = {}
    for _, ally in ipairs(allies) do seen[ally.heroId or ally.id] = true end
    return seen[1] == true and seen[2] == true and seen[3] == true
end
local function summarize(reason)
    if not ctx.bootDone then capture("assert", "full boot/firstStage did not finish") end
    if ctx.enter then
        if not checkTrio() then capture("assert", "REAL starter trio not deployed in BattleScene") end
        if ctx.battleUpdates < ctx.sampleFrames or ctx.battleRenders < ctx.sampleFrames then
            capture("assert", "insufficient real battle callbacks")
        end
        local update = ctx.metrics["update|ui.battle.tri.BattleTriPage.update"]
        local draw = ctx.metrics["draw|ui.battle.tri.BattleTriPage.draw"]
        if not update or update.calls == 0 or not draw or draw.calls == 0 then capture("assert", "battle driver/draw never ran") end
    elseif ctx.frames < ctx.sampleFrames or ctx.renders < ctx.sampleFrames then
        capture("assert", "insufficient real title callbacks")
    end
    local decodeCalls, failures, repeatLive, repeatedKeys, uniqueImages = 0, 0, 0, 0, 0
    for _, item in pairs(ctx.images) do
        uniqueImages = uniqueImages + 1
        decodeCalls, failures, repeatLive = decodeCalls + item.calls, failures + item.failed, repeatLive + item.repeatedLive
        if item.calls > 1 then repeatedKeys = repeatedKeys + 1 end
    end
    local requestCalls, requestDuplicates = 0, 0
    for _, count in pairs(ctx.requests) do
        requestCalls = requestCalls + count
        requestDuplicates = requestDuplicates + math.max(0, count - 1)
    end
    local errorCount, uniqueErrors = 0, 0
    for _, item in pairs(ctx.errors) do errorCount, uniqueErrors = errorCount + item.count, uniqueErrors + 1 end
    nativePrint(string.format("%s SUMMARY result=%s reason=%s mode=%s updates=%d renders=%d battle_updates=%d battle_renders=%d boot_steps_logged=%d full_boot=%s title_ready_frame=%d full_boot_frame=%d battle_first_frame=%d dt_total_s=%.3f dt_max_s=%.6f cpu_process_ms=%.3f wall_process_ms=%.3f error_observations=%d unique_errors=%d",
        TAG, uniqueErrors == 0 and "PASS" or "FAIL", reason, ctx.enter and "enter" or "title", ctx.frames, ctx.renders,
        ctx.battleUpdates, ctx.battleRenders, ctx.bootSteps, tostring(ctx.bootDone), ctx.titleReadyFrame, ctx.bootDoneFrame,
        ctx.battleFirstFrame, ctx.dtTotal, ctx.dtMax, (nativeClock() - ctx.beginCpu) * 1000, (wall() - ctx.beginWall) * 1000, errorCount, uniqueErrors))
    local engineUnique = 0
    for _ in pairs(ctx.engineModules) do engineUnique = engineUnique + 1 end
    nativePrint(string.format("%s LOAD require_calls=%d project_source_loads=%d source_bytes=%d engine_require_calls=%d engine_unique=%d persistence_serialization=excluded production_lines_summarized=%d",
        TAG, ctx.requireCalls, ctx.sourceLoads, ctx.sourceBytes, ctx.engineCalls, engineUnique, ctx.productionLines))
    nativePrint(string.format("%s IMAGES native_decode_calls=%d unique_context_flags_paths=%d failed_calls=%d repeated_decode_keys=%d repeated_while_live=%d post_Start_requests=%d post_Start_duplicate_requests=%d library_internal_calls=excluded",
        TAG, decodeCalls, uniqueImages, failures, repeatedKeys, repeatLive, requestCalls, requestDuplicates))
    local nativeCpuTotal, nativeWallTotal = 0, 0
    for key in pairs(ctx.images) do
        local m = ctx.metrics["decode|" .. key]
        nativeCpuTotal, nativeWallTotal = nativeCpuTotal + m.cpu, nativeWallTotal + m.wall
    end
    nativePrint(string.format("%s TOTAL nonnested_source_require_cpu_ms=%.3f nonnested_source_require_wall_ms=%.3f native_image_cpu_ms=%.3f native_image_wall_ms=%.3f",
        TAG, ctx.requireCpu, ctx.requireWall, nativeCpuTotal, nativeWallTotal))
    nativePrint(string.format("%s ISOLATION real_File_calls=0 real_fs_queries=0 closed_File_attempts=%d empty_fs_queries=%d denied_operations=%d seed=%d gc=unchanged timestep=native",
        TAG, ctx.fileAttempts, ctx.fsQueries, ctx.denied, ctx.seed))
    local keys = {}
    for key in pairs(ctx.metrics) do
        if key:match("^event|") or key:match("^probe|") or key:match("^tasks|") then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local m = ctx.metrics[key]
        if key:match("^tasks|") then
            nativePrint(string.format("%s TASKS %s callbacks=%d observed_work_calls=%d max_per_callback=%d max_frame=%d boot_steps_logged=%d boot_steps_max_per_callback=%d",
                TAG, key, m.calls, m.cpu, m.cpuMax, m.cpuFrame, m.wall, m.wallMax))
        else printMetric(m) end
    end
    ranked("require|", ctx.top, "cpu")
    ranked("engine-require|", ctx.top, "cpu")
    ranked("init|", ctx.top, "cpuMax")
    ranked("decode|", ctx.top, "cpuMax")
    ranked("update|", ctx.top, "cpuMax")
    ranked("draw|", ctx.top, "cpuMax")
    local totalFrames, totalTasks, maxTasks, maxTaskFrame = 0, 0, 0, 0
    for frame in pairs(ctx.observedFrames) do
        local tasks = ctx.frameWork[frame] or 0
        totalFrames, totalTasks = totalFrames + 1, totalTasks + tasks
        if tasks > maxTasks then maxTasks, maxTaskFrame = tasks, frame end
    end
    nativePrint(string.format("%s FRAME_WORK frames=%d observed_calls_total=%d max_Update_plus_Render=%d max_frame=%d includes_nested_export_calls=true scheduler_queue_length=false",
        TAG, totalFrames, totalTasks, maxTasks, maxTaskFrame))
    local eventKeys = {}
    for key in pairs(ctx.eventImageStats) do eventKeys[#eventKeys + 1] = key end
    table.sort(eventKeys)
    for _, key in ipairs(eventKeys) do
        local item = ctx.eventImageStats[key]
        nativePrint(string.format("%s FRAME_IMAGES %s callbacks=%d native_decodes=%d max_decodes_per_callback=%d max_frame=%d source_loads=%d post_Start_requests=%d",
            TAG, key, item.calls, item.decodes, item.max, item.maxFrame, item.loads, item.requests))
    end
    local owners = {}
    for _, item in pairs(ctx.imageOwners) do owners[#owners + 1] = item end
    table.sort(owners, function(a, b) return a.cpu == b.cpu and a.name < b.name or a.cpu > b.cpu end)
    for i = 1, math.min(ctx.top, #owners) do
        local item = owners[i]
        nativePrint(string.format("%s IMAGE_OWNER %s native_calls=%d cpu_total_ms=%.3f wall_total_ms=%.3f",
            TAG, item.name, item.calls, item.cpu, item.wall))
    end
    local townImages = {}
    for key, item in pairs(ctx.images) do
        if item.owner == "draw|ui.town.TownScene.draw" then townImages[#townImages + 1] = ctx.metrics["decode|" .. key] end
    end
    table.sort(townImages, function(a, b) return a.cpu == b.cpu and a.name < b.name or a.cpu > b.cpu end)
    for i = 1, math.min(ctx.top, #townImages) do printMetric(townImages[i]) end
    local saveKeys = {}
    for key in pairs(ctx.saveCalls) do saveKeys[#saveKeys + 1] = key end
    table.sort(saveKeys)
    for _, key in ipairs(saveKeys) do nativePrint(TAG .. " SAVE_STUB " .. key .. " calls=" .. ctx.saveCalls[key]) end
    local errors = {}
    for _, item in pairs(ctx.errors) do errors[#errors + 1] = item end
    table.sort(errors, function(a, b) return a.name .. a.message < b.name .. b.message end)
    for i = 1, math.min(ctx.top, #errors) do
        local item = errors[i]
        nativePrint(TAG .. " ERROR op=" .. item.name .. " count=" .. item.count .. " first_frame=" .. item.firstFrame
            .. " " .. item.message:sub(1, 1600):gsub("\n", " | "))
    end
    nativePrint(TAG .. " END CPU/wall callback costs only; not software-GPU FPS, device performance, or visual acceptance. Nested totals overlap.")
end
local function finish(reason)
    if ctx.done then return end
    ctx.done = true
    local ok, err = pcall(summarize, reason)
    if not ok then nativePrint(TAG .. " SUMMARY_EXCEPTION " .. tostring(err)) end
    engine:Exit() -- outside ALL pcall/xpcall; Runtime performs its real Stop lifecycle.
end
local function resetFrameCounters()
    ctx.initTasks, ctx.updateTasks, ctx.drawTasks, ctx.frameBootTasks = 0, 0, 0, 0
    ctx.frameLoads, ctx.frameImages, ctx.frameRequests = 0, 0, 0
end
local function afterUpdate()
    local title = ctx.modules["ui.story.gate.DarkTitleScreenGate"]
    if title and title.isReady() then
        if ctx.titleReadyFrame < 0 then ctx.titleReadyFrame = ctx.frames end
        if ctx.enter and not ctx.entered then
            ctx.entered = true
            measured("probe|tap-ready-title", title.handleTap)
        end
    end
    if ctx.bootDone and ctx.bootDoneFrame < 0 then ctx.bootDoneFrame = ctx.frames end
    ctx.phase = phase()
    if ctx.phase == "battle" and ctx.battleFirstFrame < 0 then ctx.battleFirstFrame = ctx.frames end
end
-- String-named production globals MUST resolve in env, not host _G. Register REAL
-- engine callbacks, forwarding the original event type/data and sender scope.
env.SubscribeToEvent = function(sender, eventName, callback)
    local scoped = type(sender) ~= "string"
    if not scoped then callback, eventName = eventName, sender end
    local function forward(eventType, eventData)
        if ctx.done then return end
        local fn = type(callback) == "string" and env[callback] or callback
        if type(fn) ~= "function" then capture("event", "missing env callback " .. tostring(callback)); finish("missing-callback"); return end
        local label = phase()
        if eventName == "Update" then
            ctx.frames = ctx.frames + 1
            ctx.renderPending = true
            resetFrameCounters()
            local dt = eventData["TimeStep"]:GetFloat()
            ctx.dtTotal, ctx.dtMax = ctx.dtTotal + dt, math.max(ctx.dtMax, dt)
        elseif eventName == "NanoVGRender" then
            ctx.renders = ctx.renders + 1
            resetFrameCounters()
        end
        local ok = guarded("event|" .. eventName .. "|" .. label, fn, eventType, eventData)
        if eventName == "Update" or eventName == "NanoVGRender" then tasksForFrame(eventName .. "|" .. label) end
        if not ok then finish("callback-error"); return end
        if eventName == "Update" then
            if label == "battle" then ctx.battleUpdates = ctx.battleUpdates + 1 end
            local observed = guarded("probe|observe", afterUpdate)
            if not observed then finish("control-error"); return end
            if ctx.frames >= ctx.maxFrames then ctx.endRequested = true end
        elseif eventName == "NanoVGRender" then
            if label == "battle" then ctx.battleRenders = ctx.battleRenders + 1 end
            ctx.renderPending = false
            local enough = ctx.enter and ctx.battleUpdates >= ctx.sampleFrames and ctx.battleRenders >= ctx.sampleFrames
                or not ctx.enter and ctx.bootDone and ctx.frames >= ctx.sampleFrames and ctx.renders >= ctx.sampleFrames
            if enough then finish("sample-complete")
            elseif ctx.endRequested then finish("frame-limit") end
        end
    end
    if scoped then return nativeSubscribe(sender, eventName, forward) end
    return nativeSubscribe(eventName, forward)
end
function Start()
    ctx.beginCpu, ctx.beginWall = nativeClock(), wall()
    for _, arg in ipairs(GetArguments()) do
        local root = arg:match("^%-tapcode_dir=(.+)$")
        if root then ctx.sourceRoot = root:gsub("/+$", "") end
        if arg == "-startup-enter" then ctx.enter = true end
        local key, value = arg:match("^%-startup%-([%a%-]+)=(%d+)$")
        local n = tonumber(value)
        if key == "frames" and n then ctx.sampleFrames = math.max(180, math.min(10000, math.floor(n)))
        elseif key == "max-frames" and n then ctx.maxFrames = math.max(180, math.min(20000, math.floor(n)))
        elseif key == "top" and n then ctx.top = math.max(1, math.min(20, math.floor(n))) end
    end
    ctx.maxFrames = math.max(ctx.maxFrames, ctx.sampleFrames)
    nativePrint(string.format("%s INPUT baseline=5fca1d82 source_root=%s mode=%s sample_frames=%d max_frames=%d seed=%d CPU=os.clock wall=time.elapsedTime save=isolated",
        TAG, ctx.sourceRoot, ctx.enter and "enter" or "title", ctx.sampleFrames, ctx.maxFrames, ctx.seed))
    math.randomseed(ctx.seed) -- exactly once; probe never draws random numbers or stops GC.
    local ok = guarded("probe|load-and-Start", function()
        local standalone = loadProject("boot.Standalone")
        ctx.started = true
        measured("probe|Standalone.Start", standalone.Start)
        installRequestHook()
    end)
    if not ok then finish("start-error"); return end
    -- End even if renderer never sends NanoVGRender (do NOT synthesize a draw).
    nativeSubscribe("PostUpdate", function()
        if ctx.done then return end
        if ctx.frames >= ctx.maxFrames and ctx.renderPending then finish("no-render/frame-limit") end
    end)
end
function Stop()
    if ctx.stopped then return end
    ctx.stopped = true
    if ctx.started then
        -- Remove ONLY our outer request hook, so real Standalone.Stop's identity
        -- checks can restore its own hooks. Stop() is called without fake arguments.
        if ctx.requestHookInstalled then env.nvgCreateImage = requestOriginal.value end
        local standalone = ctx.modules["boot.Standalone"]
        if standalone and standalone.Stop then
            local ok, err = guarded("probe|Standalone.Stop", standalone.Stop)
            nativePrint(TAG .. " STOP real_contract=true save=stub ok=" .. tostring(ok)
                .. (ok and "" or " error=" .. tostring(err):sub(1, 1200):gsub("\n", " | ")))
        end
    end
end
