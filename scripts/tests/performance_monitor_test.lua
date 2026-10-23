-- 性能诊断隔离专项：沿用 startup_save_test / auto_decompose_notice_test 的 Start+pcall 脚手架。
-- 只用 cache:GetFile 读取下面三份当前生产源码，完整 load 到私有 env；不复制监测算法。
-- 禁止 main / 业务真实 require / 玩家档 / 真 File、FS、云、网络；导出只写内存字典。
-- 官方 build 由主线程统一执行。本入口无需启动 main，无渲染，不修改生产或其它测试。
-- 构建后在专用空 cwd 运行：
-- /workspace/.cli/UrhoXRuntime tests/performance_monitor_test.lua -tapcode_dir=/workspace -tool_mode -nosound -graphicsheadless
local TAG = "[performance_monitor_test]"
local SOURCE_FILES = {
    ["core.PerformanceMonitor"] = "core/PerformanceMonitor.lua",
    ["boot.PerformanceRuntime"] = "boot/PerformanceRuntime.lua",
    ["boot.PerformanceHooks"] = "boot/PerformanceHooks.lua",
}
local nativeCache = cache
local nativeLoaded = package.loaded
local originalLoaded = {} ---@type table<string, any>
for name, value in pairs(nativeLoaded) do originalLoaded[name] = value end
local sources = {} ---@type table<string, string>
local reads = {} ---@type string[]
local contexts = {} ---@type any[]
local checks, groups, failed = 0, 0, 0
local function check(ok, label)
    checks = checks + 1
    assert(ok, label)
end
local function eq(a, b, label)
    check(a == b, label .. " actual=" .. tostring(a) .. " expected=" .. tostring(b))
end
local function near(a, b, label)
    check(type(a) == "number" and math.abs(a - b) < 0.000001,
        label .. " actual=" .. tostring(a) .. " expected=" .. tostring(b))
end
local function run(label, fn)
    groups = groups + 1
    local ok, why = pcall(fn)
    if not ok then failed = failed + 1 end
    print(TAG .. (ok and " PASS " or " FAIL ") .. label .. (ok and "" or ": " .. tostring(why)))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = copy(child) end
    return out
