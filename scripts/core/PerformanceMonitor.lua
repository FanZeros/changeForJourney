-- 有界、默认关闭的运行时诊断；复用 startup_performance_probe 的分段计时口径。
-- 帧间隔取原始系统时钟，不取可能平滑/限幅的游戏 dt；分段 CPU 为进程 CPU，wall 为同步历时。
-- inclusive 分段可嵌套，不能相加；不采集账号、姓名、钱包、装备或完整存档。
local M = {}
local FRAME_LIMIT, SLOW_LIMIT, MARK_LIMIT, SECTION_LIMIT = 3600, 80, 40, 192
local MAX_SECONDS = 600
local enabled = false
local frames, sections, slow, marks = {}, {}, {}, {}
local cursor, sampleCount, totalFrames, totalMs = 0, 0, 0, 0
local peakMs = 0
local over33, over50, over100 = 0, 0, 0
local excludedGaps, excludedPanelFrames, droppedSections = 0, 0, 0
local epoch = 0
---@type table?
local current = nil
---@type number?
local lastWall = nil
local memory = { luaMemoryKB = 0, resourceMemoryBytes = 0, batches = 0, primitives = 0 }
local memoryAt = -1
local stoppedReason = "未开始"
local cachedReport = ""
local function wall()
    -- GetSystemTime 是静态绑定；实例 time:GetSystemTime() 会在原生运行库中报参数类型错误。
    return Time:GetSystemTime() / 1000
