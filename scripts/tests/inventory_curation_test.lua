-- 真实优选规划/服务/Schema/StandaloneSave专项；不加载Boot、不使用全局RNG。
-- 仅native落盘case使用独立validation HOME及专用绝对文件路径，绝不读写玩家档。
local F = require("tests.InventoryCurationFixture")
local TAG = "[inventory_curation_test]"
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
local function new()
    local h = F.new()
    h.ES = h.require("systems.EquipmentSystem")
    h.Curation = h.require("systems.InventoryCuration")
    h.Query = h.require("systems.EquipmentQuery")
    h.Power = h.require("systems.EquipmentPower")
    return h
end
local function plan(h, bag, box, options)
    local result, err = h.Curation.plan(bag, box, options)
    check(result ~= nil, "plan " .. tostring(err))
    return result
end
local function incoming(result)
    local indexes = {}
    for _, row in ipairs(result.moveIn) do indexes[#indexes + 1] = row.index end
    return indexes
end
local function outgoing(result)
    local keys = {}
    for _, row in ipairs(result.moveOut) do keys[#keys + 1] = row.key end
    return keys
end
local function naked(item)
    local out = F.copy(item)
    out.seq = nil
    return out
end
local function preview(h)
    local ok, err, receipt = h.Service.PreviewInventoryCuration(1)
    check(ok, "preview " .. tostring(err))
    check(type(receipt) == "table" and type(receipt.token) == "string" and receipt.token ~= "", "opaque preview token")
    return receipt
end
local function apply(h, token)
    local ok, err, result = h.Service.ApplyInventoryCuration(1, token)
    check(ok, "apply " .. tostring(err))
    return result
end
local function install(count)
    local h = new()
    local modules = F.modules(h, count or 500)
    modules.lootbox = F.box({ F.item(h, "W1", 60, 5), F.item(h, "W1", 50, 4) })
    modules.lootbox.seeds[1].equip.extraOpaque = { integers = { 3, 7, 11 }, text = "keep-all", flag = true }
    h:attach(modules)
    h:connectService()
    return h, h.modules
end
-- 精确标识装备对象的多重集，不靠模板/品质/score把重复物品合并。
local function objectSet(modules)
    local result, count = {}, 0
    for _, item in pairs(modules.equipment.inventory) do
        check(not result[item], "unique inventory object")
        result[item], count = naked(item), count + 1
    end
    for _, seed in ipairs(modules.lootbox.seeds) do
        if seed.equip then
            check(not result[seed.equip], "unique seed object")
            result[seed.equip], count = naked(seed.equip), count + 1
        end
    end
    return result, count
end
local function conserved(modules, original, count)
    local now, total = objectSet(modules)
    eq(total, count, "no loss count")
    for item, fields in pairs(original) do
        check(now[item] ~= nil, "original instance retained exactly once")
        same(naked(item), fields, "all non-seq fields conserved")
    end
end

local function planningTests()
    run("capacity499/500 and safe reject501, strict same-score incumbent", function()
        local h = new()
        eq(h.ES.MAX_INVENTORY, 500, "capacity500")
        local low = F.item(h)
        local high = F.item(h, "W1", 50, 5)
        local box = F.box({ high })
        local p = plan(h, F.bag(h, 499), box)
        eq(p.moveInCount, 1, "499 fill one")
        eq(p.moveOutCount, 0, "499 no eviction")
        eq(p.counts.inventoryAfter, 500, "499 final500")
        p = plan(h, F.bag(h, 500), box)
        eq(p.moveInCount, 1, "500 exchange one")
        eq(p.moveOutCount, 1, "500 exchange one old")
        eq(p.counts.inventoryAfter, 500, "500 final500")
        eq(p.moveOut[1].seq, "500", "same low score newest seq removed")
        p = plan(h, F.bag(h, 500), F.box({ low, F.copy(low) }))
        eq(p.moveInCount, 0, "equal scores cannot churn inventory")
        eq(p.moveOutCount, 0, "equal scores no eviction")
        local bag = F.bag(h, 501)
        local before = F.copy(bag)
        local denied, err = h.Curation.plan(bag, box)
        eq(denied, nil, "oversized fail closed")
        check(type(err) == "string", "oversized explains no moves")
        same(bag, before, "oversized read only")
        eq(h.randomCalls, 0, "plan no random")
    end)
    run("same slot/type/grip scores with balanced full-bag cross-group allocation", function()
        local h = new()
        local base = F.item(h, "W1", 1)
        local variants = { "slot", "type", "grip" }
        local templates = h.require("config.EquipmentConfig").ITEMS
        for _, field in ipairs(variants) do
            local selected = ""
            for id, template in pairs(templates) do
                if template[field] ~= base[field] and h.Query.getSetId({ templateId = id }) == "none" then
                    selected = id
                    break
                end
            end
            check(selected ~= "", "real different " .. field .. " template exists")
            local different = F.item(h, selected, 999, 6)
            check(h.Query.hydrateCopy(different)[field] ~= base[field], "real hydration preserves distinct " .. field)
            local p = plan(h, F.bag(h, 500), F.box({ different }))
            eq(p.moveInCount, 1, "zero allocation group may enter full bag " .. field)
            eq(p.moveOutCount, 1, "saturated group gives up one slot " .. field)
            eq(p.counts.inventoryAfter, 500, "cross-group capacity conserved " .. field)
            eq(p.moveOut[1].reason, "balance", "cross-group eviction is quota shrink " .. field)
            eq(#p.groups, 2, "still separate scoring groups " .. field)
        end
        local candidates = { F.item(h, "W1", 999, 6), F.item(h, "C1", 1, 1), F.item(h, "C1", 50, 1) }
        local p = plan(h, F.bag(h, 499), F.box(candidates))
        local accessory = {}
        for _, row in ipairs(p.moveIn) do
            if row.index ~= 1 then accessory[#accessory + 1] = row.index; eq(row.reason, "fill", "expanded group fill") end
        end
        same(accessory, { 3, 2 }, "accessory group independently takes highest first")
        eq(p.moveInCount, 3, "scarce accessory supply plus same-group weapon upgrade")
        eq(p.moveOutCount, 2, "one quota shrink and one strict upgrade")
        eq(h.randomCalls, 0, "partition no random")
    end)
    run("stable equal candidate score and deterministic repeated pure plans", function()
        local h = new()
        local bag = F.bag(h, 500)
        local item = F.item(h, "W1", 40, 3)
        local box = F.box({ F.copy(item), F.copy(item), F.copy(item) })
        local beforeBag, beforeBox = F.copy(bag), F.copy(box)
        local aliases = F.aliases({ bag, box })
        local p = plan(h, bag, box)
        same(incoming(p), { 1, 2, 3 }, "candidate source index stable tie")
        same(outgoing(p), { "500", "499", "498" }, "incumbent sequence stable tie")
        for _ = 1, 5 do same(plan(h, bag, box), p, "repeat pure plan deterministic") end
        same(bag, beforeBag, "pure source bag unchanged")
        same(box, beforeBox, "pure source box unchanged")
        F.assertAliases(aliases)
        eq(h.randomCalls, 0, "pure repeated no random")
    end)
    run("every hero equipped protected with numeric string and leading-zero seq", function()
        local h = new()
        local bag = F.bag(h, 500)
        local expected = {}
        for hero = 1, 25 do
            ---@type any 混合数字/字符串序号是本case刻意覆盖的旧档输入。
            local value = hero % 3 == 0 and string.format("%04d", hero) or (hero % 2 == 0 and tostring(hero) or hero)
            local key = hero % 2 == 0 and tostring(hero) or hero
            bag.equipped[key] = { weapon = value }
            expected[tostring(hero)] = true
        end
        local many = {}
        for _ = 1, 500 do many[#many + 1] = F.item(h, "W1", 90, 6) end
        local p = plan(h, bag, F.box(many))
        eq(p.protected.inventory, 25, "all25 hero mappings protected, not just active team")
        eq(p.protected.reasons.equipped, 25, "equipped reason count")
        eq(p.moveOutCount, 475, "only unbound old items may leave")
        for _, row in ipairs(p.moveOut) do check(not expected[row.seq], "bound seq never moved") end
        eq(h.randomCalls, 0, "all heroes no random")
    end)
    run("locks investment corruption pending and set protect full object", function()
        local h = new()
        local updates = {
            function(item) item.locked = true end,
            function(item) item.ascendLevel = 1 end,
            function(item) item.enhanceLevel = 1 end,
            function(item) item.refineCount = 1 end,
            function(item) item.affixMult = 1.1 end,
            function(item) item.ascBonus = 0.1 end,
            function(item) item.affixes = { { affixId = 1, quality = 1, value = 2, ascBonus = 0.1 } } end,
            function(item) item.corruptCount = 1 end,
            function(item) item.corruptBaseMult = 1.1 end,
            function(item) item.corruptRevert = { baseMult = 1, affixCount = 0, patches = {} } end,
            function(item) item.corruptOriginalAffixes = {} end,
            function(item) item.corruptOriginalBaseMult = 1 end,
            function(item) item.ascendLevel = "historical-unknown" end,
            function(item) item.templateId = "W5"; item.name = nil; item.type = nil; item.slot = nil end,
        }
        local bag = F.bag(h, 500)
        for i, update in ipairs(updates) do update(bag.inventory[tostring(i)]) end
        local pendingSeq = tostring(#updates + 1)
        local p = plan(h, bag, F.box({ F.item(h, "W1", 999, 6) }), {
            hasPendingRefine = function(seq) return seq == pendingSeq end,
        })
        eq(p.protected.inventory, #updates + 1, "all protected rows counted once")
        check(p.reasons.locked >= 1 and p.reasons.investment >= 1 and p.reasons.corruption >= 1
            and p.reasons.pendingRefine >= 1 and p.reasons.set >= 1, "all protection categories")
        for _, row in ipairs(p.moveOut) do check(tonumber(row.seq) > #updates + 1, "protected seq never leave") end
        -- 仅有套装库存的配额不可被同组高分普通件挤掉。
        local setBag = F.bag(h, 500, "W5")
        p = plan(h, setBag, F.box({ F.item(h, "W1", 999, 6) }))
        eq(p.protectedCount, 500, "all set pieces protected")
        eq(p.moveOutCount, 0, "set incumbent not evicted")
        eq(p.moveInCount, 0, "no room despite higher generic score")
    end)
    run("protected seed may enter but dangling equipped/pending seed stays", function()
        local h = new()
        local items = { F.item(h, "W5", 50, 5), F.item(h, "W1", 40, 4), F.item(h, "W1", 30, 3), F.item(h, "W1", 20, 2) }
        items[2].locked = true
        items[3].seq, items[4].seq = 900, 901
        local bag = F.bag(h, 496)
        bag.equipped[25] = { weapon = "0900" }
        local box = F.box(items)
        box.seeds[4].originalSeq = "00901"
        local p = plan(h, bag, box, { hasPendingRefine = function(seq) return seq == "901" end })
        local selected = {}
        for _, row in ipairs(p.moveIn) do selected[row.index] = true end
        eq(selected[1], true, "set item may enter empty inventory")
        eq(selected[2], true, "locked item may enter")
        eq(selected[3], nil, "dangling equipped seed stays")
        eq(selected[4], nil, "pending source seq seed stays")
        eq(items[2].locked, true, "plan never unlocks")
    end)
    run("inconsistent inventory seq and both seed seq aliases protected", function()
        local h = new()
        local bag = F.bag(h, 500)
        bag.inventory["500"].seq = 2
        local p = plan(h, bag, F.box({ F.item(h, "W1", 999, 6) }), {
            hasPendingRefine = function(seq) return seq == "2" end,
        })
        check((p.reasons.invalid or 0) >= 1, "key/instance mismatch invalid")
        for _, row in ipairs(p.moveOut) do check(row.key ~= "500" and row.key ~= "2", "both pending identity aliases kept") end
        bag = F.bag(h, 500)
        bag.equipped[25] = { weapon = "0002" }
        bag.inventory["500"].seq = 2
        p = plan(h, bag, F.box({ F.item(h, "W1", 999, 6) }))
        for _, row in ipairs(p.moveOut) do check(row.key ~= "500" and row.key ~= "2", "all equipped aliases kept") end
        bag = F.bag(h, 498)
        bag.equipped[25] = { weapon = "0900" }
        local a, b = F.item(h, "W1", 99, 6), F.item(h, "W1", 98, 6)
        a.seq, b.seq = 900, 902
        local box = F.box({ a, b })
        box.seeds[1].originalSeq, box.seeds[2].originalSeq = "901", "903"
        p = plan(h, bag, box, { hasPendingRefine = function(seq) return seq == "903" end })
        eq(p.moveInCount, 0, "separate originalSeq and instance seq both audited")
        check(p.reasons.equipped >= 1 and p.reasons.pendingRefine >= 1, "both seed aliases protection reasons")
    end)
    run("legacy unknown sparse duplicate and ambiguous source fail safely", function()
        local h = new()
        local bag = F.bag(h, 0)
        local box = { seeds = { { quality = 6, level = 99, count = 999 },
            { quality = 1, level = 1, count = 1, equip = { templateId = "missing", opaque = { 1, 2 } } } } }
        local before = F.copy(box)
        local p = plan(h, bag, box)
        eq(p.counts.legacyPending, 1, "legacy one row not999 random rolls")
        eq(p.moveInCount, 0, "unknown/pending never generated")
        same(box, before, "invalid source unchanged")
        local dup = F.bag(h, 1)
        dup.inventory[1] = F.item(h)
        eq(h.Curation.plan(dup, F.box({})), nil, "same numeric/string seq ambiguous denied")
        dup = F.bag(h, 1)
        dup.inventory["0001"] = F.item(h)
        eq(h.Curation.plan(dup, F.box({})), nil, "leading zero alias denied")
        local shared = F.item(h)
        eq(h.Curation.plan({ inventory = { ["1"] = shared }, equipped = {}, nextSeq = 2 }, F.box({ shared })), nil,
            "same full instance in bag and seed denied")
        eq(h.Curation.plan(bag, { seeds = { [1] = {}, [3] = {} } }), nil, "sparse seed array denied")
        eq(h.randomCalls, 0, "invalid no random")
    end)
end

local function groupForItem(h, result, item)
    local view = h.Query.hydrateCopy(item)
    for _, group in ipairs(result.groups) do
        if group.slot == view.slot and group.type == view.type and group.grip == view.grip then return group end
    end
    error("missing planned group " .. tostring(view.slot))
end
local function slotCounts(result)
    local counts = {}
    for _, group in ipairs(result.groups) do counts[group.slot] = (counts[group.slot] or 0) + group.inventory end
    return counts
end
-- 从原始源重算最终选择，不依赖规划器的target自行证明容量/每组最高分。
local function assertSelection(h, bag, box, result)
    local removed, selected, byGroup, originalGroups = {}, {}, {}, {}
    for _, row in ipairs(result.moveOut) do removed[row.key] = true end
    for _, row in ipairs(result.moveIn) do selected[row.index] = true end
    local count = 0
    for key, item in pairs(bag.inventory) do
        local group = groupForItem(h, result, item)
        originalGroups[group.key] = (originalGroups[group.key] or 0) + 1
        if not removed[key] then
            count = count + 1
            byGroup[group.key] = (byGroup[group.key] or 0) + 1
        end
    end
    for index, seed in ipairs(box.seeds) do
        if selected[index] then
            count = count + 1
            local group = groupForItem(h, result, seed.equip)
            byGroup[group.key] = (byGroup[group.key] or 0) + 1
        end
    end
    eq(count, result.counts.inventoryAfter, "actual selected count matches receipt")
    check(count <= 500, "actual selected count bounded")
    for _, group in ipairs(result.groups) do
        eq(byGroup[group.key] or 0, group.inventory, "group actual final count")
        eq(group.target, group.inventory, "group target is final inventory count")
        check(group.inventory >= group.protected, "protected lower respected")
        local minKept, maxDropped = math.huge, -math.huge
        local droppedOriginal = 0
        for key, item in pairs(bag.inventory) do
            if groupForItem(h, result, item).key == group.key then
                local score = h.Power.genericScore(h.Query.hydrateCopy(item))
                if removed[key] then maxDropped = math.max(maxDropped, score); droppedOriginal = droppedOriginal + 1
                elseif not item.locked and h.Query.getSetId(item) == "none" then minKept = math.min(minKept, score) end
            end
        end
        for index, seed in ipairs(box.seeds) do
            if groupForItem(h, result, seed.equip).key == group.key then
                local score = h.Power.genericScore(h.Query.hydrateCopy(seed.equip))
                if selected[index] then minKept = math.min(minKept, score) else maxDropped = math.max(maxDropped, score) end
            end
        end
        check(minKept >= maxDropped, "each group selects its highest available score")
        if droppedOriginal > 0 and group.inventory >= (originalGroups[group.key] or 0) then
            for key, item in pairs(bag.inventory) do
                if removed[key] and groupForItem(h, result, item).key == group.key then
                    check(minKept > h.Power.genericScore(h.Query.hydrateCopy(item)), "unchanged/growing quota only strict upgrades")
                end
            end
        end
    end
end

local function balancedPlanningTests()
    run("500 high weapons admit a lower-score scarce accessory without loss", function()
        local h = new()
        local bag = F.bag(h, 500)
        for key in pairs(bag.inventory) do
            local item = F.item(h, "W1", 9999)
            item.seq = tonumber(key)
            bag.inventory[key] = item
        end
        local accessory = F.item(h, "C1", 1)
        check(h.Power.genericScore(h.Query.hydrateCopy(accessory)) < h.Power.genericScore(h.Query.hydrateCopy(bag.inventory["1"])),
            "incoming accessory really has lower general score")
        local box = F.box({ accessory })
        local before, aliases = F.copy({bag, box}), F.aliases({bag, box})
        local p = plan(h, bag, box)
        same(incoming(p), {1}, "zero-slot accessory admitted")
        same(outgoing(p), {"500"}, "quota shrink retains earlier equal weapons")
        eq(p.moveOut[1].reason, "balance", "not a cross-type score comparison")
        same(slotCounts(p), {weapon=499, accessory=1}, "scarce supply returns surplus to weapons")
        assertSelection(h, bag, box, p)
        same({bag, box}, before, "lower-score rebalance is pure")
        F.assertAliases(aliases)
        eq(h.randomCalls, 0, "lower-score no RNG")
    end)
    run("six-slot absolute waterfill then subtype and grip waterfill with per-group highest", function()
        local h = new()
        local EC = h.require("config.EquipmentConfig")
        -- 私有夹具模板单独覆盖同type不同grip，正式配置/生产文件不修改。
        EC.ITEMS.CURATION_GRIP = F.copy(EC.ITEMS.W1)
        EC.ITEMS.CURATION_GRIP.id, EC.ITEMS.CURATION_GRIP.grip = "CURATION_GRIP", "twohand"
        local box = {seeds={}}
        for _, id in ipairs({"W1", "W7", "CURATION_GRIP", "O1", "O7", "A1", "H1", "S1", "C1"}) do
            for i = 1, 100 do
                local item = F.item(h, id, i, 1)
                box.seeds[#box.seeds+1] = {equip=item, count=1, quality=item.quality, level=item.level}
            end
        end
        local bag = F.bag(h, 500)
        local before, aliases = F.copy({bag, box}), F.aliases({bag, box})
        local p = plan(h, bag, box)
        same(slotCounts(p), {weapon=84, offhand=84, armor=83, helmet=83, shoes=83, accessory=83}, "EC.SLOTS fixed remainder tie")
        local weapon, offhand = {}, {}
        for _, group in ipairs(p.groups) do
            if group.slot == "weapon" then weapon[#weapon+1] = group.inventory end
            if group.slot == "offhand" then offhand[#offhand+1] = group.inventory end
        end
        same(weapon, {28,28,28}, "weapon slot split by type and grip")
        same(offhand, {42,42}, "offhand subtypes split independently")
        eq(p.counts.inventoryAfter, 500, "two-layer final500")
        eq(p.counts.inventoryBefore + p.counts.lootboxBefore, p.counts.inventoryAfter + p.counts.lootboxAfter, "combined count conserved")
        assertSelection(h, bag, box, p)
        same(plan(h, bag, box), p, "two-layer ties deterministic")
        same({bag, box}, before, "all deep source fields unchanged")
        F.assertAliases(aliases)
        eq(h.randomCalls, 0, "two-layer score no RNG")
    end)
    run("scarce subtype surplus returns within slot and blocked seeds provide no supply", function()
        local h = new()
        local bag = F.bag(h, 500)
        local items = {}
        for i = 1, 3 do items[#items+1] = F.item(h, "W7", i) end
        for i = 1, 7 do items[#items+1] = F.item(h, "C1", i) end
        for i = 1, 200 do items[#items+1] = F.item(h, "O1", i) end
        local box = F.box(items)
        for i = 11, #box.seeds do box.seeds[i].count = 2 end -- 完整对象但count非法，不算upper。
        box.seeds[#box.seeds+1] = {quality=6, level=999, count=500} -- legacy不生成。
        local p = plan(h, bag, box)
        same(slotCounts(p), {weapon=493, accessory=7, offhand=0}, "invalid/legacy upper excluded and scarce slot surplus returns")
        eq(groupForItem(h, p, F.item(h,"W7")).inventory, 3, "scarce weapon subtype capped at three")
        eq(groupForItem(h, p, bag.inventory["1"]).inventory, 490, "weapon surplus returned to abundant subtype")
        eq(p.counts.legacyPending, 1, "legacy pending retained")
        eq(p.protected.lootbox, 203, "200 invalid complete rows plus three valid set seeds protected")
        eq(p.moveInCount, 10, "only eligible ten admitted")
        eq(p.moveOutCount, 10, "ten displaced to reliquary")
        eq(p.counts.inventoryAfter, 500, "no holes from insufficient supply")
    end)
    run("protected absolute lower, unclassified occupancy and all-protected full no-op", function()
        local h = new()
        local bag = F.bag(h, 500)
        for i = 1, 300 do bag.inventory[tostring(i)].locked = true end
        local items = {}
        for _ = 1, 400 do items[#items+1] = F.item(h,"C1",1) end
        local p = plan(h, bag, F.box(items))
        same(slotCounts(p), {weapon=300, accessory=200}, "absolute protected300, not protection plus equal new100")
        eq(p.protectedCount, 300, "protected lower counted")
        for _, row in ipairs(p.moveOut) do check(tonumber(row.seq)>300, "all original locked preserved") end
        local subtypeItems = {}
        for _ = 1, 400 do subtypeItems[#subtypeItems+1] = F.item(h,"W31",1) end
        local subtypePlan = plan(h, bag, F.box(subtypeItems))
        eq(groupForItem(h,subtypePlan,bag.inventory["1"]).inventory,300,"subtype absolute protected lower300")
        eq(groupForItem(h,subtypePlan,subtypeItems[1]).inventory,200,"subtype waterfill not protection plus equal extra")
        eq(subtypePlan.counts.inventoryAfter,500,"subtype lower preserves full capacity")
        for i = 1, 17 do bag.inventory[tostring(i)] = {seq=i, templateId="missing", opaque={index=i}} end
        for i = 18, 500 do bag.inventory[tostring(i)].locked = nil end
        p = plan(h, bag, F.box(items))
        same(slotCounts(p), {weapon=242, accessory=241}, "U17 leaves483 allocatable with fixed slot tie")
        eq(p.protectedCount, 17, "unclassified inventory protected")
        eq(p.counts.inventoryAfter, 500, "U consumes capacity exactly once")
        for _, row in ipairs(p.moveOut) do check(tonumber(row.seq)>17, "unclassified originals stay") end
        for _, item in pairs(bag.inventory) do item.locked = true end
        local before = F.copy(bag)
        p = plan(h, bag, F.box(items))
        eq(p.protectedCount, 500, "full protected500 including unknown")
        eq(p.moveInCount, 0, "no incoming when no releasable capacity")
        eq(p.moveOutCount, 0, "all protected no outgoing")
        eq(p.changed, false, "all protected no-op")
        same(bag, before, "all protected source unchanged")
        eq(h.randomCalls, 0, "protected and unclassified no RNG")
    end)
end

local function serviceTests()
    run("preview read-only, successful transfer lossless and one notification each", function()
        local h, modules = install(500)
        local before, aliases = F.copy(modules), F.aliases(modules)
        local objects, count = objectSet(modules)
        local incomingItem = modules.lootbox.seeds[1].equip
        local p = preview(h)
        same(modules, before, "preview all fields unchanged")
        F.assertAliases(aliases)
        eq(h.flushCalls, 0, "preview no Flush")
        eq(#h.notificationOrder, 0, "preview no notifications")
        eq(p.moveInCount, 2, "two upgrades")
        apply(h, p.token)
        eq(h.ES.getInventoryCount(modules.equipment), 500, "final capacity")
        eq(#modules.lootbox.seeds, 2, "two original moved out")
        eq(h.flushCalls, 1, "one Flush")
        eq(h.pushes.equipment, 1, "equipment notification once")
        eq(h.pushes.lootbox, 1, "lootbox notification once")
        eq(#h.notificationOrder, 2, "no unrelated notification")
        check(h.committed, "virtual atomic Rename reached")
        check(modules.equipment.inventory[tostring(incomingItem.seq)] == incomingItem, "actual incoming object retained")
        check(incomingItem.seq > 500, "new monotonic seq")
        for _, seed in ipairs(modules.lootbox.seeds) do
            eq(seed.source, "curation", "safe recovery source")
            check(seed.originalSeq ~= nil, "original seq recorded in seed")
        end
        conserved(modules, objects, count)
        eq(h.randomCalls, 0, "transaction no random")
        local after, disk, pushes, flushes = F.copy(modules), F.copy(h.disk), #h.notificationOrder, h.flushCalls
        eq(h.Service.ApplyInventoryCuration(1, p.token), false, "duplicate confirm rejected")
        same(modules, after, "duplicate no mutation")
        same(h.disk, disk, "duplicate no save")
        eq(h.flushCalls, flushes, "duplicate no Flush")
        eq(#h.notificationOrder, pushes, "duplicate no notification")
        h:resetNotifications()
        local p2 = preview(h)
        eq(p2.changed, false, "postapply fresh plan idempotent")
        apply(h, p2.token)
        same(modules, after, "no-op leaves modules")
        eq(h.Service.ApplyInventoryCuration(1, p2.token), false, "no-op consumes token")
    end)
    for _, failure in ipairs({ "false", "nil", "throw" }) do
        run("Flush " .. failure .. " original aliases restored, same token retry", function()
            local h, modules = install(500)
            local p = preview(h)
            local before, aliases = F.copy(modules), F.aliases(modules)
            local state = h.require("core.GameState").exportSave()
            local previousDisk = F.copy(h.disk)
            h.failure = failure
            eq(h.Service.ApplyInventoryCuration(1, p.token), false, "failed persistence refused")
            same(modules, before, "entire graph value rollback")
            F.assertAliases(aliases)
            same(h.require("core.GameState").exportSave(), state, "GameState unchanged")
            same(h.disk, previousDisk, "failed commit no saved candidate")
            eq(#h.notificationOrder, 0, "failure no notification")
            eq(h.flushCalls, 1, "one attempted Flush")
            h.failure = ""
            apply(h, p.token)
            eq(h.flushCalls, 2, "same token successful retry")
            eq(h.pushes.equipment, 1, "retry equipment once")
            eq(h.pushes.lootbox, 1, "retry lootbox once")
            eq(h.randomCalls, 0, "rollback retry no random")
        end)
    end
    run("persist partial callback mutations rollback every original alias", function()
        local h, modules = install(500)
        h.Service.SetPersistCallback(function()
            modules.session.lastOnlineTime = 99999
            modules.heroes.roster[1].level = 999
            modules.equipment.inventory.extra = { unexpected = true }
            modules.lootbox.seeds = { { unexpected = true } }
            modules.currency.gold = 777
            modules.player = { overwritten = true }
            error("expected callback after partial mutation")
        end)
        local p = preview(h)
        local before, aliases = F.copy(modules), F.aliases(modules)
        local state = h.require("core.GameState").exportSave()
        eq(h.Service.ApplyInventoryCuration(1, p.token), false, "partial callback throw refused")
        same(modules, before, "all module graph values restored")
        F.assertAliases(aliases)
        same(h.require("core.GameState").exportSave(), state, "game state unaffected")
        eq(#h.notificationOrder, 0, "partial failure no notification")
    end)
    run("begin hook refuses without acquiring or clearing unrelated queue", function()
        for _, mode in ipairs({ "false", "throw" }) do
            local h, modules = install(500)
            local finished, saved = 0, 0
            h.Service.SetPersistCallback(function() saved = saved + 1; return true end, {
                begin = function() if mode == "throw" then error("expected occupied transaction") end; return false end,
                finish = function() finished = finished + 1 end,
            })
            local p = preview(h)
            local before, aliases = F.copy(modules), F.aliases(modules)
            eq(h.Service.ApplyInventoryCuration(1, p.token), false, "unacquired transaction rejected")
            same(modules, before, "begin failure no mutation")
            F.assertAliases(aliases)
            eq(saved, 0, "begin failure no persist")
            eq(finished, 0, "must not clear someone else's queue")
        end
    end)
    local staleCases = {
        { "new drop", function(h, m) h.require("systems.LootBoxSystem").addEquipment(m.lootbox, F.item(h, "W1", 70)) end },
        { "inventory locked", function(_, m) m.equipment.inventory["500"].locked = true end },
        { "seed locked", function(_, m) m.lootbox.seeds[1].equip.locked = true end },
        { "equipped by nonactive hero", function(_, m) m.equipment.equipped[25] = { weapon = "0500" } end },
        { "decomposed inventory", function(_, m) m.equipment.inventory["500"] = nil end },
        { "decomposed seed", function(h, m) h.require("systems.LootBoxSystem").decomposeOne(m.lootbox, 2) end },
        { "equipment replaced equal table", function(h, m) m.equipment = F.copy(m.equipment); h.PDM.AttachLocalModules(1, m) end },
        { "lootbox replaced equal table", function(h, m) m.lootbox = F.copy(m.lootbox); h.PDM.AttachLocalModules(1, m) end },
        { "nested candidate replaced equal table", function(_, m) m.lootbox.seeds[1].equip = F.copy(m.lootbox.seeds[1].equip) end },
        { "ttl expired", function(h) h:setTime(h.clock + 121) end },
        { "latest preview invalidates old token", function(h) preview(h) end },
    }
    for _, case in ipairs(staleCases) do
        run("stale preview " .. case[1], function()
            local h, modules = install(500)
            local p = preview(h)
            case[2](h, modules)
            local before, aliases = F.copy(modules), F.aliases(modules)
            eq(h.Service.ApplyInventoryCuration(1, p.token), false, "stale rejected")
            same(modules, before, "stale action no mutation")
            F.assertAliases(aliases)
            eq(h.flushCalls, 0, "stale no Flush")
            eq(#h.notificationOrder, 0, "stale no notification")
            eq(h.randomCalls, 0, "stale no random")
        end)
    end
    run("notified same-value ABA invalidated by real Store revision", function()
        for _, name in ipairs({ "equipment", "lootbox" }) do
            local h, modules = install(500)
            local p = preview(h)
            local store = h.require("core.PlayerStore")
            local revision = store.GetRevision(name)
            h.Dispatcher.notifySubscribers(name)
            check(store.GetRevision(name) > revision, "real notification advances revision")
            local before = F.copy(modules)
            eq(h.Service.ApplyInventoryCuration(1, p.token), false, "notified ABA rejected even exact values/edges")
            same(modules, before, "ABA no mutation")
            eq(h.flushCalls, 0, "ABA no Flush")
        end
    end)
    run("observed ABA cannot resurrect invalidated token", function()
        local h, modules = install(500)
        local p = preview(h)
        local source = modules.equipment.inventory["500"]
        source.locked = true
        eq(h.Service.ApplyInventoryCuration(1, p.token), false, "observed changed state rejected")
        source.locked = nil
        eq(h.Service.ApplyInventoryCuration(1, p.token), false, "returned equal state cannot revive token")
        eq(h.flushCalls, 0, "ABA no Flush")
    end)
    run("cancel and another uid cannot apply old token", function()
        local h, modules = install(500)
        local p = preview(h)
        eq(h.Service.ApplyInventoryCuration(2, p.token), false, "other uid cannot borrow preview")
        h.Service.CancelInventoryCuration(1, p.token)
        eq(h.Service.ApplyInventoryCuration(1, p.token), false, "cancelled cannot apply")
        eq(h.flushCalls, 0, "cancel no save")
        eq(h.ES.getInventoryCount(modules.equipment), 500, "cancel preserves bag")
    end)
    run("real Blacksmith pending blocks old source and allocator skips orphan pending", function()
        local h, modules = install(500)
        local BS = h.require("rules.blacksmith.BlacksmithService")
        local ES = h.ES
        local temporary = F.item(h, "W1", 1, 2)
        temporary.seq = 501
        temporary.affixes = { { affixId = 1, key = "str", quality = 1, value = 2 } }
        modules.equipment.inventory["501"] = temporary
        modules.currency.essence = 1000000
        -- 只替换洗练的随机生成叶子；私有pending仍由真实RefineEquip创建、真实hasPendingRefine读取。
        local roll = ES.rollAffixesForRefine
        ES.rollAffixesForRefine = function(list) return F.copy(list) end
        local mark = h.PDM.MarkDirty
        h.PDM.MarkDirty = function() end
        local refined, refineErr = BS.RefineEquip(1, 501)
        ES.rollAffixesForRefine, h.PDM.MarkDirty = roll, mark
        check(refined, "real pending created " .. tostring(refineErr))
        check(BS.hasPendingRefine(1, "00501"), "real pending canonical lookup")
        modules.equipment.inventory["501"] = nil -- 旧待定号未出现在库存/遗匣/穿戴中，不能被新物重挂。
        local p = preview(h)
        apply(h, p.token)
        check(modules.equipment.inventory["501"] == nil, "allocator skips orphan pending501")
        check(modules.equipment.inventory["502"] ~= nil, "first real item gets502")
        check(BS.hasPendingRefine(1, 501), "curation never consumes pending result")
        h:resetNotifications()
        p = preview(h)
        -- 已进入仓库的实例新号与pending501不同；给真实pending持有的完整源放回遗匣。
        modules.lootbox.seeds[#modules.lootbox.seeds + 1] = { quality = temporary.quality, level = 1, count = 1,
            equip = temporary, originalSeq = "501", source = "curation" }
        p = preview(h)
        check((p.reasons.pendingRefine or 0) >= 1, "real pending source counted protected")
        BS.Cleanup(1)
        eq(BS.hasPendingRefine(1, 501), false, "real cleanup clears private pending")
        local before = F.copy(modules)
        eq(h.Service.ApplyInventoryCuration(1, p.token), false, "pending status change invalidates otherwise unchanged source")
        same(modules, before, "pending-only stale no mutation")
        eq(h.randomCalls, 0, "no RNG including deterministic pending leaf")
    end)
    run("sequence canonicalization unsafe ids and fresh allocation monotonic", function()
        local h = new()
        eq(h.Curation.sequence("00012"), "12", "leading zeros canonical")
        eq(h.Curation.sequence(12), "12", "numeric canonical")
        for _, value in ipairs({ 0, -1, 1.5, "nan", math.huge, 9007199254740991, "9007199254740992" }) do
            eq(h.Curation.sequence(value), nil, "unsafe seq rejected " .. tostring(value))
        end
        local modules = F.modules(h, 500)
        modules.equipment.nextSeq = 1 -- 历史落后的计数不能覆盖已有物品。
        modules.equipment.equipped[25] = { weapon = "0800" }
        modules.lootbox = F.box({ F.item(h, "W1", 50, 5) })
        modules.lootbox.seeds[1].originalSeq = "00900"
        modules.lootbox.seeds[1].equip.seq = 850
        h:attach(modules)
        h:connectService()
        local p = preview(h)
        local selected = modules.lootbox.seeds[1].equip
        apply(h, p.token)
        eq(selected.seq, 901, "new seq above bag/equipped/source/audit even with lagging nextSeq")
        eq(modules.equipment.nextSeq, 902, "nextSeq advances beyond assignment")
        eq(h.ES.getInventoryCount(modules.equipment), 500, "no overwrite loss")
        for _, unsafe in ipairs({ 0, -1, 2.5, "not-seq", 9007199254740991 }) do
            local other, m = install(500)
            m.equipment.nextSeq = unsafe
            local receipt = preview(other)
            local before, aliases = F.copy(m), F.aliases(m)
            eq(other.Service.ApplyInventoryCuration(1, receipt.token), false, "bad allocator input fail closed")
            same(m, before, "bad sequence preserves all fields")
            F.assertAliases(aliases)
            eq(other.flushCalls, 0, "bad sequence no Flush")
        end
    end)
    run("unconfigured persistence fails closed", function()
        local h, modules = install(500)
        h.Service.SetPersistCallback(nil)
        local p = preview(h)
        local before = F.copy(modules)
        eq(h.Service.ApplyInventoryCuration(1, p.token), false, "without Flush fails")
        same(modules, before, "no persistence no move")
        eq(#h.notificationOrder, 0, "no persistence no notification")
    end)
end

local function balancedServiceTests()
    run("partial protected seed lower is idempotent while movable capacity remains", function()
        local h = new()
        local modules = F.modules(h, 500)
        for i = 1, 50 do modules.equipment.inventory[tostring(i)].locked = true end
        local items = {}
        for _ = 1, 20 do
            local item = F.item(h,"W1",500); item.locked=true; items[#items+1]=item
        end
        for _, id in ipairs({"W31", "O1", "C1"}) do
            for i = 1, 300 do
                local item = F.item(h,id,i)
                if id=="C1" and i>280 then item.locked=true end
                items[#items+1]=item
            end
        end
        modules.lootbox=F.box(items)
        h:attach(modules); h:connectService()
        local p=preview(h)
        same(slotCounts(p),{weapon=167,offhand=167,accessory=166},"partial-protected three-slot fixed tie")
        local swordQuota = groupForItem(h,p,modules.equipment.inventory["1"]).inventory
        check(swordQuota==83 or swordQuota==84,"weapon subtypes split167 with stable remainder")
        apply(h,p.token)
        local after=F.copy(modules)
        local flushes=h.flushCalls
        h:resetNotifications()
        local p2=preview(h)
        eq(p2.protectedCount,257,"50 incumbents plus20 sword plus20 accessory and167 set offhands protected")
        check(p2.protectedCount<500,"regression really retains movable capacity")
        same(slotCounts(p2),slotCounts(p),"partial-protected slot lower growth keeps absolute quota")
        for index,group in ipairs(p.groups) do eq(p2.groups[index].inventory,group.inventory,"partial-protected subtype quota stable") end
        eq(p2.changed,false,"partial-protected second plan no churn")
        apply(h,p2.token)
        same(modules,after,"partial-protected second apply graph stable")
        eq(h.flushCalls,flushes,"partial-protected no second write")
        eq(#h.notificationOrder,0,"partial-protected no second publish")
        eq(h.randomCalls,0,"partial-protected no RNG")
    end)
    run("protected seeds become lower without two-round slot or subtype drift", function()
        local h = new()
        local modules = F.modules(h, 500)
        local items = {}
        for _, id in ipairs({"W5", "O1", "A1", "H1", "S1", "C1"}) do
            for i = 1, 100 do
                local item = F.item(h, id, 100+i)
                if id == "O1" then item.locked = true end
                if id == "C1" then
                    if i%2 == 0 then item.refineCount = 1 else item.corruptCount = 1 end
                end
                items[#items+1] = item
            end
        end
        modules.lootbox = F.box(items)
        h:attach(modules); h:connectService()
        local original, count = objectSet(modules)
        local p = preview(h)
        same(slotCounts(p), {weapon=84, offhand=84, armor=83, helmet=83, shoes=83, accessory=83}, "first protected-seed allocation")
        apply(h, p.token)
        conserved(modules, original, count)
        local after, disk = F.copy(modules), F.copy(h.disk)
        h:resetNotifications()
        local p2 = preview(h)
        same(slotCounts(p2), slotCounts(p), "new protected lower does not repartition absolute slots")
        eq(p2.protectedCount, 500, "every selected protected seed now original protected inventory")
        eq(p2.changed, false, "second preview idempotent")
        eq(p2.moveInCount, 0, "second incoming0")
        eq(p2.moveOutCount, 0, "second outgoing0")
        apply(h, p2.token)
        same(modules, after, "second apply no fields or seq drift")
        same(h.disk, disk, "second apply no rewrite")
        eq(h.flushCalls, 1, "only first apply flushed")
        eq(#h.notificationOrder, 0, "idempotent apply no notification")
        eq(h.randomCalls, 0, "protected seed rounds no RNG")
    end)
    run("balanced service real native save conservation and failed Rename rollback", function()
        local h = new()
        local modules = F.modules(h, 500)
        local items = {}
        for _, id in ipairs({"O1", "A1", "H1", "S1", "C1"}) do
            for i = 1, 100 do items[#items+1] = F.item(h,id,i) end
        end
        modules.lootbox = F.box(items)
        local identity = 0
        local function mark(item)
            identity = identity + 1
            item.curationValidationId = tostring(identity)
            item.opaqueValidation = {tag="native-curation", values={identity,7,11}, flag=true}
        end
        for _, item in pairs(modules.equipment.inventory) do mark(item) end
        for _, seed in ipairs(modules.lootbox.seeds) do mark(seed.equip) end
        h:attach(modules); h:connectService()
        -- 唯一native委托在本case；Runtime由launcher以独立HOME运行。
        -- 正式保存逻辑仍传standalone文件名，但此封闭映射只操作专项文件，从不接触玩家档。
        local validationDir = "/home/Maker/power-curation-validation-20261017/native-data/"
        local paths = { ["standalone_save.json"]=validationDir .. "inventory_curation_validation.json",
            ["standalone_save.pending.json"]=validationDir .. "inventory_curation_validation.pending.json" }
        local function path(name)
            local mapped = paths[name]
            assert(mapped, "native path outside test allowlist")
            return mapped
        end
        local nativeFs, nativeFile = fileSystem, File
        check(nativeFs:CreateDir(validationDir), "dedicated native validation directory")
        h.env.File = function(name, mode) h.fileCalls=h.fileCalls+1; return nativeFile(path(name), mode) end
        h.env.fileSystem = {
            FileExists=function(_,name) return nativeFs:FileExists(path(name)) end,
            Delete=function(_,name) return nativeFs:Delete(path(name)) end,
            Rename=function(_,from,to)
                eq(from,"standalone_save.pending.json","real Flush pending path")
                eq(to,"standalone_save.json","real Flush final path")
                if h.rejectNativeRename then return false end
                local success = nativeFs:Rename(path(from),path(to))
                h.committed = success == true
                return success
            end,
        }
        local function saved()
            local file = nativeFile(paths["standalone_save.json"],FILE_READ)
            check(file and file:IsOpen(), "native save physically exists")
            local text = file:ReadString()
            file:Close(); file:Dispose()
            check(type(text)=="string" and #text>0,"native save bytes readable")
            return text, cjson.decode(text)
        end
        check(h.Save.Flush(), "real Flush baseline saved to native disk")
        local baseline = saved()
        local p = preview(h)
        same(slotCounts(p), {weapon=84, offhand=84, armor=83, helmet=83, shoes=83, accessory=83}, "native plan balanced six slots")
        local before, aliases = F.copy(modules), F.aliases(modules)
        local state = h.require("core.GameState").exportSave()
        local original, count = objectSet(modules)
        h:resetNotifications(); h.rejectNativeRename = true
        eq(h.Service.ApplyInventoryCuration(1,p.token),false,"real Flush rename failure refused")
        same(modules,before,"balanced transfer deep rollback")
        F.assertAliases(aliases)
        same(h.require("core.GameState").exportSave(),state,"native failure GameState unchanged")
        eq(saved(),baseline,"failed native commit leaves prior disk bytes intact")
        eq(nativeFs:FileExists(paths["standalone_save.pending.json"]),false,"failed native pending cleaned")
        eq(#h.notificationOrder,0,"failed native commit no notifications")
        h.rejectNativeRename = false
        apply(h,p.token)
        eq(h.flushCalls,2,"same token retries real failed commit once")
        eq(h.pushes.equipment,1,"native success equipment once")
        eq(h.pushes.lootbox,1,"native success lootbox once")
        conserved(modules,original,count)
        local _, disk = saved()
        local diskObjects, diskCount, bagCount = {}, 0, 0
        local function observe(item)
            local id = item.curationValidationId
            check(type(id)=="string" and not diskObjects[id],"native serialized object exists exactly once")
            diskObjects[id], diskCount = naked(item), diskCount+1
        end
        for _, item in pairs(disk.modules.equipment.inventory) do observe(item); bagCount=bagCount+1 end
        for _, seed in ipairs(disk.modules.lootbox.seeds) do observe(seed.equip) end
        eq(bagCount,500,"native final inventory500")
        eq(diskCount,count,"native total object count conserved")
        for item, fields in pairs(original) do
            -- 活对象上面已精确deep equal；磁盘按现有cjson双精度编码口径比较，不能把JSON舍入误判为整理改值。
            same(diskObjects[item.curationValidationId],cjson.decode(cjson.encode(fields)),"native every encoded non-seq field conserved")
        end
        local p2 = preview(h)
        eq(p2.changed,false,"native balanced plan second preview no-op")
        same(slotCounts(p2),slotCounts(p),"protected armor seeds do not drift next round")
        print(TAG .. " NATIVE_SAVE inventory=500 total=" .. diskCount .. " rename_failure_rollback=PASS file=" .. paths["standalone_save.json"])
        eq(h.randomCalls,0,"native plan apply retry no RNG")
    end)
end

local function main()
    planningTests()
    balancedPlanningTests()
    serviceTests()
    balancedServiceTests()
    print(TAG .. " SUMMARY cases=" .. cases .. " assertions=" .. assertions .. " failures=" .. failures)
    if failures == 0 then print(TAG .. " ALL PASS") end
end
function Start()
    local ok, err = pcall(main)
    if not ok then print(TAG .. " [FAIL] harness " .. tostring(err)) end
    engine:Exit()
end
