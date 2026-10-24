-- 详情属性收集/预览热点专项。仅使用源码夹具，不启动main、不读取玩家存档。
-- 可作为独立测试入口，或使用提供cache:GetFile的Lua 5.4源码测试器运行。
local TAG = "[character_detail_copy_hotpath_test]"
local assertions, failures = 0, 0
local function check(ok, text)
    assertions = assertions + 1
    if not ok then failures = failures + 1; print(TAG .. " FAIL " .. text) end
end
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, item in pairs(value) do out[key] = copy(item, seen) end
    return out
end
local function equal(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    seen = seen or {}
    if seen[a] then return seen[a] == b end
    seen[a] = b
    for key, value in pairs(a) do if not equal(value, b[key], seen) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function source(name)
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), name)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function fixture(size)
    local modules, data, revisions = {}, {}, {}
    local metrics = { inventory = 0, unused = 0, sorts = 0, rowSorts = 0, attrs = 0, io = 0 }
    local unused = {}
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.File = function() metrics.io = metrics.io + 1; error("player IO forbidden") end
    env.fileSystem = setmetatable({}, { __index = function() return env.File end })
    env.pairs = function(value)
        if data.equipment and value == data.equipment.inventory then metrics.inventory = metrics.inventory + 1 end
        if unused[value] then metrics.unused = metrics.unused + 1 end
        return pairs(value)
    end
    env.table = setmetatable({ sort = function(...)
        metrics.sorts = metrics.sorts + 1
        local caller = debug.getinfo(2, "S").source
        if caller:find("ui.character.detail.EquipmentPreview", 1, true) then
            metrics.rowSorts = metrics.rowSorts + 1
        end
        return table.sort(...)
    end }, { __index = table })
    local store = { Get = function(key) return data[key] end,
        GetRevision = function(key) return revisions[key] or 0 end }
    modules["core.PlayerStore"] = store
    modules["runtime.ClientDispatcher"] = { get = store.Get }
    modules["core.I18n"] = { get = function() return "zh" end, lookup = function(s) return s end,
        t = function(s) return s end, format = string.format }
    modules["core.GameState"] = {}
    modules["ui.character.detail.CharacterAttributeView"] = {
        formatNumber = function(v) return tostring(math.floor(v + 0.5)) end,
        formatInterval = function(v) return string.format("%.2f", v) end,
    }
    env.require = function(name)
        if modules[name] then return modules[name] end
        assert(not name:match("^runtime%.") and not name:match("^boot%."), "undeclared runtime " .. name)
        local value = assert(load(source(name), "@copy-hotpath/" .. name, "t", env))()
        modules[name] = value
        if name == "ui.character.detail.CharacterDetailAttrs" then
            local collect = value.collectAttributes
            value.collectAttributes = function(...)
                metrics.attrs = metrics.attrs + 1; return collect(...)
            end
        end
        return value
    end
    local Attrs = env.require("ui.character.detail.CharacterDetailAttrs")
    local Preview = env.require("ui.character.detail.EquipmentPreview")
    local Snapshot = env.require("ui.character.detail.CharacterDetailSnapshot")
    local HC, Eq = env.require("config.HeroConfig"), env.require("systems.EquipmentSystem")
    local EC, AD = env.require("config.EquipmentConfig"), env.require("systems.AttributeDef")
    data.heroes = { roster = {}, teams = { { slots = { 1, 2, 20, 18 } }, { slots = { 3 } }, { slots = {} } } }
    for _, id in ipairs({ 1, 2, 20, 18, 3 }) do
        data.heroes.roster[id] = { level = 80, awakening = {}, extraTalent = {} }
    end
    data.equipment = { inventory = {}, equipped = { [1] = {}, [2] = {}, [20] = {}, [18] = {}, [3] = {} } }
    data.artifacts, data.talents = { bag = {} }, { litNodes = {} }
    local template = assert(EC.BY_SLOT.accessory[1])
    for seq = 1, size do
        local item = { templateId = template, level = 1, quality = 1,
            affixes = { { affixId = 21, key = AD.PHYS_PEN, value = seq % 13, quality = 1 } },
            baseStats = { { AD.STR, seq % 19 } } }
        data.equipment.inventory[tostring(seq)] = item
        if seq > 6 then unused[item] = true end
    end
    data.equipment.equipped[1].accessory = 1
    data.equipment.equipped[2].accessory = 2
    data.equipment.equipped[20].accessory = 3
    data.equipment.equipped[18].accessory = 4
    data.equipment.equipped[3].accessory = 5
    -- 全量复制oracle保留真实属性公式，仅禁用输入裁剪。
    -- 因此在水合前也能检测已穿别名/队友装备被错误漏掉的情况。
    local fullEnv = setmetatable({}, { __index = env })
    fullEnv.require = function(name)
        if name == "ui.character.detail.CharacterDetailSnapshot" then
            return { compactEquipment = function(equipment) return equipment or {} end }
        end
        return env.require(name)
    end
    local full = assert(load(source("ui.character.detail.CharacterDetailAttrs"), "@full-copy-oracle", "t", fullEnv))()
    local f = { data = data, attrs = Attrs, preview = Preview, snapshot = Snapshot, full = full,
        HC = HC, Eq = Eq, EC = EC, AD = AD, env = env, metrics = metrics }
    function f.reset()
        for key in pairs(metrics) do metrics[key] = 0 end
    end
    function f.collect(id, explicit)
        return Attrs.collectAttributes(id, HC.get(id), 80, explicit and data or nil)
    end
    function f.measure(label, fn, count)
        collectgarbage("collect")
        f.reset()
        local start = os.clock()
        for _ = 1, count do fn() end
        local ms = (os.clock() - start) * 1000 / count
        print(string.format("%s CPU label=%s inventorySize=%d n=%d meanMs=%.4f inventoryScans=%d unusedItemScans=%d sorts=%d attrs=%d",
            TAG, label, size, count, ms, metrics.inventory, metrics.unused, metrics.sorts, metrics.attrs))
        return copy(metrics)
    end
    return f
