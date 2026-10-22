-- 自动分解通知专项：基于 tavern_recruit_orders_test.lua 的白名单源码 load(env) 隔离脚手架。
-- 只读 cache:GetFile(SOURCE_FILES 中三条资源路径)；不 require main、不读取玩家档、不发动作。
-- Boot 仅提取真实订阅/基线与 addKillEquipment 片段执行，不是全 Boot 集成测试。
-- 所有非白名单模块均为显式 mock；没有 _G/package.loaded/原生 require 回退。
-- 契约：updateSeedData(data, {resetNotice=true}) 静默重建基线；默认首次有效通知也静默。
-- 无通知建立零基线；此后累计值的新增差额攒够 >=100 件才合并显示，忙时不得覆盖弹窗。
-- 直接验证生产 API，不在 harness 内实现通知算法，不改写生产源码。
-- 运行前须先通过官方 build 工具完成构建，由主线程统一执行；本文件不负责构建。
-- 构建完成后，只运行该隔离入口（不要用 main，cwd 使用专用验证目录）：
--   cd /home/Maker/auto-decompose-batch-validation-20261022 && \
--     /workspace/.cli/UrhoXRuntime tests/auto_decompose_notice_test.lua \
--     -tapcode_dir=/workspace -tool_mode -nosound -graphicsheadless
-- Start 同步跑完、打印 groups/checks/failures，失败写 LOG_ERROR，最后无条件 engine:Exit()。
-- 本测试只证明 UI 展示/无副作用及真实 BC 公式、累计记录；不冒充真实服务发奖集成测试。

local TAG = "[auto_decompose_notice_test] "
local SOURCE_FILES = {
    ["ui.loot.LootBox"] = "ui/loot/LootBox.lua",
    ["config.BlacksmithConfig"] = "config/BlacksmithConfig.lua",
    ["boot.StandaloneBoot"] = "boot/StandaloneBoot.lua", -- 只允许 source() 提取片段，不允许 require 全模块。
}
local nativeCache, nativeFile, nativeRequire = cache, File, require
local nativeIO, nativeOS, nativeNetwork = io, os, network
local nativeCloud, nativeServerCloud = clientCloud, serverCloud
local nativePackage, nativeLoaded, nativeTime = package, package.loaded, time
local initialLoaded = {} ---@type table<string, any>
for name, value in pairs(nativeLoaded) do initialLoaded[name] = value end
local sources = {} ---@type table<string, string>
local sourceReads = {} ---@type string[]
local contexts = {} ---@type any[]
local checks, groups = 0, 0
local failures = {} ---@type string[]

local function check(ok, message)
    checks = checks + 1
    assert(ok, message)
