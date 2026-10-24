-- 批量扫荡：读取 SweepRegressionFixture 私有加载的真实生产源码；不启动main/Boot。
-- 仅此新测试；统一源码loader由调用者提供。File/fileSystem沿夹具封闭，不读玩家档。
-- 概率组只stub私有ES.generateRandom为品质记录对象，不代表完整装备/持久化验收；
-- 完整ES另覆盖小样本原始引用/顺序/有限仓位，以及主线/装备副本各100000场。
-- 固定8种子；统计拒绝阈值预先给定，不按结果放宽，不比较旧逐杀同seed序列。
local F = require("tests.SweepRegressionFixture")
local TAG = "[sweep_batch_rewards_test] "
local SCROLLS = { "weaponScroll", "offhandScroll", "armorScroll", "helmetScroll", "shoesScroll", "accessoryScroll" }
local SEEDS = { 17, 104729, 130363, 32452843, 49979687, 67867967, 86028121, 104395301 }
local checks, cases, statisticalBatches, stubObjects, realObjects = 0, 0, 0, 0, 0

local function check(value, message)
    checks = checks + 1
    assert(value, TAG .. message)
end
local function eq(actual, expected, message)
    check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function same(actual, expected, message)
    check(F.equal(actual, expected), message)
end
local function near(actual, expected, tolerance, message)
    check(math.abs(actual - expected) <= tolerance,
        string.format("%s actual=%.12g expected=%.12g tolerance=%.12g", message, actual, expected, tolerance))
end
local function run(name, callback)
    local before = os.clock()
    callback() -- 不吞任何断言；最外层仅保证Exit后原样重抛。
    cases = cases + 1
    print(TAG .. "PASS " .. name .. string.format(" cpu=%.6f", os.clock() - before))
end
local function fixture(seed, install)
    local h = F.new()
    if install then F.install(h, 0) end
    h.env.math.randomseed(seed or 17) -- 只重置夹具私有math，绝不重置宿主RNG。
    h.Drop.rollKillDrop = function() error("批量算法不得逐杀rollKillDrop") end
    h.Drop.generateKillDrop = function() error("批量算法不得逐杀generateKillDrop") end
    h.Drop.rollScrollDrop = function() error("批量算法不得逐杀rollScrollDrop") end
    h.Drop.rollSweepTicket = function() error("扫荡不得抽券") end
    h.DC.getStageRewards = function() error("批量算法不得逐杀getStageRewards") end
    h.DC.createStageRewardsContext = function() error("批量算法不得逐杀奖励上下文") end
    return h
end
local function entry(h, id, fields)
    local source = assert(h.SC.getStage(id), "缺少关卡 " .. id)
    local value = F.copy(source)
    for key, child in pairs(fields or {}) do value[key] = child end
    return value
end
local function calculate(h, value, count, luck, control, roll)
    return h.Rewards.calculate(value, 3, count or 1, roll ~= false, luck or 0, 2, control)
end
local function noTickets(result)
    eq(result.ticketDrop, 0, "ticketDrop恒0")
    eq(result.scrollDrops.sweepTicket, nil, "卷轴中不夹扫荡券")
    eq(result.sweepTicket, nil, "不添加其他券字段")
