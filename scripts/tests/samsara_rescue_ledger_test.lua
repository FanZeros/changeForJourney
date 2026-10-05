-- samsara_rescue_ledger_test.lua — N10前置真实救援回执隔离矩阵，不添加正文/A/B或可信阴性。
-- 基于samsara_slice_player_test：cache:GetFile读取真实源码，私有env递归load真实StageConfig子模块。
-- 只在内存模拟session通知与Save委托的Flush；不访问玩家档，不改生产/docs/git/metadata。
-- 由主会话在统一构建完成后执行Runtime；本测试作者不build、不运行中间不齐的工程。
local PREFIX = "[samsara_rescue_ledger] "
local assertions, failures, cases, passed = 0, 0, 0, 0
local SOURCE = "live_nonterminal_wipe_recovery"
local ORIGINAL_KEYS = {
    "samsara.log_leaf", "samsara.cargo_match", "samsara.gray_order", "samsara.people_record",
    "samsara.returned_manifest", "samsara.dog_mirror", "samsara.bell_mirror", "samsara.opening_roster",
    "samsara.dragon_mirror", "samsara.nightmare_afterimage",
}
---@type table
local realStage, realConfig, loadCounts = {}, {}, {}

local function check(ok, label)
    assertions = assertions + 1
    if not ok then failures = failures + 1; print(PREFIX .. "FAIL assertion " .. label) end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function runCase(label, fn)
    cases = cases + 1
    local before = failures
    local ok, err = pcall(fn)
    if not ok then check(false, label .. " 异常=" .. tostring(err)) end
    if failures == before then
        passed = passed + 1; print(PREFIX .. "PASS case " .. label)
    else print(PREFIX .. "FAIL case " .. label) end
