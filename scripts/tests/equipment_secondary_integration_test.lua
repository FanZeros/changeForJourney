-- 新随机固定副属性集成回归：独立 Runtime，仅内存 fixture，不读写玩家存档。
-- 真实 EquipmentSystem / BlacksmithService / Schema / Dispatcher / Preview / Filters；
-- 仅替换 PDM、任务进度与日志边界。运行前需完成 EquipmentSecondaryStats 核心实现。
-- Runtime: tests/equipment_secondary_integration_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless

local PREFIX = "[equipment_secondary_integration] "
local assertions, failures = 0, 0

local function check(condition, message)
    assertions = assertions + 1
    if not condition then
        failures = failures + 1
        print(PREFIX .. "FAIL " .. message)
    end
end

local function near(actual, expected)
    return type(actual) == "number" and type(expected) == "number"
        and math.abs(actual - expected) <= 1e-10 * math.max(1, math.abs(expected))
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

-- JSON 允许浮点末位变化，但字段、数组长度和顺序不允许变化。
local function same(actual, expected)
    if type(actual) ~= type(expected) then return false end
    if type(expected) == "number" then return near(actual, expected) end
    if type(expected) ~= "table" then return actual == expected end
    for key, value in pairs(expected) do
        if not same(actual[key], value) then return false end
    end
    for key in pairs(actual) do if expected[key] == nil then return false end end
    return true
end

local function roundtrip(value)
    return cjson.decode(cjson.encode(value))
end

