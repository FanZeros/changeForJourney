-- N02 主体与N12–N14集成回归：原样执行真实 Player/Playback/Dialogue/Save/Dispatcher/Input 源码。
-- 所有边界替身仅在私有 load 环境；不改 package.loaded/全局、不读真实玩家档、
-- 不领奖/写真实文件、不访问 debug/upvalue、不复制业务实现；保留N02/E01主体并追加串行核验。
-- 作者不运行 Runtime/build；本文件由主会话按需执行。
local PREFIX = "[samsara_slice_integration] "
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

local function legacySession(session)
    local out = {}
    for key, value in pairs(session) do
        if key ~= "samsaraStory" then out[key] = copy(value) end
    end
    return out
end

-- 资源路径不含 scripts/，沿用既有 no-cutscene 测试。Runtime 未绑定 ReadText，
-- 用 ReadLine 逐行原样加载；绝不替换、拼接业务实现。
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
        if fallback then return fallback(name) end
        error("unexpected dependency in " .. path .. ": " .. name)
    end
    env._G = env
    setmetatable(env, { __index = _G })
    return assert(load(table.concat(lines, "\n"), "@" .. path, "t", env))(), env
end

-- 中文显示边界只替代语言选择/原样测量与GPU输出；UTF-8/折行/适配仍加载真实模块。
local function storyBoundary(f, graphics, scenarioConfig)
    f.displayed = {}
    local i18n = {
        get = function() return "zh_CN" end,
        lookup = function(text) return text end,
        displayBounds = function(_, _, _, text)
            f.count("display.bounds")
            return (utf8.len(text) or 0) * f.font
        end,
        displayText = function(vg, x, y, text, last)
            f.count("display.text")
            f.displayed[#f.displayed + 1] = text
            return graphics.nvgText(vg, x, y, text, last)
        end,
    }
    f.Story = isolated("core/I18nStory.lua", {})
    f.Display = isolated("ui/story/StoryDisplay.lua", {
        ["core.I18n"] = i18n, ["core.I18nStory"] = f.Story,
    }, graphics)
    local assets = isolated("config/HeroAssetUtil.lua", {
        ["config.HeroConfig"] = { get = function() return nil end },
    }, graphics)
    return { ["core.I18n"] = i18n, ["core.I18nStory"] = f.Story,
        ["ui.story.StoryDisplay"] = f.Display, ["config.ScenarioDialogueConfig"] = scenarioConfig,
        ["config.HeroAssetUtil"] = assets }
end

local function freshSession()
    return {
        lastOnlineTime = 9000, firstLoginTime = 100, introCompleted = true,
        hasReincarnated = true, firstGachaTenDone = true, initialHeroId = 1,
        offlineBonusCount = 2, offlineBonusDate = "2026-10-03",
        claimedScenarios = { ["5"] = true, ["17"] = true, ["62"] = true },
        scenarioRewardsGranted = { ["5"] = true, ["17"] = true },
        tutorialProgress = { groupId = 8, step = 3, completed = { ["1"] = true }, custom = "keep" },
        introPlayback = { done = true, source = "legacy" }, arbitraryOldField = { nested = { 7, false, "old" } },
    }
end

-- CharacterSchema 中仅测试真实 SessionSchema 字段；其他无关子系统注册以空 Fields
-- 隔离，不复制 session.onLoad，不用串行两种 onLoad 掩盖独立路径漏接。
local function schemas()
    local schema = isolated("shared/session/SamsaraStorySchema.lua", {})
    local sessionSchema = isolated("shared/session/SessionSchema.lua", {
        ["shared.session.SamsaraStorySchema"] = schema,
    })
    local registry = isolated("shared/ModuleRegistry.lua", {
        ["shared.session.SamsaraStorySchema"] = schema,
        ["shared.currency.CurrencySchema"] = { Fields = {} },
    })
    local character = isolated("shared/schemas/CharacterSchema.lua", {
        ["shared.session.SessionSchema"] = sessionSchema,
    }, nil, function(name)
        assert(name:match("^shared%..+Schema$"), "unexpected CharacterSchema dependency " .. name)
        return { Fields = {} }
    end)
    return schema, registry, character
end

---@return any
local function fixture(rawBattle, suppliedSession)
    local f = { calls = {}, disk = nil, fail = "", drawings = {}, font = 38 }
    function f.count(name) f.calls[name] = (f.calls[name] or 0) + 1 end
    function f.n(name) return f.calls[name] or 0 end
    local schema, registry, character = schemas()
    f.Schema, f.Registry, f.Character = schema, registry, character
    f.Config = isolated("config/SamsaraSliceConfig.lua", {})
    f.LegacyConfig = isolated("config/ScenarioDialogueConfig.lua", {})
    f.GameConfig = isolated("config/GameConfig.lua", {})
    f.Bus = isolated("core/EventBus.lua", {})
    f.Dispatcher = isolated("runtime/ClientDispatcher.lua", {
        ["shared.Protocol"] = {}, ["shared.ModuleRegistry"] = registry,
        ["shared.schemas.CharacterSchema"] = character,
    })
    f.Dispatcher.set("session", suppliedSession or freshSession())
    f.Dispatcher.set("battle", rawBattle or { maxStageId = 104, clearedStages = { ["104"] = true } })
    f.Dispatcher.set("currency", { gold = 123, gems = 456, oldCurrency = "keep" })
    f.Dispatcher.set("unknownModule", { data = { false, "old", 900 }, opaque = "not N02" })
    f.gameState = { gold = 123, exp = 11, oldState = { value = 42 } }
    local jsonBoundary = {
        encode = function(value)
            f.count("encode")
            if f.fail == "encode" then error("injected cjson.encode failure") end
            return cjson.encode(value)
        end,
        decode = function(value) return cjson.decode(value) end,
    }
    local globalBoundary = {
        cjson = jsonBoundary,
        fileSystem = {
            FileExists = function(_, path)
                eq(path, "standalone_save.json", "restore queries committed file only")
                return f.disk ~= nil
            end,
            Rename = function(_, from, to)
                f.count("rename")
                eq(from, "standalone_save.pending.json", "atomic replace source is temporary file")
                eq(to, "standalone_save.json", "atomic replace target is committed file")
                if f.fail == "rename" or not f.tempWritten or not f.tempClosed then return false end
                f.disk, f.temp, f.tempClosed, f.tempWritten = f.temp, nil, false, false
                return true
            end,
            Delete = function(_, path)
                f.count("temp.delete")
                eq(path, "standalone_save.pending.json", "failure deletes temporary file, never old save")
                f.temp, f.tempClosed, f.tempWritten = nil, false, false
                return true
            end,
        },
        File = function(path, mode)
            eq(path, mode == FILE_WRITE and "standalone_save.pending.json" or "standalone_save.json", "Save writes temporary / reads committed file (memory only)")
            f.count(mode == FILE_WRITE and "openWrite" or "openRead")
            local opened = not (mode == FILE_WRITE and f.fail == "open")
            if mode == FILE_WRITE and opened then f.temp, f.tempClosed, f.tempWritten = "", false, false end
            local file = {}
            function file:IsOpen() return opened end
            function file:WriteString(data)
                f.count("write")
                if not opened then return false end
                if f.fail == "write" then f.temp = data:sub(1, math.floor(#data / 2)); return false end
                f.temp, f.tempWritten = data, true
                return true
            end
            function file:ReadString() return f.disk end
            function file:Close()
                f.count("close")
                if mode == FILE_WRITE and opened then f.tempClosed = true end
            end
            return file
        end,
    }
    f.Save = isolated("boot/StandaloneSave.lua", {
        ["runtime.ClientDispatcher"] = f.Dispatcher,
        ["core.GameState"] = {
            exportSave = function() return f.gameState end,
            importSave = function(state) f.gameState = state end,
            syncPlayerData = function(player, options)
                f.count("player.sync")
                eq(player, f.Dispatcher.get("player"), "Restore synchronizes published player")
                eq(options.silent, true, "Restore synchronizes silently")
            end,
        },
        ["ui.battle.scene.BattleScene"] = {
            setBattleData = function() f.count("battle.apply") end,
        },
        ["rules.offline.OfflineService"] = {
            HasPendingRewards = function() f.count("offline.pending"); return false end,
            MarkOnline = function() f.count("offline.mark") end,
        },
    }, globalBoundary)
    local playerDependencies = {
        ["config.SamsaraSliceConfig"] = f.Config,
        ["shared.session.SamsaraStorySchema"] = schema,
        ["config.ScenarioDialogueConfig"] = f.LegacyConfig,
    }
    f.Player = isolated("systems/SamsaraSlicePlayer.lua", playerDependencies)
    -- 同一游戏的 JSON 发布由显式订阅重新附着，绝不只靠 getter 猜测跨档身份。
    -- 这是 N02 的新增集成契约。
    if type(f.Player.onSessionUpdated) == "function" then
        f.Dispatcher.subscribe("session", f.Player.onSessionUpdated)
    end
    f.options = {
        getSession = function() return f.Dispatcher.get("session") end,
        setSession = function(session)
            f.count("session.set")
            f.Dispatcher.set("session", session)
        end,
        flush = function()
            f.count("flush")
            return f.Save.Flush() -- 真实 writeFile；仅底层 File/cjson 注入失败
        end,
    }
    function f.session() return assert(f.Dispatcher.get("session")) end
    function f.node() return f.session().samsaraStory.nodes[f.Config.NODE_KEY] end
    function f.init(battle) return f.Player.init(f.options, battle or f.Dispatcher.get("battle")) end
    f.DrawUtil = {
        hitTest = function(x, y, cx, cy, w, h)
            return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5
        end,
        drawTextStroke = function(_, _, _, text) f.drawings[#f.drawings + 1] = text end,
        drawImageCover = function() f.count("draw.image") end,
        drawRoundedRectCentered = function() f.count("draw.rect") end,
    }
    f.graphicsBoundary = {
        nvgCreateImage = function() f.count("image.create"); return -1 end,
        nvgFontSize = function(_, size) f.font = size end,
        nvgTextBoxBounds = function(_, _, _, width, text)
            local lines = 0
            for line in (text .. "\n"):gmatch("(.-)\n") do
                lines = lines + math.max(1, math.ceil((utf8.len(line) or 0) * f.font / math.max(1, width)))
            end
            return { 0, 0, width, lines * f.font * 1.5 }
        end,
        nvgTextBox = function(_, _, _, _, text) f.drawings[#f.drawings + 1] = text end,
        nvgText = function(_, _, _, text) f.drawings[#f.drawings + 1] = text end,
        nvgRGBA = function() return {} end,
    }
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgIntersectScissor", "nvgScale",
        "nvgFontFace", "nvgTextAlign", "nvgTextLineHeight", "nvgFillColor", "nvgScissor", "nvgTranslate",
        "nvgBeginPath", "nvgRect", "nvgFill", "nvgRoundedRect", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgResetScissor" }) do
        f.graphicsBoundary[name] = function() end
    end
    -- 经济/旧剧情入口所有方法均计数（包括未知方法），Player 与 Playback 私有
    -- require 表共用这些 spy；真实业务方法不被替换，N02 不应调用这些依赖。
    local function forbidden(name)
        return setmetatable({}, { __index = function(_, method)
            return function() f.count(name .. "." .. tostring(method)); return false end
        end })
    end
    f.forbidden = {
        ["runtime.GameAction"] = forbidden("GameAction"),
        ["rules.character.PlayerDataManager"] = forbidden("PDM"),
        ["runtime.ClientMessageHandler"] = forbidden("CMH"),
        ["systems.TutorialManager"] = forbidden("tutorial"),
        ["systems.StoryPlayer"] = forbidden("legacy"),
    }
    for name, spy in pairs(f.forbidden) do playerDependencies[name] = spy end
    local dialogueDependencies = storyBoundary(f, f.graphicsBoundary, f.LegacyConfig)
    dialogueDependencies["core.DrawUtil"] = f.DrawUtil
    dialogueDependencies["config.GameConfig"] = f.GameConfig
    dialogueDependencies["ui.widget.HeroFrame"] = { draw = function() f.count("draw.hero") end }
    dialogueDependencies["core.EventBus"] = f.Bus
    f.Dialogue = isolated("ui/story/ScenarioDialogue.lua", dialogueDependencies, f.graphicsBoundary)
    local dependencies = {}
    for name, spy in pairs(f.forbidden) do dependencies[name] = spy end
    dependencies["systems.SamsaraSlicePlayer"] = f.Player
    dependencies["config.SamsaraSliceConfig"] = f.Config
    dependencies["ui.story.ScenarioDialogue"] = f.Dialogue
    f.Playback = isolated("systems/SamsaraSlicePlayback.lua", dependencies)
    f.Panel = isolated("ui/story/SamsaraRecordPanel.lua", {
        ["core.DrawUtil"] = f.DrawUtil,
        ["core.DarkIcon"] = { draw = function() end, drawNine = function() end },
        ["systems.SamsaraSlicePlayer"] = f.Player,
        ["config.SamsaraSliceConfig"] = f.Config,
    }, f.graphicsBoundary)
    return f
end

local function noRewards(f, before, label)
    local forbiddenCalls = {}
    for name, count in pairs(f.calls) do
        if count > 0 and (name:match("^GameAction%.") or name:match("^PDM%.")
            or name:match("^CMH%.") or name:match("^tutorial%.") or name:match("^legacy%.")) then
            forbiddenCalls[#forbiddenCalls + 1] = name .. "=" .. count
        end
    end
    eq(#forbiddenCalls, 0, label .. " claim/tutorial/FOLLOW/legacy.take/PDM/CMH zero " .. table.concat(forbiddenCalls, ","))
    check(same(legacySession(f.session()), before), label .. " every pre-existing session field unchanged")
    eq(f.Dispatcher.get("currency").gold, 123, label .. " currency unchanged")
    eq(f.n("battle.apply"), 0, label .. " no battle restore side effect")
end

local function gates()
    return { ready = true, legacyPending = false, blocked = false, pointerBusy = false }
end

-- 用真实打字机与进度驱动结束；不复制结束逻辑、不用 Player.onResult 代替
-- 本应覆盖 Dialogue 的完成路径。
local function finishDialogue(dialogue)
    local _, total = dialogue.getProgress()
    for _ = 1, total do dialogue.update(100); dialogue.advance() end
end

local function resultFor(lease, reason)
    return { playToken = lease.playToken, contextEpoch = lease.contextEpoch,
        nodeKey = lease.nodeKey, reason = reason }
end

local function dialogueCases()
    for _, mode in ipairs({ "small", "large" }) do
        runCase("real Dialogue " .. mode .. " normal completion once", function()
            local f = fixture()
            local cfg = assert(f.Config.get(f.Config.NODE_KEY))
            local token = { playToken = 31, contextEpoch = 7, nodeKey = f.Config.NODE_KEY, kind = "samsara_first_read" }
            local results, finishes, broadcasts = {}, 0, 0
            f.Bus.on("scenario_dialogue_finished", function() broadcasts = broadcasts + 1 end)
            cfg.mode, cfg.completionToken = mode, token
            cfg.onFinish = function() finishes = finishes + 1 end
            cfg.onResult = function(result) results[#results + 1] = result end
            eq(f.Dialogue.show(cfg), true, "show returns real boolean true")
            check(f.Dialogue.isSliceActive(), "slice kind identified")
            f.Dialogue.update(100); f.Dialogue.draw(1920, 1080)
            eq(f.Display.text(cfg.steps[1].text), cfg.steps[1].text, "Chinese display preserves source text")
            eq(f.Story.length(cfg.steps[1].text), utf8.len(cfg.steps[1].text), "real UTF-8 codepoint length")
            check(table.concat(f.displayed):find(cfg.steps[1].text, 1, true) ~= nil, "real fitLayout/drawRows emits complete Chinese first step")
            token.playToken, token.contextEpoch, token.nodeKey = 999, 999, "tampered" -- show捕获值，不能持有外部可变引用
            finishDialogue(f.Dialogue)
            if mode == "small" then
                check(f.Dialogue.isActive(), "small retains active through dismiss animation")
                eq(#results, 0, "small no early completion")
                f.Dialogue.update(0.29)
                eq(#results, 0, "small before dismiss threshold")
                f.Dialogue.update(0.02)
            end
            eq(#results, 1, "result once")
            local result = assert(results[1])
            eq(result.reason, mode == "small" and "dismissed" or "finished", "actual normal end reason")
            eq(result.playToken, 31, "immutable playToken snapshot")
            eq(result.contextEpoch, 7, "immutable epoch snapshot")
            eq(result.nodeKey, f.Config.NODE_KEY, "immutable nodeKey snapshot")
            eq(result.mode, mode, "captured mode")
            eq(finishes, 1, "legacy onFinish once")
            eq(broadcasts, 1, "legacy broadcast once")
            check(not f.Dialogue.isActive() and not f.Dialogue.isSliceActive(), "normal end releases display")
            f.Dialogue.skip(); f.Dialogue.advance(); f.Dialogue.update(100); f.Dialogue.reset()
            eq(#results, 1, "late end/reset cannot duplicate result")
            eq(finishes, 1, "late calls cannot duplicate old onFinish")
            eq(broadcasts, 1, "late calls cannot duplicate old broadcast")
        end)
    end
    for _, reason in ipairs({ "skipped", "reset", "replaced" }) do
        runCase("real Dialogue " .. reason .. " and old compatibility", function()
            local f = fixture()
            local results, finishes, broadcasts = {}, 0, 0
            f.Bus.on("scenario_dialogue_finished", function() broadcasts = broadcasts + 1 end)
            local cfg = assert(f.Config.get(f.Config.NODE_KEY))
            cfg.completionToken = { playToken = 32, contextEpoch = 8, nodeKey = f.Config.NODE_KEY, kind = "samsara_replay" }
            cfg.onResult = function(result) results[#results + 1] = result end
            cfg.onFinish = function() finishes = finishes + 1 end
            eq(f.Dialogue.show(cfg), true, "real show before " .. reason)
            if reason == "skipped" then f.Dialogue.skip()
            elseif reason == "reset" then f.Dialogue.reset()
            else eq(f.Dialogue.show({ mode = "small", steps = cfg.steps }), true, "replacing with old caller") end
            eq(#results, 1, reason .. " exactly one token result")
            eq(assert(results[1]).reason, reason, "actual terminal reason")
            eq(results[1].playToken, 32, "terminal token retained")
            eq(finishes, reason == "skipped" and 1 or 0, "reset/replaced do not old-finish")
            eq(broadcasts, reason == "skipped" and 1 or 0, "reset/replaced do not broadcast")
            f.Dialogue.reset()
            eq(#results, 1, "reset after terminal does not double-report")
            eq(f.Dialogue.show({ steps = {} }), false, "empty real show returns false")
            eq(f.Dialogue.show(nil), false, "nil real show returns false")
            check(not f.Dialogue.isSliceActive(), "old caller is not slice")
        end)
    end
    for _, ending in ipairs({ "dismissed", "finished", "skipped" }) do
        for _, reentry in ipairs({ "onFinish", "broadcast", "both" }) do
            runCase("captured result " .. ending .. " survives synchronous " .. reentry .. " show", function()
                local f = fixture()
                local results, oldFinish, broadcasts = {}, 0, 0
                local function showToken(id)
                    local nextCfg = assert(f.Config.get(f.Config.NODE_KEY))
                    nextCfg.mode = "large"
                    nextCfg.completionToken = { playToken = id, contextEpoch = id + 100,
                        nodeKey = f.Config.NODE_KEY, kind = "samsara_replay" }
                    nextCfg.onResult = function(result) results[#results + 1] = result end
                    return f.Dialogue.show(nextCfg)
                end
                f.Bus.on("scenario_dialogue_finished", function()
                    broadcasts = broadcasts + 1
                    if broadcasts == 1 and reentry ~= "onFinish" then eq(showToken(43), true, "broadcast synchronously shows") end
                end)
                local cfg = assert(f.Config.get(f.Config.NODE_KEY))
                cfg.mode = ending == "dismissed" and "small" or "large"
                cfg.completionToken = { playToken = 41, contextEpoch = 141, nodeKey = f.Config.NODE_KEY, kind = "samsara_first_read" }
                cfg.onResult = function(result) results[#results + 1] = result end
                cfg.onFinish = function()
                    oldFinish = oldFinish + 1
                    if reentry ~= "broadcast" then eq(showToken(42), true, "old onFinish synchronously shows") end
                end
                f.Dialogue.show(cfg)
                if ending == "skipped" then f.Dialogue.skip()
                else finishDialogue(f.Dialogue); if ending == "dismissed" then f.Dialogue.update(0.31) end end
                local oldResults = 0
                for _, result in ipairs(results) do
                    if result.playToken == 41 then
                        oldResults = oldResults + 1
                        eq(result.contextEpoch, 141, "old epoch not overwritten by synchronous show")
                        eq(result.reason, ending, "old reason not replaced by new show")
                        eq(result.mode, cfg.mode, "old result mode captured before callback")
                    end
                end
                eq(oldResults, 1, "old result survives exactly once")
                eq(oldFinish, 1, "old onFinish once even with synchronous show")
                eq(broadcasts, 1, "old finished broadcast once")
                check(f.Dialogue.isActive(), "replacement remains active")
                f.Dialogue.reset()
                local expectedId = reentry == "onFinish" and 42 or 43
                local last = assert(results[#results])
                eq(last.playToken, expectedId, "new slot retained separately")
                eq(last.reason, "reset", "reset belongs only to new slot")
            end)
        end
    end
end

local function playbackCases()
    for _, gateName in ipairs({ "notReady", "legacyPending", "blocked", "pointerBusy", "dialogueActive", "nilGates" }) do
        runCase("Playback gate " .. gateName .. " non-consuming", function()
            local f = fixture(); f.init()
            local old = legacySession(f.session())
            eq(f.Player.requestRead(f.Config.NODE_KEY), true, "real request queued")
            local take, realShow = f.Player.takeRequest, f.Dialogue.show
            f.Player.takeRequest = function() f.count("request.take"); return take() end
            f.Dialogue.show = function(cfg) f.count("dialogue.show"); return realShow(cfg) end
            local gate = gates()
            if gateName == "notReady" then gate.ready = false
            elseif gateName == "dialogueActive" then realShow({ mode = "small", steps = assert(f.Config.get(f.Config.NODE_KEY)).steps })
            elseif gateName ~= "nilGates" then gate[gateName] = true end
            eq(f.Playback.tryPlay(gateName ~= "nilGates" and gate or nil), false, "gate prevents start")
            eq(f.n("request.take"), 0, "gate never takes request")
            eq(f.n("dialogue.show"), 0, "gate never calls show")
            local request = assert(take(), "blocked request must remain in real single-slot queue")
            eq(request.key, f.Config.NODE_KEY, "request preserved key")
            eq(request.kind, "samsara_first_read", "request preserved kind")
            eq(f.Player.getRecord().status, "pending", "not completed by gate")
            noRewards(f, old, gateName)
        end)
    end
    for _, ending in ipairs({ "dismissed", "skipped", "reset", "replaced" }) do
        runCase("Playback real " .. ending .. " no legacy rewards or reentry", function()
            local f = fixture(); f.init()
            local old = legacySession(f.session())
            local shows, broadcasts = 0, 0
            local realShow = f.Dialogue.show
            f.Dialogue.show = function(cfg)
                shows = shows + 1
                eq(cfg.onFinish, nil, "N02 never installs old reward onFinish")
                check(type(cfg.onResult) == "function" and type(cfg.completionToken) == "table", "only token result contract installed")
                return realShow(cfg)
            end
            f.Bus.on("scenario_dialogue_finished", function() broadcasts = broadcasts + 1 end)
            check(not f.Player.getRecord().evidenceVisible, "eligible E01 not yet visible")
            eq(f.Playback.tryPlay(gates()), true, "true Player+Config+Dialogue start")
            eq(f.Player.peekReady(), nil, "lease prevents another ready node")
            eq(f.Playback.tryPlay(gates()), false, "active display is arbitration gate")
            eq(shows, 1, "active display cannot show again")
            if ending == "dismissed" then
                finishDialogue(f.Dialogue)
                eq(f.Player.getRecord().status, "pending", "dismiss animation not yet processed")
                f.Dialogue.update(0.31)
            elseif ending == "skipped" then f.Dialogue.skip()
            elseif ending == "reset" then f.Dialogue.reset()
            else realShow({ mode = "small", steps = assert(f.Config.get(f.Config.NODE_KEY)).steps }) end
            local processed = ending == "dismissed" or ending == "skipped"
            eq(f.Player.getRecord().status, processed and (ending == "skipped" and "skipped" or "finished") or "pending", "only successful end processed")
            eq(f.Player.getRecord().evidenceVisible, processed, "evidence follows processing not eligibility")
            eq(shows, 1, "result never synchronously replays/shows")
            eq(broadcasts, processed and 1 or 0, "old broadcasts unchanged")
            noRewards(f, old, ending)
            if processed then
                local storyBefore = copy(f.session().samsaraStory)
                local flushBefore = f.n("flush")
                eq(f.Player.requestRead(f.Config.NODE_KEY), true, "processed record queues replay")
                eq(f.Playback.tryPlay(gates()), true, "replay begins on a later explicit arbitration")
                f.Dialogue.skip()
                check(same(f.session().samsaraStory, storyBefore), "replay skipped cannot rewrite first resolution/evidence/history")
                eq(f.n("flush"), flushBefore, "replay no persistent write")
                noRewards(f, old, "replay")
            else
                f.Dialogue.reset()
                eq(f.Player.peekReady(), f.Config.NODE_KEY, "cancelled display remains pending for next host frame")
            end
        end)
    end
    for _, fault in ipairs({ "false", "throw" }) do
        runCase("Playback show " .. fault .. " does not complete", function()
            local f = fixture(); f.init()
            local old, before = legacySession(f.session()), f.n("flush")
            local realShow = f.Dialogue.show
            f.Dialogue.show = function()
                f.count("dialogue.show")
                if fault == "false" then return realShow({ steps = {} }) end
                error("injected presentation-boundary exception")
            end
            eq(f.Playback.tryPlay(gates()), false, "presentation failure handled")
            eq(f.Player.getRecord().status, "pending", "failure not a completion")
            check(not f.Player.getRecord().evidenceVisible, "failed show no original evidence")
            eq(f.Player.peekReady(), f.Config.NODE_KEY, "failure cancels only lease")
            eq(f.n("flush"), before, "failed display no persistence")
            noRewards(f, old, fault)
            f.Dialogue.show = realShow
            eq(f.Playback.tryPlay(gates()), true, "next host frame can recover")
            f.Dialogue.skip()
            eq(f.Player.getRecord().status, "skipped", "only recovery completion processes node")
        end)
    end
    runCase("Player exact lease / cancelled / foreign session identity", function()
        local f = fixture(); f.init()
        local old = legacySession(f.session())
        local lease = assert(f.Player.begin("samsara_first_read", f.Config.NODE_KEY))
        for _, field in ipairs({ "playToken", "contextEpoch", "nodeKey" }) do
            local wrong = resultFor(lease, "finished")
            wrong[field] = field == "nodeKey" and "wrong" or 999
            eq(f.Player.onResult(wrong), false, "wrong " .. field .. " rejected")
        end
        eq(f.Player.onResult(resultFor(lease, "other")), false, "unknown reason rejected")
        f.Player.cancel()
        eq(f.Player.onResult(resultFor(lease, "finished")), false, "cancelled lease stale")
        local nextLease = assert(f.Player.begin("samsara_first_read", f.Config.NODE_KEY))
        check(nextLease.playToken ~= lease.playToken and nextLease.contextEpoch ~= lease.contextEpoch, "new lease new identity")
        eq(f.Player.onResult(resultFor(lease, "skipped")), false, "old lease cannot finish new one")
        if type(f.Player.onSessionUpdated) == "function" then f.Dispatcher.unsubscribe("session", f.Player.onSessionUpdated) end
        local foreign = copy(f.session())
        f.Dispatcher.set("session", foreign) -- 故意无通知，不能猜测这是同一个游戏会话
        eq(f.Player.onResult(resultFor(nextLease, "finished")), false, "getter silently replacing session rejects delayed result")
        eq(foreign.samsaraStory.nodes[f.Config.NODE_KEY].resolution, nil, "new table unmodified by old lease")
        noRewards(f, old, "identity")
    end)
end

local function schemaCases()
    for _, loader in ipairs({ "Registry", "Character" }) do
        runCase("independent " .. loader .. " session onLoad and repeat normalize preservation", function()
            local f = fixture()
            local session = freshSession()
            session.samsaraStory = {
                schemaVersion = 1, historyCaptured = true, cargoHistoryCaptured = false, customStory = { keep = "yes" },
                nodes = {
                    [f.Config.NODE_KEY] = { eligible = true, contentVersion = 1, resolution = "skipped",
                        eligibilitySource = "live_clear", legacyContext = "live_skipped", customNode = { x = 8 } },
                    unknown_node = { opaque = "preserve", contentVersion = 88 },
                },
                evidence = { E01 = { unlocked = true, source = "live_clear", customEvidence = false },
                    unknown_evidence = { opaque = "preserve" } },
            }
            local expected = copy(session)
            expected.samsaraStory.mirrorHistoryCaptured = false
            expected.samsaraStory.mirrorHistoryVersion = 1
            f[loader].applyOnLoad("session", session) -- 每条路径独立运行，不串两种onLoad掩盖漏接
            check(same(session, expected), loader .. " old/unknown fields intact，镜像域仅补独立默认值")
            eq(session.samsaraStory.mirrorHistoryCaptured, false, "onLoad不捕获镜像历史")
            eq(session.samsaraStory.mirrorHistoryVersion, 1, "独立镜像来源版本")
            for _ = 1, 5 do
                local story, supported = f.Schema.normalize(session)
                check(supported and story == session.samsaraStory, "normalize idempotent identity")
            end
            check(same(session, expected), "repeated normalize preserves all unknown/legacy fields")
            local missing = freshSession()
            local old = legacySession(missing)
            f[loader].applyOnLoad("session", missing)
            eq(missing.samsaraStory.schemaVersion, 1, loader .. " independently initializes missing new field")
            eq(missing.samsaraStory.historyCaptured, false, "onLoad does not infer clear history")
            check(same(legacySession(missing), old), "onLoad leaves old session unchanged")
            local future = freshSession()
            future.samsaraStory = { schemaVersion = 99, future = { noRepair = true }, nodes = false }
            local futureBefore = copy(future)
            f[loader].applyOnLoad("session", future)
            check(same(future, futureBefore), "future schema raw structure never repaired")
            local _, supported = f.Schema.normalize(future)
            eq(supported, false, "future schema unsupported")
        end)
    end
    runCase("strict normalization and history capture not inferred from maxStage", function()
        local f = fixture({ maxStageId = 999, currentStageId = 999, clearedStages = { [104] = "true" } })
        f.init()
        eq(f.Player.getRecord().status, "locked", "maxStage and truthy string do not grant N02")
        eq(f.session().samsaraStory.historyCaptured, true, "negative history still captured once")
        f.init({ clearedStages = { [104] = true } })
        eq(f.Player.getRecord().status, "locked", "later init never rescans repaired battle")
        eq(f.Player.onStageCleared(105), false, "unrelated live stage ignored")
        eq(f.Player.onStageCleared("104"), true, "explicit real clear grants only N02")
        eq(f.node().eligibilitySource, "live_clear", "live source distinguished from legacy scan")
        eq(f.Player.onStageCleared(104), false, "duplicate clear idempotent")
        local bad = { samsaraStory = { schemaVersion = 1, historyCaptured = "false",
            nodes = { [f.Config.NODE_KEY] = { eligible = "false", contentVersion = "1", resolution = "dismissed", custom = 3 } },
            evidence = { E01 = { unlocked = "true", source = 4, custom = 9 } } } }
        f.Schema.normalize(bad)
        eq(bad.samsaraStory.historyCaptured, false, "string false not captured")
        eq(bad.samsaraStory.nodes[f.Config.NODE_KEY].eligible, false, "string false not eligible")
        eq(bad.samsaraStory.nodes[f.Config.NODE_KEY].resolution, nil, "invalid persisted resolution not completed")
        eq(bad.samsaraStory.evidence.E01.unlocked, false, "string true not unlocked")
        eq(bad.samsaraStory.evidence.E01.custom, 9, "unknown evidence survives repair")
        local contentFuture = { samsaraStory = { schemaVersion = 1, historyCaptured = true,
            nodes = { [f.Config.NODE_KEY] = { contentVersion = 99, eligible = "future", resolution = "new", custom = 7 } }, evidence = {} } }
        local futureNode = copy(contentFuture.samsaraStory.nodes[f.Config.NODE_KEY])
        f.Schema.normalize(contentFuture)
        check(same(contentFuture.samsaraStory.nodes[f.Config.NODE_KEY], futureNode), "future node not rewritten")
    end)
    for _, hero in ipairs({ 1, 2, 3 }) do
        runCase("legacy branch " .. hero .. " note result without preclaim/rewards", function()
            local session = freshSession(); session.initialHeroId = hero; session.claimedScenarios = {}
            local f = fixture(nil, session); f.init()
            local old = legacySession(f.session())
            eq(f.Player.peekReady(), nil, "existing old branch must be consumed first")
            local id = hero == 1 and 17 or (hero == 2 and 18 or 19)
            eq(f.Player.noteLegacyResult(id + 20, "finished"), false, "wrong old id not accepted")
            eq(f.Player.noteLegacyResult(id, "reset"), false, "old reset does not unlock")
            eq(f.Player.noteLegacyResult(id, "skipped"), true, "live old skip source recorded")
            eq(f.node().legacyContext, "live_skipped", "live skipped distinguished from unknown claim")
            eq(f.Player.peekReady(), f.Config.NODE_KEY, "matching old result unlocks ready")
            noRewards(f, old, "legacy source")
        end)
    end
end

local function saveCases()
    for _, fault in ipairs({ "open", "write", "encode", "rename" }) do
        runCase("real Save.Flush " .. fault .. " failure / throttled Player retry / disk roundtrip", function()
            local f = fixture(); f.init()
            eq(f.Player.isSavePending(), false, "initial real save succeeded")
            check(type(f.disk) == "string", "baseline exists only in File boundary memory")
            local previousDisk, old = f.disk, legacySession(f.session())
            local oldModules = copy(f.Dispatcher.snapshotAll())
            local stateBefore = copy(f.gameState)
            eq(f.Playback.tryPlay(gates()), true, "actual display before fault")
            f.fail = fault
            local flushBefore, openBefore, renameBefore = f.n("flush"), f.n("openWrite"), f.n("rename")
            f.Dialogue.skip()
            eq(f.n("rename"), renameBefore + (fault == "rename" and 1 or 0), "Rename attempted only after complete temporary write")
            eq(f.temp, nil, "failed attempt cleans temporary buffer")
            eq(f.node().resolution, "skipped", "result retained in memory")
            eq(f.Player.isSavePending(), true, "real failed write must remain pending")
            eq(f.n("flush"), flushBefore + 1, "completion tries actual Flush once")
            eq(f.disk, previousDisk, "failure preserves previous disk bytes")
            if fault == "encode" then eq(f.n("openWrite"), openBefore, "encode exception never opens file")
            else eq(f.n("openWrite"), openBefore + 1, "actual File open boundary reached") end
            eq(f.Save.Flush(), false, "actual Flush propagates failure boolean")
            local retries = f.n("flush")
            f.Player.cancel() -- 取消租约不能清掉已完成但尚未落盘的结果
            f.Player.update(-1); f.Player.update(0 / 0); f.Player.update(math.huge); f.Player.update(0)
            f.Player.update(1.9)
            eq(f.n("flush"), retries, "invalid/subthreshold dt does not retry")
            f.Player.update(0.11)
            eq(f.n("flush"), retries + 1, "two-second threshold retries once")
            check(f.Player.isSavePending(), "retry failure still pending")
            f.Player.update(20)
            eq(f.n("flush"), retries + 2, "large dt does not loop multiple writes")
            local beforeRecovery = f.n("flush")
            f.fail = ""
            f.Player.update(1.9)
            eq(f.n("flush"), beforeRecovery, "failed retry reset interval")
            f.Player.update(0.11)
            eq(f.n("flush"), beforeRecovery + 1, "recovery retry once")
            eq(f.Player.isSavePending(), false, "only actual successful write clears pending")
            local saved = cjson.decode(assert(f.disk))
            eq(saved.modules.session.samsaraStory.nodes[f.Config.NODE_KEY].resolution, "skipped", "N02 survived actual encoded disk")
            eq(saved.modules.session.samsaraStory.evidence.E01.unlocked, true, "E01 eligibility persisted")
            check(same(legacySession(saved.modules.session), old), "every legacy field persisted")
            check(same(saved.gameState, stateBefore), "all GameState fields persisted")
            for _, name in ipairs({ "battle", "currency", "unknownModule" }) do
                check(same(saved.modules[name], oldModules[name]), "other old module intact " .. name)
            end
            noRewards(f, old, fault .. " recovered")
            local playerBeforeRestore = f.Player
            playerBeforeRestore.cancel()
            eq(f.Save.RestoreData(), true, "actual Save.RestoreData through File+cjson+Dispatcher")
            local restored = f.session()
            check(same(legacySession(restored), old), "disk restore retains all legacy session fields")
            eq(restored.samsaraStory.historyCaptured, true, "restore retains captured history")
            eq(f.init({ clearedStages = {} }), true, "restore init cannot rescan/remove prior history")
            eq(f.Player.getRecord().status, "skipped", "restored processed record")
            check(f.Player.getRecord().evidenceVisible, "restored E01 visible")
            eq(f.Player.peekReady(), nil, "restored processed not automatic first-read")
            eq(f.Save.Flush(), true, "actual Flush success boolean")
        end)
    end
    runCase("real Dispatcher preclaim JSON replacement preserves active lease via explicit session notification", function()
        local session = freshSession(); session.claimedScenarios = {}; session.scenarioRewardsGranted = {}
        local f = fixture(nil, session); f.init()
        assert(type(f.Player.onSessionUpdated) == "function", "missing explicit Player.onSessionUpdated integration API")
        eq(f.Player.noteLegacyResult(17, "finished"), true, "real old-log completion source")
        local lease = assert(f.Player.begin("samsara_first_read", f.Config.NODE_KEY))
        local before = f.session()
        local replacement = copy(before)
        replacement.claimedScenarios["17"] = true -- 旧preclaim真实payload形状；不执行领取/action
        local expectedOld = legacySession(replacement)
        f.Dispatcher.handleStateUpdate(cjson.encode({ modules = { session = replacement } }))
        check(f.session() ~= before, "real cjson dispatcher replaces session table")
        eq(f.Player.getRecord().status, "pending", "explicit same-game notification reattaches")
        eq(f.Player.onResult(resultFor(lease, "dismissed")), true, "in-flight exact lease survives legitimate publication")
        eq(f.Player.getRecord().status, "finished", "result reaches replacement session")
        noRewards(f, expectedOld, "JSON preclaim lease")
        local firstRead = copy(f.session().samsaraStory)
        eq(f.Player.requestRead(f.Config.NODE_KEY), true, "replay request queued after publication")
        local second = copy(f.session()); second.introCompleted = true
        f.Dispatcher.handleStateUpdate(cjson.encode({ modules = { session = second } }))
        local request = assert(f.Player.takeRequest())
        eq(request.kind, "samsara_replay", "same-game request survives second publication")
        check(same(f.session().samsaraStory, firstRead), "second JSON notification does not rescan or clear result")
        local replay = assert(f.Player.begin(request.kind, request.key))
        local newGame = freshSession(); newGame.samsaraStory = f.Schema.new()
        f.Dispatcher.handleStateUpdate(cjson.encode({ modules = { session = newGame } }))
        eq(f.Player.onResult(resultFor(replay, "finished")), false, "new uncaptured game notification cancels old lease")
        eq(f.session().samsaraStory.historyCaptured, false, "notification must never scan old battle")
    end)
end

local function bindInput(f, scale, dpr)
    local b = { calls = {}, cursor = { x = 0, y = 0 }, buttons = {}, clock = { elapsedTime = 100 },
        state = { offline = false, notice = false, armed = false, dragging = false },
        RT = { frameOx = 37, frameOy = 23, frameScale = scale or 0.8, dpr = dpr or 2 } }
    function b.record(name) b.calls[name] = (b.calls[name] or 0) + 1 end
    function b.n(name) return b.calls[name] or 0 end
    local function page(name, fields)
        local base = {}
        for _, method in ipairs({ "handleInput", "handleRightClick", "handleClick", "handleHover",
            "handleDragBegin", "handleDragMove", "handleDragEnd", "handleScroll", "close" }) do
            base[method] = function() b.record(name .. "." .. method); return false end
        end
        for key, value in pairs(fields or {}) do base[key] = value end
        return setmetatable(base, { __index = function() return function() return false end end })
    end
    local modules = {
        ["boot.StandaloneHorizonWheel"] = isolated("boot/StandaloneHorizonWheel.lua", {}),
        ["ui.story.ScenarioDialogue"] = f.Dialogue,
        ["ui.story.SamsaraRecordPanel"] = f.Panel,
        ["ui.hud.BottomNav"] = page("nav", { getSelectedIndex = function() return 3 end }),
        ["ui.hud.popup.OfflineRewardPanel"] = page("offline", { isOpen = function() return b.state.offline end }),
        ["ui.hud.popup.UpdateNoticePopup"] = page("notice", { isOpen = function() return b.state.notice end }),
        ["ui.character.panel.CharacterPanel"] = page("character", { isDraggingCard = function() return b.state.dragging end }),
        ["ui.character.EquipCrossDrag"] = page("cross", {
            isArmed = function() return b.state.armed end,
            cancel = function() b.state.armed = false; b.record("cross.cancel") end,
        }),
    }
    local vp = { DS = 0.45, PANELS = { center = { bx = 486, by = 0 } },
        getNote = function() return nil end,
        hit = function(x, y) return "center", x, y end }
    local overlay = page("offlineOverlay", { hasPress = function() return false end,
        toDesign = function(x, y) return x, y end })
    local realInput, env = isolated("boot/StandaloneHorizonInput.lua", modules, {
        input = {
            GetMousePosition = function() return b.cursor end,
            GetMouseButtonDown = function(_, button) return b.buttons[button] == true end,
        },
        time = b.clock,
    }, function(name)
        if not modules[name] then modules[name] = page(name) end
        return modules[name]
    end)
    b.Input, b.env = realInput, env
    realInput.bind({
        vg = function() return {} end,
        logicalW = function() return 1920 end, logicalH = function() return 1080 end,
        windowW = function() return 1920 end, windowH = function() return 1080 end,
        DESIGN_W = function() return 1080 end, DESIGN_H = function() return 2400 end,
        dpr = function() return b.RT.dpr end, bootReady_ = function() return true end,
        toDesign = function(x, y) return (x - b.RT.frameOx) / b.RT.frameScale, (y - b.RT.frameOy) / b.RT.frameScale end,
        talentPageUsesWideLayout = function() return false end,
        syncTalentPageLayout = function() end, talentPageRightEdge = function() return 486 end,
        equipOverlayDesign = function() return nil end, seamHitAt = function() return nil end,
        RT = b.RT, Viewport = vp, OfflineRewardOverlay = overlay,
    })
    function b.position(x, y)
        b.cursor.x = (b.RT.frameOx + x * b.RT.frameScale) * b.RT.dpr
        b.cursor.y = (b.RT.frameOy + y * b.RT.frameScale) * b.RT.dpr
    end
    local function integer(value) return { GetInt = function() return value end } end
    function b.invoke(name, event)
        assert(type(env[name]) == "function", "missing real Input handler " .. name)
        env[name](name, event or {})
    end
    function b.down(button)
        b.buttons[button] = true
        b.invoke("HandleMouseButtonDownHorizon", { Button = integer(button) })
    end
    function b.up(button)
        b.buttons[button] = false
        b.clock.elapsedTime = b.clock.elapsedTime + 0.2
        b.invoke("HandleMouseButtonUpHorizon", { Button = integer(button) })
    end
    function b.touch(id, x, y)
        return { TouchID = integer(id),
            X = integer(math.floor((b.RT.frameOx + x * b.RT.frameScale) * b.RT.dpr + 0.5)),
            Y = integer(math.floor((b.RT.frameOy + y * b.RT.frameScale) * b.RT.dpr + 0.5)) }
    end
    function b.wheel() b.invoke("HandleMouseWheelHorizon", { Wheel = integer(-2) }) end
    function b.noLower(label)
        local leaked = {}
        for name, count in pairs(b.calls) do
            if count > 0 and name ~= "cross.cancel" then leaked[#leaked + 1] = name .. "=" .. count end
        end
        eq(#leaked, 0, label .. " 模态不派发任何下层输入/领奖/滚轮/hover " .. table.concat(leaked, ","))
    end
    return b
end

local function inputCases()
    for _, dpr in ipairs({ 1, 2, 3 }) do
        runCase("真实Input切片down/up/右键/无down/DPR=" .. dpr, function()
            local f = fixture(); f.init()
            local old = legacySession(f.session())
            local b = bindInput(f, 0.8, dpr)
            eq(f.Playback.tryPlay(gates()), true, "真实切片已开始")
            f.Dialogue.update(100)
            local step = f.Dialogue.getProgress()
            b.position(960, 800)
            b.up(MOUSEB_LEFT)
            eq(f.Dialogue.getProgress(), step, "无down的up不推进")
            b.down(MOUSEB_RIGHT); b.up(MOUSEB_RIGHT)
            eq(f.Dialogue.getProgress(), step, "右键不推进")
            b.down(MOUSEB_LEFT)
            eq(f.Dialogue.getProgress(), step, "down只捕获不推进")
            eq(b.Input.isPointerBusy(), true, "真实按压门禁busy")
            b.up(MOUSEB_LEFT)
            eq(f.Dialogue.getProgress(), step + 1, "对应up恰推进一次")
            b.up(MOUSEB_LEFT)
            eq(f.Dialogue.getProgress(), step + 1, "重复up不推进")
            eq(b.Input.isPointerBusy(), false, "up释放busy")
            b.wheel(); b.invoke("HandleMouseMoveHorizon"); b.invoke("HandleEquipmentHoverTickHorizon")
            eq(f.Dialogue.getProgress(), step + 1, "wheel/hover不推进")
            b.noLower("切片鼠标")
            noRewards(f, old, "切片输入")
        end)
    end
    for _, kind in ipairs({ "mouse", "touch" }) do
        runCase("真实Input切片" .. kind .. "拖出回点与关闭后up", function()
            local f = fixture(); f.init()
            local b = bindInput(f)
            f.Playback.tryPlay(gates()); f.Dialogue.update(100)
            local step = f.Dialogue.getProgress()
            if kind == "mouse" then
                b.position(960, 800); b.down(MOUSEB_LEFT)
                b.position(1160, 800); b.invoke("HandleMouseMoveHorizon")
                b.position(960, 800); b.invoke("HandleMouseMoveHorizon"); b.up(MOUSEB_LEFT)
            else
                b.invoke("HandleTouchBeginHorizon", b.touch(11, 960, 800))
                b.invoke("HandleTouchMoveHorizon", b.touch(11, 1160, 800))
                b.invoke("HandleTouchMoveHorizon", b.touch(11, 960, 800))
                b.invoke("HandleTouchEndHorizon", b.touch(11, 960, 800))
            end
            eq(f.Dialogue.getProgress(), step, "拖出再回原点也不能tap")
            b.noLower("切片拖出回点")
            b.position(960, 800); b.down(MOUSEB_LEFT)
            f.Dialogue.reset()
            b.up(MOUSEB_LEFT)
            eq(f.Player.getRecord().status, "pending", "关闭后旧up不处理N02")
            b.noLower("切片reset后up")
        end)
    end
    runCase("真实touch切片捕获/副指/skip/离线覆盖共存", function()
        local f = fixture(); f.init()
        local b = bindInput(f, 0.8, 3)
        f.Playback.tryPlay(gates()); f.Dialogue.update(100)
        b.state.offline = true -- 已开始切片后出现奖励，绝不转走旧任意抬起advance
        local step = f.Dialogue.getProgress()
        b.position(0, 0)
        b.invoke("HandleTouchEndHorizon", b.touch(12, 1700, 130))
        eq(f.Dialogue.getProgress(), step, "共存离线时无down触摸up不推进/skip")
        eq(f.Player.getRecord().status, "pending", "共存离线无down不完成")
        b.invoke("HandleTouchBeginHorizon", b.touch(11, 960, 800))
        eq(b.Input.isPointerBusy(), true, "主指真实capture busy")
        b.invoke("HandleTouchBeginHorizon", b.touch(12, 1700, 130))
        b.invoke("HandleTouchMoveHorizon", b.touch(12, 1500, 130))
        b.invoke("HandleTouchEndHorizon", b.touch(12, 1700, 130))
        eq(f.Dialogue.getProgress(), step, "副指不得释放/推进主指")
        eq(f.Player.getRecord().status, "pending", "副指不得skip")
        b.invoke("HandleTouchEndHorizon", b.touch(11, 960, 800))
        eq(f.Dialogue.getProgress(), step + 1, "触摸真实X/Y经frame+DPR逆变换推进")
        eq(b.cursor.x, (37 + 0 * 0.8) * 3, "触摸不伪造鼠标位置")
        b.invoke("HandleTouchBeginHorizon", b.touch(13, 1700, 130))
        eq(f.Player.getRecord().status, "pending", "skip down不处理")
        b.invoke("HandleTouchEndHorizon", b.touch(13, 1700, 130))
        eq(f.Player.getRecord().status, "skipped", "真实skip区域up处理")
        b.noLower("共存离线切片touch")
    end)
    runCase("真实isPointerBusy门禁检查mouse按钮/touch不消费请求", function()
        local f = fixture(); f.init()
        local b = bindInput(f)
        eq(f.Player.requestRead(f.Config.NODE_KEY), true, "真实请求排队")
        local take, realShow = f.Player.takeRequest, f.Dialogue.show
        f.Player.takeRequest = function() f.count("input.request.take"); return take() end
        f.Dialogue.show = function(cfg) f.count("input.show"); return realShow(cfg) end
        for _, button in ipairs({ MOUSEB_LEFT, MOUSEB_RIGHT, MOUSEB_MIDDLE }) do
            b.buttons[button] = true
            eq(b.Input.isPointerBusy(), true, "真实button held门禁")
            local g = gates(); g.pointerBusy = b.Input.isPointerBusy()
            eq(f.Playback.tryPlay(g), false, "按下不能开始切片")
            b.buttons[button] = false
        end
        eq(f.n("input.request.take"), 0, "所有按键门禁不消费请求")
        eq(f.n("input.show"), 0, "所有按键门禁不show")
        b.state.notice = true -- 模态spy吞down，仍可验证独立touch id capture门禁
        b.invoke("HandleTouchBeginHorizon", b.touch(11, 960, 800))
        eq(b.Input.isPointerBusy(), true, "真实touch id busy")
        local g = gates(); g.pointerBusy = b.Input.isPointerBusy()
        eq(f.Playback.tryPlay(g), false, "触摸按下不能开始")
        eq(f.n("input.request.take"), 0, "触摸不消费请求")
        b.invoke("HandleTouchEndHorizon", b.touch(11, 960, 800))
        b.state.notice = false
        eq(b.Input.isPointerBusy(), false, "触摸up释放id门禁")
        eq(f.Playback.tryPlay(gates()), true, "释放后原请求正常展示")
        eq(f.n("input.request.take"), 1, "释放后只取一次")
    end)
    runCase("真实记录Panel draw/E01/保存禁用和Input模态吞", function()
        local f = fixture(); f.init()
        local b = bindInput(f)
        f.Panel.open(); f.Panel.draw({}, 1920, 1080)
        local text = table.concat(f.drawings, "\n")
        check(text:find("待阅", 1, true) ~= nil and not text:find(f.Config.get(f.Config.NODE_KEY).evidence.text, 1, true), "待阅Panel不泄露E01原文")
        b.position(100, 600); b.down(MOUSEB_RIGHT); b.up(MOUSEB_RIGHT)
        b.up(MOUSEB_LEFT); b.wheel(); b.invoke("HandleMouseMoveHorizon"); b.invoke("HandleEquipmentHoverTickHorizon")
        check(f.Panel.isOpen(), "模态遮罩/右键/无down/wheel不关闭")
        b.position(900, 500); b.down(MOUSEB_LEFT)
        b.position(1200, 600); b.invoke("HandleMouseMoveHorizon")
        b.position(900, 500); b.invoke("HandleMouseMoveHorizon"); b.up(MOUSEB_LEFT)
        check(f.Panel.isOpen(), "记录drag不派成按钮tap")
        b.noLower("记录模态")
        -- 1920x1080下真实布局action中心(1588,928)，仅夹具点位，不复制布局算法。
        b.position(1588, 928); b.down(MOUSEB_LEFT)
        check(f.Panel.isOpen() and not f.Dialogue.isActive(), "记录down不关窗、不show")
        b.up(MOUSEB_LEFT)
        check(not f.Panel.isOpen() and not f.Dialogue.isActive(), "记录up只排请求，N02不同步show")
        eq(f.Playback.tryPlay(gates()), true, "后帧仲裁才show")
        f.fail = "write"; f.Dialogue.skip()
        check(f.Player.isSavePending(), "真实write故障保存中")
        f.drawings = {}; f.Panel.open(); f.Panel.draw({}, 1920, 1080)
        text = table.concat(f.drawings, "\n")
        check(text:find("保存中", 1, true) ~= nil, "保存中按钮文案")
        check(text:find(f.Config.get(f.Config.NODE_KEY).evidence.text, 1, true) ~= nil, "已处理Panel展示真实E01普通原件")
        b.position(1588, 928); b.down(MOUSEB_LEFT); b.up(MOUSEB_LEFT)
        check(f.Panel.isOpen() and not f.Dialogue.isActive(), "保存中不能回看/关闭排队")
        eq(f.Player.takeRequest(), nil, "保存中按钮不排请求")
        f.fail = ""; f.Player.update(2)
        eq(f.Player.isSavePending(), false, "恢复落盘后回看可用")
        b.position(1588, 928); b.down(MOUSEB_LEFT); b.up(MOUSEB_LEFT)
        check(not f.Panel.isOpen() and not f.Dialogue.isActive(), "回看up仍只排队")
        local req = assert(f.Player.takeRequest())
        eq(req.kind, "samsara_replay", "记录回看仅排N02 replay")
        b.noLower("记录整个输入链")
    end)
end

-- 快捷键用私有 input 按键替身，真实 update 负责优先级；无关页面只计数边界动作。
local function bindKeyboard(f)
    local k = { keys = {}, calls = {}, helpPaint = 0 }
    local modules = {
        ["ui.story.SamsaraRecordPanel"] = f.Panel,
        ["ui.story.ScenarioDialogue"] = f.Dialogue,
    }
    local function page(name)
        local spy = {}
        for _, method in ipairs({ "open", "close", "hide", "show", "handleInput", "claim",
            "handleTap", "cycleBattleSpeed", "setSoundOn", "openPage" }) do
            spy[method] = function()
                local label = name .. "." .. method
                k.calls[label] = (k.calls[label] or 0) + 1
                return false
            end
        end
        return setmetatable(spy, { __index = function() return function() return false end end })
    end
    local globals = {
        input = {
            GetKeyPress = function(_, key) return k.keys[key] == true end,
            GetQualifierDown = function() return false end,
        },
        nvgBeginPath = function() k.helpPaint = k.helpPaint + 1 end,
    }
    -- 绘制仍走真实helpOpen分支，只替换无GPU底层函数；H若穿透能被观测。
    for _, name in ipairs({ "nvgFontFace", "nvgTextAlign", "nvgRoundedRect", "nvgFillColor",
        "nvgFill", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgFontSize", "nvgText" }) do
        globals[name] = function() end
    end
    k.Keyboard = isolated("ui/dev/KeyboardShortcuts.lua", modules, globals, function(name)
        if not modules[name] then modules[name] = page(name) end
        return modules[name]
    end)
    function k.press(key)
        k.keys = { [key] = true }
        k.Keyboard.update()
        k.keys = {}
    end
    function k.noLower(label)
        local count, details = 0, {}
        for name, value in pairs(k.calls) do
            count = count + value
            details[#details + 1] = name .. "=" .. value
        end
        eq(count, 0, label .. " 不打开下层/切倍速/领取/通知 " .. table.concat(details, ","))
    end
    return k
end

local function keyboardAndTerminalCases()
    local beforeAssertions, beforeFailures = assertions, failures
    runCase("真实快捷键记录模态I/B/F/H不穿透，ESC仅关闭记录", function()
        local f = fixture(); f.init()
        local old = legacySession(f.session())
        local k = bindKeyboard(f)
        f.Panel.open()
        for _, key in ipairs({ KEY_I, KEY_B, KEY_F, KEY_H }) do
            k.press(key)
            check(f.Panel.isOpen(), "记录模态快捷键不能关窗 key=" .. tostring(key))
            check(not f.Dialogue.isActive(), "记录快捷键不show key=" .. tostring(key))
            k.noLower("记录 key=" .. tostring(key))
        end
        k.Keyboard.draw({}, 1920, 1080)
        eq(k.helpPaint, 0, "记录H不打开真实快捷键帮助绘制分支")
        k.press(KEY_ESCAPE)
        eq(f.Panel.isOpen(), false, "ESC关闭真实记录Panel")
        k.noLower("记录ESC")
        noRewards(f, old, "记录键盘")
    end)
    runCase("真实快捷键切片I/B/F/H不穿透，space继续且ESC跳过", function()
        local f = fixture(); f.init()
        local old = legacySession(f.session())
        local k = bindKeyboard(f)
        eq(f.Playback.tryPlay(gates()), true, "真实切片开始供键盘输入")
        f.Dialogue.update(100)
        local step, flushBefore = f.Dialogue.getProgress(), f.n("flush")
        for _, key in ipairs({ KEY_I, KEY_B, KEY_F, KEY_H }) do
            k.press(key)
            eq(f.Dialogue.getProgress(), step, "切片字母键不推进 key=" .. tostring(key))
            check(f.Dialogue.isSliceActive(), "字母键保持切片租约 key=" .. tostring(key))
            k.noLower("切片 key=" .. tostring(key))
        end
        k.Keyboard.draw({}, 1920, 1080)
        eq(k.helpPaint, 0, "切片H不打开真实帮助绘制分支")
        k.press(KEY_SPACE)
        eq(f.Dialogue.getProgress(), step + 1, "space经真实快捷键推进一次")
        eq(f.Player.getRecord().status, "pending", "space翻页不提前标记完成")
        eq(f.n("flush"), flushBefore, "space翻页不保存处理结果")
        f.Dialogue.update(100)
        k.press(KEY_RETURN)
        eq(f.Dialogue.getProgress(), step + 2, "回车仍可经真实快捷键继续")
        k.press(KEY_ESCAPE)
        eq(f.Dialogue.isActive(), false, "ESC停止真实Dialogue")
        eq(f.Player.getRecord().status, "skipped", "ESC通过租约结果处理为skipped")
        check(f.Player.getRecord().evidenceVisible, "ESC处理后普通E01可见")
        k.noLower("切片space/return/ESC")
        noRewards(f, old, "切片键盘")
    end)
    runCase("真实终焉确认open和closing门禁均不消费N02请求", function()
        local f = fixture(); f.init()
        local old = legacySession(f.session())
        local clock = { elapsedTime = 100 }
        local terminal = isolated("ui/battle/popup/TerminalConfirmDialog.lua", {
            ["core.DarkIcon"] = {}, ["ui.battle.scene.BattleDraw"] = {},
            ["core.I18n"] = { lookup = function(text) return text end, format = function(text, ...) return string.format(text, ...) end },
        }, { time = clock })
        local confirmations = 0
        local take, show = f.Player.takeRequest, f.Dialogue.show
        f.Player.takeRequest = function() f.count("terminal.take"); return take() end
        f.Dialogue.show = function(cfg) f.count("terminal.show"); return show(cfg) end
        eq(terminal.isOpen(), false, "确认弹窗初始关闭")
        eq(f.Player.requestRead(f.Config.NODE_KEY), true, "N02真实请求排队")
        terminal.open(999)
        eq(terminal.isOpen(), true, "真实open立即门禁")
        local function blocked(label)
            local g = gates(); g.blocked = terminal.isOpen()
            eq(f.Playback.tryPlay(g), false, label .. " 实际isOpen禁止Playback")
            eq(f.n("terminal.take"), 0, label .. " 不take请求")
            eq(f.n("terminal.show"), 0, label .. " 不show")
            eq(f.Player.getRecord().status, "pending", label .. " 不处理N02")
        end
        blocked("open入场中")
        clock.elapsedTime = 100.3
        eq(terminal.handleInput(740, 1310, function() confirmations = confirmations + 1 end), true, "真实取消按钮进入closing")
        eq(terminal.isOpen(), true, "closing仍算门禁，不能只查open字段")
        blocked("closing刚开始")
        clock.elapsedTime = 100.49
        terminal.update()
        eq(terminal.isOpen(), true, "关闭动画阈值前仍门禁")
        blocked("closing阈值前")
        clock.elapsedTime = 100.51
        terminal.update()
        eq(terminal.isOpen(), false, "关闭动画完成才释放门禁")
        eq(confirmations, 0, "取消不调用进入终焉确认回调")
        local g = gates(); g.blocked = terminal.isOpen()
        eq(f.Playback.tryPlay(g), true, "门禁释放后原请求展示")
        eq(f.n("terminal.take"), 1, "释放后只取原请求一次")
        eq(f.n("terminal.show"), 1, "释放后只show一次")
        noRewards(f, old, "终焉确认仲裁")
    end)
    print(PREFIX .. "追加键盘/终焉门禁 assertions=" .. (assertions - beforeAssertions)
        .. " failures=" .. (failures - beforeFailures))
end

-- 新增征用链只复用上方真实模块fixture；不替换Player/Playback/Dialogue业务流程。
local CARGO, GRAY, PEOPLE = "samsara.cargo_match", "samsara.gray_order", "samsara.people_record"
local function cargoFixture(source)
    local session = freshSession()
    session.claimedScenarios = {} -- 无N02/旧73处理记录，仍可独立核验。
    return fixture({ maxStageId = 9999, currentStageId = 4905,
        clearedStages = source == "player_record" and { [4905] = true, [204] = true } or { [4905] = true } }, session)
end
local function cargoEvidence(f, key, id)
    for _, item in ipairs(f.Player.getRecord(key).evidences) do if item.id == id then return item end end
    return nil
end
local function cargoContent(f, key)
    f.drawings = {}
    f.Panel.selectRecord(key)
    f.Panel.open()
    f.Panel.draw({}, 1920, 1080)
    return table.concat(f.drawings, "\n")
end
local function includes(text, needle)
    return type(text) == "string" and text:find(needle, 1, true) ~= nil
end
local function cargoCases()
    local beforeAssertions, beforeFailures = assertions, failures
    for _, source in ipairs({ "player_record", "case_archive" }) do
        runCase("真实Playback/Dialogue三段串行/证据分层 source=" .. source, function()
            local f = cargoFixture(source); f.init()
            local old, shows, cfgs = legacySession(f.session()), 0, {}
            local show = f.Dialogue.show
            f.Dialogue.show = function(cfg)
                shows = shows + 1; cfgs[#cfgs + 1] = cfg
                eq(cfg.onFinish, nil, "征用链不安装领奖onFinish")
                eq(cfg.mode, "small", "真实征用切片small")
                check(type(cfg.onResult) == "function", "征用链只绑定精确结果回调")
                return show(cfg)
            end
            eq(f.Player.getRecord().status, "locked", "无raw104不借高max解锁N02")
            eq(f.Player.getRecord(CARGO).status, "pending", "raw4905成立但无旧73也可进入")
            eq(cargoEvidence(f, CARGO, "E02") ~= nil, source == "player_record", "case_archive不在init抢先造原件")
            eq(f.Playback.tryPlay(gates()), true, "后帧仲裁开始N12")
            eq(cfgs[1].completionToken.nodeKey, CARGO, "真实展示token为N12")
            local opening = {}
            for _, step in ipairs(cfgs[1].steps) do opening[#opening + 1] = step.text end
            check(includes(table.concat(opening, "\n"), source == "player_record" and "你带来的货牌" or "铁匠保存的货牌副本"), "真正送入Dialogue的是来源适配正文")
            eq(cargoEvidence(f, CARGO, "E02").source, source, "begin建立/保留正确来源")
            eq(cargoEvidence(f, CARGO, "E02").annotation, nil, "N12未处理无核验")
            finishDialogue(f.Dialogue)
            eq(f.Player.getRecord(CARGO).status, "pending", "dismiss动画完成前N12未处理")
            eq(f.Player.getRecord(GRAY).status, "locked", "动画完成前N13仍锁定")
            f.Dialogue.update(0.31)
            eq(f.Player.getRecord(CARGO).status, "finished", "真实dismissed映射finished")
            eq(f.Player.getRecord(GRAY).status, "pending", "N12释放N13")
            eq(shows, 1, "N12结果回调不递归show后段")
            eq(cargoEvidence(f, CARGO, "E02").annotation, f.Config.get(CARGO).evidence.annotation, "N12核验批注公开")
            eq(cargoEvidence(f, GRAY, "E05"), nil, "N12处理仍不公开E05")
            eq(f.Playback.tryPlay(gates()), true, "下一次宿主仲裁开始N13")
            eq(cfgs[2].completionToken.nodeKey, GRAY, "N13真实token")
            f.Dialogue.skip()
            eq(f.Player.getRecord(GRAY).status, "skipped", "真实skip不写finished")
            eq(f.Player.getRecord(PEOPLE).status, "pending", "N13skip释放N14")
            eq(shows, 2, "N13结果不递归showN14")
            local e05 = assert(cargoEvidence(f, PEOPLE, "E05"))
            eq(e05.text, f.Config.get(GRAY).evidence.text, "N13公开初始抄件")
            eq(e05.continuation, nil, "N13之后未处理N14不公开续令")
            eq(e05.people, nil, "N13之后不公开人员卷")
            eq(f.Playback.tryPlay(gates()), true, "后帧仲裁开始N14")
            eq(cfgs[3].completionToken.nodeKey, PEOPLE, "N14真实token")
            finishDialogue(f.Dialogue); f.Dialogue.update(0.31)
            eq(f.Player.getRecord(PEOPLE).status, "finished", "N14自然结束")
            eq(shows, 3, "精确三次首读展示")
            e05 = assert(cargoEvidence(f, PEOPLE, "E05"))
            eq(e05.continuation, f.Config.get(PEOPLE).evidence.continuation, "N14续令开放")
            eq(e05.people, f.Config.get(PEOPLE).evidence.people, "N14人员卷开放")
            check(not includes(e05.text .. e05.continuation .. e05.people, "本人承认一致"), "未接N17不提前定罪")
            eq(f.Playback.tryPlay(gates()), false, "全部处理后不自动重播")
            eq(f.Player.hasPendingRecords(), source == "player_record", "原cargo全处理后仅可信E02留下独立N03待阅")
            local saved = cjson.decode(assert(f.disk))
            eq(saved.modules.session.samsaraStory.cargoHistoryCaptured, true, "真实Save保留独立捕获标记")
            for _, key in ipairs({ CARGO, GRAY, PEOPLE }) do
                eq(saved.modules.session.samsaraStory.nodes[key].resolution, f.Player.getRecord(key).status, "真实磁盘保留首次结果 " .. key)
                local before, flushes = copy(f.session().samsaraStory), f.n("flush")
                eq(f.Player.requestRead(key), true, "三记录均可显式回看 " .. key)
                eq(f.Playback.tryPlay(gates()), true, "回看也走真实Playback " .. key)
                eq(cfgs[#cfgs].completionToken.kind, "samsara_replay", "回看kind不变首次")
                f.Dialogue.skip()
                check(same(f.session().samsaraStory, before), "回看不改原始结果/物证/来源 " .. key)
                eq(f.n("flush"), flushes, "回看不保存 " .. key)
            end
            noRewards(f, old, "征用三段/回看 " .. source)
        end)
    end
    for _, ending in ipairs({ "reset", "replaced", "failed" }) do
        runCase("真实N13中断不释放N14 " .. ending, function()
            local f = cargoFixture("player_record"); f.init()
            local old = legacySession(f.session())
            f.Playback.tryPlay(gates()); f.Dialogue.skip()
            local show, count = f.Dialogue.show, 0
            f.Dialogue.show = function(cfg)
                count = count + 1
                if ending == "failed" then return show({ steps = {} }) end
                return show(cfg)
            end
            eq(f.Playback.tryPlay(gates()), ending ~= "failed", "实际N13展示/失败")
            if ending == "reset" then f.Dialogue.reset()
            elseif ending == "replaced" then show({ mode = "small", steps = f.Config.get(CARGO).steps }) end
            eq(f.Player.getRecord(GRAY).status, "pending", "中断不写首次结果")
            eq(f.Player.getRecord(PEOPLE).status, "locked", "中断不解锁N14")
            eq(cargoEvidence(f, PEOPLE, "E05"), nil, "中断不公开E05初始或附页")
            eq(f.Player.requestRead(PEOPLE), false, "N14不可越过依赖")
            eq(count, 1, "失败/中断没有同步补播")
            show({ mode = "small", steps = f.Config.get(CARGO).steps })
            eq(f.Playback.tryPlay(gates()), false, "其他合法旧闲聊占用下一帧，新链等待")
            eq(f.Player.getRecord(GRAY).status, "pending", "旧show/broadcast不得误完成N13")
            f.Dialogue.skip() -- 无token旧段的广播不能释放新链。
            eq(f.Player.getRecord(PEOPLE).status, "locked", "旧完成广播不能解锁N14")
            f.Dialogue.show = show
            eq(f.Playback.tryPlay(gates()), true, "空闲下一帧从N13重新开始")
            f.Dialogue.skip()
            eq(f.Player.getRecord(PEOPLE).status, "pending", "只有真实N13重试skip才释放")
            noRewards(f, old, "中断恢复 " .. ending)
        end)
    end
    for _, fault in ipairs({ "open", "write", "encode", "rename" }) do
        runCase("征用N13真实Save失败/重启/节流恢复 " .. fault, function()
            local f = cargoFixture("player_record"); f.init()
            local old = legacySession(f.session())
            f.Playback.tryPlay(gates()); f.Dialogue.skip()
            local beforeDisk, renameBefore = assert(f.disk), f.n("rename")
            f.Playback.tryPlay(gates()); f.fail = fault; f.Dialogue.skip()
            eq(f.n("rename"), renameBefore + (fault == "rename" and 1 or 0), "征用仅完整临时写入后尝试Rename")
            eq(f.temp, nil, "征用失败清理临时缓冲")
            eq(f.Player.getRecord(GRAY).status, "skipped", "失败仍保留内存首次skip")
            eq(f.Player.getRecord(PEOPLE).status, "pending", "失败内存结果仍释放下一段")
            eq(f.Player.isSavePending(), true, "真实底层故障待保存")
            eq(f.disk, beforeDisk, "失败不改旧磁盘bytes")
            local lost = cjson.decode(beforeDisk).modules.session
            local reboot = cargoFixture("player_record")
            reboot.Dispatcher.set("session", lost); reboot.init({ clearedStages = {} })
            eq(reboot.Player.getRecord(CARGO).status, "skipped", "重启保留已成功保存N12")
            eq(reboot.Player.getRecord(GRAY).status, "pending", "失败重启从N13补读，不伪造已存")
            eq(reboot.Player.getRecord(PEOPLE).status, "locked", "失败重启不越过未保存N13")
            local attempts = f.n("flush")
            f.Player.update(1.99)
            eq(f.n("flush"), attempts, "节流阈值前无写盘轰炸")
            f.fail = ""; f.Player.update(0.02)
            eq(f.n("flush"), attempts + 1, "恢复后实际Flush一次")
            eq(f.Player.isSavePending(), false, "只有真实落盘成功清pending")
            local saved = cjson.decode(assert(f.disk))
            eq(saved.modules.session.samsaraStory.nodes[GRAY].resolution, "skipped", "恢复磁盘首次skip")
            eq(saved.modules.session.samsaraStory.cargoHistoryCaptured, true, "恢复保留新独立标记")
            eq(f.Save.RestoreData(), true, "经真实File/cjson/Dispatcher恢复")
            f.init({ clearedStages = {} })
            eq(f.Player.getRecord(GRAY).status, "skipped", "恢复成功后不重播N13")
            eq(f.Player.peekReady(), PEOPLE, "恢复成功后从N14继续")
            noRewards(f, old, "cargo真实保存恢复 " .. fault)
        end)
    end
    runCase("记录七标签中的旧五KEY选择只展示不播/批注分层/显式N12优先", function()
        local session = freshSession()
        local f = fixture({ clearedStages = { [104] = true, [4905] = true, [204] = true } }, session); f.init()
        local old, readCalls, before = legacySession(f.session()), 0, copy(f.session())
        local request = f.Player.requestRead
        f.Player.requestRead = function(key) readCalls = readCalls + 1; return request(key) end
        local keys = { f.Config.NODE_KEY, CARGO, GRAY, PEOPLE, f.Config.MANIFEST_KEY }
        for _, key in ipairs(keys) do
            local text = cargoContent(f, key)
            check(includes(text, f.Config.get(key).title), "KEY选中正确标题 " .. key)
            eq(readCalls, 0, "选择标签不调用requestRead " .. key)
            eq(f.Dialogue.isActive(), false, "选择标签不触show " .. key)
            check(same(f.session(), before), "选择标签不写状态 " .. key)
        end
        local text = cargoContent(f, CARGO)
        check(includes(text, f.Config.get(CARGO).evidence.text), "待阅N12已取得raw204原件可读")
        check(not includes(text, f.Config.get(CARGO).evidence.annotation), "待阅N12批注未公开")
        -- 新布局仍在同一右下action位置；标签选择不依赖布局私有字段。
        eq(f.Panel.handleInput(1588, 928, 1920, 1080), true, "点击N12待阅只排请求")
        eq(readCalls, 1, "action才调用一次requestRead")
        eq(f.Dialogue.isActive(), false, "Panel action不在回调内播")
        eq(f.Playback.tryPlay(gates()), true, "已解锁N12显式请求优先于自动N02")
        f.Dialogue.skip()
        eq(f.Player.getRecord().status, "pending", "读N12不代读N02")
        text = cargoContent(f, CARGO)
        check(includes(text, f.Config.get(CARGO).evidence.annotation), "N12处理后分区显示批注")
        f.Panel.close(); f.Player.requestRead(GRAY); f.Playback.tryPlay(gates()); f.Dialogue.skip()
        text = cargoContent(f, PEOPLE)
        check(includes(text, f.Config.get(GRAY).evidence.text), "N14待阅能看E05初始")
        check(not includes(text, f.Config.get(PEOPLE).evidence.continuation), "N14待阅续令不泄露")
        check(not includes(text, f.Config.get(PEOPLE).evidence.people), "N14待阅人员卷不泄露")
        f.Panel.close(); f.Player.requestRead(PEOPLE); f.Playback.tryPlay(gates()); f.fail = "write"; f.Dialogue.skip()
        text = cargoContent(f, PEOPLE)
        check(includes(text, f.Config.get(PEOPLE).evidence.continuation), "N14处理后续令显示")
        check(includes(text, f.Config.get(PEOPLE).evidence.people), "N14处理后人员卷显示")
        check(includes(text, "保存中"), "保存中Panel禁用回看")
        local queued = readCalls
        f.Panel.handleInput(1588, 928, 1920, 1080)
        eq(readCalls, queued, "保存中按钮不排回看")
        eq(f.Player.takeRequest(), nil, "保存中没有新请求")
        f.fail = ""; f.Player.update(2)
        eq(f.Player.isSavePending(), false, "成功后恢复回看")
        noRewards(f, old, "七标签中的旧五KEY展示/读取/保存中")
    end)
    runCase("N12显式请求在所有门禁保留，JSON合法重附不重扫", function()
        local f = cargoFixture("case_archive"); f.init()
        local old = legacySession(f.session())
        eq(f.Player.requestRead(CARGO), true, "N12请求排队")
        local take, takes = f.Player.takeRequest, 0
        f.Player.takeRequest = function() takes = takes + 1; return take() end
        for _, name in ipairs({ "ready", "legacyPending", "blocked", "pointerBusy" }) do
            local gate = gates(); gate[name] = name ~= "ready"
            eq(f.Playback.tryPlay(gate), false, "征用门禁不开始 " .. name)
            eq(takes, 0, "征用门禁不取请求 " .. name)
        end
        eq(f.Playback.tryPlay(gates()), true, "释放门禁只取原N12请求")
        eq(takes, 1, "放行一次取请求")
        local replacement = copy(f.session())
        f.Dispatcher.handleStateUpdate(cjson.encode({ modules = { session = replacement } }))
        f.Dialogue.skip()
        eq(f.Player.getRecord(CARGO).status, "skipped", "合法JSON重附精确租约结果写入新表")
        eq(f.Player.peekReady(), GRAY, "JSON重附保持串行下一段")
        eq(cargoEvidence(f, CARGO, "E02").source, "case_archive", "JSON往返保持首次来源")
        f.init({ clearedStages = { [204] = true, [104] = true } })
        eq(cargoEvidence(f, CARGO, "E02").source, "case_archive", "后续补true不反扫改来源")
        eq(f.Player.getRecord().status, "locked", "后续补true不反扫解锁N02")
        noRewards(f, old, "征用门禁/JSON重附")
    end)
    print(PREFIX .. "新增征用集成 assertions=" .. (assertions - beforeAssertions)
        .. " failures=" .. (failures - beforeFailures))
end

function Start()
    local ok, err = pcall(function()
        runCase("N02 real configuration only / independent return copies", function()
            local f = fixture()
            eq(f.Config.NODE_KEY, "samsara.log_leaf", "sole node key")
            local cfg = assert(f.Config.get(f.Config.NODE_KEY))
            eq(cfg.mode, "small", "N02 real small mode")
            eq(cfg.evidence.id, "E01", "sole ordinary evidence")
            eq(#cfg.steps, 7, "real N02 step count")
            eq(cfg.steps[2].characterId, 1, "dog identity")
            eq(cfg.steps[3].characterId, 2, "dragon identity")
            eq(cfg.steps[4].characterId, 3, "chicken identity")
            check(cfg.evidence.text:find("先救人，回来再结。", 1, true) ~= nil, "ordinary evidence exact content")
            eq(cfg.reward, nil, "no reward configuration")
            eq(cfg.scenarioId, nil, "not an old scenario identifier")
            eq(f.Config.get("unknown"), nil, "no additional node expansion")
            cfg.steps[1].text = "mutation"
            check(assert(f.Config.get(f.Config.NODE_KEY)).steps[1].text ~= "mutation", "return copy independent")
        end)
        dialogueCases()
        schemaCases()
        playbackCases()
        saveCases()
        inputCases()
        keyboardAndTerminalCases()
        cargoCases()
    end)
    if not ok then check(false, "Start exception: " .. tostring(err)) end
    print(PREFIX .. "RESULT cases=" .. passed .. "/" .. cases .. " assertions=" .. assertions .. " failures=" .. failures)
    if failures == 0 and cases > 0 and passed == cases then print(PREFIX .. "ALL PASS") end
    engine:Exit()
end