end
local function source(name)
    local path = assert(SOURCE_FILES[name], "source denied " .. tostring(name))
    if not sources[name] then
        local f = assert(nativeCache:GetFile(path), "missing current source " .. path)
        local ok, text = pcall(function()
            assert(f:IsOpen(), "source not open")
            local lines = {}
            while not f:IsEof() do lines[#lines + 1] = f:ReadLine() end
            return table.concat(lines, "\n")
        end)
        f:Dispose()
        assert(ok, text)
        sources[name], reads[#reads + 1] = text, path
    end
    return sources[name]
end
local function fixture()
    local f = { wallMs = 0, cpuSeconds = 0, wallReads = 0, cpuReads = 0, memoryReads = 0,
        requires = {}, loaded = {}, logs = {}, denied = {}, disk = {}, opens = 0, disposes = 0,
        closes = 0, writes = 0, fault = "", panelOpen = false, pointers = {}, panelUpdates = 0,
        resets = 0, calls = {}, mouse = { x = 700, y = 1000 },
        rt = { dpr = 2, frameScale = 0.5, frameOx = 50, frameOy = 100 } } ---@type any
    contexts[#contexts + 1] = f
    local env = {} ---@type any
    f.env = env
    for _, key in ipairs({ "assert", "error", "type", "pairs", "ipairs", "next", "tonumber", "tostring",
        "pcall", "xpcall", "select", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal" }) do
        env[key] = _G[key]
    end
    env.math, env.string, env.table = copy(math), copy(string), copy(table)
    env.coroutine = copy(coroutine) -- 真Lua协程调度，既不伪造yield能力，也不模拟监测算法。
    env._G = env
    env.cjson = { encode = cjson.encode, decode = cjson.decode }
    env.print = function(...) f.logs[#f.logs + 1] = table.pack(...) end
    local function deny(label)
        f.denied[#f.denied + 1] = label
        error("performance test forbids " .. label, 2)
    end
    local function blocked(label)
        return setmetatable({}, { __index = function(_, key) return deny(label .. "." .. tostring(key)) end })
    end
    for _, key in ipairs({ "io", "network", "clientCloud", "serverCloud", "http", "socket", "sdk", "debug", "engine" }) do
        env[key] = blocked(key)
    end
    for _, key in ipairs({ "load", "loadfile", "dofile", "GetFileSystem", "GetNetwork", "GetSubsystem",
        "SendEvent", "SendRemoteEvent", "SubscribeToEvent", "GetUserId", "GetUserNickname" }) do
        env[key] = function() return deny(key) end
    end
    env.os = { clock = function()
        f.cpuReads = f.cpuReads + 1
        if f.cpuFault then error("injected process clock failure", 0) end
        return f.cpuSeconds
    end }
    -- 原生绑定要求类静态调用 Time:GetSystemTime()，实例 time 调用必须是回归陷阱。
    env.Time = { GetSystemTime = function(receiver)
        assert(receiver == env.Time, "system clock must use the Time class receiver")
        f.wallReads = f.wallReads + 1
        if f.wallFault then error("injected system clock failure", 0) end
        return f.wallMs
    end }
    env.time = { GetSystemTime = function()
        f.legacyWallReads = (f.legacyWallReads or 0) + 1
        error("argument #1 is Time; Time expected (instance time clock forbidden)", 0)
    end }
    env.collectgarbage = function(kind)
        assert(kind == "count", "cannot collect real heap")
        f.memoryReads = f.memoryReads + 1
        return 2048
    end
    env.cache = blocked("cache")
    env.cache.GetTotalMemoryUse = function() return 4194304 end
    env.graphics = { GetNumBatches = function() return 7 end, GetNumPrimitives = function() return 19 end }
    env.MOUSEB_LEFT, env.MOUSEB_RIGHT = MOUSEB_LEFT, MOUSEB_RIGHT
    env.FILE_WRITE, env.FILE_READ = FILE_WRITE, FILE_READ
    local function allowed(path)
        assert(path == "performance_report.txt", "virtual file path denied " .. tostring(path))
    end
    env.File = function(path, mode)
        allowed(path); assert(mode == FILE_WRITE, "export mode must be FILE_WRITE")
        if f.fault == "open-throw" then error("injected open throw") end
        f.opens = f.opens + 1
        local disposed = false
        return {
            IsOpen = function()
                if f.fault == "isopen-throw" then error("injected IsOpen throw") end
                return f.fault ~= "open-false"
            end,
            WriteString = function(_, text)
                f.writes = f.writes + 1
                if f.fault == "write-throw" then error("injected write throw") end
                if f.fault == "write-false" then return false end
                f.disk[path] = text
                return true
            end,
            Close = function()
                f.closes = f.closes + 1
                if f.fault == "close-throw" then error("injected close throw") end
                return f.fault ~= "close-false"
            end,
            Dispose = function()
                assert(not disposed, "double Dispose")
                disposed = true
                f.disposes = f.disposes + 1
            end,
        }
    end
    -- FS形状保留在内存，但监测导出没有任何理由删除或改名文件。
    env.fileSystem = {
        FileExists = function(_, path) allowed(path); return f.disk[path] ~= nil end,
        Delete = function(_, path) allowed(path); return deny("fileSystem.Delete") end,
        Rename = function(_, from, to) allowed(from); allowed(to); return deny("fileSystem.Rename") end,
    }
    env.package = { loaded = f.loaded }
    env.input = { GetMousePosition = function() return f.mouse end }
    local panel = {
        isOpen = function() return f.panelOpen end,
        resetPointer = function() f.resets = f.resets + 1 end,
        update = function(dt)
            f.lastPanelDt = dt; f.panelUpdates = f.panelUpdates + 1
            if f.panelFault then error("injected Panel.update failure", 0) end
        end,
        handlePointer = function(kind, x, y, id)
            f.pointers[#f.pointers + 1] = { kind = kind, x = x, y = y, id = id }
            return f.consumeTail == true
        end,
    }
    local mocks = { ["ui.dev.PerformancePanel"] = panel, ["boot.StandaloneRT"] = f.rt }
    env.require = function(name)
        f.requires[#f.requires + 1] = name
        if mocks[name] then return mocks[name] end
        if not SOURCE_FILES[name] then return deny("require " .. tostring(name)) end
        if not f.loaded[name] then
            f.loaded[name] = assert(load(source(name), "@" .. SOURCE_FILES[name], "t", env))()
        end
        return f.loaded[name]
    end
    f.monitor = env.require("core.PerformanceMonitor")
    function f.advance(wallMs, cpuMs)
        f.wallMs = f.wallMs + wallMs
        f.cpuSeconds = f.cpuSeconds + (cpuMs or 0) / 1000
    end
    function f.frame(ms, context, exclusion)
        f.advance(ms)
        f.monitor.beginFrame(context or "城镇", exclusion)
    end
    function f.section(name, wallMs, cpuMs)
        local token = f.monitor.begin(name)
        f.advance(wallMs, cpuMs)
        f.monitor.finish(token)
    end
    return f
end
local function section(snapshot, name)
    for _, row in ipairs(snapshot.sections) do if row.name == name then return row end end
    error("missing real section " .. name)
end
local function event(values)
    return { GetInt = function(_, key) return values[key] or 0 end,
        GetFloat = function(_, key) return values[key] or 0 end,
        GetBool = function(_, key) return values[key] == true end }
end
local handlers = { "HandleUpdate", "HandleNanoVGRender", "HandleMouseButtonDown", "HandleMouseMove",
    "HandleMouseButtonUp", "HandleTouchBegin", "HandleTouchMove", "HandleTouchEnd", "HandleMouseWheel" }
local function runtime(f)
    for _, name in ipairs(handlers) do
        f.env[name] = function(...)
            f.calls[name] = (f.calls[name] or 0) + 1
            f.lastArgs = table.pack(...)
            return name, nil, "tail"
        end
    end
    local rt = f.env.require("boot.PerformanceRuntime")
    rt.installHandlers()
    return rt
end
local function stoppedWithoutClocks(f, label)
    local m = f.monitor
    eq(m.isEnabled(), false, label .. " diagnostic stopped")
    local s = m.snapshot()
    eq(s.enabled, false, label .. " snapshot stopped")
    eq(s.frames, 1, label .. " completed frame retained")
    eq(#s.sections, 0, label .. " failed/open work never committed")
    local wallReads, cpuReads, memoryReads = f.wallReads, f.cpuReads, f.memoryReads
    m.beginFrame("停止后"); eq(m.begin("停止后"), nil, label .. " stopped begin")
    m.finish(nil); eq(m.mark(), false, label .. " stopped mark")
    eq(f.wallReads, wallReads, label .. " stopped zero wall reads")
    eq(f.cpuReads, cpuReads, label .. " stopped zero CPU reads")
    eq(f.memoryReads, memoryReads, label .. " stopped zero memory reads")
end
local function keysOnly(value, allowed, label)
    local count = 0
    for key in pairs(value) do
        assert(allowed[key], label .. " unexpected private/unapproved key " .. tostring(key))
        count = count + 1
    end
    for key in pairs(allowed) do assert(value[key] ~= nil, label .. " missing key " .. key) end
    check(count > 0, label .. " exact nonempty whitelist")
end
local function keySet(text)
    local out = {}
    for key in text:gmatch("%S+") do out[key] = true end
    return out
end
local function reportData(text)
    local json = assert(text:match("%-%-%-PERFORMANCE_JSON_BEGIN%-%-%-\n(.-)\n%-%-%-PERFORMANCE_JSON_END%-%-%-"), "missing JSON delimiters")
    return cjson.decode(json)
end

function Start()
    local ok, why = pcall(function()
        run("default disabled / zero clocks / direct wrap", function()
            local f = fixture(); local m = f.monitor
            eq(m.isEnabled(), false, "default disabled")
            m.beginFrame("城镇"); eq(m.begin("unused"), nil, "disabled begin returns nil")
            m.finish(nil); m.excludeCurrent("panel"); eq(m.mark(), false, "disabled mark false")
            -- Disabled wrap must not even pack or pcall; these are private tripwires, not global patches.
            f.env.table.pack = function() error("disabled path packed") end
            f.env.pcall = function() error("disabled path pcalled") end
            local identity = {}
            local result = table.pack(m.wrap("disabled", function(a, b, c) return a, b, c, nil end)(identity, nil, 7)) ---@type any
            eq(result.n, 4, "disabled trailing nil count"); eq(result[1], identity, "disabled reference unchanged")
            eq(result[2], nil, "disabled middle nil"); eq(result[3], 7, "disabled value")
            local err = {}; local success, value = pcall(m.wrap("error", function() error(err, 0) end))
            eq(success, false, "disabled error propagates"); eq(value, err, "disabled error object unchanged")
            m.snapshot(); m.stop()
            eq(f.wallReads, 0, "default path zero system clock reads")
            eq(f.cpuReads, 0, "default path zero CPU clock reads")
            eq(f.memoryReads, 0, "default path zero memory reads")
        end)
        run("Update-to-Update / previous frame slow attribution / inclusive CPU-wall", function()
            local f = fixture(); local m = f.monitor
            m.start(); m.beginFrame("角色")
            local outer = m.begin("外层")
            f.advance(2, 1)
            local inner = m.begin("内层")
            f.advance(4, 2); m.finish(inner)
            f.advance(4, 1); m.finish(outer)
            f.frame(70, "仓库") -- 从上一Update起算80ms，不是分段10ms或游戏平滑dt。
            local s = m.snapshot()
            eq(s.frames, 1, "first anchor alone is not a frame")
            near(s.frameMs.max, 80, "real full interval includes uninstrumented gap")
            near(s.fps, 12.5, "FPS uses Update interval")
            near(section(s, "外层").totalCpuMs, 4, "outer process CPU")
            near(section(s, "外层").totalWallMs, 10, "outer inclusive sync wall")
            near(section(s, "内层").totalCpuMs, 2, "inner CPU independent")
            near(section(s, "内层").totalWallMs, 4, "inner included not subtracted")
            eq(s.recentSlow[1].context, "角色", "slow context belongs to previous frame")
            eq(s.recentSlow[1].top[1].name, "外层", "slow top belongs to previous sections")
            near(s.recentSlow[1].top[1].wallMs, 10, "wall never adds CPU to wall")
            f.section("下一帧", 1, 1); f.section("下一帧", 2, 0.5); f.frame(13)
            local nextStat = section(m.snapshot(), "下一帧")
            eq(nextStat.calls, 2, "same section repeated calls aggregate")
            near(nextStat.totalWallMs, 3, "repeated wall total")
            near(nextStat.totalCpuMs, 1.5, "repeated CPU total independent from wall")
            near(nextStat.maxWallMs, 2, "maximum is single call not total")
            eq(#m.snapshot().recentSlow, 1, "current next section cannot contaminate old slow frame")
            near(m.snapshot().luaMemoryKB, 2048, "fake Lua heap sampled")
            eq(m.snapshot().resourceMemoryBytes, 4194304, "resource memory is bytes")
        end)
        run("start-stop resets / stale tokens / incomplete frames", function()
            local f = fixture(); local m = f.monitor
            m.start(); m.beginFrame("城镇"); local stale = m.begin("未完成")
            f.frame(20); m.mark(); m.stop(); m.stop()
            eq(m.snapshot().frames, 1, "stop drops open frame and is idempotent")
            local readsBefore = f.wallReads + f.cpuReads
            m.finish(stale); f.frame(90000)
            eq(f.wallReads + f.cpuReads, readsBefore, "stop blocks stale finish and new frame clocks")
            m.start(); m.beginFrame("仓库"); m.finish(stale)
            local s = m.snapshot()
            eq(s.frames, 0, "restart frame counter reset"); eq(s.percentileWindowFrames, 0, "restart ring reset")
            eq(#s.sections, 0, "restart section reset"); eq(#s.recentSlow, 0, "restart slow reset")
            eq(#s.marks, 0, "restart mark reset"); eq(s.slowFrames.over33, 0, "restart threshold reset")
            eq(s.excludedGaps + s.excludedPanelFrames + s.droppedSections, 0, "restart exclusions reset")
            f.frame(16); eq(m.snapshot().frames, 1, "restart no stopped-time gap")
            local other = m.begin("跨帧"); f.frame(16); m.finish(other); f.frame(16)
            eq(#m.snapshot().sections, 0, "cross-frame token ignored")
        end)
        run("33-50-100 strict thresholds", function()
            for _, item in ipairs({ { 33, 0, 0, 0 }, { 34, 1, 0, 0 }, { 50, 1, 0, 0 },
                { 51, 1, 1, 0 }, { 100, 1, 1, 0 }, { 101, 1, 1, 1 } }) do
                local f = fixture(); f.monitor.start(); f.monitor.beginFrame("城镇"); f.frame(item[1])
                local s = f.monitor.snapshot()
                eq(s.slowFrames.over33, item[2], ">33.333 for " .. item[1])
                eq(s.slowFrames.over50, item[3], ">50 for " .. item[1])
                eq(s.slowFrames.over100, item[4], ">100 for " .. item[1])
                eq(#s.recentSlow, item[3], "slow details require >50")
            end
        end)
        run("P95-P99 known distribution / ring 3600", function()
            local f = fixture(); local m = f.monitor
            m.start(); m.beginFrame("城镇")
            -- 固定向量：100旧慢帧随后3600个10ms。期望是常量，不实现第二份分位数算法。
            for _ = 1, 100 do f.frame(80) end
            for _ = 1, 3600 do f.frame(10) end
            local s = m.snapshot()
            eq(s.frames, 3700, "lifetime frame count survives ring rollover")
            eq(s.percentileWindowFrames, 3600, "ring capped at 3600")
            near(s.frameMs.p95, 10, "P95 excludes overwritten old slow samples")
            near(s.frameMs.p99, 10, "P99 excludes overwritten old slow samples")
            near(s.frameMs.max, 80, "session maximum retained despite ring rollover")
            eq(s.slowFrames.over50, 100, "slow count remains lifetime")
            m.start(); m.beginFrame("城镇")
            for _ = 1, 94 do f.frame(10) end
            for _ = 1, 4 do f.frame(20) end
            f.frame(60); f.frame(120)
            s = m.snapshot()
            near(s.frameMs.p50, 10, "known-vector P50")
            near(s.frameMs.p95, 20, "known-vector P95")
            near(s.frameMs.p99, 60, "known-vector P99")
            near(s.frameMs.max, 120, "known-vector max")
        end)
        run("192 sections / 80 slow / 40 marks / 600 seconds", function()
            local f = fixture(); local m = f.monitor
            m.start(); m.beginFrame("城镇")
            for i = 1, 220 do f.section("段" .. i, 0, 0) end
            f.frame(60)
            eq(#m.snapshot().sections, 192, "per-frame sections bounded")
            for i = 1, 90 do f.section("新增" .. i, 0, 0); f.frame(60); m.mark("ignored payload") end
            local s = m.snapshot()
            eq(#s.sections, 192, "cross-frame section set bounded")
            check(s.droppedSections >= 118, "excess sections accounted")
            eq(#s.recentSlow, 80, "slow history bounded")
            eq(s.recentSlow[1].frame, 12, "old slow entries evicted")
            eq(#s.marks, 40, "marks bounded")
            eq(s.marks[1].frame, 52, "old marks evicted")
            eq(s.marks[40].frame, 91, "mark captures completed frames")
            near(s.marks[40].atSeconds, 5.46, "mark uses accepted sampling time")
            local g = fixture(); g.monitor.start(); g.monitor.beginFrame("城镇")
            for _ = 1, 600 do g.frame(1000) end
            s = g.monitor.snapshot()
            eq(g.monitor.isEnabled(), false, "600 second auto-stop")
            eq(s.frames, 600, "last complete frame retained")
            near(s.elapsedSeconds, 600, "duration bounded")
            check(s.stoppedReason:find("600", 1, true), "auto-stop reason")
            local before = g.wallReads; g.frame(1000); eq(g.wallReads, before, "auto-stop no further clocks")
        end)
        run("excluded panel-background frames never commit sections", function()
            local f = fixture(); local m = f.monitor
            m.start(); m.beginFrame("角色"); f.section("面板前污染", 1, 1)
            f.frame(100, "城镇", "panel")
            local readsBefore = f.wallReads + f.cpuReads
            eq(m.begin("面板中"), nil, "panel excluded begin")
            m.wrap("excluded", function() return 1 end)()
            eq(f.wallReads + f.cpuReads, readsBefore, "excluded wrappers skip clocks")
            f.frame(100); f.section("后台前污染", 1, 1); m.excludeCurrent("background")
            f.frame(900000, "城镇", "background"); f.frame(100)
            f.section("有效", 2, 1); f.frame(14)
            local s = m.snapshot()
            eq(s.frames, 1, "both entry-exit boundary intervals excluded")
            eq(s.excludedPanelFrames, 2, "panel entry and exit accounted")
            eq(s.excludedGaps, 2, "background entry and exit accounted")
            eq(#s.sections, 1, "excluded section data never counted")
            eq(s.sections[1].name, "有效", "only accepted section remains")
            near(s.elapsedSeconds, 0.016, "background never advances sampling duration")
            eq(m.isEnabled(), true, "background long gap does not consume 600 accepted seconds")
            -- 无效非正间隔也不能提交该帧分段。
            f.section("零间隔", 0, 0); f.frame(0); f.section("倒时钟", 0, 0); f.frame(-1)
            eq(m.snapshot().frames, 1, "zero/backwards clock intervals not frames")
            eq(#m.snapshot().sections, 1, "invalid intervals do not commit sections")
        end)
        run("snapshot deep copies / mark cannot retain payload", function()
            local f = fixture(); local m = f.monitor
            m.start(); m.beginFrame("角色"); f.section("工作", 5, 2); f.frame(55); m.mark({ name = "PRIVATE_SENTINEL" })
            local s = m.snapshot()
            s.frameMs.max, s.slowFrames.over50, s.sections[1].totalWallMs = -1, -1, -1
            s.recentSlow[1].top[1].name, s.marks[1].frame, s.limits.sections = "mutated", -1, -1
            s.timing.gpu = "mutated"; s.sections[2] = { name = "injected" }
            local t = m.snapshot()
            near(t.frameMs.max, 60, "frame stats copy"); eq(t.slowFrames.over50, 1, "counter copy")
            near(t.sections[1].totalWallMs, 5, "section copy"); eq(#t.sections, 1, "section list copy")
            eq(t.recentSlow[1].top[1].name, "工作", "nested slow-top copy")
            eq(t.marks[1].frame, 1, "nested mark copy"); eq(t.limits.sections, 192, "limits copy")
            eq(t.timing.gpu, "not_sampled", "timing copy")
            keysOnly(t.marks[1], keySet("frame atSeconds"), "mark payload privacy")
        end)
        run("report readable text / real JSON / exact privacy whitelist", function()
            local f = fixture(); local m = f.monitor
            -- 私有玩家数据只是陷阱；生产模块不能访问宿主真实资料。
            f.env.player = { userId = "PRIVATE_SENTINEL", name = "PRIVATE_SENTINEL", wallet = { gold = 999 } }
            f.loaded["ui.character.panel.CharacterPanel"] = { isDetailOpen = function() return true end,
                playerName = "PRIVATE_SENTINEL", payload = f.env.player }
            local rt = runtime(f)
            m.start(); rt.updateBefore(); f.section("主循环.Update", 4, 2); f.advance(60); rt.updateBefore(); m.mark(f.env.player)
            local text = m.getReport()
            eq(m.isEnabled(), false, "getReport stops collection")
            check(text:find("inclusive", 1, true) and text:find("CPU", 1, true) and text:find("GPU", 1, true), "report caveats readable")
            check(not text:find("PRIVATE_SENTINEL", 1, true), "report never serializes player/module payload")
            local s = reportData(text)
            keysOnly(s, keySet("schemaVersion monitorVersion enabled stoppedReason elapsedSeconds frames fps frameMs percentileWindowFrames slowFrames luaMemoryKB resourceMemoryBytes batches primitives sections recentSlow marks excludedGaps excludedPanelFrames droppedSections limits timing"), "report root")
            keysOnly(s.frameMs, keySet("p50 p95 p99 max"), "frame stats")
            keysOnly(s.slowFrames, keySet("over33 over50 over100"), "threshold stats")
            keysOnly(s.limits, keySet("frames slowFrames marks sections seconds"), "limits")
            keysOnly(s.timing, keySet("frame sections gpu memory"), "timing")
            keysOnly(s.sections[1], keySet("name calls totalCpuMs maxCpuMs totalWallMs maxWallMs"), "section")
            keysOnly(s.recentSlow[1], keySet("frame intervalMs context top"), "slow frame")
            keysOnly(s.recentSlow[1].top[1], keySet("name cpuMs wallMs calls"), "slow top")
            keysOnly(s.marks[1], keySet("frame atSeconds"), "report mark")
            eq(s.recentSlow[1].context, "角色", "runtime uses fixed context enum not payload")
            near(s.sections[1].totalWallMs, 4, "JSON real production numbers")
            eq(m.getReport(), text, "report cached consistently")
            m.start(); local fresh = m.getReport(); eq(reportData(fresh).frames, 0, "restart clears report cache")
            check(fresh:find("尚无有效帧", 1, true), "empty-report guidance")
            local g = fixture(); g.env.cjson.encode = function() error("injected JSON error") end
            local fallback = g.monitor.getReport()
            check(fallback:find("JSON编码失败", 1, true), "JSON failure provides readable fallback")
        end)
        run("export fixed virtual file / all failures dispose", function()
            local f = fixture(); local m = f.monitor
            local success, path = m.export("standalone_save.json")
            eq(success, true, "export successful"); eq(path, "performance_report.txt", "fixed file name ignores caller path")
            eq(f.opens, 1, "one file"); eq(f.disposes, 1, "success Dispose"); eq(f.closes, 1, "success Close")
            eq(reportData(f.disk[path]).frames, 0, "export is parseable same report")
            eq(next(f.disk), "performance_report.txt", "only allowed dictionary key")
            for _, fault in ipairs({ "open-throw", "isopen-throw", "open-false", "write-throw", "write-false", "close-throw", "close-false" }) do
                local g = fixture(); g.fault = fault
                local result, err = g.monitor.export()
                eq(result, false, "export fault " .. fault)
                check(type(err) == "string" and #err > 0, "export error detail " .. fault)
                eq(g.disposes, g.opens, "all returned handles released " .. fault)
            end
        end)
        run("enabled wrap preserves nil-multiple returns and error identity", function()
            local f = fixture(); local m = f.monitor
            m.start(); m.beginFrame("城镇")
            local ref = {}; local args = table.pack(ref, nil, 7, nil)
            local fn = m.wrap("成功", function(...)
                local actual = table.pack(...) ---@type any
                eq(actual.n, 4, "argument count"); eq(actual[1], ref, "argument identity")
                eq(actual[2], nil, "argument nil"); eq(actual[3], 7, "argument value")
                f.advance(5, 2); return nil, ref, nil, 9, nil
            end)
            local values = table.pack(fn(table.unpack(args, 1, args.n))) ---@type any
            eq(values.n, 5, "enabled return count"); eq(values[1], nil, "first return nil")
            eq(values[2], ref, "return identity"); eq(values[3], nil, "middle return nil")
            eq(values[4], 9, "return value"); eq(values[5], nil, "trailing return nil")
            eq(table.pack(m.wrap("无返回", function() end)()).n, 0, "zero returns remain zero")
            local err = {}; local success, caught = pcall(m.wrap("异常", function() f.advance(3, 1); error(err, 0) end))
            eq(success, false, "enabled errors propagate"); eq(caught, err, "error object unchanged")
            f.frame(8); local s = m.snapshot()
            eq(section(s, "异常").calls, 1, "throwing work still measured")
            near(section(s, "异常").totalWallMs, 3, "throw duration measured")
            near(section(s, "成功").totalCpuMs, 2, "wrap CPU measured")
        end)
        for _, stage in ipairs({ "begin", "finish" }) do
            run("wrap " .. stage .. " clock throws / business once / nils and errors", function()
                for _, clock in ipairs({ "wall", "cpu" }) do
                    for _, businessThrows in ipairs({ false, true }) do
                        local f = fixture(); local m = f.monitor
                        local label = stage .. "/" .. clock .. (businessThrows and "/business-error" or "/returns")
                        m.start(); m.beginFrame("城镇"); f.frame(16)
                        local calls = 0
                        local ref, businessError = {}, {}
                        local function injectClockFault()
                            if clock == "wall" then f.wallFault = true else f.cpuFault = true end
                        end
                        local wrapped = m.wrap("故障段", function(...)
                            calls = calls + 1
                            local args = table.pack(...) ---@type any
                            eq(args.n, 4, label .. " argument count")
                            eq(args[1], ref, label .. " argument reference")
                            eq(args[2], nil, label .. " middle argument nil")
                            eq(args[3], 7, label .. " argument value")
                            eq(args[4], nil, label .. " trailing argument nil")
                            if calls == 1 then
                                if stage == "begin" then
                                    eq(m.isEnabled(), false, label .. " fail stops before fallback business")
                                else
                                    eq(m.isEnabled(), true, label .. " begin succeeded before business")
                                    injectClockFault() -- 只有生产finish调用时钟时才抛；不替换begin/finish算法。
                                end
                            end
                            f.advance(3, 1)
                            if businessThrows then error(businessError, 0) end
                            return nil, ref, nil, 9, nil
                        end)
                        local wallBefore, cpuBefore = f.wallReads, f.cpuReads
                        if stage == "begin" then injectClockFault() end
                        local result = table.pack(pcall(wrapped, ref, nil, 7, nil)) ---@type any
                        eq(calls, 1, label .. " business called exactly once")
                        if businessThrows then
                            eq(result[1], false, label .. " business error propagates")
                            eq(result[2], businessError, label .. " business error identity survives diagnostic fault")
                            eq(result.n, 2, label .. " no extra error returns")
                        else
                            eq(result[1], true, label .. " diagnostic failure cannot escape")
                            eq(result.n, 6, label .. " complete return count including pcall")
                            eq(result[2], nil, label .. " first return nil")
                            eq(result[3], ref, label .. " return reference")
                            eq(result[4], nil, label .. " middle return nil")
                            eq(result[5], 9, label .. " return value")
                            eq(result[6], nil, label .. " trailing return nil")
                        end
                        check(clock == "wall" and f.wallReads > wallBefore or clock == "cpu" and f.cpuReads > cpuBefore,
                            label .. " injected clock actually reached")
                        stoppedWithoutClocks(f, label)
                        local wallReads, cpuReads = f.wallReads, f.cpuReads
                        local after = table.pack(pcall(wrapped, ref, nil, 7, nil)) ---@type any
                        eq(calls, 2, label .. " stopped wrapper still calls business once")
                        eq(after[1], not businessThrows, label .. " stopped path preserves outcome")
                        if businessThrows then eq(after[2], businessError, label .. " stopped error identity")
                        else eq(after.n, 6, label .. " stopped path retains nil return count") end
                        eq(f.wallReads, wallReads, label .. " stopped wrap zero wall reads")
                        eq(f.cpuReads, cpuReads, label .. " stopped wrap zero CPU reads")
                    end
                end
            end)
        end
        for _, fault in ipairs({ "context", "explicit-context", "beginFrame", "Panel.update" }) do
            run("runtime " .. fault .. " throws / original Update preserved", function()
                for _, businessThrows in ipairs({ false, true }) do
                    local f = fixture(); local rt = runtime(f); local m = f.monitor
                    local label = fault .. (businessThrows and "/business-error" or "/returns")
                    m.start(); m.beginFrame("城镇"); f.frame(16)
                    local getterCalls = 0
                    if fault == "context" or fault == "explicit-context" then
                        local getter = { isDetailOpen = function()
                            getterCalls = getterCalls + 1
                            error("injected context getter failure", 0)
                        end }
                        if fault == "explicit-context" then
                            f.env.require("boot.PerformanceHooks").register({ ["ui.character.panel.CharacterPanel"] = getter })
                        else f.loaded["ui.character.panel.CharacterPanel"] = getter end
                    elseif fault == "beginFrame" then f.wallFault = true
                    else f.panelFault = true end
                    local businessError, ref = {}, {}
                    local updateEvent = event({ TimeStep = 0.025 })
                    f.env.HandleUpdate = function(kind, data)
                        f.calls.HandleUpdate = (f.calls.HandleUpdate or 0) + 1
                        eq(kind, "Update", label .. " event type preserved")
                        eq(data, updateEvent, label .. " event identity preserved")
                        eq(m.isEnabled(), false, label .. " diagnostic stops before original Update")
                        if businessThrows then error(businessError, 0) end
                        return nil, ref, nil, 9, nil
                    end
                    rt.installHandlers()
                    local result = table.pack(pcall(f.env.HandleUpdate, "Update", updateEvent)) ---@type any
                    eq(f.calls.HandleUpdate, 1, label .. " original Update called exactly once")
                    if businessThrows then
                        eq(result[1], false, label .. " original Update error propagates")
                        eq(result[2], businessError, label .. " original error identity retained")
                        eq(result.n, 2, label .. " only original business error returned")
                    else
                        eq(result[1], true, label .. " diagnostic error cannot block original Update")
                        eq(result.n, 6, label .. " original nil return count")
                        eq(result[2], nil, label .. " first return nil")
                        eq(result[3], ref, label .. " reference return retained")
                        eq(result[4], nil, label .. " middle return nil")
                        eq(result[5], 9, label .. " value return retained")
                        eq(result[6], nil, label .. " trailing return nil")
                    end
                    if fault == "context" or fault == "explicit-context" then eq(getterCalls, 1, label .. " actual resolved-module getter threw") end
                    if fault == "beginFrame" then eq(f.wallReads, 3, label .. " actual frame clock threw") end
                    if fault == "Panel.update" then
                        eq(f.panelUpdates, 1, label .. " actual panel update threw")
                        near(f.lastPanelDt, 0.025, label .. " original panel dt preserved")
                    end
                    stoppedWithoutClocks(f, label)
                    local wallReads, cpuReads = f.wallReads, f.cpuReads
                    local again = table.pack(pcall(f.env.HandleUpdate, "Update", updateEvent)) ---@type any
                    eq(f.calls.HandleUpdate, 2, label .. " later Update still called exactly once")
                    eq(again[1], not businessThrows, label .. " later Update keeps original outcome")
                    if businessThrows then eq(again[2], businessError, label .. " later business error retained")
                    else eq(again.n, 6, label .. " later nil returns retained") end
                    eq(f.wallReads, wallReads, label .. " later Update zero wall reads")
                    eq(f.cpuReads, cpuReads, label .. " later Update zero CPU reads")
                    if fault == "context" or fault == "explicit-context" then eq(getterCalls, 1, label .. " stopped diagnostic never calls getter again") end
                end
            end)
        end
        run("yieldable coroutine skipped / outer resume measured per frame", function()
            local f = fixture(); local m = f.monitor
            m.start(); m.beginFrame("城镇")
            local ref = {}
            ---@async
            local function coroutineBody(arg)
                eq(arg, ref, "coroutine argument unchanged")
                check(coroutine.isyieldable(), "test uses genuinely yieldable Lua coroutine")
                f.advance(5, 2)
                local resumed = coroutine.yield("pause", nil, ref)
                eq(resumed, "continue", "resume value preserved")
                f.advance(7, 3)
                return nil, ref, nil
            end
            local wrappedCoroutine = m.wrap("协程内层", coroutineBody)
            local co = coroutine.create(wrappedCoroutine)
            local resume = m.wrap("本地动作.updateQuickEquip", function(...) return coroutine.resume(co, ...) end)
            local first = table.pack(resume(ref)) ---@type any
            eq(first.n, 4, "yielded values and nil count preserved")
            eq(first[1], true, "first resume succeeds"); eq(first[2], "pause", "yield marker preserved")
            eq(first[3], nil, "yield nil preserved"); eq(first[4], ref, "yield identity preserved")
            eq(coroutine.status(co), "suspended", "real coroutine suspended")
            f.advance(100, 40) -- 其它主线程工作/等待发生在yield期间，不能记到内层或resume段。
            f.frame(0)
            local s = m.snapshot()
            local a = section(s, "本地动作.updateQuickEquip")
            eq(a.calls, 1, "first-frame outer resume committed")
            near(a.totalCpuMs, 2, "first resume excludes yielded-time CPU")
            near(a.totalWallMs, 5, "first resume excludes yielded-time wall")
            eq(#s.sections, 1, "yieldable inner section deliberately not measured")
            eq(s.recentSlow[1].top[1].name, "本地动作.updateQuickEquip", "slow frame keeps synchronous outer resume")
            local second = table.pack(resume("continue")) ---@type any
            eq(second.n, 4, "completion nils preserved")
            eq(second[1], true, "second resume succeeds"); eq(second[2], nil, "completion first nil")
            eq(second[3], ref, "completion identity"); eq(second[4], nil, "completion trailing nil")
            eq(coroutine.status(co), "dead", "coroutine really completed")
            f.frame(9)
            s = m.snapshot(); local b = section(s, "本地动作.updateQuickEquip")
            eq(s.frames, 2, "two separate Update frames committed")
            eq(b.calls, 2, "second-frame outer resume not lost")
            near(b.totalCpuMs, 5, "sum only CPU during two resumes, not yielded CPU40ms")
            near(b.totalWallMs, 12, "sum only synchronous resume wall")
            near(b.maxWallMs, 7, "maximum individual resume")
            eq(#s.sections, 1, "no cross-frame coroutine inner attribution")
            check(m.getReport():find("协程", 1, true), "report discloses coroutine measurement boundary")
        end)
        run("runtime modal mouse-touch-wheel / DPR / handler idempotence", function()
            local f = fixture(); local rt = runtime(f)
            local identities = {}
            for _, name in ipairs(handlers) do identities[name] = f.env[name] end
            rt.installHandlers()
            for _, name in ipairs(handlers) do eq(f.env[name], identities[name], "runtime idempotent " .. name) end
            local e = event({ Button = MOUSEB_LEFT, X = 700, Y = 1000, TouchID = 17 })
            for _, name in ipairs(handlers) do
                if name ~= "HandleUpdate" and name ~= "HandleNanoVGRender" then
                    f.env[name]("event", e)
                    eq(f.calls[name], 1, "closed panel passes " .. name)
                end
            end
            local updateEvent = event({ TimeStep = 0.025 })
            ---@type table
            local result = table.pack(f.env.HandleUpdate("Update", updateEvent))
            near(f.lastPanelDt, 0.025, "panel receives original real Update dt")
            eq(result.n, 3, "Update return count preserved"); eq(result[1], "HandleUpdate", "Update original called")
            eq(result[2], nil, "Update nil preserved"); eq(f.lastArgs[2], updateEvent, "original event identity")
            eq(f.wallReads + f.cpuReads, 0, "runtime disabled never reads clocks")
            eq(#f.pointers, 6, "closed panel may inspect unconsumed pointer events")
            f.pointers = {}
            f.panelOpen = true
            for _, name in ipairs({ "HandleMouseButtonDown", "HandleMouseMove", "HandleMouseButtonUp", "HandleTouchBegin", "HandleTouchMove", "HandleTouchEnd", "HandleMouseWheel" }) do
                f.env[name]("event", e)
                eq(f.calls[name], 1, "open modal swallows " .. name)
            end
            eq(#f.pointers, 6, "six pointer routes no wheel")
            for i, expected in ipairs({ "down", "move", "up", "down", "move", "up" }) do
                ---@type any
                local p = assert(f.pointers[i], "missing routed pointer " .. i)
                eq(p.kind, expected, "pointer kind " .. i)
                near(p.x, 600, "physical to design X DPR offset scale " .. i)
                near(p.y, 800, "physical to design Y DPR offset scale " .. i)
                eq(p.id, i <= 3 and "mouse" or 17, "pointer identity " .. i)
            end
            f.env.HandleMouseButtonDown("event", event({ Button = MOUSEB_RIGHT }))
            eq(#f.pointers, 6, "right button swallowed without panel click")
            eq(f.calls.HandleMouseButtonDown, 1, "right button never reaches business")
            f.rt.frameScale = -1
            f.env.HandleTouchMove("event", e)
            near(f.pointers[7].x, 300, "nonpositive scale falls back to one")
            f.rt.dpr, f.rt.frameScale, f.rt.frameOx, f.rt.frameOy = nil, nil, nil, nil
            f.env.HandleTouchMove("event", e)
            near(f.pointers[8].x, 700, "missing transform falls back to identity")
            f.panelOpen, f.consumeTail = false, true
            f.env.HandleTouchEnd("event", e)
            eq(f.calls.HandleTouchEnd, 1, "panel close still swallows tracked touch tail")
            f.env.HandleMouseButtonUp("event", e)
            eq(f.calls.HandleMouseButtonUp, 1, "panel close still swallows tracked mouse tail")
            f.consumeTail = false
            f.env.HandleTouchEnd("event", e)
            eq(f.calls.HandleTouchEnd, 2, "untracked post-close touch reaches business")
        end)
        run("runtime restores redefined globals without double wrapping peers", function()
            local f = fixture(); local rt = runtime(f); local m = f.monitor
            local identities = {}
            for _, name in ipairs(handlers) do identities[name] = f.env[name] end
            local updates, downs = 0, 0
            local newUpdate = function(_, e)
                updates = updates + 1; near(e:GetFloat("TimeStep"), 0.02, "replaced Update keeps event data")
                f.advance(2, 1); return "new-update", nil, 9
            end
            local newDown = function(_, _) downs = downs + 1; f.advance(1, 0.5); return "new-down", nil end
            f.env.HandleUpdate, f.env.HandleMouseButtonDown = newUpdate, newDown
            rt.installHandlers()
            check(f.env.HandleUpdate ~= newUpdate, "redefined Update rewrapped")
            check(f.env.HandleMouseButtonDown ~= newDown, "redefined input rewrapped")
            for _, name in ipairs(handlers) do
                if name ~= "HandleUpdate" and name ~= "HandleMouseButtonDown" then
                    eq(f.env[name], identities[name], "unchanged peer retains wrapper identity " .. name)
                end
            end
            local updateIdentity, inputIdentity = f.env.HandleUpdate, f.env.HandleMouseButtonDown
            rt.installHandlers()
            eq(f.env.HandleUpdate, updateIdentity, "restored Update reinstall idempotent")
            eq(f.env.HandleMouseButtonDown, inputIdentity, "restored input reinstall idempotent")
            m.start()
            local e = event({ TimeStep = 0.02, Button = MOUSEB_LEFT })
            local result = table.pack(f.env.HandleUpdate("Update", e)) ---@type any
            eq(result.n, 3, "new Update return count"); eq(result[1], "new-update", "new Update return")
            local inputResult = table.pack(f.env.HandleMouseButtonDown("down", e)) ---@type any
            eq(inputResult.n, 2, "new input nil return count")
            eq(inputResult[1], "new-down", "new input called")
            f.env.HandleNanoVGRender("render", e)
            f.advance(13)
            f.env.HandleUpdate("Update", e)
            local s = m.snapshot()
            eq(s.frames, 1, "restored Update establishes exactly one frame per event")
            eq(updates, 2, "new Update called once per event")
            eq(f.calls.HandleUpdate, nil, "old Update no longer called")
            eq(downs, 1, "new input called exactly once")
            eq(f.calls.HandleMouseButtonDown, nil, "old input no longer called")
            eq(section(s, "主循环.Update").calls, 1, "Update not double measured")
            eq(section(s, "输入.HandleMouseButtonDown").calls, 1, "replaced input not double measured")
            eq(section(s, "主循环.NanoVGRender").calls, 1, "unchanged render not double measured")
            eq(f.panelUpdates, 2, "reinstall does not duplicate updateBefore")
            f.panelOpen = true
            f.env.HandleMouseButtonDown("down", e)
            eq(downs, 1, "reinstalled input retains modal interception")
        end)
        run("runtime focus-panel exclusions and Update interval", function()
            local f = fixture(); local rt = runtime(f); local m = f.monitor
            m.start(); f.env.HandleUpdate("Update", event({ TimeStep = 0.001 }))
            f.advance(80); f.env.HandleUpdate("Update", event({ TimeStep = 0.001 }))
            near(m.snapshot().frameMs.max, 80, "runtime ignores game dt smoothing")
            f.section("失焦污染", 1, 1)
            rt.focus(event({ Focus = false, Minimized = false }))
            f.advance(999999); f.env.HandleUpdate("Update", event({}))
            rt.focus(event({ Focus = true, Minimized = false }))
            f.advance(1); f.env.HandleUpdate("Update", event({}))
            f.panelOpen = true; f.advance(60); f.env.HandleUpdate("Update", event({}))
            f.panelOpen = false; f.advance(60); f.env.HandleUpdate("Update", event({}))
            local s = m.snapshot()
            eq(s.frames, 1, "runtime panel-background excluded from valid samples")
            eq(s.excludedGaps, 2, "runtime focus boundary exclusions")
            eq(s.excludedPanelFrames, 2, "runtime panel boundary exclusions")
            eq(f.resets, 2, "focus changes reset active pointer")
            for _, row in ipairs(s.sections) do check(row.name ~= "失焦污染", "focus sections excluded") end
        end)
        run("Hooks only loaded modules / no eager business / idempotence", function()
            local f = fixture(); local hooks = f.env.require("boot.PerformanceHooks")
            hooks.install()
            eq(#f.requires, 3, "Hooks require only self and Monitor")
            eq(f.loaded["ui.battle.scene.BattleScene"], nil, "not eagerly loaded battle")
            local calls = 0
            local business = { update = function(a) calls = calls + 1; f.advance(3, 1); return a, nil, 5 end }
            f.loaded["ui.battle.scene.BattleScene"] = business
            local original = business.update
            hooks.install(); check(business.update ~= original, "late-loaded module gets wrapper")
            local wrapped = business.update; hooks.install(); eq(business.update, wrapped, "no double wrapping")
            eq(#f.requires, 3, "installation never requires business")
            f.monitor.start(); f.monitor.beginFrame("主线战斗")
            local values = table.pack(business.update("arg")) ---@type any
            f.frame(13)
            eq(calls, 1, "business called once"); eq(values.n, 3, "hook multiple returns")
            eq(values[1], "arg", "hook arg identity"); eq(values[2], nil, "hook nil preserved")
            eq(section(f.monitor.snapshot(), "主线战斗.update").calls, 1, "one timing record after repeated install")
        end)
        run("Hooks explicit references with empty loaded / precedence / replacement", function()
            local f = fixture(); local hooks = f.env.require("boot.PerformanceHooks")
            local calls = 0
            local business = { update = function(ref) calls = calls + 1; f.advance(3, 1); return ref, nil end }
            local name = "ui.battle.scene.BattleScene"
            eq(f.loaded[name], nil, "realistic cache has no business module")
            hooks.installStandalone({ BattleScene = business })
            eq(hooks.getModule(name), business, "registered exact table reachable without loaded entry")
            eq(f.loaded[name], nil, "registry does not fabricate package.loaded entries")
            local wrapped = business.update
            eq(hooks.install(), 0, "boot completion reinstall adds no duplicate wrappers")
            eq(business.update, wrapped, "registered wrapper identity stable")
            local fallback = { update = function() error("wrong fallback used", 0) end }
            f.loaded[name] = fallback
            hooks.install(); eq(hooks.getModule(name), business, "explicit reference beats shadow cache")
            eq(business.update, wrapped, "shadow cache cannot change live wrapper")
            local ref = {}
            f.monitor.start(); f.monitor.beginFrame("主线战斗")
            local result = table.pack(business.update(ref)) ---@type any
            eq(calls, 1, "explicit business called once"); eq(result.n, 2, "trailing nil preserved")
            eq(result[1], ref, "explicit business argument identity")
            f.frame(60)
            eq(section(f.monitor.snapshot(), "主线战斗.update").calls, 1, "explicit section measured")
            business.update = function() calls = calls + 1; return "replaced" end
            eq(hooks.install(), 1, "init-redefined export repaired by second install")
            local repaired = business.update
            hooks.install(); eq(business.update, repaired, "repaired export not double wrapped")
            eq(business.update(), "replaced", "replacement semantics retained")
            local fresh = { update = function() return "new-table" end }
            hooks.install({ [name] = fresh })
            eq(hooks.getModule(name), fresh, "hot-reloaded explicit table can replace registration")
            eq(fresh.update(), "new-table", "new explicit table wrapped")
            hooks.register({ [name] = false })
            eq(hooks.getModule(name), fresh, "invalid registration cannot hide live table")
            f.loaded["not-a-module"] = true
            eq(hooks.getModule("not-a-module"), nil, "non-table cache marker ignored")
            eq(#f.requires, 3, "all explicit installs require no business")
        end)
        run("Hooks expanded synchronous coarse exports / empty cache", function()
            local f = fixture(); local hooks = f.env.require("boot.PerformanceHooks")
            local specs = {
                { "ui.character.panel.CharacterPanel", "角色面板", { "updateBadges", "addHeroesExp", "finishExtraTalentBatch" } },
                { "ui.battle.tri.BattleTriPage", "三队总览", { "drawL1Underlay", "drawL0", "drawHud", "refreshHeroProgressTeams" } },
                { "ui.story.ScenarioDialogue", "剧情对话", { "update", "draw" } },
                { "systems.TutorialManager", "新手引导", { "update", "draw" } },
                { "ui.character.hero.HeroRosterPanel", "英雄名册", { "draw" } },
            }
            local modules, originals = {}, {}
            for _, spec in ipairs(specs) do
                local module = {} ---@type table<string, function>
                for _, key in ipairs(spec[3]) do
                    local label = spec[2] .. "." .. key
                    module[key] = function(a, b) f.advance(2, 1); return a, nil, b, nil end
                    originals[label] = module[key]
                end
                modules[spec[1]] = module
            end
            eq(hooks.install(modules), 12, "all requested coarse exports installed")
            eq(hooks.install(), 0, "all coarse exports idempotent")
            f.monitor.start(); f.monitor.beginFrame("角色/三队战斗")
            local ref = {}
            for _, spec in ipairs(specs) do
                local module = modules[spec[1]]
                eq(f.loaded[spec[1]], nil, "business cache remains empty")
                for _, key in ipairs(spec[3]) do
                    local label = spec[2] .. "." .. key
                    check(module[key] ~= originals[label], "wrapped " .. label)
                    local result = table.pack(module[key](ref, 7)) ---@type any
                    eq(result.n, 4, "coarse returns " .. label)
                    eq(result[1], ref, "coarse reference " .. label); eq(result[3], 7, "coarse arg " .. label)
                end
            end
            f.frame(60)
            local snapshot = f.monitor.snapshot()
            eq(#snapshot.sections, 12, "every coarse export reachable in actual Monitor")
            for _, spec in ipairs(specs) do
                for _, key in ipairs(spec[3]) do
                    eq(section(snapshot, spec[2] .. "." .. key).calls, 1, "one call per expanded export")
                end
            end
        end)
        run("Runtime explicit contexts / CharacterPanel detail getter / cache fallback", function()
            local f = fixture(); local rt = runtime(f); local hooks = f.env.require("boot.PerformanceHooks")
            local states = { detail = true, roster = true, story = true, tutorial = true, sweep = false }
            local name = "ui.character.panel.CharacterPanel"
            local character = { isDetailOpen = function() return states.detail end,
                isOpen = function() error("CharacterPanel has no isOpen API", 0) end }
            hooks.register({ [name] = character,
                ["ui.character.hero.HeroRosterPanel"] = { isVisible = function() return states.roster end },
                ["ui.story.ScenarioDialogue"] = { isActive = function() return states.story end },
                ["systems.TutorialManager"] = { isActive = function() return states.tutorial end },
                ["runtime.LocalActionBridge"] = { isSweepPending = function() return states.sweep end } })
            eq(f.loaded[name], nil, "context available with empty cache")
            f.loaded[name] = { isDetailOpen = function() error("shadow cache queried", 0) end }
            local m = f.monitor
            m.start(); rt.updateBefore(0.01); f.advance(60)
            states.detail, states.roster, states.story, states.tutorial = false, false, false, false
            rt.updateBefore(0.01)
            eq(m.snapshot().recentSlow[1].context, "角色/英雄名册/剧情对话/新手引导", "fixed explicit context enums combined")
            f.advance(60); states.sweep = true; rt.updateBefore(0.01)
            eq(m.snapshot().recentSlow[2].context, "标题/城镇/其他", "closed detail not permanently tagged character")
            f.advance(60); states.sweep = false
            f.loaded["ui.backpack.BackpackPanel"] = { isOpen = function() return true end }
            rt.updateBefore(0.01)
            eq(m.snapshot().recentSlow[3].context, "扫荡处理中", "explicit bridge keeps sweep precedence")
            f.advance(60); rt.updateBefore(0.01)
            eq(m.snapshot().recentSlow[4].context, "仓库", "unregistered modules still use loaded fallback")
            check(m.isEnabled(), "explicit context getters did not fail diagnostics")
        end)
        run("Hooks installation failure isolated / subsequent boot install recovers", function()
            local f = fixture(); local hooks = f.env.require("boot.PerformanceHooks"); local m = f.monitor
            local original = function() return "business-continues" end
            local business = { update = original }
            local wrap = m.wrap
            m.start(); m.wrap = function() error("injected hook wrap failure", 0) end
            eq(hooks.install({ ["ui.battle.scene.BattleScene"] = business }), 0, "diagnostic install error swallowed")
            eq(m.isEnabled(), false, "install failure stops diagnostics only")
            eq(business.update, original, "failed wrap never overwrites business")
            eq(business.update(), "business-continues", "business continues after diagnostic failure")
            m.wrap = wrap
            eq(hooks.install(), 1, "later boot-completion install retries failed export")
            check(business.update ~= original, "retry wrapper installed")
            eq(hooks.install(), 0, "retry remains idempotent")
        end)
        run("isolation audit / only three current source reads", function()
            eq(#reads, 3, "exactly three production Lua files read")
            for _, path in ipairs(reads) do
                check(path == "core/PerformanceMonitor.lua" or path == "boot/PerformanceRuntime.lua"
                    or path == "boot/PerformanceHooks.lua", "source read whitelist")
            end
            for _, f in ipairs(contexts) do
                eq(#f.denied, 0, "no forbidden access even if caught internally")
                eq(f.legacyWallReads or 0, 0, "instance time clock never used even if its error was caught")
            end
            for name, value in pairs(nativeLoaded) do eq(value, originalLoaded[name], "host package.loaded unchanged " .. name) end
            for name, value in pairs(originalLoaded) do eq(nativeLoaded[name], value, "host module retained " .. name) end
            eq(cache, nativeCache, "host cache unchanged")
        end)
    end)
    if not ok then failed = failed + 1; print(TAG .. " HARNESS " .. tostring(why)) end
    print(string.format("%s SUMMARY groups=%d checks=%d failures=%d sourceFiles=%d", TAG, groups, checks, failed, #reads))
    if failed > 0 then log:Write(LOG_ERROR, TAG .. " FAILED") end
    engine:Exit()
end
