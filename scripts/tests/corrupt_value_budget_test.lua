-- 腐化跨单位预算专项。真实服务/装备模块运行于私有白名单环境；PDM/任务仅内存边界。
-- 不加载 main、不读取玩家档、不联网、不 build。可由独立 Runtime 直接加载本测试。
-- RESULT/failure_count 是业务判定，进程 exit=0 本身不代表断言通过。
local PREFIX = "[corrupt_value_budget] "
local checks, failures, cases = 0, {}, 0
local function check(ok, label)
    checks = checks + 1
    if not ok then failures[#failures + 1] = label; print(PREFIX .. "[FAIL] " .. label) end
end
local function near(a, b)
    return type(a) == "number" and type(b) == "number" and a == a and b == b
        and a > -math.huge and a < math.huge
        and math.abs(a - b) <= math.max(1, math.abs(b)) * 1e-10
end
local function eq(a, b, label)
    check(near(a, b), label .. " actual=" .. tostring(a) .. " expected=" .. tostring(b))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return type(a) == "number" and near(a, b) or a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local sources = {}
local function source(path)
    if sources[path] then return sources[path] end
    local file = assert(cache:GetFile(path), "缺少隔离fixture源码 " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local text = table.concat(lines, "\n")
    sources[path] = text
    return text
end
local ALLOWED = {
    ["systems.AttributeDef"] = true, ["systems.EquipmentSystem"] = true,
    ["systems.EquipmentSecondaryStats"] = true, ["config.EquipmentConfig"] = true,
    ["systems.EquipmentStatGrowth"] = true,
    ["config.AffixConfig"] = true, ["config.BlacksmithConfig"] = true,
    ["config.ExpTable"] = true, ["config.StageConfig"] = true,
    ["rules.blacksmith.BlacksmithService"] = true, ["shared.SuccessNotificationContext"] = true,
}
for _, difficulty in ipairs({ "Normal", "Hard", "Nightmare", "Hell", "Purgatory", "Torment",
    "Torment2", "Torment3", "Torment4", "Torment5", "Annihilation", "Annihilation2",
    "Annihilation3", "Annihilation4", "Annihilation5" }) do
    ALLOWED["config.StageConfig_" .. difficulty] = true
end
local function fixture()
    local loaded, modules = {}, {}
    local rng = { state = 1, calls = 0 }
    local privateMath = copy(math)
    privateMath.randomseed = function(seed) rng.state, rng.calls = seed, 0 end
    privateMath.random = function(lo, hi)
        rng.state = (rng.state * 48271) % 2147483647
        rng.calls = rng.calls + 1
        local value = rng.state / 2147483647
        if lo == nil then return value end
        if hi == nil then hi, lo = lo, 1 end
        return lo + math.floor(value * (hi - lo + 1))
    end
    local notifications = { dirty = {}, flushes = 0, progress = 0 }
    loaded["rules.character.PlayerDataManager"] = {
        GetModule = function(uid, name) assert(uid == 1); return modules[name] end,
        MarkDirty = function(uid, name)
            assert(uid == 1)
            notifications.dirty[name] = (notifications.dirty[name] or 0) + 1
        end,
        FlushImmediate = function(uid) assert(uid == 1); notifications.flushes = notifications.flushes + 1 end,
    }
    loaded["rules.task.TaskService"] = {
        UpdateProgress = function(uid, task, amount)
            assert(uid == 1 and (task == "refine" or task == "enhance") and amount == 1)
            notifications.progress = notifications.progress + 1
        end,
    }
    local env = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, next = next,
        tonumber = tonumber, tostring = tostring, type = type, select = select,
        pcall = pcall, xpcall = xpcall, setmetatable = setmetatable, getmetatable = getmetatable,
        math = privateMath, table = table, string = string, print = function() end,
    }
    env._G = env
    local function import(name)
        if loaded[name] then return loaded[name] end
        assert(ALLOWED[name], "禁止加载非白名单模块 " .. tostring(name))
        local path = name:gsub("%.", "/") .. ".lua"
        local compile = load --[[@as fun(text: string, name: string, mode: string, env: table): function?, string?]]
        local chunk, why = compile(source(path), "@corrupt-private/" .. path, "t", env)
        if not chunk then error(tostring(why)) end
        local value = chunk()
        loaded[name] = value
        return value
    end
    env.require = import
    modules.equipment = { inventory = {}, equipped = {} }
    modules.currency = { corruptStone = 10000, sacredStone = 10000, enhanceStone = 10000,
        essence = 10 ^ 12, gold = 10 ^ 12, weaponScroll = 10 ^ 6 }
    modules.player = { level = 200 }
    modules.battle = { maxStageId = 0 }
    return {
        ES = import("systems.EquipmentSystem"), BS = import("rules.blacksmith.BlacksmithService"),
        AD = import("systems.AttributeDef"), AC = import("config.AffixConfig"),
        EC = import("config.EquipmentConfig"), math = privateMath,
        rng = rng, modules = modules, notifications = notifications,
    }
end
-- 独立oracle：直接展开正式META/全部派生项，不调用生产unitValue/转换函数。
local function unit(f, key)
    local derivatives = f.AD.DERIVATIVES[key]
    if derivatives then
        local total = 0
        for _, row in ipairs(derivatives) do total = total + row.perPoint * unit(f, row.attr) end
        return total
    end
    local meta = assert(f.AD.META[key], "missing oracle metadata: " .. tostring(key))
    return meta.dataType == f.AD.TYPE_PCT and meta.valueModel / 100 or meta.valueModel
end
local function affix(f, key, value, bonus)
    local tpl = assert(f.AC.BY_KEY[key])
    return { affixId = tpl.id, key = key, name = tpl.name, quality = 3, value = value, ascBonus = bonus }
end
local function put(f, affixes, template, level, quality, mult)
    local equip = { templateId = template or "W1", level = level or 10, quality = quality or 4,
        affixes = affixes, affixMult = mult or 1.7, seq = 1 }
    f.ES.hydrate(equip)
    f.modules.equipment.inventory["1"] = equip
    return equip
end
local function expected(f, original, equip)
    local tpl = assert(f.AC.BY_KEY[f.AC.NORMAL_TO_CORRUPT_KEY[original.key]])
    local item = assert(f.EC.ITEMS[equip.templateId])
    local double = (equip.grip or item.grip) == "twohand" and 2 or 1
    local templateFloor = tpl.baseValue * (1 + (equip.level - 1) * f.EC.LEVEL_SCALE) * double
    local equivalent = original.value * (unit(f, original.key) / unit(f, tpl.key))
    return math.max(equivalent, templateFloor) * 1.8, tpl.key, templateFloor * 1.8
end
local function action(f, equip, resource)
    local ok, err, result = f.BS.RefineEquip(1, equip.seq, resource)
    check(ok and result and result.autoReplaced, resource .. " real service accepts: " .. tostring(err))
    assert(ok and result, "service result required")
    return result
end
local function persisted(f, equip)
    local before, rngBefore = copy(equip), f.rng.calls
    local lean = f.ES.dehydrate(equip)
    check(same(equip, before), "dehydrate does not mutate equipment or revert snapshot")
    local restored = cjson.decode(cjson.encode(lean))
    f.ES.hydrate(restored)
    check(f.rng.calls == rngBefore, "dehydrate/JSON/hydrate consumes no RNG")
    restored.seq = equip.seq
    f.modules.equipment.inventory[tostring(equip.seq)] = restored
    return restored
end
local function oneConversion(f, key, value, template, level, quality, mult, bonus)
    cases = cases + 1
    local original = affix(f, key, value, bonus)
    local originalCopy = copy(original)
    local equip = put(f, { original }, template, level, quality, mult)
    local baseBefore, rollBefore = copy(equip.baseStats), copy(equip.secondaryRoll)
    local wanted, target, floor = expected(f, original, equip)
    local beforeCurrency = copy(f.modules.currency)
    local countBefore = f.rng.calls
    local result = action(f, equip, "corruptStone")
    local converted = equip.affixes[1]
    local tag = key .. "/" .. template .. "/lv" .. level .. "/q" .. quality .. "/v" .. value
    eq(converted.value, wanted, tag .. " target-unit budget/floor then 1.8")
    check(converted.key == target and converted.quality == 0 and f.AC.isCorruptAffix(converted),
        tag .. " correct corrupt identity and quality")
    check(converted.ascBonus == nil, tag .. " corrupt does not consume ordinary fixed investment")
    eq(f.ES.getAffixMult(equip), mult, tag .. " equipment slot multiplier remains unchanged")
    eq(f.ES.effectiveAffixValue(equip, converted), wanted, tag .. " converted value does not multiply again")
    local entries = f.ES.computeModifierEntries(equip, 0)
    local convertedEntry = entries[#equip.baseStats + 1]
    check(convertedEntry.key == target, tag .. " actual modifier pipeline uses target key")
    eq(convertedEntry.flat, wanted, tag .. " actual modifier pipeline uses normalized value once")
    check(wanted >= floor and converted.value < math.huge, tag .. " target template lower bound and finite")
    check(f.rng.calls == countBefore + 2, tag .. " original validation and selection RNG calls preserved")
    local currencyExpected = copy(beforeCurrency)
    currencyExpected.corruptStone = currencyExpected.corruptStone - 1
    check(same(f.modules.currency, currencyExpected), tag .. " one stone/no essence")
    check(equip.corruptCount == 1 and near(equip.corruptBaseMult, 0.9), tag .. " one curse layer")
    local patch = equip.corruptRevert.patches[1]
    check(patch[1] == "c" and patch[2] == 1 and patch.layer == 1 and patch.valueVersion == 2
        and same(patch[3], originalCopy),
        tag .. " original value/key/quality/ascBonus recoverable in c snapshot")
    check(same(original, originalCopy), tag .. " caller's original affix object is not modified")
    eq(result.corruptEffectDetail.affixChanges[1].afterValue, wanted, tag .. " response uses committed value")
    check(same(equip.secondaryRoll, rollBefore), tag .. " no secondary reroll")
    equip = persisted(f, equip)
    eq(equip.affixes[1].value, wanted, tag .. " save roundtrip preserves converted raw value")
    check(same(equip.corruptRevert.patches[1][3], originalCopy), tag .. " snapshot survives mixed-key JSON patch")
    check(equip.corruptRevert.patches[1].valueVersion == 2, tag .. " new conversion version survives JSON/hydrate")
    local cleanseRng = f.rng.calls
    action(f, equip, "sacredStone")
    check(same(equip.affixes[1], originalCopy), tag .. " cleanse restores complete original ordinary affix")
    check(equip.corruptCount == nil and equip.corruptRevert == nil and equip.corruptBaseMult == nil,
        tag .. " cleanse clears only curse state")
    check(same(equip.baseStats, baseBefore), tag .. " cleanse restores original base stats")
    -- 仅普通词条恢复后的生效值补偿；本测试高等级夹具固定Lv120。
    local growth120 = { maxHp = 2, hpRegen = 2, atkHeal = 2,
        physAtk = 1.76, magAtk = 1.76, energyShield = 2.3 }
    local growth = level == 120 and (growth120[key] or 1) or 1
    eq(f.ES.effectiveAffixValue(equip, equip.affixes[1]), (value * mult + (bonus or 0)) * growth,
        tag .. " restored bonus outside slot multiplier, then flat growth once")
    check(f.rng.calls == cleanseRng, tag .. " cleanse is deterministic")
    return wanted
end
local function testBudgetMatrix(f)
    local weights = { str = 1.5, agi = 1.495, int = 1.49, vit = 1.49, luk = 1.5, spi = 1.5 }
    for key, weight in pairs(weights) do eq(unit(f, key), weight, key .. " full six-stat derivatives") end
    eq(unit(f, "maxHp"), 0.03, "HP one-point value")
    eq(unit(f, "energyShield"), 0.1, "shield one-point value")
    eq(unit(f, "finalHpBonus"), 0.6, "percentage uses VM/100")
    local keys = {}
    for _, tpl in ipairs(f.AC.AFFIXES) do
        if f.AC.NORMAL_TO_CORRUPT_KEY[tpl.key] then keys[#keys + 1] = tpl.key end
    end
    check(#keys == 19, "all 19 official ordinary-to-corrupt mappings covered")
    for _, key in ipairs(keys) do
        for _, template in ipairs({ "W1", "W24" }) do
            for _, value in ipairs({ 0.001, 1000.125, 10 ^ 7 }) do
                for _, q in ipairs({ 1, 6 }) do
                    oneConversion(f, key, value, template, 120, q, 2.3, 0.375)
                end
            end
        end
    end
    eq(oneConversion(f, "maxHp", 1000, "W1", 1, 4, 1.7, 500), 90,
        "HP1000 becomes finalHP90 percent, not raw-number1800 percent")
    eq(oneConversion(f, "physAtk", 1000, "W1", 1, 4, 1.7, 500), 1500,
        "attack uses 0.5/0.6 ratio")
    eq(oneConversion(f, "energyShield", 1000, "W1", 1, 4, 1.7, 500), 300,
        "shield uses 0.1/0.6 ratio")
    eq(oneConversion(f, "dmgBonus", 1000, "W1", 1, 4, 1.7, 500), 1200,
        "same pct units still convert 40/60 static budget")
    local single = oneConversion(f, "maxHp", 0.001, "W1", 50, 4, 1.7, 0.375)
    local double = oneConversion(f, "maxHp", 0.002, "W24", 50, 4, 1.7, 0.375)
    eq(double, single * 2, "twohand doubles target-template floor once")
    local a = oneConversion(f, "maxHp", 1000, "W1", 1, 1, 1.1, 0.125)
    local b = oneConversion(f, "maxHp", 2000, "W24", 1, 6, 4.5, 700)
    eq(b, a * 2, "already doubled source budget does not receive second grip factor")
    local plain = oneConversion(f, "str", 1000, "W1", 1, 1, 1, nil)
    local invested = oneConversion(f, "str", 1000, "W1", 1, 6, 9, 10 ^ 6)
    eq(plain, invested, "quality/mult/ascBonus not baked into converted raw budget")
end
local function testRNGAndLayers(f)
    local equip = put(f, { affix(f, "maxHp", 1000, 0.125), affix(f, "physAtk", 70, 0.375),
        affix(f, "energyShield", 130, 0.625) }, "W24", 120, 5, 2.3)
    local initial = copy(equip.affixes)
    local originalBase = copy(equip.baseStats)
    local seed = 9845
    local oracleState = seed
    local function draw(count)
        oracleState = (oracleState * 48271) % 2147483647
        return 1 + math.floor(oracleState / 2147483647 * count)
    end
    f.math.randomseed(seed)
    local snapshots = {}
    for layer = 1, 3 do
        local indices = {}
        for i, row in ipairs(equip.affixes) do
            if not f.AC.isCorruptAffix(row) then indices[#indices + 1] = i end
        end
        draw(#indices) -- existing validation pick must still consume its first draw
        local chosen = indices[draw(#indices)]
        local before = copy(equip.affixes)
        local wanted = expected(f, before[chosen], equip)
        action(f, equip, "corruptStone")
        check(f.rng.calls == layer * 2 and f.rng.state == oracleState, "layer" .. layer .. " exact RNG state/order")
        check(equip.corruptRevert.patches[layer][2] == chosen, "layer" .. layer .. " second draw chooses correct slot")
        eq(equip.affixes[chosen].value, wanted, "layer" .. layer .. " chosen slot normalized")
        for i, row in ipairs(before) do
            if i ~= chosen then check(same(row, equip.affixes[i]), "layer" .. layer .. " untouched slot" .. i) end
        end
        equip = persisted(f, equip)
        -- convertedFrom 是当前旧存储协议不持久化的展示字段；以读档后的完整槽表为下一层基线。
        snapshots[layer] = copy(equip.affixes)
    end
    local fullBefore, currencyBefore, rngBefore = copy(equip), copy(f.modules.currency), f.rng.calls
    check(not f.BS.RefineEquip(1, equip.seq, "corruptStone"), "fourth layer rejected")
    check(same(equip, fullBefore) and same(f.modules.currency, currencyBefore) and f.rng.calls == rngBefore,
        "fourth layer rejection does not charge or roll")
    for layer = 3, 1, -1 do
        action(f, equip, "sacredStone")
        check(same(equip.affixes, layer == 1 and initial or snapshots[layer - 1]),
            "cleanse layer" .. layer .. " restores only most recent conversion")
        eq(f.ES.getAffixMult(equip), 2.3, "layer cleanse preserves slot multiplier")
        for _, patch in ipairs(equip.corruptRevert and equip.corruptRevert.patches or {}) do
            check(patch.valueVersion == 2 and patch.layer < layer, "cleanse retains lower-layer version/source only")
        end
        if layer > 1 then equip = persisted(f, equip) end
    end
    check(same(equip.baseStats, originalBase), "three-layer cleanse restores base stats")
    check(equip.corruptCount == nil and equip.corruptRevert == nil, "three-layer cleanse clears revert")
    check(f.rng.calls == rngBefore, "all cleanses/save cycles preserve RNG state")

    -- 稀疏候选/已有魔化：确认selection不是总槽数，也不重算已有魔化高值。
    equip = put(f, { affix(f, "critRate", 7), affix(f, "maxHp", 1000, 0.375),
        { affixId = 1002, key = "finalMagAtkBonus", name = "最终魔攻", quality = 0, value = 99999.125 } })
    local untouched = { copy(equip.affixes[1]), copy(equip.affixes[3]) }
    action(f, equip, "corruptStone")
    check(equip.affixes[2].key == "finalHpBonus" and same(equip.affixes[1], untouched[1])
        and same(equip.affixes[3], untouched[2]), "only convertible slot selected; existing corrupt value untouched")
    local beforeNoCandidate, beforeCurrency = copy(equip), copy(f.modules.currency)
    local callsBefore = f.rng.calls
    check(not f.BS.RefineEquip(1, equip.seq, "corruptStone"), "no remaining convertible affix rejected")
    check(same(equip, beforeNoCandidate) and same(f.modules.currency, beforeCurrency) and f.rng.calls == callsBefore,
        "no candidate rejection does not change equipment/currency/RNG")
end
local function testLegacyPreserved(f)
    local equip = put(f, { affix(f, "maxHp", 1000, 0.375) }, "W1", 20, 4, 2.3)
    action(f, equip, "corruptStone")
    -- 模拟旧实现产生且quality=0的错误高值：本修复只管今后的转换，不做任何自动迁移。
    equip.affixes[1].value = 1800000.125
    equip.corruptRevert.patches[1].valueVersion = nil
    local originalPatch = copy(equip.corruptRevert.patches[1][3])
    for i = 1, 4 do
        equip = persisted(f, equip)
        eq(equip.affixes[1].value, 1800000.125, "legacy converted value remains unchanged after save cycle" .. i)
        check(same(equip.corruptRevert.patches[1][3], originalPatch), "legacy c snapshot remains intact" .. i)
        eq(f.ES.effectiveAffixValue(equip, equip.affixes[1]), 1800000.125, "legacy effect not silently capped" .. i)
    end
    action(f, equip, "sacredStone")
    check(same(equip.affixes[1], originalPatch), "even old bad converted value can cleanse to exact c snapshot")
    -- 原预算当前可重建，但没有版本标记，不能将所有存量高值一刀切当作坏值。
    eq(expected(f, originalPatch, equip), 90, "c snapshot contains enough raw source to recompute candidate new budget")
end
function Start()
    print(PREFIX .. "start isolated whitelist / no main or player save")
    local ok, why = pcall(function()
        local f = fixture()
        testBudgetMatrix(f)
        testRNGAndLayers(f)
        testLegacyPreserved(f)
        check((f.notifications.dirty.equipment or 0) > 0 and (f.notifications.dirty.currency or 0) > 0
            and f.notifications.flushes > 0 and f.notifications.progress > 0, "real service commit boundaries exercised")
    end)
    if not ok then check(false, "exception: " .. tostring(why)) end
    print(PREFIX .. "RESULT " .. (#failures == 0 and "ALL PASS" or "FAIL")
        .. " assertions=" .. checks .. " cases=" .. cases .. " failure_count=" .. #failures)
    engine:Exit()
end
