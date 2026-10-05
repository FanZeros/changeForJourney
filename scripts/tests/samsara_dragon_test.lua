-- N08 龙没有打开的罐头：仅此文件新增，主会话统一运行 Runtime/build。
-- 复用 samsara_opening_test / samsara_mirror_test 的真实源码私有 load fixture。
-- Player/Config/Schema/Dispatcher/Save/Playback/Dialogue/Panel/Standalone/Boot 不复制业务逻辑。
-- File/经济/无关页面/GPU 全部内存替身；不碰真实档、require缓存或调试反射。
local PREFIX = "[samsara_dragon] "
local KEY, OPENING = "samsara.dragon_mirror", "samsara.opening_roster"
local DOG, BELL = "samsara.dog_mirror", "samsara.bell_mirror"
local FIRST, REPLAY, SOURCE = "samsara_first_read", "samsara_replay", "live_clear_2705"
local OLD_KEYS = { "samsara.log_leaf", "samsara.cargo_match", "samsara.gray_order", "samsara.people_record",
    "samsara.returned_manifest", DOG, BELL, OPENING }
local KEYS = { "samsara.log_leaf", "samsara.cargo_match", "samsara.gray_order", "samsara.people_record",
    "samsara.returned_manifest", DOG, BELL, OPENING, KEY, "samsara.nightmare_afterimage" }
local CHAIN = { "letter", "opening", "join.1", "join.2", "join.3" }
local B_TEXT = "我们说好胜利以后一起庆祝。\n留给三人的罐头，先别开。\n人不齐，我先等。\n申请人：黄桃龙〔旧登记页〕。\n答复：庆祝待交接。撤离未结。"
local STEPS = {
    { name = "旁白", text = "回忆·本次镜像遭遇的前夜。黄桃龙把名册旁那只罐头拿出来，将第三道浅刻痕补完。罐头仍未打开。" },
    { name = "旁白", text = "回到当前。镜像投影败退，当前页既有登记载体根据回声生成本地凭片。画中是一只未开罐的盒子，盖子同样有三道刻痕。图旁写着“胜利以后再开”，下方日期早于当前队出发。" },
    { characterId = 2, name = "黄桃龙", text = "我也有这样的盒子。" },
    { characterId = 1, name = "大狗嚼", text = "盒子能偷。叫！" },
    { characterId = 2, name = "黄桃龙", text = "可我昨天才把第三道划完。……我记得。" },
    { name = "远征长", text = "你昨天划的这只还在。先别拿那幅画改你的记性。" },
    { characterId = 3, name = "叮咚鸡", text = "你的盒子，留在你手里。她那只，先记在纸上。" },
    { characterId = 2, name = "黄桃龙", text = "她说“刚刚”拯救了世界。她会不会一直没等到庆祝？" },
}
local assertions, failures, cases, passed = 0, 0, 0, 0
local JSON = cjson
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
    if before == failures then passed = passed + 1; print(PREFIX .. "PASS " .. label) end
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
local function includes(text, needle) return type(text) == "string" and text:find(needle, 1, true) ~= nil end
local function outsideStory(session)
    local out = {}
    for key, value in pairs(session) do if key ~= "samsaraStory" then out[key] = copy(value) end end
    return out
end
local function oldPart(session)
    local story, out = session.samsaraStory, { nodes = {}, evidence = {} }
    for _, key in ipairs(OLD_KEYS) do out.nodes[key] = copy(story.nodes[key]) end
    for _, id in ipairs({ "E01", "E02", "E05", "E03-A", "E03-C", "unknown" }) do out.evidence[id] = copy(story.evidence[id]) end
    for _, field in ipairs({ "historyCaptured", "cargoHistoryCaptured", "mirrorHistoryCaptured", "mirrorHistoryVersion", "unknownStory" }) do
        out[field] = copy(story[field])
    end
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
---@param opening table|false|nil
---@return table
local function sessionWith(opening)
    ---@type table
    local session = {
        lastOnlineTime = 0, firstLoginTime = 100, initialHeroId = 1, introCompleted = true,
        hasReincarnated = true, firstGachaTenDone = true,
        claimedScenarios = { ["17"] = true, ["44"] = true, ["64"] = true, ["67"] = true, ["82"] = true },
        scenarioRewardsGranted = { ["17"] = true, ["44"] = true, ["64"] = true, ["67"] = true },
        offlineBonusCount = 2, offlineBonusDate = "2026-10-04",
        tutorialProgress = { completed = { ["1"] = true }, group = 8, step = 3, unknown = "keep" },
        introPlayback = { done = true, source = "legacy" }, unknownSession = { 7, false, "原值" },
        samsaraStory = { schemaVersion = 1, historyCaptured = true, cargoHistoryCaptured = true,
            mirrorHistoryCaptured = true, mirrorHistoryVersion = 1, dragonHistoryCaptured = true,
            dragonHistoryVersion = 1, nodes = {}, evidence = {}, unknownStory = { keep = 55 } },
    }
    if opening ~= false then session.samsaraStory.nodes[OPENING] = copy(opening or {
        eligible = true, contentVersion = 1, eligibilitySource = "live_opening_chain", resolution = "finished", unknown = { keep = 8 },
    }) end
    return session
end
local function oldArchive()
    local session = sessionWith()
    for index = 1, 7 do
        local key = OLD_KEYS[index]
        session.samsaraStory.nodes[key] = { eligible = true, contentVersion = 1,
            resolution = index % 2 == 0 and "skipped" or "finished", unknown = { keep = index },
            eligibilitySource = key == DOG and "live_clear_2505" or (key == BELL and "live_clear_2905" or "previous_processed"),
            legacyContext = "live_finished", manualOnly = key == "samsara.returned_manifest" }
    end
    session.samsaraStory.evidence = {
        E01 = { unlocked = true, source = "clear_104_legacy", unknown = { keep = 1 } },
        E02 = { unlocked = true, source = "player_record", annotationUnlocked = true, unknown = { keep = 2 } },
        E05 = { unlocked = true, source = "order_archive", continuationUnlocked = true, peopleUnlocked = true },
        ["E03-A"] = { unlocked = true, source = "live_clear_2505", unknown = { keep = 3 } },
        ["E03-C"] = { unlocked = true, source = "live_clear_2905", unknown = { keep = 4 } },
        unknown = { future = { false, "keep" } },
    }
    return session
end
local function result(lease, reason)
    return { playToken = lease.playToken, contextEpoch = lease.contextEpoch, nodeKey = lease.nodeKey, reason = reason }
end
local function gates(f) return { ready = true, legacyPending = false, blocked = f.Panel.isOpen(), pointerBusy = false } end

