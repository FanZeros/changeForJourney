-- 真实LootBoxSystem/EquipmentPower/EquipmentQuery专项；File/FS与RNG均由私有夹具封闭。
local F = require("tests.InventoryCurationFixture")
local TAG = "[lootbox_curation_claim_test]"
local assertions, failures, cases = 0, 0, 0
local function check(value, label) assertions = assertions + 1; assert(value, label) end
local function eq(a, b, label) check(a == b, label .. " " .. tostring(a) .. "/" .. tostring(b)) end
local function same(a, b, label) assertions = assertions + 1; F.same(a, b, label) end
local function run(label, fn)
    cases = cases + 1
    local ok, err = pcall(fn)
    if not ok then failures = failures + 1; print(TAG .. " [FAIL] " .. label .. " " .. tostring(err))
    else print(TAG .. " [PASS] " .. label) end
end
local function naked(item)
    local out = F.copy(item)
    out.seq = nil
    return out
end
local function new()
    local h = F.new()
    h.ES = h.require("systems.EquipmentSystem")
    h.LS = h.require("systems.LootBoxSystem")
    h.Query = h.require("systems.EquipmentQuery")
    h.Power = h.require("systems.EquipmentPower")
    return h
end
local function score(h, item) return h.Power.genericScore(h.Query.hydrateCopy(item)) end