end

local function run()
    local f = fixture(500)
    local before = copy(f.data)
    for _, id in ipairs({ 1, 2, 20, 18, 3 }) do
        local full = f.full.collectAttributes(id, f.HC.get(id), 80, f.data)
        f.reset()
        local actual = f.collect(id, true)
        check(equal(actual.left, full.left) and equal(actual.right, full.right)
            and equal(actual.stats, full.stats) and equal(actual.attrs.final, full.attrs.final),
            "projected collector matches full-copy formulas hero=" .. id)
        check(f.metrics.inventory == 0 and f.metrics.unused == 0, "collector does not enumerate unneeded inventory hero=" .. id)
    end
    local defaults = f.collect(1, false)
    local explicit = f.collect(1, true)
    check(equal(defaults.left, explicit.left) and equal(defaults.stats, explicit.stats), "default/explicit same source semantics")
    check(defaults.attrs ~= explicit.attrs and defaults.attrs.final ~= explicit.attrs.final,
        "each collector call returns independent mutable attributes")
    explicit.attrs.final[f.AD.STR] = -999
    explicit.left[1].value = "poison"
    check(not equal(defaults.left, explicit.left) and f.collect(1, true).attrs:get(f.AD.STR) ~= -999,
        "external result mutation cannot poison a later collector")
    local empty = f.attrs.collectAttributes(1, f.HC.get(1), 80, {})
    check(not equal(empty.stats, defaults.stats), "explicit empty options do not borrow live worn items")
    check(equal(before, f.data), "collection never hydrates or normalizes live source")

    -- 数字库存键与共享装备项仍可点查，且保持调用间隔离。
    f.data.equipment.inventory[1] = f.data.equipment.inventory["1"]
    f.data.equipment.inventory["1"] = nil
    f.data.equipment.equipped[1].helmet = 1
    local aliasExpected = f.full.collectAttributes(1, f.HC.get(1), 80, f.data)
    check(equal(f.collect(1, true).stats, aliasExpected.stats), "numeric seq and shared worn item match full-copy oracle")
    f.data.equipment.equipped[1].helmet = nil

    -- 星门只读取真实所属队；裁剪仍保留所有已穿映射（含非标准旧槽字段），
    -- 不能假设只有已知六槽而遗漏跨队装备引用。
    local oldTeams = copy(f.data.heroes.teams)
    f.data.heroes.teams = { { slots = { 1, 3 } }, { slots = { 20, 2, 18 } }, { slots = {} } }
    f.data.equipment.equipped[3].legacyExtraSlot = 6
    local projected = f.snapshot.compactEquipment(f.data.equipment)
    check(projected.equipped[3].legacyExtraSlot == 6 and projected.inventory["6"] ~= nil,
        "projection preserves cross-team and nonstandard slot references")
    local cross = f.full.collectAttributes(20, f.HC.get(20), 80, f.data)
    local crossActual = f.collect(20, true)
    check(equal(crossActual.right, cross.right) and equal(crossActual.stats, cross.stats),
        "team2 star gate and teammate contributions match full-copy oracle")
    local weaponId
    for _, id in ipairs(f.EC.BY_SLOT.weapon) do
        if f.EC.ITEMS[id].grip == "twohand" then weaponId = id; break end
    end
    assert(weaponId, "twohand template required")
    f.data.equipment.inventory["6"] = { templateId = weaponId, level = 1, quality = 1, affixes = {} }
    f.data.equipment.equipped[20].weapon = 6
    f.data.equipment.equipped[20].offhand = 6
    local twohandBefore = copy(f.data)
    local twohand = f.full.collectAttributes(20, f.HC.get(20), 80, f.data)
    local first = f.collect(20, true)
    local second = f.collect(20, true)
    check(equal(first.left, twohand.left) and equal(first.right, twohand.right),
        "twohand main/offhand alias matches full-copy collector")
    check(first.attrs ~= second.attrs and first.attrs.final ~= second.attrs.final and equal(f.data, twohandBefore),
        "cross-team twohand results remain per-call private and never hydrate live items")
    f.data.equipment.equipped[20].weapon, f.data.equipment.equipped[20].offhand = nil, nil
    f.data.equipment.equipped[3].legacyExtraSlot = nil
    f.data.equipment.inventory["6"] = copy(before.equipment.inventory["6"])
    f.data.heroes.teams = oldTeams

    -- 有效候选只合并/排序一次；被拒绝或缺失的候选仍保留当前属性行。
    f.reset()
    local valid = f.preview.build(1, 80, 6, "accessory", f.data)
    check(valid.preview ~= nil and valid.error == nil and #valid.rows > 0, "valid candidate reaches full preview")
    check(f.metrics.rowSorts == 1, "valid preview merges/sorts rows once")
    check(f.metrics.inventory == 0 and f.metrics.unused == 0, "valid preview never scans unused inventory")
    local missing = f.preview.build(1, 80, 999999, "accessory", f.data)
    check(missing.preview == nil and missing.error ~= nil and #missing.rows > 0, "missing candidate keeps current rows")
    local wrong = f.preview.build(1, 80, 6, "weapon", f.data)
    check(wrong.preview == nil and wrong.error ~= nil and #wrong.rows > 0, "rejected slot keeps current rows")
    local bonusOptions = copy(f.data); bonusOptions.includeEquipmentBonuses = true
    local bonus = f.preview.build(1, 80, 6, "accessory", bonusOptions)
    check(bonus.equipmentBonuses ~= nil and bonus.equipmentBonuses.preview ~= nil,
        "equipment-only source still builds current/candidate/bare baselines")
    local bonusBefore = copy(bonusOptions)
    bonus.equipmentBonuses.rows[1] = { value = "poison" }
    check(equal(bonusBefore, bonusOptions), "bare projection never mutates caller equipment/slots")

    -- 同帧原地patch仍逐内容验证；不通过帧号或引用相等跳过。
    local frozen = f.snapshot.freezeDependencies(f.data, 6, 20)
    local function matches()
        return f.snapshot.matchesDependencies(frozen, f.data.heroes, f.data.equipment,
            f.data.artifacts, f.data.talents, 20)
    end
    check(matches(), "initial frozen source matches")
    local patches = {
        function() f.data.heroes.roster[20].level = 81 end,
        function() f.data.heroes.roster[2].extraTalent.stacks = "2" end,
        function() f.data.equipment.inventory["3"].baseStats[1][2] = 123 end,
        function() f.data.equipment.inventory["6"].affixes[1].value = 123 end,
        function() f.data.equipment.equipped[2].helmet = 2 end,
        function() f.data.artifacts.bag[1] = { id = 1, level = 10 } end,
        function() f.data.talents.litNodes[1] = 1 end,
    }
    for index, patch in ipairs(patches) do
        frozen = f.snapshot.freezeDependencies(f.data, 6, 20)
        patch()
        check(not matches(), "same-ref same-frame patch rejected case=" .. index)
    end
    f.data.artifacts = { bag = {} }
    f.data.talents = { litNodes = {} }
    -- 独立实战注入oracle验证真实属性保留神器。
    -- 使用真实装配schema和已知实战效果，防止错误神器夹具静默通过。
    f.data.artifacts = { bag = { { id = "slow", artifactId = 13, value = 60 } },
        equippedByTeam = { [1] = { [1] = { "slow" } } } }
    local isolated = copy(f.data)
    local hd = isolated.heroes.roster[1]
    local unit = f.HC.createHero(1, 80, hd.advBranch, hd.awakening, hd.extraTalent,
        { litNodes = isolated.talents.litNodes, silent = true })
    f.env.require("systems.EquipmentPower").applyEquipment(unit.attrs, isolated.equipment, 1)
    f.env.require("systems.EquipmentSetRuntime").applyStaticBonuses(unit.attrs)
    f.env.require("systems.ArtifactBridge").applyToUnit(unit.attrs, 1, isolated.artifacts, 1)
    local artifactActual = f.collect(1, true)
    check(equal(artifactActual.attrs.final, unit.attrs.final)
        and artifactActual.attrs.artifactExtraDamageMult == 1.6,
        "real collector equals independent equipment/static/artifact injection oracle")
    local power = f.env.require("systems.EquipmentPower")
    local scored = power.buildWornContext(1, f.data).currentPower
    local noArtifact = copy(f.data); noArtifact.artifacts = {}
    check(scored == power.buildWornContext(1, noArtifact).currentPower,
        "scoring excludes artifacts while true attributes retain them")
    check(f.metrics.io == 0, "all paths reject player File/FS")

    for _, size in ipairs({ 500, 5000 }) do
        local b = fixture(size)
        local compactMetrics = b.measure("projected-collector", function() b.collect(20, true) end, 15)
        local fullMetrics = b.measure("full-copy-oracle", function()
            b.full.collectAttributes(20, b.HC.get(20), 80, b.data)
        end, 15)
        check(compactMetrics.inventory == 0 and compactMetrics.unused == 0,
            "projected work independent of unused inventory size=" .. size)
        check(fullMetrics.inventory >= 15 and fullMetrics.unused >= (size - 6) * 15,
            "full-copy negative control really visits unused items size=" .. size)
        b.measure("candidate-bonuses", function()
            local options = { heroes = b.data.heroes, equipment = b.data.equipment,
                artifacts = b.data.artifacts, talents = b.data.talents, includeEquipmentBonuses = true }
            b.preview.build(20, 80, 6, "accessory", options)
        end, 10)
    end
end

function Start()
    local ok, err = pcall(run)
    if not ok then check(false, "harness error: " .. tostring(err)) end
    print(string.format("%s SUMMARY assertions=%d failures=%d %s", TAG, assertions, failures,
        failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
