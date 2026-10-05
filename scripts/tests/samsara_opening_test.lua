-- N01 名册最末页：官方 UrhoXRuntime 隔离契约测试。
-- 主会话统一执行：UrhoXRuntime tests/samsara_opening_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- 仅 cache:GetFile/ReadLine 原样 load 私有 env；真实 Player/Config/Schema/Playback/Dialogue/Standalone。
-- 不改 package.loaded，不访问 debug/upvalue；File/经济/GPU/无关页面均隔离为内存边界。
-- 作者不运行 Runtime/build；测试夹具不是生产实现，流程由真实模块决定。
local PREFIX = "[samsara_opening] "
local KEY, FIRST, REPLAY = "samsara.opening_roster", "samsara_first_read", "samsara_replay"
local CHAIN = { "letter", "opening", "join.1", "join.2", "join.3" }
local assertions, failures, cases, passed = 0, 0, 0, 0

local function check(value, label)
    assertions = assertions + 1
    if not value then
        failures = failures + 1
        print(PREFIX .. "FAIL " .. label)
        log:Write(LOG_ERROR, PREFIX .. "FAIL " .. label)
    end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function runCase(label, fn)
    cases = cases + 1
    local before = failures
    local ok, err = pcall(fn)
    if not ok then check(false, label .. " exception: " .. tostring(err)) end
    if failures == before then
        passed = passed + 1
        print(PREFIX .. "PASS " .. label)
    end
end
---@param value any
---@return any
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function outsideStory(session)
    local out = {}
    for key, value in pairs(session) do if key ~= "samsaraStory" then out[key] = copy(value) end end
    return out
end

