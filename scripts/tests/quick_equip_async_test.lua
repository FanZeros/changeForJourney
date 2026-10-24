-- 独立 Runtime；真实 Fixture/Bridge/Handler/Service/PDM/Dispatcher/PlayerStore。
-- 不启动 main/Boot，不读取玩家档；File/FS/RNG/生产资源访问全部封闭。
-- 内部 runner 显式设置 QUICK_EQUIP_FROZEN_ORACLE=true 并把冻结旧 scripts 映射
-- 至 __quick_equip_oracle/；旧 Fixture/Service/依赖只从此前缀编译，缺件失败不回退。
-- 正式直接运行使用本轮真实旧源导出的固定expected；未启用外部oracle明确NOT RUN。
-- 当前测试不固定具体毫秒/检查点数，不用软件CPU样本冒充设备帧率或持久化验收。
local TAG = "[quick_equip_async_test]"
local ORACLE_PREFIX = "__quick_equip_oracle/"
local checks, groups, failures = 0, 0, {}
local harnesses = {}
---@type table<string, table<string, number>>
local sourceReads = { current = {}, oracle = {} }
local nativeCache = cache
local function noop() end
local function check(value, why)
    checks = checks + 1
    assert(value, why)
end
local function group(name, fn)
    groups = groups + 1
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        print(TAG .. " PASS " .. name)
    else
        failures[#failures + 1] = name .. " " .. tostring(err)
        print(TAG .. " FAIL " .. name .. " " .. tostring(err))
    end
end

-- Fixture 的源码读取闭包也隔离：只有 .lua cache 读取可以触达原生资源层。
-- 业务代码看不到 nativeCache；旧 require 不使用 package.loaded 或外部 require。
local function fixtureFor(prefix)
    local kind = prefix == "" and "current" or "oracle"
    local scriptCache = { GetFile = function(_, path)
        assert(type(path) == "string" and path:match("^[%w_/]+%.lua$")
            and not path:find("..", 1, true), "script-only source path")
        local resource = prefix .. path
        sourceReads[kind][resource] = (sourceReads[kind][resource] or 0) + 1
        return assert(nativeCache:GetFile(resource), "missing frozen script; no fallback: " .. resource)
    end }
    local file = scriptCache:GetFile("tests/InventoryCurationFixture.lua")
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local env = setmetatable({ cache = scriptCache }, { __index = _G })
    env._G = env
    env.require = function(name) error("external fixture require forbidden: " .. tostring(name)) end
    return assert(load(table.concat(lines, "\n"), "@" .. prefix .. "tests/InventoryCurationFixture.lua", "t", env))()
end

local function seal(h)
    h.blockedIo = 0
    local function deny()
        h.blockedIo = h.blockedIo + 1
        error("quick equip production I/O forbidden", 0)
    end
    -- 即使 Fixture 支持内存存档，此专项也要求连虚拟File/FS调用都为零。
    h.env.File = deny
    h.env.fileSystem = setmetatable({}, { __index = function() return deny end })
    h.env.cache = { GetFile = deny, GetResource = deny }
    h.env.io = setmetatable({}, { __index = function() return deny end })
    h.env.os.execute, h.env.os.remove, h.env.os.rename = deny, deny, deny
    h.env.dofile, h.env.loadfile = deny, deny
    local realRequire = h.require
    h.require = function(name)
        assert(not name:match("^boot%."), "Boot/Save forbidden in quick equip test: " .. name)
        assert(not name:match("^urhox%-libs"), "UI/engine library unnecessary in quick equip test")
        return realRequire(name)
    end
    h.env.require = h.require
    harnesses[#harnesses + 1] = h
end

local function fill(F, h, spec)
    local data = F.modules(h, 0)
    local heroId = spec.heroId or 1
    data.heroes.roster[heroId] = { level = spec.heroLevel or 100 }
    data.heroes.deployed = { heroId, 2, 3, 9 }
    data.heroes.teams[1].slots = { heroId, 2, 3, 9 }
    for _, id in ipairs({ 2, 3, 9 }) do data.heroes.roster[id] = { level = 100 } end
    if spec.dual == "different" then
        data.heroes.roster[heroId].advBranch = { first = 103, second = 207 }
    elseif spec.dual == "same" then
        data.heroes.roster[heroId].advBranch = { first = 110, second = 220 }
    end
    local templates = spec.templates or { "W1", "W13", "W7", "O1", "O7", "A13", "H13", "S13", "C1", "W25", "O13", "A49" }
    local ordinary = { "A1", "H1", "S1", "C1" }
    for seq = 1, spec.count do
        local template
        if spec.weapons then
            if seq <= spec.weapons then template = "W1"
            elseif seq <= spec.weapons + spec.offhands then template = spec.dual and "W13" or "O1"
            else template = ordinary[(seq - 1) % #ordinary + 1] end
        else
            template = templates[(seq - 1) % #templates + 1]
        end
        local item = F.item(h, template, spec.varied and ((seq - 1) % 12 + 1) or 1, 1)
        item.seq = seq
        if spec.varied and seq % 4 == 0 then
            item.ascendLevel = seq % 13
            item.affixes = { { id = 1, key = "str", value = seq % 7 + 1, quality = 1 } }
        end
        data.equipment.inventory[tostring(seq)] = item
    end
    data.equipment.nextSeq = spec.count + 1
    if spec.initial then
        data.equipment.equipped[heroId] = F.copy(spec.initial)
    end
    if spec.occupied then data.equipment.equipped[2] = F.copy(spec.occupied) end
    if spec.edit then spec.edit(data) end
    for _, name in ipairs({ "talents", "artifacts", "slotEnhance", "task", "redeem", "signin",
        "market", "tavern", "dungeon", "global_profile", "quotas" }) do
        data[name] = data[name] or {}
    end
    return data
end

local function newHarness(F, spec, bridge)
    local h = F.new()
    seal(h)
    h.F = F
    local data = fill(F, h, spec)
    -- 正式GameState镜像会补齐货币标量；先构造完整默认货币，避免把Fixture缺字段
    -- 引起的无关镜像补值误报成一键装备的提前写入。
    local currency = h.require("shared.schemas.CharacterSchema").Fields.currency.getDefault()
    for key, value in pairs(data.currency) do currency[key] = value end
    data.currency = currency
    h:attach(data)
    h.data, h.heroId = h.modules, spec.heroId or 1
    h.results, h.notifications, h.dirties, h.handlerCalls = {}, {}, {}, {}
    h.evaluations, h.evaluationTrace = 0, {}
    h.Service = h.require("rules.equipment.EquipmentService")
    h.Store = h.require("core.PlayerStore")
    local EP = h.require("systems.EquipmentPower")
    local evaluate = EP.evaluateLoadout
    EP.evaluateLoadout = function(...)
        h.evaluations = h.evaluations + 1
        local result = evaluate(...)
        h.evaluationTrace[#h.evaluationTrace + 1] = result and {
            valid = result.valid, gain = result.gain, previewPower = result.previewPower,
        } or { noResult = true }
        return result
    end
    if bridge then
        h.allowBootFixture = true -- Fixture原门禁仅为Bridge开放；外层require仍拒绝任何Boot。
        for _, name in ipairs({ "battle.Battle", "hero.Hero", "gacha.Gacha", "blacksmith.Blacksmith",
            "task.Task", "redeem.Redeem", "awakening.Awakening", "advancement.Advancement",
            "talent.Talent", "signin.SignIn", "gm.GM", "market.Market", "loot.Loot", "sweep.Sweep",
            "artifact.Artifact", "dungeon.Dungeon", "offline.Offline", "tower.Tower" }) do
            h.mocks["rules." .. name .. "Handler"] = { actionHandlers = {} }
        end
        h.mocks["rules.task.TaskService"] = { SetPersistCallback = noop }
        if spec.testReset then
            h.mocks["rules.gm.GMHandler"].actionHandlers[h.require("shared.Protocol").ACTION_TYPES.GM_RESET_SAVE] = function()
                check(not h.Bridge.isQuickEquipPending(), "real Bridge cancels pending job before explicit reset seam")
                h.resetCalled = true
                return { success = true }
            end
        end
        h.mocks["rules.dungeon.DungeonService"] = { SetPersistCallback = noop }
        h.mocks["rules.redeem.RedeemService"] = { Init = noop }
        -- 只替换最终显示消费者，真实回执内容完全由Bridge/Handler生成。
        h.mocks["runtime.ClientMessageHandler"] = { handleActionResult = function(result)
            h.results[#h.results + 1] = F.copy(result)
            if h.onResult then h.onResult(result) end
        end }
        local State = h.require("core.GameState")
        State.syncPlayerData(h.data.player)
        State.syncFromCurrency(h.data.currency)
        h.AT = h.require("shared.Protocol").ACTION_TYPES
        local Handler = h.require("rules.equipment.EquipmentHandler")
        local handler = assert(Handler.actionHandlers[h.AT.EQUIP_ALL_BEST])
        Handler.actionHandlers[h.AT.EQUIP_ALL_BEST] = function(uid, params, control)
            h.handlerCalls[#h.handlerCalls + 1] = { uid = uid, params = F.copy(params), async = control ~= nil }
            return handler(uid, params, control)
        end
        h.Bridge = h.require("runtime.LocalActionBridge")
        h.Bridge.init()
        check(type(h.Bridge.isQuickEquipPending) == "function", "pending API exists")
        check(type(h.Bridge.cancelQuickEquip) == "function", "cancel API exists")
        check(type(h.Bridge.updateQuickEquip) == "function", "pump API exists")
    else
        -- 同步Service仍沿原调度通知；本专项不伪称已经Flush。
        h.PDM.Setup({ serverDispatcher = { pushModule = function(_, name, value)
            h.Dispatcher.set(name, value, { normalized = true })
        end } })
    end
    local mark = h.PDM.MarkDirty
    h.PDM.MarkDirty = function(uid, name)
        h.dirties[#h.dirties + 1] = name
        return mark(uid, name)
    end
    h.Store.Subscribe("equipment", function(value)
        h.notifications[#h.notifications + 1] = { module = value, equipped = F.copy(value.equipped) }
    end)
    return h
end

local function attachRealMessageHandler(h)
    local F = h.F
    h.feedback = { toasts = {}, sounds = {}, tutorials = {}, pages = {}, errors = {} }
    local feedback = h.feedback
    for _, name in ipairs({ "ui.hud.popup.RewardPopup", "ui.loot.LootBox", "ui.loot.LootBoxPage",
        "ui.blacksmith.BlacksmithPage", "ui.backpack.BackpackPanel", "ui.church.ChurchPage",
        "ui.church.talent.TalentPage", "ui.tavern.TavernPage", "ui.market.MarketPage",
        "ui.dungeon.DungeonPage", "ui.dungeon.DungeonBattleScene", "ui.dev.GMConsolePanel",
        "ui.hud.TopBar", "ui.character.panel.CharacterPanel", "ui.character.equip.EquipmentDetail",
        "ui.hud.popup.RedeemCodePanel" }) do
        local pageName = name
        h.mocks[name] = { onActionResult = function()
            feedback.pages[#feedback.pages + 1] = pageName
        end }
    end
    h.mocks["systems.TutorialManager"] = { notifyEvent = function(name)
        feedback.tutorials[#feedback.tutorials + 1] = name
    end }
    h.mocks["systems.GameSFX"] = { play = function(name) feedback.sounds[#feedback.sounds + 1] = name end }
    h.mocks["core.UiToast"] = { show = function(text) feedback.toasts[#feedback.toasts + 1] = text end }
    h.mocks["runtime.ClientMessageHandler"] = nil
    local Msg = h.require("runtime.ClientMessageHandler")
    Msg.setup({ sendAction = noop, ui = {} })
    local receive = Msg.handleActionResult
    Msg.handleActionResult = function(data)
        h.results[#h.results + 1] = F.copy(data)
        local ok, err = pcall(receive, data)
        if not ok then feedback.errors[#feedback.errors + 1] = tostring(err); error(err) end
    end
    h.Msg = Msg
    return feedback
end

local function feedbackIs(h, key, sound, tutorialCount)
    local feedback = h.feedback
    check(#feedback.errors == 0, "real CMH completed without swallowed handler errors")
    check(#feedback.toasts == 1 and feedback.toasts[1] == h.require("core.I18n").t(key), "real CMH emits expected localized feedback " .. key)
    check(#feedback.pages == 0, "async completion must not route into unrelated newly opened pages")
    check(#feedback.tutorials == tutorialCount, "only authoritative successful equip notifies tutorial")
    if tutorialCount > 0 then check(feedback.tutorials[1] == "equipment_equipped", "original tutorial event retained") end
    check(#feedback.sounds == (sound and 1 or 0), "only positive actual changes play install")
    if sound then check(feedback.sounds[1] == "install", "real CMH selected install SFX") end
end

local function isolated(h)
    check(h.blockedIo == 0 and h.fileCalls == 0 and h.fsCalls == 0 and h.randomCalls == 0,
        "File/FS/cache/io/RNG remain unused")
    for name in pairs(h.loaded) do check(not name:match("^boot%."), "no Boot modules loaded") end
end

local function start(h, heroId)
    local before = h.F.copy(h.data)
    local edges = h.F.aliases(h.data)
    local n, d, r, calls = #h.notifications, #h.dirties, #h.results, #h.handlerCalls
    local dispatchStart = os.clock()
    check(h.Bridge.dispatch(h.AT.EQUIP_ALL_BEST, { heroId = heroId or h.heroId }), "dispatch handled")
    h.dispatchMs = (os.clock() - dispatchStart) * 1000
    check(h.Bridge.isQuickEquipPending(), "dispatch only queues a pending job")
    check(#h.handlerCalls == calls and h.evaluations == 0, "dispatch does not run handler/search")
    check(#h.results == r and #h.notifications == n and #h.dirties == d, "dispatch neither writes nor replies/notifies")
    h.F.same(h.data, before)
    h.F.assertAliases(edges)
    return before
end

local function pump(h, untilEvaluation)
    local count, maximum, total, slices = 0, 0, 0, {}
    while h.Bridge.isQuickEquipPending() do
        count = count + 1
        check(count <= 30000, "cooperative worker must finish within bounded pumps")
        local previous = #h.notifications
        if h.beforePump then h.beforePump() end
        local begun = os.clock()
        h.Bridge.updateQuickEquip()
        local elapsed = (os.clock() - begun) * 1000
        slices[#slices + 1] = elapsed
        maximum, total = math.max(maximum, elapsed), total + elapsed
        check(#h.notifications - previous <= 1, "one pump cannot duplicate equipment publish")
        if untilEvaluation and h.evaluations > 0 then
            check(h.Bridge.isQuickEquipPending(), "change injected after snapshot/search but before commit")
            break
        end
    end
    table.sort(slices)
    h.lastPump = { count = count, maximum = maximum, total = total, p95 = slices[math.max(1, math.ceil(#slices * 0.95))] or 0 }
    print(string.format("%s pumps=%d peakSoftwareCpuMs=%.3f p95Ms=%.3f totalCpuMs=%.3f theoretical60FpsSeconds=%.3f partial=%s",
        TAG, count, maximum, h.lastPump.p95, total, count / 60, tostring(untilEvaluation == true)))
    return count
end

local function assertAck(h, success, heroId)
    check(#h.results == 1, "exactly one final ack")
    local result = h.results[1]
    check(result.action == h.AT.EQUIP_ALL_BEST and result.heroId == (heroId or h.heroId), "ack preserves action and hero identity")
    check(type(result.quickEquipId) == "number" and result.quickEquipId > 0, "ack carries positive quickEquipId")
    check(result.success == success, "ack success agrees with authoritative commit")
    check(not h.Bridge.isQuickEquipPending(), "completed job releases busy")
    local before = h.F.copy(h.data)
    for _ = 1, 4 do h.Bridge.updateQuickEquip() end
    h.F.same(h.data, before)
    check(#h.results == 1, "idle pumps never replay final ack")
    return result
end

local function largeSpec()
    return { count = 200, weapons = 20, offhands = 20 }
end

local function run()
    local F = fixtureFor("")
    local externalOracle = rawget(_G, "QUICK_EQUIP_FROZEN_ORACLE") == true
    local OldF = externalOracle and fixtureFor(ORACLE_PREFIX) or nil
    if not externalOracle then print(TAG .. " NOT RUN external frozen-source oracle (explicit runner opt-in required)") end
    -- 2026-10-16完整冻结旧Service真实Runtime导出；不是从新算法推导，也不放宽同分。
    local expected = {
        { changes = 3, slots = { weapon = 1, offhand = 21, accessory = 44 } },
        { changes = 3, slots = { weapon = 1, offhand = 51, accessory = 104 } },
        { changes = 3, slots = { weapon = 1, offhand = 41, accessory = 84 } },
        { changes = 5, slots = { weapon = 2, offhand = 4, armor = 6, helmet = 7, shoes = 20, accessory = 21 } },
        { changes = 6, slots = { weapon = 10, offhand = 18, armor = 21, helmet = 22, shoes = 23, accessory = 24 } },
        { changes = 6, slots = { weapon = 10, offhand = 12, armor = 21, helmet = 22, shoes = 23, accessory = 24 } },
        { changes = 1, slots = { weapon = 1 } },
        { changes = 0 },
    }
    local samples = {
        { name = "200 ordinary original probe", count = 200, weapons = 20, offhands = 20 },
        { name = "500 ordinary original probe", count = 500, weapons = 50, offhands = 50 },
        { name = "500 different-type dual original probe", count = 500, weapons = 40, offhands = 40, dual = "different" },
        { name = "varied values, set pieces, occupied other hero", count = 36, varied = true,
            initial = { weapon = 3, armor = 6 }, occupied = { weapon = 1, accessory = 9 } },
        { name = "same-type dual", count = 30, heroId = 8, dual = "same", varied = true,
            templates = { "W1", "W61", "W13", "O1", "A1", "H1", "S1", "C1" } },
        { name = "magical hero whole-loadout", count = 30, heroId = 2, varied = true,
            templates = { "W25", "W31", "O13", "O19", "A49", "H49", "S49", "C7" } },
        { name = "level-gate", count = 24, heroLevel = 1, varied = true },
        { name = "empty inventory", count = 0 },
    }
    for sampleIndex, spec in ipairs(samples) do
        group("fixed baseline + sync/async + optional frozen-old " .. spec.name, function()
            local sync, async = newHarness(F, spec, false), newHarness(F, spec, true)
            local initial = F.copy(async.data)
            local aliases = F.aliases(async.data)
            local baseline = assert(expected[sampleIndex])
            local oldMs, oldEvaluations = 0, 0
            local old = nil ---@type table?
            if OldF then
                old = newHarness(OldF, spec, false)
                local oldStart = os.clock()
                local oldOk, oldReason, oldResult = old.Service.EquipAllBest(1, old.heroId)
                oldMs, oldEvaluations = (os.clock() - oldStart) * 1000, old.evaluations
                check(oldOk, "genuine frozen synchronous algorithm accepted: " .. tostring(oldReason))
                check(oldResult.changes == baseline.changes, "fixed changes match genuine frozen old export")
                F.same(old.data.equipment.equipped[old.heroId], baseline.slots)
            end
            local syncStart = os.clock()
            local syncOk, syncReason, syncResult = sync.Service.EquipAllBest(1, sync.heroId)
            local syncMs = (os.clock() - syncStart) * 1000
            check(syncOk, "new sync algorithm accepted: " .. tostring(syncReason))
            check(syncResult.changes == baseline.changes, "new sync changes match fixed old export")
            F.same(sync.data.equipment.equipped[sync.heroId], baseline.slots)
            if old then
                F.same(sync.data.equipment, old.data.equipment)
                F.same(sync.data.heroes, old.data.heroes)
            end
            start(async)
            local pumps = pump(async)
            local result = assertAck(async, true)
            check(result.changes == baseline.changes, "async changes exactly match frozen baseline")
            F.same(async.data.equipment.equipped[async.heroId], baseline.slots)
            F.same(async.data.equipment, sync.data.equipment)
            F.same(async.evaluationTrace, sync.evaluationTrace)
            if old then
                -- 逐候选valid/gain/previewPower严格相等；不只看最后胜出的六槽。
                F.same(async.evaluationTrace, old.evaluationTrace)
                F.same(async.data.equipment, old.data.equipment)
            end
            F.same(async.data.heroes, initial.heroes)
            F.same(async.data.equipment.inventory, initial.equipment.inventory)
            F.assertAliases(aliases)
            local changed = baseline.changes > 0 and 1 or 0
            check(#sync.notifications == changed and #async.notifications == changed,
                "each algorithm publishes once only if actual slots changed")
            if old then check(#old.notifications == changed, "frozen old publishes expected count") end
            check(#async.dirties == changed, "no speculative MarkDirty")
            if changed > 0 then
                check(async.notifications[1].module == async.data.equipment, "same live equipment table published")
                F.same(async.notifications[1].equipped, async.data.equipment.equipped)
            end
            check(#async.handlerCalls == 1 and async.handlerCalls[1].async, "real Handler receives async control once")
            if spec.count >= 200 then
                check(pumps > 1, "large workload is genuinely sliced, not delayed one-shot")
                print(string.format("%s PERF sample=%s dispatchCpuMs=%.3f pumps=%d sliceMaxMs=%.3f sliceP95Ms=%.3f totalPumpCpuMs=%.3f theoretical60FpsSeconds=%.3f oldSyncMs=%.3f newSyncMs=%.3f changes=%d evaluations=%d oldEvaluations=%d notifications=%d externalOld=%s",
                    TAG, spec.name, async.dispatchMs, pumps, async.lastPump.maximum, async.lastPump.p95,
                    async.lastPump.total, pumps / 60, oldMs, syncMs, result.changes,
                    async.evaluations, oldEvaluations, #async.notifications, tostring(old ~= nil)))
            end
            if old then isolated(old) end
            isolated(sync); isolated(async)
        end)
    end

    group("busy duplicates preserve original task and owned request params", function()
        local h = newHarness(F, largeSpec(), true)
        local params = { heroId = 1 }
        local before = F.copy(h.data)
        check(h.Bridge.dispatch(h.AT.EQUIP_ALL_BEST, params), "first queued")
        params.heroId = 2 -- 修改调用方table不能重定向已经接受的任务。
        check(h.Bridge.dispatch(h.AT.EQUIP_ALL_BEST, { heroId = 2 }), "busy duplicate is consumed")
        check(h.Bridge.dispatch(h.AT.EQUIP_ALL_BEST, { heroId = 1 }), "same-hero duplicate is consumed")
        F.same(h.data, before)
        check(#h.results == 0 and #h.handlerCalls == 0, "busy repeats do not execute or ack another job")
        pump(h)
        assertAck(h, true, 1)
        check(#h.handlerCalls == 1 and h.handlerCalls[1].params.heroId == 1, "original identity survives busy and caller mutation")
        check(#h.notifications == 1 and #h.dirties == 1, "busy repeats cannot duplicate commit")
        isolated(h)
    end)

    for _, name in ipairs({ "equipment", "artifacts", "talents" }) do
        for _, mode in ipairs({ "revision ABA", "in-place value", "module reference" }) do
            group("stale rejection " .. name .. " / " .. mode, function()
                local h = newHarness(F, largeSpec(), true)
                start(h)
                pump(h, true)
                local revision = h.Store.GetRevision(name)
                if mode == "revision ABA" then
                    -- 值和引用均未改变，但正式revision已经前进，旧任务也必须拒绝。
                    h.Dispatcher.set(name, h.data[name], { normalized = true })
                    h.Dispatcher.set(name, h.data[name], { normalized = true })
                    check(h.Store.GetRevision(name) > revision, "real revision advanced for ABA")
                elseif mode == "module reference" then
                    h.data[name] = F.copy(h.data[name])
                    check(h.Store.GetRevision(name) == revision, "reference replacement deliberately unnotified")
                elseif name == "equipment" then
                    h.data.equipment.inventory["1"].ascendLevel = 7
                elseif name == "artifacts" then
                    h.data.artifacts.bag = { { id = 100, artifactId = 1, quality = 1 } }
                else
                    h.data.talents.litNodes = { [0] = true, [1] = true }
                end
                if mode == "in-place value" then check(h.Store.GetRevision(name) == revision, "in-place mutation bypasses revision intentionally") end
                local afterExternalChange = F.copy(h.data)
                local aliases = F.aliases(h.data)
                local notified, dirty = #h.notifications, #h.dirties
                pump(h)
                local result = assertAck(h, false)
                check(result.reason == "quick_equip_stale", "stale has explicit reason")
                F.same(h.data, afterExternalChange)
                F.assertAliases(aliases)
                check(#h.notifications == notified and #h.dirties == dirty, "stale job neither mutates nor publishes after external change")
                isolated(h)
            end)
        end
    end

    group("clear-cache revision invalidates same PDM references", function()
        local h = newHarness(F, largeSpec(), true)
        local before = start(h)
        h.Store.ClearCache()
        pump(h)
        check(assertAck(h, false).reason == "quick_equip_stale", "reset invalidates pending job")
        F.same(h.data, before)
        check(#h.notifications == 0 and #h.dirties == 0, "reset cannot commit old loadout")
        isolated(h)
    end)

    group("cancel drops old task and reply; new task has distinct increasing identity", function()
        local h = newHarness(F, largeSpec(), true)
        start(h); pump(h)
        local first = assertAck(h, true).quickEquipId
        h.results, h.notifications, h.dirties, h.handlerCalls = {}, {}, {}, {}
        h.evaluations = 0
        local before = start(h)
        pump(h, true)
        h.Bridge.cancelQuickEquip()
        check(not h.Bridge.isQuickEquipPending(), "cancel immediately releases busy")
        for _ = 1, 5 do h.Bridge.updateQuickEquip() end
        F.same(h.data, before)
        check(#h.results == 0 and #h.notifications == 0 and #h.dirties == 0, "cancel does not complete or publish old task")
        h.evaluations, h.handlerCalls = 0, {}
        start(h, 2); pump(h)
        local nextResult = assertAck(h, true, 2)
        check(nextResult.quickEquipId > first + 1, "cancelled identity is not reused by next task")
        check(#h.handlerCalls == 1 and h.handlerCalls[1].params.heroId == 2, "only fresh task executes after cancel")
        isolated(h)
    end)

    group("committed notification throw retains successful authoritative ack", function()
        local h = newHarness(F, largeSpec(), true)
        local old = newHarness(OldF or F, largeSpec(), false)
        local ok, reason, oracle = old.Service.EquipAllBest(1, 1)
        check(ok, "independent sync oracle accepted " .. tostring(reason))
        local throws = 0
        h.Dispatcher.setOnAnyUpdate(function(modules)
            if modules.equipment then
                throws = throws + 1
                error("expected post-commit quick equip notification exception")
            end
        end)
        start(h); pump(h)
        local result = assertAck(h, true)
        check(throws == 1 and #h.notifications == 1 and #h.dirties == 1, "real Dispatcher post-commit failure is attempted only once")
        check(result.changes == oracle.changes, "notification failure ack retains committed changes")
        F.same(h.data.equipment, old.data.equipment)
        h.Dispatcher.setOnAnyUpdate(nil)
        isolated(h); isolated(old)
    end)

    group("notification reentry cancels old epoch without clearing new task", function()
        local h = newHarness(F, largeSpec(), true)
        local injected = false
        h.Store.Subscribe("equipment", function()
            if injected then return end
            injected = true
            h.Bridge.cancelQuickEquip()
            check(h.Bridge.dispatch(h.AT.EQUIP_ALL_BEST, { heroId = 2 }), "subscriber queues fresh task after cancel")
        end)
        start(h)
        local frames = 0
        while not injected do
            frames = frames + 1
            check(frames <= 30000, "first commit notification reached")
            h.Bridge.updateQuickEquip()
        end
        check(h.Bridge.isQuickEquipPending() and #h.results == 0, "old worker neither clears nor replies for new epoch")
        pump(h)
        local result = assertAck(h, true, 2)
        check(result.quickEquipId >= 2, "new task owns its distinct identity")
        check(#h.handlerCalls == 2 and #h.notifications == 2 and #h.dirties == 2, "each real committed hero publishes once")
        isolated(h)
    end)

    group("invalid hero is asynchronously rejected without mutation", function()
        local h = newHarness(F, largeSpec(), true)
        local before = start(h, 99999)
        pump(h)
        local result = assertAck(h, false, 99999)
        check(result.reason == "英雄不存在", "real Service validates hero")
        F.same(h.data, before)
        check(#h.dirties == 0 and #h.notifications == 0, "invalid hero cannot publish")
        isolated(h)
    end)

    group("continuous in-place hero exp/maxExp preserves progress and completes", function()
        local h = newHarness(F, largeSpec(), true)
        local initial = start(h)
        local revision = h.Store.GetRevision("heroes")
        local ticks = 0
        h.beforePump = function()
            ticks = ticks + 1
            h.data.heroes.roster[1].exp = ticks
            h.data.heroes.roster[1].maxExp = 10000 + ticks
            h.data.heroes.roster[2].exp = ticks * 2
            h.data.heroes.roster[2].maxExp = 20000 + ticks
        end
        pump(h)
        assertAck(h, true)
        check(ticks > 1 and #h.notifications == 1, "continuous pure experience does not starve equip")
        check(h.Store.GetRevision("heroes") == revision, "experience changes intentionally unnotified")
        check(h.data.heroes.roster[1].exp == ticks and h.data.heroes.roster[1].maxExp == 10000 + ticks
            and h.data.heroes.roster[2].exp == ticks * 2 and h.data.heroes.roster[2].maxExp == 20000 + ticks,
            "commit never overwrites newest target/teammate experience")
        initial.heroes.roster[1].exp, initial.heroes.roster[1].maxExp = ticks, 10000 + ticks
        initial.heroes.roster[2].exp, initial.heroes.roster[2].maxExp = ticks * 2, 20000 + ticks
        F.same(h.data.heroes, initial.heroes)
        isolated(h)
    end)

    local heroChanges = {
        level = function(h) h.data.heroes.roster[1].level = 101 end,
        extraTalent = function(h) h.data.heroes.roster[1].extraTalent = { stacks = 12 } end,
        awakening = function(h) h.data.heroes.roster[1].awakening = { [1] = true } end,
        advBranch = function(h) h.data.heroes.roster[1].advBranch = { first = 103 } end,
        team = function(h) h.data.heroes.teams[1].slots[2] = 0 end,
        owned = function(h) h.data.heroes.roster[4] = { level = 1 } end,
        nestedExp = function(h) h.data.heroes.roster[1].extraTalent = { exp = 1 } end,
        topLevelExp = function(h) h.data.heroes.exp = 1 end,
        notifiedExp = function(h)
            h.data.heroes.roster[1].exp = 1
            h.Dispatcher.set("heroes", h.data.heroes, { normalized = true })
        end,
        notifiedABA = function(h)
            h.Dispatcher.set("heroes", h.data.heroes, { normalized = true })
            h.Dispatcher.set("heroes", h.data.heroes, { normalized = true })
        end,
        reference = function(h)
            h.data.heroes = F.copy(h.data.heroes)
            h.Dispatcher.set("heroes", h.data.heroes, { normalized = true })
        end,
    }
    for name, mutate in pairs(heroChanges) do
        group("latest legal positive loadout survives heroes update / " .. name, function()
            local h = newHarness(F, { count = 24 }, true)
            start(h); pump(h, true)
            mutate(h)
            local after = F.copy(h.data.heroes)
            pump(h)
            local result = assertAck(h, true)
            check(result.changes > 0, "latest legal positive loadout commits instead of starving")
            F.same(h.data.heroes, after)
            check(#h.dirties == 1 and #h.notifications == 1, "latest verification publishes target slots once")
            isolated(h)
        end)
    end

    for _, mode in ipairs({ "level gate", "dual mode", "removed owner", "zero gain", "negative gain" }) do
        group("latest heroes rejects invalid or nonpositive selected loadout / " .. mode, function()
            local spec = mode == "dual mode" and { count = 30, heroId = 8, dual = "same", varied = true,
                templates = { "W1", "W61", "W13", "O1", "A1", "H1", "S1", "C1" } }
                or { count = 12, varied = true }
            local h = newHarness(F, spec, true)
            start(h); pump(h, true)
            if mode == "level gate" then h.data.heroes.roster[h.heroId].level = 1
            elseif mode == "dual mode" then h.data.heroes.roster[h.heroId].advBranch = nil
            elseif mode == "removed owner" then h.data.heroes.roster[h.heroId] = nil
            else
                -- 受控估值叶子使最终组合变成0/负收益；仍执行真实build/applyEquip/Bridge。
                local EP = h.require("systems.EquipmentPower")
                local evaluate = EP.evaluateLoadout
                EP.evaluateLoadout = function(ctx, changes)
                    local result = evaluate(ctx, changes)
                    if changes.armor ~= nil and changes.helmet ~= nil and changes.shoes ~= nil then
                        check(coroutine.isyieldable(), "verification runs inside owned worker")
                        result.gain = mode == "zero gain" and 0 or -1
                    end
                    return result
                end
                h.data.heroes.roster[h.heroId].extraTalent = { stacks = 10 }
            end
            local before = F.copy(h.data)
            pump(h)
            check(assertAck(h, false).reason == "quick_equip_stale", "unsafe answer explicitly rejected")
            F.same(h.data, before)
            check(#h.dirties == 0 and #h.notifications == 0, "unsafe answer never writes/notifies")
            isolated(h)
        end)
    end

    group("500 same-type single-hand boundary stays cancellable, not full completion benchmark", function()
        local h = newHarness(F, { count = 500, heroId = 8, dual = "same", templates = { "W1" } }, true)
        local before = start(h)
        pump(h, true) -- 有界推进到真实候选；大快照不保证12帧内完成复制。
        for _ = 1, 12 do
            h.Bridge.updateQuickEquip()
            check(h.Bridge.isQuickEquipPending(), "500x500 search remains cooperative before exhaustive finish")
            check(#h.notifications == 0 and #h.dirties == 0 and #h.results == 0, "partial boundary search never publishes")
        end
        check(h.evaluations > 0, "boundary test actually entered real candidate search")
        F.same(h.data, before)
        h.Bridge.cancelQuickEquip()
        check(not h.Bridge.isQuickEquipPending(), "worst-pool cancel releases task")
        for _ = 1, 3 do h.Bridge.updateQuickEquip() end
        F.same(h.data, before)
        check(#h.notifications == 0 and #h.results == 0, "cancelled boundary produces no ack or mutation")
        h.evaluations, h.handlerCalls = 0, {}
        start(h, 2); pump(h)
        assertAck(h, true, 2)
        isolated(h)
    end)

    for _, mode in ipairs({ "gain", "zero", "stale", "invalid", "notification throw" }) do
        group("real CMH feedback and no unrelated page callbacks / " .. mode, function()
            local h = newHarness(F, mode == "zero" and { count = 0 } or largeSpec(), true)
            attachRealMessageHandler(h)
            if mode == "notification throw" then
                h.Dispatcher.setOnAnyUpdate(function(modules)
                    if modules.equipment then error("expected CMH post-commit notification throw") end
                end)
            end
            start(h, mode == "invalid" and 99999 or nil)
            if mode == "stale" then h.Dispatcher.set("talents", h.data.talents, { normalized = true }) end
            pump(h)
            local success = mode ~= "stale" and mode ~= "invalid"
            local result = assertAck(h, success, mode == "invalid" and 99999 or nil)
            local key = ({ gain = "equip_done", zero = "equip_no_gain", stale = "equip_stale",
                invalid = "equip_failed", ["notification throw"] = "equip_notify_fail" })[mode]
            feedbackIs(h, key, mode == "gain" or mode == "notification throw", success and 1 or 0)
            if mode == "notification throw" then check(result.notificationFailed == true, "committed notification failure remains explicit") end
            isolated(h)
        end)
    end

    group("cache off/on strict candidates: real last_rite, artifacts, Melissa and changed teammate fallback", function()
        for _, targetId in ipairs({ 9, 20 }) do
            local spec = { count = 24, heroId = targetId, varied = true }
            spec.edit = function(data)
                data.heroes.roster[20] = { level = 100, awakening = { [7] = true } }
                data.heroes.roster[9] = { level = 100 }
                data.heroes.deployed = { targetId, targetId == 9 and 20 or 9, 1, 2 }
                data.heroes.teams[1].slots = F.copy(data.heroes.deployed)
            end
            local h = newHarness(F, spec, false)
            local Eq, EC = h.require("systems.EquipmentSystem"), h.require("config.EquipmentConfig")
            local ESC, EP = h.require("config.EquipmentSetConfig"), h.require("systems.EquipmentPower")
            local nextSeq = 100
            h.data.equipment.equipped[9] = {}
            local templateIds = {}; for id in pairs(EC.ITEMS) do templateIds[#templateIds + 1] = id end
            table.sort(templateIds)
            for _, slot in ipairs(EC.SLOTS) do
                local wearable, selected = Eq.getWearableTypeSet(9, slot), false
                for _, id in ipairs(templateIds) do
                    local tpl = EC.ITEMS[id]
                    if ESC.getSetIdForTemplate(tpl) == "last_rite" and tpl.slot == slot
                        and (not wearable or wearable[tpl.type]) and (slot ~= "weapon" or tpl.grip == "onehand") then
                        local item = F.item(h, id, 81, 1); item.seq = nextSeq
                        h.data.equipment.inventory[tostring(nextSeq)] = item
                        h.data.equipment.equipped[9][slot] = nextSeq
                        nextSeq = nextSeq + 1; selected = true; break
                    end
                end
                check(selected, "real last_rite template for " .. slot)
            end
            local alternate = F.item(h, "C1", 1, 1); alternate.seq = 200
            h.data.equipment.inventory["200"] = alternate
            h.data.artifacts = { bag = { { id = "adj", artifactId = 8, value = 12 } },
                equippedByTeam = { { { "adj" } }, {}, {} } }
            local before = F.copy(h.data)
            local options = { heroes = h.data.heroes, equipment = h.data.equipment,
                artifacts = h.data.artifacts, talents = h.data.talents }
            local plain = EP.buildContext(targetId, options)
            options.cacheFixedTeammates = true
            local cached = EP.buildContext(targetId, options)
            check(plain.currentPower == cached.currentPower, "cache exact current power with real aura/artifact/resonance")
            check(cached.fixedTeammates ~= nil and next(cached.fixedTeammates) ~= nil, "cache actually enabled")
            check(cached.hero.attrs.modifiers.set6_last_rite ~= nil, "real last_rite six aura present")
            local candidates = { { accessory = 200 }, { accessory = false }, { weapon = false, offhand = false } }
            for _, id in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8 }) do candidates[#candidates + 1] = { accessory = id } end
            local function compare(changes)
                local a, b = EP.evaluateLoadout(plain, changes), EP.evaluateLoadout(cached, changes)
                check(a.valid == b.valid and a.gain == b.gain and a.previewPower == b.previewPower,
                    "strict cached candidate valid/gain/previewPower without epsilon")
                F.same(a.equipment, b.equipment)
            end
            for _ = 1, 2 do for _, changes in ipairs(candidates) do compare(changes) end end
            if targetId == 20 then
                local borrowed = h.data.equipment.equipped[9].accessory
                compare({ accessory = borrowed }) -- 原生产规则拒绝他人占用；两路同拒绝。
                -- 显式预览adapter先在副本卸下队友该件，再走真实applyEquip模拟所有权变化；
                -- 用于触发缓存“队友六槽变化”回退，不宣称正式quick-equip可抢装备。
                local apply = Eq.applyEquip
                Eq.applyEquip = function(equipment, seq, heroId, slot, heroes, silent)
                    if seq == borrowed then Eq.applyUnequip(equipment, 9, "accessory") end
                    return apply(equipment, seq, heroId, slot, heroes, silent)
                end
                local ok, err = pcall(function() compare({ accessory = borrowed }) end)
                Eq.applyEquip = apply
                assert(ok, err)
            end
            F.same(h.data, before)
            isolated(h)
        end
    end)

    group("real Standalone cancellation/update prefixes execute before early returns", function()
        local source = nativeCache:GetFile("boot/Standalone.lua")
        local lines = {}
        while not source:IsEof() do lines[#lines + 1] = source:ReadLine() end
        source:Dispose()
        local text = table.concat(lines, "\n")
        local stopAt = assert(text:find("function Standalone.Stop()", 1, true))
        local stopEnd = assert(text:find('    require("ui.loot.InventoryCurationDialog").reset()', stopAt, true))
        local resetAt = assert(text:find("function Standalone.requestResetToStartScreen()", 1, true))
        local resetEnd = assert(text:find('    require("ui.loot.InventoryCurationDialog").reset()', resetAt, true))
        for _, slice in ipairs({ text:sub(stopAt, stopEnd - 1), text:sub(resetAt, resetEnd - 1) }) do
            local h = newHarness(F, largeSpec(), true)
            local before = start(h)
            local env = { Standalone = {}, LocalActionBridge = h.Bridge,
                SweepDialog = { close = noop }, require = function(name)
                    check(name == "core.PerformanceMonitor" or name == "ui.dev.PerformancePanel"
                        or name == "ui.battle.combat.BattleClock", "only lifecycle leaf seams")
                    return { stop = noop, close = noop, setPaused = noop }
                end }
            assert(load(slice .. "\nend", "@real-standalone-cancel-prefix", "t", env))()
            local fn = env.Standalone.Stop or env.Standalone.requestResetToStartScreen
            fn() -- 执行真实源前缀，不以字符串包含断言代替取消运行。
            check(not h.Bridge.isQuickEquipPending(), "host lifecycle prefix actually cancels")
            h.Bridge.updateQuickEquip()
            F.same(h.data, before)
            check(#h.results == 0 and #h.notifications == 0, "host cancel suppresses old completion")
            isolated(h)
        end
        local updateAt = assert(text:find("function HandleUpdate(eventType, eventData)", 1, true))
        local updateEnd = assert(text:find("    if entryQueue_ then", updateAt, true))
        local h = newHarness(F, largeSpec(), true)
        start(h)
        local order, after = {}, false
        local env = { bootReady_ = false, SyncPowerPresentationHorizon = noop,
            SidePanelBattlePause = { refresh = function() order[#order + 1] = "pause" end },
            PlayerStore = { Update = function() order[#order + 1] = "store" end },
            LocalActionBridge = { isSweepPending = function() return false end, updateQuickEquip = function()
                order[#order + 1] = "pump"; h.Bridge.updateQuickEquip()
            end },
            SpinePowerUpEffect = { update = noop },
            require = function(name)
                check(name == "ui.fx.SpineCardEffect" or name == "ui.fx.SpineResultEffect"
                    or name == "ui.dev.CEPanel" or name == "ui.dev.PerformancePanel", "only declared host prefix seams")
                return { update = noop, pollHotkey = noop, isOpen = function() return false end }
            end,
            pumpBootQueue_ = noop, StartScreen = { isOpen = function() return false end },
            DarkTitleScreen = { isOpen = function() return false end },
            unreachable = function() after = true end,
        }
        assert(load(text:sub(updateAt, updateEnd - 1) .. "\n unreachable()\nend", "@real-standalone-update-prefix", "t", env))()
        env.HandleUpdate("test", { TimeStep = { GetFloat = function() return 1 / 60 end } })
        check(order[1] == "pause" and order[2] == "store" and order[3] == "pump", "real host calls actual worker before boot-not-ready return")
        check(#h.handlerCalls == 1 and h.Bridge.isQuickEquipPending() and not after, "real async worker progressed even though host early returned")
        h.Bridge.cancelQuickEquip()
        isolated(h)
    end)

    for _, mode in ipairs({ "notified exp", "target growth", "other team growth", "heroes replacement", "drop" }) do
        group("real host frame pump empty slots with continuous background / " .. mode, function()
            local h = newHarness(F, { count = 12, heroId = 12,
                templates = { "W25", "W31", "O13", "O19", "A49", "H49", "S49", "C7" },
                edit = function(data)
                    data.heroes.roster[12].awakening = { [1] = true }
                    data.heroes.roster[12].extraTalent = { stacks = 0 }
                    data.heroes.roster[15] = { level = 100, extraTalent = { stacks = 0 } }
                    data.heroes.teams[2].slots = { 15, 0, 0, 0 }
                end }, true)
            local file = assert(nativeCache:GetFile("boot/Standalone.lua"))
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            file:Dispose()
            local source = table.concat(lines, "\n")
            local a = assert(source:find("function HandleUpdate(eventType, eventData)", 1, true))
            local b = assert(source:find("    if entryQueue_ then", a, true))
            local frames, background, pumpCalls = 0, 0, 0
            local expectedHeroes = F.copy(h.data.heroes)
            local env = { bootReady_ = true, SyncPowerPresentationHorizon = noop,
                SidePanelBattlePause = { refresh = noop }, PlayerStore = h.Store,
                LocalActionBridge = { isSweepPending = function() return false end,
                    updateQuickEquip = function()
                        pumpCalls = pumpCalls + 1
                        check(pumpCalls == frames, "real host resumes worker once per frame")
                        h.Bridge.updateQuickEquip()
                    end }, SpinePowerUpEffect = { update = noop }, pumpBootQueue_ = noop,
                require = function(name)
                    check(name == "ui.fx.SpineCardEffect" or name == "ui.fx.SpineResultEffect"
                        or name == "ui.dev.PerformancePanel" or name == "ui.dev.CEPanel", "host leaf only")
                    return { update = noop, pollHotkey = noop, isOpen = function() return false end }
                end,
                -- 真宿主prefix之后的战斗奖励输入边界；不运行Boot或玩家档。
                background = function()
                    background = background + 1
                    local hero = h.data.heroes.roster[12]
                    hero.exp, hero.maxExp = background, 10000 + background
                    if mode == "target growth" then hero.extraTalent.stacks = background
                    elseif mode == "other team growth" then h.data.heroes.roster[15].extraTalent.stacks = background
                    elseif mode == "heroes replacement" then h.data.heroes = F.copy(h.data.heroes)
                    elseif mode == "drop" and background == 1 then
                        local item = F.item(h, "C1", 1, 1); item.seq = 99
                        h.data.equipment.inventory["99"] = item
                        h.Dispatcher.notifySubscribers("equipment")
                    end
                    h.Dispatcher.set("heroes", h.data.heroes, { normalized = true })
                    h.data.battle.counter = background
                    h.Dispatcher.publishLive("battle", h.data.battle)
                    h.data.currency.gold = h.data.currency.gold + 1
                    h.Dispatcher.set("currency", h.data.currency, { normalized = true })
                    expectedHeroes = F.copy(h.data.heroes)
                end }
            assert(load(source:sub(a, b - 1) .. "\nbackground()\nend", "@real-quick-equip-host-frames", "t", env))()
            check(next(h.data.equipment.equipped) == nil, "all target slots initially empty")
            start(h)
            repeat
                frames = frames + 1
                check(frames < 5000, "live task is bounded, not perpetual restart")
                env.HandleUpdate("Update", { TimeStep = { GetFloat = function() return 1 / 60 end } })
            until not h.Bridge.isQuickEquipPending()
            check(background == frames and frames > 1, "background keeps advancing while actual task yields")
            local result = assertAck(h, mode ~= "drop")
            F.same(h.data.heroes, expectedHeroes)
            if mode == "drop" then
                check(result.reason == "quick_equip_stale" and #h.dirties == 0,
                    "real added equipment rejects old candidate universe")
            else
                check(result.changes > 0 and #h.dirties == 1 and #h.notifications == 1,
                    "empty slots actually filled once despite live heroes revisions/growth")
                check(h.flushCalls == 0, "QuickEquip does not invent synchronous persistence")
            end
            check(#h.handlerCalls == 1, "continuous updates never restart or duplicate handler")
            print(TAG .. " LIVE mode=" .. mode .. " frames=" .. frames .. " changes=" .. tostring(result.changes))
            isolated(h)
        end)
    end

    group("real Bridge GM_RESET cancels before explicit non-destructive handler", function()
        local spec = largeSpec(); spec.testReset = true
        local h = newHarness(F, spec, true)
        local before = start(h)
        check(h.Bridge.dispatch(h.AT.GM_RESET_SAVE, {}), "explicit reset seam handled")
        check(h.resetCalled and not h.Bridge.isQuickEquipPending(), "reset handler observed prior cancellation")
        F.same(h.data, before)
        check(#h.results == 1 and h.results[1].action == h.AT.GM_RESET_SAVE, "no old quick-equip ack misattributed to reset")
        for _ = 1, 3 do h.Bridge.updateQuickEquip() end
        check(#h.results == 1 and #h.dirties == 0, "reset prevents old worker commit")
        isolated(h)
    end)

    group("frozen source provenance and global isolation", function()
        if externalOracle then
            local oldService = ORACLE_PREFIX .. "rules/equipment/EquipmentService.lua"
            check((sourceReads.oracle[oldService] or 0) > 0, "oracle actually loaded frozen old Service")
            check((sourceReads.oracle[ORACLE_PREFIX .. "systems/EquipmentPower.lua"] or 0) > 0,
                "old oracle also loaded frozen old power implementation")
            for path in pairs(sourceReads.oracle) do
                check(path:sub(1, #ORACLE_PREFIX) == ORACLE_PREFIX, "all old dependencies remain frozen-prefixed")
            end
        else
            check(next(sourceReads.oracle) == nil, "standard run never attempts external oracle resource reads")
        end
        for _, h in ipairs(harnesses) do isolated(h) end
    end)
end

function Start()
    local ok, err = xpcall(run, debug.traceback)
    if not ok then failures[#failures + 1] = tostring(err); print(TAG .. " FAIL harness " .. tostring(err)) end
    if #failures == 0 then
        print(string.format("%s ALL PASS groups=%d assertions=%d FileFS=0 RNG=0", TAG, groups, checks))
    else
        print(string.format("%s FAILED groups=%d failures=%d assertions=%d", TAG, groups, #failures, checks))
    end
    engine:Exit()
end
