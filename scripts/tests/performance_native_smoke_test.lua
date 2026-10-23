-- 原生绑定冒烟：沿用 performance_monitor_test 的 Start + pcall + SUMMARY + Exit 生命周期。
-- 真实 require Monitor/Runtime 及关闭状态的诊断面板；不加载 main 或玩家档。
-- time/os/coroutine/cache/graphics 和 Update eventData 均保持原生，不替换这些全局。
-- 禁止 File、cache:GetFile、报告/导出；不手动发送 Update，不循环模拟帧，不创建协程。
-- 由官方 build 后运行；原生死锁/崩溃不能被 pcall 捕获，最后一条 ENTER 用于定位。
-- 回归：GetSystemTime 必须走 Time 静态绑定，实例调用在原生库中会报参数类型错误。
local TAG = "[performance_native_smoke_test]"
local SECTION = "native_smoke.Update"
local MIN_UPDATES, TARGET_FRAMES, MAX_UPDATES = 121, 120, 240
local updates, businessCount, sampledFrames = 0, 0, 0
local done, monitorLoaded = false, false
local stage = "Start"
---@type table
local Monitor = {}
---@type function?
local wrappedBusiness = nil

local function enter(label)
    stage = label
    print(TAG .. " ENTER " .. label .. " update=" .. updates .. " business=" .. businessCount)
end

local function traceback(err)
    -- 必须在栈展开前取得 trace；不能在 pcall 返回后才 debug.traceback(err)。
    if debug and type(debug.traceback) == "function" then
        return debug.traceback(tostring(err), 2)
    end
    return tostring(err) .. "\n[trace unavailable: native debug.traceback missing]"
end

local function protected(fn)
    -- 外层 pcall 也捕获错误处理器异常；内层 xpcall 保留原始出错源码行和调用栈。
    local ok, passed, result = pcall(xpcall, fn, traceback)
    if not ok then return false, passed end
    return passed, result
end

local function finish(success, why)
    if done then return end
    done = true
    if not success then print(TAG .. " FAIL stage=" .. stage .. "\n" .. tostring(why)) end
    local ok, err = protected(function() UnsubscribeFromEvent("Update") end)
    if not ok then success = false; print(TAG .. " FAIL cleanup.Unsubscribe\n" .. tostring(err)) end
    if monitorLoaded then
        ok, err = protected(function() Monitor.stop() end)
        if not ok then success = false; print(TAG .. " FAIL cleanup.Monitor.stop\n" .. tostring(err)) end
    end
    print(string.format("%s SUMMARY %s updates=%d business=%d sampledFrames=%d",
        TAG, success and "PASS" or "FAIL", updates, businessCount, sampledFrames))
    ok, err = protected(function() engine:Exit() end)
    if not ok then print(TAG .. " FAIL engine.Exit\n" .. tostring(err)) end
end

local function probe(label, fn)
    enter(label)
    local ok, value = protected(fn)
    print(TAG .. " PROBE " .. label .. " pcall=" .. tostring(ok)
        .. " resultType=" .. type(value) .. " result=" .. tostring(value))
    return ok, value
end

local function requireNumber(ok, value)
    assert(ok, value)
    assert(type(value) == "number" and value == value and value >= 0 and value < math.huge,
        stage .. " expected finite nonnegative number, got " .. type(value) .. " " .. tostring(value))
end

---@param eventType StringHash|string
---@param eventData UpdateEventData
local function business(eventType, eventData)
    enter("business.eventData:GetFloat(TimeStep)")
    local dt = eventData:GetFloat("TimeStep")
    requireNumber(true, dt)
    businessCount = businessCount + 1
    return eventType, eventData, nil, businessCount
end

function Start()
    local ok, err = protected(function()
        -- 必须先报告这两项，再 require/开启采集；失败时也保留绑定返回类型和原始 trace。
        local timeOK, timeValue = probe("Time:GetSystemTime static", function() return Time:GetSystemTime() end)
        requireNumber(timeOK, timeValue)
        local yieldableExists = coroutine ~= nil and type(coroutine.isyieldable) == "function"
        print(TAG .. " PROBE coroutine.isyieldable exists=" .. tostring(yieldableExists))
        assert(yieldableExists, "native coroutine.isyieldable missing")
        assert(debug and type(debug.traceback) == "function", "exact trace requires native debug.traceback")
        enter("require core.PerformanceMonitor")
        Monitor = require("core.PerformanceMonitor")
        monitorLoaded = true
        assert(not Monitor.isEnabled(), "use isolated test entry; monitor must initially be disabled")
        enter("Monitor.wrap create")
        wrappedBusiness = Monitor.wrap(SECTION, business)
        enter("Runtime.installHandlers")
        local runtime = require("boot.PerformanceRuntime")
        HandleUpdate = HandlePerformanceNativeSmokeUpdate
        runtime.installHandlers()
        enter("Monitor.start")
        Monitor.start()
        assert(Monitor.isEnabled(), "Monitor.start did not enable collection")
        enter("SubscribeToEvent Update")
        SubscribeToEvent("Update", "HandleUpdate")
        print(TAG .. " READY awaiting native Runtime Update callbacks; no player/file/export")
    end)
    if not ok then finish(false, err) end
end

---@param eventType StringHash|string
---@param eventData UpdateEventData
function HandlePerformanceNativeSmokeUpdate(eventType, eventData)
    if done then return end
    local ok, err = protected(function()
        updates = updates + 1
        enter("Monitor.wrap invoke")
        -- 原样传递真实事件对象；不复制/伪造 VariantMap，也不在回调结束后保存它。
        local returnedType, returnedData, hole, count = assert(wrappedBusiness)(eventType, eventData)
        enter("Monitor.wrap returned")
        assert(returnedType == eventType and returnedData == eventData and hole == nil,
            "wrapped native event identity / nil return changed")
        assert(count == updates and businessCount == updates, "business must increment exactly once per native Update")
        if updates == 1 then
            -- Monitor.sampleMemory 内部会吞掉部分 API 错误；显式探测，避免绑定异常被伪装为零值。
            requireNumber(probe("os.clock", function() return os.clock() end))
            requireNumber(probe("cache:GetTotalMemoryUse", function() return cache:GetTotalMemoryUse() end))
            requireNumber(probe("graphics:GetNumBatches", function() return graphics:GetNumBatches() end))
            requireNumber(probe("graphics:GetNumPrimitives", function() return graphics:GetNumPrimitives() end))
        end
        enter("Monitor.snapshot")
        local snapshot = Monitor.snapshot()
        sampledFrames = snapshot.frames
        assert(snapshot.enabled, "monitor unexpectedly stopped")
        print(string.format("%s FRAME update=%d business=%d sampledFrames=%d sections=%d",
            TAG, updates, businessCount, sampledFrames, #snapshot.sections))
        if updates >= MIN_UPDATES and sampledFrames >= TARGET_FRAMES then
            local measured = false
            for _, entry in ipairs(snapshot.sections) do
                if entry.name == SECTION and entry.calls >= TARGET_FRAMES then measured = true end
            end
            assert(measured, "native business section was not measured across real Runtime frames")
            finish(true)
        else
            -- 毫秒时钟下零间隔不算有效帧；等待后续真实 Update，但严格有界，不 sleep/忙等。
            assert(updates < MAX_UPDATES, "native Update limit reached before target completed timed frames")
        end
    end)
    if not ok then finish(false, err) end
end
