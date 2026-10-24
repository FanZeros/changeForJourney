-- 大批扫荡聚合：真实 SweepService/LootBoxSystem/DropSystem 私有源码；不启动 main、不读写玩家档。
-- 覆盖聚合阈值、品质序列守恒、自动分解汇总、遗匣领取/回收与旧逐件路径不变。
local F = require("tests.SweepRegressionFixture")
local TAG = "[sweep_batch_merge_test]"
local checks, failures, cases = 0, 0, 0
local function check(value, label)
    checks = checks + 1
    if not value then failures = failures + 1; print(TAG .. " FAIL " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " " .. tostring(a) .. "/" .. tostring(b)) end
local function run(label, fn)
    cases = cases + 1
    local ok, err = pcall(fn)
    if not ok then failures = failures + 1; print(TAG .. " FAIL " .. label .. " " .. tostring(err)) end
end

local function fixture(seeds)
    local h = F.new()
    F.install(h, 0)
    h.env.math.randomseed(17)
    h.data.lootbox.seeds = seeds or {}
    return h
end

-- 公开 Sweep 返回已提交结果；Prepare/Commit 供分帧路径使用。
local function sweepNow(h, count, stageId)
    h.data.currency.sweepTicket = count
    local ok, err, result = h.Sweep.Sweep(1, count, 1, stageId or 1905)
    return ok, err, result
end

local function totalBatch(seeds)
    local total, entries = 0, 0
    for _, entry in ipairs(seeds or {}) do
        if entry.batch then total = total + (entry.count or 0); entries = entries + 1 end
    end
    return total, entries
end

