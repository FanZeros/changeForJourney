-- N11「还记得刚才吗」隔离专项：仅测试，主会话协调官方build与Runtime；不生成meta。
-- 基于opening/dragon私有load夹具；真实Config/Schema/Player/Playback/Dialogue/Panel/Save/Dispatcher/宿主。
-- 仅读取cache中的源码；File/经济/GPU/无关页面为内存边界，不改require缓存或生产文件。
-- 基于scaffold-2d的Start生命周期；无实际NanoVG上下文、事件订阅或玩家档访问。
local PREFIX = "[samsara_n11] "
local KEY, OPENING, SOURCE = "samsara.nightmare_afterimage", "samsara.opening_roster", "live_legacy_70"
local FIRST, REPLAY = "samsara_first_read", "samsara_replay"
local CARGO, ORDER, PEOPLE = "samsara.cargo_match", "samsara.gray_order", "samsara.people_record"
local OLD_KEYS = { "samsara.log_leaf", CARGO, ORDER, PEOPLE, "samsara.returned_manifest",
    "samsara.dog_mirror", "samsara.bell_mirror", OPENING, "samsara.dragon_mirror" }
local KEYS = { table.unpack(OLD_KEYS) }; KEYS[#KEYS + 1] = KEY
local CHAIN = { "letter", "opening", "join.1", "join.2", "join.3" }
-- 独立oracle：冻结精修稿五句与显示用旁白，不从生产get()反向构造期望正文。
local STEPS = {
    { name = "旁白", text = "黄桃龙把分给远征长的半罐黄桃放下。分食的是另开的口粮罐；名册旁的纪念罐仍未开封。视线里没有旧伙伴的身体。" },
    { characterId = 2, name = "黄桃龙", text = "这半边是你的。不是梦里的。" },
    { name = "远征长", text = "刚才有人说物资里全是队员的遗物。" },
    { characterId = 1, name = "大狗嚼", text = "我没说。叫！我就在这里。" },
    { characterId = 3, name = "叮咚鸡", text = "我记你听见了什么。先不写“发生过”。" },
    { name = "远征长", text = "去找能对照的东西。不能只凭我脑子里的话。" },
}
local assertions, failures, cases, passed = 0, 0, 0, 0
local JSON = cjson
local function check(value, label)
    assertions = assertions + 1
    if not value then
        failures = failures + 1
        print(PREFIX .. "FAIL " .. label); log:Write(LOG_ERROR, PREFIX .. "FAIL " .. label)
    end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " 实际=" .. tostring(actual) .. " 期望=" .. tostring(expected))
end
local function runCase(label, fn)
    cases = cases + 1
    local before = failures
    local ok, err = pcall(fn)
    if not ok then check(false, label .. " 异常=" .. tostring(err)) end
    if failures == before then passed = passed + 1; print(PREFIX .. "PASS " .. label) end
end
---@param value any
---@return any
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
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
    local out = {}; for key, value in pairs(session) do if key ~= "samsaraStory" then out[key] = copy(value) end end
    return out
end
local function oldPart(session)
    local story, out = session.samsaraStory, copy(session.samsaraStory)
    out.nodes[KEY] = nil
    -- 整个物证域与捕获标记也比较，不允许新增噩梦capture域或串借调查来源。
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
    assert(file and file:IsOpen(), "缺少真实源码 " .. path)
    local lines = {}; while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end; file:Dispose()
    local env = {}; for key, value in pairs(globals or {}) do env[key] = value end
    env.require = function(name)
        if overrides[name] ~= nil then return overrides[name] end
        if fallback then return fallback(name) end
        error("未声明依赖/经济路径 " .. path .. " " .. tostring(name))
    end
    env._G = env; setmetatable(env, { __index = _G })
    return assert(load(table.concat(lines, "\n"), "@" .. path, "t", env))(), env
