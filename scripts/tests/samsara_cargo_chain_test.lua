-- samsara_cargo_chain_test.lua — N12–N14 真实模块隔离回归。
-- 仅私有env加载原始源码；session/Flush为内存边界，不污染全局require/真实存档。
-- 正文依据 docs/未寄出的撤离令-剧情正文普通至炼狱-1003.md 与最小切片接线方案。
-- 不由作者运行或build；主会话统一验收。
local PREFIX = "[samsara_cargo_chain] "
local assertions, failures, cases, passed = 0, 0, 0, 0
local N02, N12, N13, N14 = "samsara.log_leaf", "samsara.cargo_match", "samsara.gray_order", "samsara.people_record"
local FIRST, REPLAY = "samsara_first_read", "samsara_replay"
local N03 = "samsara.returned_manifest"
local KEYS = { N02, N12, N13, N14, N03 }
local INDEX_KEYS = { N02, N12, N13, N14, N03, "samsara.dog_mirror", "samsara.bell_mirror", "samsara.opening_roster", "samsara.dragon_mirror", "samsara.nightmare_afterimage" }

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
local function outsideStory(session)
    local out = {}
    for key, value in pairs(session) do if key ~= "samsaraStory" then out[key] = copy(value) end end
    return out
end
---@param path string
---@param overrides table
---@return any
local function isolated(path, overrides)
    local file = cache:GetFile(path)
    assert(file and file:IsOpen(), "missing real module " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local env = setmetatable({ require = function(name)
        if overrides[name] ~= nil then return overrides[name] end
        error("未声明依赖/经济路径: " .. name)
    end }, { __index = _G })
    return assert(load(table.concat(lines, "\n"), "@" .. path, "t", env))()
end
local function fresh()
    return {
        initialHeroId = 1, introCompleted = true, claimedScenarios = {},
        scenarioRewardsGranted = { ["17"] = true, ["73"] = true },
        tutorialProgress = { completed = { ["3"] = true }, unknown = { keep = 9 } },
        introPlayback = { done = true }, firstLoginTime = 123, offlineBonusCount = 2,
        unknownSession = { nested = { true, false, "keep" } },
    }
end
local function fixture(session, battle)
    local f = { session = session or fresh(), flushes = 0, sets = 0, disk = {}, save = true, throw = false }
    f.Config = isolated("config/SamsaraSliceConfig.lua", {})
    f.Schema = isolated("shared/session/SamsaraStorySchema.lua", {})
    f.Player = isolated("systems/SamsaraSlicePlayer.lua", {
        ["config.SamsaraSliceConfig"] = f.Config,
        ["shared.session.SamsaraStorySchema"] = f.Schema,
        ["config.ScenarioDialogueConfig"] = isolated("config/ScenarioDialogueConfig.lua", {}),
    })
    f.options = {
        getSession = function() return f.session end,
        setSession = function(value)
            eq(value, f.session, "通知只交回共享session同表")
            f.sets = f.sets + 1
        end,
        flush = function()
            f.flushes = f.flushes + 1
            if f.throw then error("模拟写盘异常") end
            if f.save == true then f.disk = copy(f.session) end
            return f.save
        end,
    }
    f.supported = f.Player.init(f.options, battle)
    return f
end
local function result(lease, reason)
    return { playToken = lease.playToken, contextEpoch = lease.contextEpoch, nodeKey = lease.nodeKey, reason = reason }
end
local function complete(f, key, reason)
    local lease = assert(f.Player.begin(FIRST, key), "missing first-read lease " .. key)
    eq(f.Player.onResult(result(lease, reason or "finished")), true, key .. "精确结果接受")
    return lease
end
local function evidence(f, key, id)
    for _, item in ipairs(f.Player.getRecord(key).evidences) do if item.id == id then return item end end
    return nil
end
local function contains(text, needle)
    return type(text) == "string" and text:find(needle, 1, true) ~= nil
end
local function expectDialogue(cfg, lines, label)
    local spoken = {}
    for _, step in ipairs(cfg.steps) do
        if step.name ~= "旁白" then spoken[#spoken + 1] = step end
    end
    eq(#spoken, #lines, label .. "正文句数不增编剧情")
    for i, line in ipairs(lines) do
        local step = assert(spoken[i], label .. "缺正文" .. i)
        eq(step.name, line[1], label .. "人物" .. i)
        eq(step.text, line[2], label .. "逐字原文" .. i)
    end
end

local function configCases()
    runCase("旧九KEY严格前缀/末尾N11/独立配置/精修原文及最小语境适配", function()
        local f = fixture()
        check(same(f.Config.KEYS, INDEX_KEYS), "Config.KEYS保留旧九KEY顺序为严格前缀，末尾仅追加N11")
        eq(f.Config.NODE_KEY, N02, "NODE_KEY保留N02兼容")
        eq(assert(f.Config.getEvidence("E03-B")).id, "E03-B", "B为合法静态初片，原调查链不授予B")
        eq(f.session.samsaraStory.evidence["E03-B"], nil, "本原链夹具未取得B")
        for _, key in ipairs(KEYS) do
            local cfg = assert(f.Config.get(key))
            eq(cfg.mode, "small", key .. "均为small")
            eq(cfg.reward, nil, key .. "无reward")
            eq(cfg.rewards, nil, key .. "无rewards")
            eq(cfg.scenarioId, nil, key .. "不占旧情景ID")
            eq(type(cfg.evidence.id), "string", key .. "evidence.id")
            eq(type(cfg.evidence.title), "string", key .. "evidence.title")
            eq(type(cfg.evidence.text), "string", key .. "evidence.text")
            local expected = copy(cfg)
            cfg.steps[1].text, cfg.evidence.text = "临时UI覆盖", "临时覆盖"
            check(same(f.Config.get(key), expected), key .. "深副本不污染后续调用")
        end
        for _, key in ipairs({ "N12", "N13", "N14", "12", "unknown", "samsara.next" }) do
            eq(f.Config.get(key), nil, "不注册未知/策划编号 " .. key)
        end
        local cargo = assert(f.Config.get(N12, "player_record"))
        local archive = assert(f.Config.get(N12, "case_archive"))
        local cargoText, archiveText = {}, {}
        for _, step in ipairs(cargo.steps) do cargoText[#cargoText + 1] = step.text end
        for _, step in ipairs(archive.steps) do archiveText[#archiveText + 1] = step.text end
        check(contains(table.concat(cargoText, "\n"), "你带来的货牌"), "player_record准确使用玩家携带语境")
        check(contains(table.concat(archiveText, "\n"), "铁匠保存的货牌副本"), "case_archive不伪造玩家取得史")
        eq(archive.evidence.text, cargo.evidence.text, "两来源不替换原件货单")
        eq(cargo.evidence.id, "E02", "N12为E02")
        check(contains(cargo.evidence.text, "商队药箱十二。") and contains(cargo.evidence.text, "回收：货牌。箱体未回。"), "E02原件首尾无改写")
        eq(cargo.evidence.annotation, "货牌位置与保全库十二号箱底拓片吻合。同物件跨两次交接有完整编号，未发现复制箱体。受害押运者另记人员卷，不并入“物资损失”。", "E02核验批注逐字")
        expectDialogue(cargo, {
            { "铁匠", "不是同款。是同一只箱子。这里打歪过，又补了一次。" },
            { "远征长", "它后来去哪了？" },
            { "圣女", "这份交接底档说，药箱十二入了保全库。" },
            { "黄桃龙", "保全库……是救人用的？" },
            { "铁匠", "货是救人用的。抢货的时候，押车的人可没有被救。" },
        }, "N12")
        expectDialogue(archive, {
            { "铁匠", "不是同款。是同一只箱子。这里打歪过，又补了一次。" },
            { "远征长", "它后来去哪了？" },
            { "圣女", "这份交接底档说，药箱十二入了保全库。" },
            { "黄桃龙", "保全库……是救人用的？" },
            { "铁匠", "货是救人用的。抢货的时候，押车的人可没有被救。" },
        }, "N12案件副本")
        local gray, people = assert(f.Config.get(N13)), assert(f.Config.get(N14))
        eq(gray.evidence.id, "E05", "N13为E05初始")
        eq(people.evidence.id, "E05", "N14仍为同一E05")
        eq(people.evidence.text, gray.evidence.text, "人员卷不覆盖初始抄件")
        eq(gray.evidence.text, "急救物资征用令。\n调取：商队药箱十二。\n送达：城镇登记接驳处。\n目的：保全三名受援人。\n签发：第三十七任远征长〔旧登记页〕。\n手令：“先救人，回来再结。”", "E05初始抄件逐字")
        eq(gray.evidence.continuation, nil, "N13配置不提前包含续令")
        eq(gray.evidence.people, nil, "N13配置不提前包含人员卷")
        eq(people.evidence.continuation, "先期物资不足。允许拦截护送支队，缴械接驳。\n遇阻待签发方答复。\n〔“停止拦截”栏：空白〕", "续令逐字")
        eq(people.evidence.people, "物资卷与人员卷分列。\n旧远征护送支队失踪：有登记名单。\n找回胸牌、外衣标识及两封未送达的家书。\n幸存者证言已保存；遗物不得换算成可交付的救援配额。", "人员卷逐字")
        expectDialogue(gray, {
            { "远征长", "我的印。不是我签的。" },
            { "圣女", "这印是真的，不代表这句话是你写的。还要找到拿它下令的人。" },
            { "叮咚鸡", "页号不对。先留着原件，别急着认人。" },
            { "铁匠", "那我留着押车人的话。有人穿得像你们，不是说现在这三个人动的手。" },
            { "远征长", "找到签发的人，当面问。" },
        }, "N13")
        expectDialogue(people, {
            { "幸存者证言", "第一次拦车，他们只搬药箱。第二次，他们说护送队也在征用名单里。" },
            { "幸存者证言", "我听见一个声音叫他们先停。命令没有撤下。刀也没有。" },
            { "远征长", "不是只有商队。" },
            { "叮咚鸡", "另开一页。人不能记成一箱东西。" },
            { "大狗嚼", "叫……被征用的不只是箱子，还有护送的人？" },
            { "圣女", "这几件遗物有主人。别把所有战利品都算到这案子里，也别把这案子漏掉。" },
        }, "N14独立语境")
        check(not contains(people.evidence.text .. people.evidence.continuation .. people.evidence.people,
            "本人承认一致"), "不泄露N17本人核验结果")
    end)
end

local function captureCases()
    local matrix = {
        { label = "数字true", raw = { [4905] = true, [204] = true }, cargo = true, e02 = true },
        { label = "字符串true", raw = { ["4905"] = true, ["204"] = true }, cargo = true, e02 = true },
        { label = "数字false", raw = { [4905] = false, [204] = false } },
        { label = "字符串false", raw = { ["4905"] = false, ["204"] = false } },
        { label = "truthy字符串true", raw = { [4905] = "true", [204] = "true" } },
        { label = "truthy字符串false", raw = { [4905] = "false", [204] = "false" } },
        { label = "truthy数字1", raw = { [4905] = 1, [204] = 1 } },
        { label = "非法补零key", raw = { ["04905"] = true, ["0204"] = true } },
        { label = "非法后缀key", raw = { ["4905x"] = true, ["204x"] = true } },
        { label = "仅E02", raw = { [204] = true }, e02 = true },
        { label = "仅4905", raw = { [4905] = true }, cargo = true },
        { label = "高max/当前4905", raw = {} },
        { label = "仅ENTER73/其他关", raw = { [73] = true, [4904] = true, [205] = true } },
    }
    for _, item in ipairs(matrix) do
        runCase("raw4905/raw204严格捕获 " .. item.label, function()
            local session = fresh()
            local old = outsideStory(session)
            local f = fixture(session, { clearedStages = item.raw, maxStageId = 9999, currentStageId = 4905 })
            eq(f.Player.getRecord(N02).status, "locked", "N02不借高进度解锁")
            eq(f.Player.getRecord(N12).status, item.cargo and "pending" or "locked", "N12严格资格")
            eq(f.Player.peekReady(), item.cargo and N12 or nil, "无N02/旧73依赖")
            eq(f.Player.getRecord(N13).status, "locked", "N13初始锁定")
            eq(f.Player.getRecord(N14).status, "locked", "N14初始锁定")
            eq(session.samsaraStory.cargoHistoryCaptured, true, "cargo历史即使无资格也捕获")
            eq(session.samsaraStory.historyCaptured, true, "N02历史独立捕获")
            eq(session.samsaraStory.dragonHistoryCaptured, true, "龙域阴性亦由init独立捕获")
            eq(session.samsaraStory.nodes["samsara.dragon_mirror"], nil, "旧调查raw不创造N08资格或亲历")
            eq(session.samsaraStory.evidence["E03-B"], nil, "旧调查raw不授予B")
            eq(f.flushes, 1, "N02/cargo与镜像/龙域历史在一次init合并持久化")
            eq(f.Player.hasPendingRecords(), item.cargo == true or item.e02 == true, "raw204 E02资格增加N03待阅，旧cargo资格不变")
            eq(evidence(f, N12, "E02") ~= nil, item.e02 == true, "只有raw204 true才提前原件可见")
            if item.e02 then
                eq(evidence(f, N12, "E02").source, "player_record", "原件来源player_record")
                eq(evidence(f, N12, "E02").annotation, nil, "未处理N12核验批注不泄露")
            end
            eq(evidence(f, N13, "E05"), nil, "raw4905不直接公开E05")
            check(same(outsideStory(session), old), "不改claimed/granted/tutorial/开场/旧字段")
        end)
    end
    runCase("N02已有historyCaptured仍首次捕获cargo，随后max补true不可重扫", function()
        local session = fresh()
        session.samsaraStory = { schemaVersion = 1, historyCaptured = true, nodes = {}, evidence = {}, keep = { x = 9 } }
        local f = fixture(session, { clearedStages = { [104] = true, [4905] = true, [204] = true } })
        eq(f.Player.getRecord(N02).status, "locked", "已有N02history不重扫104")
        eq(f.Player.getRecord(N12).status, "pending", "新cargo标记首次独立扫描4905")
        eq(evidence(f, N12, "E02").source, "player_record", "新cargo标记首次独立扫描204")
        eq(session.samsaraStory.historyCaptured, true, "不重置N02标记")
        eq(session.samsaraStory.keep.x, 9, "旧story字段保留")
        local negative = fresh()
        negative.samsaraStory = { schemaVersion = 1, historyCaptured = true, nodes = {}, evidence = {} }
        local n = fixture(negative, { maxStageId = 9999 })
        local before = n.flushes
        n.Player.init(n.options, { maxStageId = 9999, clearedStages = { [4905] = true, [204] = true } })
        eq(n.Player.getRecord(N12).status, "locked", "二次init不扫后来补true")
        eq(evidence(n, N12, "E02"), nil, "二次init不扫后来补204")
        eq(n.flushes, before, "二次init无新变化不保存")
        local restarted = fixture(cjson.decode(cjson.encode(negative)), { clearedStages = { [4905] = true, [204] = true } })
        eq(restarted.Player.getRecord(N12).status, "locked", "重载后仍不反推4905")
        eq(evidence(restarted, N12, "E02"), nil, "重载后仍不反推204")
    end)
    runCase("实时204开放E02与独立N03，实时4905只解锁N12，无N02/73完成门槛", function()
        local f = fixture(nil, { maxStageId = 9999 })
        for _, id in ipairs({ 4904, "04905", "4905x", 203, "0204", "204x", 73 }) do
            eq(f.Player.onStageCleared(id), false, "无关/非法live id " .. tostring(id))
        end
        eq(f.Player.onStageCleared("204"), true, "live204开放原件")
        eq(f.Player.peekReady(), nil, "204 N03仍等对应旧44–46，N12不借204解锁")
        eq(f.Player.getRecord(N03).status, "pending", "live204独立产生N03待阅")
        eq(evidence(f, N12, "E02").source, "player_record", "live204来源player_record")
        eq(f.Player.onStageCleared(204), false, "live204重复幂等")
        eq(f.Player.onStageCleared("4905"), true, "live4905解锁N12")
        eq(f.Player.onStageCleared(4905), false, "live4905重复幂等")
        eq(f.Player.peekReady(), N12, "无旧73仍可读N12")
        eq(f.Player.getRecord().status, "locked", "getRecord省参仍指N02")
        local before = outsideStory(f.session)
        complete(f, N12)
        eq(f.Player.peekReady(), N13, "N12完成释放N13")
        check(same(outsideStory(f.session), before), "实时调查不预claim旧73或改教程")
    end)
end

local function chainCases()
    runCase("默认peek顺序与显式N12请求不依赖N02", function()
        local session = fresh(); session.claimedScenarios["17"] = true
        local f = fixture(session, { clearedStages = { [104] = true, [4905] = true } })
        eq(f.Player.peekReady(), N02, "同时待阅自动N02优先")
        local before = copy(f.session)
        eq(f.Player.hasPendingRecords(), true, "有待阅")
        local records = f.Player.getRecords()
        eq(#records, 10, "十记录保留旧九索引，末尾仅追加N11")
        for i, record in ipairs(records) do eq(record.key, INDEX_KEYS[i], "getRecords顺序" .. i) end
        records[1].title = "覆盖"
        check(same(f.session, before), "peek/getRecords不写入或取消待阅")
        eq(f.Player.requestRead(N12), true, "显式已解锁N12可跨过N02")
        local request = assert(f.Player.takeRequest())
        eq(request.key, N12, "显式key不被peek优先级覆盖")
        eq(request.kind, FIRST, "显式待阅为首读")
        local lease = assert(f.Player.begin(request.kind, request.key))
        eq(f.Player.getRecord(N02).status, "pending", "beginN12不完成N02")
        eq(f.Player.peekReady(), nil, "全节点共享单租约")
        eq(f.Player.begin(FIRST, N02), nil, "租约期间不能再播N02")
        eq(f.Player.onResult(result(lease, "skipped")), true, "N12skip释放")
        eq(f.Player.peekReady(), N02, "N02优先级仍保留")
        complete(f, N02)
        eq(f.Player.peekReady(), N13, "N02完成后轮到N13")
        complete(f, N13)
        eq(f.Player.peekReady(), N14, "N13之后N14")
        complete(f, N14)
        eq(f.Player.peekReady(), nil, "所有首次处理后无自动重播")
        eq(f.Player.hasPendingRecords(), false, "所有处理完无待阅")
        eq(f.session.samsaraStory.evidence["E03-B"], nil, "完成原调查链仍不授予B")
    end)
    for _, key in ipairs({ N12, N13, N14 }) do
        for _, reason in ipairs({ "finished", "dismissed", "skipped", "reset", "replaced", "failed" }) do
            runCase(key .. "结果分类 " .. reason, function()
                local f = fixture(nil, { clearedStages = { [4905] = true } })
                if key ~= N12 then complete(f, N12) end
                if key == N14 then complete(f, N13) end
                local lease = assert(f.Player.begin(FIRST, key))
                local before, old = f.flushes, outsideStory(f.session)
                local nextKey = key == N12 and N13 or (key == N13 and N14 or nil)
                eq(f.Player.onResult(result(lease, reason)), true, "当前租约一次接受")
                eq(f.Player.onResult(result(lease, reason)), false, "重复结果不覆盖")
                local success = reason == "finished" or reason == "dismissed" or reason == "skipped"
                ---@type string?
                local expectedReady = key
                if success then expectedReady = nextKey end
                eq(f.Player.getRecord(key).status, success and (reason == "skipped" and "skipped" or "finished") or "pending", "精确处理状态")
                eq(f.flushes, before + (success and 1 or 0), "只有首次成功结果保存")
                eq(f.Player.peekReady(), expectedReady, "成功释放下一段，中断保留本段")
                if nextKey then
                    eq(f.Player.getRecord(nextKey).status, success and "pending" or "locked", "依赖状态")
                    if not success then
                        eq(f.Player.requestRead(nextKey), false, "中断后不得请求后段")
                        eq(f.Player.begin(FIRST, nextKey), nil, "中断后不得begin后段")
                    end
                end
                if key == N12 then
                    eq(evidence(f, N12, "E02").annotation ~= nil, success, "E02批注跟随N12处理")
                    eq(evidence(f, N13, "E05"), nil, "N12处理仍无E05初始")
                elseif key == N13 then
                    eq(evidence(f, N13, "E05") ~= nil, success, "E05初始跟随N13处理")
                    eq(evidence(f, N14, "E05") and evidence(f, N14, "E05").continuation or nil, nil, "N13处理不开放续令")
                else
                    local e05 = assert(evidence(f, N14, "E05"))
                    eq(e05.continuation ~= nil, success, "续令跟随N14处理")
                    eq(e05.people ~= nil, success, "人员卷跟随N14处理")
                end
                local restored = fixture(cjson.decode(cjson.encode(f.session)), {})
                eq(restored.Player.getRecord(key).status, f.Player.getRecord(key).status, "JSON重载保留已处理/未完成")
                eq(restored.Player.peekReady(), expectedReady, "JSON重载从未完成段继续")
                check(same(outsideStory(f.session), old), "所有结果不改旧账本/教程")
            end)
        end
    end
    runCase("E02案件副本只在beginN12建立，后续live204不改首次来源", function()
        local f = fixture(nil, { clearedStages = { [4905] = true } })
        eq(evidence(f, N12, "E02"), nil, "捕获4905不提前造E02案件副本")
        f.Player.getRecords(); f.Player.peekReady(); f.Player.hasPendingRecords()
        eq(evidence(f, N12, "E02"), nil, "所有只读查询不建立副本")
        eq(f.Player.requestRead(N12), true, "请求本身只排队")
        eq(evidence(f, N12, "E02"), nil, "request仍不建副本")
        local request = assert(f.Player.takeRequest())
        eq(evidence(f, N12, "E02"), nil, "take仍不建副本")
        local lease = assert(f.Player.begin(request.kind, request.key))
        local e02 = assert(evidence(f, N12, "E02"))
        eq(e02.source, "case_archive", "首次调查begin建立案件副本")
        eq(e02.annotation, nil, "begin仍不公开核验批注")
        eq(e02.text, f.Config.get(N12, "case_archive").evidence.text, "案件副本与真正原件同一货单")
        eq(f.Player.onResult(result(lease, "finished")), true, "N12完成")
        eq(evidence(f, N12, "E02").annotation, f.Config.get(N12).evidence.annotation, "完成后核验独立附加")
        local originalText = evidence(f, N12, "E02").text
        eq(f.Player.onStageCleared(204), true, "已有E02案件来源仍由真实204独立解锁N03")
        eq(evidence(f, N12, "E02").source, "case_archive", "后来204不倒推首次调查时玩家持有原件")
        eq(evidence(f, N12, "E02").text, originalText, "后来204不替换既有货单正文")
        eq(evidence(f, N12, "E02").annotation, f.Config.get(N12).evidence.annotation, "首次来源保留核验")
        local view = f.Player.getRecord(N12)
        view.evidences[1].annotation = "UI篡改"
        eq(evidence(f, N12, "E02").annotation, f.Config.get(N12).evidence.annotation, "evidences深副本")
    end)
    runCase("跨KEY错误身份/取消/换session拒绝迟到结果", function()
        local f = fixture(nil, { clearedStages = { [4905] = true } })
        local lease = assert(f.Player.begin(FIRST, N12))
        for _, field in ipairs({ "playToken", "contextEpoch", "nodeKey" }) do
            local bad = result(lease, "finished"); bad[field] = field == "nodeKey" and N13 or -10
            eq(f.Player.onResult(bad), false, "错误" .. field .. "拒绝")
        end
        eq(f.Player.onResult(result(lease, "unknown")), false, "未知结果不消费租约")
        eq(f.Player.getRecord(N13).status, "locked", "错误身份不释放N13")
        f.Player.cancel()
        eq(f.Player.onResult(result(lease, "finished")), false, "cancel后迟到结果拒绝")
        local retry = assert(f.Player.begin(FIRST, N12))
        check(retry.contextEpoch > lease.contextEpoch and retry.playToken > lease.playToken, "新租约token/epoch递增")
        f.session = fresh()
        eq(f.Player.onResult(result(retry, "skipped")), false, "静默换档拒绝结果")
        eq(f.session.samsaraStory, nil, "迟到结果不造新档story")
        f.Player.init(f.options, {})
        eq(f.Player.getRecord(N12).status, "locked", "新档无4905资格")
        eq(f.Player.onResult(result(retry, "finished")), false, "新档init后仍拒绝旧结果")
    end)
    runCase("三段回看所有结果不改首次resolution、不保存、不重复释放", function()
        local f = fixture(nil, { clearedStages = { [4905] = true, [204] = true } })
        complete(f, N12, "skipped"); complete(f, N13); complete(f, N14, "skipped")
        local saved, before = copy(f.session), f.flushes
        for _, key in ipairs({ N12, N13, N14 }) do
            for _, reason in ipairs({ "finished", "dismissed", "skipped", "reset", "replaced", "failed" }) do
                eq(f.Player.requestRead(key), true, key .. "回看请求")
                local request = assert(f.Player.takeRequest())
                eq(request.kind, REPLAY, "已处理只回看")
                local lease = assert(f.Player.begin(request.kind, request.key))
                eq(f.Player.onResult(result(lease, reason)), true, "回看" .. reason .. "释放展示")
                check(same(f.session, saved), "回看" .. key .. "/" .. reason .. "账本全不变")
                eq(f.flushes, before, "回看无重复Flush")
                eq(f.Player.peekReady(), nil, "回看不新增自动剧情")
            end
        end
        for _, key in ipairs({ N12, N13, N14 }) do eq(f.Player.begin(FIRST, key), nil, "已处理不得再次首读") end
    end)
end

local function preservationCases()
    runCase("新节点normalize严格布尔与未知字段幂等保全", function()
        local f = fixture()
        local session = fresh()
        session.samsaraStory = { schemaVersion = 1, historyCaptured = true, cargoHistoryCaptured = "false",
            nodes = {}, evidence = {}, unknownStory = { nested = true } }
        for _, key in ipairs({ N12, N13, N14 }) do
            session.samsaraStory.nodes[key] = { eligible = "true", contentVersion = "1", resolution = "reset", unknown = { keep = 8 } }
        end
        session.samsaraStory.nodes.future = { contentVersion = 66, opaque = true }
        session.samsaraStory.evidence.E02 = { unlocked = "true", source = 9, unknown = { keep = 6 } }
        session.samsaraStory.evidence.E05 = { unknown = { keep = 5 } }
        local old = outsideStory(session)
        f.Schema.normalize(session)
        eq(session.samsaraStory.cargoHistoryCaptured, false, "cargo捕获标记不宽松转true")
        eq(session.samsaraStory.historyCaptured, true, "N02标记不重置")
        for _, key in ipairs({ N12, N13, N14 }) do
            eq(session.samsaraStory.nodes[key].eligible, false, "资格严格布尔 " .. key)
            eq(session.samsaraStory.nodes[key].resolution, nil, "reset不成为完成 " .. key)
            eq(session.samsaraStory.nodes[key].unknown.keep, 8, "未知节点字段保留 " .. key)
        end
        eq(session.samsaraStory.evidence.E02.unlocked, false, "E02字符串true不公开")
        eq(session.samsaraStory.evidence.E02.unknown.keep, 6, "未知E02字段保全")
        eq(session.samsaraStory.evidence.E05.unknown.keep, 5, "未知E05字段保全")
        local normalized = copy(session)
        for _ = 1, 3 do f.Schema.normalize(session) end
        check(same(session, normalized), "新字段normalize幂等")
        check(same(outsideStory(session), old), "normalize不改旧session")
    end)
    for _, version in ipairs({ 2, "99" }) do
        runCase("未来schema全部新API只读保全 " .. tostring(version), function()
            local session = fresh()
            session.samsaraStory = { schemaVersion = version, historyCaptured = "future", cargoHistoryCaptured = "future",
                nodes = "future", evidence = false, unknown = { keep = 3 } }
            local before = copy(session)
            local f = fixture(session, { clearedStages = { [4905] = true, [204] = true } })
            eq(f.supported, false, "未来schema不兼容")
            eq(f.Player.peekReady(), nil, "未来schema无待播")
            eq(f.Player.hasPendingRecords(), false, "未来schema无可处理待阅")
            eq(#f.Player.getRecords(), 10, "不兼容仍安全返回十记录")
            for _, key in ipairs(KEYS) do
                eq(f.Player.getRecord(key).status, "unsupported", "未来schema记录不兼容 " .. key)
                eq(f.Player.requestRead(key), false, "未来schema不排请求 " .. key)
                eq(f.Player.begin(FIRST, key), nil, "未来schema不首读 " .. key)
                eq(f.Player.begin(REPLAY, key), nil, "未来schema不回看 " .. key)
            end
            eq(f.Player.onStageCleared(204), false, "未来schema不写E02")
            eq(f.Player.onStageCleared(4905), false, "未来schema不写N12")
            f.Player.cancel(); f.Player.update(100)
            eq(f.flushes, 0, "未来schema不保存")
            check(same(session, before), "全部API保留未来结构原样")
        end)
    end
    for _, key in ipairs({ N12, N13, N14 }) do
        runCase("未来content不规范化/播放/覆盖 " .. key, function()
            local session = fresh()
            session.samsaraStory = { schemaVersion = 1, historyCaptured = true, cargoHistoryCaptured = true,
                nodes = {}, evidence = {}, unknownStory = 44 }
            if key ~= N12 then session.samsaraStory.nodes[N12] = { eligible = true, contentVersion = 1, resolution = "finished" } end
            if key == N14 then session.samsaraStory.nodes[N13] = { eligible = true, contentVersion = 1, resolution = "finished" } end
            session.samsaraStory.nodes[key] = { eligible = "future", contentVersion = 99, resolution = "future_resolution", unknown = { keep = 55 } }
            local nodeBefore = copy(session.samsaraStory.nodes[key])
            local f = fixture(session, { clearedStages = { [4905] = true, [204] = true } })
            eq(f.Player.getRecord(key).status, "unsupported", "未来content档案不兼容")
            eq(f.Player.requestRead(key), false, "未来content不可请求")
            eq(f.Player.begin(FIRST, key), nil, "未来content不可首读")
            eq(f.Player.begin(REPLAY, key), nil, "未来content不可回看")
            f.Player.onStageCleared(4905)
            f.Schema.normalize(session)
            check(same(session.samsaraStory.nodes[key], nodeBefore), "未来节点未知字段/结果原样保全")
        end)
    end
    runCase("cargo历史捕获失败同表init不重扫，结果失败与节流恢复", function()
        local f = fixture(nil, { maxStageId = 9999 })
        f.save = false
        eq(f.Player.onStageCleared(4905), true, "真实首通资格内存保留")
        check(f.Player.isSavePending(), "资格保存失败待存")
        local old = outsideStory(f.session)
        local before = f.flushes
        f.Player.init(f.options, { clearedStages = { [204] = true, [104] = true } })
        eq(evidence(f, N12, "E02"), nil, "失败二次init不扫描后来204")
        eq(f.Player.getRecord(N02).status, "locked", "失败二次init不扫描后来104")
        eq(f.flushes, before, "无变化init不重复保存")
        complete(f, N12, "skipped")
        eq(f.Player.getRecord(N12).status, "skipped", "保存失败首次结果仍保内存")
        eq(f.Player.peekReady(), N13, "保存失败不永久卡住无奖链")
        check(f.Player.isSavePending(), "失败结果保留待存")
        local attempts = f.flushes
        f.Player.cancel(); f.Player.update(1.99)
        eq(f.flushes, attempts, "两秒前不重试")
        f.Player.update(0.02)
        eq(f.flushes, attempts + 1, "节流到期重试一次")
        f.throw = true; f.Player.update(100)
        eq(f.flushes, attempts + 2, "大dt和异常不轰炸保存")
        check(f.Player.isSavePending(), "异常仍待存")
        f.throw, f.save = false, true
        f.Player.update(2)
        eq(f.Player.isSavePending(), false, "成功才清待存")
        eq(f.disk.samsaraStory.nodes[N12].resolution, "skipped", "恢复保存首次skip")
        eq(f.disk.samsaraStory.cargoHistoryCaptured, true, "独立历史标记落盘")
        eq(evidence(f, N12, "E02").source, "case_archive", "没有伪造204玩家原件")
        check(same(outsideStory(f.session), old), "保存失败与恢复只改新story")
    end)
end

function Start()
    local ok, err = pcall(function()
        configCases()
        captureCases()
        chainCases()
        preservationCases()
    end)
    if not ok then check(false, "顶层异常: " .. tostring(err)) end
    print(PREFIX .. "RESULT assertions=" .. assertions .. " failures=" .. failures .. " cases=" .. cases .. " passed=" .. passed)
    if failures == 0 then print(PREFIX .. "ALL PASS") end
    engine:Exit()
end