end
local function cpu() return os.clock() end
local function finite(n) return type(n) == "number" and n == n and n >= 0 and n < math.huge end
local function boundedPush(list, item, limit)
    if #list >= limit then table.remove(list, 1) end
    list[#list + 1] = item
end
local function topEntries(map, limit)
    local list = {}
    for name, value in pairs(map) do
        list[#list + 1] = { name = name, cpuMs = value.cpuMs, wallMs = value.wallMs, calls = value.calls }
    end
    table.sort(list, function(a, b)
        if a.wallMs == b.wallMs then return a.name < b.name end
        return a.wallMs > b.wallMs
    end)
    while #list > limit do list[#list] = nil end
    return list
end
local function sampleMemory(now)
    if now - memoryAt < 1 then return end
    memoryAt = now
    local ok, value = pcall(collectgarbage, "count")
    if ok and finite(value) then memory.luaMemoryKB = value end
    if cache and cache.GetTotalMemoryUse then
        ok, value = pcall(function() return cache:GetTotalMemoryUse() end)
        if ok and finite(value) then memory.resourceMemoryBytes = value end
    end
    if graphics then
        ok, value = pcall(function() return graphics:GetNumBatches() end)
        if ok and finite(value) then memory.batches = value end
        ok, value = pcall(function() return graphics:GetNumPrimitives() end)
        if ok and finite(value) then memory.primitives = value end
    end
end
local function commitFrame(intervalMs)
    local frame = current
    if not frame then return end
    if frame.excluded then
        if frame.excluded == "panel" then excludedPanelFrames = excludedPanelFrames + 1
        else excludedGaps = excludedGaps + 1 end
        return
    end
    if not finite(intervalMs) or intervalMs <= 0 then return end
    for name, entry in pairs(frame.sections) do
        local stat = sections[name]
        if not stat then
            local count = 0
            for _ in pairs(sections) do count = count + 1 end
            if count < SECTION_LIMIT then
                stat = { name = name, calls = 0, totalCpuMs = 0, maxCpuMs = 0, totalWallMs = 0, maxWallMs = 0 }
                sections[name] = stat
            else droppedSections = droppedSections + 1 end
        end
        if stat then
            stat.calls = stat.calls + entry.calls
            stat.totalCpuMs, stat.totalWallMs = stat.totalCpuMs + entry.cpuMs, stat.totalWallMs + entry.wallMs
            stat.maxCpuMs, stat.maxWallMs = math.max(stat.maxCpuMs, entry.maxCpuMs), math.max(stat.maxWallMs, entry.maxWallMs)
        end
    end
    totalFrames = totalFrames + 1
    totalMs = totalMs + intervalMs
    peakMs = math.max(peakMs, intervalMs)
    cursor = cursor % FRAME_LIMIT + 1
    frames[cursor] = intervalMs
    sampleCount = math.min(FRAME_LIMIT, sampleCount + 1)
    if intervalMs > 33.333 then over33 = over33 + 1 end
    if intervalMs > 50 then over50 = over50 + 1 end
    if intervalMs > 100 then over100 = over100 + 1 end
    if intervalMs > 50 then
        boundedPush(slow, { frame = totalFrames, intervalMs = intervalMs, context = frame.context,
            top = topEntries(frame.sections, 6) }, SLOW_LIMIT)
    end
end
function M.isEnabled() return enabled end
function M.start()
    epoch = epoch + 1
    frames, sections, slow, marks = {}, {}, {}, {}
    cursor, sampleCount, totalFrames, totalMs = 0, 0, 0, 0
    peakMs = 0
    over33, over50, over100 = 0, 0, 0
    excludedGaps, excludedPanelFrames, droppedSections = 0, 0, 0
    current, lastWall = nil, nil
    memoryAt, cachedReport, stoppedReason = -1, "", "采集中"
    memory = { luaMemoryKB = 0, resourceMemoryBytes = 0, batches = 0, primitives = 0 }
    enabled = true
    print("[Performance] 开始诊断；最长600秒，仅内存采样，不上传玩家数据")
end
function M.stop()
    if not enabled then return end
    enabled = false
    current, lastWall = nil, nil -- 当前尚未闭合的帧不冒充完整帧。
    stoppedReason = "手动停止"
    epoch = epoch + 1
    print("[Performance] 停止诊断 frames=" .. totalFrames)
end
-- 诊断异常仅关闭采集，不能中断游戏；不把业务异常或玩家参数写入报告。
function M.fail(stage)
    if not enabled then return end
    M.stop()
    stoppedReason = "诊断异常，已自动停止（" .. stage .. "）"
    cachedReport = ""
    print("[Performance] " .. stoppedReason .. "；游戏继续运行")
end
-- context 必须由宿主固定枚举构造，禁止传玩家名称或业务payload。
---@param context string
---@param exclusion string?
function M.beginFrame(context, exclusion)
    if not enabled then return end
    local now = wall()
    if lastWall then
        -- 切后台/诊断面板进入与退出的两侧边界都排除，不把后台等待或复制报告当卡顿。
        if exclusion then
            if current then current.excluded = exclusion end
        end
        local interval = (now - lastWall) * 1000
        if interval < 0 then
            if current then current.excluded = "clock" end
        end
        commitFrame(interval)
    end
    if totalMs >= MAX_SECONDS * 1000 then
        M.stop()
        stoppedReason = "达到600秒上限"
        return
    end
    lastWall = now
    current = { context = context, excluded = exclusion, sections = {} }
    if not exclusion then sampleMemory(now) end
end
-- 标记面板打开/切后台发生在两次Update之间的边界，不能污染当前帧。
function M.excludeCurrent(reason)
    if current then current.excluded = reason or "panel" end
end
---@param name string
---@return table?
function M.begin(name)
    if not enabled or not current or current.excluded then return nil end
    return { name = name, c = cpu(), w = wall(), epoch = epoch, frame = current }
end
---@param token table?
function M.finish(token)
    if not token or not enabled or token.epoch ~= epoch or token.frame ~= current or current.excluded then return end
    local c, w = (cpu() - token.c) * 1000, (wall() - token.w) * 1000
    if not finite(c) or not finite(w) then return end
    local entry = current.sections[token.name]
    if not entry then
        local count = 0
        for _ in pairs(current.sections) do count = count + 1 end
        if count >= SECTION_LIMIT then droppedSections = droppedSections + 1; return end
        entry = { calls = 0, cpuMs = 0, wallMs = 0, maxCpuMs = 0, maxWallMs = 0 }
        current.sections[token.name] = entry
    end
    entry.calls, entry.cpuMs, entry.wallMs = entry.calls + 1, entry.cpuMs + c, entry.wallMs + w
    entry.maxCpuMs, entry.maxWallMs = math.max(entry.maxCpuMs, c), math.max(entry.maxWallMs, w)
end
-- 非诊断状态不pack/pcall/读时钟；开启后保持返回值个数、nil位置和错误传播。
-- 可让出的协程不包跨帧计时：挂起时间和其他帧CPU不能归给它；由宿主每次resume的同步外层计量。
function M.wrap(name, fn)
    return function(...)
        if not enabled or not current or current.excluded or coroutine.isyieldable() then return fn(...) end
        local ok, token = pcall(M.begin, name)
        if not ok then
            M.fail("分段开始")
            return fn(...)
        end
        local result = table.pack(pcall(fn, ...))
        if not pcall(M.finish, token) then M.fail("分段结束") end
        if not result[1] then error(result[2], 0) end
        return table.unpack(result, 2, result.n)
    end
end
function M.mark()
    if not enabled then return false end
    boundedPush(marks, { frame = totalFrames, atSeconds = totalMs / 1000 }, MARK_LIMIT)
    return true
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
function M.snapshot()
    local sorted = {}
    for i = 1, sampleCount do sorted[i] = frames[i] end
    table.sort(sorted)
    local function percentile(p)
        return sorted[math.max(1, math.ceil(#sorted * p))] or 0
    end
    local list = {}
    for _, value in pairs(sections) do list[#list + 1] = copy(value) end
    table.sort(list, function(a, b)
        if a.totalWallMs == b.totalWallMs then return a.name < b.name end
        return a.totalWallMs > b.totalWallMs
    end)
    return {
        schemaVersion = 1, monitorVersion = "2026-10-24-v7", enabled = enabled, stoppedReason = stoppedReason,
        elapsedSeconds = totalMs / 1000, frames = totalFrames, fps = totalMs > 0 and totalFrames * 1000 / totalMs or 0,
        frameMs = { p50 = percentile(0.5), p95 = percentile(0.95), p99 = percentile(0.99), max = peakMs },
        percentileWindowFrames = sampleCount,
        slowFrames = { over33 = over33, over50 = over50, over100 = over100 },
        luaMemoryKB = memory.luaMemoryKB, resourceMemoryBytes = memory.resourceMemoryBytes,
        batches = memory.batches, primitives = memory.primitives,
        sections = list, recentSlow = copy(slow), marks = copy(marks), excludedGaps = excludedGaps,
        excludedPanelFrames = excludedPanelFrames, droppedSections = droppedSections,
        limits = { frames = FRAME_LIMIT, slowFrames = SLOW_LIMIT, marks = MARK_LIMIT, sections = SECTION_LIMIT, seconds = MAX_SECONDS },
        timing = { frame = "system_clock_update_to_update_ms", sections = "inclusive_process_cpu_and_sync_wall_ms",
            gpu = "not_sampled", memory = "lua_heap_and_resource_cache_not_process_rss_or_vram" },
    }
end
function M.getReport()
    if enabled then M.stop() end
    if cachedReport ~= "" then return cachedReport end
    local s = M.snapshot()
    local lines = {
        "性能诊断报告 v7 · 2026-10-24",
        string.format("有效采样 %.1f秒 / %d帧 / 平均 %.1f FPS", s.elapsedSeconds, s.frames, s.fps),
        string.format("最近%d有效帧 P50 %.1f / P95 %.1f / P99 %.1f ms；本轮最大 %.1f ms", s.percentileWindowFrames,
            s.frameMs.p50, s.frameMs.p95, s.frameMs.p99, s.frameMs.max),
        string.format("长帧 >33.3ms:%d  >50ms:%d  >100ms:%d", over33, over50, over100),
        string.format("Lua %.1fMB / 资源缓存 %.1fMB / 最近批次%d / 图元%d", s.luaMemoryKB / 1024,
            s.resourceMemoryBytes / 1048576, s.batches, s.primitives),
        "计时为inclusive，嵌套项不可相加；CPU是进程CPU，同步wall不是GPU时间。",
        "帧间隔包含引擎/限帧/系统调度；无高耗时分段不等于没有卡顿。",
        "分位数仅最近3600有效帧；最大值/计数为本轮累计；内存不是完整进程或显存。",
        "批次/图元为最近一次快照，不是平均值或峰值；均次wall为总wall除调用数。",
        "可让出协程只计宿主每次resume外层（如本地动作.updateQuickEquip），不单计协程内层。",
        string.format("排除后台/时钟异常%d帧、诊断面板%d帧；标记%d条；%s", excludedGaps, excludedPanelFrames, #marks, stoppedReason),
        "模块：调用数 / CPU总ms / wall总ms / 最大单次wall ms / 均次wall ms",
    }
    for i = 1, math.min(20, #s.sections) do
        local v = s.sections[i]
        lines[#lines + 1] = string.format("%s: %d / %.1f / %.1f / %.1f / %.2f", v.name, v.calls,
            v.totalCpuMs, v.totalWallMs, v.maxWallMs, v.calls > 0 and v.totalWallMs / v.calls or 0)
    end
    lines[#lines + 1] = "最近慢帧（最多展示10条，完整记录在JSON）"
    for i = math.max(1, #slow - 9), #slow do
        local v = slow[i]
        ---@type table[]
        local entries = v.top
        local top = entries[1]
        lines[#lines + 1] = string.format("帧%d %.1fms [%s] %s", v.frame, v.intervalMs, v.context,
            top and (top.name .. string.format(" %.1fms", top.wallMs)) or "无已接入高耗时分段")
    end
    if s.frames == 0 then lines[#lines + 1] = "尚无有效帧：开始后关闭诊断面板，实际操作30~60秒再生成报告。" end
    local ok, json = pcall(cjson.encode, s)
    if ok then
        lines[#lines + 1] = "---PERFORMANCE_JSON_BEGIN---"
        lines[#lines + 1] = json
        lines[#lines + 1] = "---PERFORMANCE_JSON_END---"
    else lines[#lines + 1] = "JSON编码失败；请反馈此文本与截图。" end
    cachedReport = table.concat(lines, "\n")
    return cachedReport
end
function M.export()
    local text = M.getReport()
    local file = nil ---@type File?
    local ok, err = pcall(function()
        file = File("performance_report.txt", FILE_WRITE)
        assert(file and file:IsOpen(), "无法打开诊断文件")
        assert(file:WriteString(text) == true, "诊断文件写入失败")
        assert(file:Close() ~= false, "诊断文件关闭失败")
    end)
    if file then pcall(function() file:Dispose() end) end
    if not ok then return false, tostring(err) end
    print("[Performance] 报告已写入独立performance_report.txt；不包含玩家存档")
    return true, "performance_report.txt"
end
return M