local function main()
    run("capacity constant and 499/500/501 delivery", function()
        local h = new()
        eq(h.ES.MAX_INVENTORY, 500, "capacity")
        for _, count in ipairs({ 499, 500, 501 }) do
            local bag, box = F.bag(h, count), F.box({})
            local item = F.item(h, "W1", 1)
            local destination = h.LS.deliverEquipment(box, bag, item)
            eq(destination, count < 500 and "inventory" or "lootbox", "delivery " .. count)
            eq(h.ES.getInventoryCount(bag), count < 500 and count + 1 or count, "inventory count " .. count)
            eq(#box.seeds, count < 500 and 0 or 1, "overflow count " .. count)
            eq(h.ES.isInventoryFull(bag), true, "full " .. count)
        end
        eq(h.randomCalls, 0, "deterministic delivery")
        eq(h.fileCalls, 0, "delivery no files")
    end)
    run("score descending, ties source index, stable survivors", function()
        local h = new()
        local bag = F.bag(h, 497)
        local low = F.item(h, "W1", 1)
        local high = F.item(h, "W1", 90)
        local tie = F.copy(high)
        local middle = F.item(h, "W1", 40)
        local box = F.box({ low, high, middle, tie, F.copy(low) })
        box.seeds[6] = { quality = 6, level = 90, count = 17 }
        local refs, original = {}, F.copy(box)
        for index, entry in ipairs(box.seeds) do refs[index] = entry end
        check(score(h, high) > score(h, middle) and score(h, middle) > score(h, low), "real genericScore strict ordering")
        local got, full = h.LS.claimAll(box, bag)
        eq(#got, 3, "fills available slots")
        eq(full, true, "truncated candidates")
        eq(got[1], high, "first high score actual instance")
        eq(got[2], tie, "equal score lower original index first")
        eq(got[3], middle, "middle retained selection after nonmonotonic indexes")
        eq(got[1].seq, 498, "first fresh seq")
        eq(got[2].seq, 499, "second fresh seq")
        eq(got[3].seq, 500, "third fresh seq")
        eq(#box.seeds, 3, "survivor count")
        eq(box.seeds[1], refs[1], "survivor original index1")
        eq(box.seeds[2], refs[5], "survivor original index5")
        eq(box.seeds[3], refs[6], "pending never claimed")
        same(box.seeds[1], original.seeds[1], "low source fully unchanged")
        same(box.seeds[2], original.seeds[5], "last source fully unchanged")
        same(box.seeds[3], original.seeds[6], "pending fully unchanged")
        for index, originalIndex in ipairs({ 2, 4, 3 }) do
            same(naked(got[index]), naked(original.seeds[originalIndex].equip), "claimed fields conserved except seq")
        end
        eq(h.randomCalls, 0, "score no random")
    end)
    run("all filter dimensions intersect before ranking", function()
        local h = new()
        local bag = F.bag(h, 499)
        local eligibleLow, eligibleHigh = F.item(h, "W5", 10, 5), F.item(h, "W5", 60, 5)
        local wrongQ, wrongSet = F.item(h, "W5", 90, 6), F.item(h, "W1", 90, 5)
        local cfg = h.require("config.EquipmentConfig")
        local wrongSlotId = ""
        for id, tpl in pairs(cfg.ITEMS) do
            if tpl.slot ~= eligibleLow.slot and h.Query.getSetId({ templateId = id }) == "carapace" then
                wrongSlotId = id; break
            end
        end
        check(wrongSlotId ~= "", "real set template other slot")
        local wrongSlot = F.item(h, wrongSlotId, 90, 5)
        local box = F.box({ wrongQ, eligibleLow, wrongSet, eligibleHigh, wrongSlot })
        local before, refs = F.copy(box), {}
        for i, entry in ipairs(box.seeds) do refs[i] = entry end
        local got, full = h.LS.claimAll(box, bag, { [5] = true }, { carapace = true },
            { slotFilter = eligibleLow.slot, typeFilter = eligibleLow.type })
        eq(#got, 1, "one free slot")
        eq(got[1], eligibleHigh, "highest only among eligible")
        eq(full, true, "eligible lower remains")
        for i, old in ipairs({ 1, 2, 3, 5 }) do
            eq(box.seeds[i], refs[old], "stable survivor identity")
            same(box.seeds[i], before.seeds[old], "unselected complete source unchanged")
        end
        eq(h.randomCalls, 0, "filters no random")
    end)
    run("type filter excludes higher score of another type", function()
        local h = new()
        local target = F.item(h, "W1", 1)
        local otherId = ""
        for id, tpl in pairs(h.require("config.EquipmentConfig").ITEMS) do
            if tpl.slot == target.slot and tpl.type ~= target.type then otherId = id; break end
        end
        check(otherId ~= "", "different weapon type exists")
        local other = F.item(h, otherId, 99, 6)
        local box = F.box({ other, target })
        local got = h.LS.claimAll(box, F.bag(h, 499), nil, nil, { typeFilter = target.type })
        eq(#got, 1, "only same type")
        eq(got[1], target, "filtered lower score")
        eq(box.seeds[1].equip, other, "higher excluded left intact")
    end)
    run("fullBool exact capacity, none matching, legacy, already oversized", function()
        local h = new()
        for _, count in ipairs({ 499, 500, 501 }) do
            local box, bag = F.box({ F.item(h) }), F.bag(h, count)
            local got, full = h.LS.claimAll(box, bag)
            eq(#got, count == 499 and 1 or 0, "claimed boundary " .. count)
            eq(full, count ~= 499, "fullBool only unclaimed eligible " .. count)
        end
        local bag, box = F.bag(h, 500), F.box({ F.item(h, "W1", 1, 1) })
        local got, full = h.LS.claimAll(box, bag, 6)
        eq(#got, 0, "full bag unmatched zero")
        eq(full, false, "full bag no matching candidates false")
        box = { seeds = { { quality = 6, level = 90, count = 999 } } }
        got, full = h.LS.claimAll(box, bag)
        eq(#got, 0, "pending zero")
        eq(full, false, "pending not eligible")
        eq(box.seeds[1].count, 999, "pending not generated or consumed")
        box = F.box({})
        got, full = h.LS.claimAll(box, bag)
        eq(#got, 0, "empty zero")
        eq(full, false, "empty false")
    end)
    run("lean hydration never mutates unselected corruption or original fields", function()
        local h = new()
        local lean = {
            templateId = "W1", level = 40, quality = 5, seq = 987,
            ascendLevel = 12, affixMult = 1.2, refineCount = 7, corruptCount = 1,
            corruptBaseMult = 1.1,
            corruptRevert = { baseMult = 1, affixCount = 1, patches = { { "s", 1, 0.25 } } },
            affixes = { { affixId = 1, quality = 1, value = 1.25, ascBonus = 0.1 } },
            extraOpaque = { values = { 2, 4, 6 }, text = "keep" },
        }
        local high = F.item(h, "W1", 999, 6)
        local box, bag = F.box({ lean, high }), F.bag(h, 499)
        local before, aliases = F.copy(box), F.aliases(box)
        local got = h.LS.claimAll(box, bag)
        eq(got[1], high, "strong deterministic item selected")
        same(lean, before.seeds[1].equip, "lean score projection no mutations")
        eq(lean.name, nil, "not hydrated in place")
        eq(lean.type, nil, "no derived field writes")
        for _, edge in ipairs(aliases) do
            if edge.parent ~= box.seeds then eq(edge.parent[edge.key], edge.child, "nested reference kept") end
        end
        eq(h.randomCalls, 0, "hydrateCopy corruption no random")
    end)
    run("claim selected instance preserves opaque fields and uses new seq", function()
        local h = new()
        local item = F.item(h, "W1", 50, 5)
        item.seq, item.locked, item.refineCount, item.affixMult = 4, true, 11, 1.5
        item.corruptCount, item.corruptBaseMult = 1, 1.1
        item.corruptRevert = { baseMult = 1, affixCount = 0, patches = {} }
        item.extraOpaque = { values = { "left", 7 }, flag = true }
        local before = naked(item)
        local box, bag = F.box({ item }), F.bag(h, 499)
        box.seeds[1].source, box.seeds[1].originalSeq = "curation", "0004"
        local got, full = h.LS.claimAll(box, bag)
        eq(#got, 1, "curation/locked may be reclaimed")
        eq(full, false, "exactly fills")
        eq(got[1], item, "same full object")
        eq(bag.inventory["500"], item, "new seq assigned by standard add")
        eq(item.seq, 500, "does not revive old seq")
        same(naked(item), before, "all non-seq fields conserved")
        eq(#box.seeds, 0, "single consume")
        got = h.LS.claimAll(box, bag)
        eq(#got, 0, "repeat no duplicate")
    end)
    run("single and batch recycling deny curation and lock", function()
        local h = new()
        local curation, locked, ordinary = F.item(h), F.item(h), F.item(h)
        locked.locked = true
        local box = F.box({ curation, locked, ordinary })
        box.seeds[1].source = "curation"
        box.seeds[4] = { quality = 1, level = 1, count = 55 }
        local before = F.copy(box)
        eq(h.LS.canDecompose(nil), false, "missing denied")
        eq(h.LS.canDecompose(box.seeds[1]), false, "curation denied")
        eq(h.LS.canDecompose(box.seeds[2]), false, "lock denied")
        eq(h.LS.canDecompose(box.seeds[4]), false, "pending denied")
        eq(h.LS.canDecompose(box.seeds[3]), true, "ordinary allowed")
        for _, index in ipairs({ 1, 2, 4, 999 }) do
            local essence, pieces = h.LS.decomposeOne(box, index)
            eq(essence, 0, "protected single no essence")
            eq(pieces, 0, "protected single no pieces")
            same(box, before, "protected single no mutation")
        end
        local essence, pieces = h.LS.decomposeAll(box)
        eq(pieces, 1, "only ordinary recycled")
        check(essence > 0, "ordinary essence")
        eq(#box.seeds, 3, "all protected/pending preserved")
        same(box.seeds[1], before.seeds[1], "curation all fields")
        same(box.seeds[2], before.seeds[2], "lock all fields")
        same(box.seeds[3], before.seeds[4], "pending all fields")
        essence, pieces = h.LS.decomposeAll(box)
        eq(essence, 0, "repeat no essence")
        eq(pieces, 0, "repeat no pieces")
        eq(h.randomCalls, 0, "recycle no random")
        eq(h.fileCalls, 0, "recycle no persistence calls")
    end)
    print(TAG .. " SUMMARY cases=" .. cases .. " assertions=" .. assertions .. " failures=" .. failures)
    if failures == 0 then print(TAG .. " ALL PASS") end
end
function Start()
    local ok, err = pcall(main)
    if not ok then print(TAG .. " [FAIL] harness " .. tostring(err)) end
    engine:Exit()
end