end
local function conserved(result)
    if result.batchQualities then
        -- 聚合路径不物化装备；件数守恒由抽样序列承担。
        eq(result.equipCount, #result.batchQualities, "聚合装备件数守恒")
    else
        eq(result.equipCount, #result.equips, "实际装备件数守恒")
    end
    local sum = 0
    for key, value in pairs(result.scrollDrops) do
        local known = false
        for _, scroll in ipairs(SCROLLS) do if scroll == key then known = true end end
        check(known, "只允许六类卷轴 " .. tostring(key))
        check(value >= 0 and value == math.floor(value), "实际卷轴是非负整数")
        sum = sum + value
    end
    eq(result.scrollCount, sum, "六类卷轴总数守恒")
    noTickets(result)
end
local function qualityStub(h)
    local records = { count = 0, quality = { 0, 0, 0, 0, 0, 0 } }
    h.ES.generateRandom = function(level, quality)
        records.count = records.count + 1
        records.quality[quality] = records.quality[quality] + 1
        stubObjects = stubObjects + 1
        return { level = level, quality = quality, fakeBatchQualityRecord = true }
    end
    return records
end

--- 大批掉落改为只保留品质序列；统计口径与逐件生成完全一致。
---@param result table
---@return integer[]|nil
local function batchQualities(result)
    if not result.batchQualities then return nil end
    local counted = {}
    for _, quality in ipairs(result.batchQualities) do counted[quality] = (counted[quality] or 0) + 1 end
    return counted, #result.batchQualities
end
local function realRecorder(h)
    local original = h.ES.generateRandom
    local records = {}
    h.ES.generateRandom = function(level, quality)
        local equip = assert(original(level, quality), "真实ES生成失败")
        records[#records + 1] = equip
        realObjects = realObjects + 1
        return equip
    end
    return records
end

-- 独立品质oracle：直接读MC权重/实际怪池；不借待测Drop概率函数计算期望。
local function expectedQuality(h, value, luck)
    local mc = h.require("config.MonsterConfig")
    local pool = F.copy(value.monsters)
    if (value.bossId or 0) > 0 then pool[#pool + 1] = value.bossId end
    local diff = h.SC.getDifficulty(value.id)
    local high = diff ~= "normal" and diff ~= "hard" and diff ~= "nightmare"
    local cap = diff == "normal" and 4 or diff == "hard" and 5 or 6
    local raw = { 0, 0, 0, 0, 0, 0 }
    for _, id in ipairs(pool) do
        local weights, total = {}, 0
        for q = 1, 6 do
            local w = mc.QUALITY[mc.MONSTERS[id].quality].dropWeights[q] or 0
            if high and q >= 5 then w = w * 3 end
            w = w * (1 + (q - 1) * luck / 500)
            weights[q], total = w, total + w
        end
        for q = 1, 6 do raw[math.min(q, cap)] = raw[math.min(q, cap)] + weights[q] / total / #pool end
    end
    local probabilities = F.copy(raw)
    if raw[6] < 0.0001 then
        local add = (0.0001 - raw[6]) / (1 - raw[6])
        for q = 1, 5 do probabilities[q] = raw[q] * (1 - add) end
        probabilities[6] = raw[6] + (1 - raw[6]) * add
    end
    return probabilities, cap
end

-- 多维原始矩，最终只统计汇总；不存所有批次或百万完整装备。
local function moments(dimension)
    local m = { count = 0, sum = {}, cross = {}, dimension = dimension }
    for i = 1, dimension do
        m.sum[i], m.cross[i] = 0, {}
        for j = 1, dimension do m.cross[i][j] = 0 end
    end
    return m
end
local function observe(m, vector)
    m.count = m.count + 1
    statisticalBatches = statisticalBatches + 1
    for i = 1, m.dimension do
        m.sum[i] = m.sum[i] + vector[i]
        for j = 1, m.dimension do m.cross[i][j] = m.cross[i][j] + vector[i] * vector[j] end
    end
end
local function covariance(m, i, j)
    return (m.cross[i][j] - m.sum[i] * m.sum[j] / m.count) / (m.count - 1)
end
local function binomialMoments(m, index, n, p, label)
    local mean, variance = n * p, n * p * (1 - p)
    near(m.sum[index] / m.count, mean, 7 * math.sqrt(variance / m.count) + 0.015, label .. "均值")
    -- 18%方差容差远宽于6144样本误差，仍拒绝常量期望/一次总和取整/泊松大p近似。
    near(covariance(m, index, index), variance, variance * 0.18 + 0.015, label .. "方差")
end
local function countFit(actual, trials, probability, label)
    near(actual, trials * probability, 6 * math.sqrt(trials * probability * (1 - probability)) + 3, label)
end

local function deterministicFormulas()
    for _, id in ipairs({ 1905, 2405, 4705, 7005, 32305 }) do
        for _, luck in ipairs({ 0, 200 }) do
            local h = fixture()
            local value = entry(h, id, { idleCount = 7, dropRate = 0.2, scrollDropRate = 0.3 })
            local calls, total, phaseCalls = 0, 0, 0
            local br = h.require("shared.sweep.BatchRandom")
            br.binomial = function(n, p, random, checkpoint)
                calls = calls + 1
                eq(random, nil, "批量接口第三参nil，私有math默认随机源")
                check(type(checkpoint) == "function", "采样必须传checkpoint第四参")
                checkpoint()
                if calls == 1 then eq(n, 35, "主线掉落试验数=idleCount*count"); near(p, luck == 0 and 0.2 or 0.6, 1e-14, "幸运命中率"); return 4 end
                if calls == 2 then eq(n, 35, "卷轴独立35次"); eq(p, 0.3, "卷轴不吃幸运"); return 9 end
                eq(n, 12 - calls, "条件二项使用剩余卷轴")
                eq(p, 1 / (9 - calls), "六类条件二项概率")
                return 1
            end
            local generated = qualityStub(h)
            local result = calculate(h, value, 5, luck, { checkpoint = function(phase, done, amount)
                eq(phase, "generate", "唯一生成阶段")
                if amount == 0 then eq(done, 0, "采样checkpoint只能0/0"); phaseCalls = phaseCalls + 1
                else eq(amount, 4, "装备进度total为实际生成数"); eq(done, total, "装备进度0至实际件数"); total = total + 1 end
            end })
            eq(calls, 7, "主线2个独立总数+5个条件拆类")
            eq(phaseCalls, 7, "采样进度不伪造杀数百分比")
            eq(total, 5, "生成进度含0起点和4件完成")
            eq(generated.count, 4, "只逐件生成实际命中数")
            eq(result.scrollDrops.accessoryScroll, 4, "第六类接收余数而非再抽")
            eq(result.kills, 35, "真实击杀数")
            conserved(result)
            local mc, gold, exp = h.require("config.MonsterConfig"), 0, 0
            local normals = 7 - ((value.bossId or 0) > 0 and 1 or 0)
            for i = 1, 7 do
                local monster = mc.MONSTERS[i <= normals and value.monsters[(i - 1) % #value.monsters + 1] or value.bossId]
                local q, level = mc.QUALITY[monster.quality], mc.LEVELS[value.monsterLevel]
                gold = gold + math.floor(level.goldDrop * q.goldMult + 0.5)
                exp = exp + math.floor(level.baseExp * q.expMult + 0.5)
            end
            eq(result.gold, gold * 5, "各普通怪及一个boss逐杀金币取整后乘场数")
            eq(result.playerExp, exp * 5, "经验不按首通大奖/品质平均替代")
            eq(result.heroExpBatch.count, 5, "主线经验压缩场数")
        end
    end
    -- raw*N=17恰好为整数，而8个Bernoulli(.125)可以给3，不得只取整17。
    for _, id in ipairs({ 100001, 200001, 300001 }) do
        local h, calls = fixture(), 0
        local value = entry(h, id, { idleCount = 4 })
        h.DC.getStageRewardAmount = function(stageId, kills) eq(stageId, id, "资源源ID"); eq(kills, 1, "仅查询每杀收益"); return 2.125 end
        h.DC.getEquipDropRates = function() return 1.25, 0.9 end
        h.require("shared.sweep.BatchRandom").binomial = function(n, p, random, checkpoint)
            calls = calls + 1
            eq(random, nil, "资源二项第三参nil")
            check(type(checkpoint) == "function", "资源采样checkpoint第四参")
            checkpoint()
            if calls == 1 then eq(n, 8, "资源每杀尾数试验数8"); eq(p, 0.125, "每杀raw小数而非总收益尾数"); return 3 end
            if calls == 2 then eq(n, 8, "资源卷轴每杀8次"); eq(p, 0.25, "资源卷轴floor+Bernoulli尾数"); return 2 end
            eq(n, 13 - calls, "资源条件拆类剩余数")
            eq(p, 1 / (9 - calls), "资源条件拆类概率")
            return 1
        end
        local generated = qualityStub(h)
        local result = calculate(h, value, 2, 200, { checkpoint = function(phase, done, amount)
            eq(phase, "generate", "资源阶段"); check(amount > 0 or done == 0, "采样0/0")
        end })
        if id == 100001 then eq(result.gold, 19, "金币=2*8+Bin(8,.125)，非round(2.125*8)")
        elseif id == 300001 then eq(result.diamond, 19, "黑晶每杀取整总和")
        else
            eq(result.equipCount, 19, "装备资源floor(raw)*N+二项尾数")
            eq(result.scrollCount, 10, "资源卷轴floor(rate)*N+独立尾数")
            eq(result.scrollDrops.accessoryScroll, 5, "卷轴六类余数")
        end
        eq(calls, id == 200001 and 7 or 1, "金币/黑晶只抽一次尾数，装备不抽券")
        eq(generated.count, id == 200001 and 19 or 0, "不为金币/黑晶生成装备")
        conserved(result)
        local perKill = h.DC.getStageExpAmount(id, 1)
        local perHero = math.floor(math.floor(perKill * h.ET.getHeroCountExpMult(3) + 0.5) / 3 + 0.5)
        eq(result.playerExp, perKill * 8, "资源每杀经验先取整")
        eq(result.heroExp, perHero * 8, "资源英雄经验双重取整再求和")
        eq(result.heroExpBatch.amount, perHero, "资源压缩经验amount")
        eq(result.heroExpBatch.count, 8, "资源压缩经验count按杀")
    end
end

local function previewPurity()
    local h = fixture(123, true)
    h.forbidRNG = true
    h.data.battle.maxStageId = 32305 -- 仅夹具：覆盖高难已通关及三资源解锁，不借玩家进度。
    h.ES.generateRandom = function() error("Preview禁止生成完整装备") end
    h.require("shared.sweep.BatchRandom").binomial = function() error("Preview禁止抽二项") end
    for _, id in ipairs({ 101, 1905, 2405, 4705, 7005, 100001, 200001, 300001 }) do
        h.data.battle.clearedStages[id] = true
        local value = entry(h, id)
        for _, luck in ipairs({ 0, 200 }) do
            local result = calculate(h, value, 100000, luck, nil, false)
            eq(#result.equips, 0, "预估不伪造装备实例")
            eq(result.heroExpBatches, nil, "预估不展开百万经验数组")
            noTickets(result)
            if not h.SC.isResourceStage(id) then
                eq(result.equipCount, value.idleCount * 100000 * math.min(1, value.dropRate * (1 + luck / 100)), "预估装备为期望")
                eq(result.scrollCount, value.idleCount * 100000 * value.scrollDropRate, "预估卷轴期望")
            end
        end
        local before = F.copy(h.data)
        local d = h.data
        local result, reason = h.Sweep.Preview(d.heroes, d.battle, d.dungeon, d.equipment,
            d.artifacts, d.talents, 1, id, 7, d.player)
        check(result ~= nil, "真实Service.Preview可用 " .. id .. " " .. tostring(reason))
        same(h.data, before, "Service.Preview所有输入不变")
    end
    eq(h.rngCalls, 0, "所有预估零RNG")
    eq(h.persists + h.notifications + h.events, 0, "预估零存档/通知")
end

local function boundaryAndPool()
    for _, id in ipairs({ 105, 2405, 4705, 7005 }) do
        for _, luck in ipairs({ 0, 200 }) do
            for _, rate in ipairs({ 0, 1 }) do
                local h = fixture(1905)
                local value = entry(h, id, { dropRate = rate, scrollDropRate = 0, idleCount = 10 })
                local generated = qualityStub(h)
                local result = calculate(h, value, 3, luck)
                eq(result.equipCount, rate * 30, "dropRate0/1退化精确")
                eq(generated.count, rate * 30, "零掉装不生成")
                conserved(result)
            end
        end
    end
    local h = fixture()
    local value = entry(h, 4705, { monsters = { 1, 10 }, bossId = 16 })
    local queries = 0
    local original = h.Drop.rollQualityByMonster
    h.Drop.rollQualityByMonster = function(quality, difficulty, luck, cap, red)
        queries = queries + 1
        eq(quality, ({ 1, 2, 5 })[queries], "普通怪及boss各占1个品质池位置")
        eq(difficulty, "nightmare", "真实难度")
        eq(luck, 200, "高幸运传到品质骰")
        eq(cap, 6, "噩梦cap6")
        check(red > 0.0001, "保留整池原红率")
        return quality
    end
    local poolIndex = 0
    h.env.math.random = function(lo, hi)
        eq(lo, 1, "品质池整数骰lo"); eq(hi, 3, "品质池含boss但不按击杀次数展开")
        poolIndex = poolIndex + 1
        return poolIndex
    end
    local rate, quality = h.Drop.createKillDropContext(value, { teamIdx = 2, dropLuck = 200 })
    near(rate, value.dropRate * 3, 1e-14, "上下文幸运掉率")
    eq(poolIndex, 0, "创建上下文零随机")
    for i = 1, 3 do eq(quality(), ({ 1, 2, 5 })[i], "池返回顺序") end
    eq(queries, 3, "逐件才骰品质")
    h.Drop.rollQualityByMonster = original
    -- 确定边界核cap及红尾，两骰=选怪+品质，不额外判定红装。
    for _, id in ipairs({ 105, 2405, 4705, 7005 }) do
        local b = fixture()
        local v = entry(b, id, { monsters = { 16 }, bossId = 0 })
        local expected, cap = expectedQuality(b, v, 0)
        local observed, bound = b.Drop.getStageQualityProbabilities(v, 0), cap
        for q = 1, 6 do near(observed[q], expected[q], 1e-12, "独立权重oracle " .. id .. "/" .. q) end
        for _, r in ipairs({ 0.5, 0.9999999 }) do
            b.forceRandom = r
            local _, choose = b.Drop.createKillDropContext(v, { teamIdx = 1, dropLuck = 0 })
            local start = b.rngCalls
            local q = choose()
            check(q <= bound or q == 6, "cap外只允许至臻例外")
            if r > 0.9999 then eq(q, 6, "尾骰命中至臻") end
            eq(b.rngCalls - start, 2, "品质池及品质各1骰")
        end
        if id == 105 then eq(observed[5], 0, "普通cap4不漏Q5"); near(observed[6], 0.0001, 1e-14, "普通红尾万分一") end
    end
end

local function trueEquipmentOrder()
    for _, id in ipairs({ 1905, 200001 }) do
        local h = fixture(32452843)
        local value = entry(h, id, { idleCount = 12, dropRate = 1, scrollDropRate = 0 })
        if id == 200001 then h.DC.getStageRewardAmount = function() return 1 end end
        local records = realRecorder(h)
        local result = calculate(h, value, 2)
        eq(#records, 24, "小组真实ES完整生成24件")
        for i, equip in ipairs(records) do
            eq(result.equips[i], equip, "返回生成器原始对象和顺序")
            check(type(equip.baseStats) == "table" and type(equip.affixes) == "table" and type(equip.templateId) == "string", "不是质量stub/种子替代")
            eq(equip.seq, nil, "计算阶段不提前分配库存seq")
        end
        conserved(result)
    end
    local h = fixture(67867967, true)
    -- 仅控制品质顺序；实际逐件ES生成/有限仓位交付均走真实代码。
    local sequence = { 3, 1, 6, 2, 5, 1, 4, 2 }
    h.Drop.createKillDropContext = function()
        local index = 0
        return 1, function() index = index + 1; return sequence[index] end
    end
    local records = realRecorder(h)
    local result = calculate(h, entry(h, 1905, { idleCount = 8, scrollDropRate = 0 }))
    for i, equip in ipairs(records) do eq(equip.quality, sequence[i], "生成顺序不按品质分组"); eq(result.equips[i], equip, "原始引用") end
    local bag, box = h.data.equipment, h.data.lootbox
    ---@cast bag table
    ---@cast box table
    local filler = assert(h.ES.generate("W1", 1, 1))
    for _ = 1, h.ES.MAX_INVENTORY - 1 do h.ES.addToInventory(bag, F.copy(filler)) end
    local nextSeq = bag.nextSeq
    local context = h.LS.createDeliveryContext(bag, { summaryLogs = true })
    for i, equip in ipairs(result.equips) do
        eq(h.LS.deliverEquipment(box, bag, equip, context), i == 1 and "inventory" or "lootbox", "有限空位按实际掉落原序接收")
    end
    eq(bag.inventory[tostring(nextSeq)], records[1], "唯一空位接收Q3原件，不优先低/高品质")
    for i = 2, #records do eq(box.seeds[i - 1].equip, records[i], "溢出完整原件保持原序") end
    eq(h.ES.getInventoryCount(bag), h.ES.MAX_INVENTORY, "实际库存容量守恒")
    eq(#box.seeds + 1, #records, "交付总件数守恒")
end

local function binomialSampling()
    local h = fixture()
    local br = h.require("shared.sweep.BatchRandom")
    for _, spec in ipairs({ { 200, 0.25 }, { 200, 0.75 }, { 1000, 0.001 }, { 1000000, 0.00001 }, { 1000000, 0.42 } }) do
        local m = moments(1)
        for _, seed in ipairs(SEEDS) do
            h.env.math.randomseed(seed)
            for _ = 1, 768 do
                local x = br.binomial(spec[1], spec[2], nil, nil)
                check(x >= 0 and x <= spec[1] and x == math.floor(x), "真二项合法整数")
                observe(m, { x })
            end
        end
        binomialMoments(m, 1, spec[1], spec[2], "真Bin(" .. spec[1] .. "," .. spec[2] .. ")")
    end
end

local function scrollStatistics()
    -- 固定120个总卷轴，多项类别负相关=-120/36；独立抽六个Bin(120,1/6)会被拒绝。
    local h = fixture()
    qualityStub(h)
    local value = entry(h, 1905, { idleCount = 120, dropRate = 0, scrollDropRate = 1 })
    local fixed = moments(6)
    for _, seed in ipairs(SEEDS) do
        h.env.math.randomseed(seed)
        for _ = 1, 768 do
            local result, vector = calculate(h, value), {}
            eq(result.scrollCount, 120, "固定卷轴总数严格120")
            for i, key in ipairs(SCROLLS) do vector[i] = result.scrollDrops[key] or 0 end
            observe(fixed, vector)
            conserved(result)
        end
    end
    for i = 1, 6 do
        binomialMoments(fixed, i, 120, 1 / 6, "固定总数六类" .. i)
        for j = i + 1, 6 do
            near(covariance(fixed, i, j), -120 / 36, 1.4, "固定总数15对负协方差" .. i .. "/" .. j)
            check(covariance(fixed, i, j) < 0, "多项类别实际负相关")
        end
    end
    -- 装备与卷轴各自Bin(120,.35)/Bin(120,.4)，允许同杀双中，不互斥不复用同一计数。
    local b = fixture()
    local generated = qualityStub(b)
    local v = entry(b, 1905, { idleCount = 120, dropRate = 0.35, scrollDropRate = 0.4 })
    local random = moments(8)
    for _, seed in ipairs(SEEDS) do
        b.env.math.randomseed(seed)
        for _ = 1, 768 do
            local result, vector = calculate(b, v), {}
            vector[1], vector[2] = result.equipCount, result.scrollCount
            for i, key in ipairs(SCROLLS) do vector[i + 2] = result.scrollDrops[key] or 0 end
            observe(random, vector)
            eq(result.equipCount, #result.equips, "概率stub按真实生成次数返回")
            noTickets(result)
        end
    end
    check(generated.count > 0, "独立性组确实生成质量记录stub")
    binomialMoments(random, 1, 120, 0.35, "装备独立命中")
    binomialMoments(random, 2, 120, 0.4, "卷轴总命中")
    local independentTolerance = 7 * math.sqrt((120 * 0.35 * 0.65) * (120 * 0.4 * 0.6) / random.count) + 0.05
    near(covariance(random, 1, 2), 0, independentTolerance, "equip/scroll总数独立协方差")
    for i = 3, 8 do
        binomialMoments(random, i, 120, 0.4 / 6, "随机总数卷轴边缘" .. i)
        near(covariance(random, 1, i), 0, 1.5, "装备与各类卷轴独立")
        for j = i + 1, 8 do
            near(covariance(random, i, j), -120 * (0.4 / 6) ^ 2, 0.48, "随机卷轴15对多项协方差")
        end
    end
end

local function qualityStatistics()
    for _, id in ipairs({ 105, 2405, 4705, 7005 }) do
        for _, luck in ipairs({ 0, 200 }) do
            local h = fixture()
            -- 普通怪Q1、Q2和bossQ5各占1槽；不按120击杀内boss数量加权。
            local value = entry(h, id, { monsters = { 1, 10 }, bossId = 16, idleCount = 24, dropRate = 1, scrollDropRate = 0 })
            local probabilities, cap = expectedQuality(h, value, luck)
            local generated = qualityStub(h)
            local expectedTrials = 0
            for _, seed in ipairs(SEEDS) do
                h.env.math.randomseed(seed)
                for _ = 1, 256 do
                    local result = calculate(h, value, 1, luck)
                    eq(result.equipCount, 24, "品质统计固定24件")
                    expectedTrials = expectedTrials + 24
                end
            end
            eq(generated.count, expectedTrials, "实际stub件数与全部品质计数一致")
            for q = 1, 6 do
                countFit(generated.quality[q], expectedTrials, probabilities[q], "多seed真实品质频数" .. id .. "/luck" .. luck .. "/Q" .. q)
                if q > cap and q ~= 6 then eq(generated.quality[q], 0, "品质cap绝对禁区") end
            end
        end
    end
    -- 专门480000次品质真采样，红尾期望48，6sigma+3容差约44.6，缺失红尾会失败。
    -- 超过聚合阈值时不再逐件生成装备；品质序列仍逐次抽样，统计口径不变。
    local h = fixture()
    local value = entry(h, 101, { monsters = { 1 }, bossId = 0, idleCount = 1000, dropRate = 1, scrollDropRate = 0 })
    local generated = qualityStub(h)
    local sampled = { 0, 0, 0, 0, 0, 0 }
    local sampledTotal = 0
    for _, seed in ipairs(SEEDS) do
        h.env.math.randomseed(seed)
        for _ = 1, 60 do
            local result = calculate(h, value)
            eq(result.equipCount, 1000, "红尾组实际1000品质抽样")
            local counts, total = batchQualities(result)
            check(counts ~= nil, "1000件超过阈值走聚合")
            eq(total, 1000, "聚合保留全部1000次品质抽样")
            for q = 1, 6 do sampled[q] = sampled[q] + (counts[q] or 0) end
            sampledTotal = sampledTotal + total
        end
    end
    eq(generated.count, 0, "聚合路径不逐件物化装备")
    eq(sampledTotal, 480000, "八种子红尾总样本数")
    countFit(sampled[6], 480000, 0.0001, "真采样红尾万分一")
    check(sampled[6] > 0, "多seed真实出现红尾")
    for q = 2, 5 do eq(sampled[q], 0, "纯普通池不凭空产生中间品质") end
end

local function resourceStatistics()
    -- 故意配置raw*N为整数；单次round(raw*N)的零方差必须被真实分布测试拒绝。
    for _, spec in ipairs({ { 100001, 2.25, 120 }, { 300001, 0.375, 120 }, { 200001, 1.25, 48 } }) do
        local h = fixture()
        local generated = qualityStub(h)
        h.DC.getStageRewardAmount = function() return spec[2] end
        h.DC.getEquipDropRates = function() return 0.4, 0.9 end
        local value = entry(h, spec[1], { idleCount = spec[3] })
        local m = moments(2)
        for _, seed in ipairs(SEEDS) do
            h.env.math.randomseed(seed)
            for _ = 1, 768 do
                local result = calculate(h, value)
                local amount = spec[1] == 100001 and result.gold or spec[1] == 300001 and result.diamond or result.equipCount
                observe(m, { amount - math.floor(spec[2]) * spec[3], result.scrollCount })
                conserved(result)
            end
        end
        binomialMoments(m, 1, spec[3], spec[2] - math.floor(spec[2]), "资源每杀尾数" .. spec[1])
        if spec[1] == 200001 then
            binomialMoments(m, 2, spec[3], 0.4, "资源独立卷轴")
            near(covariance(m, 1, 2), 0, 1.4, "资源装备尾数与卷轴独立")
            check(generated.count > 0, "资源概率组使用质量stub")
        else eq(generated.count, 0, "货币概率组不生成装备") end
    end
end

local function largeBatches()
    for _, id in ipairs({ 100001, 300001 }) do
        local h = fixture(32452843)
        h.ES.generateRandom = function() error("金币/黑晶禁止生成装备") end
        local value = entry(h, id)
        local checkpoints = 0
        local result = calculate(h, value, 100000, 200, { checkpoint = function(phase, done, total)
            eq(phase, "generate", "货币采样phase"); eq(done, 0, "货币sample0"); eq(total, 0, "货币sample total0")
            checkpoints = checkpoints + 1
            check(checkpoints < 10000, "货币检查点不能逐杀百万次")
        end })
        eq(result.kills, value.idleCount * 100000, "货币100k实际击杀")
        check(result.kills >= 1000000, "货币样本确为百万kill以上")
        check(h.rngCalls < 2048, "金币/黑晶100k只抽计数，不消耗百万RNG")
        check(checkpoints > 0, "货币采样仍可暂停")
        conserved(result)
        print(TAG .. "SCALE currency stage=" .. id .. " kills=" .. result.kills .. " rng=" .. h.rngCalls)
    end
    local empty = fixture(104729)
    empty.ES.generateRandom = function() error("零掉装不得逐杀调用generateRandom") end
    local zero = calculate(empty, entry(empty, 101, { idleCount = 10, dropRate = 0, scrollDropRate = 0 }), 100000)
    eq(zero.kills, 1000000, "百万kill零掉装")
    eq(zero.equipCount, 0, "零掉装无伪装备")
    eq(empty.rngCalls, 0, "退化二项零随机，不逐杀耗骰")
    conserved(zero)
    -- 以下两组验证大批量聚合：不再逐件物化，但品质序列完整、件数守恒。
    for _, id in ipairs({ 101, 200001 }) do
        local h = fixture(49979687)
        local value = entry(h, id)
        h.ES.generateRandom = function() error("大批量聚合路径不得逐件生成装备") end
        local generatedProgress, actualTotal = 0, -1
        local result = calculate(h, value, 100000, 0, { checkpoint = function(phase, done, total)
            eq(phase, "generate", "100k阶段")
            if total > 0 then
                if done == 0 then actualTotal = total
                else
                    check(done > generatedProgress and done <= total, "100k聚合进度单调不越界")
                    generatedProgress = done
                end
                eq(total, actualTotal, "装备total不随品质组重排")
            else eq(done, 0, "大批采样只0/0") end
        end })
        local counts, total = batchQualities(result)
        check(counts ~= nil, "100k自然掉落走聚合")
        eq(total, result.equipCount, "100k聚合件数=抽样数")
        eq(generatedProgress, result.equipCount, "完成进度等于实际抽样数")
        eq(#result.equips, 0, "聚合路径不返回逐件装备")
        eq(result.kills, value.idleCount * 100000, "100k击杀守恒")
        local sum = 0
        for _, count in pairs(counts) do sum = sum + count end
        eq(sum, total, "各品质计数之和等于总件数")
        conserved(result)
        print(TAG .. "SCALE aggregate stage=" .. id .. " kills=" .. result.kills .. " sampled=" .. total .. " rng=" .. h.rngCalls)
    end
end

local function checkpointReplay()
    for _, id in ipairs({ 1905, 200001, 100001, 300001 }) do
        for _, seed in ipairs({ 17, 32452843, 86028121 }) do
            local baseline = fixture(seed)
            local value = entry(baseline, id)
            local expected = calculate(baseline, value, 80, 200)
            for _, frequency in ipairs({ 1, 7, 113 }) do
                local h, result = fixture(seed), {} ---@type table, table
                local calls, yields, completed = 0, 0, false
                local worker = coroutine.create(function()
                    result = calculate(h, entry(h, id), 80, 200, { checkpoint = function(phase, done, total)
                        eq(phase, "generate", "分帧phase")
                        check((total == 0 and done == 0) or (total > 0 and done >= 0 and done <= total), "分帧进度合法")
                        calls = calls + 1
                        if calls % frequency == 0 then yields = yields + 1; coroutine.yield() end
                    end })
                    completed = true
                end)
                while coroutine.status(worker) ~= "dead" do
                    local ok, reason = coroutine.resume(worker)
                    check(ok, "协程异常原样失败 " .. tostring(reason))
                end
                check(completed and calls > 0, "协作式真实完成并触发检查点")
                if frequency == 1 then check(yields > 0, "每检查点确实yield") end
                same(result, expected, "同新版seed不同checkpoint频率全部字段严格一致")
                eq(h.seed, baseline.seed, "分帧不改变私有RNG终态")
                eq(h.rngCalls, baseline.rngCalls, "分帧不增加/减少任何骰")
            end
        end
    end
end

local function suite()
    local requireBefore, randomBefore, seedBefore = require, math.random, math.randomseed
    local packageBefore, loadedBefore = package, {}
    for key, value in pairs(package.loaded) do loadedBefore[key] = value end
    run("确定公式/参数/进度/经验", deterministicFormulas)
    run("Preview零RNG及只读", previewPurity)
    run("边界掉率/boss池/难度/cap/红尾", boundaryAndPool)
    run("真实ES原件/原序/有限仓位", trueEquipmentOrder)
    run("真二项多seed均值及方差", binomialSampling)
    run("卷轴总数/六类多项协方差/独立性", scrollStatistics)
    run("多难度幸运品质及真红尾采样", qualityStatistics)
    run("资源每杀随机尾数的真实分布", resourceStatistics)
    run("100k货币/百万空杀/完整ES守恒", largeBatches)
    run("同新版seed不同checkpoint频率严格复播", checkpointReplay)
    eq(require, requireBefore, "宿主require不变")
    eq(math.random, randomBefore, "宿主random不变")
    eq(math.randomseed, seedBefore, "宿主randomseed不变")
    eq(package, packageBefore, "宿主package不替换")
    for key, value in pairs(loadedBefore) do eq(package.loaded[key], value, "宿主原模块引用不变 " .. key) end
    for key in pairs(package.loaded) do check(loadedBefore[key] ~= nil, "不泄露私有模块 " .. key) end
    print(TAG .. "SUMMARY cases=" .. cases .. " assertions=" .. checks .. " statistical_batches=" .. statisticalBatches
        .. " quality_stub_objects=" .. stubObjects .. " real_ES_objects=" .. realObjects .. " ALL PASS")
end

function Start()
    checks, cases, statisticalBatches, stubObjects, realObjects = 0, 0, 0, 0, 0
    local ok, reason = pcall(suite)
    engine:Exit()
    if not ok then error(TAG .. "FAIL " .. tostring(reason), 0) end
end
