-- 神器与角色/装备评分口径隔离回归；只读源码，全部玩家数据为私有内存夹具。
-- Runtime: tests/artifact_character_power_test.lua -tool_mode -graphicsheadless -nosound
-- Source: lupa.lua54；不启动 main，不借 package.loaded，不接触 File/FS/真实档。
-- 可选 -artifact-power-shard=1..4：按神器ID分四片；每片保留全部六场景和尾部回归。
local TAG = "[artifact_character_power_test]"
local artifactFirst, artifactStep = 1, 1
for _, argument in ipairs(type(GetArguments) == "function" and GetArguments() or {}) do
    local shard = argument:match("^%-artifact%-power%-shard=(%d+)$")
    if shard then
        local index = assert(tonumber(shard))
        assert(index >= 1 and index <= 4, "artifact shard must be 1..4")
        artifactFirst, artifactStep = index, 4
    end
end
local assertions, failures, matrixCases = 0, 0, 0
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
    local out = {}; seen[value] = out
    for key, item in pairs(value) do out[key] = copy(item, seen) end
    return out
end
local function equal(a, b, approximate)
    if type(a) ~= type(b) then return false end
    if approximate and type(a) == "number" then return close(a, b) end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key], approximate) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function source(path)
    assert(path:match("%.lua$") and not path:find("..", 1, true) and path ~= "main.lua", "source-only path")
    local file = assert(cache:GetFile(path), "missing source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

-- 与 equipment_power_perf_test / character_detail_performance_test 相同的私有源码图。
-- 只有显示格式、Store/Dispatcher、Owned边界为替身；HC/装备/套装/神器/估值均真实。
local function fixture()
    local loaded, data, revisions = {}, {}, {}
    local counts = { io = 0, reads = 0, owned = 0, bridge = 0 }
    local probe = { builds = {}, powers = {}, enabled = false }
    local function forbidden() counts.io = counts.io + 1; error("player IO forbidden", 2) end
    local env = setmetatable({}, { __index = _G })
    env._G, env.File, env.io, env.dofile, env.loadfile = env, forbidden, false, forbidden, forbidden
    env.package = { loaded = loaded }
    env.fileSystem = setmetatable({}, { __index = function() return forbidden end })
    env.FileSystem, env.GetFileSystem = forbidden, forbidden
    env.cache = { GetFile = forbidden, GetResource = forbidden }
    local store = {
        Get = function(key) counts.reads = counts.reads + 1; return data[key] end,
        GetRevision = function(key) return revisions[key] or 0 end,
        Subscribe = function() end,
    }
    loaded["core.PlayerStore"] = store
    loaded["runtime.ClientDispatcher"] = { get = store.Get }
    loaded["core.I18n"] = { get = function() return "zh" end, t = function(s) return s end,
        lookup = function(s) return s end, format = string.format }
    loaded["core.I18nEquipmentText"] = { lookup = function(s) return s end }
    loaded["ui.character.panel.CharacterPanel"] = { getOwnedHero = function()
        counts.owned = counts.owned + 1; error("real Owned fallback forbidden")
    end }
    loaded["ui.character.detail.CharacterAttributeView"] = {
        formatNumber = function(v) return tostring(math.floor(v + 0.5)) end,
        formatInterval = function(v) return string.format("%.2f", v) end,
    }
    env.require = function(name)
        if loaded[name] then return loaded[name] end
        assert(name:match("^config%.") or name:match("^systems%.") or name:match("^shared%.")
            or name == "core.BattleLayout" or name:match("^ui%.church%.talent%.")
            or name:match("^ui%.widget%.TalentGlyph")
            or name == "ui.character.detail.CharacterDetailAttrs"
            or name == "ui.character.detail.EquipmentPreview"
            or name == "ui.character.detail.CharacterDetailSnapshot", "undeclared dependency " .. name)
        local path = name:gsub("%.", "/") .. ".lua"
        local value = assert(load(source(path), "@artifact-private/" .. path, "t", env))()
        loaded[name] = assert(value, name)
        if name == "systems.ArtifactBridge" then
            local apply = value.applyToUnit
            value.applyToUnit = function(...)
                counts.bridge = counts.bridge + 1
                return apply(...)
            end
        elseif name == "systems.CombatPower" then
            local calculate = value.calculate
            value.calculate = function(unit, context)
                if probe.enabled then
                    probe.powers[#probe.powers + 1] = { unit = unit, context = context }
                end
                return calculate(unit, context)
            end
        elseif name == "systems.EquipmentPower" then
            local build = value.buildContext
            value.buildContext = function(id, options)
                local ctx = build(id, options)
                if probe.enabled then probe.builds[#probe.builds + 1] = { options = options, ctx = ctx } end
                return ctx
            end
        end
        return value
    end
    local f = { counts = counts, probe = probe, env = env, loaded = loaded, data = data }
    for key, name in pairs({ EP = "systems.EquipmentPower", Eq = "systems.EquipmentSystem",
        AD = "systems.AttributeDef", HC = "config.HeroConfig", EC = "config.EquipmentConfig",
        Sets = "systems.EquipmentSetSystem", ESR = "systems.EquipmentSetRuntime",
        ESC = "config.EquipmentSetConfig", Bridge = "systems.ArtifactBridge", CP = "systems.CombatPower",
        Defs = "shared.artifact.ArtifactDefs", AVC = "config.AdvancementConfig",
        Attrs = "ui.character.detail.CharacterDetailAttrs", Preview = "ui.character.detail.EquipmentPreview" }) do
        f[key] = env.require(name)
    end
    function f.setData(value)
        for key in pairs(data) do data[key] = nil end
        for key, item in pairs(value) do data[key] = item; revisions[key] = (revisions[key] or 0) + 1 end
        f.EP.invalidate()
    end
    function f.startProbe() probe.builds, probe.powers, probe.enabled = {}, {}, true end
    function f.stopProbe() probe.enabled = false end
    return f
end

local function optionsFor(data, enabled)
    return { heroes = data.heroes, equipment = data.equipment, artifacts = data.artifacts,
        talents = data.talents, includeArtifactEffects = enabled, cacheFixedTeammates = true }
end
local function position(heroes, id)
    for team = 1, 3 do
        local row = heroes.teams and (heroes.teams[team] or heroes.teams[tostring(team)])
        local ids = heroes.teams and (row and row.slots or {}) or (team == 1 and heroes.deployed or {}) or {}
        for slot = 1, 4 do
            local entry = ids[slot] or ids[tostring(slot)]
            if tonumber(type(entry) == "table" and entry.heroId or entry) == id then return slot, team, ids end
        end
    end
    return nil, nil, { id }
end

-- 独立旧真实单位oracle：HC -> 有效装备逐槽/去重/双手 -> 两件套 -> ESR四件
-- -> Bridge神器 -> ESR队伍六件光环。顺序不可缩成“裸HC+神器”，也不调用EP.build/applyEquipment。
local function manualTeam(f, data, targetId, enabled, detailStyle)
    local world = copy(data)
    local _, _, ids = position(world.heroes, targetId)
    local units, seen = {}, {}
    local function add(id)
        if not id or seen[id] or not f.HC.get(id) then return end
        seen[id] = true
        local hd = world.heroes.roster[id] or world.heroes.roster[tostring(id)] or {}
        local unit = assert(f.HC.createHero(id, hd.level or 1, hd.advBranch, hd.awakening or {}, hd.extraTalent or {},
            { litNodes = world.talents.litNodes or false, silent = true }))
        unit.awakening = hd.awakening or {}
        -- EP旧管线clone seed；Detail直接消费HC，保留fillHp的一次重算标记。
        -- 两条完整oracle各自保留原顺序/瞬时HP语义，不抹掉final.hp来伪造deep相等。
        if not detailStyle then unit.attrs = unit.attrs:clone() end
        local slots = f.Eq.getHeroSlots(world.equipment, id) or {}
        local main = slots.weapon and f.Eq.getFromInventory(world.equipment, slots.weapon)
        local applied = {}
        for _, slot in ipairs(f.EC.SLOTS) do
            local seq = slots[slot]
            if seq and not (slot == "offhand" and main and main.grip == "twohand") then
                local item = f.Eq.getFromInventory(world.equipment, seq)
                if item and not applied[tostring(seq)] then
                    f.Eq.applyToUnit(unit.attrs, item, seq, f.Eq.getAscendBoost(item))
                    applied[tostring(seq)] = true
                    if slot == "armor" and f.AD.ARMOR_TYPE_ENUM[item.type] then
                        unit.attrs.armorType = f.AD.ARMOR_TYPE_ENUM[item.type]
                    end
                end
            end
        end
        f.Sets.applyToUnit(unit.attrs, world.equipment, id, f.Eq.getFromInventory, f.Eq.getHeroSlots)
        f.ESR.applyStaticBonuses(unit.attrs)
        local slot, team = position(world.heroes, id)
        unit.partySlot, unit.teamIdx, unit.artifactEffects = slot, team, {}
        if enabled and slot then unit.artifactEffects = f.Bridge.applyToUnit(unit.attrs, slot, world.artifacts, team) end
        units[#units + 1] = unit
    end
    for slot = 1, 4 do
        local entry = ids[slot] or ids[tostring(slot)]
        add(tonumber(type(entry) == "table" and entry.heroId or entry))
    end
    add(targetId)
    f.ESR.applyTeamAura(units)
    local target
    for _, unit in ipairs(units) do if unit.heroId == targetId then target = unit end end
    return target, units, world
end
local function manualPower(f, data, id, enabled)
    local target, units, world = manualTeam(f, data, id, enabled)
    return f.CP.calculate(target, { teamUnits = units, heroesData = world.heroes,
        equipmentData = world.equipment, artifactsData = enabled and world.artifacts or {}, talentsData = world.talents }), target, units
end
local function sameUnits(a, b, approximate)
    if #a ~= #b then return false end
    for index, unit in ipairs(a) do
        local other = b[index]
        if unit.heroId ~= other.heroId or unit.partySlot ~= other.partySlot or unit.teamIdx ~= other.teamIdx
            or not equal(unit.attrs, other.attrs, approximate)
            or not equal(unit.artifactEffects, other.artifactEffects, approximate) then return false end
    end
    return true
end
local function checkContext(actual, expected, label)
    check(close(actual.currentPower, expected.currentPower), label .. " currentPower")
    check(equal(actual.hero.attrs, expected.hero.attrs), label .. " hero.attrs deep exact")
    check(sameUnits(actual.teamUnits, expected.teamUnits), label .. " all teammates attrs/effects deep exact")
    for _, unit in ipairs(actual.teamUnits) do
        check(type(unit.artifactEffects) == "table" and next(unit.artifactEffects) == nil,
            label .. " explicit empty effects hero=" .. unit.heroId)
    end
end
local function checkResult(a, b, label)
    check(a ~= nil and b ~= nil, label .. " exists")
    if not a or not b then return end
    check(a.valid == b.valid and a.error == b.error, label .. " validity")
    for _, key in ipairs({ "currentPower", "previewPower", "gain", "power" }) do
        check(a[key] == nil and b[key] == nil or close(a[key], b[key]), label .. " " .. key)
    end
end

local function put(f, data, seq, template, extra)
    local AD = f.AD
    local stats = { { AD.MAX_HP, 171.25 }, { AD.PHYS_ATK, 21.125 }, { AD.MAG_ATK, 34.5 },
        { AD.HEAL_AMOUNT, 9 }, { AD.HP_BONUS, 7.25 }, { AD.ENERGY_SHIELD, 60 },
        { AD.CRIT_RATE, 45 }, { AD.CRIT_DMG, 31 }, { AD.PHYS_BLOCK_RATE, 125 }, { AD.MAG_BLOCK_RATE, 125 },
        { AD.MAG_DMG_BONUS, 17 }, { AD.MAG_PEN, 11 }, { AD.HP_REGEN, 4 }, { AD.ATK_HEAL, 3 },
        { AD.ES_DMG_REDUCE, 25 }, { AD.HIT_VALUE, 200 } }
    if extra then for _, row in ipairs(extra) do stats[#stats + 1] = row end end
    data.equipment.inventory[tostring(seq)] = { templateId = template, level = 1, quality = 1,
        baseStats = stats, affixes = { { affixId = 18, value = 0.25, ascBonus = "3.5" } },
        affixMult = "1.25", corruptRevert = { patches = { { ["1"] = "v", ["2"] = "7.5", layer = "2" } } } }
end
local function giveSet(f, data, id, setId, count)
    local seq = id * 100
    for _, slot in ipairs(f.EC.SLOTS) do
        if count <= 0 then break end
        local wearable = f.Eq.getWearableTypeSet(id, slot)
        local candidates = {}
        for template, def in pairs(f.EC.ITEMS) do
            if def.slot == slot and f.ESC.getSetIdForTemplate(def) == setId
                and (not wearable or wearable[def.type]) and (slot ~= "weapon" or def.grip == "onehand") then
                candidates[#candidates + 1] = template
            end
        end
        table.sort(candidates)
        local selected = candidates[1]
        if selected then
            seq = seq + 1
            put(f, data, seq, selected)
            data.equipment.equipped[tostring(id)][slot] = seq
            count = count - 1
        end
    end
    assert(count == 0, "insufficient wearable set pieces " .. setId .. " hero=" .. id)
end
local function baseData(f)
    local data = { heroes = { roster = {}, teams = {}, deployed = { 25 } },
        equipment = { inventory = {}, equipped = {}, nextSeq = 9000 }, artifacts = {},
        talents = { litNodes = { 113, 115, 124, 125, 126, 128 } } }
    for _, id in ipairs({ 1, 6, 7, 9, 14, 15, 17, 18, 20, 23, 25 }) do
        data.heroes.roster[tostring(id)] = { level = 80, awakening = { [1] = true, [3] = true, [7] = true },
            extraTalent = { issuedCards = 3, attackCount = 100, killCount = 20 } }
        data.equipment.equipped[tostring(id)] = { accessory = id }
        put(f, data, id, "C1")
    end
    giveSet(f, data, 9, "last_rite", 6)
    giveSet(f, data, 7, "nitros", 4)
    giveSet(f, data, 6, "starless", 4)
    put(f, data, 8001, "C1", { { f.AD.PHYS_ATK, 40.375 }, { f.AD.MAG_ATK, 55.25 } })
    put(f, data, 8002, "C1", { { f.AD.PHYS_ATK, 70.5 } })
    data.equipment.inventory["8002"].level = 81
    return data
end
local SCENARIOS = {
    { name = "team1-melissa-healer-aura", team = 1, ids = { 1, 18, 9, 20 }, owner = 2 },
    { name = "team2-static-sets", team = 2, ids = { 17, 15, 7, 6 }, owner = 2 },
    { name = "team3-sparse-string", team = 3, ids = { [2] = 14, [4] = 23 }, owner = 2, strings = true },
    { name = "legacy-deployed", team = 1, ids = { 1, 18, 9, 20 }, owner = 2, legacy = true },
    { name = "bench-stale-deployed", team = 2, ids = { 1, 18, 9, 20 }, owner = 2, bench = true },
    { name = "adjacent-empty-owner", team = 3, ids = { 1, 0, 20, 9 }, owner = 2 },
}
local function scenarioData(f, scenario)
    local data = baseData(f)
    if scenario.legacy then data.heroes.teams = nil; data.heroes.deployed = copy(scenario.ids)
    elseif scenario.strings then
        local ids = {}; for slot, id in pairs(scenario.ids) do ids[tostring(slot)] = tostring(id) end
        data.heroes.teams[tostring(scenario.team)] = { slots = ids }
    else data.heroes.teams[scenario.team] = { slots = copy(scenario.ids) } end
    return data
end
local function artifactData(f, id, team, owner)
    local range = assert(f.Defs.getRange(id, 6))
    return { bag = { { id = "real_" .. id, artifactId = id, quality = 6,
        value = (range[1] + range[2]) / 2, threatClearValue = 80 } },
        equippedByTeam = { [team] = { [owner] = { [2] = "real_" .. id } } } }
end
local function targetIds(scenario)
    local ids = {}
    for slot = 1, 4 do
        local id = scenario.ids[slot]
        if id and id > 0 then ids[#ids + 1] = id end
    end
    if scenario.bench then ids[#ids + 1] = 25 end
    return ids
end
local function branches(f, id)
    local first, second = {}, {}
    for branchId, branch in pairs(f.AVC.BRANCHES) do
        if branch.baseClass == f.HC.get(id).classId then
            local list = branch.advLevel == f.AVC.ADV_FIRST and first or second
            list[#list + 1] = branchId
        end
    end
    table.sort(first); table.sort(second)
    return assert(first[1]), assert(second[1])
end

local function realContext(f, ctx, data, enabled, label)
    local power, target, units = manualPower(f, data, ctx.heroId, enabled)
    check(close(ctx.currentPower, power), label .. " independent complete-chain power")
    check(equal(ctx.hero.attrs, target.attrs, true) and sameUnits(ctx.teamUnits, units, true),
        label .. " independent complete-chain all attrs/effects")
end
local function previewOracle(f, ctx, result, enabled, label)
    check(result and result.valid == true, label .. " valid preview")
    if not result or not result.valid then return end
    local data = { heroes = ctx.heroesData, equipment = result.equipment,
        artifacts = ctx.artifactsData, talents = ctx.talentsData }
    check(close(result.previewPower, manualPower(f, data, ctx.heroId, enabled)), label .. " rebuilt preview power")
end

local function matrix(f)
    local definitions = 0
    for _ in pairs(f.Defs.ARTIFACTS) do definitions = definitions + 1 end
    check(definitions == 16, "matrix enumerates all 16 real definitions")
    local changed = {}
    for _, scenario in ipairs(SCENARIOS) do
        local data = scenarioData(f, scenario)
        local baseline, scores = {}, {}
        for _, id in ipairs(targetIds(scenario)) do
            baseline[id] = f.EP.buildContext(id, optionsFor(data))
            f.setData(data)
            local baseline = baseline[id]
            local snapshotItem = f.Eq.getFromInventory(baseline.equipmentData, id)
            local snapshotCandidate = f.Eq.getFromInventory(baseline.equipmentData, 8001)
            local snapshotIllegal = f.Eq.getFromInventory(baseline.equipmentData, 8002)
            scores[id] = { f.EP.score(snapshotItem, id, "accessory"),
                f.EP.score(snapshotCandidate, id, "accessory"), f.EP.score(snapshotIllegal, id, "accessory") }
        end
        for artifactId = artifactFirst, 16, artifactStep do
            data.artifacts = artifactData(f, artifactId, scenario.team, scenario.owner)
            f.setData(data)
            local before = copy(data)
            local ordinaryOptions = optionsFor(data); ordinaryOptions.reuseTeamContext = true
            local ordinaryBatch = f.EP.createWornBatch(ordinaryOptions)
            local realOptions = optionsFor(data, true); realOptions.reuseTeamContext = true
            local realBatch = f.EP.createWornBatch(realOptions)
            local reusedTeam, reusedOrdinary = {}, {}
            for _, id in ipairs(targetIds(scenario)) do
                matrixCases = matrixCases + 1
                local label = scenario.name .. "/artifact=" .. artifactId .. "/hero=" .. id
                local bridgeBefore = f.counts.bridge
                local ctx = assert(f.EP.buildContext(id, optionsFor(data)))
                checkContext(ctx, baseline[id], label .. " default")
                checkContext(f.EP.buildContext(id, optionsFor(data, false)), baseline[id], label .. " false")
                checkContext(f.EP.buildContext(id), baseline[id], label .. " Store")
                local worn = f.EP.buildWornContext(id, { reuseTeamContext = true }, ordinaryBatch)
                checkContext(worn, baseline[id], label .. " worn/reuse")
                local _, team = position(data.heroes, id)
                local teamKey = team or ("hero:" .. id)
                if reusedOrdinary[teamKey] then
                    check(worn.teamUnits == reusedOrdinary[teamKey], label .. " reused default team remains artifact-free")
                end
                reusedOrdinary[teamKey] = worn.teamUnits
                for _, seq in ipairs({ id, 8001, 8002 }) do
                    checkResult(f.EP.evaluate(ctx, seq, "accessory"), f.EP.evaluate(baseline[id], seq, "accessory"), label .. " item=" .. seq)
                    checkResult(f.EP.evaluateGain(ctx, seq, "accessory"), f.EP.evaluateGain(baseline[id], seq, "accessory"), label .. " gain=" .. seq)
                end
                checkResult(f.EP.evaluateLoadout(ctx, { accessory = 8001 }),
                    f.EP.evaluateLoadout(baseline[id], { accessory = 8001 }), label .. " loadout")
                for _, branch in ipairs({ branches(f, id) }) do
                    checkResult(f.EP.evaluateAdvancement(ctx, branch), f.EP.evaluateAdvancement(baseline[id], branch), label .. " advancement=" .. branch)
                end
                for index, seq in ipairs({ id, 8001, 8002 }) do
                    check(f.EP.score(f.Eq.getFromInventory(ctx.equipmentData, seq), id, "accessory") == scores[id][index],
                        label .. " score normal/candidate/illegal=" .. seq)
                end
                check(f.counts.bridge == bridgeBefore, label .. " all default scoring paths never apply Bridge")
                local actual = assert(f.EP.buildContext(id, realOptions))
                realContext(f, actual, data, true, label .. " true")
                local realWorn = f.EP.buildWornContext(id, { reuseTeamContext = true }, realBatch)
                check(realWorn.includeArtifactEffects == true and realBatch.includeArtifactEffects == true,
                    label .. " true flag retained from batch without options flag")
                realContext(f, realWorn, data, true, label .. " true worn/reuse")
                if reusedTeam[teamKey] then
                    check(realWorn.teamUnits == reusedTeam[teamKey], label .. " actual reused team keeps true attrs")
                end
                reusedTeam[teamKey] = realWorn.teamUnits
                if not sameUnits(actual.teamUnits, baseline[id].teamUnits, true) then changed[artifactId] = true end
                local detail = f.Attrs.collectAttributes(id, f.HC.get(id), 80, data)
                local detailUnit = manualTeam(f, data, id, true, true)
                check(equal(detail.attrs, detailUnit.attrs, true), label .. " Detail retains complete real artifact chain")
                local preview = f.Preview.build(id, 80, 8001, "accessory", data)
                check(not preview.error and preview.preview ~= nil, label .. " EquipmentPreview valid")
                check(equal(preview.current.attrs, detail.attrs, true), label .. " Preview current retains real attrs")
                if preview.preview then
                    local loadout = f.EP.evaluateLoadout(actual, { accessory = 8001 })
                    previewOracle(f, actual, loadout, true, label .. " true loadout")
                    local world = optionsFor(data, true); world.equipment = loadout.equipment
                    local unit = manualTeam(f, world, id, true, true)
                    check(equal(preview.preview.attrs, unit.attrs, true), label .. " Preview after retains complete real chain")
                end
            end
            check(equal(data, before), scenario.name .. "/artifact=" .. artifactId .. " source all modules unchanged")
        end
    end
    for artifactId = artifactFirst, 16, artifactStep do check(changed[artifactId], "nonvacuous real attrs/runtime effects artifact=" .. artifactId) end
end

local function advancementAndIsolation(f)
    local data = scenarioData(f, SCENARIOS[1])
    -- 两子格混合，包含非交换生命转盾/禁疗、暴击/混沌、反击及左右邻位增益。
    data.artifacts = { bag = {}, equippedByTeam = { [1] = {} } }
    for index, artifactId in ipairs({ 3, 9, 12, 15, 2, 5, 7, 8 }) do
        local one = artifactData(f, artifactId, 1, 1).bag[1]
        data.artifacts.bag[#data.artifacts.bag + 1] = one
        local slot = math.floor((index - 1) / 2) + 1
        local row = data.artifacts.equippedByTeam[1][slot] or {}
        data.artifacts.equippedByTeam[1][slot] = row
        row[(index - 1) % 2 + 1] = one.id
    end
    f.setData(data)
    local before = copy(data)
    for _, enabled in ipairs({ false, true }) do
        local opts = optionsFor(data, enabled)
        local ctx = f.EP.buildContext(18, opts)
        realContext(f, ctx, data, enabled, "mixed true=" .. tostring(enabled))
        local frozenEquipment, frozenAttrs = copy(ctx.equipmentData), copy(ctx.hero.attrs)
        f.startProbe()
        local first, second = branches(f, 18)
        for _, branch in ipairs({ first, second }) do
            local start = #f.probe.builds
            local result = f.EP.evaluateAdvancement(ctx, branch)
            check(#f.probe.builds == start + 2, "advancement builds before/after true=" .. tostring(enabled))
            local a, b = f.probe.builds[start + 1], f.probe.builds[start + 2]
            if a and b then
                check(a.options.includeArtifactEffects == enabled and b.options.includeArtifactEffects == enabled
                    and a.ctx.includeArtifactEffects == enabled and b.ctx.includeArtifactEffects == enabled,
                    "advancement propagates flag before AND after")
                local ap = manualPower(f, { heroes = a.ctx.heroesData, equipment = a.ctx.equipmentData,
                    artifacts = a.ctx.artifactsData, talents = a.ctx.talentsData }, 18, enabled)
                local bp = manualPower(f, { heroes = b.ctx.heroesData, equipment = b.ctx.equipmentData,
                    artifacts = b.ctx.artifactsData, talents = b.ctx.talentsData }, 18, enabled)
                check(close(result.currentPower, ap) and close(result.previewPower, bp) and close(result.gain, bp - ap),
                    "advancement complete before/after independent oracle")
            end
        end
        f.stopProbe()
        f.EP.evaluate(ctx, 8001, "accessory")
        f.EP.evaluateLoadout(ctx, { accessory = 8001 })
        check(equal(ctx.equipmentData, frozenEquipment) and equal(ctx.hero.attrs, frozenAttrs), "previews do not mutate frozen ctx")
        local secondCtx = f.EP.buildContext(18, opts)
        ctx.equipmentData.inventory["8001"].affixes[1].value = 999
        ctx.artifactsData.bag[1].value = 999
        ctx.heroesData.roster["18"].level = 1
        ctx.talentsData.litNodes[1] = -1
        check(secondCtx.equipmentData.inventory["8001"].affixes[1].value ~= 999
            and secondCtx.artifactsData.bag[1].value ~= 999 and secondCtx.heroesData.roster["18"].level == 80,
            "explicit snapshot mutations remain independent")
        check(equal(data, before), "explicit ctx mutation never writes source")
    end
end

local function fallbackAndConsumers(f)
    local data = scenarioData(f, SCENARIOS[1])
    data.artifacts = artifactData(f, 5, 1, 1)
    f.setData(data)
    local before = copy(data)
    local ctx = f.EP.buildContext(1)
    local context = { heroesData = ctx.heroesData, equipmentData = ctx.equipmentData,
        artifactsData = ctx.artifactsData, talentsData = ctx.talentsData, teamUnits = ctx.teamUnits }
    local baseline = f.CP.calculate(ctx.hero, context)
    local unit = {}; for key, value in pairs(ctx.hero) do unit[key] = value end
    unit.artifactEffects = nil
    check(f.CP.calculate(unit, context) > baseline, "positive control: CombatPower generic counter fallback still works")
    check(close(baseline, ctx.currentPower) and next(ctx.hero.artifactEffects) == nil,
        "default empty artifactEffects stops counter fallback even with real artifact context")
    local real = f.EP.buildContext(1, optionsFor(data, true))
    check(real.currentPower > ctx.currentPower and #real.hero.artifactEffects > 0,
        "explicit true restores counter runtime and actual valuation")
    -- 私有估值spy仅观察参数，不改CombatPower生产公式。
    f.startProbe()
    local default = f.EP.buildContext(1)
    f.EP.evaluate(default, 8001, "accessory")
    f.EP.score(f.Eq.getFromInventory(default.equipmentData, 8002), 1, "accessory")
    f.stopProbe()
    for _, call in ipairs(f.probe.powers) do
        check(next(call.context.artifactsData) == nil and type(call.unit.artifactEffects) == "table"
            and next(call.unit.artifactEffects) == nil, "all default powerFor calls suppress artifacts and fallback")
    end
    local ordinary = f.Attrs.collectAttributes(1, f.HC.get(1), 80)
    local preview = f.Preview.build(1, 80, 8001, "accessory")
    local detailUnit = manualTeam(f, data, 1, true, true)
    check(equal(ordinary.attrs, detailUnit.attrs, true) and equal(preview.current.attrs, detailUnit.attrs, true),
        "implicit Detail/Preview consume real Store artifacts")
    -- 直接执行实际Sweep getLuck源码hunk；不加载PDM/事务/保存，也不发奖励。
    local text = source("rules/sweep/SweepService.lua")
    local hunk = assert(text:match("(local function getLuck%b().-\nend)"), "Sweep getLuck source contract")
    local callOptions = {}
    local sweepEnv = setmetatable({ EquipmentPower = { buildWornContext = function(id, options)
        callOptions = options
        return f.EP.buildWornContext(id, options)
    end }, DropSystem = f.env.require("systems.DropSystem") }, { __index = f.env })
    local getLuck = assert(load(hunk .. "\nreturn getLuck", "@actual-sweep-getLuck", "t", sweepEnv))()
    local luck = getLuck({ 1, 18, 9, 20 }, data.heroes, data.equipment, data.artifacts, data.talents)
    local _, units = manualTeam(f, data, 1, true)
    check(callOptions.includeArtifactEffects == true and close(luck, sweepEnv.DropSystem.captureTeamLuck(units)),
        "actual sweep getLuck explicitly true preserves real drop attrs")
    check(equal(data, before), "Store/Detail/Preview/Sweep never write source")
end

function Start()
    local ok, err = pcall(function()
        local f = fixture()
        local outerLoaded = package and package.loaded
        local hostHC = outerLoaded and outerLoaded["config.HeroConfig"]
        local hostEP = outerLoaded and outerLoaded["systems.EquipmentPower"]
        -- 私有HC默认星图哨兵，显式talents不得读取/更改它。
        f.HC.setDefaultLitNodes({ 209 })
        local defaults = copy(f.HC._getSavedLitNodes())
        local config = copy(f.HC.HEROES)
        matrix(f)
        advancementAndIsolation(f)
        fallbackAndConsumers(f)
        check(equal(f.HC._getSavedLitNodes(), defaults) and equal(f.HC.HEROES, config), "HC defaults/config unchanged")
        check(not outerLoaded or outerLoaded["config.HeroConfig"] == hostHC
            and outerLoaded["systems.EquipmentPower"] == hostEP, "host package.loaded unchanged")
        check(f.counts.io == 0 and f.counts.owned == 0, "zero player File/FS/Owned fallback attempts")
        print(string.format("%s MATRIX definitions=16 selected=%d first=%d step=%d scenarios=%d heroCases=%d io=%d owned=%d",
            TAG, math.floor((16 - artifactFirst) / artifactStep) + 1, artifactFirst, artifactStep,
            #SCENARIOS, matrixCases, f.counts.io, f.counts.owned))
    end)
    if not ok then check(false, "exception " .. tostring(err)) end
    print(string.format("%s %s assertions=%d failures=%d", TAG, failures == 0 and "ALL PASS" or "FAIL", assertions, failures))
    if engine then engine:Exit() end
    assert(failures == 0, "artifact character power failures=" .. failures)
end