end
---@param value any
---@return any
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end
---@param a any
---@param b any
---@return boolean
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b or (type(a) == "number" and a ~= a and b ~= b) end
    for key, item in pairs(a) do if not same(item, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

-- 独立整档比较只排除新域；旧story本身、10节点、物证、经济、教程都仍参与比较。
---@param session any
---@return any
local function outsideLedger(session)
    local out = copy(session)
    if type(out) == "table" and type(out.samsaraStory) == "table" then out.samsaraStory.rescueLedger = nil end
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
    loadCounts[path] = (loadCounts[path] or 0) + 1
    local env = setmetatable({ require = function(name)
        if overrides[name] ~= nil then return overrides[name] end
        if name:match("^config%.StageConfig_") then
            return isolated(name:gsub("%.", "/") .. ".lua", {})
        end
        error("隔离测试拒绝未声明依赖/真实存档/经济路径: " .. tostring(name))
    end }, { __index = _G })
    env._G = env
    return assert(load(table.concat(lines, "\n"), "@" .. path, "t", env))()
end

---@return table
local function fresh()
    local story = { schemaVersion = 1, historyCaptured = true, cargoHistoryCaptured = true,
        dragonHistoryCaptured = true, dragonHistoryVersion = 1, nodes = {}, evidence = {},
        unknownStory = { keep = "旧story原值", nested = { true, false } } }
    for index, key in ipairs(ORIGINAL_KEYS) do
        story.nodes[key] = { eligible = index % 2 == 1, contentVersion = 1,
            resolution = index % 2 == 0 and "skipped" or "finished", unknown = { keep = index } }
    end
    for _, id in ipairs({ "E01", "E02", "E05", "E03-A", "E03-B", "E03-C" }) do
        story.evidence[id] = { unlocked = true, source = "原物证来源", unknown = { keep = id } }
    end
    return { samsaraStory = story, initialHeroId = 1, introCompleted = true,
        claimedScenarios = { [17] = true, ["82"] = true, [73] = false },
        scenarioRewardsGranted = { ["17"] = true, [82] = true },
        tutorialProgress = { completed = { ["3"] = true }, activeGroup = "recruit", unknown = { keep = 9 } },
        currency = { gold = 123, gems = 456, essence = 7 }, inventory = { items = { { id = 9, amount = 3 } } },
        rewards = { queued = { "旧奖" }, granted = true }, heroes = { roster = { { id = 1, level = 7 } } },
        battle = { currentStageId = 4905, maxStageId = 9999, clearedStages = { [104] = true } },
        introPlayback = { done = true }, firstLoginTime = 123, offlineBonusCount = 2,
        rescueLedger = { keep = "顶层同名旧字段也不排除" }, unknownSession = { keep = { 1, 2, 3 } } }
end
---@return table
local function receipt()
    return { schemaVersion = 1, source = SOURCE, scope = "single_scene", failedStageId = 104,
        recoveredStageId = 103, heroIds = { 1, 2, 3 }, recoveryComplete = true }
end

-- 所有夹具重载真实Ledger实例；StageConfig是私有load所得真实只读配置，不是getStage替身。
---@param session any
---@return table
local function fixture(session)
    local f = { session = session, sets = 0, flushes = 0, disk = copy(session),
        baseline = outsideLedger(session), setMode = "void", flushMode = "true", notifySame = false,
        throwGet = false, setHook = false, flushHook = false }
    f.ledger = isolated("systems/SamsaraRescueLedger.lua", { ["config.StageConfig"] = realStage })
    f.options = {
        getSession = function()
            if f.throwGet then error("模拟getter异常") end
            return f.session
        end,
        setSession = function(value)
            f.sets = f.sets + 1
            eq(value, f.session, "通知必须交回共享session同表，不替换旧档")
            if f.setMode == "throw" then error("模拟session通知异常") end
            if type(f.setHook) == "function" then f.setHook(value) end
            if f.notifySame then f.ledger.onSessionUpdated(value) end
            if f.setMode == "false" then return false end
            if f.setMode == "true" then return true end
            -- ClientDispatcher.set宿主通知无返回值：nil兼容成功，只有显式false/throw失败。
        end,
        flush = function()
            f.flushes = f.flushes + 1
            if type(f.flushHook) == "function" then f.flushHook() end
            if f.flushMode == "throw" then error("模拟Save编码/写盘异常") end
            if f.flushMode == "true" then f.disk = copy(f.session); return true end
            if f.flushMode == "false" then return false end
            if f.flushMode == "truthy" then return "true" end
        end,
    }
    f.supported = f.ledger.init(f.options)
    return f
end
local function preserved(f, label)
    check(same(outsideLedger(f.session), f.baseline), label .. " outside rescueLedger整档不变（10节点/物证/claimed/rewards/经济/教程）")
end
local function idle(f, label)
    eq(f.ledger.getReceipt(), nil, label .. " 无有效回执")
    eq(f.ledger.getExperience(), "unknown", label .. " 永远unknown，不反推阴性")
    eq(f.sets, 0, label .. " 不通知")
    eq(f.flushes, 0, label .. " 不Flush")
end
local function accepted(f, value, label)
    local ticket = assert(f.ledger.capture(), label .. " 缺失败端票据")
    eq(f.ledger.commit(ticket, value), true, label .. " 真票与恢复完成回执接受")
    check(same(f.ledger.getReceipt(), value), label .. " 回执精确记录")
    eq(f.ledger.getExperience(), "rescued", label .. " 有真实回执才rescued")
    return ticket
end

local function initializationCases()
    runCase("未init所有API安全、无副作用", function()
        local L = isolated("systems/SamsaraRescueLedger.lua", { ["config.StageConfig"] = realStage })
        eq(L.capture(), nil, "未init无票")
        eq(L.commit({}, receipt()), false, "未init不写回执")
        eq(L.getReceipt(), nil, "未init无回执")
        eq(L.getExperience(), "unknown", "未initunknown")
        L.update(100); L.cancel(); L.onSessionUpdated(fresh())
        eq(L.capture(), nil, "没有options的通知不能隐式init")
        eq(L.isSavePending(), false, "未init无待存")
    end)
    local sessions = { { label = "nil空档" }, { label = "空表档", session = {} },
        { label = "布尔坏档", session = false }, { label = "字符串坏档", session = "bad" },
        { label = "数字坏档", session = 3 } }
    local old = fresh(); old.samsaraStory = nil
    sessions[#sessions + 1] = { label = "旧档无story但高max/claimed", session = old }
    for _, bad in ipairs({ false, "坏story", 7 }) do
        local s = fresh(); s.samsaraStory = bad
        sessions[#sessions + 1] = { label = "非表story " .. tostring(bad), session = s }
    end
    runCase("旧档/空档/无story/坏session全矩阵无副作用", function()
        for _, item in ipairs(sessions) do
            local f, before = fixture(copy(item.session)), copy(item.session)
            eq(f.supported, false, "无story不支持")
            eq(f.ledger.capture(), nil, "无story无票")
            eq(f.ledger.commit({}, receipt()), false, "无story拒绝任意票")
            f.ledger.update(100); f.ledger.cancel()
            idle(f, item.label)
            check(same(f.session, before), "完整原档不变，不创建samsaraStory或rescueLedger")
        end
    end)
    runCase("支持的空story只读及capture不写档", function()
        local s = fresh(); s.samsaraStory = { schemaVersion = 1, nodes = {}, evidence = {} }
        local f, before = fixture(s), copy(s)
        eq(f.supported, true, "合法空story可附着")
        check(type(f.ledger.capture()) == "table", "capture仅进程票")
        f.ledger.update(100); f.ledger.cancel(); idle(f, "合法空story")
        check(same(s, before), "capture不生成标记/回执/coverage，也不保存")
    end)
    runCase("init配置缺失明确拒绝，不能退到真实玩家存档", function()
        for _, opts in ipairs({ {}, { getSession = function() return fresh() end },
            { getSession = function() return fresh() end, setSession = function() end } }) do
            local L = isolated("systems/SamsaraRescueLedger.lua", { ["config.StageConfig"] = realStage })
            local ok = pcall(L.init, opts)
            eq(ok, false, "缺必要回调init失败")
            eq(L.getExperience(), "unknown", "失败配置不读取真实档")
        end
    end)
end

local function schemaCases()
    local versions = { { label = "缺版本" }, { label = "字符串1", value = "1" },
        { label = "字符串future", value = "99" }, { label = "future2", value = 2 },
        { label = "零", value = 0 }, { label = "负数", value = -1 }, { label = "布尔", value = true } }
    runCase("story未知/future schema与rescueLedger保全矩阵", function()
        for _, item in ipairs(versions) do
            local s = fresh(); s.samsaraStory.schemaVersion = item.value
            s.samsaraStory.rescueLedger = { schemaVersion = 1, scope = "single_scene", firstReceipt = receipt(), unknown = { keep = 9 } }
            local storyRef, domainRef, before = s.samsaraStory, s.samsaraStory.rescueLedger, copy(s)
            local f = fixture(s)
            eq(f.supported, false, "未知/future story不支持")
            eq(f.ledger.capture(), nil, "未知story拒绝票")
            eq(f.ledger.commit({}, receipt()), false, "未知story拒绝写入")
            f.ledger.onSessionUpdated(s); f.ledger.update(100); f.ledger.cancel(); idle(f, item.label)
            eq(s.samsaraStory, storyRef, "不替换story引用")
            eq(s.samsaraStory.rescueLedger, domainRef, "不替换rescueLedger引用")
            check(same(s, before), "story以及既有回执完整原样保全")
        end
    end)
    runCase("story缺/坏nodes/evidence必要子表矩阵", function()
        for _, field in ipairs({ "nodes", "evidence" }) do
            for _, bad in ipairs({ false, "bad", 7 }) do
                local s = fresh(); s.samsaraStory[field] = bad
                local f, before = fixture(s), copy(s)
                eq(f.supported, false, "坏" .. field .. "拒绝")
                eq(f.ledger.capture(), nil, "不修复坏子表")
                idle(f, field); check(same(s, before), "原样保全")
            end
        end
    end)
    local domains = { false, "future-domain", 9, {}, { schemaVersion = 2, scope = "single_scene" },
        { schemaVersion = "1", scope = "single_scene" }, { schemaVersion = 1 },
        { schemaVersion = 1, scope = "tri" }, { schemaVersion = 1, scope = "tri_scene" } }
    runCase("既存未知rescueLedger版本/结构/tri范围保全矩阵", function()
        for index, domain in ipairs(domains) do
            local s = fresh(); s.samsaraStory.rescueLedger = copy(domain)
            local ref, before = s.samsaraStory.rescueLedger, copy(s)
            local f = fixture(s)
            eq(f.supported, false, "未知域不当作空账本" .. index)
            eq(f.ledger.capture(), nil, "未知域无票")
            eq(f.ledger.commit({}, receipt()), false, "未知域拒绝写入")
            f.ledger.update(100); f.ledger.cancel(); idle(f, "未知域")
            eq(s.samsaraStory.rescueLedger, ref, "既存域引用不变")
            check(same(s, before), "既存未知字段/版本/范围原样保全")
        end
    end)
    runCase("无回执不信coverage=complete/negative矩阵", function()
        for _, coverage in ipairs({ "unknown", "complete", "negative", true, "true" }) do
            local s = fresh(); s.samsaraStory.rescueLedger = { schemaVersion = 1, scope = "single_scene",
                coverage = coverage, negative = true, experience = "not_rescued", rescued = false, unknown = { keep = 4 } }
            local before, f = copy(s), fixture(s)
            eq(f.supported, true, "本版本域可附着，但非回执字段不作证据")
            idle(f, "coverage=" .. tostring(coverage))
            f.ledger.capture(); f.ledger.cancel(); f.ledger.update(100)
            check(same(s, before), "读取不纠正/擦除旧coverage或伪阴性字段")
        end
    end)
end

local function validReceiptCases()
    runCase("单场合法回执准确落盘，输入/读副本不可污染", function()
        local s, value = fresh(), receipt()
        local storyRef, nodesRef, evidenceRef = s.samsaraStory, s.samsaraStory.nodes, s.samsaraStory.evidence
        local f = fixture(s)
        local ticket = assert(f.ledger.capture())
        idle(f, "只捕获失败瞬间")
        eq(s.samsaraStory.rescueLedger, nil, "尚未恢复完成不建立域")
        eq(f.ledger.commit(ticket, value), true, "同一票恢复完成接受")
        local expected = copy(value)
        check(same(s.samsaraStory.rescueLedger, { schemaVersion = 1, scope = "single_scene",
            coverage = "unknown", firstReceipt = expected }), "存档域仅真实回执与unknown覆盖")
        eq(f.sets, 1, "立即通知一次，nil无返回兼容成功")
        eq(f.flushes, 1, "立即Flush一次")
        eq(f.ledger.isSavePending(), false, "严格true落盘清待存")
        check(same(f.disk, s), "内存Flush存的是独立完整副本")
        eq(s.samsaraStory, storyRef, "story同一引用")
        eq(s.samsaraStory.nodes, nodesRef, "原10节点同一引用")
        eq(s.samsaraStory.evidence, evidenceRef, "原物证同一引用")
        value.heroIds[1], value.failedStageId, value.source = 777, 105, "伪来源"
        check(same(f.ledger.getReceipt(), expected), "commit拷贝输入而非保留调用方表")
        local readA, readB = assert(f.ledger.getReceipt()), assert(f.ledger.getReceipt())
        check(readA ~= readB and readA.heroIds ~= readB.heroIds, "每次getReceipt独立深副本")
        readA.heroIds[2], readA.recoveredStageId, readA.recoveryComplete = 888, 105, false
        check(same(f.ledger.getReceipt(), expected), "读副本篡改不影响账本")
        local restored = fixture(copy(f.disk))
        eq(restored.ledger.getExperience(), "rescued", "真实模块重载读取已保存有效回执")
        check(same(restored.ledger.getReceipt(), expected), "重载精确首份，不需要本进程旧票")
        eq(restored.flushes, 0, "读档不重复保存或重新造经历")
        f.disk.samsaraStory.rescueLedger.firstReceipt.heroIds[1] = 999
        check(same(f.ledger.getReceipt(), expected), "Flush副本也不可污染内存")
        eq(f.ledger.getExperience(), "rescued", "有效首份回执才rescued")
        f.ledger.update(100); eq(f.flushes, 1, "成功之后无重试")
        preserved(f, "合法回执及副本篡改")
    end)
    runCase("英雄数合法范围1..4/保留顺序矩阵", function()
        for size = 1, 4 do
            local f, value = fixture(fresh()), receipt()
            value.heroIds = {}; for index = 1, size do value.heroIds[index] = index * 11 end
            -- 英雄ID不限制为1..4：限制的是数量；所有ID必须为不重复的正整数。
            accepted(f, value, "英雄数" .. size); preserved(f, "英雄数" .. size)
        end
    end)
    runCase("所有真实普通关与14座终焉明确来自StageConfig", function()
        check(same(realConfig.KEYS, ORIGINAL_KEYS), "真实配置严格保留原10节点，不添加N10")
        eq(#realStage.STAGES, 1739, "真实15难度普通关+14座终焉")
        local terminals = 0
        for _, entry in ipairs(realStage.STAGES) do
            if realStage.isTerminalTemple(entry.id) then
                terminals = terminals + 1
                for _, field in ipairs({ "failedStageId", "recoveredStageId" }) do
                    local f, value = fixture(fresh()), receipt(); value[field] = entry.id
                    eq(f.ledger.commit(assert(f.ledger.capture()), value), false, "真实终焉" .. entry.id .. "拒绝" .. field)
                    idle(f, "终焉"); preserved(f, "终焉")
                end
            end
        end
        eq(terminals, 14, "不硬猜仅999，覆盖真实全部终焉")
        for _, id in ipairs({ 101, 2401, 4701, 7001, 9301, 11601, 13901, 16201,
            18501, 20801, 23101, 25401, 27701, 30001, 32301, 34505 }) do
            local f, value = fixture(fresh()), receipt()
            check(realStage.getStage(id) ~= nil and not realStage.isTerminalTemple(id), "真实非终焉关存在" .. id)
            value.failedStageId, value.recoveredStageId = id, id
            accepted(f, value, "真实难度关" .. id); preserved(f, "真实难度关")
        end
    end)
end

local function invalidReceiptCases()
    local badValues = { { label = "缺失" }, { label = "false", value = false },
        { label = "字符串", value = "true" }, { label = "零", value = 0 },
        { label = "负数", value = -1 }, { label = "小数", value = 1.5 },
        { label = "NaN", value = 0 / 0 }, { label = "无穷", value = math.huge },
        { label = "负无穷", value = -math.huge }, { label = "表", value = {} } }
    local mutations = { { label = "非表nil", whole = true }, { label = "非表字符串", whole = true, value = "bad" },
        { label = "非表false", whole = true, value = false }, { label = "非表数字", whole = true, value = 1 } }
    for _, field in ipairs({ "schemaVersion", "failedStageId", "recoveredStageId", "heroIds", "recoveryComplete" }) do
        for _, bad in ipairs(badValues) do
            mutations[#mutations + 1] = { label = field .. "/" .. bad.label, field = field, value = bad.value }
        end
    end
    for _, field in ipairs({ "failedStageId", "recoveredStageId" }) do
        for _, value in ipairs({ "104", "0104", true, 106, 100, 99999999 }) do
            mutations[#mutations + 1] = { label = field .. "/伪关或类型/" .. tostring(value), field = field, value = value }
        end
    end
    for _, value in ipairs({ 101, 102, 105, 201, 2401, 34505 }) do
        mutations[#mutations + 1] = { label = "真实关但不是同关/前关/" .. value, field = "recoveredStageId", value = value }
    end
    for _, value in ipairs({ 2, "1" }) do
        mutations[#mutations + 1] = { label = "回执schema/" .. tostring(value), field = "schemaVersion", value = value }
    end
    for _, value in ipairs({ 1, "true", "false" }) do
        mutations[#mutations + 1] = { label = "恢复完成必须布尔true/" .. tostring(value), field = "recoveryComplete", value = value }
    end
    for _, value in ipairs({ "timeout", "live_timeout_recovery", "live_wipe", "legacy", "debug", "tri_wipe_recovery", 1, true }) do
        mutations[#mutations + 1] = { label = "timeout/伪来源/" .. tostring(value), field = "source", value = value }
    end
    mutations[#mutations + 1] = { label = "来源缺失", field = "source" }
    for _, value in ipairs({ "tri", "tri_scene", "three_rows", "all", "complete", true, 1 }) do
        mutations[#mutations + 1] = { label = "tri/未知scope/" .. tostring(value), field = "scope", value = value }
    end
    mutations[#mutations + 1] = { label = "scope缺失", field = "scope" }
    local heroes = { { label = "空数组", value = {} }, { label = "五英雄", value = { 1, 2, 3, 4, 5 } },
        { label = "重复", value = { 1, 2, 1 } }, { label = "中间洞", value = { [1] = 1, [3] = 3 } },
        { label = "起始洞", value = { [2] = 2 } }, { label = "零索引", value = { [0] = 3, [1] = 1 } },
        { label = "负索引", value = { [-1] = 3, [1] = 1 } }, { label = "小数索引", value = { [1] = 1, [1.5] = 2 } },
        { label = "超范围索引", value = { [1] = 1, [5] = 2 } }, { label = "字符串索引", value = { ["1"] = 1 } },
        { label = "多余hash键", value = { 1, 2, n = 2 } }, { label = "布尔键", value = { [true] = 2, [1] = 1 } } }
    for _, bad in ipairs(badValues) do
        local ids = { 1, 2, 3 }; ids[2] = bad.value
        heroes[#heroes + 1] = { label = "英雄ID严格正整数/" .. bad.label, value = ids }
    end
    heroes[#heroes + 1] = { label = "字符串数字英雄", value = { 1, "2", 3 } }
    heroes[#heroes + 1] = { label = "布尔英雄", value = { true } }
    for _, item in ipairs(heroes) do
        mutations[#mutations + 1] = { label = "英雄dense/" .. item.label, field = "heroIds", value = item.value }
    end
    runCase("严格回执类型/整数/真实关路线/dense/布尔/来源/scope拒绝矩阵", function()
        for _, item in ipairs(mutations) do
            local f, value = fixture(fresh()), receipt()
            if item.whole then value = item.value else value[item.field] = copy(item.value) end
            local before = copy(f.session)
            local ticket = assert(f.ledger.capture())
            eq(f.ledger.commit(ticket, value), false, item.label .. " 不合法拒绝")
            eq(f.ledger.commit(ticket, receipt()), false, item.label .. " 失败commit消费该票，不可修字段复用")
            idle(f, item.label); check(same(f.session, before), item.label .. " 失败连rescueLedger也不创建")
            accepted(f, receipt(), "后续重新真实捕获"); preserved(f, "非法回执后真实恢复")
        end
    end)
    runCase("读档不信非法/未来首份，NaN等未知内容原样冻结矩阵", function()
        for _, item in ipairs(mutations) do
            local s, value = fresh(), receipt()
            if item.whole then value = item.value else value[item.field] = copy(item.value) end
            -- nil表示无首份；非nil坏内容必须保全，不能当新空档覆盖掉。
            if value ~= nil then
                s.samsaraStory.rescueLedger = { schemaVersion = 1, scope = "single_scene", coverage = "complete",
                    firstReceipt = value, unknown = { keep = 77 } }
                local f, before = fixture(s), copy(s)
                idle(f, item.label)
                eq(f.ledger.commit(assert(f.ledger.capture()), receipt()), false, item.label .. " 坏/未来首份不得覆盖")
                check(same(s, before), item.label .. " 坏首份及未知字段原样保全")
                preserved(f, "读坏首份")
            end
        end
    end)
    runCase("未恢复完成绝不登记，必须新票真实恢复才录入", function()
        local f, value = fixture(fresh()), receipt(); value.recoveryComplete = false
        eq(f.ledger.commit(assert(f.ledger.capture()), value), false, "失败计时/寻怪前不记成功")
        idle(f, "恢复未完成")
        value.recoveryComplete = true; accepted(f, value, "后续真实恢复完成"); preserved(f, "完成门禁")
    end)
end

local function ticketCases()
    runCase("ticket复制/未知/重复拒绝；真票不因冒名票被消费", function()
        local f = fixture(fresh()); local ticket = assert(f.ledger.capture())
        for _, fake in ipairs({ {}, copy(ticket), { ticket = ticket }, { source = SOURCE }, false, "ticket", 1 }) do
            eq(f.ledger.commit(fake, receipt()), false, "仅捕获的同一张进程票可用")
        end
        idle(f, "假票")
        eq(f.ledger.commit(ticket, receipt()), true, "假票不消费真票")
        local before = copy(f.session)
        eq(f.ledger.commit(ticket, receipt()), false, "重复真票拒绝")
        check(same(f.session, before), "重复结果不改首份")
        eq(f.flushes, 1, "仅首份Flush一次"); preserved(f, "ticket身份")
    end)
    runCase("多票允许并存但首份提交冻结所有后来经历", function()
        local f = fixture(fresh()); local a, b = assert(f.ledger.capture()), assert(f.ledger.capture())
        check(a ~= b, "两次capture得到不同身份")
        local first = receipt(); first.heroIds = { 3, 1 }
        eq(f.ledger.commit(b, first), true, "首份按实际commit先后，不是capture先后")
        local other = receipt(); other.failedStageId, other.recoveredStageId, other.heroIds = 105, 104, { 2 }
        eq(f.ledger.commit(a, other), false, "此前其他票不能覆盖首份")
        eq(f.ledger.commit(assert(f.ledger.capture()), other), false, "后来新票也不能覆盖首份")
        check(same(f.ledger.getReceipt(), first), "首份英雄/关卡/顺序永久冻结")
        eq(f.flushes, 1, "冻结之后不重复写盘"); preserved(f, "多票冻结")
    end)
    runCase("域已存在时保留所有未知字段，仅附加首份", function()
        local s = fresh(); s.samsaraStory.rescueLedger = { schemaVersion = 1, scope = "single_scene",
            coverage = "unknown", unknown = { keep = 9 }, oldDomainField = false }
        local ref, before = s.samsaraStory.rescueLedger, copy(s.samsaraStory.rescueLedger)
        local f = fixture(s); accepted(f, receipt(), "已存空域")
        eq(s.samsaraStory.rescueLedger, ref, "已有域同一引用")
        local after = copy(ref); after.firstReceipt = nil
        check(same(after, before), "不迁移或擦除coverage/未知旧域字段"); preserved(f, "已存空域")
    end)
    runCase("cancel/init重新捕获使旧票失效但不写档", function()
        local f = fixture(fresh()); local a, b = assert(f.ledger.capture()), assert(f.ledger.capture())
        f.ledger.cancel()
        eq(f.ledger.commit(a, receipt()), false, "cancel取消票a")
        eq(f.ledger.commit(b, receipt()), false, "cancel取消全部票")
        local c = assert(f.ledger.capture()); f.ledger.init(f.options)
        eq(f.ledger.commit(c, receipt()), false, "同表init也不能复用旧票")
        idle(f, "取消/重init")
        accepted(f, receipt(), "init后重新捕获"); preserved(f, "cancel/init")
    end)
    runCase("capture后原地future schema/domain/story换引用均拒绝旧票", function()
        for _, field in ipairs({ "schemaVersion", "domain", "story" }) do
            local f = fixture(fresh()); local ticket = assert(f.ledger.capture())
            if field == "schemaVersion" then f.session.samsaraStory.schemaVersion = 2
            elseif field == "domain" then f.session.samsaraStory.rescueLedger = { schemaVersion = 1, scope = "single_scene" }
            else f.session.samsaraStory = copy(f.session.samsaraStory) end
            local before = copy(f.session)
            eq(f.ledger.commit(ticket, receipt()), false, "捕获绑定session/story/domain引用，不借新版空表")
            eq(f.ledger.getReceipt(), nil, "无回执")
            eq(f.ledger.getExperience(), "unknown", "引用升级不反推经历")
            check(same(f.session, before), "拒绝不改升级后原始表")
            eq(f.sets, 0, "拒绝不通知"); eq(f.flushes, 0, "拒绝不Flush")
        end
    end)
end

local function sessionCases()
    runCase("换档/静默getter换表/显式重新附着矩阵", function()
        for _, mode in ipairs({ "silent", "notification", "init", "story" }) do
            local old = fresh(); local f = fixture(old); local stale = assert(f.ledger.capture())
            local next = mode == "story" and old or fresh()
            if mode == "story" then next.samsaraStory = copy(next.samsaraStory) end
            f.session = next
            local before, oldBefore = copy(next), copy(old)
            if mode == "notification" then f.ledger.onSessionUpdated(next)
            elseif mode == "init" then f.ledger.init(f.options) end
            eq(f.ledger.commit(stale, receipt()), false, mode .. " 换表后迟到旧票永远拒绝")
            check(same(next, before) and same(old, oldBefore), "迟到结果不写新档或旧档")
            if mode == "silent" or mode == "story" then
                eq(f.ledger.capture(), nil, "静默换session/story不能自动借新表capture")
                f.ledger.onSessionUpdated(next)
            end
            local value = receipt(); value.heroIds = { 4 }
            accepted(f, value, "新表明确附着后真实重新捕获")
            check(same(outsideLedger(next), outsideLedger(before)), "新表除rescueLedger外完全不变")
            if next ~= old then check(same(old, oldBefore), "新档提交不回写旧档") end
        end
    end)
    runCase("同表正常session通知保留活跃票和待存，不误判换档", function()
        local f = fixture(fresh()); local ticket = assert(f.ledger.capture())
        f.ledger.onSessionUpdated(f.session)
        f.notifySame, f.flushMode = true, "false"
        eq(f.ledger.commit(ticket, receipt()), true, "同表通知后的票仍有效")
        eq(f.ledger.isSavePending(), true, "Flush失败待存")
        f.ledger.onSessionUpdated(f.session)
        eq(f.ledger.isSavePending(), true, "同表通知不清待存")
        f.flushMode = "true"; f.ledger.update(2)
        eq(f.ledger.isSavePending(), false, "同表回灌通知不阻碍真实保存")
        check(same(f.disk, f.session), "同表恢复后落盘准确"); preserved(f, "同表通知")
    end)
    runCase("getter异常使票失效；恢复getter后必须重新真实捕获", function()
        local f = fixture(fresh()); local ticket = assert(f.ledger.capture())
        f.throwGet = true
        eq(f.ledger.capture(), nil, "getter异常不抛出到调用方")
        eq(f.ledger.getExperience(), "unknown", "getter异常未知")
        f.throwGet = false
        eq(f.ledger.commit(ticket, receipt()), false, "异常期间清票，旧票不复活")
        idle(f, "getter异常")
        accepted(f, receipt(), "getter恢复后新票"); preserved(f, "getter恢复")
    end)
    runCase("切回原档不复活已经观察到换档的旧票", function()
        local old = fresh(); local f = fixture(old); local ticket = assert(f.ledger.capture())
        f.session = fresh(); eq(f.ledger.getExperience(), "unknown", "getter发现静默换档")
        f.session = old
        eq(f.ledger.commit(ticket, receipt()), false, "切回旧表不复活旧进程票")
        accepted(f, receipt(), "原档新真实捕获"); preserved(f, "切回原档")
    end)
end

local function retryCases()
    local modes = { { label = "通知显式false", set = "false", flush = "true", blocked = true },
        { label = "通知throw", set = "throw", flush = "true", blocked = true },
        { label = "Flush false", set = "void", flush = "false" },
        { label = "Flush nil", set = "void", flush = "nil" },
        { label = "Flush throw", set = "void", flush = "throw" },
        { label = "Flush字符串truthy", set = "void", flush = "truthy" } }
    for _, mode in ipairs(modes) do
        runCase("失败保留内存与两秒重试 " .. mode.label, function()
            local f = fixture(fresh()); local beforeDisk = copy(f.disk)
            f.setMode, f.flushMode = mode.set, mode.flush
            local ticket = accepted(f, receipt(), mode.label)
            eq(f.ledger.isSavePending(), true, "通知/Save失败必须待存")
            check(same(f.disk, beforeDisk), "失败不假称写盘，不修改旧磁盘字段")
            eq(f.flushes, mode.blocked and 0 or 1, "通知拒绝必须阻止Flush")
            eq(f.ledger.commit(ticket, receipt()), false, "失败后也不可重复提交同票")
            local attempts, notices = f.flushes, f.sets
            f.ledger.update(1); f.ledger.update(0.999)
            eq(f.sets, notices, "两秒前不重复通知")
            eq(f.flushes, attempts, "两秒前不重试写盘")
            f.ledger.update(0.001)
            eq(f.sets, notices + 1, "两秒恰好只重试一次通知")
            eq(f.flushes, attempts + (mode.blocked and 0 or 1), "两秒只重试一个Save，不越过拒绝通知")
            f.ledger.update(100)
            eq(f.sets, notices + 2, "大dt不循环轰炸通知")
            eq(f.ledger.isSavePending(), true, "重复失败仍待存")
            preserved(f, mode.label .. "失败重试")
            f.setMode, f.flushMode = "void", "true"
            for _, bad in ipairs({ -1, 0 / 0, math.huge, -math.huge, "2", false }) do f.ledger.update(bad) end
            f.ledger.update(nil); f.ledger.update(0); f.ledger.update(1)
            eq(f.ledger.isSavePending(), true, "非法dt/一秒不推进到成功")
            f.ledger.update(1)
            eq(f.ledger.isSavePending(), false, "后续真实通知/Flush恢复才清待存")
            check(same(f.disk, f.session), "成功保存仍为第一份真实恢复经历")
            local savedAttempts, savedNotices = f.flushes, f.sets
            f.ledger.update(100)
            eq(f.flushes, savedAttempts, "成功停止Save重试")
            eq(f.sets, savedNotices, "成功停止通知重试"); preserved(f, "恢复成功")
        end)
    end
    runCase("通知nil无返回成功兼容以及显式true成功", function()
        for _, mode in ipairs({ "void", "true" }) do
            local f = fixture(fresh()); f.setMode = mode
            accepted(f, receipt(), "通知" .. mode)
            eq(f.ledger.isSavePending(), false, "nil通知不是失败，Flush=true才最终成功")
            eq(f.flushes, 1, "合法通知允许Flush"); preserved(f, "通知兼容")
        end
    end)
    runCase("cancel和同表重新init保留待存，重新init仍使未提交票失效", function()
        local f = fixture(fresh()); f.flushMode = "false"
        local extra = assert(f.ledger.capture()); accepted(f, receipt(), "首次Save失败")
        f.ledger.update(1); f.ledger.cancel()
        eq(f.ledger.isSavePending(), true, "cancel不能丢已提交回执待存")
        eq(f.ledger.commit(extra, receipt()), false, "cancel取消未提交票")
        f.ledger.init(f.options)
        eq(f.ledger.isSavePending(), true, "同表init不得清待存（严格回归，不放宽）")
        eq(f.ledger.getExperience(), "rescued", "同表init保留内存首份")
        f.flushMode = "true"; f.ledger.update(2)
        eq(f.ledger.isSavePending(), false, "同表重新init后仍能按两秒重试成功")
        check(same(f.disk, f.session), "同表init不导致回执永远漏存"); preserved(f, "cancel/init待存")
    end)
    runCase("待存换档init/notification/silent均不串写矩阵", function()
        for _, mode in ipairs({ "init", "notification", "silent" }) do
            local old = fresh(); local f = fixture(old); f.flushMode = "false"
            accepted(f, receipt(), "旧档失败待存")
            local oldBefore, attempts = copy(old), f.flushes
            local next = fresh(); f.session = next
            if mode == "init" then f.ledger.init(f.options)
            elseif mode == "notification" then f.ledger.onSessionUpdated(next) end
            f.flushMode = "true"; f.ledger.update(2)
            eq(f.flushes, attempts, "旧待存绝不能Flush到新session")
            eq(next.samsaraStory.rescueLedger, nil, "不把旧首份复制给新档")
            check(same(old, oldBefore), "不回写旧档旧字段")
            if mode ~= "silent" then eq(f.ledger.isSavePending(), false, "显式换档应清旧待存")
            else f.ledger.onSessionUpdated(next) end
            accepted(f, receipt(), "新档明确附着重新真实恢复")
            check(same(outsideLedger(next), outsideLedger(fresh())), "新档旧字段仍完全不变")
        end
    end)
    runCase("通知过程中换档立即阻止Flush，不把新档当保存成功", function()
        local f = fixture(fresh()); local old = f.session; local next = fresh()
        f.setHook = function() f.session = next; f.ledger.onSessionUpdated(next) end
        eq(f.ledger.commit(assert(f.ledger.capture()), receipt()), true, "真实回执已留在旧档内存")
        eq(f.flushes, 0, "通知发现换档就阻止Flush")
        eq(next.samsaraStory.rescueLedger, nil, "通知重入不把回执转给新档")
        check(same(outsideLedger(old), f.baseline), "旧档之外字段不变")
        f.setHook = false; f.ledger.update(100); eq(f.flushes, 0, "旧待存不得在新档重试")
    end)
    runCase("getter暂时异常的待存保持内存，恢复后节流重试成功", function()
        local f = fixture(fresh()); f.flushMode = "false"; accepted(f, receipt(), "失败待存")
        local attempts = f.flushes; f.throwGet = true; f.ledger.update(2)
        eq(f.flushes, attempts, "getter异常不请求Save")
        eq(f.ledger.isSavePending(), true, "getter异常仍保待存")
        f.throwGet, f.flushMode = false, "true"; f.ledger.update(2)
        eq(f.ledger.isSavePending(), false, "恢复getter后的真实Save成功")
        check(same(f.disk, f.session), "恢复准确落盘"); preserved(f, "getter异常待存")
    end)
end

function Start()
    local originalRequire, originalPackage, originalLoaded = require, package, package.loaded
    local loadedBefore = {}; for key, value in pairs(package.loaded) do loadedBefore[key] = value end
    local ok, err = pcall(function()
        realStage = isolated("config/StageConfig.lua", {})
        realConfig = isolated("config/SamsaraSliceConfig.lua", {})
        initializationCases(); schemaCases(); validReceiptCases(); invalidReceiptCases()
        ticketCases(); sessionCases(); retryCases()
    end)
    if not ok then check(false, "顶层异常=" .. tostring(err)) end
    runCase("私有load真实模块且require/package.loaded零污染", function()
        eq(require, originalRequire, "全局require身份不变")
        eq(package, originalPackage, "全局package身份不变")
        eq(package.loaded, originalLoaded, "package.loaded同一表")
        for key, value in pairs(loadedBefore) do eq(package.loaded[key], value, "已加载模块未替换 " .. tostring(key)) end
        for key, value in pairs(package.loaded) do eq(loadedBefore[key], value, "没有泄漏额外全局require " .. tostring(key)) end
        eq(loadCounts["config/StageConfig.lua"], 1, "真实StageConfig主模块独立load一次")
        for _, suffix in ipairs({ "Normal", "Hard", "Nightmare", "Hell", "Purgatory", "Torment", "Torment2",
            "Torment3", "Torment4", "Torment5", "Annihilation", "Annihilation2", "Annihilation3", "Annihilation4", "Annihilation5" }) do
            eq(loadCounts["config/StageConfig_" .. suffix .. ".lua"], 1, "递归独立load真实StageConfig_" .. suffix)
        end
        check((loadCounts["systems/SamsaraRescueLedger.lua"] or 0) > 20, "各case真实Ledger独立实例，不复制实现")
    end)
    print(PREFIX .. "RESULT assertions=" .. assertions .. " failures=" .. failures .. " cases=" .. cases .. " passed=" .. passed)
    if failures == 0 then print(PREFIX .. "ALL PASS") end
    engine:Exit()
end
