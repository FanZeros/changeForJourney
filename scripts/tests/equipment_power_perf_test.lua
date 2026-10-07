-- EquipmentPower/角标热点回归；真实公式与校验，库存/存档全部内存隔离。
-- Runtime: tests/equipment_power_perf_test.lua -tool_mode -graphicsheadless
-- 可由 lupa.lua54 运行，cache:GetFile 只读取项目源码，不写玩家档。
local TAG = "[equipment_power_perf_test]"
local assertions, failures = 0, 0
local function check(ok, message)
    assertions = assertions + 1
    if not ok then failures = failures + 1; print(TAG .. " FAIL " .. message) end
end
local function close(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6
end
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[key] = copy(item, seen) end
    return result
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function source(path)
    local file = assert(cache:GetFile(path), "missing test source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function fixture(noRevisions)
    local modules, revisions, subscriptions, loaded = {}, {}, {}, {}
    local counts = { hydrate = 0, power = 0, apply = 0, context = 0, inventoryScans = 0, gain = 0 }
    local inventoryTables = setmetatable({}, { __mode = "k" })
    local store = {
        Get = function(key) return modules[key] end,
        Subscribe = function(key, fn)
            subscriptions[key] = subscriptions[key] or {}
            subscriptions[key][#subscriptions[key] + 1] = fn
        end,
    }
    if not noRevisions then store.GetRevision = function(key) return revisions[key] or 0 end end
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.File = function() error("unexpected player save access") end
    env.pairs = function(value)
        if inventoryTables[value] then counts.inventoryScans = counts.inventoryScans + 1 end
        return pairs(value)
    end
    env.require = function(name)
        if name == "core.PlayerStore" then return store end
        if loaded[name] then return loaded[name] end
        assert(name == "core.BattleLayout" or name == "ui.church.talent.TalentStarMap"
            or name == "ui.widget.TalentGlyph" or name == "ui.widget.TalentGlyphContours"
            or name == "ui.widget.TalentGlyphExtra"
            or name:match("^config%.") or name:match("^shared%.") or name:match("^systems%."),
            "undeclared test dependency " .. name)
        local path = name:gsub("%.", "/") .. ".lua"
        local value = assert(load(source(path), "@equipment-perf-isolated/" .. path, "t", env))()
        loaded[name] = value
        if name == "systems.EquipmentSystem" then
            local hydrate, apply = value.hydrate, value.applyEquip
            value.hydrate = function(...)
                counts.hydrate = counts.hydrate + 1
                return hydrate(...)
            end
            value.applyEquip = function(...)
                counts.apply = counts.apply + 1
                return apply(...)
            end
        elseif name == "systems.CombatPower" then
            local calculate = value.calculate
            value.calculate = function(...)
                counts.power = counts.power + 1
                return calculate(...)
            end
        elseif name == "systems.EquipmentPower" then
            local build = value.buildContext
            value.buildContext = function(...)
                counts.context = counts.context + 1
                local ctx = build(...)
                if ctx then inventoryTables[ctx.equipmentData.inventory] = true end
                return ctx
            end
            local gain = value.evaluateGain
            if gain then value.evaluateGain = function(...)
                counts.gain = counts.gain + 1
                return gain(...)
            end end
        end
        return value
    end
    local EP = env.require("systems.EquipmentPower")
    local Eq = env.require("systems.EquipmentSystem")
    local EC = env.require("config.EquipmentConfig")
    local HC = env.require("config.HeroConfig")
    local AD = env.require("systems.AttributeDef")
    local AVC = env.require("config.AdvancementConfig")
    local ESC = env.require("config.EquipmentSetConfig")
    -- 仅加载允许修改的实际角标 hunk，不模拟UI/字体/输入或执行渲染代码。
    local detailSource = source("ui/character/detail/CharacterDetail.lua")
    local badge = assert(detailSource:match("%-%- ======================== 装备可提升判断 ========================(.-)\n%-%-%- 检查指定英雄的碎片"))
    local DT_SLOTS = {}
    for _, slot in ipairs(EC.SLOTS) do DT_SLOTS[#DT_SLOTS + 1] = { slot = slot } end
    local detailEnv = setmetatable({ CharacterDetail = {}, EquipmentPower = EP, EquipmentSystem = Eq,
        PlayerStore = store, DT_SLOTS = DT_SLOTS }, { __index = env })
    local detail = assert(load(badge .. "\nreturn CharacterDetail", "@actual-badge-hunk", "t", detailEnv))()
    local function setData(data)
        for key in pairs(modules) do modules[key] = nil end
        for key, value in pairs(data) do modules[key] = value; revisions[key] = (revisions[key] or 0) + 1 end
        inventoryTables[data.equipment.inventory] = true
        EP.invalidate()
    end
    local function notify(key)
        revisions[key] = (revisions[key] or 0) + 1
        local callbacks = subscriptions[key] or {}
        for i = 1, #callbacks do callbacks[i](modules[key], key) end
    end
    local function resetCounts() for key in pairs(counts) do counts[key] = 0 end end
    return { EP = EP, Eq = Eq, EC = EC, HC = HC, AD = AD, AVC = AVC, ESC = ESC, detail = detail,
        modules = modules, counts = counts, setData = setData, notify = notify, reset = resetCounts,
        subscriptions = subscriptions, store = store, inventoryTables = inventoryTables }
end

local function dataFor(ids)
    local data = { heroes = { roster = {}, teams = {}, deployed = {} },
        equipment = { inventory = {}, equipped = {}, nextSeq = 100 },
        artifacts = { bag = {}, equippedByTeam = {} }, talents = { litNodes = {} } }
    for index, id in ipairs(ids) do
        local team = math.floor((index - 1) / 4) + 1
        data.heroes.teams[team] = data.heroes.teams[team] or { slots = {} }
        local slots = data.heroes.teams[team].slots
        slots[#slots + 1] = id
        data.heroes.roster[tostring(id)] = { level = 70, awakening = {}, extraTalent = {} }
        data.equipment.equipped[tostring(id)] = {}
    end
    data.heroes.deployed = copy(data.heroes.teams[1] and data.heroes.teams[1].slots or {})
    return data
end
local function put(data, seq, template, stats, affixes)
    data.equipment.inventory[tostring(seq)] = { templateId = template, quality = 1, level = 1,
        baseStats = stats, affixes = affixes or {} }
end

-- 独立完整贡献 oracle：真实 applyEquip + 深副本完整重建，而非调用被测 evaluate。
local function oracle(f, ctx, seq, slot)
    local Eq, EP = f.Eq, f.EP
    local item = Eq.getFromInventory(ctx.equipmentData, seq)
    if not item then return nil end
    local slots = Eq.getHeroSlots(ctx.equipmentData, ctx.heroId) or {}
    if not slot then
        for _, name in ipairs(f.EC.SLOTS) do
            if tostring(slots[name]) == tostring(seq) then slot = name; break end
        end
    end
    slot = slot or item.slot
    if not slot then return nil end
    local same = tostring(slots[slot]) == tostring(seq)
        or (slot == "offhand" and item.grip == "twohand" and tostring(slots.weapon) == tostring(seq))
    local preview
    if same then preview = { valid = true, gain = 0, previewPower = ctx.currentPower,
        currentPower = ctx.currentPower, equipment = ctx.equipmentData }
    else preview = EP.evaluateLoadout(ctx, { [slot] = seq }) end
    if preview and preview.valid then
        local stripped = copy(preview.equipment)
        local strippedSlots = Eq.getHeroSlots(stripped, ctx.heroId) or {}
        for name, value in pairs(strippedSlots) do
            if tostring(value) == tostring(seq) then strippedSlots[name] = nil end
        end
        local bare = EP.buildContext(ctx.heroId, { heroes = ctx.heroesData, equipment = stripped,
            artifacts = ctx.artifactsData, talents = ctx.talentsData })
        preview.power = preview.previewPower - bare.currentPower
    end
    return preview
end
local function checkPreview(f, heroId, seq, slot, label)
    local ctx = f.EP.buildContext(heroId, f.modules)
    local expected = oracle(f, ctx, seq, slot)
    f.reset()
    local gain = f.EP.evaluateGain(ctx, seq, slot)
    local afterGain = copy(f.counts)
    local full = f.EP.evaluate(ctx, seq, slot)
    local afterFull = copy(f.counts)
    check((gain == nil) == (expected == nil), label .. " missing parity")
    if expected then
        check(full == gain and full.valid == expected.valid and full.error == expected.error, label .. " valid/error/memo parity")
        check(close(full.gain, expected.gain) and close(full.previewPower, expected.previewPower)
            and close(full.currentPower, expected.currentPower), label .. " exact gain/current/preview")
        if full.valid then
            check(close(full.power, expected.power), label .. " exact contribution")
            check(afterFull.power == afterGain.power + 1 and afterFull.apply == afterGain.apply,
                label .. " full lazily adds exactly one withoutPiece, no reequip")
        else check(afterFull.power == afterGain.power, label .. " rejection has no contribution rebuild") end
    end
    f.EP.evaluate(ctx, seq, slot)
    f.EP.evaluateGain(ctx, seq, slot)
    check(f.counts.power == afterFull.power and f.counts.apply == afterFull.apply, label .. " memo reuse both orders")
    local second = f.EP.buildContext(heroId, f.modules)
    local fullFirst = f.EP.evaluate(second, seq, slot)
    local before = copy(f.counts)
    check(f.EP.evaluateGain(second, seq, slot) == fullFirst, label .. " full-first memo identity")
    check(f.counts.power == before.power and f.counts.apply == before.apply, label .. " full-first gain adds no work")
end

local function scoringCases(f)
    local data = dataFor({ 1, 2, 20, 3, 6, 7, 8, 18 })
    put(data, 1, "W1", { { f.AD.PHYS_ATK, 12.25 } })
    put(data, 2, "W1", { { f.AD.PHYS_ATK, 0 } }, { { affixId = 18, value = 0.25, ascBonus = "3.5" } })
    data.equipment.inventory["2"].affixMult = "2.5"
    put(data, 3, "W7")
    put(data, 4, "O1")
    put(data, 5, "W25")
    put(data, 6, "W1"); data.equipment.inventory["6"].level = 71
    put(data, 7, "W13")
    put(data, 8, "C1", { { f.AD.ES_DMG_REDUCE, 90 }, { f.AD.MAG_DMG_BONUS, 20.125 }, { f.AD.MAG_PEN, 12.5 } })
    data.equipment.equipped["1"] = { weapon = 1, offhand = 4 }
    data.equipment.equipped["2"] = { weapon = 5 }
    data.artifacts = { bag = { { id = "one", artifactId = 5, value = 20 },
        { id = "two", artifactId = 12, value = 250 }, { id = "three", artifactId = 9, value = 300 } },
        equippedByTeam = { { { "one" } }, { { "two" } }, { { "three" } } } }
    data.talents.litNodes = { 113, 115, 124, 125, 126, 128 }
    f.setData(data)
    local before = copy(data)
    for _, case in ipairs({ { 1, 1, "weapon", "already" }, { 1, 2, "weapon", "fractional-affix" },
        { 1, 3, "weapon", "twohand-unload" }, { 1, 6, "weapon", "level-reject" },
        { 1, 5, "weapon", "class-reject" }, { 1, 2, "armor", "slot-reject" },
        { 1, 2, "offhand", "dual-locked" }, { 20, 5, "weapon", "teammate-transfer-melissa" },
        { 6, 8, "accessory", "team2-artifact" }, { 18, 8, "accessory", "team2-magic" },
        { 1, 9999, "weapon", "missing" } }) do
        checkPreview(f, case[1], case[2], case[3], case[4])
    end
    data.equipment.equipped["1"] = { weapon = 3, offhand = 4 }
    f.setData(data)
    checkPreview(f, 1, 3, "offhand", "twohand-display-placeholder")
    checkPreview(f, 1, 4, "offhand", "stale-offhand-already")
    checkPreview(f, 1, 2, "offhand", "twohand-illegal-offhand")
    data.equipment.equipped["1"] = { weapon = 3 }
    f.setData(data)
    checkPreview(f, 1, 4, "offhand", "offhand-unloads-twohand")
    data.equipment.equipped["1"] = { weapon = 1 }
    for _, branch in ipairs({ 220, 207 }) do
        data.heroes.roster["1"].advBranch = { second = branch }
        f.setData(data)
        checkPreview(f, 1, 2, "offhand", "dual-same-" .. branch)
        checkPreview(f, 1, 7, "offhand", "dual-different-" .. branch)
        checkPreview(f, 1, 4, "offhand", "dual-normal-offhand-" .. branch)
    end
    data.heroes.roster["1"].advBranch = nil
    data.equipment.inventory["2"].corruptCount = "2"
    data.equipment.inventory["2"].corruptRevert = { affixCount = "1", baseMult = "1",
        patches = { { ["1"] = "v", ["2"] = "7.5", ["3"] = true, layer = "2" } } }
    f.setData(data)
    before = copy(data)
    local first, second = f.EP.getContext(1), f.EP.getContext(20)
    check(first.equipmentData == second.equipmentData and first.equipmentData ~= data.equipment,
        "default contexts share only isolated equipment snapshot")
    check(first.equipmentData.inventory["2"].affixes ~= data.equipment.inventory["2"].affixes
        and first.equipmentData.inventory["2"].corruptRevert ~= data.equipment.inventory["2"].corruptRevert,
        "hydrate nested affixes/revert cannot touch source")
    local frozen = copy(first.equipmentData)
    f.EP.evaluateGain(first, 2, "weapon"); f.EP.evaluate(second, 5, "weapon")
    f.EP.evaluateLoadout(first, { weapon = 3, offhand = 4 })
    f.EP.evaluateLoadout(first, { weapon = 2, armor = 2 })
    check(equal(first.equipmentData, frozen) and equal(second.equipmentData, frozen), "all previews leave shared snapshot unchanged")
    check(equal(data, before), "contexts/hydrate/previews do not mutate actual equipment or hero/artifact/talent source")
    local explicit1 = f.EP.buildContext(1, data)
    local explicit2 = f.EP.buildContext(1, data)
    check(explicit1.equipmentData ~= explicit2.equipmentData and explicit1.equipmentData ~= first.equipmentData,
        "explicit options have independent snapshots")
    explicit1.equipmentData.inventory["2"].affixes[1].value = 999
    check(explicit2.equipmentData.inventory["2"].affixes[1].value ~= 999 and equal(data, before), "explicit snapshot mutation stays private")
    -- 未取整评分与当前正式轻穿戴ctx同口径；不修改轻batch路径。
    local batch = f.EP.createWornBatch(data)
    for _, id in ipairs({ 1, 2, 3, 6, 7, 8, 18, 20 }) do
        local worn = f.EP.buildWornContext(id, data, batch)
        local full = f.EP.buildContext(id, data)
        check(close(worn.currentPower, full.currentPower), "wornBatch exact current-power parity hero=" .. id)
    end
    -- 六件末祷同队光环：用真实配置找模板，不能用通用价值代替套装贡献。
    local Sets = f.EC.ITEMS
    local ESC = f.ESC
    -- 同fixture的真实套装映射通过模板名称/显式setId解析，不假设配置已有setId。
    local config = f.HC.get(9)
    local setData = dataFor({ 9, 1 })
    local seq = 100
    for _, slot in ipairs(f.EC.SLOTS) do
        local wearable = f.Eq.getWearableTypeSet(9, slot)
        local selected
        for id, tpl in pairs(Sets) do
            if ESC.getSetIdForTemplate(tpl) == "last_rite" and tpl.slot == slot and (not wearable or wearable[tpl.type])
                and (slot ~= "weapon" or tpl.grip == "onehand") then selected = id; break end
        end
        check(selected ~= nil, "last_rite template exists " .. slot .. " class=" .. tostring(config.classId))
        if selected then put(setData, seq, selected); setData.equipment.equipped["9"][slot] = seq; seq = seq + 1 end
    end
    put(setData, 200, "C1", {})
    f.setData(setData)
    checkPreview(f, 9, 200, "accessory", "lose-last-rite-six-aura")
    local withAura = f.EP.getContext(1)
    check(withAura.hero.attrs.modifiers.set6_last_rite ~= nil, "teammate last_rite6 aura still active")
end

local function cacheCases(f)
    local data = dataFor({ 1, 2, 20 })
    put(data, 1, "W1"); put(data, 2, "W1", { { f.AD.PHYS_ATK, 30.125 } })
    data.equipment.equipped["1"].weapon = 1
    f.setData(data)
    -- 真实通知顺序复现：评分刷新者先订阅，EP getContext 的懒订阅若迟到会清新ctx。
    local builtDuringNotify
    f.store.Subscribe("equipment", function() f.EP.invalidate(); builtDuringNotify = f.EP.getContext(1) end)
    local old = f.EP.getContext(1)
    f.notify("equipment")
    local contexts = f.counts.context
    check(f.EP.getContext(1) == builtDuringNotify and f.counts.context == contexts,
        "late invalidation subscription cannot evict freshly-built notification context")
    check(#f.subscriptions.equipment == 1, "revision store has no redundant EP invalidation subscriber")
    f.EP.evaluateGain(old, 2, "weapon")
    local newBase = f.EP.getContext(1)
    local priorGain = f.EP.evaluateGain(newBase, 2, "weapon").gain
    data.equipment.inventory["2"].baseStats[1][2] = 90.5
    f.notify("equipment")
    local changed = f.EP.getContext(1)
    check(changed ~= newBase and f.EP.evaluateGain(changed, 2, "weapon").gain > priorGain,
        "in-place equipment notification updates memo and snapshot")
    check(newBase.equipmentData.inventory["2"].baseStats[1][2] == 30.125, "old snapshot remains frozen after live mutation")
    local equipment = changed.equipmentData
    for _, key in ipairs({ "heroes", "artifacts", "talents" }) do
        local previous = f.EP.getContext(20)
        if key == "heroes" then data.heroes.roster["20"].level = 71
        elseif key == "artifacts" then data.artifacts.bag = { { id = "x", artifactId = 5, value = 90 } }
        else data.talents.litNodes = { 125 } end
        f.notify(key)
        local current = f.EP.getContext(20)
        check(current ~= previous and current.equipmentData == equipment,
            key .. " revision rebuilds hero ctx without another inventory clone")
    end
    local ctx = f.EP.getContext(20)
    local previousPower = ctx.currentPower
    f.modules.heroes = copy(data.heroes)
    f.modules.heroes.roster["20"].level = 72
    check(f.EP.getContext(20) ~= ctx and f.EP.getContext(20).currentPower ~= previousPower,
        "source hero identity replacement rebuilds even without revision change")
    ctx = f.EP.getContext(1)
    f.modules.equipment = copy(data.equipment)
    check(f.EP.getContext(1) ~= ctx and f.EP.getContext(1).equipmentData ~= ctx.equipmentData,
        "source equipment identity replacement rebuilds frozen snapshot")
    local beforeClear = f.EP.getContext(1)
    f.modules.heroes, f.modules.equipment, f.modules.artifacts, f.modules.talents = nil, nil, nil, nil
    for _, key in ipairs({ "heroes", "equipment", "artifacts", "talents" }) do f.notify(key) end
    local clear = f.EP.getContext(1)
    check(clear ~= beforeClear and next(clear.equipmentData.inventory) == nil, "clear cache does not borrow previous player's equipment")
    f.setData(dataFor({ 1 }))
    check(next(f.EP.getContext(1).equipmentData.inventory) == nil, "reset/new session stays isolated")
    local legacy = fixture(true)
    legacy.setData(copy(data))
    local legacyCtx = legacy.EP.getContext(1)
    local directBefore = legacy.EP.buildContext(1)
    legacy.modules.equipment.inventory["2"].baseStats[1][2] = 110.5
    local directAfter = legacy.EP.buildContext(1)
    check(directAfter.equipmentData ~= directBefore.equipmentData
        and directBefore.equipmentData.inventory["2"].baseStats[1][2] == 90.5
        and directAfter.equipmentData.inventory["2"].baseStats[1][2] == 110.5,
        "without revisions direct build keeps fresh-per-call snapshot even without notification")
    legacy.notify("equipment")
    check(legacy.EP.getContext(1) ~= legacyCtx and #legacy.subscriptions.equipment == 1,
        "without revisions original notification invalidation fallback retained")
end

local function bruteBadge(f, heroId, slot)
    local ctx = f.EP.buildContext(heroId, f.modules)
    local occupied = {}
    for _, slots in pairs(f.modules.equipment.equipped) do
        for _, seq in pairs(slots) do occupied[tonumber(seq)] = true end
    end
    for seq in pairs(f.modules.equipment.inventory) do
        if tonumber(seq) and not occupied[tonumber(seq)] then
            local result = f.EP.evaluate(ctx, seq, slot)
            if result and result.valid and result.gain > 1e-6 then return true end
        end
    end
    return false
end
local function badgeCases(f)
    local data = dataFor({ 1, 2 })
    put(data, 1, "W1", { { f.AD.PHYS_ATK, 900 } })
    put(data, 2, "W1", { { f.AD.PHYS_ATK, 900 } })
    put(data, 3, "W7", { { f.AD.PHYS_ATK, 950 } })
    put(data, 4, "W25", { { f.AD.MAG_ATK, 1200 } })
    put(data, 5, "W1", { { f.AD.PHYS_ATK, 1900 } }); data.equipment.inventory["5"].level = 71
    put(data, 6, "O1", { { f.AD.ARMOR, 20 } })
    put(data, 7, "W13", { { f.AD.PHYS_ATK, 1500 } })
    put(data, 8, "C1", { { f.AD.MAX_HP, 7000 } })
    data.equipment.inventory["invalid-id"] = { templateId = "C1", quality = 1, level = 1 }
    data.equipment.equipped["1"] = { weapon = 1, offhand = 6 }
    data.equipment.equipped["2"] = { weapon = 2, accessory = 8 }
    for _, branch in ipairs({ false, 220, 207 }) do
        data.heroes.roster["1"].advBranch = branch and { second = branch } or nil
        f.setData(data)
        local any = false
        for _, slot in ipairs(f.EC.SLOTS) do
            local expected = bruteBadge(f, 1, slot)
            local actual = f.detail._hasUpgradeForSlot(1, slot, data.equipment)
            check(actual == expected, "candidate filter preserves authoritative badge " .. slot .. " dual=" .. tostring(branch))
            any = any or expected
        end
        check(f.detail.hasAnyUpgradeForHero(1) == any, "hasAny equals brute-force six slots dual=" .. tostring(branch))
        f.reset()
        f.detail.hasAnyUpgradeForHero(1)
        check(f.counts.power == 0 and f.counts.gain == 0 and f.counts.inventoryScans == 0,
            "cached badge does not rescan candidates or simulate")
    end
    -- 正确高等级装备/锁定装备仍可升级，不把锁定误当不可穿；微小提升不提前round。
    data.heroes.roster["1"].advBranch = nil
    data.equipment.inventory["3"].baseStats = { { f.AD.PHYS_ATK, 0 } }
    data.equipment.inventory["7"].baseStats = { { f.AD.PHYS_ATK, 0 } }
    data.equipment.inventory["5"].level = 70
    data.equipment.inventory["5"].locked = true
    f.setData(data)
    check(f.detail._hasUpgradeForSlot(1, "weapon", data.equipment), "same-level locked equipment remains upgrade candidate")
    data.equipment.inventory["5"].baseStats = { { f.AD.PHYS_ATK, 900.00001 } }
    f.notify("equipment")
    check(f.detail._hasUpgradeForSlot(1, "weapon", data.equipment), "unrounded tiny gain badge survives filtering")
    data.equipment.inventory["5"].baseStats = { { f.AD.PHYS_ATK, 800 } }
    f.notify("equipment")
    check(not f.detail._hasUpgradeForSlot(1, "weapon", data.equipment), "in-place notification clears cached true badge")
    local checkpoints = 0
    f.EP.invalidate()
    local co = coroutine.create(function()
        return f.detail.hasAnyUpgradeForHero(1, function() checkpoints = checkpoints + 1; coroutine.yield() end)
    end)
    local result, resumes = false, 0
    while coroutine.status(co) ~= "dead" do
        local ok, value = coroutine.resume(co)
        check(ok, "optional checkpoint coroutine resumes without error")
        result = value
        resumes = resumes + 1
        if not ok then break end
    end
    check(checkpoints > 0 and resumes == checkpoints + 1 and result == false,
        "optional candidate hook yields and final badge matches synchronous result")
end

local function performance(f, count)
    local ids = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 18, 20 }
    local data = dataFor(ids)
    for seq = 1, count do
        -- 全部为合法/等价饰品，最坏无提升；任何英雄均须评估到底。
        put(data, seq, "C1", {})
    end
    f.setData(data)
    local before = copy(data)
    f.reset()
    local started = os.clock()
    local allFalse = true
    for _, id in ipairs(ids) do allFalse = not f.detail.hasAnyUpgradeForHero(id) and allFalse end
    local elapsed = (os.clock() - started) * 1000
    local counts = copy(f.counts)
    check(allFalse, "large inventory all equivalent candidates has no false upgrades count=" .. count)
    check(counts.hydrate == count and counts.context == #ids,
        "large inventory is hydrated once, not once per hero count=" .. count)
    check(counts.power == #ids * (count + 1) and counts.gain == #ids * count,
        "large badge computes gain exactly once per compatible candidate, no withoutPiece count=" .. count)
    -- 计数器在首ctx返回时登记副本：捕获源copy与候选index遍历，hydrate遍历在登记前。
    check(counts.inventoryScans == 2, "large badge counted source copy/index scans once count=" .. count)
    check(equal(data, before), "large badge does not mutate source count=" .. count)
    f.reset()
    started = os.clock()
    for _, id in ipairs(ids) do f.detail.hasAnyUpgradeForHero(id) end
    local cachedMs = (os.clock() - started) * 1000
    check(f.counts.context == 0 and f.counts.power == 0 and f.counts.gain == 0 and f.counts.inventoryScans == 0,
        "large cached badge zero rebuilds/scans/evaluations count=" .. count)
    print(string.format("%s PERF inventory=%d heroes=%d cpuMs=%.3f cachedMs=%.3f hydrate=%d contexts=%d gainCalls=%d powerCalls=%d apply=%d scans=%d",
        TAG, count, #ids, elapsed, cachedMs, counts.hydrate, counts.context, counts.gain, counts.power, counts.apply, counts.inventoryScans))
end

function Start()
    local ok, err = pcall(function()
        local f = fixture()
        scoringCases(f)
        cacheCases(f)
        badgeCases(f)
        performance(f, 500)
        performance(f, 1000)
    end)
    if not ok then check(false, "exception " .. tostring(err)) end
    print(string.format("%s %s assertions=%d failures=%d", TAG, failures == 0 and "ALL PASS" or "FAIL", assertions, failures))
    if engine then engine:Exit() end
    assert(failures == 0, "equipment power regression failures=" .. failures)
end
