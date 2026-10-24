-- 转职预估沿用真实EP；私有Store与源码图，不运行main、不读写真玩家档。
local TAG = "[class_change_power_performance_test]"
local checks, failures = 0, 0
local function check(ok, label)
    checks = checks + 1
    if not ok then failures = failures + 1; print(TAG .. " FAIL " .. label) end
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for key, child in pairs(value) do out[key] = copy(child) end
    return out
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function source(name)
    local path = name:gsub("%.", "/") .. ".lua"
    local file = assert(cache:GetFile(path), path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function fixture()
    local data, loaded, counts = {}, {}, { worn = 0, full = 0, evaluate = 0, io = 0 }
    local env = setmetatable({}, { __index = _G }); env._G = env
    local function denied() counts.io = counts.io + 1; error("player IO forbidden") end
    env.File, env.io, env.dofile, env.loadfile = denied, false, denied, denied
    env.fileSystem = setmetatable({}, { __index = function() return denied end })
    loaded["core.PlayerStore"] = { Get = function(key) return data[key] end,
        GetRevision = function() return 1 end }
    env.require = function(name)
        if loaded[name] then return loaded[name] end
        local value = assert(load(source(name), "@class-power-private/" .. name, "t", env))()
        loaded[name] = value
        return value
    end
    local EP = env.require("systems.EquipmentPower")
    local full, worn, evaluate = EP.buildContext, EP.buildWornContext, EP.evaluateAdvancement
    EP.buildContext = function(...)
        counts.full = counts.full + 1
        return full(...)
    end
    EP.buildWornContext = function(...)
        counts.worn = counts.worn + 1
        return worn(...)
    end
    EP.evaluateAdvancement = function(...)
        counts.evaluate = counts.evaluate + 1
        return evaluate(...)
    end
    local reader = env.require("ui.church.ClassChangePower")
    return { data = data, EP = EP, reader = reader, counts = counts,
        AVC = env.require("config.AdvancementConfig"), HC = env.require("config.HeroConfig") }
end
local function setup(f, count)
    local data = f.data
    data.heroes = { roster = {}, teams = { { slots = { 1, 3, 4, 5 } },
        { slots = { 9, 20, 12, 23 } }, { slots = { 15, 10, 18, 24 } } } }
    data.equipment = { inventory = {}, equipped = {} }
    data.artifacts = { bag = { { id = "counter", artifactId = 5, quality = 6, value = 80 } },
        equippedByTeam = { { { "counter" } } } }
    data.talents = { litNodes = {} }
    for id = 1, 24 do
        data.heroes.roster[tostring(id)] = { level = 80, awakening = {}, extraTalent = {} }
        data.equipment.equipped[tostring(id)] = { accessory = id }
    end
    for seq = 1, count do
        data.equipment.inventory[tostring(seq)] = { seq = seq, templateId = "C1", level = 50,
            quality = 2, baseStats = { { "maxHp", 150 }, { "physAtk", seq + 12 } },
            affixes = { { affixId = 18, value = 2, ascBonus = 0.5 } },
            opaque = { values = { 3, 4, 5 }, label = "unchanged" } }
    end
    f.reader.clear()
end
local function branch(f, id)
    return f.AVC.FIRST_BRANCHES[f.HC.get(id).classId][1]
end
local function oracle(f, id, branchId)
    return f.EP.evaluateAdvancement(f.EP.buildContext(id, f.data), branchId)
end

function Start()
    local ok, err = pcall(function()
        local f = fixture(); setup(f, 500)
        local before = copy(f.data)
        for _, id in ipairs({ 1, 3, 4, 5, 9, 20, 12, 23, 15, 10, 18, 24 }) do
            local bid = branch(f, id)
            local expected = oracle(f, id, bid)
            local actual = f.reader.get(id, bid)
            check(equal(actual, expected), "full-inventory oracle hero=" .. id)
            local count = f.counts.worn
            for _ = 1, 5 do check(equal(f.reader.get(id, bid), expected), "warm result hero=" .. id) end
            check(f.counts.worn == count, "warm exact validation never rebuilds hero=" .. id)
            actual.gain = -999999
            check(equal(f.reader.get(id, bid), expected), "returned result cannot poison cache hero=" .. id)
        end
        check(equal(f.data, before), "all score and oracle calls leave source unchanged")
        local bid = branch(f, 1)
        local function patch(label, change, shouldBuild)
            f.reader.get(1, bid)
            local count = f.counts.worn
            change()
            local actual = f.reader.get(1, bid)
            local expected = oracle(f, 1, bid)
            check(equal(actual, expected), label .. " same-frame full oracle")
            check(f.counts.worn == count + (shouldBuild and 1 or 0), label .. " exact rebuild contract")
        end
        patch("target level", function() f.data.heroes.roster["1"].level = 90 end, true)
        patch("target extra", function() f.data.heroes.roster["1"].extraTalent.issuedCards = 7 end, true)
        patch("teammate level", function() f.data.heroes.roster["3"].level = 90 end, true)
        patch("other team level", function() f.data.heroes.roster["9"].level = 90 end, false)
        patch("worn deep affix", function() f.data.equipment.inventory["1"].affixes[1].value = 80 end, true)
        patch("worn opaque deep", function() f.data.equipment.inventory["1"].opaque.values[1] = 80 end, true)
        patch("unworn deep", function() f.data.equipment.inventory["500"].opaque.values[1] = 80 end, false)
        patch("same content replacement", function() f.data.equipment = copy(f.data.equipment) end, false)
        patch("artifact value", function() f.data.artifacts.bag[1].value = 81 end, true)
        patch("talent", function() f.data.talents.litNodes = { 113 } end, true)
        patch("formation", function() f.data.heroes.teams[1].slots[2] = 9 end, true)
        patch("worn missing", function() f.data.equipment.inventory["1"] = nil end, true)
        patch("missing item added", function()
            f.data.equipment.inventory["1"] = copy(f.data.equipment.inventory["2"])
        end, true)
        local first = branch(f, 1)
        f.data.heroes.roster["1"].advBranch = { first = first }
        for _, second in ipairs(f.AVC.SECOND_BRANCHES[first]) do
            check(equal(f.reader.get(1, second), oracle(f, 1, second)), "second/fusion parent branch=" .. second)
        end
        local noArtifacts = copy(f.data); noArtifacts.artifacts = {}
        check(equal(f.reader.get(1, bid), f.EP.evaluateAdvancement(f.EP.buildContext(1, noArtifacts), bid)),
            "artifact-independent advancement scoring")
        check(f.reader.get(nil, bid) == nil and f.reader.get(999999, bid) == nil, "missing hero is nil")
        check(f.reader.get(1, 999999) == nil, "unknown branch is nil")
        f.reader.clear()
        local count = f.counts.worn
        f.reader.get(1, bid)
        check(f.counts.worn == count + 1, "explicit lifecycle clear forces rebuild")
        for _, inventorySize in ipairs({ 500, 5000 }) do
            setup(f, inventorySize); bid = branch(f, 1)
            local rounds, oldTime, newTime = 8, 0, 0
            local start = os.clock()
            for _ = 1, rounds do oracle(f, 1, bid) end
            oldTime = (os.clock() - start) * 1000 / rounds
            start = os.clock()
            for _ = 1, rounds do f.reader.clear(); f.reader.get(1, bid) end
            newTime = (os.clock() - start) * 1000 / rounds
            local ctx = f.EP.buildWornContext(1, f.data)
            local items = 0; for _ in pairs(ctx.equipmentData.inventory) do items = items + 1 end
            check(items == 4, "read-only world contains only four team worn items inventory=" .. inventorySize)
            check(equal(f.reader.get(1, bid), oracle(f, 1, bid)), "benchmark exact oracle " .. inventorySize)
            print(string.format("%s PERF inventory=%d worn=%d baselineColdMs=%.3f compactColdMs=%.3f",
                TAG, inventorySize, items, oldTime, newTime))
        end
        -- 空Store/未拥有的已配置英雄仍沿原getContext的Lv1默认估值，不误当未知ID。
        do
            local boundary = fixture()
            local branchId = branch(boundary, 1)
            local expected = boundary.EP.evaluateAdvancement(boundary.EP.getContext(1), branchId)
            check(expected ~= nil and equal(boundary.reader.get(1, branchId), expected),
                "empty Store configured hero preserves getContext default")
            boundary.data.heroes = { roster = {} }
            boundary.EP.invalidate()
            expected = boundary.EP.evaluateAdvancement(boundary.EP.getContext(1), branchId)
            check(expected ~= nil and equal(boundary.reader.get(1, branchId), expected),
                "missing roster entry preserves getContext default")
            check(boundary.counts.io == 0, "empty Store boundary zero player IO")
        end
        -- 真实六件司仪袍队友光环：拆副手后由六件降到五件，暖缓存必须重新估值。
        do
            local boundary = fixture(); setup(boundary, 24)
            boundary.data.heroes.teams[1].slots[2] = 9
            boundary.data.equipment.inventory["1"].baseStats = { { "energyShield", 100 } }
            local slots = {}
            boundary.data.equipment.equipped["9"] = slots
            for index, row in ipairs({ { "weapon", "W67" }, { "armor", "A55" },
                { "helmet", "H55" }, { "shoes", "S55" },
                { "accessory", "C7" }, { "offhand", "O25" } }) do
                local seq = 100 + index
                slots[row[1]] = seq
                boundary.data.equipment.inventory[tostring(seq)] = {
                    seq = seq, templateId = row[2], level = 80, quality = 4,
                }
            end
            local branchId = branch(boundary, 1)
            local context = boundary.EP.buildContext(1, boundary.data)
            check(context.hero.attrs.modifiers.set6_last_rite ~= nil,
                "teammate actual six-piece aura active on target")
            local withAura = oracle(boundary, 1, branchId)
            check(equal(boundary.reader.get(1, branchId), withAura), "six-piece aura full oracle")
            local builds = boundary.counts.worn
            slots.offhand = nil
            local withoutAura = oracle(boundary, 1, branchId)
            context = boundary.EP.buildContext(1, boundary.data)
            check(context.hero.attrs.modifiers.set6_last_rite == nil,
                "teammate piece removal disables aura")
            check(withAura.currentPower > withoutAura.currentPower,
                "aura removal changes target power rather than vacuous fixture")
            check(equal(boundary.reader.get(1, branchId), withoutAura), "aura removal full oracle")
            check(boundary.counts.worn == builds + 1, "aura removal invalidates warm cache")
            check(boundary.counts.io == 0, "six-piece aura boundary zero player IO")
        end
        -- talents缺失时EP显式关闭HC默认星图；默认值变化不污染暖/冷结果。
        do
            local boundary = fixture(); setup(boundary, 24)
            boundary.data.talents = nil
            local branchId = branch(boundary, 1)
            local expected = boundary.EP.evaluateAdvancement(boundary.EP.getContext(1), branchId)
            check(equal(boundary.reader.get(1, branchId), expected), "missing talents getContext oracle")
            local builds = boundary.counts.worn
            boundary.HC.setDefaultLitNodes({ 125, 126, 128 })
            check(equal(boundary.reader.get(1, branchId), expected)
                and boundary.counts.worn == builds, "HC default nodes do not invalidate or change warm result")
            boundary.reader.clear(); boundary.EP.invalidate()
            check(equal(boundary.reader.get(1, branchId), expected)
                and equal(boundary.EP.evaluateAdvancement(boundary.EP.getContext(1), branchId), expected),
                "HC default nodes do not leak into cold missing-talents result")
            boundary.HC.setDefaultLitNodes(nil)
            check(boundary.counts.io == 0, "missing talents boundary zero player IO")
        end
        check(f.counts.io == 0, "zero player IO")
    end)
    if not ok then check(false, "exception " .. tostring(err)) end
    print(string.format("%s %s assertions=%d failures=%d", TAG,
        failures == 0 and "ALL PASS" or "FAIL", checks, failures))
    if engine then engine:Exit() end
    assert(failures == 0, "class change power regression")
end
