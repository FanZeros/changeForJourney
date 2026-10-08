-- 一券一场/资源也扫/券更多：纯Lua隔离真实规则回归；不运行Boot、不访问玩家存档。
-- 入口可由官方Runtime执行，也可用lupa.lua54 + 只读cache替身执行Start。
local F = require("tests.SweepRegressionFixture")
local TAG = "[sweep_battle_regression_test] "
local assertions, cases, passed = 0, 0, 0
local failures = {} ---@type string[]

local function check(value, message)
    assertions = assertions + 1
    assert(value, message)
end
local function eq(actual, expected, message)
    check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function same(actual, expected, message) check(F.equal(actual, expected), message) end
local function near(actual, expected, message)
    check(math.abs(actual - expected) < 1e-8, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function run(label, callback)
    cases = cases + 1
    local ok, err = pcall(callback)
    if ok then passed = passed + 1; print(TAG .. "PASS " .. label)
    else failures[#failures + 1] = label .. " => " .. tostring(err); print(TAG .. "FAIL " .. failures[#failures]) end
end
local function preview(h, team, stage, count)
    local d = h.data
    return h.Sweep.Preview(d.heroes, d.battle, d.dungeon, d.equipment,
        d.artifacts, d.talents, team, stage, count, d.player)
end

-- 保存所有原table边：不仅比较值，也逐个证明模块/数组/英雄/装备/嵌套词条别名还在。
local function capture(value, records, seen)
    if type(value) ~= "table" or seen[value] then return end
    seen[value] = true
    local fields = {}
    records[#records + 1] = { target = value, fields = fields }
    for key, child in pairs(value) do fields[key] = child; capture(child, records, seen) end
end
local function assertRollback(h, operation, label)
    local dataBefore, walletBefore, diskBefore = F.copy(h.data), F.copy(h.wallet), F.copy(h.disk)
    local records = {}; capture(h.data, records, {})
    local notifications, events = h.notifications, h.events
    eq(operation(), false, label .. "失败回执")
    same(h.data, dataBefore, label .. "全部模块值回滚")
    same(h.wallet, walletBefore, label .. "GameState回滚")
    same(h.disk, diskBefore, label .. "旧mock持久化快照不变")
    for _, record in ipairs(records) do
        for key, child in pairs(record.fields) do
            if type(child) == "table" then eq(record.target[key], child, label .. "原table边 " .. tostring(key)) end
        end
    end
    eq(h.notifications, notifications, label .. "不通知半成品")
    eq(h.events, events, label .. "不发余额事件")
    eq(next(h.dirty), nil, label .. "不脏写")
end

local function testMainBattle()
    local h = F.new(); F.install(h, 0)
    local entry = assert(h.SC.getStage(6705))
    check(entry.monsterLevel > 60, "真实夹具必须超过旧60级上限")
    check(entry.bossId > 0, "真实夹具有Boss")
    check((entry.fcGold or 0) + (entry.fcExp or 0) + (entry.fcEquip or 0) > 0, "真实首通大奖非零")
    h.data.battle.currentStageId = 6705
    h.data.player.level = 100 -- 非满级，才能观察实际经验增量。
    local enemies = h.Spawn.generateEnemyList(entry, false)
    local gold, exp, bosses = 0, 0, 0
    for _, unit in ipairs(enemies) do
        gold, exp = gold + unit.goldReward, exp + unit.expReward
        if unit.isBoss then bosses = bosses + 1 end
    end
    eq(#enemies, entry.idleCount, "一场使用重复战斗怪数，不用首通怪数")
    eq(bosses, 1, "Boss仅占一名额")
    for team = 1, 3 do
        for _, count in ipairs({ 1, 3, 10 }) do
            local result = assert(preview(h, team, 6705, count))
            eq(result.gold, gold * count, "金币严格等于在线怪物奖励和")
            eq(result.playerExp, exp * count, "远征经验严格等于在线怪物奖励和")
            eq(result.kills, #enemies * count, "券按场而不是分钟/多关")
            eq(result.cost, count, "每券仅一场")
            eq(result.heroExp, math.floor(exp * h.ET.getHeroCountExpMult(team) / team + 0.5) * count,
                "有效队员平分经验/空槽排除")
            near(result.equipCount, #enemies * count * entry.dropRate, "预估装备按逐杀概率，不固定件数")
            near(result.scrollCount, #enemies * count * entry.scrollDropRate, "卷轴按逐杀概率")
        end
    end
    local first = h.Spawn.generateEnemyList(entry, true)
    check(#first >= #enemies, "首通与重复场景可区分")
    h.Drop.generateFirstClearEquips = function() error("扫荡不允许首通装备生成") end
    h.Drop.generateFirstClearScrolls = function() error("扫荡不允许首通卷轴生成") end
    h.Drop.rollSweepTicket = function() error("扫荡禁止返券RNG") end
    h.forceRandom = 0.999999
    local battleBefore, dungeonBefore, sessionBefore = F.copy(h.data.battle), F.copy(h.data.dungeon), F.copy(h.data.session)
    local ok, err, result = h.Sweep.Sweep(1, 1, 2, 6705)
    check(ok, "60级以上真实扫荡必须可结算 " .. tostring(err))
    eq(result.gold, gold, "实际单场金币不包含fcGold")
    eq(result.playerExp, exp, "实际单场经验不包含fcExp")
    eq(result.equipCount, 0, "未命中逐杀时不偷发首通/固定装备")
    eq(result.diamond, 0, "主线扫荡不发首通钻石")
    eq(result.ticketDrop, 0, "扫荡不能产券")
    eq(h.data.currency.sweepTicket, 29, "只扣一券不返券")
    eq(h.data.player.exp, exp, "远征经验实际写入")
    for id, hero in pairs(h.data.heroes.roster) do
        eq(hero.exp, (id == 2 or id == 3) and result.heroExp or 0, "只发锁定队经验hero" .. id)
    end
    eq(h.persists, 1, "一场只持久化一次")
    same(h.data.battle, battleBefore, "扫荡不推进主线/队伍位置/挂机快照")
    same(h.data.dungeon, dungeonBefore, "扫荡不改首通账本/每日次/挂机积累")
    same(h.data.session, sessionBefore, "扫荡不补发情景首通记录")
    eq(result.heroExpBatches, nil, "内部经验顺序字段不得泄露正式回执")
    same(h.data.battle, h.disk.battle, "场景进度保持")
end

local function testResourceRounding()
    for _, id in ipairs({ "gold_mine", "black_diamond", "equipment_vault" }) do
        local h = F.new(); F.install(h, 0)
        local stage = h.DC.getStageId(id, 1)
        local entry = assert(h.SC.getStage(stage))
        local expPerKill = h.DC.getStageExpAmount(stage, 1)
        if id ~= "equipment_vault" then
            check(expPerKill * entry.idleCount ~= h.DC.getStageExpAmount(stage, entry.idleCount),
                "真实夹具可区分逐杀取整和整场取整 " .. id)
        end
        for team = 1, 3 do
            for _, count in ipairs({ 1, 10 }) do
                local exp = expPerKill
                local perKillHero = math.floor(math.floor(exp * h.ET.getHeroCountExpMult(team) + 0.5) / team + 0.5)
                local result = assert(preview(h, team, stage, count))
                eq(result.playerExp, exp * entry.idleCount * count, "资源远征经验逐杀取整 " .. id)
                eq(result.heroExp, perKillHero * entry.idleCount * count, "资源每人经验逐杀双重取整 " .. id)
                eq(result.heroExpTotal, result.heroExp * team, "资源报告与实际所有英雄增量相等")
                eq(result.kills, entry.idleCount * count, "资源重复场使用真实单场怪数")
                local expected = h.DC.getStageRewardAmount(stage, 1) * entry.idleCount * count
                near(id == "gold_mine" and result.gold or id == "black_diamond" and result.diamond or result.equipCount,
                    expected, "资源只读原始期望，不用首通/12h基准 " .. id)
                eq(result.ticketDrop, 0, "资源预估不返券")
                eq(result.scrollDrops.sweepTicket, nil, "资源估算剔除票券")
            end
        end
        -- 在线逐杀接口作为独立oracle，固定RNG复播证明实际奖励与每杀1完全同源。
        local oracle = F.new(); F.install(oracle, 0)
        h.forceRandom, oracle.forceRandom = 0, 0
        local expectedGold, expectedDiamond, expectedExp, expectedHero, expectedEquips, expectedScrolls = 0, 0, 0, 0, 0, {}
        for _ = 1, entry.idleCount do
            local rewards = oracle.DC.getStageRewards(stage, 1, 3)
            expectedGold = expectedGold + rewards.gold
            expectedDiamond = expectedDiamond + rewards.diamond
            expectedExp = expectedExp + rewards.adventureExp
            expectedHero = expectedHero + math.floor(rewards.adventurerExp / 3 + 0.5)
            expectedEquips = expectedEquips + #rewards.equipSeeds
            for key, amount in pairs(rewards.scrollDrops) do
                if key ~= "sweepTicket" then expectedScrolls[key] = (expectedScrolls[key] or 0) + amount end
            end
        end
        local ok, err, result = h.Sweep.Sweep(1, 1, 3, stage)
        check(ok, "资源真实单场结算 " .. id .. " " .. tostring(err))
        eq(result.gold, expectedGold, "资源逐杀真实金币")
        eq(result.diamond, expectedDiamond, "资源逐杀真实黑晶")
        eq(result.playerExp, expectedExp, "资源逐杀真实远征经验")
        eq(result.heroExp, expectedHero, "资源逐杀真实英雄经验")
        eq(result.equipCount, expectedEquips, "资源逐杀真实装备数")
        same(result.scrollDrops, expectedScrolls, "资源逐杀真实卷轴且过滤返券")
        eq(h.data.currency.sweepTicket, 29, "即便每杀券命中也只扣一券")
        eq(result.scrollDrops.sweepTicket, nil, "资源实际奖励剔除返券")
        eq(result.gold == 0 or result.gold ~= (h.DC.getFloor(id, 1).firstGold or 0), true, "无资源首通金币大奖")
    end
end

local function testPreviewPurity()
    local h = F.new(); F.install(h, 200)
    local equipment = assert(h.ES.generate("C1", 70, 4))
    equipment.seq, equipment.testNested = 999, { preserved = true }
    h.data.equipment.inventory["999"] = equipment
    h.data.equipment.equipped["2"] = { accessory = 999 }
    -- 旧字符串键、空槽以及额外缓存字段不能被normalize/水合就地修改。
    h.data.heroes.roster["2"], h.data.heroes.roster[2] = h.data.heroes.roster[2], nil
    h.data.heroes.teams["2"], h.data.heroes.teams[2] = h.data.heroes.teams[2], nil
    local before = F.copy(h.data)
    h.rngCalls = 0 -- 装备夹具生成已结束，从Preview边界开始计数。
    h.forbidRNG = true
    h.modules["rules.character.PlayerDataManager"].GetModule = function() error("Preview禁止读取PDM") end
    h.ES.generateRandom = function() error("Preview禁止生成装备") end
    local stages = { 1905, 6705, 100001, 200001, 300001 }
    for _, stage in ipairs(stages) do
        for _, count in ipairs({ 1, 10 }) do
            local result = assert(preview(h, "2", tostring(stage), count))
            eq(result.stageId, stage, "字符串目标规范化")
            eq(result.teamIdx, 2, "字符串队号规范化")
        end
    end
    eq(h.rngCalls, 0, "所有Preview零RNG")
    eq(h.persists, 0, "所有Preview零存档")
    eq(h.notifications, 0, "所有Preview零通知")
    same(h.data, before, "所有Preview不修改任一快照/词条/编队")
end

local function testGuards()
    local invalid = { { "0", 0 }, { "negative", -1 }, { "fraction", 1.5 },
        { "text", "abc" }, { "infinity", math.huge }, { "nan", 0/0 }, { "boolean", false } }
    for _, input in ipairs(invalid) do
        run("非法次数 " .. input[1], function()
            local h = F.new(); F.install(h, 0); h.forbidRNG = true
            local before = F.copy(h.data)
            local result = preview(h, 1, 1905, input[2])
            eq(result, nil, "Preview严格拒绝非法次数")
            eq(h.Sweep.Sweep(1, input[2], 1, 1905), false, "Sweep严格拒绝非法次数")
            same(h.data, before, "非法次数不写任何快照")
            eq(h.rngCalls + h.persists + h.notifications, 0, "非法次数不消费任何资源")
        end)
    end
    local guards = {
        { "未通主线", function(h) h.data.battle.clearedStages[1905] = nil; h.data.battle.clearedStages["1905"] = nil end, 1, 1905 },
        { "未通资源不可凭最高层推定", function(h) h.data.dungeon.gold_mine = { floor = 10, cleared = { [1] = true } } end, 1, 100005 },
        { "锁副本", function(h) h.data.battle.maxStageId = 304 end, 1, 100001 },
        { "锁队", function(h) h.data.battle = { maxStageId = 905, clearedStages = { [101] = true } } end, 2, 101 },
        { "队号小数", function() end, 1.5, 1905 },
        { "队号0", function() end, 0, 1905 },
        { "队内重复", function(h) h.data.heroes.teams[2].slots = { 2, 2 } end, 2, 1905 },
        { "跨队重复", function(h) h.data.heroes.teams[2].slots = { 1, 2 } end, 2, 1905 },
        { "未拥有英雄", function(h) h.data.heroes.teams[2].slots = { 99999 } end, 2, 1905 },
        { "空队", function(h) h.data.heroes.teams[2].slots = { 0, 0, 0, 0 } end, 2, 1905 },
        { "非法目标", function() end, 1, 999999 },
    }
    for _, guard in ipairs(guards) do
        run("门禁 " .. guard[1], function()
            local h = F.new(); F.install(h, 0); guard[2](h); h.forbidRNG = true
            local before = F.copy(h.data)
            eq(preview(h, guard[3], guard[4], 1), nil, "Preview拒绝门禁")
            eq(h.Sweep.Sweep(1, 1, guard[3], guard[4]), false, "Sweep拒绝门禁")
            same(h.data, before, "拒绝不normalize/写快照")
            eq(h.rngCalls + h.persists + h.notifications, 0, "门禁零RNG/存档/通知")
        end)
    end
    run("合法数字字符串/缺省次数", function()
        local h = F.new(); F.install(h, 0)
        eq(assert(preview(h, "1", "1905", "10")).cost, 10, "合法字符串10券10场")
        eq(assert(preview(h, 1, 1905)).cost, 1, "Preview缺省1场")
        eq(h.Sweep.Sweep(1, nil, 1, 1905), true, "Sweep缺省1场")
        eq(h.data.currency.sweepTicket, 29, "缺省仅扣1券")
    end)
end

local function testProtocolParity()
    for _, id in ipairs({ "gold_mine", "black_diamond", "equipment_vault" }) do
        for _, count in ipairs({ 1, 3, 10 }) do
            local a, b = F.new(), F.new(); F.install(a, 199); F.install(b, 199)
            -- 同RNG、同数据，两个真实Handler必须交付同样奖励，只允许副本标签差异。
            local protocol = a.require("shared.Protocol").ACTION_TYPES
            local stage = a.DC.getStageId(id, 1)
            local ra = a.require("rules.sweep.SweepHandler").actionHandlers[protocol.SWEEP](1,
                { stageId = stage, teamIdx = 2, count = count })
            local rb = b.require("rules.dungeon.DungeonHandler").actionHandlers[protocol.DUNGEON_SWEEP](1,
                { dungeonId = id, floor = 1, teamIdx = 2, times = count })
            check(ra.success and rb.success, "两个资源协议都成功 " .. id)
            eq(a.data.currency.sweepTicket, 30 - count, "新协议成本等于场数")
            eq(b.data.currency.sweepTicket, 30 - count, "旧资源协议成本等于场数")
            eq(rb.dungeonId, id, "旧协议保留副本身份")
            eq(rb.sweepFloor, 1, "旧协议保留已通楼层")
            rb.dungeonId, rb.sweepFloor = nil, nil
            eq(ra.heroExpBatches, nil, "新协议不泄露内部经验批次")
            eq(rb.heroExpBatches, nil, "旧协议不泄露内部经验批次")
            same(ra, rb, "双协议全部奖励与完整装备内容相等")
            same(a.data, b.data, "双协议持久化候选完全相等")
            eq(a.data.dungeon[id].dailyUsed, 2, "新扫荡不再消费每日限次")
            eq(b.data.dungeon[id].idleAccumSec, 86437, "不扣挂机积累")
        end
    end
end

local function testProtocolValidation()
    for _, action in ipairs({ "SWEEP", "DUNGEON_SWEEP" }) do
        for _, field in ipairs({ "count", "teamIdx", "times" }) do
            run("协议nil-only默认 " .. action .. "/" .. field .. "=false", function()
                local h = F.new(); F.install(h, 0); h.forbidRNG = true
                local params = { stageId = 100001, dungeonId = "gold_mine", floor = 1, teamIdx = 1 }
                params[field] = false
                local at = h.require("shared.Protocol").ACTION_TYPES
                local handler = h.require(action == "SWEEP" and "rules.sweep.SweepHandler" or "rules.dungeon.DungeonHandler")
                local before = F.copy(h.data)
                local result = handler.actionHandlers[at[action]](1, params)
                eq(result.success, false, "非法false不得默认成1场/队1")
                same(h.data, before, "协议拒绝不改快照")
                eq(h.rngCalls + h.persists + h.notifications, 0, "协议拒绝零RNG/存档/通知")
            end)
        end
    end
    run("资源默认目标从稀疏账本回退真实已通6层", function()
        local h = F.new(); F.install(h, 0)
        h.data.dungeon.gold_mine = { floor = 11, cleared = { [6] = true } }
        h.data.battle.teamStageIds[1] = 100011
        eq(h.Rewards.resolveDefaultStage(h.data.battle, h.data.dungeon, 1), 100006,
            "不把旧floor-1=10当作新账本已通")
        local before = F.copy(h.data)
        local ok, err, result = h.Transaction.Sweep(1, "gold_mine", 1)
        check(ok, "旧资源协议默认目标也回退真实6层 " .. tostring(err))
        eq(result.stageId, 100006, "旧资源协议默认已通目标")
        same(h.data.battle, before.battle, "默认回退不改战线位置")
        same(h.data.dungeon, before.dungeon, "默认回退不补写跳过层")
    end)
    run("终焉999等价进度两个资源协议同门禁", function()
        local a, b = F.new(), F.new(); F.install(a, 0); F.install(b, 0)
        a.data.battle.maxStageId, b.data.battle.maxStageId = 999, 999
        local okA, errA, ra = a.Sweep.Sweep(1, 1, 1, 200001)
        local okB, errB, rb = b.Transaction.Sweep(1, "equipment_vault", 1, 1, 1)
        check(okA and okB, "终焉等价13-5已解锁装备副本 " .. tostring(errA) .. "/" .. tostring(errB))
        eq(ra.stageId, rb.stageId, "终焉资源两协议同目标")
        same(a.data, b.data, "终焉资源两协议同成本和完整奖励")
    end)
end

local function assertProgress(h, result, ids, expected, playerExpected, before)
    eq(#result.heroProgress, #ids, "成长回执仅包含有效槽位")
    for index, id in ipairs(ids) do
        local value = result.heroProgress[index]
        local hero = expected[id] or expected[tostring(id)]
        local prior = before.heroes.roster[id] or before.heroes.roster[tostring(id)]
        eq(value.heroId, id, "成长回执按Slots顺序，不按ID排序")
        for _, field in ipairs({ "level", "exp", "maxExp" }) do
            eq(value[field], hero[field], "预估/执行精确成长hero" .. id .. "/" .. field)
        end
        eq(value.beforeLevel, prior.level, "英雄原等级")
        eq(value.gain, hero.level - prior.level, "英雄提升包含共鸣")
        eq(value.capped, h.ET.isHeroMaxLevel(hero.level), "英雄满级标记")
    end
    for _, field in ipairs({ "level", "exp", "maxExp" }) do
        eq(result.playerProgress[field], playerExpected[field], "玩家精确成长/" .. field)
    end
    eq(result.playerProgress.beforeLevel, before.player.level, "玩家原等级")
    eq(result.playerProgress.gain, playerExpected.level - before.player.level, "玩家提升等级数")
    eq(result.playerProgress.capped, h.ET.isPlayerMaxLevel(playerExpected.level), "玩家满级标记")
    eq(result.heroExpBatch, nil, "压缩经验批次不得泄露回执")
    eq(result.heroExpBatches, nil, "不得重建展开经验数组")
end

-- 独立慢速oracle直接复播旧Sweep顺序，不经过新的共用成长入口。
local function growthOracle(h, ids, stage, count)
    local expected, player = F.copy(h.data.heroes.roster), F.copy(h.data.player)
    local entry = assert(h.SC.getStage(stage))
    local resource = h.SC.isResourceStage(stage)
    local baseExp = 0
    if resource then baseExp = h.DC.getStageExpAmount(stage, 1)
    else
        for _, enemy in ipairs(h.Spawn.generateEnemyList(entry, false)) do baseExp = baseExp + enemy.expReward end
    end
    local mult = h.ET.getHeroCountExpMult(#ids)
    local amount = resource and math.floor(math.floor(baseExp * mult + 0.5) / #ids + 0.5)
        or math.floor(baseExp * mult / #ids + 0.5)
    local batches = count * (resource and entry.idleCount or 1)
    local resonance = h.require("shared.heroes.HeroResonance")
    -- 大批高等级对照仅在地板已同步且所有入账都不可能升级时走独立解析oracle，
    -- 不重复数百万次TOP5排序；升级/共鸣场景下面仍完整复播旧逐批路径。
    local stable = true
    local floor = resonance.computeResonanceLevel(expected)
    for _, hero in pairs(expected) do
        if hero.level < floor then stable = false end
    end
    for _, id in ipairs(ids) do
        local hero = expected[id] or expected[tostring(id)]
        local needed = h.ET.getHeroExpForLevel(hero.level)
        if not needed or (hero.exp or 0) + amount * batches >= needed then stable = false end
    end
    if stable then
        for _, id in ipairs(ids) do
            local hero = expected[id] or expected[tostring(id)]
            hero.exp = (hero.exp or 0) + amount * batches
            hero.maxExp = h.ET.getHeroExpForLevel(hero.level)
        end
    else
        for _ = 1, batches do
            for _, id in ipairs(ids) do
                local hero = expected[id] or expected[tostring(id)]
                hero.exp = (hero.exp or 0) + amount
                h.ET.autoLevelUpHero(hero)
                resonance.syncRosterToResonance(expected)
            end
        end
    end
    player.exp = (player.exp or 0) + baseExp * batches
    h.ET.autoLevelUpPlayer(player)
    return expected, player
end

-- 正式CharacterProgress.addHeroesExp作为顺序oracle：逐英雄升级后共鸣；资源每杀、主线每场。
local function testExpOrder()
    for _, stage in ipairs({ 101, 100001, 200001, 300001 }) do
        for _, count in ipairs({ 1, 3 }) do
            run("经验升级共鸣顺序 " .. stage .. "/" .. count .. "场", function()
                local h = F.new(); F.install(h, 0); h.forceRandom = 0.999999
                h.data.heroes.roster = {}
                for id = 1, 6 do h.data.heroes.roster[id] = { level = id <= 2 and 1 or 2, exp = id <= 2 and 19 or 0 } end
                h.data.heroes.teams = { { slots = { 1, 2, 0, 0 } }, { slots = {} }, { slots = {} } }
                h.data.heroes.deployed = { 1, 2, 0, 0 }
                h.data.battle.clearedStages[101] = true
                h.data.player = { level = 1, exp = 19 }
                local expected = F.copy(h.data.heroes.roster)
                local playerExpected = F.copy(h.data.player)
                local resonance = h.require("shared.heroes.HeroResonance")
                local noop = function() end
                local progress = h.require("ui.character.panel.CharacterProgress").bind({
                    ExpTable = h.ET, get = function(key) return key == "ownedSet" and expected or nil end,
                    applyResonanceSync = function() resonance.syncRosterToResonance(expected) end,
                    syncTeamSlotsFromOwned = noop, syncRosterExpFromOwned = noop,
                    rebuildRoster = noop, refreshPowerCache = noop, refreshNavBadge = noop,
                })
                local one = assert(preview(h, 1, stage, 1))
                local entry = assert(h.SC.getStage(stage))
                local isResource = h.SC.isResourceStage(stage)
                local exp = isResource and h.DC.getStageExpAmount(stage, 1) or one.playerExp
                local heroExp = isResource and math.floor(math.floor(exp * h.ET.getHeroCountExpMult(2) + 0.5) / 2 + 0.5)
                    or one.heroExp
                for _ = 1, count do
                    for _ = 1, isResource and entry.idleCount or 1 do
                        eq(progress.addHeroesExp({ 1, 2 }, heroExp), true, "正式顺序oracle有效入账")
                        playerExpected.exp = playerExpected.exp + exp
                        h.ET.autoLevelUpPlayer(playerExpected)
                    end
                end
                if stage == 101 and count == 1 then
                    eq(heroExp, 8, "明确共鸣反例每人8经验")
                    eq(expected[2].level, 2, "hero1升级触发hero2共鸣")
                    eq(expected[2].exp, 8, "hero2共鸣归零后再入账，应8而非7")
                end
                local before = F.copy(h.data)
                local estimated = assert(preview(h, 1, stage, count))
                assertProgress(h, estimated, { 1, 2 }, expected, playerExpected, before)
                same(h.data, before, "顺序预估不改输入")
                local ok, err, receipt = h.Sweep.Sweep(1, count, 1, stage)
                check(ok, "顺序扫荡成功 " .. tostring(err))
                assertProgress(h, receipt, { 1, 2 }, expected, playerExpected, before)
                for id = 1, 6 do
                    for _, field in ipairs({ "level", "exp", "maxExp" }) do
                        eq(h.data.heroes.roster[id][field], expected[id][field], "正式逐英雄/逐杀/逐场oracle hero" .. id .. "/" .. field)
                    end
                end
                same(h.data.player, playerExpected, "玩家升级遵守逐杀/逐场顺序")
            end)
        end
    end
end

local function configureGrowth(h, kind)
    local ids = { 4, 1, 3, 2 } -- 非ID顺序，四人队倍率必须为2.5。
    h.data.heroes.teams = { { slots = ids }, { slots = {} }, { slots = {} } }
    h.data.heroes.deployed = F.copy(ids)
    h.data.heroes.roster = {}
    for id = 1, 8 do
        local level = kind == "capped" and 200 or kind == "cap-boundary" and 199
            or kind == "stable" and 100 or 2
        if kind == "resonance" and id <= 4 then level = 1 end
        h.data.heroes.roster[id] = { level = level,
            exp = kind == "capped" and 777 or kind == "cap-boundary" and h.ET.hero[199] - 1
                or kind == "resonance" and id <= 4 and 19 or 0,
            maxExp = -1, extra = { untouched = id } }
    end
    if kind == "resonance" then
        -- 四个高等级旁队/候补：第一名出战升级就能抬TOP5地板并清掉后续英雄经验。
        for id = 5, 8 do h.data.heroes.roster[id].level = 2 end
    elseif kind == "cap-boundary" then
        for id = 5, 8 do
            h.data.heroes.roster[id].level = 200
            h.data.heroes.roster[id].exp, h.data.heroes.roster[id].maxExp = 0, 0
        end
    end
    h.data.player = { level = kind == "capped" and 200 or kind == "cap-boundary" and 199
        or kind == "stable" and 100 or 1,
        exp = kind == "capped" and 999 or kind == "cap-boundary" and h.ET.player[199] - 1 or 99,
        maxExp = -1, untouched = true }
    h.data.battle.clearedStages[101] = true
    return ids
end

local function testGrowthPreview()
    for _, kind in ipairs({ "resonance", "multilevel", "capped", "cap-boundary" }) do
        for _, stage in ipairs({ 101, 6705, 100001, 200001, 300001 }) do
            run("四人精确成长 " .. kind .. "/" .. stage, function()
                local h = F.new(); F.install(h, 0)
                local ids = configureGrowth(h, kind)
                h.forceRandom = 0.999999
                local count = kind == "multilevel" and (stage == 101 and 130 or 30) or 3
                h.data.currency.sweepTicket = math.max(h.data.currency.sweepTicket, count)
                local expected, playerExpected = growthOracle(h, ids, stage, count)
                local before = F.copy(h.data)
                h.forbidRNG = true
                local estimate = assert(preview(h, 1, stage, count))
                assertProgress(h, estimate, ids, expected, playerExpected, before)
                same(h.data, before, "四人成长预估纯读")
                h.forbidRNG = false
                local ok, err, result = h.Sweep.Sweep(1, count, 1, stage)
                check(ok, "四人真实交易 " .. tostring(err))
                assertProgress(h, result, ids, expected, playerExpected, before)
                same(result.heroProgress, estimate.heroProgress, "四人成长预估严格等于执行")
                same(result.playerProgress, estimate.playerProgress, "玩家成长预估严格等于执行")
                same(h.data.heroes.roster, expected, "全名册共鸣/附加字段精确")
                same(h.data.player, playerExpected, "玩家附加字段不变")
                if kind == "multilevel" then check(result.playerProgress.gain > 1, "真实多级成长夹具") end
                if kind == "capped" or kind == "cap-boundary" then
                    for _, value in ipairs(result.heroProgress) do
                        eq(value.exp, 0, "满级/到达满级后经验全部清零")
                        eq(value.maxExp, 0, "满级maxExp=0")
                    end
                end
            end)
        end
    end
    run("可选player不改变旧参数位置/字符串槽位纯读", function()
        local h = F.new(); F.install(h, 0)
        local ids = configureGrowth(h, "resonance")
        for id, hero in pairs(F.copy(h.data.heroes.roster)) do
            h.data.heroes.roster[tostring(id)], h.data.heroes.roster[id] = hero, nil
        end
        h.data.heroes.teams[1].slots = { "4", "1", "3", "2" }
        local before = F.copy(h.data)
        local d = h.data
        local old = assert(h.Sweep.Preview(d.heroes, d.battle, d.dungeon, d.equipment,
            d.artifacts, d.talents, 1, 101, 3))
        eq(old.playerProgress, nil, "缺省player不虚构Lv1成长")
        local expected, playerExpected = growthOracle(h, ids, 101, 3)
        local current = assert(preview(h, 1, 101, 3))
        assertProgress(h, current, ids, expected, playerExpected, before)
        same(current.heroProgress, old.heroProgress, "player可选不影响英雄共鸣")
        same(h.data, before, "字符串槽位与所有输入表不变")
        -- 修改返回值也不能污染源数据或后续预估。
        current.heroProgress[1].exp, current.playerProgress.exp = -999, -999
        same(assert(preview(h, 1, 101, 3)).heroProgress, old.heroProgress, "预估返回值无共享可变引用")
        same(h.data, before, "返回值修改不改输入")
    end)
end

local function testLargeSweep()
    for _, stage in ipairs({ 101, 100001 }) do
        run("45000券一次执行/恒定经验空间 " .. stage, function()
            local h = F.new(); F.install(h, 0)
            local ids = configureGrowth(h, stage == 101 and "resonance" or "stable")
            h.data.currency.sweepTicket = 45000
            local expected, playerExpected = growthOracle(h, ids, stage, 45000)
            local before = F.copy(h.data)
            local entry = assert(h.SC.getStage(stage))
            local raw = h.Rewards.calculate(entry, 4, 45000, false, 0, 1)
            eq(raw.heroExpBatches, nil, "45000场不创建展开数组")
            eq(raw.heroExpBatch.count, h.SC.isResourceStage(stage) and entry.idleCount * 45000 or 45000,
                "压缩批数仍为原每杀/每场")
            local calls, floors = 0, 0
            local originalLevel, originalFloor = h.ET.autoLevelUpHero, h.env.math.floor
            h.ET.autoLevelUpHero = function(...)
                calls = calls + 1; check(calls < 1000, "45000场成长不遍历每个不升级批次")
                return originalLevel(...)
            end
            h.env.math.floor = function(...)
                floors = floors + 1; check(floors < 2000, "Preview复杂度不能随count*kills增长")
                return originalFloor(...)
            end
            h.forbidRNG = true
            local estimate = assert(preview(h, 1, stage, 45000))
            assertProgress(h, estimate, ids, expected, playerExpected, before)
            same(h.data, before, "45000场预估不改输入")
            h.env.math.floor = originalFloor
            h.forbidRNG, h.forceRandom = false, 0.999999
            local rolls, originalRoll = 0, h.SC.isResourceStage(stage) and h.DC.getStageRewards or h.Drop.rollKillDrop
            local function counted(...)
                rolls = rolls + 1
                return originalRoll(...)
            end
            if h.SC.isResourceStage(stage) then h.DC.getStageRewards = counted else h.Drop.rollKillDrop = counted end
            calls = 0
            local ok, err, result = h.Sweep.Sweep(1, "45000", 1, stage)
            check(ok, "45000券合法一次执行 " .. tostring(err))
            eq(h.data.currency.sweepTicket, 0, "45000券一次扣完")
            eq(h.persists, 1, "45000场同一原子交易只持久化一次")
            eq(rolls, entry.idleCount * 45000, "随机掉落仍每杀一次原接口")
            assertProgress(h, result, ids, expected, playerExpected, before)
            same(result.heroProgress, estimate.heroProgress, "45000场预估与实际成长一致")
            same(h.data.heroes.roster, expected, "45000场全名册精确等于慢速oracle")
        end)
    end
    run("大批存档失败/成长和45000券原位回滚", function()
        local h = F.new(); F.install(h, 0)
        configureGrowth(h, "resonance")
        h.data.currency.sweepTicket = 45000
        h.forceRandom, h.failure = 0.999999, "false"
        assertRollback(h, function() return h.Sweep.Sweep(1, 45000, 1, 101) end, "45000场落盘失败")
    end)
    run("券余额决定上界/低券不足拒绝零RNG", function()
        for _, owned in ipairs({ 0, 1, 2, 11, 45000 }) do
            local h = F.new(); F.install(h, 0)
            h.data.currency.sweepTicket, h.forbidRNG = owned, true
            local before = F.copy(h.data)
            local ok, err = h.Sweep.Sweep(1, owned + 1, 1, 1905)
            eq(ok, false, "请求不得超过实际券余额")
            eq(err, "扫荡券不足", "合法正整数不足券不是无效次数")
            same(h.data, before, "不足券原模块不改")
            eq(h.rngCalls + h.persists + h.notifications, 0, "不足券零随机/落盘/通知")
            if owned > 0 and owned <= 11 then
                h.forbidRNG, h.forceRandom = false, 0.999999
                eq(h.Sweep.Sweep(1, owned, 1, 1905), true, "实际拥有11券不再受10上限")
                eq(h.data.currency.sweepTicket, 0, "低券刚好可用余额全部扣除")
            end
        end
        local h = F.new(); F.install(h, 0)
        h.data.currency.sweepTicket, h.forceRandom = 2.9, 0.999999
        local ok, err, receipt = h.Sweep.Sweep(1, 2, 1, 1905)
        check(ok, "旧档小数券余额合法交易后日志不抛错 " .. tostring(err))
        eq(receipt.ticketLeft, 2.9 - 2, "旧档小数券余额不截断")
        eq(h.data.currency.sweepTicket, 2.9 - 2, "实际扣券只减请求整场成本")
        eq(h.persists, 1, "小数旧券交易持久化一次后正常返回")
    end)
end

local function testRandomReplay()
    for _, stage in ipairs({ 1905, 200001 }) do
        run("11场逐杀RNG/完整装备原序复播 " .. stage, function()
            local h, oracle = F.new(), F.new(); F.install(h, 199); F.install(oracle, 199)
            local entry = assert(h.SC.getStage(stage))
            local count, expectedEquips, scrolls = 11, {}, {}
            local gold, diamond = 0, 0
            for _ = 1, entry.idleCount * count do
                if h.SC.isResourceStage(stage) then
                    local value = oracle.DC.getStageRewards(stage, 1, 2)
                    gold, diamond = gold + value.gold, diamond + value.diamond
                    for field, amount in pairs(value.scrollDrops) do
                        if field ~= "sweepTicket" then scrolls[field] = (scrolls[field] or 0) + amount end
                    end
                    for _, seed in ipairs(value.equipSeeds) do
                        expectedEquips[#expectedEquips + 1] = assert(oracle.ES.generateRandom(seed.level, seed.quality))
                    end
                else
                    local quality = oracle.Drop.rollKillDrop(entry, { teamIdx = 2, dropLuck = 0 })
                    if quality then expectedEquips[#expectedEquips + 1] = assert(oracle.ES.generateRandom(entry.monsterLevel, quality)) end
                    local scroll = oracle.Drop.rollScrollDrop(entry)
                    if scroll then scrolls[scroll] = (scrolls[scroll] or 0) + 1 end
                end
            end
            local ok, err, result = h.Sweep.Sweep(1, count, 2, stage)
            check(ok, "11场逐杀RNG执行 " .. tostring(err))
            eq(h.seed, oracle.seed, "每杀RNG终态相同，不少骰/多骰/改序")
            eq(h.rngCalls, oracle.rngCalls, "随机消费次数严格相同")
            eq(#result.equips, #expectedEquips, "原逐杀接口全装备数相同")
            check(#expectedEquips > 1, "夹具覆盖背包满后入遗匣")
            for index, equip in ipairs(expectedEquips) do
                equip.seq = result.equips[index].equip.seq
                same(result.equips[index].equip, equip, "完整装备内容和顺序相同")
            end
            same(result.scrollDrops, scrolls, "原卷轴掉落完全一致/不返券")
            if h.SC.isResourceStage(stage) then eq(result.gold, gold, "资源原金币"); eq(result.diamond, diamond, "资源原黑晶") end
            eq(h.data.currency.sweepTicket, 19, "仍按一券一场扣11券")
        end)
    end
end

local function testFullBag()
    for _, initial in ipairs({ 0, 199, 200, 201 }) do
        for _, stage in ipairs({ 1905, 200001 }) do
            local h = F.new(); F.install(h, initial); h.forceRandom = 0
            local generated = {}
            local original = h.ES.generateRandom
            h.ES.generateRandom = function(level, quality)
                local equip = assert(original(level, quality))
                equip.locked, equip.ascendLevel, equip.refineCount = true, 12, 3
                equip.testNested = { original = { #generated + 1, level, quality } }
                generated[#generated + 1] = { equip = equip, snapshot = F.copy(equip) }
                return equip
            end
            local ok, err, result = h.Sweep.Sweep(1, 1, 1, stage)
            check(ok, "满包真实扫荡成功 " .. tostring(err))
            check(#generated > 0, "强制命中确实生成装备")
            local direct = math.min(#generated, math.max(0, 200 - initial))
            eq(result.equipCount, #generated, "报告总数包含所有遗匣装备")
            eq(result.inventoryCount, direct, "按实际容量入包")
            eq(result.lootboxCount, #generated - direct, "全部溢出保管")
            eq(h.ES.getInventoryCount(h.data.equipment), initial + direct, "背包不可扩容")
            eq(#h.data.lootbox.seeds, #generated - direct, "遗匣件数完整守恒")
            local totalQuality = 0
            for _, amount in pairs(result.equipByQuality) do totalQuality = totalQuality + amount end
            eq(totalQuality, #generated, "品质统计覆盖匣内装备")
            for index, entry in ipairs(generated) do
                local receipt = result.equips[index]
                eq(receipt.equip, entry.equip, "回执复用真实装备实例")
                local expected = F.copy(entry.snapshot); expected.seq = entry.equip.seq
                same(entry.equip, expected, "高级字段/所有词条/嵌套状态不丢失")
                eq(receipt.destination, index <= direct and "inventory" or "lootbox", "每件准确去向")
                if index > direct then eq(h.data.lootbox.seeds[index - direct].equip, entry.equip, "原完整实例入匣") end
            end
            h.ES.generateRandom = function() error("领取/恢复不允许重骰") end
            if direct < #generated then
                local items, full = h.LS.claimAll(h.data.lootbox, h.data.equipment)
                eq(#items, 0, "满包领取不吞装备")
                eq(full, true, "满包提示")
                h.ES.removeFromInventory(h.data.equipment, 1)
                if initial > 200 then h.ES.removeFromInventory(h.data.equipment, 2) end
                local claimed = h.LS.claimAll(h.data.lootbox, h.data.equipment)
                eq(#claimed, 1, "腾出一格只领原实例")
            end
        end
    end
end

local function testRollback()
    for _, stage in ipairs({ 1905, 200001 }) do
        for _, failure in ipairs({ "generation-nil", "generation-throw", "delivery", "false", "nil", "throw", "onLoad" }) do
            run("原位回滚 " .. stage .. "/" .. failure, function()
                local h = F.new(); F.install(h, 199); h.forceRandom = 0
                local originalGenerate, originalDeliver = h.ES.generateRandom, h.LS.deliverEquipment
                local generated, delivered = 0, 0
                if failure:match("^generation") then
                    h.ES.generateRandom = function(...)
                        generated = generated + 1
                        if generated == 3 then
                            if failure == "generation-nil" then return nil end
                            error("expected third generation exception")
                        end
                        return originalGenerate(...)
                    end
                elseif failure == "delivery" then
                    h.LS.deliverEquipment = function(...)
                        delivered = delivered + 1
                        local destination = originalDeliver(...)
                        if delivered == 3 then error("expected partial delivery exception") end
                        return destination
                    end
                elseif failure == "onLoad" then
                    h.onLoad = function(name, data)
                        if name == "currency" then data.gold = -999; error("expected onLoad exception") end
                    end
                else
                    h.failure = failure
                    h.beforePersist = function()
                        -- 模拟双onLoad/Flush替换子表并更改session；旧外部别名也必须恢复。
                        h.data.equipment.inventory = {}
                        h.data.heroes.roster = {}
                        h.data.session.claimedScenarios = { injected = true }
                        h.data.session.lastOnlineTime = 999
                    end
                end
                assertRollback(h, function() return h.Sweep.Sweep(1, 1, 2, stage) end, failure)
                if failure:match("^generation") then eq(generated, 3, "真实生成中途失败"); eq(h.persists, 0, "未生成完整不可落盘") end
                if failure == "delivery" then eq(delivered, 3, "实际第三件交付后失败"); eq(h.persists, 0, "未交付完整不可落盘") end
                h.ES.generateRandom, h.LS.deliverEquipment = originalGenerate, originalDeliver
                h.failure, h.onLoad, h.beforePersist = "", nil, nil
                local ok, err = h.Sweep.Sweep(1, 1, 2, stage)
                check(ok, "失败释放事务锁后原请求可重试 " .. tostring(err))
                eq(h.data.currency.sweepTicket, 29, "重试只扣成功一次")
            end)
        end
    end
    run("未接持久化fail-closed", function()
        local h = F.new(); F.install(h, 0); h.forbidRNG = true
        h.Transaction.SetPersistCallback(nil)
        assertRollback(h, function() return h.Sweep.Sweep(1, 1, 1, 1905) end, "无持久化")
        eq(h.rngCalls, 0, "无接线不消费掉落RNG")
    end)
    run("满包缺遗匣原位拒绝", function()
        local h = F.new(); F.install(h, 200); h.forceRandom = 0; h.data.lootbox = nil
        assertRollback(h, function() return h.Sweep.Sweep(1, 1, 1, 1905) end, "缺遗匣")
        eq(h.persists, 0, "缺安全容器不保存")
    end)
end

local function testMoreTickets()
    local h = F.new(); F.install(h, 0); h.forbidRNG = true
    near(h.Drop.getSweepTicketRate(0), 0.12, "券更多最低12%")
    near(h.Drop.getSweepTicketRate(0.05), 0.20, "常规掉率20%=卷轴四倍")
    near(h.Drop.getSweepTicketRate(0.2), 0.40, "券掉率最高40%")
    for _, floor in ipairs({ 1, 20, 60, 109 }) do
        local scroll, ticket = h.DC.getEquipDropRates(floor)
        near(ticket, h.Drop.getSweepTicketRate(scroll), "资源券与主线共用统一掉率")
    end
    eq(h.rngCalls, 0, "掉率只读查询零RNG")
    h.forbidRNG = false
    local stage = assert(h.SC.getStage(1905))
    local rate = h.Drop.getSweepTicketRate(stage.scrollDropRate)
    h.forceRandom = rate - 0.000001; eq(h.Drop.rollSweepTicket(stage), true, "券阈值内命中")
    h.forceRandom = rate + 0.000001; eq(h.Drop.rollSweepTicket(stage), false, "券阈值外不命中")
end

function Start()
    assertions, cases, passed, failures = 0, 0, 0, {}
    local requireBefore, randomBefore = require, math.random
    local loadedBefore = {}; for key, value in pairs(package.loaded) do loadedBefore[key] = value end
    run("准确单场怪物奖励/60级以上/无首通大奖", testMainBattle)
    run("三资源逐杀取整及逐杀oracle", testResourceRounding)
    run("Preview零RNG/零PDM/不改快照", testPreviewPurity)
    testGuards()
    run("两资源协议同成本同奖励/不扣日次和挂机", testProtocolParity)
    testProtocolValidation()
    testExpOrder()
    testGrowthPreview()
    testLargeSweep()
    testRandomReplay()
    run("满包完整入遗匣/领取不重骰", testFullBag)
    testRollback()
    run("券更多统一掉率", testMoreTickets)
    run("隔离不污染全局require/math/package", function()
        eq(require, requireBefore, "全局require不变")
        eq(math.random, randomBefore, "全局RNG不变")
        for key, value in pairs(loadedBefore) do eq(package.loaded[key], value, "原package模块不变 " .. key) end
        for key in pairs(package.loaded) do check(loadedBefore[key] ~= nil, "未泄露新package模块 " .. key) end
    end)
    print(TAG .. "SUMMARY cases=" .. cases .. " passed=" .. passed .. " failed=" .. #failures .. " assertions=" .. assertions)
    engine:Exit() -- 失败也退出Runtime；调用者仍必须检查SUMMARY和ALL PASS，而非仅exit0。
    if #failures > 0 then error(TAG .. table.concat(failures, "\n")) end
    print(TAG .. "ALL PASS")
end
