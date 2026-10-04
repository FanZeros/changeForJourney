-- samsara_slice_player_test.lua — 真实 N02 主体与四节点兼容契约隔离回归；不复制数据层实现、不污染全局 require。
-- 后续由主会话执行：UrhoXRuntime tests/samsara_slice_player_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- 此测试只用内存 session/Flush 替身，不访问玩家真实存档或发任何经济协议。
local PREFIX = "[samsara_slice_player] "
local assertions, failures = 0, 0
local KEY, FIRST, REPLAY = "samsara.log_leaf", "samsara_first_read", "samsara_replay"

local function check(ok, message)
    assertions = assertions + 1
    if ok then
        print(PREFIX .. "PASS " .. message)
    else
        failures = failures + 1
        print(PREFIX .. "FAIL " .. message)
        log:Write(LOG_ERROR, PREFIX .. "FAIL " .. message)
    end
end

local function eq(actual, expected, message)
    check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

---@param value any
---@return any
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

---@param a any
---@param b any
---@return boolean
local function equalTables(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not equalTables(value, b[key]) then return false end
    end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

-- 原始源码只读取一次资源并用私有 env load，不做源码字符串替换。
---@param path string
---@param overrides table
---@return table
local function isolated(path, overrides)
    local file = cache:GetFile(path)
    assert(file and file:IsOpen(), "missing real module " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local env = setmetatable({
        require = function(name)
            if overrides[name] ~= nil then return overrides[name] end
            error("测试发现未声明依赖/经济路径: " .. tostring(name))
        end,
    }, { __index = _G })
    return assert(load(table.concat(lines, "\n"), "@" .. path, "t", env))()
end

---@return table
local function oldSession()
    return {
        introCompleted = true, initialHeroId = 1,
        claimedScenarios = { [17] = true, ["82"] = true },
        scenarioRewardsGranted = { ["17"] = true, [82] = true },
        tutorialProgress = { activeGroup = "recruit", unknown = { keep = true } },
        firstLoginTime = 123, offlineBonusCount = 2,
        unknownSessionField = { nested = { keep = "原值" } },
    }
end

local function outsideStory(session)
    local result = {}
    for key, value in pairs(session) do
        if key ~= "samsaraStory" then result[key] = copy(value) end
    end
    return result
end

---@param lease table
---@param reason string
---@return table
local function resultOf(lease, reason)
    return { playToken = lease.playToken, contextEpoch = lease.contextEpoch, nodeKey = lease.nodeKey, reason = reason }
end

function Start()
    local ok, err = pcall(function()
        local Config = isolated("config/SamsaraSliceConfig.lua", {})
        local Schema = isolated("shared/session/SamsaraStorySchema.lua", {})
        local Legacy = isolated("config/ScenarioDialogueConfig.lua", {})

        -- 每个夹具都重载真实 Player 实现；只替换公开 session 和落盘边界。
        local function fixture(session, rawBattle, config, legacy)
            local player = isolated("systems/SamsaraSlicePlayer.lua", {
                ["config.SamsaraSliceConfig"] = config or Config,
                ["shared.session.SamsaraStorySchema"] = Schema,
                ["config.ScenarioDialogueConfig"] = legacy or Legacy,
            })
            ---@type table
            local state = {
                session = session, sets = 0, flushes = 0, disk = {},
                flushResult = true, throwFlush = false, throwSet = false,
            }
            local options = {
                getSession = function() return state.session end,
                setSession = function(value)
                    eq(value, state.session, "setSession 使用共享同表")
                    state.sets = state.sets + 1
                    if state.throwSet then error("模拟通知失败") end
                end,
                flush = function()
                    state.flushes = state.flushes + 1
                    if state.throwFlush then error("模拟编码/写盘异常") end
                    if state.flushResult == true then state.disk = copy(state.session) end
                    return state.flushResult
                end,
            }
            local supported = player.init(options, rawBattle)
            return player, state, options, supported
        end

        eq(Config.NODE_KEY, KEY, "N02 字符串命名空间")
        eq(Config.CONTENT_VERSION, 1, "内容版本为1")
        eq(Config.get("N02"), nil, "不注册策划编号")
        local compatibilityStart = assertions
        check(equalTables(Config.KEYS, { KEY, "samsara.cargo_match", "samsara.gray_order", "samsara.people_record", "samsara.returned_manifest", "samsara.dog_mirror", "samsara.bell_mirror", "samsara.opening_roster", "samsara.dragon_mirror" }), "旧八节点顺序严格保留为前缀，N08仅末尾追加")
        for _, item in ipairs({ { "samsara.cargo_match", "E02" }, { "samsara.gray_order", "E05" }, { "samsara.people_record", "E05" } }) do
            local added = assert(Config.get(item[1]))
            eq(added.mode, "small", item[1] .. "新增小情景")
            eq(added.evidence.id, item[2], item[1] .. "新增物证定义")
            eq(added.rewards, nil, item[1] .. "新增定义无奖")
        end
        print(PREFIX .. "新增四节点兼容 assertions=" .. (assertions - compatibilityStart))
        local cfg = assert(Config.get(KEY))
        eq(cfg.mode, "small", "小情景")
        eq(#cfg.steps, 7, "一行开场旁白与六句正文")
        eq(cfg.steps[1].characterId, nil, "旁白无characterId")
        eq(cfg.steps[1].text, "日志靠近后缝的一页纸卷了角。纸上有一道细灰印，纸边露出被划掉的“回”字。", "开场纸面描述逐字")
        local originals = {
            { id = 1, name = "大狗嚼", text = "叫！说了是我们的。闻得出来。" },
            { id = 2, name = "黄桃龙", text = "有没有记我上次把火把弄丢的事？那页可以不找……" },
            { id = 3, name = "叮咚鸡", text = "页数齐全。夹页，多一张。" },
            { name = "远征长", text = "这字像我写的。" },
            { id = 3, name = "叮咚鸡", text = "叮咚。先记“像”。这页是谁写的，另查。" },
            { id = 1, name = "大狗嚼", text = "那先带着。自己家的东西，别又丢了。" },
        }
        for i, original in ipairs(originals) do
            eq(cfg.steps[i + 1].text, original.text, "第" .. i .. "句原文")
            eq(cfg.steps[i + 1].name, original.name, "第" .. i .. "句人物")
            eq(cfg.steps[i + 1].characterId, original.id, "第" .. i .. "句立绘映射")
        end
        eq(cfg.evidence.id, "E01", "仅E01")
        eq(cfg.evidence.title, "日志夹页", "物证标题不泄谜底")
        eq(cfg.evidence.text, "出征：三人。\n归还：待填。\n干粮留一份在林道路标下。\n若铃声第三下迟了，不要换收件人。\n回……〔被划去〕\n先救人，回来再结。\n〔签名末笔重落两次，登记页号缺损〕", "E01普通原件逐字无困难/地狱批注")
        eq(cfg.rewards, nil, "配置无经济奖励")
        cfg.steps[2].text = "展示方临时覆盖"
        eq(Config.get(KEY).steps[2].text, originals[1].text, "配置副本不污染真实正文")

        -- 尚未init时各查询安全返回，不读取任何玩家状态。
        local uninitialized = isolated("systems/SamsaraSlicePlayer.lua", {
            ["config.SamsaraSliceConfig"] = Config, ["shared.session.SamsaraStorySchema"] = Schema,
            ["config.ScenarioDialogueConfig"] = Legacy,
        })
        eq(uninitialized.peekReady(), nil, "未init无候选")
        eq(uninitialized.takeRequest(), nil, "未init无请求")
        eq(uninitialized.requestRead(KEY), false, "未init不能排请求")
        eq(uninitialized.begin(FIRST, KEY), nil, "未init不展示")
        eq(uninitialized.getRecord().status, "unsupported", "未init档案安全默认")
        eq(uninitialized.getRecord("samsara.cargo_match").status, "unsupported", "未init新增档案安全默认")
        eq(#uninitialized.getRecords(), 9, "未init九档案均安全返回")
        eq(uninitialized.hasPendingRecords(), false, "未init无待阅档案")
        eq(uninitialized.isSavePending(), false, "未init没有待存")
        uninitialized.cancel()
        uninitialized.update(2)

        -- Schema：结构修复只在新嵌套字段里，未知字段保留且幂等。
        local a, b = Schema.new(), Schema.new()
        eq(a.schemaVersion, 1, "默认schema版本")
        eq(a.historyCaptured, false, "默认尚未捕获历史")
        eq(a.cargoHistoryCaptured, false, "默认cargo历史独立未捕获")
        eq(a.dragonHistoryCaptured, false, "默认龙域历史独立未捕获")
        eq(a.dragonHistoryVersion, 1, "默认龙域历史版本为1")
        check(a.nodes ~= b.nodes and a.evidence ~= b.evidence, "默认子表相互独立")
        local session = oldSession()
        local old = outsideStory(session)
        local story, supported = Schema.normalize(session)
        eq(supported, true, "旧session可规范")
        eq(story, session.samsaraStory, "normalize返回新嵌套表而不是session替换")
        check(equalTables(old, outsideStory(session)), "normalize保留所有旧字段")
        story.unknownStoryField = { keep = 9 }
        story.nodes.unrelated = { futureUnknown = true }
        story.nodes[KEY] = { eligible = "false", contentVersion = "1", resolution = "reset", unknownNode = { keep = 1 } }
        story.evidence.E01 = { unlocked = "false", source = 9, unknownEvidence = true }
        Schema.normalize(session)
        eq(story.nodes[KEY].eligible, false, "字符串false资格不转true")
        eq(story.nodes[KEY].resolution, nil, "reset不成为完成结果")
        eq(story.evidence.E01.unlocked, false, "字符串false物证不公开")
        check(story.nodes[KEY].unknownNode.keep == 1 and story.unknownStoryField.keep == 9
            and story.nodes.unrelated.futureUnknown and story.evidence.E01.unknownEvidence, "未知嵌套字段保全")
        local normalized = copy(session)
        Schema.normalize(session)
        check(equalTables(session, normalized), "连续normalize幂等")
        for _, bad in ipairs({ false, "坏结构", 123 }) do
            local broken = { untouched = true, samsaraStory = bad }
            local repaired = Schema.normalize(broken)
            eq(repaired.historyCaptured, false, "非表story修复独立默认")
            eq(broken.untouched, true, "结构修复不删其他字段")
        end
        local brokenFields = { samsaraStory = { historyCaptured = "false", nodes = false, evidence = "x", unknown = 1 } }
        local repaired = Schema.normalize(brokenFields)
        check(type(repaired.nodes) == "table" and type(repaired.evidence) == "table", "子表结构修复")
        eq(repaired.historyCaptured, false, "historyCaptured严格布尔")
        eq(repaired.unknown, 1, "修复保留未知字段")

        -- 通关捕获矩阵：明确true才能解锁，数字/字符串键双路径独立覆盖。
        local cases = {
            { label = "数字true", battle = { clearedStages = { [104] = true } }, ready = true },
            { label = "字符串true", battle = { clearedStages = { ["104"] = true } }, ready = true },
            { label = "数字false", battle = { clearedStages = { [104] = false } } },
            { label = "字符串键false", battle = { clearedStages = { ["104"] = false } } },
            { label = "字符串false值", battle = { clearedStages = { [104] = "false" } } },
            { label = "字符串true值", battle = { clearedStages = { [104] = "true" } } },
            { label = "数字1值", battle = { clearedStages = { [104] = 1 } } },
            { label = "max-only", battle = { currentStageId = 4905, maxStageId = 9999 } },
            { label = "其他通关键", battle = { clearedStages = { [105] = true, [4905] = true } }, cargoReady = true },
            { label = "非法104键", battle = { clearedStages = { ["0104"] = true, ["104x"] = true } } },
            { label = "无快照" },
        }
        for _, case in ipairs(cases) do
            local originalSession = oldSession()
            local originalFields = outsideStory(originalSession)
            local p, state = fixture(originalSession, case.battle)
            eq(p.peekReady(), case.ready and KEY or (case.cargoReady and "samsara.cargo_match" or nil), case.label .. "资格（N02不借4905，新增N12可独立待阅）")
            eq(p.getRecord().status, case.ready and "pending" or "locked", case.label .. "档案状态")
            eq(originalSession.samsaraStory.historyCaptured, true, case.label .. "历史扫描已持久化")
            eq(state.flushes, 1, case.label .. "没有资格也立即Flush一次")
            eq(state.disk.samsaraStory.historyCaptured, true, case.label .. "磁盘替身有捕获标记")
            eq(p.getRecord().evidenceVisible, false, case.label .. "首次处理前不公开原件")
            eq(p.getRecord().evidence, nil, case.label .. "不从档案泄露待核原件正文")
            if case.ready then
                eq(originalSession.samsaraStory.nodes[KEY].eligibilitySource, "clear_104_legacy", case.label .. "历史来源不可反推")
                eq(p.getRecord().legacyContext, "legacy_claimed_unknown", case.label .. "旧claimed不等于完整读过")
                eq(p.peekReady(), KEY, case.label .. "peek无破坏")
            else
                eq(p.requestRead(KEY), false, case.label .. "锁定时不能请求回看")
                eq(p.begin(REPLAY, KEY), nil, case.label .. "锁定时不能begin回看")
            end
            check(equalTables(originalFields, outsideStory(originalSession)), case.label .. "旧账本教程字段无变化")
        end

        -- historyCaptured防后来battle恢复污染；同表二次init和模块重载都不重新推断。
        local clean = oldSession()
        local p, state, options = fixture(clean, { maxStageId = 9999, clearedStages = {} })
        p.init(options, { clearedStages = { [104] = true } })
        eq(p.getRecord().status, "locked", "二次init不能读取后来恢复的104")
        eq(state.flushes, 1, "二次init无变化不重复保存")
        local restarted = fixture(copy(clean), { clearedStages = { ["104"] = true } })
        eq(restarted.getRecord().status, "locked", "重启仍受historyCaptured阻止污染")
        local fresh = { introCompleted = true, initialHeroId = 1, claimedScenarios = {} }
        local live, liveState = fixture(fresh, { maxStageId = 9999 })
        eq(live.onStageCleared(105), false, "仅104可实时首通")
        eq(live.onStageCleared("0104"), false, "实时首通不宽松解析id")
        eq(live.onStageCleared("104"), true, "真实字符串104首通解锁")
        eq(fresh.samsaraStory.nodes[KEY].eligibilitySource, "live_clear", "真实首通来源live_clear")
        eq(live.onStageCleared(104), false, "重复首通幂等不改来源")
        eq(liveState.flushes, 2, "捕获和首通各存一次")
        eq(live.peekReady(), nil, "未claimed且旧真实配置存在必须等旧来源")
        eq(live.begin(FIRST, KEY), nil, "begin不抢有效未处理的旧日志")
        eq(live.requestRead(KEY), true, "待阅可先保留显式首读请求")
        eq(live.noteLegacyResult(18, "finished"), false, "错分支结束无效")
        eq(live.noteLegacyResult(17, "reset"), false, "旧reset不冒充处理")
        eq(live.noteLegacyResult(17, "finished"), true, "旧真实结束释放来源依赖")
        eq(live.getRecord().legacyContext, "live_finished", "来源记live_finished")
        eq(fresh.claimedScenarios[17], nil, "noteLegacyResult绝不写旧claimed")
        local request = assert(live.takeRequest())
        eq(request.key, KEY, "所有门禁后消费首读key")
        eq(request.kind, FIRST, "所有门禁后消费首读kind")
        eq(live.takeRequest(), nil, "请求只能消费一次")

        -- 三初始分支、数字/字符串旧claimed、缺配置与旧真实skip语境。
        for heroId = 1, 3 do
            local id = 16 + heroId
            for _, key in ipairs({ id, tostring(id) }) do
                local claimed = { introCompleted = true, initialHeroId = tostring(heroId), claimedScenarios = { [key] = true } }
                local branch = fixture(claimed, { clearedStages = { [104] = true } })
                eq(branch.getRecord().legacyContext, "legacy_claimed_unknown", "分支" .. heroId .. "数字/字符串claimed兼容")
                check(branch.begin(FIRST, KEY) ~= nil, "分支" .. heroId .. "旧claimed允许独立补读")
                branch.cancel()
            end
            local pendingSession = { initialHeroId = heroId, claimedScenarios = {} }
            local pending = fixture(pendingSession, { clearedStages = { [104] = true } })
            eq(pending.noteLegacyResult(id, "dismissed"), true, "分支" .. heroId .. "dismissed为live_finished")
            eq(pending.getRecord().legacyContext, "live_finished", "分支" .. heroId .. "真实dismissed来源")
            local skipped = fixture({ initialHeroId = heroId, claimedScenarios = {} }, { clearedStages = { [104] = true } })
            eq(skipped.noteLegacyResult(tostring(id), "skipped"), true, "分支" .. heroId .. "旧skip")
            eq(skipped.getRecord().legacyContext, "live_skipped", "旧skip不写完整读过")
            check(skipped.begin(FIRST, KEY) ~= nil, "旧skip释放N02依赖")
            local grantedOnly = fixture({ initialHeroId = heroId, claimedScenarios = { [id] = false },
                scenarioRewardsGranted = { [id] = true } }, { clearedStages = { [104] = true } })
            eq(grantedOnly.peekReady(), nil, "奖励granted不能代替旧段claimed或真实结束")
            eq(grantedOnly.begin(FIRST, KEY), nil, "有granted且claimed=false仍等旧日志")
            for _, reason in ipairs({ "reset", "replaced", "failed" }) do
                eq(pending.noteLegacyResult(id, reason), false, "旧" .. reason .. "不改真实来源")
            end
            local fieldsBeforeReinit = copy(pendingSession)
            local ignoredRaw = { clearedStages = { [104] = false } }
            pending.init({ getSession = function() return pendingSession end, setSession = function() end,
                flush = function() return true end }, ignoredRaw)
            check(equalTables(pendingSession, fieldsBeforeReinit), "二次init保留真实旧日志来源")
            local missing = fixture({ initialHeroId = heroId, claimedScenarios = {} }, { clearedStages = { [104] = true } }, nil, {})
            eq(missing.getRecord().legacyContext, "unavailable", "旧配置缺失标记异常来源")
            check(missing.begin(FIRST, KEY) ~= nil, "不存在的旧段不会永久卡住N02")
        end

        -- 租约：错误token/epoch/key、重复回调、篡改外部租约、取消、新session。
        local tokenPlayer, tokenState, tokenOptions = fixture(oldSession(), { clearedStages = { [104] = true } })
        eq(tokenPlayer.begin("legacy_reference", KEY), nil, "不承接其他kind")
        eq(tokenPlayer.begin(FIRST, "N02"), nil, "不承接数字旧命名空间")
        eq(tokenPlayer.begin(REPLAY, KEY), nil, "待阅不能越过首读回看")
        local lease = assert(tokenPlayer.begin(FIRST, KEY))
        eq(lease.nodeKey, KEY, "租约nodeKey")
        eq(lease.kind, FIRST, "租约kind")
        eq(lease.contentVersion, 1, "租约contentVersion")
        eq(type(lease.playToken), "number", "租约token类型")
        eq(type(lease.contextEpoch), "number", "租约epoch类型")
        eq(tokenPlayer.peekReady(), nil, "活跃租约时不重复提供自动候选")
        eq(tokenPlayer.begin(FIRST, KEY), nil, "同一时刻只有一个租约")
        eq(tokenPlayer.requestRead(KEY), false, "活跃租约不重复排请求")
        for _, field in ipairs({ "playToken", "contextEpoch", "nodeKey" }) do
            local bad = resultOf(lease, "finished")
            bad[field] = "错误身份"
            eq(tokenPlayer.onResult(bad), false, "错误" .. field .. "拒绝")
        end
        eq(tokenPlayer.onResult(resultOf(lease, "unknown")), false, "未知reason不消费租约")
        local actualLease = copy(lease)
        lease.playToken = -1
        eq(tokenPlayer.onResult(resultOf(lease, "finished")), false, "返回租约的修改不改内部身份")
        eq(tokenPlayer.onResult(resultOf(actualLease, "finished")), true, "当前精确租约可完成")
        eq(tokenPlayer.onResult(resultOf(actualLease, "skipped")), false, "重复结果不能覆盖首次resolution")
        eq(tokenPlayer.getRecord().status, "finished", "finished状态")
        eq(tokenPlayer.getRecord().evidenceVisible, true, "完成后原件可见")
        eq(tokenPlayer.getRecord().evidence.text, Config.get(KEY).evidence.text, "完成后原件正确")
        local readRecord = tokenPlayer.getRecord()
        readRecord.evidence.text = "UI覆盖"
        eq(tokenPlayer.getRecord().evidence.text, Config.get(KEY).evidence.text, "档案返回副本不污染正文")
        eq(tokenPlayer.peekReady(), nil, "已处理不自动重播")
        eq(tokenPlayer.begin(FIRST, KEY), nil, "已处理拒绝首读")
        local replay = assert(tokenPlayer.begin(REPLAY, KEY))
        check(replay.playToken > actualLease.playToken, "每次播放token递增")
        eq(tokenPlayer.onResult(resultOf(actualLease, "finished")), false, "新租约拒绝旧token")
        local replayBefore, replayFlushes = copy(tokenState.session), tokenState.flushes
        eq(tokenPlayer.onResult(resultOf(replay, "skipped")), true, "回看skip可以结束展示")
        check(equalTables(tokenState.session, replayBefore), "回看不改首次resolution或任何账本")
        eq(tokenState.flushes, replayFlushes, "回看不请求无谓保存")
        eq(tokenPlayer.requestRead(KEY), true, "已处理显式请求回看")
        eq(tokenPlayer.takeRequest().kind, REPLAY, "已处理请求kind回看")
        local stale = assert(tokenPlayer.begin(REPLAY, KEY))
        tokenPlayer.cancel()
        eq(tokenPlayer.onResult(resultOf(stale, "finished")), false, "cancel失效旧租约")
        local afterCancel = assert(tokenPlayer.begin(REPLAY, KEY))
        check(afterCancel.contextEpoch > stale.contextEpoch, "cancel递增epoch")
        tokenPlayer.init(tokenOptions, { clearedStages = {} })
        eq(tokenPlayer.onResult(resultOf(afterCancel, "finished")), false, "同表二次init拒绝上轮租约")
        local beforeSwap = assert(tokenPlayer.begin(REPLAY, KEY))
        tokenState.session = oldSession()
        eq(tokenPlayer.onResult(resultOf(beforeSwap, "finished")), false, "未init换session也拒绝迟到结果")
        eq(tokenState.session.samsaraStory, nil, "迟到结果不为新session写任何嵌套状态")
        tokenPlayer.init(tokenOptions, {})
        eq(tokenPlayer.getRecord().status, "locked", "新session重新捕获资格")
        eq(tokenPlayer.onResult(resultOf(beforeSwap, "skipped")), false, "新session初始化后旧回调仍被拒绝")

        -- 所有结果分类：成功/skip持久化；中断只取消，主仲裁下一帧可重新begin。
        for _, reason in ipairs({ "finished", "dismissed", "skipped", "reset", "replaced", "failed" }) do
            local rp, rs = fixture(oldSession(), { clearedStages = { [104] = true } })
            local first = assert(rp.begin(FIRST, KEY))
            local before = rs.flushes
            eq(rp.onResult(resultOf(first, reason)), true, reason .. "当前租约可接受")
            eq(rp.onResult(resultOf(first, reason)), false, reason .. "同token只能一次")
            if reason == "reset" or reason == "replaced" or reason == "failed" then
                eq(rp.getRecord().status, "pending", reason .. "不记完成")
                eq(rp.getRecord().evidenceVisible, false, reason .. "不公开证据")
                eq(rs.flushes, before, reason .. "取消不立即反复保存/重播")
                rp.update(100)
                eq(rs.flushes, before, reason .. "update不自动重播")
                local retry = assert(rp.begin(FIRST, KEY))
                check(retry.contextEpoch > first.contextEpoch and retry.playToken > first.playToken, reason .. "下一次仲裁取得新身份")
            else
                eq(rp.getRecord().status, reason == "skipped" and "skipped" or "finished", reason .. "精确resolution")
                eq(rs.flushes, before + 1, reason .. "结果只存一次")
                eq(rp.getRecord().evidenceVisible, true, reason .. "首次处理后可回看物证")
                local savedSession = copy(rs.session)
                for _, replayReason in ipairs({ "finished", "dismissed", "skipped", "reset", "replaced", "failed" }) do
                    local replayLease = assert(rp.begin(REPLAY, KEY))
                    eq(rp.onResult(resultOf(replayLease, replayReason)), true, reason .. "/回看" .. replayReason .. "结果")
                    check(equalTables(rs.session, savedSession), reason .. "/回看" .. replayReason .. "不修改保存账本")
                end
                local reloaded = fixture(cjson.decode(cjson.encode(savedSession)), {})
                eq(reloaded.getRecord().status, reason == "skipped" and "skipped" or "finished", "JSON往返保存" .. reason)
                eq(reloaded.getRecord().evidenceVisible, true, "JSON往返原件可见")
            end
        end

        -- 未来schema保全原始表/字段，禁止资格、请求、播放、结果与保存。
        for _, version in ipairs({ 2, "3" }) do
            local future = oldSession()
            future.samsaraStory = { schemaVersion = version, historyCaptured = "未知新格式", nodes = "新节点格式", unknown = { keep = 3 } }
            local beforeFuture, futureRef = copy(future), future.samsaraStory
            local returned, futureSupported = Schema.normalize(future)
            eq(returned, futureRef, "未来schema保留同一引用")
            eq(futureSupported, false, "未来schema不支持")
            check(equalTables(future, beforeFuture), "normalize未来版本原样保留")
            local fp, fs, _, enabled = fixture(future, { clearedStages = { [104] = true } })
            eq(enabled, false, "Player禁用未来schema")
            eq(fp.getRecord().status, "unsupported", "未来档案只报告不兼容")
            eq(fp.getRecord().evidenceVisible, false, "未来版本禁止读原件")
            eq(fp.peekReady(), nil, "未来版本无候选")
            eq(fp.requestRead(KEY), false, "未来版本不能请求")
            eq(fp.takeRequest(), nil, "未来版本无请求")
            eq(fp.begin(FIRST, KEY), nil, "未来版本禁止首读")
            eq(fp.begin(REPLAY, KEY), nil, "未来版本禁止回看")
            eq(fp.onStageCleared(104), false, "未来版本不能写资格")
            eq(fp.noteLegacyResult(17, "finished"), false, "未来版本不能写语境")
            eq(fp.onResult({ playToken = 1, contextEpoch = 1, nodeKey = KEY, reason = "finished" }), false, "未来版本拒绝結果")
            fp.cancel()
            fp.update(100)
            eq(fs.flushes, 0, "未来版本不请求写盘")
            check(equalTables(future, beforeFuture), "Player所有API保全未来版本原始结构")
        end
        -- 正在播放时外部将同一story升级为未来版本，当前结果也不能落盘。
        local changing, changingState = fixture(oldSession(), { clearedStages = { [104] = true } })
        local changingLease = assert(changing.begin(FIRST, KEY))
        changingState.session.samsaraStory.schemaVersion = 2
        local changedBefore = copy(changingState.session)
        local changeFlushes = changingState.flushes
        eq(changing.onResult(resultOf(changingLease, "finished")), false, "活跃租约遇未来schema也拒绝写入")
        eq(changing.onStageCleared(104), false, "运行中升级拒绝资格写入")
        eq(changing.requestRead(KEY), false, "运行中升级拒绝请求")
        check(equalTables(changingState.session, changedBefore), "运行中升级后数据原样保全")
        eq(changingState.flushes, changeFlushes, "运行中升级不Flush未来数据")

        local futureContent = oldSession()
        futureContent.samsaraStory = Schema.new()
        futureContent.samsaraStory.historyCaptured = true
        futureContent.samsaraStory.nodes[KEY] = { eligible = true, contentVersion = 2, resolution = "新版结果", unknown = 99 }
        local futureNode = copy(futureContent.samsaraStory.nodes[KEY])
        local newer = fixture(futureContent, {})
        eq(newer.getRecord().status, "unsupported", "未来内容版本也禁止播放")
        eq(newer.begin(FIRST, KEY), nil, "未来内容不能覆盖")
        check(equalTables(futureContent.samsaraStory.nodes[KEY], futureNode), "未来内容节点原样保留")

        -- 配置缺失、非法配置、配置异常均不产生租约或误完成。
        for _, get in ipairs({ function() return nil end, function() return { title = "坏配置", mode = "small", steps = {} } end,
            function() error("模拟配置异常") end }) do
            local brokenConfig = { NODE_KEY = KEY, CONTENT_VERSION = 1, get = get }
            local cp, cs = fixture(oldSession(), { clearedStages = { [104] = true } }, brokenConfig)
            eq(cp.peekReady(), nil, "缺失/错误配置无候选")
            eq(cp.begin(FIRST, KEY), nil, "缺失/错误配置拒绝租约")
            eq(cp.getRecord().status, "unsupported", "缺失/错误配置标不兼容")
            eq(cs.session.samsaraStory.nodes[KEY].resolution, nil, "错误配置不写处理结果")
        end

        -- Flush失败保留内存与待存状态；两秒重试，成功前只改新嵌套表。
        local retrySession = oldSession()
        local retryPlayer, retryState, retryOptions = fixture(retrySession, { clearedStages = { [104] = true } })
        local retryFields = outsideStory(retrySession)
        retryState.flushResult = false
        local retryLease = assert(retryPlayer.begin(FIRST, KEY))
        retryPlayer.onResult(resultOf(retryLease, "finished"))
        eq(retryPlayer.getRecord().status, "finished", "失败时内存结果保留")
        eq(retryPlayer.isSavePending(), true, "失败后标记待保存")
        eq(retryState.disk.samsaraStory.nodes[KEY].resolution, nil, "失败不假称磁盘成功")
        local attempts = retryState.flushes
        retryPlayer.update(1)
        retryPlayer.update(0.999)
        eq(retryState.flushes, attempts, "两秒前不重试")
        retryPlayer.update(0.001)
        eq(retryState.flushes, attempts + 1, "两秒恰好重试一次")
        retryPlayer.update(100)
        eq(retryState.flushes, attempts + 2, "大dt不循环轰炸Flush")
        retryPlayer.requestRead(KEY)
        retryPlayer.cancel()
        eq(retryPlayer.takeRequest(), nil, "cancel清显式请求")
        eq(retryPlayer.isSavePending(), true, "cancel不丢待保存结果")
        retryPlayer.init(retryOptions, {})
        eq(retryPlayer.isSavePending(), true, "同表二次init保留待保存")
        retryState.throwFlush = true
        retryPlayer.update(2)
        eq(retryPlayer.isSavePending(), true, "Flush异常保留待存")
        retryState.throwFlush = false
        retryState.throwSet = true
        local beforeSetError = retryState.flushes
        retryPlayer.update(2)
        eq(retryState.flushes, beforeSetError, "通知失败不假称落盘")
        eq(retryPlayer.isSavePending(), true, "通知失败保留待存")
        retryState.throwSet = false
        retryState.flushResult = nil
        retryPlayer.update(2)
        eq(retryPlayer.isSavePending(), true, "Flush nil不是成功")
        retryState.flushResult = true
        retryPlayer.update(-10)
        retryPlayer.update(0 / 0)
        retryPlayer.update(math.huge)
        retryPlayer.update(1)
        eq(retryPlayer.isSavePending(), true, "非法dt不推进重试")
        retryPlayer.update(1)
        eq(retryPlayer.isSavePending(), false, "成功后清待存")
        eq(retryState.disk.samsaraStory.nodes[KEY].resolution, "finished", "恢复后保存首次结果")
        check(equalTables(retryFields, outsideStory(retrySession)), "全部失败/重试只改新表旧字段保全")
        local doneAttempts = retryState.flushes
        retryPlayer.update(100)
        eq(retryState.flushes, doneAttempts, "保存成功后不再重试")

        -- 首次无资格捕获失败也必须保留待存，不能二次init扫描后来max恢复的通关表。
        local noHistory = oldSession()
        noHistory.samsaraStory = Schema.new()
        local np = isolated("systems/SamsaraSlicePlayer.lua", {
            ["config.SamsaraSliceConfig"] = Config, ["shared.session.SamsaraStorySchema"] = Schema,
            ["config.ScenarioDialogueConfig"] = Legacy,
        })
        local canSave, captureFlushes = false, 0
        local captureOptions = {
            getSession = function() return noHistory end,
            setSession = function(value) eq(value, noHistory, "无资格捕获共享同表") end,
            flush = function() captureFlushes = captureFlushes + 1 return canSave end,
        }
        np.init(captureOptions, { maxStageId = 9999 })
        eq(noHistory.samsaraStory.historyCaptured, true, "无资格且失败仍记内存捕获")
        eq(np.isSavePending(), true, "无资格捕获失败待存")
        np.init(captureOptions, { clearedStages = { [104] = true } })
        eq(np.getRecord().status, "locked", "捕获失败二次init也不反推104")
        canSave = true
        np.update(2)
        eq(np.isSavePending(), false, "无资格捕获恢复后可保存")
        eq(captureFlushes, 2, "首次失败和节流重试两次")
    end)
    if not ok then check(false, "异常: " .. tostring(err)) end
    print(PREFIX .. "RESULT assertions=" .. assertions .. " failures=" .. failures)
    if failures == 0 then print(PREFIX .. "ALL PASS") end
    engine:Exit()
end