-- opening fixture的真实onLoad/Dispatcher/Save链，仅替换无关schema、File和经济边界。
---@return any
local function fixture(suppliedSession, raw, config, legacy, noInit)
    local f = { calls = {}, disk = "", temp = "", fail = "", flushMode = "real", shown = {}, font = 38 }
    function f.count(name) f.calls[name] = (f.calls[name] or 0) + 1 end
    function f.n(name) return f.calls[name] or 0 end
    f.Config = config or isolated("config/SamsaraSliceConfig.lua", {})
    f.Schema = isolated("shared/session/SamsaraStorySchema.lua", {})
    f.Legacy = legacy or isolated("config/ScenarioDialogueConfig.lua", {})
    f.SessionSchema = isolated("shared/session/SessionSchema.lua", { ["shared.session.SamsaraStorySchema"] = f.Schema })
    f.Registry = isolated("shared/ModuleRegistry.lua", {
        ["shared.session.SamsaraStorySchema"] = f.Schema,
        ["config.AwakeningConfig"] = isolated("config/AwakeningConfig.lua", {}),
        -- 宿主新建的装备模块为空；明确水合隔离边界，不允许Registry吞掉缺依赖异常。
        ["systems.EquipmentSystem"] = { hydrateInventory = function(inventory)
            f.count("boundary.hydrateEmpty"); check(type(inventory) == "table" and next(inventory) == nil, "隔离水合只接受空库存")
        end },
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
        ["shared.Protocol"] = {}, ["shared.ModuleRegistry"] = f.Registry, ["shared.schemas.CharacterSchema"] = f.Character,
    })
    f.Dispatcher.set("session", suppliedSession or sessionWith())
    f.Dispatcher.set("battle", { maxStageId = 9999, currentStageId = 101, clearedStages = {} })
    f.Dispatcher.set("currency", { gold = 123, gems = 456, unknown = "keep" })
    f.Dispatcher.set("opaqueModule", { value = { false, 9, "keep" } })
    f.gameState = { gold = 123, exp = 11, unknown = { keep = 42 } }
    local saveGlobals = {
        cjson = { encode = function(value)
            f.count("encode"); if f.fail == "encode" then error("injected encode failure") end
            return JSON.encode(value)
        end, decode = function(value) return JSON.decode(value) end },
        fileSystem = {
            FileExists = function(_, path)
                eq(path, "standalone_save.json", "only query committed memory file"); return f.disk ~= ""
            end,
            Rename = function(_, from, to)
                f.count("rename")
                eq(from, "standalone_save.pending.json", "atomic memory source")
                eq(to, "standalone_save.json", "atomic memory target")
                if f.fail == "rename" or not f.written or not f.closed then return false end
                f.disk, f.temp, f.written, f.closed = f.temp, "", false, false
                return true
            end,
            Delete = function(_, path)
                eq(path, "standalone_save.pending.json", "never delete committed memory file")
                f.temp, f.written, f.closed = "", false, false; return true
            end,
        },
        File = function(path, mode)
            eq(path, mode == FILE_WRITE and "standalone_save.pending.json" or "standalone_save.json", "File boundary memory only")
            f.count(mode == FILE_WRITE and "openWrite" or "openRead")
            local opened = not (mode == FILE_WRITE and f.fail == "open")
            if mode == FILE_WRITE and opened then f.temp, f.written, f.closed = "", false, false end
            return { IsOpen = function() return opened end,
                WriteString = function(_, data)
                    f.count("write"); if not opened or f.fail == "write" then return false end
                    f.temp, f.written = data, true; return true
                end,
                ReadString = function() return f.disk end,
                Close = function() if mode == FILE_WRITE and opened then f.closed = true end end }
        end,
    }
    f.Save = isolated("boot/StandaloneSave.lua", {
        ["runtime.ClientDispatcher"] = f.Dispatcher,
        ["core.GameState"] = { exportSave = function() return f.gameState end,
            importSave = function(value) f.gameState = value end, syncPlayerData = function() f.count("restore.sync") end },
        ["ui.battle.scene.BattleScene"] = { setBattleData = function() f.count("restore.battle") end },
        ["rules.offline.OfflineService"] = { HasPendingRewards = function() return false end,
            MarkOnline = function() f.count("save.markOnline") end },
    }, saveGlobals)
    local deps = { ["config.SamsaraSliceConfig"] = f.Config, ["shared.session.SamsaraStorySchema"] = f.Schema,
        ["config.ScenarioDialogueConfig"] = f.Legacy }
    f.forbidden = {}
    for _, name in ipairs({ "runtime.GameAction", "runtime.ClientMessageHandler", "rules.character.PlayerDataManager",
        "systems.TutorialManager", "systems.StoryPlayer" }) do
        local spy = setmetatable({}, { __index = function(_, method)
            return function() f.count("forbidden." .. name .. "." .. tostring(method)); return false end
        end })
        deps[name], f.forbidden[name] = spy, spy
    end
    f.Player = isolated("systems/SamsaraSlicePlayer.lua", deps)
    f.Dispatcher.subscribe("session", f.Player.onSessionUpdated)
    f.options = { getSession = function() return f.Dispatcher.get("session") end,
        setSession = function(value)
            f.count("session.set"); eq(value, f.Dispatcher.get("session"), "shared session identity")
            if f.fail == "set" then error("injected set failure") end
            f.Dispatcher.set("session", value)
        end,
        flush = function()
            f.count("flush")
            if f.flushMode == "false" then return false end
            if f.flushMode == "nil" then return nil end
            if f.flushMode == "throw" then error("injected Flush failure") end
            return f.Save.Flush()
        end }
    function f.session() return assert(f.Dispatcher.get("session")) end
    function f.node() return f.session().samsaraStory.nodes[KEY] end
    function f.record() return f.Player.getRecord(KEY) end
    function f.init(battle) return f.Player.init(f.options, battle or raw or {}) end
    function f.publish(value) f.Dispatcher.handleStateUpdate(JSON.encode({ modules = { session = value } })) end
    -- mirror显示fixture：GPU测量替身，真实UTF-8/StoryDisplay/Dialogue折行与计时。
    f.displayed, f.drawings, f.boxes, f.tabs, f.buttons = {}, {}, {}, {}, {}
    f.graphics = { cache = { GetResource = function() return nil end },
        nvgCreateImage = function() f.count("gpu.image"); return -1 end,
        nvgRGBA = function() return {} end, nvgFontSize = function(_, size) f.font = size end,
        nvgText = function(_, _, _, text) f.drawings[#f.drawings + 1] = text; return text end,
        nvgTextBoxBounds = function(_, _, _, width, text)
            local lines = 0
            for line in (text .. "\n"):gmatch("(.-)\n") do
                lines = lines + math.max(1, math.ceil((utf8.len(line) or 0) * f.font / math.max(1, width)))
            end
            return { 0, 0, width, lines * f.font * 1.5 }
        end,
        nvgTextBox = function(_, x, y, _, text)
            f.drawings[#f.drawings + 1] = text; f.boxes[#f.boxes + 1] = { x = x, y = y, text = text }
        end }
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgIntersectScissor", "nvgScale", "nvgFontFace", "nvgTextAlign",
        "nvgTextLineHeight", "nvgFillColor", "nvgScissor", "nvgTranslate", "nvgBeginPath", "nvgRect", "nvgFill",
        "nvgRoundedRect", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgResetScissor" }) do
        f.graphics[name] = function() end
    end
    f.I18n = { get = function() return "zh_CN" end, lookup = function(text) return text end, installDrawHook = function() end,
        displayBounds = function(_, _, _, text) return (utf8.len(text) or 0) * f.font end,
        displayText = function(_, _, _, text) f.displayed[#f.displayed + 1] = text; return text end }
    f.Story = isolated("core/I18nStory.lua", {})
    f.Display = isolated("ui/story/StoryDisplay.lua", { ["core.I18n"] = f.I18n, ["core.I18nStory"] = f.Story }, f.graphics)
    f.Bus = isolated("core/EventBus.lua", {})
    f.GameConfig = isolated("config/GameConfig.lua", {})
    f.Draw = { hitTest = function(x, y, cx, cy, w, h) return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5 end,
        drawTextStroke = function(_, x, y, text)
            f.drawings[#f.drawings + 1] = text; f.buttons[#f.buttons + 1] = { x = x, y = y, text = text }
        end, drawRoundedRectCentered = function() end, drawImageCover = function() end, initShardAssets = function() end }
    f.Dialogue = isolated("ui/story/ScenarioDialogue.lua", {
        ["core.DrawUtil"] = f.Draw, ["config.GameConfig"] = f.GameConfig, ["ui.widget.HeroFrame"] = {},
        ["core.EventBus"] = f.Bus, ["core.I18n"] = f.I18n, ["core.I18nStory"] = f.Story,
        ["ui.story.StoryDisplay"] = f.Display, ["config.ScenarioDialogueConfig"] = f.Legacy, ["config.HeroAssetUtil"] = {},
    }, f.graphics)
    f.realShow = f.Dialogue.show
    f.Dialogue.show = function(cfg)
        f.shown[#f.shown + 1] = cfg
        if f.showFault == "throw" then error("injected presentation failure") end
        if f.showFault == "false" then return f.realShow({ steps = {} }) end
        return f.realShow(cfg)
    end
    local playDeps = { ["systems.SamsaraSlicePlayer"] = f.Player, ["config.SamsaraSliceConfig"] = f.Config,
        ["ui.story.ScenarioDialogue"] = f.Dialogue }
    for name, spy in pairs(f.forbidden) do playDeps[name] = spy end
    f.Playback = isolated("systems/SamsaraSlicePlayback.lua", playDeps)
    f.Panel = isolated("ui/story/SamsaraRecordPanel.lua", { ["core.DrawUtil"] = f.Draw,
        ["systems.SamsaraSlicePlayer"] = f.Player,
        ["core.DarkIcon"] = { draw = function() end, drawNine = function(_, name, x, y, w, h)
            if name == "btn" and h == 64 then f.tabs[#f.tabs + 1] = { x = x + w * 0.5, y = y + h * 0.5, width = w } end
        end } }, f.graphics)
    function f.draw(w, h)
        f.drawings, f.boxes, f.tabs, f.buttons = {}, {}, {}, {}
        f.Panel.draw({}, w or 1920, h or 1080); return table.concat(f.drawings, "\n")
    end
    function f.action(text)
        for _, button in ipairs(f.buttons) do if button.text == text and button.y > 800 then return button end end
        error("missing action " .. text)
    end
    if not noInit then f.supported = f.init(raw) end
    return f
end
local function noRewards(f, outside, label)
    for name, count in pairs(f.calls) do if name:match("^forbidden%.") then eq(count, 0, label .. " no " .. name) end end
    check(same(outsideStory(f.session()), outside), label .. " old session/claimed/granted/tutorial/offline unchanged")
    eq(f.Dispatcher.get("currency").gold, 123, label .. " currency unchanged")
    eq(f.gameState.gold, 123, label .. " GameState unchanged")
end
local function hidden(f, label)
    eq(f.record().evidenceVisible, false, label .. " no B visible")
    eq(f.record().evidence, nil, label .. " no B public object")
    eq(#f.record().evidences, 0, label .. " no cross-node evidence")
    eq(f.session().samsaraStory.evidence["E03-B"], nil, label .. " no B awarded")
end
local function reference(f, label)
    eq(f.record().referenceOnly, true, label .. " reference-only")
    check(f.record().status ~= "finished" and f.record().status ~= "skipped", label .. " not fake read")
    eq(f.Player.requestRead(KEY), false, label .. " cannot request")
    eq(f.Player.begin(FIRST, KEY), nil, label .. " cannot first-read")
    eq(f.Player.begin(REPLAY, KEY), nil, label .. " cannot replay")
    local spoken = {}
    for _, step in ipairs(f.record().referenceSteps or {}) do if step.name ~= "旁白" then spoken[#spoken + 1] = step end end
    eq(#spoken, 6, label .. " six reference lines accessible")
    for index = 1, 6 do check(same(spoken[index], STEPS[index + 2]), label .. " verbatim reference " .. index) end
    hidden(f, label)
end
local function legacy(f, reason)
    return f.Player.noteLegacyResult(65, reason or "finished", f.Player.getContextEpoch())
end
local function live(f, reason, legacyFirst)
    if legacyFirst then eq(legacy(f, reason), true, "independent old65 before CLEAR") end
    eq(f.Player.onStageCleared(2705), true, "real CLEAR only grants eligible")
    eq(f.node().eligible, true, "real eligible")
    eq(f.node().eligibilitySource, SOURCE, "exact live source")
    hidden(f, "unread CLEAR")
    if not legacyFirst then eq(legacy(f, reason), true, "independent old65 after CLEAR") end
end
local function finish(f, reason, key)
    local lease = assert(f.Player.begin(FIRST, key or KEY), "missing real first-read lease")
    eq(f.Player.onResult(result(lease, reason or "finished")), true, "accepted current first-read")
    return lease
end
local function finishOpening(f, reason)
    local epoch = assert(f.Player.beginOpening(), "real opening chain required")
    for index, step in ipairs(CHAIN) do eq(f.Player.noteOpeningResult(step, "skipped", epoch), index == #CHAIN, "ordered opening " .. step) end
    finish(f, reason or "skipped", OPENING)
end
local function finishDialogue(dialogue)
    local _, total = dialogue.getProgress()
    for _ = 1, total do dialogue.update(100); dialogue.advance() end
end

local function configurationCases()
    runCase("exact ninth key/text/front-night chronology/copies", function()
        local cfg = isolated("config/SamsaraSliceConfig.lua", {})
        eq(cfg.DRAGON_MIRROR_KEY, KEY, "DRAGON_MIRROR_KEY")
        check(same(cfg.KEYS, KEYS), "旧九KEY严格前缀，N11仅追加第十")
        eq(cfg.get("N08"), nil, "planner id not module key")
        local node = assert(cfg.get(KEY))
        eq(node.title, "龙没有打开的罐头", "N08 exact title")
        eq(node.mode, "small", "N08 small")
        eq(node.requiredStage, 2705, "N08 real-clear anchor")
        eq(node.dependency, OPENING, "N01 only dependency")
        check(same(node.steps, STEPS), "two narrator frames plus original six verbatim/portraits/order")
        eq(#node.steps, 8, "exact eight steps")
        check(includes(node.steps[1].text, "本次镜像遭遇的前夜"), "not initial departure or real-day wait")
        eq(node.scarCompleted, nil, "no fabricated scar flag")
        eq(node.evidence.id, "E03-B", "own B only")
        eq(node.evidence.text, B_TEXT, "five-line request verbatim")
        for _, field in ipairs({ "scenarioId", "reward", "rewards", "onFinish", "cg", "cgPath" }) do eq(node[field], nil, "no " .. field) end
        for _, step in ipairs(node.steps) do
            for _, field in ipairs({ "scenarioId", "reward", "rewards", "cg", "cgPath" }) do eq(step[field], nil, "step no " .. field) end
        end
        for _, field in ipairs({ "annotation", "continuation", "people", "reward", "rewards", "scenarioId" }) do
            eq(node.evidence[field], nil, "B no future field " .. field)
            eq(cfg.getEvidence("E03-B")[field], nil, "B getter no " .. field)
        end
        node.steps[1].text, node.evidence.text, node.dependency = "UI mutation", "UI mutation", DOG
        check(same(cfg.get(KEY).steps, STEPS), "steps deep-copy")
        eq(cfg.getEvidence("E03-B").text, B_TEXT, "evidence deep-copy")
        eq(cfg.get(KEY).dependency, OPENING, "dependency copy")
        local evidence = cfg.getEvidence("E03-B"); evidence.text = "mutated getter"
        eq(cfg.get(KEY).evidence.text, B_TEXT, "getEvidence copy does not pollute get")
        eq(cfg.get(DOG).dependency, nil, "A not given opening prerequisite")
        eq(cfg.get(BELL).dependency, nil, "C not given opening prerequisite")
        eq(cfg.get(OPENING).evidence, nil, "N01 stays evidence-free")
        local f = fixture(nil, nil, nil, nil, true)
        eq(#f.Player.getRecords(), 10, "未init十条记录安全返回")
        for index, record in ipairs(f.Player.getRecords()) do eq(record.key, KEYS[index], "actual record order " .. index) end
        eq(f.Player.getRecord().key, OLD_KEYS[1], "default record remains N02")
        eq(f.Player.onStageCleared(2705), false, "uninitialized CLEAR safe")
        eq(legacy(f), false, "uninitialized legacy bridge safe")
        eq(f.Player.requestRead(KEY), false, "uninitialized read safe")
        eq(f.Player.begin(FIRST, KEY), nil, "uninitialized lease safe")
        f.Player.cancel(); f.Player.update(2); eq(f.n("flush"), 0, "uninitialized never writes")
    end)
end

local function historyCases()
    for _, numeric in ipairs({ true, false }) do
        runCase("raw2705 independent capture despite old mirror captured " .. tostring(numeric), function()
            local session = oldArchive()
            session.samsaraStory.dragonHistoryCaptured, session.samsaraStory.dragonHistoryVersion = nil, nil
            local old, outside = oldPart(session), outsideStory(session)
            local f = fixture(session, { clearedStages = { [numeric and 2705 or "2705"] = true }, maxStageId = 9999, currentStageId = 2705 })
            eq(session.samsaraStory.dragonHistoryCaptured, true, "dragon capture completed")
            eq(session.samsaraStory.dragonHistoryVersion, 1, "dragon version1")
            eq(f.node().eligibilitySource, "legacy_raw_clear_unknown", "raw not live")
            check(f.node().eligible ~= true, "raw not eligible")
            reference(f, "raw unknown")
            eq(f.Player.peekReady(), nil, "raw not auto")
            eq(f.Player.hasPendingRecords(), false, "raw no red dot")
            check(same(oldPart(session), old), "migration preserves A/C/N01 and old five")
            noRewards(f, outside, "raw capture")
            local before, flushes = copy(session), f.n("flush")
            f.init({ clearedStages = { [2705] = true, [2505] = true, [2905] = true } })
            check(same(session, before), "second init no rescan")
            eq(f.n("flush"), flushes, "second init no save")
            local reboot = fixture(JSON.decode(f.disk).modules.session, { clearedStages = { [2705] = true } })
            reference(reboot, "JSON raw reference")
            eq(legacy(reboot, "skipped"), true, "independent old65 may be recorded")
            reference(reboot, "raw plus genuine old result still unknown battle")
            eq(reboot.Player.onStageCleared(2705), true, "only genuine CLEAR upgrades raw")
            eq(reboot.node().eligibilitySource, SOURCE, "upgrade source")
            eq(reboot.node().legacyContext, "live_skipped", "upgrade retains old actual skip")
            eq(reboot.record().referenceOnly, nil, "trusted sources and N01 open pending")
            hidden(reboot, "upgrade not read")
        end)
    end
    for _, value in ipairs({ false, "true", "false", 1, 0 }) do
        runCase("negative dragon capture strict true never rescan " .. tostring(value), function()
            local session = sessionWith(); session.claimedScenarios["65"] = true
            session.samsaraStory.dragonHistoryCaptured = false
            local f = fixture(session, { maxStageId = 9999, currentStageId = 2705, clearedStages = { [2705] = value } })
            check(not f.node() or f.node().eligibilitySource ~= "legacy_raw_clear_unknown", "only boolean true recognized")
            reference(f, "claimed/max/current/value not event")
            eq(session.samsaraStory.dragonHistoryCaptured, true, "negative capture persisted")
            local once, flushes = copy(session), f.n("flush")
            f.init({ clearedStages = { [2705] = true } })
            check(same(session, once), "negative same-table capture not rescan")
            eq(f.n("flush"), flushes, "negative re-init no write")
            local reboot = fixture(JSON.decode(f.disk).modules.session, { clearedStages = { [2705] = true } })
            reference(reboot, "negative JSON capture not rescan")
        end)
    end
    runCase("malformed raw keys and captured dragon cannot borrow uncaptured mirror domain", function()
        local f = fixture(sessionWith(), { clearedStages = { ["02705"] = true, ["2705.0"] = true, ["2705x"] = true, [2704] = true } })
        reference(f, "malformed raw keys")
        f.session().samsaraStory.mirrorHistoryCaptured = false
        f.init({ clearedStages = { [2705] = true, [2505] = true } })
        reference(f, "old mirror capture cannot overwrite dragon negative")
        eq(f.session().samsaraStory.nodes[DOG].eligibilitySource, "legacy_raw_clear_unknown", "A own capture still works")
    end)
end

local function prerequisiteCases()
    local variants = {
        { label = "absent", node = false },
        { label = "trusted pending", node = { eligible = true, contentVersion = 1, eligibilitySource = "live_opening_chain" } },
        { label = "unknown source finished", node = { eligible = true, contentVersion = 1, resolution = "finished", eligibilitySource = "legacy_claimed_unknown" } },
        { label = "wrong live source skipped", node = { eligible = true, contentVersion = 1, resolution = "skipped", eligibilitySource = "live_clear" } },
        { label = "string eligible", node = { eligible = "true", contentVersion = 1, resolution = "finished", eligibilitySource = "live_opening_chain" } },
        { label = "ineligible", node = { eligible = false, contentVersion = 1, resolution = "skipped", eligibilitySource = "live_opening_chain" } },
        { label = "unprocessed reason", node = { eligible = true, contentVersion = 1, resolution = "dismissed", eligibilitySource = "live_opening_chain" } },
    }
    for _, variant in ipairs(variants) do
        for _, reason in ipairs({ "finished", "skipped", "reset" }) do
            runCase("N01 gate cannot be bypassed " .. variant.label .. "/" .. reason, function()
                local f = fixture(sessionWith(variant.node))
                local openingBefore, outside = copy(f.session().samsaraStory.nodes[OPENING]), outsideStory(f.session())
                live(f, reason, true)
                eq(f.node().eligible, true, "N01 gate does not discard independent live qualification")
                reference(f, "N01 prerequisite")
                check(f.Player.peekReady() ~= KEY, "N08 not auto without processed trusted N01")
                check(same(f.session().samsaraStory.nodes[OPENING], openingBefore), "N08 events do not manufacture N01")
                noRewards(f, outside, "N01 gate")
            end)
        end
    end
    for _, openingReason in ipairs({ "finished", "skipped" }) do
        for _, legacyReason in ipairs({ "finished", "dismissed", "skipped" }) do
            for _, order in ipairs({ "opening-clear-legacy", "opening-legacy-clear", "legacy-clear-opening", "legacy-opening-clear", "clear-opening-legacy", "clear-legacy-opening" }) do
                runCase("three independent prerequisites order " .. order .. "/" .. openingReason .. "/" .. legacyReason, function()
                    local f = fixture(sessionWith(false))
                    local outside, evidence = outsideStory(f.session()), copy(f.session().samsaraStory.evidence)
                    for part in order:gmatch("[^-]+") do
                        if part == "opening" then finishOpening(f, openingReason)
                        elseif part == "clear" then eq(f.Player.onStageCleared(2705), true, "independent real clear")
                        else eq(legacy(f, legacyReason), true, "independent real old65") end
                        hidden(f, "prerequisite registration alone")
                    end
                    eq(f.record().status, "pending", "all prerequisites pending not read")
                    eq(f.record().referenceOnly, nil, "all prerequisites no longer reference")
                    eq(f.record().eventTrusted, true, "all prerequisites trusted")
                    eq(f.Player.peekReady(), KEY, "all prerequisites ready")
                    eq(f.Player.hasPendingRecords(), true, "trusted pending visible")
                    eq(f.node().legacyContext, legacyReason == "skipped" and "live_skipped" or "live_finished", "exact old65 context")
                    check(same(f.session().samsaraStory.evidence, evidence), "prerequisites award no B")
                    finish(f, "skipped")
                    eq(f.record().evidence.text, B_TEXT, "only N08 processed awards B")
                    eq(f.session().samsaraStory.nodes[OPENING].resolution, openingReason, "N01 first result stays separate")
                    noRewards(f, outside, "ordered prerequisites")
                end)
            end
        end
    end
    runCase("old65 only and CLEAR only do not supply the other source", function()
        local oldOnly = fixture(); eq(legacy(oldOnly), true, "old65 may precede CLEAR")
        reference(oldOnly, "old65 without CLEAR")
        eq(oldOnly.Player.peekReady(), nil, "old65 not success")
        local clearOnly = fixture(); eq(clearOnly.Player.onStageCleared("2705"), true, "exact string real CLEAR")
        reference(clearOnly, "CLEAR without old65")
        eq(clearOnly.Player.peekReady(), nil, "CLEAR not old encounter handling")
        clearOnly.session().claimedScenarios["65"] = true; clearOnly.init()
        reference(clearOnly, "preclaimed is not true old result")
        eq(legacy(clearOnly), true, "actual old bridge upgrades unknown context")
        eq(clearOnly.Player.peekReady(), KEY, "actual bridge now ready")
    end)
    runCase("legacy64/67 and CLEAR2505/2905 cannot lend N08 either source", function()
        for _, kind in ipairs({ "foreign old results", "foreign CLEAR" }) do
            local f = fixture(sessionWith(false))
            if kind == "foreign old results" then
                eq(f.Player.onStageCleared(2705), true, "own CLEAR registered")
                for _, id in ipairs({ 64, 67 }) do eq(f.Player.noteLegacyResult(id, "skipped", f.Player.getContextEpoch()), true, "foreign old result independent") end
                finishOpening(f)
                reference(f, "foreign old results not65")
            else
                eq(legacy(f), true, "own65 registered")
                for _, stage in ipairs({ 2505, 2905 }) do eq(f.Player.onStageCleared(stage), true, "foreign CLEAR independent") end
                finishOpening(f)
                reference(f, "foreign CLEAR not2705")
            end
            check(f.Player.peekReady() ~= KEY, "foreign source cannot make N08 ready")
        end
    end)
    for _, fault in ipairs({ "missing", "empty", "throw", "bad evidence" }) do
        runCase("missing or malformed N08 config cannot manufacture B " .. fault, function()
            local cfg = isolated("config/SamsaraSliceConfig.lua", {})
            local get = cfg.get
            cfg.get = function(key, source)
                if key ~= KEY then return get(key, source) end
                if fault == "throw" then error("injected N08 config failure") end
                if fault == "missing" then return nil end
                local definition = get(key, source)
                if fault == "empty" then definition.steps = {} else definition.evidence = nil end
                return definition
            end
            local f = fixture(nil, nil, cfg)
            local outside = outsideStory(f.session())
            eq(f.Player.onStageCleared(2705), false, "bad config no live eligibility")
            eq(legacy(f), false, "bad config no old65 registration")
            eq(f.Player.requestRead(KEY), false, "bad config no request")
            eq(f.Player.begin(FIRST, KEY), nil, "bad config no lease")
            eq(f.Playback.tryPlay(gates(f)), false, "bad config no show")
            hidden(f, "bad config")
            noRewards(f, outside, "bad config")
        end)
    end
    runCase("strict old65 reason/id/epoch and stale identity", function()
        local f = fixture(); f.Player.onStageCleared(2705)
        local before, writes = copy(f.session()), f.n("flush")
        for _, id in ipairs({ "065", "65.0", "65x", 66, 73, false }) do eq(f.Player.noteLegacyResult(id, "finished", f.Player.getContextEpoch()), false, "invalid old id " .. tostring(id)) end
        for _, reason in ipairs({ "Finished", "Skipped", "complete", "live_finished", "live_skipped", "live_interrupted", "unknown", "" }) do
            eq(f.Player.noteLegacyResult(65, reason, f.Player.getContextEpoch()), false, "invalid reason " .. reason)
        end
        for _, id in ipairs({ "02705", "2705.0", "2705x", 2704, false }) do eq(f.Player.onStageCleared(id), false, "invalid clear " .. tostring(id)) end
        check(same(f.session(), before), "invalid input no mutation")
        eq(f.n("flush"), writes, "invalid input no write")
        local epoch = f.Player.getContextEpoch(); f.Player.cancel()
        before = copy(f.session())
        eq(f.Player.noteLegacyResult(65, "finished", epoch), false, "cancel old bridge stale")
        eq(f.Player.noteLegacyResult(65, "finished", tostring(f.Player.getContextEpoch())), false, "string epoch rejected")
        check(same(f.session(), before), "stale bridge unchanged")
        epoch = f.Player.getContextEpoch(); f.Dispatcher.set("session", sessionWith()); f.init()
        eq(f.Player.noteLegacyResult(65, "skipped", epoch), false, "new init rejects old epoch")
        epoch = f.Player.getContextEpoch(); f.publish(copy(f.session()))
        eq(f.Player.getContextEpoch(), epoch, "legitimate same-game JSON retains epoch")
        eq(f.Player.noteLegacyResult("65", "skipped", epoch), true, "valid JSON reattach accepts captured epoch")
        eq(f.Player.noteLegacyResult(65, "finished"), true, "synchronous two-argument bridge remains compatible")
    end)
end

local function interruptionAndResultCases()
    for _, reason in ipairs({ "reset", "replaced", "failed" }) do
        runCase("old65 interruption explicit-only and single-use " .. reason, function()
            local f = fixture(); live(f, reason)
            eq(f.node().legacyContext, "live_interrupted", "actual old result maps interrupted")
            eq(f.record().eventTrusted, true, "successful CLEAR and N01 retained")
            eq(f.Player.peekReady(), nil, "interrupted never automatic")
            eq(f.Player.begin(FIRST, KEY), nil, "no taken explicit request no first-read")
            local reboot = fixture(JSON.decode(f.disk).modules.session)
            eq(reboot.node().legacyContext, "live_interrupted", "JSON interrupted retained")
            eq(reboot.Player.peekReady(), nil, "JSON still not automatic")
            eq(reboot.Player.requestRead(KEY), true, "explicit record request allowed")
            local request = assert(reboot.Player.takeRequest()); eq(request.key, KEY, "explicit key")
            eq(reboot.Player.takeRequest(), nil, "one-use take")
            local lease = assert(reboot.Player.begin(request.kind, request.key))
            eq(reboot.Player.onResult(result(lease, "reset")), true, "new slice cancellation")
            eq(reboot.Player.begin(FIRST, KEY), nil, "cancelled slice cannot reuse taken authorization")
            eq(reboot.Player.requestRead(KEY), true, "must explicitly request again")
            request = assert(reboot.Player.takeRequest()); lease = assert(reboot.Player.begin(request.kind, request.key))
            eq(reboot.Player.onResult(result(lease, "skipped")), true, "explicit first skip handles slice")
            eq(reboot.node().legacyContext, "live_interrupted", "slice read does not rewrite old encounter")
            eq(reboot.record().evidence.text, B_TEXT, "explicit processing awards own B")
            local saved, count = copy(reboot.session()), reboot.n("flush")
            local replay = assert(reboot.Player.begin(REPLAY, KEY)); reboot.Player.onResult(result(replay, "finished"))
            check(same(reboot.session(), saved), "replay freezes old interruption and B")
            eq(reboot.n("flush"), count, "replay no save")
        end)
    end
    for _, ending in ipairs({ "finished", "dismissed", "skipped", "reset", "replaced", "failed" }) do
        runCase("first result/replay/frozen evidence isolation " .. ending, function()
            local f = fixture(oldArchive()); local old, outside = oldPart(f.session()), outsideStory(f.session())
            live(f, "skipped")
            local lease, writes = assert(f.Player.begin(FIRST, KEY)), f.n("flush")
            for _, field in ipairs({ "playToken", "contextEpoch", "nodeKey" }) do
                local bad = result(lease, "finished"); bad[field] = "wrong"
                eq(f.Player.onResult(bad), false, "wrong identity " .. field)
            end
            eq(f.Player.onResult(result(lease, "unknown")), false, "bad reason does not consume token")
            eq(f.Player.onResult(result(lease, ending)), true, "exact real result accepted")
            eq(f.Player.onResult(result(lease, "skipped")), false, "duplicate late result rejected")
            local success = ending == "finished" or ending == "dismissed" or ending == "skipped"
            eq(f.record().status, success and (ending == "skipped" and "skipped" or "finished") or "pending", "read vs skip vs interrupted separate")
            eq(f.node().legacyContext, "live_skipped", "old65 skip stays separately recorded")
            eq(f.n("flush"), writes + (success and 1 or 0), "only handled first result writes")
            if success then
                local public, saved = assert(f.record().evidence), f.session().samsaraStory.evidence["E03-B"]
                eq(public.id, "E03-B", "B only")
                eq(public.text, B_TEXT, "B exact request")
                eq(public.source, SOURCE, "B frozen exact source")
                eq(#f.record().evidences, 1, "never A/C/E02/E05 mixture")
                saved.annotationUnlocked, saved.continuationUnlocked, saved.peopleUnlocked = true, true, true
                saved.unknown = { keep = 8 }
                for _, field in ipairs({ "annotation", "continuation", "people" }) do eq(f.record().evidence[field], nil, "no future public explanation " .. field) end
                local all, flushes = copy(f.session()), f.n("flush")
                eq(f.Player.onStageCleared(2705), false, "repeat real CLEAR cannot reset result/source")
                eq(legacy(f, "skipped"), false, "repeat old65 result idempotent")
                for _, replayReason in ipairs({ "finished", "dismissed", "skipped", "reset", "replaced", "failed" }) do
                    local replay = assert(f.Player.begin(REPLAY, KEY)); eq(f.Player.onResult(result(replay, replayReason)), true, "replay accepts " .. replayReason)
                    check(same(f.session(), all), "replay freezes first result/B/old fields " .. replayReason)
                    eq(f.n("flush"), flushes, "replay never persists " .. replayReason)
                end
                local reboot = fixture(JSON.decode(JSON.encode(f.session())))
                eq(reboot.record().status, f.record().status, "JSON exact first result")
                eq(reboot.record().evidence.source, SOURCE, "JSON B source frozen")
            else hidden(f, "unprocessed interruption") end
            check(same(oldPart(f.session()), old), "N08 never mutates A/C/N01/old five/evidence")
            noRewards(f, outside, "N08 first and replay")
        end)
    end
    runCase("public B requires exact evidence and node source, N01 still trusted", function()
        local f = fixture(); live(f); finish(f)
        local node, saved = f.node(), f.session().samsaraStory.evidence["E03-B"]
        local flushes = f.n("flush")
        for _, source in ipairs({ "legacy_raw_clear_unknown", "live_clear", "live_clear_2505", "live_clear_2905", "LIVE_CLEAR_2705", "case_archive" }) do
            saved.source = source; eq(f.record().evidence, nil, "bad evidence source hidden " .. source)
            saved.source = SOURCE; node.eligibilitySource = source
            eq(f.record().referenceOnly, true, "bad node source reference " .. source)
            eq(f.Player.begin(REPLAY, KEY), nil, "bad node source not replay")
            eq(f.record().evidence, nil, "bad node source no B")
            node.eligibilitySource = SOURCE
        end
        local opening = f.session().samsaraStory.nodes[OPENING]
        opening.eligibilitySource = "legacy_claimed_unknown"
        eq(f.Player.requestRead(KEY), false, "processed N08 cannot borrow unknown N01")
        eq(f.record().evidence, nil, "unknown N01 hides B")
        opening.eligibilitySource = "live_opening_chain"
        eq(f.record().evidence.text, B_TEXT, "restored exact provenance shows B")
        eq(f.n("flush"), flushes, "read-only provenance checks no write")
    end)
    for _, change in ipairs({ "cancel", "init", "silent swap", "new game", "N01 source", "N01 pending", "dragon source" }) do
        runCase("active first-read rejects changed context " .. change, function()
            local f = fixture(); live(f); local lease = assert(f.Player.begin(FIRST, KEY))
            if change == "cancel" then f.Player.cancel()
            elseif change == "init" then f.init()
            elseif change == "silent swap" then
                f.Dispatcher.unsubscribe("session", f.Player.onSessionUpdated); f.Dispatcher.set("session", copy(f.session()))
            elseif change == "new game" then local session = sessionWith(false); session.samsaraStory = f.Schema.new(); f.publish(session)
            elseif change == "N01 source" then f.session().samsaraStory.nodes[OPENING].eligibilitySource = "legacy_claimed_unknown"
            elseif change == "N01 pending" then f.session().samsaraStory.nodes[OPENING].resolution = nil
            else f.node().eligibilitySource = "legacy_raw_clear_unknown" end
            local before, writes = copy(f.session()), f.n("flush")
            eq(f.Player.onResult(result(lease, "finished")), false, "late result refused")
            check(same(f.session(), before), "late result no mutation")
            eq(f.n("flush"), writes, "late result no write")
        end)
    end
    runCase("legitimate same-game JSON retains request and active token", function()
        local f = fixture(); live(f)
        eq(f.Player.requestRead(KEY), true, "request queued")
        f.publish(copy(f.session())); eq(f.Player.takeRequest().key, KEY, "request survives publication")
        local lease = assert(f.Player.begin(FIRST, KEY)); f.publish(copy(f.session()))
        eq(f.Player.onResult(result(lease, "skipped")), true, "token survives notified same-game publication")
        eq(f.record().evidence.source, SOURCE, "rebound table gets same B source")
        for _, field in ipairs({ "scarCompleted", "playToken", "contextEpoch" }) do eq(f.node()[field], nil, "no invented persisted field " .. field) end
        eq(f.node().playToken, nil, "process token never persisted")
        eq(f.node().contextEpoch, nil, "process epoch never persisted")
    end)
end

local function futureCases()
    runCase("dragon schema default/strict normalization/independent loaders/idempotent", function()
        local f = fixture()
        local a, b = f.Schema.new(), f.Schema.new()
        eq(a.dragonHistoryCaptured, false, "new dragon capture false")
        eq(a.dragonHistoryVersion, 1, "new dragon version1")
        a.nodes[KEY] = {}; eq(b.nodes[KEY], nil, "new nodes independent")
        local session = oldArchive(); local old = oldPart(session)
        session.samsaraStory.dragonHistoryCaptured = "true"
        session.samsaraStory.nodes[KEY] = { eligible = "true", contentVersion = "1", resolution = "reset",
            eligibilitySource = 9, legacyContext = 8, unknown = { keep = 8 } }
        session.samsaraStory.evidence["E03-B"] = { unlocked = "true", source = {}, unknown = { keep = 9 } }
        local ref, supported = f.Schema.normalize(session)
        eq(ref, session.samsaraStory, "same story identity")
        eq(supported, true, "current schema supported")
        eq(ref.dragonHistoryCaptured, false, "capture boolean strict")
        eq(ref.nodes[KEY].eligible, false, "eligible boolean strict")
        eq(ref.nodes[KEY].resolution, nil, "reset not processed")
        eq(ref.nodes[KEY].eligibilitySource, nil, "nonstr source discarded")
        eq(ref.nodes[KEY].legacyContext, nil, "nonstr old context discarded")
        eq(ref.evidence["E03-B"].unlocked, false, "B strict boolean")
        eq(ref.evidence["E03-B"].source, nil, "B strict source")
        check(same(oldPart(session), old), "dragon normalization leaves old eight intact")
        local once = copy(session); for _ = 1, 3 do f.Schema.normalize(session) end
        check(same(session, once), "normalization idempotent")
        for _, loader in ipairs({ f.Registry, f.Character }) do
            local value = sessionWith(); value.samsaraStory.nodes[KEY] = { eligible = "false", contentVersion = "1", resolution = "dismissed", unknown = { keep = 5 } }
            loader.applyOnLoad("session", value)
            eq(value.samsaraStory.nodes[KEY].eligible, false, "real independent onLoad normalizes dragon")
            eq(value.samsaraStory.nodes[KEY].resolution, nil, "real independent onLoad not fake completion")
            eq(value.samsaraStory.nodes[KEY].unknown.keep, 5, "real onLoad preserves unknown")
        end
    end)
    for _, version in ipairs({ 2, "99" }) do
        runCase("future whole schema preserved " .. tostring(version), function()
            local session = sessionWith(); session.samsaraStory = { schemaVersion = version, nodes = "future", evidence = false,
                dragonHistoryVersion = 9, dragonHistoryCaptured = "future", unknown = { keep = { false, 7 } } }
            local before = copy(session); local f = fixture(session, { clearedStages = { [2705] = true } })
            eq(f.supported, false, "future whole disabled")
            eq(f.record().status, "unsupported", "future not reference")
            eq(f.Player.onStageCleared(2705), false, "future no CLEAR")
            eq(legacy(f), false, "future no old65")
            eq(f.Player.beginOpening(), nil, "future no opening")
            eq(f.Player.requestRead(KEY), false, "future no request")
            eq(f.Player.begin(FIRST, KEY), nil, "future no first-read")
            eq(f.Player.begin(REPLAY, KEY), nil, "future no replay")
            f.Player.cancel(); f.Player.update(100)
            check(same(f.session(), before), "future all structure preserved")
            eq(f.n("flush"), 0, "future no save")
        end)
        for _, domain in ipairs({ "dragonHistoryVersion", "contentVersion" }) do
            runCase("future dragon domain/node and B untouched " .. domain .. "/" .. tostring(version), function()
                local session = sessionWith()
                session.samsaraStory.nodes[KEY] = { contentVersion = domain == "contentVersion" and version or 1,
                    eligible = "tagged future", resolution = { future = "handled" }, source = { keep = 7 } }
                if domain == "dragonHistoryVersion" then
                    session.samsaraStory.dragonHistoryVersion, session.samsaraStory.dragonHistoryCaptured = version, "future flag"
                end
                session.samsaraStory.evidence["E03-B"] = { unlocked = "tagged true", source = { future = "source" },
                    annotationUnlocked = { keep = true }, continuationUnlocked = "future", peopleUnlocked = 7 }
                local node, evidence = copy(session.samsaraStory.nodes[KEY]), copy(session.samsaraStory.evidence["E03-B"])
                local f = fixture(session, { clearedStages = { [2705] = true } })
                eq(f.record().status, "unsupported", "only dragon future unsupported")
                eq(f.Player.onStageCleared(2705), false, "future dragon no CLEAR")
                eq(legacy(f), false, "future dragon no old65")
                eq(f.Player.requestRead(KEY), false, "future dragon no request")
                eq(f.Player.begin(FIRST, KEY), nil, "future dragon no first-read")
                check(same(f.node(), node), "future node all fields untouched")
                check(same(session.samsaraStory.evidence["E03-B"], evidence), "future B tagged source/flags untouched")
                for _, spec in ipairs({ { DOG, 2505, 64, "E03-A" }, { BELL, 2905, 67, "E03-C" } }) do
                    eq(f.Player.onStageCleared(spec[2]), true, "other mirror live CLEAR")
                    eq(f.Player.noteLegacyResult(spec[3], "skipped", f.Player.getContextEpoch()), true, "other mirror old result")
                    finish(f, "skipped", spec[1]); eq(f.Player.getRecord(spec[1]).evidence.id, spec[4], "A/C still functional")
                end
                eq(f.Player.requestRead(OPENING), true, "N01 unaffected replay request")
                local req = assert(f.Player.takeRequest()); local replay = assert(f.Player.begin(req.kind, req.key))
                f.Player.onResult(result(replay, "skipped"))
                f.Schema.normalize(session)
                check(same(f.node(), node), "A/C/N01 handling cannot wash future dragon")
                check(same(session.samsaraStory.evidence["E03-B"], evidence), "A/C/N01 cannot wash future B")
            end)
        end
        runCase("future old mirror domain does not seal independent dragon " .. tostring(version), function()
            local session = sessionWith(); session.samsaraStory.mirrorHistoryVersion, session.samsaraStory.mirrorHistoryCaptured = version, "future"
            session.samsaraStory.nodes[DOG] = { eligible = "future", contentVersion = 1, source = { future = true } }
            session.samsaraStory.evidence["E03-A"] = { source = {}, unlocked = "future" }
            local old = oldPart(session); local f = fixture(session)
            live(f); finish(f, "skipped")
            eq(f.record().evidence.text, B_TEXT, "dragon independent of future A/C domain")
            check(same(oldPart(session), old), "dragon does not wash future A/C")
        end)
    end
    for _, domain in ipairs({ "schemaVersion", "dragonHistoryVersion", "dragon content", "opening content" }) do
        runCase("runtime future upgrade rejects active N08 result " .. domain, function()
            local f = fixture(); live(f); local lease = assert(f.Player.begin(FIRST, KEY))
            if domain == "dragon content" then f.node().contentVersion = 99
            elseif domain == "opening content" then f.session().samsaraStory.nodes[OPENING].contentVersion = 99
            else f.session().samsaraStory[domain] = 99 end
            local before, writes = copy(f.session()), f.n("flush")
            eq(f.Player.onResult(result(lease, "finished")), false, "active unsupported result rejected")
            eq(f.Player.requestRead(KEY), false, "unsupported no request")
            check(same(f.session(), before), "active future unchanged")
            eq(f.n("flush"), writes, "active future no save")
        end)
    end
end

local function saveCases()
    for _, phase in ipairs({ "clear", "legacy", "resolution" }) do
        for _, fault in ipairs({ "open", "write", "encode", "rename", "set", "false", "nil", "throw" }) do
            runCase("real memory Save failure/retry " .. phase .. "/" .. fault, function()
                local f = fixture(); eq(f.Save.Flush(), true, "committed memory baseline")
                if phase == "resolution" then live(f) end
                local outside, disk, writes = outsideStory(f.session()), f.disk, f.n("flush")
                if fault == "false" or fault == "nil" or fault == "throw" then f.flushMode = fault else f.fail = fault end
                if phase == "clear" then eq(f.Player.onStageCleared(2705), true, "failed-save eligible retained")
                elseif phase == "legacy" then eq(legacy(f, "skipped"), true, "failed-save old65 retained")
                else finish(f, "skipped") end
                eq(f.Player.isSavePending(), true, "failed save pending")
                eq(f.disk, disk, "committed memory disk unchanged")
                eq(f.n("flush"), writes + (fault == "set" and 0 or 1), "one attempt unless notify failed")
                if phase == "clear" then eq(f.node().eligibilitySource, SOURCE, "memory live source")
                elseif phase == "legacy" then eq(f.node().legacyContext, "live_skipped", "memory old skip")
                else eq(f.record().status, "skipped", "memory first skip"); eq(f.record().evidence.source, SOURCE, "memory B source") end
                local reboot = fixture(JSON.decode(disk).modules.session)
                if phase == "resolution" then eq(reboot.record().status, "pending", "disk restart still unread"); hidden(reboot, "disk failed resolution")
                else reference(reboot, "disk failed registration") end
                local attempts = f.n("flush")
                f.Player.cancel(); f.init()
                eq(f.Player.isSavePending(), true, "cancel/same-table init keep dirty")
                f.Player.update(-1); f.Player.update(0 / 0); f.Player.update(math.huge)
                f.Player.update(1); f.Player.update(0.999)
                eq(f.n("flush"), attempts, "invalid dt and before2s no retry")
                f.Player.update(0.001)
                eq(f.n("flush"), attempts + (fault == "set" and 0 or 1), "at2s exactly one failed retry")
                f.fail, f.flushMode = "", "real"; f.Player.update(2)
                eq(f.Player.isSavePending(), false, "true Flush clears dirty")
                local restored = JSON.decode(f.disk).modules.session.samsaraStory.nodes[KEY]
                if phase == "legacy" then eq(restored.eligibilitySource, nil, "legacy result alone has no CLEAR source")
                else eq(restored.eligibilitySource, SOURCE, "disk source exact") end
                if phase == "clear" then eq(restored.legacyContext, nil, "CLEAR alone has no old65 result")
                else eq(restored.legacyContext, phase == "legacy" and "live_skipped" or "live_finished", "disk old context exact") end
                eq(restored.resolution, phase == "resolution" and "skipped" or nil, "disk first result exact")
                eq(f.Save.RestoreData(), true, "real RestoreData memory only")
                f.init(); local done = f.n("flush"); f.Player.update(100)
                eq(f.n("flush"), done, "successful restore no retry loop")
                noRewards(f, outside, "save fault recovery")
            end)
        end
    end
end

local function presentationCases()
    runCase("real Panel ninth tab/reference six lines/resize/scroll/touch no penetration", function()
        local f = fixture(sessionWith(false)); live(f)
        local before, flushes = copy(f.session()), f.n("flush")
        local requests, request = 0, f.Player.requestRead
        f.Player.requestRead = function(key) requests = requests + 1; return request(key) end
        for _, size in ipairs({ { 1920, 1080 }, { 2340, 1080 }, { 1280, 800 } }) do
            local w, h = size[1], size[2]
            eq(f.Panel.selectRecord(KEY), true, "select ninth key")
            f.Panel.open(); local text = f.draw(w, h)
            eq(#f.tabs, 10, "十个实际标签，N08仍第九")
            check(includes(text, "龙的罐头"), "ninth compact label")
            for index = 2, 10 do
                check(f.tabs[index].x > f.tabs[index - 1].x, "tabs centers increase")
                check(f.tabs[index].x - f.tabs[index - 1].x > f.tabs[index].width, "tabs non-overlap")
            end
            for index = 3, 8 do check(includes(text, STEPS[index].text), "reference exact six lines") end
            check(not includes(text, B_TEXT), "reference no B request text")
            local scale = math.min(w / 1920, h / 1080)
            for _, spec in ipairs({ { 7, BELL }, { 8, OPENING }, { 9, KEY } }) do
                local tab = f.tabs[spec[1]]; f.Panel.selectRecord(OLD_KEYS[1])
                eq(f.Panel.handleInput(tab.x * scale, tab.y * scale, w, h), true, "real tab input consumed")
                check(includes(f.draw(w, h), f.Config.get(spec[2]).title), "exact slot " .. spec[1] .. " selects own key")
            end
            local nightmareTab = f.tabs[10]
            f.Panel.selectRecord(OLD_KEYS[1]); f.Panel.handleInput(nightmareTab.x * scale, nightmareTab.y * scale, w, h)
            local nightmareText = f.draw(w, h)
            check(includes(nightmareText, f.Config.get("samsara.nightmare_afterimage").title), "第十标签精确选择N11")
            check(includes(nightmareText, "亲历未确认"), "N11不借龙来源补造旧70经历")
            eq(f.session().samsaraStory.nodes["samsara.nightmare_afterimage"], nil, "点击N11无资格写入")
            f.Panel.selectRecord(KEY); f.draw(w, h)
            local action = f.action("仅供查阅")
            eq(f.Panel.handleInput(action.x * scale, action.y * scale, w, h), true, "reference action consumed")
            eq(f.Panel.handleInput(0, 0, w, h), true, "full mask consumes outside")
            eq(f.Panel.isOpen(), true, "reference not closed or queued")
        end
        f.Panel.selectRecord(KEY); f.draw(); local firstY = f.boxes[1].y
        eq(f.Panel.handleWheel(-2), true, "long text wheel consumed")
        f.draw(); check(f.boxes[1].y < firstY, "wheel actually scrolls")
        f.Panel.handleWheel(100000); f.draw(); eq(f.boxes[1].y, firstY, "top clamp")
        local first = f.boxes[1]
        eq(f.Panel.handleDragBegin(first.x + 50, first.y + 80), true, "touch begin consumed")
        eq(f.Panel.handleDragMove(first.x + 50, first.y - 180), true, "touch move consumed")
        eq(f.Panel.handleDragEnd(), true, "actual drag not tap")
        local action = f.action("仅供查阅")
        eq(f.Panel.handleInput(action.x, action.y, 1920, 1080), true, "drag-ended action swallowed")
        f.draw(); check(f.boxes[1].y < firstY, "touch actually scrolls")
        f.Panel.selectRecord(KEY); f.draw(); eq(f.boxes[1].y, firstY, "reselect resets scroll")
        eq(requests, 0, "reference or drag never requests")
        eq(f.Playback.tryPlay(gates(f)), false, "no N08 presentation without N01")
        eq(#f.shown, 0, "reference no Dialogue")
        eq(f.n("flush"), flushes, "all static UI no save")
        check(same(f.session(), before), "all static UI no mutation")
    end)
    for _, ending in ipairs({ "dismissed", "skipped", "reset", "replaced", "false", "throw" }) do
        runCase("real Playback/Dialogue and Panel own frozen B " .. ending, function()
            local f = fixture(oldArchive()); live(f)
            local outside, old = outsideStory(f.session()), oldPart(f.session())
            f.Panel.selectRecord(KEY); f.Panel.open(); f.draw()
            local action = f.action("待阅"); f.Panel.handleInput(action.x, action.y, 1920, 1080)
            eq(f.Dialogue.isActive(), false, "Panel request never synchronous show")
            for _, name in ipairs({ "ready", "legacyPending", "blocked", "pointerBusy" }) do
                local g = gates(f); g[name] = name ~= "ready"
                eq(f.Playback.tryPlay(g), false, "gate preserves request " .. name)
            end
            if ending == "false" or ending == "throw" then f.showFault = ending end
            eq(f.Playback.tryPlay(gates(f)), ending ~= "false" and ending ~= "throw", "next arbitration actual show")
            local cfg = assert(f.shown[1]); check(same(cfg.steps, STEPS), "real show exact eight steps")
            eq(cfg.completionToken.nodeKey, KEY, "own completion token")
            eq(cfg.onFinish, nil, "no old economic finish callback")
            eq(cfg.scenarioId, nil, "no economic scenario id")
            if ending ~= "false" and ending ~= "throw" then
                f.Dialogue.update(100); f.Dialogue.draw(1920, 1080)
                eq(f.Story.length(STEPS[1].text), utf8.len(STEPS[1].text), "real UTF-8 codepoint length")
                check(includes(table.concat(f.displayed), STEPS[1].text), "real fitted rows show full Chinese first line")
            end
            if ending == "dismissed" then
                finishDialogue(f.Dialogue); hidden(f, "dismiss animation not yet completion"); f.Dialogue.update(0.29)
                hidden(f, "before dismiss threshold"); f.Dialogue.update(0.02)
            elseif ending == "skipped" then eq(f.Dialogue.handleSliceInput(1800, 130, 1920, 1080), true, "real landscape touch skip")
            elseif ending == "reset" then f.Dialogue.reset()
            elseif ending == "replaced" then f.realShow({ mode = "small", steps = f.Config.get(OLD_KEYS[1]).steps }); f.Dialogue.reset() end
            local success = ending == "dismissed" or ending == "skipped"
            eq(f.record().status, success and (ending == "skipped" and "skipped" or "finished") or "pending", "real terminal mapping")
            eq(#f.shown, 1, "completion never recursive show")
            if success then
                f.Panel.open(); local text = f.draw()
                check(includes(text, B_TEXT), "own B exact public request")
                check(includes(text, "冻结来源"), "Panel explicitly frozen source")
                check(not includes(text, f.Config.getEvidence("E03-A").text), "no A request in B record")
                check(not includes(text, f.Config.getEvidence("E03-C").text), "no C request in B record")
                check(not includes(text, f.Config.getEvidence("E05").text), "no E05 in B record")
                local all, writes = copy(f.session()), f.n("flush")
                action = f.action("回看"); f.Panel.handleInput(action.x, action.y, 1920, 1080)
                eq(f.Playback.tryPlay(gates(f)), true, "real replay")
                eq(f.shown[2].completionToken.kind, REPLAY, "real replay kind")
                f.Dialogue.skip(); check(same(f.session(), all), "real replay zero mutation")
                eq(f.n("flush"), writes, "real replay zero save")
            else hidden(f, "real interrupted presentation") end
            check(same(oldPart(f.session()), old), "real presentation old eight preserved")
            noRewards(f, outside, "real presentation")
        end)
    end
    runCase("pending-save Panel disables requests without turning replay into award", function()
        local f = fixture(); live(f); f.flushMode = "false"; finish(f, "skipped")
        f.Panel.selectRecord(KEY); f.Panel.open(); f.draw()
        local before = copy(f.session()); local action = f.action("保存中")
        eq(f.Panel.handleInput(action.x, action.y, 1920, 1080), true, "saving disabled input consumed")
        eq(f.Panel.isOpen(), true, "saving does not close")
        eq(f.Player.takeRequest(), nil, "saving no queued replay")
        check(same(f.session(), before), "saving action no mutation")
    end)
end

-- opening宿主fixture的真实标题/0.1s淡出与hasData门禁；增加真实StandaloneBoot。
-- 无关页面只返回门禁或保存回调；旧队列边界提供真实SCENARIO_65配置，经济仅spy。
local function bindStandalone(f)
    local h = { modules = {}, oldQueue = {}, notes = {}, actions = {}, clearHooks = {}, backfills = 0, bootRuns = 0 }
    f.Dispatcher.set("player", assert(f.Registry.find("player")).getDefault())
    f.Dispatcher.set("heroes", { roster = { [1] = { level = 1 }, [2] = { level = 1 }, [3] = { level = 1 } }, deployed = { 1, 2, 3 } })
    eq(f.Dispatcher.hasData(), true, "host core data complete; missing=" .. f.Dispatcher.getMissingRequiredModules())
    local function page() return setmetatable({}, { __index = function() return function() return false end end }) end
    local modules = h.modules
    modules["config.GameConfig"], modules["config.SamsaraSliceConfig"] = f.GameConfig, f.Config
    modules["config.ScenarioDialogueConfig"], modules["runtime.ClientDispatcher"] = f.Legacy, f.Dispatcher
    modules["shared.session.SessionSchema"], modules["systems.SamsaraSlicePlayer"] = f.SessionSchema, f.Player
    modules["systems.SamsaraSlicePlayback"], modules["ui.story.ScenarioDialogue"] = f.Playback, f.Dialogue
    modules["ui.story.SamsaraRecordPanel"], modules["core.EventBus"] = f.Panel, f.Bus
    modules["config.GameEvents"] = isolated("config/GameEvents.lua", {})
    modules["core.I18n"], modules["core.DrawUtil"] = f.I18n, f.Draw
    modules["boot.StandaloneRT"], modules["boot.StandaloneHorizon"] = {}, {}
    modules["boot.StandaloneHorizonInput"] = { isPointerBusy = function() return h.pointerBusy == true end }
    modules["boot.StandaloneSave"] = f.Save
    modules["core.GameState"] = setmetatable({ getName = function() return "fixture" end, reset = function() end },
        { __index = function(_, method) return function() f.count("host.economy." .. tostring(method)); return 0 end end })
    modules["ui.character.panel.CharacterPanel"] = setmetatable({ isHeroesDataApplied = function() return true end,
        getDeployedTeam = function() return {} end, getTotalPower = function() return 0 end,
    }, { __index = function() return function() return false end end })
    modules["ui.hud.BottomNav"] = setmetatable({ getSelectedIndex = function() return 3 end }, { __index = function() return function() return false end end })
    modules["ui.battle.scene.BattleScene"] = setmetatable({ getMaxStageId = function() return 101 end,
        getStageId = function() return 101 end, getClearedStages = function() return {} end,
        setOnFirstClear = function(fn) h.clearHooks[#h.clearHooks + 1] = fn end,
    }, { __index = function() return function() return false end end })
    modules["runtime.ClientMessageHandler"] = setmetatable({ consumePendingScenarioDialogue = function() return nil end,
        consumePendingFollowUpDialogue = function() return nil end,
    }, { __index = function() return function() return false end end })
    modules["systems.StoryPlayer"] = setmetatable({ take = function() return table.remove(h.oldQueue, 1) end,
        backfillCleared = function() h.backfills = h.backfills + 1 end,
        followOf = function() return nil end, onStage = function(id, trigger) h.lastStoryStage = { id, trigger } end,
    }, { __index = function() return function() return false end end })
    modules["systems.TutorialManager"] = setmetatable({ canPlayPendingStory = function() return true end },
        { __index = function() return function() return false end end })
    modules["rules.offline.OfflineService"] = { CalcOnEnter = function() return nil end, HasPendingRewards = function() return false end }
    modules["runtime.GameAction"] = { sendAction = function(action, params)
        h.actions[#h.actions + 1] = { action = action, params = copy(params) }; return true
    end }
    modules["config.StageConfig"] = { getNextStageId = function() return nil end, isTerminalTemple = function() return false end,
        getStage = function() return nil end } -- 无首通经济计算；真正Boot接线/账本/切片桥仍执行。
    modules["systems.LootBoxSystem"] = setmetatable({ consolidateSeeds = function() end,
        getTotalCount = function() return 0 end }, { __index = function() return function() return false end end })
    modules["runtime.LocalActionBridge"] = { init = function() end }
    modules["core.PlayerStore"] = { Init = function() end, Subscribe = function() end, Get = f.Dispatcher.get }
    h.Title = isolated("ui/story/gate/DarkTitleScreenGate.lua", { ["core.I18n"] = f.I18n }, f.graphics)
    h.Letter = isolated("ui/story/gate/LetterIntro.lua", { ["core.I18n"] = f.I18n,
        ["core.I18nStory"] = f.Story, ["ui.story.StoryDisplay"] = f.Display }, f.graphics)
    modules["ui.story.gate.DarkTitleScreenGate"], modules["ui.story.gate.LetterIntro"] = h.Title, h.Letter
    local note = f.Player.noteLegacyResult
    f.Player.noteLegacyResult = function(id, reason, epoch)
        h.notes[#h.notes + 1] = { id = id, reason = reason, epoch = epoch }; return note(id, reason, epoch)
    end
    local function fallback(name)
        assert(name ~= "rules.character.PlayerDataManager", "host must not load real PDM")
        if not modules[name] then modules[name] = page() end
        return modules[name]
    end
    h.Boot = isolated("boot/StandaloneBoot.lua", modules, nil, fallback)
    local realRun = h.Boot.run
    h.Boot.run = function(rt) h.bootRuns = h.bootRuns + 1; return realRun(rt) end
    modules["boot.StandaloneBoot"] = h.Boot
    local scene = { CreateComponent = function() return {} end,
        CreateChild = function() return { CreateComponent = function() return {} end } end }
    local globals = { Scene = function() return scene end, renderer = { SetViewport = function() end },
        Viewport = { new = function() return {} end },
        graphics = { GetWidth = function() return 1920 end, GetHeight = function() return 1080 end, GetDPR = function() return 1 end },
        time = { elapsedTime = 100 }, nvgCreate = function() return {} end, nvgCreateFont = function() return 1 end,
        nvgCreateImage = f.graphics.nvgCreateImage, nvgDelete = function() end, SubscribeToEvent = function() end,
        HandleEquipmentHoverTickHorizon = function() end, H_AUTO_OPEN_TRI = false, H_AUTO_TAB = false, H_AUTO_OPEN_PANEL = false }
    h.Standalone, h.env = isolated("boot/Standalone.lua", modules, globals, fallback)
    h.Standalone.Start()
    function h.frame(dt)
        local step = dt or 0.016; h.env.time.elapsedTime = h.env.time.elapsedTime + step
        h.env.HandleUpdate("Update", { TimeStep = { GetFloat = function() return step end } })
    end
    h.frame()
    eq(h.bootRuns, 1, "actual host bootWiring calls real Boot.run once")
    eq(#h.clearHooks, 1, "real Boot registers firstclear callback")
    eq(h.Title.isOpen(), true, "real title open")
    eq(h.Title.isReady(), true, "real boot queue title ready")
    h.Title.handleTap()
    for _ = 1, 8 do if not h.Title.isOpen() then break end; h.frame(0.1) end
    eq(h.Title.isOpen(), false, "real normal small-frame title fade closed")
    h.frame()
    eq(h.Letter.isOpen(), false, "old intro does not manufacture opening chain")
    eq(h.backfills, 1, "real hasData/postStart safe backfill")
    return h
end
local function hostCases()
    for _, teamIdx in ipairs({ 1, 2, 3 }) do
        for _, ending in ipairs({ "finished", "skipped", "reset" }) do
            runCase("real old65 queue->Boot firstclear team->safe-frame N08 " .. teamIdx .. "/" .. ending, function()
                local f = fixture(); local h = bindStandalone(f)
                eq(#f.shown, 0, "no early N08")
                local outside = outsideStory(f.session())
                h.oldQueue[#h.oldQueue + 1] = { scenarioId = 65, config = f.Legacy.SCENARIO_65 }
                h.frame(); eq(#f.shown, 1, "real host consumes old65 queue")
                local cfg = assert(f.shown[1]); check(same(cfg.steps, f.Legacy.SCENARIO_65.steps), "host authentic old65 steps")
                eq(cfg.completionToken.nodeKey, "legacy.65", "host old65 identity")
                check(type(cfg.onFinish) == "function", "old economic callback retained only in old branch")
                eq(f.session().claimedScenarios["65"], true, "real host preclaim is not proof of read")
                hidden(f, "old65 active")
                if ending == "finished" then finishDialogue(f.Dialogue)
                elseif ending == "skipped" then f.Dialogue.skip() else f.Dialogue.reset() end
                eq(#h.notes, 1, "actual old65 result once")
                eq(h.notes[1].id, 65, "captured real old65 id")
                eq(h.notes[1].reason, ending, "captured real old65 reason")
                eq(type(h.notes[1].epoch), "number", "host captured epoch")
                eq(f.node().legacyContext, ending == "reset" and "live_interrupted" or (ending == "skipped" and "live_skipped" or "live_finished"), "host result separate from CLEAR")
                eq(#f.shown, 1, "old result never recursively shows N08")
                local current = f.Dispatcher.get("battle").currentStageId
                h.clearHooks[1](2705, teamIdx)
                eq(f.node().eligibilitySource, SOURCE, "real Boot firstclear reaches Player")
                eq(f.Dispatcher.get("battle").clearedStages["2705"], true, "real Boot shared firstclear ledger")
                if teamIdx ~= 1 then eq(f.Dispatcher.get("battle").currentStageId, current, "team2/3 do not pull team1 current") end
                check(same(h.lastStoryStage, { 2705, "clear" }), "Boot retains old stage-clear trigger")
                hidden(f, "real Boot CLEAR awards no B")
                eq(#f.shown, 1, "Boot callback no synchronous N08")
                h.pointerBusy = true; h.frame(); eq(#f.shown, 1, "pointer-busy safe gate blocks")
                h.pointerBusy = false; h.frame()
                if ending == "reset" then
                    eq(#f.shown, 1, "actual old interruption never auto N08")
                    eq(f.Player.requestRead(KEY), true, "explicit request after interruption")
                    h.frame()
                end
                eq(#f.shown, 2, "next safe arbitration starts N08")
                check(same(f.shown[2].steps, STEPS), "host N08 genuine eight steps")
                eq(f.shown[2].completionToken.nodeKey, KEY, "host independent N08 token")
                eq(f.shown[2].onFinish, nil, "N08 no old grant callback")
                f.Dialogue.skip(); eq(f.record().evidence.text, B_TEXT, "host N08 firstskip awards only B")
                local actions, saved = #h.actions, copy(f.session())
                eq(f.Player.requestRead(KEY), true, "host explicit replay request")
                h.frame(); f.Dialogue.skip()
                eq(#h.actions, actions, "N08 replay no economic action")
                check(same(f.session(), saved), "host replay source/first result frozen")
                for _, action in ipairs(h.actions) do
                    eq(action.action, "claim_scenario_reward", "only existing old65 action allowed")
                    eq(action.params.scenarioId, 65, "economic spy old65 only")
                end
                for name, count in pairs(f.calls) do if name:match("^host%.economy%.") then eq(count, 0, "no actual host economy") end end
                -- 唯一旧账本变化是宿主真实65预标记；N08不再改旧账本。
                outside.claimedScenarios["65"] = true
                noRewards(f, outside, "real host N08 and replay")
            end)
        end
    end
end

function Start()
    local ok, err = pcall(function()
        assert(type(JSON) == "table" and type(JSON.encode) == "function" and type(JSON.decode) == "function", "real cjson required")
        configurationCases()
        historyCases()
        prerequisiteCases()
        interruptionAndResultCases()
        futureCases()
        saveCases()
        presentationCases()
        hostCases()
    end)
    if not ok then check(false, "Start exception: " .. tostring(err)) end
    print(PREFIX .. "RESULT cases=" .. passed .. "/" .. cases .. " assertions=" .. assertions .. " failures=" .. failures)
    if failures == 0 and cases > 0 and passed == cases then print(PREFIX .. "ALL PASS") end
    engine:Exit()
end
