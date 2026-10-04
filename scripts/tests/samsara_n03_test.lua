-- samsara_n03_test.lua — N03契约与真实Player/Playback/Dialogue/Save/Panel独立隔离回归。
-- 正文逐字来自 docs/未寄出的撤离令-剧情正文普通至炼狱-1003.md §N03。
-- 原始源码私有load，不替换源码、不污染package.loaded/全局、不访问真实玩家存档。
-- 作者不运行Runtime/build/LSP；完成后由主会话统一检查和执行。
local PREFIX = "[samsara_n03] "
local assertions, failures, cases, passed = 0, 0, 0, 0
local N02, N03 = "samsara.log_leaf", "samsara.returned_manifest"
local N12, N13, N14 = "samsara.cargo_match", "samsara.gray_order", "samsara.people_record"
local FIRST, REPLAY = "samsara_first_read", "samsara_replay"
local KEYS = { N02, N12, N13, N14, N03, "samsara.dog_mirror", "samsara.bell_mirror", "samsara.opening_roster" }
local ORIGINALS = {
    { "旁白", "铁匠整理被砸坏的货牌。焦黑的一片上还能辨认“药箱十二”，下角画着箱底补铆的位置图，其中一枚打歪。" },
    { "铁匠", "认错你们，我道歉。丢了什么，我记得。", 10 },
    { "远征长", "药箱？" },
    { "铁匠", "药、夹板，还有给伤员留的干粮。不是兵器。", 10 },
    { "黄桃龙", "干粮也抢？这不行。", 2 },
    { "铁匠", "他们说“先救人”。押车的人问救谁，没等到回答。", 10 },
    { "大狗嚼", "叫！下次遇见，我替你问。", 1 },
    { "铁匠", "货牌拿着。别只看它烧黑了。图上这处歪铆，是我给箱底补的。", 10 },
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
    if failures == before then passed = passed + 1; print(PREFIX .. "PASS " .. label) end
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
local function includes(text, needle)
    return type(text) == "string" and text:find(needle, 1, true) ~= nil
end
---@param path string
---@param overrides table
---@param globals table?
---@param fallback (fun(name: string): any)|nil
---@return any
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
        error("未声明依赖/经济路径 " .. path .. ": " .. tostring(name))
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

local function fresh(heroId, claimed)
    return {
        initialHeroId = heroId or 1, introCompleted = true, hasReincarnated = true,
        firstGachaTenDone = true, lastOnlineTime = 9000, firstLoginTime = 100,
        offlineBonusCount = 2, offlineBonusDate = "2026-10-03",
        claimedScenarios = claimed or {}, scenarioRewardsGranted = { ["44"] = true, ["17"] = true },
        tutorialProgress = { groupId = 8, step = 3, custom = { keep = true } },
        introPlayback = { done = true }, unknownSession = { keep = { "old", false, 7 } },
    }
end
local function history(e02, nodes)
    local session = fresh(1, { ["44"] = true })
    session.samsaraStory = { schemaVersion = 1, historyCaptured = true, cargoHistoryCaptured = true,
        nodes = nodes or {}, evidence = e02 and { E02 = e02 } or {}, unknownStory = { keep = 55 } }
    return session
end
local function result(lease, reason)
    return { playToken = lease.playToken, contextEpoch = lease.contextEpoch, nodeKey = lease.nodeKey, reason = reason }
end
local function fixture(session, battle, legacy)
    local f = { session = session or fresh(), disk = {}, sets = 0, flushes = 0, save = true, fault = "" }
    f.Config = isolated("config/SamsaraSliceConfig.lua", {})
    f.Schema = isolated("shared/session/SamsaraStorySchema.lua", {})
    f.Player = isolated("systems/SamsaraSlicePlayer.lua", {
        ["config.SamsaraSliceConfig"] = f.Config, ["shared.session.SamsaraStorySchema"] = f.Schema,
        ["config.ScenarioDialogueConfig"] = legacy or isolated("config/ScenarioDialogueConfig.lua", {}),
    })
    f.options = {
        getSession = function() return f.session end,
        setSession = function(value)
            eq(value, f.session, "只通知共享session同表")
            f.sets = f.sets + 1
            if f.fault == "set" then error("injected set failure") end
        end,
        flush = function()
            f.flushes = f.flushes + 1
            if f.fault == "flush" then error("injected flush failure") end
            if f.save == true then f.disk = copy(f.session) end
            return f.save
        end,
    }
    f.supported = f.Player.init(f.options, battle)
    return f
end
local function finish(f, key, reason)
    local lease = assert(f.Player.begin(FIRST, key), "missing lease " .. key)
    eq(f.Player.onResult(result(lease, reason or "finished")), true, "精确首读结果 " .. key)
    return lease
end
local function evidence(player, key, id)
    for _, item in ipairs(player.getRecord(key).evidences) do if item.id == id then return item end end
    return nil
end
local function expectOriginal(steps, label)
    eq(#steps, 8, label .. "一旁白七正文")
    for index, original in ipairs(ORIGINALS) do
        local step = assert(steps[index])
        eq(step.name, original[1], label .. "人物" .. index)
        eq(step.text, original[2], label .. "逐字原文" .. index)
        eq(step.characterId, original[3], label .. "立绘" .. index)
    end
end

local function configAndSourceCases()
    runCase("旧七KEY严格前缀/八记录末尾N01/八步正文/E02无附页/默认getRecord不变", function()
        local f = fixture()
        eq(f.Config.MANIFEST_KEY, N03, "MANIFEST_KEY命名空间")
        check(same(f.Config.KEYS, KEYS), "旧七索引严格前缀，末尾仅追加N01")
        eq(f.Player.getRecord().key, N02, "省参仍N02")
        local records = f.Player.getRecords()
        eq(#records, 8, "八条记录")
        for index, key in ipairs(KEYS) do eq(records[index].key, key, "稳定索引" .. index) end
        local cfg = assert(f.Config.get(N03))
        eq(cfg.title, "十二号箱", "不另编标题")
        eq(cfg.mode, "small", "无奖small")
        eq(cfg.requiredStage, 204, "锚点204")
        eq(cfg.dependency, nil, "N03没有N02硬前置")
        eq(f.Config.get(N12).dependency, nil, "N12不新增N03前置")
        eq(cfg.scenarioId, nil, "不复用旧44–46ID")
        eq(cfg.reward, nil, "无reward")
        eq(cfg.rewards, nil, "无rewards")
        expectOriginal(cfg.steps, "配置")
        eq(cfg.evidence.id, "E02", "复用原E02")
        eq(cfg.evidence.text, f.Config.get(N12).evidence.text, "货单同一原件")
        for _, field in ipairs({ "annotation", "continuation", "people" }) do eq(cfg.evidence[field], nil, "N03配置不带" .. field) end
        cfg.steps[2].text, cfg.evidence.text = "UI覆盖", "UI覆盖"
        expectOriginal(f.Config.get(N03).steps, "配置深副本")
        eq(f.Config.get(N03).evidence.text, f.Config.get(N12).evidence.text, "修改不污染E02")
        eq(f.Config.get("N03"), nil, "策划编号不是API key")
    end)
    local matrix = {
        { label = "真实player_record", saved = { unlocked = true, source = "player_record", unknown = { keep = 9 } }, eligible = true },
        { label = "case_archive不冒充取得", saved = { unlocked = true, source = "case_archive" } },
        { label = "字符串true不可信", saved = { unlocked = "true", source = "player_record" } },
        { label = "数字1不可信", saved = { unlocked = 1, source = "player_record" } },
        { label = "false不可信", saved = { unlocked = false, source = "player_record" } },
        { label = "缺unlocked", saved = { source = "player_record" } },
        { label = "缺source", saved = { unlocked = true } },
        { label = "未知source", saved = { unlocked = true, source = "max_stage" } },
        { label = "无E02" },
    }
    for _, item in ipairs(matrix) do
        runCase("init只看可信E02且cargo已捕获禁止重扫 " .. item.label, function()
            local session = history(copy(item.saved))
            local old = outsideStory(session)
            local f = fixture(session, { maxStageId = 9999, currentStageId = 4905,
                clearedStages = { [104] = true, [204] = true, [4905] = true } })
            eq(f.Player.getRecord(N03).status, item.eligible and "pending" or "locked", "资格严格布尔和来源")
            eq(f.Player.peekReady(), item.eligible and N03 or nil, "旧claimed历史可自动待播但不伪造清关")
            eq(f.Player.getRecord(N02).status, "locked", "historyCaptured不补104")
            eq(f.Player.getRecord(N12).status, "locked", "cargoHistoryCaptured不补4905")
            if item.eligible then
                eq(session.samsaraStory.nodes[N03].eligibilitySource, "e02_history", "存量来源e02_history")
                eq(session.samsaraStory.nodes[N03].legacyContext, "legacy_claimed_unknown", "历史claimed仅阅读未知")
                eq(session.samsaraStory.nodes[N03].resolution, nil, "不迁移成N03已读")
                eq(session.samsaraStory.evidence.E02.unknown.keep, 9, "E02未知字段保全")
            else
                eq(f.Player.requestRead(N03), false, "locked不请求首读")
                eq(f.Player.begin(FIRST, N03), nil, "locked不产生租约")
                eq(f.Player.begin(REPLAY, N03), nil, "locked不回看")
                eq(f.Player.getRecord(N03).referenceOnly, true, "仅locked静态参考")
                expectOriginal(f.Player.getRecord(N03).referenceSteps, "锁定原文")
            end
            check(same(outsideStory(session), old), "不改旧账本或奖励")
            local after = copy(session)
            local flushes = f.flushes
            f.Player.init(f.options, { clearedStages = { [204] = true } })
            check(same(session, after), "同表init幂等不重扫")
            eq(f.flushes, flushes, "无变化init不落盘")
        end)
    end
    for _, clearKey in ipairs({ 204, "204" }) do
        runCase("尚未cargo捕获的真实raw204先保E02再派生N03 " .. tostring(clearKey), function()
            local f = fixture(fresh(1, { [44] = true }), { clearedStages = { [clearKey] = true } })
            eq(f.Player.getRecord(N03).status, "pending", "首次raw204 E02可派生资格")
            eq(f.session.samsaraStory.nodes[N03].eligibilitySource, "clear_204_legacy", "首次真实raw捕获来源不标实时")
            eq(f.session.samsaraStory.evidence.E02.source, "player_record", "原件可信来源")
            eq(f.flushes, 1, "两个历史和N03一次保存")
        end)
    end
    runCase("raw204历史与既有case_archive独立资格，原来源冻结", function()
        local session = history({ unlocked = true, source = "case_archive", unknown = { keep = 9 } })
        session.samsaraStory.cargoHistoryCaptured = false
        local before = copy(session.samsaraStory.evidence.E02)
        local f = fixture(session, { clearedStages = { [204] = true } })
        eq(f.Player.getRecord(N03).status, "pending", "raw204证明不依赖E02来源")
        eq(session.samsaraStory.nodes[N03].eligibilitySource, "clear_204_legacy", "独立真实历史来源")
        check(same(session.samsaraStory.evidence.E02, before), "既有案件原件字段原样")
        eq(f.Player.getRecord(N12).status, "locked", "不额外造N12资格")
    end)
    runCase("阴性捕获重启不补204/查询静态原文不建N12案件", function()
        local f = fixture(fresh(1, { [44] = true }), { maxStageId = 9999 })
        local disk = copy(f.disk)
        f.Player.getRecords(); f.Player.getRecord(N03); f.Player.peekReady(); f.Player.hasPendingRecords()
        eq(f.session.samsaraStory.evidence.E02, nil, "只读查询不造E02")
        local reboot = fixture(disk, { clearedStages = { [204] = true, [4905] = true } })
        eq(reboot.Player.getRecord(N03).status, "locked", "重启不从后来204反推")
        eq(reboot.Player.getRecord(N12).status, "locked", "重启不从后来4905反推")
        eq(reboot.session.samsaraStory.evidence.E02, nil, "捕获阴性保全")
    end)
    runCase("live204独立资格/冻结case_archive和N02旧语境/不强加N12依赖", function()
        local f = fixture(fresh(2, { [18] = true, [45] = true }), { clearedStages = { [104] = true, [4905] = true } })
        finish(f, N12)
        local old = outsideStory(f.session)
        local n02, n12, e02 = copy(f.session.samsaraStory.nodes[N02]), copy(f.session.samsaraStory.nodes[N12]), copy(f.session.samsaraStory.evidence.E02)
        for _, id in ipairs({ 203, 205, "0204", "204x", "204.0", false }) do eq(f.Player.onStageCleared(id), false, "拒绝非精确204 " .. tostring(id)) end
        eq(f.Player.onStageCleared("204"), true, "即使E02案件存在仍记录真实204")
        eq(f.session.samsaraStory.nodes[N03].eligibilitySource, "live_clear_204", "live资格来源")
        eq(f.session.samsaraStory.nodes[N03].manualOnly, true, "高档已处理N12不被新N03自动抢播")
        check(same(f.session.samsaraStory.nodes[N02], n02), "live204绝不覆盖N02legacy")
        check(same(f.session.samsaraStory.nodes[N12], n12), "旧N12结果和来源状态不变")
        check(same(f.session.samsaraStory.evidence.E02, e02), "case_archive核验不被live204改写")
        eq(f.Player.getRecord(N03).referenceOnly, nil, "pending不是referenceOnly")
        eq(f.Player.onStageCleared(204), false, "重复live204幂等")
        local replay = assert(f.Player.begin(REPLAY, N12))
        eq(f.Player.onResult(result(replay, "skipped")), true, "老N12无需读N03仍可回看")
        check(same(outsideStory(f.session), old), "独立N03无旧奖励/教程写入")
    end)
end

local function legacyAndOrderingCases()
    for heroId = 1, 3 do
        local id = heroId + 43
        for _, reason in ipairs({ "finished", "dismissed", "skipped" }) do
            runCase("N03对应旧初始分支 " .. heroId .. "/" .. reason, function()
                local session = fresh(tostring(heroId))
                local f = fixture(session, {})
                eq(f.Player.onStageCleared(204), true, "真实204资格")
                local old = outsideStory(session)
                eq(f.Player.peekReady(), nil, "未处理对应旧铁匠不自动播")
                eq(f.Player.begin(FIRST, N03), nil, "待旧段begin不抢")
                eq(f.Player.requestRead(N03), true, "待旧源可排显式请求")
                local other = id == 46 and 44 or id + 1
                eq(f.Player.noteLegacyResult(other, reason), false, "非初始分支不能释放")
                eq(f.Player.noteLegacyResult(16 + heroId, reason), false, "无N02资格不能借17–19释放N03")
                eq(f.Player.noteLegacyResult(tostring(id), reason), true, "精确对应旧44–46释放")
                eq(session.samsaraStory.nodes[N03].legacyContext, reason == "skipped" and "live_skipped" or "live_finished", "真实终态映射不是N03resolution")
                eq(session.samsaraStory.nodes[N03].resolution, nil, "旧结果不代替N03首读")
                eq(f.Player.peekReady(), N03, "对应旧来源处理后可自动播")
                eq(f.Player.noteLegacyResult(id, reason), false, "同源结果幂等")
                local request = assert(f.Player.takeRequest())
                eq(request.key, N03, "保留请求正确key")
                eq(request.kind, FIRST, "待阅请求仍首读")
                check(f.Player.begin(request.kind, request.key) ~= nil, "旧终态允许N03begin")
                check(same(outsideStory(session), old), "不写旧claimed/granted")
            end)
        end
        for _, claimedKey in ipairs({ id, tostring(id) }) do
            runCase("历史claimed迁移阅读未知且中断不可借preclaim " .. heroId .. "/" .. tostring(claimedKey), function()
                local session = fresh(heroId, { [claimedKey] = true })
                local f = fixture(session, { clearedStages = { [204] = true } })
                eq(f.Player.getRecord(N03).legacyContext, "legacy_claimed_unknown", "数字/字符串历史claimed迁移")
                check(f.Player.begin(FIRST, N03) ~= nil, "历史未知可补读")
                f.Player.cancel()
                for _, reason in ipairs({ "reset", "replaced", "failed" }) do
                    eq(f.Player.noteLegacyResult(id, reason), reason == "reset", "同live_interrupted记录只首次改变")
                    eq(f.Player.getRecord(N03).legacyContext, "live_interrupted", "中断来源保存")
                    eq(f.Player.peekReady(), nil, "preclaimed不能绕过实时中断")
                    eq(f.Player.begin(FIRST, N03), nil, "preclaimed中断不允许begin")
                    local before = copy(session)
                    f.Player.init(f.options, { clearedStages = { [204] = true } })
                    check(same(session, before), "同进程init不擦除中断")
                end
                for _, reason in ipairs({ "unknown", "skip", "live_finished", "live_skipped" }) do
                    eq(f.Player.noteLegacyResult(id, reason), false, "严格真实reason枚举拒绝 " .. reason)
                end
                eq(f.Player.noteLegacyResult(id, "skipped"), true, "后续真实skip才能释放")
                eq(f.Player.peekReady(), N03, "真实恢复可待播")
                eq(f.Player.getRecord(N03).status, "pending", "旧恢复不替N03已读")
            end)
        end
        runCase("granted不替代claimed且缺旧配置不永久卡住 " .. heroId, function()
            local f = fixture(fresh(heroId), { clearedStages = { [204] = true } })
            f.session.scenarioRewardsGranted[tostring(id)] = true
            eq(f.Player.peekReady(), nil, "granted不作为旧阅读证明")
            eq(f.Player.begin(FIRST, N03), nil, "granted不释放来源")
            local missing = fixture(fresh(heroId), { clearedStages = { [204] = true } }, {})
            eq(missing.Player.getRecord(N03).legacyContext, "unavailable", "缺旧配置明确异常语境")
            check(missing.Player.begin(FIRST, N03) ~= nil, "缺配置允许独立补读")
        end)
    end
    runCase("已知旧中断自动不播但显式request/take/begin可独立补读", function()
        local f = fixture(fresh(1, { [44] = true }), { clearedStages = { [204] = true } })
        f.Player.noteLegacyResult(44, "reset")
        eq(f.Player.peekReady(), nil, "中断不自动抢播")
        eq(f.Player.begin(FIRST, N03), nil, "preclaim本身不授权首读")
        eq(f.Player.requestRead(N03), true, "显式补读请求")
        local request = assert(f.Player.takeRequest())
        eq(f.Player.takeRequest(), nil, "takeRequest单次消费")
        local lease = assert(f.Player.begin(request.kind, request.key))
        eq(f.Player.getRecord(N03).legacyContext, "live_interrupted", "显式补读不伪装旧段完成")
        f.Player.onResult(result(lease, "reset"))
        eq(f.Player.begin(FIRST, N03), nil, "补读租约取消后不能复用授权")
        eq(f.Player.requestRead(N03), true, "再次补读需新请求")
        request = assert(f.Player.takeRequest())
        lease = assert(f.Player.begin(request.kind, request.key))
        eq(f.Player.onResult(result(lease, "skipped")), true, "独立N03补读可处理")
        eq(f.Player.getRecord(N03).legacyContext, "live_interrupted", "新切片结果不改变旧道歉事实")
    end)
    runCase("重启live_interrupted只降为历史未知不标已读", function()
        local f = fixture(fresh(1, { [44] = true }), { clearedStages = { [204] = true } })
        f.Player.noteLegacyResult(44, "failed")
        local reboot = fixture(cjson.decode(cjson.encode(f.disk)), {})
        eq(reboot.Player.getRecord(N03).legacyContext, "legacy_claimed_unknown", "重启保留阅读未知事实")
        eq(reboot.Player.getRecord(N03).status, "pending", "重启绝不伪造finished")
        check(reboot.Player.begin(FIRST, N03) ~= nil, "历史未知可补读")
    end)
    for _, source in ipairs({ "player_record", "case_archive" }) do
        runCase("已有live N03待阅高档重启补manualOnly " .. source, function()
            local session = history({ unlocked = true, source = source }, {
                [N03] = { contentVersion = 1, eligible = true, eligibilitySource = "live_clear_204", legacyContext = "live_skipped" },
                [N12] = { contentVersion = 1, eligible = true, resolution = "finished" },
            })
            local f = fixture(session, {})
            eq(f.Player.getRecord(N03).manualOnly, true, "已推进调查的存量待阅不自动插入")
            eq(session.samsaraStory.nodes[N03].eligibilitySource, "live_clear_204", "不改既有live来源")
            eq(f.Player.peekReady(), N13, "自动继续原调查链")
            eq(f.Player.requestRead(N03), true, "历史manual仍可请求")
            local request = assert(f.Player.takeRequest())
            check(f.Player.begin(request.kind, request.key) ~= nil, "历史manual仍可begin")
        end)
    end
    runCase("自动顺序N02/N03/原cargo链，显式N03无需N02", function()
        local f = fixture(fresh(1, { [17] = true, [44] = true }), { clearedStages = { [104] = true, [204] = true, [4905] = true } })
        eq(f.Player.peekReady(), N02, "N02优先")
        eq(f.Player.requestRead(N03), true, "可显式N03跨N02")
        local request = assert(f.Player.takeRequest())
        eq(request.key, N03, "显式key不被自动顺序抢")
        local lease = assert(f.Player.begin(request.kind, request.key))
        eq(f.Player.getRecord(N02).status, "pending", "N03不代读N02")
        f.Player.onResult(result(lease, "reset"))
        finish(f, N02)
        eq(f.Player.peekReady(), N03, "N02后可自动N03")
        finish(f, N03)
        eq(f.Player.peekReady(), N12, "N03后原cargo首节点")
        finish(f, N12); eq(f.Player.peekReady(), N13, "原N12→N13")
        finish(f, N13); eq(f.Player.peekReady(), N14, "原N13→N14")
        finish(f, N14); eq(f.Player.peekReady(), nil, "处理完不重播")
    end)
    for _, resolution in ipairs({ "finished", "skipped" }) do
        runCase("高档已处理N12的N03历史补读manualOnly " .. resolution, function()
            local session = history({ unlocked = true, source = "player_record", annotationUnlocked = true }, {
                [N12] = { contentVersion = 1, eligible = true, resolution = resolution, unknown = { keep = 8 } },
            })
            local f = fixture(session, {})
            eq(f.session.samsaraStory.nodes[N03].eligibilitySource, "e02_history", "真实历史来源")
            eq(f.session.samsaraStory.nodes[N03].manualOnly, true, "新N03历史手动")
            eq(f.Player.getRecord(N03).manualOnly, true, "展示层返回手动标记")
            eq(f.Player.peekReady(), N13, "自动跳过N03沿原cargo顺序")
            eq(f.Player.hasPendingRecords(), true, "manual待阅仍算记录红点")
            eq(f.Player.requestRead(N03), true, "manual不是禁读")
            local request = assert(f.Player.takeRequest())
            check(f.Player.begin(request.kind, request.key) ~= nil, "manual显式begin可用")
            f.Player.cancel()
            finish(f, N13); finish(f, N14)
            eq(f.Player.peekReady(), nil, "只有manual剩余也不自动抢播")
            eq(f.Player.getRecord(N03).status, "pending", "不因后段处理代读N03")
        end)
    end
end

local function resultsAndPreservationCases()
    for _, reason in ipairs({ "finished", "dismissed", "skipped", "reset", "replaced", "failed" }) do
        runCase("N03首读与回看精确结果/仅E02分层 " .. reason, function()
            local f = fixture(fresh(1, { [44] = true }), { clearedStages = { [204] = true, [4905] = true } })
            local old = outsideStory(f.session)
            local e02 = copy(f.session.samsaraStory.evidence.E02)
            local lease = assert(f.Player.begin(FIRST, N03))
            local flushes = f.flushes
            eq(f.Player.getRecord(N03).evidence, nil, "首读未处理不假称已处理evidence")
            eq(f.Player.onResult(result(lease, reason)), true, "当前结果一次接受")
            eq(f.Player.onResult(result(lease, reason)), false, "迟到重复不覆盖")
            local success = reason == "finished" or reason == "dismissed" or reason == "skipped"
            eq(f.Player.getRecord(N03).status, success and (reason == "skipped" and "skipped" or "finished") or "pending", "精确状态")
            eq(f.flushes, flushes + (success and 1 or 0), "仅首次成功结果保存")
            check(same(f.session.samsaraStory.evidence.E02, e02), "N03不重复解锁或写E02核验")
            eq(evidence(f.Player, N03, "E02").annotation, nil, "N12未处理无annotation")
            eq(evidence(f.Player, N03, "E05"), nil, "N03不拿E05")
            eq(f.Player.getRecord(N13).status, "locked", "N03不释放N13")
            eq(f.Player.getRecord(N03).referenceOnly, nil, "非locked不参考模式")
            if success then
                eq(f.Player.getRecord(N03).evidence.text, f.Config.get(N03).evidence.text, "首次处理显示同一E02原件")
                local saved, count = copy(f.session), f.flushes
                for _, replayReason in ipairs({ "finished", "dismissed", "skipped", "reset", "replaced", "failed" }) do
                    local replay = assert(f.Player.begin(REPLAY, N03))
                    eq(f.Player.onResult(result(replay, replayReason)), true, "回看结束 " .. replayReason)
                    check(same(f.session, saved), "回看保首读结果/来源/旧字段 " .. replayReason)
                    eq(f.flushes, count, "回看不重复保存 " .. replayReason)
                end
                finish(f, N12)
                eq(evidence(f.Player, N03, "E02").annotation, f.Config.get(N12).evidence.annotation, "仅N12处理才公开E02annotation")
            else
                check(f.Player.begin(FIRST, N03) ~= nil, "中断保留待阅可重试")
                f.Player.cancel()
            end
            local reboot = fixture(cjson.decode(cjson.encode(f.session)), {})
            eq(reboot.Player.getRecord(N03).status, f.Player.getRecord(N03).status, "JSON往返首次状态")
            check(same(outsideStory(f.session), old), "所有结果无旧经济与教程副作用")
        end)
    end
    runCase("错误token/epoch/key/未知reason/取消/静默换session迟到保全", function()
        local f = fixture(fresh(1, { [44] = true }), { clearedStages = { [204] = true } })
        local lease = assert(f.Player.begin(FIRST, N03))
        for _, field in ipairs({ "playToken", "contextEpoch", "nodeKey" }) do
            local bad = result(lease, "finished"); bad[field] = field == "nodeKey" and N12 or -1
            eq(f.Player.onResult(bad), false, "错误租约身份 " .. field)
        end
        eq(f.Player.onResult(result(lease, "unknown")), false, "未知结果不消费")
        f.Player.cancel()
        eq(f.Player.onResult(result(lease, "finished")), false, "取消租约迟到拒绝")
        local newer = assert(f.Player.begin(FIRST, N03))
        check(newer.playToken > lease.playToken and newer.contextEpoch > lease.contextEpoch, "新身份递增")
        f.session = fresh()
        eq(f.Player.onResult(result(newer, "skipped")), false, "静默换session旧结果拒绝")
        eq(f.session.samsaraStory, nil, "不为新session造story")
        f.Player.init(f.options, {})
        eq(f.Player.onResult(result(newer, "finished")), false, "重init后旧结果仍拒绝")
        eq(f.Player.getRecord(N03).status, "locked", "新session未伪解锁")
    end)
    for _, version in ipairs({ 2, "99" }) do
        runCase("未来schema只读保全 " .. tostring(version), function()
            local session = fresh()
            session.samsaraStory = { schemaVersion = version, nodes = "future", evidence = false,
                historyCaptured = "future", cargoHistoryCaptured = "future", unknown = { keep = 3 } }
            local before = copy(session)
            local f = fixture(session, { clearedStages = { [204] = true } })
            eq(f.supported, false, "未来schema禁用")
            eq(f.Player.getRecord(N03).status, "unsupported", "未来不是locked参考模式")
            eq(f.Player.getRecord(N03).referenceOnly, nil, "未来不提供静态假兼容")
            eq(f.Player.requestRead(N03), false, "未来不请求")
            eq(f.Player.begin(FIRST, N03), nil, "未来不首读")
            eq(f.Player.begin(REPLAY, N03), nil, "未来不回看")
            eq(f.Player.onStageCleared(204), false, "未来不写204资格")
            eq(f.Player.noteLegacyResult(44, "finished"), false, "未来不写旧语境")
            f.Player.cancel(); f.Player.update(100)
            eq(f.flushes, 0, "未来不保存")
            check(same(session, before), "未来嵌套表所有字段原样")
        end)
    end
    runCase("未来N03内容和运行中升级拒绝迟到写入", function()
        local session = history({ unlocked = true, source = "player_record" }, {
            [N03] = { eligible = "future", contentVersion = 99, resolution = "future", manualOnly = "future", unknown = { keep = 8 } },
        })
        local node = copy(session.samsaraStory.nodes[N03])
        local f = fixture(session, {})
        eq(f.Player.getRecord(N03).status, "unsupported", "未来内容禁用")
        eq(f.Player.onStageCleared(204), false, "真实204不能覆盖未来N03")
        eq(f.Player.requestRead(N03), false, "未来内容不请求")
        eq(f.Player.begin(FIRST, N03), nil, "未来内容不begin")
        check(same(session.samsaraStory.nodes[N03], node), "未来N03原样保全")
        local current = fixture(fresh(1, { [44] = true }), { clearedStages = { [204] = true } })
        local lease = assert(current.Player.begin(FIRST, N03))
        current.session.samsaraStory.schemaVersion = 2
        local before, flushes = copy(current.session), current.flushes
        eq(current.Player.onResult(result(lease, "finished")), false, "活跃租约遇未来schema拒绝")
        eq(current.Player.onStageCleared(204), false, "运行中未来不写新资格")
        eq(current.Player.noteLegacyResult(44, "skipped"), false, "运行中未来不写语境")
        check(same(current.session, before), "运行中升级原样")
        eq(current.flushes, flushes, "运行中升级不Flush")
    end)
    runCase("两独立schema路径规范N03 manualOnly/未知字段与未来保全", function()
        local schema = isolated("shared/session/SamsaraStorySchema.lua", {})
        local registry = isolated("shared/ModuleRegistry.lua", { ["shared.session.SamsaraStorySchema"] = schema })
        local sessionSchema = isolated("shared/session/SessionSchema.lua", { ["shared.session.SamsaraStorySchema"] = schema })
        local character = isolated("shared/schemas/CharacterSchema.lua", { ["shared.session.SessionSchema"] = sessionSchema }, nil,
            function(name) assert(name:match("^shared%..+Schema$")); return { Fields = {} } end)
        local loaders = { registry.find("session").onLoad, character.Fields.session.onLoad }
        for index, onLoad in ipairs(loaders) do
            local session = history({ unlocked = "true", source = "player_record", unknown = { keep = 8 } }, {
                [N03] = { eligible = "true", contentVersion = "1", manualOnly = "true", resolution = "reset", unknown = { keep = 9 } },
            })
            local old = outsideStory(session)
            onLoad(session)
            local node = session.samsaraStory.nodes[N03]
            eq(node.eligible, false, "schema资格严格 " .. index)
            eq(node.manualOnly, false, "schema手动标记严格 " .. index)
            eq(node.resolution, nil, "schema中断不假已读 " .. index)
            eq(node.unknown.keep, 9, "schema未知节点字段 " .. index)
            eq(session.samsaraStory.evidence.E02.unknown.keep, 8, "schema未知证据字段 " .. index)
            check(same(outsideStory(session), old), "独立onLoad保全旧字段 " .. index)
            local normalized = copy(session); onLoad(session)
            check(same(session, normalized), "独立onLoad幂等 " .. index)
            session.samsaraStory.schemaVersion = 2
            local future = copy(session.samsaraStory); onLoad(session)
            check(same(session.samsaraStory, future), "独立onLoad保全未来story " .. index)
        end
    end)
end

-- 真实集成fixture：仅File/cjson/图形和无关系统边界替身，四业务模块原样load。
local function integration(session, battle)
    local f = { disk = "", fail = "", calls = {}, drawings = {}, buttons = {}, font = 38 }
    function f.count(name) f.calls[name] = (f.calls[name] or 0) + 1 end
    function f.n(name) return f.calls[name] or 0 end
    local schema = isolated("shared/session/SamsaraStorySchema.lua", {})
    local registry = isolated("shared/ModuleRegistry.lua", { ["shared.session.SamsaraStorySchema"] = schema })
    local sessionSchema = isolated("shared/session/SessionSchema.lua", { ["shared.session.SamsaraStorySchema"] = schema })
    local character = isolated("shared/schemas/CharacterSchema.lua", { ["shared.session.SessionSchema"] = sessionSchema }, nil,
        function(name) assert(name:match("^shared%..+Schema$")); return { Fields = {} } end)
    f.Config = isolated("config/SamsaraSliceConfig.lua", {})
    f.Dispatcher = isolated("runtime/ClientDispatcher.lua", { ["shared.Protocol"] = {},
        ["shared.ModuleRegistry"] = registry, ["shared.schemas.CharacterSchema"] = character })
    f.Dispatcher.set("session", session or fresh(1, { ["44"] = true }))
    f.Dispatcher.set("battle", battle or {})
    f.Dispatcher.set("currency", { gold = 123, gems = 456 })
    f.gameState = { gold = 123, exp = 11, unknown = { keep = true } }
    f.Save = isolated("boot/StandaloneSave.lua", {
        ["runtime.ClientDispatcher"] = f.Dispatcher,
        ["core.GameState"] = { exportSave = function() return f.gameState end, importSave = function(value) f.gameState = value end,
            syncPlayerData = function(player, options)
                f.count("player.sync")
                eq(player, f.Dispatcher.get("player"), "Restore同步已发布player")
                eq(options.silent, true, "Restore仅静默同步")
            end },
        ["ui.battle.scene.BattleScene"] = { setBattleData = function() f.count("battle.apply") end },
        ["rules.offline.OfflineService"] = {
            HasPendingRewards = function() f.count("offline.pending"); return false end,
            MarkOnline = function() f.count("offline.mark") end,
        },
    }, {
        cjson = { encode = function(value)
            f.count("encode")
            if f.fail == "encode" then error("injected encoding failure") end
            return cjson.encode(value)
        end, decode = function(value) return cjson.decode(value) end },
        fileSystem = {
            FileExists = function(_, path)
                eq(path, "standalone_save.json", "恢复只查询已提交文件")
                return f.disk ~= ""
            end,
            Rename = function(_, from, to)
                f.count("rename")
                eq(from, "standalone_save.pending.json", "原子替换来源为临时文件")
                eq(to, "standalone_save.json", "原子替换目标为正式文件")
                if f.fail == "rename" or not f.tempWritten or not f.tempClosed then return false end
                f.disk, f.temp, f.tempClosed, f.tempWritten = f.temp, nil, false, false
                return true
            end,
            Delete = function(_, path)
                f.count("temp.delete")
                eq(path, "standalone_save.pending.json", "失败只清临时文件不删旧档")
                f.temp, f.tempClosed, f.tempWritten = nil, false, false
                return true
            end,
        },
        File = function(path, mode)
            eq(path, mode == FILE_WRITE and "standalone_save.pending.json" or "standalone_save.json", "真实Save写临时/读正式")
            f.count(mode == FILE_WRITE and "write.open" or "read.open")
            local opened = not (mode == FILE_WRITE and f.fail == "open")
            if mode == FILE_WRITE and opened then f.temp, f.tempClosed, f.tempWritten = "", false, false end
            return {
                IsOpen = function() return opened end,
                WriteString = function(_, value)
                    f.count("write")
                    if not opened then return false end
                    if f.fail == "write" then f.temp = value:sub(1, math.floor(#value / 2)); return false end
                    f.temp, f.tempWritten = value, true; return true
                end,
                ReadString = function() return f.disk end,
                Close = function()
                    f.count("file.close")
                    if mode == FILE_WRITE and opened then f.tempClosed = true end
                end,
            }
        end,
    })
    local dependencies = { ["config.SamsaraSliceConfig"] = f.Config, ["shared.session.SamsaraStorySchema"] = schema,
        ["config.ScenarioDialogueConfig"] = isolated("config/ScenarioDialogueConfig.lua", {}) }
    for _, name in ipairs({ "runtime.GameAction", "rules.character.PlayerDataManager", "runtime.ClientMessageHandler",
        "systems.TutorialManager", "systems.StoryPlayer" }) do
        dependencies[name] = setmetatable({}, { __index = function(_, method)
            return function() f.count("forbidden." .. name .. "." .. tostring(method)); return false end
        end })
    end
    f.Player = isolated("systems/SamsaraSlicePlayer.lua", dependencies)
    f.Dispatcher.subscribe("session", f.Player.onSessionUpdated)
    f.options = { getSession = function() return f.Dispatcher.get("session") end,
        setSession = function(value) f.count("session.set"); f.Dispatcher.set("session", value) end,
        flush = function() f.count("flush"); return f.Save.Flush() end }
    function f.session() return assert(f.Dispatcher.get("session")) end
    function f.init(raw) return f.Player.init(f.options, raw or f.Dispatcher.get("battle")) end
    f.Bus = isolated("core/EventBus.lua", {})
    local draw = {
        hitTest = function(x, y, cx, cy, w, h) return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5 end,
        drawTextStroke = function(_, x, y, text) f.drawings[#f.drawings + 1] = text; f.buttons[#f.buttons + 1] = { x = x, y = y, text = text } end,
        drawImageCover = function() f.count("draw.image") end,
        drawRoundedRectCentered = function() end,
    }
    local graphics = {
        nvgCreateImage = function() return -1 end,
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
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgIntersectScissor", "nvgScale", "nvgFontFace",
        "nvgTextAlign", "nvgTextLineHeight", "nvgFillColor", "nvgScissor", "nvgTranslate", "nvgBeginPath",
        "nvgRect", "nvgFill", "nvgRoundedRect", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgResetScissor" }) do graphics[name] = function() end end
    local dialogueDependencies = storyBoundary(f, graphics, dependencies["config.ScenarioDialogueConfig"])
    dialogueDependencies["core.DrawUtil"] = draw
    dialogueDependencies["config.GameConfig"] = isolated("config/GameConfig.lua", {})
    dialogueDependencies["ui.widget.HeroFrame"] = { draw = function() f.count("draw.hero") end }
    dialogueDependencies["core.EventBus"] = f.Bus
    f.Dialogue = isolated("ui/story/ScenarioDialogue.lua", dialogueDependencies, graphics)
    dependencies["systems.SamsaraSlicePlayer"], dependencies["ui.story.ScenarioDialogue"] = f.Player, f.Dialogue
    f.Playback = isolated("systems/SamsaraSlicePlayback.lua", dependencies)
    f.Panel = isolated("ui/story/SamsaraRecordPanel.lua", { ["core.DrawUtil"] = draw,
        ["core.DarkIcon"] = { draw = function() end, drawNine = function() end }, ["systems.SamsaraSlicePlayer"] = f.Player }, graphics)
    return f
end
local function gates()
    return { ready = true, blocked = false, legacyPending = false, pointerBusy = false }
end
local function finishDialogue(dialogue)
    local _, total = dialogue.getProgress()
    for _ = 1, total do dialogue.update(100); dialogue.advance() end
end
local function panelContent(f, key, w, h)
    f.drawings, f.buttons = {}, {}
    check(f.Panel.selectRecord(key), "Panel支持key " .. key)
    f.Panel.open(); f.Panel.draw({}, w or 1920, h or 1080)
    return table.concat(f.drawings, "\n")
end
local function noRewards(f, before)
    for name, count in pairs(f.calls) do if name:match("^forbidden%.") then eq(count, 0, "无经济/教程/FOLLOW路径 " .. name) end end
    check(same(outsideStory(f.session()), before), "真实集成所有旧session字段不变")
    eq(f.Dispatcher.get("currency").gold, 123, "不改金币")
    eq(f.Dispatcher.get("currency").gems, 456, "不改钻石")
    eq(f.gameState.exp, 11, "不改经验")
    eq(f.n("battle.apply"), 0, "不回灌战斗场景")
    eq(f.n("offline.mark"), 0, "不推进离线边界")
end

local function integrationCases()
    runCase("locked N03静态原文Panel仅展示/八列响应式/不request-lease-save", function()
        local f = integration(); f.init()
        local old, before, flushes = outsideStory(f.session()), copy(f.session()), f.n("flush")
        local read, begin, show = f.Player.requestRead, f.Player.begin, f.Dialogue.show
        f.Player.requestRead = function(key) f.count("request"); return read(key) end
        f.Player.begin = function(kind, key) f.count("begin"); return begin(kind, key) end
        f.Dialogue.show = function(cfg) f.count("show"); return show(cfg) end
        for _, size in ipairs({ { 1920, 1080 }, { 2340, 1080 }, { 1280, 800 } }) do
            local w, h = size[1], size[2]
            local text = panelContent(f, N03, w, h)
            check(includes(text, "剧情原文／亲历状态未确认"), "locked原文标明未确认")
            for _, original in ipairs(ORIGINALS) do check(includes(text, original[2]), "locked可见逐字正文") end
            check(not includes(text, f.Config.get(N03).evidence.text), "locked不造并公开E02货单")
            check(not includes(text, "回看"), "locked无回看action")
            local centers, tabY = {}, 0
            local labels = { ["日志夹页"] = true, ["货牌核验"] = true, ["灰印令"] = true, ["人员卷"] = true, ["十二号箱"] = true,
                ["狗的绳结"] = true, ["第三声铃"] = true, ["名册末页"] = true }
            for _, button in ipairs(f.buttons) do
                if labels[button.text] and button.y < 300 then centers[#centers + 1] = button.x; tabY = button.y end
            end
            eq(#centers, 8, "真实绘制八个标签")
            for index = 2, #centers do
                check(centers[index] > centers[index - 1], "八标签中心递增")
                if index > 2 then check(math.abs((centers[index] - centers[index - 1]) - (centers[2] - centers[1])) < 0.001, "八列等宽") end
            end
            local scale = math.min(w / 1920, h / 1080)
            local action = {}
            for _, button in ipairs(f.buttons) do if button.text == "暂未开放" and button.y > 800 then action = button end end
            check(action.x ~= nil, "locked禁用action存在")
            f.Panel.handleInput(action.x * scale, action.y * scale, w, h)
            eq(f.Panel.isOpen(), true, "locked点action不关闭不读完成")
            eq(f.n("request"), 0, "locked action不request")
            -- 点击旧第五项N03验证真实handleInput使用同一动态八列，而非私有状态检查。
            f.Panel.selectRecord(N02)
            f.Panel.handleInput(centers[5] * scale, tabY * scale, w, h)
            f.drawings = {}; f.Panel.draw({}, w, h)
            check(includes(table.concat(f.drawings, "\n"), "剧情原文／亲历状态未确认"), "第五标签实际点选N03")
        end
        eq(f.Playback.tryPlay(gates()), false, "locked静态查看不进入Playback")
        eq(f.n("begin"), 0, "静态查看不发租约")
        eq(f.n("show"), 0, "静态查看不show")
        eq(f.n("flush"), flushes, "静态查看不保存")
        check(same(f.session(), before), "静态查看不写N03resolution或E02")
        noRewards(f, old)
    end)
    for _, ending in ipairs({ "dismissed", "skipped", "reset", "replaced", "failed" }) do
        runCase("真实N03 Playback/Dialogue精确结果与Panel待阅回看 " .. ending, function()
            local f = integration(nil, { clearedStages = { [204] = true } }); f.init()
            local old = outsideStory(f.session())
            local show, configs = f.Dialogue.show, {}
            f.Dialogue.show = function(cfg)
                configs[#configs + 1] = cfg
                eq(cfg.mode, "small", "真实N03small")
                eq(cfg.title, "十二号箱", "真实标题")
                eq(cfg.onFinish, nil, "无旧领奖onFinish")
                eq(cfg.completionToken.nodeKey, N03, "真实租约N03")
                expectOriginal(cfg.steps, "送入Dialogue")
                if ending == "failed" then return show({ steps = {} }) end
                return show(cfg)
            end
            local text = panelContent(f, N03)
            check(includes(text, "待阅"), "资格已成立仍正常待阅action")
            check(not includes(text, "剧情原文／亲历状态未确认"), "pending无reference横幅")
            eq(f.Player.takeRequest(), nil, "selectRecord仅展示不请求")
            eq(f.Panel.handleInput(1588, 928, 1920, 1080), true, "action正常排待阅")
            eq(f.Dialogue.isActive(), false, "Panel action不同步show")
            for _, name in ipairs({ "ready", "legacyPending", "blocked", "pointerBusy" }) do
                local gate = gates(); gate[name] = name ~= "ready"
                eq(f.Playback.tryPlay(gate), false, "真实门禁不消费请求 " .. name)
            end
            eq(f.Playback.tryPlay(gates()), ending ~= "failed", "后帧真实Playback展示或失败")
            if ending ~= "failed" then
                f.Dialogue.update(100); f.Dialogue.draw(1920, 1080)
                eq(f.Display.text(ORIGINALS[1][2]), ORIGINALS[1][2], "中文显示全文原样")
                eq(f.Story.length(ORIGINALS[1][2]), utf8.len(ORIGINALS[1][2]), "真实长度按UTF-8码点")
                check(includes(table.concat(f.displayed), ORIGINALS[1][2]), "真实fitLayout/drawRows完整绘制中文首句")
            end
            if ending == "dismissed" then
                finishDialogue(f.Dialogue)
                eq(f.Player.getRecord(N03).status, "pending", "dismiss动画前无假完成")
                f.Dialogue.update(0.31)
            elseif ending == "skipped" then f.Dialogue.skip()
            elseif ending == "reset" then f.Dialogue.reset()
            elseif ending == "replaced" then show({ mode = "small", steps = f.Config.get(N02).steps }) end
            local success = ending == "dismissed" or ending == "skipped"
            eq(f.Player.getRecord(N03).status, success and (ending == "skipped" and "skipped" or "finished") or "pending", "真实终态映射")
            eq(#configs, 1, "结束不递归show")
            eq(evidence(f.Player, N03, "E02").annotation, nil, "不提前公开核验")
            eq(evidence(f.Player, N03, "E05"), nil, "不提前取得续令或人员卷")
            if success then
                text = panelContent(f, N03)
                check(includes(text, "回看"), "已处理action回看不变")
                check(includes(text, f.Config.get(N03).evidence.text), "已处理显示E02原件")
                local before, flushes = copy(f.session()), f.n("flush")
                f.Panel.handleInput(1588, 928, 1920, 1080)
                eq(f.Playback.tryPlay(gates()), true, "真实回看Playback")
                eq(configs[2].completionToken.kind, REPLAY, "真实回看kind")
                f.Dialogue.skip()
                check(same(f.session(), before), "回看保持首次结果来源")
                eq(f.n("flush"), flushes, "真实回看不落盘")
                eq(cjson.decode(f.disk).modules.session.samsaraStory.nodes[N03].resolution, f.Player.getRecord(N03).status, "真实SaveJSON首次结果")
            end
            noRewards(f, old)
        end)
    end
    runCase("真实旧44结果桥阻抢/204不改N02/自动N02→N03→N12/旧来源冻结", function()
        local session = fresh(1, { [17] = true })
        local f = integration(session, { clearedStages = { [104] = true, [4905] = true } }); f.init()
        local old = outsideStory(f.session())
        f.Player.onStageCleared(204)
        local n02 = copy(f.session().samsaraStory.nodes[N02])
        local legacy = isolated("config/ScenarioDialogueConfig.lua", {})
        local cfg = copy(legacy.SCENARIO_44)
        cfg.onFinish = nil -- 旧领奖边界不运行；只核对真实Dialogue的有ID结果桥。
        cfg.completionToken = { nodeKey = "legacy.44", kind = "legacy_reference" }
        cfg.onResult = function(value) f.Player.noteLegacyResult(44, value.reason) end
        eq(f.Dialogue.show(cfg), true, "真实旧铁匠占用")
        eq(f.Playback.tryPlay(gates()), false, "旧剧情占用不抢N03或N02")
        f.Dialogue.skip()
        eq(f.Player.getRecord(N03).legacyContext, "live_skipped", "真实旧skip桥写入N03语境")
        check(same(f.session().samsaraStory.nodes[N02], n02), "旧44桥不覆盖N02")
        local show, keys = f.Dialogue.show, {}
        f.Dialogue.show = function(value) keys[#keys + 1] = value.completionToken.nodeKey; return show(value) end
        for _, key in ipairs({ N02, N03, N12, N13, N14 }) do
            eq(f.Playback.tryPlay(gates()), true, "真实自动顺序 " .. key)
            eq(keys[#keys], key, "真实送入Dialogue顺序")
            f.Dialogue.skip()
        end
        eq(f.Playback.tryPlay(gates()), false, "自动全处理不重播")
        noRewards(f, old)
    end)
    for _, fault in ipairs({ "open", "write", "encode", "rename" }) do
        runCase("真实N03 Save失败/Panel保存中/节流与重启 " .. fault, function()
            local f = integration(nil, { clearedStages = { [204] = true } }); f.init()
            local old = outsideStory(f.session())
            local before, renames = f.disk, f.n("rename")
            f.Playback.tryPlay(gates()); f.fail = fault; f.Dialogue.skip()
            eq(f.n("rename"), renames + (fault == "rename" and 1 or 0), "仅完整临时写入后尝试Rename")
            eq(f.temp, nil, "故障清理临时缓冲")
            eq(f.Player.getRecord(N03).status, "skipped", "写失败保内存结果")
            eq(f.Player.isSavePending(), true, "写失败明确待存")
            eq(f.disk, before, "写失败磁盘bytes不变")
            local text = panelContent(f, N03)
            check(includes(text, "保存中"), "待存禁用Panel回看")
            f.Panel.handleInput(1588, 928, 1920, 1080)
            eq(f.Player.takeRequest(), nil, "待存按钮不排请求")
            local reboot = integration(cjson.decode(before).modules.session, {})
            reboot.init()
            eq(reboot.Player.getRecord(N03).status, "pending", "未保存重启只补读，不假已存")
            local attempts = f.n("flush")
            f.Player.cancel(); f.Player.init(f.options, { clearedStages = { [4905] = true } })
            eq(f.Player.isSavePending(), true, "同表init和cancel不丢待存")
            eq(f.Player.getRecord(N12).status, "locked", "失败期间不重扫后来4905")
            f.Player.update(1.99)
            eq(f.n("flush"), attempts, "两秒前不轰炸")
            f.fail = ""; f.Player.update(0.02)
            eq(f.n("flush"), attempts + 1, "恢复真实Flush一次")
            eq(f.Player.isSavePending(), false, "成功才清待存")
            eq(cjson.decode(f.disk).modules.session.samsaraStory.nodes[N03].resolution, "skipped", "恢复后磁盘保首次skip")
            eq(f.Save.RestoreData(), true, "真实Save.RestoreData JSON发布")
            f.init({ clearedStages = { [4905] = true } })
            eq(f.Player.getRecord(N03).status, "skipped", "Restore不重播已存N03")
            eq(f.Player.getRecord(N12).status, "locked", "Restore捕获阴性不补4905")
            noRewards(f, old)
        end)
    end
    runCase("真实JSON合法重附接受当前N03租约、未来更新拒绝", function()
        local f = integration(nil, { clearedStages = { [204] = true } }); f.init()
        f.Playback.tryPlay(gates())
        local replacement = copy(f.session())
        f.Dispatcher.handleStateUpdate(cjson.encode({ modules = { session = replacement } }))
        f.Dialogue.skip()
        eq(f.Player.getRecord(N03).status, "skipped", "合法同游戏JSON重附当前精确租约")
        eq(f.Player.requestRead(N03), true, "重附后正常回看")
        f.Playback.tryPlay(gates())
        replacement = copy(f.session()); replacement.samsaraStory.schemaVersion = 2
        f.Dispatcher.handleStateUpdate(cjson.encode({ modules = { session = replacement } }))
        local before, flushes = copy(f.session()), f.n("flush")
        f.Dialogue.skip()
        eq(f.Player.getRecord(N03).status, "unsupported", "未来JSON更新禁用")
        check(same(f.session(), before), "迟到回看不写未来结构")
        eq(f.n("flush"), flushes, "未来JSON不落盘")
    end)
end

function Start()
    local ok, err = pcall(function()
        configAndSourceCases()
        legacyAndOrderingCases()
        resultsAndPreservationCases()
        integrationCases()
    end)
    if not ok then check(false, "顶层异常: " .. tostring(err)) end
    print(PREFIX .. "RESULT assertions=" .. assertions .. " failures=" .. failures .. " cases=" .. passed .. "/" .. cases)
    if failures == 0 and passed == cases and cases > 0 then print(PREFIX .. "ALL PASS") end
    engine:Exit()
end