end
---@param opening table|false|nil
---@return table
local function sessionWith(opening)
    local session = {
        lastOnlineTime = 0, firstLoginTime = 100, initialHeroId = 1, introCompleted = true,
        hasReincarnated = true, firstGachaTenDone = true,
        claimedScenarios = { ["17"] = true, ["44"] = true, ["64"] = true, ["65"] = true, ["67"] = true, ["82"] = true },
        scenarioRewardsGranted = { ["17"] = true, ["44"] = true, ["64"] = true, ["65"] = true, ["67"] = true },
        offlineBonusCount = 2, offlineBonusDate = "2026-10-04",
        tutorialProgress = { completed = { ["1"] = true }, group = 8, step = 3, unknown = "保全" },
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
    for index, key in ipairs(OLD_KEYS) do
        if key ~= OPENING then session.samsaraStory.nodes[key] = {
            eligible = true, contentVersion = 1, resolution = index % 2 == 0 and "skipped" or "finished",
            eligibilitySource = key == OLD_KEYS[6] and "live_clear_2505" or (key == OLD_KEYS[7] and "live_clear_2905"
                or (key == OLD_KEYS[9] and "live_clear_2705" or "previous_processed")),
            legacyContext = "live_finished", manualOnly = key == OLD_KEYS[5], unknown = { keep = index },
        } end
    end
    session.samsaraStory.evidence = {
        E01 = { unlocked = true, source = "clear_104_legacy", unknown = { keep = 1 } },
        E02 = { unlocked = true, source = "player_record", annotationUnlocked = true, unknown = { keep = 2 } },
        E05 = { unlocked = true, source = "order_archive", continuationUnlocked = true, peopleUnlocked = true },
        ["E03-A"] = { unlocked = true, source = "live_clear_2505" },
        ["E03-B"] = { unlocked = true, source = "live_clear_2705" },
        ["E03-C"] = { unlocked = true, source = "live_clear_2905" },
        unknown = { future = { false, "保全" } },
    }
    return session
end
local function result(lease, reason)
    return { playToken = lease.playToken, contextEpoch = lease.contextEpoch, nodeKey = lease.nodeKey, reason = reason }
end
local function gates() return { ready = true, legacyPending = false, blocked = false, pointerBusy = false } end

-- 真onLoad/Dispatcher/Save链；其余schema仅返回空字段，File只读写此夹具字符串。
---@return any
local function fixture(supplied, raw, config, legacyConfig, noInit)
    local f = { calls = {}, disk = "", temp = "", fail = "", flushMode = "real", shown = {}, font = 38 }
    function f.count(name) f.calls[name] = (f.calls[name] or 0) + 1 end
    function f.n(name) return f.calls[name] or 0 end
    f.Config = config or isolated("config/SamsaraSliceConfig.lua", {})
    f.Schema = isolated("shared/session/SamsaraStorySchema.lua", {})
    f.Legacy = legacyConfig or isolated("config/ScenarioDialogueConfig.lua", {})
    f.SessionSchema = isolated("shared/session/SessionSchema.lua", { ["shared.session.SamsaraStorySchema"] = f.Schema })
    f.Registry = isolated("shared/ModuleRegistry.lua", {
        ["shared.session.SamsaraStorySchema"] = f.Schema,
        ["config.AwakeningConfig"] = isolated("config/AwakeningConfig.lua", {}),
        -- 宿主仅创建空装备模块；水合边界必须明确接受空库存，不能让Registry捕获缺依赖异常。
        ["systems.EquipmentSystem"] = { hydrateInventory = function(inventory)
            f.count("boundary.hydrateEmpty"); check(type(inventory) == "table" and next(inventory) == nil, "隔离水合只接受空库存")
        end },
    }, nil, function(name)
        assert(name:match("^shared%..+Schema$") or name == "shared.heroes.TeamSlots", "意外Registry依赖 " .. name)
        return { Fields = {}, normalize = function() end }
    end)
    f.Character = isolated("shared/schemas/CharacterSchema.lua", { ["shared.session.SessionSchema"] = f.SessionSchema },
        nil, function(name) assert(name:match("^shared%..+Schema$"), "意外Character依赖 " .. name); return { Fields = {} } end)
    f.Dispatcher = isolated("runtime/ClientDispatcher.lua", {
        ["shared.Protocol"] = {}, ["shared.ModuleRegistry"] = f.Registry, ["shared.schemas.CharacterSchema"] = f.Character,
    })
    f.Dispatcher.set("session", supplied or sessionWith())
    f.Dispatcher.set("battle", { maxStageId = 9999, currentStageId = 101, clearedStages = {} })
    f.Dispatcher.set("currency", { gold = 123, gems = 456, unknown = "保全" })
    f.Dispatcher.set("opaqueModule", { value = { false, 9, "保全" } })
    f.gameState = { gold = 123, exp = 11, unknown = { keep = 42 } }
    local saveGlobals = {
        cjson = { encode = function(value)
            f.count("encode"); if f.fail == "encode" then error("注入编码故障") end; return JSON.encode(value)
        end, decode = function(value) return JSON.decode(value) end },
        fileSystem = {
            FileExists = function(_, path) eq(path, "standalone_save.json", "只查询内存已提交档"); return f.disk ~= "" end,
            Rename = function(_, from, to)
                f.count("rename"); eq(from, "standalone_save.pending.json", "内存原子替换来源")
                eq(to, "standalone_save.json", "内存原子替换目标")
                if f.fail == "rename" or not f.written or not f.closed then return false end
                f.disk, f.temp, f.written, f.closed = f.temp, "", false, false; return true
            end,
            Delete = function(_, path)
                eq(path, "standalone_save.pending.json", "失败只删除内存临时档，不删已提交档")
                f.temp, f.written, f.closed = "", false, false; return true
            end,
        },
        File = function(path, mode)
            eq(path, mode == FILE_WRITE and "standalone_save.pending.json" or "standalone_save.json", "File严格只在内存")
            f.count(mode == FILE_WRITE and "openWrite" or "openRead")
            local opened = not (mode == FILE_WRITE and f.fail == "open")
            if mode == FILE_WRITE and opened then f.temp, f.written, f.closed = "", false, false end
            return { IsOpen = function() return opened end,
                WriteString = function(_, data)
                    f.count("write"); if not opened or f.fail == "write" then return false end
                    if f.fail == "partial" then f.temp = data:sub(1, math.floor(#data / 2)); return false end
                    f.temp, f.written = data, true; return true
                end, ReadString = function() return f.disk end,
                Close = function() if mode == FILE_WRITE and opened then f.closed = f.fail ~= "close" end end }
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
        end }); deps[name], f.forbidden[name] = spy, spy
    end
    f.Player = isolated("systems/SamsaraSlicePlayer.lua", deps)
    f.Dispatcher.subscribe("session", f.Player.onSessionUpdated)
    f.options = { getSession = function() return f.Dispatcher.get("session") end,
        setSession = function(value)
            f.count("session.set"); eq(value, f.Dispatcher.get("session"), "共享session身份")
            if f.fail == "set" then error("注入通知故障") end; f.Dispatcher.set("session", value)
        end,
        flush = function()
            f.count("flush")
            if f.flushMode == "false" then return false end
            if f.flushMode == "nil" then return nil end
            if f.flushMode == "throw" then error("注入Flush故障") end
            return f.Save.Flush()
        end }
    function f.session() return assert(f.Dispatcher.get("session")) end
    function f.node() return f.session().samsaraStory.nodes[KEY] end
    function f.record() return f.Player.getRecord(KEY) end
    function f.init(battle) return f.Player.init(f.options, battle or raw or {}) end
    function f.publish(value) f.Dispatcher.handleStateUpdate(JSON.encode({ modules = { session = value } })) end
    -- 仅NanoVG边界替身：真实DrawUtil.hitTest/文字描边、UTF-8与Dialogue折行仍执行。
    f.displayed, f.drawings, f.boxes, f.tabs, f.buttons, f.dots = {}, {}, {}, {}, {}, {}
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
        "nvgRoundedRect", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgResetScissor", "nvgSkewX" }) do
        f.graphics[name] = function() end
    end
    f.I18n = { get = function() return "zh_CN" end, lookup = function(text) return text end, installDrawHook = function() end,
        displayBounds = function(_, _, _, text) return (utf8.len(text) or 0) * f.font end,
        displayText = function(_, _, _, text) f.displayed[#f.displayed + 1] = text; return text end }
    f.Story = isolated("core/I18nStory.lua", {})
    f.Display = isolated("ui/story/StoryDisplay.lua", { ["core.I18n"] = f.I18n, ["core.I18nStory"] = f.Story }, f.graphics)
    f.Bus = isolated("core/EventBus.lua", {})
    f.GameConfig = isolated("config/GameConfig.lua", {})
    f.Draw = isolated("core/DrawUtil.lua", { ["config.HeroAssetUtil"] = {} }, f.graphics)
    local realText = f.Draw.drawTextStroke
    f.Draw.drawTextStroke = function(vg, x, y, text, ...)
        f.buttons[#f.buttons + 1] = { x = x, y = y, text = text }; return realText(vg, x, y, text, ...)
    end
    f.Dialogue = isolated("ui/story/ScenarioDialogue.lua", {
        ["core.DrawUtil"] = f.Draw, ["config.GameConfig"] = f.GameConfig, ["ui.widget.HeroFrame"] = {},
        ["core.EventBus"] = f.Bus, ["core.I18n"] = f.I18n, ["core.I18nStory"] = f.Story,
        ["ui.story.StoryDisplay"] = f.Display, ["config.ScenarioDialogueConfig"] = f.Legacy, ["config.HeroAssetUtil"] = {},
    }, f.graphics)
    f.realShow = f.Dialogue.show
    f.Dialogue.show = function(cfg)
        f.shown[#f.shown + 1] = cfg
        if f.showFault == "throw" then error("注入展示故障") end
        if f.showFault == "false" then return f.realShow({ steps = {} }) end
        return f.realShow(cfg)
    end
    f.Playback = isolated("systems/SamsaraSlicePlayback.lua", {
        ["systems.SamsaraSlicePlayer"] = f.Player, ["config.SamsaraSliceConfig"] = f.Config,
        ["ui.story.ScenarioDialogue"] = f.Dialogue,
    })
    f.Panel = isolated("ui/story/SamsaraRecordPanel.lua", { ["core.DrawUtil"] = f.Draw,
        ["systems.SamsaraSlicePlayer"] = f.Player,
        ["core.DarkIcon"] = { draw = function(_, name, x, y, size)
            if name == "reddot" then f.dots[#f.dots + 1] = { x = x, y = y, size = size } end
        end, drawNine = function(_, name, x, y, w, h)
            if name == "btn" and h == 64 then f.tabs[#f.tabs + 1] = { x = x + w * 0.5, y = y + h * 0.5, width = w, height = h } end
        end } }, f.graphics)
    function f.draw(w, h)
        f.drawings, f.boxes, f.tabs, f.buttons, f.dots = {}, {}, {}, {}, {}
        f.Panel.draw({}, w or 1920, h or 1080); return table.concat(f.drawings, "\n")
    end
    function f.action(text)
        for _, button in ipairs(f.buttons) do if button.text == text and button.y > 800 then return button end end
        error("缺少实际操作按钮 " .. text)
    end
    if not noInit then f.supported = f.init(raw) end
    return f
end
local function noEvidence(f, before, label)
    local record = f.record()
    eq(record.evidenceVisible, false, label .. "不公开物证")
    eq(record.evidence, nil, label .. "无单份物证")
    eq(#record.evidences, 0, label .. "无混合物证")
    check(same(f.session().samsaraStory.evidence, before), label .. "整个物证域不变")
end
local function noRewards(f, outside, label)
    check(same(outsideStory(f.session()), outside), label .. "旧账本/教程/离线/开场字段不变")
    eq(f.Dispatcher.get("currency").gold, 123, label .. "金币不变")
    eq(f.Dispatcher.get("currency").gems, 456, label .. "宝石不变")
    eq(f.gameState.gold, 123, label .. "GameState不变")
    check(same(f.Dispatcher.get("opaqueModule"), { value = { false, 9, "保全" } }), label .. "外部未知模块不变")
    for name, count in pairs(f.calls) do if name:match("^forbidden%.") then eq(count, 0, label .. "禁止业务调用 " .. name) end end
end
local function legacy(f, reason, id) return f.Player.noteLegacyResult(id or 70, reason or "finished", f.Player.getContextEpoch()) end
local function finish(f, reason, key)
    local lease = assert(f.Player.begin(FIRST, key or KEY), "缺少真实首读租约")
    eq(f.Player.onResult(result(lease, reason or "finished")), true, "当前首读结果接受"); return lease
end
local function finishOpening(f, reason)
    local epoch = assert(f.Player.beginOpening(), "缺少真实开场链")
    for index, step in ipairs(CHAIN) do eq(f.Player.noteOpeningResult(step, "skipped", epoch), index == #CHAIN, "逐段真实前史 " .. step) end
    finish(f, reason or "skipped", OPENING)
end
local function finishDialogue(dialogue)
    local _, total = dialogue.getProgress()
    for _ = 1, total do dialogue.update(100); dialogue.advance() end
end
local function reference(f, label)
    local record = f.record()
    eq(record.status, "locked", label .. "锁定")
    eq(record.referenceOnly, true, label .. "仅参考")
    eq(record.eventTrusted, false, label .. "非可信事件")
    eq(f.Player.requestRead(KEY), false, label .. "拒绝请求")
    eq(f.Player.begin(FIRST, KEY), nil, label .. "拒绝首读")
    eq(f.Player.begin(REPLAY, KEY), nil, label .. "拒绝回看")
    eq(f.Player.onResult({ nodeKey = KEY, contextEpoch = f.Player.getContextEpoch(), playToken = 1, reason = "finished" }), false, label .. "拒绝伪结果")
    check(same(record.referenceSteps, STEPS), label .. "六步原文参考")
    check(f.Player.peekReady() ~= KEY, label .. "不自动播放")
end

local function configurationCases()
    runCase("第十KEY/精修六步/无奖无物证/无新调查依赖", function()
        local cfg = isolated("config/SamsaraSliceConfig.lua", {})
        eq(cfg.NIGHTMARE_KEY, KEY, "NIGHTMARE_KEY稳定")
        check(same(cfg.KEYS, KEYS), "九项严格前缀，仅尾部追加第十项")
        eq(cfg.CONTENT_VERSION, 1, "内容总版本不变")
        eq(cfg.get("N11"), nil, "规划编号不是读取key")
        local node = assert(cfg.get(KEY))
        eq(node.title, "还记得刚才吗", "精确标题"); eq(node.mode, "small", "small模式")
        eq(node.dependency, OPENING, "只依赖N01")
        check(same(node.steps, STEPS), "六步正文/角色/无ID远征长完全匹配精修稿")
        for _, field in ipairs({ "evidence", "reward", "rewards", "scenarioId", "onFinish", "cg", "cgPath",
            "requiredStage", "choices", "killedConfirmed", "believeDream", "dependencies" }) do eq(node[field], nil, "节点不新增 " .. field) end
        for _, step in ipairs(node.steps) do
            for _, field in ipairs({ "evidence", "reward", "rewards", "scenarioId", "cg", "cgPath", "choices" }) do eq(step[field], nil, "正文不附加 " .. field) end
            check(not includes(step.text, "N01") and not includes(step.text, "N11"), "显示正文不露节点编号")
        end
        node.steps[1].text, node.steps[2].characterId, node.dependency = "界面改写", 21, CARGO
        check(same(cfg.get(KEY).steps, STEPS), "get返回独立正文副本")
        eq(cfg.get(KEY).dependency, OPENING, "依赖副本不污染原配置")
        eq(cfg.get(OPENING).evidence, nil, "N01仍无物证")
        for _, key in ipairs({ CARGO, ORDER, PEOPLE }) do
            check(cfg.get(key).dependency ~= KEY, "调查段不被N11反锁 " .. key)
        end
        for _, id in ipairs({ "N11", "E11", KEY }) do eq(cfg.getEvidence(id), nil, "不编造证据编号 " .. id) end
        local f = fixture(nil, nil, nil, nil, true)
        eq(#f.Player.getRecords(), 10, "init前十条安全记录")
        for index, record in ipairs(f.Player.getRecords()) do eq(record.key, KEYS[index], "实际记录顺序 " .. index) end
        eq(f.Player.getRecord().key, OLD_KEYS[1], "默认仍N02")
        eq(legacy(f), false, "init前旧70安全拒绝")
        eq(f.Player.requestRead(KEY), false, "init前请求拒绝")
        eq(f.Player.begin(FIRST, KEY), nil, "init前首读拒绝")
        f.Player.cancel(); f.Player.update(2); eq(f.n("flush"), 0, "init前不写档")
    end)
    runCase("Schema只扩展已知node，版本/捕获域/物证域不变", function()
        local schema = isolated("shared/session/SamsaraStorySchema.lua", {})
        local new = schema.new()
        check(same(new, { schemaVersion = 1, historyCaptured = false, cargoHistoryCaptured = false,
            mirrorHistoryCaptured = false, mirrorHistoryVersion = 1, dragonHistoryCaptured = false,
            dragonHistoryVersion = 1, nodes = {}, evidence = {} }), "Schema.new没有新增N11捕获域")
        local session = oldArchive(); local before = oldPart(session)
        session.samsaraStory.nodes[KEY] = { eligible = "true", contentVersion = 1, resolution = "dismissed",
            manualOnly = "true", eligibilitySource = 70, legacyContext = false, unknown = { 9, false } }
        session.samsaraStory.nodes["未来节点"] = { eligible = "true", future = { keep = 7 } }
        before.nodes["未来节点"] = copy(session.samsaraStory.nodes["未来节点"])
        local story, supported = schema.normalize(session)
        eq(supported, true, "当前Schema支持")
        eq(story.nodes[KEY].eligible, false, "新增已知节点严格boolean")
        eq(story.nodes[KEY].manualOnly, false, "manualOnly严格boolean")
        eq(story.nodes[KEY].resolution, nil, "dismissed不作持久首读终态")
        eq(story.nodes[KEY].eligibilitySource, nil, "来源只接受字符串")
        eq(story.nodes[KEY].legacyContext, nil, "语境只接受字符串")
        check(same(story.nodes[KEY].unknown, { 9, false }), "未知节点字段保全")
        check(same(oldPart(session), before), "旧九项/未知节点/全部物证/域原样")
        local once = copy(session); schema.normalize(session); check(same(session, once), "normalize幂等")
    end)
end

local function sourceCases()
    for _, reason in ipairs({ "finished", "dismissed", "skipped" }) do
        for _, order in ipairs({ "70先", "N01先" }) do
            runCase("两份可信来源顺序独立 " .. order .. "/" .. reason, function()
                local f = fixture(sessionWith(false)); local outside, evidence = outsideStory(f.session()), copy(f.session().samsaraStory.evidence)
                if order == "N01先" then finishOpening(f, "finished") end
                eq(legacy(f, reason, reason == "skipped" and "70" or 70), true, "首次实时带ID旧70结果登记")
                eq(f.node().eligible, true, "实时结果建立资格")
                eq(f.node().eligibilitySource, SOURCE, "来源精确live_legacy_70")
                eq(f.node().legacyContext, reason == "skipped" and "live_skipped" or "live_finished", "旧段终态独立映射")
                eq(f.node().resolution, nil, "来源登记不冒充N11读完")
                eq(#f.shown, 0, "结果桥不直接show")
                if order == "70先" then
                    reference(f, "尚无前史")
                    eq(f.record().historyReady, false, "尚无N01守卫")
                    eq(f.Player.hasPendingRecords(), false, "锁定N11无红点")
                    local saved70 = copy(f.node()); finishOpening(f, "skipped")
                    check(same(f.node(), saved70), "后来N01处理不换写70来源")
                end
                eq(f.record().status, "pending", "两个来源齐备才待阅")
                eq(f.record().eventTrusted, true, "可信包含来源与前史")
                eq(f.record().historyReady, true, "前史守卫ready")
                check(not f.record().referenceOnly, "可信不是仅参考")
                eq(f.Player.peekReady(), KEY, "无调查处理可自动待阅")
                eq(f.Player.hasPendingRecords(), true, "真正待阅有红点")
                local frozen, writes = copy(f.node()), f.n("flush")
                for _, again in ipairs({ "finished", "dismissed", "skipped", "reset", "replaced", "failed", "未知" }) do
                    eq(legacy(f, again), false, "首份可信结果冻结，后续不改 " .. again)
                    check(same(f.node(), frozen), "冻结来源/语境不变 " .. again)
                end
                eq(f.n("flush"), writes, "重复不同reason也不写")
                noEvidence(f, evidence, "可信来源登记"); noRewards(f, outside, "可信来源登记")
            end)
        end
    end
    runCase("旧70必须明确当前epoch且ID/reason格式严格", function()
        local f = fixture(); local before, writes = copy(f.session()), f.n("flush")
        local epoch = f.Player.getContextEpoch()
        for _, call in ipairs({ { 70, "finished" }, { 70, "skipped", tostring(epoch) }, { 70, "finished", epoch - 1 },
            { 70, "finished", epoch + 1 }, { 70, "finished", false }, { "070", "finished", epoch },
            { "70.0", "finished", epoch }, { "70x", "finished", epoch }, { 70.5, "finished", epoch },
            { false, "finished", epoch }, { 69, "finished", epoch }, { 71, "finished", epoch }, { " 70", "finished", epoch } }) do
            eq(f.Player.noteLegacyResult(table.unpack(call)), false, "拒绝缺epoch/错代次/非精确ID " .. tostring(call[1]))
        end
        for _, reason in ipairs({ "reset", "replaced", "failed", "unknown", "dismiss", "Finished", "", " skipped" }) do
            eq(f.Player.noteLegacyResult(70, reason, epoch), false, "不建资格reason " .. reason)
        end
        eq(f.Player.noteLegacyResult(70, nil, epoch), false, "缺reason拒绝")
        check(same(f.session(), before), "全部拒绝不建立节点或capture")
        eq(f.n("flush"), writes, "全部拒绝不保存")
        eq(f.node(), nil, "无N11伪节点")
        eq(f.Player.noteLegacyResult("70", "skipped", epoch), true, "精确字符串70/数值当前epoch合法")
    end)
    for _, hint in ipairs({ "raw数值", "raw字符串", "最高关", "当前关", "claimed数值", "claimed字符串", "已发奖励", "开场标记", "缺旧70配置" }) do
        runCase("init不能由历史提示补造N11 " .. hint, function()
            local session = sessionWith(false); local raw, legacyCfg = {}, nil
            if hint == "raw数值" then raw.clearedStages = { [4701] = true }
            elseif hint == "raw字符串" then raw.clearedStages = { ["4701"] = true }
            elseif hint == "最高关" then raw.maxStageId = 9999
            elseif hint == "当前关" then raw.currentStageId = 4701
            elseif hint == "claimed数值" then session.claimedScenarios[70] = true
            elseif hint == "claimed字符串" then session.claimedScenarios["70"] = true
            elseif hint == "已发奖励" then session.scenarioRewardsGranted["70"] = true
            elseif hint == "缺旧70配置" then legacyCfg = isolated("config/ScenarioDialogueConfig.lua", {}); legacyCfg.SCENARIO_70 = nil end
            local before, outside = oldPart(session), outsideStory(session)
            -- Dispatcher真实onLoad把数字旧账本key归一为字符串；不是N11改账本。
            if hint == "claimed数值" then outside.claimedScenarios[70], outside.claimedScenarios["70"] = nil, true end
            local f = fixture(session, raw, nil, legacyCfg)
            check(same(outsideStory(f.session()), outside), "真实onLoad仅做预期账本键归一")
            eq(f.node(), nil, "不凭历史提示造N11")
            reference(f, "旧档提示")
            eq(f.record().historyReady, false, "开场标记不是N01处理")
            eq(f.Player.hasPendingRecords(), false, "旧档无N11红点")
            check(same(oldPart(f.session()), before), "不新增capture/不改原九项")
            noRewards(f, outside, "旧提示")
            f.init({ clearedStages = { [4701] = true }, maxStageId = 9999 })
            eq(f.node(), nil, "同表reinit不造来源")
            if legacyCfg then
                eq(legacy(f), true, "配置缺失也不抹去真实带ID结果")
                eq(f.node().eligibilitySource, SOURCE, "实际桥来源仍登记")
            end
        end)
    end
    runCase("任意CLEAR不授N11且不反锁调查链", function()
        local f = fixture(); local evidence = copy(f.session().samsaraStory.evidence)
        for _, id in ipairs({ 4701, "4701", "04701", 4702, 2705, 2505, 2905, 104, 204, 4905 }) do
            f.Player.onStageCleared(id); eq(f.node(), nil, "CLEAR不能造旧70结果 " .. tostring(id))
        end
        -- 已有案件链可独立处理，无N11/N08/N09/N10/E03前置。
        local independent = fixture(); eq(independent.Player.onStageCleared(4905), true, "调查首段独立首通")
        finish(independent, "finished", CARGO); finish(independent, "skipped", ORDER); finish(independent, "finished", PEOPLE)
        eq(independent.Player.getRecord(PEOPLE).status, "finished", "无旧70调查全部处理")
        eq(independent.node(), nil, "调查不会顺带授N11")
        noEvidence(independent, independent.session().samsaraStory.evidence, "N11自身查询不混合案件")
        check(same(evidence, {}), "初始夹具无证据")
    end)
end

local function guardCases()
    local variants = {
        { label = "无N01", node = false },
        { label = "可信pending", node = { eligible = true, contentVersion = 1, eligibilitySource = "live_opening_chain" } },
        { label = "unknown已读", node = { eligible = true, contentVersion = 1, resolution = "finished", eligibilitySource = "legacy_claimed_unknown" } },
        { label = "错误live来源", node = { eligible = true, contentVersion = 1, resolution = "skipped", eligibilitySource = "live_clear" } },
        { label = "字符串资格", node = { eligible = "true", contentVersion = 1, resolution = "finished", eligibilitySource = "live_opening_chain" } },
        { label = "不合格", node = { eligible = false, contentVersion = 1, resolution = "skipped", eligibilitySource = "live_opening_chain" } },
        { label = "未来N01", node = { eligible = true, contentVersion = 9, resolution = "finished", eligibilitySource = "live_opening_chain", unknown = { future = 8 } } },
        { label = "非持久终态", node = { eligible = true, contentVersion = 1, resolution = "dismissed", eligibilitySource = "live_opening_chain" } },
    }
    for _, variant in ipairs(variants) do
        runCase("N01守卫全入口拒绝 " .. variant.label, function()
            local f = fixture(sessionWith(variant.node)); local opening, evidence = copy(f.session().samsaraStory.nodes[OPENING]), copy(f.session().samsaraStory.evidence)
            eq(legacy(f, "skipped"), true, "无前史仍持久登记70")
            eq(f.node().eligible, true, "真实70资格保留")
            eq(f.node().eligibilitySource, SOURCE, "来源不丢")
            reference(f, "前史不支持/未处理")
            eq(f.record().historyReady, false, "historyReady精确表示N01守卫")
            check(same(f.session().samsaraStory.nodes[OPENING], opening), "桥不补造/重置N01")
            noEvidence(f, evidence, "前史锁定")
            local reboot = fixture(JSON.decode(f.disk).modules.session)
            eq(reboot.node().legacyContext, "live_skipped", "锁定来源真Save持久保留")
            reference(reboot, "锁定来源重启")
        end)
    end
    for _, openingReason in ipairs({ "finished", "skipped" }) do
        runCase("可信已处理N01两终态均放行 " .. openingReason, function()
            local session = sessionWith(); session.samsaraStory.nodes[OPENING].resolution = openingReason
            local f = fixture(session); eq(legacy(f), true, "真实70登记")
            eq(f.record().eventTrusted, true, "可信两来源")
            eq(f.record().historyReady, true, "N01守卫已满足")
            eq(f.Player.peekReady(), KEY, "不需要任何E03/镜像或其他节点")
            eq(f.session().samsaraStory.nodes[OLD_KEYS[9]], nil, "无N08前置")
            eq(f.session().samsaraStory.nodes[OLD_KEYS[7]], nil, "无N09前置")
            finish(f, "skipped"); eq(f.record().status, "skipped", "可处理N11")
        end)
    end
    for _, key in ipairs({ CARGO, ORDER, PEOPLE }) do
        for _, resolution in ipairs({ "finished", "skipped" }) do
            runCase("首次70看已processed案件即manualOnly " .. key .. "/" .. resolution, function()
                local session = oldArchive(); local expected = copy(session.samsaraStory.nodes)
                for _, part in ipairs({ CARGO, ORDER, PEOPLE }) do session.samsaraStory.nodes[part].resolution = nil end
                session.samsaraStory.nodes[key].resolution = resolution
                local f = fixture(session); expected = copy(f.session().samsaraStory.nodes)
                eq(legacy(f), true, "首次可信70")
                eq(f.node().manualOnly, true, "任一案件已处理即手动")
                check(f.Player.peekReady() ~= KEY, "不能自动倒插")
                for _, part in ipairs({ CARGO, ORDER, PEOPLE }) do check(same(f.session().samsaraStory.nodes[part], expected[part]), "不重置案件 " .. part) end
                eq(f.Player.requestRead(KEY), true, "显式补读合法")
                eq(f.Player.takeRequest().key, KEY, "只取N11请求")
                finish(f, "finished"); eq(f.record().status, "finished", "显式首读独立完成")
            end)
        end
    end
    runCase("70先登记而后实际N12处理转手动，不自动倒插", function()
        local f = fixture(); local outside = outsideStory(f.session())
        eq(legacy(f), true, "先有当前旧70可信来源")
        eq(f.node().manualOnly, nil, "案件处理前不伪造manualOnly")
        eq(f.Player.peekReady(), KEY, "案件处理前N11可自动候选")
        local frozenContext = f.node().legacyContext
        eq(f.Player.onStageCleared(4905), true, "实际首通建立N12资格")
        eq(f.Player.requestRead(CARGO), true, "显式进入真正N12，不先读N11")
        local request = assert(f.Player.takeRequest()); eq(request.key, CARGO, "精确调查请求")
        local lease = assert(f.Player.begin(request.kind, request.key))
        eq(f.Player.onResult(result(lease, "finished")), true, "真实N12首读处理")
        eq(f.node().manualOnly, true, "调查处理后持久转manualOnly")
        eq(f.node().resolution, nil, "N12处理不冒充N11已读")
        eq(f.node().legacyContext, frozenContext, "原70来源仍冻结")
        check(f.Player.peekReady() ~= KEY, "不把N11倒插到调查之后")
        eq(f.Player.getRecord(ORDER).status, "pending", "案件后段正常释放")
        local reboot = fixture(JSON.decode(f.disk).modules.session)
        eq(reboot.node().manualOnly, true, "真实Save重启保留补读模式")
        check(reboot.Player.peekReady() ~= KEY, "重启也不倒插")
        eq(reboot.Player.requestRead(KEY), true, "显式补读仍可用")
        finish(reboot, "skipped")
        eq(reboot.Player.getRecord(CARGO).status, "finished", "显式N11不重置N12")
        eq(reboot.Player.getRecord(ORDER).status, "pending", "显式N11不跳过N13")
        noRewards(reboot, outside, "先来源后实际案件")
    end)
    runCase("只有eligible/未知来源不能伪造N11可信结果", function()
        for _, source in ipairs({ "live_clear", "legacy_claimed_unknown", "legacy_raw_clear_unknown", "unavailable", "live_legacy_71" }) do
            local session = oldArchive(); session.samsaraStory.nodes[KEY] = { eligible = true, contentVersion = 1,
                resolution = "finished", eligibilitySource = source, legacyContext = "live_finished" }
            local f = fixture(session); reference(f, "来源不可信 " .. source)
            eq(f.record().historyReady, true, "N01ready不等于70可信")
            eq(legacy(f, "skipped"), true, "实际70可升级错误来源")
            eq(f.node().resolution, nil, "升级抹去伪首读结果")
            eq(f.node().legacyContext, "live_skipped", "真实skip替换未知语境")
        end
        for _, context in ipairs({ "live_interrupted", "legacy_claimed_unknown", "unavailable", "live_finish" }) do
            local session = sessionWith(); session.samsaraStory.nodes[KEY] = { eligible = true, contentVersion = 1,
                eligibilitySource = SOURCE, legacyContext = context }
            local f = fixture(session); reference(f, "没有可信旧70终态 " .. context)
        end
    end)
end

local function resultCases()
    for _, ending in ipairs({ "finished", "dismissed", "skipped" }) do
        runCase("严格租约/首读两终态/回看冻结 " .. ending, function()
            local f = fixture(oldArchive()); local old, outside, evidence = oldPart(f.session()), outsideStory(f.session()), copy(f.session().samsaraStory.evidence)
            eq(legacy(f, "skipped"), true, "来源旧70真实skip")
            local lease = assert(f.Player.begin(FIRST, KEY))
            eq(lease.nodeKey, KEY, "精确nodeKey")
            eq(lease.kind, FIRST, "首读kind")
            eq(f.Player.begin(FIRST, KEY), nil, "活动租约互斥")
            for _, field in ipairs({ "playToken", "contextEpoch", "nodeKey" }) do
                for _, bad in ipairs({ false, "错误", 9999 }) do
                    local invalid = result(lease, ending); invalid[field] = bad
                    eq(f.Player.onResult(invalid), false, "租约拒绝错误 " .. field .. "/" .. tostring(bad))
                end
                local missing = result(lease, ending); missing[field] = nil
                eq(f.Player.onResult(missing), false, "租约拒绝缺字段 " .. field)
            end
            for _, reason in ipairs({ "done", "unknown", "Skipped", "", " finished" }) do
                eq(f.Player.onResult(result(lease, reason)), false, "拒绝未知终态 " .. reason)
            end
            eq(f.record().status, "pending", "坏结果不损伤当前pending")
            eq(f.Player.onResult(result(lease, ending)), true, "精确当前结果接受")
            eq(f.record().status, ending == "skipped" and "skipped" or "finished", "持久首读映射")
            eq(f.node().legacyContext, "live_skipped", "首读不把旧70skip改称已读")
            eq(f.Player.onResult(result(lease, "finished")), false, "首读重复通知拒绝")
            local frozen, writes = copy(f.session()), f.n("flush")
            for _, replayEnding in ipairs({ "finished", "skipped", "reset" }) do
                local replay = assert(f.Player.begin(REPLAY, KEY))
                eq(f.Player.onResult(result(replay, replayEnding)), true, "回看结果接受 " .. replayEnding)
                check(same(f.session(), frozen), "回看/中断不改首读/来源 " .. replayEnding)
            end
            eq(f.n("flush"), writes, "回看不再保存")
            check(same(oldPart(f.session()), old), "旧九项完整快照不变")
            noEvidence(f, evidence, "首读与回看"); noRewards(f, outside, "首读与回看")
        end)
    end
    for _, reason in ipairs({ "reset", "replaced", "failed" }) do
        runCase("N11自身中断保pending并重启 " .. reason, function()
            local f = fixture(); eq(legacy(f), true, "登记70")
            local before, writes = copy(f.node()), f.n("flush")
            local lease = assert(f.Player.begin(FIRST, KEY))
            eq(f.Player.onResult(result(lease, reason)), true, "当前中断释放租约")
            check(same(f.node(), before), "自身中断不改70来源或首读")
            eq(f.record().status, "pending", "仍pending")
            eq(f.Player.onResult(result(lease, "finished")), false, "中断后旧结果迟到拒绝")
            eq(f.n("flush"), writes, "中断不伪造存档结果")
            local reboot = fixture(JSON.decode(f.disk).modules.session)
            eq(reboot.record().status, "pending", "真实Save重启仍待阅")
            eq(reboot.node().legacyContext, "live_finished", "重启来源保全")
            finish(reboot, "skipped"); eq(reboot.record().status, "skipped", "重启后可正常处理")
        end)
    end
    runCase("活动期间N01来源/终态撤回使result拒绝", function()
        for _, field in ipairs({ "eligible", "eligibilitySource", "resolution", "contentVersion" }) do
            local f = fixture(); eq(legacy(f), true, "实际来源")
            local lease = assert(f.Player.begin(FIRST, KEY))
            f.session().samsaraStory.nodes[OPENING][field] = field == "contentVersion" and 9 or (field == "eligible" and false or "unknown")
            local before, writes = copy(f.session()), f.n("flush")
            eq(f.Player.onResult(result(lease, "finished")), false, "运行中前史改变拒绝 " .. field)
            eq(f.Player.requestRead(KEY), false, "前史失效拒请求")
            check(same(f.session(), before), "拒绝不修复档/不写终态")
            eq(f.n("flush"), writes, "拒绝不Flush")
        end
    end)
    runCase("cancel/换档/init/getter静默换表拒绝旧70与N11迟到结果", function()
        for _, operation in ipairs({ "cancel", "init换档", "getter换表", "未知schema通知" }) do
            local f = fixture(); eq(legacy(f), true, "登记当前70")
            local lease = assert(f.Player.begin(FIRST, KEY)); local epoch = f.Player.getContextEpoch()
            if operation == "cancel" then f.Player.cancel()
            elseif operation == "init换档" then f.Dispatcher.set("session", sessionWith()); f.init()
            elseif operation == "getter换表" then
                -- set会同步通知onSessionUpdated，不能冒充静默换档；此处只切getter的实际返回表。
                local other = sessionWith()
                f.options.getSession = function() return other end
            else local future = sessionWith(); future.samsaraStory.schemaVersion = 99; f.publish(future) end
            local before, writes = copy(f.session()), f.n("flush")
            local getterBefore = copy(f.options.getSession())
            eq(f.Player.onResult(result(lease, "finished")), false, "拒绝旧租约 " .. operation)
            eq(f.Player.noteLegacyResult(70, "skipped", epoch), false, "拒绝旧70桥 " .. operation)
            check(same(f.session(), before), "迟到不污染原Dispatcher档")
            check(same(f.options.getSession(), getterBefore), "迟到不污染getter实际返回档")
            eq(f.n("flush"), writes, "迟到不保存")
        end
        local f = fixture(); local epoch = f.Player.getContextEpoch()
        -- 合法同游戏onLoad重附不是清档，可接受宿主捕获的同一代次。
        f.publish(copy(f.session()))
        eq(f.Player.getContextEpoch(), epoch, "合法同档重附保留代次")
        eq(f.Player.noteLegacyResult(70, "skipped", epoch), true, "合法重附70结果有效")
    end)
end

local function futureCases()
    for _, version in ipairs({ 2, "9" }) do
        runCase("未来Schema原样保全且全入口拒绝 " .. tostring(version), function()
            local session = oldArchive(); session.samsaraStory.schemaVersion = version
            session.samsaraStory.nodes[KEY] = { eligible = "future", contentVersion = 12, legacyContext = { future = true }, unknown = { 1, false } }
            session.samsaraStory.evidence.futureN11 = { unlocked = "future", source = false }
            local before = copy(session)
            local f = fixture(session)
            eq(f.supported, false, "未来Schema不支持")
            eq(f.record().status, "unsupported", "未来不展示为pending")
            eq(legacy(f), false, "未来拒旧70")
            eq(f.Player.requestRead(KEY), false, "未来拒请求")
            eq(f.Player.begin(FIRST, KEY), nil, "未来拒首读")
            eq(f.Player.begin(REPLAY, KEY), nil, "未来拒回看")
            f.Player.onStageCleared(4701); f.Player.update(100)
            check(same(f.session(), before), "未来全部字段/物证原样")
            eq(f.n("flush"), 0, "未来不写")
            noEvidence(f, before.samsaraStory.evidence, "未来Schema")
        end)
        runCase("未来N11content保全且其他旧节点仍工作 " .. tostring(version), function()
            local session = oldArchive(); session.samsaraStory.nodes[KEY] = { eligible = "future", contentVersion = version,
                resolution = "future-resolution", legacyContext = { future = true }, unknown = { 1, false } }
            local f = fixture(session); local before, writes = copy(f.session()), f.n("flush")
            eq(f.record().status, "unsupported", "未来内容不支持")
            eq(legacy(f), false, "不覆盖未来70来源")
            eq(f.Player.requestRead(KEY), false, "未来内容拒请求")
            eq(f.Player.begin(FIRST, KEY), nil, "未来内容拒首读")
            eq(f.Player.begin(REPLAY, KEY), nil, "未来内容拒回看")
            check(same(f.session(), before), "未来内容节点和所有物证保全")
            eq(f.n("flush"), writes, "未来内容不写")
            local replay = assert(f.Player.begin(REPLAY, CARGO)); eq(f.Player.onResult(result(replay, "skipped")), true, "旧调查仍可回看")
            noEvidence(f, before.samsaraStory.evidence, "未来内容不混合")
        end)
    end
    runCase("活动租约与dirty之后收到未来内容仍不降级重写", function()
        local f = fixture(); eq(legacy(f), true, "真实来源")
        local lease = assert(f.Player.begin(FIRST, KEY)); f.flushMode = "false"
        eq(f.Player.onResult(result(lease, "skipped")), true, "失败保存保内存终态")
        local future = copy(f.session()); future.samsaraStory.nodes[KEY].contentVersion = 99
        future.samsaraStory.nodes[KEY].resolution = "future-resolution"
        f.publish(future); local before = copy(f.session())
        eq(f.Player.onResult(result(lease, "finished")), false, "未来活动迟到拒绝")
        eq(legacy(f, "finished"), false, "未来不覆盖语境")
        f.flushMode = "real"; f.Player.update(2)
        check(same(f.session(), before), "dirty重试不能改未来内容")
    end)
    for _, fault in ipairs({ "missing", "empty", "throw", "evidence", "rewards" }) do
        runCase("N11定义缺失或违规不能凭70放行 " .. fault, function()
            local cfg = isolated("config/SamsaraSliceConfig.lua", {}); local get = cfg.get
            cfg.get = function(key, source)
                if key ~= KEY then return get(key, source) end
                if fault == "missing" then return nil end
                if fault == "throw" then error("注入配置读取故障") end
                local node = get(key, source)
                if fault == "empty" then node.steps = {}
                elseif fault == "evidence" then node.evidence = { id = "伪E11", title = "伪物证", text = "伪物证" }
                else node.rewards = {} end
                return node
            end
            local f = fixture(nil, nil, cfg); local before = copy(f.session())
            eq(legacy(f), false, "错误定义拒资格")
            eq(f.Player.requestRead(KEY), false, "错误定义拒请求")
            eq(f.Player.begin(FIRST, KEY), nil, "错误定义拒首读")
            check(same(f.session(), before), "错误定义不造节点或物证")
        end)
    end
    for _, key in ipairs({ OLD_KEYS[1], CARGO, ORDER, PEOPLE, OLD_KEYS[5], OLD_KEYS[6], OLD_KEYS[7], OLD_KEYS[9] }) do
        runCase("无物证窄豁免不扩散旧节点 " .. key, function()
            local cfg = isolated("config/SamsaraSliceConfig.lua", {}); local get = cfg.get
            cfg.get = function(requested, source)
                local node = get(requested, source); if requested == key and node then node.evidence = nil end; return node
            end
            local f = fixture(oldArchive(), nil, cfg)
            eq(f.Player.getRecord(key).status, "unsupported", "旧节点缺物证仍不支持")
            eq(f.Player.requestRead(key), false, "缺物证旧节点不请求")
            eq(f.Player.begin(REPLAY, key), nil, "缺物证旧节点不回看")
            eq(legacy(f), true, "N11合法无物证仍支持")
            eq(f.record().status, "pending", "只有N01/N11豁免")
        end)
    end
end

local function saveCases()
    for _, phase in ipairs({ "来源", "首读" }) do
        for _, fault in ipairs({ "set", "encode", "open", "write", "partial", "close", "rename", "false", "nil", "throw" }) do
            runCase("真实Flush内存原子提交/2秒重试 " .. phase .. "/" .. fault, function()
                local f = fixture(); local outside, evidence = outsideStory(f.session()), copy(f.session().samsaraStory.evidence)
                eq(f.Save.Flush(), true, "真Flush建立内存档基线")
                if phase == "首读" then eq(legacy(f), true, "先真提交70来源") end
                local beforeDisk, writes = f.disk, f.n("flush")
                if fault == "false" or fault == "nil" or fault == "throw" then f.flushMode = fault else f.fail = fault end
                if phase == "来源" then eq(legacy(f, "skipped"), true, "失败也保真实来源")
                else finish(f, "skipped") end
                eq(f.record().status, phase == "来源" and "pending" or "skipped", "内存终态正确")
                eq(f.Player.isSavePending(), true, "非true均dirty")
                eq(f.disk, beforeDisk, "失败不改已提交内存档")
                eq(f.n("flush"), writes + (fault == "set" and 0 or 1), "一次失败只尝试一次")
                local reboot = fixture(JSON.decode(beforeDisk).modules.session)
                if phase == "来源" then eq(reboot.node(), nil, "失败来源重启不能臆造")
                else eq(reboot.record().status, "pending", "失败首读重启仍pending") end
                local attempts = f.n("flush")
                f.Player.cancel(); f.init(); eq(f.Player.isSavePending(), true, "cancel/同表init保dirty")
                f.Player.update(-1); f.Player.update(0 / 0); f.Player.update(math.huge)
                f.Player.update(1); f.Player.update(0.999)
                eq(f.n("flush"), attempts, "非法dt及2秒前无热循环")
                f.Player.update(0.001)
                eq(f.n("flush"), attempts + (fault == "set" and 0 or 1), "恰好2秒一次重试")
                eq(f.Player.isSavePending(), true, "失败重试仍dirty")
                f.fail, f.flushMode = "", "real"; f.Player.update(2)
                eq(f.Player.isSavePending(), false, "只有真Flush成功清dirty")
                local saved = JSON.decode(f.disk).modules.session.samsaraStory.nodes[KEY]
                eq(saved.eligibilitySource, SOURCE, "磁盘来源精确")
                eq(saved.legacyContext, phase == "来源" and "live_skipped" or "live_finished", "磁盘旧70首份来源")
                eq(saved.resolution, phase == "首读" and "skipped" or nil, "磁盘首读终态")
                eq(f.Save.RestoreData(), true, "真Save/Dispatcher内存恢复")
                f.init(); local done = f.n("flush"); f.Player.update(100)
                eq(f.n("flush"), done, "成功不再重试")
                noEvidence(f, evidence, "故障恢复"); noRewards(f, outside, "故障恢复")
            end)
        end
    end
end

local function presentationCases()
    for _, variant in ipairs({ { label = "nil" }, { label = "中断", value = "live_interrupted" },
        { label = "不可用", value = "unavailable" } }) do
        runCase("真实Panel拒绝来源标记冒充旧70终态 " .. variant.label, function()
            local session = sessionWith()
            session.samsaraStory.nodes[KEY] = { eligible = true, contentVersion = 1,
                eligibilitySource = SOURCE, legacyContext = variant.value, resolution = "finished" }
            local f = fixture(session); local before, writes = copy(f.session()), f.n("flush")
            reference(f, "异常来源语境")
            f.Panel.selectRecord(KEY); f.Panel.open(); local text = f.draw()
            check(includes(text, "旧70实际处理来源尚未确认"), "明确显示来源未确认")
            check(includes(text, "亲历状态未确认"), "仍为静态参考")
            check(not includes(text, "来源：旧70的实时带ID完成记录"), "source单独不冒充完成")
            check(not includes(text, "来源：旧70已在实时带ID结果中跳过"), "异常context不冒充跳过")
            check(not includes(text, "旧70梦境已处理"), "异常context不称梦境已处理")
            eq(f.record().eventTrusted, false, "双条件不满足则不可信")
            eq(#f.dots, 0, "伪终态无待阅红点")
            local action = f.action("仅供查阅")
            eq(f.Panel.handleInput(action.x, action.y, 1920, 1080), true, "参考按钮吞输入")
            eq(f.Player.takeRequest(), nil, "不排任何读取")
            check(same(f.session(), before), "异常档展示不擅修来源/终态")
            eq(f.n("flush"), writes, "异常展示不保存")
        end)
    end
    runCase("真实DrawUtil边界/十标签全点击/长文滚动/touch不穿透", function()
        local f = fixture(sessionWith(false)); eq(legacy(f, "skipped"), true, "无N01先登记70")
        local before, writes = copy(f.session()), f.n("flush")
        local requests, realRequest = 0, f.Player.requestRead
        f.Player.requestRead = function(key) requests = requests + 1; return realRequest(key) end
        for _, size in ipairs({ { 1920, 1080 }, { 2340, 1080 }, { 1280, 800 }, { 1080, 1920 } }) do
            local w, h = size[1], size[2]; local scale = math.min(w / 1920, h / 1080)
            f.Panel.selectRecord(KEY); f.Panel.open(); local text = f.draw(w, h)
            eq(#f.tabs, 10, "实际绘制十个标签")
            check(includes(text, "刚才的梦"), "第十标签精确")
            eq(#f.dots, 0, "无前史锁定来源没有红点")
            for index, tab in ipairs(f.tabs) do
                check(tab.x - tab.width * 0.5 >= 0 and (tab.x + tab.width * 0.5) * scale <= w, "标签不越界 " .. index)
                if index > 1 then check(tab.x - f.tabs[index - 1].x > tab.width, "标签不重叠 " .. index) end
            end
            -- 不重算生产layout：直接以实际DarkIcon drawNine捕获边界驱动真实DrawUtil.hitTest。
            local actualTabs = copy(f.tabs)
            for index, tab in ipairs(actualTabs) do
                eq(f.Panel.handleInput(tab.x * scale, tab.y * scale, w, h), true, "实际标签点击吞输入 " .. index)
                check(includes(f.draw(w, h), f.Config.get(KEYS[index]).title), "实际选中准确key " .. index)
            end
            f.Panel.selectRecord(KEY); text = f.draw(w, h)
            for _, step in ipairs(STEPS) do check(includes(text, step.text), "静态参考完整精修稿") end
            check(includes(text, "口粮") and includes(text, "纪念罐"), "分食口粮与未开纪念罐区分")
            check(includes(text, "旧70") and includes(text, "跳过"), "旧70已跳过不称看过")
            check(not includes(text, "旧70已读") and not includes(text, "旧70已看过"), "旧70skip标签不虚构已读")
            for _, id in ipairs({ "E02", "E05", "E03" }) do check(not includes(text, id), "N11独立内容不露 " .. id) end
            local tab = actualTabs[10]
            eq(f.Draw.hitTest(tab.x - tab.width * 0.5, tab.y, tab.x, tab.y, tab.width, tab.height), true, "真实DrawUtil边缘包含")
            eq(f.Draw.hitTest(tab.x - tab.width * 0.5 - 0.01, tab.y, tab.x, tab.y, tab.width, tab.height), false, "真实DrawUtil边缘外拒绝")
            local action = f.action("仅供查阅")
            eq(f.Panel.handleInput(action.x * scale, action.y * scale, w, h), true, "参考操作吞输入")
            eq(f.Panel.handleInput(0, 0, w, h), true, "全窗遮罩吞输入")
            eq(f.Panel.isOpen(), true, "参考按钮不关闭/不排播放")
        end
        f.Panel.selectRecord(KEY); f.draw(); local first = copy(f.boxes[1])
        eq(f.Panel.handleWheel(-2), true, "长文滚轮吞输入")
        f.draw(); check(f.boxes[1].y < first.y, "滚轮确实移动正文")
        f.Panel.handleWheel(100000); f.draw(); eq(f.boxes[1].y, first.y, "顶部clamp")
        eq(f.Panel.handleDragBegin(first.x + 50, first.y + 80), true, "实际touch begin吞掉")
        eq(f.Panel.handleDragMove(first.x + 50, first.y - 180), true, "实际touch move吞掉")
        eq(f.Panel.handleDragEnd(), true, "真实拖动不是点击")
        local action = f.action("仅供查阅")
        eq(f.Panel.handleInput(action.x, action.y, 1920, 1080), true, "拖后操作点击吞掉")
        f.draw(); check(f.boxes[1].y < first.y, "touch确实滚动")
        f.Panel.selectRecord(KEY); f.draw(); eq(f.boxes[1].y, first.y, "重新选择复位滚动")
        eq(requests, 0, "参考/拖动/标签全不请求")
        eq(f.n("flush"), writes, "参考UI不保存")
        check(same(f.session(), before), "参考UI不改档")
    end)
    for _, ending in ipairs({ "dismissed", "skipped", "reset", "replaced", "false", "throw" }) do
        runCase("真实Playback/Dialogue首读结束与自身中断 " .. ending, function()
            local f = fixture(oldArchive()); local outside, old, evidence = outsideStory(f.session()), oldPart(f.session()), copy(f.session().samsaraStory.evidence)
            eq(legacy(f, "skipped"), true, "实时旧70已跳过")
            f.Panel.selectRecord(KEY); f.Panel.open(); f.draw()
            local action = f.action("待阅"); f.Panel.handleInput(action.x, action.y, 1920, 1080)
            eq(f.Dialogue.isActive(), false, "Panel只排请求不同步show")
            for _, name in ipairs({ "ready", "legacyPending", "blocked", "pointerBusy" }) do
                local g = gates(); g[name] = name ~= "ready"
                eq(f.Playback.tryPlay(g), false, "各门禁保留请求 " .. name)
            end
            if ending == "false" or ending == "throw" then f.showFault = ending end
            eq(f.Playback.tryPlay(gates()), ending ~= "false" and ending ~= "throw", "下帧真实展示")
            local cfg = assert(f.shown[1]); check(same(cfg.steps, STEPS), "真实show精修六步")
            eq(cfg.completionToken.nodeKey, KEY, "show带N11独立租约")
            eq(cfg.onFinish, nil, "N11无经济完成回调")
            eq(cfg.scenarioId, nil, "N11无旧奖励编号")
            if ending ~= "false" and ending ~= "throw" then
                f.Dialogue.update(100); f.Dialogue.draw(1920, 1080)
                check(includes(table.concat(f.drawings), "跳过 · 保留记录"), "N11skip标签只称记录")
                check(not includes(table.concat(f.drawings), "跳过 · 保留夹页"), "无虚构夹页")
                check(includes(table.concat(f.displayed), STEPS[1].text), "真实中文折行显示完整首旁白")
            end
            if ending == "dismissed" then
                finishDialogue(f.Dialogue); eq(f.record().status, "pending", "退出动画前不处理")
                f.Dialogue.update(0.29); eq(f.record().status, "pending", "退出阈值之前不处理")
                f.Dialogue.update(0.02)
            elseif ending == "skipped" then eq(f.Dialogue.handleSliceInput(1800, 130, 1920, 1080), true, "实际横屏skip触摸")
            elseif ending == "reset" then f.Dialogue.reset()
            elseif ending == "replaced" then f.realShow({ mode = "small", steps = f.Config.get(OLD_KEYS[1]).steps }); f.Dialogue.reset() end
            local success = ending == "dismissed" or ending == "skipped"
            eq(f.record().status, success and (ending == "skipped" and "skipped" or "finished") or "pending", "真实结果终态")
            eq(#f.shown, 1, "完成回调不递归show")
            if success then
                f.Panel.open(); local text = f.draw()
                check(includes(text, "旧70") and includes(text, "跳过"), "处理后仍显示旧70真实skip")
                for _, id in ipairs({ "E02", "E05", "E03" }) do check(not includes(text, id), "处理后不混入物证 " .. id) end
                local before, writes = copy(f.session()), f.n("flush")
                action = f.action("回看"); f.Panel.handleInput(action.x, action.y, 1920, 1080)
                eq(f.Playback.tryPlay(gates()), true, "真实回看播放")
                eq(f.shown[2].completionToken.kind, REPLAY, "真实回看kind")
                f.Dialogue.skip(); check(same(f.session(), before), "回看零持久变化")
                eq(f.n("flush"), writes, "回看零保存")
            end
            check(same(oldPart(f.session()), old), "展示不改旧九项")
            noEvidence(f, evidence, "真实展示"); noRewards(f, outside, "真实展示")
        end)
    end
    runCase("N01同用保留记录skip标签且N11保存中输入禁用", function()
        local f = fixture(sessionWith(false)); finishOpening(f, "finished")
        local lease = assert(f.Player.begin(REPLAY, OPENING))
        f.Dialogue.show({ mode = "small", steps = f.Config.get(OPENING).steps, completionToken = lease,
            onResult = function(value) f.Player.onResult(value) end })
        f.Dialogue.update(100); f.Dialogue.draw(1920, 1080)
        check(includes(table.concat(f.drawings), "跳过 · 保留记录"), "N01仍保留记录")
        check(not includes(table.concat(f.drawings), "跳过 · 保留夹页"), "N01也无夹页")
        f.Dialogue.skip(); eq(legacy(f), true, "后来真实70")
        f.flushMode = "false"; finish(f, "skipped")
        f.Panel.selectRecord(KEY); f.Panel.open(); f.draw()
        local before = copy(f.session()); local action = f.action("保存中")
        eq(f.Panel.handleInput(action.x, action.y, 1920, 1080), true, "保存中操作吞输入")
        eq(f.Panel.isOpen(), true, "保存中不关闭")
        eq(f.Player.takeRequest(), nil, "保存中不排回看")
        check(same(f.session(), before), "保存中按钮不改档")
    end)
end

-- dragon高层宿主夹具：真实Standalone/Boot/标题/Letter/Dialogue，不替换宿主源码或核心仲裁。
-- 旧队列/经济/其他页面仅边界spy；用于观察旧70带ID结果、FOLLOW与下一安全帧。
local function bindStandalone(f, realStory)
    local h = { modules = {}, oldQueue = {}, clientQueue = {}, followQueue = {}, notes = {}, actions = {},
        notifications = {}, enqueued = {}, clearHooks = {}, backfills = 0, bootRuns = 0, flags = {} }
    f.Dispatcher.set("player", assert(f.Registry.find("player")).getDefault())
    f.Dispatcher.set("heroes", { roster = { [1] = { level = 1 }, [2] = { level = 1 }, [3] = { level = 1 } }, deployed = { 1, 2, 3 } })
    eq(f.Dispatcher.hasData(), true, "真实宿主核心数据齐全 " .. f.Dispatcher.getMissingRequiredModules())
    local function page(name)
        return setmetatable({}, { __index = function(_, method)
            return function()
                if method == "isOpen" or method == "isVisible" or method == "isActive" or method == "isPlaying" then return h.flags[name] == true end
                return false
            end
        end })
    end
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
    modules["core.GameState"] = setmetatable({ getName = function() return "内存宿主" end, reset = function() end },
        { __index = function(_, method) return function() f.count("host.economy." .. tostring(method)); return 0 end end })
    modules["ui.character.panel.CharacterPanel"] = setmetatable({ isHeroesDataApplied = function() return true end,
        getDeployedTeam = function() return {} end, getTotalPower = function() return 0 end,
    }, { __index = function() return function() return false end end })
    modules["ui.hud.BottomNav"] = setmetatable({ getSelectedIndex = function() return 3 end }, { __index = function() return function() return false end end })
    modules["ui.battle.scene.BattleScene"] = setmetatable({ getMaxStageId = function() return 101 end,
        getStageId = function() return 101 end, getClearedStages = function() return {} end,
        isStoryTransitionBusy = function() return h.transitionBusy == true end,
        setOnFirstClear = function(fn) h.clearHooks[#h.clearHooks + 1] = fn end,
    }, { __index = function() return function() return false end end })
    modules["runtime.ClientMessageHandler"] = setmetatable({
        consumePendingScenarioDialogue = function() return table.remove(h.clientQueue, 1) end,
        consumePendingFollowUpDialogue = function() return table.remove(h.followQueue, 1) end,
        hasPendingScenarioDialogue = function() return h.pendingClaim == true end,
        hasPendingFollowUpDialogue = function() return h.pendingFollow == true end,
        setPendingTutorialNotify = function(id) h.notifications[#h.notifications + 1] = id end,
    }, { __index = function() return function() return false end end })
    modules["systems.StoryPlayer"] = setmetatable({ take = function() return table.remove(h.oldQueue, 1) end,
        backfillCleared = function() h.backfills = h.backfills + 1 end,
        followOf = function(id) return id == 23 and 24 or nil end,
        enqueue = function(id) h.enqueued[#h.enqueued + 1] = id; h.oldQueue[#h.oldQueue + 1] = { scenarioId = id, config = f.Legacy["SCENARIO_" .. tostring(id)] } end,
        onStage = function(id, trigger) h.lastStoryStage = { id, trigger } end,
    }, { __index = function() return function() return false end end })
    if realStory then
        -- 原样加载真实进关表/排队器；只有观察计数包装，不替代onStage/take/follow业务。
        h.StoryPlayer = isolated("systems/StoryPlayer.lua", { ["runtime.ClientDispatcher"] = f.Dispatcher,
            ["config.ScenarioDialogueConfig"] = f.Legacy })
        local backfill = h.StoryPlayer.backfillCleared
        h.StoryPlayer.backfillCleared = function() h.backfills = h.backfills + 1; return backfill() end
        modules["systems.StoryPlayer"] = h.StoryPlayer
    end
    modules["systems.TutorialManager"] = setmetatable({ canPlayPendingStory = function() return h.tutorialAllows ~= false end,
        isActive = function() return h.tutorialActive == true end,
    }, { __index = function() return function() return false end end })
    modules["rules.offline.OfflineService"] = { CalcOnEnter = function() return nil end,
        HasPendingRewards = function() return h.offlinePending == true end }
    modules["runtime.GameAction"] = { sendAction = function(action, params)
        h.actions[#h.actions + 1] = { action = action, params = copy(params) }; return true
    end }
    modules["config.StageConfig"] = { getNextStageId = function() return nil end, isTerminalTemple = function() return false end, getStage = function() return nil end }
    modules["systems.LootBoxSystem"] = setmetatable({ consolidateSeeds = function() end, getTotalCount = function() return 0 end },
        { __index = function() return function() return false end end })
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
        assert(name ~= "rules.character.PlayerDataManager", "宿主不加载真实PDM")
        if not modules[name] then modules[name] = page(name) end; return modules[name]
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
    h.frame(); eq(h.bootRuns, 1, "真实bootWiring调用Boot.run一次")
    eq(#h.clearHooks, 1, "真实Boot首通回调仍接线")
    eq(h.Title.isOpen(), true, "真实标题打开")
    eq(h.Title.isReady(), true, "真实boot queue可入场")
    h.Title.handleTap()
    for _ = 1, 8 do if not h.Title.isOpen() then break end; h.frame(0.1) end
    eq(h.Title.isOpen(), false, "真实小帧淡出标题")
    h.frame(); eq(h.Letter.isOpen(), false, "旧开场标记不制造前史")
    eq(h.backfills, 1, "真实hasData后的安全补播")
    return h
end

local function hostCases()
    runCase("真实StoryPlayer进4701->旧70->下一安全帧N11，无虚构FOLLOW70", function()
        local f = fixture(); local h = bindStandalone(f, true)
        local outside, evidence = outsideStory(f.session()), copy(f.session().samsaraStory.evidence)
        eq(h.StoryPlayer.followOf(70), nil, "真实FOLLOW表无70到71")
        h.StoryPlayer.onStage(4701, "enter")
        eq(#f.shown, 0, "真实进关只排旧队列")
        h.frame(); eq(#f.shown, 1, "安全帧消耗真实take旧70")
        eq(f.shown[1].completionToken.nodeKey, "legacy.70", "进4701的真实绑定确为70")
        check(same(f.shown[1].steps, f.Legacy.SCENARIO_70.steps), "原旧70完整正文")
        eq(f.node(), nil, "进关/preclaim不冒充70处理")
        f.Dialogue.skip()
        eq(#f.shown, 1, "旧70结果不递归N11")
        eq(f.node().legacyContext, "live_skipped", "真宿主带ID桥建立skip来源")
        eq(h.StoryPlayer.take(), nil, "旧70无FOLLOW71插队")
        h.pointerBusy = true; h.frame(); eq(#f.shown, 1, "实际pointer忙阻N11")
        h.pointerBusy = false; h.frame(); eq(#f.shown, 2, "下一安全帧才启动N11")
        eq(f.shown[2].completionToken.nodeKey, KEY, "真实路径到N11独立key")
        check(same(f.shown[2].steps, STEPS), "真实N11精修六步")
        f.Dialogue.skip(); h.frame(); eq(#f.shown, 2, "N11处理后无递归后段")
        eq(#h.actions, 1, "仅旧70原领奖回调")
        eq(h.actions[1].params.scenarioId, 70, "不复制N11奖励")
        eq(#h.notifications, 1, "仅旧70原教程通知")
        outside.claimedScenarios["70"] = true
        noEvidence(f, evidence, "真实进关N11"); noRewards(f, outside, "真实进关N11")
    end)
    for _, ending in ipairs({ "finished", "skipped", "reset" }) do
        runCase("真实宿主旧70带ID结果->下一帧N11 " .. ending, function()
            local f = fixture(); local h = bindStandalone(f)
            eq(#f.shown, 0, "入场不凭旧标记启动N11")
            local outside, evidence = outsideStory(f.session()), copy(f.session().samsaraStory.evidence)
            h.oldQueue[#h.oldQueue + 1] = { scenarioId = 70, config = f.Legacy.SCENARIO_70 }
            h.frame(); eq(#f.shown, 1, "真实宿主消费旧70")
            local cfg = assert(f.shown[1]); check(same(cfg.steps, f.Legacy.SCENARIO_70.steps), "保留真实旧70十步歧义")
            eq(cfg.completionToken.nodeKey, "legacy.70", "旧70自己的身份")
            check(type(cfg.onFinish) == "function", "旧领奖回调仍仅在旧段")
            eq(f.session().claimedScenarios["70"], true, "宿主旧preclaim不是已读来源")
            eq(f.node(), nil, "旧70活动中没有N11资格")
            if ending == "finished" then finishDialogue(f.Dialogue)
            elseif ending == "skipped" then f.Dialogue.skip() else f.Dialogue.reset() end
            eq(#h.notes, 1, "宿主结果桥一次")
            eq(h.notes[1].id, 70, "桥精确旧70ID")
            eq(h.notes[1].reason, ending, "桥真实reason")
            eq(type(h.notes[1].epoch), "number", "桥明确捕获数值epoch")
            eq(#f.shown, 1, "结果回调从不递归启动N11")
            if ending == "reset" then
                eq(f.node(), nil, "旧70中断不登记资格")
                h.frame(); eq(#f.shown, 1, "中断后下帧仍不展示")
                eq(f.Player.requestRead(KEY), false, "中断旧70不能显式绕过")
            else
                eq(f.node().legacyContext, ending == "skipped" and "live_skipped" or "live_finished", "旧70结果只建立来源")
                eq(f.record().status, "pending", "旧70结束不是N11结束")
                h.pointerBusy = true; h.frame(); eq(#f.shown, 1, "按压优先阻止新段")
                h.pointerBusy = false; h.frame(); eq(#f.shown, 2, "下一安全帧N11")
                check(same(f.shown[2].steps, STEPS), "宿主用真实N11六步")
                eq(f.shown[2].completionToken.nodeKey, KEY, "宿主N11独立token")
                eq(f.shown[2].onFinish, nil, "N11无经济/FOLLOW/教程回调")
                f.Dialogue.skip(); local before, actions, notes = copy(f.session()), #h.actions, #h.notifications
                eq(f.Player.requestRead(KEY), true, "宿主请求回看")
                h.frame(); f.Dialogue.skip()
                check(same(f.session(), before), "宿主回看冻结旧70与首读")
                eq(#h.actions, actions, "N11回看不领奖")
                eq(#h.notifications, notes, "N11回看不推进教程")
            end
            eq(#h.actions, ending == "reset" and 0 or 1, "只有旧70正常结束保留原奖回调")
            for _, action in ipairs(h.actions) do
                eq(action.action, "claim_scenario_reward", "经济spy只允许旧领奖")
                eq(action.params.scenarioId, 70, "只允许旧70奖")
                eq(action.params.preClaimed, true, "旧预标记领奖约定保留")
            end
            outside.claimedScenarios["70"] = true
            noEvidence(f, evidence, "宿主N11"); noRewards(f, outside, "宿主N11")
            for name, count in pairs(f.calls) do if name:match("^host%.economy%.") then eq(count, 0, "未执行真实经济 " .. name) end end
        end)
    end
    runCase("真实宿主旧队列/client/合法FOLLOW比N11优先，奖励教程不复制", function()
        local f = fixture(); local h = bindStandalone(f)
        h.clientQueue[1] = { scenarioId = 70, config = f.Legacy.SCENARIO_70 }
        h.followQueue[1] = { scenarioId = 72, config = f.Legacy.SCENARIO_72 }
        h.oldQueue[1] = { scenarioId = 23, config = f.Legacy.SCENARIO_23 }
        h.frame(); eq(f.shown[1].completionToken.nodeKey, "legacy.70", "旧client队列优先")
        f.Dialogue.skip(); eq(#f.shown, 1, "旧70结果只登记")
        eq(#h.enqueued, 0, "旧70没有FOLLOW71")
        eq(h.notifications[1], 70, "真实宿主原旧教程通知")
        local order = { 72, 23, 24 }
        for index, id in ipairs(order) do
            h.frame(); eq(f.shown[index + 1].completionToken.nodeKey, "legacy." .. id, "旧FOLLOW/StoryPlayer队列优先 " .. id)
            f.Dialogue.skip(); eq(#f.shown, index + 1, "旧段回调不递归N11")
        end
        eq(h.enqueued[1], 24, "只有真实城镇23到24的FOLLOW")
        eq(#h.actions, 4, "旧四段原领奖保留")
        h.frame(); eq(f.shown[5].completionToken.nodeKey, KEY, "旧队列消化后N11")
        f.Dialogue.skip(); eq(#h.actions, 4, "N11不增加奖励")
        eq(#h.notifications, 4, "N11不增加教程")
        eq(#h.enqueued, 1, "N11不增加FOLLOW")
    end)
    runCase("真实宿主各模态/待领奖/教程/按压仲裁不吞N11请求", function()
        local f = fixture(); local h = bindStandalone(f); eq(legacy(f), true, "实时来源")
        eq(f.Player.requestRead(KEY), true, "显式请求待下帧")
        for _, name in ipairs({ "ui.hud.popup.RewardPopup", "ui.hud.popup.OfflineRewardPanel", "ui.hud.popup.UpdateNoticePopup",
            "ui.hud.popup.LevelUpPopup", "ui.hud.popup.PlayerInfoPanel", "ui.hud.popup.RedeemCodePanel",
            "ui.battle.stage.StageSelectDialog", "ui.battle.popup.DamageStatsPanel", "ui.battle.popup.TerminalConfirmDialog",
            "ui.dev.CEPanel", "ui.character.equip.EquipmentDetail" }) do
            -- 只控真实require的边界对象；不存在的名称会由下面覆盖检查发现，避免虚构门禁。
            check(h.modules[name] ~= nil, "宿主实际加载此模态 " .. name)
            h.flags[name] = true; h.frame(); eq(#f.shown, 0, "真实模态优先 " .. name); h.flags[name] = false
        end
        for _, flag in ipairs({ "pointerBusy", "pendingClaim", "pendingFollow", "offlinePending", "tutorialActive", "transitionBusy" }) do
            h[flag] = true; h.frame(); eq(#f.shown, 0, "真实安全门禁 " .. flag); h[flag] = false
        end
        h.tutorialAllows = false; h.frame(); eq(#f.shown, 0, "教程canPlayPendingStory优先")
        h.tutorialAllows = true; f.Panel.open(); h.frame(); eq(#f.shown, 0, "记录页模态优先")
        f.Panel.close(); h.frame(); eq(#f.shown, 1, "释放门禁原N11请求仍在")
        eq(f.shown[1].completionToken.nodeKey, KEY, "没有排错key")
        f.Dialogue.skip(); eq(#h.actions, 0, "全部N11门禁过程不领奖")
    end)
    runCase("真实宿主旧70回调换档迟到不授新档", function()
        local f = fixture(); local h = bindStandalone(f)
        h.oldQueue[1] = { scenarioId = 70, config = f.Legacy.SCENARIO_70 }; h.frame()
        local cfg = assert(f.shown[1]); local epoch = f.Player.getContextEpoch()
        f.Player.cancel(); f.Dispatcher.set("session", sessionWith()); f.init()
        local before = copy(f.session()); f.Dialogue.reset()
        cfg.onResult({ nodeKey = "legacy.70", reason = "finished" })
        eq(f.node(), nil, "宿主闭包旧epoch不会授新档")
        check(same(f.session(), before), "迟到不改新档")
        check(f.Player.getContextEpoch() ~= epoch, "清档代次已变化")
        h.frame(); eq(#f.shown, 1, "下帧也不补造N11")
    end)
end

function Start()
    local ok, err = pcall(function()
        assert(type(JSON) == "table" and type(JSON.encode) == "function" and type(JSON.decode) == "function", "需要真实cjson")
        configurationCases(); sourceCases(); guardCases(); resultCases(); futureCases(); saveCases(); presentationCases(); hostCases()
    end)
    if not ok then check(false, "Start异常=" .. tostring(err)) end
    print(PREFIX .. "RESULT cases=" .. passed .. "/" .. cases .. " assertions=" .. assertions .. " failures=" .. failures)
    if failures == 0 and cases > 0 and passed == cases then print(PREFIX .. "ALL PASS") end
    engine:Exit()
end