---@param path string
---@param overrides table
---@param globals table?
---@param fallback (fun(name: string): any)|nil
---@return any module
---@return table env
local function isolated(path, overrides, globals, fallback)
    local file = cache:GetFile(path)
    assert(file and file:IsOpen(), "missing real source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local env = {}
    for key, value in pairs(globals or {}) do env[key] = value end
    env.require = function(name)
        if overrides[name] ~= nil then return overrides[name] end
        if name:match("^config%.StageConfig_") then
            return isolated(name:gsub("%.", "/") .. ".lua", {})
        end
        if name == "config.StoryBackgroundConfig" then
            return isolated("config/StoryBackgroundConfig.lua", {
                ["config.StageConfig"] = isolated("config/StageConfig.lua", {}),
            })
        end
        if fallback then return fallback(name) end
        error("undeclared dependency/economic path in " .. path .. ": " .. tostring(name))
    end
    env._G = env
    setmetatable(env, { __index = _G })
    return assert(load(table.concat(lines, "\n"), "@" .. path, "t", env))(), env
end

local function oldSession()
    return {
        lastOnlineTime = 0, firstLoginTime = 100, introCompleted = true,
        hasReincarnated = false, firstGachaTenDone = false, initialHeroId = 1,
        claimedScenarios = { ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true,
            ["11"] = true, ["12"] = true, ["13"] = true, ["17"] = true },
        scenarioRewardsGranted = { ["1"] = true, ["11"] = true, ["17"] = true },
        offlineBonusCount = 2, offlineBonusDate = "2026-10-04",
        tutorialProgress = { completed = { ["1"] = true }, group = 8, step = 3, unknown = "keep" },
        introPlayback = { done = true, source = "legacy" }, unknownSession = { 7, false, "原值" },
    }
end
local function capturedSession(node)
    local session = oldSession()
    session.samsaraStory = {
        schemaVersion = 1, historyCaptured = true, cargoHistoryCaptured = true,
        mirrorHistoryCaptured = true, mirrorHistoryVersion = 1,
        -- 此夹具只测N01；预先捕获龙域阴性，init不得因无关迁移改变全表/Flush计数。
        dragonHistoryCaptured = true, dragonHistoryVersion = 1, nodes = {}, evidence = {},
        unknownStory = { keep = "unchanged" },
    }
    if node then session.samsaraStory.nodes[KEY] = copy(node) end
    return session
end
local function trustedSession(resolution)
    return capturedSession({ eligible = true, contentVersion = 1,
        eligibilitySource = "live_opening_chain", resolution = resolution, unknownNode = { keep = 9 } })
end
local function resultFor(lease, reason)
    return { playToken = lease.playToken, contextEpoch = lease.contextEpoch, nodeKey = lease.nodeKey, reason = reason }
end
local function gates(f)
    return { ready = true, legacyPending = false, blocked = f.Panel ~= nil and f.Panel.isOpen(), pointerBusy = false }
end

-- 同现有 integration fixture：真正的 onLoad/Dispatcher/Save，只替换无关 schema 注册、
-- JSON编码失败与 File 内存端；不复制 Schema/Player/Playback 的业务逻辑。
---@return any
local function fixture(suppliedSession, config, legacy)
    local f = { calls = {}, disk = "", temp = "", fail = "", flushMode = "real", shown = {}, font = 38 }
    function f.count(name) f.calls[name] = (f.calls[name] or 0) + 1 end
    function f.n(name) return f.calls[name] or 0 end
    f.Config = config or isolated("config/SamsaraSliceConfig.lua", {})
    f.Schema = isolated("shared/session/SamsaraStorySchema.lua", {})
    f.Legacy = legacy or isolated("config/ScenarioDialogueConfig.lua", {})
    f.SessionSchema = isolated("shared/session/SessionSchema.lua", { ["shared.session.SamsaraStorySchema"] = f.Schema })
    f.Registry = isolated("shared/ModuleRegistry.lua", {
        ["shared.session.SamsaraStorySchema"] = f.Schema,
        -- heroes.onLoad会为旧角色补dupeCount；原样执行纯配置迁移，不能让pcall吞掉缺依赖。
        ["config.AwakeningConfig"] = isolated("config/AwakeningConfig.lua", {}),
    }, nil, function(name)
        assert(name:match("^shared%..+Schema$") or name == "shared.heroes.TeamSlots", "unexpected Registry dependency " .. name)
        return { Fields = {}, normalize = function() end }
    end)
    f.Character = isolated("shared/schemas/CharacterSchema.lua", {
        ["shared.session.SessionSchema"] = f.SessionSchema,
    }, nil, function(name)
        assert(name:match("^shared%..+Schema$"), "unexpected CharacterSchema dependency " .. name)
        return { Fields = {} }
    end)
    f.Dispatcher = isolated("runtime/ClientDispatcher.lua", {
        ["shared.Protocol"] = {}, ["shared.ModuleRegistry"] = f.Registry,
        ["shared.schemas.CharacterSchema"] = f.Character,
    })
    f.Dispatcher.set("session", suppliedSession or oldSession())
    f.Dispatcher.set("battle", { maxStageId = 9999, currentStageId = 101, clearedStages = {} })
    f.Dispatcher.set("currency", { gold = 123, gems = 456, unknown = "keep" })
    f.Dispatcher.set("opaqueModule", { value = { false, 9, "keep" } })
    f.gameState = { gold = 123, exp = 11, unknown = { keep = 42 } }
    local saveGlobals = {
        cjson = {
            encode = function(value)
                f.count("encode")
                if f.fail == "encode" then error("injected encode failure") end
                return cjson.encode(value)
            end,
            decode = function(value) return cjson.decode(value) end,
        },
        fileSystem = {
            FileExists = function(_, path)
                eq(path, "standalone_save.json", "FileExists only queries committed memory file")
                return f.disk ~= ""
            end,
            Rename = function(_, from, to)
                f.count("rename")
                eq(from, "standalone_save.pending.json", "atomic source is temporary file")
                eq(to, "standalone_save.json", "atomic target is committed file")
                if f.fail == "rename" or not f.written or not f.closed then return false end
                f.disk, f.temp, f.written, f.closed = f.temp, "", false, false
                return true
            end,
            Delete = function(_, path)
                eq(path, "standalone_save.pending.json", "failed Save never deletes committed memory file")
                f.temp, f.written, f.closed = "", false, false
                return true
            end,
        },
        File = function(path, mode)
            eq(path, mode == FILE_WRITE and "standalone_save.pending.json" or "standalone_save.json", "File boundary stays in memory")
            f.count(mode == FILE_WRITE and "openWrite" or "openRead")
            local opened = not (mode == FILE_WRITE and f.fail == "open")
            if mode == FILE_WRITE and opened then f.temp, f.written, f.closed = "", false, false end
            return {
                IsOpen = function() return opened end,
                WriteString = function(_, data)
                    f.count("write")
                    if not opened or f.fail == "write" then return false end
                    f.temp, f.written = data, true
                    return true
                end,
                ReadString = function() return f.disk end,
                Close = function() if mode == FILE_WRITE and opened then f.closed = true end end,
            }
        end,
    }
    f.Save = isolated("boot/StandaloneSave.lua", {
        ["runtime.ClientDispatcher"] = f.Dispatcher,
        ["core.GameState"] = {
            exportSave = function() return f.gameState end,
            importSave = function(value) f.gameState = value end,
            syncPlayerData = function() f.count("restore.sync") end,
        },
        ["ui.battle.scene.BattleScene"] = { setBattleData = function() f.count("restore.battle") end },
        ["rules.offline.OfflineService"] = {
            HasPendingRewards = function() return false end,
            MarkOnline = function() f.count("save.markOnline") end,
        },
    }, saveGlobals)
    local dependencies = { ["config.SamsaraSliceConfig"] = f.Config,
        ["shared.session.SamsaraStorySchema"] = f.Schema, ["config.ScenarioDialogueConfig"] = f.Legacy }
    -- 新模块若误引入经济/教程/旧队列会被这些全方法 spy 捕获。
    f.forbidden = {}
    for _, name in ipairs({ "runtime.GameAction", "runtime.ClientMessageHandler", "rules.character.PlayerDataManager",
        "systems.TutorialManager", "systems.StoryPlayer" }) do
        local spy = setmetatable({}, { __index = function(_, method)
            return function() f.count("forbidden." .. name .. "." .. tostring(method)); return false end
        end })
        dependencies[name], f.forbidden[name] = spy, spy
    end
    f.Player = isolated("systems/SamsaraSlicePlayer.lua", dependencies)
    f.Dispatcher.subscribe("session", f.Player.onSessionUpdated)
    f.options = {
        getSession = function() return f.Dispatcher.get("session") end,
        setSession = function(value)
            f.count("session.set")
            eq(value, f.Dispatcher.get("session"), "Player publishes shared session table")
            if f.fail == "set" then error("injected set failure") end
            f.Dispatcher.set("session", value)
        end,
        flush = function()
            f.count("flush")
            if f.flushMode == "false" then return false end
            if f.flushMode == "nil" then return nil end
            if f.flushMode == "throw" then error("injected Flush exception") end
            return f.Save.Flush()
        end,
    }
    function f.session() return assert(f.Dispatcher.get("session")) end
    function f.init(raw) return f.Player.init(f.options, raw or f.Dispatcher.get("battle")) end
    function f.node() return f.session().samsaraStory.nodes[KEY] end
    function f.publish(session) f.Dispatcher.handleStateUpdate(cjson.encode({ modules = { session = session } })) end
    -- 真 UTF-8/显示折行模块，只有语言/GPU边界替身；不实际创建NanoVG或音源。
    f.graphics = {
        cache = { GetResource = function() return nil end }, -- 不创建音源/资源副作用
        nvgCreateImage = function() f.count("gpu.image"); return -1 end,
        nvgFontSize = function(_, size) f.font = size end,
        nvgRGBA = function() return {} end,
        nvgText = function(_, _, _, text) f.count("gpu.text"); return text end,
    }
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgIntersectScissor", "nvgScale", "nvgFontFace",
        "nvgTextAlign", "nvgTextLineHeight", "nvgFillColor", "nvgScissor", "nvgTranslate", "nvgBeginPath",
        "nvgRect", "nvgFill", "nvgRoundedRect", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgResetScissor" }) do
        f.graphics[name] = function() end
    end
    f.I18n = {
        get = function() return "zh_CN" end, lookup = function(text) return text end,
        installDrawHook = function() end,
        displayBounds = function(_, _, _, text) return (utf8.len(text) or 0) * f.font end,
        displayText = function(_, _, _, text) return text end,
    }
    f.Story = isolated("core/I18nStory.lua", {})
    f.Display = isolated("ui/story/StoryDisplay.lua", { ["core.I18n"] = f.I18n, ["core.I18nStory"] = f.Story }, f.graphics)
    f.Bus = isolated("core/EventBus.lua", {})
    f.GameConfig = isolated("config/GameConfig.lua", {})
    f.Dialogue = isolated("ui/story/ScenarioDialogue.lua", {
        ["core.DrawUtil"] = {}, ["config.GameConfig"] = f.GameConfig,
        ["ui.widget.HeroFrame"] = {}, ["core.EventBus"] = f.Bus, ["core.I18n"] = f.I18n,
        ["core.I18nStory"] = f.Story, ["ui.story.StoryDisplay"] = f.Display,
        ["config.ScenarioDialogueConfig"] = f.Legacy, ["config.HeroAssetUtil"] = {},
    }, f.graphics)
    local realShow = f.Dialogue.show
    f.realShow = realShow
    f.Dialogue.show = function(cfg)
        f.shown[#f.shown + 1] = cfg
        if f.showFault == "throw" then error("injected presentation failure") end
        if f.showFault == "false" then return realShow({ steps = {} }) end
        return realShow(cfg)
    end
    local playbackDependencies = { ["systems.SamsaraSlicePlayer"] = f.Player,
        ["config.SamsaraSliceConfig"] = f.Config, ["ui.story.ScenarioDialogue"] = f.Dialogue }
    for name, spy in pairs(f.forbidden) do playbackDependencies[name] = spy end
    f.Playback = isolated("systems/SamsaraSlicePlayback.lua", playbackDependencies)
    return f
end

local function noRewards(f, old, label)
    local leaks = {}
    for name, count in pairs(f.calls) do
        if count > 0 and name:match("^forbidden%.") then leaks[#leaks + 1] = name .. "=" .. count end
    end
    eq(#leaks, 0, label .. " no economic/tutorial/legacy call " .. table.concat(leaks, ","))
    check(same(outsideStory(f.session()), old), label .. " pre-existing session fields unchanged")
    eq(f.Dispatcher.get("currency").gold, 123, label .. " currency unchanged")
    eq(f.gameState.gold, 123, label .. " GameState unchanged")
end
local function noEvidence(f, before, label)
    eq(f.Player.getRecord(KEY).evidenceVisible, false, label .. " no evidence visible")
    eq(f.Player.getRecord(KEY).evidence, nil, label .. " no E-number awarded")
    eq(#f.Player.getRecord(KEY).evidences, 0, label .. " evidence list empty")
    check(same(f.session().samsaraStory.evidence, before), label .. " evidence state unchanged")
    eq(assert(f.Config.getEvidence("E03-B")).id, "E03-B", label .. " supported B static definition is legal")
    eq(f.session().samsaraStory.evidence["E03-B"], nil, label .. " N01 never unlocks B")
end
local function reference(f, label)
    local record = f.Player.getRecord(KEY)
    eq(record.status, "locked", label .. " status locked")
    eq(record.referenceOnly, true, label .. " static referenceOnly")
    check(same(record.referenceSteps, f.Config.get(KEY).steps), label .. " static reference is real config")
    eq(f.Player.requestRead(KEY), false, label .. " no read request")
    eq(f.Player.begin(FIRST, KEY), nil, label .. " no first read")
    eq(f.Player.begin(REPLAY, KEY), nil, label .. " no replay")
end
local function chain(f, reason)
    local epoch = assert(f.Player.beginOpening(), "beginOpening must return current lease epoch")
    eq(epoch, f.Player.getContextEpoch(), "opening lease captures current context epoch")
    for i, step in ipairs(CHAIN) do
        eq(f.Player.noteOpeningResult(step, reason or "finished", epoch), i == #CHAIN, "opening result " .. step .. " only final grants")
    end
    return epoch
end
local function finishDialogue(dialogue)
    local _, total = dialogue.getProgress()
    for _ = 1, total do dialogue.update(100); dialogue.advance() end
end

local function configurationCases()
    runCase("N01 exact config and eight-key prefix", function()
        local cfg = isolated("config/SamsaraSliceConfig.lua", {})
        eq(cfg.OPENING_KEY, KEY, "OPENING_KEY string namespace")
        check(same(cfg.KEYS, { "samsara.log_leaf", "samsara.cargo_match", "samsara.gray_order", "samsara.people_record",
            "samsara.returned_manifest", "samsara.dog_mirror", "samsara.bell_mirror", KEY, "samsara.dragon_mirror", "samsara.nightmare_afterimage" }), "旧九KEY严格前缀；N01第八、N08第九、N11仅追加第十")
        eq(cfg.get("N01"), nil, "planner ID is not registered")
        local node = assert(cfg.get(KEY))
        eq(node.title, "名册最末页", "N01 title")
        eq(node.mode, "small", "N01 small mode")
        eq(#node.steps, 8, "one opening narration + six originals + one closing narration")
        local expected = {
            { name = "旁白", text = "叮咚鸡整理名册。出征页已有三人的名字，背面是没有填过的回程页。" },
            { characterId = 3, name = "叮咚鸡", text = "叮咚。出征人数：三。回来人数：待填。" },
            { characterId = 2, name = "黄桃龙", text = "为什么待填？现在填三，不就好了？" },
            { characterId = 3, name = "叮咚鸡", text = "回来以后填。" },
            { characterId = 1, name = "大狗嚼", text = "叫！本狗负责把“三”带回来。一个都不少！" },
            { name = "远征长", text = "那就把这页留好。" },
            { characterId = 2, name = "黄桃龙", text = "我也留好罐头。回来庆祝用，路上……只吃一点点。" },
            { name = "旁白", text = "她把一只未开封的罐头放在名册旁。盒盖已有两道浅刻痕，第三道只刻了一半。" },
        }
        check(same(node.steps, expected), "all eight steps verbatim with exact narrator/portrait mapping")
        eq(node.evidence, nil, "N01 has no evidence")
        eq(node.rewards, nil, "N01 has no rewards")
        eq(node.reward, nil, "N01 has no singular reward")
        eq(node.scenarioId, nil, "N01 not a legacy economic scenario")
        node.steps[1].text = "presentation mutation"
        check(same(cfg.get(KEY).steps, expected), "config returned copy does not mutate source")
    end)
    runCase("uninitialized Player APIs are safe", function()
        local f = fixture()
        eq(f.Player.beginOpening(), nil, "uninitialized cannot start opening tracking")
        eq(f.Player.noteOpeningResult("letter", "finished", 0), false, "uninitialized ignores opening result")
        eq(f.Player.getRecord(KEY).status, "unsupported", "uninitialized record unsupported")
        eq(#f.Player.getRecords(), 10, "未init十条记录安全返回")
        eq(f.Player.requestRead(KEY), false, "uninitialized cannot queue")
        eq(f.Player.begin(FIRST, KEY), nil, "uninitialized cannot first-read")
        f.Player.cancel(); f.Player.update(2)
        eq(f.n("flush"), 0, "uninitialized never writes")
    end)
end

local function historicalCases()
    for _, label in ipairs({ "introCompleted", "starter trio", "claimed", "max and raw clears", "forged old source" }) do
        runCase("legacy history cannot prove opening: " .. label, function()
            local session = oldSession()
            if label == "forged old source" then
                session = capturedSession({ eligible = true, contentVersion = 1, resolution = "finished", eligibilitySource = "legacy_claimed_unknown" })
            end
            local f = fixture(session)
            f.Dispatcher.set("heroes", { roster = { [1] = { level = 1 }, [2] = { level = 1 }, [3] = { level = 1 } }, deployed = { 1, 2, 3 } })
            local raw = label == "max and raw clears" and { maxStageId = 9999, clearedStages = { [104] = true, [204] = true, [4905] = true } } or {}
            f.init(raw)
            local old, evidence, before = outsideStory(f.session()), copy(f.session().samsaraStory.evidence), copy(f.session())
            reference(f, label)
            noEvidence(f, evidence, label)
            check(same(f.session(), before), "static queries never mutate session")
            eq(f.Player.noteOpeningResult("join.3", "finished", f.Player.getContextEpoch()), false, "history cannot fill untracked final result")
            noRewards(f, old, label)
        end)
    end
    for _, node in ipairs({
        { eligible = true, contentVersion = 1, resolution = "skipped" },
        { eligible = true, contentVersion = 1, resolution = "finished", eligibilitySource = "live_clear" },
        { eligible = "true", contentVersion = 1, resolution = "finished", eligibilitySource = "live_opening_chain" },
        { eligible = false, contentVersion = 1, eligibilitySource = "live_opening_chain" },
    }) do
        runCase("opening source/eligible strictness " .. tostring(node.eligibilitySource) .. "/" .. tostring(node.eligible), function()
            local f = fixture(capturedSession(node)); f.init()
            reference(f, "untrusted node")
            eq(f.Player.hasPendingRecords(), false, "untrusted N01 not pending")
            eq(f.Player.peekReady(), nil, "untrusted N01 not auto candidate")
        end)
    end
end

local function trackingCases()
    for _, reason in ipairs({ "finished", "dismissed", "skipped" }) do
        runCase("real opening chain all steps " .. reason, function()
            local f = fixture(capturedSession()); f.init()
            local old, evidence, flushes = outsideStory(f.session()), copy(f.session().samsaraStory.evidence), f.n("flush")
            local epoch = assert(f.Player.beginOpening())
            eq(epoch, f.Player.getContextEpoch(), "lease epoch current")
            for i, step in ipairs(CHAIN) do
                eq(f.Player.noteOpeningResult(step, reason, epoch), i == #CHAIN, "only last grants: " .. step)
                if i < #CHAIN then
                    reference(f, "partial chain " .. step)
                    eq(f.n("flush"), flushes, "partial tracking is process-only")
                    eq(f.Player.noteOpeningResult(step, reason, epoch), false, "duplicate just-accepted step ignored")
                end
            end
            eq(f.node().eligible, true, "completed chain grants eligible")
            eq(f.node().eligibilitySource, "live_opening_chain", "source is live_opening_chain only")
            eq(f.node().resolution, nil, "opening chain does not mark N01 read")
            eq(f.Player.getRecord(KEY).status, "pending", "completed chain opens first-read pending")
            check(f.Player.getRecord(KEY).referenceOnly ~= true, "trusted pending not reference-only")
            eq(f.n("flush"), flushes + 1, "last step persists only once")
            eq(f.Player.noteOpeningResult("join.3", "finished", epoch), false, "last result duplicate cannot regrant")
            eq(f.Player.beginOpening(), nil, "already trusted eligible cannot re-begin chain")
            eq(f.Player.requestRead(KEY), true, "trusted pending can request")
            eq(f.Player.takeRequest().kind, FIRST, "pending request first-read")
            noEvidence(f, evidence, "completed " .. reason)
            noRewards(f, old, "completed " .. reason)
        end)
    end
    for missing = 1, #CHAIN do
        runCase("missing chain segment " .. CHAIN[missing], function()
            local f = fixture(capturedSession()); f.init()
            local before, epoch = copy(f.session()), assert(f.Player.beginOpening())
            for i, step in ipairs(CHAIN) do
                if i ~= missing then eq(f.Player.noteOpeningResult(step, "finished", epoch), false, "gap cannot grant " .. step) end
            end
            if missing < #CHAIN then
                for _, step in ipairs(CHAIN) do eq(f.Player.noteOpeningResult(step, "finished", epoch), false, "destroyed tracking cannot be backfilled") end
            end
            reference(f, "missing " .. CHAIN[missing])
            check(same(f.session(), before), "missing segment never writes new story state")
        end)
    end
    for _, order in ipairs({ { "opening", "letter", "join.1", "join.2", "join.3" },
        { "letter", "opening", "join.2", "join.1", "join.3" },
        { "letter", "opening", "join.1", "unknown-step", "join.2", "join.3" } }) do
        runCase("out-of-order chain is terminal " .. table.concat(order, "/"), function()
            local f = fixture(capturedSession()); f.init()
            local epoch, before = assert(f.Player.beginOpening()), copy(f.session())
            for _, step in ipairs(order) do eq(f.Player.noteOpeningResult(step, "finished", epoch), false, "out-of-order cannot grant") end
            for _, step in ipairs(CHAIN) do eq(f.Player.noteOpeningResult(step, "finished", epoch), false, "cannot recover destroyed lease") end
            check(same(f.session(), before), "out-of-order never persists")
            reference(f, "out-of-order")
        end)
    end
    for _, reason in ipairs({ "reset", "replaced", "failed", "unknown" }) do
        for interrupted = 1, #CHAIN do
            runCase("opening interruption " .. CHAIN[interrupted] .. "/" .. reason, function()
                local f = fixture(capturedSession()); f.init()
                local epoch, before = assert(f.Player.beginOpening()), copy(f.session())
                for i = 1, interrupted - 1 do eq(f.Player.noteOpeningResult(CHAIN[i], "finished", epoch), false, "prefix process-only") end
                eq(f.Player.noteOpeningResult(CHAIN[interrupted], reason, epoch), false, "interruption not qualification")
                for _, step in ipairs(CHAIN) do eq(f.Player.noteOpeningResult(step, "finished", epoch), false, "interrupted lease cannot restart itself") end
                check(same(f.session(), before), "interruption no persisted chain fragments")
                reference(f, "interrupted")
                chain(f, "skipped")
                eq(f.Player.getRecord(KEY).status, "pending", "explicit new opening can recover")
            end)
        end
    end
    for _, source in ipairs({ "live_opening_chain", "case_archive", "legacy_claimed_unknown" }) do
        runCase("real chain upgrades untrusted historical node " .. source, function()
            local f = fixture(capturedSession({ eligible = source ~= "live_opening_chain", contentVersion = 1,
                eligibilitySource = source, resolution = "skipped", unknown = { keep = 8 } })); f.init()
            chain(f)
            eq(f.node().eligibilitySource, "live_opening_chain", "only genuine chain upgrades source")
            eq(f.node().resolution, nil, "new live qualification cannot borrow historical read result")
            eq(f.node().unknown.keep, 8, "genuine chain preserves unknown node field")
        end)
    end
    runCase("epoch mandatory/wrong epoch/untracked callback", function()
        for _, kind in ipairs({ "missing", "wrong", "string", "no lease" }) do
            local f = fixture(capturedSession()); f.init()
            local epoch = kind == "no lease" and f.Player.getContextEpoch() or assert(f.Player.beginOpening())
            local supplied = kind == "missing" and nil or (kind == "wrong" and epoch + 100 or (kind == "string" and tostring(epoch) or epoch))
            if kind == "missing" then supplied = nil end
            for _, step in ipairs(CHAIN) do eq(f.Player.noteOpeningResult(step, "finished", supplied), false, kind .. " callback cannot grant") end
            reference(f, kind .. " epoch")
        end
    end)
    for _, invalidate in ipairs({ "cancel", "init", "new begin", "silent swap", "notified new game" }) do
        runCase("tracking identity invalidated by " .. invalidate, function()
            local f = fixture(capturedSession()); f.init()
            local oldEpoch = assert(f.Player.beginOpening())
            f.Player.noteOpeningResult("letter", "finished", oldEpoch)
            if invalidate == "cancel" then f.Player.cancel()
            elseif invalidate == "init" then f.init()
            elseif invalidate == "new begin" then
                local epoch = assert(f.Player.beginOpening())
                check(epoch ~= oldEpoch, "re-begin replaces tracking with distinct epoch")
            elseif invalidate == "silent swap" then
                f.Dispatcher.unsubscribe("session", f.Player.onSessionUpdated)
                f.Dispatcher.set("session", capturedSession())
            else
                local newGame = oldSession(); newGame.samsaraStory = f.Schema.new()
                f.publish(newGame)
            end
            local before = copy(f.session())
            for i = 2, #CHAIN do eq(f.Player.noteOpeningResult(CHAIN[i], "finished", oldEpoch), false, "stale tracking cannot finish") end
            check(same(f.session(), before), "invalidation preserves target save")
        end)
    end
    for _, fault in ipairs({ "missing", "empty", "throw", "evidence", "rewards" }) do
        runCase("missing/bad opening config cannot mint result " .. fault, function()
            local cfg = isolated("config/SamsaraSliceConfig.lua", {})
            local get = cfg.get
            cfg.get = function(key, source)
                if key ~= KEY then return get(key, source) end
                if fault == "throw" then error("injected config error") end
                if fault == "empty" then return { title = "bad", mode = "small", steps = {} } end
                if fault == "evidence" or fault == "rewards" then
                    local definition = get(key)
                    definition[fault] = fault == "evidence" and { id = "E99", title = "forged", text = "not N01" } or { { gold = 9 } }
                    return definition
                end
                return nil
            end
            local f = fixture(capturedSession(), cfg); f.init()
            local epoch = f.Player.beginOpening()
            for _, step in ipairs(CHAIN) do eq(f.Player.noteOpeningResult(step, "finished", epoch), false, "bad config cannot grant") end
            check(not f.node() or f.node().eligible ~= true, "bad config no eligible node")
            eq(f.Player.requestRead(KEY), false, "bad config cannot request")
            eq(f.Player.begin(FIRST, KEY), nil, "bad config cannot begin first-read")
        end)
    end
end

local function playbackCases()
    for _, ending in ipairs({ "dismissed", "skipped", "reset", "replaced" }) do
        runCase("N01 real Playback/Dialogue " .. ending .. " and zero-reward replay", function()
            local f = fixture(trustedSession()); f.init()
            local old, evidence = outsideStory(f.session()), copy(f.session().samsaraStory.evidence)
            eq(f.Player.peekReady(), KEY, "trusted pending auto candidate")
            eq(f.Playback.tryPlay(gates(f)), true, "real Player/Config/Playback starts N01")
            local cfg = assert(f.shown[1])
            eq(cfg.completionToken.nodeKey, KEY, "real show receives N01 lease")
            eq(cfg.completionToken.kind, FIRST, "real show first-read kind")
            eq(cfg.mode, "small", "real show small")
            check(same(cfg.steps, f.Config.get(KEY).steps), "real show gets eight genuine steps")
            eq(cfg.onFinish, nil, "N01 has no legacy reward onFinish")
            check(type(cfg.onResult) == "function", "N01 uses independent token result")
            eq(f.Playback.tryPlay(gates(f)), false, "active dialogue gates second lease")
            if ending == "dismissed" then
                finishDialogue(f.Dialogue)
                eq(f.Player.getRecord(KEY).status, "pending", "dismiss animation not completion")
                f.Dialogue.update(0.29)
                eq(f.Player.getRecord(KEY).status, "pending", "threshold before dismissal not completion")
                f.Dialogue.update(0.02)
            elseif ending == "skipped" then f.Dialogue.skip()
            elseif ending == "reset" then f.Dialogue.reset()
            else f.realShow({ mode = "small", steps = f.Config.get(KEY).steps }) end
            local processed = ending == "dismissed" or ending == "skipped"
            eq(f.Player.getRecord(KEY).status, processed and (ending == "skipped" and "skipped" or "finished") or "pending", "only actual handled result reads N01")
            eq(#f.shown, 1, "result never recursively shows next/replay")
            f.Dialogue.reset()
            if processed then
                local story, writes = copy(f.session().samsaraStory), f.n("flush")
                eq(f.Player.beginOpening(), nil, "first-read processed cannot re-open tracking")
                eq(f.Player.peekReady(), nil, "processed not automatic replay")
                for _, replayReason in ipairs({ "finished", "dismissed", "skipped", "reset", "replaced", "failed" }) do
                    eq(f.Player.requestRead(KEY), true, "processed queues replay " .. replayReason)
                    eq(f.Playback.tryPlay(gates(f)), true, "real replay boundary " .. replayReason)
                    local replayCfg = assert(f.shown[#f.shown])
                    eq(replayCfg.completionToken.kind, REPLAY, "replay kind")
                    -- 仅failed需直接模拟展示边界；其他结束通过真实Dialogue。
                    if replayReason == "skipped" then f.Dialogue.skip()
                    elseif replayReason == "reset" then f.Dialogue.reset()
                    elseif replayReason == "replaced" then f.realShow({ mode = "small", steps = replayCfg.steps }); f.Dialogue.reset()
                    elseif replayReason == "failed" then f.Player.onResult(resultFor(replayCfg.completionToken, "failed")); f.Dialogue.reset()
                    else finishDialogue(f.Dialogue); f.Dialogue.update(0.31) end
                    check(same(f.session().samsaraStory, story), "replay never rewrites first resolution/source " .. replayReason)
                    eq(f.n("flush"), writes, "replay never saves " .. replayReason)
                end
                local restored = fixture(cjson.decode(cjson.encode(f.session()))); restored.init()
                eq(restored.Player.getRecord(KEY).status, ending == "skipped" and "skipped" or "finished", "JSON restart preserves first result")
            else
                eq(f.Player.peekReady(), KEY, "interrupted N01 stays pending")
            end
            noEvidence(f, evidence, ending .. " first/replays")
            noRewards(f, old, ending .. " first/replays")
        end)
    end
    runCase("N01 exact play token/epoch/key/cancel/duplicate", function()
        local f = fixture(trustedSession()); f.init()
        local lease = assert(f.Player.begin(FIRST, KEY))
        for _, field in ipairs({ "playToken", "contextEpoch", "nodeKey" }) do
            local wrong = resultFor(lease, "finished"); wrong[field] = "wrong"
            eq(f.Player.onResult(wrong), false, "wrong " .. field .. " rejected")
        end
        eq(f.Player.onResult(resultFor(lease, "unknown")), false, "invalid reason does not consume read lease")
        local original = copy(lease); lease.playToken = -100
        eq(f.Player.onResult(resultFor(lease, "finished")), false, "returned lease is not mutable internal identity")
        eq(f.Player.onResult(resultFor(original, "finished")), true, "exact original lease finishes")
        eq(f.Player.onResult(resultFor(original, "skipped")), false, "duplicate cannot rewrite first result")
        local replay = assert(f.Player.begin(REPLAY, KEY)); f.Player.cancel()
        eq(f.Player.onResult(resultFor(replay, "finished")), false, "cancel invalidates read lease")
        local nextLease = assert(f.Player.begin(REPLAY, KEY)); f.init()
        eq(f.Player.onResult(resultFor(nextLease, "finished")), false, "init invalidates read lease")
    end)
    for _, fault in ipairs({ "false", "throw" }) do
        runCase("N01 real Playback presentation failure " .. fault, function()
            local f = fixture(trustedSession()); f.init()
            local before, writes = copy(f.session()), f.n("flush")
            f.showFault = fault
            eq(f.Playback.tryPlay(gates(f)), false, "show failure caught")
            eq(f.Player.getRecord(KEY).status, "pending", "failed show not first-read completed")
            eq(f.n("flush"), writes, "failed show not persisted")
            check(same(f.session(), before), "failed show keeps source/result/legacy fields")
            f.showFault = ""
            eq(f.Playback.tryPlay(gates(f)), true, "next arbitration can retry pending N01")
            f.Dialogue.skip()
            eq(f.Player.getRecord(KEY).status, "skipped", "only successful retry handles N01")
        end)
    end
    for _, name in ipairs({ "ready", "legacyPending", "blocked", "pointerBusy", "dialogueActive" }) do
        runCase("N01 Playback gate preserves queued request " .. name, function()
            local f = fixture(trustedSession()); f.init()
            eq(f.Player.requestRead(KEY), true, "pending request queued")
            local takes, take = 0, f.Player.takeRequest
            f.Player.takeRequest = function() takes = takes + 1; return take() end
            local g = gates(f)
            if name == "dialogueActive" then f.realShow({ mode = "small", steps = f.Config.get(KEY).steps })
            else g[name] = name ~= "ready" end
            eq(f.Playback.tryPlay(g), false, "gate blocks")
            eq(takes, 0, "gate does not consume request")
            eq(#f.shown, 0, "gate never shows")
            eq(take().key, KEY, "original request preserved")
            f.Dialogue.reset()
        end)
    end
end

local function schemaAndFutureCases()
    runCase("N01 schema normalization is local/idempotent and unknown-preserving", function()
        local f = fixture()
        local s = capturedSession({ eligible = "false", contentVersion = "1", resolution = "reset",
            eligibilitySource = 9, customNode = { keep = true } })
        s.samsaraStory.unknownNodeDomain = { original = false }
        s.samsaraStory.nodes.unknown = { contentVersion = 88, raw = "keep" }
        s.samsaraStory.evidence.unknown = { future = { keep = true } }
        local old = outsideStory(s)
        local story, supported = f.Schema.normalize(s)
        eq(supported, true, "supported schema")
        eq(story, s.samsaraStory, "normalize returns same nested reference")
        eq(story.nodes[KEY].eligible, false, "string eligible not coerced true")
        eq(story.nodes[KEY].resolution, nil, "reset not persisted processed")
        eq(story.nodes[KEY].eligibilitySource, nil, "nonstring source discarded")
        eq(story.nodes[KEY].customNode.keep, true, "unknown N01 node field intact")
        check(same(outsideStory(s), old), "schema leaves old session fields intact")
        local once = copy(s)
        for _ = 1, 4 do f.Schema.normalize(s) end
        check(same(s, once), "N01 normalize idempotent")
        for _, loader in ipairs({ f.Registry, f.Character }) do
            local independent = capturedSession({ eligible = true, contentVersion = "1", resolution = "dismissed",
                eligibilitySource = "live_opening_chain", custom = { keep = 1 } })
            loader.applyOnLoad("session", independent)
            eq(independent.samsaraStory.nodes[KEY].resolution, nil, "independent onLoad normalizes N01")
            eq(independent.samsaraStory.nodes[KEY].custom.keep, 1, "independent onLoad preserves unknown N01")
        end
    end)
    for _, version in ipairs({ 2, "3" }) do
        runCase("future whole schema completely preserved " .. tostring(version), function()
            local session = oldSession()
            session.samsaraStory = { schemaVersion = version, historyCaptured = "future", nodes = "future nodes",
                evidence = false, unknown = { format = { false, "preserve" } } }
            local before, ref = copy(session), session.samsaraStory
            local f = fixture(session)
            local returned, supported = f.Schema.normalize(session)
            eq(returned, ref, "future nested object identity")
            eq(supported, false, "future schema unsupported")
            eq(f.init({ clearedStages = { [104] = true, [204] = true, [4905] = true } }), false, "Player init disabled")
            eq(f.Player.getRecord(KEY).status, "unsupported", "future N01 unsupported not reference")
            eq(f.Player.beginOpening(), nil, "future tracking disabled")
            for _, step in ipairs(CHAIN) do eq(f.Player.noteOpeningResult(step, "finished", f.Player.getContextEpoch()), false, "future opening write refused") end
            eq(f.Player.peekReady(), nil, "future no candidate")
            eq(f.Player.requestRead(KEY), false, "future no request")
            eq(f.Player.takeRequest(), nil, "future no taken request")
            eq(f.Player.begin(FIRST, KEY), nil, "future no first read")
            eq(f.Player.begin(REPLAY, KEY), nil, "future no replay")
            eq(f.Player.onResult({ playToken = 1, contextEpoch = 1, nodeKey = KEY, reason = "finished" }), false, "future result refused")
            f.Player.cancel(); f.Player.update(100)
            check(same(session, before), "all future schema fields byte-structure preserved")
            eq(f.n("flush"), 0, "future never Flush")
        end)
    end
    for _, version in ipairs({ 2, "9" }) do
        runCase("future N01 content preserved " .. tostring(version), function()
            local session = trustedSession("new-result")
            session.samsaraStory.nodes[KEY].contentVersion = version
            session.samsaraStory.nodes[KEY].eligible = "future boolean"
            local before = copy(session)
            local f = fixture(session); f.init()
            eq(f.Player.getRecord(KEY).status, "unsupported", "future content unsupported")
            eq(f.Player.beginOpening(), nil, "future content cannot restart historical chain")
            for _, step in ipairs(CHAIN) do eq(f.Player.noteOpeningResult(step, "finished", f.Player.getContextEpoch()), false, "future content no qualification") end
            eq(f.Player.requestRead(KEY), false, "future content cannot queue")
            eq(f.Player.begin(FIRST, KEY), nil, "future content cannot first-read")
            eq(f.Player.begin(REPLAY, KEY), nil, "future content cannot replay")
            f.Player.cancel(); f.Player.update(100)
            check(same(session, before), "future content plus old/unknown story fields completely preserved")
            eq(f.n("flush"), 0, "future content no write")
        end)
    end
    for _, domain in ipairs({ "schema", "content", "source" }) do
        runCase("active N01 read refuses runtime upgrade/source change " .. domain, function()
            local f = fixture(trustedSession()); f.init()
            local lease = assert(f.Player.begin(FIRST, KEY))
            if domain == "schema" then f.session().samsaraStory.schemaVersion = 2
            elseif domain == "content" then f.node().contentVersion = 2
            else f.node().eligibilitySource = "legacy_claimed_unknown" end
            local before, writes = copy(f.session()), f.n("flush")
            eq(f.Player.onResult(resultFor(lease, "finished")), false, "active result refuses changed domain")
            eq(f.Player.requestRead(KEY), false, "changed domain no request")
            check(same(f.session(), before), "no result writes after changed domain")
            eq(f.n("flush"), writes, "no Flush after changed domain")
        end)
    end
end

local function publicationCases()
    runCase("legitimate JSON publication retains process opening lease then read lease", function()
        local f = fixture(capturedSession()); f.init()
        local epoch = assert(f.Player.beginOpening())
        eq(f.Player.noteOpeningResult("letter", "finished", epoch), false, "letter only process state")
        local oldRef = f.session()
        local replacement = copy(oldRef); replacement.claimedScenarios["1"] = true
        f.publish(replacement)
        check(f.session() ~= oldRef, "real Dispatcher JSON publication changes table")
        for i = 2, #CHAIN do eq(f.Player.noteOpeningResult(CHAIN[i], "skipped", epoch), i == #CHAIN, "same-game JSON keeps opening epoch") end
        eq(f.Player.getRecord(KEY).status, "pending", "publication chain reaches new table")
        local lease = assert(f.Player.begin(FIRST, KEY))
        local old, evidence = outsideStory(f.session()), copy(f.session().samsaraStory.evidence)
        f.publish(copy(f.session()))
        eq(f.Player.onResult(resultFor(lease, "dismissed")), true, "read token survives explicit same-game publication")
        eq(f.Player.getRecord(KEY).status, "finished", "result reaches reattached JSON table")
        eq(f.Player.requestRead(KEY), true, "replay queued")
        f.publish(copy(f.session()))
        eq(f.Player.takeRequest().kind, REPLAY, "queued replay survives publication")
        local replay = assert(f.Player.begin(REPLAY, KEY))
        local fresh = oldSession(); fresh.samsaraStory = f.Schema.new()
        f.publish(fresh)
        local before = copy(f.session())
        eq(f.Player.onResult(resultFor(replay, "finished")), false, "uncaptured new game invalidates old read token")
        check(same(f.session(), before), "new game untouched by old result")
        eq(f.session().samsaraStory.historyCaptured, false, "notification never scans previous battle")
        check(same(evidence, {}), "opening chain/read never created evidence")
        check(same(outsideStory(oldRef), old), "original game legacy fields unaffected except deliberate preclaim publication")
    end)
    runCase("getter-only foreign save and init reject late N01 token", function()
        local f = fixture(trustedSession()); f.init()
        local lease = assert(f.Player.begin(FIRST, KEY))
        f.Dispatcher.unsubscribe("session", f.Player.onSessionUpdated)
        local foreign = trustedSession()
        f.Dispatcher.set("session", foreign)
        local before = copy(foreign)
        eq(f.Player.onResult(resultFor(lease, "finished")), false, "silent table swap refuses late result")
        check(same(foreign, before), "silent foreign table preserved")
        f.init()
        eq(f.Player.onResult(resultFor(lease, "skipped")), false, "after new init old token still rejected")
        eq(f.Player.getRecord(KEY).status, "pending", "new save pending not marked by old token")
    end)
end

local function saveCases()
    for _, phase in ipairs({ "eligibility", "resolution" }) do
        for _, fault in ipairs({ "open", "write", "encode", "rename", "set", "nil", "throw" }) do
            runCase("opening " .. phase .. " Flush failure/retry/JSON restore " .. fault, function()
                local f = fixture(capturedSession()); f.init()
                eq(f.Save.Flush(), true, "establish real memory disk baseline")
                local old, evidence = outsideStory(f.session()), copy(f.session().samsaraStory.evidence)
                local epoch = assert(f.Player.beginOpening())
                for i = 1, #CHAIN - 1 do f.Player.noteOpeningResult(CHAIN[i], "finished", epoch) end
                if phase == "resolution" then eq(f.Player.noteOpeningResult("join.3", "finished", epoch), true, "baseline eligibility persisted") end
                local beforeDisk, writes = f.disk, f.n("flush")
                if fault == "nil" or fault == "throw" then f.flushMode = fault else f.fail = fault end
                if phase == "eligibility" then eq(f.Player.noteOpeningResult("join.3", "finished", epoch), true, "qualification retained despite save failure")
                else
                    eq(f.Playback.tryPlay(gates(f)), true, "real first-read before failed write")
                    f.Dialogue.skip()
                end
                eq(f.Player.getRecord(KEY).status, phase == "eligibility" and "pending" or "skipped", "memory result remains correct")
                eq(f.Player.isSavePending(), true, "failed write savePending")
                eq(f.disk, beforeDisk, "failed write never claims disk success")
                eq(f.n("flush"), writes + (fault == "set" and 0 or 1), "notify failure avoids Flush; other failures attempt once")
                local reboot = fixture(cjson.decode(beforeDisk).modules.session); reboot.init()
                if phase == "eligibility" then reference(reboot, "failed disk restart")
                else eq(reboot.Player.getRecord(KEY).status, "pending", "failed first-read disk remains pending") end
                local attempts = f.n("flush")
                f.Player.cancel(); f.init()
                eq(f.Player.isSavePending(), true, "cancel and same-table init preserve dirty result")
                f.Player.update(-1); f.Player.update(0 / 0); f.Player.update(math.huge)
                f.Player.update(1); f.Player.update(0.999)
                eq(f.n("flush"), attempts, "before two seconds no retry")
                f.Player.update(0.001)
                eq(f.n("flush"), attempts + (fault == "set" and 0 or 1), "two seconds tries once without hot loop")
                eq(f.Player.isSavePending(), true, "failed retry still pending")
                f.fail, f.flushMode = "", "real"
                f.Player.update(2)
                eq(f.Player.isSavePending(), false, "actual successful Flush clears pending")
                local saved = cjson.decode(f.disk)
                eq(saved.modules.session.samsaraStory.nodes[KEY].eligibilitySource, "live_opening_chain", "disk trusted source")
                eq(saved.modules.session.samsaraStory.nodes[KEY].resolution, phase == "resolution" and "skipped" or nil, "disk exact first-read result")
                eq(f.Save.RestoreData(), true, "real Save/Dispatcher memory restore")
                f.init()
                eq(f.Player.getRecord(KEY).status, phase == "resolution" and "skipped" or "pending", "restored N01 result")
                noEvidence(f, evidence, "save fault recovery")
                noRewards(f, old, "save fault recovery")
                local done = f.n("flush"); f.Player.update(100)
                eq(f.n("flush"), done, "success stops retries")
            end)
        end
    end
end

-- Standalone夹具复用上述真实模块；标题、Letter与Dialogue也是真源码。
-- 无关页面仅稳定返回门禁/阵容边界，旧grant_starter_trio只计数不执行。
-- 不调用私有函数，不靠源码替换、debug或复制开场状态机进入路径。
local function bindStandalone(f)
    local h = { modules = {}, notes = {}, grants = 0, extraActions = {}, frames = 0, backfills = 0 }
    -- bootWiring替身不创建默认player；真实hasData必须收齐五模块，不能伪造ready/跳过补播门禁。
    if not f.Dispatcher.get("player") then
        f.Dispatcher.set("player", assert(f.Registry.find("player")).getDefault())
    end
    eq(f.Dispatcher.hasData(), true, "host core data complete; missing=" .. f.Dispatcher.getMissingRequiredModules())
    local function page()
        return setmetatable({}, { __index = function() return function() return false end end })
    end
    h.Letter = isolated("ui/story/gate/LetterIntro.lua", {
        ["core.I18n"] = f.I18n, ["core.I18nStory"] = f.Story, ["ui.story.StoryDisplay"] = f.Display,
    }, f.graphics)
    h.Title = isolated("ui/story/gate/DarkTitleScreenGate.lua", { ["core.I18n"] = f.I18n }, f.graphics)
    local note = f.Player.noteOpeningResult
    f.Player.noteOpeningResult = function(step, reason, epoch)
        h.notes[#h.notes + 1] = { step = step, reason = reason, epoch = epoch }
        return note(step, reason, epoch)
    end
    local modules = h.modules
    modules["config.GameConfig"], modules["config.SamsaraSliceConfig"] = f.GameConfig, f.Config
    modules["config.ScenarioDialogueConfig"], modules["runtime.ClientDispatcher"] = f.Legacy, f.Dispatcher
    modules["shared.session.SessionSchema"] = f.SessionSchema
    modules["systems.SamsaraSlicePlayer"], modules["systems.SamsaraSlicePlayback"] = f.Player, f.Playback
    modules["ui.story.ScenarioDialogue"], modules["ui.story.gate.LetterIntro"] = f.Dialogue, h.Letter
    modules["ui.story.gate.DarkTitleScreenGate"] = h.Title
    modules["core.EventBus"] = f.Bus
    modules["config.GameEvents"] = isolated("config/GameEvents.lua", {})
    modules["core.I18n"] = f.I18n
    modules["boot.StandaloneRT"] = {}
    modules["boot.StandaloneHorizon"] = {} -- 不装真实全局输入/渲染；宿主 HandleUpdate仍原样。
    modules["boot.StandaloneBoot"] = { run = function() end }
    modules["boot.StandaloneHorizonInput"] = { isPointerBusy = function() return false end }
    modules["boot.StandaloneSave"] = f.Save
    modules["core.GameState"] = { reset = function() end }
    modules["ui.character.panel.CharacterPanel"] = setmetatable({
        isHeroesDataApplied = function() return true end, getDeployedTeam = function() return {} end,
        getTotalPower = function() return 0 end,
    }, { __index = function() return function() return false end end })
    modules["ui.hud.BottomNav"] = setmetatable({ getSelectedIndex = function() return 3 end },
        { __index = function() return function() return false end end })
    modules["ui.battle.scene.BattleScene"] = setmetatable({
        getMaxStageId = function() return 101 end, getStageId = function() return 101 end,
        getClearedStages = function() return {} end,
    }, { __index = function() return function() return false end end })
    modules["runtime.ClientMessageHandler"] = setmetatable({
        consumePendingScenarioDialogue = function() return nil end, consumePendingFollowUpDialogue = function() return nil end,
    }, { __index = function() return function() return false end end })
    modules["systems.StoryPlayer"] = setmetatable({ take = function() return nil end,
        backfillCleared = function() h.backfills = h.backfills + 1 end,
    }, { __index = function() return function() return false end end })
    modules["systems.TutorialManager"] = setmetatable({ canPlayPendingStory = function() return true end },
        { __index = function() return function() return false end end })
    modules["rules.offline.OfflineService"] = {
        CalcOnEnter = function() return nil end, HasPendingRewards = function() return false end,
    }
    modules["runtime.GameAction"] = { sendAction = function(action)
        if action == "grant_starter_trio" then h.grants = h.grants + 1
        else h.extraActions[#h.extraActions + 1] = action end
        return true
    end }
    -- Standalone.Start中的Scene/GPU/事件只替换边界，不触碰真实engine/renderer。
    local scene = { CreateComponent = function() return {} end,
        CreateChild = function() return { CreateComponent = function() return {} end } end }
    local globals = { Scene = function() return scene end,
        renderer = { SetViewport = function() end }, Viewport = { new = function() return {} end },
        graphics = { GetWidth = function() return 1920 end, GetHeight = function() return 1080 end, GetDPR = function() return 1 end },
        time = { elapsedTime = 100 }, nvgCreate = function() return {} end, nvgCreateFont = function() return 1 end,
        nvgCreateImage = f.graphics.nvgCreateImage, nvgDelete = function() end, SubscribeToEvent = function() end,
        HandleEquipmentHoverTickHorizon = function() end,
        H_AUTO_OPEN_TRI = false, H_AUTO_TAB = false, H_AUTO_OPEN_PANEL = false,
    }
    h.Standalone, h.env = isolated("boot/Standalone.lua", modules, globals, function(name)
        assert(name ~= "rules.character.PlayerDataManager", "host must not load real PDM")
        if not modules[name] then modules[name] = page() end
        return modules[name]
    end)
    -- dialogue.init仍执行真实方法，但声源cache隔离；标题/Letter也真实init。
    h.Standalone.Start()
    function h.frame(dt)
        h.frames = h.frames + 1
        h.env.time.elapsedTime = h.env.time.elapsedTime + (dt or 0.016)
        h.env.HandleUpdate("Update", { TimeStep = { GetFloat = function() return dt or 0.016 end } })
    end
    -- 真实bootQueue在私有时钟同帧泵完，没有任何运行时事件订阅到全局。
    h.frame()
    eq(h.Title.isOpen(), true, "real Standalone title opened")
    eq(h.Title.isReady(), true, "real boot queue unlocked title")
    function h.enter()
        h.Title.handleTap()
        -- 真实宿主先update标题，再检查isFading；跨过0.55s的单帧会先关闭并return。
        -- 按正常小帧经历淡出中的开场判定，并送关闭后的下一帧，不能假定closed即已进入。
        for _ = 1, 8 do
            if not h.Title.isOpen() then break end
            h.frame(0.1)
        end
        eq(h.Title.isOpen(), false, "real title fade closes")
        h.frame()
    end
    function h.finishLetter()
        for _ = 1, 12 do
            if not h.Letter.isOpen() then break end
            h.Letter.update(100)
        end
        eq(h.Letter.isOpen(), false, "real LetterIntro updates invoke captured completion callback")
    end
    function h.noExtra(label)
        eq(#h.extraActions, 0, label .. " no new economic action " .. table.concat(h.extraActions, ","))
        eq(f.Dispatcher.get("currency").gold, 123, label .. " currency untouched")
        eq(f.gameState.gold, 123, label .. " GameState untouched")
    end
    return h
end

local function hostFixture(legacy)
    local session = oldSession()
    session.introCompleted, session.claimedScenarios, session.scenarioRewardsGranted = false, {}, {}
    local f = fixture(session, nil, legacy)
    f.Dispatcher.set("heroes", { roster = { [1] = { level = 1 } }, deployed = { 1 } })
    return f, bindStandalone(f)
end
local function openingShows(h, f)
    h.enter()
    eq(h.Letter.isOpen(), true, "title-to-letter path is real")
    eq(#f.shown, 0, "no opening Dialogue before Letter finishes")
    h.finishLetter()
    eq(#f.shown, 1, "Letter callback synchronously shows OPENING exactly once")
    return assert(f.shown[1])
end
local function assertHostConfig(f, index)
    local cfg = assert(f.shown[index], "missing genuine host show " .. index)
    local original = index == 1 and f.Legacy.OPENING or f.Legacy.OPENING_JOINS[index - 1]
    eq(cfg.title, original.title, "host title from real config " .. index)
    eq(cfg.mode, original.mode, "host mode unchanged " .. index)
    eq(#cfg.steps, #original.steps, "host step count genuine " .. index)
    for i, step in ipairs(original.steps) do
        eq(cfg.steps[i].text, step.text, "host exact original text " .. index .. "/" .. i)
        eq(cfg.steps[i].characterId, step.characterId, "host exact portrait identity " .. index .. "/" .. i)
    end
    eq(cfg.onFinish, nil, "host does not prove completion via onFinish " .. index)
    check(type(cfg.onResult) == "function" and type(cfg.completionToken) == "table", "host has independent captured token result " .. index)
    return cfg
end

local function hostCases()
    for _, mode in ipairs({ "finished", "skipped" }) do
        runCase("real Standalone title/Letter/OPENING/three joins next-frame " .. mode, function()
            local f, h = hostFixture()
            openingShows(h, f)
            local evidence = copy(f.session().samsaraStory.evidence)
            for index = 1, 4 do
                local cfg = assertHostConfig(f, index)
                eq(f.Player.getRecord(KEY).status, "locked", "before final join N01 is not eligible")
                if mode == "skipped" then f.Dialogue.skip()
                else finishDialogue(f.Dialogue); if cfg.mode == "small" then f.Dialogue.update(0.31) end end
                eq(#f.shown, index, "result callback never recursively shows next part " .. index)
                if index < 4 then
                    eq(f.Player.getRecord(KEY).referenceOnly, true, "partial host chain no live qualification")
                    h.frame()
                    eq(#f.shown, index + 1, "next host frame starts following genuine config")
                end
            end
            eq(#h.notes, 5, "only five genuinely displayed chain segments reported")
            local epoch = h.notes[1].epoch
            for i, note in ipairs(h.notes) do
                eq(note.step, CHAIN[i], "host reports exact ordered segment " .. i)
                eq(note.reason, i == 1 and "finished" or mode, "host reports actual segment result " .. i)
                eq(note.epoch, epoch, "host carries same process epoch " .. i)
            end
            eq(f.node().eligibilitySource, "live_opening_chain", "host complete chain source")
            eq(f.Player.getRecord(KEY).status, "pending", "last host join establishes pending N01")
            eq(h.grants, 1, "existing starter grant only once, never replayed for N01")
            -- 最后onResult不展示N01；下一帧交回真正Playback仲裁。
            eq(h.backfills, 0, "opening display blocks legacy backfill until safe host frame")
            h.frame()
            eq(h.backfills, 1, "safe host frame executes actual data-ready backfill branch")
            local nextCfg = assert(f.shown[5])
            eq(nextCfg.completionToken.nodeKey, KEY, "only next frame starts genuine N01 slice")
            eq(nextCfg.onFinish, nil, "N01 no reward callback")
            f.Dialogue.skip()
            eq(f.Player.getRecord(KEY).status, "skipped", "host-launched N01 token processed")
            local old = outsideStory(f.session())
            eq(f.Player.requestRead(KEY), true, "host record replay requested")
            h.frame(); f.Dialogue.skip()
            eq(h.grants, 1, "N01 replay never re-grants starter trio")
            noEvidence(f, evidence, "real complete host chain and replay")
            noRewards(f, old, "real complete host chain and replay")
            h.noExtra("real complete host chain and replay")
        end)
    end
    for _, ending in ipairs({ "reset", "replaced" }) do
        for interrupted = 1, 4 do
        runCase("real host part " .. interrupted .. " interrupted " .. ending .. " no continuation/qualification", function()
            local f, h = hostFixture()
            openingShows(h, f)
            for _ = 1, interrupted - 1 do f.Dialogue.skip(); h.frame() end
            local before = copy(f.session().samsaraStory)
            if ending == "reset" then f.Dialogue.reset()
            else f.realShow({ mode = "small", steps = f.Config.get(KEY).steps }); f.Dialogue.reset() end
            eq(#f.shown, interrupted, "interruption no recursive next")
            for _ = 1, 3 do h.frame() end
            eq(#f.shown, interrupted, "reset/replaced does not advance chain later")
            reference(f, "host interruption")
            check(same(f.session().samsaraStory, before), "host interruption no story qualification")
            h.noExtra("host interruption")
        end)
        end
    end
    for _, fault in ipairs({ "false", "throw" }) do
        runCase("real host failed show continues without qualification " .. fault, function()
            local f, h = hostFixture()
            f.showFault = fault
            openingShows(h, f)
            eq(f.Dialogue.isActive(), false, "failed opening show is inactive")
            eq(#f.shown, 1, "failed callback no synchronous join")
            f.showFault = ""
            for index = 2, 4 do
                h.frame()
                eq(#f.shown, index, "host failed show advances only on later frame")
                assertHostConfig(f, index)
                f.Dialogue.skip()
            end
            reference(f, "failed opening show chain")
            for _, note in ipairs(h.notes) do
                if note.step == "opening" then eq(note.reason, "failed", "failed show explicit failure, never fake finished") end
            end
            h.frame()
            eq(#f.shown, 4, "failed chain not auto N01")
            h.noExtra("failed host show")
        end)
    end
    for _, missing in ipairs({ "opening", "join.1", "join.2", "join.3" }) do
        runCase("real host missing config skip does not manufacture experience " .. missing, function()
            local legacy = isolated("config/ScenarioDialogueConfig.lua", {})
            if missing == "opening" then legacy.OPENING = nil
            else legacy.OPENING_JOINS[tonumber(missing:match("%d"))] = { mode = "large", steps = {} } end
            local f, h = hostFixture(legacy)
            h.enter(); h.finishLetter()
            for _ = 1, 14 do
                if f.Dialogue.isActive() then f.Dialogue.skip() end
                h.frame()
            end
            reference(f, "missing genuine host config")
            for _, note in ipairs(h.notes) do
                if note.step == missing then eq(note.reason, "failed", "missing config only failed, never invented handled result") end
            end
            eq(#f.shown, 3, "exactly existing three configs shown; missing not fabricated")
            h.noExtra("missing host config")
        end)
    end
    runCase("real host old intro/trio cannot be mistaken for opening experience", function()
        local f = fixture(oldSession())
        f.Dispatcher.set("heroes", { roster = { [1] = { level = 1 }, [2] = { level = 1 }, [3] = { level = 1 } }, deployed = { 1, 2, 3 } })
        local h = bindStandalone(f)
        h.enter(); h.frame()
        eq(h.Letter.isOpen(), false, "old intro/trio correctly avoids repeating starter Letter")
        eq(#h.notes, 0, "skipping old host chain fabricates no result")
        eq(h.grants, 0, "old host never grants trio again")
        reference(f, "old host static N01")
        h.noExtra("old host static N01")
    end)
    runCase("real host Stop invalidates late Letter callback and chain", function()
        local f, h = hostFixture()
        h.enter()
        eq(h.Letter.isOpen(), true, "Letter started before Stop")
        h.Standalone.Stop()
        h.finishLetter()
        -- 即使宿主的旧回调还运行，失效epoch不可赋资格。
        for _ = 1, 8 do
            if f.Dialogue.isActive() then f.Dialogue.skip() end
            h.frame()
        end
        reference(f, "Stop late Letter")
        h.noExtra("Stop late Letter")
    end)
end

function Start()
    local ok, err = pcall(function()
        configurationCases()
        historicalCases()
        trackingCases()
        playbackCases()
        schemaAndFutureCases()
        publicationCases()
        saveCases()
        hostCases()
    end)
    if not ok then check(false, "Start exception: " .. tostring(err)) end
    print(PREFIX .. "RESULT cases=" .. passed .. "/" .. cases .. " assertions=" .. assertions .. " failures=" .. failures)
    if failures == 0 and cases > 0 and passed == cases then print(PREFIX .. "ALL PASS") end
    engine:Exit()
end
