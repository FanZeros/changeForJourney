-- samsara_mirror_test.lua — N07/N09镜像来源、凭片与无奖展示专项。
-- 依据接线方案§13及精修稿N07/N09；仅本文件新增，主会话负责Runtime/build。
-- 复用N03测试的cache源码私有load：真实Config/Schema/Player/Playback/Panel/Dialogue。
-- 存档、图形、旧系统边界独立替身；cjson真实编解码，不访问玩家文件或package.loaded。
local PREFIX = "[samsara_mirror] "
local assertions, failures, cases, passed = 0, 0, 0, 0
local DOG, BELL = "samsara.dog_mirror", "samsara.bell_mirror"
local N02, N12, N13, N14, N03 = "samsara.log_leaf", "samsara.cargo_match", "samsara.gray_order", "samsara.people_record", "samsara.returned_manifest"
local OLD_KEYS = { N02, N12, N13, N14, N03 }
local KEYS = { N02, N12, N13, N14, N03, DOG, BELL, "samsara.opening_roster", "samsara.dragon_mirror" }
local FIRST, REPLAY = "samsara_first_read", "samsara_replay"
local JSON = cjson
local MIRRORS = {
    { key = DOG, stage = 2505, legacy = 64, id = "E03-A", title = "狗留下的绳结", source = "live_clear_2505",
        text = "请先护送远征长离开。\n若他还没到，就让我守在接驳处。\n到了，请告诉我下一次该守谁。\n申请人：大狗嚼〔旧登记页〕。\n答复：任务续征。撤离未结。",
        dialogue = {
            { "大狗嚼", "叫！我不会那样绑人。", 1 },
            { "远征长", "这里写着“请先带远征长走”。" },
            { "大狗嚼", "……是我会说的话。", 1 },
            { "叮咚鸡", "名字是你的。抄的是别页的申请。留下。", 3 },
            { "大狗嚼", "本狗没说它就是真的。", 1 },
            { "远征长", "我也没说。先让它把话留下。" },
        },
        narration = {
            "镜像投影败退，当前页既有登记载体根据回声生成一张本地抄片。绳结画成三股，中间的一股被收得最紧。",
            "大狗嚼指甲已划开纸角。听见“请先带远征长走”，他松开了手。",
        },
    },
    { key = BELL, stage = 2905, legacy = 67, id = "E03-C", title = "停不了的第三声", source = "live_clear_2905",
        text = "出征通知：已发。\n死亡通知：已发。\n请求结束通知。\n撤离收件人：〔空白〕。\n答复：收到。下一任务续征。",
        dialogue = {
            { "叮咚鸡", "死亡通知：收到。回程那行，还是空的。", 3 },
            { "远征长", "我们照她说的做了。为什么还响？" },
            { "叮咚鸡", "也许她请求的是另一件事。", 3 },
            { "大狗嚼", "叫……她说不想再走。", 1 },
            { "黄桃龙", "那为什么每张纸都叫她继续？", 2 },
            { "叮咚鸡", "这次把铃声也记下来。", 3 },
        },
        narration = {
            "凭片上有“请求结束通知”。下方的处理结果只有“收到”，没有“批准”。镜像退去后，远处又响两声铃。",
            "第三声迟到。",
        },
    },
}
local function check(ok, label)
    assertions = assertions + 1
    if not ok then
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
local function includes(text, needle)
    return type(text) == "string" and text:find(needle, 1, true) ~= nil
end
local function outsideStory(session)
    local out = {}
    for key, value in pairs(session) do if key ~= "samsaraStory" then out[key] = copy(value) end end
    return out
end
local function oldPart(session)
    local out = { nodes = {}, evidence = {} }
    for _, key in ipairs(OLD_KEYS) do out.nodes[key] = copy(session.samsaraStory.nodes[key]) end
    for _, id in ipairs({ "E01", "E02", "E05" }) do out.evidence[id] = copy(session.samsaraStory.evidence[id]) end
    out.historyCaptured = session.samsaraStory.historyCaptured
    out.cargoHistoryCaptured = session.samsaraStory.cargoHistoryCaptured
    return out