end
local function eq(actual, expected, message)
    check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then
        -- NaN 是非法输入样本，但两个未被修改的 NaN 应视为相同。
        return a == b or (type(a) == "number" and a ~= a and b ~= b)
    end
    for key, child in pairs(a) do if not same(child, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function source(name)
    local path = assert(SOURCE_FILES[name], "source denied: " .. tostring(name))
    assert(path == "ui/loot/LootBox.lua" or path == "config/BlacksmithConfig.lua"
        or path == "boot/StandaloneBoot.lua", "source path denied")
    if not sources[name] then
        -- 唯一真实数据读取出口：固定资源根路径，不接受玩家路径，不构造 File、不读其它资源。
        local file = assert(nativeCache:GetFile(path), "source unavailable: " .. path)
        local ok, text = pcall(function()
            assert(file:IsOpen(), "source open failed: " .. path)
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            return table.concat(lines, "\n")
        end)
        file:Dispose()
        assert(ok, text)
        sources[name] = text
        sourceReads[#sourceReads + 1] = path
    end
    return sources[name]
end

local function newContext()
    local ctx = {
        deps = {}, forbidden = {}, expectedDenied = 0, requires = {},
        clock = { now = 2000000000, elapsedTime = 500 }, logs = {},
        popups = {}, busy = false, active = false, onShow = false, showing = false,
        pageOpen = false, pageUpdates = {}, refreshes = {}, opens = {}, summaryCalls = {},
        summary = {}, events = {}, inputs = {}, loading = {},
        -- 仅用于验证隔离与 UI 不发奖；没有生产 Store/PDM/currency 实例。
        account = { essence = 9876543, inventory = { { seq = 17, quality = 6 } } },
    } ---@type any
    ctx.initialAccount = copy(ctx.account)
    contexts[#contexts + 1] = ctx
    local env = {} ---@type any
    ctx.env = env
    for _, key in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select",
        "tonumber", "tostring", "type", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal" }) do
        env[key] = _G[key]
    end
    env.math, env.string, env.table, env.utf8 = copy(math), copy(string), copy(table), copy(utf8)
    env._G, env.time = env, ctx.clock
    env.print = function(...) ctx.logs[#ctx.logs + 1] = { ... } end
    local function deny(label)
        ctx.forbidden[#ctx.forbidden + 1] = label
        error("isolated auto-decompose notice test forbids " .. label, 2)
    end
    local function denied(label)
        return function() return deny(label) end
    end
    local function sealed(label, values)
        return setmetatable(values or {}, { __index = function(_, key)
            return deny(label .. "." .. tostring(key))
        end })
    end
    env.File = denied("File (all paths/modes)")
    for _, key in ipairs({ "cache", "fileSystem", "io", "network", "clientCloud", "serverCloud",
        "package", "debug", "engine", "sdk", "http", "socket" }) do env[key] = sealed(key) end
    -- recordAutoDecompose 的时间是纯测试时钟；其余 os 能力一律拒绝。
    env.os = sealed("os", { time = function() return ctx.clock.now end })
    for _, key in ipairs({ "load", "loadfile", "dofile", "GetFileSystem", "GetNetwork", "GetSubsystem",
        "SubscribeToEvent", "SendEvent", "SendRemoteEvent", "GetUserId", "GetUserNickname" }) do
        env[key] = denied(key)
    end
    env.NVG_ALIGN_CENTER, env.NVG_ALIGN_MIDDLE = 1, 2 -- 不运行绘图；只占位，绝不碰真实 NanoVG。
    local function mock(name, values)
        local module = sealed(name, values)
        ctx.deps[name] = module
        return module
    end
    mock("core.DrawUtil", {}) -- 本专项不调用 drawRates；遗漏绘图调用应立即失败。
    mock("core.NumberUtil", { format = function(n) return tostring(n) end })
    mock("ui.loot.LootBoxPage", {
        init = function() ctx.pageInits = (ctx.pageInits or 0) + 1 end,
        isOpen = function() return ctx.pageOpen end,
        refresh = function(summary) ctx.refreshes[#ctx.refreshes + 1] = copy(summary) end,
        open = function(summary)
            ctx.pageOpen = true
            ctx.opens[#ctx.opens + 1] = copy(summary)
        end,
        update = function(dt) ctx.pageUpdates[#ctx.pageUpdates + 1] = dt end,
    })
    mock("systems.LootBoxSystem", {
        revealLegacy = function(data)
            ctx.events[#ctx.events + 1] = "reveal"
            ctx.revealed = data
            -- 显式只读 mock：这里不执行真实种子揭示/生成/存档/发奖。
        end,
        getSummary = function(data)
            ctx.events[#ctx.events + 1] = "summary"
            ctx.summaryCalls[#ctx.summaryCalls + 1] = data
            return copy(ctx.summary)
        end,
    })
    mock("ui.hud.popup.RewardPopup", {
        isOpen = function()
            ctx.openProbes = (ctx.openProbes or 0) + 1
            return ctx.busy
        end,
        show = function(title, items)
            check(not ctx.busy, "show must never replace an already-open RewardPopup")
            check(not ctx.showing, "show must not recursively replace an in-progress RewardPopup.show")
            check(type(title) == "string", "show title is text")
            check(type(items) == "table", "show items are a table")
            local entry = { title = title, items = copy(items), originalItems = items }
            ctx.popups[#ctx.popups + 1] = entry
            ctx.active, ctx.showing = entry, true
            -- 故意在 busy=true 之前回调：验证生产 pending 先取走且有 pump 重入保护。
            if ctx.onShow then ctx.onShow(entry) end
            ctx.showing, ctx.busy = false, true
        end,
    })
    env.require = function(name)
        ctx.requires[#ctx.requires + 1] = name
        if ctx.deps[name] ~= nil then return ctx.deps[name] end
        if name == "boot.StandaloneBoot" then return deny("full Boot require (fragments only)") end
        if not SOURCE_FILES[name] then return deny("require " .. tostring(name)) end
        assert(not ctx.loading[name], "recursive source require: " .. name)
        ctx.loading[name] = true
        local chunk, why = load(source(name), "@" .. SOURCE_FILES[name], "t", env)
        assert(chunk, why)
        local module = chunk()
        assert(type(module) == "table", "expected module table: " .. name)
        ctx.loading[name], ctx.deps[name] = nil, module
        return module
    end
    -- 不继承真实 _G；任何未显式批准的全局读写直接报错。
    setmetatable(env, {
        __index = function(_, key) return deny("global " .. tostring(key)) end,
        __newindex = function(_, key) return deny("global write " .. tostring(key)) end,
    })
    ctx.bc = env.require("config.BlacksmithConfig")
    ctx.loot = env.require("ui.loot.LootBox")
    check(type(ctx.loot.updateSeedData) == "function", "production exports updateSeedData")
    check(type(ctx.loot.update) == "function", "production exports update pump")
    function ctx.safe()
        eq(#ctx.forbidden, ctx.expectedDenied, "no unexpected IO/network/action/dependency/global access")
        check(same(ctx.account, ctx.initialAccount), "UI cannot award or change account/inventory")
        for _, entry in ipairs(ctx.popups) do
            check(same(entry.originalItems, entry.items), "previous popup payload is not later overwritten/reused")
        end
    end
    function ctx.push(data, options)
        local before, beforeOptions = copy(data), copy(options)
        ---@type any
        local seeds = nil
        ---@type any
        local notice = nil
        if type(data) == "table" then
            seeds = data.seeds
            notice = data.autoDecomposeNotice -- 保留 false 等非法样本，不能用 and/or 把它变成 nil。
        end
        ctx.currentData = data
        ctx.inputs[#ctx.inputs + 1] = { value = data, snapshot = before }
        local ok, why = pcall(ctx.loot.updateSeedData, data, options)
        check(same(data, before), "updateSeedData does not mutate input snapshot (including illegal values)")
        check(same(options, beforeOptions), "updateSeedData does not mutate options")
        if type(data) == "table" then
            eq(data.seeds, seeds, "input seeds identity unchanged")
            eq(data.autoDecomposeNotice, notice, "input notice identity unchanged")
        end
        check(ok, "updateSeedData must not throw: " .. tostring(why))
        ctx.safe()
    end
    function ctx.tick(dt)
        -- 重入可以合法推送另一个 clone；检查调用开始时持有的原输入，不能把换快照误判为修改。
        local input = ctx.currentData
        local before = copy(input)
        local ok, why = pcall(ctx.loot.update, dt or 0.016)
        check(same(input, before), "update pump does not modify retained input")
        check(ok, "update must not throw: " .. tostring(why))
        ctx.safe()
    end
    function ctx.close()
        ctx.busy, ctx.active = false, false -- 只模拟用户关闭弹窗，不触发任何真实输入/动作。
    end
    return ctx
end

local function dataWith(seq, count, essence)
    return { seeds = {}, autoDecomposeNotice = { seq = seq, count = count, essence = essence } }
end
local function baseline(ctx, data, options)
    ctx.push(data or dataWith(0, 0, 0), options)
    eq(#ctx.popups, 0, "baseline is silent, even if count exceeds threshold")
end
local function noPopup(ctx, expected, message)
    eq(#ctx.popups, expected or 0, message or "no new popup")
end
local function popup(ctx, index, count, essence)
    -- 统一显式跑帧：不依赖收包回调立即 show，允许结算回调先建立自己的奖励弹窗。
    ctx.tick(0)
    eq(#ctx.popups, index, "exactly one popup per flush, no 100-item chunks/overwrites")
    local entry = assert(ctx.popups[index], "expected popup missing")
    eq(entry.title, "自动分解 " .. count .. " 件", "title contains pending delta count, not historical total")
    eq(#entry.items, 1, "only one essence reward entry")
    eq(entry.items[1].type, "essence", "reward resource type")
    eq(entry.items[1].amount, essence, "reward is sum of per-item new essence, not cumulative/average")
end

-- 确定性装备样本：覆盖 6 品质、不同等级、小数向下取整；不是 count * 最后一件收益。
local ITEMS = {
    { quality = 1, level = 1 }, { quality = 2, level = 24 },
    { quality = 3, level = 17 }, { quality = 4, level = 35 },
    { quality = 5, level = 60 }, { quality = 6, level = 7 },
}
local function append(ctx, data, count, offset, fixed)
    local beforeCount = data.autoDecomposeNotice and data.autoDecomposeNotice.count or 0
    local beforeSeq = data.autoDecomposeNotice and data.autoDecomposeNotice.seq or 0
    local beforeEssence = data.autoDecomposeNotice and data.autoDecomposeNotice.essence or 0
    local seeds, sum = data.seeds, 0
    for i = 1, count do
        local item = fixed or ITEMS[((i + (offset or 0) - 1) % #ITEMS) + 1]
        local cost = ctx.bc.QUALITY_COST[item.quality]
        local expected = math.floor(cost.decBase * (1 + item.level * cost.decScale))
        local actual = ctx.bc.calcAutoDecomposeEssence(item.quality, item.level)
        eq(actual, expected, "real BC per-item formula q=" .. item.quality .. " lv=" .. item.level)
        sum = sum + actual
        ctx.bc.recordAutoDecompose(data, item.quality, item.level, actual)
    end
    eq(data.autoDecomposeNotice.count, beforeCount + count, "real record preserves cumulative count")
    eq(data.autoDecomposeNotice.seq, beforeSeq + count, "real record preserves cumulative seq")
    eq(data.autoDecomposeNotice.essence, beforeEssence + sum, "real record preserves cumulative essence")
    eq(data.seeds, seeds, "real record does not replace seeds")
    eq(data.autoDecomposeNotice.time, ctx.clock.now, "real record uses mocked timestamp")
    ctx.safe()
    return sum
end
local function history(ctx)
    local data = { seeds = {}, marker = { untouched = true } }
    -- 品质4、等级24：floor(20 * (1 + 24 * 0.1)) = 68；33857 * 68 = 2302276。
    eq(ctx.bc.calcAutoDecomposeEssence(4, 24), 68, "historical fixture per-item essence from real BC")
    local amount = append(ctx, data, 33857, 0, { quality = 4, level = 24 })
    eq(amount, 2302276, "33857 historical items have about 2.3M essence (real BC formula)")
    return data, amount
end

local function isolationCases()
    local a, b = newContext(), newContext()
    check(a.loot ~= b.loot and a.bc ~= b.bc, "each load(env) has independent production module state")
    eq(a.env._G, a.env, "sandbox _G does not expose host globals")
    local attempts = {
        function() a.env.require("main") end,
        function() a.env.require("core.PlayerStore") end,
        function() a.env.require("runtime.GameAction") end,
        function() a.env.require("boot.StandaloneBoot") end,
        function() a.env.require("boot.StandaloneSave") end,
        function() a.env.File("save.json") end,
        function() a.env.cache:GetFile("save.json") end,
        function() a.env.io.open("save.json") end,
        function() a.env.network:Connect("localhost") end,
        function() a.env.clientCloud:Get("lootbox") end,
        function() a.env.serverCloud:Get("lootbox") end,
        function() a.env.os.execute("forbidden") end,
        function() a.env.package.loaded.main = true end,
        function() a.env.loadfile("main.lua") end,
        function() a.env.SendEvent("award") end,
    }
    for _, attempt in ipairs(attempts) do
        local before = #a.forbidden
        local ok = pcall(attempt)
        eq(ok, false, "forbidden dependency is fail-closed without a real call")
        eq(#a.forbidden, before + 1, "guard records rejected access")
        a.expectedDenied = a.expectedDenied + 1
    end
    local reads = #sourceReads
    eq(pcall(source, "main"), false, "source loader rejects non-whitelisted module")
    eq(#sourceReads, reads, "rejected source caused no native resource read")
    a.safe(); b.safe()
end

local function recorderCases()
    local ctx = newContext()
    for quality = 1, 6 do
        for _, level in ipairs({ 1, 7, 17, 24, 35, 60 }) do
            local q = ctx.bc.QUALITY_COST[quality]
            eq(ctx.bc.calcAutoDecomposeEssence(quality, level), math.floor(q.decBase * (1 + level * q.decScale)),
                "real shared formula for every rarity and representative level")
        end
    end
    local data = dataWith(41, 88, 12345)
    data.seeds = { { index = 8, equip = { seq = 71 } } }
    data.settings = { autoQuality = 4, autoLevel = 30 }
    data.autoDecomposeNotice.marker = "must-survive"
    local previous = copy(data)
    local notice = data.autoDecomposeNotice
    local gain = append(ctx, data, 101)
    eq(data.autoDecomposeNotice, notice, "real recorder remains cumulative on the original notice table")
    eq(notice.marker, "must-survive", "recorder preserves unknown notice fields")
    check(same(data.seeds, previous.seeds) and same(data.settings, previous.settings), "recorder preserves original non-notice data")
    eq(notice.essence, 12345 + gain, "record not changed into per-batch/reset notice")
    noPopup(ctx, 0, "recording alone does not open UI or grant account rewards")
    ctx.safe()
end

local function bootstrapHistoryCases()
    local ctx = newContext()
    local data, oldEssence = history(ctx)
    baseline(ctx, data, { resetNotice = true })
    ctx.tick(600)
    noPopup(ctx, 0, "bootstrap history is never pending")
    local gain = append(ctx, data, 100)
    ctx.push(data) -- 原 table、原 notice 原地变化；生产必须保存数值基线而非 table 别名。
    popup(ctx, 1, 100, gain)
    eq(data.autoDecomposeNotice.count, 33957, "UI leaves historical + new cumulative count intact")
    eq(data.autoDecomposeNotice.essence, oldEssence + gain, "UI never clears cumulative original essence")
    ctx.close(); ctx.push(copy(data)); ctx.tick(1)
    popup(ctx, 1, 100, gain)
end

local function firstSnapshotCases()
    local ctx = newContext()
    local data = dataWith(33857, 33857, 2302276)
    baseline(ctx, copy(data)) -- 没有 bootstrap options 的首次有效 notice 仍只建基线。
    local gain = append(ctx, data, 100)
    ctx.push(copy(data), { resetNotice = false })
    popup(ctx, 1, 100, gain)
    local empty = newContext()
    baseline(empty, { seeds = {} }) -- 无 notice 已建立 0；下一次不是再次“首次静默”。
    local fresh = { seeds = {} }
    local freshGain = append(empty, fresh, 100)
    empty.push(copy(fresh))
    popup(empty, 1, 100, freshGain)
end

local function thresholdCases()
    for _, count in ipairs({ 99, 100, 101, 33857 }) do
        local ctx, data = newContext(), { seeds = {} }
        baseline(ctx)
        local gain = append(ctx, data, count)
        ctx.push(copy(data))
        if count < 100 then
            noPopup(ctx, 0, "99 items below threshold")
            ctx.tick(999999)
            noPopup(ctx, 0, "elapsed time cannot flush less than 100")
            local extra = append(ctx, data, 3, count)
            ctx.push(copy(data))
            popup(ctx, 1, 102, gain + extra)
        else
            popup(ctx, 1, count, gain)
        end
        ctx.close(); ctx.push(copy(data)); ctx.tick(0)
        eq(#ctx.popups, 1, "same seq after flush is never added twice")
    end
end

local function incrementalCases()
    local ctx, data, total = newContext(), { seeds = {} }, 0
    baseline(ctx)
    for i = 1, 100 do
        total = total + append(ctx, data, 1, i - 1)
        ctx.push(copy(data)); ctx.tick(0)
        if i < 100 then noPopup(ctx, 0, "single-item push " .. i .. " keeps pending silently") end
    end
    popup(ctx, 1, 100, total)
    ctx.close()
    local extra = append(ctx, data, 99, 100)
    ctx.push(copy(data)); noPopup(ctx, 1, "flush clears pending, next 99 do not show")
    local one = append(ctx, data, 1, 199)
    ctx.push(copy(data)); popup(ctx, 2, 100, extra + one)
end

local function monotonicCounterCases()
    local ctx = newContext()
    local data = dataWith(700, 9000, 600000)
    baseline(ctx, copy(data))
    data.autoDecomposeNotice.seq = 701
    data.autoDecomposeNotice.count = 9099
    data.autoDecomposeNotice.essence = 605555
    ctx.push(copy(data)); noPopup(ctx, 0, "delta count is not delta seq")
    data.autoDecomposeNotice.seq = 999 -- seq 可跳跃，count/essence 不变仍单调，不应清 pending。
    ctx.push(copy(data)); noPopup(ctx, 0, "seq-only progression adds zero and keeps existing pending")
    data.autoDecomposeNotice.seq = 1001
    data.autoDecomposeNotice.count = 9102
    data.autoDecomposeNotice.essence = 605678
    ctx.push(copy(data)); popup(ctx, 1, 102, 5678)
    ctx.close()
    local unchanged = copy(data)
    unchanged.autoDecomposeNotice.quality = 6
    unchanged.autoDecomposeNotice.level = 60
    unchanged.autoDecomposeNotice.time = 1
    ctx.push(unchanged); ctx.tick(100)
    popup(ctx, 1, 102, 5678)
end

local function consecutiveBatchCases()
    local ctx, data = newContext(), { seeds = {} }
    baseline(ctx)
    local a = append(ctx, data, 100)
    ctx.push(copy(data)); popup(ctx, 1, 100, a)
    ctx.close()
    local b = append(ctx, data, 101, 100)
    ctx.push(copy(data)); popup(ctx, 2, 101, b)
    eq(data.autoDecomposeNotice.count, 201, "two UI batches do not reset production cumulative record")
    ctx.close()
    for _ = 1, 3 do ctx.push(copy(data)); ctx.tick(0.016) end
    popup(ctx, 2, 101, b)
end

local function busyMergeCases()
    local ctx, data, amount = newContext(), { seeds = {} }, 0
    baseline(ctx)
    local occupied = { title = "other reward", items = { { type = "gold", amount = 42 } } }
    ctx.busy, ctx.active = true, occupied
    local total = 0
    for _, count in ipairs({ 99, 3, 101, 33857 }) do
        amount = amount + append(ctx, data, count, total)
        total = total + count
        ctx.push(copy(data)); ctx.tick(120)
        noPopup(ctx, 0, "busy popup keeps all incoming notices queued, never replaces active")
        eq(ctx.active, occupied, "busy popup identity untouched")
        eq(occupied.items[1].amount, 42, "busy popup rewards untouched")
    end
    check((ctx.openProbes or 0) > 0, "production consults RewardPopup.isOpen")
    eq(#ctx.pageUpdates, 4, "busy notice pump does not prevent page update")
    ctx.close(); ctx.tick(0)
    popup(ctx, 1, 34060, amount)
    eq(ctx.pageUpdates[#ctx.pageUpdates], 0, "zero dt still forwarded to page update")
    ctx.close(); ctx.tick(1); ctx.push(copy(data)); ctx.tick(1)
    popup(ctx, 1, total, amount)
end

local function pushPumpCases()
    local ctx, data = newContext(), { seeds = {} }
    baseline(ctx)
    local amount = append(ctx, data, 100)
    ctx.push(copy(data))
    noPopup(ctx, 0, "receipt only collects; same-frame settlement reward gets priority")
    -- 模拟首通/离线结算在通知回调返回后立即打开自己的奖励，而非真实调用奖励模块。
    local settlement = { title = "settlement", items = { { type = "gold", amount = 777 } } }
    ctx.busy, ctx.active = true, settlement
    ctx.tick(0)
    noPopup(ctx, 0, "following frame cannot overwrite same-frame settlement popup")
    eq(ctx.active, settlement, "settlement active popup preserved")
    ctx.push(copy(data)); ctx.tick(0)
    noPopup(ctx, 0, "duplicate while settlement busy neither drops nor double counts pending")
    ctx.close()
    ctx.push(copy(data))
    noPopup(ctx, 0, "duplicate receipt still does not show inside settlement callback")
    popup(ctx, 1, 100, amount)
end

local function reentryCases()
    local ctx, data = newContext(), { seeds = {} }
    baseline(ctx)
    local amount = append(ctx, data, 100)
    ctx.onShow = function()
        ctx.onShow = false
        ctx.push(copy(data))
        ctx.tick(0)
    end
    ctx.push(copy(data))
    popup(ctx, 1, 100, amount)
    ctx.close(); ctx.tick(0)
    popup(ctx, 1, 100, amount)

    local nested, other = newContext(), { seeds = {} }
    baseline(nested)
    local first = append(nested, other, 100)
    local second = 0
    nested.onShow = function()
        nested.onShow = false
        second = append(nested, other, 101, 100)
        nested.push(copy(other))
        nested.tick(0)
    end
    nested.push(copy(other))
    popup(nested, 1, 100, first)
    nested.close(); nested.tick(0)
    popup(nested, 2, 101, second)
    nested.close(); nested.tick(0)
    popup(nested, 2, 101, second)
end

local function explicitResetCases()
    for _, count in ipairs({ 99, 100, 101 }) do
        local ctx, data = newContext(), { seeds = {} }
        baseline(ctx)
        ctx.busy = true
        append(ctx, data, count)
        ctx.push(copy(data))
        ctx.close()
        ctx.push(copy(data), { resetNotice = true }) -- 同一 seq 的 bootstrap 也必须清 pending。
        ctx.tick(0); noPopup(ctx, 0, "explicit reset discards old pending before idle pump")
        local a = append(ctx, data, 99)
        ctx.push(copy(data), { resetNotice = false })
        noPopup(ctx, 0, "explicit false continues from reset baseline")
        local b = append(ctx, data, 1, 99)
        ctx.push(copy(data)); popup(ctx, 1, 100, a + b)
    end
    local ctx, data = newContext(), { seeds = {} }
    baseline(ctx)
    ctx.busy = true; append(ctx, data, 100); ctx.push(data)
    local replacement = dataWith(33857, 33857, 2302276)
    ctx.close(); ctx.push(replacement, { resetNotice = true }); ctx.tick(0)
    noPopup(ctx, 0, "different bootstrap history also clears already-ready pending")
    local amount = append(ctx, replacement, 100)
    ctx.push(replacement); popup(ctx, 1, 100, amount)
end

local function rollbackCases()
    local replacements = {
        { label = "seq rollback only", value = { seq = 600, count = 1101, essence = 110000 } },
        { label = "count rollback only", value = { seq = 602, count = 900, essence = 110000 } },
        { label = "essence rollback only", value = { seq = 602, count = 1101, essence = 1 } },
        { label = "all counters rollback", value = { seq = 0, count = 0, essence = 0 } },
        { label = "same seq count grows", value = { seq = 601, count = 1102, essence = 110000 } },
        { label = "same seq essence grows", value = { seq = 601, count = 1101, essence = 110001 } },
        { label = "same seq count shrinks", value = { seq = 601, count = 1100, essence = 110000 } },
        { label = "same seq essence shrinks", value = { seq = 601, count = 1101, essence = 109999 } },
    }
    for _, replacement in ipairs(replacements) do
        local ctx = newContext()
        baseline(ctx, dataWith(500, 1000, 100000))
        ctx.busy = true
        ctx.push(dataWith(601, 1101, 110000)); noPopup(ctx, 0, "queue old ready batch")
        ctx.close()
        local data = { seeds = {}, autoDecomposeNotice = copy(replacement.value) }
        ctx.push(copy(data)); ctx.tick(0)
        noPopup(ctx, 0, replacement.label .. " silently rebuilds baseline and clears old pending")
        local amount = append(ctx, data, 99)
        ctx.push(copy(data)); noPopup(ctx, 0, replacement.label .. " counts only new 99")
        local one = append(ctx, data, 1, 99)
        ctx.push(copy(data)); popup(ctx, 1, 100, amount + one)
    end
end

local function missingNoticeCases()
    local replacements = {
        { label = "nil snapshot" }, { label = "empty snapshot", value = {} },
        { label = "no notice", value = { seeds = {} } },
        { label = "explicit bootstrap no notice", value = { seeds = {} }, reset = true },
    }
    for _, replacement in ipairs(replacements) do
        local ctx = newContext()
        baseline(ctx, dataWith(33857, 33857, 2302276))
        ctx.busy = true
        ctx.push(dataWith(33957, 33957, 2310000))
        ctx.close()
        ctx.push(copy(replacement.value), replacement.reset and { resetNotice = true } or nil)
        ctx.tick(0); noPopup(ctx, 0, replacement.label .. " clears old ready pending")
        local cleared = { seeds = {} }
        local a = append(ctx, cleared, 99)
        ctx.push(copy(cleared)); noPopup(ctx, 0, "clear/save-reset establishes zero, not stale history")
        local b = append(ctx, cleared, 1, 99)
        ctx.push(copy(cleared)); popup(ctx, 1, 100, a + b)
    end
end

local function restartCases()
    local old, data = newContext(), dataWith(33857, 33857, 2302276)
    baseline(old, copy(data), { resetNotice = true })
    append(old, data, 99); old.push(copy(data)); noPopup(old, 0, "old process holds 99 pending")
    local restarted = newContext()
    baseline(restarted, copy(data))
    restarted.tick(0); noPopup(restarted, 0, "restarted module never replays previous process pending/history")
    local amount = append(restarted, data, 100)
    restarted.push(copy(data)); popup(restarted, 1, 100, amount)
    old.tick(0); noPopup(old, 0, "second module cannot modify first module pending")
end

local function timeCases()
    for _, mode in ipairs({ "expired-10-seconds", "expired-day", "no-time", "future-time" }) do
        local ctx, data = newContext(), { seeds = {} }
        baseline(ctx)
        local amount = append(ctx, data, 99)
        if mode == "no-time" then data.autoDecomposeNotice.time = nil
        elseif mode == "future-time" then data.autoDecomposeNotice.time = ctx.clock.now + 86400
        else data.autoDecomposeNotice.time = ctx.clock.now - (mode == "expired-day" and 86400 or 10) end
        ctx.push(copy(data)); noPopup(ctx, 0, mode .. " still waits for threshold")
        local one = append(ctx, data, 1, 99)
        if mode == "no-time" then data.autoDecomposeNotice.time = nil
        else data.autoDecomposeNotice.time = ctx.clock.now - 86400 end
        ctx.busy = true; ctx.push(copy(data))
        ctx.clock.now = ctx.clock.now + 1000000
        ctx.clock.elapsedTime = ctx.clock.elapsedTime + 1000000
        ctx.tick(1000000); noPopup(ctx, 0, mode .. " cannot replace busy reward")
        ctx.close(); ctx.tick(0)
        popup(ctx, 1, 100, amount + one)
    end
end

local function numericStringCases()
    local ctx = newContext()
    local data = dataWith(33857, 33857, 2302276)
    local function stringClone()
        local result = copy(data)
        for _, key in ipairs({ "seq", "count", "essence" }) do
            result.autoDecomposeNotice[key] = tostring(result.autoDecomposeNotice[key])
        end
        return result
    end
    baseline(ctx, stringClone(), { resetNotice = true })
    local a = append(ctx, data, 99)
    local first = stringClone()
    ctx.push(first); noPopup(ctx, 0, "numeric strings normalize without mutating input")
    eq(type(first.autoDecomposeNotice.seq), "string", "string seq remains string in caller input")
    ctx.push(copy(data)); noPopup(ctx, 0, "same values as numbers are duplicate, not reset/double count")
    local b = append(ctx, data, 3, 99)
    ctx.push(stringClone()); popup(ctx, 1, 102, a + b)
    ctx.close(); ctx.push(copy(data)); ctx.tick(0)
    popup(ctx, 1, 102, a + b)
    -- Lua 5.4 等值浮点也是有效整数值；显示必须规范成整数，不能出现“100.0 件”。
    local floating = newContext()
    baseline(floating, dataWith(0.0, 0.0, 0.0))
    local floatInput = dataWith(100.0, 100.0, 6800.0)
    floating.push(floatInput)
    popup(floating, 1, 100, 6800)
    floating.close(); floating.push(dataWith(100, 100, 6800)); floating.tick(0)
    popup(floating, 1, 100, 6800)
end

local function invalidCases()
    local invalids = {
        { label = "boolean notice", value = true }, { label = "false notice", value = false },
        { label = "scalar notice", value = 100 }, { label = "string notice", value = "notice" },
        { label = "empty notice", value = {} },
        { label = "missing seq", value = { count = 100, essence = 6000 } },
        { label = "missing count", value = { seq = 100, essence = 6000 } },
        { label = "missing essence", value = { seq = 100, count = 100 } },
    }
    local invalidValues = {
        { label = "negative", value = -1 }, { label = "fraction", value = 1.5 },
        { label = "negative string", value = "-1" }, { label = "fraction string", value = "1.5" },
        { label = "bad string", value = "not-an-integer" }, { label = "empty string", value = "" },
        { label = "true", value = true }, { label = "false", value = false },
        { label = "table", value = {} }, { label = "NaN", value = 0 / 0 },
        { label = "infinity", value = math.huge }, { label = "negative infinity", value = -math.huge },
        { label = "overflow string", value = "1e309" },
    }
    for _, key in ipairs({ "seq", "count", "essence" }) do
        for _, bad in ipairs(invalidValues) do
            ---@type table<string, any>
            local value = { seq = 700, count = 1200, essence = 120000 }
            value[key] = bad.value
            invalids[#invalids + 1] = { label = key .. " " .. bad.label, value = value }
        end
    end
    for _, sample in ipairs(invalids) do
        local ctx = newContext()
        baseline(ctx, dataWith(500, 1000, 100000))
        ctx.busy = true; ctx.push(dataWith(601, 1101, 110000))
        ctx.close()
        ctx.push({ seeds = {}, autoDecomposeNotice = copy(sample.value) })
        ctx.tick(0); noPopup(ctx, 0, sample.label .. " is silent reset, not an exception or queued old flush")
        -- 显式零值快照检验恢复基线，不依赖非法数值被截断/钳制成某个正数。
        ctx.push(dataWith(0, 0, 0)); noPopup(ctx, 0, sample.label .. " recovers to valid zero baseline")
        local valid = { seeds = {} }
        local a = append(ctx, valid, 99)
        ctx.push(copy(valid)); noPopup(ctx, 0, sample.label .. " old pending is discarded")
        local b = append(ctx, valid, 1, 99)
        ctx.push(copy(valid)); popup(ctx, 1, 100, a + b)
    end
end

local function summaryCases()
    local ctx = newContext()
    ctx.summary = {
        { index = 7, equip = { seq = 71 }, count = 9 },
        { index = 2, quality = 2, level = 24, count = 4 },
        { index = 11, quality = 3, level = 17 },
    }
    local wanted = copy(ctx.summary)
    local data = dataWith(33857, 33857, 2302276)
    data.seeds = { { quality = 2, level = 24, count = 4 }, { equip = { seq = 71 } } }
    ctx.loot.init({})
    eq(ctx.pageInits, 1, "init still delegates to mocked Page exactly once")
    ctx.pageOpen = true
    baseline(ctx, data, { resetNotice = true })
    eq(ctx.loot.getCount(), 6, "summary count remains equip=1 + stack=4 + default=1")
    check(same(ctx.refreshes[1], wanted), "open-page refresh retains equipment, count and original indices")
    eq(ctx.revealed, data, "revealLegacy receives original authoritative data")
    eq(ctx.summaryCalls[1], data, "getSummary receives original authoritative data")
    eq(ctx.events[1], "reveal", "summary refresh retains legacy reveal first")
    eq(ctx.events[2], "summary", "summary follows legacy reveal")
    local amount = append(ctx, data, 100)
    ctx.push(data); popup(ctx, 1, 100, amount)
    eq(ctx.loot.getCount(), 6, "notice flush does not affect seed count")
    check(same(ctx.refreshes[#ctx.refreshes], wanted), "notice flush does not replace/filter summary")
    local before = copy(data)
    ctx.loot.openPage(); ctx.loot.refreshPage(); ctx.tick(0.25)
    check(same(data, before), "page/refresh/update do not mutate input via test mocks")
    check(same(ctx.opens[1], wanted), "openPage still opens complete seed summary")
    eq(ctx.pageUpdates[#ctx.pageUpdates], 0.25, "page update still receives dt")
    ctx.pageOpen = false
    local refreshCount = #ctx.refreshes
    ctx.push(copy(data))
    eq(#ctx.refreshes, refreshCount, "closed page does not receive refresh")
    ctx.summary = {}
    ctx.close(); ctx.push({ seeds = {} }, { resetNotice = true })
    eq(ctx.loot.getCount(), 0, "save clear still clears seed count")
    ctx.safe()
end

local function bootFragmentCases()
    local text = source("boot.StandaloneBoot")
    local subscribeMarker = '    ClientDispatcher.subscribe("lootbox", function(data, moduleName)'
    local baselineMarker = '    LootBox.updateSeedData(ClientDispatcher.get("lootbox"), { resetNotice = true })'
    local killMarker = "    local function addKillEquipment(stageId, quality, level)"
    local endMarker = "    -- 5.245 击杀掉落："
    local function unique(marker)
        local first, last = text:find(marker, 1, true)
        check(first ~= nil, "real Boot fragment marker must exist: " .. marker)
        assert(first and last, "missing Boot marker")
        check(not text:find(marker, last + 1, true), "Boot fragment marker must be unique: " .. marker)
        return first, last
    end
    local subscribeStart = unique(subscribeMarker)
    local baselineStart, baselineEnd = unique(baselineMarker)
    local killStart = unique(killMarker)
    local killEnd = unique(endMarker)
    check(subscribeStart < baselineStart and baselineEnd < killStart and killStart < killEnd,
        "actual Boot subscribes then explicitly baselines before addKillEquipment")
    local setupText = text:sub(subscribeStart, baselineEnd)
    local killText = text:sub(killStart, killEnd - 1)
    check(not setupText:find("require", 1, true) and not killText:find("require", 1, true),
        "extracted Boot fragments do not load Boot dependencies")

    for _, restored in ipairs({ true, false }) do
        local ctx = newContext()
        local memory = { lootbox = restored and dataWith(33857, 33857, 2302276) or { seeds = {} },
            equipment = { settings = { autoQuality = 6, autoLevel = 60 } } } ---@type any
        local callbacks = {} ---@type table<string, function>
        local wallet = { essence = 1234, gold = 7654, writes = 0 }
        local trace = {} ---@type string[]
        local function strict(label, values)
            return setmetatable(values, { __index = function(_, key)
                error("unmocked Boot fragment dependency " .. label .. "." .. tostring(key))
            end })
        end
        -- 注入到本 ctx 私有 env，绝不替换宿主 _G 或真实 require/module cache。
        rawset(ctx.env, "LootBox", ctx.loot)
        rawset(ctx.env, "BlacksmithConfig", ctx.bc)
        rawset(ctx.env, "ClientDispatcher", strict("ClientDispatcher", {
            subscribe = function(name, callback)
                eq(name, "lootbox", "Boot only registers lootbox subscriber in selected fragment")
                trace[#trace + 1] = "subscribe"
                callbacks[name] = callback -- 特意不回放快照，必须由真实手动 resetNotice 基线完成。
            end,
            get = function(name)
                eq(name, "lootbox", "Boot reads restored in-memory lootbox")
                trace[#trace + 1] = "get"
                return memory.lootbox
            end,
        }))
        rawset(ctx.env, "PlayerStore", strict("PlayerStore", {
            Get = function(name)
                eq(name, "equipment", "kill fragment only reads equipment settings")
                return memory.equipment
            end,
        }))
        rawset(ctx.env, "LootBoxSystem", strict("LootBoxSystem", {
            consolidateSeeds = function(data) eq(data, memory.lootbox, "subscriber consolidates current snapshot") end,
            getTotalCount = function(data) return #(data.seeds or {}) end,
            -- addSeed 故意不开放：本组每件必须经真实自动分解路径。
        }))
        rawset(ctx.env, "BattleScene", strict("BattleScene", {
            getMaxStageId = function() return nil end, getCurrentStageId = function() return nil end,
        }))
        rawset(ctx.env, "StageConfig", strict("StageConfig", {
            getStage = function() error("no stage cap in isolated Boot fragment case") end,
        }))
        rawset(ctx.env, "GameState", strict("GameState", {
            getEssence = function() return wallet.essence end,
            setEssence = function(value) wallet.essence = value; wallet.writes = wallet.writes + 1 end,
            -- 不开放金币/文件/真实钱包方法，错误分支立即失败。
        }))
        local setup, setupWhy = load(setupText, "@boot/StandaloneBoot.lua:lootbox-wiring-fragment", "t", ctx.env)
        assert(setup, setupWhy)
        local kills, killWhy = load(killText .. "\nreturn addKillEquipment",
            "@boot/StandaloneBoot.lua:addKillEquipment-fragment", "t", ctx.env)
        assert(kills, killWhy)
        local addKill = kills()
        check(type(addKill) == "function", "real Boot fragment exports captured local addKillEquipment")
        setup()
        eq(trace[1], "subscribe", "real Boot setup first registers non-replaying subscriber")
        eq(trace[2], "get", "real Boot setup explicitly fetches restored snapshot after registration")
        eq(#ctx.summaryCalls, 1, "manual baseline really reaches LootBox without subscriber replay")
        eq(ctx.summaryCalls[1], memory.lootbox, "baseline uses pre-restored snapshot identity")
        ctx.tick(0); noPopup(ctx, 0, "restored history or missing notice bootstrap is silent")
        eq(wallet.essence, 1234, "bootstrap does not award historical essence")
        local function batch()
            local initial = wallet.essence
            local initialCount = memory.lootbox.autoDecomposeNotice and memory.lootbox.autoDecomposeNotice.count or 0
            local initialNoticeEssence = memory.lootbox.autoDecomposeNotice and memory.lootbox.autoDecomposeNotice.essence or 0
            local sum = 0
            for i = 1, 100 do
                local item = ITEMS[((i - 1) % #ITEMS) + 1]
                local gain = ctx.bc.calcAutoDecomposeEssence(item.quality, item.level)
                sum = sum + gain
                addKill(101, item.quality, item.level)
                eq(wallet.essence, initial + sum, "each real kill immediately credits exact real-BC essence")
                eq(memory.lootbox.autoDecomposeNotice.count, initialCount + i, "each real kill records cumulative count")
                eq(memory.lootbox.autoDecomposeNotice.essence, initialNoticeEssence + sum,
                    "real kill notification keeps historical essence and adds only real item gains")
                noPopup(ctx, 0, "kill receipt itself never shows or waits for the 100-item reward")
                if i < 100 then ctx.tick(0); noPopup(ctx, 0, "first 99 are credited but notification remains below threshold") end
            end
            eq(wallet.gold, 7654, "selected kill-equipment fragment never changes gold")
            eq(wallet.writes, 100, "wallet credited once per item, not on UI display")
            popup(ctx, 1, 100, sum)
            eq(wallet.essence, initial + sum, "UI threshold display cannot credit wallet again")
            ctx.close()
            callbacks.lootbox(memory.lootbox, "lootbox")
            ctx.tick(0); popup(ctx, 1, 100, sum)
            eq(wallet.essence, initial + sum, "same-table subscriber duplicate cannot re-award")
            return sum
        end
        batch()
        -- 清档后再次执行真实注册/显式baseline片段，不运行全Boot/StandaloneSave生命周期。
        memory.lootbox = { seeds = {} }
        wallet.writes = 0
        ctx.popups, ctx.active, ctx.busy = {}, false, false
        setup(); ctx.tick(0)
        noPopup(ctx, 0, "clear boot wiring establishes fresh zero baseline")
        batch()
        ctx.safe()
    end
end

local function finalSafetyCases()
    for _, ctx in ipairs(contexts) do ctx.safe() end
    eq(cache, nativeCache, "global cache untouched")
    eq(File, nativeFile, "global File untouched")
    eq(require, nativeRequire, "global require untouched")
    eq(io, nativeIO, "global io untouched")
    eq(os, nativeOS, "global os untouched")
    eq(network, nativeNetwork, "global network untouched")
    eq(clientCloud, nativeCloud, "global clientCloud untouched")
    eq(serverCloud, nativeServerCloud, "global serverCloud untouched")
    eq(time, nativeTime, "global runtime clock untouched")
    eq(package, nativePackage, "global package untouched")
    eq(package.loaded, nativeLoaded, "global package.loaded identity untouched")
    for name, value in pairs(initialLoaded) do eq(nativeLoaded[name], value, "existing module untouched " .. name) end
    for name, value in pairs(nativeLoaded) do eq(initialLoaded[name], value, "no module escaped isolated loader " .. name) end
    eq(#sourceReads, 3, "exactly three real source reads across every fresh env")
    local seen = {}
    for _, path in ipairs(sourceReads) do
        check(path == "ui/loot/LootBox.lua" or path == "config/BlacksmithConfig.lua"
            or path == "boot/StandaloneBoot.lua", "cache read is exact allowlist source")
        check(not seen[path], "source cache prevents repeated real reads")
        seen[path] = true
    end
    check(seen["ui/loot/LootBox.lua"] and seen["config/BlacksmithConfig.lua"]
        and seen["boot/StandaloneBoot.lua"], "all tested implementations and Boot fragments are real production sources")
end

function Start()
    local ok, why = pcall(function()
        local tests = {
            { "fail-closed-load-env-isolation", isolationCases },
            { "real-BC-formula-and-original-cumulative-recorder", recorderCases },
            { "bootstrap-33857-2302276-history-then-new-100-in-place", bootstrapHistoryCases },
            { "implicit-first-baseline-and-missing-notice-zero", firstSnapshotCases },
            { "threshold-99-100-101-33857-and-99-plus-3", thresholdCases },
            { "100-single-pushes-and-cleared-pending", incrementalCases },
            { "independent-monotonic-seq-count-essence-deltas", monotonicCounterCases },
            { "two-consecutive-batches-no-replay", consecutiveBatchCases },
            { "busy-many-pushes-merge-on-idle-update", busyMergeCases },
            { "deferred-update-pump-preserves-same-frame-settlement-popup", pushPumpCases },
            { "reentrant-duplicate-and-new-notice-during-show", reentryCases },
            { "explicit-reset-clears-ready-and-partial-pending", explicitResetCases },
            { "rollback-or-same-seq-content-change-rebaseline", rollbackCases },
            { "no-notice-nil-empty-save-clear-zero-baseline", missingNoticeCases },
            { "restart-does-not-replay-previous-process-pending", restartCases },
            { "expired-time-no-time-and-long-busy-no-loss", timeCases },
            { "clone-numeric-strings-normalized-without-input-mutation", numericStringCases },
            { "invalid-nonnegative-integer-fields-reset-without-throw", invalidCases },
            { "seed-summary-count-refresh-page-update-preserved", summaryCases },
            { "real-Boot-fragments-restore-baseline-kill-credit-and-clear", bootFragmentCases },
            { "final-all-contexts-source-reads-and-global-safety", finalSafetyCases },
        }
        for _, test in ipairs(tests) do
            groups = groups + 1
            local passed, reason = pcall(test[2])
            if passed then print(TAG .. "[PASS] " .. test[1])
            else
                local message = test[1] .. " " .. tostring(reason)
                failures[#failures + 1] = message
                print(TAG .. "[FAIL] " .. message)
                log:Write(LOG_ERROR, TAG .. message)
            end
        end
    end)
    if not ok then
        failures[#failures + 1] = "harness " .. tostring(why)
        log:Write(LOG_ERROR, TAG .. "HARNESS FAIL " .. tostring(why))
    end
    local result = (#failures == 0 and "ALL PASS" or "FAIL")
        .. " groups=" .. groups .. " checks=" .. checks .. " failures=" .. #failures
    print(TAG .. "RESULT " .. result)
    if #failures > 0 then log:Write(LOG_ERROR, TAG .. "RESULT " .. result) end
    -- engine:Exit 不提供退出码参数；调用方以 RESULT/failures 和 LOG_ERROR 判定失败。
    engine:Exit()
end
