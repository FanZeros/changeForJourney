-- 遗匣溢出回归入口，由 UrhoXRuntime -validate 调用 Start。
-- 使用真实装备系统、遗匣系统和 Schema；界面与服务用内存替身隔离。
-- 不渲染、不读写玩家存档、不访问云端或账号接口。

local EquipmentSystem = require("systems.EquipmentSystem")
local LootBoxSystem = require("systems.LootBoxSystem")
local LootboxSchema = require("shared.lootbox.LootboxSchema")
local BlacksmithConfig = require("config.BlacksmithConfig")

local PREFIX = "[lootbox_overflow_test] "

local function eq(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

-- JSON 可舍入浮点词条，但字段和数组长度必须保持一致。
local function same(actual, expected, path)
    path = path or "data"
    eq(type(actual), type(expected), path .. " type")
    if type(expected) == "number" then
        local tolerance = 1e-12 * math.max(1, math.abs(expected))
        assert(math.abs(actual - expected) <= tolerance, path .. ": numeric value changed")
    elseif type(expected) == "table" then
        for key, value in pairs(expected) do
            same(actual[key], value, path .. "." .. tostring(key))
        end
        for key in pairs(actual) do
            assert(expected[key] ~= nil, path .. ": unexpected field " .. tostring(key))
        end
    else
        eq(actual, expected, path)
    end
end

local function sameEquip(actual, expected, message)
    assert(type(actual) == "table", message .. ": missing equipment")
    local actualCopy, expectedCopy = copy(actual), copy(expected)
    -- 入包时分配新序列号，而不是保留旧背包键。
    actualCopy.seq, expectedCopy.seq = nil, nil
    same(actualCopy, expectedCopy, message)
end

local function roundtrip(value)
    return cjson.decode(cjson.encode(value))
end

local function newLootbox()
    return LootboxSchema.Fields.lootbox.getDefault()
end

local function newEquip(level, quality, enhanceLevel)
    local equip = EquipmentSystem.generateRandom(level, quality)
    assert(equip and equip.templateId and equip.slot, "real generator must produce equipment")
    eq(equip.level, level, "fixture equipment level")
    eq(equip.quality, quality, "fixture equipment quality")
    if enhanceLevel then
        assert(#equip.affixes > 0, "enhanced fixture needs real rolled affixes")
        equip.enhanceLevel = enhanceLevel
        equip.refineCount = 3
        equip.locked = true
    end
    return equip
end

local function newBag(count)
    local bag = { inventory = {}, equipped = {}, nextSeq = 1 }
    if count > 0 then
        local filler = newEquip(1, 1)
        for _ = 1, count do EquipmentSystem.addToInventory(bag, copy(filler)) end
    end
    eq(EquipmentSystem.getInventoryCount(bag), count, "fixture bag size")
    return bag
end

local function countIs(box, pieces, entries, message)
    eq(LootBoxSystem.getTotalCount(box), pieces, message .. " pieces")
    eq(LootBoxSystem.getEntryCount(box), entries, message .. " entries")
end

local function findEquipEntry(box, equip)
    for index, entry in ipairs(box.seeds) do
        if entry.equip == equip then return index end
    end
    error("expected independent equipment entry not found")
end

local function essenceFor(quality, level, count)
    local cost = assert(BlacksmithConfig.QUALITY_COST[quality], "missing quality cost")
    return math.floor(cost.decBase * (1 + level * cost.decScale)) * count
end

-- 临时替换共享模块字段，异常时也恢复；已有 require 缓存同样能被监听。
local function withPatchedField(target, key, replacement, body)
    local original = target[key]
    target[key] = replacement
    local ok, err = pcall(body)
    target[key] = original
    assert(ok, tostring(err))
end

-- 默认仍调用真实生成器；定型后可禁止生成，不能仅靠随机结果恰好相同来判断。
local function withGeneratorSpy(body)
    local original = EquipmentSystem.generateRandom
    local spy = { calls = {}, forbidden = false }
    withPatchedField(EquipmentSystem, "generateRandom", function(level, quality)
        assert(not spy.forbidden, "确定装备后不应再调用 generateRandom")
        local equip = original(level, quality)
        spy.calls[#spy.calls + 1] = { level = level, quality = quality, equip = equip }
        return equip
    end, function() body(spy) end)
end

local function assertSummary(box)
    local summary = LootBoxSystem.getSummary(box)
    eq(#summary, #box.seeds, "summary covers every stored entry")
    for index, entry in ipairs(box.seeds) do
        eq(summary[index].equip, entry.equip, "summary preserves equipment identity")
        eq(summary[index].sourceIndex, index, "summary preserves original storage index")
        eq(summary[index].source, entry.source, "summary preserves source")
        eq(summary[index].count, entry.count or 1, "summary count")
        eq(summary[index].quality, entry.quality, "summary quality")
        eq(summary[index].level, entry.level, "summary level")
    end
end

local function assertEmptyCannotPayAgain(box, bag)
    local beforeBag = copy(bag)
    local claimed, full = LootBoxSystem.claimAll(box, bag)
    eq(#claimed, 0, "empty claimAll cannot duplicate rewards")
    eq(full, false, "empty claimAll is not blocked")
    local group, groupFull = LootBoxSystem.claimGroup(box, 1, bag)
    eq(#group, 0, "empty claimGroup cannot duplicate rewards")
    eq(groupFull, false, "empty group is invalid rather than full")
    eq(LootBoxSystem.claimOne(box, 1), nil, "empty claimOne cannot duplicate rewards")
    local value, pieces = LootBoxSystem.decomposeAll(box)
    eq(value, 0, "empty decomposeAll essence")
    eq(pieces, 0, "empty decomposeAll pieces")
    local oneValue, onePieces = LootBoxSystem.decomposeOne(box, 1)
    eq(oneValue, 0, "empty decomposeOne essence")
    eq(onePieces, 0, "empty decomposeOne pieces")
    same(bag, beforeBag, "empty operations preserve bag and nextSeq")
end

local function testDeliveryBoundary()
    eq(EquipmentSystem.MAX_INVENTORY, 200, "inventory capacity contract")
    local bag, box = newBag(199), newLootbox()
    eq(EquipmentSystem.isInventoryFull(bag), false, "199 is not full")
    local direct = newEquip(80, 6, 11)
    local directSnapshot = copy(direct)
    eq(LootBoxSystem.deliverEquipment(box, bag, direct), "inventory", "199th boundary destination")
    eq(EquipmentSystem.getInventoryCount(bag), 200, "last free slot filled")
    eq(EquipmentSystem.isInventoryFull(bag), true, "200 is full")
    eq(bag.inventory[tostring(direct.seq)], direct, "direct delivery stores actual instance")
    sameEquip(direct, directSnapshot, "direct delivery payload")
    countIs(box, 0, 0, "no overflow until full")

    local overflow = { newEquip(80, 6, 12), newEquip(80, 6, 13), newEquip(80, 6, 14) }
    for index, equip in ipairs(overflow) do
        local snapshot = copy(equip)
        eq(LootBoxSystem.deliverEquipment(box, bag, equip), "lootbox", "overflow destination")
        eq(box.seeds[index].equip, equip, "overflow stores original instance")
        eq(box.seeds[index].count, 1, "each full equipment counts once")
        sameEquip(box.seeds[index].equip, snapshot, "overflow payload " .. index)
    end
    eq(EquipmentSystem.getInventoryCount(bag), 200, "multiple overflow never exceeds capacity")
    eq(bag.nextSeq, 201, "overflow does not reserve or consume bag seq")
    countIs(box, 3, 3, "all overflow retained independently")

    local beforeBox, beforeBag = copy(box), copy(bag)
    local claimed, full = LootBoxSystem.claimAll(box, bag)
    eq(#claimed, 0, "full claimAll returns no equipment")
    eq(full, true, "full claimAll reports capacity")
    local group, groupFull = LootBoxSystem.claimGroup(box, 1, bag)
    eq(#group, 0, "full claimGroup returns no equipment")
    eq(groupFull, true, "full claimGroup reports capacity")
    same(box, beforeBox, "full claims retain every payload")
    same(bag, beforeBag, "full claims cannot mutate bag")
end

local function testPartialFullEquipmentClaims()
    local bag, box = newBag(200), newLootbox()
    local equips = { newEquip(90, 6, 15), newEquip(90, 6, 16), newEquip(90, 6, 17) }
    local snapshots = {}
    for index, equip in ipairs(equips) do
        snapshots[index] = copy(equip)
        LootBoxSystem.addEquipment(box, equip)
    end
    assert(EquipmentSystem.removeFromInventory(bag, 1), "free one existing bag slot")
    local first, full = LootBoxSystem.claimAll(box, bag)
    eq(#first, 1, "one free slot claims exactly one complete instance")
    eq(full, true, "partial claimAll reports remaining capacity blockage")
    eq(EquipmentSystem.getInventoryCount(bag), 200, "partial claim refills bag")
    countIs(box, 2, 2, "two complete instances remain")

    local seen = {}
    seen[first[1]] = true
    local before = copy(box)
    local blocked = LootBoxSystem.claimAll(box, bag)
    eq(#blocked, 0, "repeated full claim cannot pay again")
    same(box, before, "blocked remainder unchanged")
    assert(EquipmentSystem.removeFromInventory(bag, 2), "free another slot")
    local second, groupFull = LootBoxSystem.claimGroup(box, 1, bag)
    eq(#second, 1, "claimGroup delivers one complete instance")
    eq(groupFull, false, "completed singleton group has no remainder")
    assert(not seen[second[1]], "second claim must not duplicate first")
    seen[second[1]] = true
    countIs(box, 1, 1, "one full instance remains")
    assert(EquipmentSystem.removeFromInventory(bag, 3), "free final slot")
    local third, finalFull = LootBoxSystem.claimAll(box, bag)
    eq(#third, 1, "last complete instance delivered")
    eq(finalFull, false, "no unclaimed remainder")
    assert(not seen[third[1]], "last claim must be distinct")
    seen[third[1]] = true
    for index, equip in ipairs(equips) do
        assert(seen[equip], "every original overflow instance was claimed")
        sameEquip(equip, snapshots[index], "partial claim preserves all original fields")
        eq(bag.inventory[tostring(equip.seq)], equip, "new seq resolves claimed instance")
    end
    eq(EquipmentSystem.getInventoryCount(bag), 200, "final bag respects cap")
    eq(bag.nextSeq, 204, "exactly three new sequences consumed")
    countIs(box, 0, 0, "complete instances fully drained")
    assertEmptyCannotPayAgain(box, bag)
end

local function testPersistenceAndConsolidation()
    local first = newEquip(80, 6, 21)
    -- 故意使用相同模板、品质和等级，验证完整装备仍不会合并或共享词条。
    local second = copy(first)
    second.enhanceLevel = 22
    second.affixes[1].value = second.affixes[1].value + 0.125
    local expectedFirst, expectedSecond = copy(first), copy(second)
    local box = { seeds = { { stageId = 1, quality = "6", level = "80", count = "2" } } }
    LootBoxSystem.addEquipment(box, first)
    box.seeds[#box.seeds + 1] = { stageId = 2, quality = 6, level = 80 }
    LootBoxSystem.addEquipment(box, second)

    local loaded = roundtrip(box)
    sameEquip(loaded.seeds[2].equip, expectedFirst, "JSON preserves first complete payload")
    sameEquip(loaded.seeds[4].equip, expectedSecond, "JSON preserves second complete payload")
    withGeneratorSpy(function(spy)
        LootboxSchema.Fields.lootbox.onLoad(loaded)
        eq(#spy.calls, 3, "onLoad reveals three legacy pieces exactly once")
        countIs(loaded, 5, 5, "onLoad materializes every piece as an independent entry")
        local loadedEquips, migrated = {}, 0
        local seen = {}
        for _, entry in ipairs(loaded.seeds) do
            eq(entry.quality, 6, "schema quality normalized")
            eq(entry.level, 80, "schema level normalized")
            eq(entry.count, 1, "revealed entries never retain grouped counts")
            assert(entry.equip and entry.equip.templateId, "schema must reveal all legacy seeds")
            assert(not seen[entry.equip], "each migrated equipment table is independent")
            seen[entry.equip] = true
            if entry.source == "overflow" then
                loadedEquips[#loadedEquips + 1] = entry.equip
            else
                eq(entry.source, "idle", "legacy pieces become idle equipment")
                eq(entry.stageId, nil, "legacy stage grouping removed")
                migrated = migrated + 1
                eq(entry.equip, spy.calls[migrated].equip, "migration stores actual generated instance")
                eq(spy.calls[migrated].level, 80, "normalized level passed to generator")
                eq(spy.calls[migrated].quality, 6, "normalized quality passed to generator")
            end
        end
        eq(migrated, 3, "string count and implicit count preserved through reveal")
        eq(#loadedEquips, 2, "both pre-existing complete instances survive schema")
        assert(loadedEquips[1].affixes ~= loadedEquips[2].affixes, "independent affix arrays")
        sameEquip(loadedEquips[1], expectedFirst, "schema preserves full payload A")
        sameEquip(loadedEquips[2], expectedSecond, "schema preserves full payload B")

        assert(LootBoxSystem.addSeed(loaded, 99, 6, 80), "new idle reward accepted")
        eq(#spy.calls, 4, "new idle reward rolls at insertion")
        countIs(loaded, 6, 6, "matching quality and level no longer merge equipment")
        eq(loaded.seeds[6].equip, spy.calls[4].equip, "new idle reward is already complete")
        eq(loaded.seeds[6].source, "idle", "new idle reward source")
        local before = copy(loaded)
        local identities = {}
        for index, entry in ipairs(loaded.seeds) do identities[index] = entry.equip end
        spy.forbidden = true
        -- 改变上限后重复整理、摘要与加载都不能重骰或降级已经确定的装备。
        LootBoxSystem.levelCap = 3
        for _ = 1, 3 do
            LootBoxSystem.consolidateSeeds(loaded)
            eq(LootBoxSystem.revealLegacy(loaded), 0, "second reveal is a no-op")
            LootboxSchema.Fields.lootbox.onLoad(loaded)
            assertSummary(loaded)
        end
        same(loaded, before, "repeated schema and summary preserve complete data")
        for index, equip in ipairs(identities) do
            eq(loaded.seeds[index].equip, equip, "in-memory onLoad preserves object identity")
        end
        loaded = roundtrip(loaded)
        LootboxSchema.Fields.lootbox.onLoad(loaded)
        same(loaded, before, "JSON reload must not reroll any complete payload")
        local expectedByEquip = {}
        for _, entry in ipairs(loaded.seeds) do expectedByEquip[entry.equip] = copy(entry.equip) end
        local bag = newBag(0)
        local target = loaded.seeds[1].equip
        local group = LootBoxSystem.claimGroup(loaded, findEquipEntry(loaded, target), bag)
        eq(#group, 1, "persisted instance claimGroup")
        eq(group[1], target, "claimGroup returns persisted instance")
        local rest, full = LootBoxSystem.claimAll(loaded, bag, 0)
        eq(#rest, 5, "claimAll returns five remaining complete instances")
        eq(full, false, "persisted rewards fit bag")
        for equip, expected in pairs(expectedByEquip) do
            sameEquip(equip, expected, "claim preserves persisted template/affixes/enhancement")
            eq(equip.level, 80, "complete equipment ignores later levelCap")
            eq(bag.inventory[tostring(equip.seq)], equip, "claimed persisted instance delivered once")
        end
        eq(EquipmentSystem.getInventoryCount(bag), 6, "every persisted reward paid once")
        assertEmptyCannotPayAgain(loaded, bag)
        eq(#spy.calls, 4, "only migration and insertion may generate equipment")
    end)
end

local function testClaimOneAndIdleCapacity()
    local box, bag = newLootbox(), newBag(200)
    local complete = newEquip(90, 6, 25)
    local snapshot = copy(complete)
    LootBoxSystem.addEquipment(box, complete)
    LootBoxSystem.levelCap = 7
    withGeneratorSpy(function(spy)
        spy.forbidden = true
        -- claimOne 只取出原始装备，不负责检查容量或放入背包。
        local extracted = LootBoxSystem.claimOne(box, 1)
        eq(extracted, complete, "claimOne returns original complete instance")
        sameEquip(extracted, snapshot, "claimOne bypasses legacy-only levelCap")
        eq(EquipmentSystem.getInventoryCount(bag), 200, "raw extraction does not modify bag")
        eq(LootBoxSystem.claimOne(box, 1), nil, "raw extraction cannot duplicate instance")

        spy.forbidden = false
        for _ = 1, 3 do assert(LootBoxSystem.addSeed(box, 1, 4, 35), "idle reward accepted") end
        eq(#spy.calls, 3, "three drops generated immediately")
        countIs(box, 3, 3, "same quality and level remain three complete entries")
        local snapshots = {}
        for index, entry in ipairs(box.seeds) do
            eq(entry.equip, spy.calls[index].equip, "insertion stores generated instance")
            eq(entry.quality, 4, "idle quality fixed on insertion")
            eq(entry.level, 35, "new idle equipment bypasses legacy-only cap")
            eq(entry.equip.level, 35, "full payload has insertion level")
            eq(entry.source, "idle", "idle source fixed on insertion")
            eq(entry.count, 1, "each idle equipment counts once")
            snapshots[index] = copy(entry.equip)
        end
        spy.forbidden = true
        local before = copy(box)
        for _ = 1, 4 do assertSummary(box) end
        local blocked, full = LootBoxSystem.claimGroup(box, 1, bag)
        eq(#blocked, 0, "full bag cannot consume idle equipment")
        eq(full, true, "complete group blocked by capacity")
        same(box, before, "full group and repeated summaries unchanged")
        assert(EquipmentSystem.removeFromInventory(bag, 1), "free idle equipment slot")
        local partial, partialFull = LootBoxSystem.claimGroup(box, 1, bag)
        eq(#partial, 1, "single free slot claims one complete entry")
        eq(partialFull, false, "singleton group exhausted even when other entries remain")
        eq(partial[1], spy.calls[1].equip, "claimGroup does not generate replacement")
        sameEquip(partial[1], snapshots[1], "claimed idle fields intact")
        countIs(box, 2, 2, "two complete idle entries retained")
        local uncapped = LootBoxSystem.claimOne(box, 1)
        eq(uncapped, spy.calls[2].equip, "raw extraction returns second determined instance")
        sameEquip(uncapped, snapshots[2], "raw extraction preserves full idle payload")
        countIs(box, 1, 1, "claimOne removes one entire entry")
        assert(EquipmentSystem.removeFromInventory(bag, 2), "free final idle slot")
        local last, lastFull = LootBoxSystem.claimAll(box, bag)
        eq(#last, 1, "last idle equipment delivered")
        eq(last[1], spy.calls[3].equip, "claimAll returns final determined instance")
        sameEquip(last[1], snapshots[3], "claimAll preserves insertion payload")
        eq(lastFull, false, "all entries exhausted")
        assertEmptyCannotPayAgain(box, bag)
        eq(#spy.calls, 3, "summary and all claim variants never generateRandom")
    end)
end

local function testBeyond9999()
    local box = { seeds = { { quality = 6, level = 80, count = 9999 } } }
    assert(LootBoxSystem.addSeed(box, 1, 6, 80), "10000th reward accepted")
    countIs(box, 10000, 2, "new complete reward stays separate from old 9999 seeds")
    eq(box.seeds[1].count, 9999, "new drop cannot increment old grouped count")
    assert(LootBoxSystem.addSeed(box, 2, 2, 10), "different quality accepted above cap")
    countIs(box, 10001, 3, "new quality equipment exceeds former total cap")
    local first, second = newEquip(80, 6, 31), newEquip(80, 6, 32)
    local firstSnapshot, secondSnapshot = copy(first), copy(second)
    LootBoxSystem.addEquipment(box, first)
    local bag = newBag(200)
    eq(LootBoxSystem.deliverEquipment(box, bag, second), "lootbox", "overflow above 9999 retained")
    countIs(box, 10003, 5, "old group and all new equipment retained above former limit")
    sameEquip(box.seeds[4].equip, firstSnapshot, "explicit full instance above cap")
    sameEquip(box.seeds[5].equip, secondSnapshot, "delivered full instance above cap")

    local loaded = roundtrip(box)
    withGeneratorSpy(function(spy)
        LootboxSchema.Fields.lootbox.onLoad(loaded)
        eq(#spy.calls, 9999, "all 9999 old seeds materialized exactly once")
        countIs(loaded, 10003, 10003, "migration loses no pieces and keeps every independent instance")
        local seen = {}
        for index, entry in ipairs(loaded.seeds) do
            eq(entry.count, 1, "large migrated save has singleton entries")
            assert(entry.equip and entry.equip.templateId, "large save contains complete equipment")
            assert(not seen[entry.equip], "large migration must not reuse equipment table")
            seen[entry.equip] = true
            if index <= 9999 then
                eq(entry.equip, spy.calls[index].equip, "every legacy piece has its own generated instance")
                eq(entry.source, "idle", "legacy migration source")
            end
        end
        sameEquip(loaded.seeds[10002].equip, firstSnapshot, "large save complete payload A")
        sameEquip(loaded.seeds[10003].equip, secondSnapshot, "large save complete payload B")
        local expected = copy(loaded)
        spy.forbidden = true
        loaded = roundtrip(loaded)
        LootboxSchema.Fields.lootbox.onLoad(loaded)
        eq(LootBoxSystem.revealLegacy(loaded), 0, "large migration is one-time")
        same(loaded, expected, "large complete save survives JSON reload without reroll")
        local value, pieces = LootBoxSystem.decomposeAll(loaded, 0)
        eq(pieces, 10003, "large recycle counts all migrated and new pieces")
        eq(value, essenceFor(6, 80, 10002) + essenceFor(2, 10, 1), "large essence total")
        assertEmptyCannotPayAgain(loaded, bag)
    end)
end

local function testDecompositionAndInvalidIndexes()
    local box, bag = newLootbox(), newBag(0)
    for _ = 1, 3 do LootBoxSystem.addSeed(box, 1, 1, 1) end
    LootBoxSystem.addEquipment(box, newEquip(10, 6, 35))
    for _ = 1, 2 do LootBoxSystem.addSeed(box, 2, 2, 5) end
    local before = copy(box)
    for _, index in ipairs({ 0, -1, 99 }) do
        eq(LootBoxSystem.claimOne(box, index), nil, "invalid raw claim")
        local group, full = LootBoxSystem.claimGroup(box, index, bag)
        eq(#group, 0, "invalid group claim")
        eq(full, false, "invalid group is not capacity failure")
        local value, pieces = LootBoxSystem.decomposeOne(box, index)
        eq(value, 0, "invalid decompose essence")
        eq(pieces, 0, "invalid decompose pieces")
    end
    same(box, before, "invalid indexes cannot mutate rewards")
    local idleValue, idlePieces = LootBoxSystem.decomposeOne(box, 1)
    eq(idlePieces, 1, "decomposeOne consumes only the selected determined equipment")
    eq(idleValue, 5, "round 5.5 essence down for each piece")
    countIs(box, 5, 5, "same-quality siblings remain independent after single recycle")
    local equipValue, equipPieces = LootBoxSystem.decomposeOne(box, 3)
    eq(equipPieces, 1, "complete overflow instance contributes one piece")
    eq(equipValue, 60, "complete instance quality/level essence")
    local allValue, allPieces = LootBoxSystem.decomposeAll(box, 0)
    eq(allPieces, 4, "all recycling includes two common and two uncommon instances")
    eq(allValue, 40, "sum per-piece floor values without merging or double payment")
    assertEmptyCannotPayAgain(box, bag)

    local alreadyClaimed = newEquip(10, 6, 36)
    LootBoxSystem.addEquipment(box, alreadyClaimed)
    LootBoxSystem.addSeed(box, 1, 1, 1)
    local claimed = LootBoxSystem.claimGroup(box, 1, bag)
    eq(claimed[1], alreadyClaimed, "claim preceding decomposition")
    local remainderValue, remainderPieces = LootBoxSystem.decomposeAll(box)
    eq(remainderValue, 5, "claimed equipment cannot also pay essence")
    eq(remainderPieces, 1, "claimed equipment excluded from decomposed count")
    eq(EquipmentSystem.getInventoryCount(bag), 1, "decomposition leaves claimed bag item intact")
    assertEmptyCannotPayAgain(box, bag)
end

-- 尚未迁移的种子可以展示，但任何领取接口都不能偷偷随机或消耗它。
local function testUnrevealedClaimsAndLegacyConsolidation()
    local complete = newEquip(80, 6, 37)
    local box, bag = newLootbox(), newBag(0)
    box.seeds = {
        { stageId = 1, quality = 6, level = 80, count = 2 },
        { quality = 6, level = 80, count = 1, equip = complete, source = "overflow" },
        { stageId = 2, quality = 6, level = 80 },
    }
    withGeneratorSpy(function(spy)
        spy.forbidden = true
        LootBoxSystem.consolidateSeeds(box)
        countIs(box, 4, 2, "only unrevealed legacy seeds consolidate")
        eq(box.seeds[1].count, 3, "legacy counts merge including implicit one")
        eq(box.seeds[1].stageId, nil, "legacy stage key removed")
        eq(box.seeds[2].equip, complete, "same-quality full instance never merged")
        local seedSnapshot = copy(box.seeds[1])
        for _ = 1, 3 do
            assertSummary(box)
            eq(LootBoxSystem.claimOne(box, 1), nil, "unrevealed raw claim cannot generate")
            local group, full = LootBoxSystem.claimGroup(box, 1, bag)
            eq(#group, 0, "unrevealed group cannot generate")
            eq(full, false, "unrevealed group is not a bag-capacity failure")
        end
        local claimed, full = LootBoxSystem.claimAll(box, bag, 6)
        eq(#claimed, 1, "mixed claimAll takes only already complete equipment")
        eq(claimed[1], complete, "mixed claimAll preserves full instance")
        eq(full, false, "mixed claim fits bag")
        countIs(box, 3, 1, "unrevealed quantity retained after mixed claims")
        same(box.seeds[1], seedSnapshot, "claims cannot consume or mutate unrevealed group")
        eq(#LootBoxSystem.claimAll(box, bag, 0), 0, "repeated claims still cannot reveal")
        eq(#spy.calls, 0, "summary/consolidation/claim never invoke generator")
        -- 显式迁移才生成；已领取的完整实例不会再参与迁移或回收。
        spy.forbidden = false
        eq(LootBoxSystem.revealLegacy(box), 3, "explicit reveal materializes all remaining legacy pieces")
        eq(#spy.calls, 3, "each legacy piece generated exactly once")
        spy.forbidden = true
        countIs(box, 3, 3, "revealed legacy group is three independent equipment entries")
        local rest = LootBoxSystem.claimAll(box, bag, 0)
        eq(#rest, 3, "revealed pieces can now be claimed")
        eq(EquipmentSystem.getInventoryCount(bag), 4, "mixed old/new rewards paid exactly once")
        assertEmptyCannotPayAgain(box, bag)
    end)
end

-- 生成失败要保留尚未生成的数量，重试只补剩余项，不能重骰已成功的装备。
local function testLegacyRevealFailureRecovery()
    local box = { seeds = { { quality = 4, level = 90, count = 4 } } }
    local complete = newEquip(90, 6, 38)
    LootBoxSystem.addEquipment(box, complete)
    local original = EquipmentSystem.generateRandom
    local attempts, generated = 0, {}
    LootBoxSystem.levelCap = 7
    withPatchedField(EquipmentSystem, "generateRandom", function(level, quality)
        attempts = attempts + 1
        eq(level, 7, "only legacy generation uses cap")
        eq(quality, 4, "legacy quality preserved on failure/retry")
        if attempts > 2 then return nil end
        local equip = original(level, quality)
        generated[#generated + 1] = equip
        return equip
    end, function()
        eq(LootBoxSystem.revealLegacy(box), 2, "partial migration reports successes only")
        eq(attempts, 3, "migration stops at first failed generation")
        countIs(box, 5, 4, "two revealed, two pending and one overflow all retained")
        eq(box.seeds[3].count, 2, "failed migration retains exact outstanding count")
        eq(box.seeds[3].equip, nil, "outstanding quantity remains unrevealed")
        local before = copy(box)
        eq(LootBoxSystem.revealLegacy(box), 0, "total failure converts nothing")
        same(box, before, "failed retry preserves successful payloads and pending count")
    end)
    withGeneratorSpy(function(spy)
        eq(LootBoxSystem.revealLegacy(box), 2, "successful retry only fills remaining two")
        eq(#spy.calls, 2, "retry must not regenerate the first two successes")
        countIs(box, 5, 5, "recovered migration retains all rewards independently")
        eq(box.seeds[1].equip, generated[1], "first successful instance survives retry")
        eq(box.seeds[2].equip, generated[2], "second successful instance survives retry")
        eq(box.seeds[5].equip, complete, "pre-existing overflow survives migration")
        for index = 1, 4 do
            eq(box.seeds[index].level, 7, "legacy payload is fixed at migration level")
            eq(box.seeds[index].source, "idle", "recovered legacy source")
        end
        eq(complete.level, 90, "pre-existing equipment never clamped")
        spy.forbidden = true
        LootBoxSystem.levelCap = 1
        local before = copy(box)
        LootboxSchema.Fields.lootbox.onLoad(box)
        eq(LootBoxSystem.revealLegacy(box), 0, "completed recovery is idempotent")
        same(box, before, "later cap cannot change recovered equipment")
    end)
end

-- 两轮交错插入六种品质，防止实现错误地只处理连续分组或把筛选当成上限。
local function qualityFixture()
    local box = newLootbox()
    for round = 1, 2 do
        for quality = 1, 6 do
            assert(LootBoxSystem.addSeed(box, round, quality, round * 10 + quality), "quality fixture drop")
        end
    end
    return box
end

local function hiddenEntries(box, quality)
    local entries = {}
    for _, entry in ipairs(box.seeds) do
        if quality ~= 0 and entry.quality ~= quality then entries[#entries + 1] = entry end
    end
    return entries
end

local function assertHiddenEntries(box, entries, snapshot)
    eq(#box.seeds, #entries, "only hidden qualities remain")
    for index, entry in ipairs(entries) do
        eq(box.seeds[index], entry, "hidden entry identity and order unchanged")
        same(box.seeds[index], snapshot[index], "hidden payload must remain untouched")
    end
end

local function testExactQualityClaims()
    for quality = 0, 6 do
        local box, bag = qualityFixture(), newBag(0)
        local hidden = hiddenEntries(box, quality)
        local hiddenSnapshot = copy(hidden)
        local expected = {}
        for _, entry in ipairs(box.seeds) do
            if quality == 0 or entry.quality == quality then expected[entry.equip] = copy(entry.equip) end
        end
        withGeneratorSpy(function(spy)
            spy.forbidden = true
            local claimed, full = LootBoxSystem.claimAll(box, bag, quality)
            local count = quality == 0 and 12 or 2
            eq(#claimed, count, "0 claims all; 1..6 claim exact quality only")
            eq(full, false, "selected rewards fit bag")
            local seen = {}
            for _, equip in ipairs(claimed) do
                assert(expected[equip] and not seen[equip], "only distinct selected instances claimed")
                seen[equip] = true
                sameEquip(equip, expected[equip], "filtered claim preserves complete payload")
                eq(bag.inventory[tostring(equip.seq)], equip, "filtered instance inserted once")
            end
            assertHiddenEntries(box, hidden, hiddenSnapshot)
            assertSummary(box)
            local beforeBag = copy(bag)
            local repeated, repeatedFull = LootBoxSystem.claimAll(box, bag, quality)
            eq(#repeated, 0, "empty selected quality cannot claim hidden equipment")
            eq(repeatedFull, false, "empty selection is not bag full")
            local value, pieces = LootBoxSystem.decomposeAll(box, quality)
            eq(value, 0, "claimed selection cannot also pay essence")
            eq(pieces, 0, "hidden qualities excluded from selected recycle")
            same(bag, beforeBag, "repeated filtered operations cannot mutate bag")
            assertHiddenEntries(box, hidden, hiddenSnapshot)
            eq(#LootBoxSystem.claimAll(box, bag, 0), #hidden, "quality 0 drains remaining qualities")
            assertEmptyCannotPayAgain(box, bag)
        end)
    end
    -- 背包仅余一格时，也不能因逆序遍历先领走末尾的隐藏高品质。
    local box, bag = qualityFixture(), newBag(199)
    local hidden = hiddenEntries(box, 3)
    local hiddenSnapshot = copy(hidden)
    local claimed, full = LootBoxSystem.claimAll(box, bag, 3)
    eq(#claimed, 1, "one free slot only claims one matching quality")
    eq(claimed[1].quality, 3, "partial selection must not claim hidden quality")
    eq(full, true, "matching remainder blocked by capacity")
    eq(EquipmentSystem.getInventoryCount(bag), 200, "filtered partial claim respects cap")
    local before = copy(box)
    eq(#LootBoxSystem.claimAll(box, bag, 3), 0, "full retry does not consume selection")
    same(box, before, "full filtered retry leaves every entry intact")
    assert(EquipmentSystem.removeFromInventory(bag, 1), "free slot for matching remainder")
    local rest, restFull = LootBoxSystem.claimAll(box, bag, 3)
    eq(#rest, 1, "claim matching remainder only")
    eq(restFull, false, "hidden entries do not cause false bagFull after selection exhausted")
    assertHiddenEntries(box, hidden, hiddenSnapshot)
    local empty, emptyFull = LootBoxSystem.claimAll(box, bag, 3)
    eq(#empty, 0, "no matching entry even though hidden rewards remain")
    eq(emptyFull, false, "full bag with no matching entry is not a blocked claim")
end

local function testExactQualityDecomposition()
    for quality = 0, 6 do
        local box, bag = qualityFixture(), newBag(0)
        local hidden = hiddenEntries(box, quality)
        local hiddenSnapshot = copy(hidden)
        local expectedEssence = 0
        for _, entry in ipairs(box.seeds) do
            if quality == 0 or entry.quality == quality then
                expectedEssence = expectedEssence + essenceFor(entry.quality, entry.level, 1)
            end
        end
        withGeneratorSpy(function(spy)
            spy.forbidden = true
            local value, pieces = LootBoxSystem.decomposeAll(box, quality)
            eq(pieces, quality == 0 and 12 or 2, "recycle 0/all or exact 1..6 selection")
            eq(value, expectedEssence, "filtered essence excludes all hidden equipment")
            assertHiddenEntries(box, hidden, hiddenSnapshot)
            local againValue, againPieces = LootBoxSystem.decomposeAll(box, quality)
            eq(againValue, 0, "filtered recycle cannot pay twice")
            eq(againPieces, 0, "empty selection cannot recycle hidden equipment")
            eq(#LootBoxSystem.claimAll(box, bag, quality), 0, "recycled selection cannot be claimed")
            eq(EquipmentSystem.getInventoryCount(bag), 0, "recycling never inserts bag items")
            assertHiddenEntries(box, hidden, hiddenSnapshot)
            local remainder = LootBoxSystem.claimAll(box, bag, 0)
            eq(#remainder, #hidden, "every hidden equipment remains claimable")
            for _, equip in ipairs(remainder) do
                assert(quality ~= 0 and equip.quality ~= quality, "only untouched hidden quality remains")
            end
            assertEmptyCannotPayAgain(box, bag)
        end)
    end
end

-- 只替换页面和绘制依赖，真实门面的 openPage/refreshPage/updateSeedData 参与测试。
local function testReopenAndJsonNoReroll()
    local box = newLootbox()
    LootBoxSystem.addSeed(box, 1, 6, 80)
    LootBoxSystem.addEquipment(box, newEquip(90, 6, 39))
    box.seeds[#box.seeds + 1] = { quality = 4, level = 70, count = 2 }
    local page = { opened = false, opens = 0, summary = {} }
    page.isOpen = function() return page.opened end
    page.open = function(summary)
        page.opened = true
        page.opens = page.opens + 1
        page.summary = summary
    end
    page.hide = function() page.opened = false end
    page.refresh = function(summary) page.summary = summary end
    withPatchedField(package.loaded, "ui.LootBoxPage", page, function()
        withPatchedField(package.loaded, "core.DrawUtil", {}, function()
            withPatchedField(package.loaded, "ui.LootBox", nil, function()
                local facade = require("ui.LootBox")
                withGeneratorSpy(function(spy)
                    facade.updateSeedData(box)
                    eq(#spy.calls, 2, "facade reveals only previously unrevealed legacy pieces")
                    countIs(box, 4, 4, "facade retains all rewards after initial reveal")
                    eq(facade.getCount(), 4, "facade count uses determined entries")
                    local before = copy(box)
                    spy.forbidden = true
                    LootBoxSystem.levelCap = 1
                    for _ = 1, 3 do
                        facade.openPage()
                        assert(facade.isPageOpen(), "real facade opens stub page")
                        facade.refreshPage()
                        assertSummary(box)
                        for index, entry in ipairs(box.seeds) do
                            eq(page.summary[index].equip, entry.equip, "reopen uses same equipment instance")
                            eq(page.summary[index].sourceIndex, index, "reopen preserves claim index")
                        end
                        page.hide()
                        assert(not facade.isPageOpen(), "page closes before reopening")
                    end
                    eq(page.opens, 3, "actually exercised three close/reopen cycles")
                    same(box, before, "close/reopen does not mutate determined rewards")
                    local loaded = roundtrip(box)
                    LootboxSchema.Fields.lootbox.onLoad(loaded)
                    facade.updateSeedData(loaded)
                    facade.openPage()
                    facade.refreshPage()
                    same(loaded, before, "JSON onLoad and reopen do not reroll or clamp")
                    eq(facade.getCount(), 4, "reload count preserved")
                    for index, entry in ipairs(loaded.seeds) do
                        eq(page.summary[index].equip, entry.equip, "reload points to loaded equipment")
                    end
                    eq(#spy.calls, 2, "only first legacy reveal called generator")
                end)
            end)
        end)
    end)
end

-- 执行真实 Boot.run 及其注册的回调，不在替身里重写奖励结算。
-- 缺少回调注册时直接失败。
local function withBoot(bagCount, body)
    local h = {
        data = { equipment = newBag(bagCount), lootbox = newLootbox(), heroes = {} },
        callbacks = {}, subscribers = {}, popups = {}, currency = {}, generated = {},
        notifications = {}, toasts = {}, hints = {}, bridgeReady = false,
        firstEquips = { newEquip(80, 6, 41), newEquip(80, 6, 42) },
        firstSnapshots = {},
    }
    for index, equip in ipairs(h.firstEquips) do h.firstSnapshots[index] = copy(equip) end
    local stage = {
        monsterLevel = 60, fcGold = 31, fcExp = 19, fcDiamond = 7,
        fcEssence = 11, fcArcaneDust = 13,
    }
    h.stage, h.dropQuality, h.maxStageId = stage, 5, 2
    local patches = {}
    local function inject(name, value)
        patches[#patches + 1] = { name = name, previous = package.loaded[name] }
        package.loaded[name] = value
    end
    local function noop() end
    local function ui(name, methods)
        local module = {}
        for _, method in ipairs(methods or {}) do
            local key = name .. "." .. method
            module[method] = function(callback)
                assert(type(callback) == "function", key .. " requires callback")
                assert(not h.callbacks[key], key .. " registered twice")
                h.callbacks[key] = callback
            end
        end
        inject(name, module)
        return module
    end
    function h.fire(moduleName, method, ...)
        local callback = assert(h.callbacks[moduleName .. "." .. method], "Boot callback missing: " .. method)
        return callback(...)
    end
    function h.notify(name)
        h.notifications[name] = (h.notifications[name] or 0) + 1
        for _, callback in ipairs(h.subscribers[name] or {}) do
            -- 测试不吞订阅异常，避免生产分发器的 pcall 掩盖错误。
            callback(h.data[name], name)
        end
    end
    local gameState = {}
    for _, field in ipairs({ "Gold", "Gems", "Essence", "ArcaneDust", "GoldenKey", "CorruptStone",
        "SacredStone", "WeaponScroll", "OffhandScroll", "ArmorScroll", "AccessoryScroll",
        "HelmetScroll", "ShoesScroll" }) do
        local key = field
        h.currency[key] = 0
        gameState["get" .. key] = function() return h.currency[key] end
        gameState["set" .. key] = function(value) h.currency[key] = value end
    end
    h.currency.Exp = 0
    gameState.addExp = function(value) h.currency.Exp = h.currency.Exp + value end
    inject("core.GameState", gameState)
    inject("config.ExpTable", { getHeroCountExpMult = function() return 1 end })
    inject("config.StageConfig", {
        getStage = function(id)
            if id == 1 then return { monsterLevel = 5 } end
            if id == 2 then return stage end
            return nil
        end,
        getFirstClearGoldenKey = function() return 2 end,
        getFirstClearCorruptStone = function() return 3 end,
        getFirstClearSacredStone = function() return 4 end,
    })
    inject("systems.DropSystem", {
        rollKillDrop = function() return h.dropQuality end,
        rollScrollDrop = function() return "weaponScroll" end,
        generateFirstClearEquips = function() return h.firstEquips end,
        generateFirstClearScrolls = function() return { scrolls = { weaponScroll = 3 } } end,
    })
    -- 直接监听原模块，Boot 与已经缓存该模块的 LootBoxSystem 均计入生成次数。
    local originalGenerate = EquipmentSystem.generateRandom
    EquipmentSystem.generateRandom = function(level, quality)
        local equip = originalGenerate(level, quality)
        assert(equip, "Boot reward generation must succeed")
        h.generated[#h.generated + 1] = {
            equip = equip, snapshot = copy(equip), level = level, quality = quality,
        }
        return equip
    end
    inject("runtime.ClientDispatcher", {
        get = function(name) return h.data[name] end,
        subscribe = function(name, callback)
            h.subscribers[name] = h.subscribers[name] or {}
            table.insert(h.subscribers[name], callback)
        end,
        notifySubscribers = h.notify,
    })
    local topBar = ui("ui.TopBar")
    topBar.setTotalPower = noop
    local bottomNav = ui("ui.BottomNav")
    bottomNav.setSelectedIndex = noop
    local battle = ui("ui.BattleScene", { "setOnEnemyKill", "setOnEnemyDrop", "setOnAllDead",
        "setOnStageLoaded", "setOnReincarnate", "setOnFirstClear" })
    battle.getCurrentStageId = function() return 1 end
    battle.getMaxStageId = function() return h.maxStageId end
    battle.refreshAllyStats = noop
    local character = ui("ui.CharacterPanel", { "setOnTeamChanged" })
    character.getTotalPower = function() return 0 end
    ui("ui.BattleTriPage", { "setOnKill" })
    ui("ui.TownScene", { "setOnSmithClick", "setOnChurchClick", "setOnTreeClick",
        "setOnTavernClick", "setOnMarketClick", "setOnWarehouseClick", "setOnLootBoxClick" })
    for _, name in ipairs({ "ui.BlacksmithPage", "ui.ChurchPage", "ui.TavernPage", "ui.MarketPage",
        "ui.MailPanel", "ui.IntroCutscene", "ui.TaskPanel", "ui.SignInPanel", "ui.BackpackPanel" }) do
        ui(name)
    end
    local popup = ui("ui.RewardPopup")
    popup.show = function(title, rewards, options)
        h.popups[#h.popups + 1] = { title = title, rewards = copy(rewards), options = copy(options or {}) }
    end
    local lootUI = ui("ui.LootBox", { "setOnClaimAll", "setOnClaimOne", "setOnDecomposeAll",
        "setOnDecomposeOne", "setOnAutoDecompose" })
    lootUI.updateSeedData = noop
    lootUI.refreshPage = noop
    lootUI.addSeedHint = function(quality, level)
        h.hints[#h.hints + 1] = { quality = quality, level = level }
    end
    local lootPage = ui("ui.LootBoxPage")
    lootPage.getLastClickPos = function() return 0, 0 end
    lootPage.showToast = function(text) h.toasts[#h.toasts + 1] = text end
    local combat = ui("ui.BattleCombat")
    combat.addFloatingText = noop
    local info = ui("ui.PlayerInfoPanel")
    info.setUID = noop
    inject("client.data.PlayerStore", { Subscribe = noop })
    inject("network.LocalActionBridge", { init = noop })
    inject("network.StandaloneBoot", nil)

    -- 禁止昵称分支访问云端与账号接口。
    local oldCloud, oldLobby = rawget(_G, "clientCloud"), rawget(_G, "lobby")
    local oldNickname = rawget(_G, "GetUserNickname")
    local oldCap = LootBoxSystem.levelCap
    rawset(_G, "clientCloud", false)
    rawset(_G, "lobby", false)
    rawset(_G, "GetUserNickname", function() error("test must not call account APIs") end)
    local ok, err = pcall(function()
        local Boot = require("network.StandaloneBoot")
        Boot.run({
            localSendAction = function() error("test must not dispatch external actions") end,
            setLocalBridgeReady = function() h.bridgeReady = true end,
        })
        assert(h.bridgeReady, "real Boot.run completed bridge wiring")
        body(h)
    end)
    EquipmentSystem.generateRandom = originalGenerate
    LootBoxSystem.levelCap = oldCap
    rawset(_G, "clientCloud", oldCloud)
    rawset(_G, "lobby", oldLobby)
    rawset(_G, "GetUserNickname", oldNickname)
    for index = #patches, 1, -1 do
        local patch = patches[index]
        package.loaded[patch.name] = patch.previous
    end
    assert(ok, tostring(err))
end

local function drop(h, firstClear, count)
    for _ = 1, count do
        h.fire("ui.BattleScene", "setOnEnemyDrop", { stageId = 2, isFirstClear = firstClear })
    end
end

local function rewardTotals(popup)
    local totals = {}
    for _, reward in ipairs(popup.rewards) do
        totals[reward.type] = (totals[reward.type] or 0) + (reward.type == "equip" and 1 or reward.amount)
    end
    return totals
end

local function assertBootEquipDelivered(h, equip, snapshot)
    sameEquip(equip, snapshot, "Boot delivery preserves generated payload")
    local matches = 0
    for _, stored in pairs(h.data.equipment.inventory) do
        if stored == equip then matches = matches + 1 end
    end
    for _, entry in ipairs(h.data.lootbox.seeds) do
        if entry.equip == equip then
            eq(entry.count, 1, "Boot overflow entry counts once")
            eq(entry.level, snapshot.level, "Boot subscriber cannot clamp complete instance")
            matches = matches + 1
        end
    end
    eq(matches, 1, "Boot delivers each generated instance exactly once")
end

local function assertStageEventsCannotRepay(h)
    local beforeData, beforeCurrency = copy(h.data), copy(h.currency)
    local beforePopups, beforeGenerated = #h.popups, #h.generated
    h.fire("ui.BattleScene", "setOnStageLoaded", 2, {})
    h.fire("ui.BattleScene", "setOnStageLoaded", 1, {})
    h.fire("ui.BattleScene", "setOnAllDead")
    same(h.data, beforeData, "post-settlement stage/allDead cannot duplicate equipment")
    same(h.currency, beforeCurrency, "post-settlement stage/allDead cannot duplicate currencies")
    eq(#h.popups, beforePopups, "post-settlement events cannot show duplicate popup")
    eq(#h.generated, beforeGenerated, "post-settlement events cannot regenerate drops")
end

local function testBootSuccess(bagCount)
    withBoot(bagCount, function(h)
        drop(h, true, 2)
        countIs(h.data.lootbox, 0, 0, "first-clear kills remain pending until settlement")
        eq(EquipmentSystem.getInventoryCount(h.data.equipment), bagCount, "pending kills not delivered early")
        eq(h.currency.WeaponScroll, 0, "first-clear kill scrolls pending")
        eq(#h.popups, 0, "no kill popup before first-clear settlement")
        h.fire("ui.BattleScene", "setOnFirstClear", 2)
        eq(#h.popups, 1, "success merges first-clear and kill rewards in one popup")
        eq(h.popups[1].title, "首通奖励", "success reward category unchanged")
        eq(h.popups[1].options.row, 1, "success popup remains in battle row")
        assert(h.popups[1].options.cascade ~= false, "success retains default reward cascade")
        same(rewardTotals(h.popups[1]), {
            equip = 4, gold = 31, diamond = 7, essence = 11, arcane_dust = 13,
            golden_key = 2, corrupt_stone = 3, sacred_stone = 4, weapon_scroll = 5,
        }, "success includes original currencies, FC equipment and kill rewards")
        eq(h.currency.Gold, 31, "FC gold applied once")
        eq(h.currency.Exp, 19, "FC experience applied once")
        eq(h.currency.Gems, 7, "FC diamonds applied once")
        eq(h.currency.Essence, 11, "FC essence applied once")
        eq(h.currency.ArcaneDust, 13, "FC dust applied once")
        eq(h.currency.GoldenKey, 2, "FC keys applied once")
        eq(h.currency.CorruptStone, 3, "FC corrupt stones applied once")
        eq(h.currency.SacredStone, 4, "FC sacred stones applied once")
        eq(h.currency.WeaponScroll, 5, "FC and kill scroll quantities merged")
        eq(#h.generated, 2, "two pending kills materialized exactly once")
        for index, equip in ipairs(h.firstEquips) do
            assertBootEquipDelivered(h, equip, h.firstSnapshots[index])
        end
        for _, generated in ipairs(h.generated) do
            assertBootEquipDelivered(h, generated.equip, generated.snapshot)
        end
        local overflowCount = bagCount + 4 - 200
        countIs(h.data.lootbox, overflowCount, overflowCount, "all FC overflow is complete equipment")
        eq(EquipmentSystem.getInventoryCount(h.data.equipment), 200, "FC respects final bag capacity")
        local destinations = { inventory = 0, lootbox = 0 }
        for _, reward in ipairs(h.popups[1].rewards) do
            if reward.type == "equip" then
                assert(destinations[reward.destination] ~= nil, "equipment reward has valid destination")
                destinations[reward.destination] = destinations[reward.destination] + 1
            end
        end
        eq(destinations.inventory, 200 - bagCount, "popup identifies actual direct deliveries")
        eq(destinations.lootbox, overflowCount, "popup identifies actual overflow deliveries")
        assertStageEventsCannotRepay(h)
    end)
end

local function testBootFailure()
    withBoot(200, function(h)
        drop(h, true, 3)
        h.fire("ui.BattleScene", "setOnAllDead")
        eq(#h.popups, 1, "failure shows retained drops once")
        eq(h.popups[1].title, "战斗掉落", "failure reward category unchanged")
        eq(h.popups[1].options.row, 1, "failure popup battle row")
        eq(h.popups[1].options.cascade, false, "failure popup is not FC cascade")
        same(rewardTotals(h.popups[1]), { equip = 3, weapon_scroll = 3 }, "failure awards kills only")
        eq(h.currency.Gold, 0, "failure cannot award first-clear gold")
        eq(h.currency.Exp, 0, "failure cannot award first-clear experience")
        eq(h.currency.WeaponScroll, 3, "failure retains all kill scrolls")
        countIs(h.data.lootbox, 3, 3, "every failure overflow stored as complete instance")
        eq(EquipmentSystem.getInventoryCount(h.data.equipment), 200, "failure bag stays capped")
        eq(#h.generated, 3, "failure materializes exactly three pending drops")
        for _, generated in ipairs(h.generated) do
            assertBootEquipDelivered(h, generated.equip, generated.snapshot)
        end
        assertStageEventsCannotRepay(h)
    end)
end

local function testBootStageLoadedFallback()
    withBoot(200, function(h)
        drop(h, true, 1)
        h.fire("ui.BattleScene", "setOnStageLoaded", 1, {})
        eq(#h.popups, 1, "leaving pending fight retains rewards")
        eq(h.popups[1].title, "战斗掉落", "abandoned fight uses battle-drop category")
        same(rewardTotals(h.popups[1]), { equip = 1, weapon_scroll = 1 }, "stage fallback settles pending once")
        countIs(h.data.lootbox, 1, 1, "stage fallback saves complete overflow")
        assertBootEquipDelivered(h, h.generated[1].equip, h.generated[1].snapshot)
        assertStageEventsCannotRepay(h)
        drop(h, true, 1)
        h.fire("ui.BattleScene", "setOnAllDead")
        eq(#h.popups, 2, "subsequent fight can settle new rewards")
        eq(#h.generated, 2, "new fight does not replay old pending seeds")
        eq(h.currency.WeaponScroll, 2, "new fight does not replay old scrolls")
        countIs(h.data.lootbox, 2, 2, "both fights retained independently")
        assertStageEventsCannotRepay(h)
    end)
end

local function testBootIdleAndClaimCallbacks()
    withBoot(199, function(h)
        LootBoxSystem.levelCap = 7
        drop(h, false, 2)
        countIs(h.data.lootbox, 2, 2, "idle kills immediately become independent equipment")
        eq(#h.generated, 2, "idle drops generate exactly once at insertion")
        for index, entry in ipairs(h.data.lootbox.seeds) do
            eq(entry.equip, h.generated[index].equip, "idle stores actual generated instance")
            eq(entry.source, "idle", "new idle drop records source")
            eq(entry.level, 60, "idle entry level fixed from killed stage")
            eq(entry.quality, 5, "idle entry quality fixed from drop roll")
            eq(entry.equip.level, 60, "idle payload ignores old seed cap")
            eq(entry.equip.quality, 5, "idle payload matches entry quality")
            eq(h.generated[index].level, 60, "Boot passes stage level on insertion")
            eq(h.generated[index].quality, 5, "Boot passes rolled quality on insertion")
            assertBootEquipDelivered(h, entry.equip, h.generated[index].snapshot)
        end
        eq(#h.popups, 0, "idle kills do not show FC/battle reward popup")
        eq(#h.hints, 2, "idle still sends drop hints")
        eq(h.currency.WeaponScroll, 2, "idle scrolls delivered immediately")
        eq(EquipmentSystem.getInventoryCount(h.data.equipment), 199, "idle does not use free bag slot")
        assertStageEventsCannotRepay(h)

        -- 入匣后改变后续掉落规则，现存装备的领取与回收都不能重算品质和等级。
        h.stage.monsterLevel, h.dropQuality = 3, 1
        withGeneratorSpy(function(spy)
            spy.forbidden = true
            h.notify("lootbox")
            for _ = 1, 3 do assertSummary(h.data.lootbox) end
            h.fire("ui.LootBox", "setOnClaimAll", 5)
            eq(EquipmentSystem.getInventoryCount(h.data.equipment), 200, "Boot claim respects capacity")
            countIs(h.data.lootbox, 1, 1, "Boot partial claim retains complete idle equipment")
            eq(#h.popups, 1, "idle claim uses separate popup")
            eq(h.popups[1].title, "遗匣领取", "遗匣领取使用独立标题")
            same(rewardTotals(h.popups[1]), { equip = 1 }, "claim popup includes inserted equipment only")
            eq(h.popups[1].rewards[1].quality, 5, "claim popup uses insertion quality")
            eq(h.popups[1].rewards[1].level, 60, "claim popup uses insertion level")
            for _, generated in ipairs(h.generated) do
                assertBootEquipDelivered(h, generated.equip, generated.snapshot)
            end
            h.fire("ui.LootBox", "setOnClaimAll", 5)
            eq(#h.popups, 1, "full repeated claim cannot display duplicate reward")
            countIs(h.data.lootbox, 1, 1, "full repeated claim retains complete reward")
            assert(#h.toasts > 0, "Boot still reports full inventory")
            h.fire("ui.LootBox", "setOnDecomposeAll", 5)
            eq(h.currency.Essence, essenceFor(5, 60, 1), "Boot recycles at original insertion quality/level")
            eq(#h.popups, 2, "recycle reward shown once")
            eq(h.popups[2].title, "回收奖励", "回收使用新标题")
            h.fire("ui.LootBox", "setOnDecomposeAll", 5)
            eq(h.currency.Essence, essenceFor(5, 60, 1), "repeated Boot recycle cannot pay twice")
            eq(#h.popups, 2, "repeated Boot recycle has no duplicate popup")
            eq(#h.generated, 2, "Boot summary/claim/recycle cannot regenerate idle drops")
            countIs(h.data.lootbox, 0, 0, "Boot claim and recycle drain each reward once")
        end)
    end)
end

local function testBootSubscriberSeedOnlyClamp()
    withBoot(0, function(h)
        local complete = newEquip(90, 6, 49)
        local snapshot = copy(complete)
        LootBoxSystem.addEquipment(h.data.lootbox, complete)
        LootBoxSystem.addSeed(h.data.lootbox, 2, 6, 90)
        local idle = h.data.lootbox.seeds[2].equip
        local idleSnapshot = copy(idle)
        -- Boot 页面替身不迁移，用真实旧种子夹在两件完整装备之后验证兼容修正。
        h.data.lootbox.seeds[3] = { stageId = 2, quality = 6, level = 90, count = 2 }
        h.notify("lootbox")
        eq(LootBoxSystem.levelCap, 60, "种子上限跟随最高关卡，不随回退降低")
        countIs(h.data.lootbox, 4, 3, "subscriber preserves complete entries and pending legacy quantity")
        eq(h.data.lootbox.seeds[1].level, 90, "subscriber preserves overflow entry level")
        eq(h.data.lootbox.seeds[2].level, 90, "subscriber preserves new idle entry level")
        eq(h.data.lootbox.seeds[3].level, 60, "仅尚未 reveal 的旧种子修正到最高进度上限")
        eq(h.data.lootbox.seeds[3].equip, nil, "Boot harness leaves migration for explicit reveal")
        sameEquip(complete, snapshot, "subscriber preserves complete overflow payload")
        sameEquip(idle, idleSnapshot, "subscriber preserves complete idle payload")
        withGeneratorSpy(function(spy)
            eq(LootBoxSystem.revealLegacy(h.data.lootbox), 2, "clamped old seed reveals its full quantity")
            eq(#spy.calls, 2, "only unrevealed old pieces generated")
            for _, call in ipairs(spy.calls) do
                eq(call.level, 60, "legacy migration uses repaired level")
                eq(call.quality, 6, "legacy migration preserves quality")
            end
            countIs(h.data.lootbox, 4, 4, "migration expands old group into complete equipment")
            local before = copy(h.data.lootbox)
            spy.forbidden = true
            -- 模拟上限降低；即使曾是旧种子，reveal 后也不能再被 Boot clamp。
            h.maxStageId = 1
            h.notify("lootbox")
            eq(LootBoxSystem.levelCap, 5, "lower compatibility cap is active for unrevealed seeds")
            same(h.data.lootbox, before, "Boot clamp cannot touch any already revealed equipment")
            LootboxSchema.Fields.lootbox.onLoad(h.data.lootbox)
            same(h.data.lootbox, before, "onLoad cannot reclamp revealed legacy equipment")
            h.fire("ui.LootBox", "setOnClaimOne", 1)
            eq(h.data.equipment.inventory[tostring(complete.seq)], complete, "Boot claimOne stores original instance")
            sameEquip(complete, snapshot, "Boot single claim cannot reroll or downgrade")
            countIs(h.data.lootbox, 3, 3, "Boot singleton claim leaves remaining determined entries")
            h.fire("ui.LootBox", "setOnClaimAll", 6)
            eq(EquipmentSystem.getInventoryCount(h.data.equipment), 4, "Boot claims all remaining matching equipment")
            sameEquip(idle, idleSnapshot, "new idle stays at insertion level after Boot claim")
            for _, call in ipairs(spy.calls) do
                eq(call.equip.level, 60, "revealed old equipment stays at migration level")
                eq(h.data.equipment.inventory[tostring(call.equip.seq)], call.equip, "migrated equipment paid once")
            end
            countIs(h.data.lootbox, 0, 0, "subscriber/claim path fully drained")
        end)
    end)
end

-- 监听真实系统调用并继续执行原函数，避免只验证 UI 替身收到参数却漏掉 Boot 透传。
local function testBootQualityCallbackForwarding()
    withBoot(0, function(h)
        local claimCalls, recycleCalls = {}, {}
        local realClaim, realRecycle = LootBoxSystem.claimAll, LootBoxSystem.decomposeAll
        withPatchedField(LootBoxSystem, "claimAll", function(data, bag, quality)
            eq(data, h.data.lootbox, "Boot forwards authoritative lootbox to claimAll")
            eq(bag, h.data.equipment, "Boot forwards authoritative bag to claimAll")
            claimCalls[#claimCalls + 1] = { quality = quality }
            return realClaim(data, bag, quality)
        end, function()
            withPatchedField(LootBoxSystem, "decomposeAll", function(data, quality)
                eq(data, h.data.lootbox, "Boot forwards authoritative lootbox to decomposeAll")
                recycleCalls[#recycleCalls + 1] = { quality = quality }
                return realRecycle(data, quality)
            end, function()
                for quality = 0, 6 do
                    h.data.lootbox = qualityFixture()
                    local hidden = hiddenEntries(h.data.lootbox, quality)
                    local hiddenSnapshot = copy(hidden)
                    local beforeBag = EquipmentSystem.getInventoryCount(h.data.equipment)
                    local beforePopup, beforeGenerated = #h.popups, #h.generated
                    h.fire("ui.LootBox", "setOnClaimAll", quality)
                    eq(claimCalls[#claimCalls].quality, quality, "Boot claim callback forwards 0..6 unchanged")
                    eq(EquipmentSystem.getInventoryCount(h.data.equipment), beforeBag + (quality == 0 and 12 or 2),
                        "Boot claims only exact selection")
                    assertHiddenEntries(h.data.lootbox, hidden, hiddenSnapshot)
                    eq(#h.popups, beforePopup + 1, "Boot filtered claim shows one popup")
                    eq(h.popups[#h.popups].title, "遗匣领取", "filtered claim category")
                    for _, reward in ipairs(h.popups[#h.popups].rewards) do
                        assert(quality == 0 or reward.quality == quality, "claim popup excludes hidden quality")
                    end
                    h.fire("ui.LootBox", "setOnClaimAll", quality)
                    eq(#h.popups, beforePopup + 1, "repeated selected claim produces no reward popup")
                    assertHiddenEntries(h.data.lootbox, hidden, hiddenSnapshot)
                    eq(#h.generated, beforeGenerated, "Boot filtered claim cannot generateRandom")

                    h.data.lootbox = qualityFixture()
                    hidden = hiddenEntries(h.data.lootbox, quality)
                    hiddenSnapshot = copy(hidden)
                    local expectedEssence = 0
                    for _, entry in ipairs(h.data.lootbox.seeds) do
                        if quality == 0 or entry.quality == quality then
                            expectedEssence = expectedEssence + essenceFor(entry.quality, entry.level, 1)
                        end
                    end
                    local beforeEssence = h.currency.Essence
                    beforePopup, beforeGenerated = #h.popups, #h.generated
                    h.fire("ui.LootBox", "setOnDecomposeAll", quality)
                    eq(recycleCalls[#recycleCalls].quality, quality, "Boot recycle callback forwards 0..6 unchanged")
                    eq(h.currency.Essence, beforeEssence + expectedEssence, "Boot credits only filtered essence")
                    assertHiddenEntries(h.data.lootbox, hidden, hiddenSnapshot)
                    eq(#h.popups, beforePopup + 1, "filtered recycle shows one popup")
                    eq(h.popups[#h.popups].title, "回收奖励", "filtered recycle uses new title")
                    same(rewardTotals(h.popups[#h.popups]), { essence = expectedEssence }, "filtered recycle popup amount")
                    h.fire("ui.LootBox", "setOnDecomposeAll", quality)
                    eq(h.currency.Essence, beforeEssence + expectedEssence, "repeated selection cannot pay twice")
                    eq(#h.popups, beforePopup + 1, "empty selected recycle has no popup")
                    assertHiddenEntries(h.data.lootbox, hidden, hiddenSnapshot)
                    eq(#h.generated, beforeGenerated, "Boot filtered recycle cannot generateRandom")
                end
                eq(#claimCalls, 14, "every claim callback invokes real system exactly once")
                eq(#recycleCalls, 14, "every recycle callback invokes real system exactly once")
            end)
        end)
    end)
end

function Start()
    assert(cjson and cjson.encode and cjson.decode, "UrhoXRuntime built-in cjson is required")
    math.randomseed(20260924)
    local tests = {
        { "199/200 boundary, multiple overflow and full claims", testDeliveryBoundary },
        { "one-slot partial complete-instance claims and no duplicate payouts", testPartialFullEquipmentClaims },
        { "JSON, Schema.onLoad, consolidation, summary and full payload fidelity", testPersistenceAndConsolidation },
        { "claimOne, eager idle equipment, capacity and no claim-time generation", testClaimOneAndIdleCapacity },
        { "9999 legacy seeds migrate without loss; 10000+ rewards persist", testBeyond9999 },
        { "recycle essence, independent entries, invalid indexes and no double payment", testDecompositionAndInvalidIndexes },
        { "unrevealed claims never generate; only legacy seeds consolidate", testUnrevealedClaimsAndLegacyConsolidation },
        { "legacy reveal failure retains quantity and retries remaining pieces only", testLegacyRevealFailureRecovery },
        { "quality 0/all and 1..6 exact claims preserve hidden equipment", testExactQualityClaims },
        { "quality 0/all and 1..6 exact recycling preserves hidden equipment", testExactQualityDecomposition },
        { "real LootBox facade close/reopen and JSON onLoad never reroll", testReopenAndJsonNoReroll },
        { "real Boot first-clear success at 199 items", function() testBootSuccess(199) end },
        { "real Boot first-clear success at 200 items", function() testBootSuccess(200) end },
        { "real Boot failure keeps complete battle drops", testBootFailure },
        { "real Boot stageLoaded fallback and repeated-event idempotency", testBootStageLoadedFallback },
        { "real Boot idle equipment, claim/recycle callbacks and reward categories", testBootIdleAndClaimCallbacks },
        { "real Boot subscriber clamps only unrevealed legacy seeds", testBootSubscriberSeedOnlyClamp },
        { "real Boot forwards exact quality to claimAll/decomposeAll", testBootQualityCallbackForwarding },
    }
    for index, test in ipairs(tests) do
        local savedCap = LootBoxSystem.levelCap
        LootBoxSystem.levelCap = 0
        local ok, err = pcall(test[2])
        LootBoxSystem.levelCap = savedCap
        assert(ok, PREFIX .. "FAIL " .. test[1] .. ": " .. tostring(err))
        print(PREFIX .. "PASS " .. tostring(index) .. "/" .. tostring(#tests) .. " " .. test[1])
    end
    print(PREFIX .. "ALL PASSED (" .. tostring(#tests) .. " cases)")
end