end
---@param path string
---@param overrides table
---@param globals table?
---@return any
local function isolated(path, overrides, globals)
    local file = cache:GetFile(path)
    assert(file and file:IsOpen(), "missing real source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local env = {}
    for key, value in pairs(globals or {}) do env[key] = value end
    env.require = function(name)
        if overrides[name] ~= nil then return overrides[name] end
        error("未声明依赖/奖励路径 " .. path .. ": " .. tostring(name))
    end
    env._G = env
    setmetatable(env, { __index = _G })
    return assert(load(table.concat(lines, "\n"), "@" .. path, "t", env))()
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

local function fresh(claimed)
    -- 保留独立旧账本字符串键，真实cjson可编码数字64/67键而不触发稀疏数组限制。
    local claimedMap = copy(claimed or {})
    claimedMap["82"] = true
    return { initialHeroId = 1, introCompleted = true, hasReincarnated = true,
        firstGachaTenDone = true, lastOnlineTime = 9000, firstLoginTime = 100,
        offlineBonusCount = 2, offlineBonusDate = "2026-10-03", claimedScenarios = claimedMap,
        scenarioRewardsGranted = { ["64"] = true, ["67"] = true, ["44"] = true },
        tutorialProgress = { groupId = 8, step = 3, custom = { keep = true } },
        introPlayback = { done = true }, unknownSession = { keep = { "old", false, 7 } },
        samsaraStory = { schemaVersion = 1, historyCaptured = true, cargoHistoryCaptured = true,
            nodes = {}, evidence = {}, unknownStory = { keep = 55 } },
    }
end
-- 五节点已处理的旧档：镜像迁移不得重置结果、来源、原件和既有核验。
local function oldArchive()
    local session = fresh({ ["17"] = true, ["44"] = true })
    for index, key in ipairs(OLD_KEYS) do
        session.samsaraStory.nodes[key] = { eligible = true, contentVersion = 1,
            resolution = index % 2 == 0 and "skipped" or "finished",
            eligibilitySource = key == N03 and "e02_history" or "previous_processed",
            legacyContext = "live_finished", unknown = { keep = index }, manualOnly = key == N03 }
    end
    session.samsaraStory.evidence = {
        E01 = { unlocked = true, source = "clear_104_legacy", unknown = { keep = 1 } },
        E02 = { unlocked = true, source = "player_record", annotationUnlocked = true, unknown = { keep = 2 } },
        E05 = { unlocked = true, source = "order_archive", continuationUnlocked = true, peopleUnlocked = true, unknown = { keep = 5 } },
    }
    return session
end
local function result(lease, reason)
    return { playToken = lease.playToken, contextEpoch = lease.contextEpoch, nodeKey = lease.nodeKey, reason = reason }
end
local function fixture(session, raw, legacy)
    local f = { session = session or fresh(), disk = "", sets = 0, flushes = 0, fault = "", save = true }
    f.Config = isolated("config/SamsaraSliceConfig.lua", {})
    f.Schema = isolated("shared/session/SamsaraStorySchema.lua", {})
    f.Player = isolated("systems/SamsaraSlicePlayer.lua", {
        ["config.SamsaraSliceConfig"] = f.Config, ["shared.session.SamsaraStorySchema"] = f.Schema,
        ["config.ScenarioDialogueConfig"] = legacy or isolated("config/ScenarioDialogueConfig.lua", {}),
    })
    f.options = {
        getSession = function() return f.session end,
        setSession = function(value)
            eq(value, f.session, "通知仍为共享session同表")
            f.sets = f.sets + 1
            if f.fault == "set" then error("injected set failure") end
        end,
        flush = function()
            f.flushes = f.flushes + 1
            if f.fault == "flush" then error("injected flush failure") end
            if f.save == true then f.disk = JSON.encode(f.session) end
            return f.save
        end,
    }
    f.supported = f.Player.init(f.options, raw or {})
    return f
end
local function node(f, item) return f.session.samsaraStory.nodes[item.key] end
local function record(f, item) return f.Player.getRecord(item.key) end
local function visible(f, item)
    for _, evidence in ipairs(record(f, item).evidences) do if evidence.id == item.id then return evidence end end
    return nil
end
local function noExtraEvidence(f)
    for _, id in ipairs({ "E03-B", "E04", "E06", "E07" }) do
        eq(f.session.samsaraStory.evidence[id], nil, "本批不生成" .. id)
    end
end
local function hidden(f, item, label)
    eq(visible(f, item), nil, label .. "不公开事件初片")
    eq(record(f, item).evidence, nil, label .. "无假已读原件")
    eq(f.session.samsaraStory.evidence[item.id], nil, label .. "不授予事件凭片")
    noExtraEvidence(f)
end
local function original(steps, item, label)
    eq(#steps, 8, label .. "两旁白六句对白")
    local spoken, narrations = {}, {}
    for _, step in ipairs(steps) do
        if step.name == "旁白" then
            eq(step.characterId, nil, label .. "旁白不猜人物ID")
            narrations[#narrations + 1] = step.text
        else spoken[#spoken + 1] = step end
        for _, field in ipairs({ "scenarioId", "reward", "rewards", "cg", "cgPath" }) do eq(step[field], nil, label .. "步骤无" .. field) end
    end
    eq(#spoken, #item.dialogue, label .. "六句对白无增删")
    for index, expected in ipairs(item.dialogue) do
        local step = assert(spoken[index])
        eq(step.name, expected[1], label .. "人物" .. index)
        eq(step.text, expected[2], label .. "逐字对白" .. index)
        eq(step.characterId, expected[3], label .. "已核实立绘" .. index)
    end
    for _, expected in ipairs(item.narration) do
        local found = false
        for _, text in ipairs(narrations) do if text == expected then found = true end end
        check(found, label .. "动作逐字原句 " .. expected)
    end
end
local function live(f, item, reason)
    eq(f.Player.onStageCleared(item.stage), true, "真实CLEAR只建资格")
    eq(f.Player.noteLegacyResult(item.legacy, reason or "finished"), true, "真实旧对应结果")
    eq(record(f, item).eventTrusted, true, "精确live来源与真实旧context可信")
end
local function finish(f, item, reason)
    local lease = assert(f.Player.begin(FIRST, item.key), "missing lease " .. item.key)
    eq(f.Player.onResult(result(lease, reason or "finished")), true, "接受精确首读结果")
    return lease
end

local function configAndHistoryCases()
    runCase("旧八KEY严格前缀/末尾N08/默认N02/正文与初片逐字/配置副本", function()
        local f = fixture()
        eq(f.Config.DOG_MIRROR_KEY, DOG, "DOG_MIRROR_KEY")
        eq(f.Config.BELL_MIRROR_KEY, BELL, "BELL_MIRROR_KEY")
        check(same(f.Config.KEYS, KEYS), "旧八KEY索引严格前缀，末尾仅追加N08")
        eq(f.Player.getRecord().key, N02, "省参仍N02")
        local records = f.Player.getRecords(); eq(#records, 9, "九记录")
        for index, key in ipairs(KEYS) do eq(records[index].key, key, "索引" .. index) end
        for _, item in ipairs(MIRRORS) do
            local cfg = assert(f.Config.get(item.key))
            eq(cfg.title, item.title, "原章节标题")
            eq(cfg.mode, "small", "无奖small")
            eq(cfg.requiredStage, item.stage, "成功关锚点")
            eq(cfg.dependency, nil, "两镜像互不前置/不锁N03")
            for _, field in ipairs({ "scenarioId", "reward", "rewards", "onFinish" }) do eq(cfg[field], nil, "配置不含" .. field) end
            original(cfg.steps, item, "配置")
            eq(cfg.evidence.id, item.id, "独立E03编号")
            eq(cfg.evidence.text, item.text, "逐字初片")
            for _, field in ipairs({ "annotation", "continuation", "people", "reward", "rewards", "scenarioId" }) do eq(cfg.evidence[field], nil, "初片无" .. field) end
            eq(f.Config.getEvidence(item.id).text, item.text, "独立原件API逐字初片")
            cfg.steps[1].text, cfg.evidence.text = "UI覆盖", "UI覆盖"
            original(f.Config.get(item.key).steps, item, "配置深副本")
            eq(f.Config.get(item.key).evidence.text, item.text, "初片深副本")
        end
        eq(f.Config.get("N07"), nil, "策划编号不是API key")
        eq(f.Config.get("N09"), nil, "策划编号不是API key")
        local dragonEvidence = assert(f.Config.getEvidence("E03-B"))
        eq(dragonEvidence.id, "E03-B", "B为已支持的合法静态初片，本A/C夹具不获B")
        for _, field in ipairs({ "annotation", "continuation", "people", "reward", "rewards", "scenarioId" }) do
            eq(dragonEvidence[field], nil, "B静态初片不开放" .. field)
        end
        for _, item in ipairs(MIRRORS) do
            local cfg = assert(f.Config.get(item.key))
            check(not includes(cfg.evidence.text, dragonEvidence.text), "A/C原件不泄B正文 " .. item.key)
            for _, step in ipairs(cfg.steps) do check(not includes(step.text, dragonEvidence.text), "A/C对白不泄B正文 " .. item.key) end
        end
        noExtraEvidence(f)
    end)
    for _, item in ipairs(MIRRORS) do
        for _, numeric in ipairs({ true, false }) do
            runCase("raw精确true仅历史参考 " .. item.key .. "/" .. tostring(numeric), function()
                local session = oldArchive()
                local old, outside = oldPart(session), outsideStory(session)
                local raw = { maxStageId = 9999, currentStageId = item.stage, clearedStages = { [numeric and item.stage or tostring(item.stage)] = true } }
                local f = fixture(session, raw)
                eq(session.samsaraStory.mirrorHistoryCaptured, true, "独立捕获完成")
                eq(session.samsaraStory.mirrorHistoryVersion, 1, "独立捕获版本1")
                eq(node(f, item).eligibilitySource, "legacy_raw_clear_unknown", "raw旧表不能冒充真实胜利")
                check(node(f, item).eligible ~= true, "raw不eligible")
                eq(record(f, item).eligibilitySource, "legacy_raw_clear_unknown", "展示来源一致")
                eq(record(f, item).status, "locked", "raw只locked")
                eq(record(f, item).eventTrusted, false, "raw非事件可信")
                eq(record(f, item).referenceOnly, true, "raw静态参考")
                original(record(f, item).referenceSteps, item, "raw参考正文")
                eq(f.Player.peekReady(), nil, "raw不自动播")
                eq(f.Player.requestRead(item.key), false, "raw不request")
                eq(f.Player.begin(FIRST, item.key), nil, "raw不begin首读")
                eq(f.Player.begin(REPLAY, item.key), nil, "raw不回看租约")
                hidden(f, item, "raw")
                check(same(oldPart(session), old), "旧五节点/证据/阴性标记原样")
                check(same(outsideStory(session), outside), "旧账本/教程/离线不改")
                local captured, count = copy(session), f.flushes
                f.Player.init(f.options, { clearedStages = { [2505] = true, [2905] = true, [204] = true, [104] = true } })
                check(same(session, captured), "同表二次init不重扫")
                eq(f.flushes, count, "同表无变化不保存")
                local reboot = fixture(JSON.decode(f.disk), { clearedStages = { [2505] = true, [2905] = true } })
                eq(record(reboot, item).eligibilitySource, "legacy_raw_clear_unknown", "JSON重启保持未知来源")
                hidden(reboot, item, "重启raw")
                local other = item.key == DOG and MIRRORS[2] or MIRRORS[1]
                eq(record(reboot, other).status, "locked", "阴性另一关不反扫")
            end)
        end
        for _, value in ipairs({ false, "true", "false", 1, 0 }) do
            runCase("raw严格值/max/current/claimed不能证明胜利 " .. item.key .. "/" .. tostring(value), function()
                local f = fixture(fresh({ [item.legacy] = true, [tostring(item.legacy)] = true }),
                    { maxStageId = 9999, currentStageId = item.stage, clearedStages = { [item.stage] = value } })
                local saved = node(f, item)
                check(not saved or saved.eligibilitySource ~= "legacy_raw_clear_unknown", "只有精确true保存raw来源")
                eq(record(f, item).status, "locked", "max/current/claimed仍locked")
                eq(record(f, item).referenceOnly, true, "无胜利亦可静态参考")
                eq(record(f, item).eventTrusted, false, "claimed不是事件")
                eq(f.Player.requestRead(item.key), false, "阴性不request")
                eq(f.Player.begin(FIRST, item.key), nil, "阴性不begin")
                hidden(f, item, "阴性")
            end)
        end
        runCase("阴性捕获不重扫且独立于旧两个flag " .. item.key, function()
            local session = fresh(); session.samsaraStory.historyCaptured, session.samsaraStory.cargoHistoryCaptured = true, true
            local f = fixture(session, {})
            local captured = copy(session)
            f.Player.init(f.options, { clearedStages = { [item.stage] = true, [104] = true, [204] = true, [4905] = true } })
            check(same(session, captured), "后来补齐不重扫各独立历史")
            local reboot = fixture(JSON.decode(f.disk), { clearedStages = { [item.stage] = true } })
            eq(record(reboot, item).status, "locked", "重启阴性亦不重扫")
            eq(reboot.session.samsaraStory.evidence.E02, nil, "不绕cargo阴性")
            hidden(reboot, item, "重启阴性")
            eq(f.Player.noteLegacyResult(item.legacy, "finished"), true, "阴性仍允许记录独立旧结果")
            eq(record(f, item).eventTrusted, false, "旧结束独自不证明胜利")
            eq(record(f, item).status, "locked", "未CLEAR仍锁定")
            eq(f.Player.onStageCleared(item.stage), true, "后续正式CLEAR可建立资格")
            eq(record(f, item).eventTrusted, true, "真实CLEAR与预先旧结果合并可信")
        end)
    end
    runCase("非法raw通关键不认/镜像捕获不重置旧flag", function()
        local f = fixture(fresh(), { clearedStages = { ["02505"] = true, ["2905.0"] = true, ["2905x"] = true, [2504] = true } })
        for _, item in ipairs(MIRRORS) do eq(record(f, item).status, "locked", "非法key不认") end
        eq(f.session.samsaraStory.historyCaptured, true, "N02flag保持")
        eq(f.session.samsaraStory.cargoHistoryCaptured, true, "cargoflag保持")
        eq(f.session.samsaraStory.mirrorHistoryCaptured, true, "阴性也捕获")
    end)
end

local function legacyAndTrustCases()
    for _, item in ipairs(MIRRORS) do
        local other = item.key == DOG and MIRRORS[2] or MIRRORS[1]
        for _, reason in ipairs({ "finished", "dismissed", "skipped" }) do
            runCase("旧结果可在CLEAR前独立记录 " .. item.key .. "/" .. reason, function()
                local f = fixture()
                local outside = outsideStory(f.session)
                eq(f.Player.noteLegacyResult(tostring(item.legacy), reason), true, "未eligible也不能漏记旧结果")
                eq(node(f, item).legacyContext, reason == "skipped" and "live_skipped" or "live_finished", "真实结束语境")
                eq(record(f, item).eventTrusted, false, "ENTER旧结果不等于成功CLEAR")
                eq(f.Player.peekReady(), nil, "仅ENTER不自动播")
                hidden(f, item, "仅旧结果")
                eq(f.Player.onStageCleared(tostring(item.stage)), true, "正式CLEAR精确字符串")
                eq(node(f, item).eligibilitySource, item.source, "正式live来源")
                eq(record(f, item).status, "pending", "CLEAR不代读")
                eq(record(f, item).eventTrusted, true, "旧结束与成功来源匹配")
                eq(f.Player.hasPendingRecords(), true, "可信pending有记录红点")
                eq(record(f, item).referenceOnly, nil, "可信待阅不是参考")
                eq(f.Player.peekReady(), item.key, "matching结果后可自动播")
                eq(f.Player.noteLegacyResult(item.legacy, reason), false, "同源同终态幂等")
                eq(f.Player.requestRead(item.key), true, "可信手动请求")
                local request = assert(f.Player.takeRequest()); eq(request.key, item.key, "正确key请求")
                check(f.Player.begin(request.kind, request.key) ~= nil, "可信手动begin")
                eq(record(f, other).eventTrusted, false, "另一镜像不借旧结果")
                eq(record(f, other).status, "locked", "另一镜像不借CLEAR")
                check(same(outsideStory(f.session), outside), "旧结果不写旧领奖账本")
            end)
        end
        for _, claimed in ipairs({ item.legacy, tostring(item.legacy) }) do
            runCase("liveCLEAR加preclaimed仍仅reference " .. item.key .. "/" .. tostring(claimed), function()
                local f = fixture(fresh({ [claimed] = true }))
                eq(f.Player.onStageCleared(item.stage), true, "真实CLEAR")
                eq(record(f, item).status, "pending", "成功来源仅待阅")
                eq(node(f, item).eligibilitySource, item.source, "claimed不洗正式来源")
                eq(node(f, item).legacyContext, "legacy_claimed_unknown", "preclaim阅读未知")
                eq(record(f, item).eventTrusted, false, "preclaim不是实际结束")
                eq(record(f, item).referenceOnly, true, "缺旧result只静态参考")
                eq(f.Player.hasPendingRecords(), false, "仅参考待阅不永久红点")
                eq(f.Player.peekReady(), nil, "preclaim不自动事件播")
                eq(f.Player.requestRead(item.key), false, "preclaim不request事件")
                eq(f.Player.begin(FIRST, item.key), nil, "preclaim不begin事件")
                eq(f.Player.noteLegacyResult(other.legacy, "skipped"), true, "另一旧结束独立记录")
                eq(record(f, item).eventTrusted, false, "不匹配旧result不借用")
                hidden(f, item, "preclaim")
                eq(f.Player.noteLegacyResult(item.legacy, "finished"), true, "对应真实结束才能恢复")
                eq(record(f, item).eventTrusted, true, "精确真实结束可信")
                eq(node(f, item).eligibilitySource, item.source, "真实结束不改CLEAR来源")
            end)
        end
        runCase("liveCLEAR无任何旧result仅参考无红点 " .. item.key, function()
            local f = fixture()
            eq(f.Player.onStageCleared(item.stage), true, "无旧结果的正式CLEAR")
            eq(record(f, item).status, "pending", "仍保胜利待阅状态")
            eq(record(f, item).referenceOnly, true, "缺旧result只参考")
            eq(record(f, item).eventTrusted, false, "不能用CLEAR代替旧遭遇处理")
            eq(f.Player.hasPendingRecords(), false, "仅参考不永久红点")
            eq(f.Player.requestRead(item.key), false, "仅参考不request")
            eq(f.Player.begin(FIRST, item.key), nil, "仅参考不begin")
            eq(f.Player.peekReady(), nil, "仅参考不自动")
            hidden(f, item, "CLEAR无旧result")
        end)
        runCase("无配置/无旧结果不靠unavailable放行 " .. item.key, function()
            local f = fixture(fresh(), {}, {})
            f.Player.onStageCleared(item.stage)
            eq(record(f, item).eventTrusted, false, "unavailable不能冒充真实旧结果")
            eq(record(f, item).referenceOnly, true, "来源暂缺静态参考")
            eq(f.Player.requestRead(item.key), false, "unavailable不request")
            eq(f.Player.begin(FIRST, item.key), nil, "unavailable不begin")
            eq(f.Player.peekReady(), nil, "unavailable不自动播")
            hidden(f, item, "缺配置")
        end)
        runCase("旧reason和id严格枚举 " .. item.key, function()
            local f = fixture(); f.Player.onStageCleared(item.stage)
            local before, count = copy(f.session), f.flushes
            for _, reason in ipairs({ "Finished", "FINISHED", "Skipped", "Dismissed", "RESET", "skip", "complete", "live_finished", "live_skipped", "unknown", "" }) do
                eq(f.Player.noteLegacyResult(item.legacy, reason), false, "拒绝假reason " .. reason)
            end
            for _, id in ipairs({ "0" .. item.legacy, tostring(item.legacy) .. ".0", tostring(item.legacy) .. "x", "065", "65.0", "65x", 73, 17, 44, false }) do
                eq(f.Player.noteLegacyResult(id, "finished"), false, "拒绝非法64/67格式或无关ID（精确65已合法） " .. tostring(id))
            end
            check(same(f.session, before), "非法输入不修改")
            eq(f.flushes, count, "非法输入不保存")
            -- 精确65现为合法龙遭遇；不得借其来源放行A/C，也不凭旧结束造N08资格。
            local ownNode = copy(node(f, item))
            eq(f.Player.noteLegacyResult(65, "finished"), true, "合法65仅独立记录龙遭遇")
            check(same(node(f, item), ownNode), "65不改A/C自身成功来源或旧遭遇语境")
            eq(record(f, item).eventTrusted, false, "65不替代对应64/67带ID结果")
            eq(f.Player.requestRead(item.key), false, "仅65结果不能请求A/C事件")
            eq(f.Player.begin(FIRST, item.key), nil, "仅65结果不能首读A/C事件")
            check(f.session.samsaraStory.nodes["samsara.dragon_mirror"].eligible ~= true, "65旧结束独自不造N08资格")
            hidden(f, item, "错域65来源")
        end)
        for _, reason in ipairs({ "reset", "replaced", "failed" }) do
            runCase("旧中断阻自动但可信CLEAR允许显式补读/重启保留 " .. item.key .. "/" .. reason, function()
                local f = fixture(fresh({ [tostring(item.legacy)] = true }))
                live(f, item)
                eq(f.Player.noteLegacyResult(item.legacy, reason), true, "旧中断覆盖live完成")
                eq(node(f, item).legacyContext, "live_interrupted", "明确中断不是完成")
                eq(record(f, item).eventTrusted, true, "中断不抹掉成功事件来源")
                eq(f.Player.peekReady(), nil, "interrupted自动阻播")
                eq(f.Player.begin(FIRST, item.key), nil, "未显式授权不begin")
                local reboot = fixture(JSON.decode(f.disk), { clearedStages = { [item.stage] = true } })
                eq(node(reboot, item).legacyContext, "live_interrupted", "重启不能降成claimed未知")
                eq(record(reboot, item).eventTrusted, true, "重启保留可信来源")
                eq(reboot.Player.peekReady(), nil, "重启仍不自动")
                eq(reboot.Player.requestRead(item.key), true, "记录页显式补读")
                local request = assert(reboot.Player.takeRequest())
                eq(reboot.Player.takeRequest(), nil, "显式授权单次消费")
                local lease = assert(reboot.Player.begin(request.kind, request.key))
                reboot.Player.onResult(result(lease, "reset"))
                eq(reboot.Player.begin(FIRST, item.key), nil, "租约取消不复用显式授权")
                eq(reboot.Player.requestRead(item.key), true, "新请求重新授权")
                request = assert(reboot.Player.takeRequest()); lease = assert(reboot.Player.begin(request.kind, request.key))
                eq(reboot.Player.onResult(result(lease, "skipped")), true, "独立补读可以skip处理")
                eq(node(reboot, item).legacyContext, "live_interrupted", "补读不伪装旧64/67已读")
                eq(visible(reboot, item).text, item.text, "显式处理公开自身初片")
                check(reboot.Player.begin(REPLAY, item.key) ~= nil, "中断旧来源不阻已处理自身回看")
                local restored = fixture(JSON.decode(f.disk), {})
                eq(restored.Player.noteLegacyResult(item.legacy, "skipped"), true, "后续真实旧skip恢复")
                eq(restored.Player.peekReady(), item.key, "真实旧恢复后自动允许")
            end)
        end
        runCase("raw未知加旧完成不可信/正式CLEAR升级且不重置resolution " .. item.key, function()
            local f = fixture(fresh({ [tostring(item.legacy)] = true }), { clearedStages = { [item.stage] = true } })
            eq(f.Player.noteLegacyResult(item.legacy, "finished"), true, "旧完成可独立记载")
            eq(record(f, item).eventTrusted, false, "raw加真实旧结束仍无成功来源")
            eq(f.Player.requestRead(item.key), false, "raw不能因旧结束变事件")
            node(f, item).unknown = { keep = 73 }
            eq(f.Player.onStageCleared(item.stage), true, "真实CLEAR可升级raw未知")
            eq(node(f, item).eligibilitySource, item.source, "升级live来源")
            eq(node(f, item).legacyContext, "live_finished", "升级保旧真实结束")
            eq(node(f, item).unknown.keep, 73, "升级保未知字段")
            finish(f, item, "skipped")
            local saved, count = copy(f.session), f.flushes
            eq(f.Player.onStageCleared(item.stage), false, "重复CLEAR幂等")
            eq(f.Player.noteLegacyResult(item.legacy, "finished"), false, "重复旧结果幂等")
            check(same(f.session, saved), "重复CLEAR不重置首读resolution/证据")
            eq(f.flushes, count, "重复事件不保存")
        end)
    end
end

local function resultAndVersionCases()
    for _, item in ipairs(MIRRORS) do
        for _, reason in ipairs({ "finished", "dismissed", "skipped", "reset", "replaced", "failed" }) do
            runCase("精确首读/回看结果与旧五节点保全 " .. item.key .. "/" .. reason, function()
                local f = fixture(oldArchive())
                local old, outside = oldPart(f.session), outsideStory(f.session)
                live(f, item); hidden(f, item, "CLEAR后未读")
                local lease = assert(f.Player.begin(FIRST, item.key))
                local count = f.flushes
                eq(f.Player.onResult(result(lease, reason)), true, "接受当前身份")
                eq(f.Player.onResult(result(lease, reason)), false, "重复迟到拒绝")
                local success = reason == "finished" or reason == "dismissed" or reason == "skipped"
                eq(record(f, item).status, success and (reason == "skipped" and "skipped" or "finished") or "pending", "结果映射")
                eq(f.flushes, count + (success and 1 or 0), "仅首次处理保存")
                if success then
                    local evidence = assert(visible(f, item))
                    eq(evidence.text, item.text, "公开逐字初片")
                    eq(evidence.source, item.source, "凭片来源与节点一致")
                    eq(record(f, item).eligibilitySource, evidence.source, "展示同一来源")
                    for _, field in ipairs({ "annotation", "continuation", "people" }) do eq(evidence[field], nil, "高批注锁" .. field) end
                    local saved, flushes = copy(f.session), f.flushes
                    for _, ending in ipairs({ "finished", "dismissed", "skipped", "reset", "replaced", "failed" }) do
                        local replay = assert(f.Player.begin(REPLAY, item.key))
                        eq(f.Player.onResult(result(replay, ending)), true, "回看结束 " .. ending)
                        check(same(f.session, saved), "回看不改首次结果/来源/旧账本")
                        eq(f.flushes, flushes, "回看无保存")
                    end
                    local reboot = fixture(JSON.decode(f.disk), {})
                    eq(record(reboot, item).status, record(f, item).status, "JSON首读终态保留")
                    eq(visible(reboot, item).text, item.text, "JSON初片可继续回看")
                else hidden(f, item, "中断"); check(f.Player.begin(FIRST, item.key) ~= nil, "切片中断可重试"); f.Player.cancel() end
                check(same(oldPart(f.session), old), "旧五节点所有结果来源证据不动")
                check(same(outsideStory(f.session), outside), "旧经济/教程/claimed/granted不动")
                noExtraEvidence(f)
                eq(record(f, item.key == DOG and MIRRORS[2] or MIRRORS[1]).status, "locked", "不能释放另一镜像")
            end)
        end
        runCase("读档可信live可继续/伪来源与提前批注不能泄露 " .. item.key, function()
            local session = fresh({ [tostring(item.legacy)] = true })
            session.samsaraStory.mirrorHistoryCaptured, session.samsaraStory.mirrorHistoryVersion = true, 1
            session.samsaraStory.nodes[item.key] = { contentVersion = 1, eligible = true,
                eligibilitySource = item.source, legacyContext = "live_skipped", unknown = { keep = 11 } }
            local f = fixture(JSON.decode(JSON.encode(session)), { maxStageId = 9999 })
            eq(record(f, item).eventTrusted, true, "已保存live与真实旧来源不被claimed洗掉")
            eq(node(f, item).legacyContext, "live_skipped", "读档保已知skip")
            eq(f.Player.peekReady(), item.key, "读档可继续待阅")
            finish(f, item)
            local saved = f.session.samsaraStory.evidence[item.id]
            saved.annotationUnlocked, saved.continuationUnlocked, saved.peopleUnlocked = true, true, true
            saved.unknown = { keep = 12 }
            local public = assert(visible(f, item))
            for _, field in ipairs({ "annotation", "continuation", "people" }) do eq(public[field], nil, "提前标记仍锁高批注 " .. field) end
            eq(saved.unknown.keep, 12, "未知凭片字段保留")
            local count = f.flushes
            for _, source in ipairs({ "legacy_raw_clear_unknown", "case_archive", "player_record", "live_clear", "LIVE_CLEAR_" .. item.stage, "live_clear_" .. (item.stage == 2505 and 2905 or 2505) }) do
                saved.source = source
                eq(visible(f, item), nil, "凭片伪source不能公开 " .. source)
                saved.source = item.source
                node(f, item).eligibilitySource = source
                eq(record(f, item).eventTrusted, false, "节点伪source不可信 " .. source)
                eq(record(f, item).referenceOnly, true, "伪节点来源退静态参考")
                eq(f.Player.requestRead(item.key), false, "伪source不request")
                eq(f.Player.begin(REPLAY, item.key), nil, "伪source不借resolution回看")
                eq(visible(f, item), nil, "节点伪source不能公开")
                node(f, item).eligibilitySource = item.source
            end
            eq(f.flushes, count, "伪来源只读检查不保存")
            eq(visible(f, item).text, item.text, "恢复原精确来源才可公开")
        end)
        runCase("活动租约遇未来schema或mirrorHistoryVersion拒迟到 " .. item.key, function()
            for _, field in ipairs({ "schemaVersion", "mirrorHistoryVersion" }) do
                local f = fixture(); live(f, item)
                local lease = assert(f.Player.begin(FIRST, item.key))
                f.session.samsaraStory[field] = 2
                local before, count = copy(f.session), f.flushes
                eq(f.Player.onResult(result(lease, "finished")), false, "活动未来版本拒结果 " .. field)
                eq(f.Player.noteLegacyResult(item.legacy, "skipped"), false, "活动未来版本拒旧桥 " .. field)
                eq(f.Player.onStageCleared(item.stage), false, "活动未来版本拒CLEAR " .. field)
                eq(record(f, item).status, "unsupported", "活动未来展示禁用 " .. field)
                check(same(f.session, before), "活动未来所有字段原样 " .. field)
                eq(f.flushes, count, "活动未来不保存 " .. field)
            end
        end)
        runCase("旧结果桥epoch迟到拒绝/合法JSON重附保持 " .. item.key, function()
            local f = fixture()
            local epoch = f.Player.getContextEpoch()
            eq(type(epoch), "number", "旧桥捕获number epoch")
            f.Player.cancel()
            check(f.Player.getContextEpoch() > epoch, "cancel递增旧桥代次")
            local before, count = copy(f.session), f.flushes
            eq(f.Player.noteLegacyResult(item.legacy, "finished", epoch), false, "cancel后旧遭遇迟到拒绝")
            check(same(f.session, before), "cancel旧桥不改档")
            eq(f.flushes, count, "cancel旧桥不保存")
            epoch = f.Player.getContextEpoch()
            f.session = fresh(); f.Player.init(f.options, {})
            before, count = copy(f.session), f.flushes
            eq(f.Player.noteLegacyResult(item.legacy, "skipped", epoch), false, "新session init旧桥迟到拒绝")
            check(same(f.session, before), "旧桥不污染新session")
            eq(f.flushes, count, "新档拒迟到不保存")
            epoch = f.Player.getContextEpoch()
            f.session = JSON.decode(JSON.encode(f.session)); f.Player.onSessionUpdated(f.session)
            eq(f.Player.getContextEpoch(), epoch, "合法同游戏重附代次不变")
            eq(f.Player.noteLegacyResult(item.legacy, "finished", epoch), true, "合法重附旧桥仍有效且未CLEAR可记录")
            eq(node(f, item).legacyContext, "live_finished", "合法旧桥准确来源")
            eq(record(f, item).eventTrusted, false, "合法旧桥仍不能代替CLEAR")
            eq(f.Player.noteLegacyResult(item.legacy, "skipped", tostring(epoch)), false, "字符串epoch不冒充number")
            eq(f.Player.noteLegacyResult(item.legacy, "skipped"), true, "同步两参接口仍兼容")
        end)
        runCase("token/epoch/key/reason/取消/换session/合法重附 " .. item.key, function()
            local f = fixture(); live(f, item)
            local lease = assert(f.Player.begin(FIRST, item.key))
            for _, field in ipairs({ "playToken", "contextEpoch", "nodeKey" }) do
                local bad = result(lease, "finished"); bad[field] = field == "nodeKey" and N03 or -1
                eq(f.Player.onResult(bad), false, "错误身份 " .. field)
            end
            for _, reason in ipairs({ "Finished", "skip", "live_finished", "unknown" }) do eq(f.Player.onResult(result(lease, reason)), false, "假首读reason不消费") end
            f.Player.cancel(); eq(f.Player.onResult(result(lease, "finished")), false, "进程取消迟到")
            local newer = assert(f.Player.begin(FIRST, item.key))
            check(newer.playToken > lease.playToken and newer.contextEpoch > lease.contextEpoch, "新租约身份递增")
            f.session = JSON.decode(JSON.encode(f.session))
            local before = copy(f.session)
            eq(f.Player.onResult(result(newer, "skipped")), false, "getter静默换表不重附")
            check(same(f.session, before), "迟到不污染换表")
            f.Player.init(f.options, {})
            eq(f.Player.onResult(result(newer, "finished")), false, "重新init旧token仍拒绝")
            local current = assert(f.Player.begin(FIRST, item.key))
            f.session = JSON.decode(JSON.encode(f.session)); f.Player.onSessionUpdated(f.session)
            eq(f.Player.onResult(result(current, "skipped")), true, "合法同游戏共享重附保当前租约")
            eq(record(f, item).status, "skipped", "重附精确结果处理")
            eq(node(f, item).playToken, nil, "token不持久化节点")
            eq(node(f, item).contextEpoch, nil, "epoch不持久化节点")
        end)
    end
    runCase("Schema默认独立/严格布尔/未知字段/normalize幂等", function()
        local schema = isolated("shared/session/SamsaraStorySchema.lua", {})
        local a, b = schema.new(), schema.new()
        eq(a.mirrorHistoryCaptured, false, "新镜像捕获默认false")
        eq(a.mirrorHistoryVersion, 1, "默认镜像版本1")
        eq(a.dragonHistoryCaptured, false, "龙域捕获默认false且不借A/C标记")
        eq(a.dragonHistoryVersion, 1, "默认独立龙域版本1")
        a.nodes[DOG] = { keep = true }; eq(b.nodes[DOG], nil, "新表不共享")
        local session = oldArchive(); local old = oldPart(session)
        session.samsaraStory.mirrorHistoryCaptured = "true"
        session.samsaraStory.nodes[DOG] = { contentVersion = "1", eligible = "true", resolution = "reset", legacyContext = "live_skipped", eligibilitySource = "live_clear_2505", unknown = { keep = 8 } }
        local _, supported = schema.normalize(session); eq(supported, true, "当前schema支持")
        eq(session.samsaraStory.mirrorHistoryCaptured, false, "捕获flag严格布尔")
        eq(session.samsaraStory.nodes[DOG].eligible, false, "资格严格布尔")
        eq(session.samsaraStory.nodes[DOG].resolution, nil, "reset不迁成完成")
        eq(session.samsaraStory.nodes[DOG].unknown.keep, 8, "未知字段保留")
        check(same(oldPart(session), old), "规范镜像不改已规范旧五节点")
        local before = copy(session); schema.normalize(session)
        check(same(session, before), "normalize幂等")
    end)
    for _, version in ipairs({ 2, "99" }) do
        runCase("未来schema全只读保全 " .. tostring(version), function()
            local session = fresh(); session.samsaraStory = { schemaVersion = version, nodes = "future", evidence = false,
                mirrorHistoryVersion = 9, mirrorHistoryCaptured = "future", unknown = { keep = 9 } }
            local before = copy(session); local f = fixture(session, { clearedStages = { [2505] = true, [2905] = true } })
            eq(f.supported, false, "未来schema禁用")
            for _, item in ipairs(MIRRORS) do
                eq(record(f, item).status, "unsupported", "未来不是参考locked")
                eq(record(f, item).referenceOnly, nil, "未来不假兼容")
                eq(f.Player.requestRead(item.key), false, "未来不request")
                eq(f.Player.begin(FIRST, item.key), nil, "未来不begin")
                eq(f.Player.onStageCleared(item.stage), false, "未来不写CLEAR")
                eq(f.Player.noteLegacyResult(item.legacy, "finished"), false, "未来不写旧结果")
            end
            f.Player.cancel(); f.Player.update(100)
            check(same(session, before), "未来结构逐字段保全")
            eq(f.flushes, 0, "未来不保存")
        end)
    end
    for _, item in ipairs(MIRRORS) do
        runCase("未来镜像content及活动中升级拒绝 " .. item.key, function()
            local session = fresh(); session.samsaraStory.mirrorHistoryCaptured, session.samsaraStory.mirrorHistoryVersion = true, 1
            session.samsaraStory.nodes[item.key] = { contentVersion = 99, eligible = "future", resolution = "future", unknown = { keep = 7 } }
            session.samsaraStory.evidence[item.id] = { source = { future = "tagged_source" }, unlocked = "tagged_true",
                annotationUnlocked = { tagged = true }, continuationUnlocked = "tagged_continuation", peopleUnlocked = 7, unknown = { keep = 8 } }
            local before, futureEvidence = copy(session.samsaraStory.nodes[item.key]), copy(session.samsaraStory.evidence[item.id])
            local f = fixture(session)
            eq(record(f, item).status, "unsupported", "未来content禁用")
            eq(f.Player.onStageCleared(item.stage), false, "CLEAR不覆盖未来内容")
            eq(f.Player.noteLegacyResult(item.legacy, "finished"), false, "旧结果不覆盖未来内容")
            eq(f.Player.requestRead(item.key), false, "未来content不请求")
            eq(f.Player.begin(FIRST, item.key), nil, "未来content不begin")
            check(same(node(f, item), before), "未来节点原样")
            check(same(session.samsaraStory.evidence[item.id], futureEvidence), "未来content凭片source对象及tagged标记逐字段保全")
            local other = item.key == DOG and MIRRORS[2] or MIRRORS[1]
            live(f, other); finish(f, other, "skipped")
            eq(visible(f, other).text, other.text, "另一当前内容镜像仍正常处理")
            f.Schema.normalize(session)
            check(same(node(f, item), before), "另一镜像完成不改未来节点")
            check(same(session.samsaraStory.evidence[item.id], futureEvidence), "另一镜像与再规范化不洗未来凭片")
            local current = fixture(); live(current, item)
            local lease = assert(current.Player.begin(FIRST, item.key))
            node(current, item).contentVersion = 99
            local all, count = copy(current.session), current.flushes
            eq(current.Player.onResult(result(lease, "finished")), false, "运行中升级拒绝旧结果")
            check(same(current.session, all), "运行中升级无写入")
            eq(current.flushes, count, "运行中升级不保存")
        end)
    end
    for _, version in ipairs({ 2, "99" }) do
        runCase("未来mirrorHistoryVersion只禁镜像/原五节点仍工作 " .. tostring(version), function()
            local session = fresh({ ["17"] = true })
            session.samsaraStory.mirrorHistoryVersion, session.samsaraStory.mirrorHistoryCaptured = version, "future"
            session.samsaraStory.nodes[DOG] = { eligible = "future", contentVersion = 1, resolution = "future", unknown = { keep = 3 } }
            session.samsaraStory.evidence["E03-A"] = { unlocked = "future", source = "future", unknown = { keep = 4 } }
            local mirrorNode, mirrorEvidence = copy(session.samsaraStory.nodes[DOG]), copy(session.samsaraStory.evidence["E03-A"])
            local f = fixture(session, { clearedStages = { [2505] = true, [2905] = true } })
            eq(f.supported, true, "原schema当前仍支持")
            eq(session.samsaraStory.mirrorHistoryVersion, version, "未来镜像版本原样")
            eq(session.samsaraStory.mirrorHistoryCaptured, "future", "未来flag原样")
            for _, item in ipairs(MIRRORS) do
                eq(record(f, item).status, "unsupported", "仅镜像unsupported")
                eq(f.Player.onStageCleared(item.stage), false, "未来镜像拒CLEAR")
                eq(f.Player.noteLegacyResult(item.legacy, "finished"), false, "未来镜像拒旧结束")
                eq(f.Player.requestRead(item.key), false, "未来镜像不request")
                eq(f.Player.begin(FIRST, item.key), nil, "未来镜像不begin")
            end
            check(same(session.samsaraStory.nodes[DOG], mirrorNode), "未来镜像节点保全")
            check(same(session.samsaraStory.evidence["E03-A"], mirrorEvidence), "未来镜像证据保全")
            eq(f.Player.onStageCleared(104), true, "原N02真实资格仍可写")
            local lease = assert(f.Player.begin(FIRST, N02)); eq(f.Player.onResult(result(lease, "skipped")), true, "原N02仍处理")
            eq(f.Player.onStageCleared(204), true, "原N03仍建资格")
            eq(f.Player.noteLegacyResult(44, "finished"), true, "原N03旧结束仍处理")
            lease = assert(f.Player.begin(FIRST, N03)); f.Player.onResult(result(lease, "finished"))
            eq(f.Player.onStageCleared(4905), true, "原cargo仍建资格")
            for _, key in ipairs({ N12, N13, N14 }) do
                lease = assert(f.Player.begin(FIRST, key)); eq(f.Player.onResult(result(lease, "skipped")), true, "原链仍工作 " .. key)
            end
            check(same(session.samsaraStory.nodes[DOG], mirrorNode), "原五处理不洗未来镜像节点")
            check(same(session.samsaraStory.evidence["E03-A"], mirrorEvidence), "原五处理不洗未来凭片")
        end)
    end
    for _, fault in ipairs({ "false", "flush", "set" }) do
        runCase("保存false/异常保内存与2秒重试 " .. fault, function()
            local f = fixture(); live(f, MIRRORS[1])
            local disk = f.disk
            if fault == "false" then f.save = false else f.fault = fault end
            finish(f, MIRRORS[1], "skipped")
            eq(record(f, MIRRORS[1]).status, "skipped", "失败保内存首次结果")
            eq(f.Player.isSavePending(), true, "失败明确待保存")
            eq(f.disk, disk, "磁盘JSON不变")
            local reboot = fixture(JSON.decode(disk), {})
            eq(record(reboot, MIRRORS[1]).status, "pending", "未保存重启仍待阅")
            eq(record(reboot, MIRRORS[1]).eventTrusted, true, "已保存live来源+旧结果可继续")
            local flushes, sets = f.flushes, f.sets
            f.Player.cancel(); f.Player.init(f.options, { clearedStages = { [2905] = true } })
            eq(f.Player.isSavePending(), true, "cancel/同表init不丢待存")
            f.Player.update(1.99); eq(f.flushes, flushes, "2秒前不重试Flush"); eq(f.sets, sets, "2秒前不重试通知")
            f.fault, f.save = "", true; f.Player.update(0.02)
            eq(f.flushes, flushes + 1, "恢复后只一次真实边界Flush")
            eq(f.Player.isSavePending(), false, "成功才清待存")
            eq(JSON.decode(f.disk).samsaraStory.nodes[DOG].resolution, "skipped", "真实cjson读回首次skip")
            eq(record(f, MIRRORS[2]).status, "locked", "失败期间阴性不反扫")
        end)
    end
end

-- 绘图/旧系统完全独立替身，真实Panel与Dialogue只运行其纯逻辑，不开渲染帧。
local function presentation(f)
    f.calls, f.drawings, f.boxes, f.tabs, f.buttons, f.font = {}, {}, {}, {}, {}, 38
    function f.count(name) f.calls[name] = (f.calls[name] or 0) + 1 end
    function f.n(name) return f.calls[name] or 0 end
    local draw = {
        hitTest = function(x, y, cx, cy, w, h) return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5 end,
        drawTextStroke = function(_, x, y, text) f.drawings[#f.drawings + 1] = text; f.buttons[#f.buttons + 1] = { x = x, y = y, text = text } end,
        drawImageCover = function() f.count("image") end,
        drawRoundedRectCentered = function() end,
    }
    local graphics = {
        nvgCreateImage = function() return -1 end,
        nvgRGBA = function() return {} end,
        nvgFontSize = function(_, size) f.font = size end,
        nvgTextBoxBounds = function(_, _, _, width, text)
            local lines = 0
            for line in (text .. "\n"):gmatch("(.-)\n") do lines = lines + math.max(1, math.ceil((utf8.len(line) or 0) * f.font / math.max(1, width))) end
            return { 0, 0, width, lines * f.font * 1.5 }
        end,
        nvgTextBox = function(_, x, y, _, text) f.drawings[#f.drawings + 1] = text; f.boxes[#f.boxes + 1] = { x = x, y = y, text = text } end,
        nvgText = function(_, _, _, text) f.drawings[#f.drawings + 1] = text end,
    }
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgIntersectScissor", "nvgScale", "nvgFontFace", "nvgTextAlign", "nvgTextLineHeight", "nvgFillColor", "nvgScissor", "nvgTranslate", "nvgBeginPath", "nvgRect", "nvgFill", "nvgRoundedRect", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgResetScissor" }) do graphics[name] = function() end end
    local dialogueDependencies = storyBoundary(f, graphics, isolated("config/ScenarioDialogueConfig.lua", {}))
    dialogueDependencies["core.DrawUtil"] = draw
    dialogueDependencies["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 } }
    dialogueDependencies["ui.widget.HeroFrame"] = { draw = function() end }
    dialogueDependencies["core.EventBus"] = { emit = function() f.count("legacy.broadcast") end }
    f.Dialogue = isolated("ui/story/ScenarioDialogue.lua", dialogueDependencies, graphics)
    f.Panel = isolated("ui/story/SamsaraRecordPanel.lua", { ["core.DrawUtil"] = draw,
        ["core.DarkIcon"] = { draw = function() end, drawNine = function(_, name, x, y, w, h)
            if name == "btn" and h == 64 then f.tabs[#f.tabs + 1] = { x = x + w * 0.5, y = y + h * 0.5, width = w } end
        end }, ["systems.SamsaraSlicePlayer"] = f.Player }, graphics)
    f.Playback = isolated("systems/SamsaraSlicePlayback.lua", { ["systems.SamsaraSlicePlayer"] = f.Player,
        ["config.SamsaraSliceConfig"] = f.Config, ["ui.story.ScenarioDialogue"] = f.Dialogue })
    local read, begin, show = f.Player.requestRead, f.Player.begin, f.Dialogue.show
    f.Player.requestRead = function(key) f.count("request"); return read(key) end
    f.Player.begin = function(kind, key) f.count("begin"); return begin(kind, key) end
    f.Dialogue.show = function(cfg) f.count("show"); f.shown = cfg; return show(cfg) end
    function f.draw(w, h)
        f.drawings, f.boxes, f.tabs, f.buttons = {}, {}, {}, {}
        f.Panel.draw({}, w or 1920, h or 1080)
        return table.concat(f.drawings, "\n")
    end
    function f.action(text)
        for _, button in ipairs(f.buttons) do if button.text == text and button.y > 800 then return button end end
        error("missing action " .. text)
    end
    return f
end
local function gates() return { ready = true, blocked = false, legacyPending = false, pointerBusy = false } end
local function finishDialogue(dialogue)
    local _, total = dialogue.getProgress()
    for _ = 1, total do dialogue.update(100); dialogue.advance() end
end

local function presentationCases()
    for _, item in ipairs(MIRRORS) do
        runCase("真实Panel九tab/静态参考无请求/长文滚动touch " .. item.key, function()
            local f = presentation(fixture(fresh(), { clearedStages = { [item.stage] = true } }))
            local before, flushes = copy(f.session), f.flushes
            for _, size in ipairs({ { 1920, 1080 }, { 2340, 1080 }, { 1280, 800 } }) do
                local w, h = size[1], size[2]
                eq(f.Panel.selectRecord(item.key), true, "九tab可select镜像")
                f.Panel.open(); local text = f.draw(w, h)
                check(includes(text, "亲历状态未确认"), "静态参考标亲历未知")
                for _, line in ipairs(item.dialogue) do check(includes(text, line[2]), "参考展示逐字对白") end
                check(not includes(text, item.text), "参考不公开初片")
                check(not includes(text, assert(f.Config.getEvidence("E03-B")).text), "A/C静态Panel不泄B正文")
                eq(#f.tabs, 9, "真实绘制九tab")
                local dragonLabel = false
                for _, button in ipairs(f.buttons) do
                    if button.text == "龙的罐头" and button.y < 300 then dragonLabel = true end
                end
                check(dragonLabel, "第九项使用精确龙的罐头标签")
                for index = 2, #f.tabs do
                    check(f.tabs[index].x > f.tabs[index - 1].x, "九列中心递增")
                    check(f.tabs[index].x - f.tabs[index - 1].x > f.tabs[index].width, "九列不重叠")
                    if index > 2 then check(math.abs((f.tabs[index].x - f.tabs[index - 1].x) - (f.tabs[2].x - f.tabs[1].x)) < 0.001, "九列动态等宽") end
                end
                local scale = math.min(w / 1920, h / 1080)
                local bellTab = f.tabs[7]
                f.Panel.selectRecord(N02); f.Panel.handleInput(bellTab.x * scale, bellTab.y * scale, w, h)
                check(includes(f.draw(w, h), MIRRORS[2].title), "第七tab实际选N09")
                local openingTab = f.tabs[8]
                f.Panel.selectRecord(N02); f.Panel.handleInput(openingTab.x * scale, openingTab.y * scale, w, h)
                local openingText = f.draw(w, h)
                check(includes(openingText, f.Config.get("samsara.opening_roster").title), "第八tab实际选N01")
                check(includes(openingText, "开场经历未确认"), "N01点击仅查阅不补造亲历")
                local dragonTab = f.tabs[9]
                f.Panel.selectRecord(N02); f.Panel.handleInput(dragonTab.x * scale, dragonTab.y * scale, w, h)
                local dragonText = f.draw(w, h)
                check(includes(dragonText, f.Config.get("samsara.dragon_mirror").title), "第九tab实际选N08")
                check(includes(dragonText, "亲历状态未确认"), "N08点击仅查阅不补造亲历")
                eq(f.session.samsaraStory.nodes["samsara.dragon_mirror"], nil, "点击N08不创造资格或来源")
                noExtraEvidence(f)
                f.Panel.selectRecord(item.key); f.draw(w, h)
                local action = f.action("仅供查阅")
                eq(f.Panel.handleInput(action.x * scale, action.y * scale, w, h), true, "参考按钮吞点击")
                eq(f.Panel.isOpen(), true, "参考不关闭/不播")
                eq(f.n("request"), 0, "参考按钮不request")
                eq(f.Panel.handleInput(0, 0, w, h), true, "全窗模态无穿透")
            end
            f.Panel.selectRecord(item.key); f.draw()
            local firstY = f.boxes[1].y
            eq(f.Panel.handleWheel(-2), true, "长文滚轮吞事件")
            f.draw(); check(f.boxes[1].y < firstY, "滚轮实际向下阅读")
            f.Panel.handleWheel(100000); f.draw(); eq(f.boxes[1].y, firstY, "滚动上界钳制")
            local first = f.boxes[1]
            f.Panel.handleDragBegin(first.x + 50, first.y + 80)
            f.Panel.handleDragMove(first.x + 50, first.y - 180)
            local dragged = f.Panel.handleDragEnd(); eq(dragged, true, "touch拖动不是点击")
            if not dragged then local action = f.action("仅供查阅"); f.Panel.handleInput(action.x, action.y, 1920, 1080) end
            f.draw(); check(f.boxes[1].y < firstY, "touch实际移动正文")
            eq(f.n("request"), 0, "拖动不误请求")
            f.Panel.selectRecord(item.key); f.draw(); eq(f.boxes[1].y, firstY, "换tab重置滚动")
            eq(f.Playback.tryPlay(gates()), false, "静态阅读无Playback")
            eq(f.n("begin"), 0, "静态不租约")
            eq(f.n("show"), 0, "静态不show")
            eq(f.flushes, flushes, "选取/滚动不保存")
            check(same(f.session, before), "静态阅读无任何session写入")
        end)
        for _, ending in ipairs({ "dismissed", "skipped", "reset", "replaced", "failed", "throw" }) do
            runCase("真实Playback与独立Dialogue终态 " .. item.key .. "/" .. ending, function()
                local f = presentation(fixture()); live(f, item)
                local outside = outsideStory(f.session)
                f.Panel.selectRecord(item.key); f.Panel.open(); local text = f.draw()
                check(includes(text, "来源："), "待阅明确成功来源")
                eq(f.Player.takeRequest(), nil, "select只展示")
                local action = f.action("待阅"); f.Panel.handleInput(action.x, action.y, 1920, 1080)
                eq(f.Dialogue.isActive(), false, "Panel不立即show")
                for _, name in ipairs({ "ready", "legacyPending", "blocked", "pointerBusy" }) do
                    local gate = gates(); gate[name] = name ~= "ready"
                    eq(f.Playback.tryPlay(gate), false, "门禁不消费请求 " .. name)
                end
                local show = f.Dialogue.show
                if ending == "failed" then f.Dialogue.show = function() f.count("show"); return false end
                elseif ending == "throw" then f.Dialogue.show = function() f.count("show"); error("injected show failure") end end
                eq(f.Playback.tryPlay(gates()), ending ~= "failed" and ending ~= "throw", "后帧真实Playback")
                if ending ~= "failed" and ending ~= "throw" then
                    eq(f.shown.mode, "small", "镜像small")
                    eq(f.shown.onFinish, nil, "无旧领奖收尾")
                    eq(f.shown.scenarioId, nil, "无旧编号")
                    eq(f.shown.reward, nil, "无奖励")
                    eq(f.shown.completionToken.nodeKey, item.key, "准确镜像租约")
                    original(f.shown.steps, item, "真实送入Dialogue")
                    f.Dialogue.update(100); f.Dialogue.draw(1920, 1080)
                    eq(f.Display.text(f.shown.steps[1].text), f.shown.steps[1].text, "中文显示全文原样")
                    eq(f.Story.length(f.shown.steps[1].text), utf8.len(f.shown.steps[1].text), "真实长度按UTF-8码点")
                    check(includes(table.concat(f.displayed), f.shown.steps[1].text), "真实fitLayout/drawRows完整绘制中文首句")
                end
                if ending == "dismissed" then finishDialogue(f.Dialogue); eq(record(f, item).status, "pending", "动画未完不授片"); f.Dialogue.update(0.31)
                elseif ending == "skipped" then eq(f.Dialogue.handleSliceInput(1800, 130, 1920, 1080), true, "依旧横屏触摸skip")
                elseif ending == "reset" then f.Dialogue.reset()
                elseif ending == "replaced" then show({ mode = "small", steps = f.Config.get(N02).steps }); f.Dialogue.reset() end
                local success = ending == "dismissed" or ending == "skipped"
                eq(record(f, item).status, success and (ending == "skipped" and "skipped" or "finished") or "pending", "真实Dialogue结果映射")
                if success then
                    eq(visible(f, item).text, item.text, "真实结束公开自身初片")
                    f.Panel.open(); text = f.draw(); check(includes(text, item.text), "Panel初片逐字")
                    check(includes(text, "来源："), "Panel凭片仍显示来源")
                    check(not includes(text, "征用签发底档"), "镜像不误标征用来源")
                    check(not includes(text, assert(f.Config.getEvidence("E03-B")).text), "A/C Panel不泄B正文")
                    local saved, count = copy(f.session), f.flushes
                    action = f.action("回看"); f.Panel.handleInput(action.x, action.y, 1920, 1080)
                    eq(f.Playback.tryPlay(gates()), true, "真实回看")
                    eq(f.shown.completionToken.kind, REPLAY, "回看kind")
                    f.Dialogue.skip(); check(same(f.session, saved), "真实回看不改首次来源结果")
                    eq(f.flushes, count, "真实回看不保存")
                else hidden(f, item, "真实中断") end
                check(same(outsideStory(f.session), outside), "真实无奖分支不改旧经济/tutorial/账本")
                noExtraEvidence(f)
            end)
        end
        runCase("真实旧占用先消化且无result不抢/保存中禁按钮 " .. item.key, function()
            local f = presentation(fixture(fresh({ [tostring(item.legacy)] = true })))
            f.Player.onStageCleared(item.stage)
            f.Panel.selectRecord(item.key); f.Panel.open(); f.draw()
            local action = f.action("仅供查阅")
            f.Panel.handleInput(action.x, action.y, 1920, 1080)
            eq(f.n("request"), 0, "pending但referenceOnly不request")
            eq(f.Playback.tryPlay(gates()), false, "缺可信旧结果无自动")
            local legacy = isolated("config/ScenarioDialogueConfig.lua", {})
            local cfg = copy(legacy["SCENARIO_" .. item.legacy]); cfg.onFinish = nil
            cfg.completionToken = { nodeKey = "legacy." .. item.legacy, kind = "legacy_reference" }
            local legacyEpoch = f.Player.getContextEpoch()
            cfg.onResult = function(value) f.Player.noteLegacyResult(item.legacy, value.reason, legacyEpoch) end
            eq(f.Dialogue.show(cfg), true, "旧64/67原对白独立show")
            eq(f.Playback.tryPlay(gates()), false, "真实旧active阻镜像")
            f.Dialogue.skip(); eq(record(f, item).eventTrusted, true, "真实旧skip桥可信")
            eq(f.Playback.tryPlay(gates()), true, "旧结束后下一帧镜像")
            f.save = false; f.Dialogue.skip()
            f.Panel.selectRecord(item.key); f.Panel.open(); f.draw()
            action = f.action("保存中"); local count = f.n("request")
            f.Panel.handleInput(action.x, action.y, 1920, 1080)
            eq(f.n("request"), count, "待存不排回看")
            eq(f.Panel.isOpen(), true, "待存action禁用")
        end)
    end
end

function Start()
    local loaded = {}
    for key, value in pairs(package.loaded) do loaded[key] = value end
    local ok, err = pcall(function()
        assert(type(JSON) == "table" and type(JSON.encode) == "function" and type(JSON.decode) == "function", "需要真实cjson")
        configAndHistoryCases()
        legacyAndTrustCases()
        resultAndVersionCases()
        presentationCases()
        for key, value in pairs(loaded) do eq(package.loaded[key], value, "不污染既有require缓存 " .. key) end
        for key in pairs(package.loaded) do check(loaded[key] ~= nil, "不新增require缓存 " .. key) end
    end)
    if not ok then check(false, "顶层异常: " .. tostring(err)) end
    print(PREFIX .. "RESULT assertions=" .. assertions .. " failures=" .. failures .. " cases=" .. passed .. "/" .. cases)
    if failures == 0 and passed == cases and cases > 0 then print(PREFIX .. "ALL PASS") end
    engine:Exit()
end
