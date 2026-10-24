-- 普通装备优势/劣势来源预算专项；复用 critical_rate_budget_test 私有白名单/RNG骨架。
-- 不加载main、不读玩家档/凭据、不联网、不改宿主require/package.loaded/math或生产模块。
-- 真实ES/Growth/UA/CF及CF依赖均执行原源码，无战斗公式替身；JSON只使用内存字符串。
-- 独立Runtime入口；由调用方统一运行，不build。验收看RESULT与failure_count，非退出码。
local PREFIX = "[equipment_type_bonus_budget] "
local checks, failures = 0, {}
local function check(ok, label)
    checks = checks + 1
    if not ok then failures[#failures + 1] = label; print(PREFIX .. "[FAIL] " .. label) end
end
local function near(a, b)
    return type(a) == "number" and type(b) == "number" and a == a and b == b
        and a > -math.huge and a < math.huge and b > -math.huge and b < math.huge
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
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function equivalent(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return type(a) == "number" and near(a, b) or a == b end
    for k, v in pairs(a) do if not equivalent(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local ALLOWED = {
    ["systems.AttributeDef"] = true, ["systems.UnitAttributes"] = true,
    ["systems.EquipmentSystem"] = true, ["systems.EquipmentStatGrowth"] = true,
    ["systems.EquipmentSecondaryStats"] = true, ["config.EquipmentConfig"] = true,
    ["config.AffixConfig"] = true, ["config.BlacksmithConfig"] = true,
    ["systems.CombatFormula"] = true, ["systems.BattleDiag"] = true,
    ["core.BattleLayout"] = true, ["systems.StatusEffectManager"] = true,
    ["systems.MapAffixSystem"] = true, ["config.MapAffixConfig"] = true,
    ["systems.ClassGateRuntime"] = true, ["config.ClassConfig"] = true,
}
local sources = {}
local function source(name)
    assert(ALLOWED[name], "禁止读取非白名单源码 " .. tostring(name))
    if sources[name] then return sources[name] end
    local path = name:gsub("%.", "/") .. ".lua"
    local file = assert(cache:GetFile(path), "缺少隔离fixture源码 " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local text = table.concat(lines, "\n")
    sources[name] = text
    return text
end
local function fixture()
    local loaded, rng = {}, { state = 1, calls = 0 }
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
    local env = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, next = next,
        tonumber = tonumber, tostring = tostring, type = type, select = select,
        pcall = pcall, xpcall = xpcall, setmetatable = setmetatable, getmetatable = getmetatable,
        math = privateMath, table = table, string = string, print = print, os = { clock = os.clock },
    }
    env._G = env
    local function import(name)
        if loaded[name] then return loaded[name] end
        assert(ALLOWED[name], "禁止加载非白名单模块 " .. tostring(name))
        local compile = load --[[@as fun(text: string, name: string, mode: string, env: table): function?, string?]]
        local chunk, why = compile(source(name), "@type-budget-private/" .. name, "t", env)
        if not chunk then error(tostring(why)) end
        local value = chunk()
        loaded[name] = value
        return value
    end
    env.require = import
    return {
        ES = import("systems.EquipmentSystem"), Growth = import("systems.EquipmentStatGrowth"),
        EC = import("config.EquipmentConfig"), AC = import("config.AffixConfig"),
        AD = import("systems.AttributeDef"), UA = import("systems.UnitAttributes"),
        CF = import("systems.CombatFormula"), Secondary = import("systems.EquipmentSecondaryStats"),
        math = privateMath, rng = rng,
    }
end
local function noRNG(f, fn, label)
    local calls, state = f.rng.calls, f.rng.state
    fn()
    check(f.rng.calls == calls and f.rng.state == state, label .. " 不消费RNG/不重置种子")
end
-- 独立常数oracle；不读取EC曲线，也不调用Growth/ES helper产生任何期望。
local KEYS = { "minDmgBonus", "maxDmgBonus" }
local BASE = { minDmgBonus = 30, maxDmgBonus = 30 }
local AFFIX = { minDmgBonus = 20, maxDmgBonus = 20 }
local CRIT_BASE = { critRate = 8, physCritRate = 10, magCritRate = 10, healCritRate = 10 }
local function curve(value, budget)
    if not budget or value <= 0 then return value end
    return budget / (1 + budget / value)
end
local function affix(key, value, bonus)
    return { affixId = key == "minDmgBonus" and 33 or 32, key = key, quality = 3,
        value = value, ascBonus = bonus }
end
local function testCurve(f)
    check(same(f.EC.TYPE_BONUS_CURVE, { base = BASE, affix = AFFIX }), "曲线恰为两key两来源30/20")
    check(type(f.Growth.scaleTypeBonus) == "function" and f.ES.scaleTypeBonus == f.Growth.scaleTypeBonus,
        "ES暴露同一个Growth公共代理")
    local forms = {
        { label = "nil", equip = nil, double = 1 }, { label = "空", equip = {}, double = 1 },
        { label = "单手", equip = { slot = "weapon", grip = "onehand" }, double = 1 },
        { label = "双手", equip = { slot = "weapon", grip = "twohand" }, double = 2 },
        { label = "副手非主武器", equip = { slot = "offhand", grip = "twohand" }, double = 1 },
        { label = "饰品非主武器", equip = { slot = "accessory", grip = "twohand" }, double = 1 },
        { label = "仅双手模板", equip = { templateId = "W24" }, double = 2 },
        { label = "仅单手模板", equip = { templateId = "W18" }, double = 1 },
        { label = "显式槽覆盖模板", equip = { templateId = "W24", slot = "offhand" }, double = 1 },
        { label = "显式握持覆盖模板", equip = { templateId = "W24", grip = "onehand" }, double = 1 },
        { label = "模板补握持", equip = { templateId = "W24", slot = "weapon" }, double = 2 },
        { label = "模板补槽", equip = { templateId = "W24", grip = "twohand" }, double = 2 },
        { label = "未知模板", equip = { templateId = "__missing" }, double = 1 },
    }
    noRNG(f, function()
        for _, form in ipairs(forms) do
            local before = copy(form.equip)
            for _, key in ipairs(KEYS) do
                for _, src in ipairs({ "base", "affix" }) do
                    local budget = (src == "base" and 30 or 20) * form.double
                    local previous = 0
                    for _, value in ipairs({ -17, -0.0, 0.001, 1, 100, 1e300 }) do
                        local label = key .. "/" .. src .. "/" .. form.label .. "/" .. value
                        local actual = f.ES.scaleTypeBonus(form.equip, key, value, src)
                        eq(actual, curve(value, budget), label)
                        eq(f.Growth.scaleTypeBonus(form.equip, key, value, src), curve(value, budget), label .. " Growth直调")
                        if value > 0 then
                            check(actual > previous and actual <= value and actual <= budget,
                                label .. " 单调且有界/极大输入有限")
                            previous = actual
                        else check(actual == value, label .. " 非正数原量") end
                    end
                    local zero = f.ES.scaleTypeBonus(form.equip, key, -0.0, src)
                    check(1 / zero == -math.huge, key .. "/" .. src .. " 负零符号保持")
                end
                eq(f.ES.scaleTypeBonus(form.equip, key, 123.25, "unknown"), 123.25, key .. " 未知来源恒等")
            end
            check(same(form.equip, before), form.label .. " helper不补写槽/握持/模板")
        end
        for key in pairs(f.AD.META) do
            if not BASE[key] then
                for _, src in ipairs({ "base", "affix" }) do
                    eq(f.ES.scaleTypeBonus({ templateId = "W24" }, key, 804.1, src), 804.1, key .. " 非type helper恒等")
                end
            end
        end
        eq(f.ES.scaleTypeBonus({}, "unknown", 804.1, "base"), 804.1, "未知key恒等")
    end, "来源/keys/握持兜底")
end
local function testEffectiveAndPreview(f)
    noRNG(f, function()
        for _, key in ipairs(KEYS) do
            for _, double in ipairs({ 1, 2 }) do
                local equip = { level = 200, slot = "weapon", grip = double == 2 and "twohand" or "onehand",
                    ascendLevel = 31, affixMult = 2.3,
                    baseStats = { { key, 100 }, { key, 50 }, { key, 25 } },
                    affixes = { affix(key, 111.125, 0.375) } }
                local before, ref = copy(equip), equip.baseStats
                for _, ascend in ipairs({ 0, 1, 2, 3, 31, 100 }) do
                    local steps = { 0, math.floor((ascend + 1) / 2), math.floor(ascend / 2) }
                    for i, raw in ipairs({ 100, 50, 25 }) do
                        local wanted = curve(raw * (1 + (i == 1 and ascend * 0.05 or steps[i] * 0.05)), 30 * double)
                        eq(f.ES.effectiveBaseStatValue(equip, i, nil, ascend), wanted, key .. " 主副目标升阶" .. ascend .. "/" .. i)
                        if i > 1 then
                            eq(f.ES.effectiveBaseStatValue(equip, i, 999, ascend), wanted, key .. " 副预览忽略主boost")
                        end
                    end
                end
                eq(f.ES.effectiveBaseStatValue(equip, 1), curve(255, 30 * double), key .. " 默认31阶主出口")
                eq(f.ES.effectiveBaseStatValue(equip, 1, 0.7, 100), curve(170, 30 * double), key .. " 显式boost优先")
                eq(f.ES.effectiveBaseStatValue(equip, 2), curve(90, 30 * double), key .. " 31阶副第一槽16次")
                eq(f.ES.effectiveBaseStatValue(equip, 3), curve(43.75, 30 * double), key .. " 31阶副第二槽15次")
                local wantedAffix = curve(111.125 * 2.3 + 0.375, 20 * double)
                eq(f.ES.effectiveAffixValue(equip, equip.affixes[1]), wantedAffix, key .. " 完整raw*mult+bonus后一次")
                local entries = f.ES.computeModifierEntries(equip, 0.7)
                check(#entries == 4 and entries[1].key == key and entries[4].key == key, key .. " modifier行序/key不改")
                for i, raw in ipairs({ 170, 90, 43.75 }) do eq(entries[i].flat, curve(raw, 30 * double), key .. " 实际modifier基础一次") end
                eq(entries[4].flat, wantedAffix, key .. " 实际modifier词条不二次soft")
                for _, value in ipairs({ -17, 0, 0.001, 100, 1e300 }) do
                    local edge = { level = 200, slot = equip.slot, grip = equip.grip, ascendLevel = 30,
                        affixMult = 2.3, baseStats = { { key, value }, { key, value } } }
                    eq(f.ES.effectiveBaseStatValue(edge, 1), curve(value * 2.5, 30 * double), key .. " 边界主升阶后soft")
                    eq(f.ES.effectiveBaseStatValue(edge, 2), curve(value * 2.5, 30 * double), key .. " 边界单副30次后soft")
                    eq(f.ES.effectiveAffixValue(edge, affix(key, value, 7)), curve(value * 2.3 + 7, 20 * double), key .. " 边界含固定bonus后soft")
                end
                -- raw为负但完整结果为正，不能在乘/加之前提前返回或分别压缩。
                eq(f.ES.effectiveAffixValue(equip, affix(key, -3, 7)), curve(0.1, 20 * double), key .. " 负raw加bonus过零")
                eq(f.ES.effectiveAffixValue(equip, affix(key, 0, 0)), 0, key .. " 完整零不凭空增长")
                check(same(equip, before) and equip.baseStats == ref, key .. " 预览/实际查询不改raw或引用")
            end
        end
        eq(f.ES.effectiveBaseStatValue({ baseStats = {} }, 1), 0, "缺基础行返回0")
        eq(f.ES.effectiveAffixValue({}, nil), 0, "缺词条返回0")
    end, "生效顺序/预览/实际modifier")
end
local function testExclusions(f)
    noRNG(f, function()
        for _, key in ipairs(KEYS) do
            for _, id in ipairs({ 1001, "1001" }) do
                local row = { affixId = id, key = key, value = 804.1, ascBonus = 999 }
                local equip = { templateId = "W24", level = 200, affixMult = 17, baseStats = {}, affixes = { row } }
                local before = copy(equip)
                eq(f.ES.effectiveAffixValue(equip, row), 804.1, key .. " 腐化身份即使key白名单也跳过type/mult/bonus")
                eq(f.ES.computeModifierEntries(equip, 99)[1].flat, 804.1, key .. " 腐化identity实际modifier原量")
                check(same(equip, before), key .. " 腐化不清写历史字段")
            end
        end
        for _, tpl in ipairs(f.AC.CORRUPT_AFFIXES) do
            eq(f.ES.effectiveAffixValue({ level = 200, affixMult = 17 },
                { affixId = tpl.id, key = tpl.key, value = 804.1, ascBonus = 999 }), 804.1, tpl.key .. " 正式腐化仍恒等")
        end
        local equip = { level = 200, slot = "weapon", grip = "twohand", ascendLevel = 30,
            affixMult = 2, baseStats = { { "physAtk", 100 }, { "critRate", 50 }, { "atkSpeed", 20 } },
            affixes = { { key = "energyShield", value = 10, ascBonus = 3 }, { key = "critRate", value = 50, ascBonus = 3 } } }
        local entries = f.ES.computeModifierEntries(equip, 1.5)
        for i, value in ipairs({ 600, curve(87.5, 16), 35, 80.5, curve(103, 8) }) do
            eq(entries[i].flat, value, "原flat/crit/非目标出口保留" .. i)
        end
    end, "腐化identity/已有flat与crit排除")
    -- 私有模板造白名单固有行，直接证明早返而非仅因正式固有key不在曲线里。
    local id = "__type_budget_intrinsic"
    f.EC.ITEMS[id] = { intrinsicStats = { { "minDmgBonus", 123 }, { "maxDmgBonus", 456 } } }
    local ok, why = pcall(function()
        local equip = { templateId = id, level = 200, ascendLevel = 100,
            baseStats = { { "physAtk", 10 }, { "atkSpeed", 5 }, { "minDmgBonus", 123 },
                { "maxDmgBonus", 456 }, { "armor", 7 } } }
        local before = copy(equip)
        noRNG(f, function()
            eq(f.ES.effectiveBaseStatValue(equip, 3, 999, 100), 123, "劣势固有早返不升阶/不soft")
            eq(f.ES.effectiveBaseStatValue(equip, 4, 999, 100), 456, "优势固有早返不升阶/不soft")
            eq(f.ES.getSecondaryAscendCount(equip, 2, 3), 2, "跨固有副第一槽两次")
            eq(f.ES.getSecondaryAscendCount(equip, 5, 3), 1, "跨固有副第二槽一次")
            local entries = f.ES.computeModifierEntries(equip, 999)
            eq(entries[3].flat, 123, "真实固有modifier仍原值")
            eq(entries[4].flat, 456, "优势固有modifier仍原值")
            check(same(equip, before), "固有查询只读")
        end, "固有早返")
    end)
    f.EC.ITEMS[id] = nil
    check(ok, "私有固有fixture清理 " .. tostring(why))
end
-- 两条真实普通词缀的历史RNG oracle。只排除其他43条，不更改生产词缀池/roll函数。
local ORDINARY_KEYS = { "str", "agi", "int", "vit", "luk", "spi", "maxHp", "armor", "energyShield",
    "dodge", "hpRegen", "atkHeal", "physBlockRate", "magBlockRate", "abnormalRes", "physAtk", "magAtk",
    "atkSpeed", "critRate", "critDmg", "physCritRate", "physCritDmg", "magCritRate", "magCritDmg",
    "physPen", "magPen", "dmgBonus", "physDmgBonus", "magDmgBonus", "comboRate", "comboDmgUp",
    "maxDmgBonus", "minDmgBonus", "hitValue", "healAmount", "healBonus", "healCritRate", "healCritDmg",
    "physAtkBonus", "magAtkBonus", "hpBonus", "dodgeBonus", "esBonus", "armorBonus", "dropLuck" }
local function oracleRNG(seed)
    local rng = { state = seed, calls = 0 }
    function rng.draw()
        rng.state = rng.state * 48271 % 2147483647
        rng.calls = rng.calls + 1
        return rng.state / 2147483647
    end
    return rng
end
local function typeAffixes(f, seed, double)
    local excluded = {}
    for _, key in ipairs(ORDINARY_KEYS) do if not BASE[key] then excluded[key] = true end end
    local rng, pool, chosen, expected = oracleRNG(seed), { { "maxDmgBonus", 8.3, 32 }, { "minDmgBonus", 10, 33 } }, {}, {}
    for i = 1, 2 do chosen[i] = table.remove(pool, math.floor(rng.draw() * #pool) + 1) end
    local tiers = { { 100, 1, 1.2 }, { 80, 1.2, 1.5 }, { 60, 1.5, 1.9 }, { 40, 1.9, 2.4 }, { 20, 2.4, 3 } }
    for i, row in ipairs(chosen) do
        local roll, accumulated, tier = rng.draw() * 300, 0, 5
        for q, spec in ipairs(tiers) do
            accumulated = accumulated + spec[1]
            if roll <= accumulated then tier = q break end
        end
        local spec = tiers[tier]
        local value = row[2] * (spec[2] + rng.draw() * (spec[3] - spec[2])) * 5.95 * 1.4 * double
        expected[i] = { key = row[1], affixId = row[3], quality = tier, value = value }
    end
    f.math.randomseed(seed)
    local actual = f.ES.rollAffixes(2, 5, 100, excluded, 1.4, double == 2 and "twohand" or "onehand")
    check(#actual == 2, "真实roll包含两个type key")
    for i, row in ipairs(expected) do
        check(actual[i].key == row.key and actual[i].affixId == row.affixId and actual[i].quality == row.quality,
            "独立历史RNG词缀key/顺序/品质")
        eq(actual[i].value, row.value, row.key .. " 生成raw未soft")
    end
    check(f.rng.calls == 6 and f.rng.calls == rng.calls and f.rng.state == rng.state, "词缀历史RNG次数/后继状态不变")
    return actual
end
local function expectedBase(row, index, count, ascend, double)
    local steps = index == 1 and ascend or math.floor((ascend + count - index + 1) / count)
    local value = row[2] * (1 + steps * 0.05)
    -- 此处真实代表只有Lv100物攻为flat；其余crit/type/线性互斥，仍独立常数。
    if row[1] == "physAtk" then value = value * 1.6 end
    local limit = BASE[row[1]] or CRIT_BASE[row[1]]
    return curve(value, limit and limit * double)
end
local function testRawRNGAndPersistence(f)
    eq(f.AD.META.minDmgBonus.valueModel, 10, "劣势静态VM不改")
    eq(f.AD.META.maxDmgBonus.valueModel, 12, "优势静态VM不改")
    eq(f.Secondary.unitValue("minDmgBonus"), 0.1, "劣势随机副单位预算仍0.1")
    eq(f.Secondary.unitValue("maxDmgBonus"), 0.12, "优势随机副单位预算仍0.12")
    local templates = {
        { id = "W24", double = 2, rows = { { "physAtk", 37.72 }, { "maxDmgBonus", 32.1 }, { "physDmgBonus", 12.9 } },
            budgets = { 3.852, 3.87 }, pool = { { "physPen", 0.5 }, { "physDmgBonus", 0.3 }, { "atkSpeed", 0.4 },
                { "critRate", 1 }, { "critDmg", 0.2 }, { "hitValue", 0.8 } } },
        { id = "C33", double = 1, rows = { { "luk", 4.28 }, { "maxDmgBonus", 21.4 } },
            budgets = { 2.568 }, pool = { { "atkSpeed", 0.4 }, { "critRate", 1 }, { "critDmg", 0.2 }, { "hitValue", 0.8 } } },
    }
    for _, tpl in ipairs(templates) do
        check(same(f.EC.ITEMS[tpl.id].stats, tpl.rows), tpl.id .. " 正式模板raw不改")
        for _, legacy in ipairs({ true, false }) do
            local seed, rng, pool, roll = 20261024, oracleRNG(20261024), copy(tpl.pool), { version = 1, stats = {} }
            if not legacy then
                for i, budget in ipairs(tpl.budgets) do
                    local chosen = table.remove(pool, math.floor(rng.draw() * #pool) + 1)
                    roll.stats[i] = { chosen[1], budget / chosen[2] }
                end
            end
            f.math.randomseed(seed)
            local equip = f.ES.generate(tpl.id, 100, 1, { legacySecondary = legacy })
            check(f.rng.calls == rng.calls and f.rng.state == rng.state, tpl.id .. " 新旧生成历史RNG不变")
            check(legacy and equip.secondaryRoll == nil or not legacy and equivalent(equip.secondaryRoll, roll), tpl.id .. " 新旧副预算/版本/顺序")
            for i, original in ipairs(tpl.rows) do
                local row = i > 1 and not legacy and roll.stats[i - 1] or original
                check(equip.baseStats[i][1] == row[1], tpl.id .. " 生成基础key/顺序")
                eq(equip.baseStats[i][2], row[2] * 5.95, tpl.id .. " 生成raw仅旧等级品质")
            end
            equip.affixes, equip.ascendLevel, equip.affixMult = typeAffixes(f, seed + tpl.double, tpl.double), 31, 2.3
            equip.affixes[1].ascBonus, equip.affixes[2].ascBonus = 0.375, 25000.375
            local raw, savedRoll, savedAffixes = copy(equip.baseStats), copy(equip.secondaryRoll), copy(equip.affixes)
            local originalLean = copy(f.ES.dehydrate(equip))
            noRNG(f, function()
                for pass = 1, 3 do
                    local before = copy(equip)
                    local entries = f.ES.computeModifierEntries(equip, 1.55)
                    for i, row in ipairs(raw) do
                        eq(entries[i].flat, expectedBase(row, i, #raw - 1, 31, tpl.double), tpl.id .. " 基础消费独立oracle")
                    end
                    for i, row in ipairs(savedAffixes) do
                        local wanted = curve(row.value * 2.3 + row.ascBonus, 20 * tpl.double)
                        eq(f.ES.effectiveAffixValue(equip, equip.affixes[i]), wanted, row.key .. " JSON消费只soft一次")
                        eq(entries[#raw + i].flat, wanted, row.key .. " JSON实际modifier只soft一次")
                    end
                    local lean = f.ES.dehydrate(equip)
                    check(same(equip, before), "脱水/消费不改源实例")
                    check(equivalent(lean, originalLean), "精简协议无type版本/迁移缓存字段")
                    equip = f.ES.hydrate(cjson.decode(cjson.encode(lean)))
                    check(equivalent(equip.baseStats, raw) and equivalent(equip.secondaryRoll, savedRoll), "JSON保留raw/roll/pass" .. pass)
                    for i, row in ipairs(savedAffixes) do
                        eq(equip.affixes[i].value, row.value, row.key .. " JSON不改raw")
                        eq(equip.affixes[i].ascBonus, row.ascBonus, row.key .. " JSON不裁剪旧高bonus")
                    end
                    local hydrated = copy(equip)
                    f.ES.hydrate(equip); f.ES.computeModifierEntries(equip, 1.55)
                    check(same(equip, hydrated), "重复水合/消费幂等无raw写回")
                end
            end, tpl.id .. "/" .. tostring(legacy) .. " JSON循环")
        end
    end
    -- 完整旧缓存含历史type主/副行；与精简重建分开，不要求任意手造行在脱水后仍存在。
    local cached = { templateId = "W24", level = 100, quality = 5, ascendLevel = 31, affixMult = 2.3,
        baseStats = { { "minDmgBonus", 804.1 }, { "maxDmgBonus", 12345 }, { "minDmgBonus", 0.125 } },
        affixes = { affix("minDmgBonus", 1, 25000.375) } }
    f.ES.hydrate(cached)
    local snapshot, rawRef = copy(cached), cached.baseStats
    noRNG(f, function()
        for _ = 1, 3 do
            f.ES.hydrate(cached)
            local entries = f.ES.computeModifierEntries(cached, 1.55)
            eq(entries[1].flat, curve(804.1 * 2.55, 60), "旧完整缓存type主消费")
            eq(entries[2].flat, curve(12345 * 1.8, 60), "旧完整缓存优势副消费")
            eq(entries[4].flat, curve(2.3 + 25000.375, 40), "旧完整缓存高bonus完整soft")
            check(same(cached, snapshot) and cached.baseStats == rawRef and cached.secondaryRoll == nil,
                "完整旧缓存无迁移/不补roll/不换raw引用")
        end
    end, "完整旧缓存")
end
local function testRealUAAndCF(f)
    local low = { slot = "weapon", grip = "twohand", level = 100, baseStats = {},
        affixMult = 2.5, affixes = { affix("minDmgBonus", 321.64, 0) } }
    local high = copy(low)
    high.affixes = { affix("maxDmgBonus", 321.64, 0) }
    local lowBefore, highBefore = copy(low), copy(high)
    local attrs = f.UA.create({ maxHp = 1000, magAtk = 10000 })
    local original = copy(attrs.final)
    noRNG(f, function()
        f.ES.applyToUnit(attrs, low, 1, 0); f.ES.applyToUnit(attrs, high, 2, 0)
        eq(321.64 * 2.5, 804.1, "历史完整普通词条804.1pp")
        eq(attrs:get("minDmgBonus"), 38.10448998933776, "真实UA劣势804.1->38.10449pp")
        eq(attrs:get("maxDmgBonus"), 38.10448998933776, "真实UA优势也经过来源预算")
        eq(f.CF.getMatchupDamageMult(attrs, 0.75), 1.3810448998933776, "CF实际签名返回独立乘区而非最终类型倍率")
        eq(0.75 * f.CF.getMatchupDamageMult(attrs, 0.75), 1.035783674920033, "t=.75完整倍率约1.03578")
        eq(f.CF.getMatchupDamageMult(attrs, 1), 1, "中立不吃两项")
        eq(f.CF.getMatchupDamageMult(attrs, -1), 1, "治疗不吃两项")
        eq(f.CF.getMatchupDamageMult(attrs, 0), 1, "零类型不吃两项")
        eq(1.5 * f.CF.getMatchupDamageMult(attrs, 1.5), 2.071567349840066, "优势基础倍率与优势预算独立乘一次")
    end, "真实UA/CF类型查询")
    -- 不替换random/CF：确定性私有RNG只控制固有波动；攻击无暴击/连击/格挡，检查取整前原伤。
    local matchups = {
        { atk = f.AD.ATK_FIRE, armor = f.AD.ARMOR_CLOTH, type = 0.75, expected = 10357.83674920033, label = "disadvantage" },
        { atk = f.AD.ATK_ICE, armor = f.AD.ARMOR_LIGHT, type = 1, expected = 10000, label = "neutral" },
        { atk = f.AD.ATK_LIGHTNING, armor = f.AD.ARMOR_HEAVY, type = 1.5, expected = 20715.67349840066, label = "advantage" },
    }
    for _, row in ipairs(matchups) do
        local defender = f.UA.create({ maxHp = 1000, armorType = row.armor })
        eq(f.AD.getTypeMult(row.atk, row.armor), row.type, row.label .. " 正式克制表")
        f.math.randomseed(20261024)
        local result = f.CF.calcAttack(attrs, defender, row.atk, 0)
        check(result.isHit and not result.isCrit and not result.isBlocked and result.comboCount == 0,
            row.label .. " 真实CF单次普通命中")
        check(result.matchup == row.label and #result.hits == 1, row.label .. " 真实分类/单命中")
        eq(result.hits[1].preBlockDamage, row.expected, row.label .. " 真实calcAttack原伤type一次/不作为波动端点")
        eq(result.totalDamage, math.floor(row.expected + 0.5), row.label .. " 真实CF最终取整")
        check(f.rng.calls == 3, row.label .. " 完整攻击保持命中/固有波动/暴击三次RNG")
    end
    noRNG(f, function()
        local chaos = attrs:clone()
        chaos.artifactChaosDamageMult = 2
        eq(f.CF.getMatchupDamageMult(chaos, 0.75), 1, "混沌绕过克制不吃预算结果")
        local clone = attrs:clone()
        clone:recalc()
        eq(clone:get("minDmgBonus"), 38.10448998933776, "clone/recalc不二次soft")
        f.ES.removeFromUnit(clone, 1)
        eq(clone:get("minDmgBonus"), 0, "clone卸装仅移除对应来源")
        eq(attrs:get("minDmgBonus"), 38.10448998933776, "clone卸装不污染原UA")
        f.ES.removeFromUnit(attrs, 1); f.ES.removeFromUnit(attrs, 2)
        check(same(attrs.final, original), "两件全卸恢复全部属性")
        check(same(low, lowBefore) and same(high, highBefore), "穿卸/CF不修改装备raw")
        local hero = f.UA.create({ str = 100, agi = 100, int = 100, vit = 100, luk = 100, spi = 100 })
        local derived = { physAtk = 200, magAtk = 200, physDmgBonus = 50, magDmgBonus = 50,
            armor = 115, maxHp = 5600, energyShield = 750, esBonus = 100, atkSpeed = 40,
            dodgeBonus = 10, hitValue = 40, dodge = 69, armorBonus = 50, maxDmgBonus = 50,
            critRate = 30, critDmg = 150, abnormalRes = 10, healAmount = 100, healBonus = 40 }
        for key, wanted in pairs(derived) do eq(hero.derived[key], wanted, key .. " 真实六围派生线性未soft") end
        for _, key in ipairs({ "str", "agi", "int", "vit", "luk", "spi" }) do eq(hero:get(key), 100, key .. " 六围本体不soft") end
        hero:addModifier("hero_direct", { { key = "minDmgBonus", flat = 804.1 }, { key = "maxDmgBonus", flat = 900 } })
        eq(hero:get("minDmgBonus"), 804.1, "hero直给劣势不套装备曲线")
        eq(hero:get("maxDmgBonus"), 950, "hero直给优势与LUK50不套装备曲线")
        f.ES.applyToUnit(hero, low, 3, 0)
        eq(hero:get("minDmgBonus"), 842.2044899893378, "hero原量加已soft装备，不压总属性")
        f.ES.removeFromUnit(hero, 3)
        hero:recalc()
        eq(hero:get("minDmgBonus"), 804.1, "hero卸装重算保持原量")
        eq(hero:get("maxDmgBonus"), 950, "优势英雄与派生重算保持原量")
    end, "clone/穿卸/英雄直接来源与六围")
end
function Start()
    print(PREFIX .. "start isolated whitelist / private RNG / real ES+Growth+UA+CF / no main or player save")
    for _, group in ipairs({
        { "两key两来源与单双手模板兜底", testCurve }, { "升阶预览/完整词缀/实际modifier", testEffectiveAndPreview },
        { "腐化identity与固有早返", testExclusions }, { "历史raw/VM/RNG/新旧JSON", testRawRNGAndPersistence },
        { "804.1代表值/真实CF/UA/六围/hero", testRealUAAndCF },
    }) do
        local ok, why = xpcall(function() group[2](fixture()) end, debug.traceback)
        if not ok then check(false, group[1] .. " exception: " .. tostring(why)) end
        print(PREFIX .. "完成 " .. group[1])
    end
    print(PREFIX .. "RESULT " .. (#failures == 0 and "ALL PASS" or "FAIL")
        .. " assertions=" .. checks .. " failure_count=" .. #failures)
    engine:Exit()
end