local function readSource(name)
    local path = name:gsub("%.", "/") .. ".lua"
    local file = assert(cache:GetFile(path), "missing test source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

-- 与既有 preview/lootbox 测试相同：从资源编译真实模块，替身只在该模块环境生效。
local function realModule(name, replacements)
    local env = setmetatable({ print = function() end }, { __index = _G })
    env._G = env
    env.require = function(dep)
        if replacements and replacements[dep] then return replacements[dep] end
        return require(dep)
    end
    return assert(load(readSource(name), "@secondary-integration/" .. name, "t", env))()
end

local function runGroup(name, body)
    print(PREFIX .. "GROUP " .. name)
    local ok, err = pcall(body)
    if not ok then check(false, name .. " exception: " .. tostring(err)) end
end

local function secondaryMatches(equip, expectedRoll, label)
    check(same(equip.secondaryRoll, expectedRoll), label .. " keeps immutable secondaryRoll")
    if expectedRoll then
        local stats = equip.baseStats or {}
        check(#stats == #expectedRoll.stats + 1, label .. " keeps secondary slot count")
        for index, roll in ipairs(expectedRoll.stats) do
            check(stats[index + 1] and stats[index + 1][1] == roll[1],
                label .. " keeps ordered secondary key " .. index)
        end
    end
end

local function scaled(value, key, level, strength, AD, EC)
    local result = value * (1 + (level - 1) * EC.LEVEL_SCALE) * strength
    local meta = AD.META[key]
    if meta and meta.dataType == AD.TYPE_INT then result = math.floor(result + 0.5) end
    return result
end

-- 独立 oracle 直接展开 level/quality/curse，不用被测 recalcBaseStats 作为期望。
local function baseMatches(equip, EC, AD, label)
    local template = assert(EC.ITEMS[equip.templateId], "fixture template missing")
    local strength = EC.QUALITY[equip.quality].baseStrength * (equip.corruptBaseMult or 1)
    local stats = assert(equip.baseStats, "fixture baseStats missing")
    check(stats[1][1] == template.stats[1][1]
        and near(stats[1][2], scaled(template.stats[1][2], template.stats[1][1], equip.level, strength, AD, EC)),
        label .. " primary remains template-scaled")
    local roll = equip.secondaryRoll
    if roll then
        for index, item in ipairs(roll.stats) do
            check(stats[index + 1] and stats[index + 1][1] == item[1]
                and near(stats[index + 1][2], scaled(item[2], item[1], equip.level, strength, AD, EC)),
                label .. " scales persisted secondary baseValue " .. index)
        end
    else
        check(#stats == #template.stats, label .. " legacy count remains template count")
        for index = 2, #template.stats do
            local item = template.stats[index]
            check(stats[index] and stats[index][1] == item[1]
                and near(stats[index][2], scaled(item[2], item[1], equip.level, strength, AD, EC)),
                label .. " legacy secondary remains template-derived " .. index)
        end
    end
end

local function getUpvalue(fn, wanted)
    for index = 1, 100 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing test upvalue " .. wanted)
end

local function blacksmithTests(Eq, EC, AD, AC)
    local modules = {}
    local dirty = {}
    local uid = 1010
    local pdm = {
        GetModule = function(_, name) return modules[name] end,
        MarkDirty = function(_, name) dirty[name] = (dirty[name] or 0) + 1 end,
        FlushImmediate = function() end,
    }
    local BS = realModule("rules.blacksmith.BlacksmithService", {
        ["rules.character.PlayerDataManager"] = pdm,
        ["rules.task.TaskService"] = { UpdateProgress = function() end },
    })
    local function reset()
        BS.Cleanup(uid)
        modules.player = { level = 200 }
        modules.battle = { maxStageId = 101, currentStageId = 101 }
        modules.equipment = { inventory = {}, equipped = {}, nextSeq = 1 }
        modules.currency = { gold = 10 ^ 12, essence = 10 ^ 9,
            weaponScroll = 10 ^ 6, offhandScroll = 10 ^ 6, armorScroll = 10 ^ 6,
            helmetScroll = 10 ^ 6, shoesScroll = 10 ^ 6, accessoryScroll = 10 ^ 6,
            destroyStone = 100, enhanceStone = 100, corruptStone = 100, sacredStone = 100 }
        dirty = {}
    end
    local function fixedAffixes()
        local result = {}
        -- 此处仅锁定普通随机词缀夹具以保证腐化资格；不假定新固定副属性的 key。
        for _, key in ipairs({ AD.STR, AD.AGI, AD.INT }) do
            local template = assert(AC.BY_KEY[key], "missing convertible affix")
            result[#result + 1] = { affixId = template.id, key = key, name = template.name,
                quality = 2, value = 8.25 }
        end
        return result
    end

    for _, templateId in ipairs({ "W1", "O13", "C1" }) do
        for _, legacy in ipairs({ false, true }) do
            reset()
            math.randomseed(101000 + (legacy and 1 or 0))
            local equip = assert(Eq.generate(templateId, 12, 2, { legacySecondary = legacy }))
            Eq.addToInventory(modules.equipment, equip)
            equip.affixes = fixedAffixes()
            local roll = copy(equip.secondaryRoll)
            local label = templateId .. (legacy and " legacy" or " new")
            check(legacy and roll == nil or not legacy and type(roll) == "table" and roll.version == 1,
                label .. " correct new/legacy marker")
            secondaryMatches(equip, roll, label .. " generated")
            baseMatches(equip, EC, AD, label .. " generated")

            local ok, err, result = BS.RefineEquip(uid, equip.seq, "destroyStone")
            check(ok and result and result.autoReplaced and equip.quality == 3,
                label .. " actual quality upgrade succeeds: " .. tostring(err))
            secondaryMatches(equip, roll, label .. " upgrade")
            baseMatches(equip, EC, AD, label .. " upgrade")

            for layer = 1, 2 do
                local corruptOk, corruptErr = BS.RefineEquip(uid, equip.seq, "corruptStone")
                check(corruptOk and equip.corruptCount == layer,
                    label .. " actual curse layer " .. layer .. ": " .. tostring(corruptErr))
                secondaryMatches(equip, roll, label .. " curse " .. layer)
                baseMatches(equip, EC, AD, label .. " curse " .. layer)
            end
            local upgradeOk = BS.RefineEquip(uid, equip.seq, "destroyStone")
            check(upgradeOk and equip.quality == 4 and equip.corruptCount == 2,
                label .. " quality upgrade retains active curse")
            secondaryMatches(equip, roll, label .. " cursed upgrade")
            baseMatches(equip, EC, AD, label .. " cursed upgrade")

            check(BS.RefineEquip(uid, equip.seq, "sacredStone") and equip.corruptCount == 1,
                label .. " cleanse removes only top curse")
            secondaryMatches(equip, roll, label .. " partial cleanse")
            baseMatches(equip, EC, AD, label .. " partial cleanse")
            check(BS.AscendEquip(uid, equip.seq), label .. " single ascend succeeds")
            check(BS.AscendEquipToLevel(uid, equip.seq, 6), label .. " batch ascend succeeds")
            secondaryMatches(equip, roll, label .. " ascended while cursed")
            baseMatches(equip, EC, AD, label .. " ascended raw stats")
            for index = 2, #equip.baseStats do
                local count = #equip.baseStats - 1
                local position = index - 1
                local steps = 6 < position and 0 or math.floor((6 - position) / count) + 1
                check(near(Eq.effectiveBaseStatValue(equip, index),
                    equip.baseStats[index][2] * (1 + steps * 0.05)),
                    label .. " ascend follows persisted slot order " .. index)
            end
            check(BS.RefineEquip(uid, equip.seq, "sacredStone") and equip.corruptCount == nil,
                label .. " final cleanse restores unpenalized quality")
            secondaryMatches(equip, roll, label .. " full cleanse")
            baseMatches(equip, EC, AD, label .. " full cleanse")

            for _, resource in ipairs({ "essence", "enhanceStone" }) do
                local beforeStats, beforeAffixes = copy(equip.baseStats), copy(equip.affixes)
                local refineOk, refineErr, preview = BS.RefineEquip(uid, equip.seq, resource)
                check(refineOk and preview and type(preview.refinePreview) == "table",
                    label .. " actual " .. resource .. " preview: " .. tostring(refineErr))
                check(same(equip.affixes, beforeAffixes) and same(equip.baseStats, beforeStats),
                    label .. " pending " .. resource .. " does not apply preview early")
                secondaryMatches(equip, roll, label .. " pending " .. resource)
                check(BS.RefineReplace(uid, equip.seq), label .. " actual " .. resource .. " replace succeeds")
                secondaryMatches(equip, roll, label .. " replaced " .. resource)
                check(same(equip.baseStats, beforeStats), label .. " random affix replace does not reroll fixed stats")
            end

            check(BS.RefineEquip(uid, equip.seq, "destroyStone"), label .. " at-cap affix grade upgrade succeeds")
            secondaryMatches(equip, roll, label .. " affix grade upgrade")
            baseMatches(equip, EC, AD, label .. " affix grade upgrade")
            modules.currency.destroyStone = 0
            local beforeReject = copy(equip)
            local rejected = BS.RefineEquip(uid, equip.seq, "destroyStone")
            check(not rejected and same(equip, beforeReject), label .. " insufficient resource preserves whole instance")
            check((dirty.equipment or 0) > 0, label .. " real operations mark equipment dirty")
        end
    end

    -- 兼容旧点金预览确认：直接注入过去已付费的 pending 状态，不篡改生产分支。
    reset()
    local pending = getUpvalue(BS.RefineReplace, "pendingRefines")
    for _, legacy in ipairs({ false, true }) do
        local equip = assert(Eq.generate("O13", 12, 2, { legacySecondary = legacy }))
        Eq.addToInventory(modules.equipment, equip)
        local roll = copy(equip.secondaryRoll)
        pending[uid] = pending[uid] or {}
        pending[uid][tostring(equip.seq)] = { affixes = copy(equip.affixes), upgradedQuality = 3 }
        check(BS.RefineReplace(uid, equip.seq) and equip.quality == 3,
            "legacy pending quality confirm applies: legacy=" .. tostring(legacy))
        secondaryMatches(equip, roll, "legacy pending confirm " .. tostring(legacy))
        baseMatches(equip, EC, AD, "legacy pending confirm " .. tostring(legacy))
    end
    BS.Cleanup(uid)
end

local function schemaAndPushTests(Eq, EC, AD)
    local schema = require("shared.equipment.EquipmentSchema").Fields.equipment
    local original = schema.getDefault()
    local newEquip = assert(Eq.generate("O13", 12, 4))
    local oldEquip = assert(Eq.generate("W1", 12, 3, { legacySecondary = true }))
    newEquip.ascendLevel, newEquip.enhanceLevel = 7, 7
    oldEquip.ascendLevel, oldEquip.enhanceLevel = 3, 3
    Eq.addToInventory(original, newEquip)
    Eq.addToInventory(original, oldEquip)
    original.equipped["1"] = { weapon = oldEquip.seq }
    local sourceBefore, expectedRoll = copy(original), copy(newEquip.secondaryRoll)
    local lean = schema.onSave(original)
    check(same(original, sourceBefore), "EquipmentSchema.onSave is read-only")
    check(lean.inventory["1"].baseStats == nil and lean.inventory["1"].secondaryRoll ~= nil,
        "EquipmentSchema keeps roll while removing derived stats")
    check(lean.inventory["2"].secondaryRoll == nil, "EquipmentSchema does not mark legacy equipment as new")
    local loaded = roundtrip(lean)
    for iteration = 1, 3 do
        schema.onLoad(loaded)
        secondaryMatches(loaded.inventory["1"], expectedRoll, "schema load " .. iteration)
        baseMatches(loaded.inventory["1"], EC, AD, "schema load " .. iteration)
        check(same(loaded.inventory["1"].baseStats, sourceBefore.inventory["1"].baseStats),
            "schema does not accumulate secondary scaling " .. iteration)
        check(loaded.inventory["2"].secondaryRoll == nil
            and same(loaded.inventory["2"].baseStats, sourceBefore.inventory["2"].baseStats),
            "schema legacy remains unchanged " .. iteration)
        loaded = roundtrip(schema.onSave(loaded))
    end
    schema.onLoad(loaded)

    local server = realModule("runtime.LocalDispatcher")
    local characterSchema = realModule("shared.schemas.CharacterSchema")
    local client = realModule("runtime.ClientDispatcher", {
        ["shared.schemas.CharacterSchema"] = characterSchema,
    })
    local protocol = require("shared.Protocol")
    local messages = {}
    local uid = 1010
    server.setLocalEventSink(function(sentUid, event, payload)
        check(sentUid == uid and event == protocol.RES_STATE_UPDATE, "LocalDispatcher routes state update to isolated sink")
        messages[#messages + 1] = roundtrip(payload)
    end)
    local function consume(label)
        check(#messages > 0, label .. " emits payload")
        for _, message in ipairs(messages) do client.handleStateUpdate(cjson.encode(message)) end
        local data = assert(client.get("equipment"), "push did not populate isolated client")
        secondaryMatches(data.inventory["1"], expectedRoll, label .. " hydrated client")
        check(data.inventory["2"].secondaryRoll == nil, label .. " client keeps legacy marker absent")
        check(same(Eq.dehydrateInventory(data.inventory), Eq.dehydrateInventory(loaded.inventory)),
            label .. " whole inventory roundtrip preserves all fields")
        check(same(original, sourceBefore), label .. " does not alter original source")
        messages = {}
    end
    server.pushFullState(uid, { equipment = loaded })
    consume("full push")
    for iteration = 1, 3 do
        server.pushModule(uid, "equipment", client.get("equipment"))
        consume("incremental loop " .. iteration)
    end
    check(server.resendFromCache(uid), "LocalDispatcher cache resend available")
    consume("cache resend")
    server.setLocalEventSink(nil)
    server.clearCache(uid)
end

local function lootboxTests(Eq, EC, AD)
    local calls = {}
    local proxy = setmetatable({}, { __index = Eq })
    proxy.generateRandom = function(level, quality, options)
        local equip = Eq.generateRandom(level, quality, options)
        calls[#calls + 1] = { legacy = options and options.legacySecondary == true, equip = equip }
        return equip
    end
    local Loot = realModule("systems.LootBoxSystem", { ["systems.EquipmentSystem"] = proxy })
    local Schema = realModule("shared.lootbox.LootboxSchema", { ["systems.LootBoxSystem"] = Loot }).Fields.lootbox
    local current = assert(Eq.generate("O13", 12, 4))
    local legacy = assert(Eq.generate("W1", 12, 2, { legacySecondary = true }))
    local box = Schema.getDefault()
    Loot.addEquipment(box, current)
    Loot.addEquipment(box, legacy)
    box.seeds[#box.seeds + 1] = { quality = "2", level = "12", count = "2" }
    box = roundtrip(box)
    local originalCurrent, originalLegacy = copy(box.seeds[1].equip), copy(box.seeds[2].equip)
    Schema.onLoad(box)
    check(#calls == 2 and #box.seeds == 4, "two old unresolved seeds migrate exactly once")
    for index, call in ipairs(calls) do
        check(call.legacy == true and call.equip.secondaryRoll == nil,
            "old unresolved seed skips new secondary roll " .. index)
        baseMatches(call.equip, EC, AD, "old seed migrated " .. index)
    end
    check(same(box.seeds[1].equip, originalCurrent) and same(box.seeds[2].equip, originalLegacy),
        "migration retains both new and legacy already-determined payloads")
    check(Loot.addSeed(box, 101, 3, 12), "new idle seed insertion succeeds")
    check(#calls == 3 and not calls[3].legacy and calls[3].equip.secondaryRoll ~= nil,
        "new addSeed rolls fixed secondaries at insertion, not claim")
    local inserted = copy(box.seeds[5].equip)
    for _ = 1, 3 do
        Loot.consolidateSeeds(box)
        Schema.onLoad(box)
        check(Loot.revealLegacy(box) == 0, "complete rewards never remigrate")
        Loot.getSummary(box)
    end
    check(#calls == 3 and same(box.seeds[5].equip, inserted),
        "repeated schema/consolidation/summary never rerolls new fixed secondaries")
    local bag = { inventory = {}, equipped = {}, nextSeq = 1 }
    local expected = {}
    for _, entry in ipairs(box.seeds) do expected[entry.equip] = copy(entry.equip) end
    local first = box.seeds[1].equip
    local group, full = Loot.claimGroup(box, 1, bag)
    check(not full and #group == 1 and group[1] == first,
        "claimGroup returns the same already-determined new equipment")
    local rest, finalFull = Loot.claimAll(box, bag)
    check(not finalFull and #rest == 4 and #box.seeds == 0,
        "claimAll delivers determined legacy/new rewards exactly once")
    for equip, before in pairs(expected) do
        local received = copy(equip)
        received.seq, before.seq = nil, nil
        check(same(received, before), "claim preserves payload apart from allocated inventory seq")
        check(bag.inventory[tostring(equip.seq)] == equip, "claim stores original equipment identity")
    end
    local empty = Loot.claimAll(box, bag)
    check(#empty == 0 and #calls == 3 and Eq.getInventoryCount(bag) == 5,
        "claim loops do not generate or duplicate any equipment")

    -- 缺派生字段的已确定新装备在入包时水合，仍不重新抽取副属性。
    local leanEquip = Eq.dehydrate(current)
    local leanRoll = copy(leanEquip.secondaryRoll)
    local leanBox = Schema.getDefault()
    Loot.addEquipment(leanBox, leanEquip)
    Schema.onLoad(leanBox)
    local claimed = Loot.claimGroup(leanBox, 1, bag)
    check(#claimed == 1 and claimed[1].baseStats ~= nil and #calls == 3,
        "lean determined payload hydrates only at inventory insertion")
    secondaryMatches(claimed[1], leanRoll, "lean determined claim")
    baseMatches(claimed[1], EC, AD, "lean determined claim")
end

local function attributesAndPreviewTests(Eq, AD)
    local attrsModule = require("systems.UnitAttributes")
    local equip = assert(Eq.generate("O13", 12, 4))
    equip.ascendLevel, equip.enhanceLevel, equip.affixMult = 7, 7, 1.2
    local before = copy(equip)
    local boost = Eq.getAscendBoost(equip)
    local entries = Eq.computeModifierEntries(equip, boost)
    check(#entries == #equip.baseStats + #equip.affixes, "computeModifierEntries includes every persisted fixed secondary and random affix")
    for index, stat in ipairs(equip.baseStats) do
        local value = 0
        if index == 1 then value = stat[2] * (1 + boost)
        else
            local count, position = #equip.baseStats - 1, index - 1
            local steps = 7 < position and 0 or math.floor((7 - position) / count) + 1
            value = stat[2] * (1 + steps * 0.05)
        end
        if stat[1] == AD.ATK_INTERVAL then value = -value end
        check(entries[index].key == stat[1] and near(entries[index].flat, value),
            "modifier entry follows actual rolled key/value/ascend order " .. index)
    end
    local unit = attrsModule.create({ maxHp = 1000, physAtk = 50, magAtk = 40 })
    Eq.applyToUnit(unit, equip, 90, boost)
    check(same(unit.modifiers.equip_90, entries), "actual applyToUnit uses full rolled modifier entries")
    local cloned = unit:clone()
    check(same(cloned.modifiers.equip_90, entries), "actual UnitAttributes clone retains rolled modifier entries")
    Eq.removeFromUnit(cloned, 90)
    check(cloned.modifiers.equip_90 == nil and unit.modifiers.equip_90 ~= nil,
        "clone modification/removal is isolated from current wearer")
    check(same(equip, before), "compute/apply/clone do not mutate original equipment")

    local Preview = require("ui.character.detail.EquipmentPreview")
    local worn = assert(Eq.generate("W1", 12, 1, { legacySecondary = true }))
    local candidate
    for seed = 1, 32 do
        math.randomseed(101000 + seed)
        local rolled = assert(Eq.generate("W1", 12, 3))
        if rolled.baseStats[2][1] ~= worn.baseStats[2][1]
            or rolled.baseStats[3][1] ~= worn.baseStats[3][1] then
            candidate = rolled
            break
        end
    end
    assert(candidate, "试穿夹具必须包含不同于旧模板的副属性")
    check(candidate.baseStats[2][1] ~= worn.baseStats[2][1]
        or candidate.baseStats[3][1] ~= worn.baseStats[3][1], "真实试穿强制覆盖不同副属性种类")
    candidate.ascendLevel, candidate.enhanceLevel = 6, 6
    local source = {
        heroes = { roster = { ["1"] = { level = 70, awakening = {}, extraTalent = {} } }, deployed = { 1 } },
        equipment = { inventory = { ["1"] = Eq.dehydrate(worn), ["2"] = Eq.dehydrate(candidate) },
            equipped = { ["1"] = { weapon = 1 } }, nextSeq = 3 },
        artifacts = { bag = {} }, talents = { litNodes = { 0 } },
    }
    local sourceBefore, rollBefore = copy(source), copy(candidate.secondaryRoll)
    local result = Preview.build(1, 70, 2, "weapon", source)
    check(result.error == nil and result.preview ~= nil, "real Preview accepts rolled candidate through actual equip guard")
    check(same(source, sourceBefore) and source.equipment.inventory["2"].baseStats == nil,
        "real Preview hydrates only copies and preserves original lean equipment")
    check(same(source.equipment.inventory["2"].secondaryRoll, rollBefore),
        "real Preview preserves immutable candidate secondary roll")
    if result.preview then
        check(result.current.attrs.modifiers.equip_1 ~= nil and result.current.attrs.modifiers.equip_2 == nil,
            "real Preview current wearer remains legacy equipment")
        check(result.preview.attrs.modifiers.equip_1 == nil
            and same(result.preview.attrs.modifiers.equip_2,
                Eq.computeModifierEntries(candidate, Eq.getAscendBoost(candidate))),
            "real Preview uses candidate rolled fixed stats rather than template secondary keys")
    end
    local repeated = Preview.build(1, 70, 2, "weapon", source)
    check(result.preview and repeated.preview and same(result.preview.stats, repeated.preview.stats)
        and same(source, sourceBefore), "repeated Preview neither rerolls nor accumulates candidate boosts")
end

local function sortingTests()
    local secondary = require("systems.EquipmentSecondaryStats")
    local Filters = realModule("ui.backpack.BackpackFilters")
    local state = {}
    local api = Filters.bind({ filters = state, GRID = {}, getSlot = function() return nil end,
        setSlot = function() end, onChange = function() end })
    local options, counts = api.getOptions("sort"), {}
    for _, option in ipairs(options) do counts[option.value] = (counts[option.value] or 0) + 1 end
    local keys = secondary.getAttributeKeys()
    check(#keys > 0, "random secondary attribute pool is nonempty")
    for _, key in ipairs(keys) do
        check(counts[key] == 1, "real warehouse sort menu includes rolled attribute exactly once: " .. key)
    end
    check(next(state) == nil, "building warehouse sort options is read-only")
end

function Start()
    print(PREFIX .. "START isolated fixtures; no player save IO")
    local ok, err = pcall(function()
        local Eq = require("systems.EquipmentSystem")
        local EC = require("config.EquipmentConfig")
        local AD = require("systems.AttributeDef")
        local AC = require("config.AffixConfig")
        runGroup("real blacksmith new/legacy lifecycle", function() blacksmithTests(Eq, EC, AD, AC) end)
        runGroup("EquipmentSchema and LocalDispatcher loops", function() schemaAndPushTests(Eq, EC, AD) end)
        runGroup("determined lootbox and legacy seed migration", function() lootboxTests(Eq, EC, AD) end)
        runGroup("real attribute application/clone and readonly Preview", function() attributesAndPreviewTests(Eq, AD) end)
        runGroup("real warehouse sort coverage", sortingTests)
    end)
    if not ok then check(false, "setup exception: " .. tostring(err)) end
    print(string.format("%sassertions=%d failures=%d %s", PREFIX, assertions, failures,
        failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