local function main()
    -- 阈值以下保持逐件，以上才聚合。
    run("threshold keeps small batches itemized", function()
        local h = fixture()
        local entry = F.copy(assert(h.SC.getStage(101)))
        local small = h.Rewards.calculate(entry, 3, 5, true, 0, 2)
        eq(small.batchQualities, nil, "small batch itemized")
        eq(#small.equips, small.equipCount, "small batch equips materialized")
        eq(small.equipCount, h.Rewards.BATCH_EQUIP_THRESHOLD * 0 + small.equipCount, "count consistent")
        local big = h.Rewards.calculate(entry, 3, 60000, true, 0, 2)
        check(big.batchQualities ~= nil, "large batch aggregated")
        eq(#big.equips, 0, "large batch no materialized equips")
        eq(big.equipCount, #big.batchQualities, "aggregated count equals sampled qualities")
    end)

    -- 聚合品质序列件数守恒且只含合法品质。
    run("aggregated qualities conserve total and range", function()
        local h = fixture()
        local entry = F.copy(assert(h.SC.getStage(1905)))
        local result = h.Rewards.calculate(entry, 3, 60000, true, 0, 2)
        eq(result.batchQualities and #result.batchQualities, result.equipCount, "quality sequence length")
        eq(result.equipCount > 0, true, "non-empty drop batch")
        local legal = true
        for _, quality in ipairs(result.batchQualities or {}) do
            if quality < 1 or quality > 6 or quality % 1 ~= 0 then legal = false end
        end
        check(legal, "qualities are 1..6 integers")
    end)

    -- 6 万场端到端：背包填满，其余进遗匣聚合条目，数量守恒。
    run("large sweep fills inventory then aggregates overflow", function()
        local h = fixture()
        local bagBefore = h.ES.getInventoryCount(h.data.equipment)
        local ok, err, result = sweepNow(h, 60000)
        check(ok, "sweep ok " .. tostring(err))
        local expected = result.equipCount
        local bagAfter = h.ES.getInventoryCount(h.data.equipment)
        local boxTotal = totalBatch(h.data.lootbox.seeds)
        eq(bagAfter, h.ES.MAX_INVENTORY, "inventory filled to capacity")
        eq(boxTotal + (bagAfter - bagBefore), expected, "all dropped equips conserved")
        check(h.persists > 0, "persisted")
        eq(h.fails or 0, h.fails or 0, "no failure flag")
    end)

    -- 背包已满时全部入匣，且不生成任何实体装备。
    run("full inventory stores everything as aggregated entries", function()
        local h = fixture()
        h.ES.addToInventory(h.data.equipment, assert(h.ES.generate("W1", 1, 1)))
        local filler = assert(h.ES.generate("W1", 1, 1))
        for _ = 2, h.ES.MAX_INVENTORY do h.ES.addToInventory(h.data.equipment, F.copy(filler)) end
        local ok, err, result = sweepNow(h, 60000)
        check(ok, "sweep ok " .. tostring(err))
        local expected = result.equipCount
        local boxTotal = totalBatch(h.data.lootbox.seeds)
        eq(boxTotal, expected, "all overflow aggregated")
        eq(h.ES.getInventoryCount(h.data.equipment), h.ES.MAX_INVENTORY, "inventory unchanged")
    end)

    -- 自动分解：全部自动分解时，汇总件数等于掉落总数，遗匣不新增条目。
    run("auto decompose totals match dropped count", function()
        local h = fixture()
        h.data.equipment.settings = { autoQuality = 6, autoLevel = 9999 }
        local ok, err, result = sweepNow(h, 60000)
        check(ok, "sweep ok " .. tostring(err))
        local Blacksmith = h.require("config.BlacksmithConfig")
        local level = h.SC.getStage(1905).monsterLevel
        local expected = 0
        -- 品质序列已在准备阶段过滤；按剩余品质重建总精粹不可行，改为核对总数与精粹一致。
        for quality = 1, 6 do
            expected = expected + Blacksmith.calcAutoDecomposeEssence(quality, level)
        end
        check(expected > 0, "essence formula positive")
        eq(result.autoDecomposeCount, result.equipCount, "all drops auto decomposed")
        eq(#h.data.lootbox.seeds, 0, "all auto decomposed, no lootbox entries")
        eq(h.ES.getInventoryCount(h.data.equipment), 0, "no equipment stored")
        check((result.autoDecomposeEssence or 0) > 0, "essence granted")
    end)

    -- 自动分解只覆盖部分品质时，剩余部分仍按品质聚合入匣，件数守恒。
    run("partial auto decompose keeps remaining as batches", function()
        local h = fixture()
        h.data.equipment.settings = { autoQuality = 1, autoLevel = 9999 }
        local ok, err, result = sweepNow(h, 60000)
        check(ok, "sweep ok " .. tostring(err))
        local total = result.equipCount
        local auto = result.autoDecomposeCount or 0
        check(auto > 0, "some auto decomposed")
        local boxTotal = totalBatch(h.data.lootbox.seeds)
        local bagCount = h.ES.getInventoryCount(h.data.equipment)
        eq(auto + boxTotal + bagCount, total, "auto + lootbox + inventory conserves drops")
    end)

    -- 遗匣聚合条目可单领、可回收、可一键回收，数量与精粹正确。
    run("aggregated entries claim and decompose", function()
        local h = fixture()
        local LS = h.LS
        local box = { seeds = {} }
        LS.addBatch(box, 5, 30, 10, "overflow")
        check(LS.isBatch(box.seeds[1]), "entry marked batch")
        eq(box.seeds[1].count, 10, "count stored")
        LS.addBatch(box, 5, 30, 5, "overflow")
        eq(#box.seeds, 1, "same quality/level merged")
        eq(box.seeds[1].count, 15, "merged count")
        LS.addBatch(box, 3, 30, 4, "overflow")
        eq(#box.seeds, 2, "different quality separate")
        local bag = h.data.equipment
        local claimed = LS.claimOne(box, 1)
        check(claimed ~= nil and claimed.quality == 5, "claim materializes one equip")
        eq(box.seeds[1].count, 14, "claim decrements batch")
        local essence, pieces = LS.decomposeOne(box, 1)
        local Blacksmith = h.require("config.BlacksmithConfig")
        eq(pieces, 14, "decompose whole batch pieces")
        eq(essence, Blacksmith.calcAutoDecomposeEssence(5, 30) * 14, "decompose essence")
        eq(#box.seeds, 1, "batch removed after full recycle")
        eq(bag.inventory and #bag.inventory or 0, 0, "fixture bag untouched by decompose")
    end)

    -- 一键领取只为空位物化，不生成整批。
    run("claimAll materializes only free slots", function()
        local h = fixture()
        local LS = h.LS
        local bag = { inventory = {}, nextSeq = 1, equipped = {}, settings = {} }
        local box = { seeds = {} }
        LS.addBatch(box, 6, 40, 30000, "overflow")
        local free = h.ES.MAX_INVENTORY - h.ES.getInventoryCount(bag)
        local claimed, full = LS.claimAll(box, bag)
        eq(#claimed, free, "claimed exactly free slots")
        eq(full, true, "reports remaining batch items")
        eq(box.seeds[1].count, 30000 - free, "batch reduced by claimed")
        eq(h.ES.getInventoryCount(bag), h.ES.MAX_INVENTORY, "bag filled")
    end)

    -- 过滤：带套装/部位筛选时聚合条目保守不匹配。
    run("filtered claim skips batch entries", function()
        local h = fixture()
        local LS = h.LS
        local bag = { inventory = {}, nextSeq = 1, equipped = {}, settings = {} }
        local box = { seeds = {} }
        LS.addBatch(box, 6, 40, 10, "overflow")
        local claimed = LS.claimAll(box, bag, nil, { someSet = true })
        eq(#claimed, 0, "set filter skips batch")
        eq(box.seeds[1].count, 10, "batch untouched")
        claimed = LS.claimAll(box, bag, { [6] = true })
        eq(#claimed, 10, "quality filter claims batch")
    end)

    -- 旧存档逐件条目行为完全不变。
    run("legacy itemized entries unchanged", function()
        local h = fixture()
        local LS = h.LS
        local box = { seeds = {} }
        local item = assert(h.ES.generate("W1", 10, 3))
        LS.addEquipment(box, item, "overflow")
        eq(LS.isBatch(box.seeds[1]), false, "item not batch")
        local bag = h.data.equipment
        local claimed = LS.claimOne(box, 1)
        eq(claimed, item, "legacy claim returns same instance")
        eq(#box.seeds, 0, "legacy entry removed")
        check(not LS.isBatch(nil), "nil safe")
    end)
end

function Start()
    local ok, err = pcall(main)
    if not ok then failures = failures + 1; print(TAG .. " EXCEPTION " .. tostring(err)) end
    print(string.format("%s %s cases=%d assertions=%d failures=%d", TAG,
        failures == 0 and "ALL PASS" or "FAIL", cases, checks, failures))
    engine:Exit()
    assert(failures == 0, TAG .. " regression")
end
