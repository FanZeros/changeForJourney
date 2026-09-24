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
    LootboxSchema.Fields.lootbox.onLoad(loaded)
    countIs(loaded, 5, 3, "onLoad merges only the three seed pieces")
    local loadedEquips, seedEntries = {}, {}
    for _, entry in ipairs(loaded.seeds) do
        eq(entry.quality, 6, "schema quality normalized")
        eq(entry.level, 80, "schema level normalized")
        if entry.equip then
            eq(entry.count, 1, "onLoad keeps complete instances independent")
            loadedEquips[#loadedEquips + 1] = entry.equip
        else
            seedEntries[#seedEntries + 1] = entry
        end
    end
    eq(#loadedEquips, 2, "both complete instances survive schema")
    eq(#seedEntries, 1, "legacy seed groups consolidated")
    eq(seedEntries[1].count, 3, "string count and implicit count preserved")
    eq(seedEntries[1].stageId, nil, "legacy stage grouping removed")
    assert(loadedEquips[1] ~= loadedEquips[2], "independent equipment tables")
    assert(loadedEquips[1].affixes ~= loadedEquips[2].affixes, "independent affix arrays")
    sameEquip(loadedEquips[1], expectedFirst, "schema preserves template/affixes/enhancement A")
    sameEquip(loadedEquips[2], expectedSecond, "schema preserves template/affixes/enhancement B")

    local before = copy(loaded)
    LootBoxSystem.consolidateSeeds(loaded)
    LootBoxSystem.consolidateSeeds(loaded)
    LootboxSchema.Fields.lootbox.onLoad(loaded)
    same(loaded, before, "consolidation and schema are idempotent")
    assert(LootBoxSystem.addSeed(loaded, 99, 6, 80), "matching seed accepted")
    countIs(loaded, 6, 3, "new seed does not merge into complete equipment")
    eq(seedEntries[1].count, 4, "only seed count incremented")
    local summary = LootBoxSystem.getSummary(loaded)
    eq(#summary, #loaded.seeds, "summary indexes cover every stored entry")
    for index, entry in ipairs(loaded.seeds) do
        eq(summary[index].equip, entry.equip, "summary preserves equipment identity/index")
        eq(summary[index].count, entry.count, "summary count matches stored index")
        eq(summary[index].quality, entry.quality, "summary quality matches")
        eq(summary[index].level, entry.level, "summary level matches")
    end

    LootBoxSystem.levelCap = 3
    local bag = newBag(0)
    local group = LootBoxSystem.claimGroup(loaded, findEquipEntry(loaded, loadedEquips[1]), bag)
    eq(#group, 1, "persisted complete instance claimGroup")
    eq(group[1], loadedEquips[1], "claimGroup does not reroll persisted instance")
    sameEquip(group[1], expectedFirst, "claimGroup preserves complete fields above levelCap")
    local rest, full = LootBoxSystem.claimAll(loaded, bag)
    eq(#rest, 5, "claimAll returns four seeds and second full instance")
    eq(full, false, "persisted rewards fit bag")
    local materialized = 0
    for _, equip in ipairs(rest) do
        if equip == loadedEquips[2] then
            sameEquip(equip, expectedSecond, "claimAll preserves full instance above levelCap")
        else
            eq(equip.level, 3, "only legacy seeds obey levelCap")
            eq(equip.quality, 6, "generated seed quality retained")
            assert(equip.templateId and #equip.affixes > 0, "seed produces actual equipment")
            materialized = materialized + 1
        end
    end
    eq(materialized, 4, "all four seed pieces materialized")
    eq(bag.inventory[tostring(loadedEquips[2].seq)], loadedEquips[2], "second instance delivered")
    eq(EquipmentSystem.getInventoryCount(bag), 6, "each persisted reward paid once")
    assertEmptyCannotPayAgain(loaded, bag)
end

local function testClaimOneAndSeedCapacity()
    local box, bag = newLootbox(), newBag(200)
    local complete = newEquip(90, 6, 25)
    local snapshot = copy(complete)
    LootBoxSystem.addEquipment(box, complete)
    LootBoxSystem.levelCap = 7
    -- claimOne 只取出原始装备，不负责检查容量或放入背包。
    local extracted = LootBoxSystem.claimOne(box, 1)
    eq(extracted, complete, "claimOne returns original complete instance")
    sameEquip(extracted, snapshot, "claimOne bypasses seed-only levelCap")
    eq(EquipmentSystem.getInventoryCount(bag), 200, "raw extraction does not modify bag")
    eq(LootBoxSystem.claimOne(box, 1), nil, "raw extraction cannot duplicate instance")

    for _ = 1, 3 do assert(LootBoxSystem.addSeed(box, 1, 4, 35), "seed accepted") end
    local before = copy(box)
    local blocked, full = LootBoxSystem.claimGroup(box, 1, bag)
    eq(#blocked, 0, "full bag cannot consume seeds")
    eq(full, true, "seed group blocked by capacity")
    same(box, before, "full seed group unchanged")
    assert(EquipmentSystem.removeFromInventory(bag, 1), "free seed slot")
    local partial, partialFull = LootBoxSystem.claimGroup(box, 1, bag)
    eq(#partial, 1, "single free slot consumes one seed")
    eq(partialFull, true, "seed group retains excess")
    eq(partial[1].level, 7, "seed generation obeys levelCap")
    eq(partial[1].quality, 4, "seed generation retains quality")
    assert(partial[1].templateId and #partial[1].affixes > 0, "real seed equipment generated")
    countIs(box, 2, 1, "two seed pieces retained")
    eq(box.seeds[1].equip, nil, "partially claimed seed stays a seed")
    LootBoxSystem.levelCap = 0
    local uncapped = LootBoxSystem.claimOne(box, 1)
    eq(uncapped.level, 35, "disabled cap preserves seed level")
    eq(uncapped.quality, 4, "raw seed quality retained")
    countIs(box, 1, 1, "claimOne decrements grouped count exactly once")
    assert(EquipmentSystem.removeFromInventory(bag, 2), "free final seed slot")
    local last, lastFull = LootBoxSystem.claimAll(box, bag)
    eq(#last, 1, "last seed delivered")
    eq(last[1].level, 35, "claimAll seed generated at original level")
    eq(lastFull, false, "seed group exhausted")
    assert(last[1] ~= partial[1] and last[1] ~= uncapped, "seeds generate independent instances")
    assertEmptyCannotPayAgain(box, bag)
end

local function testBeyond9999()
    local box = { seeds = { { quality = 6, level = 80, count = 9999 } } }
    assert(LootBoxSystem.addSeed(box, 1, 6, 80), "10000th seed accepted")
    countIs(box, 10000, 1, "same group exceeds former seed cap")
    assert(LootBoxSystem.addSeed(box, 2, 2, 10), "new group accepted above cap")
    countIs(box, 10001, 2, "new quality group exceeds former total cap")
    local first, second = newEquip(80, 6, 31), newEquip(80, 6, 32)
    local firstSnapshot, secondSnapshot = copy(first), copy(second)
    LootBoxSystem.addEquipment(box, first)
    local bag = newBag(200)
    eq(LootBoxSystem.deliverEquipment(box, bag, second), "lootbox", "overflow above 9999 retained")
    countIs(box, 10003, 4, "all kinds accepted above former limit")
    sameEquip(box.seeds[3].equip, firstSnapshot, "explicit full instance above cap")
    sameEquip(box.seeds[4].equip, secondSnapshot, "delivered full instance above cap")

    local loaded = roundtrip(box)
    LootboxSchema.Fields.lootbox.onLoad(loaded)
    countIs(loaded, 10003, 4, "large count survives persistence and consolidation")
    eq(loaded.seeds[1].count, 10000, "large grouped seed count intact")
    sameEquip(loaded.seeds[3].equip, firstSnapshot, "large save complete payload A")
    sameEquip(loaded.seeds[4].equip, secondSnapshot, "large save complete payload B")
    local value, pieces = LootBoxSystem.decomposeAll(loaded)
    eq(pieces, 10003, "large decompose counts pieces, not four entries")
    eq(value, essenceFor(6, 80, 10002) + essenceFor(2, 10, 1), "large essence total")
    assertEmptyCannotPayAgain(loaded, bag)
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
    local seedValue, seedPieces = LootBoxSystem.decomposeOne(box, 1)
    eq(seedPieces, 3, "decomposeOne consumes whole seed group")
    eq(seedValue, 15, "round each 5.5 essence piece down before multiplication")
    countIs(box, 3, 2, "only selected seed group removed")
    local equipValue, equipPieces = LootBoxSystem.decomposeOne(box, 1)
    eq(equipPieces, 1, "complete instance contributes one piece")
    eq(equipValue, 60, "complete instance quality/level essence")
    local allValue, allPieces = LootBoxSystem.decomposeAll(box)
    eq(allPieces, 2, "all decomposition returns remaining pieces only")
    eq(allValue, 30, "remaining quality/level essence")
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
        rollKillDrop = function() return 5 end,
        rollScrollDrop = function() return "weaponScroll" end,
        generateFirstClearEquips = function() return h.firstEquips end,
        generateFirstClearScrolls = function() return { scrolls = { weaponScroll = 3 } } end,
    })
    -- 只记录真实生成器的返回值，证明击杀奖励没有重骰、截断或替换为种子。
    ---@type table<string, any>
    local equipmentSpy = {}
    for key, value in pairs(EquipmentSystem) do equipmentSpy[key] = value end
    equipmentSpy.generateRandom = function(level, quality)
        local equip = EquipmentSystem.generateRandom(level, quality)
        assert(equip, "Boot kill reward generation must succeed")
        h.generated[#h.generated + 1] = { equip = equip, snapshot = copy(equip) }
        return equip
    end
    inject("systems.EquipmentSystem", equipmentSpy)
    inject("network.ClientDispatcher", {
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
    battle.getMaxStageId = function() return 2 end
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
        drop(h, false, 2)
        countIs(h.data.lootbox, 2, 1, "idle kills remain grouped seeds")
        eq(h.data.lootbox.seeds[1].equip, nil, "idle drop is not pre-generated full equipment")
        eq(h.data.lootbox.seeds[1].level, 60, "idle seed uses killed stage monster level")
        eq(h.data.lootbox.seeds[1].quality, 5, "idle seed quality retained")
        eq(#h.generated, 0, "idle drops do not eagerly generate equipment")
        eq(#h.popups, 0, "idle kills do not show FC/battle reward popup")
        eq(#h.hints, 2, "idle still sends seed hints")
        eq(h.currency.WeaponScroll, 2, "idle scrolls delivered immediately")
        eq(EquipmentSystem.getInventoryCount(h.data.equipment), 199, "idle does not use free bag slot")
        assertStageEventsCannotRepay(h)

        h.fire("ui.LootBox", "setOnClaimAll")
        eq(EquipmentSystem.getInventoryCount(h.data.equipment), 200, "real Boot claim callback respects capacity")
        countIs(h.data.lootbox, 1, 1, "Boot partial claim retains one seed")
        eq(#h.popups, 1, "claimed idle equipment has its separate claim popup")
        eq(h.popups[1].title, "遗匣领取", "遗匣领取使用独立标题")
        same(rewardTotals(h.popups[1]), { equip = 1 }, "claim popup counts only inserted equipment")
        h.fire("ui.LootBox", "setOnClaimAll")
        eq(#h.popups, 1, "full repeated claim cannot display duplicate reward")
        countIs(h.data.lootbox, 1, 1, "full repeated claim retains seed")
        assert(#h.toasts > 0, "Boot still reports full inventory")
        h.fire("ui.LootBox", "setOnDecomposeAll")
        eq(h.currency.Essence, essenceFor(5, 60, 1), "Boot adds remaining seed essence exactly once")
        eq(#h.popups, 2, "decompose reward shown once")
        eq(h.popups[2].title, "分解奖励", "decompose label unchanged")
        h.fire("ui.LootBox", "setOnDecomposeAll")
        eq(h.currency.Essence, essenceFor(5, 60, 1), "repeated Boot decompose cannot pay twice")
        eq(#h.popups, 2, "repeated Boot decompose has no duplicate popup")
    end)
end

local function testBootSubscriberSeedOnlyClamp()
    withBoot(0, function(h)
        local complete = newEquip(90, 6, 49)
        local snapshot = copy(complete)
        LootBoxSystem.addEquipment(h.data.lootbox, complete)
        LootBoxSystem.addSeed(h.data.lootbox, 2, 6, 90)
        h.notify("lootbox")
        eq(LootBoxSystem.levelCap, 60, "种子上限跟随最高关卡，不随回退降低")
        countIs(h.data.lootbox, 2, 2, "subscriber cannot merge full instance into seed")
        eq(h.data.lootbox.seeds[1].level, 90, "subscriber preserves full entry level")
        eq(h.data.lootbox.seeds[2].level, 60, "旧种子修正到最高进度上限")
        sameEquip(h.data.lootbox.seeds[1].equip, snapshot, "subscriber preserves complete payload")
        h.fire("ui.LootBox", "setOnClaimOne", 1)
        eq(h.data.equipment.inventory[tostring(complete.seq)], complete, "Boot claimOne wiring uses full instance")
        sameEquip(complete, snapshot, "Boot single-group claim cannot reroll or downgrade")
        countIs(h.data.lootbox, 1, 1, "Boot singleton claim leaves seed untouched")
        h.fire("ui.LootBox", "setOnClaimAll")
        eq(EquipmentSystem.getInventoryCount(h.data.equipment), 2, "Boot claims remaining seed")
        countIs(h.data.lootbox, 0, 0, "subscriber/claim path fully drained")
    end)
end

function Start()
    assert(cjson and cjson.encode and cjson.decode, "UrhoXRuntime built-in cjson is required")
    math.randomseed(20260924)
    local tests = {
        { "199/200 boundary, multiple overflow and full claims", testDeliveryBoundary },
        { "one-slot partial complete-instance claims and no duplicate payouts", testPartialFullEquipmentClaims },
        { "JSON, Schema.onLoad, consolidation, summary and full payload fidelity", testPersistenceAndConsolidation },
        { "claimOne, full/partial seed claims and seed-only levelCap", testClaimOneAndSeedCapacity },
        { "9999+ mixed rewards, persistence and quantity accounting", testBeyond9999 },
        { "decomposition essence, pieces, invalid indexes and no double payment", testDecompositionAndInvalidIndexes },
        { "real Boot first-clear success at 199 items", function() testBootSuccess(199) end },
        { "real Boot first-clear success at 200 items", function() testBootSuccess(200) end },
        { "real Boot failure keeps complete battle drops", testBootFailure },
        { "real Boot stageLoaded fallback and repeated-event idempotency", testBootStageLoadedFallback },
        { "real Boot idle seeds, claim/decompose callbacks and reward categories", testBootIdleAndClaimCallbacks },
        { "real Boot subscriber clamps seeds only", testBootSubscriberSeedOnlyClamp },
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
